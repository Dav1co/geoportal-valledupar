-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1: simulación de cierre) · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas). No simula nada (no crea tablas temporales).
-- Nota: después del 9b, la fila 03 de la verificación del 10 deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 8 RPC nuevas (simulación y cierre real): security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_simulacion_cierre', 'geoportal_redes_simulacion_guardar', 'geoportal_redes_simulaciones', 'geoportal_redes_valvula_maniobra',
                                       'geoportal_redes_corte_regreso', 'geoportal_redes_cortes_vigentes', 'geoportal_redes_cortes_recalcular', 'geoportal_redes_geovisor_mvt_cortes')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 8 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las 10 nuevas); tecnica.f_avisos tampoco',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')))
                and not has_function_privilege('service_role', 'tecnica.f_avisos(boolean,boolean,timestamp with time zone)', 'execute') then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las 2 reemplazadas (f_param_entero y tecnica.f_avisos), de las 18 nuevas y del conjunto de funciones de redes del 9b',
         case when (select count(*) from (values ('redes.f_param_entero(text)', '45e46bf5fa65c38c0cd95a9bfafb3d90'), ('tecnica.f_avisos(boolean,boolean,timestamp with time zone)', '898bafa5adddfcc08d65adf138d0114a')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 2
               and (select count(*) from (values ('redes.f_sim_grafo()', '0439fdbc6b8615d29f3ecbe7b0a97a61'), ('redes.f_sim_llenar_agua()', 'b0ae7f1b6f3dfc72c90d4c42082e8a2b'), ('redes.f_sim_escenario(bigint[],bigint,boolean,bigint[],geometry,integer)', '77c9456adc4de3337d369514398a9331'), ('redes.f_simular_cierre(bigint)', '1ea9ec75226bd0592d0f85a9c1513feb'), ('redes.f_sim_tramo_cercano(numeric,numeric)', '2c20d924a65420a23e5eaac3d7508074'), ('redes.f_sim_autorizar(text)', 'a51058c0b84d12517137f8f0eded944f'), ('public.geoportal_redes_simulacion_cierre(text,text,numeric,numeric)', 'c4b6b565b8b8de5fdd2106e459bbefcf'), ('public.geoportal_redes_simulacion_guardar(text,text,text)', '3585f16c7aa0933645c984723ba62b47'), ('public.geoportal_redes_simulaciones(text,text)', '1df51d05cc0d0f6ef20bc0d88b025704'), ('redes.f_cierres_vigentes()', '7919dabebc2a167efc2a0a5c9449cfc0'), ('redes.f_cierre_regreso(bigint)', 'dd179750ee880cd33954da6c6ba3ad21'), ('redes.f_cortes_foto(bigint,text,text)', '5e0796a8a83e41bd005cb7a941b61f40'), ('redes.f_cortes_para_avisos(timestamp with time zone,numeric,numeric)', '0d0a66c1842d8f2fc65f47f430cbd10a'), ('public.geoportal_redes_valvula_maniobra(text,text,text,text,text,text,text)', 'c17b23590b8af31d574f593aaeb8c781'), ('public.geoportal_redes_corte_regreso(text,text,text,text)', '164a24157f1e2fef6a521487b8799cea'), ('public.geoportal_redes_cortes_vigentes(text)', 'c09eadccc9399bb27b78dfb0ad14c8f8'), ('public.geoportal_redes_cortes_recalcular(text,text)', 'fb6ff311cfa2527061a7e5149d736e5b'), ('public.geoportal_redes_geovisor_mvt_cortes(text,integer,integer,integer)', '05008c9d4c4a07d932829f1924d29115')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 18
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '895517fb68f74d6d6c20079c83bdf7c4' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 las 6 tablas del 9b: nadie de la API las lee ni las escribe; son de solo agregar (con sus 2 disparadores cada una)',
         case when (select count(*) from pg_class c where c.relnamespace = 'redes'::regnamespace
                     and c.relname in ('simulaciones_cierre', 'valvula_maniobras', 'corte_fotos', 'corte_foto_zonas', 'corte_foto_tramos', 'corte_foto_valvulas') and c.relrowsecurity
                     and not exists (select 1 from aclexplode(c.relacl) x where x.grantee in (0, (select oid from pg_roles where rolname = 'anon'),
                                    (select oid from pg_roles where rolname = 'authenticated'), (select oid from pg_roles where rolname = 'service_role')))) = 6
               and (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'redes'::regnamespace
                     and c.relname in ('simulaciones_cierre', 'valvula_maniobras', 'corte_fotos', 'corte_foto_zonas', 'corte_foto_tramos', 'corte_foto_valvulas')
                     and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 12 then 'OK' else 'MAL' end
  union all select 6, '06 las tablas del 9b no tienen columnas de personas (suscriptor, nombre, teléfono, dirección, cédula)',
         case when not exists (select 1 from information_schema.columns where table_schema = 'redes'
                                and table_name in ('simulaciones_cierre', 'valvula_maniobras', 'corte_fotos', 'corte_foto_zonas', 'corte_foto_tramos', 'corte_foto_valvulas')
                                and column_name ~ 'suscriptor|nombre|telefono|celular|direccion|cedula|propietario') then 'OK' else 'MAL' end
  union all select 7, '07 los 7 parámetros de la simulación, vigentes, con unidad entera',
         case when (select count(*) from redes.parametros where clave in ('sim_segmento_grande_tramos', 'sim_segmento_grande_contratos', 'sim_no_cierra_max', 'sim_valvulas_lista_max', 'sim_contratos_guardar_max', 'sim_guardadas_max', 'corte_horas_atras_max') and estado = 'vigente' and valor is not null and redes.f_param_entero(unidad)) = 7 then 'OK' else 'MAL' end
  union all select 8, '08 los 2 parámetros del aviso «válvula cerrada» en Avisos (6 h naranja y 12 h rojo al publicar)',
         case when (select count(*) from tecnica.aviso_parametros where clave in ('valvula_cerrada_naranja_h', 'valvula_cerrada_rojo_h') and area = 'distribucion') = 2 then 'OK' else 'MAL' end
  union all select 10, 'INFO válvulas cerradas ahora · zonas sin agua · contratos afectados (última foto)',
         coalesce((select f.valvulas_cerradas || ' · ' || f.zonas || ' · ' || (f.contratos_cerrados + f.contratos_afectados) from redes.corte_fotos f order by f.id desc limit 1), 'ninguna maniobra todavía')
  union all select 11, 'INFO simulaciones guardadas · con daño · con intervención',
         (select count(*) || ' · ' || count(dano_id) || ' · ' || count(intervencion_id) from redes.simulaciones_cierre)
  union all select 12, 'INFO red de acueducto: tramos en operación · válvulas como nodos · con efecto «cierra» · «sin definir» · contratos con tramo',
         (select count(*) from redes.activo_vigente_mat where sistema = 'acueducto' and prefijo in ('RED', 'CON') and cuenta_vigente and not retirado) || ' · '
         || (select count(*) from redes.nodos n join redes.activo_vigente_mat m on m.activo_id = n.activo_id where m.prefijo = 'VAL') || ' · '
         || (select count(*) from redes.activo_vigente_mat where prefijo = 'VAL' and efecto = 'cierra') || ' · '
         || (select count(*) from redes.activo_vigente_mat where prefijo = 'VAL' and coalesce(efecto, 'sin_definir') = 'sin_definir') || ' · '
         || (select count(*) from redes.contrato_tramo)
) t order by o;
