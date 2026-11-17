-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vista nuevas: nadie de la API. Las 5 RPC: solo execute a service_role (la Edge geoportal-tecnica). Las internas: nadie.
-- Rol dell_avisos (el bot de avisos del Dell): nace SIN poder conectarse (NOLOGIN) y SIN CLAVE en este archivo. Solo ejecuta tomar, marcar y liberar.
--   Activar o rotar (a mano, fuera del repositorio): alter role dell_avisos login password '<clave>' valid until '<fecha>';   Apagar: alter role dell_avisos nologin;
-- =====================================================================
revoke all on table tecnica.aviso_parametros, tecnica.aviso_parametro_eventos, tecnica.quimico_minimo_eventos, tecnica.avisos_salida, tecnica.aviso_salida_eventos, tecnica.v_avisos_salida
  from public, anon, authenticated, service_role;
revoke all on sequence tecnica.aviso_parametro_eventos_id_seq, tecnica.quimico_minimo_eventos_id_seq, tecnica.aviso_salida_eventos_id_seq from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma, p.proname from pg_proc p
            where (p.pronamespace = 'tecnica'::regnamespace and p.proname in ('f_aparam', 'f_cuantos', 'f_texto_horas', 'f_texto_num', 'f_avisos_perfil', 'f_avisos', 'f_nivel_rango',
                                                                                'f_avisos_encolar', 'avisos_tomar', 'avisos_marcar', 'avisos_liberar'))
               or (p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_tec_avisos', 'geoportal_tec_avisos_parametros', 'geoportal_tec_aviso_parametro_fijar',
                                                                               'geoportal_tec_quimico_minimos', 'geoportal_tec_quimico_minimo_fijar')) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    if f.proname like 'geoportal\_tec\_%' then execute format('grant execute on function %s to service_role', f.firma); end if;
  end loop;
end $$;

create role dell_avisos nologin noinherit nosuperuser nocreatedb nocreaterole nobypassrls connection limit 2;
alter role dell_avisos set statement_timeout = '15s';
alter role dell_avisos set lock_timeout = '8s';
alter role dell_avisos set search_path = pg_catalog;
grant usage on schema tecnica to dell_avisos;
grant execute on function tecnica.avisos_tomar(integer, integer), tecnica.avisos_marcar(uuid, uuid, text, jsonb, boolean), tecnica.avisos_liberar(uuid, uuid) to dell_avisos;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@tecnica_corte12', 'migracion_tecnica_corte12', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.aviso_parametros', 'tecnica.aviso_parametro_eventos',
        'tecnica.quimico_minimo_eventos', 'tecnica.avisos_salida', 'tecnica.aviso_salida_eventos'), 'rpc_nuevas', 5, 'rol', 'dell_avisos (nologin)'), null);
