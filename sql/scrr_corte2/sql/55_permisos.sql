-- =====================================================================
-- SCRR · CORTE 2 · 40 — PERMISOS. Todo objeto nuevo: revoke all … from public, anon, authenticated, service_role ANTES de dar permisos.
-- Solo service_role ejecuta las RPC public.geoportal_scrr_* (la Edge geoportal-scrr). Nadie más toca el esquema scrr: las RPC son SECURITY DEFINER.
-- scrr.f_retirar_historial no se da a nadie: solo la corre el dueño desde el editor (P7 del 22-nov).
-- =====================================================================
revoke all on all tables in schema scrr from public, anon, authenticated, service_role;
revoke all on all sequences in schema scrr from public, anon, authenticated, service_role;
revoke all on all functions in schema scrr from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_scrr\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
