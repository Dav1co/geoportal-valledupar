begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · «MIS REPORTES» (levantar_mios) · 10 — GUARDIA E ÍNDICE
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: contrato del Code B (paquete_fase1/mis_reportes_y_repetidos/ENTRADA_BITACORA.md) y encargo de David del 19-nov.
-- · Presupone el Corte 15 publicado: huella del conjunto de funciones de redes ef7564883f523685cfe36478e0985e98.
-- · SOLO AGREGA 1 RPC de lectura y 1 índice (por autor) en redes.levantar_puntos. No reemplaza ninguna función, no crea tablas ni parámetros
--   y no cambia quién puede reportar ni quién ve la bandeja del supervisor.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_levantar_mios(text,integer)') is not null or to_regclass('redes.ix_levantar_puntos_autor') is not null then raise exception '«Mis reportes» ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'ef7564883f523685cfe36478e0985e98' then
    raise exception 'Las funciones de redes no son las del Corte 15 publicado (huella ef7564883f523685cfe36478e0985e98): deténgase y avise';
  end if;
  if to_regclass('redes.levantar_puntos') is null or to_regclass('redes.v_levantar_punto') is null or to_regprocedure('redes.f_levantar_acceso(text)') is null
     or to_regprocedure('redes.f_levantar_tipo_nombre(text)') is null or to_regprocedure('redes.f_levantar_estado_nombre(text)') is null then
    raise exception 'Faltan tablas o funciones del Corte 14 («Encontrar o reportar activo»): deténgase y avise';
  end if;
end $$;
-- «los míos, los últimos primero»: por autor y fecha (la tabla solo tenía índice por fecha y por lugar)
create index ix_levantar_puntos_autor on redes.levantar_puntos (autor, registrado_en desc);
-- =====================================================================
-- TÉCNICA · FASE 1 · «MIS REPORTES» (levantar_mios) · 26 — RPC (la llama la Edge geoportal-redes, ruta levantar_mios).
--   · geoportal_redes_levantar_mios: los puntos por levantar que reportó QUIEN CONSULTA, los últimos primero, con su estado de hoy.
-- Por qué: «levantar_lista» es la bandeja del supervisor (todos los puntos, con quién los reportó). Quien reporta no tenía cómo ver los suyos.
-- Quién: todo el que puede reportar (redes.f_levantar_acceso: administrador, supervisores, el operador con el formulario y Comercial con Formularios de campo).
-- Qué devuelve: solo lo propio. No trae nombres ni correos (ni el suyo ni el de quien cambió el estado), ni el motivo del estado, ni fotos, ni la posición.
-- Periodo: 30 o 90 días, o 0 = todos. Tope de 500 por respuesta; «total» dice cuántos hay y «recortada» si no cupieron todos.
-- Solo lectura: no guarda ni audita (no hay datos de suscriptores ni de otras personas).
-- =====================================================================
create function public.geoportal_redes_levantar_mios(p_solicitante text, p_dias integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare a record; v_dias integer := coalesce(p_dias, 30); v_tope constant integer := 500; v_desde timestamptz; v_total integer; v_items jsonb;
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if v_dias not in (0, 30, 90) then perform tecnica.f_error('El periodo es de 30 días, de 90 días o todos'); end if;
  if v_dias > 0 then v_desde := clock_timestamp() - make_interval(days => v_dias); end if;
  select count(*) into v_total from redes.levantar_puntos x where x.autor = a.email and (v_desde is null or x.registrado_en >= v_desde);
  select coalesce(jsonb_agg(jsonb_build_object('codigo', p.codigo, 'registrado_en', p.registrado_en, 'servicio', p.servicio, 'tipo', p.tipo, 'tipo_nombre', redes.f_levantar_tipo_nombre(p.tipo),
           'estado', p.estado, 'estado_nombre', redes.f_levantar_estado_nombre(p.estado), 'estado_desde', p.estado_desde,
           'activo', (select m.codigo from redes.activos m where m.id = p.activo_id)) order by p.registrado_en desc, p.codigo desc), '[]'::jsonb)
    into v_items
    from (select x.id from redes.levantar_puntos x where x.autor = a.email and (v_desde is null or x.registrado_en >= v_desde)
           order by x.registrado_en desc, x.codigo desc limit v_tope) m
    join redes.v_levantar_punto p on p.id = m.id;
  return jsonb_build_object('dias', v_dias, 'total', v_total, 'recortada', v_total > v_tope, 'items', v_items);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · «MIS REPORTES» (levantar_mios) · 40 — PERMISOS: revoke all antes de dar permisos. La RPC: solo service_role.
-- =====================================================================
revoke all on function public.geoportal_redes_levantar_mios(text, integer) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_levantar_mios(text, integer) to service_role;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_levantar_mios', 'migracion_redes_levantar_mios', null, jsonb_build_object(
        'nuevas', jsonb_build_array('geoportal_redes_levantar_mios'), 'indices', jsonb_build_array('redes.ix_levantar_puntos_autor'),
        'motivo', 'quien reporta un activo por levantar ve sus propios reportes y su estado («Mis reportes»); no cambia la bandeja del supervisor'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · «MIS REPORTES» (levantar_mios) · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 26 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redesmios.*), reporta puntos con las RPC publicadas (en un rincón de la caja, lejos de la red)
-- y, para los periodos y el volumen, agrega puntos con fecha vieja y códigos LEV-98…/LEV-97… (la tabla es de solo inserción: no se puede cambiar la fecha de uno).
-- Mide la lectura con 20.000 puntos de relleno y FALLA si pasa de 1 s.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · «Mis reportes» … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.foto(p_ruta text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', 200000, 'mimetype', 'image/jpeg')) $$;
-- prepara, «sube» la foto y crea un punto por levantar con las RPC publicadas; devuelve su código
create function pg_temp.punto(p_quien text, p_x numeric, p_y numeric, p_servicio text default 'acueducto', p_tipo text default 'valvula') returns text language plpgsql as $$
declare j jsonb; f jsonb;
begin
  j := public.geoportal_redes_levantar_preparar(p_quien, 1);
  for f in select e from jsonb_array_elements(j -> 'fotos') e loop perform pg_temp.foto(f ->> 'ruta'); end loop;
  return public.geoportal_redes_levantar_crear(p_quien, (j ->> 'punto_id')::uuid,
    jsonb_build_object('servicio', p_servicio, 'tipo', p_tipo, 'lat', pg_temp.lat(p_y), 'lon', pg_temp.lon(p_x), 'precision_m', 5, 'fotos', j -> 'fotos'), '127.0.0.1') ->> 'codigo';
end $$;
-- un punto con fecha vieja (inserción directa: la fecha de un punto no se puede cambiar después)
create function pg_temp.viejo(p_codigo text, p_quien text, p_dias numeric, p_x numeric, p_area text default 'tecnica') returns void language sql as $$
  insert into redes.levantar_puntos (id, codigo, servicio, tipo, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en)
  values (gen_random_uuid(), p_codigo, 'alcantarillado', 'pozo', pg_temp.lat(900), pg_temp.lon(p_x), ST_SetSRID(ST_MakePoint(pg_temp.lon(p_x), pg_temp.lat(900)), 4326), 5, false, p_area, p_quien,
          clock_timestamp() - make_interval(secs => (p_dias * 86400)::double precision)) $$;

do $prueba$
declare
  a text := 'prueba.redesmios.adm@emdupar.gov.co'; sd text := 'prueba.redesmios.sd@emdupar.gov.co'; op text := 'prueba.redesmios.op@emdupar.gov.co'; op2 text := 'prueba.redesmios.op2@emdupar.gov.co';
  op3 text := 'prueba.redesmios.op3@emdupar.gov.co'; co text := 'prueba.redesmios.co@emdupar.gov.co'; na text := 'prueba.redesmios.nada@emdupar.gov.co';
  j jsonb; j2 jsonb; v_l1 text; v_l2 text; v_l3 text; v_o1 text; v_c1 text; v_val text; v_id bigint; v_cons bigint; v_aud bigint; v_n bigint; v_xmax bigint;
  v_t0 timestamptz; v_ms numeric; v_ms2 numeric; v_ms3 numeric; v_info text; v_total integer; v_bien integer; v_fallas text; v_plan text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZTMIOS Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZTMIOS Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZTMIOS Operador uno', 'consulta', true, 'sin_restriccion', 'todos'),
    (op2, 'ZTMIOS Operador dos', 'consulta', true, 'sin_restriccion', 'todos'), (op3, 'ZTMIOS Operador sin formulario', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values (co, 'ZTMIOS Operario de Comercial', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_comercial, horario, dias) values (na, 'ZTMIOS Sin permiso', 'consulta', true, 'sin_restriccion', 'todos');
  perform public.geoportal_redes_personal_formulario(sd, op, 'activo_campo', true, 'ZTMIOS sale a campo a levantar activos', '127.0.0.1');
  perform public.geoportal_redes_personal_formulario(sd, op2, 'activo_campo', true, 'ZTMIOS sale a campo a levantar activos', '127.0.0.1');

  -- ===================== 01. Quién entra y qué ve sin reportes =====================
  j := public.geoportal_redes_levantar_mios(op);
  perform pg_temp.reg('01.01 sin reportes: la lista vacía, con el periodo por omisión (30 días), total 0 y sin recorte',
    j = jsonb_build_object('dias', 30, 'total', 0, 'recortada', false, 'items', '[]'::jsonb), j::text);
  perform pg_temp.err('01.02 el operador de Técnica sin el formulario no entra (como en «Encontrar»)', format('select public.geoportal_redes_levantar_mios(%L)', op3), '42501', 'formulario');
  perform pg_temp.err('01.03 quien no es de Técnica ni tiene Formularios de campo no entra', format('select public.geoportal_redes_levantar_mios(%L)', na), '42501');
  perform pg_temp.err('01.04 sin solicitante no entra', 'select public.geoportal_redes_levantar_mios(null)', '28000');
  perform pg_temp.err('01.05 un periodo que no es 30, 90 ni 0 se rechaza', format('select public.geoportal_redes_levantar_mios(%L, 7)', op), '22023', '30 días');
  perform pg_temp.err('01.06 … y uno negativo también', format('select public.geoportal_redes_levantar_mios(%L, -1)', op), '22023');
  perform pg_temp.reg('01.07 todos los que pueden reportar entran: administrador, supervisor de distribución, operador con el formulario y Comercial',
    (public.geoportal_redes_levantar_mios(a) ->> 'total')::integer = 0 and (public.geoportal_redes_levantar_mios(sd) ->> 'total')::integer = 0
    and (public.geoportal_redes_levantar_mios(co) ->> 'total')::integer = 0 and (public.geoportal_redes_levantar_mios(op2, null) ->> 'dias')::integer = 30);

  -- ===================== 02. Solo lo propio, los últimos primero =====================
  v_l1 := pg_temp.punto(op, 0, 1000);
  v_l2 := pg_temp.punto(op, 100, 1000, 'alcantarillado', 'pozo');
  v_o1 := pg_temp.punto(op2, 200, 1000);
  v_c1 := pg_temp.punto(co, 300, 1000);
  v_l3 := pg_temp.punto(op, 400, 1000, 'acueducto', 'hidrante');
  j := public.geoportal_redes_levantar_mios(op, 30);
  perform pg_temp.reg('02.01 el operador ve sus 3 reportes y ninguno ajeno, los últimos primero',
    (j ->> 'total')::integer = 3 and not (j ->> 'recortada')::boolean and jsonb_array_length(j -> 'items') = 3
    and (select string_agg(i ->> 'codigo', ',' order by o) from jsonb_array_elements(j -> 'items') with ordinality x(i, o)) = v_l3 || ',' || v_l2 || ',' || v_l1, j::text);
  perform pg_temp.reg('02.02 cada uno trae exactamente las 9 claves del contrato (ni correos, ni nombres, ni posición, ni fotos, ni motivos)',
    (select bool_and((select string_agg(k, ',' order by k) from jsonb_object_keys(i) k) = 'activo,codigo,estado,estado_desde,estado_nombre,registrado_en,servicio,tipo,tipo_nombre')
       from jsonb_array_elements(j -> 'items') i) and position('@' in j::text) = 0 and position('ZTMIOS' in j::text) = 0, j -> 'items' -> 0 #>> '{}');
  perform pg_temp.reg('02.03 recién reportado: «Reportado», con el nombre del tipo, el servicio, desde cuándo (su fecha de registro) y sin activo',
    j -> 'items' -> 1 ->> 'codigo' = v_l2 and j -> 'items' -> 1 ->> 'servicio' = 'alcantarillado' and j -> 'items' -> 1 ->> 'tipo' = 'pozo'
    and j -> 'items' -> 1 ->> 'tipo_nombre' = redes.f_levantar_tipo_nombre('pozo') and j -> 'items' -> 1 ->> 'estado' = 'reportado' and j -> 'items' -> 1 ->> 'estado_nombre' = 'Reportado'
    and (j -> 'items' -> 1 ->> 'estado_desde')::timestamptz = (j -> 'items' -> 1 ->> 'registrado_en')::timestamptz and j -> 'items' -> 1 -> 'activo' = 'null'::jsonb
    and (j -> 'items' -> 1 ->> 'registrado_en')::timestamptz = (select registrado_en from redes.levantar_puntos where codigo = v_l2), j -> 'items' -> 1 #>> '{}');
  perform pg_temp.reg('02.04 el otro operador ve solo el suyo, y Comercial solo el suyo',
    (select string_agg(i ->> 'codigo', ',') from jsonb_array_elements(public.geoportal_redes_levantar_mios(op2) -> 'items') i) = v_o1
    and (select string_agg(i ->> 'codigo', ',') from jsonb_array_elements(public.geoportal_redes_levantar_mios(co) -> 'items') i) = v_c1);
  perform pg_temp.reg('02.05 el supervisor que no ha reportado nada ve su lista vacía (los de todos siguen en su bandeja: levantar_lista)',
    (public.geoportal_redes_levantar_mios(sd, 0) ->> 'total')::integer = 0 and (public.geoportal_redes_levantar_lista(sd, 'todos') -> 'items') @> jsonb_build_array(jsonb_build_object('codigo', v_o1)));
  perform pg_temp.reg('02.06 el correo en mayúsculas y con espacios es la misma persona', (public.geoportal_redes_levantar_mios('  ' || upper(op) || ' ') ->> 'total')::integer = 3);
  perform pg_temp.err('02.07 la bandeja del supervisor sigue cerrada para el operador (no se abrió nada más)', format('select public.geoportal_redes_levantar_lista(%L)', op), '42501');

  -- ===================== 03. El estado de hoy =====================
  perform public.geoportal_redes_levantar_evento(sd, v_l1, 'asignado', null, null, '127.0.0.1');
  perform public.geoportal_redes_levantar_evento(sd, v_l2, 'descartado', null, 'ZTMIOS repetido de otro reporte', '127.0.0.1');
  -- un activo nuevo para marcar «levantado»
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'HID' returning ultimo into v_cons;
  v_val := 'HID-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_val, 'HID', 'carga', a) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, estado_codigo, atributos, huella, autor)
  values (v_id, 1, ST_SetSRID(ST_MakePoint(pg_temp.lon(400), pg_temp.lat(1000)), 4326), 'ZTMIOS hidrante', 'en_operacion', '{}'::jsonb, md5(v_val), a);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZTMIOS activo de prueba', a);
  perform redes.f_mat_refrescar_uno(v_id);
  perform public.geoportal_redes_levantar_evento(sd, v_l3, 'levantado', v_val, null, '127.0.0.1');
  j := public.geoportal_redes_levantar_mios(op, 30);
  perform pg_temp.reg('03.01 el que el supervisor asignó dice «Asignado a levantamiento», desde ese momento',
    (select i ->> 'estado' = 'asignado' and i ->> 'estado_nombre' = 'Asignado a levantamiento' and (i ->> 'estado_desde')::timestamptz > (i ->> 'registrado_en')::timestamptz
       from jsonb_array_elements(j -> 'items') i where i ->> 'codigo' = v_l1), j::text);
  perform pg_temp.reg('03.02 el descartado dice «Descartado» y NO trae el motivo ni quién lo descartó',
    (select i ->> 'estado' = 'descartado' and i ->> 'estado_nombre' = 'Descartado' from jsonb_array_elements(j -> 'items') i where i ->> 'codigo' = v_l2)
    and position('repetido' in j::text) = 0 and position('@' in j::text) = 0);
  perform pg_temp.reg('03.03 el levantado dice «Levantado» y trae el código del activo nuevo',
    (select i ->> 'estado' = 'levantado' and i ->> 'estado_nombre' = 'Levantado' and i ->> 'activo' = v_val from jsonb_array_elements(j -> 'items') i where i ->> 'codigo' = v_l3), j::text);
  perform public.geoportal_redes_levantar_evento(sd, v_l2, 'reabierto', null, 'ZTMIOS no era repetido', '127.0.0.1');
  j := public.geoportal_redes_levantar_mios(op, 30);
  perform pg_temp.reg('03.04 el reabierto vuelve a «Reportado»; el orden sigue siendo por fecha de registro (no por el último cambio)',
    (select i ->> 'estado' = 'reportado' and i ->> 'estado_nombre' = 'Reportado' from jsonb_array_elements(j -> 'items') i where i ->> 'codigo' = v_l2)
    and (select string_agg(i ->> 'codigo', ',' order by o) from jsonb_array_elements(j -> 'items') with ordinality x(i, o)) = v_l3 || ',' || v_l2 || ',' || v_l1, j::text);
  perform pg_temp.reg('03.05 su propia acta sigue abriendo (la ruta publicada), y la de otro no',
    public.geoportal_redes_levantar_acta(op, v_l1, '127.0.0.1') ->> 'codigo' = v_l1);
  perform pg_temp.err('03.06 … el acta de un reporte ajeno se le niega', format('select public.geoportal_redes_levantar_acta(%L, %L, %L)', op, v_o1, '127.0.0.1'), '42501');

  -- ===================== 04. Periodos: 30 días, 90 días y todos =====================
  perform pg_temp.viejo('LEV-980001', op, 29.9, 0);        -- dentro de los 30 días
  perform pg_temp.viejo('LEV-980002', op, 30.1, 10);       -- fuera de 30, dentro de 90
  perform pg_temp.viejo('LEV-980003', op, 89.9, 20);
  perform pg_temp.viejo('LEV-980004', op, 90.1, 30);       -- solo en «todos»
  perform pg_temp.viejo('LEV-980005', op, 400, 40);
  perform pg_temp.viejo('LEV-980006', op2, 5, 50);         -- ajeno
  j := public.geoportal_redes_levantar_mios(op, 30); j2 := public.geoportal_redes_levantar_mios(op, 90);
  perform pg_temp.reg('04.01 últimos 30 días: los 3 de hoy y el de hace 29,9 días (4); el de hace 30,1 no',
    (j ->> 'total')::integer = 4 and (j ->> 'dias')::integer = 30 and j -> 'items' -> 3 ->> 'codigo' = 'LEV-980001' and not (j -> 'items') @> '[{"codigo": "LEV-980002"}]'::jsonb, j::text);
  perform pg_temp.reg('04.02 últimos 90 días: 6 (entran los de 30,1 y 89,9 días; el de 90,1 no)',
    (j2 ->> 'total')::integer = 6 and (j2 ->> 'dias')::integer = 90 and j2 -> 'items' -> 5 ->> 'codigo' = 'LEV-980003' and not (j2 -> 'items') @> '[{"codigo": "LEV-980004"}]'::jsonb, j2::text);
  j := public.geoportal_redes_levantar_mios(op, 0);
  perform pg_temp.reg('04.03 todos (0): los 8 suyos, del más nuevo al más viejo, y nunca el ajeno',
    (j ->> 'total')::integer = 8 and (j ->> 'dias')::integer = 0 and jsonb_array_length(j -> 'items') = 8 and j -> 'items' -> 7 ->> 'codigo' = 'LEV-980005'
    and not (j -> 'items') @> '[{"codigo": "LEV-980006"}]'::jsonb
    and (select bool_and(f >= sig) from (select (i ->> 'registrado_en')::timestamptz as f, lead((i ->> 'registrado_en')::timestamptz) over (order by o) as sig
                                           from jsonb_array_elements(j -> 'items') with ordinality x(i, o)) q where sig is not null), j::text);

  -- ===================== 05. Recorte, volumen y tiempos =====================
  -- 600 puntos más del operador (dos con la misma fecha, para el desempate por código) y 20.000 de otras personas
  insert into redes.levantar_puntos (id, codigo, servicio, tipo, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en)
  select gen_random_uuid(), 'LEV-97' || lpad(i::text, 4, '0'), 'acueducto', 'valvula', pg_temp.lat(2000), pg_temp.lon(i), ST_SetSRID(ST_MakePoint(pg_temp.lon(i), pg_temp.lat(2000)), 4326), 5, false, 'tecnica', op,
         date_trunc('second', clock_timestamp()) - interval '2 days' - make_interval(mins => (i / 2) * 2)
    from generate_series(1, 600) i;
  insert into redes.levantar_puntos (id, codigo, servicio, tipo, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en)
  select gen_random_uuid(), 'LEV-' || lpad((700000 + i)::text, 6, '0'), 'acueducto', 'valvula', pg_temp.lat(3000 + i % 500), pg_temp.lon(i % 4000), ST_SetSRID(ST_MakePoint(pg_temp.lon(i % 4000), pg_temp.lat(3000 + i % 500)), 4326), 5, false,
         'tecnica', 'prueba.redesmios.relleno' || (i % 200) || '@emdupar.gov.co', clock_timestamp() - make_interval(mins => i)
    from generate_series(1, 20000) i;
  insert into redes.levantar_eventos (punto_id, tipo, autor) select p.id, 'asignado', sd from redes.levantar_puntos p where p.codigo like 'LEV-97%' or p.codigo like 'LEV-7%';
  analyze redes.levantar_puntos; analyze redes.levantar_eventos;
  select count(*) into v_n from redes.levantar_puntos;
  select count(*) into v_aud from public.geoportal_auditoria; select count(*) into v_xmax from redes.levantar_eventos;      -- desde aquí solo se lee
  v_t0 := clock_timestamp(); j := public.geoportal_redes_levantar_mios(op, 0); v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp(); j2 := public.geoportal_redes_levantar_mios(op, 30); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_levantar_mios(co, 30); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_info := format('TIEMPOS (con %s puntos en la tabla): mis 608 reportes, todos %s ms · los de 30 días %s ms · alguien con 1 reporte %s ms', v_n, v_ms, v_ms2, v_ms3);
  perform pg_temp.reg('05.01 con 608 reportes propios: «total» dice 608, «recortada» es verdadero y salen los 500 más nuevos',
    (j ->> 'total')::integer = 608 and (j ->> 'recortada')::boolean and jsonb_array_length(j -> 'items') = 500 and j -> 'items' -> 0 ->> 'codigo' = v_l3
    and not (j -> 'items') @> '[{"codigo": "LEV-980005"}]'::jsonb, format('total %s, items %s', j ->> 'total', jsonb_array_length(j -> 'items')));
  perform pg_temp.reg('05.02 orden estable: por fecha y, con la misma fecha, por código (los dos de la misma fecha salen juntos, el de código mayor primero)',
    (select bool_and(f > sig or (f = sig and c > csig)) from (select (i ->> 'registrado_en')::timestamptz as f, i ->> 'codigo' as c, lead((i ->> 'registrado_en')::timestamptz) over (order by o) as sig,
        lead(i ->> 'codigo') over (order by o) as csig from jsonb_array_elements(j -> 'items') with ordinality x(i, o)) q where sig is not null)
    and (select count(*) from (select (i ->> 'registrado_en') as f from jsonb_array_elements(j -> 'items') i group by 1 having count(*) = 2) d) > 100);
  perform pg_temp.reg('05.03 los de 30 días: los 604 recientes (total) y 500 en la respuesta, todos con su estado de hoy («Asignado a levantamiento» en los de relleno)',
    (j2 ->> 'total')::integer = 604 and (j2 ->> 'recortada')::boolean and (select count(*) from jsonb_array_elements(j2 -> 'items') i where i ->> 'estado' = 'asignado') >= 497, j2 ->> 'total');
  perform pg_temp.reg('05.04 TIEMPOS: con más de 20.000 puntos en la tabla, cada lectura en menos de 1 s', greatest(v_ms, v_ms2, v_ms3) < 1000 and v_n > 20000, v_info);
  perform pg_temp.reg('05.05 leer no escribe: ni una fila de auditoría, ni un punto, ni un evento de más',
    (select count(*) from public.geoportal_auditoria) = v_aud and (select count(*) from redes.levantar_puntos) = v_n and (select count(*) from redes.levantar_eventos) = v_xmax,
    format('auditoría %s → %s', v_aud, (select count(*) from public.geoportal_auditoria)));
  perform pg_temp.reg('05.06 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));
  perform pg_temp.reg('05.07 la función es de solo lectura (STABLE), security definer, y solo la ejecuta service_role',
    (select p.provolatile = 's' and p.prosecdef and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
            and not has_function_privilege('authenticated', p.oid, 'execute') from pg_proc p where p.oid = 'public.geoportal_redes_levantar_mios(text,integer)'::regprocedure));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · «Mis reportes» (levantar_mios) (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
