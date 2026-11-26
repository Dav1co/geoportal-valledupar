-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 80 — VERIFICACIÓN (SOLO LECTURA; una consulta, apta para el editor SQL web). Correr DESPUÉS de la migración: todo «OK».
-- =====================================================================
with fn as (select p.oid, p.oid::regprocedure::text as firma, n.nspname, p.proname, p.prosecdef, p.proconfig, p.proacl, p.proowner
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where p.prokind = 'f' and (n.nspname = 'analisis' or (n.nspname = 'public' and p.proname like 'geoportal\_analisis\_%'))),
     tb as (select c.oid, c.relname, c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'analisis' and c.relkind = 'r')
select k, valor, case when ok then 'OK' else 'REVISAR' end as estado from (
  select 1 as o, '1 huella de redes sin cambio' as k,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) as valor,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_REDES}}' as ok
  union all
  select 2, '2 huella de técnica sin cambio',
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))),
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))) = '{{MD5_TECNICA}}'
  union all
  select 3, '3 huella de análisis', (select md5(string_agg(md5(pg_get_functiondef(fn.oid)), '' order by fn.firma)) from fn),
         (select md5(string_agg(md5(pg_get_functiondef(fn.oid)), '' order by fn.firma)) from fn) = '{{MD5_ANALISIS}}'
  union all
  select 4, '4 las {{N_FUNC}} funciones son las del paquete, una por una', (select count(*)::text from fn where fn.firma in ({{FIRMAS}})),
         (select count(*) from fn) = {{N_FUNC}} and (select count(*) from fn where fn.firma in ({{FIRMAS}}) and md5(pg_get_functiondef(fn.oid)) = case fn.firma {{CASOS}} end) = {{N_FUNC}}
  union all
  select 5, '5 las 11 RPC: SECURITY DEFINER, search_path fijo y EXECUTE solo para service_role',
         (select count(*)::text from fn where fn.nspname = 'public'),
         (select count(*) = 11 and bool_and(fn.prosecdef and exists (select 1 from unnest(fn.proconfig) c where c like 'search_path=%')
                 and has_function_privilege('service_role', fn.oid, 'execute') and not has_function_privilege('anon', fn.oid, 'execute')
                 and not has_function_privilege('authenticated', fn.oid, 'execute')
                 and not exists (select 1 from aclexplode(coalesce(fn.proacl, acldefault('f', fn.proowner))) a where a.grantee = 0)) from fn where fn.nspname = 'public')
  union all
  select 6, '6 las internas: search_path fijo y sin EXECUTE para la API', (select count(*)::text from fn where fn.nspname = 'analisis'),
         (select bool_and(exists (select 1 from unnest(fn.proconfig) c where c like 'search_path=%') and not has_function_privilege('service_role', fn.oid, 'execute')
                 and not has_function_privilege('anon', fn.oid, 'execute') and not has_function_privilege('authenticated', fn.oid, 'execute')
                 and not exists (select 1 from aclexplode(coalesce(fn.proacl, acldefault('f', fn.proowner))) a where a.grantee = 0)) from fn where fn.nspname = 'analisis')
  union all
  select 7, '7 las 10 tablas: RLS sin políticas y sin privilegios para la API', (select string_agg(tb.relname, ', ' order by tb.relname) from tb),
         (select count(*) = 10 and bool_and(tb.relrowsecurity and not has_table_privilege('anon', tb.oid, 'select') and not has_table_privilege('authenticated', tb.oid, 'select')
                 and not has_table_privilege('service_role', tb.oid, 'select') and not has_table_privilege('service_role', tb.oid, 'insert')) from tb)
         and not exists (select 1 from pg_policy p join tb on tb.oid = p.polrelid)
  union all
  select 8, '8 solo agregar: 2 disparadores por tabla (UPDATE/DELETE por fila y TRUNCATE por sentencia)', (select count(*)::text from pg_trigger g join tb on tb.oid = g.tgrelid where not g.tgisinternal),
         (select count(*) = 20 and count(*) filter (where (g.tgtype & 32) = 32) = 10 and count(*) filter (where (g.tgtype & 24) = 24) = 10 and bool_and(g.tgenabled = 'O')
            from pg_trigger g join tb on tb.oid = g.tgrelid where not g.tgisinternal)
  union all
  select 9, '9 el Dell: USAGE del esquema y SELECT en las 10 tablas', (select count(*)::text from tb where has_table_privilege('homelab_lectura', tb.oid, 'select')),
         has_schema_privilege('homelab_lectura', 'analisis', 'usage') and (select bool_and(has_table_privilege('homelab_lectura', tb.oid, 'select') and not has_table_privilege('homelab_lectura', tb.oid, 'insert')) from tb)
  union all
  select 10, '10 catálogo (9 problemas y 12 activos) y los 8 topes', (select count(*) from analisis.catalogo) || ' · ' || (select count(distinct clave) from analisis.parametros),
         (select count(*) filter (where grupo = 'problema') = 9 and count(*) filter (where grupo = 'activo') = 12 from analisis.catalogo) and (select count(distinct clave) = 8 from analisis.parametros)
  union all
  select 11, '11 pg-safeupdate: funciones con DELETE/UPDATE sin WHERE', (select count(*)::text from analisis.f_funciones_sin_where()),
         not exists (select 1 from analisis.f_funciones_sin_where()) and not exists (select 1 from redes.f_funciones_sin_where())
  union all
  select 12, '12 bucket analisis-capturas: privado, solo JPEG, 600 KB', (select count(*)::text from storage.buckets where id = 'analisis-capturas'),
         exists (select 1 from storage.buckets where id = 'analisis-capturas' and not public and file_size_limit = 614400 and allowed_mime_types = array['image/jpeg'])
) t order by o;
