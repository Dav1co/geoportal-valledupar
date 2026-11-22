-- =====================================================================
-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · 40 — PERMISOS
-- La función nueva es interna: se revoca todo y no se le da a nadie (la llama la RPC, que es SECURITY DEFINER).
-- Las dos RPC reemplazadas conservan sus permisos publicados (create or replace no los cambia: solo service_role).
-- =====================================================================
revoke all on function campo.f_supervisor_comercial(text) from public, anon, authenticated, service_role;
