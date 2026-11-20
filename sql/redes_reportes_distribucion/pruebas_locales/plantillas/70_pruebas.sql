-- =====================================================================
-- TÉCNICA · FASE 1 · DESCARGAS DE DISTRIBUCIÓN · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- Todo es SIMULADO y se deshace: sus personas (prueba.rep.*), una red de prueba ZTREP en un rincón de la caja (2 sectores, 2 válvulas, 1 tramo), puntos LEV,
-- maniobras de válvula, eventos declarados con la RPC publicada del Corte 15, reportes de la 116 y del bot, y usuarios sensibles con contratos de prueba.
-- Los textos libres de prueba llevan un nombre y un teléfono inventados («ZTREP Pedro Prueba 3009990000») para comprobar que NO salen.
-- Mide con el volumen real: «Activos de la red» completo (iniciar y la primera página de 5.000).
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · descargas de Distribución … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.rep.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZTREP ' || p_nombre, p_clase, case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end,
          case when p_prefijo = 'RED' then 110 end, 'en_operacion', p_atributos, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZTREP activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  insert into _zt values (p_nombre, v_id, v_cod);
  return v_cod;
end $$;
create function pg_temp.id(p_nombre text) returns bigint language sql as $$ select activo_id from _zt where nombre = p_nombre $$;
create function pg_temp.cod(p_nombre text) returns text language sql as $$ select codigo from _zt where nombre = p_nombre $$;
create function pg_temp.claves(j jsonb) returns text language sql as $$ select string_agg(k, ',' order by k) from jsonb_object_keys(j) k $$;
create function pg_temp.cols(p_rep text) returns text language sql as $$ select string_agg(x ->> 'clave', ',' order by x ->> 'clave') from jsonb_array_elements(redes.f_rep_columnas(p_rep)) x $$;
-- todas las filas de una descarga, página por página (con p_lim por página); devuelve el arreglo completo
create function pg_temp.todas(p_quien text, p_id bigint, p_lim integer default 5000) returns jsonb language plpgsql as $$
declare v_c text; v_r jsonb; v_todas jsonb := '[]'; i integer := 0;
begin
  loop
    v_r := public.geoportal_redes_reporte_pagina(p_quien, p_id, v_c, p_lim);
    v_todas := v_todas || (v_r -> 'filas'); v_c := v_r ->> 'cursor'; i := i + 1;
    exit when v_c is null or i > 2000;
  end loop;
  return v_todas;
end $$;
-- iniciar y traer todo; devuelve {ini, filas}
create function pg_temp.bajar(p_quien text, p_rep text, p_f jsonb, p_incl boolean default false, p_lim integer default 5000) returns jsonb language plpgsql as $$
declare v_i jsonb;
begin
  v_i := public.geoportal_redes_reporte_iniciar(p_quien, p_rep, p_f, 'xlsx', p_incl, '10.0.0.1');
  return jsonb_build_object('ini', v_i, 'filas', pg_temp.todas(p_quien, (v_i ->> 'descarga_id')::bigint, p_lim));
end $$;
create function pg_temp.hay(p_filas jsonb, p_clave text, p_valor text) returns boolean language sql as $$
  select exists (select 1 from jsonb_array_elements(p_filas) f where f ->> p_clave = p_valor) $$;

do $prueba$
declare
  adm text := 'prueba.rep.adm@emdupar.gov.co'; sd text := 'prueba.rep.sd@emdupar.gov.co'; sd2 text := 'prueba.rep.sd2@emdupar.gov.co'; sp text := 'prueba.rep.sp@emdupar.gov.co';
  op text := 'prueba.rep.op@emdupar.gov.co'; ex text := 'prueba.rep.explorar@emdupar.gov.co';
  libre text := 'ZTREP Pedro Prueba 3009990000';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; per jsonb; j jsonb; j2 jsonb; f jsonb; v_id bigint; v_id2 bigint; v_n integer; v_m integer; v_txt text;
  v_carga bigint; v_lev1 uuid := gen_random_uuid(); v_lev2 uuid := gen_random_uuid(); v_lev3 uuid := gen_random_uuid(); v_c1 bigint; v_c2 bigint; v_rep uuid; v_rep2 uuid;
  e1 text; e2 text; v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_info text; v_total integer; v_bien integer; v_fallas text; v_aud integer;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTREP Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZTREP Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd2, 'ZTREP Otro supervisor', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZTREP Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZTREP Operador', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_explorar, horario, dias) values (ex, 'ZTREP Explorar', 'consulta', true, 'sin_restriccion', 'todos');
  per := jsonb_build_object('desde', (hoy - 30)::text, 'hasta', hoy::text);

  -- ---------- la red de prueba: sector 97 (con un subsector) y sector 98, una válvula en cada uno y un tramo ----------
  perform pg_temp.activo('S97', 'SEC', pg_temp.caja(0, -50, 400, 250), 'sector', '{"modelo": {"sector": 97}}');
  perform pg_temp.activo('S97A', 'SEC', pg_temp.caja(0, -50, 200, 250), 'subsector', '{"modelo": {"sector": 97, "subsector": "97A"}}');
  perform pg_temp.activo('S98', 'SEC', pg_temp.caja(500, -50, 900, 250), 'sector', '{"modelo": {"sector": 98}}');
  perform pg_temp.activo('V1', 'VAL', pg_temp.pt(100, 100), 'compuerta');
  perform pg_temp.activo('V2', 'VAL', pg_temp.pt(700, 100), 'compuerta');
  perform pg_temp.activo('T1', 'RED', ST_MakeLine(pg_temp.pt(50, 0), pg_temp.pt(350, 0)));

  -- ---------- 01. Quién entra ----------
  perform pg_temp.reg('01.01 el supervisor de distribución inicia una descarga (Activos de la red, tipo VAL)',
    (public.geoportal_redes_reporte_iniciar(sd, 'activos', '{"tipo": "VAL"}', 'xlsx', false, null) ->> 'total')::integer = (select count(*) from redes.activo_vigente_mat where prefijo = 'VAL' and not retirado and not oculto));
  perform pg_temp.reg('01.02 el administrador también', (public.geoportal_redes_reporte_iniciar(adm, 'activos', '{"tipo": "SEC"}', 'csv', false, null) ->> 'total')::integer >= 3);
  perform pg_temp.err('01.03 el supervisor de planta no (403)', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L, %L)', sp, 'activos', '{}', 'xlsx'), '42501');
  perform pg_temp.err('01.04 el operador no (403)', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L, %L)', op, 'activos', '{}', 'xlsx'), '42501');
  perform pg_temp.err('01.05 alguien sin Técnica no (403)', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L, %L)', ex, 'activos', '{}', 'xlsx'), '42501');
  perform pg_temp.err('01.06 ni página ni cierre para el supervisor de planta (403)', format('select public.geoportal_redes_reporte_pagina(%L, 1)', sp), '42501');

  -- ---------- 02. Lo que se rechaza ----------
  perform pg_temp.err('02.01 un reporte que no existe', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'danos', per), null, 'Ese reporte no existe');
  perform pg_temp.err('02.02 un formato que no es Excel ni CSV', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L, %L)', sd, 'eventos', per, 'pdf'), null, 'Excel o CSV');
  perform pg_temp.err('02.03 un filtro que no aplica al reporte', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'eventos', per || '{"tipo": "VAL"}'), null, 'no aplica');
  perform pg_temp.err('02.04 sin periodo en un reporte con periodo', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'l116', '{}'), null, 'Elija el periodo');
  perform pg_temp.err('02.05 más de un año', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'l116', jsonb_build_object('desde', (hoy - 366)::text, 'hasta', hoy::text)), null, 'hasta de un año');
  perform pg_temp.err('02.06 desde después de hasta', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'l116', jsonb_build_object('desde', hoy::text, 'hasta', (hoy - 1)::text)), null, 'posterior');
  perform pg_temp.err('02.07 un sector que no está en la capa', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'l116', per || '{"sector": "99"}'), null, 'capa de sectores');
  perform pg_temp.err('02.08 un tipo de activo que no existe', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'activos', '{"tipo": "XYZ"}'), null, 'tipo de activo');
  perform pg_temp.err('02.09 sin datos con esos filtros: 404', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'valvulas', jsonb_build_object('desde', '2001-01-01', 'hasta', '2001-01-31')), 'P0002', 'No hay datos');
  perform pg_temp.reg('02.10 un año exacto (366 días con los dos extremos) sí se acepta', (redes.f_rep_filtros('l116', jsonb_build_object('desde', (hoy - 365)::text, 'hasta', hoy::text)) ->> 'desde') = (hoy - 365)::text);

  -- ---------- 03. Encontrar o reportar activo ----------
  insert into redes.levantar_puntos (id, codigo, servicio, tipo, observacion, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en) values
    (v_lev1, 'LEV-9' || lpad('1', 5, '0'), 'acueducto', 'valvula', libre, pg_temp.lat(100), pg_temp.lon(150), pg_temp.pt(150, 100), 4, false, 'tecnica', op, clock_timestamp() - interval '2 days'),
    (v_lev2, 'LEV-9' || lpad('2', 5, '0'), 'alcantarillado', 'pozo', null, pg_temp.lat(100), pg_temp.lon(700), pg_temp.pt(700, 100), 30, true, 'comercial', op, clock_timestamp() - interval '1 day'),
    (v_lev3, 'LEV-9' || lpad('3', 5, '0'), 'acueducto', 'otro', libre, pg_temp.lat(100), pg_temp.lon(160), pg_temp.pt(160, 100), 5, false, 'tecnica', op, clock_timestamp() - interval '3 hours');
  insert into redes.levantar_eventos (punto_id, tipo, activo_id, autor) values (v_lev1, 'levantado', pg_temp.id('V1'), sd);
  insert into redes.levantar_eventos (punto_id, tipo, motivo, autor) values (v_lev3, 'descartado', libre, sd);
  j := pg_temp.bajar(sd, 'levantamientos', per);
  perform pg_temp.reg('03.01 los LEV del periodo sin los descartados; el levantado trae el código del activo; columnas = claves de cada fila',
    pg_temp.hay(j -> 'filas', 'codigo', 'LEV-900001') and pg_temp.hay(j -> 'filas', 'codigo', 'LEV-900002') and not pg_temp.hay(j -> 'filas', 'codigo', 'LEV-900003')
    and pg_temp.hay(j -> 'filas', 'activo', pg_temp.cod('V1')) and pg_temp.hay(j -> 'filas', 'estado', 'Levantado')
    and pg_temp.claves(j -> 'filas' -> 0) = pg_temp.cols('levantamientos') and pg_temp.claves(j -> 'filas' -> 0) = (select string_agg(x ->> 'clave', ',' order by x ->> 'clave') from jsonb_array_elements(j -> 'ini' -> 'columnas') x),
    left((j -> 'filas')::text, 300));
  j := pg_temp.bajar(sd, 'levantamientos', per || '{"sector": "97"}', true);
  perform pg_temp.reg('03.02 por sector 97 y con «Incluir ocultos»: los dos del sector 97 (el descartado también), con su número de sector; el del 98 no',
    jsonb_array_length(j -> 'filas') = 2 and pg_temp.hay(j -> 'filas', 'codigo', 'LEV-900003') and pg_temp.hay(j -> 'filas', 'estado', 'Descartado')
    and not pg_temp.hay(j -> 'filas', 'codigo', 'LEV-900002') and (select bool_and((x ->> 'sector')::integer = 97) from jsonb_array_elements(j -> 'filas') x), (j -> 'filas')::text);
  perform pg_temp.reg('03.03 la observación y el motivo (texto libre) no salen', position('Pedro' in (j)::text) = 0);

  -- ---------- 04. Válvulas cerradas ----------
  insert into redes.valvula_maniobras (valvula_id, tipo, motivo, regreso_estimado, hecho_en, autor) values (pg_temp.id('V1'), 'cerrar', libre, clock_timestamp() - interval '1 day', clock_timestamp() - interval '2 days', sd) returning id into v_c1;
  insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, regreso_estimado, hecho_en, autor) values (pg_temp.id('V1'), 'regreso', v_c1, clock_timestamp() - interval '20 hours', clock_timestamp() - interval '30 hours', sd);
  insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, hecho_en, autor) values (pg_temp.id('V1'), 'abrir', v_c1, clock_timestamp() - interval '2 days' + interval '30 hours', sd2);
  insert into redes.valvula_maniobras (valvula_id, tipo, motivo, hecho_en, autor) values (pg_temp.id('V2'), 'cerrar', libre, clock_timestamp() - interval '5 hours', sd) returning id into v_c2;
  j := pg_temp.bajar(sd, 'valvulas', per);
  select x into f from jsonb_array_elements(j -> 'filas') x where x ->> 'valvula' = pg_temp.cod('V1');
  perform pg_temp.reg('04.01 un cierre con su cambio de regreso y su apertura: Abierta, 30 h, 1 cambio, quién cerró y quién abrió',
    f ->> 'estado' = 'Abierta' and (f ->> 'duracion_h')::numeric = 30.0 and (f ->> 'cambios_regreso')::integer = 1 and f ->> 'cerro' = sd and f ->> 'abrio' = sd2 and (f ->> 'sector')::integer = 97, f::text);
  select x into f from jsonb_array_elements(j -> 'filas') x where x ->> 'valvula' = pg_temp.cod('V2');
  perform pg_temp.reg('04.02 la que sigue cerrada: Cerrada, sin apertura ni duración; sector 98', f ->> 'estado' = 'Cerrada' and f -> 'abierta' = 'null' and f -> 'duracion_h' = 'null' and (f ->> 'sector')::integer = 98, f::text);
  perform pg_temp.reg('04.03 por sector 98 solo sale la V2, y el motivo no sale',
    jsonb_array_length((pg_temp.bajar(sd, 'valvulas', per || '{"sector": "98"}')) -> 'filas') = 1 and position('Pedro' in (j)::text) = 0);

  -- ---------- 05. Eventos de suspensión ----------
  e1 := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S97')), 'causa', libre,
                                                                      'regreso', to_char(clock_timestamp() + interval '4 hours', 'YYYY-MM-DD"T"HH24:MI:SSOF'))) ->> 'codigo';
  e2 := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S98')), 'causa', 'ZTREP evento que se anula')) ->> 'codigo';
  perform public.geoportal_redes_evento_anular(sd, e2, 'ZTREP se declaró por error');
  j := pg_temp.bajar(sd, 'eventos', per);
  select x into f from jsonb_array_elements(j -> 'filas') x where x ->> 'evento' = e1;
  perform pg_temp.reg('05.01 el evento abierto sale con su zona, alcance «Sectores», regreso estimado y conteos; el anulado no sale; la causa tampoco',
    f is not null and f ->> 'alcance' = 'Sectores' and f ->> 'estado' = 'Abierto' and f ->> 'regreso_estimado' is not null and f ->> 'zona' like '%ZTREP S97%'
    and (f ->> 'contratos') is not null and (f ->> 'reportes')::integer = 0 and not pg_temp.hay(j -> 'filas', 'evento', e2) and position('Pedro' in (j)::text) = 0
    and pg_temp.claves(f) = pg_temp.cols('eventos'), f::text);
  j := pg_temp.bajar(sd, 'eventos', per || '{"sector": "98"}', true);
  perform pg_temp.reg('05.02 por sector 98 y con «Incluir ocultos»: el anulado (con su fin y quién lo anuló), y no el del 97',
    pg_temp.hay(j -> 'filas', 'evento', e2) and pg_temp.hay(j -> 'filas', 'estado', 'Anulado') and pg_temp.hay(j -> 'filas', 'cerro', sd) and not pg_temp.hay(j -> 'filas', 'evento', e1), (j -> 'filas')::text);

  -- ---------- 06. Línea 116 ----------
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
  values ('acueducto', md5('ztrep-a') || md5('ztrep-b'), 'csv', 4326, 'reporte', 3, 'ZTREP carga de prueba de la 116', adm) returning id into v_carga;
  insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, comuna, contrato, carga_id) values
    (990000001, clock_timestamp() - interval '2 days', 'Acueducto', 'Sin servicio de agua', 'Comuna 9', '999999990001', v_carga),
    (990000002, clock_timestamp() - interval '1 day', 'Acueducto', 'Fuga', null, null, v_carga),
    (990000003, clock_timestamp() - interval '3 hours', 'Alcantarillado', 'Rebose', null, '999999990003', v_carga);
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, contrato, estado, estado_desde, metodo, geom, sector, subsector, oculto)
  select r.id, r.reporte, r.fecha_registro, (r.fecha_registro at time zone 'America/Bogota')::date, r.servicio, r.causal, r.contrato,
         case when r.reporte = 990000002 then 'atendido' else 'registrado' end, r.fecha_registro, case when r.contrato is null then 'sin_ubicar' else 'contrato' end,
         case when r.contrato is not null then pg_temp.pt(120, 80) end, case when r.contrato is not null then 97 end, case when r.contrato is not null then '97A' end, r.reporte = 990000003
    from redes.l116_reportes r where r.carga_id = v_carga;
  j := pg_temp.bajar(sd, 'l116', per);
  perform pg_temp.reg('06.01 los de la 116 sin el oculto, con contrato, comuna, «Por contrato» o «Sin ubicar» y el estado vigente',
    pg_temp.hay(j -> 'filas', 'reporte', '990000001') and pg_temp.hay(j -> 'filas', 'reporte', '990000002') and not pg_temp.hay(j -> 'filas', 'reporte', '990000003')
    and pg_temp.hay(j -> 'filas', 'contrato', '999999990001') and pg_temp.hay(j -> 'filas', 'comuna', 'Comuna 9') and pg_temp.hay(j -> 'filas', 'ubicacion', 'Sin ubicar')
    and pg_temp.hay(j -> 'filas', 'estado', 'Atendido'), (j -> 'filas')::text);
  j := pg_temp.bajar(sd, 'l116', per || '{"sector": "97"}', true);
  perform pg_temp.reg('06.02 por sector 97 y con «Incluir ocultos»: los dos ubicados (el oculto marcado «sí»), no el sin ubicar',
    jsonb_array_length(j -> 'filas') = 2 and pg_temp.hay(j -> 'filas', 'oculto', 'true') and not pg_temp.hay(j -> 'filas', 'reporte', '990000002'), (j -> 'filas')::text);

  -- ---------- 07. Reportes del bot ----------
  insert into redes.reportes_externos (radicado, canal, tipo_bot, lat, lon, direccion, descripcion, recibido_en) values
    ('ZTREP-B1', 'telegram', 'Fuga en la calle', pg_temp.lat(100), pg_temp.lon(300), 'Calle de ' || libre, 'Me llamo ' || libre, clock_timestamp() - interval '2 days') returning id into v_rep;
  insert into redes.reportes_externos (radicado, canal, tipo_bot, lat, lon, direccion, descripcion, recibido_en) values
    ('ZTREP-B2', 'whatsapp', 'Sin agua', pg_temp.lat(100), pg_temp.lon(800), null, libre, clock_timestamp() - interval '1 day') returning id into v_rep2;
  insert into redes.reporte_externo_eventos (reporte_id, tipo, motivo, autor) values (v_rep2, 'descartado', 'ZTREP repetido de otro reporte', sd);
  j := pg_temp.bajar(sd, 'bot', per);
  perform pg_temp.reg('07.01 los del bot sin el descartado, con radicado, canal, tipo, estado y sector; sin la descripción ni la dirección',
    pg_temp.hay(j -> 'filas', 'radicado', 'ZTREP-B1') and not pg_temp.hay(j -> 'filas', 'radicado', 'ZTREP-B2') and pg_temp.hay(j -> 'filas', 'estado', 'Recibido')
    and position('Pedro' in (j)::text) = 0 and (select (x ->> 'sector')::integer from jsonb_array_elements(j -> 'filas') x where x ->> 'radicado' = 'ZTREP-B1') = 97, (j -> 'filas')::text);
  j := pg_temp.bajar(sd, 'bot', per || '{"sector": "98"}', true);
  perform pg_temp.reg('07.02 por sector 98 y con «Incluir ocultos»: el descartado', jsonb_array_length(j -> 'filas') = 1 and pg_temp.hay(j -> 'filas', 'estado', 'Descartado'), (j -> 'filas')::text);

  -- ---------- 08. Usuarios sensibles (inventario a hoy) ----------
  insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor) values ('999999990001', 'hospital', 'ZTREPHOSPITALPEDRO', 'nombre', adm),
    ('999999990002', 'colegio', null, 'manual', adm), ('999999990003', 'clinica', 'ZTREPCLINICAPEDRO', 'nombre', adm);
  insert into redes.usuario_sensible_eventos (contrato, accion, tipo, autor) values ('999999990001', 'confirmar', 'hospital', sd);
  insert into redes.usuario_sensible_eventos (contrato, accion, motivo, autor) values ('999999990003', 'descartar', 'ZTREP no es una clínica', sd);
  j := pg_temp.bajar(sd, 'sensibles', '{}');
  perform pg_temp.reg('08.01 sin periodo: los sensibles de hoy sin el descartado, con tipo, estado y origen; sin la palabra del nombre',
    pg_temp.hay(j -> 'filas', 'contrato', '999999990001') and pg_temp.hay(j -> 'filas', 'contrato', '999999990002') and not pg_temp.hay(j -> 'filas', 'contrato', '999999990003')
    and pg_temp.hay(j -> 'filas', 'estado', 'Confirmado') and pg_temp.hay(j -> 'filas', 'tipo', 'Hospital') and pg_temp.hay(j -> 'filas', 'origen', 'Por el nombre')
    and position('ZTREPHOSPITAL' in (j)::text) = 0 and position('Periodo' in (j -> 'ini' -> 'leame')::text) = 0 and position('Inventario al' in (j -> 'ini' -> 'leame')::text) > 0, left((j -> 'filas')::text, 300));
  j := pg_temp.bajar(sd, 'sensibles', '{"tipo": "clinica"}', true);
  perform pg_temp.reg('08.02 por tipo «clinica» y con «Incluir ocultos»: solo el descartado', jsonb_array_length(j -> 'filas') = 1 and pg_temp.hay(j -> 'filas', 'estado', 'Descartado'), (j -> 'filas')::text);

  -- ---------- 09. Activos de la red ----------
  j := pg_temp.bajar(sd, 'activos', '{"tipo": "SEC"}');
  select x into f from jsonb_array_elements(j -> 'filas') x where x ->> 'codigo' = pg_temp.cod('S97A');
  perform pg_temp.reg('09.01 por tipo SEC: los 3 sectores de prueba (y los reales), con tipo, estado, clase y un punto para ubicarlos',
    (select count(*) from jsonb_array_elements(j -> 'filas') x where x ->> 'codigo' in (pg_temp.cod('S97'), pg_temp.cod('S97A'), pg_temp.cod('S98'))) = 3
    and f ->> 'prefijo' = 'SEC' and f ->> 'estado' = 'En operación' and (f ->> 'lat') is not null and (f ->> 'sector')::integer = 97
    and jsonb_array_length(j -> 'filas') = (select count(*) from redes.activo_vigente_mat where prefijo = 'SEC' and not retirado and not oculto), f::text);
  j := pg_temp.bajar(sd, 'activos', '{"tipo": "RED", "sistema": "acueducto"}');
  select x into f from jsonb_array_elements(j -> 'filas') x where x ->> 'codigo' = pg_temp.cod('T1');
  perform pg_temp.reg('09.02 un tramo sale con su material, diámetro y longitud, y su punto queda sobre la línea',
    f ->> 'material' is not null and (f ->> 'diametro_mm')::numeric = 110 and (f ->> 'sector')::integer = 97
    and ST_DWithin(ST_SetSRID(ST_MakePoint((f ->> 'lon')::float8, (f ->> 'lat')::float8), 4326)::geography, ST_MakeLine(pg_temp.pt(50, 0), pg_temp.pt(350, 0))::geography, 1), f::text);

  -- ---------- 10. Paginación: de una en una, el mismo resultado que de una vez, sin repetir ni saltar ----------
  j := pg_temp.bajar(sd, 'valvulas', per, false, 5000); j2 := pg_temp.bajar(sd, 'valvulas', per, false, 1);
  perform pg_temp.reg('10.01 válvulas de una en una = de una vez (mismo orden y mismas filas)', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = (j -> 'ini' ->> 'total')::integer, jsonb_array_length(j2 -> 'filas')::text);
  j := pg_temp.bajar(sd, 'bot', per, true, 5000); j2 := pg_temp.bajar(sd, 'bot', per, true, 1);
  perform pg_temp.reg('10.02 bot (llave con la hora) de uno en uno = de una vez', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = (j -> 'ini' ->> 'total')::integer);
  j := pg_temp.bajar(sd, 'levantamientos', per, true, 5000); j2 := pg_temp.bajar(sd, 'levantamientos', per, true, 2);
  perform pg_temp.reg('10.03 levantamientos de dos en dos = de una vez', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = (j -> 'ini' ->> 'total')::integer);
  j := public.geoportal_redes_reporte_iniciar(sd, 'activos', '{"tipo": "SEC"}', 'xlsx', false, null);
  j2 := public.geoportal_redes_reporte_pagina(sd, (j ->> 'descarga_id')::bigint, null, (j ->> 'total')::integer);
  perform pg_temp.reg('10.04 una página exacta deja cursor; la siguiente viene vacía y sin cursor',
    j2 ->> 'cursor' is not null and (public.geoportal_redes_reporte_pagina(sd, (j ->> 'descarga_id')::bigint, j2 ->> 'cursor', 10) ->> 'devueltos')::integer = 0
    and public.geoportal_redes_reporte_pagina(sd, (j ->> 'descarga_id')::bigint, j2 ->> 'cursor', 10) -> 'cursor' = 'null');
  perform pg_temp.err('10.05 un cursor con caracteres raros se rechaza', format('select public.geoportal_redes_reporte_pagina(%L, %s, %L)', sd, j ->> 'descarga_id', 'x''; drop'), null, 'no es válida');

  -- ---------- 11. La foto: lo que llega después de iniciar no entra ----------
  j := public.geoportal_redes_reporte_iniciar(sd, 'levantamientos', per, 'xlsx', true, null);
  insert into redes.levantar_puntos (id, codigo, servicio, tipo, lat, lon, geom, precision_m, precision_baja, area, autor)
  values (gen_random_uuid(), 'LEV-900004', 'acueducto', 'hidrante', pg_temp.lat(90), pg_temp.lon(90), pg_temp.pt(90, 90), 3, false, 'tecnica', op);
  perform pg_temp.reg('11.01 un LEV reportado después de iniciar no sale en las páginas de esa descarga (sí en una nueva)',
    not pg_temp.hay(pg_temp.todas(sd, (j ->> 'descarga_id')::bigint), 'codigo', 'LEV-900004') and pg_temp.hay(pg_temp.bajar(sd, 'levantamientos', per) -> 'filas', 'codigo', 'LEV-900004'));

  -- ---------- 12. La descarga es de quien la inició, vence y se cierra una vez ----------
  v_id := (public.geoportal_redes_reporte_iniciar(sd, 'eventos', per, 'csv', false, '10.0.0.2') ->> 'descarga_id')::bigint;
  perform pg_temp.err('12.01 otra persona no puede pedir sus páginas (404)', format('select public.geoportal_redes_reporte_pagina(%L, %s)', sd2, v_id), 'P0002');
  perform pg_temp.err('12.02 ni cerrarla (404)', format('select public.geoportal_redes_reporte_cerrar(%L, %s, 1)', sd2, v_id), 'P0002');
  j := public.geoportal_redes_reporte_cerrar(sd, v_id, 1, 'completa', '10.0.0.2');
  j2 := public.geoportal_redes_reporte_cerrar(sd, v_id, 1, 'completa', '10.0.0.2');
  perform pg_temp.reg('12.03 cerrarla dos veces no es error: la segunda dice «repetida»', (j ->> 'repetida')::boolean = false and (j2 ->> 'repetida')::boolean = true);
  perform pg_temp.err('12.04 cerrada, sus páginas ya no salen (409)', format('select public.geoportal_redes_reporte_pagina(%L, %s)', sd, v_id), '55000', 'ya terminó');
  insert into redes.reporte_descargas (email, reporte, filtros, incluir, formato, total, corte_en, creado_en)
  values (sd, 'eventos', per, false, 'xlsx', 1, clock_timestamp() - interval '3 hours', clock_timestamp() - interval '3 hours') returning id into v_id2;
  perform pg_temp.err('12.05 iniciada hace más de 2 horas: venció (409)', format('select public.geoportal_redes_reporte_pagina(%L, %s)', sd, v_id2), '55000', 'venció');
  perform pg_temp.err('12.06 un resultado de cierre que no existe', format('select public.geoportal_redes_reporte_cerrar(%L, %s, 1, %L)', sd, v_id2, 'otra'), null, 'no válido');

  -- ---------- 13. Auditoría ----------
  select count(*) into v_aud from public.geoportal_auditoria a where a.accion = 'redes_reporte_iniciar' and a.referencia = v_id::text and a.email = sd and a.ip = '10.0.0.2'
     and a.detalle ->> 'reporte' = 'eventos' and (a.detalle ->> 'filas')::integer >= 1 and a.detalle -> 'filtros' ->> 'desde' = (hoy - 30)::text;
  perform pg_temp.reg('13.01 iniciar queda en la auditoría: quién, qué reporte, filtros, filas, formato e IP', v_aud = 1);
  perform pg_temp.reg('13.02 cerrar queda una sola vez en la auditoría, con las filas entregadas y el resultado',
    (select count(*) from public.geoportal_auditoria a where a.accion = 'redes_reporte_cerrar' and a.referencia = v_id::text and (a.detalle ->> 'filas_entregadas')::integer = 1 and a.detalle ->> 'resultado' = 'completa') = 1);
  perform pg_temp.reg('13.03 la auditoría de estas descargas no guarda filas ni textos libres', not exists (select 1 from public.geoportal_auditoria a where a.accion like 'redes\_reporte\_%' and (a.detalle ? 'filas_json' or position('Pedro' in a.detalle::text) > 0)));

  -- ---------- 14. Seguridad del esquema ----------
  perform pg_temp.reg('14.01 las 3 RPC: security definer, search_path fijo, solo service_role (ni anon, ni authenticated, ni PUBLIC)',
    (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array['geoportal_redes_reporte_iniciar', 'geoportal_redes_reporte_pagina', 'geoportal_redes_reporte_cerrar']) and p.prosecdef and p.proconfig is not null
       and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 3);
  perform pg_temp.reg('14.02 las funciones internas f_rep_*: nadie más que su dueño',
    not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname = any (array['f_rep_catalogo', 'f_rep_max_filas', 'f_rep_ts', 'f_rep_col', 'f_rep_rotulo', 'f_rep_sector_geom', 'f_rep_punto', 'f_rep_filtros', 'f_rep_columnas', 'f_rep_levantamientos', 'f_rep_valvulas', 'f_rep_eventos', 'f_rep_l116', 'f_rep_bot', 'f_rep_sensibles', 'f_rep_activos', 'f_rep_filas', 'f_rep_contar', 'f_rep_leame']) and exists (select 1 from aclexplode(p.proacl) x where x.grantee <> p.proowner)));
  perform pg_temp.reg('14.03 las 2 tablas nuevas: RLS y sin permisos para la API',
    (select count(*) from pg_class c where c.oid in ('redes.reporte_descargas'::regclass, 'redes.reporte_descarga_cierres'::regclass) and c.relrowsecurity
       and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')) = 2);
  perform pg_temp.err('14.04 las descargas son de solo inserción: no se cambian', format('update redes.reporte_descargas set total = 0 where id = %s', v_id));
  perform pg_temp.err('14.05 ni se borran', format('delete from redes.reporte_descarga_cierres where descarga_id = %s', v_id));
  perform pg_temp.reg('14.07 las rutas publicadas del bot de nombre parecido (reporte_convertir y reporte_descartar) siguen para service_role',
    has_function_privilege('service_role', 'public.geoportal_redes_reporte_convertir(text,uuid,jsonb)', 'execute') and has_function_privilege('service_role', 'public.geoportal_redes_reporte_descartar(text,uuid,text)', 'execute'));
  perform pg_temp.reg('14.06 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  -- ---------- 15. Tiempos con el volumen real: Activos de la red completo ----------
  v_t0 := clock_timestamp(); j := public.geoportal_redes_reporte_iniciar(sd, 'activos', '{}', 'xlsx', false, null); v_ms1 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_t0 := clock_timestamp(); j2 := public.geoportal_redes_reporte_pagina(sd, (j ->> 'descarga_id')::bigint, null, 5000); v_ms2 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_info := format('TIEMPOS con el volumen real: Activos de la red (%s activos) iniciar %s ms · primera página de 5.000 %s ms (tope de la API: 30 s por llamada)',
                   j ->> 'total', round(v_ms1), round(v_ms2));
  perform pg_temp.reg('15.01 TIEMPOS: iniciar «Activos de la red» completo y su primera página de 5.000, cada uno en menos de 5 s', (j2 ->> 'devueltos')::integer = least(5000, (j ->> 'total')::integer) and v_ms1 < 5000 and v_ms2 < 5000, v_info);

  -- ---------- 16. El tope de filas (se baja solo dentro de esta prueba) ----------
  create or replace function redes.f_rep_max_filas() returns integer language sql immutable set search_path to 'pg_catalog' as $f$ select 2 $f$;
  perform pg_temp.err('16.01 más filas que el tope: «Acote el periodo o los filtros»', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'activos', '{"tipo": "SEC"}'), null, 'Acote el periodo');

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · descargas de Distribución (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
