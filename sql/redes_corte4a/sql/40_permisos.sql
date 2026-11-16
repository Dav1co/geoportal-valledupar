-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Funciones internas nuevas de redes: nadie de la API. RPC public.geoportal_redes_* nuevas y reemplazadas: solo execute a service_role.
-- (Las 4 funciones de permisos vivas reciben sus permisos en 15, como en el paquete de Análisis de contrato.)
-- =====================================================================
revoke all on all tables in schema redes from public, anon, authenticated, service_role;
revoke all on all sequences in schema redes from public, anon, authenticated, service_role;
revoke all on all functions in schema redes from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración (la verificación 08 cuenta desde aquí los registros nuevos sin fotos)
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte4a', 'migracion_redes_corte4a', null, jsonb_build_object('permiso', 'ver_dashboard_redes', 'marcados', 0), null);
