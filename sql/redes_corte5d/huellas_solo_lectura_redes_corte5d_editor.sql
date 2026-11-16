-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 9a-bis (listo para el 5d)»; las 6 reemplazadas «CORTE 9a-bis (sin cambiar)»; las 7 nuevas «NO EXISTE»;
--        «dominio de formularios» dice «CON LAS CLAVES DEL CORTE 8»; la capa pqr_116 «PREPARADA»; el catastro «CON CONTRATO Y PUNTO».
-- DESPUÉS: «CORTE 5d (aplicado)», 6 «CORTE 5d (reemplazada)», 7 «NUEVA» y la capa pqr_116 «ACTIVA (5d)».
-- Cualquier «DISTINTA», «FALTA» o «SIN LAS CLAVES»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values ('redes.f_lote(bigint,jsonb)', '4a2f201ef3383dd7398fec5bf48584f4', 'c6eea76f5124e903f3d79308f5747580'), ('redes.f_resumen(bigint)', '94f7e7b146a554d882a481a9f0973027', 'dc256f8a36acb8ec4a1abda19179e321'), ('redes.f_publicar(bigint,text,text)', '1ac4ba2d9b48502c50397307386545fa', 'f204bc42b727c1ab284220dee2c6c9c0'), ('redes.f_revertir(text,text,text)', 'cdc66d10afdca6bf055d130b896c8c7f', 'dbe18e81f4a9605f7659258f6138a8e6'), ('public.geoportal_redes_cargue_capas(text)', '039d0c5240a323af540bc34e448a6c25', 'fcd4f1cb91c9cef0cf2d00c1f4d4fe32'), ('public.geoportal_redes_geovisor_capa(text,text,date,date)', '447cce7bc84f681d07cd916bbd7b9eb4', 'a79ba32d0d1c8f6c243928e370d217d3')),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 9a-bis (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 5d (reemplazada)' else 'DISTINTA' end as estado
    from cam c),
nue(firma, nueva) as (values ('redes.f_l116_atributos(jsonb)', '5ace157540bfed79f16a76f19c81bfcc'), ('redes.f_l116_fecha(text)', '256e9e6eebbd5d5cca1c51bedf2d4acd'), ('redes.f_l116_candidatos(bigint)', 'db66e19131c4f51b3988ddd23a1aae47'), ('redes.f_resumen_l116(bigint)', '2ad145d79e92d1e33acc0e90592b3ed7'), ('redes.f_publicar_l116(bigint,text,text)', '1d70c1fe36186cf498504898e5098b64'), ('redes.f_revertir_l116(text,text)', '976be08e317cbe396aca0b92552fe80f'), ('public.geoportal_redes_l116_vincular_dano(text,bigint,text,text,text)', 'a28ba4108c8ad8fd2d2e052b0d353dbb')),
rnue as (
  select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '814eac39ac5deae2943751b8c190f969' then 'CORTE 9a-bis (listo para el 5d)' when '5fd6d00efdaa1a798e2628a2cde23c61' then 'CORTE 5d (aplicado)' else 'DISTINTA' end as estado
union all select * from rcam
union all select * from rnue
union all select '4 dominio de formularios de Técnica', null,
       case when (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = to_regtype('tecnica.formulario_clave') and c.conname = 'formulario_clave_ck')
                 like '%''anomalia_compartida''%''revision_compartida''%' then 'CON LAS CLAVES DEL CORTE 8' else 'SIN LAS CLAVES DEL CORTE 8 (publique antes el 8)' end
union all select '5 capa pqr_116 del geovisor', null,
       (select case when fuente = 'preparada' then 'PREPARADA (sin aplicar)' when fuente = 'geojson' and estado = 'activa' then 'ACTIVA (5d)' else 'DISTINTA' end
          from redes.geovisor_capas where codigo = 'pqr_116')
union all select '6 public.catastro_valledupar', null,
       case when (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catastro_valledupar'
                   and column_name in ('cod_usuario', 'geom')) = 2 then 'CON CONTRATO Y PUNTO' else 'FALTA ALGUNA COLUMNA' end
order by 1;
