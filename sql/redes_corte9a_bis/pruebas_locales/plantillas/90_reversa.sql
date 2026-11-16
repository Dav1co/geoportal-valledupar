-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como estaban con el 9a (texto exacto), quita las 7 nuevas y devuelve el nombre y la nota de la capa de sectores.
-- Lo que NO deshace (son hechos y nada se borra): los nodos clasificados (uno a uno o por grupo) y los daños ya guardados con su sector.
-- El estado «En operación» de los sectores se deshace aparte, con «Volver a la versión anterior» de la capa «sectores» en el Cargue (o carga_sectores/).
-- SE NIEGA si alguna función cambió después de la migración.
-- =====================================================================
do $$
begin
  if to_regprocedure('redes.f_nodo_visible_id(bigint)') is null then raise exception 'No hay nada que revertir: el Corte 9a-bis no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_BIS}}' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 9a-bis: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto del 9a (antes de quitar las nuevas, que ellas usan)
{{TEXTOS_ANTES}}
-- 2. lo nuevo
{{DROPS}}
-- 3. la capa de sectores, como en el 9a
update redes.geovisor_capas set nombre = {{NOMBRE_CAPA_ANTES}}, nota = {{NOTA_CAPA_ANTES}} where codigo = 'sectores';
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte9a_bis', 'reversa_redes_corte9a_bis', null, jsonb_build_object('motivo', 'reversa del Corte 9a-bis'), null);
