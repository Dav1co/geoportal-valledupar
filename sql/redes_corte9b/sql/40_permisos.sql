-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1) · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las funciones internas nuevas y la reemplazada: nadie de la API. Las 3 RPC nuevas: solo service_role (la Edge geoportal-redes).
-- La tabla nueva: nadie de la API (10_esquema.sql): la leen y escriben solo las funciones SECURITY DEFINER.
-- =====================================================================
revoke all on function redes.f_sim_grafo(), redes.f_sim_llenar_agua(), redes.f_sim_escenario(bigint[], bigint, boolean, bigint[], geometry, integer),
                       redes.f_simular_cierre(bigint), redes.f_sim_tramo_cercano(numeric, numeric), redes.f_sim_autorizar(text),
                       redes.f_cierres_vigentes(), redes.f_cierre_regreso(bigint), redes.f_cortes_foto(bigint, text, text),
                       redes.f_cortes_para_avisos(timestamptz, numeric, numeric)
  from public, anon, authenticated, service_role;
revoke all on function tecnica.f_avisos(boolean, boolean, timestamptz) from public, anon, authenticated, service_role;
revoke all on function redes.f_param_entero(text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_simulacion_cierre', 'geoportal_redes_simulacion_guardar', 'geoportal_redes_simulaciones',
                     'geoportal_redes_valvula_maniobra', 'geoportal_redes_corte_regreso', 'geoportal_redes_cortes_vigentes', 'geoportal_redes_cortes_recalcular',
                     'geoportal_redes_geovisor_mvt_cortes') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9b', 'migracion_redes_corte9b_fase1', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.simulaciones_cierre', 'redes.valvula_maniobras', 'redes.corte_fotos', 'redes.corte_foto_zonas', 'redes.corte_foto_tramos', 'redes.corte_foto_valvulas'),
        'nuevas', jsonb_build_array('redes.f_sim_grafo', 'redes.f_sim_llenar_agua', 'redes.f_sim_escenario', 'redes.f_simular_cierre', 'redes.f_sim_tramo_cercano',
                                    'redes.f_sim_autorizar', 'geoportal_redes_simulacion_cierre', 'geoportal_redes_simulacion_guardar', 'geoportal_redes_simulaciones',
                                    'redes.f_cierres_vigentes', 'redes.f_cierre_regreso', 'redes.f_cortes_foto', 'redes.f_cortes_para_avisos',
                                    'geoportal_redes_valvula_maniobra', 'geoportal_redes_corte_regreso', 'geoportal_redes_cortes_vigentes', 'geoportal_redes_cortes_recalcular',
                                    'geoportal_redes_geovisor_mvt_cortes'),
        'reemplazadas', jsonb_build_array('redes.f_param_entero', 'tecnica.f_avisos'),
        'aviso_parametros', jsonb_build_array('valvula_cerrada_naranja_h', 'valvula_cerrada_rojo_h'),
        'parametros', jsonb_build_array('sim_segmento_grande_tramos', 'sim_segmento_grande_contratos', 'sim_no_cierra_max', 'sim_valvulas_lista_max',
                                        'sim_contratos_guardar_max', 'sim_guardadas_max', 'corte_horas_atras_max'),
        'motivo', 'simulación de cierre de válvulas (§17, N-9) y cierre real: maniobras de válvula, foto del corte vigente (tuberías cerradas y afectadas, zonas, contratos), tesela del modo Afectaciones y aviso de válvula cerrada'), null);
