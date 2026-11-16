begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 10 — GUARDIA Y ESQUEMA (integración del Plan Maestro 2014)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte9a_plan_maestro.md (16-nov) y regulatorio/salida_geoportal/LEEME.md.
-- · Presupone el Corte 7a publicado (huella del conjunto de funciones de redes 79f184a4fe37ed2baa67dac7f3dd9b3c).
-- · Todo lo del Plan Maestro va en tablas APARTE, de referencia: la ficha oficial del activo no cambia (ni «efecto», ni estado, ni diámetro).
--   Las tablas quedan vacías: se llenan con el paquete de carga por psql (carga_pm/), cada archivo con su md5.
-- · Los datos de referencia se guardan por carga (redes.ref_cargas); vale la última carga no anulada de cada conjunto. Nada se borra.
-- · El sector y el subsector de un activo, nodo, contrato, daño o intervención NO se guardan: se calculan por geometría contra los polígonos
--   vigentes de la capa «sectores» (activos SEC) cada vez que se leen. Si se carga otra versión de los polígonos, cambian solos.
-- · ⚠ Cambia la vista redes.v_nodo_vigente (mismas columnas) y el CHECK del tipo de redes.nodo_eventos; la reversa los devuelve.
-- =====================================================================
do $$
begin
  if to_regclass('redes.ref_cargas') is not null then raise exception 'El Corte 9a ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '79f184a4fe37ed2baa67dac7f3dd9b3c' then
    raise exception 'Las funciones de redes no son las del Corte 7a publicado (huella 79f184a4fe37ed2baa67dac7f3dd9b3c): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_nodo_vigente'::regclass)) <> '8085cfdb298ca64d3c7d787ccf05f8fe' then
    raise exception 'La vista redes.v_nodo_vigente no es la del Corte 1a: deténgase y avise';
  end if;
  if not exists (select 1 from redes.capas where codigo = 'sectores' and prefijo = 'SEC' and fuente = 'carga' and activa)
     or not exists (select 1 from redes.capas where codigo = 'sumideros' and prefijo = 'SUM' and fuente = 'carga' and activa)
     or not exists (select 1 from redes.geovisor_capas where codigo = 'sectores' and fuente = 'tesela') then
    raise exception 'Faltan las capas «sectores» o «sumideros» del Cargue (Corte 5c) o la capa de sectores del geovisor (Corte 6a): deténgase y avise';
  end if;
end $$;

-- ---------- 1. Registro de las cargas de referencia ----------
create table redes.ref_cargas (
  id        bigint generated always as identity primary key,
  conjunto  text not null check (conjunto ~ '^[a-z][a-z0-9_]{2,39}$'),
  archivo   text not null check (length(archivo) between 1 and 200),
  md5       text not null check (md5 ~ '^[0-9a-f]{32}$'),
  filas     integer not null check (filas >= 0),
  origen    text not null check (length(btrim(origen)) between 3 and 300),
  nota      text check (nota is null or length(nota) <= 500),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
create index ix_ref_cargas_conjunto on redes.ref_cargas (conjunto, id desc);
comment on table redes.ref_cargas is 'Corte 9a: una fila por archivo de referencia cargado (Plan Maestro 2014). Solo inserción. Vale la última no anulada de cada conjunto.';
create table redes.ref_carga_eventos (
  id        bigint generated always as identity primary key,
  carga_id  bigint not null references redes.ref_cargas (id),
  tipo      text not null check (tipo in ('anular')),
  motivo    text not null check (length(btrim(motivo)) between 10 and 1000),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
create index ix_ref_carga_eventos on redes.ref_carga_eventos (carga_id);
create view redes.v_ref_carga_vigente as
  select distinct on (c.conjunto) c.id, c.conjunto, c.archivo, c.md5, c.filas, c.origen, c.nota, c.autor, c.creado_en
    from redes.ref_cargas c
   where not exists (select 1 from redes.ref_carga_eventos e where e.carga_id = c.id and e.tipo = 'anular')
   order by c.conjunto, c.id desc;

-- ---------- 2. Acueducto: lo que dice el modelo, por nodo, por tramo y por válvula (llave = la del modelo, la misma de la capa) ----------
create table redes.pm_nodos (
  carga_id           bigint not null references redes.ref_cargas (id),
  llave              text not null check (length(llave) between 1 and 120),      -- = redes.nodos.llave_modelo y activo_versiones.llave_capa (capa acueducto_nodos)
  nombre             text,
  tipo               text,          -- unión, válvula, hidrante, tanque, fuente
  que_es             text,          -- lectura del análisis: «válvula de sectorización propuesta (no instalada)», «nodo de cálculo J-…»…
  zona_modelo        text,
  nota_modelo        text,
  activo_modelo      boolean,
  estado_modelo      text,          -- estado que sugiere el modelo (en_operacion, proyectado, fuera_servicio)
  estado_difiere     boolean not null default false,      -- distinto del estado del geoportal el día del análisis
  cota_m             numeric,
  n_tramos           integer,
  demanda_exist_lps  numeric,
  demanda_futura_lps numeric,
  emisor_fuga        boolean,
  pres_exist_min     numeric, pres_exist_max numeric, pres_exist_media numeric, pres_exist_mediana numeric, pres_exist_negativa boolean,
  pres_futura_min    numeric, pres_futura_max numeric, pres_futura_media numeric, pres_futura_mediana numeric,
  geom               geometry(Point, 4326) not null,
  primary key (carga_id, llave)
);
create index ix_pm_nodos_geom on redes.pm_nodos using gist (geom);
create index ix_pm_nodos_llave on redes.pm_nodos (llave, carga_id desc);
comment on table redes.pm_nodos is 'Corte 9a: nodos del modelo hidráulico del Plan Maestro 2014 (ModeloVF y modeloV1). REFERENCIA: la presión es de MODELO, no medida.';
create table redes.pm_tramos (
  carga_id         bigint not null references redes.ref_cargas (id),
  llave            text not null check (length(llave) between 1 and 120),      -- = ID del modelo = llave_capa de la capa «acueducto»
  clase_red        text,          -- existente activo, inactivo (fuera de servicio), obra SIVA (tercero), proyectado Plan Maestro
  nota_modelo      text,
  zona_modelo      text,
  activo_modelo    boolean,
  estado_modelo    text,
  estado_difiere   boolean not null default false,
  frontera_sectores boolean,
  q_max_futuro_lps numeric,
  v_max_futuro_mps numeric,
  primary key (carga_id, llave)
);
create index ix_pm_tramos_llave on redes.pm_tramos (llave, carga_id desc);
create table redes.pm_valvulas (
  carga_id              bigint not null references redes.ref_cargas (id),
  llave                 text not null check (length(llave) between 1 and 120),
  nombre                text,
  estado_existente      text,     -- modeloV1 (red existente validada): el que manda para la red de hoy
  estado_futuro         text,     -- ModeloVF (red del Plan)
  difiere_entre_modelos boolean not null default false,
  estado_catastro       text,
  estado_contradictorio boolean not null default false,
  verificar_en_campo    boolean not null default false,
  efecto_sugerido       text,     -- SUGERENCIA del modelo; el campo oficial «efecto» lo llena el supervisor (§30.5)
  cierre_nodos_sin_agua integer,
  cierre_demanda_lps    numeric,
  diametro_mm           numeric,
  primary key (carga_id, llave)
);
create index ix_pm_valvulas_llave on redes.pm_valvulas (llave, carga_id desc);
create table redes.pm_presion_hora (
  carga_id  bigint not null references redes.ref_cargas (id),
  llave     text not null check (length(llave) between 1 and 120),
  escenario text not null check (escenario in ('existente', 'futura')),
  p_min     numeric, hora_min numeric, p_max numeric, hora_max numeric, p_media numeric, p_mediana numeric,
  horas     numeric[] not null check (cardinality(horas) = 25),      -- hora 0 a hora 24, en m.c.a.
  primary key (carga_id, llave)
);
create index ix_pm_presion_llave on redes.pm_presion_hora (llave, escenario, carga_id desc);
comment on table redes.pm_presion_hora is 'Corte 9a: presión de MODELO por nodo y hora (existente = modeloV1 validado; futura = ModeloVF «POTs Combinados»). Referencia, no medición.';

-- ---------- 3. Alcantarillado: lo que aporta el catastro levantado de 2014 sobre la Alternativa 1 (que sigue siendo la base) ----------
create table redes.pm_alc_conductos (
  carga_id              bigint not null references redes.ref_cargas (id),
  llave                 text not null check (length(llave) between 1 and 120),      -- LABEL de la capa alc_conductos
  origen                text,     -- misma etiqueta, heredado del conducto que lo contiene, sin catastro (proyectado)
  cod_tubo_catastro     text,
  material              text,
  diametro_mm           numeric,
  diametro_nominal_pulg numeric,
  estado_fisico         text,
  estado_operacional    text,
  tipo_red              text,
  prof_inicial_m        numeric,
  prof_final_m          numeric,
  datos                 jsonb not null default '[]'::jsonb check (jsonb_typeof(datos) = 'array'),      -- lo demás, ya rotulado: [{"r": rótulo, "v": valor}]
  primary key (carga_id, llave)
);
create index ix_pm_alc_conductos_llave on redes.pm_alc_conductos (llave, carga_id desc);
create table redes.pm_alc_pozos (
  carga_id         bigint not null references redes.ref_cargas (id),
  llave            text not null check (length(llave) between 1 and 120),      -- LABEL de la capa alc_pozos
  familia          text,
  en_catastro      boolean,
  verificacion     text,
  por_verificar    boolean not null default false,      -- MHP, MH y MHONE: existentes en la Alternativa 1 que no están en el catastro levantado
  estado_pozo      text,
  profundidad_m    numeric,
  fecha_inspeccion date,
  datos            jsonb not null default '[]'::jsonb check (jsonb_typeof(datos) = 'array'),
  primary key (carga_id, llave)
);
create index ix_pm_alc_pozos_llave on redes.pm_alc_pozos (llave, carga_id desc);

-- ---------- 4. Capas de referencia (NO son activos): válvulas propuestas, campaña 2014, pluvial existente y alternativa 2043 ----------
create table redes.ref_elementos (
  carga_id bigint not null references redes.ref_cargas (id),
  capa     text not null check (capa ~ '^[a-z][a-z0-9_]{2,39}$'),      -- la capa del geovisor a la que pertenece
  llave    text not null check (length(llave) between 1 and 120),
  nombre   text,
  clase    text,
  estado   text,
  valor    numeric,
  datos    jsonb not null default '[]'::jsonb check (jsonb_typeof(datos) = 'array'),      -- la tarjeta, ya rotulada: [{"r": rótulo, "v": valor}]
  geom     geometry(Geometry, 4326),      -- nulo: sin coordenada (el punto 6 de la campaña)
  primary key (carga_id, llave)
);
create index ix_ref_elementos_geom on redes.ref_elementos using gist (geom);
create index ix_ref_elementos_capa on redes.ref_elementos (capa, llave, carga_id desc);
comment on table redes.ref_elementos is 'Corte 9a: elementos de las capas de referencia del geovisor. No son activos, no tienen ficha y quedan fuera de cualquier simulación.';
create table redes.pm_campana_lecturas (
  carga_id bigint not null references redes.ref_cargas (id),
  llave    text not null check (length(llave) between 1 and 120),      -- CAMP2014-P01…
  n        integer not null,
  cuando   timestamp not null,      -- hora local de Valledupar, como viene en los archivos de la campaña
  p_mca    numeric not null,
  primary key (carga_id, llave, n)
);
comment on table redes.pm_campana_lecturas is 'Corte 9a: campaña de presiones de 2014 (31-ene a 8-feb), lecturas cada 15 min. Es la única presión MEDIDA.';

do $$
declare t text;
begin
  foreach t in array array['ref_cargas', 'ref_carga_eventos', 'pm_nodos', 'pm_tramos', 'pm_valvulas', 'pm_presion_hora', 'pm_alc_conductos', 'pm_alc_pozos', 'ref_elementos', 'pm_campana_lecturas'] loop
    execute format('alter table redes.%I enable row level security', t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', t);
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
end $$;
revoke all on table redes.v_ref_carga_vigente from public, anon, authenticated, service_role;

-- ---------- 5. Nodos por clasificar: el supervisor puede confirmar «dejar como nodo» o «propuesto por el Plan: no crear activo» ----------
alter table redes.nodo_eventos add column clase text;
alter table redes.nodo_eventos drop constraint nodo_eventos_tipo_check;
alter table redes.nodo_eventos add constraint nodo_eventos_tipo_check check (tipo in ('enlazar_activo', 'desenlazar', 'nota', 'clasificar'));
alter table redes.nodo_eventos add constraint nodo_eventos_clase_check
  check ((tipo = 'clasificar') = (clase is not null) and (clase is null or clase in ('nodo_calculo', 'propuesta_plan', 'por_clasificar')));
comment on column redes.nodo_eventos.clase is 'Corte 9a: en un evento «clasificar», cómo queda el nodo sin crear activo (nodo_calculo, propuesta_plan) o si vuelve a la bandeja (por_clasificar).';
-- la misma vista del 1a, con el evento «clasificar»: mismas columnas y mismo orden
create or replace view redes.v_nodo_vigente as
 select n.id as nodo_id, n.sistema, n.llave_modelo, n.nombre_modelo, n.geom, n.dispersion_m, n.carga_id, n.creado_en,
        case when ev.tipo = 'enlazar_activo' then ev.activo_id when ev.tipo in ('desenlazar', 'clasificar') then null::bigint else n.activo_id end as activo_id,
        case when ev.tipo = 'enlazar_activo' then 'activo'::text
             when ev.tipo = 'clasificar' then ev.clase
             when ev.tipo = 'desenlazar' and n.clase_nodo = 'activo' then 'por_clasificar'::text
             else n.clase_nodo end as clase_nodo
   from (select distinct on (x.sistema, x.llave_modelo) x.id, x.sistema, x.llave_modelo, x.nombre_modelo, x.clase_nodo, x.geom, x.activo_id, x.dispersion_m, x.carga_id, x.creado_en
           from redes.nodos x
          where not exists (select 1 from redes.carga_eventos e where e.carga_id = x.carga_id and e.tipo = 'revertir')
          order by x.sistema, x.llave_modelo, x.id desc) n
   left join lateral (select ne.tipo, ne.activo_id, ne.clase from redes.nodo_eventos ne
                       where ne.nodo_id = n.id and ne.tipo in ('enlazar_activo', 'desenlazar', 'clasificar') order by ne.id desc limit 1) ev on true;

-- ---------- 6. Catálogos ----------
insert into redes.clases_activo (prefijo, codigo, nombre, activo, orden) values ('SEC', 'sector', 'Sector', true, 1), ('SEC', 'subsector', 'Subsector', true, 2)
on conflict (prefijo, codigo) do update set activo = true;
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('presion_baja_naranja_mca', 15, 'm.c.a.', 0, 100, 'Presión: por debajo de este valor, naranja (§30.7; Res. 0330 de 2017, art. 61). En el 9a colorea las capas de referencia; las alertas llegan con el 9b'),
  ('presion_baja_roja_mca', 10, 'm.c.a.', 0, 100, 'Presión: por debajo de este valor, roja (§30.7)'),
  ('presion_alta_naranja_mca', 50, 'm.c.a.', 10, 300, 'Presión: por encima de este valor, naranja (§30.7; Res. 0330 de 2017, art. 62)'),
  ('presion_alta_roja_mca', 60, 'm.c.a.', 10, 300, 'Presión: por encima de este valor, roja (§30.7)')
on conflict (clave) do nothing;

-- capas del geovisor: una fuente nueva, «referencia» (tesela propia; no son activos)
alter table redes.geovisor_capas drop constraint geovisor_capas_fuente_check;
alter table redes.geovisor_capas add constraint geovisor_capas_fuente_check check (fuente in ('tesela', 'geojson', 'preparada', 'contratos', 'referencia'));
update redes.geovisor_capas set nombre = 'Sectores hidráulicos (Plan Maestro 2014)', nota = 'Proyectados por el Plan Maestro 2014: 7 sectores y 29 subsectores. No son todavía los sectores con que se opera hoy'
 where codigo = 'sectores';
insert into redes.geovisor_capas (codigo, nombre, grupo, fuente, estado, prefijos, por_fecha, solo_completo, nota, orden) values
  ('plan_valvulas', 'Válvulas propuestas por el Plan (no instaladas)', 'acueducto', 'referencia', 'activa', '{}', false, true,
   'Plan Maestro 2014: 491 válvulas de sectorización PROPUESTAS. No son activos y no entran en ninguna simulación', 13),
  ('pluvial', 'Red pluvial existente', 'alcantarillado', 'referencia', 'activa', '{}', false, false,
   'Levantamiento de 2013 (Plan Maestro 2014): 686 conductos y 211 pozos. Capa de referencia: todavía no son activos', 22),
  ('pluvial_2043', 'Pluvial: alternativa a 2043 del Plan', 'alcantarillado', 'referencia', 'activa', '{}', false, true,
   'Plan Maestro 2014: lo existente y lo PROPUESTO a 2043. Capa de referencia', 23),
  ('presion_modelo', 'Presión de modelo (no medida)', 'analisis', 'referencia', 'activa', '{}', false, true,
   'Presión de MODELO, no medida: mediana del día del modelo de la red existente (Plan Maestro 2014). El modelo da presión negativa en muchos nodos de día', 78),
  ('campana_2014', 'Campaña de presiones 2014 (medida)', 'analisis', 'referencia', 'activa', '{}', false, true,
   'La única presión MEDIDA: 11 puntos, cada 15 min, del 31-ene al 8-feb-2014. Al tocar un punto, su gráfica', 79)
on conflict (codigo) do update set nombre = excluded.nombre, grupo = excluded.grupo, fuente = excluded.fuente, estado = excluded.estado, solo_completo = excluded.solo_completo,
  nota = excluded.nota, orden = excluded.orden, activa = true;
-- apagadas al abrir, salvo los sectores (encargo, punto 12)
insert into redes.capas_por_perfil (perfil, capa, encendida, actualizado_por) values
  ('supervisor_distribucion', 'sectores', true, 'migracion@redes_corte9a'), ('operador_distribucion', 'sectores', true, 'migracion@redes_corte9a')
on conflict (perfil, capa) do update set encendida = true, actualizado_en = clock_timestamp(), actualizado_por = excluded.actualizado_por;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 20 — FUNCIONES INTERNAS (nadie de la API las ejecuta)
--   · redes.f_sector_de: sector y subsector de un punto, tramo o polígono, POR GEOMETRÍA, contra los polígonos vigentes de la capa «sectores» (SEC).
--     No guarda nada: se calcula al leer, así que otra versión de los polígonos cambia el resultado sin recalcular tablas.
--   · redes.f_ref_vigente: la carga de referencia que vale para un conjunto (la última no anulada).
--   · redes.f_pm_nivel_presion: color de una presión frente a los umbrales de Parámetros (§30.7).
--   · redes.f_pm_sugerencia y redes.f_nodo_modelo: lo que dice el modelo de un nodo y la SUGERENCIA de clasificación (nada se clasifica solo).
--   · redes.f_ficha_referencia: los datos de referencia del Plan Maestro para la ficha de un activo, ya rotulados y por grupos.
--   · redes.v_pm_por_verificar y redes.f_pm_marcar_por_verificar: los activos que el Plan deja «por verificar» (estado distinto en el modelo,
--     válvulas por verificar en campo y pozos MHP, MH y MHONE) y la función que los marca (evento «por_verificar»; la corre el paquete de carga).
-- =====================================================================
create function redes.f_ref_vigente(p_conjunto text) returns bigint language sql stable set search_path = redes, pg_temp as $$
  select v.id from redes.v_ref_carga_vigente v where v.conjunto = p_conjunto $$;

create function redes.f_sector_de(p_geom geometry, out sector integer, out subsector text, out codigo text, out nombre text)
language plpgsql stable set search_path = redes, public, extensions, pg_temp as $$
declare v_pt geometry;
begin
  if p_geom is null then return; end if;
  v_pt := case when GeometryType(p_geom) = 'POINT' then p_geom else ST_PointOnSurface(p_geom) end;
  -- primero el subsector que contiene el punto; si no cae en ninguno, el sector. El número va en los atributos de la capa (columnas «sector» y «subsector»).
  select case when redes.f_num(v.atributos -> 'modelo' -> 'sector') between 1 and 100 then redes.f_num(v.atributos -> 'modelo' -> 'sector')::integer end,
         case when m.clase = 'subsector' then nullif(btrim(v.atributos -> 'modelo' ->> 'subsector'), '') end, m.codigo, m.nombre
    into sector, subsector, codigo, nombre
    from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
   where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.geom && v_pt and ST_Intersects(m.geom, v_pt)
   order by (m.clase = 'subsector') desc nulls last, ST_Area(m.geom), m.activo_id limit 1;
end $$;

create function redes.f_pm_nivel_presion(p_mca numeric) returns text language sql stable set search_path = redes, pg_temp as $$
  select case when p_mca is null then 'sin_dato'
              when p_mca < redes.f_param('presion_baja_roja_mca') then 'baja_roja'
              when p_mca < redes.f_param('presion_baja_naranja_mca') then 'baja_naranja'
              when p_mca > redes.f_param('presion_alta_roja_mca') then 'alta_roja'
              when p_mca > redes.f_param('presion_alta_naranja_mca') then 'alta_naranja'
              else 'normal' end $$;

-- La sugerencia de clasificación de un nodo «por clasificar», según lo que dice el modelo. Es solo una sugerencia: el supervisor la confirma.
create function redes.f_pm_sugerencia(p_tipo text, p_que_es text, p_nombre text, p_zona text) returns jsonb language sql immutable set search_path = pg_catalog as $$
  select case
    when p_tipo is null and p_que_es is null then null
    when p_tipo = 'tanque' and coalesce(p_zona, '') <> 'Proyectado' and p_nombre !~* 'proyectado' then
      jsonb_build_object('accion', 'crear', 'prefijo', 'TAN', 'texto', 'Tanque existente (' || p_nombre || '): crear el activo TAN')
    when p_tipo = 'tanque' then
      jsonb_build_object('accion', 'no_crear', 'clase', 'propuesta_plan', 'texto', 'Tanque proyectado por el Plan (no construido): no crear activo')
    when p_que_es like 'válvula de sectorización propuesta%' then
      jsonb_build_object('accion', 'no_crear', 'clase', 'propuesta_plan', 'texto', 'Válvula propuesta por el Plan (no instalada): no crear activo')
    when p_que_es = 'macromedidor proyectado' then
      jsonb_build_object('accion', 'no_crear', 'clase', 'propuesta_plan', 'texto', 'Macromedidor proyectado por el Plan (no instalado): no crear activo')
    when p_que_es like 'nodo de cálculo%' then
      jsonb_build_object('accion', 'dejar_nodo', 'clase', 'nodo_calculo', 'texto', 'Nodo de cálculo del modelo: dejar como nodo')
    when p_que_es like 'unión corriente%' then
      jsonb_build_object('accion', 'dejar_nodo', 'clase', 'nodo_calculo', 'texto', 'Unión corriente del modelo (sin accesorio que inventariar): dejar como nodo')
    when p_tipo = 'hidrante' then
      jsonb_build_object('accion', 'crear', 'prefijo', 'TOR', 'texto', 'Hidrante en el modelo: si existe en campo, crear el activo (Torre = hidrante)')
    else jsonb_build_object('accion', 'revisar', 'texto', 'Sin sugerencia: revisar en campo') end $$;

create function redes.f_nodo_modelo(p_llave text) returns jsonb language sql stable set search_path = redes, public, extensions, pg_temp as $$
  select jsonb_strip_nulls(jsonb_build_object('tipo', n.tipo, 'que_es', n.que_es, 'zona', n.zona_modelo, 'nota', n.nota_modelo, 'activo_en_modelo', n.activo_modelo,
           'estado_modelo', n.estado_modelo, 'cota_m', n.cota_m, 'demanda_exist_lps', n.demanda_exist_lps, 'demanda_futura_lps', n.demanda_futura_lps,
           'pres_exist_mediana', n.pres_exist_mediana, 'pres_exist_min', n.pres_exist_min, 'pres_exist_max', n.pres_exist_max,
           'pres_futura_mediana', n.pres_futura_mediana, 'pres_futura_min', n.pres_futura_min, 'pres_futura_max', n.pres_futura_max,
           'sugerencia', redes.f_pm_sugerencia(n.tipo, n.que_es, n.nombre, n.zona_modelo)))
    from redes.pm_nodos n where n.llave = p_llave and n.carga_id = redes.f_ref_vigente('pm_nodos') $$;

-- Datos de referencia para la ficha. Devuelve una lista de grupos: {titulo, origen, advertencia, filas: [{r, v, u}]}. Solo las filas con valor.
create function redes.f_ficha_referencia(p_activo bigint) returns jsonb language plpgsql stable set search_path = redes, public, extensions, pg_temp as $$
declare
  v redes.v_activo_vigente%rowtype; v_llave text; v_grupos jsonb := '[]'::jsonb; v_f jsonb;
  n redes.pm_nodos%rowtype; t redes.pm_tramos%rowtype; w redes.pm_valvulas%rowtype; c redes.pm_alc_conductos%rowtype; z redes.pm_alc_pozos%rowtype;
  v_org text;
begin
  select * into v from redes.v_activo_vigente where activo_id = p_activo;
  if not found then return v_grupos; end if;
  -- el activo creado desde un nodo «por clasificar» (el tanque La Popa) no lleva capa: su llave del modelo está en los atributos
  v_llave := case when v.capa_codigo = 'acueducto_nodos' then v.llave_capa else v.atributos ->> 'creado_desde_nodo' end;

  if v_llave is not null and v.sistema = 'acueducto' and GeometryType(v.geom) = 'POINT' then
    select * into n from redes.pm_nodos x where x.llave = v_llave and x.carga_id = redes.f_ref_vigente('pm_nodos');
    if found then
      select origen into v_org from redes.ref_cargas where id = n.carga_id;
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'Tipo en el modelo', to_jsonb(n.tipo), null), (2, 'Lectura del modelo', to_jsonb(nullif(n.que_es, 'otro')), null), (3, 'Zona del modelo', to_jsonb(n.zona_modelo), null),
        (4, 'Nota del modelo', to_jsonb(n.nota_modelo), null),
        (5, 'Estado según el modelo', to_jsonb((select e.nombre from redes.estados_activo e where e.codigo = n.estado_modelo)), null),
        (6, 'Cota', to_jsonb(n.cota_m), 'm'), (7, 'Demanda (red existente)', to_jsonb(n.demanda_exist_lps), 'L/s'), (8, 'Demanda (red futura del Plan)', to_jsonb(n.demanda_futura_lps), 'L/s')
      ) f(o, r, v, u);
      if jsonb_array_length(v_f) > 0 then
        v_grupos := v_grupos || jsonb_build_object('titulo', 'Modelo hidráulico', 'origen', v_org, 'filas', v_f,
          'advertencia', case when n.estado_difiere then 'El estado del modelo es distinto del estado de la ficha: por verificar en campo.' end);
      end if;
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'Red existente: mediana del día', to_jsonb(n.pres_exist_mediana), 'm.c.a.'), (2, 'Red existente: mínima', to_jsonb(n.pres_exist_min), 'm.c.a.'),
        (3, 'Red existente: máxima', to_jsonb(n.pres_exist_max), 'm.c.a.'),
        (4, 'Red futura del Plan: mediana', to_jsonb(n.pres_futura_mediana), 'm.c.a.'), (5, 'Red futura del Plan: mínima', to_jsonb(n.pres_futura_min), 'm.c.a.'),
        (6, 'Red futura del Plan: máxima', to_jsonb(n.pres_futura_max), 'm.c.a.')
      ) f(o, r, v, u);
      if jsonb_array_length(v_f) > 0 then
        v_grupos := v_grupos || jsonb_build_object('titulo', 'Presión de modelo', 'origen', v_org, 'filas', v_f,
          'advertencia', 'Presión de MODELO, no medida.' || case when n.pres_exist_negativa then ' El modelo de la red existente da presión negativa en este nodo a alguna hora.' else '' end);
      end if;
    end if;
    select * into w from redes.pm_valvulas x where x.llave = v_llave and x.carga_id = redes.f_ref_vigente('pm_valvulas');
    if found then
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'Efecto sugerido por el modelo', to_jsonb(w.efecto_sugerido), null),
        (2, 'Si se cierra sola: nodos sin agua', to_jsonb(w.cierre_nodos_sin_agua), null), (3, 'Si se cierra sola: demanda sin agua', to_jsonb(w.cierre_demanda_lps), 'L/s'),
        (4, 'Estado en la red existente (modeloV1)', to_jsonb(w.estado_existente), null), (5, 'Estado en la red futura (ModeloVF)', to_jsonb(w.estado_futuro), null),
        (6, 'Estado en el catastro de 2014', to_jsonb(w.estado_catastro), null),
        (7, 'Los dos modelos difieren', case when w.difiere_entre_modelos then to_jsonb('Sí'::text) end, null),
        (8, 'Modelo y catastro se contradicen', case when w.estado_contradictorio then to_jsonb('Sí'::text) end, null)
      ) f(o, r, v, u);
      v_grupos := v_grupos || jsonb_build_object('titulo', 'Válvula: sugerencia del modelo', 'origen', (select origen from redes.ref_cargas where id = w.carga_id), 'filas', v_f,
        'advertencia', 'Es una sugerencia. El «Efecto en la red» oficial lo define el supervisor de distribución en la ficha.'
                       || case when w.verificar_en_campo then ' Estado por verificar en campo.' else '' end);
    end if;
  elsif v.capa_codigo = 'acueducto' then
    select * into t from redes.pm_tramos x where x.llave = v.llave_capa and x.carga_id = redes.f_ref_vigente('pm_tramos');
    if found then
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'Clase de red', to_jsonb(t.clase_red), null), (2, 'Nota del modelo', to_jsonb(t.nota_modelo), null), (3, 'Zona del modelo', to_jsonb(t.zona_modelo), null),
        (4, 'Estado según el modelo', to_jsonb((select e.nombre from redes.estados_activo e where e.codigo = t.estado_modelo)), null),
        (5, 'Cruza la frontera entre sectores', case when t.frontera_sectores then to_jsonb('Sí'::text) end, null),
        (6, 'Caudal máximo (red futura del Plan)', to_jsonb(t.q_max_futuro_lps), 'L/s'), (7, 'Velocidad máxima (red futura del Plan)', to_jsonb(t.v_max_futuro_mps), 'm/s')
      ) f(o, r, v, u);
      v_grupos := v_grupos || jsonb_build_object('titulo', 'Modelo hidráulico', 'origen', (select origen from redes.ref_cargas where id = t.carga_id), 'filas', v_f,
        'advertencia', case when t.estado_difiere then 'El estado del modelo es distinto del estado de la ficha: por verificar en campo.' end);
    end if;
  elsif v.capa_codigo = 'alc_conductos' then
    select * into c from redes.pm_alc_conductos x where x.llave = v.llave_capa and x.carga_id = redes.f_ref_vigente('pm_alc_conductos');
    if found then
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'Cómo se amarró', to_jsonb(c.origen), null), (2, 'Código en el catastro', to_jsonb(c.cod_tubo_catastro), null), (3, 'Material', to_jsonb(c.material), null),
        (4, 'Diámetro medido', to_jsonb(c.diametro_mm), 'mm'), (5, 'Diámetro nominal', to_jsonb(c.diametro_nominal_pulg), 'pulg'),
        (6, 'Estado físico', to_jsonb(c.estado_fisico), null), (7, 'Estado operacional', to_jsonb(c.estado_operacional), null), (8, 'Tipo de red', to_jsonb(c.tipo_red), null),
        (9, 'Profundidad inicial', to_jsonb(c.prof_inicial_m), 'm'), (10, 'Profundidad final', to_jsonb(c.prof_final_m), 'm')
      ) f(o, r, v, u);
      v_grupos := v_grupos || jsonb_build_object('titulo', 'Catastro de alcantarillado 2014', 'origen', (select origen from redes.ref_cargas where id = c.carga_id), 'filas', v_f || c.datos,
        'advertencia', case when c.cod_tubo_catastro is null then 'Sin datos del catastro levantado (conducto proyectado por el Plan).' end);
    end if;
  elsif v.capa_codigo = 'alc_pozos' then
    select * into z from redes.pm_alc_pozos x where x.llave = v.llave_capa and x.carga_id = redes.f_ref_vigente('pm_alc_pozos');
    if found then
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'En el catastro levantado', to_jsonb(case when z.en_catastro then 'Sí' else 'No' end), null), (2, 'Verificación', to_jsonb(z.verificacion), null),
        (3, 'Estado del pozo', to_jsonb(z.estado_pozo), null), (4, 'Profundidad', to_jsonb(z.profundidad_m), 'm'),
        (5, 'Fecha de inspección', to_jsonb(to_char(z.fecha_inspeccion, 'YYYY-MM-DD')), null)
      ) f(o, r, v, u);
      v_grupos := v_grupos || jsonb_build_object('titulo', 'Catastro de alcantarillado 2014', 'origen', (select origen from redes.ref_cargas where id = z.carga_id), 'filas', v_f || z.datos,
        'advertencia', case when z.por_verificar then 'Figura como existente en la Alternativa 1 del Plan y no está en el catastro levantado: por verificar en campo.' end);
    end if;
  end if;
  return (select coalesce(jsonb_agg(jsonb_strip_nulls(g) order by o), '[]'::jsonb) from jsonb_array_elements(v_grupos) with ordinality x(g, o));
end $$;

-- Lo que el Plan deja «por verificar», contra los activos vigentes (por la llave de su capa). Una fila por activo y motivo.
create view redes.v_pm_por_verificar as
  select m.activo_id, 'estado'::text as grupo,
         'el modelo lo da «' || coalesce((select e.nombre from redes.estados_activo e where e.codigo = n.estado_modelo), n.estado_modelo) || '» y la ficha «'
           || (select e.nombre from redes.estados_activo e where e.codigo = m.estado_codigo) || '»' as detalle
    from redes.pm_nodos n join redes.activo_vigente_mat m on m.capa_codigo = 'acueducto_nodos' and m.llave_capa = n.llave
   where n.carga_id = redes.f_ref_vigente('pm_nodos') and n.estado_difiere and not m.retirado and n.estado_modelo is distinct from m.estado_codigo
  union all
  select m.activo_id, 'estado', 'el modelo lo da «' || coalesce((select e.nombre from redes.estados_activo e where e.codigo = t.estado_modelo), t.estado_modelo) || '» y la ficha «'
           || (select e.nombre from redes.estados_activo e where e.codigo = m.estado_codigo) || '»'
    from redes.pm_tramos t join redes.activo_vigente_mat m on m.capa_codigo = 'acueducto' and m.llave_capa = t.llave
   where t.carga_id = redes.f_ref_vigente('pm_tramos') and t.estado_difiere and not m.retirado and t.estado_modelo is distinct from m.estado_codigo
  union all
  select m.activo_id, 'valvula', 'válvula con el estado por verificar en campo (modelo: ' || coalesce(w.estado_existente, 'sin dato') || '; catastro de 2014: ' || coalesce(w.estado_catastro, 'sin dato') || ')'
    from redes.pm_valvulas w join redes.activo_vigente_mat m on m.capa_codigo = 'acueducto_nodos' and m.llave_capa = w.llave
   where w.carga_id = redes.f_ref_vigente('pm_valvulas') and w.verificar_en_campo and not m.retirado
  union all
  select m.activo_id, 'pozo', 'pozo ' || coalesce(z.familia, '') || ' que figura como existente en la Alternativa 1 y no está en el catastro levantado'
    from redes.pm_alc_pozos z join redes.activo_vigente_mat m on m.capa_codigo = 'alc_pozos' and m.llave_capa = z.llave
   where z.carga_id = redes.f_ref_vigente('pm_alc_pozos') and z.por_verificar and not m.retirado;
revoke all on table redes.v_pm_por_verificar from public, anon, authenticated, service_role;

-- Marca «por verificar» (evento con motivo; nada cambia en la ficha) a los activos de la vista que no tengan ya una marca del Plan. No repite:
-- a quien el supervisor ya verificó no se le vuelve a marcar. La corre el paquete de carga, una vez, con el correo del administrador.
create function redes.f_pm_marcar_por_verificar(p_autor text) returns integer language plpgsql set search_path = redes, public, pg_temp as $$
declare v_n integer;
begin
  if p_autor is null or position('@' in p_autor) < 2 then perform tecnica.f_error('Falta quién marca'); end if;
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor)
  select x.activo_id, 'por_verificar', left('Plan Maestro 2014: ' || string_agg(x.detalle, '; ' order by x.grupo), 1000), p_autor
    from redes.v_pm_por_verificar x
   where not exists (select 1 from redes.activo_eventos e where e.activo_id = x.activo_id and e.tipo = 'por_verificar' and e.motivo like 'Plan Maestro 2014:%')
   group by x.activo_id;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 26 — RPC NUEVAS (solo service_role: la Edge geoportal-redes). Todas leen, salvo nodo_clasificar y activo_verificar,
-- que insertan UN evento con motivo. Ninguna rehace ni recalcula tablas.
--   · geoportal_redes_geovisor_mvt_ref: tesela de una capa de referencia del geovisor (fuente «referencia»).
--   · geoportal_redes_referencia: la tarjeta de un elemento de referencia (con la serie de la campaña o el perfil horario del modelo).
--   · geoportal_redes_nodo_preliminar: ficha preliminar, de solo lectura, de un nodo «por clasificar» (encargo, punto 13).
--   · geoportal_redes_nodo_clasificar: el administrador confirma «dejar como nodo» o «propuesto por el Plan: no crear activo» (o lo devuelve a la bandeja).
--   · geoportal_redes_por_verificar y geoportal_redes_activo_verificar: la bandeja «Por verificar» del supervisor y la marca «verificado», con lo que se encontró.
-- =====================================================================
create function public.geoportal_redes_geovisor_mvt_ref(p_solicitante text, p_capa text, p_z integer, p_x integer, p_y integer) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; g redes.geovisor_capas%rowtype; v_env geometry; v_env4 geometry; v bytea;
        z_min numeric := redes.f_param('geovisor_zoom_min'); z_nod numeric := redes.f_param('geovisor_zoom_nodos');
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into g from redes.geovisor_capas where codigo = p_capa and activa and fuente = 'referencia';
  if not found then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if g.solo_completo and not a.completo then raise exception 'Capa solo para supervisores' using errcode = '42501'; end if;
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < z_min then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4 := ST_Transform(v_env, 4326);
  if p_capa = 'presion_modelo' then
    -- un punto por nodo con presión de la red existente. De lejos, solo los nodos que son activo «grande» no se distinguen: se muestran todos desde el zoom de nodos
    -- y, antes, uno de cada cuatro (por su llave), para que la tesela no pese.
    select ST_AsMVT(t, 'ref', 4096, 'geom') into v from (
      select ST_AsMVTGeom(ST_Transform(n.geom, 3857), v_env, 4096, 32, true) as geom, n.llave, 'nodo'::text as forma, coalesce(n.nombre, n.llave) as nombre,
             n.pres_exist_mediana::real as valor, redes.f_pm_nivel_presion(n.pres_exist_mediana) as nivel
        from redes.pm_nodos n
       where n.carga_id = redes.f_ref_vigente('pm_nodos') and n.pres_exist_mediana is not null and n.geom && v_env4
         and (p_z >= z_nod or abs(hashtext(n.llave)) % 4 = 0)) t
     where t.geom is not null;
  else
    select ST_AsMVT(t, 'ref', 4096, 'geom') into v from (
      select ST_AsMVTGeom(ST_Transform(e.geom, 3857), v_env, 4096, 64, true) as geom, e.llave,
             case GeometryType(e.geom) when 'POINT' then 'nodo' when 'POLYGON' then 'area' when 'MULTIPOLYGON' then 'area' else 'tramo' end as forma,
             coalesce(e.nombre, e.llave) as nombre, coalesce(e.clase, '') as clase, coalesce(e.estado, '') as estado, e.valor::real as valor,
             case when p_capa = 'campana_2014' then redes.f_pm_nivel_presion(e.valor) end as nivel
        from redes.ref_elementos e
       where e.capa = p_capa and e.carga_id in (select id from redes.v_ref_carga_vigente) and e.geom is not null and e.geom && v_env4
         and (p_capa = 'campana_2014' or GeometryType(e.geom) <> 'POINT' or p_z >= z_nod)) t
     where t.geom is not null;
  end if;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $$;

create function public.geoportal_redes_referencia(p_solicitante text, p_capa text, p_llave text) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; g redes.geovisor_capas%rowtype; e redes.ref_elementos%rowtype; n redes.pm_nodos%rowtype; v_ll text := btrim(coalesce(p_llave, '')); v_act bigint; v_sec record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into g from redes.geovisor_capas where codigo = p_capa and activa and fuente = 'referencia';
  if not found then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if g.solo_completo and not a.completo then raise exception 'Capa solo para supervisores' using errcode = '42501'; end if;
  if v_ll = '' or length(v_ll) > 120 then perform tecnica.f_error('Falta el elemento'); end if;
  if p_capa = 'presion_modelo' then
    select * into n from redes.pm_nodos x where x.llave = v_ll and x.carga_id = redes.f_ref_vigente('pm_nodos');
    if not found then perform tecnica.f_error('Ese nodo no está en el modelo', 'P0002'); end if;
    select * into v_sec from redes.f_sector_de(n.geom);
    select k.activo_id into v_act from redes.v_nodo_vigente k where k.sistema = 'acueducto' and k.llave_modelo = v_ll and k.activo_id is not null
       and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = k.activo_id and not m.retirado);
    return jsonb_strip_nulls(jsonb_build_object('capa', p_capa, 'llave', v_ll, 'titulo', coalesce(n.nombre, v_ll), 'subtitulo', 'Nodo del modelo · ' || coalesce(n.tipo, 'sin tipo'),
      'origen', (select origen from redes.ref_cargas where id = n.carga_id),
      'advertencia', 'Presión de MODELO, no medida.' || case when n.pres_exist_negativa then ' El modelo de la red existente da presión negativa en este nodo a alguna hora del día.' else '' end,
      'nivel', redes.f_pm_nivel_presion(n.pres_exist_mediana),
      'activo', case when v_act is not null then (select codigo from redes.activos where id = v_act) end,
      'filas', (select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) from (values
        (1, 'Red existente: mediana del día', to_jsonb(n.pres_exist_mediana), 'm.c.a.'), (2, 'Red existente: mínima', to_jsonb(n.pres_exist_min), 'm.c.a.'),
        (3, 'Red existente: máxima', to_jsonb(n.pres_exist_max), 'm.c.a.'), (4, 'Red futura del Plan: mediana', to_jsonb(n.pres_futura_mediana), 'm.c.a.'),
        (5, 'Red futura del Plan: mínima', to_jsonb(n.pres_futura_min), 'm.c.a.'), (6, 'Red futura del Plan: máxima', to_jsonb(n.pres_futura_max), 'm.c.a.'),
        (7, 'Cota', to_jsonb(n.cota_m), 'm'), (8, 'Demanda (red existente)', to_jsonb(n.demanda_exist_lps), 'L/s'),
        (9, 'Sector según el Plan', to_jsonb(case when v_sec.sector is not null then v_sec.sector || coalesce(' · subsector ' || v_sec.subsector, '') end), null)) f(o, r, v, u)),
      'series', (select jsonb_agg(jsonb_build_object('nombre', case p.escenario when 'existente' then 'Red existente (modeloV1)' else 'Red futura del Plan (ModeloVF)' end,
                                                     'escenario', p.escenario, 'unidad', 'm.c.a.', 'eje', 'hora', 'valores', to_jsonb(p.horas)) order by p.escenario)
                   from redes.pm_presion_hora p
                  where p.llave = v_ll and p.carga_id in (redes.f_ref_vigente('pm_presion_existente'), redes.f_ref_vigente('pm_presion_futura')))));
  end if;
  select x.* into e from redes.ref_elementos x where x.capa = p_capa and x.llave = v_ll and x.carga_id in (select id from redes.v_ref_carga_vigente) order by x.carga_id desc limit 1;
  if not found then perform tecnica.f_error('Ese elemento no está en la capa', 'P0002'); end if;
  select * into v_sec from redes.f_sector_de(e.geom);
  return jsonb_strip_nulls(jsonb_build_object('capa', p_capa, 'llave', v_ll, 'titulo', coalesce(e.nombre, v_ll), 'subtitulo', g.nombre,
    'origen', (select origen from redes.ref_cargas where id = e.carga_id),
    'advertencia', case p_capa when 'campana_2014' then 'Presión MEDIDA en campo en 2014 (no es la presión de hoy).'
                               when 'plan_valvulas' then 'Válvula PROPUESTA por el Plan: no está instalada, no es un activo y no entra en ninguna simulación.'
                               when 'pluvial_2043' then 'Alternativa del Plan a 2043: incluye lo existente y lo propuesto.' else 'Capa de referencia: no es un activo.' end,
    'nivel', case when p_capa = 'campana_2014' then redes.f_pm_nivel_presion(e.valor) end,
    'filas', e.datos || case when v_sec.sector is not null then jsonb_build_array(jsonb_build_object('r', 'Sector según el Plan', 'v', v_sec.sector || coalesce(' · subsector ' || v_sec.subsector, ''))) else '[]'::jsonb end,
    'series', case when p_capa = 'campana_2014' then (
      select jsonb_build_array(jsonb_build_object('nombre', 'Presión medida cada 15 min', 'unidad', 'm.c.a.', 'eje', 'tiempo',
               'puntos', coalesce(jsonb_agg(jsonb_build_array(to_char(l.cuando, 'YYYY-MM-DD"T"HH24:MI'), l.p_mca) order by l.n), '[]'::jsonb)))
        from redes.pm_campana_lecturas l where l.llave = v_ll and l.carga_id = redes.f_ref_vigente('campana_2014_lecturas')) end));
end $$;

-- Ficha preliminar de un nodo «por clasificar»: solo lectura. Con qué se decide: dónde está, qué tramos le llegan, su cota, su sector y lo que dice el modelo.
create function public.geoportal_redes_nodo_preliminar(p_solicitante text, p_nodo bigint) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_autorizar_admin(p_solicitante); n redes.v_nodo_visible%rowtype; v_sec record; v_mod jsonb;
begin
  select * into n from redes.v_nodo_visible where nodo_id = p_nodo;
  if not found then perform tecnica.f_error('No existe ese nodo (o ya no es el vigente)', 'P0002'); end if;
  select * into v_sec from redes.f_sector_de(n.geom);
  v_mod := redes.f_nodo_modelo(n.llave_modelo);
  return jsonb_strip_nulls(jsonb_build_object(
    'nodo_id', n.nodo_id, 'sistema', n.sistema, 'llave_modelo', n.llave_modelo, 'nombre_modelo', n.nombre_modelo, 'nombre_visible', n.nombre_visible, 'clase_nodo', n.clase_nodo,
    'lat', round(ST_Y(n.geom)::numeric, 6), 'lon', round(ST_X(n.geom)::numeric, 6),
    'sector', case when v_sec.sector is not null then jsonb_build_object('sector', v_sec.sector, 'subsector', v_sec.subsector, 'codigo', v_sec.codigo, 'nombre', v_sec.nombre) end,
    'modelo', v_mod - 'sugerencia',
    'sugerencia', v_mod -> 'sugerencia',
    'tramos', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'prefijo', m.prefijo, 'nombre', m.codigo_anterior,
                                 'material', (select x.nombre from redes.materiales x where x.codigo = m.material_codigo), 'diametro_mm', m.diametro_mm, 'longitud_m', m.longitud_m,
                                 'estado', (select s.nombre from redes.estados_activo s where s.codigo = m.estado_codigo), 'extremo', case when t.nodo_ini = n.nodo_id then 'inicio' else 'fin' end,
                                 'linea', ST_AsGeoJSON(m.geom, 6)::jsonb) order by m.codigo)
                          from redes.tramo_nodos t join redes.activo_vigente_mat m on m.activo_id = t.activo_id and m.version = t.version and not m.retirado
                         where t.nodo_ini = n.nodo_id or t.nodo_fin = n.nodo_id), '[]'::jsonb)));
end $$;

create function public.geoportal_redes_nodo_clasificar(p_solicitante text, p_nodo bigint, p_clase text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_autorizar_admin(p_solicitante); n redes.v_nodo_visible%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if coalesce(p_clase, '') not in ('nodo_calculo', 'propuesta_plan', 'por_clasificar') then perform tecnica.f_error('Esa clasificación no existe'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.nodo.' || coalesce(p_nodo, 0)));
  select * into n from redes.v_nodo_visible where nodo_id = p_nodo;
  if not found then perform tecnica.f_error('No existe ese nodo (o ya no es el vigente)', 'P0002'); end if;
  if n.clase_nodo in ('activo', 'pozo_virtual') then perform tecnica.f_error('Ese nodo ya es un activo (o un pozo virtual): no se clasifica aquí'); end if;
  if n.clase_nodo = p_clase then perform tecnica.f_error('Ese nodo ya está así'); end if;
  insert into redes.nodo_eventos (nodo_id, tipo, clase, motivo, autor) values (n.nodo_id, 'clasificar', p_clase, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_nodo_clasificar', n.nodo_id::text, jsonb_build_object('nodo', n.nombre_modelo, 'llave', n.llave_modelo, 'antes', n.clase_nodo, 'clase', p_clase, 'motivo', v_mot), null);
  return jsonb_build_object('nodo_id', n.nodo_id, 'nombre_modelo', n.nombre_modelo, 'clase_nodo', p_clase);
end $$;

-- Bandeja «Por verificar» (supervisor de distribución y administrador): los activos con la marca vigente, con su motivo. Grupos: lo que dejó el Plan
-- (estado, válvula, pozo) y «otros» (los activos nuevos de una inversión, que ya quedaban por verificar desde el Corte 3a).
create function public.geoportal_redes_por_verificar(p_solicitante text, p_grupo text default null, p_despues_de bigint default null, p_limite integer default 50) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 've la bandeja de activos por verificar'); v_lim integer := coalesce(p_limite, 50); v_items jsonb; v_grupos jsonb;
begin
  if v_lim < 1 or v_lim > 200 then perform tecnica.f_error('Se piden de 1 a 200'); end if;
  if p_grupo is not null and p_grupo not in ('estado', 'valvula', 'pozo', 'otros') then perform tecnica.f_error('Ese grupo no existe'); end if;
  -- el último evento de verificación de cada activo; queda en la lista si es «por_verificar»
  with ult as (select distinct on (e.activo_id) e.activo_id, e.tipo, e.motivo, e.creado_en, e.id
                 from redes.activo_eventos e where e.tipo in ('verificar', 'por_verificar') order by e.activo_id, e.id desc),
       pv as (select u.activo_id, u.motivo, u.creado_en,
                     -- el grupo sale del motivo guardado (un hecho), no de la referencia vigente: si se carga otra versión del Plan, la bandeja no cambia de grupo
                     case when u.motivo not like 'Plan Maestro 2014:%' then 'otros' when u.motivo like '%válvula con el estado por verificar%' then 'valvula'
                          when u.motivo like '%que figura como existente en la Alternativa 1%' then 'pozo' else 'estado' end as grupo
                from ult u where u.tipo = 'por_verificar'
                 and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = u.activo_id and not m.retirado)),
       pag as (select p.* from pv p where (p_grupo is null or p.grupo = p_grupo) and (p_despues_de is null or p.activo_id > p_despues_de) order by p.activo_id limit v_lim)
  select (select coalesce(jsonb_agg(jsonb_build_object('grupo', g.grupo, 'n', g.n) order by g.grupo), '[]'::jsonb) from (select grupo, count(*) as n from pv group by 1) g),
         (select coalesce(jsonb_agg(jsonb_build_object('activo_id', p.activo_id, 'codigo', m.codigo, 'prefijo', m.prefijo, 'tipo', (select t.nombre_visible from redes.v_tipo_visible t where t.prefijo = m.prefijo),
                    'nombre', coalesce(m.nombre, m.codigo_anterior), 'sistema', m.sistema, 'estado', (select s.nombre from redes.estados_activo s where s.codigo = m.estado_codigo),
                    'grupo', p.grupo, 'motivo', p.motivo, 'desde', p.creado_en,
                    'lat', round(ST_Y(ST_PointOnSurface(m.geom))::numeric, 6), 'lon', round(ST_X(ST_PointOnSurface(m.geom))::numeric, 6)) order by p.activo_id), '[]'::jsonb)
            from pag p join redes.activo_vigente_mat m on m.activo_id = p.activo_id)
    into v_grupos, v_items;
  return jsonb_build_object('grupos', v_grupos, 'total', (select coalesce(sum((g ->> 'n')::integer), 0) from jsonb_array_elements(v_grupos) g where p_grupo is null or g ->> 'grupo' = p_grupo),
    'items', v_items, 'siguiente', case when jsonb_array_length(v_items) = v_lim then (v_items -> (v_lim - 1) ->> 'activo_id')::bigint end);
end $$;

create function public.geoportal_redes_activo_verificar(p_solicitante text, p_ref text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'marca un activo como verificado'); v_id bigint; v_mot text := btrim(coalesce(p_motivo, '')); v_cod text;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba lo que se encontró al verificar (10 caracteres o más)'); end if;
  v_id := redes.f_buscar_activo(p_ref);
  perform pg_advisory_xact_lock(hashtext('redes.activo.' || v_id));
  if not (select e.por_verificar from redes.v_activo_estado e where e.activo_id = v_id) then perform tecnica.f_error('Ese activo no está por verificar'); end if;
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (v_id, 'verificar', v_mot, v_email);
  select codigo into v_cod from redes.activos where id = v_id;
  perform tecnica.f_auditar(v_email, 'redes_activo_verificar', v_cod, jsonb_build_object('motivo', v_mot), null);
  return jsonb_build_object('codigo', v_cod, 'por_verificar', false);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del 7a publicado) con cambios exactos, aplicados una sola vez; nodos_por_clasificar va entera.
--   · redes.f_ficha: «sector_plan» (por geometría), «referencia» (lo del Plan Maestro, de sus tablas aparte) y «por_verificar_motivo»;
--   · geoportal_redes_geovisor_mvt: el nombre de los sectores y de las instalaciones, para su tarjeta;
--   · geoportal_redes_danos y geoportal_redes_intervenciones: «sector_plan», calculado, al lado del sector escrito a mano;
--   · geoportal_redes_contrato_tarjeta: «sector_plan», el del tramo del contrato;
--   · geoportal_redes_nodos_por_clasificar: lo que dice el modelo de cada nodo, la sugerencia y el filtro «sugerencia:<acción>».
-- =====================================================================
-- redes.f_ficha(bigint,text)
CREATE OR REPLACE FUNCTION redes.f_ficha(p_activo bigint, p_perfil text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v redes.v_activo_vigente%rowtype; t redes.v_tipo_visible%rowtype; v_super boolean := p_perfil in ('admin', 'supervisor');
  v_campos jsonb; v_origen jsonb; v_nodo jsonb; v_tramo jsonb; v_pto geometry;
begin
  select * into v from redes.v_activo_vigente where activo_id = p_activo;
  if not found then perform tecnica.f_error('Ese activo no está vigente', 'P0002'); end if;
  select * into t from redes.v_tipo_visible where prefijo = v.prefijo;
  v_pto := case when GeometryType(v.geom) = 'POINT' then v.geom else ST_PointOnSurface(v.geom) end;
  -- campos por tipo (tipos_activo.campos): el valor sale de la columna o de atributos; nulo = «sin dato»
  select coalesce(jsonb_agg(jsonb_build_object('clave', c ->> 'clave', 'rotulo', c ->> 'rotulo', 'unidad', c ->> 'unidad',
           'valor', case c ->> 'clave'
                      when 'diametro_mm' then to_jsonb(v.diametro_mm)
                      when 'longitud_m' then to_jsonb(v.longitud_m)
                      when 'capacidad' then to_jsonb(v.capacidad)
                      when 'profundidad_m' then to_jsonb(v.profundidad_m)
                      when 'material_codigo' then to_jsonb((select m.nombre from redes.materiales m where m.codigo = v.material_codigo))
                      when 'clase' then to_jsonb((select x.nombre from redes.clases_activo x where x.prefijo = v.prefijo and x.codigo = v.clase))
                      when 'efecto' then to_jsonb((select e.nombre from redes.efectos_valvula e where e.codigo = v.efecto))
                      when 'punto_codigo' then (select to_jsonb(ap.punto_codigo) from redes.v_activo_punto_vigente ap where ap.activo_id = p_activo)
                      else v.atributos -> (c ->> 'clave') end) order by o), '[]'::jsonb)
    into v_campos
    from jsonb_array_elements(t.campos) with ordinality as e(c, o);
  if v_super then
    select jsonb_build_object('origen', o.origen, 'aportante', o.aportante_codigo, 'aportante_nombre', a.nombre, 'tiene_soporte', o.soporte_ruta is not null, 'nota', o.nota)
      into v_origen from redes.v_activo_origen_vigente o left join redes.entidades_aportantes a on a.codigo = o.aportante_codigo where o.activo_id = p_activo;
  end if;
  -- si el activo es un nodo de la topología: cuántos tramos llegan
  select jsonb_build_object('nombre_modelo', n.nombre_modelo, 'nombre_visible', n.nombre_visible,
           'tramos', (select count(*) from redes.v_tramo_nodos_vigente x where x.nodo_ini = n.nodo_id or x.nodo_fin = n.nodo_id))
    into v_nodo from redes.v_nodo_visible n where n.activo_id = p_activo limit 1;
  -- si es un tramo: sus dos extremos (con el activo de cada nodo, si lo tiene)
  select jsonb_build_object('metodo', tn.metodo,
           'inicio', (select jsonb_build_object('nombre', n.nombre_visible, 'activo', redes.f_activo_corto(n.activo_id)) from redes.v_nodo_visible n where n.nodo_id = tn.nodo_ini),
           'fin', (select jsonb_build_object('nombre', n.nombre_visible, 'activo', redes.f_activo_corto(n.activo_id)) from redes.v_nodo_visible n where n.nodo_id = tn.nodo_fin))
    into v_tramo from redes.v_tramo_nodos_vigente tn where tn.activo_id = p_activo;
  return jsonb_strip_nulls(jsonb_build_object(
    'perfil', p_perfil,
    'activo', jsonb_build_object(
      'codigo', v.codigo, 'prefijo', v.prefijo, 'tipo', t.nombre_visible, 'tipo_catalogo', t.nombre,
      'sistema', v.sistema, 'sistema_nombre', (select s.nombre from redes.sistemas s where s.codigo = v.sistema), 'etapa', t.etapa, 'geometria', t.geometria,
      'nombre', v.nombre, 'clase', (select x.nombre from redes.clases_activo x where x.prefijo = v.prefijo and x.codigo = v.clase),
      'estado', (select s.nombre from redes.estados_activo s where s.codigo = v.estado_codigo), 'estado_codigo', v.estado_codigo,
      'cuenta_vigente', v.cuenta_vigente, 'punteado', v.punteado, 'retirado', v.retirado, 'oculto', v.oculto, 'por_verificar', v.por_verificar,
      'material', (select m.nombre from redes.materiales m where m.codigo = v.material_codigo),
      'fecha_instalacion', v.fecha_instalacion, 'barrio_sector', v.barrio_sector, 'codigo_anterior', v.codigo_anterior,
      'version', v.version, 'version_creada_en', v.version_creada_en, 'lat', round(ST_Y(v_pto)::numeric, 6), 'lon', round(ST_X(v_pto)::numeric, 6),
      'campos', v_campos),
    -- Corte 9a: nada de esto está en la ficha oficial; se lee de las tablas de referencia y de los polígonos vigentes de sectores
    'sector_plan', case when v.prefijo <> 'SEC' then (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector, 'codigo', s.codigo, 'nombre', s.nombre)
                                                        from redes.f_sector_de(v.geom) s where s.sector is not null) end,
    'referencia', nullif(redes.f_ficha_referencia(p_activo), '[]'::jsonb),
    'por_verificar_motivo', case when v.por_verificar then (select e.motivo from redes.activo_eventos e where e.activo_id = p_activo and e.tipo = 'por_verificar' order by e.id desc limit 1) end,
    'origen', v_origen,
    'modelo', case when v_super then v.atributos -> 'modelo' end,
    'nodo', v_nodo,
    'tramo', v_tramo,
    'contratos_enlazados', case when v.prefijo in ('RED', 'CON') then (select count(*) from redes.contrato_tramo ct where ct.activo_id = p_activo) end,
    'componentes', (select coalesce(jsonb_agg(redes.f_activo_corto(c.hijo_id) order by h.codigo), '[]'::jsonb)
                      from redes.v_componentes_vigentes c join redes.activos h on h.id = c.hijo_id where c.padre_id = p_activo
                       and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = c.hijo_id)),
    'parte_de', (select coalesce(jsonb_agg(redes.f_activo_corto(c.padre_id) order by p.codigo), '[]'::jsonb)
                   from redes.v_componentes_vigentes c join redes.activos p on p.id = c.padre_id where c.hijo_id = p_activo
                    and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = c.padre_id)),
    'admite_componentes', (select admite_componentes from redes.tipos_activo where prefijo = v.prefijo),
    -- «hechos»: daños, fallas e intervenciones (los suma la epicrisis desde los Cortes 2 y 3); «registro»: altas, versiones, retiros y componentes
    'epicrisis', jsonb_build_object(
      'hechos', (select count(*) from redes.v_epicrisis e where e.activo_id = p_activo and e.clase in ('dano', 'falla', 'intervencion')),
      'registro', (select count(*) from redes.v_epicrisis e where e.activo_id = p_activo and e.clase not in ('dano', 'falla', 'intervencion')),
      'danos_12_meses', (select count(*) from redes.v_epicrisis e where e.activo_id = p_activo and e.clase in ('dano', 'falla') and e.cuando >= now() - interval '12 months'))));
end $function$;

-- public.geoportal_redes_geovisor_mvt(text,integer,integer,integer)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor_mvt(p_solicitante text, p_z integer, p_x integer, p_y integer)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare a record; v_env geometry; v_env4326 geometry; v bytea; v_pref text[]; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        z_min numeric := redes.f_param('geovisor_zoom_min'); z_red numeric := redes.f_param('geovisor_zoom_red_completa');
        z_nod numeric := redes.f_param('geovisor_zoom_nodos'); z_acc numeric := redes.f_param('geovisor_zoom_acc');
        d_acu numeric := redes.f_param('geovisor_diam_principal_acu_mm'); d_alc numeric := redes.f_param('geovisor_diam_principal_alc_mm');
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < z_min then return ''; end if;
  select array_agg(distinct p) into v_pref from redes.geovisor_capas g cross join unnest(g.prefijos) p where g.activa and g.fuente = 'tesela' and (a.completo or not g.solo_completo);
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4326 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'activos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, m.codigo, m.prefijo, m.sistema,
           case GeometryType(m.geom) when 'POINT' then 'nodo' when 'POLYGON' then 'area' when 'MULTIPOLYGON' then 'area' else 'tramo' end as forma,
           coalesce(m.clase, '') as clase, coalesce(m.material_codigo, '') as material, m.diametro_mm::real as diametro,
           case when m.fecha_instalacion is not null then greatest(0, extract(year from age(v_hoy, m.fecha_instalacion)))::integer end as edad,
           m.estado_codigo as estado, m.punteado,
           case when m.prefijo in ('SEC', 'TAN', 'PTA', 'CAP', 'DES', 'EBA', 'EBR', 'PTR') then m.nombre end as nombre
      from redes.activo_vigente_mat m
     where not m.retirado and not m.oculto and m.prefijo = any (v_pref)
       and m.geom && v_env4326
       and case
             when m.prefijo = 'ACC' then p_z >= z_acc
             when m.prefijo in ('TAN', 'PTA', 'CAP', 'DES', 'EBA', 'EBR', 'PTR', 'SEC') then true
             when GeometryType(m.geom) = 'POINT' then p_z >= z_nod
             when p_z >= z_red then true
             else m.prefijo in ('CON', 'ADU', 'INT')
                  or (m.sistema = 'acueducto' and m.diametro_mm >= d_acu) or (m.sistema = 'alcantarillado' and m.diametro_mm >= d_alc)
           end) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $function$;

-- public.geoportal_redes_danos(text,text,integer)
CREATE OR REPLACE FUNCTION public.geoportal_redes_danos(p_solicitante text, p_filtro text DEFAULT 'abiertos'::text, p_limite integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 've la lista de daños y fallas'); v_lim integer := coalesce(p_limite, 100);
begin
  if coalesce(p_filtro, '') not in ('abiertos', 'todos', 'ocultos', 'no_identificados') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_lim < 1 or v_lim > 300 then perform tecnica.f_error('Se piden de 1 a 300'); end if;
  return jsonb_build_object('filtro', p_filtro, 'danos', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'clase', x.clase, 'tipo', x.tipo_nombre, 'sistema', x.sistema, 'activo', x.activo_codigo, 'no_identificado', x.no_ident_que_es,
             'estado', x.estado, 't_detectado', x.t_detectado, 'riesgo', x.riesgo, 'causa_clase', x.causa_clase, 'sector', x.sector_num, 'sector_plan', (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector) from redes.f_sector_de(x.geom) s where s.sector is not null), 'origen', x.origen, 'autor', x.autor,
             'total_s', x.total_s, 'fotos', x.fotos, 'intervenciones', x.itv, 'tiene_tercero', x.tercero) order by x.t_detectado desc)
      from (select d.*, n.sector_num,
                   (select count(*) from redes.dano_fotos f where f.dano_id = d.id) as fotos,
                   (select count(*) from redes.intervenciones i where i.dano_id = d.id) as itv,
                   exists (select 1 from redes.dano_datos_sensibles s where s.dano_id = d.id) as tercero
              from redes.v_dano d join redes.danos n on n.id = d.id
             where case p_filtro when 'abiertos' then d.estado in ('reportado', 'en_atencion') when 'ocultos' then d.estado = 'oculto'
                                 when 'no_identificados' then d.activo_id is null and d.estado <> 'oculto' else true end
             order by d.t_detectado desc limit v_lim) x), '[]'::jsonb));
end $function$;

-- public.geoportal_redes_intervenciones(text,text,integer)
CREATE OR REPLACE FUNCTION public.geoportal_redes_intervenciones(p_solicitante text, p_filtro text DEFAULT 'recientes'::text, p_limite integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven la lista de intervenciones'); v_lim integer := coalesce(p_limite, 50);
begin
  if coalesce(p_filtro, '') not in ('recientes', 'recursos_por_completar') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_lim < 1 or v_lim > 100 then perform tecnica.f_error('Se piden de 1 a 100 intervenciones'); end if;
  return jsonb_build_object('filtro', p_filtro, 'intervenciones', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'tipo', x.tipo_nombre, 'inversion_modo', x.inversion_modo, 'sistema', x.sistema, 'activo', x.activo_codigo,
             'no_identificado', x.no_ident_que_es, 'dano', x.dano_codigo, 't_fin', x.t_fin, 'ejecutor', x.ejecutor, 'contratista', x.contratista, 'autor', x.autor,
             'sector_plan', (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector) from redes.f_sector_de(x.geom) s where s.sector is not null),
             'recursos', x.recursos, 'sin_evidencia', x.sin_evidencia, 'fotos', x.fotos, 'estado', x.estado,
             'fuentes', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('n', f.n, 'aportante', f.aportante_codigo, 'aportante_nombre', e.nombre, 'entidad', f.entidad, 'valor', f.valor,
                                                                               'porcentaje', f.porcentaje, 'soporte', f.soporte)) order by f.n)
                           from redes.v_intervencion_fuentes f join redes.entidades_aportantes e on e.codigo = f.aportante_codigo where f.intervencion_id = x.id))
             order by x.registrado_en desc)
      from (select * from redes.v_intervencion v
             where v.estado <> 'oculta' and (p_filtro = 'recientes' or v.recursos = 'por_completar')
             order by v.registrado_en desc limit v_lim) x), '[]'::jsonb));
end $function$;

-- public.geoportal_redes_contrato_tarjeta(text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_contrato_tarjeta(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'bi_interno', 'pg_temp'
AS $function$
declare a record; cs record; pr record; f record; v_c text := btrim(coalesce(p_contrato, '')); v_personal boolean;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;
  -- Corte 7a (respuesta 1 de David al 6b): nombre y dirección solo para el administrador y el supervisor de distribución (su permiso, o área distribución o las dos)
  v_personal := a.admin or public.geoportal_puede(a.email, 'dashboard_redes') or coalesce(redes.f_area(a.email) in ('distribucion', 'ambas'), false);
  if v_c !~ '^[0-9]{1,12}$' then perform tecnica.f_error('Escriba solo los números del contrato'); end if;
  if v_c in ('0', '99999999') or not exists (select 1 from public.catastro_valledupar cv where cv.cod_usuario = v_c and cv.geom is not null) then
    perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002');
  end if;
  select s.nombre, s.estado, s.categoria, s.direccion, s.barrio, s.periodo_carga into cs
    from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select cv.direccion, cv.barrio into pr from public.catastro_valledupar cv where cv.cod_usuario = v_c order by cv.id limit 1;
  select fc.periodo_ultimo, fc.uso, fc.consumo_meses, fc.cons_prom, fc.meses_con_lectura, fc.medidor_anios into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  -- la lectura queda registrada: quién, cuándo y qué contrato (NUNCA el nombre ni la dirección)
  perform tecnica.f_auditar(a.email, 'redes_contrato_tarjeta', v_c, jsonb_build_object('datos', case when v_personal then 'nombre, dirección y barrio' else 'sin nombre ni dirección' end, 'desde', 'geovisor'), p_ip);
  return jsonb_build_object(
    'contrato', v_c,
    'estado', redes.f_estado_contrato(cs.estado), 'estado_texto', nullif(btrim(cs.estado), ''),
    'uso', redes.f_contrato_uso(f.uso, cs.categoria),
    'consumo', case when f.periodo_ultimo is not null then jsonb_build_object(
        'periodo_ultimo', f.periodo_ultimo, 'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura,
        'meses', (select coalesce(jsonb_agg(jsonb_build_object('periodo', m ->> 'periodo', 'm3', m -> 'm3', 'sin_dato', coalesce((m ->> 'sin_dato')::boolean, false),
                                                               'lectura_real', coalesce((m ->> 'lectura_real')::boolean, false)) order by k), '[]'::jsonb)
                    from jsonb_array_elements(f.consumo_meses) with ordinality x(m, k))) end,
    'medidor_anios', f.medidor_anios,
    'tramo', (select v.codigo from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id where t.contrato = v_c),
    'sector_plan', (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector)      -- Corte 9a: el sector del contrato es el de su tramo (por geometría)
                      from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id cross join lateral redes.f_sector_de(v.geom) s
                     where t.contrato = v_c and s.sector is not null),
    'suscriptor', jsonb_build_object(                                  -- DATO PERSONAL: solo en pantalla
      'nombre', case when v_personal then nullif(btrim(cs.nombre), '') end,
      'direccion', case when v_personal then coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')) end,
      'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), ''))),
    'datos_personales', v_personal,
    'corte', cs.periodo_carga);
end $function$;

-- public.geoportal_redes_nodos_por_clasificar(text,text,bigint,integer)
CREATE OR REPLACE FUNCTION public.geoportal_redes_nodos_por_clasificar(p_solicitante text, p_buscar text DEFAULT NULL::text, p_despues_de bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_admin(p_solicitante); v_q text := nullif(lower(btrim(coalesce(p_buscar, ''))), ''); v_lim integer := coalesce(p_limite, 50);
        v_acc text; v_r jsonb;
begin
  if v_lim < 1 or v_lim > 200 then perform tecnica.f_error('Se piden de 1 a 200'); end if;
  if v_q is not null and length(v_q) > 60 then perform tecnica.f_error('La búsqueda es demasiado larga'); end if;
  -- Corte 9a: «sugerencia:<acción>» en la búsqueda deja solo los nodos con esa sugerencia del modelo
  -- (los tramos que llegan a cada nodo se cuentan por los índices de tramo_nodos; la vista de tramos vigentes recorría todas las versiones en cada nodo)
  if v_q like 'sugerencia:%' then
    v_acc := substring(v_q from 12); v_q := null;
    if v_acc not in ('crear', 'no_crear', 'dejar_nodo', 'revisar', 'sin_modelo') then perform tecnica.f_error('Esa sugerencia no existe'); end if;
  end if;
  with base as (
    select n.nodo_id, n.sistema, n.llave_modelo, n.nombre_modelo, n.nombre_visible, n.geom, pm.tipo, pm.que_es,
           redes.f_pm_sugerencia(pm.tipo, pm.que_es, pm.nombre, pm.zona_modelo) as sug
      from redes.v_nodo_visible n
      left join redes.pm_nodos pm on n.sistema = 'acueducto' and pm.llave = n.llave_modelo and pm.carga_id = redes.f_ref_vigente('pm_nodos')
     where n.clase_nodo = 'por_clasificar'),
  fil as (
    select b.* from base b
     where (v_q is null or position(v_q in lower(coalesce(b.nombre_modelo, '') || ' ' || b.nombre_visible || ' ' || b.llave_modelo || ' ' || coalesce(b.que_es, ''))) > 0)
       and (v_acc is null or coalesce(b.sug ->> 'accion', 'sin_modelo') = v_acc)),
  pag as (select f.* from fil f where p_despues_de is null or f.nodo_id > p_despues_de order by f.nodo_id limit v_lim)
  select jsonb_build_object(
    'grupos', coalesce((select jsonb_agg(jsonb_build_object('grupo', g.grupo, 'n', g.n) order by g.n desc, g.grupo)
                          from (select coalesce(substring(b.nombre_modelo from '^[A-Za-zÁÉÍÓÚáéíóúñ]+'), '?') as grupo, count(*) as n from base b group by 1) g), '[]'::jsonb),
    'sugerencias', coalesce((select jsonb_agg(jsonb_build_object('accion', g.accion, 'n', g.n) order by g.n desc, g.accion)
                               from (select coalesce(b.sug ->> 'accion', 'sin_modelo') as accion, count(*) as n from base b group by 1) g), '[]'::jsonb),
    'total', (select count(*) from fil),
    'items', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('nodo_id', x.nodo_id, 'sistema', x.sistema, 'llave_modelo', x.llave_modelo, 'nombre_modelo', x.nombre_modelo,
                         'nombre_visible', x.nombre_visible, 'alias', case when x.nombre_visible is distinct from coalesce(x.nombre_modelo, x.llave_modelo) then x.nombre_visible end,
                         'lat', round(ST_Y(x.geom)::numeric, 6), 'lon', round(ST_X(x.geom)::numeric, 6),
                         'tramos', (select count(*) from redes.tramo_nodos t join redes.activo_vigente_mat m on m.activo_id = t.activo_id and m.version = t.version
                                    where t.nodo_ini = x.nodo_id or t.nodo_fin = x.nodo_id),
                         'tipo_modelo', x.tipo, 'que_es', nullif(x.que_es, 'otro'), 'sugerencia', x.sug)) order by x.nodo_id) from pag x), '[]'::jsonb),
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre_visible, 'sistema', t.sistema,
                         'pide_clase', exists (select 1 from jsonb_array_elements(t.campos) c where c ->> 'clave' = 'clase' and (c ->> 'obligatorio')::boolean),
                         'clases', coalesce((select jsonb_agg(jsonb_build_object('codigo', k.codigo, 'nombre', k.nombre) order by k.orden) from redes.clases_activo k where k.prefijo = t.prefijo and k.activo), '[]'::jsonb))
                         order by t.sistema, t.orden)
                         from redes.v_tipo_visible t where t.geometria = 'punto' and t.activo and t.sistema in ('acueducto', 'alcantarillado')), '[]'::jsonb)) into v_r;
  return v_r || jsonb_build_object('siguiente', case when jsonb_array_length(v_r -> 'items') = v_lim then (v_r -> 'items' -> (v_lim - 1) ->> 'nodo_id')::bigint end);
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las 7 funciones internas nuevas: nadie de la API. Las 6 RPC nuevas y las 6 reemplazadas: solo service_role (la Edge geoportal-redes).
-- Las tablas y vistas nuevas ya quedaron sin privilegios en el 10 y en el 20.
-- =====================================================================
revoke all on function redes.f_ref_vigente(text), redes.f_sector_de(geometry), redes.f_pm_nivel_presion(numeric), redes.f_pm_sugerencia(text, text, text, text),
  redes.f_nodo_modelo(text), redes.f_ficha_referencia(bigint), redes.f_pm_marcar_por_verificar(text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_geovisor_mvt_ref', 'geoportal_redes_referencia', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_nodo_clasificar',
                                'geoportal_redes_por_verificar', 'geoportal_redes_activo_verificar',
                                'geoportal_redes_geovisor_mvt', 'geoportal_redes_danos', 'geoportal_redes_intervenciones', 'geoportal_redes_contrato_tarjeta',
                                'geoportal_redes_nodos_por_clasificar') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
revoke all on function redes.f_ficha(bigint, text) from public, anon, authenticated, service_role;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9a', 'migracion_redes_corte9a', null, jsonb_build_object(
        'tablas', jsonb_build_array('ref_cargas', 'ref_carga_eventos', 'pm_nodos', 'pm_tramos', 'pm_valvulas', 'pm_presion_hora', 'pm_alc_conductos', 'pm_alc_pozos', 'ref_elementos', 'pm_campana_lecturas'),
        'reemplazadas', jsonb_build_array('redes.f_ficha', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_danos', 'geoportal_redes_intervenciones', 'geoportal_redes_contrato_tarjeta',
                                          'geoportal_redes_nodos_por_clasificar', 'vista redes.v_nodo_vigente'),
        'motivo', 'integración del Plan Maestro 2014: datos de referencia en tablas aparte; la ficha oficial no cambia'), null);
commit;
