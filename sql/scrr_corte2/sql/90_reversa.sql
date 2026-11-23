-- =====================================================================
-- SCRR · CORTE 2 · 90 — REVERSA del paquete (deja la base como antes de la migración)
-- Se NIEGA si alguna carga de cartera cambió public.cartera_suscripcion y no se revirtió: al quitar scrr se perdería su respaldo.
-- Primero se revierten esas cargas desde la pantalla (o con public.geoportal_scrr_suscripcion_revertir) y después se corre esta reversa.
--
-- DROP 1 — POR QUÉ: las RPC public.geoportal_scrr_* son nuevas de este corte y no existían antes. ALCANCE EXACTO: solo las funciones de public cuyo
--          nombre empieza por «geoportal_scrr_» (las lista la consulta de abajo; hoy son 11). Ninguna otra función de public.
-- DROP 2 — POR QUÉ: el esquema scrr es nuevo de este corte. ALCANCE EXACTO: el esquema scrr con todo lo suyo (tablas, particiones, vistas, funciones,
--          disparadores y datos del motor: cargas, historial, pagos, actas y respaldos). «cascade» solo alcanza objetos DENTRO de scrr: nada fuera de scrr
--          depende de él (ninguna función ni vista de public, campo, acta o técnica lo usa; las RPC de public se quitan antes en el DROP 1).
-- No toca public.cartera_suscripcion, public.geoportal_auditoria (la auditoría del SCRR se queda como registro) ni las funciones de permisos.
-- =====================================================================
do $reversa$
declare f record;
begin
  if to_regnamespace('scrr') is null then
    raise notice 'REVERSA SCRR: el esquema scrr no existe; no hay nada que revertir.';
    return;
  end if;
  if exists (select 1 from scrr.suscripcion_respaldo where revertido_en is null) then
    raise exception 'REVERSA SCRR: hay cargas de cartera que cambiaron cartera_suscripcion y no se revirtieron (%). Reviértalas primero.',
      (select string_agg(distinct carga_id::text, ', ') from scrr.suscripcion_respaldo where revertido_en is null);
  end if;
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_scrr\_%' loop
    execute format('drop function %s', f.firma);                 -- DROP 1 (ver arriba)
  end loop;
  drop schema scrr cascade;                                       -- DROP 2 (ver arriba)
end $reversa$;
