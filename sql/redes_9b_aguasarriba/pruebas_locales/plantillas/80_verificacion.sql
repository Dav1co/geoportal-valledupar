-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). Todas las filas deben decir OK.
-- Nota: después de este paquete, la fila de la huella del conjunto de la verificación del Corte 14 deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 la RPC nueva: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname = 'geoportal_redes_simulacion_aguas_arriba' and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 1 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las 4 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las {{N_NUEVAS}} nuevas y del conjunto de funciones de redes',
         case when (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_AU}}' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 la simulación de siempre (redes.f_simular_cierre) no cambió, y están los 2 parámetros (criterio 1 = cota)',
         case when md5(pg_get_functiondef('redes.f_simular_cierre(bigint)'::regprocedure)) = '{{MD5_CIERRE}}'
               and (select count(*) from redes.parametros where clave in ('sim_aguas_arriba_criterio', 'sim_cota_minima_m') and estado = 'vigente') = 2 then 'OK' else 'MAL' end
  union all select 6, 'INFO criterio vigente (1 cota, 2 modelo) · desnivel mínimo (m)',
         (select valor::text from redes.parametros where clave = 'sim_aguas_arriba_criterio') || ' · ' || (select valor::text from redes.parametros where clave = 'sim_cota_minima_m')
  union all select 7, 'INFO tubos del flujo del modelo vigente · nodos del Plan con cota',
         (select count(*) from redes.flujo_modelo where carga_id = redes.f_ref_vigente('flujo_modelo')) || ' · ' || (select count(cota_m) from redes.pm_nodos where carga_id = redes.f_ref_vigente('pm_nodos'))
) t order by o;
