-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 6b, la fila 05 de la verificación del 6a dice MAL a propósito (el conjunto de funciones cambió); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 tablas nuevas con RLS; vistas compartidas de solo inserción' as k,
         case when (select bool_and(relrowsecurity) from pg_class where oid in (to_regclass('redes.contratos_capa'), to_regclass('redes.contratos_capa_estado'),
                                                                              to_regclass('redes.vistas_compartidas'), to_regclass('redes.muestreo_rangos')))
               and (select count(*) from pg_trigger where tgrelid = to_regclass('redes.vistas_compartidas') and not tgisinternal) = 2 then 'OK' else 'MAL' end as v
  union all select 2, '02 ni anon, ni authenticated, ni service_role leen las tablas ni la vista nuevas (la capa de contratos y las vistas compartidas tampoco)',
         case when not exists (select 1 from (values ('redes.contratos_capa'), ('redes.contratos_capa_estado'), ('redes.vistas_compartidas'), ('redes.muestreo_rangos'), ('redes.v_reportes_comercial')) t(n),
                                              (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                                where has_table_privilege(r.rol, t.n, 'select') or has_table_privilege(r.rol, t.n, 'insert')) then 'OK' else 'MAL' end
  union all select 3, '03 las 4 RPC nuevas y las 2 reemplazadas: security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_vista_compartir', 'geoportal_redes_vista_abrir',
                                       'geoportal_redes_geovisor', 'geoportal_redes_geovisor_capa')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 6 then 'OK' else 'MAL' end
  union all select 4, '04 ninguna función interna de redes la ejecuta la API (incluidas las 4 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 5, '05 huellas md5 de las 4 RPC nuevas, de las 2 reemplazadas y del conjunto de funciones de redes del 6b',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) = {{N_RPC}}
               and (select count(*) from (values {{CAMBIADAS_6B}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_CAMBIADAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_CORTE_6B}}' then 'OK' else 'MAL' end
  union all select 6, '06 la capa de contratos no tiene columnas de nombre, dirección, teléfono ni deuda',
         case when not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'contratos_capa'
                                and column_name ~ '(nombre|direccion|telefono|deuda|barrio|saldo|correo|identificacion)') then 'OK' else 'MAL' end
  union all select 7, '07 el catálogo del geovisor: contratos con su capa propia, reportes de Comercial por fecha y vacía (hasta el Corte 8), sin capas preparadas encendidas',
         case when (select fuente from redes.geovisor_capas where codigo = 'contratos') = 'contratos'
               and (select fuente || '|' || por_fecha from redes.geovisor_capas where codigo = 'reportes_comercial') = 'geojson|true'
               and not exists (select 1 from redes.capas_por_perfil c join redes.geovisor_capas g on g.codigo = c.capa where c.encendida and g.fuente = 'preparada') then 'OK' else 'MAL' end
  union all select 8, '08 los rangos del muestreo apuntan a variables que existen (Muestreo y Salida) y los 3 parámetros nuevos están en su rango',
         case when (select count(*) from redes.muestreo_rangos r join tecnica.variables a on a.codigo = r.variable_muestreo join tecnica.variables b on b.codigo = r.variable_salida) = 2
               and (select count(*) from redes.parametros where clave in ('geovisor_zoom_contratos', 'geovisor_contratos_horas', 'geovisor_muestreo_dias') and valor between minimo and maximo) = 3 then 'OK' else 'MAL' end
  union all select 9, '09 cada lectura de la tarjeta del contrato quedó en la auditoría sin el nombre ni la dirección',
         case when not exists (select 1 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta' and (detalle ? 'nombre' or detalle ? 'direccion_texto' or detalle::text ~* 'suscriptor ')) then 'OK' else 'MAL' end
  union all select 10, 'INFO contratos en la capa (calculada el) · vistas compartidas · lecturas de tarjetas · rango de Salida del cloro (mín–máx)',
         coalesce((select filas || ' (' || to_char(calculado_en at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI') || ')' from redes.contratos_capa_estado where id = 1), 'sin calcular todavía') || ' · ' ||
         (select count(*) from redes.vistas_compartidas) || ' · ' || (select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta') || ' · ' ||
         coalesce((select coalesce(x.ref_min::text, '—') || '–' || coalesce(x.ref_max::text, '—') from tecnica.f_referencia_vigente((select id from tecnica.variables where codigo = 'cloro_libre_tanque'), null, null) x), 'sin rango general')
) t order by o;
