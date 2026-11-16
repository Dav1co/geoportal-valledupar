-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 26, 25, 30 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes12.*) y sus contratos de prueba (9900000012xx, con predio, cartera y ficha,
-- como la suite viva de Análisis de contrato). Mide además, con los datos que haya en la base, cuánto tarda la tesela de contratos más cargada.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 6c … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.trae(p_b64 text, p_txt text) returns boolean language sql as $$
  select coalesce(position(convert_to(p_txt, 'UTF8') in decode(nullif(p_b64, ''), 'base64')) > 0, false) $$;
create function pg_temp.tesela(p_quien text, p_z integer, x numeric, y numeric) returns text language sql as $$
  select public.geoportal_redes_geovisor_mvt_contratos(p_quien, p_z, floor((pg_temp.lon(x) + 180) / 360 * (1 << p_z))::integer,
                                                       floor((1 - ln(tan(radians(pg_temp.lat(y))) + 1 / cos(radians(pg_temp.lat(y)))) / pi()) / 2 * (1 << p_z))::integer) $$;
create function pg_temp.meses6(p_ult text, p_m3 integer[]) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('periodo', to_char(to_date(p_ult, 'YYYYMM') - make_interval(months => 6 - k), 'YYYYMM'), 'sin_dato', p_m3[k] is null, 'm3', p_m3[k],
                                      'metodo', case when p_m3[k] is null then null else 'lectura' end, 'lectura_real', p_m3[k] is not null, 'causal', '99 LECTURA NORMAL') order by k)
    from generate_series(1, 6) k $$;

do $prueba$
declare
  a text := 'prueba.redes12.adm@emdupar.gov.co'; sd text := 'prueba.redes12.dist@emdupar.gov.co'; sv text := 'prueba.redes12.planta@emdupar.gov.co';
  op text := 'prueba.redes12.op@emdupar.gov.co'; na text := 'prueba.redes12.nada@emdupar.gov.co';
  C1 text := '990000001201'; C2 text := '990000001202'; C3 text := '990000001203';
  v_r jsonb; v_t text; v_n integer; v_aud0 integer; v_aud1 integer; v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_ms4 numeric; v_x integer; v_y integer; v_pred integer;
  v_info text; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT12 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT12 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT12 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT12 Operador', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT12 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT12 necesita ver la red en la calle');

  -- ===================== 01. Lo que se retira y la comprobación estática de pg-safeupdate =====================
  perform pg_temp.reg('01.01 la copia derivada ya no existe: ni las 2 tablas ni las 2 funciones que la rehacían',
     to_regclass('redes.contratos_capa') is null and to_regclass('redes.contratos_capa_estado') is null
     and to_regprocedure('redes.f_refrescar_contratos_capa()') is null and to_regprocedure('redes.f_contratos_capa_al_dia()') is null);
  perform pg_temp.reg('01.02 ninguna función de redes nombra la copia',
     not exists (select 1 from pg_proc p where (p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) and p.prosrc ~ 'contratos_capa'));
  perform pg_temp.reg('01.03 la configuración del geovisor y la tesela de contratos solo leen (STABLE): ninguna petición rehace nada',
     (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt_contratos') and p.provolatile = 's') = 2);
  perform pg_temp.reg('01.04 pg-safeupdate: ninguna función de redes, tecnica ni public.geoportal_redes_* con DELETE o UPDATE sin WHERE',
     not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion || ' → ' || sentencia, ' | ') from redes.f_funciones_sin_where()));
  -- la comprobación sí ve una función mala (y no marca las buenas): dos funciones de prueba que el ERROR final deshace
  execute $f$create function redes.zt12_mala() returns void language plpgsql as $$
    begin
      delete from redes.parametros;      -- sin where
      update redes.parametros p set valor = valor;
    end $$$f$;
  execute $f$create function redes.zt12_buena() returns void language plpgsql as $$
    begin
      delete from redes.parametros where true;
      update redes.parametros set valor = valor where clave = 'x';
      insert into redes.parametros (clave, valor, unidad, descripcion) values ('zt12', 1, 'u', 'x') on conflict (clave) do update set valor = excluded.valor;
      perform 1 from redes.parametros for update;
    end $$$f$;
  perform pg_temp.reg('01.05 la comprobación marca un DELETE y un UPDATE sin WHERE (2 sentencias de la función mala) y no marca «where true», «on conflict … do update» ni «for update»',
     (select count(*) from redes.f_funciones_sin_where() where funcion = 'redes.zt12_mala()') = 2
     and not exists (select 1 from redes.f_funciones_sin_where() where funcion = 'redes.zt12_buena()'), (select string_agg(funcion || ' → ' || sentencia, ' | ') from redes.f_funciones_sin_where()));
  execute 'drop function redes.zt12_mala()'; execute 'drop function redes.zt12_buena()';
  perform pg_temp.reg('01.06 el catálogo conserva la capa de contratos (activa, solo supervisores) y el parámetro de las horas queda marcado «sin uso»',
     (select fuente || '|' || estado || '|' || solo_completo from redes.geovisor_capas where codigo = 'contratos') = 'contratos|activa|true'
     and (select descripcion from redes.parametros where clave = 'geovisor_contratos_horas') like 'Sin uso%');
  perform pg_temp.reg('01.07 las 2 funciones nuevas son internas: la API no las ejecuta',
     not has_function_privilege('service_role', 'redes.f_funciones_sin_where()', 'execute') and not has_function_privilege('anon', 'redes.f_contrato_uso(text,text)', 'execute')
     and not has_function_privilege('authenticated', 'redes.f_contrato_uso(text,text)', 'execute'));

  -- ===================== 02. La tesela de contratos, al vuelo =====================
  insert into public.cartera_suscripcion (contrato, estado, identificacion, nombre, correo, telefono, direccion, barrio, categoria, subcategoria, ciclo,
                                          facturas_pendientes, deuda_total, saldo_pendiente, saldo_a_favor, valor_reclamo, saldo_financiado, serial_medidor, ruta, periodo_carga)
  values (C1, 'RETIRADO', 'DOC-PRUEBA-1', 'NOMBRE VIEJO DE PRUEBA', null, '3001112233', 'DIR VIEJA', 'ZT12 BARRIO VIEJO', '1 Residencial', '2 Estrato 2', '7', 9, 412300, 98000, 0, 0, 0, 'ZTM1', '0701', '20200101'),
         (C1, 'ACTIVO', 'DOC-PRUEBA-1', 'NOMBRE DE PRUEBA DOCE', null, '3001112233', 'CRA ZT12 1 2 3', 'ZT12 BARRIO CARTERA', '1 Residencial', '2 Estrato 2', '7', 9, 412300, 98000, 0, 0, 0, 'ZTM1', '0701', '29991231'),
         (C2, 'RETIRADO', 'DOC-PRUEBA-2', 'NOMBRE DE PRUEBA TRECE', null, null, 'CRA ZT12 9 9', 'ZT12 BARRIO CARTERA', '2 Comercial', '201 1/2', '7', 0, 0, 0, 0, 0, 0, null, '0702', '29991231');
  insert into public.catastro_valledupar (cod_usuario, direccion, barrio, geom)
  values (C1, 'CRA ZT12 1 2 3 CATASTRO', 'ZT12 BARRIO CATASTRO', pg_temp.pt(0, 0)), (C1, 'OTRO PREDIO', 'ZT12 BARRIO CATASTRO', pg_temp.pt(400, 400)),
         (C2, 'CRA ZT12 9 9', 'ZT12 BARRIO CATASTRO', pg_temp.pt(30, 0)), (C3, 'CRA ZT12 SOLO CATASTRO', 'ZT12 OTRO', pg_temp.pt(60, 0)), ('99999999', 'COMODIN', 'X', pg_temp.pt(90, 0));
  insert into bi_interno.ficha_contrato (contrato, periodo_ultimo, uso, consumo_meses, cons_prom, meses_con_lectura, medidor_fecha_estado, medidor_anios)
  values (C1, '202610', 'Residencial', pg_temp.meses6('202610', array[7, null, 9, 6, 5, 6]), 6.6, 5, 'real', 12);
  v_t := pg_temp.tesela(sd, 17, 0, 0);
  perform pg_temp.reg('02.01 recién cargados, sin rehacer nada, los contratos ya salen: vacía a zoom 15; a zoom 17 trae el número, el estado del último corte y el uso',
     pg_temp.tesela(sd, 15, 0, 0) = '' and pg_temp.trae(v_t, C1) and pg_temp.trae(v_t, 'activo') and pg_temp.trae(v_t, 'Residencial'));
  perform pg_temp.reg('02.02 un punto por contrato, el del predio de menor id: el segundo predio del mismo contrato no se dibuja', not pg_temp.trae(pg_temp.tesela(sd, 18, 400, 400), C1)
     and pg_temp.trae(pg_temp.tesela(sd, 18, 0, 0), C1));
  perform pg_temp.reg('02.03 retirado y sin ficha: toma el uso de la cartera sin su número («Comercial»); sin cartera: «sin_dato»',
     pg_temp.trae(v_t, C2) and pg_temp.trae(v_t, 'retirado') and pg_temp.trae(v_t, 'Comercial') and pg_temp.trae(v_t, C3) and pg_temp.trae(v_t, 'sin_dato'));
  perform pg_temp.reg('02.04 el comodín 99999999 no entra', not pg_temp.trae(v_t, '99999999'));
  perform pg_temp.reg('02.05 la tesela no lleva nombre, dirección, barrio, teléfono ni deuda', not pg_temp.trae(v_t, 'NOMBRE DE PRUEBA') and not pg_temp.trae(v_t, 'CRA ZT12') and not pg_temp.trae(v_t, 'ZT12 BARRIO')
     and not pg_temp.trae(v_t, '3001112233') and not pg_temp.trae(v_t, '412300'));
  insert into public.cartera_suscripcion (contrato, estado, nombre, direccion, barrio, categoria, periodo_carga) values (C3, 'SUSPENDIDO', 'NOMBRE DE PRUEBA CATORCE', 'CRA ZT12 7', 'ZT12 BARRIO CARTERA', '1 Residencial', '29991231');
  perform pg_temp.reg('02.06 siempre al día: un corte nuevo de la cartera se ve en la tesela siguiente, sin rehacer nada («otro» para un suspendido)', pg_temp.trae(pg_temp.tesela(sd, 17, 0, 0), 'otro'));
  perform pg_temp.err('02.07 el operador en solo lectura no pide la tesela de contratos', format($$select pg_temp.tesela(%L, 17, 0, 0)$$, op), '42501');
  perform pg_temp.err('02.08 quien no tiene el geovisor tampoco', format($$select pg_temp.tesela(%L, 17, 0, 0)$$, na), '42501');
  perform pg_temp.reg('02.09 el supervisor de planta y el administrador sí (geovisor completo)', pg_temp.trae(pg_temp.tesela(sv, 17, 0, 0), C1) and pg_temp.trae(pg_temp.tesela(a, 17, 0, 0), C1));
  perform pg_temp.err('02.10 una tesela fuera de rango', format($$select public.geoportal_redes_geovisor_mvt_contratos(%L, 17, -1, 2)$$, sd), null, 'fuera de rango');

  -- ===================== 03. La tarjeta del contrato (§30.1), sin la copia =====================
  select count(*) into v_aud0 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta';
  v_r := public.geoportal_redes_contrato_tarjeta(sd, C1, '10.0.0.7');
  perform pg_temp.reg('03.01 la tarjeta trae número, estado (activo), uso, el perfil de consumo de 6 meses (con el hueco) y los años del medidor',
     v_r ->> 'contrato' = C1 and v_r ->> 'estado' = 'activo' and v_r ->> 'estado_texto' = 'ACTIVO' and v_r ->> 'uso' = 'Residencial'
     and jsonb_array_length(v_r -> 'consumo' -> 'meses') = 6 and (v_r -> 'consumo' -> 'meses' -> 1 ->> 'sin_dato')::boolean and (v_r -> 'consumo' ->> 'promedio')::numeric = 6.6
     and (v_r ->> 'medidor_anios')::integer = 12, left(v_r::text, 400));
  perform pg_temp.reg('03.02 nombre, dirección (la del catastro) y barrio (el de la cartera) del ÚLTIMO corte', v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA DOCE'
     and v_r -> 'suscriptor' ->> 'direccion' = 'CRA ZT12 1 2 3 CATASTRO' and v_r -> 'suscriptor' ->> 'barrio' = 'ZT12 BARRIO CARTERA', (v_r -> 'suscriptor')::text);
  perform pg_temp.reg('03.03 sin teléfono, deuda, documento ni saldos', v_r::text not like '%3001112233%' and v_r::text not like '%412300%' and v_r::text not like '%DOC-PRUEBA%'
     and not (v_r ? 'deuda_total') and not (v_r -> 'suscriptor' ? 'telefonos'));
  perform pg_temp.reg('03.04 la lectura queda en la auditoría (quién, contrato e IP) sin el nombre ni la dirección',
     (select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta') = v_aud0 + 1
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta' and email = sd and referencia = C1 and ip = '10.0.0.7'
                   and detalle::text not like '%NOMBRE DE PRUEBA%' and detalle::text not like '%CRA ZT12%'));
  v_r := public.geoportal_redes_contrato_tarjeta(a, C2);
  perform pg_temp.reg('03.05 un contrato retirado y sin ficha: «retirado», uso de la cartera, sin consumo, con nombre y dirección', v_r ->> 'estado' = 'retirado' and v_r ->> 'uso' = 'Comercial'
     and v_r -> 'consumo' = 'null'::jsonb and v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA TRECE', left(v_r::text, 300));
  v_r := public.geoportal_redes_contrato_tarjeta(sv, C3);
  perform pg_temp.reg('03.06 el suspendido: «otro» con su texto; el estado es el del corte de hoy, no el de una copia', v_r ->> 'estado' = 'otro' and v_r ->> 'estado_texto' = 'SUSPENDIDO', left(v_r::text, 300));
  select count(*) into v_aud1 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta';
  perform pg_temp.err('03.07 el operador en solo lectura no abre la tarjeta del contrato', format($$select public.geoportal_redes_contrato_tarjeta(%L, %L)$$, op, C1), '42501');
  perform pg_temp.err('03.08 quien no es de Técnica tampoco', format($$select public.geoportal_redes_contrato_tarjeta(%L, %L)$$, na, C1), '42501');
  perform pg_temp.err('03.09 un contrato mal escrito', format($$select public.geoportal_redes_contrato_tarjeta(%L, '12A')$$, sd), '22023', 'números');
  perform pg_temp.err('03.10 el comodín no está en la capa', format($$select public.geoportal_redes_contrato_tarjeta(%L, '99999999')$$, sd), 'P0002');
  perform pg_temp.err('03.11 un contrato que no tiene predio en el catastro tampoco', format($$select public.geoportal_redes_contrato_tarjeta(%L, '990000001299')$$, sd), 'P0002');
  perform pg_temp.reg('03.12 los intentos negados o fallidos no dejan lectura', (select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta') = v_aud1 and v_aud1 = v_aud0 + 3);

  -- ===================== 04. La configuración del geovisor =====================
  v_r := public.geoportal_redes_geovisor(sd);
  perform pg_temp.reg('04.01 la configuración del supervisor: el zoom de contratos, «compartir» y la capa de contratos; ya no trae el estado de una copia',
     (v_r -> 'zoom' ->> 'contratos')::numeric = (select valor from redes.parametros where clave = 'geovisor_zoom_contratos') and (v_r ->> 'compartir')::boolean
     and not (v_r ? 'contratos_capa') and 'contratos' = any (select jsonb_array_elements(v_r -> 'capas') ->> 'codigo'), left(v_r::text, 300));
  v_r := public.geoportal_redes_geovisor(op);
  perform pg_temp.reg('04.02 el operador en solo lectura: sin contratos y sin «compartir»', not (v_r ->> 'compartir')::boolean
     and not ('contratos' = any (select jsonb_array_elements(v_r -> 'capas') ->> 'codigo')));
  perform pg_temp.err('04.03 quien no tiene el geovisor no recibe la configuración', format($$select public.geoportal_redes_geovisor(%L)$$, na), '42501');
  perform pg_temp.reg('04.04 las demás capas siguen igual (daños de hoy y muestreo)', public.geoportal_redes_geovisor_capa(sd, 'danos') ->> 'type' = 'FeatureCollection'
     and public.geoportal_redes_geovisor_capa(sd, 'muestreo') ->> 'type' = 'FeatureCollection');

  -- ===================== 05. Tiempos con los datos de esta base (en producción: el volumen real) =====================
  -- La tesela de zoom 16 con más predios de todo el catastro: es el peor caso de la capa. Tope de las peticiones: 8 s (authenticated) y 30 s (service_role).
  select t.x, t.y, t.n into v_x, v_y, v_pred from (
    select floor((ST_X(geom) + 180) / 360 * 65536)::integer as x, floor((1 - ln(tan(radians(ST_Y(geom))) + 1 / cos(radians(ST_Y(geom)))) / pi()) / 2 * 65536)::integer as y, count(*)::integer as n
      from public.catastro_valledupar where geom is not null and ST_Y(geom) between -80 and 80 group by 1, 2 order by 3 desc limit 1) t;
  v_t0 := clock_timestamp(); v_t := public.geoportal_redes_geovisor_mvt_contratos(sd, 16, v_x, v_y); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_n := coalesce(length(decode(nullif(v_t, ''), 'base64')), 0);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_geovisor_mvt_contratos(sd, 16, v_x, v_y); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_geovisor(sd); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_contrato_tarjeta(sd, C1); v_ms4 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS: tesela de contratos más cargada (z16 %s/%s, %s predios, %s KB): %s ms la primera vez y %s ms la segunda · configuración del geovisor: %s ms · tarjeta: %s ms',
                   v_x, v_y, v_pred, round(v_n / 1024.0), v_ms1, v_ms2, v_ms3, v_ms4);
  perform pg_temp.reg('05.01 la tesela de contratos más cargada de la base responde en menos de 8 s (tope más corto de las peticiones) y pesa menos de 500 KB', v_ms1 < 8000 and v_ms2 < 8000 and v_n < 500 * 1024, v_info);
  perform pg_temp.reg('05.02 la configuración del geovisor y la tarjeta responden en menos de 2 s', v_ms3 < 2000 and v_ms4 < 2000, v_info);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 6c (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
