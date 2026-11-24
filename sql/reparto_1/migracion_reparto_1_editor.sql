-- REPARTO DE FACTURAS · COMMIT 1 (SQL) · MIGRACIÓN (una transacción) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
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

-- 2. Archivos de rutas que carga el supervisor (origen «nueva»). David, 24-nov: la plantilla es LA MISMA del archivo de rutas de facturación
--    (CÓDIGO_DEL_CONTRATO, CICLO, DIRECCIÓN, RUTA, CONSECUTIVO_EN_LA_RUTA, NÚMERO_CONSECUTIVO_DE_PREDIO). Un archivo puede traer varias rutas y varios ciclos:
--    cada (ciclo, ruta) es una opción para el repartidor. La DIRECCIÓN se valida como columna en la pantalla pero NO llega aquí: no se guarda.
create table reparto.lotes (
  id              uuid        primary key default gen_random_uuid(),
  nombre_archivo  text        not null check (length(btrim(nombre_archivo)) between 1 and 200),
  archivo_sha256  text        not null check (archivo_sha256 ~ '^[0-9a-f]{64}$'),
  filas           integer     not null check (filas between 1 and 20000),
  rutas           integer     not null check (rutas >= 1),                     -- cuántas (ciclo, ruta) trae
  sin_registro    integer     not null default 0 check (sin_registro >= 0),   -- contratos que no están en rutas ni en cartera (se aceptan con aviso)
  otro_ciclo      integer     not null default 0 check (otro_ciclo >= 0),     -- filas cuyo CICLO no coincide con bi.v_rutas_geoportal (se cargan: manda el archivo)
  autor           text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en       timestamptz not null default now()
);
create index lotes_creado_idx on reparto.lotes (creado_en desc);

create table reparto.lote_filas (
  lote_id             uuid    not null references reparto.lotes (id),
  ciclo               text    not null check (ciclo ~ '^[0-9]{1,4}$'),
  ruta                text    not null check (ruta ~ '^[A-Za-z0-9 _.-]{1,20}$'),
  orden               integer not null check (orden >= 1),                     -- 1…N dentro de su (ciclo, ruta): CONSECUTIVO_EN_LA_RUTA y, en el empate, el de predio
  contrato            text    not null check (contrato ~ '^[0-9]{1,12}$'),
  consecutivo_ruta    numeric not null,
  consecutivo_predio  numeric,
  primary key (lote_id, ciclo, ruta, orden),
  unique (lote_id, contrato)
);

create table reparto.lotes_anulados (
  lote_id    uuid        primary key references reparto.lotes (id),
  motivo     text        not null check (length(btrim(motivo)) between 10 and 300),
  autor      text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en  timestamptz not null default now()
);

-- 3. Jornadas: una por (fecha, repartidor, fuente). La fuente es la ruta exacta de donde salió la lista:
--    'anterior:<periodo>:<ciclo>:<ruta>' · 'nueva:<lote_id>:<ciclo>:<ruta>' · 'inventada' (más '|<período de reparto>' en las de ruta)
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
  check (origen <> 'nueva' or ruta is not null),
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
    -- cada (ciclo, ruta) de cada archivo vigente es una opción
    'nuevas', (select coalesce(jsonb_agg(jsonb_build_object('id', g.lote_id, 'nombre_archivo', g.nombre_archivo, 'ciclo', g.ciclo, 'ruta', g.ruta,
                                                            'filas', g.n, 'cargado_en', g.creado_en,
                                                            'reparto', (select jsonb_build_object('periodo', p.periodo, 'desde', p.desde) from reparto.f_periodo_reparto(g.ciclo) p))
                                         order by reparto.f_num(g.ciclo), reparto.f_num(g.ruta) nulls last, g.ruta, g.creado_en desc), '[]'::jsonb)
                 from (select f.lote_id, l.nombre_archivo, l.creado_en, f.ciclo, f.ruta, count(*) as n
                         from reparto.lote_filas f join reparto.lotes l on l.id = f.lote_id
                        where not exists (select 1 from reparto.lotes_anulados a where a.lote_id = l.id)
                          and l.creado_en >= now() - make_interval(days => (reparto.f_param('lote_vigencia_dias'))::int)
                        group by f.lote_id, l.nombre_archivo, l.creado_en, f.ciclo, f.ruta) g),
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
    if v_ciclo !~ '^[0-9]{1,4}$' or v_ruta = '' then perform reparto.f_err('Escoja el ciclo y la ruta del archivo'); end if;
    if not exists (select 1 from reparto.lote_filas f where f.lote_id = p_lote and f.ciclo = v_ciclo and f.ruta = v_ruta) then
      perform reparto.f_err('Esa ruta no está en el archivo');
    end if;
    v_fuente := 'nueva:' || p_lote::text || ':' || v_ciclo || ':' || v_ruta;
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
    select array_agg(f.contrato order by f.orden) into v_lista from reparto.lote_filas f where f.lote_id = p_lote and f.ciclo = v_ciclo and f.ruta = v_ruta;
    insert into reparto.jornadas (fecha, repartidor, origen, fuente, ciclo, ruta, lote_id, total, periodo_reparto, reparto_desde, respaldo)
      values (v_hoy, v_email, 'nueva', v_fuente, v_ciclo, v_ruta, p_lote, coalesce(cardinality(v_lista), 0), v_rep.periodo, v_rep.desde, v_rep.periodo is null)
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

-- Las filas del archivo de rutas, ya normalizadas (función pura; sin tablas temporales): ciclo como número (sin ceros a la izquierda), ruta recortada,
-- consecutivos numéricos; y los textos tal como llegaron, para los mensajes de error.
create function reparto.f_filas_lote(p_filas jsonb) returns table (fila integer, contrato text, ciclo text, ruta text, cr numeric, cp numeric,
                                                                    bruto_c text, bruto_ci text, bruto_r text, bruto_cr text, bruto_cp text)
language sql immutable set search_path = pg_catalog as $$
  -- validaciones EN LÍNEA (sin llamar a f_num ni f_contrato por fila: con 10.000 filas serían decenas de miles de llamadas)
  select y.fila,
         case when y.c ~ '^[0-9]{1,12}$' then y.c end,
         case when y.ci ~ '^[0-9]{1,4}(\.0+)?$' then ((split_part(y.ci, '.', 1))::integer)::text end,
         case when y.r ~ '^[A-Za-z0-9 _.-]{1,20}$' then y.r end,
         case when y.cr ~ '^[0-9]{1,15}(\.0+)?$' then (split_part(y.cr, '.', 1))::numeric end,
         case when y.cp ~ '^[0-9]{1,15}(\.0+)?$' then (split_part(y.cp, '.', 1))::numeric end,
         y.c0, y.ci0, y.r0, y.cr0, nullif(y.cp, '')
    from (select x.o::integer + 1 as fila, x.v ->> 'contrato' as c0, x.v ->> 'ciclo' as ci0, x.v ->> 'ruta' as r0, x.v ->> 'consecutivo_ruta' as cr0,
                 btrim(coalesce(x.v ->> 'contrato', '')) as c, btrim(coalesce(x.v ->> 'ciclo', '')) as ci, btrim(coalesce(x.v ->> 'ruta', '')) as r,
                 btrim(coalesce(x.v ->> 'consecutivo_ruta', '')) as cr, btrim(coalesce(x.v ->> 'consecutivo_predio', '')) as cp
            from jsonb_array_elements(p_filas) with ordinality x(v, o)) y
$$;

-- Cargar un archivo de rutas (David, 24-nov: LA MISMA estructura del archivo de rutas de facturación que alimenta hechos.rutas_consecutivos).
-- Cada fila llega como {contrato, ciclo, ruta, consecutivo_ruta, consecutivo_predio}: la DIRECCIÓN la valida la pantalla como columna y NO se envía ni se guarda.
--  · ciclo y ruta salen de cada fila; un archivo puede traer varias rutas y varios ciclos: cada (ciclo, ruta) es una opción para el repartidor;
--  · el orden, dentro de cada (ciclo, ruta): CONSECUTIVO_EN_LA_RUTA (numérico) y, en el empate, NÚMERO_CONSECUTIVO_DE_PREDIO; al final el contrato;
--  · si el CICLO de una fila no coincide con bi.v_rutas_geoportal para ese contrato (comparación numérica), se avisa cuántos y cuáles, pero se carga
--    igual: manda el archivo;
--  · contratos repetidos en el archivo: se rechaza con la lista; los que no están ni en rutas ni en cartera se aceptan con aviso;
--  · p_confirmar = false es la VISTA PREVIA: valida y devuelve las rutas y los avisos sin escribir nada;
--  · forma: de 1 a tope_filas_lote filas; si hay errores no escribe nada y devuelve hasta 20, con su fila de Excel (la 1 es el encabezado);
--  · el mismo archivo (huella), de la misma persona, el mismo día y sin anular, devuelve el mismo lote (doble clic).
create function public.geoportal_reparto_lote_cargar(p_solicitante text, p_nombre text, p_sha256 text, p_filas jsonb, p_confirmar boolean default true,
                                                     p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_tope integer := (reparto.f_param('tope_filas_lote'))::integer; v_n integer;
        v_err jsonb; v_id uuid; v_sin integer; v_otro integer; v_otro_lista jsonb; v_rutas jsonb; v_nrutas integer;
begin
  if length(btrim(coalesce(p_nombre, ''))) not between 1 and 200 then perform reparto.f_err('Nombre de archivo no válido'); end if;
  if coalesce(p_sha256, '') !~ '^[0-9a-f]{64}$' then perform reparto.f_err('Huella del archivo no válida'); end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then perform reparto.f_err('El archivo no trae filas'); end if;
  v_n := jsonb_array_length(p_filas);
  if v_n < 1 or v_n > v_tope then perform reparto.f_err(format('El archivo debe tener entre 1 y %s filas (trae %s)', v_tope, v_n)); end if;
  -- 1. la forma de cada fila y los contratos repetidos
  with f as materialized (select * from reparto.f_filas_lote(p_filas)),
       e as (select fila, 'Fila ' || fila || ': el contrato «' || left(coalesce(bruto_c, ''), 20) || '» no es válido (solo números, de 1 a 12)' as m from f where contrato is null
             union all select fila, 'Fila ' || fila || ': el CICLO «' || left(coalesce(bruto_ci, ''), 12) || '» no es válido (número de hasta 4 cifras)' from f where ciclo is null
             union all select fila, 'Fila ' || fila || ': la RUTA «' || left(coalesce(bruto_r, ''), 24) || '» no es válida (hasta 20 letras o números)' from f where ruta is null
             union all select fila, 'Fila ' || fila || ': el CONSECUTIVO_EN_LA_RUTA «' || left(coalesce(bruto_cr, ''), 20) || '» no es un número' from f where cr is null
             union all select fila, 'Fila ' || fila || ': el NÚMERO_CONSECUTIVO_DE_PREDIO «' || left(bruto_cp, 20) || '» no es un número' from f where bruto_cp is not null and cp is null)
  select jsonb_agg(m order by fila) into v_err from (select * from e order by fila limit 20) z;
  if v_err is not null then return jsonb_build_object('ok', false, 'errores', v_err); end if;
  select jsonb_agg(format('El contrato %s está repetido (filas %s)', contrato, filas) order by primera) into v_err
    from (select contrato, string_agg(fila::text, ', ' order by fila) as filas, min(fila) as primera from reparto.f_filas_lote(p_filas) group by contrato having count(*) > 1 order by min(fila) limit 20) d;
  if v_err is not null then
    return jsonb_build_object('ok', false, 'errores', jsonb_build_array('El archivo trae contratos repetidos: cada contrato va una sola vez.') || v_err);
  end if;
  -- 2. avisos: CICLO distinto del de las rutas (manda el archivo) y contratos sin registro
  with f as materialized (select * from reparto.f_filas_lote(p_filas)),
       r as (select distinct on (r.contrato) r.contrato, r.ciclo from bi.v_rutas_geoportal r
              where r.contrato in (select contrato from f) order by r.contrato, reparto.f_num(r.consecutivo_ruta) nulls last),
       d as (select f.fila, f.contrato, f.ciclo, (reparto.f_num(r.ciclo)::bigint)::text as ciclo_rutas from f join r on r.contrato = f.contrato
              where reparto.f_num(r.ciclo) is not null and (reparto.f_num(r.ciclo)::bigint)::text <> f.ciclo),
       g as (select ciclo, ruta, count(*) as n from f group by 1, 2)
  select (select count(*) from d),
         (select jsonb_agg(jsonb_build_object('contrato', contrato, 'ciclo_archivo', ciclo, 'ciclo_rutas', ciclo_rutas) order by fila) from (select * from d order by fila limit 20) z),
         (select count(*) from f where not exists (select 1 from r where r.contrato = f.contrato)
             and not exists (select 1 from public.cartera_suscripcion s where s.contrato = f.contrato)),
         (select count(*) from g),
         (select jsonb_agg(jsonb_build_object('ciclo', ciclo, 'ruta', ruta, 'filas', n) order by ciclo::int, reparto.f_num(ruta) nulls last, ruta) from g)
    into v_otro, v_otro_lista, v_sin, v_nrutas, v_rutas;
  -- 3. vista previa: sin escribir nada
  if not coalesce(p_confirmar, true) then
    return jsonb_build_object('ok', true, 'previa', true, 'filas', v_n, 'rutas', v_rutas, 'otro_ciclo', v_otro, 'otro_ciclo_lista', coalesce(v_otro_lista, '[]'::jsonb), 'sin_registro', v_sin);
  end if;
  -- 4. cargar (doble clic = el mismo lote)
  perform pg_advisory_xact_lock(hashtextextended('reparto_lote:' || v_email || ':' || p_sha256, 0));
  select l.id into v_id from reparto.lotes l
   where l.archivo_sha256 = p_sha256 and l.autor = v_email and (l.creado_en at time zone 'America/Bogota')::date = reparto.f_hoy()
     and not exists (select 1 from reparto.lotes_anulados a where a.lote_id = l.id)
   order by l.creado_en desc limit 1;
  if v_id is not null then
    return jsonb_build_object('ok', true, 'lote_id', v_id, 'repetido', true, 'filas', v_n, 'rutas', v_rutas, 'otro_ciclo', v_otro, 'otro_ciclo_lista', coalesce(v_otro_lista, '[]'::jsonb), 'sin_registro', v_sin);
  end if;
  insert into reparto.lotes (nombre_archivo, archivo_sha256, filas, rutas, sin_registro, otro_ciclo, autor)
    values (btrim(p_nombre), p_sha256, v_n, v_nrutas, v_sin, v_otro, v_email) returning id into v_id;
  insert into reparto.lote_filas (lote_id, ciclo, ruta, orden, contrato, consecutivo_ruta, consecutivo_predio)
    select v_id, ciclo, ruta, row_number() over (partition by ciclo, ruta order by cr, cp nulls last, contrato), contrato, cr, cp from reparto.f_filas_lote(p_filas);
  perform reparto.f_auditar(v_email, 'reparto_lote_cargar', v_id::text,
            jsonb_build_object('nombre', btrim(p_nombre), 'sha256', p_sha256, 'filas', v_n, 'rutas', v_nrutas, 'otro_ciclo', v_otro, 'sin_registro', v_sin), p_ip);
  return jsonb_build_object('ok', true, 'lote_id', v_id, 'repetido', false, 'filas', v_n, 'rutas', v_rutas, 'otro_ciclo', v_otro, 'otro_ciclo_lista', coalesce(v_otro_lista, '[]'::jsonb), 'sin_registro', v_sin);
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
      'id', l.id, 'nombre_archivo', l.nombre_archivo, 'filas', l.filas, 'otro_ciclo', l.otro_ciclo, 'sin_registro', l.sin_registro, 'autor', l.autor, 'cargado_en', l.creado_en,
      'rutas', (select jsonb_agg(jsonb_build_object('ciclo', g.ciclo, 'ruta', g.ruta, 'filas', g.n) order by g.ciclo::int, reparto.f_num(g.ruta) nulls last, g.ruta)
                  from (select f.ciclo, f.ruta, count(*) as n from reparto.lote_filas f where f.lote_id = l.id group by 1, 2) g),
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

commit;
