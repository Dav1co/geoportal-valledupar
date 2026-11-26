-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 70 — ENSAYO: registros de antes → MIGRACIÓN → pruebas → REVERSA → pruebas; termina en el ERROR esperado (todo se deshace)
-- Datos propios con prefijo ZTRF (correos ztrf.*@emdupar.gov.co; textos «[PRUEBA ZTRF]»; contratos 991xxx en las derivadas). Cada prueba cuenta SOLO sus filas.
-- Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- 5 perfiles (David, 24-nov): administrador, supervisor de Comercial, operador de campo, dual (supervisor de Comercial y operador de Técnica con «Reportar anomalía»)
-- y sin permisos; además, dos operadores de planta (PTAP: «entrada»), uno con «Reportar anomalía» de Técnica y otro sin él.
-- Sin tablas temporales que se borren al confirmar: la tabla de resultados se deshace con el ERROR esperado del final.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztrf_res (n serial, nombre text, ok boolean, detalle text);
create temp table ztrf_val (k text primary key, v text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztrf_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
create function pg_temp.guardar(p_k text, p_v text) returns void language sql as $f$ insert into ztrf_val values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.val(p_k text) returns text language sql as $f$ select v from ztrf_val where k = p_k $f$;
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
                p_quien, v_id, p_tipo, '[PRUEBA ZTRF] ' || p_tipo, p_contrato, p_lat, p_lon, coalesce(p_prec::text, 'null'), v_f, p_resultado, p_causal,
                case when p_registro is null then '' else format(', %L::jsonb', p_registro) end);
  else
    q := format('public.geoportal_campo_crear_reporte(%L, %L::uuid, %L, null, %L, %L, %s, %s, %s, false, ''campo'', %L::jsonb, null, null, %L, %L, null, null%s)',
                p_quien, v_id, p_tipo, '[PRUEBA ZTRF] ' || p_tipo, p_contrato, p_lat, p_lon, coalesce(p_prec::text, 'null'), v_f, p_resultado, p_causal,
                case when p_registro is null then '' else format(', %L::jsonb', p_registro) end);
  end if;
  return pg_temp.rpc(q) || jsonb_build_object('_id', v_id);
end $f$;
create function pg_temp.pdf(p_quien text, p_id uuid) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_pdf_datos(%L, ''campo'', %L::uuid, null)', p_quien, p_id)) $f$;
create function pg_temp.lista(p_quien text, p_id uuid) returns jsonb language sql as $f$
  select e from jsonb_array_elements(pg_temp.rpc(format('public.geoportal_campo_listar_reportes(%L, %L::jsonb, null)', p_quien, '{"limite": 5000}')) -> 'reportes') e where (e ->> 'id')::uuid = p_id $f$;
create function pg_temp.detalle(p_quien text, p_id uuid) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_obtener_reporte(%L, %L::uuid, null)', p_quien, p_id)) $f$;
create function pg_temp.cab(p jsonb, p_k text) returns text language sql as $f$ select e ->> 1 from jsonb_array_elements(p -> 'cabecera') e where e ->> 0 = p_k $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico) values
  ('ztrf.admin@emdupar.gov.co', 'ZTRF Administrador', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false),
  ('ztrf.sup@emdupar.gov.co', 'ZTRF Supervisor de Comercial', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false),
  ('ztrf.op@emdupar.gov.co', 'ZTRF Operador de campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false),
  ('ztrf.op2@emdupar.gov.co', 'ZTRF Operador de campo 2', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false),
  ('ztrf.dual@emdupar.gov.co', 'ZTRF Dual (supervisor de Comercial y operador de Técnica)', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, true),
  ('ztrf.sin@emdupar.gov.co', 'ZTRF Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false),
  ('ztrf.planta@emdupar.gov.co', 'ZTRF Operador de planta con anomalía', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true),
  ('ztrf.planta2@emdupar.gov.co', 'ZTRF Operador de planta sin anomalía', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true);
insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values
  ('ztrf.dual@emdupar.gov.co', 'asignar_formulario', 'anomalia_compartida', 'ztrf.admin@emdupar.gov.co'),
  ('ztrf.planta@emdupar.gov.co', 'asignar_formulario', 'entrada', 'ztrf.admin@emdupar.gov.co'),
  ('ztrf.planta@emdupar.gov.co', 'asignar_formulario', 'anomalia_compartida', 'ztrf.admin@emdupar.gov.co'),
  ('ztrf.planta2@emdupar.gov.co', 'asignar_formulario', 'entrada', 'ztrf.admin@emdupar.gov.co');

-- ===================== 00. ANTES de la migración: registros como los de hoy y su sello =====================
do $p0$
declare r jsonb; ADM text := 'ztrf.admin@emdupar.gov.co'; OP text := 'ztrf.op@emdupar.gov.co';
begin
  -- revisión previa inefectiva (lleva PDF) y un reporte general, con las funciones publicadas
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', null, 10.46, -73.25, 5, '123456', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('00.01 antes: una revisión previa inefectiva se registra con la función publicada', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('viejo', r ->> '_id');
  r := pg_temp.reg(OP, 'otro');
  perform pg_temp.ok('00.02 antes: un reporte general se registra con la función publicada', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('viejo_general', r ->> '_id');
  r := pg_temp.pdf(ADM, pg_temp.val('viejo')::uuid);
  perform pg_temp.ok('00.03 antes: datos del PDF con su sello', pg_temp.err(r) = 'OK' and length(r ->> 'sello') = 64, left(r::text, 300));
  perform pg_temp.guardar('sello_viejo', r ->> 'sello'); perform pg_temp.guardar('cab_viejo', (r -> 'cabecera')::text); perform pg_temp.guardar('fotos_viejo', (r -> 'fotos')::text);
  perform pg_temp.guardar('lista_vieja', (pg_temp.lista(ADM, pg_temp.val('viejo')::uuid))::text);
end $p0$;

-- ===================== MIGRACIÓN (guardia incluida), dentro de esta misma transacción =====================
{{CUERPO_MIGRACION}}

-- ===================== 01. Estructura =====================
do $p1$
begin
  perform pg_temp.ok('01.01 campo.reporte_registro: llave = reporte_id (a lo sumo una fila por reporte)',
    (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'campo.reporte_registro'::regclass and contype = 'p') = 'PRIMARY KEY (reporte_id)');
  perform pg_temp.ok('01.02 RLS activa, sin políticas, sin permisos para la API; SELECT (y nada más) para homelab_lectura',
    (select relrowsecurity from pg_class where oid = 'campo.reporte_registro'::regclass) and not exists (select 1 from pg_policies where schemaname in ('campo', 'acta'))
    and not has_table_privilege('anon', 'campo.reporte_registro', 'select') and not has_table_privilege('authenticated', 'campo.reporte_registro', 'select')
    and not has_table_privilege('service_role', 'campo.reporte_registro', 'select') and not has_table_privilege('service_role', 'campo.reporte_registro', 'insert')
    and has_table_privilege('homelab_lectura', 'campo.reporte_registro', 'select') and not has_table_privilege('homelab_lectura', 'campo.reporte_registro', 'insert')
    and not has_table_privilege('homelab_lectura', 'campo.reporte_registro', 'update'));
  perform pg_temp.ok('01.03 los mismos disparadores de solo inserción que campo.reporte_fotos',
    (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = 'campo.reporte_registro'::regclass and not tgisinternal)
    = (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = 'campo.reporte_fotos'::regclass and not tgisinternal));
  perform pg_temp.ok('01.04 las fotos de antes quedan como de cámara (origen camara)',
    (select bool_and(origen = 'camara') from campo.reporte_fotos where reporte_id in (pg_temp.val('viejo')::uuid, pg_temp.val('viejo_general')::uuid)));
  perform pg_temp.ok('01.05 los reportes de antes no tienen fila en reporte_registro',
    not exists (select 1 from campo.reporte_registro where reporte_id in (pg_temp.val('viejo')::uuid, pg_temp.val('viejo_general')::uuid)));
  perform pg_temp.ok('01.06 la huella del acta no cambió', ({{HUELLA_ACTA_Q}}) = '{{HUELLA_ACTA}}');
  perform pg_temp.ok('01.07 la huella de Técnica no cambió (cambia la firma de geoportal_campo_tec_crear_reporte, que no es de esa huella)', ({{HUELLA_TECNICA_Q}}) = '{{HUELLA_TECNICA}}');
  perform pg_temp.ok('01.08 solo quedan las firmas nuevas de crear_reporte y de la entrada de Técnica',
    to_regprocedure('{{F_CREAR}}') is null and to_regprocedure('{{F_TEC}}') is null and to_regprocedure('{{F_CREAR_NUEVA}}') is not null and to_regprocedure('{{F_TEC_NUEVA}}') is not null);
  begin
    insert into campo.reporte_registro (reporte_id, xy_manual) values (pg_temp.val('viejo')::uuid, false);
    update campo.reporte_registro set xy_manual = true where reporte_id = pg_temp.val('viejo')::uuid;
    perform pg_temp.ok('01.09 reporte_registro no se modifica (solo inserción)', false);
  exception when others then perform pg_temp.ok('01.09 reporte_registro no se modifica (solo inserción)', true);
  end;
end $p1$;

-- ===================== 02. El sello y el PDF de un reporte de antes, después de migrar =====================
do $p2$
declare r jsonb; l jsonb; ADM text := 'ztrf.admin@emdupar.gov.co';
begin
  r := pg_temp.pdf(ADM, pg_temp.val('viejo')::uuid);
  perform pg_temp.ok('02.01 el sello de un reporte de antes es IGUAL después de la migración', r ->> 'sello' = pg_temp.val('sello_viejo'), (r ->> 'sello') || ' vs ' || pg_temp.val('sello_viejo'));
  perform pg_temp.ok('02.02 su cabecera y sus fotos en el PDF quedan iguales', (r -> 'cabecera')::text = pg_temp.val('cab_viejo') and (r -> 'fotos')::text = pg_temp.val('fotos_viejo'), (r -> 'cabecera')::text);
  l := pg_temp.lista(ADM, pg_temp.val('viejo')::uuid);
  perform pg_temp.ok('02.03 en la lista, lo de antes sigue igual y lo nuevo viene vacío (xy_manual y sin_ubicacion nulos, 0 fotos adjuntadas)',
    (l - array['xy_manual', 'sin_ubicacion_dispositivo', 'direccion', 'barrio', 'referencia', 'fotos_adjuntadas']) = pg_temp.val('lista_vieja')::jsonb
    and l -> 'xy_manual' = 'null'::jsonb and l -> 'sin_ubicacion_dispositivo' = 'null'::jsonb and (l ->> 'fotos_adjuntadas')::int = 0, l::text);
  r := pg_temp.detalle(ADM, pg_temp.val('viejo')::uuid);
  perform pg_temp.ok('02.04 el detalle de un reporte de antes trae «registro» nulo y las fotos con origen camara',
    r -> 'reporte' -> 'registro' = 'null'::jsonb and (select bool_and(f ->> 'origen' = 'camara') from jsonb_array_elements(r -> 'fotos') f), left(r::text, 400));
end $p2$;

-- ===================== 03. Operador de campo: sigue igual (cámara y GPS); queda dónde estaba =====================
do $p3$
declare r jsonb; n0 bigint; OP text := 'ztrf.op@emdupar.gov.co'; G jsonb := '{"lat_registro": 10.460001, "lon_registro": -73.250002, "precision_registro_m": 6.24}';
begin
  r := pg_temp.reg(OP, 'otro', '[{"origen": "camara"}]', G);
  perform pg_temp.ok('03.01 el operador registra con cámara y GPS (y la ubicación del dispositivo)', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.ok('03.02 queda su fila: XY no digitado, ubicación del dispositivo con 6 decimales y precisión con 1',
    exists (select 1 from campo.reporte_registro where reporte_id = (r ->> '_id')::uuid and not xy_manual and lat_registro = 10.460001 and lon_registro = -73.250002 and precision_registro_m = 6.2));
  perform pg_temp.ok('03.03 su foto queda de cámara', (select origen from campo.reporte_fotos where reporte_id = (r ->> '_id')::uuid) = 'camara');
  select count(*) into n0 from campo.reportes where autor = OP;
  r := pg_temp.reg(OP, 'otro', '[{"origen": "galeria"}]', G);
  perform pg_temp.ok('03.04 el operador NO puede adjuntar una foto de la galería (403)', pg_temp.err(r) = '42501' and pg_temp.msg(r) ~ 'supervisor', r::text);
  r := pg_temp.reg(OP, 'otro', '[{"origen": "archivo"}]', G);
  perform pg_temp.ok('03.05 el operador NO puede adjuntar una foto de un archivo (403)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', G || '{"xy_manual": true}', 10.47, -73.26, null);
  perform pg_temp.ok('03.06 el operador NO puede digitar el XY (403)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.reg(OP, 'otro', '[{"origen": "camara"}, {"origen": "galeria"}]', null);
  perform pg_temp.ok('03.07 tampoco sin el bloque del registro (una foto de galería basta para el rechazo)', pg_temp.err(r) = '42501', r::text);
  perform pg_temp.ok('03.08 los rechazos no dejaron reportes ni filas', (select count(*) from campo.reportes where autor = OP) = n0);
  r := pg_temp.reg(OP, 'otro', '[{"origen": "selfie"}]', G);
  perform pg_temp.ok('03.09 un origen de foto inventado se rechaza (400)', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', G, 10.46, -73.25, null, '123456', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('03.10 la visita inefectiva del operador sigue exigiendo la precisión del GPS', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'precisión', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', null);
  perform pg_temp.ok('03.11 la llamada de la Edge de antes (sin p_registro) sigue funcionando y no deja fila',
    pg_temp.err(r) = 'OK' and not exists (select 1 from campo.reporte_registro where reporte_id = (r ->> '_id')::uuid), r::text);
end $p3$;

-- ===================== 04. Sin permisos =====================
do $p4$
declare r jsonb; S text := 'ztrf.sin@emdupar.gov.co';
begin
  r := pg_temp.reg(S, 'otro', '[{}]', '{"lat_registro": 10.46, "lon_registro": -73.25}');
  perform pg_temp.ok('04.01 sin permisos no registra (403, ya en la reserva)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_listar_reportes(%L, ''{}''::jsonb, null)', S));
  perform pg_temp.ok('04.02 sin permisos no ve la lista (403)', pg_temp.err(r) = '42501', r::text);
end $p4$;

-- ===================== 05. Supervisor de Comercial: galería, archivo y XY digitado =====================
do $p5$
declare r jsonb; l jsonb; d jsonb; p jsonb; v_id uuid; SUP text := 'ztrf.sup@emdupar.gov.co'; ADM text := 'ztrf.admin@emdupar.gov.co';
  G jsonb := '{"xy_manual": true, "lat_registro": 10.4801, "lon_registro": -73.2701, "precision_registro_m": 12}';
begin
  r := pg_temp.reg(SUP, 'otro', '[{"origen": "galeria"}, {"origen": "archivo"}]', G, 10.461234, -73.251234, null);
  perform pg_temp.ok('05.01 el supervisor registra con galería, archivo y XY digitado', pg_temp.err(r) = 'OK', r::text);
  v_id := (r ->> '_id')::uuid; perform pg_temp.guardar('sup_flex', v_id::text);
  perform pg_temp.ok('05.02 queda marcado: xy_manual, el XY digitado como punto y la ubicación del dispositivo aparte',
    exists (select 1 from campo.reporte_registro rr join campo.reportes x on x.id = rr.reporte_id where rr.reporte_id = v_id and rr.xy_manual
              and x.lat = 10.461234 and x.lon = -73.251234 and x.precision_m is null and rr.lat_registro = 10.4801 and rr.lon_registro = -73.2701));
  perform pg_temp.ok('05.03 el origen de cada foto queda guardado (galeria, archivo)',
    (select string_agg(origen, ',' order by orden) from campo.reporte_fotos where reporte_id = v_id) = 'galeria,archivo');
  l := pg_temp.lista(SUP, v_id);
  perform pg_temp.ok('05.04 la lista lo marca: xy_manual, con ubicación del dispositivo y 2 fotos adjuntadas',
    l -> 'xy_manual' = 'true'::jsonb and l -> 'sin_ubicacion_dispositivo' = 'false'::jsonb and (l ->> 'fotos_adjuntadas')::int = 2, l::text);
  d := pg_temp.detalle(SUP, v_id);
  perform pg_temp.ok('05.05 el detalle trae las dos posiciones y la distancia entre ellas (unos 2,9 km)',
    d -> 'reporte' -> 'registro' -> 'xy_manual' = 'true'::jsonb and (d -> 'reporte' -> 'registro' ->> 'distancia_m')::numeric between 2500 and 3500
    and (select string_agg(f ->> 'origen', ',' order by (f ->> 'orden')::int) from jsonb_array_elements(d -> 'fotos') f) = 'galeria,archivo', left((d -> 'reporte')::text, 600));
  -- revisión previa inefectiva (lleva PDF) con XY digitado: exenta de la precisión del GPS
  r := pg_temp.reg(SUP, 'revision_previa', '[{"etiqueta": "fachada_predio", "origen": "galeria"}]', G, 10.462, -73.252, null, '123456', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('05.06 la visita inefectiva con XY digitado del supervisor no exige la precisión del GPS', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('sup_pdf', r ->> '_id');
  p := pg_temp.pdf(SUP, (r ->> '_id')::uuid);
  perform pg_temp.ok('05.07 el PDF dice «XY digitado — registrado desde otro punto», desde dónde y el origen de la foto',
    pg_temp.cab(p, 'Ubicación') ~ 'XY digitado — registrado desde otro punto' and pg_temp.cab(p, 'Registrado desde') = '10.480100, -73.270100 (precisión 12.0 m)'
    and p -> 'fotos' -> 0 ->> 'etiqueta' ~ 'adjuntada desde la galería', (p -> 'cabecera')::text || (p -> 'fotos')::text);
  -- sin ubicación del dispositivo
  r := pg_temp.reg(SUP, 'otro', '[{"origen": "galeria"}]', '{"xy_manual": true}', 10.463, -73.253, null);
  perform pg_temp.ok('05.08 sin ubicación del dispositivo, el supervisor registra igual', pg_temp.err(r) = 'OK', r::text);
  l := pg_temp.lista(SUP, (r ->> '_id')::uuid);
  perform pg_temp.ok('05.09 y queda la marca «sin ubicación del dispositivo» en la lista', l -> 'sin_ubicacion_dispositivo' = 'true'::jsonb, l::text);
  r := pg_temp.reg(SUP, 'revision_previa', '[{"etiqueta": "fachada_predio", "origen": "archivo"}]', '{"xy_manual": true}', 10.464, -73.254, null, '123456', 'inefectivo', 'nadie_atiende');
  p := pg_temp.pdf(SUP, (r ->> '_id')::uuid);
  perform pg_temp.ok('05.10 en el PDF: «Registrado desde: Sin ubicación del dispositivo»', pg_temp.cab(p, 'Registrado desde') = 'Sin ubicación del dispositivo', (p -> 'cabecera')::text);
  -- topes del XY digitado
  r := pg_temp.reg(SUP, 'otro', '[{}]', '{"xy_manual": true}', 4.711, -74.072, null);
  perform pg_temp.ok('05.11 un XY digitado fuera de la zona de Valledupar se rechaza (400) y dice el rango', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'fuera de la zona de Valledupar', r::text);
  r := pg_temp.reg(SUP, 'otro', '[{}]', '{"xy_manual": true}', 10.46, -73.25, 4);
  perform pg_temp.ok('05.12 un XY digitado no lleva precisión (400)', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'no lleva precisión', r::text);
  r := pg_temp.reg(SUP, 'otro', '[{}]', null, 4.711, -74.072, 5);
  perform pg_temp.ok('05.13 el XY del GPS fuera de la zona sigue sin rechazarse (aviso de zona)', pg_temp.err(r) = 'OK' and r -> 'aviso_zona' = 'true'::jsonb, r::text);
  -- descarga
  r := pg_temp.rpc(format('public.geoportal_campo_descarga_iniciar(%L, ''{}''::jsonb, ''xlsx'', false, null)', SUP));
  d := pg_temp.rpc(format('public.geoportal_campo_descarga_pagina(%L, %s, null, 5000)', SUP, r ->> 'descarga_id'));
  select e into l from jsonb_array_elements(d -> 'registros') e where (e ->> 'id')::uuid = pg_temp.val('sup_flex')::uuid;
  perform pg_temp.ok('05.14 la descarga trae xy_manual, la ubicación del dispositivo, la distancia y las fotos adjuntadas (y no el correo)',
    l -> 'xy_manual' = 'true'::jsonb and (l ->> 'lat_registro')::numeric = 10.4801 and (l ->> 'distancia_registro_m')::numeric > 2500 and (l ->> 'fotos_adjuntadas')::int = 2 and not (l ? 'autor'), l::text);
  perform pg_temp.rpc(format('public.geoportal_campo_descarga_cerrar(%L, %s, 1, ''completa'', null)', SUP, r ->> 'descarga_id'));
  -- reenvío idempotente
  r := pg_temp.reg(SUP, 'otro', null, G, 10.461234, -73.251234, null, null, null, null, false, pg_temp.val('sup_flex')::uuid);
  perform pg_temp.ok('05.15 el reenvío con el mismo id responde «repetido» y no agrega otra fila', pg_temp.err(r) = 'OK' and r -> 'repetido' = 'true'::jsonb
    and (select count(*) from campo.reporte_registro where reporte_id = pg_temp.val('sup_flex')::uuid) = 1, r::text);
  -- administrador
  r := pg_temp.reg(ADM, 'otro', '[{"origen": "archivo"}]', '{"xy_manual": true, "lat_registro": 10.45, "lon_registro": -73.24}', 10.465, -73.255, null);
  perform pg_temp.ok('05.16 el administrador también puede (archivo y XY digitado)', pg_temp.err(r) = 'OK', r::text);
end $p5$;

-- ===================== 06. Forma del bloque y dirección opcional =====================
do $p6$
declare r jsonb; v_id uuid; OP text := 'ztrf.op2@emdupar.gov.co'; SUP text := 'ztrf.sup@emdupar.gov.co';
begin
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"lat_registro": 10.46, "lon_registro": -73.25, "inventada": 1}');
  perform pg_temp.ok('06.01 una clave que no existe en el registro se rechaza y se nombra', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'inventada', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"lat_registro": 10.46}');
  perform pg_temp.ok('06.02 latitud sin longitud se rechaza', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"lat_registro": "10.46", "lon_registro": -73.25}');
  perform pg_temp.ok('06.03 una coordenada en texto se rechaza', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"precision_registro_m": 5}');
  perform pg_temp.ok('06.04 precisión sin ubicación se rechaza', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"xy_manual": "no"}');
  perform pg_temp.ok('06.05 xy_manual que no es sí o no se rechaza', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', jsonb_build_object('direccion', repeat('x', 121)));
  perform pg_temp.ok('06.06 dirección de 121 caracteres se rechaza (tope 120)', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ '120', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', jsonb_build_object('barrio', repeat('x', 81)));
  perform pg_temp.ok('06.07 barrio de 81 caracteres se rechaza (tope 80)', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ '80', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', jsonb_build_object('referencia', repeat('x', 201)));
  perform pg_temp.ok('06.08 referencia de 201 caracteres se rechaza (tope 200)', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ '200', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', jsonb_build_object('direccion', '  [PRUEBA ZTRF] CRA 9 # 12-30 ', 'barrio', 'Centro', 'referencia', 'Frente al parque', 'lat_registro', 10.46, 'lon_registro', -73.25));
  v_id := (r ->> '_id')::uuid;
  perform pg_temp.ok('06.09 Reportar anomalía con dirección, barrio y referencia (el operador también: es opcional, no es registro flexible)',
    pg_temp.err(r) = 'OK' and exists (select 1 from campo.reporte_registro where reporte_id = v_id and direccion = '[PRUEBA ZTRF] CRA 9 # 12-30' and barrio = 'Centro' and referencia = 'Frente al parque' and not xy_manual), r::text);
  perform pg_temp.ok('06.10 la lista y el detalle muestran la dirección',
    pg_temp.lista(SUP, v_id) ->> 'barrio' = 'Centro' and pg_temp.detalle(SUP, v_id) -> 'reporte' -> 'registro' ->> 'direccion' = '[PRUEBA ZTRF] CRA 9 # 12-30');
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"direccion": "   ", "lat_registro": 10.46, "lon_registro": -73.25}');
  perform pg_temp.ok('06.11 una dirección en blanco queda como vacía', pg_temp.err(r) = 'OK' and exists (select 1 from campo.reporte_registro where reporte_id = (r ->> '_id')::uuid and direccion is null), r::text);
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', '{"direccion": "CRA 1"}', 10.46, -73.25, 5, '123456', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('06.12 un formato con contrato obligatorio no lleva dirección (400)', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'no lleva dirección', r::text);
  r := pg_temp.reg(OP, 'instalacion_acometida', '[{"etiqueta": "fachada_predio"}]', '{"direccion": "[PRUEBA ZTRF] CLL 5 # 3-10", "barrio": "Primero de Mayo", "lat_registro": 10.46, "lon_registro": -73.25}',
                   10.46, -73.25, 5, null, 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('06.13 un formato con contrato opcional (instalación de acometida) sí lleva dirección, y su PDF la muestra', pg_temp.err(r) = 'OK'
    and pg_temp.cab(pg_temp.pdf(SUP, (r ->> '_id')::uuid), 'Barrio') = 'Primero de Mayo', r::text);
end $p6$;

-- ===================== 07. Entrada de Técnica (Reportar anomalía compartida) y el perfil dual =====================
do $p7$
declare r jsonb; PL text := 'ztrf.planta@emdupar.gov.co'; PL2 text := 'ztrf.planta2@emdupar.gov.co'; DU text := 'ztrf.dual@emdupar.gov.co';
  G jsonb := '{"lat_registro": 10.47, "lon_registro": -73.26, "precision_registro_m": 8, "direccion": "[PRUEBA ZTRF] Planta de tratamiento"}';
begin
  r := pg_temp.rpc(format('public.geoportal_campo_tec_formulario(%L)', PL));
  perform pg_temp.ok('07.01 el operador de planta con «Reportar anomalía» de Técnica abre el formulario (sin «supervisar»)',
    pg_temp.err(r) = 'OK' and r -> 'puede' -> 'supervisar' = 'false'::jsonb and r -> 'formularios' ? 'anomalia_compartida', left(r::text, 300));
  r := pg_temp.reg(PL, 'otro', '[{"origen": "camara"}]', G, 10.47, -73.26, 8, null, null, null, true);
  perform pg_temp.ok('07.02 el operador de planta registra desde Técnica, con la ubicación del dispositivo y la dirección', pg_temp.err(r) = 'OK' and r ->> 'area' = 'tecnica'
    and exists (select 1 from campo.reportes x join campo.reporte_registro rr on rr.reporte_id = x.id where x.id = (r ->> '_id')::uuid and x.area = 'tecnica' and not rr.xy_manual and rr.direccion is not null), r::text);
  r := pg_temp.reg(PL, 'otro', '[{}]', null, 10.47, -73.26, 8, null, null, null, true);
  perform pg_temp.ok('07.03 la entrada de Técnica de antes (sin p_registro) sigue funcionando', pg_temp.err(r) = 'OK' and r ->> 'area' = 'tecnica', r::text);
  r := pg_temp.reg(PL, 'otro', '[{"origen": "galeria"}]', G, 10.47, -73.26, 8, null, null, null, true);
  perform pg_temp.ok('07.04 desde Técnica no se adjuntan fotos (403)', pg_temp.err(r) = '42501' and pg_temp.msg(r) ~ 'Técnica', r::text);
  r := pg_temp.reg(PL2, 'otro', '[{}]', G, 10.47, -73.26, 8, null, null, null, true);
  perform pg_temp.ok('07.05 el operador de planta SIN «Reportar anomalía» sigue sin entrar (403)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.reg(DU, 'otro', '[{}]', G || '{"xy_manual": true}', 10.47, -73.26, null, null, null, null, true);
  perform pg_temp.ok('07.06 el dual, aunque es supervisor de Comercial, no digita el XY desde Técnica (403)', pg_temp.err(r) = '42501' and pg_temp.msg(r) ~ 'Técnica', r::text);
  r := pg_temp.reg(DU, 'otro', '[{"origen": "galeria"}]', '{"xy_manual": true, "lat_registro": 10.47, "lon_registro": -73.26}', 10.47, -73.26, null);
  perform pg_temp.ok('07.07 el dual, desde Comercial, sí puede (es supervisor de Comercial)', pg_temp.err(r) = 'OK' and r ->> 'area' is null, r::text);
  perform pg_temp.ok('07.08 el reporte de Técnica no queda marcado como de Comercial ni al revés',
    (select area from campo.reportes where id = (r ->> '_id')::uuid) is null);
end $p7$;

-- ===================== 08. El sello de un reporte NUEVO incluye su fila de reporte_registro =====================
do $p8$
declare s1 text; s2 text; v_id uuid := pg_temp.val('sup_pdf')::uuid; SUP text := 'ztrf.sup@emdupar.gov.co';
begin
  s1 := pg_temp.pdf(SUP, v_id) ->> 'sello';
  -- Solo en el ensayo (todo se deshace): se apaga el disparador de solo inserción para cambiar la fila y ver que el sello cambia
  alter table campo.reporte_registro disable trigger t_solo_agregar;
  update campo.reporte_registro set referencia = '[PRUEBA ZTRF] cambiada' where reporte_id = v_id;
  s2 := pg_temp.pdf(SUP, v_id) ->> 'sello';
  update campo.reporte_registro set referencia = null where reporte_id = v_id;
  alter table campo.reporte_registro enable trigger t_solo_agregar;
  perform pg_temp.ok('08.01 si cambia la fila de reporte_registro de un reporte nuevo, su sello cambia', s1 is not null and s2 is not null and s1 <> s2, s1 || ' / ' || s2);
  perform pg_temp.ok('08.02 y vuelve al mismo sello con la fila como estaba', pg_temp.pdf(SUP, v_id) ->> 'sello' = s1);
  perform pg_temp.ok('08.03 el sello de un reporte de antes sigue igual', pg_temp.pdf(SUP, pg_temp.val('viejo')::uuid) ->> 'sello' = pg_temp.val('sello_viejo'));
end $p8$;

-- ===================== 09. «Avisos y actividades derivadas»: conteo de pendientes y descarga auditada =====================
do $p9$
declare r jsonb; i jsonb; pg jsonb; v_o uuid := pg_temp.val('viejo')::uuid; v_d bigint; SUP text := 'ztrf.sup@emdupar.gov.co'; ADM text := 'ztrf.admin@emdupar.gov.co';
  OP text := 'ztrf.op@emdupar.gov.co'; n0 integer; p0 integer;
begin
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas(%L, ''{}''::jsonb, null)', SUP));
  n0 := (r ->> 'total')::int; p0 := (r ->> 'pendientes')::int;
  perform pg_temp.ok('09.01 la lista de derivadas trae «total» y «pendientes»', pg_temp.err(r) = 'OK' and n0 is not null and p0 is not null, left(r::text, 300));
  insert into campo.derivadas (origen_id, contrato, actividad) values (v_o, '991001', 'cambio_medidor'), (v_o, '991001', 'accesorios'), (v_o, '991001', 'reubicacion_cajilla') ;
  select min(id) into v_d from campo.derivadas where contrato = '991001';
  insert into campo.derivada_eventos (derivada_id, tipo_evento, motivo, autor) values (v_d, 'anulada', '[PRUEBA ZTRF] anulada en el ensayo', SUP);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas(%L, ''{"limite": 1}''::jsonb, null)', SUP));
  perform pg_temp.ok('09.02 total y pendientes cuentan todo, no solo la página (límite 1)', (r ->> 'total')::int = n0 + 3 and (r ->> 'pendientes')::int = p0 + 2
    and jsonb_array_length(r -> 'filas') = 1 and r ->> 'siguiente' is not null, left(r::text, 300));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas(%L, ''{"estado": "anulada", "contrato": "991001"}''::jsonb, null)', SUP));
  perform pg_temp.ok('09.03 con filtro de estado: el total sigue el filtro y los pendientes no (2 pendientes del contrato)',
    (r ->> 'total')::int = 1 and (r ->> 'pendientes')::int = 2, left(r::text, 300));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas(%L, ''{"estado": "inventado"}''::jsonb, null)', SUP));
  perform pg_temp.ok('09.04 un estado inventado se rechaza como antes', pg_temp.err(r) = '22023', r::text);
  -- descarga
  i := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{"contrato": "991001"}''::jsonb, ''xlsx'', false, null)', SUP));
  perform pg_temp.ok('09.05 el supervisor inicia la descarga: 3 filas y queda auditada', pg_temp.err(i) = 'OK' and (i ->> 'total')::int = 3
    and exists (select 1 from public.geoportal_auditoria where id = (i ->> 'descarga_id')::bigint and accion = 'campo_derivadas_descarga_iniciar' and email = SUP), i::text);
  pg := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_pagina(%L, %s, null, 2)', SUP, i ->> 'descarga_id'));
  perform pg_temp.ok('09.06 primera página de 2, sin los correos de las personas, sin datos de contacto y sin texto libre ni motivo de cierre', pg_temp.err(pg) = 'OK'
    and (pg ->> 'devueltos')::int = 2 and pg -> 'hay_mas' = 'true'::jsonb
    and pg::text !~ 'ztrf\.(op|sup)@' and pg::text !~ '"(cedula|telefono|celular|correo|texto|direccion_correcta|motivo)"' and pg::text !~ 'anulada en el ensayo', left(pg::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_pagina(%L, %s, %s, 2)', SUP, i ->> 'descarga_id', pg ->> 'ultimo_id'));
  perform pg_temp.ok('09.07 la segunda página trae la que falta', (r ->> 'devueltos')::int = 1 and r -> 'hay_mas' = 'false'::jsonb, left(r::text, 200));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_pagina(%L, %s, null, 10)', ADM, i ->> 'descarga_id'));
  perform pg_temp.ok('09.08 otra persona no lee la descarga ajena (404)', pg_temp.err(r) = 'P0002', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_cerrar(%L, %s, 3, ''completa'', null)', SUP, i ->> 'descarga_id'));
  perform pg_temp.ok('09.09 se cierra y queda auditada', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'false'::jsonb
    and exists (select 1 from public.geoportal_auditoria where accion = 'campo_derivadas_descarga_cerrar' and referencia = i ->> 'descarga_id'), r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_pagina(%L, %s, null, 10)', SUP, i ->> 'descarga_id'));
  perform pg_temp.ok('09.10 cerrada, ya no se leen páginas (409)', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_cerrar(%L, %s, 3, ''completa'', null)', SUP, i ->> 'descarga_id'));
  perform pg_temp.ok('09.11 cerrar otra vez responde «repetida»', r -> 'repetida' = 'true'::jsonb, r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{}''::jsonb, ''xlsx'', true, null)', SUP));
  perform pg_temp.ok('09.12 el supervisor no puede pedir los correos (403)', pg_temp.err(r) = '42501', r::text);
  i := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{"contrato": "991001"}''::jsonb, ''csv'', true, null)', ADM));
  pg := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_pagina(%L, %s, null, 10)', ADM, i ->> 'descarga_id'));
  perform pg_temp.ok('09.13 el administrador que los pide sí recibe el correo de quien registró', pg::text ~ 'ztrf\.op@', left(pg::text, 300));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{}''::jsonb, ''xlsx'', false, null)', OP));
  perform pg_temp.ok('09.14 el operador no descarga derivadas (403)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{"contrato": "000000"}''::jsonb, ''xlsx'', false, null)', SUP));
  perform pg_temp.ok('09.15 sin filas no se abre la descarga', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'No hay', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{}''::jsonb, ''pdf'', false, null)', SUP));
  perform pg_temp.ok('09.16 formato distinto de Excel o CSV se rechaza', pg_temp.err(r) = '22023', r::text);
end $p9$;

-- ===================== 10. Reglas de producción =====================
do $p10$
begin
  perform pg_temp.ok('10.01 ninguna función de campo con DELETE o UPDATE sin WHERE', {{SIN_WHERE_CAMPO}} = 0);
  perform pg_temp.ok('10.02 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
  perform pg_temp.ok('10.03 las RPC nuevas y cambiadas, solo para service_role',
    has_function_privilege('service_role', '{{F_CREAR_NUEVA}}', 'execute') and not has_function_privilege('authenticated', '{{F_CREAR_NUEVA}}', 'execute') and not has_function_privilege('anon', '{{F_CREAR_NUEVA}}', 'execute')
    and has_function_privilege('service_role', '{{F_TEC_NUEVA}}', 'execute') and not has_function_privilege('authenticated', '{{F_TEC_NUEVA}}', 'execute')
    and has_function_privilege('service_role', 'public.geoportal_campo_derivadas_descarga_pagina(text,bigint,bigint,integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.geoportal_campo_derivadas_descarga_pagina(text,bigint,bigint,integer)', 'execute')
    and not has_function_privilege('service_role', 'campo.f_derivadas_filtradas(jsonb)', 'execute') and not has_function_privilege('service_role', 'campo.f_derivada_descarga(jsonb,boolean)', 'execute'));
  perform pg_temp.ok('10.04 las 4 funciones de permisos vivas no cambiaron', {{PERMISOS_IGUALES}});
  perform pg_temp.ok('10.05 la auditoría de crear no lleva coordenadas ni dirección, solo marcas',
    (select bool_and(detalle ? 'xy_manual' and detalle::text !~ '10\.4801|PRUEBA ZTRF\] CRA|Centro') from public.geoportal_auditoria
      where accion = 'campo_crear_reporte' and email in ('ztrf.sup@emdupar.gov.co', 'ztrf.op2@emdupar.gov.co') and detalle ? 'xy_manual'));
end $p10$;

-- ===================== REVERSA, dentro de esta misma transacción =====================
{{CUERPO_REVERSA}}

-- ===================== 11. Después de la reversa =====================
do $p11$
declare r jsonb; OP text := 'ztrf.op@emdupar.gov.co'; ADM text := 'ztrf.admin@emdupar.gov.co';
begin
  perform pg_temp.ok('11.01 la huella de campo vuelve a la publicada', ({{HUELLA_CAMPO_Q}}) = '{{HUELLA_CAMPO}}');
  perform pg_temp.ok('11.02 el sello de un reporte de antes es IGUAL después de la reversa', pg_temp.pdf(ADM, pg_temp.val('viejo')::uuid) ->> 'sello' = pg_temp.val('sello_viejo'));
  perform pg_temp.ok('11.03 vuelven las firmas publicadas (sin p_registro)', to_regprocedure('{{F_CREAR}}') is not null and to_regprocedure('{{F_CREAR_NUEVA}}') is null
    and to_regprocedure('{{F_TEC}}') is not null and to_regprocedure('{{F_TEC_NUEVA}}') is null);
  r := pg_temp.reg(OP, 'otro', '[{}]', null);
  perform pg_temp.ok('11.04 con la función publicada se registra igual que antes', pg_temp.err(r) = 'OK' and (select origen from campo.reporte_fotos where reporte_id = (r ->> '_id')::uuid) = 'camara', r::text);
  perform pg_temp.ok('11.05 nada se borró: las filas de reporte_registro y el origen de las fotos siguen',
    exists (select 1 from campo.reporte_registro where reporte_id = pg_temp.val('sup_flex')::uuid and xy_manual)
    and (select string_agg(origen, ',' order by orden) from campo.reporte_fotos where reporte_id = pg_temp.val('sup_flex')::uuid) = 'galeria,archivo');
  perform pg_temp.ok('11.06 las 5 funciones nuevas ya no están', to_regprocedure('campo.f_derivadas_filtradas(jsonb)') is null
    and to_regprocedure('public.geoportal_campo_derivadas_descarga_iniciar(text,jsonb,text,boolean,text)') is null);
  perform pg_temp.ok('11.07 la huella del acta y la de Técnica siguen iguales', ({{HUELLA_ACTA_Q}}) = '{{HUELLA_ACTA}}' and ({{HUELLA_TECNICA_Q}}) = '{{HUELLA_TECNICA}}');
end $p11$;

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztrf_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;
