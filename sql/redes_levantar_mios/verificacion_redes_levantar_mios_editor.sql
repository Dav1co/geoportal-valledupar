-- =====================================================================
-- TÉCNICA · FASE 1 · «MIS REPORTES» (levantar_mios) · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Todas las filas deben decir OK. Nota: después de este paquete, la fila de la huella del conjunto de la verificación del Corte 15 deja de valer.
-- =====================================================================
select k, v from (
  select 1 as o, '01 la RPC nueva: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname = 'geoportal_redes_levantar_mios' and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 1 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de la nueva y del conjunto de funciones de redes',
         case when (select count(*) from (values ('public.geoportal_redes_levantar_mios(text,integer)', 'b25bb783d505778f12bda1b05f23ace9')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 1
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '314112df87e4d649945fd3f611857025' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 no se tocó nada de lo publicado: quién puede reportar, la bandeja del supervisor, el acta y el alta del punto',
         case when (select count(*) from (values ('redes.f_levantar_acceso(text)', '69298852e18084d8857cd225180b908a'), ('public.geoportal_redes_levantar_lista(text,text,text,integer)', 'd93c1a02106798ef5230d2b922f35aae'), ('public.geoportal_redes_levantar_acta(text,text,text)', '0a7f82ff6fa307a9edb877f5ab0aa816'), ('public.geoportal_redes_levantar_crear(text,uuid,jsonb,text)', '09d88de65df1238dc373a3500b6b1f3a'), ('public.geoportal_redes_levantar_evento(text,text,text,text,text,text)', '35105af251ffaa62aec4121b6c27d967')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 5 then 'OK' else 'MAL' end
  union all select 6, '06 el índice por autor está y es válido',
         case when exists (select 1 from pg_index i where i.indexrelid = to_regclass('redes.ix_levantar_puntos_autor') and i.indisvalid and i.indrelid = 'redes.levantar_puntos'::regclass) then 'OK' else 'MAL' end
  union all select 7, 'INFO puntos por levantar · personas que han reportado',
         (select count(*) from redes.levantar_puntos) || ' · ' || (select count(distinct autor) from redes.levantar_puntos)
) t order by o;
