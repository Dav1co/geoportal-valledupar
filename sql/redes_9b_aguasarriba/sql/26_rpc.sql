-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 26 — RPC (la llamará la Edge geoportal-redes; la ruta y la pantalla son del Code B).
--   · geoportal_redes_simulacion_aguas_arriba: «¿Qué válvulas cierro?» por donde ENTRA el agua, desde un tramo o nodo (o el tramo más cercano a un punto).
-- Quién: los mismos de la simulación de cierre (quien captura daños y fallas o intervenciones, el supervisor y el administrador). No guarda nada.
-- Volátil: arma tablas temporales de la transacción (la Edge llama por POST).
-- =====================================================================
create function public.geoportal_redes_simulacion_aguas_arriba(p_solicitante text, p_activo text default null, p_lat numeric default null, p_lon numeric default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_sim_autorizar(p_solicitante); v_id bigint;
begin
  if nullif(btrim(coalesce(p_activo, '')), '') is not null then v_id := redes.f_buscar_activo(p_activo);
  else v_id := redes.f_sim_tramo_cercano(p_lat, p_lon);
  end if;
  return redes.f_simular_aguas_arriba(v_id);
end $$;
