-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas nuevas: nadie de la API. Las 6 RPC nuevas: solo execute a service_role (las Edges geoportal-redes y geoportal-tecnica).
-- La función interna nueva (redes.f_cruzar_por_geometria) y las reemplazadas siguen sin permisos para la API (create or replace conserva los permisos).
-- =====================================================================
revoke all on table redes.ficha_campo_devoluciones, tecnica.punto_ubicacion_correcciones from public, anon, authenticated, service_role;
revoke all on sequence redes.ficha_campo_devoluciones_id_seq, tecnica.punto_ubicacion_correcciones_id_seq from public, anon, authenticated, service_role;
revoke all on function redes.f_cruzar_por_geometria(bigint) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_cargue_capas', 'geoportal_redes_cargue_historial', 'geoportal_redes_cargue_iniciar', 'geoportal_redes_carga_muestra',
                                'geoportal_redes_carga_devolver_campo', 'geoportal_tec_punto_ubicacion_corregir') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte5c', 'migracion_redes_corte5c', null, jsonb_build_object('tablas', jsonb_build_array('redes.ficha_campo_devoluciones', 'tecnica.punto_ubicacion_correcciones'),
        'rpc', jsonb_build_array('geoportal_redes_cargue_capas', 'geoportal_redes_cargue_historial', 'geoportal_redes_cargue_iniciar', 'geoportal_redes_carga_muestra',
                                 'geoportal_redes_carga_devolver_campo', 'geoportal_tec_punto_ubicacion_corregir'),
        'capas_nuevas', 11), null);
