-- MOTOR SCRR · CORTE 2 (modo «Cartera») · ENSAYO (termina en ERROR esperado; no deja nada) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
create temp table ztscrr_permisos as select f, md5(pg_get_functiondef(to_regprocedure(f))) as md5 from unnest(array['public.geoportal_puede(text,text)', 'public.geoportal_mis_permisos(text)', 'public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)', 'public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)']) f;
-- =====================================================================
-- SCRR · CORTE 2 · 05 — GUARDIA (no aplica nada si la base no es la esperada)
-- Se niega si:
--   · el esquema scrr ya existe (el paquete no se reaplica: para rehacerlo, primero la reversa);
--   · la huella de campo no es la publicada el 22-nov 13:46 (261bed3c9242f6261f845ec4e1374b3a): el modo «Cartera» autoriza con campo.f_autorizar_supervision;
--   · campo.f_autorizar_supervision(text) no tiene su md5 publicada (5ac3368fa5f3a6347328285501894aec);
--   · public.cartera_suscripcion no es una tabla (relkind 'r') con exactamente sus 21 columnas de hoy (el cargador la actualiza: decisión 4 del 20-nov y P4 del 22-nov);
--   · faltan public.geoportal_auditoria o public.predios_comercial (vista materializada con índice único), PostgreSQL 17, hechos.facturacion_sspd o
--     redes.f_eventos_del_contrato(text); o ya existe el rol scrr_refresco.
-- No toca las 4 funciones de permisos (geoportal_admin_permisos, geoportal_mis_permisos, geoportal_puede, geoportal_admin_guardar): la verificación comprueba
-- que siguen con su md5.
-- =====================================================================
do $guardia$
declare v text;
begin
  if exists (select 1 from pg_namespace where nspname = 'scrr') then
    raise exception 'GUARDIA SCRR: el esquema scrr ya existe. Este paquete no se reaplica; si hay que rehacerlo, primero la reversa.';
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v
    from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if v is distinct from '261bed3c9242f6261f845ec4e1374b3a' then
    raise exception 'GUARDIA SCRR: la huella de campo es % y se esperaba 261bed3c9242f6261f845ec4e1374b3a (publicada el 22-nov 13:46). Deténgase y avise.', v;
  end if;
  if to_regprocedure('campo.f_autorizar_supervision(text)') is null
     or md5(pg_get_functiondef(to_regprocedure('campo.f_autorizar_supervision(text)'))) <> '5ac3368fa5f3a6347328285501894aec' then
    raise exception 'GUARDIA SCRR: campo.f_autorizar_supervision(text) no está o cambió. Deténgase y avise.';
  end if;
  if (select relkind from pg_class where oid = to_regclass('public.cartera_suscripcion')) is distinct from 'r' then
    raise exception 'GUARDIA SCRR: public.cartera_suscripcion no existe o no es una tabla.';
  end if;
  select string_agg(column_name || ':' || data_type, ',' order by ordinal_position) into v
    from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion';
  if v is distinct from 'contrato:text,estado:text,identificacion:text,nombre:text,correo:text,telefono:text,direccion:text,barrio:text,categoria:text,subcategoria:text,ciclo:text,facturas_pendientes:numeric,deuda_total:numeric,saldo_pendiente:numeric,saldo_a_favor:numeric,valor_reclamo:numeric,saldo_financiado:numeric,serial_medidor:text,codigo_reparto:text,ruta:text,periodo_carga:text' then
    raise exception 'GUARDIA SCRR: las columnas de public.cartera_suscripcion no son las esperadas: %', v;
  end if;
  if to_regclass('public.geoportal_auditoria') is null or to_regclass('public.predios_comercial') is null then
    raise exception 'GUARDIA SCRR: falta public.geoportal_auditoria o public.predios_comercial.';
  end if;
  -- Refresco del mapa comercial por el cargador (David, 22-nov): REFRESH … CONCURRENTLY exige el índice único de la vista; el rol mínimo usa MAINTAIN (PostgreSQL 17)
  if (select relkind from pg_class where oid = 'public.predios_comercial'::regclass) <> 'm'
     or not exists (select 1 from pg_index i where i.indrelid = 'public.predios_comercial'::regclass and i.indisunique and i.indpred is null) then
    raise exception 'GUARDIA SCRR: public.predios_comercial no es una vista materializada con índice único (no se podría refrescar sin bloquear el mapa).';
  end if;
  if current_setting('server_version_num')::int < 170000 then raise exception 'GUARDIA SCRR: hace falta PostgreSQL 17 (privilegio MAINTAIN).'; end if;
  if exists (select 1 from pg_roles where rolname = 'scrr_refresco') then raise exception 'GUARDIA SCRR: el rol scrr_refresco ya existe.'; end if;
  -- Selección: «facturado» = figura en hechos.facturacion_sspd (último período cargado); evento de suspensión de agua por redes.f_eventos_del_contrato
  if to_regclass('hechos.facturacion_sspd') is null
     or (select count(*) from information_schema.columns where table_schema = 'hechos' and table_name = 'facturacion_sspd' and column_name in ('periodo', 'contrato')) <> 2 then
    raise exception 'GUARDIA SCRR: falta hechos.facturacion_sspd con sus columnas periodo y contrato.';
  end if;
  if to_regprocedure('redes.f_eventos_del_contrato(text)') is null or to_regprocedure('redes.f_eventos_abiertos()') is null then
    raise exception 'GUARDIA SCRR: falta redes.f_eventos_del_contrato(text) o redes.f_eventos_abiertos() (aviso de evento por contrato, Corte 15).';
  end if;
end $guardia$;

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
-- Cifra de la cartera (David, 22-nov: un vacío vale CERO, como el script viejo): vacío o ausente → 0; número → el número; texto que no es número → nulo (rechazo)
create function scrr.f_num0(p text) returns numeric
language sql immutable parallel safe set search_path = pg_catalog as $$
  select case when nullif(btrim(coalesce(p, '')), '') is null then 0 else scrr.f_num(p) end
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

-- 3. Anomalías de campo (decisión 9 del 20-nov): catálogo 1–17, DEFINITIVO (David, 22-nov).
create table scrr.anomalias (
  codigo       smallint primary key check (codigo between 1 and 99),
  nombre       text     not null unique check (nombre = upper(nombre) and length(nombre) between 3 and 60),
  provisional  boolean  not null default false,
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

-- =====================================================================
-- SCRR · CORTE 2 · 20 — cargas del día, tablas de paso, historial de cartera, pagos, actas y respaldo de cartera_suscripcion
-- Tablas de hechos de solo inserción; el estado de una carga se deriva de carga_eventos.
-- Historial de cartera en particiones DIARIAS (se guardan 10 días: P7 del 22-nov); pagos en particiones MENSUALES (13 meses: decisión 3 del 20-nov).
-- Las tablas de paso de cartera y el respaldo de cartera_suscripcion llevan datos personales (P4 del 22-nov: el cargador actualiza cartera_suscripcion
-- COMPLETA): son copia técnica y se vacían a los 7 días (scrr.f_vaciar_paso), igual que en la fase 0. El historial NO lleva datos personales.
-- =====================================================================

-- 1. Cargas: encabezado inmutable + eventos (estado derivado)
create table scrr.cargas (
  id               uuid        primary key,
  tipo             text        not null check (tipo in ('cartera','pagos','actividades')),
  fecha_dato       date        not null,
  version          smallint    not null default 1 check (version >= 1),   -- 1, 2, 3… por tipo y fecha del dato (las anuladas también ocupan su número)
  reemplaza_id     uuid        references scrr.cargas (id),            -- la carga vigente que esta reemplaza (con motivo)
  archivo_nombre   text        not null check (length(archivo_nombre) between 1 and 200),
  archivo_sha256   text        not null check (archivo_sha256 ~ '^[0-9a-f]{64}$'),
  filas_leidas     integer     not null check (filas_leidas between 1 and 1000000),
  autor            text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en        timestamptz not null default clock_timestamp(),
  unique (tipo, fecha_dato, version),
  constraint reemplazo_ck check (reemplaza_id is null or version > 1)
);
create table scrr.carga_eventos (
  id           bigint generated always as identity primary key,
  carga_id     uuid        not null references scrr.cargas (id),
  evento       text        not null check (evento in ('iniciada','lote_recibido','validada','lote_aplicado','aplicada','rechazada','reemplazada','anulada',
                                                       'paso_vaciado','suscripcion_revertida')),
  lote         integer,
  huella       text,
  resumen      jsonb       not null default '{}'::jsonb,
  motivo       text        check (motivo is null or length(btrim(motivo)) between 10 and 300),
  autor        text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en    timestamptz not null default clock_timestamp(),
  constraint lote_ck check ((evento in ('lote_recibido','lote_aplicado')) = (lote is not null)),
  constraint motivo_ck check (evento not in ('reemplazada','anulada','rechazada','suscripcion_revertida') or motivo is not null)
);
create index carga_eventos_carga_idx on scrr.carga_eventos (carga_id, id desc);
create unique index carga_eventos_lote_uk on scrr.carga_eventos (carga_id, lote) where evento = 'lote_recibido';
create unique index carga_eventos_lote_aplicado_uk on scrr.carga_eventos (carga_id, lote) where evento = 'lote_aplicado';
create unique index carga_eventos_vaciado_uk on scrr.carga_eventos (carga_id) where evento = 'paso_vaciado';

-- Estado derivado: en_paso | validada | aplicando | aplicada | rechazada | reemplazada | anulada | inexistente
create function scrr.f_estado_carga(p_carga uuid) returns text
language sql stable security definer set search_path = scrr as $$
  select coalesce((select case e.evento when 'iniciada' then 'en_paso' when 'lote_aplicado' then 'aplicando' else e.evento end
                     from scrr.carga_eventos e
                    where e.carga_id = p_carga and e.evento in ('iniciada','validada','lote_aplicado','aplicada','rechazada','reemplazada','anulada')
                    order by e.id desc limit 1), 'inexistente')
$$;
-- Cargas VIGENTES: la última decisión sobre la carga fue «aplicada» (no reemplazada, anulada ni rechazada)
create view scrr.v_cargas_vigentes as
  select c.* from scrr.cargas c
   where (select e.evento from scrr.carga_eventos e where e.carga_id = c.id and e.evento in ('aplicada','reemplazada','anulada','rechazada') order by e.id desc limit 1) = 'aplicada';

-- 2. Tablas de paso (copia técnica; llave (carga_id, lote, fila): reenviar un lote no duplica). Se vacían a los 7 días.
create table scrr.paso_cartera (
  carga_id uuid not null references scrr.cargas (id), lote integer not null, fila integer not null,
  contrato text, estado text, identificacion text, nombre text, correo text, telefono text, direccion text, barrio text, categoria text, subcategoria text,
  ciclo text, facturas_pendientes smallint, deuda_total numeric(14,2), saldo_pendiente numeric(14,2), saldo_a_favor numeric(14,2),
  valor_reclamo numeric(14,2), saldo_financiado numeric(14,2), serial_medidor text, codigo_reparto text, ruta text,
  error text,
  primary key (carga_id, lote, fila)
);
create index paso_cartera_contrato_idx on scrr.paso_cartera (carga_id, contrato);
create table scrr.paso_pagos (
  carga_id uuid not null references scrr.cargas (id), lote integer not null, fila integer not null,
  contrato bigint, fecha_pago date, monto numeric(14,2),
  error text,
  primary key (carga_id, lote, fila)
);
create table scrr.paso_actividades (
  carga_id uuid not null references scrr.cargas (id), lote integer not null, fila integer not null,
  contrato bigint, acta text, actividad_texto text, tipo_actividad_id smallint, drastico boolean, estado_original smallint, anomalia smallint,
  observacion text, fecha_ejecucion date, hora_inicio time, hora_fin time, lectura integer, medidor text, marca text, operario text,
  error text,
  primary key (carga_id, lote, fila)
);

-- 3. Barrios normalizados y historial diario de cartera (solo contratos con saldo pendiente + fila de salida). SIN datos personales.
create table scrr.barrios (
  id          smallint generated always as identity primary key,
  nombre_norm text not null unique check (nombre_norm = upper(nombre_norm) and length(nombre_norm) between 1 and 80),
  creado_en   timestamptz not null default clock_timestamp()
);
create table scrr.cartera_historial (
  fecha_dato          date          not null,
  version             smallint      not null default 1,
  contrato            bigint        not null,
  en_cartera          boolean       not null default true,    -- false = fila de salida (con saldo en la foto anterior y hoy no)
  marca               smallint      not null default 0,       -- 0 normal; 1 comodín (contrato 99999999 o categoría «-1 …»). Sin corporativos (decisión 5 del 20-nov)
  estado              text,
  categoria           text,
  ciclo               smallint,
  ruta                text,
  codigo_reparto      text,
  barrio_id           smallint,
  facturas_pendientes smallint      not null default 0,
  facturas_vencidas   smallint      not null default 0,       -- decisión 2 del 20-nov; las DERIVA el motor al aplicar (scrr.f_vencidas, 22-nov)
  deuda_total         numeric(14,2) not null default 0,
  saldo_pendiente     numeric(14,2) not null default 0,
  saldo_a_favor       numeric(14,2) not null default 0,
  saldo_financiado    numeric(14,2) not null default 0,
  valor_reclamo       numeric(14,2) not null default 0,
  carga_id            uuid          not null,
  primary key (fecha_dato, version, contrato)
) partition by range (fecha_dato);
create view scrr.v_cartera_vigente as
  select h.* from scrr.cartera_historial h join scrr.v_cargas_vigentes v on v.id = h.carga_id;

-- 4. Pagos del día (plantilla PROVISIONAL de 3 columnas: decisión 7 del 22-nov). Llave contra duplicados al recargar: contrato + fecha + monto + ordinal.
--    Fácil de ampliar: las columnas del archivo real entran como columnas nuevas nulas, sin cambiar la llave.
create table scrr.pagos_contrato (
  contrato   bigint        not null,
  fecha_pago date          not null,
  monto      numeric(14,2) not null,
  ordinal    smallint      not null default 1,     -- 1 para el primer pago idéntico del archivo, 2 para el segundo, etc.
  carga_id   uuid          not null,
  primary key (contrato, fecha_pago, monto, ordinal)
) partition by range (fecha_pago);

-- 5. Actas del archivo de actividades (decisión 10 del 20-nov; marca de drástico en Corte). Acumulables; repetida = se ignora con conteo.
create table scrr.actas (
  id                uuid        primary key,
  contrato          bigint      not null check (contrato > 0),
  tipo_actividad_id smallint    not null references scrr.tipos_actividad (id),
  drastico          boolean     not null default false,
  fecha_ejecucion   date        not null,
  version           smallint    not null default 1 check (version >= 1),
  resultado         text        not null check (resultado in ('efectiva','inefectiva')),
  anomalia          smallint    references scrr.anomalias (codigo),
  acta_numero       text,
  observacion       text        check (observacion is null or length(observacion) <= 300),
  hora_inicio       time,
  hora_fin          time,
  lectura           integer     check (lectura is null or lectura >= 0),
  medidor           text,
  marca_medidor     text,
  operario          text,
  origen            text        not null check (origen in ('archivo','campo')),
  estado_original   smallint,
  reporte_campo_id  uuid,
  carga_id          uuid        references scrr.cargas (id),
  creado_en         timestamptz not null default clock_timestamp(),
  creado_por        text        not null check (creado_por = lower(creado_por) and position('@' in creado_por) > 1),
  unique (contrato, tipo_actividad_id, fecha_ejecucion, version),
  constraint inefectiva_con_anomalia_ck check (resultado = 'efectiva' or anomalia is not null),
  constraint drastico_solo_corte_ck check (not drastico or tipo_actividad_id = 2),
  constraint origen_ck check ((origen = 'archivo' and carga_id is not null) or (origen = 'campo' and reporte_campo_id is not null))
);
create index actas_contrato_idx on scrr.actas (contrato, fecha_ejecucion desc);
create table scrr.acta_eventos (
  id bigint generated always as identity primary key,
  acta_id uuid not null references scrr.actas (id),
  tipo_evento text not null check (tipo_evento in ('ocultar','reincluir')),
  motivo text not null check (length(btrim(motivo)) between 10 and 300),
  autor text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp()
);
create index acta_eventos_idx on scrr.acta_eventos (acta_id, id desc);
create view scrr.v_actas_vigentes as
  select a.* from scrr.actas a
   where not exists (select 1 from scrr.actas b where b.contrato = a.contrato and b.tipo_actividad_id = a.tipo_actividad_id and b.fecha_ejecucion = a.fecha_ejecucion and b.version > a.version)
     and coalesce((select e.tipo_evento from scrr.acta_eventos e where e.acta_id = a.id order by e.id desc limit 1), 'reincluir') <> 'ocultar';
-- Estado del servicio derivado: la última acta efectiva que cambia el estado. Corte con marca de drástico → «cortado_drastico» (el retorno lo distingue).
create view scrr.v_estado_servicio as
  select distinct on (a.contrato) a.contrato,
         case when t.estado_resultante = 'cortado' and a.drastico then 'cortado_drastico' else t.estado_resultante end as estado,
         a.fecha_ejecucion as desde, a.tipo_actividad_id, a.id as acta_id
    from scrr.v_actas_vigentes a join scrr.tipos_actividad t on t.id = a.tipo_actividad_id
   where a.resultado = 'efectiva' and t.estado_resultante is not null
   order by a.contrato, a.fecha_ejecucion desc, a.creado_en desc;

-- 6. Respaldo de public.cartera_suscripcion por carga (P4 del 22-nov): antes de reemplazar las filas de un contrato se guardan las que había
--    (lista vacía = el contrato no existía). Sirve para revertir la carga. Copia técnica con datos personales: se vacía con el paso (7 días).
create table scrr.suscripcion_respaldo (
  carga_id      uuid        not null references scrr.cargas (id),
  contrato      text        not null,
  filas         jsonb       not null check (jsonb_typeof(filas) = 'array'),
  origen        text        not null check (origen in ('archivo','salida')),   -- 'salida' = estaba en la tabla y no vino en el archivo
  revertido_en  timestamptz,
  primary key (carga_id, contrato)
);

-- 7. RLS y solo inserción
do $$
declare t text;
begin
  foreach t in array array['cargas','carga_eventos','paso_cartera','paso_pagos','paso_actividades','barrios','cartera_historial','pagos_contrato','actas','acta_eventos','suscripcion_respaldo'] loop
    execute format('alter table scrr.%I enable row level security', t);
  end loop;
  foreach t in array array['cargas','carga_eventos','actas','acta_eventos'] loop
    execute format('create trigger %I before update or delete on scrr.%I for each row execute function scrr.f_solo_insercion()', t || '_solo_insercion', t);
  end loop;
end $$;
-- Historial y pagos: solo inserción también en cada partición (el disparador del padre se hereda en las particiones)
create trigger cartera_historial_solo_insercion before update or delete on scrr.cartera_historial for each row execute function scrr.f_solo_insercion();
create trigger pagos_contrato_solo_insercion before update or delete on scrr.pagos_contrato for each row execute function scrr.f_solo_insercion();

-- 8. Particiones. Se crean de antemano (migración: historial 45 días hacia adelante; pagos 13 meses atrás y 2 adelante). Si al aplicar una carga falta la
--    del día (pasaron más de 45 días sin retiro), la crea con un tope de bloqueo de 5 s. No borra nada.
create function scrr.f_preparar_historial(p_desde date, p_hasta date) returns integer
language plpgsql security definer set search_path = pg_catalog, scrr as $$
declare d date; v_nom text; n integer := 0;
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 120 then raise exception 'Rango de particiones del historial no válido'; end if;
  for d in select generate_series(p_desde, p_hasta, interval '1 day')::date loop
    v_nom := 'cartera_historial_' || to_char(d, 'YYYYMMDD');
    if to_regclass('scrr.' || v_nom) is null then
      execute format('create table scrr.%I partition of scrr.cartera_historial for values from (%L) to (%L)', v_nom, d, d + 1);
      execute format('alter table scrr.%I enable row level security', v_nom);
      execute format('revoke all on scrr.%I from public, anon, authenticated, service_role', v_nom);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
create function scrr.f_preparar_pagos(p_desde date, p_hasta date) returns integer
language plpgsql security definer set search_path = pg_catalog, scrr as $$
declare m date; v_nom text; n integer := 0;
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 800 then raise exception 'Rango de particiones de pagos no válido'; end if;
  for m in select generate_series(date_trunc('month', p_desde)::date, date_trunc('month', p_hasta)::date, interval '1 month')::date loop
    v_nom := 'pagos_contrato_' || to_char(m, 'YYYYMM');
    if to_regclass('scrr.' || v_nom) is null then
      execute format('create table scrr.%I partition of scrr.pagos_contrato for values from (%L) to (%L)', v_nom, m, (m + interval '1 month')::date);
      execute format('alter table scrr.%I enable row level security', v_nom);
      execute format('revoke all on scrr.%I from public, anon, authenticated, service_role', v_nom);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- 9. Vaciado de la copia técnica (tablas de paso y respaldo de cartera_suscripcion) a los N días de la última actividad de la carga.
--    POR QUÉ se borra: son copia técnica del archivo (con datos personales en cartera), no un dato de registro; queda un evento «paso_vaciado» por carga con
--    los conteos y la huella SHA-256 del archivo (decisión de David en la fase 0). ALCANCE: solo scrr.paso_cartera, scrr.paso_pagos, scrr.paso_actividades y
--    scrr.suscripcion_respaldo, y solo las filas de las cargas vencidas (where carga_id = …). Después de vaciar el respaldo, esa carga ya no se puede revertir.
create function scrr.f_vaciar_paso(p_dias integer) returns jsonb
language plpgsql security definer set search_path = pg_catalog, scrr as $$
declare r record; n1 bigint; n2 bigint; n3 bigint; n4 bigint; v_cargas integer := 0; v_filas bigint := 0;
begin
  if p_dias is null or p_dias < 1 then raise exception 'Días no válidos'; end if;
  for r in
    select c.id, c.archivo_sha256,
           (select max(e.creado_en) from scrr.carga_eventos e where e.carga_id = c.id and e.evento <> 'paso_vaciado') as ultimo
      from scrr.cargas c
     where not exists (select 1 from scrr.carga_eventos e where e.carga_id = c.id and e.evento = 'paso_vaciado')
  loop
    continue when r.ultimo > clock_timestamp() - make_interval(days => p_dias);
    delete from scrr.paso_cartera where carga_id = r.id;          get diagnostics n1 = row_count;
    delete from scrr.paso_pagos where carga_id = r.id;            get diagnostics n2 = row_count;
    delete from scrr.paso_actividades where carga_id = r.id;      get diagnostics n3 = row_count;
    delete from scrr.suscripcion_respaldo where carga_id = r.id;  get diagnostics n4 = row_count;
    insert into scrr.carga_eventos (carga_id, evento, resumen, autor)
      values (r.id, 'paso_vaciado', jsonb_build_object('filas_paso', n1 + n2 + n3, 'filas_respaldo', n4, 'huella_archivo', r.archivo_sha256,
                                                       'decision', scrr.f_estado_carga(r.id), 'dias', p_dias), 'sistema@emdupar.gov.co');
    v_cargas := v_cargas + 1; v_filas := v_filas + n1 + n2 + n3 + n4;
  end loop;
  return jsonb_build_object('cargas', v_cargas, 'filas', v_filas);
end $$;

-- 10. Retiro del historial diario y de los pagos viejos (P7 del 22-nov). NO CORRE SOLA: ninguna RPC la llama y solo la ejecuta el dueño (David, desde el editor).
--     POR QUÉ: el historial diario de cartera se guarda 10 días (la ventana de facturación); el cierre de cada mes sigue en hechos.cartera_contrato. Los pagos
--     se guardan 13 meses (decisión 3 del 20-nov). Sin retiro, un año de fotos diarias son ~2,7 GB (tope del SCRR: 500 MB el primer año).
--     ALCANCE EXACTO de cada DROP: una partición diaria scrr.cartera_historial_AAAAMMDD cuyo día es anterior a (hoy − ventana_dias_historial), o una partición
--     mensual scrr.pagos_contrato_AAAAMM cuyo mes termina antes de (hoy − retencion_meses_pagos). Primero se separa (detach) y luego se borra; cada una
--     queda en public.geoportal_auditoria con su nombre, sus filas y el motivo. Nada más se borra. Al final prepara las particiones de los próximos 45 días.
create function scrr.f_retirar_historial(p_autor text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, scrr as $$
declare r record; v_hoy date := (now() at time zone 'America/Bogota')::date; v_lim_h date; v_lim_p date; v_n bigint; v_res jsonb := '[]'::jsonb;
        v_autor text := lower(btrim(coalesce(p_autor, '')));
begin
  if position('@' in v_autor) < 2 then raise exception 'Indique el correo de quien retira'; end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 300 then raise exception 'Escriba un motivo de 10 a 300 caracteres'; end if;
  v_lim_h := v_hoy - (scrr.f_param('ventana_dias_historial'))::int;
  v_lim_p := (date_trunc('month', v_hoy) - make_interval(months => (scrr.f_param('retencion_meses_pagos'))::int))::date;
  for r in
    select c.relname, (regexp_match(pg_get_expr(c.relpartbound, c.oid), 'TO \(''([0-9-]+)''\)'))[1]::date as hasta, case when i.inhparent = 'scrr.cartera_historial'::regclass then 'scrr.cartera_historial' else 'scrr.pagos_contrato' end as padre
      from pg_inherits i join pg_class c on c.oid = i.inhrelid
     where i.inhparent in ('scrr.cartera_historial'::regclass, 'scrr.pagos_contrato'::regclass)
     order by c.relname
  loop
    continue when not ((r.padre = 'scrr.cartera_historial' and r.hasta <= v_lim_h) or (r.padre = 'scrr.pagos_contrato' and r.hasta <= v_lim_p));
    execute format('select count(*) from scrr.%I', r.relname) into v_n;
    execute format('alter table %s detach partition scrr.%I', r.padre, r.relname);
    execute format('drop table scrr.%I', r.relname);
    perform scrr.f_auditar(v_autor, 'scrr_retiro_particion', r.relname, jsonb_build_object('filas', v_n, 'hasta', r.hasta, 'motivo', btrim(p_motivo)), null);
    v_res := v_res || jsonb_build_object('particion', r.relname, 'filas', v_n);
  end loop;
  perform scrr.f_preparar_historial(v_hoy, v_hoy + 45);
  perform scrr.f_preparar_pagos(v_hoy, (v_hoy + interval '2 months')::date);
  return jsonb_build_object('retiradas', v_res, 'limite_historial', v_lim_h, 'limite_pagos', v_lim_p);
end $$;

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

-- =====================================================================
-- SCRR · CORTE 2 · 30 — RPC de la carga del día (cartera, pagos, actividades) y de la reversión de cartera_suscripcion
-- Convención del proyecto: SECURITY DEFINER, p_solicitante PRIMERO y p_ip AL FINAL, respuesta jsonb, mensajes para la persona con HINT = 'msg_usuario',
-- ejecutables solo por service_role. El solicitante lo pone la Edge con el correo del token. Auditoría en public.geoportal_auditoria.
-- SQLSTATE (la Edge los traduce): 42501 sin permiso (403), 22023 dato no válido (400), P0002 no existe (404), 55000 estado no permite (409),
-- 57P03 cargas en pausa (503).
-- Aplicar va POR LOTES (una llamada por lote de 2.000 filas y una de cierre): ninguna petición reescribe ni recalcula tablas enteras.
-- =====================================================================

create function scrr.f_err(p_mensaje text, p_codigo text default '22023') returns void
language plpgsql set search_path = pg_catalog as $$
begin
  raise exception '%', p_mensaje using errcode = p_codigo, hint = 'msg_usuario';
end $$;

-- Actividad del archivo (sin tildes, mayúsculas): 1 suspensión, 2 corte, 3 gestión de cobro, 4 reinstalación, 5 reconexión, 6 reconexión drástica
create function scrr.f_actividad(p text) returns smallint
language sql immutable parallel safe set search_path = pg_catalog as $$
  with t as (select regexp_replace(upper(translate(btrim(coalesce(p, '')), 'ÁÉÍÓÚáéíóúÑñ', 'AEIOUAEIOUNN')), '\s+', ' ', 'g') as x)
  select case when x like '%RECONEX%' or x like '%RECONECC%' then (case when x like '%DRASTIC%' then 6 else 5 end)
              when x like '%REINSTAL%' then 4
              when x like '%CORTE%' then 2
              when x like '%SUSPEN%' then 1
              when x like '%COBRO%' or x like '%GESTION%' then 3 end::smallint from t
$$;
-- Marca SÍ/NO del archivo: true, false o nulo si no se entiende
create function scrr.f_si_no(p text) returns boolean
language sql immutable parallel safe set search_path = pg_catalog as $$
  with t as (select upper(translate(btrim(coalesce(p, '')), 'Íí', 'II')) as x)
  select case when x in ('', 'NO', 'N', '0', 'FALSE', 'FALSO') then false when x in ('SI', 'S', '1', 'X', 'TRUE', 'VERDADERO') then true end from t
$$;

-- ---------------------------------------------------------------------
-- Contexto del modo «Cartera» (lo pide la pantalla al abrir)
-- ---------------------------------------------------------------------
create function public.geoportal_scrr_contexto(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante);
begin
  return jsonb_build_object('correo', v_email, 'es_admin', public.geoportal_es_admin(v_email),
    'parametros', jsonb_build_object('lote_filas', scrr.f_param('lote_filas'), 'tope_filas_archivo', scrr.f_param('tope_filas_archivo'),
                                     'comodin_contrato', scrr.f_param('comodin_contrato'), 'carga_pausada', scrr.f_param('carga_pausada'),
                                     'ventana_dias_historial', scrr.f_param('ventana_dias_historial'), 'retencion_meses_pagos', scrr.f_param('retencion_meses_pagos'),
                                     'tope_rechazo_pct', scrr.f_param('tope_rechazo_pct'), 'tope_salidas_suscripcion_pct', scrr.f_param('tope_salidas_suscripcion_pct')),
    'tipos_actividad', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'codigo', codigo, 'nombre', nombre, 'seleccionable', seleccionable, 'admite_drastico', admite_drastico) order by orden), '[]'::jsonb)
                          from scrr.tipos_actividad where activo),
    'anomalias', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'provisional', provisional) order by orden), '[]'::jsonb) from scrr.anomalias where activo),
    'causas_control', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'grupo', grupo) order by id), '[]'::jsonb) from scrr.causas_control where activo));
end $$;

-- ---------------------------------------------------------------------
-- Cargas
-- ---------------------------------------------------------------------
-- Iniciar (idempotente: el mismo archivo de la misma persona con la carga aún abierta devuelve la misma carga)
create function public.geoportal_scrr_carga_iniciar(p_solicitante text, p_tipo text, p_fecha_dato date, p_nombre text, p_sha256 text, p_filas integer,
                                                    p_reemplaza uuid default null, p_motivo text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_id uuid; v_lote integer; v_tope integer; v_hoy date := (now() at time zone 'America/Bogota')::date;
        v_vig record; v_ver smallint := 1; v_ab uuid;
begin
  if p_tipo is null or p_tipo not in ('cartera','pagos','actividades') then perform scrr.f_err('Tipo de carga no válido'); end if;
  if p_fecha_dato is null or p_fecha_dato > v_hoy or p_fecha_dato < date '2020-01-01' then perform scrr.f_err('La fecha del dato no es válida (no puede ser futura)'); end if;
  if coalesce(p_sha256, '') !~ '^[0-9a-f]{64}$' then perform scrr.f_err('Huella del archivo no válida'); end if;
  if length(btrim(coalesce(p_nombre, ''))) not between 1 and 200 then perform scrr.f_err('Nombre de archivo no válido'); end if;
  v_lote := (scrr.f_param('lote_filas'))::integer; v_tope := (scrr.f_param('tope_filas_archivo'))::integer;
  if p_filas is null or p_filas < 1 or p_filas > v_tope then perform scrr.f_err(format('El archivo debe tener entre 1 y %s filas', v_tope)); end if;
  if scrr.f_param('carga_pausada') = 'true'::jsonb then perform scrr.f_err('Las cargas están en pausa. Intente más tarde.', '57P03'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_iniciar:' || p_tipo || ':' || p_fecha_dato::text, 0));
  select c.id into v_id from scrr.cargas c where c.tipo = p_tipo and c.fecha_dato = p_fecha_dato and c.archivo_sha256 = p_sha256 and c.autor = v_email
     and scrr.f_estado_carga(c.id) in ('en_paso','validada') order by c.creado_en desc limit 1;
  if v_id is not null then return jsonb_build_object('carga_id', v_id, 'lote_filas', v_lote, 'lotes', ceil(p_filas::numeric / v_lote)::int, 'repetido', true); end if;
  select * into v_vig from scrr.v_cargas_vigentes where tipo = p_tipo and fecha_dato = p_fecha_dato;
  if found then
    if p_reemplaza is distinct from v_vig.id then
      perform scrr.f_err('Ya hay una carga aplicada de este tipo con esa fecha del dato. Para reemplazarla indique cuál y el motivo.', '55000'); end if;
    if p_tipo <> 'cartera' then perform scrr.f_err('Las cargas de pagos y de actividades acumulan y no se reemplazan: cargue solo lo que falta', '55000'); end if;
    if length(btrim(coalesce(p_motivo, ''))) not between 10 and 300 then perform scrr.f_err('Reemplazar una carga exige un motivo de 10 a 300 caracteres'); end if;
  elsif p_reemplaza is not null then
    perform scrr.f_err('La carga que se quiere reemplazar no está vigente', '55000');
  end if;
  select c.id into v_ab from scrr.cargas c where c.tipo = p_tipo and scrr.f_estado_carga(c.id) in ('en_paso','validada','aplicando') limit 1;
  if v_ab is not null then perform scrr.f_err('Hay otra carga abierta de este tipo. Termínela o anúlela antes.', '55000'); end if;
  v_ver := coalesce((select max(c.version) from scrr.cargas c where c.tipo = p_tipo and c.fecha_dato = p_fecha_dato), 0) + 1;
  v_id := gen_random_uuid();
  insert into scrr.cargas (id, tipo, fecha_dato, version, reemplaza_id, archivo_nombre, archivo_sha256, filas_leidas, autor)
    values (v_id, p_tipo, p_fecha_dato, v_ver, case when p_reemplaza is not null then v_vig.id end, btrim(p_nombre), p_sha256, p_filas, v_email);
  insert into scrr.carga_eventos (carga_id, evento, resumen, motivo, autor)
    values (v_id, 'iniciada', jsonb_build_object('lote_filas', v_lote, 'filas', p_filas), case when p_reemplaza is not null then btrim(p_motivo) end, v_email);
  perform scrr.f_auditar(v_email, 'scrr_carga_iniciar', v_id::text, jsonb_build_object('tipo', p_tipo, 'fecha_dato', p_fecha_dato, 'filas', p_filas, 'version', v_ver), p_ip);
  return jsonb_build_object('carga_id', v_id, 'lote_filas', v_lote, 'lotes', ceil(p_filas::numeric / v_lote)::int, 'version', v_ver, 'repetido', false);
end $$;

-- Subir un lote (idempotente: reenviar el mismo lote no duplica; reenviarlo con otro contenido es un error). Valida cada fila y deja su error en el paso.
create function public.geoportal_scrr_carga_lote(p_solicitante text, p_carga uuid, p_lote integer, p_filas jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas; v_lote integer; v_n integer; v_esperadas integer; v_huella text; v_prev text;
        v_hoy date := (now() at time zone 'America/Bogota')::date; v_ret date;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found then perform scrr.f_err('La carga no existe', 'P0002'); end if;
  if scrr.f_estado_carga(p_carga) not in ('en_paso','validada') then perform scrr.f_err('La carga ya no admite lotes', '55000'); end if;
  if scrr.f_param('carga_pausada') = 'true'::jsonb then perform scrr.f_err('Las cargas están en pausa. Intente más tarde.', '57P03'); end if;
  v_lote := (scrr.f_param('lote_filas'))::integer;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then perform scrr.f_err('El lote no es una lista de filas'); end if;
  v_n := jsonb_array_length(p_filas);
  if p_lote is null or p_lote < 1 or p_lote > ceil(c.filas_leidas::numeric / v_lote) then perform scrr.f_err('Número de lote fuera de rango'); end if;
  v_esperadas := least(v_lote, c.filas_leidas - (p_lote - 1) * v_lote);
  if v_n <> v_esperadas then perform scrr.f_err(format('El lote %s debe traer %s filas y trae %s', p_lote, v_esperadas, v_n)); end if;
  v_huella := md5(p_filas::text);
  perform pg_advisory_xact_lock(hashtextextended('scrr_lote:' || p_carga::text || ':' || p_lote, 0));
  select huella into v_prev from scrr.carga_eventos where carga_id = p_carga and evento = 'lote_recibido' and lote = p_lote;
  if found then
    if v_prev = v_huella then return jsonb_build_object('lote', p_lote, 'repetido', true); end if;
    perform scrr.f_err(format('El lote %s ya se recibió con otro contenido', p_lote), '55000');
  end if;

  if c.tipo = 'cartera' then
    insert into scrr.paso_cartera (carga_id, lote, fila, contrato, estado, identificacion, nombre, correo, telefono, direccion, barrio, categoria, subcategoria, ciclo,
                                   facturas_pendientes, deuda_total, saldo_pendiente, saldo_a_favor, valor_reclamo, saldo_financiado,
                                   serial_medidor, codigo_reparto, ruta, error)
    select p_carga, p_lote, e.o::int,
           case when btrim(e.v->>'contrato') ~ '^[0-9]{1,12}$' then btrim(e.v->>'contrato') end,
           scrr.f_txt(e.v->>'estado', 60), scrr.f_txt(e.v->>'identificacion', 40), scrr.f_txt(e.v->>'nombre', 200), scrr.f_txt(e.v->>'correo', 200),
           scrr.f_txt(e.v->>'telefono', 60), scrr.f_txt(e.v->>'direccion', 200), scrr.f_txt(e.v->>'barrio', 80), scrr.f_txt(e.v->>'categoria', 80),
           scrr.f_txt(e.v->>'subcategoria', 80), scrr.f_txt(e.v->>'ciclo', 10),
           case when scrr.f_num0(e.v->>'facturas_pendientes') between 0 and 999 and scrr.f_num0(e.v->>'facturas_pendientes') = trunc(scrr.f_num0(e.v->>'facturas_pendientes')) then scrr.f_num0(e.v->>'facturas_pendientes')::smallint end,
           scrr.f_num0(e.v->>'deuda_total'), scrr.f_num0(e.v->>'saldo_pendiente'), scrr.f_num0(e.v->>'saldo_a_favor'), scrr.f_num0(e.v->>'valor_reclamo'), scrr.f_num0(e.v->>'saldo_financiado'),
           scrr.f_txt(e.v->>'serial_medidor', 60), scrr.f_txt(e.v->>'codigo_reparto', 40), scrr.f_txt(e.v->>'ruta', 80),
           case when btrim(coalesce(e.v->>'contrato','')) !~ '^[0-9]{1,12}$' then 'Contrato ausente o no numérico'
                when scrr.f_num0(e.v->>'facturas_pendientes') is null or scrr.f_num0(e.v->>'facturas_pendientes') not between 0 and 999
                     or scrr.f_num0(e.v->>'facturas_pendientes') <> trunc(scrr.f_num0(e.v->>'facturas_pendientes')) then 'Facturas pendientes no válidas'
                when scrr.f_num0(e.v->>'deuda_total') is null or scrr.f_num0(e.v->>'saldo_pendiente') is null or scrr.f_num0(e.v->>'saldo_a_favor') is null
                     or scrr.f_num0(e.v->>'valor_reclamo') is null or scrr.f_num0(e.v->>'saldo_financiado') is null then 'Cifra con formato no válido (vacío vale cero)'
                when nullif(btrim(coalesce(e.v->>'ciclo', '')), '') is not null and scrr.f_num(e.v->>'ciclo') is null then 'Ciclo no válido' end
      from jsonb_array_elements(p_filas) with ordinality as e(v, o);
  elsif c.tipo = 'pagos' then
    v_ret := (date_trunc('month', v_hoy) - make_interval(months => (scrr.f_param('retencion_meses_pagos'))::int))::date;
    insert into scrr.paso_pagos (carga_id, lote, fila, contrato, fecha_pago, monto, error)
    select p_carga, p_lote, e.o::int,
           case when btrim(e.v->>'contrato') ~ '^[0-9]{1,12}$' then btrim(e.v->>'contrato')::bigint end,
           scrr.f_fecha(e.v->>'fecha_pago'), scrr.f_num(e.v->>'monto'),
           case when btrim(coalesce(e.v->>'contrato','')) !~ '^[0-9]{1,12}$' then 'Contrato ausente o no numérico'
                when scrr.f_fecha(e.v->>'fecha_pago') is null then 'Fecha de pago ausente o no válida'
                when scrr.f_fecha(e.v->>'fecha_pago') > v_hoy then 'Fecha de pago futura'
                when scrr.f_fecha(e.v->>'fecha_pago') < v_ret then 'Fecha de pago fuera de la retención'
                when scrr.f_num(e.v->>'monto') is null or scrr.f_num(e.v->>'monto') = 0 then 'Monto ausente, en cero o no válido' end
      from jsonb_array_elements(p_filas) with ordinality as e(v, o);
  else
    insert into scrr.paso_actividades (carga_id, lote, fila, contrato, acta, actividad_texto, tipo_actividad_id, drastico, estado_original, anomalia, observacion,
                                       fecha_ejecucion, hora_inicio, hora_fin, lectura, medidor, marca, operario, error)
    select p_carga, p_lote, e.o::int,
           case when btrim(e.v->>'contrato') ~ '^[0-9]{1,12}$' then btrim(e.v->>'contrato')::bigint end,
           scrr.f_txt(e.v->>'acta', 40), scrr.f_txt(e.v->>'actividad', 60), scrr.f_actividad(e.v->>'actividad'),
           coalesce(scrr.f_si_no(e.v->>'drastico'), false) or (scrr.f_actividad(e.v->>'actividad') = 2 and upper(coalesce(e.v->>'actividad', '')) like '%DRASTIC%'),
           case when scrr.f_num(e.v->>'estado') in (3, 4) then scrr.f_num(e.v->>'estado')::smallint end,
           case when scrr.f_num(e.v->>'anomalia') between 1 and 99 and scrr.f_num(e.v->>'anomalia') = trunc(scrr.f_num(e.v->>'anomalia')) then scrr.f_num(e.v->>'anomalia')::smallint end,
           scrr.f_txt(e.v->>'observacion', 300), scrr.f_fecha(e.v->>'fecha'), scrr.f_hora(e.v->>'hora_inicial'), scrr.f_hora(e.v->>'hora_final'),
           case when scrr.f_num(e.v->>'lectura') between 0 and 99999999 and scrr.f_num(e.v->>'lectura') = trunc(scrr.f_num(e.v->>'lectura')) then scrr.f_num(e.v->>'lectura')::int end,
           scrr.f_txt(e.v->>'medidor', 40), scrr.f_txt(e.v->>'marca', 40), scrr.f_txt(e.v->>'operario', 80),
           case when btrim(coalesce(e.v->>'contrato','')) !~ '^[0-9]{1,12}$' then 'Contrato ausente o no numérico'
                when scrr.f_actividad(e.v->>'actividad') is null then 'Actividad no reconocida'
                when scrr.f_si_no(e.v->>'drastico') is null then 'Drástico debe ser SÍ o NO'
                when scrr.f_si_no(e.v->>'drastico') and scrr.f_actividad(e.v->>'actividad') <> 2 then 'La marca de drástico solo aplica a Corte'
                when scrr.f_num(e.v->>'estado') is null or scrr.f_num(e.v->>'estado') not in (3, 4) then 'Estado distinto de 3 (efectiva) o 4 (inefectiva)'
                when nullif(btrim(coalesce(e.v->>'anomalia', '')), '') is not null
                     and not exists (select 1 from scrr.anomalias a where a.activo and a.codigo::numeric = scrr.f_num(e.v->>'anomalia')) then 'Anomalía fuera del catálogo (1 a 17)'
                when scrr.f_num(e.v->>'estado') = 4 and nullif(btrim(coalesce(e.v->>'anomalia', '')), '') is null then 'Inefectiva sin anomalía'
                when scrr.f_fecha(e.v->>'fecha') is null then 'Fecha ausente o no válida'
                when scrr.f_fecha(e.v->>'fecha') > v_hoy then 'Fecha futura'
                when nullif(btrim(coalesce(e.v->>'hora_inicial', '')), '') is not null and scrr.f_hora(e.v->>'hora_inicial') is null then 'Hora inicial no válida'
                when nullif(btrim(coalesce(e.v->>'hora_final', '')), '') is not null and scrr.f_hora(e.v->>'hora_final') is null then 'Hora final no válida'
                when nullif(btrim(coalesce(e.v->>'lectura', '')), '') is not null
                     and not (scrr.f_num(e.v->>'lectura') between 0 and 99999999 and scrr.f_num(e.v->>'lectura') = trunc(scrr.f_num(e.v->>'lectura'))) then 'Lectura no válida' end
      from jsonb_array_elements(p_filas) with ordinality as e(v, o);
  end if;
  insert into scrr.carga_eventos (carga_id, evento, lote, huella, resumen, autor) values (p_carga, 'lote_recibido', p_lote, v_huella, jsonb_build_object('filas', v_n), v_email);
  return jsonb_build_object('lote', p_lote, 'repetido', false, 'filas', v_n);
end $$;

-- Validar en el servidor: cobertura de lotes, rechazos y resumen. No escribe en las tablas finales.
create function public.geoportal_scrr_carga_validar(p_solicitante text, p_carga uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas; v_lote integer; v_lotes integer; v_faltan jsonb; v_tot bigint; v_mal bigint; v_res jsonb; v_pct numeric; v_tope numeric;
        v_prev record; v_com text;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found then perform scrr.f_err('La carga no existe', 'P0002'); end if;
  if scrr.f_estado_carga(p_carga) not in ('en_paso','validada') then perform scrr.f_err('La carga ya no se puede validar', '55000'); end if;
  v_lote := (scrr.f_param('lote_filas'))::integer; v_lotes := ceil(c.filas_leidas::numeric / v_lote)::int; v_tope := (scrr.f_param('tope_rechazo_pct'))::numeric;
  v_com := scrr.f_param('comodin_contrato') #>> '{}';
  select coalesce(jsonb_agg(g), '[]'::jsonb) into v_faltan from generate_series(1, v_lotes) g
   where not exists (select 1 from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_recibido' and e.lote = g);

  if c.tipo = 'cartera' then
    select count(*), count(*) filter (where error is not null) into v_tot, v_mal from scrr.paso_cartera where carga_id = p_carga;
    -- un solo recorrido del paso, cruzado con el calendario del período de la fecha del archivo (para las vencidas derivadas y los ciclos sin calendario)
    with cal as (select ciclo, pago_oportuno from scrr.v_calendario_vigente where periodo = to_char(c.fecha_dato, 'YYYYMM')),
         q as (select p.*, k.ciclo is not null as con_cal, scrr.f_vencidas(p.facturas_pendientes, k.pago_oportuno, c.fecha_dato) as venc, scrr.f_num(p.ciclo) as ciclo_n
                 from scrr.paso_cartera p left join cal k on k.ciclo::numeric = scrr.f_num(p.ciclo) where p.carga_id = p_carga)
    select jsonb_build_object('contratos_distintos', count(distinct contrato) filter (where error is null),
             'contratos_repetidos', count(*) filter (where error is null) - count(distinct contrato) filter (where error is null),
             'con_saldo_pendiente', count(distinct contrato) filter (where error is null and saldo_pendiente > 0),
             'con_facturas_vencidas', count(distinct contrato) filter (where error is null and saldo_pendiente > 0 and venc > 0),
             'con_saldo_sin_calendario', count(distinct contrato) filter (where error is null and saldo_pendiente > 0 and not con_cal),
             'ciclos_sin_calendario', coalesce(jsonb_agg(distinct ciclo_n::int) filter (where error is null and saldo_pendiente > 0 and not con_cal and ciclo_n between 1 and 99), '[]'::jsonb),
             'saldo_pendiente_total', coalesce(sum(saldo_pendiente) filter (where error is null and saldo_pendiente > 0), 0),
             'con_valor_reclamo', count(*) filter (where error is null and valor_reclamo > 0),
             'comodin_o_categoria_menos_1', count(*) filter (where error is null and (contrato = v_com or categoria ~ '^-1')),
             'sin_ciclo_o_sin_ruta', count(*) filter (where error is null and saldo_pendiente > 0 and (ciclo_n is null or ciclo_n in (0, 9999) or ruta is null)),
             'sin_barrio', count(*) filter (where error is null and saldo_pendiente > 0 and barrio is null)) into v_res
      from q;
    select v.fecha_dato, v.id into v_prev from scrr.v_cargas_vigentes v where v.tipo = 'cartera' and v.fecha_dato < c.fecha_dato order by v.fecha_dato desc limit 1;
    if found then
      v_res := v_res || jsonb_build_object('foto_anterior', v_prev.fecha_dato,
         'con_saldo_en_la_anterior', (select count(*) from scrr.cartera_historial h where h.fecha_dato = v_prev.fecha_dato and h.carga_id = v_prev.id and h.en_cartera));
    end if;
    v_res := v_res || jsonb_build_object('filas_en_cartera_suscripcion_hoy', (select count(*) from public.cartera_suscripcion));
  elsif c.tipo = 'pagos' then
    select count(*), count(*) filter (where error is not null) into v_tot, v_mal from scrr.paso_pagos where carga_id = p_carga;
    select jsonb_build_object('pagos_validos', count(*) filter (where error is null), 'monto_total', coalesce(sum(monto) filter (where error is null), 0),
             'primer_pago', min(fecha_pago) filter (where error is null), 'ultimo_pago', max(fecha_pago) filter (where error is null),
             'contratos_distintos', count(distinct contrato) filter (where error is null),
             'identicos_en_el_archivo', count(*) filter (where error is null)
                - (select count(*) from (select 1 from scrr.paso_pagos q where q.carga_id = p_carga and q.error is null group by q.contrato, q.fecha_pago, q.monto) z)) into v_res
      from scrr.paso_pagos where carga_id = p_carga;
  else
    select count(*), count(*) filter (where error is not null) into v_tot, v_mal from scrr.paso_actividades where carga_id = p_carga;
    select jsonb_build_object('efectivas', count(*) filter (where error is null and estado_original = 3), 'inefectivas', count(*) filter (where error is null and estado_original = 4),
             'cortes_drasticos', count(*) filter (where error is null and drastico),
             'por_actividad', coalesce((select jsonb_object_agg(t.codigo, z.n) from (select tipo_actividad_id, count(*) n from scrr.paso_actividades
                                         where carga_id = p_carga and error is null group by 1) z join scrr.tipos_actividad t on t.id = z.tipo_actividad_id), '{}'::jsonb),
             'repetidas_en_el_archivo', count(*) filter (where error is null)
                - (select count(*) from (select 1 from scrr.paso_actividades q where q.carga_id = p_carga and q.error is null group by q.contrato, q.tipo_actividad_id, q.fecha_ejecucion) z),
             'primera', min(fecha_ejecucion) filter (where error is null), 'ultima', max(fecha_ejecucion) filter (where error is null)) into v_res
      from scrr.paso_actividades where carga_id = p_carga;
  end if;
  v_pct := case when v_tot = 0 then 100 else round(v_mal * 100.0 / v_tot, 2) end;
  v_res := v_res || jsonb_build_object('filas_en_paso', v_tot, 'filas_esperadas', c.filas_leidas, 'filas_rechazadas', v_mal, 'pct_rechazadas', v_pct, 'lotes_faltantes', v_faltan,
             'causas_rechazo', coalesce((select jsonb_object_agg(error, n) from (select error, count(*) n from (
                 select error from scrr.paso_cartera where carga_id = p_carga and error is not null
                 union all select error from scrr.paso_pagos where carga_id = p_carga and error is not null
                 union all select error from scrr.paso_actividades where carga_id = p_carga and error is not null) u group by error) z), '{}'::jsonb));
  v_res := v_res || jsonb_build_object('puede_aplicar', (jsonb_array_length(v_faltan) = 0 and v_tot = c.filas_leidas and v_pct <= v_tope and v_tot - v_mal > 0),
                                       'tope_rechazo_pct', v_tope, 'lotes', v_lotes);
  insert into scrr.carga_eventos (carga_id, evento, resumen, autor) values (p_carga, 'validada', v_res, v_email);
  perform scrr.f_auditar(v_email, 'scrr_carga_validar', p_carga::text, jsonb_build_object('rechazadas', v_mal, 'filas', v_tot), p_ip);
  return v_res;
end $$;

-- Aplicar UN LOTE (p_lote) o CERRAR la carga (p_lote nulo, cuando todos los lotes están aplicados).
--  · cartera, por lote: historial de los contratos con saldo pendiente y reemplazo de sus filas en public.cartera_suscripcion con respaldo previo.
--    cierre: filas de salida del historial y retiro, con respaldo, de los contratos de cartera_suscripcion que no vinieron en el archivo. Si son más del tope
--    (tope_salidas_suscripcion_pct de la tabla), se exige confirmarlo con motivo: protege contra un archivo incompleto.
--  · pagos y actividades: acumulan sin duplicar (pagos por contrato + fecha + monto + ordinal; actas por contrato + actividad + fecha).
create function public.geoportal_scrr_carga_aplicar(p_solicitante text, p_carga uuid, p_lote integer default null, p_confirmar_salidas boolean default false,
                                                    p_motivo text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas; v_val jsonb; v_est text; v_lotes integer; v_vig record; v_prev record;
        v_com text; n1 bigint := 0; n2 bigint := 0; n3 bigint := 0; n4 bigint := 0; v_min date; v_max date; v_res jsonb; v_tot bigint; v_tope numeric;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found then perform scrr.f_err('La carga no existe', 'P0002'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_aplicar:' || c.tipo, 0));
  v_est := scrr.f_estado_carga(p_carga);
  if v_est not in ('validada','aplicando') then perform scrr.f_err('La carga debe estar validada antes de aplicarse', '55000'); end if;
  select resumen into v_val from scrr.carga_eventos where carga_id = p_carga and evento = 'validada' order by id desc limit 1;
  if coalesce((v_val->>'puede_aplicar')::boolean, false) is not true then perform scrr.f_err('La validación no permite aplicar: revise lotes faltantes y filas rechazadas', '55000'); end if;
  if scrr.f_param('carga_pausada') = 'true'::jsonb then perform scrr.f_err('Las cargas están en pausa. Intente más tarde.', '57P03'); end if;
  select * into v_vig from scrr.v_cargas_vigentes where tipo = c.tipo and fecha_dato = c.fecha_dato;
  if found and v_vig.id is distinct from c.reemplaza_id then perform scrr.f_err('Ya hay una carga aplicada con esa fecha del dato', '55000'); end if;
  v_lotes := (v_val->>'lotes')::int;
  v_com := scrr.f_param('comodin_contrato') #>> '{}';

  -- ======================= UN LOTE =======================
  if p_lote is not null then
    if p_lote < 1 or p_lote > v_lotes then perform scrr.f_err('Número de lote fuera de rango'); end if;
    if exists (select 1 from scrr.carga_eventos where carga_id = p_carga and evento = 'lote_aplicado' and lote = p_lote) then
      return jsonb_build_object('lote', p_lote, 'repetido', true);
    end if;
    if c.tipo = 'cartera' then
      if to_regclass('scrr.cartera_historial_' || to_char(c.fecha_dato, 'YYYYMMDD')) is null then
        set local lock_timeout = '5s';
        perform scrr.f_preparar_historial(c.fecha_dato, c.fecha_dato);
      end if;
      insert into scrr.barrios (nombre_norm)
        select distinct scrr.f_barrio_norm(barrio) from scrr.paso_cartera where carga_id = p_carga and lote = p_lote and error is null and scrr.f_barrio_norm(barrio) is not null
        on conflict (nombre_norm) do nothing;
      -- historial: contratos con saldo pendiente (un contrato repetido en el archivo cuenta una vez: la fila de mayor saldo dentro del lote; entre lotes, la primera)
      insert into scrr.cartera_historial (fecha_dato, version, contrato, en_cartera, marca, estado, categoria, ciclo, ruta, codigo_reparto, barrio_id,
                                          facturas_pendientes, facturas_vencidas, deuda_total, saldo_pendiente, saldo_a_favor, saldo_financiado, valor_reclamo, carga_id)
        select c.fecha_dato, c.version, s.contrato::bigint, true,
               case when s.contrato = v_com or s.categoria ~ '^-1' then 1 else 0 end, s.estado, s.categoria,
               case when scrr.f_num(s.ciclo) between 0 and 9999 then scrr.f_num(s.ciclo)::smallint end, s.ruta, s.codigo_reparto, b.id,
               s.facturas_pendientes, scrr.f_vencidas(s.facturas_pendientes, k.pago_oportuno, c.fecha_dato), s.deuda_total, s.saldo_pendiente, s.saldo_a_favor, s.saldo_financiado, s.valor_reclamo, p_carga
          from (select distinct on (contrato) * from scrr.paso_cartera where carga_id = p_carga and lote = p_lote and error is null and saldo_pendiente > 0
                 order by contrato, saldo_pendiente desc, fila) s
          left join scrr.barrios b on b.nombre_norm = scrr.f_barrio_norm(s.barrio)
          left join scrr.v_calendario_vigente k on k.periodo = to_char(c.fecha_dato, 'YYYYMM') and k.ciclo::numeric = scrr.f_num(s.ciclo)
        on conflict (fecha_dato, version, contrato) do nothing;
      get diagnostics n1 = row_count;
      -- cartera_suscripcion: respaldo de lo que había (solo la primera vez que la carga toca el contrato), retiro de esas filas e inserción de las del archivo
      with tocados as (select distinct p.contrato from scrr.paso_cartera p where p.carga_id = p_carga and p.lote = p_lote and p.error is null),
           nuevos as (select t.contrato from tocados t where not exists (select 1 from scrr.suscripcion_respaldo r where r.carga_id = p_carga and r.contrato = t.contrato)),
           resp as (insert into scrr.suscripcion_respaldo (carga_id, contrato, filas, origen)
                      select p_carga, n.contrato, coalesce((select jsonb_agg(to_jsonb(s)) from public.cartera_suscripcion s where s.contrato = n.contrato), '[]'::jsonb), 'archivo'
                        from nuevos n
                    returning contrato)
      delete from public.cartera_suscripcion s using resp where s.contrato = resp.contrato;
      get diagnostics n2 = row_count;
      insert into public.cartera_suscripcion (contrato, estado, identificacion, nombre, correo, telefono, direccion, barrio, categoria, subcategoria, ciclo,
                                              facturas_pendientes, deuda_total, saldo_pendiente, saldo_a_favor, valor_reclamo, saldo_financiado,
                                              serial_medidor, codigo_reparto, ruta, periodo_carga)
        select p.contrato, p.estado, p.identificacion, p.nombre, p.correo, p.telefono, p.direccion, p.barrio, p.categoria, p.subcategoria, p.ciclo,
               p.facturas_pendientes, p.deuda_total, p.saldo_pendiente, p.saldo_a_favor, p.valor_reclamo, p.saldo_financiado,
               p.serial_medidor, p.codigo_reparto, p.ruta, to_char(c.fecha_dato, 'YYYYMMDD')
          from scrr.paso_cartera p where p.carga_id = p_carga and p.lote = p_lote and p.error is null order by p.fila;
      get diagnostics n3 = row_count;
      v_res := jsonb_build_object('lote', p_lote, 'historial', n1, 'suscripcion_filas_retiradas', n2, 'suscripcion_filas_nuevas', n3);
    elsif c.tipo = 'pagos' then
      select min(fecha_pago), max(fecha_pago) into v_min, v_max from scrr.paso_pagos where carga_id = p_carga and lote = p_lote and error is null;
      if v_min is not null and (to_regclass('scrr.pagos_contrato_' || to_char(v_min, 'YYYYMM')) is null or to_regclass('scrr.pagos_contrato_' || to_char(v_max, 'YYYYMM')) is null) then
        set local lock_timeout = '5s';
        perform scrr.f_preparar_pagos(v_min, v_max);
      end if;
      -- ordinal: cuántos pagos idénticos (contrato, fecha, monto) hay ANTES en el archivo, en todos los lotes, más uno
      insert into scrr.pagos_contrato (contrato, fecha_pago, monto, ordinal, carga_id)
        select q.contrato, q.fecha_pago, q.monto, q.ord::smallint, p_carga
          from (select p.lote, p.contrato, p.fecha_pago, p.monto, row_number() over (partition by p.contrato, p.fecha_pago, p.monto order by p.lote, p.fila) as ord
                  from scrr.paso_pagos p
                 where p.carga_id = p_carga and p.error is null
                   and (p.contrato, p.fecha_pago, p.monto) in (select x.contrato, x.fecha_pago, x.monto from scrr.paso_pagos x where x.carga_id = p_carga and x.lote = p_lote and x.error is null)) q
         where q.lote = p_lote and q.ord < 32000
        on conflict do nothing;
      get diagnostics n1 = row_count;
      select count(*) into v_tot from scrr.paso_pagos where carga_id = p_carga and lote = p_lote and error is null;
      v_res := jsonb_build_object('lote', p_lote, 'pagos_nuevos', n1, 'pagos_ya_existentes', v_tot - n1);
    else
      -- la lista de la que salió cada visita, si la hay (fuera de las listas = nulo: ajuste inicial o actividad no programada; David, 22-nov 20:45)
      with nuevas as (
        insert into scrr.actas (id, contrato, tipo_actividad_id, drastico, fecha_ejecucion, version, resultado, anomalia, acta_numero, observacion, hora_inicio, hora_fin,
                                lectura, medidor, marca_medidor, operario, origen, estado_original, carga_id, creado_por, corrida_id)
          select gen_random_uuid(), s.contrato, s.tipo_actividad_id, s.drastico, s.fecha_ejecucion, 1, case s.estado_original when 3 then 'efectiva' else 'inefectiva' end,
                 s.anomalia, s.acta, s.observacion, s.hora_inicio, s.hora_fin, s.lectura, s.medidor, s.marca, s.operario, 'archivo', s.estado_original, p_carga, c.autor,
                 (select k.corrida_id from scrr.corrida_contratos k join scrr.corridas r on r.id = k.corrida_id
                   where k.contrato = s.contrato and r.actividad_id = s.tipo_actividad_id
                     and (r.creado_en at time zone 'America/Bogota')::date between s.fecha_ejecucion - 60 and s.fecha_ejecucion
                   order by r.creado_en desc limit 1)
            from (select distinct on (contrato, tipo_actividad_id, fecha_ejecucion) * from scrr.paso_actividades
                   where carga_id = p_carga and lote = p_lote and error is null order by contrato, tipo_actividad_id, fecha_ejecucion, fila) s
          on conflict do nothing
          returning corrida_id)
      select count(*), count(*) filter (where corrida_id is null) into n1, n2 from nuevas;
      select count(*) into v_tot from scrr.paso_actividades where carga_id = p_carga and lote = p_lote and error is null;
      v_res := jsonb_build_object('lote', p_lote, 'actas_nuevas', n1, 'actas_ya_existentes', v_tot - n1, 'actas_de_una_lista', n1 - n2, 'actas_fuera_de_las_listas', n2);
    end if;
    insert into scrr.carga_eventos (carga_id, evento, lote, resumen, autor) values (p_carga, 'lote_aplicado', p_lote, v_res, v_email);
    return v_res || jsonb_build_object('repetido', false);
  end if;

  -- ======================= CIERRE =======================
  if (select count(*) from scrr.carga_eventos where carga_id = p_carga and evento = 'lote_aplicado') <> v_lotes then
    perform scrr.f_err('Faltan lotes por aplicar antes de cerrar la carga', '55000');
  end if;
  if c.tipo = 'cartera' then
    -- filas de salida del historial: con saldo en la foto vigente anterior y hoy sin saldo (valores reales del archivo si vino; 0 si ya no figura)
    select v.fecha_dato, v.id into v_prev from scrr.v_cargas_vigentes v where v.tipo = 'cartera' and v.fecha_dato < c.fecha_dato order by v.fecha_dato desc limit 1;
    if v_prev.id is not null then
      insert into scrr.cartera_historial (fecha_dato, version, contrato, en_cartera, marca, estado, categoria, ciclo, ruta, codigo_reparto, barrio_id,
                                          facturas_pendientes, facturas_vencidas, deuda_total, saldo_pendiente, saldo_a_favor, saldo_financiado, valor_reclamo, carga_id)
        select c.fecha_dato, c.version, h.contrato, false, h.marca, coalesce(s.estado, h.estado), coalesce(s.categoria, h.categoria), h.ciclo, coalesce(s.ruta, h.ruta),
               coalesce(s.codigo_reparto, h.codigo_reparto), h.barrio_id,
               coalesce(s.facturas_pendientes, 0), 0, coalesce(s.deuda_total, 0), coalesce(s.saldo_pendiente, 0), coalesce(s.saldo_a_favor, 0),
               coalesce(s.saldo_financiado, 0), coalesce(s.valor_reclamo, 0), p_carga
          from scrr.cartera_historial h
          left join lateral (select * from scrr.paso_cartera p where p.carga_id = p_carga and p.contrato = h.contrato::text and p.error is null order by p.saldo_pendiente desc limit 1) s on true
         where h.fecha_dato = v_prev.fecha_dato and h.carga_id = v_prev.id and h.en_cartera
           and not exists (select 1 from scrr.cartera_historial n where n.fecha_dato = c.fecha_dato and n.version = c.version and n.contrato = h.contrato);
      get diagnostics n1 = row_count;
    end if;
    -- contratos de cartera_suscripcion que no vinieron en el archivo (ni con error): se retiran con respaldo. Guardia contra un archivo incompleto.
    select count(distinct s.contrato) into n2 from public.cartera_suscripcion s
     where s.contrato is not null
       and not exists (select 1 from scrr.suscripcion_respaldo r where r.carga_id = p_carga and r.contrato = s.contrato)
       and not exists (select 1 from scrr.paso_cartera p where p.carga_id = p_carga and p.contrato = s.contrato);
    select count(*) into v_tot from public.cartera_suscripcion;
    v_tope := (scrr.f_param('tope_salidas_suscripcion_pct'))::numeric;
    if n2 > 0 and n2 * 100.0 > v_tope * greatest(v_tot, 1) and not coalesce(p_confirmar_salidas, false) then
      perform scrr.f_err(format('%s contratos de la cartera de hoy no vienen en el archivo (más del %s %%). Revise que el archivo esté completo; si es correcto, confírmelo con un motivo.',
                                n2, v_tope), '55000');
    end if;
    if n2 > 0 and coalesce(p_confirmar_salidas, false) and length(btrim(coalesce(p_motivo, ''))) not between 10 and 300 then
      perform scrr.f_err('Confirmar las salidas exige un motivo de 10 a 300 caracteres');
    end if;
    with sal as (select distinct s.contrato from public.cartera_suscripcion s
                  where s.contrato is not null
                    and not exists (select 1 from scrr.suscripcion_respaldo r where r.carga_id = p_carga and r.contrato = s.contrato)
                    and not exists (select 1 from scrr.paso_cartera p where p.carga_id = p_carga and p.contrato = s.contrato)),
         resp as (insert into scrr.suscripcion_respaldo (carga_id, contrato, filas, origen)
                    select p_carga, sal.contrato, (select jsonb_agg(to_jsonb(s)) from public.cartera_suscripcion s where s.contrato = sal.contrato), 'salida' from sal
                  returning contrato)
    delete from public.cartera_suscripcion s using resp where s.contrato = resp.contrato;
    get diagnostics n3 = row_count;
    v_res := jsonb_build_object('filas_de_salida_historial', n1, 'suscripcion_contratos_salientes', n2, 'suscripcion_filas_retiradas', n3,
                                'historial', (select coalesce(sum((e.resumen->>'historial')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'),
                                'suscripcion_filas_nuevas', (select coalesce(sum((e.resumen->>'suscripcion_filas_nuevas')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'),
                                'salidas_confirmadas', n2 > 0 and coalesce(p_confirmar_salidas, false));
  elsif c.tipo = 'pagos' then
    v_res := jsonb_build_object('pagos_nuevos', (select coalesce(sum((e.resumen->>'pagos_nuevos')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'),
                                'pagos_ya_existentes', (select coalesce(sum((e.resumen->>'pagos_ya_existentes')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'));
  else
    v_res := jsonb_build_object('actas_nuevas', (select coalesce(sum((e.resumen->>'actas_nuevas')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'),
                                'actas_ya_existentes', (select coalesce(sum((e.resumen->>'actas_ya_existentes')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'),
                                'actas_de_una_lista', (select coalesce(sum((e.resumen->>'actas_de_una_lista')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'),
                                'actas_fuera_de_las_listas', (select coalesce(sum((e.resumen->>'actas_fuera_de_las_listas')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'));
  end if;
  v_res := v_res || jsonb_build_object('rechazadas', v_val->'filas_rechazadas');
  if c.reemplaza_id is not null then
    insert into scrr.carga_eventos (carga_id, evento, resumen, motivo, autor)
      select c.reemplaza_id, 'reemplazada', jsonb_build_object('reemplazada_por', p_carga), (select motivo from scrr.carga_eventos where carga_id = p_carga and evento = 'iniciada'), v_email;
  end if;
  insert into scrr.carga_eventos (carga_id, evento, resumen, motivo, autor)
    values (p_carga, 'aplicada', v_res, case when n2 > 0 and coalesce(p_confirmar_salidas, false) then btrim(p_motivo) end, v_email);
  perform scrr.f_auditar(v_email, 'scrr_carga_aplicar', p_carga::text, jsonb_build_object('tipo', c.tipo, 'fecha_dato', c.fecha_dato) || v_res, p_ip);
  return jsonb_build_object('ok', true, 'tipo', c.tipo, 'fecha_dato', c.fecha_dato, 'resultado', v_res);
end $$;

-- Revertir cartera_suscripcion a como estaba antes de una carga de cartera (hasta 5.000 contratos por llamada; se repite hasta pendientes = 0).
-- Solo la última carga de cartera que la tocó y mientras su respaldo exista (7 días).
create function public.geoportal_scrr_suscripcion_revertir(p_solicitante text, p_carga uuid, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas; n1 bigint; n2 bigint; v_pend bigint;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found or c.tipo <> 'cartera' then perform scrr.f_err('La carga de cartera no existe', 'P0002'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 300 then perform scrr.f_err('Revertir exige un motivo de 10 a 300 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_aplicar:cartera', 0));
  if not exists (select 1 from scrr.suscripcion_respaldo where carga_id = p_carga) then
    perform scrr.f_err('Esa carga no tiene respaldo de la cartera (no tocó la tabla o ya pasaron los 7 días)', '55000'); end if;
  if exists (select 1 from scrr.cargas c2 where c2.tipo = 'cartera' and c2.creado_en > c.creado_en
               and exists (select 1 from scrr.suscripcion_respaldo r where r.carga_id = c2.id and r.revertido_en is null)) then
    perform scrr.f_err('Hay una carga de cartera posterior que también cambió la tabla: revierta primero esa', '55000'); end if;
  with lote as (select r.contrato, r.filas from scrr.suscripcion_respaldo r where r.carga_id = p_carga and r.revertido_en is null order by r.contrato limit 5000),
       quitar as (delete from public.cartera_suscripcion s using lote where s.contrato = lote.contrato returning 1)
  select count(*) into n1 from quitar;
  insert into public.cartera_suscripcion
    select x.* from scrr.suscripcion_respaldo r
      cross join lateral jsonb_populate_recordset(null::public.cartera_suscripcion, r.filas) x
     where r.carga_id = p_carga and r.revertido_en is null
       and r.contrato in (select r2.contrato from scrr.suscripcion_respaldo r2 where r2.carga_id = p_carga and r2.revertido_en is null order by r2.contrato limit 5000);
  get diagnostics n2 = row_count;
  update scrr.suscripcion_respaldo r set revertido_en = clock_timestamp()
   where r.carga_id = p_carga and r.revertido_en is null
     and r.contrato in (select r2.contrato from scrr.suscripcion_respaldo r2 where r2.carga_id = p_carga and r2.revertido_en is null order by r2.contrato limit 5000);
  select count(*) into v_pend from scrr.suscripcion_respaldo where carga_id = p_carga and revertido_en is null;
  if v_pend = 0 then
    insert into scrr.carga_eventos (carga_id, evento, motivo, resumen, autor) values (p_carga, 'suscripcion_revertida', btrim(p_motivo), '{}'::jsonb, v_email);
  end if;
  perform scrr.f_auditar(v_email, 'scrr_suscripcion_revertir', p_carga::text, jsonb_build_object('filas_quitadas', n1, 'filas_restauradas', n2, 'pendientes', v_pend), p_ip);
  return jsonb_build_object('filas_quitadas', n1, 'filas_restauradas', n2, 'pendientes', v_pend);
end $$;

-- Anular (con motivo). Cartera aplicada o a medias: solo después de revertir cartera_suscripcion (su historial queda oculto, nunca borrado). Si la carga
-- anulada había reemplazado a otra, esa vuelve a quedar vigente.
-- Pagos y actividades aplicados acumulan y no se anulan: se corrigen con una carga posterior.
create function public.geoportal_scrr_carga_anular(p_solicitante text, p_carga uuid, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas; v_est text;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found then perform scrr.f_err('La carga no existe', 'P0002'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 300 then perform scrr.f_err('Anular exige un motivo de 10 a 300 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_aplicar:' || c.tipo, 0));
  v_est := scrr.f_estado_carga(p_carga);
  if v_est in ('rechazada','reemplazada','anulada') then perform scrr.f_err(format('La carga ya está %s', v_est), '55000'); end if;
  if v_est in ('aplicada','aplicando') and c.tipo <> 'cartera' then
    perform scrr.f_err('Las cargas de pagos y de actividades acumulan y no se anulan: se corrigen con una carga posterior', '55000'); end if;
  if c.tipo = 'cartera' and exists (select 1 from scrr.suscripcion_respaldo where carga_id = p_carga and revertido_en is null) then
    perform scrr.f_err('Esta carga ya cambió la cartera de suscripción: revierta primero la tabla y después anule', '55000'); end if;
  if c.tipo = 'cartera' and v_est in ('aplicada','aplicando') and not exists (select 1 from scrr.suscripcion_respaldo where carga_id = p_carga) then
    perform scrr.f_err('Ya no hay respaldo para revertir la cartera de suscripción de esta carga: corríjala con una carga nueva', '55000'); end if;
  insert into scrr.carga_eventos (carga_id, evento, motivo, resumen, autor) values (p_carga, 'anulada', btrim(p_motivo), jsonb_build_object('estado_previo', v_est), v_email);
  -- si esta carga había reemplazado a otra, la reemplazada vuelve a quedar vigente (evento nuevo; nada se borra)
  if v_est = 'aplicada' and c.reemplaza_id is not null then
    insert into scrr.carga_eventos (carga_id, evento, resumen, autor)
      values (c.reemplaza_id, 'aplicada', jsonb_build_object('vigente_de_nuevo_por_anulacion_de', p_carga), v_email);
  end if;
  perform scrr.f_auditar(v_email, 'scrr_carga_anular', p_carga::text, jsonb_build_object('tipo', c.tipo, 'estado_previo', v_est), p_ip);
  return jsonb_build_object('ok', true, 'estado', 'anulada');
end $$;

create function public.geoportal_scrr_carga_estado(p_solicitante text, p_carga uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found then perform scrr.f_err('La carga no existe', 'P0002'); end if;
  return jsonb_build_object('carga_id', c.id, 'tipo', c.tipo, 'fecha_dato', c.fecha_dato, 'version', c.version, 'archivo', c.archivo_nombre, 'filas', c.filas_leidas,
    'estado', scrr.f_estado_carga(c.id),
    'lotes_recibidos', (select coalesce(jsonb_agg(lote order by lote), '[]'::jsonb) from scrr.carga_eventos where carga_id = c.id and evento = 'lote_recibido'),
    'lotes_aplicados', (select coalesce(jsonb_agg(lote order by lote), '[]'::jsonb) from scrr.carga_eventos where carga_id = c.id and evento = 'lote_aplicado'),
    'resumen', (select resumen from scrr.carga_eventos where carga_id = c.id and evento in ('validada','aplicada') order by id desc limit 1),
    'respaldo_pendiente', (select count(*) from scrr.suscripcion_respaldo where carga_id = c.id and revertido_en is null),
    'creada_en', c.creado_en);
end $$;

-- ¿Falta cargar hoy? (hora de Bogotá). Cartera: la foto de hoy; pagos y actividades: hasta ayer.
create function public.geoportal_scrr_cargas_hoy(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  return jsonb_build_object('hoy', v_hoy, 'tipos', (
    select jsonb_agg(jsonb_build_object('tipo', t.tipo, 'ultima_fecha_dato', u.fecha_dato, 'aplicada_en', u.aplicada_en, 'requerida_desde', t.requerida,
             'al_dia', coalesce(u.fecha_dato >= t.requerida, false),
             'abierta', (select c.id from scrr.cargas c where c.tipo = t.tipo and scrr.f_estado_carga(c.id) in ('en_paso','validada','aplicando') order by c.creado_en desc limit 1)) order by t.ord)
      from (values (1, 'cartera', v_hoy), (2, 'pagos', v_hoy - 1), (3, 'actividades', v_hoy - 1)) as t(ord, tipo, requerida)
      left join lateral (select c.fecha_dato, (select max(e.creado_en) from scrr.carga_eventos e where e.carga_id = c.id and e.evento = 'aplicada') as aplicada_en
                           from scrr.v_cargas_vigentes c where c.tipo = t.tipo order by c.fecha_dato desc limit 1) u on true));
end $$;

create function public.geoportal_scrr_cargas_lista(p_solicitante text, p_limite integer default 30, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante);
begin
  return jsonb_build_object('cargas', (select coalesce(jsonb_agg(x order by (x->>'creada_en') desc), '[]'::jsonb) from (
     select jsonb_build_object('carga_id', c.id, 'tipo', c.tipo, 'fecha_dato', c.fecha_dato, 'version', c.version, 'archivo', c.archivo_nombre, 'filas', c.filas_leidas,
                               'estado', scrr.f_estado_carga(c.id), 'creada_en', c.creado_en, 'autor', c.autor) x
       from scrr.cargas c order by c.creado_en desc limit greatest(1, least(coalesce(p_limite, 30), 100))) q));
end $$;

-- Vaciado de la copia técnica (paso y respaldo) de las cargas con más de paso_dias días (lo corre el supervisor o el administrador; deja un evento por carga)
create function public.geoportal_scrr_vaciar_paso(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); r jsonb;
begin
  r := scrr.f_vaciar_paso((scrr.f_param('paso_dias'))::int);
  perform scrr.f_auditar(v_email, 'scrr_paso_vaciar', null, r, p_ip);
  return r;
end $$;

-- =====================================================================
-- SCRR · CORTE 2 · 35 — RPC de contratos con control, excluidos manuales (P6) y calendario de ciclos
-- Alta y baja siempre con motivo; nada se borra (la baja es un evento). Carga por archivo con un motivo común (P10), sin perder el alta de uno en uno.
-- =====================================================================

create function scrr.f_contrato(p text) returns bigint
language plpgsql immutable set search_path = pg_catalog as $$
begin
  if btrim(coalesce(p, '')) !~ '^[0-9]{1,12}$' then perform scrr.f_err('El contrato debe ser un número de hasta 12 dígitos'); end if;
  return btrim(p)::bigint;
end $$;

-- Alta de uno (control o excluido manual, según la causa)
create function public.geoportal_scrr_control_agregar(p_solicitante text, p_contrato text, p_causa text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_causa scrr.causas_control; v_c bigint := scrr.f_contrato(p_contrato);
begin
  if v_c::text = scrr.f_param('comodin_contrato') #>> '{}' then perform scrr.f_err('Ese número es el comodín del sistema comercial, no un contrato'); end if;
  select * into v_causa from scrr.causas_control where codigo = p_causa and activo;
  if not found then perform scrr.f_err('Causa no válida'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 200 then perform scrr.f_err('Escriba un motivo de 10 a 200 caracteres (sin nombres, cédulas ni teléfonos)'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_control:' || v_c, 0));
  if exists (select 1 from scrr.v_control_vigente where contrato = v_c and causa_id = v_causa.id) then perform scrr.f_err('Ese contrato ya está en la lista por esa causa', '55000'); end if;
  insert into scrr.control_eventos (contrato, causa_id, tipo_evento, motivo, autor) values (v_c, v_causa.id, 'alta', btrim(p_motivo), v_email);
  perform scrr.f_auditar(v_email, 'scrr_control_alta', v_c::text, jsonb_build_object('causa', p_causa, 'grupo', v_causa.grupo), p_ip);
  return jsonb_build_object('ok', true);
end $$;

-- Alta por archivo (P10): hasta 5.000 contratos por llamada, un motivo común. Los que ya están por esa causa se cuentan, no se duplican.
create function public.geoportal_scrr_control_lote(p_solicitante text, p_contratos jsonb, p_causa text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_causa scrr.causas_control; v_n int; v_validos int; v_filas_validas int; v_nuevos int;
        v_com text := scrr.f_param('comodin_contrato') #>> '{}';
begin
  select * into v_causa from scrr.causas_control where codigo = p_causa and activo;
  if not found then perform scrr.f_err('Causa no válida'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 200 then perform scrr.f_err('Escriba un motivo común de 10 a 200 caracteres'); end if;
  if p_contratos is null or jsonb_typeof(p_contratos) <> 'array' then perform scrr.f_err('La lista de contratos no es válida'); end if;
  v_n := jsonb_array_length(p_contratos);
  if v_n < 1 or v_n > 5000 then perform scrr.f_err('Se cargan de 1 a 5.000 contratos por vez'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_control_lote', 0));
  select count(*) into v_filas_validas from jsonb_array_elements(p_contratos) x
   where btrim(x #>> '{}') ~ '^[0-9]{1,12}$' and btrim(x #>> '{}') <> v_com and btrim(x #>> '{}')::bigint > 0;
  with lista as (select distinct btrim(x #>> '{}')::bigint as contrato from jsonb_array_elements(p_contratos) x
                  where btrim(x #>> '{}') ~ '^[0-9]{1,12}$' and btrim(x #>> '{}') <> v_com and btrim(x #>> '{}')::bigint > 0),
       nuevos as (insert into scrr.control_eventos (contrato, causa_id, tipo_evento, motivo, origen, autor)
                    select l.contrato, v_causa.id, 'alta', btrim(p_motivo), 'archivo', v_email from lista l
                     where not exists (select 1 from scrr.v_control_vigente v where v.contrato = l.contrato and v.causa_id = v_causa.id)
                  returning 1)
  select (select count(*) from lista), (select count(*) from nuevos) into v_validos, v_nuevos;
  perform scrr.f_auditar(v_email, 'scrr_control_lote', p_causa, jsonb_build_object('recibidos', v_n, 'validos', v_validos, 'nuevos', v_nuevos), p_ip);
  return jsonb_build_object('recibidos', v_n, 'no_validos', v_n - v_filas_validas, 'repetidos_en_el_archivo', v_filas_validas - v_validos, 'nuevos', v_nuevos, 'ya_estaban', v_validos - v_nuevos);
end $$;

create function public.geoportal_scrr_control_baja(p_solicitante text, p_contrato text, p_causa text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_causa scrr.causas_control; v_c bigint := scrr.f_contrato(p_contrato);
begin
  select * into v_causa from scrr.causas_control where codigo = p_causa;
  if not found then perform scrr.f_err('Causa no válida'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 200 then perform scrr.f_err('Escriba un motivo de 10 a 200 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_control:' || v_c, 0));
  if not exists (select 1 from scrr.v_control_vigente where contrato = v_c and causa_id = v_causa.id) then perform scrr.f_err('Ese contrato no está en la lista por esa causa', '55000'); end if;
  insert into scrr.control_eventos (contrato, causa_id, tipo_evento, motivo, autor) values (v_c, v_causa.id, 'baja', btrim(p_motivo), v_email);
  perform scrr.f_auditar(v_email, 'scrr_control_baja', v_c::text, jsonb_build_object('causa', p_causa), p_ip);
  return jsonb_build_object('ok', true);
end $$;

-- Lista: p_grupo 'control' (control y reclamo manual) o 'excluido'. Sin contrato = vigentes paginados; con contrato = su historial completo (todas las causas).
create function public.geoportal_scrr_control_lista(p_solicitante text, p_grupo text default 'control', p_contrato text default null, p_despues bigint default null,
                                                    p_limite integer default 200, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_lim integer := greatest(1, least(coalesce(p_limite, 200), 500)); v_grupos text[];
begin
  v_grupos := case p_grupo when 'excluido' then array['excluido'] when 'control' then array['control','reclamo'] else null end;
  if v_grupos is null then perform scrr.f_err('Grupo no válido'); end if;
  if p_contrato is not null then
    return jsonb_build_object('historial', (select coalesce(jsonb_agg(jsonb_build_object('causa', k.nombre, 'evento', e.tipo_evento, 'motivo', e.motivo, 'origen', e.origen, 'autor', e.autor, 'fecha', e.creado_en) order by e.id desc), '[]'::jsonb)
                                              from scrr.control_eventos e join scrr.causas_control k on k.id = e.causa_id where e.contrato = scrr.f_contrato(p_contrato)));
  end if;
  return jsonb_build_object(
    'vigentes', (select coalesce(jsonb_agg(jsonb_build_object('contrato', q.contrato, 'causa', q.codigo, 'causa_nombre', q.nombre, 'desde', q.desde, 'autor', q.autor, 'origen', q.origen) order by q.contrato, q.codigo), '[]'::jsonb)
                   from (select v.contrato, k.codigo, k.nombre, v.desde, v.autor, v.origen from scrr.v_control_vigente v join scrr.causas_control k on k.id = v.causa_id
                          where v.grupo = any (v_grupos) and (p_despues is null or v.contrato > p_despues) order by v.contrato limit v_lim) q),
    'total', (select count(*) from scrr.v_control_vigente where grupo = any (v_grupos)),
    'bajas_recientes', (select coalesce(jsonb_agg(jsonb_build_object('contrato', b.contrato, 'causa_nombre', k.nombre, 'fecha', b.creado_en, 'motivo', b.motivo) order by b.id desc), '[]'::jsonb)
                          from (select * from scrr.control_eventos e where e.tipo_evento = 'baja' and e.causa_id in (select id from scrr.causas_control where grupo = any (v_grupos))
                                 order by e.id desc limit 20) b join scrr.causas_control k on k.id = b.causa_id));
end $$;

-- Calendario: los ciclos de un período (con su última versión) y guardar uno (nuevo, o cambio con motivo). Se pueden agregar ciclos (1 a 99).
create function public.geoportal_scrr_calendario_lista(p_solicitante text, p_periodo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  if coalesce(p_periodo, '') !~ '^20[0-9]{2}(0[1-9]|1[0-2])$' then perform scrr.f_err('El período debe ser aaaamm'); end if;
  return jsonb_build_object('periodo', p_periodo, 'hoy', v_hoy,
    'ciclos', (select coalesce(jsonb_agg(jsonb_build_object('ciclo', v.ciclo, 'pago_oportuno', v.pago_oportuno, 'fecha_suspension', v.fecha_suspension, 'etapas', v.etapas,
                        'en_ventana', v.fecha_suspension <= v_hoy, 'versiones', (select count(*) from scrr.calendario_ciclos c where c.periodo = v.periodo and c.ciclo = v.ciclo),
                        'ultimo_cambio', v.vigente_desde, 'motivo', v.motivo) order by v.pago_oportuno, v.ciclo), '[]'::jsonb)
                 from scrr.v_calendario_vigente v where v.periodo = p_periodo),
    'periodos', (select coalesce(jsonb_agg(distinct periodo order by periodo desc), '[]'::jsonb) from scrr.calendario_ciclos));
end $$;

create function public.geoportal_scrr_calendario_guardar(p_solicitante text, p_periodo text, p_ciclo integer, p_pago_oportuno date, p_fecha_suspension date,
                                                         p_etapas jsonb default '{}'::jsonb, p_motivo text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_ant scrr.v_calendario_vigente; v_ini date;
begin
  if coalesce(p_periodo, '') !~ '^20[0-9]{2}(0[1-9]|1[0-2])$' then perform scrr.f_err('El período debe ser aaaamm'); end if;
  if p_ciclo is null or p_ciclo not between 1 and 99 then perform scrr.f_err('El ciclo va de 1 a 99'); end if;
  if p_pago_oportuno is null or p_fecha_suspension is null then perform scrr.f_err('Pago oportuno y fecha de suspensión son obligatorios'); end if;
  if p_fecha_suspension < p_pago_oportuno then perform scrr.f_err('La fecha de suspensión no puede ser anterior al pago oportuno'); end if;
  v_ini := to_date(p_periodo || '01', 'YYYYMMDD');
  if p_pago_oportuno < v_ini - 31 or p_pago_oportuno > (v_ini + interval '2 months')::date then perform scrr.f_err('El pago oportuno no corresponde a ese período'); end if;
  if p_etapas is null or jsonb_typeof(p_etapas) <> 'object' or length(p_etapas::text) > 4000 then perform scrr.f_err('Las etapas no son válidas'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_calendario:' || p_periodo || ':' || p_ciclo, 0));
  select * into v_ant from scrr.v_calendario_vigente where periodo = p_periodo and ciclo = p_ciclo;
  if found then
    if v_ant.pago_oportuno = p_pago_oportuno and v_ant.fecha_suspension = p_fecha_suspension and v_ant.etapas = p_etapas then
      perform scrr.f_err('No hay cambios', '55000'); end if;
    if length(btrim(coalesce(p_motivo, ''))) not between 5 and 300 then perform scrr.f_err('Cambiar un ciclo ya guardado exige un motivo de 5 a 300 caracteres'); end if;
  end if;
  insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, etapas, motivo, autor)
    values (p_periodo, p_ciclo, p_pago_oportuno, p_fecha_suspension, p_etapas, nullif(btrim(coalesce(p_motivo, '')), ''), v_email);
  perform scrr.f_auditar(v_email, 'scrr_calendario', p_periodo || '/' || p_ciclo,
    jsonb_build_object('pago_oportuno', p_pago_oportuno, 'fecha_suspension', p_fecha_suspension, 'nuevo', v_ant.ciclo is null), p_ip);
  return jsonb_build_object('ok', true, 'nuevo', v_ant.ciclo is null);
end $$;

-- =====================================================================
-- SCRR · CORTE 2 · 38 — SELECCIÓN: embudo, vista previa, corrida y lista descargable o imprimible
-- Universo: la foto de cartera VIGENTE más reciente (contratos con saldo pendiente), un ciclo a la vez. El motor no clasifica: el supervisor escoge la actividad
-- (Suspensión, Corte o Gestión de cobro) al generar (decisión 8 del 20-nov; decisión 4 del 22-nov).
-- Embudo (sección 4 del encargo del 20-nov; cada contrato sale en el PRIMER paso que lo excluye):
--   p0 comodín (99999999 o categoría «-1») · p1 no facturado (no figura en el último período de hechos.facturacion_sspd) o sin ruta · p2 control vigente ·
--   p3 reclamo (valor reclamo > 0 o reclamo manual) · p4 pago sin reflejar (lo pagado desde la fecha del archivo cubre el saldo; un abono menor solo MARCA) ·
--   p5 evento de suspensión de agua activo (regla de David: si Técnica quitó el agua allí, no se corta; se SACA de la lista) · p6 excluido manual ·
--   p7 saldo menor al monto mínimo. Después, los filtros del supervisor: rango (facturas VENCIDAS o monto), barrio y segmento (aproximado).
-- Paz y salvo (saldo pendiente en cero) no entra al universo; se cuenta aparte con las filas de salida del historial.
-- =====================================================================

-- Foto vigente más reciente (carga de cartera aplicada)
create function scrr.f_foto_vigente() returns scrr.cargas
language sql stable security definer set search_path = pg_catalog, scrr as $$
  select c.* from scrr.v_cargas_vigentes c where c.tipo = 'cartera' order by c.fecha_dato desc, c.version desc limit 1
$$;

-- Filtros normalizados (lo que no venga toma su valor por omisión; lo que venga mal es un error para la persona)
create function scrr.f_filtros(p jsonb) returns jsonb
language plpgsql stable set search_path = pg_catalog, scrr as $$
declare m text := coalesce(p->>'modo', 'meses'); s text := coalesce(p->>'segmento', 'todos'); d numeric; h numeric; mm numeric; b int;
begin
  if p is null or jsonb_typeof(p) <> 'object' then perform scrr.f_err('Filtros no válidos'); end if;
  if m not in ('meses','monto') then perform scrr.f_err('Modo de selección no válido'); end if;
  if s not in ('todos','pagaron_mes_pasado_no_este','cero_a_un_mes','menos_de_n') then perform scrr.f_err('Segmento no válido'); end if;
  d := coalesce(scrr.f_num(p->>'desde'), case m when 'meses' then 1 else 0 end);
  h := scrr.f_num(p->>'hasta');
  mm := coalesce(scrr.f_num(p->>'monto_minimo'), (scrr.f_param('monto_minimo_defecto') #>> '{}')::numeric);
  if d < 0 or (h is not null and h < d) or mm < 0 then perform scrr.f_err('El rango no es válido'); end if;
  b := case when nullif(p->>'barrio_id', '') is null then null else (p->>'barrio_id')::int end;
  return jsonb_build_object('modo', m, 'desde', d, 'hasta', h, 'monto_minimo', mm, 'barrio_id', b, 'segmento', s, 'n', coalesce(scrr.f_num(p->>'n'), 8));
end $$;

-- Clasificación de cada contrato del ciclo (función interna; no la ejecuta la API). Sin datos personales.
create function scrr.f_seleccion(p_ciclo smallint, p_filtros jsonb)
returns table (contrato bigint, paso text, saldo_pendiente numeric, facturas_vencidas smallint, barrio_id smallint, ruta text, codigo_reparto text, marca text)
language plpgsql stable security definer set search_path = pg_catalog, scrr, public as $$
declare f jsonb := scrr.f_filtros(p_filtros); v_foto scrr.cargas := scrr.f_foto_vigente(); v_fact text; v_susp date; v_mes date; v_mes_ant date; v_eventos boolean;
begin
  if v_foto.id is null then perform scrr.f_err('Todavía no hay una cartera aplicada', '55000'); end if;
  select max(periodo) into v_fact from hechos.facturacion_sspd;
  select k.fecha_suspension into v_susp from scrr.v_calendario_vigente k where k.periodo = to_char(v_foto.fecha_dato, 'YYYYMM') and k.ciclo = p_ciclo;
  v_mes := date_trunc('month', v_foto.fecha_dato)::date; v_mes_ant := (v_mes - interval '1 month')::date;
  v_eventos := exists (select 1 from redes.f_eventos_abiertos());
  return query
  with h as (select * from scrr.cartera_historial x where x.fecha_dato = v_foto.fecha_dato and x.version = v_foto.version and x.carga_id = v_foto.id and x.en_cartera and x.ciclo = p_ciclo),
       fact as (select distinct btrim(s.contrato) as c from hechos.facturacion_sspd s where s.periodo = v_fact),
       ctl as (select v.contrato, bool_or(v.grupo = 'control') as ctl, bool_or(v.grupo = 'reclamo') as rec, bool_or(v.grupo = 'excluido') as exc
                 from scrr.v_control_vigente v where v.contrato in (select h.contrato from h) group by v.contrato),
       pag as (select q.contrato, coalesce(sum(q.monto) filter (where q.fecha_pago >= v_foto.fecha_dato), 0) as desde_archivo,
                      bool_or(v_susp is not null and q.fecha_pago >= v_susp and q.fecha_pago < v_foto.fecha_dato) as desde_susp,
                      bool_or(q.fecha_pago >= v_mes_ant and q.fecha_pago < v_mes) as mes_pasado, bool_or(q.fecha_pago >= v_mes) as este_mes
                 from scrr.pagos_contrato q where q.fecha_pago >= least(v_mes_ant, coalesce(v_susp, v_mes_ant)) and q.contrato in (select h.contrato from h) group by q.contrato),
       b as (select h.*, (fa.c is not null) as facturado, coalesce(k.ctl, false) as ctl, coalesce(k.rec, false) as rec, coalesce(k.exc, false) as exc,
                    coalesce(g.desde_archivo, 0) as pagado, coalesce(g.desde_susp, false) as desde_susp,
                    coalesce(g.mes_pasado and not g.este_mes, false) as mp_no_este
               from h left join fact fa on fa.c = h.contrato::text left join ctl k on k.contrato = h.contrato left join pag g on g.contrato = h.contrato)
  select b.contrato,
         case when b.marca = 1 then 'p0_comodin'
              when not b.facturado or b.ruta is null or btrim(b.ruta) = '' then 'p1_no_facturado_o_sin_ruta'
              when b.ctl then 'p2_control_vigente'
              when b.valor_reclamo > 0 or b.rec then 'p3_reclamo'
              when b.pagado > 0 and b.pagado >= b.saldo_pendiente then 'p4_pago_sin_reflejar'
              when v_eventos and exists (select 1 from redes.f_eventos_del_contrato(b.contrato::text)) then 'p5_evento_suspension_agua'
              when b.exc then 'p6_excluido_manual'
              when b.saldo_pendiente < (f->>'monto_minimo')::numeric then 'p7_saldo_menor_al_minimo'
              when f->>'modo' = 'meses' and (b.facturas_vencidas < (f->>'desde')::numeric or (f->>'hasta' is not null and b.facturas_vencidas > (f->>'hasta')::numeric)) then 'f_fuera_del_rango'
              when f->>'modo' = 'monto' and (b.saldo_pendiente < (f->>'desde')::numeric or (f->>'hasta' is not null and b.saldo_pendiente > (f->>'hasta')::numeric)) then 'f_fuera_del_rango'
              when f->>'barrio_id' is not null and b.barrio_id is distinct from (f->>'barrio_id')::smallint then 'f_otro_barrio'
              when f->>'segmento' = 'pagaron_mes_pasado_no_este' and not b.mp_no_este then 'f_fuera_del_segmento'
              when f->>'segmento' = 'cero_a_un_mes' and b.facturas_vencidas > 1 then 'f_fuera_del_segmento'
              when f->>'segmento' = 'menos_de_n' and b.facturas_vencidas >= (f->>'n')::numeric then 'f_fuera_del_segmento'
              else 'candidato' end,
         b.saldo_pendiente, b.facturas_vencidas, b.barrio_id, b.ruta, b.codigo_reparto,
         case when b.pagado > 0 then 'abono' when b.desde_susp then 'abono_desde_suspension' end
    from b;
end $$;

-- Opciones de la pantalla: la foto vigente, los ciclos del período (con su ventana de suspensión) y, si se pide un ciclo, sus barrios con cuántos contratos con saldo
create function public.geoportal_scrr_seleccion_opciones(p_solicitante text, p_ciclo integer default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_foto scrr.cargas := scrr.f_foto_vigente(); v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  return jsonb_build_object('hoy', v_hoy, 'foto', v_foto.fecha_dato, 'facturacion_periodo', (select max(periodo) from hechos.facturacion_sspd),
    'ciclos', (select coalesce(jsonb_agg(jsonb_build_object('ciclo', k.ciclo, 'pago_oportuno', k.pago_oportuno, 'fecha_suspension', k.fecha_suspension,
                         'en_ventana', k.fecha_suspension <= v_hoy, 'con_saldo', (select count(*) from scrr.cartera_historial h where v_foto.id is not null and h.fecha_dato = v_foto.fecha_dato
                            and h.version = v_foto.version and h.carga_id = v_foto.id and h.en_cartera and h.ciclo = k.ciclo)) order by k.fecha_suspension, k.ciclo), '[]'::jsonb)
                 from scrr.v_calendario_vigente k where k.periodo = to_char(coalesce(v_foto.fecha_dato, v_hoy), 'YYYYMM')),
    'barrios', case when p_ciclo is null or v_foto.id is null then '[]'::jsonb else
                 (select coalesce(jsonb_agg(jsonb_build_object('id', x.barrio_id, 'nombre', coalesce(br.nombre_norm, 'SIN BARRIO'), 'contratos', x.n) order by br.nombre_norm nulls last), '[]'::jsonb)
                    from (select h.barrio_id, count(*) as n from scrr.cartera_historial h where h.fecha_dato = v_foto.fecha_dato and h.version = v_foto.version and h.carga_id = v_foto.id
                            and h.en_cartera and h.ciclo = p_ciclo group by h.barrio_id) x left join scrr.barrios br on br.id = x.barrio_id) end,
    'actividades', (select jsonb_agg(jsonb_build_object('id', id, 'codigo', codigo, 'nombre', nombre) order by orden) from scrr.tipos_actividad where seleccionable and activo));
end $$;

-- Vista previa: SOLO conteos (embudo, candidatos, saldo, marcas, segmentos). Se audita con los conteos (P8). Sin datos personales y sin la lista.
create function public.geoportal_scrr_seleccion_previa(p_solicitante text, p_ciclo integer, p_filtros jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_foto scrr.cargas := scrr.f_foto_vigente(); v_res jsonb; v_paz bigint;
begin
  if p_ciclo is null or p_ciclo not between 1 and 99 then perform scrr.f_err('Escoja un ciclo'); end if;
  select count(*) into v_paz from scrr.cartera_historial h where v_foto.id is not null and h.fecha_dato = v_foto.fecha_dato and h.version = v_foto.version and h.carga_id = v_foto.id
     and not h.en_cartera and h.ciclo = p_ciclo;
  with x as (select * from scrr.f_seleccion(p_ciclo::smallint, p_filtros))
  select jsonb_build_object('foto', v_foto.fecha_dato, 'ciclo', p_ciclo, 'filtros', scrr.f_filtros(p_filtros),
           'embudo', coalesce((select jsonb_object_agg(paso, jsonb_build_object('contratos', n, 'saldo', s)) from (select paso, count(*) as n, round(sum(saldo_pendiente)) as s from x group by paso) z), '{}'::jsonb)
                     || jsonb_build_object('p4_paz_y_salvo_hoy', jsonb_build_object('contratos', v_paz, 'saldo', 0)),
           'universo', (select count(*) from x), 'candidatos', count(*) filter (where paso = 'candidato'),
           'saldo_candidatos', coalesce(round(sum(saldo_pendiente) filter (where paso = 'candidato')), 0),
           'marcados_abono', count(*) filter (where paso = 'candidato' and marca = 'abono'),
           'marcados_abono_desde_suspension', count(*) filter (where paso = 'candidato' and marca = 'abono_desde_suspension'),
           'por_vencidas', coalesce((select jsonb_object_agg(t, n) from (select case when facturas_vencidas between 1 and 6 then '1-6' when facturas_vencidas between 7 and 25 then '7-25'
                                       when facturas_vencidas > 25 then '26+' else '0' end as t, count(*) as n from x where paso = 'candidato' group by 1) w), '{}'::jsonb),
           'segmentos_aproximados', true)
    into v_res
    from x;
  perform scrr.f_auditar(v_email, 'scrr_seleccion_previa', p_ciclo::text, jsonb_build_object('filtros', v_res->'filtros', 'candidatos', v_res->'candidatos', 'embudo', v_res->'embudo'), p_ip);
  return v_res;
end $$;

-- Generar la corrida: se guarda SOLO la lista (contratos en orden de ruta y reparto) con la actividad escogida. Auditada.
create function public.geoportal_scrr_seleccion_generar(p_solicitante text, p_ciclo integer, p_filtros jsonb, p_actividad text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_foto scrr.cargas := scrr.f_foto_vigente(); v_act scrr.tipos_actividad; v_id uuid := gen_random_uuid();
        v_n int; v_s numeric; v_emb jsonb; v_per text; v_lista jsonb; v_todo jsonb;
begin
  if p_ciclo is null or p_ciclo not between 1 and 99 then perform scrr.f_err('Escoja un ciclo'); end if;
  select * into v_act from scrr.tipos_actividad where codigo = p_actividad and seleccionable and activo;
  if not found then perform scrr.f_err('Escoja la actividad: Suspensión, Corte o Gestión de cobro'); end if;
  if v_foto.id is null then perform scrr.f_err('Todavía no hay una cartera aplicada', '55000'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_corrida', 0));
  -- una sola evaluación del embudo; las filas quedan en una variable (sin tablas temporales)
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_todo from scrr.f_seleccion(p_ciclo::smallint, p_filtros) x;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_lista from jsonb_array_elements(v_todo) e where e->>'paso' = 'candidato';
  select coalesce(jsonb_object_agg(z.paso, z.n), '{}'::jsonb) into v_emb from (select e->>'paso' as paso, count(*) as n from jsonb_array_elements(v_todo) e group by 1) z;
  v_n := jsonb_array_length(v_lista);
  v_s := coalesce((select sum((e->>'saldo_pendiente')::numeric) from jsonb_array_elements(v_lista) e), 0);
  if v_n = 0 then perform scrr.f_err('Con esos filtros no hay contratos para la lista', '55000'); end if;
  v_per := to_char(v_foto.fecha_dato, 'YYYYMM');
  insert into scrr.corridas (id, periodo, ciclo, fecha_dato, carga_id, actividad_id, filtros, embudo, contratos, saldo_total, autor)
    values (v_id, v_per, p_ciclo, v_foto.fecha_dato, v_foto.id, v_act.id, scrr.f_filtros(p_filtros), v_emb, v_n, v_s, v_email);
  insert into scrr.corrida_contratos (corrida_id, orden, contrato, saldo_pendiente, facturas_vencidas, barrio_id, ruta, codigo_reparto, marca)
    select v_id, row_number() over (order by t.ruta nulls last, t.codigo_reparto nulls last, t.contrato), t.contrato, t.saldo_pendiente, t.facturas_vencidas, t.barrio_id, t.ruta, t.codigo_reparto, t.marca
      from jsonb_to_recordset(v_lista) as t(contrato bigint, saldo_pendiente numeric, facturas_vencidas smallint, barrio_id smallint, ruta text, codigo_reparto text, marca text);
  perform scrr.f_auditar(v_email, 'scrr_corrida', v_id::text, jsonb_build_object('ciclo', p_ciclo, 'actividad', p_actividad, 'contratos', v_n, 'saldo', v_s, 'filtros', scrr.f_filtros(p_filtros), 'embudo', v_emb), p_ip);
  return jsonb_build_object('corrida_id', v_id, 'contratos', v_n, 'saldo_total', v_s, 'actividad', v_act.nombre);
end $$;

create function public.geoportal_scrr_corridas(p_solicitante text, p_limite integer default 30, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante);
begin
  return jsonb_build_object('corridas', (select coalesce(jsonb_agg(jsonb_build_object('corrida_id', c.id, 'ciclo', c.ciclo, 'fecha_dato', c.fecha_dato, 'actividad', t.nombre, 'actividad_codigo', t.codigo,
           'contratos', c.contratos, 'saldo_total', c.saldo_total, 'filtros', c.filtros, 'autor', c.autor, 'creada_en', c.creado_en) order by c.creado_en desc), '[]'::jsonb)
      from (select * from scrr.corridas order by creado_en desc limit greatest(1, least(coalesce(p_limite, 30), 100))) c join scrr.tipos_actividad t on t.id = c.actividad_id));
end $$;

-- Lista de una corrida para descargar (Excel) o imprimir. EXCEPCIÓN ESCRITA a la regla de descargas (P2 del 22-nov): solo para las listas de campo del SCRR,
-- llevan NOMBRE y DIRECCIÓN del suscriptor (nunca teléfono, correo ni identificación), resueltos de public.cartera_suscripcion al momento de pedirla (no se copian),
-- y cada descarga o impresión queda en la auditoría. Las dos versiones (operario y gestor de cobro) llevan la deuda (P9).
create function public.geoportal_scrr_lista(p_solicitante text, p_corrida uuid, p_formato text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.corridas; v_act scrr.tipos_actividad; v_filas jsonb;
begin
  if p_formato is null or p_formato not in ('excel','impresion') then perform scrr.f_err('Formato no válido'); end if;
  select * into c from scrr.corridas where id = p_corrida;
  if not found then perform scrr.f_err('La corrida no existe', 'P0002'); end if;
  select * into v_act from scrr.tipos_actividad where id = c.actividad_id;
  select coalesce(jsonb_agg(jsonb_build_object('orden', k.orden, 'contrato', k.contrato::text, 'nombre', s.nombre, 'direccion', s.direccion, 'barrio', coalesce(s.barrio, br.nombre_norm),
                    'ciclo', c.ciclo, 'ruta', k.ruta, 'codigo_reparto', k.codigo_reparto, 'facturas_vencidas', k.facturas_vencidas, 'saldo_pendiente', k.saldo_pendiente,
                    'marca', case k.marca when 'abono' then 'Abonó desde la fecha del archivo' when 'abono_desde_suspension' then 'Abonó desde la fecha de suspensión' end)
                  order by k.orden), '[]'::jsonb)
    into v_filas
    from scrr.corrida_contratos k
    left join lateral (select x.nombre, x.direccion, x.barrio from public.cartera_suscripcion x where x.contrato = k.contrato::text limit 1) s on true
    left join scrr.barrios br on br.id = k.barrio_id
   where k.corrida_id = p_corrida;
  perform scrr.f_auditar(v_email, 'scrr_lista_' || p_formato, p_corrida::text, jsonb_build_object('filas', jsonb_array_length(v_filas), 'ciclo', c.ciclo, 'actividad', v_act.codigo), p_ip);
  return jsonb_build_object('corrida_id', c.id, 'ciclo', c.ciclo, 'fecha_dato', c.fecha_dato, 'actividad', v_act.nombre, 'actividad_codigo', v_act.codigo,
                            'generada_en', c.creado_en, 'autor', c.autor, 'filas', v_filas);
end $$;

-- =====================================================================
-- SCRR · CORTE 2 · 50 — REFRESCO DEL MAPA COMERCIAL POR EL CARGADOR (David, 22-nov: lo hacía cargar_diario.py; el script se retira)
-- Después de cerrar (o de revertir) una carga de cartera, la Edge geoportal-scrr corre, con una conexión PROPIA a la base y como sentencia suelta:
--     refresh materialized view concurrently public.predios_comercial;
-- Por qué no lo hace una RPC: las RPC corren como service_role con statement_timeout de 30 s (un SET dentro de la función no lo amplía; probado en local) y el
-- refresco real tarda decenas de segundos. La conexión propia pone su tope (120 s) y un candado de sesión para que no corran dos refrescos a la vez.
-- CONCURRENTLY: el mapa se sigue leyendo durante el refresco (probado en local con 123.000 predios: lecturas de 13 ms como máximo).
-- Rol MÍNIMO scrr_refresco (PostgreSQL 17, privilegio MAINTAIN): solo puede refrescar esa vista; no puede leerla ni leer ninguna tabla (probado en local).
-- Nace SIN login: la clave la pone David en el editor (alter role scrr_refresco login password '…') y la cadena de conexión va en el secreto de la Edge
-- SCRR_REFRESCO_DB_URL. Ninguna clave queda en este archivo ni en el repositorio. Sin el secreto, la Edge responde «falta configurar» y la carga sigue aplicada.
-- =====================================================================
create role scrr_refresco nologin noinherit nosuperuser nocreatedb nocreaterole noreplication;
comment on role scrr_refresco is 'SCRR corte 2: solo refresca public.predios_comercial (MAINTAIN). Lo usa la Edge geoportal-scrr con el secreto SCRR_REFRESCO_DB_URL.';
do $$ begin execute format('grant connect on database %I to scrr_refresco', current_database()); end $$;
grant usage on schema public to scrr_refresco;
grant maintain on public.predios_comercial to scrr_refresco;

-- Antes del refresco: quién lo pide (Supervisor comercial o administrador) y sobre qué carga de cartera; queda en la auditoría
create function public.geoportal_scrr_refresco_iniciar(p_solicitante text, p_carga uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found or c.tipo <> 'cartera' then perform scrr.f_err('La carga de cartera no existe', 'P0002'); end if;
  if scrr.f_estado_carga(p_carga) not in ('aplicada', 'anulada', 'reemplazada') then perform scrr.f_err('El mapa se actualiza al cerrar o revertir una carga de cartera', '55000'); end if;
  perform scrr.f_auditar(v_email, 'scrr_refresco_mapa_inicio', p_carga::text, jsonb_build_object('estado_carga', scrr.f_estado_carga(p_carga)), p_ip);
  return jsonb_build_object('ok', true);
end $$;

-- Después: el resultado (ok, ocupado, error o sin_configurar) y cuánto tardó
create function public.geoportal_scrr_refresco_cerrar(p_solicitante text, p_carga uuid, p_resultado text, p_ms integer, p_detalle text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante);
begin
  if p_resultado is null or p_resultado not in ('ok', 'ocupado', 'error', 'sin_configurar') then perform scrr.f_err('Resultado no válido'); end if;
  perform scrr.f_auditar(v_email, 'scrr_refresco_mapa', p_carga::text, jsonb_build_object('resultado', p_resultado, 'ms', p_ms, 'detalle', left(p_detalle, 300)), p_ip);
  return jsonb_build_object('ok', true);
end $$;

-- =====================================================================
-- SCRR · CORTE 2 · 40 — PERMISOS. Todo objeto nuevo: revoke all … from public, anon, authenticated, service_role ANTES de dar permisos.
-- Solo service_role ejecuta las RPC public.geoportal_scrr_* (la Edge geoportal-scrr). Nadie más toca el esquema scrr: las RPC son SECURITY DEFINER.
-- scrr.f_retirar_historial no se da a nadie: solo la corre el dueño desde el editor (P7 del 22-nov).
-- =====================================================================
revoke all on all tables in schema scrr from public, anon, authenticated, service_role;
revoke all on all sequences in schema scrr from public, anon, authenticated, service_role;
revoke all on all functions in schema scrr from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_scrr\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- =====================================================================
-- SCRR · CORTE 2 · 60 — SEMILLA (parámetros, tipos de actividad, anomalías PROVISIONALES y particiones iniciales)
-- =====================================================================
insert into scrr.parametros (clave, valor, autor, motivo)
select x.clave, x.valor::jsonb, 'sistema@emdupar.gov.co', x.motivo
  from (values
    ('lote_filas', '2000', 'Lotes de 2.000 filas (fase 0)'),
    ('tope_filas_archivo', '250000', 'Tope de filas por archivo (cartera completa ~112.000)'),
    ('tope_rechazo_pct', '5', 'Más del 5 % de filas rechazadas impide aplicar'),
    ('carga_pausada', 'false', 'Interruptor para pausar las cargas'),
    ('comodin_contrato', '99999999', 'Comodín real de cartera_suscripcion (no −1)'),
    ('ventana_dias_historial', '10', 'P7 del 22-nov: el historial diario se guarda 10 días (ventana de facturación)'),
    ('retencion_meses_pagos', '13', 'Decisión 3 del 20-nov: pagos 13 meses'),
    ('paso_dias', '7', 'Copia técnica (paso y respaldo) 7 días'),
    ('tope_salidas_suscripcion_pct', '5', 'Si más del 5 % de cartera_suscripcion no viene en el archivo, se exige confirmar con motivo'),
    ('monto_minimo_opciones', '[5000,10000,20000]', 'Embudo del 20-nov: monto mínimo'),
    ('monto_minimo_defecto', '5000', 'Embudo del 20-nov: $ 5.000 por defecto')
  ) as x(clave, valor, motivo);

insert into scrr.tipos_actividad (id, codigo, nombre, actividad_campo, seleccionable, admite_drastico, estado_resultante, orden) values
  (1, 'suspension',          'Suspensión',          'suspension', true,  false, 'suspendido', 1),
  (2, 'corte',               'Corte',               'corte',      true,  true,  'cortado',    2),
  (3, 'gestion_cobro',       'Gestión de cobro',    null,         true,  false, null,         3),
  (4, 'reinstalacion',       'Reinstalación',       'reconexion', false, false, 'activo',     4),
  (5, 'reconexion',          'Reconexión',          'reconexion', false, false, 'activo',     5),
  (6, 'reconexion_drastica', 'Reconexión drástica', 'reconexion', false, false, 'activo',     6);

-- Decisión 9 del 20-nov (los 16 de Acuo, 00040_anomalias_actividad_resultado.sql, más 17 OTRO MEDIDOR). DEFINITIVO (David, 22-nov).
insert into scrr.anomalias (codigo, nombre, provisional, fuente, orden)
select n, x, false, case when n = 17 then 'decisión 9 del 20-nov' else 'Acuo 00040 y decisión 9 del 20-nov' end, n
  from unnest(array['PAGO EFECTUADO','CLIENTE NO PERMITE','USUARIO AGRESIVO','USUARIO ABONO','ACOMETIDA NO VISIBLE','ADULTO MAYOR','MENOR DE EDAD','PREDIO SOLO',
                    'FIRMA','SIGUE SUSPENDIDO','PREDIO ENREJADO','RECLAMO EN TRAMITE','VIGILANTE NO PERMITE','DIRECCION ERRADA','OTROS','SE GESTIONA PAGO','OTRO MEDIDOR'])
       with ordinality as a(x, n);

-- Causas de los contratos con control y de los excluidos manuales (P6 del 22-nov: la misma tabla de eventos, con su causa)
insert into scrr.causas_control (id, codigo, nombre, grupo) values
  (1, 'reclamo_manual', 'Reclamo manual', 'reclamo'),
  (2, 'insolvencia', 'Proceso de insolvencia', 'control'),
  (3, 'minimo_vital', 'Mínimo vital', 'control'),
  (4, 'excluido_manual', 'Excluido manual por el supervisor', 'excluido');

-- Calendario de noviembre de 2026 (sección 3 del encargo del 20-nov): 24 ciclos con pago oportuno y fecha de suspensión. Se pueden agregar más ciclos desde la pantalla.
insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, autor) values
  ('202611', 15, '2026-11-12', '2026-11-13', 'sistema@emdupar.gov.co'),
  ('202611', 19, '2026-11-12', '2026-11-13', 'sistema@emdupar.gov.co'),
  ('202611', 21, '2026-11-12', '2026-11-13', 'sistema@emdupar.gov.co'),
  ('202611', 1, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 20, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 2, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 16, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 23, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 22, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 4, '2026-11-17', '2026-11-18', 'sistema@emdupar.gov.co'),
  ('202611', 3, '2026-11-17', '2026-11-18', 'sistema@emdupar.gov.co'),
  ('202611', 5, '2026-11-17', '2026-11-18', 'sistema@emdupar.gov.co'),
  ('202611', 12, '2026-11-18', '2026-11-19', 'sistema@emdupar.gov.co'),
  ('202611', 24, '2026-11-18', '2026-11-19', 'sistema@emdupar.gov.co'),
  ('202611', 6, '2026-11-18', '2026-11-19', 'sistema@emdupar.gov.co'),
  ('202611', 9, '2026-11-18', '2026-11-19', 'sistema@emdupar.gov.co'),
  ('202611', 17, '2026-11-19', '2026-11-20', 'sistema@emdupar.gov.co'),
  ('202611', 18, '2026-11-19', '2026-11-20', 'sistema@emdupar.gov.co'),
  ('202611', 8, '2026-11-19', '2026-11-20', 'sistema@emdupar.gov.co'),
  ('202611', 11, '2026-11-20', '2026-11-21', 'sistema@emdupar.gov.co'),
  ('202611', 7, '2026-11-20', '2026-11-21', 'sistema@emdupar.gov.co'),
  ('202611', 14, '2026-11-23', '2026-11-24', 'sistema@emdupar.gov.co'),
  ('202611', 10, '2026-11-23', '2026-11-24', 'sistema@emdupar.gov.co'),
  ('202611', 13, '2026-11-23', '2026-11-24', 'sistema@emdupar.gov.co');

insert into scrr.codigos_heredados (campo, codigo, significado) values ('estado', 3, 'efectiva'), ('estado', 4, 'inefectiva');

-- Particiones iniciales: historial desde hace 10 días hasta 45 días adelante; pagos desde hace 13 meses hasta 2 meses adelante
select scrr.f_preparar_historial((now() at time zone 'America/Bogota')::date - 10, (now() at time zone 'America/Bogota')::date + 45);
select scrr.f_preparar_pagos((date_trunc('month', now() at time zone 'America/Bogota') - interval '13 months')::date,
                             (date_trunc('month', now() at time zone 'America/Bogota') + interval '2 months')::date);

-- =====================================================================
-- SCRR · CORTE 2 · 70 — PRUEBAS del primer commit (cargas del día). Dentro del ensayo: todo se deshace con el ERROR esperado del final.
-- Datos propios con prefijo ZTSCRR (correos ztscrr.*@emdupar.gov.co; contratos de 12 dígitos 91000000xxxx, que no existen en la cartera real).
-- Cada prueba cuenta SOLO sus filas. Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- En producción public.cartera_suscripcion tiene la cartera real: estas pruebas NO cierran una carga de cartera (el cierre retiraría los contratos reales
-- que no vienen en el archivo de prueba). Prueban que la guardia lo impide y revierten lo que aplicaron. El cierre completo de cartera (salidas, reemplazo,
-- reversión después del cierre) se prueba solo en local: pruebas_locales/75_pruebas_cierre_local.sql.
-- Sin tablas temporales que se borren al confirmar (regla de David, 21-nov): la tabla de resultados se deshace con el ERROR esperado del final.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztscrr_res (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztscrr_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), left(p_detalle, 600)) $f$;
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
-- una fila de cartera de prueba (todas las columnas de la plantilla)
-- p_pend = facturas pendientes; el ciclo de prueba sale del contrato: 97 (sin calendario), 98 (pago oportuno ya pasó) o 99 (aún no pasa)
create function pg_temp.fc(p_contrato bigint, p_saldo numeric, p_pend int, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $f$
  select jsonb_build_object('contrato', p_contrato::text, 'estado', 'ACTIVO', 'identificacion', 'ZT' || p_contrato, 'nombre', 'ZTSCRR SUSCRIPTOR ' || p_contrato,
         'correo', 'zt' || p_contrato || '@ejemplo.invalid', 'telefono', '3000000000', 'direccion', 'ZTSCRR CALLE ' || (p_contrato % 1000), 'barrio', 'ztscrr barrio ' || (p_contrato % 3),
         'categoria', '1 - RESIDENCIAL', 'subcategoria', '2 - ESTRATO 2', 'ciclo', (97 + (p_contrato % 3))::text, 'facturas_pendientes', p_pend::text,
         'deuda_total', (p_saldo + 1000)::text, 'saldo_pendiente', p_saldo::text, 'saldo_a_favor', '0', 'valor_reclamo', '0',
         'saldo_financiado', '1000', 'serial_medidor', 'ZTM' || p_contrato, 'codigo_reparto', 'R1', 'ruta', 'ZTRUTA') || p_extra $f$;
create function pg_temp.lote(p_carga text, p_lote int, p_filas jsonb, p_sol text default 'ztscrr.sup@emdupar.gov.co') returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_scrr_carga_lote(%L, %L::uuid, %s, %L::jsonb)', p_sol, p_carga, p_lote, p_filas)) $f$;
create function pg_temp.iniciar(p_tipo text, p_fecha date, p_sha text, p_filas int, p_sol text default 'ztscrr.sup@emdupar.gov.co') returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_scrr_carga_iniciar(%L, %L, %L::date, %L, %L, %s)', p_sol, p_tipo, p_fecha, 'ztscrr_' || p_tipo || '.xlsx', p_sha, p_filas)) $f$;
create function pg_temp.sha(p text) returns text language sql as $f$ select md5(p) || md5(p || 'x') $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta, ver_registro_tecnico) values
  ('ztscrr.adm@emdupar.gov.co', 'ZTSCRR Admin', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false, false),
  ('ztscrr.sup@emdupar.gov.co', 'ZTSCRR Supervisor comercial', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, true, true, false),
  ('ztscrr.supcampo@emdupar.gov.co', 'ZTSCRR Supervisor solo campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false, false),
  ('ztscrr.supacta@emdupar.gov.co', 'ZTSCRR Supervisor de actas', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, true, false),
  ('ztscrr.op@emdupar.gov.co', 'ZTSCRR Operario', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, true, false, false),
  ('ztscrr.tec@emdupar.gov.co', 'ZTSCRR Solo Técnica', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false, true),
  ('ztscrr.inactivo@emdupar.gov.co', 'ZTSCRR Inactivo', 'consulta', false, 'sin_restriccion', 'todos', false, true, true, true, true, false);

do $$
declare
  A text := 'ztscrr.adm@emdupar.gov.co'; S text := 'ztscrr.sup@emdupar.gov.co'; SC text := 'ztscrr.supcampo@emdupar.gov.co';
  r jsonb; c1 text; c2 text; cp text; ca text; v_hoy date := (now() at time zone 'America/Bogota')::date; f jsonb; t0 timestamptz; v_lote int;
  B bigint := 910000000000;   -- base de los contratos de prueba
  v_reales bigint; v_tope numeric; v_esperado_bloqueo boolean;
begin
  -- ===== 00. Quién entra al modo «Cartera» =====
  r := pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', S));
  perform pg_temp.ok('00.01 el Supervisor comercial (dashboard_campo) entra', pg_temp.err(r) = 'OK' and r ->> 'correo' = S and (r ->> 'es_admin')::boolean = false, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', SC));
  perform pg_temp.ok('00.02 el supervisor con solo dashboard_campo también entra', pg_temp.err(r) = 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', A));
  perform pg_temp.ok('00.03 el administrador entra (sin casillas)', pg_temp.err(r) = 'OK' and (r ->> 'es_admin')::boolean, r::text);
  perform pg_temp.ok('00.04 el supervisor de actas sin dashboard_campo: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', 'ztscrr.supacta@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.05 el operario: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', 'ztscrr.op@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.06 la persona solo de Técnica: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', 'ztscrr.tec@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.07 una persona inactiva con las casillas: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', 'ztscrr.inactivo@emdupar.gov.co'))) = '42501');
  perform pg_temp.ok('00.08 sin correo: 28000', pg_temp.err(pg_temp.rpc('public.geoportal_scrr_contexto(null)')) = '28000');
  r := pg_temp.rpc(format('public.geoportal_scrr_contexto(%L)', S));
  perform pg_temp.ok('00.09 contexto: las 17 anomalías DEFINITIVAS en el orden de la decisión 9 (1 PAGO EFECTUADO … 17 OTRO MEDIDOR)',
    jsonb_array_length(r -> 'anomalias') = 17 and not (select bool_or((x ->> 'provisional')::boolean) from jsonb_array_elements(r -> 'anomalias') x)
    and r -> 'anomalias' -> 0 ->> 'nombre' = 'PAGO EFECTUADO' and r -> 'anomalias' -> 16 ->> 'nombre' = 'OTRO MEDIDOR' and r -> 'anomalias' -> 7 ->> 'nombre' = 'PREDIO SOLO');
  perform pg_temp.ok('00.10 contexto: se escogen Suspensión, Corte y Gestión de cobro; solo Corte admite drástico',
    (select string_agg(x ->> 'codigo', ',' order by (x ->> 'id')::int) from jsonb_array_elements(r -> 'tipos_actividad') x where (x ->> 'seleccionable')::boolean) = 'suspension,corte,gestion_cobro'
    and (select string_agg(x ->> 'codigo', ',') from jsonb_array_elements(r -> 'tipos_actividad') x where (x ->> 'admite_drastico')::boolean) = 'corte');
  perform pg_temp.ok('00.11 contexto: historial 10 días, pagos 13 meses, lotes de 2.000',
    (r -> 'parametros' ->> 'ventana_dias_historial')::int = 10 and (r -> 'parametros' ->> 'retencion_meses_pagos')::int = 13 and (r -> 'parametros' ->> 'lote_filas')::int = 2000);

  -- ===== 01. Iniciar =====
  perform pg_temp.ok('01.01 tipo de carga desconocido: 22023', pg_temp.err(pg_temp.iniciar('control', v_hoy, pg_temp.sha('a'), 10)) = '22023');
  perform pg_temp.ok('01.02 fecha del dato futura: 22023', pg_temp.err(pg_temp.iniciar('cartera', v_hoy + 1, pg_temp.sha('a'), 10)) = '22023');
  perform pg_temp.ok('01.03 huella no válida: 22023', pg_temp.err(pg_temp.iniciar('cartera', v_hoy, 'abc', 10)) = '22023');
  perform pg_temp.ok('01.04 más filas que el tope (250.000): 22023', pg_temp.err(pg_temp.iniciar('cartera', v_hoy, pg_temp.sha('a'), 250001)) = '22023');
  perform pg_temp.ok('01.05 el operario no inicia cargas: 42501', pg_temp.err(pg_temp.iniciar('cartera', v_hoy, pg_temp.sha('a'), 10, 'ztscrr.op@emdupar.gov.co')) = '42501');
  -- calendario de prueba del período de hoy para los ciclos 98 (pago oportuno ayer: ya pasó) y 99 (mañana: no ha pasado); el 97 queda sin calendario
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 98, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy - 1, v_hoy - 1));
  perform pg_temp.ok('01.09 calendario: el supervisor agrega el ciclo 98 (nuevo, sin motivo)', pg_temp.err(r) = 'OK' and (r ->> 'nuevo')::boolean, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 99, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy + 1, v_hoy + 2));
  perform pg_temp.ok('01.10 calendario: y el ciclo 99', pg_temp.err(r) = 'OK', r::text);
  -- cartera de prueba: 2.003 filas (2 lotes: 2.000 + 3)
  r := pg_temp.iniciar('cartera', v_hoy, pg_temp.sha('cartera1'), 2003);
  c1 := r ->> 'carga_id';
  perform pg_temp.ok('01.06 inicia la cartera: 2 lotes de 2.000', pg_temp.err(r) = 'OK' and (r ->> 'lotes')::int = 2 and (r ->> 'repetido')::boolean = false, r::text);
  r := pg_temp.iniciar('cartera', v_hoy, pg_temp.sha('cartera1'), 2003);
  perform pg_temp.ok('01.07 el mismo archivo otra vez devuelve la misma carga (reintento)', r ->> 'carga_id' = c1 and (r ->> 'repetido')::boolean, r::text);
  perform pg_temp.ok('01.08 otro archivo de cartera con una abierta: 55000', pg_temp.err(pg_temp.iniciar('cartera', v_hoy, pg_temp.sha('otra'), 5)) = '55000');

  -- ===== 02. Lotes =====
  -- lote 1: 2.000 contratos B+1..B+2000; con saldo los impares; el B+1 con 7 vencidas y reclamo; B+3 con categoría «-1»
  -- con saldo los impares; B+1 (ciclo 99) con 8 pendientes y reclamo; B+3 (ciclo 98) con categoría «-1»; B+2 con cifras VACÍAS (valen cero). Ciclo = 97 + (contrato mod 3)
  select jsonb_agg(case when g = 1 then pg_temp.fc(B + g, 150000, 8, '{"valor_reclamo": "25000"}')
                        when g = 2 then pg_temp.fc(B + g, 0, 0, '{"deuda_total": "", "saldo_financiado": " "}') - 'saldo_a_favor'
                        when g = 3 then pg_temp.fc(B + g, 9000, 2, '{"categoria": "-1 - ------"}')
                        when g % 2 = 1 then pg_temp.fc(B + g, 20000 + g, (g % 30)::int + 1)
                        else pg_temp.fc(B + g, 0, 0) end order by g) into f
    from generate_series(1, 2000) g;
  perform pg_temp.ok('02.01 un lote con menos filas de las que le tocan: 22023', pg_temp.err(pg_temp.lote(c1, 1, f - 0)) = '22023');
  t0 := clock_timestamp();
  r := pg_temp.lote(c1, 1, f);
  perform pg_temp.ok('02.02 lote 1 de 2.000 filas recibido (' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms)', pg_temp.err(r) = 'OK' and (r ->> 'filas')::int = 2000, r::text);
  r := pg_temp.lote(c1, 1, f);
  perform pg_temp.ok('02.03 el mismo lote otra vez no duplica', (r ->> 'repetido')::boolean and (select count(*) from scrr.paso_cartera where carga_id = c1::uuid) = 2000, r::text);
  perform pg_temp.ok('02.04 el lote 1 con otro contenido: 55000', pg_temp.err(pg_temp.lote(c1, 1, jsonb_set(f, '{0,saldo_pendiente}', '"1"'))) = '55000');
  -- lote 2: tres filas con errores distintos (todas son rechazos del servidor)
  r := pg_temp.lote(c1, 2, jsonb_build_array(
         pg_temp.fc(B + 2001, 1000, 1, '{"contrato": "12A"}'),
         pg_temp.fc(B + 2002, 1000, 1, '{"deuda_total": "mil pesos"}'),
         pg_temp.fc(B + 2003, 1000, 1, '{"ciclo": "X9"}')));
  perform pg_temp.ok('02.05 lote 2 con 3 filas con error queda en el paso con su causa',
    pg_temp.err(r) = 'OK' and (select string_agg(error, ' | ' order by fila) from scrr.paso_cartera where carga_id = c1::uuid and lote = 2)
      = 'Contrato ausente o no numérico | Cifra con formato no válido (vacío vale cero) | Ciclo no válido', r::text);
  perform pg_temp.ok('02.07 cifras vacías o ausentes valen CERO (David, 22-nov): la fila de B+2 se acepta con deuda total y saldos en 0',
    (select error is null and deuda_total = 0 and saldo_a_favor = 0 and saldo_financiado = 0 from scrr.paso_cartera where carga_id = c1::uuid and contrato = (B + 2)::text));
  perform pg_temp.ok('02.06 el paso guarda la cartera COMPLETA (P4): nombre, dirección y teléfono del archivo',
    (select nombre is not null and direccion is not null and telefono is not null from scrr.paso_cartera where carga_id = c1::uuid and contrato = (B + 1)::text));

  -- ===== 03. Validar =====
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, c1));
  perform pg_temp.ok('03.01 validar: 3 rechazadas de 2.003 (0,15 %), puede aplicar', pg_temp.err(r) = 'OK' and (r ->> 'filas_rechazadas')::int = 3 and (r ->> 'puede_aplicar')::boolean, r::text);
  perform pg_temp.ok('03.02 validar: 1.000 con saldo pendiente, con reclamo 1, comodín o «-1» 1',
    (r ->> 'con_saldo_pendiente')::int = 1000 and (r ->> 'con_valor_reclamo')::int = 1 and (r ->> 'comodin_o_categoria_menos_1')::int = 1, r::text);
  perform pg_temp.ok('03.03 validar: vencidas derivadas (todas las de saldo tienen al menos una) y 333 con saldo en un ciclo sin calendario (el 97)',
    (r ->> 'con_facturas_vencidas')::int = 1000 and (r ->> 'con_saldo_sin_calendario')::int = 333 and r -> 'ciclos_sin_calendario' = '[97]'::jsonb, r::text);
  perform pg_temp.ok('03.04 el lote ya no entra después de validar si la carga se aplica (ver 04.06)', true);

  -- ===== 04. Aplicar por lotes (cartera) =====
  -- Antes: una fila «vieja» de un contrato de prueba que viene en el archivo, y otra de un contrato de prueba cuyo renglón del archivo tiene error
  insert into public.cartera_suscripcion (contrato, estado, nombre, direccion, saldo_pendiente, periodo_carga) values
    ((B + 2)::text, 'ZTVIEJO', 'ZTSCRR VIEJO', 'ZTSCRR DIR VIEJA', 777, '20261101'),
    ((B + 2002)::text, 'ZTVIEJO', 'ZTSCRR NO SE TOCA', 'ZTSCRR DIR', 555, '20261101');
  perform pg_temp.ok('04.01 el operario no aplica: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', 'ztscrr.op@emdupar.gov.co', c1))) = '42501');
  perform pg_temp.ok('04.02 cerrar antes de aplicar los lotes: 55000', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, c1))) = '55000');
  t0 := clock_timestamp();
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, c1));
  perform pg_temp.ok('04.03 lote 1 aplicado: 1.000 al historial y 2.000 filas nuevas en cartera_suscripcion (' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms)',
    pg_temp.err(r) = 'OK' and (r ->> 'historial')::int = 1000 and (r ->> 'suscripcion_filas_nuevas')::int = 2000 and (r ->> 'suscripcion_filas_retiradas')::int = 1, r::text);
  perform pg_temp.ok('04.04 el historial guarda vencidas DERIVADAS: ciclo 99 (aún no pasa el pago oportuno) 8 pendientes → 7; ciclo 98 (ya pasó) 2 → 2; ciclo 97 (sin calendario) 6 → 5',
    (select facturas_vencidas = 7 and facturas_pendientes = 8 from scrr.cartera_historial where carga_id = c1::uuid and contrato = B + 1)
    and (select facturas_vencidas = 2 and facturas_pendientes = 2 from scrr.cartera_historial where carga_id = c1::uuid and contrato = B + 3)
    and (select facturas_vencidas = 5 and facturas_pendientes = 6 from scrr.cartera_historial where carga_id = c1::uuid and contrato = B + 5));
  perform pg_temp.ok('04.04b el historial guarda reclamo y la marca del «-1»; sin nombre ni dirección',
    (select valor_reclamo = 25000 from scrr.cartera_historial where carga_id = c1::uuid and contrato = B + 1)
    and (select marca = 1 from scrr.cartera_historial where carga_id = c1::uuid and contrato = B + 3)
    and not exists (select 1 from information_schema.columns where table_schema = 'scrr' and table_name = 'cartera_historial' and column_name in ('nombre','direccion','telefono','identificacion','correo')));
  perform pg_temp.ok('04.05 cartera_suscripcion: el contrato viejo quedó con lo del archivo y su fila anterior en el respaldo',
    (select count(*) = 1 and min(nombre) = 'ZTSCRR SUSCRIPTOR ' || (B + 2) and min(periodo_carga) = to_char(v_hoy, 'YYYYMMDD') from public.cartera_suscripcion where contrato = (B + 2)::text)
    and (select filas -> 0 ->> 'nombre' = 'ZTSCRR VIEJO' and origen = 'archivo' from scrr.suscripcion_respaldo where carga_id = c1::uuid and contrato = (B + 2)::text)
    and (select filas = '[]'::jsonb from scrr.suscripcion_respaldo where carga_id = c1::uuid and contrato = (B + 1)::text));
  perform pg_temp.ok('04.06 ya aplicando, la carga no admite lotes nuevos: 55000', pg_temp.err(pg_temp.lote(c1, 2, '[]'::jsonb)) = '55000');
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, c1));
  perform pg_temp.ok('04.07 aplicar el lote 1 otra vez no duplica', (r ->> 'repetido')::boolean and (select count(*) from public.cartera_suscripcion where contrato like '91000000%') = 2001, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 2)', S, c1));
  perform pg_temp.ok('04.08 lote 2 (todas con error) no toca cartera_suscripcion: la fila del contrato con error sigue igual',
    pg_temp.err(r) = 'OK' and (r ->> 'suscripcion_filas_nuevas')::int = 0
    and (select nombre from public.cartera_suscripcion where contrato = (B + 2002)::text) = 'ZTSCRR NO SE TOCA', r::text);
  perform pg_temp.ok('04.09 estado de la carga: aplicando, 2 lotes aplicados',
    (select scrr.f_estado_carga(c1::uuid)) = 'aplicando' and jsonb_array_length(pg_temp.rpc(format('public.geoportal_scrr_carga_estado(%L, %L::uuid)', S, c1)) -> 'lotes_aplicados') = 2);

  -- ===== 05. Cierre de cartera: la guardia contra un archivo incompleto =====
  select count(*) into v_reales from public.cartera_suscripcion where contrato is not null and contrato not like '91000000%';
  v_tope := (scrr.f_param('tope_salidas_suscripcion_pct'))::numeric;
  if v_reales = 0 then   -- base local sin cartera real: se siembran 1.000 contratos de prueba que «no vienen en el archivo»
    insert into public.cartera_suscripcion (contrato, estado, nombre, periodo_carga) select (B + 5000 + g)::text, 'ZTVIEJO', 'ZTSCRR AUSENTE', '20261101' from generate_series(1, 1000) g;
  end if;
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, c1));
  perform pg_temp.ok('05.01 cerrar con más del 5 % de la cartera ausente del archivo: 55000 y no retira nada',
    pg_temp.err(r) = '55000' and r ->> 'msg' like '%no vienen en el archivo%' and (select count(*) from public.cartera_suscripcion) >= v_reales + 2001, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, null, true, null)', S, c1));
  perform pg_temp.ok('05.02 confirmarlo sin motivo: 22023', pg_temp.err(r) = '22023', r::text);

  -- ===== 06. Revertir cartera_suscripcion y anular =====
  perform pg_temp.ok('06.01 anular sin revertir la tabla: 55000', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, c1, 'ZTSCRR prueba de anulación'))) = '55000');
  perform pg_temp.ok('06.02 revertir sin motivo: 22023', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_suscripcion_revertir(%L, %L::uuid, %L)', S, c1, 'corto'))) = '22023');
  r := pg_temp.rpc(format('public.geoportal_scrr_suscripcion_revertir(%L, %L::uuid, %L)', S, c1, 'ZTSCRR revierto la carga de prueba'));
  perform pg_temp.ok('06.03 revertir: quita las 2.001 filas del archivo y restaura la vieja; no quedan pendientes',
    pg_temp.err(r) = 'OK' and (r ->> 'pendientes')::int = 0 and (r ->> 'filas_restauradas')::int = 1
    and (select count(*) from public.cartera_suscripcion where contrato like '91000000%' and contrato::bigint <= B + 2003) = 2
    and (select nombre from public.cartera_suscripcion where contrato = (B + 2)::text) = 'ZTSCRR VIEJO'
    and (select nombre from public.cartera_suscripcion where contrato = (B + 2002)::text) = 'ZTSCRR NO SE TOCA', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, c1, 'ZTSCRR prueba de anulación'));
  perform pg_temp.ok('06.04 ya revertida, se anula; el historial queda oculto (no borrado)',
    pg_temp.err(r) = 'OK' and scrr.f_estado_carga(c1::uuid) = 'anulada'
    and (select count(*) from scrr.cartera_historial where carga_id = c1::uuid) = 1000 and (select count(*) from scrr.v_cartera_vigente where carga_id = c1::uuid) = 0, r::text);
  perform pg_temp.ok('06.05 la auditoría registra iniciar, validar, revertir y anular de la carga',
    (select count(distinct accion) from public.geoportal_auditoria where referencia = c1 and accion in ('scrr_carga_iniciar','scrr_carga_validar','scrr_suscripcion_revertir','scrr_carga_anular')) = 4);
  begin
    update scrr.cargas set archivo_nombre = 'x' where id = c1::uuid;
    perform pg_temp.ok('06.06 las tablas de hechos son de solo inserción (update de una carga: 55000)', false);
  exception when sqlstate '55000' then
    perform pg_temp.ok('06.06 las tablas de hechos son de solo inserción (update de una carga: 55000)', true);
  end;

  -- ===== 07. Pagos (plantilla provisional: contrato, fecha de pago, monto) =====
  r := pg_temp.iniciar('pagos', v_hoy, pg_temp.sha('pagos1'), 6);
  cp := r ->> 'carga_id';
  r := pg_temp.lote(cp, 1, jsonb_build_array(
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 3)::text, 'fecha_pago', (v_hoy - 1)::text, 'monto', '9000'),
         jsonb_build_object('contrato', (B + 5)::text, 'fecha_pago', (v_hoy + 1)::text, 'monto', '100'),
         jsonb_build_object('contrato', (B + 7)::text, 'fecha_pago', (v_hoy - interval '2 years')::date::text, 'monto', '100'),
         jsonb_build_object('contrato', (B + 9)::text, 'fecha_pago', v_hoy::text, 'monto', '0')));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, cp));
  perform pg_temp.ok('07.01 pagos: rechaza fecha futura, fuera de los 13 meses y monto cero; 3 válidos (50 % rechazado: no se aplica)',
    (r ->> 'pagos_validos')::int = 3 and (r -> 'causas_rechazo' ->> 'Fecha de pago futura')::int = 1 and (r -> 'causas_rechazo' ->> 'Fecha de pago fuera de la retención')::int = 1
    and (r -> 'causas_rechazo' ->> 'Monto ausente, en cero o no válido')::int = 1 and (r ->> 'puede_aplicar')::boolean = false, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, cp));
  perform pg_temp.ok('07.02 con más del 5 % rechazado no se aplica: 55000', pg_temp.err(r) = '55000', r::text);
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, cp, 'ZTSCRR archivo de pagos con errores'));
  r := pg_temp.iniciar('pagos', v_hoy, pg_temp.sha('pagos2'), 3);
  cp := r ->> 'carga_id';
  perform pg_temp.lote(cp, 1, jsonb_build_array(
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 3)::text, 'fecha_pago', (v_hoy - 1)::text, 'monto', '9000')));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, cp));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, cp));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, cp));
  perform pg_temp.ok('07.03 pagos aplicados: dos pagos idénticos del mismo día quedan como ordinal 1 y 2',
    pg_temp.err(r) = 'OK' and (r -> 'resultado' ->> 'pagos_nuevos')::int = 3
    and (select string_agg(ordinal::text, ',' order by ordinal) from scrr.pagos_contrato where contrato = B + 1 and carga_id = cp::uuid) = '1,2', r::text);
  r := pg_temp.iniciar('pagos', v_hoy, pg_temp.sha('pagos3'), 4);
  perform pg_temp.ok('07.04 pagos del mismo día no se reemplazan: una carga de pagos con esa fecha ya aplicada exige otra fecha o 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.iniciar('pagos', v_hoy - 1, pg_temp.sha('pagos3'), 4);
  cp := r ->> 'carga_id';
  perform pg_temp.lote(cp, 1, jsonb_build_array(
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 1)::text, 'fecha_pago', v_hoy::text, 'monto', '50000'),
         jsonb_build_object('contrato', (B + 3)::text, 'fecha_pago', (v_hoy - 1)::text, 'monto', '9000')));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, cp));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, cp));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, cp));
  perform pg_temp.ok('07.05 recargar pagos que se solapan no duplica: solo entra el tercer pago idéntico (ordinal 3)',
    (r -> 'resultado' ->> 'pagos_nuevos')::int = 1 and (r -> 'resultado' ->> 'pagos_ya_existentes')::int = 3
    and (select count(*) from scrr.pagos_contrato where contrato = B + 1) = 3, r::text);
  perform pg_temp.ok('07.06 pagos aplicados no se anulan: 55000', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, cp, 'ZTSCRR intento anular pagos'))) = '55000');

  -- ===== 08. Actividades (plantilla de la decisión 10, con la marca de drástico en Corte) =====
  r := pg_temp.iniciar('actividades', v_hoy, pg_temp.sha('act1'), 9);
  ca := r ->> 'carga_id';
  r := pg_temp.lote(ca, 1, jsonb_build_array(
    jsonb_build_object('contrato', (B + 1)::text, 'acta', 'A1', 'actividad', 'Suspensión', 'drastico', 'NO', 'estado', '3', 'anomalia', '', 'fecha', (v_hoy - 2)::text, 'hora_inicial', '08:10', 'hora_final', '08:30', 'lectura', '1234', 'medidor', 'M1', 'marca', 'ZTMARCA', 'operario', 'ZTSCRR OPERARIO'),
    jsonb_build_object('contrato', (B + 3)::text, 'acta', 'A2', 'actividad', 'CORTE', 'drastico', 'SÍ', 'estado', '3', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 5)::text, 'acta', 'A3', 'actividad', 'Corte', 'drastico', 'NO', 'estado', '4', 'anomalia', '8', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 7)::text, 'actividad', 'Reconexión', 'drastico', 'NO', 'estado', '3', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 9)::text, 'actividad', 'Suspensión', 'drastico', 'SÍ', 'estado', '3', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 11)::text, 'actividad', 'Corte', 'drastico', 'NO', 'estado', '4', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 13)::text, 'actividad', 'Corte', 'drastico', 'NO', 'estado', '4', 'anomalia', '18', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 15)::text, 'actividad', 'Lectura', 'drastico', 'NO', 'estado', '3', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 17)::text, 'actividad', 'Corte', 'drastico', 'NO', 'estado', '3', 'fecha', (v_hoy - 1)::text, 'hora_inicial', '25:00')));
  perform pg_temp.ok('08.01 actividades: cada error con su causa (drástico fuera de Corte, inefectiva sin anomalía, anomalía 18, actividad no reconocida, hora)',
    (select string_agg(coalesce(error, 'ok'), ' | ' order by fila) from scrr.paso_actividades where carga_id = ca::uuid)
      = 'ok | ok | ok | ok | La marca de drástico solo aplica a Corte | Inefectiva sin anomalía | Anomalía fuera del catálogo (1 a 17) | Actividad no reconocida | Hora inicial no válida', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, ca));
  perform pg_temp.ok('08.02 con 5 de 9 rechazadas no se aplica', (r ->> 'puede_aplicar')::boolean = false and (r ->> 'cortes_drasticos')::int = 1, r::text);
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_anular(%L, %L::uuid, %L)', S, ca, 'ZTSCRR archivo de actividades con errores'));
  r := pg_temp.iniciar('actividades', v_hoy, pg_temp.sha('act2'), 4);
  ca := r ->> 'carga_id';
  perform pg_temp.lote(ca, 1, jsonb_build_array(
    jsonb_build_object('contrato', (B + 1)::text, 'acta', 'A1', 'actividad', 'Suspensión', 'drastico', 'NO', 'estado', '3', 'fecha', (v_hoy - 2)::text, 'hora_inicial', '08:10', 'hora_final', '08:30', 'lectura', '1234', 'medidor', 'M1', 'marca', 'ZTMARCA', 'operario', 'ZTSCRR OPERARIO'),
    jsonb_build_object('contrato', (B + 3)::text, 'acta', 'A2', 'actividad', 'CORTE', 'drastico', 'SÍ', 'estado', '3', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 5)::text, 'acta', 'A3', 'actividad', 'Corte', 'drastico', 'NO', 'estado', '4', 'anomalia', '8', 'fecha', (v_hoy - 1)::text),
    jsonb_build_object('contrato', (B + 3)::text, 'acta', 'A2', 'actividad', 'CORTE', 'drastico', 'SÍ', 'estado', '3', 'fecha', (v_hoy - 1)::text)));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, ca));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, ca));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, ca));
  perform pg_temp.ok('08.03 actividades aplicadas: 3 actas (la repetida en el archivo cuenta una vez)', pg_temp.err(r) = 'OK' and (r -> 'resultado' ->> 'actas_nuevas')::int = 3, r::text);
  perform pg_temp.ok('08.04 estado del servicio: suspendido, cortado drástico; la inefectiva no cambia el estado',
    (select estado from scrr.v_estado_servicio where contrato = B + 1) = 'suspendido' and (select estado from scrr.v_estado_servicio where contrato = B + 3) = 'cortado_drastico'
    and not exists (select 1 from scrr.v_estado_servicio where contrato = B + 5));
  perform pg_temp.ok('08.05 el acta guarda anomalía, horas, lectura, medidor, marca y operario',
    (select anomalia = 8 and resultado = 'inefectiva' from scrr.actas where contrato = B + 5)
    and (select hora_inicio = '08:10' and hora_fin = '08:30' and lectura = 1234 and medidor = 'M1' and marca_medidor = 'ZTMARCA' and operario = 'ZTSCRR OPERARIO' from scrr.actas where contrato = B + 1));

  -- ===== 09. Cargas de hoy, lista y vaciado =====
  r := pg_temp.rpc(format('public.geoportal_scrr_cargas_hoy(%L)', S));
  perform pg_temp.ok('09.01 «falta cargar hoy»: la cartera de hoy falta (la de prueba se anuló); pagos al día',
    (select (x ->> 'al_dia')::boolean = false from jsonb_array_elements(r -> 'tipos') x where x ->> 'tipo' = 'cartera')
    and (select (x ->> 'al_dia')::boolean from jsonb_array_elements(r -> 'tipos') x where x ->> 'tipo' = 'pagos'), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_cargas_lista(%L, 100)', S));
  perform pg_temp.ok('09.02 la lista muestra las 6 cargas de prueba con su estado',
    (select count(*) from jsonb_array_elements(r -> 'cargas') x where x ->> 'autor' = S) = 6);
  r := pg_temp.rpc(format('public.geoportal_scrr_vaciar_paso(%L)', S));
  perform pg_temp.ok('09.03 vaciar el paso hoy no vacía nada de prueba (tienen menos de 7 días)',
    pg_temp.err(r) = 'OK' and (select count(*) from scrr.paso_cartera where carga_id = c1::uuid) = 2003, r::text);

  -- ===== 11. Calendario =====
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_lista(%L, %L)', S, '202611'));
  perform pg_temp.ok('11.01 calendario de noviembre sembrado: 24 ciclos; el 15 con pago oportuno 12/11 y suspensión 13/11',
    (select count(*) from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int between 1 and 24) = 24 and (select x ->> 'pago_oportuno' = '2026-11-12' and x ->> 'fecha_suspension' = '2026-11-13' from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 15), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 98, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy - 1, v_hoy - 1));
  perform pg_temp.ok('11.02 guardar el mismo ciclo sin cambios: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 98, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy - 1, v_hoy));
  perform pg_temp.ok('11.03 cambiar un ciclo ya guardado sin motivo: 22023', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 98, %L::date, %L::date, %L::jsonb, %L)', S, to_char(v_hoy, 'YYYYMM'), v_hoy - 1, v_hoy, '{"reparto": "2026-11-05"}', 'ZTSCRR se corre la suspensión'));
  perform pg_temp.ok('11.04 con motivo se guarda una versión nueva (la anterior queda en el historial) y las etapas de contexto',
    pg_temp.err(r) = 'OK' and (select count(*) from scrr.calendario_ciclos where periodo = to_char(v_hoy, 'YYYYMM') and ciclo = 98) = 2
    and (select etapas ->> 'reparto' from scrr.v_calendario_vigente where periodo = to_char(v_hoy, 'YYYYMM') and ciclo = 98) = '2026-11-05', r::text);
  perform pg_temp.ok('11.05 suspensión antes del pago oportuno: 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 96, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy, v_hoy - 1))) = '22023');
  perform pg_temp.ok('11.06 ciclo 100: 22023; el operario no toca el calendario: 42501',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 100, %L::date, %L::date)', S, to_char(v_hoy, 'YYYYMM'), v_hoy, v_hoy))) = '22023'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_calendario_guardar(%L, %L, 96, %L::date, %L::date)', 'ztscrr.op@emdupar.gov.co', to_char(v_hoy, 'YYYYMM'), v_hoy, v_hoy))) = '42501');

  -- ===== 12. Contratos con control y excluidos manuales =====
  r := pg_temp.rpc(format('public.geoportal_scrr_control_agregar(%L, %L, %L, %L)', S, (B + 103)::text, 'insolvencia', 'ZTSCRR proceso de insolvencia'));
  perform pg_temp.ok('12.01 alta de control (insolvencia) con motivo', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.ok('12.02 la misma alta otra vez: 55000; sin motivo: 22023; el comodín: 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_control_agregar(%L, %L, %L, %L)', S, (B + 103)::text, 'insolvencia', 'ZTSCRR proceso de insolvencia'))) = '55000'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_control_agregar(%L, %L, %L, %L)', S, (B + 104)::text, 'insolvencia', 'corto'))) = '22023'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_control_agregar(%L, %L, %L, %L)', S, '99999999', 'insolvencia', 'ZTSCRR el comodín no es un contrato'))) = '22023');
  r := pg_temp.rpc(format('public.geoportal_scrr_control_agregar(%L, %L, %L, %L)', S, (B + 105)::text, 'reclamo_manual', 'ZTSCRR reclamo que no está en el sistema'));
  r := pg_temp.rpc(format('public.geoportal_scrr_control_lote(%L, %L::jsonb, %L, %L)', S, jsonb_build_array((B + 108)::text, (B + 108)::text, 'x12', '99999999', (B + 130)::text), 'excluido_manual', 'ZTSCRR excluidos por decisión del supervisor'));
  perform pg_temp.ok('12.03 excluidos por archivo con un motivo común (P10): 5 recibidos, 2 no válidos (texto y comodín), 2 nuevos (el repetido cuenta una vez)',
    pg_temp.err(r) = 'OK' and (r ->> 'recibidos')::int = 5 and (r ->> 'no_validos')::int = 2 and (r ->> 'repetidos_en_el_archivo')::int = 1 and (r ->> 'nuevos')::int = 2 and (r ->> 'ya_estaban')::int = 0
    and (select count(*) from scrr.control_eventos where contrato in (B + 108, B + 130) and origen = 'archivo') = 2, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_control_baja(%L, %L, %L, %L)', S, (B + 130)::text, 'excluido_manual', 'ZTSCRR vuelve a ser elegible'));
  perform pg_temp.ok('12.04 baja con motivo: el contrato sale de la lista y queda el historial (alta y baja)',
    pg_temp.err(r) = 'OK' and not exists (select 1 from scrr.v_control_vigente where contrato = B + 130) and (select count(*) from scrr.control_eventos where contrato = B + 130) = 2, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_control_lista(%L, %L)', S, 'excluido'));
  perform pg_temp.ok('12.05 la lista de excluidos trae a B+108 y no a los de control; la de control trae insolvencia y reclamo manual',
    exists (select 1 from jsonb_array_elements(r -> 'vigentes') x where (x ->> 'contrato')::bigint = B + 108)
    and not exists (select 1 from jsonb_array_elements(r -> 'vigentes') x where (x ->> 'contrato')::bigint = B + 103)
    and (select count(*) from jsonb_array_elements(pg_temp.rpc(format('public.geoportal_scrr_control_lista(%L, %L)', S, 'control')) -> 'vigentes') x where (x ->> 'contrato')::bigint in (B + 103, B + 105)) = 2, r::text);

  -- ===== 13. Selección: una foto de cartera VIGENTE de prueba (sin tocar cartera_suscripcion), ciclo 98 =====
  ca := gen_random_uuid()::text;
  insert into scrr.cargas (id, tipo, fecha_dato, version, archivo_nombre, archivo_sha256, filas_leidas, autor)
    values (ca::uuid, 'cartera', v_hoy, (select max(version) + 1 from scrr.cargas where tipo = 'cartera' and fecha_dato = v_hoy), 'ztscrr_foto.xlsx', pg_temp.sha('foto'), 20, S);
  insert into scrr.carga_eventos (carga_id, evento, autor) values (ca::uuid, 'iniciada', S), (ca::uuid, 'aplicada', S);
  insert into scrr.barrios (nombre_norm) values ('ZTSCRR NORTE'), ('ZTSCRR SUR') on conflict do nothing;
  insert into scrr.cartera_historial (fecha_dato, version, contrato, en_cartera, marca, ciclo, ruta, codigo_reparto, barrio_id, facturas_pendientes, facturas_vencidas, deuda_total, saldo_pendiente, valor_reclamo, carga_id)
  select v_hoy, (select version from scrr.cargas where id = ca::uuid), B + n, n <> 120, case when n = 101 then 1 else 0 end, 98,
         case when n = 102 then 'ZTR1' else 'ZTR' || (n % 3) end, 'P' || n, (select id from scrr.barrios where nombre_norm = case when n = 112 then 'ZTSCRR SUR' else 'ZTSCRR NORTE' end),
         venc + 1, venc, sal + 1000, case when n = 120 then 0 else sal end, case when n = 104 then 5000 else 0 end, ca::uuid
    from (values (101, 3, 30000), (102, 3, 30000), (103, 3, 30000), (104, 3, 30000), (105, 3, 30000), (106, 3, 30000), (107, 3, 30000), (108, 3, 30000),
                 (109, 3, 3000), (110, 30, 30000), (111, 1, 20000), (112, 2, 21000), (113, 3, 22000), (114, 4, 23000), (115, 5, 24000), (120, 0, 0)) z(n, venc, sal);
  insert into scrr.cartera_historial (fecha_dato, version, contrato, ciclo, ruta, facturas_pendientes, facturas_vencidas, deuda_total, saldo_pendiente, carga_id)
    values (v_hoy, (select version from scrr.cargas where id = ca::uuid), B + 201, 99, 'ZTR', 4, 3, 40000, 40000, ca::uuid);
  -- facturados: todos menos B+102 (en el último período de hechos.facturacion_sspd)
  insert into hechos.facturacion_sspd (periodo, contrato)
    select coalesce((select max(periodo) from hechos.facturacion_sspd), to_char(v_hoy, 'YYYYMM')), (B + n)::text from generate_series(101, 201) n where n <> 102;
  -- pagos: B+106 pagó hoy todo su saldo (pago sin reflejar); B+111 abonó 1.000 hoy
  insert into scrr.pagos_contrato (contrato, fecha_pago, monto, ordinal, carga_id) values (B + 106, v_hoy, 30000, 1, ca::uuid), (B + 111, v_hoy, 1000, 1, ca::uuid);
  -- evento de suspensión de agua sobre B+107 (solo donde existe el doble local de Técnica; en producción no se toca)
  if to_regclass('redes.zz_doble_eventos_contrato') is not null then insert into redes.zz_doble_eventos_contrato values ((B + 107)::text, 1); end if;
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_previa(%L, 98, %L::jsonb)', S, '{"modo": "meses", "desde": 1, "hasta": 25}'));
  perform pg_temp.ok('13.01 embudo en su orden: comodín 1, no facturado 1, control 1, reclamo 2 (valor y manual), pago sin reflejar 1, excluido manual 1, saldo menor al mínimo 1, fuera del rango 1',
    pg_temp.err(r) = 'OK' and (r -> 'embudo' -> 'p0_comodin' ->> 'contratos')::int = 1 and (r -> 'embudo' -> 'p1_no_facturado_o_sin_ruta' ->> 'contratos')::int = 1
    and (r -> 'embudo' -> 'p2_control_vigente' ->> 'contratos')::int = 1 and (r -> 'embudo' -> 'p3_reclamo' ->> 'contratos')::int = 2
    and (r -> 'embudo' -> 'p4_pago_sin_reflejar' ->> 'contratos')::int = 1 and (r -> 'embudo' -> 'p6_excluido_manual' ->> 'contratos')::int = 1
    and (r -> 'embudo' -> 'p7_saldo_menor_al_minimo' ->> 'contratos')::int = 1 and (r -> 'embudo' -> 'f_fuera_del_rango' ->> 'contratos')::int = 1, r::text);
  v_esperado_bloqueo := to_regclass('redes.zz_doble_eventos_contrato') is not null;   -- aquí: ¿hay evento de prueba?
  perform pg_temp.ok('13.02 evento de suspensión de agua: el contrato dentro del evento SALE de la lista (o es candidato donde no hay evento)',
    coalesce((r -> 'embudo' -> 'p5_evento_suspension_agua' ->> 'contratos')::int, 0) = case when v_esperado_bloqueo then 1 else 0 end
    and (r ->> 'candidatos')::int = case when v_esperado_bloqueo then 5 else 6 end, r::text);
  perform pg_temp.ok('13.03 paz y salvo hoy se cuenta aparte (1); el abono de 1.000 MARCA y no excluye; el otro ciclo no se mezcla',
    (r -> 'embudo' -> 'p4_paz_y_salvo_hoy' ->> 'contratos')::int = 1 and (r ->> 'marcados_abono')::int = 1 and (r ->> 'universo')::int = 15, r::text);
  perform pg_temp.ok('13.04 la vista previa queda en la auditoría solo con conteos (sin contratos)',
    exists (select 1 from public.geoportal_auditoria where email = S and accion = 'scrr_seleccion_previa' and referencia = '98' and not (detalle::text ~ '9100000001'))
  );
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_previa(%L, 98, %L::jsonb)', S, jsonb_build_object('modo', 'meses', 'desde', 1, 'hasta', 25, 'barrio_id', (select id from scrr.barrios where nombre_norm = 'ZTSCRR SUR'))));
  perform pg_temp.ok('13.05 filtro de barrio: solo B+112', (r ->> 'candidatos')::int = 1, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_previa(%L, 98, %L::jsonb)', S, '{"modo": "monto", "desde": 22000, "hasta": 23500}'));
  perform pg_temp.ok('13.06 rango por monto: 22.000 a 23.500 → 2', (r ->> 'candidatos')::int = 2, r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_previa(%L, 98, %L::jsonb)', S, '{"modo": "meses", "desde": 1, "hasta": 25, "segmento": "menos_de_n", "n": 3}'));
  perform pg_temp.ok('13.07 segmento «menos de 3 vencidas» (aproximado): 2', (r ->> 'candidatos')::int = 2 and (r ->> 'segmentos_aproximados')::boolean, r::text);
  perform pg_temp.ok('13.08 el operario no ve la selección: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_seleccion_previa(%L, 98, %L::jsonb)', 'ztscrr.op@emdupar.gov.co', '{}'))) = '42501');
  perform pg_temp.ok('13.09 generar con una actividad que no se escoge (reinstalación): 22023',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_seleccion_generar(%L, 98, %L::jsonb, %L)', S, '{"modo": "meses", "desde": 1, "hasta": 25}', 'reinstalacion'))) = '22023');
  perform pg_temp.ok('13.10 generar sin candidatos: 55000',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_seleccion_generar(%L, 98, %L::jsonb, %L)', S, '{"modo": "meses", "desde": 20, "hasta": 25}', 'corte'))) = '55000');
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_generar(%L, 98, %L::jsonb, %L)', S, '{"modo": "meses", "desde": 1, "hasta": 25}', 'corte'));
  cp := r ->> 'corrida_id';
  perform pg_temp.ok('13.11 generar la corrida de Corte: guarda solo la lista (los candidatos), en orden de ruta y reparto, con la actividad',
    pg_temp.err(r) = 'OK' and (r ->> 'contratos')::int = case when v_esperado_bloqueo then 5 else 6 end
    and (select count(*) from scrr.corrida_contratos where corrida_id = cp::uuid) = (r ->> 'contratos')::int
    and (select string_agg(ruta, ',' order by orden) from scrr.corrida_contratos where corrida_id = cp::uuid) ~ '^(ZTR0,)*(ZTR1,?)*(ZTR2,?)*$'
    and (select t.codigo from scrr.corridas c join scrr.tipos_actividad t on t.id = c.actividad_id where c.id = cp::uuid) = 'corte', r::text);
  -- nombre y dirección para la lista (los resuelve la RPC de la cartera de suscripción; teléfono y correo NO salen)
  insert into public.cartera_suscripcion (contrato, nombre, direccion, telefono, correo, identificacion, barrio)
    select (B + n)::text, 'ZTSCRR NOMBRE ' || n, 'ZTSCRR CALLE ' || n, '3000000000', 'zt@ejemplo.invalid', 'ZTID' || n, 'ZTSCRR NORTE' from generate_series(111, 115) n;
  r := pg_temp.rpc(format('public.geoportal_scrr_lista(%L, %L::uuid, %L)', S, cp, 'excel'));
  perform pg_temp.ok('13.12 la lista lleva nombre y dirección (excepción P2), la deuda (P9) y la marca del abono; nunca teléfono, correo ni identificación',
    pg_temp.err(r) = 'OK' and (select x ->> 'nombre' = 'ZTSCRR NOMBRE 111' and x ->> 'direccion' = 'ZTSCRR CALLE 111' and (x ->> 'saldo_pendiente')::numeric = 20000
                                and x ->> 'marca' like 'Abonó%' from jsonb_array_elements(r -> 'filas') x where (x ->> 'contrato')::bigint = B + 111)
    and not (r::text ~ '3000000000|ejemplo\.invalid|ZTID'), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_lista(%L, %L::uuid, %L)', S, cp, 'impresion'));
  perform pg_temp.ok('13.13 cada descarga e impresión queda en la auditoría con sus filas',
    (select count(*) from public.geoportal_auditoria where referencia = cp and accion in ('scrr_lista_excel', 'scrr_lista_impresion')) = 2
    and exists (select 1 from public.geoportal_auditoria where referencia = cp and accion = 'scrr_corrida'));
  perform pg_temp.ok('13.14 el operario no descarga listas: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_lista(%L, %L::uuid, %L)', 'ztscrr.op@emdupar.gov.co', cp, 'excel'))) = '42501');
  r := pg_temp.rpc(format('public.geoportal_scrr_corridas(%L)', S));
  perform pg_temp.ok('13.15 la corrida aparece en la lista de corridas con su actividad', exists (select 1 from jsonb_array_elements(r -> 'corridas') x where x ->> 'corrida_id' = cp and x ->> 'actividad' = 'Corte'), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_seleccion_opciones(%L, 98)', S));
  perform pg_temp.ok('13.16 opciones: los ciclos del período con su ventana y los barrios del ciclo (dependen del ciclo)',
    (select count(*) from jsonb_array_elements(r -> 'barrios') x where x ->> 'nombre' like 'ZTSCRR%') = 2
    and exists (select 1 from jsonb_array_elements(r -> 'ciclos') x where (x ->> 'ciclo')::int = 98 and (x ->> 'en_ventana')::boolean), r::text);

  -- ===== 14. Refresco del mapa comercial (las RPC que lo rodean; el REFRESH lo corre la Edge con el rol scrr_refresco) =====
  perform pg_temp.ok('14.01 iniciar el refresco con una carga de pagos: P0002',
    pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_refresco_iniciar(%L, %L::uuid)', S, (select id from scrr.cargas where tipo = 'pagos' and autor = S limit 1)))) = 'P0002');
  r := pg_temp.rpc(format('public.geoportal_scrr_refresco_iniciar(%L, %L::uuid)', S, ca));
  perform pg_temp.ok('14.02 con una carga de cartera aplicada: autoriza y lo deja en la auditoría', pg_temp.err(r) = 'OK'
    and exists (select 1 from public.geoportal_auditoria where accion = 'scrr_refresco_mapa_inicio' and referencia = ca), r::text);
  r := pg_temp.rpc(format('public.geoportal_scrr_refresco_cerrar(%L, %L::uuid, %L, 650)', S, ca, 'ok'));
  perform pg_temp.ok('14.03 cerrar con el resultado y el tiempo; un resultado desconocido: 22023', pg_temp.err(r) = 'OK'
    and pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_refresco_cerrar(%L, %L::uuid, %L, 1)', S, ca, 'quizas'))) = '22023', r::text);
  perform pg_temp.ok('14.04 el operario no pide el refresco: 42501', pg_temp.err(pg_temp.rpc(format('public.geoportal_scrr_refresco_iniciar(%L, %L::uuid)', 'ztscrr.op@emdupar.gov.co', ca))) = '42501');
  perform pg_temp.ok('14.05 el rol scrr_refresco: sin login, sin superusuario, solo MAINTAIN sobre predios_comercial (no la lee ni lee la cartera)',
    (select not rolcanlogin and not rolsuper and not rolcreaterole and not rolinherit from pg_roles where rolname = 'scrr_refresco')
    and has_table_privilege('scrr_refresco', 'public.predios_comercial', 'MAINTAIN') and not has_table_privilege('scrr_refresco', 'public.predios_comercial', 'SELECT')
    and not has_table_privilege('scrr_refresco', 'public.cartera_suscripcion', 'SELECT'));

  -- ===== 15. Actividades fuera de las listas y ajuste inicial (David, 22-nov 20:45) =====
  r := pg_temp.iniciar('actividades', v_hoy - 2, pg_temp.sha('act3'), 3);
  ca := r ->> 'carga_id';
  perform pg_temp.lote(ca, 1, jsonb_build_array(
    jsonb_build_object('contrato', (B + 111)::text, 'actividad', 'Corte', 'drastico', 'NO', 'estado', '3', 'fecha', v_hoy::text),
    jsonb_build_object('contrato', (B + 150)::text, 'actividad', 'Suspensión', 'drastico', 'NO', 'estado', '3', 'fecha', v_hoy::text),
    jsonb_build_object('contrato', (B + 151)::text, 'actividad', 'Corte', 'drastico', 'SÍ', 'estado', '3', 'fecha', '2025-12-01')));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_validar(%L, %L::uuid)', S, ca));
  perform pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid, 1)', S, ca));
  r := pg_temp.rpc(format('public.geoportal_scrr_carga_aplicar(%L, %L::uuid)', S, ca));
  perform pg_temp.ok('15.01 la carga de actividades no exige lista: 3 actas, 1 de la lista de Corte y 2 fuera de las listas',
    pg_temp.err(r) = 'OK' and (r -> 'resultado' ->> 'actas_nuevas')::int = 3 and (r -> 'resultado' ->> 'actas_de_una_lista')::int = 1
    and (r -> 'resultado' ->> 'actas_fuera_de_las_listas')::int = 2, r::text);
  perform pg_temp.ok('15.02 el acta de B+111 queda enlazada a su corrida; las otras, sin corrida (marcadas fuera de las listas)',
    (select corrida_id = cp::uuid from scrr.actas where contrato = B + 111 and carga_id = ca::uuid)
    and (select count(*) from scrr.actas where contrato in (B + 150, B + 151) and carga_id = ca::uuid and corrida_id is null) = 2);
  perform pg_temp.ok('15.03 ajuste inicial: un corte drástico de 2025 fuera de las listas actualiza igual el estado del servicio; la suspensión de hoy también',
    (select estado from scrr.v_estado_servicio where contrato = B + 151) = 'cortado_drastico' and (select estado from scrr.v_estado_servicio where contrato = B + 150) = 'suspendido');

  -- ===== 10. Estructura, permisos y reglas de producción =====
  perform pg_temp.ok('10.01 historial en particiones diarias (hoy existe) y pagos en mensuales',
    to_regclass('scrr.cartera_historial_' || to_char(v_hoy, 'YYYYMMDD')) is not null and to_regclass('scrr.pagos_contrato_' || to_char(v_hoy, 'YYYYMM')) is not null);
  perform pg_temp.ok('10.02 service_role ejecuta las RPC; anon y authenticated no',
    (select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute'))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_scrr\_%'));
  perform pg_temp.ok('10.03 nadie más que el dueño ejecuta funciones de scrr (incluida f_retirar_historial)',
    not exists (select 1 from pg_proc p where p.pronamespace = 'scrr'::regnamespace
                  and (has_function_privilege('service_role', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
  perform pg_temp.ok('10.04 ninguna tabla de scrr (ni sus particiones) se lee como anon, authenticated o service_role',
    not exists (select 1 from pg_class c where c.relnamespace = 'scrr'::regnamespace and c.relkind in ('r','p','v')
                  and (has_table_privilege('service_role', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select') or has_table_privilege('anon', c.oid, 'select'))));
  perform pg_temp.ok('10.05 ninguna función de scrr con DELETE o UPDATE sin WHERE', (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = to_regnamespace('scrr') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_scrr\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\m(where|using)\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0);
  perform pg_temp.ok('10.06 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
  perform pg_temp.ok('10.07 las 4 funciones de permisos no cambiaron', not exists (select 1 from ztscrr_permisos z where md5(pg_get_functiondef(to_regprocedure(z.f))) is distinct from z.md5));
end $$;

-- Resultado: termina SIEMPRE en un ERROR (deshace todo). «N de N … SIN FALLAS» es el éxito.
do $$
declare v_tot int; v_ok int; v_fallas text;
begin
  select count(*), count(*) filter (where ok), string_agg(format('%s — %s', nombre, coalesce(detalle, '')), E'\n' order by n) filter (where not ok) into v_tot, v_ok, v_fallas from ztscrr_res;
  if v_ok = v_tot then
    raise exception 'RESULTADO: % de % pruebas correctas — SIN FALLAS (este ERROR es el esperado: deshace todo)', v_ok, v_tot;
  else
    raise exception 'RESULTADO: % de % pruebas correctas — FALLAS:%', v_ok, v_tot, E'\n' || v_fallas;
  end if;
end $$;

rollback;
