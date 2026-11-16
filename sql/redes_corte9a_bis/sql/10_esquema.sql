-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 10 — GUARDIA Y CATÁLOGO
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code B). Generado por pruebas_locales/generar.py.
-- · Presupone el Corte 9a publicado (huella del conjunto de funciones de redes 4a46069fc3c71c305c49bafd764f316e).
-- · Respuestas de David del 16-nov: (1) clasifican nodos el supervisor de distribución y el administrador; (3) confirmar nodos por grupo (solo «no crear activo»),
--   con motivo y vista previa; (4) los 7 sectores del Plan SON los que se operan hoy: el sector calculado es el oficial y el formulario de daño lo propone.
-- · La ficha deja de recorrer tablas enteras (tardaba 4,4 s en producción).
-- · Sin tablas nuevas. Los sectores pasan a «En operación» con una carga nueva por el motor (carga_sectores/), no en esta migración.
-- =====================================================================
do $$
begin
  if to_regprocedure('redes.f_nodo_visible_id(bigint)') is not null then raise exception 'El Corte 9a-bis ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '4a46069fc3c71c305c49bafd764f316e' then
    raise exception 'Las funciones de redes no son las del Corte 9a publicado (huella 4a46069fc3c71c305c49bafd764f316e): deténgase y avise';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'redes' and indexname in ('ix_nodos_llave')) or not exists (select 1 from pg_indexes where schemaname = 'redes' and indexname = 'ix_tn_ini')
     or not exists (select 1 from pg_indexes where schemaname = 'redes' and indexname = 'ix_tn_fin') or not exists (select 1 from pg_indexes where schemaname = 'redes' and indexname = 'ix_nodos_activo') then
    raise exception 'Faltan los índices de nodos y tramo_nodos con que la ficha responde rápido: deténgase y avise';
  end if;
end $$;

-- los sectores del Plan son los de hoy (respuesta 4): cambia la nota de la capa (el estado de los polígonos lo cambia la carga de carga_sectores/)
update redes.geovisor_capas set nombre = 'Sectores hidráulicos',
       nota = '7 sectores y 29 subsectores con que se opera (los del Plan Maestro 2014). El sector de cada activo, daño y contrato sale de su ubicación'
 where codigo = 'sectores';
