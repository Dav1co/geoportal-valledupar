-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 5d (listo para el 10)»; las 4 reemplazadas «CORTE 5d (sin cambiar)»; las 4 nuevas «NO EXISTE»;
--        «tablas de referencia del 9a» dice «ESTÁN»; «tablas de la valoración» dice «NO EXISTEN (sin aplicar)».
-- DESPUÉS: «CORTE 10 (aplicado)», 4 «CORTE 10 (reemplazada)», 4 «NUEVA» y «tablas de la valoración» «EXISTEN (10)».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values ('redes.f_ficha(bigint,text)', '02f80b8677c84b8a9d2e3a21141da695', 'cf4791cf96d0b9852fcfa78bb4b25622'), ('redes.f_param_entero(text)', '4d5a8a342e1cd5a523f85aae3e0d90d8', 'b6218d0d4d4e8b343116b99fc35bc0ea'), ('public.geoportal_redes_geovisor_mvt(text,integer,integer,integer)', '33d3cce77bff2de11cac3de6261cd274', '017d8993f9e9677c881f5d7a4763a06a'), ('public.geoportal_redes_geovisor(text)', '1213eae6331a46e90fe23129c96bb32e', 'f9d408248906b538278a474ca2ab92af')),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 5d (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 10 (reemplazada)' else 'DISTINTA' end as estado
    from cam c),
nue(firma, nueva) as (values ('redes.f_val_hoja_alc()', '12f0e8528d072329237d2487b7e0225a'), ('redes.f_val_prefijos()', '96809e8a00089c8142dfc1c1a6b7e7a2'), ('redes.f_ficha_regulatorio(bigint,text)', '4260a4611f540b87566ee145729e0737'), ('public.geoportal_redes_valoracion(text)', 'ec88cca4eea304ad4310015c2a386b4a')),
rnue as (
  select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '5fd6d00efdaa1a798e2628a2cde23c61' then 'CORTE 5d (listo para el 10)' when 'aad5952c27e13cc3ad45623279ba7085' then 'CORTE 10 (aplicado)' else 'DISTINTA' end as estado
union all select * from rcam
union all select * from rnue
union all select '4 tablas de referencia del 9a (ref_cargas, pm_valvulas)', null,
       case when to_regclass('redes.ref_cargas') is not null and to_regclass('redes.pm_valvulas') is not null then 'ESTÁN' else 'FALTA' end
union all select '5 tablas de la valoración (val_hojas, val_filas, val_amarre)', null,
       case (to_regclass('redes.val_hojas') is not null)::int + (to_regclass('redes.val_filas') is not null)::int + (to_regclass('redes.val_amarre') is not null)::int
         when 0 then 'NO EXISTEN (sin aplicar)' when 3 then 'EXISTEN (10)' else 'DISTINTA' end
order by 1;
