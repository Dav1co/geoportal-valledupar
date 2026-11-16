-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 4a (listo para el 4b)»; las 4 funciones de permisos «CORTE 4a (sin cambiar)»; las 12 RPC nuevas
-- «NO EXISTE»; las 2 tablas nuevas «NO EXISTE». DESPUÉS: «CORTE 4b (aplicado)», las 4 de permisos igual, «NUEVA» y «EXISTE».
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with viv(objeto, md5) as (values ('geoportal_puede', '32f174a55b95788d3f8187b507303c2f'), ('geoportal_mis_permisos', '83166fe17be58da67bbdedaae429bedb'), ('geoportal_admin_permisos', 'e5a90103b4a83440fd826f03266b7245'), ('geoportal_admin_listar', 'd7311a32ea03cccd6c83691e63ba10bc')),
rviv as (
  select 'permisos public.' || v.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = v.md5 then 'CORTE 4a (sin cambiar)' else 'DISTINTA' end as estado
    from viv v left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = v.objeto group by v.objeto, v.md5),
esp(objeto, nueva) as (values ('geoportal_redes_alias_historial', '479953c39cf9137dcb226b5d6f8c74a3'), ('geoportal_redes_catalogo', 'c36c45abfbbc5941c27464aada29a5d1'), ('geoportal_redes_cuadrilla_fijar', '16ac4ed9bb95dee57f04b289aa3f4899'), ('geoportal_redes_descarga', '6a45b63d76ee2e96d68439a14f238c1f'), ('geoportal_redes_graficas', '735df0b9976ae50ed9c8a60f413f2744'), ('geoportal_redes_nodo_crear_activo', '44ad4d3d307814ade4b1b0c14cd8f46a'), ('geoportal_redes_nodos_por_clasificar', '9d57944786b8bfd2fe8790034c2cd90a'), ('geoportal_redes_parametro_fijar', '90793e6a9deede3f1484cf13fb77ee2a'), ('geoportal_redes_parametros', '6d37a259b5b5171a0449a5807fd39b5f'), ('geoportal_redes_personal', '43882432c360917c3ebcaf610c98d2e5'), ('geoportal_redes_personal_fijar', 'c946cafeaa3ac93d7e5d681aa72bb653'), ('geoportal_redes_personal_historial', '8e438f52d628d5b01d35ff67b31da7ae')),
rpc as (
  select 'public.' || e.objeto, max(md5(pg_get_functiondef(p.oid))),
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '1a2be013019c9a59f1c1e0f2241661f0' then 'CORTE 4a (listo para el 4b)' when '55668dddf263065b5eb90aeb3001a3b7' then 'CORTE 4b (aplicado)' else 'DISTINTA' end as estado
union all select * from rviv
union all select * from rpc
union all select '1 tabla tecnica.personal_ficha_eventos', null, case when to_regclass('tecnica.personal_ficha_eventos') is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
union all select '1 tabla redes.cuadrillas', null, case when to_regclass('redes.cuadrillas') is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
order by 1;
