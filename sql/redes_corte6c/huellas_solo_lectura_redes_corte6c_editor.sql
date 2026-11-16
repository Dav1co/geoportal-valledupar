-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 6b + hotfix (listo para el 6c)»; las 3 reemplazadas «CORTE 6b (sin cambiar)»; las 2 funciones nuevas
-- «NO EXISTE»; la copia derivada (2 tablas y 2 funciones) «EXISTE»; los 4 índices de Comercial «EXISTE».
-- DESPUÉS: «CORTE 6c (aplicado)», 3 «CORTE 6c (reemplazada)», 2 «NUEVA», 4 «RETIRADO» y los 4 índices «EXISTE».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values ('public.geoportal_redes_geovisor(text)', '034c6ad129c2c34b41541dc9cabfd93c', '78fb8266415de46937fe1af18bfba7e2'), ('public.geoportal_redes_geovisor_mvt_contratos(text,integer,integer,integer)', '6e5deffd58bb9d5e8c27739c73adae67', '88c6f29e74b29d90429258d2b5902ec9'), ('public.geoportal_redes_contrato_tarjeta(text,text,text)', '1af144caaebfe57e14c71d41c3e4b520', '4c0fc2ff5c97b6a203d929b28e452cfa')),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 6b (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 6c (reemplazada)' else 'DISTINTA' end as estado
    from cam c),
nue(firma, nueva) as (values ('redes.f_contrato_uso(text,text)', '7510f2f3b17efa5a49738b4b709dc720'), ('redes.f_funciones_sin_where()', '56251d0248ec94be8e385f4c6c4b2070')),
rnue as (
  select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '8113af17c6bd862d62a6cbc4bc4cba1f' then 'CORTE 6b + hotfix (listo para el 6c)' when '2c2658002d114d755f19a7b5f5dfe542' then 'CORTE 6c (aplicado)'
            when 'fca28bf695d1fcfa153f1113ce821528' then 'CORTE 6b SIN el hotfix: FALTA aplicar el hotfix' else 'DISTINTA' end as estado
union all select * from rcam
union all select * from rnue
union all select '4 copia derivada ' || t, null, case when to_regclass(t) is not null then 'EXISTE (sin aplicar)' else 'RETIRADO (aplicado)' end
  from unnest(array['redes.contratos_capa', 'redes.contratos_capa_estado']) t
union all select '4 copia derivada ' || t, null, case when to_regprocedure(t) is not null then 'EXISTE (sin aplicar)' else 'RETIRADO (aplicado)' end
  from unnest(array['redes.f_refrescar_contratos_capa()', 'redes.f_contratos_capa_al_dia()']) t
union all select '5 índice GiST de catastro_valledupar.geom',
       (select string_agg(i.relname, ', ') from pg_index x join pg_class i on i.oid = x.indexrelid join pg_am am on am.oid = i.relam
         where x.indrelid = to_regclass('public.catastro_valledupar') and am.amname = 'gist' and pg_get_indexdef(i.oid) ~ '\(geom\)'),
       case when exists (select 1 from pg_index x join pg_class i on i.oid = x.indexrelid join pg_am am on am.oid = i.relam
                          where x.indrelid = to_regclass('public.catastro_valledupar') and am.amname = 'gist' and pg_get_indexdef(i.oid) ~ '\(geom\)') then 'EXISTE' else 'FALTA' end
union all select '5 índice de catastro_valledupar por cod_usuario',
       (select string_agg(x.indexrelid::regclass::text, ', ') from pg_index x where x.indrelid = to_regclass('public.catastro_valledupar') and x.indisvalid and x.indpred is null
          and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(cod_usuario( text_pattern_ops)?[,)]'),
       case when exists (select 1 from pg_index x where x.indrelid = to_regclass('public.catastro_valledupar') and x.indisvalid and x.indpred is null
                          and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(cod_usuario( text_pattern_ops)?[,)]') then 'EXISTE' else 'FALTA' end
union all select '5 índice de cartera_suscripcion por contrato',
       (select string_agg(x.indexrelid::regclass::text, ', ') from pg_index x where x.indrelid = to_regclass('public.cartera_suscripcion') and x.indisvalid and x.indpred is null
          and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(contrato[,)]'),
       case when exists (select 1 from pg_index x where x.indrelid = to_regclass('public.cartera_suscripcion') and x.indisvalid and x.indpred is null
                          and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(contrato[,)]') then 'EXISTE' else 'FALTA' end
union all select '5 índice de bi_interno.ficha_contrato por contrato',
       (select string_agg(x.indexrelid::regclass::text, ', ') from pg_index x where x.indrelid = to_regclass('bi_interno.ficha_contrato') and x.indisvalid
          and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(contrato[,)]'),
       case when exists (select 1 from pg_index x where x.indrelid = to_regclass('bi_interno.ficha_contrato') and x.indisvalid
                          and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(contrato[,)]') then 'EXISTE' else 'FALTA' end
order by 1;
