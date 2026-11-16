-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las 2 funciones internas nuevas: nadie de la API. Las 3 RPC reemplazadas conservan lo suyo (create or replace no cambia permisos); se repite
-- aquí el revoke y el grant a service_role (la Edge geoportal-redes) para que quede explícito.
-- =====================================================================
revoke all on function redes.f_contrato_uso(text, text), redes.f_funciones_sin_where() from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte6c', 'migracion_redes_corte6c', null, jsonb_build_object(
        'reemplazadas', jsonb_build_array('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta'),
        'nuevas', jsonb_build_array('redes.f_contrato_uso', 'redes.f_funciones_sin_where'),
        'retiradas', jsonb_build_array('redes.contratos_capa', 'redes.contratos_capa_estado', 'redes.f_refrescar_contratos_capa', 'redes.f_contratos_capa_al_dia'),
        'motivo', 'la capa de contratos se arma al vuelo; ninguna petición la rehace'), null);
