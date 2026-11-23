-- =====================================================================
-- SCRR · CORTE 2 · 25 — contratos con control y excluidos manuales, calendario de ciclos, corridas de selección y facturas vencidas
-- Todo de solo inserción; lo vigente se deriva (vistas). Sin datos personales.
-- =====================================================================

-- 1. Contratos con control y EXCLUIDOS MANUALES en la misma tabla de eventos (P6 del 22-nov): la causa dice cuál es.
--    reclamo_manual cuenta en el paso «reclamo» del embudo; excluido_manual en «excluidos manuales»; las demás, en «control vigente».
create table scrr.causas_control (
  id      smallint primary key,
  codigo  text     not null unique check (codigo ~ '^[a-z][a-z0-9_]{1,39}$'),
  nombre  text     not null,
  grupo   text     not null check (grupo in ('control','reclamo','excluido')),
  activo  boolean  not null default true
);
create table scrr.control_eventos (
  id          bigint generated always as identity primary key,
  contrato    bigint      not null check (contrato > 0),
  causa_id    smallint    not null references scrr.causas_control (id),
  tipo_evento text        not null check (tipo_evento in ('alta','baja')),
  motivo      text        not null check (length(btrim(motivo)) between 10 and 200),
  origen      text        not null default 'manual' check (origen in ('manual','archivo')),   -- P10: por archivo con un motivo común
  autor       text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en   timestamptz not null default clock_timestamp()
);
create index control_eventos_contrato_idx on scrr.control_eventos (contrato, causa_id, id desc);
create view scrr.v_control_vigente as
  select u.contrato, u.causa_id, k.grupo, u.creado_en as desde, u.autor, u.origen
    from (select distinct on (contrato, causa_id) * from scrr.control_eventos order by contrato, causa_id, id desc) u
    join scrr.causas_control k on k.id = u.causa_id
   where u.tipo_evento = 'alta';

-- 2. Calendario de ciclos (decisión 7 del 20-nov; 22-nov: el calendario no es fijo y se pueden agregar ciclos). Mandan «pago oportuno» y «fecha de suspensión»;
--    las demás etapas (lectura, crítica, facturación, reparto…) van en «etapas» para contexto. Una fila nueva por cambio; cambiar una fecha ya guardada exige motivo.
create table scrr.calendario_ciclos (
  periodo           char(6)     not null check (periodo ~ '^20[0-9]{2}(0[1-9]|1[0-2])$'),
  ciclo             smallint    not null check (ciclo between 1 and 99),
  pago_oportuno     date        not null,
  fecha_suspension  date        not null,
  etapas            jsonb       not null default '{}'::jsonb check (jsonb_typeof(etapas) = 'object'),
  motivo            text        check (motivo is null or length(btrim(motivo)) between 5 and 300),
  autor             text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  vigente_desde     timestamptz not null default clock_timestamp(),
  primary key (periodo, ciclo, vigente_desde),
  constraint fechas_ck check (fecha_suspension >= pago_oportuno)
);
create view scrr.v_calendario_vigente as
  select distinct on (periodo, ciclo) periodo, ciclo, pago_oportuno, fecha_suspension, etapas, motivo, autor, vigente_desde
    from scrr.calendario_ciclos order by periodo, ciclo, vigente_desde desc;

-- 3. Facturas VENCIDAS (David, 22-nov: no vienen en el archivo; las deriva el motor al aplicar la cartera):
--    vencidas = pendientes − 1 si la fecha del archivo todavía no pasó el «pago oportuno» del ciclo del contrato en el período de esa fecha; si ya pasó, = pendientes;
--    nunca menor que 0. El ciclo sale de la cartera del día (un contrato puede cambiar de ciclo). Si el ciclo no tiene calendario en ese período, se toma la
--    regla prudente (pendientes − 1: la factura del mes aún no se cuenta vencida) y la validación lo avisa.
create function scrr.f_vencidas(p_pendientes smallint, p_pago_oportuno date, p_fecha date) returns smallint
language sql immutable parallel safe set search_path = pg_catalog as $$
  select case when p_pendientes is null then 0::smallint
              when p_pago_oportuno is not null and p_fecha > p_pago_oportuno then p_pendientes
              else greatest(p_pendientes - 1, 0)::smallint end
$$;

-- 4. Corridas de selección (P8 del 22-nov: se guarda SOLO la lista generada; de la vista previa, solo los conteos en la auditoría)
create table scrr.corridas (
  id            uuid        primary key,
  periodo       char(6)     not null,
  ciclo         smallint    not null,
  fecha_dato    date        not null,                      -- foto de cartera usada
  carga_id      uuid        not null references scrr.cargas (id),
  actividad_id  smallint    not null references scrr.tipos_actividad (id),
  filtros       jsonb       not null,
  embudo        jsonb       not null,
  contratos     integer     not null check (contratos >= 0),
  saldo_total   numeric(16,2) not null default 0,
  autor         text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en     timestamptz not null default clock_timestamp()
);
create index corridas_creado_idx on scrr.corridas (creado_en desc);
create table scrr.corrida_contratos (
  corrida_id          uuid          not null references scrr.corridas (id),
  orden               integer       not null,
  contrato            bigint        not null,
  saldo_pendiente     numeric(14,2) not null,
  facturas_vencidas   smallint      not null,
  barrio_id           smallint,
  ruta                text,
  codigo_reparto      text,
  marca               text          check (marca is null or marca in ('abono', 'abono_desde_suspension')),
  primary key (corrida_id, contrato)
);

create index corrida_contratos_contrato_idx on scrr.corrida_contratos (contrato);

-- 5. Origen de cada acta (David, 22-nov 20:45): las actas del archivo de actividades se cargan estén o no en una lista programada. corrida_id = la lista de la
--    que salió la visita (la última corrida de la MISMA actividad que traía el contrato, generada hasta el día de la visita y no más de 60 días antes); nulo =
--    actividad hecha FUERA de las listas (o del ajuste inicial: lo ya realizado antes de arrancar el motor). Las dos actualizan igual el estado del servicio.
alter table scrr.actas add column corrida_id uuid references scrr.corridas (id);
comment on column scrr.actas.corrida_id is 'Lista programada de la que salió la visita; nulo = fuera de las listas o ajuste inicial (David, 22-nov 20:45).';

do $$
declare t text;
begin
  foreach t in array array['causas_control','control_eventos','calendario_ciclos','corridas','corrida_contratos'] loop
    execute format('alter table scrr.%I enable row level security', t);
  end loop;
  foreach t in array array['control_eventos','calendario_ciclos','corridas','corrida_contratos'] loop
    execute format('create trigger %I before update or delete on scrr.%I for each row execute function scrr.f_solo_insercion()', t || '_solo_insercion', t);
  end loop;
end $$;
