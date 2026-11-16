-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: las 2 RPC que se reemplazan «CORTE 7a (sin cambiar)»; las 5 funciones nuevas y los 3 objetos «NO EXISTE».
-- DESPUÉS: 2 «CORTE 7c (reemplazada)», 5 «NUEVA» y 3 «EXISTE». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values {{CAMBIADAS}}),
nue(firma, nueva) as (values {{NUEVAS}})
select '1 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
       case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 7a (sin cambiar)'
            when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 7c (reemplazada)' else 'DISTINTA' end as estado
  from cam c
union all select '2 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
       case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
  from nue n
union all select '3 objeto ' || t, null, case when to_regclass(t) is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
  from unnest(array['tecnica.quimico_remision_preparaciones', 'tecnica.quimico_parametro_eventos']) t
union all select '3 columna tecnica.quimico_movimientos.remision_foto', null,
       case when exists (select 1 from information_schema.columns where table_schema = 'tecnica' and table_name = 'quimico_movimientos' and column_name = 'remision_foto') then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
order by 1;
