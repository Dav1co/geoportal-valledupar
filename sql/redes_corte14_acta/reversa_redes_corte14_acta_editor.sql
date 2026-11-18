begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 90 · REVERSA (PROPUESTA). Quita las 2 funciones nuevas. No hay datos que borrar.
-- SE NIEGA si alguna función de redes cambió después de la migración.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_levantar_acta(text,text,text)') is null then raise exception 'No hay nada que revertir: el acta no está aplicada'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '7c888d4f9ba3835cef951b49ada8ca59' then
    raise exception 'Las funciones cambiaron después de la migración del acta: la reversa se niega a pisarlas; avise';
  end if;
end $$;
drop function public.geoportal_redes_levantar_acta(text, text, text);
drop function redes.f_levantar_funcionario(text, text);
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte14_acta', 'reversa_redes_corte14_acta', null, jsonb_build_object('motivo', 'reversa del acta del Corte 14'), null);
commit;
