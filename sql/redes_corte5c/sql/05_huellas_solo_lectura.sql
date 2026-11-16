-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 5b (listo para el 5c)»; las 6 RPC nuevas «NO EXISTE»; las 8 reemplazadas «CORTE 5b (sin cambiar)»;
-- las 2 tablas «NO EXISTE». DESPUÉS: «CORTE 5c (aplicado)», 6 «NUEVA», 8 «CORTE 5c (reemplazada)» y 2 «EXISTE».
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with esp(objeto, nueva) as (values ('geoportal_redes_carga_devolver_campo', 'b36ed8f42ee53116db9862d5506d6178'), ('geoportal_redes_carga_muestra', 'dbeb32df95032c73b63a8d0ba2e7f916'), ('geoportal_redes_cargue_capas', 'ece3cdd5b0930ad6c978e0918767241d'), ('geoportal_redes_cargue_historial', '2931fb96f354077feb8f55f7e8c9eae1'), ('geoportal_redes_cargue_iniciar', 'bb82f2257259cef249565c18a537836c'), ('geoportal_tec_punto_ubicacion_corregir', '5518a3d3bd764c7801b089d7e48f2a1e')),
rpc as (
  select 'public.' || e.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(firma, antes, despues) as (values ('redes.f_geo_desde_wkt(text,integer)', '54f3575c8826a1f2b6383b54206b5979', '275df2e3a71fcd4fcf8623858f7a02d4'), ('redes.f_candidatos(bigint)', 'c7c2f4f51b8aaa20a9cf20e553340364', 'e8b1b1c04a4e826e9b631c489a4d4716'), ('redes.f_preparar_candidatos(bigint)', '21eb19b24d8ec93bf94871c619210493', '140cd3d91986bea1a9e5f772c78a23e3'), ('redes.f_resumen(bigint)', '187ab77324b78a81d8ddd16edbacddb8', '94f7e7b146a554d882a481a9f0973027'), ('redes.f_fusionar_ficha()', '618360146f984c9715de3eb494a3a818', '490965f220573ec3bee6423f7c63ab2d'), ('redes.f_iniciar(text,text,text,integer,text,integer,text,text)', 'cbf4a50bb72ad439bd41f8d0ba384c5b', 'fa0b7dffda7a7c04bec4265d99633cb8'), ('public.geoportal_tec_punto_ubicacion_revisar(text,bigint,text,text,text)', '450f01d67ca644905a223c1e99ca062a', '763c90cacdab105969966721b27f4c98'), ('public.geoportal_tec_punto_ubicaciones(text)', '22930b502a1d1ee412f5288a3bb3c27e', 'dcf5e4a013481f2d0077a9de32a0db72')),
rcam as (
  select c.firma, md5(pg_get_functiondef(to_regprocedure(c.firma))),
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 5b (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 5c (reemplazada)' else 'DISTINTA' end
    from cam c),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when 'cbff4ee6e25826251d90496c833ac3de' then 'CORTE 5b (listo para el 5c)' when 'a5ce1ff8c5659de3b853e30f4d3025e6' then 'CORTE 5c (aplicado)' else 'DISTINTA' end as estado
union all select * from rpc
union all select * from rcam
union all select '1 tabla ' || t, null, case when to_regclass(t) is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
  from unnest(array['redes.ficha_campo_devoluciones', 'tecnica.punto_ubicacion_correcciones']) t
order by 1;
