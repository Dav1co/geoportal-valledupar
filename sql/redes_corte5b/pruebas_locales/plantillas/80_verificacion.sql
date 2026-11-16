-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 5b, la fila 05 de la verificación del 5a dice MAL a propósito (el conjunto de funciones cambió: f_candidatos_muestreo); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 tablas nuevas con RLS y reglas de solo inserción (propuestas y revisiones de ubicación)' as k,
         case when (select bool_and(relrowsecurity) from pg_class where oid in (to_regclass('tecnica.punto_ubicacion_propuestas'), to_regclass('tecnica.punto_ubicacion_revisiones')))
               and (select count(*) from pg_trigger where tgrelid in (to_regclass('tecnica.punto_ubicacion_propuestas'), to_regclass('tecnica.punto_ubicacion_revisiones')) and not tgisinternal) = 4
              then 'OK' else 'MAL' end as v
  union all select 2, '02 ni anon, ni authenticated, ni service_role leen las tablas ni la vista nuevas',
         case when not exists (select 1 from (values ('tecnica.punto_ubicacion_propuestas'), ('tecnica.punto_ubicacion_revisiones'), ('tecnica.v_punto_propuestas')) t(n),
                                              (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                                where has_table_privilege(r.rol, t.n, 'select') or has_table_privilege(r.rol, t.n, 'insert')) then 'OK' else 'MAL' end
  union all select 3, '03 las 4 RPC geoportal_tec_punto*: security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_punto%' and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 4 then 'OK' else 'MAL' end
  union all select 4, '04 ninguna función interna de redes la ejecuta la API (incluida la reemplazada)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 5, '05 huellas md5 de las 4 RPC nuevas, de la reemplazada y del conjunto de funciones de redes del 5b',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) = 4
               and (select count(*) from (values {{CAMBIADAS_5B}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_CAMBIADAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_CORTE_5B}}' then 'OK' else 'MAL' end
  union all select 6, '06 los 2 parámetros nuevos existen con su rango (precisión del GPS y distancia del aviso)',
         case when (select count(*) from redes.parametros where clave in ('mue_gps_precision_max_m', 'mue_gps_distancia_aviso_m') and valor between minimo and maximo) = 2 then 'OK' else 'MAL' end
  union all select 7, '07 cada aprobada tiene su ubicación verificada del GPS del operador; ningún punto con dos propuestas pendientes',
         case when not exists (select 1 from tecnica.punto_ubicacion_revisiones r left join tecnica.puntos_ubicacion u on u.id = r.ubicacion_id
                                where r.decision = 'aprobar' and (u.id is null or u.exactitud <> 'verificada' or u.fuente <> 'gps_operador'))
               and not exists (select punto_id from tecnica.v_punto_propuestas where estado = 'pendiente' group by punto_id having count(*) > 1) then 'OK' else 'MAL' end
  union all select 8, '08 tecnica.puntos y tecnica.puntos_ubicacion conservan sus candados',
         case when (select count(*) from pg_trigger where tgrelid = 'tecnica.puntos'::regclass and tgname in ('t_no_borrar', 't_no_vaciar') and not tgisinternal) = 2
               and (select count(*) from pg_trigger where tgrelid = 'tecnica.puntos_ubicacion'::regclass and tgname in ('t_solo_agregar', 't_solo_agregar_trunc') and not tgisinternal) = 2 then 'OK' else 'MAL' end
  union all select 9, 'INFO ubicaciones propuestas: pendientes · aprobadas · rechazadas',
         (select count(*) filter (where estado = 'pendiente') || ' · ' || count(*) filter (where estado = 'aprobada') || ' · ' || count(*) filter (where estado = 'rechazada') from tecnica.v_punto_propuestas)
  union all select 10, 'INFO puntos de muestreo activos con ubicación verificada · aproximada · sin ubicación',
         (select count(*) filter (where u.exactitud = 'verificada') || ' · ' || count(*) filter (where u.exactitud = 'aproximada') || ' · ' || count(*) filter (where u.punto_id is null)
            from tecnica.puntos p left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id where p.tipo = 'muestreo' and p.activo)
) t order by o;
