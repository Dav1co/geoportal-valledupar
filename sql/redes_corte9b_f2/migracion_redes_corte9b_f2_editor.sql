begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 (presiones y alertas, sensores vacíos, usuarios sensibles y afectación del daño) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte9b_simulacion_alertas.md (Fase 2), §30.7 y §17 de la bitácora, respuestas de David del 17-nov.
-- · Presupone el paquete del 9b (1a + 1b) publicado: huella del conjunto de funciones de redes 895517fb68f74d6d6c20079c83bdf7c4.
-- · No reemplaza ninguna función de redes. Reemplaza UNA de tecnica: tecnica.f_avisos (del 9b 1b, md5 898bafa5adddfcc08d65adf138d0114a), para sumar el aviso informativo
--   de presiones (David, 17-nov): APAGADO por omisión (parámetro de Avisos «presion_modelo_aviso») y calculado solo con las horas confiables del modelo.
--   Solo base de datos: las rutas de la Edge y las pantallas son del Code B.
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

-- ---------- 2b. Horas del día en que el modelo NO es confiable (David, 17-nov). En la red existente (modeloV1) el modelo colapsa en las horas de consumo
--                5, 7, 10, 12 y 14 (Fase 0 del 9b): las alertas y el aviso de presiones se calculan sin esas horas. La capa de presión del geovisor NO cambia ----------
create table redes.presion_horas_no_confiables (
  escenario text not null check (escenario in ('existente', 'futura')),
  hora      integer not null check (hora between 0 and 24),      -- la hora del modelo (0 a 24): el valor horas[hora + 1] de redes.pm_presion_hora
  motivo    text not null check (length(btrim(motivo)) between 10 and 300),
  activa    boolean not null default true,      -- para volver a contar una hora: activa = false (no se borra)
  creado_en timestamptz not null default clock_timestamp(),
  primary key (escenario, hora)
);
insert into redes.presion_horas_no_confiables (escenario, hora, motivo)
select 'existente', h, 'El modelo de la red existente (modeloV1, Plan Maestro 2014) colapsa a esta hora: presiones no confiables (Fase 0 del Corte 9b)' from unnest(array[5, 7, 10, 12, 14]) h;
create trigger t_no_borrar before delete on redes.presion_horas_no_confiables for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on redes.presion_horas_no_confiables for each statement execute function tecnica.f_solo_agregar();
comment on table redes.presion_horas_no_confiables is 'Corte 9b (Fase 2): horas del día en que la presión del modelo no es confiable; las alertas y el aviso de presiones no las cuentan. No se borra: activa = false.';

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
  foreach t in array array['tipos_sensible', 'usuarios_sensibles', 'usuario_sensible_eventos', 'presion_trabajo', 'presion_horas_no_confiables', 'sensor_lecturas'] loop
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
-- el aviso informativo de presiones sale APAGADO (David, 17-nov): lo enciende Técnica cuando lo revise, en los parámetros de Avisos (0 apagado, 1 encendido)
insert into tecnica.aviso_parametros (clave, area, valor, minimo, maximo, unidad, orden, nombre, descripcion) values
  ('presion_modelo_aviso', 'distribucion', 0, 0, 1, '(0 no, 1 sí)', 175, 'Aviso de presiones del modelo',
   '0: apagado. 1: encendido. Encendido, sale un aviso informativo con los nodos fuera de rango según el modelo (presión de modelo, no medida; sin las horas en que el modelo no es confiable).')
on conflict (clave) do update set valor = 0, descripcion = excluded.descripcion;

-- ---------- 5. La capa «Cortes programados vigentes» se OCULTA de la lista de capas (David, 17-nov): ahora vive en el modo «Afectaciones». No se borra ----------
update redes.geovisor_capas set activa = false, nota = 'Oculta el 17-nov-2026 (Corte 9b): los cortes vigentes se ven en el modo «Afectaciones» del geovisor'
 where codigo = 'cortes';
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 20 — FUNCIONES INTERNAS. PROPUESTA. Solo agrega (no reemplaza nada).
-- · Alertas de presión (§30.7, Res. 0330 de 2017, arts. 61 y 62): con los 4 parámetros del 9a (15 y 10 m.c.a. de mínima; 50 y 60 de máxima) sobre la presión
--   de MODELO por nodo (redes.pm_nodos, carga vigente; red existente o futura). Y por material: nodos cuya presión máxima pasa la presión de trabajo de un tramo
--   que llega a ellos. Es presión de modelo, no medida: así se rotula. La mínima y la máxima del día se toman SOLO de las horas confiables del modelo
--   (redes.f_presion_nodos: sin las horas de redes.presion_horas_no_confiables), lo mismo en las alertas y en el aviso, para que den el mismo número.
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

-- ---------- presión mínima y máxima del día por nodo, SOLO con las horas confiables del modelo (David, 17-nov) ----------
-- Si el escenario tiene horas no confiables y el nodo tiene sus presiones por hora (redes.pm_presion_hora, carga vigente): mínima y máxima de las demás horas.
-- Si no (escenario sin horas excluidas, o nodo sin presiones por hora): la mínima y la máxima del día de redes.pm_nodos, como antes.
create function redes.f_presion_nodos(p_escenario text) returns table (llave text, p_min numeric, p_max numeric)
language sql stable security definer set search_path = redes, pg_temp as $$
  with ex as (select array_agg(h.hora) as hs from redes.presion_horas_no_confiables h where h.escenario = p_escenario and h.activa)
  select x.llave,
         case when ph.llave is not null then c.p_min when p_escenario = 'futura' then x.pres_futura_min else x.pres_exist_min end,
         case when ph.llave is not null then c.p_max when p_escenario = 'futura' then x.pres_futura_max else x.pres_exist_max end
    from redes.pm_nodos x
    left join redes.pm_presion_hora ph on (select hs from ex) is not null and ph.carga_id = redes.f_ref_vigente('pm_presion_' || p_escenario) and ph.llave = x.llave
    left join lateral (select min(u.v) as p_min, max(u.v) as p_max from unnest(ph.horas) with ordinality u(v, o) where (u.o - 1)::integer <> all ((select hs from ex)::integer[])) c on ph.llave is not null
   where x.carga_id = redes.f_ref_vigente('pm_nodos') $$;
comment on function redes.f_presion_nodos(text) is 'Corte 9b (Fase 2): presión de modelo mínima y máxima por nodo, sin las horas no confiables (redes.presion_horas_no_confiables). La usan las alertas y el aviso de presiones.';

-- ---------- las alertas de presión de un escenario (existente | futura): conteos por nivel, los peores nodos y la alerta por material ----------
create function redes.f_alertas_presion(p_escenario text) returns jsonb
language plpgsql stable security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_c bigint := redes.f_ref_vigente('pm_nodos'); v_hs integer[]; v_lim integer := coalesce(redes.f_param('presion_lista_max'), 50)::integer; v_fut boolean := p_escenario = 'futura'; j jsonb;
  -- los 4 umbrales se leen UNA vez (la misma regla de redes.f_presion_nivel; por nodo costaba 4 lecturas de parámetros)
  v_bn numeric := redes.f_param('presion_baja_naranja_mca'); v_br numeric := redes.f_param('presion_baja_roja_mca');
  v_an numeric := redes.f_param('presion_alta_naranja_mca'); v_ar numeric := redes.f_param('presion_alta_roja_mca');
begin
  if p_escenario not in ('existente', 'futura') then perform tecnica.f_error('El escenario es «existente» o «futura»'); end if;
  if v_c is null then return jsonb_build_object('cargado', false, 'escenario', p_escenario); end if;
  select array_agg(h.hora order by h.hora) into v_hs from redes.presion_horas_no_confiables h where h.escenario = p_escenario and h.activa;
  with n as (      -- la mínima y la máxima, solo de las horas confiables
    select x.llave, coalesce(x.nombre, x.llave) as nombre, x.zona_modelo, x.geom, p.p_min, p.p_max
      from redes.pm_nodos x join redes.f_presion_nodos(p_escenario) p on p.llave = x.llave where x.carga_id = v_c),
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
    'horas_excluidas', coalesce(to_jsonb(v_hs), '[]'::jsonb),
    'nota_horas', case when v_hs is not null then format('Mínima y máxima del día sin las horas en que el modelo no es confiable (%s).', array_to_string(v_hs, ', ')) end,
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

-- ---------- los nodos fuera de rango por nivel (red existente, horas confiables): la suma es el número del aviso informativo de tecnica.f_avisos (D11) ----------
create function redes.f_presion_para_avisos() returns table (nivel text, n bigint)
language sql stable security definer set search_path = redes, pg_temp as $$
  with u as materialized (select redes.f_param('presion_baja_naranja_mca') as bn, redes.f_param('presion_baja_roja_mca') as br,      -- los 4 umbrales, una vez
                                 redes.f_param('presion_alta_naranja_mca') as an, redes.f_param('presion_alta_roja_mca') as ar)
  select y.nivel, count(*)
    from (select case when x.p_min < u.br then 'baja_roja' when x.p_max > u.ar then 'alta_roja' when x.p_min < u.bn then 'baja_naranja' when x.p_max > u.an then 'alta_naranja' end as nivel
            from redes.f_presion_nodos('existente') x cross join u) y
   where y.nivel is not null group by 1 $$;

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
-- «N nodos fuera de rango según el modelo» (David, 17-nov: ni rojo ni naranja; APAGADO por omisión, parámetro «presion_modelo_aviso»; solo horas confiables).
-- Lo demás queda igual. AVISADO al Code B en la entrada de bitácora.
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

  -- D11 (Corte 9b, Fase 2). Presión de MODELO fuera de rango (Res. 0330 de 2017): un solo aviso informativo. APAGADO por omisión: solo sale si el
  -- parámetro «presion_modelo_aviso» vale 1 (lo enciende Técnica). Solo con las horas confiables del modelo (redes.f_presion_nodos). Los umbrales se leen una vez
  if p_distribucion and coalesce(tecnica.f_aparam('presion_modelo_aviso'), 0) >= 1 then
    v_x := redes.f_param('presion_baja_naranja_mca'); v_y := redes.f_param('presion_alta_naranja_mca');
    select count(*) into v_n from redes.f_presion_nodos('existente') x where x.p_min < v_x or x.p_max > v_y;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'presion_modelo', 'area', 'distribucion', 'nivel', 'info', 'orden', 175,
                'titulo', format('%s %s fuera de rango según el modelo', tecnica.f_texto_num(v_n), case when v_n = 1 then 'nodo' else 'nodos' end),      -- con punto de miles
                'detalle', format('Presión de modelo, no medida (Plan Maestro 2014): mínima bajo %s o máxima sobre %s m.c.a., sin las horas en que el modelo no es confiable.', v_x, v_y),
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
--   · geoportal_redes_afectaciones_danos: TODOS los daños abiertos o en atención, sin límite de fecha, para el modo «Afectaciones» (supervisor y administrador).
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

-- todos los daños abiertos («reportado») o en atención, SIN límite de fecha (David, 17-nov): para el modo «Afectaciones» del geovisor. Supervisor y administrador.
-- La misma forma que la capa «danos» de geoportal_redes_geovisor_capa (las mismas propiedades), más «total». Acueducto y alcantarillado.
create function public.geoportal_redes_afectaciones_danos(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven todos los daños abiertos'); v_max integer := floor(redes.f_param('geovisor_max_elementos'))::integer;
        v_f jsonb; v_n integer;
begin
  with ab as materialized (      -- redes.v_dano se lee una sola vez
    select d.codigo, d.clase, d.tipo_nombre, d.sistema, d.estado, d.activo_codigo, d.t_detectado, d.riesgo, d.origen, d.lat, d.lon
      from redes.v_dano d where d.estado in ('reportado', 'en_atencion'))
  select coalesce((select jsonb_agg(x.f order by x.o desc, x.codigo) from (
           select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(ab.lon, ab.lat)),
                    'properties', jsonb_build_object('codigo', ab.codigo, 'clase', ab.clase, 'tipo', ab.tipo_nombre, 'sistema', ab.sistema, 'estado', ab.estado,
                                                     'activo', ab.activo_codigo, 'cuando', ab.t_detectado, 'riesgo', ab.riesgo, 'origen', ab.origen)) as f, ab.t_detectado as o, ab.codigo
             from ab order by ab.t_detectado desc, ab.codigo limit v_max) x), '[]'::jsonb),
         (select count(*) from ab)
    into v_f, v_n;
  return jsonb_build_object('type', 'FeatureCollection', 'capa', 'afectaciones_danos', 'total', v_n, 'recortada', v_n > v_max, 'features', v_f);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las 8 funciones internas: nadie de la API. Las 6 RPC: solo service_role (la Edge geoportal-redes). Las tablas y la vista: nadie de la API (10_esquema.sql).
-- =====================================================================
revoke all on function redes.f_presion_nivel(numeric, numeric), redes.f_presion_nodos(text), redes.f_alertas_presion(text), redes.f_presion_para_avisos(), redes.f_sensible_tipo(text), redes.f_sensibles_proponer(text),
                       redes.f_sensibles_en(text[]), redes.f_sensor_estado(bigint)
  from public, anon, authenticated, service_role;
revoke all on function tecnica.f_avisos(boolean, boolean, timestamptz) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_alertas_presion', 'geoportal_redes_sensibles', 'geoportal_redes_sensible_fijar',
                     'geoportal_redes_afectacion', 'geoportal_redes_sensores', 'geoportal_redes_afectaciones_danos') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9b_f2', 'migracion_redes_corte9b_fase2', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.tipos_sensible', 'redes.usuarios_sensibles', 'redes.usuario_sensible_eventos', 'redes.presion_trabajo', 'redes.presion_horas_no_confiables', 'redes.sensor_lecturas'),
        'vistas', jsonb_build_array('redes.v_usuario_sensible'),
        'nuevas', jsonb_build_array('redes.f_presion_nivel', 'redes.f_presion_nodos', 'redes.f_alertas_presion', 'redes.f_presion_para_avisos', 'redes.f_sensible_tipo', 'redes.f_sensibles_proponer', 'redes.f_sensibles_en',
                                    'redes.f_sensor_estado', 'geoportal_redes_alertas_presion', 'geoportal_redes_sensibles', 'geoportal_redes_sensible_fijar',
                                    'geoportal_redes_afectacion', 'geoportal_redes_sensores', 'geoportal_redes_afectaciones_danos'),
        'aviso_parametros', jsonb_build_array('presion_modelo_aviso (0: el aviso de presiones sale apagado)'),
        'parametros', jsonb_build_array('sensor_sin_senal_min', 'presion_lista_max'),
        'reemplazadas', jsonb_build_array('tecnica.f_avisos (aviso informativo de presiones, D11: apagado por omisión y solo con las horas confiables)'),
        'capa_oculta', 'cortes',
        'motivo', 'alertas de presión de modelo (Res. 0330 de 2017), con las horas confiables, usuarios sensibles, afectación del daño o la intervención, daños abiertos sin límite de fecha para el modo Afectaciones, lecturas de sensores (vacía) y la capa de cortes oculta (vive en el modo Afectaciones)'), null);
commit;
