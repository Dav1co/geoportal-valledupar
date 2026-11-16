-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las funciones internas nuevas y las reemplazadas: nadie de la API. La RPC nueva y las RPC reemplazadas: solo service_role (la Edge geoportal-redes).
-- Las tablas nuevas: nadie de la API (las leen y escriben solo las funciones SECURITY DEFINER).
-- =====================================================================
revoke all on function redes.f_dir_norm(text), redes.f_dir_base(text), redes.f_barrio_norm(text), redes.f_l116_atributos(jsonb), redes.f_l116_fecha(text),
  redes.f_l116_candidatos(bigint), redes.f_resumen_l116(bigint), redes.f_publicar_l116(bigint, text, text), redes.f_revertir_l116(text, text)
  from public, anon, authenticated, service_role;
revoke all on function redes.f_lote(bigint, jsonb), redes.f_resumen(bigint), redes.f_publicar(bigint, text, text), redes.f_revertir(text, text, text)
  from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_l116_vincular_dano', 'geoportal_redes_geovisor_capa', 'geoportal_redes_cargue_capas') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte5d', 'migracion_redes_corte5d', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.l116_reportes', 'redes.l116_eventos', 'redes.l116_vigente', 'redes.l116_danos'),
        'nuevas', jsonb_build_array('redes.f_dir_norm', 'redes.f_dir_base', 'redes.f_barrio_norm', 'redes.f_l116_atributos', 'redes.f_l116_fecha', 'redes.f_l116_candidatos',
                                    'redes.f_resumen_l116', 'redes.f_publicar_l116', 'redes.f_revertir_l116', 'geoportal_redes_l116_vincular_dano'),
        'formularios_distribucion', jsonb_build_array('anomalia_compartida', 'revision_compartida'),
        'motivo', 'línea 116 por el Cargue de capas (sin nombre), ubicada por contrato, dirección o barrio, en el geovisor por fecha; formularios compartidos en distribución'), null);
