-- MOTOR SCRR · CORTE 2 (modo «Cartera») · HUELLAS (solo lectura; ANTES y DESPUÉS) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
-- Solo lectura. ANTES: 1 «PUBLICADA (22-nov 13:46)», 2 «NO EXISTE», 3 a 6 con su md5 (anótelas). DESPUÉS: 1 igual, 2 «CON ESTE CORTE», 3 a 6 IGUALES a las de antes.
select o, k, v, estado from (
  select 1 as o, '1 funciones de campo (conjunto)' as k, (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) as v,
         case (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) when '261bed3c9242f6261f845ec4e1374b3a' then 'PUBLICADA (22-nov 13:46): lista para este corte' else 'OTRA: deténgase y avise' end as estado
  union all
  select 2, '2 funciones de scrr y public.geoportal_scrr_* (conjunto)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = to_regnamespace('scrr') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_scrr\_%')),
         case when to_regnamespace('scrr') is null then 'NO EXISTE (sin aplicar)' when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = to_regnamespace('scrr') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_scrr\_%')) = '9489c37205ece7ff51787156cc7beda5' then 'CON ESTE CORTE' else 'OTRA: deténgase y avise' end
  union all
  select 3, '3 public.geoportal_puede (no se toca)', md5(pg_get_functiondef(to_regprocedure('public.geoportal_puede(text,text)'))), 'anote: debe ser igual antes y después'
  union all
  select 4, '4 public.geoportal_mis_permisos (no se toca)', md5(pg_get_functiondef(to_regprocedure('public.geoportal_mis_permisos(text)'))), 'anote: debe ser igual antes y después'
  union all
  select 5, '5 public.geoportal_admin_guardar (no se toca)', md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)'))), 'anote: debe ser igual antes y después'
  union all
  select 6, '6 public.geoportal_admin_permisos (no se toca)', md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'))), 'anote: debe ser igual antes y después'
) t order by o;
