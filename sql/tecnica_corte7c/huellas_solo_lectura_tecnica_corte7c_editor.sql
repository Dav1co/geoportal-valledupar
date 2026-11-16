-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: las 2 RPC que se reemplazan «CORTE 7a (sin cambiar)»; las 5 funciones nuevas y los 3 objetos «NO EXISTE».
-- DESPUÉS: 2 «CORTE 7c (reemplazada)», 5 «NUEVA» y 3 «EXISTE». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values ('public.geoportal_tec_quimico_entrada(text,jsonb,text)', '9daf6b0ef659b44d30a9260b003e0a31', 'b98b131b312d3a370d96c288cfb565b0'), ('public.geoportal_tec_quimico_historial(text,text)', '9112d90a773971bacfb9d69310b2da89', '2a02dcc13b3323d3f7b43778d3a8fdac')),
nue(firma, nueva) as (values ('tecnica.f_remision_subida(text,text)', '01786c84892a2997a06a4cc70447dcc2'), ('tecnica.f_qparam_editable(text)', '8dd655218813ed42f4e573afc96197dd'), ('public.geoportal_tec_quimico_remision_preparar(text)', '0090d5936af9474875861efb60f7c6cb'), ('public.geoportal_tec_quimico_parametros(text)', '38fa1497fc33537e0f2b7ba682a10684'), ('public.geoportal_tec_quimico_parametro_fijar(text,text,numeric,text)', '73a15eef0783e83d4aeb81f902e77f31'))
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
