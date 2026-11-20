-- =====================================================================
-- TÉCNICA · FASE 1 · REPORTES DEL PTAP · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «PUBLICADA» (b474fbbe… o, si ya se aplicaron las descargas de Distribución, la de ellas), las 22 nuevas «NO EXISTE»,
--        las tablas «NO EXISTEN» y «lo que se lee» «ESTÁ».
-- DESPUÉS: las 22 «NUEVA» y las tablas «EXISTEN». Cualquier «DISTINTA», «FALTA» o «A MEDIAS»: no aplique nada y avise.
-- La fila «huella de técnica» es INFORMATIVA: el esquema tecnica no tiene una huella de conjunto publicada; anótela antes y después (este paquete la cambia).
-- =====================================================================
with nue(firma, nueva) as (values ('geoportal_tec_reporte_cerrar(text,bigint,integer,text,text)', '2f76c0632a3bd6c7fc8ba054ef2ce3d0'), ('geoportal_tec_reporte_iniciar(text,text,jsonb,text,boolean,text)', '4c5c6acb1b81b545cbbc1865f45ac860'), ('geoportal_tec_reporte_pagina(text,bigint,text,integer)', '818a99308a99c880739ba08299cb0bce'), ('geoportal_tec_reporte_remision_foto(text,bigint,text)', 'd0ed2351fb3dfd2ab289e0688479e921'), ('tecnica.f_rep_catalogo()', '497bb7bd8d8867cd35dc362ef8ae4f94'), ('tecnica.f_rep_col(text,text,text,text,integer)', '03302ef51c4248764d7ba5b483b2d459'), ('tecnica.f_rep_cols_variables(text,date,date)', 'd46ff6aeacd556fb5fa5bf0c24eec8f7'), ('tecnica.f_rep_columnas(text,jsonb)', '1cff00cc20c2f5414c3ea93e60471cfd'), ('tecnica.f_rep_envios(text,jsonb,boolean,timestamp with time zone,text,integer,jsonb,boolean)', '5adfbcb96a9ae77e2e2e61456a9e72ec'), ('tecnica.f_rep_envios_llaves(text,jsonb,boolean,timestamp with time zone,text,integer)', '9f8573b0fb8aeb4a99be41b1fe3f5cb0'), ('tecnica.f_rep_envios_pagina(text,jsonb,boolean,timestamp with time zone,text,integer,jsonb,date)', '27b983d1f6c6408322d5e761cecd671b'), ('tecnica.f_rep_eventos_planta(jsonb,boolean,timestamp with time zone,text,integer)', '1375fd35b4677bde85ed913ce39560e3'), ('tecnica.f_rep_filas(text,jsonb,boolean,timestamp with time zone,text,integer,jsonb,boolean)', '3322cf0a784a1822d1b48b34eb96d642'), ('tecnica.f_rep_filtros(text,jsonb)', 'a95c2f1e25415fbfd6b660b766da220c'), ('tecnica.f_rep_fuera_referencia(jsonb,boolean,timestamp with time zone,text,integer)', '7824ffb564ac569503870bba371a6bc0'), ('tecnica.f_rep_kardex(jsonb,timestamp with time zone,text,integer)', 'd9ef46b5af9ee5ac7ccfe308144f0d22'), ('tecnica.f_rep_leame(text,jsonb,boolean,text,timestamp with time zone)', '103378e27fc97a5124a58365b6876e0a'), ('tecnica.f_rep_max_filas()', '570dfa334c7e4cb8808dfebbb765bd14'), ('tecnica.f_rep_max_pagina()', '2c2200c266a01dd2ee191c24af93df53'), ('tecnica.f_rep_quimicos(text,jsonb,timestamp with time zone,text,integer)', 'd17b765a1230efba574b890d5dbfd6a8'), ('tecnica.f_rep_ts(timestamp with time zone)', '02a1cb1f4f2ef2d501b132eadaffeb0e'), ('tecnica.f_rep_valores(text[],jsonb,timestamp with time zone,date,bigint,date,boolean)', 'fb4317249f97dc75871c5c6be4019164')),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when 'b474fbbe3e0f7a3a7e6dbc04c53e02e7' then 'PUBLICADA (aviso por contrato)' when 'ef5fc9df2a7ba17df5797bc2971d2f04' then 'PUBLICADA (con las descargas de Distribución)' else 'DISTINTA' end as estado
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
