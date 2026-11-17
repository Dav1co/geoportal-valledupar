-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las 8 funciones internas: nadie de la API. Las 6 RPC: solo service_role (la Edge geoportal-redes). Las tablas y la vista: nadie de la API (10_esquema.sql).
-- =====================================================================
revoke all on function redes.f_presion_nivel(numeric, numeric), redes.f_presion_nodos(text), redes.f_alertas_presion(text), redes.f_presion_para_avisos(), redes.f_sensible_tipo(text), redes.f_sensibles_proponer(text),
                       redes.f_sensibles_en(text[]), redes.f_sensor_estado(bigint)
  from public, anon, authenticated, service_role;
revoke all on function tecnica.f_avisos(boolean, boolean, timestamptz) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_alertas_presion', 'geoportal_redes_sensibles', 'geoportal_redes_sensible_fijar',
                     'geoportal_redes_afectacion', 'geoportal_redes_sensores', 'geoportal_redes_afectaciones_danos') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9b_f2', 'migracion_redes_corte9b_fase2', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.tipos_sensible', 'redes.usuarios_sensibles', 'redes.usuario_sensible_eventos', 'redes.presion_trabajo', 'redes.presion_horas_no_confiables', 'redes.sensor_lecturas'),
        'vistas', jsonb_build_array('redes.v_usuario_sensible'),
        'nuevas', jsonb_build_array('redes.f_presion_nivel', 'redes.f_presion_nodos', 'redes.f_alertas_presion', 'redes.f_presion_para_avisos', 'redes.f_sensible_tipo', 'redes.f_sensibles_proponer', 'redes.f_sensibles_en',
                                    'redes.f_sensor_estado', 'geoportal_redes_alertas_presion', 'geoportal_redes_sensibles', 'geoportal_redes_sensible_fijar',
                                    'geoportal_redes_afectacion', 'geoportal_redes_sensores', 'geoportal_redes_afectaciones_danos'),
        'aviso_parametros', jsonb_build_array('presion_modelo_aviso (0: el aviso de presiones sale apagado)'),
        'parametros', jsonb_build_array('sensor_sin_senal_min', 'presion_lista_max'),
        'reemplazadas', jsonb_build_array('tecnica.f_avisos (aviso informativo de presiones, D11: apagado por omisión y solo con las horas confiables)'),
        'capa_oculta', 'cortes',
        'motivo', 'alertas de presión de modelo (Res. 0330 de 2017), con las horas confiables, usuarios sensibles, afectación del daño o la intervención, daños abiertos sin límite de fecha para el modo Afectaciones, lecturas de sensores (vacía) y la capa de cortes oculta (vive en el modo Afectaciones)'), null);
