-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 26 — RPC NUEVAS (solo service_role: la Edge geoportal-redes)
--   · geoportal_redes_sector_en: el sector hidráulico de un punto. El formulario de daño lo propone desde la ubicación (respuesta 4 de David, 16-nov).
--   · geoportal_redes_nodos_clasificar_grupo: confirmar de una vez un grupo de «no crear activo» (respuesta 3 de David): primero la vista previa (cuántos,
--     cuáles y en qué sectores, con una huella del grupo), luego confirmar con un motivo y esa huella. Si el grupo cambió entre la vista previa y la
--     confirmación, se niega. Un evento «clasificar» por nodo; nada se borra ni se crea ningún activo.
-- =====================================================================
create function public.geoportal_redes_sector_en(p_solicitante text, p_lat numeric, p_lon numeric) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare p record; s record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then perform tecnica.f_error('La posición no es válida'); end if;
  select * into s from redes.f_sector_en(p_lat, p_lon);
  return jsonb_build_object('sector', s.sector, 'subsector', s.subsector, 'nombre', s.nombre);
end $$;

create function public.geoportal_redes_nodos_clasificar_grupo(p_solicitante text, p_grupo text, p_huella text default null, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'clasifica nodos'); v_mot text := btrim(coalesce(p_motivo, ''));
        v_ids bigint[]; v_ids2 bigint[]; v_texto text; v_clase text; v_n integer; v_huella text;
begin
  if coalesce(p_grupo, '') not in ('valvula_propuesta', 'macro_proyectado', 'tanque_proyectado') then
    perform tecnica.f_error('Ese grupo no existe: por grupo solo se confirman los de «no crear activo»');
  end if;
  select array_agg(b.nodo_id order by b.nodo_id), min(b.sug ->> 'texto'), min(b.sug ->> 'clase') into v_ids, v_texto, v_clase
    from (select n.nodo_id, redes.f_pm_sugerencia(pm.tipo, pm.que_es, pm.nombre, pm.zona_modelo) as sug
            from redes.v_nodo_visible n
            join redes.pm_nodos pm on n.sistema = 'acueducto' and pm.llave = n.llave_modelo and pm.carga_id = redes.f_ref_vigente('pm_nodos')
           where n.clase_nodo = 'por_clasificar') b
   where b.sug ->> 'accion' = 'no_crear' and b.sug ->> 'grupo' = p_grupo;
  v_n := coalesce(cardinality(v_ids), 0);
  v_huella := md5(coalesce(array_to_string(v_ids, ','), ''));
  if p_huella is null then      -- vista previa: no escribe nada
    return jsonb_build_object('vista_previa', true, 'grupo', p_grupo, 'texto', v_texto, 'clase', v_clase, 'n', v_n, 'huella', v_huella,
      'muestra', coalesce((select jsonb_agg(jsonb_build_object('nodo_id', x.id, 'nombre', coalesce(x.nombre_modelo, x.llave_modelo)) order by x.id)
                             from redes.nodos x where x.id = any (v_ids[1:30])), '[]'::jsonb),
      'por_sector', coalesce((select jsonb_agg(jsonb_build_object('sector', s.sector, 'n', s.n) order by s.sector nulls last)
                                from (select (select z.sector from redes.f_sector_de(x.geom) z) as sector, count(*) as n
                                        from redes.nodos x where x.id = any (v_ids) group by 1) s), '[]'::jsonb));
  end if;
  if v_n = 0 then perform tecnica.f_error('No quedan nodos en ese grupo'); end if;
  if p_huella <> v_huella then perform tecnica.f_error('El grupo cambió desde la vista previa (alguien clasificó un nodo): vuelva a ver la vista previa'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  -- los mismos candados que la clasificación de uno en uno; con los candados puestos, el grupo se vuelve a armar y debe ser el mismo
  perform pg_advisory_xact_lock(hashtext('redes.nodo.' || x)) from unnest(v_ids) x;
  select array_agg(b.nodo_id order by b.nodo_id) into v_ids2
    from (select n.nodo_id, redes.f_pm_sugerencia(pm.tipo, pm.que_es, pm.nombre, pm.zona_modelo) as sug
            from redes.v_nodo_visible n
            join redes.pm_nodos pm on n.sistema = 'acueducto' and pm.llave = n.llave_modelo and pm.carga_id = redes.f_ref_vigente('pm_nodos')
           where n.clase_nodo = 'por_clasificar') b
   where b.sug ->> 'accion' = 'no_crear' and b.sug ->> 'grupo' = p_grupo;
  if v_ids2 is distinct from v_ids then perform tecnica.f_error('El grupo cambió desde la vista previa (alguien clasificó un nodo): vuelva a ver la vista previa'); end if;
  insert into redes.nodo_eventos (nodo_id, tipo, clase, motivo, autor) select x, 'clasificar', v_clase, v_mot, v_email from unnest(v_ids) x;
  perform tecnica.f_auditar(v_email, 'redes_nodos_clasificar_grupo', p_grupo, jsonb_build_object('n', v_n, 'huella', v_huella, 'clase', v_clase, 'motivo', v_mot), null);
  return jsonb_build_object('grupo', p_grupo, 'texto', v_texto, 'n', v_n, 'clase_nodo', v_clase);
end $$;
