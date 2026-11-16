-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES de la migración: «funciones de redes» dice «CORTE 2 (listo para el 3a)»; las 8 RPC nuevas «NO EXISTE (sin aplicar)»; las 2 RPC y las
-- 2 vistas que se reemplazan «CORTE 2 (sin cambiar)»; el bucket y las dependencias «EXISTE».
-- Después: «CORTE 3a (aplicado)», «NUEVA (aplicada)» y «CORTE 3a (reemplazada)». Tras la reversa: otra vez como antes.
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise.
-- =====================================================================
with esp(objeto, nueva) as (values ('geoportal_redes_asociar_activo', '5a4a6c58d8269eb80fee2c3d989cd4c7'), ('geoportal_redes_crear_intervencion', '65579eea5c981ca532a605b33be8cbe3'), ('geoportal_redes_danos_abiertos', '3e83bbf79f79da3526bde3523c3ac5c4'), ('geoportal_redes_formulario_intervencion', '452c8e353d00ef0ecf1ae6d31d35536e'), ('geoportal_redes_intervencion_recursos', '44a92bf4a7379df6f3a259e254d245cf'), ('geoportal_redes_intervenciones', 'b0d3a41405f63f4f35781ef2865122f3'), ('geoportal_redes_no_identificados', 'e6dea9565701b15dc9fcb925861066bb'), ('geoportal_redes_preparar_intervencion', '363488408002e09d046b842ba7861c8c')),
rpc as (
  select 'public.' || e.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(objeto, antes, despues) as (values ('geoportal_redes_crear_dano', '3c5a3d37d8e61e50b8bafb204dbdebd2', '7e70de54924240852635815f423571d1'), ('geoportal_redes_preparar_dano', '52af990ab124e9ea1d8a822a5a23e520', 'e425feacdf9066b56fc0ae971aa843e1')),
rpc2 as (
  select 'public.' || c.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = c.antes then 'CORTE 2 (sin cambiar)'
              when max(md5(pg_get_functiondef(p.oid))) = c.despues then 'CORTE 3a (reemplazada)' else 'DISTINTA' end
    from cam c left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = c.objeto group by c.objeto, c.antes, c.despues),
vis(objeto, antes, despues) as (values ('redes.v_dano', '6c5d9335e3d49eddaf7149a1b8731ef6', 'bee1b39d753fc55ae7cb85a3952896fb'), ('redes.v_epicrisis', 'd97fa858302da7febe1cb82270e24185', '6f459132b88e95dbce6f8d2b398ffeef')),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')),
dep(objeto, firma) as (values ('tecnica.f_autorizar_captura', 'tecnica.f_autorizar_captura(text,text)'), ('tecnica.f_max_horas_inicio', 'tecnica.f_max_horas_inicio()'),
    ('tecnica.f_solo_agregar', 'tecnica.f_solo_agregar()'), ('tecnica.f_auditar', 'tecnica.f_auditar(text,text,text,jsonb,text)'), ('tecnica.f_perfil', 'tecnica.f_perfil(text)'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '06ecefcf2922e724e1be5546b87a5510' then 'CORTE 2 (listo para el 3a)' when '2bd01b1d2556d8630f8533ee23ed2eb3' then 'CORTE 3a (aplicado)' else 'DISTINTA' end as estado
union all select * from rpc
union all select * from rpc2
union all select 'vista ' || v.objeto, md5(pg_get_viewdef(v.objeto::regclass, true)),
       case md5(pg_get_viewdef(v.objeto::regclass, true)) when v.antes then 'CORTE 2 (sin cambiar)' when v.despues then 'CORTE 3a (reemplazada)' else 'DISTINTA' end from vis v
union all select '1 bucket redes-evidencias (del Corte 2)', null, case when exists (select 1 from storage.buckets where id = 'redes-evidencias') then 'EXISTE' else 'FALTA' end
union all select 'dependencia ' || d.objeto, case when to_regprocedure(d.firma) is not null then md5(pg_get_functiondef(to_regprocedure(d.firma))) end,
       case when to_regprocedure(d.firma) is not null then 'EXISTE' else 'FALTA' end from dep d
order by 1;
