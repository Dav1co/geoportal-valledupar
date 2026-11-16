begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja el esquema redes como lo dejó el Corte 3a: devuelve activo_buscar y v_epicrisis a su texto del 3a y quita las 5 RPC, las vistas, las tablas y las
-- funciones del 3b. El parámetro nuevo se conserva (redes.parametros no deja borrar filas).
-- SE NIEGA si hay ediciones de la ficha, preparaciones o fotos de perfil, u objetos en activos/ del bucket (nada se borra), o si alguna función cambió.
-- =====================================================================
do $$
begin
  if to_regclass('redes.ficha_ediciones') is null then raise exception 'No hay nada que revertir: no existe redes.ficha_ediciones'; end if;
  if exists (select 1 from redes.ficha_ediciones) or exists (select 1 from redes.foto_perfil_preparaciones)
     or exists (select 1 from storage.objects where bucket_id = 'redes-evidencias' and name like 'activos/%') then
    raise exception 'Ya hay ediciones de la ficha o fotos de perfil: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '45971067176a3d30286b6227f0447c0d' then
    raise exception 'Las funciones de redes cambiaron después de la migración del Corte 3b: la reversa se niega a pisarlas; avise';
  end if;
end $$;

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
            WHEN v.version = 1 AND (EXISTS ( SELECT 1
               FROM redes.activos x
              WHERE x.id = v.activo_id AND x.origen_alta = 'intervencion'::text)) THEN COALESCE((' (inversión '::text || (( SELECT i.codigo
               FROM redes.intervenciones i
              WHERE i.activo_id = v.activo_id AND i.activo_creado
             LIMIT 1))) || ')'::text, ' (intervención)'::text)
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
    ((((((((d.codigo || ' · '::text) || d.tipo_nombre) || COALESCE(' · '::text || (( SELECT r.nombre
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
        END) ||
        CASE
            WHEN NOT (EXISTS ( SELECT 1
               FROM redes.dano_fotos f
              WHERE f.dano_id = d.id)) THEN ' · sin evidencia fotográfica'::text
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
  WHERE d.activo_id IS NOT NULL AND d.estado <> 'oculto'::text
UNION ALL
 SELECT i.activo_id,
    i.t_fin AS cuando,
    'intervencion'::text AS clase,
    SUBSTRING(i.codigo FROM 5)::bigint AS ref_id,
    (((((((((((i.codigo || ' · '::text) || i.tipo_nombre) ||
        CASE i.inversion_modo
            WHEN 'nuevo'::text THEN ' (activo nuevo)'::text
            WHEN 'mejora'::text THEN ' (mejora)'::text
            ELSE ''::text
        END) ||
        CASE
            WHEN i.dano_codigo IS NOT NULL THEN (' · atiende '::text || i.dano_codigo) ||
            CASE
                WHEN i.resuelve_dano THEN ' (lo resuelve)'::text
                ELSE ' (sigue abierto)'::text
            END
            ELSE ' · programada o mejora'::text
        END) ||
        CASE i.ejecutor
            WHEN 'emdupar'::text THEN ' · EMDUPAR'::text
            ELSE ' · contratista'::text || COALESCE(' '::text || i.contratista, ''::text)
        END) || ' · duración '::text) || (i.duracion_s / 3600)) || ' h '::text) || lpad((i.duracion_s % 3600::bigint / 60)::text, 2, '0'::text)) || ' min'::text) ||
        CASE
            WHEN i.tambien > 0 THEN (' · '::text || i.tambien) || ' activo(s) más'::text
            ELSE ''::text
        END) ||
        CASE
            WHEN i.sin_evidencia THEN ' · sin evidencia fotográfica'::text
            ELSE (' · '::text || i.fotos) || ' foto(s)'::text
        END AS resumen,
        CASE i.estado
            WHEN 'cerrada'::text THEN 'Cerrada'::text
            WHEN 'anulada'::text THEN 'Anulada'::text
            WHEN 'programada'::text THEN 'Programada'::text
            WHEN 'en_ejecucion'::text THEN 'En ejecución'::text
            ELSE 'Oculta'::text
        END AS estado,
    i.autor
   FROM redes.v_intervencion i
  WHERE i.activo_id IS NOT NULL AND i.estado <> 'oculta'::text
UNION ALL
 SELECT x.activo_id,
    i.t_fin AS cuando,
    'intervencion'::text AS clase,
    SUBSTRING(i.codigo FROM 5)::bigint AS ref_id,
    (((i.codigo || ' · '::text) || i.tipo_nombre) || ' · también intervenido'::text) || COALESCE((' (principal '::text || i.activo_codigo) || ')'::text, ''::text) AS resumen,
        CASE i.estado
            WHEN 'cerrada'::text THEN 'Cerrada'::text
            WHEN 'anulada'::text THEN 'Anulada'::text
            WHEN 'programada'::text THEN 'Programada'::text
            WHEN 'en_ejecucion'::text THEN 'En ejecución'::text
            ELSE 'Oculta'::text
        END AS estado,
    i.autor
   FROM redes.intervencion_activos x
     JOIN redes.v_intervencion i ON i.id = x.intervencion_id
  WHERE i.estado <> 'oculta'::text AND x.activo_id IS DISTINCT FROM i.activo_id;

CREATE OR REPLACE FUNCTION public.geoportal_redes_activo_buscar(p_solicitante text, p_texto text, p_sistema text DEFAULT NULL::text, p_limite integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare p record; v text := btrim(coalesce(p_texto, '')); v_lim integer := coalesce(p_limite, 10);
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if length(v) < 2 or length(v) > 60 then perform tecnica.f_error('Escriba de 2 a 60 caracteres'); end if;
  if p_sistema is not null and p_sistema not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Ese sistema no existe'); end if;
  if v_lim < 1 or v_lim > 10 then perform tecnica.f_error('Se piden de 1 a 10 activos'); end if;
  return jsonb_build_object('activos', coalesce((
    select jsonb_agg(redes.f_activo_corto(x.activo_id) || jsonb_build_object('sistema', x.sistema, 'lat', x.lat, 'lon', x.lon) order by x.rango, x.codigo)
      from (select m.activo_id, m.codigo, m.sistema,
                   round(ST_Y(case when GeometryType(m.geom) = 'POINT' then m.geom else ST_PointOnSurface(m.geom) end)::numeric, 6) as lat,
                   round(ST_X(case when GeometryType(m.geom) = 'POINT' then m.geom else ST_PointOnSurface(m.geom) end)::numeric, 6) as lon,
                   case when m.codigo = upper(v) or lower(m.codigo_anterior) = lower(v) then 0 else 1 end as rango
              from redes.activo_vigente_mat m
             where not m.retirado and not m.oculto and (p_sistema is null or m.sistema = p_sistema)
               and (m.codigo like upper(v) || '%' or lower(m.codigo_anterior) like lower(v) || '%')
             order by rango, m.codigo limit v_lim) x), '[]'::jsonb));
end $function$;

drop function public.geoportal_redes_perfil(text, text);
drop function public.geoportal_redes_galeria(text, text, integer);
drop function public.geoportal_redes_ficha_editar(text, text, jsonb, text);
drop function public.geoportal_redes_foto_perfil_preparar(text, text);
drop function public.geoportal_redes_foto_perfil_fijar(text, text, text, text);
drop function redes.f_foto_principal(bigint);
drop function redes.f_texto_valor(text, text, text);
drop function redes.f_editor_ficha(text);
drop function redes.f_fotos_activo(bigint);
drop view redes.v_activo_identificadores;
drop table redes.activo_fotos_perfil, redes.foto_perfil_preparaciones, redes.activo_identificador_eventos, redes.ficha_ediciones;

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'b1511119a1014345b4287dc7a45cfcfc'
     or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> '4769d9dc85bdb6b6cc81364b3ab7dec7' then
    raise exception 'La reversa no dejó redes como en el Corte 3a';
  end if;
end $$;
commit;
