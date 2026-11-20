-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «MIS REPORTES (lista para el aviso)» y las 3 nuevas «NO EXISTE».
-- DESPUÉS: «AVISO POR CONTRATO (aplicado)» y las 3 «NUEVA». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise.
-- =====================================================================
with nue(firma, nueva) as (values ('redes.f_eventos_del_contrato(text)', '8095ab6a65b1d983873d34d9fdfe5b95'), ('redes.f_evento_contrato_acceso(text)', '14128308aa6b4a48c8d32ca0f692bbbc'), ('public.geoportal_redes_evento_contrato(text,text)', 'f82b45906c62feca8b431020284e8bbf')),
rnue as (
  select '3 ' || n.firma as objeto, md5(pg_get_functiondef(to_regprocedure(n.firma))) as md5,
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from nue n),
pub(firma, publicada) as (values ('redes.f_eventos_abiertos()', '2d265a26461ea19a01e9a81bb927b120'), ('redes.f_evento_contratos(geometry,boolean,boolean)', '8dafa57412c9b41aca0a0e3652f3bf2a'), ('redes.f_evento_franja(text,timestamp with time zone,text,timestamp with time zone)', 'fb9de8c4ada4a35de44889aea9f17b62'), ('public.geoportal_redes_eventos_vigentes(text)', '30d3b3306038af969a1e7e1b75e6f5ef'), ('public.geoportal_redes_evento_declarar(text,jsonb)', 'ddf3e36525c21605a4dbf36789082c92')),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '314112df87e4d649945fd3f611857025' then 'MIS REPORTES (lista para el aviso)' when '52147337ba4d42045bdd937a2b1f0bc1' then 'AVISO POR CONTRATO (aplicado)' else 'DISTINTA' end as estado
union all select * from rnue
union all select '2 ' || p.firma || ' (no se toca)', md5(pg_get_functiondef(to_regprocedure(p.firma))),
       case when to_regprocedure(p.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(p.firma))) = p.publicada then 'LA PUBLICADA' else 'DISTINTA' end from pub p
union all select '5 tablas que lee (eventos_suspension, v_evento_suspension, contrato_tramo)', null,
       case when to_regclass('redes.eventos_suspension') is not null and to_regclass('redes.v_evento_suspension') is not null and to_regclass('redes.contrato_tramo') is not null then 'ESTÁN' else 'FALTA' end
union all select '6 INFO datos: eventos abiertos · contratos con amarre a la red', null,
       (select count(*) from redes.f_eventos_abiertos()) || ' · ' || (select count(*) from redes.contrato_tramo)
order by 1;
