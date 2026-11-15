-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES de la migración: «funciones de redes» dice «CORTE 1a (listo para el 2)», las 8 RPC y el bucket «NO EXISTE (sin aplicar)» y las dependencias «EXISTE».
-- Después: «CORTE 2 (aplicado)» y «NUEVA (aplicada)». Tras la reversa: otra vez como antes. Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise.
-- =====================================================================
with esp(objeto, nueva) as (values {{RPC_FILAS}}),
rpc as (
  select 'public.' || e.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')),
dep(objeto, firma) as (values ('tecnica.f_autorizar_captura', 'tecnica.f_autorizar_captura(text,text)'), ('tecnica.f_max_horas_inicio', 'tecnica.f_max_horas_inicio()'),
    ('tecnica.f_solo_agregar', 'tecnica.f_solo_agregar()'), ('tecnica.f_auditar', 'tecnica.f_auditar(text,text,text,jsonb,text)'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_CORTE_1A}}' then 'CORTE 1a (listo para el 2)' when '{{MD5_CORTE_2}}' then 'CORTE 2 (aplicado)' when null then 'FALTA el Corte 1a' else 'DISTINTA' end as estado
union all select * from rpc
union all select '1 bucket redes-evidencias', null, case when exists (select 1 from storage.buckets where id = 'redes-evidencias') then 'NUEVA (aplicada)' else 'NO EXISTE (sin aplicar)' end
union all select 'dependencia ' || d.objeto, case when to_regprocedure(d.firma) is not null then md5(pg_get_functiondef(to_regprocedure(d.firma))) end,
       case when to_regprocedure(d.firma) is not null then 'EXISTE' else 'FALTA' end from dep d
union all select 'dependencia storage.objects', null, case when to_regclass('storage.objects') is not null then 'EXISTE' else 'FALTA' end
order by 1;
