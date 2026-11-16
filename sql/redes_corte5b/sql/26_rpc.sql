-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 26 — RPC NUEVAS DE PLANTA (las llama la Edge geoportal-tecnica en rutas nuevas)
-- PROPUESTA. No se ha ejecutado en la base real. security definer, search_path fijo, mensajes con HINT msg_usuario (tecnica.f_error); solo service_role.
--   · geoportal_tec_puntos_mapa: los puntos de muestreo activos con su ubicación vigente, para el minimapa de Muestreo (quien captura Muestreo).
--   · geoportal_tec_punto_ubicacion_proponer: «Guardar la ubicación de este punto» con el GPS (quien captura Muestreo). Queda pendiente.
--   · geoportal_tec_punto_ubicaciones: lo que revisa el supervisor en el Dashboard PTAP (pendientes, puntos y revisadas).
--   · geoportal_tec_punto_ubicacion_revisar: aprobar (agrega la ubicación verificada) o rechazar (con motivo). Nadie revisa lo que propuso.
-- Nada se actualiza ni se borra: todo es inserción con autor y hora.
-- =====================================================================

-- Minimapa de Muestreo. GeoJSON (FeatureCollection) de los puntos de muestreo ACTIVOS que tienen ubicación vigente; los que no la tienen van en «sin_ubicacion».
-- No trae autores ni nombres de personas: solo si hay una propuesta en revisión y si es de quien pregunta.
create function public.geoportal_tec_puntos_mapa(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'muestreo');
begin
  return jsonb_build_object(
    'type', 'FeatureCollection',
    'precision_max_m', redes.f_param('mue_gps_precision_max_m'),
    'features', coalesce((
      select jsonb_agg(jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(u.lon, u.lat)),
               'properties', jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'exactitud', u.exactitud, 'fuente', u.fuente,
                                                'en_revision', pr.id is not null, 'propuesta_mia', coalesce(pr.autor = v_email, false)))
             order by p.codigo)
        from tecnica.puntos p
        join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
        left join lateral (select x.id, x.autor from tecnica.v_punto_propuestas x where x.punto_id = p.id and x.estado = 'pendiente' order by x.id desc limit 1) pr on true
       where p.tipo = 'muestreo' and p.activo), '[]'::jsonb),
    'sin_ubicacion', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre,
                                          'en_revision', exists (select 1 from tecnica.v_punto_propuestas x where x.punto_id = p.id and x.estado = 'pendiente')) order by p.codigo)
        from tecnica.puntos p where p.tipo = 'muestreo' and p.activo and not exists (select 1 from redes.v_punto_ubicacion_vigente u where u.punto_id = p.id)), '[]'::jsonb));
end $f$;

-- «Guardar la ubicación de este punto». La propone quien captura Muestreo, parado en el punto, con el GPS del celular. Reglas:
--   · el punto existe, es de muestreo y está activo; su ubicación vigente NO está verificada (si lo está, se corrige desde el Dashboard o por archivo);
--   · la precisión del GPS es de mue_gps_precision_max_m metros o menos, y la posición cae en la caja de Valledupar (la misma del cargue de capas);
--   · una sola propuesta pendiente por punto: si la pendiente es de la misma persona, se devuelve esa (doble toque o reintento); si es de otra, se rechaza.
create function public.geoportal_tec_punto_ubicacion_proponer(p_solicitante text, p_punto text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_captura(p_solicitante, 'muestreo');
  p tecnica.puntos%rowtype; u record; pr record; v_max numeric := redes.f_param('mue_gps_precision_max_m'); v_id bigint; v_dist numeric;
  v_lat numeric := round(p_lat, 6); v_lon numeric := round(p_lon, 6);
begin
  if p_lat is null or p_lon is null or p_precision_m is null then perform tecnica.f_error('Falta la ubicación del GPS. Espere a que el celular la encuentre.'); end if;
  select * into p from tecnica.puntos where codigo = upper(btrim(coalesce(p_punto, ''))) and tipo = 'muestreo';
  if not found then perform tecnica.f_error('No existe ese punto de muestreo', 'P0002'); end if;
  if not p.activo then perform tecnica.f_error('Ese punto de muestreo está desactivado'); end if;
  if p_precision_m <= 0 or p_precision_m > 1000 then perform tecnica.f_error('La precisión del GPS no es válida'); end if;
  if p_precision_m > v_max then
    perform tecnica.f_error(format('El GPS tiene una precisión de %s m y se necesita de %s m o menos. Espere unos segundos junto al punto, a cielo abierto, y vuelva a intentarlo.',
                                   ceil(p_precision_m)::integer, v_max::integer));
  end if;
  if v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
    perform tecnica.f_error('La ubicación del GPS está fuera de Valledupar. Revise el GPS del celular.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('tecnica.punto_ubicacion|' || p.id, 0));
  select * into u from redes.v_punto_ubicacion_vigente where punto_id = p.id;
  if found and u.exactitud = 'verificada' then
    perform tecnica.f_error('La ubicación de este punto ya está verificada. Si está mal, avise a su supervisor.', '55000');
  end if;
  select * into pr from tecnica.v_punto_propuestas where punto_id = p.id and estado = 'pendiente' order by id desc limit 1;
  if found then
    if pr.autor = v_email then
      return jsonb_build_object('propuesta_id', pr.id, 'punto', p.codigo, 'estado', 'pendiente', 'duplicado', true, 'lat', pr.lat, 'lon', pr.lon, 'precision_m', pr.precision_m);
    end if;
    perform tecnica.f_error('Ya hay una ubicación de este punto en revisión del supervisor.', '55000');
  end if;
  insert into tecnica.punto_ubicacion_propuestas (punto_id, lat, lon, precision_m, ubicacion_previa_id, autor)
  values (p.id, v_lat, v_lon, round(p_precision_m, 1), u.id, v_email) returning id into v_id;
  if u.id is not null then
    v_dist := round(ST_Distance(ST_SetSRID(ST_MakePoint(v_lon::double precision, v_lat::double precision), 4326)::geography, u.geom::geography)::numeric);
  end if;
  perform tecnica.f_auditar(v_email, 'tec_punto_ubicacion_proponer', p.codigo, jsonb_build_object('propuesta_id', v_id, 'precision_m', round(p_precision_m, 1), 'distancia_m', v_dist), p_ip);
  return jsonb_build_object('propuesta_id', v_id, 'punto', p.codigo, 'estado', 'pendiente', 'duplicado', false, 'lat', v_lat, 'lon', v_lon, 'precision_m', round(p_precision_m, 1),
                            'distancia_m', v_dist);
end $f$;

-- Lo que revisa el supervisor (Dashboard PTAP, pestaña «Puntos»): las propuestas pendientes con la distancia a la ubicación vigente, todos los puntos de
-- muestreo activos con su ubicación y las 50 últimas revisiones. El correo de quien propuso y de quien revisó es dato de supervisión (como el autor de un registro).
create function public.geoportal_tec_punto_ubicaciones(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_aviso numeric := redes.f_param('mue_gps_distancia_aviso_m');
begin
  return jsonb_build_object(
    'precision_max_m', redes.f_param('mue_gps_precision_max_m'), 'distancia_aviso_m', v_aviso,
    'pendientes', coalesce((
      select jsonb_agg(jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'activo', p.activo,
               'lat', x.lat, 'lon', x.lon, 'precision_m', x.precision_m, 'autor', x.autor, 'autor_nombre', lb.nombre, 'creado_en', x.creado_en, 'propia', x.autor = v_email,
               'vigente', case when u.punto_id is not null then jsonb_build_object('lat', u.lat, 'lon', u.lon, 'exactitud', u.exactitud, 'fuente', u.fuente) end,
               'distancia_m', d.m, 'lejos', coalesce(d.m > v_aviso, false)) order by x.id)
        from tecnica.v_punto_propuestas x join tecnica.puntos p on p.id = x.punto_id
        left join redes.v_punto_ubicacion_vigente u on u.punto_id = x.punto_id
        left join public.geoportal_lista_blanca lb on lb.email = x.autor
        cross join lateral (select round(ST_Distance(x.geom::geography, u.geom::geography)::numeric) as m) d
       where x.estado = 'pendiente'), '[]'::jsonb),
    'puntos', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'lat', u.lat, 'lon', u.lon, 'exactitud', u.exactitud, 'fuente', u.fuente,
               'desde', u.creado_en, 'en_revision', exists (select 1 from tecnica.v_punto_propuestas x where x.punto_id = p.id and x.estado = 'pendiente')) order by p.codigo)
        from tecnica.puntos p left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
       where p.tipo = 'muestreo' and p.activo), '[]'::jsonb),
    'revisadas', coalesce((
      select jsonb_agg(r order by (r ->> 'revisada_en') desc) from (
        select jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'nombre', p.nombre, 'decision', x.estado, 'motivo', x.revision_motivo,
                                  'autor', x.autor, 'revisor', x.revisor, 'revisada_en', x.revisada_en, 'precision_m', x.precision_m) as r
          from tecnica.v_punto_propuestas x join tecnica.puntos p on p.id = x.punto_id
         where x.estado <> 'pendiente' order by x.revisada_en desc limit 50) z), '[]'::jsonb));
end $f$;

-- Aprobar o rechazar una ubicación propuesta. Al aprobar se AGREGA la ubicación a tecnica.puntos_ubicacion (verificada, fuente gps_operador; el autor
-- es quien la tomó) y queda como la vigente. El rechazo pide motivo (10 caracteres o más). Nadie revisa una ubicación que propuso (como en Personal).
create function public.geoportal_tec_punto_ubicacion_revisar(p_solicitante text, p_propuesta_id bigint, p_decision text, p_motivo text, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_supervision(p_solicitante); x record; p tecnica.puntos%rowtype; u record;
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), ''); v_ubic bigint; v_rev bigint;
begin
  if p_decision is null or p_decision not in ('aprobar', 'rechazar') then perform tecnica.f_error('Diga si aprueba o rechaza la ubicación'); end if;
  if p_decision = 'rechazar' and (v_mot is null or length(v_mot) < 10) then perform tecnica.f_error('Escriba el motivo del rechazo (10 caracteres o más)'); end if;
  if v_mot is not null and (length(v_mot) < 10 or length(v_mot) > 1000) then perform tecnica.f_error('El motivo, si lo escribe, va de 10 a 1.000 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('tecnica.puntos'));          -- el mismo candado que la publicación de la capa MUE (Corte 5a)
  select * into x from tecnica.v_punto_propuestas where id = p_propuesta_id;
  if not found then perform tecnica.f_error('No existe esa ubicación propuesta', 'P0002'); end if;
  if x.estado <> 'pendiente' then perform tecnica.f_error(format('Esta ubicación ya fue %s por %s', x.estado, x.revisor), '55000'); end if;
  if x.autor = v_email then perform tecnica.f_error('No puede revisar una ubicación que usted mismo tomó: pídaselo a otro supervisor o al administrador'); end if;
  select * into p from tecnica.puntos where id = x.punto_id;
  if p_decision = 'aprobar' then
    if not p.activo then perform tecnica.f_error('El punto está desactivado: no se puede aprobar su ubicación (puede rechazarla)'); end if;
    select * into u from redes.v_punto_ubicacion_vigente where punto_id = p.id;
    insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, barrio_capa, carga_id, autor)
    values (p.id, x.lat, x.lon, 'verificada', 'gps_operador', u.barrio_capa, null, x.autor) returning id into v_ubic;
  end if;
  insert into tecnica.punto_ubicacion_revisiones (propuesta_id, decision, motivo, ubicacion_id, autor)
  values (x.id, p_decision, v_mot, v_ubic, v_email) returning id into v_rev;
  perform tecnica.f_auditar(v_email, 'tec_punto_ubicacion_' || p_decision, p.codigo, jsonb_build_object('propuesta_id', x.id, 'propuso', x.autor, 'motivo', v_mot, 'ubicacion_id', v_ubic), p_ip);
  return jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'decision', p_decision, 'estado', case when p_decision = 'aprobar' then 'aprobada' else 'rechazada' end,
                            'ubicacion_id', v_ubic, 'revision_id', v_rev);
end $f$;
