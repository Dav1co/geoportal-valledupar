-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 5a, la fila 05 de la verificación del 4b dice MAL a propósito (el conjunto de funciones cambió); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 tablas nuevas con RLS y reglas de solo inserción (ubicación y eventos de los puntos) y de no borrar (formularios de distribución)' as k,
         case when (select bool_and(relrowsecurity) from pg_class where oid in (to_regclass('tecnica.puntos_ubicacion'), to_regclass('tecnica.punto_eventos'), to_regclass('redes.formularios_distribucion')))
               and (select count(*) from pg_trigger where tgrelid in (to_regclass('tecnica.puntos_ubicacion'), to_regclass('tecnica.punto_eventos'), to_regclass('redes.formularios_distribucion')) and not tgisinternal) = 6
              then 'OK' else 'MAL' end as v
  union all select 2, '02 ni anon, ni authenticated, ni service_role leen las tablas ni la vista nuevas',
         case when not exists (select 1 from (values ('tecnica.puntos_ubicacion'), ('tecnica.punto_eventos'), ('redes.formularios_distribucion'), ('redes.v_punto_ubicacion_vigente')) t(n),
                                              (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                                where has_table_privilege(r.rol, t.n, 'select') or has_table_privilege(r.rol, t.n, 'insert')) then 'OK' else 'MAL' end
  union all select 3, '03 las 51 RPC geoportal_redes_* (50 + 1 del 5a): security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 51 then 'OK' else 'MAL' end
  union all select 4, '04 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 5, '05 huellas md5 de la RPC nueva, de las {{N_CAMBIADAS}} reemplazadas y del conjunto de funciones de redes del 5a',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) = 1
               and (select count(*) from (values {{CAMBIADAS_5A}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_CAMBIADAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_CORTE_5A}}' then 'OK' else 'MAL' end
  union all select 6, '06 las 4 funciones de permisos siguen con su huella del 4a',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{VIVAS_4A}})) = 4 then 'OK' else 'MAL' end
  union all select 7, '07 las vistas v_dano y v_epicrisis no cambiaron',
         case when md5(pg_get_viewdef('redes.v_dano'::regclass, true)) = '{{MD5_V_DANO}}' and md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) = '{{MD5_V_EPICRISIS}}' then 'OK' else 'MAL' end
  union all select 8, '08 tecnica.puntos conserva sus candados (no borrar, no vaciar) y ningún punto de muestreo quedó sin su evento al cambiar «activo»',
         case when (select count(*) from pg_trigger where tgrelid = 'tecnica.puntos'::regclass and tgname in ('t_no_borrar', 't_no_vaciar') and not tgisinternal) = 2
               and not exists (select 1 from tecnica.puntos p where p.tipo = 'muestreo' and p.activo is distinct from coalesce((select e.tipo <> 'desactivar' from tecnica.punto_eventos e
                                 where e.punto_id = p.id order by e.id desc limit 1), p.activo)) then 'OK' else 'MAL' end
  union all select 9, '09 la capa MUE existe y se carga por archivo; el tope de días atrás del supervisor existe (§28.1)',
         case when exists (select 1 from redes.capas where codigo = 'muestreo' and fuente = 'carga' and activa)
               and exists (select 1 from redes.parametros where clave = 'itv_dias_atras_max_supervisor' and valor between 1 and 90) then 'OK' else 'MAL' end
  union all select 10, 'INFO puntos de muestreo activos · con ubicación vigente (verificada · aproximada)',
         (select count(*) from tecnica.puntos where tipo = 'muestreo' and activo)::text || ' · ' || (select count(*) from redes.v_punto_ubicacion_vigente)::text || ' ('
           || (select count(*) filter (where exactitud = 'verificada') || ' · ' || count(*) filter (where exactitud = 'aproximada') from redes.v_punto_ubicacion_vigente) || ')'
  union all select 11, 'INFO cargas de la capa de muestreo publicadas', (select count(*)::text from redes.v_cargas_estado where capa_codigo = 'muestreo' and estado = 'publicada')
  union all select 12, 'INFO formularios de distribución asignados por el supervisor de distribución desde el 5a',
         (select count(*)::text from public.geoportal_auditoria where accion in ('redes_asignar_formulario', 'redes_quitar_formulario'))
) t order by o;
