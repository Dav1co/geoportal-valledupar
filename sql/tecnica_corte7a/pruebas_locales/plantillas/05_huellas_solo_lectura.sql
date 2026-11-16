-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 6c (listo para el 7a)»; las 11 RPC nuevas «NO EXISTE»; las 4 reemplazadas «CORTE 6c (sin cambiar)»; las 4 tablas, las 2 vistas
-- y el bucket «NO EXISTE». DESPUÉS: «CORTE 7a (aplicado)», 11 «NUEVA», 4 «CORTE 7a (reemplazada)» y 7 «EXISTE».
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with esp(objeto, nueva) as (values {{RPC_NUEVAS}}),
rpc as (
  select 'public.' || e.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(firma, antes, despues) as (values {{CAMBIADAS}}),
rcam as (
  select c.firma, md5(pg_get_functiondef(to_regprocedure(c.firma))),
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 6c (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 7a (reemplazada)' else 'DISTINTA' end
    from cam c),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_CORTE_6C}}' then 'CORTE 6c (listo para el 7a)' when '{{MD5_CORTE_7A}}' then 'CORTE 7a (aplicado)' else 'DISTINTA' end as estado
union all select * from rpc
union all select * from rcam
union all select '1 objeto ' || t, null, case when to_regclass(t) is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
  from unnest(array['tecnica.quimico_ficha_eventos', 'tecnica.quimico_ficha_preparaciones', 'tecnica.quimico_movimientos', 'tecnica.quimico_parametros',
                    'tecnica.v_quimico_vigente', 'tecnica.v_quimico_saldo']) t
union all select '1 bucket tecnica-evidencias', null, case when exists (select 1 from storage.buckets where id = 'tecnica-evidencias') then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
order by 1;
