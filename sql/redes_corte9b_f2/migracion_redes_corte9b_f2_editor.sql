begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 (presiones y alertas, sensores vacíos, usuarios sensibles y afectación del daño) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte9b_simulacion_alertas.md (Fase 2), §30.7 y §17 de la bitácora, respuestas de David del 17-nov.
-- · Presupone el paquete del 9b (1a + 1b) publicado: huella del conjunto de funciones de redes 895517fb68f74d6d6c20079c83bdf7c4.
-- · SOLO AGREGA: no reemplaza ninguna función (ni de redes ni tecnica.f_avisos). Solo base de datos: las rutas de la Edge y las pantallas son del Code B.
-- · Sin datos de personas: de un usuario sensible se guarda el contrato, el tipo y la PALABRA que coincidió (nunca el nombre).
-- =====================================================================
do $$
begin
  if to_regclass('redes.usuarios_sensibles') is not null then raise exception 'La Fase 2 del Corte 9b ya está aplicada: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '895517fb68f74d6d6c20079c83bdf7c4' then
    raise exception 'Las funciones de redes no son las del Corte 9b (1a + 1b) publicado (huella 895517fb68f74d6d6c20079c83bdf7c4): deténgase y avise';
  end if;
  if to_regclass('redes.corte_fotos') is null or to_regclass('redes.pm_nodos') is null then raise exception 'Faltan tablas del 9b (1b) o del 9a: deténgase y avise'; end if;
end $$;

-- ---------- 1. Usuarios sensibles (hospitales, clínicas, colegios…): propuesta por el nombre y confirmación del supervisor ----------
create table redes.tipos_sensible (
  codigo text primary key check (codigo ~ '^[a-z][a-z0-9_]{2,29}$'),
  nombre text not null check (length(btrim(nombre)) between 3 and 60),
  patron text not null check (length(patron) between 3 and 500),      -- expresión regular sobre el nombre en mayúsculas y sin tildes
  orden  integer not null,
  activo boolean not null default true
);
insert into redes.tipos_sensible (codigo, nombre, patron, orden) values
  ('hospital', 'Hospital', '\m(HOSPITAL|HOSPITALARIO)\M', 10),
  ('clinica', 'Clínica o centro de salud', '\m(CLINICA|CENTRO DE SALUD|PUESTO DE SALUD|UNIDAD RENAL|DIALISIS|CENTRO MEDICO)\M', 20),
  ('colegio', 'Colegio, institución educativa u hogar infantil', '\m(COLEGIO|ESCUELA|INSTITUCION EDUCATIVA|INST EDUCATIVA|JARDIN INFANTIL|HOGAR INFANTIL|CDI|UNIVERSIDAD|SENA)\M', 30),
  ('otro', 'Otro (cárcel, bomberos, policía, hogar geriátrico…)', '\m(BOMBEROS|POLICIA|CARCEL|PENITENCIARI[AO]|ANCIANATO|HOGAR GERIATRICO|ASILO|BATALLON)\M', 40),
  ('sede_propia', 'Sede de EMDUPAR', '\m(ACUEDUCTO|EMDUPAR)\M', 50);      -- David, 17-nov: las sedes propias. «IPS» y «E.S.E.» quedan fuera (muchos falsos positivos)
create table redes.usuarios_sensibles (
  contrato  text primary key check (contrato ~ '^[0-9]{1,15}$'),
  tipo      text not null references redes.tipos_sensible (codigo),
  palabra   text check (palabra is null or length(palabra) <= 60),      -- la palabra del nombre que coincidió (no el nombre)
  origen    text not null check (origen in ('nombre', 'manual')),
  autor     text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp()
);
create table redes.usuario_sensible_eventos (
  id        bigint generated always as identity primary key,
  contrato  text not null references redes.usuarios_sensibles (contrato),
  accion    text not null check (accion in ('confirmar', 'descartar')),
  tipo      text references redes.tipos_sensible (codigo),      -- al confirmar, el tipo que vale (puede corregir el propuesto)
  motivo    text check (motivo is null or length(btrim(motivo)) between 10 and 500),
  autor     text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp(),
  check ((accion = 'confirmar') = (tipo is not null)),
  check (accion <> 'descartar' or motivo is not null)
);
create index ix_sensible_eventos on redes.usuario_sensible_eventos (contrato, id desc);
comment on table redes.usuarios_sensibles is 'Corte 9b (Fase 2): contratos de usuarios sensibles (propuestos por una palabra del nombre o agregados a mano). Solo agregar; sin el nombre. El estado es su último evento.';
-- el estado vigente: por_confirmar (sin eventos), confirmado o descartado; el tipo que vale es el del último «confirmar»
create view redes.v_usuario_sensible as
select u.contrato, coalesce(e.tipo, u.tipo) as tipo, u.palabra, u.origen,
       case e.accion when 'confirmar' then 'confirmado' when 'descartar' then 'descartado' else 'por_confirmar' end as estado, coalesce(e.creado_en, u.creado_en) as desde
  from redes.usuarios_sensibles u
  left join lateral (select x.accion, x.tipo, x.creado_en from redes.usuario_sensible_eventos x where x.contrato = u.contrato order by x.id desc limit 1) e on true;
revoke all on table redes.v_usuario_sensible from public, anon, authenticated, service_role;

-- ---------- 2. Presión de trabajo por material y clase (§30.7; para la alerta por material). «por_verificar»: falta la ficha del fabricante ----------
create table redes.presion_trabajo (
  id              bigint generated always as identity primary key,
  material_codigo text not null references redes.materiales (codigo),
  clase           text check (clase is null or length(btrim(clase)) between 1 and 40),      -- p. ej. «RDE 21»; nula: la que se usa si el tramo no dice su clase
  presion_mca     numeric not null check (presion_mca > 0 and presion_mca <= 1000),
  fuente          text not null check (length(btrim(fuente)) between 3 and 200),
  por_verificar   boolean not null default true,
  creado_en       timestamptz not null default clock_timestamp()
);
create unique index ux_presion_trabajo on redes.presion_trabajo (material_codigo, coalesce(clase, ''));
insert into redes.presion_trabajo (material_codigo, clase, presion_mca, fuente)
select m.codigo, x.clase, x.p, x.fuente from redes.materiales m
  join (values ('RDE 21', 140, 'PVC RDE 21 = 200 psi (§30.7; por verificar con Técnica)'), ('RDE 26', 112, 'PVC RDE 26 = 160 psi (§30.7; por verificar con Técnica)'),
               ('RDE 32,5', 88, 'PVC RDE 32,5 = 125 psi (§30.7; por verificar con Técnica)'),
               (null, 88, 'PVC sin clase en la ficha: se toma la menor (RDE 32,5 = 125 psi; por verificar con Técnica)')) x(clase, p, fuente) on m.codigo = 'PVC';
comment on table redes.presion_trabajo is 'Corte 9b (Fase 2): presión de trabajo por material y clase del tubo, para la alerta por material. Valores por verificar con la ficha del fabricante.';

-- ---------- 3. Lecturas de sensores: queda VACÍA (los sensores son activos SEN; «por conectar» mientras no haya lecturas). Sin ruta de escritura en la fase 1 ----------
create table redes.sensor_lecturas (
  id          bigint generated always as identity primary key,
  activo_id   bigint not null references redes.activos (id),
  variable    text not null check (variable in ('presion', 'caudal', 'nivel', 'cloro')),
  valor       numeric not null check (valor::text not in ('NaN', 'Infinity', '-Infinity')),
  unidad      text not null check (length(unidad) between 1 and 20),
  medido_en   timestamptz not null,
  fuente      text not null check (length(btrim(fuente)) between 2 and 80),
  recibido_en timestamptz not null default clock_timestamp()
);
create index ix_sensor_lecturas on redes.sensor_lecturas (activo_id, medido_en desc);
comment on table redes.sensor_lecturas is 'Corte 9b (Fase 2): lecturas de sensores (activos SEN). Solo agregar. Vacía: la conexión del SCADA está fuera de la fase 1.';

do $$
declare t text;
begin
  foreach t in array array['tipos_sensible', 'usuarios_sensibles', 'usuario_sensible_eventos', 'presion_trabajo', 'sensor_lecturas'] loop
    execute format('alter table redes.%I enable row level security', t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', t);
  end loop;
  foreach t in array array['usuarios_sensibles', 'usuario_sensible_eventos', 'sensor_lecturas'] loop
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
end $$;

-- ---------- 4. Parámetros ----------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('sensor_sin_senal_min', 60, 'minutos', 5, 10080,
   'Sensores (Corte 9b): minutos sin lecturas desde los que un sensor conectado sale «sin señal»'),
  ('presion_lista_max', 50, 'nodos', 5, 500,
   'Alertas de presión (Corte 9b): cuántos nodos se listan como máximo por cada nivel (los peores primero); el total siempre se dice')
on conflict (clave) do update set estado = 'vigente', descripcion = excluded.descripcion;

-- ---------- 5. La capa «Cortes programados vigentes» se OCULTA de la lista de capas (David, 17-nov): ahora vive en el modo «Afectaciones». No se borra ----------
update redes.geovisor_capas set activa = false, nota = 'Oculta el 17-nov-2026 (Corte 9b): los cortes vigentes se ven en el modo «Afectaciones» del geovisor'
 where codigo = 'cortes';
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 20 — FUNCIONES INTERNAS. PROPUESTA. Solo agrega (no reemplaza nada).
-- · Alertas de presión (§30.7, Res. 0330 de 2017, arts. 61 y 62): con los 4 parámetros del 9a (15 y 10 m.c.a. de mínima; 50 y 60 de máxima) sobre la presión
--   de MODELO por nodo (redes.pm_nodos, carga vigente; red existente o futura). Y por material: nodos cuya presión máxima pasa la presión de trabajo de un tramo
--   que llega a ellos. Es presión de modelo, no medida: así se rotula.
-- · Usuarios sensibles: propuesta por una palabra del nombre (cartera_suscripcion, último período) — se corre por psql o editor, NUNCA en una petición.
-- · Afectación de un daño o una intervención: contratos sin agua y usuarios sensibles, del cierre real (la foto) si tiene válvulas cerradas, o de la simulación.
-- · Sensores: estado derivado de las lecturas («por conectar» mientras no haya).
-- =====================================================================

-- ---------- nivel de alerta de un nodo por su presión mínima y máxima del día (nulo: en rango). La baja manda sobre la alta; el rojo sobre el naranja ----------
create function redes.f_presion_nivel(p_min numeric, p_max numeric) returns text
language sql stable set search_path = redes, pg_temp as $$
  select case when p_min < redes.f_param('presion_baja_roja_mca') then 'baja_roja'
              when p_max > redes.f_param('presion_alta_roja_mca') then 'alta_roja'
              when p_min < redes.f_param('presion_baja_naranja_mca') then 'baja_naranja'
              when p_max > redes.f_param('presion_alta_naranja_mca') then 'alta_naranja' end $$;

-- ---------- las alertas de presión de un escenario (existente | futura): conteos por nivel, los peores nodos y la alerta por material ----------
create function redes.f_alertas_presion(p_escenario text) returns jsonb
language plpgsql stable security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_c bigint := redes.f_ref_vigente('pm_nodos'); v_lim integer := coalesce(redes.f_param('presion_lista_max'), 50)::integer; v_fut boolean := p_escenario = 'futura'; j jsonb;
  -- los 4 umbrales se leen UNA vez (la misma regla de redes.f_presion_nivel; por nodo costaba 4 lecturas de parámetros)
  v_bn numeric := redes.f_param('presion_baja_naranja_mca'); v_br numeric := redes.f_param('presion_baja_roja_mca');
  v_an numeric := redes.f_param('presion_alta_naranja_mca'); v_ar numeric := redes.f_param('presion_alta_roja_mca');
begin
  if p_escenario not in ('existente', 'futura') then perform tecnica.f_error('El escenario es «existente» o «futura»'); end if;
  if v_c is null then return jsonb_build_object('cargado', false, 'escenario', p_escenario); end if;
  with n as (
    select x.llave, coalesce(x.nombre, x.llave) as nombre, x.zona_modelo, x.geom,
           case when v_fut then x.pres_futura_min else x.pres_exist_min end as p_min, case when v_fut then x.pres_futura_max else x.pres_exist_max end as p_max
      from redes.pm_nodos x where x.carga_id = v_c),
  c as materialized (select n.*, case when n.p_min < v_br then 'baja_roja' when n.p_max > v_ar then 'alta_roja' when n.p_min < v_bn then 'baja_naranja' when n.p_max > v_an then 'alta_naranja' end as nivel
          from n where n.p_min is not null or n.p_max is not null),
  -- por material: el tramo de menor presión de trabajo que llega al nodo (el nodo de la red se amarra por la llave del modelo)
  m as (
    select c.llave, c.nombre, c.p_max, c.geom, min(pt.presion_mca) as trabajo, (array_agg(t.codigo order by pt.presion_mca, t.codigo))[1] as tramo,
           (array_agg(t.material_codigo order by pt.presion_mca, t.codigo))[1] as material
      from c join redes.nodos nd on nd.sistema = 'acueducto' and nd.llave_modelo = c.llave
      join redes.tramo_nodos tn on nd.id in (tn.nodo_ini, tn.nodo_fin)
      join redes.activo_vigente_mat t on t.activo_id = tn.activo_id and t.version = tn.version and t.cuenta_vigente and not t.retirado
      join redes.presion_trabajo pt on pt.material_codigo = t.material_codigo and coalesce(pt.clase, '') = coalesce(t.clase, '')
     where c.p_max > (select min(presion_mca) from redes.presion_trabajo) group by c.llave, c.nombre, c.p_max, c.geom having c.p_max > min(pt.presion_mca))
  select jsonb_build_object(
    'cargado', true, 'escenario', p_escenario, 'fuente', (select origen from redes.ref_cargas where id = v_c),
    'aviso', 'Presión de MODELO, no medida.',
    'umbrales', jsonb_build_object('baja_naranja', v_bn, 'baja_roja', v_br, 'alta_naranja', v_an, 'alta_roja', v_ar),
    'nodos', (select count(*) from c),
    'niveles', (select coalesce(jsonb_object_agg(g.nivel, g.n), '{}') from (select c.nivel, count(*) as n from c where c.nivel is not null group by 1) g),
    'peores', (select coalesce(jsonb_agg(jsonb_build_object('nodo', w.nombre, 'nivel', w.nivel, 'p_min', w.p_min, 'p_max', w.p_max, 'zona', w.zona_modelo,
                                                           'lat', round(ST_Y(w.geom)::numeric, 6), 'lon', round(ST_X(w.geom)::numeric, 6)) order by w.nivel, w.o), '[]')
                 from (select c.*, row_number() over (partition by c.nivel order by case when c.nivel like 'baja%' then c.p_min else -c.p_max end, c.llave) as o
                         from c where c.nivel is not null) w where w.o <= v_lim),
    'por_material', jsonb_build_object('n', (select count(*) from m),
      'nodos', (select coalesce(jsonb_agg(jsonb_build_object('nodo', y.nombre, 'p_max', y.p_max, 'presion_trabajo', y.trabajo, 'tramo', y.tramo, 'material', y.material,
                                                            'lat', round(ST_Y(y.geom)::numeric, 6), 'lon', round(ST_X(y.geom)::numeric, 6)) order by y.exceso desc, y.llave), '[]')
                  from (select m.*, m.p_max - m.trabajo as exceso from m order by m.p_max - m.trabajo desc, m.llave limit v_lim) y),
      'nota', 'Presión de trabajo por material y clase: por verificar con la ficha del fabricante.'))
    into j;
  return j;
end $$;
comment on function redes.f_alertas_presion(text) is 'Corte 9b (Fase 2): alertas de presión de modelo por nodo (Res. 0330 de 2017; 4 parámetros editables) y por material. Lectura.';

-- ---------- lista para los Avisos del 12 (NO está conectada: sumarla pide un bloque en tecnica.f_avisos, que no se toca sin avisar) ----------
create function redes.f_presion_para_avisos() returns table (nivel text, n bigint)
language sql stable security definer set search_path = redes, pg_temp as $$
  select redes.f_presion_nivel(x.pres_exist_min, x.pres_exist_max), count(*)
    from redes.pm_nodos x where x.carga_id = redes.f_ref_vigente('pm_nodos') and redes.f_presion_nivel(x.pres_exist_min, x.pres_exist_max) is not null group by 1 $$;

-- ---------- el tipo de usuario sensible que sugiere un nombre (y la palabra que coincidió); sin filas si no sugiere ninguno ----------
create function redes.f_sensible_tipo(p_nombre text) returns table (tipo text, palabra text)
language sql stable security definer set search_path = redes, pg_temp as $$
  select x.codigo, left((regexp_match(n.nom, x.patron))[1], 60)
    from (select upper(translate(coalesce(p_nombre, ''), 'ÁÉÍÓÚÜáéíóúü', 'AEIOUUaeiouu')) as nom) n      -- primero sin tildes: con configuración regional «C», upper() no cambia las vocales con tilde
    join redes.tipos_sensible x on x.activo and n.nom ~ x.patron order by x.orden limit 1 $$;

-- ---------- propone usuarios sensibles por una palabra del nombre (último período de la cartera). Recorre la cartera: se corre por psql o editor, no en peticiones ----------
create function redes.f_sensibles_proponer(p_autor text) returns integer
language plpgsql volatile security definer set search_path = redes, public, pg_temp as $$
declare v_n integer; v_autor text := lower(btrim(coalesce(p_autor, '')));
begin
  if not public.geoportal_es_admin(v_autor) then raise exception 'Ese correo no es de un administrador' using errcode = '42501'; end if;
  insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor)
  select s.contrato, t.tipo, t.palabra, 'nombre', v_autor
    from (select distinct on (c.contrato) c.contrato, c.nombre
            from public.cartera_suscripcion c where c.contrato ~ '^[0-9]{1,15}$' and c.contrato not in ('0', '99999999')
           order by c.contrato, c.periodo_carga desc nulls last) s
    cross join lateral redes.f_sensible_tipo(s.nombre) t
  on conflict (contrato) do nothing;
  get diagnostics v_n = row_count;
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values (v_autor, 'redes_sensibles_proponer', null, jsonb_build_object('nuevos', v_n), null);
  return v_n;
end $$;
comment on function redes.f_sensibles_proponer(text) is 'Corte 9b (Fase 2): propone usuarios sensibles por una palabra del nombre. Guarda contrato, tipo y la palabra; nunca el nombre. Solo por psql o editor (recorre la cartera).';

-- ---------- los usuarios sensibles entre unos contratos: confirmados y por confirmar (los descartados no) ----------
create function redes.f_sensibles_en(p_contratos text[]) returns jsonb
language sql stable security definer set search_path = redes, pg_temp as $$
  select jsonb_build_object(
    'confirmados', count(*) filter (where v.estado = 'confirmado'), 'por_confirmar', count(*) filter (where v.estado = 'por_confirmar'),
    'lista', coalesce(jsonb_agg(jsonb_build_object('contrato', v.contrato, 'tipo', t.nombre, 'tipo_codigo', v.tipo, 'estado', v.estado) order by t.orden, v.contrato), '[]'))
    from redes.v_usuario_sensible v join redes.tipos_sensible t on t.codigo = v.tipo
   where v.contrato = any (p_contratos) and v.estado <> 'descartado' $$;

-- ---------- el estado de un sensor (activo SEN): por conectar (sin lecturas), en línea o sin señal ----------
create function redes.f_sensor_estado(p_activo bigint) returns text
language sql stable security definer set search_path = redes, pg_temp as $$
  select case when u.medido_en is null then 'por_conectar'
              when u.medido_en >= clock_timestamp() - make_interval(mins => coalesce(redes.f_param('sensor_sin_senal_min'), 60)::integer) then 'en_linea' else 'sin_senal' end
    from (select max(l.medido_en) as medido_en from redes.sensor_lecturas l where l.activo_id = p_activo) u $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 26 — RPC (las llamará la Edge geoportal-redes; las rutas y las pantallas son del Code B).
--   · geoportal_redes_alertas_presion: alertas de presión de modelo (supervisor y administrador).
--   · geoportal_redes_sensibles / geoportal_redes_sensible_fijar: bandeja de usuarios sensibles; el supervisor confirma, descarta o agrega uno a mano.
--   · geoportal_redes_afectacion: contratos sin agua y usuarios sensibles de un daño o una intervención (cierre real si lo hay; si no, simulación).
--   · geoportal_redes_sensores: los sensores (activos SEN) con su estado («por conectar» sin lecturas).
-- Sin nombres ni teléfonos: contrato, tipo y conteos.
-- =====================================================================
create function public.geoportal_redes_alertas_presion(p_solicitante text, p_escenario text default 'existente')
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven las alertas de presión');
begin
  return redes.f_alertas_presion(coalesce(p_escenario, 'existente'));
end $$;

create function public.geoportal_redes_sensibles(p_solicitante text, p_estado text default null, p_despues_de text default null, p_limite integer default 100)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven los usuarios sensibles'); v_lim integer := coalesce(p_limite, 100); v_items jsonb;
begin
  if v_lim < 1 or v_lim > 500 then perform tecnica.f_error('Se piden de 1 a 500'); end if;
  if p_estado is not null and p_estado not in ('por_confirmar', 'confirmado', 'descartado') then perform tecnica.f_error('Ese estado no existe'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('contrato', x.contrato, 'tipo', x.tipo, 'tipo_nombre', x.nombre, 'palabra', x.palabra, 'origen', x.origen, 'estado', x.estado,
                                               'desde', x.desde, 'tramo', x.tramo, 'lat', x.lat, 'lon', x.lon) order by x.contrato), '[]') into v_items
    from (select v.*, t.nombre, (select a.codigo from redes.contrato_tramo ct join redes.activos a on a.id = ct.activo_id where ct.contrato = v.contrato) as tramo,
                 (select round(ST_Y(c.geom)::numeric, 6) from public.catastro_valledupar c where c.cod_usuario = v.contrato and c.geom is not null order by c.id limit 1) as lat,
                 (select round(ST_X(c.geom)::numeric, 6) from public.catastro_valledupar c where c.cod_usuario = v.contrato and c.geom is not null order by c.id limit 1) as lon
            from redes.v_usuario_sensible v join redes.tipos_sensible t on t.codigo = v.tipo
           where (p_estado is null or v.estado = p_estado) and (p_despues_de is null or v.contrato > p_despues_de)
           order by v.contrato limit v_lim) x;
  return jsonb_build_object(
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre) order by t.orden) from redes.tipos_sensible t where t.activo),
    'totales', (select coalesce(jsonb_object_agg(g.estado, g.n), '{}') from (select v.estado, count(*) as n from redes.v_usuario_sensible v group by 1) g),
    'items', v_items, 'siguiente', case when jsonb_array_length(v_items) = v_lim then v_items -> (v_lim - 1) ->> 'contrato' end);
end $$;

create function public.geoportal_redes_sensible_fijar(p_solicitante text, p_contrato text, p_accion text, p_tipo text default null, p_motivo text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'confirman los usuarios sensibles'); v_c text := btrim(coalesce(p_contrato, '')); v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
        u redes.v_usuario_sensible%rowtype; v_tipo text; v_nuevo text;
begin
  if v_c !~ '^[0-9]{1,15}$' then perform tecnica.f_error('Escriba el número del contrato'); end if;
  if coalesce(p_accion, '') not in ('confirmar', 'descartar') then perform tecnica.f_error('Elija: confirmar o descartar'); end if;
  if p_tipo is not null and not exists (select 1 from redes.tipos_sensible where codigo = p_tipo and activo) then perform tecnica.f_error('Ese tipo no existe'); end if;
  select * into u from redes.v_usuario_sensible where contrato = v_c;
  if not found then
    -- agregar uno a mano: solo confirmando, con su tipo y un motivo, y si el contrato está en el catastro
    if p_accion <> 'confirmar' or p_tipo is null or v_mot is null or length(v_mot) < 10 then perform tecnica.f_error('Ese contrato no está en la lista: para agregarlo, confirme con el tipo y el motivo (al menos 10 letras)'); end if;
    if not exists (select 1 from public.catastro_valledupar c where c.cod_usuario = v_c) then perform tecnica.f_error(format('El contrato %s no está en el catastro', v_c), 'P0002'); end if;
    insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor) values (v_c, p_tipo, null, 'manual', v_email);
  end if;
  if p_accion = 'descartar' and (v_mot is null or length(v_mot) < 10) then perform tecnica.f_error('Para descartar, escriba el motivo (al menos 10 letras)'); end if;
  v_tipo := case when p_accion = 'confirmar' then coalesce(p_tipo, u.tipo) end;
  v_nuevo := case p_accion when 'confirmar' then 'confirmado' else 'descartado' end;      -- (fuera del «if»: un «case … then» dentro de la condición la corta)
  if u.estado = v_nuevo and u.tipo is not distinct from coalesce(v_tipo, u.tipo) then
    return jsonb_build_object('contrato', v_c, 'estado', u.estado, 'tipo', u.tipo, 'cambio', false);
  end if;
  insert into redes.usuario_sensible_eventos (contrato, accion, tipo, motivo, autor) values (v_c, p_accion, v_tipo, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_sensible_' || p_accion, v_c, jsonb_build_object('tipo', v_tipo, 'motivo', v_mot), null);
  return jsonb_build_object('contrato', v_c, 'estado', case p_accion when 'confirmar' then 'confirmado' else 'descartado' end, 'tipo', v_tipo, 'cambio', true);
end $$;

-- contratos sin agua y usuarios sensibles de un daño o una intervención. Con válvulas cerradas vigentes de ese registro: lo real (la última foto, sin recalcular);
-- si no: la simulación sobre su activo (o el tramo más cercano a su punto). Volátil por la simulación (tablas temporales).
create function public.geoportal_redes_afectacion(p_solicitante text, p_registro text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare
  v_email text := redes.f_sim_autorizar(p_solicitante); v_cod text := upper(btrim(coalesce(p_registro, '')));
  v_dano uuid; v_itv uuid; v_act bigint; v_sis text; v_lat numeric; v_lon numeric; v_foto bigint; v_zonas integer[]; v_con text[]; j jsonb;
begin
  if v_cod ~ '^DAN-[0-9]{6}$' then select d.id, d.activo_id, d.sistema, d.lat, d.lon into v_dano, v_act, v_sis, v_lat, v_lon from redes.danos d where d.codigo = v_cod;
  elsif v_cod ~ '^ITV-[0-9]{6}$' then select i.id, i.activo_id, i.sistema, i.lat, i.lon into v_itv, v_act, v_sis, v_lat, v_lon from redes.intervenciones i where i.codigo = v_cod;
  else perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
  end if;
  if v_dano is null and v_itv is null then perform tecnica.f_error(format('No hay ningún daño ni intervención con el código «%s»', v_cod), 'P0002'); end if;
  if v_sis <> 'acueducto' then perform tecnica.f_error('La afectación por cierre es solo para acueducto'); end if;
  select max(id) into v_foto from redes.corte_fotos;
  select array_agg(distinct fv.zona) filter (where fv.zona is not null) into v_zonas
    from redes.f_cierres_vigentes() c join redes.corte_foto_valvulas fv on fv.foto_id = v_foto and fv.cierre_id = c.cierre_id
   where c.dano_id = v_dano or c.intervencion_id = v_itv;
  if exists (select 1 from redes.f_cierres_vigentes() c where c.dano_id = v_dano or c.intervencion_id = v_itv) then
    select coalesce(array_agg(distinct ct.contrato), '{}') into v_con
      from redes.corte_foto_tramos ft join redes.contrato_tramo ct on ct.activo_id = ft.activo_id where ft.foto_id = v_foto and ft.zona = any (coalesce(v_zonas, '{}'));
    return jsonb_build_object('registro', v_cod, 'fuente', 'cierre_real', 'texto', 'Según las válvulas cerradas en este momento',
      'valvulas_cerradas', (select count(*) from redes.f_cierres_vigentes() c where c.dano_id = v_dano or c.intervencion_id = v_itv),
      'zonas', coalesce(cardinality(v_zonas), 0), 'contratos', cardinality(v_con), 'contratos_min', cardinality(v_con), 'contratos_max', cardinality(v_con),
      'sensibles', redes.f_sensibles_en(v_con));
  end if;
  j := redes.f_simular_cierre(coalesce(v_act, redes.f_sim_tramo_cercano(v_lat, v_lon)));
  return jsonb_build_object('registro', v_cod, 'fuente', 'simulacion', 'texto', 'Propuesta según la simulación de cierre (todavía no hay válvulas cerradas)',
    'activo', j -> 'activo' ->> 'codigo', 'valvulas_a_cerrar', j -> 'estrecho' -> 'valvulas_total', 'segmento_grande', j -> 'segmento_grande',
    'contratos_min', j -> 'contratos_min', 'contratos_max', j -> 'contratos_max',
    -- los sensibles del escenario estrecho (el número menor); si el sector es tan grande que no se listan los contratos, no se calculan
    'sensibles', case when jsonb_typeof(j -> '_contratos') = 'array' then redes.f_sensibles_en(array(select jsonb_array_elements_text(j -> '_contratos'))) end);
end $$;

create function public.geoportal_redes_sensores(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  return jsonb_build_object('sensores', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', coalesce(m.nombre, m.codigo), 'tipo', redes.f_tipo_nombre(m.prefijo), 'estado', redes.f_sensor_estado(m.activo_id),
                                        'lat', round(ST_Y(ST_PointOnSurface(m.geom))::numeric, 6), 'lon', round(ST_X(ST_PointOnSurface(m.geom))::numeric, 6),
                                        'ultima', (select jsonb_build_object('variable', l.variable, 'valor', l.valor, 'unidad', l.unidad, 'medido_en', l.medido_en)
                                                     from redes.sensor_lecturas l where l.activo_id = m.activo_id order by l.medido_en desc limit 1)) order by m.codigo)
      from redes.activo_vigente_mat m where m.prefijo in ('SEN', 'SCA') and not m.retirado and not m.oculto), '[]'::jsonb),
    'nota', 'Los sensores sin lecturas están «por conectar»: todavía no envían datos.');
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las 7 funciones internas: nadie de la API. Las 5 RPC: solo service_role (la Edge geoportal-redes). Las tablas y la vista: nadie de la API (10_esquema.sql).
-- =====================================================================
revoke all on function redes.f_presion_nivel(numeric, numeric), redes.f_alertas_presion(text), redes.f_presion_para_avisos(), redes.f_sensible_tipo(text), redes.f_sensibles_proponer(text),
                       redes.f_sensibles_en(text[]), redes.f_sensor_estado(bigint)
  from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_alertas_presion', 'geoportal_redes_sensibles', 'geoportal_redes_sensible_fijar',
                     'geoportal_redes_afectacion', 'geoportal_redes_sensores') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9b_f2', 'migracion_redes_corte9b_fase2', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.tipos_sensible', 'redes.usuarios_sensibles', 'redes.usuario_sensible_eventos', 'redes.presion_trabajo', 'redes.sensor_lecturas'),
        'vistas', jsonb_build_array('redes.v_usuario_sensible'),
        'nuevas', jsonb_build_array('redes.f_presion_nivel', 'redes.f_alertas_presion', 'redes.f_presion_para_avisos', 'redes.f_sensible_tipo', 'redes.f_sensibles_proponer', 'redes.f_sensibles_en',
                                    'redes.f_sensor_estado', 'geoportal_redes_alertas_presion', 'geoportal_redes_sensibles', 'geoportal_redes_sensible_fijar',
                                    'geoportal_redes_afectacion', 'geoportal_redes_sensores'),
        'parametros', jsonb_build_array('sensor_sin_senal_min', 'presion_lista_max'),
        'capa_oculta', 'cortes',
        'motivo', 'alertas de presión de modelo (Res. 0330 de 2017), usuarios sensibles, afectación del daño o la intervención, lecturas de sensores (vacía) y la capa de cortes oculta (vive en el modo Afectaciones)'), null);
commit;
