-- =====================================================================
-- TÉCNICA · FASE 1 · EVENTOS: ORIGEN Y TUBOS · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). Todas las filas deben decir OK.
-- Nota: después de este paquete, la fila de la huella del conjunto de la verificación de las descargas de Distribución deja de valer.
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 2 RPC nuevas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.oid in (to_regprocedure('public.geoportal_redes_evento_causal_fijar(text,text,text,boolean,text)'), to_regprocedure('public.geoportal_redes_tubo_sectores_fijar(text,text,text[],text)'))
                     and p.prosecdef and p.proconfig is not null and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
                     and not has_function_privilege('authenticated', p.oid, 'execute') and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 2 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5: las {{N_REEMPLAZADAS}} reemplazadas, las {{N_NUEVAS}} nuevas y el conjunto de redes',
         case when (select count(*) from (values {{REEMPLAZADAS_DESPUES}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_REEMPLAZADAS}}
               and (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_DESPUES}}' then 'OK' else 'MAL' end
  union all select 4, '04 no se tocó evento_contrato, el aviso, el SCRR, los disparadores, el bot ni las demás rutas de eventos ({{N_NO_TOCAR}} funciones)',
         case when (select count(*) from (values {{NO_TOCAR}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NO_TOCAR}} then 'OK' else 'MAL' end
  union all select 5, '05 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 6, '06 las 6 tablas nuevas: RLS y sin permisos para la API; las de hechos, solo inserción',
         case when (select count(*) from pg_class c where c.oid in ('redes.evento_causales'::regclass, 'redes.evento_causal_eventos'::regclass, 'redes.evento_causal'::regclass,
                                                                      'redes.tubo_sectores'::regclass, 'redes.tubo_sector_eventos'::regclass, 'redes.evento_tubos'::regclass)
                     and c.relrowsecurity and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select')
                     and not has_table_privilege('service_role', c.oid, 'select')) = 6
               and (select count(*) from pg_trigger t where t.tgname in ('t_solo_agregar', 't_solo_agregar_trunc')
                     and t.tgrelid in ('redes.evento_causal_eventos'::regclass, 'redes.evento_causal'::regclass, 'redes.tubo_sector_eventos'::regclass, 'redes.evento_tubos'::regclass)) = 8 then 'OK' else 'MAL' end
  union all select 7, '07 los sectores por planta quedaron todos inactivos, con su hecho (nada se borró)',
         case when not exists (select 1 from redes.planta_sectores where activo)
               and not exists (select distinct planta_id from redes.planta_sectores except select planta_id from redes.planta_sector_eventos where motivo = 'el sistema es único; los sectores pasan a los tubos de salida') then 'OK' else 'MAL' end
  union all select 8, '08 las 5 causales de David, activas', case when (select count(*) from redes.evento_causales where activa and codigo in ('trabajo_programado', 'parametros_entrada', 'falla_planta', 'mantenimiento_planta', 'otra')) = 5 then 'OK' else 'MAL' end
  union all select 9, 'INFO causales · tubos con sectores · eventos con causal · eventos por tubo', (select count(*) from redes.evento_causales) || ' · ' || (select count(distinct punto_id) from redes.tubo_sectores where activo)
         || ' · ' || (select count(*) from redes.evento_causal) || ' · ' || (select count(distinct evento_id) from redes.evento_tubos)
) t order by o;
