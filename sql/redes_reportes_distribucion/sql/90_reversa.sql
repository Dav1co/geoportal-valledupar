-- =====================================================================
-- TÉCNICA · FASE 1 · DESCARGAS DE DISTRIBUCIÓN · 90 — REVERSA (PROPUESTA). Quita las 3 RPC, las funciones internas y las 2 tablas.
-- SE NIEGA si alguna función cambió después de la migración, y SE NIEGA si ya hay descargas guardadas (son registro de auditoría: nada se borra;
-- la auditoría común también las tiene). Antes de la reversa, devuelva la Edge a la anterior.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_reporte_iniciar(text,text,jsonb,text,boolean,text)') is null then raise exception 'No hay nada que revertir: las descargas de Distribución no están aplicadas'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'ef5fc9df2a7ba17df5797bc2971d2f04' then
    raise exception 'Las funciones cambiaron después de la migración: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.reporte_descargas) then
    raise exception 'Ya hay descargas guardadas en redes.reporte_descargas: la reversa no las borra. Avise (se puede quitar solo la Edge y dejar el SQL)';
  end if;
end $$;
drop function redes.f_rep_valvulas(jsonb,timestamp with time zone,text,integer,boolean);
drop function redes.f_rep_ts(timestamp with time zone);
drop function redes.f_rep_sensibles(jsonb,boolean,timestamp with time zone,text,integer,boolean);
drop function redes.f_rep_sector_geom(integer);
drop function redes.f_rep_rotulo(text);
drop function redes.f_rep_punto(geometry);
drop function redes.f_rep_max_filas();
drop function redes.f_rep_levantamientos(jsonb,boolean,timestamp with time zone,text,integer,boolean);
drop function redes.f_rep_leame(text,jsonb,boolean,text,timestamp with time zone);
drop function redes.f_rep_l116(jsonb,boolean,timestamp with time zone,text,integer,boolean);
drop function redes.f_rep_filtros(text,jsonb);
drop function redes.f_rep_filas(text,jsonb,boolean,timestamp with time zone,text,integer,boolean);
drop function redes.f_rep_eventos(jsonb,boolean,timestamp with time zone,text,integer,boolean);
drop function redes.f_rep_contar(text,jsonb,boolean,timestamp with time zone);
drop function redes.f_rep_columnas(text);
drop function redes.f_rep_col(text,text,text,text,integer);
drop function redes.f_rep_catalogo();
drop function redes.f_rep_bot(jsonb,boolean,timestamp with time zone,text,integer,boolean);
drop function redes.f_rep_activos(jsonb,boolean,timestamp with time zone,text,integer,boolean);
drop function geoportal_redes_reporte_pagina(text,bigint,text,integer);
drop function geoportal_redes_reporte_iniciar(text,text,jsonb,text,boolean,text);
drop function geoportal_redes_reporte_cerrar(text,bigint,integer,text,text);
drop table redes.reporte_descarga_cierres;
drop table redes.reporte_descargas;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_reportes_distribucion', 'reversa_redes_reportes_distribucion', null, jsonb_build_object('motivo', 'reversa de las descargas de Distribución'), null);
