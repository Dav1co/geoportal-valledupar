-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 26 — RPC NUEVAS (public.geoportal_redes_levantar_*; solo service_role, desde la Edge geoportal-redes)
-- PROPUESTA. No se ha ejecutado en la base real.
-- Ninguna recorre tablas enteras: la búsqueda de cercanos entra por el índice espacial de redes.activo_vigente_mat (caja de pocos metros).
-- =====================================================================

-- ---------- Abrir la pantalla: quién es, los parámetros y los tipos ----------
create function public.geoportal_redes_levantar_inicio(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare a record;
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  return jsonb_build_object('perfil', a.perfil, 'area', a.area,
    'ficha_completa', a.area = 'tecnica',                                            -- en Técnica se abre la ficha de siempre (la edita quien ya podía)
    'reporta_dano', a.area = 'tecnica' and redes.f_puede_formulario(a.email, 'danos_fallas'),      -- «Reportar daño en este activo» (quien tiene el formulario de daños)
    'radio_min_m', redes.f_param('levantar_radio_min_m'), 'radio_max_m', redes.f_param('levantar_radio_max_m'), 'duplicado_m', redes.f_param('levantar_duplicado_m'),
    'min_fotos', 1, 'max_fotos', 3,
    'servicios', jsonb_build_array(jsonb_build_object('codigo', 'acueducto', 'nombre', 'Acueducto'), jsonb_build_object('codigo', 'alcantarillado', 'nombre', 'Alcantarillado')),
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', t, 'nombre', redes.f_levantar_tipo_nombre(t)) order by o)
                from unnest(array['tuberia', 'valvula', 'hidrante', 'pozo', 'caja', 'otro']) with ordinality x(t, o)));
end $$;

-- ---------- Encontrar: los activos cercanos a la persona (y los puntos por levantar que ya hay ahí) ----------
-- Radio = el mayor entre el mínimo (15 m) y la precisión del GPS, con tope (30 m). La posición no se guarda.
create function public.geoportal_redes_levantar_cerca(p_solicitante text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_servicio text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare a record; v_min numeric := redes.f_param('levantar_radio_min_m'); v_max numeric := redes.f_param('levantar_radio_max_m'); v_dup numeric := redes.f_param('levantar_duplicado_m');
        v_lim integer := redes.f_param('levantar_lista_max')::integer; v_radio numeric; v_pto geometry; v_g geography; v_caja geometry; v_recorte geometry;
        v_act jsonb; v_total integer; v_ptos jsonb;
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if p_lat is null or p_lon is null or p_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max')
     or p_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
    perform tecnica.f_error('La posición está fuera de Valledupar');
  end if;
  if p_servicio is null or p_servicio not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija acueducto o alcantarillado'); end if;
  if p_precision_m is not null and (p_precision_m <= 0 or p_precision_m > 5000) then perform tecnica.f_error('La precisión del GPS no es válida'); end if;
  v_radio := greatest(v_min, least(coalesce(p_precision_m, v_min), v_max));
  v_pto := ST_SetSRID(ST_MakePoint(p_lon::double precision, p_lat::double precision), 4326); v_g := v_pto::geography;
  v_caja := ST_Expand(v_pto, (greatest(v_radio, v_dup) + 5) / 100000.0);      -- caja en grados (1 grado ≈ 110 km): entra por el índice espacial
  v_recorte := ST_Buffer(v_g, 4 * v_max)::geometry;                            -- los tramos se dibujan recortados alrededor de la persona
  with c as (
    select m.activo_id, m.codigo, m.prefijo, m.material_codigo, m.diametro_mm, m.estado_codigo, m.geom,
           case when GeometryType(m.geom) in ('POINT', 'MULTIPOINT') then 'punto' when GeometryType(m.geom) in ('POLYGON', 'MULTIPOLYGON') then 'area' else 'linea' end as forma,
           ST_Distance(m.geom::geography, v_g) as d
      from redes.activo_vigente_mat m
     where not m.retirado and not m.oculto and m.sistema = p_servicio and m.geom && v_caja and ST_DWithin(m.geom::geography, v_g, v_radio)
  ), o as (
    -- a igual distancia (al decímetro), primero los puntos (válvula, pozo) y después los tramos que llegan a ellos
    select c.*, row_number() over (order by round(c.d::numeric, 1), (c.forma <> 'punto'), c.codigo) as n, count(*) over () as total from c
  )
  select coalesce(max(o.total), 0)::integer,
         coalesce(jsonb_agg(jsonb_build_object('n', o.n, 'codigo', o.codigo, 'prefijo', o.prefijo, 'tipo', redes.f_tipo_nombre(o.prefijo), 'forma', o.forma,
                    'material', (select mt.nombre from redes.materiales mt where mt.codigo = o.material_codigo), 'diametro_mm', o.diametro_mm,
                    'estado', (select s.nombre from redes.estados_activo s where s.codigo = o.estado_codigo), 'proyectado', o.estado_codigo = 'proyectado',
                    'distancia_m', round(o.d::numeric, 1),
                    'lat', round(ST_Y(ST_ClosestPoint(o.geom, v_pto))::numeric, 6), 'lon', round(ST_X(ST_ClosestPoint(o.geom, v_pto))::numeric, 6),
                    'geometria', ST_AsGeoJSON(case when o.forma = 'punto' then o.geom else ST_Intersection(o.geom, v_recorte) end, 6)::jsonb) order by o.n)
                  filter (where o.n <= v_lim), '[]'::jsonb)
    into v_total, v_act from o;
  select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'servicio', x.servicio, 'tipo', x.tipo, 'tipo_nombre', redes.f_levantar_tipo_nombre(x.tipo), 'estado', x.estado,
                    'registrado_en', x.registrado_en, 'distancia_m', round(x.d::numeric, 1), 'lat', x.lat, 'lon', x.lon, 'posible_duplicado', x.d <= v_dup) order by x.d, x.codigo), '[]'::jsonb)
    into v_ptos
    from (select p.codigo, p.servicio, p.tipo, p.estado, p.registrado_en, p.lat, p.lon, ST_Distance(p.geom::geography, v_g) as d
            from redes.v_levantar_punto p
           where p.geom && v_caja and ST_DWithin(p.geom::geography, v_g, greatest(v_radio, v_dup)) and p.estado in ('reportado', 'asignado')) x;
  return jsonb_build_object('servicio', p_servicio, 'radio_m', v_radio, 'precision_m', p_precision_m, 'senal_debil', p_precision_m is null or p_precision_m > v_max,
    'tope_m', v_max, 'duplicado_m', v_dup, 'total', v_total, 'activos', v_act, 'puntos', v_ptos);
end $$;

-- ---------- La ficha corta (solo lectura) de un activo, para quien no entra a la ficha de Técnica ----------
create function public.geoportal_redes_levantar_ficha(p_solicitante text, p_codigo text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare a record; m redes.activo_vigente_mat%rowtype; v_cod text := upper(btrim(coalesce(p_codigo, '')));
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if v_cod !~ '^[A-Z]{3}-[0-9]{1,8}$' then perform tecnica.f_error('Ese código de activo no es válido'); end if;
  select * into m from redes.activo_vigente_mat x where x.codigo = v_cod and not x.retirado and not x.oculto;
  if not found then perform tecnica.f_error('Ese activo no existe', 'P0002'); end if;
  return jsonb_build_object('codigo', m.codigo, 'prefijo', m.prefijo, 'tipo', redes.f_tipo_nombre(m.prefijo), 'sistema', m.sistema,
    'clase', (select c.nombre from redes.clases_activo c where c.prefijo = m.prefijo and c.codigo = m.clase), 'nombre', m.nombre,
    'material', (select mt.nombre from redes.materiales mt where mt.codigo = m.material_codigo), 'diametro_mm', m.diametro_mm,
    'longitud_m', case when GeometryType(m.geom) in ('LINESTRING', 'MULTILINESTRING') then round(coalesce(m.longitud_m, ST_Length(m.geom::geography)::numeric), 1) end, 'profundidad_m', m.profundidad_m, 'fecha_instalacion', m.fecha_instalacion,
    'estado', (select s.nombre from redes.estados_activo s where s.codigo = m.estado_codigo), 'codigo_anterior', m.codigo_anterior,
    'sector', (select s.nombre from redes.f_sector_de(ST_PointOnSurface(m.geom)) s),
    'lat', round(ST_Y(ST_PointOnSurface(m.geom))::numeric, 6), 'lon', round(ST_X(ST_PointOnSurface(m.geom))::numeric, 6),
    'ficha_completa', a.area = 'tecnica');
end $$;

-- ---------- Reportar activo: preparar la subida de las fotos (1 obligatoria y 2 opcionales) ----------
create function public.geoportal_redes_levantar_preparar(p_solicitante text, p_fotos integer) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare a record; v_id uuid := gen_random_uuid(); v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM');
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if p_fotos is null or p_fotos < 1 or p_fotos > 3 then perform tecnica.f_error('Un activo por levantar lleva de 1 a 3 fotos'); end if;
  insert into redes.levantar_preparaciones (punto_id, autor, fotos) values (v_id, a.email, p_fotos);
  return jsonb_build_object('punto_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_dano')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', (select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'levantar/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n) from generate_series(1, p_fotos) n));
end $$;

-- ---------- Reportar activo: crear el punto por levantar ----------
-- p_datos: servicio, tipo, observacion, lat, lon, precision_m, fotos [{n, ruta}], no_es_duplicado (la persona ya vio el punto cercano y dijo que no es el mismo).
-- Si hay un punto por levantar a menos de levantar_duplicado_m y no viene «no_es_duplicado», NO crea nada: devuelve creado = false y los puntos.
create function public.geoportal_redes_levantar_crear(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'storage', 'pg_temp' as $$
declare a record; d jsonb := coalesce(p_datos, '{}'::jsonb); v_prev redes.levantar_puntos%rowtype; v_prep redes.levantar_preparaciones%rowtype;
        v_obs text; v_lat numeric; v_lon numeric; v_prec numeric; v_max numeric := redes.f_param('levantar_radio_max_m'); v_dup numeric := redes.f_param('levantar_duplicado_m');
        v_pto geometry; v_dups jsonb; v_fotos jsonb; v_n integer; v_f jsonb; v_ruta text; v_size bigint; v_mime text; v_max_bytes bigint := redes.f_param('max_bytes_foto_dano')::bigint;
        v_ref jsonb := '[]'::jsonb; v_cons bigint; v_codigo text; v_en timestamptz := clock_timestamp();
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if p_id is null then perform tecnica.f_error('Falta el identificador: prepare la subida de las fotos primero'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos no tienen el formato esperado'); end if;
  perform pg_advisory_xact_lock(hashtextextended('lev|' || p_id::text, 0));
  select * into v_prev from redes.levantar_puntos where id = p_id;
  if found then      -- reintento del mismo envío (sin señal): se devuelve lo ya guardado
    if v_prev.autor <> a.email then perform tecnica.f_error('Primero debe prepararse la subida de las fotos'); end if;
    return jsonb_build_object('creado', true, 'repetido', true, 'id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'precision_baja', v_prev.precision_baja, 'estado', 'reportado');
  end if;
  select * into v_prep from redes.levantar_preparaciones where punto_id = p_id and autor = a.email;
  if not found then perform tecnica.f_error('Primero debe prepararse la subida de las fotos'); end if;
  if coalesce(d ->> 'servicio', '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el servicio: acueducto o alcantarillado'); end if;
  if coalesce(d ->> 'tipo', '') not in ('tuberia', 'valvula', 'hidrante', 'pozo', 'caja', 'otro') then perform tecnica.f_error('Elija qué activo encontró'); end if;
  v_obs := nullif(btrim(coalesce(d ->> 'observacion', '')), '');
  if v_obs is not null and (length(v_obs) < 3 or length(v_obs) > 500) then perform tecnica.f_error('La observación va de 3 a 500 caracteres'); end if;
  if d ->> 'tipo' = 'otro' and v_obs is null then perform tecnica.f_error('Escriba en la observación qué activo es'); end if;
  begin
    v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric; v_prec := (d ->> 'precision_m')::numeric;
  exception when others then perform tecnica.f_error('La posición del GPS no es válida');
  end;
  if v_lat is null or v_lon is null then perform tecnica.f_error('Falta la posición del GPS: active la ubicación del celular'); end if;
  if v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
    perform tecnica.f_error('La posición está fuera de Valledupar');
  end if;
  if v_prec is null or v_prec <= 0 or v_prec > 5000 then perform tecnica.f_error('Falta la precisión del GPS: active la ubicación del celular'); end if;
  v_pto := ST_SetSRID(ST_MakePoint(v_lon::double precision, v_lat::double precision), 4326);

  -- duplicados (regla 2): un punto por levantar a pocos metros se muestra antes de crear otro
  if d -> 'no_es_duplicado' is distinct from 'true'::jsonb then
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'servicio', x.servicio, 'tipo', x.tipo, 'tipo_nombre', redes.f_levantar_tipo_nombre(x.tipo), 'registrado_en', x.registrado_en,
                     'distancia_m', round(x.dist::numeric, 1), 'lat', x.lat, 'lon', x.lon) order by x.dist, x.codigo)
      into v_dups
      from (select p.codigo, p.servicio, p.tipo, p.registrado_en, p.lat, p.lon, ST_Distance(p.geom::geography, v_pto::geography) as dist
              from redes.v_levantar_punto p
             where p.geom && ST_Expand(v_pto, (v_dup + 5) / 100000.0) and ST_DWithin(p.geom::geography, v_pto::geography, v_dup) and p.estado in ('reportado', 'asignado')) x;
    if v_dups is not null then return jsonb_build_object('creado', false, 'duplicados', v_dups, 'duplicado_m', v_dup); end if;
  end if;

  -- fotos: el tamaño y el tipo se leen de Storage (nunca se le creen al celular)
  v_fotos := coalesce(d -> 'fotos', '[]'::jsonb);
  if jsonb_typeof(v_fotos) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n < 1 or v_n > 3 or v_n > v_prep.fotos then perform tecnica.f_error('Un activo por levantar lleva de 1 a 3 fotos'); end if;
  if (select count(distinct (e ->> 'n')) <> v_n or bool_or(coalesce(e ->> 'n', '') !~ '^[1-3]$') from jsonb_array_elements(v_fotos) e)
     or (select max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_fotos) e) then
    perform tecnica.f_error('El orden de las fotos debe ser 1, 2, 3 sin repetir ni saltar');
  end if;
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'n')::integer loop
    v_ruta := coalesce(v_f ->> 'ruta', '');
    if v_ruta !~ ('^levantar/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || '\.jpg$') then
      perform tecnica.f_error(format('La ruta de la foto %s no corresponde a este reporte', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró la foto %s: súbala de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('La foto %s está vacía', v_f ->> 'n')); end if;
    if v_size > v_max_bytes then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;

  -- código LEV-000123 (candado de fila del consecutivo) e inserción
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'LEV' returning ultimo into v_cons;
  v_codigo := 'LEV-' || lpad(v_cons::text, 6, '0');
  insert into redes.levantar_puntos (id, codigo, servicio, tipo, observacion, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en)
  values (p_id, v_codigo, d ->> 'servicio', d ->> 'tipo', v_obs, round(v_lat, 6), round(v_lon, 6), v_pto, round(v_prec, 1), v_prec > v_max, a.area, a.email, v_en);
  insert into redes.levantar_fotos (punto_id, n, ruta_storage, bytes, mime)
  select p_id, (e ->> 'n')::smallint, e ->> 'ruta', (e ->> 'bytes')::integer, e ->> 'mime' from jsonb_array_elements(v_ref) e;
  perform tecnica.f_auditar(a.email, 'redes_levantar_crear', v_codigo, jsonb_build_object('servicio', d ->> 'servicio', 'tipo', d ->> 'tipo', 'fotos', v_n,
          'precision_m', round(v_prec, 1), 'precision_baja', v_prec > v_max, 'area', a.area, 'no_es_duplicado', d -> 'no_es_duplicado' = 'true'::jsonb), p_ip);
  return jsonb_build_object('creado', true, 'repetido', false, 'id', p_id, 'codigo', v_codigo, 'registrado_en', v_en, 'precision_baja', v_prec > v_max, 'estado', 'reportado');
end $$;

-- ---------- Supervisor: la bandeja «Otros activos por levantamiento» (Dashboard distribución → Por verificar) ----------
create function public.geoportal_redes_levantar_lista(p_solicitante text, p_estado text default 'abiertos', p_despues_de text default null, p_limite integer default 50) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 've los activos por levantar'); v_lim integer := coalesce(p_limite, 50); v_est text := coalesce(p_estado, 'abiertos');
        v_desp text := nullif(upper(btrim(coalesce(p_despues_de, ''))), ''); v_items jsonb; v_cont jsonb; v_prop numeric := redes.f_param('levantar_propuesta_m');
begin
  if v_lim < 1 or v_lim > 200 then perform tecnica.f_error('Se piden de 1 a 200'); end if;
  if v_est not in ('abiertos', 'reportado', 'asignado', 'levantado', 'descartado', 'todos') then perform tecnica.f_error('Ese estado no existe'); end if;
  if v_desp is not null and v_desp !~ '^LEV-[0-9]{6}$' then perform tecnica.f_error('La página pedida no es válida'); end if;
  select coalesce(jsonb_object_agg(g.estado, g.n), '{}'::jsonb) into v_cont from (select p.estado, count(*) as n from redes.v_levantar_punto p group by 1) g;
  select coalesce(jsonb_agg(jsonb_build_object('codigo', p.codigo, 'servicio', p.servicio, 'tipo', p.tipo, 'tipo_nombre', redes.f_levantar_tipo_nombre(p.tipo), 'observacion', p.observacion,
           'lat', p.lat, 'lon', p.lon, 'precision_m', p.precision_m, 'precision_baja', p.precision_baja, 'registrado_en', p.registrado_en, 'area', p.area,
           'quien', redes.f_levantar_quien(p.autor), 'estado', p.estado, 'estado_nombre', redes.f_levantar_estado_nombre(p.estado), 'estado_desde', p.estado_desde,
           'estado_motivo', p.estado_motivo, 'estado_quien', case when p.estado_autor is not null then redes.f_levantar_quien(p.estado_autor) end,
           'activo', (select m.codigo from redes.activos m where m.id = p.activo_id), 'fotos', p.fotos,
           -- cierre casi automático (regla 4): un activo NUEVO (creado después del reporte) del mismo servicio a pocos metros; el supervisor confirma
           'propuesta', case when p.estado in ('reportado', 'asignado') then (
              select jsonb_build_object('activo', m.codigo, 'tipo', redes.f_tipo_nombre(m.prefijo), 'distancia_m', round(ST_Distance(m.geom::geography, p.geom::geography)::numeric, 1), 'cargado_en', a.creado_en)
                from redes.activo_vigente_mat m join redes.activos a on a.id = m.activo_id
               where not m.retirado and not m.oculto and m.sistema = p.servicio and a.creado_en > p.registrado_en
                 and m.geom && ST_Expand(p.geom, (v_prop + 5) / 100000.0) and ST_DWithin(m.geom::geography, p.geom::geography, v_prop)
               order by ST_Distance(m.geom::geography, p.geom::geography), m.codigo limit 1) end,
           'sector', (select s.nombre from redes.f_sector_de(p.geom) s)) order by p.codigo desc), '[]'::jsonb)
    into v_items
    from (select x.* from redes.v_levantar_punto x
           where (v_est = 'todos' or (v_est = 'abiertos' and x.estado in ('reportado', 'asignado')) or x.estado = v_est) and (v_desp is null or x.codigo < v_desp)
           order by x.codigo desc limit v_lim) p;
  return jsonb_build_object('estado', v_est, 'conteos', v_cont,
    'abiertos', coalesce((v_cont ->> 'reportado')::integer, 0) + coalesce((v_cont ->> 'asignado')::integer, 0),
    'items', v_items, 'siguiente', case when jsonb_array_length(v_items) = v_lim then v_items -> (v_lim - 1) ->> 'codigo' end);
end $$;

-- ---------- Supervisor: cambiar el estado (solo se agregan eventos; nada se borra) ----------
-- asignado (desde reportado) · levantado, con el activo nuevo (desde reportado o asignado) · descartado, con motivo (desde reportado o asignado) ·
-- reabierto, con motivo (desde levantado o descartado: vuelve a «reportado»).
create function public.geoportal_redes_levantar_evento(p_solicitante text, p_codigo text, p_tipo text, p_activo text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'cambian el estado de un activo por levantar'); v_cod text := upper(btrim(coalesce(p_codigo, '')));
        v_mot text := nullif(btrim(coalesce(p_motivo, '')), ''); v_act text := nullif(upper(btrim(coalesce(p_activo, ''))), ''); v_activo bigint; p record; v_id bigint;
begin
  if coalesce(p_tipo, '') not in ('asignado', 'levantado', 'descartado', 'reabierto') then perform tecnica.f_error('Ese cambio de estado no existe'); end if;
  if v_cod !~ '^LEV-[0-9]{6}$' then perform tecnica.f_error('Ese código no es de un activo por levantar'); end if;
  if v_mot is not null and (length(v_mot) < 3 or length(v_mot) > 500) then perform tecnica.f_error('El motivo va de 3 a 500 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtextextended('lev|' || v_cod, 0));
  select * into p from redes.v_levantar_punto x where x.codigo = v_cod;
  if not found then perform tecnica.f_error('Ese activo por levantar no existe', 'P0002'); end if;
  if p_tipo = 'reabierto' then
    if p.estado not in ('levantado', 'descartado') then perform tecnica.f_error('Solo se reabre un punto levantado o descartado', '55000'); end if;
  elsif p.estado not in ('reportado', 'asignado') then perform tecnica.f_error(format('Este punto ya está «%s»: reábralo primero', lower(redes.f_levantar_estado_nombre(p.estado))), '55000');
  elsif p_tipo = 'asignado' and p.estado = 'asignado' then perform tecnica.f_error('Ya está asignado a levantamiento', '55000');
  end if;
  if p_tipo in ('descartado', 'reabierto') and (v_mot is null or length(v_mot) < 10) then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  if p_tipo = 'levantado' then
    if v_act is null then perform tecnica.f_error('Diga con qué activo quedó levantado (su código)'); end if;
    select m.activo_id into v_activo from redes.activo_vigente_mat m where m.codigo = v_act and not m.retirado;
    if v_activo is null then perform tecnica.f_error('Ese activo no existe en la red: publique primero la carga de la capa', 'P0002'); end if;
  elsif v_act is not null then perform tecnica.f_error('El activo solo va al marcar «levantado»');
  end if;
  insert into redes.levantar_eventos (punto_id, tipo, activo_id, motivo, autor) values (p.id, p_tipo, v_activo, v_mot, v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'redes_levantar_' || p_tipo, v_cod, jsonb_build_object('evento', v_id, 'activo', v_act, 'antes', p.estado), p_ip);
  return (select jsonb_build_object('codigo', x.codigo, 'estado', x.estado, 'estado_nombre', redes.f_levantar_estado_nombre(x.estado), 'estado_desde', x.estado_desde, 'activo', v_act)
            from redes.v_levantar_punto x where x.id = p.id);
end $$;

-- ---------- Supervisor: las fotos de un punto (la Edge firma la lectura por 60 s; la lectura queda en la auditoría) ----------
create function public.geoportal_redes_levantar_fotos(p_solicitante text, p_codigo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 've las fotos de un activo por levantar'); v_cod text := upper(btrim(coalesce(p_codigo, ''))); v_id uuid; v_fotos jsonb;
begin
  if v_cod !~ '^LEV-[0-9]{6}$' then perform tecnica.f_error('Ese código no es de un activo por levantar'); end if;
  select p.id into v_id from redes.levantar_puntos p where p.codigo = v_cod;
  if v_id is null then perform tecnica.f_error('Ese activo por levantar no existe', 'P0002'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('n', f.n, 'ruta', f.ruta_storage, 'creado_en', f.creado_en) order by f.n), '[]'::jsonb) into v_fotos from redes.levantar_fotos f where f.punto_id = v_id;
  perform tecnica.f_auditar(v_email, 'redes_levantar_fotos', v_cod, jsonb_build_object('fotos', jsonb_array_length(v_fotos)), p_ip);
  return jsonb_build_object('codigo', v_cod, 'fotos', v_fotos);
end $$;

-- ---------- Supervisor: la hoja de levantamiento (PDF con la hoja membretada): los puntos numerados EN EL ORDEN DEL RECORRIDO ----------
-- Empieza por el punto más al norte y sigue siempre al más cercano que falte. Trae la primera foto de cada punto (la Edge firma la lectura) y la observación
-- (David, 17-nov: en este PDF sí va, le sirve a la cuadrilla). Sin quién reportó y sin datos de suscriptores. La descarga queda en la auditoría.
create function public.geoportal_redes_levantar_hoja(p_solicitante text, p_estado text default 'abiertos', p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'descargan la hoja de levantamiento'); v_est text := coalesce(p_estado, 'abiertos');
        v_max integer := redes.f_param('levantar_hoja_max')::integer; v_ids uuid[]; v_orden uuid[] := '{}'; v_act uuid; v_total integer; v_puntos jsonb;
begin
  if v_est not in ('abiertos', 'reportado', 'asignado') then perform tecnica.f_error('La hoja de levantamiento es de los puntos por levantar'); end if;
  select count(*) into v_total from redes.v_levantar_punto x where (v_est = 'abiertos' and x.estado in ('reportado', 'asignado')) or x.estado = v_est;
  select array_agg(y.id order by y.lat desc, y.lon, y.codigo) into v_ids
    from (select x.id, x.lat, x.lon, x.codigo from redes.v_levantar_punto x
           where (v_est = 'abiertos' and x.estado in ('reportado', 'asignado')) or x.estado = v_est order by x.codigo limit v_max) y;
  if v_ids is not null then
    v_act := v_ids[1];
    loop
      v_orden := v_orden || v_act;
      exit when cardinality(v_orden) >= cardinality(v_ids);
      select q.id into v_act from redes.levantar_puntos q, redes.levantar_puntos c
       where c.id = v_act and q.id = any (v_ids) and q.id <> all (v_orden) order by q.geom <-> c.geom, q.codigo limit 1;
    end loop;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('n', o.n, 'codigo', p.codigo, 'tipo_nombre', redes.f_levantar_tipo_nombre(p.tipo), 'servicio', p.servicio, 'registrado_en', p.registrado_en,
           'lat', p.lat, 'lon', p.lon, 'precision_m', p.precision_m, 'precision_baja', p.precision_baja, 'observacion', p.observacion, 'estado_nombre', redes.f_levantar_estado_nombre(p.estado),
           'sector', (select s.nombre from redes.f_sector_de(p.geom) s),
           'foto', (select f.ruta_storage from redes.levantar_fotos f where f.punto_id = p.id order by f.n limit 1)) order by o.n), '[]'::jsonb)
    into v_puntos from unnest(v_orden) with ordinality o(id, n) join redes.v_levantar_punto p on p.id = o.id;
  perform tecnica.f_auditar(v_email, 'redes_levantar_hoja', null, jsonb_build_object('estado', v_est, 'puntos', jsonb_array_length(v_puntos), 'total', v_total), p_ip);
  return jsonb_build_object('generado_en', clock_timestamp(), 'estado', v_est, 'total', v_total, 'recortada', v_total > jsonb_array_length(v_puntos), 'puntos', v_puntos);
end $$;

-- =====================================================================
-- ETAPA 3 · Parte 2: modo «Remuneración» del geovisor (antes «10-bis»). SOLO supervisor de distribución y administrador (es término tarifario: el operador
-- y el supervisor de planta no ven el modo, ni su leyenda, ni su tesela). Fuente: el amarre del Corte 10 (redes.val_amarre, con la hoja de alcantarillado
-- vigente por el parámetro) y la misma regla de redes.f_ficha_regulatorio. Nada nuevo se carga.
--   remunerado: tiene fila en la valoración vigente · no_remunerado: tiene fila, pero está fuera de servicio o es obra de un tercero (SIVA) ·
--   sin_fila: en la red, sin amarre a la valoración (o sin fila que le corresponda) · proyectado: del Plan, no construido.
-- =====================================================================
create function redes.f_remuneracion_estado(p_con boolean, p_aparte boolean, p_proyectado boolean) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case when p_con then 'remunerado' when p_aparte then 'no_remunerado' when p_proyectado then 'proyectado' else 'sin_fila' end
$$;

-- La leyenda y los conteos del modo (y si hay amarre cargado)
create function public.geoportal_redes_remuneracion(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el modo «Remuneración»'); v_am bigint := redes.f_ref_vigente('val_amarre'); v_val bigint := redes.f_ref_vigente('valoracion');
        v_hoja text := redes.f_val_hoja_alc(); v_pref text[] := redes.f_val_prefijos(); v_cont jsonb;
begin
  if v_am is not null and v_val is not null then
    select coalesce(jsonb_object_agg(g.estado, g.n), '{}'::jsonb) into v_cont from (
      select redes.f_remuneracion_estado(coalesce(r.con, false), coalesce(r.aparte, false), coalesce(r.proy, false) or m.estado_codigo = 'proyectado') as estado, count(*) as n
        from redes.activo_vigente_mat m
        left join (select am.activo_id, bool_or(am.situacion = 'con_fila') as con, bool_or(am.situacion like 'aparte\_%') as aparte, bool_or(am.situacion = 'proyectado') as proy
                     from redes.val_amarre am where am.carga_id = v_am and am.val_carga_id = v_val and am.hoja in ('acueducto', v_hoja) group by am.activo_id) r on r.activo_id = m.activo_id
       where not m.retirado and not m.oculto and (m.prefijo = any (v_pref) or r.activo_id is not null) group by 1) g;
  end if;
  return jsonb_build_object('cargado', v_am is not null and v_val is not null, 'version', v_am,
    'rotulo', 'Valoración técnica 2019, propuesta',
    'nota', 'Remuneración vía tarifa según la Valoración Técnica de 2019 (Res. CRA 688 de 2014), que es una PROPUESTA: su adopción no está confirmada.',
    'conteos', coalesce(v_cont, '{}'::jsonb),
    'leyenda', jsonb_build_array(
      jsonb_build_object('clave', 'remunerado', 'nombre', 'Remunerado', 'significa', 'Tiene fila en la valoración vigente'),
      jsonb_build_object('clave', 'no_remunerado', 'nombre', 'No remunerado', 'significa', 'Tiene fila, pero está fuera de servicio o es obra de un tercero (SIVA)'),
      jsonb_build_object('clave', 'sin_fila', 'nombre', 'Sin fila', 'significa', 'En la red, sin amarre a la valoración'),
      jsonb_build_object('clave', 'proyectado', 'nombre', 'Proyectado', 'significa', 'Del Plan, no construido')));
end $$;

-- La tesela del modo (aparte de la del geovisor, que no se toca): la misma red, con el estado de remuneración de cada activo
create function public.geoportal_redes_geovisor_mvt_remuneracion(p_solicitante text, p_z integer, p_x integer, p_y integer) returns text
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el modo «Remuneración»'); v_am bigint := redes.f_ref_vigente('val_amarre'); v_val bigint := redes.f_ref_vigente('valoracion');
        v_hoja text := redes.f_val_hoja_alc(); v_pref text[] := redes.f_val_prefijos(); v_env geometry; v_env4326 geometry; v bytea;
        z_min numeric := redes.f_param('geovisor_zoom_min'); z_red numeric := redes.f_param('geovisor_zoom_red_completa'); z_nod numeric := redes.f_param('geovisor_zoom_nodos');
        d_acu numeric := redes.f_param('geovisor_diam_principal_acu_mm'); d_alc numeric := redes.f_param('geovisor_diam_principal_alc_mm');
begin
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < z_min or v_am is null or v_val is null then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4326 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'remuneracion', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, m.codigo, m.prefijo, m.sistema,
           case GeometryType(m.geom) when 'POINT' then 'nodo' when 'POLYGON' then 'area' when 'MULTIPOLYGON' then 'area' else 'tramo' end as forma,
           redes.f_remuneracion_estado(coalesce(r.con, false), coalesce(r.aparte, false), coalesce(r.proy, false) or m.estado_codigo = 'proyectado') as rem
      from redes.activo_vigente_mat m
      left join lateral (select count(*) as n, bool_or(am.situacion = 'con_fila') as con, bool_or(am.situacion like 'aparte\_%') as aparte, bool_or(am.situacion = 'proyectado') as proy
                           from redes.val_amarre am
                          where am.activo_id = m.activo_id and am.carga_id = v_am and am.val_carga_id = v_val and am.hoja in ('acueducto', v_hoja)) r on true
     where not m.retirado and not m.oculto and m.geom && v_env4326 and (m.prefijo = any (v_pref) or r.n > 0)
       and case
             when m.prefijo in ('TAN', 'PTA', 'CAP', 'DES', 'PTR') then true
             when GeometryType(m.geom) = 'POINT' then p_z >= z_nod
             when p_z >= z_red then true
             else m.prefijo in ('CON', 'ADU', 'INT')
                  or (m.sistema = 'acueducto' and m.diametro_mm >= d_acu) or (m.sistema = 'alcantarillado' and m.diametro_mm >= d_alc)
           end) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $$;

-- La tarjeta del activo en este modo: «Remunerado vía tarifa: sí / no», el motivo y la fila (o filas) de la valoración. La misma regla de la ficha.
create function public.geoportal_redes_remuneracion_tarjeta(p_solicitante text, p_codigo text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el modo «Remuneración»'); v_cod text := upper(btrim(coalesce(p_codigo, ''))); m redes.activo_vigente_mat%rowtype; j jsonb; v_sit text;
begin
  if v_cod !~ '^[A-Z]{3}-[0-9]{1,8}$' then perform tecnica.f_error('Ese código de activo no es válido'); end if;
  select * into m from redes.activo_vigente_mat x where x.codigo = v_cod and not x.retirado and not x.oculto;
  if not found then perform tecnica.f_error('Ese activo no existe', 'P0002'); end if;
  j := redes.f_ficha_regulatorio(m.activo_id, m.prefijo);
  v_sit := j ->> 'situacion';
  return jsonb_strip_nulls(jsonb_build_object('codigo', m.codigo, 'tipo', redes.f_tipo_nombre(m.prefijo), 'sistema', m.sistema,
    'cargado', redes.f_ref_vigente('val_amarre') is not null,
    'estado', case when j is null then 'no_aplica' when v_sit = 'con_fila' then 'remunerado' when v_sit = 'aparte' then 'no_remunerado'
                   when v_sit = 'proyectado' or m.estado_codigo = 'proyectado' then 'proyectado' else 'sin_fila' end,
    'remunerado', coalesce((j ->> 'remunerado')::boolean, false),
    'rotulo', 'Valoración técnica 2019, propuesta',
    'motivo', case when j is null then 'Este tipo de activo no entra en la valoración.' else j ->> 'texto' end,
    'filas', (select jsonb_agg(jsonb_build_object('hoja', f ->> 'hoja', 'n', (f ->> 'n')::integer, 'nombre', f ->> 'nombre', 'caracteristica', f ->> 'caracteristica',
                                'cantidad', (f ->> 'cantidad')::numeric, 'unidad', f ->> 'unidad', 'anio_operacion', (f ->> 'anio_operacion')::integer) order by (f ->> 'n')::integer)
                from jsonb_array_elements(j -> 'filas') f)));
end $$;
