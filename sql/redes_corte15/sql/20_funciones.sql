-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 20 — VISTA Y FUNCIONES INTERNAS (ninguna la ejecuta la API)
--   · quién puede qué; la zona de cada alcance; contratos y usuarios sensibles de la zona; los reportes que caen en una zona;
--   · la ASOCIACIÓN AUTOMÁTICA: tres disparadores AFTER INSERT por sentencia (con la tabla de filas nuevas: una consulta por sentencia, no por fila):
--       bot   → redes.reporte_externo_eventos (cuando entra el «recibido»);   116 → redes.l116_eventos (el «alta» al publicar);   daño → redes.danos;
--       formato de campo (Comercial o Técnica) → campo.reportes.
--     Sin eventos abiertos no hacen nada. Los eventos abiertos se leen UNA vez por sentencia («ab»), no una vez por reporte (crecía con el historial de eventos).
--     La pertenencia se decide por el punto del reporte (dentro de la zona; «toda la ciudad» no tiene geometría).
--     Si un punto cae en dos eventos abiertos gana EL MÁS ESPECÍFICO (David, 19-nov): círculo > sectores > total; entre dos de la misma clase, el de menor
--     área (un subsector antes que su sector) y, si empatan, el declarado más recientemente.
--   · lo que le llega a cada reporte: bot → «en_atencion» al asociar, «atendido» al cerrar, «recibido» al desasociar o anular; daño → una nota en su historial
--     (el daño NO se cierra con el evento: sigue hasta su reparación); 116 → «atendido» al cerrar; formato de campo → una nota al asociar, desasociar o
--     anular, y «atendido» al cerrar (si seguía «reportado» o «en revisión»).
--   · la publicación de la línea 116 NO revive lo que cerró un evento (redes.f_evento_l116_cerrado; el reemplazo está en 25_reemplazos.sql).
--   · los dos bloques para Avisos y la respuesta para el bot.
-- =====================================================================

-- ---------- estado de un evento: abierto → cerrado | anulado; la hora de regreso vigente es la del último ajuste ----------
create view redes.v_evento_suspension as
select e.*, coalesce(f.estado, 'abierto') as estado, f.hecho_en as fin_en, f.motivo as fin_motivo, f.autor as fin_autor,
       coalesce((select x.regreso_estimado from redes.evento_suspension_eventos x where x.evento_id = e.id and x.tipo = 'regreso' order by x.id desc limit 1), e.regreso_estimado) as regreso_vigente
  from redes.eventos_suspension e
  left join lateral (select case x.tipo when 'cerrar' then 'cerrado' else 'anulado' end as estado, x.hecho_en, x.motivo, x.autor
                       from redes.evento_suspension_eventos x where x.evento_id = e.id and x.tipo in ('cerrar', 'anular') limit 1) f on true;
revoke all on table redes.v_evento_suspension from public, anon, authenticated, service_role;

create function redes.f_eventos_abiertos() returns setof redes.eventos_suspension
language sql stable security definer set search_path = redes, pg_temp as $$
  select e.* from redes.eventos_suspension e
   where not exists (select 1 from redes.evento_suspension_eventos x where x.evento_id = e.id and x.tipo in ('cerrar', 'anular')) $$;

-- un reporte está «libre» si su último hecho no es «asociar» a un evento que siga abierto. SQL sin SET: se integra en la consulta que la llama
create function redes.f_evento_ref_libre(p_origen text, p_ref text) returns boolean
language sql stable as $$
  select not exists (
    select 1 from (select y.tipo, y.evento_id from redes.evento_suspension_reportes y where y.origen = p_origen and y.ref = p_ref order by y.id desc limit 1) u
     where u.tipo = 'asociar'
       and not exists (select 1 from redes.evento_suspension_eventos z where z.evento_id = u.evento_id and z.tipo in ('cerrar', 'anular'))) $$;

-- los reportes asociados HOY a un evento (su último hecho es «asociar» a este evento)
create function redes.f_evento_reportes(p_evento bigint) returns setof redes.evento_suspension_reportes
language sql stable security definer set search_path = redes, pg_temp as $$
  select r.* from redes.evento_suspension_reportes r
   where r.evento_id = p_evento and r.tipo = 'asociar'
     and not exists (select 1 from redes.evento_suspension_reportes x where x.origen = r.origen and x.ref = r.ref and x.id > r.id) $$;

-- el evento que CERRÓ un reporte de la línea 116 (su último hecho es «asociar» a un evento que terminó en «cerrar»), o nulo. La usa la publicación de la 116:
-- lo que cerró un evento conserva «Atendido» aunque el archivo siga diciendo «Registrado»
create function redes.f_evento_l116_cerrado(p_reporte_id bigint) returns text
language sql stable security definer set search_path = redes, pg_temp as $$
  select e.codigo
    from (select y.tipo, y.evento_id from redes.evento_suspension_reportes y where y.origen = 'l116' and y.ref = p_reporte_id::text order by y.id desc limit 1) u
    join redes.eventos_suspension e on e.id = u.evento_id
   where u.tipo = 'asociar' and exists (select 1 from redes.evento_suspension_eventos z where z.evento_id = u.evento_id and z.tipo = 'cerrar') $$;

-- un reporte del formato de campo sigue abierto: «reportado» o «en revisión», y no está oculto
create function redes.f_evento_campo_abierto(p_id uuid) returns boolean
language sql stable security definer set search_path = redes, pg_temp as $$
  select campo.f_estado_actual(p_id) in ('reportado', 'en_revision')
     and coalesce((select x.tipo_evento from campo.reporte_eventos x where x.reporte_id = p_id and x.tipo_evento in ('ocultar', 'reincluir') order by x.id desc limit 1), 'reincluir') <> 'ocultar' $$;

-- la causal de la 116 como clave del catálogo: minúsculas y un solo espacio
create function redes.f_evento_clave(p_texto text) returns text
language sql immutable as $$ select lower(regexp_replace(btrim(coalesce(p_texto, '')), '\s+', ' ', 'g')) $$;

-- «18/11, 9:40 p. m.» (hora de Bogotá)
create function redes.f_evento_hora(p_cuando timestamptz) returns text
language sql stable as $$
  select to_char(p_cuando at time zone 'America/Bogota', 'DD/MM, FMHH12:MI') || case when extract(hour from p_cuando at time zone 'America/Bogota') < 12 then ' a. m.' else ' p. m.' end $$;

-- ---------- quién puede qué ----------
--   lectura: cualquiera de Técnica · detalle y catálogo: los dos supervisores · zona (sectores o círculo) y reportes: supervisor de distribución
--   total: supervisor de planta · el administrador, todo.
create function redes.f_evento_autorizar(p_solicitante text, p_para text) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_p record; v_sd boolean; v_sp boolean;
begin
  select * into v_p from redes.f_perfil_lectura(p_solicitante);
  if v_p.perfil = 'admin' or p_para = 'lectura' then return v_p.email; end if;
  v_sd := v_p.perfil = 'supervisor';
  v_sp := public.geoportal_puede(v_p.email, 'dashboard_tecnico');
  if (p_para in ('zona', 'reportes') and v_sd) or (p_para = 'total' and v_sp) or (p_para = 'detalle' and (v_sd or v_sp)) then return v_p.email; end if;
  raise exception '%', case p_para
      when 'total' then 'Un evento total lo declara, ajusta o cierra el supervisor de planta o el administrador'
      when 'zona' then 'Un evento por sectores o por círculo lo declara, ajusta o cierra el supervisor de distribución o el administrador'
      when 'reportes' then 'Los reportes de un evento y sus catálogos los maneja el supervisor de distribución o el administrador'
      else 'Solo los supervisores o el administrador ven el detalle de un evento' end using errcode = '42501';
end $$;

-- ---------- la zona de cada alcance (no revisa permisos) ----------
create function redes.f_evento_zona(p jsonb, out alcance text, out todo boolean, out geom geometry, out sectores bigint[], out planta_id bigint,
                                    out centro_lat numeric, out centro_lon numeric, out radio_m numeric, out zona_nombre text) returns record
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_cods text[]; v_cuantos integer; v_pl tecnica.plantas%rowtype; v_sector text; v_pt geometry;
begin
  alcance := coalesce(p ->> 'alcance', ''); todo := false; sectores := '{}';
  if alcance = 'sectores' then
    if jsonb_typeof(p -> 'sectores') is distinct from 'array' or jsonb_array_length(p -> 'sectores') = 0 then perform tecnica.f_error('Escoja al menos un sector o subsector'); end if;
    if jsonb_array_length(p -> 'sectores') > coalesce(redes.f_param('evento_sectores_max'), 40) then
      perform tecnica.f_error(format('Un evento admite máximo %s sectores o subsectores', coalesce(redes.f_param('evento_sectores_max'), 40)));
    end if;
    select array_agg(distinct upper(btrim(x))) into v_cods from jsonb_array_elements_text(p -> 'sectores') x;
    select array_agg(m.activo_id order by m.codigo), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(m.geom)), 3)),
           string_agg(coalesce(nullif(btrim(m.nombre), ''), m.codigo), ', ' order by m.codigo), count(*)
      into sectores, geom, zona_nombre, v_cuantos
      from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.codigo = any (v_cods);
    if v_cuantos is distinct from cardinality(v_cods) then perform tecnica.f_error('Alguno de los sectores no existe o ya no está vigente', 'P0002'); end if;
    zona_nombre := left(zona_nombre, 300);
  elsif alcance = 'circulo' then
    centro_lat := round(redes.f_num(p -> 'lat'), 6); centro_lon := round(redes.f_num(p -> 'lon'), 6); radio_m := round(redes.f_num(p -> 'radio_m'), 1);
    if centro_lat is null or centro_lon is null or centro_lat not between -90 and 90 or centro_lon not between -180 and 180 then perform tecnica.f_error('Marque el centro del círculo en el mapa'); end if;
    if radio_m is null or radio_m < coalesce(redes.f_param('evento_radio_min_m'), 20) or radio_m > coalesce(redes.f_param('evento_radio_max_m'), 5000) then
      perform tecnica.f_error(format('El radio del círculo va de %s a %s metros', coalesce(redes.f_param('evento_radio_min_m'), 20), coalesce(redes.f_param('evento_radio_max_m'), 5000)));
    end if;
    v_pt := ST_SetSRID(ST_MakePoint(centro_lon, centro_lat), 4326);
    geom := ST_Multi(ST_Buffer(v_pt::geography, radio_m, 16)::geometry);
    select s.nombre into v_sector from redes.f_sector_de(v_pt) s;
    zona_nombre := format('un círculo de %s m', round(radio_m)) || coalesce(' en ' || nullif(btrim(v_sector), ''), '');
  elsif alcance = 'total' then
    if coalesce(p ->> 'total', '') = 'ciudad' then
      todo := true; zona_nombre := 'toda la ciudad';
    elsif coalesce(p ->> 'total', '') = 'planta' then
      select * into v_pl from tecnica.plantas pl where pl.codigo = lower(btrim(coalesce(p ->> 'planta', ''))) and pl.activa;
      if v_pl.id is null then perform tecnica.f_error('Escoja la planta', 'P0002'); end if;
      planta_id := v_pl.id;
      select array_agg(m.activo_id order by m.codigo), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(m.geom)), 3))
        into sectores, geom
        from redes.planta_sectores ps join redes.activo_vigente_mat m on m.activo_id = ps.sector_id
       where ps.planta_id = v_pl.id and ps.activo and m.prefijo = 'SEC' and not m.retirado and not m.oculto;
      if sectores is null then
        perform tecnica.f_error(format('La planta %s todavía no tiene sectores asignados: asígnelos primero, o declare el evento para toda la ciudad', v_pl.nombre));
      end if;
      zona_nombre := 'lo que surte la planta ' || v_pl.nombre;
    else perform tecnica.f_error('El evento total es de toda la ciudad o de una planta');
    end if;
  else perform tecnica.f_error('Escoja el alcance: por sectores, por círculo o total');
  end if;
  if not todo and (geom is null or ST_IsEmpty(geom)) then perform tecnica.f_error('No se pudo armar la zona del evento'); end if;
end $$;

-- ---------- contratos de la zona (por el tramo más cercano de cada contrato: aproximado) y usuarios sensibles CONFIRMADOS. Sin nombres ----------
create function redes.f_evento_contratos(p_geom geometry, p_todo boolean, p_lista boolean default false) returns jsonb
language plpgsql stable security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_contratos integer; v_sens integer; v_lista jsonb;
begin
  if p_todo then
    select count(*) into v_contratos from redes.contrato_tramo;
    select count(*), case when p_lista then coalesce(jsonb_agg(jsonb_build_object('contrato', s.contrato, 'tipo', ts.nombre) order by ts.orden, s.contrato), '[]'::jsonb) end
      into v_sens, v_lista
      from redes.v_usuario_sensible s join redes.tipos_sensible ts on ts.codigo = s.tipo where s.estado = 'confirmado';
  else
    select count(*) into v_contratos
      from redes.activo_vigente_mat m join redes.contrato_tramo ct on ct.activo_id = m.activo_id
     where m.geom && p_geom and ST_Intersects(m.geom, p_geom);
    select count(*), case when p_lista then coalesce(jsonb_agg(jsonb_build_object('contrato', s.contrato, 'tipo', ts.nombre) order by ts.orden, s.contrato), '[]'::jsonb) end
      into v_sens, v_lista
      from redes.v_usuario_sensible s join redes.tipos_sensible ts on ts.codigo = s.tipo
      join redes.contrato_tramo ct on ct.contrato = s.contrato join redes.activo_vigente_mat m on m.activo_id = ct.activo_id
     where s.estado = 'confirmado' and ST_Intersects(m.geom, p_geom);
  end if;
  return jsonb_build_object('contratos', v_contratos, 'sensibles', v_sens) || case when p_lista then jsonb_build_object('sensibles_lista', v_lista) else '{}'::jsonb end;
end $$;

-- ---------- los reportes ABIERTOS que caen en una zona desde una hora (al declarar y en la vista previa) ----------
create function redes.f_evento_candidatos(p_geom geometry, p_todo boolean, p_desde timestamptz, p_sin_dano uuid default null)
returns table (origen text, reporte_externo_id uuid, l116_reporte_id bigint, dano_id uuid, campo_reporte_id uuid)
language sql stable security definer set search_path = redes, public, extensions, pg_temp as $$
  select 'bot', r.id, null::bigint, null::uuid, null::uuid
    from redes.reportes_externos r
   where r.recibido_en >= p_desde and r.geom is not null and (p_todo or (r.geom && p_geom and ST_Intersects(p_geom, r.geom)))
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'bot' and t.codigo = lower(btrim(r.tipo_bot)) and t.asocia)
     and (select x.tipo from redes.reporte_externo_eventos x where x.reporte_id = r.id order by x.id desc limit 1) = 'recibido'
     and redes.f_evento_ref_libre('bot', r.id::text)
  union all
  select 'l116', null::uuid, v.reporte_id, null::uuid, null::uuid
    from redes.l116_vigente v
   where not v.oculto and v.estado = 'registrado' and v.fecha_registro >= p_desde and v.geom is not null and (p_todo or (v.geom && p_geom and ST_Intersects(p_geom, v.geom)))
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'l116' and t.codigo = redes.f_evento_clave(v.causal) and t.asocia)
     and redes.f_evento_ref_libre('l116', v.reporte_id::text)
  union all
  select 'dano', null::uuid, null::bigint, d.id, null::uuid
    from redes.danos d
   where d.registrado_en >= p_desde and d.t_detectado >= p_desde and d.sistema = 'acueducto' and d.geom is not null and (p_todo or (d.geom && p_geom and ST_Intersects(p_geom, d.geom)))
     and (p_sin_dano is null or d.id <> p_sin_dano)
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'dano' and t.codigo = d.tipo_codigo and t.asocia)
     and (select vd.estado from redes.v_dano vd where vd.id = d.id) <> 'atendido'
     and redes.f_evento_ref_libre('dano', d.id::text)
  union all
  select 'campo', null::uuid, null::bigint, null::uuid, c.id
    from campo.reportes c join campo.tipos_reporte tc on tc.id = c.tipo_id
   where c.registrado_en >= p_desde and (p_todo or ST_Intersects(p_geom, c.geom))
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'campo' and t.codigo = tc.codigo and t.asocia)
     and redes.f_evento_campo_abierto(c.id)
     and redes.f_evento_ref_libre('campo', c.id::text) $$;

-- ---------- lo que le llega a cada reporte de unas asociaciones: bot → un hecho de su historial; daño → una nota; formato de campo → una nota, o «atendido»
-- cuando el evento se cierra (p_bot_tipo = 'atendido') y el reporte seguía abierto. «{evento}» = el código ----------
create function redes.f_evento_marcar(p_ids bigint[], p_bot_tipo text, p_texto text, p_autor text) returns void
language plpgsql volatile security definer set search_path = redes, pg_temp as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then return; end if;
  insert into redes.reporte_externo_eventos (reporte_id, tipo, motivo, autor)
  select r.reporte_externo_id, p_bot_tipo, left(replace(p_texto, '{evento}', e.codigo), 1000), p_autor
    from redes.evento_suspension_reportes r join redes.eventos_suspension e on e.id = r.evento_id
   where r.id = any (p_ids) and r.origen = 'bot' order by r.id;
  insert into redes.dano_eventos (dano_id, tipo, motivo, autor)
  select r.dano_id, 'nota', left(replace(p_texto, '{evento}', e.codigo), 1000), p_autor
    from redes.evento_suspension_reportes r join redes.eventos_suspension e on e.id = r.evento_id
   where r.id = any (p_ids) and r.origen = 'dano' order by r.id;
  insert into campo.reporte_eventos (reporte_id, tipo_evento, estado_nuevo, motivo, autor)
  select r.campo_reporte_id, case when k.cierra then 'cambio_estado' else 'nota' end, case when k.cierra then 'atendido' end,
         left(replace(p_texto, '{evento}', e.codigo), 1000), p_autor
    from redes.evento_suspension_reportes r join redes.eventos_suspension e on e.id = r.evento_id
   cross join lateral (select coalesce(p_bot_tipo = 'atendido', false) and redes.f_evento_campo_abierto(r.campo_reporte_id) as cierra) k
   where r.id = any (p_ids) and r.origen = 'campo' order by r.id;
end $$;

-- ---------- LA ASOCIACIÓN AUTOMÁTICA ----------
-- bot: cuando entra el «recibido» ORIGINAL de un reporte (sin motivo; el reporte ya está guardado). El «en_atencion» que escribe vuelve a disparar esto y sale
-- en la primera línea. Un «recibido» con motivo es el de un reporte que alguien desasoció o de un evento anulado: ese no se vuelve a asociar solo.
create function redes.f_evento_tg_bot() returns trigger
language plpgsql security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_ids bigint[];
begin
  if not exists (select 1 from nuevos x where x.tipo = 'recibido' and x.motivo is null) or not exists (select 1 from redes.f_eventos_abiertos()) then return null; end if;
  with ab as materialized (select e.id, e.desde, e.todo, e.geom, e.alcance from redes.f_eventos_abiertos() e),
  hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, tipo, modo, autor)
    select ev.id, 'bot', r.id, 'asociar', 'automatica', 'sistema@evento.suspension'
      from nuevos x join redes.reportes_externos r on r.id = x.reporte_id
     cross join lateral (select e.id from ab e
                          where e.desde <= r.recibido_en and (e.todo or ST_Intersects(e.geom, r.geom)) order by case e.alcance when 'circulo' then 1 when 'sectores' then 2 else 3 end, ST_Area(e.geom) nulls last, e.id desc limit 1) ev
     where x.tipo = 'recibido' and x.motivo is null and r.geom is not null
       and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'bot' and t.codigo = lower(btrim(r.tipo_bot)) and t.asocia)
       and redes.f_evento_ref_libre('bot', r.id::text)
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, 'en_atencion', 'Asociado al evento de suspensión {evento}', 'sistema@evento.suspension');
  return null;
end $$;
create trigger t_evento_asociar after insert on redes.reporte_externo_eventos referencing new table as nuevos for each statement execute function redes.f_evento_tg_bot();

-- línea 116: el «alta» de cada reporte nuevo al publicar una carga (trae el punto del contrato). Solo los que llegan en «Registrado»
create function redes.f_evento_tg_l116() returns trigger
language plpgsql security definer set search_path = redes, public, extensions, pg_temp as $$
begin
  if not exists (select 1 from nuevos x where x.tipo = 'alta' and x.geom is not null) or not exists (select 1 from redes.f_eventos_abiertos()) then return null; end if;
  with ab as materialized (select e.id, e.desde, e.todo, e.geom, e.alcance from redes.f_eventos_abiertos() e)
  insert into redes.evento_suspension_reportes (evento_id, origen, l116_reporte_id, tipo, modo, autor)
  select ev.id, 'l116', r.id, 'asociar', 'automatica', 'sistema@evento.suspension'
    from nuevos x join redes.l116_reportes r on r.id = x.reporte_id
   cross join lateral (select e.id from ab e
                        where e.desde <= r.fecha_registro and (e.todo or ST_Intersects(e.geom, x.geom)) order by case e.alcance when 'circulo' then 1 when 'sectores' then 2 else 3 end, ST_Area(e.geom) nulls last, e.id desc limit 1) ev
   where x.tipo = 'alta' and x.estado = 'registrado' and x.geom is not null
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'l116' and t.codigo = redes.f_evento_clave(r.causal) and t.asocia);      -- (un «alta» es de un reporte nuevo: no puede estar ya en un evento)
  return null;
end $$;
create trigger t_evento_asociar after insert on redes.l116_eventos referencing new table as nuevos for each statement execute function redes.f_evento_tg_l116();

-- daños (formulario, o un reporte del bot convertido): el daño se guarda como siempre y queda asociado, con una nota en su historial
create function redes.f_evento_tg_dano() returns trigger
language plpgsql security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_ids bigint[];
begin
  if not exists (select 1 from redes.f_eventos_abiertos()) then return null; end if;
  with ab as materialized (select e.id, e.desde, e.todo, e.geom, e.alcance from redes.f_eventos_abiertos() e),
  hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, dano_id, tipo, modo, autor)
    select ev.id, 'dano', d.id, 'asociar', 'automatica', 'sistema@evento.suspension'
      from nuevos d
     cross join lateral (select e.id from ab e
                          where e.desde <= d.t_detectado and (e.todo or ST_Intersects(e.geom, d.geom)) order by case e.alcance when 'circulo' then 1 when 'sectores' then 2 else 3 end, ST_Area(e.geom) nulls last, e.id desc limit 1) ev
     where d.sistema = 'acueducto' and d.geom is not null
       and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'dano' and t.codigo = d.tipo_codigo and t.asocia)
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, null, 'Asociado al evento de suspensión {evento} (el daño sigue abierto hasta su reparación)', 'sistema@evento.suspension');
  return null;
end $$;
create trigger t_evento_asociar after insert on redes.danos referencing new table as nuevos for each statement execute function redes.f_evento_tg_dano();

-- formato de campo (Comercial o Técnica): el reporte se guarda como siempre y queda asociado, con una nota en su historial (David, 19-nov)
create function redes.f_evento_tg_campo() returns trigger
language plpgsql security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_ids bigint[];
begin
  if not exists (select 1 from redes.f_eventos_abiertos()) then return null; end if;
  with ab as materialized (select e.id, e.desde, e.todo, e.geom, e.alcance from redes.f_eventos_abiertos() e),
  hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, campo_reporte_id, tipo, modo, autor)
    select ev.id, 'campo', c.id, 'asociar', 'automatica', 'sistema@evento.suspension'
      from nuevos c join campo.tipos_reporte tc on tc.id = c.tipo_id
     cross join lateral (select e.id from ab e
                          where e.desde <= c.registrado_en and (e.todo or ST_Intersects(e.geom, c.geom)) order by case e.alcance when 'circulo' then 1 when 'sectores' then 2 else 3 end, ST_Area(e.geom) nulls last, e.id desc limit 1) ev
     where exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'campo' and t.codigo = tc.codigo and t.asocia)
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, null, 'Asociado al evento de suspensión {evento}', 'sistema@evento.suspension');
  return null;
end $$;
create trigger t_evento_asociar after insert on campo.reportes referencing new table as nuevos for each statement execute function redes.f_evento_tg_campo();

-- ---------- el evento como lo ven las pantallas (sin datos de suscriptores; «quién» es el nombre del funcionario) ----------
create function redes.f_evento_franja(p_zona text, p_desde timestamptz, p_causa text, p_regreso timestamptz) returns text
language sql stable as $$
  select format('Sin agua en %s desde las %s por %s. Regreso estimado: %s', p_zona, redes.f_evento_hora(p_desde), rtrim(btrim(p_causa), '.'),
                coalesce(redes.f_evento_hora(p_regreso), 'sin definir.')) $$;      -- la hora ya termina en punto («p. m.»)

create function redes.f_evento_json(p_evento bigint, p_geo boolean default false) returns jsonb
language sql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
  select jsonb_build_object(
    'codigo', e.codigo, 'estado', e.estado, 'alcance', e.alcance,
    'total', case when e.alcance = 'total' then case when e.todo then 'ciudad' else 'planta' end end,
    'planta', (select pl.nombre from tecnica.plantas pl where pl.id = e.planta_id),
    'zona', e.zona_nombre, 'causa', e.causa,
    'registro', coalesce((select d.codigo from redes.danos d where d.id = e.dano_id), (select i.codigo from redes.intervenciones i where i.id = e.intervencion_id)),
    'desde', e.desde, 'regreso_estimado', e.regreso_vigente, 'declarado_en', e.creado_en,
    'declarado_por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = e.autor), 'Funcionario de EMDUPAR'),
    'contratos', e.contratos, 'sensibles', e.sensibles,
    'reportes', (select jsonb_build_object('total', count(*), 'bot', count(*) filter (where r.origen = 'bot'), 'l116', count(*) filter (where r.origen = 'l116'),
                                           'danos', count(*) filter (where r.origen = 'dano'), 'campo', count(*) filter (where r.origen = 'campo')) from redes.f_evento_reportes(e.id) r),
    'franja', redes.f_evento_franja(e.zona_nombre, e.desde, e.causa, e.regreso_vigente),
    'fin', case when e.estado <> 'abierto' then jsonb_build_object('cuando', e.fin_en, 'motivo', e.fin_motivo,
              'por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = e.fin_autor), 'Funcionario de EMDUPAR')) end,
    'circulo', case when e.alcance = 'circulo' then jsonb_build_object('lat', e.centro_lat, 'lon', e.centro_lon, 'radio_m', e.radio_m) end,
    'sectores', (select coalesce(jsonb_agg(m.codigo order by m.codigo), '[]'::jsonb) from redes.activo_vigente_mat m where m.activo_id = any (e.sectores)))
    || case when p_geo then jsonb_build_object('zona_geojson', case when e.geom is not null then ST_AsGeoJSON(ST_Multi(ST_SimplifyPreserveTopology(e.geom, 0.00002)), 6)::jsonb end) else '{}'::jsonb end
    from redes.v_evento_suspension e where e.id = p_evento $$;

-- ---------- para Avisos (Corte 12): UN aviso por evento abierto, y los «sin agua» que no están en ningún evento ----------
create function redes.f_eventos_para_avisos(p_ahora timestamptz) returns table (codigo text, alcance text, nivel text, titulo text, detalle text, n integer, desde timestamptz)
language sql stable security definer set search_path = redes, public, pg_temp as $$
  select e.codigo, e.alcance, case when e.regreso_vigente is not null and e.regreso_vigente < p_ahora then 'rojo' else 'naranja' end,
         format('Sin agua en %s desde las %s', e.zona_nombre, redes.f_evento_hora(e.desde)),
         format('%s. %s. Regreso estimado: %s%s', rtrim(btrim(e.causa), '.'),
                case c.n when 0 then 'Sin reportes asociados' when 1 then '1 reporte asociado' else c.n || ' reportes asociados' end,
                coalesce(redes.f_evento_hora(e.regreso_vigente), 'sin definir.'),      -- la hora ya termina en punto («p. m.»)
                case when e.regreso_vigente is not null and e.regreso_vigente < p_ahora then ' Ya pasó: ajuste la hora o cierre el evento.' else '' end),
         c.n, e.desde
    from (select a.*, coalesce((select x.regreso_estimado from redes.evento_suspension_eventos x where x.evento_id = a.id and x.tipo = 'regreso' order by x.id desc limit 1),
                               a.regreso_estimado) as regreso_vigente
            from redes.f_eventos_abiertos() a) e      -- solo los abiertos: no recorre el historial de eventos
   cross join lateral (select count(*)::integer as n from redes.f_evento_reportes(e.id)) c
   where e.creado_en <= p_ahora $$;

-- Los avisos se consultan seguido. Los eventos abiertos y los tipos de «sin agua» se calculan UNA vez, y «está en un evento abierto» se resuelve por reporte
-- con el índice de las asociaciones (origen, ref), escrito aquí mismo (una función por fila no se integra en el plan y se llamaba miles de veces).
create function redes.f_sin_agua_para_avisos(p_ahora timestamptz, p_horas numeric) returns table (n integer, desde timestamptz, items jsonb)
language sql stable security definer set search_path = redes, public, pg_temp as $$
  with abiertos as materialized (select coalesce(array_agg(e.id), '{}') as ids from redes.f_eventos_abiertos() e),
  tipos as materialized (
    select coalesce(array_agg(t.codigo) filter (where t.origen = 'bot'), '{}') as bot, coalesce(array_agg(t.codigo) filter (where t.origen = 'l116'), '{}') as l116,
           coalesce(array_agg(t.codigo) filter (where t.origen = 'campo'), '{}') as campo
      from redes.evento_tipos_asociables t where t.clase = 'sin_agua'),
  s as (
    select r.recibido_en as cuando, 'Bot · ' || r.radicado as txt
      from redes.reportes_externos r
     where r.recibido_en > p_ahora - make_interval(secs => (p_horas * 3600)::double precision) and r.recibido_en <= p_ahora
       and lower(btrim(r.tipo_bot)) = any ((select bot from tipos)::text[])
       and (select x.tipo from redes.reporte_externo_eventos x where x.reporte_id = r.id order by x.id desc limit 1) = 'recibido'
       and not exists (select 1 from redes.evento_suspension_reportes y
                        where y.origen = 'bot' and y.ref = r.id::text and y.tipo = 'asociar'
                          and not exists (select 1 from redes.evento_suspension_reportes y2 where y2.origen = y.origen and y2.ref = y.ref and y2.id > y.id)
                          and y.evento_id = any ((select ids from abiertos)::bigint[]))
    union all
    select v.fecha_registro, 'Línea 116 · ' || v.reporte || coalesce(' · sector ' || v.sector, '')
      from redes.l116_vigente v
     where not v.oculto and v.estado = 'registrado' and v.fecha_registro > p_ahora - make_interval(secs => (p_horas * 3600)::double precision) and v.fecha_registro <= p_ahora
       and redes.f_evento_clave(v.causal) = any ((select l116 from tipos)::text[])
       and not exists (select 1 from redes.evento_suspension_reportes y
                        where y.origen = 'l116' and y.ref = v.reporte_id::text and y.tipo = 'asociar'
                          and not exists (select 1 from redes.evento_suspension_reportes y2 where y2.origen = y.origen and y2.ref = y.ref and y2.id > y.id)
                          and y.evento_id = any ((select ids from abiertos)::bigint[]))
    union all
    select c.registrado_en, 'Formato de campo · ' || coalesce(c.consecutivo, 'REP-' || lpad(c.seq::text, 6, '0'))
      from campo.reportes c join campo.tipos_reporte tc on tc.id = c.tipo_id
     where c.registrado_en > p_ahora - make_interval(secs => (p_horas * 3600)::double precision) and c.registrado_en <= p_ahora
       and tc.codigo = any ((select campo from tipos)::text[])
       and campo.f_estado_actual(c.id) = 'reportado' and redes.f_evento_campo_abierto(c.id)
       and not exists (select 1 from redes.evento_suspension_reportes y
                        where y.origen = 'campo' and y.ref = c.id::text and y.tipo = 'asociar'
                          and not exists (select 1 from redes.evento_suspension_reportes y2 where y2.origen = y.origen and y2.ref = y.ref and y2.id > y.id)
                          and y.evento_id = any ((select ids from abiertos)::bigint[])))
  select count(*)::integer, min(s.cuando), coalesce((array_to_json((array_agg(s.txt order by s.cuando desc))[1:5]))::jsonb, '[]'::jsonb) from s $$;

-- ---------- para el bot (n8n en el Dell): recibe el reporte como siempre y dice si quedó en un evento abierto, con el texto listo ----------
-- No se da permiso a ningún rol aquí: el permiso para el Dell va cuando se conecte el bot. La función anterior (f_reporte_externo_recibir) no se toca.
create function redes.f_reporte_externo_recibir_evento(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_id uuid := redes.f_reporte_externo_recibir(p); v_ev redes.v_evento_suspension%rowtype;
begin
  select e.* into v_ev from redes.evento_suspension_reportes r join redes.v_evento_suspension e on e.id = r.evento_id
   where r.origen = 'bot' and r.ref = v_id::text and r.tipo = 'asociar' and e.estado = 'abierto'
     and not exists (select 1 from redes.evento_suspension_reportes x where x.origen = 'bot' and x.ref = r.ref and x.id > r.id);
  return jsonb_build_object('id', v_id, 'radicado', p ->> 'radicado', 'evento', v_ev.codigo, 'regreso_estimado', v_ev.regreso_vigente,
    'mensaje', case when v_ev.id is null then null
                    when v_ev.regreso_vigente is null then 'Ya sabemos del corte en tu sector. Todavía no hay hora estimada de regreso.'
                    else 'Ya sabemos del corte en tu sector. Regreso estimado: ' || redes.f_evento_hora(v_ev.regreso_vigente) end);
end $$;
