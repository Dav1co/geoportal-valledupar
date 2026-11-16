-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vista nuevas: nadie de la API. Las 4 RPC nuevas: solo execute a service_role (la Edge geoportal-redes). Las 4 funciones internas: nadie.
-- =====================================================================
revoke all on table redes.contratos_capa, redes.contratos_capa_estado, redes.vistas_compartidas, redes.muestreo_rangos, redes.v_reportes_comercial
  from public, anon, authenticated, service_role;
revoke all on function redes.f_estado_contrato(text), redes.f_refrescar_contratos_capa(), redes.f_contratos_capa_al_dia(), redes.f_muestreo_calidad(bigint)
  from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_vista_compartir', 'geoportal_redes_vista_abrir') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte6b', 'migracion_redes_corte6b', null, jsonb_build_object('tablas', jsonb_build_array('redes.contratos_capa', 'redes.contratos_capa_estado', 'redes.vistas_compartidas', 'redes.muestreo_rangos'),
        'vista', 'redes.v_reportes_comercial',
        'rpc', jsonb_build_array('geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_vista_compartir', 'geoportal_redes_vista_abrir'),
        'reemplazadas', 2), null);
