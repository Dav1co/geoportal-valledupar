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
  if (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> {{N_NUEVAS}} then
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
