-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 26 — RPC (public, SECURITY DEFINER, solo service_role; las llama la Edge geoportal-tecnica con el correo del token).
-- Seis RPC nuevas: perfil, mapa, ficha de un elemento, alias, y alcance (lista y fijar, solo el administrador). Ninguna RPC existente cambia de firma.
-- Sin datos personales del suscriptor ni términos tarifarios. Los mensajes para la persona llevan HINT 'msg_usuario' (tecnica.f_error).
-- =====================================================================

-- Lo que ve la persona en Técnica respecto de las plantas (lo usa el inicio para el modo PTAR y el selector de dashboards).
create function public.geoportal_tec_ptar_perfil(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v text := lower(btrim(coalesce(p_solicitante, ''))); v_perfil text; v_activa boolean; v_ptap boolean; v_ptar boolean;
begin
  v_perfil := tecnica.f_perfil(v);
  perform tecnica.f_verificar(p_solicitante, case when v_perfil = 'operador' then 'registro_tecnico' else 'dashboard_tecnico' end);   -- 28000 / 42501 si no hay acceso
  v_activa := v_perfil = 'admin' or tecnica.f_tecnica_activa(v);
  v_ptap := v_perfil in ('admin', 'supervisor') and v_activa and tecnica.f_tiene_alcance(v, 'ptap');
  v_ptar := v_perfil in ('admin', 'supervisor') and v_activa and tecnica.f_tiene_alcance(v, 'ptar');
  return jsonb_build_object('perfil', v_perfil, 'activa', v_activa, 'admin', v_perfil = 'admin', 'ptap', v_ptap, 'ptar', v_ptar,
    'instalaciones', coalesce((select jsonb_agg(jsonb_build_object('codigo', i.codigo, 'nombre', i.nombre, 'tipo', i.tipo,
                                                 'elementos', (select count(*) from tecnica.elementos_planta e where e.instalacion_id = i.id and e.activo)) order by i.tipo desc, i.id)
                                 from tecnica.instalaciones i where i.activa and ((i.tipo = 'residual' and v_ptar) or (i.tipo = 'potable' and v_ptap))), '[]'::jsonb));
end $$;

-- El mapa de una instalación: todos sus elementos activos en un GeoJSON (6 decimales ≈ 0,1 m), en el orden de dibujo
-- (perímetro, lagunas, tramos, pozos y descargas, puntos de medición). Mientras un elemento no tenga variables asignadas, su estado es «sin_variables».
create function public.geoportal_tec_ptar_mapa(p_solicitante text, p_instalacion text default 'ptar') returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare i tecnica.instalaciones; v_fc jsonb; v_caja jsonb; v_tipos jsonb;
begin
  perform tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  i := tecnica.f_instalacion(p_instalacion);
  perform tecnica.f_autorizar_instalacion(p_solicitante, i.id);
  with al as (
    select distinct on (a.codigo) a.codigo, a.alias from tecnica.elemento_alias_eventos a where a.instalacion_id = i.id order by a.codigo, a.id desc
  ), el as (
    select e.*, al.alias, case e.tipo when 'perimetro' then 1 when 'laguna' then 2 when 'tramo' then 3 when 'pozo' then 4 when 'descarga' then 4 else 5 end as capa
      from tecnica.elementos_planta e left join al on al.codigo = e.codigo
     where e.instalacion_id = i.id and e.activo
  )
  select jsonb_build_object('type', 'FeatureCollection', 'features', coalesce(jsonb_agg(jsonb_build_object('type', 'Feature', 'id', el.id,
           'geometry', st_asgeojson(el.geom, 6)::jsonb,
           'properties', jsonb_strip_nulls(jsonb_build_object('codigo', el.codigo, 'tipo', el.tipo, 'nombre', el.nombre, 'alias', el.alias, 'orden', el.orden,
                                                              'activo', el.activo_codigo, 'origen', el.origen, 'tipo_laguna', el.atributos ->> 'tipo_laguna',
                                                              'tren', el.atributos ->> 'tren', 'estado', 'sin_variables')))
           order by el.capa, el.orden, el.codigo), '[]'::jsonb)),
         (select jsonb_build_array(round(st_xmin(x)::numeric, 6), round(st_ymin(x)::numeric, 6), round(st_xmax(x)::numeric, 6), round(st_ymax(x)::numeric, 6))
            from (select st_extent(geom)::geometry as x from el) c where x is not null),
         (select jsonb_object_agg(t, n) from (select tipo as t, count(*) as n from el group by tipo) z)
    into v_fc, v_caja, v_tipos
    from el;
  return jsonb_build_object('instalacion', jsonb_build_object('codigo', i.codigo, 'nombre', i.nombre, 'tipo', i.tipo, 'horas_sin_dato', i.horas_sin_dato),
                            'caja', v_caja, 'por_tipo', coalesce(v_tipos, '{}'::jsonb), 'total', jsonb_array_length(v_fc -> 'features'), 'elementos', v_fc);
end $$;

-- Ficha de un elemento (popup del mapa): nombre, alias, tipo, medida, flujo, activo de redes y atributos. Indicadores: vacíos mientras no tenga variables asignadas.
create function public.geoportal_tec_ptar_elemento(p_solicitante text, p_codigo text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_cod text := upper(btrim(coalesce(p_codigo, ''))); e tecnica.elementos_planta; i tecnica.instalaciones; v_medida jsonb;
begin
  perform tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if v_cod !~ '^[A-Z0-9][A-Z0-9_-]{1,39}$' then perform tecnica.f_error('El código del elemento no es válido'); end if;
  select * into e from tecnica.elementos_planta x where x.codigo = v_cod and x.activo;
  if not found then perform tecnica.f_error('Ese elemento no existe', 'P0002'); end if;
  perform tecnica.f_autorizar_instalacion(p_solicitante, e.instalacion_id);
  select * into i from tecnica.instalaciones x where x.id = e.instalacion_id;
  v_medida := case when e.tipo in ('perimetro', 'laguna') then jsonb_build_object('area_m2', round(st_area(e.geom::geography)::numeric), 'area_ha', round((st_area(e.geom::geography) / 10000)::numeric, 2))
                   when e.tipo = 'tramo' then jsonb_build_object('longitud_m', round(st_length(e.geom::geography)::numeric, 1))
                   else jsonb_build_object('lat', round(st_y(e.geom)::numeric, 6), 'lon', round(st_x(e.geom)::numeric, 6)) end;
  return jsonb_strip_nulls(jsonb_build_object(
    'codigo', e.codigo, 'tipo', e.tipo, 'tipo_texto', tecnica.f_tipo_elemento_texto(e.tipo), 'nombre', e.nombre, 'alias', tecnica.f_alias_vigente(e.instalacion_id, e.codigo),
    'orden', e.orden, 'origen', e.origen, 'activo', e.activo_codigo, 'atributos', e.atributos, 'medida', v_medida,
    'instalacion', jsonb_build_object('codigo', i.codigo, 'nombre', i.nombre, 'tipo', i.tipo),
    'desde', (select jsonb_build_object('codigo', d.codigo, 'nombre', d.nombre) from tecnica.elementos_planta d where d.id = e.desde_id),
    'hasta', (select jsonb_build_object('codigo', h.codigo, 'nombre', h.nombre) from tecnica.elementos_planta h where h.id = e.hasta_id),
    'punto', (select jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre) from tecnica.puntos p where p.id = e.punto_id),
    'versiones', (select count(*) from tecnica.elementos_planta x where x.instalacion_id = e.instalacion_id and x.codigo = e.codigo),
    'alias_historial', coalesce((select jsonb_agg(jsonb_build_object('alias', a.alias, 'motivo', a.motivo, 'autor', a.autor, 'creado_en', a.creado_en) order by a.id desc)
                                   from (select * from tecnica.elemento_alias_eventos a where a.instalacion_id = e.instalacion_id and a.codigo = e.codigo order by a.id desc limit 10) a), '[]'::jsonb),
    'estado', 'sin_variables', 'indicadores', '[]'::jsonb, 'creado_en', e.creado_en));
end $$;

-- Fijar o quitar el alias de un elemento (alias vacío = quitar). Con motivo; solo se agrega un evento.
create function public.geoportal_tec_ptar_alias_fijar(p_solicitante text, p_codigo text, p_alias text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text; v_cod text := upper(btrim(coalesce(p_codigo, ''))); e tecnica.elementos_planta; v_alias text := nullif(btrim(coalesce(p_alias, '')), '');
        v_mot text := btrim(coalesce(p_motivo, '')); v_antes text;
begin
  perform tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if v_cod !~ '^[A-Z0-9][A-Z0-9_-]{1,39}$' then perform tecnica.f_error('El código del elemento no es válido'); end if;
  select * into e from tecnica.elementos_planta x where x.codigo = v_cod and x.activo;
  if not found then perform tecnica.f_error('Ese elemento no existe', 'P0002'); end if;
  v_email := tecnica.f_autorizar_instalacion(p_solicitante, e.instalacion_id);
  if v_alias is not null and (length(v_alias) > 60 or v_alias ~ '[[:cntrl:]]') then perform tecnica.f_error('El alias va de 1 a 60 caracteres, sin saltos de línea'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  v_antes := tecnica.f_alias_vigente(e.instalacion_id, e.codigo);
  if v_antes is not distinct from v_alias then
    perform tecnica.f_error(case when v_alias is null then 'El elemento no tiene alias' else 'El elemento ya tiene ese alias' end);
  end if;
  insert into tecnica.elemento_alias_eventos (instalacion_id, codigo, alias, motivo, autor) values (e.instalacion_id, e.codigo, v_alias, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'tec_ptar_alias', e.codigo, jsonb_build_object('antes', v_antes, 'despues', v_alias), p_ip);
  return jsonb_build_object('codigo', e.codigo, 'antes', v_antes, 'alias', v_alias);
end $$;

-- Alcance PTAP / PTAR de las personas (D6). Solo el administrador.
create function public.geoportal_tec_ptar_alcances(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
begin
  if not public.geoportal_es_admin(v_email) then
    raise exception 'Solo el administrador asigna el alcance PTAP o PTAR' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'personas', coalesce((select jsonb_agg(jsonb_build_object('persona', x.persona, 'perfil', tecnica.f_perfil(x.persona),
                                                              'ptap', tecnica.f_tiene_alcance(x.persona, 'ptap'), 'ptar', tecnica.f_tiene_alcance(x.persona, 'ptar')) order by x.persona)
                            from (select distinct a.persona from tecnica.alcance_eventos a) x), '[]'::jsonb),
    'historial', coalesce((select jsonb_agg(jsonb_build_object('persona', h.persona, 'alcance', h.alcance, 'tipo', h.tipo_evento, 'motivo', h.motivo, 'autor', h.autor, 'creado_en', h.creado_en) order by h.id desc)
                             from (select * from tecnica.alcance_eventos order by id desc limit 50) h), '[]'::jsonb),
    'regla', 'Sin asignación: PTAP sí, PTAR no. El administrador tiene los dos.');
end $$;

create function public.geoportal_tec_ptar_alcance_fijar(p_solicitante text, p_persona text, p_alcance text, p_accion text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico'); v_per text := lower(btrim(coalesce(p_persona, '')));
        v_alc text := lower(btrim(coalesce(p_alcance, ''))); v_acc text := lower(btrim(coalesce(p_accion, ''))); v_mot text := btrim(coalesce(p_motivo, '')); v_perfil text;
begin
  if not public.geoportal_es_admin(v_email) then
    raise exception 'Solo el administrador asigna el alcance PTAP o PTAR' using errcode = '42501';
  end if;
  if v_per !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' then perform tecnica.f_error('El correo de la persona no es válido'); end if;
  if v_alc not in ('ptap', 'ptar') then perform tecnica.f_error('El alcance es PTAP o PTAR'); end if;
  if v_acc not in ('asignar', 'quitar') then perform tecnica.f_error('La acción es asignar o quitar'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  v_perfil := tecnica.f_perfil(v_per);
  if v_perfil is null then perform tecnica.f_error('Esa persona no tiene acceso a Técnica'); end if;
  if v_perfil = 'admin' then perform tecnica.f_error('El administrador tiene los dos alcances siempre'); end if;
  if tecnica.f_tiene_alcance(v_per, v_alc) = (v_acc = 'asignar') then
    perform tecnica.f_error(case when v_acc = 'asignar' then 'Esa persona ya tiene ese alcance' else 'Esa persona no tiene ese alcance' end);
  end if;
  insert into tecnica.alcance_eventos (persona, alcance, tipo_evento, motivo, autor) values (v_per, v_alc, v_acc, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'tec_ptar_alcance', v_per, jsonb_build_object('alcance', v_alc, 'accion', v_acc), p_ip);
  return jsonb_build_object('persona', v_per, 'perfil', v_perfil, 'ptap', tecnica.f_tiene_alcance(v_per, 'ptap'), 'ptar', tecnica.f_tiene_alcance(v_per, 'ptar'));
end $$;
