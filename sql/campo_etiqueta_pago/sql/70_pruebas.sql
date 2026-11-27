-- =====================================================================
-- ETIQUETA DEL ÚLTIMO PAGO (Code A, 27-nov) · 70 — ENSAYO: datos de prueba y respuestas de ANTES → MIGRACIÓN → pruebas → REVERSA → pruebas; termina en el
-- ERROR esperado (todo se deshace). Datos propios con prefijo ZTPAG (correos ztpag.*@emdupar.gov.co; contratos de 12 dígitos 9918000001NN, que se comprueba
-- que no existen). Las filas de prueba de cartera_suscripcion y bi_interno.ficha_contrato también se deshacen. Las RPC corren como service_role con los topes
-- de producción. Cinco perfiles: administrador, supervisor de Comercial, operador de campo (sin Análisis), dual (campo y Análisis) y sin permisos.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztpag_res (n serial, nombre text, ok boolean, detalle text);
create temp table ztpag_val (k text primary key, v text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztpag_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
create function pg_temp.guardar(p_k text, p_v text) returns void language sql as $f$ insert into ztpag_val values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.val(p_k text) returns text language sql as $f$ select v from ztpag_val where k = p_k $f$;
-- llama una RPC como service_role; devuelve su jsonb o {"error": sqlstate, "msg": mensaje}
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
create function pg_temp.consultar(p_quien text, p_contrato text) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_analisis_contrato(%L, %L, null)', p_quien, p_contrato)) $f$;
-- huella de campo SIN la función que cambia (para comprobar que no cambió nada más)
create function pg_temp.huella_resto() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text collate "C", p.proname, p.oid::regprocedure::text collate "C")) from pg_proc p
   where (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))
     and p.oid <> to_regprocedure('{{FUNCION}}') $f$;
-- lo que cada perfil recibe por cada contrato de prueba (respuesta completa) → ztpag_val 'r:<perfil>:<contrato>'
create function pg_temp.foto(p_pref text) returns void language plpgsql as $f$
declare u text; c text;
begin
  foreach u in array array['admin', 'sup', 'op', 'dual', 'sin'] loop
    foreach c in array array['991800000101', '991800000102', '991800000103', '991800000199'] loop
      perform pg_temp.guardar(p_pref || ':' || u || ':' || c, pg_temp.consultar('ztpag.' || u || '@emdupar.gov.co', c)::text);
    end loop;
  end loop;
end $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico, ver_analisis_contrato) values
  ('ztpag.admin@emdupar.gov.co', 'ZTPAG Administrador', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('ztpag.sup@emdupar.gov.co', 'ZTPAG Supervisor', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('ztpag.op@emdupar.gov.co', 'ZTPAG Operario sin Análisis', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztpag.dual@emdupar.gov.co', 'ZTPAG Dual campo y Análisis', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, true),
  ('ztpag.sin@emdupar.gov.co', 'ZTPAG Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false);

-- ===================== 00. Datos de prueba y lo de ANTES de la migración =====================
do $p0$
declare r jsonb; v_meses jsonb;
begin
  perform pg_temp.ok('00.01 los contratos de prueba no existen (cartera, censo, ficha)',
    not exists (select 1 from public.cartera_suscripcion where contrato like '9918000001__') and not exists (select 1 from public.catastro_valledupar where cod_usuario like '9918000001__')
    and not exists (select 1 from bi_interno.ficha_contrato where contrato like '9918000001__'));
  -- la ficha a la que se le escribe tiene las restricciones de producción (las 4 que crea el paquete de Análisis de contrato) y ningún disparador
  perform pg_temp.ok('00.02 bi_interno.ficha_contrato: llave, 3 CHECK y sin disparadores',
    (select string_agg(conname, ',' order by conname) from pg_constraint where conrelid = 'bi_interno.ficha_contrato'::regclass)
      = 'ficha_contrato_consumo_meses_check,ficha_contrato_medidor_fecha_estado_check,ficha_contrato_periodo_ultimo_check,ficha_contrato_pkey'
    and not exists (select 1 from pg_trigger where tgrelid = 'bi_interno.ficha_contrato'::regclass and not tgisinternal));
  select jsonb_agg(jsonb_build_object('periodo', p, 'sin_dato', false, 'm3', 10 + k, 'metodo', 'lectura', 'lectura_real', true, 'causal', '99 LECTURA NORMAL') order by k) into v_meses
    from unnest(array['202604', '202605', '202606', '202607', '202608', '202609']) with ordinality u(p, k);
  -- 101: pago por cupones (corte 202610) · 102: pago de la cartera mensual (corte 202609) · 103: sin pago · 199: no existe
  insert into public.cartera_suscripcion (contrato, estado, nombre, telefono, direccion, barrio, deuda_total, periodo_carga) values
    ('991800000101', 'ACTIVO', 'ZTPAG PERSONA UNO', '3001112233', 'CRA 9 # 12-30', 'CENTRO', 45000, '20261123'),
    ('991800000102', 'ACTIVO', 'ZTPAG PERSONA DOS', '3002223344', 'CLL 5 # 3-10', 'LOS MAYALES', 0, '20261123'),
    ('991800000103', 'ACTIVO', 'ZTPAG PERSONA TRES', null, 'MZ 4 CASA 7', 'PRIMERO DE MAYO', 0, '20261123');
  insert into bi_interno.ficha_contrato (contrato, periodo_ultimo, uso, estrato, consumo_meses, meses_con_lectura, medidor_fecha_estado, ultimo_pago) values
    ('991800000101', '202609', 'Residencial', 'Estrato 2', v_meses, 6, 'sin_dato', jsonb_build_object('fecha', date '2026-10-20', 'valor', 45000, 'fuente', 'cupones', 'corte', '202610')),
    ('991800000102', '202609', 'Residencial', 'Estrato 2', v_meses, 6, 'sin_dato', jsonb_build_object('fecha', date '2026-09-03', 'valor', 30000.5, 'fuente', 'cartera', 'corte', '202609')),
    ('991800000103', '202609', 'Residencial', 'Estrato 2', v_meses, 6, 'sin_dato', null);
  perform pg_temp.guardar('huella_resto', pg_temp.huella_resto());
  perform pg_temp.foto('antes');
  r := pg_temp.val('antes:dual:991800000101')::jsonb;
  perform pg_temp.ok('00.03 antes: el pago (cupones) llega sin «corte»', pg_temp.err(r) = 'OK' and r -> 'pago' ->> 'fuente' = 'cupones' and not (r -> 'pago' ? 'corte'), left(r::text, 300));
  r := pg_temp.val('antes:dual:991800000102')::jsonb;
  perform pg_temp.ok('00.04 antes: el pago (cartera) llega sin «corte»; sin pago llega null',
    r -> 'pago' ->> 'fuente' = 'cartera' and not (r -> 'pago' ? 'corte') and jsonb_typeof(pg_temp.val('antes:dual:991800000103')::jsonb -> 'pago') = 'null', left(r::text, 300));
end $p0$;

-- ===================== MIGRACIÓN (guardia incluida) =====================
{{CUERPO_MIGRACION}}

-- ===================== 01. Funciones y permisos =====================
do $p1$
begin
  perform pg_temp.ok('01.01 la huella de campo es la de este cambio', ({{HUELLA_CAMPO_Q}}) = '{{HUELLA_CAMPO_NUEVA}}');
  perform pg_temp.ok('01.02 la función nueva tiene su md5 y el resto de campo no cambió',
    md5(pg_get_functiondef(to_regprocedure('{{FUNCION}}'))) = '{{MD5_NUEVA}}' and pg_temp.huella_resto() = pg_temp.val('huella_resto'));
  perform pg_temp.ok('01.03 la huella del acta y la de Técnica no cambiaron', ({{HUELLA_ACTA_Q}}) = '{{HUELLA_ACTA}}' and ({{HUELLA_TECNICA_Q}}) = '{{HUELLA_TECNICA}}');
  perform pg_temp.ok('01.04 la RPC sigue solo para service_role (ni anon ni authenticated) y SECURITY DEFINER',
    has_function_privilege('service_role', '{{FUNCION}}', 'execute') and not has_function_privilege('anon', '{{FUNCION}}', 'execute')
    and not has_function_privilege('authenticated', '{{FUNCION}}', 'execute') and (select prosecdef from pg_proc where oid = to_regprocedure('{{FUNCION}}')));
  perform pg_temp.ok('01.05 la línea quedó sin «- ''corte''» y no quedan otras',
    position('f.ultimo_pago - ''corte''' in pg_get_functiondef(to_regprocedure('{{FUNCION}}'))) = 0
    and position('f.ultimo_pago || jsonb_build_object(''dias''' in pg_get_functiondef(to_regprocedure('{{FUNCION}}'))) > 0);
end $p1$;

-- ===================== 02. La respuesta =====================
do $p2$
declare r jsonb; a jsonb; u text; c text; v_dif text := ''; t0 timestamptz; v_ms numeric;
        v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
begin
  t0 := clock_timestamp();
  perform pg_temp.foto('despues');
  v_ms := extract(epoch from clock_timestamp() - t0) * 1000 / 20;
  r := pg_temp.val('despues:dual:991800000101')::jsonb;
  perform pg_temp.ok('02.01 cupones: pago.corte = 202610 y lo demás del pago igual (fecha, valor, fuente, días)',
    r -> 'pago' ->> 'corte' = '202610' and r -> 'pago' ->> 'fuente' = 'cupones' and r -> 'pago' ->> 'fecha' = '2026-10-20'
    and (r -> 'pago' ->> 'valor')::numeric = 45000 and (r -> 'pago' ->> 'dias')::int = v_hoy - date '2026-10-20', (r -> 'pago')::text);
  r := pg_temp.val('despues:dual:991800000102')::jsonb;
  perform pg_temp.ok('02.02 cartera mensual: pago.corte = 202609 (no el periodo del consumo ni el de cupones)',
    r -> 'pago' ->> 'corte' = '202609' and r -> 'pago' ->> 'fuente' = 'cartera' and (r -> 'pago' ->> 'valor')::numeric = 30000.5, (r -> 'pago')::text);
  perform pg_temp.ok('02.03 las claves del pago son exactamente fecha, valor, fuente, corte y días',
    (select string_agg(k, ',' order by k) from jsonb_object_keys(r -> 'pago') k) = 'corte,dias,fecha,fuente,valor', (r -> 'pago')::text);
  perform pg_temp.ok('02.04 sin pago: sigue null', jsonb_typeof(pg_temp.val('despues:dual:991800000103')::jsonb -> 'pago') = 'null');
  -- los 5 perfiles × 4 contratos: todo lo demás de la respuesta igual que antes; el pago, igual salvo «corte»
  foreach u in array array['admin', 'sup', 'op', 'dual', 'sin'] loop
    foreach c in array array['991800000101', '991800000102', '991800000103', '991800000199'] loop
      a := pg_temp.val('antes:' || u || ':' || c)::jsonb; r := pg_temp.val('despues:' || u || ':' || c)::jsonb;
      if (a - 'pago') is distinct from (r - 'pago') or (a -> 'pago') is distinct from (case when jsonb_typeof(r -> 'pago') = 'object' then (r -> 'pago') - 'corte' else r -> 'pago' end) then
        v_dif := v_dif || u || ':' || c || ' ';
      end if;
    end loop;
  end loop;
  perform pg_temp.ok('02.05 5 perfiles × 4 contratos: la respuesta es la de antes salvo pago.corte', v_dif = '', v_dif);
  perform pg_temp.ok('02.06 los perfiles sin Análisis siguen sin acceso (operador y sin permisos: mismo error que antes)',
    pg_temp.err(pg_temp.val('despues:op:991800000101')::jsonb) <> 'OK' and pg_temp.err(pg_temp.val('despues:sin:991800000101')::jsonb) <> 'OK'
    and pg_temp.err(pg_temp.val('despues:op:991800000101')::jsonb) = pg_temp.err(pg_temp.val('antes:op:991800000101')::jsonb),
    pg_temp.val('despues:op:991800000101'));
  perform pg_temp.ok('02.07 el contrato que no existe responde igual que antes',
    pg_temp.val('despues:dual:991800000199')::jsonb = pg_temp.val('antes:dual:991800000199')::jsonb, pg_temp.val('despues:dual:991800000199'));
  perform pg_temp.ok('02.08 una consulta tarda menos de 1 s como service_role (con 30 s de tope)', v_ms < 1000, round(v_ms, 1)::text || ' ms');
end $p2$;

-- ===================== 03. Reglas de producción =====================
do $p3$
begin
  perform pg_temp.ok('03.01 ninguna función de campo con DELETE o UPDATE sin WHERE', {{SIN_WHERE_CAMPO}} = 0);
  perform pg_temp.ok('03.02 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
end $p3$;

-- ===================== REVERSA =====================
{{CUERPO_REVERSA}}

-- ===================== 04. Después de la reversa =====================
do $p4$
declare r jsonb;
begin
  perform pg_temp.ok('04.01 la huella de campo vuelve a la publicada', ({{HUELLA_CAMPO_Q}}) = '{{HUELLA_CAMPO}}');
  perform pg_temp.ok('04.02 la función vuelve a su md5 publicado', md5(pg_get_functiondef(to_regprocedure('{{FUNCION}}'))) = '{{MD5_VIEJA}}');
  r := pg_temp.consultar('ztpag.dual@emdupar.gov.co', '991800000101');
  perform pg_temp.ok('04.03 la respuesta vuelve a ser la de antes (sin «corte»)', r = pg_temp.val('antes:dual:991800000101')::jsonb, left(r::text, 300));
  perform pg_temp.ok('04.04 la RPC sigue solo para service_role', has_function_privilege('service_role', '{{FUNCION}}', 'execute')
    and not has_function_privilege('authenticated', '{{FUNCION}}', 'execute') and not has_function_privilege('anon', '{{FUNCION}}', 'execute'));
end $p4$;

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztpag_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;
