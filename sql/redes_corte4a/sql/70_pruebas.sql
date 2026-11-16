-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 15, 24, 25, 26 y 40, en la misma transacción.
-- Como las del 3a y el 3b: corre después de la carga real y de los cortes publicados; NO supone códigos ni conteos de la base. Arma su red de prueba
-- (ID 99500xx, LABEL ZT5-…) con el motor del 1a. Termina con un ERROR a propósito que deshace todo y trae el informe.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 4a … RESULTADO: N de N pruebas correctas — SIN FALLAS
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

do $prueba$
declare
  a text := 'prueba.redes5.adm@emdupar.gov.co'; sv text := 'prueba.redes5.sup@emdupar.gov.co'; op text := 'prueba.redes5.op@emdupar.gov.co';
  sf text := 'prueba.redes5.sinform@emdupar.gov.co'; na text := 'prueba.redes5.nada@emdupar.gov.co'; sd text := 'prueba.redes5.dist@emdupar.gov.co';
  sr text := 'prueba.redes5.soloredes@emdupar.gov.co';
  v_red1 text; v_red2 text; v_val text; v_acc text; v_tor text; v_poz1 text; v_poz2 text; v_col text;
  v_c bigint; v_r jsonb; v_x jsonb; v_p jsonb; v_d1 text; v_d2 text; v_d3 text; v_dn text; v_i1 text; v_in text; v_rep uuid;
  v_total integer; v_bien integer; v_fallas text;
  w1 text := 'LINESTRING(' || pg_temp.p(0, 0) || ',' || pg_temp.p(100, 0) || ')';
  w2 text := 'LINESTRING(' || pg_temp.p(100, 0) || ',' || pg_temp.p(200, 0) || ')';
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos'),
    (sr, 'Solo dashboard de redes', 'consulta', false, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'Operador', 'consulta', true, 'sin_restriccion', 'todos'),
    (sf, 'Operador sin el formulario', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'mantenimiento', a), (op, 'asignar_formulario', 'danos_fallas', a),
    (sf, 'asignar_formulario', 'danos_fallas', a);

  -- red de prueba con el motor del 1a: 2 tramos de acueducto (V995 → Tee-995 → Torre-995) y 2 pozos con un conducto
  v_c := (public.geoportal_redes_carga_iniciar(a, 'acueducto', pg_temp.sha('zt5-acu'), 'shp', 4326, 'ID', 2) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    pg_temp.tramo(1, 9950001, 'Distribucion-ZT51', '99501', 'V995', '99502', 'Tee-995', w1), pg_temp.tramo(2, 9950002, 'Lateral-ZT52', '99502', 'Tee-995', '99503', 'Torre-995', w2)));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Red de prueba del Corte 4a');
  v_c := (public.geoportal_redes_carga_iniciar(a, 'alc_pozos', pg_temp.sha('zt5-poz'), 'shp', 4326, 'LABEL', 2) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    jsonb_build_object('orden', 1, 'wkt', 'POINT(' || pg_temp.p(0, 300) || ')', 'atributos', jsonb_build_object('LABEL', 'ZT5-PA', 'EST_POZO', 'VISIBLE', 'ESTADO', 'Existente', 'C_RASANTE', 100, 'C_FONDO', 98)),
    jsonb_build_object('orden', 2, 'wkt', 'POINT(' || pg_temp.p(100, 300) || ')', 'atributos', jsonb_build_object('LABEL', 'ZT5-PB', 'EST_POZO', 'VISIBLE', 'ESTADO', 'Existente', 'C_RASANTE', 100, 'C_FONDO', 97))));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Pozos de prueba del Corte 4a');
  v_c := (public.geoportal_redes_carga_iniciar(a, 'alc_conductos', pg_temp.sha('zt5-con'), 'shp', 4326, 'LABEL', 1) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(jsonb_build_object('orden', 1, 'wkt', 'LINESTRING(' || pg_temp.p(0, 300) || ',' || pg_temp.p(100, 300) || ')',
    'atributos', jsonb_build_object('LABEL', 'ZT5-PA-PB', 'PZ_INICIAL', 'ZT5-PA', 'PZ_FINAL', 'ZT5-PB', 'MATERIAL', 'PVC', 'DIAMETRO', 200, 'ESTADO', 'Existente'))));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Conducto de prueba del Corte 4a');
  select codigo into v_red1 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9950001';
  select codigo into v_red2 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9950002';
  select codigo into v_val from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99501';
  select codigo into v_acc from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99502';
  select codigo into v_tor from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99503';
  select codigo into v_poz1 from redes.v_activo_vigente where capa_codigo = 'alc_pozos' and llave_capa = 'ZT5-PA';
  select codigo into v_poz2 from redes.v_activo_vigente where capa_codigo = 'alc_pozos' and llave_capa = 'ZT5-PB';
  select codigo into v_col from redes.v_activo_vigente where capa_codigo = 'alc_conductos' and llave_capa = 'ZT5-PA-PB';
  perform set_config('zt.red1', v_red1, true);
  perform pg_temp.reg('00.01 red de prueba: 2 RED, VAL, ACC, TOR, 2 POZ y COL, encontrados por su llave',
     v_red1 like 'RED-%' and v_red2 like 'RED-%' and v_val like 'VAL-%' and v_acc like 'ACC-%' and v_tor like 'TOR-%' and v_poz1 like 'POZ-%' and v_poz2 like 'POZ-%' and v_col like 'COL-%'
     and (select count(*) from redes.activo_vigente_mat where codigo in (v_red1, v_red2, v_val, v_acc, v_tor, v_poz1, v_poz2, v_col) and not retirado) = 8,
     concat_ws(' ', v_red1, v_red2, v_val, v_acc, v_tor, v_poz1, v_poz2, v_col));
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a), (op, 'asignar_formulario', 'mantenimiento', a);

  -- ---------- 01 Permiso nuevo ver_dashboard_redes en las 4 funciones de permisos ----------
  perform pg_temp.reg('01.01 geoportal_puede(dashboard_redes): el supervisor de distribución y el administrador sí; el de planta y el operador no',
     public.geoportal_puede(sd, 'dashboard_redes') and public.geoportal_puede(a, 'dashboard_redes') and not public.geoportal_puede(sv, 'dashboard_redes') and not public.geoportal_puede(op, 'dashboard_redes')
     and public.geoportal_puede(sv, 'dashboard_tecnico') and not public.geoportal_puede(sd, 'dashboard_tecnico'));
  perform pg_temp.reg('01.02 mis_permisos: dashboard_redes y torre_b (también para quien solo tiene el dashboard de redes)', (public.geoportal_mis_permisos(sd) ->> 'dashboard_redes')::boolean
     and (public.geoportal_mis_permisos(sr) ->> 'torre_b')::boolean and not (public.geoportal_mis_permisos(sv) ->> 'dashboard_redes')::boolean
     and (public.geoportal_mis_permisos(a) ->> 'dashboard_redes')::boolean and public.geoportal_mis_permisos('nadie.nunca@emdupar.gov.co') ? 'dashboard_redes');
  perform pg_temp.reg('01.03 admin_permisos: una sola firma, de 20 parámetros (la de 19 ya no existe)', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'geoportal_admin_permisos') = 1
     and to_regprocedure('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean)') is null
     and to_regprocedure('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)') is not null);
  perform public.geoportal_admin_permisos(a, op, false, false, false, false, 'sin_restriccion', 'todos', false, null, null, '10.0.0.5', null, null, null, null, null, null, null, true);
  perform pg_temp.reg('01.04 el administrador da el permiso con p_dashboard_redes: queda en la lista y en la auditoría (antes y después)', (select ver_dashboard_redes from public.geoportal_lista_blanca where email = op)
     and exists (select 1 from public.geoportal_auditoria where accion = 'admin_cambiar_permisos' and referencia = op and (detalle -> 'despues' ->> 'ver_dashboard_redes')::boolean
                  and not (detalle -> 'antes' ->> 'ver_dashboard_redes')::boolean));
  perform public.geoportal_admin_permisos(a, op, false, false, false, false, 'sin_restriccion', 'todos', false, null, null, null, null, null, null, null, null, null, null, false);
  perform pg_temp.reg('01.05 sin p_dashboard_redes (nulo) no se toca; con falso se quita', not (select ver_dashboard_redes from public.geoportal_lista_blanca where email = op)
     and (select ver_registro_tecnico from public.geoportal_lista_blanca where email = op));
  perform pg_temp.err('01.06 un no administrador no da permisos', format($$select public.geoportal_admin_permisos(%L, %L, false, false, false, false, 'laboral', 'habiles', false, null, null, null, null, null, null, null, null, null, null, true)$$, sd, op), null, 'No autorizado');
  perform pg_temp.reg('01.07 admin_listar trae la columna ver_dashboard_redes', exists (select 1 from public.geoportal_admin_listar(a) l where l.email = sd and l.ver_dashboard_redes));
  perform pg_temp.reg('01.08 la columna nueva nace en falso para todos (sin marcado inicial)', (select column_default from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_lista_blanca'
     and column_name = 'ver_dashboard_redes') = 'false');

  -- ---------- 02 Perfiles de redes (§16) ----------
  perform pg_temp.reg('02.01 mi_perfil: distribución = supervisor; planta = operador en redes (con su Dashboard PTAP); administrador = admin',
     public.geoportal_redes_mi_perfil(sd) ->> 'perfil' = 'supervisor' and (public.geoportal_redes_mi_perfil(sd) ->> 'dashboard_redes')::boolean
     and public.geoportal_redes_mi_perfil(sv) ->> 'perfil' = 'operador' and (public.geoportal_redes_mi_perfil(sv) ->> 'dashboard_ptap')::boolean and not (public.geoportal_redes_mi_perfil(sv) ->> 'dashboard_redes')::boolean
     and public.geoportal_redes_mi_perfil(a) ->> 'perfil' = 'admin' and public.geoportal_redes_mi_perfil(op) ->> 'perfil' = 'operador');
  perform pg_temp.reg('02.02 quien solo tiene el dashboard de redes también es supervisor de distribución', public.geoportal_redes_mi_perfil(sr) ->> 'perfil' = 'supervisor');
  perform pg_temp.err('02.03 sin Técnica ni redes: 42501', format($$select public.geoportal_redes_mi_perfil(%L)$$, na), '42501');
  perform pg_temp.reg('02.04 el origen del activo en la ficha: lo ve el supervisor de distribución; ya no el de planta', public.geoportal_redes_activo(sd, v_red1) -> 'origen' is not null
     and public.geoportal_redes_activo(sv, v_red1) -> 'origen' is null);

  -- ---------- 03 Captura: el supervisor de distribución pasa sin el formulario asignado ----------
  v_r := public.geoportal_redes_formulario_intervencion(sd);
  perform pg_temp.reg('03.01 formulario de intervención del supervisor de distribución: perfil supervisor, pone valores, sin tope y al menos 1 foto (§25.8)',
     v_r ->> 'perfil' = 'supervisor' and (v_r -> 'reglas' ->> 'pone_valores')::boolean and v_r -> 'reglas' -> 'max_horas' = 'null'::jsonb
     and (v_r -> 'reglas' ->> 'min_fotos')::integer = 1 and not (v_r -> 'reglas' ->> 'puede_sin_fotos')::boolean, (v_r -> 'reglas' || jsonb_build_object('perfil', v_r ->> 'perfil'))::text);
  perform pg_temp.reg('03.02 el supervisor de distribución abre el formulario de daño sin tenerlo asignado', public.geoportal_redes_formulario_dano(sd) ? 'tipos');
  v_r := public.geoportal_redes_formulario_intervencion(sv);
  perform pg_temp.reg('03.03 el supervisor de planta sigue abriendo el formulario (regla de Técnica), pero en redes es operador: no pone valores y tiene tope',
     v_r ->> 'perfil' = 'operador' and not (v_r -> 'reglas' ->> 'pone_valores')::boolean and (v_r -> 'reglas' ->> 'max_horas')::integer = 72);
  perform pg_temp.err('03.04 operador sin el formulario: 42501', format($$select public.geoportal_redes_formulario_intervencion(%L)$$, sf), '42501');

  -- ---------- 04 Nadie registra «sin evidencia fotográfica» (§25.8) ----------
  perform pg_temp.err('04.01 el administrador no prepara un daño sin fotos', format($$select public.geoportal_redes_preparar_dano(%L, 0)$$, a), '22023', 'de 1 a 6 fotos');
  perform pg_temp.err('04.02 el supervisor de distribución tampoco', format($$select public.geoportal_redes_preparar_dano(%L, 0)$$, sd), '22023', 'de 1 a 6 fotos');
  perform pg_temp.err('04.03 ni una intervención sin fotos', format($$select public.geoportal_redes_preparar_intervencion(%L, 0)$$, a), '22023', 'de 1 a 9 fotos');
  v_p := public.geoportal_redes_preparar_dano(sd, 1); perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  perform pg_temp.err('04.04 con foto y el motivo «sin evidencia»: se rechaza con un mensaje claro', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, sd, v_p ->> 'dano_id',
     jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', v_red1, 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(40), 'ubicacion_origen', 'gps', 't_detectado', pg_temp.iso('-2 hours'),
       'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida', 'sin_evidencia_motivo', 'Llegó por la línea 116',
       'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))), '22023', 'Ya no se registra');
  v_p := pg_temp.preparar(sd, 1);
  perform pg_temp.err('04.05 el supervisor manda una intervención sin la foto preparada: «Tome al menos 1 foto»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sd, v_p ->> 'intervencion_id',
     pg_temp.itv('[]'::jsonb)), '22023', 'Tome al menos 1 foto');

  -- ---------- 05 Sector: número del 1 al 100 (§25.1) ----------
  v_d1 := pg_temp.dano(op, '{"sector": 3}') ->> 'codigo';
  perform pg_temp.reg('05.01 el daño guarda el sector 3 como número; el texto viejo queda vacío', (select sector_num || '|' || coalesce(sector_texto, '∅') from redes.danos where codigo = v_d1) = '3|∅');
  perform pg_temp.err('05.02 sector 0', format($$select pg_temp.dano(%L, '{"sector": 0}')$$, op), '22023', 'del 1 al 100');
  perform pg_temp.err('05.03 sector 101', format($$select pg_temp.dano(%L, '{"sector": 101}')$$, op), '22023', 'del 1 al 100');
  perform pg_temp.err('05.04 sector como texto', format($$select pg_temp.dano(%L, '{"sector": "3"}')$$, op), '22023', 'del 1 al 100');
  perform pg_temp.err('05.05 sector con decimales', format($$select pg_temp.dano(%L, '{"sector": 2.5}')$$, op), '22023', 'del 1 al 100');
  v_x := pg_temp.dano(op, '{}');
  perform pg_temp.reg('05.06 sin sector, como antes', (select sector_num is null from redes.danos where codigo = v_x ->> 'codigo'));
  perform pg_temp.err('05.07 la regla de la tabla también lo exige', $$insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor, sector_num)
     select gen_random_uuid(), 'DAN-999998', 'dano', 'fuga', 'acueducto', activo_id, 10.47, -73.24, 'gps', now(), 'bajo', 'desconocida', 'x', 200 from redes.danos limit 1$$, '23514');

  -- ---------- 06 Los valores de los recursos los pone el supervisor de DISTRIBUCIÓN ----------
  v_p := pg_temp.preparar(sd, 1);
  v_r := public.geoportal_redes_crear_intervencion(sd, (v_p ->> 'intervencion_id')::uuid, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'),
            '{"fuentes": [{"aportante": "emdupar", "valor": 1200000, "soporte": "Presupuesto 2026"}]}'));
  perform pg_temp.reg('06.01 el supervisor de distribución registra con valores: recursos completos', v_r ->> 'recursos' = 'completos', v_r::text);
  v_p := pg_temp.preparar(sv, 1);
  perform pg_temp.err('06.02 el de planta ya no pone valores en redes', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sv, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), '{"fuentes": [{"aportante": "emdupar", "valor": 1}]}')), '22023', 'los pone el supervisor');

  -- ---------- 07 Daños y fallas: lista y eventos con motivo ----------
  perform pg_temp.err('07.01 el operador no ve la lista', format($$select public.geoportal_redes_danos(%L)$$, op), '42501');
  perform pg_temp.err('07.02 el de planta tampoco', format($$select public.geoportal_redes_danos(%L)$$, sv), '42501');
  v_r := public.geoportal_redes_danos(sd, 'abiertos', 300);
  perform pg_temp.reg('07.03 «abiertos»: el daño con su sector, fotos, tipo y estado; sin autor del tercero', exists (select 1 from jsonb_array_elements(v_r -> 'danos') x where x ->> 'codigo' = v_d1
     and (x ->> 'sector')::integer = 3 and (x ->> 'fotos')::integer = 1 and x ->> 'estado' = 'reportado' and not (x ->> 'tiene_tercero')::boolean), left(v_r::text, 400));
  perform pg_temp.err('07.04 ocultar sin motivo', format($$select public.geoportal_redes_dano_evento(%L, %L, 'ocultar', 'x')$$, sd, v_d1), '22023', 'motivo');
  v_r := public.geoportal_redes_dano_evento(sd, lower(v_d1), 'ocultar', 'Dato de prueba del 15-nov (celular)');
  perform pg_temp.reg('07.05 ocultar con motivo: queda «oculto», sale de la epicrisis y entra a «ocultos»; el daño no se cambia', v_r ->> 'estado' = 'oculto'
     and not exists (select 1 from redes.v_epicrisis where clase = 'dano' and resumen like v_d1 || ' %')
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_danos(sd, 'ocultos') -> 'danos') x where x ->> 'codigo' = v_d1));
  perform pg_temp.err('07.06 ocultar dos veces', format($$select public.geoportal_redes_dano_evento(%L, %L, 'ocultar', 'Otra vez de prueba')$$, sd, v_d1), '22023', 'ya está oculto');
  perform pg_temp.reg('07.07 reincluir lo devuelve a «reportado»', public.geoportal_redes_dano_evento(a, v_d1, 'reincluir', 'No era de prueba, era real') ->> 'estado' = 'reportado');
  v_d2 := pg_temp.dano(op, jsonb_build_object('t_inicio_reparacion', pg_temp.iso('-3 hours'), 't_restablecido', pg_temp.iso('-2 hours'))) ->> 'codigo';
  perform pg_temp.err('07.08 reabrir un daño que no está atendido', format($$select public.geoportal_redes_dano_evento(%L, %L, 'reabrir', 'Volvió a salir agua')$$, sd, v_d1), '22023', 'Solo se reabre');
  v_r := public.geoportal_redes_dano_evento(sd, v_d2, 'reabrir', 'Volvió a salir agua en el mismo punto');
  perform pg_temp.reg('07.09 reabrir un daño atendido lo deja «en atención» y vuelve a «abiertos»', v_r ->> 'estado' = 'en_atencion'
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_danos(sd, 'abiertos', 300) -> 'danos') x where x ->> 'codigo' = v_d2), v_r::text);
  perform pg_temp.err('07.10 el operador no oculta daños', format($$select public.geoportal_redes_dano_evento(%L, %L, 'ocultar', 'Dato de prueba del operador')$$, op, v_d2), '42501');

  -- ---------- 08 Nombre o placa del tercero: supervisor de distribución y administrador, lectura auditada ----------
  v_d3 := pg_temp.dano(op, '{"causa_clase": "terceros", "tercero_tipo": "vehiculo", "tercero_nombre": "Placa ZT5-999"}') ->> 'codigo';
  perform pg_temp.reg('08.01 la lista dice que tiene tercero, sin el nombre', exists (select 1 from jsonb_array_elements(public.geoportal_redes_danos(sd, 'abiertos', 300) -> 'danos') x where x ->> 'codigo' = v_d3
     and (x ->> 'tiene_tercero')::boolean) and public.geoportal_redes_danos(sd, 'abiertos', 300)::text not like '%ZT5-999%');
  v_r := public.geoportal_redes_dano_tercero(sd, v_d3);
  perform pg_temp.reg('08.02 el supervisor de distribución lo lee; la lectura queda auditada sin el valor', v_r ->> 'tercero' = 'Placa ZT5-999'
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_ver_tercero' and referencia = v_d3 and email = sd and detalle::text not like '%ZT5%'));
  perform pg_temp.reg('08.03 el administrador también', public.geoportal_redes_dano_tercero(a, v_d3) ->> 'tercero' = 'Placa ZT5-999');
  perform pg_temp.err('08.04 el de planta no', format($$select public.geoportal_redes_dano_tercero(%L, %L)$$, sv, v_d3), '42501');
  perform pg_temp.err('08.05 el operador no', format($$select public.geoportal_redes_dano_tercero(%L, %L)$$, op, v_d3), '42501');
  perform pg_temp.err('08.06 un daño sin tercero', format($$select public.geoportal_redes_dano_tercero(%L, %L)$$, sd, v_d1), 'P0002', 'no tiene nombre');

  -- ---------- 09 Intervenciones: ocultar, reincluir y anular con motivo ----------
  v_p := pg_temp.preparar(op, 1);
  v_i1 := public.geoportal_redes_crear_intervencion(op, (v_p ->> 'intervencion_id')::uuid, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'),
            jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d1, 'resuelve_dano', true))) ->> 'codigo';
  v_r := public.geoportal_redes_intervencion_evento(sd, v_i1, 'ocultar', 'Intervención de prueba del celular');
  perform pg_temp.reg('09.01 ocultar la intervención: «oculta» y fuera de la epicrisis', v_r ->> 'estado' = 'oculta' and not exists (select 1 from redes.v_epicrisis where clase = 'intervencion' and resumen like v_i1 || ' %'));
  perform pg_temp.reg('09.02 reincluir', public.geoportal_redes_intervencion_evento(sd, v_i1, 'reincluir', 'Era real, se reincluye') ->> 'estado' = 'cerrada');
  v_r := public.geoportal_redes_intervencion_evento(sd, v_i1, 'anulada', 'Se registró dos veces la misma reparación');
  perform pg_temp.reg('09.03 anular: «anulada» en la epicrisis, con el aviso de que el daño que resolvía sigue atendido', v_r ->> 'estado' = 'anulada' and v_r ->> 'aviso' like 'El daño ' || v_d1 || ' sigue atendido%'
     and exists (select 1 from redes.v_epicrisis where clase = 'intervencion' and resumen like v_i1 || ' %' and estado = 'Anulada'), v_r::text);
  perform pg_temp.err('09.04 anular dos veces', format($$select public.geoportal_redes_intervencion_evento(%L, %L, 'anulada', 'Otra vez la misma')$$, sd, v_i1), '22023', 'Solo se anula');
  perform pg_temp.err('09.05 el operador no anula', format($$select public.geoportal_redes_intervencion_evento(%L, %L, 'ocultar', 'Intento del operador')$$, op, v_i1), '42501');

  -- ---------- 10 Reportes del bot: la bandeja ----------
  v_rep := redes.f_reporte_externo_recibir(jsonb_build_object('radicado', 'ZT5-0001', 'canal', 'telegram', 'tipo', 'Fuga', 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(30), 'recibido_en', pg_temp.iso('-1 hours')));
  perform pg_temp.reg('10.01 la bandeja trae el reporte pendiente', exists (select 1 from jsonb_array_elements(public.geoportal_redes_reportes_bot(sd) -> 'reportes') x where x ->> 'radicado' = 'ZT5-0001' and x ->> 'estado_bot' = 'recibido'));
  perform pg_temp.err('10.02 el de planta ya no ve la bandeja', format($$select public.geoportal_redes_reportes_bot(%L)$$, sv), '42501');
  v_r := public.geoportal_redes_reporte_convertir(sd, v_rep, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', v_red1, 'riesgo', 'medio'));
  perform pg_temp.reg('10.03 el supervisor de distribución lo convierte en daño; sale de «pendientes»', v_r ->> 'dano_codigo' like 'DAN-%'
     and not exists (select 1 from jsonb_array_elements(public.geoportal_redes_reportes_bot(sd) -> 'reportes') x where x ->> 'radicado' = 'ZT5-0001'));
  perform pg_temp.err('10.04 el de planta ya no convierte reportes', format($$select public.geoportal_redes_reporte_convertir(%L, %L, '{}')$$, sv, v_rep), '42501');

  -- ---------- 11 Crear el activo desde la bandeja (respuesta 4 de David al 3a) ----------
  v_p := pg_temp.preparar(op, 1);
  v_in := public.geoportal_redes_crear_intervencion(op, (v_p ->> 'intervencion_id')::uuid, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('tipo', 'correctivo',
            'sistema', 'alcantarillado', 'activo', null, 'no_identificado', 'Pozo que no sale en el mapa', 'lat', pg_temp.lat(400), 'lon', pg_temp.lon(50), 'ubicacion_origen', 'mapa'))) ->> 'codigo';
  perform pg_temp.err('11.01 un tramo no se crea desde la bandeja', format($$select public.geoportal_redes_crear_activo_bandeja(%L, 'intervencion', %L, 'COL', null, null, 'Tramo nuevo en la esquina')$$, sd, v_in), '22023', 'Cargue de capas');
  perform pg_temp.err('11.02 un tipo de otro sistema', format($$select public.geoportal_redes_crear_activo_bandeja(%L, 'intervencion', %L, 'VAL', 'cierre', null, 'Válvula en la esquina')$$, sd, v_in), '22023', 'mismo sistema');
  perform pg_temp.err('11.03 el operador no crea', format($$select public.geoportal_redes_crear_activo_bandeja(%L, 'intervencion', %L, 'POZ', null, null, 'Pozo nuevo en la esquina')$$, op, v_in), '42501');
  v_r := public.geoportal_redes_crear_activo_bandeja(sd, 'intervencion', v_in, 'POZ', null, 'Pozo de la esquina', 'Pozo nuevo visto en la visita');
  perform pg_temp.reg('11.04 crear el pozo: POZ-… «por verificar», alta por asociación, en el punto del registro, y la intervención queda sobre él',
     v_r ->> 'activo' like 'POZ-%' and exists (select 1 from redes.v_activo_vigente v join redes.activos x on x.id = v.activo_id where v.codigo = v_r ->> 'activo' and v.por_verificar and x.origen_alta = 'asociacion'
       and ST_DWithin(v.geom::geography, ST_SetSRID(ST_MakePoint(pg_temp.lon(50), pg_temp.lat(400)), 4326)::geography, 0.5))
     and (select activo_codigo from redes.v_intervencion where codigo = v_in) = v_r ->> 'activo' and not exists (select 1 from redes.v_no_identificados where codigo = v_in), v_r::text);
  perform pg_temp.err('11.05 crear dos veces', format($$select public.geoportal_redes_crear_activo_bandeja(%L, 'intervencion', %L, 'POZ', null, null, 'Otra vez el mismo pozo')$$, sd, v_in), '22023', 'ya tiene activo');
  v_dn := pg_temp.dano(op, jsonb_build_object('activo', null, 'no_identificado', 'Válvula sin código', 'lat', pg_temp.lat(-20), 'lon', pg_temp.lon(60), 'ubicacion_origen', 'mapa')) ->> 'codigo';
  perform pg_temp.err('11.06 una válvula nueva sin clase', format($$select public.geoportal_redes_crear_activo_bandeja(%L, 'dano', %L, 'VAL', null, null, 'Válvula vista en la visita')$$, sd, v_dn), '22023', 'clase');
  v_r := public.geoportal_redes_crear_activo_bandeja(a, 'dano', v_dn, 'VAL', 'cierre', null, 'Válvula vista en la visita');
  perform pg_temp.reg('11.07 crear la válvula para el daño no identificado: el daño la toma', (select activo_codigo from redes.v_dano where codigo = v_dn) = v_r ->> 'activo' and v_r ->> 'activo' like 'VAL-%');

  -- ---------- 12 Ficha (§26): galería para todos; edita el supervisor de distribución, el origen solo el administrador ----------
  v_x := public.geoportal_redes_galeria(op, v_red1);
  perform pg_temp.reg('12.01 el operador ve el conteo de fotos y la galería (lectura auditada)', public.geoportal_redes_perfil(op, v_red1) ? 'fotos'
     and (v_x ->> 'total')::integer >= 1 and exists (select 1 from public.geoportal_auditoria where accion = 'redes_galeria' and email = op), (v_x ->> 'total'));
  v_r := public.geoportal_redes_perfil(sd, v_red1);
  perform pg_temp.reg('12.02 el supervisor de distribución edita, pero sin el origen', (v_r ->> 'editable')::boolean and not (v_r -> 'edicion' ->> 'puede_origen')::boolean
     and not v_r -> 'edicion' -> 'valores' ? 'origen', left((v_r -> 'edicion' -> 'valores')::text, 300));
  perform pg_temp.reg('12.03 el administrador ve y corrige el origen', (public.geoportal_redes_perfil(a, v_red1) -> 'edicion' ->> 'puede_origen')::boolean
     and public.geoportal_redes_perfil(a, v_red1) -> 'edicion' -> 'valores' ->> 'origen' = 'emdupar');
  v_r := public.geoportal_redes_ficha_editar(sd, v_red1, '{"alias": "Tramo de prueba ZT5", "diametro_mm": 110}', 'Revisión del supervisor de distribución');
  perform pg_temp.reg('12.04 el supervisor de distribución guarda la ficha (versión nueva y alias)', (v_r ->> 'version_nueva')::boolean
     and public.geoportal_redes_perfil(op, v_red1) ->> 'alias' = 'Tramo de prueba ZT5');
  perform pg_temp.err('12.05 el supervisor de distribución no corrige el origen', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"origen": {"origen": "tercero", "aportante": "alcaldia"}}', 'Lo entregó la alcaldía')$$, sd, v_red1), '42501');
  perform pg_temp.err('12.06 el de planta ya no edita la ficha', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"alias": "x y"}', 'Intento del de planta')$$, sv, v_red1), '42501');
  v_p := public.geoportal_redes_foto_perfil_preparar(sd, v_red1);
  perform pg_temp.reg('12.07 el supervisor de distribución también cambia la foto principal', v_p ->> 'ruta' like 'activos/%');

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 4a (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
