-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes14.*), sus activos y nodos (ZT14, en un rincón de Valledupar), sus polígonos de
-- sector (número 94) y su carga de referencia del modelo (que tapa la del Plan dentro de esta transacción). Mide la ficha con los datos de la base donde corre
-- y FALLA si una ficha pasa de 1 s (en producción tardaba 4,4 s).
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 9a-bis … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4200 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.3000 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.caja(x0 numeric, y0 numeric, x1 numeric, y1 numeric) returns geometry language sql as $$
  select ST_SetSRID(ST_MakeEnvelope(pg_temp.lon(x0), pg_temp.lat(y0), pg_temp.lon(x1), pg_temp.lat(y1)), 4326) $$;
create function pg_temp.activo(p_prefijo text, p_geom geometry, p_capa text, p_llave text, p_clase text default null, p_attr jsonb default '{}'::jsonb, p_nombre text default null)
returns text language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes14.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, estado_codigo, atributos, codigo_anterior, capa_codigo, llave_capa, huella, autor)
  values (v_id, 1, p_geom, coalesce(p_nombre, 'ZT14 ' || p_prefijo), p_clase, case when p_prefijo = 'VAL' then 'sin_definir' end,
          case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end, case when p_prefijo = 'RED' then 110 end,
          'en_operacion', p_attr, p_llave, p_capa, p_llave, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT14 activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_cod;
end $$;
create function pg_temp.id(p_codigo text) returns bigint language sql as $$ select id from redes.activos where codigo = p_codigo $$;
create function pg_temp.archivo(p_ruta text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg')) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
-- un daño de prueba del operador (con su foto); devuelve el código
create function pg_temp.dano(p_op text, p_datos jsonb) returns text language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_dano(p_op, 1);
begin
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  return public.geoportal_redes_crear_dano(p_op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
           'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))) || p_datos) ->> 'codigo';
end $$;

do $prueba$
declare
  a text := 'prueba.redes14.adm@emdupar.gov.co'; sd text := 'prueba.redes14.dist@emdupar.gov.co'; sv text := 'prueba.redes14.planta@emdupar.gov.co';
  op text := 'prueba.redes14.op@emdupar.gov.co'; opp text := 'prueba.redes14.opplanta@emdupar.gov.co'; na text := 'prueba.redes14.nada@emdupar.gov.co';
  v_r jsonb; v_x jsonb; v_c bigint; v_carga bigint; v_huella text;
  v_sec text; v_sub text; v_red text; v_val text; v_red2 text;
  n_val bigint; n_s1 bigint; n_s2 bigint; n_s3 bigint; n_m1 bigint; n_j1 bigint; n_fin bigint; v_act0 bigint; v_ev0 bigint;
  v_dano text; v_rep uuid; v_codigo text; v_cod_real text; v_cod_real2 text;
  v_t0 timestamptz; v_ms_val numeric; v_ms_red numeric; v_ms_real numeric; v_ms_real2 numeric; v_ms_tn numeric; v_ms_bandeja numeric; v_ms_grupo numeric; v_ms_sec numeric;
  v_info text; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT14 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT14 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT14 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT14 Operador de redes', 'consulta', true, 'sin_restriccion', 'todos'),
    (opp, 'ZT14 Operador de planta', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT14 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a), (opp, 'asignar_formulario', 'muestreo', a);

  -- ===================== 01. Esquema, permisos y lo que no cambia =====================
  perform pg_temp.reg('01.01 las 5 funciones internas nuevas no las ejecuta la API; las 2 RPC nuevas, solo service_role (security definer)',
     not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname in ('f_nodo_visible_id', 'f_nodo_de_activo', 'f_tramos_de_nodo', 'f_sector_en', 'f_operador_redes')
                   and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')))
     and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_sector_en', 'geoportal_redes_nodos_clasificar_grupo')
            and p.prosecdef and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')) = 2);
  perform pg_temp.reg('01.02 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
     not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion || ' → ' || sentencia, ' | ') from redes.f_funciones_sin_where()));
  perform pg_temp.reg('01.03 ninguna función de redes busca en las vistas de nodos o de tramos por una columna que no es su llave (lo que recorría las tablas enteras)',
     not exists (select 1 from pg_proc p where (p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
                  and (p.prosrc ~ 'v_tramo_nodos_vigente' or p.prosrc ~ 'v_nodo_visible n where n\.(nodo_id|activo_id) =' or p.prosrc ~ 'v_nodo_visible where nodo_id =')));
  perform pg_temp.reg('01.04 «sector_plan» ya no sale en ninguna función (el sector hidráulico es el oficial) y la capa lo dice',
     not exists (select 1 from pg_proc p where (p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) and p.prosrc ~ '''sector_plan''')
     and (select nota from redes.geovisor_capas where codigo = 'sectores') like '7 sectores y 29 subsectores con que se opera%');
  perform pg_temp.reg('01.05 la ficha, el minimapa y el sector de un punto siguen siendo de solo lectura (STABLE)',
     (select count(*) from pg_proc p where p.provolatile = 's' and ((p.pronamespace = 'redes'::regnamespace and p.proname in ('f_ficha', 'f_nodo_visible_id', 'f_nodo_de_activo', 'f_tramos_de_nodo', 'f_sector_en'))
        or (p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_activo', 'geoportal_redes_tramo_nodos', 'geoportal_redes_sector_en', 'geoportal_redes_nodo_preliminar')))) = 9);

  -- ===================== 02. La ficha por índice: lo mismo que antes, sin recorrer tablas =====================
  v_sec := pg_temp.activo('SEC', pg_temp.caja(0, 0, 400, 200), 'sectores', 'ZT14-SECTOR-94', 'sector', '{"modelo": {"sector": 94}}', 'ZT14 Sector 94');
  v_sub := pg_temp.activo('SEC', pg_temp.caja(0, 0, 200, 200), 'sectores', 'ZT14-SUB-94.1', 'subsector', '{"modelo": {"sector": 94, "subsector": "94.1"}}', 'ZT14 Subsector 94.1');
  v_red := pg_temp.activo('RED', ST_SetSRID(ST_MakeLine(pg_temp.pt(40, 50), pg_temp.pt(100, 50)), 4326), 'acueducto', 'ZT14-T1');
  v_red2 := pg_temp.activo('RED', ST_SetSRID(ST_MakeLine(pg_temp.pt(100, 50), pg_temp.pt(160, 50)), 4326), 'acueducto', 'ZT14-T2');
  v_val := pg_temp.activo('VAL', pg_temp.pt(40, 50), 'acueducto_nodos', 'ZT14-N1', 'cierre');
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor) values ('acueducto', md5('zt14a') || md5('zt14b'), 'shp', 4326, 'ID', 1, 'ZT14 nodos de prueba', a) returning id into v_carga;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values ('acueducto', 'ZT14-N1', 'ZT14V1', 'activo', pg_temp.pt(40, 50), pg_temp.id(v_val), 0, v_carga) returning id into n_val;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values ('acueducto', 'ZT14-S1', 'ZT14S-1', 'por_clasificar', pg_temp.pt(100, 50), null, 0, v_carga) returning id into n_s1;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values ('acueducto', 'ZT14-S2', 'ZT14S-2', 'por_clasificar', pg_temp.pt(120, 60), null, 0, v_carga) returning id into n_s2;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values ('acueducto', 'ZT14-S3', 'ZT14S-3', 'por_clasificar', pg_temp.pt(900, 900), null, 0, v_carga) returning id into n_s3;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values ('acueducto', 'ZT14-M1', 'ZT14M-1', 'por_clasificar', pg_temp.pt(140, 60), null, 0, v_carga) returning id into n_m1;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values ('acueducto', 'ZT14-J1', 'ZT14J-1', 'por_clasificar', pg_temp.pt(150, 60), null, 0, v_carga) returning id into n_j1;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values ('acueducto', 'ZT14-F1', 'ZT14F-1', 'por_clasificar', pg_temp.pt(160, 50), null, 0, v_carga) returning id into n_fin;
  insert into redes.tramo_nodos (activo_id, version, nodo_ini, nodo_fin, metodo, carga_id) values (pg_temp.id(v_red), 1, n_val, n_s1, 'modelo', v_carga), (pg_temp.id(v_red2), 1, n_s1, n_fin, 'modelo', v_carga);
  v_r := public.geoportal_redes_activo(sd, v_val);
  perform pg_temp.reg('02.01 la ficha de la válvula encuentra su nodo (por índice) y cuenta el tramo que le llega',
     v_r -> 'nodo' ->> 'nombre_modelo' = 'ZT14V1' and (v_r -> 'nodo' ->> 'tramos')::integer = 1, (v_r -> 'nodo')::text);
  v_r := public.geoportal_redes_activo(sd, v_red);
  perform pg_temp.reg('02.02 la ficha del tramo trae sus dos extremos: la válvula (con su activo) y el nodo sin activo',
     v_r -> 'tramo' ->> 'metodo' = 'modelo' and v_r -> 'tramo' -> 'inicio' -> 'activo' ->> 'codigo' = v_val and v_r -> 'tramo' -> 'fin' ->> 'nombre' = 'ZT14S-1' and not (v_r -> 'tramo' -> 'fin' ? 'activo'),
     (v_r -> 'tramo')::text);
  perform pg_temp.reg('02.03 nodo y extremos dan EXACTAMENTE lo mismo que la forma anterior (por las vistas), en los activos de prueba y en 30 activos reales',
     not exists (
       select 1 from (select pg_temp.id(c) as activo_id from unnest(array[v_val, v_red, v_red2]) c
                      union all (select activo_id from redes.activo_vigente_mat where prefijo in ('VAL', 'TOR', 'RED', 'POZ', 'COL', 'TAN') and coalesce(llave_capa, '') not like 'ZT14%' order by md5(activo_id::text) limit 30)) m
        where (select jsonb_build_object('n', n.nombre_visible, 't', (select count(*) from redes.v_tramo_nodos_vigente x where x.nodo_ini = n.nodo_id or x.nodo_fin = n.nodo_id))
                 from redes.v_nodo_visible n where n.activo_id = m.activo_id limit 1)
              is distinct from (select jsonb_build_object('n', n.nombre_visible, 't', redes.f_tramos_de_nodo(n.nodo_id)) from redes.f_nodo_de_activo(m.activo_id) n limit 1)
           or (select jsonb_build_object('i', (select n.nombre_visible || coalesce(n.activo_id::text, '') from redes.v_nodo_visible n where n.nodo_id = tn.nodo_ini),
                                         'f', (select n.nombre_visible || coalesce(n.activo_id::text, '') from redes.v_nodo_visible n where n.nodo_id = tn.nodo_fin))
                 from redes.v_tramo_nodos_vigente tn where tn.activo_id = m.activo_id)
              is distinct from (select jsonb_build_object('i', (select n.nombre_visible || coalesce(n.activo_id::text, '') from redes.f_nodo_visible_id(tn.nodo_ini) n),
                                                          'f', (select n.nombre_visible || coalesce(n.activo_id::text, '') from redes.f_nodo_visible_id(tn.nodo_fin) n))
                                  from redes.tramo_nodos tn join redes.activo_vigente_mat tv on tv.activo_id = tn.activo_id and tv.version = tn.version where tn.activo_id = m.activo_id)));
  v_r := public.geoportal_redes_tramo_nodos(op, v_red);
  perform pg_temp.reg('02.04 el minimapa (tramo_nodos) trae los dos nodos del tramo, como antes', jsonb_array_length(v_r -> 'nodos') = 2
     and v_r -> 'nodos' -> 0 ->> 'rol' = 'inicio' and v_r -> 'nodos' -> 0 -> 'activo' ->> 'codigo' = v_val and v_r -> 'nodos' -> 1 ->> 'nombre' = 'ZT14S-1', (v_r -> 'nodos')::text);
  perform pg_temp.reg('02.05 un nodo enlazado a un activo desde la bandeja (evento, no carga) también lo encuentra la ficha',
     (select count(*) from redes.f_nodo_de_activo(pg_temp.id(v_val))) = 1);

  -- ===================== 03. El sector hidráulico es el oficial =====================
  v_r := public.geoportal_redes_activo(op, v_red);
  perform pg_temp.reg('03.01 la ficha trae «sector_hidraulico» (94, 94.1), también para el operador; «sector_plan» ya no sale',
     v_r -> 'sector_hidraulico' ->> 'sector' = '94' and v_r -> 'sector_hidraulico' ->> 'subsector' = '94.1' and not (v_r ? 'sector_plan'), (v_r -> 'sector_hidraulico')::text);
  perform pg_temp.reg('03.02 los datos del modelo y la referencia del Plan son solo para supervisor y administrador: el operador no los recibe',
     not (public.geoportal_redes_activo(op, v_red) ? 'referencia') and not (public.geoportal_redes_activo(op, v_red) ? 'modelo'));
  v_r := public.geoportal_redes_sector_en(op, pg_temp.lat(50), pg_temp.lon(50));
  perform pg_temp.reg('03.03 «sector_en» da el sector de un punto (94, 94.1); fuera de los polígonos, vacío', v_r ->> 'sector' = '94' and v_r ->> 'subsector' = '94.1'
     and public.geoportal_redes_sector_en(op, pg_temp.lat(900), pg_temp.lon(900)) ->> 'sector' is null, v_r::text);
  perform pg_temp.err('03.04 «sector_en» exige una posición válida', format('select public.geoportal_redes_sector_en(%L, 200, 0)', op), null, 'La posición no es válida');
  perform pg_temp.err('03.05 … y ser de Técnica', format('select public.geoportal_redes_sector_en(%L, 10.4, -73.2)', na), '42501');
  v_dano := pg_temp.dano(op, jsonb_build_object('activo', v_red, 'lat', pg_temp.lat(50), 'lon', pg_temp.lon(50)));
  perform pg_temp.reg('03.06 un daño sin sector escrito toma el sector de su ubicación (94)', (select sector_num from redes.danos where codigo = v_dano) = 94);
  v_dano := pg_temp.dano(op, jsonb_build_object('activo', v_red, 'lat', pg_temp.lat(50), 'lon', pg_temp.lon(50), 'sector', 9));
  perform pg_temp.reg('03.07 si el sector viene escrito (respaldo), se guarda el escrito (9)', (select sector_num from redes.danos where codigo = v_dano) = 9);
  v_x := (select d from jsonb_array_elements(public.geoportal_redes_danos(sd, 'todos', 300) -> 'danos') d where d ->> 'codigo' = v_dano);
  perform pg_temp.reg('03.08 la lista de daños trae el sector guardado (9) y, al lado, el hidráulico de la ubicación (94)', v_x ->> 'sector' = '9' and v_x -> 'sector_hidraulico' ->> 'sector' = '94', v_x::text);
  v_dano := pg_temp.dano(op, jsonb_build_object('no_identificado', 'ZT14 tubo sin identificar', 'lat', pg_temp.lat(900), 'lon', pg_temp.lon(900)));
  perform pg_temp.reg('03.09 un daño fuera de todos los sectores y sin número escrito queda sin sector (no se inventa)', (select sector_num from redes.danos where codigo = v_dano) is null);
  v_rep := redes.f_reporte_externo_recibir(jsonb_build_object('radicado', 'ZT14-REP-1', 'canal', 'telegram', 'tipo', 'fuga', 'lat', pg_temp.lat(60), 'lon', pg_temp.lon(60)));
  v_codigo := public.geoportal_redes_reporte_convertir(sd, v_rep, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'riesgo', 'medio')) ->> 'dano_codigo';
  perform pg_temp.reg('03.10 el daño que entra del bot también toma el sector de su ubicación (94)', (select sector_num from redes.danos where codigo = v_codigo) = 94, v_codigo);
  perform pg_temp.reg('03.11 la tarjeta de referencia rotula «Sector hidráulico» (ya no «según el Plan»)',
     (select prosrc from pg_proc where proname = 'geoportal_redes_referencia' and pronamespace = 'public'::regnamespace) like '%''Sector hidráulico''%'
     and (select prosrc from pg_proc where proname = 'geoportal_redes_referencia' and pronamespace = 'public'::regnamespace) not like '%según el Plan%');

  -- ===================== 04. Nodos: también el supervisor de distribución =====================
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, autor) values ('pm_nodos', 'zt14_pm_nodos.csv', md5('zt14' || clock_timestamp()::text), 6, 'ZT14 origen de prueba', a) returning id into v_c;
  insert into redes.pm_nodos (carga_id, llave, nombre, tipo, que_es, zona_modelo, activo_modelo, estado_modelo, estado_difiere, geom) values
    (v_c, 'ZT14-S1', 'ZT14S-1', 'válvula', 'válvula de sectorización propuesta (no instalada)', 'Proyectado', true, 'proyectado', false, pg_temp.pt(100, 50)),
    (v_c, 'ZT14-S2', 'ZT14S-2', 'válvula', 'válvula de sectorización propuesta (no instalada)', 'Proyectado', true, 'proyectado', false, pg_temp.pt(120, 60)),
    (v_c, 'ZT14-S3', 'ZT14S-3', 'válvula', 'válvula de sectorización propuesta (no instalada)', 'Proyectado', true, 'proyectado', false, pg_temp.pt(900, 900)),
    (v_c, 'ZT14-M1', 'ZT14M-1', 'válvula', 'macromedidor proyectado', 'Proyectado', true, 'proyectado', false, pg_temp.pt(140, 60)),
    (v_c, 'ZT14-J1', 'ZT14J-1', 'unión', 'nodo de cálculo J-…', null, true, 'en_operacion', false, pg_temp.pt(150, 60)),
    (v_c, 'ZT14-F1', 'ZT14F-1', 'unión', 'nodo de cálculo J-…', null, true, 'en_operacion', false, pg_temp.pt(160, 50));
  v_r := public.geoportal_redes_nodos_por_clasificar(sd, 'zt14', null, 50);
  perform pg_temp.reg('04.01 el supervisor de distribución ve la bandeja de nodos (respuesta 1 de David) y la bandeja trae los grupos de «no crear activo»',
     (v_r ->> 'total')::integer = 6 and (select (g ->> 'n')::integer from jsonb_array_elements(v_r -> 'grupos_no_crear') g where g ->> 'grupo' = 'valvula_propuesta') = 3
     and (select (g ->> 'n')::integer from jsonb_array_elements(v_r -> 'grupos_no_crear') g where g ->> 'grupo' = 'macro_proyectado') = 1
     and not exists (select 1 from jsonb_array_elements(v_r -> 'grupos_no_crear') g where g ->> 'grupo' is null), (v_r -> 'grupos_no_crear')::text);
  perform pg_temp.reg('04.02 la sugerencia trae su grupo (válvula propuesta, macromedidor o tanque proyectado); las de «dejar como nodo» no tienen grupo',
     redes.f_pm_sugerencia('válvula', 'válvula de sectorización propuesta (no instalada)', 'S1-1', 'Proyectado') ->> 'grupo' = 'valvula_propuesta'
     and redes.f_pm_sugerencia('tanque', 'tanque', 'Módulo 4 Proyectado La Popa', 'Proyectado') ->> 'grupo' = 'tanque_proyectado'
     and redes.f_pm_sugerencia('válvula', 'macromedidor proyectado', 'M-1', 'Proyectado') ->> 'grupo' = 'macro_proyectado'
     and not (redes.f_pm_sugerencia('unión', 'nodo de cálculo J-…', 'J-1', null) ? 'grupo'));
  perform pg_temp.reg('04.03 el supervisor abre la ficha preliminar de un nodo (por índice)', public.geoportal_redes_nodo_preliminar(sd, n_s1) ->> 'nombre_modelo' = 'ZT14S-1');
  perform public.geoportal_redes_nodo_clasificar(sd, n_j1, 'nodo_calculo', 'ZT14 nodo de cálculo del modelo');
  perform pg_temp.reg('04.04 el supervisor clasifica un nodo (evento con su autor)', (select tipo || '|' || clase || '|' || autor from redes.nodo_eventos where nodo_id = n_j1 order by id desc limit 1) = 'clasificar|nodo_calculo|' || sd);
  v_r := public.geoportal_redes_nodo_crear_activo(sd, n_fin, 'VAL', 'cierre', null, 'ZT14 la válvula sí existe en campo');
  perform pg_temp.reg('04.05 el supervisor crea el activo de un nodo y queda enlazado', v_r ->> 'activo' like 'VAL-%' and (select clase_nodo from redes.v_nodo_vigente where nodo_id = n_fin) = 'activo');
  perform pg_temp.reg('04.06 la ficha del activo recién creado desde el nodo encuentra su nodo (enlazado por evento)', public.geoportal_redes_activo(sd, v_r ->> 'activo') -> 'nodo' ->> 'nombre_modelo' = 'ZT14F-1');
  perform pg_temp.err('04.07 el operador no ve la bandeja', format('select public.geoportal_redes_nodos_por_clasificar(%L)', op), '42501');
  perform pg_temp.err('04.08 … ni clasifica', format('select public.geoportal_redes_nodo_clasificar(%L, %s, %L, %L)', op, n_s2, 'propuesta_plan', 'ZT14 no debe poder'), '42501');
  perform pg_temp.err('04.09 … ni crea el activo de un nodo', format('select public.geoportal_redes_nodo_crear_activo(%L, %s, %L, %L, %L, %L)', op, n_s2, 'VAL', 'cierre', null, 'ZT14 no debe poder'), '42501');
  perform pg_temp.err('04.10 el supervisor de planta (operador en redes) tampoco', format('select public.geoportal_redes_nodos_por_clasificar(%L)', sv), '42501');
  perform pg_temp.err('04.11 el nombre visible de un nodo (catálogo, N-12) sigue siendo solo del administrador', format('select public.geoportal_redes_alias_fijar(%L, %L, %L, %L, %L)', sd, 'nodo', n_s2::text, 'ZT14 nombre', 'ZT14 no debe poder'), '42501');

  -- ===================== 05. Confirmar por grupo (solo «no crear activo»), con vista previa y motivo =====================
  v_r := public.geoportal_redes_nodos_clasificar_grupo(sd, 'valvula_propuesta');
  v_huella := v_r ->> 'huella';
  perform pg_temp.reg('05.01 la vista previa no escribe nada y dice cuántos (3), cuáles y en qué sectores (2 en el 94 y 1 fuera), con la huella del grupo',
     (v_r ->> 'vista_previa')::boolean and (v_r ->> 'n')::integer = 3 and jsonb_array_length(v_r -> 'muestra') = 3 and v_r ->> 'clase' = 'propuesta_plan' and length(v_huella) = 32
     and (select (s ->> 'n')::integer from jsonb_array_elements(v_r -> 'por_sector') s where s ->> 'sector' = '94') = 2
     and (select (s ->> 'n')::integer from jsonb_array_elements(v_r -> 'por_sector') s where s -> 'sector' = 'null'::jsonb) = 1
     and not exists (select 1 from redes.nodo_eventos where nodo_id in (n_s1, n_s2, n_s3)), v_r::text);
  perform pg_temp.err('05.02 solo se confirman por grupo los de «no crear activo»', format('select public.geoportal_redes_nodos_clasificar_grupo(%L, %L)', sd, 'dejar_nodo'), null, 'solo se confirman los de «no crear activo»');
  perform pg_temp.err('05.03 confirmar exige el motivo', format('select public.geoportal_redes_nodos_clasificar_grupo(%L, %L, %L, %L)', sd, 'valvula_propuesta', v_huella, 'corto'), null, 'Escriba el motivo');
  perform pg_temp.err('05.04 con una huella que no es la de la vista previa, se niega', format('select public.geoportal_redes_nodos_clasificar_grupo(%L, %L, %L, %L)', sd, 'valvula_propuesta', md5('otra'), 'ZT14 válvulas que no se instalaron'),
     null, 'El grupo cambió desde la vista previa');
  perform pg_temp.err('05.05 el operador no confirma grupos', format('select public.geoportal_redes_nodos_clasificar_grupo(%L, %L)', op, 'valvula_propuesta'), '42501');
  -- alguien clasifica uno del grupo entre la vista previa y la confirmación: el grupo cambió y se niega
  perform public.geoportal_redes_nodo_clasificar(a, n_s3, 'propuesta_plan', 'ZT14 una del grupo, de una en una');
  perform pg_temp.err('05.06 si el grupo cambió después de la vista previa (alguien clasificó uno), se niega y no escribe nada',
     format('select public.geoportal_redes_nodos_clasificar_grupo(%L, %L, %L, %L)', sd, 'valvula_propuesta', v_huella, 'ZT14 válvulas que no se instalaron'), null, 'El grupo cambió desde la vista previa');
  select count(*) into v_ev0 from redes.nodo_eventos;
  select count(*) into v_act0 from redes.activos;
  v_r := public.geoportal_redes_nodos_clasificar_grupo(sd, 'valvula_propuesta');
  v_x := public.geoportal_redes_nodos_clasificar_grupo(sd, 'valvula_propuesta', v_r ->> 'huella', 'ZT14 válvulas de sectorización que el Plan propuso y no se instalaron');
  perform pg_temp.reg('05.07 con la vista previa nueva, confirmar clasifica los 2 que quedaban: un evento por nodo con el motivo y su autor, ningún activo nuevo, y la auditoría',
     (v_x ->> 'n')::integer = 2 and (select count(*) from redes.nodo_eventos) = v_ev0 + 2 and (select count(*) from redes.activos) = v_act0
     and (select count(*) from redes.v_nodo_vigente where nodo_id in (n_s1, n_s2) and clase_nodo = 'propuesta_plan') = 2
     and (select count(*) from redes.nodo_eventos where nodo_id in (n_s1, n_s2) and autor = sd and motivo like 'ZT14 válvulas de sectorización%') = 2
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_nodos_clasificar_grupo' and email = sd and (detalle ->> 'n')::integer = 2), v_x::text);
  perform pg_temp.reg('05.08 los otros grupos no se tocaron (el macromedidor proyectado sigue por clasificar)', (select clase_nodo from redes.v_nodo_vigente where nodo_id = n_m1) = 'por_clasificar');
  perform pg_temp.reg('05.09 el grupo queda vacío: la vista previa da 0', (public.geoportal_redes_nodos_clasificar_grupo(sd, 'valvula_propuesta') ->> 'n')::integer = 0);
  perform pg_temp.err('05.10 confirmar un grupo vacío se niega', format('select public.geoportal_redes_nodos_clasificar_grupo(%L, %L, %L, %L)', sd, 'valvula_propuesta', md5(''), 'ZT14 otra vez el mismo grupo'), null, 'No quedan nodos en ese grupo');

  -- ===================== 06. La Ficha de activos en modo buscar para el operador de redes =====================
  perform pg_temp.reg('06.01 «ficha_buscar»: sí para el administrador, el supervisor de distribución y el operador de redes (con un formulario de distribución)',
     (public.geoportal_redes_mi_perfil(a) ->> 'ficha_buscar')::boolean and (public.geoportal_redes_mi_perfil(sd) ->> 'ficha_buscar')::boolean and (public.geoportal_redes_mi_perfil(op) ->> 'ficha_buscar')::boolean);
  perform pg_temp.reg('06.02 … y no para el operador de planta (solo Muestreo)', (public.geoportal_redes_mi_perfil(opp) ->> 'ficha_buscar')::boolean = false);
  perform public.geoportal_redes_personal_fijar(sd, opp, 'area', 'distribucion', 'ZT14 pasa a trabajar en distribución');
  perform pg_temp.reg('06.03 con el área «distribución» en Personal, ese operador también la ve', (public.geoportal_redes_mi_perfil(opp) ->> 'ficha_buscar')::boolean);
  v_r := public.geoportal_redes_perfil(op, v_val);
  perform pg_temp.reg('06.04 en modo buscar el operador ve la ficha sin poder editarla (sin origen, sin modelo ni referencia del Plan)', (v_r ->> 'editable')::boolean = false and not (v_r ? 'edicion')
     and public.geoportal_redes_activo(op, v_val) ->> 'perfil' = 'operador' and not (public.geoportal_redes_activo(op, v_val) ? 'origen'));
  perform pg_temp.err('06.05 el operador no edita la ficha', format('select public.geoportal_redes_ficha_editar(%L, %L, %L::jsonb, %L)', op, v_val, '{"nombre": "ZT14"}', 'ZT14 no debe poder editar'), '42501');

  -- ===================== 07. Tiempos con los datos de esta base (en producción, el volumen real). La ficha FALLA si pasa de 1 s =====================
  select m.codigo into v_cod_real from redes.activo_vigente_mat m join redes.nodos n on n.activo_id = m.activo_id where m.prefijo = 'VAL' and coalesce(m.llave_capa, '') not like 'ZT14%' order by m.activo_id limit 1;
  select m.codigo into v_cod_real2 from redes.activo_vigente_mat m join redes.tramo_nodos t on t.activo_id = m.activo_id and t.version = m.version where m.prefijo = 'RED' and coalesce(m.llave_capa, '') not like 'ZT14%' order by m.activo_id limit 1;
  v_t0 := clock_timestamp(); perform public.geoportal_redes_activo(sd, v_val); v_ms_val := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_activo(sd, v_red); v_ms_red := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_activo(sd, coalesce(v_cod_real, v_val)); v_ms_real := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_activo(sd, coalesce(v_cod_real2, v_red)); v_ms_real2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_tramo_nodos(op, coalesce(v_cod_real2, v_red)); v_ms_tn := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_sector_en(op, pg_temp.lat(50), pg_temp.lon(50)); v_ms_sec := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_nodos_por_clasificar(sd, null, null, 50); v_ms_bandeja := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_nodos_clasificar_grupo(sd, 'macro_proyectado'); v_ms_grupo := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS: ficha de una válvula %s ms y de un tramo %s ms (de prueba) · ficha de una válvula real (%s) %s ms y de un tramo real (%s) %s ms · minimapa de un tramo %s ms · sector de un punto %s ms · bandeja de nodos %s ms · vista previa de un grupo %s ms',
                   v_ms_val, v_ms_red, coalesce(v_cod_real, '—'), v_ms_real, coalesce(v_cod_real2, '—'), v_ms_real2, v_ms_tn, v_ms_sec, v_ms_bandeja, v_ms_grupo);
  perform pg_temp.reg('07.01 la ficha responde en menos de 1 s (antes, 4,4 s en producción): válvula y tramo de prueba y reales de esta base', greatest(v_ms_val, v_ms_red, v_ms_real, v_ms_real2) < 1000, v_info);
  perform pg_temp.reg('07.02 el minimapa y el sector de un punto, en menos de 1 s', greatest(v_ms_tn, v_ms_sec) < 1000, v_info);
  perform pg_temp.reg('07.03 la bandeja de nodos y la vista previa de un grupo, en menos de 8 s (el tope más corto de las peticiones)', greatest(v_ms_bandeja, v_ms_grupo) < 8000, v_info);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 9a-bis (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
