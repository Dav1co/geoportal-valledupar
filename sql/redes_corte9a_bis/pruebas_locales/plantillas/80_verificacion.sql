-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 9a-bis, la fila 04 de la verificación del 9a deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 2 RPC nuevas y las reemplazadas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_sector_en', 'geoportal_redes_nodos_clasificar_grupo', 'geoportal_redes_tramo_nodos', 'geoportal_redes_nodo_crear_activo',
                                       'geoportal_redes_nodos_por_clasificar', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_nodo_clasificar', 'geoportal_redes_danos',
                                       'geoportal_redes_intervenciones', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_referencia', 'geoportal_redes_mi_perfil',
                                       'geoportal_redes_crear_dano', 'geoportal_redes_reporte_convertir')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 14 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las 5 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las {{N_CAMBIADAS}} reemplazadas, de las {{N_NUEVAS}} nuevas y del conjunto de funciones de redes del 9a-bis',
         case when (select count(*) from (values {{CAMBIADAS_BIS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_CAMBIADAS}}
               and (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_BIS}}' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 la ficha y el minimapa ya no leen las vistas enteras de nodos y tramos (ninguna función de redes busca en ellas por una columna que no es su llave)',
         case when not exists (select 1 from pg_proc p where (p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
                                and (p.prosrc ~ 'v_tramo_nodos_vigente' or p.prosrc ~ 'v_nodo_visible n where n\.(nodo_id|activo_id) =' or p.prosrc ~ 'v_nodo_visible where nodo_id =')) then 'OK' else 'MAL' end
  union all select 6, '06 «sector_plan» ya no sale en ninguna función: el sector hidráulico (por la ubicación) es el oficial',
         case when not exists (select 1 from pg_proc p where (p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
                                and p.prosrc ~ '''sector_plan''') then 'OK' else 'MAL' end
  union all select 7, '07 la capa de sectores dice que son los sectores con que se opera (nota nueva)',
         case when (select nombre || '|' || nota from redes.geovisor_capas where codigo = 'sectores') like 'Sectores hidráulicos|7 sectores y 29 subsectores con que se opera%' then 'OK' else 'MAL' end
  union all select 8, 'INFO sectores vigentes (SEC): en operación · proyectados (después de carga_sectores/sectores_oficiales.sql: 36 · 0) · nodos por clasificar · clasificados sin activo',
         (select count(*) filter (where estado_codigo = 'en_operacion') || ' · ' || count(*) filter (where estado_codigo = 'proyectado') from redes.activo_vigente_mat where prefijo = 'SEC' and not retirado)
         || ' · ' || (select count(*) from redes.v_nodo_vigente where clase_nodo = 'por_clasificar')
         || ' · ' || (select count(*) from redes.v_nodo_vigente where clase_nodo in ('nodo_calculo', 'propuesta_plan'))
) t order by o;
