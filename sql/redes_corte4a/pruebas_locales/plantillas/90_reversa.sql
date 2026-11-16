-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja la base como la dejó el 3b: las 4 funciones de permisos con su texto del 14-nov, las 10 RPC y las 2 funciones internas de redes con su texto del
-- 3b, sin las 7 RPC nuevas ni sus ayudantes, y sin las 2 columnas nuevas.
-- SE NIEGA si alguien ya tiene ver_dashboard_redes, si algún daño tiene sector (nada se borra), o si alguna función cambió después de la migración.
-- Los eventos de ocultar, reabrir o anular que se hayan hecho se quedan (son de las tablas del 2 y el 3a): la reversa no los toca.
-- =====================================================================
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_lista_blanca' and column_name = 'ver_dashboard_redes') then
    raise exception 'No hay nada que revertir: no existe ver_dashboard_redes';
  end if;
  if exists (select 1 from public.geoportal_lista_blanca where ver_dashboard_redes) or exists (select 1 from redes.danos where sector_num is not null) then
    raise exception 'Ya hay supervisores de distribución o daños con sector: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_4A}}'
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{VIVAS_4A}})) <> 4 then
    raise exception 'Las funciones cambiaron después de la migración del Corte 4a: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las 4 funciones de permisos, con su texto del 14-nov
drop function {{FIRMA_ADMIN_PERMISOS_4A}};
drop function public.geoportal_admin_listar(text);
{{TEXTO_PUEDE}}
{{TEXTO_MIS_PERMISOS}}
{{TEXTO_ADMIN_PERMISOS}}
{{TEXTO_ADMIN_LISTAR}}
revoke all on function {{FIRMA_ADMIN_PERMISOS_VIVA}} from public, anon, authenticated;
revoke all on function public.geoportal_admin_listar(text) from public, anon, authenticated;
grant execute on function {{FIRMA_ADMIN_PERMISOS_VIVA}} to service_role;
grant execute on function public.geoportal_admin_listar(text) to service_role;

-- 2. las RPC y las funciones internas de redes, con su texto del 3b
{{TEXTOS_RPC_3B}}
{{TEXTOS_INTERNAS_3B}}
drop function public.geoportal_redes_mi_perfil(text);
drop function public.geoportal_redes_danos(text, text, integer);
drop function public.geoportal_redes_dano_evento(text, text, text, text);
drop function public.geoportal_redes_dano_tercero(text, text);
drop function public.geoportal_redes_intervencion_evento(text, text, text, text);
drop function public.geoportal_redes_reportes_bot(text, text, integer);
drop function public.geoportal_redes_crear_activo_bandeja(text, text, text, text, text, text, text);
drop function redes.f_autorizar_captura_redes(text, text);
drop function redes.f_es_supervisor_redes(text);

-- 3. las columnas nuevas (vacías: lo garantiza la guardia)
alter table redes.danos drop column sector_num;
comment on column redes.danos.sector_texto is null;
alter table public.geoportal_lista_blanca drop column ver_dashboard_redes;

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_3B}}'
     or md5(pg_get_functiondef('public.geoportal_puede(text,text)'::regprocedure)) <> '{{MD5_GEOPORTAL_PUEDE}}'
     or md5(pg_get_functiondef('public.geoportal_mis_permisos(text)'::regprocedure)) <> '{{MD5_GEOPORTAL_MIS_PERMISOS}}'
     or md5(pg_get_functiondef('{{FIRMA_ADMIN_PERMISOS_VIVA}}'::regprocedure)) <> '{{MD5_GEOPORTAL_ADMIN_PERMISOS}}'
     or md5(pg_get_functiondef('public.geoportal_admin_listar(text)'::regprocedure)) <> '{{MD5_GEOPORTAL_ADMIN_LISTAR}}' then
    raise exception 'La reversa no dejó la base como en el 3b';
  end if;
end $$;
