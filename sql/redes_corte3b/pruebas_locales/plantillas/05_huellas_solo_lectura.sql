-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES de la migración: «funciones de redes» dice «CORTE 3a (listo para el 3b)»; las 5 RPC nuevas «NO EXISTE (sin aplicar)»; activo_buscar y v_epicrisis
-- «CORTE 3a (sin cambiar)». Después: «CORTE 3b (aplicado)», «NUEVA (aplicada)» y «CORTE 3b (reemplazada)». Tras la reversa: otra vez como antes.
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise.
-- =====================================================================
with esp(objeto, nueva) as (values {{RPC_NUEVAS}}),
rpc as (
  select 'public.' || e.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(objeto, antes, despues) as (values {{RPC_CAMBIADAS}}),
rpc2 as (
  select 'public.' || c.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = c.antes then 'CORTE 3a (sin cambiar)'
              when max(md5(pg_get_functiondef(p.oid))) = c.despues then 'CORTE 3b (reemplazada)' else 'DISTINTA' end
    from cam c left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = c.objeto group by c.objeto, c.antes, c.despues),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_CORTE_3A}}' then 'CORTE 3a (listo para el 3b)' when '{{MD5_CORTE_3B}}' then 'CORTE 3b (aplicado)' else 'DISTINTA' end as estado
union all select * from rpc
union all select * from rpc2
union all select 'vista redes.v_epicrisis', md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)),
       case md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) when '{{MD5_V_EPICRISIS_3A}}' then 'CORTE 3a (sin cambiar)' when '{{MD5_V_EPICRISIS_3B}}' then 'CORTE 3b (reemplazada)' else 'DISTINTA' end
union all select '1 bucket redes-evidencias (del Corte 2)', null, case when exists (select 1 from storage.buckets where id = 'redes-evidencias') then 'EXISTE' else 'FALTA' end
order by 1;
