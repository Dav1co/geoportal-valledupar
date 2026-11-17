-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 9b completo (listo para el 14)»; las {{N_CAMBIADAS}} reemplazadas «ANTES DEL 14 (sin cambiar)»; las {{N_NUEVAS}} nuevas
--        «NO EXISTE»; el dominio «9 CLAVES (listo)»; el CHECK de Comercial «PASADA 14-NOV (listo)»; las tablas «NO EXISTEN (sin aplicar)».
-- DESPUÉS: «CORTE 14 (aplicado)», {{N_CAMBIADAS}} «CORTE 14 (reemplazada)», {{N_NUEVAS}} «NUEVA», «10 CLAVES (14)», «CORTE 14» y «EXISTEN (14)».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values {{CAMBIADAS}}),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'ANTES DEL 14 (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 14 (reemplazada)' else 'DISTINTA' end as estado
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
       case (select m from conj) when '{{MD5_BASE}}' then 'CORTE 9b completo (listo para el 14)' when '{{MD5_14}}' then 'CORTE 14 (aplicado)' else 'DISTINTA' end as estado
union all select * from rcam
union all select * from rnue
union all select '4 dominio tecnica.formulario_clave', null,
       case (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck')
         when '{{DEF_DOMINIO}}' then '9 CLAVES (listo)' when '{{DEF_DOMINIO_14}}' then '10 CLAVES (14)' else 'DISTINTA' end
union all select '5 CHECK de campo.personal_eventos.formulario', null,
       case (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_eventos_formulario_check')
         when '{{DEF_CHECK_CAMPO}}' then 'PASADA 14-NOV (listo)' when '{{DEF_CHECK_CAMPO_14}}' then 'CORTE 14' else 'DISTINTA' end
union all select '6 tablas de los puntos por levantar (4)', null,
       case (select count(*) from unnest(array['redes.levantar_puntos', 'redes.levantar_preparaciones', 'redes.levantar_fotos', 'redes.levantar_eventos']) t where to_regclass(t) is not null)
         when 0 then 'NO EXISTEN (sin aplicar)' when 4 then 'EXISTEN (14)' else 'DISTINTA' end
union all select '7 formulario activo_campo en redes.formularios_distribucion', null,
       case when exists (select 1 from redes.formularios_distribucion where clave = 'activo_campo') then 'ESTÁ (14)' else 'NO ESTÁ (sin aplicar)' end
order by 1;
