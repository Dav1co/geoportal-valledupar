-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: las 2 funciones de redes que se llaman «SIN CAMBIAR»; las 16 funciones nuevas, las 6 tablas o vistas y el rol «NO EXISTE».
-- DESPUÉS: 2 «SIN CAMBIAR», 16 «NUEVA», 6 «EXISTE» y el rol «EXISTE (nologin)». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- La línea 0 es el conjunto de funciones de redes (informativo: el Corte 12 no lo cambia; hoy debería ser 5fd6d00efdaa1a798e2628a2cde23c61).
-- =====================================================================
with red(firma, md5) as (values ('redes.f_param(text)', 'fb51278a5e07f3a0825be0155a76fd8b'), ('redes.f_muestreo_calidad(bigint)', 'a800598f12b1a46c768deffcc42671c1')),
nue(firma, nueva) as (values ('tecnica.f_aparam(text)', '157c8dfefb1867bce225d739f4f17370'), ('tecnica.f_cuantos(bigint,text,text)', '11e20d62bb6b54e48acbbfa23669999e'), ('tecnica.f_texto_horas(numeric)', '0376f9abe6c621d41617252a6da41012'), ('tecnica.f_texto_num(numeric)', '59a22259145b1cb40965a167e699abe3'), ('tecnica.f_avisos_perfil(text)', '332d8d75a4a11b841b3067dded32a714'), ('tecnica.f_avisos(boolean,boolean,timestamp with time zone)', '061990d1826a5a2de0a539ca22004987'), ('tecnica.f_nivel_rango(text)', 'f1b46546abb592ee757a11d1f5011f11'), ('tecnica.f_avisos_encolar(timestamp with time zone)', '39f25178f60c1ecf9758ca61df9a519a'), ('tecnica.avisos_tomar(integer,integer)', 'af7ca7068b3ef64e8bbcd610fbe0ba43'), ('tecnica.avisos_marcar(uuid,uuid,text,jsonb,boolean)', 'a5d3fae6abe9e4e35930276a5b761607'), ('tecnica.avisos_liberar(uuid,uuid)', 'a3f470a6beee4576994aeb6f6e32e589'), ('public.geoportal_tec_avisos(text)', 'f4e5d9159a6ea7d08936a86fd30af927'), ('public.geoportal_tec_avisos_parametros(text)', '6fbd9820e1af5ee0905672ec3a9db283'), ('public.geoportal_tec_aviso_parametro_fijar(text,text,numeric,text)', 'eca9e770442b99fa240541297d07f319'), ('public.geoportal_tec_quimico_minimos(text)', '3359eb220ca5121a7183b01e93a8dcb4'), ('public.geoportal_tec_quimico_minimo_fijar(text,text,numeric,text)', '81fa3ce0a1bc5caba6cdf5c4a208f956'))
select '0 conjunto de funciones de redes' as objeto, (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
        where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) as md5,
       case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
        where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '5fd6d00efdaa1a798e2628a2cde23c61' then 'IGUAL AL DEL ENCARGO' else 'OTRO (informativo)' end as estado
union all select '1 ' || r.firma, md5(pg_get_functiondef(to_regprocedure(r.firma))),
       case when to_regprocedure(r.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(r.firma))) = r.md5 then 'SIN CAMBIAR' else 'DISTINTA' end
  from red r
union all select '2 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
       case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
  from nue n
union all select '3 objeto ' || t, null, case when to_regclass(t) is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
  from unnest(array['tecnica.aviso_parametros', 'tecnica.aviso_parametro_eventos', 'tecnica.quimico_minimo_eventos', 'tecnica.avisos_salida', 'tecnica.aviso_salida_eventos', 'tecnica.v_avisos_salida']) t
union all select '4 rol dell_avisos', null, case when not exists (select 1 from pg_roles where rolname = 'dell_avisos') then 'NO EXISTE (sin aplicar)'
                                                  when (select rolcanlogin from pg_roles where rolname = 'dell_avisos') then 'EXISTE (CON LOGIN: lo activó el administrador)' else 'EXISTE (nologin)' end
order by 1;
