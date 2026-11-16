-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 9a (listo para el 9a-bis)»; las 14 reemplazadas «CORTE 9a (sin cambiar)»; las 7 nuevas «NO EXISTE»;
--        los 4 índices «EXISTE».
-- DESPUÉS: «CORTE 9a-bis (aplicado)», 14 «CORTE 9a-bis (reemplazada)», 7 «NUEVA» y los 4 índices «EXISTE».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values ('redes.f_ficha(bigint,text)', '5fda646e3d5577f06f3375162730ba80', '02f80b8677c84b8a9d2e3a21141da695'), ('public.geoportal_redes_tramo_nodos(text,text)', 'ee1795310c54c44b088dd644bb263f09', '3fccc4ad74d0375936f31abf30499fe9'), ('public.geoportal_redes_nodo_crear_activo(text,bigint,text,text,text,text)', '44ad4d3d307814ade4b1b0c14cd8f46a', 'a419c44a32af2d793c941c46cc2d4a53'), ('public.geoportal_redes_nodo_preliminar(text,bigint)', 'f871d0367f33d00d411aa02279c4a605', 'bdc48ca0996c21288c4588855d77fe0c'), ('public.geoportal_redes_nodo_clasificar(text,bigint,text,text)', '84541f4efb3b5347937299531c4f9ddc', '989ccc3191317c17d6d523156a74b009'), ('public.geoportal_redes_nodos_por_clasificar(text,text,bigint,integer)', 'e063594fb8d6b3565330297292fdc4ce', 'ff869315491308180071dba3a9608e5b'), ('redes.f_pm_sugerencia(text,text,text,text)', '0e66cbaea934858c0a9c041ef3671b42', '4ba75667ca567f4ff62bcd35e3e6ed60'), ('public.geoportal_redes_danos(text,text,integer)', '50fe7e4336e4c39eaf94e852166bd8ff', '8a76f015aace5d2b51b74fd7411d191e'), ('public.geoportal_redes_intervenciones(text,text,integer)', 'e35feec21442612a90531b96826af125', 'ee6d1e0f784870673b3789e92e1e30ac'), ('public.geoportal_redes_contrato_tarjeta(text,text,text)', '7d7598af58b4a1724159531cbf9e787b', '9b49d7546cd9092cd8e54f3cf9edfd90'), ('public.geoportal_redes_referencia(text,text,text)', '93531b8b99f1fe869d1e7c4cfd3989cb', '50abc61c89fd96a961535c91a7a3d858'), ('public.geoportal_redes_mi_perfil(text)', '63f796c3777a4b46cebc82c08d1c81bd', '5cca0e645a5e106529382ed51e1519e9'), ('public.geoportal_redes_crear_dano(text,uuid,jsonb,text)', 'e7cac815fb0ae796fff42ade0f39419c', 'f6578d1011d2ccb8431881ab576a4a6b'), ('public.geoportal_redes_reporte_convertir(text,uuid,jsonb)', 'e98e2cfea5ddab54be11ee9b7ba93681', 'c51e28695635e028403f0c85c7ded5f9')),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 9a (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 9a-bis (reemplazada)' else 'DISTINTA' end as estado
    from cam c),
nue(firma, nueva) as (values ('redes.f_nodo_visible_id(bigint)', '27595e1f4a61b6dc9f6e4c22c56f660b'), ('redes.f_nodo_de_activo(bigint)', '26712634417f839dca7a5f54cfd1a3e6'), ('redes.f_tramos_de_nodo(bigint)', '80a2bc06e0cc217a4661f294bdbcc676'), ('redes.f_sector_en(numeric,numeric)', '1c5ee3d6e546d98829da333c44726fa7'), ('redes.f_operador_redes(text)', 'bded76df80afb3cda7ba97be91f7341e'), ('public.geoportal_redes_sector_en(text,numeric,numeric)', 'c41099b5b868b9ce8b58a51a4c98aa28'), ('public.geoportal_redes_nodos_clasificar_grupo(text,text,text,text)', '48f999ac9d51e2fdc327a1d87515c161')),
rnue as (
  select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '4a46069fc3c71c305c49bafd764f316e' then 'CORTE 9a (listo para el 9a-bis)' when '814eac39ac5deae2943751b8c190f969' then 'CORTE 9a-bis (aplicado)' else 'DISTINTA' end as estado
union all select * from rcam
union all select * from rnue
union all select '4 índice ' || i, null, case when exists (select 1 from pg_indexes where schemaname = 'redes' and indexname = i) then 'EXISTE' else 'FALTA' end
  from unnest(array['ix_nodos_llave', 'ix_nodos_activo', 'ix_tn_ini', 'ix_tn_fin']) i
order by 1;
