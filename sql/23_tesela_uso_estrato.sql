-- =====================================================================
-- 23 — La tesela lleva `categoria` y `subcategoria`
--
-- PENDIENTE DE APROBACIÓN DE DAVID. No ejecutado.
--
-- Por qué: el filtro de Uso y Estrato del modo Comercial es una
-- expresión MapLibre que se evalúa en el navegador sobre los atributos
-- que viajan en la tesela. Hoy `pred_completo` no incluye esas dos
-- columnas, así que ["get","categoria"] devuelve null en todos los
-- predios y el filtro no puede funcionar: el mapa quedaría vacío al
-- elegir cualquier uso.
--
-- Qué cambia: DOS columnas en el bloque pred_completo (zoom >= 15).
-- Nada más. Mismo nombre, misma firma, mismo SECURITY DEFINER, mismos
-- bloques de manzanas, barrios, terrenos y redes. Es CREATE OR REPLACE:
-- no borra ni recrea la función, no toca permisos ni grants, y no toca
-- la vista materializada predios_comercial.
--
-- Costo en peso de tesela, MEDIDO sobre la tesela z15 más densa
-- (9715/15426, 4.761 predios): 372.267 -> 390.430 bytes, +18.163
-- bytes, +4,88 %. Solo desde z15; z13-14 usan pred_liviano y no
-- cambian.
--
-- DESPUÉS DE APLICAR: subir TESELA_V en src/components/MapView.tsx
-- (de 6 a 7) para invalidar la caché de teselas del navegador. Sin eso
-- los clientes seguirán con teselas viejas, sin los campos nuevos.
--
-- Para revertir: volver a ejecutar la definición anterior, que se
-- recupera con pg_get_functiondef sobre geoportal_mvt_b64.
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
           p.categoria, p.subcategoria,
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
$function$;
