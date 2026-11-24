-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 05 — GUARDIA (no aplica nada si la base no es la esperada)
-- Se niega si:
--   · el esquema reparto o alguna public.geoportal_reparto_* ya existen (el paquete no se reaplica: para rehacerlo, primero la reversa);
--   · cambió alguna de las funciones de campo que el reparto LLAMA sin tocarlas (md5 de producción del 23-nov): campo.f_verificar, campo.f_autorizar_supervision,
--     campo.f_actividades_persona, campo.f_persona_comercial y campo.f_quien_puede.
--     NO se exige la huella del conjunto de campo: el paquete de Investigación y Análisis (Code B) se publica antes y la cambia (§6 del encargo); el reparto
--     no crea ni reemplaza nada en campo, y la verificación comprueba que la huella de campo quedó igual que antes de la migración;
--   · la actividad «reparto» no existe o no está activa en campo.actividades, u otra actividad ya se llama «Supervisión de reparto» (este paquete la crea:
--     supervision_reparto, decisión de David del 23-nov);
--   · bi.v_rutas_geoportal no es una vista con exactamente sus 6 columnas de texto (contrato, periodo_carga, ciclo, ruta, consecutivo_ruta, consecutivo_predio)
--     y con su definición de producción («el último período»: md5 {{MD5_V_RUTAS}}, consulta A del 23-nov);
--   · hechos.rutas_consecutivos (la lee la vista; las pruebas escriben en ella dentro del ensayo) no es una tabla con sus 9 columnas de texto, sin NOT NULL ni
--     defaults, sin CHECK y sin disparadores propios (como en producción: consulta A del 23-nov);
--   · public.cartera_suscripcion no tiene sus 23 columnas de producción (nombre, tipo, NOT NULL y default) o le falta el índice por contrato;
--   · scrr.v_calendario_vigente no es una vista con su definición de producción (md5 {{MD5_V_CALENDARIO}}) o scrr.calendario_ciclos no es una tabla con sus
--     8 columnas, sus 7 restricciones (md5 {{MD5_RESTRICCIONES_CALENDARIO}}) y su disparador de solo inserción (el reparto lee etapas->>'reparto'; no los toca;
--     las pruebas escriben fechas de prueba dentro del ensayo);
--   · no existe el rol homelab_lectura (el Dell: USAGE sobre reparto y SELECT sobre cada tabla, cambio de D2 del 23-nov);
--   · public.geoportal_lista_blanca o public.geoportal_auditoria no tienen las columnas que se usan; falta redes.f_funciones_sin_where().
-- No toca las 4 funciones de permisos (geoportal_admin_permisos, geoportal_mis_permisos, geoportal_puede, geoportal_admin_guardar).
-- =====================================================================
do $guardia$
declare v text; f record;
begin
  if to_regnamespace('reparto') is not null then
    raise exception 'GUARDIA REPARTO: el esquema reparto ya existe. Este paquete no se reaplica; si hay que rehacerlo, primero la reversa.';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%') then
    raise exception 'GUARDIA REPARTO: ya hay funciones public.geoportal_reparto_*. Deténgase y avise.';
  end if;
  for f in select * from (values {{MD5_CAMPO_LLAMADAS}}) x(firma, md5) loop
    if to_regprocedure(f.firma) is null or md5(pg_get_functiondef(to_regprocedure(f.firma))) <> f.md5 then
      raise exception 'GUARDIA REPARTO: % no está o cambió (se esperaba md5 %). Deténgase y avise.', f.firma, f.md5;
    end if;
  end loop;
  if not exists (select 1 from campo.actividades a where a.codigo = 'reparto' and a.activa) then
    raise exception 'GUARDIA REPARTO: la actividad «reparto» no existe o no está activa en campo.actividades.';
  end if;
  if exists (select 1 from campo.actividades a where lower(a.nombre) = 'supervisión de reparto' and a.codigo <> 'supervision_reparto') then
    raise exception 'GUARDIA REPARTO: ya hay otra actividad llamada «Supervisión de reparto» en campo.actividades. Deténgase y avise.';
  end if;
  if (select relkind from pg_class where oid = to_regclass('bi.v_rutas_geoportal')) is distinct from 'v' then
    raise exception 'GUARDIA REPARTO: bi.v_rutas_geoportal no existe o no es una vista.';
  end if;
  select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum) into v
    from pg_attribute a where a.attrelid = 'bi.v_rutas_geoportal'::regclass and a.attnum > 0 and not a.attisdropped;
  if v is distinct from '{{COLUMNAS_V_RUTAS}}' then
    raise exception 'GUARDIA REPARTO: las columnas de bi.v_rutas_geoportal no son las esperadas: %', v;
  end if;
  if md5(pg_get_viewdef('bi.v_rutas_geoportal'::regclass, true)) <> '{{MD5_V_RUTAS}}' then
    raise exception 'GUARDIA REPARTO: la definición de bi.v_rutas_geoportal cambió (md5 %; se esperaba {{MD5_V_RUTAS}}). Deténgase y avise.',
      md5(pg_get_viewdef('bi.v_rutas_geoportal'::regclass, true));
  end if;
  if (select relkind from pg_class where oid = to_regclass('hechos.rutas_consecutivos')) is distinct from 'r' then
    raise exception 'GUARDIA REPARTO: hechos.rutas_consecutivos no existe o no es una tabla.';
  end if;
  select string_agg(column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, ''), ',' order by ordinal_position) into v
    from information_schema.columns where table_schema = 'hechos' and table_name = 'rutas_consecutivos';
  if v is distinct from '{{COLUMNAS_HECHOS_RUTAS}}' then
    raise exception 'GUARDIA REPARTO: las columnas de hechos.rutas_consecutivos (nombre:tipo:nulable:default) no son las esperadas: %', v;
  end if;
  if exists (select 1 from pg_trigger t where t.tgrelid = 'hechos.rutas_consecutivos'::regclass and not t.tgisinternal)
     or exists (select 1 from pg_constraint c where c.conrelid = 'hechos.rutas_consecutivos'::regclass) then
    raise exception 'GUARDIA REPARTO: hechos.rutas_consecutivos tiene disparadores o restricciones que el doble local no tiene. Deténgase y avise.';
  end if;
  if (select relkind from pg_class where oid = to_regclass('public.cartera_suscripcion')) is distinct from 'r' then
    raise exception 'GUARDIA REPARTO: public.cartera_suscripcion no existe o no es una tabla.';
  end if;
  select string_agg(column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, ''), ',' order by ordinal_position) into v
    from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion';
  if v is distinct from '{{COLUMNAS_SUSCRIPCION}}' then
    raise exception 'GUARDIA REPARTO: las columnas de public.cartera_suscripcion (nombre:tipo:nulable:default) no son las esperadas: %', v;
  end if;
  if not exists (select 1 from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
                  where i.indrelid = 'public.cartera_suscripcion'::regclass and i.indnatts = 1 and a.attname = 'contrato') then
    raise exception 'GUARDIA REPARTO: public.cartera_suscripcion no tiene índice por contrato (la búsqueda sin ruta lo necesita).';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_lista_blanca'
        and (column_name, data_type) in (('email', 'text'), ('nombre', 'text'))) <> 2 then
    raise exception 'GUARDIA REPARTO: a public.geoportal_lista_blanca le faltan email o nombre (text).';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_auditoria'
        and column_name in ('email', 'accion', 'referencia', 'detalle', 'ip')) <> 5 then
    raise exception 'GUARDIA REPARTO: a public.geoportal_auditoria le faltan columnas.';
  end if;
  -- calendario de reparto (scrr, publicado: huella 722fc84b… del 23-nov)
  if (select relkind from pg_class where oid = to_regclass('scrr.v_calendario_vigente')) is distinct from 'v'
     or md5(pg_get_viewdef('scrr.v_calendario_vigente'::regclass, true)) <> '{{MD5_V_CALENDARIO}}' then
    raise exception 'GUARDIA REPARTO: scrr.v_calendario_vigente no existe o su definición cambió (se esperaba md5 {{MD5_V_CALENDARIO}}). Deténgase y avise.';
  end if;
  if (select relkind from pg_class where oid = to_regclass('scrr.calendario_ciclos')) is distinct from 'r' then
    raise exception 'GUARDIA REPARTO: scrr.calendario_ciclos no existe o no es una tabla.';
  end if;
  select string_agg(column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, ''), ',' order by ordinal_position) into v
    from information_schema.columns where table_schema = 'scrr' and table_name = 'calendario_ciclos';
  if v is distinct from '{{COLUMNAS_CALENDARIO}}' then
    raise exception 'GUARDIA REPARTO: las columnas de scrr.calendario_ciclos (nombre:tipo:nulable:default) no son las esperadas: %', v;
  end if;
  if (select md5(string_agg(c.conname || '=' || pg_get_constraintdef(c.oid), ' | ' order by c.conname)) from pg_constraint c where c.conrelid = 'scrr.calendario_ciclos'::regclass)
       is distinct from '{{MD5_RESTRICCIONES_CALENDARIO}}'
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'scrr.calendario_ciclos'::regclass and not t.tgisinternal and t.tgname = 'calendario_ciclos_solo_insercion') then
    raise exception 'GUARDIA REPARTO: las restricciones o el disparador de solo inserción de scrr.calendario_ciclos no son los de producción. Deténgase y avise.';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'homelab_lectura') then
    raise exception 'GUARDIA REPARTO: no existe el rol homelab_lectura (respaldo del Dell).';
  end if;
  if to_regprocedure('redes.f_funciones_sin_where()') is null or to_regprocedure('public.geoportal_es_admin(text)') is null then
    raise exception 'GUARDIA REPARTO: falta redes.f_funciones_sin_where() o public.geoportal_es_admin(text).';
  end if;
end $guardia$;
