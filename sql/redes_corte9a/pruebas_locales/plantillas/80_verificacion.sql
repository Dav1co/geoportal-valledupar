-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas). Vale antes y después de la carga del Plan Maestro:
-- la fila INFO dice cuánto hay cargado (después de la carga, la verificación propia de la carga es carga_pm/generado/verificacion_carga_pm.sql).
-- Nota: después del 9a, la fila de huellas de la verificación del 7a deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 10 tablas de referencia existen, con RLS, sin privilegios para la API y de solo inserción' as k,
         case when (select count(*) from pg_class c where c.relnamespace = 'redes'::regnamespace and c.relkind = 'r' and c.relrowsecurity
                     and c.relname in ('ref_cargas', 'ref_carga_eventos', 'pm_nodos', 'pm_tramos', 'pm_valvulas', 'pm_presion_hora', 'pm_alc_conductos', 'pm_alc_pozos', 'ref_elementos', 'pm_campana_lecturas')
                     and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')
                     and (select count(*) from pg_trigger t where t.tgrelid = c.oid and t.tgname in ('t_solo_agregar', 't_solo_agregar_trunc')) = 2) = 10 then 'OK' else 'MAL' end as v
  union all select 2, '02 las 6 RPC nuevas y las 5 RPC reemplazadas: security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_geovisor_mvt_ref', 'geoportal_redes_referencia', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_nodo_clasificar',
                                       'geoportal_redes_por_verificar', 'geoportal_redes_activo_verificar', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_danos',
                                       'geoportal_redes_intervenciones', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_nodos_por_clasificar')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 11 then 'OK' else 'MAL' end
  union all select 3, '03 ninguna función interna de redes la ejecuta la API (incluidas las 7 nuevas), ni las vistas nuevas',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')))
               and not has_table_privilege('service_role', 'redes.v_pm_por_verificar', 'select') and not has_table_privilege('service_role', 'redes.v_ref_carga_vigente', 'select') then 'OK' else 'MAL' end
  union all select 4, '04 huellas md5 de las {{N_CAMBIADAS}} reemplazadas, de las {{N_NUEVAS}} nuevas, de la vista de nodos y del conjunto de funciones de redes del 9a',
         case when (select count(*) from (values {{CAMBIADAS_9A}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_CAMBIADAS}}
               and (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}}
               and md5(pg_get_viewdef('redes.v_nodo_vigente'::regclass)) = '{{MD5_VISTA_NODO_9A}}'
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_9A}}' then 'OK' else 'MAL' end
  union all select 5, '05 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 6, '06 las RPC de lectura del 9a solo leen (STABLE): teselas, tarjetas, ficha preliminar, bandejas y la ficha',
         case when (select count(*) from pg_proc p where p.provolatile = 's' and ((p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_geovisor_mvt_ref', 'geoportal_redes_referencia', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_por_verificar',
                                       'geoportal_redes_nodos_por_clasificar', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_danos', 'geoportal_redes_intervenciones'))
                     or (p.pronamespace = 'redes'::regnamespace and p.proname in ('f_ficha', 'f_sector_de', 'f_ficha_referencia', 'f_nodo_modelo')))) = 12 then 'OK' else 'MAL' end
  union all select 7, '07 el campo oficial «efecto» de las válvulas no lo toca nada del 9a: ninguna función nueva escribe en activo_versiones',
         case when not exists (select 1 from pg_proc p where p.oid in (select to_regprocedure(c.f) from (values {{NUEVAS}}) c(f, m))
                                and p.prosrc ~* '(insert\s+into|update)\s+redes\.activo_versiones') then 'OK' else 'MAL' end
  union all select 8, '08 catálogo del geovisor: 5 capas de referencia activas (4 solo de supervisores), sectores encendidos al abrir para distribución y los 4 umbrales de presión en su rango',
         case when (select count(*) from redes.geovisor_capas where fuente = 'referencia' and activa and codigo in ('plan_valvulas', 'pluvial', 'pluvial_2043', 'presion_modelo', 'campana_2014')) = 5
               and (select count(*) from redes.geovisor_capas where fuente = 'referencia' and solo_completo) = 4
               and (select count(*) from redes.capas_por_perfil where capa = 'sectores' and encendida and perfil in ('supervisor_distribucion', 'operador_distribucion')) = 2
               and not exists (select 1 from redes.capas_por_perfil c join redes.geovisor_capas g on g.codigo = c.capa where g.fuente = 'referencia' and c.encendida and c.actualizado_por like 'migracion@%')
               and (select count(*) from redes.parametros where clave like 'presion\_%\_mca' and valor between minimo and maximo) = 4 then 'OK' else 'MAL' end
  union all select 9, '09 la vista de nodos conserva sus 10 columnas y los nodos vigentes siguen siendo uno por llave',
         case when (select count(*) from information_schema.columns where table_schema = 'redes' and table_name = 'v_nodo_vigente') = 10
               and not exists (select 1 from redes.v_nodo_vigente group by sistema, llave_modelo having count(*) > 1) then 'OK' else 'MAL' end
  union all select 10, 'INFO cargas de referencia vigentes · nodos del modelo · tramos · válvulas · presiones por hora · conductos y pozos de alcantarillado · elementos de referencia · lecturas de la campaña · sectores (SEC) vigentes · por verificar hoy · nodos por clasificar',
         (select count(*) from redes.v_ref_carga_vigente) || ' · ' || (select count(*) from redes.pm_nodos) || ' · ' || (select count(*) from redes.pm_tramos) || ' · ' || (select count(*) from redes.pm_valvulas)
         || ' · ' || (select count(*) from redes.pm_presion_hora) || ' · ' || (select count(*) from redes.pm_alc_conductos) || ' y ' || (select count(*) from redes.pm_alc_pozos)
         || ' · ' || (select count(*) from redes.ref_elementos) || ' · ' || (select count(*) from redes.pm_campana_lecturas)
         || ' · ' || (select count(*) from redes.activo_vigente_mat where prefijo = 'SEC' and not retirado)
         || ' · ' || (select count(*) from redes.v_activo_estado where por_verificar) || ' · ' || (select count(*) from redes.v_nodo_vigente where clase_nodo = 'por_clasificar')
) t order by o;
