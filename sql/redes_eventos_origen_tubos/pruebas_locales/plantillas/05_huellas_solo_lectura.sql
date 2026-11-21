-- =====================================================================
-- TÉCNICA · FASE 1 · EVENTOS: ORIGEN Y TUBOS · 05 — HUELLAS (SOLO LECTURA; una sola consulta, apta para el editor SQL web). Correr ANTES y DESPUÉS.
-- Antes: la fila 0 debe decir PUBLICADA, las 1 «LA PUBLICADA», la 2 «NO EXISTE»; después: APLICADO, «REEMPLAZADA» y «NUEVA». La 3 siempre «SIN CAMBIO».
-- =====================================================================
select k, v, estado from (
  select 0 as o, '0 funciones de redes (conjunto)' as k,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) as v,
         case (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
              when '{{MD5_BASE}}' then 'PUBLICADA (reportes del PTAP y Distribución; lista para este corte)' when '{{MD5_DESPUES}}' then 'EVENTOS: ORIGEN Y TUBOS (aplicado)' else 'OTRA: deténgase y avise' end as estado
  union all
  select 1, '1 ' || a.f || ' (se reemplaza)', md5(pg_get_functiondef(to_regprocedure(a.f))),
         case md5(pg_get_functiondef(to_regprocedure(a.f))) when a.m then 'LA PUBLICADA' when d.m then 'REEMPLAZADA (aplicado)' else 'OTRA: deténgase y avise' end
    from (values {{REEMPLAZADAS_ANTES}}) a(f, m) join (values {{REEMPLAZADAS_DESPUES}}) d(f, m) on d.f = a.f
  union all
  select 2, '2 ' || n.f || ' (nueva)', case when to_regprocedure(n.f) is not null then md5(pg_get_functiondef(to_regprocedure(n.f))) end,
         case when to_regprocedure(n.f) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.f))) = n.m then 'NUEVA (aplicada)' else 'OTRA: deténgase y avise' end
    from (values {{NUEVAS}}) n(f, m)
  union all
  select 3, '3 las {{N_NO_TOCAR}} que no se tocan (evento_contrato, aviso, SCRR, disparadores, bot, demás rutas de eventos)', null,
         case when (select count(*) from (values {{NO_TOCAR}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NO_TOCAR}} then 'SIN CAMBIO' else 'CAMBIARON: deténgase y avise' end
  union all
  select 4, '4 tablas nuevas (6)', null,
         case (select count(*) from pg_class where oid in (to_regclass('redes.evento_causales'), to_regclass('redes.evento_causal_eventos'), to_regclass('redes.evento_causal'),
                                                         to_regclass('redes.tubo_sectores'), to_regclass('redes.tubo_sector_eventos'), to_regclass('redes.evento_tubos')))
              when 0 then 'NO EXISTEN (sin aplicar)' when 6 then 'EXISTEN (aplicado)' else 'A MEDIAS: deténgase y avise' end
  union all
  select 5, '5 INFO sectores por planta activos · plantas con alguno · tubos de salida (tipo distribución) · eventos · eventos de planta', null,
         (select count(*) from redes.planta_sectores where activo) || ' · ' || (select count(distinct planta_id) from redes.planta_sectores where activo) || ' · '
         || (select count(*) from tecnica.puntos where tipo = 'distribucion') || ' · ' || (select count(*) from redes.eventos_suspension) || ' · '
         || (select count(*) from redes.eventos_suspension where planta_id is not null)
  union all
  select 6, '6 INFO huella de técnica (esquema tecnica y geoportal_tec_*; anótela antes y después)',
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%')), 'INFORMATIVA'
) t order by o, k;
