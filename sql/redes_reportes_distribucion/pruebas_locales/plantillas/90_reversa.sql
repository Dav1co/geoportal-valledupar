-- =====================================================================
-- TÉCNICA · FASE 1 · DESCARGAS DE DISTRIBUCIÓN · 90 — REVERSA (PROPUESTA). Quita las 3 RPC, las funciones internas y las 2 tablas.
-- SE NIEGA si alguna función cambió después de la migración, y SE NIEGA si ya hay descargas guardadas (son registro de auditoría: nada se borra;
-- la auditoría común también las tiene). Antes de la reversa, devuelva la Edge a la anterior.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_reporte_iniciar(text,text,jsonb,text,boolean,text)') is null then raise exception 'No hay nada que revertir: las descargas de Distribución no están aplicadas'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_DIST}}' then
    raise exception 'Las funciones cambiaron después de la migración: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.reporte_descargas) then
    raise exception 'Ya hay descargas guardadas en redes.reporte_descargas: la reversa no las borra. Avise (se puede quitar solo la Edge y dejar el SQL)';
  end if;
end $$;
{{DROPS}}
drop table redes.reporte_descarga_cierres;
drop table redes.reporte_descargas;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_reportes_distribucion', 'reversa_redes_reportes_distribucion', null, jsonb_build_object('motivo', 'reversa de las descargas de Distribución'), null);
