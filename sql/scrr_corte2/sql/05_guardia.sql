-- =====================================================================
-- SCRR · CORTE 2 · 05 — GUARDIA (no aplica nada si la base no es la esperada)
-- Se niega si:
--   · el esquema scrr ya existe (el paquete no se reaplica: para rehacerlo, primero la reversa);
--   · la huella de campo no es la publicada el 22-nov 13:46 ({{HUELLA_CAMPO}}): el modo «Cartera» autoriza con campo.f_autorizar_supervision;
--   · campo.f_autorizar_supervision(text) no tiene su md5 publicada ({{MD5_AUTORIZAR_SUPERVISION}});
--   · public.cartera_suscripcion no es una tabla (relkind 'r') con exactamente sus 21 columnas de hoy (el cargador la actualiza: decisión 4 del 20-nov y P4 del 22-nov);
--   · faltan public.geoportal_auditoria o public.predios_comercial.
-- No toca las 4 funciones de permisos (geoportal_admin_permisos, geoportal_mis_permisos, geoportal_puede, geoportal_admin_guardar): la verificación comprueba
-- que siguen con su md5.
-- =====================================================================
do $guardia$
declare v text;
begin
  if exists (select 1 from pg_namespace where nspname = 'scrr') then
    raise exception 'GUARDIA SCRR: el esquema scrr ya existe. Este paquete no se reaplica; si hay que rehacerlo, primero la reversa.';
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v
    from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if v is distinct from '{{HUELLA_CAMPO}}' then
    raise exception 'GUARDIA SCRR: la huella de campo es % y se esperaba {{HUELLA_CAMPO}} (publicada el 22-nov 13:46). Deténgase y avise.', v;
  end if;
  if to_regprocedure('campo.f_autorizar_supervision(text)') is null
     or md5(pg_get_functiondef(to_regprocedure('campo.f_autorizar_supervision(text)'))) <> '{{MD5_AUTORIZAR_SUPERVISION}}' then
    raise exception 'GUARDIA SCRR: campo.f_autorizar_supervision(text) no está o cambió. Deténgase y avise.';
  end if;
  if (select relkind from pg_class where oid = to_regclass('public.cartera_suscripcion')) is distinct from 'r' then
    raise exception 'GUARDIA SCRR: public.cartera_suscripcion no existe o no es una tabla.';
  end if;
  select string_agg(column_name || ':' || data_type, ',' order by ordinal_position) into v
    from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion';
  if v is distinct from '{{COLUMNAS_SUSCRIPCION}}' then
    raise exception 'GUARDIA SCRR: las columnas de public.cartera_suscripcion no son las esperadas: %', v;
  end if;
  if to_regclass('public.geoportal_auditoria') is null or to_regclass('public.predios_comercial') is null then
    raise exception 'GUARDIA SCRR: falta public.geoportal_auditoria o public.predios_comercial.';
  end if;
end $guardia$;
