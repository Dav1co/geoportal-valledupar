-- =====================================================================
-- TÉCNICA · FASE 1 · «MIS REPORTES» (levantar_mios) · 90 — REVERSA (PROPUESTA). Quita la RPC de lectura y el índice.
-- SE NIEGA si alguna función cambió después de la migración. No hay datos que cuidar: el paquete no guarda nada (los puntos por levantar no se tocan).
-- Antes de la reversa, devuelva la Edge a la anterior (el frontend puede quedarse: sin la ruta, «Mis reportes» no aparece).
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_levantar_mios(text,integer)') is null then raise exception 'No hay nada que revertir: «Mis reportes» no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '314112df87e4d649945fd3f611857025' then
    raise exception 'Las funciones cambiaron después de la migración: la reversa se niega a pisarlas; avise';
  end if;
end $$;
drop function public.geoportal_redes_levantar_mios(text,integer);
drop index redes.ix_levantar_puntos_autor;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_levantar_mios', 'reversa_redes_levantar_mios', null, jsonb_build_object('motivo', 'reversa de «Mis reportes» (levantar_mios)'), null);
