begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1: simulación de cierre, §17) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte9b_simulacion_alertas.md, §17 y N-9 de la bitácora, corte9b/analisis_cierre_valvulas.md (opción C).
-- · Presupone el Corte 10 publicado (huella del conjunto de funciones de redes aad5952c27e13cc3ad45623279ba7085).
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
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1) · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del Corte 10 publicado) con cambios exactos, aplicados una sola vez.
--   · redes.f_param_entero: las unidades «tramos», «contratos», «válvulas» y «simulaciones» son números enteros (parámetros de la simulación).
-- =====================================================================
-- redes.f_param_entero(text)
CREATE OR REPLACE FUNCTION redes.f_param_entero(p_unidad text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select p_unidad in ('fotos', 'documentos', 'materiales', 'activos', 'días', 'horas', 'filas', 'bytes', 'zoom', 'hoja', 'tramos', 'contratos', 'válvulas', 'simulaciones') $function$;
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
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1) · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las funciones internas nuevas y la reemplazada: nadie de la API. Las 3 RPC nuevas: solo service_role (la Edge geoportal-redes).
-- La tabla nueva: nadie de la API (10_esquema.sql): la leen y escriben solo las funciones SECURITY DEFINER.
-- =====================================================================
revoke all on function redes.f_sim_grafo(), redes.f_sim_llenar_agua(), redes.f_sim_escenario(bigint[], bigint, boolean, bigint[], geometry, integer),
                       redes.f_simular_cierre(bigint), redes.f_sim_tramo_cercano(numeric, numeric), redes.f_sim_autorizar(text)
  from public, anon, authenticated, service_role;
revoke all on function redes.f_param_entero(text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_simulacion_cierre', 'geoportal_redes_simulacion_guardar', 'geoportal_redes_simulaciones') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9b', 'migracion_redes_corte9b_fase1', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.simulaciones_cierre'),
        'nuevas', jsonb_build_array('redes.f_sim_grafo', 'redes.f_sim_llenar_agua', 'redes.f_sim_escenario', 'redes.f_simular_cierre', 'redes.f_sim_tramo_cercano',
                                    'redes.f_sim_autorizar', 'geoportal_redes_simulacion_cierre', 'geoportal_redes_simulacion_guardar', 'geoportal_redes_simulaciones'),
        'reemplazadas', jsonb_build_array('redes.f_param_entero'),
        'parametros', jsonb_build_array('sim_segmento_grande_tramos', 'sim_segmento_grande_contratos', 'sim_no_cierra_max', 'sim_valvulas_lista_max',
                                        'sim_contratos_guardar_max', 'sim_guardadas_max'),
        'motivo', 'simulación de cierre de válvulas (§17, N-9): qué válvulas cerrar, tramos y contratos sin agua como rango, si una no cierra y alternativas; guardada con el daño o la intervención'), null);
commit;
