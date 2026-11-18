-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 80 · VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). Todas las filas deben decir OK.
-- Nota: después del acta, la fila 03 de la verificación del Corte 14 deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 la RPC del acta: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.oid = 'public.geoportal_redes_levantar_acta(text,text,text)'::regprocedure and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 1 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluida la nueva)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las 2 nuevas y del conjunto de funciones de redes con el acta',
         case when (select count(*) from (values ('redes.f_levantar_funcionario(text,text)', '60ef521c697327104ad52fbbbbec78b6'), ('public.geoportal_redes_levantar_acta(text,text,text)', '0a7f82ff6fa307a9edb877f5ab0aa816')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 2
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '7c888d4f9ba3835cef951b49ada8ca59' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
) t order by o;
