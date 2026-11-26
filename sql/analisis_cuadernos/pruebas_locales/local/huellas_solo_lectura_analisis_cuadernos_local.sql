-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 05 — HUELLAS (SOLO LECTURA; una sola consulta, apta para el editor SQL web). Correr ANTES y DESPUÉS de la migración.
-- Antes: 1 = 1ba192724c2fddcf321104700829f3cc, 2 = 4a10aa60971401954717fc3c74d3d869, 3 = vacío, 4 = 0, 5 = 0, 6 = el bucket ya creado por David. Después: 1 y 2 IGUALES, 3 = 1b0af7d56f1dbf4010dbf5ac8774db6e, 4 = 10, 5 = 11.
-- =====================================================================
select k, valor, esperado_antes, esperado_despues from (
  select 1 as o, '1 huella de redes (no cambia)' as k,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) as valor,
         '1ba192724c2fddcf321104700829f3cc' as esperado_antes, '1ba192724c2fddcf321104700829f3cc' as esperado_despues
  union all
  select 2, '2 huella de técnica (no cambia)',
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))),
         '4a10aa60971401954717fc3c74d3d869', '4a10aa60971401954717fc3c74d3d869'
  union all
  select 3, '3 huella de análisis (esquema analisis y geoportal_analisis_*)',
         coalesce((select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where p.prokind = 'f' and (n.nspname = 'analisis' or (n.nspname = 'public' and p.proname like 'geoportal\_analisis\_%'))), '(sin funciones)'),
         '(sin funciones)', '1b0af7d56f1dbf4010dbf5ac8774db6e'
  union all
  select 4, '4 tablas del esquema analisis', (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'analisis' and c.relkind = 'r'), '0', '10'
  union all
  select 5, '5 RPC geoportal_analisis_*', (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname like 'geoportal\_analisis\_%'), '0', '11'
  union all
  select 6, '6 bucket analisis-capturas (privado · bytes · tipos)',
         coalesce((select case when public then 'PÚBLICO' else 'privado' end || ' · ' || coalesce(file_size_limit::text, 'sin tope') || ' · ' || coalesce(array_to_string(allowed_mime_types, ','), 'cualquiera')
                     from storage.buckets where id = 'analisis-capturas'), 'NO EXISTE'), 'privado · 614400 · image/jpeg', 'privado · 614400 · image/jpeg'
) t order by o;
