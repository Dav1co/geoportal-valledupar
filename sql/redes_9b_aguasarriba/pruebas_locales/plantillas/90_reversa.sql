-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 90 — REVERSA (PROPUESTA). Quita las {{N_NUEVAS}} funciones y deja los 2 parámetros «sin uso» (no se borran).
-- SE NIEGA si alguna función cambió después de la migración. No hay datos que cuidar: el paquete no guarda nada.
-- =====================================================================
do $$
begin
  if to_regprocedure('redes.f_simular_aguas_arriba(bigint)') is null then raise exception 'No hay nada que revertir: «Cierre por aguas arriba» no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_AU}}' then
    raise exception 'Las funciones cambiaron después de la migración: la reversa se niega a pisarlas; avise';
  end if;
end $$;
{{DROPS}}
update redes.parametros set descripcion = 'Sin uso (reversa de «Cierre por aguas arriba»)' where clave in ('sim_aguas_arriba_criterio', 'sim_cota_minima_m');
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_9b_aguasarriba', 'reversa_redes_9b_aguas_arriba', null, jsonb_build_object('motivo', 'reversa de «Cierre por aguas arriba»'), null);
