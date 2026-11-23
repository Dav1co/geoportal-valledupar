-- =====================================================================
-- SCRR · CORTE 2 · 10 — esquema, utilidades, parámetros y catálogos
-- Base: la fase 0 (rama scrr-fase0, nunca publicada), SIN el esquema trabajo ni los perfiles propios (D1 del 21-nov; decisión 3 del 22-nov).
-- Esquema cerrado a anon, authenticated y service_role: todo pasa por las RPC public.geoportal_scrr_* (SECURITY DEFINER), que solo ejecuta service_role.
-- =====================================================================

create schema scrr;
revoke all on schema scrr from public, anon, authenticated, service_role;
comment on schema scrr is 'Motor SCRR (modo «Cartera» del Geoportal Comercial; corte 2, 22-nov-2026). Solo por RPC public.geoportal_scrr_*. Nada se borra salvo lo que dice cada función con su porqué.';

-- Disparador común: tablas de solo inserción (nada se actualiza ni se borra: se oculta o se anula con un evento nuevo)
create function scrr.f_solo_insercion() returns trigger
language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'La tabla %.% es de solo inserción: no se actualiza ni se borra (se anula u oculta con un evento nuevo)', tg_table_schema, tg_table_name
    using errcode = '55000', hint = 'msg_usuario';
end $$;

-- Utilidades puras (portables: PL/pgSQL y SQL estándar)
create function scrr.f_barrio_norm(p text) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(upper(regexp_replace(translate(btrim(coalesce(p, '')), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'), '\s+', ' ', 'g')), '')
$$;
-- Número seguro: solo el formato canónico que el navegador ya normalizó (punto decimal, sin miles); lo demás es nulo, nunca un error
create function scrr.f_num(p text) returns numeric
language sql immutable parallel safe set search_path = pg_catalog as $$
  select case when btrim(p) ~ '^-?[0-9]{1,12}(\.[0-9]{1,4})?$' then btrim(p)::numeric else null end
$$;
-- Fecha segura: solo aaaa-mm-dd válida entre 2020 y 2100
create function scrr.f_fecha(p text) returns date
language plpgsql immutable set search_path = pg_catalog as $$
declare d date;
begin
  if p is null or btrim(p) !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then return null; end if;
  d := btrim(p)::date;
  return d;
exception when others then return null;
end $$;
-- Hora segura: hh:mm o hh:mm:ss
create function scrr.f_hora(p text) returns time
language plpgsql immutable set search_path = pg_catalog as $$
begin
  if p is null or btrim(p) !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' then return null; end if;
  return btrim(p)::time;
exception when others then return null;
end $$;
-- Texto acotado: recorta espacios, nulo si queda vacío, a lo sumo p_max caracteres
create function scrr.f_txt(p text, p_max integer) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select left(nullif(btrim(coalesce(p, '')), ''), p_max)
$$;

-- 1. Parámetros versionados (una fila nueva por cambio; la vigente se deriva)
create table scrr.parametros (
  clave          text        not null check (clave ~ '^[a-z][a-z0-9_]{1,59}$'),
  valor          jsonb       not null,
  vigente_desde  timestamptz not null default clock_timestamp(),
  autor          text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  motivo         text        not null check (length(btrim(motivo)) between 5 and 300),
  primary key (clave, vigente_desde)
);
create view scrr.v_parametros_vigentes as
  select distinct on (clave) clave, valor, vigente_desde, autor, motivo from scrr.parametros order by clave, vigente_desde desc;

-- 2. Tipos de actividad (decisión 4 del 22-nov): en la selección se escogen Suspensión, Corte y Gestión de cobro. El corte drástico NO es un tipo aparte:
--    es una marca del Corte. El retorno sí distingue: suspendido → reinstalación; cortado → reconexión; cortado drástico → reconexión drástica.
create table scrr.tipos_actividad (
  id                 smallint primary key,
  codigo             text     not null unique check (codigo ~ '^[a-z][a-z0-9_]{1,39}$'),
  nombre             text     not null,
  actividad_campo    text,                      -- código en campo.actividades (Personal de Comercial), sin llave foránea: es otro módulo
  seleccionable      boolean  not null,         -- se escoge en la selección (Suspensión, Corte, Gestión de cobro)
  admite_drastico    boolean  not null default false,
  estado_resultante  text     check (estado_resultante in ('activo','suspendido','cortado')),   -- nulo = no cambia el estado del servicio (Gestión de cobro)
  orden              smallint not null,
  activo             boolean  not null default true
);

-- 3. Anomalías de campo (decisión 9 del 20-nov): catálogo 1–17. PROVISIONAL hasta que llegue el archivo modelo de David (ENCARGO §7).
create table scrr.anomalias (
  codigo       smallint primary key check (codigo between 1 and 99),
  nombre       text     not null unique check (nombre = upper(nombre) and length(nombre) between 3 and 60),
  provisional  boolean  not null default true,
  fuente       text     not null,
  orden        smallint not null,
  activo       boolean  not null default true
);

-- 4. Códigos heredados del archivo de actividades (estado 3 efectiva / 4 inefectiva)
create table scrr.codigos_heredados (
  campo       text     not null check (campo in ('estado')),
  codigo      smallint not null,
  significado text     not null,
  primary key (campo, codigo)
);

alter table scrr.parametros        enable row level security;
alter table scrr.tipos_actividad   enable row level security;
alter table scrr.anomalias         enable row level security;
alter table scrr.codigos_heredados enable row level security;
create trigger parametros_solo_insercion before update or delete on scrr.parametros for each row execute function scrr.f_solo_insercion();

-- 5. Auditoría, parámetros y autorización
create function scrr.f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values (lower(p_email), p_accion, p_ref, p_detalle, p_ip);
$$;

create function scrr.f_param(p_clave text) returns jsonb
language plpgsql stable security definer set search_path = scrr, pg_temp as $$
declare v jsonb;
begin
  select valor into v from scrr.v_parametros_vigentes where clave = p_clave;
  if v is null then raise exception 'Falta el parámetro %', p_clave using errcode = '55000'; end if;
  return v;
end $$;

-- Quién entra al modo «Cartera» (decisión 3 del 22-nov): el Supervisor comercial (dashboard_campo) y el administrador, por la función de campo ya publicada.
-- Sin casilla nueva, sin perfiles propios y sin tocar las 4 funciones de permisos. Devuelve el correo normalizado.
create function scrr.f_autorizar(p_solicitante text) returns text
language plpgsql security definer set search_path = pg_catalog, public, campo, scrr as $$
begin
  return campo.f_autorizar_supervision(p_solicitante);
end $$;
