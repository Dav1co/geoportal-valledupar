-- =====================================================================
-- TÉCNICA · FASE 1 · «MIS REPORTES» (levantar_mios) · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «CORTE 15 (lista para Mis reportes)», la nueva «NO EXISTE» y el índice «NO EXISTE».
-- DESPUÉS: «MIS REPORTES (aplicado)», la nueva «NUEVA» y el índice «ESTÁ». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise.
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
       case (select m from conj) when '{{MD5_BASE}}' then 'CORTE 15 (lista para Mis reportes)' when '{{MD5_MIOS}}' then 'MIS REPORTES (aplicado)' else 'DISTINTA' end as estado
union all select * from rnue
union all select '2 ' || p.firma || ' (no se toca)', md5(pg_get_functiondef(to_regprocedure(p.firma))),
       case when to_regprocedure(p.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(p.firma))) = p.publicada then 'LA PUBLICADA' else 'DISTINTA' end from pub p
union all select '4 índice redes.ix_levantar_puntos_autor', null, case when to_regclass('redes.ix_levantar_puntos_autor') is null then 'NO EXISTE (sin aplicar)' else 'ESTÁ (aplicado)' end
union all select '5 tablas que lee (levantar_puntos, levantar_eventos, v_levantar_punto)', null,
       case when to_regclass('redes.levantar_puntos') is not null and to_regclass('redes.levantar_eventos') is not null and to_regclass('redes.v_levantar_punto') is not null then 'ESTÁN' else 'FALTA' end
union all select '6 INFO datos: puntos por levantar · personas que han reportado', null,
       (select count(*) from redes.levantar_puntos) || ' · ' || (select count(distinct autor) from redes.levantar_puntos)
order by 1;
