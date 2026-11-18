begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 10 — GUARDIA Y PARÁMETROS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: pedido de David del 17-nov (caso real RED-000077 / VAL-000684).
-- · Presupone el Corte 14 publicado: huella del conjunto de funciones de redes 1a9ef250a74fb01962f463d98834cc4a.
-- · SOLO AGREGA: 4 funciones internas, 1 RPC y 2 parámetros. No reemplaza ninguna función: la simulación de hoy (redes.f_simular_cierre) queda igual,
--   como «Aislamiento total». No toca tecnica.f_avisos, Personal, «Por verificar» ni el geovisor. Sin tablas nuevas. Solo base de datos: la ruta de la Edge
--   y la pantalla son del Code B.
-- =====================================================================
do $$
begin
  if to_regprocedure('redes.f_simular_aguas_arriba(bigint)') is not null then raise exception '«Cierre por aguas arriba» ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '1a9ef250a74fb01962f463d98834cc4a' then
    raise exception 'Las funciones de redes no son las del Corte 14 publicado (huella 1a9ef250a74fb01962f463d98834cc4a): deténgase y avise';
  end if;
  if to_regclass('redes.flujo_modelo') is null or to_regclass('redes.pm_nodos') is null or to_regprocedure('redes.f_simular_cierre(bigint)') is null then
    raise exception 'Faltan tablas o funciones del 9a o del 9b: deténgase y avise';
  end if;
end $$;

insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('sim_aguas_arriba_criterio', 1, '1 cota, 2 modelo', 1, 2,
   'Cierre por aguas arriba (Corte 9b): con qué se decide por dónde entra el agua. 1: la altura del terreno (el agua baja). 2: el flujo del modelo. El otro se muestra como comprobación'),
  ('sim_cota_minima_m', 0.1, 'm', 0, 5,
   'Cierre por aguas arriba (Corte 9b): desnivel mínimo entre los dos extremos de un tramo para decir hacia dónde baja el agua; con menos, el tramo queda sin sentido')
on conflict (clave) do update set estado = 'vigente', valor = excluded.valor, descripcion = excluded.descripcion;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 20 — FUNCIONES. PROPUESTA. Solo agrega (no reemplaza nada: la simulación de hoy queda como «Aislamiento total»).
-- Caso real (David, 17-nov): para aislar RED-000077 el aislamiento total pide cientos de válvulas, y en la operación basta VAL-000684, por donde le ENTRA el agua.
-- Qué hace: desde el extremo por donde entra el agua al tramo, recorre la red CONTRA el sentido del agua y se detiene en las válvulas que operan: esas se cierran.
-- El sentido de cada tramo sale de uno de dos criterios (se calculan los dos y se dice si coinciden):
--   · cota: el agua baja del nodo más alto al más bajo (cota del terreno, redes.pm_nodos; con menos desnivel que «sim_cota_minima_m», el tramo queda sin sentido);
--   · modelo: el sentido del flujo de redes.flujo_modelo (hora de mayor consumo; la de menor, como comprobación).
-- El principal lo dice el parámetro «sim_aguas_arriba_criterio» (1 cota, 2 modelo). Un tramo SIN sentido se toma como posible entrada (se recorre igual).
-- Si no se puede (el tramo del trabajo no tiene sentido, no hay válvulas aguas arriba, o se llega a un tanque sin válvula de por medio): cae al aislamiento total y lo dice.
-- Contratos, como rango: el mínimo, lo que queda sin camino desde los tanques con esas válvulas cerradas (más el tramo del trabajo); el máximo, todo lo que recibía
-- el agua a través de esas válvulas según el sentido. Es una aproximación: al cerrar, en una red mallada el agua puede llegar por otro lado.
-- Usa las tablas temporales de redes.f_sim_grafo (_sim_g, _sim_v, _sim_f, _sim_s, _sim_c, _sim_w, _sim_b) y cuatro propias (_sim_d, _sim_u, _sim_q, _sim_q0).
-- =====================================================================

-- ---------- llena _sim_d: el sentido del agua de cada tramo del grafo (va del nodo a al nodo b) según un criterio. Los tramos sin sentido no quedan ----------
create function redes.f_sim_sentidos(p_criterio text) returns integer
language plpgsql volatile security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_n integer; v_min numeric := coalesce(redes.f_param('sim_cota_minima_m'), 0.1); v_c bigint;
begin
  if to_regclass('pg_temp._sim_d') is null then create temp table _sim_d (t bigint primary key, a bigint not null, b bigint not null) on commit drop; end if;
  truncate pg_temp._sim_d;
  if p_criterio = 'cota' then
    v_c := redes.f_ref_vigente('pm_nodos');
    -- (uniones por tabla: con subconsultas por tramo tardaba 6 veces más)
    insert into pg_temp._sim_d (t, a, b)
    with k as materialized (select n.id, p.cota_m from redes.nodos n join redes.pm_nodos p on p.llave = n.llave_modelo where p.carga_id = v_c and n.sistema = 'acueducto'),
         e as materialized (select distinct on (g.t) g.t, g.n, g.m from pg_temp._sim_g g order by g.t, g.n)
    select e.t, case when kn.cota_m > km.cota_m then e.n else e.m end, case when kn.cota_m > km.cota_m then e.m else e.n end
      from e join k kn on kn.id = e.n join k km on km.id = e.m
     where abs(kn.cota_m - km.cota_m) >= v_min;
  elsif p_criterio in ('modelo', 'modelo_menor') then
    v_c := redes.f_ref_vigente('flujo_modelo');
    -- el sentido del modelo va sobre la geometría del tramo (geom_mismo), y el nodo inicial del tramo está en el inicio de su geometría
    insert into pg_temp._sim_d (t, a, b)
    select x.t, case when x.con_la_linea then x.ni else x.nf end, case when x.con_la_linea then x.nf else x.ni end
      from (select tn.activo_id as t, tn.nodo_ini as ni, tn.nodo_fin as nf,
                   case when p_criterio = 'modelo' then f.sentido_mayor else f.sentido_menor end as sentido,
                   ((case when p_criterio = 'modelo' then f.sentido_mayor else f.sentido_menor end) = 'ini_fin') = f.geom_mismo as con_la_linea
              from redes.flujo_modelo f
              join redes.activo_vigente_mat v on v.activo_id = f.activo_id
              join redes.tramo_nodos tn on tn.activo_id = v.activo_id and tn.version = v.version
             where f.carga_id = v_c and f.activo_id = any (array(select distinct g.t from pg_temp._sim_g g))) x
     where x.sentido <> 'sin_flujo';
  else
    perform tecnica.f_error('El criterio es «cota» o «modelo»');
  end if;
  get diagnostics v_n = row_count;
  analyze pg_temp._sim_d;
  return v_n;
end $$;

-- ---------- llena _sim_q: los tramos que reciben agua desde los tanques SIGUIENDO el sentido (los tramos sin sentido, en los dos), con las válvulas de _sim_c cerradas ----------
create function redes.f_sim_llenar_sentido() returns integer
language plpgsql volatile security definer set search_path = redes, pg_temp as $$
declare v_n integer;
begin
  if to_regclass('pg_temp._sim_q') is null then create temp table _sim_q (t bigint primary key) on commit drop; end if;
  truncate pg_temp._sim_q;
  insert into pg_temp._sim_q (t)
  with recursive r(n) as (
    select f.n from pg_temp._sim_f f
    union
    select g.m from r join pg_temp._sim_g g on g.n = r.n
     where not exists (select 1 from pg_temp._sim_c c where c.n = g.n)
       and not exists (select 1 from pg_temp._sim_d d where d.t = g.t and d.a <> g.n))      -- el tramo sale de este nodo, o no tiene sentido
  select distinct g.t from r join pg_temp._sim_g g on g.n = r.n
   where not exists (select 1 from pg_temp._sim_c c where c.n = r.n)
     and not exists (select 1 from pg_temp._sim_d d where d.t = g.t and d.a <> g.n);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ---------- un criterio: las válvulas por donde entra el agua, lo que queda sin agua (rango) y por qué no se puede, si no se puede ----------
-- Supone _sim_g, _sim_v, _sim_f y _sim_b (con agua sin cerrar nada) ya armadas. p_tramo: el tramo del trabajo (nulo si es un nodo); p_nodos: sus nodos.
-- p_pasan: nodos que no detienen aunque sean válvulas (la válvula que se interviene). Deja en _sim_c las válvulas a cerrar.
-- p_solo_valvulas: no calcula lo que queda sin agua (para la comprobación con la otra hora del modelo).
create function redes.f_sim_aguas_arriba_criterio(p_criterio text, p_tramo bigint, p_nodos bigint[], p_pasan bigint[], p_ref geometry, p_lista integer, p_solo_valvulas boolean)
returns jsonb
language plpgsql volatile security definer set search_path = redes, public, extensions, pg_temp as $$
declare
  v_con integer; v_ini bigint[]; v_entra bigint; v_n_valv integer; v_n_rec integer; v_n_sin integer; v_fuentes jsonb; v_valvulas jsonb; v_cods text[];
  v_min_t integer; v_min_c integer; v_max_t integer; v_max_c integer; v_long numeric; v_no text; v_base bigint[]; v_cerrar bigint[];
begin
  v_con := redes.f_sim_sentidos(p_criterio);
  if to_regclass('pg_temp._sim_u') is null then create temp table _sim_u (n bigint primary key) on commit drop; end if;
  truncate pg_temp._sim_u, pg_temp._sim_c, pg_temp._sim_s;
  if p_tramo is not null then
    select d.a into v_entra from pg_temp._sim_d d where d.t = p_tramo;
    if v_entra is null then
      return jsonb_build_object('criterio', p_criterio, 'se_puede', false, 'motivo', 'sin_sentido',
        'texto', case when p_criterio = 'cota' then 'No se sabe por dónde le entra el agua: los dos extremos del tramo están casi a la misma altura (o falta su cota)'
                      else 'El modelo no tiene flujo para este tramo: no se sabe por dónde le entra el agua' end, 'tramos_con_sentido', v_con);
    end if;
    v_ini := array[v_entra];
  else
    v_ini := p_nodos;
  end if;
  -- contra el sentido: de un nodo se pasa al otro extremo de cada tramo que le TRAE agua (o que no tiene sentido); una válvula que opera detiene
  insert into pg_temp._sim_u (n)
  with recursive r(n) as (
    select x from unnest(v_ini) x
    union
    select g.m from r join pg_temp._sim_g g on g.n = r.n
     where (g.cn is null or g.n = any (p_pasan))
       and g.t is distinct from p_tramo
       and not exists (select 1 from pg_temp._sim_d d where d.t = g.t and d.b <> g.n))      -- el tramo llega a este nodo, o no tiene sentido
  select n from r;
  insert into pg_temp._sim_c (n)
  select v.n from pg_temp._sim_u u join pg_temp._sim_v v on v.n = u.n where v.cuenta in ('cierra', 'sin_definir') and v.n <> all (p_pasan);
  get diagnostics v_n_valv = row_count;
  -- tramos recorridos aguas arriba y cuántos de ellos no tienen sentido (se tomaron como posibles entradas)
  select count(distinct g.t), count(distinct g.t) filter (where not exists (select 1 from pg_temp._sim_d d where d.t = g.t)) into v_n_rec, v_n_sin
    from pg_temp._sim_u u join pg_temp._sim_g g on g.n = u.n join pg_temp._sim_u u2 on u2.n = g.m
   where g.t is distinct from p_tramo and not exists (select 1 from pg_temp._sim_c c where c.n = u.n);
  -- tanques o planta alcanzados sin una válvula de por medio: por aguas arriba no se aísla
  select jsonb_agg(redes.f_activo_corto(f.activo_id) order by f.activo_id) into v_fuentes
    from pg_temp._sim_f f join pg_temp._sim_u u on u.n = f.n where not exists (select 1 from pg_temp._sim_c c where c.n = f.n);
  v_no := case when v_fuentes is not null then 'llega_a_la_fuente' when v_n_valv = 0 then 'sin_valvulas' end;
  if v_no is not null then
    return jsonb_build_object('criterio', p_criterio, 'se_puede', false, 'motivo', v_no,
      'texto', case v_no when 'llega_a_la_fuente' then 'Aguas arriba se llega a un tanque o a la planta sin una válvula de por medio'
                         else 'No hay válvulas que operen aguas arriba de este tramo' end,
      'fuentes', coalesce(v_fuentes, '[]'), 'valvulas_total', v_n_valv, 'tramos_recorridos', v_n_rec, 'tramos_sin_sentido', v_n_sin, 'tramos_con_sentido', v_con);
  end if;
  select coalesce(jsonb_agg(y.j order by y.d, y.codigo), '[]'), array_agg(y.codigo order by y.codigo) into v_valvulas, v_cods
    from (select v.codigo, ST_Distance(v.geom::geography, p_ref::geography) as d,
                 redes.f_activo_corto(v.activo_id) || jsonb_build_object('efecto', v.efecto, 'por_verificar', v.por_verificar,
                   'distancia_m', round(ST_Distance(v.geom::geography, p_ref::geography)::numeric, 0),
                   'lat', round(ST_Y(v.geom)::numeric, 6), 'lon', round(ST_X(v.geom)::numeric, 6), 'nodo', v.n) as j
            from pg_temp._sim_c c join pg_temp._sim_v v on v.n = c.n) y;
  if p_solo_valvulas then
    return jsonb_build_object('criterio', p_criterio, 'se_puede', true, 'valvulas_total', v_n_valv, 'codigos', to_jsonb(v_cods));
  end if;
  -- mínimo: lo que queda sin camino desde los tanques con esas válvulas cerradas (por conectividad), más el tramo del trabajo
  perform redes.f_sim_llenar_agua();
  select array(select b.t from pg_temp._sim_b b where not exists (select 1 from pg_temp._sim_w w where w.t = b.t) union select p_tramo where p_tramo is not null) into v_base;
  select count(*) into v_min_t from unnest(v_base) x;
  select count(distinct ct.contrato) into v_min_c from redes.contrato_tramo ct where ct.activo_id = any (v_base);
  -- máximo: además, lo que recibía el agua a través de esas válvulas según el sentido (sin cerrar nada sí le llegaba; con ellas cerradas, no)
  if to_regclass('pg_temp._sim_q0') is null then create temp table _sim_q0 (t bigint primary key) on commit drop; end if;
  select array_agg(c.n) into v_cerrar from pg_temp._sim_c c;
  truncate pg_temp._sim_q0, pg_temp._sim_c;
  perform redes.f_sim_llenar_sentido();      -- sin cerrar nada
  insert into pg_temp._sim_q0 (t) select t from pg_temp._sim_q;
  insert into pg_temp._sim_c (n) select unnest(v_cerrar);
  perform redes.f_sim_llenar_sentido();      -- con las válvulas cerradas
  select array(select x from unnest(v_base) x union
               select q0.t from pg_temp._sim_q0 q0 where not exists (select 1 from pg_temp._sim_q q where q.t = q0.t)) into v_base;
  select count(*), coalesce(round(sum(m.longitud_m)), 0) into v_max_t, v_long from redes.activo_vigente_mat m where m.activo_id = any (v_base);
  select count(distinct ct.contrato) into v_max_c from redes.contrato_tramo ct where ct.activo_id = any (v_base);
  return jsonb_build_object('criterio', p_criterio, 'se_puede', true,
    'valvulas_total', v_n_valv, 'valvulas', (select coalesce(jsonb_agg(x order by o), '[]') from jsonb_array_elements(v_valvulas) with ordinality y(x, o) where o <= greatest(p_lista, 0)),
    'codigos', to_jsonb(v_cods),
    'entra_por', (select coalesce(redes.f_activo_corto(n.activo_id), '{}'::jsonb) || jsonb_build_object('nodo', n.id, 'nombre', n.nombre_modelo, 'lat', round(ST_Y(n.geom)::numeric, 6), 'lon', round(ST_X(n.geom)::numeric, 6))
                    from redes.nodos n where n.id = v_entra),
    'tramos_recorridos', v_n_rec, 'tramos_sin_sentido', v_n_sin, 'tramos_con_sentido', v_con,
    'tramos_sin_agua_min', v_min_t, 'tramos_sin_agua_max', v_max_t, 'longitud_sin_agua_max_m', v_long,
    'contratos_min', v_min_c, 'contratos_max', v_max_c);
end $$;

-- ---------- la simulación «por aguas arriba» completa ----------
-- p_activo: el tramo o el nodo (válvula, accesorio, hidrante…) del trabajo. Devuelve el resultado (jsonb), sin guardar.
create function redes.f_simular_aguas_arriba(p_activo bigint) returns jsonb
language plpgsql volatile security definer set search_path = redes, public, extensions, pg_temp as $$
declare
  t0 timestamptz := clock_timestamp(); m redes.activo_vigente_mat%rowtype; v_huella text; v_nodos bigint[]; v_tramo bigint; v_pasan bigint[] := '{}'; v_ref geometry;
  v_lista integer := coalesce(redes.f_param('sim_valvulas_lista_max'), 30)::integer;
  v_cual text := case when coalesce(redes.f_param('sim_aguas_arriba_criterio'), 1) = 2 then 'modelo' else 'cota' end; v_otro text;
  c_p jsonb; c_o jsonb; c_m2 jsonb; v_total jsonb; v_coinciden boolean; v_horas boolean;
begin
  v_otro := case v_cual when 'cota' then 'modelo' else 'cota' end;
  select * into m from redes.activo_vigente_mat where activo_id = p_activo;
  if not found then perform tecnica.f_error('Ese activo no existe', 'P0002'); end if;
  if m.sistema <> 'acueducto' then perform tecnica.f_error('La simulación de cierre es solo para acueducto'); end if;
  if m.retirado then perform tecnica.f_error('Ese activo está retirado'); end if;
  v_huella := redes.f_sim_grafo();
  v_ref := case when GeometryType(m.geom) = 'LINESTRING' then ST_LineInterpolatePoint(m.geom, 0.5)
                when GeometryType(m.geom) = 'MULTILINESTRING' and GeometryType(ST_LineMerge(m.geom)) = 'LINESTRING' then ST_LineInterpolatePoint(ST_LineMerge(m.geom), 0.5)
                else ST_PointOnSurface(m.geom) end;
  if m.prefijo in ('RED', 'CON') then
    if not exists (select 1 from pg_temp._sim_g g where g.t = m.activo_id) then
      perform tecnica.f_error(format('El tramo %s no conduce agua según la red (estado «%s»): no hay válvulas que cerrar', m.codigo,
                                     (select s.nombre from redes.estados_activo s where s.codigo = m.estado_codigo)));
    end if;
    select array_agg(distinct g.n) into v_nodos from pg_temp._sim_g g where g.t = m.activo_id;
    v_tramo := m.activo_id;
  else
    select array_agg(distinct g.n) into v_nodos from pg_temp._sim_g g join redes.nodos n on n.id = g.n where n.activo_id = m.activo_id;
    if v_nodos is null then perform tecnica.f_error(format('%s no es un nodo de la red de acueducto en operación: elija el tramo', m.codigo)); end if;
    if m.prefijo = 'VAL' then v_pasan := v_nodos; end if;      -- la válvula que se interviene no sirve para aislarse a sí misma
  end if;
  -- con agua sin cerrar nada, por conectividad (la base de comparación del mínimo)
  perform redes.f_sim_llenar_agua();
  insert into pg_temp._sim_b (t) select t from pg_temp._sim_w;
  -- la comprobación primero y el principal de último (para que _sim_c quede con las válvulas del principal)
  c_o := redes.f_sim_aguas_arriba_criterio(v_otro, v_tramo, v_nodos, v_pasan, v_ref, v_lista, false);
  c_m2 := redes.f_sim_aguas_arriba_criterio('modelo_menor', v_tramo, v_nodos, v_pasan, v_ref, 0, true);
  c_p := redes.f_sim_aguas_arriba_criterio(v_cual, v_tramo, v_nodos, v_pasan, v_ref, v_lista, false);
  v_coinciden := (c_p ->> 'se_puede')::boolean and (c_o ->> 'se_puede')::boolean and c_p -> 'codigos' = c_o -> 'codigos';
  v_horas := case v_cual when 'modelo' then c_p else c_o end -> 'codigos' is not distinct from c_m2 -> 'codigos'
             and (case v_cual when 'modelo' then c_p else c_o end ->> 'se_puede') = (c_m2 ->> 'se_puede');
  -- si el principal no se puede: cae al aislamiento total (la simulación de siempre) y lo dice
  if not (c_p ->> 'se_puede')::boolean then v_total := redes.f_simular_cierre(p_activo) - '_contratos'; end if;
  return jsonb_build_object(
    'activo', redes.f_activo_corto(m.activo_id) || jsonb_build_object('sistema', m.sistema, 'lat', round(ST_Y(v_ref)::numeric, 6), 'lon', round(ST_X(v_ref)::numeric, 6)),
    'metodo', case when (c_p ->> 'se_puede')::boolean then 'aguas_arriba' else 'aislamiento_total' end,
    'criterio', v_cual,
    'aguas_arriba', c_p - 'codigos',
    'comprobacion', (c_o - 'codigos') || jsonb_build_object('coincide', v_coinciden,
        'texto', case when v_coinciden then format('Por %s da las mismas válvulas', case v_otro when 'cota' then 'la altura del terreno' else 'el flujo del modelo' end)
                      when not (c_o ->> 'se_puede')::boolean then format('Por %s no se pudo comprobar', case v_otro when 'cota' then 'la altura del terreno' else 'el flujo del modelo' end)
                      else format('Por %s da otras válvulas: confirme en campo por dónde entra el agua', case v_otro when 'cota' then 'la altura del terreno' else 'el flujo del modelo' end) end),
    'modelo_horas_coinciden', v_horas,
    'cae_a_total', not (c_p ->> 'se_puede')::boolean,
    'aislamiento_total', v_total,
    'contratos_min', case when (c_p ->> 'se_puede')::boolean then c_p -> 'contratos_min' else v_total -> 'contratos_min' end,
    'contratos_max', case when (c_p ->> 'se_puede')::boolean then c_p -> 'contratos_max' else v_total -> 'contratos_max' end,
    'red', jsonb_build_object('huella', v_huella, 'tramos', (select count(distinct t) from pg_temp._sim_g), 'valvulas', (select count(*) from pg_temp._sim_v)),
    'notas', jsonb_build_array(
      case v_cual when 'cota' then 'Por dónde entra el agua: según la altura del terreno (el agua baja). No es una medición.'
                  else 'Por dónde entra el agua: según el flujo del modelo (Plan Maestro 2014). Modelo, no medido.' end,
      'Al cerrar, el agua puede llegar por otro lado si la red está mallada: confirme en campo que el tramo quedó sin agua.',
      'Contratos: el número menor, si el agua llega por otro lado a los demás tramos; el mayor, si no. Por el tramo más cercano (hasta 30 m): es una aproximación.')
      || case when (c_p ->> 'se_puede')::boolean and (c_p ->> 'tramos_sin_sentido')::integer > 0
              then jsonb_build_array(format('%s tramos del recorrido no tienen sentido conocido: se tomaron como posibles entradas.', c_p ->> 'tramos_sin_sentido')) else '[]' end
      || case when not (c_p ->> 'se_puede')::boolean then jsonb_build_array(format('%s: se muestra el aislamiento total.', c_p ->> 'texto')) else '[]' end,
    'ms', round(extract(epoch from clock_timestamp() - t0) * 1000));
end $$;
comment on function redes.f_simular_aguas_arriba(bigint) is 'Corte 9b («Cierre por aguas arriba»): las válvulas por donde ENTRA el agua a un tramo o nodo de acueducto, según la cota o el flujo del modelo, con la otra como comprobación. Si no se puede, cae al aislamiento total (redes.f_simular_cierre). Sin guardar.';
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 26 — RPC (la llamará la Edge geoportal-redes; la ruta y la pantalla son del Code B).
--   · geoportal_redes_simulacion_aguas_arriba: «¿Qué válvulas cierro?» por donde ENTRA el agua, desde un tramo o nodo (o el tramo más cercano a un punto).
-- Quién: los mismos de la simulación de cierre (quien captura daños y fallas o intervenciones, el supervisor y el administrador). No guarda nada.
-- Volátil: arma tablas temporales de la transacción (la Edge llama por POST).
-- =====================================================================
create function public.geoportal_redes_simulacion_aguas_arriba(p_solicitante text, p_activo text default null, p_lat numeric default null, p_lon numeric default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_sim_autorizar(p_solicitante); v_id bigint;
begin
  if nullif(btrim(coalesce(p_activo, '')), '') is not null then v_id := redes.f_buscar_activo(p_activo);
  else v_id := redes.f_sim_tramo_cercano(p_lat, p_lon);
  end if;
  return redes.f_simular_aguas_arriba(v_id);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 40 — PERMISOS: revoke all antes de dar permisos. Las 4 internas: nadie de la API. La RPC: solo service_role.
-- =====================================================================
revoke all on function redes.f_sim_sentidos(text), redes.f_sim_llenar_sentido(), redes.f_sim_aguas_arriba_criterio(text, bigint, bigint[], bigint[], geometry, integer, boolean),
                       redes.f_simular_aguas_arriba(bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.geoportal_redes_simulacion_aguas_arriba(text, text, numeric, numeric) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_simulacion_aguas_arriba(text, text, numeric, numeric) to service_role;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_9b_aguasarriba', 'migracion_redes_9b_aguas_arriba', null, jsonb_build_object(
        'nuevas', jsonb_build_array('redes.f_sim_sentidos', 'redes.f_sim_llenar_sentido', 'redes.f_sim_aguas_arriba_criterio', 'redes.f_simular_aguas_arriba', 'geoportal_redes_simulacion_aguas_arriba'),
        'parametros', jsonb_build_array('sim_aguas_arriba_criterio', 'sim_cota_minima_m'),
        'motivo', 'simulación de cierre por aguas arriba: las válvulas por donde entra el agua al tramo (por cota o por el flujo del modelo); la de siempre queda como aislamiento total'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes9a.*), la red de prueba ZT9A (en un rincón de la caja), sus contratos (99999…),
-- las cotas de sus nodos (en la carga vigente del Plan, o en una propia si no hay) y el flujo de modelo de sus tramos (igual).
-- Al final mide con la red real de la base y dice, como dato, qué da RED-000077 (el caso de David) si existe. FALLA si una simulación pasa de 5 s.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 9b, cierre por aguas arriba … RESULTADO: N de N pruebas correctas — SIN FALLAS
-- =====================================================================
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
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes9a.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZT9A ' || p_nombre, p_clase, p_efecto,
          case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end, case when p_prefijo = 'RED' then 110 end,
          p_estado, '{}'::jsonb, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT9A activo de prueba', q);
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
  values ('acueducto', 'ZT9A-' || p_nombre, 'ZT9A' || p_nombre, case when v_act is null then 'por_clasificar' else 'activo' end, pg_temp.pt(x, y), v_act, 0, p_carga)
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
create function pg_temp.vals(p jsonb) returns text language sql as $$ select coalesce(string_agg(x ->> 'codigo', ',' order by x ->> 'codigo'), '') from jsonb_array_elements(p) x $$;
create function pg_temp.cods(p text) returns text language sql as $$
  select coalesce(string_agg(pg_temp.cod(btrim(x)), ',' order by pg_temp.cod(btrim(x))), '') from unnest(string_to_array(p, ',')) x $$;

do $prueba$
declare
  a text := 'prueba.redes9a.adm@emdupar.gov.co'; op text := 'prueba.redes9a.op@emdupar.gov.co'; na text := 'prueba.redes9a.nada@emdupar.gov.co';
  v_carga bigint; v_cpm bigint; v_cfl bigint; j jsonb; j2 jsonb; v_md5 text; v_real bigint; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric := 0; v_t0 timestamptz;
  v_info text := ''; v_caso text := 'RED-000077 no está en esta base'; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9A Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT9A Operador daños', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT9A Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);
  v_md5 := md5(pg_get_functiondef('redes.f_simular_cierre(bigint)'::regprocedure));

  -- ---------- la red de prueba: dos tanques (F y F2), una línea que baja de F a D, un ramal plano (B–V3) y una malla que cierra por V4 y H ----------
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
  values ('acueducto', md5('zt9a-a') || md5('zt9a-b'), 'shp', 4326, 'ID', 1, 'ZT9A red de prueba', a) returning id into v_carga;
  perform pg_temp.nodo('F', 0, 0, v_carga, 'TAN');
  perform pg_temp.nodo('A', 100, 0, v_carga);
  perform pg_temp.nodo('V1', 200, 0, v_carga, 'VAL', 'cierre', 'sin_definir');
  perform pg_temp.nodo('B', 300, 0, v_carga);
  perform pg_temp.nodo('C', 400, 0, v_carga);
  perform pg_temp.nodo('V2', 500, 0, v_carga, 'VAL', 'cierre', 'sin_definir');
  perform pg_temp.nodo('D', 600, 0, v_carga);
  perform pg_temp.nodo('V3', 300, 100, v_carga, 'VAL', 'cierre', 'sin_definir');
  perform pg_temp.nodo('E', 300, 200, v_carga);
  perform pg_temp.nodo('G', 400, -100, v_carga);
  perform pg_temp.nodo('V4', 700, 0, v_carga, 'VAL', 'cierre', 'sin_definir');
  perform pg_temp.nodo('H', 800, 0, v_carga);
  perform pg_temp.nodo('F2', 900, 0, v_carga, 'TAN');
  perform pg_temp.tramo('T1', 'F', 'A', v_carga, 1);
  perform pg_temp.tramo('T2', 'A', 'V1', v_carga, 1);
  perform pg_temp.tramo('T3', 'V1', 'B', v_carga, 1);
  perform pg_temp.tramo('T4', 'B', 'C', v_carga, 5);
  perform pg_temp.tramo('T5', 'C', 'V2', v_carga, 2);
  perform pg_temp.tramo('T6', 'V2', 'D', v_carga, 3);
  perform pg_temp.tramo('T7', 'B', 'V3', v_carga, 1);
  perform pg_temp.tramo('T8', 'V3', 'E', v_carga, 2);
  perform pg_temp.tramo('T9', 'C', 'G', v_carga, 1);
  perform pg_temp.tramo('T10', 'D', 'V4', v_carga, 1);
  perform pg_temp.tramo('T11', 'V4', 'H', v_carga, 1);
  perform pg_temp.tramo('T12', 'H', 'F2', v_carga, 1);
  -- las cotas (m): baja de F (100) a D (60); B y V3 casi a la misma altura (tramo plano: sin sentido); G más alto que C; por el otro lado baja de F2 (100) a D
  v_cpm := redes.f_ref_vigente('pm_nodos');
  if v_cpm is null then
    insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, autor) values ('pm_nodos', 'zt9a_pm_nodos.csv', md5('zt9a' || clock_timestamp()::text), 13, 'ZT9A cotas de prueba', a) returning id into v_cpm;
  end if;
  insert into redes.pm_nodos (carga_id, llave, nombre, geom, cota_m)
  select v_cpm, 'ZT9A-' || z.nombre, 'ZT9A ' || z.nombre, pg_temp.pt(z.x, z.y), c.cota
    from _zt z join (values ('F', 100), ('A', 90), ('V1', 85), ('B', 80), ('C', 70), ('V2', 65), ('D', 60), ('V3', 80.02), ('E', 75), ('G', 72), ('V4', 62), ('H', 95), ('F2', 100)) c(nombre, cota)
      on c.nombre = z.nombre;
  -- el flujo del modelo de prueba, AL REVÉS de la cota en el tramo del trabajo (como en el caso real): T4 va de C a B. T1, T2, T7, T8, T11 y T12 no están en el modelo.
  -- En la hora de menor consumo T5 cambia de sentido.
  v_cfl := redes.f_ref_vigente('flujo_modelo');
  if v_cfl is null then
    insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, autor) values ('flujo_modelo', 'zt9a_flujo.csv', md5('zt9a-f' || clock_timestamp()::text), 6, 'ZT9A flujo de prueba', a) returning id into v_cfl;
  end if;
  insert into redes.flujo_modelo (carga_id, llave, activo_id, amarre, geom_mismo, q_mayor_lps, v_mayor_mps, sentido_mayor, q_menor_lps, v_menor_mps, sentido_menor)
  select v_cfl, 'ZT9A-' || f.t, pg_temp.id(f.t), 'llave', true, 5, 0.5, f.s1, 3, 0.3, f.s2
    from (values ('T3', 'fin_ini', 'fin_ini'), ('T4', 'fin_ini', 'fin_ini'), ('T5', 'fin_ini', 'ini_fin'), ('T6', 'fin_ini', 'fin_ini'), ('T9', 'ini_fin', 'ini_fin'), ('T10', 'fin_ini', 'fin_ini')) f(t, s1, s2);

  -- ===================== 01. Estructura =====================
  perform pg_temp.reg('01.01 la RPC nueva: solo service_role; las 4 internas: nadie de la API',
     has_function_privilege('service_role', 'public.geoportal_redes_simulacion_aguas_arriba(text,text,numeric,numeric)', 'execute')
     and not has_function_privilege('authenticated', 'public.geoportal_redes_simulacion_aguas_arriba(text,text,numeric,numeric)', 'execute')
     and not has_function_privilege('service_role', 'redes.f_simular_aguas_arriba(bigint)', 'execute') and not has_function_privilege('service_role', 'redes.f_sim_sentidos(text)', 'execute'));
  perform pg_temp.reg('01.02 los 2 parámetros: el criterio vigente es 1 (cota) y el desnivel mínimo, 0,1 m',
     (select valor = 1 and minimo = 1 and maximo = 2 from redes.parametros where clave = 'sim_aguas_arriba_criterio') and (select valor = 0.1 from redes.parametros where clave = 'sim_cota_minima_m'));

  -- ===================== 02. Por cota (el criterio vigente) =====================
  j := public.geoportal_redes_simulacion_aguas_arriba(op, pg_temp.cod('T4'));
  perform pg_temp.reg('02.01 T4 por cota: el agua le entra por B (el extremo alto); se cierran V1 (aguas arriba) y V3 (por el tramo plano, posible entrada): 2 válvulas, no las del otro lado',
     j ->> 'metodo' = 'aguas_arriba' and j ->> 'criterio' = 'cota' and not (j ->> 'cae_a_total')::boolean and (j -> 'aguas_arriba' ->> 'valvulas_total')::integer = 2
     and pg_temp.vals(j -> 'aguas_arriba' -> 'valvulas') = pg_temp.cods('V1,V3') and j -> 'aguas_arriba' -> 'entra_por' ->> 'nombre' = 'ZT9AB', j::text);
  perform pg_temp.reg('02.02 … recorrió 2 tramos aguas arriba; 1 no tiene sentido (plano) y lo dice en las notas',
     (j -> 'aguas_arriba' ->> 'tramos_recorridos')::integer = 2 and (j -> 'aguas_arriba' ->> 'tramos_sin_sentido')::integer = 1 and j ->> 'notas' like '%1 tramos del recorrido no tienen sentido%', j ->> 'notas');
  perform pg_temp.reg('02.03 … contratos como rango: 7 si el agua llega por el otro lado (T4 y lo que queda sin camino, T8) y 14 si no (todo lo que recibía por esas válvulas)',
     (j ->> 'contratos_min')::integer = 7 and (j ->> 'contratos_max')::integer = 14 and (j -> 'aguas_arriba' ->> 'tramos_sin_agua_min')::integer = 2
     and (j -> 'aguas_arriba' ->> 'tramos_sin_agua_max')::integer = 6, (j -> 'aguas_arriba')::text);
  perform pg_temp.reg('02.04 … la comprobación con el modelo da OTRA válvula (V2: el modelo va al revés) y lo dice: «confirme en campo»; y entre las dos horas del modelo tampoco coincide',
     not (j -> 'comprobacion' ->> 'coincide')::boolean and j -> 'comprobacion' ->> 'criterio' = 'modelo' and pg_temp.vals(j -> 'comprobacion' -> 'valvulas') = pg_temp.cods('V2')
     and j -> 'comprobacion' ->> 'texto' like '%confirme en campo%' and (j -> 'comprobacion' ->> 'contratos_min')::integer = 5 and (j -> 'comprobacion' ->> 'contratos_max')::integer = 12
     and not (j ->> 'modelo_horas_coinciden')::boolean, (j -> 'comprobacion')::text);
  perform pg_temp.reg('02.05 … frente al aislamiento total de siempre, que para T4 pide 3 válvulas (V1, V2 y V3)',
     (redes.f_simular_cierre(pg_temp.id('T4')) -> 'estrecho' ->> 'valvulas_total')::integer = 3);
  j := public.geoportal_redes_simulacion_aguas_arriba(op, pg_temp.cod('T6'));
  perform pg_temp.reg('02.06 T6: el agua le entra por una válvula (V2): basta esa; 3 contratos',
     pg_temp.vals(j -> 'aguas_arriba' -> 'valvulas') = pg_temp.cods('V2') and (j ->> 'contratos_min')::integer = 3 and (j ->> 'contratos_max')::integer = 3, j::text);
  perform pg_temp.reg('02.07 … y aquí el modelo dice que entra por D: otra válvula (V4)', pg_temp.vals(j -> 'comprobacion' -> 'valvulas') = pg_temp.cods('V4') and not (j -> 'comprobacion' ->> 'coincide')::boolean, (j -> 'comprobacion')::text);

  -- ===================== 03. Cuando no se puede: cae al aislamiento total y lo dice =====================
  j := public.geoportal_redes_simulacion_aguas_arriba(op, pg_temp.cod('T7'));
  perform pg_temp.reg('03.01 T7 (plano: no se sabe por dónde entra): cae al aislamiento total, trae sus 3 válvulas y lo dice en las notas',
     j ->> 'metodo' = 'aislamiento_total' and (j ->> 'cae_a_total')::boolean and j -> 'aguas_arriba' ->> 'motivo' = 'sin_sentido'
     and (j -> 'aislamiento_total' -> 'estrecho' ->> 'valvulas_total')::integer = 3 and j ->> 'notas' like '%se muestra el aislamiento total%'
     and (j ->> 'contratos_min') = (j -> 'aislamiento_total' ->> 'contratos_min') and j -> 'aislamiento_total' ->> '_contratos' is null, j::text);
  j := public.geoportal_redes_simulacion_aguas_arriba(op, pg_temp.cod('T1'));
  perform pg_temp.reg('03.02 T1 (sale del tanque, sin válvula de por medio): cae al aislamiento total y nombra el tanque',
     (j ->> 'cae_a_total')::boolean and j -> 'aguas_arriba' ->> 'motivo' = 'llega_a_la_fuente' and j -> 'aguas_arriba' -> 'fuentes' -> 0 ->> 'codigo' = pg_temp.cod('F'), j::text);
  j := public.geoportal_redes_simulacion_aguas_arriba(op, pg_temp.cod('V1'));
  perform pg_temp.reg('03.03 intervenir la válvula V1: no sirve para aislarse a sí misma; aguas arriba se llega al tanque → aislamiento total',
     (j ->> 'cae_a_total')::boolean and j -> 'aguas_arriba' ->> 'motivo' = 'llega_a_la_fuente' and j -> 'aislamiento_total' is not null, j::text);
  j := public.geoportal_redes_simulacion_aguas_arriba(op, pg_temp.cod('T9'));
  perform pg_temp.reg('03.04 T9 (el agua le «entra» por G, una punta sin válvulas): no hay válvulas aguas arriba → aislamiento total',
     (j ->> 'cae_a_total')::boolean and j -> 'aguas_arriba' ->> 'motivo' = 'sin_valvulas', (j -> 'aguas_arriba')::text);

  -- ===================== 04. El criterio es un parámetro; el desnivel mínimo también =====================
  update redes.parametros set valor = 2 where clave = 'sim_aguas_arriba_criterio';
  j := public.geoportal_redes_simulacion_aguas_arriba(op, pg_temp.cod('T4'));
  perform pg_temp.reg('04.01 con el criterio en 2 (modelo): la principal es la del modelo (V2) y la comprobación, la de la cota (V1 y V3)',
     j ->> 'criterio' = 'modelo' and pg_temp.vals(j -> 'aguas_arriba' -> 'valvulas') = pg_temp.cods('V2') and pg_temp.vals(j -> 'comprobacion' -> 'valvulas') = pg_temp.cods('V1,V3')
     and j ->> 'notas' like '%flujo del modelo%', j::text);
  j := public.geoportal_redes_simulacion_aguas_arriba(op, pg_temp.cod('T2'));
  perform pg_temp.reg('04.02 … y un tramo que no está en el modelo (T2) cae al aislamiento total: «El modelo no tiene flujo para este tramo»',
     (j ->> 'cae_a_total')::boolean and j -> 'aguas_arriba' ->> 'texto' like 'El modelo no tiene flujo%', (j -> 'aguas_arriba')::text);
  update redes.parametros set valor = 1 where clave = 'sim_aguas_arriba_criterio';
  update redes.parametros set valor = 0.01 where clave = 'sim_cota_minima_m';
  j := public.geoportal_redes_simulacion_aguas_arriba(op, pg_temp.cod('T4'));
  perform pg_temp.reg('04.03 con el desnivel mínimo en 1 cm, el tramo plano (B 80,00 → V3 80,02) ya tiene sentido (sale de V3 hacia B): sigue siendo entrada, sin tramos «sin sentido»',
     pg_temp.vals(j -> 'aguas_arriba' -> 'valvulas') = pg_temp.cods('V1,V3') and (j -> 'aguas_arriba' ->> 'tramos_sin_sentido')::integer = 0, (j -> 'aguas_arriba')::text);
  update redes.parametros set valor = 0.1 where clave = 'sim_cota_minima_m';

  -- ===================== 05. Quién, errores y que no toca nada =====================
  perform pg_temp.err('05.01 alguien sin Técnica no simula (42501)', format('select public.geoportal_redes_simulacion_aguas_arriba(%L, %L)', na, pg_temp.cod('T4')), '42501');
  perform pg_temp.err('05.02 un activo que no existe', format('select public.geoportal_redes_simulacion_aguas_arriba(%L, %L)', op, 'RED-999999'), 'P0002');
  perform pg_temp.err('05.03 sin activo ni punto', format('select public.geoportal_redes_simulacion_aguas_arriba(%L)', op), null, 'Elija el tramo');
  j := public.geoportal_redes_simulacion_aguas_arriba(op, null, pg_temp.lat(0), pg_temp.lon(350));
  perform pg_temp.reg('05.04 por un punto del mapa: toma el tramo más cercano (T4)', j -> 'activo' ->> 'codigo' = pg_temp.cod('T4'), j ->> 'activo');
  perform pg_temp.reg('05.05 la simulación de siempre no cambió (mismo texto) y la respuesta no trae contratos, nombres ni teléfonos',
     md5(pg_get_functiondef('redes.f_simular_cierre(bigint)'::regprocedure)) = v_md5 and j::text !~* '_contratos|suscriptor|tel[eé]fono|direcci[oó]n');
  perform pg_temp.reg('05.06 no guarda nada: ninguna simulación guardada ni fila de auditoría por simular',
     not exists (select 1 from redes.simulaciones_cierre s where s.autor = op) and not exists (select 1 from public.geoportal_auditoria where email = op));

  -- ===================== 06. Tiempos con la red real de esta base =====================
  select f.activo_id into v_real from redes.flujo_modelo f join redes.activo_vigente_mat m on m.activo_id = f.activo_id
   where f.carga_id = v_cfl and f.llave not like 'ZT9A-%' and m.cuenta_vigente and not m.retirado and f.sentido_mayor <> 'sin_flujo' order by md5(f.llave) limit 1;
  if v_real is null then v_real := pg_temp.id('T4'); end if;
  v_t0 := clock_timestamp(); j := redes.f_simular_aguas_arriba(v_real); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); j2 := redes.f_simular_aguas_arriba(pg_temp.id('T4')); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS (red de %s tramos y %s válvulas): un tramo real (%s; %s; %s válvulas; %s a %s contratos) %s ms · el tramo de prueba %s ms',
                   j -> 'red' ->> 'tramos', j -> 'red' ->> 'valvulas', j -> 'activo' ->> 'codigo', j ->> 'metodo',
                   case when (j ->> 'cae_a_total')::boolean then j -> 'aislamiento_total' -> 'estrecho' ->> 'valvulas_total' else j -> 'aguas_arriba' ->> 'valvulas_total' end, j ->> 'contratos_min', j ->> 'contratos_max', v_ms1, v_ms2);
  -- el caso de David, como dato (solo si el tramo existe en esta base): qué pide por aguas arriba y qué pide el aislamiento total
  if exists (select 1 from redes.activo_vigente_mat where codigo = 'RED-000077' and sistema = 'acueducto' and not retirado) then
    v_t0 := clock_timestamp(); j := redes.f_simular_aguas_arriba((select activo_id from redes.activo_vigente_mat where codigo = 'RED-000077'));
    v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
    v_caso := format('RED-000077 (%s ms): %s; por %s %s; comprobación por %s: %s; aislamiento total: %s válvulas', v_ms3, j ->> 'metodo', j ->> 'criterio',
      case when (j -> 'aguas_arriba' ->> 'se_puede')::boolean then format('%s válvula(s) [%s], %s a %s contratos', j -> 'aguas_arriba' ->> 'valvulas_total', pg_temp.vals(j -> 'aguas_arriba' -> 'valvulas'), j ->> 'contratos_min', j ->> 'contratos_max')
           else 'no se puede (' || (j -> 'aguas_arriba' ->> 'texto') || ')' end,
      j -> 'comprobacion' ->> 'criterio',
      case when (j -> 'comprobacion' ->> 'se_puede')::boolean then format('%s válvula(s) [%s]', j -> 'comprobacion' ->> 'valvulas_total', pg_temp.vals(j -> 'comprobacion' -> 'valvulas')) else 'no se puede' end,
      redes.f_simular_cierre((select activo_id from redes.activo_vigente_mat where codigo = 'RED-000077')) -> 'estrecho' ->> 'valvulas_total');
  end if;
  v_info := v_info || E'\nCASO REAL: ' || v_caso;
  perform pg_temp.reg('06.01 TIEMPOS: cada simulación por aguas arriba en menos de 5 s', greatest(v_ms1, v_ms2, v_ms3) < 5000, v_info);
  perform pg_temp.reg('06.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 9b, cierre por aguas arriba (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
