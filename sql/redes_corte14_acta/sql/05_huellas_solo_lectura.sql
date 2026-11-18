-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 05 · HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada. Generada por generar.py.
-- ANTES: «funciones de redes» dice «CORTE 14 (listo para el acta)» y las 2 nuevas «NO EXISTE». DESPUÉS: «ACTA (aplicada)» y 2 «NUEVA».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with nue(firma, nueva) as (values ('redes.f_levantar_funcionario(text,text)', '60ef521c697327104ad52fbbbbec78b6'), ('public.geoportal_redes_levantar_acta(text,text,text)', '0a7f82ff6fa307a9edb877f5ab0aa816')),
conj as (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '1a9ef250a74fb01962f463d98834cc4a' then 'CORTE 14 (listo para el acta)' when '7c888d4f9ba3835cef951b49ada8ca59' then 'ACTA (aplicada)' else 'DISTINTA' end as estado
union all select '1 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
       case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end from nue n
union all select '2 objetos que usa (puntos por levantar, Personal de distribución y cargo de Comercial)', null,
       case when to_regclass('redes.levantar_puntos') is not null and to_regclass('redes.v_personal_ficha') is not null and to_regprocedure('campo.f_cargo_vigente(text)') is not null then 'ESTÁN' else 'FALTA' end
order by 1;
