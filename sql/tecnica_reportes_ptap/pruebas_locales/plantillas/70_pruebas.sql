-- =====================================================================
-- TÉCNICA · FASE 1 · REPORTES DEL PTAP · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- Todo es SIMULADO y se deshace: sus personas (prueba.rep.*), una planta de prueba (zt_rep_pl), 3 puntos (ZTREP-*), 5 variables (zt_rep_*) en Entrada, Salida y
-- Muestreo, una referencia, 2 químicos de prueba con su kardex, envíos con exclusiones y una revisión, y 2 eventos de suspensión de la planta de prueba.
-- Los textos libres de prueba llevan un nombre y un teléfono inventados («ZTREP Pedro Prueba 3009990000») para comprobar que NO salen.
-- Mide con UN AÑO de Entrada simulado en la planta de prueba (6 envíos al día, 2 variables).
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · reportes del PTAP … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.claves(j jsonb) returns text language sql as $$ select string_agg(k, ',' order by k) from jsonb_object_keys(j) k $$;
create function pg_temp.ccols(j jsonb) returns text language sql as $$ select string_agg(x ->> 'clave', ',' order by x ->> 'clave') from jsonb_array_elements(j) x $$;
create function pg_temp.todas(p_quien text, p_id bigint, p_lim integer default 5000) returns jsonb language plpgsql as $$
declare v_c text; v_r jsonb; v_todas jsonb := '[]'; i integer := 0;
begin
  loop
    v_r := public.geoportal_tec_reporte_pagina(p_quien, p_id, v_c, p_lim);
    v_todas := v_todas || (v_r -> 'filas'); v_c := v_r ->> 'cursor'; i := i + 1;
    exit when v_c is null or i > 5000;
  end loop;
  return v_todas;
end $$;
create function pg_temp.bajar(p_quien text, p_rep text, p_f jsonb, p_incl boolean default false, p_lim integer default 5000) returns jsonb language plpgsql as $$
declare v_i jsonb;
begin
  v_i := public.geoportal_tec_reporte_iniciar(p_quien, p_rep, p_f, 'xlsx', p_incl, '10.0.0.1');
  return jsonb_build_object('ini', v_i, 'filas', pg_temp.todas(p_quien, (v_i ->> 'descarga_id')::bigint, p_lim));
end $$;
create function pg_temp.hay(p_filas jsonb, p_clave text, p_valor text) returns boolean language sql as $$
  select exists (select 1 from jsonb_array_elements(p_filas) f where f ->> p_clave = p_valor) $$;
create function pg_temp.fila(p_filas jsonb, p_clave text, p_valor text) returns jsonb language sql as $$
  select f from jsonb_array_elements(p_filas) f where f ->> p_clave = p_valor limit 1 $$;
create temp table _v (codigo text primary key, id bigint);
create function pg_temp.vid(p text) returns bigint language sql as $$ select id from _v where codigo = p $$;
create function pg_temp.reg_valor(p_lote uuid, p_form text, p_var text, p_planta bigint, p_punto bigint, p_valor numeric, p_dias integer, p_hora integer) returns bigint language sql as $$
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, punto_id, valor, fecha_muestra, hora_muestra, autor)
  values (p_lote, p_form, pg_temp.vid(p_var), p_planta, p_punto, p_valor, (clock_timestamp() at time zone 'America/Bogota')::date - p_dias, make_time(p_hora, 0, 0), 'prueba.rep.op@emdupar.gov.co')
  returning id $$;

do $prueba$
declare
  adm text := 'prueba.rep.adm@emdupar.gov.co'; sp text := 'prueba.rep.sp@emdupar.gov.co'; sp2 text := 'prueba.rep.sp2@emdupar.gov.co'; sd text := 'prueba.rep.sd@emdupar.gov.co';
  op text := 'prueba.rep.op@emdupar.gov.co'; libre text := 'ZTREP Pedro Prueba 3009990000';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; per jsonb; pf jsonb; j jsonb; j2 jsonb; f jsonb; v_id bigint; v_id2 bigint; v_n integer;
  v_pl bigint; v_m1 bigint; v_m2 bigint; v_t1 bigint; v_q bigint; v_coag bigint; e1 uuid := gen_random_uuid(); e2 uuid := gen_random_uuid(); e3 uuid := gen_random_uuid();
  s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); m1 uuid := gen_random_uuid(); m2 uuid := gen_random_uuid(); v_r_alto bigint; v_r_excl bigint;
  v_mov_foto bigint; v_mov_uso bigint; v_ev1 bigint; v_ev2 bigint; v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_info text; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTREP Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZTREP Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp2, 'ZTREP Otro supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZTREP Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZTREP Operador', 'consulta', true, 'sin_restriccion', 'todos');
  per := jsonb_build_object('desde', (hoy - 30)::text, 'hasta', hoy::text);
  pf := per || '{"planta": "zt_rep_pl"}';

  -- ---------- el catálogo de prueba ----------
  insert into tecnica.plantas (codigo, nombre) values ('zt_rep_pl', 'ZTREP Planta') returning id into v_pl;
  insert into tecnica.puntos (codigo, nombre, tipo, zona, numero_informe) select 'ZTREP-M1', 'ZTREP Muestreo norte', 'muestreo', 'norte', coalesce(max(numero_informe), 0) + 1 from tecnica.puntos where tipo = 'muestreo' returning id into v_m1;
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('ZTREP-M2', 'ZTREP Muestreo sur', 'muestreo', 'sur') returning id into v_m2;
  insert into tecnica.puntos (codigo, nombre, tipo, planta_id) values ('ZTREP-T1', 'ZTREP Tanque', 'tanque', v_pl) returning id into v_t1;
  with v as (insert into tecnica.variables (codigo, nombre, unidad, categoria, decimales) values
               ('zt_rep_ti', 'ZTREP Turbiedad de ingreso', 'NTU', 'fisicoquimico', 1), ('zt_rep_qi', 'ZTREP Caudal de ingreso', 'L/s', 'caudal', 0),
               ('zt_rep_cl', 'ZTREP Cloro de salida', 'mg/L', 'fisicoquimico', 2), ('zt_rep_clt', 'ZTREP Cloro en tanque', 'mg/L', 'fisicoquimico', 2),
               ('zt_rep_ph', 'ZTREP pH', 'pH', 'fisicoquimico', 2) returning codigo, id)
  insert into _v select codigo, id from v;
  insert into tecnica.formulario_variables (formulario, variable_id, orden, alcance, tipo_punto) values
    ('entrada', pg_temp.vid('zt_rep_ti'), 991, 'por_planta', 'muestreo'), ('entrada', pg_temp.vid('zt_rep_qi'), 992, 'por_planta', 'muestreo'),
    ('salida', pg_temp.vid('zt_rep_cl'), 991, 'por_planta', 'muestreo'), ('salida', pg_temp.vid('zt_rep_clt'), 992, 'por_punto', 'tanque'),
    ('muestreo', pg_temp.vid('zt_rep_ph'), 991, 'por_punto', 'muestreo');
  insert into tecnica.referencias (variable_id, planta_id, ref_max, origen, fuente) values (pg_temp.vid('zt_rep_ti'), v_pl, 1000, 'criterio_planta', 'ZTREP referencia de prueba');
  insert into tecnica.quimicos (codigo, nombre, rol) values ('zt_rep_coag', 'ZTREP Coagulante', 'coagulante') returning id into v_coag;
  insert into tecnica.quimicos (codigo, nombre, rol) values ('zt_rep_q', 'ZTREP Químico de bodega', 'auxiliar') returning id into v_q;

  -- ---------- envíos: Entrada (E1 normal con dosis, E2 con un valor alto y otro excluido, E3 excluido entero), Salida (planta y tanque), Muestreo (2 puntos) ----------
  perform pg_temp.reg_valor(e1, 'entrada', 'zt_rep_ti', v_pl, null, 12.5, 3, 8); perform pg_temp.reg_valor(e1, 'entrada', 'zt_rep_qi', v_pl, null, 400, 3, 8);
  v_r_alto := pg_temp.reg_valor(e2, 'entrada', 'zt_rep_ti', v_pl, null, 4321.5, 2, 8); v_r_excl := pg_temp.reg_valor(e2, 'entrada', 'zt_rep_qi', v_pl, null, 410, 2, 8);
  perform pg_temp.reg_valor(e3, 'entrada', 'zt_rep_ti', v_pl, null, 10, 1, 8); perform pg_temp.reg_valor(e3, 'entrada', 'zt_rep_qi', v_pl, null, 420, 1, 8);
  insert into tecnica.exclusiones (registro_id, motivo, autor) values (v_r_excl, libre, sp);
  insert into tecnica.exclusiones (lote_id, motivo, autor) values (e3, libre, sp);
  insert into tecnica.uso_quimicos (lote_id, origen, tipo_uso, quimico_id, planta_id, dosis, fecha_muestra, hora_muestra, autor)
  values (e1, 'entrada', 'dosificacion', v_coag, v_pl, 25, hoy - 3, '08:00', op);
  insert into tecnica.revisiones_fuera_referencia (registro_id, accion, nota, creado_por) values (v_r_alto, 'revisado', libre, sp2);
  perform pg_temp.reg_valor(s1, 'salida', 'zt_rep_cl', v_pl, null, 1.2, 2, 9); perform pg_temp.reg_valor(s2, 'salida', 'zt_rep_clt', null, v_t1, 0.8, 2, 10);
  perform pg_temp.reg_valor(m1, 'muestreo', 'zt_rep_ph', null, v_m1, 7.1, 4, 7); perform pg_temp.reg_valor(m2, 'muestreo', 'zt_rep_ph', null, v_m2, 6.0, 4, 11);

  -- ---------- 01. Quién entra ----------
  perform pg_temp.reg('01.01 el supervisor de planta inicia (Entrada de la planta de prueba): 2 envíos vigentes',
    (public.geoportal_tec_reporte_iniciar(sp, 'entrada', pf, 'xlsx', false, null) ->> 'total')::integer = 2);
  perform pg_temp.reg('01.02 el administrador también', (public.geoportal_tec_reporte_iniciar(adm, 'entrada', pf, 'csv', false, null) ->> 'total')::integer = 2);
  perform pg_temp.err('01.03 el supervisor de distribución no (403)', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sd, 'entrada', pf), '42501');
  perform pg_temp.err('01.04 el operador no (403)', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', op, 'entrada', pf), '42501');
  perform pg_temp.err('01.05 ni la foto de una remisión para el supervisor de distribución (403)', format('select public.geoportal_tec_reporte_remision_foto(%L, 1)', sd), '42501');

  -- ---------- 02. Lo que se rechaza ----------
  perform pg_temp.err('02.01 un reporte que no existe', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'registros', per), null, 'Ese reporte no existe');
  perform pg_temp.err('02.02 un formato que no es Excel ni CSV', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L, %L)', sp, 'entrada', per, 'pdf'), null, 'Excel o CSV');
  perform pg_temp.err('02.03 un filtro que no aplica (químico en Entrada)', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'entrada', per || '{"quimico": "zt_rep_q"}'), null, 'no aplica');
  perform pg_temp.err('02.04 sin periodo', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'salida', '{}'), null, 'Elija el periodo');
  perform pg_temp.err('02.05 más de un año', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'salida', jsonb_build_object('desde', (hoy - 366)::text, 'hasta', hoy::text)), null, 'hasta de un año');
  perform pg_temp.err('02.06 una planta que no existe', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'entrada', per || '{"planta": "zt_no_existe"}'), null, 'planta no existe');
  perform pg_temp.err('02.07 una zona que no existe', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'muestreo', per || '{"zona": "oeste"}'), null, 'zona no existe');
  perform pg_temp.err('02.08 un formulario sin referencias (Uso de químicos) en Fuera de referencia', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'fuera_referencia', per || '{"formulario": "uso_quimicos"}'), null, 'no tiene valores');
  perform pg_temp.err('02.09 sin datos: 404', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'entrada', jsonb_build_object('desde', '2001-01-01', 'hasta', '2001-01-31', 'planta', 'zt_rep_pl')), 'P0002', 'No hay datos');

  -- ---------- 03. Entrada ----------
  j := pg_temp.bajar(sp, 'entrada', pf);
  f := pg_temp.fila(j -> 'filas', 'envio', e1::text);
  perform pg_temp.reg('03.01 una fila por envío y planta; una columna por variable con su unidad (las de prueba al final, en el orden del catálogo); la dosis del envío',
    jsonb_array_length(j -> 'filas') = 2 and (f ->> 'v_zt_rep_ti')::numeric = 12.5 and (f ->> 'v_zt_rep_qi')::numeric = 400 and f ->> 'planta' = 'ZTREP Planta'
    and f ->> 'coagulante' = 'ZTREP Coagulante' and (f ->> 'dosis_ppm')::numeric = 25 and f ->> 'estado' = 'Vigente' and (f ->> 'fuera_referencia')::integer = 0
    and exists (select 1 from jsonb_array_elements(j -> 'ini' -> 'columnas') c where c ->> 'clave' = 'v_zt_rep_ti' and c ->> 'unidad' = 'NTU' and (c ->> 'decimales')::integer = 1)
    and f ->> 'muestra' = to_char(hoy - 3, 'YYYY-MM-DD') || 'T08:00:00' and f ->> 'registro' = op, f::text);
  perform pg_temp.reg('03.02 las claves de cada fila son exactamente las columnas que anunció «iniciar»',
    (select bool_and(pg_temp.claves(x) = pg_temp.ccols(j -> 'ini' -> 'columnas')) from jsonb_array_elements(j -> 'filas') x));
  f := pg_temp.fila(j -> 'filas', 'envio', e2::text);
  perform pg_temp.reg('03.03 el valor excluido sale vacío, el envío «Excluido en parte», con 1 valor fuera de referencia; el envío excluido entero no sale',
    f -> 'v_zt_rep_qi' = 'null' and (f ->> 'v_zt_rep_ti')::numeric = 4321.5 and f ->> 'estado' = 'Excluido en parte' and (f ->> 'fuera_referencia')::integer = 1
    and not pg_temp.hay(j -> 'filas', 'envio', e3::text), f::text);
  j2 := pg_temp.bajar(sp, 'entrada', pf, true);
  perform pg_temp.reg('03.04 con «Incluir excluidos»: el valor excluido aparece y el envío excluido entero también («Excluido»)',
    (pg_temp.fila(j2 -> 'filas', 'envio', e2::text) ->> 'v_zt_rep_qi')::numeric = 410 and pg_temp.fila(j2 -> 'filas', 'envio', e3::text) ->> 'estado' = 'Excluido'
    and position('Valores excluidos: incluidos' in (j2 -> 'ini' -> 'leame')::text) > 0);
  perform pg_temp.reg('03.05 el Léame: qué trae, qué no, filtros (periodo y planta), quién y cuándo; sin motivos de exclusión en ninguna parte',
    jsonb_array_length(j -> 'ini' -> 'leame' -> 'que_trae') >= 1 and jsonb_array_length(j -> 'ini' -> 'leame' -> 'que_no_trae') >= 1
    and position('Planta: ZTREP Planta' in (j -> 'ini' -> 'leame')::text) > 0 and j -> 'ini' -> 'leame' ->> 'generado_por' = sp and position('Pedro' in (j || j2)::text) = 0);

  -- ---------- 04. Salida y 05. Muestreo ----------
  j := pg_temp.bajar(sp, 'salida', per || '{"punto": "ZTREP-T1"}');
  perform pg_temp.reg('04.01 Salida por punto: el envío del tanque con su punto y su variable; el de la planta no',
    jsonb_array_length(j -> 'filas') = 1 and (j -> 'filas' -> 0 ->> 'v_zt_rep_clt')::numeric = 0.8 and j -> 'filas' -> 0 ->> 'punto' = 'ZTREP-T1' and j -> 'filas' -> 0 ->> 'punto_nombre' = 'ZTREP Tanque', (j -> 'filas')::text);
  j := pg_temp.bajar(sp, 'salida', pf);
  perform pg_temp.reg('04.02 Salida por planta: el envío de la planta, con la planta y sin punto', jsonb_array_length(j -> 'filas') = 1 and (j -> 'filas' -> 0 ->> 'v_zt_rep_cl')::numeric = 1.2 and j -> 'filas' -> 0 -> 'punto' = 'null', (j -> 'filas')::text);
  j := pg_temp.bajar(sp, 'muestreo', per || '{"zona": "norte"}');
  f := pg_temp.fila(j -> 'filas', 'punto', 'ZTREP-M1');
  perform pg_temp.reg('05.01 Muestreo por zona norte: el punto de prueba del norte con tipo, zona y número en el informe; el del sur no',
    f ->> 'tipo_punto' = 'Muestreo' and f ->> 'zona' = 'norte' and (f ->> 'numero_informe')::integer = (select numero_informe from tecnica.puntos where codigo = 'ZTREP-M1') and (f ->> 'v_zt_rep_ph')::numeric = 7.1 and not pg_temp.hay(j -> 'filas', 'punto', 'ZTREP-M2')
    and not (j -> 'ini' -> 'columnas')::text like '%"planta"%', f::text);
  perform pg_temp.reg('05.02 Muestreo por punto', jsonb_array_length((pg_temp.bajar(sp, 'muestreo', per || '{"punto": "ZTREP-M2"}')) -> 'filas') = 1);

  -- ---------- 06–08. Químicos: un kardex completo del químico de prueba (inventario, entrada, uso, entrada con foto, ajuste, inventario, uso) ----------
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, autor) values ('entrada', v_q, 300, 'kg', 300, hoy - 45, 'ZTREP Químicos S. A.', 'R-090', op);
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor) values ('inventario_inicial', v_q, 1000, 'kg', 1000, hoy - 40, 'ZTREP conteo inicial de prueba', sp);
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, autor) values ('entrada', v_q, 0.5, 't', 500, hoy - 35, 'ZTREP Químicos S. A.', 'R-100', op);
  insert into tecnica.quimico_movimientos (tipo, quimico_id, planta_id, para_que, cantidad, unidad, cantidad_kg, dia, dosis_optima_ppm, autor) values ('uso', v_q, v_pl, 'dosificacion', 200, 'kg', -200, hoy - 20, 18, op) returning id into v_mov_uso;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, lote_fabricante, vence, remision_foto, autor)
  values ('entrada', v_q, 1, 't', 1000, hoy - 10, 'ZTREP Químicos S. A.', 'R-123', 'L-9', hoy + 300, 'remisiones/' || to_char(hoy, 'YYYY-MM') || '/' || gen_random_uuid() || '.jpg', op) returning id into v_mov_foto;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor) values ('ajuste', v_q, 100, 'kg', -100, hoy - 5, libre, sp);
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor) values ('inventario_inicial', v_q, 2150, 'kg', 2150, hoy - 2, libre, sp);
  insert into tecnica.quimico_movimientos (tipo, quimico_id, planta_id, para_que, cantidad, unidad, cantidad_kg, dia, autor) values ('uso', v_q, v_pl, 'limpieza', 50, 'kg', -50, hoy - 1, op);
  j := pg_temp.bajar(sp, 'uso_quimicos', per || '{"quimico": "zt_rep_q"}');
  f := pg_temp.fila(j -> 'filas', 'movimiento', v_mov_uso::text);
  perform pg_temp.reg('06.01 Uso de químicos: los 2 usos del periodo, con planta, «Dosificación», kg en positivo y la dosis óptima vigente',
    jsonb_array_length(j -> 'filas') = 2 and f ->> 'para_que' = 'Dosificación' and (f ->> 'cantidad_kg')::numeric = 200 and (f ->> 'dosis_optima_ppm')::numeric = 18 and f ->> 'planta' = 'ZTREP Planta'
    and pg_temp.hay(j -> 'filas', 'para_que', 'Limpieza'), (j -> 'filas')::text);
  j := pg_temp.bajar(sp, 'entrada_quimicos', per || '{"quimico": "zt_rep_q"}');
  f := pg_temp.fila(j -> 'filas', 'movimiento', v_mov_foto::text);
  perform pg_temp.reg('07.01 Entrada de químicos: la del periodo, con proveedor, remisión, lote, vencimiento y la foto como enlace (el número del movimiento), no la ruta',
    jsonb_array_length(j -> 'filas') = 1 and f ->> 'proveedor' = 'ZTREP Químicos S. A.' and f ->> 'remision' = 'R-123' and (f ->> 'foto_remision')::bigint = v_mov_foto
    and (f ->> 'cantidad_kg')::numeric = 1000 and f ->> 'unidad' = 't' and position('remisiones/' in (j)::text) = 0, f::text);
  j2 := public.geoportal_tec_reporte_remision_foto(sp, v_mov_foto, '10.0.0.3');
  perform pg_temp.reg('07.02 la foto de la remisión: la ruta para que la Edge la firme, y la consulta queda en la auditoría',
    j2 ->> 'ruta' like 'remisiones/%' and (j2 ->> 'movimiento')::bigint = v_mov_foto
    and exists (select 1 from public.geoportal_auditoria a where a.accion = 'tec_reporte_remision_foto' and a.referencia = v_mov_foto::text and a.email = sp and a.ip = '10.0.0.3'));
  perform pg_temp.err('07.03 un movimiento sin foto: 404', format('select public.geoportal_tec_reporte_remision_foto(%L, %s)', sp, v_mov_uso), 'P0002', 'no tiene foto');
  j := pg_temp.bajar(sp, 'kardex_quimicos', per || '{"quimico": "zt_rep_q"}');
  perform pg_temp.reg('08.01 Kardex: saldo inicial 1.500 kg (lo de antes del periodo), los 5 movimientos del periodo en orden y saldo al cierre 2.100 kg',
    jsonb_array_length(j -> 'filas') = 7 and j -> 'filas' -> 0 ->> 'tipo' = 'Saldo inicial' and (j -> 'filas' -> 0 ->> 'saldo_kg')::numeric = 1500
    and (select string_agg(x ->> 'tipo', ',' order by n) from jsonb_array_elements(j -> 'filas') with ordinality t(x, n)) = 'Saldo inicial,Uso,Entrada,Ajuste por conteo,Inventario inicial,Uso,Saldo al cierre'
    and (select string_agg(x ->> 'saldo_kg', ',' order by n) from jsonb_array_elements(j -> 'filas') with ordinality t(x, n)) = '1500,1300,2300,2200,2150,2100,2100'
    and j -> 'filas' -> 6 ->> 'tipo' = 'Saldo al cierre', (j -> 'filas')::text);
  perform pg_temp.reg('08.02 el saldo al cierre de hoy es el mismo del sistema (v_quimico_saldo); el inventario va como conteo y reemplaza el saldo; el ajuste sale',
    (j -> 'filas' -> 6 ->> 'saldo_kg')::numeric = (select s.saldo_kg from tecnica.v_quimico_saldo s where s.quimico_id = v_q)
    and (j -> 'filas' -> 4 ->> 'conteo_kg')::numeric = 2150 and (j -> 'filas' -> 3 ->> 'sale_kg')::numeric = 100 and j -> 'filas' -> 2 ->> 'detalle' = 'Remisión R-123 · ZTREP Químicos S. A.'
    and (select bool_and(x ->> 'bodega' = 'Bodega de químicos') from jsonb_array_elements(j -> 'filas') x));
  perform pg_temp.reg('08.03 los motivos de inventarios y ajustes no salen en ninguno de los tres reportes de químicos', position('Pedro' in (j)::text) = 0);
  j := pg_temp.bajar(sp, 'kardex_quimicos', jsonb_build_object('desde', (hoy - 60)::text, 'hasta', (hoy - 41)::text, 'quimico', 'zt_rep_q'));
  perform pg_temp.reg('08.04 un periodo antes del primer inventario: la entrada sale, pero el saldo es desconocido (vacío) al empezar, en el movimiento y al cerrar',
    jsonb_array_length(j -> 'filas') = 3 and j -> 'filas' -> 1 ->> 'tipo' = 'Entrada' and (j -> 'filas' -> 1 ->> 'entra_kg')::numeric = 300
    and (select bool_and(x -> 'saldo_kg' = 'null') from jsonb_array_elements(j -> 'filas') x), (j -> 'filas')::text);

  -- ---------- 09. Eventos de planta ----------
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, planta_id, zona_nombre, causa, desde, regreso_estimado, contratos, sensibles, autor)
  values ('EVS-990001', 'total', false, ST_Multi(ST_MakeEnvelope(-73.58, 10.13, -73.579, 10.131, 4326)), '{}', v_pl, 'lo que surte la planta ZTREP Planta', libre,
          clock_timestamp() - interval '10 hours', clock_timestamp() - interval '2 hours', 120, 3, sd) returning id into v_ev1;
  insert into redes.evento_suspension_eventos (evento_id, tipo, regreso_estimado, hecho_en, autor) values (v_ev1, 'regreso', clock_timestamp() - interval '1 hour', clock_timestamp() - interval '5 hours', sd);
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) values (v_ev1, 'cerrar', 'ZTREP volvió el agua a la planta', clock_timestamp() - interval '30 minutes', sp);
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, planta_id, zona_nombre, causa, desde, contratos, sensibles, autor)
  values ('EVS-990002', 'total', false, ST_Multi(ST_MakeEnvelope(-73.58, 10.13, -73.579, 10.131, 4326)), '{}', v_pl, 'lo que surte la planta ZTREP Planta', 'ZTREP evento anulado',
          clock_timestamp() - interval '3 hours', 0, 0, sd) returning id into v_ev2;
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) values (v_ev2, 'anular', 'ZTREP se declaró por error', clock_timestamp() - interval '2 hours', sd);
  j := pg_temp.bajar(sp, 'eventos_planta', pf);
  f := pg_temp.fila(j -> 'filas', 'evento', 'EVS-990001');
  perform pg_temp.reg('09.01 Eventos de planta: el cerrado con su suspensión, regreso al declarar y vigente, 1 cambio, reanudación, 9,5 h, contratos y sensibles; el anulado no; sin la causa',
    jsonb_array_length(j -> 'filas') = 1 and f ->> 'estado' = 'Cerrado' and (f ->> 'cambios_regreso')::integer = 1 and (f ->> 'duracion_h')::numeric = 9.5 and (f ->> 'contratos')::integer = 120
    and (f ->> 'sensibles')::integer = 3 and f ->> 'reanudado' is not null and f ->> 'regreso_estimado' <> f ->> 'regreso_estimado_inicial' and f ->> 'declaro' = sd and f ->> 'cerro' = sp
    and position('Pedro' in (j)::text) = 0 and pg_temp.claves(f) = pg_temp.ccols(j -> 'ini' -> 'columnas'), f::text);
  j := pg_temp.bajar(sp, 'eventos_planta', pf, true);
  perform pg_temp.reg('09.02 con «Incluir excluidos»: también el anulado (sin reanudación ni duración)',
    jsonb_array_length(j -> 'filas') = 2 and pg_temp.fila(j -> 'filas', 'evento', 'EVS-990002') ->> 'estado' = 'Anulado' and pg_temp.fila(j -> 'filas', 'evento', 'EVS-990002') -> 'duracion_h' = 'null');

  -- ---------- 10. Fuera de referencia ----------
  j := pg_temp.bajar(sp, 'fuera_referencia', pf);
  f := pg_temp.fila(j -> 'filas', 'registro_id', v_r_alto::text);
  perform pg_temp.reg('10.01 Fuera de referencia: el valor alto con su referencia, la marca, la revisión y quién la hizo; sin la nota',
    f ->> 'marca' = 'Alto' and (f ->> 'ref_max')::numeric = 1000 and f ->> 'ref_origen' = 'Criterio de planta' and f ->> 'revision' = 'Revisado' and f ->> 'revisado_por' = sp2
    and f ->> 'formulario' = 'Entrada' and f ->> 'variable' = 'ZTREP Turbiedad de ingreso' and f ->> 'unidad' = 'NTU' and (f ->> 'excluido')::boolean = false and position('Pedro' in (j)::text) = 0, f::text);
  insert into tecnica.exclusiones (registro_id, motivo, autor) values (v_r_alto, 'ZTREP se excluye el valor alto', sp);
  perform pg_temp.err('10.02 excluido el valor, ya no sale (404 sin datos)', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'fuera_referencia', pf), 'P0002');
  j := pg_temp.bajar(sp, 'fuera_referencia', pf || '{"formulario": "entrada"}', true);
  perform pg_temp.reg('10.03 con «Incluir excluidos» vuelve, marcado «excluido»', (pg_temp.fila(j -> 'filas', 'registro_id', v_r_alto::text) ->> 'excluido')::boolean = true);
  insert into tecnica.exclusiones (registro_id, accion, motivo, autor) values (v_r_alto, 'REINCLUIR', 'ZTREP se vuelve a incluir el valor alto', sp);

  perform pg_temp.reg('10.04 la marca, la referencia y la exclusión de cada valor del periodo (una referencia por combinación) son las mismas de tecnica.v_registros_detalle',
    (select count(*) from tecnica.f_rep_valores(array['entrada', 'salida', 'muestreo'], per, clock_timestamp(), null, null))
      = (select count(*) from tecnica.v_registros_detalle d where d.formulario in ('entrada', 'salida', 'muestreo') and d.fecha_muestra between hoy - 30 and hoy)
    and not exists (select 1 from tecnica.f_rep_valores(array['entrada', 'salida', 'muestreo'], per, clock_timestamp(), null, null) a
                     join tecnica.v_registros_detalle d on d.registro_id = a.registro_id
                    where a.marca is distinct from d.fuera_de_rango or a.excluido <> d.excluido or a.ref_min is distinct from d.ref_min or a.ref_max is distinct from d.ref_max
                       or a.ref_origen is distinct from d.ref_origen or a.lote_id <> d.lote_id or a.valor <> d.valor));

  -- ---------- 11. Paginación ----------
  j := pg_temp.bajar(sp, 'entrada', pf, true, 5000); j2 := pg_temp.bajar(sp, 'entrada', pf, true, 1);
  perform pg_temp.reg('11.01 Entrada de uno en uno = de una vez (mismo orden, sin repetir ni saltar)', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = (j -> 'ini' ->> 'total')::integer);
  j := pg_temp.bajar(sp, 'kardex_quimicos', per || '{"quimico": "zt_rep_q"}', false, 5000); j2 := pg_temp.bajar(sp, 'kardex_quimicos', per || '{"quimico": "zt_rep_q"}', false, 2);
  perform pg_temp.reg('11.02 Kardex de dos en dos = de una vez (el saldo corrido no se pierde entre páginas)', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = 7);
  j := pg_temp.bajar(sp, 'muestreo', per, false, 5000); j2 := pg_temp.bajar(sp, 'muestreo', per, false, 1);
  perform pg_temp.reg('11.03 Muestreo (todos los puntos) de uno en uno = de una vez', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = (j -> 'ini' ->> 'total')::integer);
  perform pg_temp.err('11.04 un cursor con caracteres raros se rechaza', format('select public.geoportal_tec_reporte_pagina(%L, %s, %L)', sp, j -> 'ini' ->> 'descarga_id', 'x''; drop'), null, 'no es válida');

  -- ---------- 12. La foto: lo que llega después de iniciar no entra ----------
  j := public.geoportal_tec_reporte_iniciar(sp, 'salida', pf, 'xlsx', false, null);
  perform pg_temp.reg_valor(gen_random_uuid(), 'salida', 'zt_rep_cl', v_pl, null, 1.9, 0, 6);
  perform pg_temp.reg('12.01 un envío registrado después de iniciar no sale en esa descarga (sí en una nueva)',
    jsonb_array_length(pg_temp.todas(sp, (j ->> 'descarga_id')::bigint)) = 1 and jsonb_array_length(pg_temp.bajar(sp, 'salida', pf) -> 'filas') = 2);

  -- ---------- 13. La descarga es de quien la inició, vence y se cierra una vez ----------
  v_id := (public.geoportal_tec_reporte_iniciar(sp, 'entrada', pf, 'csv', false, '10.0.0.2') ->> 'descarga_id')::bigint;
  perform pg_temp.err('13.01 otra persona no puede pedir sus páginas (404)', format('select public.geoportal_tec_reporte_pagina(%L, %s)', sp2, v_id), 'P0002');
  perform pg_temp.err('13.02 ni cerrarla (404)', format('select public.geoportal_tec_reporte_cerrar(%L, %s, 1)', sp2, v_id), 'P0002');
  j := public.geoportal_tec_reporte_cerrar(sp, v_id, 2, 'completa', '10.0.0.2'); j2 := public.geoportal_tec_reporte_cerrar(sp, v_id, 2, 'completa', '10.0.0.2');
  perform pg_temp.reg('13.03 cerrarla dos veces no es error: la segunda dice «repetida»', (j ->> 'repetida')::boolean = false and (j2 ->> 'repetida')::boolean = true);
  perform pg_temp.err('13.04 cerrada, sus páginas ya no salen (409)', format('select public.geoportal_tec_reporte_pagina(%L, %s)', sp, v_id), '55000', 'ya terminó');
  insert into tecnica.reporte_descargas (email, reporte, filtros, incluir, formato, columnas, total, corte_en, creado_en)
  values (sp, 'entrada', pf, false, 'xlsx', '[]', 1, clock_timestamp() - interval '3 hours', clock_timestamp() - interval '3 hours') returning id into v_id2;
  perform pg_temp.err('13.05 iniciada hace más de 2 horas: venció (409)', format('select public.geoportal_tec_reporte_pagina(%L, %s)', sp, v_id2), '55000', 'venció');

  -- ---------- 14. Auditoría ----------
  perform pg_temp.reg('14.01 iniciar queda en la auditoría: quién, qué reporte, filtros, filas, formato e IP',
    (select count(*) from public.geoportal_auditoria a where a.accion = 'tec_reporte_iniciar' and a.referencia = v_id::text and a.email = sp and a.ip = '10.0.0.2'
       and a.detalle ->> 'reporte' = 'entrada' and (a.detalle ->> 'filas')::integer = 2 and a.detalle ->> 'formato' = 'csv' and a.detalle -> 'filtros' ->> 'planta' = 'zt_rep_pl') = 1);
  perform pg_temp.reg('14.02 cerrar queda una sola vez, con las filas entregadas y el resultado',
    (select count(*) from public.geoportal_auditoria a where a.accion = 'tec_reporte_cerrar' and a.referencia = v_id::text and (a.detalle ->> 'filas_entregadas')::integer = 2) = 1);
  perform pg_temp.reg('14.03 la auditoría no guarda filas ni textos libres', not exists (select 1 from public.geoportal_auditoria a where a.accion like 'tec\_reporte\_%' and position('Pedro' in a.detalle::text) > 0));

  -- ---------- 15. Seguridad del esquema ----------
  perform pg_temp.reg('15.01 las 4 RPC: security definer, search_path fijo, solo service_role (ni anon, ni authenticated, ni PUBLIC)',
    (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname = any (array['geoportal_tec_reporte_iniciar', 'geoportal_tec_reporte_pagina', 'geoportal_tec_reporte_cerrar', 'geoportal_tec_reporte_remision_foto']) and p.prosecdef and p.proconfig is not null
       and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 4);
  perform pg_temp.reg('15.02 las funciones internas: nadie más que su dueño',
    not exists (select 1 from pg_proc p where p.pronamespace = 'tecnica'::regnamespace and p.proname like 'f\_rep\_%' and exists (select 1 from aclexplode(p.proacl) x where x.grantee <> p.proowner)));
  perform pg_temp.reg('15.03 las 2 tablas nuevas: RLS y sin permisos para la API',
    (select count(*) from pg_class c where c.oid in ('tecnica.reporte_descargas'::regclass, 'tecnica.reporte_descarga_cierres'::regclass) and c.relrowsecurity
       and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')) = 2);
  perform pg_temp.err('15.04 las descargas son de solo inserción: no se cambian', format('update tecnica.reporte_descargas set total = 0 where id = %s', v_id));
  perform pg_temp.err('15.05 ni se borran', format('delete from tecnica.reporte_descarga_cierres where descarga_id = %s', v_id));
  perform pg_temp.reg('15.06 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));
  perform pg_temp.reg('15.07 la huella de redes no cambia con este paquete',
    (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
      where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) in ('{{MD5_BASE}}', '{{MD5_REDES_DESPUES}}'));

  -- ---------- 16. Tiempos: un año de Entrada en la planta de prueba (6 envíos al día, 2 variables) ----------
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor, registrado_en)
  select l.lote, 'entrada', v.id, v_pl, 100 + (random() * 50)::integer, hoy - l.d, make_time(l.h, 0, 0), op, (hoy - l.d)::timestamp at time zone 'America/Bogota' + make_interval(hours => l.h + 1)
    from (select gen_random_uuid() as lote, d, h from generate_series(4, 365) d cross join generate_series(0, 20, 4) h) l
    cross join (select id from tecnica.variables where codigo in ('zt_rep_ti', 'zt_rep_qi')) v;
  analyze tecnica.registros;
  v_t0 := clock_timestamp(); j := public.geoportal_tec_reporte_iniciar(sp, 'entrada', jsonb_build_object('desde', (hoy - 365)::text, 'hasta', hoy::text, 'planta', 'zt_rep_pl'), 'xlsx', false, null);
  v_ms1 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_t0 := clock_timestamp(); j2 := public.geoportal_tec_reporte_pagina(sp, (j ->> 'descarga_id')::bigint, null, 1000); v_ms2 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_t0 := clock_timestamp(); v_n := (public.geoportal_tec_reporte_pagina(sp, (j ->> 'descarga_id')::bigint, j2 ->> 'cursor', 1000) ->> 'devueltos')::integer; v_ms3 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_info := format('TIEMPOS con un año de Entrada simulado (%s envíos, %s valores): iniciar %s ms · primera página de 1.000 %s ms · la segunda %s ms (tope de la API: 30 s por llamada)',
                   j ->> 'total', (select count(*) from tecnica.registros where planta_id = v_pl), round(v_ms1), round(v_ms2), round(v_ms3));
  perform pg_temp.reg('16.01 TIEMPOS: un año de Entrada; iniciar y cada página en menos de 5 s', (j ->> 'total')::integer = 362 * 6 + 2 and (j2 ->> 'devueltos')::integer = 1000 and v_n = 1000
    and v_ms1 < 5000 and v_ms2 < 5000 and v_ms3 < 5000, v_info);

  -- ---------- 17. El tope de filas (se baja solo dentro de esta prueba) ----------
  create or replace function tecnica.f_rep_max_filas() returns integer language sql immutable set search_path to 'pg_catalog' as $f$ select 2 $f$;
  perform pg_temp.err('17.01 más filas que el tope: «Acote el periodo o los filtros»', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'muestreo', per), null, 'Acote el periodo');

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · reportes del PTAP (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
