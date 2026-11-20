-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- Todo es SIMULADO y se deshace: sus personas (prueba.evc.*), una red de prueba ZTEVC en un rincón de la caja (4 tramos y 2 sectores), 5 contratos de
-- prueba (99999999000x; uno sin amarre), un daño, y eventos declarados con las RPC publicadas del Corte 15: círculo, sectores, planta y toda la ciudad.
-- Nunca toca un evento real: los que hubiera abiertos en la base se tienen en cuenta solo para los tiempos.
-- Mide la consulta con 300 eventos viejos cerrados, 5 abiertos (dos sobre la red real) y 200 contratos reales, y FALLA si uno pasa de 150 ms (la meta).
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · aviso de evento por contrato … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.1300 + y * 0.0000090437, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.5800 + x * 0.0000091290, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.caja(x1 numeric, y1 numeric, x2 numeric, y2 numeric) returns geometry language sql as $$
  select ST_Multi(ST_MakeEnvelope(pg_temp.lon(x1), pg_temp.lat(y1), pg_temp.lon(x2), pg_temp.lat(y2), 4326)) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
create temp table _zt (nombre text primary key, activo_id bigint, codigo text);
-- un activo de prueba (versión 1)
create function pg_temp.activo(p_nombre text, p_prefijo text, p_geom geometry, p_clase text default null) returns text language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.evc.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZTEVC ' || p_nombre, p_clase, case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end,
          case when p_prefijo = 'RED' then 110 end, 'en_operacion', '{}'::jsonb, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZTEVC activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  insert into _zt values (p_nombre, v_id, v_cod);
  return v_cod;
end $$;
create function pg_temp.cod(p_nombre text) returns text language sql as $$ select codigo from _zt where nombre = p_nombre $$;
-- la respuesta, como la pide la Edge
create function pg_temp.ev(p_quien text, p_contrato text) returns jsonb language sql as $$ select public.geoportal_redes_evento_contrato(p_quien, p_contrato) $$;
create function pg_temp.claves(j jsonb) returns text language sql as $$ select string_agg(k, ',' order by k) from jsonb_object_keys(j) k $$;

do $prueba$
declare
  adm text := 'prueba.evc.adm@emdupar.gov.co'; co text := 'prueba.evc.comercial@emdupar.gov.co'; ca text := 'prueba.evc.campo@emdupar.gov.co'; dc text := 'prueba.evc.supcampo@emdupar.gov.co';
  sd text := 'prueba.evc.sd@emdupar.gov.co'; sp text := 'prueba.evc.sp@emdupar.gov.co'; op text := 'prueba.evc.op@emdupar.gov.co'; ex text := 'prueba.evc.explorar@emdupar.gov.co';
  ac text := 'prueba.evc.acta@emdupar.gov.co';
  c1 text := '999999990001'; c2 text := '999999990002'; c3 text := '999999990003'; c4 text := '999999990004'; c5 text := '999999990005';
  j jsonb; j2 jsonb; v_dan text; e1 text; e2 text; e3 text; e4 text; v_reg timestamptz; v_reg2 timestamptz; v_aud bigint; v_n integer; v_txt text;
  v_t0 timestamptz; v_ms numeric; v_tiempos numeric[] := '{}'; v_max numeric; v_p95 numeric; v_med numeric; v_ct text; v_info text; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTEVC Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_comercial, horario, dias) values (co, 'ZTEVC Comercial', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values (ca, 'ZTEVC Formularios de campo', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_dashboard_campo, horario, dias) values (dc, 'ZTEVC Supervisor de campo', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZTEVC Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZTEVC Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZTEVC Operador', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_explorar, horario, dias) values (ex, 'ZTEVC Explorar', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_acta, horario, dias) values (ac, 'ZTEVC Actas', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', adm);
  -- la red de prueba: 4 tramos separados y 2 sectores (S1 cubre T1 y T2; S2 cubre T3); T4 queda por fuera de todo
  perform pg_temp.activo('T1', 'RED', ST_MakeLine(pg_temp.pt(0, 0), pg_temp.pt(100, 0)));
  perform pg_temp.activo('T2', 'RED', ST_MakeLine(pg_temp.pt(500, 0), pg_temp.pt(600, 0)));
  perform pg_temp.activo('T3', 'RED', ST_MakeLine(pg_temp.pt(1500, 0), pg_temp.pt(1600, 0)));
  perform pg_temp.activo('T4', 'RED', ST_MakeLine(pg_temp.pt(2500, 0), pg_temp.pt(2600, 0)));
  perform pg_temp.activo('S1', 'SEC', pg_temp.caja(-50, -50, 700, 50), 'sector');
  perform pg_temp.activo('S2', 'SEC', pg_temp.caja(1400, -50, 1700, 50), 'subsector');
  insert into redes.contrato_tramo (contrato, activo_id, distancia_m, metodo)
  select x.c, z.activo_id, 4, 'cercania' from (values (c1, 'T1'), (c2, 'T2'), (c3, 'T3'), (c4, 'T4')) x(c, t) join _zt z on z.nombre = x.t;      -- c5: sin amarre

  -- ===================== 01. Quién consulta =====================
  perform pg_temp.reg('01.01 consultan Comercial (geovisor comercial), Formularios de campo, el supervisor de campo y el administrador',
    pg_temp.ev(co, c4) ->> 'contrato' = c4 and pg_temp.ev(ca, c4) ->> 'contrato' = c4 and pg_temp.ev(dc, c4) ->> 'contrato' = c4 and pg_temp.ev(adm, c4) ->> 'contrato' = c4);
  perform pg_temp.err('01.02 el supervisor de distribución (solo Técnica) no: 42501', format('select public.geoportal_redes_evento_contrato(%L, %L)', sd, c1), '42501');
  perform pg_temp.err('01.03 el supervisor de planta no: 42501', format('select public.geoportal_redes_evento_contrato(%L, %L)', sp, c1), '42501');
  perform pg_temp.err('01.04 el operador de Técnica no: 42501', format('select public.geoportal_redes_evento_contrato(%L, %L)', op, c1), '42501');
  perform pg_temp.err('01.05 quien solo tiene Explorar no: 42501', format('select public.geoportal_redes_evento_contrato(%L, %L)', ex, c1), '42501');
  perform pg_temp.err('01.06 quien solo captura actas no: 42501', format('select public.geoportal_redes_evento_contrato(%L, %L)', ac, c1), '42501');
  perform pg_temp.err('01.07 alguien que no está en la lista blanca no: 42501', format('select public.geoportal_redes_evento_contrato(%L, %L)', 'prueba.evc.nadie@emdupar.gov.co', c1), '42501');
  perform pg_temp.err('01.08 sin solicitante: 28000', format('select public.geoportal_redes_evento_contrato(null, %L)', c1), '28000');
  perform pg_temp.err('01.09 un contrato con letras se rechaza (22023, con su texto)', format('select public.geoportal_redes_evento_contrato(%L, %L)', co, '12A45'), '22023', 'solo números');
  perform pg_temp.err('01.10 … uno vacío o de 16 cifras también', format('select public.geoportal_redes_evento_contrato(%L, %L)', co, ''), '22023');
  perform pg_temp.err('01.11 … y uno de 16 cifras', format('select public.geoportal_redes_evento_contrato(%L, %L)', co, '1234567890123456'), '22023');
  perform pg_temp.reg('01.12 el contrato con espacios alrededor se lee igual', pg_temp.ev(co, '  ' || c4 || ' ') ->> 'contrato' = c4);

  -- ===================== 02. Sin eventos en su zona =====================
  j := pg_temp.ev(co, c1);
  perform pg_temp.reg('02.01 sin eventos que lo toquen: en_evento falso, evento null, otros 0, ubicado verdadero, y exactamente las 6 claves del contrato',
    pg_temp.claves(j) = 'consultado_en,contrato,en_evento,evento,otros_eventos,ubicado' and not (j ->> 'en_evento')::boolean and j -> 'evento' = 'null'::jsonb
    and (j ->> 'otros_eventos')::integer = 0 and (j ->> 'ubicado')::boolean and (j ->> 'consultado_en')::timestamptz is not null, j::text);
  j := pg_temp.ev(co, c5);
  perform pg_temp.reg('02.02 el contrato sin amarre a la red: ubicado falso (y sin evento)', not (j ->> 'ubicado')::boolean and not (j ->> 'en_evento')::boolean, j::text);

  -- ===================== 03. Los cuatro tipos de zona (eventos simulados, con las RPC publicadas) =====================
  -- un daño de acueducto en T1, para que el evento del círculo nazca de un daño
  j := public.geoportal_redes_preparar_dano(op, 1);
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', j -> 'fotos' -> 0 ->> 'ruta', '{"size": 300000, "mimetype": "image/jpeg"}');
  v_dan := public.geoportal_redes_crear_dano(op, (j ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
             'activo', pg_temp.cod('T1'), 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(50), 't_detectado', pg_temp.iso('-30 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio',
             'causa_clase', 'desconocida', 'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', j -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
  v_reg := date_trunc('minute', clock_timestamp()) + interval '4 hours';
  e2 := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZTEVC mantenimiento del tanque del sector',
          'desde', pg_temp.iso('-20 minutes'), 'regreso', to_char(v_reg, 'YYYY-MM-DD"T"HH24:MI:SSOF'))) ->> 'codigo';
  e1 := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'circulo', 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(50), 'radio_m', 80, 'causa', 'ZTEVC fuga en la tubería de la esquina',
          'registro', v_dan, 'desde', pg_temp.iso('-10 minutes'))) ->> 'codigo';
  perform public.geoportal_redes_planta_sectores_fijar(sd, 'gota_fria', array[pg_temp.cod('S2')], 'ZTEVC sectores de prueba de la planta');
  e3 := public.geoportal_redes_evento_declarar(sp, jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'gota_fria', 'causa', 'ZTEVC falla de energía en la planta')) ->> 'codigo';

  j := pg_temp.ev(co, c1);
  perform pg_temp.reg('03.01 el contrato del círculo: en_evento, el evento del círculo (el más específico) y 1 otro (el de sectores que también lo toca)',
    (j ->> 'en_evento')::boolean and j -> 'evento' ->> 'codigo' = e1 and j -> 'evento' ->> 'zona' = 'circulo' and (j ->> 'otros_eventos')::integer = 1, j::text);
  perform pg_temp.reg('03.02 el evento trae exactamente sus 9 claves; tipo «dano» («Daño en la red») porque nació del daño; sin regreso estimado',
    pg_temp.claves(j -> 'evento') = 'causa,codigo,desde,regreso_estimado,texto,tipo,tipo_nombre,zona,zona_nombre' and j -> 'evento' ->> 'tipo' = 'dano'
    and j -> 'evento' ->> 'tipo_nombre' = 'Daño en la red' and j -> 'evento' -> 'regreso_estimado' = 'null'::jsonb and j -> 'evento' ->> 'causa' = 'ZTEVC fuga en la tubería de la esquina'
    and j -> 'evento' ->> 'zona_nombre' like 'un círculo de 80 m%', j::text);
  perform pg_temp.reg('03.03 «desde» es el del evento y «texto» es la franja del Corte 15 («Sin agua en … desde las … por …. Regreso estimado: sin definir.»)',
    (j -> 'evento' ->> 'desde')::timestamptz = (select desde from redes.eventos_suspension where codigo = e1)
    and j -> 'evento' ->> 'texto' = (select redes.f_evento_franja(e.zona_nombre, e.desde, e.causa, e.regreso_vigente) from redes.v_evento_suspension e where e.codigo = e1)
    and j -> 'evento' ->> 'texto' like 'Sin agua en un círculo de 80 m% desde las % por ZTEVC fuga en la tubería de la esquina. Regreso estimado: sin definir.', j -> 'evento' ->> 'texto');
  j := pg_temp.ev(ca, c2);
  perform pg_temp.reg('03.04 el contrato del sector: el evento por sectores, tipo «suspension» («Suspensión del servicio»), con su regreso estimado y 0 otros',
    j -> 'evento' ->> 'codigo' = e2 and j -> 'evento' ->> 'zona' = 'sectores' and j -> 'evento' ->> 'tipo' = 'suspension' and j -> 'evento' ->> 'tipo_nombre' = 'Suspensión del servicio'
    and (j -> 'evento' ->> 'regreso_estimado')::timestamptz = v_reg and (j ->> 'otros_eventos')::integer = 0 and j -> 'evento' ->> 'zona_nombre' = 'ZTEVC S1', j::text);
  v_reg2 := v_reg + interval '2 hours';
  perform public.geoportal_redes_evento_regreso(adm, e2, to_char(v_reg2, 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'ZTEVC la reparación se demora');
  j := pg_temp.ev(ca, c2);
  perform pg_temp.reg('03.05 si el supervisor corrige el regreso, la respuesta trae el vigente (y el texto lo dice)', (j -> 'evento' ->> 'regreso_estimado')::timestamptz = v_reg2
    and j -> 'evento' ->> 'texto' like '%Regreso estimado: ' || redes.f_evento_hora(v_reg2), j::text);
  j := pg_temp.ev(dc, c3);
  perform pg_temp.reg('03.06 el contrato de un sector de la planta: zona «planta», «lo que surte la planta Gota Fría»',
    j -> 'evento' ->> 'codigo' = e3 and j -> 'evento' ->> 'zona' = 'planta' and j -> 'evento' ->> 'zona_nombre' = 'lo que surte la planta Gota Fría', j::text);
  j := pg_temp.ev(co, c4);
  perform pg_temp.reg('03.07 el contrato fuera de todas las zonas sigue sin evento', not (j ->> 'en_evento')::boolean and j -> 'evento' = 'null'::jsonb, j::text);
  perform pg_temp.reg('03.08 MISMA REGLA DEL CORTE 15: para cada evento, los contratos que esta consulta pone dentro son los que el Corte 15 contó al declararlo',
    (select count(*) from unnest(array[c1, c2, c3, c4, c5]) c where exists (select 1 from redes.f_eventos_del_contrato(c) x join redes.eventos_suspension e on e.id = x.evento_id where e.codigo = e1))
      = (select contratos from redes.eventos_suspension where codigo = e1)
    and (select count(*) from unnest(array[c1, c2, c3, c4, c5]) c where exists (select 1 from redes.f_eventos_del_contrato(c) x join redes.eventos_suspension e on e.id = x.evento_id where e.codigo = e2))
      = (select contratos from redes.eventos_suspension where codigo = e2)
    and (select count(*) from unnest(array[c1, c2, c3, c4, c5]) c where exists (select 1 from redes.f_eventos_del_contrato(c) x join redes.eventos_suspension e on e.id = x.evento_id where e.codigo = e3))
      = (select contratos from redes.eventos_suspension where codigo = e3)
    and (select string_agg(contratos::text, ',' order by codigo) from redes.eventos_suspension where codigo in (e1, e2, e3)) = '2,1,1',
    (select string_agg(codigo || '=' || contratos, ',' order by codigo) from redes.eventos_suspension where codigo in (e1, e2, e3)));

  -- ===================== 04. Cerrar, anular y toda la ciudad =====================
  perform public.geoportal_redes_evento_cerrar(adm, e1, 'ZTEVC se reparó la fuga');
  j := pg_temp.ev(co, c1);
  perform pg_temp.reg('04.01 cerrado el círculo, el mismo contrato pasa al evento por sectores (que sigue abierto), sin otros', j -> 'evento' ->> 'codigo' = e2 and (j ->> 'otros_eventos')::integer = 0, j::text);
  perform public.geoportal_redes_evento_anular(adm, e3, 'ZTEVC se declaró por error');
  j := pg_temp.ev(co, c3);
  perform pg_temp.reg('04.02 anulado el de la planta, su contrato queda sin evento', not (j ->> 'en_evento')::boolean, j::text);
  e4 := public.geoportal_redes_evento_declarar(sp, jsonb_build_object('alcance', 'total', 'total', 'ciudad', 'causa', 'ZTEVC racionamiento en toda la ciudad')) ->> 'codigo';
  j := pg_temp.ev(co, c4); j2 := pg_temp.ev(co, c5);
  perform pg_temp.reg('04.03 un evento de toda la ciudad toca a todos: zona «ciudad», «toda la ciudad», también al contrato sin amarre (que sigue «ubicado: falso»)',
    j -> 'evento' ->> 'codigo' = e4 and j -> 'evento' ->> 'zona' = 'ciudad' and j -> 'evento' ->> 'zona_nombre' = 'toda la ciudad'
    and j2 -> 'evento' ->> 'codigo' = e4 and not (j2 ->> 'ubicado')::boolean and (j2 ->> 'en_evento')::boolean, j::text || ' ' || j2::text);
  j := pg_temp.ev(co, c2);
  perform pg_temp.reg('04.04 con la ciudad abierta, el contrato del sector muestra el de sectores (más específico) y 1 otro', j -> 'evento' ->> 'codigo' = e2 and (j ->> 'otros_eventos')::integer = 1, j::text);
  perform pg_temp.reg('04.05 la ciudad también coincide con el Corte 15: contó todos los contratos con amarre', (select contratos from redes.eventos_suspension where codigo = e4) = (select count(*) from redes.contrato_tramo));

  -- ===================== 05. Nada personal, solo lectura =====================
  select count(*) into v_aud from public.geoportal_auditoria;
  select string_agg(pg_temp.ev(co, c)::text, ' ') into v_txt from unnest(array[c1, c2, c3, c4, c5]) c;
  perform pg_temp.reg('05.01 ninguna respuesta trae correos, nombres de personas, coordenadas, códigos de tramo o de sector, ni el código del daño',
    position('@' in v_txt) = 0 and v_txt !~ '"(lat|lon|geom|zona_geojson|tramo|activo|sectores|registro|declarado_por|contratos|sensibles|planta|circulo)":'
    and position('ZTEVC Admin' in v_txt) = 0 and position(pg_temp.cod('T1') in v_txt) = 0 and position(pg_temp.cod('S1') in v_txt) = 0 and position(v_dan in v_txt) = 0, left(v_txt, 400));
  perform pg_temp.reg('05.02 consultar no escribe: ni auditoría ni un evento de más', (select count(*) from public.geoportal_auditoria) = v_aud);
  perform pg_temp.reg('05.03 la RPC es de solo lectura (STABLE), security definer, solo de service_role; las 2 internas no las ejecuta nadie',
    (select p.provolatile = 's' and p.prosecdef and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
            and not has_function_privilege('authenticated', p.oid, 'execute') from pg_proc p where p.oid = 'public.geoportal_redes_evento_contrato(text,text)'::regprocedure)
    and not has_function_privilege('service_role', 'redes.f_eventos_del_contrato(text)'::regprocedure, 'execute') and not has_function_privilege('anon', 'redes.f_evento_contrato_acceso(text)'::regprocedure, 'execute'));

  -- ===================== 06. Tiempos (meta: menos de 150 ms por contrato) =====================
  -- 300 eventos viejos cerrados, y 2 abiertos más sobre la red real (un sector de la mitad occidental y un círculo de 2 km en el centro): con la ciudad y el de
  -- sectores de prueba, 4 abiertos
  perform pg_temp.activo('SR', 'SEC', (select ST_Multi(ST_MakeEnvelope(ST_XMin(c), ST_YMin(c), (ST_XMin(c) + ST_XMax(c)) / 2, ST_YMax(c), 4326))
                                         from (select ST_Extent(m.geom)::geometry as c from redes.activo_vigente_mat m where m.prefijo = 'RED' and m.sistema = 'acueducto') x), 'sector');
  with viejos as (
    insert into redes.eventos_suspension (codigo, alcance, geom, sectores, zona_nombre, causa, desde, contratos, sensibles, autor)
    select 'EVS-9' || lpad(i::text, 5, '0'), 'sectores', (select geom from redes.activo_vigente_mat where codigo = pg_temp.cod('SR')), array[(select activo_id from _zt where nombre = 'SR')],
           'ZTEVC relleno', 'ZTEVC evento viejo de relleno', clock_timestamp() - interval '90 days' + make_interval(hours => i), 0, 0, adm from generate_series(1, 300) i
    returning id, desde)
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) select id, 'cerrar', 'ZTEVC cierre de relleno', desde + interval '2 hours', adm from viejos;
  perform public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('SR')), 'causa', 'ZTEVC sector grande sobre la red'));
  perform public.geoportal_redes_evento_declarar(sd, (select jsonb_build_object('alcance', 'circulo', 'lat', round(ST_Y(ST_Centroid(c))::numeric, 6), 'lon', round(ST_X(ST_Centroid(c))::numeric, 6),
                                                                                  'radio_m', 2000, 'causa', 'ZTEVC círculo grande en el centro')
                                                        from (select ST_Extent(m.geom)::geometry as c from redes.activo_vigente_mat m where m.prefijo = 'RED' and m.sistema = 'acueducto') x));
  analyze redes.eventos_suspension; analyze redes.evento_suspension_eventos;
  for v_ct in select ct.contrato from redes.contrato_tramo ct where ct.contrato not like '99999999%' order by md5(ct.contrato) limit 200 loop
    v_t0 := clock_timestamp(); j := pg_temp.ev(co, v_ct); v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
    v_tiempos := v_tiempos || v_ms;
  end loop;
  select max(t), percentile_cont(0.95) within group (order by t), percentile_cont(0.5) within group (order by t) into v_max, v_p95, v_med from unnest(v_tiempos) t;
  select count(*) into v_n from redes.f_eventos_abiertos();
  v_info := format('TIEMPOS (%s contratos reales, %s eventos abiertos y 300 cerrados): mediana %s ms · p95 %s ms · el más lento %s ms (meta 150 ms)',
                   cardinality(v_tiempos), v_n, round(v_med, 1), round(v_p95, 1), round(v_max, 1));
  perform pg_temp.reg('06.01 TIEMPOS: 200 contratos reales, cada uno en menos de 150 ms, con 300 eventos viejos y los abiertos sobre la red real',
    cardinality(v_tiempos) = 200 and v_max < 150 and v_n >= 4, v_info);
  perform pg_temp.reg('06.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · aviso de evento por contrato (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
