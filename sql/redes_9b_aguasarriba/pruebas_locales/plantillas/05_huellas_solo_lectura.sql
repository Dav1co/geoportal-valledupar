-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «CORTE 14 (listo para aguas arriba)» y las {{N_NUEVAS}} nuevas «NO EXISTE».
-- DESPUÉS: «AGUAS ARRIBA (aplicada)» y {{N_NUEVAS}} «NUEVA». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise.
-- =====================================================================
with nue(firma, nueva) as (values {{NUEVAS}}),
rnue as (
  select '3 ' || n.firma as objeto, md5(pg_get_functiondef(to_regprocedure(n.firma))) as md5,
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_BASE}}' then 'CORTE 14 (listo para aguas arriba)' when '{{MD5_AU}}' then 'AGUAS ARRIBA (aplicada)' else 'DISTINTA' end as estado
union all select * from rnue
union all select '2 redes.f_simular_cierre(bigint) (la simulación de siempre: no se toca)', md5(pg_get_functiondef('redes.f_simular_cierre(bigint)'::regprocedure)),
       case md5(pg_get_functiondef('redes.f_simular_cierre(bigint)'::regprocedure)) when '{{MD5_CIERRE}}' then 'LA PUBLICADA' else 'DISTINTA' end
union all select '4 tablas que usa (flujo_modelo, pm_nodos)', null,
       case when to_regclass('redes.flujo_modelo') is not null and to_regclass('redes.pm_nodos') is not null then 'ESTÁN' else 'FALTA' end
union all select '5 INFO datos: tubos del flujo del modelo vigente · nodos del Plan con cota', null,
       (select count(*) from redes.flujo_modelo where carga_id = redes.f_ref_vigente('flujo_modelo')) || ' · '
       || (select count(cota_m) from redes.pm_nodos where carga_id = redes.f_ref_vigente('pm_nodos'))
order by 1;
