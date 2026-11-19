-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes9b.*), tres sectores de prueba y su red ZT9B (en un rincón de la caja), sus contratos
-- (99999…), dos usuarios sensibles confirmados, reportes del bot, de la línea 116, daños y reportes del formato de campo, y los eventos con las RPC del corte.
-- Publica cargas REALES de la línea 116 por el motor del Cargue (iniciar, lotes, resumen, publicar) sobre reportes que cerró un evento.
-- Mide con volumen: la zona grande cubre la red real de la base (todos sus contratos), 300 eventos viejos y una carga de 5.000 reportes de la 116.
-- FALLA si la asociación de un reporte, declarar, cerrar o los avisos pasan de 1 s. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 15, evento de suspensión … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- ---------- ayudantes del Corte 15 ----------
create temp table _c15 (carga bigint);
create function pg_temp.poli(x1 numeric, y1 numeric, x2 numeric, y2 numeric) returns geometry language sql as $$
  select ST_SetSRID(ST_MakeEnvelope(pg_temp.lon(x1), pg_temp.lat(y1), pg_temp.lon(x2), pg_temp.lat(y2)), 4326) $$;
-- un reporte del bot en (x, y), por la función nueva; devuelve lo que recibiría el bot
create function pg_temp.bot(p_rad text, x numeric, y numeric, p_tipo text default 'sin_agua', p_cuando interval default '0') returns jsonb language sql as $$
  select redes.f_reporte_externo_recibir_evento(jsonb_build_object('radicado', p_rad, 'canal', 'telegram', 'tipo', p_tipo, 'lat', pg_temp.lat(y), 'lon', pg_temp.lon(x),
           'recibido_en', clock_timestamp() + p_cuando)) $$;
create function pg_temp.ebot(p_rad text) returns text language sql as $$ select v.estado_bot from redes.v_reporte_externo v where v.radicado = p_rad $$;
create function pg_temp.idbot(p_rad text) returns text language sql as $$ select r.id::text from redes.reportes_externos r where r.radicado = p_rad $$;
-- un reporte de la línea 116, como lo deja la publicación de una carga (reporte, su «alta» con el punto del contrato, y la fila vigente)
create function pg_temp.l116(p_num bigint, x numeric, y numeric, p_causal text default 'Sin servicio de agua', p_estado text default 'registrado', p_cuando interval default '0') returns bigint
language plpgsql as $$
declare v_id bigint; v_f timestamptz := clock_timestamp() + p_cuando; v_c bigint := (select carga from _c15);
begin
  insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, carga_id) values (p_num, v_f, 'Acueducto', p_causal, v_c) returning id into v_id;
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, carga_id, motivo, autor)
  values (v_id, 'alta', p_estado, 'contrato', pg_temp.pt(x, y), v_c, 'ZT9B carga de prueba', 'prueba.redes9b.adm@emdupar.gov.co');
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, estado, estado_desde, metodo, geom)
  values (v_id, p_num, v_f, (v_f at time zone 'America/Bogota')::date, 'Acueducto', p_causal, p_estado, v_f, 'contrato', pg_temp.pt(x, y));
  return v_id;
end $$;
-- un daño por formulario sobre un tramo de prueba, en (x, y); devuelve su código
create function pg_temp.dano(p_quien text, p_tramo text, x numeric, y numeric, p_tipo text default 'fuga', p_cuando interval default '-5 minutes') returns text language plpgsql as $$
declare v_p jsonb;
begin
  v_p := public.geoportal_redes_preparar_dano(p_quien, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  return public.geoportal_redes_crear_dano(p_quien, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', p_tipo, 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           'activo', pg_temp.cod(p_tramo), 'lat', pg_temp.lat(y), 'lon', pg_temp.lon(x), 't_detectado', pg_temp.iso(p_cuando), 'tipo_rotura', 'parcial', 'riesgo', 'medio',
           'causa_clase', 'desconocida', 'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
end $$;
-- un reporte del formato de campo en (x, y), como lo deja geoportal_campo_crear_reporte (la fila en campo.reportes; nulo en «area» = hecho desde Comercial)
create function pg_temp.campo(x numeric, y numeric, p_tipo text default 'sin_agua', p_cuando interval default '0') returns uuid language sql as $$
  insert into campo.reportes (id, tipo_id, lat, lon, origen, autor, registrado_en)
  select gen_random_uuid(), t.id, pg_temp.lat(y), pg_temp.lon(x), 'campo', 'prueba.redes9b.comercial@emdupar.gov.co', clock_timestamp() + p_cuando from campo.tipos_reporte t where t.codigo = p_tipo
  returning id $$;
create function pg_temp.ecampo(p_id uuid) returns text language sql as $$ select v.estado from campo.v_reportes_estado v where v.id = p_id $$;
create function pg_temp.codcampo(p_id uuid) returns text language sql as $$ select 'REP-' || lpad(c.seq::text, 6, '0') from campo.reportes c where c.id = p_id $$;
-- una fila de un archivo de la línea 116 y la subida por el motor del Cargue (como la pantalla: iniciar y lotes de 200); devuelve la carga
create function pg_temp.fila116(p_orden integer, p_rep bigint, p_estado text, p_causal text default 'Sin servicio de agua') returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', null, 'atributos', jsonb_build_object('REPORTE', p_rep, 'ESTADO', p_estado,
           'FECHA_REGISTRO', to_char((clock_timestamp() at time zone 'America/Bogota') - interval '2 minutes', 'YYYY-MM-DD HH24:MI:SS'), 'CONTRATO', '0',
           'DIRECCION', 'CL ZT9B 1 2 3', 'BARRIO', 'ZT9B BARRIO', 'COMUNA', 'COMUNA 5', 'DESC_CAUSAL', p_causal, 'SERVICIO', 'Acueducto')) $$;
create function pg_temp.subir116(p_sd text, p_filas jsonb, p_sha text) returns bigint language plpgsql as $$
declare v_c bigint; k integer := 0; n integer := jsonb_array_length(p_filas);
begin
  v_c := (public.geoportal_redes_cargue_iniciar(p_sd, 'linea_116', md5(p_sha) || md5(p_sha || 'b'), 'xlsx', 4326, 'reporte', n, 'ZT9B archivo de prueba') ->> 'carga_id')::bigint;
  while k < n loop
    perform public.geoportal_redes_carga_lote(p_sd, v_c, (select jsonb_agg(e order by o) from jsonb_array_elements(p_filas) with ordinality x(e, o) where o > k and o <= k + 200));
    k := k + 200;
  end loop;
  return v_c;
end $$;
create function pg_temp.h116(p_rep bigint) returns text[] language sql as $$
  select array_agg(e.tipo || ':' || coalesce(e.estado, '-') || ':' || coalesce(e.estado_antes, '-') order by e.id) from redes.l116_eventos e join redes.l116_reportes r on r.id = e.reporte_id where r.reporte = p_rep $$;
-- a qué evento ABIERTO está asociado hoy un reporte (o nulo)
create function pg_temp.en(p_origen text, p_ref text) returns text language sql as $$
  select e.codigo from redes.f_eventos_abiertos() e join lateral redes.f_evento_reportes(e.id) r on true where r.origen = p_origen and r.ref = p_ref $$;
create function pg_temp.iddano(p_cod text) returns text language sql as $$ select d.id::text from redes.danos d where d.codigo = p_cod $$;
create function pg_temp.aviso(p jsonb, p_clave text) returns jsonb language sql as $$ select x from jsonb_array_elements(p) x where x ->> 'clave' like p_clave limit 1 $$;

do $prueba$
declare
  a text := 'prueba.redes9b.adm@emdupar.gov.co'; sd text := 'prueba.redes9b.dist@emdupar.gov.co'; sp text := 'prueba.redes9b.planta@emdupar.gov.co';
  op text := 'prueba.redes9b.op@emdupar.gov.co'; na text := 'prueba.redes9b.nada@emdupar.gov.co';
  v_carga bigint; j jsonb; j2 jsonb; v_e1 text; v_e2 text; v_e3 text; v_e4 text; v_d1 text; v_d2 text; v_d3 text; v_d4 text; v_md5 text; v_txt text; v_num integer; v_num2 integer; v_id bigint;
  v_c1 text; v_c2 text; v_c3 text; v_reales integer; v_gran text; v_t0 timestamptz; v_ms numeric; v_ms_bot numeric; v_ms_dano numeric; v_ms_116 numeric; v_ms_decl numeric; v_ms_cerrar numeric;
  v_ms_av numeric; v_ms_vp numeric; v_ms_det numeric; v_info text := ''; v_total integer; v_bien integer; v_fallas text; v_av jsonb; v_caja geometry;
  ca1 uuid; ca2 uuid; ca3 uuid; ca4 uuid; ca5 uuid; v_e5 text; v_e6 text; v_cg bigint; v_x jsonb; v_r jsonb; v_ts timestamptz; v_ms_pub numeric; v_ms_campo numeric;
begin
  -- ---------- personas de prueba ----------
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9B Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT9B Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZT9B Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT9B Operador daños', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT9B Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);
  v_md5 := md5(pg_get_functiondef('redes.f_reporte_externo_recibir(jsonb)'::regprocedure)) || md5(pg_get_functiondef('public.geoportal_redes_crear_dano(text,uuid,jsonb,text)'::regprocedure));

  -- ---------- tres sectores de prueba y su red: S1 (con el subsector S1A adentro) y S2, lejos de la red real ----------
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
  values ('acueducto', md5('zt15-a') || md5('zt15-b'), 'shp', 4326, 'ID', 1, 'ZT9B red de prueba', a) returning id into v_carga;
  insert into _c15 values (v_carga);
  insert into _zt select 'S1', pg_temp.activo('Sector S1', 'SEC', pg_temp.poli(0, -50, 400, 250), 'sector'), null, 200, 100;
  insert into _zt select 'S1A', pg_temp.activo('Subsector S1A', 'SEC', pg_temp.poli(0, -50, 200, 250), 'subsector'), null, 100, 100;
  insert into _zt select 'S2', pg_temp.activo('Sector S2', 'SEC', pg_temp.poli(500, -50, 900, 250), 'sector'), null, 700, 100;
  perform pg_temp.nodo('A', 50, 0, v_carga); perform pg_temp.nodo('B', 150, 0, v_carga); perform pg_temp.nodo('C', 350, 0, v_carga);
  perform pg_temp.nodo('D', 550, 0, v_carga); perform pg_temp.nodo('E', 750, 0, v_carga);
  perform pg_temp.tramo('T1', 'A', 'B', v_carga, 3);      -- en S1 (y en S1A)
  perform pg_temp.tramo('T2', 'B', 'C', v_carga, 2);      -- en S1
  perform pg_temp.tramo('T3', 'D', 'E', v_carga, 4);      -- en S2
  select min(contrato) into v_c1 from redes.contrato_tramo where activo_id = pg_temp.id('T1');
  select min(contrato) into v_c2 from redes.contrato_tramo where activo_id = pg_temp.id('T2');
  select min(contrato) into v_c3 from redes.contrato_tramo where activo_id = pg_temp.id('T3');
  -- usuarios sensibles: uno CONFIRMADO en S1, uno confirmado en S2 y uno solo propuesto en S1 (no cuenta)
  insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor) values (v_c1, 'hospital', null, 'manual', a), (v_c3, 'colegio', null, 'manual', a), (v_c2, 'clinica', null, 'manual', a);
  insert into redes.usuario_sensible_eventos (contrato, accion, tipo, motivo, autor) values (v_c1, 'confirmar', 'hospital', 'ZT9B sensible de prueba', a), (v_c3, 'confirmar', 'colegio', 'ZT9B sensible de prueba', a);
  select count(*) into v_reales from redes.contrato_tramo;

  -- ===================== 01. Estructura =====================
  perform pg_temp.reg('01.01 las 7 tablas con RLS y sin permisos para la API; las 13 RPC solo para service_role; las internas (y la del bot), para nadie de la API',
     (select count(*) from pg_class c where c.relnamespace = 'redes'::regnamespace and c.relrowsecurity and c.relname in ('eventos_suspension', 'evento_suspension_eventos', 'evento_suspension_reportes',
             'evento_tipos_asociables', 'evento_tipo_eventos', 'planta_sectores', 'planta_sector_eventos') and not has_table_privilege('service_role', c.oid, 'select')) = 7
     and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\_redes\_evento%' or p.proname = 'geoportal_redes_planta_sectores_fijar')
             and p.prosecdef and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')) = 13
     and not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and has_function_privilege('service_role', p.oid, 'execute')));
  perform pg_temp.reg('01.02 el tipo «sin_agua» quedó activo en el catálogo de campo (grupo red_acueducto) y en la lista de lo que se asocia; lo que había en el catálogo no cambió',
     (select t.activo and t.nombre = 'No tengo agua o tengo baja presión' and g.codigo = 'red_acueducto' from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id where t.codigo = 'sin_agua')
     and (select count(*) from campo.tipos_reporte where codigo <> 'sin_agua') = 2
     and (select count(*) = 2 and bool_and(clase = 'sin_agua' and asocia) from redes.evento_tipos_asociables where origen in ('bot', 'campo') and codigo = 'sin_agua'));
  perform pg_temp.reg('01.03 la lista por omisión: 4 causales de la 116 son «sin agua» (sin servicio, poca presión, deficiencia, no llega) y 5 son daño en la red; del bot, 2; de daños, 3 (fuga, bombeo y eléctrica); del formato de campo, 1',
     (select count(*) filter (where origen = 'l116' and clase = 'sin_agua') = 4 and count(*) filter (where origen = 'l116' and clase = 'dano_red') = 5
             and count(*) filter (where origen = 'bot') = 2 and count(*) filter (where origen = 'dano' and codigo in ('fuga', 'bombeo', 'electrica')) = 3
             and count(*) filter (where origen = 'dano') = 3 and count(*) filter (where origen = 'campo') = 1 and bool_and(asocia) from redes.evento_tipos_asociables));
  perform pg_temp.reg('01.04 los 4 disparadores de la asociación están puestos (bot, línea 116, daños y formato de campo); campo.reportes conserva los suyos',
     (select count(*) from pg_trigger t where t.tgname = 't_evento_asociar' and t.tgrelid in ('redes.reporte_externo_eventos'::regclass, 'redes.l116_eventos'::regclass, 'redes.danos'::regclass, 'campo.reportes'::regclass)) = 4
     and (select count(*) from pg_trigger t where t.tgrelid = 'campo.reportes'::regclass and not t.tgisinternal and t.tgname in ('t_reporte_coherente', 't_solo_agregar', 't_solo_agregar_trunc')) = 3);

  -- ===================== 02. Sin eventos, todo sigue como antes; el «sin agua» suelto se avisa =====================
  j := pg_temp.bot('ZT15-0001', 100, 10, 'sin_agua', '-10 minutes');      -- en S1
  perform pg_temp.reg('02.01 sin eventos abiertos, un «sin agua» del bot entra como siempre («Recibido») y al bot no se le dice nada de un corte',
     pg_temp.ebot('ZT15-0001') = 'recibido' and j ->> 'evento' is null and j ->> 'mensaje' is null and j ->> 'radicado' = 'ZT15-0001' and j ->> 'id' = pg_temp.idbot('ZT15-0001'), j::text);
  perform pg_temp.l116(990000001, 120, 20, 'Sin servicio de agua', 'registrado', '-8 minutes');      -- en S1
  perform pg_temp.l116(990000002, 600, 20, 'Poca presión  de AGUA', 'registrado', '-8 minutes');      -- en S2 (la causal con otro uso de mayúsculas y espacios)
  perform pg_temp.l116(990000003, 130, 20, 'Fuga en el medidor', 'registrado', '-8 minutes');      -- en S1, pero no es de los que se asocian
  v_d1 := pg_temp.dano(op, 'T1', 100, 0, 'fuga', '-6 minutes');      -- en S1
  perform pg_temp.bot('ZT15-0002', 110, 10, 'tapa_caja_acueducto', '-9 minutes');      -- en S1, tipo que no se asocia
  perform pg_temp.bot('ZT15-0003', 105, 10, 'sin_agua', '-3 hours');      -- en S1, pero de antes del evento
  ca1 := pg_temp.campo(150, 30, 'sin_agua', '-7 minutes');      -- formato de campo, hecho desde Comercial, en S1
  ca3 := pg_temp.campo(800, 200, 'sin_agua', '-7 minutes');      -- en S2
  perform pg_temp.reg('02.01b sin eventos abiertos, un «sin agua» del formato de campo (Comercial) se guarda como siempre: «Reportado», sin hechos ni asociación',
     pg_temp.ecampo(ca1) = 'reportado' and not exists (select 1 from campo.reporte_eventos) and not exists (select 1 from redes.evento_suspension_reportes));
  v_av := tecnica.f_avisos(false, true);
  perform pg_temp.reg('02.02 AVISO: los «sin agua» que no están en ningún evento salen en UN aviso al supervisor de distribución (2 del bot, 2 de la 116 y 2 del formato de campo), no uno por reporte',
     (pg_temp.aviso(v_av, 'sin_agua_sin_evento') ->> 'n')::integer = 6 and pg_temp.aviso(v_av, 'sin_agua_sin_evento') ->> 'nivel' = 'naranja'
     and pg_temp.aviso(v_av, 'sin_agua_sin_evento') ->> 'titulo' = '6 reportes de falta de agua sin evento' and jsonb_array_length(pg_temp.aviso(v_av, 'sin_agua_sin_evento') -> 'items') = 5
     and pg_temp.aviso(v_av, 'sin_agua_sin_evento') -> 'items' @> to_jsonb(array['Formato de campo · ' || pg_temp.codcampo(ca1)])
     and pg_temp.aviso(v_av, 'evento_suspension_%') is null, pg_temp.aviso(v_av, 'sin_agua_sin_evento')::text);
  perform pg_temp.reg('02.03 … al supervisor de planta no le sale', pg_temp.aviso(tecnica.f_avisos(true, false), 'sin_agua_sin_evento') is null);

  -- ===================== 03. Quién puede; el catálogo; la vista previa =====================
  j := public.geoportal_redes_evento_catalogo(sd);
  perform pg_temp.reg('03.01 el catálogo para el supervisor de distribución: puede zona y reportes, no total; trae los sectores de prueba, las 2 plantas (sin sectores) y los 15 tipos; los sectores dicen si son sector o subsector',
     (j -> 'puede' ->> 'zona')::boolean and (j -> 'puede' ->> 'reportes')::boolean and not (j -> 'puede' ->> 'total')::boolean
     and (select count(*) from jsonb_array_elements(j -> 'sectores') x where x ->> 'codigo' in (pg_temp.cod('S1'), pg_temp.cod('S1A'), pg_temp.cod('S2'))) = 3
     and jsonb_array_length(j -> 'plantas') = (select count(*) from tecnica.plantas where activa) and j -> 'plantas' -> 0 -> 'sectores' = '[]'::jsonb and jsonb_array_length(j -> 'tipos') = 15
     and (select x ->> 'clase' from jsonb_array_elements(j -> 'sectores') x where x ->> 'codigo' = pg_temp.cod('S1A')) = 'subsector'
     and (select x ->> 'clase' from jsonb_array_elements(j -> 'sectores') x where x ->> 'codigo' = pg_temp.cod('S1')) = 'sector', left(j::text, 500));
  j := public.geoportal_redes_evento_catalogo(sp);
  perform pg_temp.reg('03.02 … para el supervisor de planta: puede total, no zona ni reportes', (j -> 'puede' ->> 'total')::boolean and not (j -> 'puede' ->> 'zona')::boolean and not (j -> 'puede' ->> 'reportes')::boolean, (j -> 'puede')::text);
  perform pg_temp.err('03.03 el operador no ve el catálogo ni la lista de eventos (42501)', format('select public.geoportal_redes_evento_catalogo(%L)', op), '42501');
  perform pg_temp.err('03.04 … ni declara (42501)', format('select public.geoportal_redes_evento_declarar(%L, %L)', op, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba')), '42501');
  perform pg_temp.err('03.05 alguien sin Técnica no ve ni los eventos vigentes (42501); sin solicitante, 28000', format('select public.geoportal_redes_eventos_vigentes(%L)', na), '42501');
  perform pg_temp.err('03.06 … sin solicitante: 28000', 'select public.geoportal_redes_eventos_vigentes('''')', '28000');
  perform pg_temp.err('03.07 el supervisor de distribución no declara un evento total (42501)', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'total', 'total', 'ciudad', 'causa', 'ZT9B falla de planta')), '42501', 'supervisor de planta');
  perform pg_temp.err('03.08 el supervisor de planta no declara uno por sectores (42501)', format('select public.geoportal_redes_evento_declarar(%L, %L)', sp, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba')), '42501', 'supervisor de distribución');
  j := public.geoportal_redes_evento_vista_previa(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'desde', pg_temp.iso('-30 minutes')));
  perform pg_temp.reg('03.09 VISTA PREVIA de S1 desde hace 30 minutos: 5 contratos, 1 usuario sensible confirmado (el propuesto no cuenta) y 4 reportes que quedarían asociados (1 bot, 1 de la 116, 1 daño, 1 del formato de campo); trae la zona; no guarda',
     (j ->> 'contratos')::integer = 5 and (j ->> 'sensibles')::integer = 1 and j -> 'reportes' = jsonb_build_object('total', 4, 'bot', 1, 'l116', 1, 'danos', 1, 'campo', 1)
     and j -> 'zona_geojson' ->> 'type' = 'MultiPolygon' and j ->> 'ya_abierto' is null and j ->> 'zona' = 'ZT9B Sector S1' and not exists (select 1 from redes.eventos_suspension), j::text);

  -- ===================== 04. Declarar por sectores: asocia lo que ya estaba =====================
  perform pg_temp.err('04.01 sin causa', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')))), '22023', 'causa');
  perform pg_temp.err('04.02 un sector que no existe: P0002', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array('SEC-999999'), 'causa', 'ZT9B daño de prueba')), 'P0002');
  perform pg_temp.err('04.03 un dato que no corresponde', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba', 'autor', 'otro@emdupar.gov.co')), '22023', 'no corresponde');
  perform pg_temp.err('04.04 no puede empezar en el futuro', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba', 'desde', pg_temp.iso('2 hours'))), '22023', 'futuro');
  perform pg_temp.err('04.05 ni hace más de 72 horas', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba', 'desde', pg_temp.iso('-80 hours'))), '22023', '72');
  perform pg_temp.err('04.06 el regreso estimado debe ser después del inicio', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba', 'desde', pg_temp.iso('-30 minutes'), 'regreso', pg_temp.iso('-40 minutes'))), '22023', 'regreso');
  select count(*) into v_num from redes.dano_eventos;
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'Daño en la tubería matriz de la calle 44',
         'desde', pg_temp.iso('-30 minutes'), 'regreso', pg_temp.iso('3 hours')));
  v_e1 := j ->> 'codigo';
  perform pg_temp.reg('04.07 el supervisor de distribución DECLARA el evento por sectores (S1): código EVS-…, abierto, con su zona, 5 contratos, 1 sensible y quién lo declaró (nombre del funcionario)',
     v_e1 ~ '^EVS-[0-9]{6}$' and j ->> 'estado' = 'abierto' and j ->> 'alcance' = 'sectores' and j ->> 'zona' = 'ZT9B Sector S1' and (j ->> 'contratos')::integer = 5 and (j ->> 'sensibles')::integer = 1
     and j ->> 'declarado_por' = 'ZT9B Supervisor de distribución' and j -> 'sectores' = jsonb_build_array(pg_temp.cod('S1')) and j -> 'zona_geojson' ->> 'type' = 'MultiPolygon', j::text);
  perform pg_temp.reg('04.08 … la franja: «Sin agua en <zona> desde las <hora> por <causa>. Regreso estimado: <hora>»',
     j ->> 'franja' ~ '^Sin agua en ZT9B Sector S1 desde las [0-9]{2}/[0-9]{2}, [0-9]{1,2}:[0-9]{2} [ap]\. m\. por Daño en la tubería matriz de la calle 44\. Regreso estimado: [0-9]{2}/[0-9]{2}, [0-9]{1,2}:[0-9]{2} [ap]\. m\.$', j ->> 'franja');
  perform pg_temp.reg('04.09 … y asoció de una vez los 4 reportes que ya estaban en la zona desde el inicio (bot, 116, daño y formato de campo)',
     (j ->> 'asociados_al_declarar')::integer = 4 and j -> 'reportes' = jsonb_build_object('total', 4, 'bot', 1, 'l116', 1, 'danos', 1, 'campo', 1) and pg_temp.en('campo', ca1::text) = v_e1 and pg_temp.en('campo', ca3::text) is null
     and pg_temp.en('bot', pg_temp.idbot('ZT15-0001')) = v_e1 and pg_temp.en('dano', pg_temp.iddano(v_d1)) = v_e1
     and (select count(*) from redes.evento_suspension_reportes where modo = 'al_declarar') = 4, j::text);
  perform pg_temp.reg('04.10 el reporte del bot asociado pasa a «En atención» con el evento en su historial; el daño recibe una nota y SIGUE abierto',
     pg_temp.ebot('ZT15-0001') = 'en_atencion'
     and (select x.motivo like 'Asociado al evento de suspensión ' || v_e1 || '%' from redes.reporte_externo_eventos x join redes.reportes_externos r on r.id = x.reporte_id where r.radicado = 'ZT15-0001' order by x.id desc limit 1)
     and (select count(*) from redes.dano_eventos) = v_num + 1 and (select e.tipo = 'nota' and e.motivo like '%' || v_e1 || '%' from redes.dano_eventos e order by e.id desc limit 1)
     and (select estado from redes.v_dano where codigo = v_d1) <> 'atendido');
  perform pg_temp.reg('04.10b el reporte del formato de campo asociado recibe una nota con el evento en su historial y sigue «Reportado» (se cierra con el evento)',
     pg_temp.ecampo(ca1) = 'reportado' and (select count(*) = 1 and bool_and(x.tipo_evento = 'nota' and x.motivo like 'Asociado al evento de suspensión ' || v_e1 || '%' and x.autor = sd)
                                             from campo.reporte_eventos x where x.reporte_id = ca1));
  perform pg_temp.reg('04.11 lo que NO se asoció: el de otro sector (S2), el tipo que no está en la lista (tapa; fuga en el medidor) y el que llegó antes del inicio',
     pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000002)) is null and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000003)) is null
     and pg_temp.en('bot', pg_temp.idbot('ZT15-0002')) is null and pg_temp.en('bot', pg_temp.idbot('ZT15-0003')) is null and pg_temp.ebot('ZT15-0002') = 'recibido');
  perform pg_temp.err('04.12 otro evento para la misma zona, mientras ese siga abierto, se niega (55000)',
     format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B otro daño de prueba')), '55000', v_e1);
  perform pg_temp.reg('04.13 queda en la auditoría quién lo declaró (sin datos de suscriptores)',
     (select count(*) = 1 and bool_and(x.detalle ->> 'zona' = 'ZT9B Sector S1') from public.geoportal_auditoria x where x.email = sd and x.accion = 'redes_evento_declarar' and x.referencia = v_e1));

  -- ===================== 05. La asociación automática de lo que llega mientras está abierto =====================
  j := pg_temp.bot('ZT15-0010', 300, 30, 'sin_agua');
  perform pg_temp.reg('05.01 BOT: un «sin agua» nuevo dentro de la zona queda asociado solo, en «En atención», y al bot se le responde «Ya sabemos del corte en tu sector. Regreso estimado: <hora>»',
     pg_temp.en('bot', pg_temp.idbot('ZT15-0010')) = v_e1 and pg_temp.ebot('ZT15-0010') = 'en_atencion' and j ->> 'evento' = v_e1 and j ->> 'radicado' = 'ZT15-0010'
     and j ->> 'mensaje' ~ '^Ya sabemos del corte en tu sector\. Regreso estimado: [0-9]{2}/[0-9]{2}, [0-9]{1,2}:[0-9]{2} [ap]\. m\.$' and (j ->> 'regreso_estimado')::timestamptz > clock_timestamp(), j::text);
  j2 := pg_temp.bot('ZT15-0010', 300, 30, 'sin_agua');
  perform pg_temp.reg('05.02 … si el bot reenvía el mismo radicado, recibe lo mismo y no se duplica nada',
     j2 = j and (select count(*) from redes.evento_suspension_reportes r where r.origen = 'bot' and r.ref = pg_temp.idbot('ZT15-0010')) = 1 and (select count(*) from redes.reportes_externos where radicado = 'ZT15-0010') = 1);
  j := pg_temp.bot('ZT15-0011', 310, 30, 'dano_red_acueducto');
  perform pg_temp.reg('05.03 … un «daño en la red» del bot dentro de la zona también se asocia (en vez de quedar para crear un daño nuevo)', j ->> 'evento' = v_e1 and pg_temp.ebot('ZT15-0011') = 'en_atencion');
  j := pg_temp.bot('ZT15-0012', 320, 30, 'tapa_caja_acueducto');
  j2 := pg_temp.bot('ZT15-0013', 700, 30, 'sin_agua');
  perform pg_temp.reg('05.04 … una tapa dentro de la zona, o un «sin agua» fuera de ella, siguen su flujo normal (sin evento ni mensaje)',
     j ->> 'evento' is null and j ->> 'mensaje' is null and pg_temp.ebot('ZT15-0012') = 'recibido' and j2 ->> 'evento' is null and pg_temp.ebot('ZT15-0013') = 'recibido');
  perform pg_temp.err('05.05 … el bot sigue sin poder mandar datos personales', $q$select redes.f_reporte_externo_recibir_evento('{"radicado": "ZT15-0014", "canal": "telegram", "tipo": "sin_agua", "lat": 10.13, "lon": -73.58, "telefono": "300"}')$q$, null, 'datos personales');
  -- línea 116: una «publicación» de varios reportes en una sola sentencia
  with r as (
    insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, carga_id)
    select x.num, clock_timestamp() + x.cuando, 'Acueducto', x.causal, v_carga
      from (values (990000010::bigint, 'No llega agua a la residencia', interval '0'), (990000011, 'Tubería rota', interval '0'), (990000012, 'Sin servicio de agua', interval '0'),
                   (990000013, 'Sin servicio de agua', interval '0'), (990000014, 'Sin servicio de agua', interval '-5 hours'), (990000015, 'Manjole tapado', interval '0')) x(num, causal, cuando)
    returning id, reporte)
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, carga_id, motivo, autor)
  select r.id, 'alta', case r.reporte when 990000013 then 'atendido' else 'registrado' end, 'contrato',
         case r.reporte when 990000012 then pg_temp.pt(650, 40) else pg_temp.pt(60 + (r.reporte - 990000010) * 10, 40) end, v_carga, 'ZT9B carga de prueba', a from r;
  perform pg_temp.reg('05.06 LÍNEA 116: al publicar una carga, los reportes nuevos de la zona se asocian (2 de 6): no el de fuera de la zona, ni el que ya viene «Atendido», ni el de antes del inicio, ni la causal que no aplica',
     (select count(*) from redes.evento_suspension_reportes r join redes.l116_reportes l on l.id = r.l116_reporte_id where l.reporte between 990000010 and 990000015) = 2
     and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000010)) = v_e1 and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000011)) = v_e1);
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, estado, estado_desde, metodo, geom)
  select l.id, l.reporte, l.fecha_registro, (l.fecha_registro at time zone 'America/Bogota')::date, l.servicio, l.causal, e.estado, l.fecha_registro, 'contrato', e.geom
    from redes.l116_reportes l join redes.l116_eventos e on e.reporte_id = l.id and e.tipo = 'alta' where l.reporte between 990000010 and 990000015;
  -- daños por formulario
  select count(*) into v_num from redes.danos;
  v_d2 := pg_temp.dano(op, 'T2', 250, 0, 'fuga');
  perform pg_temp.reg('05.07 DAÑO: el operador reporta un daño dentro de la zona: el daño SE CREA como siempre (su código, «Reportado») y queda asociado al evento, con la nota en su historial',
     v_d2 ~ '^DAN-[0-9]{6}$' and (select count(*) from redes.danos) = v_num + 1 and (select estado from redes.v_dano where codigo = v_d2) = 'reportado' and pg_temp.en('dano', pg_temp.iddano(v_d2)) = v_e1
     and (select e.tipo = 'nota' and e.motivo like '%' || v_e1 || '%sigue abierto%' and e.autor = 'sistema@evento.suspension' from redes.dano_eventos e where e.dano_id::text = pg_temp.iddano(v_d2)));
  v_d3 := pg_temp.dano(op, 'T3', 600, 0, 'fuga');
  v_d4 := pg_temp.dano(op, 'T2', 260, 0, 'valvula_danada');
  perform pg_temp.reg('05.08 … un daño fuera de la zona, o de un tipo que no está en la lista (válvula dañada), no se asocia ni recibe nota',
     pg_temp.en('dano', pg_temp.iddano(v_d3)) is null and pg_temp.en('dano', pg_temp.iddano(v_d4)) is null
     and not exists (select 1 from redes.dano_eventos e where e.dano_id::text in (pg_temp.iddano(v_d3), pg_temp.iddano(v_d4))));
  -- formato de campo (Comercial): la fila nueva en campo.reportes
  ca2 := pg_temp.campo(160, 30, 'sin_agua');
  perform pg_temp.reg('05.08b FORMATO DE CAMPO: un «sin agua» hecho desde Comercial dentro de la zona se guarda como siempre («Reportado») y queda asociado solo, con la nota en su historial',
     pg_temp.en('campo', ca2::text) = v_e1 and pg_temp.ecampo(ca2) = 'reportado'
     and (select count(*) = 1 and bool_and(x.tipo_evento = 'nota' and x.motivo = 'Asociado al evento de suspensión ' || v_e1 and x.autor = 'sistema@evento.suspension') from campo.reporte_eventos x where x.reporte_id = ca2));
  ca4 := pg_temp.campo(170, 30, 'fuga_acometida');
  ca5 := pg_temp.campo(820, 200, 'sin_agua');
  perform pg_temp.reg('05.08c … uno de otro tipo (fuga en acometida) dentro de la zona, o un «sin agua» fuera de ella, no se asocian ni reciben nota',
     pg_temp.en('campo', ca4::text) is null and pg_temp.en('campo', ca5::text) is null and not exists (select 1 from campo.reporte_eventos x where x.reporte_id in (ca4, ca5)));
  j := public.geoportal_redes_evento(sd, v_e1);
  perform pg_temp.reg('05.09 el evento lleva 10 reportes asociados: 3 del bot, 3 de la 116, 2 daños y 2 del formato de campo', j -> 'reportes' = jsonb_build_object('total', 10, 'bot', 3, 'l116', 3, 'danos', 2, 'campo', 2), (j -> 'reportes')::text);

  -- ===================== 06. Avisos: uno por evento =====================
  v_av := tecnica.f_avisos(false, true);
  perform pg_temp.reg('06.01 AVISOS: UN solo aviso por el evento (naranja), con los 10 reportes asociados en el texto, y no uno por reporte',
     (select count(*) from jsonb_array_elements(v_av) x where x ->> 'clave' like 'evento_suspension_%') = 1
     and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'clave' = 'evento_suspension_' || lower(v_e1) and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'nivel' = 'naranja'
     and (pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'n')::integer = 10 and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'titulo' like 'Sin agua en ZT9B Sector S1 desde las %'
     and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'detalle' like 'Daño en la tubería matriz de la calle 44. 10 reportes asociados. Regreso estimado: %'
     and pg_temp.aviso(v_av, 'evento_suspension_%') -> 'bandeja' ->> 'evento' = v_e1, pg_temp.aviso(v_av, 'evento_suspension_%')::text);
  perform pg_temp.reg('06.02 … el aviso de «sin agua sin evento» ya solo cuenta los que quedaron por fuera (7): los 2 de la 116, el del bot y los 2 del formato de campo en S2, y los 2 de antes del inicio (uno del bot y uno de la 116)',
     (pg_temp.aviso(v_av, 'sin_agua_sin_evento') ->> 'n')::integer = 7, pg_temp.aviso(v_av, 'sin_agua_sin_evento')::text);
  perform pg_temp.reg('06.03 … el aviso de reportes del bot «Recibidos» no cuenta los asociados (están «En atención»)',
     not exists (select 1 from redes.v_reporte_externo v where v.radicado in ('ZT15-0001', 'ZT15-0010', 'ZT15-0011') and v.ultimo_evento = 'recibido'));
  perform pg_temp.reg('06.04 … al supervisor de planta no le sale un evento por sectores', pg_temp.aviso(tecnica.f_avisos(true, false), 'evento_suspension_%') is null);
  v_av := tecnica.f_avisos(false, true, clock_timestamp() + interval '4 hours');
  perform pg_temp.reg('06.05 … cuando pasa la hora estimada de regreso y sigue abierto, el aviso sale en ROJO y lo dice',
     pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'nivel' = 'rojo' and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'detalle' like '%Ya pasó: ajuste la hora o cierre el evento.', pg_temp.aviso(v_av, 'evento_suspension_%')::text);

  -- ===================== 07. Ajustar el regreso; desasociar y asociar a mano; el detalle =====================
  perform pg_temp.err('07.01 el operador no ajusta la hora de regreso (42501)', format('select public.geoportal_redes_evento_regreso(%L, %L, %L)', op, v_e1, pg_temp.iso('5 hours')), '42501');
  perform pg_temp.err('07.02 el supervisor de planta tampoco, en un evento por sectores (42501)', format('select public.geoportal_redes_evento_regreso(%L, %L, %L)', sp, v_e1, pg_temp.iso('5 hours')), '42501');
  j := public.geoportal_redes_evento_regreso(sd, v_e1, pg_temp.iso('6 hours'), 'ZT9B llegó el repuesto más tarde');
  perform pg_temp.reg('07.03 el supervisor de distribución ajusta el regreso estimado: vale la hora nueva (lo declarado no cambia) y el bot responde con ella',
     (j ->> 'regreso_estimado')::timestamptz > clock_timestamp() + interval '5 hours' and (select regreso_estimado < clock_timestamp() + interval '4 hours' from redes.eventos_suspension where codigo = v_e1)
     and (pg_temp.bot('ZT15-0020', 330, 30, 'sin_agua') ->> 'regreso_estimado')::timestamptz > clock_timestamp() + interval '5 hours');
  perform pg_temp.err('07.04 desasociar sin motivo', format('select public.geoportal_redes_evento_desasociar(%L, %L, %L, %L, %L)', sd, v_e1, 'bot', pg_temp.idbot('ZT15-0011'), 'corto'), '22023', 'motivo');
  perform pg_temp.err('07.05 el operador no desasocia (42501)', format('select public.geoportal_redes_evento_desasociar(%L, %L, %L, %L, %L)', op, v_e1, 'bot', pg_temp.idbot('ZT15-0011'), 'ZT9B es otro problema'), '42501');
  j := public.geoportal_redes_evento_desasociar(sd, v_e1, 'bot', pg_temp.idbot('ZT15-0011'), 'ZT9B es otra fuga, a tres cuadras');
  perform pg_temp.reg('07.06 el supervisor DESASOCIA un reporte del bot con motivo: sale del evento (quedan 10 con el que acaba de entrar) y vuelve a «Recibido», con el motivo en su historial',
     (j -> 'reportes' ->> 'total')::integer = 10 and pg_temp.en('bot', pg_temp.idbot('ZT15-0011')) is null and pg_temp.ebot('ZT15-0011') = 'recibido'
     and (select x.motivo like 'Desasociado del evento de suspensión ' || v_e1 || ': ZT9B es otra fuga%' from redes.reporte_externo_eventos x where x.reporte_id::text = pg_temp.idbot('ZT15-0011') order by x.id desc limit 1), j::text);
  perform pg_temp.err('07.07 desasociar uno que no está en el evento', format('select public.geoportal_redes_evento_desasociar(%L, %L, %L, %L, %L)', sd, v_e1, 'bot', pg_temp.idbot('ZT15-0011'), 'ZT9B es otro problema'), '22023', 'no está asociado');
  j := public.geoportal_redes_evento_desasociar(sd, v_e1, 'dano', v_d2, 'ZT9B ese daño es de otra tubería');
  perform pg_temp.reg('07.08 … desasocia un daño (por su código): sale del evento y queda la nota en su historial',
     pg_temp.en('dano', pg_temp.iddano(v_d2)) is null and (select count(*) from redes.dano_eventos e where e.dano_id::text = pg_temp.iddano(v_d2) and e.tipo = 'nota') = 2);
  j := public.geoportal_redes_evento_asociar(sd, v_e1, 'l116', '990000003', 'ZT9B sí es del mismo corte');
  perform pg_temp.reg('07.09 ASOCIA a mano uno de la 116 que no había entrado solo (por su número), con motivo',
     pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000003)) = v_e1
     and (select r.modo = 'manual' and r.motivo is not null from redes.evento_suspension_reportes r order by r.id desc limit 1));
  perform pg_temp.err('07.10 asociar uno que ya está en el evento', format('select public.geoportal_redes_evento_asociar(%L, %L, %L, %L, %L)', sd, v_e1, 'l116', '990000003', 'ZT9B sí es del mismo corte'), '22023', 'ya está asociado');
  perform pg_temp.err('07.11 un reporte que no existe: P0002', format('select public.geoportal_redes_evento_asociar(%L, %L, %L, %L, %L)', sd, v_e1, 'dano', 'DAN-999999', 'ZT9B sí es del mismo corte'), 'P0002');
  j := public.geoportal_redes_evento(sd, v_e1);
  perform pg_temp.reg('07.12 EL DETALLE: 10 asociados con origen, rótulo, tipo, cuándo y punto; el usuario sensible confirmado (contrato y tipo); y el historial (regreso, desasociaciones y la asociación a mano)',
     jsonb_array_length(j -> 'asociados') = 10
     and (select count(*) = 2 and bool_and(x ->> 'ref' ~ '^REP-[0-9]{6}$' and x ->> 'rotulo' = 'Formato de campo · ' || (x ->> 'ref') and x ->> 'tipo' = 'No tengo agua o tengo baja presión') from jsonb_array_elements(j -> 'asociados') x where x ->> 'origen' = 'campo')
     and (select bool_and(x ? 'rotulo' and x ->> 'cuando' is not null and x ->> 'lat' is not null and x ->> 'tipo' is not null) from jsonb_array_elements(j -> 'asociados') x)
     and j -> 'sensibles_lista' = jsonb_build_array(jsonb_build_object('contrato', v_c1, 'tipo', 'Hospital'))
     and (select count(*) filter (where x ->> 'que' = 'regreso') = 1 and count(*) filter (where x ->> 'que' = 'desasociar') = 2 and count(*) filter (where x ->> 'que' = 'asociar_a_mano') = 1 from jsonb_array_elements(j -> 'historial') x),
     left(j::text, 900));
  perform pg_temp.reg('07.13 … sin nombres, teléfonos, direcciones, textos del ciudadano ni correos',
     j::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n|descripcion|@emdupar' and public.geoportal_redes_eventos_vigentes(op)::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n|@emdupar|contrato"');
  j := public.geoportal_redes_eventos_vigentes(op);
  perform pg_temp.reg('07.14 el OPERADOR sí ve los eventos vigentes (la zona en el mapa y la franja), sin la lista de reportes ni los sensibles',
     jsonb_array_length(j -> 'eventos') = 1 and j -> 'eventos' -> 0 ->> 'codigo' = v_e1 and j -> 'eventos' -> 0 -> 'zona_geojson' ->> 'type' = 'MultiPolygon'
     and j -> 'eventos' -> 0 ->> 'franja' like 'Sin agua en %' and not (j -> 'eventos' -> 0 ? 'asociados') and not (j -> 'eventos' -> 0 ? 'sensibles_lista'));
  perform pg_temp.err('07.15 … pero no el detalle ni la lista (42501)', format('select public.geoportal_redes_evento(%L, %L)', op, v_e1), '42501');
  j := public.geoportal_redes_evento_desasociar(sd, v_e1, 'campo', pg_temp.codcampo(ca2), 'ZT9B ese reporte es de otra cuadra');
  perform pg_temp.reg('07.16 FORMATO DE CAMPO: el supervisor desasocia un reporte por su código (REP-…), con motivo: sale del evento, sigue «Reportado» y queda la nota en su historial',
     pg_temp.en('campo', ca2::text) is null and pg_temp.ecampo(ca2) = 'reportado' and (j -> 'reportes' ->> 'campo')::integer = 1
     and (select x.tipo_evento = 'nota' and x.motivo like 'Desasociado del evento de suspensión ' || v_e1 || ': ZT9B ese reporte%' from campo.reporte_eventos x where x.reporte_id = ca2 order by x.id desc limit 1));
  j := public.geoportal_redes_evento_asociar(sd, v_e1, 'campo', pg_temp.codcampo(ca2), 'ZT9B sí era del mismo corte');
  perform pg_temp.reg('07.17 … y lo vuelve a asociar a mano; un reporte de campo que no existe: P0002', pg_temp.en('campo', ca2::text) = v_e1 and (j -> 'reportes' ->> 'campo')::integer = 2);
  perform pg_temp.err('07.18 … un reporte de campo que no existe: P0002', format('select public.geoportal_redes_evento_asociar(%L, %L, %L, %L, %L)', sd, v_e1, 'campo', 'REP-99999999', 'ZT9B sí es del mismo corte'), 'P0002');

  -- ===================== 08. Por círculo; dos eventos que se cruzan =====================
  perform pg_temp.err('08.01 un radio fuera de rango', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'circulo', 'lat', pg_temp.lat(100), 'lon', pg_temp.lon(380), 'radio_m', 5, 'causa', 'ZT9B fuga localizada')), '22023', 'radio');
  perform pg_temp.err('08.02 sin centro', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'circulo', 'radio_m', 100, 'causa', 'ZT9B fuga localizada')), '22023', 'centro');
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'circulo', 'lat', pg_temp.lat(100), 'lon', pg_temp.lon(560), 'radio_m', 120, 'causa', 'Fuga en la carrera 9', 'desde', pg_temp.iso('-30 minutes')));
  v_e2 := j ->> 'codigo';
  perform pg_temp.reg('08.03 declara un evento POR CÍRCULO (centro y radio de 120 m) en S2: guarda el centro, el radio y la zona; cuenta los 4 contratos del tramo que toca y su sensible; sin hora de regreso',
     j ->> 'alcance' = 'circulo' and (j -> 'circulo' ->> 'radio_m')::numeric = 120 and j ->> 'zona' = 'un círculo de 120 m en ZT9B Sector S2' and (j ->> 'contratos')::integer = 4 and (j ->> 'sensibles')::integer = 1
     and j ->> 'regreso_estimado' is null and j ->> 'franja' like '%Regreso estimado: sin definir.'
     and (select abs(ST_Area(geom::geography) - pi() * 120 * 120) / (pi() * 120 * 120) < 0.02 from redes.eventos_suspension where codigo = v_e2), j::text);
  perform pg_temp.reg('08.04 … asoció al declarar lo que ya estaba dentro del círculo desde el inicio: los 2 «sin agua» de la 116 (a 89 y a 108 m del centro) y el daño (a 108 m); no el del bot que está a 156 m',
     (j ->> 'asociados_al_declarar')::integer = 3 and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000012)) = v_e2 and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000002)) = v_e2 and pg_temp.en('dano', pg_temp.iddano(v_d3)) = v_e2
     and pg_temp.en('bot', pg_temp.idbot('ZT15-0013')) is null, j::text);
  j := pg_temp.bot('ZT15-0030', 620, 80, 'sin_agua');
  j2 := pg_temp.bot('ZT15-0031', 800, 80, 'sin_agua');
  perform pg_temp.reg('08.05 la pertenencia se decide por el punto: un reporte a 63 m del centro entra al círculo; uno a 240 m, no. Sin hora de regreso, al bot se le dice que todavía no hay',
     j ->> 'evento' = v_e2 and j ->> 'mensaje' = 'Ya sabemos del corte en tu sector. Todavía no hay hora estimada de regreso.' and j2 ->> 'evento' is null, j::text);
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'circulo', 'lat', pg_temp.lat(100), 'lon', pg_temp.lon(380), 'radio_m', 60, 'causa', 'ZT9B válvula cerrada en la esquina'));
  v_e3 := j ->> 'codigo';
  -- y, DESPUÉS, un evento de toda la ciudad: es el más reciente de los tres, pero el menos específico
  v_e5 := public.geoportal_redes_evento_declarar(a, jsonb_build_object('alcance', 'total', 'total', 'ciudad', 'causa', 'ZT9B falla general de prueba')) ->> 'codigo';
  j2 := pg_temp.bot('ZT15-0032', 370, 100, 'sin_agua');
  perform pg_temp.reg('08.06 si un punto cae en varios eventos abiertos (el sector S1, un círculo adentro y toda la ciudad, declarado de último), queda en UNO solo: EL MÁS ESPECÍFICO, el círculo (no el más reciente)',
     j2 ->> 'evento' = v_e3 and (select count(*) from redes.evento_suspension_reportes r where r.origen = 'bot' and r.ref = pg_temp.idbot('ZT15-0032')) = 1, j2::text);
  j := pg_temp.bot('ZT15-0033', 100, 200, 'sin_agua');
  j2 := pg_temp.bot('ZT15-0034', 5000, 5000, 'sin_agua');
  perform pg_temp.reg('08.06b … círculo > sectores > total: un punto del sector fuera del círculo queda en el evento del sector (no en el total, que es más reciente); uno fuera de todo, en el total',
     j ->> 'evento' = v_e1 and j2 ->> 'evento' = v_e5, j::text || j2::text);
  ca5 := pg_temp.campo(375, 100, 'sin_agua');
  perform pg_temp.reg('08.06c … la misma regla para la línea 116, los daños y el formato de campo (un reporte de campo dentro del círculo queda en el círculo)', pg_temp.en('campo', ca5::text) = v_e3);
  perform public.geoportal_redes_evento_anular(a, v_e5, 'ZT9B fin de la prueba de prioridad');
  v_av := tecnica.f_avisos(false, true);
  perform pg_temp.reg('08.07 con 3 eventos abiertos hay 3 avisos, uno por evento', (select count(*) from jsonb_array_elements(v_av) x where x ->> 'clave' like 'evento_suspension_%') = 3);

  -- ===================== 09. Anular: los reportes vuelven a su flujo =====================
  perform pg_temp.err('09.01 anular sin motivo', format('select public.geoportal_redes_evento_anular(%L, %L, %L)', sd, v_e3, ''), '22023', 'motivo');
  j := public.geoportal_redes_evento_anular(sd, v_e3, 'ZT9B se declaró por error, era el mismo corte');
  perform pg_temp.reg('09.02 el supervisor ANULA un evento con motivo: queda «anulado» (nada se borra), su reporte del bot vuelve a «Recibido», el del formato de campo queda libre con la nota, y ya no tiene aviso',
     j ->> 'estado' = 'anulado' and (j ->> 'reportes_liberados')::integer = 2 and pg_temp.en('campo', ca5::text) is null and pg_temp.ecampo(ca5) = 'reportado'
     and (select x.tipo_evento = 'nota' and x.motivo like 'Evento de suspensión ' || v_e3 || ' anulado:%' from campo.reporte_eventos x where x.reporte_id = ca5 order by x.id desc limit 1) and j -> 'fin' ->> 'motivo' like 'ZT9B se declaró por error%' and pg_temp.ebot('ZT15-0032') = 'recibido'
     and pg_temp.en('bot', pg_temp.idbot('ZT15-0032')) is null and exists (select 1 from redes.eventos_suspension where codigo = v_e3)
     and (select count(*) from jsonb_array_elements(tecnica.f_avisos(false, true)) x where x ->> 'clave' like 'evento_suspension_%') = 2, j::text);
  perform pg_temp.err('09.03 un evento anulado no se cierra ni se vuelve a anular (55000)', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L)', sd, v_e3, 'ZT9B ya volvió el servicio'), '55000', 'anulado');
  j := public.geoportal_redes_evento_asociar(sd, v_e1, 'bot', pg_temp.idbot('ZT15-0032'), 'ZT9B era del corte del sector');
  perform pg_temp.reg('09.04 … y ese reporte, ya libre, se puede asociar a mano al evento del sector', pg_temp.en('bot', pg_temp.idbot('ZT15-0032')) = v_e1 and pg_temp.ebot('ZT15-0032') = 'en_atencion');

  -- ===================== 10. Cierre en bloque («dar de alta») =====================
  perform pg_temp.err('10.01 cerrar sin motivo', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L)', sd, v_e1, 'ya'), '22023', 'motivo');
  perform pg_temp.err('10.02 no se cierra antes de la hora en que empezó', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L, %L)', sd, v_e1, 'ZT9B ya volvió el servicio', pg_temp.iso('-2 hours')), '22023', 'antes');
  perform pg_temp.err('10.03 el operador no cierra (42501)', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L)', op, v_e1, 'ZT9B ya volvió el servicio'), '42501');
  select count(*) into v_num from redes.danos; select count(*) into v_num2 from redes.reportes_externos;
  j := public.geoportal_redes_evento_cerrar(sd, v_e1, 'Tubería reparada y servicio restablecido');
  perform pg_temp.reg('10.04 el supervisor CIERRA el evento: queda «cerrado» con motivo, hora y quién; cierra en bloque 5 reportes del bot, 4 de la 116 y 2 del formato de campo; el daño asociado sigue abierto',
     j ->> 'estado' = 'cerrado' and j -> 'fin' ->> 'motivo' = 'Tubería reparada y servicio restablecido' and j -> 'fin' ->> 'por' = 'ZT9B Supervisor de distribución'
     and j -> 'cerrados' = jsonb_build_object('bot', 5, 'l116', 4, 'campo', 2) and (j ->> 'danos_siguen_abiertos')::integer = 1, j::text);
  perform pg_temp.reg('10.05 … cada reporte del bot quedó «Atendido» con el MISMO motivo y la MISMA hora en su historial',
     (select count(*) = 5 and count(distinct x.motivo) = 1 and bool_and(x.motivo like 'Evento de suspensión ' || v_e1 || ' cerrado (%): Tubería reparada y servicio restablecido' and x.autor = sd)
        from redes.reporte_externo_eventos x where x.tipo = 'atendido')
     and pg_temp.ebot('ZT15-0001') = 'atendido' and pg_temp.ebot('ZT15-0010') = 'atendido' and pg_temp.ebot('ZT15-0020') = 'atendido' and pg_temp.ebot('ZT15-0032') = 'atendido');
  perform pg_temp.reg('10.06 … cada reporte de la 116 quedó «Atendido», con su hecho en el historial (de «Registrado» a «Atendido», mismo motivo)',
     (select count(*) = 4 and count(distinct e.motivo) = 1 and bool_and(e.estado = 'atendido' and e.estado_antes = 'registrado' and e.motivo like '%' || v_e1 || '%Tubería reparada%') from redes.l116_eventos e where e.tipo = 'estado')
     and (select count(*) = 4 and bool_and(v.estado = 'atendido') from redes.l116_vigente v where v.reporte in (990000001, 990000003, 990000010, 990000011)));
  perform pg_temp.reg('10.06b … cada reporte del formato de campo (Comercial) quedó «Atendido» con el mismo motivo y la misma hora en su historial; los que no estaban en el evento siguen «Reportado»',
     pg_temp.ecampo(ca1) = 'atendido' and pg_temp.ecampo(ca2) = 'atendido' and pg_temp.ecampo(ca3) = 'reportado' and pg_temp.ecampo(ca4) = 'reportado' and pg_temp.ecampo(ca5) = 'reportado'
     and (select count(*) = 2 and count(distinct x.motivo) = 1 and bool_and(x.estado_nuevo = 'atendido' and x.autor = sd
                 and x.motivo = (select y.motivo from redes.reporte_externo_eventos y where y.tipo = 'atendido' limit 1))
            from campo.reporte_eventos x where x.tipo_evento = 'cambio_estado'));
  perform pg_temp.reg('10.07 … el daño NO se cerró: sigue «Reportado», con la nota del cierre del evento en su historial',
     (select estado from redes.v_dano where codigo = v_d1) = 'reportado'
     and (select e.motivo like 'Evento de suspensión ' || v_e1 || ' cerrado%' from redes.dano_eventos e where e.dano_id::text = pg_temp.iddano(v_d1) order by e.id desc limit 1));
  perform pg_temp.reg('10.08 … los desasociados no se tocaron (el del bot sigue «Recibido»; el daño, sin nota de cierre) y no se borró ni se creó ningún reporte ni daño',
     pg_temp.ebot('ZT15-0011') = 'recibido' and (select count(*) from redes.dano_eventos e where e.dano_id::text = pg_temp.iddano(v_d2)) = 2
     and (select count(*) from redes.danos) = v_num and (select count(*) from redes.reportes_externos) = v_num2);
  perform pg_temp.err('10.09 un evento cerrado no se vuelve a cerrar (55000)', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L)', sd, v_e1, 'ZT9B ya volvió el servicio'), '55000', 'cerrado');
  j := pg_temp.bot('ZT15-0040', 300, 30, 'sin_agua');
  perform pg_temp.reg('10.10 después del cierre, un reporte nuevo en esa zona ya no se asocia: entra como siempre y se avisa como «sin agua sin evento»',
     j ->> 'evento' is null and pg_temp.ebot('ZT15-0040') = 'recibido');
  j := public.geoportal_redes_eventos(sd, 'todos');
  perform pg_temp.reg('10.11 la lista del supervisor: 4 eventos (1 abierto, 1 cerrado, 2 anulados), los últimos primero; por estado, solo los de ese estado',
     jsonb_array_length(j -> 'eventos') = 4 and j -> 'eventos' -> 0 ->> 'codigo' = v_e5 and jsonb_array_length(public.geoportal_redes_eventos(sd, 'anulado') -> 'eventos') = 2 and jsonb_array_length(public.geoportal_redes_eventos(sd, 'abierto') -> 'eventos') = 1
     and public.geoportal_redes_eventos(sd, 'cerrado') -> 'eventos' -> 0 ->> 'codigo' = v_e1);
  perform pg_temp.reg('10.12 el evento cerrado conserva sus 12 reportes y su historial en el detalle', (public.geoportal_redes_evento(sd, v_e1) -> 'reportes' ->> 'total')::integer = 12
     and jsonb_array_length(public.geoportal_redes_evento(sd, v_e1) -> 'historial') = 8, public.geoportal_redes_evento(sd, v_e1)::text);      -- 1 regreso, 3 desasociaciones, 3 asociaciones a mano y el cierre

  -- ===================== 10b. La publicación de la línea 116 NO revive lo que cerró un evento (una publicación REAL, por el motor del Cargue) =====================
  -- el archivo trae: 990000001 en «Registrado» (lo cerró el evento) · 990000010 «Atendido» (igual) · 990000015 «Atendido» (cambio normal: no estaba en el evento)
  -- · 990000013 «Registrado» (estaba «Atendido» desde su alta, sin evento: la publicación SÍ lo devuelve, como siempre) · 990000030, nuevo
  select estado_desde into v_ts from redes.l116_vigente where reporte = 990000001;
  v_cg := pg_temp.subir116(sd, jsonb_build_array(pg_temp.fila116(1, 990000001, 'Registrado'), pg_temp.fila116(2, 990000010, 'Atendido', 'No llega agua a la residencia'),
            pg_temp.fila116(3, 990000015, 'Atendido', 'Manjole tapado'), pg_temp.fila116(4, 990000013, 'Registrado'), pg_temp.fila116(5, 990000030, 'Registrado')), 'zt9b-116-uno');
  v_r := public.geoportal_redes_carga_resumen(sd, v_cg);
  v_x := public.geoportal_redes_carga_publicar(sd, v_cg, 'ZT9B carga de la 116 después del cierre del evento');
  perform pg_temp.reg('10b.01 PUBLICACIÓN REAL de la 116 después del cierre: lista para publicar; 1 nuevo, 2 cambios de estado normales y 1 conservado por el evento',
     (v_r ->> 'lista_para_publicar')::boolean and (v_x ->> 'nuevos')::integer = 1 and (v_x ->> 'cambios_estado')::integer = 2 and (v_x ->> 'conservados_por_evento')::integer = 1, (v_r - 'tabla')::text || v_x::text);
  perform pg_temp.reg('10b.02 … el reporte que cerró el evento NO revive: sigue «Atendido» (desde la misma hora), aunque el archivo lo trae en «Registrado»',
     (select v.estado = 'atendido' and v.estado_desde = v_ts and not v.oculto from redes.l116_vigente v where v.reporte = 990000001));
  perform pg_temp.reg('10b.03 … y la diferencia con la fuente queda en su historial: «La carga N … lo trae en «Registrado»: conserva «Atendido» porque lo cerró el evento EVS-…»',
     pg_temp.h116(990000001) = array['alta:registrado:-', 'estado:atendido:registrado', 'estado:atendido:atendido']
     and (select e.motivo = format('La carga %s de la línea 116 lo trae en «Registrado»: conserva «Atendido» porque lo cerró el evento de suspensión %s', v_cg, v_e1) and e.carga_id is null and e.autor = sd
            from redes.l116_eventos e join redes.l116_reportes r on r.id = e.reporte_id where r.reporte = 990000001 order by e.id desc limit 1), pg_temp.h116(990000001)::text);
  perform pg_temp.reg('10b.04 … lo demás se publica como siempre: el que no estaba en un evento sí vuelve a «Registrado»; el otro pasa a «Atendido»; el nuevo entra',
     (select estado from redes.l116_vigente where reporte = 990000013) = 'registrado' and pg_temp.h116(990000013) = array['alta:atendido:-', 'estado:registrado:atendido']
     and (select estado from redes.l116_vigente where reporte = 990000015) = 'atendido' and (select estado from redes.l116_vigente where reporte = 990000030) = 'registrado'
     and (select (detalle ->> 'conservados_por_evento')::integer from redes.carga_eventos where carga_id = v_cg and tipo = 'publicar') = 1);
  v_cg := pg_temp.subir116(sd, jsonb_build_array(pg_temp.fila116(1, 990000001, 'Registrado'), pg_temp.fila116(2, 990000003, 'Registrado', 'Fuga en el medidor')), 'zt9b-116-dos');
  v_x := public.geoportal_redes_carga_publicar(sd, v_cg, 'ZT9B otra carga de la 116 con los mismos reportes');
  perform pg_temp.reg('10b.05 una carga siguiente que los vuelve a traer en «Registrado» tampoco los revive (2 conservados, 0 cambios); la diferencia se anota UNA vez por reporte',
     (v_x ->> 'conservados_por_evento')::integer = 2 and (v_x ->> 'cambios_estado')::integer = 0
     and pg_temp.h116(990000001) = array['alta:registrado:-', 'estado:atendido:registrado', 'estado:atendido:atendido']
     and pg_temp.h116(990000003) = array['alta:registrado:-', 'estado:atendido:registrado', 'estado:atendido:atendido']
     and (select count(*) = 2 and bool_and(v.estado = 'atendido') from redes.l116_vigente v where v.reporte in (990000001, 990000003)), v_x::text);
  v_x := public.geoportal_redes_carga_revertir(sd, 'linea_116', 'ZT9B se revierte la última carga de prueba');
  perform pg_temp.reg('10b.06 revertir esa carga no toca lo conservado (sigue «Atendido», sin hechos nuevos)',
     (v_x ->> 'estados_devueltos')::integer = 0 and (select count(*) = 2 and bool_and(v.estado = 'atendido') from redes.l116_vigente v where v.reporte in (990000001, 990000003))
     and array_length(pg_temp.h116(990000001), 1) = 3, v_x::text);
  perform pg_temp.reg('10b.07 un reporte de la 116 que alguien DESASOCIÓ del evento antes del cierre no queda protegido (la publicación lo trata como siempre)',
     redes.f_evento_l116_cerrado((select id from redes.l116_reportes where reporte = 990000001)) = v_e1
     and redes.f_evento_l116_cerrado((select id from redes.l116_reportes where reporte = 990000013)) is null);

  -- ===================== 11. Total: por planta y toda la ciudad =====================
  perform pg_temp.err('11.01 una planta sin sectores asignados no se puede declarar: lo dice', format('select public.geoportal_redes_evento_declarar(%L, %L)', sp, jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'huaricha', 'causa', 'ZT9B falla de energía')), '22023', 'no tiene sectores asignados');
  perform pg_temp.err('11.02 el supervisor de planta no asigna los sectores de una planta (42501)', format('select public.geoportal_redes_planta_sectores_fijar(%L, %L, %L, %L)', sp, 'huaricha', array[pg_temp.cod('S2')], 'ZT9B sectores de prueba'), '42501');
  j := public.geoportal_redes_planta_sectores_fijar(sd, 'huaricha', array[pg_temp.cod('S1'), pg_temp.cod('S2')], 'ZT9B sectores de prueba de la planta');
  j := public.geoportal_redes_planta_sectores_fijar(sd, 'huaricha', array[pg_temp.cod('S2')], 'ZT9B se corrige: solo el sector dos');
  perform pg_temp.reg('11.03 el supervisor de distribución asigna, y luego corrige, los sectores que surte una planta (con motivo; queda el historial): al final, solo S2',
     j -> 'sectores' = jsonb_build_array(pg_temp.cod('S2')) and (select count(*) from redes.planta_sector_eventos) = 2
     and (select count(*) filter (where activo) = 1 and count(*) = 2 from redes.planta_sectores)
     and (select x -> 'sectores' from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sp) -> 'plantas') x where x ->> 'codigo' = 'huaricha') = jsonb_build_array(pg_temp.cod('S2')));
  j := public.geoportal_redes_evento_declarar(sp, jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'huaricha', 'causa', 'Falla de energía en la planta', 'regreso', pg_temp.iso('2 hours')));
  v_e4 := j ->> 'codigo';
  perform pg_temp.reg('11.04 el supervisor de planta declara un TOTAL POR PLANTA: la zona es lo que surte la planta (S2), con sus 4 contratos y su sensible',
     j ->> 'alcance' = 'total' and j ->> 'total' = 'planta' and j ->> 'planta' = 'Huaricha' and j ->> 'zona' = 'lo que surte la planta Huaricha' and (j ->> 'contratos')::integer = 4 and (j ->> 'sensibles')::integer = 1
     and j -> 'sectores' = jsonb_build_array(pg_temp.cod('S2')), j::text);
  v_av := tecnica.f_avisos(true, false);
  perform pg_temp.reg('11.05 … su aviso le sale también al supervisor de planta (los totales), y no el del círculo',
     (select count(*) from jsonb_array_elements(v_av) x where x ->> 'clave' like 'evento_suspension_%') = 1 and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'clave' = 'evento_suspension_' || lower(v_e4)
     and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'area' = 'planta');
  perform pg_temp.err('11.06 el supervisor de distribución no cierra un evento total (42501)', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L)', sd, v_e4, 'ZT9B ya volvió el servicio'), '42501');
  j := public.geoportal_redes_evento_desasociar(sd, v_e2, 'bot', pg_temp.idbot('ZT15-0030'), 'ZT9B se pasa al evento de la planta');
  j := public.geoportal_redes_evento_asociar(sd, v_e4, 'bot', pg_temp.idbot('ZT15-0030'), 'ZT9B se pasa al evento de la planta');
  perform pg_temp.reg('11.07 … pero sí maneja sus reportes: pasa uno del círculo al evento de la planta (desasociar y asociar, con motivo)', pg_temp.en('bot', pg_temp.idbot('ZT15-0030')) = v_e4);
  j := public.geoportal_redes_evento_cerrar(sp, v_e4, 'Volvió la energía y la planta bombea');
  perform pg_temp.reg('11.08 el supervisor de planta cierra su evento total', j ->> 'estado' = 'cerrado' and pg_temp.ebot('ZT15-0030') = 'atendido');
  j := public.geoportal_redes_evento_declarar(a, jsonb_build_object('alcance', 'total', 'total', 'ciudad', 'causa', 'Falla en la captación', 'desde', pg_temp.iso('-1 minutes')));
  v_e4 := j ->> 'codigo';
  perform pg_temp.reg('11.09 el administrador declara un TOTAL DE TODA LA CIUDAD: sin geometría, cuenta todos los contratos con tramo y todos los sensibles confirmados',
     j ->> 'total' = 'ciudad' and j ->> 'zona' = 'toda la ciudad' and (j ->> 'contratos')::integer = v_reales and (j ->> 'sensibles')::integer = (select count(*) from redes.v_usuario_sensible where estado = 'confirmado')
     and j -> 'zona_geojson' = 'null'::jsonb, j::text);
  j2 := pg_temp.bot('ZT15-0050', 5000, 5000, 'sin_agua');
  perform pg_temp.reg('11.10 … cualquier reporte nuevo, esté donde esté, queda en el evento de la ciudad', j2 ->> 'evento' = v_e4);
  perform pg_temp.err('11.11 un segundo evento de toda la ciudad se niega (55000)', format('select public.geoportal_redes_evento_declarar(%L, %L)', a, jsonb_build_object('alcance', 'total', 'total', 'ciudad', 'causa', 'ZT9B otra falla')), '55000');
  perform public.geoportal_redes_evento_anular(a, v_e4, 'ZT9B fin de la prueba del evento total');
  perform public.geoportal_redes_evento_cerrar(sd, v_e2, 'ZT9B fuga reparada en la carrera 9');

  -- ===================== 12. La lista ajustable de lo que se asocia =====================
  perform pg_temp.err('12.01 el operador no cambia la lista (42501)', format('select public.geoportal_redes_evento_tipo_fijar(%L, %L, %L, false, %L)', op, 'bot', 'dano_red_acueducto', 'ZT9B ya no se asocia'), '42501');
  perform pg_temp.err('12.02 sin motivo', format('select public.geoportal_redes_evento_tipo_fijar(%L, %L, %L, false, %L)', sd, 'bot', 'dano_red_acueducto', 'no'), '22023', 'motivo');
  perform pg_temp.err('12.03 un tipo nuevo necesita nombre y clase', format('select public.geoportal_redes_evento_tipo_fijar(%L, %L, %L, true, %L)', sd, 'l116', 'Agua turbia', 'ZT9B se agrega la causal'), '22023', 'nombre');
  j := public.geoportal_redes_evento_tipo_fijar(sd, 'bot', 'dano_red_acueducto', false, 'ZT9B el daño en la red sigue su flujo normal');
  j2 := public.geoportal_redes_evento_tipo_fijar(sd, 'l116', '  Fuga en  el MEDIDOR ', true, 'ZT9B se agrega la causal de prueba', 'Fuga en el medidor', 'otro');
  v_e1 := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1A')), 'causa', 'ZT9B corte programado del subsector')) ->> 'codigo';
  perform pg_temp.l116(990000020, 90, 60, 'fuga en el medidor');
  perform pg_temp.reg('12.04 el supervisor ajusta la lista con motivo (queda el historial): un «daño en la red» del bot ya no se asocia, y una causal nueva de la 116 sí (sin importar mayúsculas ni espacios)',
     not (j ->> 'asocia')::boolean and j2 ->> 'codigo' = 'fuga en el medidor' and (select count(*) from redes.evento_tipo_eventos) = 2
     and pg_temp.bot('ZT15-0060', 90, 50, 'dano_red_acueducto') ->> 'evento' is null and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000020)) = v_e1);
  perform pg_temp.reg('12.05 un evento por SUBSECTOR: la zona es la del subsector (un reporte en el resto del sector no entra)',
     pg_temp.bot('ZT15-0061', 90, 50, 'sin_agua') ->> 'evento' = v_e1 and pg_temp.bot('ZT15-0062', 300, 50, 'sin_agua') ->> 'evento' is null);
  -- después del subsector, el sector que lo contiene (más reciente y de la misma clase): gana el de MENOR ÁREA, el subsector
  v_e6 := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B corte del sector completo')) ->> 'codigo';
  perform pg_temp.reg('12.05b dos eventos por sectores que se cruzan (el subsector S1A y, declarado después, su sector S1): un punto del subsector queda en el del SUBSECTOR (el más específico); uno del resto del sector, en el del sector',
     pg_temp.bot('ZT15-0063', 95, 50, 'sin_agua') ->> 'evento' = v_e1 and pg_temp.bot('ZT15-0064', 300, 50, 'sin_agua') ->> 'evento' = v_e6);
  perform pg_temp.err('12.06 un tipo del formato de campo que no existe no se agrega a la lista: P0002', format('select public.geoportal_redes_evento_tipo_fijar(%L, %L, %L, true, %L, %L, %L)', sd, 'campo', 'zt9b_no_existe', 'ZT9B se agrega el tipo de prueba', 'ZT9B tipo', 'otro'), 'P0002');
  j := public.geoportal_redes_evento_tipo_fijar(sd, 'campo', 'fuga_acometida', true, 'ZT9B la fuga en acometida también se asocia', 'Fuga en acometida', 'dano_red');
  ca4 := pg_temp.campo(90, 60, 'fuga_acometida');
  perform pg_temp.reg('12.07 la lista del formato de campo también se ajusta: se agrega «fuga en acometida» y un reporte de ese tipo dentro de la zona queda asociado',
     (j ->> 'asocia')::boolean and j ->> 'origen' = 'campo' and pg_temp.en('campo', ca4::text) = v_e1);
  perform public.geoportal_redes_evento_cerrar(sd, v_e6, 'ZT9B terminó el corte del sector');
  perform public.geoportal_redes_evento_cerrar(sd, v_e1, 'ZT9B terminó el corte programado');

  -- ===================== 13. Solo agregar =====================
  perform pg_temp.err('13.01 solo agregar: un evento no se cambia', 'update redes.eventos_suspension set causa = ''otra causa'' where id = (select min(id) from redes.eventos_suspension)');
  perform pg_temp.err('13.02 solo agregar: un evento no se borra', 'delete from redes.eventos_suspension where id = (select min(id) from redes.eventos_suspension)');
  perform pg_temp.err('13.03 solo agregar: una asociación no se cambia ni se borra', 'delete from redes.evento_suspension_reportes where id = (select min(id) from redes.evento_suspension_reportes)');
  perform pg_temp.err('13.04 solo agregar: el cierre de un evento no se cambia', 'update redes.evento_suspension_eventos set motivo = ''otro motivo distinto'' where id = (select min(id) from redes.evento_suspension_eventos)');
  perform pg_temp.err('13.05 un evento termina una sola vez (la base lo impide aunque se salte la RPC)',
     format('insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) select id, ''anular'', ''ZT9B segundo final'', clock_timestamp(), %L from redes.eventos_suspension where codigo = %L', a, v_e1), '23505');
  perform pg_temp.reg('13.06 al final no queda ningún evento abierto y nadie recibió nada que no fuera suyo: 8 eventos en la base (5 cerrados y 3 anulados)',
     not exists (select 1 from redes.f_eventos_abiertos()) and (select count(*) filter (where estado = 'cerrado') = 5 and count(*) filter (where estado = 'anulado') = 3 and count(*) = 8 from redes.v_evento_suspension));

  -- ===================== 14. TIEMPOS con volumen: la zona cubre la red real de esta base, 300 eventos viejos y una carga de 5.000 reportes de la 116 =====================
  select ST_SetSRID(ST_Extent(m.geom)::geometry, 4326) into v_caja from redes.activo_vigente_mat m where m.prefijo = 'RED' and m.sistema = 'acueducto' and m.codigo not in (pg_temp.cod('T1'), pg_temp.cod('T2'), pg_temp.cod('T3'))
     and ST_Y(ST_StartPoint(m.geom)) > 10.3;
  if v_caja is null then v_caja := pg_temp.poli(-3000, -3000, -1000, -1000); end if;
  insert into _zt select 'GRAN', pg_temp.activo('Sector de toda la red', 'SEC', v_caja, 'sector'), null, 0, 0;
  -- 300 eventos viejos, ya cerrados (la búsqueda de «eventos abiertos» no debe depender de cuántos ha habido)
  with viejos as (
    insert into redes.eventos_suspension (codigo, alcance, geom, sectores, zona_nombre, causa, desde, contratos, sensibles, autor)
    select 'EVS-9' || lpad(i::text, 5, '0'), 'sectores', ST_Multi(pg_temp.poli(0, -50, 400, 250)), array[pg_temp.id('S1')], 'ZT9B Sector S1', 'ZT9B evento viejo de relleno',
           clock_timestamp() - interval '90 days' + make_interval(hours => i), 5, 1, a from generate_series(1, 300) i
    returning id, desde)
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) select id, 'cerrar', 'ZT9B cierre de relleno', desde + interval '2 hours', a from viejos;
  v_t0 := clock_timestamp();
  j := public.geoportal_redes_evento_vista_previa(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('GRAN')), 'desde', pg_temp.iso('-30 minutes')));
  v_ms_vp := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('GRAN')), 'causa', 'ZT9B evento grande para medir tiempos', 'desde', pg_temp.iso('-30 minutes')));
  v_ms_decl := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_gran := j ->> 'codigo';
  v_t0 := clock_timestamp();
  j2 := redes.f_reporte_externo_recibir_evento(jsonb_build_object('radicado', 'ZT15-9001', 'canal', 'telegram', 'tipo', 'sin_agua', 'lat', round(ST_Y(ST_Centroid(v_caja))::numeric, 6), 'lon', round(ST_X(ST_Centroid(v_caja))::numeric, 6)));
  v_ms_bot := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  -- una carga de 5.000 reportes nuevos de la 116 en una sentencia, todos dentro de la zona
  v_t0 := clock_timestamp();
  with r as (
    insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, carga_id)
    select 980000000 + i, clock_timestamp(), 'Acueducto', case when i % 2 = 0 then 'Sin servicio de agua' else 'Manjole tapado' end, v_carga from generate_series(1, 5000) i
    returning id, reporte)
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, carga_id, motivo, autor)
  select r.id, 'alta', 'registrado', 'contrato',
         ST_SetSRID(ST_MakePoint(ST_XMin(v_caja) + (ST_XMax(v_caja) - ST_XMin(v_caja)) * ((r.reporte % 97) / 97.0), ST_YMin(v_caja) + (ST_YMax(v_caja) - ST_YMin(v_caja)) * ((r.reporte % 89) / 89.0)), 4326),
         v_carga, 'ZT9B carga de relleno', a from r;
  v_ms_116 := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, estado, estado_desde, metodo, geom)
  select l.id, l.reporte, l.fecha_registro, (l.fecha_registro at time zone 'America/Bogota')::date, l.servicio, l.causal, 'registrado', l.fecha_registro, 'contrato', e.geom
    from redes.l116_reportes l join redes.l116_eventos e on e.reporte_id = l.id and e.tipo = 'alta' where l.reporte > 980000000 and l.reporte <= 980005000;
  v_t0 := clock_timestamp(); v_av := tecnica.f_avisos(false, true); v_ms_av := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp(); j2 := public.geoportal_redes_evento(sd, v_gran); v_ms_det := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  j := public.geoportal_redes_evento_cerrar(sd, v_gran, 'ZT9B fin de la medición de tiempos');
  v_ms_cerrar := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_info := format('TIEMPOS (zona con %s contratos; %s eventos en la base): asociar un reporte del bot %s ms · una carga de 5.000 reportes de la 116 (2.500 asociados) %s ms, %s ms por reporte · '
                   || 'vista previa %s ms · declarar %s ms · avisos %s ms · detalle (200 de %s asociados) %s ms · cerrar en bloque %s reportes %s ms',
                   j2 ->> 'contratos', (select count(*) from redes.eventos_suspension), v_ms_bot, v_ms_116, round(v_ms_116 / 5000, 3), v_ms_vp, v_ms_decl, v_ms_av, j2 -> 'reportes' ->> 'total', v_ms_det,
                   (j -> 'cerrados' ->> 'bot')::integer + (j -> 'cerrados' ->> 'l116')::integer, v_ms_cerrar);
  perform pg_temp.reg('14.01 con volumen, la carga de la 116 asoció los 2.500 «sin agua» (y ningún «manjole»), el detalle lista 200 y el cierre los dejó «Atendido»',
     (j2 -> 'reportes' ->> 'l116')::integer = 2500 and jsonb_array_length(j2 -> 'asociados') = 200 and (j -> 'cerrados' ->> 'l116')::integer = 2500
     and (select count(*) from redes.l116_vigente v where v.reporte > 980000000 and v.reporte <= 980005000 and v.estado = 'atendido') = 2500, (j -> 'cerrados')::text);
  perform pg_temp.reg('14.02 TIEMPOS: asociar un reporte nuevo (bot) en menos de 1 s', v_ms_bot < 1000, v_info);
  perform pg_temp.reg('14.03 TIEMPOS: la carga de 5.000 reportes de la 116, la vista previa, declarar, los avisos, el detalle y el cierre en bloque, cada uno en menos de 1 s (local; producción es unas 6 veces más lenta)',
     greatest(v_ms_116, v_ms_vp, v_ms_decl, v_ms_av, v_ms_det, v_ms_cerrar) < 1000, v_info);
  -- una publicación REAL de la 116 con los 2.500 reportes que cerró el evento otra vez en «Registrado»: ninguno revive
  v_cg := pg_temp.subir116(sd, (select jsonb_agg(pg_temp.fila116(i, 980000000 + 2 * i, 'Registrado') order by i) from generate_series(1, 2500) i), 'zt9b-116-volumen');
  v_r := public.geoportal_redes_carga_resumen(sd, v_cg);
  v_t0 := clock_timestamp(); v_x := public.geoportal_redes_carga_publicar(sd, v_cg, 'ZT9B carga de volumen después del cierre'); v_ms_pub := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_info := v_info || format(' · publicar una carga REAL de la 116 con 2.500 reportes cerrados por el evento %s ms', v_ms_pub);
  perform pg_temp.reg('14.03b PUBLICACIÓN REAL con volumen: los 2.500 reportes que cerró el evento vuelven en «Registrado» y NINGUNO revive (2.500 conservados, 0 cambios), en menos de 1 s',
     (v_x ->> 'conservados_por_evento')::integer = 2500 and (v_x ->> 'cambios_estado')::integer = 0 and v_ms_pub < 1000
     and (select count(*) from redes.l116_vigente v where v.reporte > 980000000 and v.reporte <= 980005000 and v.estado = 'atendido') = 2500
     and (select count(*) from redes.l116_eventos e where e.tipo = 'estado' and e.estado_antes = 'atendido' and e.estado = 'atendido' and e.motivo like 'La carga ' || v_cg || ' %') = 2500, v_x::text || ' ' || v_info);
  v_t0 := clock_timestamp(); v_d1 := pg_temp.dano(op, 'T1', 100, 0, 'fuga'); v_ms_dano := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp(); ca1 := pg_temp.campo(100, 10, 'sin_agua'); v_ms_campo := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_info := v_info || format(' · crear un daño sin eventos abiertos %s ms · guardar un reporte de campo sin eventos abiertos %s ms', v_ms_dano, v_ms_campo);
  perform pg_temp.reg('14.04b sin eventos abiertos, guardar un reporte del formato de campo no se demora por el disparador (menos de 1 s) y no escribe nada del corte',
     v_ms_campo < 1000 and not exists (select 1 from campo.reporte_eventos x where x.reporte_id = ca1) and pg_temp.ecampo(ca1) = 'reportado', v_info);
  perform pg_temp.reg('14.04 sin eventos abiertos, crear un daño no se demora por los disparadores (menos de 1 s) y no escribe nada del corte',
     v_ms_dano < 1000 and not exists (select 1 from redes.dano_eventos e where e.dano_id::text = pg_temp.iddano(v_d1)), v_info);
  perform pg_temp.reg('14.05 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion, ', ') from redes.f_funciones_sin_where()));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 15, evento de suspensión (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
