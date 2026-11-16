-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 6a (listo para el 6b)»; las 4 RPC nuevas «NO EXISTE»; las 2 reemplazadas «CORTE 6a (sin cambiar)»; las 4 tablas y la
-- vista «NO EXISTE». DESPUÉS: «CORTE 6b (aplicado)», 4 «NUEVA», 2 «CORTE 6b (reemplazada)» y 5 «EXISTE».
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with esp(objeto, nueva) as (values ('geoportal_redes_contrato_tarjeta', '1af144caaebfe57e14c71d41c3e4b520'), ('geoportal_redes_geovisor_mvt_contratos', '6e5deffd58bb9d5e8c27739c73adae67'), ('geoportal_redes_vista_abrir', '4d3f657eb81827e50d2d775aae6d1759'), ('geoportal_redes_vista_compartir', '8e3dec45766cc19c7f5ae2b42046c826')),
rpc as (
  select 'public.' || e.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(firma, antes, despues) as (values ('public.geoportal_redes_geovisor(text)', 'c6eaa9bd7840c2827ecd2991938f8439', '034c6ad129c2c34b41541dc9cabfd93c'), ('public.geoportal_redes_geovisor_capa(text,text,date,date)', 'f53157aafba91cb1b5c6f1712b9a26ce', '447cce7bc84f681d07cd916bbd7b9eb4')),
rcam as (
  select c.firma, md5(pg_get_functiondef(to_regprocedure(c.firma))),
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 6a (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 6b (reemplazada)' else 'DISTINTA' end
    from cam c),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '91a4d3e6e1c3539d8a447cb00a52d735' then 'CORTE 6a (listo para el 6b)' when 'fca28bf695d1fcfa153f1113ce821528' then 'CORTE 6b (aplicado)' else 'DISTINTA' end as estado
union all select * from rpc
union all select * from rcam
union all select '1 objeto ' || t, null, case when to_regclass(t) is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
  from unnest(array['redes.contratos_capa', 'redes.contratos_capa_estado', 'redes.vistas_compartidas', 'redes.muestreo_rangos', 'redes.v_reportes_comercial']) t
order by 1;
