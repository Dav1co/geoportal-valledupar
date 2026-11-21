-- =====================================================================
-- TÉCNICA · FASE 1 · EVENTOS: ORIGEN Y TUBOS · 90 — REVERSA (PROPUESTA). Generada por pruebas_locales/generar.py.
-- Deja las {{N_REEMPLAZADAS}} funciones con su texto de antes, quita las nuevas y las 6 tablas, y VUELVE A ACTIVAR los sectores por planta que la migración desactivó
-- (los del último hecho de cada planta antes de la migración), con un hecho nuevo y su motivo.
-- SE NIEGA si alguna función cambió después de la migración, o si ya hay hechos nuevos: eventos con causal o por tubo, sectores asignados a un tubo o
-- causales ajustadas (la reversa no borra hechos: avise). Antes, devuelva la Edge a la anterior.
-- =====================================================================
do $$
begin
  if to_regclass('redes.evento_causales') is null then raise exception 'No hay nada que revertir: el corte de eventos (origen y tubos) no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_DESPUES}}'
     or (select count(*) from (values {{REEMPLAZADAS_DESPUES}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> {{N_REEMPLAZADAS}} then
    raise exception 'Las funciones cambiaron después de la migración: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.evento_causal) or exists (select 1 from redes.evento_tubos) or exists (select 1 from redes.tubo_sector_eventos) or exists (select 1 from redes.evento_causal_eventos) then
    raise exception 'Ya hay hechos nuevos (eventos con causal o por tubo, sectores de un tubo o causales ajustadas): la reversa no los borra. Avise';
  end if;
end $$;
-- 1. las funciones reemplazadas, con su texto de antes
{{ORIGINALES}}
-- 2. los sectores por planta vuelven a estar activos: los del último hecho de cada planta antes de la migración (con un hecho nuevo y su motivo)
with mig as (select planta_id, min(id) as id from redes.planta_sector_eventos where motivo = 'el sistema es único; los sectores pasan a los tubos de salida' group by planta_id),
     antes as (select distinct on (e.planta_id) e.planta_id, e.sectores from redes.planta_sector_eventos e join mig on mig.planta_id = e.planta_id and e.id < mig.id order by e.planta_id, e.id desc),
     act as (update redes.planta_sectores ps set activo = true from antes a where ps.planta_id = a.planta_id and ps.sector_id = any (a.sectores) and not ps.activo returning ps.planta_id)
insert into redes.planta_sector_eventos (planta_id, sectores, motivo, autor)
select a.planta_id, a.sectores, 'reversa del corte de eventos: vuelven los sectores por planta', 'reversa@redes_eventos_origen_tubos' from antes a;
-- 3. lo nuevo (las tablas de hechos están vacías: lo comprobó la guardia)
{{DROPS}}
drop table redes.evento_tubos;
drop table redes.evento_causal;
drop table redes.evento_causal_eventos;
drop table redes.evento_causales;
drop table redes.tubo_sector_eventos;
drop table redes.tubo_sectores;
drop function redes.f_tubo_es_distribucion();
notify pgrst, 'reload schema';
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_eventos_origen_tubos', 'reversa_redes_eventos_origen_tubos', null, jsonb_build_object('motivo', 'reversa del corte de eventos (origen y tubos)'), null);
