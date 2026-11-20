-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO · 90 — REVERSA (PROPUESTA). Quita la RPC de lectura y sus 2 internas.
-- SE NIEGA si alguna función cambió después de la migración. No hay datos que cuidar: el paquete no guarda nada (los eventos no se tocan).
-- Antes de la reversa, devuelva la Edge a la anterior (el frontend puede quedarse si trata la ruta que falta como «sin aviso»).
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_evento_contrato(text,text)') is null then raise exception 'No hay nada que revertir: el aviso de evento por contrato no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'b474fbbe3e0f7a3a7e6dbc04c53e02e7' then
    raise exception 'Las funciones cambiaron después de la migración: la reversa se niega a pisarlas; avise';
  end if;
end $$;
drop function public.geoportal_redes_evento_contrato(text,text);
drop function redes.f_evento_contrato_acceso(text);
drop function redes.f_eventos_del_contrato(text);
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_aviso_evento_contrato', 'reversa_redes_aviso_evento_contrato', null, jsonb_build_object('motivo', 'reversa del aviso de evento por contrato'), null);
