-- =====================================================================
-- COMERCIAL 21-NOV · (b) ACTAS · 70 — PRUEBAS (dentro del ensayo; todo se deshace con el ERROR esperado)
-- Datos propios ZTB (correos ztb.*@emdupar.gov.co). El contrato es uno que exista en el catastro, elegido al correr (sin contratos fijos). Cada prueba cuenta SOLO sus filas. Los registros se hacen con las RPC publicadas
-- (geoportal_campo_crear_reporte y geoportal_acta_registrar, sin cambios); las RPC nuevas se llaman como service_role con los topes de producción.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table zt_res (n serial, nombre text, ok boolean, detalle text) on commit drop;
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into zt_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
create function pg_temp.rpc(q text) returns jsonb language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  begin
    execute 'set local role service_role';
    execute 'select (' || q || ')::jsonb' into r;
    execute 'reset role';
    return coalesce(r, 'null'::jsonb);
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    return jsonb_build_object('error', e, 'msg', m);
  end;
end $f$;
create function pg_temp.con() returns text language sql stable as $f$
  select c.cod_usuario from public.catastro_valledupar c where c.cod_usuario ~ '^[A-Za-z0-9-]{1,20}$' order by c.cod_usuario limit 1 $f$;
create function pg_temp.err(r jsonb) returns text language sql as $f$ select coalesce(r ->> 'error', 'OK') $f$;
create function pg_temp.msg(p_sql text) returns text language plpgsql as $f$
declare v_m text; begin execute p_sql; return 'OK'; exception when others then get stacked diagnostics v_m = message_text; return v_m; end $f$;
-- JPEG de prueba (cabecera FFD8FF y relleno) en base64
create function pg_temp.jpg(p_n integer default 1) returns text language sql as $f$ select encode('\xffd8ffe0'::bytea || convert_to(repeat('ZTB' || p_n, 120), 'UTF8'), 'base64') $f$;
-- Formato de campo (ayudante de la pasada del 14-nov): crea el reporte con sus fotos en storage.objects
create function pg_temp.cr(p_quien text, p_tipo text, p_datos jsonb, p_etqs text[], p_id uuid default null, p_contrato text default pg_temp.con()) returns jsonb language plpgsql as $f$
declare v_f jsonb := '[]'::jsonb; v_ruta text; v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  for i in 1 .. coalesce(cardinality(p_etqs), 0) loop
    v_ruta := 'reportes/2026-11/' || v_id::text || '/' || i || '.jpg';
    insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', v_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg')) on conflict do nothing;
    v_f := v_f || (jsonb_build_object('orden', i, 'ruta', v_ruta) || jsonb_build_object('etiqueta', p_etqs[i]));
  end loop;
  return public.geoportal_campo_crear_reporte(p_quien, v_id, p_tipo, null, '[PRUEBA ZTB] actas 21-nov', p_contrato, 10.46, -73.25, 5, false, 'campo', v_f, null, p_datos, 'efectivo', null, null);
end $f$;
create function pg_temp.base_inst(p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $f$
  select jsonb_build_object('serie_acta', 'S-1', 'orden_servicio', 'OS-1', 'tipo_servicio', 'residencial', 'hora_inicio', '2026-11-14T08:00', 'hora_final', '2026-11-14T08:40',
    'firma_atendio', 'atendio_firmo', 'firmo_operario', true, 'irr_hay', false, 'mi_lectura', 10, 'inst_tipo', 'd1',
    'inst_modalidad', 'instalacion', 'mi_r', 'r160', 'mi_tipo_medidor', 'velocidad', 'inst_reubica_cajilla', false) || p_extra $f$;
-- Acta de inspección (ayudantes de cancelar y de la pasada del 14-nov)
create function pg_temp.fot(p_id uuid, p_orden integer, p_tipo text) returns jsonb language plpgsql as $f$
declare v text := 'actas/' || to_char(now(), 'YYYY-MM') || '/' || p_id::text || '/fotos/' || p_orden || '.jpg';
begin
  insert into storage.objects (bucket_id, name, metadata) values ('acta-evidencias', v, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg')) on conflict do nothing;
  return jsonb_build_object('orden', p_orden, 'tipo', p_tipo, 'ruta', v);
end $f$;
create function pg_temp.huellas() returns jsonb language sql as $f$ select jsonb_object_agg(i::text, lpad(to_hex(i), 64, 'a')) from generate_series(1, 40) i $f$;
create function pg_temp.hoy() returns text language sql as $f$ select to_char((clock_timestamp() at time zone 'America/Bogota')::date, 'YYYY-MM-DD') $f$;
create function pg_temp.cb(p_id uuid) returns jsonb language sql as $f$
  select jsonb_build_object('modo_identificacion', 'con_contrato', 'contrato', pg_temp.con(), 'direccion', 'CRA 10 # 5-20', 'barrio', 'ZTB Centro', 'estrato', '3', 'uso', 'RESIDENCIAL',
    'tiene_medidor', true, 'medidor_serie', 'M-123', 'marca', 'MARCA X', 'lectura_m3', 120.5, 'estado_medidor', 'funcionando', 'estado_sellos', 'rotos',
    'hallazgos', jsonb_build_array(jsonb_build_object('codigo', 'conexion_directa')), 'descripcion_hallazgos', 'Conexión directa antes del medidor',
    'nadie_atendio', false, 'atendiente', jsonb_build_object('nombre', 'ZTB Persona Atiende', 'calidad', 'propietario'),
    'firmo_operario', true, 'firmo_atendiente', true, 'se_nego_a_firmar', false, 'fecha_acta_fisica', pg_temp.hoy(), 'papel_pendiente', false,
    'fotos', jsonb_build_array(pg_temp.fot(p_id, 1, 'fachada'), pg_temp.fot(p_id, 2, 'hallazgo'), pg_temp.fot(p_id, 3, 'acta_fisica'))) $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta) values
  ('ztb.rep@emdupar.gov.co', 'ZTB Operario', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztb.rep2@emdupar.gov.co', 'ZTB Operario 2', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztb.sup@emdupar.gov.co', 'ZTB Supervisor', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('ztb.aco@emdupar.gov.co', 'ZTB Operario Actas', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, false),
  ('ztb.acs@emdupar.gov.co', 'ZTB Sup Actas', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, true),
  ('ztb.nada@emdupar.gov.co', 'ZTB Sin acceso', 'consulta', true, 'sin_restriccion', 'todos', true, false, false, false, false);
update campo.parametros set valor = 1000 where clave in ('limite_reportes_ventana', 'limite_contratos_ventana');
update campo.parametros set valor = 100 where clave = 'limite_contratos_falsos_dia';
update campo.grupos_reporte set activo = true where codigo in ('facturacion', 'perdidas_formatos', 'pqr', 'cartera') and not activo;
update campo.tipos_reporte set activo = true where codigo in ('revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida') and not activo;

do $$
declare r jsonb; m text; id1 uuid := gen_random_uuid(); id2 uuid := gen_random_uuid(); id3 uuid := gen_random_uuid(); id4 uuid := gen_random_uuid(); id5 uuid := gen_random_uuid();
  aid uuid; aid2 uuid; dv bigint; dv2 bigint; t0 timestamptz;
  IM constant text[] := array['fachada_predio', 'medidor_instalado', 'acta_fisica'];
  CAMBIO constant jsonb := '{"inst_modalidad": "cambio", "me_lectura": 12.5, "me_r": "r315", "me_tipo_medidor": "woltman"}';
  REP constant text := '''ztb.rep@emdupar.gov.co'''; SUP constant text := '''ztb.sup@emdupar.gov.co'''; ACS constant text := '''ztb.acs@emdupar.gov.co'''; ACO constant text := '''ztb.aco@emdupar.gov.co''';
begin
  -- 01 catálogo de formularios con PDF y firmas
  r := pg_temp.rpc('public.geoportal_campo_documentos_catalogo(' || REP || ')');
  perform pg_temp.ok('01.01 el catálogo trae los 9 formularios con PDF y las tres firmas (operario obligatoria)',
    (select count(*) from jsonb_array_elements(r -> 'formularios') x where x -> 'firmas' = '{"operario": "obligatoria", "usuario": "opcional", "testigo": "opcional"}'::jsonb and x -> 'lleva_pdf' = 'true'::jsonb
       and x ->> 'formulario' in ('acta', 'tipo:revision_previa', 'tipo:revision_pqr', 'tipo:instalacion_medidor', 'tipo:instalacion_acometida', 'tipo:suspension', 'tipo:corte', 'tipo:reinstalacion', 'tipo:reconexion_servicio')) = 9
    and jsonb_array_length(r -> 'formularios') = 9, left(r::text, 300));
  perform pg_temp.ok('01.02 sin PDF: LEV, VER, INV, CME y Reportar anomalía no están', not exists (select 1 from jsonb_array_elements(r -> 'formularios') x
    where x ->> 'formulario' in ('tipo:levantamiento_acometida', 'tipo:verificacion_posterior', 'tipo:investigacion_ubicacion', 'tipo:cambio_medidor', 'reporte_general')));
  perform pg_temp.ok('01.03 alguien sin campo ni acta no ve el catálogo (42501)', pg_temp.err(pg_temp.rpc('public.geoportal_campo_documentos_catalogo(''ztb.nada@emdupar.gov.co'')')) = '42501');

  -- 02 firmas antes de registrar
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''operario'', ''firmo'', null, %L)', REP, id1, encode('\x89504e47'::bytea || convert_to(repeat('x', 300), 'UTF8'), 'base64')));
  perform pg_temp.ok('02.01 una firma que no es JPEG se rechaza', r ->> 'msg' = 'La firma debe ser una imagen JPEG de 200 B a 40 KB', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''operario'', ''firmo'', null, %L)', REP, id1, pg_temp.jpg(1)));
  perform pg_temp.ok('02.02 firma del operario: guarda la huella sha256 de la imagen', r ->> 'sha256' = encode(sha256(decode(pg_temp.jpg(1), 'base64')), 'hex')
    and (select nombre from campo.firmas where registro_id = id1 and rol = 'operario') = 'ZTB Operario', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''operario'', ''firmo'', null, %L)', REP, id1, pg_temp.jpg(2)));
  perform pg_temp.ok('02.03 se puede repetir antes de registrar (reemplaza)', r ->> 'sha256' = encode(sha256(decode(pg_temp.jpg(2), 'base64')), 'hex')
    and (select count(*) from campo.firmas where registro_id = id1 and rol = 'operario') = 1, r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''usuario'', ''firmo'', null, %L)', REP, id1, pg_temp.jpg(3)));
  perform pg_temp.ok('02.04 firma del usuario sin nombre: 400 con texto', r ->> 'msg' = 'Escriba el nombre de quien atendió (entre 2 y 120 caracteres)', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''testigo'', ''firmo'', ''ZTB Testigo'', %L)', REP, id1, pg_temp.jpg(4)));
  perform pg_temp.ok('02.05 el testigo solo firma si el usuario no firmó', r ->> 'msg' = 'El testigo firma solo cuando el usuario no firmó', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''usuario'', ''no_firmo'')', REP, id1));
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''testigo'', ''firmo'', ''ZTB Testigo Uno'', %L)', REP, id1, pg_temp.jpg(4)));
  perform pg_temp.ok('02.06 usuario no firmó → firma el testigo con su nombre', pg_temp.err(r) = 'OK' and (select nombre from campo.firmas where registro_id = id1 and rol = 'testigo') = 'ZTB Testigo Uno', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''usuario'', ''firmo'', ''ZTB Persona Atiende'', %L)', REP, id1, pg_temp.jpg(5)));
  perform pg_temp.ok('02.07 si el usuario pasa a firmar, el testigo queda «quitada» (no se borra)', pg_temp.err(r) = 'OK'
    and (select estado from campo.firmas where registro_id = id1 and rol = 'testigo') = 'quitada', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(''ztb.rep2@emdupar.gov.co'', ''campo'', %L, ''usuario'', ''nadie_atendio'')', id1));
  perform pg_temp.ok('02.08 otra persona no firma un registro ajeno', r ->> 'msg' = 'Ese registro lo está diligenciando otra persona', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''operario'', ''quitar'')', REP, id1));
  perform pg_temp.ok('02.09 la firma del operario no se quita', r ->> 'msg' like 'La firma del operario es obligatoria%', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(''ztb.aco@emdupar.gov.co'', ''campo'', %L, ''operario'', ''firmo'', null, %L)', id2, pg_temp.jpg(1)));
  perform pg_temp.ok('02.10 un operario solo de actas no firma formatos de campo (42501)', pg_temp.err(r) = '42501', r::text);

  -- 03 registrar: la firma del operario es obligatoria (disparador; las RPC de registro no cambian)
  m := pg_temp.msg(format('select pg_temp.cr(%L, %L, %L::jsonb, %L::text[], %L)', 'ztb.rep@emdupar.gov.co', 'instalacion_medidor', pg_temp.base_inst(), IM, id2));
  perform pg_temp.ok('03.01 sin la firma del operario no se registra (texto para el usuario)', m = 'Falta la firma del operario', m);
  m := pg_temp.msg(format('select pg_temp.cr(%L, %L, %L::jsonb, %L::text[], %L)', 'ztb.rep@emdupar.gov.co', 'instalacion_medidor', pg_temp.base_inst(), IM, id1));
  perform pg_temp.ok('03.02 con la firma del operario sí se registra', m = 'OK', m);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''operario'', ''firmo'', null, %L)', REP, id1, pg_temp.jpg(9)));
  perform pg_temp.ok('03.03 después de registrar la firma es definitiva (409)', pg_temp.err(r) = '55000' and r ->> 'msg' = 'El registro ya está hecho: la firma es definitiva', r::text);
  m := pg_temp.msg(format('update campo.firmas set nombre = %L where registro_id = %L and rol = %L', 'Otro', id1, 'usuario'));
  perform pg_temp.ok('03.04 ni siquiera el dueño de la base cambia una firma registrada', m like 'El registro ya está hecho%', m);
  m := pg_temp.msg(format('delete from campo.firmas where registro_id = %L', id1));
  perform pg_temp.ok('03.05 las firmas no se borran', m = 'Las firmas no se borran', m);

  -- 04 «¿Da lugar a otras actividades?» y req_cambio_medidor (D13)
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''operario'', ''firmo'', null, %L)', REP, id3, pg_temp.jpg(1)));
  m := pg_temp.msg(format('select pg_temp.cr(%L, %L, %L::jsonb, %L::text[], %L)', 'ztb.rep@emdupar.gov.co', 'instalacion_medidor',
                          pg_temp.base_inst(CAMBIO || '{"req_cambio_medidor": false, "da_lugar": ["cambio_medidor", "fuga_externa"]}'), IM, id3));
  perform pg_temp.ok('04.01 req_cambio_medidor distinto de da_lugar: no se registra', m = '¿Se requiere cambio de medidor? no coincide con las actividades derivadas', m);
  m := pg_temp.msg(format('select pg_temp.cr(%L, %L, %L::jsonb, %L::text[], %L)', 'ztb.rep@emdupar.gov.co', 'instalacion_medidor',
                          pg_temp.base_inst(CAMBIO || '{"req_cambio_medidor": true, "da_lugar": ["cambio_medidor", "fuga_externa"]}'), IM, id3));
  perform pg_temp.ok('04.02 coherentes: se registra y crea una derivada pendiente por opción', m = 'OK'
    and (select count(*) from campo.derivadas where origen_id = id3) = 2 and (select bool_and(campo.f_derivada_estado(id) = 'pendiente') from campo.derivadas where origen_id = id3), m);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''operario'', ''firmo'', null, %L)', REP, id4, pg_temp.jpg(1)));
  m := pg_temp.msg(format('select pg_temp.cr(%L, %L, %L::jsonb, %L::text[], %L)', 'ztb.rep@emdupar.gov.co', 'instalacion_medidor',
                          pg_temp.base_inst('{"da_lugar": ["accesorios", "otra"], "da_lugar_otra": "Revisar el andén"}'), IM, id4));
  perform pg_temp.ok('04.03 «otra» queda como derivada sin destino', m = 'OK' and (select count(*) from campo.derivadas where origen_id = id4) = 2
    and (select destinos from campo.derivadas_catalogo where codigo = 'otra') = '{}', m);
  perform pg_temp.ok('04.04 fuga por fuera de la casa: por omisión Instalación de medidor y se puede escoger Revisiones generales',
    (select destino_omision = 'tipo:instalacion_medidor' and destinos = '{tipo:instalacion_medidor,tipo:revision_previa}' from campo.derivadas_catalogo where codigo = 'fuga_externa'));
  perform pg_temp.ok('04.05 los 4 REV tienen los campos da_lugar y da_lugar_otra activos', (select count(*) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id
    where c.codigo in ('da_lugar', 'da_lugar_otra') and c.activo and t.codigo in ('revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida')) = 8);

  -- 05 derivadas: abiertas, atender, cerrar
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_abiertas(%s, %L, ''tipo:instalacion_medidor'')', REP, pg_temp.con()));
  perform pg_temp.ok('05.01 abiertas del contrato que atiende Instalación de medidor (las 3 con destino; «otra» no)',
    (select count(*) from jsonb_array_elements(r -> 'derivadas') x where (x -> 'origen' ->> 'registro_id')::uuid in (id3, id4)) = 3, left(r::text, 300));
  select id into dv from campo.derivadas where origen_id = id3 and actividad = 'cambio_medidor';
  select id into dv2 from campo.derivadas where origen_id = id3 and actividad = 'fuga_externa';
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%s, %s, ''campo'', %L)', REP, dv, id3));
  perform pg_temp.ok('05.02 una revisión no atiende sus propias derivadas', r ->> 'msg' = 'Una revisión no atiende sus propias actividades derivadas', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''campo'', %L, ''operario'', ''firmo'', null, %L)', REP, id5, pg_temp.jpg(1)));
  m := pg_temp.msg(format('select pg_temp.cr(%L, %L, %L::jsonb, %L::text[], %L)', 'ztb.rep@emdupar.gov.co', 'instalacion_medidor', pg_temp.base_inst(), IM, id5));
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%s, %s, ''campo'', %L)', REP, dv, id5));
  perform pg_temp.ok('05.03 otra instalación del mismo contrato la atiende; queda el enlace', m = 'OK' and r ->> 'estado' = 'atendida' and (r -> 'cierre' ->> 'registro_id')::uuid = id5, r::text || m);
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%s, %s, ''campo'', %L)', REP, dv, id5));
  perform pg_temp.ok('05.04 atenderla otra vez: 409', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_cerrar(%s, %s, ''anulada'', ''ZTB no aplica en este predio'')', REP, dv2));
  perform pg_temp.ok('05.05 un operario no anula derivadas (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_cerrar(%s, %s, ''anulada'', null)', SUP, dv2));
  perform pg_temp.ok('05.06 anular exige motivo', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_cerrar(%s, %s, ''atendida_fuera'', ''ZTB se reparó en la visita de redes'')', SUP, dv2));
  perform pg_temp.ok('05.07 el supervisor la cierra como atendida fuera del sistema (el cierre trae el motivo)', r ->> 'estado' = 'atendida_fuera' and r -> 'cierre' ->> 'motivo' = 'ZTB se reparó en la visita de redes', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas(%s, %L)', ACS, jsonb_build_object('contrato', pg_temp.con(), 'estado', 'pendiente')));
  perform pg_temp.ok('05.08 lista de derivadas: quedan pendientes las 2 de la otra instalación', (select count(*) from jsonb_array_elements(r -> 'filas') x where (x -> 'origen' ->> 'registro_id')::uuid in (id3, id4)) = 2, left(r::text, 300));
  m := pg_temp.msg(format('delete from campo.derivada_eventos where derivada_id = %s', dv));
  perform pg_temp.ok('05.09 los cierres de derivadas son de solo agregar', m like '%solo agregar%', m);

  -- 06 acta de inspección (AI): firma obligatoria al registrar y vínculo posible pérdida → revisión
  aid := (public.geoportal_acta_abrir('ztb.aco@emdupar.gov.co', 10.46, -73.25, 5) ->> 'acta_id')::uuid;
  m := pg_temp.msg(format('select public.geoportal_acta_registrar(%L, %L, %L::jsonb, %L::jsonb)', 'ztb.aco@emdupar.gov.co', aid, pg_temp.cb(aid), pg_temp.huellas()));
  perform pg_temp.ok('06.01 el acta sin la firma del operario no se registra', m = 'Falta la firma del operario', m);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''acta'', %L, ''operario'', ''firmo'', null, %L)', ACO, aid, pg_temp.jpg(7)));
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''acta'', %L, ''usuario'', ''nadie_atendio'')', ACO, aid));
  m := pg_temp.msg(format('select public.geoportal_acta_registrar(%L, %L, %L::jsonb, %L::jsonb)', 'ztb.aco@emdupar.gov.co', aid, pg_temp.cb(aid), pg_temp.huellas()));
  perform pg_temp.ok('06.02 con la firma sí se registra', m = 'OK', m);
  r := pg_temp.rpc(format('public.geoportal_campo_actas_abiertas(%s, %L)', REP, pg_temp.con()));
  perform pg_temp.ok('06.03 actas abiertas del contrato para el selector de origen', exists (select 1 from jsonb_array_elements(r -> 'actas') x where (x ->> 'acta_id')::uuid = aid), left(r::text, 200));
  r := pg_temp.rpc(format('public.geoportal_campo_origen_vincular(%s, %L, %L)', REP, id1, aid));
  perform pg_temp.ok('06.04 la revisión o instalación indica el acta que la originó', r -> 'vinculado' = 'true'::jsonb and (select acta_id from campo.origen_vinculos where reporte_id = id1) = aid, r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_origen_vincular(%s, %L, %L)', REP, id1, aid));
  perform pg_temp.ok('06.05 una sola acta de origen por revisión (409)', pg_temp.err(r) = '55000', r::text);

  -- 06b corrección del acta AI: la firma quien corrige (David, 21-nov) y el PDF -v2 junta su firma con las de la original
  aid2 := (public.geoportal_acta_iniciar_correccion('ztb.acs@emdupar.gov.co', aid, 'ZTB se corrige la dirección escrita por error') ->> 'acta_id')::uuid;
  m := pg_temp.msg(format('select public.geoportal_acta_registrar(%L, %L, %L::jsonb, %L::jsonb)', 'ztb.acs@emdupar.gov.co', aid2, pg_temp.cb(aid2) || '{"fotos": []}'::jsonb, pg_temp.huellas()));
  perform pg_temp.ok('06.06 la corrección (versión 2) sin la firma de quien corrige no se registra', m = 'Falta la firma del operario', m);
  r := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%s, ''acta'', %L, ''operario'', ''firmo'', null, %L)', ACS, aid2, pg_temp.jpg(8)));
  perform pg_temp.ok('06.07 el supervisor de actas (quien corrige) guarda su firma', pg_temp.err(r) = 'OK' and (select nombre from campo.firmas where registro_id = aid2 and rol = 'operario') = 'ZTB Sup Actas', r::text);
  m := pg_temp.msg(format('select public.geoportal_acta_registrar(%L, %L, %L::jsonb, %L::jsonb)', 'ztb.acs@emdupar.gov.co', aid2, pg_temp.cb(aid2) || '{"fotos": []}'::jsonb, pg_temp.huellas()));
  perform pg_temp.ok('06.08 con la firma de quien corrige, la versión 2 se registra', m = 'OK', m);
  r := pg_temp.rpc(format('public.geoportal_campo_pdf_datos(%s, ''acta'', %L)', ACS, aid2));
  perform pg_temp.ok('06.09 el PDF de la corrección termina en -v2 y trae la firma de quien corrige junto a las de la original',
    r ->> 'nombre' ~ '^[0-9]{14}-ITEC-AI-[0-9]{4}-[0-9]{6}-v2\.pdf$' and (r ->> 'version')::int = 2
    and exists (select 1 from jsonb_array_elements(r -> 'firmas') x where x ->> 'de' = 'esta' and x ->> 'rol' = 'operario' and x ->> 'nombre' = 'ZTB Sup Actas')
    and exists (select 1 from jsonb_array_elements(r -> 'firmas') x where x ->> 'de' = 'original' and x ->> 'rol' = 'operario' and x ->> 'nombre' = 'ZTB Operario Actas')
    and exists (select 1 from jsonb_array_elements(r -> 'firmas') x where x ->> 'de' = 'original' and x ->> 'rol' = 'usuario' and x ->> 'estado' = 'nadie_atendio'), left(r::text, 500));

  -- 07 actas registradas (lista y descarga sin nombres ni imágenes)
  r := pg_temp.rpc('public.geoportal_campo_actas_registradas(' || ACS || ', ''{"operario": "ztb."}'')');
  perform pg_temp.ok('07.01 el supervisor de actas ve las actas registradas: 4 instalaciones y 1 acta AI (su versión vigente, la corrección)', (select count(*) from jsonb_array_elements(r -> 'filas') x
    where (x ->> 'registro_id')::uuid in (id1, id3, id4, id5, aid2)) = 5, left(r::text, 300));
  perform pg_temp.ok('07.02 marcas por fila: firmas (operario, usuario) y derivadas', (select x -> 'firmas' = '{"operario": true, "usuario": "firmo", "testigo": false}'::jsonb
      from jsonb_array_elements(r -> 'filas') x where (x ->> 'registro_id')::uuid = id1)
    and (select x -> 'derivadas' = '{"total": 2, "pendientes": 0}'::jsonb from jsonb_array_elements(r -> 'filas') x where (x ->> 'registro_id')::uuid = id3)
    and (select x -> 'firmas' ->> 'usuario' = 'nadie_atendio' from jsonb_array_elements(r -> 'filas') x where (x ->> 'registro_id')::uuid = aid2) is null
    and (select x -> 'pdf' = '{"estado": "pendiente", "nombre": null, "version": null}'::jsonb from jsonb_array_elements(r -> 'filas') x where (x ->> 'registro_id')::uuid = id3));
  r := pg_temp.rpc('public.geoportal_campo_actas_registradas(' || SUP || ', ''{"operario": "ztb.", "derivadas": "pendientes"}'')');
  perform pg_temp.ok('07.03 filtro «con derivadas pendientes» (supervisor de campo)', (select array_agg((x ->> 'registro_id')::uuid) from jsonb_array_elements(r -> 'filas') x where (x ->> 'registro_id')::uuid in (id1, id3, id4, id5, aid, aid2)) = array[id4], left(r::text, 300));
  r := pg_temp.rpc('public.geoportal_campo_actas_registradas(' || SUP || ', ''{"operario": "ztb.", "tipo": "acta"}'')');
  perform pg_temp.ok('07.04 filtro por tipo (acta)', (select count(*) from jsonb_array_elements(r -> 'filas') x where (x ->> 'registro_id')::uuid in (id1, id3, id4, id5, aid, aid2)) = 1);
  r := pg_temp.rpc('public.geoportal_campo_actas_registradas(' || REP || ')');
  perform pg_temp.ok('07.05 un operario no ve las actas registradas (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc('public.geoportal_campo_actas_registradas_descarga(' || ACS || ', ''{"operario": "ztb."}'')');
  perform pg_temp.ok('07.06 la descarga no lleva nombres de quien atendió ni del testigo, ni firmas, ni texto libre', pg_temp.err(r) = 'OK'
    and r::text not like '%ZTB Persona Atiende%' and r::text not like '%ZTB Testigo%' and r::text not like '%Revisar el andén%' and r::text not like '%/9j/%'
    and (select count(*) from jsonb_array_elements(r -> 'filas') x where (x ->> 'registro_id')::uuid in (id1, id3, id4, id5, aid2)) = 5, left(r::text, 200));
  perform pg_temp.ok('07.07 la descarga queda en la auditoría', exists (select 1 from public.geoportal_auditoria where email = 'ztb.acs@emdupar.gov.co' and accion = 'campo_actas_registradas_descarga'));

  -- 08 PDF: datos para la Edge, registro único, descarga
  r := pg_temp.rpc(format('public.geoportal_campo_pdf_datos(%s, ''campo'', %L)', REP, id1));
  perform pg_temp.ok('08.01 datos del PDF: nombre AAAAMMDDHHMMSS-REV-IME…, secciones, 3 fotos y las firmas con su imagen',
    r ->> 'nombre' ~ '^[0-9]{14}-REV-IME[0-9]{6}\.pdf$' and jsonb_array_length(r -> 'fotos') = 3 and jsonb_array_length(r -> 'secciones') > 0
    and (select count(*) from jsonb_array_elements(r -> 'firmas') x where x ->> 'imagen' is not null) = 2 and r ->> 'sello' ~ '^[0-9a-f]{64}$'
    and r -> 'documento' = 'null'::jsonb and r ->> 'ruta' like 'campo/____-__/' || id1 || '/%.pdf', left(r::text, 400));
  perform pg_temp.ok('08.01b el PDF dice el resultado en palabras y las horas sin la «T»', r -> 'cabecera' @> '[["Resultado", "Efectivo (se realizó la actividad)"]]'::jsonb
    and r::text not like '%2026-11-14T08:00%' and r::text like '%2026-11-14 08:00%', left(r::text, 300));
  perform pg_temp.ok('08.02 el PDF interno sí lleva el nombre de quien atendió (D7)', exists (select 1 from jsonb_array_elements(r -> 'firmas') x where x ->> 'nombre' = 'ZTB Persona Atiende'));
  r := pg_temp.rpc(format('public.geoportal_campo_pdf_datos(''ztb.rep2@emdupar.gov.co'', ''campo'', %L)', id1));
  perform pg_temp.ok('08.03 otro operario no ve los datos del PDF (42501)', pg_temp.err(r) = '42501', r::text);
  perform pg_temp.ok('08.03b sin campo ni acta: 403 aunque el registro no exista (no averigua si existe)', pg_temp.err(pg_temp.rpc(format('public.geoportal_campo_pdf_datos(''ztb.nada@emdupar.gov.co'', ''campo'', %L)', gen_random_uuid()))) = '42501');
  r := pg_temp.rpc(format('public.geoportal_campo_pdf_obtener(%s, ''campo'', %L)', REP, id1));
  perform pg_temp.ok('08.04 antes de generarlo: 404 con texto', pg_temp.err(r) = 'P0002' and r ->> 'msg' = 'Ese registro todavía no tiene PDF', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_pdf_registrar(%s, ''campo'', %L, %L, 52000)', REP, id1, repeat('a', 64)));
  perform pg_temp.ok('08.05 registrar el PDF (una sola vez)', r -> 'nuevo' = 'true'::jsonb and r ->> 'sha256' = repeat('a', 64), r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_pdf_registrar(%s, ''campo'', %L, %L, 60000)', SUP, id1, repeat('b', 64)));
  perform pg_temp.ok('08.06 otra generación no lo reemplaza: devuelve el mismo', r -> 'nuevo' = 'false'::jsonb and r ->> 'sha256' = repeat('a', 64), r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_pdf_obtener(%s, ''campo'', %L)', ACS, id1));
  perform pg_temp.ok('08.07 el supervisor de actas lo obtiene', r ->> 'nombre' ~ '-REV-IME' and (r ->> 'bytes')::int = 52000, r::text);
  m := pg_temp.msg(format('update campo.documentos_pdf set sha256 = %L where registro_id = %L', repeat('c', 64), id1));
  perform pg_temp.ok('08.08 el PDF registrado no se cambia', m like '%solo agregar%', m);
  r := pg_temp.rpc(format('public.geoportal_campo_pdf_datos(%s, ''acta'', %L)', ACO, aid));
  perform pg_temp.ok('08.09 acta AI: nombre AAAAMMDDHHMMSS-ITEC-AI-AAAA-NNNNNN.pdf y la firma del operario', r ->> 'nombre' ~ '^[0-9]{14}-ITEC-AI-[0-9]{4}-[0-9]{6}\.pdf$'
    and exists (select 1 from jsonb_array_elements(r -> 'firmas') x where x ->> 'rol' = 'operario') and jsonb_array_length(r -> 'fotos') = 3, left(r::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_pdf_fallo(%s, ''acta'', %L, ''ZTB prueba de fallo'')', ACO, aid));
  perform pg_temp.ok('08.10 un fallo de generación queda anotado (el registro no se pierde)', (select count(*) from campo.documento_intentos where registro_id = aid) = 1, r::text);
  perform pg_temp.ok('08.11 el bucket actas-pdf es privado, solo PDF y con tope de 25 MB', (select not public and file_size_limit = 26214400 and allowed_mime_types = array['application/pdf'] from storage.buckets where id = 'actas-pdf'));

  -- 09 permisos, RLS, sin WHERE
  perform pg_temp.ok('09.01 las 14 RPC nuevas: solo service_role', (select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_campo_documentos_catalogo', 'geoportal_campo_firma_guardar',
      'geoportal_campo_pdf_datos', 'geoportal_campo_pdf_registrar', 'geoportal_campo_pdf_fallo', 'geoportal_campo_pdf_obtener', 'geoportal_campo_actas_registradas', 'geoportal_campo_actas_registradas_descarga',
      'geoportal_campo_derivadas_abiertas', 'geoportal_campo_derivada_atender', 'geoportal_campo_derivada_cerrar', 'geoportal_campo_derivadas', 'geoportal_campo_actas_abiertas', 'geoportal_campo_origen_vincular'))
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_campo_documentos_catalogo', 'geoportal_campo_firma_guardar', 'geoportal_campo_pdf_datos',
      'geoportal_campo_pdf_registrar', 'geoportal_campo_pdf_fallo', 'geoportal_campo_pdf_obtener', 'geoportal_campo_actas_registradas', 'geoportal_campo_actas_registradas_descarga', 'geoportal_campo_derivadas_abiertas',
      'geoportal_campo_derivada_atender', 'geoportal_campo_derivada_cerrar', 'geoportal_campo_derivadas', 'geoportal_campo_actas_abiertas', 'geoportal_campo_origen_vincular')) = 14);
  perform pg_temp.ok('09.02 las 8 tablas nuevas: con RLS y sin permisos para anon, authenticated ni service_role', (select bool_and(c.relrowsecurity and not has_table_privilege(r_, c.oid, 'select'))
      from pg_class c, unnest(array['anon', 'authenticated', 'service_role']) r_ where c.oid in ('campo.formularios_documento'::regclass, 'campo.firmas'::regclass, 'campo.documentos_pdf'::regclass,
      'campo.documento_intentos'::regclass, 'campo.derivadas_catalogo'::regclass, 'campo.derivadas'::regclass, 'campo.derivada_eventos'::regclass, 'campo.origen_vinculos'::regclass)));
  execute 'select count(*) from redes.f_funciones_sin_where()' into m;
  perform pg_temp.ok('09.03 ninguna función con DELETE o UPDATE sin WHERE (redes.f_funciones_sin_where y la misma regla sobre campo)', m = '0' and {{SIN_WHERE_CAMPO}} = 0, 'redes: ' || m);
  perform pg_temp.ok('09.04 las RPC de registro publicadas no cambiaron (huella del acta igual)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text))
      from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '111506c690249ad3b56ebf572566434c');

  -- 10 tiempos
  t0 := clock_timestamp(); r := pg_temp.rpc('public.geoportal_campo_actas_registradas(' || ACS || ')');
  perform pg_temp.ok('10.01 actas registradas (primera página) en menos de 2 s', pg_temp.err(r) = 'OK' and clock_timestamp() - t0 < interval '2 s', (clock_timestamp() - t0)::text);
end $$;

do $$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from zt_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $$;
