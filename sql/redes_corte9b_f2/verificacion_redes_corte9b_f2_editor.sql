-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). Todas las filas deben decir OK.
-- Nota: la verificación del 9b (1a + 1b) que mira el md5 de tecnica.f_avisos deja de valer después de la Fase 2. Además, después de la Fase 2, la fila 03 de la verificación del 9b (1a + 1b) deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 6 RPC nuevas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_alertas_presion', 'geoportal_redes_sensibles', 'geoportal_redes_sensible_fijar', 'geoportal_redes_afectacion', 'geoportal_redes_sensores', 'geoportal_redes_afectaciones_danos')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 6 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las 8 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las 14 nuevas y del conjunto de funciones de redes de la Fase 2',
         case when (select count(*) from (values ('redes.f_presion_nivel(numeric,numeric)', '6441a3c6df8b11bdd06c448c6adacbe2'), ('redes.f_presion_nodos(text)', '623913f7d7769657395e132bf04fb26e'), ('redes.f_alertas_presion(text)', 'b22987360efe991cb6d21bedf90fa905'), ('redes.f_presion_para_avisos()', 'b9e6313e5c653f4d65be306ef49e8e11'), ('redes.f_sensible_tipo(text)', '6044a2bed03348f62ed92855748edb76'), ('redes.f_sensibles_proponer(text)', 'aabaf7f82fffbd7e94385ee005bd6037'), ('redes.f_sensibles_en(text[])', 'd390c744e700b61b2fafebbc4f74dd01'), ('redes.f_sensor_estado(bigint)', '1df139091aa8b2f3eb31ae331db68333'), ('public.geoportal_redes_alertas_presion(text,text)', '0c7d2964e96ec0f525d7f0957530d293'), ('public.geoportal_redes_sensibles(text,text,text,integer)', 'f2e0bf3d61dac8f8b85eb044e37f925a'), ('public.geoportal_redes_sensible_fijar(text,text,text,text,text)', 'ea00de3bbdf9e0a490ffbaff9f72d96a'), ('public.geoportal_redes_afectacion(text,text)', 'd8bda5a0a052c48234f62f3e9d9e6139'), ('public.geoportal_redes_sensores(text)', '4a39e349b0ce1fc3336e3a22bf4504b1'), ('public.geoportal_redes_afectaciones_danos(text)', '65b3a8e98f25d0bca2f1fe648d5749d8')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 14
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '24e62e151ff418ea6acf631572d72683' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 las 6 tablas y la vista de la Fase 2: nadie de la API las lee ni las escribe; los hechos son de solo agregar',
         case when (select count(*) from pg_class c where c.relnamespace = 'redes'::regnamespace
                     and c.relname in ('tipos_sensible', 'usuarios_sensibles', 'usuario_sensible_eventos', 'presion_trabajo', 'presion_horas_no_confiables', 'sensor_lecturas', 'v_usuario_sensible')
                     and not exists (select 1 from aclexplode(c.relacl) x where x.grantee in (0, (select oid from pg_roles where rolname = 'anon'),
                                    (select oid from pg_roles where rolname = 'authenticated'), (select oid from pg_roles where rolname = 'service_role')))) = 7
               and (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'redes'::regnamespace
                     and c.relname in ('usuarios_sensibles', 'usuario_sensible_eventos', 'sensor_lecturas') and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 6 then 'OK' else 'MAL' end
  union all select 6, '06 usuarios sensibles sin datos de personas: ninguna columna de nombre, teléfono, dirección ni cédula',
         case when not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name in ('usuarios_sensibles', 'usuario_sensible_eventos')
                                and column_name ~ 'suscriptor|nombre|telefono|celular|direccion|cedula|propietario') then 'OK' else 'MAL' end
  union all select 7, '07 la capa «Cortes programados vigentes» está oculta de la lista (no borrada) y tecnica.f_avisos es la de la Fase 2 (con el aviso informativo de presiones, que depende del parámetro «presion_modelo_aviso»)',
         case when (select not activa from redes.geovisor_capas where codigo = 'cortes')
               and exists (select 1 from tecnica.aviso_parametros where clave = 'presion_modelo_aviso')
               and md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) = '2a7989bead5fd35d3a4d0c4e45bcb92b'
               and not has_function_privilege('service_role', 'tecnica.f_avisos(boolean,boolean,timestamp with time zone)', 'execute') then 'OK' else 'MAL' end
  union all select 8, 'INFO usuarios sensibles: por confirmar · confirmados · descartados',
         (select count(*) filter (where estado = 'por_confirmar') || ' · ' || count(*) filter (where estado = 'confirmado') || ' · ' || count(*) filter (where estado = 'descartado') from redes.v_usuario_sensible)
  union all select 8.5, 'INFO aviso de presiones: parámetro «presion_modelo_aviso» (0 apagado, 1 encendido) · horas no confiables (red existente) · nodos fuera de rango que diría el aviso',
         (select valor::text from tecnica.aviso_parametros where clave = 'presion_modelo_aviso') || ' · '
         || coalesce((select string_agg(hora::text, ', ' order by hora) from redes.presion_horas_no_confiables where escenario = 'existente' and activa), 'ninguna') || ' · '
         || coalesce((select sum(n)::text from redes.f_presion_para_avisos()), '0')
  union all select 9, 'INFO alertas de presión de modelo (red existente, horas confiables): nodos · por nivel',
         coalesce((select (redes.f_alertas_presion('existente') ->> 'nodos') || ' · ' || (redes.f_alertas_presion('existente') ->> 'niveles')), 'sin carga del Plan Maestro')
  union all select 10, 'INFO sensores (activos SEN o SCA) · lecturas',
         (select count(*) from redes.activo_vigente_mat where prefijo in ('SEN', 'SCA') and not retirado) || ' · ' || (select count(*) from redes.sensor_lecturas)
) t order by o;
