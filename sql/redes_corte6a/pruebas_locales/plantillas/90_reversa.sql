-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como las dejó el 5c (las 10 reemplazadas con su texto exacto), sin las 4 RPC nuevas, sin las 4 funciones internas nuevas, sin las
-- 3 tablas nuevas y sin la columna carga_supervisor. Los parámetros nuevos se quedan (nadie los lee; los parámetros no se borran).
-- SE NIEGA si ya hay cambios de las capas por omisión (nada se borra), si alguna carga la abrió alguien que no es administrador, o si alguna función
-- cambió después de la migración.
-- =====================================================================
do $$
begin
  if to_regclass('redes.geovisor_capas') is null then raise exception 'No hay nada que revertir: no existe redes.geovisor_capas'; end if;
  if exists (select 1 from redes.capas_por_perfil_eventos) then
    raise exception 'Ya hay cambios de las capas por omisión del geovisor: la reversa se niega (nada se borra)';
  end if;
  if exists (select 1 from redes.cargas c where not public.geoportal_es_admin(c.autor)
              and c.creado_en > (select max(a.creado_en) from public.geoportal_auditoria a where a.accion = 'migracion_redes_corte6a')) then
    raise exception 'Ya hay cargas abiertas por el supervisor de distribución: la reversa se niega (el 5c no las conoce)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_6A}}'
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) <> {{N_RPC}}
     or (select count(*) from (values {{CAMBIADAS_6A}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> {{N_CAMBIADAS}} then
    raise exception 'Las funciones cambiaron después de la migración del Corte 6a: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto del 5c
{{TEXTOS_5C}}
-- 2. lo nuevo
{{DROPS}}
drop table redes.capas_por_perfil_eventos;
drop table redes.capas_por_perfil;
drop table redes.geovisor_capas;
alter table redes.capas drop column carga_supervisor;

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_5C}}' then
    raise exception 'La reversa no dejó la base como en el 5c';
  end if;
end $$;
