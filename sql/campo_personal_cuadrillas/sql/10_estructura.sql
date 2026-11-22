-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 10 — ESTRUCTURA
-- Catálogos de áreas y de actividades (los edita el administrador), cuadrillas (las crea el supervisor de campo) y sus eventos, y cuatro eventos nuevos en
-- campo.personal_eventos (fijar_area, fijar_cuadrilla, asignar_actividad, quitar_actividad). Nada se borra: los catálogos y las cuadrillas se desactivan;
-- los eventos son de solo agregar. Decisiones de David del 21-nov: D1 (en campo; reemplaza el diseño trabajo.* de SCRR fase 0), D2 (áreas), D3, D4.
-- =====================================================================

-- Disparador de «no se borra» para las tablas que sí se actualizan (nombre, activa, orden): impide DELETE y TRUNCATE, y que cambie la llave.
create function campo.f_no_borrar_catalogo() returns trigger
language plpgsql set search_path to 'pg_catalog' as $$
begin
  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception 'En %.% no se borra: se desactiva con motivo', tg_table_schema, tg_table_name using errcode = '42501';
  end if;
  if (to_jsonb(new) -> 'codigo') is distinct from (to_jsonb(old) -> 'codigo') or (to_jsonb(new) -> 'id') is distinct from (to_jsonb(old) -> 'id')
     or (to_jsonb(new) -> 'creado_en') is distinct from (to_jsonb(old) -> 'creado_en') or (to_jsonb(new) -> 'autor') is distinct from (to_jsonb(old) -> 'autor') then
    raise exception 'En %.% no cambian el código, el id, el autor ni la fecha de creación', tg_table_schema, tg_table_name using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function campo.f_no_borrar_catalogo() from public, anon, authenticated, service_role;

-- ---------- 1. Catálogos ----------
create table campo.areas_comercial (
  codigo     text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,39}$'),
  nombre     text not null check (length(btrim(nombre)) between 2 and 60 and nombre = btrim(nombre)),
  activa     boolean not null default true,
  orden      integer not null check (orden between 0 and 100000),
  autor      text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en  timestamptz not null default clock_timestamp()
);
create unique index areas_comercial_nombre_uk on campo.areas_comercial (lower(nombre));
comment on table campo.areas_comercial is 'Comercial 21-nov (D2): áreas de Comercial para la ficha de Personal. Las edita el administrador; no se borran (se desactivan con motivo, ver campo.catalogo_eventos).';

create table campo.actividades (
  codigo       text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,39}$'),
  nombre       text not null check (length(btrim(nombre)) between 2 and 60 and nombre = btrim(nombre)),
  activa       boolean not null default true,
  orden        integer not null check (orden between 0 and 100000),
  formularios  text[] not null default '{}' check (cardinality(formularios) <= 10 and array_to_string(formularios, ',') !~ '[^a-z0-9_:,]'),
  autor        text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en    timestamptz not null default clock_timestamp()
);
create unique index actividades_nombre_uk on campo.actividades (lower(nombre));
comment on table campo.actividades is 'Comercial 21-nov (D3, D4): actividades que hace el personal de Comercial (SCRR, lectura, reparto, revisiones, instalaciones…). Las asigna el supervisor a una cuadrilla o a una persona; hoy SOLO se registran (no restringen la captura). «formularios» = claves de campo.f_formularios_personal() que corresponden a la actividad (informativo). No se borran.';

create table campo.catalogo_eventos (
  id           bigint generated always as identity primary key,
  catalogo     text not null check (catalogo in ('area', 'actividad')),
  codigo       text not null check (codigo ~ '^[a-z][a-z0-9_]{1,39}$'),
  tipo_evento  text not null check (tipo_evento in ('crear', 'renombrar', 'desactivar', 'activar')),
  nombre       text check (nombre is null or length(btrim(nombre)) between 2 and 60),
  motivo       text check (motivo is null or length(btrim(motivo)) between 10 and 300),
  autor        text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en    timestamptz not null default clock_timestamp(),
  constraint catalogo_eventos_ck check ((tipo_evento in ('crear', 'renombrar')) = (nombre is not null) and (tipo_evento <> 'desactivar' or motivo is not null))
);
comment on table campo.catalogo_eventos is 'Comercial 21-nov: historial de los catálogos de áreas y de actividades. Solo agregar.';
create index catalogo_eventos_codigo_idx on campo.catalogo_eventos (catalogo, codigo, id desc);

-- ---------- 2. Cuadrillas ----------
create table campo.cuadrillas (
  id         bigint generated always as identity primary key,
  nombre     text not null check (length(btrim(nombre)) between 2 and 60 and nombre = btrim(nombre)),
  activa     boolean not null default true,
  autor      text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en  timestamptz not null default clock_timestamp()
);
create unique index cuadrillas_nombre_uk on campo.cuadrillas (lower(regexp_replace(nombre, '\s', '', 'g')));
comment on table campo.cuadrillas is 'Comercial 21-nov: cuadrillas del personal de Comercial. Las crea el supervisor de campo (o el administrador). Nombre único sin distinguir mayúsculas ni espacios. No se borran: se desactivan con motivo (y solo sin miembros).';

create table campo.cuadrilla_eventos (
  id            bigint generated always as identity primary key,
  cuadrilla_id  bigint not null references campo.cuadrillas (id),
  tipo_evento   text not null check (tipo_evento in ('crear', 'renombrar', 'desactivar', 'activar', 'agregar_actividad', 'quitar_actividad')),
  valor         text check (valor is null or length(btrim(valor)) between 2 and 60),
  motivo        text check (motivo is null or length(btrim(motivo)) between 10 and 300),
  autor         text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en     timestamptz not null default clock_timestamp(),
  constraint cuadrilla_eventos_ck check ((tipo_evento in ('crear', 'renombrar', 'agregar_actividad', 'quitar_actividad')) = (valor is not null)
                                         and (tipo_evento not in ('desactivar', 'quitar_actividad') or motivo is not null))
);
comment on table campo.cuadrilla_eventos is 'Comercial 21-nov: historial de cada cuadrilla (crear, renombrar, desactivar, activar) y de sus actividades (agregar o quitar; valor = código de la actividad). Lo vigente es el último evento de cada actividad. Solo agregar.';
create index cuadrilla_eventos_cuadrilla_idx on campo.cuadrilla_eventos (cuadrilla_id, id desc);

-- ---------- 3. Eventos nuevos de Personal ----------
alter table campo.personal_eventos add column valor text check (valor is null or valor ~ '^[a-z0-9_]{1,40}$');
comment on column campo.personal_eventos.valor is 'Comercial 21-nov: el código del área (fijar_area), el id de la cuadrilla (fijar_cuadrilla; nulo = sin cuadrilla) o el código de la actividad (asignar_actividad, quitar_actividad).';
alter table campo.personal_eventos drop constraint personal_eventos_tipo_evento_check;
alter table campo.personal_eventos add constraint personal_eventos_tipo_evento_check
  check (tipo_evento in ('fijar_cargo', 'asignar_formulario', 'quitar_formulario', 'fijar_area', 'fijar_cuadrilla', 'asignar_actividad', 'quitar_actividad'));
alter table campo.personal_eventos drop constraint personal_ev_ck;
alter table campo.personal_eventos add constraint personal_ev_ck
  check (((tipo_evento = 'fijar_cargo') = (cargo is not null))
         and ((tipo_evento in ('asignar_formulario', 'quitar_formulario')) = (formulario is not null))
         and (tipo_evento not in ('quitar_formulario', 'quitar_actividad') or motivo is not null)
         and (tipo_evento not in ('fijar_area', 'asignar_actividad', 'quitar_actividad') or valor is not null)
         and (tipo_evento in ('fijar_area', 'fijar_cuadrilla', 'asignar_actividad', 'quitar_actividad') or valor is null)
         and (tipo_evento <> 'fijar_cuadrilla' or valor is null or valor ~ '^[0-9]{1,18}$'));
create index personal_eventos_tipo_valor_idx on campo.personal_eventos (tipo_evento, valor) where valor is not null;

-- ---------- 4. Protección: no se borra; eventos de solo agregar; RLS y sin permisos por defecto ----------
create trigger t_no_borrar before update or delete on campo.areas_comercial for each row execute function campo.f_no_borrar_catalogo();
create trigger t_no_vaciar before truncate on campo.areas_comercial for each statement execute function campo.f_no_borrar_catalogo();
create trigger t_no_borrar before update or delete on campo.actividades for each row execute function campo.f_no_borrar_catalogo();
create trigger t_no_vaciar before truncate on campo.actividades for each statement execute function campo.f_no_borrar_catalogo();
create trigger t_no_borrar before update or delete on campo.cuadrillas for each row execute function campo.f_no_borrar_catalogo();
create trigger t_no_vaciar before truncate on campo.cuadrillas for each statement execute function campo.f_no_borrar_catalogo();
create trigger t_solo_agregar before update or delete on campo.catalogo_eventos for each row execute function campo.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on campo.catalogo_eventos for each statement execute function campo.f_solo_agregar();
create trigger t_solo_agregar before update or delete on campo.cuadrilla_eventos for each row execute function campo.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on campo.cuadrilla_eventos for each statement execute function campo.f_solo_agregar();
alter table campo.areas_comercial enable row level security;
alter table campo.actividades enable row level security;
alter table campo.catalogo_eventos enable row level security;
alter table campo.cuadrillas enable row level security;
alter table campo.cuadrilla_eventos enable row level security;
revoke all on table campo.areas_comercial, campo.actividades, campo.catalogo_eventos, campo.cuadrillas, campo.cuadrilla_eventos from public, anon, authenticated, service_role;
revoke all on sequence campo.catalogo_eventos_id_seq, campo.cuadrillas_id_seq, campo.cuadrilla_eventos_id_seq from public, anon, authenticated, service_role;

-- ---------- 5. Semilla (D2 y D4) ----------
insert into campo.areas_comercial (codigo, nombre, orden, autor) values
  ('facturacion', 'Facturación', 1, 'migracion@geoportal'),
  ('cartera_scrr', 'Cartera / SCRR', 2, 'migracion@geoportal'),
  ('perdidas', 'Pérdidas', 3, 'migracion@geoportal'),
  ('pqr_atencion', 'PQR / Atención al usuario', 4, 'migracion@geoportal');
insert into campo.actividades (codigo, nombre, orden, formularios, autor) values
  ('suspension', 'Suspensión', 1, '{tipo:suspension}', 'migracion@geoportal'),
  ('corte', 'Corte', 2, '{tipo:corte}', 'migracion@geoportal'),
  ('reconexion', 'Reconexión', 3, '{tipo:reconexion_servicio,tipo:reinstalacion}', 'migracion@geoportal'),
  ('lectura', 'Lectura', 4, '{}', 'migracion@geoportal'),
  ('reparto', 'Reparto', 5, '{}', 'migracion@geoportal'),
  ('revision_previa', 'Revisiones generales', 6, '{tipo:revision_previa}', 'migracion@geoportal'),
  ('revision_pqr', 'Revisión PQR', 7, '{tipo:revision_pqr}', 'migracion@geoportal'),
  ('instalacion_medidor', 'Instalación o cambio de medidor', 8, '{tipo:instalacion_medidor}', 'migracion@geoportal'),
  ('instalacion_acometida', 'Instalación de acometida', 9, '{tipo:instalacion_acometida}', 'migracion@geoportal'),
  ('posible_perdida', 'Posible pérdida (acta)', 10, '{acta}', 'migracion@geoportal');
-- y una por cada formato de actividad activo que no esté en la lista (mismo nombre del formato); se omite si el nombre ya existe
insert into campo.actividades (codigo, nombre, orden, formularios, autor)
select substr(x.clave, 6), left(btrim(x.nombre), 60), 100 + row_number() over (order by x.orden, x.clave), array[x.clave], 'migracion@geoportal'
  from campo.f_formularios_personal() x
 where x.clave like 'tipo:%' and length(btrim(x.nombre)) >= 2 and substr(x.clave, 6) ~ '^[a-z][a-z0-9_]{1,39}$'
   and not exists (select 1 from campo.actividades a where x.clave = any (a.formularios) or a.codigo = substr(x.clave, 6) or lower(a.nombre) = lower(btrim(x.nombre)));
insert into campo.catalogo_eventos (catalogo, codigo, tipo_evento, nombre, autor)
select 'area', codigo, 'crear', nombre, autor from campo.areas_comercial
union all
select 'actividad', codigo, 'crear', nombre, autor from campo.actividades;
