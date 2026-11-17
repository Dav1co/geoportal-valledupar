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
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 15 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las 5 reemplazadas, de las 18 nuevas y del conjunto de funciones de redes del 14',
         case when (select count(*) from (values ('public.geoportal_redes_mi_perfil(text)', 'e3ca21b7b39667d0ab1566945091e5cd'), ('campo.f_formularios_personal()', '283a63c1ee3fad9e5956a65f8a4644b6'), ('public.geoportal_redes_geovisor_capa(text,text,date,date)', '906724ad57340fdcc44d718f7c0a33e7'), ('tecnica.f_avisos(boolean,boolean,timestamptz)', 'b7ec2303f95153684963ded7bdb0a5c0'), ('public.geoportal_redes_geovisor(text)', 'c10f6049c8dd5310cac885b59e22c2c9')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 5
               and (select count(*) from (values ('public.geoportal_redes_geovisor_mvt_remuneracion(text,integer,integer,integer)', '14298af247824fc469bbc9e6c8e05efb'), ('public.geoportal_redes_levantar_cerca(text,numeric,numeric,numeric,text)', '5c71a3b9e07e272889053aa85cc6d98c'), ('public.geoportal_redes_levantar_crear(text,uuid,jsonb,text)', '09d88de65df1238dc373a3500b6b1f3a'), ('public.geoportal_redes_levantar_evento(text,text,text,text,text,text)', '35105af251ffaa62aec4121b6c27d967'), ('public.geoportal_redes_levantar_ficha(text,text)', 'e95e990d7fba78671e071dec31c82950'), ('public.geoportal_redes_levantar_fotos(text,text,text)', '1a6e3335fb52027cd000ebbeb3ae7086'), ('public.geoportal_redes_levantar_hoja(text,text,text)', '73a119ce305683abcd946bae93f2024c'), ('public.geoportal_redes_levantar_inicio(text)', '6224656efc6267fcf540b978618afcf7'), ('public.geoportal_redes_levantar_lista(text,text,text,integer)', 'd93c1a02106798ef5230d2b922f35aae'), ('public.geoportal_redes_levantar_preparar(text,integer)', '032583d085ad2574018180fd96f911ab'), ('public.geoportal_redes_remuneracion(text)', 'e8b5d12973516a9f274d186a0349cfce'), ('public.geoportal_redes_remuneracion_tarjeta(text,text)', '920f0a86e85ba3ac238c06042481cdfb'), ('redes.f_levantar_acceso(text)', '69298852e18084d8857cd225180b908a'), ('redes.f_levantar_estado_nombre(text)', 'b4a5e88be2ad8bcd31fab2ab524c896c'), ('redes.f_levantar_puede(text)', '460b91b2eb72f0e4fbe6833c5a80890b'), ('redes.f_levantar_quien(text)', 'c69f713e91680287d454dbf1085e56fc'), ('redes.f_levantar_tipo_nombre(text)', '45417609f57adb1b7928b9ae5f8be179'), ('redes.f_remuneracion_estado(boolean,boolean,boolean)', '74fad162a44190520b6154014bb26875')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 18
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '1a9ef250a74fb01962f463d98834cc4a' then 'OK' else 'MAL' end
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
         case when (select count(*) from redes.parametros where clave in ('levantar_radio_min_m', 'levantar_radio_max_m', 'levantar_duplicado_m', 'levantar_lista_max', 'levantar_propuesta_m', 'levantar_hoja_max') and estado = 'vigente' and valor is not null) = 6
               and exists (select 1 from redes.consecutivos where prefijo = 'LEV') then 'OK' else 'MAL' end
  union all select 8, '08 el formulario «Encontrar o reportar activo»: en el dominio de Técnica, en Personal de distribución y en la lista de Personal de Comercial',
         case when 'activo_campo'::tecnica.formulario_clave is not null and exists (select 1 from redes.formularios_distribucion where clave = 'activo_campo' and activo)
               and exists (select 1 from campo.f_formularios_personal() x where x.clave = 'activo_campo')
               and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_eventos_formulario_check') = 'CHECK (((formulario IS NULL) OR (formulario ~ ''^(reporte_general|acta|activo_campo|tipo:[a-z][a-z0-9_]{1,59})$''::text)))'
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
