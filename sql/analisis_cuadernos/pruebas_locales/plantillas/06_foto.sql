-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 06 — FOTO DE ANTES. Va SOLO en el ensayo, ANTES de la guardia y del esquema (la migración no la lleva).
-- Guarda las huellas de redes y de técnica y el número de objetos de esos dos esquemas, para comprobar al final que el paquete no los tocó.
-- =====================================================================
create function pg_temp.foto() returns table (k text, v text) language sql stable as $$
  select 'huella_redes', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
  union all
  select 'huella_tecnica', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%')))
  union all
  select 'objetos_redes_tecnica', (select count(*)::text from pg_class c where c.relnamespace in ('redes'::regnamespace, 'tecnica'::regnamespace))
  union all
  select 'columnas_redes_tecnica', (select md5(coalesce(string_agg(c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by c.relname, a.attnum), ''))
           from pg_class c join pg_attribute a on a.attrelid = c.oid where c.relnamespace in ('redes'::regnamespace, 'tecnica'::regnamespace) and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped)
  union all
  select 'funciones_public', (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname not like 'geoportal\_analisis\_%')
  union all
  select 'disparadores_redes_tecnica', (select count(*)::text from pg_trigger t join pg_class c on c.oid = t.tgrelid where not t.tgisinternal and c.relnamespace in ('redes'::regnamespace, 'tecnica'::regnamespace)) $$;
create temp table _foto_antes as select * from pg_temp.foto();
