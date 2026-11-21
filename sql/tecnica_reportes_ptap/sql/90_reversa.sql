-- =====================================================================
-- TÉCNICA · FASE 1 · REPORTES DEL PTAP · 90 — REVERSA (PROPUESTA). Quita las 4 RPC, las funciones internas y las 2 tablas.
-- SE NIEGA si alguna de las funciones nuevas cambió después de la migración, y SE NIEGA si ya hay descargas guardadas (son registro de auditoría: nada se
-- borra; la auditoría común también las tiene). Antes de la reversa, devuelva la Edge a la anterior.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_tec_reporte_iniciar(text,text,jsonb,text,boolean,text)') is null then raise exception 'No hay nada que revertir: los reportes del PTAP no están aplicados'; end if;
  if (select count(*) from (values ('geoportal_tec_reporte_cerrar(text,bigint,integer,text,text)', '2f76c0632a3bd6c7fc8ba054ef2ce3d0'), ('geoportal_tec_reporte_iniciar(text,text,jsonb,text,boolean,text)', '4c5c6acb1b81b545cbbc1865f45ac860'), ('geoportal_tec_reporte_pagina(text,bigint,text,integer)', '818a99308a99c880739ba08299cb0bce'), ('geoportal_tec_reporte_remision_foto(text,bigint,text)', 'd0ed2351fb3dfd2ab289e0688479e921'), ('tecnica.f_rep_catalogo()', '497bb7bd8d8867cd35dc362ef8ae4f94'), ('tecnica.f_rep_col(text,text,text,text,integer)', '03302ef51c4248764d7ba5b483b2d459'), ('tecnica.f_rep_cols_variables(text,date,date)', 'd46ff6aeacd556fb5fa5bf0c24eec8f7'), ('tecnica.f_rep_columnas(text,jsonb)', 'd178a29b3e4408b96b07bbaeae20f476'), ('tecnica.f_rep_envios(text,jsonb,boolean,timestamp with time zone,text,integer,jsonb,boolean)', '5adfbcb96a9ae77e2e2e61456a9e72ec'), ('tecnica.f_rep_envios_llaves(text,jsonb,boolean,timestamp with time zone,text,integer)', '9f8573b0fb8aeb4a99be41b1fe3f5cb0'), ('tecnica.f_rep_envios_pagina(text,jsonb,boolean,timestamp with time zone,text,integer,jsonb,date)', '27b983d1f6c6408322d5e761cecd671b'), ('tecnica.f_rep_eventos_planta(jsonb,boolean,timestamp with time zone,text,integer)', '5b97ed0684b94b94c14ec420aa1c212a'), ('tecnica.f_rep_filas(text,jsonb,boolean,timestamp with time zone,text,integer,jsonb,boolean)', '3322cf0a784a1822d1b48b34eb96d642'), ('tecnica.f_rep_filtros(text,jsonb)', 'a95c2f1e25415fbfd6b660b766da220c'), ('tecnica.f_rep_fuera_referencia(jsonb,boolean,timestamp with time zone,text,integer)', '7824ffb564ac569503870bba371a6bc0'), ('tecnica.f_rep_kardex(jsonb,timestamp with time zone,text,integer)', 'd9ef46b5af9ee5ac7ccfe308144f0d22'), ('tecnica.f_rep_leame(text,jsonb,boolean,text,timestamp with time zone)', '5f894b795ad896a7cc965b3ec5d37745'), ('tecnica.f_rep_max_filas()', '570dfa334c7e4cb8808dfebbb765bd14'), ('tecnica.f_rep_max_pagina()', '2c2200c266a01dd2ee191c24af93df53'), ('tecnica.f_rep_quimicos(text,jsonb,timestamp with time zone,text,integer)', 'd17b765a1230efba574b890d5dbfd6a8'), ('tecnica.f_rep_ts(timestamp with time zone)', '02a1cb1f4f2ef2d501b132eadaffeb0e'), ('tecnica.f_rep_valores(text[],jsonb,timestamp with time zone,date,bigint,date,boolean)', 'fb4317249f97dc75871c5c6be4019164')) c(f, m) where to_regprocedure(c.f) is not null and md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 22 then
    raise exception 'Las funciones de los reportes cambiaron después de la migración: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from tecnica.reporte_descargas) then
    raise exception 'Ya hay descargas guardadas en tecnica.reporte_descargas: la reversa no las borra. Avise (se puede quitar solo la Edge y dejar el SQL)';
  end if;
end $$;
drop function tecnica.f_rep_valores(text[],jsonb,timestamp with time zone,date,bigint,date,boolean);
drop function tecnica.f_rep_ts(timestamp with time zone);
drop function tecnica.f_rep_quimicos(text,jsonb,timestamp with time zone,text,integer);
drop function tecnica.f_rep_max_pagina();
drop function tecnica.f_rep_max_filas();
drop function tecnica.f_rep_leame(text,jsonb,boolean,text,timestamp with time zone);
drop function tecnica.f_rep_kardex(jsonb,timestamp with time zone,text,integer);
drop function tecnica.f_rep_fuera_referencia(jsonb,boolean,timestamp with time zone,text,integer);
drop function tecnica.f_rep_filtros(text,jsonb);
drop function tecnica.f_rep_filas(text,jsonb,boolean,timestamp with time zone,text,integer,jsonb,boolean);
drop function tecnica.f_rep_eventos_planta(jsonb,boolean,timestamp with time zone,text,integer);
drop function tecnica.f_rep_envios_pagina(text,jsonb,boolean,timestamp with time zone,text,integer,jsonb,date);
drop function tecnica.f_rep_envios_llaves(text,jsonb,boolean,timestamp with time zone,text,integer);
drop function tecnica.f_rep_envios(text,jsonb,boolean,timestamp with time zone,text,integer,jsonb,boolean);
drop function tecnica.f_rep_columnas(text,jsonb);
drop function tecnica.f_rep_cols_variables(text,date,date);
drop function tecnica.f_rep_col(text,text,text,text,integer);
drop function tecnica.f_rep_catalogo();
drop function geoportal_tec_reporte_remision_foto(text,bigint,text);
drop function geoportal_tec_reporte_pagina(text,bigint,text,integer);
drop function geoportal_tec_reporte_iniciar(text,text,jsonb,text,boolean,text);
drop function geoportal_tec_reporte_cerrar(text,bigint,integer,text,text);
drop table tecnica.reporte_descarga_cierres;
drop table tecnica.reporte_descargas;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@tecnica_reportes_ptap', 'reversa_tecnica_reportes_ptap', null, jsonb_build_object('motivo', 'reversa de los reportes del PTAP'), null);
