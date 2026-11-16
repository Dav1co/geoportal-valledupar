-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas nuevas: nadie de la API. Las 3 RPC nuevas y las 2 reemplazadas: solo execute a service_role (la Edge geoportal-tecnica). Las internas: nadie.
-- =====================================================================
revoke all on table tecnica.quimico_remision_preparaciones, tecnica.quimico_parametro_eventos from public, anon, authenticated, service_role;
revoke all on sequence tecnica.quimico_parametro_eventos_id_seq from public, anon, authenticated, service_role;
revoke all on function tecnica.f_remision_subida(text, text), tecnica.f_qparam_editable(text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_tec_quimico_remision_preparar', 'geoportal_tec_quimico_parametros', 'geoportal_tec_quimico_parametro_fijar', 'geoportal_tec_quimico_entrada', 'geoportal_tec_quimico_historial') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@tecnica_corte7c', 'migracion_tecnica_corte7c', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.quimico_remision_preparaciones', 'tecnica.quimico_parametro_eventos'),
        'columna', 'tecnica.quimico_movimientos.remision_foto', 'rpc_nuevas', 3, 'reemplazadas', jsonb_build_array('geoportal_tec_quimico_entrada', 'geoportal_tec_quimico_historial')), null);
