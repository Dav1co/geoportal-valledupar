-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · CORRECCIÓN «LA VÁLVULA QUE CERRÓ EL OPERADOR» · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «AGUAS ARRIBA (lista para la corrección)» y la nueva «NO EXISTE».
-- DESPUÉS: «CORRECCIÓN (aplicada)» y la nueva «NUEVA». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise.
-- =====================================================================
with nue(firma, nueva) as (values {{NUEVAS}}),
rnue as (
  select '3 ' || n.firma as objeto, md5(pg_get_functiondef(to_regprocedure(n.firma))) as md5,
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from nue n),
pub(firma, publicada) as (values {{PUBLICADAS}}),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_BASE}}' then 'AGUAS ARRIBA (lista para la corrección)' when '{{MD5_VO}}' then 'CORRECCIÓN (aplicada)' else 'DISTINTA' end as estado
union all select * from rnue
union all select '2 ' || p.firma || ' (no se toca)', md5(pg_get_functiondef(to_regprocedure(p.firma))),
       case when to_regprocedure(p.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(p.firma))) = p.publicada then 'LA PUBLICADA' else 'DISTINTA' end from pub p
union all select '4 tablas que lee (valvula_maniobras, danos, intervenciones)', null,
       case when to_regclass('redes.valvula_maniobras') is not null and to_regclass('redes.danos') is not null and to_regclass('redes.intervenciones') is not null then 'ESTÁN' else 'FALTA' end
union all select '5 INFO datos: maniobras registradas · válvulas cerradas en este momento', null,
       (select count(*) from redes.valvula_maniobras) || ' · ' || (select count(*) from redes.f_cierres_vigentes())
order by 1;
