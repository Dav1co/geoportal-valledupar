-- =====================================================================
-- TÉCNICA · FASE 1 · EVENTOS: ORIGEN Y TUBOS · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 25, 26 y 40, en la misma transacción.
-- Todo es SIMULADO y se deshace: personas prueba.evt.*, una planta ZTEVT, 3 tubos de salida ZTEVT (uno sin sectores), un punto de muestreo ZTEVT,
-- 3 sectores ZTEVT en un rincón de la caja, un tramo y un contrato de prueba (999999991001), daños e intervención de prueba.
-- CADA PRUEBA CUENTA SOLO SUS FILAS DE PRUEBA (lección del 20-nov: 08.02 y 17.01 dependían de que la base real estuviera vacía).
-- Los textos libres de prueba llevan un nombre y un teléfono inventados («ZTEVT Pedro Prueba 3009990000») para comprobar que no salen en las descargas.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · eventos (origen y tubos) … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.1300 + y * 0.0000090437, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.5800 + x * 0.0000091290, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.caja(x1 numeric, y1 numeric, x2 numeric, y2 numeric) returns geometry language sql as $$
  select ST_Multi(ST_MakeEnvelope(pg_temp.lon(x1), pg_temp.lat(y1), pg_temp.lon(x2), pg_temp.lat(y2), 4326)) $$;
create temp table _zt (nombre text primary key, activo_id bigint, codigo text);
create function pg_temp.activo(p_nombre text, p_prefijo text, p_geom geometry, p_clase text default null, p_atributos jsonb default '{}') returns text language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.evt.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZTEVT ' || p_nombre, p_clase, case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end,
          case when p_prefijo = 'RED' then 110 end, 'en_operacion', p_atributos, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZTEVT activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  insert into _zt values (p_nombre, v_id, v_cod);
  return v_cod;
end $$;
create function pg_temp.id(p_nombre text) returns bigint language sql as $$ select activo_id from _zt where nombre = p_nombre $$;
create function pg_temp.cod(p_nombre text) returns text language sql as $$ select codigo from _zt where nombre = p_nombre $$;
create function pg_temp.claves(j jsonb) returns text language sql as $$ select string_agg(k, ',' order by k) from jsonb_object_keys(j) k $$;
-- todas las filas de una descarga de Distribución o del PTAP, página por página
create function pg_temp.bajar(p_esq text, p_quien text, p_rep text, p_f jsonb, p_incl boolean default true) returns jsonb language plpgsql as $$
declare v_i jsonb; v_c text; v_r jsonb; v_todas jsonb := '[]'; i integer := 0;
begin
  v_i := case p_esq when 'redes' then public.geoportal_redes_reporte_iniciar(p_quien, p_rep, p_f, 'xlsx', p_incl, null) else public.geoportal_tec_reporte_iniciar(p_quien, p_rep, p_f, 'xlsx', p_incl, null) end;
  loop
    v_r := case p_esq when 'redes' then public.geoportal_redes_reporte_pagina(p_quien, (v_i ->> 'descarga_id')::bigint, v_c, 5000) else public.geoportal_tec_reporte_pagina(p_quien, (v_i ->> 'descarga_id')::bigint, v_c, 5000) end;
    v_todas := v_todas || (v_r -> 'filas'); v_c := v_r ->> 'cursor'; i := i + 1;
    exit when v_c is null or i > 200;
  end loop;
  return jsonb_build_object('ini', v_i, 'filas', v_todas);
end $$;
create function pg_temp.fila(p_filas jsonb, p_clave text, p_valor text) returns jsonb language sql as $$
  select f from jsonb_array_elements(p_filas) f where f ->> p_clave = p_valor limit 1 $$;
-- la respuesta de evento_contrato sin lo que depende del código o del nombre de la zona (para comparar un evento por tubo con el mismo por sectores)
create function pg_temp.contrato_sin_codigo(j jsonb) returns jsonb language sql as $$
  select (j - 'consultado_en' - 'otros_eventos') || jsonb_build_object('evento', (j -> 'evento') - 'codigo' - 'zona_nombre' - 'texto') $$;

do $prueba$
declare
  adm text := 'prueba.evt.adm@emdupar.gov.co'; sd text := 'prueba.evt.sd@emdupar.gov.co'; sp text := 'prueba.evt.sp@emdupar.gov.co'; op text := 'prueba.evt.op@emdupar.gov.co';
  libre text := 'ZTEVT Pedro Prueba 3009990000'; ct text := '999999991001';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; per jsonb; j jsonb; j2 jsonb; f jsonb; v_txt text; v_pl bigint; v_t1 bigint; v_t2 bigint; v_t3 bigint; v_m1 bigint;
  v_dan text; v_itv text; v_viejo bigint; v_viejo2 bigint; e_tubo text; e_sec text; e_pl text; e_dan text; e_otra text; v_desde text; r_tubo jsonb; r_sec jsonb; v_hay_todo boolean;
  v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_info text; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTEVT Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZTEVT Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZTEVT Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZTEVT Operador', 'consulta', true, 'sin_restriccion', 'todos');
  per := jsonb_build_object('desde', (hoy - 2)::text, 'hasta', hoy::text);
  v_desde := to_char(clock_timestamp() - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SSOF');

  -- ---------- datos de prueba: planta, 3 tubos (T3 sin sectores), un punto de muestreo, 3 sectores, un tramo y un contrato ----------
  insert into tecnica.plantas (codigo, nombre) values ('zt_evt_pl', 'ZTEVT Planta') returning id into v_pl;
  insert into tecnica.puntos (codigo, nombre, tipo, planta_id, orden) values ('ZTEVT-T1', 'ZTEVT Distrito Uno', 'distribucion', v_pl, 9991) returning id into v_t1;
  insert into tecnica.puntos (codigo, nombre, tipo, planta_id, orden) values ('ZTEVT-T2', 'ZTEVT Distrito Dos', 'distribucion', v_pl, 9992) returning id into v_t2;
  insert into tecnica.puntos (codigo, nombre, tipo, planta_id, orden) values ('ZTEVT-T3', 'ZTEVT Distrito Tres', 'distribucion', v_pl, 9993) returning id into v_t3;
  insert into tecnica.puntos (codigo, nombre, tipo) values ('ZTEVT-M1', 'ZTEVT Muestreo', 'muestreo') returning id into v_m1;
  perform pg_temp.activo('S1', 'SEC', pg_temp.caja(0, -50, 300, 250), 'sector', '{"modelo": {"sector": 71}}');
  perform pg_temp.activo('S2', 'SEC', pg_temp.caja(300, -50, 600, 250), 'sector', '{"modelo": {"sector": 72}}');
  perform pg_temp.activo('S3', 'SEC', pg_temp.caja(600, -50, 900, 250), 'sector', '{"modelo": {"sector": 73}}');
  perform pg_temp.activo('T1', 'RED', ST_MakeLine(pg_temp.pt(50, 0), pg_temp.pt(250, 0)));
  insert into redes.contrato_tramo (contrato, activo_id, distancia_m, metodo) values (ct, pg_temp.id('T1'), 3, 'cercania');
  -- daños e intervención de prueba FUERA de las zonas (no se asocian solos)
  v_txt := (select coalesce(max(substr(d.codigo, 5)::integer), 0) from redes.danos d);
  v_dan := 'DAN-' || lpad((v_txt::integer + 1)::text, 6, '0');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, causa_codigo, descripcion, autor)
  values (gen_random_uuid(), v_dan, 'dano', 'fuga', 'acueducto', pg_temp.id('T1'), pg_temp.lat(100), pg_temp.lon(3000), 'gps', clock_timestamp() - interval '2 hours', 'medio', 'propia', 'desgaste', libre, sd),
         (gen_random_uuid(), 'DAN-' || lpad((v_txt::integer + 2)::text, 6, '0'), 'falla', 'electrica', 'acueducto', pg_temp.id('T1'), pg_temp.lat(100), pg_temp.lon(3100), 'gps', clock_timestamp() - interval '2 hours', 'alto', 'desconocida', null, libre, sd);
  v_itv := 'ITV-' || lpad(((select coalesce(max(substr(i.codigo, 5)::integer), 0) from redes.intervenciones i) + 1)::text, 6, '0');
  insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_inicio, t_fin, descripcion, ejecutor, autor)
  select gen_random_uuid(), v_itv, 'dano', d.id, 'reparacion', 'acueducto', pg_temp.id('T1'), pg_temp.lat(100), pg_temp.lon(3100), 'gps', clock_timestamp() - interval '90 minutes', clock_timestamp() - interval '80 minutes', libre, 'emdupar', sd
    from redes.danos d where d.codigo = 'DAN-' || lpad((v_txt::integer + 2)::text, 6, '0');

  -- ---------- 01. Origen obligatorio ----------
  perform pg_temp.err('01.01 ni registro ni causal: «Indique el origen…»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZTEVT observación de prueba')), null, 'Indique el origen: el daño o la intervención, o la causal del trabajo.');
  perform pg_temp.err('01.02 los dos a la vez: «Elija un solo origen…»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZTEVT observación de prueba', 'registro', v_dan, 'causal', 'otra')), null, 'Elija un solo origen: el daño o la intervención, o la causal.');
  perform pg_temp.err('01.03 una causal que no existe: «Esa causal no existe o está desactivada.»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZTEVT observación de prueba', 'causal', 'zt_no_existe')), null, 'Esa causal no existe o está desactivada.');
  perform pg_temp.err('01.04 «Otra» sin observación: «Escriba la observación…»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ab', 'causal', 'otra')), null, 'Escriba la observación (de 5 a 200 letras)');
  perform pg_temp.err('01.05 una clave que no corresponde sigue siendo error', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZTEVT observación de prueba', 'causal', 'otra', 'origen', 'x')), null, 'no corresponde');
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S3')), 'causa', libre, 'causal', 'otra', 'desde', v_desde));
  e_otra := j ->> 'codigo';
  perform pg_temp.reg('01.06 declarado como trabajo con «Otra» y su observación: origen Trabajo, causal {otra, Otra}, sin tubos; queda la causal del evento',
    j -> 'origen' = '{"codigo": "trabajo", "nombre": "Trabajo"}' and j -> 'causal' = '{"codigo": "otra", "nombre": "Otra"}' and j -> 'tubos' = '[]' and j ->> 'causa' = libre
    and exists (select 1 from redes.evento_causal c join redes.eventos_suspension e on e.id = c.evento_id where e.codigo = e_otra and c.causal = 'otra'), j::text);
  perform public.geoportal_redes_evento_anular(sd, e_otra, 'ZTEVT se anula para seguir la prueba');
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S3')), 'causa', 'ZTEVT por el daño', 'registro', v_dan));
  e_dan := j ->> 'codigo';
  perform pg_temp.reg('01.07 declarado por un daño: origen Daño, sin causal', j -> 'origen' ->> 'codigo' = 'dano' and j -> 'origen' ->> 'nombre' = 'Daño' and j -> 'causal' = 'null', j::text);
  perform public.geoportal_redes_evento_anular(sd, e_dan, 'ZTEVT se anula para seguir la prueba');
  -- dos eventos «como antes» (sin causal): uno sin nada y otro con una intervención
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, zona_nombre, causa, desde, contratos, sensibles, autor)
  values ('EVS-991001', 'sectores', false, pg_temp.caja(2000, 0, 2100, 100), array[pg_temp.id('S1')], 'ZTEVT zona vieja', 'ZTEVT evento de antes del cambio', clock_timestamp() - interval '3 hours', 0, 0, sd) returning id into v_viejo;
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, zona_nombre, causa, intervencion_id, desde, contratos, sensibles, autor)
  select 'EVS-991002', 'sectores', false, pg_temp.caja(2200, 0, 2300, 100), array[pg_temp.id('S1')], 'ZTEVT zona vieja 2', 'ZTEVT evento de antes con intervención', i.id, clock_timestamp() - interval '3 hours', 0, 0, sd
    from redes.intervenciones i where i.codigo = v_itv returning id into v_viejo2;
  perform pg_temp.reg('01.08 un evento de antes, sin daño, intervención ni causal: «No registrado (anterior al cambio)»',
    redes.f_evento_json(v_viejo) -> 'origen' = '{"codigo": "no_registrado", "nombre": "No registrado (anterior al cambio)"}' and redes.f_evento_json(v_viejo) -> 'causal' = 'null', (redes.f_evento_json(v_viejo) -> 'origen')::text);
  perform pg_temp.reg('01.09 un evento de antes con intervención sale con su origen real: Intervención', redes.f_evento_json(v_viejo2) -> 'origen' ->> 'nombre' = 'Intervención');

  -- ---------- 02. Causales (catálogo ajustable con historial) ----------
  j := public.geoportal_redes_evento_causal_fijar(adm, null, 'ZTEVT Causal de prueba', true, 'ZTEVT se crea una causal de prueba');
  perform pg_temp.reg('02.01 crear una causal: código armado del nombre, activa, con su hecho «crear»',
    j ->> 'codigo' = 'ztevt_causal_de_prueba' and (j ->> 'activa')::boolean and exists (select 1 from redes.evento_causal_eventos where codigo = 'ztevt_causal_de_prueba' and accion = 'crear' and autor = adm), j::text);
  perform pg_temp.err('02.02 sin motivo: 400', format('select public.geoportal_redes_evento_causal_fijar(%L, null, %L, true, %L)', adm, 'ZTEVT Otra más', 'corto'), null, 'motivo');
  perform pg_temp.err('02.03 un nombre repetido: 400', format('select public.geoportal_redes_evento_causal_fijar(%L, null, %L, true, %L)', adm, 'ztevt causal de prueba', 'ZTEVT nombre repetido a propósito'), null, 'Ya hay una causal');
  j := public.geoportal_redes_evento_causal_fijar(sd, 'ztevt_causal_de_prueba', 'ZTEVT Causal renombrada', false, 'ZTEVT se renombra y se desactiva');
  perform pg_temp.reg('02.04 el supervisor de distribución la renombra y la desactiva; queda el hecho «cambiar»; el catálogo la trae inactiva',
    j ->> 'nombre' = 'ZTEVT Causal renombrada' and not (j ->> 'activa')::boolean and (select count(*) from redes.evento_causal_eventos where codigo = 'ztevt_causal_de_prueba') = 2
    and (select (x ->> 'activa')::boolean = false from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sd) -> 'causales') x where x ->> 'codigo' = 'ztevt_causal_de_prueba'), j::text);
  perform pg_temp.err('02.05 con la causal desactivada no se declara', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S3')), 'causa', 'ZTEVT observación de prueba', 'causal', 'ztevt_causal_de_prueba')), null, 'Esa causal no existe o está desactivada.');
  perform pg_temp.err('02.06 el operador no ajusta causales (403)', format('select public.geoportal_redes_evento_causal_fijar(%L, null, %L, true, %L)', op, 'ZTEVT del operador', 'ZTEVT no debería poder'), '42501');
  perform pg_temp.reg('02.07 el catálogo trae las 5 causales de David activas', (select count(*) from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sd) -> 'causales') x
     where x ->> 'codigo' in ('trabajo_programado', 'parametros_entrada', 'falla_planta', 'mantenimiento_planta', 'otra') and (x ->> 'activa')::boolean) = 5);

  -- ---------- 03. Tubos de salida → sectores, y el evento «por tubo» ----------
  j := public.geoportal_redes_tubo_sectores_fijar(sd, 'ztevt-t1', array[pg_temp.cod('S1'), pg_temp.cod('S2')], 'ZTEVT el tubo uno abastece los sectores uno y dos');
  perform public.geoportal_redes_tubo_sectores_fijar(adm, 'ZTEVT-T2', array[pg_temp.cod('S2'), pg_temp.cod('S3')], 'ZTEVT el tubo dos abastece los sectores dos y tres');
  f := (select x from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sd) -> 'tubos') x where x ->> 'codigo' = 'ZTEVT-T1');
  perform pg_temp.reg('03.01 fijar un tubo (el código en minúsculas vale): su lista, el hecho con motivo; el catálogo trae el tubo con nombre, planta y sectores',
    j ->> 'tubo' = 'ZTEVT-T1' and j ->> 'nombre' = 'ZTEVT Distrito Uno' and jsonb_array_length(j -> 'sectores') = 2 and (select count(*) from redes.tubo_sector_eventos where punto_id = v_t1) = 1
    and f ->> 'nombre' = 'ZTEVT Distrito Uno' and f ->> 'planta' = 'ZTEVT Planta' and (f ->> 'activo')::boolean and f -> 'sectores' = jsonb_build_array(pg_temp.cod('S1'), pg_temp.cod('S2'))
    and pg_temp.claves(f) = 'activo,codigo,nombre,planta,sectores', f::text);
  perform pg_temp.reg('03.02 el tubo sin sectores también sale en el catálogo, con la lista vacía',
    (select x -> 'sectores' from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sd) -> 'tubos') x where x ->> 'codigo' = 'ZTEVT-T3') = '[]');
  perform pg_temp.err('03.03 «Por tubo» con un tubo sin sectores: «Ese tubo no tiene sectores asignados (ZTEVT-T3).»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T1', 'ZTEVT-T3'), 'causa', 'ZTEVT observación de prueba', 'causal', 'trabajo_programado')), null, 'Ese tubo no tiene sectores asignados (ZTEVT-T3).');
  perform pg_temp.err('03.04 un tubo que no existe: «Ese tubo de salida no existe o está inactivo.»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T9'), 'causa', 'ZTEVT observación de prueba', 'causal', 'trabajo_programado')), null, 'Ese tubo de salida no existe o está inactivo.');
  perform pg_temp.err('03.05 un punto de muestreo no es un tubo (al declarar)', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-M1'), 'causa', 'ZTEVT observación de prueba', 'causal', 'trabajo_programado')), null, 'Ese tubo de salida no existe o está inactivo.');
  perform pg_temp.err('03.06 ni al fijar sus sectores', format('select public.geoportal_redes_tubo_sectores_fijar(%L, %L, %L, %L)', sd, 'ZTEVT-M1', array[pg_temp.cod('S1')], 'ZTEVT un punto de muestreo no es un tubo'), null, 'Ese tubo de salida no existe o está inactivo.');
  perform pg_temp.err('03.07 ni escribiendo directo en la tabla (lo cuida el disparador)', format('insert into redes.tubo_sectores (punto_id, sector_id) values (%s, %s)', v_m1, pg_temp.id('S1')), '23514', 'no es un tubo de salida');
  perform pg_temp.err('03.08 el operador no fija tubos (403)', format('select public.geoportal_redes_tubo_sectores_fijar(%L, %L, %L, %L)', op, 'ZTEVT-T1', array[pg_temp.cod('S1')], 'ZTEVT no debería poder'), '42501');
  j := public.geoportal_redes_evento_vista_previa(sd, jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T1', 'ZTEVT-T2')));
  j2 := public.geoportal_redes_evento_vista_previa(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1'), pg_temp.cod('S2'), pg_temp.cod('S3'))));
  perform pg_temp.reg('03.09 la vista previa por los dos tubos = la de sus 3 sectores (zona, contratos, sensibles y reportes); sin guardar nada',
    j ->> 'alcance' = 'sectores' and j -> 'zona_geojson' = j2 -> 'zona_geojson' and j -> 'contratos' = j2 -> 'contratos' and j -> 'sensibles' = j2 -> 'sensibles' and j -> 'reportes' = j2 -> 'reportes'
    and not exists (select 1 from redes.evento_tubos t where t.punto_id in (v_t1, v_t2)), j::text);
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T2', 'ztevt-t1'), 'causa', libre, 'causal', 'trabajo_programado', 'desde', v_desde));
  e_tubo := j ->> 'codigo';
  perform pg_temp.reg('03.10 declarado por dos tubos: queda POR SECTORES con la unión (3 sectores), guarda los dos tubos; zona «lo que sale por los tubos …»; origen Trabajo',
    j ->> 'alcance' = 'sectores' and jsonb_array_length(j -> 'sectores') = 3 and j -> 'tubos' = '[{"codigo": "ZTEVT-T1", "nombre": "ZTEVT Distrito Uno"}, {"codigo": "ZTEVT-T2", "nombre": "ZTEVT Distrito Dos"}]'
    and j ->> 'zona' = 'lo que sale por los tubos ZTEVT-T1, ZTEVT-T2' and j -> 'causal' ->> 'nombre' = 'Trabajo programado en redes' and j -> 'origen' ->> 'codigo' = 'trabajo'
    and (select count(*) from redes.evento_tubos t join redes.eventos_suspension e on e.id = t.evento_id where e.codigo = e_tubo) = 2, j::text);
  perform pg_temp.reg('03.11 el detalle (evento) trae los mismos origen, causal y tubos',
    public.geoportal_redes_evento(sd, e_tubo) -> 'tubos' = j -> 'tubos' and public.geoportal_redes_evento(sd, e_tubo) -> 'causal' = j -> 'causal'
    and public.geoportal_redes_evento(sd, e_tubo) -> 'origen' = j -> 'origen', (public.geoportal_redes_evento(sd, e_tubo))::text);

  -- ---------- 04. Lo que NO cambia: evento_contrato, la asociación automática, el bot ----------
  -- el contrato de prueba (tramo en el sector 1) frente al evento por tubo y frente al mismo evento declarado por sus sectores
  r_tubo := public.geoportal_redes_evento_contrato(adm, ct);
  perform public.geoportal_redes_evento_anular(sd, e_tubo, 'ZTEVT se anula para comparar con el mismo por sectores');
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1'), pg_temp.cod('S2'), pg_temp.cod('S3')), 'causa', libre,
                                                                     'causal', 'trabajo_programado', 'desde', v_desde));
  e_sec := j ->> 'codigo';
  r_sec := public.geoportal_redes_evento_contrato(adm, ct);
  perform pg_temp.reg('04.01 evento_contrato: el evento por tubo y el mismo por sectores dan la misma respuesta (salvo el código y el nombre de la zona): en_evento, tipo, zona «sectores», desde',
    r_tubo -> 'evento' ->> 'codigo' = e_tubo and r_sec -> 'evento' ->> 'codigo' = e_sec and (r_tubo ->> 'en_evento')::boolean and r_tubo -> 'evento' ->> 'zona' = 'sectores'
    and pg_temp.contrato_sin_codigo(r_tubo) = pg_temp.contrato_sin_codigo(r_sec), r_tubo::text || ' / ' || r_sec::text);
  perform public.geoportal_redes_evento_anular(sd, e_sec, 'ZTEVT se anula para volver al evento por tubo');
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T1'), 'causa', 'ZTEVT por el tubo uno', 'causal', 'trabajo_programado'));
  e_tubo := j ->> 'codigo';
  j2 := redes.f_reporte_externo_recibir_evento(jsonb_build_object('radicado', 'ZTEVT-B1', 'canal', 'telegram', 'tipo', 'sin_agua', 'lat', pg_temp.lat(100), 'lon', pg_temp.lon(150), 'descripcion', libre));
  perform pg_temp.reg('04.02 un reporte del bot dentro de la zona del tubo se asocia solo al evento por tubo y el bot responde como siempre',
    j2 ->> 'evento' = e_tubo and j2 ->> 'mensaje' like 'Ya sabemos del corte en tu sector.%', j2::text);
  perform pg_temp.reg('04.03 las funciones que no se tocan siguen con su md5 (evento_contrato, aviso, SCRR, disparadores, bot y demás rutas de eventos)',
    (select count(*) from (values ('geoportal_redes_evento_anular(text,text,text)', '8947de32c9f76c9bfc937a31e8bf2c39'), ('geoportal_redes_evento_asociar(text,text,text,text,text)', 'd97df5946041079714a86de12e1d1902'), ('geoportal_redes_evento_cerrar(text,text,text,text)', '1ae6ea7e5c0c5f71b5d41f752775f343'), ('geoportal_redes_evento_contrato(text,text)', 'f82b45906c62feca8b431020284e8bbf'), ('geoportal_redes_evento_desasociar(text,text,text,text,text)', 'cf6f1f7a378e8ab653be26aa9a78a4ee'), ('geoportal_redes_evento_regreso(text,text,text,text)', 'daa542d7d0b0f8cbb09c4f4429fbfd6a'), ('geoportal_redes_evento_tipo_fijar(text,text,text,boolean,text,text,text)', '72a0f1537529089418bd981a30f2fdca'), ('geoportal_redes_evento_vista_previa(text,jsonb)', 'cb22112ec60088390648e3394f1376d7'), ('geoportal_redes_evento(text,text)', 'e1c60d1fdc53332d64db9360ed164461'), ('geoportal_redes_eventos_vigentes(text)', '30d3b3306038af969a1e7e1b75e6f5ef'), ('geoportal_redes_eventos(text,text,integer)', '5b6e1f23c3985e69cfe4908dc3752b8a'), ('geoportal_redes_reporte_iniciar(text,text,jsonb,text,boolean,text)', '05ee00808781f3af88db3d3a57c68f22'), ('geoportal_redes_reporte_pagina(text,bigint,text,integer)', '5e55735ae8f7ad024627f1393aedefdd'), ('geoportal_redes_reporte_sectores(text)', 'b4c7e051d0f41881fc24550a7297f538'), ('redes.f_evento_abierto(text,text,text)', '59df33f21167b73cbc9a5049b505859e'), ('redes.f_evento_autorizar(text,text)', '1c1dc3406cf363dbe6c7a6de06e12954'), ('redes.f_evento_candidatos(geometry,boolean,timestamp with time zone,uuid)', 'dc09e88af2c5c2daa62f2c53fa8ee842'), ('redes.f_evento_contratos(geometry,boolean,boolean)', '8dafa57412c9b41aca0a0e3652f3bf2a'), ('redes.f_evento_franja(text,timestamp with time zone,text,timestamp with time zone)', 'fb9de8c4ada4a35de44889aea9f17b62'), ('redes.f_evento_marcar(bigint[],text,text,text)', 'f067be6b5b0344e0d9c044f8ade679de'), ('redes.f_evento_reportes(bigint)', 'e9d6c5b2d72868e188e2bc5eeda47ddd'), ('redes.f_evento_tg_bot()', '857c47e052a5204c1c437c07d4cd77d1'), ('redes.f_evento_tg_campo()', '8a755c25a340e331b233ccadf99bb099'), ('redes.f_evento_tg_dano()', '430048038207e8bcfeedbf537e75faf8'), ('redes.f_evento_tg_l116()', 'a3959ab3a96e37539fd6507cddc3e075'), ('redes.f_eventos_abiertos()', '2d265a26461ea19a01e9a81bb927b120'), ('redes.f_eventos_para_avisos(timestamp with time zone)', '755cc3b1a15fbd9c82fd34991a97216a'), ('redes.f_reporte_externo_recibir_evento(jsonb)', '92be46589b80d60ce38139e3fe44550d'), ('redes.f_sector_de(geometry)', '455378c9b8cf43343ff821a2896eae37'), ('redes.f_sin_agua_para_avisos(timestamp with time zone,numeric)', '6a370c60ddcc409b06104f599110915a'), ('tecnica.f_avisos(boolean,boolean,timestamp with time zone)', 'aaa81ee57ec79080b9e76213ecea006c')) c(fn, m) where md5(pg_get_functiondef(to_regprocedure(c.fn))) = c.m) = 31);
  -- re-fijar el tubo 1 solo con el sector 1: el 2 queda inactivo (no se borra) y hay un segundo hecho
  perform public.geoportal_redes_tubo_sectores_fijar(sd, 'ZTEVT-T1', array[pg_temp.cod('S1')], 'ZTEVT el tubo uno ya no abastece el sector dos');
  perform pg_temp.reg('04.04 cambiar los sectores de un tubo desactiva el que sale (no se borra) y deja su hecho; el evento ya declarado no cambia',
    (select activo from redes.tubo_sectores where punto_id = v_t1 and sector_id = pg_temp.id('S2')) = false and (select count(*) from redes.tubo_sector_eventos where punto_id = v_t1) = 2
    and (select cardinality(sectores) from redes.eventos_suspension where codigo = e_tubo) = 2);

  -- ---------- 05. Planta: el sistema es único ----------
  perform pg_temp.err('05.01 los sectores ya no se asignan por planta (400)', format('select public.geoportal_redes_planta_sectores_fijar(%L, %L, %L, %L)', sd, 'zt_evt_pl', array[pg_temp.cod('S1')], 'ZTEVT ya no se puede por planta'),
    null, 'Los sectores ya no se asignan por planta: el sistema es único. Asígnelos a los tubos de salida.');
  perform pg_temp.err('05.02 y el operador sigue recibiendo 403', format('select public.geoportal_redes_planta_sectores_fijar(%L, %L, %L, %L)', op, 'zt_evt_pl', array[pg_temp.cod('S1')], 'ZTEVT ya no se puede por planta'), '42501');
  perform pg_temp.reg('05.03 la migración dejó inactivos todos los sectores por planta, con UN hecho por cada planta que tenía (nada se borró)',
    not exists (select 1 from redes.planta_sectores where activo)
    and not exists (select ps.planta_id from redes.planta_sectores ps group by ps.planta_id
                    having (select count(*) from redes.planta_sector_eventos e where e.planta_id = ps.planta_id and e.motivo = 'el sistema es único; los sectores pasan a los tubos de salida') <> 1));
  perform pg_temp.reg('05.04 el catálogo deja vacíos los sectores de cada planta', not exists (select 1 from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sd) -> 'plantas') x where x -> 'sectores' <> '[]'));
  -- un evento de planta nuevo cubre toda la ciudad (si en la base ya hay uno de toda la ciudad abierto, la regla «uno por zona» lo impide: se comprueba eso)
  v_hay_todo := exists (select 1 from redes.f_eventos_abiertos() e where e.todo);
  if v_hay_todo then
    perform pg_temp.err('05.05 (hay un evento de toda la ciudad abierto en la base) uno de planta choca con él: «Ya hay un evento abierto para esa misma zona»', format('select public.geoportal_redes_evento_declarar(%L, %L)', adm,
      jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'zt_evt_pl', 'causa', 'ZTEVT falla de la planta', 'causal', 'falla_planta')), '55000', 'misma zona');
  else
    j := public.geoportal_redes_evento_declarar(adm, jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'zt_evt_pl', 'causa', 'ZTEVT falla de la planta', 'causal', 'falla_planta'));
    e_pl := j ->> 'codigo';
    perform pg_temp.reg('05.05 un evento de planta nuevo cubre TODA LA CIUDAD y guarda la planta: zona «Toda la ciudad (planta ZTEVT Planta)», total «planta», sin zona dibujada',
      j ->> 'alcance' = 'total' and j ->> 'total' = 'planta' and j ->> 'planta' = 'ZTEVT Planta' and j ->> 'zona' = 'Toda la ciudad (planta ZTEVT Planta)' and j -> 'zona_geojson' = 'null'
      and (select todo and geom is null and planta_id = v_pl from redes.eventos_suspension where codigo = e_pl), j::text);
    perform pg_temp.reg('05.06 con el evento de planta, el contrato de prueba también está dentro (toda la ciudad)',
      exists (select 1 from redes.f_eventos_del_contrato(ct) x join redes.eventos_suspension e on e.id = x.evento_id where e.codigo = e_pl));
  end if;
  perform pg_temp.err('05.07 el supervisor de distribución no declara un evento de planta (es total: 403)', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'zt_evt_pl', 'causa', 'ZTEVT falla de la planta', 'causal', 'falla_planta')), '42501');

  -- ---------- 06. Las descargas de eventos (solo filas de prueba) ----------
  j := pg_temp.bajar('redes', sd, 'eventos', per);
  f := pg_temp.fila(j -> 'filas', 'evento', e_tubo);
  perform pg_temp.reg('06.01 Distribución · Eventos: el de tubo dice «Por tubo», su tubo, origen Trabajo y la causal; las columnas = claves de la fila',
    f ->> 'alcance' = 'Por tubo' and f ->> 'tubos' = 'ZTEVT-T1' and f ->> 'origen' = 'Trabajo' and f ->> 'causal' = 'Trabajo programado en redes'
    and pg_temp.claves(f) = (select string_agg(x ->> 'clave', ',' order by x ->> 'clave') from jsonb_array_elements(j -> 'ini' -> 'columnas') x), f::text);
  perform pg_temp.reg('06.02 el evento de antes sale «No registrado (anterior al cambio)» y sin causal; el de antes con intervención, «Intervención»; el de «Otra», su causal',
    pg_temp.fila(j -> 'filas', 'evento', 'EVS-991001') ->> 'origen' = 'No registrado (anterior al cambio)' and pg_temp.fila(j -> 'filas', 'evento', 'EVS-991001') -> 'causal' = 'null'
    and pg_temp.fila(j -> 'filas', 'evento', 'EVS-991002') ->> 'origen' = 'Intervención' and pg_temp.fila(j -> 'filas', 'evento', e_otra) ->> 'causal' = 'Otra');
  perform pg_temp.reg('06.03 la observación (texto libre) no sale en la descarga; el Léame lo dice', position('Pedro' in (j)::text) = 0 and (j -> 'ini' -> 'leame' -> 'que_no_trae')::text like '%observación escrita%');
  if not v_hay_todo then
    j := pg_temp.bajar('tec', sp, 'eventos_planta', per || '{"planta": "zt_evt_pl"}');
    f := pg_temp.fila(j -> 'filas', 'evento', e_pl);
    perform pg_temp.reg('06.04 PTAP · Eventos de planta: el de la planta de prueba, origen Trabajo, causal «Falla en la planta»; el Léame dice que cubre toda la ciudad',
      jsonb_array_length(j -> 'filas') = 1 and f ->> 'origen' = 'Trabajo' and f ->> 'causal' = 'Falla en la planta' and (j -> 'ini' -> 'leame' -> 'que_trae')::text like '%toda la ciudad%'
      and pg_temp.claves(f) = (select string_agg(x ->> 'clave', ',' order by x ->> 'clave') from jsonb_array_elements(j -> 'ini' -> 'columnas') x), f::text);
  else
    perform pg_temp.reg('06.04 PTAP · Eventos de planta: las columnas origen y causal están (no se declaró el de planta: hay uno de toda la ciudad abierto)',
      (select count(*) from jsonb_array_elements(tecnica.f_rep_columnas('eventos_planta', '{}')) x where x ->> 'clave' in ('origen', 'causal')) = 2);
  end if;

  -- ---------- 07. Seguridad del esquema ----------
  perform pg_temp.reg('07.01 las 2 RPC nuevas: security definer, search_path fijo, solo service_role',
    (select count(*) from pg_proc p where p.oid in ('public.geoportal_redes_evento_causal_fijar(text,text,text,boolean,text)'::regprocedure, 'public.geoportal_redes_tubo_sectores_fijar(text,text,text[],text)'::regprocedure)
       and p.prosecdef and p.proconfig is not null and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
       and not has_function_privilege('authenticated', p.oid, 'execute') and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 2);
  perform pg_temp.reg('07.02 las internas nuevas: nadie más que su dueño',
    not exists (select 1 from pg_proc p where p.oid in ('redes.f_evento_origen(bigint)'::regprocedure, 'redes.f_tubo_zona(text[])'::regprocedure, 'redes.f_tubo_es_distribucion()'::regprocedure)
                  and exists (select 1 from aclexplode(p.proacl) x where x.grantee <> p.proowner)));
  perform pg_temp.reg('07.03 las 6 tablas nuevas: RLS y sin permisos para la API',
    (select count(*) from pg_class c where c.oid in ('redes.evento_causales'::regclass, 'redes.evento_causal_eventos'::regclass, 'redes.evento_causal'::regclass, 'redes.tubo_sectores'::regclass,
       'redes.tubo_sector_eventos'::regclass, 'redes.evento_tubos'::regclass) and c.relrowsecurity and not has_table_privilege('anon', c.oid, 'select')
       and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')) = 6);
  perform pg_temp.err('07.04 de qué tubos salió un evento es de solo inserción', format('delete from redes.evento_tubos where punto_id = %s', v_t1));
  perform pg_temp.err('07.05 la causal de un evento tampoco se cambia', format('update redes.evento_causal set causal = %L where causal = %L', 'otra', 'trabajo_programado'));
  perform pg_temp.reg('07.06 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  -- ---------- 08. Tiempos con el volumen real ----------
  v_t0 := clock_timestamp(); j := public.geoportal_redes_evento_catalogo(sd); v_ms1 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_t0 := clock_timestamp(); j2 := public.geoportal_redes_evento_vista_previa(sd, jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T2'))); v_ms2 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_info := format('TIEMPOS: catálogo de eventos %s ms (%s tubos, %s sectores) · vista previa por tubo %s ms (tope de la API: 30 s por llamada)',
                   round(v_ms1), jsonb_array_length(j -> 'tubos'), jsonb_array_length(j -> 'sectores'), round(v_ms2));
  perform pg_temp.reg('08.01 TIEMPOS: el catálogo y la vista previa por tubo, cada uno en menos de 5 s', v_ms1 < 5000 and v_ms2 < 5000, v_info);

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · eventos (origen y tubos) (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
