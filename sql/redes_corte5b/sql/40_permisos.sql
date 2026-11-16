-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vista nuevas: nadie de la API. Las 4 RPC nuevas: solo execute a service_role (la Edge geoportal-tecnica).
-- La función interna reemplazada (redes.f_candidatos_muestreo) sigue sin permisos para la API.
-- =====================================================================
revoke all on table tecnica.punto_ubicacion_propuestas, tecnica.punto_ubicacion_revisiones, tecnica.v_punto_propuestas from public, anon, authenticated, service_role;
revoke all on sequence tecnica.punto_ubicacion_propuestas_id_seq, tecnica.punto_ubicacion_revisiones_id_seq from public, anon, authenticated, service_role;
revoke all on function redes.f_candidatos_muestreo(bigint) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_punto%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte5b', 'migracion_redes_corte5b', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.punto_ubicacion_propuestas', 'tecnica.punto_ubicacion_revisiones'),
        'rpc', jsonb_build_array('geoportal_tec_puntos_mapa', 'geoportal_tec_punto_ubicacion_proponer', 'geoportal_tec_punto_ubicaciones', 'geoportal_tec_punto_ubicacion_revisar')), null);
