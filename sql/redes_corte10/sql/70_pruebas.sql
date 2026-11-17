-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes10.*), sus activos (ZT10, en un rincón de Valledupar), su valoración de prueba
-- (archivo «ZT10 …», que dentro de esta transacción pasa a ser la vigente) y sus amarres. Ninguna cifra real de la valoración.
-- Mide con el volumen real: amarra TODOS los tramos, conductos, hidrantes y válvulas de la base donde corre a la valoración de prueba y toma el tiempo de la
-- conciliación, de la ficha y de la tesela más cargada: FALLA si alguna llamada pasa de 5 s.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 10 … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$
  select ST_SetSRID(ST_MakePoint(round(-73.5800 + x * 0.0000091, 6), round(10.1300 + y * 0.0000090, 6)), 4326) $$;
create function pg_temp.linea(x0 numeric, y0 numeric, x1 numeric, y1 numeric) returns geometry language sql as $$ select ST_MakeLine(pg_temp.pt(x0, y0), pg_temp.pt(x1, y1)) $$;
create function pg_temp.activo(p_prefijo text, p_geom geometry, p_origen_alta text default 'carga', p_fecha date default null, p_estado text default 'en_operacion')
returns bigint language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes10.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, p_origen_alta, q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, estado_codigo, fecha_instalacion, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZT10 ' || p_prefijo, p_estado, p_fecha, '{}'::jsonb, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT10 activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_id;
end $$;
create function pg_temp.cod(p_id bigint) returns text language sql as $$ select codigo from redes.activos where id = p_id $$;
-- la tesela (z, x, y) que contiene un punto
create function pg_temp.tx(g geometry, z integer) returns integer language sql as $$ select floor((ST_X(g) + 180) / 360 * (1 << z))::integer $$;
create function pg_temp.ty(g geometry, z integer) returns integer language sql as $$
  select floor((1 - ln(tan(radians(ST_Y(g))) + 1 / cos(radians(ST_Y(g)))) / pi()) / 2 * (1 << z))::integer $$;
-- una fila de la conciliación
create function pg_temp.fila(p jsonb, p_hoja text, p_n integer) returns jsonb language sql as $$
  select x from jsonb_array_elements(p -> 'filas') x where x ->> 'hoja' = p_hoja and (x ->> 'n')::integer = p_n $$;

do $prueba$
declare
  a text := 'prueba.redes10.adm@emdupar.gov.co'; sd text := 'prueba.redes10.dist@emdupar.gov.co'; op text := 'prueba.redes10.op@emdupar.gov.co';
  v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; v_fop date; v_antes bigint;
  v_val bigint; v_am bigint; v_am2 bigint; v_j jsonb; v_f jsonb; v_x jsonb;
  t1 bigint; t2 bigint; t3 bigint; t4 bigint; t5 bigint; t6 bigint; h1 bigint; h2 bigint; pl bigint; c1 bigint; pz bigint;
  v_z integer; v_m text; v_m2 text; v_g geometry;
  v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_ms4 numeric; v_n integer; v_real bigint; v_tx integer; v_ty integer;
  v_info text := ''; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT10 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT10 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT10 Operador de redes', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);
  v_fop := (v_hoy - interval '10 years')::date;

  -- ===================== 01. Esquema, permisos y parámetros =====================
  perform pg_temp.reg('01.01 las 3 funciones internas nuevas no las ejecuta la API; la RPC nueva y las dos reemplazadas (configuración y tesela del geovisor), solo service_role (security definer)',
     not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname in ('f_val_hoja_alc', 'f_val_prefijos', 'f_ficha_regulatorio', 'f_ficha', 'f_param_entero')
                   and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')))
     and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_valoracion', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor') and p.prosecdef
           and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
           and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 3);
  perform pg_temp.reg('01.02 las 3 tablas: con seguridad de filas, sin permisos para la API y de solo agregar (6 disparadores)',
     (select count(*) from pg_class c where c.oid in ('redes.val_hojas'::regclass, 'redes.val_filas'::regclass, 'redes.val_amarre'::regclass) and c.relrowsecurity
       and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')) = 3
     and (select count(*) from pg_trigger t where t.tgrelid in ('redes.val_hojas'::regclass, 'redes.val_filas'::regclass, 'redes.val_amarre'::regclass) and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 6);
  perform pg_temp.reg('01.03 los parámetros: vale la hoja «ALCANTARILLADO (2)» (2) y la tolerancia es 2 %; la unidad «hoja» es un entero',
     redes.f_param('valoracion_hoja_alcantarillado') = 2 and redes.f_val_hoja_alc() = 'alcantarillado_2' and redes.f_param('valoracion_tolerancia_pct') = 2
     and redes.f_param_entero('hoja') and redes.f_param_entero('zoom') and not redes.f_param_entero('%'));
  perform pg_temp.reg('01.04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()),
     (select string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()));

  -- ===================== 02. Los activos de prueba y, antes de cargar nada, cómo responde =====================
  t1 := pg_temp.activo('RED', pg_temp.linea(0, 0, 100, 0));                 -- amarrado, sin fecha de instalación
  t2 := pg_temp.activo('RED', pg_temp.linea(0, 20, 150, 20));               -- amarrado
  t3 := pg_temp.activo('RED', pg_temp.linea(0, 40, 60, 40), 'carga', null, 'proyectado');      -- proyectado: no entra
  t4 := pg_temp.activo('RED', pg_temp.linea(0, 60, 80, 60));                -- sin fila
  t5 := pg_temp.activo('RED', pg_temp.linea(0, 80, 40, 80), 'intervencion');      -- nuevo de una inversión: sin amarre → fuera de la valoración
  t6 := pg_temp.activo('RED', pg_temp.linea(20000, 20000, 20100, 20000), 'carga', (v_hoy - interval '3 years')::date);      -- lejos; amarrado y CON fecha de instalación
  h1 := pg_temp.activo('TOR', pg_temp.pt(10, 100)); h2 := pg_temp.activo('TOR', pg_temp.pt(30, 100));
  pl := pg_temp.activo('PTA', pg_temp.pt(50, 120));                          -- una planta para dos filas
  c1 := pg_temp.activo('COL', pg_temp.linea(0, 140, 90, 140));              -- conducto de alcantarillado: fila según la hoja que valga
  pz := pg_temp.activo('POZ', pg_temp.pt(0, 160));                           -- un tipo que la valoración no cubre
  v_antes := redes.f_ref_vigente('valoracion');
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t1));
  v_j := public.geoportal_redes_valoracion(a);
  perform pg_temp.reg('02.01 sin valoración cargada: la ficha no trae la sección y la conciliación dice «sin cargar» (si ya hay una vigente, la trae)',
     case when v_antes is null then not (v_f ? 'regulatorio') and not (v_j ->> 'cargada')::boolean and v_j ->> 'hoja_alcantarillado' = 'alcantarillado_2'
          else (v_j ->> 'cargada')::boolean and (v_f -> 'regulatorio' ->> 'situacion') = 'fuera' end,
     case when v_antes is null then 'la base no tenía valoración' else 'la base ya tenía una valoración vigente (carga ' || v_antes || ')' end);

  -- ===================== 03. La valoración y el amarre de prueba =====================
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor) values ('valoracion', 'ZT10 valoracion de prueba.xlsx', md5('zt10-val'), 8, 'ZT10 valoración de prueba', null, a) returning id into v_val;
  insert into redes.val_hojas (carga_id, hoja, nombre_hoja, servicio, filas, bcr0, valor_total, depreciacion_anual) values
    (v_val, 'acueducto', 'ZT10 ACUEDUCTO', 'acueducto', 5, 5000, 9000, 200), (v_val, 'alcantarillado', 'ZT10 ALCANTARILLADO', 'alcantarillado', 1, 700, 900, 20),
    (v_val, 'alcantarillado_2', 'ZT10 ALCANTARILLADO (2)', 'alcantarillado', 2, 800, 1000, 30);
  insert into redes.val_filas (carga_id, hoja, n, nombre, vida_util, caracteristica, cantidad, unidad, precio_unitario, valor_total, anio_operacion, fecha_operacion, fecha_tarifa,
                               valor_remanente, depreciacion_anual, clase, material, diametro_pulg, nota) values
    (v_val, 'acueducto', 1, 'TUBERIA ZT10', 45, '3', 250, 'm', 10, 2500, extract(year from v_fop)::integer, v_fop, v_fop + 30, 1500, 55.6, 'tuberia', 'ZT10', 3, null),
    (v_val, 'acueducto', 2, 'TUBERIA ZT10', 45, '4', 500, 'm', 12, 6000, 1989, date '1989-07-01', date '2016-07-01', 3000, 133.3, 'tuberia', 'ZT10', 4, null),
    (v_val, 'acueducto', 3, 'HIDRANTES ZT10', 45, null, 2, 'un', 100, 200, 1989, date '1989-07-01', date '2016-07-01', 100, 4.4, 'hidrante', null, null, null),
    (v_val, 'acueducto', 4, 'PLANTA ZT10 UNO', 40, 'Planta', 600, 'L/s', null, 200, 1992, date '1992-07-01', date '2016-07-01', 200, 5, 'puntual', null, null, null),
    (v_val, 'acueducto', 5, 'PLANTA ZT10 DOS', 40, 'Planta', 300, 'L/s', null, 100, 2001, date '2001-07-01', date '2016-07-01', 200, 2.5, 'puntual', null, null, 'ZT10 nota de la fila'),
    (v_val, 'alcantarillado', 1, 'TUBERIA ZT10 GRES', 45, '8', 500, 'm', 9, 900, 1989, date '1989-07-01', date '2016-07-01', 700, 20, 'tuberia', 'ZT10 GRES', 8, null),
    (v_val, 'alcantarillado_2', 1, 'TUBERIA ZT10 GRES', 45, '8', 90, 'm', 9, 810, 1989, date '1989-07-01', date '2016-07-01', 600, 18, 'tuberia', 'ZT10 GRES', 8, null),
    (v_val, 'alcantarillado_2', 2, 'TUBERIA ZT10 PVC', 45, '8', 40, 'm', 9, 190, 1989, date '1989-07-01', date '2016-07-01', 200, 12, 'tuberia', 'ZT10 PVC', 8, null);
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor) values ('val_amarre', 'ZT10 amarre de prueba.csv', md5('zt10-am'), 10, 'ZT10 amarre de prueba', null, a) returning id into v_am;
  insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion, nota) values
    (v_am, v_val, t1, 'acueducto', 1, 100, 'con_fila', null), (v_am, v_val, t2, 'acueducto', 1, 150, 'aparte_siva', 'ZT10 obra de un tercero'),
    (v_am, v_val, t3, 'acueducto', null, 60, 'proyectado', null), (v_am, v_val, t4, 'acueducto', null, 80, 'sin_fila', 'ZT10 sin pareja'),
    (v_am, v_val, t6, 'acueducto', 1, 0, 'con_fila', null),
    (v_am, v_val, h1, 'acueducto', 3, 1, 'con_fila', null), (v_am, v_val, h2, 'acueducto', 3, 1, 'con_fila', null),
    (v_am, v_val, pl, 'acueducto', 4, 1, 'con_fila', null), (v_am, v_val, pl, 'acueducto', 5, 1, 'con_fila', null),
    (v_am, v_val, c1, 'alcantarillado_2', 1, 90, 'con_fila', null), (v_am, v_val, c1, 'alcantarillado', 1, 90, 'con_fila', null);
  perform pg_temp.reg('03.01 la valoración y el amarre de prueba quedan vigentes', redes.f_ref_vigente('valoracion') = v_val and redes.f_ref_vigente('val_amarre') = v_am);
  perform pg_temp.err('03.02 un amarre «con fila» sin número de fila se rechaza',
     format($$insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion) values (%s, %s, %s, 'acueducto', null, 1, 'con_fila')$$, v_am, v_val, t4), '23514');
  perform pg_temp.err('03.03 un amarre a una fila que no existe en la valoración se rechaza',
     format($$insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion) values (%s, %s, %s, 'acueducto', 99, 1, 'con_fila')$$, v_am, v_val, t4), '23503');
  perform pg_temp.err('03.04 el mismo activo no se amarra dos veces a la misma fila en una carga',
     format($$insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion) values (%s, %s, %s, 'acueducto', 1, 1, 'con_fila')$$, v_am, v_val, t1), '23505');
  perform pg_temp.err('03.05 la valoración es de solo inserción: no se corrige una fila', format($$update redes.val_filas set cantidad = 1 where carga_id = %s and hoja = 'acueducto' and n = 1$$, v_val));
  perform pg_temp.err('03.06 el amarre es de solo inserción: no se borra', format($$delete from redes.val_amarre where carga_id = %s and activo_id = %s$$, v_am, t1));

  -- ===================== 04. La ficha: «Inventario regulatorio», solo supervisor y administrador =====================
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t1)) -> 'regulatorio';
  v_x := v_f -> 'filas' -> 0;
  perform pg_temp.reg('04.01 administrador, tramo amarrado: remunerado, con su fila (nombre, característica, cantidad y cuántos activos tiene amarrados)',
     (v_f ->> 'remunerado')::boolean and v_f ->> 'situacion' = 'con_fila' and v_f ->> 'fuente' like 'Valoración técnica 2019%propuesta' and jsonb_array_length(v_f -> 'filas') = 1
     and v_x ->> 'nombre' = 'TUBERIA ZT10' and v_x ->> 'caracteristica' = '3' and (v_x ->> 'cantidad')::numeric = 250 and v_x ->> 'unidad' = 'm' and (v_x ->> 'activos')::integer = 3
     and v_x ->> 'hoja' = 'ZT10 ACUEDUCTO' and (v_x ->> 'aporte')::numeric = 100, v_f::text);
  perform pg_temp.reg('04.02 fecha de entrada en operación regulatoria, vida útil 45 y vida útil remanente A HOY (45 − 10 años = 35,0); valor y depreciación de la FILA',
     (v_x ->> 'fecha_operacion')::date = v_fop and (v_x ->> 'vida_util')::numeric = 45 and (v_x ->> 'vida_remanente_hoy')::numeric between 34.9 and 35.1
     and (v_x ->> 'fin_vida_util')::date = (v_fop + interval '45 years')::date
     and (v_x ->> 'valor_total')::numeric = 2500 and (v_x ->> 'valor_remanente')::numeric = 1500 and (v_x ->> 'depreciacion_anual')::numeric = 56, v_x::text);
  perform pg_temp.reg('04.03 una fila ya vencida da vida útil remanente 0 o más (nunca negativa)',
     (select (public.geoportal_redes_activo(a, pg_temp.cod(h1)) -> 'regulatorio' -> 'filas' -> 0 ->> 'vida_remanente_hoy')::numeric)
       = greatest(0, round(45 - (v_hoy - date '1989-07-01') / 365.25, 1)));
  perform pg_temp.reg('04.04 el supervisor de distribución también la ve; el operador NO (ni la sección ni ningún valor)',
     (public.geoportal_redes_activo(sd, pg_temp.cod(t1)) -> 'regulatorio' ->> 'remunerado')::boolean
     and not (public.geoportal_redes_activo(op, pg_temp.cod(t1)) ? 'regulatorio')
     and public.geoportal_redes_activo(op, pg_temp.cod(t1))::text !~* 'remunerad|valoraci|depreciaci|tarif|regulator');
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t2)) -> 'regulatorio';
  perform pg_temp.reg('04.05 un tramo «marcado aparte» (obra de un tercero): NO remunerado, pero muestra su fila y su nota (decisión de David, 16-nov)',
     not (v_f ->> 'remunerado')::boolean and v_f ->> 'situacion' = 'aparte' and v_f ->> 'texto' like '%obra de un tercero (SIVA)%no se remunera%'
     and jsonb_array_length(v_f -> 'filas') = 1 and v_f -> 'filas' -> 0 ->> 'nota' = 'ZT10 obra de un tercero', v_f::text);
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t3)) -> 'regulatorio';
  perform pg_temp.reg('04.06 un tramo proyectado: no remunerado, «no entra en la valoración»',
     not (v_f ->> 'remunerado')::boolean and v_f ->> 'situacion' = 'proyectado' and v_f ->> 'texto' like 'Proyectado%' and not (v_f ? 'filas'), v_f::text);
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t4)) -> 'regulatorio';
  perform pg_temp.reg('04.07 un tramo sin fila: no remunerado, con el motivo',
     not (v_f ->> 'remunerado')::boolean and v_f ->> 'situacion' = 'sin_fila' and v_f ->> 'texto' like 'Sin fila%' and v_f ->> 'nota' = 'ZT10 sin pareja', v_f::text);
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t5)) -> 'regulatorio';
  perform pg_temp.reg('04.08 un activo nuevo de una inversión (sin amarre): «fuera de la valoración 2019», no remunerado',
     not (v_f ->> 'remunerado')::boolean and v_f ->> 'situacion' = 'fuera' and v_f ->> 'texto' like 'Fuera de la valoración 2019%', v_f::text);
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(pl)) -> 'regulatorio';
  perform pg_temp.reg('04.09 un activo con dos filas (la planta): las trae las dos, en orden',
     (v_f ->> 'remunerado')::boolean and jsonb_array_length(v_f -> 'filas') = 2 and v_f -> 'filas' -> 0 ->> 'nombre' = 'PLANTA ZT10 UNO' and v_f -> 'filas' -> 1 ->> 'nombre' = 'PLANTA ZT10 DOS'
     and v_f -> 'filas' -> 0 ->> 'unidad' = 'L/s', v_f::text);
  perform pg_temp.reg('04.10 un tipo que la valoración no cubre (un pozo) no lleva la sección',
     not (public.geoportal_redes_activo(a, pg_temp.cod(pz)) ? 'regulatorio'));
  perform pg_temp.reg('04.11 la ficha oficial no cambió: ningún activo de prueba tiene más de su versión 1',
     (select max(v.version) from redes.activo_versiones v where v.activo_id in (t1, t2, t3, t4, t5, t6, h1, h2, pl, c1, pz)) = 1);

  -- ===================== 05. La hoja de alcantarillado que vale (parámetro) =====================
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(c1)) -> 'regulatorio';
  perform pg_temp.reg('05.01 con el parámetro en 2, el conducto muestra su fila de «ALCANTARILLADO (2)»',
     v_f -> 'filas' -> 0 ->> 'hoja' = 'ZT10 ALCANTARILLADO (2)' and (v_f -> 'filas' -> 0 ->> 'cantidad')::numeric = 90 and jsonb_array_length(v_f -> 'filas') = 1, v_f::text);
  perform pg_temp.err('05.02 el parámetro de la hoja solo admite 1 o 2 (enteros)',
     format($$select public.geoportal_redes_parametro_fijar(%L, 'valoracion_hoja_alcantarillado', 1.5, 'ZT10 prueba de la hoja vigente')$$, a), null, 'enteros');
  perform pg_temp.err('05.03 el supervisor no cambia la hoja: solo el administrador',
     format($$select public.geoportal_redes_parametro_fijar(%L, 'valoracion_hoja_alcantarillado', 1, 'ZT10 prueba de la hoja vigente')$$, sd), '42501');
  perform public.geoportal_redes_parametro_fijar(a, 'valoracion_hoja_alcantarillado', 1, 'ZT10 prueba de la hoja vigente');
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(c1)) -> 'regulatorio';
  v_j := public.geoportal_redes_valoracion(a);
  perform pg_temp.reg('05.04 al cambiar el parámetro a 1, vale la otra hoja: en la ficha y en la conciliación (sin recargar nada)',
     v_f -> 'filas' -> 0 ->> 'hoja' = 'ZT10 ALCANTARILLADO' and (v_f -> 'filas' -> 0 ->> 'cantidad')::numeric = 500 and v_j ->> 'hoja_alcantarillado' = 'alcantarillado'
     and (select (x ->> 'vigente')::boolean from jsonb_array_elements(v_j -> 'hojas') x where x ->> 'hoja' = 'alcantarillado')
     and not (select (x ->> 'vigente')::boolean from jsonb_array_elements(v_j -> 'hojas') x where x ->> 'hoja' = 'alcantarillado_2'), v_f::text);
  perform public.geoportal_redes_parametro_fijar(a, 'valoracion_hoja_alcantarillado', 2, 'ZT10 prueba: vuelve a la hoja (2)');

  -- ===================== 06. La conciliación (solo el administrador) =====================
  perform pg_temp.err('06.01 la conciliación no la ve el supervisor de distribución', format('select public.geoportal_redes_valoracion(%L)', sd), '42501');
  perform pg_temp.err('06.02 ni el operador', format('select public.geoportal_redes_valoracion(%L)', op), '42501');
  perform pg_temp.err('06.03 ni alguien sin identificar', 'select public.geoportal_redes_valoracion(null)', '28000');
  v_j := public.geoportal_redes_valoracion(a);
  v_x := pg_temp.fila(v_j, 'acueducto', 1);
  perform pg_temp.reg('06.04 una fila de tubería: 250 m en la valoración contra 250 m de la red (3 tramos; 150 «aparte»), diferencia 0, 100 %, calza',
     (v_x ->> 'cantidad')::numeric = 250 and (v_x ->> 'red')::numeric = 250 and (v_x ->> 'activos')::integer = 3 and (v_x ->> 'aparte')::numeric = 150
     and (v_x ->> 'diferencia')::numeric = 0 and (v_x ->> 'pct')::numeric = 100 and (v_x ->> 'calza')::boolean and (v_x ->> 'comparable')::boolean, v_x::text);
  v_x := pg_temp.fila(v_j, 'acueducto', 2);
  perform pg_temp.reg('06.05 una fila sin activos: red 0, diferencia −500, 0 %, no calza',
     (v_x ->> 'activos')::integer = 0 and (v_x ->> 'red')::numeric = 0 and (v_x ->> 'diferencia')::numeric = -500 and (v_x ->> 'pct')::numeric = 0 and not (v_x ->> 'calza')::boolean, v_x::text);
  v_x := pg_temp.fila(v_j, 'acueducto', 3);
  perform pg_temp.reg('06.06 hidrantes: 2 en la valoración y 2 en la red, con sus códigos', (v_x ->> 'red')::numeric = 2 and (v_x ->> 'calza')::boolean and v_x ->> 'codigos' like 'TOR-%, TOR-%', v_x::text);
  v_x := pg_temp.fila(v_j, 'acueducto', 5);
  perform pg_temp.reg('06.07 un puntual (planta) no se compara por cantidad: dice con qué activo está amarrado y trae la nota de la fila',
     not (v_x ->> 'comparable')::boolean and not (v_x ? 'red') and not (v_x ? 'calza') and (v_x ->> 'activos')::integer = 1 and v_x ->> 'codigos' = pg_temp.cod(pl) and v_x ->> 'nota' = 'ZT10 nota de la fila', v_x::text);
  v_x := pg_temp.fila(v_j, 'alcantarillado_2', 1);
  perform pg_temp.reg('06.08 las dos hojas de alcantarillado vienen conciliadas: la (2) calza (90 de 90) y la de referencia no (90 de 500)',
     (v_x ->> 'calza')::boolean and (pg_temp.fila(v_j, 'alcantarillado', 1) ->> 'pct')::numeric = 18 and not (pg_temp.fila(v_j, 'alcantarillado', 1) ->> 'calza')::boolean
     and (pg_temp.fila(v_j, 'alcantarillado_2', 2) ->> 'activos')::integer = 0, v_x::text);
  perform pg_temp.reg('06.09 activos sin fila, agrupados: el proyectado, el «sin fila» y el nuevo de una inversión («fuera»), con sus metros',
     (select count(*) from jsonb_array_elements(v_j -> 'sin_fila') x where x ->> 'prefijo' = 'RED' and x ->> 'motivo' = 'proyectado' and (x ->> 'longitud_m')::numeric = 60) >= 1
     and (select count(*) from jsonb_array_elements(v_j -> 'sin_fila') x where x ->> 'prefijo' = 'RED' and x ->> 'motivo' = 'sin_fila' and (x ->> 'longitud_m')::numeric = 80) >= 1
     and (select count(*) from jsonb_array_elements(v_j -> 'sin_fila') x where x ->> 'prefijo' = 'RED' and x ->> 'motivo' = 'fuera' and (x ->> 'activos')::integer >= 1) >= 1
     and not exists (select 1 from jsonb_array_elements(v_j -> 'sin_fila') x where x ->> 'prefijo' = 'POZ'),
     (select string_agg(x ->> 'prefijo' || ':' || (x ->> 'motivo') || ':' || (x ->> 'activos'), ' ') from jsonb_array_elements(v_j -> 'sin_fila') x));
  perform pg_temp.reg('06.10 la conciliación dice de qué archivo sale, que es una propuesta, los totales por hoja y la tolerancia; sin datos de personas',
     v_j ->> 'fuente' like '%propuesta' and v_j -> 'valoracion' ->> 'archivo' = 'ZT10 valoracion de prueba.xlsx' and v_j -> 'amarre' ->> 'archivo' = 'ZT10 amarre de prueba.csv'
     and (v_j ->> 'tolerancia_pct')::numeric = 2 and jsonb_array_length(v_j -> 'hojas') = 3 and jsonb_array_length(v_j -> 'filas') = 8
     and (select (x ->> 'bcr0')::numeric from jsonb_array_elements(v_j -> 'hojas') x where x ->> 'hoja' = 'acueducto') = 5000
     and v_j::text !~* 'suscriptor|telefono|teléfono|cedula|cédula');

  -- ===================== 07. El color por edad del geovisor =====================
  -- (la tesela no se puede abrir desde SQL: se compara la del administrador con la del operador, que nunca recibe la fecha regulatoria)
  v_z := floor(redes.f_param('geovisor_zoom_red_completa'))::integer;
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT10 prueba: el operador con el geovisor');
  v_g := pg_temp.pt(50, 0);
  v_m := public.geoportal_redes_geovisor_mvt(a, v_z, pg_temp.tx(v_g, v_z), pg_temp.ty(v_g, v_z));
  v_m2 := public.geoportal_redes_geovisor_mvt(op, v_z, pg_temp.tx(v_g, v_z), pg_temp.ty(v_g, v_z));
  perform pg_temp.reg('07.01 tramos sin fecha de instalación y con fila: la tesela del administrador trae la edad de la fecha regulatoria (marcada «edad_reg»); la del operador de redes, no',
     length(v_m2) > 0 and length(v_m) > length(v_m2) and position('edad_reg'::bytea in decode(v_m, 'base64')) > 0, length(v_m) || ' caracteres contra ' || length(v_m2));
  perform pg_temp.reg('07.02 el supervisor de distribución recibe la misma tesela que el administrador',
     public.geoportal_redes_geovisor_mvt(sd, v_z, pg_temp.tx(v_g, v_z), pg_temp.ty(v_g, v_z)) = v_m);
  v_g := pg_temp.pt(20050, 20000);
  v_m := public.geoportal_redes_geovisor_mvt(a, v_z, pg_temp.tx(v_g, v_z), pg_temp.ty(v_g, v_z));
  v_m2 := public.geoportal_redes_geovisor_mvt(op, v_z, pg_temp.tx(v_g, v_z), pg_temp.ty(v_g, v_z));
  perform pg_temp.reg('07.04 la configuración del geovisor avisa que hay edad regulatoria (para la nota de la leyenda) a supervisores y administrador, no al operador',
     (public.geoportal_redes_geovisor(a) ->> 'edad_ref')::boolean and (public.geoportal_redes_geovisor(sd) ->> 'edad_ref')::boolean
     and (public.geoportal_redes_geovisor(op) ->> 'edad_ref') is null and public.geoportal_redes_geovisor(op)::text !~* 'regulator|valoraci|tarif');
  perform pg_temp.reg('07.03 la fecha de instalación de la ficha siempre gana: un tramo con fecha y con fila sale igual para el administrador y para el operador (sin fecha regulatoria)',
     length(v_m) > 0 and v_m = v_m2, length(v_m) || ' caracteres');

  -- ===================== 08. El amarre se puede volver a cargar: vale el último; el anterior queda =====================
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor) values ('val_amarre', 'ZT10 amarre de prueba 2.csv', md5('zt10-am2'), 1, 'ZT10 amarre de prueba', null, a) returning id into v_am2;
  insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion) values (v_am2, v_val, t4, 'acueducto', 2, 80, 'con_fila');
  v_j := public.geoportal_redes_valoracion(a);
  perform pg_temp.reg('08.01 con un amarre nuevo, el tramo que estaba «sin fila» queda con fila, y el que no viene en él queda «fuera»; el amarre anterior sigue guardado',
     (public.geoportal_redes_activo(a, pg_temp.cod(t4)) -> 'regulatorio' ->> 'remunerado')::boolean
     and public.geoportal_redes_activo(a, pg_temp.cod(t1)) -> 'regulatorio' ->> 'situacion' = 'fuera'
     and (pg_temp.fila(v_j, 'acueducto', 2) ->> 'red')::numeric = 80 and (select count(*) from redes.val_amarre where carga_id = v_am) = 11);
  insert into redes.ref_carga_eventos (carga_id, tipo, motivo, autor) values (v_am2, 'anular', 'ZT10 prueba: se anula el segundo amarre', a);
  perform pg_temp.reg('08.02 al anular esa carga (con motivo) vuelve a valer el amarre anterior',
     redes.f_ref_vigente('val_amarre') = v_am and (public.geoportal_redes_activo(a, pg_temp.cod(t1)) -> 'regulatorio' ->> 'remunerado')::boolean);

  -- ===================== 09. Tiempos con el volumen real =====================
  -- todos los tramos, conductos, hidrantes y válvulas de la base, amarrados a la valoración de prueba (lo que hará la carga real)
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor) values ('val_amarre', 'ZT10 amarre de volumen.csv', md5('zt10-vol'), 0, 'ZT10 amarre de prueba', null, a) returning id into v_am2;
  insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion)
  select v_am2, v_val, m.activo_id, h.hoja, case when h.hoja = 'acueducto' and m.prefijo in ('TOR', 'HID', 'VAL') then 3 when h.hoja = 'acueducto' then 1 + (m.activo_id % 2)::integer else 1 end,
         coalesce(m.longitud_m, 1), 'con_fila'
    from redes.activo_vigente_mat m
    join (values ('acueducto', 'acueducto'), ('alcantarillado', 'alcantarillado'), ('alcantarillado', 'alcantarillado_2')) h(sistema, hoja) on h.sistema = m.sistema
   where not m.retirado and not m.oculto and m.prefijo in ('RED', 'CON', 'COL', 'TOR', 'HID', 'VAL');
  get diagnostics v_n = row_count;
  analyze redes.val_amarre;
  select m.activo_id into v_real from redes.activo_vigente_mat m where m.prefijo = 'RED' and not m.retirado and m.activo_id not in (t1, t2, t3, t4, t5, t6) order by m.activo_id limit 1;
  v_real := coalesce(v_real, t1);
  select t.x, t.y into v_tx, v_ty from (select pg_temp.tx(ST_PointOnSurface(m.geom), v_z) as x, pg_temp.ty(ST_PointOnSurface(m.geom), v_z) as y
                                          from redes.activo_vigente_mat m where m.prefijo in ('RED', 'COL') and not m.retirado) t group by t.x, t.y order by count(*) desc limit 1;
  v_t0 := clock_timestamp(); v_j := public.geoportal_redes_valoracion(a); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_f := public.geoportal_redes_activo(a, pg_temp.cod(v_real)); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_m := public.geoportal_redes_geovisor_mvt(a, v_z, v_tx, v_ty); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_m2 := public.geoportal_redes_geovisor_mvt(a, v_z - 1, v_tx / 2, v_ty / 2); v_ms4 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS con %s amarres (todos los tramos, conductos, hidrantes y válvulas de esta base): conciliación %s ms · ficha de %s %s ms · tesela más cargada %s/%s/%s %s ms (%s kB) · tesela %s/%s/%s %s ms (%s kB)',
                   v_n, v_ms1, pg_temp.cod(v_real), v_ms2, v_z, v_tx, v_ty, v_ms3, round(length(v_m) * 0.75 / 1024), v_z - 1, v_tx / 2, v_ty / 2, v_ms4, round(length(v_m2) * 0.75 / 1024));
  perform pg_temp.reg('09.01 con el volumen real, la conciliación suma todo lo amarrado y la ficha de un tramo real trae su fila',
     (v_f -> 'regulatorio' ->> 'remunerado')::boolean
     and (select sum((x ->> 'activos')::integer) from jsonb_array_elements(v_j -> 'filas') x) = v_n, v_info);
  perform pg_temp.reg('09.02 TIEMPOS: la conciliación, la ficha y las teselas, cada llamada en menos de 5 s (el tope de la Edge es 30 s)', greatest(v_ms1, v_ms2, v_ms3, v_ms4) < 5000, v_info);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 10 (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
