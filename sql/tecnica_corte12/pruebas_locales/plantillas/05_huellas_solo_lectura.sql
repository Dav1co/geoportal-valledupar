-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: las 2 funciones de redes que se llaman «SIN CAMBIAR»; las 16 funciones nuevas, las 6 tablas o vistas y el rol «NO EXISTE».
-- DESPUÉS: 2 «SIN CAMBIAR», 16 «NUEVA», 6 «EXISTE» y el rol «EXISTE (nologin)». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- La línea 0 es el conjunto de funciones de redes (informativo: el Corte 12 no lo cambia; hoy debería ser {{CONJ}}).
-- =====================================================================
with red(firma, md5) as (values {{REDES_USADAS}}),
nue(firma, nueva) as (values {{NUEVAS}})
select '0 conjunto de funciones de redes' as objeto, (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
        where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) as md5,
       case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
        where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{CONJ}}' then 'IGUAL AL DEL ENCARGO' else 'OTRO (informativo)' end as estado
union all select '1 ' || r.firma, md5(pg_get_functiondef(to_regprocedure(r.firma))),
       case when to_regprocedure(r.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(r.firma))) = r.md5 then 'SIN CAMBIAR' else 'DISTINTA' end
  from red r
union all select '2 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
       case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
  from nue n
union all select '3 objeto ' || t, null, case when to_regclass(t) is not null then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
  from unnest(array[{{TABLAS}}]) t
union all select '4 rol dell_avisos', null, case when not exists (select 1 from pg_roles where rolname = 'dell_avisos') then 'NO EXISTE (sin aplicar)'
                                                  when (select rolcanlogin from pg_roles where rolname = 'dell_avisos') then 'EXISTE (CON LOGIN: lo activó el administrador)' else 'EXISTE (nologin)' end
order by 1;
