-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 40 — PERMISOS (primero se revoca todo; solo service_role ejecuta las RPC nuevas)
-- Las dos reemplazadas (personal, historial_personal) conservan sus permisos (create or replace no los cambia).
-- =====================================================================
revoke all on function public.geoportal_campo_personal_fijar(text, text, text, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_cuadrillas(text, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_cuadrilla_cambiar(text, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_catalogos(text, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_catalogo_cambiar(text, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_personal_actividad(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_personal_fijar(text, text, text, jsonb, text) to service_role;
grant execute on function public.geoportal_campo_cuadrillas(text, jsonb, text) to service_role;
grant execute on function public.geoportal_campo_cuadrilla_cambiar(text, jsonb, text) to service_role;
grant execute on function public.geoportal_campo_catalogos(text, text) to service_role;
grant execute on function public.geoportal_campo_catalogo_cambiar(text, jsonb, text) to service_role;
grant execute on function public.geoportal_campo_personal_actividad(text, text, text) to service_role;
