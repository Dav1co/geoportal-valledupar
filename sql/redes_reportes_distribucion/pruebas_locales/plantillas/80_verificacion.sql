-- =====================================================================
-- TÉCNICA · FASE 1 · DESCARGAS DE DISTRIBUCIÓN · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Todas las filas deben decir OK. Nota: después de este paquete, la fila de la huella del conjunto de la verificación del aviso por contrato deja de valer.
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 4 RPC: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array['geoportal_redes_reporte_iniciar', 'geoportal_redes_reporte_pagina', 'geoportal_redes_reporte_cerrar', 'geoportal_redes_reporte_sectores']) and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 4 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las {{N_NUEVAS}} nuevas y del conjunto de funciones de redes',
         case when (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_DIST}}' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 no se tocó nada de lo publicado que se lee ni las rutas del bot de nombre parecido (supervisor, perfil, sector, reportes de un evento, descarga de daños e intervenciones, reporte_convertir y reporte_descartar)',
         case when (select count(*) from (values {{PUBLICADAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_PUBLICADAS}} then 'OK' else 'MAL' end
  union all select 6, '06 las 2 tablas nuevas: RLS, solo inserción y sin permisos para la API',
         case when (select count(*) from pg_class c where c.oid in ('redes.reporte_descargas'::regclass, 'redes.reporte_descarga_cierres'::regclass) and c.relrowsecurity
                     and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')
                     and (select count(*) from pg_trigger t where t.tgrelid = c.oid and t.tgname in ('t_solo_agregar', 't_solo_agregar_trunc')) = 2) = 2 then 'OK' else 'MAL' end
  union all select 7, 'INFO descargas iniciadas · cerradas', (select count(*) from redes.reporte_descargas) || ' · ' || (select count(*) from redes.reporte_descarga_cierres)
) t order by o;
