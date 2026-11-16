-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 7a (listo para el 9a)»; las 6 reemplazadas «CORTE 7a (sin cambiar)»; las 13 nuevas «NO EXISTE»;
--        la vista de nodos «CORTE 1a (sin cambiar)»; las tablas de referencia «NO EXISTE».
-- DESPUÉS: «CORTE 9a (aplicado)», 6 «CORTE 9a (reemplazada)», 13 «NUEVA», la vista «CORTE 9a» y las tablas «EXISTE».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with cam(firma, antes, despues) as (values ('redes.f_ficha(bigint,text)', '0a9bc0637511b9fe69d27d7e14621644', '5fda646e3d5577f06f3375162730ba80'), ('public.geoportal_redes_geovisor_mvt(text,integer,integer,integer)', 'a2b1806a5200e2a3119f7a4592c5db05', '33d3cce77bff2de11cac3de6261cd274'), ('public.geoportal_redes_danos(text,text,integer)', '6916bb6e1f206bec88607808e5e7af18', '50fe7e4336e4c39eaf94e852166bd8ff'), ('public.geoportal_redes_intervenciones(text,text,integer)', 'b0d3a41405f63f4f35781ef2865122f3', 'e35feec21442612a90531b96826af125'), ('public.geoportal_redes_contrato_tarjeta(text,text,text)', 'fb3af00f93f627d3b5fa7f61c3f11cf5', '7d7598af58b4a1724159531cbf9e787b'), ('public.geoportal_redes_nodos_por_clasificar(text,text,bigint,integer)', '9d57944786b8bfd2fe8790034c2cd90a', 'e063594fb8d6b3565330297292fdc4ce')),
rcam as (
  select '2 ' || c.firma as objeto, md5(pg_get_functiondef(to_regprocedure(c.firma))) as md5,
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 7a (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 9a (reemplazada)' else 'DISTINTA' end as estado
    from cam c),
nue(firma, nueva) as (values ('redes.f_ref_vigente(text)', '102072192378998fb730738d9f0d4c6a'), ('redes.f_sector_de(geometry)', '455378c9b8cf43343ff821a2896eae37'), ('redes.f_pm_nivel_presion(numeric)', 'b8f5220dac667ca8388f2eaf15cb491b'), ('redes.f_pm_sugerencia(text,text,text,text)', '0e66cbaea934858c0a9c041ef3671b42'), ('redes.f_nodo_modelo(text)', '01dfa06ed01ee83a08c66a21225518a6'), ('redes.f_ficha_referencia(bigint)', '384d164062ebf786acff4a86bcc7d594'), ('redes.f_pm_marcar_por_verificar(text)', '28c7ca78eb1b166743667786d9f7e8af'), ('public.geoportal_redes_geovisor_mvt_ref(text,text,integer,integer,integer)', '940aa8766b455a10766a724ef2ecc535'), ('public.geoportal_redes_referencia(text,text,text)', '93531b8b99f1fe869d1e7c4cfd3989cb'), ('public.geoportal_redes_nodo_preliminar(text,bigint)', 'f871d0367f33d00d411aa02279c4a605'), ('public.geoportal_redes_nodo_clasificar(text,bigint,text,text)', '84541f4efb3b5347937299531c4f9ddc'), ('public.geoportal_redes_por_verificar(text,text,bigint,integer)', '6befe5e1be76a68266ca9cb454433082'), ('public.geoportal_redes_activo_verificar(text,text,text)', '71713dcd93f3b17f912ee5c0b339a4fe')),
rnue as (
  select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
         case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from nue n),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '79f184a4fe37ed2baa67dac7f3dd9b3c' then 'CORTE 7a (listo para el 9a)' when '4a46069fc3c71c305c49bafd764f316e' then 'CORTE 9a (aplicado)' else 'DISTINTA' end as estado
union all select '1 vista redes.v_nodo_vigente', md5(pg_get_viewdef('redes.v_nodo_vigente'::regclass)),
       case md5(pg_get_viewdef('redes.v_nodo_vigente'::regclass)) when '8085cfdb298ca64d3c7d787ccf05f8fe' then 'CORTE 1a (sin cambiar)' when '486a445772d5b7348f62c800863ac734' then 'CORTE 9a (aplicada)' else 'DISTINTA' end
union all select * from rcam
union all select * from rnue
union all select '4 tabla ' || t, null, case when to_regclass(t) is null then 'NO EXISTE (sin aplicar)' else 'EXISTE (aplicado)' end
  from unnest(array['redes.ref_cargas', 'redes.ref_carga_eventos', 'redes.pm_nodos', 'redes.pm_tramos', 'redes.pm_valvulas', 'redes.pm_presion_hora', 'redes.pm_alc_conductos',
                    'redes.pm_alc_pozos', 'redes.ref_elementos', 'redes.pm_campana_lecturas']) t
union all select '5 capas del Cargue «sectores» y «sumideros» (Corte 5c)', null,
       case when (select count(*) from redes.capas where codigo in ('sectores', 'sumideros') and fuente = 'carga' and activa) = 2 then 'EXISTE' else 'FALTA' end
order by 1;
