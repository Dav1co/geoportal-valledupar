-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas, vista y funciones internas nuevas: nadie de la API. RPC public.geoportal_redes_* (las nuevas y las de antes): solo execute a service_role.
-- =====================================================================
revoke all on all tables in schema redes from public, anon, authenticated, service_role;
revoke all on all sequences in schema redes from public, anon, authenticated, service_role;
revoke all on all functions in schema redes from public, anon, authenticated, service_role;
revoke all on table tecnica.personal_ficha_eventos from public, anon, authenticated, service_role;
revoke all on sequence tecnica.personal_ficha_eventos_id_seq from public, anon, authenticated, service_role;
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
values ('migracion@redes_corte4b', 'migracion_redes_corte4b', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.personal_ficha_eventos', 'redes.cuadrillas')), null);
