-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 4b, la fila 06 de la verificación del 4a dice MAL a propósito (el conjunto de funciones cambió); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 tablas nuevas con RLS y reglas de solo inserción (ficha del personal) y de no borrar (cuadrillas)' as k,
         case when (select relrowsecurity from pg_class where oid = to_regclass('tecnica.personal_ficha_eventos')) and (select relrowsecurity from pg_class where oid = to_regclass('redes.cuadrillas'))
               and (select count(*) from pg_trigger where tgrelid = to_regclass('tecnica.personal_ficha_eventos') and not tgisinternal) = 2
               and (select count(*) from pg_trigger where tgrelid = to_regclass('redes.cuadrillas') and not tgisinternal) = 2 then 'OK' else 'MAL' end as v
  union all select 2, '02 ni anon, ni authenticated, ni service_role leen las tablas ni la vista nuevas',
         case when not exists (select 1 from (values ('tecnica.personal_ficha_eventos'), ('redes.cuadrillas'), ('redes.v_personal_ficha')) t(n), (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                                where has_table_privilege(r.rol, t.n, 'select') or has_table_privilege(r.rol, t.n, 'insert')) then 'OK' else 'MAL' end
  union all select 3, '03 las 50 RPC geoportal_redes_* (38 + 12 del 4b): security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 50 then 'OK' else 'MAL' end
  union all select 4, '04 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 5, '05 huellas md5 de las 12 RPC nuevas y del conjunto de funciones de redes del 4b',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) = 12
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_CORTE_4B}}' then 'OK' else 'MAL' end
  union all select 6, '06 ninguna función de redes del 4a cambió (las {{N_FUNCIONES_4A}}, con su huella)',
         case when (select count(*) from pg_proc p where (p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))) in ({{FUNCIONES_4A}})) = {{N_FUNCIONES_4A}} then 'OK' else 'MAL' end
  union all select 7, '07 las 4 funciones de permisos siguen con su huella del 4a (el 4b no las toca)',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{VIVAS_4A}})) = 4 then 'OK' else 'MAL' end
  union all select 8, '08 las vistas v_dano y v_epicrisis no cambiaron',
         case when md5(pg_get_viewdef('redes.v_dano'::regclass, true)) = '{{MD5_V_DANO}}' and md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) = '{{MD5_V_EPICRISIS}}' then 'OK' else 'MAL' end
  union all select 9, '09 las fotos mínimas del daño y de la intervención siguen en 1 o más (§25.8)',
         case when (select min(valor) from redes.parametros where clave in ('min_fotos_dano', 'min_fotos_itv')) >= 1 then 'OK' else 'MAL' end
  union all select 10, 'INFO personas con área (planta · distribución · las dos)', (select count(*) filter (where area = 'planta') || ' · ' || count(*) filter (where area = 'distribucion') || ' · '
                                                                                  || count(*) filter (where area = 'ambas') from redes.v_personal_ficha)
  union all select 11, 'INFO operadores con el geovisor activado', (select count(*)::text from redes.v_personal_ficha where geovisor)
  union all select 12, 'INFO cuadrillas activas', (select count(*)::text from redes.cuadrillas where activa)
  union all select 13, 'INFO cambios de parámetros desde el 4b', (select count(*)::text from redes.parametro_eventos
                                                                     where creado_en > (select max(creado_en) from public.geoportal_auditoria where accion = 'migracion_redes_corte4b'))
  union all select 14, 'INFO nodos por clasificar', (select count(*)::text from redes.v_nodo_vigente where clase_nodo = 'por_clasificar')
) t order by o;
