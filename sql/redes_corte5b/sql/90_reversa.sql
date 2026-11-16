-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como las dejó el 5a (redes.f_candidatos_muestreo con su texto exacto), sin las 4 RPC nuevas, sin la vista y sin las 2 tablas nuevas.
-- Los 2 parámetros nuevos se quedan (no se borran; nadie los lee).
-- SE NIEGA si ya hay ubicaciones propuestas (nada se borra), o si alguna función cambió después de la migración.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.punto_ubicacion_propuestas') is null then raise exception 'No hay nada que revertir: no existe tecnica.punto_ubicacion_propuestas'; end if;
  if exists (select 1 from tecnica.punto_ubicacion_propuestas) then
    raise exception 'Ya hay ubicaciones propuestas desde Muestreo: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'cbff4ee6e25826251d90496c833ac3de'
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_tec_punto_ubicacion_proponer', '8bedf27e311eef237a304dbbee455151'), ('geoportal_tec_punto_ubicacion_revisar', '450f01d67ca644905a223c1e99ca062a'), ('geoportal_tec_punto_ubicaciones', '22930b502a1d1ee412f5288a3bb3c27e'), ('geoportal_tec_puntos_mapa', 'a04bc885a773086d1199d92ea0dc5ef5'))) <> 4 then
    raise exception 'Las funciones cambiaron después de la migración del Corte 5b: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. la función reemplazada, con su texto del 5a
CREATE OR REPLACE FUNCTION redes.f_candidatos_muestreo(p_carga bigint)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'tecnica', 'public', 'extensions', 'pg_temp'
AS $function$
begin
  if to_regclass('pg_temp._mue') is not null then drop table pg_temp._mue; end if;
  create temp table _mue on commit drop as
  select cf.orden, upper(nullif(btrim(cf.llave), '')) as codigo, nullif(btrim(cf.atributos ->> 'nombre'), '') as nombre,
         lower(nullif(btrim(cf.atributos ->> 'zona'), '')) as zona, nullif(btrim(cf.atributos ->> 'barrio'), '') as barrio,
         lower(coalesce(nullif(btrim(cf.atributos ->> 'exactitud'), ''), nullif(btrim(cf.atributos ->> 'precision'), ''), 'aproximada')) as exactitud,
         lower(coalesce(nullif(btrim(cf.atributos ->> 'fuente'), ''), 'carga')) as fuente,
         case when cf.geom is not null and ST_GeometryType(cf.geom) = 'ST_Point' then round(ST_Y(cf.geom)::numeric, 6) end as lat,
         case when cf.geom is not null and ST_GeometryType(cf.geom) = 'ST_Point' then round(ST_X(cf.geom)::numeric, 6) end as lon,
         coalesce(cf.error, case when ST_GeometryType(cf.geom) <> 'ST_Point' then 'No es un punto' end) as error,
         p.id as punto_id, p.tipo as tipo_vigente, p.activo as activo_vigente, p.nombre as nombre_vigente,
         u.lat as lat_vigente, u.lon as lon_vigente, u.exactitud as exactitud_vigente, null::text as accion, null::text as codigo_nuevo
    from redes.carga_filas cf
    left join tecnica.puntos p on p.codigo = upper(nullif(btrim(cf.llave), ''))
    left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
   where cf.carga_id = p_carga;
  update _mue set accion = case when codigo is null then 'nuevo_sin_codigo'
                                when punto_id is null then 'nuevo'
                                when not activo_vigente then 'reactivar'
                                when lat_vigente is distinct from lat or lon_vigente is distinct from lon or exactitud_vigente is distinct from exactitud then 'ubicacion'
                                else 'igual' end;
end $function$;

revoke all on function redes.f_candidatos_muestreo(bigint) from public, anon, authenticated, service_role;
-- 2. lo nuevo
drop function geoportal_tec_puntos_mapa(text);
drop function geoportal_tec_punto_ubicacion_proponer(text,text,numeric,numeric,numeric,text);
drop function geoportal_tec_punto_ubicaciones(text);
drop function geoportal_tec_punto_ubicacion_revisar(text,bigint,text,text,text);
drop view tecnica.v_punto_propuestas;
drop table tecnica.punto_ubicacion_revisiones;
drop table tecnica.punto_ubicacion_propuestas;

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '5d104bb916ca0b055659c1b14902f519' then
    raise exception 'La reversa no dejó la base como en el 5a';
  end if;
end $$;
