-- =====================================================================
-- 40 — PERMISOS: lo nuevo, por NOMBRE EXACTO (nunca por patrón). Las 2 RPC nuevas solo para service_role (la Edge); las internas, para nadie.
-- Las funciones reemplazadas conservan sus permisos (create or replace no los cambia).
-- =====================================================================
revoke all on function redes.f_evento_origen(bigint) from public, anon, authenticated, service_role;
revoke all on function redes.f_tubo_zona(text[]) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_redes_evento_causal_fijar(text, text, text, boolean, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_redes_tubo_sectores_fijar(text, text, text[], text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_evento_causal_fijar(text, text, text, boolean, text) to service_role;
grant execute on function public.geoportal_redes_tubo_sectores_fijar(text, text, text[], text) to service_role;
notify pgrst, 'reload schema';
