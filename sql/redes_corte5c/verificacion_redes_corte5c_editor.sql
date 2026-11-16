-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 5c, las filas 03 y 05 de la verificación del 5b dicen MAL a propósito (ya son 5 las RPC geoportal_tec_punto* y el conjunto de funciones
-- cambió); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 tablas nuevas con RLS y reglas de solo inserción (devoluciones a la capa y correcciones de ubicación)' as k,
         case when (select bool_and(relrowsecurity) from pg_class where oid in (to_regclass('redes.ficha_campo_devoluciones'), to_regclass('tecnica.punto_ubicacion_correcciones')))
               and (select count(*) from pg_trigger where tgrelid in (to_regclass('redes.ficha_campo_devoluciones'), to_regclass('tecnica.punto_ubicacion_correcciones')) and not tgisinternal) = 4
              then 'OK' else 'MAL' end as v
  union all select 2, '02 ni anon, ni authenticated, ni service_role leen ni escriben las tablas nuevas',
         case when not exists (select 1 from (values ('redes.ficha_campo_devoluciones'), ('tecnica.punto_ubicacion_correcciones')) t(n),
                                              (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                                where has_table_privilege(r.rol, t.n, 'select') or has_table_privilege(r.rol, t.n, 'insert')) then 'OK' else 'MAL' end
  union all select 3, '03 las 6 RPC nuevas y las 2 de planta reemplazadas: security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_cargue_capas', 'geoportal_redes_cargue_historial', 'geoportal_redes_cargue_iniciar', 'geoportal_redes_carga_muestra',
                                       'geoportal_redes_carga_devolver_campo', 'geoportal_tec_punto_ubicacion_corregir', 'geoportal_tec_punto_ubicacion_revisar', 'geoportal_tec_punto_ubicaciones')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 8 then 'OK' else 'MAL' end
  union all select 4, '04 ninguna función interna de redes la ejecuta la API (incluidas la nueva y las reemplazadas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 5, '05 huellas md5 de las 6 RPC nuevas, de las 8 reemplazadas y del conjunto de funciones de redes del 5c',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_redes_carga_devolver_campo', 'b36ed8f42ee53116db9862d5506d6178'), ('geoportal_redes_carga_muestra', 'dbeb32df95032c73b63a8d0ba2e7f916'), ('geoportal_redes_cargue_capas', 'ece3cdd5b0930ad6c978e0918767241d'), ('geoportal_redes_cargue_historial', '2931fb96f354077feb8f55f7e8c9eae1'), ('geoportal_redes_cargue_iniciar', 'bb82f2257259cef249565c18a537836c'), ('geoportal_tec_punto_ubicacion_corregir', '5518a3d3bd764c7801b089d7e48f2a1e'))) = 6
               and (select count(*) from (values ('redes.f_geo_desde_wkt(text,integer)', '275df2e3a71fcd4fcf8623858f7a02d4'), ('redes.f_candidatos(bigint)', 'e8b1b1c04a4e826e9b631c489a4d4716'), ('redes.f_preparar_candidatos(bigint)', '140cd3d91986bea1a9e5f772c78a23e3'), ('redes.f_resumen(bigint)', '94f7e7b146a554d882a481a9f0973027'), ('redes.f_fusionar_ficha()', '490965f220573ec3bee6423f7c63ab2d'), ('redes.f_iniciar(text,text,text,integer,text,integer,text,text)', 'fa0b7dffda7a7c04bec4265d99633cb8'), ('public.geoportal_tec_punto_ubicacion_revisar(text,bigint,text,text,text)', '763c90cacdab105969966721b27f4c98'), ('public.geoportal_tec_punto_ubicaciones(text)', 'dcf5e4a013481f2d0077a9de32a0db72')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 8
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = 'a5ce1ff8c5659de3b853e30f4d3025e6' then 'OK' else 'MAL' end
  union all select 6, '06 el parámetro del cruce por geometría existe con su rango, y las 11 capas nuevas del lector genérico están activas',
         case when (select count(*) from redes.parametros where clave = 'cruce_geometria_tol_m' and valor between minimo and maximo) = 1
               and (select count(*) from redes.capas where activa and fuente = 'carga' and prefijo is not null and columna_llave is null
                       and codigo in ('captaciones', 'aduccion', 'desarenadores', 'bombeo_ap', 'sumideros', 'interceptores', 'bombeo_ar', 'ptar', 'sectores', 'sensores', 'scada')) = 11
              then 'OK' else 'MAL' end
  union all select 7, '07 el CHECK de fuente de las ubicaciones admite «correccion» y cada corrección apunta a una ubicación verificada de fuente «correccion»',
         case when (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'tecnica.puntos_ubicacion'::regclass and conname = 'puntos_ubicacion_fuente_check') like '%correccion%'
               and not exists (select 1 from tecnica.punto_ubicacion_correcciones c join tecnica.puntos_ubicacion u on u.id = c.ubicacion_id
                                where u.exactitud <> 'verificada' or u.fuente <> 'correccion' or u.punto_id <> c.punto_id) then 'OK' else 'MAL' end
  union all select 8, '08 tecnica.puntos, tecnica.puntos_ubicacion y redes.ficha_ediciones conservan sus candados',
         case when (select count(*) from pg_trigger where tgrelid = 'tecnica.puntos'::regclass and tgname in ('t_no_borrar', 't_no_vaciar') and not tgisinternal) = 2
               and (select count(*) from pg_trigger where tgrelid = 'tecnica.puntos_ubicacion'::regclass and tgname in ('t_solo_agregar', 't_solo_agregar_trunc') and not tgisinternal) = 2
               and (select count(*) from pg_trigger where tgrelid = 'redes.ficha_ediciones'::regclass and tgname in ('t_solo_agregar', 't_solo_agregar_trunc') and not tgisinternal) = 2 then 'OK' else 'MAL' end
  union all select 9, '09 la reproyección de EPSG 9377 funciona en esta base (un punto de Valledupar ida y vuelta, a menos de 1 m)',
         case when (select ST_Distance(g.geom::geography, ST_SetSRID(ST_MakePoint(-73.25, 10.46), 4326)::geography) < 1
                      from redes.f_geo_desde_wkt('POINT(4972651.402 2713870.093)', 9377) g) then 'OK' else 'MAL' end
  union all select 10, 'INFO EPSG 9377 en spatial_ref_sys (sí: lo usa directo; no: usa su definición)',
         case when exists (select 1 from spatial_ref_sys where srid = 9377) then 'sí' else 'no' end
  union all select 11, 'INFO devoluciones a la capa · correcciones de ubicación · cargas abiertas',
         (select count(*) from redes.ficha_campo_devoluciones) || ' · ' || (select count(*) from tecnica.punto_ubicacion_correcciones) || ' · '
           || (select count(*) from redes.v_cargas_estado where estado = 'abierta')
) t order by o;
