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
  perform pg_temp.ok('01.03 campos activos: solo la dirección es obligatoria; hallazgo, barrio, habitado, tipo de predio, medidor y observación opcionales',
    (select string_agg(c.codigo || ':' || c.obligatorio, ',' order by c.orden) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id
      where t.codigo = 'investigacion_ubicacion' and c.activo) = 'hallazgo:false,direccion_encontrada:true,barrio:false,habitado:false,tipo_predio:false,medidor:false,observacion:false');
  perform pg_temp.ok('01.04 los 4 campos de despeje y visita están desactivados, no borrados',
    (select count(*) = 4 and bool_and(not c.activo) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id
      where t.codigo = 'investigacion_ubicacion' and c.codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada', 'cita_acordada')));
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
  perform pg_temp.ok('02.02 y con los 7 campos activos (los 4 desactivados no viajan)',
    jsonb_array_length(t -> 'campos') = 7 and not exists (select 1 from jsonb_array_elements(t -> 'campos') c where c ->> 'codigo' in ('despeje_caja', 'cita_acordada')), left(coalesce(t::text, ''), 300));

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
  r := pg_temp.inv(S2, D || '{"hallazgo": "ubicado", "barrio": "[PRUEBA ZTINV] Centro", "habitado": true, "tipo_predio": "lote_desocupado", "medidor": "ZT-12345", "observacion": "[PRUEBA ZTINV] reja verde"}',
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

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztinv_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;
