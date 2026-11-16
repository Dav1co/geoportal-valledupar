-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES de la migración: «funciones de redes» dice «CORTE 3a (listo para el 3b)»; las 5 RPC nuevas «NO EXISTE (sin aplicar)»; activo_buscar y v_epicrisis
-- «CORTE 3a (sin cambiar)». Después: «CORTE 3b (aplicado)», «NUEVA (aplicada)» y «CORTE 3b (reemplazada)». Tras la reversa: otra vez como antes.
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise.
-- =====================================================================
with esp(objeto, nueva) as (values ('geoportal_redes_ficha_editar', '81b34cc4069f05b0d11c0bd48c2e50aa'), ('geoportal_redes_foto_perfil_fijar', 'a430ec67e09a89e03de29b6716c7a766'), ('geoportal_redes_foto_perfil_preparar', 'b1ed56aa688b8c060a49a058f903a1ff'), ('geoportal_redes_galeria', '3f96811f59b6cd31497d3d013b102205'), ('geoportal_redes_perfil', '2520ff7f1def39d5ba9958dbeb7ee7cc')),
rpc as (
  select 'public.' || e.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(objeto, antes, despues) as (values ('geoportal_redes_activo_buscar', '12e6d731e9a49981073e05ad9624dafe', 'c735714c0623621a4acd74ccbd0346ae')),
rpc2 as (
  select 'public.' || c.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = c.antes then 'CORTE 3a (sin cambiar)'
              when max(md5(pg_get_functiondef(p.oid))) = c.despues then 'CORTE 3b (reemplazada)' else 'DISTINTA' end
    from cam c left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = c.objeto group by c.objeto, c.antes, c.despues),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when 'b1511119a1014345b4287dc7a45cfcfc' then 'CORTE 3a (listo para el 3b)' when '45971067176a3d30286b6227f0447c0d' then 'CORTE 3b (aplicado)' else 'DISTINTA' end as estado
union all select * from rpc
union all select * from rpc2
union all select 'vista redes.v_epicrisis', md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)),
       case md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) when '4769d9dc85bdb6b6cc81364b3ab7dec7' then 'CORTE 3a (sin cambiar)' when 'a1e45ec72cb5b254a67698111994746a' then 'CORTE 3b (reemplazada)' else 'DISTINTA' end
union all select '1 bucket redes-evidencias (del Corte 2)', null, case when exists (select 1 from storage.buckets where id = 'redes-evidencias') then 'EXISTE' else 'FALTA' end
order by 1;
