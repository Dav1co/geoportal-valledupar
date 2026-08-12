-- =====================================================================
-- 21_redes_servicio.sql
-- Capas de redes de acueducto y alcantarillado: SOLO VISUALIZACION.
--
-- Sin atributos, sin ficha, sin busqueda, sin interaccion. El shapefile
-- va a seguir cambiando y por ahora solo interesa verlo dibujado, asi
-- que las tablas son (id, geom) y la tesela solo lleva la geometria.
--
-- Las tablas se crean aparte (ver el cuerpo del cargador
-- ~/geoportal-loader/cargar_redes.py). Este archivo redefine
-- geoportal_mvt_b64 anadiendo los dos bloques.
--
-- ZOOM: z15, el mismo umbral de pred_completo. Se decidio midiendo, no
-- a ojo. A z14 una tesela tipica lleva ~1.925 lineas de acueducto y
-- ~1.571 de alcantarillado, y el peso subia un 12,6 % (563.173 ->
-- 634.386 bytes) sobre las teselas que ya son las mas pesadas del mapa.
-- A z15 las teselas z14 quedan intactas y las z15 crecen solo un 3,8 %
-- (420.379 -> 436.500). Ademas a z14 todavia no se distinguen las
-- calles, que es cuando una red empieza a servir.
--
-- Del entregable de alcantarillado solo entra alc_conductos (9.064
-- lineas). alc_pozos (9.146) y alc_descargas (4) son capas de PUNTOS y
-- quedaron fuera a proposito: no caben en una tabla MultiLineString y
-- necesitan su propio tratamiento.
--
-- OJO: subir TESELA_V en el frontend al cambiar esta funcion, o las
-- teselas cacheadas seguiran sirviendo la version anterior. Se subio de
-- 5 a 6 con este cambio.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.geoportal_mvt_b64(z integer, x integer, y integer)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with bounds as (
    select ST_TileEnvelope(z, x, y) as env_3857,
           ST_Transform(ST_TileEnvelope(z, x, y), 4326) as env_4326
  ),
  -- Zoom lejano: solo lo necesario para dibujar el punto.
  pred_liviano as (
    select ST_AsMVTGeom(ST_Transform(p.geom, 3857), b.env_3857) as geom,
           p.id, p.sin_contrato as clandestino
    from public.predios_comercial p, bounds b
    where z >= 13 and z < 15
      and p.geom && b.env_4326 and ST_Intersects(p.geom, b.env_4326)
  ),
  -- Zoom cercano: todos los atributos para filtrar, colorear y contar.
  pred_completo as (
    select ST_AsMVTGeom(ST_Transform(p.geom, 3857), b.env_3857) as geom,
           p.id, p.cod_usuario, p.sin_contrato as clandestino,
           p.estado_predio as estado, p.estado_medidor, p.determinacion_consumo,
           p.clase_consumo, p.grupo_consumo, (p.dif_consumo)::int as dif_consumo, p.venia_de_cero, p.tramo_mora, p.tiene_deuda,
           p.cruza_acuo, p.barrio, p.ciclo,
           p.deuda_total, p.facturas_pendientes, p.consumo_actual,
           p.semaforo_cartera, p.edad_medidor, p.rango_pago, p.causal_lectura
    from public.predios_comercial p, bounds b
    where z >= 15
      and p.geom && b.env_4326 and ST_Intersects(p.geom, b.env_4326)
  ),
  manz as (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), bm.env_3857) as geom,
           m.id, m.predios
    from public.manzanas_agregadas m, bounds bm
    where z < 13
      and m.geom && bm.env_4326
  ),
  barr as (
    select ST_AsMVTGeom(ST_Transform(b.geom, 3857), bo.env_3857) as geom,
           b.id, b.nombre
    from public.barrios_valledupar b, bounds bo
    where z >= 12
      and b.geom && bo.env_4326
  ),
  terr as (
    select ST_AsMVTGeom(ST_Transform(t.geom, 3857), b.env_3857) as geom,
           t.codigo, t.matricula
    from public.terrenos_valledupar t, bounds b
    where z >= 16
      and t.geom && b.env_4326
  ),
  -- Redes de servicio: SOLO GEOMETRIA. Sin atributos, sin interaccion.
  red_acu as (
    select ST_AsMVTGeom(ST_Transform(r.geom, 3857), b.env_3857) as geom
    from public.redes_acueducto r, bounds b
    where z >= 15
      and r.geom && b.env_4326
  ),
  red_alc as (
    select ST_AsMVTGeom(ST_Transform(r.geom, 3857), b.env_3857) as geom
    from public.redes_alcantarillado r, bounds b
    where z >= 15
      and r.geom && b.env_4326
  )
  select encode(
    coalesce((select ST_AsMVT(terr.*, 'terrenos') from terr), ''::bytea) ||
    coalesce((select ST_AsMVT(red_acu.*, 'red_acueducto') from red_acu), ''::bytea) ||
    coalesce((select ST_AsMVT(red_alc.*, 'red_alcantarillado') from red_alc), ''::bytea) ||
    coalesce((select ST_AsMVT(barr.*, 'barrios') from barr), ''::bytea) ||
    coalesce((select ST_AsMVT(manz.*, 'manzanas') from manz), ''::bytea) ||
    case when z < 15
      then coalesce((select ST_AsMVT(pred_liviano.*, 'predios') from pred_liviano), ''::bytea)
      else coalesce((select ST_AsMVT(pred_completo.*, 'predios') from pred_completo), ''::bytea)
    end,
    'base64');
$function$

;
