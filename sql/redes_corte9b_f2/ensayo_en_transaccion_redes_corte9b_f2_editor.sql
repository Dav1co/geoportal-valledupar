begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 (presiones y alertas, sensores vacíos, usuarios sensibles y afectación del daño) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte9b_simulacion_alertas.md (Fase 2), §30.7 y §17 de la bitácora, respuestas de David del 17-nov.
-- · Presupone el paquete del 9b (1a + 1b) publicado: huella del conjunto de funciones de redes 895517fb68f74d6d6c20079c83bdf7c4.
-- · No reemplaza ninguna función de redes. Reemplaza UNA de tecnica: tecnica.f_avisos (del 9b 1b, md5 898bafa5adddfcc08d65adf138d0114a), para sumar el aviso informativo
--   de presiones (David, 17-nov). Solo base de datos: las rutas de la Edge y las pantallas son del Code B.
-- · Sin datos de personas: de un usuario sensible se guarda el contrato, el tipo y la PALABRA que coincidió (nunca el nombre).
-- =====================================================================
do $$
begin
  if to_regclass('redes.usuarios_sensibles') is not null then raise exception 'La Fase 2 del Corte 9b ya está aplicada: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '895517fb68f74d6d6c20079c83bdf7c4' then
    raise exception 'Las funciones de redes no son las del Corte 9b (1a + 1b) publicado (huella 895517fb68f74d6d6c20079c83bdf7c4): deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) <> '898bafa5adddfcc08d65adf138d0114a' then
    raise exception 'tecnica.f_avisos no es la publicada con el Corte 9b (1b) (md5 898bafa5adddfcc08d65adf138d0114a): deténgase y avise';
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
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 25 — REEMPLAZO (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- tecnica.f_avisos, con su texto vivo (el publicado con el 9b 1a + 1b, md5 898bafa5adddfcc08d65adf138d0114a) más UN bloque: D11, el aviso informativo
-- «N nodos fuera de rango según el modelo» (David, 17-nov: ni rojo ni naranja). Lo demás queda igual. AVISADO al Code B en la entrada de bitácora.
-- =====================================================================

-- tecnica.f_avisos(boolean,boolean,timestamp with time zone)
CREATE OR REPLACE FUNCTION tecnica.f_avisos(p_planta boolean, p_distribucion boolean, p_ahora timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'redes', 'extensions', 'pg_temp'
AS $function$
declare
  v_ahora timestamptz := coalesce(p_ahora, clock_timestamp());
  v_loc timestamp := coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota';
  v_hoy date := (coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota')::date;
  v_h numeric := extract(hour from (coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota')) + extract(minute from (coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota')) / 60.0;
  v_av jsonb := '[]'::jsonb;
  r record; v_n bigint; v_items jsonb; v_items2 jsonb; v_dz jsonb; v_desde timestamptz; v_dias integer; v_x numeric; v_y numeric; v_z numeric;
  v_ini numeric; v_fin numeric; v_primer numeric; v_sin numeric;
begin
  -- ===================== PLANTAS =====================
  if p_planta then
    v_ini := tecnica.f_aparam('horario_inicio'); v_fin := tecnica.f_aparam('horario_fin');
    v_primer := tecnica.f_aparam('planta_primer_registro_hora'); v_sin := tecnica.f_aparam('planta_horas_sin_registro');
    -- P1. Entrada y Salida sin registrar hoy, por planta, dentro del horario del personal (8 a. m. a 6 p. m.)
    if v_h >= greatest(v_ini, v_primer) then
      for r in select p.codigo, p.nombre, f.form, f.titulo, f.ord,
                      (select max(x.muestra_ts) from tecnica.v_registros_estado x
                        where x.formulario::text = f.form and x.planta_id = p.id and x.fecha_muestra = v_hoy and not x.excluido and x.muestra_ts <= v_ahora) as ultimo
                 from tecnica.plantas p cross join (values ('entrada', 'Entrada', 1), ('salida', 'Salida', 2)) f(form, titulo, ord)
                where p.activa order by p.id, f.ord loop
        if r.ultimo is null and v_h >= v_fin then
          v_av := v_av || jsonb_build_object('clave', 'planta_' || r.form || ':' || r.codigo, 'area', 'planta', 'nivel', 'rojo', 'orden', 10 + r.ord,
                    'titulo', format('%s sin registros hoy en %s', r.titulo, r.nombre), 'detalle', 'Cerró el horario del personal sin ningún registro del día.',
                    'n', 1, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'registros'), 'desde', null);
        elsif r.ultimo is null and v_h < v_fin then
          v_av := v_av || jsonb_build_object('clave', 'planta_' || r.form || ':' || r.codigo, 'area', 'planta', 'nivel', 'naranja', 'orden', 10 + r.ord,
                    'titulo', format('%s sin el primer registro del día en %s', r.titulo, r.nombre),
                    'detalle', format('Ningún registro hoy; el primero se espera antes de las %s:00.', v_primer),
                    'n', 1, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'registros'), 'desde', null);
        elsif r.ultimo is not null and v_h < v_fin and v_ahora - r.ultimo > make_interval(secs => (v_sin * 3600)::double precision) then
          v_av := v_av || jsonb_build_object('clave', 'planta_' || r.form || ':' || r.codigo, 'area', 'planta', 'nivel', 'naranja', 'orden', 10 + r.ord,
                    'titulo', format('%s sin registro hace %s en %s', r.titulo, tecnica.f_texto_horas(extract(epoch from v_ahora - r.ultimo)::numeric / 3600), r.nombre),
                    'detalle', format('El último registro de hoy fue a las %s.', to_char(r.ultimo at time zone 'America/Bogota', 'HH24:MI')),
                    'n', 1, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'registros'), 'desde', r.ultimo);
        end if;
      end loop;
    end if;

    -- P2. Puntos de muestreo sin muestra en los últimos días (el mismo parámetro del geovisor: geovisor_muestreo_dias, 35)
    v_dias := floor(redes.f_param('geovisor_muestreo_dias'))::integer;
    select count(*), coalesce(jsonb_agg(s.codigo || ' · ' || s.nombre order by s.o, s.codigo) filter (where s.rn <= 5), '[]'::jsonb) into v_n, v_items
      from (select p.codigo, p.nombre, coalesce(p.orden, 999999) as o, row_number() over (order by coalesce(p.orden, 999999), p.codigo) as rn
              from tecnica.puntos p
             where p.tipo = 'muestreo' and p.activo
               and p.id not in (select x.punto_id from tecnica.v_registros_estado x
                                 where x.formulario::text = 'muestreo' and x.punto_id is not null and not x.excluido
                                   and x.muestra_ts >= v_ahora - make_interval(days => v_dias) and x.muestra_ts <= v_ahora)) s;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'muestreo_sin_muestra', 'area', 'planta', 'nivel', 'naranja', 'orden', 20,
                'titulo', format('%s sin muestra en %s días', tecnica.f_cuantos(v_n, 'punto de muestreo', 'puntos de muestreo'), v_dias), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'puntos'), 'desde', null);
    end if;

    -- P3. Último cloro o última turbiedad fuera de rango (la misma calidad que pinta el geovisor: redes.f_muestreo_calidad)
    select count(*), coalesce(jsonb_agg(s.txt order by s.o, s.codigo) filter (where s.rn <= 5), '[]'::jsonb) into v_n, v_items
      from (select c.codigo, c.o, row_number() over (order by c.o, c.codigo) as rn,
                   c.codigo || ' · ' || (select string_agg(format('%s %s %s', m ->> 'nombre', tecnica.f_texto_num((m ->> 'valor')::numeric), coalesce(m ->> 'unidad', '')), ', ')
                                           from jsonb_array_elements(c.cal -> 'medidas') m where (m ->> 'reciente')::boolean and (m ->> 'dentro')::boolean is false) as txt
              from (select p.codigo, coalesce(p.orden, 999999) as o, redes.f_muestreo_calidad(p.id) as cal from tecnica.puntos p where p.tipo = 'muestreo' and p.activo) c
             where c.cal ->> 'calidad' = 'fuera') s;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'muestreo_fuera_rango', 'area', 'planta', 'nivel', 'rojo', 'orden', 21,
                'titulo', format('%s con el último cloro o la última turbiedad fuera de rango', tecnica.f_cuantos(v_n, 'punto', 'puntos')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'eventos'), 'desde', null);
    end if;

    -- P4. Químicos: días con dosis y caudal sin uso, y desvío de esperado contra usado (los últimos días cerrados, hasta ayer; la misma cuenta del Corte 7a)
    v_dias := floor(tecnica.f_aparam('quimicos_dias_revisar'))::integer;
    v_x := tecnica.f_qparam('desvio_pct');
    with filas as (
      select d.dia, p.nombre as planta, v.nombre as quimico, qi.qi,
             coalesce((select m.dosis_optima_ppm from tecnica.quimico_movimientos m where m.tipo = 'uso' and m.para_que = 'dosificacion' and m.quimico_id = v.quimico_id
                        and m.planta_id = p.id and m.dia = d.dia and m.dosis_optima_ppm is not null order by m.id desc limit 1),
                      tecnica.f_dosis_optima_en(v.quimico_id, ((d.dia + 1)::timestamp at time zone 'America/Bogota'))) as dosis,
             coalesce((select -sum(m.cantidad_kg) from tecnica.quimico_movimientos m where m.tipo = 'uso' and m.para_que = 'dosificacion' and m.quimico_id = v.quimico_id
                        and m.planta_id = p.id and m.dia = d.dia), 0) as usado
        from generate_series(v_hoy - v_dias, v_hoy - 1, interval '1 day') d0(t) cross join lateral (select d0.t::date as dia) d
        cross join tecnica.plantas p cross join tecnica.v_quimico_vigente v
        cross join lateral (select avg(r2.valor) as qi from tecnica.v_registros_estado r2
                             where r2.formulario::text = 'entrada' and r2.planta_id = p.id and r2.fecha_muestra = d.dia and not r2.excluido
                               and r2.variable_id = (select id from tecnica.variables where codigo = 'caudal_qi')) qi
       where p.activa and v.potabilizacion and v.activo and qi.qi is not null),
    calc as (select f.*, f.dosis * f.qi * 86.4 / 1000 as esperado from filas f where f.dosis is not null)
    select count(*) filter (where c.esperado > 0 and c.usado = 0),
           coalesce(jsonb_agg(to_char(c.dia, 'DD/MM') || ' · ' || c.planta || ' · ' || c.quimico order by c.dia desc, c.planta, c.quimico) filter (where c.esperado > 0 and c.usado = 0), '[]'::jsonb),
           count(*) filter (where c.esperado > 0 and c.usado > 0 and abs(c.usado - c.esperado) > c.esperado * v_x / 100),
           coalesce(jsonb_agg(to_char(c.dia, 'DD/MM') || ' · ' || c.planta || ' · ' || c.quimico || ' · ' || case when c.usado > c.esperado then '+' else '' end
                              || round((c.usado - c.esperado) / c.esperado * 100) || ' %' order by c.dia desc, c.planta, c.quimico)
                    filter (where c.esperado > 0 and c.usado > 0 and abs(c.usado - c.esperado) > c.esperado * v_x / 100), '[]'::jsonb)
      into v_n, v_items, v_y, v_items2
      from calc c;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_sin_uso', 'area', 'planta', 'nivel', 'naranja', 'orden', 30,
                'titulo', format('%s con dosis y caudal sin uso de químicos registrado', tecnica.f_cuantos(v_n, 'día', 'días')),
                'detalle', format('Revisados los últimos %s días cerrados.', v_dias),
                'n', v_n, 'items', (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(v_items) with ordinality t(e, i) where i <= 5) z), 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;
    if v_y > 0 and tecnica.f_qparam('marca_esperado_usado') = 1 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_desvio', 'area', 'planta', 'nivel', 'naranja', 'orden', 31,
                'titulo', format('%s con el uso de químicos fuera del %s %% de lo esperado', tecnica.f_cuantos(v_y::bigint, 'día', 'días'), tecnica.f_texto_num(v_x)),
                'detalle', format('Revisados los últimos %s días cerrados.', v_dias),
                'n', v_y, 'items', (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(v_items2) with ordinality t(e, i) where i <= 5) z),
                'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;

    -- P5. Químicos de potabilización sin dosis óptima o sin ficha técnica en PDF
    select count(*), coalesce(jsonb_agg(v.nombre || ' · ' || concat_ws(' y ', case when v.dosis_optima_ppm is null then 'sin dosis óptima' end,
                                                                     case when v.ficha_ruta is null then 'sin ficha en PDF' end) order by v.nombre), '[]'::jsonb)
      into v_n, v_items
      from tecnica.v_quimico_vigente v where v.activo and v.potabilizacion and (v.dosis_optima_ppm is null or v.ficha_ruta is null);
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_ficha', 'area', 'planta', 'nivel', 'naranja', 'orden', 32,
                'titulo', format('%s de potabilización sin dosis óptima o sin ficha técnica', tecnica.f_cuantos(v_n, 'químico', 'químicos')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;

    -- P6. Saldo por debajo del mínimo (el mínimo lo fija el supervisor de planta por químico; sin mínimo fijado no hay aviso)
    select count(*), coalesce(jsonb_agg(s.nombre || ' · ' || tecnica.f_texto_num(s.saldo_kg) || ' kg (mínimo ' || tecnica.f_texto_num(m.minimo_kg) || ' kg)' order by s.nombre), '[]'::jsonb)
      into v_n, v_items
      from tecnica.v_quimico_saldo s
      join tecnica.quimicos q on q.id = s.quimico_id and q.activo
      cross join lateral (select e.minimo_kg from tecnica.quimico_minimo_eventos e where e.quimico_id = s.quimico_id order by e.id desc limit 1) m
     where m.minimo_kg is not null and s.saldo_kg is not null and s.saldo_kg < m.minimo_kg;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_saldo', 'area', 'planta', 'nivel', 'naranja', 'orden', 33,
                'titulo', format('%s por debajo del saldo mínimo', tecnica.f_cuantos(v_n, 'químico', 'químicos')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;

    -- P7. Ubicaciones de puntos de muestreo pendientes de aprobar (Corte 5b)
    select count(*), coalesce(jsonb_agg(s.codigo order by s.creado_en) filter (where s.rn <= 5), '[]'::jsonb), min(s.creado_en) into v_n, v_items, v_desde
      from (select p.codigo, pr.creado_en, row_number() over (order by pr.creado_en) as rn
              from tecnica.v_punto_propuestas pr join tecnica.puntos p on p.id = pr.punto_id where pr.estado = 'pendiente') s;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'ubicaciones_pendientes', 'area', 'planta', 'nivel', 'naranja', 'orden', 40,
                'titulo', format('%s de puntos de muestreo por aprobar', tecnica.f_cuantos(v_n, 'ubicación', 'ubicaciones')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'puntos'), 'desde', v_desde);
    end if;
  end if;

  -- ===================== DISTRIBUCIÓN =====================
  if p_distribucion then
    -- D1. Daños abiertos o en atención según su riesgo (alto: 2 h y 6 h; medio o sin riesgo: 24 h y 72 h; bajo: 72 h y 7 días). Avisan a cualquier hora.
    -- redes.v_dano se lee UNA sola vez para D1 y D2 (es la vista más cara): los abiertos o en atención y los atendidos de los últimos días
    select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'riesgo', coalesce(x.riesgo, 'medio'), 't', x.t_detectado, 'estado', x.estado,
                                                 'fin', coalesce(x.t_restablecido, x.registrado_en),
                                                 'itv', x.estado = 'atendido' and exists (select 1 from redes.intervenciones i where i.dano_id = x.id))), '[]'::jsonb) into v_dz
      from redes.v_dano x
     where x.t_detectado <= v_ahora
       and (x.estado in ('reportado', 'en_atencion')
            or (x.estado = 'atendido' and coalesce(x.t_restablecido, x.registrado_en) >= v_ahora - make_interval(days => floor(tecnica.f_aparam('dano_sin_itv_dias'))::integer)));
    with d as (
      select z.codigo, z.riesgo, z.t as t_detectado, extract(epoch from v_ahora - z.t)::numeric / 3600 as h
        from jsonb_to_recordset(v_dz) z(codigo text, riesgo text, t timestamptz, estado text) where z.estado in ('reportado', 'en_atencion')),
    n as (
      select d.*, case when d.h >= tecnica.f_aparam('dano_' || d.riesgo || '_rojo_h') then 'rojo'
                       when d.h >= tecnica.f_aparam('dano_' || d.riesgo || '_naranja_h') then 'naranja' end as nivel from d)
    select jsonb_agg(z.a) into v_items
      from (select jsonb_build_object('clave', 'danos_' || n.nivel, 'area', 'distribucion', 'nivel', n.nivel, 'orden', case n.nivel when 'rojo' then 100 else 101 end,
                     'titulo', case when n.nivel = 'rojo' and count(*) = 1 then '1 daño abierto pasó su plazo'
                                    when n.nivel = 'rojo' then count(*) || ' daños abiertos pasaron su plazo'
                                    when count(*) = 1 then '1 daño abierto se acerca a su plazo'
                                    else count(*) || ' daños abiertos se acercan a su plazo' end,
                     'detalle', format('Plazos: riesgo alto %s y %s h; medio %s y %s h; bajo %s y %s h.', tecnica.f_aparam('dano_alto_naranja_h'), tecnica.f_aparam('dano_alto_rojo_h'),
                                       tecnica.f_aparam('dano_medio_naranja_h'), tecnica.f_aparam('dano_medio_rojo_h'), tecnica.f_aparam('dano_bajo_naranja_h'), tecnica.f_aparam('dano_bajo_rojo_h')),
                     'n', count(*),
                     'items', (array_to_json((array_agg(n.codigo || ' · riesgo ' || n.riesgo || ' · abierto hace ' || tecnica.f_texto_horas(n.h)
                                                        order by case n.riesgo when 'alto' then 1 when 'medio' then 2 else 3 end, n.h desc))[1:5]))::jsonb,
                     'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'danos'), 'desde', min(n.t_detectado)) as a
              from n where n.nivel is not null group by n.nivel) z;
    v_av := v_av || coalesce(v_items, '[]'::jsonb);

    -- D2. Daños atendidos en los últimos días sin ninguna intervención registrada
    select count(*), coalesce((array_to_json((array_agg(z.codigo order by z.fin desc))[1:5]))::jsonb, '[]'::jsonb) into v_n, v_items
      from jsonb_to_recordset(v_dz) z(codigo text, estado text, fin timestamptz, itv boolean)
     where z.estado = 'atendido' and not z.itv;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'danos_sin_intervencion', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 110,
                'titulo', format('%s sin intervención registrada', tecnica.f_cuantos(v_n, 'daño atendido', 'daños atendidos')),
                'detalle', format('Atendidos en los últimos %s días.', tecnica.f_aparam('dano_sin_itv_dias')),
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'danos'), 'desde', null);
    end if;

    -- D3. Daños e intervenciones con el activo no identificado (por asociar o crear)
    select count(*), coalesce((array_to_json((array_agg(x.codigo order by x.registrado_en))[1:5]))::jsonb, '[]'::jsonb), min(x.registrado_en) into v_n, v_items, v_desde
      from redes.v_no_identificados x;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'no_identificados', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 120,
                'titulo', format('%s con el activo sin identificar', tecnica.f_cuantos(v_n, 'registro', 'registros')), 'detalle', 'Daños o intervenciones por asociar a un activo.',
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'no_identificados'), 'desde', v_desde);
    end if;

    -- D4. Intervenciones con los recursos sin completar
    select count(*), coalesce((array_to_json((array_agg(x.codigo order by x.registrado_en))[1:5]))::jsonb, '[]'::jsonb), min(x.registrado_en) into v_n, v_items, v_desde
      from redes.v_intervencion x where x.estado <> 'oculta' and x.recursos = 'por_completar';
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'recursos_por_completar', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 130,
                'titulo', format('%s con los recursos sin completar', tecnica.f_cuantos(v_n, 'intervención', 'intervenciones')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'intervenciones'), 'desde', v_desde);
    end if;

    -- D5. Reportes del bot sin convertir ni descartar
    select count(*), coalesce((array_to_json((array_agg(coalesce(x.radicado, 'Sin radicado') || ' · hace ' || tecnica.f_texto_horas(extract(epoch from v_ahora - x.recibido_en)::numeric / 3600)
                                                        order by x.recibido_en))[1:5]))::jsonb, '[]'::jsonb), min(x.recibido_en) into v_n, v_items, v_desde
      from redes.v_reporte_externo x where x.ultimo_evento = 'recibido';
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'reportes_bot', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 140,
                'titulo', format('%s sin atender', tecnica.f_cuantos(v_n, 'reporte del bot', 'reportes del bot')), 'detalle', 'Convertir en daño o descartar con motivo.',
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'bot'), 'desde', v_desde);
    end if;

    -- D6. Línea 116: reportes en «Registrado» desde hace más de N días. Queda listo y APAGADO hasta que el Corte 5d esté publicado (sin su tabla no hay aviso).
    if to_regclass('redes.l116_vigente') is not null then
      execute 'select count(*), min(estado_desde) from redes.l116_vigente where not oculto and estado = ''registrado'' and estado_desde < $1'
         into v_n, v_desde using v_ahora - make_interval(days => floor(tecnica.f_aparam('l116_registrado_dias'))::integer);
      if v_n > 0 then
        v_av := v_av || jsonb_build_object('clave', 'l116_registrado', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 150,
                  'titulo', format('%s de la línea 116 en «Registrado» hace más de %s días', tecnica.f_cuantos(v_n, 'reporte', 'reportes'), tecnica.f_aparam('l116_registrado_dias')),
                  'detalle', 'La línea 116 es de referencia: el cierre lo hace el sistema comercial.',
                  'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', v_desde);
      end if;
    end if;

    -- D7. Cargas de capas abiertas sin publicar ni anular
    select count(*), coalesce((array_to_json((array_agg(x.capa_codigo || ' · abierta hace ' || tecnica.f_texto_horas(extract(epoch from v_ahora - x.creado_en)::numeric / 3600) order by x.creado_en))[1:5]))::jsonb, '[]'::jsonb),
           min(x.creado_en) into v_n, v_items, v_desde
      from redes.v_cargas_estado x where x.estado = 'abierta' and x.creado_en < v_ahora - make_interval(secs => (tecnica.f_aparam('carga_abierta_horas') * 3600)::double precision);
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'cargas_abiertas', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 160,
                'titulo', format('%s del Cargue de capas sin publicar', tecnica.f_cuantos(v_n, 'carga abierta', 'cargas abiertas')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'cargue'), 'desde', v_desde);
    end if;

    -- D8. Activos «por verificar» (la misma regla de la bandeja: el último evento de verificación es «por_verificar» y el activo no está retirado)
    select count(*) into v_n
      from (select distinct on (e.activo_id) e.activo_id, e.tipo from redes.activo_eventos e where e.tipo in ('verificar', 'por_verificar') order by e.activo_id, e.id desc) u
     where u.tipo = 'por_verificar' and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = u.activo_id and not m.retirado);
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'por_verificar', 'area', 'distribucion', 'nivel', 'info', 'orden', 170,
                'titulo', format('%s por verificar', tecnica.f_cuantos(v_n, 'activo', 'activos')), 'detalle', null,
                'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'por_verificar'), 'desde', null);
    end if;

    -- D9. Nodos por clasificar
    select count(*) into v_n from redes.v_nodo_visible x where x.clase_nodo = 'por_clasificar';
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'nodos_por_clasificar', 'area', 'distribucion', 'nivel', 'info', 'orden', 180,
                'titulo', format('%s por clasificar', tecnica.f_cuantos(v_n, 'nodo', 'nodos')), 'detalle', null,
                'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'nodos'), 'desde', null);
    end if;
  end if;

  -- D10 (Corte 9b, Fase 1b). Válvulas cerradas (sin «abrir») hace más de X horas: naranja desde valvula_cerrada_naranja_h, rojo desde valvula_cerrada_rojo_h
  if p_distribucion then
    for r in select c.nivel, count(*) as n, min(c.hecho_en) as desde,
                    (array_to_json((array_agg(c.codigo || coalesce(' · ' || c.registro, '') || ' · hace ' || tecnica.f_texto_horas(c.horas) order by c.hecho_en))[1:5]))::jsonb as items
               from redes.f_cortes_para_avisos(v_ahora, tecnica.f_aparam('valvula_cerrada_naranja_h'), tecnica.f_aparam('valvula_cerrada_rojo_h')) c
              group by c.nivel loop
      v_av := v_av || jsonb_build_object('clave', 'valvulas_cerradas_' || r.nivel, 'area', 'distribucion', 'nivel', r.nivel, 'orden', case r.nivel when 'rojo' then 102 else 103 end,
                'titulo', format('%s hace más de %s', tecnica.f_cuantos(r.n, 'válvula cerrada', 'válvulas cerradas'),
                                 tecnica.f_texto_horas(tecnica.f_aparam(case r.nivel when 'rojo' then 'valvula_cerrada_rojo_h' else 'valvula_cerrada_naranja_h' end))),
                'detalle', 'Abra la válvula cuando vuelva el servicio, o ajuste la hora estimada de regreso.',
                'n', r.n, 'items', r.items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', r.desde);
    end loop;
  end if;

  -- D11 (Corte 9b, Fase 2). Presión de MODELO fuera de rango (Res. 0330 de 2017): un solo aviso informativo. Los dos umbrales se leen una vez
  if p_distribucion then
    v_x := redes.f_param('presion_baja_naranja_mca'); v_y := redes.f_param('presion_alta_naranja_mca');
    select count(*) into v_n from redes.pm_nodos x where x.carga_id = redes.f_ref_vigente('pm_nodos') and (x.pres_exist_min < v_x or x.pres_exist_max > v_y);
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'presion_modelo', 'area', 'distribucion', 'nivel', 'info', 'orden', 175,
                'titulo', format('%s %s fuera de rango según el modelo', tecnica.f_texto_num(v_n), case when v_n = 1 then 'nodo' else 'nodos' end),      -- con punto de miles
                'detalle', format('Presión de modelo, no medida (Plan Maestro 2014): mínima bajo %s o máxima sobre %s m.c.a.', v_x, v_y),
                'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', null);
    end if;
  end if;

  -- ===================== PERSONAL (los dos supervisores y el administrador) =====================
  if p_planta or p_distribucion then
    for r in
      with pob as (
        select lb.email, coalesce(nullif(btrim(lb.nombre), ''), lb.email) as nombre,
               (lb.ver_registro_tecnico and not lb.ver_dashboard_tecnico and not lb.ver_dashboard_redes) as operador, f.area, f.cuadrilla_id
          from public.geoportal_lista_blanca lb left join redes.v_personal_ficha f on f.persona = lb.email
         where lb.activo and lb.rol <> 'admin' and (lb.ver_registro_tecnico or lb.ver_dashboard_redes or lb.ver_dashboard_tecnico) and tecnica.f_tecnica_activa(lb.email)),
      cat as (
        select 'personal_sin_formularios' as clave, 300 as orden, 'persona activa sin formularios' as uno, 'personas activas sin formularios' as varios, p.nombre
          from pob p
         where p.operador and not exists (select 1 from (select distinct on (e.formulario) e.tipo_evento from tecnica.personal_tecnico_eventos e
                                                         where e.persona = p.email and e.tipo_evento in ('asignar_formulario', 'quitar_formulario') and e.formulario is not null
                                                         order by e.formulario, e.id desc) x where x.tipo_evento = 'asignar_formulario')
        union all select 'personal_sin_area', 301, 'persona activa sin área', 'personas activas sin área', p.nombre from pob p where p.area is null
        union all select 'personal_sin_cuadrilla', 302, 'persona de distribución sin cuadrilla', 'personas de distribución sin cuadrilla', p.nombre
          from pob p where p.operador and p.area in ('distribucion', 'ambas') and p.cuadrilla_id is null)
      select c.clave, c.orden, count(*) as n, min(c.uno) as uno, min(c.varios) as varios, (array_to_json((array_agg(c.nombre order by lower(c.nombre)))[1:5]))::jsonb as items
        from cat c group by c.clave, c.orden order by c.orden
    loop
      v_av := v_av || jsonb_build_object('clave', r.clave, 'area', 'personal', 'nivel', 'naranja', 'orden', r.orden,
                'titulo', tecnica.f_cuantos(r.n, r.uno, r.varios), 'detalle', null, 'n', r.n, 'items', r.items,
                'bandeja', jsonb_build_object('tablero', 'personal', 'pestana', 'personal'), 'desde', null);
    end loop;
  end if;

  return coalesce((select jsonb_agg(a order by case a ->> 'nivel' when 'rojo' then 1 when 'naranja' then 2 else 3 end, (a ->> 'orden')::integer, a ->> 'clave')
                     from jsonb_array_elements(v_av) a), '[]'::jsonb);
end $function$;
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
revoke all on function tecnica.f_avisos(boolean, boolean, timestamptz) from public, anon, authenticated, service_role;
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
        'reemplazadas', jsonb_build_array('tecnica.f_avisos (aviso informativo de presiones, D11)'),
        'capa_oculta', 'cortes',
        'motivo', 'alertas de presión de modelo (Res. 0330 de 2017), usuarios sensibles, afectación del daño o la intervención, lecturas de sensores (vacía) y la capa de cortes oculta (vive en el modo Afectaciones)'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes9f.*), la red de prueba ZT9B (la misma del ensayo del 9b, en un rincón de la caja),
-- sus contratos (15 cifras, 99999…), su carga de presiones de modelo (que tapa la del Plan dentro de esta transacción), sus usuarios sensibles y su sensor.
-- NO escribe en tablas de Comercial (cartera, catastro): la regla del nombre se prueba con textos, y la propuesta real solo se corre (y se deshace).
-- Mide con el volumen real y FALLA si una lectura pasa de 1 s o la afectación de 5 s. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 9b, Fase 2 … RESULTADO: N de N pruebas correctas — SIN FALLAS
-- =====================================================================
create temp table _r (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.reg(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as
$$ insert into _r (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $$;
create function pg_temp.err(p_nombre text, p_sql text, p_estado text default null, p_texto text default null) returns void language plpgsql as $$
declare v_e text; v_m text;
begin
  begin
    execute p_sql;
    perform pg_temp.reg(p_nombre, false, 'No falló y debía fallar');
  exception when others then
    get stacked diagnostics v_e = returned_sqlstate, v_m = message_text;
    perform pg_temp.reg(p_nombre, (p_estado is null or v_e = p_estado) and (p_texto is null or position(p_texto in v_m) > 0), 'SQLSTATE ' || v_e || ': ' || left(v_m, 200));
  end;
end $$;
-- un rincón de la caja de Valledupar, lejos de la red (x, y en metros aproximados)
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.1300 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.5800 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create temp table _zt (nombre text primary key, activo_id bigint, nodo bigint, x numeric, y numeric);
-- un activo de prueba (versión 1); devuelve su id
create function pg_temp.activo(p_nombre text, p_prefijo text, p_geom geometry, p_clase text default null, p_efecto text default null, p_estado text default 'en_operacion')
returns bigint language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes9f.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZT9B ' || p_nombre, p_clase, p_efecto,
          case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end, case when p_prefijo = 'RED' then 110 end,
          p_estado, '{}'::jsonb, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT9B activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_id;
end $$;
-- un nodo de la red de prueba (con su activo si es válvula o tanque)
create function pg_temp.nodo(p_nombre text, x numeric, y numeric, p_carga bigint, p_prefijo text default null, p_clase text default null, p_efecto text default null)
returns void language plpgsql as $$
declare v_act bigint; v_n bigint;
begin
  if p_prefijo is not null then v_act := pg_temp.activo(p_nombre, p_prefijo, pg_temp.pt(x, y), p_clase, p_efecto); end if;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id)
  values ('acueducto', 'ZT9B-' || p_nombre, 'ZT9B' || p_nombre, case when v_act is null then 'por_clasificar' else 'activo' end, pg_temp.pt(x, y), v_act, 0, p_carga)
  returning id into v_n;
  insert into _zt values (p_nombre, v_act, v_n, x, y);
end $$;
-- un tramo de la red de prueba entre dos nodos, con n contratos de prueba
create function pg_temp.tramo(p_nombre text, p_a text, p_b text, p_carga bigint, p_contratos integer, p_estado text default 'en_operacion')
returns void language plpgsql as $$
declare a _zt; b _zt; v_id bigint;
begin
  select * into a from _zt where nombre = p_a; select * into b from _zt where nombre = p_b;
  v_id := pg_temp.activo(p_nombre, 'RED', ST_MakeLine(pg_temp.pt(a.x, a.y), pg_temp.pt(b.x, b.y)), null, null, p_estado);
  insert into redes.tramo_nodos (activo_id, version, nodo_ini, nodo_fin, metodo, carga_id) values (v_id, 1, a.nodo, b.nodo, 'modelo', p_carga);
  insert into _zt values (p_nombre, v_id, null, (a.x + b.x) / 2, (a.y + b.y) / 2);
  insert into redes.contrato_tramo (contrato, activo_id, distancia_m, metodo)
  select '99999' || lpad((v_id % 100000)::text, 5, '0') || lpad(i::text, 5, '0'), v_id, 5, 'cercania' from generate_series(1, p_contratos) i;
end $$;
create function pg_temp.id(p_nombre text) returns bigint language sql as $$ select activo_id from _zt where nombre = p_nombre $$;
create function pg_temp.cod(p_nombre text) returns text language sql as $$ select a.codigo from redes.activos a join _zt z on z.activo_id = a.id where z.nombre = p_nombre $$;
create function pg_temp.cods(p jsonb) returns text language sql as $$ select coalesce(string_agg(x ->> 'codigo', ',' order by o), '') from jsonb_array_elements(p) with ordinality y(x, o) $$;
create function pg_temp.ncods(p text) returns text language sql as $$
  select coalesce(string_agg(pg_temp.cod(btrim(x)), ',' order by o), '') from unnest(string_to_array(p, ',')) with ordinality u(x, o) $$;
-- la tesela (z, x, y) que contiene un punto
create function pg_temp.tx(g geometry, z integer) returns integer language sql as $$ select floor((ST_X(g) + 180) / 360 * (1 << z))::integer $$;
create function pg_temp.ty(g geometry, z integer) returns integer language sql as $$
  select floor((1 - ln(tan(radians(ST_Y(g))) + 1 / cos(radians(ST_Y(g)))) / pi()) / 2 * (1 << z))::integer $$;
create function pg_temp.foto() returns redes.corte_fotos language sql as $$ select * from redes.corte_fotos order by id desc limit 1 $$;
create function pg_temp.archivo(p_ruta text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg')) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;

do $prueba$
declare
  a text := 'prueba.redes9f.adm@emdupar.gov.co'; sd text := 'prueba.redes9f.dist@emdupar.gov.co'; op text := 'prueba.redes9f.op@emdupar.gov.co'; na text := 'prueba.redes9f.nada@emdupar.gov.co';
  v_carga bigint; v_c bigint; j jsonb; v_p jsonb; v_dan text; v_sen bigint; c1 text; c2 text; c3 text; v_real text; v_n integer;
  v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_ms4 numeric; v_ms5 numeric; v_ms6 numeric; v_info text := ''; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9B Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT9B Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT9B Operador daños', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT9B Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);

  -- ---------- la red de prueba ----------
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
  values ('acueducto', md5('zt9b-a') || md5('zt9b-b'), 'shp', 4326, 'ID', 1, 'ZT9B red de prueba', a) returning id into v_carga;
  perform pg_temp.nodo('F', 0, 0, v_carga, 'TAN');
  perform pg_temp.nodo('A', 100, 0, v_carga);
  perform pg_temp.nodo('V1', 200, 0, v_carga, 'VAL', 'cierre', 'cierra');
  perform pg_temp.nodo('B', 300, 0, v_carga);
  perform pg_temp.nodo('V2', 400, 0, v_carga, 'VAL', 'cierre', 'sin_definir');
  perform pg_temp.nodo('C', 500, 0, v_carga);
  perform pg_temp.nodo('V3', 600, 0, v_carga, 'VAL', 'cierre', 'cierra');
  perform pg_temp.nodo('D', 700, 0, v_carga);
  perform pg_temp.nodo('K', 800, 0, v_carga);
  perform pg_temp.nodo('V4', 300, 100, v_carga, 'VAL', 'cierre', 'deriva');
  perform pg_temp.nodo('E', 300, 200, v_carga);
  perform pg_temp.nodo('V5', 300, -100, v_carga, 'VAL', 'ventosa', 'cierra');
  perform pg_temp.nodo('G', 300, -200, v_carga);
  perform pg_temp.nodo('H', 500, 100, v_carga);
  perform pg_temp.nodo('F2', 500, -100, v_carga, 'TAN');
  perform pg_temp.tramo('T1', 'F', 'A', v_carga, 1);
  perform pg_temp.tramo('T2', 'A', 'V1', v_carga, 1);
  perform pg_temp.tramo('T3', 'V1', 'B', v_carga, 1);
  perform pg_temp.tramo('T4', 'B', 'V2', v_carga, 2);
  perform pg_temp.tramo('T5', 'V2', 'C', v_carga, 1);
  perform pg_temp.tramo('T6', 'C', 'V3', v_carga, 1);
  perform pg_temp.tramo('T7', 'V3', 'D', v_carga, 2);
  perform pg_temp.tramo('T8', 'B', 'V4', v_carga, 1);
  perform pg_temp.tramo('T9', 'V4', 'E', v_carga, 1);
  perform pg_temp.tramo('T10', 'B', 'V5', v_carga, 0);
  perform pg_temp.tramo('T11', 'V5', 'G', v_carga, 1);
  perform pg_temp.tramo('T12', 'C', 'H', v_carga, 3);
  perform pg_temp.tramo('T13', 'C', 'F2', v_carga, 0);
  perform pg_temp.tramo('T14', 'D', 'K', v_carga, 4, 'proyectado');


  -- ===================== 01. Estructura =====================
  perform pg_temp.reg('01.01 las 5 tablas existen sin permisos de la API; los hechos (usuarios sensibles, sus eventos y las lecturas) son de solo agregar',
     not has_table_privilege('service_role', 'redes.usuarios_sensibles', 'select') and not has_table_privilege('anon', 'redes.sensor_lecturas', 'select')
     and not has_table_privilege('service_role', 'redes.v_usuario_sensible', 'select')
     and (select count(*) from pg_trigger t where t.tgrelid in ('redes.usuarios_sensibles'::regclass, 'redes.usuario_sensible_eventos'::regclass, 'redes.sensor_lecturas'::regclass)
            and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 6);
  perform pg_temp.reg('01.02 las RPC nuevas: solo service_role; las internas: nadie de la API',
     has_function_privilege('service_role', 'public.geoportal_redes_afectacion(text,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_redes_sensibles(text,text,text,integer)', 'execute')
     and not has_function_privilege('service_role', 'redes.f_sensibles_proponer(text)', 'execute'));
  perform pg_temp.reg('01.03 la capa «Cortes programados vigentes» ya no sale en la lista del geovisor, pero sigue en la tabla con su nota',
     not exists (select 1 from jsonb_array_elements(public.geoportal_redes_geovisor(sd) -> 'capas') x where x ->> 'codigo' = 'cortes')
     and (select not activa and nota like 'Oculta%' from redes.geovisor_capas where codigo = 'cortes'));
  perform pg_temp.reg('01.04 tecnica.f_avisos conserva el bloque del 1b (válvulas cerradas) y suma el de presiones (D11)',
     position('D10 (Corte 9b, Fase 1b)' in pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) > 0
     and position('D11 (Corte 9b, Fase 2)' in pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) > 0);

  -- ===================== 02. Alertas de presión (modelo) =====================
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, autor) values ('pm_nodos', 'zt9b_pm_nodos.csv', md5('zt9b' || clock_timestamp()::text), 6, 'ZT9B modelo de prueba', a) returning id into v_c;
  insert into redes.pm_nodos (carga_id, llave, nombre, geom, pres_exist_min, pres_exist_max, pres_futura_min, pres_futura_max) values
    (v_c, 'ZT9B-A', 'ZT9B A', pg_temp.pt(100, 0), 8, 30, 20, 40),      -- mínima bajo 10: roja
    (v_c, 'ZT9B-B', 'ZT9B B', pg_temp.pt(300, 0), 12, 40, 20, 40),     -- mínima bajo 15: naranja
    (v_c, 'ZT9B-C', 'ZT9B C', pg_temp.pt(500, 0), 20, 55, 20, 40),     -- máxima sobre 50: naranja
    (v_c, 'ZT9B-D', 'ZT9B D', pg_temp.pt(700, 0), 20, 65, 20, 70),     -- máxima sobre 60: roja (también en la futura)
    (v_c, 'ZT9B-H', 'ZT9B H', pg_temp.pt(500, 100), 25, 45, 25, 45),   -- en rango
    (v_c, 'ZT9B-E', 'ZT9B E', pg_temp.pt(300, 200), 30, 95, 30, 45);   -- sobre 60 y sobre la presión de trabajo del PVC (88)
  j := public.geoportal_redes_alertas_presion(sd);
  perform pg_temp.reg('02.01 red existente: 6 nodos; mínima roja 1 (A), mínima naranja 1 (B), máxima naranja 1 (C), máxima roja 2 (D y E); rotulada «de MODELO, no medida»',
     (j ->> 'cargado')::boolean and (j ->> 'nodos')::integer = 6 and j -> 'niveles' = '{"baja_roja": 1, "baja_naranja": 1, "alta_naranja": 1, "alta_roja": 2}'::jsonb
     and j ->> 'aviso' like '%MODELO%' and (j -> 'umbrales' ->> 'baja_naranja')::numeric = 15 and jsonb_array_length(j -> 'peores') = 5, j::text);
  perform pg_temp.reg('02.02 por material: el nodo E (95 m.c.a.) pasa la presión de trabajo del tramo T9 (PVC sin clase: 88), con la nota «por verificar»',
     (j -> 'por_material' ->> 'n')::integer = 1 and j -> 'por_material' -> 'nodos' -> 0 ->> 'tramo' = pg_temp.cod('T9')
     and (j -> 'por_material' -> 'nodos' -> 0 ->> 'presion_trabajo')::numeric = 88 and j -> 'por_material' ->> 'nota' like '%por verificar%', j ->> 'por_material');
  perform pg_temp.reg('02.03 red futura: solo D queda en rojo', public.geoportal_redes_alertas_presion(sd, 'futura') -> 'niveles' = '{"alta_roja": 1}'::jsonb);
  update redes.parametros set valor = 9 where clave = 'presion_baja_naranja_mca';
  update redes.parametros set valor = 7 where clave = 'presion_baja_roja_mca';
  perform pg_temp.reg('02.04 los umbrales son los parámetros editables: con 9 y 7 de mínima, A pasa a naranja y B queda en rango',
     public.geoportal_redes_alertas_presion(sd) -> 'niveles' = '{"baja_naranja": 1, "alta_naranja": 1, "alta_roja": 2}'::jsonb);
  update redes.parametros set valor = 15 where clave = 'presion_baja_naranja_mca';
  update redes.parametros set valor = 10 where clave = 'presion_baja_roja_mca';
  perform pg_temp.err('02.05 las alertas de presión son del supervisor: el operador no (42501)', format('select public.geoportal_redes_alertas_presion(%L)', op), '42501');
  perform pg_temp.err('02.06 un escenario que no existe', format('select public.geoportal_redes_alertas_presion(%L, %L)', sd, 'otra'), null, 'escenario');
  perform pg_temp.reg('02.07 Avisos (distribución): UN aviso informativo «5 nodos fuera de rango según el modelo» (ni rojo ni naranja); al supervisor de planta no le sale',
     (select count(*) = 1 and bool_and(av ->> 'nivel' = 'info' and av ->> 'titulo' = '5 nodos fuera de rango según el modelo' and av ->> 'detalle' like 'Presión de modelo, no medida%15%50%')
        from jsonb_array_elements(tecnica.f_avisos(false, true)) av where av ->> 'clave' = 'presion_modelo')
     and not exists (select 1 from jsonb_array_elements(tecnica.f_avisos(true, false)) av where av ->> 'clave' = 'presion_modelo')
     and (select sum(n) from redes.f_presion_para_avisos()) = 5);

  -- ===================== 03. Usuarios sensibles =====================
  perform pg_temp.reg('03.01 la regla del nombre: hospital, clínica (con tilde), institución educativa y bomberos se reconocen; una persona no',
     (select tipo || ':' || palabra from redes.f_sensible_tipo('Hospital Rosario Pumarejo')) = 'hospital:HOSPITAL'
     and (select tipo from redes.f_sensible_tipo('CLÍNICA DEL CESAR S.A.')) = 'clinica' and (select tipo from redes.f_sensible_tipo('institución educativa loperena')) = 'colegio'
     and (select tipo from redes.f_sensible_tipo('CUERPO DE BOMBEROS')) = 'otro' and not exists (select 1 from redes.f_sensible_tipo('JUAN PEREZ ESCUELAS'))
     and not exists (select 1 from redes.f_sensible_tipo(null))
     and (select tipo from redes.f_sensible_tipo('CDI Los Pequeñitos')) = 'colegio' and (select tipo from redes.f_sensible_tipo('Estación de Policía Centro')) = 'otro'
     and (select tipo from redes.f_sensible_tipo('Unidad de diálisis')) = 'clinica' and (select tipo from redes.f_sensible_tipo('EMDUPAR S.A. E.S.P. SEDE')) = 'sede_propia'
     and (select tipo from redes.f_sensible_tipo('Hogar geriátrico San José')) = 'otro'
     and not exists (select 1 from redes.f_sensible_tipo('IPS SALUD TOTAL')) and not exists (select 1 from redes.f_sensible_tipo('E.S.E. DEL NORTE')));
  perform pg_temp.err('03.02 la propuesta por el nombre solo la corre un administrador', format('select redes.f_sensibles_proponer(%L)', sd), '42501');
  v_t0 := clock_timestamp(); v_n := redes.f_sensibles_proponer(a); v_ms5 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  perform pg_temp.reg('03.03 la propuesta recorre la cartera de esta base y es repetible: la segunda vez no agrega nada; nunca guarda un nombre',
     v_n >= 0 and redes.f_sensibles_proponer(a) = 0 and not exists (select 1 from redes.usuarios_sensibles u where length(u.palabra) > 30), 'propuestos: ' || v_n);
  -- tres usuarios sensibles de prueba sobre contratos de la red ZT9B (como los dejaría la propuesta): dos en T4 y uno en T12
  select min(ct.contrato), max(ct.contrato) into c1, c2 from redes.contrato_tramo ct where ct.activo_id = pg_temp.id('T4');
  select min(ct.contrato) into c3 from redes.contrato_tramo ct where ct.activo_id = pg_temp.id('T12');
  insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor) values (c1, 'hospital', 'HOSPITAL', 'nombre', a), (c2, 'colegio', 'COLEGIO', 'nombre', a), (c3, 'clinica', 'CLINICA', 'nombre', a);
  j := public.geoportal_redes_sensibles(sd, 'por_confirmar', null, 500);
  perform pg_temp.reg('03.04 la bandeja del supervisor: los tres por confirmar, con su tipo, la palabra y su tramo; sin nombres',
     (select count(*) from jsonb_array_elements(j -> 'items') x where x ->> 'contrato' in (c1, c2, c3) and x ->> 'estado' = 'por_confirmar' and x ->> 'tramo' is not null) = 3
     and jsonb_array_length(j -> 'tipos') = 5 and (j -> 'totales' ->> 'por_confirmar')::integer >= 3, left(j::text, 300));
  perform pg_temp.err('03.05 la bandeja es del supervisor (42501 al operador)', format('select public.geoportal_redes_sensibles(%L)', op), '42501');
  j := public.geoportal_redes_sensible_fijar(sd, c1, 'confirmar');
  v_p := public.geoportal_redes_sensible_fijar(sd, c1, 'confirmar');
  perform pg_temp.reg('03.06 el supervisor confirma el hospital; repetirlo no cambia nada',
     j ->> 'estado' = 'confirmado' and not (v_p ->> 'cambio')::boolean and (select count(*) from redes.usuario_sensible_eventos where contrato = c1) = 1);
  perform pg_temp.err('03.07 descartar pide motivo', format('select public.geoportal_redes_sensible_fijar(%L, %L, %L)', sd, c2, 'descartar'), null, 'motivo');
  j := public.geoportal_redes_sensible_fijar(sd, c2, 'descartar', null, 'ZT9B no es un colegio, es una casa');
  v_p := public.geoportal_redes_sensible_fijar(sd, c3, 'confirmar', 'hospital');
  perform pg_temp.reg('03.08 descartar con motivo; y confirmar corrigiendo el tipo (la «clínica» era un hospital)',
     j ->> 'estado' = 'descartado' and v_p ->> 'tipo' = 'hospital'
     and (select tipo = 'hospital' and estado = 'confirmado' from redes.v_usuario_sensible where contrato = c3));
  perform pg_temp.err('03.09 agregar a mano un contrato que no está en el catastro: P0002',
     format('select public.geoportal_redes_sensible_fijar(%L, %L, %L, %L, %L)', sd, '999990000099999', 'confirmar', 'otro', 'ZT9B hogar de ancianos'), 'P0002');
  select c.cod_usuario into v_real from public.catastro_valledupar c
   where c.cod_usuario ~ '^[0-9]{1,15}$' and c.cod_usuario not in ('0', '99999999') and not exists (select 1 from redes.usuarios_sensibles u where u.contrato = c.cod_usuario) order by c.id limit 1;
  if v_real is not null then j := public.geoportal_redes_sensible_fijar(sd, v_real, 'confirmar', 'otro', 'ZT9B hogar de ancianos de prueba'); end if;
  perform pg_temp.reg('03.10 agregar a mano un contrato del catastro, con tipo y motivo: queda confirmado, de origen «manual»',
     v_real is null or (j ->> 'estado' = 'confirmado' and (select origen = 'manual' and palabra is null from redes.usuarios_sensibles where contrato = v_real)));
  perform pg_temp.err('03.11 solo agregar: no se cambia un usuario sensible', format('update redes.usuarios_sensibles set tipo = %L where contrato = %L', 'otro', c1));

  -- ===================== 04. Afectación del daño (usuarios sin servicio y sensibles) =====================
  v_p := public.geoportal_redes_preparar_dano(op, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_dan := public.geoportal_redes_crear_dano(op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           'activo', pg_temp.cod('T4'), 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(350),
           't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
           'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
  j := public.geoportal_redes_afectacion(op, v_dan);
  perform pg_temp.reg('04.01 sin válvulas cerradas: la propuesta sale de la simulación (entre 6 y 13 contratos) y trae el hospital confirmado de T4; el descartado no cuenta',
     j ->> 'fuente' = 'simulacion' and (j ->> 'contratos_min')::integer = 6 and (j ->> 'contratos_max')::integer = 13
     and (j -> 'sensibles' ->> 'confirmados')::integer = 1 and (j -> 'sensibles' ->> 'por_confirmar')::integer = 0
     and j -> 'sensibles' -> 'lista' -> 0 ->> 'contrato' = c1 and j::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n', j::text);
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V1'), 'cerrar', v_dan);
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V2'), 'cerrar', v_dan);
  j := public.geoportal_redes_afectacion(op, v_dan);
  perform pg_temp.reg('04.02 con V1 y V2 cerradas: lo real (2 válvulas, 1 zona, 6 contratos) y el hospital',
     j ->> 'fuente' = 'cierre_real' and (j ->> 'valvulas_cerradas')::integer = 2 and (j ->> 'zonas')::integer = 1 and (j ->> 'contratos')::integer = 6
     and (j -> 'sensibles' ->> 'confirmados')::integer = 1, j::text);
  perform pg_temp.err('04.03 un daño que no existe: P0002', format('select public.geoportal_redes_afectacion(%L, %L)', op, 'DAN-999999'), 'P0002');
  perform pg_temp.err('04.04 alguien sin Técnica no la ve (42501)', format('select public.geoportal_redes_afectacion(%L, %L)', na, v_dan), '42501');
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V1'), 'abrir');
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V2'), 'abrir');

  -- ===================== 05. Sensores (vacíos) =====================
  v_sen := pg_temp.activo('SENSOR', 'SEN', pg_temp.pt(300, 0));
  j := public.geoportal_redes_sensores(sd);
  perform pg_temp.reg('05.01 un sensor sin lecturas sale «por conectar», con su posición',
     (select x ->> 'estado' = 'por_conectar' and x ->> 'lat' is not null and x -> 'ultima' = 'null'::jsonb from jsonb_array_elements(j -> 'sensores') x where x ->> 'codigo' = (select codigo from redes.activos where id = v_sen)), j::text);
  insert into redes.sensor_lecturas (activo_id, variable, valor, unidad, medido_en, fuente) values (v_sen, 'presion', 22.5, 'm.c.a.', clock_timestamp() - interval '5 hours', 'ZT9B prueba');
  perform pg_temp.reg('05.02 con una lectura de hace 5 horas: «sin señal»; con una de ahora: «en línea»',
     redes.f_sensor_estado(v_sen) = 'sin_senal');
  insert into redes.sensor_lecturas (activo_id, variable, valor, unidad, medido_en, fuente) values (v_sen, 'presion', 23, 'm.c.a.', clock_timestamp(), 'ZT9B prueba');
  perform pg_temp.reg('05.03 … «en línea», y la lista trae la última lectura', redes.f_sensor_estado(v_sen) = 'en_linea'
     and (select (x -> 'ultima' ->> 'valor')::numeric = 23 from jsonb_array_elements(public.geoportal_redes_sensores(sd) -> 'sensores') x where x ->> 'codigo' = (select codigo from redes.activos where id = v_sen)));
  perform pg_temp.err('05.04 solo agregar: una lectura no se borra', format('delete from redes.sensor_lecturas where activo_id = %s', v_sen));

  -- ===================== 06. Tiempos con volumen real =====================
  insert into redes.pm_nodos (carga_id, llave, nombre, geom, pres_exist_min, pres_exist_max, pres_futura_min, pres_futura_max)
  select v_c, 'ZT9B-vol-' || i, 'ZT9B vol ' || i, pg_temp.pt(1000 + (i % 100) * 10, (i / 100) * 10), (i % 40), 20 + (i % 70), 10 + (i % 30), 30 + (i % 40) from generate_series(1, 7000) i;
  analyze redes.pm_nodos;
  v_t0 := clock_timestamp(); j := public.geoportal_redes_alertas_presion(sd); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_sensibles(sd, null, null, 500); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_afectacion(op, v_dan); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_sensores(sd); v_ms4 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform tecnica.f_avisos(true, true); v_ms6 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS: avisos completos (con el de presiones, 7.006 nodos) %s ms · alertas de presión con %s nodos %s ms · bandeja de sensibles %s ms · afectación de un daño (simulación sobre la red de esta base) %s ms · sensores %s ms · propuesta de sensibles sobre la cartera de esta base (%s filas; solo por psql o editor) %s ms',
                   v_ms6, j ->> 'nodos', v_ms1, v_ms2, v_ms3, v_ms4, (select count(*) from public.cartera_suscripcion), v_ms5);
  perform pg_temp.reg('06.01 TIEMPOS: las lecturas (avisos completos, alertas de presión, bandeja de sensibles, sensores) en menos de 1 s y la afectación en menos de 5 s',
     greatest(v_ms1, v_ms2, v_ms4, v_ms6) < 1000 and v_ms3 < 5000, v_info);
  perform pg_temp.reg('06.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 9b, Fase 2 (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
