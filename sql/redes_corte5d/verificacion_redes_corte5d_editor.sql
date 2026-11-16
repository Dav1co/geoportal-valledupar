-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 5d, la fila 03 de la verificación del 9a-bis deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 la RPC nueva y las reemplazadas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_l116_vincular_dano', 'geoportal_redes_geovisor_capa', 'geoportal_redes_cargue_capas')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 3 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las 6 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las 6 reemplazadas, de las 7 nuevas y del conjunto de funciones de redes del 5d',
         case when (select count(*) from (values ('redes.f_lote(bigint,jsonb)', 'c6eea76f5124e903f3d79308f5747580'), ('redes.f_resumen(bigint)', 'dc256f8a36acb8ec4a1abda19179e321'), ('redes.f_publicar(bigint,text,text)', 'f204bc42b727c1ab284220dee2c6c9c0'), ('redes.f_revertir(text,text,text)', 'dbe18e81f4a9605f7659258f6138a8e6'), ('public.geoportal_redes_cargue_capas(text)', 'fcd4f1cb91c9cef0cf2d00c1f4d4fe32'), ('public.geoportal_redes_geovisor_capa(text,text,date,date)', 'a79ba32d0d1c8f6c243928e370d217d3')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 6
               and (select count(*) from (values ('redes.f_l116_atributos(jsonb)', '5ace157540bfed79f16a76f19c81bfcc'), ('redes.f_l116_fecha(text)', '256e9e6eebbd5d5cca1c51bedf2d4acd'), ('redes.f_l116_candidatos(bigint)', 'db66e19131c4f51b3988ddd23a1aae47'), ('redes.f_resumen_l116(bigint)', '2ad145d79e92d1e33acc0e90592b3ed7'), ('redes.f_publicar_l116(bigint,text,text)', '1d70c1fe36186cf498504898e5098b64'), ('redes.f_revertir_l116(text,text)', '976be08e317cbe396aca0b92552fe80f'), ('public.geoportal_redes_l116_vincular_dano(text,bigint,text,text,text)', 'a28ba4108c8ad8fd2d2e052b0d353dbb')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 7
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '5fd6d00efdaa1a798e2628a2cde23c61' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 las 6 tablas de la 116: nadie de la API las lee ni las escribe; reportes, eventos, daños y revisiones son de solo agregar (con su disparador)',
         case when (select count(*) from pg_class c where c.oid in (to_regclass('redes.l116_reportes'), to_regclass('redes.l116_eventos'), to_regclass('redes.l116_vigente'), to_regclass('redes.l116_danos'),
                                                       to_regclass('redes.l116_revisiones'), to_regclass('redes.l116_revision_filas'))
                     and not exists (select 1 from aclexplode(c.relacl) x where x.grantee in (0, (select oid from pg_roles where rolname = 'anon'), (select oid from pg_roles where rolname = 'authenticated'),
                                                                                              (select oid from pg_roles where rolname = 'service_role')))) = 6
               and (select count(*) from pg_trigger t where t.tgrelid in ('redes.l116_reportes'::regclass, 'redes.l116_eventos'::regclass, 'redes.l116_danos'::regclass, 'redes.l116_revisiones'::regclass,
                                                                    'redes.l116_revision_filas'::regclass)
                     and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 10 then 'OK' else 'MAL' end
  union all select 6, '06 ninguna tabla de la 116 tiene columna de nombre, teléfono, dirección ni barrio (no se cargan), y la ubicación es solo «contrato» o «sin_ubicar»',
         case when not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name like 'l116\_%' and column_name ~ 'nombre|telefono|celular|direccion|barrio')
               and not exists (select 1 from redes.l116_eventos where metodo not in ('contrato', 'sin_ubicar')) then 'OK' else 'MAL' end
  union all select 7, '07 la capa «linea_116» del Cargue (CSV o Excel, llave «reporte», la carga el supervisor) y la «pqr_116» del geovisor, por fecha y solo para supervisores',
         case when exists (select 1 from redes.capas where codigo = 'linea_116' and fuente = 'carga' and activa and carga_supervisor and columna_llave = 'reporte' and formatos = '{csv,xlsx}')
               and exists (select 1 from redes.geovisor_capas where codigo = 'pqr_116' and fuente = 'geojson' and estado = 'activa' and por_fecha and solo_completo) then 'OK' else 'MAL' end
  union all select 8, '08 los formularios compartidos con Comercial están en los formularios de distribución (punto 8, pedido del Code A)',
         case when (select count(*) from redes.formularios_distribucion where clave in ('anomalia_compartida', 'revision_compartida') and activo) = 2 then 'OK' else 'MAL' end
  union all select 9, 'INFO reportes de la 116: total · registrados · atendidos · ubicados por contrato · sin ubicar · ocultos · cargas publicadas',
         (select count(*) || ' · ' || count(*) filter (where estado = 'registrado') || ' · ' || count(*) filter (where estado = 'atendido') || ' · '
                 || count(*) filter (where metodo = 'contrato') || ' · '
                 || count(*) filter (where metodo = 'sin_ubicar') || ' · ' || count(*) filter (where oculto) from redes.l116_vigente)
         || ' · ' || (select count(*) from redes.v_cargas_estado where capa_codigo = 'linea_116' and estado = 'publicada')
) t order by o;
