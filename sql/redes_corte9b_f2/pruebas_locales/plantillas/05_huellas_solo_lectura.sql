-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «9b 1a + 1b (listo para la Fase 2)»; las {{N_NUEVAS}} nuevas «NO EXISTE»; «tablas de la Fase 2» «NO EXISTEN (sin aplicar)».
-- DESPUÉS: «FASE 2 (aplicada)», {{N_NUEVAS}} «NUEVA» y «tablas de la Fase 2» «EXISTEN». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise.
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
       case (select m from conj) when '{{MD5_BASE}}' then '9b 1a + 1b (listo para la Fase 2)' when '{{MD5_F2}}' then 'FASE 2 (aplicada)' else 'DISTINTA' end as estado
union all select * from rnue
union all select '4 tablas del 9b 1b (corte_fotos) y del 9a (pm_nodos)', null,
       case when to_regclass('redes.corte_fotos') is not null and to_regclass('redes.pm_nodos') is not null then 'ESTÁN' else 'FALTA' end
union all select '5 tablas de la Fase 2 (tipos_sensible, usuarios_sensibles, usuario_sensible_eventos, presion_trabajo, sensor_lecturas)', null,
       case (to_regclass('redes.tipos_sensible') is not null)::int + (to_regclass('redes.usuarios_sensibles') is not null)::int + (to_regclass('redes.usuario_sensible_eventos') is not null)::int
            + (to_regclass('redes.presion_trabajo') is not null)::int + (to_regclass('redes.sensor_lecturas') is not null)::int
         when 0 then 'NO EXISTEN (sin aplicar)' when 5 then 'EXISTEN (Fase 2)' else 'DISTINTA' end
union all select '6 INFO capa «cortes» en la lista del geovisor', null, (select case when activa then 'visible' else 'oculta' end from redes.geovisor_capas where codigo = 'cortes')
order by 1;
