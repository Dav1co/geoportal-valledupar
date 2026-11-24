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
