-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las funciones internas nuevas y las reemplazadas: nadie de la API. La RPC nueva y las dos RPC reemplazadas: solo service_role (la Edge geoportal-redes).
-- Las tablas nuevas: nadie de la API (10_esquema.sql): las leen solo las funciones SECURITY DEFINER.
-- =====================================================================
revoke all on function redes.f_val_hoja_alc(), redes.f_val_prefijos(), redes.f_ficha_regulatorio(bigint, text) from public, anon, authenticated, service_role;
revoke all on function redes.f_ficha(bigint, text), redes.f_param_entero(text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_valoracion', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte10', 'migracion_redes_corte10', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.val_hojas', 'redes.val_filas', 'redes.val_amarre'),
        'nuevas', jsonb_build_array('redes.f_val_hoja_alc', 'redes.f_val_prefijos', 'redes.f_ficha_regulatorio', 'geoportal_redes_valoracion'),
        'reemplazadas', jsonb_build_array('redes.f_ficha', 'redes.f_param_entero', 'geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt'),
        'parametros', jsonb_build_array('valoracion_hoja_alcantarillado', 'valoracion_tolerancia_pct'),
        'motivo', 'inventario regulatorio: la Valoración Técnica de 2019 como referencia, el amarre de cada activo con su fila, la conciliación, la sección de la ficha y la fecha regulatoria en el color por edad'), null);
