-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 70 · PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 26 y 40, en la misma transacción.
-- Arma sus personas (prueba.redes14a.*), sus fotos de prueba en storage.objects y sus puntos por levantar; termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 14 · ACTA … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.1300 + y * 0.0000090437, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.5800 + x * 0.0000091290, 6) $$;
create function pg_temp.punto(p_quien text, p_x numeric, p_y numeric, p_prec numeric, p_extra jsonb default '{}'::jsonb, p_fotos integer default 1) returns jsonb language plpgsql as $$
declare j jsonb; f jsonb;
begin
  j := public.geoportal_redes_levantar_preparar(p_quien, p_fotos);
  for f in select e from jsonb_array_elements(j -> 'fotos') e loop
    insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', f ->> 'ruta', jsonb_build_object('size', 200000, 'mimetype', 'image/jpeg'));
  end loop;
  return public.geoportal_redes_levantar_crear(p_quien, (j ->> 'punto_id')::uuid,
    jsonb_build_object('servicio', 'acueducto', 'tipo', 'valvula', 'lat', pg_temp.lat(p_y), 'lon', pg_temp.lon(p_x), 'precision_m', p_prec, 'fotos', j -> 'fotos') || p_extra, '127.0.0.1');
end $$;

do $prueba$
declare
  adm text := 'prueba.redes14a.adm@emdupar.gov.co'; sd text := 'prueba.redes14a.sd@emdupar.gov.co'; op text := 'prueba.redes14a.op@emdupar.gov.co'; op2 text := 'prueba.redes14a.op2@emdupar.gov.co';
  co text := 'prueba.redes14a.co@emdupar.gov.co'; na text := 'prueba.redes14a.nada@emdupar.gov.co';
  j jsonb; v_lev text; v_lev2 text; v_val text; v_t0 timestamptz; v_ms numeric; v_info text; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZT14A Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT14A Supervisora de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT14A Operador Uno', 'consulta', true, 'sin_restriccion', 'todos'), (op2, 'ZT14A Operador Dos', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values (co, 'ZT14A Operaria de Comercial', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_comercial, horario, dias) values (na, 'ZT14A Sin permiso', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'activo_campo', adm), (op2, 'asignar_formulario', 'activo_campo', adm);
  perform public.geoportal_redes_personal_fijar(sd, op, 'area', 'distribucion', 'ZT14A sale a campo con la cuadrilla'), public.geoportal_redes_personal_fijar(sd, op, 'cargo', 'Fontanero', 'ZT14A cargo de la persona');
  insert into campo.personal_eventos (persona, tipo_evento, cargo, autor) values (co, 'fijar_cargo', 'Revisora de campo', adm);

  j := pg_temp.punto(op, 3000, 3000, 45, jsonb_build_object('observacion', 'ZT14A válvula en el andén'), 2); v_lev := j ->> 'codigo';
  j := pg_temp.punto(co, 3200, 3000, 6, jsonb_build_object('tipo', 'pozo', 'servicio', 'alcantarillado')); v_lev2 := j ->> 'codigo';

  -- ===================== 01. Quién ve el acta =====================
  j := public.geoportal_redes_levantar_acta(op, lower(v_lev), '127.0.0.1');
  perform pg_temp.reg('01.01 quien reportó ve su propia acta: código, servicio, tipo, fecha, coordenadas, precisión («precisión baja»), observación y estado',
    j ->> 'codigo' = v_lev and j ->> 'servicio' = 'acueducto' and j ->> 'tipo_nombre' = 'Válvula' and j ->> 'registrado_en' is not null and (j ->> 'lat')::numeric = pg_temp.lat(3000)
    and (j ->> 'precision_m')::numeric = 45 and (j ->> 'precision_baja')::boolean and j ->> 'observacion' = 'ZT14A válvula en el andén' and j ->> 'estado_nombre' = 'Reportado', left(j::text, 400));
  perform pg_temp.reg('01.02 quién lo reportó: nombre del funcionario, área y cargo (los de Personal de distribución)',
    j -> 'reporto' = jsonb_build_object('nombre', 'ZT14A Operador Uno', 'area', 'Técnica · Distribución', 'cargo', 'Fontanero'), (j -> 'reporto')::text);
  perform pg_temp.reg('01.03 las fotos (2), con su ruta para que la Edge firme la lectura y la hora en que se guardaron',
    jsonb_array_length(j -> 'fotos') = 2 and j -> 'fotos' -> 0 ->> 'ruta' like 'levantar/%/1.jpg' and j -> 'fotos' -> 1 ->> 'creado_en' is not null);
  perform pg_temp.reg('01.04 el historial empieza con «Reportado» (quién y cuándo)', jsonb_array_length(j -> 'historial') = 1 and j -> 'historial' -> 0 ->> 'que' = 'Reportado' and j -> 'historial' -> 0 ->> 'quien' = 'ZT14A Operador Uno');
  perform pg_temp.err('01.05 otro operador (con el formulario) NO ve el acta de un punto que no reportó', format('select public.geoportal_redes_levantar_acta(%L, %L)', op2, v_lev), '42501');
  perform pg_temp.err('01.06 … ni Comercial la de un punto de Técnica', format('select public.geoportal_redes_levantar_acta(%L, %L)', co, v_lev), '42501');
  perform pg_temp.err('01.07 quien no entra a «Encontrar o reportar activo» no ve ninguna', format('select public.geoportal_redes_levantar_acta(%L, %L)', na, v_lev), '42501');
  j := public.geoportal_redes_levantar_acta(co, v_lev2);
  perform pg_temp.reg('01.08 Comercial ve la suya, con su área y su cargo de Personal de Comercial',
    j ->> 'codigo' = v_lev2 and j -> 'reporto' = jsonb_build_object('nombre', 'ZT14A Operaria de Comercial', 'area', 'Comercial', 'cargo', 'Revisora de campo') and not (j ->> 'precision_baja')::boolean, (j -> 'reporto')::text);
  perform pg_temp.reg('01.09 el supervisor de distribución y el administrador ven todas',
    public.geoportal_redes_levantar_acta(sd, v_lev) ->> 'codigo' = v_lev and public.geoportal_redes_levantar_acta(sd, v_lev2) ->> 'codigo' = v_lev2 and public.geoportal_redes_levantar_acta(adm, v_lev2) ->> 'codigo' = v_lev2);
  perform pg_temp.err('01.10 un código que no es de un activo por levantar se rechaza', format('select public.geoportal_redes_levantar_acta(%L, %L)', sd, 'DAN-000001'), '22023');
  perform pg_temp.err('01.11 … y uno que no existe: no encontrado', format('select public.geoportal_redes_levantar_acta(%L, %L)', sd, 'LEV-999999'), 'P0002');

  -- ===================== 02. Estado e historial =====================
  select m.codigo into v_val from redes.activo_vigente_mat m where not m.retirado order by m.activo_id limit 1;
  perform public.geoportal_redes_levantar_evento(sd, v_lev, 'asignado', null, 'ZT14A cuadrilla de topografía');
  perform public.geoportal_redes_levantar_evento(sd, v_lev, 'descartado', null, 'ZT14A era la misma válvula ya levantada');
  perform public.geoportal_redes_levantar_evento(adm, v_lev, 'reabierto', null, 'ZT14A no era la misma válvula');
  if v_val is not null then perform public.geoportal_redes_levantar_evento(sd, v_lev, 'levantado', v_val, null); end if;
  j := public.geoportal_redes_levantar_acta(op, v_lev);
  perform pg_temp.reg('02.01 el historial: quién asignó, descartó, reabrió y levantó, cuándo y con qué motivo, en orden',
    (select string_agg(h ->> 'tipo', ',' order by o) from jsonb_array_elements(j -> 'historial') with ordinality x(h, o)) = 'reportado,asignado,descartado,reabierto' || case when v_val is not null then ',levantado' else '' end
    and j -> 'historial' -> 1 ->> 'quien' = 'ZT14A Supervisora de distribución' and j -> 'historial' -> 2 ->> 'motivo' = 'ZT14A era la misma válvula ya levantada'
    and j -> 'historial' -> 3 ->> 'quien' = 'ZT14A Admin' and (select bool_and(h ->> 'cuando' is not null) from jsonb_array_elements(j -> 'historial') h), (j -> 'historial')::text);
  perform pg_temp.reg('02.02 el estado actual: «Levantado», con el activo nuevo', v_val is null or (j ->> 'estado_nombre' = 'Levantado' and j ->> 'activo' = v_val and j -> 'historial' -> 4 ->> 'activo' = v_val), (j - 'historial' - 'fotos')::text);
  perform pg_temp.reg('02.03 el acta no trae correos ni datos de suscriptores (solo nombres de funcionarios)',
    j::text !~ '@' and not exists (select 1 from jsonb_object_keys(j) k where k ~ 'contrato|suscriptor|telefono|direccion|autor|email'), j::text);
  perform pg_temp.reg('02.04 cada consulta del acta queda en la auditoría (dice si era la propia)',
    (select count(*) from public.geoportal_auditoria where accion = 'redes_levantar_acta' and referencia = v_lev and email = op and (detalle ->> 'propia')::boolean) = 2
    and exists (select 1 from public.geoportal_auditoria where accion = 'redes_levantar_acta' and referencia = v_lev and email = sd and not (detalle ->> 'propia')::boolean));

  -- ===================== 03. Tiempos =====================
  v_t0 := clock_timestamp(); perform public.geoportal_redes_levantar_acta(sd, v_lev); perform public.geoportal_redes_levantar_acta(co, v_lev2); v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS: dos actas (una con historial de %s eventos) %s ms', jsonb_array_length(j -> 'historial'), v_ms);
  perform pg_temp.reg('03.01 TIEMPOS: el acta, en menos de 1 s', v_ms < 1000, v_info);
  perform pg_temp.reg('03.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 14 · ACTA (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
