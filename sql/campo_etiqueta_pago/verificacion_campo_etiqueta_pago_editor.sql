-- [Code A] ETIQUETA DEL ÚLTIMO PAGO (27-nov) · VERIFICACIÓN (solo lectura; después de la migración: 8 de 8 OK) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
select o, k, estado from (
  select 1 as o, '1 la huella de campo es la de este cambio' as k, case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text collate "C", p.proname, p.oid::regprocedure::text collate "C")) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) = '9f8b8ec55fc7e1c56fdf74a5f4e7f3c4' then 'OK' else 'FALLA' end as estado
  union all
  select 2 as o, '2 la huella del acta no cambió' as k, case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '111506c690249ad3b56ebf572566434c' then 'OK' else 'FALLA' end as estado
  union all
  select 3 as o, '3 la huella de Técnica no cambió' as k, case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))) = '838b80984e51cc7873a666f85d657195' then 'OK' else 'FALLA' end as estado
  union all
  select 4 as o, '4 geoportal_campo_analisis_contrato es la de este cambio y ya no quita el corte del pago' as k, case when md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)'))) = '81d0967ea34e183d397f0ff846332a32' and position('f.ultimo_pago - ''corte''' in pg_get_functiondef(to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)'))) = 0 then 'OK' else 'FALLA' end as estado
  union all
  select 5 as o, '5 la RPC sigue solo para service_role y SECURITY DEFINER' as k, case when has_function_privilege('service_role', 'public.geoportal_campo_analisis_contrato(text,text,text)', 'execute') and not has_function_privilege('anon', 'public.geoportal_campo_analisis_contrato(text,text,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_analisis_contrato(text,text,text)', 'execute') and (select prosecdef from pg_proc where oid = to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)')) then 'OK' else 'FALLA' end as estado
  union all
  select 6 as o, '6 las 4 funciones de permisos vivas no cambiaron' as k, case when md5(pg_get_functiondef(to_regprocedure('public.geoportal_puede(text,text)'))) = '32f174a55b95788d3f8187b507303c2f' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_mis_permisos(text)'))) = '83166fe17be58da67bbdedaae429bedb' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)'))) = '01fda69a9d912067b8b4dc153ac7957e' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'))) = 'e5a90103b4a83440fd826f03266b7245' then 'OK' else 'FALLA' end as estado
  union all
  select 7 as o, '7 ninguna función de campo con DELETE o UPDATE sin WHERE' as k, case when (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0 then 'OK' else 'FALLA' end as estado
  union all
  select 8 as o, '8 redes.f_funciones_sin_where() devuelve cero filas' as k, case when (select count(*) from redes.f_funciones_sin_where()) = 0 then 'OK' else 'FALLA' end as estado
) t order by o;
