-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 7a, la fila 05 de la verificación del 6b dice MAL a propósito (el conjunto de funciones cambió); esta la reemplaza.
-- =====================================================================
select k, v from (
  select 1 as o, '01 tablas nuevas de químicos con RLS; eventos y movimientos de solo inserción; parámetros que no se borran' as k,
         case when (select bool_and(relrowsecurity) from pg_class where oid in (to_regclass('tecnica.quimico_ficha_eventos'), to_regclass('tecnica.quimico_ficha_preparaciones'),
                                                                              to_regclass('tecnica.quimico_movimientos'), to_regclass('tecnica.quimico_parametros')))
               and (select count(*) from pg_trigger where tgrelid in (to_regclass('tecnica.quimico_ficha_eventos'), to_regclass('tecnica.quimico_movimientos'), to_regclass('tecnica.quimico_parametros')) and not tgisinternal) = 5
              then 'OK' else 'MAL' end as v
  union all select 2, '02 ni anon, ni authenticated, ni service_role leen ni escriben las tablas y vistas nuevas',
         case when not exists (select 1 from (values ('tecnica.quimico_ficha_eventos'), ('tecnica.quimico_ficha_preparaciones'), ('tecnica.quimico_movimientos'), ('tecnica.quimico_parametros'),
                                                     ('tecnica.v_quimico_vigente'), ('tecnica.v_quimico_saldo')) t(n), (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                                where has_table_privilege(r.rol, t.n, 'select') or has_table_privilege(r.rol, t.n, 'insert')) then 'OK' else 'MAL' end
  union all select 3, '03 las 11 RPC nuevas y las 2 reemplazadas: security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and (p.proname like 'geoportal\_tec\_quimic%' and p.proname <> 'geoportal_tec_listar_quimicos' or p.proname = 'geoportal_redes_contrato_tarjeta')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 12 then 'OK' else 'MAL' end
  union all select 4, '04 las funciones internas nuevas (tecnica) y las de redes no las ejecuta la API',
         case when not exists (select 1 from pg_proc p where (p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'tecnica'::regnamespace and p.proname in
                                  ('f_qparam', 'f_quimico_por_codigo', 'f_ficha_subida', 'f_dosis_optima_en', 'f_dia_movimiento', 'f_quimico_identidad')))
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')))
              then 'OK' else 'MAL' end
  union all select 5, '05 huellas md5 de las 11 RPC nuevas, de las 2 reemplazadas y del conjunto de funciones de redes del 7a',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_tec_quimico_ajuste', '4ff08adcd3140c1da41827af1811727a'), ('geoportal_tec_quimico_crear', '851c1a8e7ba351bc3fb5d7fd53a2e8e0'), ('geoportal_tec_quimico_entrada', '9daf6b0ef659b44d30a9260b003e0a31'), ('geoportal_tec_quimico_ficha_preparar', '1a28c7a420f0ad7a2f064ebc401fa369'), ('geoportal_tec_quimico_fijar', '2026b1ec6e6752b368063609e3b1a60c'), ('geoportal_tec_quimico_historial', '9112d90a773971bacfb9d69310b2da89'), ('geoportal_tec_quimico_inventario', 'dc9ecbbbc7ae91e6a5fdb5653ebc59cb'), ('geoportal_tec_quimico_uso', '146290c07b0befb3aca05fdf350b34db'), ('geoportal_tec_quimicos_catalogo', '27c5a7644b003c62f06bf478772d1e57'), ('geoportal_tec_quimicos_comparacion', 'edbc5521095974d4f289e1d4f395f2b6'), ('geoportal_tec_quimicos_formulario', '443e5fa3f77b76d618e7e09131da4185'))) = 11
               and (select count(*) from (values ('redes.f_estado_contrato(text)', '6bf7c182fb2998534baa81719912c37e'), ('public.geoportal_redes_contrato_tarjeta(text,text,text)', '32d43e65e8c7ff30baa209469915ed87')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 2
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = 'f6c14c268aaedb5ab243f87685b428dd' then 'OK' else 'MAL' end
  union all select 6, '06 tecnica.quimicos: rol con «auxiliar», candado de identidad y los de siempre; hipoclorito de calcio; PAC y cloro de potabilización',
         case when (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'tecnica.quimicos'::regclass and conname = 'quimicos_rol_check') like '%auxiliar%'
               and (select count(*) from pg_trigger where tgrelid = 'tecnica.quimicos'::regclass and tgname in ('t_quimico_identidad', 't_quimico_protegido', 't_no_borrar') and not tgisinternal) = 3
               and exists (select 1 from tecnica.quimicos where codigo = 'hipoclorito_calcio')
               and (select count(*) from tecnica.v_quimico_vigente where potabilizacion and codigo in ('pac', 'cloro_gaseoso')) = 2 then 'OK' else 'MAL' end
  union all select 7, '07 el bucket tecnica-evidencias es privado (PDF y JPEG, 5 MB) y no tiene políticas en storage.objects',
         case when (select not public and file_size_limit = 5242880 and allowed_mime_types @> array['application/pdf', 'image/jpeg'] from storage.buckets where id = 'tecnica-evidencias')
               and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and (qual like '%tecnica-evidencias%' or with_check like '%tecnica-evidencias%')) then 'OK' else 'MAL' end
  union all select 8, '08 respuestas al 6b: estados del contrato (suspendido y cortado) y el muestreo a 35 días',
         case when (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'redes.contratos_capa'::regclass and conname = 'contratos_capa_estado_check') like '%cortado%'
               and (select valor from redes.parametros where clave = 'geovisor_muestreo_dias') = 35 then 'OK' else 'MAL' end
  union all select 9, '09 cada movimiento cuadra: kg = cantidad (× 1.000 si son toneladas), con signo (el uso resta)',
         case when not exists (select 1 from tecnica.quimico_movimientos m
                                where m.tipo in ('entrada', 'inventario_inicial') and m.cantidad_kg <> case m.unidad when 't' then m.cantidad * 1000 else m.cantidad end
                                   or m.tipo = 'uso' and m.cantidad_kg <> -case m.unidad when 't' then m.cantidad * 1000 else m.cantidad end) then 'OK' else 'MAL' end
  union all select 10, 'INFO químicos (activos · de potabilización · con ficha en PDF · con dosis óptima) · movimientos · saldo de PAC (kg)',
         (select count(*) filter (where activo) || ' · ' || count(*) filter (where potabilizacion) || ' · ' || count(ficha_ruta) || ' · ' || count(dosis_optima_ppm) from tecnica.v_quimico_vigente)
         || ' · ' || (select count(*) from tecnica.quimico_movimientos) || ' · ' || coalesce((select saldo_kg::text from tecnica.v_quimico_saldo where codigo = 'pac'), 'sin inventario inicial')
) t order by o;
