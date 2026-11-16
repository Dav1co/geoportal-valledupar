-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 25 — REEMPLAZO (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- es el texto del 5a con un cambio exacto, aplicado una sola vez:
--   · redes.f_candidatos_muestreo (capa MUE): una ubicación verificada no la pisa un archivo que la trae aproximada («conserva_verificada»).
-- =====================================================================

-- redes.f_candidatos_muestreo(bigint)
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
  -- Corte 5b: una ubicación verificada (David o el GPS del operador aprobado en el Dashboard PTAP) no la pisa un archivo que la trae aproximada:
  -- se conserva la vigente («conserva_verificada» en el resumen). Un archivo con la ubicación verificada sí la cambia (es una corrección explícita).
  update _mue set lat = lat_vigente, lon = lon_vigente, exactitud = 'verificada',
                  accion = case when accion = 'ubicacion' then 'conserva_verificada' else accion end
   where exactitud_vigente = 'verificada' and exactitud = 'aproximada' and lat is not null and error is null;
end $function$;
