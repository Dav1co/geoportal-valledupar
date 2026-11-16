-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 7a (listo para el 9a)»; las {{N_CAMBIADAS}} reemplazadas «CORTE 7a (sin cambiar)»; las {{N_NUEVAS}} nuevas «NO EXISTE»;
--        la vista de nodos «CORTE 1a (sin cambiar)»; las tablas de referencia «NO EXISTE».
-- DESPUÉS: «CORTE 9a (aplicado)», {{N_CAMBIADAS}} «CORTE 9a (reemplazada)», {{N_NUEVAS}} «NUEVA», la vista «CORTE 9a» y las tablas «EXISTE».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values {{CAMBIADAS}}),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 7a (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 9a (reemplazada)' else 'DISTINTA' end as estado
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
       case (select m from conj) when '{{MD5_BASE}}' then 'CORTE 7a (listo para el 9a)' when '{{MD5_9A}}' then 'CORTE 9a (aplicado)' else 'DISTINTA' end as estado
union all select '1 vista redes.v_nodo_vigente', md5(pg_get_viewdef('redes.v_nodo_vigente'::regclass)),
       case md5(pg_get_viewdef('redes.v_nodo_vigente'::regclass)) when '{{MD5_VISTA_NODO}}' then 'CORTE 1a (sin cambiar)' when '{{MD5_VISTA_NODO_9A}}' then 'CORTE 9a (aplicada)' else 'DISTINTA' end
union all select * from rcam
union all select * from rnue
union all select '4 tabla ' || t, null, case when to_regclass(t) is null then 'NO EXISTE (sin aplicar)' else 'EXISTE (aplicado)' end
  from unnest(array['redes.ref_cargas', 'redes.ref_carga_eventos', 'redes.pm_nodos', 'redes.pm_tramos', 'redes.pm_valvulas', 'redes.pm_presion_hora', 'redes.pm_alc_conductos',
                    'redes.pm_alc_pozos', 'redes.ref_elementos', 'redes.pm_campana_lecturas']) t
union all select '5 capas del Cargue «sectores» y «sumideros» (Corte 5c)', null,
       case when (select count(*) from redes.capas where codigo in ('sectores', 'sumideros') and fuente = 'carga' and activa) = 2 then 'EXISTE' else 'FALTA' end
order by 1;
