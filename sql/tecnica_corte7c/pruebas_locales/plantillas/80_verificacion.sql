-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- =====================================================================
select k, v from (
  select 1 as o, '01 las 2 tablas nuevas con RLS y de solo inserción' as k,
         case when (select bool_and(relrowsecurity) from pg_class where oid in ('tecnica.quimico_remision_preparaciones'::regclass, 'tecnica.quimico_parametro_eventos'::regclass))
               and (select count(*) from pg_trigger where tgrelid in ('tecnica.quimico_remision_preparaciones'::regclass, 'tecnica.quimico_parametro_eventos'::regclass) and not tgisinternal) = 4 then 'OK' else 'MAL' end as v
  union all select 2, '02 ni anon, ni authenticated, ni service_role leen las tablas nuevas',
         case when not exists (select 1 from (values ('tecnica.quimico_remision_preparaciones'), ('tecnica.quimico_parametro_eventos')) t(n), (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                                where has_table_privilege(r.rol, t.n, 'select') or has_table_privilege(r.rol, t.n, 'insert')) then 'OK' else 'MAL' end
  union all select 3, '03 las 3 RPC nuevas y las 2 reemplazadas: security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_tec_quimico_remision_preparar', 'geoportal_tec_quimico_parametros', 'geoportal_tec_quimico_parametro_fijar', 'geoportal_tec_quimico_entrada', 'geoportal_tec_quimico_historial')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 5 then 'OK' else 'MAL' end
  union all select 4, '04 las 2 funciones internas nuevas no las ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.oid in ('tecnica.f_remision_subida(text,text)'::regprocedure, 'tecnica.f_qparam_editable(text)'::regprocedure)
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 5, '05 huellas md5 de las 2 reemplazadas y de las 5 nuevas',
         case when (select count(*) from (values {{CAMBIADAS_7C}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 2
               and (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 5 then 'OK' else 'MAL' end
  union all select 6, '06 la foto de la remisión: columna nula por omisión, solo en entradas, una foto por entrada; ningún movimiento anterior la tiene sin ser entrada',
         case when (select is_nullable = 'YES' and column_default is null from information_schema.columns where table_schema = 'tecnica' and table_name = 'quimico_movimientos' and column_name = 'remision_foto')
               and exists (select 1 from pg_constraint where conrelid = 'tecnica.quimico_movimientos'::regclass and conname = 'quimico_movimientos_remision_foto_ck')
               and to_regclass('tecnica.ux_qmov_remision_foto') is not null
               and not exists (select 1 from tecnica.quimico_movimientos where remision_foto is not null and tipo <> 'entrada') then 'OK' else 'MAL' end
  union all select 7, '07 los parámetros están en su rango y cada cambio hecho por pantalla tiene su evento con motivo y autor',
         case when not exists (select 1 from tecnica.quimico_parametros where valor < minimo or valor > maximo)
               and not exists (select 1 from tecnica.quimico_parametro_eventos e where length(btrim(e.motivo)) < 10 or position('@' in e.autor) < 2) then 'OK' else 'MAL' end
  union all select 8, '08 pg-safeupdate: ninguna función de redes, tecnica, geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 9, 'INFO huella del conjunto de funciones de redes (este corte no la cambia: debe ser la misma de antes de migrar; 4a46069f… con el 9a publicado)',
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
  union all select 10, 'INFO parámetros (desvío % · marca · días atrás uso · días atrás entrada) · cambios hechos · entradas con foto de la remisión',
         (select string_agg(valor::text, ' · ' order by case clave when 'desvio_pct' then 1 when 'marca_esperado_usado' then 2 when 'dias_atras_uso' then 3 else 4 end)
            from tecnica.quimico_parametros where tecnica.f_qparam_editable(clave)) || ' · ' || (select count(*) from tecnica.quimico_parametro_eventos) || ' · ' ||
         (select count(*) from tecnica.quimico_movimientos where remision_foto is not null)
) t order by o;
