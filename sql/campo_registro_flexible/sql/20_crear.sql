-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 20 — CREAR REPORTE (reporte general y formatos de actividad; también la entrada de Técnica)
-- Un solo parámetro nuevo al final, p_registro jsonb (opcional): {xy_manual, lat_registro, lon_registro, precision_registro_m, direccion, barrio, referencia}.
-- Y en p_fotos, cada foto puede traer «origen» (camara | galeria | archivo; camara si no viene).
-- Sin p_registro (la Edge de antes) todo sigue igual y no se guarda fila en campo.reporte_registro.
-- REGLA (en la base, no solo en la pantalla): XY digitado o una foto que no sea de cámara → solo supervisor o administrador (campo.f_autorizar_supervision),
-- y nunca desde la entrada de Técnica (geoportal.via_tecnica). El XY digitado se rechaza fuera de la zona de Valledupar (el del GPS sigue sin rechazarse).
-- La firma cambia (un parámetro más): se quita la anterior y se crea la nueva con sus permisos (DROP: por qué y alcance — solo esa firma; la nueva la reemplaza en la
-- misma transacción y la Edge de antes la sigue llamando igual porque p_registro tiene valor por omisión).
-- =====================================================================
drop function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone);
CREATE FUNCTION public.geoportal_campo_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_origen text, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_orden_trabajo_id uuid DEFAULT NULL::uuid, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone, p_registro jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'storage', 'pg_temp'
AS $function$
declare
  v_email text; v_perfil text; v_origen text := coalesce(p_origen, ''); v_maxdesc integer := campo.f_param('max_descripcion')::integer;
  v_t campo.tipos_reporte%rowtype; v_s campo.subtipos_reporte%rowtype; v_sub bigint;
  v_desc text; v_contrato text; v_verif boolean; v_fuera boolean; v_lat numeric; v_lon numeric;
  v_max_fotos integer; v_min_fotos integer; v_max_bytes bigint := campo.f_param('max_bytes_foto')::bigint;
  v_fotos jsonb := coalesce(p_fotos, '[]'::jsonb); v_n integer; v_f jsonb; v_orden integer; v_ruta text; v_size bigint; v_mime text;
  v_id uuid := p_id; v_prev campo.reportes%rowtype; v_reg timestamptz; v_ref jsonb := '[]'::jsonb;
  v_resultado text; v_causal_id bigint; v_causal_cod text; v_exigir boolean; v_val jsonb; v_gen jsonb; v_sen jsonb;
  v_con_etiquetas boolean; v_etq text; v_etqs text[] := '{}'; v_falta text; v_num bigint; v_consecutivo text;
  v_fin timestamptz; v_max_h numeric;   -- pasada 14/11: hora de inicio
  -- Registro flexible (25-nov)
  v_reg_in jsonb := p_registro; v_xy boolean := false; v_lat_r numeric; v_lon_r numeric; v_prec_r numeric; v_dir text; v_barrio text; v_refer text;
  v_forigen text; v_no_camara integer := 0; v_via_tec boolean := coalesce(current_setting('geoportal.via_tecnica', true), '') = 'on'; v_k text;
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);
  v_perfil := campo.f_perfil(v_email);

  -- Registro flexible: forma del bloque p_registro (solo estas claves; la Edge ya validó la forma y aquí se vuelve a validar)
  if v_reg_in is not null then
    if jsonb_typeof(v_reg_in) <> 'object' then perform campo.f_error('Los datos del registro no vienen en el formato esperado'); end if;
    for v_k in select jsonb_object_keys(v_reg_in) loop
      if v_k not in ('xy_manual', 'lat_registro', 'lon_registro', 'precision_registro_m', 'direccion', 'barrio', 'referencia') then
        perform campo.f_error(format('El dato «%s» no existe en el registro', left(v_k, 40)));
      end if;
    end loop;
    if v_reg_in ? 'xy_manual' and jsonb_typeof(v_reg_in -> 'xy_manual') not in ('boolean', 'null') then perform campo.f_error('xy_manual debe ser sí o no'); end if;
    v_xy := coalesce((v_reg_in ->> 'xy_manual')::boolean, false);
    if (v_reg_in ? 'lat_registro' and jsonb_typeof(v_reg_in -> 'lat_registro') not in ('number', 'null'))
       or (v_reg_in ? 'lon_registro' and jsonb_typeof(v_reg_in -> 'lon_registro') not in ('number', 'null'))
       or (v_reg_in ? 'precision_registro_m' and jsonb_typeof(v_reg_in -> 'precision_registro_m') not in ('number', 'null')) then
      perform campo.f_error('La ubicación del dispositivo no es válida');
    end if;
    v_lat_r := (v_reg_in ->> 'lat_registro')::numeric; v_lon_r := (v_reg_in ->> 'lon_registro')::numeric; v_prec_r := (v_reg_in ->> 'precision_registro_m')::numeric;
    if (v_lat_r is null) <> (v_lon_r is null) then perform campo.f_error('La ubicación del dispositivo debe traer latitud y longitud'); end if;
    if v_lat_r is not null and (v_lat_r < -90 or v_lat_r > 90 or v_lon_r < -180 or v_lon_r > 180) then perform campo.f_error('La ubicación del dispositivo está fuera de los rangos válidos'); end if;
    if v_prec_r is not null and (v_lat_r is null or v_prec_r < 0 or v_prec_r > 100000) then perform campo.f_error('La precisión de la ubicación del dispositivo no es válida'); end if;
    if v_lat_r is not null then v_lat_r := round(v_lat_r, 6); v_lon_r := round(v_lon_r, 6); end if;
    if v_prec_r is not null then v_prec_r := round(v_prec_r, 1); end if;
    if (v_reg_in ? 'direccion' and jsonb_typeof(v_reg_in -> 'direccion') not in ('string', 'null'))
       or (v_reg_in ? 'barrio' and jsonb_typeof(v_reg_in -> 'barrio') not in ('string', 'null'))
       or (v_reg_in ? 'referencia' and jsonb_typeof(v_reg_in -> 'referencia') not in ('string', 'null')) then
      perform campo.f_error('La dirección, el barrio y la referencia deben ser texto');
    end if;
    v_dir := nullif(btrim(coalesce(v_reg_in ->> 'direccion', '')), ''); v_barrio := nullif(btrim(coalesce(v_reg_in ->> 'barrio', '')), '');
    v_refer := nullif(btrim(coalesce(v_reg_in ->> 'referencia', '')), '');
    if length(coalesce(v_dir, '')) > 120 then perform campo.f_error('La dirección es demasiado larga (máximo 120 caracteres)'); end if;
    if length(coalesce(v_barrio, '')) > 80 then perform campo.f_error('El barrio es demasiado largo (máximo 80 caracteres)'); end if;
    if length(coalesce(v_refer, '')) > 200 then perform campo.f_error('La referencia es demasiado larga (máximo 200 caracteres)'); end if;
  end if;
  -- Origen de cada foto (camara si no viene)
  if jsonb_typeof(coalesce(p_fotos, '[]'::jsonb)) = 'array' then
    for v_f in select e from jsonb_array_elements(coalesce(p_fotos, '[]'::jsonb)) e loop
      if jsonb_typeof(v_f) = 'object' and v_f ? 'origen' then
        v_forigen := v_f ->> 'origen';
        if v_forigen is null or v_forigen not in ('camara', 'galeria', 'archivo') then perform campo.f_error('El origen de una foto debe ser cámara, galería o archivo'); end if;
        if v_forigen <> 'camara' then v_no_camara := v_no_camara + 1; end if;
      end if;
    end loop;
  end if;
  -- LA REGLA: XY digitado o foto adjuntada (galería o archivo) → solo supervisor o administrador de campo, y nunca desde la entrada de Técnica
  if v_xy or v_no_camara > 0 then
    if v_via_tec then
      raise exception 'Desde Técnica el registro se hace con la cámara y la ubicación del celular' using errcode = '42501';
    end if;
    if v_perfil is null or v_perfil not in ('admin', 'supervisor') then
      raise exception 'Solo el supervisor o el administrador pueden adjuntar fotos o digitar el XY' using errcode = '42501';
    end if;
    perform campo.f_autorizar_supervision(v_email);
  end if;
  if v_origen not in ('campo', 'escritorio') then perform campo.f_error('El origen debe ser campo o escritorio'); end if;
  if v_origen = 'escritorio' and v_perfil not in ('admin', 'supervisor') then
    raise exception 'Solo el supervisor o el administrador crean reportes desde el escritorio' using errcode = '42501';
  end if;

  -- Reenvío (red inestable): mismo identificador y mismo autor = misma respuesta, sin duplicar (y sin gastar cupo ni consecutivo)
  if v_id is not null then
    select * into v_prev from campo.reportes where id = v_id;
    if found then
      if v_prev.autor = v_email then
        return jsonb_build_object('id', v_prev.id, 'registrado_en', v_prev.registrado_en, 'repetido', true,
                                  'contrato_verificado', v_prev.contrato_verificado, 'aviso_zona', v_prev.fuera_de_zona, 'consecutivo', v_prev.consecutivo);
      end if;
      perform campo.f_error('Identificador de reporte no válido');
    end if;
  end if;

  -- Límite de ritmo (Paso B1): los reenvíos idempotentes de arriba NO consumen cupo; el cupo se verifica antes de validar el resto
  perform campo.f_cupo_reportes(v_email, v_perfil);

  -- Tipo, subtipo y texto
  select t.* into v_t from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where t.codigo = btrim(coalesce(p_tipo, '')) and t.activo and g.activo;
  if not found then perform campo.f_error('El tipo de reporte no existe o está desactivado'); end if;
  if nullif(btrim(coalesce(p_subtipo, '')), '') is not null then
    select s.* into v_s from campo.subtipos_reporte s where s.tipo_id = v_t.id and s.codigo = btrim(p_subtipo);
    if not found then perform campo.f_error('El subtipo no corresponde al tipo elegido'); end if;
    if not v_s.activo then perform campo.f_error('El subtipo está desactivado'); end if;
    v_sub := v_s.id;
  elsif v_t.exige_subtipo then
    perform campo.f_error('Elija un subtipo para este tipo de reporte');
  end if;
  v_desc := nullif(btrim(coalesce(p_descripcion, '')), '');
  if v_t.exige_texto and (v_desc is null or length(v_desc) < 3) then perform campo.f_error('Describa lo que encontró: este tipo de reporte lo exige'); end if;
  if length(coalesce(v_desc, '')) > v_maxdesc then perform campo.f_error(format('La descripción es demasiado larga (máximo %s caracteres)', replace(to_char(v_maxdesc, 'FM9G999'), ',', '.'))); end if;

  -- Resultado y causal (Paso D): solo en los tipos que lo llevan
  v_resultado := nullif(btrim(coalesce(p_resultado, '')), '');
  v_causal_cod := nullif(btrim(coalesce(p_causal, '')), '');
  if v_t.genera_resultado then
    if v_resultado is null then perform campo.f_error('Indique si la visita fue efectiva o inefectiva'); end if;
    if v_resultado not in ('efectivo', 'inefectivo') then perform campo.f_error('El resultado debe ser efectivo o inefectivo'); end if;
    if v_resultado = 'inefectivo' then
      if v_causal_cod is null then perform campo.f_error('Una visita inefectiva necesita la causal'); end if;
      select c.id into v_causal_id from campo.causales c
       where c.codigo = v_causal_cod and c.activo
         and (c.general or exists (select 1 from campo.causales_tipos ct where ct.causal_id = c.id and ct.tipo_id = v_t.id and ct.activo));
      if not found then perform campo.f_error('La causal no existe, está desactivada o no aplica a este formato'); end if;
    elsif v_causal_cod is not null then
      perform campo.f_error('La causal solo se informa cuando la visita es inefectiva');
    end if;
  elsif v_resultado is not null or v_causal_cod is not null then
    perform campo.f_error('Este tipo de reporte no lleva resultado ni causal');
  end if;
  v_exigir := v_resultado is distinct from 'inefectivo';

  -- Coordenada: dato numérico en rango; nunca se rechaza por la ubicación
  if p_lat is null or p_lon is null or p_lat = 'NaN'::numeric or p_lon = 'NaN'::numeric then perform campo.f_error('La coordenada no es válida'); end if;
  if p_lat < -90 or p_lat > 90 or p_lon < -180 or p_lon > 180 then perform campo.f_error('La coordenada está fuera de los rangos válidos de latitud y longitud'); end if;
  v_lat := round(p_lat, 6); v_lon := round(p_lon, 6);
  v_fuera := not (v_lat between campo.f_param('zona_lat_min') and campo.f_param('zona_lat_max')
              and v_lon between campo.f_param('zona_lon_min') and campo.f_param('zona_lon_max'));
  if p_precision_m is not null and (p_precision_m = 'NaN'::numeric or p_precision_m < 0 or p_precision_m > 100000) then perform campo.f_error('La precisión de la coordenada no es válida'); end if;
  -- Registro flexible: el XY digitado debe caer en la zona de Valledupar (ataja un dedazo; el del GPS sigue sin rechazarse) y no lleva precisión
  if v_xy and v_fuera then
    perform campo.f_error(format('El XY digitado está fuera de la zona de Valledupar (latitud %s a %s, longitud %s a %s): revíselo',
                                 trim_scale(campo.f_param('zona_lat_min')), trim_scale(campo.f_param('zona_lat_max')),
                                 trim_scale(campo.f_param('zona_lon_min')), trim_scale(campo.f_param('zona_lon_max'))));
  end if;
  if v_xy and p_precision_m is not null then perform campo.f_error('El XY digitado no lleva precisión: esa es la del GPS'); end if;
  -- La visita inefectiva con XY digitado (solo supervisor) no exige la precisión del GPS (aprobado por David, 25-nov)
  if v_resultado = 'inefectivo' and v_origen = 'campo' and not v_xy and p_precision_m is null then
    perform campo.f_error('Una visita inefectiva necesita la ubicación tomada por el celular (con su precisión): active la ubicación e intente de nuevo');
  end if;

  -- Contrato: según el tipo es obligatorio, opcional o no se pide. Solo se confirma si existe; no se lee ningún otro dato
  v_contrato := nullif(btrim(coalesce(p_contrato, '')), '');
  if v_t.requiere_contrato = 'si' and v_contrato is null then perform campo.f_error('Este formato necesita el número de contrato'); end if;
  if v_t.requiere_contrato = 'no' and v_contrato is not null then perform campo.f_error('Este formato no lleva número de contrato'); end if;
  if v_contrato is not null then
    if v_contrato !~ '^[A-Za-z0-9-]{1,20}$' then perform campo.f_error('El contrato solo puede llevar letras, números y guiones (máximo 20)'); end if;
    if v_t.limite_ventana is not null then
      perform campo.f_cupo_tipo(v_email, v_perfil, v_t.id, v_t.limite_ventana, v_t.nombre);   -- Paso D: tope propio del tipo, en vez del general de contratos
    else
      perform campo.f_cupo_contratos(v_email, v_perfil);   -- Paso B1: tope de reportes con contrato (impide enumerar contratos); antes de consultar si existe
    end if;
    perform campo.f_cupo_contratos_falsos(v_email, v_perfil);   -- Paso B1: tope de contratos NO verificados en 24 h; también antes de consultar si existe
    v_verif := exists (select 1 from public.predios_comercial pc where pc.cod_usuario = v_contrato);
  end if;

  -- Registro flexible: la dirección opcional va en Reportar anomalía (tipos generales) y en los formatos cuyo contrato no es obligatorio (David, 25-nov)
  if (v_dir is not null or v_barrio is not null or v_refer is not null) and not (campo.f_tipo_general(v_t.codigo) or v_t.requiere_contrato <> 'si') then
    perform campo.f_error('Este formato no lleva dirección: la del predio sale del contrato');
  end if;

  -- Campos propios (Paso D): validados contra la definición del tipo; los sensibles se separan
  v_val := campo.f_validar_datos(v_t.id, p_datos, v_exigir);
  v_gen := nullif(v_val -> 'general', '{}'::jsonb);
  v_sen := nullif(v_val -> 'sensibles', '{}'::jsonb);

  -- Orden de trabajo (Paso D): gancho para SCRR; hoy solo se guarda
  if p_orden_trabajo_id is not null then perform campo.f_validar_orden_trabajo(p_orden_trabajo_id, v_email, v_t.id); end if;

  -- Fotos: cantidad (mínimo y máximo del tipo), orden, etiqueta, ruta propia y objeto realmente subido (tamaño y tipo leídos de Storage)
  v_max_fotos := coalesce(v_t.fotos_max, campo.f_param('max_fotos')::integer);
  v_min_fotos := case when v_origen <> 'campo' then 0 when v_exigir then coalesce(v_t.fotos_min, 1) else least(coalesce(v_t.fotos_min, 1), 1) end;
  if jsonb_typeof(v_fotos) <> 'array' then perform campo.f_error('Las fotos no vienen en el formato esperado'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n < v_min_fotos then
    if v_min_fotos = 1 then perform campo.f_error('Un reporte de campo necesita al menos una foto'); end if;
    perform campo.f_error(format('Este formato necesita al menos %s fotos (lleva %s)', v_min_fotos, v_n));
  end if;
  if v_n > v_max_fotos then perform campo.f_error(format('Máximo %s fotos por reporte', v_max_fotos)); end if;
  if v_n > 0 and v_id is null then perform campo.f_error('Para adjuntar fotos primero debe reservarse el reporte (preparar la subida)'); end if;
  if v_n > 0 and (select count(distinct (e ->> 'orden')::integer) <> v_n or min((e ->> 'orden')::integer) <> 1 or max((e ->> 'orden')::integer) <> v_n
                    from jsonb_array_elements(v_fotos) e) then
    perform campo.f_error('El orden de las fotos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  v_con_etiquetas := exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo);
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'orden')::integer loop
    v_orden := (v_f ->> 'orden')::integer;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^reportes/[0-9]{4}-[0-9]{2}/' || v_id::text || '/' || v_orden || '\.jpg$') then
      perform campo.f_error(format('La ruta de la foto %s no corresponde a este reporte', v_orden));
    end if;
    v_etq := nullif(btrim(coalesce(v_f ->> 'etiqueta', '')), '');
    if v_con_etiquetas then
      if v_etq is null then perform campo.f_error(format('Indique qué muestra la foto %s', v_orden)); end if;
      if v_etq <> 'adicional' then
        if not exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.codigo = v_etq and tf.activo) then
          perform campo.f_error(format('La etiqueta de la foto %s no existe en este formato', v_orden));
        end if;
        if v_etq = any (v_etqs) then perform campo.f_error(format('Hay dos fotos con la misma etiqueta (foto %s)', v_orden)); end if;
      end if;
      v_etqs := v_etqs || v_etq;
    elsif v_etq is not null then
      perform campo.f_error('Este tipo de reporte no usa etiquetas de foto');
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime
      from storage.objects o where o.bucket_id = 'campo-fotos' and o.name = v_ruta;
    if not found then perform campo.f_error(format('No se encontró la foto %s: súbala de nuevo', v_orden)); end if;
    if coalesce(v_size, 0) <= 0 then perform campo.f_error(format('La foto %s está vacía', v_orden)); end if;
    if v_size > v_max_bytes then perform campo.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_orden, v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform campo.f_error(format('La foto %s debe ser JPEG', v_orden)); end if;
    v_ref := v_ref || jsonb_build_object('orden', v_orden, 'ruta', v_ruta, 'tamano', v_size, 'mime', v_mime, 'etiqueta', v_etq, 'origen', coalesce(v_f ->> 'origen', 'camara'));
  end loop;
  if v_con_etiquetas and v_exigir and v_origen = 'campo' then
    select tf.nombre into v_falta from campo.tipo_fotos tf
     where tf.tipo_id = v_t.id and tf.activo and tf.obligatoria and tf.codigo <> all (v_etqs) order by tf.orden, tf.id limit 1;
    if v_falta is not null then perform campo.f_error(format('Falta la foto obligatoria: «%s»', v_falta)); end if;
  end if;
  -- Visita inefectiva en campo: al menos una foto de la fachada o del predio (las etiquetas con soporte_inefectiva del tipo)
  if v_resultado = 'inefectivo' and v_origen = 'campo' and exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo and tf.soporte_inefectiva)
     and not exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo and tf.soporte_inefectiva and tf.codigo = any (v_etqs)) then
    perform campo.f_error('Una visita inefectiva necesita la foto de la fachada o del predio');
  end if;
  -- Pasada 14/11: hora de inicio = la del celular al abrir el formulario. Fin = la hora del servidor al registrar (v_fin: la MISMA que se guarda en registrado_en).
  v_fin := clock_timestamp();
  if p_inicio_dispositivo is not null then
    v_max_h := campo.f_param('max_horas_inicio');
    if p_inicio_dispositivo > v_fin + interval '2 minutes' then
      perform campo.f_error('La hora de su celular está adelantada. Corríjala y vuelva a enviar: lo escrito y las fotos no se pierden.');
    end if;
    if p_inicio_dispositivo < v_fin - v_max_h * interval '1 hour' then
      perform campo.f_error(format('Este formulario se abrió hace más de %s horas. Revise la hora de su celular o ábralo de nuevo.', trim_scale(v_max_h)));
    end if;
  end if;
  if v_id is null then v_id := gen_random_uuid(); end if;

  -- Inserción (una sola transacción; una carrera por el mismo id se resuelve como «repetido»).
  -- El consecutivo se toma AQUÍ, al final y dentro del mismo bloque: si la inserción falla, el número vuelve al contador (sin huecos).
  begin
    v_num := campo.f_siguiente_consecutivo(v_t.id);
    if v_num is not null then v_consecutivo := campo.f_texto_consecutivo(v_t.prefijo_consecutivo, v_num); end if;
    insert into campo.reportes (id, tipo_id, subtipo_id, descripcion, contrato, contrato_verificado, lat, lon, precision_m, riesgo_inmediato, origen, fuera_de_zona, autor,
                                datos, resultado, causal_id, consecutivo_num, consecutivo, orden_trabajo_id, registrado_en, inicio_en, inicio_origen)
    values (v_id, v_t.id, v_sub, v_desc, v_contrato, v_verif, v_lat, v_lon, p_precision_m, coalesce(p_riesgo_inmediato, false), v_origen, v_fuera, v_email,
            v_gen, v_resultado, v_causal_id, v_num, v_consecutivo, p_orden_trabajo_id, v_fin, p_inicio_dispositivo, case when p_inicio_dispositivo is not null then 'dispositivo' end)
    returning registrado_en into v_reg;
    insert into campo.reporte_fotos (reporte_id, orden, ruta_storage, tamano_bytes, tipo_mime, etiqueta, origen)
      select v_id, (x ->> 'orden')::smallint, x ->> 'ruta', (x ->> 'tamano')::integer, x ->> 'mime', x ->> 'etiqueta', x ->> 'origen' from jsonb_array_elements(v_ref) x;
    if v_sen is not null then insert into campo.reporte_datos_sensibles (reporte_id, datos) values (v_id, v_sen); end if;
    -- Registro flexible: una fila por reporte, solo si la Edge mandó el bloque (sin fila = como antes)
    if v_reg_in is not null then
      insert into campo.reporte_registro (reporte_id, xy_manual, lat_registro, lon_registro, precision_registro_m, direccion, barrio, referencia)
      values (v_id, v_xy, v_lat_r, v_lon_r, v_prec_r, v_dir, v_barrio, v_refer);
    end if;
  exception when unique_violation then
    select * into v_prev from campo.reportes where id = v_id;
    if found and v_prev.autor = v_email then
      return jsonb_build_object('id', v_prev.id, 'registrado_en', v_prev.registrado_en, 'repetido', true,
                                'contrato_verificado', v_prev.contrato_verificado, 'aviso_zona', v_prev.fuera_de_zona, 'consecutivo', v_prev.consecutivo);
    end if;
    perform campo.f_error('Una de las fotos ya está usada en otro reporte');
  end;

  -- Auditoría: nunca los valores de los campos propios, solo cuántos y si hubo sensibles
  perform campo.f_auditar(v_email, 'campo_crear_reporte', v_id::text,
    jsonb_build_object('tipo', v_t.codigo, 'subtipo', v_s.codigo, 'origen', v_origen, 'fotos', v_n, 'riesgo_inmediato', coalesce(p_riesgo_inmediato, false),
                       'fuera_de_zona', v_fuera, 'contrato_informado', v_contrato is not null, 'contrato_verificado', v_verif,
                       'consecutivo', v_consecutivo, 'resultado', v_resultado, 'causal', case when v_causal_id is not null then v_causal_cod end, 'con_inicio', p_inicio_dispositivo is not null,
                       'campos', (select count(*) from jsonb_object_keys(coalesce(v_gen, '{}'::jsonb))), 'campos_sensibles', v_sen is not null,
                       'orden_trabajo', p_orden_trabajo_id is not null)
    -- Registro flexible: solo marcas, nunca las coordenadas ni la dirección
    || case when v_reg_in is null then '{}'::jsonb else jsonb_build_object('xy_manual', v_xy, 'fotos_adjuntadas', v_no_camara, 'con_ubicacion_dispositivo', v_lat_r is not null,
                                                                        'con_direccion', v_dir is not null or v_barrio is not null or v_refer is not null) end, p_ip);
  return jsonb_build_object('id', v_id, 'registrado_en', v_reg, 'repetido', false, 'contrato_verificado', v_verif, 'aviso_zona', v_fuera, 'consecutivo', v_consecutivo);
end $function$;

revoke all on function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone, jsonb)
  to service_role;

-- Entrada de Técnica (Corte 8): la misma firma con p_registro al final. Desde Técnica solo viaja la ubicación del dispositivo y la dirección opcional;
-- el XY digitado y las fotos adjuntadas los rechaza geoportal_campo_crear_reporte (geoportal.via_tecnica). DROP: por qué y alcance — solo esa firma, reemplazada aquí.
drop function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone);
CREATE FUNCTION public.geoportal_campo_tec_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone, p_registro jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'tecnica', 'pg_temp'
AS $function$
declare v jsonb;
begin
  if p_tipo is null then raise exception 'Falta el tipo de reporte' using errcode = '22023'; end if;
  perform campo.f_tecnica_entrar(p_solicitante, p_tipo);
  v := public.geoportal_campo_crear_reporte(p_solicitante, p_id, p_tipo, p_subtipo, p_descripcion, p_contrato, p_lat, p_lon, p_precision_m, p_riesgo_inmediato, 'campo', p_fotos,
                                            p_ip, p_datos, p_resultado, p_causal, null, p_inicio_dispositivo, p_registro);
  perform set_config('geoportal.via_tecnica', '', true);
  return v || jsonb_build_object('area', 'tecnica');
end $function$;
revoke all on function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone, jsonb)
  to service_role;
