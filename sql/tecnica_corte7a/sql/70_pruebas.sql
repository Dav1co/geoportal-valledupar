-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.tec7.*), sus químicos («ZT7 …»), sus PDF en Storage, sus caudales de Entrada del día y,
-- para la tarjeta del contrato, un contrato de prueba (99000000120x) como la suite viva de Análisis de contrato. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · CORTE 7a … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- prepara la subida de un PDF y lo deja «subido» en Storage (la subida real la hace el navegador con la URL firmada)
create function pg_temp.pdf(p_quien text, p_mime text default 'application/pdf', p_bytes integer default 200000) returns text language plpgsql as $$
declare v_r text := public.geoportal_tec_quimico_ficha_preparar(p_quien) ->> 'ruta';
begin
  insert into storage.objects (bucket_id, name, metadata) values ('tecnica-evidencias', v_r, jsonb_build_object('size', p_bytes, 'mimetype', p_mime));
  return v_r;
end $$;
create function pg_temp.saldo(p_cod text) returns numeric language sql as $$ select saldo_kg from tecnica.v_quimico_saldo where codigo = p_cod $$;
create function pg_temp.fila(p jsonb, p_quimico text, p_planta text) returns jsonb language sql as $$
  select f from jsonb_array_elements(p -> 'filas') f where f ->> 'quimico' = p_quimico and f ->> 'planta' = p_planta and (f ->> 'dia')::date = (clock_timestamp() at time zone 'America/Bogota')::date $$;

do $prueba$
declare
  a text := 'prueba.tec7.adm@emdupar.gov.co'; sv text := 'prueba.tec7.planta@emdupar.gov.co'; sd text := 'prueba.tec7.dist@emdupar.gov.co';
  op text := 'prueba.tec7.op@emdupar.gov.co'; op2 text := 'prueba.tec7.op2@emdupar.gov.co'; sv2 text := 'prueba.tec7.planta2@emdupar.gov.co';
  C1 text := '990000001201';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_r jsonb; v_x jsonb; v_cod text; v_ruta text; v_n integer; v_qi numeric; v_esp numeric;
  v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT7 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values
    (sv, 'ZT7 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos'), (sv2, 'ZT7 Supervisor de planta y distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT7 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT7 Operador', 'consulta', true, 'sin_restriccion', 'todos'),
    (op2, 'ZT7 Operador sin químicos', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'uso_quimicos', a), (op, 'asignar_formulario', 'entrada_quimicos', a);

  -- ===================== 01. Respuestas al 6b =====================
  perform pg_temp.reg('01.01 estados del contrato: SUSPENDIDO, CORTADO, RETIRADO y ACTIVO, cada uno el suyo; otro texto, «otro»',
     redes.f_estado_contrato('SUSPENDIDO') = 'suspendido' and redes.f_estado_contrato(' cortado ') = 'cortado' and redes.f_estado_contrato('RETIRADO') = 'retirado'
     and redes.f_estado_contrato('ACTIVO') = 'activo' and redes.f_estado_contrato('EN TRAMITE') = 'otro' and redes.f_estado_contrato(null) = 'sin_dato');
  perform pg_temp.reg('01.02 el muestreo se pinta hasta 35 días, con su evento', (select valor from redes.parametros where clave = 'geovisor_muestreo_dias') = 35
     and exists (select 1 from redes.parametro_eventos where clave = 'geovisor_muestreo_dias' and despues = 35));
  insert into public.cartera_suscripcion (contrato, estado, identificacion, nombre, correo, telefono, direccion, barrio, categoria, subcategoria, ciclo,
                                          facturas_pendientes, deuda_total, saldo_pendiente, saldo_a_favor, valor_reclamo, saldo_financiado, serial_medidor, ruta, periodo_carga)
  values (C1, 'SUSPENDIDO', 'DOC-PRUEBA-7', 'NOMBRE DE PRUEBA SIETE', null, '3007770000', 'CRA ZT7 1', 'ZT7 BARRIO', '1 Residencial', '2 Estrato 2', '7', 1, 1000, 0, 0, 0, 0, null, '0701', '29991231');
  insert into public.catastro_valledupar (cod_usuario, direccion, barrio, geom) values (C1, 'CRA ZT7 1 CATASTRO', 'ZT7 BARRIO', ST_SetSRID(ST_MakePoint(-73.30, 10.42), 4326));
  perform redes.f_refrescar_contratos_capa();
  perform pg_temp.reg('01.03 la capa de contratos clasifica el suspendido como «suspendido»', (select estado from redes.contratos_capa where contrato = C1) = 'suspendido');
  v_r := public.geoportal_redes_contrato_tarjeta(sv, C1);
  perform pg_temp.reg('01.04 el supervisor de planta ve la tarjeta SIN nombre ni dirección (sí el barrio) y la auditoría lo dice',
     not (v_r ->> 'datos_personales')::boolean and v_r -> 'suscriptor' ->> 'nombre' is null and v_r -> 'suscriptor' ->> 'direccion' is null and v_r -> 'suscriptor' ->> 'barrio' = 'ZT7 BARRIO'
     and v_r::text not like '%NOMBRE DE PRUEBA%' and v_r::text not like '%CRA ZT7%'
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta' and email = sv and referencia = C1 and detalle ->> 'datos' = 'sin nombre ni dirección'), v_r::text);
  v_r := public.geoportal_redes_contrato_tarjeta(sd, C1);
  perform pg_temp.reg('01.05 el supervisor de distribución sí ve nombre y dirección', (v_r ->> 'datos_personales')::boolean and v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA SIETE');
  v_r := public.geoportal_redes_contrato_tarjeta(a, C1);
  perform pg_temp.reg('01.06 el administrador también', v_r -> 'suscriptor' ->> 'direccion' = 'CRA ZT7 1 CATASTRO');
  perform public.geoportal_redes_personal_fijar(sd, sv2, 'area', 'ambas', 'ZT7 trabaja en planta y en la red');
  v_r := public.geoportal_redes_contrato_tarjeta(sv2, C1);
  perform pg_temp.reg('01.07 un supervisor de planta con área «las dos» en Personal sí los ve', (v_r ->> 'datos_personales')::boolean and v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA SIETE');

  -- ===================== 02. Catálogo e identidad =====================
  perform pg_temp.reg('02.01 hipoclorito de calcio en el catálogo (auxiliar, no de potabilización); PAC y cloro gaseoso de potabilización',
     (select rol || '|' || potabilizacion from tecnica.v_quimico_vigente where codigo = 'hipoclorito_calcio') = 'auxiliar|false'
     and (select bool_and(potabilizacion) from tecnica.v_quimico_vigente where codigo in ('pac', 'cloro_gaseoso')));
  v_r := public.geoportal_tec_quimicos_catalogo(sv);
  perform pg_temp.reg('02.02 el supervisor de planta ve el catálogo con saldo y parámetros (sin «Otro»)', jsonb_array_length(v_r -> 'quimicos') >= 3
     and not exists (select 1 from jsonb_array_elements(v_r -> 'quimicos') x where x ->> 'codigo' = 'otro') and (v_r -> 'parametros' ->> 'desvio_pct')::numeric = 25
     and (v_r -> 'parametros' ->> 'marca_esperado_usado')::numeric = 1);
  perform pg_temp.err('02.03 el operador no ve el catálogo ni el saldo', format($$select public.geoportal_tec_quimicos_catalogo(%L)$$, op), '42501');
  perform pg_temp.err('02.04 el supervisor de distribución tampoco (químicos es solo de planta)', format($$select public.geoportal_tec_quimicos_catalogo(%L)$$, sd), '42501');
  perform pg_temp.err('02.05 el nombre de un químico no se cambia (identidad)', $$update tecnica.quimicos set nombre = 'Otro nombre' where codigo = 'pac'$$, '55000', 'identidad');
  perform pg_temp.err('02.06 los químicos no se borran', $$delete from tecnica.quimicos where codigo = 'hipoclorito_calcio'$$, '42501');

  -- ===================== 03. Crear un químico (PDF obligatorio) =====================
  v_ruta := public.geoportal_tec_quimico_ficha_preparar(sv) ->> 'ruta';
  perform pg_temp.reg('03.01 preparar la subida da una ruta de PDF en quimicos/AAAA-MM/', v_ruta ~ '^quimicos/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.pdf$', v_ruta);
  perform pg_temp.err('03.02 crear sin que el PDF haya subido', format($$select public.geoportal_tec_quimico_crear(%L, 'ZT7 Coagulante', 'coagulante', true, 20, %L, 'ZT7 coagulante de prueba')$$, sv, v_ruta), '22023', 'no terminó de subir');
  perform pg_temp.err('03.03 crear con un archivo que no es PDF', format($$select public.geoportal_tec_quimico_crear(%L, 'ZT7 Coagulante', 'coagulante', true, 20, %L, 'ZT7 coagulante de prueba')$$, sv, pg_temp.pdf(sv, 'image/jpeg')), '22023', 'PDF');
  perform pg_temp.err('03.04 crear con el PDF que preparó otra persona', format($$select public.geoportal_tec_quimico_crear(%L, 'ZT7 Coagulante', 'coagulante', true, 20, %L, 'ZT7 coagulante de prueba')$$, sv2, pg_temp.pdf(sv)), '22023', 'Suba primero');
  perform pg_temp.err('03.05 de potabilización sin dosis óptima', format($$select public.geoportal_tec_quimico_crear(%L, 'ZT7 Coagulante', 'coagulante', true, null, %L, 'ZT7 coagulante de prueba')$$, sv, pg_temp.pdf(sv)), '22023', 'dosis óptima');
  perform pg_temp.err('03.06 sin PDF no se crea', format($$select public.geoportal_tec_quimico_crear(%L, 'ZT7 Coagulante', 'coagulante', true, 20, null, 'ZT7 coagulante de prueba')$$, sv), '22023', 'Suba primero');
  v_r := public.geoportal_tec_quimico_crear(sv, '  ZT7   Coagulante Ñandú ', 'coagulante', true, 20, pg_temp.pdf(sv), 'ZT7 coagulante de prueba');
  v_cod := v_r ->> 'codigo';
  perform pg_temp.reg('03.07 se crea: código del nombre (sin tildes ni espacios), alta con dosis, potabilización, activo y la ficha; auditado',
     v_cod = 'zt7_coagulante_nandu' and v_r ->> 'nombre' = 'ZT7 Coagulante Ñandú'
     and (select dosis_optima_ppm || '|' || potabilizacion || '|' || activo || '|' || (ficha_ruta is not null) from tecnica.v_quimico_vigente where codigo = v_cod) = '20|true|true|true'
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_quimico_crear' and referencia = v_cod), v_r::text);
  perform pg_temp.err('03.08 el mismo nombre otra vez (aunque con otra tilde)', format($$select public.geoportal_tec_quimico_crear(%L, 'zt7 coagulante ñandu', 'coagulante', true, 20, %L, 'ZT7 coagulante de prueba')$$, sv, pg_temp.pdf(sv)), '55000', 'Ya hay');
  perform pg_temp.err('03.09 el operador no crea químicos', format($$select public.geoportal_tec_quimico_ficha_preparar(%L)$$, op), '42501');

  -- ===================== 04. Lo que sí cambia, con historial =====================
  perform pg_temp.err('04.01 la dosis óptima no cambia sin un PDF nuevo', format($$select public.geoportal_tec_quimico_fijar(%L, %L, '{"dosis_optima_ppm": 30}', null, 'ZT7 nueva dosis del jar test')$$, sv, v_cod), '22023', 'PDF');
  perform pg_temp.err('04.02 el nombre no se cambia por aquí', format($$select public.geoportal_tec_quimico_fijar(%L, %L, '{"nombre": "Otro"}', null, 'ZT7 cambiar el nombre')$$, sv, v_cod), '22023', 'identidad');
  perform pg_temp.err('04.03 sin motivo no', format($$select public.geoportal_tec_quimico_fijar(%L, %L, '{"activo": false}', null, 'corto')$$, sv, v_cod), '22023', 'motivo');
  perform pg_temp.reg('04.04 una versión nueva de la ficha sola (sin cambiar la dosis)',
     public.geoportal_tec_quimico_fijar(sv, v_cod, '{}', pg_temp.pdf(sv), 'ZT7 el proveedor mandó la ficha nueva') -> 'cambios' = '["ficha"]'::jsonb);
  perform pg_temp.err('04.05 nada que cambiar', format($$select public.geoportal_tec_quimico_fijar(%L, %L, '{"dosis_optima_ppm": 20, "potabilizacion": true}', null, 'ZT7 nada cambia')$$, sv, v_cod), '22023', 'No hay cambios');

  -- ===================== 05. Bodega: inventario inicial, entrada, uso y ajuste (todo en kg) =====================
  perform pg_temp.err('05.01 el ajuste antes del inventario inicial', format($$select public.geoportal_tec_quimico_ajuste(%L, %L, -5, 'ZT7 faltante del conteo')$$, sv, v_cod), '55000', 'inventario inicial');
  perform pg_temp.err('05.02 el operador no carga el inventario inicial', format($$select public.geoportal_tec_quimico_inventario(%L, %L, 2, 't', %L, 'ZT7 conteo físico de bodega')$$, op, v_cod, hoy), '42501');
  v_r := public.geoportal_tec_quimico_inventario(sv, v_cod, 2, 't', hoy - 1, 'ZT7 conteo físico de bodega');
  perform pg_temp.reg('05.03 inventario inicial de 2 t: saldo 2.000 kg', (v_r ->> 'saldo_kg')::numeric = 2000 and pg_temp.saldo(v_cod) = 2000, v_r::text);
  perform pg_temp.err('05.04 el inventario con fecha futura', format($$select public.geoportal_tec_quimico_inventario(%L, %L, 2, 't', %L, 'ZT7 conteo físico de bodega')$$, sv, v_cod, hoy + 1), '22023', 'fecha');
  perform pg_temp.err('05.05 el operador sin el formulario de entrada no registra', format($$select public.geoportal_tec_quimico_entrada(%L, '{"quimico": %s, "cantidad": 1, "unidad": "t"}', null)$$, op2, to_jsonb(v_cod)), '42501');
  v_r := public.geoportal_tec_quimico_entrada(op, jsonb_build_object('quimico', v_cod, 'cantidad', 1.5, 'unidad', 't', 'proveedor', 'ZT7 Proveedor', 'remision', 'R-77', 'lote', 'L-1', 'vence', hoy + 365), 'zt7-entrada-0001');
  perform pg_temp.reg('05.06 entrada de 1,5 t: se guarda como 1.500 kg con proveedor, remisión, lote y vencimiento; saldo 3.500', (v_r ->> 'cantidad_kg')::numeric = 1500 and pg_temp.saldo(v_cod) = 3500
     and (select proveedor || '|' || remision || '|' || lote_fabricante || '|' || unidad || '|' || cantidad from tecnica.quimico_movimientos where id = (v_r ->> 'movimiento_id')::bigint) = 'ZT7 Proveedor|R-77|L-1|t|1.5', v_r::text);
  v_x := public.geoportal_tec_quimico_entrada(op, jsonb_build_object('quimico', v_cod, 'cantidad', 1.5, 'unidad', 't'), 'zt7-entrada-0001');
  perform pg_temp.reg('05.07 el reintento con la misma clave no duplica', (v_x ->> 'repetido')::boolean and pg_temp.saldo(v_cod) = 3500);
  perform pg_temp.err('05.08 la entrada con día futuro', format($$select public.geoportal_tec_quimico_entrada(%L, '{"quimico": %s, "cantidad": 1, "unidad": "t", "dia": %s}', null)$$, op, to_jsonb(v_cod), to_jsonb(hoy + 1)), '22023', 'futuro');
  perform pg_temp.err('05.09 la entrada de hace 20 días (el tope es 7)', format($$select public.geoportal_tec_quimico_entrada(%L, '{"quimico": %s, "cantidad": 1, "unidad": "t", "dia": %s}', null)$$, op, to_jsonb(v_cod), to_jsonb(hoy - 20)), '22023', 'días atrás');
  perform pg_temp.err('05.10 una unidad que no es t ni kg', format($$select public.geoportal_tec_quimico_entrada(%L, '{"quimico": %s, "cantidad": 1, "unidad": "lb"}', null)$$, op, to_jsonb(v_cod)), '22023', 'unidad');
  perform pg_temp.err('05.11 el uso para dosificar sin la planta', format($$select public.geoportal_tec_quimico_uso(%L, '{"quimico": %s, "cantidad": 100, "para_que": "dosificacion"}', null)$$, op, to_jsonb(v_cod)), '22023', 'planta');
  v_r := public.geoportal_tec_quimico_uso(op, jsonb_build_object('quimico', v_cod, 'cantidad', 200, 'unidad', 'kg', 'para_que', 'dosificacion', 'planta', 'huaricha'), 'zt7-uso-0001');
  perform pg_temp.reg('05.12 uso de 200 kg para dosificar en Huaricha: resta del saldo (3.300) y guarda la dosis óptima vigente (20 ppm)',
     (v_r ->> 'cantidad_kg')::numeric = -200 and (v_r ->> 'dosis_optima_ppm')::numeric = 20 and pg_temp.saldo(v_cod) = 3300, v_r::text);
  perform public.geoportal_tec_quimico_uso(op, jsonb_build_object('quimico', 'hipoclorito_calcio', 'cantidad', 5, 'para_que', 'limpieza'), null);
  perform pg_temp.reg('05.13 el hipoclorito para limpieza no pide planta', exists (select 1 from tecnica.quimico_movimientos m join tecnica.quimicos q on q.id = m.quimico_id
     where q.codigo = 'hipoclorito_calcio' and m.para_que = 'limpieza' and m.planta_id is null and m.cantidad_kg = -5));
  v_r := public.geoportal_tec_quimico_ajuste(sv, v_cod, -50, 'ZT7 faltante del conteo semanal');
  perform pg_temp.reg('05.14 ajuste de −50 kg con motivo: saldo 3.250', (v_r ->> 'saldo_kg')::numeric = 3250);
  perform pg_temp.err('05.15 el operador no ajusta', format($$select public.geoportal_tec_quimico_ajuste(%L, %L, 10, 'ZT7 ajuste no permitido')$$, op, v_cod), '42501');
  perform pg_temp.err('05.16 los movimientos no se cambian', $$update tecnica.quimico_movimientos set cantidad = 1$$, '42501');
  perform pg_temp.err('05.17 la regla de la tabla: los kg cuadran con las toneladas', format($$insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, autor)
     select 'entrada', id, 1, 't', 900, current_date, 'x' from tecnica.quimicos where codigo = %L$$, v_cod), '23514');
  v_x := public.geoportal_tec_quimicos_formulario(op, 'uso_quimicos');
  perform pg_temp.reg('05.18 el formulario del operador: químicos activos (sin saldo), plantas, para qué y días atrás',
     exists (select 1 from jsonb_array_elements(v_x -> 'quimicos') x where x ->> 'codigo' = v_cod) and not (v_x::text like '%saldo%') and (v_x ->> 'dias_atras')::numeric = 7
     and v_x -> 'para_que' = '["dosificacion", "limpieza", "otro"]'::jsonb);

  -- ===================== 06. Esperado contra usado (marca encendida) =====================
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'entrada', v.id, p.id, 500, hoy, make_time(h, 0, 0), op from tecnica.variables v, tecnica.plantas p, generate_series(0, 2) h where v.codigo = 'caudal_qi' and p.codigo = 'huaricha';
  select avg(r.valor) into v_qi from tecnica.v_registros_estado r join tecnica.plantas p on p.id = r.planta_id
   where r.formulario::text = 'entrada' and p.codigo = 'huaricha' and r.fecha_muestra = hoy and not r.excluido and r.variable_id = (select id from tecnica.variables where codigo = 'caudal_qi');
  v_esp := round(20 * v_qi * 86.4 / 1000, 1);
  -- la dosis óptima cambia DESPUÉS del uso: la comparación de hoy sigue con la que guardó el uso (20)
  perform public.geoportal_tec_quimico_fijar(sv, v_cod, '{"dosis_optima_ppm": 30}', pg_temp.pdf(sv), 'ZT7 nueva dosis del jar test');
  perform pg_temp.reg('04.06 la dosis óptima cambia con su PDF: evento con el antes en el historial', (select dosis_optima_ppm from tecnica.v_quimico_vigente where codigo = v_cod) = 30
     and (select count(*) from tecnica.quimico_ficha_eventos e join tecnica.quimicos q on q.id = e.quimico_id where q.codigo = v_cod and e.tipo in ('alta', 'dosis_optima')) = 2);
  v_r := public.geoportal_tec_quimicos_comparacion(sv, hoy - 2, hoy);
  v_x := pg_temp.fila(v_r, v_cod, 'huaricha');
  perform pg_temp.reg('06.01 hoy en Huaricha: volumen = Qi promedio × 86,4; esperado = 20 ppm (la del uso) × volumen / 1.000; usado 200 kg',
     (v_x ->> 'dosis_optima_ppm')::numeric = 20 and (v_x ->> 'esperado_kg')::numeric = v_esp and (v_x ->> 'usado_kg')::numeric = 200, coalesce(v_x::text, 'sin fila') || ' · esperado ' || v_esp);
  perform pg_temp.reg('06.02 la marca sale si se aparta más del 25 %', (v_x ->> 'marca')::boolean = (abs(200 - v_esp) > v_esp * 0.25) and (v_r ->> 'marca_activa')::boolean);
  perform pg_temp.reg('06.03 la dosis nueva (30) cuenta para un uso nuevo', (public.geoportal_tec_quimico_uso(op, jsonb_build_object('quimico', v_cod, 'cantidad', 10, 'para_que', 'dosificacion', 'planta', 'huaricha'), null) ->> 'dosis_optima_ppm')::numeric = 30);
  perform pg_temp.err('06.04 el operador no ve la comparación', format($$select public.geoportal_tec_quimicos_comparacion(%L, null, null)$$, op), '42501');
  perform pg_temp.err('06.05 un rango de más de 3 meses', format($$select public.geoportal_tec_quimicos_comparacion(%L, %L, %L)$$, sv, hoy - 200, hoy), '22023', '3 meses');

  -- ===================== 07. Desactivar y volver a activar =====================
  v_r := public.geoportal_tec_quimico_fijar(sv, v_cod, '{"activo": false}', null, 'ZT7 se dejó de usar en la planta');
  perform pg_temp.reg('07.01 desactivado con motivo: sale del formulario del operador; queda en el catálogo del supervisor con su historial',
     not (select activo from tecnica.quimicos where codigo = v_cod) and not exists (select 1 from jsonb_array_elements(public.geoportal_tec_quimicos_formulario(op, 'uso_quimicos') -> 'quimicos') x where x ->> 'codigo' = v_cod)
     and exists (select 1 from jsonb_array_elements(public.geoportal_tec_quimicos_catalogo(sv) -> 'quimicos') x where x ->> 'codigo' = v_cod and not (x ->> 'activo')::boolean)
     and jsonb_array_length(public.geoportal_tec_quimico_historial(sv, v_cod) -> 'eventos') >= 4);
  perform pg_temp.err('07.02 un químico desactivado no recibe usos', format($$select public.geoportal_tec_quimico_uso(%L, '{"quimico": %s, "cantidad": 1, "para_que": "otro"}', null)$$, op, to_jsonb(v_cod)), '22023', 'desactivado');
  perform public.geoportal_tec_quimico_fijar(a, v_cod, '{"activo": true}', null, 'ZT7 se volvió a usar');
  perform pg_temp.reg('07.03 el administrador lo reactiva', (select activo from tecnica.quimicos where codigo = v_cod));
  perform pg_temp.reg('07.04 el historial trae eventos y movimientos (sin la ruta del PDF a la vista del operador: el operador no tiene la ruta)',
     jsonb_array_length(public.geoportal_tec_quimico_historial(sv, v_cod) -> 'movimientos') >= 5);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · CORTE 7a (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
