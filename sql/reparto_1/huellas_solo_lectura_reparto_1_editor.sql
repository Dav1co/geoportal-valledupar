-- REPARTO DE FACTURAS · COMMIT 1 (SQL) · HUELLAS (solo lectura; ANTES y DESPUÉS) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
-- Solo lectura. ANTES: 1 «NO EXISTE»; 2 a 7 con su md5 (anótelas); 8 «LAS DE PRODUCCIÓN»; 9 «LA DE PRODUCCIÓN». DESPUÉS: 1 «CON ESTE CORTE»; 2 a 9 IGUALES a las de antes.
select o, k, v, estado from (
  select 1 as o, '1 funciones de reparto y public.geoportal_reparto_* (conjunto)' as k, (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = to_regnamespace('reparto') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%')) as v,
         case when to_regnamespace('reparto') is null then 'NO EXISTE (sin aplicar)' when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = to_regnamespace('reparto') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%')) = '96b044a678e316f47673ac1216b466f8' then 'CON ESTE CORTE' else 'OTRA: deténgase y avise' end as estado
  union all
  select 2, '2 funciones de campo (conjunto)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')), 'anote: debe ser igual antes y después (hoy 261bed3c…; cambia con el paquete del Code B, que va antes)'
  union all
  select 3, '3 funciones de scrr (conjunto)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = to_regnamespace('scrr') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_scrr\_%')), 'anote: debe ser igual antes y después (722fc84b… el 23-nov)'
  union all
  select 4, '4 public.geoportal_puede (no se toca)', md5(pg_get_functiondef(to_regprocedure('public.geoportal_puede(text,text)'))), 'anote: debe ser igual antes y después'
  union all
  select 5, '5 public.geoportal_mis_permisos (no se toca)', md5(pg_get_functiondef(to_regprocedure('public.geoportal_mis_permisos(text)'))), 'anote: debe ser igual antes y después'
  union all
  select 6, '6 public.geoportal_admin_guardar (no se toca)', md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)'))), 'anote: debe ser igual antes y después'
  union all
  select 7, '7 public.geoportal_admin_permisos (no se toca)', md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'))), 'anote: debe ser igual antes y después'
  union all
  select 8, '8 las 5 funciones de campo que llama el reparto', (select string_agg(md5(pg_get_functiondef(to_regprocedure(f))), ' ' order by f) from unnest(array['campo.f_verificar(text,text)', 'campo.f_autorizar_supervision(text)', 'campo.f_actividades_persona(text)', 'campo.f_persona_comercial(text)', 'campo.f_quien_puede(text)']) f),
         case when (select bool_and(md5(pg_get_functiondef(to_regprocedure(x.f))) = x.m) from (values ('campo.f_verificar(text,text)', '6133b5c36189e31743270064c8398b8a'), ('campo.f_autorizar_supervision(text)', '5ac3368fa5f3a6347328285501894aec'), ('campo.f_actividades_persona(text)', '69bc9bd73d5797b826b3e504c1d92070'), ('campo.f_persona_comercial(text)', '99af03344249f7260357528096e92829'), ('campo.f_quien_puede(text)', '5a381a87f432b8d2a6c88ad98a13fe3c')) x(f, m)) then 'LAS DE PRODUCCIÓN (23-nov)' else 'OTRA: deténgase y avise' end
  union all
  select 9, '9 definición de bi.v_rutas_geoportal (md5; no se toca)', md5(pg_get_viewdef('bi.v_rutas_geoportal'::regclass, true)),
         case md5(pg_get_viewdef('bi.v_rutas_geoportal'::regclass, true)) when '51da701454deeee5accfd2163a9c8e31' then 'LA DE PRODUCCIÓN (23-nov)' else 'OTRA: deténgase y avise' end
) t order by o;
