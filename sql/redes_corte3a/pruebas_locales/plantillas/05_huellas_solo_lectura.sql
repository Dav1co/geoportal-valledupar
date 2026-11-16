-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES de la migración: «funciones de redes» dice «CORTE 2 (listo para el 3a)»; las 8 RPC nuevas «NO EXISTE (sin aplicar)»; las 2 RPC y las
-- 2 vistas que se reemplazan «CORTE 2 (sin cambiar)»; el bucket y las dependencias «EXISTE».
-- Después: «CORTE 3a (aplicado)», «NUEVA (aplicada)» y «CORTE 3a (reemplazada)». Tras la reversa: otra vez como antes.
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
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = c.antes then 'CORTE 2 (sin cambiar)'
              when max(md5(pg_get_functiondef(p.oid))) = c.despues then 'CORTE 3a (reemplazada)' else 'DISTINTA' end
    from cam c left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = c.objeto group by c.objeto, c.antes, c.despues),
vis(objeto, antes, despues) as (values ('redes.v_dano', '{{MD5_V_DANO_2}}', '{{MD5_V_DANO_3A}}'), ('redes.v_epicrisis', '{{MD5_V_EPICRISIS_2}}', '{{MD5_V_EPICRISIS_3A}}')),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')),
dep(objeto, firma) as (values ('tecnica.f_autorizar_captura', 'tecnica.f_autorizar_captura(text,text)'), ('tecnica.f_max_horas_inicio', 'tecnica.f_max_horas_inicio()'),
    ('tecnica.f_solo_agregar', 'tecnica.f_solo_agregar()'), ('tecnica.f_auditar', 'tecnica.f_auditar(text,text,text,jsonb,text)'), ('tecnica.f_perfil', 'tecnica.f_perfil(text)'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_CORTE_2}}' then 'CORTE 2 (listo para el 3a)' when '{{MD5_CORTE_3A}}' then 'CORTE 3a (aplicado)' else 'DISTINTA' end as estado
union all select * from rpc
union all select * from rpc2
union all select 'vista ' || v.objeto, md5(pg_get_viewdef(v.objeto::regclass, true)),
       case md5(pg_get_viewdef(v.objeto::regclass, true)) when v.antes then 'CORTE 2 (sin cambiar)' when v.despues then 'CORTE 3a (reemplazada)' else 'DISTINTA' end from vis v
union all select '1 bucket redes-evidencias (del Corte 2)', null, case when exists (select 1 from storage.buckets where id = 'redes-evidencias') then 'EXISTE' else 'FALTA' end
union all select 'dependencia ' || d.objeto, case when to_regprocedure(d.firma) is not null then md5(pg_get_functiondef(to_regprocedure(d.firma))) end,
       case when to_regprocedure(d.firma) is not null then 'EXISTE' else 'FALTA' end from dep d
order by 1;
