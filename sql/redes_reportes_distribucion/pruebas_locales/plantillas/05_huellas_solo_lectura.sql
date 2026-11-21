-- =====================================================================
-- TÉCNICA · FASE 1 · DESCARGAS DE DISTRIBUCIÓN · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «AVISO POR CONTRATO (lista para las descargas)», las {{N_NUEVAS}} nuevas «NO EXISTE» y las tablas «NO EXISTEN».
-- DESPUÉS: «DESCARGAS DE DISTRIBUCIÓN (aplicado)», las {{N_NUEVAS}} «NUEVA» y las tablas «EXISTEN». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise.
-- =====================================================================
with nue(firma, nueva) as (values {{NUEVAS}}),
pub(firma, publicada) as (values {{PUBLICADAS}}),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_BASE}}' then 'AVISO POR CONTRATO (lista para las descargas)' when '{{MD5_DIST}}' then 'DESCARGAS DE DISTRIBUCIÓN (aplicado)' else 'DISTINTA' end as estado
union all select '1 las ' || count(*) || ' funciones nuevas', null,
       case when count(*) filter (where to_regprocedure(n.firma) is null) = count(*) then 'NO EXISTE (sin aplicar)'
            when count(*) filter (where md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva) = count(*) then 'NUEVA (aplicada)'
            else 'DISTINTA: ' || coalesce(string_agg(n.firma, ', ') filter (where to_regprocedure(n.firma) is null or md5(pg_get_functiondef(to_regprocedure(n.firma))) <> n.nueva), '') end
  from nue n
union all select '2 ' || p.firma || ' (no se toca)', md5(pg_get_functiondef(to_regprocedure(p.firma))),
       case when to_regprocedure(p.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(p.firma))) = p.publicada then 'LA PUBLICADA' else 'DISTINTA' end from pub p
union all select '3 tablas nuevas (reporte_descargas, reporte_descarga_cierres)', null,
       case when to_regclass('redes.reporte_descargas') is null and to_regclass('redes.reporte_descarga_cierres') is null then 'NO EXISTEN (sin aplicar)'
            when to_regclass('redes.reporte_descargas') is not null and to_regclass('redes.reporte_descarga_cierres') is not null then 'EXISTEN (aplicado)' else 'A MEDIAS' end
union all select '4 INFO datos: LEV · cierres de válvula · eventos · 116 · bot · sensibles · activos · sectores', null,
       (select count(*) from redes.levantar_puntos) || ' · ' || (select count(*) from redes.valvula_maniobras where tipo = 'cerrar') || ' · ' || (select count(*) from redes.eventos_suspension)
       || ' · ' || (select count(*) from redes.l116_vigente) || ' · ' || (select count(*) from redes.reportes_externos) || ' · ' || (select count(*) from redes.usuarios_sensibles)
       || ' · ' || (select count(*) from redes.activo_vigente_mat) || ' · ' || (select count(*) from redes.activo_vigente_mat where prefijo = 'SEC' and not retirado and not oculto)
order by 1;
