-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 · 40 — PERMISOS: revoke all antes de dar permisos. La interna: nadie de la API. Las 3 RPC: solo service_role.
-- =====================================================================
revoke all on function redes.f_flujo_clase(numeric) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_geovisor_mvt_flujo', 'geoportal_redes_flujo_modelo', 'geoportal_redes_flujo_tramo') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9b_f3', 'migracion_redes_corte9b_fase3', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.flujo_modelo', 'redes.flujo_modelo_horas'),
        'nuevas', jsonb_build_array('redes.f_flujo_clase', 'geoportal_redes_geovisor_mvt_flujo', 'geoportal_redes_flujo_modelo', 'geoportal_redes_flujo_tramo'),
        'capa', 'flujo_modelo (en espera)', 'motivo', 'capa «Flujo del agua (modelo)»: flujo por tubo de modeloV1 en la hora de mayor y de menor consumo'), null);
