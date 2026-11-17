begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1a: simulación de cierre, §17; Fase 1b: cierre real) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte9b_simulacion_alertas.md, §17 y N-9 de la bitácora, corte9b/analisis_cierre_valvulas.md (opción C).
-- · Presupone el Corte 10 publicado (huella del conjunto de funciones de redes aad5952c27e13cc3ad45623279ba7085) y tecnica.f_avisos del Corte 12 (md5 061990d1826a5a2de0a539ca22004987).
-- · 1a y 1b se publican JUNTAS (David, 17-nov).
-- · La simulación se calcula en cada llamada sobre la red registrada (tablas temporales); aquí solo se guarda lo que el usuario decide guardar
--   con un daño o una intervención: el resultado completo, la huella de la red con la que se calculó y el autor. Solo agregar; nada se borra.
-- · Sin datos de personas: los contratos van como número (Técnica no muestra nombres ni teléfonos en listados).
-- =====================================================================
do $$
begin
  if to_regclass('redes.simulaciones_cierre') is not null then raise exception 'El Corte 9b (Fase 1) ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'aad5952c27e13cc3ad45623279ba7085' then
    raise exception 'Las funciones de redes no son las del Corte 10 publicado (huella aad5952c27e13cc3ad45623279ba7085): deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) <> '061990d1826a5a2de0a539ca22004987' then
    raise exception 'tecnica.f_avisos no es la del Corte 12 publicado (md5 061990d1826a5a2de0a539ca22004987): deténgase y avise';
  end if;
  if to_regclass('redes.tramo_nodos') is null or to_regclass('redes.nodos') is null or to_regclass('redes.contrato_tramo') is null or to_regclass('redes.val_amarre') is null then
    raise exception 'Faltan tablas de la red (tramo_nodos, nodos, contrato_tramo) o del Corte 10: deténgase y avise';
  end if;
end $$;

-- ---------- 1. Las simulaciones guardadas (con un daño o una intervención) ----------
create table redes.simulaciones_cierre (
  id              bigint generated always as identity primary key,
  dano_id         uuid references redes.danos (id),
  intervencion_id uuid references redes.intervenciones (id),
  activo_id       bigint not null references redes.activos (id),      -- el tramo o el nodo del trabajo
  red_huella      text not null check (red_huella ~ '^[0-9a-f]{32}$'),      -- la red con la que se calculó (tramos, nodos, válvulas y cómo cuentan)
  valvulas        integer not null check (valvulas >= 0),      -- cuántas válvulas cerrar (escenario estrecho)
  contratos_min   integer not null check (contratos_min >= 0),
  contratos_max   integer not null check (contratos_max >= contratos_min),
  segmento_grande boolean not null,
  resultado       jsonb not null check (jsonb_typeof(resultado) = 'object'),
  contratos       text[] check (contratos is null or cardinality(contratos) <= 200000),      -- los contratos sin agua del escenario estrecho (nulo si pasan del tope)
  ms              integer not null check (ms >= 0),
  autor           text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en       timestamptz not null default clock_timestamp(),
  check (num_nonnulls(dano_id, intervencion_id) = 1)
);
create index ix_sim_cierre_dano on redes.simulaciones_cierre (dano_id, id desc) where dano_id is not null;
create index ix_sim_cierre_itv on redes.simulaciones_cierre (intervencion_id, id desc) where intervencion_id is not null;
comment on table redes.simulaciones_cierre is 'Corte 9b (§17): simulaciones de cierre de válvulas guardadas con un daño o una intervención. Solo agregar. El resultado es el que vio el usuario, con la huella de la red con la que se calculó.';
alter table redes.simulaciones_cierre enable row level security;
revoke all on table redes.simulaciones_cierre from public, anon, authenticated, service_role;
create trigger t_solo_agregar before update or delete on redes.simulaciones_cierre for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.simulaciones_cierre for each statement execute function tecnica.f_solo_agregar();

-- ---------- 2. Parámetros (editables en Parámetros; sus cambios quedan en parametro_eventos) ----------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('sim_segmento_grande_tramos', 200, 'tramos', 10, 20000,
   'Simulación de cierre (Corte 9b): si el sector que se aísla tiene más tramos que esto, es «segmento grande»: con las válvulas registradas no se aísla en pequeño'),
  ('sim_segmento_grande_contratos', 2000, 'contratos', 10, 200000,
   'Simulación de cierre (Corte 9b): si el cierre deja sin agua más contratos que esto, es «segmento grande»'),
  ('sim_no_cierra_max', 4, 'válvulas', 0, 10,
   'Simulación de cierre (Corte 9b): de cuántas válvulas (las más cercanas) se calcula «si esta no cierra»'),
  ('sim_valvulas_lista_max', 30, 'válvulas', 5, 200,
   'Simulación de cierre (Corte 9b): cuántas válvulas se muestran como máximo (las más cercanas); el total siempre se dice'),
  ('sim_contratos_guardar_max', 20000, 'contratos', 0, 200000,
   'Simulación de cierre (Corte 9b): hasta cuántos contratos sin agua se guardan, uno por uno, con la simulación (si son más, solo el conteo)'),
  ('sim_guardadas_max', 20, 'simulaciones', 1, 100,
   'Simulación de cierre (Corte 9b): cuántas simulaciones se pueden guardar como máximo con un mismo daño o intervención')
on conflict (clave) do update set estado = 'vigente', descripcion = excluded.descripcion;

-- ---------- 3. Fase 1b: las maniobras de válvula (el cierre real). Solo agregar: el estado de una válvula es su último «cerrar» sin «abrir» ----------
create table redes.valvula_maniobras (
  id               bigint generated always as identity primary key,
  valvula_id       bigint not null references redes.activos (id),
  tipo             text not null check (tipo in ('cerrar', 'abrir', 'regreso')),      -- «regreso»: ajuste de la hora estimada de regreso del servicio
  cierre_id        bigint references redes.valvula_maniobras (id),      -- «abrir» y «regreso»: el cierre al que pertenecen
  dano_id          uuid references redes.danos (id),
  intervencion_id  uuid references redes.intervenciones (id),
  motivo           text check (motivo is null or length(btrim(motivo)) between 10 and 500),
  regreso_estimado timestamptz,      -- hora estimada de regreso del servicio (la pone quien cierra; el supervisor la ajusta con «regreso»)
  hecho_en         timestamptz not null,      -- cuándo se hizo en campo (puede ser antes del registro, con tope)
  autor            text not null check (autor = lower(autor) and position('@' in autor) > 1),
  registrado_en    timestamptz not null default clock_timestamp(),
  check (num_nonnulls(dano_id, intervencion_id) <= 1),
  check ((tipo = 'cerrar') = (cierre_id is null)),
  check (tipo <> 'regreso' or regreso_estimado is not null),
  check (tipo <> 'abrir' or regreso_estimado is null),
  check (regreso_estimado is null or regreso_estimado > hecho_en),
  check (tipo <> 'cerrar' or dano_id is not null or intervencion_id is not null or motivo is not null)      -- sin daño ni intervención, con motivo
);
create unique index ux_maniobra_abrir on redes.valvula_maniobras (cierre_id) where tipo = 'abrir';      -- un cierre se abre una sola vez
create index ix_maniobra_valvula on redes.valvula_maniobras (valvula_id, id desc);
create index ix_maniobra_cierre on redes.valvula_maniobras (cierre_id, id desc) where cierre_id is not null;
create index ix_maniobra_cerrar on redes.valvula_maniobras (id) where tipo = 'cerrar';
comment on table redes.valvula_maniobras is 'Corte 9b (1b): maniobras de válvula en campo (cerrar, abrir, ajuste de la hora de regreso), con quién, cuándo y el daño o la intervención. Solo agregar.';

-- ---------- 4. Fase 1b: la foto del corte vigente (se saca en cada maniobra; la leen la tesela, la franja y los avisos) ----------
create table redes.corte_fotos (
  id                    bigint generated always as identity primary key,
  maniobra_id           bigint references redes.valvula_maniobras (id),      -- nula si la sacó el supervisor a mano (la red cambió)
  motivo                text check (motivo is null or length(btrim(motivo)) between 10 and 500),
  red_huella            text not null check (red_huella ~ '^[0-9a-f]{32}$'),
  valvulas_cerradas     integer not null check (valvulas_cerradas >= 0),
  valvulas_fuera_de_red integer not null check (valvulas_fuera_de_red >= 0),
  tramos_cerrados       integer not null check (tramos_cerrados >= 0),
  tramos_afectados      integer not null check (tramos_afectados >= 0),
  contratos_cerrados    integer not null check (contratos_cerrados >= 0),
  contratos_afectados   integer not null check (contratos_afectados >= 0),
  zonas                 integer not null check (zonas >= 0),
  ms                    integer not null check (ms >= 0),
  autor                 text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en             timestamptz not null default clock_timestamp(),
  check (maniobra_id is not null or motivo is not null)
);
create table redes.corte_foto_zonas (
  foto_id             bigint not null references redes.corte_fotos (id),
  zona                integer not null check (zona >= 1),
  tramos_cerrados     integer not null check (tramos_cerrados >= 0),
  tramos_afectados    integer not null check (tramos_afectados >= 0),
  contratos_cerrados  integer not null check (contratos_cerrados >= 0),
  contratos_afectados integer not null check (contratos_afectados >= 0),
  lat                 numeric(9,6) not null,
  lon                 numeric(9,6) not null,
  caja                numeric[] not null check (cardinality(caja) = 4),      -- oeste, sur, este, norte (para llevar el mapa a la zona)
  primary key (foto_id, zona)
);
create table redes.corte_foto_tramos (
  foto_id   bigint not null references redes.corte_fotos (id),
  activo_id bigint not null references redes.activos (id),
  papel     text not null check (papel in ('cerrado', 'afectado')),
  zona      integer not null,
  primary key (foto_id, activo_id),
  foreign key (foto_id, zona) references redes.corte_foto_zonas (foto_id, zona) deferrable initially deferred
);
create table redes.corte_foto_valvulas (
  foto_id    bigint not null references redes.corte_fotos (id),
  cierre_id  bigint not null references redes.valvula_maniobras (id),
  valvula_id bigint not null references redes.activos (id),
  en_red     boolean not null,      -- falso: la válvula no es un nodo de la red en operación (no corta nada en el cálculo)
  zona       integer,      -- nula si su cierre no deja a nadie sin agua
  primary key (foto_id, cierre_id)
);
comment on table redes.corte_fotos is 'Corte 9b (1b): foto del corte vigente después de cada maniobra (tramos cerrados y afectados, zonas, contratos). Solo agregar; vale la última.';

do $$
declare t text;
begin
  foreach t in array array['valvula_maniobras', 'corte_fotos', 'corte_foto_zonas', 'corte_foto_tramos', 'corte_foto_valvulas'] loop
    execute format('alter table redes.%I enable row level security', t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', t);
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
end $$;

insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('corte_horas_atras_max', 48, 'horas', 1, 720,
   'Cierre real (Corte 9b): hasta cuántas horas atrás se puede registrar que una válvula se cerró o se abrió (lo hecho en campo y registrado después)')
on conflict (clave) do update set estado = 'vigente', descripcion = excluded.descripcion;

-- ---------- 5. Fase 1b: el aviso «válvula cerrada hace más de X horas» (Avisos del 12, distribución; David: 6 h naranja y 12 h rojo) ----------
insert into tecnica.aviso_parametros (clave, area, valor, minimo, maximo, unidad, orden, nombre, descripcion) values
  ('valvula_cerrada_naranja_h', 'distribucion', 6, 1, 720, 'horas', 162, 'Válvula cerrada: naranja',
   'Una válvula que sigue cerrada (sin «abrir») sale en naranja desde estas horas.'),
  ('valvula_cerrada_rojo_h', 'distribucion', 12, 1, 720, 'horas', 164, 'Válvula cerrada: rojo',
   'Una válvula que sigue cerrada sale en rojo desde estas horas.')
on conflict (clave) do nothing;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · 20 — FUNCIONES INTERNAS de la simulación de cierre (§17, opción C de analisis_cierre_valvulas.md). PROPUESTA.
-- Recorrido sobre la RED DE LA BASE (la oficial: tramos de acueducto en operación y sus nodos, con las válvulas como nodos), en cada llamada:
--   · el grafo se arma en tablas TEMPORALES de la transacción (unos 10 mil tramos); no se escribe ninguna tabla de la base: nada se «rehace»;
--   · un recorrido en anchura (CTE recursiva) desde el trabajo avanza por tramos y nodos y se detiene en las válvulas que cierran: esas son las que hay que cerrar;
--   · un segundo recorrido desde los tanques y la planta, con esas válvulas cerradas, dice qué tramos se quedan sin camino (sin agua) además del segmento.
-- N-9 (David, 15-nov): las válvulas con efecto «sin definir» NO se cuentan como que cierran → dos escenarios y un RANGO:
--   · estrecho (X): las «sin definir» cierran (el sector más pequeño posible) → es el que dice qué válvulas cerrar;
--   · amplio (Y, el que vale): las «sin definir» no detienen; si no hay válvulas «cierra» alrededor, no se puede aislar.
-- Una válvula NO detiene si: está retirada o fuera de operación (fuera de servicio, inactiva en el modelo, proyectada, por eliminar), su efecto es «deriva»,
-- o es ventosa o purga (no están en la línea). Las «por verificar en campo» cuentan como que operan, pero salen marcadas.
-- Sin datos de personas: los contratos van como número y conteo (contrato_tramo, el tramo más cercano a 30 m).
-- Las funciones que leen las tablas temporales son plpgsql (no sql): el cuerpo nombra tablas que no existen al crear la función.
-- =====================================================================

-- ---------- el grafo vigente de acueducto, en tablas temporales de la transacción. Devuelve la huella de la red con la que se calcula ----------
create function redes.f_sim_grafo() returns text
language plpgsql volatile security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_h text; v_t text;
begin
  foreach v_t in array array['_sim_g', '_sim_v', '_sim_f', '_sim_s', '_sim_c', '_sim_cx', '_sim_t', '_sim_w', '_sim_b', '_sim_x'] loop
    if to_regclass('pg_temp.' || v_t) is not null then execute format('drop table pg_temp.%I', v_t); end if;
  end loop;
  -- aristas en los dos sentidos: el tramo t va del nodo n al nodo m. Solo tramos de acueducto (RED, CON) que cuentan (en operación) y no están retirados
  create temp table _sim_g (t bigint not null, n bigint not null, m bigint not null, cn text) on commit drop;
  insert into _sim_g (t, n, m)
  select tn.activo_id, x.a, x.b
    from redes.tramo_nodos tn
    join redes.activo_vigente_mat v on v.activo_id = tn.activo_id and v.version = tn.version
   cross join lateral (values (tn.nodo_ini, tn.nodo_fin), (tn.nodo_fin, tn.nodo_ini)) x(a, b)
   where v.sistema = 'acueducto' and v.prefijo in ('RED', 'CON') and v.cuenta_vigente and not v.retirado
     and tn.nodo_ini is not null and tn.nodo_fin is not null;
  -- las válvulas que son nodos de la red, con cómo cuentan en el cierre
  create temp table _sim_v on commit drop as
  select n.id as n, m.activo_id, m.codigo, coalesce(m.efecto, 'sin_definir') as efecto, m.estado_codigo, m.clase,
         case when m.retirado or m.estado_codigo in ('fuera_servicio', 'inactivo_modelo', 'proyectado', 'por_eliminar') then 'no_opera'
              when coalesce(m.clase, 'cierre') in ('ventosa', 'purga') then 'no_corta'
              when m.efecto = 'cierra' then 'cierra'
              when m.efecto = 'deriva' then 'deriva'
              else 'sin_definir' end as cuenta,
         coalesce(pv.tipo = 'por_verificar', false) as por_verificar, n.geom
    from redes.nodos n join redes.activo_vigente_mat m on m.activo_id = n.activo_id
    left join (select distinct on (e.activo_id) e.activo_id, e.tipo from redes.activo_eventos e
                where e.tipo in ('verificar', 'por_verificar') order by e.activo_id, e.id desc) pv on pv.activo_id = m.activo_id      -- el último evento de verificación
   where m.prefijo = 'VAL' and exists (select 1 from _sim_g g where g.n = n.id);
  alter table _sim_v add primary key (n);
  -- el nodo de salida de cada arista sabe si es una válvula que puede detener el paso (cierra o sin_definir)
  update _sim_g g set cn = v.cuenta from _sim_v v where v.n = g.n and v.cuenta in ('cierra', 'sin_definir');
  create index on _sim_g (n);
  analyze _sim_g;
  -- las fuentes: tanques y planta en operación que son nodos de la red
  create temp table _sim_f on commit drop as
  select distinct n.id as n, m.activo_id
    from redes.nodos n join redes.activo_vigente_mat m on m.activo_id = n.activo_id
   where m.prefijo in ('TAN', 'PTA') and m.cuenta_vigente and not m.retirado and exists (select 1 from _sim_g g where g.n = n.id);
  -- conjuntos de trabajo de cada escenario: nodos del segmento (s), válvulas cerradas (c; cx: las del escenario estrecho), tramos del segmento (t),
  -- tramos con agua (w), con agua sin cerrar nada (b) y sin agua por el cierre (x)
  create temp table _sim_s (n bigint primary key) on commit drop;
  create temp table _sim_c (n bigint primary key) on commit drop;
  create temp table _sim_cx (n bigint primary key) on commit drop;
  create temp table _sim_t (t bigint primary key) on commit drop;
  create temp table _sim_w (t bigint primary key) on commit drop;
  create temp table _sim_b (t bigint primary key) on commit drop;
  create temp table _sim_x (t bigint primary key) on commit drop;
  select md5(coalesce((select string_agg(t || ':' || n || ':' || m || ':' || coalesce(cn, ''), ',' order by t, n, m) from _sim_g), '')
             || '|' || coalesce((select string_agg(n || ':' || cuenta || ':' || por_verificar, ',' order by n) from _sim_v), '')
             || '|' || coalesce((select string_agg(n::text, ',' order by n) from _sim_f), ''))
    into v_h;
  return v_h;
end $$;
comment on function redes.f_sim_grafo() is 'Corte 9b: arma en tablas temporales (de la transacción) el grafo vigente de acueducto, sus válvulas y sus fuentes; devuelve la huella de esa red. No escribe tablas de la base.';

-- ---------- llena _sim_w: los tramos con agua desde las fuentes que no están en el segmento (_sim_s), con las válvulas de _sim_c cerradas ----------
-- Un tramo tiene agua si uno de sus extremos se alcanza y ese extremo no es una válvula cerrada.
create function redes.f_sim_llenar_agua() returns integer
language plpgsql volatile security definer set search_path = redes, pg_temp as $$
declare v_n integer;
begin
  truncate pg_temp._sim_w;
  insert into pg_temp._sim_w (t)
  with recursive r(n) as (
    select f.n from pg_temp._sim_f f where not exists (select 1 from pg_temp._sim_s s where s.n = f.n)
    union
    select g.m from r join pg_temp._sim_g g on g.n = r.n where not exists (select 1 from pg_temp._sim_c c where c.n = g.n))
  select distinct g.t from r join pg_temp._sim_g g on g.n = r.n where not exists (select 1 from pg_temp._sim_c c where c.n = r.n);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ---------- un escenario: segmento, válvulas del borde, tramos sin agua y contratos ----------
-- p_amplio: las «sin definir» no detienen (solo las «cierra»). p_pasan: nodos que no detienen aunque sean válvulas (la que se interviene, la que «no cierra»).
-- Deja en _sim_c las válvulas del borde y en _sim_x los tramos sin agua (para que quien llama lea más). p_lista: cuántas válvulas devolver (las más cercanas).
create function redes.f_sim_escenario(p_ini bigint[], p_tramo bigint, p_amplio boolean, p_pasan bigint[], p_ref geometry, p_lista integer)
returns jsonb
language plpgsql volatile security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_n_valv integer; v_n_seg integer; v_n_sin integer; v_n_contratos integer; v_long numeric; v_valvulas jsonb; v_dentro jsonb;
begin
  truncate pg_temp._sim_s, pg_temp._sim_c, pg_temp._sim_t, pg_temp._sim_x;
  insert into pg_temp._sim_s (n)
  with recursive r(n) as (
    select x from unnest(p_ini) x
    union
    select g.m from r join pg_temp._sim_g g on g.n = r.n
     where g.cn is null or (p_amplio and g.cn = 'sin_definir') or g.n = any (p_pasan))
  select n from r;
  -- el borde: válvulas alcanzadas que detienen (no se avanzó a través de ellas)
  insert into pg_temp._sim_c (n)
  select v.n from pg_temp._sim_s s join pg_temp._sim_v v on v.n = s.n
   where (v.cuenta = 'cierra' or (not p_amplio and v.cuenta = 'sin_definir')) and v.n <> all (p_pasan);
  get diagnostics v_n_valv = row_count;
  -- los tramos del segmento: los que salen de un nodo alcanzado que no es del borde, más el del trabajo
  insert into pg_temp._sim_t (t)
  select distinct g.t from pg_temp._sim_s s join pg_temp._sim_g g on g.n = s.n where not exists (select 1 from pg_temp._sim_c c where c.n = s.n);
  if p_tramo is not null then insert into pg_temp._sim_t (t) values (p_tramo) on conflict do nothing; end if;
  perform redes.f_sim_llenar_agua();
  -- sin agua: los del segmento y los que tenían agua sin cerrar nada y ya no la tienen (lo que la capa ya trae desconectado no es efecto del cierre)
  insert into pg_temp._sim_x (t)
  select t from pg_temp._sim_t
  union
  select b.t from pg_temp._sim_b b where not exists (select 1 from pg_temp._sim_w w where w.t = b.t);
  -- (con «= any (array(…))» los conteos van por el índice: las tablas temporales no tienen estadísticas)
  select count(*), coalesce(round(sum(m.longitud_m)), 0) into v_n_sin, v_long from redes.activo_vigente_mat m where m.activo_id = any (array(select t from pg_temp._sim_x));
  select count(*) into v_n_seg from pg_temp._sim_t;
  select count(distinct ct.contrato) into v_n_contratos from redes.contrato_tramo ct where ct.activo_id = any (array(select t from pg_temp._sim_x));
  select coalesce(jsonb_agg(y.j order by y.d, y.codigo), '[]') into v_valvulas
    from (select v.codigo, ST_Distance(v.geom::geography, p_ref::geography) as d,
                 redes.f_activo_corto(v.activo_id) || jsonb_build_object('efecto', v.efecto, 'por_verificar', v.por_verificar,
                   'distancia_m', round(ST_Distance(v.geom::geography, p_ref::geography)::numeric, 0),
                   'lat', round(ST_Y(v.geom)::numeric, 6), 'lon', round(ST_X(v.geom)::numeric, 6), 'nodo', v.n) as j
            from pg_temp._sim_c c join pg_temp._sim_v v on v.n = c.n
           order by 2, 1 limit greatest(p_lista, 0)) y;
  -- tanques o planta que quedan dentro del segmento (aislados con él)
  select jsonb_agg(redes.f_activo_corto(f.activo_id) order by f.activo_id) into v_dentro
    from pg_temp._sim_f f where exists (select 1 from pg_temp._sim_s s where s.n = f.n);
  return jsonb_build_object(
    'valvulas_total', v_n_valv, 'valvulas', v_valvulas,
    'aislable', v_n_valv > 0,      -- sin válvulas que cierren alrededor, no se puede aislar
    'tramos_segmento', v_n_seg, 'tramos_aguas_abajo', v_n_sin - v_n_seg, 'tramos_sin_agua', v_n_sin, 'longitud_sin_agua_m', v_long,
    'contratos', v_n_contratos, 'fuentes_aisladas', coalesce(v_dentro, '[]'));
end $$;

-- ---------- la simulación completa ----------
-- p_activo: el tramo o el nodo (válvula, accesorio, hidrante, macromedidor, tanque, planta) del trabajo. Devuelve el resultado (jsonb), sin guardar.
-- La clave «_contratos» (los contratos sin agua del escenario estrecho, si no pasan del tope) es interna: la RPC la quita antes de responder y la usa al guardar.
create function redes.f_simular_cierre(p_activo bigint) returns jsonb
language plpgsql volatile security definer set search_path = redes, public, extensions, pg_temp as $$
declare
  t0 timestamptz := clock_timestamp(); m redes.activo_vigente_mat%rowtype; v_huella text; v_ini bigint[]; v_tramo bigint; v_pasan bigint[] := '{}';
  e_x jsonb; e_y jsonb; e jsonb; v_no jsonb := '[]'; v_alt jsonb; v_dudosas jsonb; v_grande boolean; r record; v_ref geometry;
  v_k integer := coalesce(redes.f_param('sim_no_cierra_max'), 6)::integer;
  v_lista integer := coalesce(redes.f_param('sim_valvulas_lista_max'), 30)::integer;
  v_gr_t numeric := coalesce(redes.f_param('sim_segmento_grande_tramos'), 200);
  v_gr_c numeric := coalesce(redes.f_param('sim_segmento_grande_contratos'), 2000);
  v_tope_c integer := coalesce(redes.f_param('sim_contratos_guardar_max'), 20000)::integer;
  v_tramos jsonb; v_contratos jsonb;
begin
  select * into m from redes.activo_vigente_mat where activo_id = p_activo;
  if not found then perform tecnica.f_error('Ese activo no existe', 'P0002'); end if;
  if m.sistema <> 'acueducto' then perform tecnica.f_error('La simulación de cierre es solo para acueducto'); end if;
  if m.retirado then perform tecnica.f_error('Ese activo está retirado'); end if;
  v_huella := redes.f_sim_grafo();
  -- referencia para «la más cercana»: el punto medio del tramo (ST_PointOnSurface de una línea de dos vértices da una punta) o el punto del nodo
  v_ref := case when GeometryType(m.geom) = 'LINESTRING' then ST_LineInterpolatePoint(m.geom, 0.5)
                when GeometryType(m.geom) = 'MULTILINESTRING' and GeometryType(ST_LineMerge(m.geom)) = 'LINESTRING' then ST_LineInterpolatePoint(ST_LineMerge(m.geom), 0.5)
                else ST_PointOnSurface(m.geom) end;
  if m.prefijo in ('RED', 'CON') then
    if not exists (select 1 from pg_temp._sim_g g where g.t = m.activo_id) then
      perform tecnica.f_error(format('El tramo %s no conduce agua según la red (estado «%s»): no hay válvulas que cerrar', m.codigo,
                                     (select s.nombre from redes.estados_activo s where s.codigo = m.estado_codigo)));
    end if;
    select array_agg(distinct g.n) into v_ini from pg_temp._sim_g g where g.t = m.activo_id;
    v_tramo := m.activo_id;
  else
    select array_agg(distinct g.n) into v_ini from pg_temp._sim_g g join redes.nodos n on n.id = g.n where n.activo_id = m.activo_id;
    if v_ini is null then perform tecnica.f_error(format('%s no es un nodo de la red de acueducto en operación: elija el tramo', m.codigo)); end if;
    if m.prefijo = 'VAL' then v_pasan := v_ini; end if;      -- la válvula que se interviene no sirve para aislarse a sí misma
  end if;
  -- con agua sin cerrar nada (la base de comparación)
  perform redes.f_sim_llenar_agua();
  insert into pg_temp._sim_b (t) select t from pg_temp._sim_w;
  -- estrecho (X): las «sin definir» cierran. Da las válvulas a cerrar
  e_x := redes.f_sim_escenario(v_ini, v_tramo, false, v_pasan, v_ref, v_lista);
  insert into pg_temp._sim_cx (n) select n from pg_temp._sim_c;
  v_grande := (e_x ->> 'tramos_segmento')::integer > v_gr_t or (e_x ->> 'contratos')::integer > v_gr_c;
  if (e_x ->> 'tramos_segmento')::integer <= v_gr_t then
    select jsonb_agg(a.codigo order by a.codigo) into v_tramos from pg_temp._sim_t t join redes.activo_vigente_mat a on a.activo_id = t.t;
  end if;
  if (e_x ->> 'contratos')::integer <= v_tope_c then
    select coalesce(jsonb_agg(c order by c), '[]') into v_contratos
      from (select distinct ct.contrato as c from pg_temp._sim_x x join redes.contrato_tramo ct on ct.activo_id = x.t) s;
  end if;
  -- «si esta válvula no cierra»: las más cercanas del escenario estrecho, una por una (aparecen las siguientes hacia afuera).
  -- Con un segmento grande no se calcula: ya con todas cerrando no se aísla en pequeño.
  if not v_grande then
    for r in select (x ->> 'nodo')::bigint as n, x ->> 'codigo' as codigo from jsonb_array_elements(e_x -> 'valvulas') x limit v_k loop
      e := redes.f_sim_escenario(v_ini, v_tramo, false, v_pasan || r.n, v_ref, 0);
      v_no := v_no || jsonb_build_object('valvula', r.codigo,
        'cerrar_en_su_lugar', (select coalesce(jsonb_agg(y.j order by y.d, y.codigo), '[]')
                                 from (select v.codigo, ST_Distance(v.geom::geography, v_ref::geography) as d,
                                              jsonb_build_object('codigo', v.codigo, 'efecto', v.efecto, 'por_verificar', v.por_verificar,
                                                'distancia_m', round(ST_Distance(v.geom::geography, v_ref::geography)::numeric, 0),
                                                'lat', round(ST_Y(v.geom)::numeric, 6), 'lon', round(ST_X(v.geom)::numeric, 6)) as j
                                         from pg_temp._sim_c c join pg_temp._sim_v v on v.n = c.n
                                        where not exists (select 1 from pg_temp._sim_cx x where x.n = c.n)
                                        order by 2, 1 limit greatest(v_lista, 1)) y),
        'valvulas_total', e -> 'valvulas_total', 'tramos_sin_agua', e -> 'tramos_sin_agua', 'contratos', e -> 'contratos');
    end loop;
  end if;
  -- alternativas: de esos casos, los 2 que dejan menos contratos sin agua (sirven si la primera opción no se puede)
  select coalesce(jsonb_agg(s.a order by (s.a ->> 'contratos')::integer, s.a ->> 'valvula'), '[]') into v_alt
    from (select a from jsonb_array_elements(v_no) a order by (a ->> 'contratos')::integer, a ->> 'valvula' limit 2) s;
  -- amplio (Y, el que vale): solo las «cierra» detienen
  e_y := redes.f_sim_escenario(v_ini, v_tramo, true, v_pasan, v_ref, v_lista);
  -- las «sin definir» que hacen la diferencia entre X y Y: las del borde estrecho (que Técnica defina primero su efecto), las más cercanas
  select coalesce(jsonb_agg(x ->> 'codigo' order by (x ->> 'distancia_m')::numeric), '[]') into v_dudosas
    from jsonb_array_elements(e_x -> 'valvulas') x where x ->> 'efecto' = 'sin_definir';
  return jsonb_build_object(
    'activo', redes.f_activo_corto(m.activo_id) || jsonb_build_object('sistema', m.sistema, 'lat', round(ST_Y(v_ref)::numeric, 6), 'lon', round(ST_X(v_ref)::numeric, 6)),
    'red', jsonb_build_object('huella', v_huella, 'tramos', (select count(distinct t) from pg_temp._sim_g), 'valvulas', (select count(*) from pg_temp._sim_v),
                              'fuentes', (select count(*) from pg_temp._sim_f), 'fuente', 'red registrada en el geoportal (no el modelo)'),
    'estrecho', e_x, 'amplio', e_y,
    'contratos_min', least((e_x ->> 'contratos')::integer, (e_y ->> 'contratos')::integer),
    'contratos_max', greatest((e_x ->> 'contratos')::integer, (e_y ->> 'contratos')::integer),
    'rango', (e_x ->> 'contratos') <> (e_y ->> 'contratos'),
    'dudosas', v_dudosas,
    'segmento_grande', v_grande,
    'si_no_cierra', v_no, 'alternativas', v_alt,
    'tramos', v_tramos,
    '_contratos', v_contratos,
    'notas', jsonb_build_array(
      'Según la red registrada en el geoportal: no tiene en cuenta presiones ni caudales.',
      'Contratos por el tramo más cercano (hasta 30 m): es una aproximación.',
      'Las válvulas con efecto «sin definir» dan el rango: el número menor si todas cierran; el mayor si ninguna cierra.',
      'Falta ubicar en la red la válvula de retención P-24 y las bombas.')
      || case when v_grande then jsonb_build_array('Con las válvulas registradas este tramo no se aísla en pequeño: se muestran las válvulas más cercanas del borde.') else '[]' end,
    'ms', round(extract(epoch from clock_timestamp() - t0) * 1000));
end $$;
comment on function redes.f_simular_cierre(bigint) is 'Corte 9b (§17): qué válvulas cerrar para aislar un tramo o un nodo de acueducto, qué tramos y cuántos contratos quedan sin agua (rango N-9), si una no cierra y alternativas. Sobre la red registrada, sin guardar.';

-- ---------- el tramo de acueducto en operación más cercano a un punto (para un daño sin activo identificado) ----------
create function redes.f_sim_tramo_cercano(p_lat numeric, p_lon numeric) returns bigint
language plpgsql stable security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_p geometry; v_id bigint; v_d numeric := coalesce(redes.f_param('distancia_activo_cercano_m'), 30);
begin
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then perform tecnica.f_error('Elija el tramo o marque el punto'); end if;
  v_p := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326);
  select m.activo_id into v_id from redes.activo_vigente_mat m
   where m.sistema = 'acueducto' and m.prefijo in ('RED', 'CON') and m.cuenta_vigente and not m.retirado
     and ST_DWithin(m.geom::geography, v_p::geography, v_d)
   order by m.geom <-> v_p limit 1;
  if v_id is null then perform tecnica.f_error(format('No hay un tramo de acueducto en operación a menos de %s m de ese punto: elija el tramo', v_d)); end if;
  return v_id;
end $$;

-- ---------- quién puede simular: quien captura daños y fallas o intervenciones (mantenimiento), el supervisor y el administrador ----------
create function redes.f_sim_autorizar(p_solicitante text) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
begin
  begin
    return redes.f_autorizar_captura_redes(p_solicitante, 'danos_fallas');
  exception when sqlstate '42501' then
    return redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento');
  end;
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1b: cierre real) · 21 — FUNCIONES INTERNAS de los cortes vigentes. PROPUESTA.
-- · Cada maniobra («cerrar», «abrir») se guarda en redes.valvula_maniobras (solo agregar) y, en la MISMA transacción, se saca la FOTO del corte vigente:
--   con TODAS las válvulas cerradas en ese momento, qué tramos quedan sin agua y su papel:
--     · «cerrado»: dentro del sector aislado donde está el trabajo (el daño o la intervención), entre válvulas cerradas;
--     · «afectado»: sin agua aguas abajo del cierre. Si un tramo es las dos cosas, gana «cerrado» (David, 17-nov).
--   y los agrupa en ZONAS (cada grupo conectado de tramos sin agua), con sus contratos (conteo, sin nombres), su centro y su caja.
-- · La tesela, la franja «N zonas sin agua» y los Avisos LEEN la última foto: ninguna petición de lectura recalcula (regla del 6c).
-- · Reutiliza el recorrido de la 1a (redes.f_sim_grafo y sus tablas temporales). Un cierre sin trabajo (solo supervisor, con motivo) no marca «cerrado»:
--   todo lo que deja sin agua sale como «afectado».
-- =====================================================================

-- ---------- los cierres vigentes: el último «cerrar» de cada válvula que no tiene su «abrir» ----------
create function redes.f_cierres_vigentes() returns table (cierre_id bigint, valvula_id bigint, dano_id uuid, intervencion_id uuid, hecho_en timestamptz, autor text, motivo text)
language sql stable security definer set search_path = redes, pg_temp as $$
  select m.id, m.valvula_id, m.dano_id, m.intervencion_id, m.hecho_en, m.autor, m.motivo
    from redes.valvula_maniobras m
   where m.tipo = 'cerrar' and not exists (select 1 from redes.valvula_maniobras a where a.cierre_id = m.id and a.tipo = 'abrir') $$;

-- ---------- la hora estimada de regreso vigente de un cierre: la del último ajuste, o la que puso quien cerró ----------
create function redes.f_cierre_regreso(p_cierre bigint) returns timestamptz
language sql stable security definer set search_path = redes, pg_temp as $$
  select m.regreso_estimado from redes.valvula_maniobras m
   where (m.id = p_cierre or (m.cierre_id = p_cierre and m.tipo = 'regreso')) order by m.id desc limit 1 $$;

-- ---------- la foto del corte vigente. Devuelve el id de la foto ----------
create function redes.f_cortes_foto(p_maniobra bigint, p_autor text, p_motivo text default null) returns bigint
language plpgsql volatile security definer set search_path = redes, public, extensions, pg_temp as $$
declare
  t0 timestamptz := clock_timestamp(); v_h text; v_foto bigint; v_zona integer := 0; v_semilla bigint; r record; v_ini bigint[]; v_act bigint;
  m redes.activo_vigente_mat%rowtype; v_lat numeric; v_lon numeric;
begin
  v_h := redes.f_sim_grafo();
  if to_regclass('pg_temp._cx') is not null then drop table pg_temp._cx; end if;
  if to_regclass('pg_temp._cc') is not null then drop table pg_temp._cc; end if;
  if to_regclass('pg_temp._cz') is not null then drop table pg_temp._cz; end if;
  -- los cierres vigentes y el nodo de la red de cada válvula (nulo si la válvula no es un nodo de la red en operación)
  create temp table _cx on commit drop as
  select c.cierre_id, c.valvula_id, c.dano_id, c.intervencion_id,
         (select min(n.id) from redes.nodos n where n.activo_id = c.valvula_id and exists (select 1 from pg_temp._sim_g g where g.n = n.id)) as n
    from redes.f_cierres_vigentes() c;
  create temp table _cc (t bigint primary key) on commit drop;      -- tramos «cerrado»
  create temp table _cz (t bigint primary key, zona integer) on commit drop;      -- zona de cada tramo sin agua
  -- con agua sin cerrar nada (_sim_b) y con las válvulas cerradas (_sim_w); sin agua = _sim_x
  perform redes.f_sim_llenar_agua();
  insert into pg_temp._sim_b (t) select t from pg_temp._sim_w;
  insert into pg_temp._sim_c (n) select distinct n from pg_temp._cx where n is not null;
  perform redes.f_sim_llenar_agua();
  insert into pg_temp._sim_x (t) select b.t from pg_temp._sim_b b where not exists (select 1 from pg_temp._sim_w w where w.t = b.t);
  -- «cerrado»: desde el lugar de cada trabajo (daño o intervención con cierres vigentes), hasta las válvulas cerradas, entre los tramos sin agua
  for r in select distinct x.dano_id, x.intervencion_id from pg_temp._cx x where x.dano_id is not null or x.intervencion_id is not null loop
    if r.dano_id is not null then select d.activo_id, d.lat, d.lon into v_act, v_lat, v_lon from redes.danos d where d.id = r.dano_id;
    else select i.activo_id, i.lat, i.lon into v_act, v_lat, v_lon from redes.intervenciones i where i.id = r.intervencion_id;
    end if;
    v_ini := null;
    if v_act is not null then
      select * into m from redes.activo_vigente_mat where activo_id = v_act;
      if m.prefijo in ('RED', 'CON') then select array_agg(distinct g.n) into v_ini from pg_temp._sim_g g where g.t = v_act;
      else select array_agg(distinct g.n) into v_ini from pg_temp._sim_g g join redes.nodos n on n.id = g.n where n.activo_id = v_act;
      end if;
    end if;
    if v_ini is null and v_lat is not null then      -- sin activo en la red: el tramo en operación más cercano al punto (si hay)
      begin
        select array_agg(distinct g.n) into v_ini from pg_temp._sim_g g where g.t = redes.f_sim_tramo_cercano(v_lat, v_lon);
      exception when others then v_ini := null;
      end;
    end if;
    continue when v_ini is null;
    insert into pg_temp._cc (t)
    with recursive s(n) as (
      select x from unnest(v_ini) x
      union
      select g.m from s join pg_temp._sim_g g on g.n = s.n where not exists (select 1 from pg_temp._sim_c c where c.n = g.n))
    select distinct g.t from s join pg_temp._sim_g g on g.n = s.n
     where not exists (select 1 from pg_temp._sim_c c where c.n = s.n) and exists (select 1 from pg_temp._sim_x x where x.t = g.t)
    on conflict do nothing;
  end loop;
  -- zonas: grupos conectados de tramos sin agua (se conectan también a través de una válvula cerrada: el sector y lo de aguas abajo son la misma zona)
  loop
    select min(x.t) into v_semilla from pg_temp._sim_x x where not exists (select 1 from pg_temp._cz z where z.t = x.t);
    exit when v_semilla is null;
    v_zona := v_zona + 1;
    insert into pg_temp._cz (t, zona)
    with recursive s(n) as (
      select g.n from pg_temp._sim_g g where g.t = v_semilla
      union
      select g.m from s join pg_temp._sim_g g on g.n = s.n where exists (select 1 from pg_temp._sim_x x where x.t = g.t))
    select distinct g.t, v_zona from s join pg_temp._sim_g g on g.n = s.n where exists (select 1 from pg_temp._sim_x x where x.t = g.t)
    on conflict do nothing;
  end loop;
  -- la foto
  insert into redes.corte_fotos (maniobra_id, motivo, red_huella, valvulas_cerradas, valvulas_fuera_de_red, tramos_cerrados, tramos_afectados,
                                 contratos_cerrados, contratos_afectados, zonas, ms, autor)
  select p_maniobra, p_motivo, v_h, (select count(*) from pg_temp._cx), (select count(*) from pg_temp._cx where n is null),
         (select count(*) from pg_temp._cc), (select count(*) from pg_temp._sim_x) - (select count(*) from pg_temp._cc),
         (select count(distinct ct.contrato) from redes.contrato_tramo ct where ct.activo_id = any (array(select t from pg_temp._cc))),
         (select count(distinct ct.contrato) from redes.contrato_tramo ct
           where ct.activo_id = any (array(select x.t from pg_temp._sim_x x where not exists (select 1 from pg_temp._cc c where c.t = x.t)))),
         v_zona, round(extract(epoch from clock_timestamp() - t0) * 1000), p_autor      -- ms: el cálculo (grafo, recorridos y zonas)
  returning id into v_foto;
  insert into redes.corte_foto_tramos (foto_id, activo_id, papel, zona)
  select v_foto, z.t, case when exists (select 1 from pg_temp._cc c where c.t = z.t) then 'cerrado' else 'afectado' end, z.zona from pg_temp._cz z;
  -- cada cierre con su zona (la de los tramos sin agua que tocan su válvula); nula si su válvula no deja a nadie sin agua o no está en la red
  insert into redes.corte_foto_valvulas (foto_id, cierre_id, valvula_id, en_red, zona)
  select v_foto, x.cierre_id, x.valvula_id, x.n is not null,
         (select min(z.zona) from pg_temp._sim_g g join pg_temp._cz z on z.t = g.t where g.n = x.n)
    from pg_temp._cx x;
  insert into redes.corte_foto_zonas (foto_id, zona, tramos_cerrados, tramos_afectados, contratos_cerrados, contratos_afectados, lat, lon, caja)
  select v_foto, z.zona,
         count(*) filter (where ft.papel = 'cerrado'), count(*) filter (where ft.papel = 'afectado'),
         (select count(distinct ct.contrato) from redes.corte_foto_tramos f2 join redes.contrato_tramo ct on ct.activo_id = f2.activo_id
           where f2.foto_id = v_foto and f2.zona = z.zona and f2.papel = 'cerrado'),
         (select count(distinct ct.contrato) from redes.corte_foto_tramos f2 join redes.contrato_tramo ct on ct.activo_id = f2.activo_id
           where f2.foto_id = v_foto and f2.zona = z.zona and f2.papel = 'afectado'),
         round(ST_Y(ST_PointOnSurface(ST_Collect(a.geom)))::numeric, 6), round(ST_X(ST_PointOnSurface(ST_Collect(a.geom)))::numeric, 6),
         array[round(ST_XMin(ST_Extent(a.geom))::numeric, 6), round(ST_YMin(ST_Extent(a.geom))::numeric, 6),
               round(ST_XMax(ST_Extent(a.geom))::numeric, 6), round(ST_YMax(ST_Extent(a.geom))::numeric, 6)]
    from pg_temp._cz z join redes.corte_foto_tramos ft on ft.foto_id = v_foto and ft.activo_id = z.t
    join redes.activo_vigente_mat a on a.activo_id = z.t
   group by z.zona;
  return v_foto;
end $$;
comment on function redes.f_cortes_foto(bigint, text, text) is 'Corte 9b (1b): saca la foto del corte vigente (tramos «cerrado» y «afectado», zonas, contratos) con todas las válvulas cerradas en este momento. Solo agregar.';

-- ---------- las válvulas cerradas para los Avisos del 12 (las lee tecnica.f_avisos): nivel por horas cerrada ----------
create function redes.f_cortes_para_avisos(p_ahora timestamptz, p_naranja_h numeric, p_rojo_h numeric)
returns table (nivel text, codigo text, registro text, hecho_en timestamptz, horas numeric)
language sql stable security definer set search_path = redes, pg_temp as $$
  select case when extract(epoch from p_ahora - c.hecho_en) / 3600 >= p_rojo_h then 'rojo' else 'naranja' end,
         a.codigo, coalesce(d.codigo, i.codigo), c.hecho_en, round((extract(epoch from p_ahora - c.hecho_en) / 3600)::numeric, 1)
    from redes.f_cierres_vigentes() c
    join redes.activos a on a.id = c.valvula_id
    left join redes.danos d on d.id = c.dano_id
    left join redes.intervenciones i on i.id = c.intervencion_id
   where extract(epoch from p_ahora - c.hecho_en) / 3600 >= p_naranja_h $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1) · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del Corte 10 publicado) con cambios exactos, aplicados una sola vez.
--   · redes.f_param_entero: las unidades «tramos», «contratos», «válvulas» y «simulaciones» son números enteros (parámetros de la simulación);
--   · tecnica.f_avisos (Corte 12): el aviso D10 «válvula cerrada hace más de X horas» (Fase 1b). Solo agrega el bloque; lo demás queda igual.
-- =====================================================================
-- redes.f_param_entero(text)
CREATE OR REPLACE FUNCTION redes.f_param_entero(p_unidad text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select p_unidad in ('fotos', 'documentos', 'materiales', 'activos', 'días', 'horas', 'filas', 'bytes', 'zoom', 'hoja', 'tramos', 'contratos', 'válvulas', 'simulaciones') $function$;

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
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1) · 26 — RPC de la simulación de cierre (las llama la Edge geoportal-redes; las rutas van en la Fase 4).
--   · geoportal_redes_simulacion_cierre: «¿Qué válvulas cierro?» desde un tramo o nodo (o el tramo más cercano a un punto). No guarda nada.
--   · geoportal_redes_simulacion_guardar: la recalcula en el servidor y la guarda con el daño (DAN-…) o la intervención (ITV-…). Solo agregar.
--   · geoportal_redes_simulaciones: las guardadas de un daño o una intervención.
-- Quién: quien captura daños y fallas o intervenciones, el supervisor y el administrador. Guardar: quien registró el daño o la intervención, o el supervisor.
-- Volátiles: la simulación arma tablas temporales de la transacción (la Edge llama por POST).
-- =====================================================================
create function public.geoportal_redes_simulacion_cierre(p_solicitante text, p_activo text default null, p_lat numeric default null, p_lon numeric default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_sim_autorizar(p_solicitante); v_id bigint;
begin
  if nullif(btrim(coalesce(p_activo, '')), '') is not null then v_id := redes.f_buscar_activo(p_activo);
  else v_id := redes.f_sim_tramo_cercano(p_lat, p_lon);
  end if;
  return redes.f_simular_cierre(v_id) - '_contratos';
end $$;

create function public.geoportal_redes_simulacion_guardar(p_solicitante text, p_registro text, p_activo text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare
  v_cod text := upper(btrim(coalesce(p_registro, ''))); v_email text; v_super boolean;
  v_dano uuid; v_itv uuid; v_act bigint; v_sis text; v_lat numeric; v_lon numeric; v_autor text; v_id bigint; j jsonb; v_sid bigint;
begin
  if v_cod ~ '^DAN-[0-9]{6}$' then
    v_email := redes.f_autorizar_captura_redes(p_solicitante, 'danos_fallas');
    select d.id, d.activo_id, d.sistema, d.lat, d.lon, d.autor into v_dano, v_act, v_sis, v_lat, v_lon, v_autor from redes.danos d where d.codigo = v_cod;
    if v_dano is null then perform tecnica.f_error(format('No hay ningún daño o falla con el código «%s»', v_cod), 'P0002'); end if;
  elsif v_cod ~ '^ITV-[0-9]{6}$' then
    v_email := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento');
    select i.id, i.activo_id, i.sistema, i.lat, i.lon, i.autor into v_itv, v_act, v_sis, v_lat, v_lon, v_autor from redes.intervenciones i where i.codigo = v_cod;
    if v_itv is null then perform tecnica.f_error(format('No hay ninguna intervención con el código «%s»', v_cod), 'P0002'); end if;
  else
    perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
  end if;
  v_super := (select p.perfil in ('admin', 'supervisor') from redes.f_perfil_lectura(v_email) p);
  if not v_super and v_autor <> v_email then
    raise exception 'Solo quien lo registró, el supervisor o el administrador guardan la simulación' using errcode = '42501';
  end if;
  if v_sis <> 'acueducto' then perform tecnica.f_error('La simulación de cierre es solo para acueducto'); end if;
  if (select count(*) from redes.simulaciones_cierre s where s.dano_id = v_dano or s.intervencion_id = v_itv) >= coalesce(redes.f_param('sim_guardadas_max'), 20) then
    perform tecnica.f_error(format('%s ya tiene %s simulaciones guardadas (el máximo)', v_cod, coalesce(redes.f_param('sim_guardadas_max'), 20)));
  end if;
  v_id := case when nullif(btrim(coalesce(p_activo, '')), '') is not null then redes.f_buscar_activo(p_activo)
               when v_act is not null then v_act
               else redes.f_sim_tramo_cercano(v_lat, v_lon) end;
  j := redes.f_simular_cierre(v_id);
  insert into redes.simulaciones_cierre (dano_id, intervencion_id, activo_id, red_huella, valvulas, contratos_min, contratos_max, segmento_grande, resultado, contratos, ms, autor)
  values (v_dano, v_itv, v_id, j -> 'red' ->> 'huella', (j -> 'estrecho' ->> 'valvulas_total')::integer, (j ->> 'contratos_min')::integer, (j ->> 'contratos_max')::integer,
          (j ->> 'segmento_grande')::boolean, j - '_contratos',
          case when jsonb_typeof(j -> '_contratos') = 'array' then array(select jsonb_array_elements_text(j -> '_contratos')) end,
          (j ->> 'ms')::integer, v_email)
  returning id into v_sid;
  perform tecnica.f_auditar(v_email, 'redes_simulacion_guardar', v_cod, jsonb_build_object('simulacion', v_sid, 'activo', j -> 'activo' ->> 'codigo',
          'contratos_min', j -> 'contratos_min', 'contratos_max', j -> 'contratos_max', 'valvulas', j -> 'estrecho' -> 'valvulas_total'), null);
  return jsonb_build_object('id', v_sid, 'registro', v_cod) || (j - '_contratos');
end $$;

create function public.geoportal_redes_simulaciones(p_solicitante text, p_registro text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_sim_autorizar(p_solicitante); v_cod text := upper(btrim(coalesce(p_registro, ''))); v_dano uuid; v_itv uuid;
begin
  if v_cod ~ '^DAN-[0-9]{6}$' then select id into v_dano from redes.danos where codigo = v_cod;
  elsif v_cod ~ '^ITV-[0-9]{6}$' then select id into v_itv from redes.intervenciones where codigo = v_cod;
  else perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
  end if;
  if v_dano is null and v_itv is null then perform tecnica.f_error(format('No hay ningún daño ni intervención con el código «%s»', v_cod), 'P0002'); end if;
  return jsonb_build_object('registro', v_cod, 'simulaciones', coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'creado_en', s.creado_en, 'autor', s.autor, 'activo', a.codigo,
                                        'valvulas', s.valvulas, 'contratos_min', s.contratos_min, 'contratos_max', s.contratos_max,
                                        'segmento_grande', s.segmento_grande, 'red_huella', s.red_huella, 'resultado', s.resultado) order by s.id desc)
      from redes.simulaciones_cierre s join redes.activos a on a.id = s.activo_id
     where (v_dano is not null and s.dano_id = v_dano) or (v_itv is not null and s.intervencion_id = v_itv)), '[]'::jsonb));
end $$;

-- =====================================================================
-- Fase 1b · el cierre real (David, 17-nov):
--   · geoportal_redes_valvula_maniobra: «válvula cerrada» / «válvula abierta». Ligada a un daño o una intervención: el operador de redes (daños y fallas o
--     mantenimiento) o el supervisor. Sin daño ni intervención: solo el supervisor y con motivo. Saca la foto del corte vigente en la misma transacción.
--   · geoportal_redes_corte_regreso: ajusta la hora estimada de regreso del servicio (quien cerró o el supervisor).
--   · geoportal_redes_cortes_vigentes: zonas sin agua, válvulas cerradas y conteos (la franja, las tarjetas y la leyenda). Lee la última foto.
--   · geoportal_redes_cortes_recalcular: el supervisor saca una foto nueva (si la red cambió después de la última maniobra).
--   · geoportal_redes_geovisor_mvt_cortes: la tesela del modo «Afectaciones» (tramos cerrados y afectados, válvulas cerradas). Lee la última foto.
-- =====================================================================
create function public.geoportal_redes_valvula_maniobra(p_solicitante text, p_valvula text, p_tipo text, p_registro text default null, p_motivo text default null,
                                                       p_hecho_en text default null, p_regreso text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare
  v_email text; v_super boolean; v_cod text := nullif(upper(btrim(coalesce(p_registro, ''))), ''); v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_val bigint; m redes.activo_vigente_mat%rowtype; v_dano uuid; v_itv uuid; v_sis text; v_hecho timestamptz; v_regreso timestamptz;
  c record; v_man bigint; v_foto bigint; f redes.corte_fotos%rowtype; v_ahora timestamptz := clock_timestamp();
begin
  if coalesce(p_tipo, '') not in ('cerrar', 'abrir') then perform tecnica.f_error('Elija: válvula cerrada o válvula abierta'); end if;
  -- una maniobra a la vez: la foto debe ver todas las válvulas cerradas en este momento
  perform pg_advisory_xact_lock(hashtext('redes.cortes_vigentes'));
  v_val := redes.f_buscar_activo(p_valvula);
  select * into m from redes.activo_vigente_mat where activo_id = v_val;
  if m.prefijo <> 'VAL' or m.sistema <> 'acueducto' then perform tecnica.f_error(format('%s no es una válvula de acueducto', m.codigo)); end if;
  if m.retirado then perform tecnica.f_error(format('La válvula %s está retirada', m.codigo)); end if;
  select * into c from redes.f_cierres_vigentes() x where x.valvula_id = v_val;
  if p_tipo = 'abrir' then
    if c.cierre_id is null then perform tecnica.f_error(format('La válvula %s no está cerrada', m.codigo)); end if;
    v_dano := c.dano_id; v_itv := c.intervencion_id;      -- la apertura pertenece al mismo daño o intervención que el cierre
  else
    if c.cierre_id is not null then
      perform tecnica.f_error(format('La válvula %s ya está cerrada desde %s', m.codigo, to_char(c.hecho_en at time zone 'America/Bogota', 'DD/MM HH24:MI')));
    end if;
    if v_cod ~ '^DAN-[0-9]{6}$' then
      select d.id, d.sistema into v_dano, v_sis from redes.danos d where d.codigo = v_cod;
      if v_dano is null then perform tecnica.f_error(format('No hay ningún daño o falla con el código «%s»', v_cod), 'P0002'); end if;
    elsif v_cod ~ '^ITV-[0-9]{6}$' then
      select i.id, i.sistema into v_itv, v_sis from redes.intervenciones i where i.codigo = v_cod;
      if v_itv is null then perform tecnica.f_error(format('No hay ninguna intervención con el código «%s»', v_cod), 'P0002'); end if;
    elsif v_cod is not null then perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
    end if;
    if v_sis is not null and v_sis <> 'acueducto' then perform tecnica.f_error('Ese daño o intervención no es de acueducto'); end if;
  end if;
  -- quién: con daño, quien captura daños y fallas; con intervención, mantenimiento; sin ninguno, solo el supervisor (y con motivo)
  if v_dano is not null then v_email := redes.f_autorizar_captura_redes(p_solicitante, 'danos_fallas');
  elsif v_itv is not null then v_email := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento');
  else
    v_email := redes.f_supervisor(p_solicitante, 'cierran o abren una válvula sin daño ni intervención');
    if v_motivo is null or length(v_motivo) < 10 then perform tecnica.f_error('Sin daño ni intervención, escriba el motivo (al menos 10 letras)'); end if;
  end if;
  -- cuándo: ahora, o lo hecho en campo y registrado después (con tope); nunca en el futuro ni antes del cierre
  v_hecho := coalesce(redes.f_instante(p_hecho_en, 'hora de la maniobra'), v_ahora);
  if v_hecho > v_ahora + interval '5 minutes' then perform tecnica.f_error('La hora de la maniobra no puede ser futura'); end if;
  if v_hecho < v_ahora - make_interval(secs => (coalesce(redes.f_param('corte_horas_atras_max'), 48) * 3600)::double precision) then
    perform tecnica.f_error(format('La hora de la maniobra no puede ser de hace más de %s horas', coalesce(redes.f_param('corte_horas_atras_max'), 48)));
  end if;
  if p_tipo = 'abrir' and v_hecho < c.hecho_en then perform tecnica.f_error('La válvula no se puede abrir antes de la hora en que se cerró'); end if;
  v_regreso := redes.f_instante(p_regreso, 'regreso estimado del servicio');
  if v_regreso is not null and p_tipo <> 'cerrar' then perform tecnica.f_error('La hora estimada de regreso se pone al cerrar'); end if;
  if v_regreso is not null and (v_regreso <= v_hecho or v_regreso > v_hecho + interval '30 days') then
    perform tecnica.f_error('La hora estimada de regreso debe ser después del cierre y antes de 30 días');
  end if;
  insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, dano_id, intervencion_id, motivo, regreso_estimado, hecho_en, autor)
  values (v_val, p_tipo, case when p_tipo = 'abrir' then c.cierre_id end, v_dano, v_itv, v_motivo, v_regreso, v_hecho, v_email)
  returning id into v_man;
  v_foto := redes.f_cortes_foto(v_man, v_email);
  select * into f from redes.corte_fotos where id = v_foto;
  perform tecnica.f_auditar(v_email, 'redes_valvula_' || p_tipo, m.codigo, jsonb_build_object('maniobra', v_man, 'registro', coalesce(v_cod, (select codigo from redes.danos where id = v_dano),
          (select codigo from redes.intervenciones where id = v_itv)), 'foto', v_foto, 'zonas', f.zonas, 'ms', f.ms), null);
  return jsonb_build_object('maniobra', v_man, 'valvula', m.codigo, 'estado', case when p_tipo = 'cerrar' then 'cerrada' else 'abierta' end, 'hecho_en', v_hecho,
    'en_red', exists (select 1 from redes.corte_foto_valvulas fv where fv.foto_id = v_foto and fv.valvula_id = v_val and fv.en_red) or p_tipo = 'abrir',
    'zona', (select fv.zona from redes.corte_foto_valvulas fv where fv.foto_id = v_foto and fv.valvula_id = v_val),
    'vigente', jsonb_build_object('zonas', f.zonas, 'valvulas_cerradas', f.valvulas_cerradas, 'contratos', f.contratos_cerrados + f.contratos_afectados,
                                  'tramos_cerrados', f.tramos_cerrados, 'tramos_afectados', f.tramos_afectados, 'ms', f.ms));
end $$;

create function public.geoportal_redes_corte_regreso(p_solicitante text, p_valvula text, p_regreso text, p_motivo text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_sim_autorizar(p_solicitante); v_val bigint := redes.f_buscar_activo(p_valvula); c record; v_reg timestamptz; v_man bigint; v_super boolean;
begin
  select * into c from redes.f_cierres_vigentes() x where x.valvula_id = v_val;
  if c.cierre_id is null then perform tecnica.f_error('Esa válvula no está cerrada'); end if;
  v_super := (select p.perfil in ('admin', 'supervisor') from redes.f_perfil_lectura(v_email) p);
  if not v_super and c.autor <> v_email then raise exception 'Solo quien cerró la válvula o el supervisor ajustan la hora de regreso' using errcode = '42501'; end if;
  v_reg := redes.f_instante(p_regreso, 'regreso estimado del servicio');
  if v_reg is null then perform tecnica.f_error('Escriba la hora estimada de regreso del servicio'); end if;
  if v_reg <= c.hecho_en or v_reg > c.hecho_en + interval '30 days' then perform tecnica.f_error('La hora estimada de regreso debe ser después del cierre y antes de 30 días'); end if;
  insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, dano_id, intervencion_id, motivo, regreso_estimado, hecho_en, autor)
  values (v_val, 'regreso', c.cierre_id, c.dano_id, c.intervencion_id, nullif(btrim(coalesce(p_motivo, '')), ''), v_reg, clock_timestamp(), v_email)
  returning id into v_man;
  return jsonb_build_object('maniobra', v_man, 'regreso_estimado', v_reg);
end $$;

-- lo que ve cualquiera que entra al geovisor (todos los perfiles del geovisor): solo conteos; quién = el nombre del funcionario de la lista blanca
create function public.geoportal_redes_cortes_vigentes(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; f redes.corte_fotos%rowtype;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into f from redes.corte_fotos order by id desc limit 1;
  if f.id is null or f.valvulas_cerradas = 0 then return jsonb_build_object('hay', false, 'zonas', '[]'::jsonb, 'valvulas', '[]'::jsonb); end if;
  return jsonb_build_object(
    'hay', true, 'foto', jsonb_build_object('id', f.id, 'calculada_en', f.creado_en, 'red_huella', f.red_huella),
    'resumen', jsonb_build_object('zonas', f.zonas, 'valvulas_cerradas', f.valvulas_cerradas, 'contratos', f.contratos_cerrados + f.contratos_afectados),
    'leyenda', jsonb_build_array(jsonb_build_object('clave', 'afectado', 'texto', 'Sin agua'), jsonb_build_object('clave', 'cerrado', 'texto', 'Tubería cerrada'),
                                 jsonb_build_object('clave', 'valvula', 'texto', 'Válvula cerrada')),
    'zonas', coalesce((
      select jsonb_agg(jsonb_build_object('zona', z.zona, 'lat', z.lat, 'lon', z.lon, 'caja', to_jsonb(z.caja),
               'contratos', z.contratos_cerrados + z.contratos_afectados, 'tramos', z.tramos_cerrados + z.tramos_afectados,
               'desde', (select min(m.hecho_en) from redes.corte_foto_valvulas fv join redes.valvula_maniobras m on m.id = fv.cierre_id where fv.foto_id = f.id and fv.zona = z.zona),
               'regreso_estimado', (select max(redes.f_cierre_regreso(fv.cierre_id)) from redes.corte_foto_valvulas fv where fv.foto_id = f.id and fv.zona = z.zona),
               'por', (select coalesce(jsonb_agg(distinct jsonb_build_object('registro', coalesce(d.codigo, i.codigo),
                                 'que', case when d.id is not null then coalesce((select t.nombre from redes.tipos_dano t where t.codigo = d.tipo_codigo), 'daño')
                                             when i.id is not null then case when i.nace_de = 'programada' then 'trabajo programado' else 'reparación' end
                                             else 'maniobra del supervisor' end)), '[]'::jsonb)
                         from redes.corte_foto_valvulas fv join redes.valvula_maniobras m on m.id = fv.cierre_id
                         left join redes.danos d on d.id = m.dano_id left join redes.intervenciones i on i.id = m.intervencion_id
                        where fv.foto_id = f.id and fv.zona = z.zona)) order by z.contratos_cerrados + z.contratos_afectados desc, z.zona)
        from redes.corte_foto_zonas z where z.foto_id = f.id), '[]'::jsonb),
    'valvulas', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', v.codigo, 'nombre', coalesce(v.codigo_anterior, v.codigo), 'zona', fv.zona, 'en_red', fv.en_red,
               'lat', round(ST_Y(ST_PointOnSurface(v.geom))::numeric, 6), 'lon', round(ST_X(ST_PointOnSurface(v.geom))::numeric, 6),
               'desde', m.hecho_en, 'quien', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = m.autor), 'Funcionario de EMDUPAR'),
               'registro', coalesce(d.codigo, i.codigo), 'regreso_estimado', redes.f_cierre_regreso(m.id)) order by m.hecho_en)
        from redes.corte_foto_valvulas fv join redes.valvula_maniobras m on m.id = fv.cierre_id join redes.activo_vigente_mat v on v.activo_id = fv.valvula_id
        left join redes.danos d on d.id = m.dano_id left join redes.intervenciones i on i.id = m.intervencion_id
       where fv.foto_id = f.id), '[]'::jsonb));
end $$;

create function public.geoportal_redes_cortes_recalcular(p_solicitante text, p_motivo text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'recalculan los cortes vigentes'); v_foto bigint; f redes.corte_fotos%rowtype;
begin
  if length(btrim(coalesce(p_motivo, ''))) < 10 then perform tecnica.f_error('Escriba el motivo (al menos 10 letras)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.cortes_vigentes'));
  v_foto := redes.f_cortes_foto(null, v_email, btrim(p_motivo));
  select * into f from redes.corte_fotos where id = v_foto;
  return jsonb_build_object('foto', v_foto, 'zonas', f.zonas, 'valvulas_cerradas', f.valvulas_cerradas, 'contratos', f.contratos_cerrados + f.contratos_afectados, 'ms', f.ms);
end $$;

-- la tesela del modo «Afectaciones»: capas «corte_tramos» (papel: cerrado | afectado, zona) y «corte_valvulas» (código, zona). Todos los perfiles del geovisor.
create function public.geoportal_redes_geovisor_mvt_cortes(p_solicitante text, p_z integer, p_x integer, p_y integer)
returns text
language plpgsql stable security definer set search_path = public, redes, extensions, pg_temp as $$
declare a record; v_env geometry; v_env4 geometry; v_foto bigint; v1 bytea; v2 bytea;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  select max(id) into v_foto from redes.corte_fotos;
  if v_foto is null or p_z < 10 then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'corte_tramos', 4096, 'geom') into v1 from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, ft.papel, ft.zona, m.codigo
      from redes.activo_vigente_mat m join redes.corte_foto_tramos ft on ft.foto_id = v_foto and ft.activo_id = m.activo_id
     where m.geom && v_env4) t where t.geom is not null;
  select ST_AsMVT(t, 'corte_valvulas', 4096, 'geom') into v2 from (
    select ST_AsMVTGeom(ST_Transform(ST_PointOnSurface(m.geom), 3857), v_env, 4096, 64, true) as geom, m.codigo, fv.zona
      from redes.activo_vigente_mat m join redes.corte_foto_valvulas fv on fv.foto_id = v_foto and fv.valvula_id = m.activo_id
     where m.geom && v_env4) t where t.geom is not null;
  return replace(encode(coalesce(v1, ''::bytea) || coalesce(v2, ''::bytea), 'base64'), E'\n', '');
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1) · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las funciones internas nuevas y la reemplazada: nadie de la API. Las 3 RPC nuevas: solo service_role (la Edge geoportal-redes).
-- La tabla nueva: nadie de la API (10_esquema.sql): la leen y escriben solo las funciones SECURITY DEFINER.
-- =====================================================================
revoke all on function redes.f_sim_grafo(), redes.f_sim_llenar_agua(), redes.f_sim_escenario(bigint[], bigint, boolean, bigint[], geometry, integer),
                       redes.f_simular_cierre(bigint), redes.f_sim_tramo_cercano(numeric, numeric), redes.f_sim_autorizar(text),
                       redes.f_cierres_vigentes(), redes.f_cierre_regreso(bigint), redes.f_cortes_foto(bigint, text, text),
                       redes.f_cortes_para_avisos(timestamptz, numeric, numeric)
  from public, anon, authenticated, service_role;
revoke all on function tecnica.f_avisos(boolean, boolean, timestamptz) from public, anon, authenticated, service_role;
revoke all on function redes.f_param_entero(text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_simulacion_cierre', 'geoportal_redes_simulacion_guardar', 'geoportal_redes_simulaciones',
                     'geoportal_redes_valvula_maniobra', 'geoportal_redes_corte_regreso', 'geoportal_redes_cortes_vigentes', 'geoportal_redes_cortes_recalcular',
                     'geoportal_redes_geovisor_mvt_cortes') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9b', 'migracion_redes_corte9b_fase1', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.simulaciones_cierre', 'redes.valvula_maniobras', 'redes.corte_fotos', 'redes.corte_foto_zonas', 'redes.corte_foto_tramos', 'redes.corte_foto_valvulas'),
        'nuevas', jsonb_build_array('redes.f_sim_grafo', 'redes.f_sim_llenar_agua', 'redes.f_sim_escenario', 'redes.f_simular_cierre', 'redes.f_sim_tramo_cercano',
                                    'redes.f_sim_autorizar', 'geoportal_redes_simulacion_cierre', 'geoportal_redes_simulacion_guardar', 'geoportal_redes_simulaciones',
                                    'redes.f_cierres_vigentes', 'redes.f_cierre_regreso', 'redes.f_cortes_foto', 'redes.f_cortes_para_avisos',
                                    'geoportal_redes_valvula_maniobra', 'geoportal_redes_corte_regreso', 'geoportal_redes_cortes_vigentes', 'geoportal_redes_cortes_recalcular',
                                    'geoportal_redes_geovisor_mvt_cortes'),
        'reemplazadas', jsonb_build_array('redes.f_param_entero', 'tecnica.f_avisos'),
        'aviso_parametros', jsonb_build_array('valvula_cerrada_naranja_h', 'valvula_cerrada_rojo_h'),
        'parametros', jsonb_build_array('sim_segmento_grande_tramos', 'sim_segmento_grande_contratos', 'sim_no_cierra_max', 'sim_valvulas_lista_max',
                                        'sim_contratos_guardar_max', 'sim_guardadas_max', 'corte_horas_atras_max'),
        'motivo', 'simulación de cierre de válvulas (§17, N-9) y cierre real: maniobras de válvula, foto del corte vigente (tuberías cerradas y afectadas, zonas, contratos), tesela del modo Afectaciones y aviso de válvula cerrada'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1a: simulación de cierre; 1b: cierre real) · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 25, 26 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes9b.*), su red de prueba (ZT9B, en un rincón de la caja de Valledupar, lejos de la red)
-- con sus contratos (números de 15 cifras que empiezan por 99999), su daño y su intervención. Ninguna cifra de la red real se da por supuesta.
-- La red de prueba (x, y en metros):
--     F(tanque) —T1— A —T2— V1(cierra) —T3— B —T4— V2(sin definir) —T5— C —T6— V3(cierra) —T7— D —T14(proyectado)— K
--                                            B —T8— V4(deriva) —T9— E          C —T12— H
--                                            B —T10— V5(ventosa) —T11— G       C —T13— F2(tanque)
-- Mide con el volumen real: simula sobre tramos, una válvula y un tanque de la red de la base donde corre, y FALLA si una simulación pasa de 5 s.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 9b … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes9b.adm@emdupar.gov.co';
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
  a text := 'prueba.redes9b.adm@emdupar.gov.co'; sd text := 'prueba.redes9b.dist@emdupar.gov.co'; op text := 'prueba.redes9b.op@emdupar.gov.co';
  op2 text := 'prueba.redes9b.mant@emdupar.gov.co'; op3 text := 'prueba.redes9b.op3@emdupar.gov.co'; na text := 'prueba.redes9b.nada@emdupar.gov.co';
  v_carga bigint; j jsonb; j2 jsonb; v_p jsonb; v_dan text; v_itv text; v_h1 text; v_h2 text; v_s jsonb; v_n integer; r record;
  v_t0 timestamptz; v_ms numeric; v_max numeric := 0; v_max_m numeric; v_nm integer; v_ms_v numeric; v_ms_t numeric; v_ms_a numeric; v_tiempos text := ''; v_peq integer := 0; v_info text := ''; v_total integer; v_bien integer; v_fallas text;
begin
  -- ---------- personas de prueba ----------
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9B Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT9B Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values
    (op, 'ZT9B Operador daños', 'consulta', true, 'sin_restriccion', 'todos'), (op2, 'ZT9B Operador mantenimiento', 'consulta', true, 'sin_restriccion', 'todos'),
    (op3, 'ZT9B Otro operador daños', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT9B Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values
    (op, 'asignar_formulario', 'danos_fallas', a), (op2, 'asignar_formulario', 'mantenimiento', a), (op3, 'asignar_formulario', 'danos_fallas', a);

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
  perform pg_temp.reg('01.01 la tabla de simulaciones existe, con RLS, sin permisos de la API y de solo agregar (2 disparadores)',
     (select relrowsecurity from pg_class where oid = 'redes.simulaciones_cierre'::regclass)
     and not has_table_privilege('service_role', 'redes.simulaciones_cierre', 'select') and not has_table_privilege('anon', 'redes.simulaciones_cierre', 'select')
     and (select count(*) from pg_trigger t where t.tgrelid = 'redes.simulaciones_cierre'::regclass and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 2);
  perform pg_temp.reg('01.02 los 6 parámetros de la simulación existen, con unidad entera',
     (select count(*) from redes.parametros where clave like 'sim\_%' and estado = 'vigente' and redes.f_param_entero(unidad)) = 6);
  perform pg_temp.reg('01.03 las RPC nuevas: solo service_role; las internas: nadie de la API',
     has_function_privilege('service_role', 'public.geoportal_redes_simulacion_cierre(text,text,numeric,numeric)', 'execute')
     and not has_function_privilege('authenticated', 'public.geoportal_redes_simulacion_guardar(text,text,text)', 'execute')
     and not has_function_privilege('service_role', 'redes.f_simular_cierre(bigint)', 'execute'));

  -- ===================== 02. El caso de la §17 sobre la red de prueba: daño en T4 =====================
  j := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('T4'));
  perform pg_temp.reg('02.01 estrecho (las «sin definir» cierran): cerrar V2 y V1, en orden de cercanía',
     pg_temp.cods(j -> 'estrecho' -> 'valvulas') = pg_temp.ncods('V2,V1') and (j -> 'estrecho' ->> 'valvulas_total')::integer = 2, j -> 'estrecho' ->> 'valvulas');
  perform pg_temp.reg('02.02 estrecho: el segmento son T3, T4, T8, T9, T10 y T11 (la «deriva» y la ventosa no detienen); nada aguas abajo (C se alimenta de F2); 6 contratos',
     (j -> 'estrecho' ->> 'tramos_segmento')::integer = 6 and (j -> 'estrecho' ->> 'tramos_aguas_abajo')::integer = 0 and (j -> 'estrecho' ->> 'contratos')::integer = 6
     and (select string_agg(x, ',' order by x) from jsonb_array_elements_text(j -> 'tramos') x) = (select string_agg(pg_temp.cod(t), ',' order by pg_temp.cod(t)) from unnest(array['T3', 'T4', 'T8', 'T9', 'T10', 'T11']) t),
     j ->> 'estrecho');
  perform pg_temp.reg('02.03 amplio (la «sin definir» no cierra): cerrar V1 y V3; T7 queda aguas abajo sin agua; el tanque F2 queda aislado; 13 contratos',
     pg_temp.cods(j -> 'amplio' -> 'valvulas') = pg_temp.ncods('V1,V3') and (j -> 'amplio' ->> 'tramos_aguas_abajo')::integer = 1
     and (j -> 'amplio' ->> 'contratos')::integer = 13 and pg_temp.cods(j -> 'amplio' -> 'fuentes_aisladas') = pg_temp.cod('F2'), j ->> 'amplio');
  perform pg_temp.reg('02.04 el rango (N-9): entre 6 y 13 contratos, y la «sin definir» que hace la diferencia es V2',
     (j ->> 'contratos_min')::integer = 6 and (j ->> 'contratos_max')::integer = 13 and (j ->> 'rango')::boolean
     and j -> 'dudosas' = jsonb_build_array(pg_temp.cod('V2')) and not (j ->> 'segmento_grande')::boolean);
  perform pg_temp.reg('02.05 la «deriva» (V4) y la ventosa (V5) nunca salen como válvulas a cerrar',
     position(pg_temp.cod('V4') in j::text) = 0 and position(pg_temp.cod('V5') in j::text) = 0);
  perform pg_temp.reg('02.06 «si V2 no cierra»: cerrar V3 en su lugar (13 contratos); «si V1 no cierra»: no hay otra hacia ese lado (8 contratos)',
     (select pg_temp.cods(x -> 'cerrar_en_su_lugar') = pg_temp.cod('V3') and (x ->> 'contratos')::integer = 13 from jsonb_array_elements(j -> 'si_no_cierra') x where x ->> 'valvula' = pg_temp.cod('V2'))
     and (select jsonb_array_length(x -> 'cerrar_en_su_lugar') = 0 and (x ->> 'contratos')::integer = 8 from jsonb_array_elements(j -> 'si_no_cierra') x where x ->> 'valvula' = pg_temp.cod('V1')),
     j ->> 'si_no_cierra');
  perform pg_temp.reg('02.07 alternativas: las 2 que dejan menos contratos sin agua, de menor a mayor (V1: 8; V2: 13)',
     (select string_agg((x ->> 'valvula') || ':' || (x ->> 'contratos'), ',' order by o) from jsonb_array_elements(j -> 'alternativas') with ordinality y(x, o))
       = pg_temp.cod('V1') || ':8,' || pg_temp.cod('V2') || ':13', j ->> 'alternativas');
  perform pg_temp.reg('02.08 la respuesta no trae la lista interna de contratos ni datos de personas; dice que es la red registrada y trae las notas',
     not (j ? '_contratos') and j::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n|tarifa|estrato' and j -> 'red' ->> 'fuente' like 'red registrada%'
     and jsonb_array_length(j -> 'notas') >= 4 and (j ->> 'ms')::numeric >= 0);

  -- ===================== 03. Otros puntos de trabajo =====================
  j := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('V2'));
  perform pg_temp.reg('03.01 trabajo SOBRE la válvula V2: no sirve para aislarse a sí misma; cerrar V1 y V3 (13 contratos)',
     pg_temp.cods(j -> 'estrecho' -> 'valvulas') = pg_temp.ncods('V2,V1,V3') is not true and pg_temp.cods(j -> 'estrecho' -> 'valvulas') in (pg_temp.ncods('V1,V3'), pg_temp.ncods('V3,V1'))
     and (j -> 'estrecho' ->> 'contratos')::integer = 13, j ->> 'estrecho');
  j := public.geoportal_redes_simulacion_cierre(op, null, pg_temp.lat(4), pg_temp.lon(350));
  perform pg_temp.reg('03.02 sin activo, con un punto a 4 m de T4: simula sobre T4 (el tramo en operación más cercano)', j -> 'activo' ->> 'codigo' = pg_temp.cod('T4'));
  perform pg_temp.err('03.03 un punto lejos de todo tramo: «No hay un tramo de acueducto…»',
     format('select public.geoportal_redes_simulacion_cierre(%L, null, %s, %s)', op, pg_temp.lat(5000), pg_temp.lon(5000)), null, 'No hay un tramo de acueducto');
  perform pg_temp.err('03.04 un tramo proyectado (T14) no conduce agua: lo dice',
     format('select public.geoportal_redes_simulacion_cierre(%L, %L)', op, pg_temp.cod('T14')), null, 'no conduce agua');
  perform pg_temp.err('03.05 un activo de alcantarillado: «solo para acueducto»',
     format('select public.geoportal_redes_simulacion_cierre(%L, %L)', op, (select codigo from redes.activo_vigente_mat where sistema = 'alcantarillado' and not retirado order by activo_id limit 1)),
     null, 'solo para acueducto');

  -- ===================== 04. Quién =====================
  perform pg_temp.reg('04.01 el operador de mantenimiento también simula', (public.geoportal_redes_simulacion_cierre(op2, pg_temp.cod('T4')) ->> 'contratos_min')::integer = 6);
  perform pg_temp.err('04.02 alguien sin Técnica no simula (42501)', format('select public.geoportal_redes_simulacion_cierre(%L, %L)', na, pg_temp.cod('T4')), '42501');
  perform pg_temp.err('04.03 sin solicitante: 28000', format('select public.geoportal_redes_simulacion_cierre(%L, %L)', '', pg_temp.cod('T4')), '28000');

  -- ===================== 05. Guardar con el daño o la intervención =====================
  v_p := public.geoportal_redes_preparar_dano(op, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_dan := public.geoportal_redes_crear_dano(op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           'activo', pg_temp.cod('T4'), 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(350),
           't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
           'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
  j := public.geoportal_redes_simulacion_guardar(op, v_dan);
  perform pg_temp.reg('05.01 quien registró el daño guarda la simulación: queda con el daño, su activo, el rango, la huella de la red y los 6 contratos del escenario estrecho',
     (select s.dano_id = (select id from redes.danos where codigo = v_dan) and s.activo_id = pg_temp.id('T4') and s.contratos_min = 6 and s.contratos_max = 13 and s.valvulas = 2
             and s.red_huella = j -> 'red' ->> 'huella' and cardinality(s.contratos) = 6 and s.autor = op and not (s.resultado ? '_contratos')
        from redes.simulaciones_cierre s where s.id = (j ->> 'id')::bigint) and not (j ? '_contratos') and j ->> 'registro' = v_dan);
  perform pg_temp.err('05.02 otro operador de daños no guarda en un daño ajeno (42501)', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', op3, v_dan), '42501', 'Solo quien lo registró');
  perform pg_temp.err('05.03 el operador de mantenimiento no guarda en un daño (no tiene ese formulario)', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', op2, v_dan), '42501');
  j := public.geoportal_redes_simulacion_guardar(sd, v_dan, pg_temp.cod('V2'));
  perform pg_temp.reg('05.04 el supervisor guarda en ese daño otra simulación, sobre otro activo (V2)',
     (select s.activo_id = pg_temp.id('V2') and s.autor = sd from redes.simulaciones_cierre s where s.id = (j ->> 'id')::bigint));
  v_s := public.geoportal_redes_simulaciones(op, v_dan);
  perform pg_temp.reg('05.05 las guardadas del daño: 2, la última primero, con su resultado',
     jsonb_array_length(v_s -> 'simulaciones') = 2 and v_s -> 'simulaciones' -> 0 ->> 'activo' = pg_temp.cod('V2') and v_s -> 'simulaciones' -> 1 -> 'resultado' ? 'estrecho');
  v_p := public.geoportal_redes_preparar_intervencion(sd, 1, 0);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_itv := public.geoportal_redes_crear_intervencion(sd, (v_p ->> 'intervencion_id')::uuid, jsonb_build_object('nace_de', 'programada', 'tipo', 'preventivo', 'sistema', 'acueducto',
         'activo', pg_temp.cod('T4'), 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(350), 'precision_m', 5, 'ubicacion_origen', 'gps', 't_inicio', pg_temp.iso('-50 minutes'), 't_fin', pg_temp.iso('-10 minutes'),
         'descripcion', 'ZT9B cambio de válvula programado', 'materiales', '[]'::jsonb, 'ejecutor', 'emdupar', 'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')),
         'archivos', jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'despues', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
  j := public.geoportal_redes_simulacion_guardar(sd, v_itv);
  perform pg_temp.reg('05.06 con una intervención (corte programado): queda con la intervención y su tramo',
     (select s.intervencion_id = (select id from redes.intervenciones where codigo = v_itv) and s.dano_id is null and s.activo_id = pg_temp.id('T4')
        from redes.simulaciones_cierre s where s.id = (j ->> 'id')::bigint));
  perform pg_temp.err('05.07 el operador de mantenimiento no guarda en una intervención ajena (42501)', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', op2, v_itv), '42501');
  perform pg_temp.err('05.08 un código que no es de daño ni de intervención', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', sd, 'RED-000001'), null, 'Escriba el código');
  perform pg_temp.err('05.09 un daño que no existe: P0002', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', sd, 'DAN-999999'), 'P0002');
  update redes.parametros set valor = 2 where clave = 'sim_guardadas_max';
  perform pg_temp.err('05.10 con el tope de guardadas (2), una tercera en el mismo daño se niega', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', sd, v_dan), null, 'el máximo');
  update redes.parametros set valor = 20 where clave = 'sim_guardadas_max';
  perform pg_temp.err('05.11 solo agregar: no se cambia una simulación guardada', 'update redes.simulaciones_cierre set valvulas = 0 where id = (select min(id) from redes.simulaciones_cierre)');
  perform pg_temp.err('05.12 solo agregar: no se borra una simulación guardada', 'delete from redes.simulaciones_cierre where id = (select min(id) from redes.simulaciones_cierre)');

  -- ===================== 08. Fase 1b: el cierre real sobre la red de prueba =====================
  -- (antes de la sección 06, que deja V1 fuera de servicio). El daño v_dan y la intervención v_itv son sobre T4.
  j := public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V1'), 'cerrar', v_dan, null, null, pg_temp.iso('3 hours'));
  perform pg_temp.reg('08.01 el operador de daños cierra V1 con su daño (y la hora estimada de regreso): queda cerrada, con la foto del corte',
     j ->> 'estado' = 'cerrada' and (j -> 'vigente' ->> 'valvulas_cerradas')::integer = 1
     and (select m.dano_id = (select id from redes.danos where codigo = v_dan) and m.autor = op and m.regreso_estimado is not null
            from redes.valvula_maniobras m where m.id = (j ->> 'maniobra')::bigint), j::text);
  perform pg_temp.err('08.02 cerrar otra vez una válvula cerrada: «ya está cerrada»', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, %L)', op, pg_temp.cod('V1'), 'cerrar', v_dan), null, 'ya está cerrada');
  j := public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V2'), 'cerrar', v_dan);
  perform pg_temp.reg('08.03 con V1 y V2 cerradas: 1 zona; T3, T4, T8, T9, T10 y T11 son «tubería cerrada» (el sector del daño); nada afectado; 6 contratos',
     (pg_temp.foto()).zonas = 1 and (pg_temp.foto()).tramos_cerrados = 6 and (pg_temp.foto()).tramos_afectados = 0 and (pg_temp.foto()).contratos_cerrados = 6
     and (select string_agg(a.codigo, ',' order by a.codigo) from redes.corte_foto_tramos ft join redes.activos a on a.id = ft.activo_id where ft.foto_id = (pg_temp.foto()).id and ft.papel = 'cerrado')
         = (select string_agg(pg_temp.cod(t), ',' order by pg_temp.cod(t)) from unnest(array['T3', 'T4', 'T8', 'T9', 'T10', 'T11']) t), row_to_json(pg_temp.foto())::text);
  j := public.geoportal_redes_valvula_maniobra(sd, pg_temp.cod('V3'), 'cerrar', v_itv, null, null, pg_temp.iso('5 hours'));
  perform pg_temp.reg('08.04 el supervisor cierra V3 con la intervención: T7 queda «sin agua» (afectado, 2 contratos) en una segunda zona',
     (pg_temp.foto()).zonas = 2 and (pg_temp.foto()).tramos_afectados = 1 and (pg_temp.foto()).contratos_afectados = 2 and (pg_temp.foto()).tramos_cerrados = 6
     and (select ft.papel = 'afectado' from redes.corte_foto_tramos ft where ft.foto_id = (pg_temp.foto()).id and ft.activo_id = pg_temp.id('T7')), row_to_json(pg_temp.foto())::text);
  perform pg_temp.err('08.05b quien no tiene el geovisor técnico no ve los cortes vigentes (42501)', format('select public.geoportal_redes_cortes_vigentes(%L)', op), '42501');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT9B prueba: el operador con el geovisor');
  v_s := public.geoportal_redes_cortes_vigentes(op);
  perform pg_temp.reg('08.05 lo que ve el geovisor: 2 zonas (la de 6 contratos primero, por el daño; la otra por «trabajo programado», con su regreso estimado), 3 válvulas con quién y desde cuándo, leyenda sencilla',
     (v_s ->> 'hay')::boolean and (v_s -> 'resumen' ->> 'zonas')::integer = 2 and (v_s -> 'resumen' ->> 'contratos')::integer = 8
     and (v_s -> 'zonas' -> 0 ->> 'contratos')::integer = 6 and v_s -> 'zonas' -> 0 -> 'por' -> 0 ->> 'registro' = v_dan
     and v_s -> 'zonas' -> 1 -> 'por' -> 0 ->> 'que' = 'trabajo programado' and v_s -> 'zonas' -> 1 ->> 'regreso_estimado' is not null
     and jsonb_array_length(v_s -> 'valvulas') = 3 and (select bool_and(x ->> 'quien' like 'ZT9B%' and x ->> 'desde' is not null) from jsonb_array_elements(v_s -> 'valvulas') x)
     and (select string_agg(x ->> 'texto', ',' order by o) from jsonb_array_elements(v_s -> 'leyenda') with ordinality y(x, o)) = 'Sin agua,Tubería cerrada,Válvula cerrada'
     and v_s::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n|@emdupar', left(v_s::text, 600));
  perform pg_temp.reg('08.06 la tesela del modo «Afectaciones» trae la zona (z 16 en T4) y nada lejos de ella',
     length(public.geoportal_redes_geovisor_mvt_cortes(op, 16, pg_temp.tx(pg_temp.pt(350, 0), 16), pg_temp.ty(pg_temp.pt(350, 0), 16))) > 0
     and public.geoportal_redes_geovisor_mvt_cortes(op, 16, pg_temp.tx(pg_temp.pt(5000, 5000), 16), pg_temp.ty(pg_temp.pt(5000, 5000), 16)) = '');
  perform pg_temp.err('08.07 el operador de mantenimiento no cierra con un daño (no tiene ese formulario)', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, %L)', op2, pg_temp.cod('V4'), 'cerrar', v_dan), '42501');
  perform pg_temp.err('08.08 sin daño ni intervención, el operador no cierra (solo el supervisor)',
     format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, null, %L)', op, pg_temp.cod('V4'), 'cerrar', 'ZT9B maniobra de operación'), '42501');
  perform pg_temp.err('08.09 sin daño ni intervención, el supervisor debe escribir el motivo', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L)', sd, pg_temp.cod('V4'), 'cerrar'), null, 'motivo');
  perform pg_temp.err('08.10 abrir una válvula que no está cerrada', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L)', op, pg_temp.cod('V4'), 'abrir'), null, 'no está cerrada');
  perform pg_temp.err('08.11 una maniobra en el futuro se niega', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, %L, null, %L)', op, pg_temp.cod('V4'), 'cerrar', v_dan, pg_temp.iso('2 hours')), null, 'futura');
  perform pg_temp.err('08.12 una maniobra de hace más de 48 h se niega', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, %L, null, %L)', op, pg_temp.cod('V4'), 'cerrar', v_dan, pg_temp.iso('-50 hours')), null, 'más de');
  perform pg_temp.err('08.13 abrir antes de la hora en que se cerró se niega', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, null, null, %L)', op, pg_temp.cod('V1'), 'abrir', pg_temp.iso('-2 hours')), null, 'antes de la hora');
  perform pg_temp.err('08.14 la hora de regreso la ajusta quien cerró o el supervisor: otro operador no (42501)',
     format('select public.geoportal_redes_corte_regreso(%L, %L, %L)', op3, pg_temp.cod('V1'), pg_temp.iso('6 hours')), '42501');
  j := public.geoportal_redes_corte_regreso(sd, pg_temp.cod('V1'), pg_temp.iso('8 hours'), 'ZT9B la cuadrilla pidió más tiempo');
  perform pg_temp.reg('08.15 el supervisor ajusta la hora de regreso: vale la última, la anterior queda guardada',
     (select redes.f_cierre_regreso(c.cierre_id) = (j ->> 'regreso_estimado')::timestamptz from redes.f_cierres_vigentes() c where c.valvula_id = pg_temp.id('V1'))
     and (select count(*) from redes.valvula_maniobras m where m.valvula_id = pg_temp.id('V1') and m.regreso_estimado is not null) = 2);
  perform pg_temp.reg('08.16 Avisos (distribución): a las 7 h, «3 válvulas cerradas hace más de 6 h» en naranja; a las 13 h, en rojo',
     (select (av ->> 'n')::integer >= 3 and av ->> 'titulo' like '%válvulas cerradas hace más de 6 h' from jsonb_array_elements(tecnica.f_avisos(false, true, clock_timestamp() + interval '7 hours')) av
       where av ->> 'clave' = 'valvulas_cerradas_naranja')
     and exists (select 1 from jsonb_array_elements(tecnica.f_avisos(false, true, clock_timestamp() + interval '13 hours')) av where av ->> 'clave' = 'valvulas_cerradas_rojo')
     and not exists (select 1 from jsonb_array_elements(tecnica.f_avisos(false, true, clock_timestamp() + interval '1 hour')) av where av ->> 'clave' like 'valvulas_cerradas%'));
  j := public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V2'), 'abrir');
  perform pg_temp.reg('08.17 abrir V2 (con el mismo daño): el sector del daño vuelve a tener agua por C; solo T7 sigue sin agua (1 zona, afectado)',
     j ->> 'estado' = 'abierta' and (pg_temp.foto()).zonas = 1 and (pg_temp.foto()).tramos_cerrados = 0 and (pg_temp.foto()).tramos_afectados = 1
     and (select m.dano_id = (select id from redes.danos where codigo = v_dan) from redes.valvula_maniobras m where m.id = (j ->> 'maniobra')::bigint), row_to_json(pg_temp.foto())::text);
  perform pg_temp.err('08.18 solo agregar: no se cambia una maniobra', 'update redes.valvula_maniobras set motivo = ''ZT9B cambio indebido'' where id = (select min(id) from redes.valvula_maniobras)');
  perform pg_temp.err('08.19 solo agregar: no se borra una foto', 'delete from redes.corte_foto_tramos where foto_id = (select min(foto_id) from redes.corte_foto_tramos)');
  perform pg_temp.err('08.20 recalcular los cortes es del supervisor', format('select public.geoportal_redes_cortes_recalcular(%L, %L)', op, 'ZT9B la red cambió'), '42501');
  perform pg_temp.reg('08.21 el supervisor recalcula (la red cambió): foto nueva, mismo resultado',
     (public.geoportal_redes_cortes_recalcular(sd, 'ZT9B la red cambió') ->> 'zonas')::integer = 1 and (pg_temp.foto()).maniobra_id is null);
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V1'), 'abrir');
  perform public.geoportal_redes_valvula_maniobra(sd, pg_temp.cod('V3'), 'abrir');
  perform pg_temp.reg('08.22 con todo abierto: el geovisor no muestra nada (ni franja) y no hay aviso',
     not (public.geoportal_redes_cortes_vigentes(op) ->> 'hay')::boolean and (pg_temp.foto()).valvulas_cerradas = 0
     and public.geoportal_redes_geovisor_mvt_cortes(op, 16, pg_temp.tx(pg_temp.pt(350, 0), 16), pg_temp.ty(pg_temp.pt(350, 0), 16)) = ''
     and not exists (select 1 from jsonb_array_elements(tecnica.f_avisos(false, true, clock_timestamp() + interval '13 hours')) av where av ->> 'clave' like 'valvulas_cerradas%'));

  -- ===================== 06. Lo que cambia la ficha cambia la simulación =====================
  v_h1 := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('T4')) -> 'red' ->> 'huella';
  v_h2 := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('T4')) -> 'red' ->> 'huella';
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (pg_temp.id('V2'), 'por_verificar', 'ZT9B prueba: hay que verificar en campo si opera', a);
  j := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('T4'));
  perform pg_temp.reg('06.01 la huella de la red no cambia entre dos simulaciones; una válvula «por verificar» sale marcada (y cambia la huella)',
     v_h1 = v_h2 and j -> 'red' ->> 'huella' <> v_h1
     and (select (x ->> 'por_verificar')::boolean from jsonb_array_elements(j -> 'estrecho' -> 'valvulas') x where x ->> 'codigo' = pg_temp.cod('V2')));
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, estado_codigo, atributos, huella, autor)
  select activo_id, 2, pg_temp.pt(200, 0), 'ZT9B V1', 'cierre', 'cierra', 'fuera_servicio', '{}'::jsonb, md5('zt9b-v1-2'), a from _zt where nombre = 'V1';
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (pg_temp.id('V1'), 2, 'emdupar', 'ZT9B V1 fuera de servicio', a);
  perform redes.f_mat_refrescar_uno(pg_temp.id('V1'));
  j := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('T4'));
  perform pg_temp.reg('06.02 con V1 fuera de servicio, ya no sirve: solo V2 cierra ese lado y el tanque F queda dentro (8 contratos en el estrecho)',
     pg_temp.cods(j -> 'estrecho' -> 'valvulas') = pg_temp.cod('V2') and (j -> 'estrecho' ->> 'contratos')::integer = 8
     and pg_temp.cods(j -> 'estrecho' -> 'fuentes_aisladas') = pg_temp.cod('F'), j ->> 'estrecho');

  -- ===================== 07. Tiempos con la red real (la de la base donde corre) =====================
  for r in (select m.activo_id, m.codigo, 'tramo' as que from redes.activo_vigente_mat m
             where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
             order by md5(m.activo_id::text) limit 4)
           union all
           (select tn.activo_id, m.codigo, 'tramo junto a una válvula' from redes.tramo_nodos tn join redes.activo_vigente_mat m on m.activo_id = tn.activo_id and m.version = tn.version
              join redes.nodos n on n.id = tn.nodo_fin join redes.activo_vigente_mat v on v.activo_id = n.activo_id and v.prefijo = 'VAL'
             where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
             order by md5(tn.activo_id::text) limit 2)
           union all
           (select tn.activo_id, m.codigo, 'tramo entre dos válvulas' from redes.tramo_nodos tn join redes.activo_vigente_mat m on m.activo_id = tn.activo_id and m.version = tn.version
              join redes.nodos n1 on n1.id = tn.nodo_ini join redes.activo_vigente_mat v1 on v1.activo_id = n1.activo_id and v1.prefijo = 'VAL'
              join redes.nodos n2 on n2.id = tn.nodo_fin join redes.activo_vigente_mat v2 on v2.activo_id = n2.activo_id and v2.prefijo = 'VAL'
             where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
             order by md5(tn.activo_id::text) limit 2)
           union all
           (select m.activo_id, m.codigo, 'válvula' from redes.activo_vigente_mat m join redes.nodos n on n.activo_id = m.activo_id
             where m.prefijo = 'VAL' and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
               and exists (select 1 from redes.tramo_nodos t where t.nodo_ini = n.id or t.nodo_fin = n.id)
             order by md5(m.activo_id::text) limit 1)
           union all
           (select m.activo_id, m.codigo, 'tanque' from redes.activo_vigente_mat m join redes.nodos n on n.activo_id = m.activo_id
             where m.prefijo = 'TAN' and m.cuenta_vigente and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
               and exists (select 1 from redes.tramo_nodos t where t.nodo_ini = n.id or t.nodo_fin = n.id)
             order by md5(m.activo_id::text) limit 1) loop
    v_t0 := clock_timestamp();
    begin
      j := public.geoportal_redes_simulacion_cierre(a, r.codigo);
      v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
      v_tiempos := v_tiempos || format(' · %s %s %s ms (%s–%s contratos, %s válvulas%s)', r.que, r.codigo, v_ms, j ->> 'contratos_min', j ->> 'contratos_max',
                                       j -> 'estrecho' ->> 'valvulas_total', case when (j ->> 'segmento_grande')::boolean then ', segmento grande' else '' end);
      if not (j ->> 'segmento_grande')::boolean then v_peq := v_peq + 1; end if;
    exception when others then
      v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
      v_tiempos := v_tiempos || format(' · %s %s %s ms (%s)', r.que, r.codigo, v_ms, sqlerrm);
    end;
    v_max := greatest(v_max, v_ms); v_n := coalesce(v_n, 0) + 1;
  end loop;
  -- cierre real con la red real: el supervisor cierra 12 válvulas reales (las dos de cada uno de 6 tramos entre dos válvulas), una por una; cada maniobra saca la foto
  for r in (select v.codigo from (select distinct v1.codigo, v1.activo_id from redes.tramo_nodos tn join redes.activo_vigente_mat m on m.activo_id = tn.activo_id and m.version = tn.version
              join redes.nodos n1 on n1.id in (tn.nodo_ini, tn.nodo_fin) join redes.activo_vigente_mat v1 on v1.activo_id = n1.activo_id and v1.prefijo = 'VAL' and not v1.retirado
             where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
               and tn.activo_id in (select tn2.activo_id from redes.tramo_nodos tn2
                                      join redes.nodos a1 on a1.id = tn2.nodo_ini join redes.activo_vigente_mat b1 on b1.activo_id = a1.activo_id and b1.prefijo = 'VAL'
                                      join redes.nodos a2 on a2.id = tn2.nodo_fin join redes.activo_vigente_mat b2 on b2.activo_id = a2.activo_id and b2.prefijo = 'VAL'
                                     order by md5(tn2.activo_id::text) limit 6)) v order by md5(v.activo_id::text) limit 12) loop
    v_t0 := clock_timestamp();
    perform public.geoportal_redes_valvula_maniobra(a, r.codigo, 'cerrar', null, 'ZT9B prueba de tiempos con la red real');
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000); v_max_m := greatest(coalesce(v_max_m, 0), v_ms); v_nm := coalesce(v_nm, 0) + 1;
  end loop;
  v_t0 := clock_timestamp(); v_s := public.geoportal_redes_cortes_vigentes(a); v_ms_v := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp();
  perform public.geoportal_redes_geovisor_mvt_cortes(a, 15, pg_temp.tx(ST_SetSRID(ST_MakePoint((v_s -> 'zonas' -> 0 ->> 'lon')::float8, (v_s -> 'zonas' -> 0 ->> 'lat')::float8), 4326), 15),
                                                     pg_temp.ty(ST_SetSRID(ST_MakePoint((v_s -> 'zonas' -> 0 ->> 'lon')::float8, (v_s -> 'zonas' -> 0 ->> 'lat')::float8), 4326), 15))
   where (v_s ->> 'hay')::boolean and jsonb_array_length(v_s -> 'zonas') > 0;
  v_ms_t := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform tecnica.f_avisos(true, true, clock_timestamp() + interval '13 hours'); v_ms_a := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_tiempos := v_tiempos || format(' · CIERRE REAL: %s maniobras, la más lenta %s ms (con la foto; quedan %s zonas, %s contratos) · cortes vigentes %s ms · tesela %s ms · avisos completos %s ms',
                                   v_nm, v_max_m, v_s -> 'resumen' ->> 'zonas', v_s -> 'resumen' ->> 'contratos', v_ms_v, v_ms_t, v_ms_a);
  v_info := format('TIEMPOS de la simulación sobre la red de esta base (%s tramos en operación, %s contratos con tramo): máximo %s ms%s',
                   (select count(*) from redes.activo_vigente_mat where sistema = 'acueducto' and prefijo in ('RED', 'CON') and cuenta_vigente and not retirado),
                   (select count(*) from redes.contrato_tramo), v_max, v_tiempos);
  perform pg_temp.reg('07.01 TIEMPOS: ' || coalesce(v_n, 0) || ' simulaciones sobre la red real (' || v_peq || ' con sector pequeño y «si no cierra»), cada una en menos de 5 s (el tope de la Edge es 30 s)',
     v_n >= 1 and v_max < 5000, v_info);
  perform pg_temp.reg('07.03 TIEMPOS del cierre real con la red real: cada maniobra (con su foto) en menos de 5 s; cortes vigentes, tesela y avisos en menos de 1 s',
     v_nm >= 1 and v_max_m < 5000 and v_ms_v < 1000 and v_ms_t < 1000 and v_ms_a < 1000, v_info);
  perform pg_temp.reg('07.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 9b, Fase 1 (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
