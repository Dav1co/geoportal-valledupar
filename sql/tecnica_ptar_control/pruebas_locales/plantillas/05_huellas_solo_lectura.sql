-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 · 05 — HUELLAS (SOLO LECTURA; una consulta, apta para el editor SQL web). Correr ANTES y DESPUÉS de la migración.
-- =====================================================================
select k, valor, esperado_antes, esperado_despues from (
  select 1 as o, '1 huella de redes (no cambia)' as k,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) as valor,
         '{{MD5_REDES}}' as esperado_antes, '{{MD5_REDES}}' as esperado_despues
  union all
  select 2, '2 huella de técnica (anótela)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))), 'la de después de PTAR-1', 'cambia'
  union all select 3, '3 md5 de tecnica.f_formularios', (select md5(pg_get_functiondef('tecnica.f_formularios()'::regprocedure))), '{{MD5_FORMULARIOS}}', '{{MD5_FORMULARIOS_DESPUES}}'
  union all select 4, '4 md5 de tecnica.f_autorizar_captura', (select md5(pg_get_functiondef('tecnica.f_autorizar_captura(text,text)'::regprocedure))), '{{MD5_CAPTURA}}', '{{MD5_CAPTURA_DESPUES}}'
  union all select 5, '5 puntos PTAR-* · variables ar_*', (select count(*) from tecnica.puntos where codigo like 'PTAR-%') || ' · ' || (select count(*) from tecnica.variables where codigo like 'ar\_%'), '0 · 0', '4 · 9'
  union all select 6, '6 pg-safeupdate: funciones con DELETE/UPDATE sin WHERE', (select count(*)::text from redes.f_funciones_sin_where()), '0', '0'
) t order by o;
