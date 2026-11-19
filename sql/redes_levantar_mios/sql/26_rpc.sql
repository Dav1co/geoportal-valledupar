-- =====================================================================
-- TÉCNICA · FASE 1 · «MIS REPORTES» (levantar_mios) · 26 — RPC (la llama la Edge geoportal-redes, ruta levantar_mios).
--   · geoportal_redes_levantar_mios: los puntos por levantar que reportó QUIEN CONSULTA, los últimos primero, con su estado de hoy.
-- Por qué: «levantar_lista» es la bandeja del supervisor (todos los puntos, con quién los reportó). Quien reporta no tenía cómo ver los suyos.
-- Quién: todo el que puede reportar (redes.f_levantar_acceso: administrador, supervisores, el operador con el formulario y Comercial con Formularios de campo).
-- Qué devuelve: solo lo propio. No trae nombres ni correos (ni el suyo ni el de quien cambió el estado), ni el motivo del estado, ni fotos, ni la posición.
-- Periodo: 30 o 90 días, o 0 = todos. Tope de 500 por respuesta; «total» dice cuántos hay y «recortada» si no cupieron todos.
-- Solo lectura: no guarda ni audita (no hay datos de suscriptores ni de otras personas).
-- =====================================================================
create function public.geoportal_redes_levantar_mios(p_solicitante text, p_dias integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare a record; v_dias integer := coalesce(p_dias, 30); v_tope constant integer := 500; v_desde timestamptz; v_total integer; v_items jsonb;
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if v_dias not in (0, 30, 90) then perform tecnica.f_error('El periodo es de 30 días, de 90 días o todos'); end if;
  if v_dias > 0 then v_desde := clock_timestamp() - make_interval(days => v_dias); end if;
  select count(*) into v_total from redes.levantar_puntos x where x.autor = a.email and (v_desde is null or x.registrado_en >= v_desde);
  select coalesce(jsonb_agg(jsonb_build_object('codigo', p.codigo, 'registrado_en', p.registrado_en, 'servicio', p.servicio, 'tipo', p.tipo, 'tipo_nombre', redes.f_levantar_tipo_nombre(p.tipo),
           'estado', p.estado, 'estado_nombre', redes.f_levantar_estado_nombre(p.estado), 'estado_desde', p.estado_desde,
           'activo', (select m.codigo from redes.activos m where m.id = p.activo_id)) order by p.registrado_en desc, p.codigo desc), '[]'::jsonb)
    into v_items
    from (select x.id from redes.levantar_puntos x where x.autor = a.email and (v_desde is null or x.registrado_en >= v_desde)
           order by x.registrado_en desc, x.codigo desc limit v_tope) m
    join redes.v_levantar_punto p on p.id = m.id;
  return jsonb_build_object('dias', v_dias, 'total', v_total, 'recortada', v_total > v_tope, 'items', v_items);
end $$;
