begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 · 90 — REVERSA (PROPUESTA). Quita las 4 funciones y las 2 tablas (vacías) y deja la capa «sin uso» (no se borra).
-- SE NIEGA si alguna función cambió después de la migración o si el flujo ya está cargado (la reversa no borra datos: avise).
-- =====================================================================
do $$
begin
  if to_regclass('redes.flujo_modelo') is null then raise exception 'No hay nada que revertir: la Fase 3 del Corte 9b no está aplicada'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'fbcbd7b3da35dfdc0e4104ed4a6e8f2f' then
    raise exception 'Las funciones cambiaron después de la migración de la Fase 3: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.flujo_modelo) or exists (select 1 from redes.ref_cargas where conjunto = 'flujo_modelo') then
    raise exception 'El flujo del modelo ya está cargado: la reversa no borra datos; avise';
  end if;
end $$;
drop function public.geoportal_redes_flujo_tramo(text,text);
drop function public.geoportal_redes_flujo_modelo(text);
drop function public.geoportal_redes_geovisor_mvt_flujo(text,text,integer,integer,integer);
drop function redes.f_flujo_clase(numeric);
drop table redes.flujo_modelo_horas, redes.flujo_modelo;
update redes.geovisor_capas set activa = false, nota = 'Sin uso (reversa del Corte 9b, Fase 3)' where codigo = 'flujo_modelo';
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte9b_f3', 'reversa_redes_corte9b_fase3', null, jsonb_build_object('motivo', 'reversa del Corte 9b (Fase 3)'), null);
commit;
