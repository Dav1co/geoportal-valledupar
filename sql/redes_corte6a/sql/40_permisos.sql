-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas nuevas: nadie de la API. Las 4 RPC nuevas: solo execute a service_role (la Edge geoportal-redes).
-- Las 4 funciones internas nuevas: nadie de la API. Las reemplazadas conservan sus permisos (create or replace).
-- =====================================================================
revoke all on table redes.geovisor_capas, redes.capas_por_perfil, redes.capas_por_perfil_eventos from public, anon, authenticated, service_role;
revoke all on sequence redes.capas_por_perfil_eventos_id_seq from public, anon, authenticated, service_role;
revoke all on function redes.f_autorizar_carga(text, text), redes.f_autorizar_carga_id(text, bigint), redes.f_geovisor_acceso(text), redes.f_puede_formulario(text, text)
  from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor_capa', 'geoportal_redes_geovisor_capas_fijar') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte6a', 'migracion_redes_corte6a', null, jsonb_build_object('tablas', jsonb_build_array('redes.geovisor_capas', 'redes.capas_por_perfil', 'redes.capas_por_perfil_eventos'),
        'rpc', jsonb_build_array('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor_capa', 'geoportal_redes_geovisor_capas_fijar'),
        'reemplazadas', 10, 'columna', 'redes.capas.carga_supervisor'), null);
