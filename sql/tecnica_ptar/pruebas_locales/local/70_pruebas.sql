-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 70 — PRUEBAS «N de N». Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- Todo es SIMULADO y se deshace: sus personas (prueba.ptar.*), una instalación de prueba (prueba_ptar) y su planta potable de prueba (prueba_ptar_pl),
-- y elementos con código PRUEBA-… Cuenta SOLO sus filas (nada de lo real entra en los conteos). Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · PTAR-1 … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- un polígono de prueba (cuadrado de ~110 m) alrededor de un punto lejos de Valledupar, para no tocar nada real
create function pg_temp.cuadro(p_x numeric, p_y numeric, p_l numeric default 0.001) returns text language sql as $$
  select format('{"type":"Polygon","coordinates":[[[%s,%s],[%s,%s],[%s,%s],[%s,%s],[%s,%s]]]}', p_x, p_y, p_x + p_l, p_y, p_x + p_l, p_y + p_l, p_x, p_y + p_l, p_x, p_y) $$;
create function pg_temp.el(p_inst bigint, p_cod text, p_tipo text, p_geo text, p_desde bigint default null, p_hasta bigint default null, p_reemplaza bigint default null,
                           p_origen text default 'dibujo', p_activo text default null) returns bigint language sql as $$
  insert into tecnica.elementos_planta (instalacion_id, codigo, tipo, nombre, orden, geom, desde_id, hasta_id, activo_codigo, origen, reemplaza_id, creado_por)
  values (p_inst, p_cod, p_tipo, 'Prueba ' || p_cod, 1, st_setsrid(st_geomfromgeojson(p_geo), 4326), p_desde, p_hasta, p_activo, p_origen, p_reemplaza, 'prueba.ptar.carga@emdupar.gov.co')
  returning id $$;

do $prueba$
declare
  adm text := 'prueba.ptar.adm@emdupar.gov.co'; sp text := 'prueba.ptar.sp@emdupar.gov.co'; sr text := 'prueba.ptar.sr@emdupar.gov.co';
  sx text := 'prueba.ptar.sx@emdupar.gov.co'; op text := 'prueba.ptar.op@emdupar.gov.co'; nadie text := 'prueba.ptar.nadie@emdupar.gov.co';
  v_inst bigint; v_ipot bigint; v_pl bigint; v_l1 bigint; v_l2 bigint; v_tr bigint; v_po bigint; v_old bigint; v_new bigint; j jsonb; v_n integer; v_txt text;
  v_aud integer; v_total integer; v_bien integer; v_fallas text;
  pt text := '{"type":"Point","coordinates":[-74.5,4.5]}';
  ln text := '{"type":"LineString","coordinates":[[-74.5,4.5],[-74.499,4.501]]}';
  mono text := '{"type":"Polygon","coordinates":[[[-74.5,4.5],[-74.49,4.51],[-74.49,4.5],[-74.5,4.51],[-74.5,4.5]]]}';   -- corbatín: inválido
begin
  -- ---------- personas de prueba ----------
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTPTAR Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values
    (sp, 'ZTPTAR Supervisor de planta (PTAP)', 'consulta', true, true, 'sin_restriccion', 'todos'),
    (sr, 'ZTPTAR Jefe de la PTAR', 'consulta', true, true, 'sin_restriccion', 'todos'),
    (sx, 'ZTPTAR Supervisor con los dos alcances', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZTPTAR Operador', 'consulta', true, 'sin_restriccion', 'todos');

  -- ---------- 01. Instalaciones (D1) ----------
  perform pg_temp.reg('01.01 tres instalaciones reales: las dos PTAP con su planta y la PTAR sin planta (168 h sin dato)',
    (select count(*) from tecnica.instalaciones where codigo in ('ptap_huaricha', 'ptap_gota_fria', 'ptar')) = 3
    and (select p.codigo from tecnica.instalaciones i join tecnica.plantas p on p.id = i.planta_id where i.codigo = 'ptap_huaricha') = 'huaricha'
    and (select p.codigo from tecnica.instalaciones i join tecnica.plantas p on p.id = i.planta_id where i.codigo = 'ptap_gota_fria') = 'gota_fria'
    and (select planta_id is null and tipo = 'residual' and horas_sin_dato = 168 and nombre = 'PTAR El Salguero' from tecnica.instalaciones where codigo = 'ptar')
    and (select bool_and(horas_sin_dato = 24) from tecnica.instalaciones where tipo = 'potable' and codigo like 'ptap\_%'));
  perform pg_temp.reg('01.02 la PTAR NO es una planta de agua potable (tecnica.plantas sigue con sus filas, sin «ptar»)',
    not exists (select 1 from tecnica.plantas where codigo like '%ptar%'));
  insert into tecnica.plantas (codigo, nombre) values ('prueba_ptar_pl', 'PRUEBA planta potable') returning id into v_pl;
  insert into tecnica.instalaciones (codigo, nombre, tipo, planta_id, horas_sin_dato) values ('prueba_ptar', 'PRUEBA PTAR', 'residual', null, 168) returning id into v_inst;
  insert into tecnica.instalaciones (codigo, nombre, tipo, planta_id, horas_sin_dato) values ('prueba_ptar_pot', 'PRUEBA PTAP', 'potable', v_pl, 24) returning id into v_ipot;
  perform pg_temp.err('01.03 una PTAP sin planta no entra', $$insert into tecnica.instalaciones (codigo, nombre, tipo, horas_sin_dato) values ('prueba_x', 'PRUEBA X', 'potable', 24)$$, '23514');
  perform pg_temp.err('01.04 una PTAR con planta no entra', format($$insert into tecnica.instalaciones (codigo, nombre, tipo, planta_id, horas_sin_dato) values ('prueba_y', 'PRUEBA Y', 'residual', %s, 24)$$,
    (select id from tecnica.plantas where codigo = 'huaricha')), '23514');
  perform pg_temp.err('01.05 una instalación no se borra', format('delete from tecnica.instalaciones where id = %s', v_inst), '42501');
  perform pg_temp.err('01.06 inactiva sin motivo no se acepta', format('update tecnica.instalaciones set activa = false where id = %s', v_ipot), '23514');

  -- ---------- 02. Elementos de la planta (D9, D12) ----------
  v_l1 := pg_temp.el(v_inst, 'PRUEBA-LAG-1', 'laguna', pg_temp.cuadro(-74.5, 4.5));
  v_l2 := pg_temp.el(v_inst, 'PRUEBA-LAG-2', 'laguna', pg_temp.cuadro(-74.498, 4.5));
  v_tr := pg_temp.el(v_inst, 'PRUEBA-TR-1', 'tramo', ln, v_l1, v_l2);
  v_po := pg_temp.el(v_inst, 'PRUEBA-POZ-1', 'pozo', pt, p_origen => 'redes', p_activo => 'POZ-999991');
  perform pg_temp.el(v_inst, 'PRUEBA-PER', 'perimetro', pg_temp.cuadro(-74.501, 4.499, 0.01));
  perform pg_temp.el(v_inst, 'PRUEBA-PM-1', 'punto_medicion', pt);
  perform pg_temp.el(v_inst, 'PRUEBA-COL-1', 'tramo', ln, p_origen => 'redes', p_activo => 'COL-999991');
  perform pg_temp.el(v_inst, 'PRUEBA-VER-1', 'descarga', '{"type":"Point","coordinates":[-74.4995,4.5005]}', p_origen => 'redes', p_activo => 'VER-999991');
  perform pg_temp.err('02.20 una descarga no puede ser una línea', format('select pg_temp.el(%s, %L, %L, %L)', v_inst, 'PRUEBA-X9', 'descarga', ln), '23514', 'elementos_planta_forma');
  perform pg_temp.reg('02.01 se cargan laguna, tramo con desde/hasta, pozo y descarga de redes, perímetro, punto y conducto', (select count(*) from tecnica.elementos_planta where instalacion_id = v_inst) = 8);
  perform pg_temp.err('02.02 una laguna no puede ser un punto', format('select pg_temp.el(%s, %L, %L, %L)', v_inst, 'PRUEBA-X1', 'laguna', pt), '23514', 'elementos_planta_forma');
  perform pg_temp.err('02.03 un pozo no puede ser una línea', format('select pg_temp.el(%s, %L, %L, %L)', v_inst, 'PRUEBA-X2', 'pozo', ln), '23514', 'elementos_planta_forma');
  perform pg_temp.err('02.04 un polígono inválido (corbatín) no entra', format('select pg_temp.el(%s, %L, %L, %L)', v_inst, 'PRUEBA-X3', 'laguna', mono), '23514', 'elementos_planta_valida');
  perform pg_temp.err('02.05 solo un tramo lleva desde/hasta', format('select pg_temp.el(%s, %L, %L, %L, %s)', v_inst, 'PRUEBA-X4', 'pozo', pt, v_l1), '23514', 'elementos_planta_flujo');
  perform pg_temp.err('02.06 lo copiado de redes lleva su activo', format('select pg_temp.el(%s, %L, %L, %L, p_origen => %L)', v_inst, 'PRUEBA-X5', 'pozo', pt, 'redes'), '23514', 'elementos_planta_redes');
  perform pg_temp.err('02.07 el código activo no se repite', format('select pg_temp.el(%s, %L, %L, %L)', v_inst, 'PRUEBA-LAG-1', 'laguna', pg_temp.cuadro(-74.4, 4.4)), '23505');
  perform pg_temp.err('02.08 el mismo activo de redes no se copia dos veces en la planta', format('select pg_temp.el(%s, %L, %L, %L, p_origen => %L, p_activo => %L)', v_inst, 'PRUEBA-X6', 'pozo', pt, 'redes', 'POZ-999991'), '23505');
  perform pg_temp.err('02.09 un tramo no sale de otra planta', format('select pg_temp.el(%s, %L, %L, %L, %s)', v_ipot, 'PRUEBA-X7', 'tramo', ln, v_l1), '22023', 'misma planta');
  perform pg_temp.err('02.10 un elemento no se edita (nombre)', format('update tecnica.elementos_planta set nombre = %L where id = %s', 'Otro nombre', v_l1), '55000');
  perform pg_temp.err('02.11 un elemento no se edita (geometría)', format('update tecnica.elementos_planta set geom = st_translate(geom, 0.0001, 0) where id = %s', v_l1), '55000');
  perform pg_temp.err('02.12 desactivar sin motivo no se acepta', format('update tecnica.elementos_planta set activo = false where id = %s', v_po), '22023', 'motivo');
  update tecnica.elementos_planta set activo = false, motivo_inactivo = 'PRUEBA se corrige el dibujo del pozo' where id = v_po;
  perform pg_temp.reg('02.13 desactivar con motivo: la fecha la pone el servidor', (select not activo and inactivado_en is not null from tecnica.elementos_planta where id = v_po));
  perform pg_temp.err('02.14 un elemento desactivado no se reactiva', format('update tecnica.elementos_planta set activo = true, motivo_inactivo = null, inactivado_en = null where id = %s', v_po), '55000');
  v_new := pg_temp.el(v_inst, 'PRUEBA-POZ-1', 'pozo', '{"type":"Point","coordinates":[-74.5001,4.5001]}', p_reemplaza => v_po, p_origen => 'redes', p_activo => 'POZ-999991');
  perform pg_temp.reg('02.15 reemplazo (D9): fila nueva del mismo código que apunta a la desactivada', (select reemplaza_id = v_po and activo from tecnica.elementos_planta where id = v_new)
    and (select count(*) from tecnica.elementos_planta where codigo = 'PRUEBA-POZ-1') = 2);
  perform pg_temp.err('02.16 no se reemplaza un elemento activo', format('select pg_temp.el(%s, %L, %L, %L, p_reemplaza => %s)', v_inst, 'PRUEBA-LAG-9', 'laguna', pg_temp.cuadro(-74.3, 4.3), v_l2), '22023', 'ya desactivado');
  perform pg_temp.err('02.17 un elemento no se borra', format('delete from tecnica.elementos_planta where id = %s', v_l2), '42501');
  perform pg_temp.err('02.18 los elementos no se vacían', 'truncate tecnica.elementos_planta', '42501');
  perform pg_temp.err('02.19 un elemento nuevo no entra inactivo', format($$insert into tecnica.elementos_planta (instalacion_id, codigo, tipo, nombre, geom, origen, activo, motivo_inactivo, inactivado_en, creado_por)
    values (%s, 'PRUEBA-X8', 'pozo', 'Prueba', st_setsrid(st_geomfromgeojson(%L), 4326), 'dibujo', false, 'PRUEBA nace inactivo, no debe', now(), 'prueba.ptar.carga@emdupar.gov.co')$$, v_inst, pt), '22023');

  -- ---------- 03. Alcance por persona (D6) ----------
  perform pg_temp.reg('03.01 sin eventos: el supervisor tiene PTAP y no PTAR; el administrador, los dos',
    tecnica.f_tiene_alcance(sp, 'ptap') and not tecnica.f_tiene_alcance(sp, 'ptar') and tecnica.f_tiene_alcance(adm, 'ptap') and tecnica.f_tiene_alcance(adm, 'ptar'));
  perform pg_temp.err('03.02 alcance: solo el administrador lo fija', format('select public.geoportal_tec_ptar_alcance_fijar(%L, %L, %L, %L, %L)', sp, sr, 'ptar', 'asignar', 'PRUEBA jefe de la PTAR'), '42501');
  j := public.geoportal_tec_ptar_alcance_fijar(adm, upper(sr), 'PTAR', 'asignar', 'PRUEBA se nombra jefe de la PTAR', '10.0.0.1');
  perform pg_temp.reg('03.03 asignar PTAR al jefe (correo en mayúsculas se normaliza)', (j ->> 'ptar')::boolean and (j ->> 'ptap')::boolean and j ->> 'persona' = sr, j::text);
  j := public.geoportal_tec_ptar_alcance_fijar(adm, sr, 'ptap', 'quitar', 'PRUEBA el jefe de la PTAR no ve la PTAP');
  perform pg_temp.reg('03.04 quitar PTAP al jefe de la PTAR', (j ->> 'ptar')::boolean and not (j ->> 'ptap')::boolean, j::text);
  perform public.geoportal_tec_ptar_alcance_fijar(adm, sx, 'ptar', 'asignar', 'PRUEBA supervisor con los dos alcances');
  perform pg_temp.err('03.05 asignar lo que ya tiene: error', format('select public.geoportal_tec_ptar_alcance_fijar(%L, %L, %L, %L, %L)', adm, sr, 'ptar', 'asignar', 'PRUEBA otra vez lo mismo'), '22023', 'ya tiene');
  perform pg_temp.err('03.06 al administrador no se le fija alcance', format('select public.geoportal_tec_ptar_alcance_fijar(%L, %L, %L, %L, %L)', adm, adm, 'ptap', 'quitar', 'PRUEBA quitarle al admin'), '22023', 'administrador');
  perform pg_temp.err('03.07 a quien no tiene Técnica no se le fija', format('select public.geoportal_tec_ptar_alcance_fijar(%L, %L, %L, %L, %L)', adm, nadie, 'ptar', 'asignar', 'PRUEBA persona sin Técnica'), '22023', 'no tiene acceso');
  perform pg_temp.err('03.08 alcance desconocido', format('select public.geoportal_tec_ptar_alcance_fijar(%L, %L, %L, %L, %L)', adm, sp, 'aseo', 'asignar', 'PRUEBA alcance que no existe'), '22023', 'PTAP o PTAR');
  perform pg_temp.err('03.09 motivo corto', format('select public.geoportal_tec_ptar_alcance_fijar(%L, %L, %L, %L, %L)', adm, sp, 'ptar', 'asignar', 'corto'), '22023', 'motivo');
  perform pg_temp.reg('03.10 los tres cambios de alcance de prueba quedan auditados',
    (select count(*) from public.geoportal_auditoria where accion = 'tec_ptar_alcance' and referencia in (sr, sx)) = 3);
  perform pg_temp.err('03.11 un evento de alcance no se edita', format('update tecnica.alcance_eventos set motivo = %L where persona = %L', 'PRUEBA cambiar el motivo', sr), '42501');
  j := public.geoportal_tec_ptar_alcances(adm);
  perform pg_temp.reg('03.12 la lista de alcances (solo el administrador) trae a los de prueba con su vigente',
    exists (select 1 from jsonb_array_elements(j -> 'personas') x where x ->> 'persona' = sr and (x ->> 'ptar')::boolean and not (x ->> 'ptap')::boolean)
    and exists (select 1 from jsonb_array_elements(j -> 'personas') x where x ->> 'persona' = sx and (x ->> 'ptar')::boolean and (x ->> 'ptap')::boolean));
  perform pg_temp.err('03.13 la lista de alcances: el supervisor no', format('select public.geoportal_tec_ptar_alcances(%L)', sx), '42501');

  -- ---------- 04. La puerta de la PTAP (f_autorizar_supervision con el alcance) ----------
  perform pg_temp.reg('04.01 el supervisor de siempre sigue entrando al Dashboard PTAP (químicos)', (select public.geoportal_tec_quimicos_catalogo(sp) is not null));
  perform pg_temp.reg('04.02 el de los dos alcances también', (select public.geoportal_tec_quimicos_catalogo(sx) is not null));
  perform pg_temp.err('04.03 el jefe de la PTAR (sin PTAP) no entra a lo de la PTAP', format('select public.geoportal_tec_quimicos_catalogo(%L)', sr), '42501', 'PTAR');
  perform pg_temp.err('04.04 el operador sigue sin entrar (no tiene Dashboard técnico)', format('select public.geoportal_tec_quimicos_catalogo(%L)', op), '42501');
  perform pg_temp.reg('04.05 el administrador entra', (select public.geoportal_tec_quimicos_catalogo(adm) is not null));

  -- ---------- 05. Perfil ----------
  j := public.geoportal_tec_ptar_perfil(sp);
  perform pg_temp.reg('05.01 perfil del supervisor de planta: PTAP sí, PTAR no, y solo sus instalaciones', (j ->> 'ptap')::boolean and not (j ->> 'ptar')::boolean
    and not exists (select 1 from jsonb_array_elements(j -> 'instalaciones') x where x ->> 'tipo' = 'residual'), j::text);
  j := public.geoportal_tec_ptar_perfil(sr);
  perform pg_temp.reg('05.02 perfil del jefe de la PTAR: PTAR sí, PTAP no; solo instalaciones residuales', (j ->> 'ptar')::boolean and not (j ->> 'ptap')::boolean
    and exists (select 1 from jsonb_array_elements(j -> 'instalaciones') x where x ->> 'codigo' = 'ptar')
    and not exists (select 1 from jsonb_array_elements(j -> 'instalaciones') x where x ->> 'tipo' = 'potable'), j::text);
  j := public.geoportal_tec_ptar_perfil(op);
  perform pg_temp.reg('05.03 perfil del operador: ni PTAP ni PTAR (no tiene Dashboard)', j ->> 'perfil' = 'operador' and not (j ->> 'ptap')::boolean and not (j ->> 'ptar')::boolean, j::text);
  j := public.geoportal_tec_ptar_perfil(adm);
  perform pg_temp.reg('05.04 perfil del administrador: los dos', (j ->> 'ptap')::boolean and (j ->> 'ptar')::boolean and (j ->> 'admin')::boolean);
  perform pg_temp.err('05.05 sin acceso a Técnica: 42501', format('select public.geoportal_tec_ptar_perfil(%L)', nadie), '42501');
  perform pg_temp.err('05.06 sin correo: 28000', 'select public.geoportal_tec_ptar_perfil(null)', '28000');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, motivo, autor) values (sx, 'desactivar_tecnica', 'PRUEBA se desactiva', adm);
  j := public.geoportal_tec_ptar_perfil(sx);
  perform pg_temp.reg('05.07 con Técnica desactivada: ni PTAP ni PTAR', not (j ->> 'activa')::boolean and not (j ->> 'ptap')::boolean and not (j ->> 'ptar')::boolean, j::text);
  perform pg_temp.err('05.08 con Técnica desactivada no ve el mapa', format('select public.geoportal_tec_ptar_mapa(%L, %L)', sx, 'prueba_ptar'), '42501', 'desactivado');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, motivo, autor) values (sx, 'activar_tecnica', 'PRUEBA se reactiva', adm);

  -- ---------- 06. Mapa ----------
  perform public.geoportal_tec_ptar_alias_fijar(sr, 'prueba-lag-1', 'Anaerobia N1', 'PRUEBA el jefe le pone el nombre corto');
  j := public.geoportal_tec_ptar_mapa(sr, 'prueba_ptar');
  perform pg_temp.reg('06.01 el jefe de la PTAR ve el mapa: 8 activos de su planta (el desactivado no sale; el que lo reemplaza sí)', (j ->> 'total')::integer = 8
    and (j -> 'por_tipo' ->> 'laguna')::integer = 2 and (j -> 'por_tipo' ->> 'tramo')::integer = 2 and (j -> 'por_tipo' ->> 'pozo')::integer = 1 and (j -> 'por_tipo' ->> 'descarga')::integer = 1
    and (select count(*) from jsonb_array_elements(j -> 'elementos' -> 'features') f where (f -> 'properties' ->> 'codigo') = 'PRUEBA-POZ-1' and (f ->> 'id')::bigint = v_new) = 1, (j - 'elementos')::text);
  perform pg_temp.reg('06.02 orden de dibujo: el perímetro primero, los puntos al final; con el alias y el estado «sin_variables»',
    j -> 'elementos' -> 'features' -> 0 -> 'properties' ->> 'tipo' = 'perimetro'
    and j -> 'elementos' -> 'features' -> 7 -> 'properties' ->> 'tipo' = 'punto_medicion'
    and exists (select 1 from jsonb_array_elements(j -> 'elementos' -> 'features') f where f -> 'properties' ->> 'codigo' = 'PRUEBA-LAG-1' and f -> 'properties' ->> 'alias' = 'Anaerobia N1')
    and (select bool_and(f -> 'properties' ->> 'estado' = 'sin_variables') from jsonb_array_elements(j -> 'elementos' -> 'features') f));
  perform pg_temp.reg('06.03 la caja del mapa encierra el perímetro de prueba', (j -> 'caja' ->> 0)::numeric <= -74.501 and (j -> 'caja' ->> 3)::numeric >= 4.509, j ->> 'caja');
  perform pg_temp.reg('06.04 sin datos del suscriptor ni términos tarifarios en el mapa', (j::text !~* 'suscriptor|tarifa|estrato|subsidio|telefono|teléfono'));
  perform pg_temp.err('06.05 el supervisor de la PTAP no ve el mapa de la PTAR', format('select public.geoportal_tec_ptar_mapa(%L, %L)', sp, 'prueba_ptar'), '42501', 'PTAR');
  perform pg_temp.err('06.06 el jefe de la PTAR no ve el mapa de una PTAP', format('select public.geoportal_tec_ptar_mapa(%L, %L)', sr, 'prueba_ptar_pot'), '42501');
  perform pg_temp.reg('06.07 el supervisor de la PTAP sí ve el de una PTAP (vacío)', (public.geoportal_tec_ptar_mapa(sp, 'prueba_ptar_pot') ->> 'total')::integer = 0);
  perform pg_temp.err('06.08 instalación que no existe: 404', format('select public.geoportal_tec_ptar_mapa(%L, %L)', sr, 'no_existe'), 'P0002');
  perform pg_temp.err('06.09 el operador no ve el mapa', format('select public.geoportal_tec_ptar_mapa(%L, %L)', op, 'prueba_ptar'), '42501');

  -- ---------- 07. Ficha de un elemento ----------
  j := public.geoportal_tec_ptar_elemento(sr, 'prueba-tr-1');
  perform pg_temp.reg('07.01 ficha de un tramo: longitud, desde y hasta, sin variables', j ->> 'tipo' = 'tramo' and (j -> 'medida' ->> 'longitud_m')::numeric > 100
    and j -> 'desde' ->> 'codigo' = 'PRUEBA-LAG-1' and j -> 'hasta' ->> 'codigo' = 'PRUEBA-LAG-2' and j ->> 'estado' = 'sin_variables' and jsonb_array_length(j -> 'indicadores') = 0, j::text);
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA-LAG-1');
  perform pg_temp.reg('07.02 ficha de una laguna: área, alias y su historial', (j -> 'medida' ->> 'area_m2')::numeric between 11000 and 13000 and j ->> 'alias' = 'Anaerobia N1'
    and jsonb_array_length(j -> 'alias_historial') = 1, j::text);
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA-POZ-1');
  perform pg_temp.reg('07.03 ficha de un pozo copiado: su activo de redes, 2 versiones, coordenadas', j ->> 'activo' = 'POZ-999991' and (j ->> 'versiones')::integer = 2
    and (j -> 'medida' ->> 'lat')::numeric = 4.5001, j::text);
  perform pg_temp.err('07.04 código no válido', format('select public.geoportal_tec_ptar_elemento(%L, %L)', sr, 'x; drop'), '22023');
  perform pg_temp.err('07.05 elemento que no existe: 404', format('select public.geoportal_tec_ptar_elemento(%L, %L)', sr, 'PRUEBA-NADA'), 'P0002');
  perform pg_temp.err('07.06 el supervisor de la PTAP no abre un elemento de la PTAR', format('select public.geoportal_tec_ptar_elemento(%L, %L)', sp, 'PRUEBA-LAG-1'), '42501');

  -- ---------- 08. Alias ----------
  perform pg_temp.err('08.01 el mismo alias otra vez: error', format('select public.geoportal_tec_ptar_alias_fijar(%L, %L, %L, %L)', sr, 'PRUEBA-LAG-1', 'Anaerobia N1', 'PRUEBA otra vez lo mismo'), '22023', 'ya tiene');
  perform pg_temp.err('08.02 alias de más de 60 caracteres', format('select public.geoportal_tec_ptar_alias_fijar(%L, %L, %L, %L)', sr, 'PRUEBA-LAG-2', repeat('a', 61), 'PRUEBA alias muy largo'), '22023', '60');
  perform pg_temp.err('08.03 alias con salto de línea', format('select public.geoportal_tec_ptar_alias_fijar(%L, %L, %L, %L)', sr, 'PRUEBA-LAG-2', E'A\nB', 'PRUEBA alias con salto'), '22023');
  perform pg_temp.err('08.04 motivo corto', format('select public.geoportal_tec_ptar_alias_fijar(%L, %L, %L, %L)', sr, 'PRUEBA-LAG-2', 'Otra', 'corto'), '22023', 'motivo');
  perform pg_temp.err('08.05 el supervisor de la PTAP no pone alias en la PTAR', format('select public.geoportal_tec_ptar_alias_fijar(%L, %L, %L, %L)', sp, 'PRUEBA-LAG-2', 'Otra', 'PRUEBA sin el alcance'), '42501');
  j := public.geoportal_tec_ptar_alias_fijar(sr, 'PRUEBA-LAG-1', '  ', 'PRUEBA se quita el alias');
  perform pg_temp.reg('08.06 alias vacío = quitar; queda el historial', j ->> 'antes' = 'Anaerobia N1' and j -> 'alias' = 'null'::jsonb
    and tecnica.f_alias_vigente(v_inst, 'PRUEBA-LAG-1') is null and (select count(*) from tecnica.elemento_alias_eventos where instalacion_id = v_inst) = 2, j::text);
  perform pg_temp.err('08.07 quitar cuando no tiene: error', format('select public.geoportal_tec_ptar_alias_fijar(%L, %L, %L, %L)', sr, 'PRUEBA-LAG-1', '', 'PRUEBA quitar otra vez'), '22023', 'no tiene alias');
  perform pg_temp.reg('08.08 los cambios de alias quedan auditados', (select count(*) from public.geoportal_auditoria where accion = 'tec_ptar_alias' and referencia = 'PRUEBA-LAG-1') = 2);
  perform pg_temp.err('08.09 un evento de alias no se edita', format('update tecnica.elemento_alias_eventos set alias = %L where instalacion_id = %s', 'X', v_inst), '42501');
  perform pg_temp.reg('08.10 el alias sigue a la pieza por su código (sirve después de un reemplazo)', (select count(distinct codigo) from tecnica.elemento_alias_eventos where instalacion_id = v_inst) = 1);

  -- ---------- 09. Lo que no cambia ----------
  perform pg_temp.reg('09.01 la huella de redes no cambia (1ba192724c2fddcf321104700829f3cc)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
      where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '1ba192724c2fddcf321104700829f3cc');
  perform pg_temp.reg('09.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));
  perform pg_temp.reg('09.03 las 6 RPC: EXECUTE solo para service_role (ni public, ni anon, ni authenticated)',
    (select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute'))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_ptar\_%')
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_ptar\_%') = 6);
  perform pg_temp.reg('09.04 las funciones internas: sin EXECUTE para los roles de la API',
    (select bool_and(not has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute'))
       from pg_proc p where p.pronamespace = 'tecnica'::regnamespace and p.proname in ('f_tiene_alcance', 'f_autorizar_ptar', 'f_autorizar_instalacion', 'f_alias_vigente', 'f_instalacion', 'f_elemento_coherente', 'f_elemento_protegido', 'f_tipo_elemento_texto')));
  perform pg_temp.reg('09.05 las 4 tablas nuevas: sin privilegios para los roles de la API y con RLS',
    (select bool_and(not has_table_privilege(r, c.oid, 'select') and not has_table_privilege(r, c.oid, 'insert') and not has_table_privilege(r, c.oid, 'update') and c.relrowsecurity)
       from pg_class c cross join (values ('anon'), ('authenticated'), ('service_role')) x(r)
      where c.oid in ('tecnica.instalaciones'::regclass, 'tecnica.elementos_planta'::regclass, 'tecnica.elemento_alias_eventos'::regclass, 'tecnica.alcance_eventos'::regclass)));
  perform pg_temp.reg('09.06 ninguna tabla existente cambió de columnas (plantas, puntos, registros, referencias)',
    (select count(*) from pg_attribute where attrelid in ('tecnica.plantas'::regclass, 'tecnica.puntos'::regclass, 'tecnica.registros'::regclass, 'tecnica.referencias'::regclass)
       and attnum > 0 and not attisdropped) = 44);
  perform pg_temp.reg('09.07 f_autorizar_supervision conserva sus privilegios', not has_function_privilege('anon', 'tecnica.f_autorizar_supervision(text)'::regprocedure, 'execute'));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · PTAR-1 (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total,
    case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
