-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: las 2 funciones que se reemplazan «VIVA (sin cambiar)»; las 3 RPC de campo «FIRMA ESPERADA»; lo nuevo «NO EXISTE»; el dominio con 7 claves; la vista «VACÍA (6b)».
-- DESPUÉS: 2 «CORTE 8 (reemplazada)», 6 «NUEVA», columna «EXISTE», dominio con 9 claves, vista «CORTE 8».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió). Las filas «7 …» son informativas: los tipos parecidos a los dos que se agregan.
-- =====================================================================
with cam(firma, antes, despues) as (values {{CAMBIADAS}}),
nue(firma, nueva) as (values {{NUEVAS}})
select '1 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
       case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'VIVA (sin cambiar)'
            when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 8 (reemplazada)' else 'DISTINTA' end as estado
  from cam c
union all select '2 ' || f, md5(pg_get_functiondef(to_regprocedure(f))), case when to_regprocedure(f) is null then 'FALTA' else 'FIRMA ESPERADA' end
  from unnest(array['public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)',
                    'public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'public.geoportal_campo_obtener_formulario(text,boolean)']) f
union all select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
       case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
  from nue n
union all select '4 columna campo.reportes.area', null,
       case when exists (select 1 from information_schema.columns where table_schema = 'campo' and table_name = 'reportes' and column_name = 'area') then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
union all select '5 dominio tecnica.formulario_clave', (select md5(pg_get_constraintdef(c.oid)) from pg_constraint c where c.contypid = to_regtype('tecnica.formulario_clave') and c.conname = 'formulario_clave_ck'),
       case (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = to_regtype('tecnica.formulario_clave') and c.conname = 'formulario_clave_ck')
            when '{{DEF_DOMINIO}}' then '7 CLAVES (sin aplicar)' when '{{DEF_DOMINIO_8}}' then '9 CLAVES (aplicado)' else 'DISTINTA' end
union all select '6 vista redes.v_reportes_comercial', md5(pg_get_viewdef(to_regclass('redes.v_reportes_comercial'), true)),
       case when to_regclass('redes.v_reportes_comercial') is null then 'FALTA' when pg_get_viewdef(to_regclass('redes.v_reportes_comercial'), true) ~* 'where false' then 'VACÍA (6b, sin aplicar)'
            when md5(pg_get_viewdef(to_regclass('redes.v_reportes_comercial'), true)) = '{{MD5_VISTA}}' then 'CORTE 8 (aplicada)' else 'DISTINTA' end
union all select '7 tipos de campo: total · activos', null, (select count(*) || ' · ' || count(*) filter (where activo) from campo.tipos_reporte)
union all select '7 tipo parecido: ' || t.codigo, null, t.nombre || case when t.activo then '' else ' (inactivo)' end
  from campo.tipos_reporte t where lower(t.nombre) like '%fuga%' or lower(t.nombre) like '%caja%' or t.codigo in ('fuga_acometida', 'caja_medidor_danada')
order by 1;
