-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- =====================================================================
select k, v from (
  select 1 as o, '01 campo.reportes tiene «area» (nula = Comercial; solo admite «tecnica») y sigue siendo de solo inserción' as k,
         case when (select is_nullable = 'YES' and column_default like '%geoportal.via_tecnica%' from information_schema.columns where table_schema = 'campo' and table_name = 'reportes' and column_name = 'area')
               and exists (select 1 from pg_constraint where conrelid = 'campo.reportes'::regclass and conname = 'reportes_area_ck')
               and (select count(*) from pg_trigger where tgrelid = 'campo.reportes'::regclass and tgname in ('t_solo_agregar', 't_solo_agregar_trunc') and not tgisinternal) = 2 then 'OK' else 'MAL' end as v
  union all select 2, '02 ningún reporte anterior al corte quedó marcado: todos los que no son de Técnica tienen el área nula',
         case when not exists (select 1 from campo.reportes r where r.area is not null and r.area <> 'tecnica') then 'OK' else 'MAL' end
  union all select 3, '03 las 3 RPC nuevas: security definer, search_path fijo, solo service_role',
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_campo_tec_formulario', 'geoportal_campo_tec_preparar_subida', 'geoportal_campo_tec_crear_reporte') and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 3 then 'OK' else 'MAL' end
  union all select 4, '04 las funciones internas (las 3 nuevas, campo.f_autorizar_reporte y tecnica.f_formularios) no las ejecuta la API',
         case when not exists (select 1 from pg_proc p where p.oid in ('campo.f_tipo_general(text)'::regprocedure, 'campo.f_tecnica_claves(text)'::regprocedure, 'campo.f_tecnica_entrar(text,text)'::regprocedure,
                                 'campo.f_autorizar_reporte(text)'::regprocedure, 'tecnica.f_formularios()'::regprocedure)
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 5, '05 huellas md5 de las 2 reemplazadas, de las 6 nuevas y de la vista',
         case when (select count(*) from (values ('campo.f_autorizar_reporte(text)', '097a21e90766512921f185d213f3c779'), ('tecnica.f_formularios()', 'a20a338b69efbcfbb5e90df54b1cb14d')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 2
               and (select count(*) from (values ('campo.f_tipo_general(text)', '4ede0bf1f2a69982fb033cea893b84e2'), ('campo.f_tecnica_claves(text)', '98c2f200b97968a30d9e2ba521c92d6b'), ('campo.f_tecnica_entrar(text,text)', '0b8a0b83e29192980e9d3f902e05b305'), ('public.geoportal_campo_tec_formulario(text)', 'edaee27220655f13ce9ecc193e42c4b1'), ('public.geoportal_campo_tec_preparar_subida(text,integer,text,text)', '52047247a4d6a68aba4140d3f293dd3d'), ('public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone)', '7281c4bbf3db56fdfc1c11bb42f645ff')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 6
               and md5(pg_get_viewdef('redes.v_reportes_comercial'::regclass, true)) = '825a60fdb3815b1972badfef332c04c0' then 'OK' else 'MAL' end
  union all select 6, '06 Técnica: el dominio admite las 2 claves compartidas y tecnica.f_formularios las lista (9 formularios)',
         case when (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') = 'CHECK ((VALUE = ANY (ARRAY[''entrada''::text, ''salida''::text, ''muestreo''::text, ''danos_fallas''::text, ''mantenimiento''::text, ''uso_quimicos''::text, ''entrada_quimicos''::text, ''anomalia_compartida''::text, ''revision_compartida''::text])))'
               and (select count(*) from tecnica.f_formularios()) = 9
               and (select string_agg(nombre, '|' order by orden) from tecnica.f_formularios() where clave in ('anomalia_compartida', 'revision_compartida')) = 'Reportar anomalía|Revisiones generales' then 'OK' else 'MAL' end
  union all select 7, '07 el catálogo: existe «fuga en acometida» y «caja de medidor dañada» (o ya había uno parecido) y los tipos anteriores siguen todos',
         case when exists (select 1 from campo.tipos_reporte where lower(nombre) like '%fuga%acometida%' or codigo = 'fuga_acometida')
               and exists (select 1 from campo.tipos_reporte where lower(nombre) like '%caja%medidor%da_ad%' or codigo = 'caja_medidor_danada')
               and (select count(*) from campo.tipos_reporte where codigo not in ('fuga_acometida', 'caja_medidor_danada')) >= 26 then 'OK' else 'MAL' end
  union all select 8, '08 la vista del geovisor no lleva contrato, descripción, autor ni fotos, y nadie de la API la lee',
         case when (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'redes' and table_name = 'v_reportes_comercial')
                   = 'codigo,tipo,subtipo,area,con_contrato,estado,registrado_en,lat,lon'
               and not exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol) where has_table_privilege(r.rol, 'redes.v_reportes_comercial', 'select')) then 'OK' else 'MAL' end
  union all select 9, '09 pg-safeupdate: las funciones nuevas y las reemplazadas no llevan DELETE ni UPDATE',
         case when not exists (select 1 from pg_proc p where p.proname in ('f_tipo_general', 'f_tecnica_claves', 'f_tecnica_entrar', 'f_autorizar_reporte', 'f_formularios', 'geoportal_campo_tec_formulario',
                                 'geoportal_campo_tec_preparar_subida', 'geoportal_campo_tec_crear_reporte') and p.pronamespace::regnamespace::text in ('campo', 'tecnica', 'public')
                                and p.prosrc ~* '\m(delete\s+from|update\s+[a-z_.]+\s+set)\M') then 'OK' else 'MAL' end
  union all select 10, 'INFO reportes en campo.reportes: total · de Técnica · en la capa del geovisor · tipos del catálogo',
         (select count(*) || ' · ' || count(*) filter (where area = 'tecnica') from campo.reportes) || ' · ' || (select count(*) from redes.v_reportes_comercial) || ' · ' || (select count(*) from campo.tipos_reporte)
  union all select 11, 'INFO personas de Técnica con «Reportar anomalía» · con «Revisiones generales» (asignados en Personal)',
         (select count(distinct persona) filter (where formulario = 'anomalia_compartida') || ' · ' || count(distinct persona) filter (where formulario = 'revision_compartida') from tecnica.personal_tecnico_eventos)
) t order by o;
