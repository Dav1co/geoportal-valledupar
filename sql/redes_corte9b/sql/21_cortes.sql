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
