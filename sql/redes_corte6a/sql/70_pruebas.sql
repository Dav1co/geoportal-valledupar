-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 26, 25 y 40, en la misma transacción.
-- Como las de los cortes anteriores: corre después de la carga real y de los cortes publicados; NO supone códigos ni conteos de la base. Arma sus personas
-- (prueba.redes10.*), sus activos (creados con el motor, en un rincón de Valledupar), un daño, una intervención, un reporte del bot y sus puntos MUE-96nn.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 6a … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.sha(p text) returns text language sql as $$ select encode(sha256(convert_to(p, 'UTF8')), 'hex') $$;
-- posición de prueba: x, y en metros aproximados desde un rincón de Valledupar, lejos de los datos reales
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4200 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.3000 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.ln(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakeLine(pg_temp.pt(x, y), pg_temp.pt(x + 60, y)), 4326) $$;
create function pg_temp.activo(p_prefijo text, p_geom geometry, p_material text default null, p_diam numeric default null, p_fecha date default null, p_clase text default null) returns text language plpgsql as $$
declare v_id bigint := redes.f_activo_crear(p_prefijo, p_geom, p_clase, p_material, p_diam, 'ZT10 ' || p_prefijo, p_fecha, '{}'::jsonb, 'emdupar', null,
                                            'prueba.redes10.adm@emdupar.gov.co', 'Activo de prueba del Corte 6a');
begin
  return (select codigo from redes.activos where id = v_id);
end $$;
-- ¿la tesela (base64) trae este texto? (los códigos y los valores de texto viajan tal cual dentro del MVT)
create function pg_temp.trae(p_b64 text, p_txt text) returns boolean language sql as $$
  select coalesce(position(convert_to(p_txt, 'UTF8') in decode(nullif(p_b64, ''), 'base64')) > 0, false) $$;
-- la tesela del geovisor que contiene un punto de prueba, a un zoom
create function pg_temp.tesela(p_quien text, p_z integer, x numeric, y numeric) returns text language sql as $$
  select public.geoportal_redes_geovisor_mvt(p_quien, p_z, floor((pg_temp.lon(x) + 180) / 360 * (1 << p_z))::integer,
                                             floor((1 - ln(tan(radians(pg_temp.lat(y))) + 1 / cos(radians(pg_temp.lat(y)))) / pi()) / 2 * (1 << p_z))::integer) $$;
-- ¿la tesela que contiene el activo (a ese zoom) lo trae?
create function pg_temp.sale(p_quien text, p_z integer, p_codigo text) returns boolean language sql as $$
  select pg_temp.trae(public.geoportal_redes_geovisor_mvt(p_quien, p_z, floor((ST_X(c) + 180) / 360 * (1 << p_z))::integer,
                                                         floor((1 - ln(tan(radians(ST_Y(c))) + 1 / cos(radians(ST_Y(c)))) / pi()) / 2 * (1 << p_z))::integer), p_codigo)
    from (select ST_PointOnSurface(geom) as c from redes.activo_vigente_mat where codigo = p_codigo) x $$;
create function pg_temp.codigos(p jsonb) returns text[] language sql as $$ select coalesce(array_agg(f -> 'properties' ->> 'codigo'), '{}') from jsonb_array_elements(p -> 'features') f $$;
create function pg_temp.encendidas(p jsonb) returns text[] language sql as $$
  select coalesce(array_agg(c ->> 'codigo' order by c ->> 'codigo'), '{}') from jsonb_array_elements(p -> 'capas') c where (c ->> 'encendida')::boolean $$;
create function pg_temp.visibles(p jsonb) returns text[] language sql as $$ select coalesce(array_agg(c ->> 'codigo'), '{}') from jsonb_array_elements(p -> 'capas') c $$;
create function pg_temp.archivo(p_ruta text, p_bytes integer default 300000, p_mime text default 'image/jpeg') returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', p_bytes, 'mimetype', p_mime)) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
create function pg_temp.dia(p timestamptz) returns date language sql as $$ select (p at time zone 'America/Bogota')::date $$;

do $prueba$
declare
  a text := 'prueba.redes10.adm@emdupar.gov.co'; sd text := 'prueba.redes10.dist@emdupar.gov.co'; sv text := 'prueba.redes10.planta@emdupar.gov.co';
  dos text := 'prueba.redes10.dos@emdupar.gov.co'; op text := 'prueba.redes10.op@emdupar.gov.co'; op2 text := 'prueba.redes10.op2@emdupar.gov.co';
  na text := 'prueba.redes10.nada@emdupar.gov.co';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_r jsonb; v_x jsonb; v_c bigint; v_ca bigint; v_t text; v_n integer; v_v integer; v_p jsonb;
  r_chica text; r_grande text; v_val text; v_acc text; v_tan text; v_col_chico text; v_poz text; v_sen text; v_sec text; v_ret text;
  v_dano jsonb; v_itv jsonb; v_dia_dano date; v_dia_itv date;
  v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT10 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT10 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT10 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, ver_dashboard_redes, horario, dias) values (dos, 'ZT10 Los dos', 'consulta', true, true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT10 Operador uno', 'consulta', true, 'sin_restriccion', 'todos'),
    (op2, 'ZT10 Operador sin geovisor', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT10 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a), (op2, 'asignar_formulario', 'mantenimiento', a);

  -- ===================== 01. Esquema =====================
  perform pg_temp.reg('01.01 quién carga: las 4 capas del modelo solo el administrador; las demás (13, con muestreo) también el supervisor de distribución',
     (select count(*) from redes.capas where not carga_supervisor and codigo in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas')) = 4
     and (select count(*) from redes.capas where carga_supervisor) = 13 and (select carga_supervisor from redes.capas where codigo = 'muestreo'));
  perform pg_temp.reg('01.02 el catálogo del geovisor: 19 capas, 7 de tesela con prefijos que existen, 4 por GeoJSON y 8 preparadas',
     (select count(*) from redes.geovisor_capas) = 19 and (select count(*) from redes.geovisor_capas where fuente = 'tesela') = 7
     and (select count(*) from redes.geovisor_capas where fuente = 'geojson') = 4 and (select count(*) from redes.geovisor_capas where fuente = 'preparada') = 8
     and not exists (select 1 from redes.geovisor_capas g cross join unnest(g.prefijos) p where not exists (select 1 from redes.tipos_activo t where t.prefijo = p)));
  perform pg_temp.reg('01.03 ningún prefijo está en dos capas de tesela (un activo, un interruptor)',
     (select count(p) = count(distinct p) from redes.geovisor_capas g cross join unnest(g.prefijos) p));
  perform pg_temp.reg('01.04 capas al abrir: distribución 7, planta 2, operador 6; ninguna preparada, y el operador solo las que ve',
     (select count(*) from redes.capas_por_perfil where encendida and perfil = 'supervisor_distribucion') = 7
     and (select count(*) from redes.capas_por_perfil where encendida and perfil = 'supervisor_planta') = 2
     and (select count(*) from redes.capas_por_perfil where encendida and perfil = 'operador_distribucion') = 6
     and not exists (select 1 from redes.capas_por_perfil c join redes.geovisor_capas g on g.codigo = c.capa where c.encendida and (g.fuente = 'preparada' or (c.perfil = 'operador_distribucion' and g.solo_completo))));
  perform pg_temp.reg('01.05 los 8 parámetros del geovisor, con su valor dentro del rango',
     (select count(*) from redes.parametros where clave like 'geovisor\_%' and valor between minimo and maximo) = 8 and redes.f_param('geovisor_zoom_min') = 13);
  perform pg_temp.err('01.06 el catálogo no se borra', $$delete from redes.geovisor_capas where codigo = 'mapa_calor'$$, '42501');
  perform pg_temp.err('01.07 las capas por perfil no se borran', $$delete from redes.capas_por_perfil$$, '42501');
  perform pg_temp.err('01.08 una capa de tesela sin prefijos no se admite', $$insert into redes.geovisor_capas (codigo, nombre, grupo, fuente, orden) values ('zt_sin', 'Sin prefijos', 'acueducto', 'tesela', 1)$$, '23514');

  -- ===================== 02. Quién carga (David, 16-nov 01:30) =====================
  v_r := public.geoportal_redes_cargue_capas(sd);
  perform pg_temp.reg('02.01 el supervisor de distribución ve «puede cargar», por capa: sensores sí; acueducto, conductos, pozos y descargas no (solo el administrador)',
     (v_r ->> 'puede_cargar')::boolean
     and (select bool_and((x ->> 'puede_cargar')::boolean) from jsonb_array_elements(v_r -> 'capas') x where x ->> 'codigo' in ('sensores', 'acometidas', 'sumideros', 'muestreo', 'sectores', 'scada'))
     and (select bool_and(not (x ->> 'puede_cargar')::boolean and (x ->> 'solo_admin')::boolean) from jsonb_array_elements(v_r -> 'capas') x where x ->> 'codigo' in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas')));
  v_r := public.geoportal_redes_cargue_capas(a);
  perform pg_temp.reg('02.02 el administrador puede cargar todas', (v_r ->> 'puede_cargar')::boolean
     and not exists (select 1 from jsonb_array_elements(v_r -> 'capas') x where x ->> 'lector' is not null and not (x ->> 'puede_cargar')::boolean));
  perform pg_temp.err('02.03 el supervisor de planta no ve el Cargue (como antes)', format($$select public.geoportal_redes_cargue_capas(%L)$$, sv), '42501');
  perform pg_temp.err('02.04 el supervisor de distribución no abre la red de acueducto', format($$select public.geoportal_redes_cargue_iniciar(%L, 'acueducto', %L, 'shp', 4326, 'ID', 1)$$, sd, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.05 … ni los conductos', format($$select public.geoportal_redes_cargue_iniciar(%L, 'alc_conductos', %L, 'shp', 4326, 'LABEL', 1)$$, sd, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.06 … ni los pozos', format($$select public.geoportal_redes_cargue_iniciar(%L, 'alc_pozos', %L, 'shp', 4326, 'LABEL', 1)$$, sd, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.07 … ni las descargas (también salen del modelo de alcantarillado)', format($$select public.geoportal_redes_cargue_iniciar(%L, 'alc_descargas', %L, 'shp', 4326, 'LABEL', 1)$$, sd, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.08 el supervisor de planta no carga', format($$select public.geoportal_redes_cargue_iniciar(%L, 'sensores', %L, 'geojson', 4326, 'ID', 1)$$, sv, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.09 el operador no carga', format($$select public.geoportal_redes_cargue_iniciar(%L, 'sensores', %L, 'geojson', 4326, 'ID', 1)$$, op, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.10 la carga por psql del 1a sigue siendo del administrador', format($$select public.geoportal_redes_carga_iniciar(%L, 'sensores', %L, 'geojson', 4326, 'ID', 1)$$, sd, pg_temp.sha('zt10-x')), '42501');
  -- el supervisor de distribución carga sensores de punta a punta (abrir, lote, resumen, vista previa y publicar)
  v_r := public.geoportal_redes_cargue_iniciar(sd, 'sensores', pg_temp.sha('zt10-sen'), 'geojson', 4326, 'ID', 2, 'ZT10 sensores del supervisor', '0b1e7d1c-2222-4222-8333-944455556666');
  v_c := (v_r ->> 'carga_id')::bigint;
  perform pg_temp.reg('02.11 el supervisor de distribución abre una carga de sensores (con la marca de la masiva y su auditoría)', (v_r ->> 'nueva')::boolean
     and (select autor from redes.cargas where id = v_c) = sd and exists (select 1 from public.geoportal_auditoria where accion = 'redes_carga_iniciar' and referencia = v_c::text and email = sd), v_r::text);
  v_r := public.geoportal_redes_carga_lote(sd, v_c, jsonb_build_array(
    jsonb_build_object('orden', 1, 'wkt', format('POINT(%s %s)', pg_temp.lon(500), pg_temp.lat(500)), 'atributos', '{"ID": "ZT10-S1", "NOMBRE": "ZT10 Sensor uno"}'::jsonb),
    jsonb_build_object('orden', 2, 'wkt', format('POINT(%s %s)', pg_temp.lon(520), pg_temp.lat(500)), 'atributos', '{"ID": "ZT10-S2", "NOMBRE": "ZT10 Sensor dos"}'::jsonb)));
  v_x := public.geoportal_redes_carga_resumen(sd, v_c);
  perform pg_temp.reg('02.12 … pasa el lote y ve el resumen (2 de tipo SEN, lista para publicar)', (v_x -> 'por_prefijo' ->> 'SEN')::integer = 2 and (v_x ->> 'lista_para_publicar')::boolean, left(v_x::text, 300));
  v_x := public.geoportal_redes_carga_muestra(sd, v_c);
  perform pg_temp.reg('02.13 … y la vista previa', (v_x ->> 'con_geometria')::integer = 2);
  v_x := public.geoportal_redes_carga_publicar(sd, v_c, 'ZT10 primera carga de sensores');
  perform pg_temp.reg('02.14 … y publica: 2 sensores vigentes, con la auditoría a su nombre',
     (select count(*) from redes.activo_vigente_mat where capa_codigo = 'sensores' and llave_capa like 'ZT10-S%' and not retirado) = 2
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_carga_publicar' and referencia = v_c::text and email = sd), left(v_x::text, 300));
  select codigo into v_sen from redes.activo_vigente_mat where capa_codigo = 'sensores' and llave_capa = 'ZT10-S1';
  -- una carga del acueducto abierta por el administrador: el supervisor no la toca
  v_ca := (public.geoportal_redes_cargue_iniciar(a, 'acueducto', pg_temp.sha('zt10-acu'), 'shp', 4326, 'ID', 1, 'ZT10 abierta por el administrador') ->> 'carga_id')::bigint;
  perform pg_temp.err('02.15 el supervisor no pasa lotes a una carga del acueducto', format($$select public.geoportal_redes_carga_lote(%L, %s, '[{"orden": 1, "wkt": null, "atributos": {}}]')$$, sd, v_ca), '42501');
  perform pg_temp.err('02.16 … ni ve su resumen', format($$select public.geoportal_redes_carga_resumen(%L, %s)$$, sd, v_ca), '42501');
  perform pg_temp.err('02.17 … ni su vista previa', format($$select public.geoportal_redes_carga_muestra(%L, %s)$$, sd, v_ca), '42501');
  perform pg_temp.err('02.18 … ni la publica', format($$select public.geoportal_redes_carga_publicar(%L, %s, 'ZT10 no debe')$$, sd, v_ca), '42501');
  perform pg_temp.err('02.19 … ni la anula', format($$select public.geoportal_redes_carga_anular(%L, %s, 'ZT10 no debe poder')$$, sd, v_ca), '42501');
  perform pg_temp.err('02.20 … ni devuelve campos en ella', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, 'RED-000001', 'nombre', 'ZT10 no debe poder')$$, sd, v_ca), '42501');
  perform pg_temp.err('02.21 … ni revierte el acueducto', format($$select public.geoportal_redes_carga_revertir(%L, 'acueducto', 'ZT10 no debe poder')$$, sd), '42501');
  perform public.geoportal_redes_carga_anular(a, v_ca, 'ZT10 era de prueba');
  perform pg_temp.reg('02.22 el administrador sí anula la suya', (select estado from redes.v_cargas_estado where id = v_ca) = 'anulada');
  perform pg_temp.err('02.23 una carga que no existe: al supervisor no se le dice si existe', format($$select public.geoportal_redes_carga_resumen(%L, -5)$$, sd), '42501');
  perform pg_temp.err('02.24 al administrador sí', format($$select public.geoportal_redes_carga_resumen(%L, -5)$$, a), 'P0002');
  -- el origen al devolver un campo sigue siendo solo del administrador (§26.2)
  v_c := (public.geoportal_redes_cargue_iniciar(sd, 'sensores', pg_temp.sha('zt10-sen-2'), 'geojson', 4326, 'ID', 1) ->> 'carga_id')::bigint;
  perform pg_temp.err('02.25 el supervisor no devuelve «origen» a la capa', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'origen', 'ZT10 el origen no lo toca')$$, sd, v_c, v_sen), '42501');
  perform pg_temp.err('02.26 un campo no editado en la ficha sí llega a la regla de siempre (el supervisor pasó el permiso)',
     format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'nombre', 'ZT10 probar el permiso')$$, sd, v_c, v_sen), '55000', 'no está editado');
  perform public.geoportal_redes_carga_anular(sd, v_c, 'ZT10 era de prueba');
  perform pg_temp.reg('02.27 el supervisor anula la suya de sensores', (select estado from redes.v_cargas_estado where id = v_c) = 'anulada');
  v_x := public.geoportal_redes_carga_revertir(sd, 'sensores', 'ZT10 volver a la versión anterior');
  perform pg_temp.reg('02.28 … y revierte sensores a la versión anterior (sin los 2 de prueba)',
     (select count(*) from redes.activo_vigente_mat where capa_codigo = 'sensores' and llave_capa like 'ZT10-S%' and not retirado) = 0, left(v_x::text, 300));

  -- ===================== 03. Quién abre el geovisor y con qué capas (N-11 y N-13) =====================
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT10 necesita ver la red en la calle');
  perform pg_temp.reg('03.01 «geovisor» en mi perfil: supervisores, administrador y el operador con la casilla sí; el que no la tiene, no',
     (public.geoportal_redes_mi_perfil(a) ->> 'geovisor')::boolean and (public.geoportal_redes_mi_perfil(sd) ->> 'geovisor')::boolean
     and (public.geoportal_redes_mi_perfil(sv) ->> 'geovisor')::boolean and (public.geoportal_redes_mi_perfil(op) ->> 'geovisor')::boolean
     and not (public.geoportal_redes_mi_perfil(op2) ->> 'geovisor')::boolean and (public.geoportal_redes_mi_perfil(sd) ->> 'dashboard_redes')::boolean);
  v_r := public.geoportal_redes_geovisor(a);
  perform pg_temp.reg('03.02 el administrador: completo, con los dos perfiles de supervisor y las capas encendidas de los dos (8)',
     v_r ->> 'perfil' = 'admin' and (v_r ->> 'completo')::boolean and v_r -> 'perfiles' = '["supervisor_distribucion", "supervisor_planta"]'::jsonb
     and pg_temp.encendidas(v_r) = array['acu_instalaciones', 'acu_nodos', 'acu_tramos', 'alc_conductos', 'alc_pozos', 'danos', 'intervenciones', 'muestreo']
     and cardinality(pg_temp.visibles(v_r)) = 19, pg_temp.encendidas(v_r)::text);
  perform pg_temp.reg('03.03 … y la tabla de capas por omisión para editarla', jsonb_array_length(v_r -> 'por_perfil') = 15);
  perform pg_temp.reg('03.04 … con zooms, rango, hoy, tipos con su alias y materiales', (v_r -> 'zoom' ->> 'min')::numeric = 13 and (v_r ->> 'rango_meses')::integer = 12
     and (v_r ->> 'hoy')::date = hoy and v_r -> 'tipos' ->> 'RED' is not null and v_r -> 'estados' ->> 'en_operacion' = 'En operación' and jsonb_array_length(v_r -> 'materiales') > 0 and (v_r ->> 'version')::integer >= 1);
  v_r := public.geoportal_redes_geovisor(sd);
  perform pg_temp.reg('03.05 el supervisor de distribución: redes y actividades encendidas; muestreo y reportes del bot los ve pero apagados; sin la tabla de omisión',
     v_r ->> 'perfil' = 'supervisor' and pg_temp.encendidas(v_r) = array['acu_instalaciones', 'acu_nodos', 'acu_tramos', 'alc_conductos', 'alc_pozos', 'danos', 'intervenciones']
     and 'muestreo' = any (pg_temp.visibles(v_r)) and 'reportes_bot' = any (pg_temp.visibles(v_r)) and v_r -> 'por_perfil' = 'null'::jsonb, pg_temp.encendidas(v_r)::text);
  perform pg_temp.reg('03.06 … y los dos formularios (por su permiso de supervisor)', (v_r -> 'formularios' ->> 'danos_fallas')::boolean and (v_r -> 'formularios' ->> 'mantenimiento')::boolean);
  v_r := public.geoportal_redes_geovisor(sv);
  perform pg_temp.reg('03.07 el supervisor de planta: muestreo y tanques encendidos; completo',
     pg_temp.encendidas(v_r) = array['acu_instalaciones', 'muestreo'] and (v_r ->> 'completo')::boolean and v_r -> 'perfiles' = '["supervisor_planta"]'::jsonb, pg_temp.encendidas(v_r)::text);
  v_r := public.geoportal_redes_geovisor(dos);
  perform pg_temp.reg('03.08 una persona de las dos áreas: la unión de las capas de sus perfiles',
     pg_temp.encendidas(v_r) = array['acu_instalaciones', 'acu_nodos', 'acu_tramos', 'alc_conductos', 'alc_pozos', 'danos', 'intervenciones', 'muestreo'], pg_temp.encendidas(v_r)::text);
  v_r := public.geoportal_redes_geovisor(op);
  perform pg_temp.reg('03.09 el operador con la casilla: solo lectura, sin muestreo, reportes ni capas preparadas; redes y actividades encendidas',
     v_r ->> 'perfil' = 'operador' and not (v_r ->> 'completo')::boolean and not (v_r ->> 'ficha')::boolean
     and not ('muestreo' = any (pg_temp.visibles(v_r))) and not ('reportes_bot' = any (pg_temp.visibles(v_r))) and not ('contratos' = any (pg_temp.visibles(v_r)))
     and pg_temp.encendidas(v_r) = array['acu_nodos', 'acu_tramos', 'alc_conductos', 'alc_pozos', 'danos', 'intervenciones'], pg_temp.visibles(v_r)::text);
  perform pg_temp.reg('03.10 … con «Reportar daño» (lo tiene asignado) y sin «Registrar intervención» (no lo tiene)',
     (v_r -> 'formularios' ->> 'danos_fallas')::boolean and not (v_r -> 'formularios' ->> 'mantenimiento')::boolean);
  perform pg_temp.err('03.11 el operador sin la casilla no abre el geovisor (aunque tenga formularios de distribución)', format($$select public.geoportal_redes_geovisor(%L)$$, op2), '42501');
  perform pg_temp.err('03.12 quien no es de Técnica no lo abre', format($$select public.geoportal_redes_geovisor(%L)$$, na), '42501');
  perform pg_temp.err('03.13 sin solicitante', $$select public.geoportal_redes_geovisor('')$$, '28000');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'no', 'ZT10 ya no necesita el geovisor');
  perform pg_temp.err('03.14 al quitarle la casilla, el operador deja de abrirlo', format($$select public.geoportal_redes_geovisor(%L)$$, op), '42501');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT10 lo necesita otra vez');

  -- ===================== 04. Capas por omisión (las edita el administrador, con motivo) =====================
  perform pg_temp.err('04.01 el supervisor no las cambia', format($$select public.geoportal_redes_geovisor_capas_fijar(%L, 'supervisor_distribucion', 'muestreo', true, 'ZT10 no debe poder')$$, sd), '42501');
  perform pg_temp.err('04.02 sin motivo, no', format($$select public.geoportal_redes_geovisor_capas_fijar(%L, 'supervisor_distribucion', 'muestreo', true, 'corto')$$, a), '22023', 'motivo');
  perform pg_temp.err('04.03 una capa preparada no se enciende al abrir', format($$select public.geoportal_redes_geovisor_capas_fijar(%L, 'supervisor_distribucion', 'contratos', true, 'ZT10 todavía no tiene datos')$$, a), '22023', 'todavía no tiene datos');
  perform pg_temp.err('04.04 al operador no se le enciende lo que no ve', format($$select public.geoportal_redes_geovisor_capas_fijar(%L, 'operador_distribucion', 'muestreo', true, 'ZT10 el operador no la ve')$$, a), '22023', 'no ve');
  perform pg_temp.err('04.05 un perfil que no existe', format($$select public.geoportal_redes_geovisor_capas_fijar(%L, 'gerente', 'muestreo', true, 'ZT10 perfil que no existe')$$, a), '22023', 'perfil');
  v_x := public.geoportal_redes_geovisor_capas_fijar(a, 'supervisor_distribucion', 'muestreo', true, 'ZT10 el supervisor también mira el muestreo');
  perform pg_temp.reg('04.06 el administrador enciende muestreo para el supervisor de distribución: queda el evento con el antes y la auditoría',
     (v_x ->> 'cambio')::boolean and 'muestreo' = any (pg_temp.encendidas(public.geoportal_redes_geovisor(sd)))
     and exists (select 1 from redes.capas_por_perfil_eventos where perfil = 'supervisor_distribucion' and capa = 'muestreo' and antes is null and despues and autor = a)
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_geovisor_capas_fijar' and referencia = 'supervisor_distribucion/muestreo'));
  v_x := public.geoportal_redes_geovisor_capas_fijar(a, 'supervisor_distribucion', 'muestreo', true, 'ZT10 otra vez lo mismo');
  perform pg_temp.reg('04.07 lo mismo otra vez no deja otro evento', not (v_x ->> 'cambio')::boolean
     and (select count(*) from redes.capas_por_perfil_eventos where perfil = 'supervisor_distribucion' and capa = 'muestreo') = 1);
  perform public.geoportal_redes_geovisor_capas_fijar(a, 'supervisor_distribucion', 'danos', false, 'ZT10 los daños se prenden a mano');
  perform pg_temp.reg('04.08 apagar una: el supervisor ya no la abre encendida; el administrador tampoco (si nadie de sus perfiles la tiene)',
     not ('danos' = any (pg_temp.encendidas(public.geoportal_redes_geovisor(sd)))) and not ('danos' = any (pg_temp.encendidas(public.geoportal_redes_geovisor(a))))
     and (select antes and not despues from redes.capas_por_perfil_eventos where capa = 'danos'));
  perform pg_temp.err('04.09 los eventos no se cambian', $$update redes.capas_por_perfil_eventos set motivo = 'cambiado a mano'$$, '42501');

  -- ===================== 05. La tesela del geovisor =====================
  r_chica := pg_temp.activo('RED', pg_temp.ln(0, 0), 'PVC', 100, (hoy - interval '30 years')::date);
  r_grande := pg_temp.activo('RED', pg_temp.ln(0, 40), 'AC', 250, null);
  v_val := pg_temp.activo('VAL', pg_temp.pt(0, 80), null, 100, null, null);
  v_acc := pg_temp.activo('ACC', pg_temp.pt(20, 80));
  v_tan := pg_temp.activo('TAN', pg_temp.pt(40, 80));
  v_col_chico := pg_temp.activo('COL', pg_temp.ln(0, 120), 'CONCRETO', 200, null);
  v_poz := pg_temp.activo('POZ', pg_temp.pt(60, 80));
  v_sec := pg_temp.activo('SEC', ST_SetSRID(ST_MakeEnvelope(pg_temp.lon(-50), pg_temp.lat(-50), pg_temp.lon(150), pg_temp.lat(200)), 4326));
  v_ret := pg_temp.activo('VAL', pg_temp.pt(80, 80));
  update redes.activo_vigente_mat set retirado = true where codigo = v_ret;      -- un retirado (en la vida real lo deja así una recarga)
  perform pg_temp.reg('05.00 activos de prueba creados con el motor',
     (select count(*) from redes.activo_vigente_mat where codigo in (r_chica, r_grande, v_val, v_acc, v_tan, v_col_chico, v_poz, v_sec)) = 8,
     concat_ws(' ', r_chica, r_grande, v_val, v_acc, v_tan, v_col_chico, v_poz, v_sec));
  perform pg_temp.reg('05.01 a zoom 12 la tesela sale vacía (la red no se dibuja tan lejos)', pg_temp.tesela(a, 12, 0, 0) = '' and not pg_temp.sale(a, 12, r_grande));
  perform pg_temp.reg('05.02 a zoom 13: la red principal (250 mm), el tanque y el sector; no el tramo de 100 mm, ni el conducto de 200, ni la válvula ni el pozo',
     pg_temp.sale(a, 13, r_grande) and pg_temp.sale(a, 13, v_tan) and pg_temp.sale(a, 13, v_sec)
     and not pg_temp.sale(a, 13, r_chica) and not pg_temp.sale(a, 13, v_col_chico) and not pg_temp.sale(a, 13, v_val) and not pg_temp.sale(a, 13, v_poz));
  perform pg_temp.reg('05.03 a zoom 14: todos los tramos; todavía no los puntos', pg_temp.sale(a, 14, r_chica) and pg_temp.sale(a, 14, v_col_chico) and not pg_temp.sale(a, 14, v_val));
  perform pg_temp.reg('05.04 a zoom 15: válvulas y pozos; no los accesorios', pg_temp.sale(a, 15, v_val) and pg_temp.sale(a, 15, v_poz) and not pg_temp.sale(a, 15, v_acc) and not pg_temp.sale(a, 16, v_acc));
  perform pg_temp.reg('05.05 a zoom 17: los accesorios', pg_temp.sale(a, 17, v_acc));
  v_t := pg_temp.tesela(a, 16, 0, 0);
  perform pg_temp.reg('05.06 trae lo que colorea: material, estado y la forma', pg_temp.sale(a, 16, r_chica) and pg_temp.trae(v_t, 'PVC') and pg_temp.trae(v_t, 'AC') and pg_temp.trae(v_t, 'en_operacion')
     and pg_temp.trae(v_t, 'tramo') and pg_temp.trae(v_t, 'area'));
  perform pg_temp.reg('05.07 un activo retirado no sale', not pg_temp.sale(a, 17, v_ret) and pg_temp.sale(a, 17, v_val));
  perform pg_temp.reg('05.08 el operador con la casilla también recibe la tesela de la red', pg_temp.sale(op, 16, r_chica) and pg_temp.sale(op, 16, v_poz));
  perform pg_temp.err('05.09 el operador sin la casilla no', format($$select pg_temp.tesela(%L, 16, 0, 0)$$, op2), '42501');
  perform pg_temp.err('05.10 una tesela fuera de rango', format($$select public.geoportal_redes_geovisor_mvt(%L, 14, 99999, 1)$$, a), '22023', 'fuera de rango');
  update redes.geovisor_capas set activa = false where codigo = 'alc_pozos';
  perform pg_temp.reg('05.11 una capa desactivada del catálogo deja de verse en el geovisor (sin otra migración)', not ('alc_pozos' = any (pg_temp.visibles(public.geoportal_redes_geovisor(a)))));
  perform pg_temp.reg('05.12 … el pozo ya no sale en la tesela y el tramo sí', not pg_temp.sale(a, 16, v_poz) and pg_temp.sale(a, 16, r_chica));
  update redes.geovisor_capas set activa = true where codigo = 'alc_pozos';
  perform pg_temp.reg('05.13 la edad sale en años (30 para el de 30 años) y sin fecha va sin edad',
     (select extract(year from age(hoy, fecha_instalacion))::integer from redes.activo_vigente_mat where codigo = r_chica) = 30
     and (select fecha_instalacion is null from redes.activo_vigente_mat where codigo = r_grande));

  -- ===================== 06. Capas por fecha (daños, intervenciones y reportes del bot) y muestreo =====================
  v_p := public.geoportal_redes_preparar_dano(op, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_dano := public.geoportal_redes_crear_dano(op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', r_chica,
         'lat', pg_temp.lat(0), 'lon', pg_temp.lon(30), 'ubicacion_origen', 'gps', 't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio',
         'causa_clase', 'terceros', 'tercero_tipo', 'vehiculo', 'tercero_nombre', 'ZT10 Placa ABC123', 'descripcion', 'ZT10 vecino Pedro 3001234567 avisó',
         'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))));
  v_dia_dano := pg_temp.dia((select t_detectado from redes.danos where codigo = v_dano ->> 'codigo'));
  v_r := public.geoportal_redes_geovisor_capa(sd, 'danos', v_dia_dano, v_dia_dano);
  perform pg_temp.reg('06.01 la capa de daños del día trae el daño con su código, tipo, estado y activo', (v_dano ->> 'codigo') = any (pg_temp.codigos(v_r))
     and (select f -> 'properties' ->> 'activo' from jsonb_array_elements(v_r -> 'features') f where f -> 'properties' ->> 'codigo' = v_dano ->> 'codigo') = r_chica
     and not (v_r ->> 'recortada')::boolean, left(v_r::text, 300));
  perform pg_temp.reg('06.02 sin la descripción, el tercero, las fotos ni el autor', v_r::text not like '%Pedro%' and v_r::text not like '%3001234567%' and v_r::text not like '%ABC123%'
     and v_r::text not like '%' || op || '%' and v_r::text not like '%redes-evidencias%');
  v_r := public.geoportal_redes_geovisor_capa(sd, 'danos', v_dia_dano - 3, v_dia_dano - 1);
  perform pg_temp.reg('06.03 en otras fechas no sale', not ((v_dano ->> 'codigo') = any (pg_temp.codigos(v_r))));
  perform public.geoportal_redes_dano_evento(sd, v_dano ->> 'codigo', 'ocultar', 'ZT10 dato de prueba');
  perform pg_temp.reg('06.04 un daño oculto no sale', not ((v_dano ->> 'codigo') = any (pg_temp.codigos(public.geoportal_redes_geovisor_capa(sd, 'danos', v_dia_dano, v_dia_dano)))));
  perform public.geoportal_redes_dano_evento(sd, v_dano ->> 'codigo', 'reincluir', 'ZT10 volver a mostrarlo');
  -- intervención del supervisor sobre el tramo, con su foto
  v_p := public.geoportal_redes_preparar_intervencion(sd, 1, 0);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_itv := public.geoportal_redes_crear_intervencion(sd, (v_p ->> 'intervencion_id')::uuid, jsonb_build_object('nace_de', 'programada', 'tipo', 'preventivo', 'sistema', 'acueducto',
         'activo', r_grande, 'lat', pg_temp.lat(40), 'lon', pg_temp.lon(10), 'precision_m', 5, 'ubicacion_origen', 'gps', 't_inicio', pg_temp.iso('-50 minutes'), 't_fin', pg_temp.iso('-10 minutes'),
         'descripcion', 'ZT10 limpieza, avisó la señora Marta', 'materiales', '[]'::jsonb, 'ejecutor', 'emdupar', 'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')),
         'archivos', jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'despues', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))));
  v_dia_itv := pg_temp.dia((select t_inicio from redes.intervenciones where codigo = v_itv ->> 'codigo'));
  v_r := public.geoportal_redes_geovisor_capa(sd, 'intervenciones', v_dia_itv, v_dia_itv);
  perform pg_temp.reg('06.05 la capa de intervenciones trae la del día con su tipo y activo, sin la descripción',
     (v_itv ->> 'codigo') = any (pg_temp.codigos(v_r)) and v_r::text not like '%Marta%'
     and (select f -> 'properties' ->> 'tipo_codigo' from jsonb_array_elements(v_r -> 'features') f where f -> 'properties' ->> 'codigo' = v_itv ->> 'codigo') = 'preventivo', left(v_r::text, 300));
  perform public.geoportal_redes_intervencion_evento(sd, v_itv ->> 'codigo', 'anulada', 'ZT10 era de prueba');
  perform pg_temp.reg('06.06 una intervención anulada no sale', not ((v_itv ->> 'codigo') = any (pg_temp.codigos(public.geoportal_redes_geovisor_capa(sd, 'intervenciones', v_dia_itv, v_dia_itv)))));
  -- reporte del bot
  perform redes.f_reporte_externo_recibir(jsonb_build_object('radicado', 'ZT10-0001', 'canal', 'telegram', 'tipo', 'Fuga', 'lat', pg_temp.lat(10), 'lon', pg_temp.lon(10),
                                                            'direccion', 'ZT10 Calle 1 # 2-3', 'descripcion', 'ZT10 la vecina Rosa', 'recibido_en', pg_temp.iso('-30 minutes')));
  v_r := public.geoportal_redes_geovisor_capa(sd, 'reportes_bot', pg_temp.dia(clock_timestamp() - interval '30 minutes'), pg_temp.dia(clock_timestamp() - interval '30 minutes'));
  perform pg_temp.reg('06.07 la capa de reportes del bot trae el radicado y el estado, sin la dirección ni la descripción',
     'ZT10-0001' = any (pg_temp.codigos(v_r)) and v_r::text not like '%Rosa%' and v_r::text not like '%Calle 1%', left(v_r::text, 300));
  -- muestreo
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9601', 'ZT10 Uno', 'muestreo', 'norte'), ('MUE-9602', 'ZT10 Dos', 'muestreo', 'sur');
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, autor) select id, pg_temp.lat(300), pg_temp.lon(300), 'verificada', 'david', a from tecnica.puntos where codigo = 'MUE-9601';
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, autor) select id, pg_temp.lat(320), pg_temp.lon(300), 'aproximada', 'barrio', a from tecnica.puntos where codigo = 'MUE-9602';
  v_r := public.geoportal_redes_geovisor_capa(sv, 'muestreo');
  perform pg_temp.reg('06.08 la capa de muestreo trae los puntos con su exactitud (verificada o aproximada)',
     (select f -> 'properties' ->> 'exactitud' from jsonb_array_elements(v_r -> 'features') f where f -> 'properties' ->> 'codigo' = 'MUE-9601') = 'verificada'
     and (select f -> 'properties' ->> 'exactitud' from jsonb_array_elements(v_r -> 'features') f where f -> 'properties' ->> 'codigo' = 'MUE-9602') = 'aproximada');
  -- reglas de las fechas y del operador
  perform pg_temp.err('06.09 más de 12 meses de rango', format($$select public.geoportal_redes_geovisor_capa(%L, 'danos', %L, %L)$$, sd, hoy - 400, hoy), '22023', '12 meses');
  perform pg_temp.err('06.10 la fecha final futura', format($$select public.geoportal_redes_geovisor_capa(%L, 'danos', %L, %L)$$, sd, hoy, hoy + 1), '22023', 'futura');
  perform pg_temp.err('06.11 las fechas al revés', format($$select public.geoportal_redes_geovisor_capa(%L, 'danos', %L, %L)$$, sd, hoy, hoy - 1), '22023', 'posterior');
  v_r := public.geoportal_redes_geovisor_capa(sd, 'danos', hoy - 365, hoy);
  perform pg_temp.reg('06.12 doce meses exactos sí', v_r ->> 'type' = 'FeatureCollection');
  v_r := public.geoportal_redes_geovisor_capa(op, 'danos');
  perform pg_temp.reg('06.13 el operador ve los daños del día (sin fechas = hoy)', (v_r ->> 'desde')::date = hoy and (v_r ->> 'hasta')::date = hoy
     and (v_dia_dano <> hoy or (v_dano ->> 'codigo') = any (pg_temp.codigos(v_r))));
  perform pg_temp.err('06.14 el operador no pide otros días', format($$select public.geoportal_redes_geovisor_capa(%L, 'danos', %L, %L)$$, op, hoy - 7, hoy), '42501');
  perform pg_temp.err('06.15 el operador no ve el muestreo', format($$select public.geoportal_redes_geovisor_capa(%L, 'muestreo')$$, op), '42501');
  perform pg_temp.err('06.16 … ni los reportes del bot', format($$select public.geoportal_redes_geovisor_capa(%L, 'reportes_bot')$$, op), '42501');
  perform pg_temp.err('06.17 una capa preparada no tiene datos', format($$select public.geoportal_redes_geovisor_capa(%L, 'contratos')$$, a), 'P0002');
  perform pg_temp.err('06.18 una capa de tesela no va por aquí', format($$select public.geoportal_redes_geovisor_capa(%L, 'acu_tramos')$$, a), 'P0002');
  perform pg_temp.err('06.19 el operador sin la casilla no ve las actividades', format($$select public.geoportal_redes_geovisor_capa(%L, 'danos')$$, op2), '42501');
  -- tope de elementos: con el parámetro en 100, un rango con más de 100 sale recortado (se arman 101 reportes del bot de prueba)
  for v_n in 1 .. 101 loop
    perform redes.f_reporte_externo_recibir(jsonb_build_object('radicado', 'ZT10-T' || lpad(v_n::text, 3, '0'), 'canal', 'telegram', 'tipo', 'Fuga',
                                                              'lat', pg_temp.lat(v_n), 'lon', pg_temp.lon(0), 'recibido_en', pg_temp.iso('-2 days')));
  end loop;
  update redes.parametros set valor = 100 where clave = 'geovisor_max_elementos';
  v_r := public.geoportal_redes_geovisor_capa(a, 'reportes_bot', pg_temp.dia(clock_timestamp() - interval '2 days'), pg_temp.dia(clock_timestamp() - interval '2 days'));
  perform pg_temp.reg('06.20 con más elementos que el tope: 100 y «recortada»', jsonb_array_length(v_r -> 'features') = 100 and (v_r ->> 'recortada')::boolean);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 6a (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
