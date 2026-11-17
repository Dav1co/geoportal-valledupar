-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «FASE 2 (lista para la Fase 3)»; las 4 nuevas «NO EXISTE»; «tablas del flujo» «NO EXISTEN (sin aplicar)».
-- DESPUÉS: «FASE 3 (aplicada)», 4 «NUEVA» y «tablas del flujo» «EXISTEN». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise.
-- =====================================================================
with nue(firma, nueva) as (values ('redes.f_flujo_clase(numeric)', '89bae2a6a12a190dd157284a5e5d70f3'), ('public.geoportal_redes_geovisor_mvt_flujo(text,text,integer,integer,integer)', '18f63f5c1a3d8b4879eff4ea9c6aa5a3'), ('public.geoportal_redes_flujo_modelo(text)', '8537203136d3b32b11cb60b928233816'), ('public.geoportal_redes_flujo_tramo(text,text)', '8ff94c6089fe2705b766bfc81ed4fb71')),
rnue as (
  select '3 ' || n.firma as objeto, md5(pg_get_functiondef(to_regprocedure(n.firma))) as md5,
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '7f9c0157c47e371e1d3d87ef6bda847b' then 'FASE 2 (lista para la Fase 3)' when 'fbcbd7b3da35dfdc0e4104ed4a6e8f2f' then 'FASE 3 (aplicada)' else 'DISTINTA' end as estado
union all select * from rnue
union all select '4 tablas de referencia del 9a (ref_cargas) y de la Fase 2 (usuarios_sensibles)', null,
       case when to_regclass('redes.ref_cargas') is not null and to_regclass('redes.usuarios_sensibles') is not null then 'ESTÁN' else 'FALTA' end
union all select '5 tablas del flujo (flujo_modelo, flujo_modelo_horas)', null,
       case (to_regclass('redes.flujo_modelo') is not null)::int + (to_regclass('redes.flujo_modelo_horas') is not null)::int
         when 0 then 'NO EXISTEN (sin aplicar)' when 2 then 'EXISTEN (Fase 3)' else 'DISTINTA' end
order by 1;
