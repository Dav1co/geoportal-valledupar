-- =====================================================================
-- TÉCNICA · FASE 1 · «MIS REPORTES» (levantar_mios) · 40 — PERMISOS: revoke all antes de dar permisos. La RPC: solo service_role.
-- =====================================================================
revoke all on function public.geoportal_redes_levantar_mios(text, integer) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_levantar_mios(text, integer) to service_role;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_levantar_mios', 'migracion_redes_levantar_mios', null, jsonb_build_object(
        'nuevas', jsonb_build_array('geoportal_redes_levantar_mios'), 'indices', jsonb_build_array('redes.ix_levantar_puntos_autor'),
        'motivo', 'quien reporta un activo por levantar ve sus propios reportes y su estado («Mis reportes»); no cambia la bandeja del supervisor'), null);
