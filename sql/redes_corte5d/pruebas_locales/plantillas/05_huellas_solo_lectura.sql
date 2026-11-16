-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 9a-bis (listo para el 5d)»; las {{N_CAMBIADAS}} reemplazadas «CORTE 9a-bis (sin cambiar)»; las {{N_NUEVAS}} nuevas «NO EXISTE»;
--        «dominio de formularios» dice «CON LAS CLAVES DEL CORTE 8»; la capa pqr_116 «PREPARADA»; el catastro «CON DIRECCIÓN Y BARRIO».
-- DESPUÉS: «CORTE 5d (aplicado)», {{N_CAMBIADAS}} «CORTE 5d (reemplazada)», {{N_NUEVAS}} «NUEVA» y la capa pqr_116 «ACTIVA (5d)».
-- Cualquier «DISTINTA», «FALTA» o «SIN LAS CLAVES»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values {{CAMBIADAS}}),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 9a-bis (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 5d (reemplazada)' else 'DISTINTA' end as estado
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
       case (select m from conj) when '{{MD5_BASE}}' then 'CORTE 9a-bis (listo para el 5d)' when '{{MD5_5D}}' then 'CORTE 5d (aplicado)' else 'DISTINTA' end as estado
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
                   and column_name in ('cod_usuario', 'geom', 'direccion', 'barrio')) = 4 then 'CON DIRECCIÓN Y BARRIO' else 'FALTA ALGUNA COLUMNA' end
order by 1;
