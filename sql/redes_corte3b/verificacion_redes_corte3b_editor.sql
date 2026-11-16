-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del Corte 3b, la fila 06 de la verificación del Corte 3a dice MAL a propósito (el conjunto de funciones cambió); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 4 tablas nuevas del Corte 3b, la vista de identificadores y f_fotos_activo' as k,
         case when (select count(*) from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'r' and relname in ('ficha_ediciones', 'activo_identificador_eventos',
                     'foto_perfil_preparaciones', 'activo_fotos_perfil')) = 4 and to_regclass('redes.v_activo_identificadores') is not null
               and to_regprocedure('redes.f_fotos_activo(bigint)') is not null then 'OK' else 'MAL' end as v
  union all select 2, '02 parámetro max_bytes_foto_perfil', case when exists (select 1 from redes.parametros where clave = 'max_bytes_foto_perfil') then 'OK' else 'MAL' end
  union all select 3, '03 RLS activa y ningún privilegio de la API en todas las tablas y vistas de redes',
         case when not exists (select 1 from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'r' and not relrowsecurity)
               and not exists (select 1 from pg_class c cross join (values ('anon'), ('authenticated'), ('service_role')) r(rol) where c.relnamespace = 'redes'::regnamespace and c.relkind in ('r', 'v', 'S')
                                and (has_table_privilege(r.rol, c.oid, 'select') or has_table_privilege(r.rol, c.oid, 'insert') or has_table_privilege(r.rol, c.oid, 'update') or has_table_privilege(r.rol, c.oid, 'delete')))
               and not exists (select 1 from pg_class c, aclexplode(c.relacl) x where c.relnamespace = 'redes'::regnamespace and x.grantee = 0) then 'OK' else 'MAL' end
  union all select 4, '04 las 31 RPC geoportal_redes_* (10 del 1a + 8 del 2 + 8 del 3a + 5 del 3b): security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 31 then 'OK' else 'MAL' end
  union all select 5, '05 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 6, '06 huellas md5 de las 6 RPC del 3b (5 nuevas y activo_buscar), de v_epicrisis y del conjunto de funciones de redes',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_redes_activo_buscar', 'c735714c0623621a4acd74ccbd0346ae'), ('geoportal_redes_ficha_editar', '81b34cc4069f05b0d11c0bd48c2e50aa'), ('geoportal_redes_foto_perfil_fijar', 'a430ec67e09a89e03de29b6716c7a766'), ('geoportal_redes_foto_perfil_preparar', 'b1ed56aa688b8c060a49a058f903a1ff'), ('geoportal_redes_galeria', '3f96811f59b6cd31497d3d013b102205'), ('geoportal_redes_perfil', '2520ff7f1def39d5ba9958dbeb7ee7cc'))) = 6
               and md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) = 'a1e45ec72cb5b254a67698111994746a'
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '45971067176a3d30286b6227f0447c0d' then 'OK' else 'MAL' end
  union all select 7, '07 hechos de solo inserción en las 4 tablas nuevas',
         case when (select count(distinct c.relname) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'redes'::regnamespace and t.tgname = 't_solo_agregar'
                     and c.relname in ('ficha_ediciones', 'activo_identificador_eventos', 'foto_perfil_preparaciones', 'activo_fotos_perfil')) = 4 then 'OK' else 'MAL' end
  union all select 8, '08 la epicrisis incluye los cambios de la ficha', case when position('ficha_ediciones' in pg_get_viewdef('redes.v_epicrisis'::regclass, true)) > 0 then 'OK' else 'MAL' end
  union all select 9, '09 cada versión hecha en la ficha tiene su edición (con motivo), y ninguna placa vigente se repite entre activos',
         case when not exists (select 1 from redes.ficha_ediciones f where f.version is not null
                                and not exists (select 1 from redes.activo_versiones v where v.activo_id = f.activo_id and v.version = f.version and v.carga_id is null))
               and not exists (select lower(placa) from redes.v_activo_identificadores where placa is not null group by 1 having count(*) > 1) then 'OK' else 'MAL' end
  union all select 10, '10 toda foto de perfil existe en Storage', case when not exists (select 1 from redes.activo_fotos_perfil f where not exists (select 1 from storage.objects o
                                where o.bucket_id = 'redes-evidencias' and o.name = f.ruta_storage)) then 'OK' else 'MAL' end
  union all select 11, 'INFO ediciones de la ficha', (select count(*)::text from redes.ficha_ediciones)
  union all select 12, 'INFO activos con alias o placa', (select count(*)::text from redes.v_activo_identificadores where alias is not null or placa is not null)
) t order by o;
