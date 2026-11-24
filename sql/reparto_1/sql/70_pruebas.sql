-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 70 — PRUEBAS. Dentro del ensayo: todo se deshace con el ERROR esperado del final.
-- Datos propios con prefijo ZTREP (correos ztrep.*@emdupar.gov.co; contratos de 12 dígitos 88000000xxxx, que no existen; ciclos 97 y 98, que no existen:
-- el calendario de reparto solo admite ciclos de 1 a 99). Las fechas de reparto de prueba se escriben en scrr.calendario_ciclos y se deshacen al final.
-- Las rutas de prueba se escriben en hechos.rutas_consecutivos con el período MÁS RECIENTE (así las ve bi.v_rutas_geoportal) y se deshacen al final.
-- Cada prueba cuenta SOLO sus filas. Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- Sin tablas temporales que se borren al confirmar (regla de David, 21-nov).
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztrep_res (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztrep_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), left(p_detalle, 600)) $f$;
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
-- entregar con XY de Valledupar
create function pg_temp.ent(p_sol text, p_j bigint, p_c text, p_uuid uuid default gen_random_uuid(), p_prec numeric default 8, p_lon numeric default -73.25, p_lat numeric default 10.47) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_reparto_entregar(%L, %s, %L, %s, %s, %s, false, %L::uuid)', p_sol, p_j, p_c, coalesce(p_lon::text, 'null'), coalesce(p_lat::text, 'null'), coalesce(p_prec::text, 'null'), p_uuid)) $f$;
-- entregar desde el BUSCADOR (no mueve el punto de avance de los saltados)
create function pg_temp.entb(p_sol text, p_j bigint, p_c text) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_reparto_entregar(%L, %s, %L, -73.25, 10.47, 8, true, %L::uuid)', p_sol, p_j, p_c, gen_random_uuid())) $f$;
-- archivo de rutas: una fila con las columnas del archivo de facturación (sin la dirección, que no viaja) y la carga
create function pg_temp.fil(c text, ci text, ru text, cr text, cp text) returns jsonb language sql as $f$
  select jsonb_strip_nulls(jsonb_build_object('contrato', c, 'ciclo', ci, 'ruta', ru, 'consecutivo_ruta', cr, 'consecutivo_predio', cp)) $f$;
create function pg_temp.lote(p_sol text, p_nombre text, p_sha text, p_filas jsonb, p_confirmar boolean default true) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L::jsonb, %L::boolean)', p_sol, p_nombre, p_sha, p_filas, p_confirmar)) $f$;
create function pg_temp.pend(r jsonb) returns text language sql as $f$
  select coalesce(string_agg(x ->> 'c', ',' order by o), '') from jsonb_array_elements(r -> 'pendientes') with ordinality t(x, o) $f$;
create function pg_temp.salt(r jsonb) returns text language sql as $f$
  select coalesce(string_agg(x ->> 'c', ',' order by o), '') from jsonb_array_elements(r -> 'pendientes') with ordinality t(x, o) where (x ->> 's')::boolean $f$;

-- Personas de prueba
insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta, ver_registro_tecnico) values
  ('ztrep.adm@emdupar.gov.co', 'ZTREP Admin', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false, false),
  ('ztrep.sup@emdupar.gov.co', 'ZTREP Supervisor de reparto', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.supcal@emdupar.gov.co', 'ZTREP Supervisor de reparto y de campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false, false),
  ('ztrep.supcampo@emdupar.gov.co', 'ZTREP Supervisor de campo (SCRR)', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false, false),
  ('ztrep.supquitada@emdupar.gov.co', 'ZTREP Supervisión de reparto quitada', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.rep1@emdupar.gov.co', 'ZTREP Repartidor uno', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.rep2@emdupar.gov.co', 'ZTREP Repartidor dos', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.sinact@emdupar.gov.co', 'ZTREP Campo sin reparto', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.quitada@emdupar.gov.co', 'ZTREP Reparto quitado', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.inactivo@emdupar.gov.co', 'ZTREP Inactivo', 'consulta', false, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.tec@emdupar.gov.co', 'ZTREP Solo Técnica', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false, true);
insert into campo.personal_eventos (persona, tipo_evento, valor, motivo, autor) values
  ('ztrep.rep1@emdupar.gov.co', 'asignar_actividad', 'reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.rep2@emdupar.gov.co', 'asignar_actividad', 'reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.quitada@emdupar.gov.co', 'asignar_actividad', 'reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.quitada@emdupar.gov.co', 'quitar_actividad', 'reparto', 'ZTREP ya no reparte facturas', 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.inactivo@emdupar.gov.co', 'asignar_actividad', 'reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.sup@emdupar.gov.co', 'asignar_actividad', 'supervision_reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.supcal@emdupar.gov.co', 'asignar_actividad', 'supervision_reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.supquitada@emdupar.gov.co', 'asignar_actividad', 'supervision_reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.supquitada@emdupar.gov.co', 'quitar_actividad', 'supervision_reparto', 'ZTREP ya no supervisa el reparto', 'ztrep.adm@emdupar.gov.co');

-- Rutas de prueba en el período más reciente. Ruta 880101: 12 contratos; orden esperado por consecutivo_ruta y, en el empate, consecutivo_predio.
-- 880000000105 aparece DOS veces en el período (cuenta una vez, en su primer lugar). 880000000199 está solo en un período viejo (no debe salir).
-- Ruta 880102: 3 contratos. Ciclo 9999: no se ofrece.
insert into hechos.rutas_consecutivos (ciclo, consecutivo_ruta, ruta, contrato, direccion, consecutivo_predio, periodo, archivo_origen, fecha_carga)
select x.ciclo, x.cr, x.ruta, x.contrato, 'ZTREP CALLE', x.cp, coalesce(x.periodo, (select max(periodo) from hechos.rutas_consecutivos)), 'ZTREP.xlsx', '2026-11-23'
  from (values
    ('98', '5000000',  '880101', '880000000101', '10', null),
    ('98', '1000000',  '880101', '880000000102', '7',  null),
    ('98', '9000000',  '880101', '880000000103', '3',  null),
    ('98', '2000000',  '880101', '880000000104', '9',  null),   -- empate con 107: va DESPUÉS (predio 9 > 4)
    ('98', '2000000',  '880101', '880000000107', '4',  null),
    ('98', '3000000',  '880101', '880000000105', '1',  null),
    ('98', '8000000',  '880101', '880000000105', '1',  null),   -- repetido en el período
    ('98', '0',        '880101', '880000000106', '2',  null),   -- consecutivo 0: va primero
    ('98', '7000000',  '880101', '880000000108', '5',  null),
    ('98', '6000000',  '880101', '880000000109', '6',  null),
    ('98', '9500000',  '880101', '880000000110', '8',  null),
    ('98', '9600000',  '880101', '880000000111', '11', null),
    ('98', '9700000',  '880101', '880000000112', '12', null),
    ('98', '100',      '880101', '880000000199', '1',  '190001'),  -- período viejo
    ('98', '1000000',  '880102', '880000000201', '1',  null),
    ('98', '2000000',  '880102', '880000000202', '2',  null),
    ('98', '3000000',  '880102', '880000000203', '3',  null),
    ('9999', '1000000',  '889999', '880000000901', '1',  null),
    ('97',   '1000000',  '970101', '880000000501', '1',  null),   -- ciclo 97: sin fecha de reparto (respaldo)
    ('97',   '2000000',  '970101', '880000000502', '2',  null)
  ) x(ciclo, cr, ruta, contrato, cp, periodo);
-- un contrato que solo está en cartera_suscripcion (para «inventada»)
insert into public.cartera_suscripcion (contrato, estado, ciclo, periodo_carga) values ('880000000301', 'ACTIVO', '98', 'ZTREP'),
  ('880000000302', 'ACTIVO', '9999', 'ZTREP'),   -- sin ciclo de calendario: el mes del día
  ('880000000303', 'ACTIVO', '97', 'ZTREP'),     -- ciclo sin fecha de reparto: respaldo
  ('880000000201', 'ACTIVO', '97', 'ZTREP'),     -- en las rutas es del ciclo 98: al deducir el ciclo de un archivo manda la tabla de rutas
  ('880000000304', 'ACTIVO', '098', 'ZTREP');    -- solo en la cartera, con el ciclo escrito «098» (comparación numérica)
-- Calendario de reparto de prueba. Ciclo 98: el mes pasado (reparto hace 32 días), este mes (hace 2 días) y el próximo (en 3 días: aún no llega).
-- Ciclo 97: este mes, sin fecha de reparto (solo lectura).
insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, etapas, autor)
select to_char(date_trunc('month', h.h) + make_interval(months => x.k), 'YYYYMM'), x.c, h.h + 10, h.h + 15, x.e, 'ztrep.adm@emdupar.gov.co'
  from (select (now() at time zone 'America/Bogota')::date as h) h,
       lateral (values (-1, 98::smallint, jsonb_build_object('reparto', (h.h - 32)::text)),
                       ( 0, 98::smallint, jsonb_build_object('reparto', (h.h - 2)::text)),
                       ( 1, 98::smallint, jsonb_build_object('reparto', (h.h + 3)::text)),
                       ( 0, 97::smallint, jsonb_build_object('lectura', h.h::text))) x(k, c, e);
analyze hechos.rutas_consecutivos;

do $$
declare
  A text := 'ztrep.adm@emdupar.gov.co'; S text := 'ztrep.sup@emdupar.gov.co'; R1 text := 'ztrep.rep1@emdupar.gov.co'; R2 text := 'ztrep.rep2@emdupar.gov.co';
  r jsonb; fx jsonb; j1 bigint; j2 bigint; j3 bigint; ji bigint; jn bigint; u uuid := gen_random_uuid(); e1 bigint; e4 bigint; v_lote uuid; v_lote2 uuid; v_n bigint; v_aud bigint;
  t0 timestamptz; ms numeric; v_orden text; v_sha text := md5('ztrep-lote') || md5('ztrep-lote-b');
  v_hoy date := (now() at time zone 'America/Bogota')::date; v_mes text := to_char(v_hoy, 'YYYYMM');
  v_mes_ant text := to_char(date_trunc('month', v_hoy) - interval '1 month', 'YYYYMM'); j97 bigint; j97b bigint; r2b jsonb;
begin
  -- ===== 00. Quién entra =====
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R1));
  perform pg_temp.ok('00.01 el repartidor (campo + actividad reparto) entra: es repartidor y no supervisor',
    (r ->> 'es_repartidor')::boolean and not (r ->> 'es_supervisor')::boolean, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', S));
  perform pg_temp.ok('00.02 el supervisor de reparto (actividad supervision_reparto) entra: es supervisor y no repartidor; sin dashboard_campo no cambia el calendario',
    (r ->> 'es_supervisor')::boolean and not (r ->> 'es_repartidor')::boolean and not (r ->> 'puede_calendario')::boolean, r::text);
  perform pg_temp.ok('00.11 con dashboard_campo pero SIN supervision_reparto (supervisor del SCRR): 42501 en el contexto y en lo del supervisor',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.supcampo@emdupar.gov.co'))) = '42501'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', 'ztrep.supcampo@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.12 con supervision_reparto QUITADA: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', 'ztrep.supquitada@emdupar.gov.co'))) = '42501');
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.supcal@emdupar.gov.co'));
  perform pg_temp.ok('00.13 el supervisor de reparto que también tiene dashboard_campo ve el enlace «Cambiar en Calendario» (puede_calendario); el administrador también',
    (r ->> 'es_supervisor')::boolean and (r ->> 'puede_calendario')::boolean
    and (pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', A)) ->> 'puede_calendario')::boolean, r::text);
  perform pg_temp.ok('00.15 perfil liviano: repartidor, supervisor, administrador, campo sin actividades (falso y falso, sin error) y sin campo (42501)',
    pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', R1)) = '{"es_repartidor": true, "es_supervisor": false}'::jsonb
    and pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', S)) = '{"es_repartidor": false, "es_supervisor": true}'::jsonb
    and pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', A)) = '{"es_repartidor": true, "es_supervisor": true}'::jsonb
    and pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', 'ztrep.sinact@emdupar.gov.co')) = '{"es_repartidor": false, "es_supervisor": false}'::jsonb
    and pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', 'ztrep.supcampo@emdupar.gov.co')) = '{"es_repartidor": false, "es_supervisor": false}'::jsonb
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', 'ztrep.tec@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.14 la actividad «Supervisión de reparto» está en el catálogo de Personal, activa, y el supervisor sale en f_quien_puede',
    exists (select 1 from campo.actividades where codigo = 'supervision_reparto' and activa and nombre = 'Supervisión de reparto')
    and exists (select 1 from campo.f_quien_puede('supervision_reparto') q where q.persona = S)
    and not exists (select 1 from campo.f_quien_puede('supervision_reparto') q where q.persona = R1));
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', A));
  perform pg_temp.ok('00.03 el administrador es las dos cosas', (r ->> 'es_supervisor')::boolean and (r ->> 'es_repartidor')::boolean and (r ->> 'es_admin')::boolean, r::text);
  perform pg_temp.ok('00.04 con campo pero SIN la actividad reparto: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.sinact@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.05 con la actividad QUITADA: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.quitada@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.06 inactivo en la lista blanca (aunque tenga la actividad): 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.inactivo@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.07 solo Técnica: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.tec@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.08 sin solicitante: 28000', pg_temp.err(pg_temp.rpc('public.geoportal_reparto_contexto(null)')) = '28000');
  perform pg_temp.ok('00.09 el repartidor no carga archivos ni ve el avance (42501)',
    pg_temp.err(pg_temp.lote(R1, 'x.xlsx', v_sha, jsonb_build_array(pg_temp.fil('880000000101', '98', '880101', '1', null)))) = '42501'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', R1))) = '42501'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_mapa(%L)', R1))) = '42501'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_lotes(%L)', R1))) = '42501');
  perform pg_temp.ok('00.10 el supervisor que no reparte no empieza jornadas (42501)',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', S, 'anterior', '98', '880101'))) = '42501');

  -- ===== 01. Rutas del último período en el contexto =====
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R1));
  perform pg_temp.ok('01.01 el contexto trae el período más reciente', r ->> 'periodo' = (select max(periodo) from hechos.rutas_consecutivos), r ->> 'periodo');
  perform pg_temp.ok('01.02 ciclo 98 con sus rutas 880101 (12 contratos distintos) y 880102 (3)',
    (select x -> 'rutas' from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' = '98') = '[{"n": 12, "ruta": "880101"}, {"n": 3, "ruta": "880102"}]'::jsonb,
    (select (x -> 'rutas')::text from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' = '98'));
  perform pg_temp.ok('01.03 el ciclo 9999 no se ofrece (P4)', not exists (select 1 from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' = '9999'));
  perform pg_temp.ok('01.04 parámetros: respaldo 15 días, tope 10000 filas, precisión mala 30 m',
    r -> 'parametros' = '{"respaldo_dias": 15, "tope_filas_lote": 10000, "precision_mala_m": 30}'::jsonb, (r -> 'parametros')::text);
  perform pg_temp.ok('01.05 calendario: el ciclo 98 reparte el período de este mes (su fecha de reparto ya llegó; la del próximo mes no); el 97 no tiene fecha',
    (select x -> 'reparto' from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' = '98') = jsonb_build_object('periodo', v_mes, 'desde', v_hoy - 2)
    and (select x -> 'reparto' from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' = '97') = 'null'::jsonb,
    (select string_agg((x -> 'reparto')::text, ' ') from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' in ('97', '98')));

  -- ===== 02. Empezar con la ruta anterior =====
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '98', '880101'));
  j1 := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('02.01 empieza la jornada: 12 facturas, origen anterior, sin retomar', j1 is not null and (r -> 'jornada' ->> 'total')::int = 12
    and r -> 'jornada' ->> 'origen' = 'anterior' and not (r ->> 'retomada')::boolean and (r ->> 'siguiente')::int = 1, r::text);
  v_orden := (select string_agg(right(contrato, 3), ',' order by orden_lectura) from reparto.jornada_items where jornada_id = j1);
  perform pg_temp.ok('02.02 orden de lectura: consecutivo_ruta, el empate por consecutivo_predio y el repetido en su primer lugar',
    v_orden = '106,102,107,104,105,101,109,108,103,110,111,112', v_orden);
  perform pg_temp.ok('02.03 la lista trae solo los códigos (sin el número de orden), en ese orden y sin saltados',
    pg_temp.pend(r) = '880000000106,880000000102,880000000107,880000000104,880000000105,880000000101,880000000109,880000000108,880000000103,880000000110,880000000111,880000000112'
    and pg_temp.salt(r) = '' and not exists (select 1 from jsonb_array_elements(r -> 'pendientes') x where x ? 'o' or x ? 'orden_lectura'), pg_temp.pend(r));
  perform pg_temp.ok('02.09 la jornada reparte el período de este mes, sin respaldo ni aviso',
    r -> 'jornada' ->> 'periodo_reparto' = v_mes and (r -> 'jornada' ->> 'reparto_desde')::date = v_hoy - 2 and not (r -> 'jornada' ->> 'respaldo')::boolean
    and r -> 'jornada' -> 'aviso' = 'null'::jsonb, (r -> 'jornada')::text);
  perform pg_temp.ok('02.04 el contrato del período viejo no está', not exists (select 1 from reparto.jornada_items where jornada_id = j1 and contrato = '880000000199'));
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '98', '880101'));
  perform pg_temp.ok('02.05 volver a escoger la misma ruta el mismo día retoma la MISMA jornada', (r -> 'jornada' ->> 'id')::bigint = j1 and (r ->> 'retomada')::boolean
    and (select count(*) from reparto.jornadas where repartidor = R1) = 1);
  perform pg_temp.ok('02.06 ciclo 9999: no se reparte por ruta', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '9999', '889999'))) = '22023');
  perform pg_temp.ok('02.07 una ruta que no está en el último período: error claro',
    pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '98', '880199')) ->> 'msg' = 'Esa ruta no está en el último período cargado');
  perform pg_temp.ok('02.08 origen inválido o sin ciclo: 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L)', R1, 'otro'))) = '22023'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, null, %L)', R1, 'anterior', '880101'))) = '22023');

  -- ===== 03. Entregar en desorden, saltar, doble toque =====
  r := pg_temp.ent(R1, j1, '880000000106', u);
  e1 := (r ->> 'entrega_id')::bigint;
  perform pg_temp.ok('03.01 primera entrega: consecutivo 1, con su XY, su período de reparto y no repetida', (r ->> 'consecutivo')::int = 1 and not (r ->> 'repetida')::boolean
    and r ->> 'periodo_reparto' = v_mes and (select periodo_reparto from reparto.entregas where id = e1) = v_mes
    and exists (select 1 from reparto.entregas where id = e1 and lon = -73.25 and lat = 10.47 and precision_m = 8 and orden_lectura = 1 and autor = R1), r::text);
  r := pg_temp.ent(R1, j1, '880000000106', u);
  perform pg_temp.ok('03.02 el MISMO toque (mismo uuid) otra vez devuelve la misma entrega, sin error y sin otra fila',
    (r ->> 'entrega_id')::bigint = e1 and (r ->> 'repetida')::boolean and (select count(*) from reparto.entregas where jornada_id = j1) = 1, r::text);
  r := pg_temp.ent(R1, j1, '880000000106');
  perform pg_temp.ok('03.03 la misma factura con otro toque: no se registra dos veces (23505) y lo dice', pg_temp.err(r) = '23505' and r ->> 'msg' like '%ya se registró%(entrega 1)%', r::text);
  r := pg_temp.ent(R1, j1, '880000000104');            -- se salta 102 y 107
  e4 := (r ->> 'entrega_id')::bigint;
  perform pg_temp.ok('03.04 entrega en desorden: la del 4.º lugar queda como entrega 2', (r ->> 'consecutivo')::int = 2, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R1, j1));
  perform pg_temp.ok('03.05 los saltados (102 y 107) quedan ARRIBA, marcados, y las entregadas salen de la lista',
    pg_temp.salt(r) = '880000000102,880000000107' and pg_temp.pend(r) like '880000000102,880000000107,880000000105,%' and (r ->> 'entregadas_mias')::int = 2
    and (r ->> 'siguiente')::int = 3, pg_temp.pend(r) || ' | ' || pg_temp.salt(r));
  r := pg_temp.ent(R1, j1, '880000000102');
  perform pg_temp.ok('03.06 entregar un saltado: entrega 3; ya no está saltado', (r ->> 'consecutivo')::int = 3
    and pg_temp.salt(pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R1, j1))) = '880000000107', r::text);
  perform pg_temp.ok('03.07 un contrato que no es de esta ruta: error claro', pg_temp.ent(R1, j1, '880000000201') ->> 'msg' = 'El contrato 880000000201 no está en esta ruta');
  perform pg_temp.ok('03.08 sin GPS no se guarda (P8)', pg_temp.ent(R1, j1, '880000000105', gen_random_uuid(), null, null, null) ->> 'msg' like 'Sin ubicación del GPS%'
    and pg_temp.ent(R1, j1, '880000000105', gen_random_uuid(), 10, 2.35, 48.85) ->> 'msg' like 'La ubicación del GPS no es válida%');
  r := pg_temp.ent(R1, j1, '880000000105', gen_random_uuid(), 85);
  perform pg_temp.ok('03.09 GPS impreciso (85 m) se guarda y queda marcado (P8)', (r ->> 'consecutivo')::int = 4 and (r ->> 'precision_mala')::boolean, r::text);
  perform pg_temp.ok('03.10 contrato con letras: 22023', pg_temp.err(pg_temp.ent(R1, j1, '88A')) = '22023');
  perform pg_temp.ok('03.11 sin uuid del toque: 22023', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_entregar(%L, %s, %L, -73.25, 10.47, 5, false, null)', R1, j1, '880000000101'))) = '22023');
  -- segundo repartidor en la MISMA ruta
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R2, 'anterior', '98', '880101'));
  j2 := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('03.12 otro repartidor en la misma ruta: su propia jornada, y su lista ya descuenta lo entregado por el primero',
    j2 <> j1 and pg_temp.pend(r) = '880000000107,880000000101,880000000109,880000000108,880000000103,880000000110,880000000111,880000000112' and pg_temp.salt(r) = '', pg_temp.pend(r));
  r := pg_temp.ent(R2, j2, '880000000104');
  perform pg_temp.ok('03.13 la factura que ya entregó otro: no se registra y dice «por otro repartidor»', pg_temp.err(r) = '23505' and r ->> 'msg' like '%por otro repartidor', r::text);
  perform pg_temp.ok('03.14 entregar en la lista de otro: 42501', pg_temp.err(pg_temp.ent(R2, j1, '880000000107')) = '42501'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R2, j1))) = '42501');
  r := pg_temp.ent(R2, j2, '880000000112', u);
  perform pg_temp.ok('03.15 el uuid de otro toque (de otra persona) no sirve', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.ent(R2, j2, '880000000112');
  perform pg_temp.ok('03.16 el consecutivo es de cada jornada: la primera del segundo repartidor es la 1', (r ->> 'consecutivo')::int = 1, r::text);

  -- ===== 04. Anular con motivo (P7) =====
  r := pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', R1, e4, 'corto'));
  perform pg_temp.ok('04.01 anular sin motivo suficiente: 22023', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', R2, e4, 'ZTREP toqué la que no era'));
  perform pg_temp.ok('04.02 un repartidor no anula la entrega de otro (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', R1, e4, 'ZTREP toqué la que no era'));
  perform pg_temp.ok('04.03 el repartidor anula la suya de hoy con motivo; la fila de la entrega sigue ahí', (r ->> 'ok')::boolean
    and exists (select 1 from reparto.entregas where id = e4) and exists (select 1 from reparto.entregas_anuladas where entrega_id = e4 and autor = R1), r::text);
  perform pg_temp.ok('04.04 anularla otra vez: 55000', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', R1, e4, 'ZTREP otra vez lo mismo'))) = '55000');
  r := pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R1, j1));
  perform pg_temp.ok('04.05 la anulada vuelve a pendientes', pg_temp.pend(r) like '%880000000104%' and (r ->> 'entregadas_mias')::int = 3, pg_temp.pend(r));
  r := pg_temp.ent(R1, j1, '880000000104');
  perform pg_temp.ok('04.06 se entrega otra vez con un consecutivo NUEVO (5): no se renumera', (r ->> 'consecutivo')::int = 5
    and (select string_agg(consecutivo::text, ',' order by consecutivo) from reparto.entregas where jornada_id = j1) = '1,2,3,4,5', r::text);
  v_aud := (select count(*) from public.geoportal_auditoria where email = S and accion = 'reparto_anular_entrega');
  r := pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', S, (select id from reparto.entregas where jornada_id = j2 and consecutivo = 1), 'ZTREP la anula el supervisor'));
  perform pg_temp.ok('04.07 el supervisor anula la de cualquiera, y queda en la auditoría', (r ->> 'ok')::boolean
    and (select count(*) from public.geoportal_auditoria where email = S and accion = 'reparto_anular_entrega') = v_aud + 1, r::text);
  perform pg_temp.ok('04.08 entrega que no existe: 22023', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', S, -1, 'ZTREP no existe esta'))) = '22023');

  -- ===== 05. Sin ruta («inventada») =====
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L)', R1, 'inventada'));
  ji := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('05.01 repartir sin ruta: jornada sin lista', ji is not null and (r -> 'jornada' ->> 'total')::int = 0 and r -> 'pendientes' = '[]'::jsonb, r::text);
  r := pg_temp.ent(R1, ji, '880000000301');
  perform pg_temp.ok('05.02 un contrato que solo está en cartera_suscripcion: entrega 1 (su orden real es su ruta), con el período de reparto de SU ciclo (98)',
    (r ->> 'consecutivo')::int = 1 and r ->> 'periodo_reparto' = v_mes
    and (select orden_lectura from reparto.entregas where id = (r ->> 'entrega_id')::bigint) is null, r::text);
  r := pg_temp.ent(R1, ji, '880000000203');
  perform pg_temp.ok('05.03 un contrato que solo está en las rutas: entrega 2', (r ->> 'consecutivo')::int = 2, r::text);
  perform pg_temp.ok('05.04 un código que no existe en ningún lado: error claro', pg_temp.ent(R1, ji, '880000000999') ->> 'msg' = 'No hay ningún contrato con el código 880000000999');
  perform pg_temp.ok('05.05 sin ruta tampoco se registra dos veces la misma factura (ya entregada desde una ruta)', pg_temp.err(pg_temp.ent(R1, ji, '880000000106')) = '23505');

  -- ===== 06. Archivos de rutas («nueva»): la estructura del archivo de rutas de facturación; varias rutas y ciclos por archivo =====
  r := pg_temp.lote(S, 'ztrep_rutas.xlsx', v_sha, jsonb_build_array(
         pg_temp.fil('880000000203', '98', 'ZT-NUEVA', '30', '1'), pg_temp.fil('880000000201', '98', 'ZT-NUEVA', '10', '1'), pg_temp.fil('880000000202', '98', 'ZT-NUEVA', '20', '1'),
         pg_temp.fil('880000000401', '98', 'ZT-NUEVA', '40', '2'), pg_temp.fil('880000000402', '98', 'ZT-NUEVA', '40', '1'),
         pg_temp.fil('880000000110', '097', 'ZT-OTRA', '1000000', null)));   -- el 110 es del ciclo 98 en las rutas: el archivo dice 97 (manda el archivo, con aviso)
  v_lote := (r ->> 'lote_id')::uuid;
  perform pg_temp.ok('06.01 el supervisor carga un archivo de rutas: 6 filas, 2 rutas (98 ZT-NUEVA y 97 ZT-OTRA), 2 sin registro y 1 de otro ciclo (110: archivo 97, rutas 98)',
    (r ->> 'ok')::boolean and (r ->> 'filas')::int = 6 and not (r ->> 'repetido')::boolean
    and r -> 'rutas' = '[{"ruta": "ZT-OTRA", "ciclo": "97", "filas": 1}, {"ruta": "ZT-NUEVA", "ciclo": "98", "filas": 5}]'::jsonb
    and (r ->> 'sin_registro')::int = 2 and (r ->> 'otro_ciclo')::int = 1
    and r -> 'otro_ciclo_lista' = '[{"contrato": "880000000110", "ciclo_rutas": "98", "ciclo_archivo": "97"}]'::jsonb
    and (select rutas || '|' || sin_registro || '|' || otro_ciclo from reparto.lotes where id = v_lote) = '2|2|1', r::text);
  perform pg_temp.ok('06.02 el orden de cada ruta: CONSECUTIVO_EN_LA_RUTA y, en el empate, el de predio; cada fila con su ciclo y su ruta (manda el archivo); sin dirección',
    (select string_agg(right(contrato, 3) || ':' || orden, ',' order by orden) from reparto.lote_filas where lote_id = v_lote and ruta = 'ZT-NUEVA') = '201:1,202:2,203:3,402:4,401:5'
    and (select ciclo from reparto.lote_filas where lote_id = v_lote and contrato = '880000000110') = '97'
    and not exists (select 1 from information_schema.columns where table_schema = 'reparto' and table_name in ('lote_filas', 'lotes') and column_name ilike '%direcci%'));
  r := pg_temp.lote(S, 'ztrep_rutas.xlsx', v_sha, jsonb_build_array(pg_temp.fil('880000000203', '98', 'ZT-NUEVA', '30', '1')));
  perform pg_temp.ok('06.03 el mismo archivo otra vez el mismo día (doble clic): el mismo lote', (r ->> 'lote_id')::uuid = v_lote and (r ->> 'repetido')::boolean
    and (select count(*) from reparto.lotes where autor = S) = 1, r::text);
  v_n := (select count(*) from reparto.lotes);
  r := pg_temp.lote(S, 'malo.xlsx', md5('m') || md5('n'), jsonb_build_array(
         pg_temp.fil('88A', '98', 'R1', '1', null), pg_temp.fil('880000000201', 'C1', 'R1', '2', null), pg_temp.fil('880000000202', '98', '', '3', null),
         pg_temp.fil('880000000203', '98', 'R1', 'x', null), pg_temp.fil('880000000204', '98', 'R1', '5', 'y')));
  perform pg_temp.ok('06.04 un archivo con errores no escribe nada y dice cada error con su fila de Excel',
    not (r ->> 'ok')::boolean and (select count(*) from reparto.lotes) = v_n
    and r -> 'errores' = '["Fila 2: el contrato «88A» no es válido (solo números, de 1 a 12)", "Fila 3: el CICLO «C1» no es válido (número de hasta 4 cifras)", "Fila 4: la RUTA «» no es válida (hasta 20 letras o números)", "Fila 5: el CONSECUTIVO_EN_LA_RUTA «x» no es un número", "Fila 6: el NÚMERO_CONSECUTIVO_DE_PREDIO «y» no es un número"]'::jsonb,
    (r -> 'errores')::text);
  r := pg_temp.lote(S, 'repetidos.xlsx', md5('r') || md5('s'), jsonb_build_array(
         pg_temp.fil('880000000201', '98', 'R1', '1', null), pg_temp.fil('880000000202', '98', 'R1', '2', null), pg_temp.fil('880000000201', '98', 'R2', '3', null)));
  perform pg_temp.ok('06.05 contratos repetidos en el archivo: se rechaza con la lista, sin escribir nada',
    not (r ->> 'ok')::boolean and (select count(*) from reparto.lotes) = v_n
    and r -> 'errores' = '["El archivo trae contratos repetidos: cada contrato va una sola vez.", "El contrato 880000000201 está repetido (filas 2, 4)"]'::jsonb, (r -> 'errores')::text);
  insert into reparto.parametros (clave, valor, nota, autor) values ('tope_filas_lote', '2', 'ZTREP prueba del tope', A);
  perform pg_temp.ok('06.06 más filas que el tope: 22023 con el tope en el mensaje; sin nombre de archivo: 22023',
    pg_temp.lote(S, 'x.xlsx', v_sha, jsonb_build_array(pg_temp.fil('1', '98', 'R', '1', null), pg_temp.fil('2', '98', 'R', '2', null), pg_temp.fil('3', '98', 'R', '3', null))) ->> 'msg'
      = 'El archivo debe tener entre 1 y 2 filas (trae 3)'
    and pg_temp.err(pg_temp.lote(S, ' ', v_sha, jsonb_build_array(pg_temp.fil('1', '98', 'R', '1', null)))) = '22023');
  insert into reparto.parametros (clave, valor, nota, autor) values ('tope_filas_lote', '10000', 'ZTREP vuelve el tope', A);
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R2));
  perform pg_temp.ok('06.07 el repartidor ve CADA (ciclo, ruta) del archivo vigente como una ruta nueva',
    exists (select 1 from jsonb_array_elements(r -> 'nuevas') x where (x ->> 'id')::uuid = v_lote and x ->> 'ciclo' = '98' and x ->> 'ruta' = 'ZT-NUEVA' and (x ->> 'filas')::int = 5)
    and exists (select 1 from jsonb_array_elements(r -> 'nuevas') x where (x ->> 'id')::uuid = v_lote and x ->> 'ciclo' = '97' and x ->> 'ruta' = 'ZT-OTRA' and (x ->> 'filas')::int = 1), (r -> 'nuevas')::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L, %L::uuid)', R2, 'nueva', '98', 'ZT-NUEVA', v_lote));
  jn := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('06.08 empezar con una ruta del archivo: su orden y ya sin la 203 (entregada sin ruta por el otro repartidor)',
    (r -> 'jornada' ->> 'total')::int = 5 and r -> 'jornada' ->> 'nombre_archivo' = 'ztrep_rutas.xlsx' and r -> 'jornada' ->> 'ruta' = 'ZT-NUEVA'
    and pg_temp.pend(r) = '880000000201,880000000202,880000000402,880000000401', pg_temp.pend(r));
  perform pg_temp.ok('06.08b una ruta que no está en el archivo: error claro',
    pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L, %L::uuid)', R2, 'nueva', '98', 'ZT-OTRA', v_lote)) ->> 'msg' = 'Esa ruta no está en el archivo');
  r := pg_temp.ent(R2, jn, '880000000202');
  perform pg_temp.ok('06.09 entrega en el archivo; la 201 queda saltada', (r ->> 'consecutivo')::int = 1
    and pg_temp.salt(pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R2, jn))) = '880000000201', r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_anular(%L, %L::uuid, %L)', S, v_lote, 'ZTREP archivo equivocado'));
  perform pg_temp.ok('06.10 el supervisor anula el archivo con motivo', (r ->> 'ok')::boolean and exists (select 1 from reparto.lotes_anulados where lote_id = v_lote), r::text);
  perform pg_temp.ok('06.11 anulado: no se empieza, no se entrega en su jornada y ya no se ofrece',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L, %L::uuid)', R1, 'nueva', '97', 'ZT-OTRA', v_lote))) = '22023'
    and pg_temp.ent(R2, jn, '880000000401') ->> 'msg' = 'El supervisor anuló el archivo de esta ruta'
    and not exists (select 1 from jsonb_array_elements(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R2)) -> 'nuevas') x where (x ->> 'id')::uuid = v_lote));
  perform pg_temp.ok('06.12 anular el archivo dos veces: 55000', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_lote_anular(%L, %L::uuid, %L)', S, v_lote, 'ZTREP otra vez lo mismo'))) = '55000');
  insert into reparto.lotes (nombre_archivo, archivo_sha256, filas, rutas, autor, creado_en) values ('ztrep_viejo.xlsx', v_sha, 1, 1, S, now() - interval '50 days')
    returning id into v_lote2;
  insert into reparto.lote_filas (lote_id, ciclo, ruta, orden, contrato, consecutivo_ruta) values (v_lote2, '98', 'ZT-VIEJA', 1, '880000000111', 1);
  perform pg_temp.ok('06.13 un archivo vencido (más de 45 días) no se ofrece ni se empieza',
    pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L, %L::uuid)', R1, 'nueva', '98', 'ZT-VIEJA', v_lote2)) ->> 'msg' like 'Ese archivo de ruta ya venció%'
    and not exists (select 1 from jsonb_array_elements(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R1)) -> 'nuevas') x where (x ->> 'id')::uuid = v_lote2));
  r := pg_temp.rpc(format('public.geoportal_reparto_lotes(%L)', S));
  perform pg_temp.ok('06.14 la lista de archivos del supervisor: sus rutas, los avisos, anulado con su motivo y su jornada; el viejo, no vigente',
    exists (select 1 from jsonb_array_elements(r -> 'lotes') x where (x ->> 'id')::uuid = v_lote and (x ->> 'anulado')::boolean and x ->> 'motivo_anulacion' = 'ZTREP archivo equivocado'
              and (x ->> 'jornadas')::int = 1 and jsonb_array_length(x -> 'rutas') = 2 and (x ->> 'otro_ciclo')::int = 1)
    and exists (select 1 from jsonb_array_elements(r -> 'lotes') x where (x ->> 'id')::uuid = v_lote2 and not (x ->> 'vigente')::boolean), (r -> 'lotes')::text);
  perform pg_temp.ok('06.15 la auditoría tiene la carga y la anulación, sin las filas del archivo',
    exists (select 1 from public.geoportal_auditoria where accion = 'reparto_lote_cargar' and referencia = v_lote::text and detalle ->> 'filas' = '6' and detalle ->> 'rutas' = '2'
            and detalle::text not like '%880000000201%')
    and exists (select 1 from public.geoportal_auditoria where accion = 'reparto_lote_anular' and referencia = v_lote::text));

  -- ===== 07. Avance, detalle y mapa del supervisor =====
  r := pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', S));
  perform pg_temp.ok('07.01 avance de hoy, una fila por jornada (4: dos de la ruta 880101, la de sin ruta y la del archivo)',
    (select count(*) from jsonb_array_elements(r -> 'filas') x where x ->> 'repartidor' like 'ztrep.%') = 4, (r -> 'filas')::text);
  fx := (select x from jsonb_array_elements(r -> 'filas') x where (x ->> 'jornada_id')::bigint = j1);
  perform pg_temp.ok('07.02 la jornada 1: 12 facturas, 4 entregadas, 1 anulada, 8 pendientes, 1 saltada (107), con el nombre del repartidor',
    (fx ->> 'total')::int = 12 and (fx ->> 'entregadas')::int = 4 and (fx ->> 'anuladas')::int = 1 and (fx ->> 'pendientes')::int = 8 and (fx ->> 'saltadas')::int = 1
    and fx ->> 'nombre' = 'ZTREP Repartidor uno' and fx ->> 'ultima' is not null, fx::text);
  fx := (select x from jsonb_array_elements(r -> 'filas') x where (x ->> 'jornada_id')::bigint = ji);
  perform pg_temp.ok('07.03 la jornada sin ruta: 2 entregadas, sin pendientes ni saltadas', (fx ->> 'entregadas')::int = 2 and fx -> 'pendientes' = 'null'::jsonb and fx -> 'saltadas' = 'null'::jsonb, fx::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_detalle(%L, %s)', S, j1));
  perform pg_temp.ok('07.04 detalle: el orden real (1…5) con su orden de lectura, y la anulada con su motivo',
    (select string_agg((x ->> 'consecutivo') || ':' || coalesce(x ->> 'orden_lectura', '-') || case when (x ->> 'anulada')::boolean then '(A)' else '' end, ',' order by (x ->> 'consecutivo')::int)
       from jsonb_array_elements(r -> 'entregas') x) = '1:1,2:4(A),3:2,4:5,5:4'
    and (select x ->> 'motivo_anulacion' from jsonb_array_elements(r -> 'entregas') x where (x ->> 'consecutivo')::int = 2) = 'ZTREP toqué la que no era', (r -> 'entregas')::text);
  perform pg_temp.ok('07.05 detalle: los saltados (107) y las pendientes (8)',
    (select string_agg(x ->> 'contrato', ',' order by (x ->> 'orden_lectura')::int) from jsonb_array_elements(r -> 'saltados') x) = '880000000107' and (r ->> 'pendientes')::int = 8, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_mapa(%L)', S));
  perform pg_temp.ok('07.06 mapa de hoy: todos los XY de prueba (9), con las 2 anuladas marcadas',
    (select count(*) from jsonb_array_elements(r -> 'puntos') x where x ->> 'repartidor' like 'ztrep.%') = 9
    and (select count(*) from jsonb_array_elements(r -> 'puntos') x where x ->> 'repartidor' like 'ztrep.%' and (x ->> 'anulada')::boolean) = 2, (r -> 'puntos')::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_mapa(%L, null, %s)', S, j1));
  perform pg_temp.ok('07.07 mapa de una jornada: sus 5 puntos en el orden real', jsonb_array_length(r -> 'puntos') = 5
    and (select string_agg(x ->> 'consecutivo', ',' order by o) from jsonb_array_elements(r -> 'puntos') with ordinality t(x, o)) = '1,2,3,4,5', r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_mapa(%L, null, %s, %s)', S, j1, (select max(id) from reparto.entregas where jornada_id = j1 and consecutivo = 3)));
  perform pg_temp.ok('07.11 mapa en vivo: con el último id que ya tiene, solo vienen los puntos nuevos (4 y 5), la lista de anuladas y el último id',
    (select string_agg(x ->> 'consecutivo', ',' order by o) from jsonb_array_elements(r -> 'puntos') with ordinality t(x, o)) = '4,5'
    and r -> 'anuladas' = jsonb_build_array(e4) and (r ->> 'ultimo_id')::bigint = (select max(id) from reparto.entregas where jornada_id = j1), r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_mapa(%L, null, %s, %s)', S, j1, (select max(id) from reparto.entregas where jornada_id = j1)));
  perform pg_temp.ok('07.12 mapa en vivo sin nada nuevo: cero puntos (respuesta pequeña)', r -> 'puntos' = '[]'::jsonb and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_mapa(%L, null, null, -1)', S))) = '22023', r::text);
  perform pg_temp.ok('07.08 fecha futura: 22023', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_avance(%L, %L::date)', S, reparto.f_hoy() + 1))) = '22023');
  perform pg_temp.ok('07.09 el administrador también ve el avance', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', A))) = 'OK');
  perform pg_temp.ok('07.10 nada de lo que ve el repartidor ni el supervisor trae nombre, dirección ni teléfono del suscriptor',
    (pg_temp.rpc(format('public.geoportal_reparto_detalle(%L, %s)', S, j1))::text || pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R1, j1))::text
     || pg_temp.rpc(format('public.geoportal_reparto_mapa(%L)', S))::text) !~* '(direcci|telefono|teléfono|ZTREP CALLE|nombre_suscriptor)');

  -- ===== 08. Otro día =====
  insert into reparto.jornadas (fecha, repartidor, origen, fuente, total) values (reparto.f_hoy() - 1, R1, 'inventada', 'inventada', 0) returning id into j3;
  perform pg_temp.ok('08.01 en la lista de ayer no se entrega hoy (55000)', pg_temp.ent(R1, j3, '880000000110') ->> 'msg' = 'Esta lista es de otro día: vuelva a escoger la ruta');
  insert into reparto.entregas (jornada_id, contrato, consecutivo, lon, lat, precision_m, id_cliente, autor, registrado_en)
    values (j3, '880000000111', 101, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '1 day') returning id into e1;
  perform pg_temp.ok('08.02 el repartidor no anula una suya de ayer; el supervisor sí',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', R1, e1, 'ZTREP anular la de ayer'))) = '42501'
    and (pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', S, e1, 'ZTREP anular la de ayer')) ->> 'ok')::boolean);
  insert into reparto.entregas (jornada_id, contrato, consecutivo, lon, lat, precision_m, id_cliente, autor, registrado_en)
    values (j3, '880000000110', 102, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '10 days');
  perform pg_temp.ok('08.03 una entrega de respaldo (sin período) de ANTES de la fecha de reparto no cuenta para este período: se entrega',
    pg_temp.err(pg_temp.ent(R1, j1, '880000000110')) = 'OK');
  insert into reparto.entregas (jornada_id, contrato, consecutivo, periodo_reparto, lon, lat, precision_m, id_cliente, autor, registrado_en)
    values (j3, '880000000109', 103, v_mes_ant, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '1 hour'),
           (j3, '880000000108', 104, null, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '1 day');
  perform pg_temp.ok('08.04 una entrega del período ANTERIOR (aunque sea de hoy) no cuenta: se entrega', pg_temp.err(pg_temp.ent(R1, j1, '880000000109')) = 'OK');
  perform pg_temp.ok('08.05 una entrega de respaldo (sin período) DESPUÉS de la fecha de reparto sí cuenta: no se registra otra vez',
    pg_temp.err(pg_temp.ent(R1, j1, '880000000108')) = '23505');

  -- ===== 09. Solo inserción =====
  begin
    update reparto.entregas set lat = 0 where id = e4;
    perform pg_temp.ok('09.01 UPDATE directo rechazado por el disparador', false);
  exception when sqlstate '55000' then perform pg_temp.ok('09.01 UPDATE directo rechazado por el disparador', true);
  end;
  begin
    delete from reparto.entregas_anuladas where entrega_id = e4;
    perform pg_temp.ok('09.02 DELETE de una anulación rechazado', false);
  exception when sqlstate '55000' then perform pg_temp.ok('09.02 DELETE de una anulación rechazado', true);
  end;
  begin
    truncate reparto.jornada_items;
    perform pg_temp.ok('09.03 TRUNCATE rechazado', false);
  exception when sqlstate '55000' then perform pg_temp.ok('09.03 TRUNCATE rechazado', true);
  end;

  -- ===== 10. Seguridad y lo que no se toca =====
  perform pg_temp.ok('10.01 service_role ejecuta las 13 RPC; anon y authenticated no',
    (select count(*) = 13 and bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute'))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%'));
  perform pg_temp.ok('10.02 nadie más que el dueño ejecuta funciones de reparto',
    not exists (select 1 from pg_proc p where p.pronamespace = 'reparto'::regnamespace
                  and (has_function_privilege('service_role', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
  perform pg_temp.ok('10.03 ninguna tabla ni vista de reparto se lee como anon, authenticated o service_role',
    not exists (select 1 from pg_class c where c.relnamespace = 'reparto'::regnamespace and c.relkind in ('r','p','v')
                  and (has_table_privilege('service_role', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select') or has_table_privilege('anon', c.oid, 'select'))));
  perform pg_temp.ok('10.04 ninguna función de reparto con DELETE o UPDATE sin WHERE', {{SIN_WHERE_REPARTO}} = 0);
  perform pg_temp.ok('10.05 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
  perform pg_temp.ok('10.06 las 4 funciones de permisos no cambiaron', {{PERMISOS_SIN_CAMBIO}});
  perform pg_temp.ok('10.07 la huella de campo es la misma que antes de la migración (el reparto no toca campo)', {{CAMPO_SIN_CAMBIO}});
  perform pg_temp.ok('10.09 el Dell (homelab_lectura): USAGE sobre reparto y SELECT sobre las 8 tablas, nada más', {{HOMELAB}});
  perform pg_temp.ok('10.10 el reparto no escribe en el calendario: solo las filas de prueba',
    (select count(*) from scrr.calendario_ciclos where autor like 'ztrep.%') = 4 and not exists (select 1 from scrr.calendario_ciclos where autor like 'ztrep.%' and ciclo not in (97, 98)));
  perform pg_temp.ok('10.08 ninguna función de reparto ni RPC sin search_path fijo',
    not exists (select 1 from pg_proc p where (p.pronamespace = 'reparto'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%'))
                  and p.prokind = 'f' and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')));

  -- ===== 11. Tiempos con el volumen real (en producción: ~114 mil contratos por período, 6 períodos) =====
  t0 := clock_timestamp();
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R1));
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('11.01 contexto (rutas del período agrupadas) en menos de 5 s: ' || ms || ' ms', pg_temp.err(r) = 'OK' and ms < 5000, ms::text);
  t0 := clock_timestamp();
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '98', '880102'));
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('11.02 empezar una ruta del período en menos de 5 s: ' || ms || ' ms', pg_temp.err(r) = 'OK' and ms < 5000, ms::text);
  t0 := clock_timestamp();
  r := pg_temp.ent(R1, (r -> 'jornada' ->> 'id')::bigint, '880000000201');
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('11.03 una entrega en menos de 1 s: ' || ms || ' ms', pg_temp.err(r) in ('OK', '23505') and ms < 1000, ms::text || ' ' || r::text);
  t0 := clock_timestamp();
  r := pg_temp.ent(R1, ji, '880000000999');
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('11.04 sin ruta, un código que no está en cartera (recorre el período) en menos de 3 s: ' || ms || ' ms', ms < 3000, ms::text);
  t0 := clock_timestamp();
  r := pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', S));
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('11.05 avance del día en menos de 3 s: ' || ms || ' ms', pg_temp.err(r) = 'OK' and ms < 3000, ms::text);

  -- ===== 12. Calendario de reparto: falta la fecha (respaldo de 15 días), sin ruta y cambio del calendario en el día =====
  insert into reparto.entregas (jornada_id, contrato, consecutivo, lon, lat, precision_m, id_cliente, autor, registrado_en)
    values (j3, '880000000501', 105, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '20 days'),
           (j3, '880000000502', 106, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '10 days');
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '97', '970101'));
  j97 := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('12.01 ciclo sin fecha de reparto: la jornada va en respaldo y trae el aviso para la pantalla',
    (r -> 'jornada' ->> 'respaldo')::boolean and r -> 'jornada' -> 'periodo_reparto' = 'null'::jsonb
    and r -> 'jornada' ->> 'aviso' = 'Al ciclo 97 le falta la fecha de reparto en el calendario: se toman como entregadas las facturas de los últimos 15 días.', (r -> 'jornada')::text);
  perform pg_temp.ok('12.02 respaldo de 15 días: la de hace 20 días queda pendiente; la de hace 10, entregada', pg_temp.pend(r) = '880000000501', pg_temp.pend(r));
  r := pg_temp.ent(R1, j97, '880000000501');
  perform pg_temp.ok('12.03 se entrega en respaldo: sin período, con el aviso', (r ->> 'respaldo')::boolean and r -> 'periodo_reparto' = 'null'::jsonb and r ->> 'aviso' like 'Al ciclo 97 le falta%', r::text);
  r := pg_temp.ent(R1, ji, '880000000302');
  perform pg_temp.ok('12.04 sin ruta, un contrato sin ciclo de calendario (9999): el período es el mes del día', r ->> 'periodo_reparto' = v_mes and not (r ->> 'respaldo')::boolean, r::text);
  r := pg_temp.ent(R1, ji, '880000000303');
  perform pg_temp.ok('12.05 sin ruta, un contrato cuyo ciclo no tiene fecha de reparto: respaldo con aviso', (r ->> 'respaldo')::boolean and r ->> 'aviso' like 'Al ciclo 97 le falta%', r::text);
  insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, etapas, motivo, autor)
    values (v_mes, 97, v_hoy + 10, v_hoy + 15, jsonb_build_object('lectura', v_hoy::text, 'reparto', v_hoy::text), 'ZTREP llega la fecha de reparto', A);
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '97', '970101'));
  j97b := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('12.06 el supervisor llena la fecha de reparto en el día: al volver a abrir la ruta es otra jornada, ya con el período y sin aviso',
    j97b <> j97 and r -> 'jornada' ->> 'periodo_reparto' = v_mes and not (r -> 'jornada' ->> 'respaldo')::boolean and r -> 'jornada' -> 'aviso' = 'null'::jsonb, (r -> 'jornada')::text);
  perform pg_temp.ok('12.07 con la fecha nueva (hoy): la entrega de respaldo de hoy cuenta; la de hace 10 días ya no', pg_temp.pend(r) = '880000000502', pg_temp.pend(r));
  r := pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', S));
  r := pg_temp.rpc(format('public.geoportal_reparto_calendario(%L)', S));
  perform pg_temp.ok('12.09 calendario en solo lectura: el ciclo 98 con su fecha de reparto de este mes; el 97 con la que se llenó hoy; sin enlace para quien no tiene dashboard_campo',
    (select x ->> 'reparto' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 98) = (v_hoy - 2)::text
    and (select x ->> 'reparto' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 97) = v_hoy::text
    and (select x -> 'en_reparto_hoy' ->> 'periodo' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 98) = v_mes
    and not (r ->> 'puede_cambiar')::boolean and (pg_temp.rpc(format('public.geoportal_reparto_calendario(%L)', 'ztrep.supcal@emdupar.gov.co')) ->> 'puede_cambiar')::boolean, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_calendario(%L, %L)', S, to_char(date_trunc('month', v_hoy) + interval '1 month', 'YYYYMM')));
  perform pg_temp.ok('12.10 el calendario del mes siguiente: la fecha que aún no llega, y el período que se reparte hoy sigue siendo este mes',
    (select x ->> 'reparto' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 98) = (v_hoy + 3)::text
    and (select x -> 'en_reparto_hoy' ->> 'periodo' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 98) = v_mes, r::text);
  perform pg_temp.ok('12.11 el repartidor no ve el calendario (42501); un período mal escrito: 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_calendario(%L)', R1))) = '42501' and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_calendario(%L, %L)', S, '2026-11'))) = '22023');
  r := pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', S));
  perform pg_temp.ok('12.08 el avance del supervisor muestra el período de reparto y el respaldo de cada jornada',
    (select y ->> 'respaldo' from jsonb_array_elements(r -> 'filas') y where (y ->> 'jornada_id')::bigint = j97) = 'true'
    and (select y ->> 'periodo_reparto' from jsonb_array_elements(r -> 'filas') y where (y ->> 'jornada_id')::bigint = j1) = v_mes, (r -> 'filas')::text);

  -- ===== 13. Lo entregado con el buscador NO mueve el punto de avance (David, 24-nov) =====
  -- pendientes de la ruta en este punto: 107 (3.º), 101 (6.º), 103 (9.º), 111 (11.º) y 112 (12.º)
  r := pg_temp.ent(R2, j2, '880000000107');            -- tocando la lista: el 3.º; lo anterior ya está entregado
  v_orden := pg_temp.salt(pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R2, j2)));
  perform pg_temp.ok('13.01 tocando la lista el 3.º (lo anterior ya está entregado): ningún saltado', (r ->> 'consecutivo') is not null and v_orden = '', v_orden || ' ' || r::text);
  r := pg_temp.entb(R2, j2, '880000000111');           -- con el buscador: el 11.º
  r2b := pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R2, j2));
  perform pg_temp.ok('13.02 una entrega con el buscador (el 11.º) NO marca como saltados al 101 (6.º) ni al 103 (9.º): el punto de avance sigue en el 3.º',
    (r ->> 'consecutivo') is not null and pg_temp.salt(r2b) = '' and pg_temp.pend(r2b) = '880000000101,880000000103,880000000112'
    and (select por_buscador from reparto.entregas where id = (r ->> 'entrega_id')::bigint), pg_temp.pend(r2b) || ' | ' || pg_temp.salt(r2b));
  r := pg_temp.ent(R2, j2, '880000000103');            -- tocando la lista el 9.º: ahora sí, el 101 queda saltado
  perform pg_temp.ok('13.03 al tocar en la lista el 9.º, el 101 (6.º) pasa a «Saltado»', pg_temp.salt(pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R2, j2))) = '880000000101');
  r := pg_temp.rpc(format('public.geoportal_reparto_detalle(%L, %s)', S, j2));
  perform pg_temp.ok('13.04 el supervisor ve el orden real completo, con la del buscador (3, 11, 9), y los saltados con la misma regla',
    (select string_agg(x ->> 'orden_lectura', ',' order by (x ->> 'consecutivo')::int) from jsonb_array_elements(r -> 'entregas') x) like '%3,11,9'
    and (select string_agg(x ->> 'contrato', ',' order by (x ->> 'orden_lectura')::int) from jsonb_array_elements(r -> 'saltados') x) = '880000000101', r::text);

  -- ===== 14. Archivo de rutas: vista previa, ciclo numérico y tiempo =====
  v_n := (select count(*) from reparto.lotes);
  r := pg_temp.lote(S, 'previa.xlsx', md5('p1') || md5('p2'), jsonb_build_array(pg_temp.fil('880000000201', '98', '880101', '1', '1'), pg_temp.fil('880000000202', '98', '880102', '1', '1')), false);
  perform pg_temp.ok('14.01 vista previa (confirmar = false): devuelve las rutas y los avisos y NO escribe nada',
    (r ->> 'ok')::boolean and (r ->> 'previa')::boolean and jsonb_array_length(r -> 'rutas') = 2 and (select count(*) from reparto.lotes) = v_n, r::text);
  r := pg_temp.lote(S, 'ceros.xlsx', md5('c1') || md5('c2'), jsonb_build_array(pg_temp.fil('880000000202', '098', 'ZT-CEROS', '1.0', null)));
  perform pg_temp.ok('14.02 el CICLO se guarda como número («098» → 98, «1.0» → 1) y coincide con las rutas (sin aviso)',
    (r ->> 'ok')::boolean and (r ->> 'otro_ciclo')::int = 0 and (select ciclo || '|' || consecutivo_ruta from reparto.lote_filas where lote_id = (r ->> 'lote_id')::uuid) = '98|1', r::text);
  t0 := clock_timestamp();
  r := pg_temp.lote(S, 'grande.xlsx', md5('g1') || md5('g2'),
         (select jsonb_agg(pg_temp.fil((880000100000 + g)::text, (1 + g % 24)::text, 'ZT-G' || (g % 30), g::text, null)) from generate_series(1, 9000) g), false);
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('14.07 revisar un archivo de 9.000 contratos y 120 rutas (cruza el período de rutas y la cartera) en menos de 5 s: ' || ms || ' ms',
    (r ->> 'ok')::boolean and jsonb_array_length(r -> 'rutas') = 120 and (r ->> 'sin_registro')::int = 9000 and ms < 5000, ms::text || ' ' || left(r::text, 200));
end $$;

-- Resultado: termina SIEMPRE en un ERROR (deshace todo). «N de N … SIN FALLAS» es el éxito.
do $$
declare v_tot int; v_ok int; v_fallas text; v_tiempos text;
begin
  select count(*), count(*) filter (where ok), string_agg(format('%s — %s', nombre, coalesce(detalle, '')), E'\n' order by n) filter (where not ok),
         string_agg(nombre, E'\n' order by n) filter (where nombre like '11.%' or nombre like '14.07%')
    into v_tot, v_ok, v_fallas, v_tiempos from ztrep_res;
  if v_ok = v_tot then
    raise exception 'RESULTADO: % de % pruebas correctas — SIN FALLAS (este ERROR es el esperado: deshace todo)%', v_ok, v_tot, E'\nTiempos:\n' || coalesce(v_tiempos, '');
  else
    raise exception 'RESULTADO: % de % pruebas correctas — FALLAS:%', v_ok, v_tot, E'\n' || v_fallas;
  end if;
end $$;
