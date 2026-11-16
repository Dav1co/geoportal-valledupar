-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 6b (listo para el 7a)»; las 11 RPC nuevas «NO EXISTE»; las 2 reemplazadas «CORTE 6b (sin cambiar)»; las 4 tablas, las 2 vistas
-- y el bucket «NO EXISTE». DESPUÉS: «CORTE 7a (aplicado)», 11 «NUEVA», 2 «CORTE 7a (reemplazada)» y 7 «EXISTE».
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with esp(objeto, nueva) as (values ('geoportal_tec_quimico_ajuste', '4ff08adcd3140c1da41827af1811727a'), ('geoportal_tec_quimico_crear', '851c1a8e7ba351bc3fb5d7fd53a2e8e0'), ('geoportal_tec_quimico_entrada', '9daf6b0ef659b44d30a9260b003e0a31'), ('geoportal_tec_quimico_ficha_preparar', '1a28c7a420f0ad7a2f064ebc401fa369'), ('geoportal_tec_quimico_fijar', '2026b1ec6e6752b368063609e3b1a60c'), ('geoportal_tec_quimico_historial', '9112d90a773971bacfb9d69310b2da89'), ('geoportal_tec_quimico_inventario', 'dc9ecbbbc7ae91e6a5fdb5653ebc59cb'), ('geoportal_tec_quimico_uso', '146290c07b0befb3aca05fdf350b34db'), ('geoportal_tec_quimicos_catalogo', '27c5a7644b003c62f06bf478772d1e57'), ('geoportal_tec_quimicos_comparacion', 'edbc5521095974d4f289e1d4f395f2b6'), ('geoportal_tec_quimicos_formulario', '443e5fa3f77b76d618e7e09131da4185')),
rpc as (
  select 'public.' || e.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end as estado
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(firma, antes, despues) as (values ('redes.f_estado_contrato(text)', 'f81143cf200d3d2de057a98ac9f07c49', '6bf7c182fb2998534baa81719912c37e'), ('public.geoportal_redes_contrato_tarjeta(text,text,text)', '1af144caaebfe57e14c71d41c3e4b520', '32d43e65e8c7ff30baa209469915ed87')),
rcam as (
  select c.firma, md5(pg_get_functiondef(to_regprocedure(c.firma))),
         case when to_regprocedure(c.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.antes then 'CORTE 6b (sin cambiar)'
              when md5(pg_get_functiondef(to_regprocedure(c.firma))) = c.despues then 'CORTE 7a (reemplazada)' else 'DISTINTA' end
    from cam c),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when 'fca28bf695d1fcfa153f1113ce821528' then 'CORTE 6b (listo para el 7a)' when 'f6c14c268aaedb5ab243f87685b428dd' then 'CORTE 7a (aplicado)' else 'DISTINTA' end as estado
union all select * from rpc
union all select * from rcam
union all select '1 objeto ' || t, null, case when to_regclass(t) is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
  from unnest(array['tecnica.quimico_ficha_eventos', 'tecnica.quimico_ficha_preparaciones', 'tecnica.quimico_movimientos', 'tecnica.quimico_parametros',
                    'tecnica.v_quimico_vigente', 'tecnica.v_quimico_saldo']) t
union all select '1 bucket tecnica-evidencias', null, case when exists (select 1 from storage.buckets where id = 'tecnica-evidencias') then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
order by 1;
