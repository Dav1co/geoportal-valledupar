-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes9f.*), la red de prueba ZT9B (la misma del ensayo del 9b, en un rincón de la caja),
-- sus contratos (15 cifras, 99999…), su carga de presiones de modelo (que tapa la del Plan dentro de esta transacción), sus usuarios sensibles y su sensor.
-- NO escribe en tablas de Comercial (cartera, catastro): la regla del nombre se prueba con textos, y la propuesta real solo se corre (y se deshace).
-- Mide con el volumen real y FALLA si una lectura pasa de 1 s o la afectación de 5 s. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 9b, Fase 2 … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes9f.adm@emdupar.gov.co';
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
  a text := 'prueba.redes9f.adm@emdupar.gov.co'; sd text := 'prueba.redes9f.dist@emdupar.gov.co'; op text := 'prueba.redes9f.op@emdupar.gov.co'; na text := 'prueba.redes9f.nada@emdupar.gov.co';
  v_carga bigint; v_c bigint; j jsonb; v_p jsonb; v_dan text; v_sen bigint; c1 text; c2 text; c3 text; v_real text; v_n integer;
  v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_ms4 numeric; v_ms5 numeric; v_info text := ''; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9B Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT9B Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT9B Operador daños', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT9B Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);

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
  perform pg_temp.reg('01.01 las 5 tablas existen sin permisos de la API; los hechos (usuarios sensibles, sus eventos y las lecturas) son de solo agregar',
     not has_table_privilege('service_role', 'redes.usuarios_sensibles', 'select') and not has_table_privilege('anon', 'redes.sensor_lecturas', 'select')
     and not has_table_privilege('service_role', 'redes.v_usuario_sensible', 'select')
     and (select count(*) from pg_trigger t where t.tgrelid in ('redes.usuarios_sensibles'::regclass, 'redes.usuario_sensible_eventos'::regclass, 'redes.sensor_lecturas'::regclass)
            and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 6);
  perform pg_temp.reg('01.02 las RPC nuevas: solo service_role; las internas: nadie de la API',
     has_function_privilege('service_role', 'public.geoportal_redes_afectacion(text,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_redes_sensibles(text,text,text,integer)', 'execute')
     and not has_function_privilege('service_role', 'redes.f_sensibles_proponer(text)', 'execute'));
  perform pg_temp.reg('01.03 la capa «Cortes programados vigentes» ya no sale en la lista del geovisor, pero sigue en la tabla con su nota',
     not exists (select 1 from jsonb_array_elements(public.geoportal_redes_geovisor(sd) -> 'capas') x where x ->> 'codigo' = 'cortes')
     and (select not activa and nota like 'Oculta%' from redes.geovisor_capas where codigo = 'cortes'));
  perform pg_temp.reg('01.04 tecnica.f_avisos no cambió: sigue con el bloque del 1b y sin presiones',
     position('D10 (Corte 9b, Fase 1b)' in pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) > 0
     and position('presion' in lower(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure))) = 0);

  -- ===================== 02. Alertas de presión (modelo) =====================
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, autor) values ('pm_nodos', 'zt9b_pm_nodos.csv', md5('zt9b' || clock_timestamp()::text), 6, 'ZT9B modelo de prueba', a) returning id into v_c;
  insert into redes.pm_nodos (carga_id, llave, nombre, geom, pres_exist_min, pres_exist_max, pres_futura_min, pres_futura_max) values
    (v_c, 'ZT9B-A', 'ZT9B A', pg_temp.pt(100, 0), 8, 30, 20, 40),      -- mínima bajo 10: roja
    (v_c, 'ZT9B-B', 'ZT9B B', pg_temp.pt(300, 0), 12, 40, 20, 40),     -- mínima bajo 15: naranja
    (v_c, 'ZT9B-C', 'ZT9B C', pg_temp.pt(500, 0), 20, 55, 20, 40),     -- máxima sobre 50: naranja
    (v_c, 'ZT9B-D', 'ZT9B D', pg_temp.pt(700, 0), 20, 65, 20, 70),     -- máxima sobre 60: roja (también en la futura)
    (v_c, 'ZT9B-H', 'ZT9B H', pg_temp.pt(500, 100), 25, 45, 25, 45),   -- en rango
    (v_c, 'ZT9B-E', 'ZT9B E', pg_temp.pt(300, 200), 30, 95, 30, 45);   -- sobre 60 y sobre la presión de trabajo del PVC (88)
  j := public.geoportal_redes_alertas_presion(sd);
  perform pg_temp.reg('02.01 red existente: 6 nodos; mínima roja 1 (A), mínima naranja 1 (B), máxima naranja 1 (C), máxima roja 2 (D y E); rotulada «de MODELO, no medida»',
     (j ->> 'cargado')::boolean and (j ->> 'nodos')::integer = 6 and j -> 'niveles' = '{"baja_roja": 1, "baja_naranja": 1, "alta_naranja": 1, "alta_roja": 2}'::jsonb
     and j ->> 'aviso' like '%MODELO%' and (j -> 'umbrales' ->> 'baja_naranja')::numeric = 15 and jsonb_array_length(j -> 'peores') = 5, j::text);
  perform pg_temp.reg('02.02 por material: el nodo E (95 m.c.a.) pasa la presión de trabajo del tramo T9 (PVC sin clase: 88), con la nota «por verificar»',
     (j -> 'por_material' ->> 'n')::integer = 1 and j -> 'por_material' -> 'nodos' -> 0 ->> 'tramo' = pg_temp.cod('T9')
     and (j -> 'por_material' -> 'nodos' -> 0 ->> 'presion_trabajo')::numeric = 88 and j -> 'por_material' ->> 'nota' like '%por verificar%', j ->> 'por_material');
  perform pg_temp.reg('02.03 red futura: solo D queda en rojo', public.geoportal_redes_alertas_presion(sd, 'futura') -> 'niveles' = '{"alta_roja": 1}'::jsonb);
  update redes.parametros set valor = 9 where clave = 'presion_baja_naranja_mca';
  update redes.parametros set valor = 7 where clave = 'presion_baja_roja_mca';
  perform pg_temp.reg('02.04 los umbrales son los parámetros editables: con 9 y 7 de mínima, A pasa a naranja y B queda en rango',
     public.geoportal_redes_alertas_presion(sd) -> 'niveles' = '{"baja_naranja": 1, "alta_naranja": 1, "alta_roja": 2}'::jsonb);
  update redes.parametros set valor = 15 where clave = 'presion_baja_naranja_mca';
  update redes.parametros set valor = 10 where clave = 'presion_baja_roja_mca';
  perform pg_temp.err('02.05 las alertas de presión son del supervisor: el operador no (42501)', format('select public.geoportal_redes_alertas_presion(%L)', op), '42501');
  perform pg_temp.err('02.06 un escenario que no existe', format('select public.geoportal_redes_alertas_presion(%L, %L)', sd, 'otra'), null, 'escenario');
  perform pg_temp.reg('02.07 la lista para Avisos está lista (5 nodos fuera de rango) pero NO conectada', (select sum(n) from redes.f_presion_para_avisos()) = 5);

  -- ===================== 03. Usuarios sensibles =====================
  perform pg_temp.reg('03.01 la regla del nombre: hospital, clínica (con tilde), institución educativa y bomberos se reconocen; una persona no',
     (select tipo || ':' || palabra from redes.f_sensible_tipo('Hospital Rosario Pumarejo')) = 'hospital:HOSPITAL'
     and (select tipo from redes.f_sensible_tipo('CLÍNICA DEL CESAR S.A.')) = 'clinica' and (select tipo from redes.f_sensible_tipo('institución educativa loperena')) = 'colegio'
     and (select tipo from redes.f_sensible_tipo('CUERPO DE BOMBEROS')) = 'otro' and not exists (select 1 from redes.f_sensible_tipo('JUAN PEREZ ESCUELAS'))
     and not exists (select 1 from redes.f_sensible_tipo(null))
     and (select tipo from redes.f_sensible_tipo('CDI Los Pequeñitos')) = 'colegio' and (select tipo from redes.f_sensible_tipo('Estación de Policía Centro')) = 'otro'
     and (select tipo from redes.f_sensible_tipo('Unidad de diálisis')) = 'clinica' and (select tipo from redes.f_sensible_tipo('EMDUPAR S.A. E.S.P. SEDE')) = 'sede_propia'
     and (select tipo from redes.f_sensible_tipo('Hogar geriátrico San José')) = 'otro'
     and not exists (select 1 from redes.f_sensible_tipo('IPS SALUD TOTAL')) and not exists (select 1 from redes.f_sensible_tipo('E.S.E. DEL NORTE')));
  perform pg_temp.err('03.02 la propuesta por el nombre solo la corre un administrador', format('select redes.f_sensibles_proponer(%L)', sd), '42501');
  v_t0 := clock_timestamp(); v_n := redes.f_sensibles_proponer(a); v_ms5 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  perform pg_temp.reg('03.03 la propuesta recorre la cartera de esta base y es repetible: la segunda vez no agrega nada; nunca guarda un nombre',
     v_n >= 0 and redes.f_sensibles_proponer(a) = 0 and not exists (select 1 from redes.usuarios_sensibles u where length(u.palabra) > 30), 'propuestos: ' || v_n);
  -- tres usuarios sensibles de prueba sobre contratos de la red ZT9B (como los dejaría la propuesta): dos en T4 y uno en T12
  select min(ct.contrato), max(ct.contrato) into c1, c2 from redes.contrato_tramo ct where ct.activo_id = pg_temp.id('T4');
  select min(ct.contrato) into c3 from redes.contrato_tramo ct where ct.activo_id = pg_temp.id('T12');
  insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor) values (c1, 'hospital', 'HOSPITAL', 'nombre', a), (c2, 'colegio', 'COLEGIO', 'nombre', a), (c3, 'clinica', 'CLINICA', 'nombre', a);
  j := public.geoportal_redes_sensibles(sd, 'por_confirmar', null, 500);
  perform pg_temp.reg('03.04 la bandeja del supervisor: los tres por confirmar, con su tipo, la palabra y su tramo; sin nombres',
     (select count(*) from jsonb_array_elements(j -> 'items') x where x ->> 'contrato' in (c1, c2, c3) and x ->> 'estado' = 'por_confirmar' and x ->> 'tramo' is not null) = 3
     and jsonb_array_length(j -> 'tipos') = 5 and (j -> 'totales' ->> 'por_confirmar')::integer >= 3, left(j::text, 300));
  perform pg_temp.err('03.05 la bandeja es del supervisor (42501 al operador)', format('select public.geoportal_redes_sensibles(%L)', op), '42501');
  j := public.geoportal_redes_sensible_fijar(sd, c1, 'confirmar');
  v_p := public.geoportal_redes_sensible_fijar(sd, c1, 'confirmar');
  perform pg_temp.reg('03.06 el supervisor confirma el hospital; repetirlo no cambia nada',
     j ->> 'estado' = 'confirmado' and not (v_p ->> 'cambio')::boolean and (select count(*) from redes.usuario_sensible_eventos where contrato = c1) = 1);
  perform pg_temp.err('03.07 descartar pide motivo', format('select public.geoportal_redes_sensible_fijar(%L, %L, %L)', sd, c2, 'descartar'), null, 'motivo');
  j := public.geoportal_redes_sensible_fijar(sd, c2, 'descartar', null, 'ZT9B no es un colegio, es una casa');
  v_p := public.geoportal_redes_sensible_fijar(sd, c3, 'confirmar', 'hospital');
  perform pg_temp.reg('03.08 descartar con motivo; y confirmar corrigiendo el tipo (la «clínica» era un hospital)',
     j ->> 'estado' = 'descartado' and v_p ->> 'tipo' = 'hospital'
     and (select tipo = 'hospital' and estado = 'confirmado' from redes.v_usuario_sensible where contrato = c3));
  perform pg_temp.err('03.09 agregar a mano un contrato que no está en el catastro: P0002',
     format('select public.geoportal_redes_sensible_fijar(%L, %L, %L, %L, %L)', sd, '999990000099999', 'confirmar', 'otro', 'ZT9B hogar de ancianos'), 'P0002');
  select c.cod_usuario into v_real from public.catastro_valledupar c
   where c.cod_usuario ~ '^[0-9]{1,15}$' and c.cod_usuario not in ('0', '99999999') and not exists (select 1 from redes.usuarios_sensibles u where u.contrato = c.cod_usuario) order by c.id limit 1;
  if v_real is not null then j := public.geoportal_redes_sensible_fijar(sd, v_real, 'confirmar', 'otro', 'ZT9B hogar de ancianos de prueba'); end if;
  perform pg_temp.reg('03.10 agregar a mano un contrato del catastro, con tipo y motivo: queda confirmado, de origen «manual»',
     v_real is null or (j ->> 'estado' = 'confirmado' and (select origen = 'manual' and palabra is null from redes.usuarios_sensibles where contrato = v_real)));
  perform pg_temp.err('03.11 solo agregar: no se cambia un usuario sensible', format('update redes.usuarios_sensibles set tipo = %L where contrato = %L', 'otro', c1));

  -- ===================== 04. Afectación del daño (usuarios sin servicio y sensibles) =====================
  v_p := public.geoportal_redes_preparar_dano(op, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_dan := public.geoportal_redes_crear_dano(op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           'activo', pg_temp.cod('T4'), 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(350),
           't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
           'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
  j := public.geoportal_redes_afectacion(op, v_dan);
  perform pg_temp.reg('04.01 sin válvulas cerradas: la propuesta sale de la simulación (entre 6 y 13 contratos) y trae el hospital confirmado de T4; el descartado no cuenta',
     j ->> 'fuente' = 'simulacion' and (j ->> 'contratos_min')::integer = 6 and (j ->> 'contratos_max')::integer = 13
     and (j -> 'sensibles' ->> 'confirmados')::integer = 1 and (j -> 'sensibles' ->> 'por_confirmar')::integer = 0
     and j -> 'sensibles' -> 'lista' -> 0 ->> 'contrato' = c1 and j::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n', j::text);
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V1'), 'cerrar', v_dan);
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V2'), 'cerrar', v_dan);
  j := public.geoportal_redes_afectacion(op, v_dan);
  perform pg_temp.reg('04.02 con V1 y V2 cerradas: lo real (2 válvulas, 1 zona, 6 contratos) y el hospital',
     j ->> 'fuente' = 'cierre_real' and (j ->> 'valvulas_cerradas')::integer = 2 and (j ->> 'zonas')::integer = 1 and (j ->> 'contratos')::integer = 6
     and (j -> 'sensibles' ->> 'confirmados')::integer = 1, j::text);
  perform pg_temp.err('04.03 un daño que no existe: P0002', format('select public.geoportal_redes_afectacion(%L, %L)', op, 'DAN-999999'), 'P0002');
  perform pg_temp.err('04.04 alguien sin Técnica no la ve (42501)', format('select public.geoportal_redes_afectacion(%L, %L)', na, v_dan), '42501');
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V1'), 'abrir');
  perform public.geoportal_redes_valvula_maniobra(op, pg_temp.cod('V2'), 'abrir');

  -- ===================== 05. Sensores (vacíos) =====================
  v_sen := pg_temp.activo('SENSOR', 'SEN', pg_temp.pt(300, 0));
  j := public.geoportal_redes_sensores(sd);
  perform pg_temp.reg('05.01 un sensor sin lecturas sale «por conectar», con su posición',
     (select x ->> 'estado' = 'por_conectar' and x ->> 'lat' is not null and x -> 'ultima' = 'null'::jsonb from jsonb_array_elements(j -> 'sensores') x where x ->> 'codigo' = (select codigo from redes.activos where id = v_sen)), j::text);
  insert into redes.sensor_lecturas (activo_id, variable, valor, unidad, medido_en, fuente) values (v_sen, 'presion', 22.5, 'm.c.a.', clock_timestamp() - interval '5 hours', 'ZT9B prueba');
  perform pg_temp.reg('05.02 con una lectura de hace 5 horas: «sin señal»; con una de ahora: «en línea»',
     redes.f_sensor_estado(v_sen) = 'sin_senal');
  insert into redes.sensor_lecturas (activo_id, variable, valor, unidad, medido_en, fuente) values (v_sen, 'presion', 23, 'm.c.a.', clock_timestamp(), 'ZT9B prueba');
  perform pg_temp.reg('05.03 … «en línea», y la lista trae la última lectura', redes.f_sensor_estado(v_sen) = 'en_linea'
     and (select (x -> 'ultima' ->> 'valor')::numeric = 23 from jsonb_array_elements(public.geoportal_redes_sensores(sd) -> 'sensores') x where x ->> 'codigo' = (select codigo from redes.activos where id = v_sen)));
  perform pg_temp.err('05.04 solo agregar: una lectura no se borra', format('delete from redes.sensor_lecturas where activo_id = %s', v_sen));

  -- ===================== 06. Tiempos con volumen real =====================
  insert into redes.pm_nodos (carga_id, llave, nombre, geom, pres_exist_min, pres_exist_max, pres_futura_min, pres_futura_max)
  select v_c, 'ZT9B-vol-' || i, 'ZT9B vol ' || i, pg_temp.pt(1000 + (i % 100) * 10, (i / 100) * 10), (i % 40), 20 + (i % 70), 10 + (i % 30), 30 + (i % 40) from generate_series(1, 7000) i;
  analyze redes.pm_nodos;
  v_t0 := clock_timestamp(); j := public.geoportal_redes_alertas_presion(sd); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_sensibles(sd, null, null, 500); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_afectacion(op, v_dan); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_sensores(sd); v_ms4 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS: alertas de presión con %s nodos %s ms · bandeja de sensibles %s ms · afectación de un daño (simulación sobre la red de esta base) %s ms · sensores %s ms · propuesta de sensibles sobre la cartera de esta base (%s filas; solo por psql o editor) %s ms',
                   j ->> 'nodos', v_ms1, v_ms2, v_ms3, v_ms4, (select count(*) from public.cartera_suscripcion), v_ms5);
  perform pg_temp.reg('06.01 TIEMPOS: las lecturas (alertas de presión, bandeja de sensibles, sensores) en menos de 1 s y la afectación en menos de 5 s',
     greatest(v_ms1, v_ms2, v_ms4) < 1000 and v_ms3 < 5000, v_info);
  perform pg_temp.reg('06.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 9b, Fase 2 (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
