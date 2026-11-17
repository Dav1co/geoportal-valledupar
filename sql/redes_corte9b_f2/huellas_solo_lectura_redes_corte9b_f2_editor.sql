-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «9b 1a + 1b (listo para la Fase 2)»; tecnica.f_avisos «9b 1b (sin cambiar)»; las 14 nuevas «NO EXISTE»; «tablas de la Fase 2» «NO EXISTEN (sin aplicar)».
-- DESPUÉS: «FASE 2 (aplicada)», tecnica.f_avisos «FASE 2 (reemplazada)», 14 «NUEVA» y «tablas de la Fase 2» «EXISTEN». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise.
-- =====================================================================
with nue(firma, nueva) as (values ('redes.f_presion_nivel(numeric,numeric)', '6441a3c6df8b11bdd06c448c6adacbe2'), ('redes.f_presion_nodos(text)', '623913f7d7769657395e132bf04fb26e'), ('redes.f_alertas_presion(text)', 'b22987360efe991cb6d21bedf90fa905'), ('redes.f_presion_para_avisos()', 'b9e6313e5c653f4d65be306ef49e8e11'), ('redes.f_sensible_tipo(text)', '6044a2bed03348f62ed92855748edb76'), ('redes.f_sensibles_proponer(text)', 'aabaf7f82fffbd7e94385ee005bd6037'), ('redes.f_sensibles_en(text[])', 'd390c744e700b61b2fafebbc4f74dd01'), ('redes.f_sensor_estado(bigint)', '1df139091aa8b2f3eb31ae331db68333'), ('public.geoportal_redes_alertas_presion(text,text)', '0c7d2964e96ec0f525d7f0957530d293'), ('public.geoportal_redes_sensibles(text,text,text,integer)', 'f2e0bf3d61dac8f8b85eb044e37f925a'), ('public.geoportal_redes_sensible_fijar(text,text,text,text,text)', 'ea00de3bbdf9e0a490ffbaff9f72d96a'), ('public.geoportal_redes_afectacion(text,text)', 'd8bda5a0a052c48234f62f3e9d9e6139'), ('public.geoportal_redes_sensores(text)', '4a39e349b0ce1fc3336e3a22bf4504b1'), ('public.geoportal_redes_afectaciones_danos(text)', '65b3a8e98f25d0bca2f1fe648d5749d8')),
rnue as (
  select '3 ' || n.firma as objeto, md5(pg_get_functiondef(to_regprocedure(n.firma))) as md5,
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '895517fb68f74d6d6c20079c83bdf7c4' then '9b 1a + 1b (listo para la Fase 2)' when '24e62e151ff418ea6acf631572d72683' then 'FASE 2 (aplicada)' else 'DISTINTA' end as estado
union all select * from rnue
union all select '2 tecnica.f_avisos(boolean,boolean,timestamp with time zone)', md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)),
       case md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) when '898bafa5adddfcc08d65adf138d0114a' then '9b 1b (sin cambiar)' when '2a7989bead5fd35d3a4d0c4e45bcb92b' then 'FASE 2 (reemplazada)' else 'DISTINTA' end
union all select '4 tablas del 9b 1b (corte_fotos) y del 9a (pm_nodos)', null,
       case when to_regclass('redes.corte_fotos') is not null and to_regclass('redes.pm_nodos') is not null then 'ESTÁN' else 'FALTA' end
union all select '5 tablas de la Fase 2 (tipos_sensible, usuarios_sensibles, usuario_sensible_eventos, presion_trabajo, presion_horas_no_confiables, sensor_lecturas)', null,
       case (to_regclass('redes.tipos_sensible') is not null)::int + (to_regclass('redes.usuarios_sensibles') is not null)::int + (to_regclass('redes.usuario_sensible_eventos') is not null)::int
            + (to_regclass('redes.presion_trabajo') is not null)::int + (to_regclass('redes.presion_horas_no_confiables') is not null)::int + (to_regclass('redes.sensor_lecturas') is not null)::int
         when 0 then 'NO EXISTEN (sin aplicar)' when 6 then 'EXISTEN (Fase 2)' else 'DISTINTA' end
union all select '6 INFO capa «cortes» en la lista del geovisor', null, (select case when activa then 'visible' else 'oculta' end from redes.geovisor_capas where codigo = 'cortes')
order by 1;
