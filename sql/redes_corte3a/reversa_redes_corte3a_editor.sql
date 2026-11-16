begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja el esquema redes como lo dejó el Corte 2: devuelve preparar_dano, crear_dano, v_dano y v_epicrisis a su texto del Corte 2 y quita las
-- 8 RPC, las vistas, las tablas y las funciones del 3a. Los 11 parámetros nuevos se conservan (redes.parametros no deja borrar filas).
-- SE NIEGA si hay intervenciones, preparaciones, archivos de intervenciones en el bucket, activos creados por intervenciones o daños asociados
-- desde la bandeja (nada se borra; y sin el 3a, v_dano dejaría de ver el activo asociado), o si alguna función cambió.
-- =====================================================================
do $$
begin
  if to_regclass('redes.intervenciones') is null then raise exception 'No hay nada que revertir: no existe redes.intervenciones'; end if;
  if exists (select 1 from redes.intervenciones) or exists (select 1 from redes.intervencion_preparaciones)
     or exists (select 1 from storage.objects where bucket_id = 'redes-evidencias' and name like 'intervenciones/%')
     or exists (select 1 from redes.activos where origen_alta = 'intervencion') or exists (select 1 from redes.dano_eventos where tipo = 'asociar_activo') then
    raise exception 'Ya hay intervenciones, archivos, activos creados por intervenciones o daños asociados: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'b1511119a1014345b4287dc7a45cfcfc' then
    raise exception 'Las funciones de redes cambiaron después de la migración del Corte 3a: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- la epicrisis y el daño vuelven al texto del Corte 2 (mismas columnas)
create or replace view redes.v_epicrisis as
SELECT v.activo_id,
    v.creado_en AS cuando,
        CASE
            WHEN v.version = 1 THEN 'alta'::text
            ELSE 'version'::text
        END AS clase,
    v.id AS ref_id,
        CASE
            WHEN v.version = 1 THEN 'Alta del activo'::text
            ELSE 'Versión '::text || v.version
        END ||
        CASE
            WHEN v.carga_id IS NOT NULL THEN (' (carga '::text || v.carga_id) || ')'::text
            ELSE ' (ficha)'::text
        END AS resumen,
        CASE
            WHEN v.carga_id IS NOT NULL AND (EXISTS ( SELECT 1
               FROM redes.carga_eventos e
              WHERE e.carga_id = v.carga_id AND e.tipo = 'revertir'::text)) THEN 'revertida'::text
            ELSE 'vigente'::text
        END AS estado,
    v.autor
   FROM redes.activo_versiones v
UNION ALL
 SELECT e.activo_id,
    e.creado_en AS cuando,
    'evento_'::text || e.tipo AS clase,
    e.id AS ref_id,
    e.motivo AS resumen,
    NULL::text AS estado,
    e.autor
   FROM redes.activo_eventos e
UNION ALL
 SELECT c.padre_id AS activo_id,
    c.creado_en AS cuando,
    'componente_'::text || c.accion AS clase,
    c.id AS ref_id,
    (('Componente '::text || h.codigo) || ': '::text) || c.motivo AS resumen,
    NULL::text AS estado,
    c.autor
   FROM redes.activo_componentes c
     JOIN redes.activos h ON h.id = c.hijo_id
UNION ALL
 SELECT c.hijo_id AS activo_id,
    c.creado_en AS cuando,
    'es_componente_'::text || c.accion AS clase,
    c.id AS ref_id,
    (('Parte de '::text || p.codigo) || ': '::text) || c.motivo AS resumen,
    NULL::text AS estado,
    c.autor
   FROM redes.activo_componentes c
     JOIN redes.activos p ON p.id = c.padre_id
UNION ALL
 SELECT d.activo_id,
    d.t_detectado AS cuando,
    d.clase,
    SUBSTRING(d.codigo FROM 5)::bigint AS ref_id,
    (((((((d.codigo || ' · '::text) || d.tipo_nombre) || COALESCE(' · '::text || (( SELECT r.nombre
           FROM redes.tipos_rotura r
          WHERE r.codigo = d.tipo_rotura)), ''::text)) || ' · riesgo '::text) || d.riesgo) ||
        CASE d.causa_clase
            WHEN 'propia'::text THEN ' · causa propia'::text
            WHEN 'terceros'::text THEN ' · causa de terceros'::text
            ELSE ' · causa desconocida'::text
        END) ||
        CASE
            WHEN d.total_corre THEN ''::text
            ELSE (((' · duración '::text || (d.total_s / 3600)) || ' h '::text) || lpad((d.total_s % 3600::bigint / 60)::text, 2, '0'::text)) || ' min'::text
        END) ||
        CASE
            WHEN d.perdida_m3 IS NOT NULL THEN (' · pérdida ≈ '::text || d.perdida_m3) || ' m³'::text
            ELSE ''::text
        END AS resumen,
        CASE d.estado
            WHEN 'reportado'::text THEN 'Reportado'::text
            WHEN 'en_atencion'::text THEN 'En atención'::text
            WHEN 'atendido'::text THEN 'Atendido'::text
            ELSE 'Oculto'::text
        END AS estado,
    d.autor
   FROM redes.v_dano d
  WHERE d.activo_id IS NOT NULL AND d.estado <> 'oculto'::text;
create or replace view redes.v_dano as
WITH b AS (
         SELECT d.id,
            d.codigo,
            d.clase,
            d.tipo_codigo,
            d.sistema,
            d.activo_id,
            d.no_ident_que_es,
            d.lat,
            d.lon,
            d.geom,
            d.ubicacion_origen,
            d.precision_m,
            d.fuera_de_zona,
            d.t_inicio_dano,
            d.t_detectado,
            d.inicio_en,
            d.inicio_origen,
            d.tipo_rotura,
            d.largo_afectado_m,
            d.presion_mca,
            d.usuarios_sin_servicio,
            d.usuarios_propuesta,
            d.sector_texto,
            d.riesgo,
            d.marcas,
            d.causa_clase,
            d.causa_codigo,
            d.tercero_tipo,
            d.descripcion,
            d.origen,
            d.reporte_externo_id,
            d.autor,
            d.registrado_en,
            tm.t_inicio_reparacion,
            tm.t_restablecido,
            ( SELECT e.tipo = 'ocultar'::text
                   FROM redes.dano_eventos e
                  WHERE e.dano_id = d.id AND (e.tipo = ANY (ARRAY['ocultar'::text, 'reincluir'::text]))
                  ORDER BY e.id DESC
                 LIMIT 1) AS ev_oculto,
            ( SELECT e.tipo
                   FROM redes.dano_eventos e
                  WHERE e.dano_id = d.id AND (e.tipo = ANY (ARRAY['atendido'::text, 'reabrir'::text, 'en_atencion'::text]))
                  ORDER BY e.id DESC
                 LIMIT 1) AS ev_estado,
            ( SELECT a.codigo
                   FROM redes.activos a
                  WHERE a.id = d.activo_id) AS activo_codigo,
            ( SELECT v.diametro_mm
                   FROM redes.activo_vigente_mat v
                  WHERE v.activo_id = d.activo_id) AS diametro_mm
           FROM redes.danos d
             JOIN redes.v_dano_tiempos tm ON tm.dano_id = d.id
        ), c AS (
         SELECT b.id,
            b.codigo,
            b.clase,
            b.tipo_codigo,
            b.sistema,
            b.activo_id,
            b.no_ident_que_es,
            b.lat,
            b.lon,
            b.geom,
            b.ubicacion_origen,
            b.precision_m,
            b.fuera_de_zona,
            b.t_inicio_dano,
            b.t_detectado,
            b.inicio_en,
            b.inicio_origen,
            b.tipo_rotura,
            b.largo_afectado_m,
            b.presion_mca,
            b.usuarios_sin_servicio,
            b.usuarios_propuesta,
            b.sector_texto,
            b.riesgo,
            b.marcas,
            b.causa_clase,
            b.causa_codigo,
            b.tercero_tipo,
            b.descripcion,
            b.origen,
            b.reporte_externo_id,
            b.autor,
            b.registrado_en,
            b.t_inicio_reparacion,
            b.t_restablecido,
            b.ev_oculto,
            b.ev_estado,
            b.activo_codigo,
            b.diametro_mm,
                CASE
                    WHEN COALESCE(b.ev_oculto, false) THEN 'oculto'::text
                    WHEN b.ev_estado = 'atendido'::text OR b.t_restablecido IS NOT NULL AND b.ev_estado IS DISTINCT FROM 'reabrir'::text THEN 'atendido'::text
                    WHEN b.t_inicio_reparacion IS NOT NULL OR (b.ev_estado = ANY (ARRAY['en_atencion'::text, 'reabrir'::text])) THEN 'en_atencion'::text
                    ELSE 'reportado'::text
                END AS estado,
            EXTRACT(epoch FROM b.t_inicio_reparacion - b.t_detectado)::bigint AS respuesta_s,
            EXTRACT(epoch FROM b.t_restablecido - b.t_inicio_reparacion)::bigint AS reparacion_s,
            EXTRACT(epoch FROM COALESCE(b.t_restablecido, clock_timestamp()) - COALESCE(b.t_inicio_dano, b.t_detectado))::bigint AS total_s,
            b.t_restablecido IS NULL AS total_corre,
            ( SELECT q.caudal_lps
                   FROM redes.caudales_fuga q
                  WHERE q.tipo_rotura = b.tipo_rotura AND b.diametro_mm >= q.diametro_min_mm AND b.diametro_mm <= q.diametro_max_mm AND (b.presion_mca IS NULL AND q.presion_min_mca IS NULL AND q.presion_max_mca IS NULL OR b.presion_mca >= COALESCE(q.presion_min_mca, 0::numeric) AND b.presion_mca <= COALESCE(q.presion_max_mca, 1000::numeric))
                  ORDER BY q.vigente_desde DESC, q.id DESC
                 LIMIT 1) AS caudal_lps
           FROM b
        )
 SELECT id,
    codigo,
    clase,
    tipo_codigo,
    ( SELECT t.nombre
           FROM redes.tipos_dano t
          WHERE t.codigo = c.tipo_codigo) AS tipo_nombre,
    sistema,
    activo_id,
    activo_codigo,
    no_ident_que_es,
    lat,
    lon,
    geom,
    ubicacion_origen,
    precision_m,
    fuera_de_zona,
    t_inicio_dano,
    t_detectado,
    t_inicio_reparacion,
    t_restablecido,
    inicio_en,
    inicio_origen,
    tipo_rotura,
    largo_afectado_m,
    presion_mca,
    usuarios_sin_servicio,
    usuarios_propuesta,
    sector_texto,
    riesgo,
    marcas,
    causa_clase,
    causa_codigo,
    tercero_tipo,
    descripcion,
    origen,
    reporte_externo_id,
    autor,
    registrado_en,
    estado,
    respuesta_s,
    reparacion_s,
    total_s,
    total_corre,
    caudal_lps,
        CASE
            WHEN caudal_lps IS NOT NULL THEN round(caudal_lps * total_s::numeric / 1000.0, 1)
            ELSE NULL::numeric
        END AS perdida_m3,
        CASE
            WHEN caudal_lps IS NOT NULL THEN 'calculada'::text
            WHEN clase = 'falla'::text OR tipo_rotura IS NULL THEN 'no_aplica'::text
            WHEN NOT (EXISTS ( SELECT 1
               FROM redes.caudales_fuga)) THEN 'sin_tabla'::text
            WHEN diametro_mm IS NULL THEN 'sin_diametro'::text
            ELSE 'sin_fila'::text
        END AS perdida_estado
   FROM c;

-- preparar y crear el daño vuelven al texto del Corte 2 (la ACL no cambia con create or replace)
CREATE OR REPLACE FUNCTION public.geoportal_redes_preparar_dano(p_solicitante text, p_fotos integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas'); v_id uuid := gen_random_uuid();
        v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM'); v_max integer := redes.f_param('max_fotos_dano')::integer;
begin
  if p_fotos is null or p_fotos < redes.f_param('min_fotos_dano') or p_fotos > v_max then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', redes.f_param('min_fotos_dano')::integer, v_max));
  end if;
  insert into redes.dano_preparaciones (dano_id, autor, fotos) values (v_id, v_email, p_fotos);
  return jsonb_build_object('dano_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_dano')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', (select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'danos/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n) from generate_series(1, p_fotos) n));
end $function$;
CREATE OR REPLACE FUNCTION public.geoportal_redes_crear_dano(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas'); d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_dano%rowtype; v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text;
  v_t_ini timestamptz; v_t_det timestamptz; v_t_rep timestamptz; v_t_res timestamptz; v_inicio timestamptz;
  v_lat numeric; v_lon numeric; v_fuera boolean; v_fotos jsonb := coalesce(p_datos -> 'fotos', '[]'::jsonb); v_n integer; v_f jsonb; v_ruta text; v_size bigint; v_mime text;
  v_ref jsonb := '[]'::jsonb; v_cons bigint; v_codigo text; v_tipo redes.tipos_dano%rowtype; v_marcas text[]; v_causa text; v_ter text; v_ter_nom text;
  v_desc text := nullif(btrim(coalesce(d ->> 'descripcion', '')), ''); v_max_bytes bigint := redes.f_param('max_bytes_foto_dano')::bigint;
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador del daño: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_dano where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'fuera_de_zona', v_prev.fuera_de_zona, 'repetido', true);
  end if;
  if not exists (select 1 from redes.dano_preparaciones where dano_id = p_id and autor = v_email) then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos del daño no son válidos'); end if;

  -- qué pasó
  select * into v_tipo from redes.tipos_dano where codigo = d ->> 'tipo' and activo;
  if not found then perform tecnica.f_error('Elija qué pasó'); end if;
  if d ->> 'clase' is distinct from v_tipo.clase then perform tecnica.f_error('El tipo elegido no corresponde a daño o falla'); end if;
  if coalesce(d ->> 'sistema', '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;
  if not ((d ->> 'sistema') = any (v_tipo.sistemas)) then perform tecnica.f_error(format('«%s» no aplica a %s', v_tipo.nombre, d ->> 'sistema')); end if;

  -- activo o «no identificado»
  if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado then perform tecnica.f_error('El activo elegido no existe o está retirado: elíjalo de nuevo en el mapa'); end if;
    if v_act.sistema <> d ->> 'sistema' then perform tecnica.f_error('El activo elegido no es de ese sistema'); end if;
    v_activo := v_act.activo_id;
  else
    v_noid := nullif(btrim(coalesce(d ->> 'no_identificado', '')), '');
    if v_noid is null or length(v_noid) < 3 or length(v_noid) > 120 then perform tecnica.f_error('Elija el activo en el mapa o, si no lo identifica, diga qué es (3 a 120 caracteres)'); end if;
  end if;

  -- ubicación: nunca se rechaza por estar fuera de la zona (se marca)
  v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric;
  if v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then perform tecnica.f_error('Falta la ubicación del daño'); end if;
  if coalesce(d ->> 'ubicacion_origen', '') not in ('gps', 'mapa', 'activo') then perform tecnica.f_error('Falta de dónde sale la ubicación'); end if;
  v_fuera := v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max');

  -- tiempos (contra la hora del servidor)
  v_t_ini := redes.f_instante(d ->> 't_inicio_dano', 'inicio del daño');
  v_t_det := redes.f_instante(d ->> 't_detectado', 'detectado');
  v_t_rep := redes.f_instante(d ->> 't_inicio_reparacion', 'inicio de la reparación');
  v_t_res := redes.f_instante(d ->> 't_restablecido', 'servicio restablecido');
  if v_t_det is null then perform tecnica.f_error('Escriba cuándo se detectó'); end if;
  if greatest(v_t_ini, v_t_det, v_t_rep, v_t_res) > v_ahora + interval '2 minutes' then perform tecnica.f_error('Hay una hora en el futuro: revise la hora de su celular'); end if;
  if v_t_det < v_ahora - make_interval(days => redes.f_param('dano_dias_atras_max')::integer) then
    perform tecnica.f_error(format('La detección no puede ser de hace más de %s días', redes.f_param('dano_dias_atras_max')::integer));
  end if;
  if v_t_ini is not null and v_t_ini > v_t_det then perform tecnica.f_error('El inicio del daño no puede ser después de la detección'); end if;
  if v_t_rep is not null and v_t_rep < v_t_det then perform tecnica.f_error('El inicio de la reparación no puede ser antes de la detección'); end if;
  if v_t_res is not null and v_t_rep is null then perform tecnica.f_error('Para el servicio restablecido, escriba también el inicio de la reparación'); end if;
  if v_t_res is not null and v_t_res < v_t_rep then perform tecnica.f_error('El servicio restablecido no puede ser antes del inicio de la reparación'); end if;
  v_inicio := redes.f_instante(d ->> 'inicio_dispositivo', 'apertura del formulario');
  if v_inicio is not null and (v_inicio > v_ahora + interval '2 minutes' or v_inicio < v_ahora - make_interval(hours => tecnica.f_max_horas_inicio())) then
    perform tecnica.f_error(format('Este formulario se abrió hace más de %s horas o la hora de su celular está adelantada. Revise la hora y vuelva a enviar.', tecnica.f_max_horas_inicio()));
  end if;

  -- tamaño, afectación, riesgo y causa
  if d ->> 'tipo_rotura' is not null and not exists (select 1 from redes.tipos_rotura where codigo = d ->> 'tipo_rotura' and activo) then perform tecnica.f_error('El tipo de rotura no existe'); end if;
  if d ->> 'tipo_rotura' is not null and not v_tipo.pide_rotura then perform tecnica.f_error('Este tipo de daño no lleva tipo de rotura'); end if;
  if coalesce(d ->> 'riesgo', '') not in ('bajo', 'medio', 'alto') then perform tecnica.f_error('Elija el riesgo'); end if;
  if d -> 'marcas' is not null and jsonb_typeof(d -> 'marcas') <> 'array' then perform tecnica.f_error('Las marcas de riesgo no son válidas'); end if;
  v_marcas := coalesce(array(select distinct jsonb_array_elements_text(d -> 'marcas')), '{}');
  if exists (select 1 from unnest(v_marcas) m where not exists (select 1 from redes.marcas_riesgo r where r.codigo = m and r.activo)) then perform tecnica.f_error('Una marca de riesgo no existe'); end if;
  if coalesce(d ->> 'causa_clase', '') not in ('propia', 'terceros', 'desconocida') then perform tecnica.f_error('Elija la causa: propia, de terceros o desconocida'); end if;
  if d ->> 'causa_clase' = 'propia' then
    v_causa := d ->> 'causa';
    if not exists (select 1 from redes.causas where codigo = v_causa and activo) then perform tecnica.f_error('Elija la causa propia'); end if;
  elsif d ->> 'causa_clase' = 'terceros' then
    v_ter := d ->> 'tercero_tipo';
    if not exists (select 1 from redes.tipos_tercero where codigo = v_ter and activo) then perform tecnica.f_error('Elija quién lo causó'); end if;
    v_ter_nom := nullif(btrim(coalesce(d ->> 'tercero_nombre', '')), '');
    if v_ter_nom is not null and length(v_ter_nom) not between 2 and 120 then perform tecnica.f_error('El nombre, la empresa o la placa lleva de 2 a 120 caracteres'); end if;
  end if;
  if v_desc is not null and length(v_desc) > 1000 then perform tecnica.f_error('La descripción admite hasta 1.000 caracteres'); end if;

  -- fotos: el tamaño y el tipo se leen de Storage (nunca se le creen al celular)
  if jsonb_typeof(v_fotos) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n < redes.f_param('min_fotos_dano') or v_n > redes.f_param('max_fotos_dano') or v_n > (select fotos from redes.dano_preparaciones where dano_id = p_id) then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', redes.f_param('min_fotos_dano')::integer, redes.f_param('max_fotos_dano')::integer));
  end if;
  if v_n > 0 and (select count(distinct (e ->> 'n')::integer) <> v_n or min((e ->> 'n')::integer) <> 1 or max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_fotos) e) then
    perform tecnica.f_error('El orden de las fotos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  if v_n > 0 and not exists (select 1 from jsonb_array_elements(v_fotos) e where e ->> 'momento' = 'dano') then perform tecnica.f_error('Falta una foto del daño'); end if;
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'n')::integer loop
    if coalesce(v_f ->> 'momento', '') not in ('dano', 'entorno', 'reparado') then perform tecnica.f_error('Cada foto dice si es del daño, del entorno o de la reparación'); end if;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^danos/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || '\.jpg$') then
      perform tecnica.f_error(format('La ruta de la foto %s no corresponde a este daño', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró la foto %s: súbala de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('La foto %s está vacía', v_f ->> 'n')); end if;
    if v_size > v_max_bytes then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'momento', v_f ->> 'momento', 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;

  -- código DAN-000123 (candado de fila del consecutivo) e inserción
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'DAN' returning ultimo into v_cons;
  v_codigo := 'DAN-' || lpad(v_cons::text, 6, '0');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, no_ident_que_es, lat, lon, ubicacion_origen, precision_m, fuera_de_zona,
         t_inicio_dano, t_detectado, inicio_en, inicio_origen, tipo_rotura, largo_afectado_m, presion_mca, usuarios_sin_servicio, sector_texto,
         riesgo, marcas, causa_clase, causa_codigo, tercero_tipo, descripcion, origen, autor, registrado_en)
  values (p_id, v_codigo, v_tipo.clase, v_tipo.codigo, d ->> 'sistema', v_activo, v_noid, round(v_lat, 6), round(v_lon, 6), d ->> 'ubicacion_origen',
          (d ->> 'precision_m')::numeric, v_fuera, v_t_ini, v_t_det, v_inicio, case when v_inicio is not null then 'dispositivo' end,
          d ->> 'tipo_rotura', (d ->> 'largo_afectado_m')::numeric, (d ->> 'presion_mca')::numeric, (d ->> 'usuarios_sin_servicio')::integer,
          nullif(btrim(coalesce(d ->> 'sector', '')), ''), d ->> 'riesgo', v_marcas, d ->> 'causa_clase', v_causa, v_ter, v_desc, 'formulario', v_email, v_ahora);
  if v_ter_nom is not null then insert into redes.dano_datos_sensibles (dano_id, tercero_nombre) values (p_id, v_ter_nom); end if;
  if v_t_rep is not null then insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor) values (p_id, v_t_rep, v_t_res, 'formulario', v_email); end if;
  insert into redes.dano_fotos (dano_id, n, momento, ruta_storage, bytes, mime)
  select p_id, (x ->> 'n')::smallint, x ->> 'momento', x ->> 'ruta', (x ->> 'bytes')::integer, x ->> 'mime' from jsonb_array_elements(v_ref) x;
  -- auditoría sin el nombre del tercero ni la posición
  perform tecnica.f_auditar(v_email, 'redes_crear_dano', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'sistema', d ->> 'sistema', 'activo', v_act.codigo,
          'no_identificado', v_noid is not null, 'fotos', v_n, 'riesgo', d ->> 'riesgo'), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo,
                                    'fuera_de_zona', x.fuera_de_zona, 'respuesta_s', x.respuesta_s, 'reparacion_s', x.reparacion_s, 'total_s', x.total_s,
                                    'perdida_estado', x.perdida_estado, 'repetido', false) from redes.v_dano x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.danos where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_dano x where x.id = p_id);
  end if;
  perform tecnica.f_error('Una de las fotos ya está usada en otro daño');
  return null;
end $function$;

drop function public.geoportal_redes_formulario_intervencion(text);
drop function public.geoportal_redes_danos_abiertos(text, text, text, numeric, numeric);
drop function public.geoportal_redes_preparar_intervencion(text, integer, integer);
drop function public.geoportal_redes_crear_intervencion(text, uuid, jsonb, text);
drop function public.geoportal_redes_intervencion_recursos(text, text, jsonb, text);
drop function public.geoportal_redes_intervenciones(text, text, integer);
drop function public.geoportal_redes_no_identificados(text, integer);
drop function public.geoportal_redes_asociar_activo(text, text, text, text, text);
drop function redes.f_dano_elegible(redes.v_dano, text, bigint[], geometry);
drop function redes.f_fuentes_validas(jsonb, boolean, boolean);
drop function redes.f_activo_crear(text, geometry, text, text, numeric, text, date, jsonb, text, text, text, text);
drop function redes.f_mat_refrescar_uno(bigint);
drop function redes.f_supervisor(text, text);
drop view redes.v_no_identificados;
drop view redes.v_intervencion;
drop view redes.v_intervencion_fuentes;
drop table redes.intervencion_eventos, redes.intervencion_archivos, redes.intervencion_fuentes, redes.intervencion_materiales, redes.intervencion_activos,
           redes.intervenciones, redes.intervencion_preparaciones, redes.unidades_material, redes.tipos_intervencion;
drop function redes.f_intervencion_activo_coherente();
drop function redes.f_intervencion_coherente();

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '06ecefcf2922e724e1be5546b87a5510'
     or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> 'd97fa858302da7febe1cb82270e24185' or md5(pg_get_viewdef('redes.v_dano'::regclass, true)) <> '6c5d9335e3d49eddaf7149a1b8731ef6' then
    raise exception 'La reversa no dejó redes como en el Corte 2';
  end if;
end $$;
commit;
