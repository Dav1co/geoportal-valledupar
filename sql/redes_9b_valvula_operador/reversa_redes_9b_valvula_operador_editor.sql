begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · CORRECCIÓN «LA VÁLVULA QUE CERRÓ EL OPERADOR» · 90 — REVERSA (PROPUESTA). Quita la RPC de lectura.
-- SE NIEGA si alguna función cambió después de la migración. No hay datos que cuidar: el paquete no guarda nada (las maniobras no se tocan).
-- Antes de la reversa, devuelva la Edge y el frontend a los anteriores (o deje el frontend: sin la ruta, el panel vuelve a leer como antes).
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_cierres_registro(text,text)') is null then raise exception 'No hay nada que revertir: la corrección «la válvula que cerró el operador» no está aplicada'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '63d917635b33e3696f28a3b0e579c002' then
    raise exception 'Las funciones cambiaron después de la migración: la reversa se niega a pisarlas; avise';
  end if;
end $$;
drop function public.geoportal_redes_cierres_registro(text,text);
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_9b_valvula_operador', 'reversa_redes_9b_valvula_operador', null, jsonb_build_object('motivo', 'reversa de la corrección «la válvula que cerró el operador»'), null);
commit;
