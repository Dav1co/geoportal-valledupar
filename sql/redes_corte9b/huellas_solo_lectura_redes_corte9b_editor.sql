-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1: simulación de cierre) · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 10 (listo para el 9b)»; las 2 reemplazadas «PRODUCCIÓN (sin cambiar)» (f_param_entero del 10 y tecnica.f_avisos del 12); las 18 nuevas «NO EXISTE»;
--        «tablas de la red» dice «ESTÁN»; «tabla de simulaciones» dice «NO EXISTE (sin aplicar)».
-- DESPUÉS: «CORTE 9b (aplicado)», «CORTE 9b (reemplazada)», 18 «NUEVA» y «tabla de simulaciones» «EXISTE (9b)».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values ('redes.f_param_entero(text)', 'b6218d0d4d4e8b343116b99fc35bc0ea', '45e46bf5fa65c38c0cd95a9bfafb3d90'), ('tecnica.f_avisos(boolean,boolean,timestamp with time zone)', '061990d1826a5a2de0a539ca22004987', '898bafa5adddfcc08d65adf138d0114a')),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'PRODUCCIÓN (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 9b (reemplazada)' else 'DISTINTA' end as estado
    from cam c),
nue(firma, nueva) as (values ('redes.f_sim_grafo()', '0439fdbc6b8615d29f3ecbe7b0a97a61'), ('redes.f_sim_llenar_agua()', 'b0ae7f1b6f3dfc72c90d4c42082e8a2b'), ('redes.f_sim_escenario(bigint[],bigint,boolean,bigint[],geometry,integer)', '77c9456adc4de3337d369514398a9331'), ('redes.f_simular_cierre(bigint)', '1ea9ec75226bd0592d0f85a9c1513feb'), ('redes.f_sim_tramo_cercano(numeric,numeric)', '2c20d924a65420a23e5eaac3d7508074'), ('redes.f_sim_autorizar(text)', 'a51058c0b84d12517137f8f0eded944f'), ('public.geoportal_redes_simulacion_cierre(text,text,numeric,numeric)', 'c4b6b565b8b8de5fdd2106e459bbefcf'), ('public.geoportal_redes_simulacion_guardar(text,text,text)', '3585f16c7aa0933645c984723ba62b47'), ('public.geoportal_redes_simulaciones(text,text)', '1df51d05cc0d0f6ef20bc0d88b025704'), ('redes.f_cierres_vigentes()', '7919dabebc2a167efc2a0a5c9449cfc0'), ('redes.f_cierre_regreso(bigint)', 'dd179750ee880cd33954da6c6ba3ad21'), ('redes.f_cortes_foto(bigint,text,text)', '5e0796a8a83e41bd005cb7a941b61f40'), ('redes.f_cortes_para_avisos(timestamp with time zone,numeric,numeric)', '0d0a66c1842d8f2fc65f47f430cbd10a'), ('public.geoportal_redes_valvula_maniobra(text,text,text,text,text,text,text)', 'c17b23590b8af31d574f593aaeb8c781'), ('public.geoportal_redes_corte_regreso(text,text,text,text)', '164a24157f1e2fef6a521487b8799cea'), ('public.geoportal_redes_cortes_vigentes(text)', 'c09eadccc9399bb27b78dfb0ad14c8f8'), ('public.geoportal_redes_cortes_recalcular(text,text)', 'fb6ff311cfa2527061a7e5149d736e5b'), ('public.geoportal_redes_geovisor_mvt_cortes(text,integer,integer,integer)', '05008c9d4c4a07d932829f1924d29115')),
rnue as (
  select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when 'aad5952c27e13cc3ad45623279ba7085' then 'CORTE 10 (listo para el 9b)' when '895517fb68f74d6d6c20079c83bdf7c4' then 'CORTE 9b (aplicado)' else 'DISTINTA' end as estado
union all select * from rcam
union all select * from rnue
union all select '4 tablas de la red (tramo_nodos, nodos, contrato_tramo) y del 10 (val_amarre)', null,
       case when to_regclass('redes.tramo_nodos') is not null and to_regclass('redes.nodos') is not null and to_regclass('redes.contrato_tramo') is not null
                 and to_regclass('redes.val_amarre') is not null then 'ESTÁN' else 'FALTA' end
union all select '5 tablas del 9b (simulaciones_cierre, valvula_maniobras, corte_fotos y sus 3 detalles)', null,
       case (to_regclass('redes.simulaciones_cierre') is not null)::int + (to_regclass('redes.valvula_maniobras') is not null)::int + (to_regclass('redes.corte_fotos') is not null)::int
            + (to_regclass('redes.corte_foto_zonas') is not null)::int + (to_regclass('redes.corte_foto_tramos') is not null)::int + (to_regclass('redes.corte_foto_valvulas') is not null)::int
         when 0 then 'NO EXISTEN (sin aplicar)' when 6 then 'EXISTEN (9b)' else 'DISTINTA' end
union all select '6 INFO red de acueducto: tramos en operación · válvulas como nodos · tanques y planta · contratos con tramo', null,
       (select count(*) from redes.activo_vigente_mat where sistema = 'acueducto' and prefijo in ('RED', 'CON') and cuenta_vigente and not retirado) || ' · '
       || (select count(*) from redes.nodos n join redes.activo_vigente_mat m on m.activo_id = n.activo_id where m.prefijo = 'VAL') || ' · '
       || (select count(*) from redes.activo_vigente_mat where prefijo in ('TAN', 'PTA') and cuenta_vigente and not retirado) || ' · '
       || (select count(*) from redes.contrato_tramo)
order by 1;
