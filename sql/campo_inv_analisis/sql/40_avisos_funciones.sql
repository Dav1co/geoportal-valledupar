-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 40 — AVISOS DEL ANÁLISIS DE CONTRATO: funciones
-- Cambian (respaldo y md5 en la guardia y en la reversa): campo.f_derivada_json, geoportal_campo_derivadas (filtro «origen»),
-- geoportal_campo_derivada_atender y geoportal_campo_derivadas_abiertas (usan el destino propio de la derivada si lo hay).
-- Nuevas: campo.f_contacto y campo.f_texto_sin_datos (validan), geoportal_campo_analisis_observar (marca), geoportal_campo_aviso_crear_actividad,
-- geoportal_campo_aviso_datos y geoportal_campo_aviso_datos_anular (supervisor de campo y administrador).
-- Ninguna lleva DELETE ni UPDATE.
-- =====================================================================

-- Datos de contacto de «Actualización de datos»: valida y normaliza. Las casillas vacías no cuentan; ninguna casilla = null.
create function campo.f_contacto(p jsonb) returns jsonb
language plpgsql immutable set search_path = pg_catalog, campo, pg_temp as $f$
declare v jsonb := '{}'::jsonb; k text; x text;
begin
  if p is null or p = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p) <> 'object' then perform campo.f_error('Los datos de contacto no tienen el formato esperado'); end if;
  select min(key) into k from jsonb_object_keys(p) key where key not in ('nombre', 'cedula', 'telefono', 'correo', 'relacion');
  if k is not null then perform campo.f_error(format('El dato «%s» no se recibe', left(k, 40))); end if;
  for k in select key from jsonb_object_keys(p) key loop
    if jsonb_typeof(p -> k) not in ('string', 'null') then perform campo.f_error(format('El dato «%s» debe ser un texto', k)); end if;
  end loop;
  x := nullif(btrim(regexp_replace(coalesce(p ->> 'nombre', ''), '\s+', ' ', 'g')), '');
  if x is not null then
    if length(x) < 2 or length(x) > 80 or x ~ '\d' or x !~ '^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ .''-]*$' then
      perform campo.f_error('El nombre debe tener entre 2 y 80 letras, sin números');
    end if;
    v := v || jsonb_build_object('nombre', x);
  end if;
  x := nullif(btrim(coalesce(p ->> 'cedula', '')), '');
  if x is not null then
    if x !~ '^\d{5,10}$' then perform campo.f_error('La cédula debe tener solo números, entre 5 y 10'); end if;
    v := v || jsonb_build_object('cedula', x);
  end if;
  x := nullif(regexp_replace(coalesce(p ->> 'telefono', ''), '[\s()-]', '', 'g'), '');
  if x is not null then
    if x !~ '^(\d{7}|3\d{9}|60\d{8})$' then perform campo.f_error('El teléfono debe tener 7 o 10 números; si tiene 10, empieza por 3 o por 60'); end if;
    v := v || jsonb_build_object('telefono', x);
  end if;
  x := nullif(lower(btrim(coalesce(p ->> 'correo', ''))), '');
  if x is not null then
    if length(x) > 120 or x !~ '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$' then perform campo.f_error('El correo no tiene un formato válido'); end if;
    v := v || jsonb_build_object('correo', x);
  end if;
  x := nullif(btrim(coalesce(p ->> 'relacion', '')), '');
  if x is not null then
    if x not in ('propietario', 'arrendatario', 'familiar', 'encargado', 'otro') then
      perform campo.f_error('La relación con el predio debe ser propietario, arrendatario, familiar, encargado u otro');
    end if;
    v := v || jsonb_build_object('relacion', x);
  end if;
  return nullif(v, '{}'::jsonb);
end $f$;

-- Textos libres del aviso (texto de «Otra» y dirección correcta): sin teléfonos ni números largos (cédulas). Devuelve el texto limpio o null.
create function campo.f_texto_sin_datos(p_texto text, p_que text, p_min integer, p_max integer) returns text
language plpgsql immutable set search_path = pg_catalog, campo, pg_temp as $f$
declare v text := nullif(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), '');
begin
  if v is null then return null; end if;
  if length(v) < p_min or length(v) > p_max then perform campo.f_error(format('%s debe tener entre %s y %s caracteres', p_que, p_min, p_max)); end if;
  if coalesce(cardinality(campo.f_telefonos(v)), 0) > 0 or v ~ '\d{6,}' then
    perform campo.f_error(format('%s no puede llevar teléfonos ni cédulas: esos datos van en sus casillas de «Actualización de datos»', p_que));
  end if;
  return v;
end $f$;

CREATE OR REPLACE FUNCTION campo.f_derivada_json(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'campo', 'pg_temp'
AS $function$
  -- Investigación y Análisis (23-nov): el origen es un registro (revisión, PQR, instalación) o una observación del Análisis de contrato.
  -- Sin datos de contacto: solo «trae_datos» y «datos_anulados». El destino propio de la derivada (actividad creada por el supervisor) manda sobre el del catálogo.
  select jsonb_build_object('id', d.id, 'actividad', d.actividad, 'actividad_nombre', c.nombre, 'contrato', d.contrato, 'estado', campo.f_derivada_estado(d.id), 'creada_en', d.creado_en,
           -- sección 7: días (de calendario, hora de Colombia) desde que se creó; los pendientes viejos no se cierran solos y muestran su antigüedad
           'antiguedad_dias', (clock_timestamp() at time zone 'America/Bogota')::date - (d.creado_en at time zone 'America/Bogota')::date,
           'destinos', case when d.destino is not null then jsonb_build_array(d.destino) else to_jsonb(c.destinos) end,
           'destino_omision', coalesce(d.destino, c.destino_omision),
           'destino_nombre', (select t2.nombre from campo.tipos_reporte t2 where 'tipo:' || t2.codigo = d.destino),
           'origen', case when d.origen_id is not null then
               jsonb_build_object('clase', 'registro', 'registro_id', r.id, 'tipo', t.codigo, 'tipo_nombre', t.nombre, 'consecutivo', r.consecutivo, 'fecha', r.registrado_en, 'operario', r.autor)
             else
               jsonb_build_object('clase', 'analisis', 'observacion_id', o.id, 'tipo', 'analisis_contrato', 'tipo_nombre', 'Análisis de contrato', 'observacion', o.tipo,
                                  'observacion_nombre', case o.tipo when 'desocupado' then 'Desocupado' when 'direccion_errada' then 'Dirección errada'
                                                                    when 'actualizacion_datos' then 'Actualización de datos' else 'Otra' end,
                                  'texto', o.texto, 'direccion_correcta', o.direccion_correcta, 'fecha', o.creado_en, 'operario', o.autor,
                                  'trae_datos', exists (select 1 from campo.analisis_observacion_datos x where x.observacion_id = o.id),
                                  -- anulados = tiene entregas y ninguna está vigente (sin anular); entregas = cuántas recibió el aviso (David, 24-nov)
                                  'datos_anulados', exists (select 1 from campo.analisis_observacion_datos x where x.observacion_id = o.id)
                                                    and not exists (select 1 from campo.analisis_observacion_datos x where x.observacion_id = o.id
                                                                      and not exists (select 1 from campo.analisis_observacion_anulaciones a where a.datos_id = x.id)),
                                  'entregas_datos', (select count(*) from campo.analisis_observacion_datos x where x.observacion_id = o.id),
                                  'entregas_vigentes', (select count(*) from campo.analisis_observacion_datos x where x.observacion_id = o.id
                                                         and not exists (select 1 from campo.analisis_observacion_anulaciones a where a.datos_id = x.id)),
                                  'aviso_id', (select a.id from campo.derivadas a where a.observacion_id = o.id and a.actividad like 'aviso\_%'),
                                  'actividad_creada_id', (select a.id from campo.derivadas a where a.observacion_id = o.id and a.actividad = 'actividad_supervisor'),
                                  -- sección 7: cuántas veces lo vieron otra vez dentro de la vigencia, y la última
                                  'vistos', (select count(*) from campo.analisis_avisos_vistos v where v.observacion_id = o.id),
                                  'ultimo_visto', (select jsonb_build_object('en', v.visto_en, 'autor', v.autor) from campo.analisis_avisos_vistos v
                                                    where v.observacion_id = o.id order by v.visto_en desc, v.id desc limit 1))
             end,
           'cierre', (select jsonb_build_object('tipo', e.tipo_evento, 'esquema', e.esquema, 'registro_id', e.registro_id, 'autor', e.autor, 'en', e.creado_en, 'motivo', e.motivo,
                                                 'consecutivo', case e.esquema when 'campo' then (select x.consecutivo from campo.reportes x where x.id = e.registro_id)
                                                                               when 'acta' then (select x.consecutivo from acta.actas x where x.id = e.registro_id) end)
                        from campo.derivada_eventos e where e.derivada_id = d.id))
    from campo.derivadas d join campo.derivadas_catalogo c on c.codigo = d.actividad
    left join campo.reportes r on r.id = d.origen_id left join campo.tipos_reporte t on t.id = r.tipo_id
    left join campo.analisis_observaciones o on o.id = d.observacion_id
   where d.id = p_id
$function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivadas(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_est text; v_con text; v_act text; v_desde date; v_hasta date; v_antes bigint; v_lim integer; v_filas jsonb; v_n integer;
  v_ori text;   -- Investigación y Análisis (23-nov): «registro» (revisiones, PQR, instalación) o «analisis» (avisos del Análisis de contrato)
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_est := nullif(f ->> 'estado', ''); v_con := nullif(btrim(coalesce(f ->> 'contrato', '')), ''); v_act := nullif(f ->> 'actividad', '');
    v_desde := nullif(f ->> 'desde', '')::date; v_hasta := nullif(f ->> 'hasta', '')::date; v_antes := nullif(f ->> 'antes', '')::bigint;
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 50), 1), 200);
    v_ori := nullif(f ->> 'origen', '');
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  if v_est is not null and v_est not in ('pendiente', 'atendida', 'atendida_fuera', 'anulada') then perform campo.f_error('El estado no es válido'); end if;
  if v_ori is not null and v_ori not in ('registro', 'analisis') then perform campo.f_error('El origen no es válido'); end if;
  select count(*), coalesce(jsonb_agg(campo.f_derivada_json(x.id) order by x.id desc) filter (where x.rn <= v_lim), '[]'::jsonb) into v_n, v_filas
    from (select d.id, row_number() over (order by d.id desc) as rn from campo.derivadas d
           where (v_est is null or campo.f_derivada_estado(d.id) = v_est) and (v_con is null or d.contrato = v_con) and (v_act is null or d.actividad = v_act)
             and (v_ori is null or (v_ori = 'registro' and d.origen_id is not null) or (v_ori = 'analisis' and d.observacion_id is not null))
             and (v_desde is null or (d.creado_en at time zone 'America/Bogota')::date >= v_desde) and (v_hasta is null or (d.creado_en at time zone 'America/Bogota')::date <= v_hasta)
             and (v_antes is null or d.id < v_antes) order by d.id desc limit v_lim + 1) x;
  return jsonb_build_object('filas', v_filas, 'siguiente', case when v_n > v_lim then (select min((e ->> 'id')::bigint) from jsonb_array_elements(v_filas) e) end);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivada_atender(p_solicitante text, p_derivada_id bigint, p_esquema text, p_registro_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'acta', 'pg_temp'
AS $function$
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
  -- Investigación y Análisis (23-nov): la actividad que crea el supervisor trae su propio destino
  if not (v_form = any (case when v_d.destino is not null then array[v_d.destino] else v_c.destinos end)) then perform campo.f_error('Ese formulario no atiende esa actividad derivada'); end if;
  if v_con is distinct from v_d.contrato then perform campo.f_error('El registro es de otro contrato'); end if;
  if v_d.origen_id is not null and p_registro_id = v_d.origen_id then perform campo.f_error('Una revisión no atiende sus propias actividades derivadas'); end if;
  insert into campo.derivada_eventos (derivada_id, tipo_evento, esquema, registro_id, autor) values (v_d.id, 'atendida', p_esquema, p_registro_id, v_email);
  perform campo.f_auditar(v_email, 'campo_derivada_atender', v_d.id::text, jsonb_build_object('esquema', p_esquema, 'registro', p_registro_id), p_ip);
  return campo.f_derivada_json(v_d.id);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivadas_abiertas(p_solicitante text, p_contrato text, p_formulario text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'acta', 'pg_temp'
AS $function$
declare v_email text; v_con text := nullif(btrim(coalesce(p_contrato, '')), '');
begin
  if p_formulario = 'acta' then v_email := acta.f_autorizar(p_solicitante, 'capturar'); else v_email := campo.f_verificar(p_solicitante, 'campo'); end if;
  if v_con is null then return jsonb_build_object('derivadas', '[]'::jsonb); end if;
  -- Investigación y Análisis (23-nov): la actividad que crea el supervisor trae su propio destino; los avisos no tienen destino y no aparecen
  return jsonb_build_object('derivadas', (select coalesce(jsonb_agg(campo.f_derivada_json(d.id) order by d.id), '[]'::jsonb)
    from campo.derivadas d join campo.derivadas_catalogo c on c.codigo = d.actividad
   where d.contrato = v_con and p_formulario = any (case when d.destino is not null then array[d.destino] else c.destinos end) and campo.f_derivada_estado(d.id) = 'pendiente'));
end $function$;

-- Marcar una observación desde el Análisis de contrato (quien tenga Análisis y haya consultado ese contrato en las últimas 12 horas)
create function public.geoportal_campo_analisis_observar(p_solicitante text, p_contrato text, p_tipo text, p_texto text default null, p_direccion text default null,
                                                         p_contacto jsonb default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $f$
declare v_email text; v_c text := btrim(coalesce(p_contrato, '')); v_tipo text := btrim(coalesce(p_tipo, '')); v_txt text; v_dir text; v_con jsonb;
  v_obs uuid; v_der bigint; v_prev bigint; v_prev_obs uuid; v_prev_en timestamptz; v_vig integer; v_dup_rel text; v_dup_por text;
begin
  v_email := campo.f_autorizar_analisis(p_solicitante);
  if v_c !~ '^\d{1,12}$' then perform campo.f_error('Escriba solo los números del contrato (hasta 12 dígitos)'); end if;
  if v_c = '99999999' then perform campo.f_error('El contrato comodín no admite observaciones'); end if;
  if v_tipo not in ('desocupado', 'direccion_errada', 'actualizacion_datos', 'otra') then
    perform campo.f_error('La observación debe ser desocupado, dirección errada, actualización de datos u otra');
  end if;
  if not exists (select 1 from campo.consultas_analisis q where q.autor = v_email and q.contrato = v_c and q.existe and q.consultado_en > clock_timestamp() - interval '12 hours') then
    perform campo.f_error('Primero consulte el contrato en el Análisis (la observación se marca sobre un contrato consultado en las últimas 12 horas)', '55000');
  end if;
  v_txt := campo.f_texto_sin_datos(p_texto, 'El texto de «Otra»', 3, 120);
  v_dir := campo.f_texto_sin_datos(p_direccion, 'La dirección correcta', 3, 120);
  v_con := campo.f_contacto(p_contacto);
  if (v_tipo = 'otra') <> (v_txt is not null) then
    perform campo.f_error(case when v_tipo = 'otra' then 'Escriba la observación (entre 3 y 120 caracteres)' else 'El texto corto solo va en «Otra»' end);
  end if;
  if v_dir is not null and v_tipo <> 'direccion_errada' then perform campo.f_error('La dirección correcta solo va en «Dirección errada»'); end if;
  if v_con is not null and v_tipo <> 'actualizacion_datos' then perform campo.f_error('Los datos de contacto solo van en «Actualización de datos»'); end if;

  perform pg_advisory_xact_lock(hashtext('campo_aviso:' || v_c));
  if v_tipo = 'desocupado' then
    -- «Desocupado» (sección 7, David 24-nov): vigencia. Dentro de vigencia_avisos_dias desde el aviso ORIGINAL del mismo contrato, esté pendiente o cerrado, no se
    -- crea otro: se anota «visto otra vez». La vigencia cuenta desde el aviso original, no desde el último «visto otra vez». Pasada la vigencia, aviso nuevo.
    v_vig := campo.f_param('vigencia_avisos_dias')::integer;
    select o.id, o.creado_en, d.id into v_prev_obs, v_prev_en, v_prev
      from campo.analisis_observaciones o join campo.derivadas d on d.observacion_id = o.id and d.actividad = 'aviso_' || v_tipo
     where o.contrato = v_c and o.tipo = v_tipo and o.creado_en > clock_timestamp() - make_interval(days => v_vig)
     order by o.creado_en desc limit 1;
    if v_prev is not null then
      insert into campo.analisis_avisos_vistos (observacion_id, autor, ip) values (v_prev_obs, v_email, left(p_ip, 64));
      perform campo.f_auditar(v_email, 'campo_analisis_visto_otra_vez', v_prev_obs::text, jsonb_build_object('tipo', v_tipo, 'derivada', v_prev), p_ip);
      return jsonb_build_object('repetida', true, 'regla', 'vigencia', 'derivada_id', v_prev, 'tipo', v_tipo, 'contrato', v_c, 'ya_avisado_en', v_prev_en,
        'estado', campo.f_derivada_estado(v_prev), 'vistos', (select count(*) from campo.analisis_avisos_vistos v where v.observacion_id = v_prev_obs),
        'vigencia_dias', v_vig, 'datos_no_guardados', false);
    end if;
  else
    -- Dirección errada, Actualización de datos y Otra (David, 24-nov): uno PENDIENTE a la vez por contrato («Otra»: con el mismo texto; un texto distinto crea
    -- su propio aviso). Cerrado el anterior, se puede avisar de nuevo sin importar los días.
    select o.id, o.creado_en, d.id into v_prev_obs, v_prev_en, v_prev
      from campo.analisis_observaciones o join campo.derivadas d on d.observacion_id = o.id and d.actividad = 'aviso_' || v_tipo
     where o.contrato = v_c and o.tipo = v_tipo and campo.f_derivada_estado(d.id) = 'pendiente'
       and (v_tipo <> 'otra' or lower(o.texto) = lower(v_txt))
     order by o.creado_en desc limit 1;
    if v_prev is not null then
      -- «Actualización de datos» (David, 24-nov, revisión 7.4): SIN restricción de envíos. Cada envío con datos es una entrega más del aviso pendiente del contrato
      -- (propietario, arrendatario, correcciones). Si ya hay una entrega VIGENTE con la misma relación o la misma cédula, se guarda igual y se avisa del posible duplicado.
      if v_tipo = 'actualizacion_datos' and v_con is not null then
        select x.datos ->> 'relacion', case when v_con ? 'relacion' and x.datos ->> 'relacion' = v_con ->> 'relacion' then 'relacion' else 'cedula' end
          into v_dup_rel, v_dup_por
          from campo.analisis_observacion_datos x
         where x.observacion_id = v_prev_obs and not exists (select 1 from campo.analisis_observacion_anulaciones a where a.datos_id = x.id)
           and ((v_con ? 'relacion' and x.datos ->> 'relacion' = v_con ->> 'relacion') or (v_con ? 'cedula' and x.datos ->> 'cedula' = v_con ->> 'cedula'))
         order by x.id desc limit 1;
        insert into campo.analisis_observacion_datos (observacion_id, datos, autor) values (v_prev_obs, v_con, v_email);
        perform campo.f_auditar(v_email, 'campo_analisis_datos_entrega', v_prev_obs::text, jsonb_build_object('derivada', v_prev, 'posible_duplicado', v_dup_por is not null), p_ip);
        return jsonb_build_object('repetida', true, 'regla', 'pendiente', 'derivada_id', v_prev, 'tipo', v_tipo, 'contrato', v_c, 'ya_avisado_en', v_prev_en,
          'estado', 'pendiente', 'datos_guardados', true, 'trae_datos', true, 'posible_duplicado', v_dup_por is not null,
          'duplicado_por', v_dup_por, 'duplicado_relacion', case when v_dup_por = 'relacion' then v_dup_rel end);
      end if;
      perform campo.f_auditar(v_email, 'campo_analisis_ya_pendiente', v_prev_obs::text, jsonb_build_object('tipo', v_tipo, 'derivada', v_prev), p_ip);
      return jsonb_build_object('repetida', true, 'regla', 'pendiente', 'derivada_id', v_prev, 'tipo', v_tipo, 'contrato', v_c, 'ya_avisado_en', v_prev_en,
        'estado', 'pendiente', 'datos_no_guardados', (v_con is not null or v_dir is not null));
    end if;
  end if;

  insert into campo.analisis_observaciones (contrato, tipo, texto, direccion_correcta, autor, ip) values (v_c, v_tipo, v_txt, v_dir, v_email, left(p_ip, 64)) returning id into v_obs;
  if v_con is not null then insert into campo.analisis_observacion_datos (observacion_id, datos, autor) values (v_obs, v_con, v_email); end if;
  insert into campo.derivadas (observacion_id, contrato, actividad) values (v_obs, v_c, 'aviso_' || v_tipo) returning id into v_der;
  -- Auditoría sin el contrato (queda en la bitácora del análisis, decisión 15) ni los textos ni los datos de contacto
  perform campo.f_auditar(v_email, 'campo_analisis_observar', v_obs::text, jsonb_build_object('tipo', v_tipo, 'derivada', v_der, 'trae_datos', v_con is not null), p_ip);
  return jsonb_build_object('repetida', false, 'observacion_id', v_obs, 'derivada_id', v_der, 'tipo', v_tipo, 'contrato', v_c, 'trae_datos', v_con is not null);
end $f$;

-- «Crear actividad» desde un aviso (Q1): una sola por aviso; el aviso se cierra solo como «atendida fuera» con motivo automático
create function public.geoportal_campo_aviso_crear_actividad(p_solicitante text, p_derivada_id bigint, p_formulario text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $f$
declare v_email text; v_d campo.derivadas; v_t campo.tipos_reporte; v_nueva bigint; v_form text := btrim(coalesce(p_formulario, ''));
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  perform pg_advisory_xact_lock(hashtext('campo_derivada:' || p_derivada_id));
  select * into v_d from campo.derivadas where id = p_derivada_id;
  if v_d.id is null then perform campo.f_error('Ese aviso no existe', 'P0002'); end if;
  if v_d.observacion_id is null or v_d.actividad not like 'aviso\_%' then perform campo.f_error('Solo se crea una actividad desde un aviso del Análisis de contrato'); end if;
  if campo.f_derivada_estado(v_d.id) <> 'pendiente' then perform campo.f_error('Ese aviso ya está cerrado', '55000'); end if;
  select t.* into v_t from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where 'tipo:' || t.codigo = v_form and t.activo and g.activo and t.requiere_contrato = 'si';
  if v_t.id is null then perform campo.f_error('Elija un formulario activo que pida el contrato'); end if;
  insert into campo.derivadas (observacion_id, contrato, actividad, destino) values (v_d.observacion_id, v_d.contrato, 'actividad_supervisor', v_form) returning id into v_nueva;
  insert into campo.derivada_eventos (derivada_id, tipo_evento, motivo, autor) values (v_d.id, 'atendida_fuera', left('Se creó la actividad: ' || v_t.nombre, 300), v_email);
  perform campo.f_auditar(v_email, 'campo_aviso_crear_actividad', v_d.id::text, jsonb_build_object('actividad', v_nueva, 'formulario', v_form), p_ip);
  return jsonb_build_object('aviso', campo.f_derivada_json(v_d.id), 'actividad', campo.f_derivada_json(v_nueva));
end $f$;

-- Ver los datos de contacto de un aviso (supervisor de campo y administrador); lectura auditada sin los valores (David, 24-nov, 7.4):
-- cada entrega con su relación, autor y fecha; las vigentes con sus datos y la marca de posible duplicado (misma relación o misma cédula que otra vigente);
-- las anuladas, solo con su motivo (Q2: los valores no se muestran).
create function public.geoportal_campo_aviso_datos(p_solicitante text, p_derivada_id bigint, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $f$
declare v_email text; v_obs uuid; v_entregas jsonb; v_n integer; v_vigentes integer;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select d.observacion_id into v_obs from campo.derivadas d where d.id = p_derivada_id;
  if v_obs is null then perform campo.f_error('Ese aviso no existe o no es del Análisis de contrato', 'P0002'); end if;
  with e as (
    select x.id, x.datos, x.autor, x.registrado_en, a.datos_id is not null as anulada, a.motivo, a.creado_en as anulada_en, a.autor as anulada_por
      from campo.analisis_observacion_datos x left join campo.analisis_observacion_anulaciones a on a.datos_id = x.id
     where x.observacion_id = v_obs)
  select count(*), count(*) filter (where not e.anulada),
         coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'autor', e.autor, 'registrado_en', e.registrado_en, 'relacion', e.datos ->> 'relacion', 'anulada', e.anulada)
           || case when e.anulada then jsonb_build_object('motivo', e.motivo, 'anulada_en', e.anulada_en, 'anulada_por', e.anulada_por)
                   else jsonb_build_object('datos', e.datos, 'posible_duplicado', exists (
                          select 1 from e o where o.id <> e.id and not o.anulada
                             and ((e.datos ? 'relacion' and o.datos ->> 'relacion' = e.datos ->> 'relacion') or (e.datos ? 'cedula' and o.datos ->> 'cedula' = e.datos ->> 'cedula')))) end
           order by e.id), '[]'::jsonb)
    into v_n, v_vigentes, v_entregas from e;
  if v_n = 0 then perform campo.f_error('Ese aviso no tiene datos de contacto', 'P0002'); end if;
  perform campo.f_auditar(v_email, 'campo_ver_datos_contacto', p_derivada_id::text,
                          jsonb_build_object('entregas', v_n, 'vigentes', v_vigentes,
                                             'campos', (select jsonb_agg(distinct k order by k) from campo.analisis_observacion_datos x, jsonb_object_keys(x.datos) k
                                                         where x.observacion_id = v_obs and not exists (select 1 from campo.analisis_observacion_anulaciones a where a.datos_id = x.id))), p_ip);
  return jsonb_build_object('derivada_id', p_derivada_id, 'entregas', v_entregas, 'total', v_n, 'vigentes', v_vigentes, 'anulados', v_vigentes = 0);
end $f$;

-- Anular UNA entrega de datos de contacto (estaba mal o sobra): queda guardada, ya no se muestra
create function public.geoportal_campo_aviso_datos_anular(p_solicitante text, p_derivada_id bigint, p_datos_id bigint, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $f$
declare v_email text; v_obs uuid; v_m text;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  v_m := campo.f_motivo_personal(p_motivo, true);
  select d.observacion_id into v_obs from campo.derivadas d where d.id = p_derivada_id;
  if v_obs is null then perform campo.f_error('Ese aviso no existe o no es del Análisis de contrato', 'P0002'); end if;
  -- el mismo bloqueo por contrato que analisis_observar: anular y una entrega nueva no se cruzan
  perform pg_advisory_xact_lock(hashtext('campo_aviso:' || (select o.contrato from campo.analisis_observaciones o where o.id = v_obs)));
  if not exists (select 1 from campo.analisis_observacion_datos x where x.id = p_datos_id and x.observacion_id = v_obs) then
    perform campo.f_error('Esa entrega de datos no es de este aviso', 'P0002');
  end if;
  if exists (select 1 from campo.analisis_observacion_anulaciones a where a.datos_id = p_datos_id) then perform campo.f_error('Esa entrega ya está anulada', '55000'); end if;
  insert into campo.analisis_observacion_anulaciones (datos_id, motivo, autor, ip) values (p_datos_id, v_m, v_email, left(p_ip, 64));
  perform campo.f_auditar(v_email, 'campo_anular_datos_contacto', p_derivada_id::text, jsonb_build_object('entrega', p_datos_id), p_ip);
  return jsonb_build_object('derivada_id', p_derivada_id, 'datos_id', p_datos_id, 'anulada', true, 'motivo', v_m);
end $f$;

-- Permisos: las funciones nuevas, primero sin permisos para nadie; las 4 RPC, solo service_role (la Edge). CREATE OR REPLACE conserva los de las que cambian.
revoke all on function campo.f_contacto(jsonb), campo.f_texto_sin_datos(text, text, integer, integer),
  public.geoportal_campo_analisis_observar(text, text, text, text, text, jsonb, text), public.geoportal_campo_aviso_crear_actividad(text, bigint, text, text),
  public.geoportal_campo_aviso_datos(text, bigint, text), public.geoportal_campo_aviso_datos_anular(text, bigint, bigint, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_analisis_observar(text, text, text, text, text, jsonb, text), public.geoportal_campo_aviso_crear_actividad(text, bigint, text, text),
  public.geoportal_campo_aviso_datos(text, bigint, text), public.geoportal_campo_aviso_datos_anular(text, bigint, bigint, text, text) to service_role;
