-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · CORRECCIÓN «LA VÁLVULA QUE CERRÓ EL OPERADOR» · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Todas las filas deben decir OK. Nota: después de este paquete, la fila de la huella del conjunto de la verificación de «Cierre por aguas arriba» deja de valer.
-- =====================================================================
select k, v from (
  select 1 as o, '01 la RPC nueva: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname = 'geoportal_redes_cierres_registro' and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 1 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de la nueva y del conjunto de funciones de redes',
         case when (select count(*) from (values ('public.geoportal_redes_cierres_registro(text,text)', '97d6150367c8f751bea98e237522a8f7')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 1
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '63d917635b33e3696f28a3b0e579c002' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 no se tocó nada de lo publicado: la maniobra, los cortes vigentes del geovisor (siguen pidiendo el geovisor) y quién tiene el geovisor',
         case when (select count(*) from (values ('public.geoportal_redes_valvula_maniobra(text,text,text,text,text,text,text)', 'c17b23590b8af31d574f593aaeb8c781'), ('public.geoportal_redes_cortes_vigentes(text)', 'c09eadccc9399bb27b78dfb0ad14c8f8'), ('redes.f_geovisor_acceso(text)', '21a230858f6f70457275ed8d9919093e'), ('redes.f_geovisor_lectura(text)', '1e0e4e790361d8b366de64ed0506b50a'), ('redes.f_sim_autorizar(text)', 'a51058c0b84d12517137f8f0eded944f')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 5 then 'OK' else 'MAL' end
  union all select 6, 'INFO maniobras registradas · válvulas cerradas en este momento',
         (select count(*) from redes.valvula_maniobras) || ' · ' || (select count(*) from redes.f_cierres_vigentes())
) t order by o;
