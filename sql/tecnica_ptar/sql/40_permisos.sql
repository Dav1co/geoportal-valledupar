-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 40 — PERMISOS. Todo objeto nuevo: revoke all a public, anon, authenticated y service_role; luego solo lo necesario.
-- Tablas: sin privilegios para ningún rol de la API (RLS activa sin políticas). Funciones internas: sin EXECUTE para nadie de la API.
-- RPC: EXECUTE solo service_role (la Edge). f_autorizar_supervision se reemplazó con CREATE OR REPLACE: conserva sus privilegios.
-- =====================================================================
revoke all on table tecnica.instalaciones, tecnica.elementos_planta, tecnica.elemento_alias_eventos, tecnica.alcance_eventos from public, anon, authenticated, service_role;

revoke all on function tecnica.f_elemento_coherente(), tecnica.f_elemento_protegido(), tecnica.f_tiene_alcance(text, text), tecnica.f_autorizar_ptar(text),
  tecnica.f_autorizar_instalacion(text, bigint), tecnica.f_alias_vigente(bigint, text), tecnica.f_tipo_elemento_texto(text), tecnica.f_instalacion(text)
  from public, anon, authenticated, service_role;

revoke all on function public.geoportal_tec_ptar_perfil(text), public.geoportal_tec_ptar_mapa(text, text), public.geoportal_tec_ptar_elemento(text, text),
  public.geoportal_tec_ptar_alias_fijar(text, text, text, text, text), public.geoportal_tec_ptar_alcances(text),
  public.geoportal_tec_ptar_alcance_fijar(text, text, text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_tec_ptar_perfil(text), public.geoportal_tec_ptar_mapa(text, text), public.geoportal_tec_ptar_elemento(text, text),
  public.geoportal_tec_ptar_alias_fijar(text, text, text, text, text), public.geoportal_tec_ptar_alcances(text),
  public.geoportal_tec_ptar_alcance_fijar(text, text, text, text, text, text)
  to service_role;
