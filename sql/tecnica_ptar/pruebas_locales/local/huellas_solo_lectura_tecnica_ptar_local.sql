-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 05 — HUELLAS (SOLO LECTURA; una sola consulta, apta para el editor SQL web). Correr ANTES y DESPUÉS de la migración.
-- Antes: 1 = 1ba192724c2fddcf321104700829f3cc, 2 = 4a10aa60971401954717fc3c74d3d869, 3 = 50f8be54db2465be1db2a03a37b26d20, 4 = 0 tablas. Después: 1 igual (redes no cambia), 3 = cf531900f6be5fc187b73395a2340e2b, 4 = 4 tablas, 5 = las 6 RPC.
-- =====================================================================
select k, valor, esperado_antes, esperado_despues from (
  select 1 as o, '1 huella de redes (no cambia)' as k,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) as valor,
         '1ba192724c2fddcf321104700829f3cc' as esperado_antes, '1ba192724c2fddcf321104700829f3cc' as esperado_despues
  union all
  select 2, '2 huella de técnica (esquema tecnica y geoportal_tec_*)',
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))),
         '4a10aa60971401954717fc3c74d3d869', 'cambia (anótela)'
  union all
  select 3, '3 md5 de tecnica.f_autorizar_supervision', (select md5(pg_get_functiondef('tecnica.f_autorizar_supervision(text)'::regprocedure))), '50f8be54db2465be1db2a03a37b26d20', 'cf531900f6be5fc187b73395a2340e2b'
  union all
  select 4, '4 tablas de la PTAR', (select count(*)::text from pg_class where oid in (coalesce(to_regclass('tecnica.instalaciones'), 0), coalesce(to_regclass('tecnica.elementos_planta'), 0),
         coalesce(to_regclass('tecnica.elemento_alias_eventos'), 0), coalesce(to_regclass('tecnica.alcance_eventos'), 0))), '0', '4'
  union all
  select 5, '5 RPC geoportal_tec_ptar_*', (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname like 'geoportal\_tec\_ptar\_%'), '0', '6'
  union all
  select 6, '6 pg-safeupdate: funciones con DELETE/UPDATE sin WHERE', (select count(*)::text from redes.f_funciones_sin_where()), '0', '0'
) t order by o;
