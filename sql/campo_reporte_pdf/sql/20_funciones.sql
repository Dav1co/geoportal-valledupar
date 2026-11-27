-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov) · 20 — FUNCIONES
-- Internas (nadie de la API): f_ran_autorizar, f_ran_persona, f_ran_contenido, f_ran_destino, f_ran_mapa.
-- RPC (solo service_role, desde la Edge geoportal-campo): geoportal_campo_ran_datos, geoportal_campo_ran_registrar, geoportal_campo_ran_obtener.
-- Reglas (David, 27-nov): sin firmas; solo supervisión de Comercial y administrador (los demás, 403); nunca los datos sensibles ni las rutas en el PDF;
-- nombre del operario (el correo solo si no tiene nombre); versión nueva solo si cambia el sello; mapa vectorial armado en el servidor.
-- =====================================================================

-- Supervisión de Comercial (dashboard_campo) o administrador; después, que exista y que sea de «Reportar anomalía» (tipo general: los formatos tienen su PDF).
create function campo.f_ran_autorizar(p_solicitante text, p_id uuid) returns text
language plpgsql security definer set search_path = public, campo, pg_temp as $$
declare v_email text; v_cod text;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select t.codigo into v_cod from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id where r.id = p_id;
  if v_cod is null then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  if not campo.f_tipo_general(v_cod) then
    perform campo.f_error('Ese reporte es un formato: su PDF es el del formato, no el de «Reportar anomalía»');
  end if;
  return v_email;
end $$;

-- Nombre de la persona (lista blanca); el correo solo si no tiene nombre (David, 27-nov)
create function campo.f_ran_persona(p_email text) returns text
language sql stable security definer set search_path = public, campo, pg_temp as $$
  select coalesce((select nullif(btrim(b.nombre), '') from public.geoportal_lista_blanca b where b.email = lower(btrim(p_email)) limit 1), lower(btrim(p_email)))
$$;

-- Todo lo que va al PDF (menos el mapa y el pie de generación). Su sha256 es el sello: si cambia (estado, historial, datos), hay versión nueva.
-- NUNCA lee campo.reporte_datos_sensibles. Las rutas de las fotos van solo para que la Edge las lea; el PDF no las imprime.
create function campo.f_ran_contenido(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, campo, acta, pg_temp as $$
declare v campo.v_reportes_estado%rowtype; v_rr campo.reporte_registro; v_dc campo.reporte_direccion_contrato; r jsonb;
        f_hora constant text := 'DD/MM/YYYY HH24:MI';
begin
  select * into v from campo.v_reportes_estado where id = p_id;
  if not found then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  select * into v_rr from campo.reporte_registro where reporte_id = p_id;
  select * into v_dc from campo.reporte_direccion_contrato where reporte_id = p_id;
  select jsonb_build_object(
    'identificador', 'RAN-' || lpad(v.seq::text, 6, '0'),
    'grupo', g.nombre, 'tipo', t.nombre, 'subtipo', s.nombre,
    'estado', coalesce((select e.nombre from campo.estados_reporte e where e.codigo = v.estado), v.estado),
    'oculto', v.oculto, 'riesgo_inmediato', v.riesgo_inmediato, 'fuera_de_zona', v.fuera_de_zona,
    'contrato', v.contrato, 'contrato_verificado', v.contrato_verificado,
    'direccion_contrato', case when v_dc.reporte_id is not null then jsonb_build_object(
        'comercial', v_dc.direccion_comercial, 'barrio_comercial', v_dc.barrio_comercial, 'catastro', v_dc.direccion_catastro, 'barrio_catastro', v_dc.barrio_catastro) end,
    'terreno', case when v_rr.reporte_id is not null and coalesce(v_rr.direccion, v_rr.barrio, v_rr.referencia) is not null then jsonb_build_object(
        'direccion', v_rr.direccion, 'barrio', v_rr.barrio, 'referencia', v_rr.referencia) end,
    'ubicacion', jsonb_build_object('lat', v.lat, 'lon', v.lon, 'precision_m', v.precision_m,
        'xy_digitado', coalesce(v_rr.xy_manual, false), 'sin_ubicacion_dispositivo', v_rr.reporte_id is not null and v_rr.lat_registro is null,
        'lat_registro', v_rr.lat_registro, 'lon_registro', v_rr.lon_registro, 'precision_registro_m', v_rr.precision_registro_m),
    'descripcion', v.descripcion,
    'reporto', campo.f_ran_persona(v.autor),
    'inicio', to_char(v.inicio_en at time zone 'America/Bogota', f_hora) || case v.inicio_origen when 'dispositivo' then ' (celular)' when 'servidor' then ' (hora del servidor)' else '' end,
    'fin', to_char(v.registrado_en at time zone 'America/Bogota', f_hora),
    'duracion', case when v.inicio_en is null or v.registrado_en < v.inicio_en then null
                     else (select case when s < 60 then s || ' s' when s < 3600 then (s / 60) || ' min'
                                       else (s / 3600) || ' h ' || lpad(((s % 3600) / 60)::text, 2, '0') || ' min' end
                             from (select floor(extract(epoch from v.registrado_en - v.inicio_en))::bigint as s) q) end,
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', f.orden, 'ruta', f.ruta_storage, 'bytes', f.tamano_bytes,
                         'etiqueta', coalesce(case when f.etiqueta = 'adicional' then 'Adicional' else (select tf.nombre from campo.tipo_fotos tf where tf.tipo_id = v.tipo_id and tf.codigo = f.etiqueta) end,
                                              'Foto ' || f.orden)
                                     || case f.origen when 'galeria' then ' · adjuntada desde la galería' when 'archivo' then ' · adjuntada desde un archivo' else ' · tomada con la cámara' end)
                         order by f.orden) from campo.reporte_fotos f where f.reporte_id = p_id), '[]'::jsonb),
    'historial', jsonb_build_array(jsonb_build_object('fecha', to_char(v.registrado_en at time zone 'America/Bogota', f_hora), 'texto', 'Reportado', 'quien', campo.f_ran_persona(v.autor)))
      || coalesce((select jsonb_agg(jsonb_build_object('fecha', to_char(e.creado_en at time zone 'America/Bogota', f_hora),
                     'texto', case e.tipo_evento
                                when 'cambio_estado' then 'Cambio de estado → ' || coalesce((select x.nombre from campo.estados_reporte x where x.codigo = e.estado_nuevo), e.estado_nuevo)
                                when 'ocultar' then 'Se ocultó el reporte'
                                when 'reincluir' then 'Se reincluyó el reporte'
                                when 'vincular_duplicado' then 'Se vinculó como duplicado de ' || coalesce((select 'RAN-' || lpad(o.seq::text, 6, '0') from campo.reportes o where o.id = e.reporte_original_id), 'otro reporte')
                                when 'nota' then 'Nota'
                                when 'vincular_acta' then 'Se vinculó el acta ' || coalesce((select a.consecutivo from acta.actas a where a.id = e.acta_id), '')
                                else e.tipo_evento end
                              || coalesce(' · ' || nullif(btrim(e.motivo), ''), ''),
                     'quien', campo.f_ran_persona(e.autor)) order by e.id)
                     from campo.reporte_eventos e where e.reporte_id = p_id), '[]'::jsonb)
  ) into r
  from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id left join campo.subtipos_reporte s on s.id = v.subtipo_id
  where t.id = v.tipo_id;
  return r;
end $$;

-- Versión, nombre y ruta para un sello: la versión ya registrada con ese sello, o la siguiente
create function campo.f_ran_destino(p_id uuid, p_sello text) returns jsonb
language plpgsql stable security definer set search_path = public, campo, pg_temp as $$
declare v_r campo.reportes; v_doc campo.reporte_pdf; v_ver integer; v_nombre text;
begin
  select * into v_r from campo.reportes where id = p_id;
  select * into v_doc from campo.reporte_pdf where reporte_id = p_id and sello = p_sello;
  v_ver := coalesce(v_doc.version, (select coalesce(max(version), 0) + 1 from campo.reporte_pdf where reporte_id = p_id));
  if v_ver > 99 then perform campo.f_error('Este reporte ya tiene 99 versiones de PDF', '55000'); end if;
  v_nombre := campo.f_nombre_pdf(v_r.registrado_en, 'RAN', lpad(v_r.seq::text, 6, '0'), v_ver);
  return jsonb_build_object('version', v_ver, 'nombre', v_nombre,
    'ruta', 'campo/' || to_char(v_r.registrado_en at time zone 'America/Bogota', 'YYYY-MM') || '/' || p_id || '/' || v_nombre,
    'documento', case when v_doc.id is not null then jsonb_build_object('nombre', v_doc.nombre, 'ruta', v_doc.ruta, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes,
                   'version', v_doc.version, 'generado_en', v_doc.generado_en) end);
end $$;

-- Mapa pequeño, vectorial, en metros (MAGNA-SIRGAS Bogotá, 3116) relativo al punto del reporte: ventana de 400 × 200 m con las redes de acueducto y alcantarillado
-- recortadas y simplificadas (0,5 m) y los predios. Usa los índices GiST de producción (idx_redes_acu_geom, idx_redes_alc_geom, idx_predcom_geom_n) por el filtro &&.
-- Topes: 1.500 trozos de red y 3.000 predios. Sin teselas ni servicios externos.
create function campo.f_ran_mapa(p_lat numeric, p_lon numeric, p_lat_reg numeric default null, p_lon_reg numeric default null) returns jsonb
language plpgsql stable security definer set search_path = public, campo, pg_temp as $$
declare v_c geometry; v_x0 double precision; v_y0 double precision; v_env geometry; v_env_g geometry; v_lin jsonb; v_pred jsonb; v_reg jsonb;
        c_ax constant double precision := 200; c_ay constant double precision := 100;
begin
  if p_lat is null or p_lon is null then return null; end if;
  v_c := st_transform(st_setsrid(st_makepoint(p_lon::double precision, p_lat::double precision), 4326), 3116);
  v_x0 := st_x(v_c); v_y0 := st_y(v_c);
  v_env := st_makeenvelope(v_x0 - c_ax, v_y0 - c_ay, v_x0 + c_ax, v_y0 + c_ay, 3116);
  v_env_g := st_transform(v_env, 4326);
  with l as (
    select 'acueducto'::text as capa, a.geom from public.redes_acueducto a where a.geom && v_env_g
    union all
    select 'alcantarillado', b.geom from public.redes_alcantarillado b where b.geom && v_env_g
  ), c as (
    select l.capa, (st_dump(st_collectionextract(st_simplify(st_intersection(st_transform(l.geom, 3116), v_env), 0.5), 2))).geom as g from l
  )
  select coalesce(jsonb_agg(jsonb_build_object('capa', x.capa, 'p', st_asgeojson(st_translate(x.g, -v_x0, -v_y0), 1)::jsonb -> 'coordinates') order by x.capa), '[]'::jsonb) into v_lin
    from (select c.capa, c.g from c where not st_isempty(c.g) and st_npoints(c.g) >= 2 limit 1500) x;
  select coalesce(jsonb_agg(jsonb_build_array(round((st_x(x.t) - v_x0)::numeric, 1), round((st_y(x.t) - v_y0)::numeric, 1))), '[]'::jsonb) into v_pred
    from (select st_transform(p.geom, 3116) as t from public.predios_comercial p where p.geom && v_env_g limit 3000) x
   where st_intersects(x.t, v_env);
  if p_lat_reg is not null and p_lon_reg is not null then
    select jsonb_build_array(round((st_x(q) - v_x0)::numeric, 1), round((st_y(q) - v_y0)::numeric, 1)) into v_reg
      from (select st_transform(st_setsrid(st_makepoint(p_lon_reg::double precision, p_lat_reg::double precision), 4326), 3116) as q) z;
  end if;
  return jsonb_build_object('ancho_m', 2 * c_ax, 'alto_m', 2 * c_ay, 'lineas', v_lin, 'predios', v_pred, 'registro', v_reg);
end $$;

-- RPC 1: lo que la Edge necesita para armar el PDF (o para saber que ya existe el de este sello). Lectura: no audita (audita registrar u obtener).
create function public.geoportal_campo_ran_datos(p_solicitante text, p_reporte_id uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $$
declare v_email text; v_cont jsonb; v_sello text; v_dest jsonb;
begin
  v_email := campo.f_ran_autorizar(p_solicitante, p_reporte_id);
  v_cont := campo.f_ran_contenido(p_reporte_id);
  v_sello := encode(sha256(convert_to(v_cont::text, 'UTF8')), 'hex');
  v_dest := campo.f_ran_destino(p_reporte_id, v_sello);
  return v_cont || v_dest || jsonb_build_object('reporte_id', p_reporte_id, 'sello', v_sello,
    'mapa', case when v_dest -> 'documento' = 'null'::jsonb then campo.f_ran_mapa((v_cont -> 'ubicacion' ->> 'lat')::numeric, (v_cont -> 'ubicacion' ->> 'lon')::numeric,
              case when (v_cont -> 'ubicacion' ->> 'xy_digitado')::boolean then (v_cont -> 'ubicacion' ->> 'lat_registro')::numeric end,
              case when (v_cont -> 'ubicacion' ->> 'xy_digitado')::boolean then (v_cont -> 'ubicacion' ->> 'lon_registro')::numeric end) end,
    'generado_por', campo.f_ran_persona(v_email), 'generado_en', to_char(clock_timestamp() at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI'));
end $$;

-- RPC 2: la Edge ya subió el PDF de este sello: queda la versión (solo inserción) y la auditoría. Si el reporte cambió mientras tanto, 409 y se vuelve a pedir.
create function public.geoportal_campo_ran_registrar(p_solicitante text, p_reporte_id uuid, p_sello text, p_sha256 text, p_bytes integer, p_fotos_omitidas integer default 0,
                                                     p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $$
declare v_email text; v_sello text; v_dest jsonb; v_id bigint; v_doc campo.reporte_pdf;
begin
  v_email := campo.f_ran_autorizar(p_solicitante, p_reporte_id);
  v_sello := encode(sha256(convert_to(campo.f_ran_contenido(p_reporte_id)::text, 'UTF8')), 'hex');
  if p_sello is distinct from v_sello then perform campo.f_error('El reporte cambió mientras se armaba el PDF: vuelva a pedirlo', '55000'); end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then perform campo.f_error('La huella del PDF no es válida'); end if;
  if p_bytes is null or p_bytes < 200 or p_bytes > 26214400 then perform campo.f_error('El tamaño del PDF no es válido'); end if;
  v_dest := campo.f_ran_destino(p_reporte_id, v_sello);
  insert into campo.reporte_pdf (reporte_id, version, sello, nombre, ruta, sha256, bytes, fotos_omitidas, generado_por)
  values (p_reporte_id, (v_dest ->> 'version')::integer, v_sello, v_dest ->> 'nombre', v_dest ->> 'ruta', p_sha256, p_bytes, greatest(coalesce(p_fotos_omitidas, 0), 0), v_email)
  on conflict do nothing returning id into v_id;
  select * into v_doc from campo.reporte_pdf where reporte_id = p_reporte_id and sello = v_sello;
  if v_doc.id is null then perform campo.f_error('Otro supervisor generó una versión al mismo tiempo: vuelva a pedirlo', '55000'); end if;
  perform campo.f_auditar(v_email, case when v_id is not null then 'campo_ran_pdf_generar' else 'campo_ran_pdf_descargar' end, p_reporte_id::text,
    jsonb_build_object('nombre', v_doc.nombre, 'version', v_doc.version, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes, 'fotos_omitidas', v_doc.fotos_omitidas), p_ip);
  return jsonb_build_object('nombre', v_doc.nombre, 'ruta', v_doc.ruta, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes, 'version', v_doc.version, 'nuevo', v_id is not null);
end $$;

-- RPC 3: el PDF del sello VIGENTE ya existe: se entrega y la descarga queda auditada
create function public.geoportal_campo_ran_obtener(p_solicitante text, p_reporte_id uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $$
declare v_email text; v_sello text; v_doc campo.reporte_pdf;
begin
  v_email := campo.f_ran_autorizar(p_solicitante, p_reporte_id);
  v_sello := encode(sha256(convert_to(campo.f_ran_contenido(p_reporte_id)::text, 'UTF8')), 'hex');
  select * into v_doc from campo.reporte_pdf where reporte_id = p_reporte_id and sello = v_sello;
  if v_doc.id is null then perform campo.f_error('El PDF de la versión vigente de este reporte todavía no existe', 'P0002'); end if;
  perform campo.f_auditar(v_email, 'campo_ran_pdf_descargar', p_reporte_id::text, jsonb_build_object('nombre', v_doc.nombre, 'version', v_doc.version), p_ip);
  return jsonb_build_object('nombre', v_doc.nombre, 'ruta', v_doc.ruta, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes, 'version', v_doc.version, 'nuevo', false);
end $$;

-- Permisos: las internas, para nadie de la API; las RPC, solo service_role (la Edge)
revoke all on function campo.f_ran_autorizar(text, uuid), campo.f_ran_persona(text), campo.f_ran_contenido(uuid), campo.f_ran_destino(uuid, text),
                       campo.f_ran_mapa(numeric, numeric, numeric, numeric) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_ran_datos(text, uuid, text), public.geoportal_campo_ran_registrar(text, uuid, text, text, integer, integer, text),
                       public.geoportal_campo_ran_obtener(text, uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_ran_datos(text, uuid, text), public.geoportal_campo_ran_registrar(text, uuid, text, text, integer, integer, text),
                          public.geoportal_campo_ran_obtener(text, uuid, text) to service_role;
