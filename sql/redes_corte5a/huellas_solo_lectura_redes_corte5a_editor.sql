-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 4b (listo para el 5a)»; las 4 de permisos «CORTE 4a (sin cambiar)»; la RPC nueva «NO EXISTE»; las 9 que se
-- reemplazan «CORTE 4b (sin cambiar)»; las 3 tablas «NO EXISTE». DESPUÉS: «CORTE 5a (aplicado)», «NUEVA», «CORTE 5a (reemplazada)» y «EXISTE».
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with viv(objeto, md5) as (values ('geoportal_puede', '32f174a55b95788d3f8187b507303c2f'), ('geoportal_mis_permisos', '83166fe17be58da67bbdedaae429bedb'), ('geoportal_admin_permisos', 'e5a90103b4a83440fd826f03266b7245'), ('geoportal_admin_listar', 'd7311a32ea03cccd6c83691e63ba10bc')),
rviv as (
  select 'permisos public.' || v.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = v.md5 then 'CORTE 4a (sin cambiar)' else 'DISTINTA' end as estado
    from viv v left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = v.objeto group by v.objeto, v.md5),
esp(objeto, nueva) as (values ('geoportal_redes_personal_formulario', 'ab592b70aaba94ee58e6649d49476041')),
rpc as (
  select 'public.' || e.objeto, max(md5(pg_get_functiondef(p.oid))),
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(firma, antes, despues) as (values ('redes.f_preparar_candidatos(bigint)', '7e38935a5aef86f90099f5d09b87bb31', '21eb19b24d8ec93bf94871c619210493'), ('redes.f_resumen(bigint)', '8f9292cc965652cffa4b342542c12412', '187ab77324b78a81d8ddd16edbacddb8'), ('redes.f_publicar(bigint,text,text)', 'e9fa20c6271577c204db14b1c46cb6c1', '1ac4ba2d9b48502c50397307386545fa'), ('redes.f_revertir(text,text,text)', 'e872990874a708762ba77f6db5debfec', 'cdc66d10afdca6bf055d130b896c8c7f'), ('public.geoportal_redes_formulario_intervencion(text)', '70d3ece24b27766dbc2c38e3dfc607ea', 'e4144f1dbbe185ff6474d0bbf574a819'), ('public.geoportal_redes_crear_intervencion(text,uuid,jsonb,text)', 'a818d3622ae5877867f2ed45cf44d0f7', '52cba7c207f3640a279bd16c2683e14d'), ('public.geoportal_redes_cuadrilla_fijar(text,bigint,text,boolean,text)', '16ac4ed9bb95dee57f04b289aa3f4899', '5a729ccc8dac79b45a64b9222122480c'), ('public.geoportal_redes_catalogo(text)', 'c36c45abfbbc5941c27464aada29a5d1', '9d25d079d9249cac3dd32f079b6cd027'), ('public.geoportal_redes_personal(text,text,text)', '43882432c360917c3ebcaf610c98d2e5', '33d483212bc944112cb4ca9409686545')),
rcam as (
  select c.firma, md5(pg_get_functiondef(to_regprocedure(c.firma))),
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 4b (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 5a (reemplazada)' else 'DISTINTA' end
    from cam c),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '55668dddf263065b5eb90aeb3001a3b7' then 'CORTE 4b (listo para el 5a)' when '5d104bb916ca0b055659c1b14902f519' then 'CORTE 5a (aplicado)' else 'DISTINTA' end as estado
union all select * from rviv
union all select * from rpc
union all select * from rcam
union all select '1 tabla ' || t, null, case when to_regclass(t) is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
  from unnest(array['tecnica.puntos_ubicacion', 'tecnica.punto_eventos', 'redes.formularios_distribucion']) t
order by 1;
