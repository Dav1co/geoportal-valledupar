-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 80 — VERIFICACIÓN (SOLO LECTURA; una consulta, apta para el editor SQL web). Correr DESPUÉS de la migración: todo «OK».
-- =====================================================================
select k, valor, case when ok then 'OK' else 'REVISAR' end as estado from (
  select 1 as o, '1 huella de redes sin cambio' as k,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) as valor,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
           where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '1ba192724c2fddcf321104700829f3cc' as ok
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
  select 5, '5 las funciones nuevas o reemplazadas son las del paquete (15)', (select count(*)::text from pg_proc p where p.oid::regprocedure::text in ('geoportal_tec_ptar_alcance_fijar(text,text,text,text,text,text)', 'geoportal_tec_ptar_alcances(text)', 'geoportal_tec_ptar_alias_fijar(text,text,text,text,text)', 'geoportal_tec_ptar_elemento(text,text)', 'geoportal_tec_ptar_mapa(text,text)', 'geoportal_tec_ptar_perfil(text)', 'tecnica.f_alias_vigente(bigint,text)', 'tecnica.f_autorizar_instalacion(text,bigint)', 'tecnica.f_autorizar_ptar(text)', 'tecnica.f_autorizar_supervision(text)', 'tecnica.f_elemento_coherente()', 'tecnica.f_elemento_protegido()', 'tecnica.f_instalacion(text)', 'tecnica.f_tiene_alcance(text,text)', 'tecnica.f_tipo_elemento_texto(text)')),
         (select count(*) from pg_proc p where p.oid::regprocedure::text in ('geoportal_tec_ptar_alcance_fijar(text,text,text,text,text,text)', 'geoportal_tec_ptar_alcances(text)', 'geoportal_tec_ptar_alias_fijar(text,text,text,text,text)', 'geoportal_tec_ptar_elemento(text,text)', 'geoportal_tec_ptar_mapa(text,text)', 'geoportal_tec_ptar_perfil(text)', 'tecnica.f_alias_vigente(bigint,text)', 'tecnica.f_autorizar_instalacion(text,bigint)', 'tecnica.f_autorizar_ptar(text)', 'tecnica.f_autorizar_supervision(text)', 'tecnica.f_elemento_coherente()', 'tecnica.f_elemento_protegido()', 'tecnica.f_instalacion(text)', 'tecnica.f_tiene_alcance(text,text)', 'tecnica.f_tipo_elemento_texto(text)')
             and md5(pg_get_functiondef(p.oid)) = case p.oid::regprocedure::text when 'geoportal_tec_ptar_alcance_fijar(text,text,text,text,text,text)' then '3a1f3486e13483c153d8d892923c8e53' when 'geoportal_tec_ptar_alcances(text)' then 'c8d884538b1a0acbd5ef4b533eb9e0b6' when 'geoportal_tec_ptar_alias_fijar(text,text,text,text,text)' then '5c69eed5cd6d7fc21f9169ac30dc63cf' when 'geoportal_tec_ptar_elemento(text,text)' then '817fd0406e1dabeeea8702cbf3bc308a' when 'geoportal_tec_ptar_mapa(text,text)' then '550af2a41febc7e3c5b47e27f9c593fa' when 'geoportal_tec_ptar_perfil(text)' then '82b3f0d0ea0daf91e4ef6ebc874a0176' when 'tecnica.f_alias_vigente(bigint,text)' then 'ca7ac34d15f78d38593673045457ed55' when 'tecnica.f_autorizar_instalacion(text,bigint)' then '4d914ca0346b0873041402ca4d10a3af' when 'tecnica.f_autorizar_ptar(text)' then '43d5ea4dd8e67167857a3259c76f3d59' when 'tecnica.f_autorizar_supervision(text)' then 'cf531900f6be5fc187b73395a2340e2b' when 'tecnica.f_elemento_coherente()' then 'b7d44aab48b738d13fca15fbd4f14806' when 'tecnica.f_elemento_protegido()' then 'b7b2c2d38aac9ccd21e1dd375a588038' when 'tecnica.f_instalacion(text)' then 'c114e7fda41db3262029e55b7157aa87' when 'tecnica.f_tiene_alcance(text,text)' then '0dfdd5f19eafc581bdb878137a880c8c' when 'tecnica.f_tipo_elemento_texto(text)' then '2974e567d6cf466200792a46afe0d6b2' end) = 15
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
