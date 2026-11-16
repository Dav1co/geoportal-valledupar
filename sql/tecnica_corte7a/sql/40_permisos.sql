-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vistas nuevas: nadie de la API. Las 11 RPC nuevas: solo execute a service_role (la Edge geoportal-tecnica). Las funciones internas: nadie.
-- =====================================================================
revoke all on table tecnica.quimico_ficha_eventos, tecnica.quimico_ficha_preparaciones, tecnica.quimico_movimientos, tecnica.quimico_parametros,
                    tecnica.v_quimico_vigente, tecnica.v_quimico_saldo from public, anon, authenticated, service_role;
revoke all on sequence tecnica.quimico_ficha_eventos_id_seq, tecnica.quimico_movimientos_id_seq from public, anon, authenticated, service_role;
revoke all on function tecnica.f_qparam(text), tecnica.f_quimico_por_codigo(text), tecnica.f_ficha_subida(text, text), tecnica.f_dosis_optima_en(bigint, timestamptz),
                       tecnica.f_dia_movimiento(date, numeric), tecnica.f_quimico_identidad() from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_quimic%' and p.proname <> 'geoportal_tec_listar_quimicos' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@tecnica_corte7a', 'migracion_tecnica_corte7a', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.quimico_ficha_eventos', 'tecnica.quimico_ficha_preparaciones',
        'tecnica.quimico_movimientos', 'tecnica.quimico_parametros'), 'vistas', jsonb_build_array('tecnica.v_quimico_vigente', 'tecnica.v_quimico_saldo'), 'rpc_nuevas', 11,
        'reemplazadas', jsonb_build_array('redes.f_estado_contrato', 'public.geoportal_redes_contrato_tarjeta', 'public.geoportal_redes_geovisor', 'redes.f_funciones_sin_where'), 'base', 'corte 6c', 'bucket', 'tecnica-evidencias'), null);
