-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 10 — GUARDIA Y TABLAS NUEVAS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: §28 y §26.3 de la bitácora, pendientes 17c y 17f, 01 sección E (capa MUE) y §4 de hallazgos_capas_redes_15nov.md.
-- · Presupone el 4b aplicado (huella del conjunto de funciones de redes, de v_dano y de v_epicrisis, y de las 4 funciones de permisos del 4a).
-- · ⚠ tecnica.puntos está VIVA: este corte no la altera. Solo le AGREGA filas (puntos nuevos de una carga MUE) y cambia «activo» con un evento en
--   tecnica.punto_eventos; nunca borra. La ubicación va en la tabla lateral tecnica.puntos_ubicacion (D-24), de solo inserción.
-- · ⚠ tecnica.personal_tecnico_eventos está VIVA: no se altera; la RPC nueva del supervisor de distribución solo INSERTA eventos de asignar o quitar
--   los formularios de distribución, igual que las de planta (que no se tocan).
-- · ⚠ Se reemplazan 4 funciones del motor del 1a (vivas) y 5 RPC de los Cortes 4a y 4b, con su texto exacto en la reversa (guardia por la huella del conjunto).
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.personal_ficha_eventos') is null or to_regclass('redes.cuadrillas') is null then raise exception 'Falta el Corte 4b: aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_4B}}' then
    raise exception 'Las funciones de redes no son las del Corte 4b (o el Corte 5a ya está aplicado): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_dano'::regclass, true)) <> '{{MD5_V_DANO}}' or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> '{{MD5_V_EPICRISIS}}' then
    raise exception 'Las vistas v_dano o v_epicrisis no son las del 4b: deténgase y avise';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{VIVAS_4A}})) <> 4 then
    raise exception 'Las 4 funciones de permisos no son las del Corte 4a: deténgase y avise';
  end if;
  if to_regclass('tecnica.puntos_ubicacion') is not null or to_regclass('tecnica.punto_eventos') is not null or to_regclass('redes.formularios_distribucion') is not null
     or exists (select 1 from redes.capas where codigo = 'muestreo' and activa) then
    raise exception 'Las tablas del 5a o la capa «muestreo» ya existen: el Corte 5a parece aplicado';
  end if;
  -- lo vivo que se usa, con la forma esperada
  if (select count(*) from information_schema.columns where table_schema = 'tecnica' and table_name = 'puntos'
       and column_name in ('id', 'codigo', 'nombre', 'tipo', 'activo', 'zona', 'barrio', 'numero_informe')) <> 8 then
    raise exception 'tecnica.puntos no tiene las columnas esperadas (id, codigo, nombre, tipo, activo, zona, barrio, numero_informe): deténgase y avise';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'tecnica.puntos'::regclass and tgname = 't_no_borrar' and not tgisinternal) then
    raise exception 'tecnica.puntos no tiene su candado t_no_borrar: deténgase y avise';
  end if;
  if to_regclass('tecnica.senal_cambio') is null or to_regprocedure('tecnica.f_formulario_asignado(text,text)') is null then
    raise exception 'Faltan tecnica.senal_cambio o tecnica.f_formulario_asignado';
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'tecnica' and t.typname = 'formulario_clave') then
    raise exception 'Falta el dominio tecnica.formulario_clave';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. UBICACIÓN DE LOS PUNTOS DE MUESTREO (D-24): tabla lateral, solo inserción. La vigente es la última por punto que no sea de una carga revertida.
--    exactitud: verificada (David o GPS aprobado) o aproximada (centro del barrio). fuente: david, barrio, gps_operador (Corte 5b) o carga (archivo).
-- ---------------------------------------------------------------------
create table tecnica.puntos_ubicacion (
  id          bigint generated always as identity primary key,
  punto_id    bigint not null references tecnica.puntos (id),
  lat         numeric(9, 6) not null check (lat between -90 and 90),
  lon         numeric(9, 6) not null check (lon between -180 and 180),
  geom        geometry(Point, 4326) generated always as (ST_SetSRID(ST_MakePoint(lon::double precision, lat::double precision), 4326)) stored,
  exactitud   text not null check (exactitud in ('verificada', 'aproximada')),
  fuente      text not null check (fuente in ('david', 'barrio', 'gps_operador', 'carga')),
  barrio_capa text check (barrio_capa is null or length(btrim(barrio_capa)) between 1 and 120),
  carga_id    bigint references redes.cargas (id),
  autor       text not null,
  creado_en   timestamptz not null default clock_timestamp()
);
create index ix_pu_punto on tecnica.puntos_ubicacion (punto_id, id desc);
create index ix_pu_geom on tecnica.puntos_ubicacion using gist (geom);
comment on table tecnica.puntos_ubicacion is 'Ubicación de los puntos de tecnica.puntos (D-24). Solo inserción; la vigente es la última por punto que no sea de una carga revertida. La carga la capa MUE del Cargue de capas (Corte 5a).';

-- Eventos de los puntos que cambia una carga MUE: crear (punto nuevo), desactivar (no vino en la versión) y reactivar. Solo inserción.
create table tecnica.punto_eventos (
  id        bigint generated always as identity primary key,
  punto_id  bigint not null references tecnica.puntos (id),
  tipo      text not null check (tipo in ('crear', 'desactivar', 'reactivar')),
  motivo    text not null check (length(btrim(motivo)) between 10 and 1000),
  carga_id  bigint references redes.cargas (id),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
create index ix_pe_punto on tecnica.punto_eventos (punto_id, id desc);
comment on table tecnica.punto_eventos is 'Eventos de los puntos de muestreo que cambia la capa MUE (crear, desactivar, reactivar). Solo inserción. tecnica.puntos.activo sigue al último evento.';
do $$
declare t text;
begin
  foreach t in array array['puntos_ubicacion', 'punto_eventos'] loop
    execute format('create trigger t_solo_agregar before update or delete on tecnica.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on tecnica.%I for each statement execute function tecnica.f_solo_agregar()', t);
    execute format('alter table tecnica.%I enable row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2. FORMULARIOS DEL GRUPO DISTRIBUCIÓN (§28.2): los que el supervisor de distribución asigna desde Personal. El Corte 8 agrupa los formularios;
--    mientras tanto, esta lista. Se agregan filas; no se borran (se desactivan).
-- ---------------------------------------------------------------------
create table redes.formularios_distribucion (
  clave   tecnica.formulario_clave primary key,
  nombre  text not null check (length(btrim(nombre)) between 2 and 80),
  orden   integer not null default 0,
  activo  boolean not null default true
);
insert into redes.formularios_distribucion (clave, nombre, orden) values ('danos_fallas', 'Reportar daño o falla', 1), ('mantenimiento', 'Registrar intervención', 2);
create trigger t_no_borrar before delete on redes.formularios_distribucion for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on redes.formularios_distribucion for each statement execute function tecnica.f_solo_agregar();
alter table redes.formularios_distribucion enable row level security;

-- ---------------------------------------------------------------------
-- 3. CAPA MUE (01 sección E) y el tope de días atrás del supervisor (§28.1)
-- ---------------------------------------------------------------------
insert into redes.capas (codigo, nombre, grupo, sistema, geometria, prefijo, fuente, derivada_de, columna_llave, formatos, orden)
values ('muestreo', 'Puntos de muestreo de calidad del agua (MUE)', 'calidad_pqr', null, 'punto', null, 'carga', null, 'codigo', '{csv,xlsx,shp,geojson,kml}', 40)
on conflict (codigo) do update set activa = true;      -- si una reversa la dejó inactiva (las capas no se borran)
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('itv_dias_atras_max_supervisor', 30, 'días', 1, 90, 'Cuánto atrás puede empezar una intervención que registra el supervisor de distribución o el administrador (§28.1); el operador sigue con itv_dias_atras_max')
on conflict (clave) do nothing;      -- una reversa lo deja (los parámetros no se borran)
