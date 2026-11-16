-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 4b (listo para el 5a)»; las 4 de permisos «CORTE 4a (sin cambiar)»; la RPC nueva «NO EXISTE»; las 9 que se
-- reemplazan «CORTE 4b (sin cambiar)»; las 3 tablas «NO EXISTE». DESPUÉS: «CORTE 5a (aplicado)», «NUEVA», «CORTE 5a (reemplazada)» y «EXISTE».
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with viv(objeto, md5) as (values {{VIVAS_4A}}),
rviv as (
  select 'permisos public.' || v.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = v.md5 then 'CORTE 4a (sin cambiar)' else 'DISTINTA' end as estado
    from viv v left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = v.objeto group by v.objeto, v.md5),
esp(objeto, nueva) as (values {{RPC_NUEVAS}}),
rpc as (
  select 'public.' || e.objeto, max(md5(pg_get_functiondef(p.oid))),
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(firma, antes, despues) as (values {{CAMBIADAS}}),
rcam as (
  select c.firma, md5(pg_get_functiondef(to_regprocedure(c.firma))),
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 4b (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 5a (reemplazada)' else 'DISTINTA' end
    from cam c),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_CORTE_4B}}' then 'CORTE 4b (listo para el 5a)' when '{{MD5_CORTE_5A}}' then 'CORTE 5a (aplicado)' else 'DISTINTA' end as estado
union all select * from rviv
union all select * from rpc
union all select * from rcam
union all select '1 tabla ' || t, null, case when to_regclass(t) is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
  from unnest(array['tecnica.puntos_ubicacion', 'tecnica.punto_eventos', 'redes.formularios_distribucion']) t
order by 1;
