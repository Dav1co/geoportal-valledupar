-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 26 — FUNCIONES NUEVAS
--   · redes.f_autorizar_carga y redes.f_autorizar_carga_id: quién carga cada capa (el administrador todas; el supervisor de distribución las que
--     tienen carga_supervisor). Las usan las RPC del Cargue reemplazadas en 25.
--   · redes.f_geovisor_acceso: quién abre el geovisor y con qué perfiles (N-11 y N-13). Se apoya en redes.f_geovisor_lectura (Corte 4b), sin tocarla.
--   · redes.f_puede_formulario: si la persona puede abrir un formulario de distribución (para los botones de la tarjeta), sin lanzar error.
--   · public.geoportal_redes_geovisor: la configuración del geovisor (capas que puede ver, encendidas al abrir, zooms, rango de fechas, materiales…).
--   · public.geoportal_redes_geovisor_mvt: la tesela de los activos vigentes, con material, diámetro, edad y estado.
--   · public.geoportal_redes_geovisor_capa: las capas por fecha (daños, intervenciones, reportes del bot) y los puntos de muestreo, en GeoJSON.
--   · public.geoportal_redes_geovisor_capas_fijar: el administrador cambia las capas que se encienden al abrir, por perfil, con motivo.
-- Nada de esto lleva datos de contratos, nombres, teléfonos, descripciones ni el tercero de un daño.
-- =====================================================================

-- ---------- Quién carga cada capa ----------
create function redes.f_autorizar_carga(p_solicitante text, p_capa text) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_email text := lower(btrim(coalesce(p_solicitante, ''))); c redes.capas%rowtype;
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if public.geoportal_es_admin(v_email) then return v_email; end if;
  if not public.geoportal_puede(v_email, 'dashboard_redes') then raise exception 'Solo el administrador o el supervisor de distribución cargan capas' using errcode = '42501'; end if;
  if not tecnica.f_tecnica_activa(v_email) then raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501'; end if;
  select * into c from redes.capas where codigo = p_capa;
  if not found then perform tecnica.f_error('No existe esa capa', 'P0002'); end if;
  if not c.carga_supervisor then raise exception 'La capa % viene del modelo hidráulico: la carga solo el administrador', c.nombre using errcode = '42501'; end if;
  return v_email;
end $$;
comment on function redes.f_autorizar_carga(text, text) is 'Corte 6a: el administrador carga todas las capas; el supervisor de distribución, las que tienen carga_supervisor (las del modelo, no).';

create function redes.f_autorizar_carga_id(p_solicitante text, p_carga bigint) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_capa text;
begin
  select capa_codigo into v_capa from redes.cargas where id = p_carga;
  if v_capa is null then
    perform redes.f_autorizar_admin(p_solicitante);      -- quien no es administrador no sabe si la carga existe
    perform tecnica.f_error('No existe esa carga', 'P0002');
  end if;
  return redes.f_autorizar_carga(p_solicitante, v_capa);
end $$;

-- ---------- Quién abre el geovisor y con qué perfiles ----------
-- completo = supervisor (de distribución o de planta) o administrador; el operador de distribución con la casilla activada (N-13) ve solo las capas
-- sin solo_completo y las actividades del día. El administrador abre con las capas de los dos supervisores (N-11).
create function redes.f_geovisor_acceso(p_solicitante text, out email text, out completo boolean, out admin boolean, out perfiles text[]) returns record
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
begin
  email := lower(btrim(coalesce(p_solicitante, '')));
  if email = '' or position('@' in email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if not redes.f_geovisor_lectura(email) then raise exception 'Sin el geovisor técnico' using errcode = '42501'; end if;
  admin := public.geoportal_es_admin(email);
  if admin then perfiles := array['supervisor_distribucion', 'supervisor_planta']; completo := true; return; end if;
  perfiles := array_remove(array[case when public.geoportal_puede(email, 'dashboard_redes') then 'supervisor_distribucion' end,
                                 case when public.geoportal_puede(email, 'dashboard_tecnico') then 'supervisor_planta' end], null);
  completo := cardinality(perfiles) > 0;
  if not completo then perfiles := array['operador_distribucion']; end if;
end $$;

create function redes.f_puede_formulario(p_email text, p_formulario text) returns boolean
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
begin
  perform redes.f_autorizar_captura_redes(p_email, p_formulario);
  return true;
exception when others then
  return false;
end $$;

-- ---------- Configuración del geovisor ----------
create function public.geoportal_redes_geovisor(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  return jsonb_build_object(
    'perfil', case when a.admin then 'admin' when a.completo then 'supervisor' else 'operador' end,
    'completo', a.completo, 'perfiles', to_jsonb(a.perfiles),
    'hoy', (clock_timestamp() at time zone 'America/Bogota')::date,
    'rango_meses', floor(redes.f_param('geovisor_rango_meses'))::integer,
    'max_elementos', floor(redes.f_param('geovisor_max_elementos'))::integer,
    'zoom', jsonb_build_object('min', redes.f_param('geovisor_zoom_min'), 'red_completa', redes.f_param('geovisor_zoom_red_completa'),
                               'nodos', redes.f_param('geovisor_zoom_nodos'), 'accesorios', redes.f_param('geovisor_zoom_acc')),
    'version', (select coalesce(sum(version), 0) from redes.tesela_version),
    'formularios', jsonb_build_object('danos_fallas', redes.f_puede_formulario(a.email, 'danos_fallas'),
                                      'mantenimiento', redes.f_puede_formulario(a.email, 'mantenimiento')),
    'ficha', a.completo,
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre, 'grupo', g.grupo, 'fuente', g.fuente, 'estado', g.estado, 'nota', g.nota,
                                          'prefijos', to_jsonb(g.prefijos), 'por_fecha', g.por_fecha,
                                          'encendida', exists (select 1 from redes.capas_por_perfil c where c.capa = g.codigo and c.encendida and c.perfil = any (a.perfiles)))
             order by g.orden)
        from redes.geovisor_capas g where g.activa and (a.completo or not g.solo_completo)), '[]'::jsonb),
    'tipos', coalesce((select jsonb_object_agg(t.prefijo, t.nombre_visible) from redes.v_tipo_visible t), '{}'::jsonb),
    'estados', coalesce((select jsonb_object_agg(e.codigo, e.nombre) from redes.estados_activo e), '{}'::jsonb),
    'materiales', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', m.nombre) order by m.codigo) from redes.materiales m), '[]'::jsonb),
    -- solo el administrador: la tabla de capas por omisión, para editarla (N-11)
    'por_perfil', case when a.admin then coalesce((
      select jsonb_agg(jsonb_build_object('perfil', c.perfil, 'capa', c.capa, 'encendida', c.encendida, 'actualizado_en', c.actualizado_en, 'actualizado_por', c.actualizado_por)
             order by c.perfil, c.capa) from redes.capas_por_perfil c), '[]'::jsonb) end);
end $$;

-- ---------- Tesela del geovisor (perfil completo): activos vigentes, con lo que hace falta para colorear por material o edad ----------
-- Por zoom (parámetros): menos de geovisor_zoom_min, vacía; hasta geovisor_zoom_red_completa, solo la red principal (por diámetro), las conducciones,
-- las aducciones, los interceptores, los sectores y las instalaciones; los demás puntos desde geovisor_zoom_nodos; los accesorios desde geovisor_zoom_acc.
-- Solo los prefijos de las capas que la persona puede ver.
create function public.geoportal_redes_geovisor_mvt(p_solicitante text, p_z integer, p_x integer, p_y integer) returns text
language plpgsql stable security definer set search_path = public, redes, extensions, pg_temp as $$
declare a record; v_env geometry; v_env4326 geometry; v bytea; v_pref text[]; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        z_min numeric := redes.f_param('geovisor_zoom_min'); z_red numeric := redes.f_param('geovisor_zoom_red_completa');
        z_nod numeric := redes.f_param('geovisor_zoom_nodos'); z_acc numeric := redes.f_param('geovisor_zoom_acc');
        d_acu numeric := redes.f_param('geovisor_diam_principal_acu_mm'); d_alc numeric := redes.f_param('geovisor_diam_principal_alc_mm');
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < z_min then return ''; end if;
  select array_agg(distinct p) into v_pref from redes.geovisor_capas g cross join unnest(g.prefijos) p where g.activa and g.fuente = 'tesela' and (a.completo or not g.solo_completo);
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4326 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'activos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, m.codigo, m.prefijo, m.sistema,
           case GeometryType(m.geom) when 'POINT' then 'nodo' when 'POLYGON' then 'area' when 'MULTIPOLYGON' then 'area' else 'tramo' end as forma,
           coalesce(m.clase, '') as clase, coalesce(m.material_codigo, '') as material, m.diametro_mm::real as diametro,
           case when m.fecha_instalacion is not null then greatest(0, extract(year from age(v_hoy, m.fecha_instalacion)))::integer end as edad,
           m.estado_codigo as estado, m.punteado
      from redes.activo_vigente_mat m
     where not m.retirado and not m.oculto and m.prefijo = any (v_pref)
       and m.geom && v_env4326
       and case
             when m.prefijo = 'ACC' then p_z >= z_acc
             when m.prefijo in ('TAN', 'PTA', 'CAP', 'DES', 'EBA', 'EBR', 'PTR', 'SEC') then true
             when GeometryType(m.geom) = 'POINT' then p_z >= z_nod
             when p_z >= z_red then true
             else m.prefijo in ('CON', 'ADU', 'INT')
                  or (m.sistema = 'acueducto' and m.diametro_mm >= d_acu) or (m.sistema = 'alcantarillado' and m.diametro_mm >= d_alc)
           end) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $$;

-- ---------- Capas en GeoJSON: daños, intervenciones y reportes del bot por fecha (día de Bogotá), y los puntos de muestreo ----------
-- El operador (N-13) solo ve las actividades del día. Nunca van la descripción, el tercero, la dirección ni las fotos: solo lo que se dibuja y la tarjeta.
create function public.geoportal_redes_geovisor_capa(p_solicitante text, p_capa text, p_desde date default null, p_hasta date default null) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; g redes.geovisor_capas%rowtype; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        v_desde date := coalesce(p_desde, v_hoy); v_hasta date := coalesce(p_hasta, v_hoy); v_max integer := floor(redes.f_param('geovisor_max_elementos'))::integer;
        v_ini timestamptz; v_fin timestamptz; v_f jsonb; v_n integer;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into g from redes.geovisor_capas where codigo = p_capa and activa;
  if not found or g.fuente <> 'geojson' then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if g.solo_completo and not a.completo then raise exception 'Capa solo para supervisores' using errcode = '42501'; end if;
  if g.por_fecha then
    if v_desde > v_hasta then perform tecnica.f_error('La fecha inicial es posterior a la final'); end if;
    if v_hasta > v_hoy then perform tecnica.f_error('La fecha final no puede ser futura'); end if;
    if v_desde < (v_hasta - make_interval(months => floor(redes.f_param('geovisor_rango_meses'))::integer))::date then
      perform tecnica.f_error(format('El rango de fechas es de máximo %s meses', floor(redes.f_param('geovisor_rango_meses'))::integer));
    end if;
    if not a.completo and (v_desde <> v_hoy or v_hasta <> v_hoy) then raise exception 'El geovisor en solo lectura muestra solo las actividades del día' using errcode = '42501'; end if;
  end if;
  v_ini := v_desde::timestamp at time zone 'America/Bogota';
  v_fin := (v_hasta + 1)::timestamp at time zone 'America/Bogota';

  if p_capa = 'danos' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(d.lon, d.lat)),
               'properties', jsonb_build_object('codigo', d.codigo, 'clase', d.clase, 'tipo', d.tipo_nombre, 'sistema', d.sistema, 'estado', d.estado,
                                                'activo', d.activo_codigo, 'cuando', d.t_detectado, 'riesgo', d.riesgo, 'origen', d.origen)) as f, d.t_detectado as o
        from redes.v_dano d
       where d.estado <> 'oculto' and d.t_detectado >= v_ini and d.t_detectado < v_fin and d.lat is not null
       order by d.t_detectado desc limit v_max + 1) x;
  elsif p_capa = 'intervenciones' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(i.lon, i.lat)),
               'properties', jsonb_build_object('codigo', i.codigo, 'tipo_codigo', i.tipo_codigo, 'tipo', i.tipo_nombre, 'sistema', i.sistema, 'estado', i.estado,
                                                'activo', i.activo_codigo, 'dano', i.dano_codigo, 'cuando', i.t_inicio, 'fin', i.t_fin, 'ejecutor', i.ejecutor)) as f, i.t_inicio as o
        from redes.v_intervencion i
       where i.estado not in ('oculta', 'anulada') and i.t_inicio >= v_ini and i.t_inicio < v_fin and i.lat is not null
       order by i.t_inicio desc limit v_max + 1) x;
  elsif p_capa = 'reportes_bot' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.radicado, 'canal', r.canal, 'tipo', r.tipo_bot, 'estado', r.estado_bot, 'dano', r.dano_codigo,
                                                'cuando', r.recibido_en)) as f, r.recibido_en as o
        from redes.v_reporte_externo r
       where r.recibido_en >= v_ini and r.recibido_en < v_fin and r.lat is not null
       order by r.recibido_en desc limit v_max + 1) x;
  elsif p_capa = 'muestreo' then
    select coalesce(jsonb_agg(f order by o), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(u.lon, u.lat)),
               'properties', jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'exactitud', u.exactitud)) as f, p.codigo as o
        from tecnica.puntos p join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
       where p.tipo = 'muestreo' and p.activo
       order by p.codigo limit v_max + 1) x;
  else
    perform tecnica.f_error('Esa capa todavía no tiene datos', 'P0002');
  end if;

  if v_n > v_max then v_f := v_f - v_max; end if;      -- se quitó el elemento de más (el último de la lista)
  return jsonb_build_object('type', 'FeatureCollection', 'capa', p_capa, 'desde', case when g.por_fecha then v_desde end, 'hasta', case when g.por_fecha then v_hasta end,
                            'recortada', v_n > v_max, 'features', v_f);
end $$;

-- ---------- Capas por omisión del geovisor (N-11): las cambia el administrador, con motivo ----------
create function public.geoportal_redes_geovisor_capas_fijar(p_solicitante text, p_perfil text, p_capa text, p_encendida boolean, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_email text := redes.f_autorizar_admin(p_solicitante); v_mot text := btrim(coalesce(p_motivo, '')); v_antes boolean; g redes.geovisor_capas%rowtype;
begin
  if p_perfil is null or p_perfil not in ('supervisor_distribucion', 'supervisor_planta', 'operador_distribucion') then perform tecnica.f_error('Ese perfil no existe'); end if;
  if p_encendida is null then perform tecnica.f_error('Diga si la capa se enciende o no'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  select * into g from redes.geovisor_capas where codigo = p_capa and activa;
  if not found then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if p_encendida and g.fuente = 'preparada' then perform tecnica.f_error(format('La capa «%s» todavía no tiene datos: no se puede encender al abrir', g.nombre)); end if;
  if p_encendida and p_perfil = 'operador_distribucion' and g.solo_completo then perform tecnica.f_error(format('El operador no ve la capa «%s»', g.nombre)); end if;
  perform pg_advisory_xact_lock(hashtext('redes.capas_por_perfil'));
  select encendida into v_antes from redes.capas_por_perfil where perfil = p_perfil and capa = p_capa;
  if v_antes is not distinct from p_encendida or (v_antes is null and not p_encendida) then
    return jsonb_build_object('perfil', p_perfil, 'capa', p_capa, 'encendida', p_encendida, 'cambio', false);
  end if;
  insert into redes.capas_por_perfil (perfil, capa, encendida, actualizado_por) values (p_perfil, p_capa, p_encendida, v_email)
  on conflict (perfil, capa) do update set encendida = excluded.encendida, actualizado_en = clock_timestamp(), actualizado_por = excluded.actualizado_por;
  insert into redes.capas_por_perfil_eventos (perfil, capa, antes, despues, motivo, autor) values (p_perfil, p_capa, v_antes, p_encendida, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_geovisor_capas_fijar', p_perfil || '/' || p_capa, jsonb_build_object('antes', v_antes, 'despues', p_encendida, 'motivo', v_mot), null);
  return jsonb_build_object('perfil', p_perfil, 'capa', p_capa, 'encendida', p_encendida, 'cambio', true);
end $$;
