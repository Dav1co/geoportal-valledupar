-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las 2 funciones de redes como las dejó el 6b, quita las RPC y funciones nuevas, las tablas y las vistas de químicos (el bucket, vacío, se queda), el candado de identidad y
-- el rol «auxiliar»; los estados del contrato vuelven a los del 6b. El hipoclorito de calcio se DESACTIVA (los químicos no se borran) y los parámetros se quedan.
-- SE NIEGA si ya hay movimientos, eventos de ficha que no sean los de la migración, archivos en el bucket o químicos «auxiliar» distintos del hipoclorito.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.quimico_movimientos') is null then raise exception 'No hay nada que revertir: no existe tecnica.quimico_movimientos'; end if;
  if exists (select 1 from tecnica.quimico_movimientos) or exists (select 1 from tecnica.quimico_ficha_eventos where autor <> 'migracion@tecnica_corte7a')
     or exists (select 1 from storage.objects where bucket_id = 'tecnica-evidencias')
     or exists (select 1 from tecnica.quimicos where rol = 'auxiliar' and codigo <> 'hipoclorito_calcio') then
    raise exception 'Ya hay movimientos, fichas, archivos o químicos nuevos: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_7A}}'
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) <> {{N_RPC}} then
    raise exception 'Las funciones cambiaron después de la migración del Corte 7a: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las funciones de redes reemplazadas, con su texto del 6b
{{TEXTOS_6B}}
-- 2. lo nuevo
{{DROPS}}
drop view tecnica.v_quimico_saldo;
drop view tecnica.v_quimico_vigente;
drop table tecnica.quimico_movimientos;
drop table tecnica.quimico_ficha_preparaciones;
drop table tecnica.quimico_ficha_eventos;
drop table tecnica.quimico_parametros;
-- el bucket tecnica-evidencias se queda (vacío y privado): Storage no deja borrar buckets por SQL; si se vuelve a migrar, se reutiliza
drop trigger t_quimico_identidad on tecnica.quimicos;
drop function tecnica.f_quimico_identidad();
update tecnica.quimicos set activo = false, rol = 'desinfectante' where codigo = 'hipoclorito_calcio';
alter table tecnica.quimicos drop constraint quimicos_rol_check;
alter table tecnica.quimicos add constraint quimicos_rol_check check (rol = any (array['coagulante', 'desinfectante', 'otro']));
update redes.contratos_capa set estado = 'otro' where estado in ('suspendido', 'cortado');
alter table redes.contratos_capa drop constraint contratos_capa_estado_check;
alter table redes.contratos_capa add constraint contratos_capa_estado_check check (estado in ('activo', 'retirado', 'otro', 'sin_dato'));

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_6B}}' then
    raise exception 'La reversa no dejó la base como en el 6b';
  end if;
end $$;
