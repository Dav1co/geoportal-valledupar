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
