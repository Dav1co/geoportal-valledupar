-- REPARTO DE FACTURAS · COMMIT 1 (SQL) · ENSAYO (termina en ERROR esperado; no deja nada) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
create temp table ztrep_antes as select f, md5(pg_get_functiondef(to_regprocedure(f))) as md5 from unnest(array['public.geoportal_puede(text,text)', 'public.geoportal_mis_permisos(text)', 'public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)', 'public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)']) f
  union all select 'campo', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'));
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
--     y con su definición de producción («el último período»: md5 51da701454deeee5accfd2163a9c8e31, consulta A del 23-nov);
--   · hechos.rutas_consecutivos (la lee la vista; las pruebas escriben en ella dentro del ensayo) no es una tabla con sus 9 columnas de texto, sin NOT NULL ni
--     defaults, sin CHECK y sin disparadores propios (como en producción: consulta A del 23-nov);
--   · public.cartera_suscripcion no tiene sus 23 columnas de producción (nombre, tipo, NOT NULL y default) o le falta el índice por contrato;
--   · scrr.v_calendario_vigente no es una vista con su definición de producción (md5 64f9c515a0323a72737b950afaf4a741) o scrr.calendario_ciclos no es una tabla con sus
--     8 columnas, sus 7 restricciones (md5 f09f069a5ec1fd32518a9444bcb18ed2) y su disparador de solo inserción (el reparto lee etapas->>'reparto'; no los toca;
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
  for f in select * from (values ('campo.f_verificar(text,text)', '6133b5c36189e31743270064c8398b8a'), ('campo.f_autorizar_supervision(text)', '5ac3368fa5f3a6347328285501894aec'), ('campo.f_actividades_persona(text)', '69bc9bd73d5797b826b3e504c1d92070'), ('campo.f_persona_comercial(text)', '99af03344249f7260357528096e92829'), ('campo.f_quien_puede(text)', '5a381a87f432b8d2a6c88ad98a13fe3c')) x(firma, md5) loop
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
  if v is distinct from 'contrato:text,periodo_carga:text,ciclo:text,ruta:text,consecutivo_ruta:text,consecutivo_predio:text' then
    raise exception 'GUARDIA REPARTO: las columnas de bi.v_rutas_geoportal no son las esperadas: %', v;
  end if;
  if md5(pg_get_viewdef('bi.v_rutas_geoportal'::regclass, true)) <> '51da701454deeee5accfd2163a9c8e31' then
    raise exception 'GUARDIA REPARTO: la definición de bi.v_rutas_geoportal cambió (md5 %; se esperaba 51da701454deeee5accfd2163a9c8e31). Deténgase y avise.',
      md5(pg_get_viewdef('bi.v_rutas_geoportal'::regclass, true));
  end if;
  if (select relkind from pg_class where oid = to_regclass('hechos.rutas_consecutivos')) is distinct from 'r' then
    raise exception 'GUARDIA REPARTO: hechos.rutas_consecutivos no existe o no es una tabla.';
  end if;
  select string_agg(column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, ''), ',' order by ordinal_position) into v
    from information_schema.columns where table_schema = 'hechos' and table_name = 'rutas_consecutivos';
  if v is distinct from 'ciclo:text:YES:,consecutivo_ruta:text:YES:,ruta:text:YES:,contrato:text:YES:,direccion:text:YES:,consecutivo_predio:text:YES:,periodo:text:YES:,archivo_origen:text:YES:,fecha_carga:text:YES:' then
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
  if v is distinct from 'id:bigint:NO:nextval(''cartera_suscripcion_id_seq''::regclass),contrato:text:NO:,estado:text:YES:,identificacion:text:YES:,nombre:text:YES:,correo:text:YES:,telefono:text:YES:,direccion:text:YES:,barrio:text:YES:,categoria:text:YES:,subcategoria:text:YES:,ciclo:text:YES:,facturas_pendientes:numeric:YES:,deuda_total:numeric:YES:,saldo_pendiente:numeric:YES:,saldo_a_favor:numeric:YES:,valor_reclamo:numeric:YES:,saldo_financiado:numeric:YES:,serial_medidor:text:YES:,codigo_reparto:text:YES:,ruta:text:YES:,periodo_carga:text:NO:,cargado_en:timestamp with time zone:NO:now()' then
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
     or md5(pg_get_viewdef('scrr.v_calendario_vigente'::regclass, true)) <> '64f9c515a0323a72737b950afaf4a741' then
    raise exception 'GUARDIA REPARTO: scrr.v_calendario_vigente no existe o su definición cambió (se esperaba md5 64f9c515a0323a72737b950afaf4a741). Deténgase y avise.';
  end if;
  if (select relkind from pg_class where oid = to_regclass('scrr.calendario_ciclos')) is distinct from 'r' then
    raise exception 'GUARDIA REPARTO: scrr.calendario_ciclos no existe o no es una tabla.';
  end if;
  select string_agg(column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, ''), ',' order by ordinal_position) into v
    from information_schema.columns where table_schema = 'scrr' and table_name = 'calendario_ciclos';
  if v is distinct from 'periodo:character:NO:,ciclo:smallint:NO:,pago_oportuno:date:NO:,fecha_suspension:date:NO:,etapas:jsonb:NO:''{}''::jsonb,motivo:text:YES:,autor:text:NO:,vigente_desde:timestamp with time zone:NO:clock_timestamp()' then
    raise exception 'GUARDIA REPARTO: las columnas de scrr.calendario_ciclos (nombre:tipo:nulable:default) no son las esperadas: %', v;
  end if;
  if (select md5(string_agg(c.conname || '=' || pg_get_constraintdef(c.oid), ' | ' order by c.conname)) from pg_constraint c where c.conrelid = 'scrr.calendario_ciclos'::regclass)
       is distinct from 'f09f069a5ec1fd32518a9444bcb18ed2'
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

-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 10 — esquema, utilidades, parámetros y tablas (todas de solo inserción)
-- Decisiones de David (23-nov, §6 del encargo): el REPARTIDOR escoge su ruta (ciclo y luego ruta) entre tres orígenes:
--   «anterior» = ruta del último período cargado (bi.v_rutas_geoportal); «nueva» = archivo de una ruta o de un ciclo que cargó el supervisor;
--   «inventada» = sin ruta: busca el contrato y el orden en que entrega queda como su ruta real. No hay asignación por persona.
-- Cada vez que un repartidor abre una ruta en un día nace (o se retoma) una JORNADA con su lista CONGELADA (la recarga mensual de rutas borra el período).
-- Esquema cerrado a anon, authenticated y service_role: todo pasa por las RPC public.geoportal_reparto_* (SECURITY DEFINER), que solo ejecuta service_role.
-- Sin PostGIS (portabilidad): el XY se guarda en grados (lon, lat) con su precisión.
-- «Ya entregada» va por el CALENDARIO DE REPARTO (David, 23-nov): scrr.v_calendario_vigente, etapas->>'reparto' de cada (período, ciclo). Al abrir una ruta,
-- el período que se reparte es el último cuya fecha de reparto ya llegó para ese ciclo; cada entrega guarda ese período, y una factura está entregada si ya
-- tiene una entrega vigente de ese período. Si al ciclo le falta la fecha de reparto: aviso en pantalla y respaldo de 15 días (parámetro respaldo_dias).
-- Sin ruta: el ciclo del contrato; si no tiene ciclo, el mes del día. El reparto LEE el calendario; no lo toca.
-- =====================================================================

create schema reparto;
revoke all on schema reparto from public, anon, authenticated, service_role;
comment on schema reparto is 'Reparto de facturas con XY (Comercial, 23-nov-2026). Solo por RPC public.geoportal_reparto_*. Nada se borra: una entrega o un archivo equivocado se anulan con motivo.';

-- Disparador común: nada se actualiza ni se borra
create function reparto.f_solo_insercion() returns trigger
language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'La tabla %.% es de solo inserción: no se actualiza ni se borra (se anula con motivo)', tg_table_schema, tg_table_name
    using errcode = '55000', hint = 'msg_usuario';
end $$;

-- Error con mensaje para el usuario (la Edge muestra el texto cuando el HINT es msg_usuario)
create function reparto.f_err(p_mensaje text, p_codigo text default '22023') returns void
language plpgsql set search_path = pg_catalog as $$
begin
  raise exception '%', p_mensaje using errcode = p_codigo, hint = 'msg_usuario';
end $$;

-- Número seguro desde el texto de las rutas (todo text en hechos): solo dígitos (con «.0» opcional); lo demás, nulo
create function reparto.f_num(p text) returns numeric
language sql immutable parallel safe set search_path = pg_catalog as $$
  select case when btrim(coalesce(p, '')) ~ '^[0-9]{1,15}(\.0+)?$' then btrim(p)::numeric else null end
$$;

-- Contrato válido: solo dígitos, de 1 a 12
create function reparto.f_contrato(p text) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select case when btrim(coalesce(p, '')) ~ '^[0-9]{1,12}$' then btrim(p) else null end
$$;

-- Fecha segura desde el texto del calendario (aaaa-mm-dd); lo demás, nulo
create function reparto.f_fecha(p text) returns date
language plpgsql immutable set search_path = pg_catalog as $$
begin
  if p is null or btrim(p) !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then return null; end if;
  return btrim(p)::date;
exception when others then return null;
end $$;

-- Hoy en Valledupar
create function reparto.f_hoy() returns date
language sql stable set search_path = pg_catalog as $$ select (now() at time zone 'America/Bogota')::date $$;

-- 1. Parámetros versionados (una fila nueva por cambio; la vigente es la última)
create table reparto.parametros (
  id         bigint      generated always as identity primary key,
  clave      text        not null check (clave ~ '^[a-z][a-z0-9_]{1,59}$'),
  valor      jsonb       not null,
  nota       text        check (nota is null or length(nota) <= 300),
  autor      text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en  timestamptz not null default now()
);
create view reparto.v_parametros_vigentes as
  select distinct on (clave) clave, valor, autor, creado_en from reparto.parametros order by clave, id desc;

create function reparto.f_param(p_clave text) returns jsonb
language plpgsql stable security definer set search_path = reparto, pg_temp as $$
declare v jsonb;
begin
  select valor into v from reparto.v_parametros_vigentes where clave = p_clave;
  if v is null then raise exception 'Falta el parámetro %', p_clave using errcode = '55000'; end if;
  return v;
end $$;

-- 2. Archivos de ruta o de ciclo que carga el supervisor (origen «nueva»)
create table reparto.lotes (
  id              uuid        primary key default gen_random_uuid(),
  nombre_archivo  text        not null check (length(btrim(nombre_archivo)) between 1 and 200),
  archivo_sha256  text        not null check (archivo_sha256 ~ '^[0-9a-f]{64}$'),
  tipo            text        not null check (tipo in ('ruta', 'ciclo')),
  ciclo           text        not null check (ciclo ~ '^[0-9]{1,4}$'),
  ruta            text        check (ruta is null or ruta ~ '^[A-Za-z0-9 _.-]{1,20}$'),
  filas           integer     not null check (filas between 1 and 20000),
  sin_registro    integer     not null default 0 check (sin_registro >= 0),   -- contratos que no están en rutas ni en cartera (P5: se aceptan con aviso)
  autor           text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en       timestamptz not null default now(),
  check ((tipo = 'ruta') = (ruta is not null))
);
create index lotes_creado_idx on reparto.lotes (creado_en desc);

create table reparto.lote_filas (
  lote_id   uuid    not null references reparto.lotes (id),
  orden     integer not null check (orden >= 1),
  contrato  text    not null check (contrato ~ '^[0-9]{1,12}$'),
  primary key (lote_id, orden),
  unique (lote_id, contrato)
);

create table reparto.lotes_anulados (
  lote_id    uuid        primary key references reparto.lotes (id),
  motivo     text        not null check (length(btrim(motivo)) between 10 and 300),
  autor      text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en  timestamptz not null default now()
);

-- 3. Jornadas: una por (fecha, repartidor, fuente). La fuente es la ruta exacta de donde salió la lista:
--    'anterior:<periodo>:<ciclo>:<ruta>' · 'nueva:<lote_id>' · 'inventada'
create table reparto.jornadas (
  id          bigint      generated always as identity primary key,
  fecha       date        not null,
  repartidor  text        not null check (repartidor = lower(repartidor) and position('@' in repartidor) > 1),
  origen      text        not null check (origen in ('anterior', 'nueva', 'inventada')),
  fuente      text        not null check (length(fuente) between 9 and 120),
  periodo     text        check (periodo is null or periodo ~ '^[0-9]{6}$'),
  ciclo       text        check (ciclo is null or ciclo ~ '^[0-9]{1,4}$'),
  ruta        text        check (ruta is null or length(ruta) between 1 and 20),
  lote_id     uuid        references reparto.lotes (id),
  total       integer     not null check (total >= 0),
  periodo_reparto text    check (periodo_reparto is null or periodo_reparto ~ '^20[0-9]{2}(0[1-9]|1[0-2])$'),   -- el período que se reparte (calendario)
  reparto_desde   date,                                                    -- su fecha de reparto
  respaldo        boolean not null default false,                         -- al ciclo le falta la fecha de reparto: ventana de respaldo
  creado_en   timestamptz not null default now(),
  unique (fecha, repartidor, fuente),
  check ((periodo_reparto is null) = (reparto_desde is null)),
  check (case when origen = 'inventada' then periodo_reparto is null and not respaldo else respaldo = (periodo_reparto is null) end),
  check ((origen = 'anterior') = (periodo is not null and ruta is not null)),
  check ((origen = 'nueva') = (lote_id is not null)),
  check ((origen = 'inventada') = (ciclo is null and total = 0)),
  check (origen = 'inventada' or ciclo is not null)
);
create index jornadas_fecha_idx on reparto.jornadas (fecha, repartidor);

-- La lista congelada de la jornada (orden de lectura 1…N; el repartidor no lo ve)
create table reparto.jornada_items (
  jornada_id     bigint  not null references reparto.jornadas (id),
  orden_lectura  integer not null check (orden_lectura >= 1),
  contrato       text    not null check (contrato ~ '^[0-9]{1,12}$'),
  primary key (jornada_id, orden_lectura),
  unique (jornada_id, contrato)
);

-- 4. Entregas: una fila por factura entregada, en el momento, con su XY
create table reparto.entregas (
  id             bigint       generated always as identity primary key,
  jornada_id     bigint       not null references reparto.jornadas (id),
  contrato       text         not null check (contrato ~ '^[0-9]{1,12}$'),
  consecutivo    integer      not null check (consecutivo >= 1),             -- orden REAL de entrega dentro de la jornada (no se renumera al anular)
  orden_lectura  integer      check (orden_lectura is null or orden_lectura >= 1),   -- copiado de la lista; nulo en «inventada»
  periodo_reparto text        check (periodo_reparto is null or periodo_reparto ~ '^20[0-9]{2}(0[1-9]|1[0-2])$'),   -- nulo = respaldo (sin fecha de reparto)
  lon            numeric(9,6) not null check (lon between -82 and -66),      -- Colombia continental e insular (grados)
  lat            numeric(8,6) not null check (lat between -5 and 14),
  precision_m    numeric(7,1) not null check (precision_m >= 0 and precision_m <= 5000),
  por_buscador   boolean      not null default false,                         -- P3: se tocó desde el buscador y no desde las casillas
  id_cliente     uuid         not null unique,                                -- P3: un uuid por toque; el reintento devuelve la misma entrega
  autor          text         not null check (autor = lower(autor) and position('@' in autor) > 1),
  registrado_en  timestamptz  not null default now(),                         -- hora del servidor
  unique (jornada_id, consecutivo)
);
create index entregas_contrato_idx on reparto.entregas (contrato, registrado_en desc);
create index entregas_fecha_idx on reparto.entregas (registrado_en);

create table reparto.entregas_anuladas (
  entrega_id  bigint      primary key references reparto.entregas (id),
  motivo      text        not null check (length(btrim(motivo)) between 10 and 300),
  autor       text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en   timestamptz not null default now()
);

-- Solo inserción en todas
do $$
declare t text;
begin
  foreach t in array array['parametros', 'lotes', 'lote_filas', 'lotes_anulados', 'jornadas', 'jornada_items', 'entregas', 'entregas_anuladas'] loop
    execute format('create trigger t_solo_insercion before update or delete on reparto.%I for each row execute function reparto.f_solo_insercion()', t);
    execute format('create trigger t_solo_insercion_trunc before truncate on reparto.%I for each statement execute function reparto.f_solo_insercion()', t);
  end loop;
end $$;

-- 5. Vistas: entregas con su estado, y el avance por jornada
create view reparto.v_entregas as
  select e.*, (a.entrega_id is not null) as anulada, a.motivo as motivo_anulacion, a.autor as anulada_por, a.creado_en as anulada_en
    from reparto.entregas e left join reparto.entregas_anuladas a on a.entrega_id = e.id;

-- El período que se reparte HOY para un ciclo: el último del calendario vigente cuya fecha de reparto (etapas->>'reparto') ya llegó. Sin fila: el ciclo no tiene
-- fecha de reparto (respaldo). Solo lee scrr.v_calendario_vigente.
create function reparto.f_periodo_reparto(p_ciclo text) returns table (periodo text, desde date)
language sql stable security definer set search_path = reparto, scrr, pg_temp as $$
  select v.periodo::text, reparto.f_fecha(v.etapas ->> 'reparto')
    from scrr.v_calendario_vigente v
   where btrim(coalesce(p_ciclo, '')) ~ '^[0-9]{1,2}$' and v.ciclo = btrim(p_ciclo)::smallint
     and reparto.f_fecha(v.etapas ->> 'reparto') <= reparto.f_hoy()
   order by v.periodo desc limit 1
$$;

-- Comienzo de la ventana de respaldo (parámetro respaldo_dias: días calendario contando hoy), cuando al ciclo le falta la fecha de reparto
create function reparto.f_desde_respaldo() returns timestamptz
language sql stable security definer set search_path = reparto, pg_temp as $$
  select ((reparto.f_hoy() - ((reparto.f_param('respaldo_dias'))::int - 1))::timestamp at time zone 'America/Bogota')
$$;

-- ¿Este contrato ya tiene una entrega vigente del período que se reparte (cualquier origen y cualquier repartidor)? Regla de una sola entrega por factura.
--  · con período: una entrega de ese período, o una de respaldo (sin período) hecha desde su fecha de reparto;
--  · sin período (respaldo): cualquier entrega de los últimos respaldo_dias días.
create function reparto.f_entrega_vigente(p_contrato text, p_periodo text, p_desde date) returns bigint
language sql stable security definer set search_path = reparto, pg_temp as $$
  select e.id from reparto.entregas e
   where e.contrato = p_contrato
     and not exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = e.id)
     and case when p_periodo is not null
              then e.periodo_reparto = p_periodo or (e.periodo_reparto is null and e.registrado_en >= (p_desde::timestamp at time zone 'America/Bogota'))
              else e.registrado_en >= reparto.f_desde_respaldo() end
   order by e.registrado_en desc limit 1
$$;

-- Estado de la lista de una jornada: cada contrato con su orden de lectura, si ya se entregó (en la ventana, por cualquiera) y si quedó saltado.
-- Saltado = pendiente con orden de lectura menor que el mayor orden de lectura ya entregado EN ESTA jornada TOCANDO LA LISTA (David, 24-nov: lo entregado con el
-- buscador NO mueve el punto de avance; el supervisor ve el orden real completo en el detalle, columna «Habría sido»).
create function reparto.f_estado_lista(p_jornada bigint) returns table (orden_lectura integer, contrato text, entregada boolean, saltado boolean)
language sql stable security definer set search_path = reparto, pg_temp as $$
  with j as (select jo.periodo_reparto, jo.reparto_desde from reparto.jornadas jo where jo.id = p_jornada),
       i as (select it.orden_lectura, it.contrato, (reparto.f_entrega_vigente(it.contrato, j.periodo_reparto, j.reparto_desde) is not null) as entregada
               from reparto.jornada_items it, j where it.jornada_id = p_jornada),
       m as (select max(e.orden_lectura) as maximo from reparto.entregas e
              where e.jornada_id = p_jornada and not e.por_buscador and not exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = e.id))
  select i.orden_lectura, i.contrato, i.entregada, (not i.entregada and i.orden_lectura < coalesce(m.maximo, 0))
    from i, m
$$;

-- Avance por jornada (lo lee el supervisor)
create view reparto.v_avance as
  select j.id as jornada_id, j.fecha, j.repartidor, j.origen, j.periodo, j.ciclo, j.ruta, j.lote_id, l.nombre_archivo, j.total,
         j.periodo_reparto, j.reparto_desde, j.respaldo,
         (select count(*) from reparto.entregas e where e.jornada_id = j.id and not exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = e.id)) as entregadas,
         (select count(*) from reparto.entregas e where e.jornada_id = j.id and exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = e.id)) as anuladas,
         (select max(e.registrado_en) from reparto.entregas e where e.jornada_id = j.id and not exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = e.id)) as ultima
    from reparto.jornadas j left join reparto.lotes l on l.id = j.lote_id;

-- Auditoría de lo que hace el supervisor (mismo registro que el SCRR)
create function reparto.f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values (lower(p_email), p_accion, p_ref, p_detalle, p_ip);
$$;

-- Quién entra
-- Repartidor: modo campo, Personal de Comercial y la actividad «reparto» (propia o por cuadrilla), el mismo criterio de campo.f_quien_puede('reparto').
-- El administrador pasa siempre (para revisar).
create function reparto.f_autorizar_repartidor(p_solicitante text) returns text
language plpgsql security definer set search_path = pg_catalog, public, campo, reparto as $$
declare v_email text := campo.f_verificar(p_solicitante, 'campo');
begin
  if public.geoportal_es_admin(v_email) then return v_email; end if;
  if not (campo.f_persona_comercial(v_email) and exists (select 1 from campo.f_actividades_persona(v_email) a where a.codigo = 'reparto')) then
    raise exception 'Sin permiso para esta función' using errcode = '42501';
  end if;
  return v_email;
end $$;

-- Supervisor de reparto (David, 23-nov, opción B «ahora»): quien tiene la actividad «supervision_reparto» en Personal de Comercial (modo campo), o el
-- administrador. dashboard_campo solo NO basta: son personas distintas a las del SCRR. No se tocan las 4 funciones de permisos ni scrr.
create function reparto.f_autorizar_supervisor(p_solicitante text) returns text
language plpgsql security definer set search_path = pg_catalog, public, campo, reparto as $$
declare v_email text := campo.f_verificar(p_solicitante, 'campo');
begin
  if public.geoportal_es_admin(v_email) then return v_email; end if;
  if not (campo.f_persona_comercial(v_email) and exists (select 1 from campo.f_actividades_persona(v_email) a where a.codigo = 'supervision_reparto')) then
    raise exception 'Sin permiso para esta función' using errcode = '42501';
  end if;
  return v_email;
end $$;

-- ¿Puede cambiar el calendario? (Cartera → Calendario exige dashboard_campo; el enlace «Cambiar en Calendario» solo aparece si es así). Solo informa.
create function reparto.f_puede_calendario(p_email text) returns boolean
language sql stable security definer set search_path = pg_catalog, public as $$
  select coalesce(public.geoportal_puede(lower(p_email), 'dashboard_campo'), false)
$$;

-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 20 — RPC del repartidor (y el contexto común)
-- Todas: SECURITY DEFINER, search_path fijo, solicitante = el correo del token (lo pone la Edge). Solo las ejecuta service_role.
-- Ninguna lleva UPDATE ni DELETE. Lo que lee de rutas: bi.v_rutas_geoportal (último período), nunca la tabla entera de hechos.
-- =====================================================================

-- Lista de la jornada para la pantalla: solo los códigos pendientes en orden de lectura (sin el número de orden), con su marca de saltado
create function reparto.f_lista(p_jornada bigint) returns jsonb
language sql stable security definer set search_path = reparto, public, pg_temp as $$
  select jsonb_build_object(
    'jornada', (select jsonb_build_object('id', j.id, 'fecha', j.fecha, 'origen', j.origen, 'periodo', j.periodo, 'ciclo', j.ciclo, 'ruta', j.ruta,
                                          'lote_id', j.lote_id, 'nombre_archivo', l.nombre_archivo, 'total', j.total,
                                          'periodo_reparto', j.periodo_reparto, 'reparto_desde', j.reparto_desde, 'respaldo', j.respaldo,
                                          -- aviso en pantalla cuando al ciclo le falta la fecha de reparto (David, 23-nov)
                                          'aviso', case when j.respaldo then format('Al ciclo %s le falta la fecha de reparto en el calendario: se toman como entregadas las facturas de los últimos %s días.',
                                                                                    j.ciclo, reparto.f_param('respaldo_dias')) end)
                  from reparto.jornadas j left join reparto.lotes l on l.id = j.lote_id where j.id = p_jornada),
    'entregadas_mias', (select count(*) from reparto.entregas e where e.jornada_id = p_jornada and not exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = e.id)),
    'siguiente', (select coalesce(max(e.consecutivo), 0) + 1 from reparto.entregas e where e.jornada_id = p_jornada),
    'pendientes', (select coalesce(jsonb_agg(jsonb_build_object('c', s.contrato, 's', s.saltado) order by s.orden_lectura), '[]'::jsonb)
                     from reparto.f_estado_lista(p_jornada) s where not s.entregada),
    'ultimas', (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'contrato', u.contrato, 'consecutivo', u.consecutivo, 'hora', u.registrado_en) order by u.consecutivo desc), '[]'::jsonb)
                  from (select e.id, e.contrato, e.consecutivo, e.registrado_en from reparto.entregas e
                         where e.jornada_id = p_jornada and not exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = e.id)
                         order by e.consecutivo desc limit 5) u))
$$;

-- Perfil LIVIANO (commit 3): ¿es repartidor y/o supervisor de reparto? No lee rutas. Lo pide Formatos de campo al abrirse, para mostrar o no las entradas
-- «Reparto de facturas»: quien tiene el modo campo sin ninguna de las dos actividades recibe falso y falso (200); sin el modo campo, 42501.
create function public.geoportal_reparto_perfil(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := campo.f_verificar(p_solicitante, 'campo'); v_rep boolean := false; v_sup boolean := false;
begin
  begin perform reparto.f_autorizar_repartidor(v_email); v_rep := true; exception when sqlstate '42501' then null; end;
  begin perform reparto.f_autorizar_supervisor(v_email); v_sup := true; exception when sqlstate '42501' then null; end;
  return jsonb_build_object('es_repartidor', v_rep, 'es_supervisor', v_sup);
end $$;

-- Contexto: quién es (repartidor, supervisor o ambos), las rutas del último período por ciclo, los archivos vigentes y sus jornadas de hoy
create function public.geoportal_reparto_contexto(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text; v_rep boolean := false; v_sup boolean := false; v_rutas jsonb; v_periodo text;
begin
  begin v_email := reparto.f_autorizar_repartidor(p_solicitante); v_rep := true; exception when sqlstate '42501' then null; end;
  begin v_email := reparto.f_autorizar_supervisor(p_solicitante); v_sup := true; exception when sqlstate '42501' then null; end;
  if not (v_rep or v_sup) then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  -- rutas del último período (ciclo 9999 «sin ciclo» no se ofrece: P4). Una sola lectura agrupada de la vista.
  with g as (select r.periodo_carga, r.ciclo, r.ruta, count(distinct r.contrato) as n from bi.v_rutas_geoportal r
              -- filtros en línea (no reparto.f_contrato ni f_num: con su search_path fijo no se incrustan y se llamarían ~114 mil veces)
              where r.ciclo is distinct from '9999' and r.contrato ~ '^[0-9]{1,12}$' and btrim(r.ruta) <> '' and r.ciclo ~ '^[0-9]{1,4}$'
              group by 1, 2, 3),
       c as (select g.ciclo, jsonb_agg(jsonb_build_object('ruta', g.ruta, 'n', g.n) order by reparto.f_num(g.ruta) nulls last, g.ruta) as rutas
               from g group by g.ciclo)
  -- con cada ciclo, el período que se reparte hoy según el calendario (nulo: le falta la fecha de reparto → aviso y respaldo)
  select (select max(periodo_carga) from g),
         coalesce(jsonb_agg(jsonb_build_object('ciclo', c.ciclo, 'rutas', c.rutas,
                                               'reparto', (select jsonb_build_object('periodo', p.periodo, 'desde', p.desde) from reparto.f_periodo_reparto(c.ciclo) p))
                            order by reparto.f_num(c.ciclo)), '[]'::jsonb)
    into v_periodo, v_rutas from c;
  return jsonb_build_object(
    'correo', v_email, 'es_repartidor', v_rep, 'es_supervisor', v_sup, 'es_admin', public.geoportal_es_admin(v_email), 'hoy', reparto.f_hoy(),
    'puede_calendario', v_sup and reparto.f_puede_calendario(v_email),
    'periodo', v_periodo, 'anterior', v_rutas,
    'nuevas', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'nombre_archivo', l.nombre_archivo, 'tipo', l.tipo, 'ciclo', l.ciclo, 'ruta', l.ruta,
                                                            'filas', l.filas, 'cargado_en', l.creado_en,
                                                            'reparto', (select jsonb_build_object('periodo', p.periodo, 'desde', p.desde) from reparto.f_periodo_reparto(l.ciclo) p)) order by reparto.f_num(l.ciclo), l.ruta nulls first, l.creado_en desc), '[]'::jsonb)
                 from reparto.lotes l
                where not exists (select 1 from reparto.lotes_anulados a where a.lote_id = l.id)
                  and l.creado_en >= now() - make_interval(days => (reparto.f_param('lote_vigencia_dias'))::int)),
    'mis_jornadas_hoy', (select coalesce(jsonb_agg(jsonb_build_object('id', v.jornada_id, 'origen', v.origen, 'ciclo', v.ciclo, 'ruta', v.ruta, 'nombre_archivo', v.nombre_archivo,
                                                                     'total', v.total, 'entregadas', v.entregadas, 'ultima', v.ultima, 'periodo_reparto', v.periodo_reparto,
                                                                     'respaldo', v.respaldo) order by v.jornada_id), '[]'::jsonb)
                           from reparto.v_avance v where v.fecha = reparto.f_hoy() and v.repartidor = v_email),
    'parametros', jsonb_build_object('precision_mala_m', reparto.f_param('precision_mala_m'), 'respaldo_dias', reparto.f_param('respaldo_dias'),
                                     'tope_filas_lote', reparto.f_param('tope_filas_lote')));
end $$;

-- Empezar (o retomar) una jornada: el repartidor escoge el origen y la ruta. Idempotente: la misma persona, el mismo día y la misma fuente → la misma jornada.
create function public.geoportal_reparto_empezar(p_solicitante text, p_origen text, p_ciclo text default null, p_ruta text default null,
                                                 p_lote uuid default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_repartidor(p_solicitante); v_hoy date := reparto.f_hoy(); v_fuente text; v_periodo text; v_id bigint;
        v_lista text[]; v_lote record; v_ciclo text := btrim(coalesce(p_ciclo, '')); v_ruta text := btrim(coalesce(p_ruta, '')); v_rep record;
begin
  if p_origen is null or p_origen not in ('anterior', 'nueva', 'inventada') then perform reparto.f_err('Origen de la ruta no válido'); end if;
  if p_origen = 'anterior' then
    if v_ciclo !~ '^[0-9]{1,4}$' or v_ruta = '' or length(v_ruta) > 20 then perform reparto.f_err('Escoja el ciclo y la ruta'); end if;
    if v_ciclo = '9999' then perform reparto.f_err('El ciclo 9999 (sin ciclo) no se reparte por ruta: use «Repartir sin ruta»'); end if;
    select max(r.periodo_carga) into v_periodo from bi.v_rutas_geoportal r where r.ciclo = v_ciclo and r.ruta = v_ruta;
    if v_periodo is null then perform reparto.f_err('Esa ruta no está en el último período cargado'); end if;
    v_fuente := 'anterior:' || v_periodo || ':' || v_ciclo || ':' || v_ruta;
  elsif p_origen = 'nueva' then
    select l.* into v_lote from reparto.lotes l where l.id = p_lote;
    if not found then perform reparto.f_err('Ese archivo de ruta no existe'); end if;
    if exists (select 1 from reparto.lotes_anulados a where a.lote_id = p_lote) then perform reparto.f_err('El supervisor anuló ese archivo de ruta'); end if;
    if v_lote.creado_en < now() - make_interval(days => (reparto.f_param('lote_vigencia_dias'))::int) then perform reparto.f_err('Ese archivo de ruta ya venció: pida al supervisor que lo cargue de nuevo'); end if;
    v_fuente := 'nueva:' || p_lote::text;
    v_ciclo := v_lote.ciclo;
  else
    v_fuente := 'inventada';
  end if;
  -- el período que se reparte hoy para el ciclo de la ruta (calendario de reparto). Va en la fuente: si el calendario cambia, la lista es otra jornada.
  if p_origen <> 'inventada' then
    select p.periodo, p.desde into v_rep from reparto.f_periodo_reparto(v_ciclo) p;
    v_fuente := v_fuente || '|' || coalesce(v_rep.periodo, 'respaldo');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('reparto_jornada:' || v_hoy::text || ':' || v_email || ':' || v_fuente, 0));
  select j.id into v_id from reparto.jornadas j where j.fecha = v_hoy and j.repartidor = v_email and j.fuente = v_fuente;
  if v_id is not null then return reparto.f_lista(v_id) || jsonb_build_object('retomada', true); end if;
  if p_origen = 'anterior' then
    -- Orden de lectura (P1): consecutivo_ruta y, en los empates, consecutivo_predio; al final el contrato. Un contrato repetido en el período cuenta una vez (su primer lugar).
    select array_agg(x.contrato order by x.cr nulls last, x.cp nulls last, x.contrato) into v_lista
      from (select distinct on (r.contrato) r.contrato, reparto.f_num(r.consecutivo_ruta) as cr, reparto.f_num(r.consecutivo_predio) as cp
              from bi.v_rutas_geoportal r
             where r.ciclo = v_ciclo and r.ruta = v_ruta and r.periodo_carga = v_periodo and reparto.f_contrato(r.contrato) is not null
             order by r.contrato, reparto.f_num(r.consecutivo_ruta) nulls last, reparto.f_num(r.consecutivo_predio) nulls last) x;
    insert into reparto.jornadas (fecha, repartidor, origen, fuente, periodo, ciclo, ruta, total, periodo_reparto, reparto_desde, respaldo)
      values (v_hoy, v_email, 'anterior', v_fuente, v_periodo, v_ciclo, v_ruta, coalesce(cardinality(v_lista), 0), v_rep.periodo, v_rep.desde, v_rep.periodo is null)
      returning id into v_id;
  elsif p_origen = 'nueva' then
    select array_agg(f.contrato order by f.orden) into v_lista from reparto.lote_filas f where f.lote_id = p_lote;
    insert into reparto.jornadas (fecha, repartidor, origen, fuente, ciclo, ruta, lote_id, total, periodo_reparto, reparto_desde, respaldo)
      values (v_hoy, v_email, 'nueva', v_fuente, v_lote.ciclo, v_lote.ruta, p_lote, coalesce(cardinality(v_lista), 0), v_rep.periodo, v_rep.desde, v_rep.periodo is null)
      returning id into v_id;
  else
    insert into reparto.jornadas (fecha, repartidor, origen, fuente, total) values (v_hoy, v_email, 'inventada', v_fuente, 0) returning id into v_id;
  end if;
  if v_lista is not null then
    insert into reparto.jornada_items (jornada_id, orden_lectura, contrato) select v_id, u.o, u.c from unnest(v_lista) with ordinality u(c, o);
  end if;
  return reparto.f_lista(v_id) || jsonb_build_object('retomada', false);
end $$;

-- La lista de una jornada propia (para refrescar al volver la señal o tras recargar la página)
create function public.geoportal_reparto_lista(p_solicitante text, p_jornada bigint, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_repartidor(p_solicitante);
begin
  if not exists (select 1 from reparto.jornadas j where j.id = p_jornada and j.repartidor = v_email) then perform reparto.f_err('Esa lista no es suya', '42501'); end if;
  return reparto.f_lista(p_jornada);
end $$;

-- Registrar una entrega en el momento, con su XY. Doble toque y reintentos:
--  · el mismo id_cliente (uuid del toque) devuelve la MISMA entrega (repetida = true), sin error;
--  · un contrato con una entrega vigente del período que se reparte (cualquier repartidor u origen) no se registra otra vez; la entrega guarda ese período;
--  · el consecutivo se calcula bajo el bloqueo de la jornada: no hay dos iguales.
create function public.geoportal_reparto_entregar(p_solicitante text, p_jornada bigint, p_contrato text, p_lon numeric, p_lat numeric, p_precision_m numeric,
                                                  p_por_buscador boolean, p_id_cliente uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_repartidor(p_solicitante); v_c text := reparto.f_contrato(p_contrato); v_j record; v_orden integer;
        v_prev record; v_cons integer; v_id bigint; v_hora timestamptz; v_vig bigint; v_ciclo text; v_existe boolean;
        v_per text; v_desde date;
begin
  if p_id_cliente is null then perform reparto.f_err('Falta el identificador del toque'); end if;
  -- primero el bloqueo de la jornada: así un reintento que llega A LA VEZ espera al primero y después lo encuentra por su uuid
  select j.* into v_j from reparto.jornadas j where j.id = p_jornada for update;
  if not found or v_j.repartidor <> v_email then perform reparto.f_err('Esa lista no es suya', '42501'); end if;
  select e.id, e.consecutivo, e.contrato, e.autor, e.registrado_en into v_prev from reparto.entregas e where e.id_cliente = p_id_cliente;
  if found then
    if v_prev.autor <> v_email then perform reparto.f_err('Identificador de toque no válido'); end if;
    return jsonb_build_object('entrega_id', v_prev.id, 'consecutivo', v_prev.consecutivo, 'contrato', v_prev.contrato, 'registrado_en', v_prev.registrado_en, 'repetida', true);
  end if;
  if v_c is null then perform reparto.f_err('El código del contrato no es válido (solo números)'); end if;
  if p_lon is null or p_lat is null or p_precision_m is null then perform reparto.f_err('Sin ubicación del GPS: la entrega no se guardó. Active la ubicación e intente de nuevo.'); end if;
  if p_lon not between -82 and -66 or p_lat not between -5 and 14 or p_precision_m < 0 or p_precision_m > 5000 then
    perform reparto.f_err('La ubicación del GPS no es válida: la entrega no se guardó');
  end if;
  if v_j.fecha <> reparto.f_hoy() then perform reparto.f_err('Esta lista es de otro día: vuelva a escoger la ruta', '55000'); end if;
  if v_j.lote_id is not null and exists (select 1 from reparto.lotes_anulados a where a.lote_id = v_j.lote_id) then
    perform reparto.f_err('El supervisor anuló el archivo de esta ruta', '55000');
  end if;
  if v_j.origen = 'inventada' then
    -- sin ruta: el contrato debe existir; su ciclo (cartera o rutas) da el período que se reparte; sin ciclo, el mes del día (David, 23-nov)
    select true, s.ciclo into v_existe, v_ciclo from public.cartera_suscripcion s where s.contrato = v_c order by s.cargado_en desc limit 1;
    if v_existe is null then
      select true, r.ciclo into v_existe, v_ciclo from bi.v_rutas_geoportal r where r.contrato = v_c limit 1;
    end if;
    if v_existe is null then perform reparto.f_err('No hay ningún contrato con el código ' || v_c); end if;
    if btrim(coalesce(v_ciclo, '')) ~ '^0*[1-9][0-9]?$' then
      select p.periodo, p.desde into v_per, v_desde from reparto.f_periodo_reparto(ltrim(btrim(v_ciclo), '0')) p;   -- sin fila: respaldo
    else
      v_per := to_char(reparto.f_hoy(), 'YYYYMM'); v_desde := date_trunc('month', reparto.f_hoy())::date;
    end if;
  else
    select it.orden_lectura into v_orden from reparto.jornada_items it where it.jornada_id = p_jornada and it.contrato = v_c;
    if v_orden is null then perform reparto.f_err('El contrato ' || v_c || ' no está en esta ruta'); end if;
    v_per := v_j.periodo_reparto; v_desde := v_j.reparto_desde;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('reparto_contrato:' || v_c, 0));
  v_vig := reparto.f_entrega_vigente(v_c, v_per, v_desde);
  if v_vig is not null then
    select e.id, e.consecutivo, e.autor, e.registrado_en into v_prev from reparto.entregas e where e.id = v_vig;
    perform reparto.f_err(format('La factura del contrato %s ya se registró el %s%s', v_c,
              to_char(v_prev.registrado_en at time zone 'America/Bogota', 'DD/MM "a las" HH24:MI'),
              case when v_prev.autor = v_email then ' (entrega ' || v_prev.consecutivo || ')' else ', por otro repartidor' end), '23505');
  end if;
  select coalesce(max(e.consecutivo), 0) + 1 into v_cons from reparto.entregas e where e.jornada_id = p_jornada;
  begin
    insert into reparto.entregas (jornada_id, contrato, consecutivo, orden_lectura, periodo_reparto, lon, lat, precision_m, por_buscador, id_cliente, autor)
      values (p_jornada, v_c, v_cons, v_orden, v_per, round(p_lon, 6), round(p_lat, 6), round(p_precision_m, 1), coalesce(p_por_buscador, false), p_id_cliente, v_email)
      returning id, registrado_en into v_id, v_hora;
  exception when unique_violation then
    -- el mismo toque llegó dos veces a la vez: gana el primero y este devuelve el mismo
    select e.id, e.consecutivo, e.contrato, e.autor, e.registrado_en into v_prev from reparto.entregas e where e.id_cliente = p_id_cliente;
    if found and v_prev.autor = v_email then
      return jsonb_build_object('entrega_id', v_prev.id, 'consecutivo', v_prev.consecutivo, 'contrato', v_prev.contrato, 'registrado_en', v_prev.registrado_en, 'repetida', true);
    end if;
    raise;
  end;
  return jsonb_build_object('entrega_id', v_id, 'consecutivo', v_cons, 'contrato', v_c, 'registrado_en', v_hora, 'repetida', false,
                            'precision_mala', p_precision_m > (reparto.f_param('precision_mala_m'))::numeric, 'periodo_reparto', v_per, 'respaldo', v_per is null,
                            'aviso', case when v_per is null then format('Al ciclo %s le falta la fecha de reparto en el calendario: se revisó contra las entregas de los últimos %s días.',
                                                                         coalesce(v_ciclo, v_j.ciclo), reparto.f_param('respaldo_dias')) end);
end $$;

-- Anular una entrega con motivo (P7): el supervisor, cualquiera; el repartidor, solo las suyas del mismo día. Nada se borra y el consecutivo no se renumera.
create function public.geoportal_reparto_anular(p_solicitante text, p_entrega bigint, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text; v_sup boolean := false; v_e record; v_m text := btrim(coalesce(p_motivo, ''));
begin
  begin v_email := reparto.f_autorizar_supervisor(p_solicitante); v_sup := true; exception when sqlstate '42501' then null; end;
  if not v_sup then v_email := reparto.f_autorizar_repartidor(p_solicitante); end if;
  if length(v_m) not between 10 and 300 then perform reparto.f_err('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
  select e.* into v_e from reparto.entregas e where e.id = p_entrega;
  if not found then perform reparto.f_err('Esa entrega no existe'); end if;
  if not v_sup and (v_e.autor <> v_email or (v_e.registrado_en at time zone 'America/Bogota')::date <> reparto.f_hoy()) then
    perform reparto.f_err('Solo puede anular sus propias entregas de hoy; las demás las anula el supervisor', '42501');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('reparto_contrato:' || v_e.contrato, 0));
  if exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = p_entrega) then perform reparto.f_err('Esa entrega ya estaba anulada', '55000'); end if;
  insert into reparto.entregas_anuladas (entrega_id, motivo, autor) values (p_entrega, v_m, v_email);
  if v_sup then perform reparto.f_auditar(v_email, 'reparto_anular_entrega', p_entrega::text, jsonb_build_object('contrato', v_e.contrato), p_ip); end if;
  return jsonb_build_object('ok', true, 'entrega_id', p_entrega, 'contrato', v_e.contrato);
end $$;

-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 30 — RPC del supervisor: archivos de ruta, avance, detalle y mapa
-- Quién: el supervisor de campo (dashboard_campo) o el administrador (reparto.f_autorizar_supervisor → campo.f_autorizar_supervision).
-- Las filas de los archivos nunca se escriben en la auditoría (solo nombre, huella, tipo, ciclo, ruta y conteos).
-- =====================================================================

-- Cargar un archivo de una ruta o de un ciclo (plantilla: Contrato y, opcional, Orden). «Todo comienza con el archivo de rutas» (David, 24-nov):
--  · EL CICLO NO LO ESCRIBE EL SUPERVISOR: se deduce de los contratos según bi.v_rutas_geoportal (último período); si un contrato no está ahí, según
--    public.cartera_suscripcion (su fila más reciente); si discrepan, manda la tabla de rutas. La comparación es numérica («098» = «98»);
--  · si los contratos con ciclo conocido son de MÁS DE UN ciclo, se rechaza sin escribir nada, con el detalle por ciclo («98: 30 · 15: 10»);
--  · los contratos sin registro (ni en rutas ni en cartera) se aceptan con aviso, como antes, y NO cuentan para decidir el ciclo; si TODOS son sin registro,
--    el supervisor escoge el ciclo a mano (p_ciclo; si no viene, se le pide: «pide_ciclo»). Si el ciclo se deduce, p_ciclo se ignora;
--  · la ruta la escribe el supervisor, como rótulo, sin validarla contra los contratos;
--  · p_confirmar = false es la VISTA PREVIA: valida, deduce y devuelve el ciclo y los conteos sin escribir nada (la pantalla lo muestra antes de confirmar);
--  · forma: de 1 a tope_filas_lote filas; contrato solo dígitos (1 a 12) y sin repetir; Orden en todas las filas o en ninguna, entero ≥ 1 y sin repetir;
--    si hay errores no escribe nada y devuelve hasta 20, con su fila de Excel (la 1 es el encabezado);
--  · el mismo archivo (huella), de la misma persona, con el mismo tipo, ciclo y ruta, el mismo día y sin anular, devuelve el mismo lote (doble clic).
create function public.geoportal_reparto_lote_cargar(p_solicitante text, p_nombre text, p_sha256 text, p_tipo text, p_ciclo text, p_ruta text,
                                                     p_filas jsonb, p_confirmar boolean default true, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_tope integer := (reparto.f_param('tope_filas_lote'))::integer; v_n integer;
        v_err jsonb; v_id uuid; v_ciclo text; v_ruta text := nullif(btrim(coalesce(p_ruta, '')), ''); v_con_orden integer;
        v_sin integer; v_por_ciclo jsonb; v_ciclos integer; v_texto text; v_deducido boolean;
begin
  if p_tipo is null or p_tipo not in ('ruta', 'ciclo') then perform reparto.f_err('Indique si el archivo es de una ruta o de un ciclo'); end if;
  if p_tipo = 'ruta' and (v_ruta is null or v_ruta !~ '^[A-Za-z0-9 _.-]{1,20}$') then perform reparto.f_err('Indique la ruta (hasta 20 letras o números)'); end if;
  if p_tipo = 'ciclo' then v_ruta := null; end if;
  if length(btrim(coalesce(p_nombre, ''))) not between 1 and 200 then perform reparto.f_err('Nombre de archivo no válido'); end if;
  if coalesce(p_sha256, '') !~ '^[0-9a-f]{64}$' then perform reparto.f_err('Huella del archivo no válida'); end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then perform reparto.f_err('El archivo no trae filas'); end if;
  v_n := jsonb_array_length(p_filas);
  if v_n < 1 or v_n > v_tope then perform reparto.f_err(format('El archivo debe tener entre 1 y %s filas (trae %s)', v_tope, v_n)); end if;
  -- 1. la forma
  with f as (select x.o::integer + 1 as fila, x.v from jsonb_array_elements(p_filas) with ordinality x(v, o)),
       c as (select f.fila, f.v ->> 'contrato' as bruto, reparto.f_contrato(f.v ->> 'contrato') as contrato,
                    nullif(btrim(coalesce(f.v ->> 'orden', '')), '') as orden_txt from f),
       e as (select c.fila, 'Fila ' || c.fila || ': el contrato «' || left(coalesce(c.bruto, ''), 20) || '» no es válido (solo números, de 1 a 12)' as m from c where c.contrato is null
             union all
             select c.fila, 'Fila ' || c.fila || ': el contrato ' || c.contrato || ' está repetido' from c
              where c.contrato is not null and exists (select 1 from c c2 where c2.contrato = c.contrato and c2.fila < c.fila)
             union all
             select c.fila, 'Fila ' || c.fila || ': el Orden «' || left(c.orden_txt, 12) || '» no es un entero mayor que cero' from c
              where c.orden_txt is not null and c.orden_txt !~ '^[1-9][0-9]{0,6}$'
             union all
             select c.fila, 'Fila ' || c.fila || ': el Orden ' || c.orden_txt || ' está repetido' from c
              where c.orden_txt ~ '^[1-9][0-9]{0,6}$' and exists (select 1 from c c2 where c2.orden_txt = c.orden_txt and c2.fila < c.fila))
  select (select count(*) from c where c.orden_txt is not null), (select jsonb_agg(m order by fila) from (select * from e order by fila limit 20) z)
    into v_con_orden, v_err;
  if v_con_orden not in (0, v_n) then
    v_err := coalesce(v_err, '[]'::jsonb) || jsonb_build_array('La columna Orden debe venir en todas las filas o en ninguna');
  end if;
  if v_err is not null then return jsonb_build_object('ok', false, 'errores', v_err); end if;
  -- 2. el ciclo de cada contrato: rutas (último período) y, si no está, cartera; manda rutas; comparación numérica
  with f as (select distinct reparto.f_contrato(x.v ->> 'contrato') as contrato from jsonb_array_elements(p_filas) x(v)),
       r as (select distinct on (r.contrato) r.contrato, r.ciclo from bi.v_rutas_geoportal r
              where r.contrato in (select contrato from f) order by r.contrato, reparto.f_num(r.consecutivo_ruta) nulls last),
       s as (select distinct on (s.contrato) s.contrato, s.ciclo from public.cartera_suscripcion s
              where s.contrato in (select contrato from f) and not exists (select 1 from r where r.contrato = s.contrato) order by s.contrato, s.cargado_en desc),
       k as (select case when btrim(coalesce(x.ciclo, '')) ~ '^[0-9]{1,9}$' then (btrim(x.ciclo)::bigint)::text end as ciclo from (select ciclo from r union all select ciclo from s) x),
       g as (select k.ciclo, count(*) as n from k where k.ciclo is not null group by k.ciclo)
  select (select count(*) from f) - (select count(*) from r) - (select count(*) from s), (select count(*) from g),
         (select jsonb_agg(jsonb_build_object('ciclo', g.ciclo, 'contratos', g.n) order by g.n desc, g.ciclo::bigint) from g),
         (select string_agg(g.ciclo || ': ' || g.n, ' · ' order by g.n desc, g.ciclo::bigint) from g),
         (select min(g.ciclo) from g)
    into v_sin, v_ciclos, v_por_ciclo, v_texto, v_ciclo;
  if v_ciclos > 1 then
    return jsonb_build_object('ok', false, 'por_ciclo', v_por_ciclo,
      'errores', jsonb_build_array(format('El archivo tiene contratos de más de un ciclo: %s. Un archivo debe ser de un solo ciclo.', v_texto)));
  end if;
  v_deducido := v_ciclos = 1;
  if not v_deducido then
    v_ciclo := btrim(coalesce(p_ciclo, ''));
    if v_ciclo = '' then
      return jsonb_build_object('ok', false, 'pide_ciclo', true, 'sin_registro', v_sin,
        'errores', jsonb_build_array(format('Ninguno de los %s contratos está en las rutas ni en la cartera: escoja el ciclo a mano.', v_n)));
    end if;
    if v_ciclo !~ '^[0-9]{1,4}$' then perform reparto.f_err('Indique el ciclo (solo números)'); end if;
    v_ciclo := (v_ciclo::integer)::text;
  end if;
  if v_ciclo !~ '^[0-9]{1,4}$' then perform reparto.f_err(format('El ciclo deducido (%s) no es válido', v_ciclo)); end if;
  -- 3. vista previa: sin escribir nada
  if not coalesce(p_confirmar, true) then
    return jsonb_build_object('ok', true, 'previa', true, 'ciclo', v_ciclo, 'ciclo_deducido', v_deducido, 'filas', v_n, 'sin_registro', v_sin, 'por_ciclo', coalesce(v_por_ciclo, '[]'::jsonb));
  end if;
  -- 4. cargar (doble clic = el mismo lote)
  perform pg_advisory_xact_lock(hashtextextended('reparto_lote:' || v_email || ':' || p_sha256, 0));
  select l.id into v_id from reparto.lotes l
   where l.archivo_sha256 = p_sha256 and l.autor = v_email and l.tipo = p_tipo and l.ciclo = v_ciclo and l.ruta is not distinct from v_ruta
     and (l.creado_en at time zone 'America/Bogota')::date = reparto.f_hoy() and not exists (select 1 from reparto.lotes_anulados a where a.lote_id = l.id)
   order by l.creado_en desc limit 1;
  if v_id is not null then
    return jsonb_build_object('ok', true, 'lote_id', v_id, 'repetido', true, 'ciclo', v_ciclo, 'ciclo_deducido', v_deducido, 'filas', (select filas from reparto.lotes where id = v_id),
                              'sin_registro', (select sin_registro from reparto.lotes where id = v_id));
  end if;
  insert into reparto.lotes (nombre_archivo, archivo_sha256, tipo, ciclo, ruta, filas, sin_registro, autor)
    values (btrim(p_nombre), p_sha256, p_tipo, v_ciclo, v_ruta, v_n, v_sin, v_email) returning id into v_id;
  -- el orden: el de la columna Orden (renumerado 1…N) o, si no viene, el de las filas
  insert into reparto.lote_filas (lote_id, orden, contrato)
    select v_id, row_number() over (order by coalesce(nullif(btrim(coalesce(x.v ->> 'orden', '')), '')::integer, x.o::integer), x.o), reparto.f_contrato(x.v ->> 'contrato')
      from jsonb_array_elements(p_filas) with ordinality x(v, o);
  perform reparto.f_auditar(v_email, 'reparto_lote_cargar', v_id::text,
            jsonb_build_object('nombre', btrim(p_nombre), 'sha256', p_sha256, 'tipo', p_tipo, 'ciclo', v_ciclo, 'ciclo_deducido', v_deducido, 'ruta', v_ruta, 'filas', v_n, 'sin_registro', v_sin), p_ip);
  return jsonb_build_object('ok', true, 'lote_id', v_id, 'repetido', false, 'ciclo', v_ciclo, 'ciclo_deducido', v_deducido, 'filas', v_n, 'sin_registro', v_sin);
end $$;

create function public.geoportal_reparto_lote_anular(p_solicitante text, p_lote uuid, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_m text := btrim(coalesce(p_motivo, ''));
begin
  if length(v_m) not between 10 and 300 then perform reparto.f_err('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
  if not exists (select 1 from reparto.lotes l where l.id = p_lote) then perform reparto.f_err('Ese archivo de ruta no existe'); end if;
  perform pg_advisory_xact_lock(hashtextextended('reparto_lote_anular:' || p_lote::text, 0));
  if exists (select 1 from reparto.lotes_anulados a where a.lote_id = p_lote) then perform reparto.f_err('Ese archivo ya estaba anulado', '55000'); end if;
  insert into reparto.lotes_anulados (lote_id, motivo, autor) values (p_lote, v_m, v_email);
  perform reparto.f_auditar(v_email, 'reparto_lote_anular', p_lote::text, jsonb_build_object('motivo', v_m), p_ip);
  return jsonb_build_object('ok', true, 'lote_id', p_lote);
end $$;

-- Archivos cargados (los últimos 60 días), con su estado y cuántas jornadas salieron de cada uno
create function public.geoportal_reparto_lotes(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante);
begin
  return jsonb_build_object('lotes', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'nombre_archivo', l.nombre_archivo, 'tipo', l.tipo, 'ciclo', l.ciclo, 'ruta', l.ruta, 'filas', l.filas, 'autor', l.autor, 'cargado_en', l.creado_en,
      'vigente', a.lote_id is null and l.creado_en >= now() - make_interval(days => (reparto.f_param('lote_vigencia_dias'))::int),
      'anulado', a.lote_id is not null, 'motivo_anulacion', a.motivo, 'anulado_por', a.autor, 'anulado_en', a.creado_en,
      'jornadas', (select count(*) from reparto.jornadas j where j.lote_id = l.id)) order by l.creado_en desc), '[]'::jsonb)
    from reparto.lotes l left join reparto.lotes_anulados a on a.lote_id = l.id where l.creado_en >= now() - interval '60 days'));
end $$;

-- Avance de un día: por repartidor y ruta (una fila por jornada): total, entregadas, pendientes, saltadas, anuladas y la última entrega.
-- Las pendientes descuentan lo que entregó cualquier repartidor en la ventana (dos personas pueden repartir la misma ruta).
create function public.geoportal_reparto_avance(p_solicitante text, p_fecha date default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_fecha date := coalesce(p_fecha, reparto.f_hoy());
begin
  if v_fecha < date '2026-01-01' or v_fecha > reparto.f_hoy() then perform reparto.f_err('Fecha no válida'); end if;
  return jsonb_build_object('fecha', v_fecha, 'filas', (select coalesce(jsonb_agg(jsonb_build_object(
      'jornada_id', v.jornada_id, 'repartidor', v.repartidor, 'nombre', (select b.nombre from public.geoportal_lista_blanca b where b.email = v.repartidor),
      'origen', v.origen, 'periodo', v.periodo, 'ciclo', v.ciclo, 'ruta', v.ruta, 'nombre_archivo', v.nombre_archivo, 'total', v.total,
      'periodo_reparto', v.periodo_reparto, 'reparto_desde', v.reparto_desde, 'respaldo', v.respaldo,
      'entregadas', v.entregadas, 'anuladas', v.anuladas, 'ultima', v.ultima,
      'pendientes', case when v.origen = 'inventada' then null else s.pendientes end,
      'saltadas', case when v.origen = 'inventada' then null else s.saltadas end) order by v.repartidor, v.jornada_id), '[]'::jsonb)
    from reparto.v_avance v
    left join lateral (select count(*) filter (where not x.entregada) as pendientes, count(*) filter (where x.saltado) as saltadas
                         from reparto.f_estado_lista(v.jornada_id) x) s on true
   where v.fecha = v_fecha));
end $$;

-- Detalle de una jornada: el orden real (consecutivo) frente al de lectura, los saltados y las anuladas con su motivo
create function public.geoportal_reparto_detalle(p_solicitante text, p_jornada bigint, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante);
begin
  if not exists (select 1 from reparto.jornadas j where j.id = p_jornada) then perform reparto.f_err('Esa jornada no existe'); end if;
  return jsonb_build_object(
    'jornada', (select to_jsonb(v) - 'lote_id' || jsonb_build_object('nombre', (select b.nombre from public.geoportal_lista_blanca b where b.email = v.repartidor))
                  from reparto.v_avance v where v.jornada_id = p_jornada),
    'entregas', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'contrato', e.contrato, 'consecutivo', e.consecutivo, 'orden_lectura', e.orden_lectura,
                   'periodo_reparto', e.periodo_reparto,
                   'hora', e.registrado_en, 'lon', e.lon, 'lat', e.lat, 'precision_m', e.precision_m, 'por_buscador', e.por_buscador,
                   'anulada', e.anulada, 'motivo_anulacion', e.motivo_anulacion, 'anulada_por', e.anulada_por, 'anulada_en', e.anulada_en) order by e.consecutivo), '[]'::jsonb)
                   from reparto.v_entregas e where e.jornada_id = p_jornada),
    'saltados', (select coalesce(jsonb_agg(jsonb_build_object('contrato', s.contrato, 'orden_lectura', s.orden_lectura) order by s.orden_lectura), '[]'::jsonb)
                   from reparto.f_estado_lista(p_jornada) s where s.saltado),
    'pendientes', (select count(*) from reparto.f_estado_lista(p_jornada) s where not s.entregada));
end $$;

-- Mapa EN VIVO (David, 23-nov): los XY de un día (o de una jornada), numerados por el orden real. La pantalla lo consulta cada pocos segundos:
-- con p_despues (el último id que ya tiene) solo vienen los puntos nuevos, más la lista de ids anulados del día (pocos) para tacharlos.
create function public.geoportal_reparto_mapa(p_solicitante text, p_fecha date default null, p_jornada bigint default null, p_despues bigint default null,
                                              p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_fecha date := coalesce(p_fecha, reparto.f_hoy());
begin
  if v_fecha < date '2026-01-01' or v_fecha > reparto.f_hoy() then perform reparto.f_err('Fecha no válida'); end if;
  if p_despues is not null and p_despues < 0 then perform reparto.f_err('Cursor no válido'); end if;
  return (with j as (select jo.id, jo.repartidor from reparto.jornadas jo where jo.fecha = v_fecha and (p_jornada is null or jo.id = p_jornada)),
               e as (select e.*, j.repartidor from reparto.v_entregas e join j on j.id = e.jornada_id)
    select jsonb_build_object('fecha', v_fecha,
      'puntos', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'jornada_id', e.jornada_id, 'repartidor', e.repartidor, 'contrato', e.contrato, 'consecutivo', e.consecutivo,
                   'hora', e.registrado_en, 'lon', e.lon, 'lat', e.lat, 'precision_m', e.precision_m, 'anulada', e.anulada) order by e.jornada_id, e.consecutivo), '[]'::jsonb)
                   from e where p_despues is null or e.id > p_despues),
      'anuladas', (select coalesce(jsonb_agg(e.id order by e.id), '[]'::jsonb) from e where e.anulada),
      'ultimo_id', (select max(e.id) from e)));
end $$;

-- Calendario de reparto en SOLO LECTURA para el supervisor de reparto (David, 23-nov): lo llena quien tiene dashboard_campo en Cartera → Calendario.
-- Por ciclo: la fecha de reparto del período pedido (o nula: falta) y el período que se reparte hoy. «puede_cambiar» decide si se muestra el enlace.
create function public.geoportal_reparto_calendario(p_solicitante text, p_periodo text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto, scrr as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_per text := coalesce(nullif(btrim(coalesce(p_periodo, '')), ''), to_char(reparto.f_hoy(), 'YYYYMM'));
begin
  if v_per !~ '^20[0-9]{2}(0[1-9]|1[0-2])$' then perform reparto.f_err('Período no válido (aaaamm)'); end if;
  return jsonb_build_object('periodo', v_per, 'hoy', reparto.f_hoy(), 'puede_cambiar', reparto.f_puede_calendario(v_email),
    'ciclos', (select coalesce(jsonb_agg(jsonb_build_object('ciclo', v.ciclo, 'reparto', reparto.f_fecha(v.etapas ->> 'reparto'),
                 'en_reparto_hoy', (select jsonb_build_object('periodo', p.periodo, 'desde', p.desde) from reparto.f_periodo_reparto(v.ciclo::text) p)) order by v.ciclo), '[]'::jsonb)
                 from scrr.v_calendario_vigente v where v.periodo = v_per));
end $$;

-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 55 — PERMISOS. Todo objeto nuevo: revoke all … from public, anon, authenticated, service_role ANTES de dar permisos.
-- Solo service_role ejecuta las RPC public.geoportal_reparto_* (la Edge geoportal-reparto). Nadie más toca el esquema reparto: las RPC son SECURITY DEFINER.
-- El Dell (respaldo cifrado, cambio de D2 del 23-nov): homelab_lectura recibe USAGE sobre reparto y SELECT sobre CADA tabla, con la lista explícita
-- (sin ALTER DEFAULT PRIVILEGES: una tabla futura no queda legible por accidente). Las tablas de reparto no tienen RLS: el SELECT basta.
-- =====================================================================
revoke all on all tables in schema reparto from public, anon, authenticated, service_role;
revoke all on all sequences in schema reparto from public, anon, authenticated, service_role;
revoke all on all functions in schema reparto from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
grant usage on schema reparto to homelab_lectura;
grant select on reparto.parametros, reparto.lotes, reparto.lote_filas, reparto.lotes_anulados,
                reparto.jornadas, reparto.jornada_items, reparto.entregas, reparto.entregas_anuladas to homelab_lectura;

-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 60 — SEMILLA: los parámetros iniciales (versionados; un cambio es una fila nueva)
-- =====================================================================
insert into reparto.parametros (clave, valor, nota, autor) values
  ('respaldo_dias', '15', 'Respaldo cuando al ciclo le falta la fecha de reparto en el calendario: días (contando hoy) en que una factura entregada no se vuelve a ofrecer.', 'migracion@geoportal'),
  ('lote_vigencia_dias', '45', 'Días en que un archivo de ruta cargado por el supervisor se ofrece a los repartidores.', 'migracion@geoportal'),
  ('tope_filas_lote', '10000', 'Filas máximas de un archivo de ruta o de ciclo (el ciclo más grande tiene unos 9.100 contratos).', 'migracion@geoportal'),
  ('precision_mala_m', '30', 'Precisión del GPS (metros) desde la que una entrega queda marcada como imprecisa (P8). Se registra igual.', 'migracion@geoportal');

-- La actividad «Supervisión de reparto» en Personal de Comercial (David, 23-nov). Es una fila del catálogo de campo (dato, no función: la huella de campo no
-- cambia). Si ya existiera (una reaplicación tras la reversa, que la desactiva), se vuelve a activar.
insert into campo.actividades (codigo, nombre, orden, formularios, autor) values ('supervision_reparto', 'Supervisión de reparto', 11, '{}', 'migracion@geoportal')
  on conflict (codigo) do update set activa = true;

-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 70 — PRUEBAS. Dentro del ensayo: todo se deshace con el ERROR esperado del final.
-- Datos propios con prefijo ZTREP (correos ztrep.*@emdupar.gov.co; contratos de 12 dígitos 88000000xxxx, que no existen; ciclos 97 y 98, que no existen:
-- el calendario de reparto solo admite ciclos de 1 a 99). Las fechas de reparto de prueba se escriben en scrr.calendario_ciclos y se deshacen al final.
-- Las rutas de prueba se escriben en hechos.rutas_consecutivos con el período MÁS RECIENTE (así las ve bi.v_rutas_geoportal) y se deshacen al final.
-- Cada prueba cuenta SOLO sus filas. Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- Sin tablas temporales que se borren al confirmar (regla de David, 21-nov).
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztrep_res (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztrep_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), left(p_detalle, 600)) $f$;
create function pg_temp.rpc(q text) returns jsonb language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  begin
    execute 'set local role service_role';
    execute 'select (' || q || ')::jsonb' into r;
    execute 'reset role';
    return coalesce(r, 'null'::jsonb);
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    return jsonb_build_object('error', e, 'msg', m);
  end;
end $f$;
create function pg_temp.err(r jsonb) returns text language sql as $f$ select coalesce(r ->> 'error', 'OK') $f$;
-- entregar con XY de Valledupar
create function pg_temp.ent(p_sol text, p_j bigint, p_c text, p_uuid uuid default gen_random_uuid(), p_prec numeric default 8, p_lon numeric default -73.25, p_lat numeric default 10.47) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_reparto_entregar(%L, %s, %L, %s, %s, %s, false, %L::uuid)', p_sol, p_j, p_c, coalesce(p_lon::text, 'null'), coalesce(p_lat::text, 'null'), coalesce(p_prec::text, 'null'), p_uuid)) $f$;
-- entregar desde el BUSCADOR (no mueve el punto de avance de los saltados)
create function pg_temp.entb(p_sol text, p_j bigint, p_c text) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_reparto_entregar(%L, %s, %L, -73.25, 10.47, 8, true, %L::uuid)', p_sol, p_j, p_c, gen_random_uuid())) $f$;
create function pg_temp.pend(r jsonb) returns text language sql as $f$
  select coalesce(string_agg(x ->> 'c', ',' order by o), '') from jsonb_array_elements(r -> 'pendientes') with ordinality t(x, o) $f$;
create function pg_temp.salt(r jsonb) returns text language sql as $f$
  select coalesce(string_agg(x ->> 'c', ',' order by o), '') from jsonb_array_elements(r -> 'pendientes') with ordinality t(x, o) where (x ->> 's')::boolean $f$;

-- Personas de prueba
insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta, ver_registro_tecnico) values
  ('ztrep.adm@emdupar.gov.co', 'ZTREP Admin', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false, false),
  ('ztrep.sup@emdupar.gov.co', 'ZTREP Supervisor de reparto', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.supcal@emdupar.gov.co', 'ZTREP Supervisor de reparto y de campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false, false),
  ('ztrep.supcampo@emdupar.gov.co', 'ZTREP Supervisor de campo (SCRR)', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false, false),
  ('ztrep.supquitada@emdupar.gov.co', 'ZTREP Supervisión de reparto quitada', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.rep1@emdupar.gov.co', 'ZTREP Repartidor uno', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.rep2@emdupar.gov.co', 'ZTREP Repartidor dos', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.sinact@emdupar.gov.co', 'ZTREP Campo sin reparto', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.quitada@emdupar.gov.co', 'ZTREP Reparto quitado', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.inactivo@emdupar.gov.co', 'ZTREP Inactivo', 'consulta', false, 'sin_restriccion', 'todos', false, true, false, false, false, false),
  ('ztrep.tec@emdupar.gov.co', 'ZTREP Solo Técnica', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false, true);
insert into campo.personal_eventos (persona, tipo_evento, valor, motivo, autor) values
  ('ztrep.rep1@emdupar.gov.co', 'asignar_actividad', 'reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.rep2@emdupar.gov.co', 'asignar_actividad', 'reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.quitada@emdupar.gov.co', 'asignar_actividad', 'reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.quitada@emdupar.gov.co', 'quitar_actividad', 'reparto', 'ZTREP ya no reparte facturas', 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.inactivo@emdupar.gov.co', 'asignar_actividad', 'reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.sup@emdupar.gov.co', 'asignar_actividad', 'supervision_reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.supcal@emdupar.gov.co', 'asignar_actividad', 'supervision_reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.supquitada@emdupar.gov.co', 'asignar_actividad', 'supervision_reparto', null, 'ztrep.adm@emdupar.gov.co'),
  ('ztrep.supquitada@emdupar.gov.co', 'quitar_actividad', 'supervision_reparto', 'ZTREP ya no supervisa el reparto', 'ztrep.adm@emdupar.gov.co');

-- Rutas de prueba en el período más reciente. Ruta 880101: 12 contratos; orden esperado por consecutivo_ruta y, en el empate, consecutivo_predio.
-- 880000000105 aparece DOS veces en el período (cuenta una vez, en su primer lugar). 880000000199 está solo en un período viejo (no debe salir).
-- Ruta 880102: 3 contratos. Ciclo 9999: no se ofrece.
insert into hechos.rutas_consecutivos (ciclo, consecutivo_ruta, ruta, contrato, direccion, consecutivo_predio, periodo, archivo_origen, fecha_carga)
select x.ciclo, x.cr, x.ruta, x.contrato, 'ZTREP CALLE', x.cp, coalesce(x.periodo, (select max(periodo) from hechos.rutas_consecutivos)), 'ZTREP.xlsx', '2026-11-23'
  from (values
    ('98', '5000000',  '880101', '880000000101', '10', null),
    ('98', '1000000',  '880101', '880000000102', '7',  null),
    ('98', '9000000',  '880101', '880000000103', '3',  null),
    ('98', '2000000',  '880101', '880000000104', '9',  null),   -- empate con 107: va DESPUÉS (predio 9 > 4)
    ('98', '2000000',  '880101', '880000000107', '4',  null),
    ('98', '3000000',  '880101', '880000000105', '1',  null),
    ('98', '8000000',  '880101', '880000000105', '1',  null),   -- repetido en el período
    ('98', '0',        '880101', '880000000106', '2',  null),   -- consecutivo 0: va primero
    ('98', '7000000',  '880101', '880000000108', '5',  null),
    ('98', '6000000',  '880101', '880000000109', '6',  null),
    ('98', '9500000',  '880101', '880000000110', '8',  null),
    ('98', '9600000',  '880101', '880000000111', '11', null),
    ('98', '9700000',  '880101', '880000000112', '12', null),
    ('98', '100',      '880101', '880000000199', '1',  '190001'),  -- período viejo
    ('98', '1000000',  '880102', '880000000201', '1',  null),
    ('98', '2000000',  '880102', '880000000202', '2',  null),
    ('98', '3000000',  '880102', '880000000203', '3',  null),
    ('9999', '1000000',  '889999', '880000000901', '1',  null),
    ('97',   '1000000',  '970101', '880000000501', '1',  null),   -- ciclo 97: sin fecha de reparto (respaldo)
    ('97',   '2000000',  '970101', '880000000502', '2',  null)
  ) x(ciclo, cr, ruta, contrato, cp, periodo);
-- un contrato que solo está en cartera_suscripcion (para «inventada»)
insert into public.cartera_suscripcion (contrato, estado, ciclo, periodo_carga) values ('880000000301', 'ACTIVO', '98', 'ZTREP'),
  ('880000000302', 'ACTIVO', '9999', 'ZTREP'),   -- sin ciclo de calendario: el mes del día
  ('880000000303', 'ACTIVO', '97', 'ZTREP'),     -- ciclo sin fecha de reparto: respaldo
  ('880000000201', 'ACTIVO', '97', 'ZTREP'),     -- en las rutas es del ciclo 98: al deducir el ciclo de un archivo manda la tabla de rutas
  ('880000000304', 'ACTIVO', '098', 'ZTREP');    -- solo en la cartera, con el ciclo escrito «098» (comparación numérica)
-- Calendario de reparto de prueba. Ciclo 98: el mes pasado (reparto hace 32 días), este mes (hace 2 días) y el próximo (en 3 días: aún no llega).
-- Ciclo 97: este mes, sin fecha de reparto (solo lectura).
insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, etapas, autor)
select to_char(date_trunc('month', h.h) + make_interval(months => x.k), 'YYYYMM'), x.c, h.h + 10, h.h + 15, x.e, 'ztrep.adm@emdupar.gov.co'
  from (select (now() at time zone 'America/Bogota')::date as h) h,
       lateral (values (-1, 98::smallint, jsonb_build_object('reparto', (h.h - 32)::text)),
                       ( 0, 98::smallint, jsonb_build_object('reparto', (h.h - 2)::text)),
                       ( 1, 98::smallint, jsonb_build_object('reparto', (h.h + 3)::text)),
                       ( 0, 97::smallint, jsonb_build_object('lectura', h.h::text))) x(k, c, e);
analyze hechos.rutas_consecutivos;

do $$
declare
  A text := 'ztrep.adm@emdupar.gov.co'; S text := 'ztrep.sup@emdupar.gov.co'; R1 text := 'ztrep.rep1@emdupar.gov.co'; R2 text := 'ztrep.rep2@emdupar.gov.co';
  r jsonb; fx jsonb; j1 bigint; j2 bigint; j3 bigint; ji bigint; jn bigint; u uuid := gen_random_uuid(); e1 bigint; e4 bigint; v_lote uuid; v_lote2 uuid; v_n bigint; v_aud bigint;
  t0 timestamptz; ms numeric; v_orden text; v_sha text := md5('ztrep-lote') || md5('ztrep-lote-b');
  v_hoy date := (now() at time zone 'America/Bogota')::date; v_mes text := to_char(v_hoy, 'YYYYMM');
  v_mes_ant text := to_char(date_trunc('month', v_hoy) - interval '1 month', 'YYYYMM'); j97 bigint; j97b bigint; r2b jsonb;
begin
  -- ===== 00. Quién entra =====
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R1));
  perform pg_temp.ok('00.01 el repartidor (campo + actividad reparto) entra: es repartidor y no supervisor',
    (r ->> 'es_repartidor')::boolean and not (r ->> 'es_supervisor')::boolean, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', S));
  perform pg_temp.ok('00.02 el supervisor de reparto (actividad supervision_reparto) entra: es supervisor y no repartidor; sin dashboard_campo no cambia el calendario',
    (r ->> 'es_supervisor')::boolean and not (r ->> 'es_repartidor')::boolean and not (r ->> 'puede_calendario')::boolean, r::text);
  perform pg_temp.ok('00.11 con dashboard_campo pero SIN supervision_reparto (supervisor del SCRR): 42501 en el contexto y en lo del supervisor',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.supcampo@emdupar.gov.co'))) = '42501'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', 'ztrep.supcampo@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.12 con supervision_reparto QUITADA: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', 'ztrep.supquitada@emdupar.gov.co'))) = '42501');
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.supcal@emdupar.gov.co'));
  perform pg_temp.ok('00.13 el supervisor de reparto que también tiene dashboard_campo ve el enlace «Cambiar en Calendario» (puede_calendario); el administrador también',
    (r ->> 'es_supervisor')::boolean and (r ->> 'puede_calendario')::boolean
    and (pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', A)) ->> 'puede_calendario')::boolean, r::text);
  perform pg_temp.ok('00.15 perfil liviano: repartidor, supervisor, administrador, campo sin actividades (falso y falso, sin error) y sin campo (42501)',
    pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', R1)) = '{"es_repartidor": true, "es_supervisor": false}'::jsonb
    and pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', S)) = '{"es_repartidor": false, "es_supervisor": true}'::jsonb
    and pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', A)) = '{"es_repartidor": true, "es_supervisor": true}'::jsonb
    and pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', 'ztrep.sinact@emdupar.gov.co')) = '{"es_repartidor": false, "es_supervisor": false}'::jsonb
    and pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', 'ztrep.supcampo@emdupar.gov.co')) = '{"es_repartidor": false, "es_supervisor": false}'::jsonb
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_perfil(%L)', 'ztrep.tec@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.14 la actividad «Supervisión de reparto» está en el catálogo de Personal, activa, y el supervisor sale en f_quien_puede',
    exists (select 1 from campo.actividades where codigo = 'supervision_reparto' and activa and nombre = 'Supervisión de reparto')
    and exists (select 1 from campo.f_quien_puede('supervision_reparto') q where q.persona = S)
    and not exists (select 1 from campo.f_quien_puede('supervision_reparto') q where q.persona = R1));
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', A));
  perform pg_temp.ok('00.03 el administrador es las dos cosas', (r ->> 'es_supervisor')::boolean and (r ->> 'es_repartidor')::boolean and (r ->> 'es_admin')::boolean, r::text);
  perform pg_temp.ok('00.04 con campo pero SIN la actividad reparto: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.sinact@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.05 con la actividad QUITADA: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.quitada@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.06 inactivo en la lista blanca (aunque tenga la actividad): 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.inactivo@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.07 solo Técnica: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', 'ztrep.tec@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.08 sin solicitante: 28000', pg_temp.err(pg_temp.rpc('public.geoportal_reparto_contexto(null)')) = '28000');
  perform pg_temp.ok('00.09 el repartidor no carga archivos ni ve el avance (42501)',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, %L, %L, %L::jsonb)', R1, 'x.xlsx', v_sha, 'ruta', '98', '880101', '[{"contrato":"880000000101"}]'))) = '42501'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', R1))) = '42501'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_mapa(%L)', R1))) = '42501'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_lotes(%L)', R1))) = '42501');
  perform pg_temp.ok('00.10 el supervisor que no reparte no empieza jornadas (42501)',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', S, 'anterior', '98', '880101'))) = '42501');

  -- ===== 01. Rutas del último período en el contexto =====
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R1));
  perform pg_temp.ok('01.01 el contexto trae el período más reciente', r ->> 'periodo' = (select max(periodo) from hechos.rutas_consecutivos), r ->> 'periodo');
  perform pg_temp.ok('01.02 ciclo 98 con sus rutas 880101 (12 contratos distintos) y 880102 (3)',
    (select x -> 'rutas' from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' = '98') = '[{"n": 12, "ruta": "880101"}, {"n": 3, "ruta": "880102"}]'::jsonb,
    (select (x -> 'rutas')::text from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' = '98'));
  perform pg_temp.ok('01.03 el ciclo 9999 no se ofrece (P4)', not exists (select 1 from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' = '9999'));
  perform pg_temp.ok('01.04 parámetros: respaldo 15 días, tope 10000 filas, precisión mala 30 m',
    r -> 'parametros' = '{"respaldo_dias": 15, "tope_filas_lote": 10000, "precision_mala_m": 30}'::jsonb, (r -> 'parametros')::text);
  perform pg_temp.ok('01.05 calendario: el ciclo 98 reparte el período de este mes (su fecha de reparto ya llegó; la del próximo mes no); el 97 no tiene fecha',
    (select x -> 'reparto' from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' = '98') = jsonb_build_object('periodo', v_mes, 'desde', v_hoy - 2)
    and (select x -> 'reparto' from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' = '97') = 'null'::jsonb,
    (select string_agg((x -> 'reparto')::text, ' ') from jsonb_array_elements(r -> 'anterior') x where x ->> 'ciclo' in ('97', '98')));

  -- ===== 02. Empezar con la ruta anterior =====
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '98', '880101'));
  j1 := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('02.01 empieza la jornada: 12 facturas, origen anterior, sin retomar', j1 is not null and (r -> 'jornada' ->> 'total')::int = 12
    and r -> 'jornada' ->> 'origen' = 'anterior' and not (r ->> 'retomada')::boolean and (r ->> 'siguiente')::int = 1, r::text);
  v_orden := (select string_agg(right(contrato, 3), ',' order by orden_lectura) from reparto.jornada_items where jornada_id = j1);
  perform pg_temp.ok('02.02 orden de lectura: consecutivo_ruta, el empate por consecutivo_predio y el repetido en su primer lugar',
    v_orden = '106,102,107,104,105,101,109,108,103,110,111,112', v_orden);
  perform pg_temp.ok('02.03 la lista trae solo los códigos (sin el número de orden), en ese orden y sin saltados',
    pg_temp.pend(r) = '880000000106,880000000102,880000000107,880000000104,880000000105,880000000101,880000000109,880000000108,880000000103,880000000110,880000000111,880000000112'
    and pg_temp.salt(r) = '' and not exists (select 1 from jsonb_array_elements(r -> 'pendientes') x where x ? 'o' or x ? 'orden_lectura'), pg_temp.pend(r));
  perform pg_temp.ok('02.09 la jornada reparte el período de este mes, sin respaldo ni aviso',
    r -> 'jornada' ->> 'periodo_reparto' = v_mes and (r -> 'jornada' ->> 'reparto_desde')::date = v_hoy - 2 and not (r -> 'jornada' ->> 'respaldo')::boolean
    and r -> 'jornada' -> 'aviso' = 'null'::jsonb, (r -> 'jornada')::text);
  perform pg_temp.ok('02.04 el contrato del período viejo no está', not exists (select 1 from reparto.jornada_items where jornada_id = j1 and contrato = '880000000199'));
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '98', '880101'));
  perform pg_temp.ok('02.05 volver a escoger la misma ruta el mismo día retoma la MISMA jornada', (r -> 'jornada' ->> 'id')::bigint = j1 and (r ->> 'retomada')::boolean
    and (select count(*) from reparto.jornadas where repartidor = R1) = 1);
  perform pg_temp.ok('02.06 ciclo 9999: no se reparte por ruta', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '9999', '889999'))) = '22023');
  perform pg_temp.ok('02.07 una ruta que no está en el último período: error claro',
    pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '98', '880199')) ->> 'msg' = 'Esa ruta no está en el último período cargado');
  perform pg_temp.ok('02.08 origen inválido o sin ciclo: 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L)', R1, 'otro'))) = '22023'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, null, %L)', R1, 'anterior', '880101'))) = '22023');

  -- ===== 03. Entregar en desorden, saltar, doble toque =====
  r := pg_temp.ent(R1, j1, '880000000106', u);
  e1 := (r ->> 'entrega_id')::bigint;
  perform pg_temp.ok('03.01 primera entrega: consecutivo 1, con su XY, su período de reparto y no repetida', (r ->> 'consecutivo')::int = 1 and not (r ->> 'repetida')::boolean
    and r ->> 'periodo_reparto' = v_mes and (select periodo_reparto from reparto.entregas where id = e1) = v_mes
    and exists (select 1 from reparto.entregas where id = e1 and lon = -73.25 and lat = 10.47 and precision_m = 8 and orden_lectura = 1 and autor = R1), r::text);
  r := pg_temp.ent(R1, j1, '880000000106', u);
  perform pg_temp.ok('03.02 el MISMO toque (mismo uuid) otra vez devuelve la misma entrega, sin error y sin otra fila',
    (r ->> 'entrega_id')::bigint = e1 and (r ->> 'repetida')::boolean and (select count(*) from reparto.entregas where jornada_id = j1) = 1, r::text);
  r := pg_temp.ent(R1, j1, '880000000106');
  perform pg_temp.ok('03.03 la misma factura con otro toque: no se registra dos veces (23505) y lo dice', pg_temp.err(r) = '23505' and r ->> 'msg' like '%ya se registró%(entrega 1)%', r::text);
  r := pg_temp.ent(R1, j1, '880000000104');            -- se salta 102 y 107
  e4 := (r ->> 'entrega_id')::bigint;
  perform pg_temp.ok('03.04 entrega en desorden: la del 4.º lugar queda como entrega 2', (r ->> 'consecutivo')::int = 2, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R1, j1));
  perform pg_temp.ok('03.05 los saltados (102 y 107) quedan ARRIBA, marcados, y las entregadas salen de la lista',
    pg_temp.salt(r) = '880000000102,880000000107' and pg_temp.pend(r) like '880000000102,880000000107,880000000105,%' and (r ->> 'entregadas_mias')::int = 2
    and (r ->> 'siguiente')::int = 3, pg_temp.pend(r) || ' | ' || pg_temp.salt(r));
  r := pg_temp.ent(R1, j1, '880000000102');
  perform pg_temp.ok('03.06 entregar un saltado: entrega 3; ya no está saltado', (r ->> 'consecutivo')::int = 3
    and pg_temp.salt(pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R1, j1))) = '880000000107', r::text);
  perform pg_temp.ok('03.07 un contrato que no es de esta ruta: error claro', pg_temp.ent(R1, j1, '880000000201') ->> 'msg' = 'El contrato 880000000201 no está en esta ruta');
  perform pg_temp.ok('03.08 sin GPS no se guarda (P8)', pg_temp.ent(R1, j1, '880000000105', gen_random_uuid(), null, null, null) ->> 'msg' like 'Sin ubicación del GPS%'
    and pg_temp.ent(R1, j1, '880000000105', gen_random_uuid(), 10, 2.35, 48.85) ->> 'msg' like 'La ubicación del GPS no es válida%');
  r := pg_temp.ent(R1, j1, '880000000105', gen_random_uuid(), 85);
  perform pg_temp.ok('03.09 GPS impreciso (85 m) se guarda y queda marcado (P8)', (r ->> 'consecutivo')::int = 4 and (r ->> 'precision_mala')::boolean, r::text);
  perform pg_temp.ok('03.10 contrato con letras: 22023', pg_temp.err(pg_temp.ent(R1, j1, '88A')) = '22023');
  perform pg_temp.ok('03.11 sin uuid del toque: 22023', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_entregar(%L, %s, %L, -73.25, 10.47, 5, false, null)', R1, j1, '880000000101'))) = '22023');
  -- segundo repartidor en la MISMA ruta
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R2, 'anterior', '98', '880101'));
  j2 := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('03.12 otro repartidor en la misma ruta: su propia jornada, y su lista ya descuenta lo entregado por el primero',
    j2 <> j1 and pg_temp.pend(r) = '880000000107,880000000101,880000000109,880000000108,880000000103,880000000110,880000000111,880000000112' and pg_temp.salt(r) = '', pg_temp.pend(r));
  r := pg_temp.ent(R2, j2, '880000000104');
  perform pg_temp.ok('03.13 la factura que ya entregó otro: no se registra y dice «por otro repartidor»', pg_temp.err(r) = '23505' and r ->> 'msg' like '%por otro repartidor', r::text);
  perform pg_temp.ok('03.14 entregar en la lista de otro: 42501', pg_temp.err(pg_temp.ent(R2, j1, '880000000107')) = '42501'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R2, j1))) = '42501');
  r := pg_temp.ent(R2, j2, '880000000112', u);
  perform pg_temp.ok('03.15 el uuid de otro toque (de otra persona) no sirve', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.ent(R2, j2, '880000000112');
  perform pg_temp.ok('03.16 el consecutivo es de cada jornada: la primera del segundo repartidor es la 1', (r ->> 'consecutivo')::int = 1, r::text);

  -- ===== 04. Anular con motivo (P7) =====
  r := pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', R1, e4, 'corto'));
  perform pg_temp.ok('04.01 anular sin motivo suficiente: 22023', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', R2, e4, 'ZTREP toqué la que no era'));
  perform pg_temp.ok('04.02 un repartidor no anula la entrega de otro (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', R1, e4, 'ZTREP toqué la que no era'));
  perform pg_temp.ok('04.03 el repartidor anula la suya de hoy con motivo; la fila de la entrega sigue ahí', (r ->> 'ok')::boolean
    and exists (select 1 from reparto.entregas where id = e4) and exists (select 1 from reparto.entregas_anuladas where entrega_id = e4 and autor = R1), r::text);
  perform pg_temp.ok('04.04 anularla otra vez: 55000', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', R1, e4, 'ZTREP otra vez lo mismo'))) = '55000');
  r := pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R1, j1));
  perform pg_temp.ok('04.05 la anulada vuelve a pendientes', pg_temp.pend(r) like '%880000000104%' and (r ->> 'entregadas_mias')::int = 3, pg_temp.pend(r));
  r := pg_temp.ent(R1, j1, '880000000104');
  perform pg_temp.ok('04.06 se entrega otra vez con un consecutivo NUEVO (5): no se renumera', (r ->> 'consecutivo')::int = 5
    and (select string_agg(consecutivo::text, ',' order by consecutivo) from reparto.entregas where jornada_id = j1) = '1,2,3,4,5', r::text);
  v_aud := (select count(*) from public.geoportal_auditoria where email = S and accion = 'reparto_anular_entrega');
  r := pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', S, (select id from reparto.entregas where jornada_id = j2 and consecutivo = 1), 'ZTREP la anula el supervisor'));
  perform pg_temp.ok('04.07 el supervisor anula la de cualquiera, y queda en la auditoría', (r ->> 'ok')::boolean
    and (select count(*) from public.geoportal_auditoria where email = S and accion = 'reparto_anular_entrega') = v_aud + 1, r::text);
  perform pg_temp.ok('04.08 entrega que no existe: 22023', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', S, -1, 'ZTREP no existe esta'))) = '22023');

  -- ===== 05. Sin ruta («inventada») =====
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L)', R1, 'inventada'));
  ji := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('05.01 repartir sin ruta: jornada sin lista', ji is not null and (r -> 'jornada' ->> 'total')::int = 0 and r -> 'pendientes' = '[]'::jsonb, r::text);
  r := pg_temp.ent(R1, ji, '880000000301');
  perform pg_temp.ok('05.02 un contrato que solo está en cartera_suscripcion: entrega 1 (su orden real es su ruta), con el período de reparto de SU ciclo (98)',
    (r ->> 'consecutivo')::int = 1 and r ->> 'periodo_reparto' = v_mes
    and (select orden_lectura from reparto.entregas where id = (r ->> 'entrega_id')::bigint) is null, r::text);
  r := pg_temp.ent(R1, ji, '880000000203');
  perform pg_temp.ok('05.03 un contrato que solo está en las rutas: entrega 2', (r ->> 'consecutivo')::int = 2, r::text);
  perform pg_temp.ok('05.04 un código que no existe en ningún lado: error claro', pg_temp.ent(R1, ji, '880000000999') ->> 'msg' = 'No hay ningún contrato con el código 880000000999');
  perform pg_temp.ok('05.05 sin ruta tampoco se registra dos veces la misma factura (ya entregada desde una ruta)', pg_temp.err(pg_temp.ent(R1, ji, '880000000106')) = '23505');

  -- ===== 06. Archivos de ruta («nueva») =====
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, %L, %L, %L::jsonb)', S, 'ztrep_ruta.xlsx', v_sha, 'ruta', '98', 'ZT-NUEVA',
         '[{"contrato":"880000000203","orden":"30"},{"contrato":"880000000201","orden":"10"},{"contrato":"880000000202","orden":"20"},{"contrato":"880000000401","orden":"40"},{"contrato":"880000000402","orden":"50"}]'));
  v_lote := (r ->> 'lote_id')::uuid;
  perform pg_temp.ok('06.01 el supervisor carga un archivo de una ruta: 5 filas, 2 sin registro (se aceptan con aviso, P5)', (r ->> 'ok')::boolean and (r ->> 'filas')::int = 5
    and (r ->> 'sin_registro')::int = 2 and not (r ->> 'repetido')::boolean and (select sin_registro from reparto.lotes where id = v_lote) = 2, r::text);
  perform pg_temp.ok('06.02 el orden es el de la columna Orden, renumerado 1…N',
    (select string_agg(right(contrato, 3) || ':' || orden, ',' order by orden) from reparto.lote_filas where lote_id = v_lote) = '201:1,202:2,203:3,401:4,402:5');
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, %L, %L, %L::jsonb)', S, 'ztrep_ruta.xlsx', v_sha, 'ruta', '98', 'ZT-NUEVA', '[{"contrato":"880000000203"}]'));
  perform pg_temp.ok('06.03 el mismo archivo otra vez el mismo día (doble clic): el mismo lote', (r ->> 'lote_id')::uuid = v_lote and (r ->> 'repetido')::boolean
    and (select count(*) from reparto.lotes where autor = S) = 1, r::text);
  v_n := (select count(*) from reparto.lotes);
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, %L, %L, %L::jsonb)', S, 'malo.xlsx', md5('m') || md5('n'), 'ciclo', '98', null,
         '[{"contrato":"88A"},{"contrato":"880000000201"},{"contrato":"880000000201"},{"contrato":"880000000202","orden":"0"}]'));
  perform pg_temp.ok('06.04 un archivo con errores no escribe nada y dice cada error con su fila de Excel',
    not (r ->> 'ok')::boolean and (select count(*) from reparto.lotes) = v_n
    and r -> 'errores' = '["Fila 2: el contrato «88A» no es válido (solo números, de 1 a 12)", "Fila 4: el contrato 880000000201 está repetido", "Fila 5: el Orden «0» no es un entero mayor que cero", "La columna Orden debe venir en todas las filas o en ninguna"]'::jsonb,
    (r -> 'errores')::text);
  perform pg_temp.ok('06.05 archivo de ruta sin la ruta, o ciclo inválido: 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, %L, null, %L::jsonb)', S, 'x.xlsx', v_sha, 'ruta', '98', '[{"contrato":"1"}]'))) = '22023'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, %L, null, %L::jsonb)', S, 'x.xlsx', v_sha, 'ciclo', 'C1', '[{"contrato":"880000000998"}]'))) = '22023');
  insert into reparto.parametros (clave, valor, nota, autor) values ('tope_filas_lote', '2', 'ZTREP prueba del tope', A);
  perform pg_temp.ok('06.06 más filas que el tope: 22023 con el tope en el mensaje',
    pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, %L, null, %L::jsonb)', S, 'x.xlsx', v_sha, 'ciclo', '98', '[{"contrato":"1"},{"contrato":"2"},{"contrato":"3"}]')) ->> 'msg'
      = 'El archivo debe tener entre 1 y 2 filas (trae 3)');
  insert into reparto.parametros (clave, valor, nota, autor) values ('tope_filas_lote', '10000', 'ZTREP vuelve el tope', A);
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R2));
  perform pg_temp.ok('06.07 el repartidor ve el archivo vigente entre las rutas nuevas', exists (select 1 from jsonb_array_elements(r -> 'nuevas') x where (x ->> 'id')::uuid = v_lote and x ->> 'ruta' = 'ZT-NUEVA'), (r -> 'nuevas')::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, null, null, %L::uuid)', R2, 'nueva', v_lote));
  jn := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('06.08 empezar con el archivo: su orden y ya sin la 203 (entregada sin ruta por el otro repartidor)',
    (r -> 'jornada' ->> 'total')::int = 5 and r -> 'jornada' ->> 'nombre_archivo' = 'ztrep_ruta.xlsx' and pg_temp.pend(r) = '880000000201,880000000202,880000000401,880000000402', pg_temp.pend(r));
  r := pg_temp.ent(R2, jn, '880000000202');
  perform pg_temp.ok('06.09 entrega en el archivo; la 201 queda saltada', (r ->> 'consecutivo')::int = 1
    and pg_temp.salt(pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R2, jn))) = '880000000201', r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_anular(%L, %L::uuid, %L)', S, v_lote, 'ZTREP archivo equivocado'));
  perform pg_temp.ok('06.10 el supervisor anula el archivo con motivo', (r ->> 'ok')::boolean and exists (select 1 from reparto.lotes_anulados where lote_id = v_lote), r::text);
  perform pg_temp.ok('06.11 anulado: no se empieza, no se entrega en su jornada y ya no se ofrece',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, null, null, %L::uuid)', R1, 'nueva', v_lote))) = '22023'
    and pg_temp.ent(R2, jn, '880000000401') ->> 'msg' = 'El supervisor anuló el archivo de esta ruta'
    and not exists (select 1 from jsonb_array_elements(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R2)) -> 'nuevas') x where (x ->> 'id')::uuid = v_lote));
  perform pg_temp.ok('06.12 anular el archivo dos veces: 55000', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_lote_anular(%L, %L::uuid, %L)', S, v_lote, 'ZTREP otra vez lo mismo'))) = '55000');
  insert into reparto.lotes (nombre_archivo, archivo_sha256, tipo, ciclo, ruta, filas, autor, creado_en) values ('ztrep_viejo.xlsx', v_sha, 'ciclo', '98', null, 1, S, now() - interval '50 days')
    returning id into v_lote2;
  insert into reparto.lote_filas (lote_id, orden, contrato) values (v_lote2, 1, '880000000111');
  perform pg_temp.ok('06.13 un archivo vencido (más de 45 días) no se ofrece ni se empieza',
    pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, null, null, %L::uuid)', R1, 'nueva', v_lote2)) ->> 'msg' like 'Ese archivo de ruta ya venció%'
    and not exists (select 1 from jsonb_array_elements(pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R1)) -> 'nuevas') x where (x ->> 'id')::uuid = v_lote2));
  r := pg_temp.rpc(format('public.geoportal_reparto_lotes(%L)', S));
  perform pg_temp.ok('06.14 la lista de archivos del supervisor: anulado con su motivo y su jornada; el viejo, no vigente',
    exists (select 1 from jsonb_array_elements(r -> 'lotes') x where (x ->> 'id')::uuid = v_lote and (x ->> 'anulado')::boolean and x ->> 'motivo_anulacion' = 'ZTREP archivo equivocado' and (x ->> 'jornadas')::int = 1)
    and exists (select 1 from jsonb_array_elements(r -> 'lotes') x where (x ->> 'id')::uuid = v_lote2 and not (x ->> 'vigente')::boolean), (r -> 'lotes')::text);
  perform pg_temp.ok('06.15 la auditoría tiene la carga y la anulación, sin las filas del archivo',
    exists (select 1 from public.geoportal_auditoria where accion = 'reparto_lote_cargar' and referencia = v_lote::text and detalle ->> 'filas' = '5' and not detalle ? 'filas_archivo'
            and detalle::text not like '%880000000201%')
    and exists (select 1 from public.geoportal_auditoria where accion = 'reparto_lote_anular' and referencia = v_lote::text));

  -- ===== 07. Avance, detalle y mapa del supervisor =====
  r := pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', S));
  perform pg_temp.ok('07.01 avance de hoy, una fila por jornada (4: dos de la ruta 880101, la de sin ruta y la del archivo)',
    (select count(*) from jsonb_array_elements(r -> 'filas') x where x ->> 'repartidor' like 'ztrep.%') = 4, (r -> 'filas')::text);
  fx := (select x from jsonb_array_elements(r -> 'filas') x where (x ->> 'jornada_id')::bigint = j1);
  perform pg_temp.ok('07.02 la jornada 1: 12 facturas, 4 entregadas, 1 anulada, 8 pendientes, 1 saltada (107), con el nombre del repartidor',
    (fx ->> 'total')::int = 12 and (fx ->> 'entregadas')::int = 4 and (fx ->> 'anuladas')::int = 1 and (fx ->> 'pendientes')::int = 8 and (fx ->> 'saltadas')::int = 1
    and fx ->> 'nombre' = 'ZTREP Repartidor uno' and fx ->> 'ultima' is not null, fx::text);
  fx := (select x from jsonb_array_elements(r -> 'filas') x where (x ->> 'jornada_id')::bigint = ji);
  perform pg_temp.ok('07.03 la jornada sin ruta: 2 entregadas, sin pendientes ni saltadas', (fx ->> 'entregadas')::int = 2 and fx -> 'pendientes' = 'null'::jsonb and fx -> 'saltadas' = 'null'::jsonb, fx::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_detalle(%L, %s)', S, j1));
  perform pg_temp.ok('07.04 detalle: el orden real (1…5) con su orden de lectura, y la anulada con su motivo',
    (select string_agg((x ->> 'consecutivo') || ':' || coalesce(x ->> 'orden_lectura', '-') || case when (x ->> 'anulada')::boolean then '(A)' else '' end, ',' order by (x ->> 'consecutivo')::int)
       from jsonb_array_elements(r -> 'entregas') x) = '1:1,2:4(A),3:2,4:5,5:4'
    and (select x ->> 'motivo_anulacion' from jsonb_array_elements(r -> 'entregas') x where (x ->> 'consecutivo')::int = 2) = 'ZTREP toqué la que no era', (r -> 'entregas')::text);
  perform pg_temp.ok('07.05 detalle: los saltados (107) y las pendientes (8)',
    (select string_agg(x ->> 'contrato', ',' order by (x ->> 'orden_lectura')::int) from jsonb_array_elements(r -> 'saltados') x) = '880000000107' and (r ->> 'pendientes')::int = 8, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_mapa(%L)', S));
  perform pg_temp.ok('07.06 mapa de hoy: todos los XY de prueba (9), con las 2 anuladas marcadas',
    (select count(*) from jsonb_array_elements(r -> 'puntos') x where x ->> 'repartidor' like 'ztrep.%') = 9
    and (select count(*) from jsonb_array_elements(r -> 'puntos') x where x ->> 'repartidor' like 'ztrep.%' and (x ->> 'anulada')::boolean) = 2, (r -> 'puntos')::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_mapa(%L, null, %s)', S, j1));
  perform pg_temp.ok('07.07 mapa de una jornada: sus 5 puntos en el orden real', jsonb_array_length(r -> 'puntos') = 5
    and (select string_agg(x ->> 'consecutivo', ',' order by o) from jsonb_array_elements(r -> 'puntos') with ordinality t(x, o)) = '1,2,3,4,5', r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_mapa(%L, null, %s, %s)', S, j1, (select max(id) from reparto.entregas where jornada_id = j1 and consecutivo = 3)));
  perform pg_temp.ok('07.11 mapa en vivo: con el último id que ya tiene, solo vienen los puntos nuevos (4 y 5), la lista de anuladas y el último id',
    (select string_agg(x ->> 'consecutivo', ',' order by o) from jsonb_array_elements(r -> 'puntos') with ordinality t(x, o)) = '4,5'
    and r -> 'anuladas' = jsonb_build_array(e4) and (r ->> 'ultimo_id')::bigint = (select max(id) from reparto.entregas where jornada_id = j1), r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_mapa(%L, null, %s, %s)', S, j1, (select max(id) from reparto.entregas where jornada_id = j1)));
  perform pg_temp.ok('07.12 mapa en vivo sin nada nuevo: cero puntos (respuesta pequeña)', r -> 'puntos' = '[]'::jsonb and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_mapa(%L, null, null, -1)', S))) = '22023', r::text);
  perform pg_temp.ok('07.08 fecha futura: 22023', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_avance(%L, %L::date)', S, reparto.f_hoy() + 1))) = '22023');
  perform pg_temp.ok('07.09 el administrador también ve el avance', pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', A))) = 'OK');
  perform pg_temp.ok('07.10 nada de lo que ve el repartidor ni el supervisor trae nombre, dirección ni teléfono del suscriptor',
    (pg_temp.rpc(format('public.geoportal_reparto_detalle(%L, %s)', S, j1))::text || pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R1, j1))::text
     || pg_temp.rpc(format('public.geoportal_reparto_mapa(%L)', S))::text) !~* '(direcci|telefono|teléfono|ZTREP CALLE|nombre_suscriptor)');

  -- ===== 08. Otro día =====
  insert into reparto.jornadas (fecha, repartidor, origen, fuente, total) values (reparto.f_hoy() - 1, R1, 'inventada', 'inventada', 0) returning id into j3;
  perform pg_temp.ok('08.01 en la lista de ayer no se entrega hoy (55000)', pg_temp.ent(R1, j3, '880000000110') ->> 'msg' = 'Esta lista es de otro día: vuelva a escoger la ruta');
  insert into reparto.entregas (jornada_id, contrato, consecutivo, lon, lat, precision_m, id_cliente, autor, registrado_en)
    values (j3, '880000000111', 101, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '1 day') returning id into e1;
  perform pg_temp.ok('08.02 el repartidor no anula una suya de ayer; el supervisor sí',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', R1, e1, 'ZTREP anular la de ayer'))) = '42501'
    and (pg_temp.rpc(format('public.geoportal_reparto_anular(%L, %s, %L)', S, e1, 'ZTREP anular la de ayer')) ->> 'ok')::boolean);
  insert into reparto.entregas (jornada_id, contrato, consecutivo, lon, lat, precision_m, id_cliente, autor, registrado_en)
    values (j3, '880000000110', 102, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '10 days');
  perform pg_temp.ok('08.03 una entrega de respaldo (sin período) de ANTES de la fecha de reparto no cuenta para este período: se entrega',
    pg_temp.err(pg_temp.ent(R1, j1, '880000000110')) = 'OK');
  insert into reparto.entregas (jornada_id, contrato, consecutivo, periodo_reparto, lon, lat, precision_m, id_cliente, autor, registrado_en)
    values (j3, '880000000109', 103, v_mes_ant, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '1 hour'),
           (j3, '880000000108', 104, null, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '1 day');
  perform pg_temp.ok('08.04 una entrega del período ANTERIOR (aunque sea de hoy) no cuenta: se entrega', pg_temp.err(pg_temp.ent(R1, j1, '880000000109')) = 'OK');
  perform pg_temp.ok('08.05 una entrega de respaldo (sin período) DESPUÉS de la fecha de reparto sí cuenta: no se registra otra vez',
    pg_temp.err(pg_temp.ent(R1, j1, '880000000108')) = '23505');

  -- ===== 09. Solo inserción =====
  begin
    update reparto.entregas set lat = 0 where id = e4;
    perform pg_temp.ok('09.01 UPDATE directo rechazado por el disparador', false);
  exception when sqlstate '55000' then perform pg_temp.ok('09.01 UPDATE directo rechazado por el disparador', true);
  end;
  begin
    delete from reparto.entregas_anuladas where entrega_id = e4;
    perform pg_temp.ok('09.02 DELETE de una anulación rechazado', false);
  exception when sqlstate '55000' then perform pg_temp.ok('09.02 DELETE de una anulación rechazado', true);
  end;
  begin
    truncate reparto.jornada_items;
    perform pg_temp.ok('09.03 TRUNCATE rechazado', false);
  exception when sqlstate '55000' then perform pg_temp.ok('09.03 TRUNCATE rechazado', true);
  end;

  -- ===== 10. Seguridad y lo que no se toca =====
  perform pg_temp.ok('10.01 service_role ejecuta las 13 RPC; anon y authenticated no',
    (select count(*) = 13 and bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute'))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%'));
  perform pg_temp.ok('10.02 nadie más que el dueño ejecuta funciones de reparto',
    not exists (select 1 from pg_proc p where p.pronamespace = 'reparto'::regnamespace
                  and (has_function_privilege('service_role', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
  perform pg_temp.ok('10.03 ninguna tabla ni vista de reparto se lee como anon, authenticated o service_role',
    not exists (select 1 from pg_class c where c.relnamespace = 'reparto'::regnamespace and c.relkind in ('r','p','v')
                  and (has_table_privilege('service_role', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select') or has_table_privilege('anon', c.oid, 'select'))));
  perform pg_temp.ok('10.04 ninguna función de reparto con DELETE o UPDATE sin WHERE', (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = to_regnamespace('reparto') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\m(where|using)\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0);
  perform pg_temp.ok('10.05 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
  perform pg_temp.ok('10.06 las 4 funciones de permisos no cambiaron', not exists (select 1 from ztrep_antes z where z.f <> 'campo' and md5(pg_get_functiondef(to_regprocedure(z.f))) is distinct from z.md5));
  perform pg_temp.ok('10.07 la huella de campo es la misma que antes de la migración (el reparto no toca campo)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) = (select z.md5 from ztrep_antes z where z.f = 'campo'));
  perform pg_temp.ok('10.09 el Dell (homelab_lectura): USAGE sobre reparto y SELECT sobre las 8 tablas, nada más', has_schema_privilege('homelab_lectura', 'reparto', 'usage') and (select bool_and(has_table_privilege('homelab_lectura', c.oid, 'select') = (c.relkind = 'r' and c.relname = any (array['parametros', 'lotes', 'lote_filas', 'lotes_anulados', 'jornadas', 'jornada_items', 'entregas', 'entregas_anuladas'])) and not has_table_privilege('homelab_lectura', c.oid, 'insert, update, delete, truncate')) from pg_class c where c.relnamespace = 'reparto'::regnamespace and c.relkind in ('r','v','m')) and (select count(*) from pg_class c where c.relnamespace = 'reparto'::regnamespace and c.relkind = 'r' and has_table_privilege('homelab_lectura', c.oid, 'select')) = 8 and not exists (select 1 from pg_proc p where (p.pronamespace = 'reparto'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%')) and has_function_privilege('homelab_lectura', p.oid, 'execute')));
  perform pg_temp.ok('10.10 el reparto no escribe en el calendario: solo las filas de prueba',
    (select count(*) from scrr.calendario_ciclos where autor like 'ztrep.%') = 4 and not exists (select 1 from scrr.calendario_ciclos where autor like 'ztrep.%' and ciclo not in (97, 98)));
  perform pg_temp.ok('10.08 ninguna función de reparto ni RPC sin search_path fijo',
    not exists (select 1 from pg_proc p where (p.pronamespace = 'reparto'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%'))
                  and p.prokind = 'f' and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')));

  -- ===== 11. Tiempos con el volumen real (en producción: ~114 mil contratos por período, 6 períodos) =====
  t0 := clock_timestamp();
  r := pg_temp.rpc(format('public.geoportal_reparto_contexto(%L)', R1));
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('11.01 contexto (rutas del período agrupadas) en menos de 5 s: ' || ms || ' ms', pg_temp.err(r) = 'OK' and ms < 5000, ms::text);
  t0 := clock_timestamp();
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '98', '880102'));
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('11.02 empezar una ruta del período en menos de 5 s: ' || ms || ' ms', pg_temp.err(r) = 'OK' and ms < 5000, ms::text);
  t0 := clock_timestamp();
  r := pg_temp.ent(R1, (r -> 'jornada' ->> 'id')::bigint, '880000000201');
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('11.03 una entrega en menos de 1 s: ' || ms || ' ms', pg_temp.err(r) in ('OK', '23505') and ms < 1000, ms::text || ' ' || r::text);
  t0 := clock_timestamp();
  r := pg_temp.ent(R1, ji, '880000000999');
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('11.04 sin ruta, un código que no está en cartera (recorre el período) en menos de 3 s: ' || ms || ' ms', ms < 3000, ms::text);
  t0 := clock_timestamp();
  r := pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', S));
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('11.05 avance del día en menos de 3 s: ' || ms || ' ms', pg_temp.err(r) = 'OK' and ms < 3000, ms::text);

  -- ===== 12. Calendario de reparto: falta la fecha (respaldo de 15 días), sin ruta y cambio del calendario en el día =====
  insert into reparto.entregas (jornada_id, contrato, consecutivo, lon, lat, precision_m, id_cliente, autor, registrado_en)
    values (j3, '880000000501', 105, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '20 days'),
           (j3, '880000000502', 106, -73.25, 10.47, 5, gen_random_uuid(), R1, now() - interval '10 days');
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '97', '970101'));
  j97 := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('12.01 ciclo sin fecha de reparto: la jornada va en respaldo y trae el aviso para la pantalla',
    (r -> 'jornada' ->> 'respaldo')::boolean and r -> 'jornada' -> 'periodo_reparto' = 'null'::jsonb
    and r -> 'jornada' ->> 'aviso' = 'Al ciclo 97 le falta la fecha de reparto en el calendario: se toman como entregadas las facturas de los últimos 15 días.', (r -> 'jornada')::text);
  perform pg_temp.ok('12.02 respaldo de 15 días: la de hace 20 días queda pendiente; la de hace 10, entregada', pg_temp.pend(r) = '880000000501', pg_temp.pend(r));
  r := pg_temp.ent(R1, j97, '880000000501');
  perform pg_temp.ok('12.03 se entrega en respaldo: sin período, con el aviso', (r ->> 'respaldo')::boolean and r -> 'periodo_reparto' = 'null'::jsonb and r ->> 'aviso' like 'Al ciclo 97 le falta%', r::text);
  r := pg_temp.ent(R1, ji, '880000000302');
  perform pg_temp.ok('12.04 sin ruta, un contrato sin ciclo de calendario (9999): el período es el mes del día', r ->> 'periodo_reparto' = v_mes and not (r ->> 'respaldo')::boolean, r::text);
  r := pg_temp.ent(R1, ji, '880000000303');
  perform pg_temp.ok('12.05 sin ruta, un contrato cuyo ciclo no tiene fecha de reparto: respaldo con aviso', (r ->> 'respaldo')::boolean and r ->> 'aviso' like 'Al ciclo 97 le falta%', r::text);
  insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, etapas, motivo, autor)
    values (v_mes, 97, v_hoy + 10, v_hoy + 15, jsonb_build_object('lectura', v_hoy::text, 'reparto', v_hoy::text), 'ZTREP llega la fecha de reparto', A);
  r := pg_temp.rpc(format('public.geoportal_reparto_empezar(%L, %L, %L, %L)', R1, 'anterior', '97', '970101'));
  j97b := (r -> 'jornada' ->> 'id')::bigint;
  perform pg_temp.ok('12.06 el supervisor llena la fecha de reparto en el día: al volver a abrir la ruta es otra jornada, ya con el período y sin aviso',
    j97b <> j97 and r -> 'jornada' ->> 'periodo_reparto' = v_mes and not (r -> 'jornada' ->> 'respaldo')::boolean and r -> 'jornada' -> 'aviso' = 'null'::jsonb, (r -> 'jornada')::text);
  perform pg_temp.ok('12.07 con la fecha nueva (hoy): la entrega de respaldo de hoy cuenta; la de hace 10 días ya no', pg_temp.pend(r) = '880000000502', pg_temp.pend(r));
  r := pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', S));
  r := pg_temp.rpc(format('public.geoportal_reparto_calendario(%L)', S));
  perform pg_temp.ok('12.09 calendario en solo lectura: el ciclo 98 con su fecha de reparto de este mes; el 97 con la que se llenó hoy; sin enlace para quien no tiene dashboard_campo',
    (select x ->> 'reparto' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 98) = (v_hoy - 2)::text
    and (select x ->> 'reparto' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 97) = v_hoy::text
    and (select x -> 'en_reparto_hoy' ->> 'periodo' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 98) = v_mes
    and not (r ->> 'puede_cambiar')::boolean and (pg_temp.rpc(format('public.geoportal_reparto_calendario(%L)', 'ztrep.supcal@emdupar.gov.co')) ->> 'puede_cambiar')::boolean, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_calendario(%L, %L)', S, to_char(date_trunc('month', v_hoy) + interval '1 month', 'YYYYMM')));
  perform pg_temp.ok('12.10 el calendario del mes siguiente: la fecha que aún no llega, y el período que se reparte hoy sigue siendo este mes',
    (select x ->> 'reparto' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 98) = (v_hoy + 3)::text
    and (select x -> 'en_reparto_hoy' ->> 'periodo' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 98) = v_mes, r::text);
  perform pg_temp.ok('12.11 el repartidor no ve el calendario (42501); un período mal escrito: 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_calendario(%L)', R1))) = '42501' and pg_temp.err(pg_temp.rpc(format('public.geoportal_reparto_calendario(%L, %L)', S, '2026-11'))) = '22023');
  r := pg_temp.rpc(format('public.geoportal_reparto_avance(%L)', S));
  perform pg_temp.ok('12.08 el avance del supervisor muestra el período de reparto y el respaldo de cada jornada',
    (select y ->> 'respaldo' from jsonb_array_elements(r -> 'filas') y where (y ->> 'jornada_id')::bigint = j97) = 'true'
    and (select y ->> 'periodo_reparto' from jsonb_array_elements(r -> 'filas') y where (y ->> 'jornada_id')::bigint = j1) = v_mes, (r -> 'filas')::text);

  -- ===== 13. Lo entregado con el buscador NO mueve el punto de avance (David, 24-nov) =====
  -- pendientes de la ruta en este punto: 107 (3.º), 101 (6.º), 103 (9.º), 111 (11.º) y 112 (12.º)
  r := pg_temp.ent(R2, j2, '880000000107');            -- tocando la lista: el 3.º; lo anterior ya está entregado
  v_orden := pg_temp.salt(pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R2, j2)));
  perform pg_temp.ok('13.01 tocando la lista el 3.º (lo anterior ya está entregado): ningún saltado', (r ->> 'consecutivo') is not null and v_orden = '', v_orden || ' ' || r::text);
  r := pg_temp.entb(R2, j2, '880000000111');           -- con el buscador: el 11.º
  r2b := pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R2, j2));
  perform pg_temp.ok('13.02 una entrega con el buscador (el 11.º) NO marca como saltados al 101 (6.º) ni al 103 (9.º): el punto de avance sigue en el 3.º',
    (r ->> 'consecutivo') is not null and pg_temp.salt(r2b) = '' and pg_temp.pend(r2b) = '880000000101,880000000103,880000000112'
    and (select por_buscador from reparto.entregas where id = (r ->> 'entrega_id')::bigint), pg_temp.pend(r2b) || ' | ' || pg_temp.salt(r2b));
  r := pg_temp.ent(R2, j2, '880000000103');            -- tocando la lista el 9.º: ahora sí, el 101 queda saltado
  perform pg_temp.ok('13.03 al tocar en la lista el 9.º, el 101 (6.º) pasa a «Saltado»', pg_temp.salt(pg_temp.rpc(format('public.geoportal_reparto_lista(%L, %s)', R2, j2))) = '880000000101');
  r := pg_temp.rpc(format('public.geoportal_reparto_detalle(%L, %s)', S, j2));
  perform pg_temp.ok('13.04 el supervisor ve el orden real completo, con la del buscador (3, 11, 9), y los saltados con la misma regla',
    (select string_agg(x ->> 'orden_lectura', ',' order by (x ->> 'consecutivo')::int) from jsonb_array_elements(r -> 'entregas') x) like '%3,11,9'
    and (select string_agg(x ->> 'contrato', ',' order by (x ->> 'orden_lectura')::int) from jsonb_array_elements(r -> 'saltados') x) = '880000000101', r::text);

  -- ===== 14. El ciclo del archivo se DEDUCE de sus contratos («todo comienza con el archivo de rutas», David, 24-nov) =====
  v_n := (select count(*) from reparto.lotes);
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, null, %L, %L::jsonb, false)', S, 'previa.xlsx', md5('p1') || md5('p2'), 'ruta', 'ZT-PREVIA',
         '[{"contrato":"880000000201"},{"contrato":"880000000301"},{"contrato":"880000000304"},{"contrato":"880000000977"}]'));
  perform pg_temp.ok('14.01 vista previa: deduce el ciclo 98 (201 por las rutas aunque la cartera diga 97; 301 «98» y 304 «098» por la cartera, comparación numérica), cuenta 1 sin registro y NO escribe nada',
    (r ->> 'ok')::boolean and (r ->> 'previa')::boolean and r ->> 'ciclo' = '98' and (r ->> 'ciclo_deducido')::boolean and (r ->> 'sin_registro')::int = 1
    and r -> 'por_ciclo' = '[{"ciclo": "98", "contratos": 3}]'::jsonb and (select count(*) from reparto.lotes) = v_n, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, null, %L, %L::jsonb)', S, 'dos_ciclos.xlsx', md5('d1') || md5('d2'), 'ruta', 'ZT-MAL',
         '[{"contrato":"880000000101"},{"contrato":"880000000102"},{"contrato":"880000000501"},{"contrato":"880000000977"}]'));
  perform pg_temp.ok('14.02 contratos de más de un ciclo: se rechaza sin escribir nada, con el detalle por ciclo (los sin registro no cuentan)',
    not (r ->> 'ok')::boolean and r -> 'errores' ->> 0 = 'El archivo tiene contratos de más de un ciclo: 98: 2 · 97: 1. Un archivo debe ser de un solo ciclo.'
    and (select count(*) from reparto.lotes) = v_n, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, %L, %L, %L::jsonb)', S, 'otro_rotulo.xlsx', md5('o1') || md5('o2'), 'ruta', '15', 'ZT-ROTULO',
         '[{"contrato":"880000000102"},{"contrato":"880000000101"}]'));
  perform pg_temp.ok('14.03 el ciclo deducido manda aunque llegue otro escrito; la ruta es solo el rótulo que escribió el supervisor',
    (r ->> 'ok')::boolean and r ->> 'ciclo' = '98' and (select ciclo || '|' || ruta from reparto.lotes where id = (r ->> 'lote_id')::uuid) = '98|ZT-ROTULO', r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, null, null, %L::jsonb)', S, 'sin_registro.xlsx', md5('s1') || md5('s2'), 'ciclo',
         '[{"contrato":"880000000977"},{"contrato":"880000000978"}]'));
  perform pg_temp.ok('14.04 si TODOS son sin registro y no viene el ciclo: no escribe y pide escogerlo a mano',
    not (r ->> 'ok')::boolean and (r ->> 'pide_ciclo')::boolean and r -> 'errores' ->> 0 like 'Ninguno de los 2 contratos está en las rutas ni en la cartera%' and (select count(*) from reparto.lotes) = v_n + 1, r::text);
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, %L, null, %L::jsonb)', S, 'sin_registro.xlsx', md5('s1') || md5('s2'), 'ciclo', '097',
         '[{"contrato":"880000000977"},{"contrato":"880000000978"}]'));
  perform pg_temp.ok('14.05 con el ciclo escogido a mano («097» = 97), se carga, con los 2 sin registro avisados',
    (r ->> 'ok')::boolean and r ->> 'ciclo' = '97' and not (r ->> 'ciclo_deducido')::boolean and (r ->> 'sin_registro')::int = 2
    and (select ciclo from reparto.lotes where id = (r ->> 'lote_id')::uuid) = '97', r::text);
  t0 := clock_timestamp();
  r := pg_temp.rpc(format('public.geoportal_reparto_lote_cargar(%L, %L, %L, %L, null, null, %L::jsonb, false)', S, 'grande.xlsx', md5('g1') || md5('g2'), 'ciclo',
         (select jsonb_agg(jsonb_build_object('contrato', (880000100000 + g)::text)) from generate_series(1, 9000) g)));
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  perform pg_temp.ok('14.07 deducir el ciclo de un archivo de 9.000 contratos (cruza el período de rutas y la cartera) en menos de 5 s: ' || ms || ' ms',
    (r ->> 'pide_ciclo')::boolean and (r ->> 'sin_registro')::int = 9000 and ms < 5000, ms::text || ' ' || left(r::text, 200));
  perform pg_temp.ok('14.06 la auditoría dice si el ciclo se dedujo', exists (select 1 from public.geoportal_auditoria where accion = 'reparto_lote_cargar'
    and referencia = (select id::text from reparto.lotes where nombre_archivo = 'sin_registro.xlsx') and detalle ->> 'ciclo_deducido' = 'false' and detalle ->> 'ciclo' = '97'));
end $$;

-- Resultado: termina SIEMPRE en un ERROR (deshace todo). «N de N … SIN FALLAS» es el éxito.
do $$
declare v_tot int; v_ok int; v_fallas text; v_tiempos text;
begin
  select count(*), count(*) filter (where ok), string_agg(format('%s — %s', nombre, coalesce(detalle, '')), E'\n' order by n) filter (where not ok),
         string_agg(nombre, E'\n' order by n) filter (where nombre like '11.%' or nombre like '14.07%')
    into v_tot, v_ok, v_fallas, v_tiempos from ztrep_res;
  if v_ok = v_tot then
    raise exception 'RESULTADO: % de % pruebas correctas — SIN FALLAS (este ERROR es el esperado: deshace todo)%', v_ok, v_tot, E'\nTiempos:\n' || coalesce(v_tiempos, '');
  else
    raise exception 'RESULTADO: % de % pruebas correctas — FALLAS:%', v_ok, v_tot, E'\n' || v_fallas;
  end if;
end $$;

rollback;
