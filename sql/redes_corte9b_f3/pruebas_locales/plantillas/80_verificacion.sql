-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). Todas las filas deben decir OK.
-- Nota: después de la Fase 3, la fila 03 de la verificación de la Fase 2 deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 3 RPC nuevas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_geovisor_mvt_flujo', 'geoportal_redes_flujo_modelo', 'geoportal_redes_flujo_tramo') and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 3 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las {{N_NUEVAS}} nuevas y del conjunto de funciones de redes de la Fase 3',
         case when (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_F3}}' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 las 2 tablas del flujo: nadie de la API las lee ni las escribe; son de solo agregar',
         case when (select count(*) from pg_class c where c.relnamespace = 'redes'::regnamespace and c.relname in ('flujo_modelo', 'flujo_modelo_horas') and c.relrowsecurity
                     and not exists (select 1 from aclexplode(c.relacl) x where x.grantee in (0, (select oid from pg_roles where rolname = 'anon'),
                                    (select oid from pg_roles where rolname = 'authenticated'), (select oid from pg_roles where rolname = 'service_role')))) = 2
               and (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'redes'::regnamespace
                     and c.relname in ('flujo_modelo', 'flujo_modelo_horas') and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 4 then 'OK' else 'MAL' end
  union all select 6, '06 la capa «Flujo del agua (modelo)» está en la lista, en espera y solo para supervisores; tecnica.f_avisos no cambió',
         case when (select fuente = 'preparada' and estado = 'espera_dato' and solo_completo and activa from redes.geovisor_capas where codigo = 'flujo_modelo')
               and position('flujo' in lower(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure))) = 0 then 'OK' else 'MAL' end
  union all select 7, 'INFO flujo del modelo vigente: archivo · tubos · con tramo de la red',
         coalesce((select c.archivo || ' · ' || c.filas || ' · ' || (select count(f.activo_id) from redes.flujo_modelo f where f.carga_id = c.id)
                     from redes.v_ref_carga_vigente c where c.conjunto = 'flujo_modelo'), 'sin cargar todavía (paquete carga_flujo)')
) t order by o;
