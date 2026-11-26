-- =====================================================================
-- CONSULTAR DIRECCIONES (Code A, 25-nov) · 70 — ENSAYO: datos de prueba y un reporte de antes → MIGRACIÓN → pruebas → REVERSA → pruebas; termina en el ERROR
-- esperado (todo se deshace). Datos propios con prefijo ZTDIR (correos ztdir.*@emdupar.gov.co; contratos de 12 dígitos 9918000000NN, que se comprueba que no
-- existen). Las filas de prueba de cartera_suscripcion y catastro_valledupar también se deshacen. Las RPC corren como service_role con los topes de producción.
-- Perfiles: administrador, supervisor de Comercial, operador de campo (SIN Análisis), analista (campo y Análisis), sin permisos, y dos operadores de planta.
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
create function pg_temp.dir(p_quien text, p_contrato text, p_tec boolean default false) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_%sdireccion_contrato(%L, %L, null)', case when p_tec then 'tec_' else '' end, p_quien, p_contrato)) $f$;
create function pg_temp.consultar(p_quien text, p_contrato text) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_analisis_contrato(%L, %L, null)', p_quien, p_contrato)) $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico, ver_analisis_contrato) values
  ('ztdir.admin@emdupar.gov.co', 'ZTDIR Administrador', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('ztdir.sup@emdupar.gov.co', 'ZTDIR Supervisor', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('ztdir.op@emdupar.gov.co', 'ZTDIR Operario sin Análisis', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztdir.ana@emdupar.gov.co', 'ZTDIR Analista', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, true),
  ('ztdir.sin@emdupar.gov.co', 'ZTDIR Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('ztdir.planta@emdupar.gov.co', 'ZTDIR Planta con anomalía', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, false),
  ('ztdir.planta2@emdupar.gov.co', 'ZTDIR Planta sin anomalía', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, false);
insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values
  ('ztdir.planta@emdupar.gov.co', 'asignar_formulario', 'entrada', 'ztdir.admin@emdupar.gov.co'), ('ztdir.planta@emdupar.gov.co', 'asignar_formulario', 'anomalia_compartida', 'ztdir.admin@emdupar.gov.co'),
  ('ztdir.planta2@emdupar.gov.co', 'asignar_formulario', 'entrada', 'ztdir.admin@emdupar.gov.co');

-- ===================== 00. Datos de prueba y lo de ANTES de la migración =====================
do $p0$
declare r jsonb; OP text := 'ztdir.op@emdupar.gov.co'; ADM text := 'ztdir.admin@emdupar.gov.co';
begin
  perform pg_temp.ok('00.01 los contratos de prueba no existen en la base (ni en cartera, ni en el censo, ni en reportes)',
    not exists (select 1 from public.cartera_suscripcion where contrato like '9918000000__') and not exists (select 1 from public.catastro_valledupar where cod_usuario like '9918000000__')
    and not exists (select 1 from campo.reportes where contrato like '9918000000__'));
  -- A: direcciones distintas en cartera y censo · B: solo cartera (sin predio en el censo) · C: dos predios en el censo · X: no existe
  insert into public.cartera_suscripcion (contrato, estado, nombre, telefono, direccion, barrio, deuda_total, periodo_carga) values
    ('991800000001', 'ACTIVO', 'ZTDIR PERSONA UNO', '3001112233', 'CRA 9 # 12-30 TORRE 2 APTO 301', 'CENTRO', 123456, '20261123'),
    ('991800000002', 'ACTIVO', 'ZTDIR PERSONA DOS', '3002223344', 'CLL 5 # 3-10', 'LOS MAYALES', 0, '20261123'),
    ('991800000003', 'ACTIVO', 'ZTDIR PERSONA TRES', '3003334455', 'MZ 4 CASA 7', 'PRIMERO DE MAYO', 0, '20261123');
  insert into public.catastro_valledupar (cod_usuario, direccion, barrio, clase_uso, act_eco, unih, uninh, telefono) values
    ('991800000001', 'CRA 9 12 30  ', 'CENTRO ', 'RESIDENCIAL RESIDENCIAL  ', 'NO APLICA', '- 4- - - CASA- CS- 1- - - - ,- - - - - APTO- AP- 101- - - - ,- ', 'NO APLICA', '3009998877'),
    ('991800000003', 'MANZANA 4 CASA 7', 'PRIMERO DE MAYO', 'RESIDENCIAL COMERCIAL', 'TIENDA', null, '- - - - - LC- 101- - - - COMERCIAL- SIN ACTIVIDAD- Local- ,- ', null),
    ('991800000003', 'MANZANA 4 CASA 7 B', 'PRIMERO DE MAYO', 'COMERCIAL', 'NO APLICA', null, null, null);
  -- un reporte de antes con contrato (revisión previa inefectiva, lleva PDF) y su sello
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', null, 10.46, -73.25, 5, '991800000001', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('00.02 antes: una revisión previa con contrato se registra', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('viejo', r ->> '_id');
  r := pg_temp.pdf(ADM, pg_temp.val('viejo')::uuid);
  perform pg_temp.guardar('sello_viejo', r ->> 'sello'); perform pg_temp.guardar('cab_viejo', (r -> 'cabecera')::text);
  perform pg_temp.ok('00.03 antes: la consulta del analista guarda la bitácora sin «via»', not exists (select 1 from information_schema.columns where table_schema = 'campo' and table_name = 'consultas_analisis' and column_name = 'via'));
  r := pg_temp.consultar('ztdir.ana@emdupar.gov.co', '991800000001');
  perform pg_temp.guardar('consulta_vieja', (r - 'gestiones')::text);
  perform pg_temp.ok('00.04 antes: «Consultar» mezcla las direcciones (la del censo primero)', r -> 'comercial' ->> 'direccion' = 'CRA 9 12 30' and not (r ? 'direcciones'), left(r::text, 300));
end $p0$;

-- ===================== MIGRACIÓN (guardia incluida) =====================
{{CUERPO_MIGRACION}}

-- ===================== 01. Estructura =====================
do $p1$
begin
  perform pg_temp.ok('01.01 la bitácora tiene via; lo de antes quedó como «analisis»', (select bool_and(via = 'analisis') from campo.consultas_analisis where autor like 'ztdir.%'));
  perform pg_temp.ok('01.02 campo.reporte_direccion_contrato: llave reporte_id, RLS, sin permisos para la API, SELECT para homelab_lectura',
    (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'campo.reporte_direccion_contrato'::regclass and contype = 'p') = 'PRIMARY KEY (reporte_id)'
    and (select relrowsecurity from pg_class where oid = 'campo.reporte_direccion_contrato'::regclass) and not has_table_privilege('service_role', 'campo.reporte_direccion_contrato', 'select')
    and not has_table_privilege('authenticated', 'campo.reporte_direccion_contrato', 'select') and has_table_privilege('homelab_lectura', 'campo.reporte_direccion_contrato', 'select'));
  perform pg_temp.ok('01.03 el parámetro limite_direccion_hora vale 60', (select valor from campo.parametros where clave = 'limite_direccion_hora') = 60);
  perform pg_temp.ok('01.04 la huella del acta y la de Técnica no cambiaron', ({{HUELLA_ACTA_Q}}) = '{{HUELLA_ACTA}}' and ({{HUELLA_TECNICA_Q}}) = '{{HUELLA_TECNICA}}');
  perform pg_temp.ok('01.05 el reporte de antes no tiene foto de direcciones', not exists (select 1 from campo.reporte_direccion_contrato where reporte_id = pg_temp.val('viejo')::uuid));
end $p1$;

-- ===================== 02. Consultar: dos direcciones y el predio =====================
do $p2$
declare r jsonb; ANA text := 'ztdir.ana@emdupar.gov.co';
begin
  r := pg_temp.consultar(ANA, '991800000001');
  perform pg_temp.ok('02.01 lo de antes sigue igual (encabezado: comercial.direccion; sin cambiar ninguna clave vieja)',
    ((r - 'gestiones' - 'direcciones' - 'predio') - 'cortes') = ((pg_temp.val('consulta_vieja')::jsonb) - 'cortes'), left(r::text, 400));
  perform pg_temp.ok('02.02 direcciones por separado: base comercial y catastro, cada una con su barrio (limpieza mínima)',
    r -> 'direcciones' -> 'comercial' ->> 'direccion' = 'CRA 9 # 12-30 TORRE 2 APTO 301' and r -> 'direcciones' -> 'comercial' ->> 'barrio' = 'CENTRO'
    and r -> 'direcciones' -> 'catastro' ->> 'direccion' = 'CRA 9 12 30' and r -> 'direcciones' -> 'catastro' ->> 'barrio' = 'CENTRO', (r -> 'direcciones')::text);
  perform pg_temp.ok('02.03 predio: clase de uso sin la palabra repetida, actividad, unidades tal cual (recortadas) y 1 predio',
    r -> 'predio' ->> 'clase_uso' = 'RESIDENCIAL' and r -> 'predio' ->> 'act_eco' = 'NO APLICA' and r -> 'predio' ->> 'uninh' = 'NO APLICA'
    and r -> 'predio' ->> 'unih' = '- 4- - - CASA- CS- 1- - - - ,- - - - - APTO- AP- 101- - - - ,-' and (r -> 'predio' ->> 'predios_total')::int = 1, (r -> 'predio')::text);
  r := pg_temp.consultar(ANA, '991800000002');
  perform pg_temp.ok('02.04 sin predio en el censo: catastro y predio nulos; la base comercial sí', r -> 'direcciones' -> 'catastro' = 'null'::jsonb and r -> 'predio' = 'null'::jsonb
    and r -> 'direcciones' -> 'comercial' ->> 'direccion' = 'CLL 5 # 3-10', left(r::text, 300));
  r := pg_temp.consultar(ANA, '991800000003');
  perform pg_temp.ok('02.05 dos predios: los datos del principal (menor id) y «2 predios»; la mezcla de clase de uso se deja',
    r -> 'direcciones' -> 'catastro' ->> 'direccion' = 'MANZANA 4 CASA 7' and (r -> 'predio' ->> 'predios_total')::int = 2 and r -> 'predio' ->> 'clase_uso' = 'RESIDENCIAL COMERCIAL'
    and r -> 'predio' -> 'unih' = 'null'::jsonb and r -> 'predio' ->> 'uninh' like '%LC- 101%', (r -> 'predio')::text);
  perform pg_temp.ok('02.06 la consulta queda en la bitácora como «analisis»', (select count(*) from campo.consultas_analisis where autor = ANA and via = 'analisis') = 4);
end $p2$;

-- ===================== 03. La dirección del contrato desde los formatos =====================
do $p3$
declare r jsonb; OP text := 'ztdir.op@emdupar.gov.co'; SUP text := 'ztdir.sup@emdupar.gov.co'; ADM text := 'ztdir.admin@emdupar.gov.co'; n integer;
begin
  r := pg_temp.consultar(OP, '991800000001');
  perform pg_temp.ok('03.01 el operario SIN permiso de Análisis no puede «Consultar» (403)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.dir(OP, '991800000001');
  perform pg_temp.ok('03.02 pero sí ve la dirección del contrato en el formato: las dos, con su barrio, y que son distintas',
    pg_temp.err(r) = 'OK' and r -> 'encontrado' = 'true'::jsonb and r -> 'comercial' ->> 'direccion' = 'CRA 9 # 12-30 TORRE 2 APTO 301' and r -> 'catastro' ->> 'direccion' = 'CRA 9 12 30'
    and r -> 'distintas' = 'true'::jsonb, r::text);
  perform pg_temp.ok('03.03 nada más: ni nombre, ni teléfono, ni deuda', r::text !~ 'ZTDIR PERSONA|300111|300999|123456|deuda|nombre|telefono', r::text);
  r := pg_temp.dir(OP, '991800000002');
  perform pg_temp.ok('03.04 sin predio en el censo: solo la base comercial, «distintas» falso', r -> 'catastro' = 'null'::jsonb and r -> 'distintas' = 'false'::jsonb, r::text);
  r := pg_temp.dir(OP, '991800000009');
  perform pg_temp.ok('03.05 contrato inexistente: «no encontrado» y nada más', r = '{"encontrado": false, "contrato": "991800000009"}'::jsonb, r::text);
  r := pg_temp.dir(OP, '12A');
  perform pg_temp.ok('03.06 contrato con letras: 400', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.dir('ztdir.sin@emdupar.gov.co', '991800000001');
  perform pg_temp.ok('03.07 sin permisos: 403', pg_temp.err(r) = '42501', r::text);
  perform pg_temp.ok('03.08 cada consulta queda en la bitácora como «formato», también la inexistente (existe = falso)',
    (select count(*) from campo.consultas_analisis where autor = OP and via = 'formato') = 3
    and exists (select 1 from campo.consultas_analisis where autor = OP and via = 'formato' and contrato = '991800000009' and not existe));
  -- tope por hora (se baja a 4 solo en el ensayo): el operario ya lleva 3
  update campo.parametros set valor = 4 where clave = 'limite_direccion_hora';
  r := pg_temp.dir(OP, '991800000003');
  perform pg_temp.ok('03.09 la cuarta consulta de la hora pasa', pg_temp.err(r) = 'OK', r::text);
  r := pg_temp.dir(OP, '991800000009');
  perform pg_temp.ok('03.10 la quinta: límite (429) y lo dice, aunque el contrato no exista', pg_temp.err(r) = '53400' and pg_temp.msg(r) ~ 'límite de 4 consultas', r::text);
  perform pg_temp.ok('03.11 la rechazada no se cuenta en la bitácora', (select count(*) from campo.consultas_analisis where autor = OP and via = 'formato') = 4);
  for n in 1 .. 20 loop r := pg_temp.dir(SUP, '991800000009'); end loop;
  perform pg_temp.ok('03.12 el supervisor tiene 4 × 5 = 20 por hora', pg_temp.err(r) = 'OK' and pg_temp.err(pg_temp.dir(SUP, '991800000009')) = '53400');
  for n in 1 .. 25 loop r := pg_temp.dir(ADM, '991800000009'); end loop;
  perform pg_temp.ok('03.13 el administrador no tiene tope', pg_temp.err(r) = 'OK', r::text);
  update campo.parametros set valor = 60 where clave = 'limite_direccion_hora';
  r := pg_temp.dir(OP, '99999999');
  perform pg_temp.ok('03.14 el contrato comodín responde «comodín» sin direcciones', r ->> 'comodin' = 'true' and not (r ? 'comercial'), r::text);
end $p3$;

-- ===================== 04. «Observar» sigue exigiendo haber CONSULTADO (no basta la dirección del formato) =====================
do $p4$
declare r jsonb; ANA text := 'ztdir.ana@emdupar.gov.co';
begin
  r := pg_temp.dir(ANA, '991800000002');
  r := pg_temp.rpc(format('public.geoportal_campo_analisis_observar(%L, %L, %L, %L, null, null, null)', ANA, '991800000099', 'otra', '[PRUEBA ZTDIR] sin consultar'));
  perform pg_temp.ok('04.01 un contrato que solo se pidió desde un formato no habilita «observar»', pg_temp.err(r) = '55000' and pg_temp.msg(r) ~ 'Primero consulte', r::text);
  insert into campo.consultas_analisis (autor, contrato, existe, via) values (ANA, '991800000099', true, 'formato');
  r := pg_temp.rpc(format('public.geoportal_campo_analisis_observar(%L, %L, %L, %L, null, null, null)', ANA, '991800000099', 'otra', '[PRUEBA ZTDIR] formato no cuenta'));
  perform pg_temp.ok('04.02 ni aunque la bitácora diga que existe (via formato)', pg_temp.err(r) = '55000' and pg_temp.msg(r) ~ 'Primero consulte', r::text);
  insert into campo.consultas_analisis (autor, contrato, existe, via) values (ANA, '991800000099', true, 'analisis');
  r := pg_temp.rpc(format('public.geoportal_campo_analisis_observar(%L, %L, %L, %L, null, null, null)', ANA, '991800000099', 'otra', '[PRUEBA ZTDIR] consultado en Consultar'));
  perform pg_temp.ok('04.03 con la consulta de «Consultar» sí se puede observar (como antes)', pg_temp.err(r) = 'OK', r::text);
end $p4$;

-- ===================== 05. Desde Técnica (operador de planta) =====================
do $p5$
declare r jsonb;
begin
  r := pg_temp.dir('ztdir.planta@emdupar.gov.co', '991800000001', true);
  perform pg_temp.ok('05.01 el operador de planta con «Reportar anomalía» ve la dirección del contrato desde Técnica', pg_temp.err(r) = 'OK' and r -> 'comercial' ->> 'barrio' = 'CENTRO', r::text);
  r := pg_temp.dir('ztdir.planta2@emdupar.gov.co', '991800000001', true);
  perform pg_temp.ok('05.02 el operador de planta sin «Reportar anomalía», no (403)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.dir('ztdir.planta@emdupar.gov.co', '991800000001');
  perform pg_temp.ok('05.03 ni por la ruta de Comercial (no tiene campo)', pg_temp.err(r) = '42501', r::text);
end $p5$;

-- ===================== 06. Registrar con contrato: dirección en terreno y foto de las direcciones =====================
do $p6$
declare r jsonb; d jsonb; p jsonb; OP text := 'ztdir.op@emdupar.gov.co'; SUP text := 'ztdir.sup@emdupar.gov.co';
  T jsonb := '{"lat_registro": 10.46, "lon_registro": -73.25, "direccion": "[PRUEBA ZTDIR] CRA 9 # 12-32", "barrio": "CENTRO", "referencia": "Casa de rejas verdes"}';
begin
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', T, 10.46, -73.25, 5, '991800000001', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('06.01 un formato con contrato OBLIGATORIO ya acepta la dirección encontrada en terreno', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('nuevo', r ->> '_id');
  perform pg_temp.ok('06.02 y guarda la foto de las dos direcciones del contrato (la lee la base)',
    exists (select 1 from campo.reporte_direccion_contrato where reporte_id = (r ->> '_id')::uuid and contrato = '991800000001' and direccion_comercial = 'CRA 9 # 12-30 TORRE 2 APTO 301'
            and barrio_comercial = 'CENTRO' and direccion_catastro = 'CRA 9 12 30' and predios_catastro = 1));
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"lat_registro": 10.46, "lon_registro": -73.25, "direccion": "[PRUEBA ZTDIR] terreno"}', 10.46, -73.25, 5, '991800000009');
  perform pg_temp.ok('06.03 Reportar anomalía con un contrato inexistente: se registra y la foto queda vacía (0 predios)', pg_temp.err(r) = 'OK'
    and exists (select 1 from campo.reporte_direccion_contrato where reporte_id = (r ->> '_id')::uuid and direccion_comercial is null and direccion_catastro is null and predios_catastro = 0), r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"lat_registro": 10.46, "lon_registro": -73.25}');
  perform pg_temp.ok('06.04 sin contrato: no hay foto de direcciones', pg_temp.err(r) = 'OK' and not exists (select 1 from campo.reporte_direccion_contrato where reporte_id = (r ->> '_id')::uuid), r::text);
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', '{"direccion": "CRA 1"}', 10.46, -73.25, 5, null, 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('06.05 un formato de contrato obligatorio SIN contrato sigue rechazándose (lo exige el formato)', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', null, 10.46, -73.25, 5, '991800000002');
  perform pg_temp.ok('06.06 la Edge de antes (sin «registro») con contrato también guarda la foto de direcciones', pg_temp.err(r) = 'OK'
    and exists (select 1 from campo.reporte_direccion_contrato where reporte_id = (r ->> '_id')::uuid and direccion_comercial = 'CLL 5 # 3-10'), r::text);
  -- lecturas de Supervisión
  d := pg_temp.detalle(SUP, pg_temp.val('nuevo')::uuid);
  perform pg_temp.ok('06.07 el detalle trae la dirección del contrato junto a la encontrada en terreno',
    d -> 'reporte' -> 'direccion_contrato' ->> 'comercial' = 'CRA 9 # 12-30 TORRE 2 APTO 301' and d -> 'reporte' -> 'registro' ->> 'direccion' = '[PRUEBA ZTDIR] CRA 9 # 12-32', left((d -> 'reporte')::text, 500));
  d := pg_temp.lista(SUP, pg_temp.val('nuevo')::uuid);
  perform pg_temp.ok('06.08 la lista también', d ->> 'direccion_contrato' = 'CRA 9 # 12-30 TORRE 2 APTO 301' and d ->> 'direccion_catastro' = 'CRA 9 12 30' and d ->> 'direccion' = '[PRUEBA ZTDIR] CRA 9 # 12-32', d::text);
  r := pg_temp.rpc(format('public.geoportal_campo_descarga_iniciar(%L, %L::jsonb, ''xlsx'', false, null)', SUP, '{}'));
  d := pg_temp.rpc(format('public.geoportal_campo_descarga_pagina(%L, %s, null, 5000)', SUP, r ->> 'descarga_id'));
  select e into d from jsonb_array_elements(d -> 'registros') e where (e ->> 'id')::uuid = pg_temp.val('nuevo')::uuid;
  perform pg_temp.ok('06.09 la descarga también (las dos direcciones del contrato con su barrio)', d ->> 'direccion_contrato' = 'CRA 9 # 12-30 TORRE 2 APTO 301' and d ->> 'barrio_catastro' = 'CENTRO', d::text);
  p := pg_temp.pdf(SUP, pg_temp.val('nuevo')::uuid);
  perform pg_temp.ok('06.10 el PDF: «Dirección encontrada en terreno» y las dos del contrato (base comercial y catastro, por ser distintas)',
    pg_temp.cab(p, 'Dirección encontrada en terreno') = '[PRUEBA ZTDIR] CRA 9 # 12-32' and pg_temp.cab(p, 'Dirección del contrato (base comercial)') = 'CRA 9 # 12-30 TORRE 2 APTO 301 · CENTRO'
    and pg_temp.cab(p, 'Dirección del contrato (catastro)') = 'CRA 9 12 30 · CENTRO', (p -> 'cabecera')::text);
end $p6$;

-- ===================== 07. Sellos =====================
do $p7$
declare s1 text; s2 text; v uuid := pg_temp.val('nuevo')::uuid; ADM text := 'ztdir.admin@emdupar.gov.co';
begin
  perform pg_temp.ok('07.01 el sello y la cabecera del PDF de un reporte de antes son IGUALES después de migrar',
    pg_temp.pdf(ADM, pg_temp.val('viejo')::uuid) ->> 'sello' = pg_temp.val('sello_viejo') and (pg_temp.pdf(ADM, pg_temp.val('viejo')::uuid) -> 'cabecera')::text = pg_temp.val('cab_viejo'));
  s1 := pg_temp.pdf(ADM, v) ->> 'sello';
  alter table campo.reporte_direccion_contrato disable trigger t_solo_agregar;
  update campo.reporte_direccion_contrato set barrio_comercial = 'OTRO' where reporte_id = v;
  s2 := pg_temp.pdf(ADM, v) ->> 'sello';
  update campo.reporte_direccion_contrato set barrio_comercial = 'CENTRO' where reporte_id = v;
  alter table campo.reporte_direccion_contrato enable trigger t_solo_agregar;
  perform pg_temp.ok('07.02 el sello de un reporte nuevo cambia si cambia su foto de direcciones', s1 <> s2, s1 || ' / ' || s2);
  begin
    update campo.reporte_direccion_contrato set barrio_comercial = 'X' where reporte_id = v;
    perform pg_temp.ok('07.03 la foto de direcciones no se modifica (solo inserción)', false);
  exception when others then perform pg_temp.ok('07.03 la foto de direcciones no se modifica (solo inserción)', true);
  end;
end $p7$;

-- ===================== 08. Reglas de producción =====================
do $p8$
begin
  perform pg_temp.ok('08.01 ninguna función de campo con DELETE o UPDATE sin WHERE', {{SIN_WHERE_CAMPO}} = 0);
  perform pg_temp.ok('08.02 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
  perform pg_temp.ok('08.03 las 4 funciones de permisos vivas no cambiaron', {{PERMISOS_IGUALES}});
  perform pg_temp.ok('08.04 las RPC nuevas solo para service_role; las internas para nadie de la API',
    has_function_privilege('service_role', 'public.geoportal_campo_direccion_contrato(text,text,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_direccion_contrato(text,text,text)', 'execute')
    and has_function_privilege('service_role', 'public.geoportal_campo_tec_direccion_contrato(text,text,text)', 'execute') and not has_function_privilege('anon', 'public.geoportal_campo_tec_direccion_contrato(text,text,text)', 'execute')
    and not has_function_privilege('service_role', 'campo.f_direcciones_contrato(text)', 'execute') and not has_function_privilege('service_role', 'campo.f_texto_censo(text,boolean)', 'execute'));
end $p8$;

-- ===================== REVERSA =====================
{{CUERPO_REVERSA}}

-- ===================== 09. Después de la reversa =====================
do $p9$
declare r jsonb; ADM text := 'ztdir.admin@emdupar.gov.co';
begin
  perform pg_temp.ok('09.01 la huella de campo vuelve a la publicada', ({{HUELLA_CAMPO_Q}}) = '{{HUELLA_CAMPO}}');
  perform pg_temp.ok('09.02 el sello del reporte de antes es IGUAL tras la reversa', pg_temp.pdf(ADM, pg_temp.val('viejo')::uuid) ->> 'sello' = pg_temp.val('sello_viejo'));
  r := pg_temp.consultar('ztdir.ana@emdupar.gov.co', '991800000001');
  perform pg_temp.ok('09.03 «Consultar» vuelve a la respuesta de antes', not (r ? 'direcciones') and r -> 'comercial' ->> 'direccion' = 'CRA 9 12 30', left(r::text, 200));
  perform pg_temp.ok('09.04 nada se borró: las fotos de direcciones, la columna via y el parámetro siguen',
    exists (select 1 from campo.reporte_direccion_contrato where reporte_id = pg_temp.val('nuevo')::uuid) and exists (select 1 from campo.consultas_analisis where via = 'formato')
    and exists (select 1 from campo.parametros where clave = 'limite_direccion_hora'));
  perform pg_temp.ok('09.05 la ruta nueva ya no está', to_regprocedure('public.geoportal_campo_direccion_contrato(text,text,text)') is null);
end $p9$;

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztrf_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;
