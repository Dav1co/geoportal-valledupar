-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1: simulación de cierre) · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas). No simula nada (no crea tablas temporales).
-- Nota: después del 9b, la fila 03 de la verificación del 10 deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 3 RPC nuevas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_simulacion_cierre', 'geoportal_redes_simulacion_guardar', 'geoportal_redes_simulaciones')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 3 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las 6 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de la 1 reemplazada, de las 9 nuevas y del conjunto de funciones de redes del 9b',
         case when (select count(*) from (values ('redes.f_param_entero(text)', '45e46bf5fa65c38c0cd95a9bfafb3d90')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 1
               and (select count(*) from (values ('redes.f_sim_grafo()', '0439fdbc6b8615d29f3ecbe7b0a97a61'), ('redes.f_sim_llenar_agua()', 'b0ae7f1b6f3dfc72c90d4c42082e8a2b'), ('redes.f_sim_escenario(bigint[],bigint,boolean,bigint[],geometry,integer)', '77c9456adc4de3337d369514398a9331'), ('redes.f_simular_cierre(bigint)', '1ea9ec75226bd0592d0f85a9c1513feb'), ('redes.f_sim_tramo_cercano(numeric,numeric)', '2c20d924a65420a23e5eaac3d7508074'), ('redes.f_sim_autorizar(text)', 'a51058c0b84d12517137f8f0eded944f'), ('public.geoportal_redes_simulacion_cierre(text,text,numeric,numeric)', 'c4b6b565b8b8de5fdd2106e459bbefcf'), ('public.geoportal_redes_simulacion_guardar(text,text,text)', '3585f16c7aa0933645c984723ba62b47'), ('public.geoportal_redes_simulaciones(text,text)', '1df51d05cc0d0f6ef20bc0d88b025704')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 9
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = 'beafb93a12ff2e4b306281692e62dd93' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 la tabla de simulaciones: nadie de la API la lee ni la escribe; es de solo agregar (con su disparador)',
         case when (select c.relrowsecurity and not exists (select 1 from aclexplode(c.relacl) x where x.grantee in (0, (select oid from pg_roles where rolname = 'anon'),
                                                             (select oid from pg_roles where rolname = 'authenticated'), (select oid from pg_roles where rolname = 'service_role')))
                     from pg_class c where c.oid = to_regclass('redes.simulaciones_cierre'))
               and (select count(*) from pg_trigger t where t.tgrelid = 'redes.simulaciones_cierre'::regclass and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 2 then 'OK' else 'MAL' end
  union all select 6, '06 la tabla de simulaciones no tiene columnas de personas (suscriptor, nombre, teléfono, dirección, cédula)',
         case when not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'simulaciones_cierre'
                                and column_name ~ 'suscriptor|nombre|telefono|celular|direccion|cedula|propietario') then 'OK' else 'MAL' end
  union all select 7, '07 los 6 parámetros de la simulación, vigentes, con unidad entera',
         case when (select count(*) from redes.parametros where clave in ('sim_segmento_grande_tramos', 'sim_segmento_grande_contratos', 'sim_no_cierra_max', 'sim_valvulas_lista_max', 'sim_contratos_guardar_max', 'sim_guardadas_max') and estado = 'vigente' and valor is not null and redes.f_param_entero(unidad)) = 6 then 'OK' else 'MAL' end
  union all select 8, 'INFO simulaciones guardadas · con daño · con intervención',
         (select count(*) || ' · ' || count(dano_id) || ' · ' || count(intervencion_id) from redes.simulaciones_cierre)
  union all select 9, 'INFO red de acueducto: tramos en operación · válvulas como nodos · con efecto «cierra» · «sin definir» · contratos con tramo',
         (select count(*) from redes.activo_vigente_mat where sistema = 'acueducto' and prefijo in ('RED', 'CON') and cuenta_vigente and not retirado) || ' · '
         || (select count(*) from redes.nodos n join redes.activo_vigente_mat m on m.activo_id = n.activo_id where m.prefijo = 'VAL') || ' · '
         || (select count(*) from redes.activo_vigente_mat where prefijo = 'VAL' and efecto = 'cierra') || ' · '
         || (select count(*) from redes.activo_vigente_mat where prefijo = 'VAL' and coalesce(efecto, 'sin_definir') = 'sin_definir') || ' · '
         || (select count(*) from redes.contrato_tramo)
) t order by o;
