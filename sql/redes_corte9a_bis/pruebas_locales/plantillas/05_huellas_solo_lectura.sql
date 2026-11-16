-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 9a (listo para el 9a-bis)»; las {{N_CAMBIADAS}} reemplazadas «CORTE 9a (sin cambiar)»; las {{N_NUEVAS}} nuevas «NO EXISTE»;
--        los 4 índices «EXISTE».
-- DESPUÉS: «CORTE 9a-bis (aplicado)», {{N_CAMBIADAS}} «CORTE 9a-bis (reemplazada)», {{N_NUEVAS}} «NUEVA» y los 4 índices «EXISTE».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values {{CAMBIADAS}}),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 9a (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 9a-bis (reemplazada)' else 'DISTINTA' end as estado
    from cam c),
nue(firma, nueva) as (values {{NUEVAS}}),
rnue as (
  select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_BASE}}' then 'CORTE 9a (listo para el 9a-bis)' when '{{MD5_BIS}}' then 'CORTE 9a-bis (aplicado)' else 'DISTINTA' end as estado
union all select * from rcam
union all select * from rnue
union all select '4 índice ' || i, null, case when exists (select 1 from pg_indexes where schemaname = 'redes' and indexname = i) then 'EXISTE' else 'FALTA' end
  from unnest(array['ix_nodos_llave', 'ix_nodos_activo', 'ix_tn_ini', 'ix_tn_fin']) i
order by 1;
