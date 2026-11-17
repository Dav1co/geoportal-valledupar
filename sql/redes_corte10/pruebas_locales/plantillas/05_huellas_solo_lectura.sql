-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 5d (listo para el 10)»; las {{N_CAMBIADAS}} reemplazadas «CORTE 5d (sin cambiar)»; las {{N_NUEVAS}} nuevas «NO EXISTE»;
--        «tablas de referencia del 9a» dice «ESTÁN»; «tablas de la valoración» dice «NO EXISTEN (sin aplicar)».
-- DESPUÉS: «CORTE 10 (aplicado)», {{N_CAMBIADAS}} «CORTE 10 (reemplazada)», {{N_NUEVAS}} «NUEVA» y «tablas de la valoración» «EXISTEN (10)».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values {{CAMBIADAS}}),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 5d (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 10 (reemplazada)' else 'DISTINTA' end as estado
    from cam c),
nue(firma, nueva) as (values {{NUEVAS}}),
rnue as (
  select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_BASE}}' then 'CORTE 5d (listo para el 10)' when '{{MD5_10}}' then 'CORTE 10 (aplicado)' else 'DISTINTA' end as estado
union all select * from rcam
union all select * from rnue
union all select '4 tablas de referencia del 9a (ref_cargas, pm_valvulas)', null,
       case when to_regclass('redes.ref_cargas') is not null and to_regclass('redes.pm_valvulas') is not null then 'ESTÁN' else 'FALTA' end
union all select '5 tablas de la valoración (val_hojas, val_filas, val_amarre)', null,
       case (to_regclass('redes.val_hojas') is not null)::int + (to_regclass('redes.val_filas') is not null)::int + (to_regclass('redes.val_amarre') is not null)::int
         when 0 then 'NO EXISTEN (sin aplicar)' when 3 then 'EXISTEN (10)' else 'DISTINTA' end
order by 1;
