-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 · 80 — VERIFICACIÓN (SOLO LECTURA; una consulta, apta para el editor SQL web). Después de la migración: todo «OK».
-- =====================================================================
select k, valor, case when ok then 'OK' else 'REVISAR' end as estado from (
  select 1 as o, '1 huella de redes sin cambio' as k,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) as valor,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '1ba192724c2fddcf321104700829f3cc' as ok
  union all
  select 2, '2 formulario Caracterización (dominio, f_formularios, 7 días)', (select string_agg(clave, ',' order by orden) from tecnica.f_formularios() where orden >= 9),
         (select count(*) from tecnica.f_formularios()) = 10 and (select dias_atras_max from tecnica.formularios_config where formulario = 'ptar_caracterizacion') = 7
         and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') like '%ptar_caracterizacion%'
  union all
  select 3, '3 puntos de la PTAR', (select string_agg(codigo, ',' order by codigo) from tecnica.puntos where tipo = 'ptar'),
         (select count(*) from tecnica.puntos where tipo = 'ptar' and planta_id is null and codigo in ('PTAR-AFL', 'PTAR-EFL', 'PTAR-RIO-ARR', 'PTAR-RIO-ABJ')) = 4
  union all
  select 4, '4 variables ar_* y sus filas en la Caracterización', (select count(*) from tecnica.variables where codigo like 'ar\_%') || ' variables · '
           || (select count(*) from tecnica.formulario_variables where formulario = 'ptar_caracterizacion') || ' en el formulario',
         (select count(*) from tecnica.variables where codigo like 'ar\_%') = 9 and (select count(*) from tecnica.formulario_variables where formulario = 'ptar_caracterizacion' and alcance = 'por_punto' and tipo_punto = 'ptar') = 6
  union all
  select 5, '5 las funciones nuevas o reemplazadas son las del paquete (7)', (select count(*)::text from pg_proc p where p.oid::regprocedure::text in ('tecnica.f_formularios()', 'tecnica.f_tipo_punto_texto(text)', 'tecnica.f_autorizar_captura(text,text)', 'geoportal_tec_ptar_mapa(text,text)', 'geoportal_tec_ptar_elemento(text,text)', 'tecnica.f_parametros_punto(bigint,integer)', 'tecnica.f_estado_parametros(jsonb)')),
         (select count(*) from pg_proc p where p.oid::regprocedure::text in ('tecnica.f_formularios()', 'tecnica.f_tipo_punto_texto(text)', 'tecnica.f_autorizar_captura(text,text)', 'geoportal_tec_ptar_mapa(text,text)', 'geoportal_tec_ptar_elemento(text,text)', 'tecnica.f_parametros_punto(bigint,integer)', 'tecnica.f_estado_parametros(jsonb)') and md5(pg_get_functiondef(p.oid)) = case p.oid::regprocedure::text when 'tecnica.f_formularios()' then 'd6e83d926d8ef7f4646762b66a2dd716' when 'tecnica.f_tipo_punto_texto(text)' then '3d66602a3dd26d424d865c80e689ebc7' when 'tecnica.f_autorizar_captura(text,text)' then '772ba83aba78ec6a0e651f2c76aa8639' when 'geoportal_tec_ptar_mapa(text,text)' then 'eecfe4479a9c0794a8fb3d78eefd8ade' when 'geoportal_tec_ptar_elemento(text,text)' then '8f7bbf839b07f6e108648bab7dd110af' when 'tecnica.f_parametros_punto(bigint,integer)' then 'a4239b6ae07b63ec023f1f33970a42ad' when 'tecnica.f_estado_parametros(jsonb)' then 'a11b83ef822f261d8651667f7fd091a9' end) = 7
  union all
  select 6, '6 CHECK del tipo de punto con «ptar»', (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'tecnica.puntos'::regclass and c.conname = 'puntos_tipo_check'),
         (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'tecnica.puntos'::regclass and c.conname = 'puntos_tipo_check') like '%''ptar''%'
         and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'tecnica.formulario_variables'::regclass and c.conname = 'formulario_variables_tipo_punto_check') like '%''ptar''%'
  union all
  select 7, '7 sin referencias de la PTAR todavía (por definir)', (select count(*)::text from tecnica.referencias r join tecnica.variables v on v.id = r.variable_id where v.codigo like 'ar\_%'),
         not exists (select 1 from tecnica.referencias r join tecnica.variables v on v.id = r.variable_id where v.codigo like 'ar\_%')
  union all
  select 8, '8 pg-safeupdate: funciones con DELETE/UPDATE sin WHERE', (select count(*)::text from redes.f_funciones_sin_where()), not exists (select 1 from redes.f_funciones_sin_where())
) t order by o;
