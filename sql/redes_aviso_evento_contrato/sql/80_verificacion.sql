-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Todas las filas deben decir OK. Nota: después de este paquete, la fila de la huella del conjunto de la verificación del Corte 15 deja de valer.
-- =====================================================================
select k, v from (
  select 1 as o, '01 la RPC nueva: security definer, search_path fijo, de solo lectura (STABLE), solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname = 'geoportal_redes_evento_contrato' and p.prosecdef and p.proconfig is not null and p.provolatile = 's'
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 1 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de la nueva y del conjunto de funciones de redes',
         case when (select count(*) from (values ('redes.f_eventos_del_contrato(text)', '8095ab6a65b1d983873d34d9fdfe5b95'), ('redes.f_evento_contrato_acceso(text)', '0dbfe115507497bb587be04f994d07bc'), ('public.geoportal_redes_evento_contrato(text,text)', 'f82b45906c62feca8b431020284e8bbf')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 3
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = 'b474fbbe3e0f7a3a7e6dbc04c53e02e7' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 no se tocó nada de lo publicado: los eventos abiertos, el conteo de contratos del Corte 15, la franja, las zonas vigentes y declarar',
         case when (select count(*) from (values ('redes.f_eventos_abiertos()', '2d265a26461ea19a01e9a81bb927b120'), ('redes.f_evento_contratos(geometry,boolean,boolean)', '8dafa57412c9b41aca0a0e3652f3bf2a'), ('redes.f_evento_franja(text,timestamp with time zone,text,timestamp with time zone)', 'fb9de8c4ada4a35de44889aea9f17b62'), ('public.geoportal_redes_eventos_vigentes(text)', '30d3b3306038af969a1e7e1b75e6f5ef'), ('public.geoportal_redes_evento_declarar(text,jsonb)', 'ddf3e36525c21605a4dbf36789082c92')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 5 then 'OK' else 'MAL' end
  union all select 6, '06 las 2 internas nuevas no las ejecuta nadie más que su dueño',
         case when (select count(*) from pg_proc p where p.oid in ('redes.f_eventos_del_contrato(text)'::regprocedure, 'redes.f_evento_contrato_acceso(text)'::regprocedure)
                     and p.prosecdef and p.proconfig is not null and not exists (select 1 from aclexplode(p.proacl) x where x.grantee <> p.proowner)) = 2 then 'OK' else 'MAL' end
  union all select 7, 'INFO eventos abiertos · contratos con amarre a la red',
         (select count(*) from redes.f_eventos_abiertos()) || ' · ' || (select count(*) from redes.contrato_tramo)
) t order by o;
