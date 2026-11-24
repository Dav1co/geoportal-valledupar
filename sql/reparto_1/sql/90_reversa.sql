-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 90 — REVERSA del paquete (deja la base como antes de la migración)
-- Se NIEGA si ya hay entregas o archivos de ruta registrados: son hechos y no se borran. Con datos, el reparto se desactiva (se quita la Edge o la entrada de la
-- pantalla) y el esquema se queda.
--
-- DROP 1 — POR QUÉ: las RPC public.geoportal_reparto_* son nuevas de este corte y no existían antes. ALCANCE EXACTO: solo las funciones de public cuyo nombre
--          empieza por «geoportal_reparto_» (las lista la consulta de abajo). Ninguna otra función de public.
-- Antes de los DROP se quitan los permisos de homelab_lectura (el Dell) sobre reparto.
-- DROP 2 — POR QUÉ: el esquema reparto es nuevo de este corte. ALCANCE EXACTO: el esquema reparto con lo suyo (tablas, vistas, funciones, disparadores y los
--          parámetros de la semilla). «cascade» solo alcanza objetos DENTRO de reparto: nada fuera de reparto depende de él (las RPC de public se quitan antes).
-- La actividad «supervision_reparto» de campo.actividades NO se borra (el catálogo no se borra): se desactiva (update con where).
-- No toca más de campo, ni bi, hechos, public.cartera_suscripcion, public.geoportal_auditoria (lo auditado se queda) ni las funciones de permisos.
-- =====================================================================
do $reversa$
declare f record;
begin
  if to_regnamespace('reparto') is null then
    raise notice 'REVERSA REPARTO: el esquema reparto no existe; no hay nada que revertir.';
    return;
  end if;
  if exists (select 1 from reparto.entregas) or exists (select 1 from reparto.lotes) or exists (select 1 from reparto.jornadas) then
    raise exception 'REVERSA REPARTO: ya hay jornadas, entregas o archivos de ruta registrados (son hechos y no se borran). Desactive el reparto en vez de revertirlo.';
  end if;
  if exists (select 1 from pg_roles where rolname = 'homelab_lectura') then
    revoke select on reparto.parametros, reparto.lotes, reparto.lote_filas, reparto.lotes_anulados,
                     reparto.jornadas, reparto.jornada_items, reparto.entregas, reparto.entregas_anuladas from homelab_lectura;
    revoke usage on schema reparto from homelab_lectura;
  end if;
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%' loop
    execute format('drop function %s', f.firma);                 -- DROP 1 (ver arriba)
  end loop;
  drop schema reparto cascade;                                    -- DROP 2 (ver arriba)
  update campo.actividades set activa = false where codigo = 'supervision_reparto';
end $reversa$;
