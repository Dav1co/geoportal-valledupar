-- DOBLE LOCAL (solo pruebas; NO va en la migración): lo vivo de planta que el Corte 7a lee o amplía y que la base local no trae.
-- Copiado del paquete vivo «químicos y dosis» (paquete_quimicos_dosis/sql_dosis/10_migracion_dosis.sql): tecnica.quimicos con su candado y su semilla,
-- tecnica.uso_quimicos (la dosis en ppm, que el 7a no toca); plantas con «activa» y el caudal de Entrada (caudal_qi, por planta).
alter table tecnica.plantas add column if not exists activa boolean not null default true;
create table if not exists tecnica.quimicos (
  id bigint generated always as identity primary key, codigo text not null unique check (codigo ~ '^[a-z][a-z0-9_]{1,29}$'),
  nombre text not null check (length(btrim(nombre)) between 2 and 100), unidad_dosis text not null default 'ppm' check (unidad_dosis = 'ppm'),
  rol text not null check (rol in ('coagulante', 'desinfectante', 'otro')), pide_nombre boolean not null default false, activo boolean not null default true,
  creado_en timestamptz not null default clock_timestamp(), check (pide_nombre = (rol = 'otro')));
create table if not exists tecnica.uso_quimicos (id bigint generated always as identity primary key, lote_id uuid not null, origen text not null, tipo_uso text not null,
  quimico_id bigint not null references tecnica.quimicos (id), planta_id bigint not null references tecnica.plantas (id), dosis numeric not null, fecha_muestra date not null,
  hora_muestra time(0) not null, registrado_en timestamptz not null default clock_timestamp(), autor text not null);
create or replace function tecnica.f_quimico_protegido() returns trigger language plpgsql set search_path to 'pg_catalog', 'pg_temp' as $$
begin
  if (new.codigo is distinct from old.codigo or new.unidad_dosis is distinct from old.unidad_dosis or new.rol is distinct from old.rol or new.pide_nombre is distinct from old.pide_nombre)
     and exists (select 1 from tecnica.uso_quimicos u where u.quimico_id = old.id) then
    raise exception 'El químico ya tiene usos registrados: no se puede cambiar su código, unidad, rol ni si pide nombre. Cree uno nuevo y desactive este' using errcode = '55000';
  end if;
  return new;
end $$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 't_quimico_protegido') then
    create trigger t_quimico_protegido before update on tecnica.quimicos for each row execute function tecnica.f_quimico_protegido();
    create trigger t_no_borrar before delete on tecnica.quimicos for each row execute function tecnica.f_solo_agregar();
    create trigger t_no_vaciar before truncate on tecnica.quimicos for each statement execute function tecnica.f_solo_agregar();
  end if;
end $$;
alter table tecnica.quimicos enable row level security;
insert into tecnica.quimicos (codigo, nombre, rol, pide_nombre) values ('pac', 'Policloruro de aluminio', 'coagulante', false), ('cloro_gaseoso', 'Cloro gaseoso', 'desinfectante', false),
  ('otro', 'Otro', 'otro', true) on conflict (codigo) do nothing;
insert into tecnica.variables (codigo, nombre, unidad, categoria) values ('caudal_qi', 'Caudal de ingreso Qi', 'L/s', 'caudal') on conflict do nothing;
insert into tecnica.formulario_variables (formulario, variable_id, orden, alcance) select 'entrada', id, 1, 'por_planta' from tecnica.variables where codigo = 'caudal_qi' on conflict do nothing;
