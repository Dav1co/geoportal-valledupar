-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes11.*), sus contratos de prueba (99000000xxxx, con predio, cartera y ficha, como la suite
-- viva de Análisis de contrato), sus puntos de muestreo (MUE-95nn) con sus muestras, y una referencia propia de Muestreo para un punto.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 6b … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4200 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.3000 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.trae(p_b64 text, p_txt text) returns boolean language sql as $$
  select coalesce(position(convert_to(p_txt, 'UTF8') in decode(nullif(p_b64, ''), 'base64')) > 0, false) $$;
create function pg_temp.tesela(p_quien text, p_z integer, x numeric, y numeric) returns text language sql as $$
  select public.geoportal_redes_geovisor_mvt_contratos(p_quien, p_z, floor((pg_temp.lon(x) + 180) / 360 * (1 << p_z))::integer,
                                                       floor((1 - ln(tan(radians(pg_temp.lat(y))) + 1 / cos(radians(pg_temp.lat(y)))) / pi()) / 2 * (1 << p_z))::integer) $$;
create function pg_temp.meses6(p_ult text, p_m3 integer[]) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('periodo', to_char(to_date(p_ult, 'YYYYMM') - make_interval(months => 6 - k), 'YYYYMM'), 'sin_dato', p_m3[k] is null, 'm3', p_m3[k],
                                      'metodo', case when p_m3[k] is null then null else 'lectura' end, 'lectura_real', p_m3[k] is not null, 'causal', '99 LECTURA NORMAL') order by k)
    from generate_series(1, 6) k $$;
create function pg_temp.prop(p jsonb, p_codigo text) returns jsonb language sql as $$
  select f -> 'properties' from jsonb_array_elements(p -> 'features') f where f -> 'properties' ->> 'codigo' = p_codigo $$;

do $prueba$
declare
  a text := 'prueba.redes11.adm@emdupar.gov.co'; sd text := 'prueba.redes11.dist@emdupar.gov.co'; sv text := 'prueba.redes11.planta@emdupar.gov.co';
  op text := 'prueba.redes11.op@emdupar.gov.co'; na text := 'prueba.redes11.nada@emdupar.gov.co';
  C1 text := '990000001101'; C2 text := '990000001102'; C3 text := '990000001103'; C4 text := '990000001104';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_r jsonb; v_x jsonb; v_t text; v_n integer; v_id text; v_aud0 integer; v_p1 bigint; v_p2 bigint; v_p3 bigint; v_p4 bigint; v_ref jsonb;
  v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT11 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT11 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT11 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT11 Operador', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT11 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT11 necesita ver la red en la calle');

  -- ===================== 01. Esquema =====================
  perform pg_temp.reg('01.01 la capa de contratos no tiene columnas de nombre, dirección, teléfono, barrio ni deuda',
     not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'contratos_capa' and column_name ~ '(nombre|direccion|telefono|deuda|barrio|saldo)'));
  perform pg_temp.reg('01.02 el catálogo: contratos con capa propia (solo supervisores), reportes de Comercial por fecha, 6 preparadas',
     (select fuente || '|' || estado || '|' || solo_completo from redes.geovisor_capas where codigo = 'contratos') = 'contratos|activa|true'
     and (select fuente || '|' || por_fecha || '|' || solo_completo from redes.geovisor_capas where codigo = 'reportes_comercial') = 'geojson|true|true'
     and (select count(*) from redes.geovisor_capas where fuente = 'preparada') = 6);
  perform pg_temp.reg('01.03 los rangos del muestreo: cloro con el de Salida del tanque y turbiedad con la de salida', (select string_agg(variable_muestreo || '>' || variable_salida, ',' order by orden) from redes.muestreo_rangos)
     = 'cloro_residual_libre>cloro_libre_tanque,turbiedad>turbiedad_salida');
  perform pg_temp.reg('01.04 los 3 parámetros nuevos', (select count(*) from redes.parametros where clave in ('geovisor_zoom_contratos', 'geovisor_contratos_horas', 'geovisor_muestreo_dias')) = 3);
  perform pg_temp.reg('01.06 la capa de reportes de Comercial existe y está vacía hasta el Corte 8', (select count(*) from redes.v_reportes_comercial) = 0);

  -- ===================== 02. Capa de contratos =====================
  insert into public.cartera_suscripcion (contrato, estado, identificacion, nombre, correo, telefono, direccion, barrio, categoria, subcategoria, ciclo,
                                          facturas_pendientes, deuda_total, saldo_pendiente, saldo_a_favor, valor_reclamo, saldo_financiado, serial_medidor, ruta, periodo_carga)
  values (C1, 'RETIRADO', 'DOC-PRUEBA-1', 'NOMBRE VIEJO DE PRUEBA', null, '3001112233', 'DIR VIEJA', 'ZT11 BARRIO VIEJO', '1 Residencial', '2 Estrato 2', '7', 9, 412300, 98000, 0, 0, 0, 'ZTM1', '0701', '20200101'),
         (C1, 'ACTIVO', 'DOC-PRUEBA-1', 'NOMBRE DE PRUEBA ONCE', null, '3001112233', 'CRA ZT11 1 2 3', 'ZT11 BARRIO CARTERA', '1 Residencial', '2 Estrato 2', '7', 9, 412300, 98000, 0, 0, 0, 'ZTM1', '0701', '29991231'),
         (C2, 'RETIRADO', 'DOC-PRUEBA-2', 'NOMBRE DE PRUEBA DOCE', null, null, 'CRA ZT11 9 9', 'ZT11 BARRIO CARTERA', '2 Comercial', '201 1/2', '7', 0, 0, 0, 0, 0, 0, null, '0702', '29991231');
  insert into public.catastro_valledupar (cod_usuario, direccion, barrio, geom)
  values (C1, 'CRA ZT11 1 2 3 CATASTRO', 'ZT11 BARRIO CATASTRO', pg_temp.pt(0, 0)), (C1, 'OTRO PREDIO', 'ZT11 BARRIO CATASTRO', pg_temp.pt(400, 400)),
         (C2, 'CRA ZT11 9 9', 'ZT11 BARRIO CATASTRO', pg_temp.pt(30, 0)), (C3, 'CRA ZT11 SOLO CATASTRO', 'ZT11 OTRO', pg_temp.pt(60, 0)), ('99999999', 'COMODIN', 'X', pg_temp.pt(90, 0));
  insert into bi_interno.ficha_contrato (contrato, periodo_ultimo, uso, consumo_meses, cons_prom, meses_con_lectura, medidor_fecha_estado, medidor_anios)
  values (C1, '202610', 'Residencial', pg_temp.meses6('202610', array[7, null, 9, 6, 5, 6]), 6.6, 5, 'real', 12);
  v_n := redes.f_refrescar_contratos_capa();
  perform pg_temp.reg('02.01 la capa se rehace con los contratos del catastro (al menos los 3 de prueba) y deja su estado',
     v_n >= 3 and (select filas from redes.contratos_capa_estado where id = 1) = v_n and (select count(*) from redes.contratos_capa where contrato in (C1, C2, C3)) = 3, v_n::text);
  perform pg_temp.reg('02.02 un punto por contrato: el del predio de menor id; con uso, estado del último corte de la cartera, consumo y años del medidor',
     (select ST_Equals(geom, pg_temp.pt(0, 0)) and uso = 'Residencial' and estado = 'activo' and consumo_prom = 6.6 and medidor_anios = 12 from redes.contratos_capa where contrato = C1));
  perform pg_temp.reg('02.03 retirado: sin ficha toma el uso de la cartera sin su número («Comercial»); sin cartera: estado «sin_dato»',
     (select estado || '|' || uso from redes.contratos_capa where contrato = C2) = 'retirado|Comercial' and (select estado from redes.contratos_capa where contrato = C3) = 'sin_dato');
  perform pg_temp.reg('02.04 el comodín 99999999 y el «0» no entran', not exists (select 1 from redes.contratos_capa where contrato in ('99999999', '0')));
  perform pg_temp.reg('02.05 «al día»: con la misma ficha y menos de un día, no la rehace', not redes.f_contratos_capa_al_dia());
  update bi_interno.ficha_contrato_estado set calculado_en = clock_timestamp() + interval '1 minute' where id = 1;
  if not found then insert into bi_interno.ficha_contrato_estado (id, firma, filas, calculado_en, duracion_ms) values (1, 'zt11', 1, clock_timestamp() + interval '1 minute', 1); end if;
  perform pg_temp.reg('02.06 si cambió la ficha del contrato (cálculo mensual), la rehace', redes.f_contratos_capa_al_dia());
  v_r := public.geoportal_redes_geovisor(sd);
  perform pg_temp.reg('02.07 la configuración del supervisor trae el zoom de contratos, «compartir» y el estado de la capa', (v_r -> 'zoom' ->> 'contratos')::numeric = 16
     and (v_r ->> 'compartir')::boolean and (v_r -> 'contratos_capa' ->> 'filas')::integer >= 3 and 'contratos' = any (select jsonb_array_elements(v_r -> 'capas') ->> 'codigo'));
  v_r := public.geoportal_redes_geovisor(op);
  perform pg_temp.reg('02.08 el operador en solo lectura: sin contratos, sin «compartir» y sin el estado de la capa', not (v_r ->> 'compartir')::boolean and v_r -> 'contratos_capa' = 'null'::jsonb
     and not ('contratos' = any (select jsonb_array_elements(v_r -> 'capas') ->> 'codigo')));
  -- tesela
  perform pg_temp.reg('02.09 la tesela de contratos: vacía a zoom 15; a zoom 17 trae el número, el estado y el uso', pg_temp.tesela(sd, 15, 0, 0) = ''
     and pg_temp.trae(pg_temp.tesela(sd, 17, 0, 0), C1) and pg_temp.trae(pg_temp.tesela(sd, 17, 0, 0), 'activo') and pg_temp.trae(pg_temp.tesela(sd, 17, 0, 0), 'Residencial'));
  v_t := pg_temp.tesela(a, 17, 0, 0);
  perform pg_temp.reg('02.10 la tesela no lleva nombre, dirección, barrio ni teléfono', not pg_temp.trae(v_t, 'NOMBRE DE PRUEBA') and not pg_temp.trae(v_t, 'CRA ZT11') and not pg_temp.trae(v_t, 'ZT11 BARRIO')
     and not pg_temp.trae(v_t, '3001112233'));
  perform pg_temp.err('02.11 el operador no pide la tesela de contratos', format($$select pg_temp.tesela(%L, 17, 0, 0)$$, op), '42501');
  perform pg_temp.err('02.12 quien no tiene el geovisor tampoco', format($$select pg_temp.tesela(%L, 17, 0, 0)$$, na), '42501');
  perform pg_temp.reg('02.13 el supervisor de planta sí (geovisor completo)', pg_temp.trae(pg_temp.tesela(sv, 17, 0, 0), C1));

  -- ===================== 03. Tarjeta del contrato (§30.1) =====================
  select count(*) into v_aud0 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta';
  v_r := public.geoportal_redes_contrato_tarjeta(sd, C1, '10.0.0.7');
  perform pg_temp.reg('03.01 la tarjeta trae número, estado (activo), uso, el perfil de consumo de 6 meses (con el hueco) y los años del medidor',
     v_r ->> 'contrato' = C1 and v_r ->> 'estado' = 'activo' and v_r ->> 'estado_texto' = 'ACTIVO' and v_r ->> 'uso' = 'Residencial'
     and jsonb_array_length(v_r -> 'consumo' -> 'meses') = 6 and (v_r -> 'consumo' -> 'meses' -> 1 ->> 'sin_dato')::boolean and (v_r -> 'consumo' ->> 'promedio')::numeric = 6.6
     and (v_r ->> 'medidor_anios')::integer = 12, left(v_r::text, 400));
  perform pg_temp.reg('03.02 nombre, dirección (la del catastro) y barrio (el de la cartera) del ÚLTIMO corte', v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA ONCE'
     and v_r -> 'suscriptor' ->> 'direccion' = 'CRA ZT11 1 2 3 CATASTRO' and v_r -> 'suscriptor' ->> 'barrio' = 'ZT11 BARRIO CARTERA', (v_r -> 'suscriptor')::text);
  perform pg_temp.reg('03.03 sin teléfono, deuda, documento ni saldos', v_r::text not like '%3001112233%' and v_r::text not like '%412300%' and v_r::text not like '%DOC-PRUEBA%'
     and not (v_r ? 'deuda_total') and not (v_r -> 'suscriptor' ? 'telefonos'));
  perform pg_temp.reg('03.04 la lectura queda en la auditoría (quién, contrato e IP) sin el nombre ni la dirección',
     (select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta') = v_aud0 + 1
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta' and email = sd and referencia = C1 and ip = '10.0.0.7'
                   and detalle::text not like '%NOMBRE DE PRUEBA%' and detalle::text not like '%CRA ZT11%'));
  v_r := public.geoportal_redes_contrato_tarjeta(a, C2);
  perform pg_temp.reg('03.05 un contrato retirado y sin ficha: «retirado», sin consumo, con nombre y dirección', v_r ->> 'estado' = 'retirado' and v_r -> 'consumo' = 'null'::jsonb
     and v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA DOCE');
  v_r := public.geoportal_redes_contrato_tarjeta(sv, C3);
  perform pg_temp.reg('03.06 sin cartera: sin nombre, con la dirección y el barrio del catastro', v_r -> 'suscriptor' ->> 'nombre' is null and v_r -> 'suscriptor' ->> 'barrio' = 'ZT11 OTRO');
  perform pg_temp.err('03.07 el operador en solo lectura no abre la tarjeta del contrato', format($$select public.geoportal_redes_contrato_tarjeta(%L, %L)$$, op, C1), '42501');
  perform pg_temp.err('03.08 quien no es de Técnica tampoco', format($$select public.geoportal_redes_contrato_tarjeta(%L, %L)$$, na, C1), '42501');
  perform pg_temp.reg('03.09 los intentos negados no dejan lectura', (select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta') = v_aud0 + 3);
  perform pg_temp.err('03.10 un contrato mal escrito', format($$select public.geoportal_redes_contrato_tarjeta(%L, '12A')$$, sd), '22023', 'números');
  perform pg_temp.err('03.11 un contrato fuera de la capa (el comodín)', format($$select public.geoportal_redes_contrato_tarjeta(%L, '99999999')$$, sd), 'P0002');

  -- ===================== 04. Compartir la vista (§30.2) =====================
  v_x := jsonb_build_object('capas', jsonb_build_array('acu_tramos', 'danos', 'contratos', 'muestreo'), 'colores', 'material',
                            'periodo', jsonb_build_object('modo', 'rango', 'desde', hoy - 30, 'hasta', hoy), 'lon', -73.25, 'lat', 10.46, 'zoom', 16.5, 'atenuadas', jsonb_build_array('reportes_comercial'));
  v_r := public.geoportal_redes_vista_compartir(sd, v_x);
  v_id := v_r ->> 'id';
  perform pg_temp.reg('04.01 el supervisor comparte la vista: un código de 10 letras y números, guardado con su autor y en la auditoría',
     v_id ~ '^[a-z0-9]{10}$' and (select autor || '|' || colores || '|' || array_to_string(capas, ',') from redes.vistas_compartidas where id = v_id) = sd || '|material|acu_tramos,contratos,danos,muestreo'
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_vista_compartir' and referencia = v_id), v_r::text);
  perform pg_temp.reg('04.02 la vista no guarda datos personales (solo capas, colores, fechas, centro y zoom)',
     (select to_jsonb(v) - 'id' - 'autor' - 'creado_en' from redes.vistas_compartidas v where id = v_id)::text !~* '(nombre|direcci|telefono|suscriptor)');
  perform pg_temp.err('04.02b una vista compartida no se cambia ni se borra', format($$update redes.vistas_compartidas set zoom = 12 where id = %L$$, v_id), '42501');
  v_r := public.geoportal_redes_vista_abrir(a, v_id);
  perform pg_temp.reg('04.03 el administrador la abre igual: capas, colores, el rango de fechas, centro y zoom; nada omitido',
     v_r -> 'capas' = '["acu_tramos", "contratos", "danos", "muestreo"]'::jsonb and v_r ->> 'colores' = 'material' and (v_r -> 'periodo' ->> 'desde')::date = hoy - 30
     and (v_r ->> 'zoom')::numeric = 16.5 and jsonb_array_length(v_r -> 'omitidas') = 0 and exists (select 1 from public.geoportal_auditoria where accion = 'redes_vista_abrir' and email = a and referencia = v_id), v_r::text);
  v_r := public.geoportal_redes_vista_abrir(op, v_id);
  perform pg_temp.reg('04.04 el operador con la casilla la abre sin las capas que no ve (contratos y muestreo, nombradas) y con las actividades de hoy',
     v_r -> 'capas' = '["acu_tramos", "danos"]'::jsonb and v_r -> 'omitidas' @> '["Contratos (consumo y edad del medidor)", "Puntos de muestreo"]'::jsonb
     and (v_r -> 'periodo' ->> 'modo') = 'hoy' and (v_r -> 'periodo' ->> 'desde')::date = hoy and (v_r ->> 'fechas_cambiadas')::boolean, v_r::text);
  perform pg_temp.err('04.05 quien no tiene el geovisor no abre el enlace', format($$select public.geoportal_redes_vista_abrir(%L, %L)$$, na, v_id), '42501');
  perform pg_temp.err('04.06 un enlace que no existe', format($$select public.geoportal_redes_vista_abrir(%L, 'zzzzzzzzzz')$$, sd), 'P0002');
  perform pg_temp.err('04.07 un enlace mal formado', format($$select public.geoportal_redes_vista_abrir(%L, 'ABC')$$, sd), '22023');
  perform pg_temp.err('04.08 el operador en solo lectura no comparte', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, op, v_x), '42501');
  perform pg_temp.err('04.09 una capa que no existe', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, sd, v_x || '{"capas": ["acu_tramos", "inventada"]}'), '22023', 'inventada');
  perform pg_temp.err('04.10 una capa preparada no se comparte', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, sd, v_x || '{"capas": ["presion"]}'), '22023', 'presion');
  perform pg_temp.err('04.11 un rango de más de 12 meses', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, sd,
     v_x || jsonb_build_object('periodo', jsonb_build_object('modo', 'rango', 'desde', hoy - 400, 'hasta', hoy))), '22023', 'rango');
  perform pg_temp.err('04.12 un centro fuera de Valledupar', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, sd, v_x || '{"lon": -74.08, "lat": 4.6}'), '22023', 'fuera de Valledupar');
  perform pg_temp.err('04.13 unos colores que no existen', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, sd, v_x || '{"colores": "arcoiris"}'), '22023', 'colores');
  v_r := public.geoportal_redes_vista_compartir(sv, v_x || '{"periodo": {"modo": "semana"}}');
  perform pg_temp.reg('04.14 «7 días» guarda el modo y, al abrirla otro día, son los 7 días de ese día', (public.geoportal_redes_vista_abrir(sd, v_r ->> 'id') -> 'periodo' ->> 'desde')::date = hoy - 6);

  -- ===================== 05. Color del muestreo (rangos de Salida, respuesta 4 de David al 6a) =====================
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9501', 'ZT11 Uno', 'muestreo', 'norte'), ('MUE-9502', 'ZT11 Dos', 'muestreo', 'sur'),
    ('MUE-9503', 'ZT11 Tres', 'muestreo', 'medio'), ('MUE-9504', 'ZT11 Cuatro', 'muestreo', 'medio');
  select id into v_p1 from tecnica.puntos where codigo = 'MUE-9501'; select id into v_p2 from tecnica.puntos where codigo = 'MUE-9502';
  select id into v_p3 from tecnica.puntos where codigo = 'MUE-9503'; select id into v_p4 from tecnica.puntos where codigo = 'MUE-9504';
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, autor)
  select id, pg_temp.lat(500 + id % 50), pg_temp.lon(500), 'verificada', 'david', a from tecnica.puntos where codigo like 'MUE-95__';
  -- el rango de Salida del cloro, como lo resuelve planta (general o, si no hay, el más estricto por planta)
  select coalesce((select jsonb_build_object('min', x.ref_min, 'max', x.ref_max) from tecnica.f_referencia_vigente((select id from tecnica.variables where codigo = 'cloro_libre_tanque'), null, null) x),
                  (select jsonb_build_object('min', max(r.ref_min), 'max', min(r.ref_max)) from tecnica.referencias r where r.activa and r.punto_id is null
                      and r.variable_id = (select id from tecnica.variables where codigo = 'cloro_libre_tanque'))) into v_ref;
  insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'muestreo', v.id, x.p, x.valor, hoy - x.dias, x.hora::time, op
    from (values (v_p1, 'cloro_residual_libre', 1000.0, 0, '06:00'), (v_p1, 'cloro_residual_libre', 1.0, 1, '06:00'),   -- el último (hoy) es absurdo: se sale de cualquier rango
                 (v_p2, 'ph', 7.0, 0, '06:00'),                                                                         -- el pH no colorea
                 (v_p3, 'cloro_residual_libre', 1000.0, 1, '00:00'),                                                    -- de ayer a la medianoche (para la prueba de «reciente»)
                 (v_p4, 'cloro_residual_libre', 1000.0, 0, '06:00')) x(p, cod, valor, dias, hora)
    join tecnica.variables v on v.codigo = x.cod;
  v_r := public.geoportal_redes_geovisor_capa(sv, 'muestreo');
  perform pg_temp.reg('05.01 un punto con el último cloro fuera del rango de Salida sale «fuera», con su valor, la fecha y el rango (de Salida)',
     (v_ref ->> 'min' is null and v_ref ->> 'max' is null and pg_temp.prop(v_r, 'MUE-9501') ->> 'calidad' = 'sin_rango')
     or (pg_temp.prop(v_r, 'MUE-9501') ->> 'calidad' = 'fuera' and (pg_temp.prop(v_r, 'MUE-9501') -> 'medidas' -> 0 ->> 'valor')::numeric = 1000
         and pg_temp.prop(v_r, 'MUE-9501') -> 'medidas' -> 0 ->> 'rango' = 'salida'), (pg_temp.prop(v_r, 'MUE-9501'))::text || ' · ref ' || coalesce(v_ref::text, 'ninguna'));
  perform pg_temp.reg('05.02 sin cloro ni turbiedad (solo pH): «sin_muestra»', pg_temp.prop(v_r, 'MUE-9502') ->> 'calidad' = 'sin_muestra');
  update redes.parametros set valor = 1 where clave = 'geovisor_muestreo_dias';      -- con 1 día, la de ayer a la medianoche ya no es reciente
  v_x := pg_temp.prop(public.geoportal_redes_geovisor_capa(sv, 'muestreo'), 'MUE-9503');
  update redes.parametros set valor = 30 where clave = 'geovisor_muestreo_dias';
  perform pg_temp.reg('05.03 una muestra más vieja que «geovisor_muestreo_dias» no colorea («sin_muestra», marcada como no reciente); con 30 días sí cuenta',
     v_x ->> 'calidad' = 'sin_muestra' and not (v_x -> 'medidas' -> 0 ->> 'reciente')::boolean and pg_temp.prop(v_r, 'MUE-9503') ->> 'calidad' <> 'sin_muestra', v_x::text);
  insert into tecnica.exclusiones (registro_id, accion, motivo, autor)
  select r.id, 'EXCLUIR', 'ZT11 valor de prueba mal digitado', a from tecnica.registros r where r.punto_id = v_p1 and r.valor = 1000;
  v_r := public.geoportal_redes_geovisor_capa(sv, 'muestreo');
  perform pg_temp.reg('05.04 si se excluye ese registro, cuenta la muestra anterior (1,0 mg/L) y queda dentro del rango',
     (pg_temp.prop(v_r, 'MUE-9501') -> 'medidas' -> 0 ->> 'valor')::numeric = 1.0
     and (pg_temp.prop(v_r, 'MUE-9501') ->> 'calidad' = case when coalesce((v_ref ->> 'min')::numeric, 0) <= 1 and coalesce((v_ref ->> 'max')::numeric, 99) >= 1 and v_ref is not null
                                                              and (v_ref ->> 'min' is not null or v_ref ->> 'max' is not null) then 'dentro' else pg_temp.prop(v_r, 'MUE-9501') ->> 'calidad' end),
     (pg_temp.prop(v_r, 'MUE-9501'))::text);
  -- una referencia propia de Muestreo para un punto gana sobre la de Salida
  insert into tecnica.referencias (variable_id, punto_id, ref_min, ref_max, origen, fuente)
  select id, v_p4, 0, 2000, 'criterio_planta', 'ZT11 referencia de prueba del punto' from tecnica.variables where codigo = 'cloro_residual_libre';
  v_r := public.geoportal_redes_geovisor_capa(sv, 'muestreo');
  perform pg_temp.reg('05.05 la referencia propia del punto (Muestreo) gana sobre la de Salida: 1000 queda «dentro» con rango «muestreo»',
     pg_temp.prop(v_r, 'MUE-9504') ->> 'calidad' = 'dentro' and pg_temp.prop(v_r, 'MUE-9504') -> 'medidas' -> 0 ->> 'rango' = 'muestreo', (pg_temp.prop(v_r, 'MUE-9504'))::text);
  perform pg_temp.reg('05.06 la capa sigue sin datos personales (sin el autor de la muestra)', v_r::text not like '%' || op || '%');

  -- ===================== 06. Reportes de Comercial (§30.4), vacía hasta el Corte 8 =====================
  v_r := public.geoportal_redes_geovisor_capa(sd, 'reportes_comercial', hoy - 7, hoy);
  perform pg_temp.reg('06.01 la capa de reportes de Comercial responde vacía (la llena el Corte 8)', v_r ->> 'type' = 'FeatureCollection' and jsonb_array_length(v_r -> 'features') = 0);
  perform pg_temp.err('06.02 el operador no la ve', format($$select public.geoportal_redes_geovisor_capa(%L, 'reportes_comercial')$$, op), '42501');
  perform pg_temp.reg('06.03 las demás capas por fecha siguen igual (daños de hoy)', public.geoportal_redes_geovisor_capa(sd, 'danos') ->> 'type' = 'FeatureCollection');

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 6b (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
