-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · VERIFICACIÓN (solo lectura; después de la migración: 6 de 6 OK) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
select o, k, estado from (
  select 1 as o, '1 las dos RPC y la función nueva con su md5' as k, case when md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)'))) = '8baf8468c6a9178df700cd94830cdd41' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal(text,jsonb,text)'))) = '8298374d98bd0cfedb7f205e838ccf65' and md5(pg_get_functiondef(to_regprocedure('campo.f_supervisor_comercial(text)'))) = '4f3f9883cf4afc0e1f75677d4c5898bd' then 'OK' else 'FALLA' end as estado
  union all
  select 2 as o, '2 la huella de campo es la de este cambio' as k, case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) = '261bed3c9242f6261f845ec4e1374b3a' then 'OK' else 'FALLA' end as estado
  union all
  select 3 as o, '3 la huella del acta no cambió (111506c6…)' as k, case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '111506c690249ad3b56ebf572566434c' then 'OK' else 'FALLA' end as estado
  union all
  select 4 as o, '4 permisos: las dos RPC solo service_role; la función nueva, nadie' as k, case when has_function_privilege('service_role', 'public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)', 'execute') and has_function_privilege('service_role', 'public.geoportal_campo_personal(text,jsonb,text)', 'execute') and not has_function_privilege('anon', 'public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)', 'execute') and not has_function_privilege('anon', 'public.geoportal_campo_personal(text,jsonb,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_personal(text,jsonb,text)', 'execute') and not has_function_privilege('service_role', 'campo.f_supervisor_comercial(text)', 'execute') and not has_function_privilege('authenticated', 'campo.f_supervisor_comercial(text)', 'execute') and not has_function_privilege('anon', 'campo.f_supervisor_comercial(text)', 'execute') then 'OK' else 'FALLA' end as estado
  union all
  select 5 as o, '5 ninguna función de campo con DELETE o UPDATE sin WHERE' as k, case when (with f as (
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
  select 6 as o, '6 redes.f_funciones_sin_where() devuelve cero filas' as k, case when (select count(*) from redes.f_funciones_sin_where()) = 0 then 'OK' else 'FALLA' end as estado
) t order by o;
