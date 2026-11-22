-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 · 40 — PERMISOS. Funciones nuevas: revoke all a public, anon, authenticated y service_role (las usan las RPC SECURITY DEFINER).
-- Las reemplazadas con CREATE OR REPLACE (f_formularios, f_tipo_punto_texto, f_autorizar_captura, geoportal_tec_ptar_mapa y _elemento) conservan sus privilegios.
-- =====================================================================
revoke all on function tecnica.f_parametros_punto(bigint, integer), tecnica.f_estado_parametros(jsonb) from public, anon, authenticated, service_role;
-- Las internas reemplazadas: sin EXECUTE para los roles de la API (en producción ya lo estaban desde la Torre B; se repite por si acaso: es idempotente y las RPC
-- SECURITY DEFINER las siguen llamando como dueñas).
revoke all on function tecnica.f_autorizar_captura(text, text), tecnica.f_formularios(), tecnica.f_tipo_punto_texto(text) from public, anon, authenticated;
