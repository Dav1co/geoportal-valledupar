-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · CORRECCIÓN «LA VÁLVULA QUE CERRÓ EL OPERADOR» · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «AGUAS ARRIBA (lista para la corrección)» y la nueva «NO EXISTE».
-- DESPUÉS: «CORRECCIÓN (aplicada)» y la nueva «NUEVA». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise.
-- =====================================================================
with nue(firma, nueva) as (values ('public.geoportal_redes_cierres_registro(text,text)', '97d6150367c8f751bea98e237522a8f7')),
rnue as (
  select '3 ' || n.firma as objeto, md5(pg_get_functiondef(to_regprocedure(n.firma))) as md5,
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from nue n),
pub(firma, publicada) as (values ('public.geoportal_redes_valvula_maniobra(text,text,text,text,text,text,text)', 'c17b23590b8af31d574f593aaeb8c781'), ('public.geoportal_redes_cortes_vigentes(text)', 'c09eadccc9399bb27b78dfb0ad14c8f8'), ('redes.f_geovisor_acceso(text)', '21a230858f6f70457275ed8d9919093e'), ('redes.f_geovisor_lectura(text)', '1e0e4e790361d8b366de64ed0506b50a'), ('redes.f_sim_autorizar(text)', 'a51058c0b84d12517137f8f0eded944f')),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when 'af34032d8e20434f53744eb642cddac2' then 'AGUAS ARRIBA (lista para la corrección)' when '63d917635b33e3696f28a3b0e579c002' then 'CORRECCIÓN (aplicada)' else 'DISTINTA' end as estado
union all select * from rnue
union all select '2 ' || p.firma || ' (no se toca)', md5(pg_get_functiondef(to_regprocedure(p.firma))),
       case when to_regprocedure(p.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(p.firma))) = p.publicada then 'LA PUBLICADA' else 'DISTINTA' end from pub p
union all select '4 tablas que lee (valvula_maniobras, danos, intervenciones)', null,
       case when to_regclass('redes.valvula_maniobras') is not null and to_regclass('redes.danos') is not null and to_regclass('redes.intervenciones') is not null then 'ESTÁN' else 'FALTA' end
union all select '5 INFO datos: maniobras registradas · válvulas cerradas en este momento', null,
       (select count(*) from redes.valvula_maniobras) || ' · ' || (select count(*) from redes.f_cierres_vigentes())
order by 1;
