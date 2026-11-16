-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 9a-bis, la fila 04 de la verificación del 9a deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 2 RPC nuevas y las reemplazadas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_sector_en', 'geoportal_redes_nodos_clasificar_grupo', 'geoportal_redes_tramo_nodos', 'geoportal_redes_nodo_crear_activo',
                                       'geoportal_redes_nodos_por_clasificar', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_nodo_clasificar', 'geoportal_redes_danos',
                                       'geoportal_redes_intervenciones', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_referencia', 'geoportal_redes_mi_perfil',
                                       'geoportal_redes_crear_dano', 'geoportal_redes_reporte_convertir')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 14 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las 5 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las 14 reemplazadas, de las 7 nuevas y del conjunto de funciones de redes del 9a-bis',
         case when (select count(*) from (values ('redes.f_ficha(bigint,text)', '02f80b8677c84b8a9d2e3a21141da695'), ('public.geoportal_redes_tramo_nodos(text,text)', '3fccc4ad74d0375936f31abf30499fe9'), ('public.geoportal_redes_nodo_crear_activo(text,bigint,text,text,text,text)', 'a419c44a32af2d793c941c46cc2d4a53'), ('public.geoportal_redes_nodo_preliminar(text,bigint)', 'bdc48ca0996c21288c4588855d77fe0c'), ('public.geoportal_redes_nodo_clasificar(text,bigint,text,text)', '989ccc3191317c17d6d523156a74b009'), ('public.geoportal_redes_nodos_por_clasificar(text,text,bigint,integer)', 'ff869315491308180071dba3a9608e5b'), ('redes.f_pm_sugerencia(text,text,text,text)', '4ba75667ca567f4ff62bcd35e3e6ed60'), ('public.geoportal_redes_danos(text,text,integer)', '8a76f015aace5d2b51b74fd7411d191e'), ('public.geoportal_redes_intervenciones(text,text,integer)', 'ee6d1e0f784870673b3789e92e1e30ac'), ('public.geoportal_redes_contrato_tarjeta(text,text,text)', '9b49d7546cd9092cd8e54f3cf9edfd90'), ('public.geoportal_redes_referencia(text,text,text)', '50abc61c89fd96a961535c91a7a3d858'), ('public.geoportal_redes_mi_perfil(text)', '5cca0e645a5e106529382ed51e1519e9'), ('public.geoportal_redes_crear_dano(text,uuid,jsonb,text)', 'f6578d1011d2ccb8431881ab576a4a6b'), ('public.geoportal_redes_reporte_convertir(text,uuid,jsonb)', 'c51e28695635e028403f0c85c7ded5f9')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 14
               and (select count(*) from (values ('redes.f_nodo_visible_id(bigint)', '27595e1f4a61b6dc9f6e4c22c56f660b'), ('redes.f_nodo_de_activo(bigint)', '26712634417f839dca7a5f54cfd1a3e6'), ('redes.f_tramos_de_nodo(bigint)', '80a2bc06e0cc217a4661f294bdbcc676'), ('redes.f_sector_en(numeric,numeric)', '1c5ee3d6e546d98829da333c44726fa7'), ('redes.f_operador_redes(text)', 'bded76df80afb3cda7ba97be91f7341e'), ('public.geoportal_redes_sector_en(text,numeric,numeric)', 'c41099b5b868b9ce8b58a51a4c98aa28'), ('public.geoportal_redes_nodos_clasificar_grupo(text,text,text,text)', '48f999ac9d51e2fdc327a1d87515c161')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 7
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '814eac39ac5deae2943751b8c190f969' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 la ficha y el minimapa ya no leen las vistas enteras de nodos y tramos (ninguna función de redes busca en ellas por una columna que no es su llave)',
         case when not exists (select 1 from pg_proc p where (p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
                                and (p.prosrc ~ 'v_tramo_nodos_vigente' or p.prosrc ~ 'v_nodo_visible n where n\.(nodo_id|activo_id) =' or p.prosrc ~ 'v_nodo_visible where nodo_id =')) then 'OK' else 'MAL' end
  union all select 6, '06 «sector_plan» ya no sale en ninguna función: el sector hidráulico (por la ubicación) es el oficial',
         case when not exists (select 1 from pg_proc p where (p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
                                and p.prosrc ~ '''sector_plan''') then 'OK' else 'MAL' end
  union all select 7, '07 la capa de sectores dice que son los sectores con que se opera (nota nueva)',
         case when (select nombre || '|' || nota from redes.geovisor_capas where codigo = 'sectores') like 'Sectores hidráulicos|7 sectores y 29 subsectores con que se opera%' then 'OK' else 'MAL' end
  union all select 8, 'INFO sectores vigentes (SEC): en operación · proyectados (después de carga_sectores/sectores_oficiales.sql: 36 · 0) · nodos por clasificar · clasificados sin activo',
         (select count(*) filter (where estado_codigo = 'en_operacion') || ' · ' || count(*) filter (where estado_codigo = 'proyectado') from redes.activo_vigente_mat where prefijo = 'SEC' and not retirado)
         || ' · ' || (select count(*) from redes.v_nodo_vigente where clase_nodo = 'por_clasificar')
         || ' · ' || (select count(*) from redes.v_nodo_vigente where clase_nodo in ('nodo_calculo', 'propuesta_plan'))
) t order by o;
