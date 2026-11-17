-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 14, la fila de huellas de la verificación del 9b (Fase 3) deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 las RPC nuevas y las reemplazadas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and (p.proname like 'geoportal\_redes\_levantar\_%' or p.proname like 'geoportal\_redes\_%remuneracion%' or p.proname in ('geoportal_redes_mi_perfil', 'geoportal_redes_geovisor_capa', 'geoportal_redes_geovisor'))
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = {{N_RPC}} then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las {{N_CAMBIADAS}} reemplazadas, de las {{N_NUEVAS}} nuevas y del conjunto de funciones de redes del 14',
         case when (select count(*) from (values {{CAMBIADAS_14}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_CAMBIADAS}}
               and (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_14}}' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 las 4 tablas de los puntos por levantar: nadie de la API las lee ni las escribe; son de solo agregar (con su disparador)',
         case when (select count(*) from pg_class c where c.oid in ('redes.levantar_puntos'::regclass, 'redes.levantar_preparaciones'::regclass, 'redes.levantar_fotos'::regclass, 'redes.levantar_eventos'::regclass)
                     and c.relrowsecurity
                     and not exists (select 1 from aclexplode(c.relacl) x where x.grantee in (0, (select oid from pg_roles where rolname = 'anon'), (select oid from pg_roles where rolname = 'authenticated'),
                                                                                              (select oid from pg_roles where rolname = 'service_role')))) = 4
               and (select count(*) from pg_trigger t where t.tgrelid in ('redes.levantar_puntos'::regclass, 'redes.levantar_preparaciones'::regclass, 'redes.levantar_fotos'::regclass, 'redes.levantar_eventos'::regclass)
                     and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 8 then 'OK' else 'MAL' end
  union all select 6, '06 ninguna tabla de los puntos por levantar tiene columnas de suscriptores (nombre, contrato, teléfono, dirección)',
         case when not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name like 'levantar\_%'
                                and column_name ~ 'suscriptor|contrato|telefono|celular|direccion|cedula|propietario|nombre') then 'OK' else 'MAL' end
  union all select 7, '07 los parámetros del 14 y el consecutivo LEV',
         case when (select count(*) from redes.parametros where clave in ({{PARAMETROS}}) and estado = 'vigente' and valor is not null) = {{N_PARAMETROS}}
               and exists (select 1 from redes.consecutivos where prefijo = 'LEV') then 'OK' else 'MAL' end
  union all select 8, '08 el formulario «Encontrar o reportar activo»: en el dominio de Técnica, en Personal de distribución y en la lista de Personal de Comercial',
         case when 'activo_campo'::tecnica.formulario_clave is not null and exists (select 1 from redes.formularios_distribucion where clave = 'activo_campo' and activo)
               and exists (select 1 from campo.f_formularios_personal() x where x.clave = 'activo_campo')
               and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_eventos_formulario_check') = '{{DEF_CHECK_CAMPO_14}}'
              then 'OK' else 'MAL' end
  union all select 9, '09 la lista de Personal de Comercial conserva los formularios que tenía (solo se sumó uno)',
         case when (select count(*) from campo.f_formularios_personal() x where x.clave in ('reporte_general', 'acta')) = 2
               and (select count(*) from campo.f_formularios_personal() x where x.clave = 'activo_campo') = 1 then 'OK' else 'MAL' end
  union all select 10, '10 Etapa 2: la capa «Por levantar» del geovisor (GeoJSON, solo geovisor completo) y el parámetro del aviso (levantar_naranja_dias)',
         case when exists (select 1 from redes.geovisor_capas where codigo = 'por_levantar' and activa and fuente = 'geojson' and solo_completo and not por_fecha)
               and exists (select 1 from tecnica.aviso_parametros where clave = 'levantar_naranja_dias' and area = 'distribucion') then 'OK' else 'MAL' end
  union all select 11, '11 tecnica.f_avisos sigue sin permisos para la API (la llama la RPC de avisos)',
         case when not has_function_privilege('anon', 'tecnica.f_avisos(boolean,boolean,timestamptz)', 'execute') and not has_function_privilege('authenticated', 'tecnica.f_avisos(boolean,boolean,timestamptz)', 'execute') then 'OK' else 'MAL' end
  union all select 12, 'INFO puntos por levantar: reportados · asignados · levantados · descartados',
         (select count(*) filter (where estado = 'reportado') || ' · ' || count(*) filter (where estado = 'asignado') || ' · ' || count(*) filter (where estado = 'levantado')
                 || ' · ' || count(*) filter (where estado = 'descartado') from redes.v_levantar_punto)
  union all select 13, 'INFO personas de Técnica con el formulario «Encontrar o reportar activo» asignado',
         (select count(*)::text from public.geoportal_lista_blanca lb where lb.activo and lb.ver_registro_tecnico and tecnica.f_formulario_asignado(lb.email, 'activo_campo'))
) t order by o;
