-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como las dejó el 6a (las 2 reemplazadas con su texto exacto), sin las 4 RPC nuevas, sin las 4 funciones internas nuevas, sin las 4 tablas
-- y la vista nuevas, y el catálogo del geovisor como en el 6a (contratos y reportes de Comercial vuelven a «preparada»). Los parámetros nuevos se quedan.
-- SE NIEGA si ya hay vistas compartidas (nada se borra) o si alguna función cambió después de la migración. La capa de contratos es derivada (se rehace).
-- =====================================================================
do $$
begin
  if to_regclass('redes.vistas_compartidas') is null then raise exception 'No hay nada que revertir: no existe redes.vistas_compartidas'; end if;
  if exists (select 1 from redes.vistas_compartidas) then raise exception 'Ya hay vistas compartidas: la reversa se niega (nada se borra)'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_6B}}'
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) <> {{N_RPC}}
     or (select count(*) from (values {{CAMBIADAS_6B}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> {{N_CAMBIADAS}} then
    raise exception 'Las funciones cambiaron después de la migración del Corte 6b: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto del 6a
{{TEXTOS_6A}}
-- 2. lo nuevo
{{DROPS}}
drop view redes.v_reportes_comercial;
drop table redes.vistas_compartidas;
drop table redes.contratos_capa;
drop table redes.contratos_capa_estado;
drop table redes.muestreo_rangos;
update redes.geovisor_capas set fuente = 'preparada', estado = 'espera_dato', nota = 'Llega en el Corte 6b' where codigo = 'contratos';
update redes.geovisor_capas set fuente = 'preparada', por_fecha = false, nota = 'Azul con contrato, rojo posibles clandestinos (Corte 8)' where codigo = 'reportes_comercial';
update redes.geovisor_capas set nota = 'El último cloro y la turbiedad llegan con los rangos del jefe de planta' where codigo = 'muestreo';
alter table redes.geovisor_capas drop constraint geovisor_capas_fuente_check;
alter table redes.geovisor_capas add constraint geovisor_capas_fuente_check check (fuente in ('tesela', 'geojson', 'preparada'));

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_6A}}' then
    raise exception 'La reversa no dejó la base como en el 6a';
  end if;
end $$;
