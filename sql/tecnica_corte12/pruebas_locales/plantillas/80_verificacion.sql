-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 80 — VERIFICACIÓN DESPUÉS DE LA MIGRACIÓN (solo lectura; una sola consulta). Todas las filas deben decir OK.
-- Generada por pruebas_locales/generar.py.
-- =====================================================================
with nue(firma, nueva) as (values {{NUEVAS}})
select '1 las 16 funciones nuevas con su huella' as que, case when (select count(*) from nue where md5(pg_get_functiondef(to_regprocedure(firma))) = nueva) = {{N_NUEVAS}} then 'OK' else 'FALLA' end as resultado
union all select '2 las 5 tablas y la vista', case when (select count(*) from unnest(array[{{TABLAS}}]) t where to_regclass(t) is not null) = 6 then 'OK' else 'FALLA' end
union all select '3 los 15 plazos y mínimos con los valores de David', case when (select count(*) from tecnica.aviso_parametros) = 15
     and (select string_agg(clave || '=' || valor, ',' order by orden) from tecnica.aviso_parametros)
       = 'horario_inicio=8,horario_fin=18,planta_primer_registro_hora=10,planta_horas_sin_registro=4,quimicos_dias_revisar=3,dano_alto_naranja_h=2,dano_alto_rojo_h=6,dano_medio_naranja_h=24,dano_medio_rojo_h=72,dano_bajo_naranja_h=72,dano_bajo_rojo_h=168,dano_sin_itv_dias=30,l116_registrado_dias=3,carga_abierta_horas=24,salida_max_intentos=5'
     then 'OK' else 'FALLA' end
union all select '4 nada de prueba quedó: eventos, mínimos y cola vacíos', case when not exists (select 1 from tecnica.aviso_parametro_eventos) and not exists (select 1 from tecnica.quimico_minimo_eventos)
     and not exists (select 1 from tecnica.avisos_salida) then 'OK' else 'FALLA' end
union all select '5 permisos: service_role solo las 5 RPC; anon y authenticated nada; nadie de la API lee las tablas', case when
     (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_tec_avisos', 'geoportal_tec_avisos_parametros', 'geoportal_tec_aviso_parametro_fijar', 'geoportal_tec_quimico_minimos', 'geoportal_tec_quimico_minimo_fijar')
       and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')) = 5
     and not has_function_privilege('service_role', 'tecnica.f_avisos(boolean,boolean,timestamp with time zone)', 'execute') and not has_function_privilege('service_role', 'tecnica.avisos_tomar(integer,integer)', 'execute')
     and not exists (select 1 from unnest(array[{{TABLAS}}]) t, unnest(array['anon', 'authenticated', 'service_role']) r where has_table_privilege(r, t, 'select') or has_table_privilege(r, t, 'insert'))
     then 'OK' else 'FALLA' end
union all select '6 rol dell_avisos: sin login, 2 conexiones, solo tomar, marcar y liberar', case when (select not rolcanlogin and rolconnlimit = 2 from pg_roles where rolname = 'dell_avisos')
     and has_function_privilege('dell_avisos', 'tecnica.avisos_tomar(integer,integer)', 'execute') and has_function_privilege('dell_avisos', 'tecnica.avisos_liberar(uuid,uuid)', 'execute')
     and not has_function_privilege('dell_avisos', 'public.geoportal_tec_avisos(text)', 'execute') and not has_table_privilege('dell_avisos', 'tecnica.avisos_salida', 'select') then 'OK' else 'FALLA' end
union all select '7 pg-safeupdate: ninguna función de redes, tecnica, geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE', case when not exists (select 1 from redes.f_funciones_sin_where()) then 'OK' else 'FALLA' end
union all select '8 el conjunto de funciones de redes no cambió (informativo si ya se publicó otro corte de redes): ' || (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
        where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')),
     case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
        where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{CONJ}}' then 'OK' else 'OTRO (avise)' end
order by 1;
