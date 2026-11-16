-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 6a, la fila 05 de la verificación del 5c dice MAL a propósito (el conjunto de funciones cambió); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 tablas nuevas con RLS y sus candados (catálogo y capas por perfil no se borran; los eventos son de solo inserción)' as k,
         case when (select bool_and(relrowsecurity) from pg_class where oid in (to_regclass('redes.geovisor_capas'), to_regclass('redes.capas_por_perfil'), to_regclass('redes.capas_por_perfil_eventos')))
               and (select count(*) from pg_trigger where tgrelid in (to_regclass('redes.geovisor_capas'), to_regclass('redes.capas_por_perfil'), to_regclass('redes.capas_por_perfil_eventos')) and not tgisinternal) = 6
              then 'OK' else 'MAL' end as v
  union all select 2, '02 ni anon, ni authenticated, ni service_role leen ni escriben las tablas nuevas',
         case when not exists (select 1 from (values ('redes.geovisor_capas'), ('redes.capas_por_perfil'), ('redes.capas_por_perfil_eventos')) t(n),
                                              (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                                where has_table_privilege(r.rol, t.n, 'select') or has_table_privilege(r.rol, t.n, 'insert') or has_table_privilege(r.rol, t.n, 'update')) then 'OK' else 'MAL' end
  union all select 3, '03 las 4 RPC nuevas y las 10 reemplazadas: security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor_capa', 'geoportal_redes_geovisor_capas_fijar',
                                       'geoportal_redes_carga_lote', 'geoportal_redes_carga_resumen', 'geoportal_redes_carga_publicar', 'geoportal_redes_carga_anular',
                                       'geoportal_redes_carga_muestra', 'geoportal_redes_carga_revertir', 'geoportal_redes_cargue_iniciar', 'geoportal_redes_carga_devolver_campo',
                                       'geoportal_redes_cargue_capas', 'geoportal_redes_mi_perfil')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 14 then 'OK' else 'MAL' end
  union all select 4, '04 ninguna función interna de redes la ejecuta la API (incluidas las 4 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 5, '05 huellas md5 de las 4 RPC nuevas, de las 10 reemplazadas y del conjunto de funciones de redes del 6a',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) = {{N_RPC}}
               and (select count(*) from (values {{CAMBIADAS_6A}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_CAMBIADAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_CORTE_6A}}' then 'OK' else 'MAL' end
  union all select 6, '06 quién carga: el supervisor solo las capas que no son del modelo (acueducto, conductos, pozos y descargas, solo el administrador)',
         case when (select count(*) from redes.capas where carga_supervisor and codigo in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas')) = 0
               and (select count(*) from redes.capas where carga_supervisor and codigo in ('muestreo', 'acometidas', 'captaciones', 'aduccion', 'desarenadores', 'bombeo_ap',
                        'sumideros', 'interceptores', 'bombeo_ar', 'ptar', 'sectores', 'sensores', 'scada')) = 13 then 'OK' else 'MAL' end
  union all select 7, '07 catálogo del geovisor: las capas de tesela tienen prefijos que existen; ninguna preparada está encendida al abrir',
         case when not exists (select 1 from redes.geovisor_capas g cross join unnest(g.prefijos) p where not exists (select 1 from redes.tipos_activo t where t.prefijo = p))
               and not exists (select 1 from redes.capas_por_perfil c join redes.geovisor_capas g on g.codigo = c.capa where c.encendida and g.fuente = 'preparada')
               and not exists (select 1 from redes.capas_por_perfil c join redes.geovisor_capas g on g.codigo = c.capa where c.encendida and c.perfil = 'operador_distribucion' and g.solo_completo)
               and (select count(*) from redes.geovisor_capas) >= 19 then 'OK' else 'MAL' end
  union all select 8, '08 los 8 parámetros del geovisor existen dentro de su rango',
         case when (select count(*) from redes.parametros where clave like 'geovisor\_%' and valor between minimo and maximo) = 8 then 'OK' else 'MAL' end
  union all select 9, '09 las RPC del Cargue de la pantalla ya no piden «solo el administrador» (la de psql del 1a sí, como antes)',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_carga_lote', 'geoportal_redes_carga_resumen', 'geoportal_redes_carga_publicar', 'geoportal_redes_carga_anular',
                                       'geoportal_redes_carga_muestra', 'geoportal_redes_carga_revertir', 'geoportal_redes_cargue_iniciar', 'geoportal_redes_carga_devolver_campo')
                     and p.prosrc like '%f_autorizar_carga%' and p.prosrc not like '%f_autorizar_admin%') = 8
               and (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'geoportal_redes_carga_iniciar') like '%f_autorizar_admin%' then 'OK' else 'MAL' end
  union all select 10, 'INFO capas del geovisor · encendidas por perfil (distribución · planta · operador) · cambios de las capas por omisión',
         (select count(*) from redes.geovisor_capas where activa) || ' · ' ||
         (select count(*) from redes.capas_por_perfil where encendida and perfil = 'supervisor_distribucion') || ' · ' ||
         (select count(*) from redes.capas_por_perfil where encendida and perfil = 'supervisor_planta') || ' · ' ||
         (select count(*) from redes.capas_por_perfil where encendida and perfil = 'operador_distribucion') || ' · ' ||
         (select count(*) from redes.capas_por_perfil_eventos)
) t order by o;
