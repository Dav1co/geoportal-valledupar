-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del Corte 3a, la fila 07 de la verificación del Corte 2 dice MAL a propósito (el conjunto de funciones de redes cambió); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 9 tablas nuevas del Corte 3a y sus 3 vistas' as k,
         case when (select count(*) from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'r' and relname in ('tipos_intervencion', 'unidades_material',
                     'intervencion_preparaciones', 'intervenciones', 'intervencion_activos', 'intervencion_materiales', 'intervencion_fuentes', 'intervencion_archivos', 'intervencion_eventos')) = 9
               and (select count(*) from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'v' and relname in ('v_intervencion', 'v_intervencion_fuentes', 'v_no_identificados')) = 3 then 'OK' else 'MAL' end as v
  union all select 2, '02 catálogos: 5 tipos de intervención y 8 unidades; 11 parámetros nuevos',
         case when (select count(*) from redes.tipos_intervencion) >= 5 and (select count(*) from redes.unidades_material) >= 8
               and (select count(*) from redes.parametros where clave in ('itv_dias_atras_max', 'itv_max_horas', 'min_fotos_itv', 'max_fotos_itv', 'max_docs_itv', 'max_bytes_foto_itv',
                     'max_bytes_doc_itv', 'itv_radio_danos_m', 'itv_radio_propuesta_m', 'itv_max_activos_tambien', 'itv_max_materiales')) = 11 then 'OK' else 'MAL' end
  union all select 3, '03 RLS activa y ningún privilegio de la API en todas las tablas y vistas de redes',
         case when not exists (select 1 from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'r' and not relrowsecurity)
               and not exists (select 1 from pg_class c cross join (values ('anon'), ('authenticated'), ('service_role')) r(rol) where c.relnamespace = 'redes'::regnamespace and c.relkind in ('r', 'v', 'S')
                                and (has_table_privilege(r.rol, c.oid, 'select') or has_table_privilege(r.rol, c.oid, 'insert') or has_table_privilege(r.rol, c.oid, 'update') or has_table_privilege(r.rol, c.oid, 'delete')))
               and not exists (select 1 from pg_class c, aclexplode(c.relacl) x where c.relnamespace = 'redes'::regnamespace and x.grantee = 0) then 'OK' else 'MAL' end
  union all select 4, '04 las 26 RPC geoportal_redes_* (10 del 1a + 8 del 2 + 8 del 3a): security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 26 then 'OK' else 'MAL' end
  union all select 5, '05 ninguna función interna de redes la ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 6, '06 huellas md5 de las 10 RPC del 3a (8 nuevas y 2 reemplazadas), de las 2 vistas reemplazadas y del conjunto de funciones de redes',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_redes_asociar_activo', '5a4a6c58d8269eb80fee2c3d989cd4c7'), ('geoportal_redes_crear_dano', '7e70de54924240852635815f423571d1'), ('geoportal_redes_crear_intervencion', '65579eea5c981ca532a605b33be8cbe3'), ('geoportal_redes_danos_abiertos', '3e83bbf79f79da3526bde3523c3ac5c4'), ('geoportal_redes_formulario_intervencion', '452c8e353d00ef0ecf1ae6d31d35536e'), ('geoportal_redes_intervencion_recursos', '44a92bf4a7379df6f3a259e254d245cf'), ('geoportal_redes_intervenciones', 'b0d3a41405f63f4f35781ef2865122f3'), ('geoportal_redes_no_identificados', 'e6dea9565701b15dc9fcb925861066bb'), ('geoportal_redes_preparar_dano', 'e425feacdf9066b56fc0ae971aa843e1'), ('geoportal_redes_preparar_intervencion', '363488408002e09d046b842ba7861c8c'))) = 10
               and md5(pg_get_viewdef('redes.v_dano'::regclass, true)) = 'bee1b39d753fc55ae7cb85a3952896fb' and md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) = '6f459132b88e95dbce6f8d2b398ffeef'
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '2bd01b1d2556d8630f8533ee23ed2eb3' then 'OK' else 'MAL' end
  union all select 7, '07 hechos de solo inserción en las 7 tablas nuevas y catálogos sin borrar en las 2',
         case when (select count(distinct c.relname) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'redes'::regnamespace and t.tgname = 't_solo_agregar'
                     and c.relname in ('intervencion_preparaciones', 'intervenciones', 'intervencion_activos', 'intervencion_materiales', 'intervencion_fuentes', 'intervencion_archivos', 'intervencion_eventos')) = 7
               and (select count(distinct c.relname) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'redes'::regnamespace and t.tgname = 't_no_borrar'
                     and c.relname in ('tipos_intervencion', 'unidades_material')) = 2 then 'OK' else 'MAL' end
  union all select 8, '08 la epicrisis incluye las intervenciones y el daño toma el activo asociado',
         case when position('v_intervencion' in pg_get_viewdef('redes.v_epicrisis'::regclass, true)) > 0 and position('asociar_activo' in pg_get_viewdef('redes.v_dano'::regclass, true)) > 0 then 'OK' else 'MAL' end
  union all select 9, '09 todo archivo de intervención existe en Storage, y toda intervención que nace de un daño lo dejó atendido con su código',
         case when not exists (select 1 from redes.intervencion_archivos f where not exists (select 1 from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = f.ruta_storage))
               and not exists (select 1 from redes.intervenciones i where i.dano_id is not null
                                and not exists (select 1 from redes.dano_eventos e where e.dano_id = i.dano_id and e.tipo = 'atendido' and e.intervencion_id = i.id)) then 'OK' else 'MAL' end
  union all select 10, '10 toda intervención sin fotos tiene su motivo; todo daño sin fotos tiene su nota «Sin evidencia fotográfica»',
         case when not exists (select 1 from redes.v_intervencion where sin_evidencia and sin_evidencia_motivo is null)
               and not exists (select 1 from redes.danos d where not exists (select 1 from redes.dano_fotos f where f.dano_id = d.id) and d.origen = 'formulario'
                                and not exists (select 1 from redes.dano_eventos e where e.dano_id = d.id and e.tipo = 'nota' and e.motivo like 'Sin evidencia fotográfica:%')) then 'OK' else 'MAL' end
  union all select 11, '11 todo activo creado por una intervención está «por verificar», con su origen y su fila en la tabla vigente',
         case when not exists (select 1 from redes.activos a where a.origen_alta = 'intervencion'
                                and (not exists (select 1 from redes.activo_eventos e where e.activo_id = a.id and e.tipo = 'por_verificar')
                                     or not exists (select 1 from redes.activo_origen o where o.activo_id = a.id)
                                     or not exists (select 1 from redes.activo_vigente_mat m where m.activo_id = a.id))) then 'OK' else 'MAL' end
  union all select 12, 'INFO intervenciones por tipo', coalesce((select string_agg(tipo_codigo || ' ' || n, ', ' order by tipo_codigo) from (select tipo_codigo, count(*) n from redes.intervenciones group by 1) x), 'ninguna')
  union all select 13, 'INFO pendientes en la bandeja de no identificados', (select count(*)::text from redes.v_no_identificados)
  union all select 14, 'INFO intervenciones con recursos por completar', (select count(*)::text from redes.v_intervencion where recursos = 'por_completar')
) t order by o;
