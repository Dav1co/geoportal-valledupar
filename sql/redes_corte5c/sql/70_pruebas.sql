-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 25, 26 y 40, en la misma transacción.
-- Como las de los cortes anteriores: corre después de la carga real y de los cortes publicados; NO supone códigos ni conteos de la base. Arma sus personas
-- (prueba.redes9.*), sus puntos de muestreo (MUE-97nn) y sus activos en las capas NUEVAS del 5c (que nacen vacías en esta misma transacción).
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 5c … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.fila(p_orden integer, p_wkt text, p_atributos jsonb) returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', p_wkt, 'atributos', p_atributos) $$;
-- abre una carga desde la pantalla (RPC nueva) y le pasa un solo lote
create function pg_temp.cargar(p_admin text, p_capa text, p_huella text, p_llave text, p_filas jsonb, p_masiva text default null, p_srid integer default 4326) returns bigint language plpgsql as $$
declare v_c bigint := (public.geoportal_redes_cargue_iniciar(p_admin, p_capa, pg_temp.sha(p_huella), 'geojson', p_srid, p_llave, jsonb_array_length(p_filas), null, p_masiva) ->> 'carga_id')::bigint;
begin
  for i in 0 .. (jsonb_array_length(p_filas) - 1) / 200 loop      -- lotes de 200 filas, como la pantalla
    perform public.geoportal_redes_carga_lote(p_admin, v_c, (select jsonb_agg(e order by k) from jsonb_array_elements(p_filas) with ordinality x(e, k) where k > i * 200 and k <= (i + 1) * 200));
  end loop;
  return v_c;
end $$;
create function pg_temp.vig(p_codigo text) returns text language sql as $$
  select u.exactitud || '|' || u.fuente || '|' || u.lat || '|' || u.lon || '|' || u.autor from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = p_codigo $$;
create function pg_temp.lin(x0 numeric, y0 numeric, dy numeric default 0) returns text language sql as $$
  select format('LINESTRING(%s %s, %s %s, %s %s)', x0, y0 + dy, x0 + 0.0006, y0 + dy, x0 + 0.0012, y0 + dy + 0.0003) $$;

do $prueba$
declare
  a text := 'prueba.redes9.adm@emdupar.gov.co'; sv text := 'prueba.redes9.sup@emdupar.gov.co'; sv2 text := 'prueba.redes9.sup2@emdupar.gov.co';
  op text := 'prueba.redes9.op@emdupar.gov.co'; sd text := 'prueba.redes9.dist@emdupar.gov.co'; na text := 'prueba.redes9.nada@emdupar.gov.co';
  la numeric := 10.420000; lo numeric := -73.300000;      -- un origen dentro de Valledupar, lejos de los datos reales
  v_r jsonb; v_x jsonb; v_c bigint; v_c2 bigint; v_t text; v_s1 text; v_s2 text; v_a1 text; v_a2 text; v_n integer; v_id bigint; v_u0 integer; v_m text;
  v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values
    (sv, 'ZT9 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos'), (sv2, 'ZT9 Otro supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT9 Operador', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT9 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT9 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'muestreo', a), (sv, 'asignar_formulario', 'muestreo', a);

  -- ===================== A. Esquema =====================
  perform pg_temp.reg('01.01 las 11 capas nuevas del lector genérico están activas y vacías, y acometidas sigue lista',
     (select count(*) from redes.capas where activa and fuente = 'carga' and prefijo is not null and columna_llave is null) = 12
     and not exists (select 1 from redes.cargas where capa_codigo in ('captaciones', 'aduccion', 'sensores', 'sectores', 'sumideros')));
  perform pg_temp.reg('01.02 el parámetro del cruce por geometría (2 m, de 0,1 a 50)', (select valor || '|' || minimo || '|' || maximo from redes.parametros where clave = 'cruce_geometria_tol_m') = '2|0.1|50');

  -- ===================== B. Reproyección =====================
  select ST_Distance(g.geom::geography, ST_SetSRID(ST_MakePoint(-73.25, 10.46), 4326)::geography) into v_x from redes.f_geo_desde_wkt('POINT(4972651.402 2713870.093)', 9377) g;
  perform pg_temp.reg('02.01 un punto en EPSG 9377 (Origen Nacional) cae a menos de 1 m de su lugar en WGS 84', (v_x #>> '{}')::numeric < 1, v_x::text);
  perform pg_temp.reg('02.02 un MULTIPOINT de un solo punto llega como POINT',
     (select GeometryType(geom) from redes.f_geo_desde_wkt('MULTIPOINT((-73.25 10.46))', 4326)) = 'POINT');
  perform pg_temp.reg('02.03 EPSG 3116 (MAGNA Bogotá) sigue igual, y fuera de la caja de Valledupar es error',
     (select ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint(-73.25, 10.46), 4326)::geography) < 1
        from redes.f_geo_desde_wkt((select ST_AsText(ST_Transform(ST_SetSRID(ST_MakePoint(-73.25, 10.46), 4326), 3116))), 3116))
     and (select error from redes.f_geo_desde_wkt('POINT(-74.08 4.60)', 4326)) like 'Fuera de la caja%');

  -- ===================== C. Abrir una carga desde la pantalla =====================
  perform pg_temp.err('03.01 el supervisor de distribución no abre cargas', format($$select public.geoportal_redes_cargue_iniciar(%L, 'sensores', %L, 'geojson', 4326, 'ID', 1)$$, sd, pg_temp.sha('x')), '42501');
  perform pg_temp.err('03.02 un sistema de coordenadas que no es de Colombia se rechaza', format($$select public.geoportal_redes_cargue_iniciar(%L, 'sensores', %L, 'geojson', 32618, 'ID', 1)$$, a, pg_temp.sha('x')), null, 'sistema de coordenadas');
  perform pg_temp.err('03.03 un formato que la capa no acepta (CSV para una capa de líneas)', format($$select public.geoportal_redes_cargue_iniciar(%L, 'aduccion', %L, 'csv', 4326, 'ID', 1)$$, a, pg_temp.sha('x')), null, 'no se carga con csv');
  perform pg_temp.err('03.04 el acueducto solo con su llave del modelo (ID, N-5)', format($$select public.geoportal_redes_cargue_iniciar(%L, 'acueducto', %L, 'shp', 4326, 'LABEL', 1)$$, a, pg_temp.sha('x')), null, 'columna llave ID');
  perform pg_temp.err('03.05 «sin columna llave» no se admite en las capas del modelo', format($$select public.geoportal_redes_cargue_iniciar(%L, 'alc_pozos', %L, 'shp', 4326, '(geometria)', 1)$$, a, pg_temp.sha('x')), null, 'columna llave LABEL');
  perform pg_temp.err('03.06 un identificador de carga masiva mal formado', format($$select public.geoportal_redes_cargue_iniciar(%L, 'sensores', %L, 'geojson', 4326, 'ID', 1, null, 'no-es-uuid')$$, a, pg_temp.sha('x')), null, 'masiva');
  v_r := public.geoportal_redes_cargue_iniciar(a, 'sensores', pg_temp.sha('zt9-sen-1'), 'geojson', 4326, 'ID', 3, 'ZT9 primera', '0b1e7d1c-1111-4222-8333-944455556666');
  v_c := (v_r ->> 'carga_id')::bigint;
  perform pg_temp.reg('03.07 abre la carga, con la marca de la carga masiva y la auditoría', (v_r ->> 'nueva')::boolean
     and (select masiva_id::text from redes.cargas where id = v_c) = '0b1e7d1c-1111-4222-8333-944455556666'
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_carga_iniciar' and referencia = v_c::text and detalle ->> 'desde' = 'pantalla'), v_r::text);
  v_r := public.geoportal_redes_cargue_iniciar(a, 'sensores', pg_temp.sha('zt9-sen-1'), 'geojson', 4326, 'ID', 3, 'ZT9 primera', '0b1e7d1c-1111-4222-8333-944455556666');
  perform pg_temp.reg('03.08 el mismo archivo otra vez retoma la misma carga (para seguir una subida cortada)', not (v_r ->> 'nueva')::boolean and (v_r ->> 'carga_id')::bigint = v_c);
  v_id := (public.geoportal_redes_carga_iniciar(a, 'scada', pg_temp.sha('zt9-sca'), 'geojson', 4326, 'ID', 1) ->> 'carga_id')::bigint;
  perform pg_temp.reg('03.09 una carga por psql (RPC del 1a) no queda marcada como masiva', (select masiva_id is null from redes.cargas where id = v_id));

  -- ===================== D. Lector genérico (sensores, puntos con llave ID) =====================
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    pg_temp.fila(1, format('POINT(%s %s)', lo, la), '{"ID": "S-1", "Nombre": "ZT9 Sensor uno", "ESTADO": "Existente", "Clase": "radar", "MARCA": "Acme"}'),
    pg_temp.fila(2, format('MULTIPOINT((%s %s))', lo + 0.001, la), '{"ID": "S-2", "NOMBRE": "ZT9 Sensor dos", "estado": "En operación"}'),
    pg_temp.fila(3, format('POINT(%s %s)', lo + 0.002, la), '{"ID": "S-3", "NOMBRE": "ZT9 Sensor tres", "PROFUNDIDAD": "1.5", "CAPACIDAD": -3}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('04.01 el resumen del lector genérico: 3 nuevos de tipo SEN, lista para publicar', (v_r -> 'por_prefijo' ->> 'SEN')::integer = 3
     and (v_r -> 'frente_a_vigente' ->> 'nuevo')::integer = 3 and (v_r ->> 'lista_para_publicar')::boolean, left(v_r::text, 400));
  v_x := public.geoportal_redes_carga_publicar(a, v_c, 'ZT9 primera carga de sensores');
  select codigo into v_s1 from redes.v_activo_vigente where capa_codigo = 'sensores' and llave_capa = 'S-1';
  select codigo into v_s2 from redes.v_activo_vigente where capa_codigo = 'sensores' and llave_capa = 'S-3';
  perform pg_temp.reg('04.02 al publicar: 3 activos SEN de la capa sensores, con su código, versión 1 de la capa', (v_x ->> 'nuevos')::integer = 3 and (v_x ->> 'version_capa')::integer = 1
     and v_s1 like 'SEN-%' and (select count(*) from redes.v_activo_vigente where capa_codigo = 'sensores' and not retirado) = 3, v_x::text);
  perform pg_temp.reg('04.03 los campos: nombre y estado reconocidos sin importar mayúsculas; la clase que no existe y lo demás van a los atributos',
     (select nombre || '|' || estado_codigo || '|' || coalesce(clase, '-') || '|' || (atributos ->> 'clase_capa') || '|' || (atributos -> 'modelo' ->> 'MARCA')
        from redes.v_activo_vigente where codigo = v_s1) = 'ZT9 Sensor uno|en_operacion|-|radar|Acme'
     and (select atributos ->> 'estado_capa' from redes.v_activo_vigente where codigo = v_s1) = 'Existente'
     and (select estado_codigo from redes.v_activo_vigente where capa_codigo = 'sensores' and llave_capa = 'S-2') = 'en_operacion'
     and (select GeometryType(geom) from redes.v_activo_vigente where capa_codigo = 'sensores' and llave_capa = 'S-2') = 'POINT');
  perform pg_temp.reg('04.04 los números: la profundidad de texto se lee y la capacidad negativa no entra a la ficha',
     (select profundidad_m = 1.5 and capacidad is null from redes.v_activo_vigente where codigo = v_s2));
  v_r := public.geoportal_redes_cargue_capas(sd);
  perform pg_temp.reg('04.05 el Cargue de capas (supervisor, solo lectura): sensores en la versión 1, «al día», 3 vigentes; sin cargar las demás nuevas',
     not (v_r ->> 'puede_cargar')::boolean
     and (select x ->> 'estado' || '|' || (x ->> 'version') || '|' || (x ->> 'vigentes') || '|' || (x ->> 'lector') from jsonb_array_elements(v_r -> 'capas') x where x ->> 'codigo' = 'sensores') = 'al_dia|1|3|generico'
     and (select x ->> 'estado' from jsonb_array_elements(v_r -> 'capas') x where x ->> 'codigo' = 'captaciones') = 'sin_cargar'
     and (select x ->> 'lector' from jsonb_array_elements(v_r -> 'capas') x where x ->> 'codigo' = 'acueducto') = 'modelo'
     and (select x ->> 'estado' from jsonb_array_elements(v_r -> 'capas') x where x ->> 'codigo' = 'acueducto_nodos') = 'derivada');
  perform pg_temp.reg('04.06 el administrador puede cargar; el operador no ve el Cargue', (public.geoportal_redes_cargue_capas(a) ->> 'puede_cargar')::boolean);
  perform pg_temp.err('04.07 el operador no ve el Cargue de capas', format($$select public.geoportal_redes_cargue_capas(%L)$$, op), '42501');
  -- una línea en una capa de puntos
  v_c := pg_temp.cargar(a, 'sensores', 'zt9-sen-linea', 'ID', jsonb_build_array(pg_temp.fila(1, pg_temp.lin(lo, la), '{"ID": "S-9"}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('04.08 una geometría que no es la del tipo (línea en una capa de puntos) bloquea la publicación',
     not (v_r ->> 'lista_para_publicar')::boolean and exists (select 1 from jsonb_array_elements_text(v_r -> 'bloqueos') b where b like '%geometría que no es la del tipo%'), left((v_r -> 'bloqueos')::text, 300));
  perform public.geoportal_redes_carga_anular(a, v_c, 'ZT9 anulada a propósito');
  v_c := pg_temp.cargar(a, 'sensores', 'zt9-sen-rep', 'ID', jsonb_build_array(pg_temp.fila(1, format('POINT(%s %s)', lo, la), '{"ID": "S-1"}'), pg_temp.fila(2, format('POINT(%s %s)', lo, la + 0.001), '{"ID": "S-1"}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('04.09 las llaves repetidas bloquean y el aviso dice cómo seguir (otra llave o «sin columna llave»)',
     exists (select 1 from jsonb_array_elements_text(v_r -> 'bloqueos') b where b like '%llaves repetidas%sin columna llave%'), left((v_r -> 'bloqueos')::text, 300));
  perform public.geoportal_redes_carga_anular(a, v_c, 'ZT9 anulada a propósito');

  -- ===================== E. «Devolver este campo a la capa» (§31.1) =====================
  perform public.geoportal_redes_ficha_editar(a, v_s1, '{"nombre": "ZT9 Nombre de la ficha"}', 'ZT9 lo corrigió la cuadrilla en campo');
  -- S-3 vuelve con los mismos valores escritos de otra forma (la profundidad 1.50 como número, antes «1.5» como texto): debe salir «igual», no «cambiado»
  v_c := pg_temp.cargar(a, 'sensores', 'zt9-sen-2', 'ID', jsonb_build_array(
    pg_temp.fila(1, format('POINT(%s %s)', lo, la), '{"ID": "S-1", "Nombre": "ZT9 Nombre del modelo", "ESTADO": "Existente", "Clase": "radar", "MARCA": "Acme"}'),
    pg_temp.fila(2, format('POINT(%s %s)', lo + 0.001, la), '{"ID": "S-2", "NOMBRE": "ZT9 Sensor dos", "estado": "En operación"}'),
    pg_temp.fila(3, format('POINT(%s %s)', lo + 0.002, la), '{"ID": "S-3", "NOMBRE": "ZT9 Sensor tres", "PROFUNDIDAD": 1.50, "CAPACIDAD": -3}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('05.01 el choque sale en el resumen: nombre de la ficha contra el de la capa (gana la ficha)',
     exists (select 1 from jsonb_array_elements(v_r -> 'choques') x where x ->> 'codigo' = v_s1 and x ->> 'campo' = 'nombre' and x ->> 'ficha' = 'ZT9 Nombre de la ficha' and x ->> 'capa' = 'ZT9 Nombre del modelo'),
     left((v_r -> 'choques')::text, 300));
  perform pg_temp.reg('05.01b los mismos valores escritos de otra forma (1.50 y 1.5) salen «igual», y S-1 también (gana la ficha): ninguno cambiado',
     (v_r -> 'frente_a_vigente' ->> 'igual')::integer = 3 and (v_r -> 'frente_a_vigente' ->> 'cambiado') is null, (v_r -> 'frente_a_vigente')::text);
  perform pg_temp.err('05.02 el supervisor de distribución no devuelve campos', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'nombre', 'ZT9 Técnica corrigió el modelo')$$, sd, v_c, v_s1), '42501');
  perform pg_temp.err('05.03 un campo que no se editó en la ficha ya lo manda la capa', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'estado_codigo', 'ZT9 Técnica corrigió el modelo')$$, a, v_c, v_s1), '55000', 'no está editado en la ficha');
  perform pg_temp.err('05.04 sin motivo no se devuelve', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'nombre', 'corto')$$, a, v_c, v_s1), null, 'motivo');
  perform pg_temp.err('05.05 un campo que no existe se rechaza', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'geom', 'ZT9 Técnica corrigió el modelo')$$, a, v_c, v_s1), '55000');
  v_x := public.geoportal_redes_carga_devolver_campo(a, v_c, v_s1, 'nombre', 'ZT9 Técnica corrigió el modelo');
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('05.06 devuelto: queda en el historial con el valor de la ficha, y al pedir el resumen otra vez ya no hay choque y el activo sale «cambiado»',
     (v_x ->> 'valor_ficha') = 'ZT9 Nombre de la ficha' and (select count(*) from redes.ficha_campo_devoluciones d join redes.activos x on x.id = d.activo_id where x.codigo = v_s1) = 1
     and not exists (select 1 from jsonb_array_elements(v_r -> 'choques') x where x ->> 'codigo' = v_s1) and (v_r -> 'frente_a_vigente' ->> 'cambiado')::integer = 1
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_ficha_campo_devolver' and referencia = v_s1), left(v_r::text, 300));
  perform pg_temp.reg('05.07 la ficha no cambia hasta publicar', (select nombre from redes.v_activo_vigente where codigo = v_s1) = 'ZT9 Nombre de la ficha');
  perform pg_temp.err('05.08 devolverlo dos veces: ya lo manda la capa', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'nombre', 'ZT9 Técnica corrigió el modelo')$$, a, v_c, v_s1), '55000');
  perform public.geoportal_redes_carga_publicar(a, v_c, 'ZT9 segunda carga de sensores');
  perform pg_temp.reg('05.09 al publicar, el nombre es el de la capa; los demás campos de la ficha siguen igual',
     (select nombre from redes.v_activo_vigente where codigo = v_s1) = 'ZT9 Nombre del modelo');
  perform pg_temp.err('05.10 desde una carga ya publicada no se devuelve', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'nombre', 'ZT9 Técnica corrigió el modelo')$$, a, v_c, v_s1), '55000', 'publicada');
  perform public.geoportal_redes_ficha_editar(a, v_s1, '{"nombre": "ZT9 Otra vez en la ficha"}', 'ZT9 se volvió a corregir en campo');
  v_c := pg_temp.cargar(a, 'sensores', 'zt9-sen-3', 'ID', jsonb_build_array(
    pg_temp.fila(1, format('POINT(%s %s)', lo, la), '{"ID": "S-1", "Nombre": "ZT9 Nombre del modelo", "ESTADO": "Existente", "Clase": "radar", "MARCA": "Acme"}'),
    pg_temp.fila(2, format('POINT(%s %s)', lo + 0.001, la), '{"ID": "S-2", "NOMBRE": "ZT9 Sensor dos", "estado": "En operación"}'),
    pg_temp.fila(3, format('POINT(%s %s)', lo + 0.002, la), '{"ID": "S-3", "NOMBRE": "ZT9 Sensor tres", "PROFUNDIDAD": "1.5", "CAPACIDAD": -3}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('05.11 si se vuelve a editar en la ficha, el campo es otra vez de la ficha (el choque vuelve)',
     exists (select 1 from jsonb_array_elements(v_r -> 'choques') x where x ->> 'codigo' = v_s1 and x ->> 'campo' = 'nombre' and x ->> 'ficha' = 'ZT9 Otra vez en la ficha'), left((v_r -> 'choques')::text, 300));
  perform public.geoportal_redes_carga_anular(a, v_c, 'ZT9 anulada a propósito');
  -- un activo de otra capa
  v_c := pg_temp.cargar(a, 'sumideros', 'zt9-sum-0', 'ID', jsonb_build_array(pg_temp.fila(1, format('POINT(%s %s)', lo, la + 0.01), '{"ID": "M-1"}')));
  perform pg_temp.err('05.12 un activo de otra capa no se devuelve desde esta carga', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'nombre', 'ZT9 Técnica corrigió el modelo')$$, a, v_c, v_s1), null, 'no es de la capa');

  -- ===================== F. Vista previa de una carga abierta =====================
  perform public.geoportal_redes_carga_anular(a, v_c, 'ZT9 anulada a propósito');
  v_c := pg_temp.cargar(a, 'sumideros', 'zt9-sum-1', 'ID', (select jsonb_agg(pg_temp.fila(g, format('POINT(%s %s)', lo + g * 0.00001, la + 0.01), jsonb_build_object('ID', 'M-' || g))) from generate_series(1, 450) g)
                                                          || jsonb_build_array(pg_temp.fila(451, 'POINT(-74.08 4.60)', '{"ID": "M-fuera"}')));
  v_r := public.geoportal_redes_carga_muestra(a, v_c);
  perform pg_temp.reg('06.01 la vista previa: la caja, la fila fuera de Valledupar como error y una muestra de 400 geometrías o menos repartida en el archivo',
     (v_r ->> 'recibidas')::integer = 451 and (v_r ->> 'con_error')::integer = 1 and (v_r -> 'errores' -> 0 ->> 'llave') = 'M-fuera'
     and jsonb_array_length(v_r -> 'muestra' -> 'features') between 200 and 400 and jsonb_array_length(v_r -> 'caja') = 4
     and (v_r -> 'muestra' -> 'features' -> -1 -> 'properties' ->> 'orden')::integer > 400, left(v_r::text, 300));
  perform pg_temp.err('06.02 el supervisor no ve la vista previa (el staging es del administrador)', format($$select public.geoportal_redes_carga_muestra(%L, %s)$$, sd, v_c), '42501');
  perform public.geoportal_redes_carga_anular(a, v_c, 'ZT9 anulada a propósito');
  perform pg_temp.err('06.03 una carga anulada ya no tiene vista previa', format($$select public.geoportal_redes_carga_muestra(%L, %s)$$, a, v_c), '55000');

  -- ===================== G. Cruce por geometría (D-4): aducción sin columna llave =====================
  v_c := pg_temp.cargar(a, 'aduccion', 'zt9-adu-1', '(geometria)', jsonb_build_array(
    pg_temp.fila(1, pg_temp.lin(lo, la + 0.02), '{"MATERIAL": "PVC", "DIAMETRO": 200}'), pg_temp.fila(2, pg_temp.lin(lo, la + 0.03), '{"MATERIAL": "PVC", "DIAMETRO": 250}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('07.01 sin columna llave: las filas sin llave no bloquean y el cruce dice 0 cruzados y 2 sin par (nuevos)', (v_r ->> 'lista_para_publicar')::boolean
     and (v_r -> 'detalle' -> 'cruce_por_geometria' ->> 'cruzados')::integer = 0 and (v_r -> 'detalle' -> 'cruce_por_geometria' ->> 'sin_par_nuevos')::integer = 2, left(v_r::text, 400));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'ZT9 primera carga de aducción');
  select codigo into v_a1 from redes.v_activo_vigente where capa_codigo = 'aduccion' and diametro_mm = 200;
  select codigo into v_a2 from redes.v_activo_vigente where capa_codigo = 'aduccion' and diametro_mm = 250;
  perform pg_temp.reg('07.02 publicados con su llave propia (G<carga>-<orden>), su material y su longitud', v_a1 like 'ADU-%' and v_a2 like 'ADU-%'
     and (select llave_capa from redes.v_activo_vigente where codigo = v_a1) = 'G' || v_c || '-1'
     and (select material_codigo = 'PVC' and longitud_m > 100 from redes.v_activo_vigente where codigo = v_a1));
  v_c2 := v_c;
  v_c := pg_temp.cargar(a, 'aduccion', 'zt9-adu-2', '(geometria)', jsonb_build_array(
    pg_temp.fila(1, pg_temp.lin(lo, la + 0.02, 0.0000045), '{"MATERIAL": "PVC", "DIAMETRO": 200, "NOTA": "medio metro al norte"}'),
    pg_temp.fila(2, pg_temp.lin(lo, la + 0.03, 0.00027), '{"MATERIAL": "PVC", "DIAMETRO": 250}'),
    pg_temp.fila(3, pg_temp.lin(lo, la + 0.04), '{"MATERIAL": "AC", "DIAMETRO": 300}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('07.03 recarga: la línea movida 0,5 m se cruza (cambiada); la movida 30 m y la nueva salen nuevas, y la vieja de 30 m se retira',
     (v_r -> 'detalle' -> 'cruce_por_geometria' ->> 'cruzados')::integer = 1 and (v_r -> 'detalle' -> 'cruce_por_geometria' ->> 'sin_par_nuevos')::integer = 2
     and (v_r -> 'frente_a_vigente' ->> 'cambiado')::integer = 1 and (v_r -> 'frente_a_vigente' ->> 'nuevo')::integer = 2 and (v_r ->> 'retirados')::integer = 1, left(v_r::text, 400));
  v_x := public.geoportal_redes_carga_publicar(a, v_c, 'ZT9 segunda carga de aducción');
  perform pg_temp.reg('07.04 al publicar: el activo cruzado conserva su código (versión 2); el de 30 m queda retirado con motivo',
     (select version from redes.v_activo_vigente where codigo = v_a1) = 2 and (select retirado from redes.v_activo_vigente where codigo = v_a2)
     and (v_x ->> 'nuevos')::integer = 2 and (v_x ->> 'retirados')::integer = 1
     and exists (select 1 from redes.activo_eventos e join redes.activos x on x.id = e.activo_id where x.codigo = v_a2 and e.tipo = 'retirar' and e.motivo like 'No vino en la carga%'), v_x::text);
  v_c := pg_temp.cargar(a, 'aduccion', 'zt9-adu-3', '(geometria)', jsonb_build_array(
    pg_temp.fila(1, pg_temp.lin(lo, la + 0.02, 0.0000045), '{"MATERIAL": "PVC", "DIAMETRO": 200, "NOTA": "medio metro al norte"}'),
    pg_temp.fila(2, pg_temp.lin(lo, la + 0.03, 0.00027), '{"MATERIAL": "PVC", "DIAMETRO": 250}'),
    pg_temp.fila(3, pg_temp.lin(lo, la + 0.04), '{"MATERIAL": "AC", "DIAMETRO": 300}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('07.05 el mismo archivo otra vez: los 3 se cruzan y quedan iguales; nada se retira',
     (v_r -> 'detalle' -> 'cruce_por_geometria' ->> 'cruzados')::integer = 3 and (v_r -> 'frente_a_vigente' ->> 'igual')::integer = 3 and (v_r ->> 'retirados')::integer = 0, left(v_r::text, 400));
  perform public.geoportal_redes_carga_anular(a, v_c, 'ZT9 anulada a propósito');
  -- puntos: dos vigentes a 1 m entre sí; el archivo los trae 0,3 m corridos → cada uno con su par (uno a uno)
  v_c := pg_temp.cargar(a, 'captaciones', 'zt9-cap-1', '(geometria)', jsonb_build_array(
    pg_temp.fila(1, format('POINT(%s %s)', lo, la + 0.05), '{"NOMBRE": "ZT9 Bocatoma A"}'), pg_temp.fila(2, format('POINT(%s %s)', lo + 0.000009, la + 0.05), '{"NOMBRE": "ZT9 Bocatoma B"}')));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'ZT9 primera carga de captaciones');
  v_c := pg_temp.cargar(a, 'captaciones', 'zt9-cap-2', '(geometria)', jsonb_build_array(
    pg_temp.fila(1, format('POINT(%s %s)', lo + 0.000003, la + 0.05), '{"NOMBRE": "ZT9 Bocatoma A"}'), pg_temp.fila(2, format('POINT(%s %s)', lo + 0.000012, la + 0.05), '{"NOMBRE": "ZT9 Bocatoma B"}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_c);
  perform pg_temp.reg('07.06 puntos cercanos entre sí: cada uno se cruza con el suyo (el más cercano de los dos lados), sin nuevos ni retiros',
     (v_r -> 'detalle' -> 'cruce_por_geometria' ->> 'cruzados')::integer = 2 and (v_r -> 'frente_a_vigente' ->> 'cambiado')::integer = 2 and (v_r ->> 'retirados')::integer = 0, left(v_r::text, 400));
  perform public.geoportal_redes_carga_anular(a, v_c, 'ZT9 anulada a propósito');
  -- polígonos (sectores hidráulicos) con su llave
  v_c := pg_temp.cargar(a, 'sectores', 'zt9-sec-1', 'SECTOR', jsonb_build_array(
    pg_temp.fila(1, format('POLYGON((%s %s, %s %s, %s %s, %s %s))', lo, la + 0.06, lo + 0.01, la + 0.06, lo + 0.01, la + 0.07, lo, la + 0.06), '{"SECTOR": "99", "NOMBRE": "ZT9 Sector"}')));
  v_x := public.geoportal_redes_carga_publicar(a, v_c, 'ZT9 primera carga de sectores');
  perform pg_temp.reg('07.07 los polígonos (sectores hidráulicos) se publican como activos SEC', (v_x ->> 'nuevos')::integer = 1
     and (select GeometryType(geom) from redes.v_activo_vigente where capa_codigo = 'sectores' and llave_capa = '99') = 'POLYGON');

  -- ===================== H. Revertir e historial =====================
  v_x := public.geoportal_redes_carga_revertir(a, 'aduccion', 'ZT9 se cargó el archivo equivocado');
  perform pg_temp.reg('07.08 revertir la segunda carga de aducción: vuelve el retirado, salen los 2 nuevos y el cruzado vuelve a la versión 1',
     not (select retirado from redes.v_activo_vigente where codigo = v_a2) and (select version from redes.v_activo_vigente where codigo = v_a1) = 1
     and (select count(*) from redes.v_activo_vigente where capa_codigo = 'aduccion' and not retirado) = 2, v_x::text);
  v_r := public.geoportal_redes_cargue_historial(sd, 'aduccion');
  perform pg_temp.reg('07.09 el historial de la capa (supervisor): 3 cargas, la última anulada, la segunda revertida con su motivo',
     jsonb_array_length(v_r -> 'cargas') = 3 and (v_r -> 'cargas' -> 0 ->> 'estado') = 'anulada' and (v_r -> 'cargas' -> 1 ->> 'estado') = 'revertida'
     and exists (select 1 from jsonb_array_elements(v_r -> 'cargas' -> 1 -> 'eventos') e where e ->> 'tipo' = 'revertir' and e ->> 'motivo' = 'ZT9 se cargó el archivo equivocado'), left(v_r::text, 300));
  perform pg_temp.err('07.10 el operador no ve el historial', format($$select public.geoportal_redes_cargue_historial(%L, 'aduccion')$$, op), '42501');
  perform pg_temp.reg('07.11 la carga masiva queda marcada en el historial', (select x ->> 'masiva' from jsonb_array_elements(public.geoportal_redes_cargue_historial(a, 'sensores') -> 'cargas') x
                                                                       where (x ->> 'carga_id')::bigint = (select min(id) from redes.cargas where capa_codigo = 'sensores')) = 'true');

  -- ===================== I. Planta: el administrador aprueba lo suyo (§32.1) y corregir una verificada (§32.2) =====================
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9701', 'ZT9 Uno', 'muestreo', 'norte'), ('MUE-9702', 'ZT9 Dos', 'muestreo', 'sur'), ('MUE-9703', 'ZT9 Tres', 'muestreo', 'medio');
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, barrio_capa, autor)
  select id, la + 0.08, lo + o * 0.002, case when codigo = 'MUE-9703' then 'verificada' else 'aproximada' end, case when codigo = 'MUE-9703' then 'david' else 'barrio' end, 'ZT9 BARRIO', a
    from (select id, codigo, row_number() over (order by codigo) o from tecnica.puntos where codigo like 'MUE-97%') x;
  v_x := public.geoportal_tec_punto_ubicacion_proponer(a, 'MUE-9701', la + 0.0801, lo + 0.002, 5);
  v_r := public.geoportal_tec_punto_ubicaciones(a);
  perform pg_temp.reg('08.01 la lista dice que el administrador puede revisar la suya',
     (v_r ->> 'soy_admin')::boolean and (select (x ->> 'propia')::boolean and (x ->> 'puede_revisar')::boolean from jsonb_array_elements(v_r -> 'pendientes') x where x ->> 'punto' = 'MUE-9701'));
  v_x := public.geoportal_tec_punto_ubicacion_revisar(a, (v_x ->> 'propuesta_id')::bigint, 'aprobar', null);
  perform pg_temp.reg('08.02 el administrador aprueba la ubicación que tomó él mismo: queda verificada, del GPS del operador', v_x ->> 'estado' = 'aprobada'
     and pg_temp.vig('MUE-9701') like 'verificada|gps_operador|%|' || a);
  v_x := public.geoportal_tec_punto_ubicacion_proponer(sv, 'MUE-9702', la + 0.0801, lo + 0.004, 5);
  perform pg_temp.reg('08.03 la del supervisor sigue sin poder revisarla él mismo (en la lista)',
     (select not (x ->> 'puede_revisar')::boolean from jsonb_array_elements(public.geoportal_tec_punto_ubicaciones(sv) -> 'pendientes') x where x ->> 'punto' = 'MUE-9702'));
  perform pg_temp.err('08.04 y la RPC tampoco le deja', format($$select public.geoportal_tec_punto_ubicacion_revisar(%L, %s, 'aprobar', null)$$, sv, v_x ->> 'propuesta_id'), null, 'usted mismo');
  perform pg_temp.err('08.05 corregir una aproximada no: va por Muestreo o por la capa', format($$select public.geoportal_tec_punto_ubicacion_corregir(%L, 'MUE-9702', %s, %s, 'mapa', null, 'ZT9 el punto está al frente')$$, sv2, la + 0.081, lo + 0.004), '55000', 'Solo se corrige una ubicación verificada');
  v_t := pg_temp.vig('MUE-9703'); v_u0 := (select count(*) from tecnica.puntos_ubicacion);
  perform pg_temp.err('08.06 el operador no corrige', format($$select public.geoportal_tec_punto_ubicacion_corregir(%L, 'MUE-9703', %s, %s, 'mapa', null, 'ZT9 el punto está al frente')$$, op, la + 0.081, lo + 0.006));
  perform pg_temp.err('08.07 sin motivo no se corrige', format($$select public.geoportal_tec_punto_ubicacion_corregir(%L, 'MUE-9703', %s, %s, 'mapa', null, 'corto')$$, sv, la + 0.081, lo + 0.006), null, 'motivo');
  perform pg_temp.err('08.08 fuera de Valledupar no', format($$select public.geoportal_tec_punto_ubicacion_corregir(%L, 'MUE-9703', 4.6, -74.08, 'coordenadas', null, 'ZT9 el punto está al frente')$$, sv), null, 'fuera de Valledupar');
  perform pg_temp.err('08.09 el mismo lugar (menos de 1 m) no', format($$select public.geoportal_tec_punto_ubicacion_corregir(%L, 'MUE-9703', %s, %s, 'coordenadas', null, 'ZT9 el punto está al frente')$$, sv, la + 0.08, lo + 0.006), null, 'la misma de ahora');
  perform pg_temp.err('08.10 con el GPS impreciso no', format($$select public.geoportal_tec_punto_ubicacion_corregir(%L, 'MUE-9703', %s, %s, 'gps', 45, 'ZT9 el punto está al frente')$$, sv, la + 0.081, lo + 0.006), null, 'precisión de 45 m');
  perform pg_temp.err('08.11 la precisión solo va con el GPS', format($$select public.geoportal_tec_punto_ubicacion_corregir(%L, 'MUE-9703', %s, %s, 'mapa', 5, 'ZT9 el punto está al frente')$$, sv, la + 0.081, lo + 0.006), null, 'solo va con el GPS');
  perform pg_temp.reg('08.12 los intentos fallidos no dejaron rastro', pg_temp.vig('MUE-9703') = v_t and (select count(*) from tecnica.puntos_ubicacion) = v_u0);
  v_x := public.geoportal_tec_punto_ubicacion_corregir(sv, 'MUE-9703', la + 0.0805, lo + 0.006, 'mapa', null, 'ZT9 el punto real está en la esquina');
  perform pg_temp.reg('08.13 corregida: la nueva es verificada, fuente «correccion», del supervisor; la anterior queda en el historial; con la distancia y la auditoría',
     pg_temp.vig('MUE-9703') = 'verificada|correccion|' || round(la + 0.0805, 6) || '|' || round(lo + 0.006, 6) || '|' || sv
     and (select count(*) from tecnica.puntos_ubicacion u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-9703') = 2
     and (v_x ->> 'distancia_m')::numeric between 50 and 60 and (select barrio_capa from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-9703') = 'ZT9 BARRIO'
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_punto_ubicacion_corregir' and referencia = 'MUE-9703'), v_x::text);
  perform pg_temp.reg('08.14 la lista de «Puntos» trae la corrección con su motivo',
     (select x ->> 'motivo' from jsonb_array_elements(public.geoportal_tec_punto_ubicaciones(sv2) -> 'correcciones') x where x ->> 'punto' = 'MUE-9703') = 'ZT9 el punto real está en la esquina');
  v_x := public.geoportal_tec_punto_ubicacion_corregir(sv2, 'MUE-9701', la + 0.0802, lo + 0.002, 'gps', 6, 'ZT9 se volvió a tomar en campo');
  perform pg_temp.reg('08.15 también con el GPS del supervisor (precisión de 30 m o menos)', pg_temp.vig('MUE-9701') like 'verificada|correccion|%|' || sv2
     and (select metodo || '|' || precision_m from tecnica.punto_ubicacion_correcciones where id = (v_x ->> 'correccion_id')::bigint) = 'gps|6.0');
  perform pg_temp.err('08.16 un punto corregido sigue verificado: el operador ya no propone sobre él',
     format($$select public.geoportal_tec_punto_ubicacion_proponer(%L, 'MUE-9703', %s, %s, 5)$$, op, la + 0.0806, lo + 0.006), '55000', 'ya está verificada');
  -- un punto aproximado con una propuesta pendiente que, mientras tanto, queda verificado por una carga de la capa: no se corrige hasta revisar la propuesta
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9704', 'ZT9 Cuatro', 'muestreo', 'sur');
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, autor) select id, la + 0.09, lo, 'aproximada', 'barrio', a from tecnica.puntos where codigo = 'MUE-9704';
  perform public.geoportal_tec_punto_ubicacion_proponer(op, 'MUE-9704', la + 0.0901, lo, 5);
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, autor) select id, la + 0.0902, lo, 'verificada', 'carga', a from tecnica.puntos where codigo = 'MUE-9704';
  perform pg_temp.err('08.17 con una propuesta en revisión no se corrige (primero se aprueba o se rechaza)',
     format($$select public.geoportal_tec_punto_ubicacion_corregir(%L, 'MUE-9704', %s, %s, 'mapa', null, 'ZT9 el punto está al frente')$$, sv2, la + 0.0905, lo), '55000', 'en revisión');
  perform pg_temp.err('08.18 un punto que no existe', format($$select public.geoportal_tec_punto_ubicacion_corregir(%L, 'MUE-9799', %s, %s, 'mapa', null, 'ZT9 el punto está al frente')$$, sv2, la + 0.0905, lo), 'P0002');

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 5c (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
