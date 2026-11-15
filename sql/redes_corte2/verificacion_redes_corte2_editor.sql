-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del Corte 2, la fila 07 de la verificación del 1a dice MAL a propósito (el conjunto de funciones de redes creció); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 15 tablas nuevas del Corte 2 y sus 3 vistas' as k,
         case when (select count(*) from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'r' and relname in ('tipos_dano', 'tipos_rotura', 'causas', 'tipos_tercero', 'marcas_riesgo',
                     'caudales_fuga', 'reportes_externos', 'reporte_externo_fotos', 'reporte_externo_eventos', 'dano_preparaciones', 'danos', 'dano_datos_sensibles', 'dano_tiempos', 'dano_eventos', 'dano_fotos')) = 15
               and (select count(*) from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'v' and relname in ('v_dano', 'v_dano_tiempos', 'v_reporte_externo')) = 3 then 'OK' else 'MAL' end as v
  union all select 2, '02 catálogos: 13 tipos de daño o falla, 4 roturas, 6 causas, 6 terceros, 4 marcas; 6 parámetros nuevos',
         case when (select count(*) from redes.tipos_dano) >= 13 and (select count(*) from redes.tipos_rotura) >= 4 and (select count(*) from redes.causas) >= 6 and (select count(*) from redes.tipos_tercero) >= 6
               and (select count(*) from redes.marcas_riesgo) >= 4 and (select count(*) from redes.parametros where clave in ('dano_dias_atras_max', 'min_fotos_dano', 'max_fotos_dano', 'max_bytes_foto_dano', 'mini_zoom_min', 'mini_zoom_acc')) = 6 then 'OK' else 'MAL' end
  union all select 3, '03 bucket redes-evidencias: privado, 5 MB, JPEG y PDF, sin políticas en storage.objects',
         case when exists (select 1 from storage.buckets where id = 'redes-evidencias' and not public and file_size_limit = 5242880 and allowed_mime_types = array['image/jpeg', 'application/pdf'])
               and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and (qual ilike '%redes-evidencias%' or with_check ilike '%redes-evidencias%')) then 'OK' else 'MAL' end
  union all select 4, '04 RLS activa y ningún privilegio de la API en todas las tablas y vistas de redes',
         case when not exists (select 1 from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'r' and not relrowsecurity)
               and not exists (select 1 from pg_class c cross join (values ('anon'), ('authenticated'), ('service_role')) r(rol) where c.relnamespace = 'redes'::regnamespace and c.relkind in ('r', 'v', 'S')
                                and (has_table_privilege(r.rol, c.oid, 'select') or has_table_privilege(r.rol, c.oid, 'insert') or has_table_privilege(r.rol, c.oid, 'update') or has_table_privilege(r.rol, c.oid, 'delete')))
               and not exists (select 1 from pg_class c, aclexplode(c.relacl) x where c.relnamespace = 'redes'::regnamespace and x.grantee = 0) then 'OK' else 'MAL' end
  union all select 5, '05 las 18 RPC geoportal_redes_* (10 del 1a + 8 del 2): security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 18 then 'OK' else 'MAL' end
  union all select 6, '06 ninguna función interna de redes la ejecuta la API (incluida la entrada del bot)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 7, '07 huellas md5 de las 8 RPC nuevas y del conjunto de funciones de redes (las que dejó la migración)',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_redes_activo_buscar', '12e6d731e9a49981073e05ad9624dafe'), ('geoportal_redes_crear_dano', '3c5a3d37d8e61e50b8bafb204dbdebd2'), ('geoportal_redes_formulario_dano', '099483758f22b4fe033937d14476f380'), ('geoportal_redes_mvt', '59ebf5e8b6cd89acc81283249ce717cc'), ('geoportal_redes_preparar_dano', '52af990ab124e9ea1d8a822a5a23e520'), ('geoportal_redes_reporte_convertir', 'e98e2cfea5ddab54be11ee9b7ba93681'), ('geoportal_redes_reporte_descartar', 'f070fb817ea878564a0274154ce5c042'), ('geoportal_redes_tramo_nodos', 'ee1795310c54c44b088dd644bb263f09'))) = 8
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '06ecefcf2922e724e1be5546b87a5510' then 'OK' else 'MAL' end
  union all select 8, '08 hechos de solo inserción en las 10 tablas nuevas y catálogos sin borrar en las 5',
         case when (select count(distinct c.relname) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'redes'::regnamespace and t.tgname = 't_solo_agregar'
                     and c.relname in ('danos', 'dano_datos_sensibles', 'dano_tiempos', 'dano_eventos', 'dano_fotos', 'dano_preparaciones', 'reportes_externos', 'reporte_externo_fotos', 'reporte_externo_eventos', 'caudales_fuga')) = 10
               and (select count(distinct c.relname) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'redes'::regnamespace and t.tgname = 't_no_borrar'
                     and c.relname in ('tipos_dano', 'tipos_rotura', 'causas', 'tipos_tercero', 'marcas_riesgo')) = 5 then 'OK' else 'MAL' end
  union all select 9, '09 la epicrisis incluye los daños (v_epicrisis lee v_dano)', case when position('v_dano' in pg_get_viewdef('redes.v_epicrisis'::regclass, true)) > 0 then 'OK' else 'MAL' end
  union all select 10, '10 toda foto de daño existe en Storage con su tamaño, y el nombre del tercero solo existe para daños con causa de terceros',
         case when not exists (select 1 from redes.dano_fotos f where not exists (select 1 from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = f.ruta_storage))
               and not exists (select 1 from redes.dano_datos_sensibles s join redes.danos d on d.id = s.dano_id where d.causa_clase <> 'terceros') then 'OK' else 'MAL' end
  union all select 11, '11 reportes del bot sin columnas de nombre ni de teléfono',
         case when not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name like 'reporte%' and column_name ~ '(nombre|telefono|celular|cedula|correo|email)') then 'OK' else 'MAL' end
  union all select 12, 'INFO daños por estado', coalesce((select string_agg(estado || ' ' || n, ', ' order by estado) from (select estado, count(*) n from redes.v_dano group by 1) x), 'ninguno')
  union all select 13, 'INFO reportes del bot por estado', coalesce((select string_agg(estado_bot || ' ' || n, ', ' order by estado_bot) from (select estado_bot, count(*) n from redes.v_reporte_externo group by 1) x), 'ninguno')
  union all select 14, 'INFO filas en caudales_fuga (vacía hasta que Técnica la entregue)', (select count(*)::text from redes.caudales_fuga)
) t order by o;
