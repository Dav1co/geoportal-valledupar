-- =====================================================================
-- SCRR · CORTE 2 · 75 — PRUEBAS SOLO LOCALES del cierre completo de cartera (salidas, historial de salida, reemplazo, reversión, anulación) y del retiro
-- del historial. Corre DESPUÉS de la migración, en una sola transacción que termina en ERROR (no deja nada).
-- Se NIEGA a correr si public.cartera_suscripcion tiene filas que no son de prueba: el cierre retira los contratos que no vienen en el archivo.
-- =====================================================================
begin;
set local statement_timeout = '60s';
do $$ begin
  if exists (select 1 from public.cartera_suscripcion where contrato is null or contrato not like '92000000%') then
    raise exception 'Estas pruebas son solo para la base local: cartera_suscripcion tiene filas que no son de prueba';
  end if;
end $$;
create temp table ztscrr_res (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztscrr_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), left(p_detalle, 600)) $f$;
create function pg_temp.rpc(q text) returns jsonb language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  begin
    execute 'set local role service_role';
    execute 'select (' || q || ')::jsonb' into r;
    execute 'reset role';
    return coalesce(r, 'null'::jsonb);
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    return jsonb_build_object('error', e, 'msg', m);
  end;
end $f$;
create function pg_temp.err(r jsonb) returns text language sql as $f$ select coalesce(r ->> 'error', 'OK') $f$;
create function pg_temp.fc(p_contrato bigint, p_saldo numeric, p_vencidas int) returns jsonb language sql as $f$
  select jsonb_build_object('contrato', p_contrato::text, 'estado', 'ACTIVO', 'identificacion', 'ZT' || p_contrato, 'nombre', 'ZTSCRR ' || p_contrato,
         'correo', 'zt@ejemplo.invalid', 'telefono', '3000000000', 'direccion', 'ZTSCRR CALLE', 'barrio', 'ztscrr barrio', 'categoria', '1 - RESIDENCIAL', 'subcategoria', '2',
         'ciclo', '5', 'facturas_pendientes', (p_vencidas + 1)::text, 'facturas_vencidas', p_vencidas::text, 'deuda_total', p_saldo::text, 'saldo_pendiente', p_saldo::text,
         'saldo_a_favor', '0', 'valor_reclamo', '0', 'saldo_financiado', '0', 'serial_medidor', 'ZTM', 'codigo_reparto', 'R1', 'ruta', 'ZTRUTA') $f$;
-- carga completa de cartera en una llamada por paso (iniciar, lote, validar, aplicar lote 1); devuelve el id
create function pg_temp.cartera(p_fecha date, p_filas jsonb, p_sha text, p_reemplaza text default null, p_motivo text default null) returns text language plpgsql as $f$
declare r jsonb; c text; S text := 'ztscrr.sup@emdupar.gov.co';
begin
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_iniciar(%L, %L, %L::date, %L, %L, %s, %L::uuid, %L)', S, 'cartera', p_fecha, 'zt.xlsx', p_sha, jsonb_array_length(p_filas), p_reemplaza, p_motivo));
  if r ? 'error' then raise exception 'iniciar: %', r; end if;
  c := r ->> 'carga_id';
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_lote(%L, %L::uuid, 1, %L::jsonb)', S, c, p_filas)); if r ? 'error' then raise exception 'lote: %', r; end if;
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, c)); if r ? 'error' then raise exception 'validar: %', r; end if;
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, c)); if r ? 'error' then raise exception 'aplicar: %', r; end if;
  return c;
end $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_campo, ver_dashboard_campo)
  values ('ztscrr.sup@emdupar.gov.co', 'ZTSCRR Supervisor', 'consulta', true, 'sin_restriccion', 'todos', true, true);

do $$
declare S text := 'ztscrr.sup@emdupar.gov.co'; B bigint := 920000000000; v_hoy date := (now() at time zone 'America/Bogota')::date; v_ids numeric;
        r jsonb; c1 text; c2 text; c3 text; f jsonb; v_nom text;
begin
  -- estado «viejo» (como lo dejó el script): 300 contratos
  insert into public.cartera_suscripcion (contrato, estado, nombre, saldo_pendiente, periodo_carga, cargado_en)
    select (B + g)::text, 'ZTVIEJO', 'ZTSCRR VIEJO', 1, '20261101', '2026-11-01 07:00:00-05' from generate_series(1, 300) g;
  select sum(id) into v_ids from public.cartera_suscripcion;
  -- 1. Carga de AYER: vienen 1..200 (con saldo los pares) y 301..400 nuevos; NO vienen 201..300 (100 de 300 = 33 %)
  select jsonb_agg(pg_temp.fc(B + g, case when g % 2 = 0 then 10000 else 0 end, 2) order by g) into f from generate_series(1, 200) g;
  select f || jsonb_agg(pg_temp.fc(B + g, 5000, 1) order by g) into f from generate_series(301, 400) g;
  c1 := pg_temp.cartera(v_hoy - 1, f, md5('c1') || md5('c1x'));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, c1));
  perform pg_temp.ok('L01 cerrar con 100 de 300 ausentes (33 %): 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, null, true, %L)', S, c1, 'ZTSCRR los 100 salieron de la cartera'));
  perform pg_temp.ok('L02 confirmado con motivo: cierra, retira los 100 ausentes con respaldo «salida»',
    pg_temp.err(r) = 'OK' and (r -> 'resultado' ->> 'suscripcion_contratos_salientes')::int = 100
    and (select count(*) from scrr.suscripcion_respaldo where carga_id = c1::uuid and origen = 'salida') = 100, r::text);
  perform pg_temp.ok('L03 cartera_suscripcion = el archivo: 300 contratos, ninguno «viejo»',
    (select count(*) from public.cartera_suscripcion) = 300 and not exists (select 1 from public.cartera_suscripcion where estado = 'ZTVIEJO'));
  perform pg_temp.ok('L04 historial de ayer: 200 con saldo (100 pares + 100 nuevos), sin filas de salida (no había foto anterior)',
    (select count(*) from scrr.v_cartera_vigente where fecha_dato = v_hoy - 1 and en_cartera) = 200 and (select count(*) from scrr.v_cartera_vigente where fecha_dato = v_hoy - 1 and not en_cartera) = 0);
  perform pg_temp.ok('L05 el cierre confirmado queda con su motivo en el evento «aplicada»',
    (select motivo from scrr.carga_eventos where carga_id = c1::uuid and evento = 'aplicada') = 'ZTSCRR los 100 salieron de la cartera');
  -- 2. Carga de HOY: pagaron 2..40 pares (saldo 0); los demás igual
  select jsonb_agg(pg_temp.fc(B + g, case when g % 2 = 0 and g > 40 then 10000 else 0 end, 2) order by g) into f from generate_series(1, 200) g;
  select f || jsonb_agg(pg_temp.fc(B + g, 5000, 1) order by g) into f from generate_series(301, 400) g;
  c2 := pg_temp.cartera(v_hoy, f, md5('c2') || md5('c2x'));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, c2));
  perform pg_temp.ok('L06 carga de hoy cierra sin confirmar (nadie ausente)', pg_temp.err(r) = 'OK' and (r -> 'resultado' ->> 'suscripcion_contratos_salientes')::int = 0, r::text);
  perform pg_temp.ok('L07 historial de hoy: 180 con saldo y 20 filas de salida (los que pagaron), con saldo 0',
    (select count(*) from scrr.v_cartera_vigente where fecha_dato = v_hoy and en_cartera) = 180
    and (select count(*) from scrr.v_cartera_vigente where fecha_dato = v_hoy and not en_cartera and saldo_pendiente = 0) = 20);
  -- 3. Reemplazo de la de hoy (versión 2): ahora también pagó el 400
  f := jsonb_set(f, array[(jsonb_array_length(f) - 1)::text, 'saldo_pendiente'], '"0"');
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_iniciar(%L, %L, %L::date, %L, %L, %s)', S, 'cartera', v_hoy, 'zt2.xlsx', md5('c3') || md5('c3x'), jsonb_array_length(f)));
  perform pg_temp.ok('L08 otra cartera de hoy sin decir que reemplaza: 55000', pg_temp.err(r) = '55000', r::text);
  c3 := pg_temp.cartera(v_hoy, f, md5('c3') || md5('c3x'), c2, 'ZTSCRR el archivo de hoy venía sin el pago del 400');
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, c3));
  perform pg_temp.ok('L09 el reemplazo cierra: la anterior queda «reemplazada» y el historial vigente de hoy es el nuevo (179 con saldo)',
    pg_temp.err(r) = 'OK' and scrr.f_estado_carga(c2::uuid) = 'reemplazada'
    and (select count(*) from scrr.v_cartera_vigente where fecha_dato = v_hoy and en_cartera) = 179
    and (select count(distinct carga_id) from scrr.v_cartera_vigente where fecha_dato = v_hoy) = 1, r::text);
  -- 4. Reversión en orden y anulación
  r := pg_temp.rpc(format('public.geoportal_scrr_suscripcion_revertir(%L, %L::uuid, %L)', S, c2, 'ZTSCRR revertir la de antes'));
  perform pg_temp.ok('L10 no se revierte una carga si una posterior también cambió la tabla: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_suscripcion_revertir(%L, %L::uuid, %L)', S, c3, 'ZTSCRR revierto el reemplazo'));
  perform pg_temp.ok('L11 revertir el reemplazo deja la tabla como después de la versión 1 (el 400 con saldo 5000)',
    pg_temp.err(r) = 'OK' and (r ->> 'pendientes')::int = 0 and (select saldo_pendiente from public.cartera_suscripcion where contrato = (B + 400)::text) = 5000
    and (select count(*) from public.cartera_suscripcion) = 300, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, c3, 'ZTSCRR anulo el reemplazo'));
  perform pg_temp.ok('L12 anular el reemplazo: la versión 1 vuelve a quedar vigente (180 con saldo hoy)',
    pg_temp.err(r) = 'OK' and scrr.f_estado_carga(c2::uuid) = 'aplicada' and (select count(*) from scrr.v_cartera_vigente where fecha_dato = v_hoy and en_cartera) = 180, r::text);
  -- 5. Revertir la de ayer con salidas: vuelven los 100 que habían salido, y los 100 nuevos se van
  r := pg_temp.rpc(format('public.geoportal_scrr_suscripcion_revertir(%L, %L::uuid, %L)', S, c2, 'ZTSCRR revierto la de hoy'));
  r := pg_temp.rpc(format('public.geoportal_scrr_suscripcion_revertir(%L, %L::uuid, %L)', S, c1, 'ZTSCRR revierto la de ayer'));
  perform pg_temp.ok('L13 revertir en orden hasta la primera deja la tabla como la dejó el script (300 «viejos»)',
    pg_temp.err(r) = 'OK' and (select count(*) from public.cartera_suscripcion where estado = 'ZTVIEJO') = 300 and (select count(*) from public.cartera_suscripcion) = 300, r::text);
  perform pg_temp.ok('L13b los 300 vuelven con sus MISMOS id (también los 100 que habían salido) y su cargado_en original',
    (select sum(id) from public.cartera_suscripcion) = v_ids and (select bool_and(cargado_en = '2026-11-01 07:00:00-05') from public.cartera_suscripcion));
  refresh materialized view public.zz_doble_depende_cartera_mv;
  perform pg_temp.ok('L13c tras aplicar, retirar salidas y revertir, las dependientes siguen: la vista lee las 300 filas y la materializada se refresca con 300',
    (select count(*) from public.zz_doble_depende_cartera) = 300 and (select count(*) from public.zz_doble_depende_cartera_mv) = 300);
  perform pg_temp.ok('L13d la tabla sigue como en producción: RLS activado y periodo_carga NOT NULL (una fila sin él se rechaza con 23502)',
    (select relrowsecurity from pg_class where oid = 'public.cartera_suscripcion'::regclass)
    and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion' and column_name = 'periodo_carga' and is_nullable = 'NO') = 1);
  -- 6. Retiro del historial (P7): una partición de hace 15 días con una fila se retira; la de hoy no
  perform scrr.f_preparar_historial(v_hoy - 15, v_hoy - 15);
  v_nom := 'cartera_historial_' || to_char(v_hoy - 15, 'YYYYMMDD');
  insert into scrr.cartera_historial (fecha_dato, contrato, carga_id) values (v_hoy - 15, B + 1, c1::uuid);
  r := scrr.f_retirar_historial('ztscrr.sup@emdupar.gov.co', 'ZTSCRR retiro de prueba del historial');
  perform pg_temp.ok('L14 retiro: la partición de hace 15 días se separa y se borra, con su conteo en la auditoría',
    to_regclass('scrr.' || v_nom) is null and exists (select 1 from jsonb_array_elements(r -> 'retiradas') x where x ->> 'particion' = v_nom and (x ->> 'filas')::int = 1)
    and exists (select 1 from public.geoportal_auditoria where accion = 'scrr_retiro_particion' and referencia = v_nom), r::text);
  perform pg_temp.ok('L15 el retiro deja las de los últimos 10 días y prepara las de los próximos 45',
    to_regclass('scrr.cartera_historial_' || to_char(v_hoy - 1, 'YYYYMMDD')) is not null and to_regclass('scrr.cartera_historial_' || to_char(v_hoy + 45, 'YYYYMMDD')) is not null
    and (select count(*) from scrr.v_cartera_vigente where fecha_dato = v_hoy - 1) = 200);
  begin
    perform scrr.f_retirar_historial('x', 'corto');
    perform pg_temp.ok('L16 el retiro exige correo y motivo', false);
  exception when others then perform pg_temp.ok('L16 el retiro exige correo y motivo', true);
  end;
end $$;

do $$
declare v_tot int; v_ok int; v_fallas text;
begin
  select count(*), count(*) filter (where ok), string_agg(format('%s — %s', nombre, coalesce(detalle, '')), E'\n' order by n) filter (where not ok) into v_tot, v_ok, v_fallas from ztscrr_res;
  if v_ok = v_tot then raise exception 'RESULTADO LOCAL: % de % pruebas correctas — SIN FALLAS (este ERROR es el esperado: deshace todo)', v_ok, v_tot;
  else raise exception 'RESULTADO LOCAL: % de % pruebas correctas — FALLAS:%', v_ok, v_tot, E'\n' || v_fallas; end if;
end $$;
rollback;
