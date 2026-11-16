-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 4a, la fila 06 de la verificación del 3b dice MAL a propósito (el conjunto de funciones cambió); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 columnas nuevas: ver_dashboard_redes (falso por omisión) y redes.danos.sector_num (1 a 100)' as k,
         case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_lista_blanca' and column_name = 'ver_dashboard_redes'
                            and column_default = 'false' and is_nullable = 'NO')
               and exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'danos' and column_name = 'sector_num') then 'OK' else 'MAL' end as v
  union all select 2, '02 las 4 funciones de permisos con dashboard_redes, una firma cada una, y su huella del 4a',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{VIVAS_4A}})) = 4
               and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('geoportal_puede', 'geoportal_mis_permisos', 'geoportal_admin_permisos', 'geoportal_admin_listar')) = 4 then 'OK' else 'MAL' end
  union all select 3, '03 las 4 funciones de permisos: solo service_role (ni anon ni authenticated)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_puede', 'geoportal_mis_permisos', 'geoportal_admin_permisos', 'geoportal_admin_listar')
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or not has_function_privilege('service_role', p.oid, 'execute')))
              then 'OK' else 'MAL' end
  union all select 4, '04 las 38 RPC geoportal_redes_* (31 + 7 del 4a): security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 38 then 'OK' else 'MAL' end
  union all select 5, '05 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 6, '06 huellas md5 de las 17 RPC del 4a (7 nuevas y 10 reemplazadas) y del conjunto de funciones de redes',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_TODAS_4A}})) = 17
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_CORTE_4A}}' then 'OK' else 'MAL' end
  union all select 7, '07 ninguna RPC de redes autoriza la captura con la función de planta directamente (todas pasan por f_autorizar_captura_redes)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'
                                and position('tecnica.f_autorizar_captura(' in pg_get_functiondef(p.oid)) > 0) then 'OK' else 'MAL' end
  union all select 8, '08 ningún daño ni intervención NUEVOS sin fotos (desde el 4a nadie registra «sin evidencia fotográfica»)',
         case when not exists (select 1 from redes.v_intervencion where sin_evidencia and registrado_en > (select max(creado_en) from public.geoportal_auditoria where accion = 'migracion_redes_corte4a'))
               and not exists (select 1 from redes.danos d where d.origen = 'formulario' and not exists (select 1 from redes.dano_fotos f where f.dano_id = d.id)
                                and d.registrado_en > (select max(creado_en) from public.geoportal_auditoria where accion = 'migracion_redes_corte4a')) then 'OK' else 'MAL' end
  union all select 9, 'INFO personas con ver_dashboard_redes (supervisores de distribución)', (select count(*)::text from public.geoportal_lista_blanca where ver_dashboard_redes)
  union all select 10, 'INFO daños con sector (número)', (select count(*)::text from redes.danos where sector_num is not null)
  union all select 11, 'INFO daños e intervenciones ocultos', (select count(*) filter (where estado = 'oculto') from redes.v_dano)::text || ' daños, '
                                                                 || (select count(*) filter (where estado = 'oculta') from redes.v_intervencion)::text || ' intervenciones'
) t order by o;
