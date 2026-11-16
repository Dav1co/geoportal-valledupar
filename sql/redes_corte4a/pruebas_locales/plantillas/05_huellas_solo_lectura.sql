-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 3b (listo para el 4a)»; las 4 funciones de permisos «14-nov (sin cambiar)»; las 7 RPC nuevas «NO EXISTE»;
-- las 10 que se reemplazan «CORTE 3b (sin cambiar)». DESPUÉS: «CORTE 4a (aplicado)», «CORTE 4a (con dashboard_redes)», «NUEVA» y «CORTE 4a (reemplazada)».
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with viv(objeto, antes, despues) as (values {{VIVAS}}),
rviv as (
  select 'permisos public.' || v.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = v.antes then '14-nov (sin cambiar)'
              when max(md5(pg_get_functiondef(p.oid))) = v.despues then 'CORTE 4a (con dashboard_redes)' else 'DISTINTA' end as estado
    from viv v left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = v.objeto group by v.objeto, v.antes, v.despues),
esp(objeto, nueva) as (values {{RPC_NUEVAS}}),
rpc as (
  select 'public.' || e.objeto, max(md5(pg_get_functiondef(p.oid))),
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(objeto, antes, despues) as (values {{RPC_CAMBIADAS}}),
rpc2 as (
  select 'public.' || c.objeto, max(md5(pg_get_functiondef(p.oid))),
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = c.antes then 'CORTE 3b (sin cambiar)'
              when max(md5(pg_get_functiondef(p.oid))) = c.despues then 'CORTE 4a (reemplazada)' else 'DISTINTA' end
    from cam c left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = c.objeto group by c.objeto, c.antes, c.despues),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_CORTE_3B}}' then 'CORTE 3b (listo para el 4a)' when '{{MD5_CORTE_4A}}' then 'CORTE 4a (aplicado)' else 'DISTINTA' end as estado
union all select * from rviv
union all select * from rpc
union all select * from rpc2
union all select '1 columna ver_dashboard_redes', null, case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_lista_blanca'
       and column_name = 'ver_dashboard_redes') then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
union all select '1 columna redes.danos.sector_num', null, case when exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'danos'
       and column_name = 'sector_num') then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
order by 1;
