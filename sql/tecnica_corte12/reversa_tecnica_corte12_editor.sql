begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Quita las 16 funciones, la vista, las 5 tablas y el rol dell_avisos. Ninguna función existente cambió en el 12: no hay nada que devolver.
-- SE NIEGA (nada se borra) si ya hay cambios de plazos, saldos mínimos fijados o avisos en la cola de salida, o si el rol ya tiene login.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.aviso_parametros') is null then raise exception 'No hay nada que revertir: el Corte 12 no está aplicado'; end if;
  if exists (select 1 from tecnica.aviso_parametro_eventos) or exists (select 1 from tecnica.quimico_minimo_eventos) or exists (select 1 from tecnica.avisos_salida) then
    raise exception 'Ya hay cambios de plazos, saldos mínimos o avisos de salida: la reversa se niega (nada se borra)';
  end if;
  if (select rolcanlogin from pg_roles where rolname = 'dell_avisos') then raise exception 'El rol dell_avisos ya tiene login (el Dell está conectado): apáguelo antes (alter role dell_avisos nologin)'; end if;
  if (select count(*) from (values ('tecnica.f_aparam(text)', '157c8dfefb1867bce225d739f4f17370'), ('tecnica.f_cuantos(bigint,text,text)', '11e20d62bb6b54e48acbbfa23669999e'), ('tecnica.f_texto_horas(numeric)', '0376f9abe6c621d41617252a6da41012'), ('tecnica.f_texto_num(numeric)', '59a22259145b1cb40965a167e699abe3'), ('tecnica.f_avisos_perfil(text)', '332d8d75a4a11b841b3067dded32a714'), ('tecnica.f_avisos(boolean,boolean,timestamp with time zone)', '061990d1826a5a2de0a539ca22004987'), ('tecnica.f_nivel_rango(text)', 'f1b46546abb592ee757a11d1f5011f11'), ('tecnica.f_avisos_encolar(timestamp with time zone)', '39f25178f60c1ecf9758ca61df9a519a'), ('tecnica.avisos_tomar(integer,integer)', 'af7ca7068b3ef64e8bbcd610fbe0ba43'), ('tecnica.avisos_marcar(uuid,uuid,text,jsonb,boolean)', 'a5d3fae6abe9e4e35930276a5b761607'), ('tecnica.avisos_liberar(uuid,uuid)', 'a3f470a6beee4576994aeb6f6e32e589'), ('public.geoportal_tec_avisos(text)', 'f4e5d9159a6ea7d08936a86fd30af927'), ('public.geoportal_tec_avisos_parametros(text)', '6fbd9820e1af5ee0905672ec3a9db283'), ('public.geoportal_tec_aviso_parametro_fijar(text,text,numeric,text)', 'eca9e770442b99fa240541297d07f319'), ('public.geoportal_tec_quimico_minimos(text)', '3359eb220ca5121a7183b01e93a8dcb4'), ('public.geoportal_tec_quimico_minimo_fijar(text,text,numeric,text)', '81fa3ce0a1bc5caba6cdf5c4a208f956')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 16 then
    raise exception 'Las funciones del Corte 12 cambiaron después de la migración: la reversa se niega a quitarlas; avise';
  end if;
end $$;
drop function public.geoportal_tec_avisos(text), public.geoportal_tec_avisos_parametros(text), public.geoportal_tec_aviso_parametro_fijar(text, text, numeric, text),
              public.geoportal_tec_quimico_minimos(text), public.geoportal_tec_quimico_minimo_fijar(text, text, numeric, text);
drop function tecnica.avisos_tomar(integer, integer), tecnica.avisos_marcar(uuid, uuid, text, jsonb, boolean), tecnica.avisos_liberar(uuid, uuid), tecnica.f_avisos_encolar(timestamptz),
              tecnica.f_nivel_rango(text), tecnica.f_avisos(boolean, boolean, timestamptz), tecnica.f_avisos_perfil(text), tecnica.f_texto_num(numeric), tecnica.f_texto_horas(numeric),
              tecnica.f_cuantos(bigint, text, text), tecnica.f_aparam(text);
drop view tecnica.v_avisos_salida;
drop table tecnica.aviso_salida_eventos, tecnica.avisos_salida, tecnica.quimico_minimo_eventos, tecnica.aviso_parametro_eventos, tecnica.aviso_parametros;
revoke usage on schema tecnica from dell_avisos;
drop role dell_avisos;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values ('migracion@tecnica_corte12', 'reversa_tecnica_corte12', null, '{}'::jsonb, null);
commit;
