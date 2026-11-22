-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 · 70 — PRUEBAS «N de N». Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción. Todo SIMULADO y se deshace.
-- Personas prueba.ptar3.*; una instalación de prueba (prueba_ptar3) con elementos PRUEBA3-*; un punto de muestreo de prueba (PRUEBA3-MUE). Las variables ar_* y los
-- puntos PTAR-* los crea esta migración: sus registros en la prueba son SOLO de la prueba. Termina con un ERROR a propósito.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · PTAR-3 … RESULTADO: N de N pruebas correctas — SIN FALLAS
-- =====================================================================
create temp table _r (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.reg(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as
$$ insert into _r (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $$;
create function pg_temp.err(p_nombre text, p_sql text, p_estado text default null, p_texto text default null) returns void language plpgsql as $$
declare v_e text; v_m text;
begin
  begin
    execute p_sql;
    perform pg_temp.reg(p_nombre, false, 'No falló y debía fallar');
  exception when others then
    get stacked diagnostics v_e = returned_sqlstate, v_m = message_text;
    perform pg_temp.reg(p_nombre, (p_estado is null or v_e = p_estado) and (p_texto is null or position(p_texto in v_m) > 0), 'SQLSTATE ' || v_e || ': ' || left(v_m, 200));
  end;
end $$;
create function pg_temp.registrar(p_quien text, p_punto text, p_valores jsonb, p_dias integer) returns jsonb language sql as $$
  select public.geoportal_tec_registrar_medicion(p_solicitante => p_quien, p_formulario => 'ptar_caracterizacion', p_planta => null, p_hora_muestra => '08:00',
           p_valores => p_valores, p_punto => p_punto, p_fecha_muestra => (clock_timestamp() at time zone 'America/Bogota')::date - p_dias) $$;
create function pg_temp.par(j jsonb, p_cod text) returns jsonb language sql as $$ select e from jsonb_array_elements(j -> 'indicadores') e where e ->> 'codigo' = p_cod $$;

do $prueba$
declare
  adm text := 'prueba.ptar3.adm@emdupar.gov.co'; sr text := 'prueba.ptar3.jefe@emdupar.gov.co'; sp text := 'prueba.ptar3.sp@emdupar.gov.co';
  sx text := 'prueba.ptar3.sx@emdupar.gov.co'; op text := 'prueba.ptar3.op@emdupar.gov.co'; op2 text := 'prueba.ptar3.op2@emdupar.gov.co';
  v_inst bigint; v_afl bigint; v_efl bigint; v_abj bigint; j jsonb; v_total integer; v_bien integer; v_fallas text;
  pt text := '{"type":"Point","coordinates":[-74.5,4.5]}';
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTPTAR3 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values
    (sr, 'ZTPTAR3 Jefe de la PTAR', 'consulta', true, true, 'sin_restriccion', 'todos'), (sp, 'ZTPTAR3 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos'),
    (sx, 'ZTPTAR3 Supervisor técnico', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values
    (op, 'ZTPTAR3 Operador de la PTAR', 'consulta', true, 'sin_restriccion', 'todos'), (op2, 'ZTPTAR3 Operador sin el formulario', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.alcance_eventos (persona, alcance, tipo_evento, motivo, autor) values (sr, 'ptar', 'asignar', 'PRUEBA3 jefe de la PTAR', adm),
    (sr, 'ptap', 'quitar', 'PRUEBA3 el jefe no ve la PTAP', adm), (sx, 'ptar', 'asignar', 'PRUEBA3 supervisor técnico con los dos', adm);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'ptar_caracterizacion', adm);
  select id into v_afl from tecnica.puntos where codigo = 'PTAR-AFL';
  select id into v_efl from tecnica.puntos where codigo = 'PTAR-EFL';
  select id into v_abj from tecnica.puntos where codigo = 'PTAR-RIO-ABJ';

  -- ---------- 01. Lo que crea el paquete ----------
  perform pg_temp.reg('01.01 la clave ptar_caracterizacion en el dominio (11 claves)', (select pg_get_constraintdef(c.oid) from pg_constraint c
    where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') like '%''activo_campo''::text, ''ptar_caracterizacion''::text]%');
  perform pg_temp.reg('01.02 f_formularios: las 9 de siempre, iguales, y «Caracterización» al final (orden 10)', (select count(*) from tecnica.f_formularios()) = 10
    and (select string_agg(clave || ':' || orden, ',' order by orden) from tecnica.f_formularios()) = 'entrada:1,salida:2,muestreo:3,danos_fallas:4,mantenimiento:5,uso_quimicos:6,entrada_quimicos:7,anomalia_compartida:8,revision_compartida:9,ptar_caracterizacion:10'
    and (select nombre from tecnica.f_formularios() where clave = 'ptar_caracterizacion') = 'Caracterización');
  perform pg_temp.reg('01.03 cuatro puntos de la PTAR, tipo ptar, sin planta de agua potable', (select count(*) from tecnica.puntos where codigo in ('PTAR-AFL', 'PTAR-EFL', 'PTAR-RIO-ARR', 'PTAR-RIO-ABJ')
    and tipo = 'ptar' and planta_id is null and activo) = 4);
  perform pg_temp.reg('01.04 nueve variables ar_* (caracterización y sonda) y ninguna referencia («por definir»)', (select count(*) from tecnica.variables where codigo like 'ar\_%') = 9
    and not exists (select 1 from tecnica.referencias r join tecnica.variables v on v.id = r.variable_id where v.codigo like 'ar\_%'));
  perform pg_temp.reg('01.05 Caracterización: 6 variables por punto (tipo ptar), ninguna obligatoria, en su orden', (select string_agg(v.codigo, ',' order by fv.orden) from tecnica.formulario_variables fv
    join tecnica.variables v on v.id = fv.variable_id where fv.formulario = 'ptar_caracterizacion' and fv.alcance = 'por_punto' and fv.tipo_punto = 'ptar' and not fv.obligatoria and fv.activa)
    = 'ar_caudal,ar_dbo5,ar_dqo,ar_sst,ar_nitrogeno_total,ar_fosforo_total');
  perform pg_temp.reg('01.06 Caracterización admite 7 días hacia atrás', (select dias_atras_max from tecnica.formularios_config where formulario = 'ptar_caracterizacion' and activa) = 7);
  perform pg_temp.reg('01.07 el texto del tipo de punto: «punto de la PTAR» (los de siempre no cambian)', tecnica.f_tipo_punto_texto('ptar') = 'punto de la PTAR'
    and tecnica.f_tipo_punto_texto('muestreo') = 'punto de muestreo' and tecnica.f_tipo_punto_texto('tanque') = 'tanque');
  perform pg_temp.err('01.08 un tipo de punto desconocido no entra', $$insert into tecnica.puntos (codigo, nombre, tipo) values ('PRUEBA3-X', 'PRUEBA3 X', 'laguna')$$, '23514');

  -- ---------- 02. La puerta de la captura con el alcance (D6) ----------
  perform pg_temp.reg('02.01 Caracterización: el jefe de la PTAR, el de los dos alcances, el administrador y el operador con el formulario', tecnica.f_autorizar_captura(sr, 'ptar_caracterizacion') = sr
    and tecnica.f_autorizar_captura(sx, 'ptar_caracterizacion') = sx and tecnica.f_autorizar_captura(adm, 'ptar_caracterizacion') = adm and tecnica.f_autorizar_captura(op, 'ptar_caracterizacion') = op);
  perform pg_temp.err('02.02 Caracterización: el supervisor de la PTAP (sin la PTAR) no', format('select tecnica.f_autorizar_captura(%L, %L)', sp, 'ptar_caracterizacion'), '42501', 'PTAR');
  perform pg_temp.err('02.03 Caracterización: el operador sin el formulario asignado no', format('select tecnica.f_autorizar_captura(%L, %L)', op2, 'ptar_caracterizacion'), '42501', 'asignado');
  perform pg_temp.err('02.04 Entrada (PTAP): el jefe de la PTAR (sin la PTAP) no', format('select tecnica.f_autorizar_captura(%L, %L)', sr, 'entrada'), '42501', 'PTAR');
  perform pg_temp.reg('02.05 Entrada (PTAP): el supervisor de planta y el de los dos, como siempre', tecnica.f_autorizar_captura(sp, 'entrada') = sp and tecnica.f_autorizar_captura(sx, 'salida') = sx);
  perform pg_temp.reg('02.06 lo de distribución no cambia: el jefe de la PTAR (supervisor) sigue pudiendo «Daños o fallas»', tecnica.f_autorizar_captura(sr, 'danos_fallas') = sr);

  -- ---------- 03. El formulario y el registro (las RPC de siempre, sin cambios) ----------
  j := public.geoportal_tec_obtener_formulario(sr, 'ptar_caracterizacion');
  perform pg_temp.reg('03.01 obtener_formulario: los 4 puntos de la PTAR, las 6 variables y 7 días hacia atrás', (select string_agg(e ->> 'codigo', ',' order by e ->> 'codigo') from jsonb_array_elements(j -> 'puntos') e)
    = 'PTAR-AFL,PTAR-EFL,PTAR-RIO-ABJ,PTAR-RIO-ARR' and jsonb_array_length(j -> 'variables') = 6 and (j ->> 'dias_atras_max')::integer = 7, (j - 'plantas')::text);
  j := pg_temp.registrar(sr, 'PTAR-AFL', '[{"variable":"ar_caudal","valor":"412.5"}]', 0);
  perform pg_temp.reg('03.02 el jefe registra solo el caudal del afluente (las de laboratorio no son obligatorias)', (j ->> 'guardados')::integer = 1, j::text);
  j := pg_temp.registrar(op, 'PTAR-AFL', '[{"variable":"ar_dbo5","valor":180},{"variable":"ar_dqo","valor":"390"},{"variable":"ar_sst","valor":"120"}]', 3);
  perform pg_temp.reg('03.03 el operador registra los resultados del laboratorio de hace 3 días', (j ->> 'guardados')::integer = 3
    and j ->> 'fecha_muestra' = ((clock_timestamp() at time zone 'America/Bogota')::date - 3)::text, j::text);
  perform pg_temp.err('03.04 más de 7 días atrás: no', format('select pg_temp.registrar(%L, %L, %L, 8)', sr, 'PTAR-EFL', '[{"variable":"ar_caudal","valor":1}]'), '22023', '7 días');
  insert into tecnica.puntos (codigo, nombre, tipo) values ('PRUEBA3-MUE', 'PRUEBA3 punto de muestreo', 'muestreo');
  perform pg_temp.err('03.05 un punto de muestreo de la red no sirve para la Caracterización', format('select pg_temp.registrar(%L, %L, %L, 0)', sr, 'PRUEBA3-MUE', '[{"variable":"ar_caudal","valor":1}]'),
    '22023', 'punto de la PTAR');
  perform pg_temp.err('03.06 el supervisor de la PTAP no registra la Caracterización', format('select pg_temp.registrar(%L, %L, %L, 0)', sp, 'PTAR-AFL', '[{"variable":"ar_caudal","valor":1}]'), '42501');
  perform pg_temp.err('03.07 una variable de la sonda no está en la Caracterización', format('select pg_temp.registrar(%L, %L, %L, 0)', sr, 'PTAR-AFL', '[{"variable":"ar_ph","valor":7}]'), '22023', 'no pertenece');

  -- ---------- 04. Parámetros y estado en la ficha y en el mapa ----------
  insert into tecnica.instalaciones (codigo, nombre, tipo, horas_sin_dato) values ('prueba_ptar3', 'PRUEBA3 PTAR', 'residual', 168) returning id into v_inst;
  insert into tecnica.elementos_planta (instalacion_id, codigo, tipo, nombre, geom, punto_id, origen, creado_por) values
    (v_inst, 'PRUEBA3-PM-AFL', 'punto_medicion', 'PRUEBA3 afluente', st_setsrid(st_geomfromgeojson(pt), 4326), v_afl, 'dibujo', adm),
    (v_inst, 'PRUEBA3-PM-EFL', 'punto_medicion', 'PRUEBA3 efluente', st_setsrid(st_geomfromgeojson(pt), 4326), v_efl, 'dibujo', adm),
    (v_inst, 'PRUEBA3-PM-ABJ', 'punto_medicion', 'PRUEBA3 río abajo', st_setsrid(st_geomfromgeojson(pt), 4326), v_abj, 'dibujo', adm),
    (v_inst, 'PRUEBA3-POZ', 'pozo', 'PRUEBA3 pozo', st_setsrid(st_geomfromgeojson(pt), 4326), null, 'dibujo', adm);
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA3-PM-AFL');
  perform pg_temp.reg('04.01 ficha del afluente: primero la sonda (pH, temperatura, OD) «sin registros», luego la Caracterización',
    (select string_agg(e ->> 'codigo', ',' order by n) from jsonb_array_elements(j -> 'indicadores') with ordinality x(e, n)) = 'ar_ph,ar_temperatura,ar_od,ar_caudal,ar_dbo5,ar_dqo,ar_sst,ar_nitrogeno_total,ar_fosforo_total'
    and (select bool_and(e ->> 'estado' = 'sin_registros' and e ->> 'grupo' = 'Sonda multiparámetro') from jsonb_array_elements(j -> 'indicadores') e where e ->> 'codigo' in ('ar_ph', 'ar_temperatura', 'ar_od')), j::text);
  perform pg_temp.reg('04.02 el último valor con su fecha: caudal 412,5 de hoy y DBO5 180 de hace 3 días, «sin referencia» (por definir)', (pg_temp.par(j, 'ar_caudal') ->> 'valor')::numeric = 412.5
    and pg_temp.par(j, 'ar_caudal') ->> 'estado' = 'sin_referencia' and (pg_temp.par(j, 'ar_dbo5') ->> 'valor')::numeric = 180 and pg_temp.par(j, 'ar_dbo5') ->> 'muestra_ts' is not null
    and pg_temp.par(j, 'ar_fosforo_total') ->> 'estado' = 'sin_registros' and j ->> 'estado' = 'con_datos', j::text);
  -- una referencia de prueba en el efluente y un valor por encima: «fuera»
  insert into tecnica.referencias (variable_id, punto_id, ref_max, origen, fuente) select id, v_efl, 100, 'criterio_planta', 'PRUEBA3 referencia de prueba' from tecnica.variables where codigo = 'ar_dbo5';
  perform pg_temp.registrar(sr, 'PTAR-EFL', '[{"variable":"ar_dbo5","valor":150}]', 1);
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA3-PM-EFL');
  perform pg_temp.reg('04.03 con referencia y un valor por encima: «fuera» en el parámetro y en el elemento', pg_temp.par(j, 'ar_dbo5') ->> 'estado' = 'fuera' and j ->> 'estado' = 'fuera', j::text);
  -- un valor viejo (7 días, más que la ventana de 168 h): «sin dato reciente»
  perform pg_temp.registrar(sr, 'PTAR-RIO-ABJ', '[{"variable":"ar_caudal","valor":2000}]', 7);
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA3-PM-ABJ');
  perform pg_temp.reg('04.04 con un dato más viejo que la ventana (D10): «sin dato reciente»', pg_temp.par(j, 'ar_caudal') ->> 'estado' = 'sin_dato_reciente' and j ->> 'estado' = 'sin_dato_reciente', j::text);
  -- un registro excluido no cuenta (se toma el anterior)
  insert into tecnica.exclusiones (registro_id, accion, motivo, autor)
  select r.id, 'EXCLUIR', 'PRUEBA3 valor mal digitado', adm from tecnica.registros r join tecnica.variables v on v.id = r.variable_id where v.codigo = 'ar_caudal' and r.punto_id = v_afl;
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA3-PM-AFL');
  perform pg_temp.reg('04.05 un registro excluido no cuenta como último valor', pg_temp.par(j, 'ar_caudal') ->> 'estado' = 'sin_registros', j::text);
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA3-POZ');
  perform pg_temp.reg('04.06 un elemento sin punto: «sin_variables», sin parámetros', j ->> 'estado' = 'sin_variables' and jsonb_array_length(j -> 'indicadores') = 0, j::text);
  j := public.geoportal_tec_ptar_mapa(sr, 'prueba_ptar3');
  perform pg_temp.reg('04.07 el mapa trae el estado y el punto de cada punto de medición', (select string_agg(f -> 'properties' ->> 'codigo' || '=' || (f -> 'properties' ->> 'estado') || '@' || coalesce(f -> 'properties' ->> 'punto', '-'), ',' order by f -> 'properties' ->> 'codigo')
      from jsonb_array_elements(j -> 'elementos' -> 'features') f) = 'PRUEBA3-PM-ABJ=sin_dato_reciente@PTAR-RIO-ABJ,PRUEBA3-PM-AFL=con_datos@PTAR-AFL,PRUEBA3-PM-EFL=fuera@PTAR-EFL,PRUEBA3-POZ=sin_variables@-', j::text);
  perform pg_temp.err('04.08 el supervisor de la PTAP no abre la ficha de la PTAR', format('select public.geoportal_tec_ptar_elemento(%L, %L)', sp, 'PRUEBA3-PM-AFL'), '42501');

  -- ---------- 05. Lo que no cambia ----------
  perform pg_temp.reg('05.01 la huella de redes no cambia (1ba192724c2fddcf321104700829f3cc)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
      where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '1ba192724c2fddcf321104700829f3cc');
  perform pg_temp.reg('05.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));
  perform pg_temp.reg('05.03 las funciones nuevas sin EXECUTE para la API; las RPC del mapa y la ficha, solo service_role',
    (select bool_and(not has_function_privilege(r, p.oid, 'execute')) from pg_proc p cross join (values ('anon'), ('authenticated'), ('service_role')) x(r)
      where p.pronamespace = 'tecnica'::regnamespace and p.proname in ('f_parametros_punto', 'f_estado_parametros'))
    and (select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute'))
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_tec_ptar_mapa', 'geoportal_tec_ptar_elemento'))
    and not has_function_privilege('anon', 'tecnica.f_autorizar_captura(text,text)'::regprocedure, 'execute'));
  perform pg_temp.reg('05.04 la PTAR sigue fuera de tecnica.plantas', not exists (select 1 from tecnica.plantas where codigo like '%ptar%'));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · PTAR-3 (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total,
    case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
