-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Funciones internas: nadie de la API. Las 3 RPC nuevas: solo execute a service_role (la Edge geoportal-campo). La vista: nadie de la API (como en el 6b).
-- =====================================================================
revoke all on function campo.f_tipo_general(text), campo.f_tecnica_claves(text), campo.f_tecnica_entrar(text, text) from public, anon, authenticated, service_role;
revoke all on function campo.f_autorizar_reporte(text), tecnica.f_formularios() from public, anon, authenticated, service_role;
revoke all on table redes.v_reportes_comercial from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_campo_tec_formulario', 'geoportal_campo_tec_preparar_subida', 'geoportal_campo_tec_crear_reporte') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@tecnica_corte8', 'migracion_tecnica_corte8', null, jsonb_build_object(
        'columna', 'campo.reportes.area', 'reemplazadas', jsonb_build_array('campo.f_autorizar_reporte', 'tecnica.f_formularios'), 'dominio', 'tecnica.formulario_clave',
        'rpc_nuevas', jsonb_build_array('geoportal_campo_tec_formulario', 'geoportal_campo_tec_preparar_subida', 'geoportal_campo_tec_crear_reporte'),
        'vista', 'redes.v_reportes_comercial',
        'tipos_agregados', (select coalesce(jsonb_agg(codigo), '[]'::jsonb) from campo.tipos_reporte where codigo in ('fuga_acometida', 'caja_medidor_danada'))), null);
