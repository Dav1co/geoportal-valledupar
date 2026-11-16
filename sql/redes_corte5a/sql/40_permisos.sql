-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas, vista y funciones internas nuevas: nadie de la API. RPC public.geoportal_redes_* (las nuevas, las reemplazadas y las de antes): solo execute a service_role.
-- =====================================================================
revoke all on all tables in schema redes from public, anon, authenticated, service_role;
revoke all on all sequences in schema redes from public, anon, authenticated, service_role;
revoke all on all functions in schema redes from public, anon, authenticated, service_role;
revoke all on table tecnica.puntos_ubicacion, tecnica.punto_eventos from public, anon, authenticated, service_role;
revoke all on sequence tecnica.puntos_ubicacion_id_seq, tecnica.punto_eventos_id_seq from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte5a', 'migracion_redes_corte5a', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.puntos_ubicacion', 'tecnica.punto_eventos', 'redes.formularios_distribucion')), null);
