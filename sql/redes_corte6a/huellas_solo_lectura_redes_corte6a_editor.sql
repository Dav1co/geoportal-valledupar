-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 5c (listo para el 6a)»; las 4 RPC nuevas «NO EXISTE»; las 10 reemplazadas «CORTE 5c (sin cambiar)»;
-- las 3 tablas y la columna «NO EXISTE». DESPUÉS: «CORTE 6a (aplicado)», 4 «NUEVA», 10 «CORTE 6a (reemplazada)» y 4 «EXISTE».
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with esp(objeto, nueva) as (values ('geoportal_redes_geovisor', 'c6eaa9bd7840c2827ecd2991938f8439'), ('geoportal_redes_geovisor_capa', 'f53157aafba91cb1b5c6f1712b9a26ce'), ('geoportal_redes_geovisor_capas_fijar', 'f2498ee99743b202b4ba36a5beb402e9'), ('geoportal_redes_geovisor_mvt', 'a2b1806a5200e2a3119f7a4592c5db05')),
rpc as (
  select 'public.' || e.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(firma, antes, despues) as (values ('public.geoportal_redes_carga_lote(text,bigint,jsonb)', '7a9023aea35bfac3b4c6789ba31dfb04', 'c231d11e9e1a8d7da92e9e1d24538597'), ('public.geoportal_redes_carga_resumen(text,bigint)', '5440de9e3d493c08a1adfeb371c77142', '080cc0adc4fe187c6b7b32ddbffef36d'), ('public.geoportal_redes_carga_publicar(text,bigint,text)', 'bc0776c9047fb812d79a0472f6f611aa', '34e7db499d5b673dbfd255a244cde06c'), ('public.geoportal_redes_carga_anular(text,bigint,text)', 'd50ce45663e49aeac1e663e4a9ff6506', 'a37619ca3507f73f89647e469ca3e52c'), ('public.geoportal_redes_carga_muestra(text,bigint)', 'dbeb32df95032c73b63a8d0ba2e7f916', '221d72397ec45c2ff0384490d64feadd'), ('public.geoportal_redes_carga_revertir(text,text,text)', 'e75fc3beec3f732d4d23d9b326abc1bd', 'c67e42afd8d8322ef747216ff55fbe44'), ('public.geoportal_redes_cargue_iniciar(text,text,text,text,integer,text,integer,text,text)', 'bb82f2257259cef249565c18a537836c', '49e0bfc8069af69cec997b6e61c939bf'), ('public.geoportal_redes_carga_devolver_campo(text,bigint,text,text,text)', 'b36ed8f42ee53116db9862d5506d6178', '3d539b299226e7a018c8755454c74854'), ('public.geoportal_redes_cargue_capas(text)', 'ece3cdd5b0930ad6c978e0918767241d', '039d0c5240a323af540bc34e448a6c25'), ('public.geoportal_redes_mi_perfil(text)', '5586014c1951c945beae56892c392c1f', '63f796c3777a4b46cebc82c08d1c81bd')),
rcam as (
  select c.firma, md5(pg_get_functiondef(to_regprocedure(c.firma))),
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 5c (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 6a (reemplazada)' else 'DISTINTA' end
    from cam c),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when 'a5ce1ff8c5659de3b853e30f4d3025e6' then 'CORTE 5c (listo para el 6a)' when '91a4d3e6e1c3539d8a447cb00a52d735' then 'CORTE 6a (aplicado)' else 'DISTINTA' end as estado
union all select * from rpc
union all select * from rcam
union all select '1 tabla ' || t, null, case when to_regclass(t) is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
  from unnest(array['redes.geovisor_capas', 'redes.capas_por_perfil', 'redes.capas_por_perfil_eventos']) t
union all select '1 columna redes.capas.carga_supervisor', null,
       case when exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'capas' and column_name = 'carga_supervisor')
            then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
order by 1;
