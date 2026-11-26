-- [Code A] REGISTRO FLEXIBLE (25-nov) · REVERSA (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 90 — REVERSA
-- Devuelve crear_reporte y la entrada de Técnica a su firma y texto publicados, y la lista, el detalle, la descarga, los datos del PDF y la lista de derivadas a
-- su texto publicado; quita las 5 funciones nuevas (filtro y correos de las derivadas, y las 3 de la descarga auditada). La huella de campo vuelve a cce593806f59d3d27c34d7f2070cc5c1.
-- NADA SE BORRA: campo.reporte_registro y la columna campo.reporte_fotos.origen se conservan con sus datos (las funciones publicadas no las leen; el sello del
-- PDF de cualquier reporte vuelve a ser el de antes porque campo.reportes no cambió).
-- =====================================================================
do $rev$
declare r record; v_xy bigint; v_adj bigint;
begin
  for r in select * from (values ('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone,jsonb)', 'cfb2dbb022ae0f6e93989dcc6579e4d8'), ('public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone,jsonb)', '8ae23410abdba2194377b5ae19abc417'), ('public.geoportal_campo_listar_reportes(text,jsonb,text)', 'c6a74c023f37e5e0de7527b71d7cb369'), ('public.geoportal_campo_obtener_reporte(text,uuid,text)', 'bf9900e35a4051a00fec8b87cb34f153'), ('public.geoportal_campo_descarga_pagina(text,bigint,bigint,integer)', '0f4ce407e77abe49b1e6cc6132507f86'), ('public.geoportal_campo_pdf_datos(text,text,uuid,text)', '52d496ead7c6ea884b1c58b8c80541eb'), ('public.geoportal_campo_derivadas(text,jsonb,text)', '87250167e19a0b95ff7c40c351638a52')) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise', r.f;
    end if;
  end loop;
  select count(*) filter (where xy_manual) into v_xy from campo.reporte_registro;
  select count(*) into v_adj from campo.reporte_fotos where origen <> 'camara';
  raise notice 'Reversa del registro flexible: % reportes con XY digitado y % fotos adjuntadas conservan su marca en campo.reporte_registro y campo.reporte_fotos.origen (las pantallas de antes no la muestran)', v_xy, v_adj;
end $rev$;

-- DROP (por qué y alcance): las dos firmas con p_registro las creó este paquete y se reemplazan aquí mismo por las publicadas. Alcance: SOLO esas 2 firmas.
drop function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone, jsonb);
drop function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone, jsonb);

CREATE OR REPLACE FUNCTION public.geoportal_campo_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_origen text, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_orden_trabajo_id uuid DEFAULT NULL::uuid, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone)
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
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);
  v_perfil := campo.f_perfil(v_email);
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
  if v_resultado = 'inefectivo' and v_origen = 'campo' and p_precision_m is null then
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
    v_ref := v_ref || jsonb_build_object('orden', v_orden, 'ruta', v_ruta, 'tamano', v_size, 'mime', v_mime, 'etiqueta', v_etq);
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
    insert into campo.reporte_fotos (reporte_id, orden, ruta_storage, tamano_bytes, tipo_mime, etiqueta)
      select v_id, (x ->> 'orden')::smallint, x ->> 'ruta', (x ->> 'tamano')::integer, x ->> 'mime', x ->> 'etiqueta' from jsonb_array_elements(v_ref) x;
    if v_sen is not null then insert into campo.reporte_datos_sensibles (reporte_id, datos) values (v_id, v_sen); end if;
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
                       'orden_trabajo', p_orden_trabajo_id is not null), p_ip);
  return jsonb_build_object('id', v_id, 'registrado_en', v_reg, 'repetido', false, 'contrato_verificado', v_verif, 'aviso_zona', v_fuera, 'consecutivo', v_consecutivo);
end $function$;
revoke all on function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone)
  to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_campo_tec_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone)
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
                                            p_ip, p_datos, p_resultado, p_causal, null, p_inicio_dispositivo);
  perform set_config('geoportal.via_tecnica', '', true);
  return v || jsonb_build_object('area', 'tecnica');
end $function$;
revoke all on function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone)
  to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_campo_listar_reportes(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v_f jsonb := coalesce(p_filtros, '{}'::jsonb); v_ids uuid[]; v_total integer; v_eps numeric; v_lim integer; v_cur bigint;
        v_rows jsonb; v_min bigint; v_mas boolean;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  v_eps := campo.f_param('distancia_duplicados_m');
  v_lim := least(greatest(coalesce(nullif(v_f ->> 'limite', '')::integer, 1000), 1), 5000);
  v_cur := nullif(v_f ->> 'cursor', '')::bigint;
  select coalesce(array_agg(x.id), '{}'::uuid[]), count(*)::integer into v_ids, v_total from campo.f_filtrar(v_f) x;
  with pag as (
    select x.*, row_number() over (order by x.seq desc) as rn
      from campo.f_filtrar(v_f) x where v_cur is null or x.seq < v_cur order by x.seq desc limit v_lim + 1
  ), cl as (select * from campo.f_grupos_cercanos(v_eps, v_ids)),
  fila as (
    select p.*, t.codigo as tipo_codigo, t.nombre as tipo_nombre, g.codigo as grupo_codigo, g.nombre as grupo_nombre,
           s.codigo as sub_codigo, s.nombre as sub_nombre, cl.grupo_id as grupo_dup, cl.tamano as tam_dup,
           ca.codigo as causal_codigo, ca.nombre as causal_nombre
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
     where p.rn <= v_lim
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'seq', f.seq,
           'tipo', jsonb_build_object('codigo', f.tipo_codigo, 'nombre', f.tipo_nombre),
           'grupo', jsonb_build_object('codigo', f.grupo_codigo, 'nombre', f.grupo_nombre),
           'subtipo', case when f.sub_codigo is null then null else jsonb_build_object('codigo', f.sub_codigo, 'nombre', f.sub_nombre) end,
           'descripcion', f.descripcion, 'contrato', f.contrato, 'contrato_verificado', f.contrato_verificado,
           'lat', f.lat, 'lon', f.lon, 'precision_m', f.precision_m, 'riesgo_inmediato', f.riesgo_inmediato, 'origen', f.origen,
           'fuera_de_zona', f.fuera_de_zona, 'autor', f.autor, 'registrado_en', f.registrado_en,
           'estado', f.estado, 'estado_desde', f.estado_desde, 'oculto', f.oculto, 'reporte_original_id', f.reporte_original_id,
           'grupo_duplicados', f.grupo_dup, 'tamano_grupo', f.tam_dup, 'n_fotos', f.n_fotos)
           -- Paso D
           || jsonb_build_object(
           'consecutivo', f.consecutivo, 'resultado', f.resultado,
           'causal', case when f.causal_codigo is null then null else jsonb_build_object('codigo', f.causal_codigo, 'nombre', f.causal_nombre) end,
           'orden_trabajo_id', f.orden_trabajo_id, 'datos', coalesce(f.datos, '{}'::jsonb), 'tiene_datos_sensibles', f.tiene_datos_sensibles,
           'inicio_en', f.inicio_en, 'inicio_origen', f.inicio_origen) order by f.seq desc), '[]'::jsonb),
         min(f.seq), (select count(*) from pag) > v_lim
    into v_rows, v_min, v_mas from fila f;
  return jsonb_build_object('reportes', v_rows, 'total', v_total, 'siguiente', case when v_mas then v_min end, 'distancia_duplicados_m', v_eps);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_obtener_reporte(p_solicitante text, p_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v campo.v_reportes_estado%rowtype; v_eps numeric := campo.f_param('distancia_duplicados_m');
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select * into v from campo.v_reportes_estado where id = p_id;
  if not found then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  -- Paso C: consultar el detalle (muestra autor y contrato) queda auditado
  perform campo.f_auditar(v_email, 'campo_ver_detalle', p_id::text, '{}'::jsonb, p_ip);
  return (
    select jsonb_build_object(
      'reporte', jsonb_build_object(
        'id', v.id, 'seq', v.seq,
        'tipo', jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre), 'grupo', jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre),
        'subtipo', case when s.id is null then null else jsonb_build_object('codigo', s.codigo, 'nombre', s.nombre) end,
        'descripcion', v.descripcion, 'contrato', v.contrato, 'contrato_verificado', v.contrato_verificado, 'lat', v.lat, 'lon', v.lon,
        'precision_m', v.precision_m, 'riesgo_inmediato', v.riesgo_inmediato, 'origen', v.origen, 'fuera_de_zona', v.fuera_de_zona,
        'autor', v.autor, 'registrado_en', v.registrado_en, 'estado', v.estado, 'estado_desde', v.estado_desde, 'oculto', v.oculto,
        'reporte_original_id', v.reporte_original_id)
        -- Paso D
        || jsonb_build_object(
        'consecutivo', v.consecutivo, 'resultado', v.resultado,
        'causal', (select jsonb_build_object('codigo', ca.codigo, 'nombre', ca.nombre) from campo.causales ca where ca.id = v.causal_id),
        'orden_trabajo_id', v.orden_trabajo_id, 'datos', coalesce(v.datos, '{}'::jsonb), 'tiene_datos_sensibles', v.tiene_datos_sensibles,
        'inicio_en', v.inicio_en, 'inicio_origen', v.inicio_origen),
      'campos', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'tipo_dato', c.tipo_dato, 'unidad', c.unidad,
                                  'opciones', (select jsonb_agg(jsonb_build_object('codigo', o ->> 'codigo', 'nombre', o ->> 'nombre')) from jsonb_array_elements(c.opciones) o),
                                  'sensible', c.sensible, 'activo', c.activo)) order by c.orden, c.id)
                           from campo.tipo_campos c where c.tipo_id = v.tipo_id), '[]'::jsonb),
      'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', f.orden, 'tamano_bytes', f.tamano_bytes, 'tipo_mime', f.tipo_mime, 'registrada_en', f.registrada_en,
                                  'etiqueta', f.etiqueta,
                                  'etiqueta_nombre', case when f.etiqueta = 'adicional' then 'Adicional'
                                                          else (select tf.nombre from campo.tipo_fotos tf where tf.tipo_id = v.tipo_id and tf.codigo = f.etiqueta) end) order by f.orden)
                           from campo.reporte_fotos f where f.reporte_id = v.id), '[]'::jsonb),
      'eventos', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'tipo_evento', e.tipo_evento, 'estado_nuevo', e.estado_nuevo,
                                  'reporte_original_id', e.reporte_original_id, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en) order by e.id)
                           from campo.reporte_eventos e where e.reporte_id = v.id), '[]'::jsonb),
      'cercanos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'distancia_m', c.d, 'registrado_en', c.registrado_en, 'estado', c.estado) order by c.d)
                              from (select o.id, round(st_distance(o.geom::geography, v.geom::geography)::numeric, 1) as d, o.registrado_en, o.estado
                                      from campo.v_reportes_estado o
                                     where o.id <> v.id and o.tipo_id = v.tipo_id and not o.oculto and st_dwithin(o.geom::geography, v.geom::geography, v_eps::double precision)
                                     order by st_distance(o.geom::geography, v.geom::geography) limit 20) c), '[]'::jsonb),
      'distancia_duplicados_m', v_eps)
    from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id left join campo.subtipos_reporte s on s.id = v.subtipo_id
   where t.id = v.tipo_id);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_descarga_pagina(p_solicitante text, p_descarga_id bigint, p_despues_de bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; a record; v_f jsonb; v_corte bigint; v_autor boolean; v_lim integer := least(greatest(coalesce(p_limite, 5000), 1), 5000); v_eps numeric := campo.f_param('distancia_duplicados_m');
        v_ids uuid[]; v_rows jsonb; v_min bigint; v_mas boolean;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select x.id, x.email, x.detalle into a from public.geoportal_auditoria x where x.id = p_descarga_id and x.accion = 'campo_descarga_iniciar';
  if not found or a.email <> v_email then perform campo.f_error('La descarga no existe', 'P0002'); end if;
  if exists (select 1 from public.geoportal_auditoria x where x.accion = 'campo_descarga_cerrar' and x.referencia = p_descarga_id::text) then perform campo.f_error('La descarga ya se cerró', '55000'); end if;
  v_f := a.detalle -> 'filtros'; v_corte := (a.detalle ->> 'hasta_seq')::bigint; v_autor := coalesce((a.detalle ->> 'incluir_autor')::boolean, false);
  select coalesce(array_agg(x.id), '{}'::uuid[]) into v_ids from campo.f_filtrar(v_f) x where x.seq <= v_corte;
  with pag as (
    select x.*, row_number() over (order by x.seq desc) as rn from campo.f_filtrar(v_f) x where x.seq <= v_corte and (p_despues_de is null or x.seq < p_despues_de) order by x.seq desc limit v_lim + 1
  ), cl as (select * from campo.f_grupos_cercanos(v_eps, v_ids)),
  fila as (
    select p.*, t.codigo as tipo_codigo, t.nombre as tipo_nombre, g.nombre as grupo_nombre, s.nombre as sub_nombre, es.nombre as estado_nombre, ca.nombre as causal_nombre,
           cl.grupo_id as grupo_dup, cl.tamano as tam_dup
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join campo.estados_reporte es on es.codigo = p.estado left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
     where p.rn <= v_lim
  )
  select coalesce(jsonb_agg(
           jsonb_build_object('seq', f.seq, 'id', f.id, 'registrado_local', to_char(f.registrado_en at time zone 'America/Bogota', 'YYYY-MM-DD"T"HH24:MI:SS'),
             'tipo_codigo', f.tipo_codigo, 'tipo_nombre', f.tipo_nombre, 'grupo_nombre', f.grupo_nombre, 'subtipo_nombre', f.sub_nombre,
             'consecutivo', f.consecutivo, 'resultado', f.resultado, 'causal_nombre', f.causal_nombre,
             'estado', f.estado, 'estado_nombre', f.estado_nombre, 'oculto', f.oculto, 'riesgo_inmediato', f.riesgo_inmediato, 'fuera_de_zona', f.fuera_de_zona,
             'contrato', f.contrato, 'contrato_verificado', f.contrato_verificado, 'descripcion', f.descripcion,
             'lat', f.lat, 'lon', f.lon, 'precision_m', f.precision_m, 'origen', f.origen, 'n_fotos', f.n_fotos,
             'grupo_duplicados', f.grupo_dup, 'tamano_grupo', f.tam_dup, 'reporte_original_id', f.reporte_original_id,
             'orden_trabajo_id', f.orden_trabajo_id, 'datos', coalesce(f.datos, '{}'::jsonb),
             'inicio_local', to_char(f.inicio_en at time zone 'America/Bogota', 'YYYY-MM-DD"T"HH24:MI:SS'), 'inicio_origen', f.inicio_origen,
             'duracion_min', round(extract(epoch from (f.registrado_en - f.inicio_en)) / 60.0, 1))
           || case when v_autor then jsonb_build_object('autor', f.autor) else '{}'::jsonb end order by f.seq desc), '[]'::jsonb),
         min(f.seq), (select count(*) from pag) > v_lim
    into v_rows, v_min, v_mas from fila f;
  return jsonb_build_object('registros', v_rows, 'devueltos', jsonb_array_length(v_rows), 'ultimo_seq', v_min, 'hay_mas', v_mas);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_pdf_datos(p_solicitante text, p_esquema text, p_registro_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'acta', 'pg_temp'
AS $function$
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
  -- Firmas: las de este registro («esta»). En una corrección del acta (versión 2 en adelante) va la del operario que corrige más las tres del acta original («original»).
  select coalesce(jsonb_agg(jsonb_build_object('rol', x.rol, 'estado', x.estado, 'nombre', x.nombre, 'imagen', encode(x.imagen, 'base64'), 'huella', x.huella, 'de', x.de)
                            order by x.o1, array_position(array['operario', 'usuario', 'testigo'], x.rol)), '[]'::jsonb)
    into v_firmas
    from (select f.*, 'esta'::text as de, case when v_ver > 1 then 2 else 1 end as o1
            from campo.firmas f where f.esquema = p_esquema and f.registro_id = p_registro_id and f.estado <> 'quitada' and (v_ver = 1 or f.rol = 'operario')
          union all
          select f.*, 'original'::text, 1 from campo.firmas f
           where v_ver > 1 and f.esquema = 'acta' and f.estado <> 'quitada'
             and f.registro_id = (select o.id from acta.actas o where o.acta_raiz_id = v_a.acta_raiz_id and o.version = 1)) x;
  select coalesce(nullif(btrim(lb.nombre), ''), split_part(coalesce(v_r.autor, v_a.autor), '@', 1)) into v_op from public.geoportal_lista_blanca lb where lb.email = coalesce(v_r.autor, v_a.autor);
  if p_esquema = 'campo' then
    select d.datos into v_sen from campo.reporte_datos_sensibles d where d.reporte_id = v_r.id;
    v_cab := jsonb_build_array(jsonb_build_array('Formato', v_t.nombre), jsonb_build_array('Consecutivo', v_r.consecutivo), jsonb_build_array('Contrato', coalesce(v_r.contrato, '—')),
               jsonb_build_array('Resultado', case v_r.resultado when 'efectivo' then 'Efectivo (se realizó la actividad)' when 'inefectivo' then 'No efectivo (no se realizó)' else coalesce(v_r.resultado, '—') end
                 || coalesce(' · Causal: ' || (select c.nombre from campo.causales c where c.id = v_r.causal_id), '')), jsonb_build_array('Ubicación', v_r.lat || ', ' || v_r.lon || coalesce(' (precisión ' || v_r.precision_m || ' m)', '')));
    with c as (
      select c.seccion, c.orden, c.nombre, c.tipo_dato, c.opciones, coalesce(v_r.datos -> c.codigo, v_sen -> c.codigo) as v
        from campo.tipo_campos c where c.tipo_id = v_t.id and (v_r.datos ? c.codigo or coalesce(v_sen, '{}'::jsonb) ? c.codigo)
    ), f as (
      select c.seccion, c.orden, jsonb_build_array(c.nombre,
               case c.tipo_dato when 'si_no' then case when c.v = 'true'::jsonb then 'Sí' when c.v = 'false'::jsonb then 'No' else c.v #>> '{}' end
                                when 'opcion' then coalesce((select o ->> 'nombre' from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = c.v #>> '{}'), c.v #>> '{}')
                                when 'opciones' then (select string_agg(coalesce((select o ->> 'nombre' from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = x), x), '; ')
                                                        from jsonb_array_elements_text(case when jsonb_typeof(c.v) = 'array' then c.v else '[]'::jsonb end) x)
                                when 'dia_hora' then replace(c.v #>> '{}', 'T', ' ')
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
    v_sello := encode(sha256(convert_to(coalesce((select s.sello_sha256 from acta.acta_sellos s where s.acta_id = v_a.id), '') || coalesce((select string_agg(x ->> 'huella', ',' order by x ->> 'de', x ->> 'rol')
                 from jsonb_array_elements(v_firmas) x where x ->> 'estado' = 'firmo'), ''), 'UTF8')), 'hex');
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
end $function$;

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

-- DROP (por qué y alcance): las 5 funciones las creó este paquete; con la lista de derivadas ya devuelta a su texto publicado, nadie las usa. Alcance: SOLO esas 5 firmas;
-- no toca tablas, datos ni otras funciones.
drop function public.geoportal_campo_derivadas_descarga_cerrar(text, bigint, integer, text, text);
drop function public.geoportal_campo_derivadas_descarga_pagina(text, bigint, bigint, integer);
drop function public.geoportal_campo_derivadas_descarga_iniciar(text, jsonb, text, boolean, text);
drop function campo.f_derivada_descarga(jsonb, boolean);
drop function campo.f_derivadas_filtradas(jsonb);

commit;
