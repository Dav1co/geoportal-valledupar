-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · CORRECCIÓN «LA VÁLVULA QUE CERRÓ EL OPERADOR» · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 26 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes9b.*; el operador de daños NO tiene la casilla del geovisor), la red de prueba ZT9B
-- (en un rincón de la caja), sus contratos (99999…), un daño y una intervención, y hace los cierres con las RPC publicadas.
-- Mide la lectura nueva con 20.000 maniobras de relleno y FALLA si pasa de 1 s.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 9b, la válvula que cerró el operador … RESULTADO: N de N pruebas correctas — SIN FALLAS
-- =====================================================================
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
  v_carga bigint; j jsonb; j2 jsonb; v_p jsonb; v_dan text; v_dan2 text; v_itv text; v_md5 text; v_aud bigint; v_man bigint; v_n integer;
  v_t0 timestamptz; v_ms numeric; v_ms2 numeric; v_info text := ''; v_total integer; v_bien integer; v_fallas text;
begin
  -- ---------- personas de prueba: el operador de daños (op) NO tiene la casilla del geovisor ----------
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9B Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT9B Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values
    (op, 'ZT9B Operador daños', 'consulta', true, 'sin_restriccion', 'todos'), (op2, 'ZT9B Operador mantenimiento', 'consulta', true, 'sin_restriccion', 'todos'),
    (op3, 'ZT9B Otro operador daños', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT9B Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values
    (op, 'asignar_formulario', 'danos_fallas', a), (op2, 'asignar_formulario', 'mantenimiento', a), (op3, 'asignar_formulario', 'danos_fallas', a);
  v_md5 := md5(pg_get_functiondef('public.geoportal_redes_cortes_vigentes(text)'::regprocedure)) || md5(pg_get_functiondef('public.geoportal_redes_valvula_maniobra(text,text,text,text,text,text,text)'::regprocedure))
           || md5(pg_get_functiondef('redes.f_geovisor_lectura(text)'::regprocedure));

  -- ---------- la red de prueba: F —T1— A —T2— V1 —T3— B —T4— V2 —T5— C —T6— V3 —T7— D, con un segundo tanque en C ----------
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
  values ('acueducto', md5('zt9v-a') || md5('zt9v-b'), 'shp', 4326, 'ID', 1, 'ZT9B red de prueba', a) returning id into v_carga;
  perform pg_temp.nodo('F', 0, 0, v_carga, 'TAN');
  perform pg_temp.nodo('A', 100, 0, v_carga);
  perform pg_temp.nodo('V1', 200, 0, v_carga, 'VAL', 'cierre', 'cierra');
  perform pg_temp.nodo('B', 300, 0, v_carga);
  perform pg_temp.nodo('V2', 400, 0, v_carga, 'VAL', 'cierre', 'sin_definir');
  perform pg_temp.nodo('C', 500, 0, v_carga);
  perform pg_temp.nodo('V3', 600, 0, v_carga, 'VAL', 'cierre', 'cierra');
  perform pg_temp.nodo('D', 700, 0, v_carga);
  perform pg_temp.nodo('V4', 300, 100, v_carga, 'VAL', 'cierre', 'cierra');
  perform pg_temp.nodo('E', 300, 200, v_carga);
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
  perform pg_temp.tramo('T13', 'C', 'F2', v_carga, 0);

  -- ---------- un daño del operador (v_dan), otro del otro operador (v_dan2) y una intervención del supervisor (v_itv), sobre T4 ----------
  v_p := public.geoportal_redes_preparar_dano(op, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_dan := public.geoportal_redes_crear_dano(op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           'activo', pg_temp.cod('T4'), 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(350),
           't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
           'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
  v_p := public.geoportal_redes_preparar_dano(op3, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_dan2 := public.geoportal_redes_crear_dano(op3, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           'activo', pg_temp.cod('T8'), 'lat', pg_temp.lat(50), 'lon', pg_temp.lon(300),
           't_detectado', pg_temp.iso('-15 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
           'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
  v_p := public.geoportal_redes_preparar_intervencion(sd, 1, 0);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_itv := public.geoportal_redes_crear_intervencion(sd, (v_p ->> 'intervencion_id')::uuid, jsonb_build_object('nace_de', 'programada', 'tipo', 'preventivo', 'sistema', 'acueducto',
         'activo', pg_temp.cod('T4'), 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(350), 'precision_m', 5, 'ubicacion_origen', 'gps', 't_inicio', pg_temp.iso('-50 minutes'), 't_fin', pg_temp.iso('-10 minutes'),
         'descripcion', 'ZT9B cambio de válvula programado', 'materiales', '[]'::jsonb, 'ejecutor', 'emdupar', 'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')),
         'archivos', jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'despues', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';

  -- ===================== 01. Estructura =====================
  perform pg_temp.reg('01.01 la RPC nueva: security definer, solo service_role (ni anon ni authenticated ni public)',
     (select p.prosecdef and p.proconfig is not null and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0) from pg_proc p where p.oid = 'public.geoportal_redes_cierres_registro(text,text)'::regprocedure)
     and has_function_privilege('service_role', 'public.geoportal_redes_cierres_registro(text,text)', 'execute')
     and not has_function_privilege('authenticated', 'public.geoportal_redes_cierres_registro(text,text)', 'execute')
     and not has_function_privilege('anon', 'public.geoportal_redes_cierres_registro(text,text)', 'execute'));
  perform pg_temp.reg('01.02 el operador de la prueba NO tiene el geovisor (ni la casilla ni un dashboard) y sí su formulario de daños y fallas',
     not redes.f_geovisor_lectura(op) and redes.f_puede_formulario(op, 'danos_fallas') and not redes.f_puede_formulario(op, 'mantenimiento')
     and not coalesce((select geovisor from redes.v_personal_ficha where persona = op), false));

  -- ===================== 02. El hallazgo: cierra desde su daño, sin el geovisor =====================
  j := public.geoportal_redes_cierres_registro(op, v_dan);
  perform pg_temp.reg('02.01 antes de cerrar: su daño no tiene válvulas cerradas (lista vacía) y dice que puede abrir',
     j ->> 'registro' = v_dan and jsonb_array_length(j -> 'valvulas') = 0 and (j ->> 'puede_abrir')::boolean, j::text);
  j2 := public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V1'), 'cerrar', v_dan, null, null, pg_temp.iso('3 hours'));
  perform pg_temp.reg('02.02 el operador sin geovisor cierra V1 desde su daño: el cierre queda guardado (como en producción)',
     j2 ->> 'estado' = 'cerrada' and (select m.autor = op and m.dano_id = (select id from redes.danos where codigo = v_dan) from redes.valvula_maniobras m where m.id = (j2 ->> 'maniobra')::bigint), j2::text);
  perform pg_temp.err('02.03 LA CAUSA: lo que leía el panel (cortes vigentes, del geovisor) se le niega: 42501 «Sin el geovisor técnico»',
     format('select public.geoportal_redes_cortes_vigentes(%L)', op), '42501', 'Sin el geovisor');
  j := public.geoportal_redes_cierres_registro(op, v_dan);
  perform pg_temp.reg('02.04 LA CORRECCIÓN: la lectura por registro le muestra V1 cerrada por su daño, con desde cuándo, quién (nombre del funcionario) y el regreso estimado; puede abrir',
     jsonb_array_length(j -> 'valvulas') = 1 and j -> 'valvulas' -> 0 ->> 'codigo' = pg_temp.cod('V1') and j -> 'valvulas' -> 0 ->> 'registro' = v_dan
     and (j -> 'valvulas' -> 0 ->> 'desde')::timestamptz = (j2 ->> 'hecho_en')::timestamptz and j -> 'valvulas' -> 0 ->> 'quien' = 'ZT9B Operador daños'
     and (j -> 'valvulas' -> 0 ->> 'regreso_estimado')::timestamptz > clock_timestamp() + interval '2 hours' and (j ->> 'puede_abrir')::boolean, j::text);
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V2'), 'cerrar', v_dan, null, pg_temp.iso('-5 minutes'));
  j := public.geoportal_redes_cierres_registro(op, v_dan);
  perform pg_temp.reg('02.05 cierra V2 (hecho hace 5 minutos): ahora son 2, ordenadas por la hora del cierre (V2 primero); sin regreso estimado en V2',
     jsonb_array_length(j -> 'valvulas') = 2 and j -> 'valvulas' -> 0 ->> 'codigo' = pg_temp.cod('V2') and j -> 'valvulas' -> 1 ->> 'codigo' = pg_temp.cod('V1')
     and j -> 'valvulas' -> 0 ->> 'regreso_estimado' is null, j::text);
  j2 := public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V1'), 'abrir');
  j := public.geoportal_redes_cierres_registro(op, v_dan);
  perform pg_temp.reg('02.06 el operador sin geovisor ABRE V1 (la maniobra ya lo dejaba): sale de la lista y queda V2',
     j2 ->> 'estado' = 'abierta' and jsonb_array_length(j -> 'valvulas') = 1 and j -> 'valvulas' -> 0 ->> 'codigo' = pg_temp.cod('V2'), j::text);
  perform public.geoportal_redes_corte_regreso(op, pg_temp.cod('V2'), pg_temp.iso('6 hours'));
  j := public.geoportal_redes_cierres_registro(op, v_dan);
  perform pg_temp.reg('02.07 si quien cerró ajusta la hora de regreso de V2, la lectura trae la hora ajustada',
     (j -> 'valvulas' -> 0 ->> 'regreso_estimado')::timestamptz > clock_timestamp() + interval '5 hours', j::text);

  -- ===================== 03. Solo las de ESE registro (no es el geovisor) =====================
  perform public.geoportal_redes_valvula_maniobra(sd, pg_temp.cod('V3'), 'cerrar', v_itv, null, null, pg_temp.iso('5 hours'));
  perform public.geoportal_redes_valvula_maniobra(op3, pg_temp.cod('V4'), 'cerrar', v_dan2);
  j := public.geoportal_redes_cierres_registro(op, v_dan);
  perform pg_temp.reg('03.01 con otras válvulas cerradas por una intervención (V3) y por el daño de otro operador (V4), su daño sigue mostrando solo la suya (V2)',
     jsonb_array_length(j -> 'valvulas') = 1 and j -> 'valvulas' -> 0 ->> 'codigo' = pg_temp.cod('V2') and (select count(*) from redes.f_cierres_vigentes()) = 3, j::text);
  perform pg_temp.reg('03.02 la respuesta no trae zonas, conteos de contratos, coordenadas ni correos: solo registro, puede_abrir y las válvulas',
     (select array_agg(k order by k) from jsonb_object_keys(j) k) = array['puede_abrir', 'registro', 'valvulas']
     and (select array_agg(k order by k) from jsonb_object_keys(j -> 'valvulas' -> 0) k) = array['codigo', 'desde', 'nombre', 'quien', 'registro', 'regreso_estimado']
     and j::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n|contrato|@emdupar', j::text);
  j := public.geoportal_redes_cierres_registro(op, v_itv);
  perform pg_temp.reg('03.03 el operador de daños lee la intervención: ve V3 cerrada, pero «puede_abrir» es falso (abrirla pide el formulario de mantenimiento)',
     jsonb_array_length(j -> 'valvulas') = 1 and j -> 'valvulas' -> 0 ->> 'codigo' = pg_temp.cod('V3') and j -> 'valvulas' -> 0 ->> 'quien' = 'ZT9B Supervisor de distribución'
     and not (j ->> 'puede_abrir')::boolean, j::text);
  perform pg_temp.err('03.04 … y la maniobra dice lo mismo: el operador de daños no abre la válvula de la intervención (42501)',
     format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L)', op, pg_temp.cod('V3'), 'abrir'), '42501');
  j := public.geoportal_redes_cierres_registro(op2, v_dan);
  perform pg_temp.reg('03.05 el operador de mantenimiento lee el daño: ve V2 cerrada y «puede_abrir» es falso',
     jsonb_array_length(j -> 'valvulas') = 1 and not (j ->> 'puede_abrir')::boolean, j::text);
  perform pg_temp.err('03.06 … y la maniobra dice lo mismo: no abre la válvula del daño (42501)', format('select public.geoportal_redes_valvula_maniobra(%L, %L, %L)', op2, pg_temp.cod('V2'), 'abrir'), '42501');
  perform pg_temp.reg('03.07 el operador de mantenimiento sí puede abrir la de la intervención; el supervisor y el administrador, las dos',
     (public.geoportal_redes_cierres_registro(op2, v_itv) ->> 'puede_abrir')::boolean
     and (public.geoportal_redes_cierres_registro(sd, v_dan) ->> 'puede_abrir')::boolean and (public.geoportal_redes_cierres_registro(sd, v_itv) ->> 'puede_abrir')::boolean
     and (public.geoportal_redes_cierres_registro(a, v_dan) ->> 'puede_abrir')::boolean and (public.geoportal_redes_cierres_registro(a, v_itv) ->> 'puede_abrir')::boolean
     and jsonb_array_length(public.geoportal_redes_cierres_registro(sd, v_dan) -> 'valvulas') = 1);
  perform public.geoportal_redes_valvula_maniobra(sd, pg_temp.cod('V1'), 'cerrar', null, 'ZT9B maniobra del supervisor sin registro');
  perform pg_temp.reg('03.08 una válvula que el supervisor cierra sin daño ni intervención no aparece en ningún registro',
     jsonb_array_length(public.geoportal_redes_cierres_registro(op, v_dan) -> 'valvulas') = 1 and jsonb_array_length(public.geoportal_redes_cierres_registro(sd, v_itv) -> 'valvulas') = 1
     and jsonb_array_length(public.geoportal_redes_cierres_registro(op3, v_dan2) -> 'valvulas') = 1);
  j := public.geoportal_redes_cierres_registro(op3, v_dan);
  j2 := public.geoportal_redes_valvula_maniobra(op3, pg_temp.cod('V2'), 'abrir');
  perform pg_temp.reg('03.09 otro operador de daños (el compañero que llega a reparar) ve V2 cerrada, «puede_abrir» es cierto y la maniobra se lo confirma: la abre',
     jsonb_array_length(j -> 'valvulas') = 1 and (j ->> 'puede_abrir')::boolean and j2 ->> 'estado' = 'abierta'
     and jsonb_array_length(public.geoportal_redes_cierres_registro(op, v_dan) -> 'valvulas') = 0);

  -- ===================== 04. Quién y errores =====================
  perform pg_temp.err('04.01 alguien sin Técnica no lee (42501)', format('select public.geoportal_redes_cierres_registro(%L, %L)', na, v_dan), '42501');
  perform pg_temp.err('04.02 sin solicitante: 28000', format('select public.geoportal_redes_cierres_registro(%L, %L)', '', v_dan), '28000');
  perform pg_temp.err('04.03 un código que no es de daño ni de intervención', format('select public.geoportal_redes_cierres_registro(%L, %L)', op, 'VAL-000001'), '22023', 'Escriba el código');
  perform pg_temp.err('04.04 sin código', format('select public.geoportal_redes_cierres_registro(%L, null)', op), '22023', 'Escriba el código');
  perform pg_temp.err('04.05 un daño que no existe: P0002', format('select public.geoportal_redes_cierres_registro(%L, %L)', op, 'DAN-999999'), 'P0002');
  perform pg_temp.reg('04.06 acepta el código en minúsculas y con espacios', public.geoportal_redes_cierres_registro(op, '  ' || lower(v_itv) || ' ') ->> 'registro' = v_itv);

  -- ===================== 05. No da el geovisor ni toca lo publicado =====================
  perform pg_temp.reg('05.01 después de todo, el operador sigue SIN el geovisor: ni los cortes vigentes ni la configuración del geovisor',
     not redes.f_geovisor_lectura(op) and not coalesce((select geovisor from redes.v_personal_ficha where persona = op), false));
  perform pg_temp.err('05.02 … la configuración del geovisor se le sigue negando (42501)', format('select public.geoportal_redes_geovisor(%L)', op), '42501');
  perform pg_temp.err('05.03 … y la tesela del modo «Afectaciones», también (42501)', format('select public.geoportal_redes_geovisor_mvt_cortes(%L, 16, 0, 0)', op), '42501');
  perform pg_temp.reg('05.04 los cortes vigentes del geovisor, la maniobra y el acceso al geovisor conservan su texto (no se reemplazó nada)',
     v_md5 = md5(pg_get_functiondef('public.geoportal_redes_cortes_vigentes(text)'::regprocedure)) || md5(pg_get_functiondef('public.geoportal_redes_valvula_maniobra(text,text,text,text,text,text,text)'::regprocedure))
           || md5(pg_get_functiondef('redes.f_geovisor_lectura(text)'::regprocedure)));
  select count(*) into v_aud from public.geoportal_auditoria; select count(*) into v_man from redes.valvula_maniobras;
  perform public.geoportal_redes_cierres_registro(op, v_dan); perform public.geoportal_redes_cierres_registro(sd, v_itv);
  perform pg_temp.reg('05.05 leer no escribe: ni una maniobra ni una fila de auditoría',
     (select count(*) from public.geoportal_auditoria) = v_aud and (select count(*) from redes.valvula_maniobras) = v_man);
  perform pg_temp.reg('05.06 el supervisor sigue viendo todo en el geovisor: 3 válvulas cerradas (V3 por la intervención, V4 por el otro daño y V1 por su maniobra)',
     jsonb_array_length(public.geoportal_redes_cortes_vigentes(sd) -> 'valvulas') = 3);

  -- ===================== 06. Tiempos con muchas maniobras, y pg-safeupdate =====================
  with c as (
    insert into redes.valvula_maniobras (valvula_id, tipo, motivo, hecho_en, autor)
    select pg_temp.id('V1'), 'cerrar', 'ZT9B relleno para medir tiempos', clock_timestamp() - interval '40 days' + make_interval(secs => i), a from generate_series(1, 10000) i
    returning id, hecho_en)
  insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, hecho_en, autor) select pg_temp.id('V1'), 'abrir', c.id, c.hecho_en + interval '1 second', a from c;
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V2'), 'cerrar', v_dan);
  select count(*) into v_n from redes.valvula_maniobras;
  v_t0 := clock_timestamp(); j := public.geoportal_redes_cierres_registro(op, v_dan); v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp(); j2 := public.geoportal_redes_cierres_registro(sd, v_itv); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_info := format('TIEMPOS (con %s maniobras en la tabla): las válvulas cerradas de un daño %s ms · las de una intervención %s ms', v_n, v_ms, v_ms2);
  perform pg_temp.reg('06.01 TIEMPOS: con más de 20.000 maniobras, cada lectura en menos de 1 s, y sigue dando lo suyo (V2 en el daño, V3 en la intervención)',
     greatest(v_ms, v_ms2) < 1000 and v_n > 20000 and jsonb_array_length(j -> 'valvulas') = 1 and j -> 'valvulas' -> 0 ->> 'codigo' = pg_temp.cod('V2')
     and jsonb_array_length(j2 -> 'valvulas') = 1 and j2 -> 'valvulas' -> 0 ->> 'codigo' = pg_temp.cod('V3'), v_info);
  perform pg_temp.reg('06.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 9b, la válvula que cerró el operador (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
