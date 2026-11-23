-- =====================================================================
-- SCRR · CORTE 2 · 70 — PRUEBAS del primer commit (cargas del día). Dentro del ensayo: todo se deshace con el ERROR esperado del final.
-- Datos propios con prefijo ZTSCRR (correos ztscrr.*@emdupar.gov.co; contratos de 12 dígitos 91000000xxxx, que no existen en la cartera real).
-- Cada prueba cuenta SOLO sus filas. Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- En producción public.cartera_suscripcion tiene la cartera real: estas pruebas NO cierran una carga de cartera (el cierre retiraría los contratos reales
-- que no vienen en el archivo de prueba). Prueban que la guardia lo impide y revierten lo que aplicaron. El cierre completo de cartera (salidas, reemplazo,
-- reversión después del cierre) se prueba solo en local: pruebas_locales/75_pruebas_cierre_local.sql.
-- Sin tablas temporales que se borren al confirmar (regla de David, 21-nov): la tabla de resultados se deshace con el ERROR esperado del final.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
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
-- una fila de cartera de prueba (todas las columnas de la plantilla)
-- p_pend = facturas pendientes; el ciclo de prueba sale del contrato: 97 (sin calendario), 98 (pago oportuno ya pasó) o 99 (aún no pasa)
create function pg_temp.fc(p_contrato bigint, p_saldo numeric, p_pend int, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $f$
  select jsonb_build_object('contrato', p_contrato::text, 'estado', 'ACTIVO', 'identificacion', 'ZT' || p_contrato, 'nombre', 'ZTSCRR SUSCRIPTOR ' || p_contrato,
         'correo', 'zt' || p_contrato || '@ejemplo.invalid', 'telefono', '3000000000', 'direccion', 'ZTSCRR CALLE ' || (p_contrato % 1000), 'barrio', 'ztscrr barrio ' || (p_contrato % 3),
         'categoria', '1 - RESIDENCIAL', 'subcategoria', '2 - ESTRATO 2', 'ciclo', (97 + (p_contrato % 3))::text, 'facturas_pendientes', p_pend::text,
         'deuda_total', (p_saldo + 1000)::text, 'saldo_pendiente', p_saldo::text, 'saldo_a_favor', '0', 'valor_reclamo', '0',
         'saldo_financiado', '1000', 'serial_medidor', 'ZTM' || p_contrato, 'codigo_reparto', 'R1', 'ruta', 'ZTRUTA') || p_extra $f$;
create function pg_temp.lote(p_carga text, p_lote int, p_filas jsonb, p_sol text default 'ztscrr.sup@emdupar.gov.co') returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_scrr_carga_lote(%L, %L::uuid, %s, %L::jsonb)', p_sol, p_carga, p_lote, p_filas)) $f$;
create function pg_temp.iniciar(p_tipo text, p_fecha date, p_sha text, p_filas int, p_sol text default 'ztscrr.sup@emdupar.gov.co') returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_scrr_carga_iniciar(%L, %L, %L::date, %L, %L, %s)', p_sol, p_tipo, p_fecha, 'ztscrr_' || p_tipo || '.xlsx', p_sha, p_filas)) $f$;
create function pg_temp.sha(p text) returns text language sql as $f$ select md5(p) || md5(p || 'x') $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta, ver_registro_tecnico) values
  ('ztscrr.adm@emdupar.gov.co', 'ZTSCRR Admin', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false, false),
  ('ztscrr.sup@emdupar.gov.co', 'ZTSCRR Supervisor comercial', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, true, true, false),
  ('ztscrr.supcampo@emdupar.gov.co', 'ZTSCRR Supervisor solo campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false, false),
  ('ztscrr.supacta@emdupar.gov.co', 'ZTSCRR Supervisor de actas', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, true, false),
  ('ztscrr.op@emdupar.gov.co', 'ZTSCRR Operario', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, true, false, false),
  ('ztscrr.tec@emdupar.gov.co', 'ZTSCRR Solo Técnica', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false, true),
  ('ztscrr.inactivo@emdupar.gov.co', 'ZTSCRR Inactivo', 'consulta', false, 'sin_restriccion', 'todos', false, true, true, true, true, false);

do $$
declare
  A text := 'ztscrr.adm@emdupar.gov.co'; S text := 'ztscrr.sup@emdupar.gov.co'; SC text := 'ztscrr.supcampo@emdupar.gov.co';
  r jsonb; c1 text; c2 text; cp text; ca text; v_hoy date := (now() at time zone 'America/Bogota')::date; f jsonb; t0 timestamptz; v_lote int;
  B bigint := 910000000000;   -- base de los contratos de prueba
  v_reales bigint; v_tope numeric; v_esperado_bloqueo boolean;
begin
  -- ===== 00. Quién entra al modo «Cartera» =====
  r := pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', S));
  perform pg_temp.ok('00.01 el Supervisor comercial (dashboard_campo) entra', pg_temp.err(r) = 'OK' and r ->> 'correo' = S and (r ->> 'es_admin')::boolean = false, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', SC));
  perform pg_temp.ok('00.02 el supervisor con solo dashboard_campo también entra', pg_temp.err(r) = 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', A));
  perform pg_temp.ok('00.03 el administrador entra (sin casillas)', pg_temp.err(r) = 'OK' and (r ->> 'es_admin')::boolean, r::text);
  perform pg_temp.ok('00.04 el supervisor de actas sin dashboard_campo: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', 'ztscrr.supacta@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.05 el operario: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', 'ztscrr.op@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.06 la persona solo de Técnica: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', 'ztscrr.tec@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.07 una persona inactiva con las casillas: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', 'ztscrr.inactivo@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.08 sin correo: 28000', pg_temp.err(pg_temp.rpc('public.geoportal_scrr_contexto(null)')) = '28000');
  r := pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', S));
  perform pg_temp.ok('00.09 contexto: las 17 anomalías DEFINITIVAS en el orden de la decisión 9 (1 PAGO EFECTUADO … 17 OTRO MEDIDOR)',
    jsonb_array_length(r -> 'anomalias') = 17 and not (select bool_or((x ->> 'provisional')::boolean) from jsonb_array_elements(r -> 'anomalias') x)
    and r -> 'anomalias' -> 0 ->> 'nombre' = 'PAGO EFECTUADO' and r -> 'anomalias' -> 16 ->> 'nombre' = 'OTRO MEDIDOR' and r -> 'anomalias' -> 7 ->> 'nombre' = 'PREDIO SOLO');
  perform pg_temp.ok('00.10 contexto: se escogen Suspensión, Corte y Gestión de cobro; solo Corte admite drástico',
    (select string_agg(x ->> 'codigo', ',' order by (x ->> 'id')::int) from jsonb_array_elements(r -> 'tipos_actividad') x where (x ->> 'seleccionable')::boolean) = 'suspension,corte,gestion_cobro'
    and (select string_agg(x ->> 'codigo', ',') from jsonb_array_elements(r -> 'tipos_actividad') x where (x ->> 'admite_drastico')::boolean) = 'corte');
  perform pg_temp.ok('00.11 contexto: historial 10 días, pagos 13 meses, lotes de 2.000',
    (r -> 'parametros' ->> 'ventana_dias_historial')::int = 10 and (r -> 'parametros' ->> 'retencion_meses_pagos')::int = 13 and (r -> 'parametros' ->> 'lote_filas')::int = 2000);

  -- ===== 01. Iniciar =====
  perform pg_temp.ok('01.01 tipo de carga desconocido: 22023', pg_temp.err(pg_temp.iniciar('control', v_hoy, pg_temp.sha('a'), 10)) = '22023');
  perform pg_temp.ok('01.02 fecha del dato futura: 22023', pg_temp.err(pg_temp.iniciar('cartera', v_hoy + 1, pg_temp.sha('a'), 10)) = '22023');
  perform pg_temp.ok('01.03 huella no válida: 22023', pg_temp.err(pg_temp.iniciar('cartera', v_hoy, 'abc', 10)) = '22023');
  perform pg_temp.ok('01.04 más filas que el tope (250.000): 22023', pg_temp.err(pg_temp.iniciar('cartera', v_hoy, pg_temp.sha('a'), 250001)) = '22023');
  perform pg_temp.ok('01.05 el operario no inicia cargas: 42501', pg_temp.err(pg_temp.iniciar('cartera', v_hoy, pg_temp.sha('a'), 10, 'ztscrr.op@emdupar.gov.co')) = '42501');
  -- calendario de prueba del período de hoy para los ciclos 98 (pago oportuno ayer: ya pasó) y 99 (mañana: no ha pasado); el 97 queda sin calendario
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 98, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy - 1, v_hoy - 1));
  perform pg_temp.ok('01.09 calendario: el supervisor agrega el ciclo 98 (nuevo, sin motivo)', pg_temp.err(r) = 'OK' and (r ->> 'nuevo')::boolean, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 99, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy + 1, v_hoy + 2));
  perform pg_temp.ok('01.10 calendario: y el ciclo 99', pg_temp.err(r) = 'OK', r::text);
  -- cartera de prueba: 2.003 filas (2 lotes: 2.000 + 3)
  r := pg_temp.iniciar('cartera', v_hoy, pg_temp.sha('cartera1'), 2003);
  c1 := r ->> 'carga_id';
  perform pg_temp.ok('01.06 inicia la cartera: 2 lotes de 2.000', pg_temp.err(r) = 'OK' and (r ->> 'lotes')::int = 2 and (r ->> 'repetido')::boolean = false, r::text);
  r := pg_temp.iniciar('cartera', v_hoy, pg_temp.sha('cartera1'), 2003);
  perform pg_temp.ok('01.07 el mismo archivo otra vez devuelve la misma carga (reintento)', r ->> 'carga_id' = c1 and (r ->> 'repetido')::boolean, r::text);
  perform pg_temp.ok('01.08 otro archivo de cartera con una abierta: 55000', pg_temp.err(pg_temp.iniciar('cartera', v_hoy, pg_temp.sha('otra'), 5)) = '55000');

  -- ===== 02. Lotes =====
  -- lote 1: 2.000 contratos B+1..B+2000; con saldo los impares; el B+1 con 7 vencidas y reclamo; B+3 con categoría «-1»
  -- con saldo los impares; B+1 (ciclo 99) con 8 pendientes y reclamo; B+3 (ciclo 98) con categoría «-1»; B+2 con cifras VACÍAS (valen cero). Ciclo = 97 + (contrato mod 3)
  select jsonb_agg(case when g = 1 then pg_temp.fc(B + g, 150000, 8, '{"valor_reclamo": "25000"}')
                        when g = 2 then pg_temp.fc(B + g, 0, 0, '{"deuda_total": "", "saldo_financiado": " "}') - 'saldo_a_favor'
                        when g = 3 then pg_temp.fc(B + g, 9000, 2, '{"categoria": "-1 - ------"}')
                        when g % 2 = 1 then pg_temp.fc(B + g, 20000 + g, (g % 30)::int + 1)
                        else pg_temp.fc(B + g, 0, 0) end order by g) into f
    from generate_series(1, 2000) g;
  perform pg_temp.ok('02.01 un lote con menos filas de las que le tocan: 22023', pg_temp.err(pg_temp.lote(c1, 1, f - 0)) = '22023');
  t0 := clock_timestamp();
  r := pg_temp.lote(c1, 1, f);
  perform pg_temp.ok('02.02 lote 1 de 2.000 filas recibido (' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms)', pg_temp.err(r) = 'OK' and (r ->> 'filas')::int = 2000, r::text);
  r := pg_temp.lote(c1, 1, f);
  perform pg_temp.ok('02.03 el mismo lote otra vez no duplica', (r ->> 'repetido')::boolean and (select count(*) from scrr.paso_cartera where carga_id = c1::uuid) = 2000, r::text);
  perform pg_temp.ok('02.04 el lote 1 con otro contenido: 55000', pg_temp.err(pg_temp.lote(c1, 1, jsonb_set(f, '{0,saldo_pendiente}', '"1"'))) = '55000');
  -- lote 2: tres filas con errores distintos (todas son rechazos del servidor)
  r := pg_temp.lote(c1, 2, jsonb_build_array(
         pg_temp.fc(B + 2001, 1000, 1, '{"contrato": "12A"}'),
         pg_temp.fc(B + 2002, 1000, 1, '{"deuda_total": "mil pesos"}'),
         pg_temp.fc(B + 2003, 1000, 1, '{"ciclo": "X9"}')));
  perform pg_temp.ok('02.05 lote 2 con 3 filas con error queda en el paso con su causa',
    pg_temp.err(r) = 'OK' and (select string_agg(error, ' | ' order by fila) from scrr.paso_cartera where carga_id = c1::uuid and lote = 2)
      = 'Contrato ausente o no numérico | Cifra con formato no válido (vacío vale cero) | Ciclo no válido', r::text);
  perform pg_temp.ok('02.07 cifras vacías o ausentes valen CERO (David, 22-nov): la fila de B+2 se acepta con deuda total y saldos en 0',
    (select error is null and deuda_total = 0 and saldo_a_favor = 0 and saldo_financiado = 0 from scrr.paso_cartera where carga_id = c1::uuid and contrato = (B + 2)::text));
  perform pg_temp.ok('02.06 el paso guarda la cartera COMPLETA (P4): nombre, dirección y teléfono del archivo',
    (select nombre is not null and direccion is not null and telefono is not null from scrr.paso_cartera where carga_id = c1::uuid and contrato = (B + 1)::text));

  -- ===== 03. Validar =====
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, c1));
  perform pg_temp.ok('03.01 validar: 3 rechazadas de 2.003 (0,15 %), puede aplicar', pg_temp.err(r) = 'OK' and (r ->> 'filas_rechazadas')::int = 3 and (r ->> 'puede_aplicar')::boolean, r::text);
  perform pg_temp.ok('03.02 validar: 1.000 con saldo pendiente, con reclamo 1, comodín o «-1» 1',
    (r ->> 'con_saldo_pendiente')::int = 1000 and (r ->> 'con_valor_reclamo')::int = 1 and (r ->> 'comodin_o_categoria_menos_1')::int = 1, r::text);
  perform pg_temp.ok('03.03 validar: vencidas derivadas (todas las de saldo tienen al menos una) y 333 con saldo en un ciclo sin calendario (el 97)',
    (r ->> 'con_facturas_vencidas')::int = 1000 and (r ->> 'con_saldo_sin_calendario')::int = 333 and r -> 'ciclos_sin_calendario' = '[97]'::jsonb, r::text);
  perform pg_temp.ok('03.04 el lote ya no entra después de validar si la carga se aplica (ver 04.06)', true);

  -- ===== 04. Aplicar por lotes (cartera) =====
  -- Antes: una fila «vieja» de un contrato de prueba que viene en el archivo, y otra de un contrato de prueba cuyo renglón del archivo tiene error
  insert into public.cartera_suscripcion (contrato, estado, nombre, direccion, saldo_pendiente, periodo_carga) values
    ((B + 2)::text, 'ZTVIEJO', 'ZTSCRR VIEJO', 'ZTSCRR DIR VIEJA', 777, '20261101'),
    ((B + 2002)::text, 'ZTVIEJO', 'ZTSCRR NO SE TOCA', 'ZTSCRR DIR', 555, '20261101');
  perform pg_temp.ok('04.01 el operario no aplica: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', 'ztscrr.op@emdupar.gov.co', c1))) = '42501');
  perform pg_temp.ok('04.02 cerrar antes de aplicar los lotes: 55000', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, c1))) = '55000');
  t0 := clock_timestamp();
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, c1));
  perform pg_temp.ok('04.03 lote 1 aplicado: 1.000 al historial y 2.000 filas nuevas en cartera_suscripcion (' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms)',
    pg_temp.err(r) = 'OK' and (r ->> 'historial')::int = 1000 and (r ->> 'suscripcion_filas_nuevas')::int = 2000 and (r ->> 'suscripcion_filas_retiradas')::int = 1, r::text);
  perform pg_temp.ok('04.04 el historial guarda vencidas DERIVADAS: ciclo 99 (aún no pasa el pago oportuno) 8 pendientes → 7; ciclo 98 (ya pasó) 2 → 2; ciclo 97 (sin calendario) 6 → 5',
    (select facturas_vencidas = 7 and facturas_pendientes = 8 from scrr.cartera_historial where carga_id = c1::uuid and contrato = B + 1)
    and (select facturas_vencidas = 2 and facturas_pendientes = 2 from scrr.cartera_historial where carga_id = c1::uuid and contrato = B + 3)
    and (select facturas_vencidas = 5 and facturas_pendientes = 6 from scrr.cartera_historial where carga_id = c1::uuid and contrato = B + 5));
  perform pg_temp.ok('04.04b el historial guarda reclamo y la marca del «-1»; sin nombre ni dirección',
    (select valor_reclamo = 25000 from scrr.cartera_historial where carga_id = c1::uuid and contrato = B + 1)
    and (select marca = 1 from scrr.cartera_historial where carga_id = c1::uuid and contrato = B + 3)
    and not exists (select 1 from information_schema.columns where table_schema = 'scrr' and table_name = 'cartera_historial' and column_name in ('nombre','direccion','telefono','identificacion','correo')));
  perform pg_temp.ok('04.05 cartera_suscripcion: el contrato viejo quedó con lo del archivo y su fila anterior en el respaldo',
    (select count(*) = 1 and min(nombre) = 'ZTSCRR SUSCRIPTOR ' || (B + 2) and min(periodo_carga) = to_char(v_hoy, 'YYYYMMDD') from public.cartera_suscripcion where contrato = (B + 2)::text)
    and (select filas -> 0 ->> 'nombre' = 'ZTSCRR VIEJO' and origen = 'archivo' from scrr.suscripcion_respaldo where carga_id = c1::uuid and contrato = (B + 2)::text)
    and (select filas = '[]'::jsonb from scrr.suscripcion_respaldo where carga_id = c1::uuid and contrato = (B + 1)::text));
  perform pg_temp.ok('04.06 ya aplicando, la carga no admite lotes nuevos: 55000', pg_temp.err(pg_temp.lote(c1, 2, '[]'::jsonb)) = '55000');
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, c1));
  perform pg_temp.ok('04.07 aplicar el lote 1 otra vez no duplica', (r ->> 'repetido')::boolean and (select count(*) from public.cartera_suscripcion where contrato like '91000000%') = 2001, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 2)', S, c1));
  perform pg_temp.ok('04.08 lote 2 (todas con error) no toca cartera_suscripcion: la fila del contrato con error sigue igual',
    pg_temp.err(r) = 'OK' and (r ->> 'suscripcion_filas_nuevas')::int = 0
    and (select nombre from public.cartera_suscripcion where contrato = (B + 2002)::text) = 'ZTSCRR NO SE TOCA', r::text);
  perform pg_temp.ok('04.09 estado de la carga: aplicando, 2 lotes aplicados',
    (select scrr.f_estado_carga(c1::uuid)) = 'aplicando' and jsonb_array_length(pg_temp.rpc(format('public.geoportal_scrr_carga_estado(%L, %L::uuid)', S, c1)) -> 'lotes_aplicados') = 2);

  -- ===== 05. Cierre de cartera: la guardia contra un archivo incompleto =====
  select count(*) into v_reales from public.cartera_suscripcion where contrato is not null and contrato not like '91000000%';
  v_tope := (scrr.f_param('tope_salidas_suscripcion_pct'))::numeric;
  if v_reales = 0 then   -- base local sin cartera real: se siembran 1.000 contratos de prueba que «no vienen en el archivo»
    insert into public.cartera_suscripcion (contrato, estado, nombre, periodo_carga) select (B + 5000 + g)::text, 'ZTVIEJO', 'ZTSCRR AUSENTE', '20261101' from generate_series(1, 1000) g;
  end if;
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, c1));
  perform pg_temp.ok('05.01 cerrar con más del 5 % de la cartera ausente del archivo: 55000 y no retira nada',
    pg_temp.err(r) = '55000' and r ->> 'msg' like '%no vienen en el archivo%' and (select count(*) from public.cartera_suscripcion) >= v_reales + 2001, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, null, true, null)', S, c1));
  perform pg_temp.ok('05.02 confirmarlo sin motivo: 22023', pg_temp.err(r) = '22023', r::text);

  -- ===== 06. Revertir cartera_suscripcion y anular =====
  perform pg_temp.ok('06.01 anular sin revertir la tabla: 55000', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, c1, 'ZTSCRR prueba de anulación'))) = '55000');
  perform pg_temp.ok('06.02 revertir sin motivo: 22023', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_suscripcion_revertir(%L, %L::uuid, %L)', S, c1, 'corto'))) = '22023');
  r := pg_temp.rpc(format('public.geoportal_scrr_suscripcion_revertir(%L, %L::uuid, %L)', S, c1, 'ZTSCRR revierto la carga de prueba'));
  perform pg_temp.ok('06.03 revertir: quita las 2.001 filas del archivo y restaura la vieja; no quedan pendientes',
    pg_temp.err(r) = 'OK' and (r ->> 'pendientes')::int = 0 and (r ->> 'filas_restauradas')::int = 1
    and (select count(*) from public.cartera_suscripcion where contrato like '91000000%' and contrato::bigint <= B + 2003) = 2
    and (select nombre from public.cartera_suscripcion where contrato = (B + 2)::text) = 'ZTSCRR VIEJO'
    and (select nombre from public.cartera_suscripcion where contrato = (B + 2002)::text) = 'ZTSCRR NO SE TOCA', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, c1, 'ZTSCRR prueba de anulación'));
  perform pg_temp.ok('06.04 ya revertida, se anula; el historial queda oculto (no borrado)',
    pg_temp.err(r) = 'OK' and scrr.f_estado_carga(c1::uuid) = 'anulada'
    and (select count(*) from scrr.cartera_historial where carga_id = c1::uuid) = 1000 and (select count(*) from scrr.v_cartera_vigente where carga_id = c1::uuid) = 0, r::text);
  perform pg_temp.ok('06.05 la auditoría registra iniciar, validar, revertir y anular de la carga',
    (select count(distinct accion) from public.geoportal_auditoria where referencia = c1 and accion in ('scrr_carga_iniciar','scrr_carga_validar','scrr_suscripcion_revertir','scrr_carga_anular')) = 4);
  begin
    update scrr.cargas set archivo_nombre = 'x' where id = c1::uuid;
    perform pg_temp.ok('06.06 las tablas de hechos son de solo inserción (update de una carga: 55000)', false);
  exception when sqlstate '55000' then
    perform pg_temp.ok('06.06 las tablas de hechos son de solo inserción (update de una carga: 55000)', true);
  end;

  -- ===== 07. Pagos (plantilla provisional: contrato, fecha de pago, monto) =====
  r := pg_temp.iniciar('pagos', v_hoy, pg_temp.sha('pagos1'), 6);
  cp := r ->> 'carga_id';
  r := pg_temp.lote(cp, 1, jsonb_build_array(
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 3)::text, 'fecha_pago', (v_hoy - 1)::text, 'monto', '9000'),
         jsonb_build_object('contrato', (B + 5)::text, 'fecha_pago', (v_hoy + 1)::text, 'monto', '100'),
         jsonb_build_object('contrato', (B + 7)::text, 'fecha_pago', (v_hoy - interval '2 years')::date::text, 'monto', '100'),
         jsonb_build_object('contrato', (B + 9)::text, 'fecha_pago', v_hoy::text, 'monto', '0')));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, cp));
  perform pg_temp.ok('07.01 pagos: rechaza fecha futura, fuera de los 13 meses y monto cero; 3 válidos (50 % rechazado: no se aplica)',
    (r ->> 'pagos_validos')::int = 3 and (r -> 'causas_rechazo' ->> 'Fecha de pago futura')::int = 1 and (r -> 'causas_rechazo' ->> 'Fecha de pago fuera de la retención')::int = 1
    and (r -> 'causas_rechazo' ->> 'Monto ausente, en cero o no válido')::int = 1 and (r ->> 'puede_aplicar')::boolean = false, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, cp));
  perform pg_temp.ok('07.02 con más del 5 % rechazado no se aplica: 55000', pg_temp.err(r) = '55000', r::text);
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, cp, 'ZTSCRR archivo de pagos con errores'));
  r := pg_temp.iniciar('pagos', v_hoy, pg_temp.sha('pagos2'), 3);
  cp := r ->> 'carga_id';
  perform pg_temp.lote(cp, 1, jsonb_build_array(
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 3)::text, 'fecha_pago', (v_hoy - 1)::text, 'monto', '9000')));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, cp));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, cp));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, cp));
  perform pg_temp.ok('07.03 pagos aplicados: dos pagos idénticos del mismo día quedan como ordinal 1 y 2',
    pg_temp.err(r) = 'OK' and (r -> 'resultado' ->> 'pagos_nuevos')::int = 3
    and (select string_agg(ordinal::text, ',' order by ordinal) from scrr.pagos_contrato where contrato = B + 1 and carga_id = cp::uuid) = '1,2', r::text);
  r := pg_temp.iniciar('pagos', v_hoy, pg_temp.sha('pagos3'), 4);
  perform pg_temp.ok('07.04 pagos del mismo día no se reemplazan: una carga de pagos con esa fecha ya aplicada exige otra fecha o 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.iniciar('pagos', v_hoy - 1, pg_temp.sha('pagos3'), 4);
  cp := r ->> 'carga_id';
  perform pg_temp.lote(cp, 1, jsonb_build_array(
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 3)::text, 'fecha_pago', (v_hoy - 1)::text, 'monto', '9000')));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, cp));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, cp));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, cp));
  perform pg_temp.ok('07.05 recargar pagos que se solapan no duplica: solo entra el tercer pago idéntico (ordinal 3)',
    (r -> 'resultado' ->> 'pagos_nuevos')::int = 1 and (r -> 'resultado' ->> 'pagos_ya_existentes')::int = 3
    and (select count(*) from scrr.pagos_contrato where contrato = B + 1) = 3, r::text);
  perform pg_temp.ok('07.06 pagos aplicados no se anulan: 55000', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, cp, 'ZTSCRR intento anular pagos'))) = '55000');

  -- ===== 08. Actividades (plantilla de la decisión 10, con la marca de drástico en Corte) =====
  r := pg_temp.iniciar('actividades', v_hoy, pg_temp.sha('act1'), 9);
  ca := r ->> 'carga_id';
  r := pg_temp.lote(ca, 1, jsonb_build_array(
    jsonb_build_object('contrato', (B + 1)::text, 'acta', 'A1', 'actividad', 'Suspensión', 'drastico', 'NO', 'estado', '3', 'anomalia', '', 'fecha', (v_hoy - 2)::text, 'hora_inicial', '08:10', 'hora_final', '08:30', 'lectura', '1234', 'medidor', 'M1', 'marca', 'ZTMARCA', 'operario', 'ZTSCRR OPERARIO'),
    jsonb_build_object('contrato', (B + 3)::text, 'acta', 'A2', 'actividad', 'CORTE', 'drastico', 'SÍ', 'estado', '3', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 5)::text, 'acta', 'A3', 'actividad', 'Corte', 'drastico', 'NO', 'estado', '4', 'anomalia', '8', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 7)::text, 'actividad', 'Reconexión', 'drastico', 'NO', 'estado', '3', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 9)::text, 'actividad', 'Suspensión', 'drastico', 'SÍ', 'estado', '3', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 11)::text, 'actividad', 'Corte', 'drastico', 'NO', 'estado', '4', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 13)::text, 'actividad', 'Corte', 'drastico', 'NO', 'estado', '4', 'anomalia', '18', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 15)::text, 'actividad', 'Lectura', 'drastico', 'NO', 'estado', '3', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 17)::text, 'actividad', 'Corte', 'drastico', 'NO', 'estado', '3', 'fecha', (v_hoy - 1)::text, 'hora_inicial', '25:00')));
  perform pg_temp.ok('08.01 actividades: cada error con su causa (drástico fuera de Corte, inefectiva sin anomalía, anomalía 18, actividad no reconocida, hora)',
    (select string_agg(coalesce(error, 'ok'), ' | ' order by fila) from scrr.paso_actividades where carga_id = ca::uuid)
      = 'ok | ok | ok | ok | La marca de drástico solo aplica a Corte | Inefectiva sin anomalía | Anomalía fuera del catálogo (1 a 17) | Actividad no reconocida | Hora inicial no válida', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, ca));
  perform pg_temp.ok('08.02 con 5 de 9 rechazadas no se aplica', (r ->> 'puede_aplicar')::boolean = false and (r ->> 'cortes_drasticos')::int = 1, r::text);
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, ca, 'ZTSCRR archivo de actividades con errores'));
  r := pg_temp.iniciar('actividades', v_hoy, pg_temp.sha('act2'), 4);
  ca := r ->> 'carga_id';
  perform pg_temp.lote(ca, 1, jsonb_build_array(
    jsonb_build_object('contrato', (B + 1)::text, 'acta', 'A1', 'actividad', 'Suspensión', 'drastico', 'NO', 'estado', '3', 'fecha', (v_hoy - 2)::text, 'hora_inicial', '08:10', 'hora_final', '08:30', 'lectura', '1234', 'medidor', 'M1', 'marca', 'ZTMARCA', 'operario', 'ZTSCRR OPERARIO'),
    jsonb_build_object('contrato', (B + 3)::text, 'acta', 'A2', 'actividad', 'CORTE', 'drastico', 'SÍ', 'estado', '3', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 5)::text, 'acta', 'A3', 'actividad', 'Corte', 'drastico', 'NO', 'estado', '4', 'anomalia', '8', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 3)::text, 'acta', 'A2', 'actividad', 'CORTE', 'drastico', 'SÍ', 'estado', '3', 'fecha', (v_hoy - 1)::text)));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, ca));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, ca));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, ca));
  perform pg_temp.ok('08.03 actividades aplicadas: 3 actas (la repetida en el archivo cuenta una vez)', pg_temp.err(r) = 'OK' and (r -> 'resultado' ->> 'actas_nuevas')::int = 3, r::text);
  perform pg_temp.ok('08.04 estado del servicio: suspendido, cortado drástico; la inefectiva no cambia el estado',
    (select estado from scrr.v_estado_servicio where contrato = B + 1) = 'suspendido' and (select estado from scrr.v_estado_servicio where contrato = B + 3) = 'cortado_drastico'
    and not exists (select 1 from scrr.v_estado_servicio where contrato = B + 5));
  perform pg_temp.ok('08.05 el acta guarda anomalía, horas, lectura, medidor, marca y operario',
    (select anomalia = 8 and resultado = 'inefectiva' from scrr.actas where contrato = B + 5)
    and (select hora_inicio = '08:10' and hora_fin = '08:30' and lectura = 1234 and medidor = 'M1' and marca_medidor = 'ZTMARCA' and operario = 'ZTSCRR OPERARIO' from scrr.actas where contrato = B + 1));

  -- ===== 09. Cargas de hoy, lista y vaciado =====
  r := pg_temp.rpc(format('public.geoportal_scrr_cargas_hoy(%L)', S));
  perform pg_temp.ok('09.01 «falta cargar hoy»: la cartera de hoy falta (la de prueba se anuló); pagos al día',
    (select (x ->> 'al_dia')::boolean = false from jsonb_array_elements(r -> 'tipos') x where x ->> 'tipo' = 'cartera')
    and (select (x ->> 'al_dia')::boolean from jsonb_array_elements(r -> 'tipos') x where x ->> 'tipo' = 'pagos'), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_cargas_lista(%L, 100)', S));
  perform pg_temp.ok('09.02 la lista muestra las 6 cargas de prueba con su estado',
    (select count(*) from jsonb_array_elements(r -> 'cargas') x where x ->> 'autor' = S) = 6);
  r := pg_temp.rpc(format('public.geoportal_scrr_vaciar_paso(%L)', S));
  perform pg_temp.ok('09.03 vaciar el paso hoy no vacía nada de prueba (tienen menos de 7 días)',
    pg_temp.err(r) = 'OK' and (select count(*) from scrr.paso_cartera where carga_id = c1::uuid) = 2003, r::text);

  -- ===== 11. Calendario =====
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_lista(%L, %L)', S, '202611'));
  perform pg_temp.ok('11.01 calendario de noviembre sembrado: 24 ciclos; el 15 con pago oportuno 12/11 y suspensión 13/11',
    (select count(*) from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int between 1 and 24) = 24 and (select x ->> 'pago_oportuno' = '2026-11-12' and x ->> 'fecha_suspension' = '2026-11-13' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 15), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 98, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy - 1, v_hoy - 1));
  perform pg_temp.ok('11.02 guardar el mismo ciclo sin cambios: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 98, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy - 1, v_hoy));
  perform pg_temp.ok('11.03 cambiar un ciclo ya guardado sin motivo: 22023', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 98, %L::date, %L::date, %L::jsonb, %L)', S, to_char(v_hoy, 'YYYYMM'), v_hoy - 1, v_hoy, '{"reparto": "2026-11-05"}', 'ZTSCRR se corre la suspensión'));
  perform pg_temp.ok('11.04 con motivo se guarda una versión nueva (la anterior queda en el historial) y las etapas de contexto',
    pg_temp.err(r) = 'OK' and (select count(*) from scrr.calendario_ciclos where periodo = to_char(v_hoy, 'YYYYMM') and ciclo = 98) = 2
    and (select etapas ->> 'reparto' from scrr.v_calendario_vigente where periodo = to_char(v_hoy, 'YYYYMM') and ciclo = 98) = '2026-11-05', r::text);
  perform pg_temp.ok('11.05 suspensión antes del pago oportuno: 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 96, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy, v_hoy - 1))) = '22023');
  perform pg_temp.ok('11.06 ciclo 100: 22023; el operario no toca el calendario: 42501',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 100, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy, v_hoy))) = '22023'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 96, %L::date, %L::date)', 'ztscrr.op@emdupar.gov.co', to_char(v_hoy, 'YYYYMM'), v_hoy, v_hoy))) = '42501');

  -- ===== 12. Contratos con control y excluidos manuales =====
  r := pg_temp.rpc(format('public.geoportal_scrr_control_agregar(%L, %L, %L, %L)', S, (B + 103)::text, 'insolvencia', 'ZTSCRR proceso de insolvencia'));
  perform pg_temp.ok('12.01 alta de control (insolvencia) con motivo', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.ok('12.02 la misma alta otra vez: 55000; sin motivo: 22023; el comodín: 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_control_agregar(%L, %L, %L, %L)', S, (B + 103)::text, 'insolvencia', 'ZTSCRR proceso de insolvencia'))) = '55000'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_control_agregar(%L, %L, %L, %L)', S, (B + 104)::text, 'insolvencia', 'corto'))) = '22023'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_control_agregar(%L, %L, %L, %L)', S, '99999999', 'insolvencia', 'ZTSCRR el comodín no es un contrato'))) = '22023');
  r := pg_temp.rpc(format('public.geoportal_scrr_control_agregar(%L, %L, %L, %L)', S, (B + 105)::text, 'reclamo_manual', 'ZTSCRR reclamo que no está en el sistema'));
  r := pg_temp.rpc(format('public.geoportal_scrr_control_lote(%L, %L::jsonb, %L, %L)', S, jsonb_build_array((B + 108)::text, (B + 108)::text, 'x12', '99999999', (B + 130)::text), 'excluido_manual', 'ZTSCRR excluidos por decisión del supervisor'));
  perform pg_temp.ok('12.03 excluidos por archivo con un motivo común (P10): 5 recibidos, 2 no válidos (texto y comodín), 2 nuevos (el repetido cuenta una vez)',
    pg_temp.err(r) = 'OK' and (r ->> 'recibidos')::int = 5 and (r ->> 'no_validos')::int = 2 and (r ->> 'repetidos_en_el_archivo')::int = 1 and (r ->> 'nuevos')::int = 2 and (r ->> 'ya_estaban')::int = 0
    and (select count(*) from scrr.control_eventos where contrato in (B + 108, B + 130) and origen = 'archivo') = 2, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_control_baja(%L, %L, %L, %L)', S, (B + 130)::text, 'excluido_manual', 'ZTSCRR vuelve a ser elegible'));
  perform pg_temp.ok('12.04 baja con motivo: el contrato sale de la lista y queda el historial (alta y baja)',
    pg_temp.err(r) = 'OK' and not exists (select 1 from scrr.v_control_vigente where contrato = B + 130) and (select count(*) from scrr.control_eventos where contrato = B + 130) = 2, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_control_lista(%L, %L)', S, 'excluido'));
  perform pg_temp.ok('12.05 la lista de excluidos trae a B+108 y no a los de control; la de control trae insolvencia y reclamo manual',
    exists (select 1 from jsonb_array_elements(r -> 'vigentes') x where (x ->> 'contrato')::bigint = B + 108)
    and not exists (select 1 from jsonb_array_elements(r -> 'vigentes') x where (x ->> 'contrato')::bigint = B + 103)
    and (select count(*) from jsonb_array_elements(pg_temp.rpc(format('public.geoportal_scrr_control_lista(%L, %L)', S, 'control')) -> 'vigentes') x where (x ->> 'contrato')::bigint in (B + 103, B + 105)) = 2, r::text);

  -- ===== 13. Selección: una foto de cartera VIGENTE de prueba (sin tocar cartera_suscripcion), ciclo 98 =====
  ca := gen_random_uuid()::text;
  insert into scrr.cargas (id, tipo, fecha_dato, version, archivo_nombre, archivo_sha256, filas_leidas, autor)
    values (ca::uuid, 'cartera', v_hoy, (select max(version) + 1 from scrr.cargas where tipo = 'cartera' and fecha_dato = v_hoy), 'ztscrr_foto.xlsx', pg_temp.sha('foto'), 20, S);
  insert into scrr.carga_eventos (carga_id, evento, autor) values (ca::uuid, 'iniciada', S), (ca::uuid, 'aplicada', S);
  insert into scrr.barrios (nombre_norm) values ('ZTSCRR NORTE'), ('ZTSCRR SUR') on conflict do nothing;
  insert into scrr.cartera_historial (fecha_dato, version, contrato, en_cartera, marca, ciclo, ruta, codigo_reparto, barrio_id, facturas_pendientes, facturas_vencidas, deuda_total, saldo_pendiente, valor_reclamo, carga_id)
  select v_hoy, (select version from scrr.cargas where id = ca::uuid), B + n, n <> 120, case when n = 101 then 1 else 0 end, 98,
         case when n = 102 then 'ZTR1' else 'ZTR' || (n % 3) end, 'P' || n, (select id from scrr.barrios where nombre_norm = case when n = 112 then 'ZTSCRR SUR' else 'ZTSCRR NORTE' end),
         venc + 1, venc, sal + 1000, case when n = 120 then 0 else sal end, case when n = 104 then 5000 else 0 end, ca::uuid
    from (values (101, 3, 30000), (102, 3, 30000), (103, 3, 30000), (104, 3, 30000), (105, 3, 30000), (106, 3, 30000), (107, 3, 30000), (108, 3, 30000),
                 (109, 3, 3000), (110, 30, 30000), (111, 1, 20000), (112, 2, 21000), (113, 3, 22000), (114, 4, 23000), (115, 5, 24000), (120, 0, 0)) z(n, venc, sal);
  insert into scrr.cartera_historial (fecha_dato, version, contrato, ciclo, ruta, facturas_pendientes, facturas_vencidas, deuda_total, saldo_pendiente, carga_id)
    values (v_hoy, (select version from scrr.cargas where id = ca::uuid), B + 201, 99, 'ZTR', 4, 3, 40000, 40000, ca::uuid);
  -- facturados: todos menos B+102 (en el último período de hechos.facturacion_sspd)
  insert into hechos.facturacion_sspd (periodo, contrato)
    select coalesce((select max(periodo) from hechos.facturacion_sspd), to_char(v_hoy, 'YYYYMM')), (B + n)::text from generate_series(101, 201) n where n <> 102;
  -- pagos: B+106 pagó hoy todo su saldo (pago sin reflejar); B+111 abonó 1.000 hoy
  insert into scrr.pagos_contrato (contrato, fecha_pago, monto, ordinal, carga_id) values (B + 106, v_hoy, 30000, 1, ca::uuid), (B + 111, v_hoy, 1000, 1, ca::uuid);
  -- evento de suspensión de agua sobre B+107 (solo donde existe el doble local de Técnica; en producción no se toca)
  if to_regclass('redes.zz_doble_eventos_contrato') is not null then insert into redes.zz_doble_eventos_contrato values ((B + 107)::text, 1); end if;
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_previa(%L, 98, %L::jsonb)', S, '{"modo": "meses", "desde": 1, "hasta": 25}'));
  perform pg_temp.ok('13.01 embudo en su orden: comodín 1, no facturado 1, control 1, reclamo 2 (valor y manual), pago sin reflejar 1, excluido manual 1, saldo menor al mínimo 1, fuera del rango 1',
    pg_temp.err(r) = 'OK' and (r -> 'embudo' -> 'p0_comodin' ->> 'contratos')::int = 1 and (r -> 'embudo' -> 'p1_no_facturado_o_sin_ruta' ->> 'contratos')::int = 1
    and (r -> 'embudo' -> 'p2_control_vigente' ->> 'contratos')::int = 1 and (r -> 'embudo' -> 'p3_reclamo' ->> 'contratos')::int = 2
    and (r -> 'embudo' -> 'p4_pago_sin_reflejar' ->> 'contratos')::int = 1 and (r -> 'embudo' -> 'p6_excluido_manual' ->> 'contratos')::int = 1
    and (r -> 'embudo' -> 'p7_saldo_menor_al_minimo' ->> 'contratos')::int = 1 and (r -> 'embudo' -> 'f_fuera_del_rango' ->> 'contratos')::int = 1, r::text);
  v_esperado_bloqueo := to_regclass('redes.zz_doble_eventos_contrato') is not null;   -- aquí: ¿hay evento de prueba?
  perform pg_temp.ok('13.02 evento de suspensión de agua: el contrato dentro del evento SALE de la lista (o es candidato donde no hay evento)',
    coalesce((r -> 'embudo' -> 'p5_evento_suspension_agua' ->> 'contratos')::int, 0) = case when v_esperado_bloqueo then 1 else 0 end
    and (r ->> 'candidatos')::int = case when v_esperado_bloqueo then 5 else 6 end, r::text);
  perform pg_temp.ok('13.03 paz y salvo hoy se cuenta aparte (1); el abono de 1.000 MARCA y no excluye; el otro ciclo no se mezcla',
    (r -> 'embudo' -> 'p4_paz_y_salvo_hoy' ->> 'contratos')::int = 1 and (r ->> 'marcados_abono')::int = 1 and (r ->> 'universo')::int = 15, r::text);
  perform pg_temp.ok('13.04 la vista previa queda en la auditoría solo con conteos (sin contratos)',
    exists (select 1 from public.geoportal_auditoria where email = S and accion = 'scrr_seleccion_previa' and referencia = '98' and not (detalle::text ~ '9100000001'))
  );
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_previa(%L, 98, %L::jsonb)', S, jsonb_build_object('modo', 'meses', 'desde', 1, 'hasta', 25, 'barrio_id', (select id from scrr.barrios where nombre_norm = 'ZTSCRR SUR'))));
  perform pg_temp.ok('13.05 filtro de barrio: solo B+112', (r ->> 'candidatos')::int = 1, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_previa(%L, 98, %L::jsonb)', S, '{"modo": "monto", "desde": 22000, "hasta": 23500}'));
  perform pg_temp.ok('13.06 rango por monto: 22.000 a 23.500 → 2', (r ->> 'candidatos')::int = 2, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_previa(%L, 98, %L::jsonb)', S, '{"modo": "meses", "desde": 1, "hasta": 25, "segmento": "menos_de_n", "n": 3}'));
  perform pg_temp.ok('13.07 segmento «menos de 3 vencidas» (aproximado): 2', (r ->> 'candidatos')::int = 2 and (r ->> 'segmentos_aproximados')::boolean, r::text);
  perform pg_temp.ok('13.08 el operario no ve la selección: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_seleccion_previa(%L, 98, %L::jsonb)', 'ztscrr.op@emdupar.gov.co', '{}'))) = '42501');
  perform pg_temp.ok('13.09 generar con una actividad que no se escoge (reinstalación): 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_seleccion_generar(%L, 98, %L::jsonb, %L)', S, '{"modo": "meses", "desde": 1, "hasta": 25}', 'reinstalacion'))) = '22023');
  perform pg_temp.ok('13.10 generar sin candidatos: 55000',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_seleccion_generar(%L, 98, %L::jsonb, %L)', S, '{"modo": "meses", "desde": 20, "hasta": 25}', 'corte'))) = '55000');
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_generar(%L, 98, %L::jsonb, %L)', S, '{"modo": "meses", "desde": 1, "hasta": 25}', 'corte'));
  cp := r ->> 'corrida_id';
  perform pg_temp.ok('13.11 generar la corrida de Corte: guarda solo la lista (los candidatos), en orden de ruta y reparto, con la actividad',
    pg_temp.err(r) = 'OK' and (r ->> 'contratos')::int = case when v_esperado_bloqueo then 5 else 6 end
    and (select count(*) from scrr.corrida_contratos where corrida_id = cp::uuid) = (r ->> 'contratos')::int
    and (select string_agg(ruta, ',' order by orden) from scrr.corrida_contratos where corrida_id = cp::uuid) ~ '^(ZTR0,)*(ZTR1,?)*(ZTR2,?)*$'
    and (select t.codigo from scrr.corridas c join scrr.tipos_actividad t on t.id = c.actividad_id where c.id = cp::uuid) = 'corte', r::text);
  -- nombre y dirección para la lista (los resuelve la RPC de la cartera de suscripción; teléfono y correo NO salen)
  insert into public.cartera_suscripcion (contrato, nombre, direccion, telefono, correo, identificacion, barrio)
    select (B + n)::text, 'ZTSCRR NOMBRE ' || n, 'ZTSCRR CALLE ' || n, '3000000000', 'zt@ejemplo.invalid', 'ZTID' || n, 'ZTSCRR NORTE' from generate_series(111, 115) n;
  r := pg_temp.rpc(format('public.geoportal_scrr_lista(%L, %L::uuid, %L)', S, cp, 'excel'));
  perform pg_temp.ok('13.12 la lista lleva nombre y dirección (excepción P2), la deuda (P9) y la marca del abono; nunca teléfono, correo ni identificación',
    pg_temp.err(r) = 'OK' and (select x ->> 'nombre' = 'ZTSCRR NOMBRE 111' and x ->> 'direccion' = 'ZTSCRR CALLE 111' and (x ->> 'saldo_pendiente')::numeric = 20000
                                and x ->> 'marca' like 'Abonó%' from jsonb_array_elements(r -> 'filas') x where (x ->> 'contrato')::bigint = B + 111)
    and not (r::text ~ '3000000000|ejemplo\.invalid|ZTID'), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_lista(%L, %L::uuid, %L)', S, cp, 'impresion'));
  perform pg_temp.ok('13.13 cada descarga e impresión queda en la auditoría con sus filas',
    (select count(*) from public.geoportal_auditoria where referencia = cp and accion in ('scrr_lista_excel', 'scrr_lista_impresion')) = 2
    and exists (select 1 from public.geoportal_auditoria where referencia = cp and accion = 'scrr_corrida'));
  perform pg_temp.ok('13.14 el operario no descarga listas: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_lista(%L, %L::uuid, %L)', 'ztscrr.op@emdupar.gov.co', cp, 'excel'))) = '42501');
  r := pg_temp.rpc(format('public.geoportal_scrr_corridas(%L)', S));
  perform pg_temp.ok('13.15 la corrida aparece en la lista de corridas con su actividad', exists (select 1 from jsonb_array_elements(r -> 'corridas') x where x ->> 'corrida_id' = cp and x ->> 'actividad' = 'Corte'), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_opciones(%L, 98)', S));
  perform pg_temp.ok('13.16 opciones: los ciclos del período con su ventana y los barrios del ciclo (dependen del ciclo)',
    (select count(*) from jsonb_array_elements(r -> 'barrios') x where x ->> 'nombre' like 'ZTSCRR%') = 2
    and exists (select 1 from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 98 and (x ->> 'en_ventana')::boolean), r::text);

  -- ===== 14. Refresco del mapa comercial (las RPC que lo rodean; el REFRESH lo corre la Edge con el rol scrr_refresco) =====
  perform pg_temp.ok('14.01 iniciar el refresco con una carga de pagos: P0002',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_refresco_iniciar(%L, %L::uuid)', S, (select id from scrr.cargas where tipo = 'pagos' and autor = S limit 1)))) = 'P0002');
  r := pg_temp.rpc(format('public.geoportal_scrr_refresco_iniciar(%L, %L::uuid)', S, ca));
  perform pg_temp.ok('14.02 con una carga de cartera aplicada: autoriza y lo deja en la auditoría', pg_temp.err(r) = 'OK'
    and exists (select 1 from public.geoportal_auditoria where accion = 'scrr_refresco_mapa_inicio' and referencia = ca), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_refresco_cerrar(%L, %L::uuid, %L, 650)', S, ca, 'ok'));
  perform pg_temp.ok('14.03 cerrar con el resultado y el tiempo; un resultado desconocido: 22023', pg_temp.err(r) = 'OK'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_refresco_cerrar(%L, %L::uuid, %L, 1)', S, ca, 'quizas'))) = '22023', r::text);
  perform pg_temp.ok('14.04 el operario no pide el refresco: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_refresco_iniciar(%L, %L::uuid)', 'ztscrr.op@emdupar.gov.co', ca))) = '42501');
  perform pg_temp.ok('14.05 el rol scrr_refresco: sin login, sin superusuario, solo MAINTAIN sobre predios_comercial (no la lee ni lee la cartera)',
    (select not rolcanlogin and not rolsuper and not rolcreaterole and not rolinherit from pg_roles where rolname = 'scrr_refresco')
    and has_table_privilege('scrr_refresco', 'public.predios_comercial', 'MAINTAIN') and not has_table_privilege('scrr_refresco', 'public.predios_comercial', 'SELECT')
    and not has_table_privilege('scrr_refresco', 'public.cartera_suscripcion', 'SELECT'));

  -- ===== 15. Actividades fuera de las listas y ajuste inicial (David, 22-nov 20:45) =====
  r := pg_temp.iniciar('actividades', v_hoy - 2, pg_temp.sha('act3'), 3);
  ca := r ->> 'carga_id';
  perform pg_temp.lote(ca, 1, jsonb_build_array(
    jsonb_build_object('contrato', (B + 111)::text, 'actividad', 'Corte', 'drastico', 'NO', 'estado', '3', 'fecha', v_hoy::text),
    jsonb_build_object('contrato', (B + 150)::text, 'actividad', 'Suspensión', 'drastico', 'NO', 'estado', '3', 'fecha', v_hoy::text),
    jsonb_build_object('contrato', (B + 151)::text, 'actividad', 'Corte', 'drastico', 'SÍ', 'estado', '3', 'fecha', '2025-12-01')));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, ca));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, ca));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, ca));
  perform pg_temp.ok('15.01 la carga de actividades no exige lista: 3 actas, 1 de la lista de Corte y 2 fuera de las listas',
    pg_temp.err(r) = 'OK' and (r -> 'resultado' ->> 'actas_nuevas')::int = 3 and (r -> 'resultado' ->> 'actas_de_una_lista')::int = 1
    and (r -> 'resultado' ->> 'actas_fuera_de_las_listas')::int = 2, r::text);
  perform pg_temp.ok('15.02 el acta de B+111 queda enlazada a su corrida; las otras, sin corrida (marcadas fuera de las listas)',
    (select corrida_id = cp::uuid from scrr.actas where contrato = B + 111 and carga_id = ca::uuid)
    and (select count(*) from scrr.actas where contrato in (B + 150, B + 151) and carga_id = ca::uuid and corrida_id is null) = 2);
  perform pg_temp.ok('15.03 ajuste inicial: un corte drástico de 2025 fuera de las listas actualiza igual el estado del servicio; la suspensión de hoy también',
    (select estado from scrr.v_estado_servicio where contrato = B + 151) = 'cortado_drastico' and (select estado from scrr.v_estado_servicio where contrato = B + 150) = 'suspendido');

  -- ===== 16. Retorno automático =====
  -- en la cartera de suscripción: B+150 (suspendido) y B+151 (cortado drástico) quedaron a paz y salvo; B+111 (cortado hoy, de la lista) sigue con saldo y pagó 1.000 hoy
  insert into public.cartera_suscripcion (contrato, nombre, direccion, saldo_pendiente, ciclo, ruta, codigo_reparto) values
    ((B + 150)::text, 'ZTSCRR NOMBRE 150', 'ZTSCRR CALLE 150', 0, '98', 'ZTR1', 'P150'), ((B + 151)::text, 'ZTSCRR NOMBRE 151', 'ZTSCRR CALLE 151', 0, '98', 'ZTR0', 'P151'),
    ((B + 111)::text, 'ZTSCRR NOMBRE 111', 'ZTSCRR CALLE 111', 20000, '98', 'ZTR0', 'P111');
  r := pg_temp.rpc(format('public.geoportal_scrr_retorno_agregar(%L, %L, %L, %L)', S, (B + 113)::text, 'reconexion', 'ZTSCRR reclamo no registrado en el sistema'));
  perform pg_temp.ok('16.01 adición manual al retorno con motivo (decisión 12)', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.ok('16.02 la misma otra vez: 55000; una actividad que no es de retorno: 22023; el operario: 42501',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_retorno_agregar(%L, %L, %L, %L)', S, (B + 113)::text, 'reconexion', 'ZTSCRR reclamo no registrado en el sistema'))) = '55000'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_retorno_agregar(%L, %L, %L, %L)', S, (B + 114)::text, 'corte', 'ZTSCRR esto no es un retorno válido'))) = '22023'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_retorno_agregar(%L, %L, %L, %L)', 'ztscrr.op@emdupar.gov.co', (B + 114)::text, 'reconexion', 'ZTSCRR el operario no puede'))) = '42501');
  r := pg_temp.rpc(format('public.geoportal_scrr_retorno(%L)', S));
  perform pg_temp.ok('16.03 retorno: suspendido a paz y salvo → reinstalación; cortado drástico → reconexión drástica con su aviso; el manual con su origen y motivo',
    pg_temp.err(r) = 'OK' and (r ->> 'pendientes')::int = 3
    and (select x ->> 'actividad' = 'Reinstalación' and x ->> 'origen' = 'automatico' from jsonb_array_elements(r -> 'proponer') x where (x ->> 'contrato')::bigint = B + 150)
    and (select x ->> 'actividad' = 'Reconexión drástica' and x ->> 'aviso' like 'Reconexión DRÁSTICA%' from jsonb_array_elements(r -> 'proponer') x where (x ->> 'contrato')::bigint = B + 151)
    and (select x ->> 'actividad' = 'Reconexión' and x ->> 'origen' = 'manual' and x ->> 'motivo' like 'ZTSCRR reclamo%' from jsonb_array_elements(r -> 'proponer') x where (x ->> 'contrato')::bigint = B + 113), r::text);
  perform pg_temp.ok('16.04 «por confirmar»: B+111 pagó hoy pero la cartera aún muestra saldo; no se propone',
    exists (select 1 from jsonb_array_elements(r -> 'por_confirmar') x where (x ->> 'contrato')::bigint = B + 111 and (x ->> 'pagado_desde_cartera')::numeric = 1000)
    and not exists (select 1 from jsonb_array_elements(r -> 'proponer') x where (x ->> 'contrato')::bigint = B + 111), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_retorno_generar(%L)', S));
  c2 := r ->> 'corrida_id';
  perform pg_temp.ok('16.05 generar la lista de retorno: una corrida «retorno» con los 3, cada uno con su actividad y su origen',
    pg_temp.err(r) = 'OK' and (r ->> 'contratos')::int = 3 and (select tipo from scrr.corridas where id = c2::uuid) = 'retorno'
    and (select string_agg(k.actividad_id::text || k.origen, ',' order by k.orden) from scrr.corrida_contratos k where k.corrida_id = c2::uuid) = '4automatico,5manual,6automatico', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_retorno(%L)', S));
  perform pg_temp.ok('16.06 ya listados no vuelven a salir: pendientes 0 y generar otra vez da 55000',
    (r ->> 'pendientes')::int = 0 and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_retorno_generar(%L)', S))) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_lista(%L, %L::uuid, %L)', S, c2, 'excel'));
  perform pg_temp.ok('16.07 la lista de retorno lleva la actividad de cada fila y el aviso del drástico; nombre y dirección para la visita',
    (select x ->> 'actividad' = 'Reconexión drástica' and x ->> 'marca' like 'Reconexión DRÁSTICA%' and x ->> 'nombre' = 'ZTSCRR NOMBRE 151' from jsonb_array_elements(r -> 'filas') x where (x ->> 'contrato')::bigint = B + 151)
    and r ->> 'actividad' like 'Restablecer%', r::text);
  -- la reinstalación de B+150 se hace (archivo de actividades): sale del retorno y su acta queda enlazada a la lista de retorno
  r := pg_temp.iniciar('actividades', v_hoy - 3, pg_temp.sha('act4'), 1);
  ca := r ->> 'carga_id';
  perform pg_temp.lote(ca, 1, jsonb_build_array(jsonb_build_object('contrato', (B + 150)::text, 'actividad', 'Reinstalación', 'drastico', 'NO', 'estado', '3', 'fecha', v_hoy::text)));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, ca));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, ca));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, ca));
  perform pg_temp.ok('16.08 hecha la reinstalación: B+150 queda activo, sale del retorno y su acta se enlaza a la lista de retorno',
    (select estado from scrr.v_estado_servicio where contrato = B + 150) = 'activo'
    and not exists (select 1 from scrr.f_retorno() x where x.contrato = B + 150)
    and (select corrida_id = c2::uuid from scrr.actas where contrato = B + 150 and tipo_actividad_id = 4));
  r := pg_temp.rpc(format('public.geoportal_scrr_retorno_quitar(%L, %L, %L)', S, (B + 113)::text, 'ZTSCRR ya no corresponde'));
  perform pg_temp.ok('16.09 quitar el manual con motivo: deja de proponerse (queda el historial)',
    pg_temp.err(r) = 'OK' and not exists (select 1 from scrr.f_retorno() x where x.contrato = B + 113) and (select count(*) from scrr.retorno_manual_eventos where contrato = B + 113) = 2, r::text);

  -- ===== 17. Calendario: copiar del mes anterior (lote) y aviso del mes en curso =====
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar_lote(%L, %L, %L::jsonb)', S, to_char(v_hoy + interval '1 month', 'YYYYMM'),
         jsonb_build_array(jsonb_build_object('ciclo', 97, 'pago_oportuno', (v_hoy + interval '1 month')::date, 'fecha_suspension', (v_hoy + interval '1 month')::date + 1),
                           jsonb_build_object('ciclo', 98, 'pago_oportuno', (v_hoy + interval '1 month')::date, 'fecha_suspension', (v_hoy + interval '1 month')::date + 1))));
  perform pg_temp.ok('17.01 copiar del mes anterior: crea los ciclos que faltan en el mes siguiente', pg_temp.err(r) = 'OK' and (r ->> 'nuevos')::int = 2, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar_lote(%L, %L, %L::jsonb)', S, to_char(v_hoy + interval '1 month', 'YYYYMM'),
         jsonb_build_array(jsonb_build_object('ciclo', 97, 'pago_oportuno', (v_hoy + interval '1 month')::date, 'fecha_suspension', (v_hoy + interval '1 month')::date + 5))));
  perform pg_temp.ok('17.02 los que ya están no se tocan (cambiarlos exige motivo, uno por uno)', (r ->> 'nuevos')::int = 0 and (r ->> 'ya_estaban')::int = 1
    and (select fecha_suspension from scrr.v_calendario_vigente where periodo = to_char(v_hoy + interval '1 month', 'YYYYMM') and ciclo = 97) = (v_hoy + interval '1 month')::date + 1, r::text);
  perform pg_temp.ok('17.03 suspensión antes del pago oportuno en el lote: 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar_lote(%L, %L, %L::jsonb)', S, to_char(v_hoy + interval '1 month', 'YYYYMM'),
      jsonb_build_array(jsonb_build_object('ciclo', 96, 'pago_oportuno', (v_hoy + interval '1 month')::date, 'fecha_suspension', (v_hoy + interval '1 month')::date - 1))))) = '22023');
  r := pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', S));
  perform pg_temp.ok('17.04 el contexto dice cuántos ciclos tiene el mes en curso (para el aviso visible)',
    (r -> 'calendario_actual' ->> 'periodo') = to_char(v_hoy, 'YYYYMM')
    and (r -> 'calendario_actual' ->> 'ciclos')::int = (select count(*) from scrr.v_calendario_vigente where periodo = to_char(v_hoy, 'YYYYMM')), r::text);

  -- ===== 10. Estructura, permisos y reglas de producción =====
  perform pg_temp.ok('10.01 historial en particiones diarias (hoy existe) y pagos en mensuales',
    to_regclass('scrr.cartera_historial_' || to_char(v_hoy, 'YYYYMMDD')) is not null and to_regclass('scrr.pagos_contrato_' || to_char(v_hoy, 'YYYYMM')) is not null);
  perform pg_temp.ok('10.02 service_role ejecuta las RPC; anon y authenticated no',
    (select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute'))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_scrr\_%'));
  perform pg_temp.ok('10.03 nadie más que el dueño ejecuta funciones de scrr (incluida f_retirar_historial)',
    not exists (select 1 from pg_proc p where p.pronamespace = 'scrr'::regnamespace
                  and (has_function_privilege('service_role', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
  perform pg_temp.ok('10.04 ninguna tabla de scrr (ni sus particiones) se lee como anon, authenticated o service_role',
    not exists (select 1 from pg_class c where c.relnamespace = 'scrr'::regnamespace and c.relkind in ('r','p','v')
                  and (has_table_privilege('service_role', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select') or has_table_privilege('anon', c.oid, 'select'))));
  perform pg_temp.ok('10.05 ninguna función de scrr con DELETE o UPDATE sin WHERE', {{SIN_WHERE_SCRR}} = 0);
  perform pg_temp.ok('10.06 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
  perform pg_temp.ok('10.07 las 4 funciones de permisos no cambiaron', {{PERMISOS_SIN_CAMBIO}});
end $$;

-- Resultado: termina SIEMPRE en un ERROR (deshace todo). «N de N … SIN FALLAS» es el éxito.
do $$
declare v_tot int; v_ok int; v_fallas text;
begin
  select count(*), count(*) filter (where ok), string_agg(format('%s — %s', nombre, coalesce(detalle, '')), E'\n' order by n) filter (where not ok) into v_tot, v_ok, v_fallas from ztscrr_res;
  if v_ok = v_tot then
    raise exception 'RESULTADO: % de % pruebas correctas — SIN FALLAS (este ERROR es el esperado: deshace todo)', v_ok, v_tot;
  else
    raise exception 'RESULTADO: % de % pruebas correctas — FALLAS:%', v_ok, v_tot, E'\n' || v_fallas;
  end if;
end $$;
