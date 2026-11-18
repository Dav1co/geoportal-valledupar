-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 40 · PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- =====================================================================
revoke all on function redes.f_levantar_funcionario(text, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_redes_levantar_acta(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_levantar_acta(text, text, text) to service_role;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte14_acta', 'migracion_redes_corte14_acta', null, jsonb_build_object(
        'nuevas', jsonb_build_array('redes.f_levantar_funcionario', 'geoportal_redes_levantar_acta'),
        'motivo', 'Acta del reporte de activo (PDF, una por punto): quien reportó ve la suya; supervisor de distribución y administrador, todas'), null);
