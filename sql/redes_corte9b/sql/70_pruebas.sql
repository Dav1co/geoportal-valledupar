-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1a: simulación de cierre; 1b: cierre real) · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 25, 26 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes9b.*), su red de prueba (ZT9B, en un rincón de la caja de Valledupar, lejos de la red)
-- con sus contratos (números de 15 cifras que empiezan por 99999), su daño y su intervención. Ninguna cifra de la red real se da por supuesta.
-- La red de prueba (x, y en metros):
--     F(tanque) —T1— A —T2— V1(cierra) —T3— B —T4— V2(sin definir) —T5— C —T6— V3(cierra) —T7— D —T14(proyectado)— K
--                                            B —T8— V4(deriva) —T9— E          C —T12— H
--                                            B —T10— V5(ventosa) —T11— G       C —T13— F2(tanque)
-- Mide con el volumen real: simula sobre tramos, una válvula y un tanque de la red de la base donde corre, y FALLA si una simulación pasa de 5 s.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 9b … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- un rincón de la caja de Valledupar, lejos de la red (x, y en metros aproximados)
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.1300 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.5800 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create temp table _zt (nombre text primary key, activo_id bigint, nodo bigint, x numeric, y numeric);
-- un activo de prueba (versión 1); devuelve su id
create function pg_temp.activo(p_nombre text, p_prefijo text, p_geom geometry, p_clase text default null, p_efecto text default null, p_estado text default 'en_operacion')
returns bigint language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes9b.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZT9B ' || p_nombre, p_clase, p_efecto,
          case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end, case when p_prefijo = 'RED' then 110 end,
          p_estado, '{}'::jsonb, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT9B activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_id;
end $$;
-- un nodo de la red de prueba (con su activo si es válvula o tanque)
create function pg_temp.nodo(p_nombre text, x numeric, y numeric, p_carga bigint, p_prefijo text default null, p_clase text default null, p_efecto text default null)
returns void language plpgsql as $$
declare v_act bigint; v_n bigint;
begin
  if p_prefijo is not null then v_act := pg_temp.activo(p_nombre, p_prefijo, pg_temp.pt(x, y), p_clase, p_efecto); end if;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id)
  values ('acueducto', 'ZT9B-' || p_nombre, 'ZT9B' || p_nombre, case when v_act is null then 'por_clasificar' else 'activo' end, pg_temp.pt(x, y), v_act, 0, p_carga)
  returning id into v_n;
  insert into _zt values (p_nombre, v_act, v_n, x, y);
end $$;
-- un tramo de la red de prueba entre dos nodos, con n contratos de prueba
create function pg_temp.tramo(p_nombre text, p_a text, p_b text, p_carga bigint, p_contratos integer, p_estado text default 'en_operacion')
returns void language plpgsql as $$
declare a _zt; b _zt; v_id bigint;
begin
  select * into a from _zt where nombre = p_a; select * into b from _zt where nombre = p_b;
  v_id := pg_temp.activo(p_nombre, 'RED', ST_MakeLine(pg_temp.pt(a.x, a.y), pg_temp.pt(b.x, b.y)), null, null, p_estado);
  insert into redes.tramo_nodos (activo_id, version, nodo_ini, nodo_fin, metodo, carga_id) values (v_id, 1, a.nodo, b.nodo, 'modelo', p_carga);
  insert into _zt values (p_nombre, v_id, null, (a.x + b.x) / 2, (a.y + b.y) / 2);
  insert into redes.contrato_tramo (contrato, activo_id, distancia_m, metodo)
  select '99999' || lpad((v_id % 100000)::text, 5, '0') || lpad(i::text, 5, '0'), v_id, 5, 'cercania' from generate_series(1, p_contratos) i;
end $$;
create function pg_temp.id(p_nombre text) returns bigint language sql as $$ select activo_id from _zt where nombre = p_nombre $$;
create function pg_temp.cod(p_nombre text) returns text language sql as $$ select a.codigo from redes.activos a join _zt z on z.activo_id = a.id where z.nombre = p_nombre $$;
create function pg_temp.cods(p jsonb) returns text language sql as $$ select coalesce(string_agg(x ->> 'codigo', ',' order by o), '') from jsonb_array_elements(p) with ordinality y(x, o) $$;
create function pg_temp.ncods(p text) returns text language sql as $$
  select coalesce(string_agg(pg_temp.cod(btrim(x)), ',' order by o), '') from unnest(string_to_array(p, ',')) with ordinality u(x, o) $$;
-- la tesela (z, x, y) que contiene un punto
create function pg_temp.tx(g geometry, z integer) returns integer language sql as $$ select floor((ST_X(g) + 180) / 360 * (1 << z))::integer $$;
create function pg_temp.ty(g geometry, z integer) returns integer language sql as $$
  select floor((1 - ln(tan(radians(ST_Y(g))) + 1 / cos(radians(ST_Y(g)))) / pi()) / 2 * (1 << z))::integer $$;
create function pg_temp.foto() returns redes.corte_fotos language sql as $$ select * from redes.corte_fotos order by id desc limit 1 $$;
create function pg_temp.archivo(p_ruta text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg')) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;

do $prueba$
declare
  a text := 'prueba.redes9b.adm@emdupar.gov.co'; sd text := 'prueba.redes9b.dist@emdupar.gov.co'; op text := 'prueba.redes9b.op@emdupar.gov.co';
  op2 text := 'prueba.redes9b.mant@emdupar.gov.co'; op3 text := 'prueba.redes9b.op3@emdupar.gov.co'; na text := 'prueba.redes9b.nada@emdupar.gov.co';
  v_carga bigint; j jsonb; j2 jsonb; v_p jsonb; v_dan text; v_itv text; v_h1 text; v_h2 text; v_s jsonb; v_n integer; r record;
  v_t0 timestamptz; v_ms numeric; v_max numeric := 0; v_max_m numeric; v_nm integer; v_ms_v numeric; v_ms_t numeric; v_ms_a numeric; v_tiempos text := ''; v_peq integer := 0; v_info text := ''; v_total integer; v_bien integer; v_fallas text;
begin
  -- ---------- personas de prueba ----------
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9B Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT9B Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values
    (op, 'ZT9B Operador daños', 'consulta', true, 'sin_restriccion', 'todos'), (op2, 'ZT9B Operador mantenimiento', 'consulta', true, 'sin_restriccion', 'todos'),
    (op3, 'ZT9B Otro operador daños', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT9B Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values
    (op, 'asignar_formulario', 'danos_fallas', a), (op2, 'asignar_formulario', 'mantenimiento', a), (op3, 'asignar_formulario', 'danos_fallas', a);

  -- ---------- la red de prueba ----------
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
  values ('acueducto', md5('zt9b-a') || md5('zt9b-b'), 'shp', 4326, 'ID', 1, 'ZT9B red de prueba', a) returning id into v_carga;
  perform pg_temp.nodo('F', 0, 0, v_carga, 'TAN');
  perform pg_temp.nodo('A', 100, 0, v_carga);
  perform pg_temp.nodo('V1', 200, 0, v_carga, 'VAL', 'cierre', 'cierra');
  perform pg_temp.nodo('B', 300, 0, v_carga);
  perform pg_temp.nodo('V2', 400, 0, v_carga, 'VAL', 'cierre', 'sin_definir');
  perform pg_temp.nodo('C', 500, 0, v_carga);
  perform pg_temp.nodo('V3', 600, 0, v_carga, 'VAL', 'cierre', 'cierra');
  perform pg_temp.nodo('D', 700, 0, v_carga);
  perform pg_temp.nodo('K', 800, 0, v_carga);
  perform pg_temp.nodo('V4', 300, 100, v_carga, 'VAL', 'cierre', 'deriva');
  perform pg_temp.nodo('E', 300, 200, v_carga);
  perform pg_temp.nodo('V5', 300, -100, v_carga, 'VAL', 'ventosa', 'cierra');
  perform pg_temp.nodo('G', 300, -200, v_carga);
  perform pg_temp.nodo('H', 500, 100, v_carga);
  perform pg_temp.nodo('F2', 500, -100, v_carga, 'TAN');
  perform pg_temp.tramo('T1', 'F', 'A', v_carga, 1);
  perform pg_temp.tramo('T2', 'A', 'V1', v_carga, 1);
  perform pg_temp.tramo('T3', 'V1', 'B', v_carga, 1);
  perform pg_temp.tramo('T4', 'B', 'V2', v_carga, 2);
  perform pg_temp.tramo('T5', 'V2', 'C', v_carga, 1);
  perform pg_temp.tramo('T6', 'C', 'V3', v_carga, 1);
  perform pg_temp.tramo('T7', 'V3', 'D', v_carga, 2);
  perform pg_temp.tramo('T8', 'B', 'V4', v_carga, 1);
  perform pg_temp.tramo('T9', 'V4', 'E', v_carga, 1);
  perform pg_temp.tramo('T10', 'B', 'V5', v_carga, 0);
  perform pg_temp.tramo('T11', 'V5', 'G', v_carga, 1);
  perform pg_temp.tramo('T12', 'C', 'H', v_carga, 3);
  perform pg_temp.tramo('T13', 'C', 'F2', v_carga, 0);
  perform pg_temp.tramo('T14', 'D', 'K', v_carga, 4, 'proyectado');

  -- ===================== 01. Estructura =====================
  perform pg_temp.reg('01.01 la tabla de simulaciones existe, con RLS, sin permisos de la API y de solo agregar (2 disparadores)',
     (select relrowsecurity from pg_class where oid = 'redes.simulaciones_cierre'::regclass)
     and not has_table_privilege('service_role', 'redes.simulaciones_cierre', 'select') and not has_table_privilege('anon', 'redes.simulaciones_cierre', 'select')
     and (select count(*) from pg_trigger t where t.tgrelid = 'redes.simulaciones_cierre'::regclass and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 2);
  perform pg_temp.reg('01.02 los 6 parámetros de la simulación existen, con unidad entera',
     (select count(*) from redes.parametros where clave like 'sim\_%' and estado = 'vigente' and redes.f_param_entero(unidad)) = 6);
  perform pg_temp.reg('01.03 las RPC nuevas: solo service_role; las internas: nadie de la API',
     has_function_privilege('service_role', 'public.geoportal_redes_simulacion_cierre(text,text,numeric,numeric)', 'execute')
     and not has_function_privilege('authenticated', 'public.geoportal_redes_simulacion_guardar(text,text,text)', 'execute')
     and not has_function_privilege('service_role', 'redes.f_simular_cierre(bigint)', 'execute'));

  -- ===================== 02. El caso de la §17 sobre la red de prueba: daño en T4 =====================
  j := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('T4'));
  perform pg_temp.reg('02.01 estrecho (las «sin definir» cierran): cerrar V2 y V1, en orden de cercanía',
     pg_temp.cods(j -> 'estrecho' -> 'valvulas') = pg_temp.ncods('V2,V1') and (j -> 'estrecho' ->> 'valvulas_total')::integer = 2, j -> 'estrecho' ->> 'valvulas');
  perform pg_temp.reg('02.02 estrecho: el segmento son T3, T4, T8, T9, T10 y T11 (la «deriva» y la ventosa no detienen); nada aguas abajo (C se alimenta de F2); 6 contratos',
     (j -> 'estrecho' ->> 'tramos_segmento')::integer = 6 and (j -> 'estrecho' ->> 'tramos_aguas_abajo')::integer = 0 and (j -> 'estrecho' ->> 'contratos')::integer = 6
     and (select string_agg(x, ',' order by x) from jsonb_array_elements_text(j -> 'tramos') x) = (select string_agg(pg_temp.cod(t), ',' order by pg_temp.cod(t)) from unnest(array['T3', 'T4', 'T8', 'T9', 'T10', 'T11']) t),
     j ->> 'estrecho');
  perform pg_temp.reg('02.03 amplio (la «sin definir» no cierra): cerrar V1 y V3; T7 queda aguas abajo sin agua; el tanque F2 queda aislado; 13 contratos',
     pg_temp.cods(j -> 'amplio' -> 'valvulas') = pg_temp.ncods('V1,V3') and (j -> 'amplio' ->> 'tramos_aguas_abajo')::integer = 1
     and (j -> 'amplio' ->> 'contratos')::integer = 13 and pg_temp.cods(j -> 'amplio' -> 'fuentes_aisladas') = pg_temp.cod('F2'), j ->> 'amplio');
  perform pg_temp.reg('02.04 el rango (N-9): entre 6 y 13 contratos, y la «sin definir» que hace la diferencia es V2',
     (j ->> 'contratos_min')::integer = 6 and (j ->> 'contratos_max')::integer = 13 and (j ->> 'rango')::boolean
     and j -> 'dudosas' = jsonb_build_array(pg_temp.cod('V2')) and not (j ->> 'segmento_grande')::boolean);
  perform pg_temp.reg('02.05 la «deriva» (V4) y la ventosa (V5) nunca salen como válvulas a cerrar',
     position(pg_temp.cod('V4') in j::text) = 0 and position(pg_temp.cod('V5') in j::text) = 0);
  perform pg_temp.reg('02.06 «si V2 no cierra»: cerrar V3 en su lugar (13 contratos); «si V1 no cierra»: no hay otra hacia ese lado (8 contratos)',
     (select pg_temp.cods(x -> 'cerrar_en_su_lugar') = pg_temp.cod('V3') and (x ->> 'contratos')::integer = 13 from jsonb_array_elements(j -> 'si_no_cierra') x where x ->> 'valvula' = pg_temp.cod('V2'))
     and (select jsonb_array_length(x -> 'cerrar_en_su_lugar') = 0 and (x ->> 'contratos')::integer = 8 from jsonb_array_elements(j -> 'si_no_cierra') x where x ->> 'valvula' = pg_temp.cod('V1')),
     j ->> 'si_no_cierra');
  perform pg_temp.reg('02.07 alternativas: las 2 que dejan menos contratos sin agua, de menor a mayor (V1: 8; V2: 13)',
     (select string_agg((x ->> 'valvula') || ':' || (x ->> 'contratos'), ',' order by o) from jsonb_array_elements(j -> 'alternativas') with ordinality y(x, o))
       = pg_temp.cod('V1') || ':8,' || pg_temp.cod('V2') || ':13', j ->> 'alternativas');
  perform pg_temp.reg('02.08 la respuesta no trae la lista interna de contratos ni datos de personas; dice que es la red registrada y trae las notas',
     not (j ? '_contratos') and j::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n|tarifa|estrato' and j -> 'red' ->> 'fuente' like 'red registrada%'
     and jsonb_array_length(j -> 'notas') >= 4 and (j ->> 'ms')::numeric >= 0);

  -- ===================== 03. Otros puntos de trabajo =====================
  j := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('V2'));
  perform pg_temp.reg('03.01 trabajo SOBRE la válvula V2: no sirve para aislarse a sí misma; cerrar V1 y V3 (13 contratos)',
     pg_temp.cods(j -> 'estrecho' -> 'valvulas') = pg_temp.ncods('V2,V1,V3') is not true and pg_temp.cods(j -> 'estrecho' -> 'valvulas') in (pg_temp.ncods('V1,V3'), pg_temp.ncods('V3,V1'))
     and (j -> 'estrecho' ->> 'contratos')::integer = 13, j ->> 'estrecho');
  j := public.geoportal_redes_simulacion_cierre(op, null, pg_temp.lat(4), pg_temp.lon(350));
  perform pg_temp.reg('03.02 sin activo, con un punto a 4 m de T4: simula sobre T4 (el tramo en operación más cercano)', j -> 'activo' ->> 'codigo' = pg_temp.cod('T4'));
  perform pg_temp.err('03.03 un punto lejos de todo tramo: «No hay un tramo de acueducto…»',
     format('select public.geoportal_redes_simulacion_cierre(%L, null, %s, %s)', op, pg_temp.lat(5000), pg_temp.lon(5000)), null, 'No hay un tramo de acueducto');
  perform pg_temp.err('03.04 un tramo proyectado (T14) no conduce agua: lo dice',
     format('select public.geoportal_redes_simulacion_cierre(%L, %L)', op, pg_temp.cod('T14')), null, 'no conduce agua');
  perform pg_temp.err('03.05 un activo de alcantarillado: «solo para acueducto»',
     format('select public.geoportal_redes_simulacion_cierre(%L, %L)', op, (select codigo from redes.activo_vigente_mat where sistema = 'alcantarillado' and not retirado order by activo_id limit 1)),
     null, 'solo para acueducto');

  -- ===================== 04. Quién =====================
  perform pg_temp.reg('04.01 el operador de mantenimiento también simula', (public.geoportal_redes_simulacion_cierre(op2, pg_temp.cod('T4')) ->> 'contratos_min')::integer = 6);
  perform pg_temp.err('04.02 alguien sin Técnica no simula (42501)', format('select public.geoportal_redes_simulacion_cierre(%L, %L)', na, pg_temp.cod('T4')), '42501');
  perform pg_temp.err('04.03 sin solicitante: 28000', format('select public.geoportal_redes_simulacion_cierre(%L, %L)', '', pg_temp.cod('T4')), '28000');

  -- ===================== 05. Guardar con el daño o la intervención =====================
  v_p := public.geoportal_redes_preparar_dano(op, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_dan := public.geoportal_redes_crear_dano(op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           'activo', pg_temp.cod('T4'), 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(350),
           't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
           'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
  j := public.geoportal_redes_simulacion_guardar(op, v_dan);
  perform pg_temp.reg('05.01 quien registró el daño guarda la simulación: queda con el daño, su activo, el rango, la huella de la red y los 6 contratos del escenario estrecho',
     (select s.dano_id = (select id from redes.danos where codigo = v_dan) and s.activo_id = pg_temp.id('T4') and s.contratos_min = 6 and s.contratos_max = 13 and s.valvulas = 2
             and s.red_huella = j -> 'red' ->> 'huella' and cardinality(s.contratos) = 6 and s.autor = op and not (s.resultado ? '_contratos')
        from redes.simulaciones_cierre s where s.id = (j ->> 'id')::bigint) and not (j ? '_contratos') and j ->> 'registro' = v_dan);
  perform pg_temp.err('05.02 otro operador de daños no guarda en un daño ajeno (42501)', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', op3, v_dan), '42501', 'Solo quien lo registró');
  perform pg_temp.err('05.03 el operador de mantenimiento no guarda en un daño (no tiene ese formulario)', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', op2, v_dan), '42501');
  j := public.geoportal_redes_simulacion_guardar(sd, v_dan, pg_temp.cod('V2'));
  perform pg_temp.reg('05.04 el supervisor guarda en ese daño otra simulación, sobre otro activo (V2)',
     (select s.activo_id = pg_temp.id('V2') and s.autor = sd from redes.simulaciones_cierre s where s.id = (j ->> 'id')::bigint));
  v_s := public.geoportal_redes_simulaciones(op, v_dan);
  perform pg_temp.reg('05.05 las guardadas del daño: 2, la última primero, con su resultado',
     jsonb_array_length(v_s -> 'simulaciones') = 2 and v_s -> 'simulaciones' -> 0 ->> 'activo' = pg_temp.cod('V2') and v_s -> 'simulaciones' -> 1 -> 'resultado' ? 'estrecho');
  v_p := public.geoportal_redes_preparar_intervencion(sd, 1, 0);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_itv := public.geoportal_redes_crear_intervencion(sd, (v_p ->> 'intervencion_id')::uuid, jsonb_build_object('nace_de', 'programada', 'tipo', 'preventivo', 'sistema', 'acueducto',
         'activo', pg_temp.cod('T4'), 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(350), 'precision_m', 5, 'ubicacion_origen', 'gps', 't_inicio', pg_temp.iso('-50 minutes'), 't_fin', pg_temp.iso('-10 minutes'),
         'descripcion', 'ZT9B cambio de válvula programado', 'materiales', '[]'::jsonb, 'ejecutor', 'emdupar', 'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')),
         'archivos', jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'despues', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
  j := public.geoportal_redes_simulacion_guardar(sd, v_itv);
  perform pg_temp.reg('05.06 con una intervención (corte programado): queda con la intervención y su tramo',
     (select s.intervencion_id = (select id from redes.intervenciones where codigo = v_itv) and s.dano_id is null and s.activo_id = pg_temp.id('T4')
        from redes.simulaciones_cierre s where s.id = (j ->> 'id')::bigint));
  perform pg_temp.err('05.07 el operador de mantenimiento no guarda en una intervención ajena (42501)', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', op2, v_itv), '42501');
  perform pg_temp.err('05.08 un código que no es de daño ni de intervención', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', sd, 'RED-000001'), null, 'Escriba el código');
  perform pg_temp.err('05.09 un daño que no existe: P0002', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', sd, 'DAN-999999'), 'P0002');
  update redes.parametros set valor = 2 where clave = 'sim_guardadas_max';
  perform pg_temp.err('05.10 con el tope de guardadas (2), una tercera en el mismo daño se niega', format('select public.geoportal_redes_simulacion_guardar(%L, %L)', sd, v_dan), null, 'el máximo');
  update redes.parametros set valor = 20 where clave = 'sim_guardadas_max';
  perform pg_temp.err('05.11 solo agregar: no se cambia una simulación guardada', 'update redes.simulaciones_cierre set valvulas = 0 where id = (select min(id) from redes.simulaciones_cierre)');
  perform pg_temp.err('05.12 solo agregar: no se borra una simulación guardada', 'delete from redes.simulaciones_cierre where id = (select min(id) from redes.simulaciones_cierre)');

  -- ===================== 08. Fase 1b: el cierre real sobre la red de prueba =====================
  -- (antes de la sección 06, que deja V1 fuera de servicio). El daño v_dan y la intervención v_itv son sobre T4.
  j := public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V1'), 'cerrar', v_dan, null, null, pg_temp.iso('3 hours'));
  perform pg_temp.reg('08.01 el operador de daños cierra V1 con su daño (y la hora estimada de regreso): queda cerrada, con la foto del corte',
     j ->> 'estado' = 'cerrada' and (j -> 'vigente' ->> 'valvulas_cerradas')::integer = 1
     and (select m.dano_id = (select id from redes.danos where codigo = v_dan) and m.autor = op and m.regreso_estimado is not null
            from redes.valvula_maniobras m where m.id = (j ->> 'maniobra')::bigint), j::text);
  perform pg_temp.err('08.02 cerrar otra vez una válvula cerrada: «ya está cerrada»', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, %L)', op, pg_temp.cod('V1'), 'cerrar', v_dan), null, 'ya está cerrada');
  j := public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V2'), 'cerrar', v_dan);
  perform pg_temp.reg('08.03 con V1 y V2 cerradas: 1 zona; T3, T4, T8, T9, T10 y T11 son «tubería cerrada» (el sector del daño); nada afectado; 6 contratos',
     (pg_temp.foto()).zonas = 1 and (pg_temp.foto()).tramos_cerrados = 6 and (pg_temp.foto()).tramos_afectados = 0 and (pg_temp.foto()).contratos_cerrados = 6
     and (select string_agg(a.codigo, ',' order by a.codigo) from redes.corte_foto_tramos ft join redes.activos a on a.id = ft.activo_id where ft.foto_id = (pg_temp.foto()).id and ft.papel = 'cerrado')
         = (select string_agg(pg_temp.cod(t), ',' order by pg_temp.cod(t)) from unnest(array['T3', 'T4', 'T8', 'T9', 'T10', 'T11']) t), row_to_json(pg_temp.foto())::text);
  j := public.geoportal_redes_valvula_maniobra(sd, pg_temp.cod('V3'), 'cerrar', v_itv, null, null, pg_temp.iso('5 hours'));
  perform pg_temp.reg('08.04 el supervisor cierra V3 con la intervención: T7 queda «sin agua» (afectado, 2 contratos) en una segunda zona',
     (pg_temp.foto()).zonas = 2 and (pg_temp.foto()).tramos_afectados = 1 and (pg_temp.foto()).contratos_afectados = 2 and (pg_temp.foto()).tramos_cerrados = 6
     and (select ft.papel = 'afectado' from redes.corte_foto_tramos ft where ft.foto_id = (pg_temp.foto()).id and ft.activo_id = pg_temp.id('T7')), row_to_json(pg_temp.foto())::text);
  perform pg_temp.err('08.05b quien no tiene el geovisor técnico no ve los cortes vigentes (42501)', format('select public.geoportal_redes_cortes_vigentes(%L)', op), '42501');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT9B prueba: el operador con el geovisor');
  v_s := public.geoportal_redes_cortes_vigentes(op);
  perform pg_temp.reg('08.05 lo que ve el geovisor: 2 zonas (la de 6 contratos primero, por el daño; la otra por «trabajo programado», con su regreso estimado), 3 válvulas con quién y desde cuándo, leyenda sencilla',
     (v_s ->> 'hay')::boolean and (v_s -> 'resumen' ->> 'zonas')::integer = 2 and (v_s -> 'resumen' ->> 'contratos')::integer = 8
     and (v_s -> 'zonas' -> 0 ->> 'contratos')::integer = 6 and v_s -> 'zonas' -> 0 -> 'por' -> 0 ->> 'registro' = v_dan
     and v_s -> 'zonas' -> 1 -> 'por' -> 0 ->> 'que' = 'trabajo programado' and v_s -> 'zonas' -> 1 ->> 'regreso_estimado' is not null
     and jsonb_array_length(v_s -> 'valvulas') = 3 and (select bool_and(x ->> 'quien' like 'ZT9B%' and x ->> 'desde' is not null) from jsonb_array_elements(v_s -> 'valvulas') x)
     and (select string_agg(x ->> 'texto', ',' order by o) from jsonb_array_elements(v_s -> 'leyenda') with ordinality y(x, o)) = 'Sin agua,Tubería cerrada,Válvula cerrada'
     and v_s::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n|@emdupar', left(v_s::text, 600));
  perform pg_temp.reg('08.06 la tesela del modo «Afectaciones» trae la zona (z 16 en T4) y nada lejos de ella',
     length(public.geoportal_redes_geovisor_mvt_cortes(op, 16, pg_temp.tx(pg_temp.pt(350, 0), 16), pg_temp.ty(pg_temp.pt(350, 0), 16))) > 0
     and public.geoportal_redes_geovisor_mvt_cortes(op, 16, pg_temp.tx(pg_temp.pt(5000, 5000), 16), pg_temp.ty(pg_temp.pt(5000, 5000), 16)) = '');
  perform pg_temp.err('08.07 el operador de mantenimiento no cierra con un daño (no tiene ese formulario)', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, %L)', op2, pg_temp.cod('V4'), 'cerrar', v_dan), '42501');
  perform pg_temp.err('08.08 sin daño ni intervención, el operador no cierra (solo el supervisor)',
     format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, null, %L)', op, pg_temp.cod('V4'), 'cerrar', 'ZT9B maniobra de operación'), '42501');
  perform pg_temp.err('08.09 sin daño ni intervención, el supervisor debe escribir el motivo', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L)', sd, pg_temp.cod('V4'), 'cerrar'), null, 'motivo');
  perform pg_temp.err('08.10 abrir una válvula que no está cerrada', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L)', op, pg_temp.cod('V4'), 'abrir'), null, 'no está cerrada');
  perform pg_temp.err('08.11 una maniobra en el futuro se niega', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, %L, null, %L)', op, pg_temp.cod('V4'), 'cerrar', v_dan, pg_temp.iso('2 hours')), null, 'futura');
  perform pg_temp.err('08.12 una maniobra de hace más de 48 h se niega', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, %L, null, %L)', op, pg_temp.cod('V4'), 'cerrar', v_dan, pg_temp.iso('-50 hours')), null, 'más de');
  perform pg_temp.err('08.13 abrir antes de la hora en que se cerró se niega', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L, null, null, %L)', op, pg_temp.cod('V1'), 'abrir', pg_temp.iso('-2 hours')), null, 'antes de la hora');
  perform pg_temp.err('08.14 la hora de regreso la ajusta quien cerró o el supervisor: otro operador no (42501)',
     format('select public.geoportal_redes_corte_regreso(%L, %L, %L)', op3, pg_temp.cod('V1'), pg_temp.iso('6 hours')), '42501');
  j := public.geoportal_redes_corte_regreso(sd, pg_temp.cod('V1'), pg_temp.iso('8 hours'), 'ZT9B la cuadrilla pidió más tiempo');
  perform pg_temp.reg('08.15 el supervisor ajusta la hora de regreso: vale la última, la anterior queda guardada',
     (select redes.f_cierre_regreso(c.cierre_id) = (j ->> 'regreso_estimado')::timestamptz from redes.f_cierres_vigentes() c where c.valvula_id = pg_temp.id('V1'))
     and (select count(*) from redes.valvula_maniobras m where m.valvula_id = pg_temp.id('V1') and m.regreso_estimado is not null) = 2);
  perform pg_temp.reg('08.16 Avisos (distribución): a las 7 h, «3 válvulas cerradas hace más de 6 h» en naranja; a las 13 h, en rojo',
     (select (av ->> 'n')::integer >= 3 and av ->> 'titulo' like '%válvulas cerradas hace más de 6 h' from jsonb_array_elements(tecnica.f_avisos(false, true, clock_timestamp() + interval '7 hours')) av
       where av ->> 'clave' = 'valvulas_cerradas_naranja')
     and exists (select 1 from jsonb_array_elements(tecnica.f_avisos(false, true, clock_timestamp() + interval '13 hours')) av where av ->> 'clave' = 'valvulas_cerradas_rojo')
     and not exists (select 1 from jsonb_array_elements(tecnica.f_avisos(false, true, clock_timestamp() + interval '1 hour')) av where av ->> 'clave' like 'valvulas_cerradas%'));
  j := public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V2'), 'abrir');
  perform pg_temp.reg('08.17 abrir V2 (con el mismo daño): el sector del daño vuelve a tener agua por C; solo T7 sigue sin agua (1 zona, afectado)',
     j ->> 'estado' = 'abierta' and (pg_temp.foto()).zonas = 1 and (pg_temp.foto()).tramos_cerrados = 0 and (pg_temp.foto()).tramos_afectados = 1
     and (select m.dano_id = (select id from redes.danos where codigo = v_dan) from redes.valvula_maniobras m where m.id = (j ->> 'maniobra')::bigint), row_to_json(pg_temp.foto())::text);
  perform pg_temp.err('08.18 solo agregar: no se cambia una maniobra', 'update redes.valvula_maniobras set motivo = ''ZT9B cambio indebido'' where id = (select min(id) from redes.valvula_maniobras)');
  perform pg_temp.err('08.19 solo agregar: no se borra una foto', 'delete from redes.corte_foto_tramos where foto_id = (select min(foto_id) from redes.corte_foto_tramos)');
  perform pg_temp.err('08.20 recalcular los cortes es del supervisor', format('select public.geoportal_redes_cortes_recalcular(%L, %L)', op, 'ZT9B la red cambió'), '42501');
  perform pg_temp.reg('08.21 el supervisor recalcula (la red cambió): foto nueva, mismo resultado',
     (public.geoportal_redes_cortes_recalcular(sd, 'ZT9B la red cambió') ->> 'zonas')::integer = 1 and (pg_temp.foto()).maniobra_id is null);
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V1'), 'abrir');
  perform public.geoportal_redes_valvula_maniobra(sd, pg_temp.cod('V3'), 'abrir');
  perform pg_temp.reg('08.22 con todo abierto: el geovisor no muestra nada (ni franja) y no hay aviso',
     not (public.geoportal_redes_cortes_vigentes(op) ->> 'hay')::boolean and (pg_temp.foto()).valvulas_cerradas = 0
     and public.geoportal_redes_geovisor_mvt_cortes(op, 16, pg_temp.tx(pg_temp.pt(350, 0), 16), pg_temp.ty(pg_temp.pt(350, 0), 16)) = ''
     and not exists (select 1 from jsonb_array_elements(tecnica.f_avisos(false, true, clock_timestamp() + interval '13 hours')) av where av ->> 'clave' like 'valvulas_cerradas%'));

  -- ===================== 06. Lo que cambia la ficha cambia la simulación =====================
  v_h1 := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('T4')) -> 'red' ->> 'huella';
  v_h2 := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('T4')) -> 'red' ->> 'huella';
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (pg_temp.id('V2'), 'por_verificar', 'ZT9B prueba: hay que verificar en campo si opera', a);
  j := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('T4'));
  perform pg_temp.reg('06.01 la huella de la red no cambia entre dos simulaciones; una válvula «por verificar» sale marcada (y cambia la huella)',
     v_h1 = v_h2 and j -> 'red' ->> 'huella' <> v_h1
     and (select (x ->> 'por_verificar')::boolean from jsonb_array_elements(j -> 'estrecho' -> 'valvulas') x where x ->> 'codigo' = pg_temp.cod('V2')));
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, estado_codigo, atributos, huella, autor)
  select activo_id, 2, pg_temp.pt(200, 0), 'ZT9B V1', 'cierre', 'cierra', 'fuera_servicio', '{}'::jsonb, md5('zt9b-v1-2'), a from _zt where nombre = 'V1';
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (pg_temp.id('V1'), 2, 'emdupar', 'ZT9B V1 fuera de servicio', a);
  perform redes.f_mat_refrescar_uno(pg_temp.id('V1'));
  j := public.geoportal_redes_simulacion_cierre(op, pg_temp.cod('T4'));
  perform pg_temp.reg('06.02 con V1 fuera de servicio, ya no sirve: solo V2 cierra ese lado y el tanque F queda dentro (8 contratos en el estrecho)',
     pg_temp.cods(j -> 'estrecho' -> 'valvulas') = pg_temp.cod('V2') and (j -> 'estrecho' ->> 'contratos')::integer = 8
     and pg_temp.cods(j -> 'estrecho' -> 'fuentes_aisladas') = pg_temp.cod('F'), j ->> 'estrecho');

  -- ===================== 07. Tiempos con la red real (la de la base donde corre) =====================
  for r in (select m.activo_id, m.codigo, 'tramo' as que from redes.activo_vigente_mat m
             where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
             order by md5(m.activo_id::text) limit 4)
           union all
           (select tn.activo_id, m.codigo, 'tramo junto a una válvula' from redes.tramo_nodos tn join redes.activo_vigente_mat m on m.activo_id = tn.activo_id and m.version = tn.version
              join redes.nodos n on n.id = tn.nodo_fin join redes.activo_vigente_mat v on v.activo_id = n.activo_id and v.prefijo = 'VAL'
             where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
             order by md5(tn.activo_id::text) limit 2)
           union all
           (select tn.activo_id, m.codigo, 'tramo entre dos válvulas' from redes.tramo_nodos tn join redes.activo_vigente_mat m on m.activo_id = tn.activo_id and m.version = tn.version
              join redes.nodos n1 on n1.id = tn.nodo_ini join redes.activo_vigente_mat v1 on v1.activo_id = n1.activo_id and v1.prefijo = 'VAL'
              join redes.nodos n2 on n2.id = tn.nodo_fin join redes.activo_vigente_mat v2 on v2.activo_id = n2.activo_id and v2.prefijo = 'VAL'
             where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
             order by md5(tn.activo_id::text) limit 2)
           union all
           (select m.activo_id, m.codigo, 'válvula' from redes.activo_vigente_mat m join redes.nodos n on n.activo_id = m.activo_id
             where m.prefijo = 'VAL' and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
               and exists (select 1 from redes.tramo_nodos t where t.nodo_ini = n.id or t.nodo_fin = n.id)
             order by md5(m.activo_id::text) limit 1)
           union all
           (select m.activo_id, m.codigo, 'tanque' from redes.activo_vigente_mat m join redes.nodos n on n.activo_id = m.activo_id
             where m.prefijo = 'TAN' and m.cuenta_vigente and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
               and exists (select 1 from redes.tramo_nodos t where t.nodo_ini = n.id or t.nodo_fin = n.id)
             order by md5(m.activo_id::text) limit 1) loop
    v_t0 := clock_timestamp();
    begin
      j := public.geoportal_redes_simulacion_cierre(a, r.codigo);
      v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
      v_tiempos := v_tiempos || format(' · %s %s %s ms (%s–%s contratos, %s válvulas%s)', r.que, r.codigo, v_ms, j ->> 'contratos_min', j ->> 'contratos_max',
                                       j -> 'estrecho' ->> 'valvulas_total', case when (j ->> 'segmento_grande')::boolean then ', segmento grande' else '' end);
      if not (j ->> 'segmento_grande')::boolean then v_peq := v_peq + 1; end if;
    exception when others then
      v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
      v_tiempos := v_tiempos || format(' · %s %s %s ms (%s)', r.que, r.codigo, v_ms, sqlerrm);
    end;
    v_max := greatest(v_max, v_ms); v_n := coalesce(v_n, 0) + 1;
  end loop;
  -- cierre real con la red real: el supervisor cierra 12 válvulas reales (las dos de cada uno de 6 tramos entre dos válvulas), una por una; cada maniobra saca la foto
  for r in (select v.codigo from (select distinct v1.codigo, v1.activo_id from redes.tramo_nodos tn join redes.activo_vigente_mat m on m.activo_id = tn.activo_id and m.version = tn.version
              join redes.nodos n1 on n1.id in (tn.nodo_ini, tn.nodo_fin) join redes.activo_vigente_mat v1 on v1.activo_id = n1.activo_id and v1.prefijo = 'VAL' and not v1.retirado
             where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado and m.activo_id not in (select activo_id from _zt where activo_id is not null)
               and tn.activo_id in (select tn2.activo_id from redes.tramo_nodos tn2
                                      join redes.nodos a1 on a1.id = tn2.nodo_ini join redes.activo_vigente_mat b1 on b1.activo_id = a1.activo_id and b1.prefijo = 'VAL'
                                      join redes.nodos a2 on a2.id = tn2.nodo_fin join redes.activo_vigente_mat b2 on b2.activo_id = a2.activo_id and b2.prefijo = 'VAL'
                                     order by md5(tn2.activo_id::text) limit 6)) v order by md5(v.activo_id::text) limit 12) loop
    v_t0 := clock_timestamp();
    perform public.geoportal_redes_valvula_maniobra(a, r.codigo, 'cerrar', null, 'ZT9B prueba de tiempos con la red real');
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000); v_max_m := greatest(coalesce(v_max_m, 0), v_ms); v_nm := coalesce(v_nm, 0) + 1;
  end loop;
  v_t0 := clock_timestamp(); v_s := public.geoportal_redes_cortes_vigentes(a); v_ms_v := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp();
  perform public.geoportal_redes_geovisor_mvt_cortes(a, 15, pg_temp.tx(ST_SetSRID(ST_MakePoint((v_s -> 'zonas' -> 0 ->> 'lon')::float8, (v_s -> 'zonas' -> 0 ->> 'lat')::float8), 4326), 15),
                                                     pg_temp.ty(ST_SetSRID(ST_MakePoint((v_s -> 'zonas' -> 0 ->> 'lon')::float8, (v_s -> 'zonas' -> 0 ->> 'lat')::float8), 4326), 15))
   where (v_s ->> 'hay')::boolean and jsonb_array_length(v_s -> 'zonas') > 0;
  v_ms_t := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform tecnica.f_avisos(true, true, clock_timestamp() + interval '13 hours'); v_ms_a := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_tiempos := v_tiempos || format(' · CIERRE REAL: %s maniobras, la más lenta %s ms (con la foto; quedan %s zonas, %s contratos) · cortes vigentes %s ms · tesela %s ms · avisos completos %s ms',
                                   v_nm, v_max_m, v_s -> 'resumen' ->> 'zonas', v_s -> 'resumen' ->> 'contratos', v_ms_v, v_ms_t, v_ms_a);
  v_info := format('TIEMPOS de la simulación sobre la red de esta base (%s tramos en operación, %s contratos con tramo): máximo %s ms%s',
                   (select count(*) from redes.activo_vigente_mat where sistema = 'acueducto' and prefijo in ('RED', 'CON') and cuenta_vigente and not retirado),
                   (select count(*) from redes.contrato_tramo), v_max, v_tiempos);
  perform pg_temp.reg('07.01 TIEMPOS: ' || coalesce(v_n, 0) || ' simulaciones sobre la red real (' || v_peq || ' con sector pequeño y «si no cierra»), cada una en menos de 5 s (el tope de la Edge es 30 s)',
     v_n >= 1 and v_max < 5000, v_info);
  perform pg_temp.reg('07.03 TIEMPOS del cierre real con la red real: cada maniobra (con su foto) en menos de 5 s; cortes vigentes, tesela y avisos en menos de 1 s',
     v_nm >= 1 and v_max_m < 5000 and v_ms_v < 1000 and v_ms_t < 1000 and v_ms_a < 1000, v_info);
  perform pg_temp.reg('07.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 9b, Fase 1 (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
