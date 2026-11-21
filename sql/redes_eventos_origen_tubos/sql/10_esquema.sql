-- =====================================================================
-- TÉCNICA · FASE 1 · EVENTOS: ORIGEN OBLIGATORIO Y SECTORES POR TUBO DE SALIDA · 10 — GUARDIA, ESQUEMA Y DATOS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Encargo y decisiones de David del 20-nov (eventos_origen_tubos/ENTRADA_BITACORA.md y DECISION_VIGENTE.md):
-- · ORIGEN: al declarar, un daño o una intervención (lo de hoy) O un trabajo con su causal de catálogo; la observación (el campo «causa») sigue obligatoria.
--   El origen se DERIVA: daño, intervención, causal o «No registrado (anterior al cambio)». Nada viejo se completa.
-- · TUBOS: los sectores se asignan a los tubos de salida (tecnica.puntos tipo «distribucion»), no a las plantas. Un evento «por tubo» se guarda como un
--   evento POR SECTORES (alcance «sectores»: evento_contrato, el aviso «sin agua», el SCRR, los disparadores y el bot no cambian) y se anota de qué tubos salió.
-- · PLANTA: el sistema es único; un evento de planta nuevo cubre toda la ciudad. Las filas de redes.planta_sectores NO se borran: se desactivan con motivo.
-- Exige la huella de redes publicada 3f3c89e603629d92e1cc5065de33d0c1 (reportes del PTAP y descargas de Distribución, 20-nov 21:08) y las 3 funciones de técnica que reemplaza.
-- =====================================================================
do $$
begin
  if to_regclass('redes.evento_causales') is not null or to_regclass('redes.tubo_sectores') is not null then
    raise exception 'El corte de eventos (origen y tubos) ya está aplicado: deténgase y avise';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '3f3c89e603629d92e1cc5065de33d0c1' then
    raise exception 'Las funciones de redes no son las publicadas (huella 3f3c89e603629d92e1cc5065de33d0c1): deténgase y avise';
  end if;
  if (select count(*) from (values ('tecnica.f_rep_columnas(text,jsonb)', 'd178a29b3e4408b96b07bbaeae20f476'), ('tecnica.f_rep_eventos_planta(jsonb,boolean,timestamp with time zone,text,integer)', '5b97ed0684b94b94c14ec420aa1c212a'), ('tecnica.f_rep_leame(text,jsonb,boolean,text,timestamp with time zone)', '5f894b795ad896a7cc965b3ec5d37745')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 3 then
    raise exception 'Las funciones de los reportes del PTAP que este paquete reemplaza no son las publicadas: deténgase y avise';
  end if;
  if to_regclass('redes.planta_sectores') is null or to_regclass('redes.planta_sector_eventos') is null or to_regclass('tecnica.puntos') is null
     or not exists (select 1 from pg_constraint where conrelid = 'tecnica.puntos'::regclass and pg_get_constraintdef(oid) like '%distribucion%') then
    raise exception 'Faltan los sectores por planta del Corte 15 o los puntos de distribución de técnica: deténgase y avise';
  end if;
end $$;

-- ---------- 1. Causales de un evento declarado como trabajo (catálogo ajustable con historial) ----------
create table redes.evento_causales (
  codigo text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,39}$'),
  nombre text not null unique check (length(btrim(nombre)) between 3 and 80),
  activa boolean not null default true,
  orden  integer not null default 50
);
create table redes.evento_causal_eventos (
  id bigint generated always as identity primary key,
  codigo text not null references redes.evento_causales (codigo),
  accion text not null check (accion in ('crear', 'cambiar')),
  nombre text not null, activa boolean not null,
  motivo text not null check (length(btrim(motivo)) between 10 and 500), autor text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp()
);
-- la causal de cada evento declarado como trabajo (una por evento; solo inserción)
create table redes.evento_causal (
  evento_id bigint primary key references redes.eventos_suspension (id),
  causal    text not null references redes.evento_causales (codigo),
  creado_en timestamptz not null default clock_timestamp()
);
-- ---------- 2. Tubos de salida → sectores (como planta → sectores, con historial) y de qué tubos salió cada evento ----------
create table redes.tubo_sectores (
  punto_id  bigint not null references tecnica.puntos (id),
  sector_id bigint not null references redes.activos (id),
  activo    boolean not null default true,
  primary key (punto_id, sector_id)
);
create table redes.tubo_sector_eventos (
  id bigint generated always as identity primary key, punto_id bigint not null references tecnica.puntos (id), sectores bigint[] not null,
  motivo text not null check (length(btrim(motivo)) between 10 and 500), autor text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp()
);
create table redes.evento_tubos (
  evento_id bigint not null references redes.eventos_suspension (id),
  punto_id  bigint not null references tecnica.puntos (id),
  primary key (evento_id, punto_id)
);
-- un tubo es un punto de tipo «distribucion» (la llave foránea no lo puede decir)
create function redes.f_tubo_es_distribucion() returns trigger language plpgsql set search_path to 'redes', 'tecnica', 'pg_temp' as $$
begin
  if not exists (select 1 from tecnica.puntos p where p.id = new.punto_id and p.tipo = 'distribucion') then
    raise exception 'Ese punto no es un tubo de salida (tipo distribución)' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t_tubo_es_distribucion before insert or update on redes.tubo_sectores for each row execute function redes.f_tubo_es_distribucion();
create trigger t_tubo_es_distribucion before insert or update on redes.tubo_sector_eventos for each row execute function redes.f_tubo_es_distribucion();
create trigger t_tubo_es_distribucion before insert or update on redes.evento_tubos for each row execute function redes.f_tubo_es_distribucion();
comment on table redes.tubo_sectores is 'Sectores y subsectores que abastece cada tubo de salida (tecnica.puntos tipo distribucion). Arranca vacía: la llena el administrador o el supervisor de distribución (David, 20-nov).';
comment on table redes.evento_tubos is 'De qué tubos de salida se declaró un evento «por tubo» (el evento queda por sectores).';
comment on table redes.evento_causal is 'La causal de catálogo de un evento declarado como trabajo o actividad (no por un daño ni una intervención).';

do $$
declare v_t text;
begin
  foreach v_t in array array['evento_causales', 'evento_causal_eventos', 'evento_causal', 'tubo_sectores', 'tubo_sector_eventos', 'evento_tubos'] loop
    execute format('alter table redes.%I enable row level security', v_t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', v_t);
  end loop;
  foreach v_t in array array['evento_causal_eventos', 'evento_causal', 'tubo_sector_eventos', 'evento_tubos'] loop
    execute format('create trigger t_solo_agregar before delete or update on redes.%I for each row execute function tecnica.f_solo_agregar()', v_t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', v_t);
  end loop;
end $$;
revoke all on sequence redes.evento_causal_eventos_id_seq, redes.tubo_sector_eventos_id_seq from public, anon, authenticated, service_role;
revoke all on function redes.f_tubo_es_distribucion() from public, anon, authenticated, service_role;

-- ---------- 3. Las causales de David (20-nov) ----------
insert into redes.evento_causales (codigo, nombre, orden) values
  ('trabajo_programado', 'Trabajo programado en redes', 1),
  ('parametros_entrada', 'Parámetros de entrada que impiden operar', 2),
  ('falla_planta', 'Falla en la planta', 3),
  ('mantenimiento_planta', 'Limpieza o mantenimiento de planta', 4),
  ('otra', 'Otra', 9);

-- ---------- 4. Planta → sectores: se DESACTIVAN (no se borran), con un hecho por planta y el motivo de David ----------
insert into redes.planta_sector_eventos (planta_id, sectores, motivo, autor)
select distinct ps.planta_id, '{}'::bigint[], 'el sistema es único; los sectores pasan a los tubos de salida', 'migracion@redes_eventos_origen_tubos'
  from redes.planta_sectores ps where ps.activo;
update redes.planta_sectores set activo = false where activo;
