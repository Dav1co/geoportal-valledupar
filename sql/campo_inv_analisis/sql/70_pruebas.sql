-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 70 — PRUEBAS (dentro del ensayo; todo se deshace al final con el ERROR esperado)
-- Datos propios con prefijo ZTINV (correos ztinv.*@emdupar.gov.co; textos «[PRUEBA ZTINV]»). Cada prueba cuenta SOLO sus filas.
-- Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- Sin tablas temporales que se borren al confirmar: la tabla de resultados se deshace con el ERROR esperado del final.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztinv_res (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztinv_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
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
create function pg_temp.prep(p_quien text, p_cant integer, p_tipo text, p_origen text default 'campo') returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_preparar_subida(%L, %s, %L, null, %L)', p_quien, p_cant, p_origen, p_tipo)) $f$;
-- Registra una Investigación (o el formato que se indique): reserva con preparar_subida, sube las fotos al doble de Storage y crea el reporte
create function pg_temp.inv(p_quien text, p_datos jsonb, p_etqs text[] default '{}', p_contrato text default '123456', p_tipo text default 'investigacion_ubicacion',
                            p_resultado text default null, p_causal text default null, p_lat numeric default 10.46) returns jsonb language plpgsql as $f$
declare p jsonb; v_id uuid; v_f jsonb := '[]'::jsonb; v_ruta text;
begin
  p := pg_temp.prep(p_quien, coalesce(cardinality(p_etqs), 0), p_tipo);
  if p ? 'error' then return p; end if;
  v_id := (p ->> 'reporte_id')::uuid;
  for i in 1 .. coalesce(cardinality(p_etqs), 0) loop
    v_ruta := p -> 'fotos' -> (i - 1) ->> 'ruta';
    insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', v_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg'));
    v_f := v_f || jsonb_build_object('orden', i, 'ruta', v_ruta, 'etiqueta', p_etqs[i]);
  end loop;
  return pg_temp.rpc(format('public.geoportal_campo_crear_reporte(%L, %L::uuid, %L, null, %L, %L, %s, -73.25, 5, false, ''campo'', %L::jsonb, null, %L::jsonb, %L, %L, null)',
                            p_quien, v_id, p_tipo, '[PRUEBA ZTINV] investigación', p_contrato, coalesce(p_lat::text, 'null'), v_f, p_datos, p_resultado, p_causal));
end $f$;
create function pg_temp.tipo_inv(r jsonb) returns jsonb language sql as $f$
  select t from jsonb_array_elements(r -> 'grupos') g, jsonb_array_elements(g -> 'tipos') t where t ->> 'codigo' = 'investigacion_ubicacion' $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo) values
  ('ztinv.op1@emdupar.gov.co', 'ZTINV Operario 1', 'consulta', true, 'sin_restriccion', 'todos', false, true, false),
  ('ztinv.op2@emdupar.gov.co', 'ZTINV Operario 2', 'consulta', true, 'sin_restriccion', 'todos', false, true, false),
  ('ztinv.op3@emdupar.gov.co', 'ZTINV Operario 3', 'consulta', true, 'sin_restriccion', 'todos', false, true, false),
  ('ztinv.sup@emdupar.gov.co', 'ZTINV Supervisor de campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, true);

do $p1$
declare r jsonb; t jsonb; n0 bigint; v_aud bigint; S text := 'ztinv.op1@emdupar.gov.co'; S2 text := 'ztinv.op2@emdupar.gov.co'; S3 text := 'ztinv.op3@emdupar.gov.co';
  D jsonb := '{"direccion_encontrada": "[PRUEBA ZTINV] CRA 9 # 12-30"}';
begin
  -- 01: el catálogo de la Investigación como lo decidió David
  perform pg_temp.ok('01.01 Investigación: sin resultado, fotos de 0 a 6, contrato obligatorio, activa, id 35',
    (select not genera_resultado and fotos_min = 0 and fotos_max = 6 and requiere_contrato = 'si' and activo and id = 35 from campo.tipos_reporte where codigo = 'investigacion_ubicacion'));
  perform pg_temp.ok('01.02 las 3 fotos quedan opcionales y sin marca de soporte (siguen activas)',
    (select count(*) = 3 and bool_and(not f.obligatoria and not f.soporte_inefectiva and f.activo) from campo.tipo_fotos f join campo.tipos_reporte t on t.id = f.tipo_id where t.codigo = 'investigacion_ubicacion'));
  perform pg_temp.ok('01.03 campos activos: solo la dirección es obligatoria; hallazgo, barrio, habitado, tipo de predio y medidor opcionales',
    (select string_agg(c.codigo || ':' || c.obligatorio, ',' order by c.orden) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id
      where t.codigo = 'investigacion_ubicacion' and c.activo) = 'hallazgo:false,direccion_encontrada:true,barrio:false,habitado:false,tipo_predio:false,medidor:false');
  perform pg_temp.ok('01.04 los 4 campos de despeje y visita y «observacion» están desactivados, no borrados',
    (select count(*) = 5 and bool_and(not c.activo) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id
      where t.codigo = 'investigacion_ubicacion' and c.codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada', 'cita_acordada', 'observacion')));
  perform pg_temp.ok('01.05 los campos nuevos tienen su tipo y su tope (barrio texto 80, habitado sí o no, tipo de predio 6 opciones, medidor texto 20)',
    (select string_agg(c.codigo || ':' || c.tipo_dato || ':' || coalesce(c.maximo::int::text, '-') || ':' || coalesce(jsonb_array_length(c.opciones)::text, '-'), ',' order by c.orden)
       from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id where t.codigo = 'investigacion_ubicacion' and c.codigo in ('barrio', 'habitado', 'tipo_predio', 'medidor'))
     = 'barrio:texto:80:-,habitado:si_no:-:-,tipo_predio:opcion:-:6,medidor:texto:20:-');
  perform pg_temp.ok('01.06 el cambio de catálogo quedó auditado (campo_catalogo, con antes y después)',
    exists (select 1 from public.geoportal_auditoria where accion = 'campo_catalogo' and referencia = 'tipo:investigacion_ubicacion' and detalle ->> 'paquete' = 'campo_inv_analisis'
             and detalle -> 'antes' -> 'tipo' ->> 'fotos_min' = '3' and detalle -> 'despues' -> 'tipo' ->> 'fotos_min' = '0'));
  perform pg_temp.ok('01.07 la Investigación sigue fuera del catálogo de documentos (sin PDF ni firmas)',
    not exists (select 1 from campo.formularios_documento where formulario = 'tipo:investigacion_ubicacion' and lleva_pdf));

  -- 02: lo que recibe la pantalla
  r := pg_temp.rpc(format('public.geoportal_campo_obtener_formulario(%L)', S)); t := pg_temp.tipo_inv(r);
  perform pg_temp.ok('02.01 obtener_formulario entrega la Investigación con fotos_min 0, sin resultado y sin causales',
    pg_temp.err(r) = 'OK' and (t ->> 'fotos_min')::int = 0 and (t ->> 'fotos_max')::int = 6 and t -> 'genera_resultado' = 'false'::jsonb and t -> 'causales' = '[]'::jsonb, left(coalesce(t::text, r::text), 300));
  perform pg_temp.ok('02.02 y con los 6 campos activos (los 5 desactivados no viajan: una sola caja de texto)',
    jsonb_array_length(t -> 'campos') = 6 and not exists (select 1 from jsonb_array_elements(t -> 'campos') c where c ->> 'codigo' in ('despeje_caja', 'cita_acordada', 'observacion')), left(coalesce(t::text, ''), 300));

  -- 03: preparar_subida
  r := pg_temp.prep(S, 0, 'investigacion_ubicacion');
  perform pg_temp.ok('03.01 con la Investigación, preparar 0 fotos desde campo se acepta y reserva el identificador',
    pg_temp.err(r) = 'OK' and r ? 'reporte_id' and r -> 'fotos' = '[]'::jsonb and exists (select 1 from campo.preparaciones where reporte_id = (r ->> 'reporte_id')::uuid), r::text);
  r := pg_temp.prep(S, 0, null);
  perform pg_temp.ok('03.02 sin tipo, 0 fotos desde campo se sigue rechazando (entre 1 y …)', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like 'La cantidad de fotos debe estar entre 1 y %', r::text);
  r := pg_temp.prep(S, 0, 'suspension');
  perform pg_temp.ok('03.03 con otro formato de mínimo 3 (suspensión), 0 fotos se sigue rechazando', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like '%entre 1 y%', r::text);
  r := pg_temp.prep(S, 0, 'fraude');
  perform pg_temp.ok('03.04 con un reporte general (sin mínimo propio), 0 fotos se sigue rechazando', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like '%entre 1 y%', r::text);
  r := pg_temp.prep(S, 7, 'investigacion_ubicacion');
  perform pg_temp.ok('03.05 con la Investigación, más de 6 fotos se rechaza (entre 0 y 6)', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'La cantidad de fotos debe estar entre 0 y 6', r::text);
  r := pg_temp.prep(S, -1, 'investigacion_ubicacion');
  perform pg_temp.ok('03.06 una cantidad negativa se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.prep('ztinv.sup@emdupar.gov.co', 0, null, 'escritorio');
  perform pg_temp.ok('03.07 desde el escritorio el supervisor sigue pudiendo preparar 0 fotos (como hoy)', pg_temp.err(r) = 'OK', r::text);
  r := pg_temp.prep(S, 2, 'investigacion_ubicacion');
  perform pg_temp.ok('03.08 con la Investigación, preparar 2 fotos sigue funcionando', pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'fotos') = 2, r::text);

  -- 04: registrar una Investigación
  r := pg_temp.inv(S, D);
  perform pg_temp.ok('04.01 se registra SIN fotos y SIN los campos opcionales (contrato, dirección y XY)', pg_temp.err(r) = 'OK' and r ->> 'consecutivo' like '%INV%', r::text);
  perform pg_temp.ok('04.02 queda sin resultado ni causal y sin fotos',
    (select resultado is null and causal_id is null from campo.reportes where id = (r ->> 'id')::uuid) and not exists (select 1 from campo.reporte_fotos where reporte_id = (r ->> 'id')::uuid), r::text);
  r := pg_temp.inv(S2, D || '{"hallazgo": "ubicado", "barrio": "[PRUEBA ZTINV] Centro", "habitado": true, "tipo_predio": "lote_desocupado", "medidor": "ZT-12345"}',
                   array['fachada_nomenclatura', 'vecino_referencia']);
  perform pg_temp.ok('04.03 se registra con todos los opcionales y 2 fotos', pg_temp.err(r) = 'OK'
    and (select datos ->> 'tipo_predio' = 'lote_desocupado' and datos -> 'habitado' = 'true'::jsonb and datos ->> 'barrio' = '[PRUEBA ZTINV] Centro' from campo.reportes where id = (r ->> 'id')::uuid), r::text);
  r := pg_temp.inv(S3, '{"hallazgo": "ubicado"}');
  perform pg_temp.ok('04.04 sin la dirección encontrada se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) ilike '%dirección encontrada%', r::text);
  r := pg_temp.inv(S3, D, '{}', null);
  perform pg_temp.ok('04.05 sin contrato se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Este formato necesita el número de contrato', r::text);
  r := pg_temp.inv(S3, D, '{}', '123456', 'investigacion_ubicacion', null, null, null);
  perform pg_temp.ok('04.06 sin coordenada se rechaza (el XY sigue obligatorio)', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) ilike '%coordenada%', r::text);
  r := pg_temp.inv(S3, D, '{}', '123456', 'investigacion_ubicacion', 'efectivo');
  perform pg_temp.ok('04.07 con resultado (efectivo) se rechaza: ya no lleva resultado', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Este tipo de reporte no lleva resultado ni causal', r::text);
  r := pg_temp.inv(S3, D, '{}', '123456', 'investigacion_ubicacion', 'inefectivo', 'no_ubicado');
  perform pg_temp.ok('04.08 con resultado inefectivo y causal se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Este tipo de reporte no lleva resultado ni causal', r::text);
  r := pg_temp.inv(S3, D || '{"observacion": "[PRUEBA ZTINV] reja verde"}');
  perform pg_temp.ok('04.09b el campo «observacion» desactivado se rechaza (la observación va en la descripción general)', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D || '{"despeje_caja": true}');
  perform pg_temp.ok('04.09 un campo desactivado (despeje_caja) se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D || '{"tipo_predio": "bodega"}');
  perform pg_temp.ok('04.10 un tipo de predio fuera de la lista se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D || '{"habitado": "si"}');
  perform pg_temp.ok('04.11 «habitado» que no es sí o no (booleano) se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D || jsonb_build_object('barrio', repeat('B', 81)));
  perform pg_temp.ok('04.12 un barrio de más de 80 caracteres se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D || jsonb_build_object('medidor', repeat('9', 21)));
  perform pg_temp.ok('04.13 un medidor de más de 20 caracteres se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D, array['fachada_nomenclatura', 'fachada_nomenclatura']);
  perform pg_temp.ok('04.14 dos fotos con la misma etiqueta se siguen rechazando', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like 'Hay dos fotos con la misma etiqueta%', r::text);

  -- 05: los demás formularios no cambian
  perform pg_temp.ok('05.01 los demás formatos de cartera conservan su resultado y su mínimo de fotos',
    (select bool_and(genera_resultado) and min(fotos_min) >= 1 from campo.tipos_reporte where codigo in ('suspension', 'corte', 'levantamiento_acometida', 'verificacion_posterior', 'reinstalacion')));
  perform pg_temp.ok('05.02 las fotos y los campos de los demás formatos no cambiaron (ningún cambio fuera de la Investigación)',
    not exists (select 1 from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id where t.codigo <> 'investigacion_ubicacion' and c.codigo in ('barrio', 'habitado', 'tipo_predio', 'medidor') and c.creado_en > now() - interval '1 hour'));
  r := pg_temp.rpc(format('public.geoportal_campo_obtener_formulario(%L)', S));
  select x into t from jsonb_array_elements(r -> 'grupos') g, jsonb_array_elements(g -> 'tipos') x where x ->> 'codigo' = 'suspension';
  perform pg_temp.ok('05.03 la pantalla sigue recibiendo la suspensión con mínimo 3 fotos, con resultado y con causales',
    (t ->> 'fotos_min')::int = 3 and t -> 'genera_resultado' = 'true'::jsonb and jsonb_array_length(t -> 'causales') > 0, left(coalesce(t::text, r::text), 300));

  -- 06: lo que no se toca
  perform pg_temp.ok('06.01 la huella del acta no cambió ({{HUELLA_ACTA}})', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '{{HUELLA_ACTA}}');
  perform pg_temp.ok('06.02 crear_reporte no cambió', md5(pg_get_functiondef(to_regprocedure('{{F_CREAR}}'))) = '{{MD5_CREAR}}');
  perform pg_temp.ok('06.03 las 4 funciones de permisos vivas no cambiaron', {{PERMISOS_IGUALES}});
  perform pg_temp.ok('06.04 preparar_subida sigue solo para service_role',
    has_function_privilege('service_role', 'public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'execute'));
  perform pg_temp.ok('06.05 ninguna función de campo con DELETE o UPDATE sin WHERE', {{SIN_WHERE_CAMPO}} = 0);
  perform pg_temp.ok('06.06 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
end $p1$;

-- ===================== PARTE 2: avisos del Análisis de contrato =====================
create function pg_temp.obs(p_quien text, p_contrato text, p_tipo text, p_texto text default null, p_dir text default null, p_contacto jsonb default null) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_analisis_observar(%L, %L, %L, %L, %L, %L::jsonb)', p_quien, p_contrato, p_tipo, p_texto, p_dir, p_contacto)) $f$;
create function pg_temp.lista(p_quien text, p_filtros jsonb) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_derivadas(%L, %L::jsonb)', p_quien, p_filtros)) $f$;
create function pg_temp.fila(r jsonb, p_id bigint) returns jsonb language sql as $f$
  select x from jsonb_array_elements(r -> 'filas') x where (x ->> 'id')::bigint = p_id $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta, ver_analisis_contrato) values
  ('ztinv.ana@emdupar.gov.co', 'ZTINV Analista', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false, true),
  ('ztinv.ana2@emdupar.gov.co', 'ZTINV Analista 2', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false, true),
  ('ztinv.supacta@emdupar.gov.co', 'ZTINV Supervisor de actas', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, true, false),
  ('ztinv.adm@emdupar.gov.co', 'ZTINV Administrador', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false, false);
-- La bitácora del Análisis: los contratos que consultó cada analista (datos de prueba)
insert into campo.consultas_analisis (autor, contrato, existe, consultado_en) values
  ('ztinv.ana@emdupar.gov.co', '990001', true, clock_timestamp()), ('ztinv.ana@emdupar.gov.co', '990002', true, clock_timestamp()),
  ('ztinv.ana@emdupar.gov.co', '990003', true, clock_timestamp()), ('ztinv.ana@emdupar.gov.co', '990004', false, clock_timestamp()),
  ('ztinv.ana@emdupar.gov.co', '990005', true, clock_timestamp() - interval '13 hours'), ('ztinv.ana@emdupar.gov.co', '99999999', true, clock_timestamp()),
  ('ztinv.ana2@emdupar.gov.co', '990001', true, clock_timestamp());

do $p2$
declare r jsonb; jx jsonb; A text := 'ztinv.ana@emdupar.gov.co'; A2 text := 'ztinv.ana2@emdupar.gov.co'; SUP text := 'ztinv.sup@emdupar.gov.co'; SA text := 'ztinv.supacta@emdupar.gov.co';
  ADM text := 'ztinv.adm@emdupar.gov.co'; OP text := 'ztinv.op1@emdupar.gov.co'; t0 timestamptz;
  d_des bigint; d_dir bigint; d_act bigint; d_otra bigint; d_nueva bigint; n0 bigint; n1 bigint; v_inv jsonb;
  C jsonb := '{"nombre": "ZTINV Persona Prueba", "cedula": "1065123456", "telefono": "300 123 4567", "correo": "ZTINV.Persona@Ejemplo.com", "relacion": "arrendatario"}';
begin
  -- 10: estructura y permisos
  perform pg_temp.ok('10.01 las 3 tablas nuevas existen con RLS activa y sin políticas (campo y acta siguen sin políticas)',
    (select count(*) = 3 and bool_and(relrowsecurity) from pg_class where oid in ('campo.analisis_observaciones'::regclass, 'campo.analisis_observacion_datos'::regclass, 'campo.analisis_observacion_anulaciones'::regclass))
    and not exists (select 1 from pg_policies where schemaname in ('campo', 'acta')));
  perform pg_temp.ok('10.02 sin permisos para anon, authenticated ni service_role; SELECT (y nada más) para homelab_lectura',
    (select bool_and(not has_table_privilege(rl, t, 'select') and not has_table_privilege(rl, t, 'insert'))
       from unnest(array['anon', 'authenticated', 'service_role']) rl, unnest(array['campo.analisis_observaciones', 'campo.analisis_observacion_datos', 'campo.analisis_observacion_anulaciones']) t)
    and (select bool_and(has_table_privilege('homelab_lectura', t, 'select') and not has_table_privilege('homelab_lectura', t, 'insert') and not has_table_privilege('homelab_lectura', t, 'update'))
       from unnest(array['campo.analisis_observaciones', 'campo.analisis_observacion_datos', 'campo.analisis_observacion_anulaciones']) t));
  perform pg_temp.ok('10.03 la tabla de datos de contacto está marcada SENSIBLE en su comentario',
    obj_description('campo.analisis_observacion_datos'::regclass, 'pg_class') like 'SENSIBLE (Ley 1581)%');
  perform pg_temp.ok('10.04 campo.derivadas: origen_id nulo solo con observación (exactamente uno de los dos)', exists (select 1 from pg_constraint where conname = 'derivadas_origen_ck'));

  -- 11: quién puede marcar y sobre qué contrato
  r := pg_temp.obs(OP, '990001', 'desocupado');
  perform pg_temp.ok('11.01 un operario sin Análisis de contrato no marca (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.obs(SA, '990001', 'desocupado');
  perform pg_temp.ok('11.02 el supervisor de actas sin Análisis no marca (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.obs(A, '990009', 'desocupado');
  perform pg_temp.ok('11.03 un contrato que el analista no consultó se rechaza', pg_temp.err(r) = '55000' and pg_temp.msg(r) like 'Primero consulte el contrato%', r::text);
  r := pg_temp.obs(A, '990005', 'desocupado');
  perform pg_temp.ok('11.04 un contrato consultado hace 13 horas se rechaza (12 h)', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.obs(A, '990004', 'desocupado');
  perform pg_temp.ok('11.05 un contrato que no existe (la consulta dio «no encontrado») se rechaza', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.obs(A, '99999999', 'desocupado');
  perform pg_temp.ok('11.06 el contrato comodín se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'El contrato comodín no admite observaciones', r::text);
  r := pg_temp.obs(A2, '990002', 'desocupado');
  perform pg_temp.ok('11.07 otro analista no marca un contrato que consultó el primero', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.obs(A, '99 0001', 'desocupado');
  perform pg_temp.ok('11.08 un contrato con algo distinto de números se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.obs(A, '990001', 'vendido');
  perform pg_temp.ok('11.09 una observación fuera de la lista se rechaza', pg_temp.err(r) <> 'OK', r::text);

  -- 12: los textos y los datos van solo donde corresponden
  r := pg_temp.obs(A, '990001', 'otra');
  perform pg_temp.ok('12.01 «Otra» sin texto se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like 'Escriba la observación%', r::text);
  r := pg_temp.obs(A, '990001', 'otra', 'ab');
  perform pg_temp.ok('12.02 «Otra» con menos de 3 caracteres se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.obs(A, '990001', 'otra', repeat('x', 121));
  perform pg_temp.ok('12.03 «Otra» con más de 120 caracteres se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.obs(A, '990001', 'otra', 'llamar al 300 123 4567');
  perform pg_temp.ok('12.04 «Otra» con un teléfono se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like '%no puede llevar teléfonos ni cédulas%', r::text);
  r := pg_temp.obs(A, '990001', 'otra', 'cédula 1065123456 del dueño');
  perform pg_temp.ok('12.05 «Otra» con una cédula (6 o más números seguidos) se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like '%no puede llevar teléfonos ni cédulas%', r::text);
  r := pg_temp.obs(A, '990001', 'desocupado', 'texto de más');
  perform pg_temp.ok('12.06 un texto en «Desocupado» se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'El texto corto solo va en «Otra»', r::text);
  r := pg_temp.obs(A, '990001', 'desocupado', null, 'CRA 9 # 12-30');
  perform pg_temp.ok('12.07 una dirección en «Desocupado» se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'La dirección correcta solo va en «Dirección errada»', r::text);
  r := pg_temp.obs(A, '990001', 'otra', '[PRUEBA ZTINV] reja', null, '{"nombre": "Ana"}');
  perform pg_temp.ok('12.08 datos de contacto en «Otra» se rechazan', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Los datos de contacto solo van en «Actualización de datos»', r::text);
  r := pg_temp.obs(A, '990001', 'direccion_errada', null, 'CRA 9 tel 3001234567');
  perform pg_temp.ok('12.09 una dirección correcta con un teléfono se rechaza', pg_temp.err(r) <> 'OK', r::text);

  -- 13: formato de los datos de contacto (Q3)
  perform pg_temp.ok('13.01 cédula: letras, 4 números u 11 números se rechazan', pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"cedula": "12a45"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"cedula": "1234"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"cedula": "12345678901"}')) <> 'OK');
  perform pg_temp.ok('13.02 teléfono: 6 u 8 números, o 10 que no empiezan por 3 ni 60, se rechazan', pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"telefono": "123456"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"telefono": "12345678"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"telefono": "2123456789"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"telefono": "6123456789"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"telefono": "300123456a"}')) <> 'OK');
  perform pg_temp.ok('13.03 correo sin @ o sin dominio se rechaza', pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"correo": "ana.ejemplo.com"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"correo": "ana@ejemplo"}')) <> 'OK');
  perform pg_temp.ok('13.04 relación fuera de la lista, nombre con números y una casilla desconocida se rechazan',
    pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"relacion": "vecino"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"nombre": "Ana 2"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"direccion": "CRA 1"}')) <> 'OK');
  perform pg_temp.ok('13.05 ningún intento rechazado dejó filas', not exists (select 1 from campo.analisis_observaciones where autor = A));
  perform pg_temp.ok('13.06 los formatos válidos: fijo de 7, celular de 10 con 3, fijo de 10 con 60, cédula de 5 y de 10, nombre con tildes',
    campo.f_contacto('{"telefono": "5701234"}') ->> 'telefono' = '5701234' and campo.f_contacto('{"telefono": "(300) 123-4567"}') ->> 'telefono' = '3001234567'
    and campo.f_contacto('{"telefono": "6055701234"}') ->> 'telefono' = '6055701234' and campo.f_contacto('{"cedula": "12345"}') ->> 'cedula' = '12345'
    and campo.f_contacto('{"cedula": "1065123456"}') ->> 'cedula' = '1065123456' and campo.f_contacto('{"nombre": "  María  José Núñez "}') ->> 'nombre' = 'María José Núñez'
    and campo.f_contacto('{"correo": " Ana.P@Ejemplo.COM.co "}') ->> 'correo' = 'ana.p@ejemplo.com.co' and campo.f_contacto('{"nombre": "", "cedula": ""}') is null);

  -- 14: marcar las 4 observaciones
  r := pg_temp.obs(A, '990001', 'desocupado'); d_des := (r ->> 'derivada_id')::bigint;
  perform pg_temp.ok('14.01 «Desocupado» crea su aviso pendiente', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'false'::jsonb
    and exists (select 1 from campo.derivadas where id = d_des and actividad = 'aviso_desocupado' and origen_id is null and contrato = '990001') and campo.f_derivada_estado(d_des) = 'pendiente', r::text);
  r := pg_temp.obs(A, '990001', 'direccion_errada', null, '[PRUEBA ZTINV] CRA 9 # 12-30 Barrio Centro'); d_dir := (r ->> 'derivada_id')::bigint;
  perform pg_temp.ok('14.02 «Dirección errada» con la dirección correcta crea su aviso', pg_temp.err(r) = 'OK'
    and (select o.direccion_correcta = '[PRUEBA ZTINV] CRA 9 # 12-30 Barrio Centro' from campo.derivadas d join campo.analisis_observaciones o on o.id = d.observacion_id where d.id = d_dir), r::text);
  r := pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, C); d_act := (r ->> 'derivada_id')::bigint;
  perform pg_temp.ok('14.03 «Actualización de datos» con los 5 datos crea su aviso y guarda los datos aparte, normalizados', pg_temp.err(r) = 'OK' and r -> 'trae_datos' = 'true'::jsonb
    and (select x.datos = '{"nombre": "ZTINV Persona Prueba", "cedula": "1065123456", "telefono": "3001234567", "correo": "ztinv.persona@ejemplo.com", "relacion": "arrendatario"}'::jsonb
           from campo.derivadas d join campo.analisis_observacion_datos x on x.observacion_id = d.observacion_id where d.id = d_act), r::text);
  perform pg_temp.ok('14.04 la respuesta al analista NO devuelve los datos de contacto', r::text !~* 'ztinv persona|1065123456|3001234567|ztinv\.persona' and not (r ? 'datos'), r::text);
  r := pg_temp.obs(A, '990001', 'otra', '[PRUEBA ZTINV] tiene perro bravo'); d_otra := (r ->> 'derivada_id')::bigint;
  perform pg_temp.ok('14.05 «Otra» con texto corto crea su aviso', pg_temp.err(r) = 'OK' and d_otra is not null, r::text);
  select count(*) into n0 from campo.analisis_observaciones where autor = A;
  r := pg_temp.obs(A, '990001', 'desocupado');
  perform pg_temp.ok('14.06 repetir «Desocupado» dentro de la vigencia: «ya se avisó» con la fecha y el estado, el mismo aviso, ninguna observación nueva', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'true'::jsonb
    and (r ->> 'derivada_id')::bigint = d_des and (select count(*) from campo.analisis_observaciones where autor = A) = n0
    and r ->> 'estado' = 'pendiente' and (r ->> 'ya_avisado_en') is not null and (r ->> 'vistos')::int = 1 and (r ->> 'vigencia_dias')::int = 20, r::text);
  r := pg_temp.obs(A, '990002', 'actualizacion_datos');
  perform pg_temp.ok('14.07 «Actualización de datos» sin ninguna casilla guarda solo el aviso (sin fila de datos)', pg_temp.err(r) = 'OK' and r -> 'trae_datos' = 'false'::jsonb
    and not exists (select 1 from campo.analisis_observacion_datos x join campo.derivadas d on d.observacion_id = x.observacion_id where d.id = (r ->> 'derivada_id')::bigint), r::text);
  perform pg_temp.ok('14.08 la auditoría de las marcas no guarda el contrato, los textos ni los datos de contacto',
    (select count(*) = 5 and bool_and(detalle::text !~* '990001|ztinv persona|1065123456|3001234567|perro|cra 9') from public.geoportal_auditoria where accion = 'campo_analisis_observar' and email = A));
  t0 := clock_timestamp(); r := pg_temp.obs(A, '990003', 'desocupado');
  perform pg_temp.ok('14.09 marcar tarda menos de 1 s', pg_temp.err(r) = 'OK' and clock_timestamp() - t0 < interval '1 s', (clock_timestamp() - t0)::text);

  -- 15: «Actividades derivadas» con el filtro de origen
  r := pg_temp.lista(SUP, '{"origen": "analisis", "contrato": "990001"}');
  perform pg_temp.ok('15.01 el supervisor de campo ve los 4 avisos del contrato con el filtro Origen = Análisis de contrato',
    pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'filas') = 4 and (select bool_and(x -> 'origen' ->> 'clase' = 'analisis' and x -> 'origen' ->> 'tipo_nombre' = 'Análisis de contrato') from jsonb_array_elements(r -> 'filas') x), left(r::text, 400));
  jx := pg_temp.fila(r, d_act);
  perform pg_temp.ok('15.02 el aviso de actualización dice «trae datos», pero la lista NO trae los datos de contacto',
    jx -> 'origen' -> 'trae_datos' = 'true'::jsonb and r::text !~* 'ztinv persona|1065123456|3001234567|ztinv\.persona|arrendatario', left(coalesce(jx::text, r::text), 400));
  perform pg_temp.ok('15.03 el aviso trae la dirección correcta y el texto de «Otra», el operario y la fecha',
    pg_temp.fila(r, d_dir) -> 'origen' ->> 'direccion_correcta' = '[PRUEBA ZTINV] CRA 9 # 12-30 Barrio Centro' and pg_temp.fila(r, d_otra) -> 'origen' ->> 'texto' = '[PRUEBA ZTINV] tiene perro bravo'
    and pg_temp.fila(r, d_des) -> 'origen' ->> 'operario' = A and pg_temp.fila(r, d_des) -> 'destinos' = '[]'::jsonb);
  r := pg_temp.lista(SUP, '{"origen": "registro", "contrato": "990001"}');
  perform pg_temp.ok('15.04 con Origen = Revisiones no aparecen los avisos', pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'filas') = 0, left(r::text, 300));
  r := pg_temp.lista(SUP, '{"origen": "mapa"}');
  perform pg_temp.ok('15.05 un origen fuera de la lista se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'El origen no es válido', r::text);
  r := pg_temp.lista(SA, '{"origen": "analisis", "contrato": "990001"}');
  perform pg_temp.ok('15.06 el supervisor de actas ve la lista (como hoy), también sin los datos', pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'filas') = 4 and r::text !~* '1065123456|3001234567', left(r::text, 200));
  r := pg_temp.lista(A, '{"origen": "analisis"}');
  perform pg_temp.ok('15.07 el analista no ve «Actividades derivadas» (42501)', pg_temp.err(r) = '42501', r::text);
  t0 := clock_timestamp(); r := pg_temp.lista(SUP, '{"origen": "analisis", "limite": 200}');
  perform pg_temp.ok('15.08 la lista tarda menos de 2 s', pg_temp.err(r) = 'OK' and clock_timestamp() - t0 < interval '2 s', (clock_timestamp() - t0)::text);

  -- 16: ver los datos de contacto (solo supervisor de campo y administrador, auditado)
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', A, d_act));
  perform pg_temp.ok('16.01 el analista que los guardó NO los vuelve a leer (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', SA, d_act));
  perform pg_temp.ok('16.02 el supervisor de actas no los lee (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', OP, d_act));
  perform pg_temp.ok('16.03 un operario no los lee (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', SUP, d_act));
  perform pg_temp.ok('16.04 el supervisor de campo los lee al abrir el aviso', pg_temp.err(r) = 'OK' and r -> 'anulados' = 'false'::jsonb and r -> 'datos' ->> 'cedula' = '1065123456' and r -> 'datos' ->> 'telefono' = '3001234567', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', ADM, d_act));
  perform pg_temp.ok('16.05 el administrador también', pg_temp.err(r) = 'OK' and r -> 'datos' ->> 'nombre' = 'ZTINV Persona Prueba', r::text);
  perform pg_temp.ok('16.06 cada lectura queda auditada, con los nombres de las casillas y sin los valores',
    (select count(*) = 2 and bool_and(detalle -> 'campos' = '["cedula", "correo", "nombre", "relacion", "telefono"]'::jsonb and detalle::text !~* '1065123456|3001234567|ztinv persona')
       from public.geoportal_auditoria where accion = 'campo_ver_datos_contacto' and referencia = d_act::text));
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', SUP, d_des));
  perform pg_temp.ok('16.07 un aviso sin datos de contacto lo dice', pg_temp.err(r) = 'P0002', r::text);

  -- 17: anular los datos de contacto (Q2)
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos_anular(%L, %s, %L)', A, d_act, 'el nombre estaba mal escrito'));
  perform pg_temp.ok('17.01 el analista no anula (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos_anular(%L, %s, %L)', SUP, d_act, 'mal'));
  perform pg_temp.ok('17.02 sin un motivo de 10 caracteres o más se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos_anular(%L, %s, %L)', SUP, d_act, '[PRUEBA ZTINV] la cédula no corresponde'));
  perform pg_temp.ok('17.03 el supervisor anula con motivo', pg_temp.err(r) = 'OK' and r -> 'anulados' = 'true'::jsonb, r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', SUP, d_act));
  perform pg_temp.ok('17.04 anulados: se ve «Anulados» y el motivo, sin los valores', pg_temp.err(r) = 'OK' and r -> 'anulados' = 'true'::jsonb
    and r ->> 'motivo' = '[PRUEBA ZTINV] la cédula no corresponde' and not (r ? 'datos') and r::text !~* '1065123456|3001234567', r::text);
  perform pg_temp.ok('17.05 los datos siguen guardados (nada se borra)', exists (select 1 from campo.analisis_observacion_datos x join campo.derivadas d on d.observacion_id = x.observacion_id where d.id = d_act and x.datos ->> 'cedula' = '1065123456'));
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos_anular(%L, %s, %L)', SUP, d_act, '[PRUEBA ZTINV] otra vez la anulo'));
  perform pg_temp.ok('17.06 anular dos veces se rechaza', pg_temp.err(r) = '55000', r::text);
  perform pg_temp.ok('17.07 la lista marca «datos anulados»', (pg_temp.fila(pg_temp.lista(SUP, '{"origen": "analisis", "contrato": "990001"}'), d_act) -> 'origen' -> 'datos_anulados') = 'true'::jsonb);

  -- 18: «Crear actividad» desde el aviso (Q1)
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', A, d_dir, 'tipo:investigacion_ubicacion'));
  perform pg_temp.ok('18.01 el analista no crea actividades (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SA, d_dir, 'tipo:investigacion_ubicacion'));
  perform pg_temp.ok('18.02 el supervisor de actas tampoco (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_dir, 'acta'));
  perform pg_temp.ok('18.03 el acta no se elige', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Elija un formulario activo que pida el contrato', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_dir, 'tipo:cambio_medidor'));
  perform pg_temp.ok('18.04 un formulario desactivado (cambio de medidor) no se elige', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_dir, 'tipo:fraude'));
  perform pg_temp.ok('18.05 un reporte general (contrato opcional) no se elige', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_dir, 'tipo:investigacion_ubicacion'));
  d_nueva := (r -> 'actividad' ->> 'id')::bigint;
  perform pg_temp.ok('18.06 el supervisor crea la Investigación de ubicación desde «Dirección errada»', pg_temp.err(r) = 'OK'
    and r -> 'actividad' ->> 'estado' = 'pendiente' and r -> 'actividad' -> 'destinos' = '["tipo:investigacion_ubicacion"]'::jsonb
    and r -> 'actividad' ->> 'destino_nombre' = 'Investigación de ubicación del predio' and r -> 'actividad' -> 'origen' ->> 'direccion_correcta' = '[PRUEBA ZTINV] CRA 9 # 12-30 Barrio Centro', left(r::text, 500));
  perform pg_temp.ok('18.07 el aviso se cerró solo: atendida fuera, con el motivo automático', r -> 'aviso' ->> 'estado' = 'atendida_fuera'
    and r -> 'aviso' -> 'cierre' ->> 'motivo' = 'Se creó la actividad: Investigación de ubicación del predio' and (r -> 'aviso' -> 'origen' ->> 'actividad_creada_id')::bigint = d_nueva, left(r::text, 500));
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_dir, 'tipo:suspension'));
  perform pg_temp.ok('18.08 una segunda actividad desde el mismo aviso se rechaza (ya está cerrado)', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_nueva, 'tipo:suspension'));
  perform pg_temp.ok('18.09 desde la actividad creada no se crea otra (no es un aviso)', pg_temp.err(r) <> 'OK', r::text);
  perform pg_temp.ok('18.10 quedó auditado', exists (select 1 from public.geoportal_auditoria where accion = 'campo_aviso_crear_actividad' and referencia = d_dir::text and email = SUP));

  -- 19: el operario la atiende con «¿Viene de…?»
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_abiertas(%L, %L, %L)', OP, '990001', 'tipo:investigacion_ubicacion'));
  perform pg_temp.ok('19.01 al operario que abre la Investigación con ese contrato le aparece la actividad (y no los avisos)',
    pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'derivadas') = 1 and (r -> 'derivadas' -> 0 ->> 'id')::bigint = d_nueva, left(r::text, 300));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_abiertas(%L, %L, %L)', OP, '990001', 'tipo:suspension'));
  perform pg_temp.ok('19.02 con otro formulario no aparece', pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'derivadas') = 0, r::text);
  v_inv := pg_temp.inv(OP, '{"direccion_encontrada": "[PRUEBA ZTINV] CRA 9 # 12-30"}', '{}', '990001');
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%L, %s, ''campo'', %L::uuid)', OP, d_des, v_inv ->> 'id'));
  perform pg_temp.ok('19.03 un aviso (sin destino) no se atiende con un registro', pg_temp.err(v_inv) = 'OK' and pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Ese formulario no atiende esa actividad derivada', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%L, %s, ''campo'', %L::uuid)', OP, d_nueva, v_inv ->> 'id'));
  perform pg_temp.ok('19.04 la Investigación registrada atiende la actividad: queda «atendida» con su consecutivo', pg_temp.err(r) = 'OK' and r ->> 'estado' = 'atendida'
    and r -> 'cierre' ->> 'consecutivo' = v_inv ->> 'consecutivo', left(r::text, 400));
  v_inv := pg_temp.inv(OP, '{"direccion_encontrada": "[PRUEBA ZTINV] otra"}', '{}', '990002');
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, (select id from campo.derivadas where contrato = '990002' and actividad = 'aviso_actualizacion_datos'), 'tipo:investigacion_ubicacion'));
  jx := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%L, %s, ''campo'', %L::uuid)', OP, (r -> 'actividad' ->> 'id')::bigint, (pg_temp.inv(OP, '{"direccion_encontrada": "[PRUEBA ZTINV] tercera"}', '{}', '990001')) ->> 'id'));
  perform pg_temp.ok('19.05 un registro de otro contrato no atiende la actividad', pg_temp.err(r) = 'OK' and pg_temp.err(jx) <> 'OK' and pg_temp.msg(jx) = 'El registro es de otro contrato', jx::text);

  -- 20: cerrar avisos como hoy
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_cerrar(%L, %s, ''atendida_fuera'', %L)', SUP, d_des, '[PRUEBA ZTINV] se confirmó por teléfono'));
  perform pg_temp.ok('20.01 «Desocupado» se cierra como atendida fuera con motivo', pg_temp.err(r) = 'OK' and r ->> 'estado' = 'atendida_fuera', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_cerrar(%L, %s, ''anulada'', %L)', SUP, d_otra, '[PRUEBA ZTINV] marcada por error'));
  perform pg_temp.ok('20.02 «Otra» se anula con motivo', pg_temp.err(r) = 'OK' and r ->> 'estado' = 'anulada', r::text);
  r := pg_temp.obs(A, '990001', 'desocupado');
  perform pg_temp.ok('20.03 con el aviso CERRADO y dentro de la vigencia, «Desocupado» no crea otro: «ya se avisó» (cerrado) y queda visto otra vez', pg_temp.err(r) = 'OK'
    and r -> 'repetida' = 'true'::jsonb and (r ->> 'derivada_id')::bigint = d_des and r ->> 'estado' = 'atendida_fuera' and (r ->> 'vistos')::int = 2, r::text);

  -- 21: las derivadas de las revisiones no cambian
  begin
    insert into campo.derivadas (origen_id, contrato, actividad) values ((v_inv ->> 'id')::uuid, '990002', 'otra') returning id into n1;
  exception when others then
    perform pg_temp.ok('21.00 se puede crear una derivada de prueba desde un registro', false, sqlerrm || ' · ' || coalesce(v_inv::text, ''));
  end;
  jx := campo.f_derivada_json(n1);
  perform pg_temp.ok('21.01 una derivada de un registro conserva sus claves de siempre (más «clase»: registro)',
    jx -> 'origen' ->> 'clase' = 'registro' and jx -> 'origen' ?& array['registro_id', 'tipo', 'tipo_nombre', 'consecutivo', 'fecha', 'operario'] and jx -> 'destinos' = '[]'::jsonb
    and jx ?& array['id', 'actividad', 'actividad_nombre', 'contrato', 'estado', 'creada_en', 'destinos', 'destino_omision', 'origen', 'cierre'], jx::text);
  perform pg_temp.ok('21.02 y aparece con el filtro Origen = Revisiones', pg_temp.fila(pg_temp.lista(SUP, '{"origen": "registro", "contrato": "990002"}'), n1) is not null);
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%L, %s, ''campo'', %L::uuid)', OP, n1, v_inv ->> 'id'));
  perform pg_temp.ok('21.03 la regla de siempre: un registro no atiende sus propias derivadas', pg_temp.err(r) <> 'OK', r::text);
  begin
    insert into campo.derivadas (contrato, actividad) values ('990002', 'otra');
    perform pg_temp.ok('21.04 una derivada sin origen ni observación se rechaza', false);
  exception when check_violation then perform pg_temp.ok('21.04 una derivada sin origen ni observación se rechaza', true);
  end;
  begin
    insert into campo.derivadas (origen_id, observacion_id, contrato, actividad) values ((v_inv ->> 'id')::uuid, (select observacion_id from campo.derivadas where id = d_des), '990002', 'aviso_otra');
    perform pg_temp.ok('21.05 una derivada con origen Y observación se rechaza', false);
  exception when check_violation then perform pg_temp.ok('21.05 una derivada con origen Y observación se rechaza', true);
  end;
  begin
    insert into campo.derivadas (origen_id, contrato, actividad, destino) values ((v_inv ->> 'id')::uuid, '990002', 'accesorios', 'tipo:suspension');
    perform pg_temp.ok('21.06 un destino propio en una derivada de revisión se rechaza', false);
  exception when check_violation then perform pg_temp.ok('21.06 un destino propio en una derivada de revisión se rechaza', true);
  end;
  perform pg_temp.ok('21.07 los 5 códigos nuevos no se cuelan en «¿Da lugar a otras actividades?» de las revisiones',
    not exists (select 1 from campo.tipo_campos c, jsonb_array_elements(coalesce(c.opciones, '[]')) o where o ->> 'codigo' in ('aviso_desocupado', 'aviso_direccion_errada', 'aviso_actualizacion_datos', 'aviso_otra', 'actividad_supervisor')));

  -- 22: solo inserción y nada se borra
  begin
    update campo.analisis_observaciones set texto = 'x' where autor = A;
    perform pg_temp.ok('22.01 las observaciones no se modifican', false);
  exception when others then perform pg_temp.ok('22.01 las observaciones no se modifican', true);
  end;
  begin
    delete from campo.analisis_observacion_datos where true;
    perform pg_temp.ok('22.02 los datos de contacto no se borran', false);
  exception when others then perform pg_temp.ok('22.02 los datos de contacto no se borran', true);
  end;
  perform pg_temp.ok('22.03 ninguna función nueva lleva DELETE ni UPDATE', (select bool_and(pg_get_functiondef(p.oid) !~* '\m(delete|update)\M\s') from pg_proc p
     where p.oid in ('campo.f_contacto(jsonb)'::regprocedure, 'campo.f_texto_sin_datos(text,text,integer,integer)'::regprocedure,
                     'public.geoportal_campo_analisis_observar(text,text,text,text,text,jsonb,text)'::regprocedure, 'public.geoportal_campo_aviso_crear_actividad(text,bigint,text,text)'::regprocedure,
                     'public.geoportal_campo_aviso_datos(text,bigint,text)'::regprocedure, 'public.geoportal_campo_aviso_datos_anular(text,bigint,text,text)'::regprocedure)));
  perform pg_temp.ok('22.04 solo aviso_datos devuelve los datos de contacto: ninguna otra función de campo, exportación o mapa lee esa tabla',
    (select array_agg(p.proname::text order by p.proname) from pg_proc p where pg_get_functiondef(p.oid) ~ 'analisis_observacion_datos' and p.prokind = 'f')
     = array['f_derivada_json', 'geoportal_campo_analisis_observar', 'geoportal_campo_aviso_datos', 'geoportal_campo_aviso_datos_anular']::text[]);
  perform pg_temp.ok('22.05 ninguna función de campo con DELETE o UPDATE sin WHERE (con la parte 2)', {{SIN_WHERE_CAMPO}} = 0);
end $p2$;

-- ===================== SECCIÓN 7: vigencia de los avisos (20 días por omisión) =====================
-- El paso del tiempo se simula con avisos de prueba fechados hacia atrás (contrato 990003, que el analista consultó).
create function pg_temp.aviso_viejo(p_tipo text, p_dias integer, p_contrato text default '990003') returns bigint language plpgsql as $f$
declare v_obs uuid; v_der bigint;
begin
  insert into campo.analisis_observaciones (contrato, tipo, texto, autor, creado_en)
  values (p_contrato, p_tipo, case when p_tipo = 'otra' then '[PRUEBA ZTINV] viejo' end, 'ztinv.ana2@emdupar.gov.co', clock_timestamp() - make_interval(days => p_dias)) returning id into v_obs;
  insert into campo.derivadas (observacion_id, contrato, actividad, creado_en) values (v_obs, p_contrato, 'aviso_' || p_tipo, clock_timestamp() - make_interval(days => p_dias)) returning id into v_der;
  return v_der;
end $f$;

insert into campo.consultas_analisis (autor, contrato, existe, consultado_en) values ('ztinv.ana@emdupar.gov.co', '990006', true, clock_timestamp()), ('ztinv.ana@emdupar.gov.co', '990007', true, clock_timestamp());

do $p3$
declare r jsonb; A text := 'ztinv.ana@emdupar.gov.co'; SUP text := 'ztinv.sup@emdupar.gov.co'; d19 bigint; d21 bigint; d5 bigint; dp4 bigint; dd bigint; n0 bigint; jx jsonb; dnew bigint;
begin
  perform pg_temp.ok('23.01 el parámetro vigencia_avisos_dias existe: 20 días (de 1 a 365)',
    exists (select 1 from campo.parametros where clave = 'vigencia_avisos_dias' and valor = 20 and unidad = 'días' and minimo = 1 and maximo = 365));
  -- «Desocupado»: VIGENCIA (sección 7)
  dd := pg_temp.aviso_viejo('desocupado', 19, '990006');
  r := pg_temp.obs(A, '990006', 'desocupado');
  perform pg_temp.ok('23.02 «Desocupado» con un aviso de hace 19 días: «ya se avisó» con esa fecha, el mismo aviso y visto otra vez', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'true'::jsonb
    and r ->> 'regla' = 'vigencia' and (r ->> 'derivada_id')::bigint = dd and (r ->> 'ya_avisado_en')::timestamptz < clock_timestamp() - interval '18 days' and (r ->> 'vistos')::int = 1, r::text);
  perform pg_temp.ok('23.03 el aviso de «Desocupado» muestra su antigüedad (19 días) y «visto otra vez» con quién',
    (campo.f_derivada_json(dd) ->> 'antiguedad_dias')::int = 19 and (campo.f_derivada_json(dd) -> 'origen' ->> 'vistos')::int = 1
    and campo.f_derivada_json(dd) -> 'origen' -> 'ultimo_visto' ->> 'autor' = A);
  dp4 := pg_temp.aviso_viejo('desocupado', 25, '990002');
  insert into campo.analisis_avisos_vistos (observacion_id, autor, visto_en) select observacion_id, 'ztinv.ana2@emdupar.gov.co', clock_timestamp() - interval '2 days' from campo.derivadas where id = dp4;
  r := pg_temp.obs(A, '990002', 'desocupado');
  perform pg_temp.ok('23.04 «Desocupado» de hace 25 días (visto otra vez hace 2): pasada la vigencia desde el ORIGINAL se crea uno nuevo; el viejo sigue pendiente',
    pg_temp.err(r) = 'OK' and r -> 'repetida' = 'false'::jsonb and (r ->> 'derivada_id')::bigint <> dp4 and campo.f_derivada_estado(dp4) = 'pendiente'
    and (campo.f_derivada_json(dp4) ->> 'antiguedad_dias')::int = 25, r::text);
  update campo.parametros set valor = 5 where clave = 'vigencia_avisos_dias';
  dd := pg_temp.aviso_viejo('desocupado', 10, '990007');
  r := pg_temp.obs(A, '990007', 'desocupado');
  perform pg_temp.ok('23.05 con vigencia_avisos_dias = 5, un «Desocupado» de hace 10 días ya no vale: aviso nuevo', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'false'::jsonb and (r ->> 'derivada_id')::bigint <> dd, r::text);
  update campo.parametros set valor = 20 where clave = 'vigencia_avisos_dias';

  -- «Dirección errada»: uno pendiente a la vez (sin días)
  d19 := pg_temp.aviso_viejo('direccion_errada', 40, '990006');
  r := pg_temp.obs(A, '990006', 'direccion_errada', null, '[PRUEBA ZTINV] CRA 1');
  perform pg_temp.ok('23.06 «Dirección errada» con un aviso PENDIENTE (aunque tenga 40 días): «ya hay un aviso pendiente», no se crea otro ni se guarda la dirección',
    pg_temp.err(r) = 'OK' and r -> 'repetida' = 'true'::jsonb and r ->> 'regla' = 'pendiente' and (r ->> 'derivada_id')::bigint = d19 and r -> 'datos_no_guardados' = 'true'::jsonb
    and not exists (select 1 from campo.analisis_observaciones where direccion_correcta = '[PRUEBA ZTINV] CRA 1') and not exists (select 1 from campo.analisis_avisos_vistos v join campo.derivadas d on d.observacion_id = v.observacion_id where d.id = d19), r::text);
  perform pg_temp.rpc(format('public.geoportal_campo_derivada_cerrar(%L, %s, ''atendida_fuera'', %L)', SUP, d19, '[PRUEBA ZTINV] se corrigió la dirección'));
  r := pg_temp.obs(A, '990006', 'direccion_errada', null, '[PRUEBA ZTINV] CRA 2');
  perform pg_temp.ok('23.07 cerrado el anterior, «Dirección errada» se puede avisar de nuevo enseguida (aviso nuevo con su dirección)', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'false'::jsonb
    and exists (select 1 from campo.analisis_observaciones where direccion_correcta = '[PRUEBA ZTINV] CRA 2'), r::text);

  -- «Otra»: uno pendiente a la vez con el mismo texto; un texto distinto crea su propio aviso
  d21 := pg_temp.aviso_viejo('otra', 30, '990006');
  r := pg_temp.obs(A, '990006', 'otra', '[PRUEBA ZTINV] VIEJO');
  perform pg_temp.ok('23.08 «Otra» con el MISMO texto que un aviso pendiente (aunque tenga 30 días, sin importar mayúsculas): ya hay un aviso pendiente',
    pg_temp.err(r) = 'OK' and r -> 'repetida' = 'true'::jsonb and r ->> 'regla' = 'pendiente' and (r ->> 'derivada_id')::bigint = d21, r::text);
  select count(*) into n0 from campo.derivadas where contrato = '990006' and actividad = 'aviso_otra';
  r := pg_temp.obs(A, '990006', 'otra', '[PRUEBA ZTINV] otro asunto');
  perform pg_temp.ok('23.09 «Otra» con un texto distinto crea su propio aviso (el otro sigue pendiente)', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'false'::jsonb
    and (select count(*) from campo.derivadas where contrato = '990006' and actividad = 'aviso_otra') = n0 + 1 and campo.f_derivada_estado(d21) = 'pendiente', r::text);

  -- «Actualización de datos»: uno pendiente a la vez; excepción: si el supervisor anuló los datos, el analista los vuelve a enviar en ESE aviso
  r := pg_temp.obs(A, '990007', 'actualizacion_datos', null, null, '{"cedula": "11111111", "telefono": "3001112233"}');
  d5 := (r ->> 'derivada_id')::bigint;
  r := pg_temp.obs(A, '990007', 'actualizacion_datos', null, null, '{"cedula": "22222222"}');
  perform pg_temp.ok('23.10 «Actualización de datos» con un aviso pendiente con datos VIGENTES: no se crea otro y los datos nuevos NO se guardan',
    pg_temp.err(r) = 'OK' and r -> 'repetida' = 'true'::jsonb and r ->> 'regla' = 'pendiente' and (r ->> 'derivada_id')::bigint = d5 and r -> 'datos_no_guardados' = 'true'::jsonb
    and not exists (select 1 from campo.analisis_observacion_datos where datos ->> 'cedula' = '22222222') and r::text !~ '22222222', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos_anular(%L, %s, %L)', SUP, d5, '[PRUEBA ZTINV] la cédula no corresponde'));
  r := pg_temp.obs(A, '990007', 'actualizacion_datos', null, null, '{"cedula": "33333333", "relacion": "familiar"}');
  perform pg_temp.ok('23.11 anulados por el supervisor: el analista vuelve a enviar los datos y se guardan en ESE MISMO aviso (entrega nueva)',
    pg_temp.err(r) = 'OK' and r -> 'repetida' = 'true'::jsonb and r -> 'datos_guardados' = 'true'::jsonb and (r ->> 'derivada_id')::bigint = d5
    and (select count(*) from campo.analisis_observacion_datos x join campo.derivadas d on d.observacion_id = x.observacion_id where d.id = d5) = 2 and r::text !~ '33333333', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', SUP, d5));
  perform pg_temp.ok('23.12 el supervisor ve la entrega nueva (vigente) y que hay 1 anulada', pg_temp.err(r) = 'OK' and r -> 'anulados' = 'false'::jsonb
    and r -> 'datos' ->> 'cedula' = '33333333' and (r ->> 'entregas')::int = 2 and (r ->> 'anuladas')::int = 1, r::text);
  r := pg_temp.obs(A, '990007', 'actualizacion_datos', null, null, '{"cedula": "44444444"}');
  perform pg_temp.ok('23.13 con la entrega nueva vigente, otra entrega más ya no se guarda', pg_temp.err(r) = 'OK' and r -> 'datos_no_guardados' = 'true'::jsonb
    and not exists (select 1 from campo.analisis_observacion_datos where datos ->> 'cedula' = '44444444'), r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos_anular(%L, %s, %L)', SUP, d5, '[PRUEBA ZTINV] también estaba mal'));
  jx := campo.f_derivada_json(d5);
  perform pg_temp.ok('23.14 anulada también la segunda: la lista dice «datos anulados», con 2 entregas, y aviso_datos muestra solo el motivo',
    pg_temp.err(r) = 'OK' and jx -> 'origen' -> 'datos_anulados' = 'true'::jsonb and (jx -> 'origen' ->> 'entregas_datos')::int = 2
    and (pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', SUP, d5)) ->> 'motivo') = '[PRUEBA ZTINV] también estaba mal', left(jx::text, 300));
  d19 := pg_temp.aviso_viejo('actualizacion_datos', 3, '990006');
  r := pg_temp.obs(A, '990006', 'actualizacion_datos', null, null, '{"cedula": "55555555"}');
  perform pg_temp.ok('23.15 un aviso pendiente SIN datos (nunca tuvo): no es la excepción; los datos nuevos no se guardan', pg_temp.err(r) = 'OK' and r -> 'datos_no_guardados' = 'true'::jsonb
    and (r ->> 'derivada_id')::bigint = d19 and not exists (select 1 from campo.analisis_observacion_datos where datos ->> 'cedula' = '55555555'), r::text);
  perform pg_temp.rpc(format('public.geoportal_campo_derivada_cerrar(%L, %s, ''anulada'', %L)', SUP, d5, '[PRUEBA ZTINV] se cierra para probar'));
  r := pg_temp.obs(A, '990007', 'actualizacion_datos', null, null, '{"cedula": "66666666"}');
  perform pg_temp.ok('23.16 cerrado el aviso, «Actualización de datos» crea uno nuevo con sus datos', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'false'::jsonb and (r ->> 'derivada_id')::bigint <> d5
    and exists (select 1 from campo.analisis_observacion_datos where datos ->> 'cedula' = '66666666'), r::text);

  perform pg_temp.ok('23.17 la auditoría de «visto otra vez», «ya pendiente» y «reenviados» no lleva el contrato ni los datos',
    (select count(*) >= 5 and bool_and(detalle::text !~ '99000[67]|1111|2222|3333') from public.geoportal_auditoria
      where accion in ('campo_analisis_visto_otra_vez', 'campo_analisis_ya_pendiente', 'campo_analisis_datos_reenviados') and email = A));
  begin
    update campo.analisis_avisos_vistos set autor = 'x@y' where observacion_id is not null;
    perform pg_temp.ok('23.18 «visto otra vez» no se modifica (solo inserción)', false);
  exception when others then perform pg_temp.ok('23.18 «visto otra vez» no se modifica (solo inserción)', true);
  end;
  perform pg_temp.ok('23.19 ninguna función de campo con DELETE o UPDATE sin WHERE (con la vigencia)', {{SIN_WHERE_CAMPO}} = 0);
end $p3$;

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztinv_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;
