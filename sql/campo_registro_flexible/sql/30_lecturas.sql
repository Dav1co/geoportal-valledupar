-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 30 — LECTURAS DE SUPERVISIÓN: lista, detalle, descarga y datos del PDF
-- Agregan lo de campo.reporte_registro (por la llave; sin fila = reporte anterior: todo nulo) y el origen de las fotos:
--   xy_manual, sin_ubicacion_dispositivo, direccion, barrio, referencia, fotos_adjuntadas; el detalle y la descarga, además, la ubicación del dispositivo y la
--   distancia entre las dos posiciones. El PDF (solo esquema campo; el del acta no cambia) agrega la línea «XY digitado — registrado desde otro punto» y el origen
--   de cada foto adjuntada. EL SELLO de un reporte sin fila en reporte_registro es EXACTAMENTE el de antes (se le concatena '' ); con fila, la fila entra al sello.
-- Firmas iguales: create or replace.
-- =====================================================================
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
           ca.codigo as causal_codigo, ca.nombre as causal_nombre,
           rr.reporte_id as rr_id, rr.xy_manual, rr.lat_registro, rr.direccion, rr.barrio, rr.referencia,
           (select count(*) from campo.reporte_fotos fo where fo.reporte_id = p.id and fo.origen <> 'camara')::integer as fotos_adjuntadas
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
      left join campo.reporte_registro rr on rr.reporte_id = p.id
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
           'inicio_en', f.inicio_en, 'inicio_origen', f.inicio_origen)
           -- Registro flexible (25-nov): nulos si el reporte no tiene fila (anterior a este paquete)
           || jsonb_build_object(
           'xy_manual', f.xy_manual, 'sin_ubicacion_dispositivo', case when f.rr_id is not null then f.lat_registro is null end,
           'direccion', f.direccion, 'barrio', f.barrio, 'referencia', f.referencia, 'fotos_adjuntadas', f.fotos_adjuntadas) order by f.seq desc), '[]'::jsonb),
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
        'inicio_en', v.inicio_en, 'inicio_origen', v.inicio_origen)
        -- Registro flexible (25-nov): «registro» nulo si el reporte no tiene fila (anterior a este paquete)
        || jsonb_build_object('registro', (select jsonb_build_object('xy_manual', rr.xy_manual, 'lat_registro', rr.lat_registro, 'lon_registro', rr.lon_registro,
                                                   'precision_registro_m', rr.precision_registro_m, 'sin_ubicacion_dispositivo', rr.lat_registro is null,
                                                   'distancia_m', case when rr.lat_registro is not null then round(st_distance(v.geom::geography,
                                                     st_setsrid(st_makepoint(rr.lon_registro::double precision, rr.lat_registro::double precision), 4326)::geography)::numeric, 1) end,
                                                   'direccion', rr.direccion, 'barrio', rr.barrio, 'referencia', rr.referencia)
                                             from campo.reporte_registro rr where rr.reporte_id = v.id)),
      'campos', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'tipo_dato', c.tipo_dato, 'unidad', c.unidad,
                                  'opciones', (select jsonb_agg(jsonb_build_object('codigo', o ->> 'codigo', 'nombre', o ->> 'nombre')) from jsonb_array_elements(c.opciones) o),
                                  'sensible', c.sensible, 'activo', c.activo)) order by c.orden, c.id)
                           from campo.tipo_campos c where c.tipo_id = v.tipo_id), '[]'::jsonb),
      'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', f.orden, 'tamano_bytes', f.tamano_bytes, 'tipo_mime', f.tipo_mime, 'registrada_en', f.registrada_en,
                                  'etiqueta', f.etiqueta, 'origen', f.origen,
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
           cl.grupo_id as grupo_dup, cl.tamano as tam_dup,
           rr.reporte_id as rr_id, rr.xy_manual, rr.lat_registro, rr.lon_registro, rr.precision_registro_m, rr.direccion, rr.barrio, rr.referencia,
           (select count(*) from campo.reporte_fotos fo where fo.reporte_id = p.id and fo.origen <> 'camara')::integer as fotos_adjuntadas
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join campo.estados_reporte es on es.codigo = p.estado left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
      left join campo.reporte_registro rr on rr.reporte_id = p.id
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
           -- Registro flexible (25-nov): nulos si el reporte no tiene fila (anterior a este paquete)
           || jsonb_build_object('xy_manual', f.xy_manual, 'sin_ubicacion_dispositivo', case when f.rr_id is not null then f.lat_registro is null end,
             'lat_registro', f.lat_registro, 'lon_registro', f.lon_registro, 'precision_registro_m', f.precision_registro_m,
             'distancia_registro_m', case when f.lat_registro is not null then round(st_distance(f.geom::geography,
               st_setsrid(st_makepoint(f.lon_registro::double precision, f.lat_registro::double precision), 4326)::geography)::numeric, 1) end,
             'direccion', f.direccion, 'barrio', f.barrio, 'referencia', f.referencia, 'fotos_adjuntadas', f.fotos_adjuntadas)
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
        v_rr campo.reporte_registro;   -- registro flexible (25-nov)
begin
  v_email := campo.f_autorizar_documento(p_solicitante, p_esquema, p_registro_id);
  if p_esquema = 'campo' then
    select * into v_r from campo.reportes where id = p_registro_id;
    select * into v_rr from campo.reporte_registro where reporte_id = p_registro_id;
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
                 || coalesce(' · Causal: ' || (select c.nombre from campo.causales c where c.id = v_r.causal_id), '')), jsonb_build_array('Ubicación', v_r.lat || ', ' || v_r.lon || coalesce(' (precisión ' || v_r.precision_m || ' m)', '')
                 || case when v_rr.xy_manual then ' · XY digitado — registrado desde otro punto' else '' end));
    -- Registro flexible (25-nov): solo si el reporte tiene fila en reporte_registro (los anteriores quedan exactamente como antes)
    if v_rr.reporte_id is not null then
      v_cab := v_cab || jsonb_build_array(jsonb_build_array('Registrado desde', case when v_rr.lat_registro is null then 'Sin ubicación del dispositivo'
                 else v_rr.lat_registro || ', ' || v_rr.lon_registro || coalesce(' (precisión ' || v_rr.precision_registro_m || ' m)', '') end));
      if v_rr.direccion is not null then v_cab := v_cab || jsonb_build_array(jsonb_build_array('Dirección', v_rr.direccion)); end if;
      if v_rr.barrio is not null then v_cab := v_cab || jsonb_build_array(jsonb_build_array('Barrio', v_rr.barrio)); end if;
      if v_rr.referencia is not null then v_cab := v_cab || jsonb_build_array(jsonb_build_array('Referencia', v_rr.referencia)); end if;
    end if;
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
    select coalesce(jsonb_agg(jsonb_build_object('bucket', 'campo-fotos', 'ruta', p.ruta_storage, 'etiqueta', coalesce(p.etiqueta, 'Foto ' || p.orden)
             || case p.origen when 'galeria' then ' · adjuntada desde la galería' when 'archivo' then ' · adjuntada desde un archivo' else '' end, 'bytes', p.tamano_bytes) order by p.orden), '[]'::jsonb)
      into v_fotos from campo.reporte_fotos p where p.reporte_id = v_r.id;
    v_nombre := campo.f_nombre_pdf(v_r.registrado_en, v_d.sigla, replace(v_r.consecutivo, '-', ''), 1);
    -- Sello: sin fila en reporte_registro se le concatena '' (el sello de un reporte anterior no cambia); con fila, la fila entra al sello
    v_sello := encode(sha256(convert_to(to_jsonb(v_r)::text || coalesce(v_sen::text, '') || case when v_rr.reporte_id is null then '' else to_jsonb(v_rr)::text end || coalesce((select string_agg(f.huella, ',' order by f.rol) from campo.firmas f
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


