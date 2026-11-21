-- =====================================================================
-- TÉCNICA · FASE 1 · REPORTES DEL PTAP · 90 — REVERSA (PROPUESTA). Quita las 4 RPC, las funciones internas y las 2 tablas.
-- SE NIEGA si alguna de las funciones nuevas cambió después de la migración, y SE NIEGA si ya hay descargas guardadas (son registro de auditoría: nada se
-- borra; la auditoría común también las tiene). Antes de la reversa, devuelva la Edge a la anterior.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_tec_reporte_iniciar(text,text,jsonb,text,boolean,text)') is null then raise exception 'No hay nada que revertir: los reportes del PTAP no están aplicados'; end if;
  if (select count(*) from (values {{NUEVAS}}) c(f, m) where to_regprocedure(c.f) is not null and md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> {{N_NUEVAS}} then
    raise exception 'Las funciones de los reportes cambiaron después de la migración: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from tecnica.reporte_descargas) then
    raise exception 'Ya hay descargas guardadas en tecnica.reporte_descargas: la reversa no las borra. Avise (se puede quitar solo la Edge y dejar el SQL)';
  end if;
end $$;
{{DROPS}}
drop table tecnica.reporte_descarga_cierres;
drop table tecnica.reporte_descargas;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@tecnica_reportes_ptap', 'reversa_tecnica_reportes_ptap', null, jsonb_build_object('motivo', 'reversa de los reportes del PTAP'), null);
