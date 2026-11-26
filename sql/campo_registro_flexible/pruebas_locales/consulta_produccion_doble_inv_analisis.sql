-- [Code B] INVESTIGACIÓN Y ANÁLISIS · CONSULTA PARA REHACER EL DOBLE (solo lectura; para el editor SQL de Supabase)
-- Es un solo SELECT: no escribe nada, solo lee el catálogo de campo y la estructura de las tablas que el paquete toca.
-- Sin correos ni nombres de personas: la columna «autor» sale siempre como «(omitido)».
-- Devuelve una fila por dato (k, v). Descargue el resultado en CSV y déjelo en
--   ~/geoportal-consultas/campo/paquete_inv_analisis_1/produccion_doble.csv
-- Si alguna fila dice «NO EXISTE», no es un error de la consulta: es el dato.
with inv as (select t.* from campo.tipos_reporte t where t.codigo = 'investigacion_ubicacion'),
     tablas(n) as (values ('campo.tipos_reporte'), ('campo.tipo_campos'), ('campo.tipo_fotos'), ('campo.actividades'),
                          ('campo.derivadas'), ('campo.derivadas_catalogo'), ('campo.derivada_eventos'), ('campo.consultas_analisis'),
                          ('campo.causales_tipos'), ('campo.formularios_documento'), ('campo.grupos_reporte'))
select k, v from (
  -- 1. Los formularios (todos; la tabla es pequeña)
  select 100 + t.id::int as o, '1 tipos_reporte ' || t.codigo as k, (to_jsonb(t))::text as v from campo.tipos_reporte t
  union all
  select 200 + g.id::int, '1 grupos_reporte ' || g.id, (to_jsonb(g))::text from campo.grupos_reporte g
  union all
  -- 2. Campos, fotos y causales de la Investigación de ubicación
  select 1000 + c.orden, '2 tipo_campos INV ' || c.codigo, (to_jsonb(c))::text from campo.tipo_campos c join inv on inv.id = c.tipo_id
  union all
  select 2000 + f.orden, '2 tipo_fotos INV ' || f.codigo, (to_jsonb(f))::text from campo.tipo_fotos f join inv on inv.id = f.tipo_id
  union all
  select 2500 + ct.causal_id::int, '2 causales_tipos INV ' || ct.causal_id, (to_jsonb(ct))::text from campo.causales_tipos ct join inv on inv.id = ct.tipo_id
  union all
  -- 3. Actividades, catálogo de derivadas y formularios con documento (sin el autor)
  select 3000 + a.orden, '3 actividades ' || a.codigo, (to_jsonb(a) || '{"autor":"(omitido)"}')::text from campo.actividades a
  union all
  select 3500 + d.orden, '3 derivadas_catalogo ' || d.codigo, (to_jsonb(d) || '{"autor":"(omitido)"}')::text from campo.derivadas_catalogo d
  union all
  select 3900, '3 formularios_documento ' || x.formulario, (to_jsonb(x) || '{"autor":"(omitido)"}')::text from campo.formularios_documento x
  union all
  -- 4. Conteos (solo números)
  select 4000, '4 registros de la Investigación', coalesce((select count(*)::text from campo.reportes r join inv on inv.id = r.tipo_id), 'NO EXISTE')
  union all
  select 4001, '4 derivadas (total · sin evento de cierre)',
         (select count(*)::text from campo.derivadas) || ' · ' || (select count(*)::text from campo.derivadas d where not exists (select 1 from campo.derivada_eventos e where e.derivada_id = d.id))
  union all
  select 4002, '4 consultas_analisis (total · últimas 24 h)',
         (select count(*)::text from campo.consultas_analisis) || ' · ' || (select count(*)::text from campo.consultas_analisis where consultado_en > now() - interval '24 hours')
  union all
  select 4003, '4 secuencias (último valor)',
         (select string_agg(schemaname || '.' || sequencename || '=' || coalesce(last_value::text, 'sin usar'), ', ' order by sequencename) from pg_sequences
           where schemaname = 'campo' and sequencename in ('tipos_reporte_id_seq', 'tipo_campos_id_seq', 'tipo_fotos_id_seq', 'derivadas_id_seq', 'grupos_reporte_id_seq'))
  union all
  -- 5. Estructura exacta de las tablas que el paquete lee o toca
  select 5000, '5 columnas ' || tb.n,
         coalesce((select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end
                                     || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum)
                     from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
                    where a.attrelid = to_regclass(tb.n) and a.attnum > 0 and not a.attisdropped), 'NO EXISTE')
    from tablas tb
  union all
  select 5100, '5 restricciones ' || tb.n,
         coalesce((select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = to_regclass(tb.n)), 'NINGUNA')
    from tablas tb
  union all
  select 5200, '5 índices ' || tb.n,
         coalesce((select string_agg(i.indexdef, ' | ' order by i.indexname) from pg_indexes i where (i.schemaname || '.' || i.tablename) = tb.n), 'NINGUNO')
    from tablas tb
  union all
  select 5300, '5 disparadores ' || tb.n,
         coalesce((select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = to_regclass(tb.n) and not g.tgisinternal), 'NINGUNO')
    from tablas tb
  union all
  select 5400, '5 clase, RLS y permisos ' || tb.n,
         coalesce((select c.relkind::text || ' · rls ' || c.relrowsecurity::text || ' · acl ' || coalesce(c.relacl::text, '(por omisión)') from pg_class c where c.oid = to_regclass(tb.n)), 'NO EXISTE')
    from tablas tb
  union all
  -- 6. md5 de las funciones que el paquete cambia o de las que depende
  select 6000, '6 md5 ' || p.pronamespace::regnamespace::text || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', md5(pg_get_functiondef(p.oid))
    from pg_proc p
   where (p.pronamespace = 'campo'::regnamespace and p.proname in ('f_derivada_json', 'f_validar_datos', 'f_opciones_validas', 'f_autorizar_analisis', 'f_derivadas_al_registrar',
                                                                 'f_solo_agregar', 'f_auditar', 'f_telefonos', 'f_cupo_preparaciones', 'f_registradas_filtradas',
                                                                 'f_autorizar_supervision', 'f_error', 'f_verificar'))
      or (p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_campo_preparar_subida', 'geoportal_campo_crear_reporte', 'geoportal_campo_derivadas',
                                                                    'geoportal_campo_derivada_atender', 'geoportal_campo_derivada_cerrar', 'geoportal_campo_derivadas_abiertas',
                                                                    'geoportal_campo_analisis', 'geoportal_campo_gestionar_catalogo', 'geoportal_campo_formularios',
                                                                    'geoportal_campo_datos_sensibles', 'geoportal_campo_pdf_datos'))
  union all
  -- 7. Huellas (conjunto completo, como la guardia del SCRR y del reparto)
  select 7000, '7 huella de campo (debe ser 261bed3c9242f6261f845ec4e1374b3a)',
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))
  union all
  select 7001, '7 huella del acta (debe ser 111506c690249ad3b56ebf572566434c)',
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p
           where p.pronamespace = to_regnamespace('acta') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%'))
  union all
  -- 8. Que los nombres nuevos estén libres
  select 8000, '8 campo.analisis_observaciones', case when to_regclass('campo.analisis_observaciones') is null then 'LIBRE' else 'YA EXISTE' end
  union all
  select 8002, '8 campo.analisis_observacion_datos (sensible)', case when to_regclass('campo.analisis_observacion_datos') is null then 'LIBRE' else 'YA EXISTE' end
  union all
  select 8003, '8 campo.analisis_observacion_anulaciones', case when to_regclass('campo.analisis_observacion_anulaciones') is null then 'LIBRE' else 'YA EXISTE' end
  union all
  select 8004, '8 funciones public.geoportal_campo_analisis_observ*', (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname like 'geoportal\_campo\_analisis\_observ%')
  union all
  select 8005, '8 campo.reporte_datos_sensibles (el patrón que se copia)', coalesce((select c.relkind::text || ' · rls ' || c.relrowsecurity::text || ' · acl ' || coalesce(c.relacl::text, '(por omisión)') from pg_class c where c.oid = to_regclass('campo.reporte_datos_sensibles')), 'NO EXISTE')
  union all
  select 8001, '8 public.geoportal_campo_analisis_observar', case when exists (select 1 from pg_proc where proname = 'geoportal_campo_analisis_observar') then 'YA EXISTE' else 'LIBRE' end
) z
order by o, k;
