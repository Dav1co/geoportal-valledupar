-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 25, 26 y 40, en la misma transacción.
-- Como las de los cortes anteriores: corre después de la carga real y de los cortes publicados; NO supone códigos ni conteos de la base. Arma sus personas
-- (prueba.redes8.*) y sus puntos de muestreo (MUE-98nn) con su ubicación. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 5b … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.mue(p_orden integer, p_codigo text, p_lat numeric, p_lon numeric, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', 'POINT(' || p_lon || ' ' || p_lat || ')', 'atributos', jsonb_strip_nulls(jsonb_build_object('codigo', p_codigo)) || p_extra) $$;
create function pg_temp.cargar_mue(p_admin text, p_huella text, p_filas jsonb) returns bigint language plpgsql as $$
declare v_c bigint := (public.geoportal_redes_carga_iniciar(p_admin, 'muestreo', pg_temp.sha(p_huella), 'csv', 4326, 'codigo', jsonb_array_length(p_filas)) ->> 'carga_id')::bigint;
begin
  perform public.geoportal_redes_carga_lote(p_admin, v_c, p_filas);
  return v_c;
end $$;
-- la ubicación vigente de un punto, como texto «exactitud|fuente|lat|lon|autor»
create function pg_temp.vig(p_codigo text) returns text language sql as $$
  select u.exactitud || '|' || u.fuente || '|' || u.lat || '|' || u.lon || '|' || u.autor from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = p_codigo $$;
-- la propiedad de un punto en el minimapa de una persona
create function pg_temp.mapa(p_quien text, p_codigo text) returns jsonb language sql as $$
  select f -> 'properties' from jsonb_array_elements(public.geoportal_tec_puntos_mapa(p_quien) -> 'features') f where f -> 'properties' ->> 'codigo' = p_codigo $$;

do $prueba$
declare
  a text := 'prueba.redes8.adm@emdupar.gov.co'; sv text := 'prueba.redes8.sup@emdupar.gov.co'; sv2 text := 'prueba.redes8.sup2@emdupar.gov.co';
  op text := 'prueba.redes8.op@emdupar.gov.co'; o2 text := 'prueba.redes8.op2@emdupar.gov.co'; osm text := 'prueba.redes8.sinmuestreo@emdupar.gov.co';
  sd text := 'prueba.redes8.dist@emdupar.gov.co'; na text := 'prueba.redes8.nada@emdupar.gov.co';
  -- un origen dentro de Valledupar, lejos de los 27 puntos reales (las pruebas no dependen de ellos)
  la numeric := 10.430000; lo numeric := -73.290000;
  v_r jsonb; v_x jsonb; v_id bigint; v_id2 bigint; v_id3 bigint; v_n integer; v_c bigint; v_t text; v_aud integer; v_ubic0 integer;
  v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT8 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values
    (sv, 'ZT8 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos'), (sv2, 'ZT8 Otro supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values
    (op, 'ZT8 Operador de planta', 'consulta', true, 'sin_restriccion', 'todos'), (o2, 'ZT8 Otro operador', 'consulta', true, 'sin_restriccion', 'todos'),
    (osm, 'ZT8 Operador sin Muestreo', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT8 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT8 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'muestreo', a), (o2, 'asignar_formulario', 'muestreo', a),
    (osm, 'asignar_formulario', 'entrada', a), (sd, 'asignar_formulario', 'muestreo', a);
  -- puntos de prueba: 9801 aproximado, 9802 aproximado, 9803 sin ubicación, 9804 verificado (David), 9805 desactivado, 9806 aproximado (para el rechazo)
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9801', 'ZT8 Uno', 'muestreo', 'norte'), ('MUE-9802', 'ZT8 Dos', 'muestreo', 'sur'),
    ('MUE-9803', 'ZT8 Tres', 'muestreo', 'medio'), ('MUE-9804', 'ZT8 Cuatro', 'muestreo', 'medio'), ('MUE-9805', 'ZT8 Cinco', 'muestreo', 'sur'), ('MUE-9806', 'ZT8 Seis', 'muestreo', 'norte');
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, barrio_capa, autor)
  select p.id, la + x.dy, lo + x.dx, x.ex, x.fu, 'BARRIO ZT8', a from tecnica.puntos p
    join (values ('MUE-9801', 0, 0, 'aproximada', 'barrio'), ('MUE-9802', 0.002, 0, 'aproximada', 'barrio'), ('MUE-9804', 0.004, 0, 'verificada', 'david'),
                 ('MUE-9805', 0.006, 0, 'aproximada', 'barrio'), ('MUE-9806', 0.008, 0, 'aproximada', 'barrio')) x(c, dy, dx, ex, fu) on x.c = p.codigo;
  update tecnica.puntos set activo = false where codigo = 'MUE-9805';
  select count(*) into v_ubic0 from tecnica.puntos_ubicacion;

  -- ===================== A. el minimapa de Muestreo (puntos_mapa) =====================
  v_r := public.geoportal_tec_puntos_mapa(op);
  perform pg_temp.reg('01.01 el operador con Muestreo recibe un GeoJSON con los puntos activos ubicados, su exactitud y la precisión exigida',
     v_r ->> 'type' = 'FeatureCollection' and (v_r ->> 'precision_max_m')::numeric = 30
     and pg_temp.mapa(op, 'MUE-9801') ->> 'exactitud' = 'aproximada' and pg_temp.mapa(op, 'MUE-9804') ->> 'exactitud' = 'verificada'
     and (select f -> 'geometry' -> 'coordinates' from jsonb_array_elements(v_r -> 'features') f where f -> 'properties' ->> 'codigo' = 'MUE-9801') = jsonb_build_array(lo, la), left(v_r::text, 300));
  perform pg_temp.reg('01.02 el punto sin ubicación va en «sin_ubicacion» y el desactivado no sale en ninguna lista',
     exists (select 1 from jsonb_array_elements(v_r -> 'sin_ubicacion') x where x ->> 'codigo' = 'MUE-9803') and pg_temp.mapa(op, 'MUE-9803') is null
     and pg_temp.mapa(op, 'MUE-9805') is null and not exists (select 1 from jsonb_array_elements(v_r -> 'sin_ubicacion') x where x ->> 'codigo' = 'MUE-9805'));
  perform pg_temp.reg('01.03 solo puntos de muestreo (ningún macromedidor ni tanque) y sin autores ni correos',
     not exists (select 1 from jsonb_array_elements(v_r -> 'features') f join tecnica.puntos p on p.codigo = f -> 'properties' ->> 'codigo' where p.tipo <> 'muestreo')
     and position('@' in v_r::text) = 0);
  perform pg_temp.reg('01.04 el supervisor de planta y el administrador también lo ven', pg_temp.mapa(sv, 'MUE-9801') is not null and pg_temp.mapa(a, 'MUE-9801') is not null);
  perform pg_temp.err('01.05 el operador sin Muestreo asignado: 42501', format('select public.geoportal_tec_puntos_mapa(%L)', osm), '42501');
  perform pg_temp.err('01.06 una persona sin Técnica: 42501', format('select public.geoportal_tec_puntos_mapa(%L)', na), '42501');
  perform pg_temp.err('01.07 sin solicitante: 28000', 'select public.geoportal_tec_puntos_mapa(null)', '28000');

  -- ===================== B. «Guardar la ubicación de este punto» (proponer) =====================
  perform pg_temp.err('02.01 precisión peor que la exigida (31 m): no se guarda y dice cuánto se necesita',
     format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, %s, %s, 31)', op, 'MUE-9801', la, lo), '22023', 'se necesita de 30 m o menos');
  perform pg_temp.err('02.02 fuera de Valledupar: no se guarda', format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, 4.6, -74.08, 5)', op, 'MUE-9801'), '22023', 'fuera de Valledupar');
  perform pg_temp.err('02.03 sin posición: no se guarda', format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, null, %s, 5)', op, 'MUE-9801', lo), '22023', 'Falta la ubicación');
  perform pg_temp.err('02.04 precisión cero o negativa: no es válida', format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, %s, %s, 0)', op, 'MUE-9801', la, lo), '22023', 'no es válida');
  perform pg_temp.err('02.05 un punto que no existe: P0002', format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, %s, %s, 5)', op, 'MUE-9899', la, lo), 'P0002');
  perform pg_temp.err('02.06 un punto que no es de muestreo (macromedidor): P0002',
     format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, %s, %s, 5)', op, (select codigo from tecnica.puntos where tipo <> 'muestreo' order by id limit 1), la, lo), 'P0002');
  perform pg_temp.err('02.07 un punto desactivado: no', format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, %s, %s, 5)', op, 'MUE-9805', la, lo), '22023', 'desactivado');
  perform pg_temp.err('02.08 un punto ya verificado: 55000', format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, %s, %s, 5)', op, 'MUE-9804', la, lo), '55000', 'ya está verificada');
  perform pg_temp.err('02.09 el operador sin Muestreo: 42501', format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, %s, %s, 5)', osm, 'MUE-9801', la, lo), '42501');
  select count(*) into v_aud from public.geoportal_auditoria where accion = 'tec_punto_ubicacion_proponer';
  v_r := public.geoportal_tec_punto_ubicacion_proponer(op, ' mue-9801 ', la + 0.0004, lo + 0.0003, 6.4);
  v_id := (v_r ->> 'propuesta_id')::bigint;
  perform pg_temp.reg('02.10 el operador propone (código con espacios y en minúsculas): queda pendiente, con la distancia a la vigente (~55 m) y su auditoría',
     v_r ->> 'estado' = 'pendiente' and not (v_r ->> 'duplicado')::boolean and (v_r ->> 'distancia_m')::numeric between 45 and 65 and (v_r ->> 'precision_m')::numeric = 6.4
     and (select autor from tecnica.punto_ubicacion_propuestas where id = v_id) = op
     and (select count(*) from public.geoportal_auditoria where accion = 'tec_punto_ubicacion_proponer') = v_aud + 1, v_r::text);
  perform pg_temp.reg('02.11 la ubicación vigente NO cambia hasta que el supervisor la apruebe', pg_temp.vig('MUE-9801') = 'aproximada|barrio|' || la || '|' || lo || '|' || a, pg_temp.vig('MUE-9801'));
  perform pg_temp.reg('02.12 en el minimapa: «en revisión», propia para el que la tomó y ajena para otro', (pg_temp.mapa(op, 'MUE-9801') ->> 'en_revision')::boolean
     and (pg_temp.mapa(op, 'MUE-9801') ->> 'propuesta_mia')::boolean and not (pg_temp.mapa(o2, 'MUE-9801') ->> 'propuesta_mia')::boolean);
  v_x := public.geoportal_tec_punto_ubicacion_proponer(op, 'MUE-9801', la + 0.0005, lo, 5);
  perform pg_temp.reg('02.13 el mismo operador otra vez (doble toque o reintento): devuelve la misma, sin otra fila', (v_x ->> 'propuesta_id')::bigint = v_id and (v_x ->> 'duplicado')::boolean
     and (select count(*) from tecnica.punto_ubicacion_propuestas p join tecnica.puntos t on t.id = p.punto_id where t.codigo = 'MUE-9801') = 1, v_x::text);
  perform pg_temp.err('02.14 otro operador sobre el mismo punto: 55000 (ya hay una en revisión)', format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, %s, %s, 5)', o2, 'MUE-9801', la, lo), '55000', 'en revisión');
  v_r := public.geoportal_tec_punto_ubicacion_proponer(o2, 'MUE-9803', la + 0.01, lo, 12);
  v_id2 := (v_r ->> 'propuesta_id')::bigint;
  perform pg_temp.reg('02.15 un punto sin ubicación también se propone (sin distancia)', v_r ->> 'estado' = 'pendiente' and v_r -> 'distancia_m' = 'null'::jsonb
     and (select ubicacion_previa_id from tecnica.punto_ubicacion_propuestas where id = v_id2) is null, v_r::text);
  -- el supervisor de planta toma una (para probar que no se aprueba a sí mismo) y una lejana (aviso «lejos»)
  v_r := public.geoportal_tec_punto_ubicacion_proponer(sv, 'MUE-9802', la + 0.002 + 0.0045, lo, 4);
  v_id3 := (v_r ->> 'propuesta_id')::bigint;
  perform pg_temp.reg('02.16 el supervisor también puede tomarla (500 m lejos de la vigente)', v_r ->> 'estado' = 'pendiente' and (v_r ->> 'distancia_m')::numeric between 480 and 520, v_r::text);
  perform pg_temp.err('02.17 las propuestas son de solo inserción (no se cambian)', format('update tecnica.punto_ubicacion_propuestas set lat = 10.5 where id = %s', v_id), '42501');
  perform pg_temp.err('02.18 ni se borran', format('delete from tecnica.punto_ubicacion_propuestas where id = %s', v_id), '42501');

  -- ===================== C. la revisión en el Dashboard PTAP =====================
  perform pg_temp.err('03.01 el operador no ve las ubicaciones por revisar: 42501', format('select public.geoportal_tec_punto_ubicaciones(%L)', op), '42501');
  perform pg_temp.err('03.02 el supervisor de distribución (sin Dashboard PTAP) tampoco: 42501', format('select public.geoportal_tec_punto_ubicaciones(%L)', sd), '42501');
  v_r := public.geoportal_tec_punto_ubicaciones(sv2);
  perform pg_temp.reg('03.03 el supervisor ve las 3 pendientes con quién la tomó, su precisión, la distancia y el aviso «lejos» (> 300 m)',
     (select count(*) from jsonb_array_elements(v_r -> 'pendientes') x where (x ->> 'propuesta_id')::bigint in (v_id, v_id2, v_id3)) = 3
     and (select x ->> 'autor' = op and x ->> 'autor_nombre' = 'ZT8 Operador de planta' and not (x ->> 'lejos')::boolean and x -> 'vigente' ->> 'exactitud' = 'aproximada'
            from jsonb_array_elements(v_r -> 'pendientes') x where (x ->> 'propuesta_id')::bigint = v_id)
     and (select (x ->> 'lejos')::boolean from jsonb_array_elements(v_r -> 'pendientes') x where (x ->> 'propuesta_id')::bigint = v_id3)
     and (select x -> 'vigente' = 'null'::jsonb from jsonb_array_elements(v_r -> 'pendientes') x where (x ->> 'propuesta_id')::bigint = v_id2)
     and (v_r ->> 'distancia_aviso_m')::numeric = 300, left(v_r::text, 400));
  perform pg_temp.reg('03.04 y la lista de puntos activos con su ubicación (el desactivado no)', (select x ->> 'exactitud' from jsonb_array_elements(v_r -> 'puntos') x where x ->> 'codigo' = 'MUE-9804') = 'verificada'
     and (select (x ->> 'en_revision')::boolean from jsonb_array_elements(v_r -> 'puntos') x where x ->> 'codigo' = 'MUE-9801')
     and not exists (select 1 from jsonb_array_elements(v_r -> 'puntos') x where x ->> 'codigo' = 'MUE-9805'));
  perform pg_temp.reg('03.05 «propia» marca la que tomó el mismo supervisor', (select (x ->> 'propia')::boolean from jsonb_array_elements(public.geoportal_tec_punto_ubicaciones(sv) -> 'pendientes') x where (x ->> 'propuesta_id')::bigint = v_id3));
  perform pg_temp.err('03.06 el operador no revisa: 42501', format($$select public.geoportal_tec_punto_ubicacion_revisar(%L, %s, 'aprobar', null)$$, op, v_id), '42501');
  perform pg_temp.err('03.07 nadie revisa la que tomó: el supervisor con la suya', format($$select public.geoportal_tec_punto_ubicacion_revisar(%L, %s, 'aprobar', null)$$, sv, v_id3), '22023', 'usted mismo');
  perform pg_temp.err('03.08 rechazar sin motivo: no', format($$select public.geoportal_tec_punto_ubicacion_revisar(%L, %s, 'rechazar', '  ')$$, sv, v_id), '22023', 'motivo del rechazo');
  perform pg_temp.err('03.09 un motivo corto al aprobar: no', format($$select public.geoportal_tec_punto_ubicacion_revisar(%L, %s, 'aprobar', 'corto')$$, sv, v_id), '22023', '10 a 1.000');
  perform pg_temp.err('03.10 una decisión que no existe: no', format($$select public.geoportal_tec_punto_ubicacion_revisar(%L, %s, 'borrar', 'Motivo suficientemente largo')$$, sv, v_id), '22023', 'aprueba o rechaza');
  perform pg_temp.err('03.11 una propuesta que no existe: P0002', format($$select public.geoportal_tec_punto_ubicacion_revisar(%L, -1, 'aprobar', null)$$, sv), 'P0002');
  select count(*) into v_aud from public.geoportal_auditoria where accion = 'tec_punto_ubicacion_aprobar';
  v_r := public.geoportal_tec_punto_ubicacion_revisar(sv, v_id, 'aprobar', null);
  perform pg_temp.reg('03.12 el supervisor aprueba: la ubicación del GPS queda vigente, verificada, con fuente gps_operador y el operador como autor (el barrio se conserva)',
     v_r ->> 'estado' = 'aprobada' and pg_temp.vig('MUE-9801') = 'verificada|gps_operador|' || round(la + 0.0004, 6) || '|' || round(lo + 0.0003, 6) || '|' || op
     and (select barrio_capa from tecnica.puntos_ubicacion where id = (v_r ->> 'ubicacion_id')::bigint) = 'BARRIO ZT8'
     and (select autor from tecnica.punto_ubicacion_revisiones where propuesta_id = v_id) = sv
     and (select count(*) from public.geoportal_auditoria where accion = 'tec_punto_ubicacion_aprobar') = v_aud + 1, v_r::text || ' · ' || coalesce(pg_temp.vig('MUE-9801'), '∅'));
  perform pg_temp.reg('03.13 la ubicación anterior se queda (solo inserción): el punto tiene 2 filas de ubicación', (select count(*) from tecnica.puntos_ubicacion u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-9801') = 2);
  perform pg_temp.reg('03.14 en el minimapa ya sale verificada y sin «en revisión»', pg_temp.mapa(op, 'MUE-9801') ->> 'exactitud' = 'verificada' and not (pg_temp.mapa(op, 'MUE-9801') ->> 'en_revision')::boolean);
  perform pg_temp.err('03.15 revisarla otra vez: 55000 (dice quién la aprobó)', format($$select public.geoportal_tec_punto_ubicacion_revisar(%L, %s, 'rechazar', 'Ya no debería poderse')$$, sv2, v_id), '55000', 'ya fue aprobada por ' || sv);
  perform pg_temp.err('03.16 y ya no se puede proponer otra: está verificada', format('select public.geoportal_tec_punto_ubicacion_proponer(%L, %L, %s, %s, 5)', o2, 'MUE-9801', la, lo), '55000', 'ya está verificada');
  v_r := public.geoportal_tec_punto_ubicacion_revisar(sv2, v_id3, 'rechazar', 'El punto de toma está en la otra esquina del parque');
  perform pg_temp.reg('03.17 otro supervisor rechaza la lejana con motivo: la vigente no cambia', v_r ->> 'estado' = 'rechazada' and v_r -> 'ubicacion_id' = 'null'::jsonb
     and pg_temp.vig('MUE-9802') like 'aproximada|barrio|%' and (select motivo from tecnica.punto_ubicacion_revisiones where propuesta_id = v_id3) = 'El punto de toma está en la otra esquina del parque');
  v_x := public.geoportal_tec_punto_ubicacion_proponer(sv, 'MUE-9802', la + 0.0021, lo, 5);
  perform pg_temp.reg('03.18 después del rechazo se puede proponer de nuevo (propuesta nueva, pendiente)', (v_x ->> 'propuesta_id')::bigint > v_id3 and v_x ->> 'estado' = 'pendiente' and not (v_x ->> 'duplicado')::boolean);
  v_r := public.geoportal_tec_punto_ubicacion_revisar(a, v_id2, 'aprobar', 'Revisado en el mapa con el operador');
  perform pg_temp.reg('03.19 el administrador aprueba la de un punto que no tenía ubicación (con motivo opcional)', v_r ->> 'estado' = 'aprobada' and pg_temp.vig('MUE-9803') like 'verificada|gps_operador|%|' || o2
     and (select motivo from tecnica.punto_ubicacion_revisiones where propuesta_id = v_id2) = 'Revisado en el mapa con el operador');
  v_r := public.geoportal_tec_punto_ubicaciones(sv2);
  perform pg_temp.reg('03.20 «revisadas» trae las 3 decisiones con quién la tomó y quién la revisó; en pendientes queda solo la nueva del MUE-9802',
     (select count(*) from jsonb_array_elements(v_r -> 'revisadas') x where (x ->> 'propuesta_id')::bigint in (v_id, v_id2, v_id3)) = 3
     and (select x ->> 'decision' || '|' || (x ->> 'autor') || '|' || (x ->> 'revisor') from jsonb_array_elements(v_r -> 'revisadas') x where (x ->> 'propuesta_id')::bigint = v_id3) = 'rechazada|' || sv || '|' || sv2
     and (select count(*) from jsonb_array_elements(v_r -> 'pendientes') x join tecnica.puntos p on p.codigo = x ->> 'punto' where p.codigo like 'MUE-98%') = 1);
  -- un punto que se desactiva con su propuesta pendiente: no se aprueba, se puede rechazar
  v_x := public.geoportal_tec_punto_ubicacion_proponer(op, 'MUE-9806', la + 0.0081, lo, 5);
  update tecnica.puntos set activo = false where codigo = 'MUE-9806';
  perform pg_temp.err('03.21 aprobar la de un punto desactivado: no', format($$select public.geoportal_tec_punto_ubicacion_revisar(%L, %s, 'aprobar', null)$$, sv, (v_x ->> 'propuesta_id')::bigint), '22023', 'desactivado');
  v_r := public.geoportal_tec_punto_ubicacion_revisar(sv, (v_x ->> 'propuesta_id')::bigint, 'rechazar', 'El punto se desactivó en la última carga');
  perform pg_temp.reg('03.22 y sí se puede rechazar', v_r ->> 'estado' = 'rechazada');
  update tecnica.puntos set activo = true where codigo = 'MUE-9806';
  perform pg_temp.err('03.23 las revisiones son de solo inserción', format('update tecnica.punto_ubicacion_revisiones set decision = %L where propuesta_id = %s', 'rechazar', v_id), '42501');
  perform pg_temp.reg('03.24 nada se borró: las ubicaciones solo crecieron (2 aprobadas)', (select count(*) from tecnica.puntos_ubicacion) = v_ubic0 + 2);
  perform pg_temp.reg('03.25 los parámetros nuevos existen con su rango', (select count(*) from redes.parametros where (clave, valor, minimo, maximo) in (('mue_gps_precision_max_m', 30, 5, 100), ('mue_gps_distancia_aviso_m', 300, 20, 5000))) = 2);

  -- ===================== D. una recarga de la capa MUE no pisa una ubicación verificada con una aproximada =====================
  -- archivo con todos los puntos activos (para no desactivar ninguno), donde MUE-9801 (verificada por GPS) y MUE-9804 (verificada por David) vienen aproximadas
  -- y MUE-9806 (aproximada) viene aproximada en otro lugar
  v_c := pg_temp.cargar_mue(a, 'zt8-mue-1', (select jsonb_agg(pg_temp.mue(rn::integer, codigo,
            case codigo when 'MUE-9801' then la + 0.003 when 'MUE-9804' then la + 0.0042 when 'MUE-9806' then la + 0.0085 else coalesce(u.lat, la) end,
            case codigo when 'MUE-9801' then lo when 'MUE-9804' then lo when 'MUE-9806' then lo else coalesce(u.lon, lo) end,
            jsonb_build_object('exactitud', case when codigo in ('MUE-9801', 'MUE-9804', 'MUE-9806') then 'aproximada' else coalesce(u.exactitud, 'aproximada') end,
                               'fuente', case when coalesce(u.exactitud, '') = 'verificada' and codigo not in ('MUE-9801', 'MUE-9804') then 'david' else 'barrio' end)))
          from (select p.codigo, row_number() over (order by p.codigo) rn, u.lat, u.lon, u.exactitud from tecnica.puntos p left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
                 where p.tipo = 'muestreo' and p.activo) u));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('04.01 el resumen marca «conserva_verificada» las dos verificadas que el archivo trae aproximadas, y la aproximada sí cambia',
     (select x ->> 'accion' from jsonb_array_elements(v_r -> 'puntos') x where x ->> 'codigo' = 'MUE-9801') = 'conserva_verificada'
     and (select x ->> 'accion' from jsonb_array_elements(v_r -> 'puntos') x where x ->> 'codigo' = 'MUE-9804') = 'conserva_verificada'
     and (select x ->> 'accion' from jsonb_array_elements(v_r -> 'puntos') x where x ->> 'codigo' = 'MUE-9806') = 'ubicacion'
     and (v_r ->> 'lista_para_publicar')::boolean and (v_r -> 'frente_a_vigente' ->> 'conserva_verificada')::integer >= 2, left((v_r -> 'frente_a_vigente')::text || ' ' || (v_r -> 'bloqueos')::text, 400));
  v_t := pg_temp.vig('MUE-9801');
  v_x := public.geoportal_redes_carga_publicar(a, v_c, 'Recarga de prueba del Corte 5b con dos verificadas');
  perform pg_temp.reg('04.02 al publicar, las verificadas siguen igual y la aproximada toma su lugar nuevo', pg_temp.vig('MUE-9801') = v_t and pg_temp.vig('MUE-9804') like 'verificada|david|%'
     and pg_temp.vig('MUE-9806') like 'aproximada|barrio|' || round(la + 0.0085, 6) || '|%', v_x::text);
  v_c := pg_temp.cargar_mue(a, 'zt8-mue-2', (select jsonb_agg(pg_temp.mue(rn::integer, codigo, case when codigo = 'MUE-9804' then la + 0.0043 else u.lat end, u.lon,
            jsonb_build_object('exactitud', case when codigo = 'MUE-9804' then 'verificada' else u.exactitud end, 'fuente', case when u.exactitud = 'verificada' then 'david' else 'barrio' end)))
          from (select p.codigo, row_number() over (order by p.codigo) rn, u.lat, u.lon, u.exactitud from tecnica.puntos p join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
                 where p.tipo = 'muestreo' and p.activo) u));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('04.03 un archivo con la ubicación VERIFICADA sí cambia una verificada (es una corrección explícita)',
     (select x ->> 'accion' from jsonb_array_elements(v_r -> 'puntos') x where x ->> 'codigo' = 'MUE-9804') = 'ubicacion', left((v_r -> 'frente_a_vigente')::text, 300));

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 5b (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
