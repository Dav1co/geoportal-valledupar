-- =====================================================================
-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · 05 — GUARDIA (se detiene sin cambiar nada si la base no es la publicada el 21-nov 19:45)
-- Huellas: campo 3437a83d… (TODAS sus funciones y las public.geoportal_campo_*), acta 111506c6…, y las md5 de las dos funciones que se reemplazan.
-- =====================================================================
do $$
declare v text;
begin
  if to_regprocedure('campo.f_supervisor_comercial(text)') is not null then
    raise exception 'El cambio de cargo y área por el supervisor ya parece aplicado (existe campo.f_supervisor_comercial): use la reversa antes de repetir';
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_CAMPO}}' then
    raise exception 'Las funciones de campo no son las publicadas el 21-nov 19:45 (huella {{HUELLA_CAMPO}}; hay %): deténgase y avise', v;
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%');
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_ACTA}}' then
    raise exception 'Las funciones del acta no son las publicadas (huella {{HUELLA_ACTA}}; hay %): deténgase y avise', v;
  end if;
  if md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)'))) is distinct from '{{MD5_FIJAR}}'
     or md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal(text,jsonb,text)'))) is distinct from '{{MD5_PERSONAL}}' then
    raise exception 'geoportal_campo_personal_fijar o geoportal_campo_personal no son las publicadas el 21-nov: deténgase y avise';
  end if;
end $$;
