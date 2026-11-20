-- =====================================================================
-- TÉCNICA · FASE 1 · REPORTES DEL PTAP · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). Todas las filas deben decir OK.
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 4 RPC: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname = any (array['geoportal_tec_reporte_iniciar', 'geoportal_tec_reporte_pagina', 'geoportal_tec_reporte_cerrar', 'geoportal_tec_reporte_remision_foto'])
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 4 then 'OK' else 'MAL' end as v
  union all select 2, '02 las funciones internas nuevas: nadie más que su dueño',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'tecnica'::regnamespace
                                and p.proname = any (array['f_rep_catalogo', 'f_rep_max_filas', 'f_rep_max_pagina', 'f_rep_ts', 'f_rep_col', 'f_rep_filtros', 'f_rep_cols_variables', 'f_rep_columnas', 'f_rep_valores', 'f_rep_envios_llaves', 'f_rep_envios_pagina', 'f_rep_envios',
                                                           'f_rep_quimicos', 'f_rep_kardex', 'f_rep_eventos_planta', 'f_rep_fuera_referencia', 'f_rep_filas', 'f_rep_leame'])
                                and exists (select 1 from aclexplode(p.proacl) x where x.grantee <> p.proowner)) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las {{N_NUEVAS}} nuevas',
         case when (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}} then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 la huella de redes no cambió con este paquete',
         case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) in ('{{MD5_BASE}}', '{{MD5_REDES_DESPUES}}') then 'OK' else 'MAL' end
  union all select 6, '06 las 2 tablas nuevas: RLS, solo inserción y sin permisos para la API',
         case when (select count(*) from pg_class c where c.oid in ('tecnica.reporte_descargas'::regclass, 'tecnica.reporte_descarga_cierres'::regclass) and c.relrowsecurity
                     and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')
                     and (select count(*) from pg_trigger t where t.tgrelid = c.oid and t.tgname in ('t_solo_agregar', 't_solo_agregar_trunc')) = 2) = 2 then 'OK' else 'MAL' end
  union all select 7, 'INFO descargas iniciadas · cerradas', (select count(*) from tecnica.reporte_descargas) || ' · ' || (select count(*) from tecnica.reporte_descarga_cierres)
) t order by o;
