-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1: simulación de cierre) · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 10 (listo para el 9b)»; la 1 reemplazada «CORTE 10 (sin cambiar)»; las 9 nuevas «NO EXISTE»;
--        «tablas de la red» dice «ESTÁN»; «tabla de simulaciones» dice «NO EXISTE (sin aplicar)».
-- DESPUÉS: «CORTE 9b (aplicado)», «CORTE 9b (reemplazada)», 9 «NUEVA» y «tabla de simulaciones» «EXISTE (9b)».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values ('redes.f_param_entero(text)', 'b6218d0d4d4e8b343116b99fc35bc0ea', '45e46bf5fa65c38c0cd95a9bfafb3d90')),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 10 (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 9b (reemplazada)' else 'DISTINTA' end as estado
    from cam c),
nue(firma, nueva) as (values ('redes.f_sim_grafo()', '0439fdbc6b8615d29f3ecbe7b0a97a61'), ('redes.f_sim_llenar_agua()', 'b0ae7f1b6f3dfc72c90d4c42082e8a2b'), ('redes.f_sim_escenario(bigint[],bigint,boolean,bigint[],geometry,integer)', '77c9456adc4de3337d369514398a9331'), ('redes.f_simular_cierre(bigint)', '1ea9ec75226bd0592d0f85a9c1513feb'), ('redes.f_sim_tramo_cercano(numeric,numeric)', '2c20d924a65420a23e5eaac3d7508074'), ('redes.f_sim_autorizar(text)', 'a51058c0b84d12517137f8f0eded944f'), ('public.geoportal_redes_simulacion_cierre(text,text,numeric,numeric)', 'c4b6b565b8b8de5fdd2106e459bbefcf'), ('public.geoportal_redes_simulacion_guardar(text,text,text)', '3585f16c7aa0933645c984723ba62b47'), ('public.geoportal_redes_simulaciones(text,text)', '1df51d05cc0d0f6ef20bc0d88b025704')),
rnue as (
  select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when 'aad5952c27e13cc3ad45623279ba7085' then 'CORTE 10 (listo para el 9b)' when 'beafb93a12ff2e4b306281692e62dd93' then 'CORTE 9b (aplicado)' else 'DISTINTA' end as estado
union all select * from rcam
union all select * from rnue
union all select '4 tablas de la red (tramo_nodos, nodos, contrato_tramo) y del 10 (val_amarre)', null,
       case when to_regclass('redes.tramo_nodos') is not null and to_regclass('redes.nodos') is not null and to_regclass('redes.contrato_tramo') is not null
                 and to_regclass('redes.val_amarre') is not null then 'ESTÁN' else 'FALTA' end
union all select '5 tabla de simulaciones (simulaciones_cierre)', null,
       case when to_regclass('redes.simulaciones_cierre') is null then 'NO EXISTE (sin aplicar)' else 'EXISTE (9b)' end
union all select '6 INFO red de acueducto: tramos en operación · válvulas como nodos · tanques y planta · contratos con tramo', null,
       (select count(*) from redes.activo_vigente_mat where sistema = 'acueducto' and prefijo in ('RED', 'CON') and cuenta_vigente and not retirado) || ' · '
       || (select count(*) from redes.nodos n join redes.activo_vigente_mat m on m.activo_id = n.activo_id where m.prefijo = 'VAL') || ' · '
       || (select count(*) from redes.activo_vigente_mat where prefijo in ('TAN', 'PTA') and cuenta_vigente and not retirado) || ' · '
       || (select count(*) from redes.contrato_tramo)
order by 1;
