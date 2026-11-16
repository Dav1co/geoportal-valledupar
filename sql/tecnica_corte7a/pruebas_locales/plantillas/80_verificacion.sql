-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 7a, la fila 04 de la verificación del 6c dice MAL a propósito (el conjunto de funciones cambió); esta la reemplaza.
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
  union all select 5, '05 huellas md5 de las 11 RPC nuevas, de las 4 reemplazadas y del conjunto de funciones de redes del 7a',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) = {{N_RPC}}
               and (select count(*) from (values {{CAMBIADAS_7A}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_CAMBIADAS}}
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_CORTE_7A}}' then 'OK' else 'MAL' end
  union all select 6, '06 tecnica.quimicos: rol con «auxiliar», candado de identidad y los de siempre; hipoclorito de calcio; PAC y cloro de potabilización',
         case when (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'tecnica.quimicos'::regclass and conname = 'quimicos_rol_check') like '%auxiliar%'
               and (select count(*) from pg_trigger where tgrelid = 'tecnica.quimicos'::regclass and tgname in ('t_quimico_identidad', 't_quimico_protegido', 't_no_borrar') and not tgisinternal) = 3
               and exists (select 1 from tecnica.quimicos where codigo = 'hipoclorito_calcio')
               and (select count(*) from tecnica.v_quimico_vigente where potabilizacion and codigo in ('pac', 'cloro_gaseoso')) = 2 then 'OK' else 'MAL' end
  union all select 7, '07 el bucket tecnica-evidencias es privado (PDF y JPEG, 5 MB) y no tiene políticas en storage.objects',
         case when (select not public and file_size_limit = 5242880 and allowed_mime_types @> array['application/pdf', 'image/jpeg'] from storage.buckets where id = 'tecnica-evidencias')
               and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and (qual like '%tecnica-evidencias%' or with_check like '%tecnica-evidencias%')) then 'OK' else 'MAL' end
  union all select 8, '08 respuestas al 6b: estados del contrato (suspendido y cortado) y el muestreo a 35 días',
         case when redes.f_estado_contrato('SUSPENDIDO') = 'suspendido' and redes.f_estado_contrato('CORTADO') = 'cortado' and to_regclass('redes.contratos_capa') is null
               and (select valor from redes.parametros where clave = 'geovisor_muestreo_dias') = 35 then 'OK' else 'MAL' end
  union all select 9, '09 cada movimiento cuadra: kg = cantidad (× 1.000 si son toneladas), con signo (el uso resta)',
         case when not exists (select 1 from tecnica.quimico_movimientos m
                                where m.tipo in ('entrada', 'inventario_inicial') and m.cantidad_kg <> case m.unidad when 't' then m.cantidad * 1000 else m.cantidad end
                                   or m.tipo = 'uso' and m.cantidad_kg <> -case m.unidad when 't' then m.cantidad * 1000 else m.cantidad end) then 'OK' else 'MAL' end
  union all select 10, '10 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni public.geoportal_tec_* (químicos incluidos) con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 11, '11 la configuración del geovisor trae la fecha del último corte de la cartera (nota de la capa de contratos) y sigue de solo lectura (STABLE)',
         case when (select p.provolatile = 's' and p.prosrc like '%contratos_corte%' from pg_proc p where p.oid = 'public.geoportal_redes_geovisor(text)'::regprocedure) then 'OK' else 'MAL' end
  union all select 12, 'INFO desvío de esperado contra usado (%) · unidades de la entrada · último corte de la cartera',
         (select valor::text from tecnica.quimico_parametros where clave = 'desvio_pct') || ' · ' ||
         (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'tecnica.quimico_movimientos'::regclass and pg_get_constraintdef(oid) like '%unidad = ANY%') || ' · ' ||
         coalesce((select max(periodo_carga) from public.cartera_suscripcion), 'sin cartera')
  union all select 13, 'INFO químicos (activos · de potabilización · con ficha en PDF · con dosis óptima) · movimientos · saldo de PAC (kg)',
         (select count(*) filter (where activo) || ' · ' || count(*) filter (where potabilizacion) || ' · ' || count(ficha_ruta) || ' · ' || count(dosis_optima_ppm) from tecnica.v_quimico_vigente)
         || ' · ' || (select count(*) from tecnica.quimico_movimientos) || ' · ' || coalesce((select saldo_kg::text from tecnica.v_quimico_saldo where codigo = 'pac'), 'sin inventario inicial')
) t order by o;
