-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). Todas las filas deben decir OK.
-- Nota: después de la Fase 2, la fila 03 de la verificación del 9b (1a + 1b) deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 5 RPC nuevas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_alertas_presion', 'geoportal_redes_sensibles', 'geoportal_redes_sensible_fijar', 'geoportal_redes_afectacion', 'geoportal_redes_sensores')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 5 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las 7 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las {{N_NUEVAS}} nuevas y del conjunto de funciones de redes de la Fase 2',
         case when (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_F2}}' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 las 5 tablas y la vista de la Fase 2: nadie de la API las lee ni las escribe; los hechos son de solo agregar',
         case when (select count(*) from pg_class c where c.relnamespace = 'redes'::regnamespace
                     and c.relname in ('tipos_sensible', 'usuarios_sensibles', 'usuario_sensible_eventos', 'presion_trabajo', 'sensor_lecturas', 'v_usuario_sensible')
                     and not exists (select 1 from aclexplode(c.relacl) x where x.grantee in (0, (select oid from pg_roles where rolname = 'anon'),
                                    (select oid from pg_roles where rolname = 'authenticated'), (select oid from pg_roles where rolname = 'service_role')))) = 6
               and (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'redes'::regnamespace
                     and c.relname in ('usuarios_sensibles', 'usuario_sensible_eventos', 'sensor_lecturas') and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 6 then 'OK' else 'MAL' end
  union all select 6, '06 usuarios sensibles sin datos de personas: ninguna columna de nombre, teléfono, dirección ni cédula',
         case when not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name in ('usuarios_sensibles', 'usuario_sensible_eventos')
                                and column_name ~ 'suscriptor|nombre|telefono|celular|direccion|cedula|propietario') then 'OK' else 'MAL' end
  union all select 7, '07 la capa «Cortes programados vigentes» está oculta de la lista (no borrada) y tecnica.f_avisos no cambió (sigue la del 9b 1b)',
         case when (select not activa from redes.geovisor_capas where codigo = 'cortes')
               and position('D10 (Corte 9b, Fase 1b)' in pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) > 0
               and position('f_presion_para_avisos' in pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) = 0 then 'OK' else 'MAL' end
  union all select 8, 'INFO usuarios sensibles: por confirmar · confirmados · descartados',
         (select count(*) filter (where estado = 'por_confirmar') || ' · ' || count(*) filter (where estado = 'confirmado') || ' · ' || count(*) filter (where estado = 'descartado') from redes.v_usuario_sensible)
  union all select 9, 'INFO alertas de presión de modelo (red existente): nodos · por nivel',
         coalesce((select (redes.f_alertas_presion('existente') ->> 'nodos') || ' · ' || (redes.f_alertas_presion('existente') ->> 'niveles')), 'sin carga del Plan Maestro')
  union all select 10, 'INFO sensores (activos SEN o SCA) · lecturas',
         (select count(*) from redes.activo_vigente_mat where prefijo in ('SEN', 'SCA') and not retirado) || ' · ' || (select count(*) from redes.sensor_lecturas)
) t order by o;
