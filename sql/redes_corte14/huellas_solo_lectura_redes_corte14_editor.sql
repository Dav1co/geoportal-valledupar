-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 9b completo (listo para el 14)»; las 5 reemplazadas «ANTES DEL 14 (sin cambiar)»; las 18 nuevas
--        «NO EXISTE»; el dominio «9 CLAVES (listo)»; el CHECK de Comercial «PASADA 14-NOV (listo)»; las tablas «NO EXISTEN (sin aplicar)».
-- DESPUÉS: «CORTE 14 (aplicado)», 5 «CORTE 14 (reemplazada)», 18 «NUEVA», «10 CLAVES (14)», «CORTE 14» y «EXISTEN (14)».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values ('public.geoportal_redes_mi_perfil(text)', '5cca0e645a5e106529382ed51e1519e9', 'e3ca21b7b39667d0ab1566945091e5cd'), ('campo.f_formularios_personal()', '51b26c1209ae8403560888ca29902fb5', '283a63c1ee3fad9e5956a65f8a4644b6'), ('public.geoportal_redes_geovisor_capa(text,text,date,date)', 'a79ba32d0d1c8f6c243928e370d217d3', '906724ad57340fdcc44d718f7c0a33e7'), ('tecnica.f_avisos(boolean,boolean,timestamptz)', '2a7989bead5fd35d3a4d0c4e45bcb92b', 'b7ec2303f95153684963ded7bdb0a5c0'), ('public.geoportal_redes_geovisor(text)', 'f9d408248906b538278a474ca2ab92af', 'c10f6049c8dd5310cac885b59e22c2c9')),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'ANTES DEL 14 (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 14 (reemplazada)' else 'DISTINTA' end as estado
    from cam c),
nue(firma, nueva) as (values ('public.geoportal_redes_geovisor_mvt_remuneracion(text,integer,integer,integer)', '14298af247824fc469bbc9e6c8e05efb'), ('public.geoportal_redes_levantar_cerca(text,numeric,numeric,numeric,text)', '5c71a3b9e07e272889053aa85cc6d98c'), ('public.geoportal_redes_levantar_crear(text,uuid,jsonb,text)', '09d88de65df1238dc373a3500b6b1f3a'), ('public.geoportal_redes_levantar_evento(text,text,text,text,text,text)', '35105af251ffaa62aec4121b6c27d967'), ('public.geoportal_redes_levantar_ficha(text,text)', 'e95e990d7fba78671e071dec31c82950'), ('public.geoportal_redes_levantar_fotos(text,text,text)', '1a6e3335fb52027cd000ebbeb3ae7086'), ('public.geoportal_redes_levantar_hoja(text,text,text)', '73a119ce305683abcd946bae93f2024c'), ('public.geoportal_redes_levantar_inicio(text)', '6224656efc6267fcf540b978618afcf7'), ('public.geoportal_redes_levantar_lista(text,text,text,integer)', 'd93c1a02106798ef5230d2b922f35aae'), ('public.geoportal_redes_levantar_preparar(text,integer)', '032583d085ad2574018180fd96f911ab'), ('public.geoportal_redes_remuneracion(text)', 'e8b5d12973516a9f274d186a0349cfce'), ('public.geoportal_redes_remuneracion_tarjeta(text,text)', '920f0a86e85ba3ac238c06042481cdfb'), ('redes.f_levantar_acceso(text)', '69298852e18084d8857cd225180b908a'), ('redes.f_levantar_estado_nombre(text)', 'b4a5e88be2ad8bcd31fab2ab524c896c'), ('redes.f_levantar_puede(text)', '460b91b2eb72f0e4fbe6833c5a80890b'), ('redes.f_levantar_quien(text)', 'c69f713e91680287d454dbf1085e56fc'), ('redes.f_levantar_tipo_nombre(text)', '45417609f57adb1b7928b9ae5f8be179'), ('redes.f_remuneracion_estado(boolean,boolean,boolean)', '74fad162a44190520b6154014bb26875')),
rnue as (
  select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when 'a327aa51f43bb5cc2112a6db089718ed' then 'CORTE 9b completo (listo para el 14)' when '1a9ef250a74fb01962f463d98834cc4a' then 'CORTE 14 (aplicado)' else 'DISTINTA' end as estado
union all select * from rcam
union all select * from rnue
union all select '4 dominio tecnica.formulario_clave', null,
       case (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck')
         when 'CHECK ((VALUE = ANY (ARRAY[''entrada''::text, ''salida''::text, ''muestreo''::text, ''danos_fallas''::text, ''mantenimiento''::text, ''uso_quimicos''::text, ''entrada_quimicos''::text, ''anomalia_compartida''::text, ''revision_compartida''::text])))' then '9 CLAVES (listo)' when 'CHECK ((VALUE = ANY (ARRAY[''entrada''::text, ''salida''::text, ''muestreo''::text, ''danos_fallas''::text, ''mantenimiento''::text, ''uso_quimicos''::text, ''entrada_quimicos''::text, ''anomalia_compartida''::text, ''revision_compartida''::text, ''activo_campo''::text])))' then '10 CLAVES (14)' else 'DISTINTA' end
union all select '5 CHECK de campo.personal_eventos.formulario', null,
       case (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_eventos_formulario_check')
         when 'CHECK (((formulario IS NULL) OR (formulario ~ ''^(reporte_general|acta|tipo:[a-z][a-z0-9_]{1,59})$''::text)))' then 'PASADA 14-NOV (listo)' when 'CHECK (((formulario IS NULL) OR (formulario ~ ''^(reporte_general|acta|activo_campo|tipo:[a-z][a-z0-9_]{1,59})$''::text)))' then 'CORTE 14' else 'DISTINTA' end
union all select '6 tablas de los puntos por levantar (4)', null,
       case (select count(*) from unnest(array['redes.levantar_puntos', 'redes.levantar_preparaciones', 'redes.levantar_fotos', 'redes.levantar_eventos']) t where to_regclass(t) is not null)
         when 0 then 'NO EXISTEN (sin aplicar)' when 4 then 'EXISTEN (14)' else 'DISTINTA' end
union all select '7 formulario activo_campo en redes.formularios_distribucion', null,
       case when exists (select 1 from redes.formularios_distribucion where clave = 'activo_campo') then 'ESTÁ (14)' else 'NO ESTÁ (sin aplicar)' end
order by 1;
