-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov) · 70 — ENSAYO: datos de prueba y reportes de ANTES → MIGRACIÓN → pruebas → REVERSA → pruebas; termina en el
-- ERROR esperado (todo se deshace). Datos propios con prefijo ZTRAN (correos ztran.*@emdupar.gov.co; contrato de 12 dígitos 991800000201, que se comprueba que
-- no existe). Las RPC corren como service_role con los topes de producción (30 s y 8 s). Cinco perfiles: administrador, supervisor de Comercial, operador de
-- campo, dual (operador de campo y de Técnica, sin supervisión) y sin permisos. El mapa se mide con las capas REALES de la base (redes y predios).
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztran_res (n serial, nombre text, ok boolean, detalle text);
create temp table ztran_val (k text primary key, v text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztran_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
create function pg_temp.guardar(p_k text, p_v text) returns void language sql as $f$ insert into ztran_val values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.val(p_k text) returns text language sql as $f$ select v from ztran_val where k = p_k $f$;
-- llama una RPC como service_role; devuelve su jsonb o {"error": sqlstate, "msg": mensaje}
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
create function pg_temp.err(r jsonb) returns text language sql as $f$ select coalesce(r ->> 'error', 'OK') $f$;
create function pg_temp.msg(r jsonb) returns text language sql as $f$ select coalesce(r ->> 'msg', '') $f$;
-- Registra un reporte como lo hace la Edge: reserva (preparar_subida, o la de Técnica), «sube» cada foto al doble de Storage y crea.
-- p_fotos: arreglo de {etiqueta?, origen?} (una entrada por foto; «origen» solo si viene). p_registro: el bloque nuevo (nulo = la Edge de antes: llamada sin p_registro).
create function pg_temp.reg(p_quien text, p_tipo text, p_fotos jsonb default '[{}]', p_registro jsonb default null, p_lat numeric default 10.46, p_lon numeric default -73.25,
                            p_prec numeric default 5, p_contrato text default null, p_resultado text default null, p_causal text default null, p_tec boolean default false,
                            p_id uuid default null) returns jsonb language plpgsql as $f$
declare p jsonb; v_id uuid; v_f jsonb := '[]'::jsonb; v_ruta text; v_n integer := jsonb_array_length(coalesce(p_fotos, '[]'::jsonb)); v_e jsonb; q text;
begin
  if p_id is null then
    p := case when p_tec then pg_temp.rpc(format('public.geoportal_campo_tec_preparar_subida(%L, %s, null, %L)', p_quien, v_n, p_tipo))
              else pg_temp.rpc(format('public.geoportal_campo_preparar_subida(%L, %s, ''campo'', null, %L)', p_quien, v_n, p_tipo)) end;
    if p ? 'error' then return p; end if;
    v_id := (p ->> 'reporte_id')::uuid;
    for i in 1 .. v_n loop
      v_ruta := p -> 'fotos' -> (i - 1) ->> 'ruta';
      insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', v_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg'));
      v_e := jsonb_build_object('orden', i, 'ruta', v_ruta) || coalesce(p_fotos -> (i - 1), '{}'::jsonb);
      v_f := v_f || v_e;
    end loop;
    perform pg_temp.guardar('fotos:' || v_id, v_f::text);
    -- los formatos con firma del operario obligatoria (los de PDF): se firma antes de registrar, como lo hace la pantalla
    if not p_tec and exists (select 1 from campo.formularios_documento d where d.formulario = 'tipo:' || p_tipo and d.firma_operario = 'obligatoria') then
      p := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%L, ''campo'', %L::uuid, ''operario'', ''firmo'', null, %L)', p_quien, v_id,
                              encode('\xffd8ffe0'::bytea || convert_to(repeat('z', 400), 'UTF8'), 'base64')));
      if p ? 'error' then return p || jsonb_build_object('_id', v_id, '_paso', 'firma'); end if;
    end if;
  else
    v_id := p_id; v_f := coalesce(pg_temp.val('fotos:' || v_id), '[]')::jsonb;
  end if;
  if p_tec then
    q := format('public.geoportal_campo_tec_crear_reporte(%L, %L::uuid, %L, null, %L, %L, %s, %s, %s, false, %L::jsonb, null, null, %L, %L, null%s)',
                p_quien, v_id, p_tipo, '[PRUEBA ZTRAN] ' || p_tipo, p_contrato, p_lat, p_lon, coalesce(p_prec::text, 'null'), v_f, p_resultado, p_causal,
                case when p_registro is null then '' else format(', %L::jsonb', p_registro) end);
  else
    q := format('public.geoportal_campo_crear_reporte(%L, %L::uuid, %L, null, %L, %L, %s, %s, %s, false, ''campo'', %L::jsonb, null, null, %L, %L, null, null%s)',
                p_quien, v_id, p_tipo, '[PRUEBA ZTRAN] ' || p_tipo, p_contrato, p_lat, p_lon, coalesce(p_prec::text, 'null'), v_f, p_resultado, p_causal,
                case when p_registro is null then '' else format(', %L::jsonb', p_registro) end);
  end if;
  return pg_temp.rpc(q) || jsonb_build_object('_id', v_id);
end $f$;
create function pg_temp.datos(p_quien text, p_id uuid) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_ran_datos(%L, %L::uuid, null)', p_quien, p_id)) $f$;
create function pg_temp.registrar(p_quien text, p_id uuid, p_sello text, p_sha text default repeat('ab', 32), p_bytes integer default 150000) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_ran_registrar(%L, %L::uuid, %L, %L, %s, 0, null)', p_quien, p_id, p_sello, p_sha, p_bytes)) $f$;
create function pg_temp.obtener(p_quien text, p_id uuid) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_ran_obtener(%L, %L::uuid, null)', p_quien, p_id)) $f$;
create function pg_temp.audit(p_quien text, p_accion text, p_id text) returns bigint language sql as $f$
  select count(*) from public.geoportal_auditoria where email = p_quien and accion = p_accion and referencia = p_id $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico, ver_analisis_contrato) values
  ('ztran.adm@emdupar.gov.co', 'ZTRAN Administración', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('ztran.sup@emdupar.gov.co', 'ZTRAN Supervisora', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('ztran.op@emdupar.gov.co', 'ZTRAN Operario', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztran.dual@emdupar.gov.co', 'ZTRAN Dual sin supervisión', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, true, false),
  ('ztran.sin@emdupar.gov.co', 'ZTRAN Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false);
insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('ztran.dual@emdupar.gov.co', 'asignar_formulario', 'anomalia_compartida', 'ztran.adm@emdupar.gov.co');

-- ===================== 00. Datos de prueba y lo de ANTES =====================
do $p0$
declare r jsonb; OP text := 'ztran.op@emdupar.gov.co'; SUP text := 'ztran.sup@emdupar.gov.co';
begin
  perform pg_temp.ok('00.01 el contrato de prueba no existe (cartera, censo, reportes)',
    not exists (select 1 from public.cartera_suscripcion where contrato = '991800000201') and not exists (select 1 from public.catastro_valledupar where cod_usuario = '991800000201')
    and not exists (select 1 from campo.reportes where contrato = '991800000201'));
  insert into public.cartera_suscripcion (contrato, estado, nombre, telefono, direccion, barrio, deuda_total, periodo_carga) values
    ('991800000201', 'ACTIVO', 'ZTRAN PERSONA', '3001112233', 'CRA 9 # 12-30', 'CENTRO', 0, '20261123');
  -- A: el operario, con contrato y dirección encontrada en terreno, foto de cámara, punto real de la ciudad
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"lat_registro": 10.476071, "lon_registro": -73.251529, "precision_registro_m": 6, "direccion": "[PRUEBA ZTRAN] CRA 9 # 12-32", "barrio": "CENTRO", "referencia": "Casa de rejas verdes"}',
                   10.476071, -73.251529, 6, '991800000201');
  perform pg_temp.ok('00.02 antes: un reporte de «Reportar anomalía» del operario se registra', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('A', r ->> '_id');
  -- B: la supervisora, foto de la galería y XY digitado (registrado desde otro punto)
  r := pg_temp.reg(SUP, 'otro', '[{"origen": "galeria"}]', '{"xy_manual": true, "lat_registro": 10.4762, "lon_registro": -73.2512, "precision_registro_m": 9}', 10.476071, -73.251529, null);
  perform pg_temp.ok('00.03 antes: un reporte con galería y XY digitado se registra', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('B', r ->> '_id');
  -- F: un formato (revisión previa): tiene su propio PDF
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', null, 10.476071, -73.251529, 5, '991800000201', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('00.04 antes: un formato con contrato se registra', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('F', r ->> '_id');
  perform pg_temp.ok('00.05 antes: no existe la ruta del PDF del reporte', to_regprocedure('public.geoportal_campo_ran_datos(text,uuid,text)') is null);
end $p0$;

-- ===================== MIGRACIÓN (guardia incluida) =====================
{{CUERPO_MIGRACION}}

-- ===================== 01. Estructura y permisos =====================
do $p1$
begin
  perform pg_temp.ok('01.01 la huella de campo es la de este cambio; acta y Técnica no cambiaron',
    ({{HUELLA_CAMPO_Q}}) = '{{HUELLA_CAMPO_NUEVA}}' and ({{HUELLA_ACTA_Q}}) = '{{HUELLA_ACTA}}' and ({{HUELLA_TECNICA_Q}}) = '{{HUELLA_TECNICA}}');
  perform pg_temp.ok('01.02 campo.reporte_pdf: RLS sin políticas, sin permisos para la API, SELECT para homelab_lectura',
    (select relrowsecurity from pg_class where oid = 'campo.reporte_pdf'::regclass) and not exists (select 1 from pg_policies where schemaname = 'campo')
    and not has_table_privilege('service_role', 'campo.reporte_pdf', 'select') and not has_table_privilege('authenticated', 'campo.reporte_pdf', 'select')
    and not has_table_privilege('anon', 'campo.reporte_pdf', 'select') and has_table_privilege('homelab_lectura', 'campo.reporte_pdf', 'select')
    and not has_table_privilege('homelab_lectura', 'campo.reporte_pdf', 'insert'));
  perform pg_temp.ok('01.03 las 3 RPC solo para service_role; las 5 internas para nadie de la API',
    has_function_privilege('service_role', 'public.geoportal_campo_ran_datos(text,uuid,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_ran_datos(text,uuid,text)', 'execute')
    and has_function_privilege('service_role', 'public.geoportal_campo_ran_obtener(text,uuid,text)', 'execute') and not has_function_privilege('anon', 'public.geoportal_campo_ran_obtener(text,uuid,text)', 'execute')
    and has_function_privilege('service_role', 'public.geoportal_campo_ran_registrar(text,uuid,text,text,integer,integer,text)', 'execute')
    and not has_function_privilege('service_role', 'campo.f_ran_contenido(uuid)', 'execute') and not has_function_privilege('service_role', 'campo.f_ran_mapa(numeric,numeric,numeric,numeric)', 'execute')
    and not has_function_privilege('service_role', 'campo.f_ran_autorizar(text,uuid)', 'execute'));
end $p1$;

-- ===================== 02. Quién puede =====================
do $p2$
declare A uuid := pg_temp.val('A')::uuid; F uuid := pg_temp.val('F')::uuid;
begin
  perform pg_temp.ok('02.01 administrador y supervisora de Comercial: sí', pg_temp.err(pg_temp.datos('ztran.adm@emdupar.gov.co', A)) = 'OK' and pg_temp.err(pg_temp.datos('ztran.sup@emdupar.gov.co', A)) = 'OK',
    pg_temp.datos('ztran.adm@emdupar.gov.co', A)::text);
  perform pg_temp.ok('02.02 el operario (aunque sea el autor), el dual sin supervisión y el sin permisos: 403 (42501)',
    pg_temp.err(pg_temp.datos('ztran.op@emdupar.gov.co', A)) = '42501' and pg_temp.err(pg_temp.datos('ztran.dual@emdupar.gov.co', A)) = '42501'
    and pg_temp.err(pg_temp.datos('ztran.sin@emdupar.gov.co', A)) = '42501');
  perform pg_temp.ok('02.03 también 403 al registrar y al obtener',
    pg_temp.err(pg_temp.registrar('ztran.op@emdupar.gov.co', A, repeat('0', 64))) = '42501' and pg_temp.err(pg_temp.obtener('ztran.dual@emdupar.gov.co', A)) = '42501');
  perform pg_temp.ok('02.04 un reporte que no existe: 404 (P0002)', pg_temp.err(pg_temp.datos('ztran.sup@emdupar.gov.co', gen_random_uuid())) = 'P0002');
  perform pg_temp.ok('02.05 un formato: se rechaza (tiene su propio PDF)', pg_temp.err(pg_temp.datos('ztran.sup@emdupar.gov.co', F)) = '22023', pg_temp.datos('ztran.sup@emdupar.gov.co', F)::text);
  perform pg_temp.ok('02.06 antes de generarlo, obtener responde 404', pg_temp.err(pg_temp.obtener('ztran.sup@emdupar.gov.co', A)) = 'P0002');
end $p2$;

-- ===================== 03. El contenido =====================
do $p3$
declare A uuid := pg_temp.val('A')::uuid; B uuid := pg_temp.val('B')::uuid; d jsonb; e jsonb; v_seq bigint;
begin
  d := pg_temp.datos('ztran.sup@emdupar.gov.co', A);
  select seq into v_seq from campo.reportes where id = A;
  perform pg_temp.ok('03.01 identificador RAN-NNNNNN, grupo, tipo y estado «Reportado»',
    d ->> 'identificador' = 'RAN-' || lpad(v_seq::text, 6, '0') and d ->> 'tipo' = (select nombre from campo.tipos_reporte where codigo = 'otro') and d ->> 'estado' = 'Reportado'
    and d ->> 'grupo' is not null, left(d::text, 400));
  perform pg_temp.ok('03.02 reportó: el NOMBRE del operario (no el correo)', d ->> 'reporto' = 'ZTRAN Operario' and position('ztran.op@' in (d - 'fotos')::text) = 0, d ->> 'reporto');
  perform pg_temp.ok('03.03 sin nombre en la lista blanca: el correo', campo.f_ran_persona('ztran.nadie@emdupar.gov.co') = 'ztran.nadie@emdupar.gov.co'
    and campo.f_ran_persona('ZTRAN.SUP@emdupar.gov.co') = 'ZTRAN Supervisora');
  perform pg_temp.ok('03.04 contrato, dirección del contrato (base comercial) y dirección encontrada en terreno con barrio y referencia',
    d ->> 'contrato' = '991800000201' and d -> 'direccion_contrato' ->> 'comercial' is not null and d -> 'terreno' ->> 'direccion' = '[PRUEBA ZTRAN] CRA 9 # 12-32'
    and d -> 'terreno' ->> 'barrio' = 'CENTRO' and d -> 'terreno' ->> 'referencia' = 'Casa de rejas verdes', left(d::text, 600));
  perform pg_temp.ok('03.05 ubicación con precisión; foto de cámara con su origen; inicio, fin y duración',
    (d -> 'ubicacion' ->> 'precision_m')::numeric = 6 and jsonb_array_length(d -> 'fotos') = 1 and d -> 'fotos' -> 0 ->> 'etiqueta' like '% · tomada con la cámara'
    and d ->> 'fin' ~ '^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$' and d ? 'inicio' and d ? 'duracion', left(d::text, 600));
  perform pg_temp.ok('03.06 historial: «Reportado» por el operario', d -> 'historial' -> 0 ->> 'texto' = 'Reportado' and d -> 'historial' -> 0 ->> 'quien' = 'ZTRAN Operario');
  e := pg_temp.datos('ztran.sup@emdupar.gov.co', B);
  perform pg_temp.ok('03.07 galería y XY digitado: la foto dice su origen y la ubicación marca el XY con el punto de registro',
    e -> 'fotos' -> 0 ->> 'etiqueta' like '% · adjuntada desde la galería' and (e -> 'ubicacion' ->> 'xy_digitado')::boolean and (e -> 'ubicacion' ->> 'lat_registro')::numeric = 10.4762, left(e::text, 600));
  perform pg_temp.ok('03.08 sin firmas ni rutas sueltas: las únicas rutas son las de las fotos (para la Edge)',
    not (d ? 'firmas') and (select count(*) from jsonb_array_elements(d -> 'fotos') f where f ? 'ruta') = 1);
  perform pg_temp.guardar('sello_A1', d ->> 'sello');
end $p3$;

-- ===================== 04. Datos sensibles: nunca =====================
do $p4$
declare A uuid := pg_temp.val('A')::uuid; d jsonb;
begin
  insert into campo.reporte_datos_sensibles (reporte_id, datos, registrado_en) values (A, '{"telefono_contacto": "3009876543", "nombre_contacto": "ZTRAN CONTACTO SECRETO"}', clock_timestamp());
  d := pg_temp.datos('ztran.adm@emdupar.gov.co', A);
  perform pg_temp.ok('04.01 los datos sensibles no salen (ni al administrador) y no cambian el sello',
    position('3009876543' in d::text) = 0 and position('SECRETO' in d::text) = 0 and d ->> 'sello' = pg_temp.val('sello_A1'));
end $p4$;

-- ===================== 05. El mapa (capas reales) =====================
do $p5$
declare A uuid := pg_temp.val('A')::uuid; B uuid := pg_temp.val('B')::uuid; d jsonb; m jsonb; t0 timestamptz; v_ms numeric; v_fuera int;
begin
  t0 := clock_timestamp(); d := pg_temp.datos('ztran.sup@emdupar.gov.co', A); v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  m := d -> 'mapa';
  perform pg_temp.ok('05.01 el mapa trae red de acueducto alrededor del punto (ventana 400 × 200 m)',
    (m ->> 'ancho_m')::int = 400 and (m ->> 'alto_m')::int = 200 and (select count(*) from jsonb_array_elements(m -> 'lineas') l where l ->> 'capa' = 'acueducto') > 0, left(m::text, 300));
  perform pg_temp.ok('05.02 trae predios', jsonb_array_length(m -> 'predios') > 0, jsonb_array_length(m -> 'predios')::text);
  select count(*) into v_fuera from jsonb_array_elements(m -> 'lineas') l, jsonb_array_elements(l -> 'p') q where abs((q ->> 0)::numeric) > 200.05 or abs((q ->> 1)::numeric) > 100.05;
  select v_fuera + count(*) into v_fuera from jsonb_array_elements(m -> 'predios') q where abs((q ->> 0)::numeric) > 200.05 or abs((q ->> 1)::numeric) > 100.05;
  perform pg_temp.ok('05.03 todo queda recortado dentro de la ventana (metros relativos al punto)', v_fuera = 0, v_fuera::text);
  perform pg_temp.ok('05.04 la consulta con el mapa tarda menos de 3 s como service_role (con 30 s de tope)', v_ms < 3000, round(v_ms)::text || ' ms');
  m := pg_temp.datos('ztran.sup@emdupar.gov.co', B) -> 'mapa';
  perform pg_temp.ok('05.05 con XY digitado, el mapa trae el punto de registro (a unos 40 m)', jsonb_typeof(m -> 'registro') = 'array'
    and sqrt(power((m -> 'registro' ->> 0)::numeric, 2) + power((m -> 'registro' ->> 1)::numeric, 2)) between 20 and 80, (m -> 'registro')::text);
  m := campo.f_ran_mapa(4.6, -74.08);
  perform pg_temp.ok('05.06 un punto lejos de la ciudad: mapa vacío, sin error', jsonb_array_length(m -> 'lineas') = 0 and jsonb_array_length(m -> 'predios') = 0);
end $p5$;

-- ===================== 06. Generar, entregar y auditar =====================
do $p6$
declare A uuid := pg_temp.val('A')::uuid; SUP text := 'ztran.sup@emdupar.gov.co'; ADM text := 'ztran.adm@emdupar.gov.co'; d jsonb; r jsonb;
begin
  d := pg_temp.datos(SUP, A);
  perform pg_temp.ok('06.01 primera vez: versión 1, sin documento, nombre AAAAMMDDHHMMSS-RAN-NNNNNN.pdf y ruta en campo/AAAA-MM/<id>/',
    (d ->> 'version')::int = 1 and d -> 'documento' = 'null'::jsonb and d ->> 'nombre' ~ '^[0-9]{14}-RAN-[0-9]{6}\.pdf$'
    and d ->> 'ruta' = 'campo/' || to_char((select registrado_en from campo.reportes where id = A) at time zone 'America/Bogota', 'YYYY-MM') || '/' || A || '/' || (d ->> 'nombre'), d ->> 'ruta');
  perform pg_temp.ok('06.02 registrar con un sello viejo: 409 (55000); con huella inválida: 400',
    pg_temp.err(pg_temp.registrar(SUP, A, repeat('0', 64))) = '55000' and pg_temp.err(pg_temp.registrar(SUP, A, d ->> 'sello', 'xyz')) = '22023');
  r := pg_temp.registrar(SUP, A, d ->> 'sello');
  perform pg_temp.ok('06.03 registrar: versión 1 nueva, auditada como generación', pg_temp.err(r) = 'OK' and (r ->> 'nuevo')::boolean and (r ->> 'version')::int = 1
    and pg_temp.audit(SUP, 'campo_ran_pdf_generar', A::text) = 1, r::text);
  r := pg_temp.registrar(ADM, A, d ->> 'sello', repeat('cd', 32));
  perform pg_temp.ok('06.04 otro registro del mismo sello: devuelve el primero (no hay otra versión) y se audita como descarga',
    not (r ->> 'nuevo')::boolean and r ->> 'sha256' = repeat('ab', 32) and (select count(*) from campo.reporte_pdf where reporte_id = A) = 1
    and pg_temp.audit(ADM, 'campo_ran_pdf_descargar', A::text) = 1, r::text);
  d := pg_temp.datos(ADM, A);
  perform pg_temp.ok('06.05 la siguiente consulta ve el documento y no arma el mapa', (d -> 'documento' ->> 'version')::int = 1 and d -> 'mapa' = 'null'::jsonb);
  r := pg_temp.obtener(SUP, A);
  perform pg_temp.ok('06.06 obtener: el mismo PDF, auditado', (r ->> 'version')::int = 1 and r ->> 'nombre' = d -> 'documento' ->> 'nombre' and pg_temp.audit(SUP, 'campo_ran_pdf_descargar', A::text) = 1, r::text);
  perform pg_temp.ok('06.07 la fila guarda quién lo generó, el sello, el tamaño y las fotos omitidas',
    exists (select 1 from campo.reporte_pdf where reporte_id = A and version = 1 and generado_por = SUP and sello = d ->> 'sello' and bytes = 150000 and fotos_omitidas = 0));
end $p6$;

-- ===================== 07. Versión nueva solo si cambia el sello =====================
do $p7$
declare A uuid := pg_temp.val('A')::uuid; SUP text := 'ztran.sup@emdupar.gov.co'; d jsonb; r jsonb;
begin
  r := pg_temp.rpc(format('public.geoportal_campo_cambiar_estado(%L, %L::uuid, ''en_revision'', ''[PRUEBA ZTRAN] se revisa en terreno'', null)', SUP, A));
  perform pg_temp.ok('07.01 la supervisora cambia el estado', pg_temp.err(r) = 'OK', r::text);
  d := pg_temp.datos(SUP, A);
  perform pg_temp.ok('07.02 cambió el sello: versión 2, sin documento, nombre con -v2; el historial lo dice con su nombre',
    d ->> 'sello' <> pg_temp.val('sello_A1') and (d ->> 'version')::int = 2 and d -> 'documento' = 'null'::jsonb and d ->> 'nombre' ~ '-v2\.pdf$'
    and d -> 'historial' -> 1 ->> 'texto' = 'Cambio de estado → En revisión · [PRUEBA ZTRAN] se revisa en terreno' and d -> 'historial' -> 1 ->> 'quien' = 'ZTRAN Supervisora'
    and d ->> 'estado' = 'En revisión', left((d -> 'historial')::text, 400));
  perform pg_temp.ok('07.03 obtener responde 404 hasta generar la versión vigente', pg_temp.err(pg_temp.obtener(SUP, A)) = 'P0002');
  r := pg_temp.registrar(SUP, A, d ->> 'sello', repeat('ef', 32));
  perform pg_temp.ok('07.04 la versión 2 queda; la 1 sigue igual', (r ->> 'version')::int = 2 and (r ->> 'nuevo')::boolean
    and (select count(*) from campo.reporte_pdf where reporte_id = A) = 2 and exists (select 1 from campo.reporte_pdf where reporte_id = A and version = 1 and sha256 = repeat('ab', 32)), r::text);
  d := pg_temp.datos(SUP, A);
  perform pg_temp.ok('07.05 sin otro cambio, se entrega la versión 2', (d -> 'documento' ->> 'version')::int = 2);
end $p7$;

-- ===================== 08. Solo inserción y reglas de producción =====================
do $p8$
declare v_ok boolean;
begin
  begin update campo.reporte_pdf set bytes = bytes where reporte_id = pg_temp.val('A')::uuid; v_ok := false; exception when others then v_ok := true; end;
  perform pg_temp.ok('08.01 campo.reporte_pdf no se modifica (UPDATE rechazado)', v_ok);
  begin delete from campo.reporte_pdf where reporte_id = pg_temp.val('A')::uuid; v_ok := false; exception when others then v_ok := true; end;
  perform pg_temp.ok('08.02 ni se borra (DELETE rechazado)', v_ok);
  perform pg_temp.ok('08.03 ninguna función de campo con DELETE o UPDATE sin WHERE', {{SIN_WHERE_CAMPO}} = 0);
  perform pg_temp.ok('08.04 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
end $p8$;

-- ===================== REVERSA =====================
{{CUERPO_REVERSA}}

-- ===================== 09. Después de la reversa =====================
do $p9$
begin
  perform pg_temp.ok('09.01 la huella de campo vuelve a la de partida', ({{HUELLA_CAMPO_Q}}) = '{{HUELLA_CAMPO}}');
  perform pg_temp.ok('09.02 las RPC ya no están; nada se borró: las 2 versiones siguen', to_regprocedure('public.geoportal_campo_ran_datos(text,uuid,text)') is null
    and (select count(*) from campo.reporte_pdf where reporte_id = pg_temp.val('A')::uuid) = 2);
end $p9$;

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztran_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;
