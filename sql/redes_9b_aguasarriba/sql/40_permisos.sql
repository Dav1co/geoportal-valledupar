-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 40 — PERMISOS: revoke all antes de dar permisos. Las 4 internas: nadie de la API. La RPC: solo service_role.
-- =====================================================================
revoke all on function redes.f_sim_sentidos(text), redes.f_sim_llenar_sentido(), redes.f_sim_aguas_arriba_criterio(text, bigint, bigint[], bigint[], geometry, integer, boolean),
                       redes.f_simular_aguas_arriba(bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.geoportal_redes_simulacion_aguas_arriba(text, text, numeric, numeric) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_simulacion_aguas_arriba(text, text, numeric, numeric) to service_role;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_9b_aguasarriba', 'migracion_redes_9b_aguas_arriba', null, jsonb_build_object(
        'nuevas', jsonb_build_array('redes.f_sim_sentidos', 'redes.f_sim_llenar_sentido', 'redes.f_sim_aguas_arriba_criterio', 'redes.f_simular_aguas_arriba', 'geoportal_redes_simulacion_aguas_arriba'),
        'parametros', jsonb_build_array('sim_aguas_arriba_criterio', 'sim_cota_minima_m'),
        'motivo', 'simulación de cierre por aguas arriba: las válvulas por donde entra el agua al tramo (por cota o por el flujo del modelo); la de siempre queda como aislamiento total'), null);
