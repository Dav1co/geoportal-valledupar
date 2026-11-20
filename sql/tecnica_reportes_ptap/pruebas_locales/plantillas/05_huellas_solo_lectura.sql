-- =====================================================================
-- TÉCNICA · FASE 1 · REPORTES DEL PTAP · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «PUBLICADA» (b474fbbe… o, si ya se aplicaron las descargas de Distribución, la de ellas), las {{N_NUEVAS}} nuevas «NO EXISTE»,
--        las tablas «NO EXISTEN» y «lo que se lee» «ESTÁ».
-- DESPUÉS: las {{N_NUEVAS}} «NUEVA» y las tablas «EXISTEN». Cualquier «DISTINTA», «FALTA» o «A MEDIAS»: no aplique nada y avise.
-- La fila «huella de técnica» es INFORMATIVA: el esquema tecnica no tiene una huella de conjunto publicada; anótela antes y después (este paquete la cambia).
-- =====================================================================
with nue(firma, nueva) as (values {{NUEVAS}}),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_BASE}}' then 'PUBLICADA (aviso por contrato)' when '{{MD5_REDES_DESPUES}}' then 'PUBLICADA (con las descargas de Distribución)' else 'DISTINTA' end as estado
union all select '1 las ' || count(*) || ' funciones nuevas', null,
       case when count(*) filter (where to_regprocedure(n.firma) is null) = count(*) then 'NO EXISTE (sin aplicar)'
            when count(*) filter (where md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva) = count(*) then 'NUEVA (aplicada)'
            else 'DISTINTA: ' || coalesce(string_agg(n.firma, ', ') filter (where to_regprocedure(n.firma) is null or md5(pg_get_functiondef(to_regprocedure(n.firma))) <> n.nueva), '') end
  from nue n
union all select '2 lo que se lee (registros de planta, revisiones, dosis, químicos, eventos de planta y permisos)', null,
       case when to_regclass('tecnica.v_registros_estado') is not null and to_regprocedure('tecnica.f_referencia_vigente(bigint,bigint,bigint)') is not null and to_regclass('tecnica.revisiones_fuera_referencia') is not null and to_regclass('tecnica.v_uso_quimicos_estado') is not null
             and to_regclass('tecnica.quimico_movimientos') is not null and to_regclass('redes.v_evento_suspension') is not null and to_regprocedure('tecnica.f_autorizar_supervision(text)') is not null
             and to_regprocedure('redes.f_evento_reportes(bigint)') is not null then 'ESTÁ' else 'FALTA' end
union all select '3 tablas nuevas (tecnica.reporte_descargas, tecnica.reporte_descarga_cierres)', null,
       case when to_regclass('tecnica.reporte_descargas') is null and to_regclass('tecnica.reporte_descarga_cierres') is null then 'NO EXISTEN (sin aplicar)'
            when to_regclass('tecnica.reporte_descargas') is not null and to_regclass('tecnica.reporte_descarga_cierres') is not null then 'EXISTEN (aplicado)' else 'A MEDIAS' end
union all select '4 INFO huella de técnica (esquema tecnica y geoportal_tec_*; anótela)',
       (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
         where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))), 'INFORMATIVA'
union all select '5 INFO datos: registros de planta · envíos · fuera de referencia sin excluir · movimientos de químicos · eventos de planta', null,
       (select count(*) from tecnica.registros) || ' · ' || (select count(distinct lote_id) from tecnica.registros) || ' · '
       || (select count(*) from tecnica.v_registros_detalle where fuera_de_rango is not null and not excluido and fecha_muestra >= current_date - 365) || ' · '
       || (select count(*) from tecnica.quimico_movimientos) || ' · ' || (select count(*) from redes.eventos_suspension where planta_id is not null)
order by 1;
