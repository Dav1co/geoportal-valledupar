-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de la migración, en la misma transacción.
-- Arma sus personas (prueba.tec9.*), su químico de prueba («ZT9 …») y sus archivos en Storage. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · CORTE 7c … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- reserva una foto como la persona indicada y la «sube» (deja el objeto en Storage con ese tipo y tamaño)
create function pg_temp.foto(p_quien text, p_mime text default 'image/jpeg', p_bytes bigint default 400000) returns text language plpgsql as $$
declare v text := public.geoportal_tec_quimico_remision_preparar(p_quien) ->> 'ruta';
begin
  insert into storage.objects (bucket_id, name, metadata) values ('tecnica-evidencias', v, jsonb_build_object('size', p_bytes, 'mimetype', p_mime));
  return v;
end $$;

do $prueba$
declare
  a text := 'prueba.tec9.adm@emdupar.gov.co'; sv text := 'prueba.tec9.planta@emdupar.gov.co'; op text := 'prueba.tec9.op@emdupar.gov.co'; op2 text := 'prueba.tec9.op2@emdupar.gov.co';
  v_r jsonb; v_x jsonb; v_cod text; v_ruta text; v_f1 text; v_f2 text; v_n0 integer; v_redes text; v_desvio numeric;
  v_total integer; v_bien integer; v_fallas text;
begin
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v_redes from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  select count(*) into v_n0 from tecnica.quimico_movimientos;
  select valor into v_desvio from tecnica.quimico_parametros where clave = 'desvio_pct';
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT9 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT9 Operador', 'consulta', true, 'sin_restriccion', 'todos'), (op2, 'ZT9 Operador sin químicos', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'entrada_quimicos', a), (op, 'asignar_formulario', 'uso_quimicos', a);
  -- un químico de prueba (auxiliar: no pide dosis), con su ficha en PDF
  v_ruta := public.geoportal_tec_quimico_ficha_preparar(sv) ->> 'ruta';
  insert into storage.objects (bucket_id, name, metadata) values ('tecnica-evidencias', v_ruta, '{"size": 300000, "mimetype": "application/pdf"}'::jsonb);
  v_cod := public.geoportal_tec_quimico_crear(sv, 'ZT9 Químico de prueba', 'auxiliar', false, null, v_ruta, 'ZT9 químico para las pruebas del 7c') ->> 'codigo';

  -- ===================== 01. Estructura =====================
  perform pg_temp.reg('01.01 los movimientos que ya existían no cambian: misma cantidad y ninguno con foto',
     (select count(*) from tecnica.quimico_movimientos) = v_n0 and not exists (select 1 from tecnica.quimico_movimientos where remision_foto is not null));
  perform pg_temp.reg('01.02 el parámetro del tamaño de la foto existe y los 4 que se editan siguen con su valor', (select valor from tecnica.quimico_parametros where clave = 'max_bytes_remision') = 3145728
     and (select valor from tecnica.quimico_parametros where clave = 'desvio_pct') = v_desvio);

  -- ===================== 02. Foto de la remisión =====================
  v_r := public.geoportal_tec_quimico_remision_preparar(op);
  perform pg_temp.reg('02.01 el operador con «Entrada de químicos» reserva la foto: una ruta remisiones/AAAA-MM/<uuid>.jpg, JPEG y su tamaño máximo',
     v_r ->> 'ruta' ~ '^remisiones/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.jpg$' and v_r ->> 'tipo_mime' = 'image/jpeg' and (v_r ->> 'max_bytes')::bigint = 3145728, v_r::text);
  perform pg_temp.err('02.02 un operador sin ese formulario no reserva fotos', format($$select public.geoportal_tec_quimico_remision_preparar(%L)$$, op2), '42501');
  perform pg_temp.err('02.03 una entrada con una foto que no terminó de subir se rechaza', format($$select public.geoportal_tec_quimico_entrada(%L, %L, null)$$, op,
     jsonb_build_object('quimico', v_cod, 'cantidad', 1, 'unidad', 't', 'foto', v_r ->> 'ruta')), '22023', 'no terminó de subir');
  v_f1 := pg_temp.foto(op);
  v_x := public.geoportal_tec_quimico_entrada(op, jsonb_build_object('quimico', v_cod, 'cantidad', 2, 'unidad', 't', 'remision', 'R-9001', 'foto', v_f1), 'zt9-entrada-0001');
  perform pg_temp.reg('02.04 la entrada con su foto subida queda guardada con la ruta de la foto y la auditoría dice «con_foto» (sin la ruta)',
     (select remision_foto = v_f1 and cantidad_kg = 2000 from tecnica.quimico_movimientos where id = (v_x ->> 'movimiento_id')::bigint)
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_quimico_entrada' and email = op and (detalle ->> 'con_foto')::boolean and detalle::text not like '%remisiones/%'), v_x::text);
  perform pg_temp.reg('02.05 repetir el mismo envío (misma clave) no duplica', (public.geoportal_tec_quimico_entrada(op, jsonb_build_object('quimico', v_cod, 'cantidad', 2, 'unidad', 't', 'foto', v_f1), 'zt9-entrada-0001') ->> 'repetido')::boolean
     and (select count(*) from tecnica.quimico_movimientos where remision_foto = v_f1) = 1);
  perform pg_temp.err('02.06 la misma foto no sirve para otra entrada', format($$select public.geoportal_tec_quimico_entrada(%L, %L, null)$$, op,
     jsonb_build_object('quimico', v_cod, 'cantidad', 1, 'unidad', 'kg', 'foto', v_f1)), '22023', 'otra entrada');
  v_f2 := pg_temp.foto(sv);
  perform pg_temp.err('02.07 una foto reservada por otra persona no se acepta', format($$select public.geoportal_tec_quimico_entrada(%L, %L, null)$$, op,
     jsonb_build_object('quimico', v_cod, 'cantidad', 1, 'unidad', 'kg', 'foto', v_f2)), '22023', 'Tome de nuevo');
  perform pg_temp.err('02.08 un archivo que no es JPEG se rechaza', format($$select public.geoportal_tec_quimico_entrada(%L, %L, null)$$, op,
     jsonb_build_object('quimico', v_cod, 'cantidad', 1, 'unidad', 'kg', 'foto', pg_temp.foto(op, 'application/pdf'))), '22023', 'JPEG');
  perform pg_temp.err('02.09 una foto que pasa del tamaño se rechaza', format($$select public.geoportal_tec_quimico_entrada(%L, %L, null)$$, op,
     jsonb_build_object('quimico', v_cod, 'cantidad', 1, 'unidad', 'kg', 'foto', pg_temp.foto(op, 'image/jpeg', 4000000))), '22023', 'tamaño');
  v_x := public.geoportal_tec_quimico_entrada(op, jsonb_build_object('quimico', v_cod, 'cantidad', 50, 'unidad', 'kg'), null);
  perform pg_temp.reg('02.10 la foto es opcional: una entrada sin foto se guarda como antes', (select remision_foto is null from tecnica.quimico_movimientos where id = (v_x ->> 'movimiento_id')::bigint));
  perform pg_temp.err('02.11 la regla de la tabla: solo una entrada lleva foto de remisión', format($$insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, para_que, remision_foto, autor)
     select 'uso', id, 1, 'kg', -1, current_date, 'limpieza', %L, 'x@y.co' from tecnica.quimicos where codigo = %L$$, v_f2, v_cod), '23514');
  perform pg_temp.err('02.12 la foto de una entrada no se puede cambiar después (solo inserción)', format($$update tecnica.quimico_movimientos set remision_foto = null where remision_foto = %L$$, v_f1), '42501');
  v_r := public.geoportal_tec_quimico_historial(sv, v_cod);
  perform pg_temp.reg('02.13 el historial del supervisor trae la ruta de la foto en esa entrada (la Edge la cambia por una URL firmada) y nula en las demás',
     (select count(*) from jsonb_array_elements(v_r -> 'movimientos') m where m ->> 'remision_foto_ruta' = v_f1 and m ->> 'remision' = 'R-9001') = 1
     and (select count(*) from jsonb_array_elements(v_r -> 'movimientos') m where m ->> 'remision_foto_ruta' is not null) = 1);
  perform pg_temp.err('02.14 el operador no lee el historial (ni las fotos)', format($$select public.geoportal_tec_quimico_historial(%L, %L)$$, op, v_cod), '42501');

  -- ===================== 03. Parámetros editables =====================
  v_r := public.geoportal_tec_quimico_parametros(sv);
  perform pg_temp.reg('03.01 el supervisor de planta ve los 4 parámetros que se editan, con su rango y sin los tamaños de archivo',
     (select string_agg(p ->> 'clave', ',' order by n) from jsonb_array_elements(v_r -> 'parametros') with ordinality x(p, n)) = 'desvio_pct,marca_esperado_usado,dias_atras_uso,dias_atras_entrada'
     and (v_r -> 'parametros' -> 0 ->> 'minimo')::numeric = 1 and (v_r -> 'parametros' -> 0 ->> 'maximo')::numeric = 500 and v_r -> 'parametros' -> 0 -> 'ultimo' = 'null'::jsonb, v_r::text);
  perform pg_temp.err('03.02 el operador no ve los parámetros', format($$select public.geoportal_tec_quimico_parametros(%L)$$, op), '42501');
  v_x := public.geoportal_tec_quimico_parametro_fijar(sv, 'desvio_pct', 30, 'ZT9 el jefe de planta ajusta el desvío');
  perform pg_temp.reg('03.03 el supervisor cambia el desvío a 30 %: queda el valor, el evento con el antes, el después, el motivo y el autor, y la auditoría',
     (v_x ->> 'valor')::numeric = 30 and (v_x ->> 'antes')::numeric = v_desvio and tecnica.f_qparam('desvio_pct') = 30
     and (select antes = v_desvio and despues = 30 and autor = sv and motivo like 'ZT9%' from tecnica.quimico_parametro_eventos where clave = 'desvio_pct' order by id desc limit 1)
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_quimico_parametro' and email = sv and referencia = 'desvio_pct'), v_x::text);
  perform pg_temp.reg('03.04 el cambio rige de inmediato: el catálogo y «esperado contra usado» ya dicen 30 %',
     (public.geoportal_tec_quimicos_catalogo(sv) -> 'parametros' ->> 'desvio_pct')::numeric = 30 and (public.geoportal_tec_quimicos_comparacion(sv, null, null) ->> 'desvio_pct')::numeric = 30);
  perform pg_temp.reg('03.05 la lista muestra el último cambio', (public.geoportal_tec_quimico_parametros(a) -> 'parametros' -> 0 -> 'ultimo' ->> 'autor') = sv);
  perform pg_temp.err('03.06 fuera del rango', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'desvio_pct', 0, 'ZT9 fuera del rango permitido')$$, sv), '22023', 'entre');
  perform pg_temp.err('03.07 sin motivo suficiente', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'desvio_pct', 40, 'corto')$$, sv), '22023', 'motivo');
  perform pg_temp.err('03.08 el mismo valor no es un cambio', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'desvio_pct', 30, 'ZT9 mismo valor de antes')$$, sv), '22023', 'ya tiene');
  perform pg_temp.err('03.09 los días atrás son enteros', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'dias_atras_uso', 2.5, 'ZT9 con decimales no vale')$$, sv), '22023', 'entero');
  perform pg_temp.err('03.10 un tamaño de archivo no se cambia desde la pantalla', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'max_bytes_ficha', 200000, 'ZT9 no es editable aquí')$$, a), '22023', 'pantalla');
  perform pg_temp.err('03.11 el operador no cambia parámetros', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'desvio_pct', 50, 'ZT9 el operador no puede')$$, op), '42501');
  perform pg_temp.err('03.12 el historial de cambios no se edita', $$update tecnica.quimico_parametro_eventos set motivo = 'ZT9 cambiado a mano' where clave = 'desvio_pct'$$, '42501');
  v_x := public.geoportal_tec_quimico_parametro_fijar(a, 'dias_atras_entrada', 3, 'ZT9 el administrador acorta los días');
  perform pg_temp.reg('03.13 el administrador también; el formulario del operador ya dice 3 días atrás', (public.geoportal_tec_quimicos_formulario(op, 'entrada_quimicos') ->> 'dias_atras')::numeric = 3);

  -- ===================== 04. Lo que ve producción =====================
  perform pg_temp.reg('04.01 pg-safeupdate: ninguna función de redes, tecnica, geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
     not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion || ' → ' || sentencia, ' | ') from redes.f_funciones_sin_where()));
  perform pg_temp.reg('04.02 la huella de las funciones de redes no cambió', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = v_redes);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · CORTE 7c (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
