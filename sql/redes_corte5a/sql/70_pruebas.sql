-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 25, 26 y 40, en la misma transacción.
-- Como las de los cortes anteriores: corre después de la carga real y de los cortes publicados; NO supone códigos ni conteos de la base. Arma su red de
-- prueba (ID 99700xx; nodos V997, J-997 y Tee-997) y sus puntos de muestreo (MUE-99nn). Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 5a … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- posición de prueba: x, y en metros aproximados desde un origen dentro de Valledupar
create function pg_temp.p(x numeric, y numeric) returns text language sql as $$ select (-73.2400 + x * 0.0000091)::text || ' ' || (10.4700 + y * 0.0000090)::text $$;
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4700 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.2400 + x * 0.0000091, 6) $$;
create function pg_temp.tramo(p_orden integer, p_id integer, p_label text, p_ini text, p_ini_nom text, p_fin text, p_fin_nom text, p_wkt text) returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', p_wkt, 'atributos', jsonb_build_object('ID', p_id, 'LABEL', p_label, 'MATERIAL', 'PVC', 'D', 3, 'LENGTH', 100, 'ZONE', null,
         'IS_ACTIVE?', true, 'CHK_VLVE?', false, 'STARTNODID', p_ini, 'STARTNODE', p_ini_nom, 'STOPNODEID', p_fin, 'STOPNODE', p_fin_nom)) $$;
-- archivo de prueba en Storage (la subida real la hace el celular con la URL firmada)
create function pg_temp.archivo(p_ruta text, p_bytes integer default 300000, p_mime text default 'image/jpeg') returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', p_bytes, 'mimetype', p_mime)) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
-- datos base de una intervención válida (se cambian claves en cada prueba)
create function pg_temp.itv(p_archivos jsonb, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('nace_de', 'programada', 'tipo', 'preventivo', 'sistema', 'acueducto', 'activo', current_setting('zt.red1'),
         'lat', pg_temp.lat(0), 'lon', pg_temp.lon(50), 'precision_m', 5, 'ubicacion_origen', 'gps', 't_inicio', pg_temp.iso('-3 hours'), 't_fin', pg_temp.iso('-1 hours'),
         'descripcion', 'Revisión y limpieza de prueba del tramo', 'materiales', '[]'::jsonb, 'ejecutor', 'emdupar',
         'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')), 'archivos', p_archivos) || p_extra $$;
create function pg_temp.a1(p_ruta text, p_clase text default 'despues') returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('n', 1, 'clase', p_clase, 'ruta', p_ruta)) $$;
-- un daño válido (para los que se atienden), con su foto ya en Storage
create function pg_temp.dano(p_quien text, p_extra jsonb) returns jsonb language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_dano(p_quien, 1);
begin
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  return public.geoportal_redes_crear_dano(p_quien, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', current_setting('zt.red1'),
         'lat', pg_temp.lat(0), 'lon', pg_temp.lon(40), 'ubicacion_origen', 'gps', 't_detectado', pg_temp.iso('-5 hours'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
         'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))) || p_extra);
end $$;
-- prepara una intervención y sube sus archivos de prueba; devuelve la preparación
create function pg_temp.preparar(p_quien text, p_fotos integer, p_docs integer default 0) returns jsonb language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_intervencion(p_quien, p_fotos, p_docs); x jsonb;
begin
  for x in select e from jsonb_array_elements(v_p -> 'fotos') e loop perform pg_temp.archivo(x ->> 'ruta'); end loop;
  for x in select e from jsonb_array_elements(v_p -> 'documentos') e loop perform pg_temp.archivo(x ->> 'ruta', 800000, 'application/pdf'); end loop;
  return v_p;
end $$;

-- una carga de acueducto de prueba, publicada, con las filas dadas
create function pg_temp.cargar_acu(p_admin text, p_huella text, p_filas jsonb) returns jsonb language plpgsql as $$
declare v_c bigint := (public.geoportal_redes_carga_iniciar(p_admin, 'acueducto', pg_temp.sha(p_huella), 'shp', 4326, 'ID', jsonb_array_length(p_filas)) ->> 'carga_id')::bigint;
begin
  perform public.geoportal_redes_carga_lote(p_admin, v_c, p_filas);
  return jsonb_build_object('carga_id', v_c, 'resumen', public.geoportal_redes_carga_resumen(p_admin, v_c));
end $$;
create function pg_temp.mue(p_orden integer, p_codigo text, p_lat numeric, p_lon numeric, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', 'POINT(' || p_lon || ' ' || p_lat || ')',
         'atributos', jsonb_strip_nulls(jsonb_build_object('codigo', p_codigo)) || p_extra) $$;
create function pg_temp.cargar_mue(p_admin text, p_huella text, p_filas jsonb) returns bigint language plpgsql as $$
declare v_c bigint := (public.geoportal_redes_carga_iniciar(p_admin, 'muestreo', pg_temp.sha(p_huella), 'csv', 4326, 'codigo', jsonb_array_length(p_filas)) ->> 'carga_id')::bigint;
begin
  perform public.geoportal_redes_carga_lote(p_admin, v_c, p_filas);
  return v_c;
end $$;

do $prueba$
declare
  a text := 'prueba.redes7.adm@emdupar.gov.co'; sv text := 'prueba.redes7.sup@emdupar.gov.co'; op text := 'prueba.redes7.op@emdupar.gov.co';
  o2 text := 'prueba.redes7.op2@emdupar.gov.co'; sd text := 'prueba.redes7.dist@emdupar.gov.co'; sd2 text := 'prueba.redes7.dist2@emdupar.gov.co';
  sr text := 'prueba.redes7.soloredes@emdupar.gov.co'; na text := 'prueba.redes7.nada@emdupar.gov.co';
  v_red1 text; v_red2 text; v_acc text; v_nj bigint; v_c bigint; v_r jsonb; v_x jsonb; v_p jsonb; v_n integer; v_m integer; v_k text; v_t text; v_id bigint;
  v_act_otros integer; v_puntos0 integer; v_sig integer; v_m1 bigint; v_m2 bigint;
  v_total integer; v_bien integer; v_fallas text;
  c1 jsonb; c2 jsonb; c3 jsonb;
  w1 text := 'LINESTRING(' || pg_temp.p(0, 0) || ',' || pg_temp.p(100, 0) || ')';
  w2 text := 'LINESTRING(' || pg_temp.p(100, 0) || ',' || pg_temp.p(200, 0) || ')';
  w1b text := 'LINESTRING(' || pg_temp.p(0, 0) || ',' || pg_temp.p(100, 6) || ')';
  w2b text := 'LINESTRING(' || pg_temp.p(100, 6) || ',' || pg_temp.p(200, 0) || ')';
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT7 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT7 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos'),
    (sd2, 'ZT7 Otro supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos'), (sr, 'ZT7 Solo dashboard de redes', 'consulta', false, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT7 Operador', 'consulta', true, 'sin_restriccion', 'todos'),
    (o2, 'ZT7 Operador sin formularios', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT7 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'mantenimiento', a), (op, 'asignar_formulario', 'danos_fallas', a);

  -- ===================== A. §28 =====================
  -- red de prueba con el motor del 1a (la primera carga)
  c1 := pg_temp.cargar_acu(a, 'zt7-acu-1', jsonb_build_array(
    pg_temp.tramo(1, 9970001, 'Distribucion-ZT71', '99701', 'V997', '99702', 'J-997', w1), pg_temp.tramo(2, 9970002, 'Lateral-ZT72', '99702', 'J-997', '99703', 'Tee-997', w2)));
  perform public.geoportal_redes_carga_publicar(a, (c1 ->> 'carga_id')::bigint, 'Red de prueba del Corte 5a (primera carga)');
  select codigo into v_red1 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9970001';
  select codigo into v_red2 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9970002';
  select nodo_id into v_nj from redes.v_nodo_vigente where sistema = 'acueducto' and llave_modelo = '99702';
  perform set_config('zt.red1', v_red1, true);
  perform pg_temp.reg('00.01 red de prueba: 2 RED; J-997 «por clasificar»', v_red1 like 'RED-%' and v_red2 like 'RED-%'
     and (select clase_nodo from redes.v_nodo_vigente where nodo_id = v_nj) = 'por_clasificar', concat_ws(' ', v_red1, v_red2, v_nj));

  -- §28.1: el supervisor y el administrador con tope (72 h y 30 días); el operador sigue con 7 días
  v_r := public.geoportal_redes_formulario_intervencion(sd);
  perform pg_temp.reg('01.01 el formulario del supervisor dice 30 días atrás y 72 h (antes: sin tope)', (v_r -> 'reglas' ->> 'dias_atras_max')::integer = 30 and (v_r -> 'reglas' ->> 'max_horas')::integer = 72, (v_r -> 'reglas')::text);
  v_r := public.geoportal_redes_formulario_intervencion(op);
  perform pg_temp.reg('01.02 el del operador sigue en 7 días y 72 h', (v_r -> 'reglas' ->> 'dias_atras_max')::integer = 7 and (v_r -> 'reglas' ->> 'max_horas')::integer = 72);
  v_p := pg_temp.preparar(sd, 1);
  v_r := public.geoportal_redes_crear_intervencion(sd, (v_p ->> 'intervencion_id')::uuid, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'),
            jsonb_build_object('t_inicio', pg_temp.iso('-20 days'), 't_fin', pg_temp.iso('-20 days') )));
  perform pg_temp.reg('01.03 el supervisor registra una intervención de hace 20 días', v_r ->> 'codigo' like 'ITV-%', left(v_r::text, 200));
  v_p := pg_temp.preparar(sd, 1);
  perform pg_temp.err('01.04 de hace 40 días, ya no', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sd, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('t_inicio', pg_temp.iso('-40 days'), 't_fin', pg_temp.iso('-39 days')))), '22023', 'más de 30 días');
  perform pg_temp.err('01.05 una de 5 días seguidos (120 h), tampoco: «varias intervenciones, cada una con su foto»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sd, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('t_inicio', pg_temp.iso('-10 days'), 't_fin', pg_temp.iso('-5 days')))), '22023', 'varias intervenciones');
  v_p := pg_temp.preparar(a, 1);
  perform pg_temp.err('01.06 el administrador también tiene tope', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, a, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('t_inicio', pg_temp.iso('-40 days'), 't_fin', pg_temp.iso('-39 days')))), '22023', 'más de 30 días');
  v_p := pg_temp.preparar(op, 1);
  perform pg_temp.err('01.07 el operador, de hace 10 días, no (sigue en 7)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('t_inicio', pg_temp.iso('-10 days'), 't_fin', pg_temp.iso('-10 days')))), '22023', 'más de 7 días');
  perform pg_temp.reg('01.08 el tope del supervisor es un parámetro (30 días, de 1 a 90)', (select valor = 30 and minimo = 1 and maximo = 90 from redes.parametros where clave = 'itv_dias_atras_max_supervisor'));

  -- §28.2: el supervisor de distribución asigna los formularios de distribución
  v_r := public.geoportal_redes_personal_formulario(sd, o2, 'mantenimiento', true, 'Empieza a registrar intervenciones', '10.0.0.7');
  perform pg_temp.reg('02.01 el supervisor de distribución asigna «Registrar intervención»: evento en la tabla de siempre, con su autor y motivo',
     v_r ->> 'asignado' = 'true' and tecnica.f_formulario_asignado(o2, 'mantenimiento')
     and exists (select 1 from tecnica.personal_tecnico_eventos where persona = o2 and formulario = 'mantenimiento' and tipo_evento = 'asignar_formulario' and autor = sd));
  perform pg_temp.reg('02.02 con eso el operador ya captura la intervención (la regla de planta de siempre)', public.geoportal_redes_formulario_intervencion(o2) ? 'reglas');
  perform pg_temp.reg('02.03 queda la señal de tiempo real y la auditoría (con la IP)', exists (select 1 from tecnica.senal_cambio where tabla = 'personal_tecnico_eventos')
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_asignar_formulario' and referencia = o2 and ip = '10.0.0.7'));
  perform pg_temp.err('02.04 asignarlo otra vez', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'mantenimiento', true, 'Otra vez el mismo')$$, sd, o2), '22023', 'Ya tiene');
  v_r := public.geoportal_redes_personal_formulario(sd2, o2, 'mantenimiento', false, 'Ya no hace intervenciones');
  perform pg_temp.reg('02.05 quitarlo (otro supervisor): evento «quitar» y ya no captura', not tecnica.f_formulario_asignado(o2, 'mantenimiento')
     and exists (select 1 from tecnica.personal_tecnico_eventos where persona = o2 and tipo_evento = 'quitar_formulario' and autor = sd2));
  perform pg_temp.err('02.06 sin el formulario, el operador ya no abre la intervención', format($$select public.geoportal_redes_formulario_intervencion(%L)$$, o2), '42501');
  perform pg_temp.err('02.07 un formulario de planta, no (se asigna en el Dashboard PTAP)', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'entrada', true, 'Formulario de planta')$$, sd, o2), '22023', 'Dashboard PTAP');
  perform pg_temp.err('02.08 sin motivo', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'corto')$$, sd, o2), '22023', 'motivo');
  perform pg_temp.err('02.09 a sí mismo, no', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'Me lo asigno a mí')$$, sd, sd), '22023', 'propios');
  perform pg_temp.err('02.10 a quien no tiene Registro técnico, no', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'Sin registro técnico')$$, sd, sr), '55000');
  perform pg_temp.err('02.11 el operador no asigna', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'Intento del operador')$$, op, o2), '42501');
  perform pg_temp.err('02.12 el supervisor de planta tampoco (lo hace en su Dashboard PTAP)', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'Intento del de planta')$$, sv, o2), '42501');
  perform pg_temp.err('02.13 quien no es de Técnica', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'Persona sin Técnica')$$, sd, na), 'P0002');
  v_r := public.geoportal_redes_personal(sd, 'zt7', 'todas');
  perform pg_temp.reg('02.14 Personal lista los formularios desde la tabla de distribución y los de cada uno', v_r -> 'formularios' @> '[{"clave": "danos_fallas"}, {"clave": "mantenimiento"}]'::jsonb
     and exists (select 1 from jsonb_array_elements(v_r -> 'personas') x where x ->> 'email' = op and x -> 'formularios' = '["danos_fallas", "mantenimiento"]'::jsonb)
     and exists (select 1 from jsonb_array_elements(v_r -> 'personas') x where x ->> 'email' = o2 and x -> 'formularios' = '[]'::jsonb));
  -- §28.5: las cuadrillas también las crea el supervisor de distribución
  v_r := public.geoportal_redes_cuadrilla_fijar(sd, null, 'ZT7 Cuadrilla del supervisor', null, 'La crea el supervisor de distribución');
  perform pg_temp.reg('03.01 el supervisor de distribución crea una cuadrilla y el catálogo se lo dice', (v_r ->> 'nueva')::boolean
     and (public.geoportal_redes_catalogo(sd) ->> 'puede_cuadrillas')::boolean and not (public.geoportal_redes_catalogo(sd) ->> 'puede_editar')::boolean);
  perform pg_temp.reg('03.02 y la desactiva', not (public.geoportal_redes_cuadrilla_fijar(sd, (v_r ->> 'id')::bigint, null, false, 'Cuadrilla de prueba que se cierra') ->> 'activa')::boolean);
  perform pg_temp.err('03.03 el operador no', format($$select public.geoportal_redes_cuadrilla_fijar(%L, null, 'ZT7 Otra', null, 'Intento del operador')$$, op), '42501');
  perform pg_temp.err('03.04 el alias de los tipos sigue siendo solo del administrador', format($$select public.geoportal_redes_alias_fijar(%L, 'tipo', 'TOR', 'Hidrante', 'Intento del supervisor')$$, sd), '42501');

  -- ===================== B. Recarga: gana la ficha (§26.3) y los choques en el resumen (17c); la bandeja de nodos se conserva (17f) =====================
  perform public.geoportal_redes_ficha_editar(sd, v_red1, '{"diametro_mm": 110, "fecha_instalacion": "2020-05-01", "observaciones": "Se cambió en 2020"}', 'Datos que trajo la cuadrilla');
  perform public.geoportal_redes_ficha_editar(a, v_red2, '{"origen": {"origen": "tercero", "aportante": "alcaldia"}}', 'Lo entregó la alcaldía');
  v_acc := public.geoportal_redes_nodo_crear_activo(a, v_nj, 'ACC', 'union', null, 'Técnica confirmó que la J-997 es una unión') ->> 'activo';
  -- segunda carga: tramo 1 con D = 4" (102 mm) y tramo 2 con D = 6" (152 mm) y zona SIVA (origen tercero, SIVA)
  c2 := pg_temp.cargar_acu(a, 'zt7-acu-2', jsonb_build_array(
    jsonb_set(pg_temp.tramo(1, 9970001, 'Distribucion-ZT71', '99701', 'V997', '99702', 'J-997', w1), '{atributos,D}', '4'),
    jsonb_set(jsonb_set(pg_temp.tramo(2, 9970002, 'Lateral-ZT72', '99702', 'J-997', '99703', 'Tee-997', w2), '{atributos,D}', '6'), '{atributos,ZONE}', '"SIVA"')));
  v_r := c2 -> 'resumen';
  perform pg_temp.reg('10.01 el resumen lista los choques con la ficha: el diámetro de RED-1 (ficha 110 / capa 102) y el origen de RED-2',
     exists (select 1 from jsonb_array_elements(v_r -> 'choques') x where x ->> 'codigo' = v_red1 and x ->> 'campo' = 'diametro_mm' and x ->> 'ficha' = '110' and x ->> 'capa' = '102')
     and exists (select 1 from jsonb_array_elements(v_r -> 'choques') x where x ->> 'codigo' = v_red2 and x ->> 'campo' = 'origen')
     and (v_r ->> 'lista_para_publicar')::boolean, left((v_r -> 'choques')::text, 400));
  perform pg_temp.reg('10.02 los choques no bloquean: van como aviso y en la tabla para psql (sección «6b choques con la ficha»)',
     exists (select 1 from jsonb_array_elements_text(v_r -> 'avisos') x where x like '%gana la ficha%')
     and exists (select 1 from jsonb_array_elements(v_r -> 'tabla') x where x ->> 's' like '6b choques%' and x ->> 'c' = v_red1 || ' · diametro_mm'));
  perform pg_temp.reg('10.03 el resumen cuenta el nodo clasificado en la bandeja (se conserva)', (v_r -> 'detalle' ->> 'nodos_clasificados_en_la_bandeja')::integer = 1);
  perform public.geoportal_redes_carga_publicar(a, (c2 ->> 'carga_id')::bigint, 'Segunda carga de prueba del Corte 5a');
  select * into v_x from (select to_jsonb(v) as j from redes.v_activo_vigente v where codigo = v_red1) z;
  perform pg_temp.reg('10.04 gana la ficha: RED-1 sigue en 110 mm, con su fecha de instalación y sus observaciones (la carga no las trae)',
     (v_x ->> 'diametro_mm')::numeric = 110 and v_x ->> 'fecha_instalacion' = '2020-05-01' and v_x -> 'atributos' ->> 'observaciones' = 'Se cambió en 2020', left(v_x::text, 400));
  perform pg_temp.reg('10.05 lo que no se editó en la ficha sí lo cambia la capa: RED-2 pasa a 152 mm', (select diametro_mm from redes.v_activo_vigente where codigo = v_red2) = 152);
  perform pg_temp.reg('10.06 el origen corregido en la ficha (alcaldía) no lo pisa la capa (SIVA)',
     (select o.aportante_codigo from redes.v_activo_origen_vigente o join redes.activos x on x.id = o.activo_id where x.codigo = v_red2) = 'alcaldia');
  perform pg_temp.reg('10.07 la J-997 sigue siendo el accesorio de la bandeja', (select clase_nodo = 'activo' and activo_id = (select id from redes.activos where codigo = v_acc)
     from redes.v_nodo_vigente where sistema = 'acueducto' and llave_modelo = '99702'));
  -- tercera carga: la J-997 se mueve 6 m (el nodo es nuevo en la topología); tramo 1 con D = 110 mm de la capa (ya no hay choque)
  c3 := pg_temp.cargar_acu(a, 'zt7-acu-3', jsonb_build_array(
    jsonb_set(pg_temp.tramo(1, 9970001, 'Distribucion-ZT71', '99701', 'V997', '99702', 'J-997', w1b), '{atributos,D}', '4.33'),
    jsonb_set(jsonb_set(pg_temp.tramo(2, 9970002, 'Lateral-ZT72', '99702', 'J-997', '99703', 'Tee-997', w2b), '{atributos,D}', '6'), '{atributos,ZONE}', '"SIVA"')));
  perform pg_temp.reg('10.08 cuando la capa trae lo mismo que la ficha, no hay choque', not exists (select 1 from jsonb_array_elements(c3 -> 'resumen' -> 'choques') x where x ->> 'campo' = 'diametro_mm'),
     left((c3 -> 'resumen' -> 'choques')::text, 300));
  perform public.geoportal_redes_carga_publicar(a, (c3 ->> 'carga_id')::bigint, 'Tercera carga de prueba del Corte 5a (la J se mueve)');
  perform pg_temp.reg('10.09 la J-997 se movió (nodo nuevo) y sigue enlazada al mismo accesorio (evento «enlazar_activo» de la carga)',
     (select n.nodo_id <> v_nj and n.clase_nodo = 'activo' and n.activo_id = (select id from redes.activos where codigo = v_acc) from redes.v_nodo_vigente n where n.sistema = 'acueducto' and n.llave_modelo = '99702')
     and exists (select 1 from redes.nodo_eventos e join redes.nodos n on n.id = e.nodo_id where n.llave_modelo = '99702' and n.carga_id = (c3 ->> 'carga_id')::bigint and e.tipo = 'enlazar_activo'));
  perform pg_temp.reg('10.10 el accesorio creado en el nodo no se retiró en ninguna recarga', not (select retirado from redes.v_activo_vigente where codigo = v_acc));
  perform public.geoportal_redes_carga_revertir(a, 'acueducto', 'Se revierte la tercera carga de prueba');
  perform pg_temp.reg('10.11 revertir la tercera carga: la J-997 vuelve a su nodo y a su accesorio', (select nodo_id = v_nj and activo_id = (select id from redes.activos where codigo = v_acc)
     from redes.v_nodo_vigente where sistema = 'acueducto' and llave_modelo = '99702'));
  perform pg_temp.reg('10.12 la ficha sigue ganando después de revertir (110 mm y la fecha de 2020)', (select diametro_mm = 110 and fecha_instalacion = date '2020-05-01' from redes.v_activo_vigente where codigo = v_red1));

  -- ===================== C. Capa MUE (puntos de muestreo; tecnica.puntos solo agrega y cambia «activo» con evento) =====================
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9901', 'ZT7 Punto uno', 'muestreo', 'norte'), ('MUE-9902', 'ZT7 Punto dos', 'muestreo', 'sur'),
    ('MUE-9950', 'ZT7 Tanque con código de muestreo', 'tanque', null);
  select count(*) into v_act_otros from tecnica.puntos where tipo = 'muestreo' and activo and codigo not in ('MUE-9901', 'MUE-9902');
  select count(*) into v_puntos0 from tecnica.puntos;
  v_sig := (select max(substring(codigo from '^MUE-([0-9]+)$')::integer) from tecnica.puntos where codigo ~ '^MUE-[0-9]+$');
  perform pg_temp.err('20.01 el supervisor de distribución no carga capas', format($$select public.geoportal_redes_carga_iniciar(%L, 'muestreo', %L, 'csv', 4326, 'codigo', 1)$$, sd, pg_temp.sha('x')), '42501');
  -- una carga con errores: todo lo que bloquea
  v_m1 := pg_temp.cargar_mue(a, 'zt7-mue-mala', jsonb_build_array(
    pg_temp.mue(1, 'ZZ-1', 10.47, -73.25, '{"nombre": "Código raro"}'), pg_temp.mue(2, 'MUE-9950', 10.47, -73.25), pg_temp.mue(3, 'MUE-9901', 4.60, -74.08),
    pg_temp.mue(4, 'MUE-9902', 10.47, -73.25), pg_temp.mue(5, 'MUE-9902', 10.47, -73.25), pg_temp.mue(6, null, 10.47, -73.25),
    pg_temp.mue(7, 'MUE-9903', 10.47, -73.25, '{"nombre": "ZT7 Nuevo", "fuente": "gps_operador"}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_m1);
  perform pg_temp.reg('20.02 el resumen bloquea: código que no es MUE-nn, código de otro tipo de punto, fuera de Valledupar, repetido, nuevo sin nombre y la fuente GPS',
     not (v_r ->> 'lista_para_publicar')::boolean and jsonb_array_length(v_r -> 'bloqueos') = 6
     and (v_r -> 'bloqueos')::text like '%MUE-nn%' and (v_r -> 'bloqueos')::text like '%otro tipo de punto%' and (v_r -> 'bloqueos')::text like '%Fuera de la caja de Valledupar%'
     and (v_r -> 'bloqueos')::text like '%repetidos%' and (v_r -> 'bloqueos')::text like '%necesita su nombre%' and (v_r -> 'bloqueos')::text like '%GPS del operador%', (v_r -> 'bloqueos')::text);
  perform pg_temp.err('20.03 y no se publica', format($$select public.geoportal_redes_carga_publicar(%L, %s, 'No debe publicarse')$$, a, v_m1), '22023', 'no está lista');
  perform public.geoportal_redes_carga_anular(a, v_m1, 'Archivo de prueba con errores');
  -- la buena: dos que existen (sin ubicación), uno nuevo con código y uno sin código
  v_m1 := pg_temp.cargar_mue(a, 'zt7-mue-1', jsonb_build_array(
    pg_temp.mue(1, 'MUE-9901', 10.48067, -73.25744, '{"exactitud": "verificada", "fuente": "david"}'),
    pg_temp.mue(2, 'mue-9902 ', 10.4600, -73.2500, '{"barrio": "ZT7 BARRIO", "fuente": "barrio", "nombre": "Otro nombre"}'),
    pg_temp.mue(3, 'MUE-9903', 10.4700, -73.2600, '{"nombre": "ZT7 Punto tres", "zona": "medio"}'),
    pg_temp.mue(4, null, 10.4650, -73.2550, '{"nombre": "ZT7 Punto sin código"}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_m1);
  perform pg_temp.reg('20.04 resumen listo: 2 ubicaciones, 1 nuevo, 1 sin código, y avisa los activos que se desactivan y el nombre distinto (que no se cambia)',
     (v_r ->> 'lista_para_publicar')::boolean and (v_r -> 'frente_a_vigente' ->> 'ubicacion')::integer = 2 and (v_r -> 'frente_a_vigente' ->> 'nuevo')::integer = 1
     and (v_r -> 'frente_a_vigente' ->> 'nuevo_sin_codigo')::integer = 1 and jsonb_array_length(v_r -> 'desactivar') = v_act_otros
     and (v_r -> 'avisos')::text like '%no se cambia%' and (v_act_otros = 0 or (v_r -> 'avisos')::text like '%DESACTIVAN%'), left(v_r::text, 500));
  perform pg_temp.reg('20.05 el resumen no escribió nada en tecnica.puntos', (select count(*) from tecnica.puntos) = v_puntos0 and not exists (select 1 from tecnica.puntos_ubicacion));
  v_r := public.geoportal_redes_carga_publicar(a, v_m1, 'Primera carga de prueba de la capa de muestreo');
  v_k := 'MUE-' || lpad((greatest(v_sig, 9903) + 1)::text, 2, '0');
  perform pg_temp.reg('20.06 publicar: 2 puntos nuevos agregados (MUE-9903 y el siguiente consecutivo ' || v_k || '), con su evento «crear»',
     (v_r ->> 'nuevos')::integer = 2 and v_r -> 'codigos_asignados' = jsonb_build_array(v_k)
     and (select count(*) from tecnica.puntos) = v_puntos0 + 2 and exists (select 1 from tecnica.puntos where codigo = v_k and nombre = 'ZT7 Punto sin código' and tipo = 'muestreo' and activo)
     and (select count(*) from tecnica.punto_eventos e join tecnica.puntos p on p.id = e.punto_id where p.codigo in ('MUE-9903', v_k) and e.tipo = 'crear') = 2, v_r::text);
  perform pg_temp.reg('20.07 las 4 ubicaciones, con su exactitud y su fuente; el nombre del punto que ya existía no cambió',
     (select count(*) from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo in ('MUE-9901', 'MUE-9902', 'MUE-9903', v_k)) = 4
     and (select exactitud || '|' || fuente from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-9901') = 'verificada|david'
     and (select exactitud || '|' || fuente || '|' || barrio_capa from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-9902') = 'aproximada|barrio|ZT7 BARRIO'
     and (select nombre from tecnica.puntos where codigo = 'MUE-9902') = 'ZT7 Punto dos');
  perform pg_temp.reg('20.08 los activos que no vinieron quedaron DESACTIVADOS con su evento, no borrados',
     (v_r ->> 'desactivados')::integer = v_act_otros and (select count(*) from tecnica.puntos) = v_puntos0 + 2
     and not exists (select 1 from tecnica.puntos p where p.tipo = 'muestreo' and not p.activo and p.codigo not in ('MUE-9901', 'MUE-9902', 'MUE-9903', v_k)
                      and not exists (select 1 from tecnica.punto_eventos e where e.punto_id = p.id and e.tipo = 'desactivar' and e.carga_id = v_m1)));
  perform pg_temp.err('20.09 un punto no se puede borrar (candado de siempre)', $$delete from tecnica.puntos where codigo = 'MUE-9903'$$, '42501');
  perform pg_temp.err('20.10 la ubicación es de solo inserción', $$update tecnica.puntos_ubicacion set lat = 1$$, '42501');
  perform pg_temp.err('20.11 los eventos de los puntos también', $$delete from tecnica.punto_eventos$$, '42501');
  -- segunda carga: solo MUE-9901, igual; los demás se desactivan
  v_m2 := pg_temp.cargar_mue(a, 'zt7-mue-2', jsonb_build_array(pg_temp.mue(1, 'MUE-9901', 10.48067, -73.25744, '{"exactitud": "verificada", "fuente": "david"}')));
  v_r := public.geoportal_redes_carga_publicar(a, v_m2, 'Segunda carga de prueba: solo un punto');
  perform pg_temp.reg('20.12 segunda carga: MUE-9901 igual (sin ubicación nueva) y los otros 3 desactivados',
     (v_r ->> 'iguales')::integer = 1 and (v_r ->> 'ubicaciones')::integer = 0 and (v_r ->> 'desactivados')::integer = 3
     and (select count(*) from tecnica.puntos where codigo in ('MUE-9902', 'MUE-9903', v_k) and not activo) = 3, v_r::text);
  v_r := public.geoportal_redes_carga_revertir(a, 'muestreo', 'Se revierte la segunda carga de prueba');
  perform pg_temp.reg('20.13 revertir la segunda: los 3 vuelven a estar activos (eventos «reactivar»)', (v_r ->> 'reactivados')::integer = 3
     and (select count(*) from tecnica.puntos where codigo in ('MUE-9902', 'MUE-9903', v_k) and activo) = 3);
  v_r := public.geoportal_redes_carga_revertir(a, 'muestreo', 'Se revierte la primera carga de prueba');
  perform pg_temp.reg('20.14 revertir la primera: sus ubicaciones dejan de contar, los creados quedan inactivos (no se borran) y los desactivados vuelven',
     not exists (select 1 from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo in ('MUE-9901', 'MUE-9902', 'MUE-9903', v_k))
     and (select count(*) from tecnica.puntos where codigo in ('MUE-9903', v_k) and not activo) = 2 and (select count(*) from tecnica.puntos) = v_puntos0 + 2
     and (select count(*) from tecnica.puntos where tipo = 'muestreo' and activo and codigo not in ('MUE-9901', 'MUE-9902', 'MUE-9903', v_k)) = v_act_otros, v_r::text);
  perform pg_temp.reg('20.15 cada cambio de «activo» tiene su evento (la regla de la verificación 08)', not exists (select 1 from tecnica.puntos p where p.tipo = 'muestreo'
     and p.activo is distinct from coalesce((select e.tipo <> 'desactivar' from tecnica.punto_eventos e where e.punto_id = p.id order by e.id desc limit 1), p.activo)));
  perform pg_temp.err('20.16 no hay más cargas que revertir', format($$select public.geoportal_redes_carga_revertir(%L, 'muestreo', 'Otra reversa de prueba')$$, a), '22023', 'no tiene una carga publicada');

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 5a (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
