-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes14.*), sus activos de prueba (ZT14, en un rincón de la caja de Valledupar, lejos de
-- la red), sus fotos de prueba en storage.objects y sus puntos por levantar. Mide con el volumen real: busca los cercanos en el lugar con más activos de la
-- base donde corre y FALLA si pasa de 1 s. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 14 … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.activo(p_nombre text, p_prefijo text, p_geom geometry) returns text language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes14.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZT14 ' || p_nombre, null, null,
          case when p_prefijo in ('RED', 'COL') then (select codigo from redes.materiales order by orden limit 1) end, case when p_prefijo in ('RED', 'COL') then 110 end,
          'en_operacion', '{}'::jsonb, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT14 activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_cod;
end $$;
create function pg_temp.foto(p_ruta text, p_bytes bigint default 200000, p_mime text default 'image/jpeg') returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', p_bytes, 'mimetype', p_mime)) $$;
-- prepara, «sube» las fotos y crea un punto por levantar; devuelve la respuesta de crear
create function pg_temp.punto(p_quien text, p_x numeric, p_y numeric, p_prec numeric, p_extra jsonb default '{}'::jsonb, p_fotos integer default 1) returns jsonb language plpgsql as $$
declare j jsonb; f jsonb;
begin
  j := public.geoportal_redes_levantar_preparar(p_quien, p_fotos);
  for f in select e from jsonb_array_elements(j -> 'fotos') e loop perform pg_temp.foto(f ->> 'ruta'); end loop;
  return public.geoportal_redes_levantar_crear(p_quien, (j ->> 'punto_id')::uuid,
    jsonb_build_object('servicio', 'acueducto', 'tipo', 'valvula', 'lat', pg_temp.lat(p_y), 'lon', pg_temp.lon(p_x), 'precision_m', p_prec, 'fotos', j -> 'fotos') || p_extra, '127.0.0.1')
    || jsonb_build_object('_id', j ->> 'punto_id', '_fotos', j -> 'fotos');
end $$;

do $prueba$
declare
  a text := 'prueba.redes14.adm@emdupar.gov.co'; sd text := 'prueba.redes14.sd@emdupar.gov.co'; op text := 'prueba.redes14.op@emdupar.gov.co'; op2 text := 'prueba.redes14.op2@emdupar.gov.co';
  pl text := 'prueba.redes14.pl@emdupar.gov.co'; co text := 'prueba.redes14.co@emdupar.gov.co'; na text := 'prueba.redes14.nada@emdupar.gov.co';
  j jsonb; j2 jsonb; v_val text; v_red text; v_col text; v_lev text; v_lev2 text; v_id uuid; v_n integer; v_n2 integer;
  v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_ms4 numeric; v_lat numeric; v_lon numeric; v_info text; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT14 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT14 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT14 Operador con formulario', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op2, 'ZT14 Operador sin formulario', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (pl, 'ZT14 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values (co, 'ZT14 Operario de Comercial', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_comercial, horario, dias) values (na, 'ZT14 Sin permiso', 'consulta', true, 'sin_restriccion', 'todos');
  -- activos de prueba: una válvula en (0, 0), un tramo de acueducto que pasa a 8 m, un colector a 5 m y otro tramo lejos (60 m)
  v_val := pg_temp.activo('válvula', 'VAL', pg_temp.pt(0, 0));
  v_red := pg_temp.activo('tramo', 'RED', ST_MakeLine(pg_temp.pt(-100, 8), pg_temp.pt(100, 8)));
  v_col := pg_temp.activo('colector', 'COL', ST_MakeLine(pg_temp.pt(-100, -5), pg_temp.pt(100, -5)));
  perform pg_temp.activo('tramo lejano', 'RED', ST_MakeLine(pg_temp.pt(-100, 60), pg_temp.pt(100, 60)));

  -- ===================== 01. Quién entra =====================
  -- el formulario se asigna en Personal de distribución, con la RPC de siempre
  j := public.geoportal_redes_personal_formulario(sd, op, 'activo_campo', true, 'ZT14 sale a campo a levantar activos', '127.0.0.1');
  perform pg_temp.reg('01.01 el supervisor de distribución asigna «Encontrar o reportar activo» en Personal (la RPC de siempre)', (j ->> 'asignado')::boolean and j ->> 'nombre' = 'Encontrar o reportar activo', j::text);
  perform pg_temp.reg('01.02 … y Personal de distribución lo lista entre los formularios y en la persona',
    (select count(*) from jsonb_array_elements(public.geoportal_redes_personal(sd, 'zt14', 'todas') -> 'formularios') f where f ->> 'clave' = 'activo_campo') = 1
    and (select p -> 'formularios' ? 'activo_campo' from jsonb_array_elements(public.geoportal_redes_personal(sd, 'zt14', 'todas') -> 'personas') p where p ->> 'email' = op));
  perform pg_temp.reg('01.03 perfiles: administrador, supervisor de distribución, operador con el formulario, supervisor de planta y Comercial',
    (select perfil || '/' || area from redes.f_levantar_acceso(a)) = 'admin/tecnica' and (select perfil || '/' || area from redes.f_levantar_acceso(sd)) = 'supervisor/tecnica'
    and (select perfil || '/' || area from redes.f_levantar_acceso(op)) = 'operador/tecnica' and (select perfil || '/' || area from redes.f_levantar_acceso(pl)) = 'operador/tecnica'
    and (select perfil || '/' || area from redes.f_levantar_acceso(co)) = 'comercial/comercial');
  perform pg_temp.err('01.04 el operador de Técnica sin el formulario no entra', format('select public.geoportal_redes_levantar_inicio(%L)', op2), '42501', 'formulario');
  perform pg_temp.err('01.05 quien no es de Técnica ni tiene Formularios de campo no entra', format('select public.geoportal_redes_levantar_cerca(%L, %s, %s, 5, %L)', na, pg_temp.lat(0), pg_temp.lon(0), 'acueducto'), '42501');
  perform pg_temp.reg('01.06 el perfil de redes dice quién tiene la tarjeta (sí con el formulario, no sin él)',
    (public.geoportal_redes_mi_perfil(op) ->> 'activo_campo')::boolean and not (public.geoportal_redes_mi_perfil(op2) ->> 'activo_campo')::boolean
    and (public.geoportal_redes_mi_perfil(sd) ->> 'activo_campo')::boolean and public.geoportal_redes_mi_perfil(op) ? 'ficha_buscar');
  j := public.geoportal_redes_levantar_inicio(co);
  perform pg_temp.reg('01.07 al abrir: los parámetros (15, 30 y 10 m), 6 tipos, 2 servicios y de 1 a 3 fotos; Comercial no abre la ficha de Técnica',
    (j ->> 'radio_min_m')::numeric = redes.f_param('levantar_radio_min_m') and (j ->> 'radio_max_m')::numeric = redes.f_param('levantar_radio_max_m') and (j ->> 'duplicado_m')::numeric = redes.f_param('levantar_duplicado_m')
    and jsonb_array_length(j -> 'tipos') = 6 and jsonb_array_length(j -> 'servicios') = 2 and j ->> 'max_fotos' = '3' and not (j ->> 'ficha_completa')::boolean
    and (public.geoportal_redes_levantar_inicio(op) ->> 'ficha_completa')::boolean, j::text);

  -- ===================== 02. Encontrar =====================
  j := public.geoportal_redes_levantar_cerca(co, pg_temp.lat(0), pg_temp.lon(0), 5, 'acueducto');
  perform pg_temp.reg('02.01 con buena señal (5 m) el radio es el mínimo y salen la válvula (a 0 m) y el tramo (a 8 m), en ese orden y numerados',
    (j ->> 'radio_m')::numeric = redes.f_param('levantar_radio_min_m') and not (j ->> 'senal_debil')::boolean and (j ->> 'total')::integer = 2
    and j -> 'activos' -> 0 ->> 'codigo' = v_val and j -> 'activos' -> 0 ->> 'n' = '1' and (j -> 'activos' -> 0 ->> 'distancia_m')::numeric = 0 and j -> 'activos' -> 0 ->> 'forma' = 'punto'
    and j -> 'activos' -> 1 ->> 'codigo' = v_red and (j -> 'activos' -> 1 ->> 'distancia_m')::numeric between 7.5 and 8.5 and j -> 'activos' -> 1 ->> 'forma' = 'linea'
    and j -> 'activos' -> 1 ->> 'diametro_mm' = '110' and j -> 'activos' -> 1 ->> 'material' is not null and j -> 'activos' -> 1 ->> 'tipo' is not null, left(j::text, 600));
  perform pg_temp.reg('02.02 cada activo trae su dibujo (el tramo, recortado alrededor de la persona) y el punto donde va su número',
    j -> 'activos' -> 0 -> 'geometria' ->> 'type' = 'Point' and j -> 'activos' -> 1 -> 'geometria' ->> 'type' in ('LineString', 'MultiLineString')
    and ST_Length(ST_GeomFromGeoJSON(j -> 'activos' -> 1 ->> 'geometria')::geography) < 2 * 4 * redes.f_param('levantar_radio_max_m') + 1
    and abs((j -> 'activos' -> 1 ->> 'lat')::numeric - pg_temp.lat(8)) < 0.00002, left(j -> 'activos' -> 1 ->> 'geometria', 200));
  j := public.geoportal_redes_levantar_cerca(op, pg_temp.lat(0), pg_temp.lon(0), 22, 'alcantarillado');
  perform pg_temp.reg('02.03 el filtro por servicio: en alcantarillado solo sale el colector; con precisión de 22 m el radio es 22 m',
    (j ->> 'radio_m')::numeric = 22 and (j ->> 'total')::integer = 1 and j -> 'activos' -> 0 ->> 'codigo' = v_col, left(j::text, 300));
  j := public.geoportal_redes_levantar_cerca(op, pg_temp.lat(0), pg_temp.lon(0), 80, 'acueducto');
  perform pg_temp.reg('02.04 con señal débil (80 m) el radio se queda en el tope (30 m), avisa «señal débil» y el tramo de 60 m no entra',
    (j ->> 'radio_m')::numeric = redes.f_param('levantar_radio_max_m') and (j ->> 'senal_debil')::boolean and (j ->> 'total')::integer = 2, left(j::text, 200));
  perform pg_temp.err('02.05 una posición fuera de Valledupar se rechaza', format('select public.geoportal_redes_levantar_cerca(%L, 4.6, -74.08, 5, %L)', op, 'acueducto'), '22023', 'fuera de Valledupar');
  perform pg_temp.err('02.06 un servicio que no existe se rechaza', format('select public.geoportal_redes_levantar_cerca(%L, %s, %s, 5, %L)', op, pg_temp.lat(0), pg_temp.lon(0), 'tecnologia'), '22023');
  j := public.geoportal_redes_levantar_ficha(co, v_red);
  perform pg_temp.reg('02.07 la ficha corta (solo lectura) para Comercial: tipo, material, diámetro, longitud y estado; sin la ficha de Técnica',
    j ->> 'codigo' = v_red and j ->> 'diametro_mm' = '110' and j ->> 'material' is not null and (j ->> 'longitud_m')::numeric > 150 and j ->> 'estado' = 'En operación'
    and not (j ->> 'ficha_completa')::boolean and (public.geoportal_redes_levantar_ficha(sd, v_val) ->> 'ficha_completa')::boolean, j::text);
  perform pg_temp.err('02.08 la ficha de un activo que no existe: no encontrado', format('select public.geoportal_redes_levantar_ficha(%L, %L)', co, 'RED-99999999'), 'P0002');
  perform pg_temp.err('02.09 … y Comercial no entra a la ficha de Técnica (sigue cerrada)', format('select public.geoportal_redes_activo(%L, %L)', co, v_red), '42501');

  -- ===================== 03. Reportar activo =====================
  perform pg_temp.err('03.01 sin fotos no se prepara', format('select public.geoportal_redes_levantar_preparar(%L, 0)', co), '22023', 'de 1 a 3 fotos');
  perform pg_temp.err('03.02 con más de 3 fotos tampoco', format('select public.geoportal_redes_levantar_preparar(%L, 4)', co), '22023', 'de 1 a 3 fotos');
  j := public.geoportal_redes_levantar_preparar(co, 2);
  v_id := (j ->> 'punto_id')::uuid;
  perform pg_temp.reg('03.03 preparar: el identificador y las rutas de las fotos (levantar/AAAA-MM/<id>/<n>.jpg)',
    jsonb_array_length(j -> 'fotos') = 2 and j -> 'fotos' -> 1 ->> 'ruta' ~ ('^levantar/[0-9]{4}-[0-9]{2}/' || v_id || '/2\.jpg$') and j ->> 'tipo_mime' = 'image/jpeg', j::text);
  perform pg_temp.err('03.04 si la foto no llegó a Storage, no se crea', format('select public.geoportal_redes_levantar_crear(%L, %L, %L)', co, v_id,
    jsonb_build_object('servicio', 'acueducto', 'tipo', 'hidrante', 'lat', pg_temp.lat(200), 'lon', pg_temp.lon(200), 'precision_m', 6, 'fotos', j -> 'fotos')), '22023', 'No se encontró la foto');
  perform pg_temp.foto(j -> 'fotos' -> 0 ->> 'ruta'); perform pg_temp.foto(j -> 'fotos' -> 1 ->> 'ruta');
  perform pg_temp.err('03.05 «otro» exige decir qué es en la observación', format('select public.geoportal_redes_levantar_crear(%L, %L, %L)', co, v_id,
    jsonb_build_object('servicio', 'acueducto', 'tipo', 'otro', 'lat', pg_temp.lat(200), 'lon', pg_temp.lon(200), 'precision_m', 6, 'fotos', j -> 'fotos')), '22023', 'observación');
  perform pg_temp.err('03.06 sin la precisión del GPS no se crea', format('select public.geoportal_redes_levantar_crear(%L, %L, %L)', co, v_id,
    jsonb_build_object('servicio', 'acueducto', 'tipo', 'hidrante', 'lat', pg_temp.lat(200), 'lon', pg_temp.lon(200), 'fotos', j -> 'fotos')), '22023', 'precisión del GPS');
  perform pg_temp.err('03.07 otra persona no puede usar la subida preparada', format('select public.geoportal_redes_levantar_crear(%L, %L, %L)', op, v_id,
    jsonb_build_object('servicio', 'acueducto', 'tipo', 'hidrante', 'lat', pg_temp.lat(200), 'lon', pg_temp.lon(200), 'precision_m', 6, 'fotos', j -> 'fotos')), '22023', 'prepararse');
  j2 := public.geoportal_redes_levantar_crear(co, v_id, jsonb_build_object('servicio', 'acueducto', 'tipo', 'hidrante', 'observacion', '  ZT14 hidrante frente a la tienda  ',
          'lat', pg_temp.lat(200), 'lon', pg_temp.lon(200), 'precision_m', 6, 'fotos', j -> 'fotos'), '127.0.0.1');
  v_lev := j2 ->> 'codigo';
  perform pg_temp.reg('03.08 se crea: código LEV-, estado «reportado», sin «precisión baja», con sus 2 fotos, la observación limpia y el área de quien reporta (Comercial)',
    (j2 ->> 'creado')::boolean and v_lev ~ '^LEV-[0-9]{6}$' and j2 ->> 'estado' = 'reportado' and not (j2 ->> 'precision_baja')::boolean
    and (select p.area = 'comercial' and p.observacion = 'ZT14 hidrante frente a la tienda' and p.precision_m = 6 and p.autor = co and p.fotos = 2 and p.estado = 'reportado'
           from redes.v_levantar_punto p where p.codigo = v_lev), j2::text);
  j2 := public.geoportal_redes_levantar_crear(co, v_id, jsonb_build_object('servicio', 'acueducto', 'tipo', 'hidrante', 'lat', pg_temp.lat(200), 'lon', pg_temp.lon(200), 'precision_m', 6, 'fotos', j -> 'fotos'));
  perform pg_temp.reg('03.09 reenviar el mismo reporte (sin señal) no lo duplica: devuelve el que ya quedó', (j2 ->> 'repetido')::boolean and j2 ->> 'codigo' = v_lev
    and (select count(*) from redes.levantar_puntos where id = v_id) = 1, j2::text);
  j := pg_temp.punto(op, 400, 400, 45, jsonb_build_object('tipo', 'pozo', 'servicio', 'alcantarillado'));
  perform pg_temp.reg('03.10 con señal débil (45 m) igual se guarda, marcado «precisión baja», y queda con el área Técnica',
    (j ->> 'creado')::boolean and (j ->> 'precision_baja')::boolean and (select p.precision_baja and p.area = 'tecnica' and p.servicio = 'alcantarillado' from redes.levantar_puntos p where p.codigo = j ->> 'codigo'), j::text);
  perform pg_temp.reg('03.11 cada reporte queda en la auditoría (sin la posición)',
    (select count(*) from public.geoportal_auditoria where accion = 'redes_levantar_crear' and referencia in (v_lev, j ->> 'codigo') and not detalle ? 'lat') = 2);

  -- ===================== 04. Duplicados =====================
  j := pg_temp.punto(op, 204, 203, 5);      -- a 5 m del hidrante ya reportado
  perform pg_temp.reg('04.01 a 5 m de un punto por levantar NO se crea otro: se muestra el que ya hay, con su fecha',
    not (j ->> 'creado')::boolean and j -> 'duplicados' -> 0 ->> 'codigo' = v_lev and (j -> 'duplicados' -> 0 ->> 'distancia_m')::numeric between 4 and 6
    and j -> 'duplicados' -> 0 ->> 'registrado_en' is not null and not exists (select 1 from redes.levantar_puntos where id = (j ->> '_id')::uuid), j::text);
  j2 := public.geoportal_redes_levantar_crear(op, (j ->> '_id')::uuid, jsonb_build_object('servicio', 'acueducto', 'tipo', 'valvula', 'lat', pg_temp.lat(203), 'lon', pg_temp.lon(204),
          'precision_m', 5, 'fotos', j -> '_fotos', 'no_es_duplicado', true));
  v_lev2 := j2 ->> 'codigo';
  perform pg_temp.reg('04.02 si la persona dice que no es el mismo, se crea', (j2 ->> 'creado')::boolean and v_lev2 <> v_lev, j2::text);
  j := public.geoportal_redes_levantar_cerca(co, pg_temp.lat(200), pg_temp.lon(200), 5, 'acueducto');
  perform pg_temp.reg('04.03 «Encontrar» muestra los puntos por levantar que ya hay ahí y marca los que están a menos de 10 m',
    jsonb_array_length(j -> 'puntos') = 2 and j -> 'puntos' -> 0 ->> 'codigo' = v_lev and (j -> 'puntos' -> 0 ->> 'posible_duplicado')::boolean
    and (j -> 'puntos' -> 1 ->> 'posible_duplicado')::boolean and (j ->> 'total')::integer = 0, j::text);
  j := pg_temp.punto(co, 200, 188, 5);      -- a 12 m del primero y a 15 m del segundo: ya no es duplicado
  perform pg_temp.reg('04.04 a 12 m ya no pregunta: se crea', (j ->> 'creado')::boolean, j::text);

  -- ===================== 05. La bandeja del supervisor y los estados =====================
  j := public.geoportal_redes_levantar_lista(sd, 'abiertos', null, 50);
  select count(*) into v_n from jsonb_array_elements(j -> 'items') i where i ->> 'codigo' in (v_lev, v_lev2);
  perform pg_temp.reg('05.01 la bandeja «Otros activos por levantamiento»: los puntos abiertos, con quién reportó (nombre del funcionario), fotos y precisión',
    v_n = 2 and (j ->> 'abiertos')::integer >= 4
    and (select i ->> 'quien' = 'ZT14 Operario de Comercial' and i ->> 'fotos' = '2' and i ->> 'area' = 'comercial' and i ->> 'estado_nombre' = 'Reportado' and i ->> 'tipo_nombre' = 'Hidrante'
           from jsonb_array_elements(j -> 'items') i where i ->> 'codigo' = v_lev), left(j::text, 500));
  perform pg_temp.err('05.02 el operador no ve la bandeja', format('select public.geoportal_redes_levantar_lista(%L)', op), '42501');
  perform pg_temp.err('05.03 … ni Comercial', format('select public.geoportal_redes_levantar_lista(%L)', co), '42501');
  j := public.geoportal_redes_levantar_evento(sd, v_lev, 'asignado', null, 'ZT14 cuadrilla de topografía, jueves', '127.0.0.1');
  perform pg_temp.reg('05.04 «asignado a levantamiento»', j ->> 'estado' = 'asignado' and j ->> 'estado_nombre' = 'Asignado a levantamiento', j::text);
  perform pg_temp.err('05.05 asignar dos veces se rechaza', format('select public.geoportal_redes_levantar_evento(%L, %L, %L, null, null)', sd, v_lev, 'asignado'), '55000');
  perform pg_temp.err('05.06 «levantado» exige el activo nuevo', format('select public.geoportal_redes_levantar_evento(%L, %L, %L, null, null)', sd, v_lev, 'levantado'), '22023', 'activo');
  perform pg_temp.err('05.07 … y que el activo exista en la red', format('select public.geoportal_redes_levantar_evento(%L, %L, %L, %L, null)', sd, v_lev, 'levantado', 'HID-99999999'), 'P0002');
  j := public.geoportal_redes_levantar_evento(sd, v_lev, 'levantado', lower(v_val), null, '127.0.0.1');
  perform pg_temp.reg('05.08 «levantado», vinculado al activo nuevo', j ->> 'estado' = 'levantado' and j ->> 'activo' = v_val
    and (select i ->> 'activo' = v_val from jsonb_array_elements(public.geoportal_redes_levantar_lista(sd, 'levantado') -> 'items') i where i ->> 'codigo' = v_lev), j::text);
  perform pg_temp.err('05.09 un punto levantado no se descarta sin reabrirlo', format('select public.geoportal_redes_levantar_evento(%L, %L, %L, null, %L)', sd, v_lev, 'descartado', 'ZT14 motivo de sobra largo'), '55000');
  perform pg_temp.err('05.10 reabrir exige motivo', format('select public.geoportal_redes_levantar_evento(%L, %L, %L, null, %L)', sd, v_lev, 'reabierto', 'corto'), '22023', 'motivo');
  j := public.geoportal_redes_levantar_evento(a, v_lev, 'reabierto', null, 'ZT14 se vinculó al activo equivocado');
  perform pg_temp.reg('05.11 reabrir lo devuelve a «reportado» (queda el historial: nada se borra)', j ->> 'estado' = 'reportado'
    and (select count(*) from redes.levantar_eventos e join redes.levantar_puntos p on p.id = e.punto_id where p.codigo = v_lev) = 3, j::text);
  perform pg_temp.err('05.12 descartar exige motivo', format('select public.geoportal_redes_levantar_evento(%L, %L, %L, null, null)', sd, v_lev2, 'descartado'), '22023', 'motivo');
  j := public.geoportal_redes_levantar_evento(sd, v_lev2, 'descartado', null, 'ZT14 es la misma válvula ya levantada');
  perform pg_temp.reg('05.13 «descartado», con motivo: sale de los abiertos y un descartado ya no cuenta como duplicado',
    j ->> 'estado' = 'descartado' and not exists (select 1 from jsonb_array_elements(public.geoportal_redes_levantar_lista(sd, 'abiertos') -> 'items') i where i ->> 'codigo' = v_lev2)
    and (public.geoportal_redes_levantar_lista(sd, 'descartado') -> 'conteos' ->> 'descartado')::integer >= 1
    and not exists (select 1 from jsonb_array_elements(public.geoportal_redes_levantar_cerca(co, pg_temp.lat(203), pg_temp.lon(204), 5, 'acueducto') -> 'puntos') x where x ->> 'codigo' = v_lev2), j::text);
  perform pg_temp.err('05.14 el operador no cambia estados', format('select public.geoportal_redes_levantar_evento(%L, %L, %L, null, null)', op, v_lev, 'asignado'), '42501');
  perform pg_temp.err('05.15 los puntos no se modifican (solo inserción)', format('update redes.levantar_puntos set observacion = %L where codigo = %L', 'ZT14 cambiado', v_lev), '42501');
  perform pg_temp.err('05.16 … ni se borran sus eventos', 'delete from redes.levantar_eventos where true', '42501');
  j := public.geoportal_redes_levantar_fotos(sd, v_lev, '127.0.0.1');
  perform pg_temp.reg('05.17 el supervisor pide las fotos (la Edge firma la lectura) y la lectura queda en la auditoría',
    jsonb_array_length(j -> 'fotos') = 2 and j -> 'fotos' -> 0 ->> 'ruta' like 'levantar/%/1.jpg'
    and exists (select 1 from public.geoportal_auditoria where accion = 'redes_levantar_fotos' and referencia = v_lev and email = sd), j::text);
  perform pg_temp.err('05.18 Comercial no pide las fotos de la bandeja', format('select public.geoportal_redes_levantar_fotos(%L, %L)', co, v_lev), '42501');

  -- ===================== 06. El formulario asignable =====================
  j := public.geoportal_redes_personal_formulario(sd, op, 'activo_campo', false, 'ZT14 ya no sale a campo', '127.0.0.1');
  perform pg_temp.err('06.01 al quitarle el formulario en Personal, el operador deja de entrar', format('select public.geoportal_redes_levantar_inicio(%L)', op), '42501');
  perform pg_temp.reg('06.02 Personal de Comercial lista el formulario (grupo «Activos de la red») y conserva los que tenía',
    (select count(*) from campo.f_formularios_personal() x where x.clave = 'activo_campo' and x.nombre = 'Encontrar o reportar activo' and x.grupo = 'Activos de la red') = 1
    and (select count(*) from campo.f_formularios_personal() x where x.clave in ('reporte_general', 'acta')) = 2
    and (select max(x.orden) from campo.f_formularios_personal() x) = (select x.orden from campo.f_formularios_personal() x where x.clave = 'activo_campo'));
  insert into campo.personal_eventos (persona, tipo_evento, formulario, autor) values (co, 'asignar_formulario', 'activo_campo', a);
  perform pg_temp.reg('06.03 … y la asignación en Comercial se puede registrar (el CHECK admite la clave)', 'activo_campo' = any (campo.f_formularios_asignados(co)));
  perform pg_temp.err('06.04 el CHECK de Comercial sigue rechazando una clave cualquiera',
    format('insert into campo.personal_eventos (persona, tipo_evento, formulario, autor) values (%L, %L, %L, %L)', co, 'asignar_formulario', 'zt14_inventado', a), '23514');
  perform pg_temp.reg('06.05 en Comercial la asignación solo se registra: quien tiene Formularios de campo entra igual', (public.geoportal_redes_levantar_inicio(co) ->> 'perfil') = 'comercial');

  -- ===================== 07. Tiempos con el volumen real =====================
  -- el lugar con más activos de la base donde corre (celda de ~100 m); allí se buscan los cercanos con el radio máximo
  select c.lat, c.lon into v_lat, v_lon
    from (select round(avg(ST_Y(ST_PointOnSurface(m.geom)))::numeric, 6) as lat, round(avg(ST_X(ST_PointOnSurface(m.geom)))::numeric, 6) as lon, count(*) as n
            from redes.activo_vigente_mat m where m.sistema = 'acueducto' and not m.retirado and not m.oculto and m.codigo not in (v_val, v_red)
           group by round(ST_Y(ST_PointOnSurface(m.geom))::numeric, 3), round(ST_X(ST_PointOnSurface(m.geom))::numeric, 3) order by 3 desc limit 1) c;
  if v_lat is null then v_lat := pg_temp.lat(0); v_lon := pg_temp.lon(0); end if;
  select count(*) into v_n from redes.activo_vigente_mat where not retirado;
  v_t0 := clock_timestamp(); j := public.geoportal_redes_levantar_cerca(co, v_lat, v_lon, 30, 'acueducto'); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); j2 := public.geoportal_redes_levantar_cerca(co, v_lat, v_lon, 5, 'alcantarillado'); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_levantar_lista(sd, 'todos', null, 200); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform pg_temp.punto(co, 900, 900, 8); v_ms4 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS con %s activos vigentes en esta base: cercanos en el lugar más cargado (%s, %s; radio 30 m; %s activos, %s kB) %s ms · cercanos de alcantarillado (15 m; %s activos) %s ms · bandeja del supervisor %s ms · preparar y crear un punto %s ms',
                   v_n, v_lat, v_lon, j ->> 'total', round(length(j::text) / 1024.0), v_ms1, j2 ->> 'total', v_ms2, v_ms3, v_ms4);
  perform pg_temp.reg('07.01 TIEMPOS: buscar los cercanos, la bandeja y crear un punto, cada uno en menos de 1 s', greatest(v_ms1, v_ms2, v_ms3, v_ms4) < 1000, v_info);
  perform pg_temp.reg('07.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 14 (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
