-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las 7 funciones internas nuevas: nadie de la API. Las 6 RPC nuevas y las 6 reemplazadas: solo service_role (la Edge geoportal-redes).
-- Las tablas y vistas nuevas ya quedaron sin privilegios en el 10 y en el 20.
-- =====================================================================
revoke all on function redes.f_ref_vigente(text), redes.f_sector_de(geometry), redes.f_pm_nivel_presion(numeric), redes.f_pm_sugerencia(text, text, text, text),
  redes.f_nodo_modelo(text), redes.f_ficha_referencia(bigint), redes.f_pm_marcar_por_verificar(text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_geovisor_mvt_ref', 'geoportal_redes_referencia', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_nodo_clasificar',
                                'geoportal_redes_por_verificar', 'geoportal_redes_activo_verificar',
                                'geoportal_redes_geovisor_mvt', 'geoportal_redes_danos', 'geoportal_redes_intervenciones', 'geoportal_redes_contrato_tarjeta',
                                'geoportal_redes_nodos_por_clasificar') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
revoke all on function redes.f_ficha(bigint, text) from public, anon, authenticated, service_role;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9a', 'migracion_redes_corte9a', null, jsonb_build_object(
        'tablas', jsonb_build_array('ref_cargas', 'ref_carga_eventos', 'pm_nodos', 'pm_tramos', 'pm_valvulas', 'pm_presion_hora', 'pm_alc_conductos', 'pm_alc_pozos', 'ref_elementos', 'pm_campana_lecturas'),
        'reemplazadas', jsonb_build_array('redes.f_ficha', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_danos', 'geoportal_redes_intervenciones', 'geoportal_redes_contrato_tarjeta',
                                          'geoportal_redes_nodos_por_clasificar', 'vista redes.v_nodo_vigente'),
        'motivo', 'integración del Plan Maestro 2014: datos de referencia en tablas aparte; la ficha oficial no cambia'), null);
