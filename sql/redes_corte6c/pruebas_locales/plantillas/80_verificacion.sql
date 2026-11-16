-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 6c, las filas 01, 05, 06 y 10 de la verificación del 6b dejan de valer (la copia derivada ya no existe y el conjunto cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 la copia derivada ya no existe (2 tablas y 2 funciones) y ninguna función de redes la nombra' as k,
         case when to_regclass('redes.contratos_capa') is null and to_regclass('redes.contratos_capa_estado') is null
               and to_regprocedure('redes.f_refrescar_contratos_capa()') is null and to_regprocedure('redes.f_contratos_capa_al_dia()') is null
               and not exists (select 1 from pg_proc p where (p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
                                and p.prosrc ~ 'contratos_capa') then 'OK' else 'MAL' end as v
  union all select 2, '02 las 3 RPC reemplazadas: security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 3 then 'OK' else 'MAL' end
  union all select 3, '03 ninguna función interna de redes la ejecuta la API (incluidas las 2 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 4, '04 huellas md5 de las 3 reemplazadas, de las 2 nuevas y del conjunto de funciones de redes del 6c',
         case when (select count(*) from (values {{CAMBIADAS_6C}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_CAMBIADAS}}
               and (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_CORTE_6C}}' then 'OK' else 'MAL' end
  union all select 5, '05 pg-safeupdate: ninguna función de redes, tecnica ni public.geoportal_redes_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 6, '06 la configuración del geovisor y la tesela de contratos solo leen (STABLE): ninguna petición rehace nada',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt_contratos')
                     and p.provolatile = 's') = 2 then 'OK' else 'MAL' end
  union all select 7, '07 los 4 índices de Comercial que usa la tesela de contratos siguen ahí',
         case when exists (select 1 from pg_index x join pg_class i on i.oid = x.indexrelid join pg_am am on am.oid = i.relam
                            where x.indrelid = 'public.catastro_valledupar'::regclass and am.amname = 'gist' and pg_get_indexdef(i.oid) ~ '\(geom\)')
               and exists (select 1 from pg_index x where x.indrelid = 'public.catastro_valledupar'::regclass and x.indisvalid and x.indpred is null
                            and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(cod_usuario( text_pattern_ops)?[,)]')
               and exists (select 1 from pg_index x where x.indrelid = 'public.cartera_suscripcion'::regclass and x.indisvalid and x.indpred is null
                            and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(contrato[,)]')
               and exists (select 1 from pg_index x where x.indrelid = 'bi_interno.ficha_contrato'::regclass and x.indisvalid
                            and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(contrato[,)]') then 'OK' else 'MAL' end
  union all select 8, '08 el catálogo del geovisor conserva la capa de contratos (activa, solo supervisores) y el zoom de contratos está en su rango',
         case when (select fuente || '|' || estado || '|' || solo_completo from redes.geovisor_capas where codigo = 'contratos') = 'contratos|activa|true'
               and (select count(*) from redes.parametros where clave = 'geovisor_zoom_contratos' and valor between minimo and maximo) = 1 then 'OK' else 'MAL' end
  union all select 9, '09 cada lectura de la tarjeta del contrato sigue en la auditoría sin el nombre ni la dirección',
         case when not exists (select 1 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta' and (detalle ? 'nombre' or detalle ? 'direccion_texto' or detalle::text ~* 'suscriptor ')) then 'OK' else 'MAL' end
  union all select 10, 'INFO predios del catastro con contrato y punto · contratos distintos · lecturas de tarjetas · topes de service_role (statement_timeout) y authenticator (lock_timeout)',
         (select count(*) || ' · ' || count(distinct cod_usuario) from public.catastro_valledupar where cod_usuario ~ '^[0-9]{1,12}$' and cod_usuario not in ('0', '99999999') and geom is not null) || ' · ' ||
         (select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta') || ' · ' ||
         coalesce((select substring(c from 'statement_timeout=(.*)') from pg_roles r, unnest(r.rolconfig) c where r.rolname = 'service_role' and c like 'statement_timeout=%'), 'sin tope') || ' y ' ||
         coalesce((select substring(c from 'lock_timeout=(.*)') from pg_roles r, unnest(r.rolconfig) c where r.rolname = 'authenticator' and c like 'lock_timeout=%'), 'sin tope')
) t order by o;
