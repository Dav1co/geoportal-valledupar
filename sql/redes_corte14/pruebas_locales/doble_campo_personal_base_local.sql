-- DOBLE LOCAL (solo para las pruebas de Code B; NO se corre en producción): lo mínimo del esquema «campo» que toca el Corte 14.
-- · campo.personal_eventos y campo.f_formularios_personal van con el TEXTO EXACTO del paquete publicado (campo/paquete_pasada_14nov/campo_sql/sql/40_personal.sql),
--   para que la guardia md5 y el CHECK sean los de producción (regla de David, 17-nov: los dobles llevan los CHECK, las llaves y los disparadores de producción).
-- · Las tablas del catálogo (tipos, grupos, campos y fotos) llevan solo las columnas que lee esa función.
create schema campo;
revoke all on schema campo from public;
create function campo.f_solo_agregar() returns trigger language plpgsql as $$ begin raise exception 'Esta tabla es de solo agregar' using errcode = '42501'; end $$;
create table campo.grupos_reporte (id bigint generated always as identity primary key, codigo text not null unique, nombre text not null, orden integer not null default 0, activo boolean not null default true);
create table campo.tipos_reporte (id bigint generated always as identity primary key, grupo_id bigint not null references campo.grupos_reporte (id), codigo text not null unique, nombre text not null,
  orden integer not null default 0, activo boolean not null default true, genera_resultado boolean not null default false, prefijo_consecutivo text);
create table campo.tipo_campos (id bigint generated always as identity primary key, tipo_id bigint not null references campo.tipos_reporte (id), activo boolean not null default true);
create table campo.tipo_fotos (id bigint generated always as identity primary key, tipo_id bigint not null references campo.tipos_reporte (id), activo boolean not null default true);
insert into campo.grupos_reporte (codigo, nombre, orden) values ('suspension', 'Suspensión y corte', 1), ('red_acueducto', 'Red de acueducto', 2);
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, genera_resultado) values (1, 'suspension', 'Suspensión del servicio', 1, true), (2, 'fuga_acometida', 'Fuga en acometida', 1, false);
revoke all on all tables in schema campo from public, anon, authenticated, service_role;

create table if not exists campo.personal_eventos (
  id           bigint generated always as identity primary key,
  persona      text not null check (persona = lower(persona) and position('@' in persona) > 1),
  tipo_evento  text not null check (tipo_evento in ('fijar_cargo', 'asignar_formulario', 'quitar_formulario')),
  formulario   text check (formulario is null or formulario ~ '^(reporte_general|acta|tipo:[a-z][a-z0-9_]{1,59})$'),
  cargo        text check (cargo is null or length(btrim(cargo)) between 2 and 80),
  motivo       text check (motivo is null or length(btrim(motivo)) between 10 and 300),
  autor        text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en    timestamptz not null default clock_timestamp(),
  constraint personal_ev_ck check (((tipo_evento = 'fijar_cargo') = (cargo is not null)) and ((tipo_evento = 'fijar_cargo') = (formulario is null))
                                   and (tipo_evento <> 'quitar_formulario' or motivo is not null))
);
comment on table campo.personal_eventos is 'Pasada 14/11: cargo y formularios asignados del personal de Comercial (campo y acta). Solo agregar. En este corte las asignaciones SOLO se registran (no restringen la captura).';
create index if not exists personal_eventos_persona_idx on campo.personal_eventos (persona, id desc);
alter table campo.personal_eventos enable row level security;
create or replace trigger t_solo_agregar before update or delete on campo.personal_eventos for each row execute function campo.f_solo_agregar();
create or replace trigger t_solo_agregar_trunc before truncate on campo.personal_eventos for each statement execute function campo.f_solo_agregar();
revoke all on table campo.personal_eventos from public, anon, authenticated, service_role;
revoke all on sequence campo.personal_eventos_id_seq from public, anon, authenticated, service_role;

-- Formularios que se pueden asignar: «Reportar anomalía» (reporte general), cada formato de actividad ACTIVO y «Reportar posible pérdida» (acta).
-- Un tipo es «formato de actividad» con la misma regla de la pantalla (esFormatoD): tiene campos o fotos activos, genera resultado o lleva consecutivo.
create or replace function campo.f_formularios_personal() returns table (clave text, nombre text, grupo text, orden integer)
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select 'reporte_general', 'Reportar anomalía', 'Reportar anomalía', 0
  union all
  select 'tipo:' || t.codigo, t.nombre, g.nombre, (1000 + g.orden * 1000 + t.orden)::integer
    from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where t.activo and g.activo
     and (exists (select 1 from campo.tipo_campos c where c.tipo_id = t.id and c.activo) or exists (select 1 from campo.tipo_fotos f where f.tipo_id = t.id and f.activo)
          or t.genera_resultado or t.prefijo_consecutivo is not null)
  union all
  select 'acta', 'Reportar posible pérdida', 'Reportar posible pérdida', 2000000000
$$;
create or replace function campo.f_cargo_vigente(p_email text) returns text
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select e.cargo from campo.personal_eventos e where e.persona = lower(p_email) and e.tipo_evento = 'fijar_cargo' order by e.id desc limit 1
$$;
create or replace function campo.f_formularios_asignados(p_email text) returns text[]
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select coalesce(array_agg(u.formulario order by u.formulario), '{}') from (
    select distinct on (e.formulario) e.formulario, e.tipo_evento from campo.personal_eventos e
     where e.persona = lower(p_email) and e.tipo_evento in ('asignar_formulario', 'quitar_formulario') order by e.formulario, e.id desc) u
   where u.tipo_evento = 'asignar_formulario'
$$;
revoke all on function campo.f_formularios_personal(), campo.f_cargo_vigente(text), campo.f_formularios_asignados(text) from public, anon, authenticated;
