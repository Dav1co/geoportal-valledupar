-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 26 — FUNCIONES NUEVAS
--   · redes.f_estado_contrato, redes.f_refrescar_contratos_capa y redes.f_contratos_capa_al_dia: la capa de contratos (derivada, sin datos personales).
--   · redes.f_muestreo_calidad: el último cloro y la última turbiedad de un punto frente a sus rangos (respuesta 4 de David al 6a).
--   · public.geoportal_redes_geovisor_mvt_contratos: la tesela de los contratos (número, uso, estado, consumo promedio y años del medidor).
--   · public.geoportal_redes_contrato_tarjeta: la tarjeta del contrato al tocarlo (§30.1), con nombre, dirección y barrio; lectura auditada; sin teléfono ni deuda.
--   · public.geoportal_redes_vista_compartir y _vista_abrir: compartir la vista con un enlace (§30.2).
-- =====================================================================

-- ---------- Capa de contratos ----------
create function redes.f_estado_contrato(p text) returns text language sql immutable set search_path = pg_catalog as $$
  select case when nullif(btrim(coalesce(p, '')), '') is null then 'sin_dato' when upper(btrim(p)) like 'RETIR%' then 'retirado'
              when upper(btrim(p)) like 'ACTIV%' then 'activo' else 'otro' end $$;

-- Rehace la capa entera: un punto por contrato (el predio de menor id, como redes.contrato_tramo); sin el comodín (99999999) ni el «0».
create function redes.f_refrescar_contratos_capa() returns integer
language plpgsql security definer set search_path = public, redes, bi_interno, extensions, pg_temp as $$
declare t0 timestamptz := clock_timestamp(); n integer;
begin
  delete from redes.contratos_capa;
  insert into redes.contratos_capa (contrato, geom, uso, estado, consumo_prom, medidor_anios)
  select c.cod_usuario, c.geom,
         coalesce(nullif(btrim(f.uso), '(sin dato)'), nullif(regexp_replace(btrim(coalesce(cs.categoria, '')), '^-?[0-9]+\s+', ''), '')),
         redes.f_estado_contrato(cs.estado), f.cons_prom, f.medidor_anios
    from (select distinct on (cv.cod_usuario) cv.cod_usuario, cv.geom from public.catastro_valledupar cv
           where cv.cod_usuario ~ '^[0-9]{1,12}$' and cv.cod_usuario not in ('0', '99999999') and cv.geom is not null
           order by cv.cod_usuario, cv.id) c
    left join bi_interno.ficha_contrato f on f.contrato = c.cod_usuario
    left join lateral (select s.estado, s.categoria from public.cartera_suscripcion s where s.contrato = c.cod_usuario order by s.periodo_carga desc nulls last limit 1) cs on true;
  get diagnostics n = row_count;
  insert into redes.contratos_capa_estado (id, firma, filas, calculado_en, duracion_ms)
  values (1, coalesce((select calculado_en::text from bi_interno.ficha_contrato_estado where id = 1), 'sin ficha'), n, clock_timestamp(),
          (extract(epoch from clock_timestamp() - t0) * 1000)::integer)
  on conflict (id) do update set firma = excluded.firma, filas = excluded.filas, calculado_en = excluded.calculado_en, duracion_ms = excluded.duracion_ms;
  return n;
end $$;

-- La rehace si cambió la ficha del contrato (cálculo mensual) o si tiene más de geovisor_contratos_horas. Si otra sesión la está rehaciendo, no espera.
create function redes.f_contratos_capa_al_dia() returns boolean
language plpgsql security definer set search_path = public, redes, bi_interno, pg_temp as $$
declare e redes.contratos_capa_estado%rowtype;
begin
  select * into e from redes.contratos_capa_estado where id = 1;
  if found and e.firma = coalesce((select calculado_en::text from bi_interno.ficha_contrato_estado where id = 1), 'sin ficha')
     and e.calculado_en > clock_timestamp() - make_interval(hours => floor(redes.f_param('geovisor_contratos_horas'))::integer) then
    return false;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('redes.contratos_capa')) then return false; end if;
  perform redes.f_refrescar_contratos_capa();
  return true;
end $$;

-- ---------- Calidad de un punto de muestreo: el último resultado (no excluido) de cada variable que colorea, frente a su rango ----------
-- Rango: el de la variable de Muestreo si lo tiene (por punto o general); si no, el general de la variable de Salida; si Salida solo tiene rangos por planta,
-- el más estricto de ellos. Estado: «fuera» si alguno reciente se sale; «dentro» si los recientes con rango están dentro; «sin_rango»; «sin_muestra».
create function redes.f_muestreo_calidad(p_punto_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_dias integer := floor(redes.f_param('geovisor_muestreo_dias'))::integer; m record; u record; rg record; v_med jsonb := '[]'::jsonb;
        v_reciente boolean; v_dentro boolean; v_fuente text; n_rec integer := 0; n_rango integer := 0; n_fuera integer := 0;
begin
  for m in select r.variable_muestreo, r.variable_salida, v.id as vid, v.nombre, v.unidad, s.id as sid
             from redes.muestreo_rangos r join tecnica.variables v on v.codigo = r.variable_muestreo join tecnica.variables s on s.codigo = r.variable_salida order by r.orden loop
    select e.valor, e.muestra_ts into u from tecnica.v_registros_estado e
     where e.formulario::text = 'muestreo' and e.punto_id = p_punto_id and e.variable_id = m.vid and not e.excluido
     order by e.muestra_ts desc, e.id desc limit 1;
    if not found then continue; end if;
    v_fuente := 'muestreo';
    select x.ref_min, x.ref_max into rg from tecnica.f_referencia_vigente(m.vid, null, p_punto_id) x;
    if not found or (rg.ref_min is null and rg.ref_max is null) then
      v_fuente := 'salida';
      select x.ref_min, x.ref_max into rg from tecnica.f_referencia_vigente(m.sid, null, null) x;
      if not found or (rg.ref_min is null and rg.ref_max is null) then
        select max(r.ref_min) as ref_min, min(r.ref_max) as ref_max into rg from tecnica.referencias r where r.activa and r.variable_id = m.sid and r.punto_id is null;
      end if;
    end if;
    v_reciente := u.muestra_ts >= clock_timestamp() - make_interval(days => v_dias);
    v_dentro := case when rg.ref_min is null and rg.ref_max is null then null
                     else (rg.ref_min is null or u.valor >= rg.ref_min) and (rg.ref_max is null or u.valor <= rg.ref_max) end;
    if v_reciente then
      n_rec := n_rec + 1;
      if v_dentro is not null then n_rango := n_rango + 1; if not v_dentro then n_fuera := n_fuera + 1; end if; end if;
    end if;
    v_med := v_med || jsonb_build_array(jsonb_build_object('variable', m.variable_muestreo, 'nombre', m.nombre, 'unidad', m.unidad, 'valor', u.valor, 'cuando', u.muestra_ts,
               'reciente', v_reciente, 'min', rg.ref_min, 'max', rg.ref_max, 'dentro', v_dentro,
               'rango', case when rg.ref_min is null and rg.ref_max is null then null else v_fuente end));
  end loop;
  return jsonb_build_object('calidad', case when n_rec = 0 then 'sin_muestra' when n_fuera > 0 then 'fuera' when n_rango > 0 then 'dentro' else 'sin_rango' end, 'medidas', v_med);
end $$;

-- ---------- Tesela de contratos (supervisores y administrador; el operador en solo lectura no la ve) ----------
create function public.geoportal_redes_geovisor_mvt_contratos(p_solicitante text, p_z integer, p_x integer, p_y integer) returns text
language plpgsql stable security definer set search_path = public, redes, extensions, pg_temp as $$
declare a record; v_env geometry; v bytea;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La capa de contratos es para supervisores' using errcode = '42501'; end if;
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < redes.f_param('geovisor_zoom_contratos') then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  select ST_AsMVT(t, 'contratos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(c.geom, 3857), v_env, 4096, 32, true) as geom, c.contrato, coalesce(c.uso, '') as uso, c.estado,
           c.consumo_prom::real as consumo, c.medidor_anios as medidor_anios
      from redes.contratos_capa c where c.geom && ST_Transform(v_env, 4326)) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $$;

-- ---------- Tarjeta del contrato (§30.1): se pide al tocarlo; el nombre y la dirección son dato personal: solo en pantalla, lectura auditada ----------
create function public.geoportal_redes_contrato_tarjeta(p_solicitante text, p_contrato text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, bi_interno, pg_temp as $$
declare a record; c redes.contratos_capa%rowtype; cs record; pr record; f record; v_c text := btrim(coalesce(p_contrato, ''));
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;
  if v_c !~ '^[0-9]{1,12}$' then perform tecnica.f_error('Escriba solo los números del contrato'); end if;
  select * into c from redes.contratos_capa where contrato = v_c;
  if not found then perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002'); end if;
  select s.nombre, s.estado, s.categoria, s.direccion, s.barrio, s.periodo_carga into cs
    from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select cv.direccion, cv.barrio into pr from public.catastro_valledupar cv where cv.cod_usuario = v_c order by cv.id limit 1;
  select fc.periodo_ultimo, fc.uso, fc.consumo_meses, fc.cons_prom, fc.meses_con_lectura, fc.medidor_anios into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  -- la lectura queda registrada: quién, cuándo y qué contrato (NUNCA el nombre ni la dirección)
  perform tecnica.f_auditar(a.email, 'redes_contrato_tarjeta', v_c, jsonb_build_object('datos', 'nombre, dirección y barrio', 'desde', 'geovisor'), p_ip);
  return jsonb_build_object(
    'contrato', v_c,
    'estado', c.estado, 'estado_texto', nullif(btrim(cs.estado), ''),
    'uso', c.uso,
    'consumo', case when f.periodo_ultimo is not null then jsonb_build_object(
        'periodo_ultimo', f.periodo_ultimo, 'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura,
        'meses', (select coalesce(jsonb_agg(jsonb_build_object('periodo', m ->> 'periodo', 'm3', m -> 'm3', 'sin_dato', coalesce((m ->> 'sin_dato')::boolean, false),
                                                               'lectura_real', coalesce((m ->> 'lectura_real')::boolean, false)) order by k), '[]'::jsonb)
                    from jsonb_array_elements(f.consumo_meses) with ordinality x(m, k))) end,
    'medidor_anios', f.medidor_anios,
    'tramo', (select v.codigo from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id where t.contrato = v_c),
    'suscriptor', jsonb_build_object(                                  -- DATO PERSONAL: solo en pantalla
      'nombre', nullif(btrim(cs.nombre), ''),
      'direccion', coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')),
      'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), ''))),
    'corte', cs.periodo_carga);
end $$;

-- ---------- Compartir la vista (§30.2) ----------
-- La guardan los supervisores y el administrador (el operador en solo lectura no comparte). Solo capas que existen y que la persona ve; sin datos personales.
create function public.geoportal_redes_vista_compartir(p_solicitante text, p_vista jsonb) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, pg_temp as $$
declare a record; v jsonb := coalesce(p_vista, '{}'::jsonb); v_capas text[]; v_aten text[]; v_malas text[]; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        v_modo text := coalesce(v #>> '{periodo,modo}', 'hoy'); v_desde date; v_hasta date; v_lon numeric; v_lat numeric; v_zoom numeric; v_id text;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'El geovisor en solo lectura no comparte vistas' using errcode = '42501'; end if;
  if jsonb_typeof(v) <> 'object' or jsonb_typeof(v -> 'capas') <> 'array' then perform tecnica.f_error('La vista no es válida'); end if;
  select array_agg(x order by x) into v_capas from (select distinct jsonb_array_elements_text(v -> 'capas') x) z;
  v_capas := coalesce(v_capas, '{}');
  select array_agg(x) into v_aten from (select distinct jsonb_array_elements_text(coalesce(v -> 'atenuadas', '[]'::jsonb)) x) z;
  v_aten := coalesce(v_aten, '{}');
  select array_agg(x) into v_malas from unnest(v_capas || v_aten) x
   where not exists (select 1 from redes.geovisor_capas g where g.codigo = x and g.activa and g.fuente <> 'preparada');
  if v_malas is not null then perform tecnica.f_error(format('Capas que no existen en el geovisor: %s', array_to_string(v_malas, ', '))); end if;
  if coalesce(v ->> 'colores', '') not in ('tipo', 'material', 'edad') then perform tecnica.f_error('Los colores son por tipo, material o edad'); end if;
  if v_modo not in ('hoy', 'semana', 'rango') then perform tecnica.f_error('Las fechas son hoy, 7 días o un rango'); end if;
  if v_modo = 'rango' then
    begin
      v_desde := (v #>> '{periodo,desde}')::date; v_hasta := (v #>> '{periodo,hasta}')::date;
    exception when others then perform tecnica.f_error('Las fechas del rango no son válidas');
    end;
    if v_desde is null or v_hasta is null or v_desde > v_hasta or v_hasta > v_hoy
       or v_desde < (v_hasta - make_interval(months => floor(redes.f_param('geovisor_rango_meses'))::integer))::date then
      perform tecnica.f_error(format('El rango de fechas no es válido (hasta hoy y de máximo %s meses)', floor(redes.f_param('geovisor_rango_meses'))));
    end if;
  end if;
  if jsonb_typeof(v -> 'lon') <> 'number' or jsonb_typeof(v -> 'lat') <> 'number' or jsonb_typeof(v -> 'zoom') <> 'number' then perform tecnica.f_error('Falta el centro o el zoom'); end if;
  v_lon := round((v ->> 'lon')::numeric, 6); v_lat := round((v ->> 'lat')::numeric, 6); v_zoom := round((v ->> 'zoom')::numeric, 2);
  if v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') or v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') then
    perform tecnica.f_error('El centro del mapa está fuera de Valledupar');
  end if;
  if v_zoom not between 10 and 20 then perform tecnica.f_error('El zoom no es válido'); end if;
  loop
    v_id := substr(md5(random()::text || clock_timestamp()::text || a.email), 1, 10);
    exit when not exists (select 1 from redes.vistas_compartidas where id = v_id);
  end loop;
  insert into redes.vistas_compartidas (id, capas, colores, periodo, lon, lat, zoom, atenuadas, autor)
  values (v_id, v_capas, v ->> 'colores', jsonb_build_object('modo', v_modo, 'desde', v_desde, 'hasta', v_hasta), v_lon, v_lat, v_zoom, v_aten, a.email);
  perform tecnica.f_auditar(a.email, 'redes_vista_compartir', v_id, jsonb_build_object('capas', v_capas), null);
  return jsonb_build_object('id', v_id);
end $$;

-- Abrir un enlace: quien lo abre ya inició sesión (lo exige la Edge) y debe tener el geovisor; ve solo las capas para las que tiene permiso.
-- Al operador en solo lectura se le abren las actividades de hoy, aunque el enlace diga otras fechas.
create function public.geoportal_redes_vista_abrir(p_solicitante text, p_id text) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, pg_temp as $$
declare a record; v redes.vistas_compartidas%rowtype; v_ok text[]; v_omit text[]; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; v_modo text;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if coalesce(p_id, '') !~ '^[a-z0-9]{10}$' then perform tecnica.f_error('El enlace no es válido'); end if;
  select * into v from redes.vistas_compartidas where id = p_id;
  if not found then perform tecnica.f_error('Ese enlace no existe', 'P0002'); end if;
  select array_agg(x order by x) filter (where ok), array_agg(nombre order by x) filter (where not ok) into v_ok, v_omit
    from (select x, coalesce(g.nombre, x) as nombre, coalesce(g.activa and g.fuente <> 'preparada' and (a.completo or not g.solo_completo), false) as ok
            from unnest(v.capas) x left join redes.geovisor_capas g on g.codigo = x) z;
  v_modo := case when not a.completo then 'hoy' else v.periodo ->> 'modo' end;
  perform tecnica.f_auditar(a.email, 'redes_vista_abrir', v.id, jsonb_build_object('omitidas', coalesce(cardinality(v_omit), 0)), null);
  return jsonb_build_object('id', v.id, 'capas', to_jsonb(coalesce(v_ok, '{}')), 'omitidas', to_jsonb(coalesce(v_omit, '{}')), 'colores', v.colores,
    'periodo', jsonb_build_object('modo', v_modo,
                                  'desde', case v_modo when 'hoy' then v_hoy when 'semana' then v_hoy - 6 else (v.periodo ->> 'desde')::date end,
                                  'hasta', case v_modo when 'rango' then (v.periodo ->> 'hasta')::date else v_hoy end),
    'lon', v.lon, 'lat', v.lat, 'zoom', v.zoom, 'atenuadas', to_jsonb(v.atenuadas), 'creada_en', v.creado_en,
    'fechas_cambiadas', not a.completo and v.periodo ->> 'modo' <> 'hoy');
end $$;
