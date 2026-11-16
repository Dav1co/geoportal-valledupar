-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de la migración, en la misma transacción.
-- No supone conteos de la base: arma sus personas (prueba.tec8.*) y sus reportes (en un rincón de Valledupar, con el contrato de prueba 990000001301).
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · CORTE 8 … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.tipos(p jsonb) returns text language sql as $$
  select coalesce(string_agg(t ->> 'codigo', ',' order by t ->> 'codigo'), '') from jsonb_array_elements(p -> 'grupos') g, jsonb_array_elements(g -> 'tipos') t $$;

do $prueba$
declare
  a text := 'prueba.tec8.adm@emdupar.gov.co'; sv text := 'prueba.tec8.sup@emdupar.gov.co'; o1 text := 'prueba.tec8.op1@emdupar.gov.co'; o2 text := 'prueba.tec8.op2@emdupar.gov.co';
  o3 text := 'prueba.tec8.op3@emdupar.gov.co'; rc text := 'prueba.tec8.rep@emdupar.gov.co'; na text := 'prueba.tec8.nada@emdupar.gov.co';
  C1 text := '990000001301';
  v_r jsonb; v_x jsonb; v_id uuid; v_id2 uuid; v_id3 uuid; v_n0 integer; v_t0 integer; v_gen text; v_md5 text; v_fotos jsonb;
  v_total integer; v_bien integer; v_fallas text;
begin
  select count(*), md5(coalesce(string_agg(r.id::text || coalesce(r.descripcion, '') || coalesce(r.contrato, '') || r.registrado_en::text || coalesce(r.datos::text, ''), ',' order by r.seq), '')) into v_n0, v_md5 from campo.reportes r;
  select count(*) into v_t0 from campo.tipos_reporte where codigo not in ('fuga_acometida', 'caja_medidor_danada');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT8 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT8 Supervisor técnico', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values
    (o1, 'ZT8 Operador con anomalía', 'consulta', true, 'sin_restriccion', 'todos'), (o2, 'ZT8 Operador con revisión', 'consulta', true, 'sin_restriccion', 'todos'),
    (o3, 'ZT8 Operador sin compartidos', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values (rc, 'ZT8 Reportante de Comercial', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT8 Sin nada', 'consulta', 'sin_restriccion', 'todos');

  -- ===================== 01. Técnica: las dos claves nuevas =====================
  perform pg_temp.reg('01.01 tecnica.f_formularios lista 9 formularios: los 7 de antes, «Reportar anomalía» y «Revisiones generales»',
     (select count(*) from tecnica.f_formularios()) = 9 and (select string_agg(clave, ',' order by orden) from tecnica.f_formularios() where orden > 7) = 'anomalia_compartida,revision_compartida');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (o1, 'asignar_formulario', 'anomalia_compartida', a), (o2, 'asignar_formulario', 'revision_compartida', a),
    (o3, 'asignar_formulario', 'entrada', a);
  perform pg_temp.reg('01.02 las claves nuevas se asignan en Personal como cualquier formulario (el dominio las admite)',
     (select count(*) from tecnica.personal_tecnico_eventos where persona in (o1, o2) and formulario in ('anomalia_compartida', 'revision_compartida')) = 2);
  perform pg_temp.err('01.03 una clave inventada sigue sin entrar al dominio', format($$insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (%L, 'asignar_formulario', 'inventada', %L)$$, o1, a), '23514');
  v_r := public.geoportal_tec_mis_formularios(o1);
  perform pg_temp.reg('01.04 «mis formularios» del operador trae «Reportar anomalía» (sin campos propios: la pantalla es la de Comercial)',
     exists (select 1 from jsonb_array_elements(v_r -> 'formularios') f where f ->> 'clave' = 'anomalia_compartida' and f ->> 'nombre' = 'Reportar anomalía' and not (f ->> 'con_campos')::boolean)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'formularios') f where f ->> 'clave' = 'revision_compartida'), v_r::text);
  perform pg_temp.reg('01.05 quién tiene qué: operador 1 anomalía, operador 2 revisión, operador 3 ninguno, supervisor técnico y administrador los dos; Comercial y «nada», ninguno',
     campo.f_tecnica_claves(o1) = '{anomalia_compartida}' and campo.f_tecnica_claves(o2) = '{revision_compartida}' and campo.f_tecnica_claves(o3) = '{}'
     and cardinality(campo.f_tecnica_claves(sv)) = 2 and cardinality(campo.f_tecnica_claves(a)) = 2 and campo.f_tecnica_claves(rc) = '{}' and campo.f_tecnica_claves(na) = '{}');

  -- ===================== 02. El catálogo es el mismo =====================
  perform pg_temp.reg('02.01 los tipos que ya había siguen todos, sin cambios de cantidad; existen «Fuga en acometida» y «Caja de medidor dañada»',
     (select count(*) from campo.tipos_reporte where codigo not in ('fuga_acometida', 'caja_medidor_danada')) = v_t0
     and exists (select 1 from campo.tipos_reporte where lower(nombre) like '%fuga%acometida%') and exists (select 1 from campo.tipos_reporte where lower(nombre) like '%caja%medidor%da_ad%'));
  perform pg_temp.reg('02.02 los dos nuevos son del reporte general (sin campos ni consecutivo) y «Revisiones generales» no',
     (not exists (select 1 from campo.tipos_reporte where codigo = 'fuga_acometida') or campo.f_tipo_general('fuga_acometida'))
     and (not exists (select 1 from campo.tipos_reporte where codigo = 'caja_medidor_danada') or campo.f_tipo_general('caja_medidor_danada'))
     and not campo.f_tipo_general('revision_previa') and not campo.f_tipo_general('inventado'));
  select t.codigo into v_gen from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where t.activo and g.activo and campo.f_tipo_general(t.codigo) and not t.exige_subtipo and not t.exige_texto and t.requiere_contrato <> 'si' order by (t.codigo = 'fuga_acometida') desc, t.id limit 1;

  -- ===================== 03. El formulario, desde Técnica =====================
  v_r := public.geoportal_campo_tec_formulario(o1);
  perform pg_temp.reg('03.01 operador con «Reportar anomalía»: perfil de reportante, área «tecnica» y solo los tipos del reporte general (sin formatos de actividad ni revisiones)',
     v_r ->> 'perfil' = 'reportante' and v_r ->> 'area' = 'tecnica' and not (v_r -> 'puede' ->> 'supervisar')::boolean and v_r -> 'limites' ->> 'max_fotos' is not null
     and pg_temp.tipos(v_r) <> '' and not exists (select 1 from unnest(string_to_array(pg_temp.tipos(v_r), ',')) c where not campo.f_tipo_general(c)), pg_temp.tipos(v_r));
  perform pg_temp.reg('03.02 es el MISMO catálogo que ve el reportante de Comercial en «Reportar anomalía»',
     pg_temp.tipos(v_r) = (select string_agg(c, ',' order by c) from unnest(string_to_array(pg_temp.tipos(public.geoportal_campo_obtener_formulario(rc, false)), ',')) c where campo.f_tipo_general(c)));
  v_x := public.geoportal_campo_tec_formulario(o2);
  perform pg_temp.reg('03.03 operador con «Revisiones generales»: solo ese formato, con sus campos', pg_temp.tipos(v_x) = 'revision_previa'
     and (select jsonb_array_length(t -> 'campos') > 5 from jsonb_array_elements(v_x -> 'grupos') g, jsonb_array_elements(g -> 'tipos') t), pg_temp.tipos(v_x));
  v_x := public.geoportal_campo_tec_formulario(a);
  perform pg_temp.reg('03.04 el administrador, entrando por Técnica, recibe la vista de reportante (sin estados, parámetros ni definiciones de supervisión) con los dos formularios',
     v_x ->> 'perfil' = 'reportante' and v_x -> 'parametros' = 'null'::jsonb and v_x -> 'estados' = 'null'::jsonb and position('revision_previa' in pg_temp.tipos(v_x)) > 0 and position(v_gen in pg_temp.tipos(v_x)) > 0);
  perform pg_temp.err('03.05 un operador de Técnica sin formularios compartidos no entra', format($$select public.geoportal_campo_tec_formulario(%L)$$, o3), '42501');
  perform pg_temp.err('03.06 un reportante de Comercial sin Técnica tampoco entra por esta puerta', format($$select public.geoportal_campo_tec_formulario(%L)$$, rc), '42501');
  perform pg_temp.err('03.07 quien no tiene nada, tampoco', format($$select public.geoportal_campo_tec_formulario(%L)$$, na), '42501');
  perform pg_temp.err('03.08 el operador de Técnica sigue SIN entrar al formulario de Comercial por la puerta de Comercial', format($$select public.geoportal_campo_obtener_formulario(%L, false)$$, o1), '42501');

  -- ===================== 04. Crear desde Técnica: misma tabla, con el área =====================
  insert into public.predios_comercial (id, cod_usuario) select 990000001301, C1 where not exists (select 1 from public.predios_comercial where cod_usuario = C1);
  v_r := public.geoportal_campo_tec_preparar_subida(o1, 1, '10.0.0.8', null);
  v_id := (v_r ->> 'reporte_id')::uuid;
  perform pg_temp.reg('04.01 preparar la subida desde Técnica: mismas rutas del bucket de campo (campo-fotos)', v_r ->> 'bucket' = 'campo-fotos' and jsonb_array_length(v_r -> 'fotos') = 1 and v_id is not null, v_r::text);
  insert into storage.objects (bucket_id, name, metadata) select 'campo-fotos', f ->> 'ruta', '{"size": 200000, "mimetype": "image/jpeg"}'::jsonb from jsonb_array_elements(v_r -> 'fotos') f;
  v_fotos := (select jsonb_agg(jsonb_build_object('orden', (f ->> 'orden')::integer, 'ruta', f ->> 'ruta', 'tomada_en', clock_timestamp())) from jsonb_array_elements(v_r -> 'fotos') f);
  v_x := public.geoportal_campo_tec_crear_reporte(o1, v_id, v_gen, null, 'ZT8 fuga en la acometida, frente al predio', C1, 10.4400, -73.2600, 8, false, v_fotos, '10.0.0.8');
  perform pg_temp.reg('04.02 el operador de Técnica crea el reporte: queda en campo.reportes (la misma tabla), con el área «tecnica», su autor y origen «campo»',
     (v_x ->> 'id')::uuid = v_id and v_x ->> 'area' = 'tecnica'
     and (select area || '|' || autor || '|' || origen || '|' || contrato from campo.reportes where id = v_id) = 'tecnica|' || o1 || '|campo|' || C1, v_x::text);
  perform pg_temp.reg('04.03 con sus fotos, su evento inicial y su auditoría, como cualquier reporte de campo',
     (select count(*) from campo.reporte_fotos where reporte_id = v_id) = 1 and (select estado from campo.v_reportes_estado where id = v_id) = 'reportado'
     and exists (select 1 from public.geoportal_auditoria where accion = 'campo_crear_reporte' and email = o1));
  perform pg_temp.err('04.04 el reporte no se puede cambiar después (solo inserción): tampoco su área', format($$update campo.reportes set area = null where id = %L$$, v_id), '42501');
  perform pg_temp.err('04.05 el operador con solo «Reportar anomalía» no crea una revisión general', format($$select public.geoportal_campo_tec_crear_reporte(%L, gen_random_uuid(), 'revision_previa', null, null, %L, 10.44, -73.26, 8, false, '[]'::jsonb)$$, o1, C1), '42501');
  perform pg_temp.err('04.06 el operador con solo «Revisiones generales» no crea un reporte de anomalía', format($$select public.geoportal_campo_tec_crear_reporte(%L, gen_random_uuid(), %L, null, 'x', null, 10.44, -73.26, 8, false, '[]'::jsonb)$$, o2, v_gen), '42501');
  perform pg_temp.err('04.07 desde Técnica no se llena ningún otro formato de Comercial (por ejemplo, una suspensión)', format($$select public.geoportal_campo_tec_crear_reporte(%L, gen_random_uuid(), 'suspension', null, null, %L, 10.44, -73.26, 8, false, '[]'::jsonb)$$, a, C1), '42501', 'Técnica');
  perform pg_temp.err('04.08 ni se prepara la subida de otro formato', format($$select public.geoportal_campo_tec_preparar_subida(%L, 2, null, 'corte')$$, a), '42501');
  perform pg_temp.err('04.09 un operador sin compartidos no crea nada', format($$select public.geoportal_campo_tec_crear_reporte(%L, gen_random_uuid(), %L, null, 'x', null, 10.44, -73.26, 8, false, '[]'::jsonb)$$, o3, v_gen), '42501');
  perform pg_temp.reg('04.10 la marca se apaga al terminar cada RPC de Técnica (no queda puesta para la llamada siguiente)', coalesce(current_setting('geoportal.via_tecnica', true), '') <> 'on');
  perform pg_temp.err('04.11 por eso el operador de Técnica sigue sin poder crear por la puerta de Comercial, aun en la misma transacción',
     format($$select public.geoportal_campo_crear_reporte(%L, gen_random_uuid(), %L, null, 'ZT8 intento por Comercial', null, 10.44, -73.26, 8, false, 'campo', '[]'::jsonb)$$, o1, v_gen), '42501');

  -- ===================== 05. Comercial sigue igual =====================
  perform pg_temp.err('05.01 sin la marca, quien no tiene campo sigue rechazado por campo.f_autorizar_reporte', format($$select campo.f_autorizar_reporte(%L)$$, o1), '42501');
  v_r := public.geoportal_campo_preparar_subida(rc, 1, 'campo', '10.0.0.9', null);
  v_id2 := (v_r ->> 'reporte_id')::uuid;
  insert into storage.objects (bucket_id, name, metadata) select 'campo-fotos', f ->> 'ruta', '{"size": 200000, "mimetype": "image/jpeg"}'::jsonb from jsonb_array_elements(v_r -> 'fotos') f;
  v_fotos := (select jsonb_agg(jsonb_build_object('orden', (f ->> 'orden')::integer, 'ruta', f ->> 'ruta', 'tomada_en', clock_timestamp())) from jsonb_array_elements(v_r -> 'fotos') f);
  v_x := public.geoportal_campo_crear_reporte(rc, v_id2, v_gen, null, 'ZT8 reporte de Comercial sin contrato', null, 10.4410, -73.2610, 8, false, 'campo', v_fotos, '10.0.0.9');
  perform pg_temp.reg('05.02 el reportante de Comercial crea su reporte como siempre: el área queda NULA (Comercial) y la respuesta no cambia',
     (select area is null and autor = rc from campo.reportes where id = v_id2) and not (v_x ? 'area') and v_x ? 'registrado_en', v_x::text);
  perform pg_temp.reg('05.03 ningún reporte que ya existía cambió: mismos registros, mismo contenido y área nula',
     (select count(*) from campo.reportes where id not in (v_id, v_id2)) = v_n0
     and (select md5(coalesce(string_agg(r.id::text || coalesce(r.descripcion, '') || coalesce(r.contrato, '') || r.registrado_en::text || coalesce(r.datos::text, ''), ',' order by r.seq), ''))
            from campo.reportes r where r.id not in (v_id, v_id2)) = v_md5
     and not exists (select 1 from campo.reportes where id not in (v_id, v_id2) and area is not null));
  perform pg_temp.reg('05.04 el formulario de Comercial sigue trayendo lo mismo para el reportante (incluidos los formatos de actividad activos)',
     public.geoportal_campo_obtener_formulario(rc, false) ->> 'perfil' = 'reportante' and position('revision_previa' in pg_temp.tipos(public.geoportal_campo_obtener_formulario(rc, false))) > 0);

  -- ===================== 06. La capa del geovisor =====================
  perform pg_temp.reg('06.01 la vista trae los dos reportes: el de Técnica con contrato (azul) y el de Comercial sin contrato (rojo, posible clandestino), con su área',
     (select string_agg(area || ':' || con_contrato, ',' order by area) from redes.v_reportes_comercial where registrado_en >= clock_timestamp() - interval '5 minutes'
        and lat between 10.4399 and 10.4411 and lon between -73.2611 and -73.2599) = 'comercial:false,tecnica:true',
     (select string_agg(area || ':' || con_contrato || ':' || codigo, ',') from redes.v_reportes_comercial where registrado_en >= clock_timestamp() - interval '5 minutes'));
  perform pg_temp.reg('06.02 sin datos del suscriptor: ni el contrato, ni la descripción, ni el autor',
     (select bool_and(to_jsonb(v)::text not like '%' || C1 || '%' and to_jsonb(v)::text not like '%ZT8%' and to_jsonb(v)::text not like '%prueba.tec8%') from redes.v_reportes_comercial v
       where v.registrado_en >= clock_timestamp() - interval '5 minutes'));
  perform pg_temp.reg('06.03 con el nombre del tipo, el estado y un código que no es el contrato',
     (select bool_and(tipo is not null and estado = 'Reportado' and codigo ~ '^REP-[0-9]{6,}$') from redes.v_reportes_comercial where registrado_en >= clock_timestamp() - interval '5 minutes'
        and lat between 10.4399 and 10.4411));
  insert into campo.reporte_eventos (reporte_id, tipo_evento, autor, motivo) values (v_id2, 'ocultar', a, 'ZT8 reporte de prueba del Corte 8');
  perform pg_temp.reg('06.04 un reporte oculto sale de la capa', not exists (select 1 from redes.v_reportes_comercial v where v.lat = 10.4410 and v.lon = -73.2610 and v.registrado_en >= clock_timestamp() - interval '5 minutes'));

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · CORTE 8 (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
