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
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '1ba192724c2fddcf321104700829f3cc' as ok
  union all
  select 2, '2 huella de técnica sin cambio',
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))),
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))) = '4a10aa60971401954717fc3c74d3d869'
  union all
  select 3, '3 huella de análisis', (select md5(string_agg(md5(pg_get_functiondef(fn.oid)), '' order by fn.firma collate "C")) from fn),
         (select md5(string_agg(md5(pg_get_functiondef(fn.oid)), '' order by fn.firma collate "C")) from fn) = 'c8a803aae851e77c9cdf010535dec090'
  union all
  select 4, '4 las 28 funciones son las del paquete, una por una', (select count(*)::text from fn where fn.firma in ('analisis.f_acceso(text)', 'analisis.f_archivado(uuid)', 'analisis.f_conteo_zona(geometry)', 'analisis.f_cuaderno(text,uuid,boolean)', 'analisis.f_cupo_zona(text,integer)', 'analisis.f_en_valledupar(geometry)', 'analisis.f_err(text,text)', 'analisis.f_estilo_valido(jsonb)', 'analisis.f_funciones_sin_where()', 'analisis.f_geom(jsonb)', 'analisis.f_marcas(uuid,integer)', 'analisis.f_parametro(text)', 'analisis.f_punto(geometry)', 'analisis.f_solo_agregar()', 'analisis.f_ultima_version(uuid)', 'analisis.f_zona_valida(geometry)', 'geoportal_analisis_captura_anular(text,uuid,text)', 'geoportal_analisis_captura_confirmar(text,uuid)', 'geoportal_analisis_captura_firmar(text,uuid,text,numeric,numeric,numeric,numeric,integer,integer,integer,text)', 'geoportal_analisis_captura_ruta(text,uuid)', 'geoportal_analisis_cuaderno(text,uuid,integer)', 'geoportal_analisis_cuaderno_crear(text,text,text,jsonb)', 'geoportal_analisis_cuaderno_estado(text,uuid,text,text)', 'geoportal_analisis_cuaderno_exportar(text,uuid)', 'geoportal_analisis_cuaderno_guardar(text,uuid,integer,text,text,jsonb,jsonb)', 'geoportal_analisis_cuadernos(text,boolean)', 'geoportal_analisis_perfil(text)', 'geoportal_analisis_zona(text,jsonb)')),
         (select count(*) from fn) = 28 and (select count(*) from fn where fn.firma in ('analisis.f_acceso(text)', 'analisis.f_archivado(uuid)', 'analisis.f_conteo_zona(geometry)', 'analisis.f_cuaderno(text,uuid,boolean)', 'analisis.f_cupo_zona(text,integer)', 'analisis.f_en_valledupar(geometry)', 'analisis.f_err(text,text)', 'analisis.f_estilo_valido(jsonb)', 'analisis.f_funciones_sin_where()', 'analisis.f_geom(jsonb)', 'analisis.f_marcas(uuid,integer)', 'analisis.f_parametro(text)', 'analisis.f_punto(geometry)', 'analisis.f_solo_agregar()', 'analisis.f_ultima_version(uuid)', 'analisis.f_zona_valida(geometry)', 'geoportal_analisis_captura_anular(text,uuid,text)', 'geoportal_analisis_captura_confirmar(text,uuid)', 'geoportal_analisis_captura_firmar(text,uuid,text,numeric,numeric,numeric,numeric,integer,integer,integer,text)', 'geoportal_analisis_captura_ruta(text,uuid)', 'geoportal_analisis_cuaderno(text,uuid,integer)', 'geoportal_analisis_cuaderno_crear(text,text,text,jsonb)', 'geoportal_analisis_cuaderno_estado(text,uuid,text,text)', 'geoportal_analisis_cuaderno_exportar(text,uuid)', 'geoportal_analisis_cuaderno_guardar(text,uuid,integer,text,text,jsonb,jsonb)', 'geoportal_analisis_cuadernos(text,boolean)', 'geoportal_analisis_perfil(text)', 'geoportal_analisis_zona(text,jsonb)') and md5(pg_get_functiondef(fn.oid)) = case fn.firma when 'analisis.f_acceso(text)' then 'f713dc4049a0c646831e2225bdbf37bd' when 'analisis.f_archivado(uuid)' then 'c82d60aeba0792382ee912e5fba40b82' when 'analisis.f_conteo_zona(geometry)' then '3a012a0857cd2a4e16692d684cbe7718' when 'analisis.f_cuaderno(text,uuid,boolean)' then 'f75e9a6f4a025f7ed274685ab9e79eac' when 'analisis.f_cupo_zona(text,integer)' then 'b505a2442cf2e04e0bd1197a7847a3b5' when 'analisis.f_en_valledupar(geometry)' then '696a1ff956d9e226b6e6ca7f52554744' when 'analisis.f_err(text,text)' then 'd4b79977a062c526536a1f247c3d3478' when 'analisis.f_estilo_valido(jsonb)' then 'bfc8a34f54ee3caf6abe5db05da9c08f' when 'analisis.f_funciones_sin_where()' then 'c52d854e168dd8b64ba2efed0e2bd628' when 'analisis.f_geom(jsonb)' then '953fdcaa21aae7c0b2d9abc5989b1bb8' when 'analisis.f_marcas(uuid,integer)' then '8d0b1b53eafbdabbfdfd8fcb1f1e2ea0' when 'analisis.f_parametro(text)' then '2b4d16a50c85e216c12d2ee38d7603fb' when 'analisis.f_punto(geometry)' then '10e0ce0498c0cbdb7f0e9e38f7a2c395' when 'analisis.f_solo_agregar()' then '1496b259c051f18dd7336b321eb8ff24' when 'analisis.f_ultima_version(uuid)' then 'a347cae914a2f228e971bb3c25930498' when 'analisis.f_zona_valida(geometry)' then '19f460ac9258df7975fd82fb1a422812' when 'geoportal_analisis_captura_anular(text,uuid,text)' then '580015cc0a87ebc9a25ce3d1d64df913' when 'geoportal_analisis_captura_confirmar(text,uuid)' then '1c9bab956d831cf2641c3701a8a66fcc' when 'geoportal_analisis_captura_firmar(text,uuid,text,numeric,numeric,numeric,numeric,integer,integer,integer,text)' then '91fcf98ea2d40d05f2fe5a8824842c1c' when 'geoportal_analisis_captura_ruta(text,uuid)' then 'b2ce99db6717c87a41883706d3622b54' when 'geoportal_analisis_cuaderno(text,uuid,integer)' then '42b81b99774d17e218f96d29a2bef1f4' when 'geoportal_analisis_cuaderno_crear(text,text,text,jsonb)' then '4846f64bea10d0b44eb3ad1e20a0dd10' when 'geoportal_analisis_cuaderno_estado(text,uuid,text,text)' then 'ac8dbc89ab498c3a2693775271b19aa2' when 'geoportal_analisis_cuaderno_exportar(text,uuid)' then 'e9ca1a52d06b6bcdfed242f7f00369be' when 'geoportal_analisis_cuaderno_guardar(text,uuid,integer,text,text,jsonb,jsonb)' then 'f783fd678b11585bbe3870526d0b36e7' when 'geoportal_analisis_cuadernos(text,boolean)' then 'a282d773c56f367a6052944e2a3476a6' when 'geoportal_analisis_perfil(text)' then '08c6aa995785d05e57764dcf2c8c8404' when 'geoportal_analisis_zona(text,jsonb)' then '4d544f824721012c45db19f2edf7dd87' end) = 28
  union all
  select 5, '5 las 12 RPC: SECURITY DEFINER, search_path fijo y EXECUTE solo para service_role',
         (select count(*)::text from fn where fn.nspname = 'public'),
         (select count(*) = 12 and bool_and(fn.prosecdef and exists (select 1 from unnest(fn.proconfig) c where c like 'search_path=%')
                 and has_function_privilege('service_role', fn.oid, 'execute') and not has_function_privilege('anon', fn.oid, 'execute')
                 and not has_function_privilege('authenticated', fn.oid, 'execute')
                 and not exists (select 1 from aclexplode(coalesce(fn.proacl, acldefault('f', fn.proowner))) a where a.grantee = 0)) from fn where fn.nspname = 'public')
  union all
  select 6, '6 las internas: search_path fijo y sin EXECUTE para la API', (select count(*)::text from fn where fn.nspname = 'analisis'),
         (select bool_and(exists (select 1 from unnest(fn.proconfig) c where c like 'search_path=%') and not has_function_privilege('service_role', fn.oid, 'execute')
                 and not has_function_privilege('anon', fn.oid, 'execute') and not has_function_privilege('authenticated', fn.oid, 'execute')
                 and not exists (select 1 from aclexplode(coalesce(fn.proacl, acldefault('f', fn.proowner))) a where a.grantee = 0)) from fn where fn.nspname = 'analisis')
  union all
  select 7, '7 las 11 tablas: RLS sin políticas y sin privilegios para la API', (select string_agg(tb.relname, ', ' order by tb.relname) from tb),
         (select count(*) = 11 and bool_and(tb.relrowsecurity and not has_table_privilege('anon', tb.oid, 'select') and not has_table_privilege('authenticated', tb.oid, 'select')
                 and not has_table_privilege('service_role', tb.oid, 'select') and not has_table_privilege('service_role', tb.oid, 'insert')) from tb)
         and not exists (select 1 from pg_policy p join tb on tb.oid = p.polrelid)
  union all
  select 8, '8 solo agregar: 2 disparadores por tabla (UPDATE/DELETE por fila y TRUNCATE por sentencia)', (select count(*)::text from pg_trigger g join tb on tb.oid = g.tgrelid where not g.tgisinternal),
         (select count(*) = 22 and count(*) filter (where (g.tgtype & 32) = 32) = 11 and count(*) filter (where (g.tgtype & 24) = 24) = 11 and bool_and(g.tgenabled = 'O')
            from pg_trigger g join tb on tb.oid = g.tgrelid where not g.tgisinternal)
  union all
  select 9, '9 el Dell: USAGE del esquema y SELECT en las 11 tablas', (select count(*)::text from tb where has_table_privilege('homelab_lectura', tb.oid, 'select')),
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
