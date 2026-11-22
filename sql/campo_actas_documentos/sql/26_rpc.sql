-- =====================================================================
-- COMERCIAL 21-NOV · (b) ACTAS · 26 — RPC NUEVAS (solo service_role; el solicitante es el correo del token)
-- Las llaman las Edges geoportal-campo (8 formatos de campo) y geoportal-acta (acta AI). El PDF lo arma la Edge con geoportal_campo_pdf_datos y lo registra
-- con geoportal_campo_pdf_registrar (una sola vez; nunca se reescribe). Mensajes con HINT msg_usuario; 55000 → 409; P0002 → 404.
-- =====================================================================

create function public.geoportal_campo_documentos_catalogo(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if not (public.geoportal_es_admin(v_email) or public.geoportal_puede(v_email, 'campo') or public.geoportal_puede(v_email, 'dashboard_campo')
          or public.geoportal_puede(v_email, 'acta') or public.geoportal_puede(v_email, 'dashboard_acta')) then
    raise exception 'Sin permiso para esta función' using errcode = '42501';
  end if;
  return jsonb_build_object('formularios', (select coalesce(jsonb_agg(jsonb_build_object('formulario', d.formulario, 'lleva_pdf', d.lleva_pdf,
           'firmas', jsonb_build_object('operario', d.firma_operario, 'usuario', d.firma_usuario, 'testigo', d.firma_testigo)) order by d.formulario), '[]'::jsonb)
      from campo.formularios_documento d where d.activo));
end $$;

create function public.geoportal_campo_firma_guardar(p_solicitante text, p_esquema text, p_registro_id uuid, p_rol text, p_estado text, p_nombre text default null,
                                                     p_imagen text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'acta', 'pg_temp' as $$
declare v_email text; v_nombre text := nullif(regexp_replace(btrim(coalesce(p_nombre, '')), '\s+', ' ', 'g'), ''); v_img bytea; v_huella text; v_otro text; v_usuario text; v_estado text := p_estado;
begin
  if p_esquema = 'campo' then v_email := campo.f_verificar(p_solicitante, 'campo');
  elsif p_esquema = 'acta' then v_email := acta.f_autorizar(p_solicitante, 'capturar');
  else perform campo.f_error('El tipo de registro no es válido'); end if;
  if p_registro_id is null then perform campo.f_error('Indique el registro'); end if;
  if p_rol is null or p_rol not in ('operario', 'usuario', 'testigo') then perform campo.f_error('La firma debe ser del operario, del usuario o del testigo'); end if;
  perform pg_advisory_xact_lock(hashtext('campo_firma:' || p_registro_id::text));
  if campo.f_registro_existe(p_esquema, p_registro_id) then perform campo.f_error('El registro ya está hecho: la firma es definitiva', '55000'); end if;
  select f.autor into v_otro from campo.firmas f where f.esquema = p_esquema and f.registro_id = p_registro_id and f.autor <> v_email limit 1;
  if v_otro is not null then perform campo.f_error('Ese registro lo está diligenciando otra persona'); end if;
  if v_estado = 'quitar' then
    if p_rol = 'operario' then perform campo.f_error('La firma del operario es obligatoria: fírmela de nuevo en vez de quitarla'); end if;
    if not exists (select 1 from campo.firmas f where f.esquema = p_esquema and f.registro_id = p_registro_id and f.rol = p_rol and f.estado <> 'quitada') then
      perform campo.f_error('No hay firma que quitar', '55000');
    end if;
    update campo.firmas set estado = 'quitada', nombre = null, imagen = null, huella = null, cambiado_en = clock_timestamp()
     where esquema = p_esquema and registro_id = p_registro_id and rol in (p_rol, case when p_rol = 'usuario' then 'testigo' end);
    perform campo.f_auditar(v_email, 'campo_firma_quitar', p_registro_id::text, jsonb_build_object('esquema', p_esquema, 'rol', p_rol), p_ip);
    return jsonb_build_object('rol', p_rol, 'estado', 'quitada', 'sha256', null);
  end if;
  if v_estado is null or not ((p_rol = 'operario' and v_estado = 'firmo') or (p_rol = 'usuario' and v_estado in ('firmo', 'no_firmo', 'nadie_atendio'))
                              or (p_rol = 'testigo' and v_estado = 'firmo')) then
    perform campo.f_error(case p_rol when 'usuario' then 'El estado del usuario debe ser firmo, no_firmo o nadie_atendio' else 'El estado de esa firma debe ser firmo' end);
  end if;
  if p_rol = 'operario' then
    select case when length(btrim(coalesce(lb.nombre, ''))) >= 2 then left(btrim(lb.nombre), 120) else left(split_part(v_email, '@', 1), 120) end into v_nombre
      from public.geoportal_lista_blanca lb where lb.email = v_email;
    if length(coalesce(v_nombre, '')) < 2 then v_nombre := left(v_email, 120); end if;
  elsif v_estado = 'firmo' or p_rol = 'testigo' then
    if v_nombre is null or length(v_nombre) < 2 or length(v_nombre) > 120 then
      perform campo.f_error(case p_rol when 'testigo' then 'Escriba el nombre del testigo (entre 2 y 120 caracteres)' else 'Escriba el nombre de quien atendió (entre 2 y 120 caracteres)' end);
    end if;
  else v_nombre := null;
  end if;
  if p_rol = 'testigo' then
    select f.estado into v_usuario from campo.firmas f where f.esquema = p_esquema and f.registro_id = p_registro_id and f.rol = 'usuario';
    if v_usuario is distinct from 'no_firmo' then perform campo.f_error('El testigo firma solo cuando el usuario no firmó'); end if;
  end if;
  if v_estado = 'firmo' then
    begin v_img := decode(p_imagen, 'base64'); exception when others then perform campo.f_error('La imagen de la firma no es válida'); end;
    if v_img is null or octet_length(v_img) < 200 or octet_length(v_img) > 40960 or substring(v_img from 1 for 3) <> '\xffd8ff'::bytea then
      perform campo.f_error('La firma debe ser una imagen JPEG de 200 B a 40 KB');
    end if;
    v_huella := encode(sha256(v_img), 'hex');
  end if;
  insert into campo.firmas (esquema, registro_id, rol, estado, nombre, imagen, huella, autor) values (p_esquema, p_registro_id, p_rol, v_estado, v_nombre, v_img, v_huella, v_email)
  on conflict (esquema, registro_id, rol) do update set estado = excluded.estado, nombre = excluded.nombre, imagen = excluded.imagen, huella = excluded.huella, cambiado_en = clock_timestamp();
  if p_rol = 'usuario' and v_estado <> 'no_firmo' then
    update campo.firmas set estado = 'quitada', nombre = null, imagen = null, huella = null, cambiado_en = clock_timestamp()
     where esquema = p_esquema and registro_id = p_registro_id and rol = 'testigo' and estado <> 'quitada';
  end if;
  perform campo.f_auditar(v_email, 'campo_firma_guardar', p_registro_id::text, jsonb_build_object('esquema', p_esquema, 'rol', p_rol, 'estado', v_estado, 'huella', v_huella), p_ip);
  return jsonb_build_object('rol', p_rol, 'estado', v_estado, 'sha256', v_huella);
end $$;

-- Datos completos para armar el PDF (solo la Edge; incluye los nombres y las firmas, que van SOLO en el PDF interno)
create function public.geoportal_campo_pdf_datos(p_solicitante text, p_esquema text, p_registro_id uuid, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'acta', 'pg_temp' as $$
declare v_email text; v_r campo.reportes; v_a acta.actas; v_t campo.tipos_reporte; v_d campo.formularios_documento; v_form text; v_sen jsonb; v_secc jsonb; v_cab jsonb;
        v_fotos jsonb; v_firmas jsonb; v_nombre text; v_sello text; v_doc jsonb; v_op text; v_ver integer := 1;
begin
  v_email := campo.f_autorizar_documento(p_solicitante, p_esquema, p_registro_id);
  if p_esquema = 'campo' then
    select * into v_r from campo.reportes where id = p_registro_id;
    select * into v_t from campo.tipos_reporte where id = v_r.tipo_id;
    v_form := 'tipo:' || v_t.codigo;
  else
    select * into v_a from acta.actas where id = p_registro_id;
    v_form := 'acta'; v_ver := v_a.version;
  end if;
  v_d := campo.f_documento_de(v_form);
  if v_d.formulario is null or not v_d.lleva_pdf then perform campo.f_error('Ese formulario no lleva PDF'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('rol', f.rol, 'estado', f.estado, 'nombre', f.nombre, 'imagen', encode(f.imagen, 'base64'), 'huella', f.huella)
                            order by array_position(array['operario', 'usuario', 'testigo'], f.rol)), '[]'::jsonb)
    into v_firmas from campo.firmas f where f.esquema = p_esquema and f.registro_id = p_registro_id and f.estado <> 'quitada';
  select coalesce(nullif(btrim(lb.nombre), ''), split_part(coalesce(v_r.autor, v_a.autor), '@', 1)) into v_op from public.geoportal_lista_blanca lb where lb.email = coalesce(v_r.autor, v_a.autor);
  if p_esquema = 'campo' then
    select d.datos into v_sen from campo.reporte_datos_sensibles d where d.reporte_id = v_r.id;
    v_cab := jsonb_build_array(jsonb_build_array('Formato', v_t.nombre), jsonb_build_array('Consecutivo', v_r.consecutivo), jsonb_build_array('Contrato', coalesce(v_r.contrato, '—')),
               jsonb_build_array('Resultado', coalesce(v_r.resultado, '—')), jsonb_build_array('Ubicación', v_r.lat || ', ' || v_r.lon || coalesce(' (precisión ' || v_r.precision_m || ' m)', '')));
    with c as (
      select c.seccion, c.orden, c.nombre, c.tipo_dato, c.opciones, coalesce(v_r.datos -> c.codigo, v_sen -> c.codigo) as v
        from campo.tipo_campos c where c.tipo_id = v_t.id and (v_r.datos ? c.codigo or coalesce(v_sen, '{}'::jsonb) ? c.codigo)
    ), f as (
      select c.seccion, c.orden, jsonb_build_array(c.nombre,
               case c.tipo_dato when 'si_no' then case when c.v = 'true'::jsonb then 'Sí' when c.v = 'false'::jsonb then 'No' else c.v #>> '{}' end
                                when 'opcion' then coalesce((select o ->> 'nombre' from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = c.v #>> '{}'), c.v #>> '{}')
                                when 'opciones' then (select string_agg(coalesce((select o ->> 'nombre' from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = x), x), '; ')
                                                        from jsonb_array_elements_text(case when jsonb_typeof(c.v) = 'array' then c.v else '[]'::jsonb end) x)
                                else c.v #>> '{}' end) as par
        from c
    )
    select jsonb_agg(jsonb_build_object('titulo', s.seccion, 'campos', s.campos) order by s.o) into v_secc
      from (select coalesce(f.seccion, 'Datos') as seccion, min(f.orden) as o, jsonb_agg(f.par order by f.orden) as campos from f group by coalesce(f.seccion, 'Datos')) s;
    select coalesce(jsonb_agg(jsonb_build_object('bucket', 'campo-fotos', 'ruta', p.ruta_storage, 'etiqueta', coalesce(p.etiqueta, 'Foto ' || p.orden), 'bytes', p.tamano_bytes) order by p.orden), '[]'::jsonb)
      into v_fotos from campo.reporte_fotos p where p.reporte_id = v_r.id;
    v_nombre := campo.f_nombre_pdf(v_r.registrado_en, v_d.sigla, replace(v_r.consecutivo, '-', ''), 1);
    v_sello := encode(sha256(convert_to(to_jsonb(v_r)::text || coalesce(v_sen::text, '') || coalesce((select string_agg(f.huella, ',' order by f.rol) from campo.firmas f
                 where f.esquema = 'campo' and f.registro_id = v_r.id and f.estado = 'firmo'), ''), 'UTF8')), 'hex');
  else
    v_cab := jsonb_build_array(jsonb_build_array('Consecutivo', v_a.consecutivo || case when v_a.version > 1 then ' (versión ' || v_a.version || ')' else '' end),
               jsonb_build_array('Acta física', coalesce(v_a.numero_acta_fisica, 'pendiente') || coalesce(' del ' || to_char(v_a.fecha_acta_fisica, 'YYYY-MM-DD'), '')),
               jsonb_build_array('Contrato', coalesce(v_a.contrato, '—')), jsonb_build_array('Dirección', coalesce(v_a.direccion, '—')), jsonb_build_array('Barrio', coalesce(v_a.barrio, '—')),
               jsonb_build_array('Ubicación', v_a.lat || ', ' || v_a.lon || coalesce(' (precisión ' || v_a.precision_m || ' m)', '')));
    v_secc := jsonb_build_array(
      jsonb_build_object('titulo', 'Medidor', 'campos', jsonb_build_array(
        jsonb_build_array('Tiene medidor', case when v_a.tiene_medidor then 'Sí' when v_a.tiene_medidor = false then 'No' else '—' end),
        jsonb_build_array('Serie', coalesce(v_a.medidor_serie, '—')), jsonb_build_array('Marca', coalesce(v_a.marca, '—')), jsonb_build_array('Lectura (m³)', coalesce(v_a.lectura_m3::text, '—')),
        jsonb_build_array('Serie de los sellos', coalesce(v_a.serie_sellos, '—')))),
      jsonb_build_object('titulo', 'Hallazgos', 'campos', jsonb_build_array(
        jsonb_build_array('Sin irregularidad', case when v_a.sin_irregularidad then 'Sí' else 'No' end),
        jsonb_build_array('Hallazgos', coalesce((select string_agg(coalesce(h.texto_otro, th.nombre), '; ') from acta.acta_hallazgos h join acta.tipos_hallazgo th on th.id = h.tipo_hallazgo_id where h.acta_id = v_a.id), '—')),
        jsonb_build_array('Descripción', coalesce(v_a.descripcion_hallazgos, '—')),
        jsonb_build_array('Acciones', coalesce((select string_agg(ac.nombre, '; ') from acta.acta_acciones x join acta.acciones_correctivas ac on ac.id = x.accion_id where x.acta_id = v_a.id), '—')))),
      jsonb_build_object('titulo', 'Quién atendió', 'campos', jsonb_build_array(
        jsonb_build_array('Nadie atendió', case when v_a.nadie_atendio then 'Sí' else 'No' end),
        jsonb_build_array('Atendió', coalesce((select p.nombre || coalesce(' (' || coalesce(ca.nombre, p.calidad_texto) || ')', '') from acta.acta_personas p left join acta.calidades_atendiente ca on ca.id = p.calidad_id
                                                where p.acta_id = v_a.id and p.rol = 'atendiente' limit 1), '—')),
        jsonb_build_array('Testigo', coalesce((select p.nombre from acta.acta_personas p where p.acta_id = v_a.id and p.rol = 'testigo' limit 1), '—')),
        jsonb_build_array('Observaciones', coalesce(v_a.observaciones, '—')))));
    select coalesce(jsonb_agg(jsonb_build_object('bucket', 'acta-evidencias', 'ruta', p.ruta_storage, 'etiqueta', coalesce(tf.nombre, 'Foto ' || p.orden), 'bytes', p.tamano_bytes) order by p.orden), '[]'::jsonb)
      into v_fotos from acta.acta_fotos p left join acta.tipos_foto tf on tf.id = p.tipo_foto_id where p.acta_id = v_a.id;
    v_nombre := campo.f_nombre_pdf(v_a.registrado_en, v_d.sigla, v_a.consecutivo, v_a.version);
    v_sello := encode(sha256(convert_to(coalesce((select s.sello_sha256 from acta.acta_sellos s where s.acta_id = v_a.id), '') || coalesce((select string_agg(f.huella, ',' order by f.rol)
                 from campo.firmas f where f.esquema = 'acta' and f.registro_id = v_a.id and f.estado = 'firmo'), ''), 'UTF8')), 'hex');
  end if;
  select jsonb_build_object('nombre', d.nombre, 'ruta', d.ruta, 'sha256', d.sha256, 'bytes', d.bytes, 'version', d.version) into v_doc
    from campo.documentos_pdf d where d.esquema = p_esquema and d.registro_id = p_registro_id;
  return jsonb_build_object('esquema', p_esquema, 'registro_id', p_registro_id, 'formulario', v_form, 'version', v_ver, 'nombre', v_nombre,
    'ruta', p_esquema || '/' || to_char(coalesce(v_r.registrado_en, v_a.registrado_en) at time zone 'America/Bogota', 'YYYY-MM') || '/' || p_registro_id || '/' || v_nombre,
    'titulo', case when p_esquema = 'acta' then 'ACTA DE INSPECCIÓN TÉCNICA · REPORTAR POSIBLE PÉRDIDA' else upper(v_t.nombre) end,
    'consecutivo', coalesce(v_r.consecutivo, v_a.consecutivo),
    'registrado_en', to_char(coalesce(v_r.registrado_en, v_a.registrado_en) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
    'inicio_en', to_char(coalesce(v_r.inicio_en, v_a.inicio_en) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
    'fin_en', to_char(coalesce(v_r.registrado_en, v_a.fin_en) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
    'operario', jsonb_build_object('nombre', v_op, 'correo', coalesce(v_r.autor, v_a.autor)),
    'cabecera', v_cab, 'secciones', coalesce(v_secc, '[]'::jsonb), 'fotos', v_fotos, 'firmas', v_firmas, 'sello', v_sello, 'documento', v_doc);
end $$;

create function public.geoportal_campo_pdf_registrar(p_solicitante text, p_esquema text, p_registro_id uuid, p_sha256 text, p_bytes integer, p_fotos_omitidas integer default 0,
                                                     p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; v_datos jsonb; v_id bigint; v_doc campo.documentos_pdf;
begin
  v_datos := public.geoportal_campo_pdf_datos(p_solicitante, p_esquema, p_registro_id);
  v_email := lower(btrim(p_solicitante));
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then perform campo.f_error('La huella del PDF no es válida'); end if;
  if p_bytes is null or p_bytes < 200 or p_bytes > 26214400 then perform campo.f_error('El tamaño del PDF no es válido'); end if;
  insert into campo.documentos_pdf (esquema, registro_id, formulario, version, nombre, ruta, sha256, bytes, fotos_omitidas, generado_por)
  values (p_esquema, p_registro_id, v_datos ->> 'formulario', (v_datos ->> 'version')::integer, v_datos ->> 'nombre', v_datos ->> 'ruta', p_sha256, p_bytes, greatest(coalesce(p_fotos_omitidas, 0), 0), v_email)
  on conflict (esquema, registro_id) do nothing returning id into v_id;
  select * into v_doc from campo.documentos_pdf where esquema = p_esquema and registro_id = p_registro_id;
  if v_id is not null then
    perform campo.f_auditar(v_email, 'campo_pdf_generar', p_registro_id::text, jsonb_build_object('esquema', p_esquema, 'nombre', v_doc.nombre, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes), p_ip);
  end if;
  return jsonb_build_object('nombre', v_doc.nombre, 'ruta', v_doc.ruta, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes, 'version', v_doc.version, 'nuevo', v_id is not null);
end $$;

create function public.geoportal_campo_pdf_fallo(p_solicitante text, p_esquema text, p_registro_id uuid, p_detalle text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text;
begin
  v_email := campo.f_autorizar_documento(p_solicitante, p_esquema, p_registro_id);
  insert into campo.documento_intentos (esquema, registro_id, resultado, detalle, autor) values (p_esquema, p_registro_id, 'fallo', left(p_detalle, 300), v_email);
  return jsonb_build_object('registrado', true);
end $$;

create function public.geoportal_campo_pdf_obtener(p_solicitante text, p_esquema text, p_registro_id uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; v_doc campo.documentos_pdf;
begin
  v_email := campo.f_autorizar_documento(p_solicitante, p_esquema, p_registro_id);
  select * into v_doc from campo.documentos_pdf where esquema = p_esquema and registro_id = p_registro_id;
  if v_doc.id is null then perform campo.f_error('Ese registro todavía no tiene PDF', 'P0002'); end if;
  perform campo.f_auditar(v_email, 'campo_pdf_descargar', p_registro_id::text, jsonb_build_object('esquema', p_esquema, 'nombre', v_doc.nombre), p_ip);
  return jsonb_build_object('nombre', v_doc.nombre, 'ruta', v_doc.ruta, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes, 'version', v_doc.version);
end $$;

-- Filas de las actas registradas con sus marcas (PDF, firmas, derivadas). Sin nombres de personas, sin imágenes, sin texto libre.
create function campo.f_registradas_filtradas(f jsonb) returns table (fila jsonb, registrado_en timestamptz, registro_id uuid)
language plpgsql stable security definer set search_path to 'public', 'campo', 'acta', 'pg_temp' as $$
declare v_tipo text; v_desde date; v_hasta date; v_op text; v_con text; v_bar text; v_res text; v_der text;
begin
  begin
    v_tipo := nullif(f ->> 'tipo', ''); v_desde := nullif(f ->> 'desde', '')::date; v_hasta := nullif(f ->> 'hasta', '')::date;
    v_op := nullif(lower(btrim(coalesce(f ->> 'operario', ''))), ''); v_con := nullif(btrim(coalesce(f ->> 'contrato', '')), '');
    v_bar := nullif(btrim(coalesce(f ->> 'barrio', '')), ''); v_res := nullif(f ->> 'resultado', ''); v_der := nullif(f ->> 'derivadas', '');
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  if v_der is not null and v_der not in ('con', 'pendientes', 'atendidas') then perform campo.f_error('El filtro de derivadas debe ser con, pendientes o atendidas'); end if;
  return query
  select jsonb_build_object('registro_id', g.registro_id, 'esquema', g.esquema, 'tipo', g.tipo, 'tipo_nombre', g.tipo_nombre, 'consecutivo', g.consecutivo, 'numero_fisico', g.numero_fisico,
           'fecha', g.fecha, 'registrado_en', g.registrado_en, 'operario', g.operario, 'contrato', g.contrato, 'barrio', g.barrio, 'resultado', g.resultado,
           'pdf', coalesce((select jsonb_build_object('estado', 'generado', 'nombre', d.nombre, 'version', d.version) from campo.documentos_pdf d where d.esquema = g.esquema and d.registro_id = g.registro_id),
                           jsonb_build_object('estado', 'pendiente', 'nombre', null, 'version', null)),
           'derivadas', jsonb_build_object('total', dv.total, 'pendientes', dv.pendientes),
           'firmas', jsonb_build_object('operario', exists (select 1 from campo.firmas x where x.esquema = g.esquema and x.registro_id = g.registro_id and x.rol = 'operario' and x.estado = 'firmo'),
                                        'usuario', (select x.estado from campo.firmas x where x.esquema = g.esquema and x.registro_id = g.registro_id and x.rol = 'usuario' and x.estado <> 'quitada'),
                                        'testigo', exists (select 1 from campo.firmas x where x.esquema = g.esquema and x.registro_id = g.registro_id and x.rol = 'testigo' and x.estado = 'firmo'))),
         g.registrado_en, g.registro_id
    from campo.f_registradas() g
    cross join lateral (select count(*)::integer as total, count(*) filter (where campo.f_derivada_estado(dd.id) = 'pendiente')::integer as pendientes
                          from campo.derivadas dd where g.esquema = 'campo' and dd.origen_id = g.registro_id) dv
   where (v_tipo is null or g.tipo = v_tipo) and (v_desde is null or g.fecha >= v_desde) and (v_hasta is null or g.fecha <= v_hasta)
     and (v_op is null or g.operario like '%' || v_op || '%') and (v_con is null or g.contrato = v_con) and (v_bar is null or g.barrio ilike '%' || v_bar || '%')
     and (v_res is null or g.resultado = v_res)
     and (v_der is null or (v_der = 'con' and dv.total > 0) or (v_der = 'pendientes' and dv.pendientes > 0) or (v_der = 'atendidas' and dv.total > 0 and dv.pendientes = 0));
end $$;

create function public.geoportal_campo_actas_registradas(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_lim integer; v_antes timestamptz; v_filas jsonb; v_n integer;
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 50), 1), 200); v_antes := nullif(f ->> 'antes', '')::timestamptz;
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  select count(*), coalesce(jsonb_agg(x.fila order by x.registrado_en desc, x.registro_id) filter (where x.rn <= v_lim), '[]'::jsonb) into v_n, v_filas
    from (select r.*, row_number() over (order by r.registrado_en desc, r.registro_id) as rn from campo.f_registradas_filtradas(f) r
           where v_antes is null or r.registrado_en < v_antes order by r.registrado_en desc limit v_lim + 1) x;
  return jsonb_build_object('filas', v_filas, 'siguiente', case when v_n > v_lim then (select min((e ->> 'registrado_en')::timestamptz) from jsonb_array_elements(v_filas) e) end);
end $$;

create function public.geoportal_campo_actas_registradas_descarga(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_lim integer; v_desp timestamptz; v_filas jsonb; v_n integer;
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 5000), 1), 5000); v_desp := nullif(f ->> 'despues', '')::timestamptz;
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  select count(*), coalesce(jsonb_agg((x.fila - 'firmas') || jsonb_build_object('firmas', jsonb_build_object('operario', x.fila -> 'firmas' -> 'operario', 'usuario', x.fila -> 'firmas' -> 'usuario',
           'testigo', x.fila -> 'firmas' -> 'testigo')) order by x.registrado_en, x.registro_id) filter (where x.rn <= v_lim), '[]'::jsonb) into v_n, v_filas
    from (select r.*, row_number() over (order by r.registrado_en, r.registro_id) as rn from campo.f_registradas_filtradas(f) r
           where v_desp is null or r.registrado_en > v_desp order by r.registrado_en limit v_lim + 1) x;
  perform campo.f_auditar(v_email, 'campo_actas_registradas_descarga', null, jsonb_build_object('filtros', f - 'despues' - 'limite', 'filas', least(v_n, v_lim)), p_ip);
  return jsonb_build_object('filas', v_filas, 'siguiente', case when v_n > v_lim then (select max((e ->> 'registrado_en')::timestamptz) from jsonb_array_elements(v_filas) e) end);
end $$;

-- ---------- Derivadas ----------
create function campo.f_derivada_json(p_id bigint) returns jsonb
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select jsonb_build_object('id', d.id, 'actividad', d.actividad, 'actividad_nombre', c.nombre, 'contrato', d.contrato, 'estado', campo.f_derivada_estado(d.id), 'creada_en', d.creado_en,
           'destinos', to_jsonb(c.destinos), 'destino_omision', c.destino_omision,
           'origen', jsonb_build_object('registro_id', r.id, 'tipo', t.codigo, 'tipo_nombre', t.nombre, 'consecutivo', r.consecutivo, 'fecha', r.registrado_en, 'operario', r.autor),
           'cierre', (select jsonb_build_object('tipo', e.tipo_evento, 'esquema', e.esquema, 'registro_id', e.registro_id, 'autor', e.autor, 'en', e.creado_en, 'motivo', e.motivo,
                                                 'consecutivo', case e.esquema when 'campo' then (select x.consecutivo from campo.reportes x where x.id = e.registro_id)
                                                                               when 'acta' then (select x.consecutivo from acta.actas x where x.id = e.registro_id) end)
                        from campo.derivada_eventos e where e.derivada_id = d.id))
    from campo.derivadas d join campo.derivadas_catalogo c on c.codigo = d.actividad join campo.reportes r on r.id = d.origen_id join campo.tipos_reporte t on t.id = r.tipo_id
   where d.id = p_id
$$;

create function public.geoportal_campo_derivadas_abiertas(p_solicitante text, p_contrato text, p_formulario text, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'acta', 'pg_temp' as $$
declare v_email text; v_con text := nullif(btrim(coalesce(p_contrato, '')), '');
begin
  if p_formulario = 'acta' then v_email := acta.f_autorizar(p_solicitante, 'capturar'); else v_email := campo.f_verificar(p_solicitante, 'campo'); end if;
  if v_con is null then return jsonb_build_object('derivadas', '[]'::jsonb); end if;
  return jsonb_build_object('derivadas', (select coalesce(jsonb_agg(campo.f_derivada_json(d.id) order by d.id), '[]'::jsonb)
    from campo.derivadas d join campo.derivadas_catalogo c on c.codigo = d.actividad
   where d.contrato = v_con and p_formulario = any (c.destinos) and campo.f_derivada_estado(d.id) = 'pendiente'));
end $$;

create function public.geoportal_campo_derivada_atender(p_solicitante text, p_derivada_id bigint, p_esquema text, p_registro_id uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'acta', 'pg_temp' as $$
declare v_email text; v_d campo.derivadas; v_c campo.derivadas_catalogo; v_form text; v_con text; v_autor text;
begin
  v_email := campo.f_autorizar_documento(p_solicitante, p_esquema, p_registro_id);
  perform pg_advisory_xact_lock(hashtext('campo_derivada:' || p_derivada_id));
  select * into v_d from campo.derivadas where id = p_derivada_id;
  if v_d.id is null then perform campo.f_error('Esa actividad derivada no existe', 'P0002'); end if;
  select * into v_c from campo.derivadas_catalogo where codigo = v_d.actividad;
  if campo.f_derivada_estado(v_d.id) <> 'pendiente' then perform campo.f_error('Esa actividad derivada ya está cerrada', '55000'); end if;
  if p_esquema = 'campo' then select 'tipo:' || t.codigo, r.contrato, r.autor into v_form, v_con, v_autor from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id where r.id = p_registro_id;
  else select 'acta', a.contrato, a.autor into v_form, v_con, v_autor from acta.actas a where a.id = p_registro_id; end if;
  if not (v_form = any (v_c.destinos)) then perform campo.f_error('Ese formulario no atiende esa actividad derivada'); end if;
  if v_con is distinct from v_d.contrato then perform campo.f_error('El registro es de otro contrato'); end if;
  if p_registro_id = v_d.origen_id then perform campo.f_error('Una revisión no atiende sus propias actividades derivadas'); end if;
  insert into campo.derivada_eventos (derivada_id, tipo_evento, esquema, registro_id, autor) values (v_d.id, 'atendida', p_esquema, p_registro_id, v_email);
  perform campo.f_auditar(v_email, 'campo_derivada_atender', v_d.id::text, jsonb_build_object('esquema', p_esquema, 'registro', p_registro_id), p_ip);
  return campo.f_derivada_json(v_d.id);
end $$;

create function public.geoportal_campo_derivada_cerrar(p_solicitante text, p_derivada_id bigint, p_tipo text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; v_m text;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if p_tipo is null or p_tipo not in ('atendida_fuera', 'anulada') then perform campo.f_error('El cierre debe ser atendida_fuera o anulada'); end if;
  v_m := campo.f_motivo_personal(p_motivo, true);
  perform pg_advisory_xact_lock(hashtext('campo_derivada:' || p_derivada_id));
  if not exists (select 1 from campo.derivadas where id = p_derivada_id) then perform campo.f_error('Esa actividad derivada no existe', 'P0002'); end if;
  if campo.f_derivada_estado(p_derivada_id) <> 'pendiente' then perform campo.f_error('Esa actividad derivada ya está cerrada', '55000'); end if;
  insert into campo.derivada_eventos (derivada_id, tipo_evento, motivo, autor) values (p_derivada_id, p_tipo, v_m, v_email);
  perform campo.f_auditar(v_email, 'campo_derivada_' || p_tipo, p_derivada_id::text, '{}'::jsonb, p_ip);
  return campo.f_derivada_json(p_derivada_id);
end $$;

create function public.geoportal_campo_derivadas(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_est text; v_con text; v_act text; v_desde date; v_hasta date; v_antes bigint; v_lim integer; v_filas jsonb; v_n integer;
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_est := nullif(f ->> 'estado', ''); v_con := nullif(btrim(coalesce(f ->> 'contrato', '')), ''); v_act := nullif(f ->> 'actividad', '');
    v_desde := nullif(f ->> 'desde', '')::date; v_hasta := nullif(f ->> 'hasta', '')::date; v_antes := nullif(f ->> 'antes', '')::bigint;
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 50), 1), 200);
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  if v_est is not null and v_est not in ('pendiente', 'atendida', 'atendida_fuera', 'anulada') then perform campo.f_error('El estado no es válido'); end if;
  select count(*), coalesce(jsonb_agg(campo.f_derivada_json(x.id) order by x.id desc) filter (where x.rn <= v_lim), '[]'::jsonb) into v_n, v_filas
    from (select d.id, row_number() over (order by d.id desc) as rn from campo.derivadas d
           where (v_est is null or campo.f_derivada_estado(d.id) = v_est) and (v_con is null or d.contrato = v_con) and (v_act is null or d.actividad = v_act)
             and (v_desde is null or (d.creado_en at time zone 'America/Bogota')::date >= v_desde) and (v_hasta is null or (d.creado_en at time zone 'America/Bogota')::date <= v_hasta)
             and (v_antes is null or d.id < v_antes) order by d.id desc limit v_lim + 1) x;
  return jsonb_build_object('filas', v_filas, 'siguiente', case when v_n > v_lim then (select min((e ->> 'id')::bigint) from jsonb_array_elements(v_filas) e) end);
end $$;

create function public.geoportal_campo_actas_abiertas(p_solicitante text, p_contrato text, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'acta', 'pg_temp' as $$
declare v_email text; v_con text := nullif(btrim(coalesce(p_contrato, '')), '');
begin
  v_email := campo.f_verificar(p_solicitante, 'campo');
  if v_con is null then return jsonb_build_object('actas', '[]'::jsonb); end if;
  return jsonb_build_object('actas', (select coalesce(jsonb_agg(jsonb_build_object('acta_id', a.id, 'consecutivo', a.consecutivo, 'fecha', a.fecha_acta_fisica, 'registrado_en', a.registrado_en,
           'sin_irregularidad', a.sin_irregularidad) order by a.registrado_en desc), '[]'::jsonb)
      from acta.actas a where a.contrato = v_con and not exists (select 1 from acta.actas b where b.version_anterior_id = a.id)));
end $$;

create function public.geoportal_campo_origen_vincular(p_solicitante text, p_reporte_id uuid, p_acta_id uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'acta', 'pg_temp' as $$
declare v_email text; v_r campo.reportes; v_codigo text; v_a acta.actas;
begin
  v_email := campo.f_autorizar_documento(p_solicitante, 'campo', p_reporte_id);
  select * into v_r from campo.reportes where id = p_reporte_id;
  select t.codigo into v_codigo from campo.tipos_reporte t where t.id = v_r.tipo_id;
  if v_codigo not in ('revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida') then perform campo.f_error('Solo una revisión o instalación se vincula con un acta de posible pérdida'); end if;
  select * into v_a from acta.actas where id = p_acta_id;
  if v_a.id is null then perform campo.f_error('Esa acta no existe', 'P0002'); end if;
  if v_a.contrato is distinct from v_r.contrato then perform campo.f_error('El acta es de otro contrato'); end if;
  if exists (select 1 from campo.origen_vinculos o where o.reporte_id = p_reporte_id) then perform campo.f_error('Esa revisión ya tiene su acta de origen', '55000'); end if;
  insert into campo.origen_vinculos (reporte_id, acta_id, autor) values (p_reporte_id, p_acta_id, v_email);
  perform campo.f_auditar(v_email, 'campo_origen_vincular', p_reporte_id::text, jsonb_build_object('acta', p_acta_id), p_ip);
  return jsonb_build_object('reporte_id', p_reporte_id, 'acta_id', p_acta_id, 'consecutivo_acta', v_a.consecutivo, 'vinculado', true);
end $$;
