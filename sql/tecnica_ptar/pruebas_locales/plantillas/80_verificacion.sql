-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 80 — VERIFICACIÓN (SOLO LECTURA; una consulta, apta para el editor SQL web). Correr DESPUÉS de la migración: todo «OK».
-- =====================================================================
select k, valor, case when ok then 'OK' else 'REVISAR' end as estado from (
  select 1 as o, '1 huella de redes sin cambio' as k,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) as valor,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_REDES}}' as ok
  union all
  select 2, '2 instalaciones: PTAP Huaricha y Gota Fría con su planta, PTAR El Salguero sin planta',
         (select string_agg(i.codigo || coalesce('→' || p.codigo, '') || ' ' || i.horas_sin_dato || ' h', ', ' order by i.id) from tecnica.instalaciones i left join tecnica.plantas p on p.id = i.planta_id),
         (select count(*) = 3 and count(*) filter (where codigo = 'ptar' and tipo = 'residual' and planta_id is null and horas_sin_dato = 168) = 1
                 and count(*) filter (where tipo = 'potable' and planta_id is not null and horas_sin_dato = 24) = 2 from tecnica.instalaciones)
  union all
  select 3, '3 la PTAR no está en tecnica.plantas', (select count(*)::text from tecnica.plantas where codigo like '%ptar%'), not exists (select 1 from tecnica.plantas where codigo like '%ptar%')
  union all
  select 4, '4 tablas nuevas vacías de alcance y alias (nadie pierde la PTAP)', (select count(*) from tecnica.alcance_eventos) || ' alcance · ' || (select count(*) from tecnica.elemento_alias_eventos) || ' alias',
         not exists (select 1 from tecnica.alcance_eventos) and not exists (select 1 from tecnica.elemento_alias_eventos)
  union all
  select 5, '5 las funciones nuevas o reemplazadas son las del paquete ({{N_FUNC}})', (select count(*)::text from pg_proc p where p.oid::regprocedure::text in ({{FIRMAS}})),
         (select count(*) from pg_proc p where p.oid::regprocedure::text in ({{FIRMAS}})
             and md5(pg_get_functiondef(p.oid)) = case p.oid::regprocedure::text {{CASOS}} end) = {{N_FUNC}}
  union all
  select 6, '6 RPC: EXECUTE solo service_role',
         (select string_agg(p.proname, ', ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_ptar\_%'),
         (select count(*) = 6 and bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
                 and not has_function_privilege('authenticated', p.oid, 'execute')) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_ptar\_%')
  union all
  select 7, '7 tablas: RLS y sin privilegios para la API', (select string_agg(c.relname, ', ' order by c.relname) from pg_class c where c.relnamespace = 'tecnica'::regnamespace
           and c.relname in ('instalaciones', 'elementos_planta', 'elemento_alias_eventos', 'alcance_eventos')),
         (select count(*) = 4 and bool_and(c.relrowsecurity and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select')
                 and not has_table_privilege('service_role', c.oid, 'select')) from pg_class c where c.relnamespace = 'tecnica'::regnamespace
            and c.relname in ('instalaciones', 'elementos_planta', 'elemento_alias_eventos', 'alcance_eventos'))
  union all
  select 8, '8 disparadores de no borrar / solo agregar / no editar', (select count(*)::text from pg_trigger where not tgisinternal and tgrelid in ('tecnica.instalaciones'::regclass,
           'tecnica.elementos_planta'::regclass, 'tecnica.elemento_alias_eventos'::regclass, 'tecnica.alcance_eventos'::regclass)),
         (select count(*) = 10 from pg_trigger where not tgisinternal and tgrelid in ('tecnica.instalaciones'::regclass, 'tecnica.elementos_planta'::regclass,
           'tecnica.elemento_alias_eventos'::regclass, 'tecnica.alcance_eventos'::regclass))
  union all
  select 9, '9 pg-safeupdate: funciones con DELETE/UPDATE sin WHERE', (select count(*)::text from redes.f_funciones_sin_where()), not exists (select 1 from redes.f_funciones_sin_where())
) t order by o;
