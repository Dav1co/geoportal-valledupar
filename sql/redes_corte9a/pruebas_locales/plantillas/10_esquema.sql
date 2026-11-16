-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 10 — GUARDIA Y ESQUEMA (integración del Plan Maestro 2014)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte9a_plan_maestro.md (16-nov) y regulatorio/salida_geoportal/LEEME.md.
-- · Presupone el Corte 7a publicado (huella del conjunto de funciones de redes {{MD5_BASE}}).
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
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_BASE}}' then
    raise exception 'Las funciones de redes no son las del Corte 7a publicado (huella {{MD5_BASE}}): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_nodo_vigente'::regclass)) <> '{{MD5_VISTA_NODO}}' then
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
