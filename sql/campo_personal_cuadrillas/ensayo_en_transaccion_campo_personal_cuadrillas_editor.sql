-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · ENSAYO (termina en ERROR esperado; no deja nada) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 05 — GUARDIA (se detiene si la base no es la de producción del 21-nov 17:55)
-- Huellas: redes 1ba19272… y técnica 3e9b0121… (corte de eventos publicado); campo cf40d2a2… (68 funciones) y las md5 de lo que se reemplaza.
-- =====================================================================
do $$
declare v text;
begin
  if to_regprocedure('public.geoportal_campo_cuadrillas(text,jsonb,text)') is not null then
    raise exception 'Personal y cuadrillas de Comercial ya parece aplicado (existe geoportal_campo_cuadrillas): use la reversa antes de repetir';
  end if;
  -- tras una reversa con datos, las tablas se conservan (y el disparador campo.f_no_borrar_catalogo): la migración las reutiliza; por eso esa función no cuenta en la huella
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v from pg_proc p
   where p.pronamespace = to_regnamespace('redes') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if coalesce(v, '(ninguna)') is distinct from '1ba192724c2fddcf321104700829f3cc' then raise exception 'Las funciones de redes no son las publicadas el 21-nov (huella 1ba192724c2fddcf321104700829f3cc; hay %): deténgase y avise', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = to_regnamespace('tecnica') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%');
  if coalesce(v, '(ninguna)') is distinct from '3e9b0121e2b8beb313fad05de9e50f15' then raise exception 'Las funciones de técnica no son las publicadas el 21-nov (huella 3e9b0121e2b8beb313fad05de9e50f15; hay %): deténgase y avise', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where (p.pronamespace = 'campo'::regnamespace and p.proname <> 'f_no_borrar_catalogo') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if coalesce(v, '(ninguna)') is distinct from 'cf40d2a279c385d17a6cc5da2aac3fa9' then raise exception 'Las funciones de campo no son las del 21-nov 17:55 (huella cf40d2a279c385d17a6cc5da2aac3fa9; hay %): deténgase y avise', v; end if;
  if md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal(text,jsonb,text)'))) is distinct from 'f8a83b02da97e8f6a729767f57a394c4'
     or md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_historial_personal(text,jsonb,text)'))) is distinct from 'e82377f5de26a2dcc1a007403889ba48'
     or md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal_cambiar(text,text,text,text,text,text,text)'))) is distinct from 'c0302a7b45307215d8f780d8c78cd396'
     or md5(pg_get_functiondef(to_regprocedure('campo.f_formularios_personal()'))) is distinct from '283a63c1ee3fad9e5956a65f8a4644b6' then
    raise exception 'Las funciones de Personal de campo no son las esperadas (pasada del 14-nov y Corte 14): deténgase y avise';
  end if;
  if to_regclass('campo.cuadrillas') is null and ((select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_eventos_tipo_evento_check')
       is distinct from 'CHECK ((tipo_evento = ANY (ARRAY[''fijar_cargo''::text, ''asignar_formulario''::text, ''quitar_formulario''::text])))'
     or (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_ev_ck')
       is distinct from 'CHECK ((((tipo_evento = ''fijar_cargo''::text) = (cargo IS NOT NULL)) AND ((tipo_evento = ''fijar_cargo''::text) = (formulario IS NULL)) AND ((tipo_evento <> ''quitar_formulario''::text) OR (motivo IS NOT NULL))))'
     or exists (select 1 from pg_attribute where attrelid = 'campo.personal_eventos'::regclass and attname = 'valor' and not attisdropped)) then
    raise exception 'campo.personal_eventos no tiene los CHECK de la pasada del 14-nov: deténgase y avise';
  end if;
  if to_regprocedure('campo.f_auditar(text,text,text,jsonb,text)') is null or to_regprocedure('campo.f_autorizar_personal(text)') is null
     or to_regprocedure('campo.f_autorizar_supervision(text)') is null or to_regprocedure('campo.f_autorizar_admin(text)') is null or to_regprocedure('campo.f_solo_agregar()') is null then
    raise exception 'Faltan funciones internas de campo (auditar, autorizar o solo agregar): deténgase y avise';
  end if;
end $$;

-- Si una reversa con datos conservó las tablas, la estructura no se repite (nada se borra; se reutiliza lo conservado).
do $estructura$
begin
  if to_regclass('campo.cuadrillas') is null then
    execute $sql_estructura$
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

$sql_estructura$;
  else
    raise notice 'Las tablas de Personal y cuadrillas se conservaron de una reversa: se reutilizan';
  end if;
end $estructura$;

-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 20 — FUNCIONES INTERNAS (nadie las ejecuta directamente: revoke all)
-- Lo vigente es siempre el último evento de cada grupo (área; cuadrilla; cada actividad), igual que cargo y formularios en la pasada del 14-nov.
-- =====================================================================

-- Persona que se gestiona en Personal de Comercial: la misma regla de la pasada del 14-nov (activa, no administradora, con acceso a campo o al acta).
create function campo.f_persona_comercial(p_email text) returns boolean
language sql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
  select exists (select 1 from public.geoportal_lista_blanca lb where lb.email = lower(p_email) and lb.activo and lb.rol <> 'admin'
                   and (coalesce(lb.ver_campo, false) or coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_acta, false) or coalesce(lb.ver_dashboard_acta, false)))
$$;

create function campo.f_area_vigente(p_email text) returns text
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select e.valor from campo.personal_eventos e where e.persona = lower(p_email) and e.tipo_evento = 'fijar_area' order by e.id desc limit 1
$$;

create function campo.f_cuadrilla_vigente(p_email text) returns bigint
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select e.valor::bigint from campo.personal_eventos e where e.persona = lower(p_email) and e.tipo_evento = 'fijar_cuadrilla' order by e.id desc limit 1
$$;

create function campo.f_actividades_propias(p_email text) returns text[]
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select coalesce(array_agg(u.valor order by u.valor), '{}') from (
    select distinct on (e.valor) e.valor, e.tipo_evento from campo.personal_eventos e
     where e.persona = lower(p_email) and e.tipo_evento in ('asignar_actividad', 'quitar_actividad') order by e.valor, e.id desc) u
   where u.tipo_evento = 'asignar_actividad'
$$;

create function campo.f_cuadrilla_actividades(p_cuadrilla bigint) returns text[]
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select coalesce(array_agg(u.valor order by u.valor), '{}') from (
    select distinct on (e.valor) e.valor, e.tipo_evento from campo.cuadrilla_eventos e
     where e.cuadrilla_id = p_cuadrilla and e.tipo_evento in ('agregar_actividad', 'quitar_actividad') order by e.valor, e.id desc) u
   where u.tipo_evento = 'agregar_actividad'
$$;

-- Miembros vigentes de las cuadrillas: el último fijar_cuadrilla de cada persona gestionable.
create function campo.f_miembros_cuadrillas() returns table (persona text, cuadrilla_id bigint)
language sql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
  select v.persona, v.valor::bigint from (
    select distinct on (e.persona) e.persona, e.valor from campo.personal_eventos e where e.tipo_evento = 'fijar_cuadrilla' order by e.persona, e.id desc) v
   where v.valor is not null and campo.f_persona_comercial(v.persona)
$$;

-- Actividades vigentes de una persona: las propias más las de su cuadrilla (D3), con su origen. Incluye las desactivadas (la pantalla las marca).
create function campo.f_actividades_persona(p_email text) returns table (codigo text, origen text)
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  with p as (select unnest(campo.f_actividades_propias(p_email)) as codigo),
       c as (select unnest(campo.f_cuadrilla_actividades(q.id)) as codigo
               from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(p_email) and q.activa)
  select coalesce(p.codigo, c.codigo), case when p.codigo is not null and c.codigo is not null then 'ambas' when p.codigo is not null then 'propia' else 'cuadrilla' end
    from p full join c on c.codigo = p.codigo
$$;

-- «Quién puede hacer la actividad X» (para SCRR, lectura y reparto, que la usarán desde sus propias RPC): personas activas con acceso a campo o al acta,
-- que tienen la actividad como propia o por su cuadrilla activa.
create function campo.f_quien_puede(p_actividad text) returns table (persona text, cuadrilla_id bigint, origen text)
language sql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
  with propias as (
         select u.persona from (
           select distinct on (e.persona) e.persona, e.tipo_evento from campo.personal_eventos e
            where e.valor = p_actividad and e.tipo_evento in ('asignar_actividad', 'quitar_actividad') order by e.persona, e.id desc) u
          where u.tipo_evento = 'asignar_actividad' and campo.f_persona_comercial(u.persona)),
       por_cuadrilla as (
         select m.persona, m.cuadrilla_id from campo.f_miembros_cuadrillas() m join campo.cuadrillas q on q.id = m.cuadrilla_id and q.activa
          where p_actividad = any (campo.f_cuadrilla_actividades(m.cuadrilla_id)))
  select coalesce(p.persona, c.persona), (select m.cuadrilla_id from campo.f_miembros_cuadrillas() m where m.persona = coalesce(p.persona, c.persona)),
         case when p.persona is not null and c.persona is not null then 'ambas' when p.persona is not null then 'propia' else 'cuadrilla' end
    from propias p full join por_cuadrilla c on c.persona = p.persona
$$;

-- Código a partir del nombre (catálogos): minúsculas sin tildes, guion bajo en lo demás, hasta 40 caracteres.
create function campo.f_codigo_desde_nombre(p_nombre text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select left(btrim(regexp_replace(translate(lower(btrim(p_nombre)), 'áéíóúüñàèìòù', 'aeiouunaeiou'), '[^a-z0-9]+', '_', 'g'), '_'), 40)
$$;

-- Motivo: nulo o de 10 a 300 caracteres (el CHECK de las tablas); el mensaje lo ve el usuario.
create function campo.f_motivo_personal(p_motivo text, p_obligatorio boolean) returns text
language plpgsql stable set search_path to 'pg_catalog' as $$
declare v text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if v is null and p_obligatorio then perform campo.f_error('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
  if v is not null and (length(v) < 10 or length(v) > 300) then perform campo.f_error('El motivo debe tener entre 10 y 300 caracteres'); end if;
  return v;
end $$;

revoke all on function campo.f_persona_comercial(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_area_vigente(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_cuadrilla_vigente(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_actividades_propias(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_cuadrilla_actividades(bigint) from public, anon, authenticated, service_role;
revoke all on function campo.f_miembros_cuadrillas() from public, anon, authenticated, service_role;
revoke all on function campo.f_actividades_persona(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_quien_puede(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_codigo_desde_nombre(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_motivo_personal(text, boolean) from public, anon, authenticated, service_role;

-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 25 — REEMPLAZOS (misma firma; la respuesta de hoy no cambia, solo se le agregan campos)
-- public.geoportal_campo_personal (f8a83b02…) y public.geoportal_campo_historial_personal (e82377f5…). La reversa vuelve a los textos publicados.
-- public.geoportal_campo_personal_cambiar (c0302a7b…) NO se toca: la sigue usando la Edge publicada; la nueva ruta usa geoportal_campo_personal_fijar (26).
-- =====================================================================

create or replace function public.geoportal_campo_personal(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_buscar text; v_admin boolean; v_sup boolean;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  v_buscar := nullif(btrim(coalesce(f ->> 'buscar', '')), '');
  v_admin := public.geoportal_es_admin(v_email);
  v_sup := v_admin or public.geoportal_puede(v_email, 'dashboard_campo');
  return jsonb_build_object(
    'puede_editar', v_admin,
    'yo', v_email,
    'puede', jsonb_build_object('cargo', v_admin, 'area', v_admin, 'cuadrilla', v_sup, 'cuadrillas', v_sup, 'actividades', v_sup, 'formularios', v_sup, 'catalogos', v_admin),
    'formularios', (select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'nombre', x.nombre, 'grupo', x.grupo) order by x.orden, x.clave), '[]'::jsonb) from campo.f_formularios_personal() x),
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre) order by a.orden, a.codigo), '[]'::jsonb) from campo.areas_comercial a where a.activa),
    'cuadrillas', (select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nombre', q.nombre) order by lower(q.nombre), q.id), '[]'::jsonb) from campo.cuadrillas q where q.activa),
    'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre) order by a.orden, a.codigo), '[]'::jsonb) from campo.actividades a where a.activa),
    'personas', (select coalesce(jsonb_agg(p order by p ->> 'nombre_orden', p ->> 'email'), '[]'::jsonb) from (
      select jsonb_build_object('email', lb.email, 'nombre', nullif(btrim(lb.nombre), ''), 'nombre_orden', lower(coalesce(nullif(btrim(lb.nombre), ''), lb.email)),
               'perfil', case when coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_dashboard_acta, false) then 'supervisor' else 'operario' end,
               'permisos', jsonb_build_object('campo', coalesce(lb.ver_campo, false), 'dashboard_campo', coalesce(lb.ver_dashboard_campo, false),
                                              'acta', coalesce(lb.ver_acta, false), 'dashboard_acta', coalesce(lb.ver_dashboard_acta, false)),
               'cargo', campo.f_cargo_vigente(lb.email),
               'formularios', to_jsonb(campo.f_formularios_asignados(lb.email)),
               'sin_asignacion', cardinality(campo.f_formularios_asignados(lb.email)) = 0,
               'ultimo_cambio', (select max(e.creado_en) from campo.personal_eventos e where e.persona = lb.email),
               'propia', lb.email = v_email,
               'area', (select jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'activa', a.activa) from campo.areas_comercial a where a.codigo = campo.f_area_vigente(lb.email)),
               'cuadrilla', (select jsonb_build_object('id', q.id, 'nombre', q.nombre, 'activa', q.activa) from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(lb.email)),
               'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'nombre', coalesce(a.nombre, x.codigo), 'activa', coalesce(a.activa, false), 'origen', x.origen)
                                                         order by a.orden, x.codigo), '[]'::jsonb)
                                 from campo.f_actividades_persona(lb.email) x left join campo.actividades a on a.codigo = x.codigo)) as p
        from public.geoportal_lista_blanca lb
       where lb.activo and lb.rol <> 'admin'
         and (coalesce(lb.ver_campo, false) or coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_acta, false) or coalesce(lb.ver_dashboard_acta, false))
         and (v_buscar is null or lb.email ilike '%' || v_buscar || '%' or coalesce(lb.nombre, '') ilike '%' || v_buscar || '%')) s));
end $$;

-- Historial: las mismas filas de hoy más los tipos nuevos, con valor_codigo y valor_nombre (y «clave» única: p:<id> de persona, c:<id> de cuadrilla).
-- Con cuadrilla_id: los eventos de esa cuadrilla (persona nula, tipo_evento cuadrilla_<tipo>) más las entradas y salidas de personas; sin paginar (los 500 más nuevos).
create or replace function public.geoportal_campo_historial_personal(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_p text; v_desp bigint; v_lim integer; v_cuad bigint; v_filas jsonb; v_n integer;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_p := nullif(lower(btrim(coalesce(f ->> 'persona', ''))), ''); v_desp := nullif(f ->> 'despues_de', '')::bigint;
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 100), 1), 500);
    v_cuad := nullif(f ->> 'cuadrilla_id', '')::bigint;
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  if v_cuad is not null then
    if not exists (select 1 from campo.cuadrillas q where q.id = v_cuad) then perform campo.f_error('Esa cuadrilla no existe'); end if;
    with ce as (
      select e.creado_en, jsonb_build_object('clave', 'c:' || e.id, 'id', e.id, 'persona', null, 'nombre', null, 'tipo_evento', 'cuadrilla_' || e.tipo_evento,
               'cuadrilla', jsonb_build_object('id', q.id, 'nombre', q.nombre),
               'formulario', null, 'formulario_nombre', null, 'cargo', null,
               'valor_codigo', case when e.tipo_evento in ('agregar_actividad', 'quitar_actividad') then e.valor end,
               'valor_nombre', case when e.tipo_evento in ('agregar_actividad', 'quitar_actividad') then coalesce((select a.nombre from campo.actividades a where a.codigo = e.valor), e.valor) else e.valor end,
               'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en, 'vigente', null) as fila
        from campo.cuadrilla_eventos e join campo.cuadrillas q on q.id = e.cuadrilla_id where e.cuadrilla_id = v_cuad
    ), pe as (
      select x.*, lag(x.valor) over (partition by x.persona order by x.id) as anterior from campo.personal_eventos x where x.tipo_evento = 'fijar_cuadrilla'
    ), pm as (
      select pe.creado_en, jsonb_build_object('clave', 'p:' || pe.id, 'id', pe.id, 'persona', pe.persona, 'nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = pe.persona),
               'tipo_evento', pe.tipo_evento, 'cuadrilla', jsonb_build_object('id', q.id, 'nombre', q.nombre),
               'formulario', null, 'formulario_nombre', null, 'cargo', null,
               'valor_codigo', pe.valor, 'valor_nombre', (select c.nombre from campo.cuadrillas c where c.id = pe.valor::bigint),
               'entra', pe.valor = v_cuad::text, 'motivo', pe.motivo, 'autor', pe.autor, 'creado_en', pe.creado_en, 'vigente', null) as fila
        from pe join campo.cuadrillas q on q.id = v_cuad where pe.valor = v_cuad::text or pe.anterior = v_cuad::text
    ), todo as (select * from ce union all select * from pm order by 1 desc limit 500)
    select coalesce(jsonb_agg(fila order by creado_en desc), '[]'::jsonb) into v_filas from todo;
    return jsonb_build_object('eventos', v_filas, 'siguiente', null);
  end if;
  with ev as (
    select e.*, e.id = max(e.id) over (partition by e.persona, case when e.tipo_evento in ('asignar_formulario', 'quitar_formulario') then 'f:' || e.formulario
                                                                    when e.tipo_evento in ('asignar_actividad', 'quitar_actividad') then 'a:' || e.valor
                                                                    else e.tipo_evento end) as vigente
      from campo.personal_eventos e where v_p is null or e.persona = v_p
  ), pag as (select * from ev where v_desp is null or ev.id < v_desp order by ev.id desc limit v_lim + 1)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'persona', p.persona, 'nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = p.persona),
           'tipo_evento', p.tipo_evento, 'formulario', p.formulario,
           'formulario_nombre', case when p.formulario is null then null else coalesce((select x.nombre from campo.f_formularios_personal() x where x.clave = p.formulario),
                                                                                     (select t.nombre from campo.tipos_reporte t where 'tipo:' || t.codigo = p.formulario), p.formulario) end,
           'cargo', p.cargo, 'motivo', p.motivo, 'autor', p.autor, 'creado_en', p.creado_en, 'vigente', p.vigente,
           'clave', 'p:' || p.id, 'valor_codigo', p.valor,
           'valor_nombre', case p.tipo_evento when 'fijar_area' then (select a.nombre from campo.areas_comercial a where a.codigo = p.valor)
                                              when 'fijar_cuadrilla' then (select q.nombre from campo.cuadrillas q where q.id = p.valor::bigint)
                                              when 'asignar_actividad' then (select a.nombre from campo.actividades a where a.codigo = p.valor)
                                              when 'quitar_actividad' then (select a.nombre from campo.actividades a where a.codigo = p.valor) end) order by p.id desc) filter (where rn <= v_lim), '[]'::jsonb)
    into v_n, v_filas from (select pag.*, row_number() over (order by pag.id desc) as rn from pag) p;
  return jsonb_build_object('eventos', v_filas, 'siguiente', case when v_n > v_lim then (select min((x ->> 'id')::bigint) from jsonb_array_elements(v_filas) x) end);
end $$;

-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 26 — RPC NUEVAS (solo service_role; el solicitante es el correo del token, lo pone la Edge)
-- Quién edita (patrón de Técnica, cortes 4b y 5a): el supervisor de campo cuadrillas, miembros, actividades y formularios; el administrador además área,
-- cargo y catálogos; el supervisor de actas solo ve. Nadie cambia su propia ficha. Mensajes con HINT msg_usuario (los ve el usuario); 55000 → 409.
-- =====================================================================

create function public.geoportal_campo_personal_fijar(p_solicitante text, p_persona text, p_tipo text, p_datos jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; v_admin boolean; d jsonb := coalesce(p_datos, '{}'::jsonb); v_p text := lower(btrim(coalesce(p_persona, '')));
        v_f text; v_c text; v_m text; v_val text; v_cuad bigint; v_ant bigint; v_q campo.cuadrillas; v_a campo.actividades; v_ar campo.areas_comercial; v_id bigint;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  v_admin := public.geoportal_es_admin(v_email);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del cambio no tienen el formato esperado'); end if;
  if p_tipo is null or p_tipo not in ('fijar_cargo', 'fijar_area', 'fijar_cuadrilla', 'asignar_formulario', 'quitar_formulario', 'asignar_actividad', 'quitar_actividad') then
    perform campo.f_error('El cambio debe ser fijar_cargo, fijar_area, fijar_cuadrilla, asignar_formulario, quitar_formulario, asignar_actividad o quitar_actividad');
  end if;
  if p_tipo in ('fijar_cargo', 'fijar_area') and not v_admin then raise exception 'Solo el administrador puede hacerlo' using errcode = '42501'; end if;
  if not campo.f_persona_comercial(v_p) then perform campo.f_error('Esa persona no tiene acceso activo a Formularios de campo ni al acta'); end if;
  if v_p = v_email then perform campo.f_error('No puede cambiar su propia ficha'); end if;
  perform pg_advisory_xact_lock(hashtext('campo_personal:' || v_p));
  v_m := campo.f_motivo_personal(d ->> 'motivo', p_tipo in ('quitar_formulario', 'quitar_actividad'));
  if p_tipo = 'fijar_cargo' then
    v_c := nullif(btrim(coalesce(d ->> 'cargo', '')), '');
    if v_c is null or length(v_c) < 2 or length(v_c) > 80 then perform campo.f_error('El cargo debe tener entre 2 y 80 caracteres'); end if;
    if v_c is not distinct from campo.f_cargo_vigente(v_p) then perform campo.f_error('Ese ya es el cargo vigente', '55000'); end if;
  elsif p_tipo = 'fijar_area' then
    select * into v_ar from campo.areas_comercial a where a.codigo = nullif(btrim(coalesce(d ->> 'area', '')), '');
    if v_ar.codigo is null then perform campo.f_error('Esa área no existe'); end if;
    if not v_ar.activa then perform campo.f_error('Esa área está desactivada'); end if;
    if v_ar.codigo is not distinct from campo.f_area_vigente(v_p) then perform campo.f_error('Ya tiene esa área', '55000'); end if;
    v_val := v_ar.codigo;
  elsif p_tipo = 'fijar_cuadrilla' then
    begin v_cuad := nullif(d ->> 'cuadrilla_id', '')::bigint; exception when others then perform campo.f_error('La cuadrilla no es válida'); end;
    v_ant := campo.f_cuadrilla_vigente(v_p);
    if v_cuad is not null then
      perform pg_advisory_xact_lock(hashtext('campo_cuadrilla:' || v_cuad));
      select * into v_q from campo.cuadrillas q where q.id = v_cuad;
      if v_q.id is null then perform campo.f_error('Esa cuadrilla no existe'); end if;
      if not v_q.activa then perform campo.f_error('Esa cuadrilla está desactivada'); end if;
    end if;
    if v_cuad is not distinct from v_ant then
      perform campo.f_error(case when v_cuad is null then 'No está en ninguna cuadrilla' else 'Ya está en esa cuadrilla' end, '55000');
    end if;
    if v_ant is not null and v_m is null then perform campo.f_error('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
    v_val := v_cuad::text;
  elsif p_tipo in ('asignar_formulario', 'quitar_formulario') then
    v_f := nullif(btrim(coalesce(d ->> 'formulario', '')), '');
    if v_f is null then perform campo.f_error('Indique el formulario'); end if;
    if p_tipo = 'asignar_formulario' then
      if not exists (select 1 from campo.f_formularios_personal() x where x.clave = v_f) then perform campo.f_error('Ese formulario no existe o está desactivado'); end if;
      if v_f = any (campo.f_formularios_asignados(v_p)) then perform campo.f_error('Ya tiene asignado ese formulario', '55000'); end if;
    elsif not (v_f = any (campo.f_formularios_asignados(v_p))) then perform campo.f_error('No tiene asignado ese formulario', '55000');
    end if;
  else
    select * into v_a from campo.actividades a where a.codigo = nullif(btrim(coalesce(d ->> 'actividad', '')), '');
    if v_a.codigo is null then perform campo.f_error('Esa actividad no existe'); end if;
    if p_tipo = 'asignar_actividad' then
      if not v_a.activa then perform campo.f_error('Esa actividad está desactivada'); end if;
      if v_a.codigo = any (campo.f_actividades_propias(v_p)) then perform campo.f_error('Ya tiene esa actividad', '55000'); end if;
    elsif not (v_a.codigo = any (campo.f_actividades_propias(v_p))) then
      if exists (select 1 from campo.f_actividades_persona(v_p) x where x.codigo = v_a.codigo) then
        perform campo.f_error('Esa actividad viene de la cuadrilla ' || (select q.nombre from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(v_p)) || ': se quita en la cuadrilla', '55000');
      end if;
      perform campo.f_error('No tiene esa actividad', '55000');
    end if;
    v_val := v_a.codigo;
  end if;
  insert into campo.personal_eventos (persona, tipo_evento, formulario, cargo, valor, motivo, autor) values (v_p, p_tipo, v_f, v_c, v_val, v_m, v_email) returning id into v_id;
  perform campo.f_auditar(v_email, 'campo_personal_' || p_tipo, v_p, jsonb_build_object('evento', v_id, 'formulario', v_f, 'valor', v_val, 'cargo', v_c is not null), p_ip);
  return jsonb_build_object('id', v_id, 'cambio', true);
end $$;

create function public.geoportal_campo_cuadrillas(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_todas boolean;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  if f ? 'incluir_inactivas' and jsonb_typeof(f -> 'incluir_inactivas') not in ('boolean', 'null') then perform campo.f_error('incluir_inactivas debe ser sí o no'); end if;
  v_todas := coalesce((f ->> 'incluir_inactivas')::boolean, false);
  return jsonb_build_object('cuadrillas', (
    with m as (select * from campo.f_miembros_cuadrillas())
    select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nombre', q.nombre, 'activa', q.activa, 'creada_en', q.creado_en, 'autor', q.autor,
             'n_miembros', (select count(*) from m where m.cuadrilla_id = q.id),
             'miembros', (select coalesce(jsonb_agg(jsonb_build_object('email', m.persona, 'nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = m.persona))
                                                    order by m.persona), '[]'::jsonb) from m where m.cuadrilla_id = q.id),
             'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'nombre', coalesce(a.nombre, x.codigo), 'activa', coalesce(a.activa, false)) order by a.orden, x.codigo), '[]'::jsonb)
                               from unnest(campo.f_cuadrilla_actividades(q.id)) as x(codigo) left join campo.actividades a on a.codigo = x.codigo))
             order by q.activa desc, lower(q.nombre), q.id), '[]'::jsonb)
      from campo.cuadrillas q where q.activa or v_todas));
end $$;

create function public.geoportal_campo_cuadrilla_cambiar(p_solicitante text, p_datos jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; d jsonb := coalesce(p_datos, '{}'::jsonb); v_tipo text; v_id bigint; v_q campo.cuadrillas; v_nombre text; v_m text; v_a campo.actividades; v_n integer; v_ev bigint; v_val text;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del cambio no tienen el formato esperado'); end if;
  v_tipo := d ->> 'tipo';
  if v_tipo is null or v_tipo not in ('crear', 'renombrar', 'desactivar', 'activar', 'agregar_actividad', 'quitar_actividad') then
    perform campo.f_error('El cambio debe ser crear, renombrar, desactivar, activar, agregar_actividad o quitar_actividad');
  end if;
  v_m := campo.f_motivo_personal(d ->> 'motivo', v_tipo in ('desactivar', 'quitar_actividad'));
  if v_tipo in ('crear', 'renombrar') then
    v_nombre := regexp_replace(btrim(coalesce(d ->> 'nombre', '')), '\s+', ' ', 'g');
    if length(v_nombre) < 2 or length(v_nombre) > 60 then perform campo.f_error('El nombre de la cuadrilla debe tener entre 2 y 60 caracteres'); end if;
  end if;
  if v_tipo = 'crear' then
    perform pg_advisory_xact_lock(hashtext('campo_cuadrillas'));
    if exists (select 1 from campo.cuadrillas q where lower(regexp_replace(q.nombre, '\s', '', 'g')) = lower(regexp_replace(v_nombre, '\s', '', 'g'))) then
      perform campo.f_error('Ya existe una cuadrilla con ese nombre', '55000');
    end if;
    insert into campo.cuadrillas (nombre, autor) values (v_nombre, v_email) returning id into v_id;
    insert into campo.cuadrilla_eventos (cuadrilla_id, tipo_evento, valor, autor) values (v_id, 'crear', v_nombre, v_email) returning id into v_ev;
    perform campo.f_auditar(v_email, 'campo_cuadrilla_crear', v_id::text, jsonb_build_object('evento', v_ev), p_ip);
    return jsonb_build_object('id', v_id, 'cambio', true);
  end if;
  begin v_id := (d ->> 'cuadrilla_id')::bigint; exception when others then perform campo.f_error('La cuadrilla no es válida'); end;
  if v_id is null then perform campo.f_error('Indique la cuadrilla'); end if;
  perform pg_advisory_xact_lock(hashtext('campo_cuadrillas'));
  perform pg_advisory_xact_lock(hashtext('campo_cuadrilla:' || v_id));
  select * into v_q from campo.cuadrillas q where q.id = v_id;
  if v_q.id is null then perform campo.f_error('Esa cuadrilla no existe'); end if;
  if v_tipo = 'renombrar' then
    if v_nombre = v_q.nombre then perform campo.f_error('La cuadrilla ya tiene ese nombre', '55000'); end if;
    if exists (select 1 from campo.cuadrillas q where q.id <> v_id and lower(regexp_replace(q.nombre, '\s', '', 'g')) = lower(regexp_replace(v_nombre, '\s', '', 'g'))) then
      perform campo.f_error('Ya existe una cuadrilla con ese nombre', '55000');
    end if;
    update campo.cuadrillas set nombre = v_nombre where id = v_id;
    v_val := v_nombre;
  elsif v_tipo = 'desactivar' then
    if not v_q.activa then perform campo.f_error('La cuadrilla ya está desactivada', '55000'); end if;
    select count(*) into v_n from campo.f_miembros_cuadrillas() m where m.cuadrilla_id = v_id;
    if v_n > 0 then
      perform campo.f_error(case when v_n = 1 then 'La cuadrilla tiene 1 miembro: sáquelo antes de desactivarla' else 'La cuadrilla tiene ' || v_n || ' miembros: sáquelos antes de desactivarla' end, '55000');
    end if;
    update campo.cuadrillas set activa = false where id = v_id;
  elsif v_tipo = 'activar' then
    if v_q.activa then perform campo.f_error('La cuadrilla ya está activa', '55000'); end if;
    update campo.cuadrillas set activa = true where id = v_id;
  else
    select * into v_a from campo.actividades a where a.codigo = nullif(btrim(coalesce(d ->> 'actividad', '')), '');
    if v_a.codigo is null then perform campo.f_error('Esa actividad no existe'); end if;
    if v_tipo = 'agregar_actividad' then
      if not v_q.activa then perform campo.f_error('Esa cuadrilla está desactivada'); end if;
      if not v_a.activa then perform campo.f_error('Esa actividad está desactivada'); end if;
      if v_a.codigo = any (campo.f_cuadrilla_actividades(v_id)) then perform campo.f_error('La cuadrilla ya tiene esa actividad', '55000'); end if;
    elsif not (v_a.codigo = any (campo.f_cuadrilla_actividades(v_id))) then perform campo.f_error('La cuadrilla no tiene esa actividad', '55000');
    end if;
    v_val := v_a.codigo;
  end if;
  insert into campo.cuadrilla_eventos (cuadrilla_id, tipo_evento, valor, motivo, autor) values (v_id, v_tipo, v_val, v_m, v_email) returning id into v_ev;
  perform campo.f_auditar(v_email, 'campo_cuadrilla_' || v_tipo, v_id::text, jsonb_build_object('evento', v_ev, 'valor', v_val), p_ip);
  return jsonb_build_object('id', v_id, 'cambio', true);
end $$;

create function public.geoportal_campo_catalogos(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  return jsonb_build_object(
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'activa', a.activa, 'orden', a.orden) order by a.orden, a.codigo), '[]'::jsonb) from campo.areas_comercial a),
    'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'activa', a.activa, 'orden', a.orden) order by a.orden, a.codigo), '[]'::jsonb) from campo.actividades a));
end $$;

create function public.geoportal_campo_catalogo_cambiar(p_solicitante text, p_datos jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; d jsonb := coalesce(p_datos, '{}'::jsonb); v_cat text; v_tipo text; v_cod text; v_nombre text; v_m text; v_activa boolean; v_actual text; v_ev bigint; v_que text;
begin
  v_email := campo.f_autorizar_admin(p_solicitante);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del cambio no tienen el formato esperado'); end if;
  v_cat := d ->> 'catalogo'; v_tipo := d ->> 'tipo';
  if v_cat is null or v_cat not in ('area', 'actividad') then perform campo.f_error('El catálogo debe ser area o actividad'); end if;
  if v_tipo is null or v_tipo not in ('crear', 'renombrar', 'desactivar', 'activar') then perform campo.f_error('El cambio debe ser crear, renombrar, desactivar o activar'); end if;
  v_que := case v_cat when 'area' then 'un área' else 'una actividad' end;
  v_m := campo.f_motivo_personal(d ->> 'motivo', v_tipo = 'desactivar');
  perform pg_advisory_xact_lock(hashtext('campo_catalogo:' || v_cat));
  if v_tipo in ('crear', 'renombrar') then
    v_nombre := regexp_replace(btrim(coalesce(d ->> 'nombre', '')), '\s+', ' ', 'g');
    if length(v_nombre) < 2 or length(v_nombre) > 60 then perform campo.f_error('El nombre debe tener entre 2 y 60 caracteres'); end if;
  end if;
  if v_tipo = 'crear' then
    v_cod := campo.f_codigo_desde_nombre(v_nombre);
    if v_cod !~ '^[a-z][a-z0-9_]{1,39}$' then perform campo.f_error('El nombre debe empezar con una letra'); end if;
    if (v_cat = 'area' and exists (select 1 from campo.areas_comercial a where lower(a.nombre) = lower(v_nombre) or a.codigo = v_cod))
       or (v_cat = 'actividad' and exists (select 1 from campo.actividades a where lower(a.nombre) = lower(v_nombre) or a.codigo = v_cod)) then
      perform campo.f_error('Ya existe ' || v_que || ' con ese nombre', '55000');
    end if;
    if v_cat = 'area' then
      insert into campo.areas_comercial (codigo, nombre, orden, autor) select v_cod, v_nombre, coalesce(max(orden), 0) + 1, v_email from campo.areas_comercial;
    else
      insert into campo.actividades (codigo, nombre, orden, autor) select v_cod, v_nombre, coalesce(max(orden), 0) + 1, v_email from campo.actividades;
    end if;
  else
    v_cod := nullif(btrim(coalesce(d ->> 'codigo', '')), '');
    if v_cat = 'area' then select a.nombre, a.activa into v_actual, v_activa from campo.areas_comercial a where a.codigo = v_cod;
    else select a.nombre, a.activa into v_actual, v_activa from campo.actividades a where a.codigo = v_cod; end if;
    if v_actual is null then perform campo.f_error('No existe ' || v_que || ' con ese código'); end if;
    if v_tipo = 'renombrar' then
      if v_nombre = v_actual then perform campo.f_error('Ya tiene ese nombre', '55000'); end if;
      if (v_cat = 'area' and exists (select 1 from campo.areas_comercial a where a.codigo <> v_cod and lower(a.nombre) = lower(v_nombre)))
         or (v_cat = 'actividad' and exists (select 1 from campo.actividades a where a.codigo <> v_cod and lower(a.nombre) = lower(v_nombre))) then
        perform campo.f_error('Ya existe ' || v_que || ' con ese nombre', '55000');
      end if;
    elsif v_tipo = 'desactivar' and not v_activa then perform campo.f_error('Ya está desactivada', '55000');
    elsif v_tipo = 'activar' and v_activa then perform campo.f_error('Ya está activa', '55000');
    end if;
    if v_cat = 'area' then
      update campo.areas_comercial set nombre = coalesce(v_nombre, nombre), activa = case v_tipo when 'desactivar' then false when 'activar' then true else activa end where codigo = v_cod;
    else
      update campo.actividades set nombre = coalesce(v_nombre, nombre), activa = case v_tipo when 'desactivar' then false when 'activar' then true else activa end where codigo = v_cod;
    end if;
  end if;
  insert into campo.catalogo_eventos (catalogo, codigo, tipo_evento, nombre, motivo, autor) values (v_cat, v_cod, v_tipo, v_nombre, v_m, v_email) returning id into v_ev;
  perform campo.f_auditar(v_email, 'campo_catalogo_' || v_cat || '_' || v_tipo, v_cod, jsonb_build_object('evento', v_ev), p_ip);
  return jsonb_build_object('codigo', v_cod, 'cambio', true);
end $$;

create function public.geoportal_campo_personal_actividad(p_solicitante text, p_actividad text, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; v_a campo.actividades;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  select * into v_a from campo.actividades a where a.codigo = nullif(btrim(coalesce(p_actividad, '')), '');
  if v_a.codigo is null then perform campo.f_error('Esa actividad no existe'); end if;
  return jsonb_build_object(
    'actividad', jsonb_build_object('codigo', v_a.codigo, 'nombre', v_a.nombre, 'activa', v_a.activa),
    'personas', (select coalesce(jsonb_agg(jsonb_build_object('email', x.persona, 'nombre', nullif(btrim(lb.nombre), ''),
                                                              'cuadrilla', (select jsonb_build_object('id', q.id, 'nombre', q.nombre) from campo.cuadrillas q where q.id = x.cuadrilla_id),
                                                              'origen', x.origen) order by lower(coalesce(nullif(btrim(lb.nombre), ''), x.persona)), x.persona), '[]'::jsonb)
                   from campo.f_quien_puede(v_a.codigo) x left join public.geoportal_lista_blanca lb on lb.email = x.persona));
end $$;

-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 40 — PERMISOS (primero se revoca todo; solo service_role ejecuta las RPC nuevas)
-- Las dos reemplazadas (personal, historial_personal) conservan sus permisos (create or replace no los cambia).
-- =====================================================================
revoke all on function public.geoportal_campo_personal_fijar(text, text, text, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_cuadrillas(text, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_cuadrilla_cambiar(text, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_catalogos(text, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_catalogo_cambiar(text, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_personal_actividad(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_personal_fijar(text, text, text, jsonb, text) to service_role;
grant execute on function public.geoportal_campo_cuadrillas(text, jsonb, text) to service_role;
grant execute on function public.geoportal_campo_cuadrilla_cambiar(text, jsonb, text) to service_role;
grant execute on function public.geoportal_campo_catalogos(text, text) to service_role;
grant execute on function public.geoportal_campo_catalogo_cambiar(text, jsonb, text) to service_role;
grant execute on function public.geoportal_campo_personal_actividad(text, text, text) to service_role;

-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 70 — PRUEBAS (dentro del ensayo; todo se deshace al final con el ERROR esperado)
-- Datos propios con prefijo ZTCOM (correos ztcom.*@emdupar.gov.co, cuadrillas «ZTCOM …», áreas y actividades «ZTCOM …»). Cada prueba cuenta SOLO sus filas.
-- Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table zt_res (n serial, nombre text, ok boolean, detalle text) on commit drop;
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into zt_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
-- llama una RPC como service_role; devuelve su jsonb o {"error": sqlstate, "msg": mensaje}
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
create function pg_temp.persona(r jsonb, p_email text) returns jsonb language sql as $f$
  select x from jsonb_array_elements(r -> 'personas') x where x ->> 'email' = p_email $f$;
create function pg_temp.act(p jsonb, p_codigo text) returns text language sql as $f$
  select x ->> 'origen' from jsonb_array_elements(p -> 'actividades') x where x ->> 'codigo' = p_codigo $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta) values
  ('ztcom.adm@emdupar.gov.co', 'ZTCOM Admin', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('ztcom.sup@emdupar.gov.co', 'ZTCOM Supervisor', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('ztcom.supacta@emdupar.gov.co', 'ZTCOM Sup Actas', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, true),
  ('ztcom.op1@emdupar.gov.co', 'ZTCOM Operario 1', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztcom.op2@emdupar.gov.co', 'ZTCOM Operario 2', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, true, false),
  ('ztcom.op3@emdupar.gov.co', 'ZTCOM Operario 3', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztcom.nada@emdupar.gov.co', 'ZTCOM Sin acceso', 'consulta', true, 'sin_restriccion', 'todos', true, false, false, false, false);

do $$
declare r jsonb; p jsonb; c1 bigint; c2 bigint; t0 timestamptz; v text;
  S constant text := '''ztcom.sup@emdupar.gov.co'''; A constant text := '''ztcom.adm@emdupar.gov.co'''; SA constant text := '''ztcom.supacta@emdupar.gov.co''';
begin
  -- 01 a 03: lectura y semilla
  r := pg_temp.rpc('public.geoportal_campo_personal(' || SA || ')');
  perform pg_temp.ok('01.01 el supervisor de actas ve Personal; puede todo en falso; yo = su correo', pg_temp.err(r) = 'OK' and r ->> 'yo' = 'ztcom.supacta@emdupar.gov.co'
    and not exists (select 1 from jsonb_each(r -> 'puede') x where x.value = 'true'::jsonb), left(r::text, 300));
  perform pg_temp.ok('01.02 la semilla trae las 4 áreas de D2', (select count(*) from jsonb_array_elements(r -> 'areas') x where x ->> 'codigo' in ('facturacion', 'cartera_scrr', 'perdidas', 'pqr_atencion')) = 4);
  perform pg_temp.ok('01.03 la semilla trae las 10 actividades de D4 (SCRR en tres)', (select count(*) from jsonb_array_elements(r -> 'actividades') x
    where x ->> 'codigo' in ('suspension', 'corte', 'reconexion', 'lectura', 'reparto', 'revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida', 'posible_perdida')) = 10);
  p := pg_temp.persona(r, 'ztcom.op1@emdupar.gov.co');
  perform pg_temp.ok('01.04 la persona conserva las claves de hoy y trae las nuevas', p ?& array['email', 'nombre', 'perfil', 'permisos', 'cargo', 'formularios', 'sin_asignacion', 'ultimo_cambio', 'propia', 'area', 'cuadrilla', 'actividades']
    and r ?& array['puede_editar', 'formularios', 'personas', 'yo', 'puede', 'areas', 'cuadrillas', 'actividades'] and p -> 'actividades' = '[]'::jsonb and p -> 'propia' = 'false'::jsonb, left(p::text, 300));
  perform pg_temp.ok('01.05 propia: true en la ficha de quien consulta', pg_temp.persona(r, 'ztcom.supacta@emdupar.gov.co') -> 'propia' = 'true'::jsonb);
  r := pg_temp.rpc('public.geoportal_campo_personal(' || S || ')');
  perform pg_temp.ok('01.06 el supervisor de campo puede cuadrilla, cuadrillas, actividades y formularios; no cargo, área ni catálogos',
    r -> 'puede' = '{"area": false, "cargo": false, "cuadrilla": true, "catalogos": false, "cuadrillas": true, "actividades": true, "formularios": true}'::jsonb, (r -> 'puede')::text);
  r := pg_temp.rpc('public.geoportal_campo_personal(' || A || ')');
  perform pg_temp.ok('01.07 el administrador puede todo', not exists (select 1 from jsonb_each(r -> 'puede') x where x.value <> 'true'::jsonb), (r -> 'puede')::text);
  r := pg_temp.rpc('public.geoportal_campo_personal(''ztcom.op1@emdupar.gov.co'')');
  perform pg_temp.ok('01.08 un operario no ve Personal (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc('public.geoportal_campo_cuadrillas(''ztcom.nada@emdupar.gov.co'')');
  perform pg_temp.ok('01.09 alguien sin acceso a campo no ve las cuadrillas (42501)', pg_temp.err(r) = '42501', r::text);

  -- 02: cuadrillas
  r := pg_temp.rpc('public.geoportal_campo_cuadrilla_cambiar(' || S || ', ''{"tipo": "crear", "nombre": "ZTCOM  Norte"}'')');
  c1 := (r ->> 'id')::bigint;
  perform pg_temp.ok('02.01 el supervisor crea una cuadrilla (espacios repetidos se reducen)', c1 is not null and (select nombre from campo.cuadrillas where id = c1) = 'ZTCOM Norte', r::text);
  r := pg_temp.rpc('public.geoportal_campo_cuadrilla_cambiar(' || S || ', ''{"tipo": "crear", "nombre": "ztcom norte"}'')');
  perform pg_temp.ok('02.02 nombre repetido sin distinguir mayúsculas ni espacios: 55000 con texto', pg_temp.err(r) = '55000' and r ->> 'msg' = 'Ya existe una cuadrilla con ese nombre', r::text);
  r := pg_temp.rpc('public.geoportal_campo_cuadrilla_cambiar(' || SA || ', ''{"tipo": "crear", "nombre": "ZTCOM Actas"}'')');
  perform pg_temp.ok('02.03 el supervisor de actas no crea cuadrillas (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc('public.geoportal_campo_cuadrilla_cambiar(' || S || ', ''{"tipo": "crear", "nombre": "ZTCOM Sur"}'')');
  c2 := (r ->> 'id')::bigint;
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "renombrar", "cuadrilla_id": %s, "nombre": "ZTCOM Sur"}'')', S, c2));
  perform pg_temp.ok('02.04 renombrar con el mismo nombre: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "renombrar", "cuadrilla_id": %s, "nombre": "ZTCOM Norte"}'')', S, c2));
  perform pg_temp.ok('02.05 renombrar al nombre de otra cuadrilla: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "renombrar", "cuadrilla_id": %s, "nombre": "ZTCOM Sur Oriente"}'')', S, c2));
  perform pg_temp.ok('02.06 renombrar', pg_temp.err(r) = 'OK' and (select nombre from campo.cuadrillas where id = c2) = 'ZTCOM Sur Oriente', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "suspension"}'')', S, c1));
  perform pg_temp.ok('02.07 agregar una actividad a la cuadrilla', pg_temp.err(r) = 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "corte"}'')', S, c1));
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "corte"}'')', S, c1));
  perform pg_temp.ok('02.08 agregar la misma actividad otra vez: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "no_existe"}'')', S, c1));
  perform pg_temp.ok('02.09 una actividad que no existe: 22023 con texto', pg_temp.err(r) = '22023' and r ->> 'msg' = 'Esa actividad no existe', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "suspension"}'')', S, c2));
  perform pg_temp.ok('02.10 la cuadrilla tiene sus actividades (y solo esas)', campo.f_cuadrilla_actividades(c1) = '{corte,suspension}' and campo.f_cuadrilla_actividades(c2) = '{suspension}');

  -- 03: personas en cuadrillas y actividades propias (D3)
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": 999999999}'')', S));
  perform pg_temp.ok('03.01 una cuadrilla que no existe', r ->> 'msg' = 'Esa cuadrilla no existe', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('03.02 el supervisor mete a una persona en la cuadrilla', pg_temp.err(r) = 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('03.03 meterla otra vez: 55000', pg_temp.err(r) = '55000' and r ->> 'msg' = 'Ya está en esa cuadrilla', r::text);
  p := pg_temp.persona(pg_temp.rpc('public.geoportal_campo_personal(' || S || ')'), 'ztcom.op1@emdupar.gov.co');
  perform pg_temp.ok('03.04 hereda las actividades de la cuadrilla (origen cuadrilla) y se ve la cuadrilla', pg_temp.act(p, 'suspension') = 'cuadrilla' and pg_temp.act(p, 'corte') = 'cuadrilla'
    and jsonb_array_length(p -> 'actividades') = 2 and p -> 'cuadrilla' = jsonb_build_object('id', c1, 'nombre', 'ZTCOM Norte', 'activa', true), left(p::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "corte"}'')', S));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "lectura"}'')', S));
  p := pg_temp.persona(pg_temp.rpc('public.geoportal_campo_personal(' || S || ')'), 'ztcom.op1@emdupar.gov.co');
  perform pg_temp.ok('03.05 además tiene propias: corte queda «ambas», lectura «propia»', pg_temp.act(p, 'corte') = 'ambas' and pg_temp.act(p, 'lectura') = 'propia' and jsonb_array_length(p -> 'actividades') = 3, left(p::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''quitar_actividad'', ''{"actividad": "suspension", "motivo": "ZTCOM prueba de quitar heredada"}'')', S));
  perform pg_temp.ok('03.06 quitar como propia una que viene de la cuadrilla: 55000 con el nombre de la cuadrilla', pg_temp.err(r) = '55000'
    and r ->> 'msg' = 'Esa actividad viene de la cuadrilla ZTCOM Norte: se quita en la cuadrilla', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''quitar_actividad'', ''{"actividad": "corte"}'')', S));
  perform pg_temp.ok('03.07 quitar una propia exige motivo', pg_temp.err(r) = '22023' and r ->> 'msg' like 'Escriba el motivo%', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''quitar_actividad'', ''{"actividad": "corte", "motivo": "corto"}'')', S));
  perform pg_temp.ok('03.08 motivo de menos de 10 caracteres: rechazado', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''quitar_actividad'', ''{"actividad": "corte", "motivo": "ZTCOM ya no hace cortes por su cuenta"}'')', S));
  p := pg_temp.persona(pg_temp.rpc('public.geoportal_campo_personal(' || S || ')'), 'ztcom.op1@emdupar.gov.co');
  perform pg_temp.ok('03.09 al quitar la propia, «ambas» vuelve a «cuadrilla»', pg_temp.err(r) = 'OK' and pg_temp.act(p, 'corte') = 'cuadrilla', left(p::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op2@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "suspension"}'')', S));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op3@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": %s}'')', S, c2));
  perform pg_temp.ok('03.10 persona sin cuadrilla con varias actividades propias (op2) y otra en la cuadrilla Sur (op3)', pg_temp.err(r) = 'OK');
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.sup@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('03.11 nadie cambia su propia ficha (400 con texto)', pg_temp.err(r) = '22023' and r ->> 'msg' = 'No puede cambiar su propia ficha', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "reparto"}'')', SA));
  perform pg_temp.ok('03.12 el supervisor de actas no cambia fichas (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.nada@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "reparto"}'')', S));
  perform pg_temp.ok('03.13 una persona sin acceso a campo ni acta no se gestiona', r ->> 'msg' = 'Esa persona no tiene acceso activo a Formularios de campo ni al acta', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''asignar_formulario'', ''{"formulario": "acta"}'')', S));
  perform pg_temp.ok('03.14 el supervisor de campo asigna formularios (antes solo el administrador)', pg_temp.err(r) = 'OK' and 'acta' = any (campo.f_formularios_asignados('ztcom.op1@emdupar.gov.co')), r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''quitar_formulario'', ''{"formulario": "acta", "motivo": "ZTCOM prueba de retiro de formulario"}'')', S));
  perform pg_temp.ok('03.15 y lo retira con motivo', pg_temp.err(r) = 'OK' and not ('acta' = any (campo.f_formularios_asignados('ztcom.op1@emdupar.gov.co'))), r::text);

  -- 04: área y cargo (solo administrador)
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_area'', ''{"area": "perdidas"}'')', S));
  perform pg_temp.ok('04.01 el supervisor no fija el área (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cargo'', ''{"cargo": "Operario"}'')', S));
  perform pg_temp.ok('04.02 el supervisor no fija el cargo (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_area'', ''{"area": "perdidas"}'')', A));
  perform pg_temp.ok('04.03 el administrador fija el área', pg_temp.err(r) = 'OK' and campo.f_area_vigente('ztcom.op1@emdupar.gov.co') = 'perdidas', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_area'', ''{"area": "perdidas"}'')', A));
  perform pg_temp.ok('04.04 la misma área otra vez: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cargo'', ''{"cargo": "ZTCOM Operario de pérdidas"}'')', A));
  perform pg_temp.ok('04.05 el administrador fija el cargo con la ruta nueva', pg_temp.err(r) = 'OK' and campo.f_cargo_vigente('ztcom.op1@emdupar.gov.co') = 'ZTCOM Operario de pérdidas', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_cambiar(%s, ''ztcom.op2@emdupar.gov.co'', ''fijar_cargo'', null, ''ZTCOM Operario antiguo'')', A));
  perform pg_temp.ok('04.06 la RPC publicada (la que usa la Edge de hoy) sigue funcionando igual', pg_temp.err(r) = 'OK' and campo.f_cargo_vigente('ztcom.op2@emdupar.gov.co') = 'ZTCOM Operario antiguo', r::text);

  -- 05: catálogos (solo administrador)
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "crear", "nombre": "ZTCOM Área de Prueba"}'')', S));
  perform pg_temp.ok('05.01 el supervisor no edita catálogos (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "crear", "nombre": "ZTCOM Área de Prueba"}'')', A));
  perform pg_temp.ok('05.02 crear un área: el servidor genera el código', r ->> 'codigo' = 'ztcom_area_de_prueba', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "crear", "nombre": "ztcom área de prueba"}'')', A));
  perform pg_temp.ok('05.03 nombre repetido: 55000 con texto', pg_temp.err(r) = '55000' and r ->> 'msg' = 'Ya existe un área con ese nombre', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "actividad", "tipo": "crear", "nombre": "ZTCOM Toma de lectura especial"}'')', A));
  perform pg_temp.ok('05.04 crear una actividad', r ->> 'codigo' = 'ztcom_toma_de_lectura_especial', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op3@emdupar.gov.co'', ''fijar_area'', ''{"area": "ztcom_area_de_prueba"}'')', A));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op3@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "ztcom_toma_de_lectura_especial"}'')', S));
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "desactivar", "codigo": "ztcom_area_de_prueba"}'')', A));
  perform pg_temp.ok('05.05 desactivar exige motivo', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "desactivar", "codigo": "ztcom_area_de_prueba", "motivo": "ZTCOM área de prueba que se retira"}'')', A));
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "actividad", "tipo": "desactivar", "codigo": "ztcom_toma_de_lectura_especial", "motivo": "ZTCOM actividad de prueba que se retira"}'')', A));
  p := pg_temp.persona(pg_temp.rpc('public.geoportal_campo_personal(' || S || ')'), 'ztcom.op3@emdupar.gov.co');
  perform pg_temp.ok('05.06 lo desactivado sigue en la persona con activa: false', p -> 'area' = '{"codigo": "ztcom_area_de_prueba", "nombre": "ZTCOM Área de Prueba", "activa": false}'::jsonb
    and exists (select 1 from jsonb_array_elements(p -> 'actividades') x where x ->> 'codigo' = 'ztcom_toma_de_lectura_especial' and x -> 'activa' = 'false'::jsonb), left(p::text, 500));
  r := pg_temp.rpc('public.geoportal_campo_personal(' || S || ')');
  perform pg_temp.ok('05.07 y no sale en los catálogos para asignar', not exists (select 1 from jsonb_array_elements(r -> 'areas') x where x ->> 'codigo' = 'ztcom_area_de_prueba')
    and not exists (select 1 from jsonb_array_elements(r -> 'actividades') x where x ->> 'codigo' = 'ztcom_toma_de_lectura_especial'));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_area'', ''{"area": "ztcom_area_de_prueba"}'')', A));
  perform pg_temp.ok('05.08 asignar un área desactivada: 400 con texto', r ->> 'msg' = 'Esa área está desactivada', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "ztcom_toma_de_lectura_especial"}'')', S));
  perform pg_temp.ok('05.09 asignar una actividad desactivada: 400 con texto', r ->> 'msg' = 'Esa actividad está desactivada', r::text);
  r := pg_temp.rpc('public.geoportal_campo_catalogos(' || SA || ')');
  perform pg_temp.ok('05.10 catalogos trae también las inactivas', exists (select 1 from jsonb_array_elements(r -> 'areas') x where x ->> 'codigo' = 'ztcom_area_de_prueba' and x -> 'activa' = 'false'::jsonb), left(r::text, 200));
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "activar", "codigo": "ztcom_area_de_prueba"}'')', A));
  perform pg_temp.ok('05.11 activar de nuevo', pg_temp.err(r) = 'OK' and (select activa from campo.areas_comercial where codigo = 'ztcom_area_de_prueba'), r::text);

  -- 06: quién puede hacer la actividad X
  r := pg_temp.rpc('public.geoportal_campo_personal_actividad(' || SA || ', ''suspension'')');
  perform pg_temp.ok('06.01 «quién puede» suspensión: op1 y op3 por cuadrilla, op2 propia (solo ZTCOM)',
    (select jsonb_object_agg(x ->> 'email', x ->> 'origen') from jsonb_array_elements(r -> 'personas') x where x ->> 'email' like 'ztcom.%')
      = '{"ztcom.op1@emdupar.gov.co": "cuadrilla", "ztcom.op2@emdupar.gov.co": "propia", "ztcom.op3@emdupar.gov.co": "cuadrilla"}'::jsonb, left(r::text, 500));
  perform pg_temp.ok('06.02 con la cuadrilla de cada uno', (select x -> 'cuadrilla' ->> 'nombre' from jsonb_array_elements(r -> 'personas') x where x ->> 'email' = 'ztcom.op3@emdupar.gov.co') = 'ZTCOM Sur Oriente'
    and (select x -> 'cuadrilla' from jsonb_array_elements(r -> 'personas') x where x ->> 'email' = 'ztcom.op2@emdupar.gov.co') = 'null'::jsonb);
  r := pg_temp.rpc('public.geoportal_campo_personal_actividad(' || SA || ', ''no_existe'')');
  perform pg_temp.ok('06.03 una actividad que no existe: 400', pg_temp.err(r) = '22023', r::text);

  -- 07: desactivar cuadrilla, sacar personas
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "desactivar", "cuadrilla_id": %s, "motivo": "ZTCOM se cierra la cuadrilla"}'')', S, c1));
  perform pg_temp.ok('07.01 no se desactiva una cuadrilla con miembros: 55000 con cuántos', pg_temp.err(r) = '55000' and r ->> 'msg' = 'La cuadrilla tiene 1 miembro: sáquelo antes de desactivarla', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": null}'')', S));
  perform pg_temp.ok('07.02 sacar a alguien de la cuadrilla exige motivo', pg_temp.err(r) = '22023' and r ->> 'msg' like 'Escriba el motivo%', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": null, "motivo": "ZTCOM pasa a trabajar sin cuadrilla"}'')', S));
  p := pg_temp.persona(pg_temp.rpc('public.geoportal_campo_personal(' || S || ')'), 'ztcom.op1@emdupar.gov.co');
  perform pg_temp.ok('07.03 al salir pierde las heredadas y conserva las propias', pg_temp.err(r) = 'OK' and p -> 'cuadrilla' = 'null'::jsonb
    and (select jsonb_agg(x ->> 'codigo') from jsonb_array_elements(p -> 'actividades') x) = '["lectura"]'::jsonb, left(p::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": null, "motivo": "ZTCOM otra vez sin cuadrilla"}'')', S));
  perform pg_temp.ok('07.04 sacarla otra vez: 55000', pg_temp.err(r) = '55000' and r ->> 'msg' = 'No está en ninguna cuadrilla', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "desactivar", "cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('07.05 desactivar exige motivo', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "desactivar", "cuadrilla_id": %s, "motivo": "ZTCOM se cierra la cuadrilla"}'')', S, c1));
  perform pg_temp.ok('07.06 sin miembros sí se desactiva (no se borra)', pg_temp.err(r) = 'OK' and (select not activa from campo.cuadrillas where id = c1), r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op2@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('07.07 meter a alguien en una cuadrilla desactivada: 400 con texto', r ->> 'msg' = 'Esa cuadrilla está desactivada', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "lectura"}'')', S, c1));
  perform pg_temp.ok('07.08 agregar actividad a una cuadrilla desactivada: 400', r ->> 'msg' = 'Esa cuadrilla está desactivada', r::text);
  r := pg_temp.rpc('public.geoportal_campo_cuadrillas(' || SA || ')');
  perform pg_temp.ok('07.09 cuadrillas: por omisión solo las activas', not exists (select 1 from jsonb_array_elements(r -> 'cuadrillas') x where (x ->> 'id')::bigint = c1)
    and exists (select 1 from jsonb_array_elements(r -> 'cuadrillas') x where (x ->> 'id')::bigint = c2 and (x ->> 'n_miembros')::int = 1 and x -> 'miembros' -> 0 ->> 'email' = 'ztcom.op3@emdupar.gov.co'
                and x -> 'actividades' = '[{"codigo": "suspension", "nombre": "Suspensión", "activa": true}]'::jsonb), left(r::text, 500));
  r := pg_temp.rpc('public.geoportal_campo_cuadrillas(' || SA || ', ''{"incluir_inactivas": true}'')');
  perform pg_temp.ok('07.10 con incluir_inactivas sale la desactivada', exists (select 1 from jsonb_array_elements(r -> 'cuadrillas') x where (x ->> 'id')::bigint = c1 and x -> 'activa' = 'false'::jsonb));
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "activar", "cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('07.11 activar de nuevo', pg_temp.err(r) = 'OK' and (select activa from campo.cuadrillas where id = c1), r::text);

  -- 08: historial
  r := pg_temp.rpc('public.geoportal_campo_historial_personal(' || SA || ', ''{"persona": "ztcom.op1@emdupar.gov.co"}'')');
  perform pg_temp.ok('08.01 historial de la persona: tipos nuevos con valor_codigo, valor_nombre y clave', (select count(*) from jsonb_array_elements(r -> 'eventos') x
     where x ->> 'tipo_evento' in ('fijar_cuadrilla', 'asignar_actividad', 'quitar_actividad', 'fijar_area') and x ? 'valor_codigo' and x ->> 'clave' like 'p:%') = 6
    and exists (select 1 from jsonb_array_elements(r -> 'eventos') x where x ->> 'tipo_evento' = 'fijar_area' and x ->> 'valor_nombre' = 'Pérdidas' and x -> 'vigente' = 'true'::jsonb), left(r::text, 300));
  perform pg_temp.ok('08.02 vigente: el último por grupo (la cuadrilla vigente es la salida)', (select x -> 'vigente' from jsonb_array_elements(r -> 'eventos') x where x ->> 'tipo_evento' = 'fijar_cuadrilla' order by (x ->> 'id')::bigint desc limit 1) = 'true'::jsonb
    and (select count(*) from jsonb_array_elements(r -> 'eventos') x where x ->> 'tipo_evento' = 'fijar_cuadrilla' and x -> 'vigente' = 'true'::jsonb) = 1);
  r := pg_temp.rpc(format('public.geoportal_campo_historial_personal(%s, ''{"cuadrilla_id": %s}'')', SA, c1));
  perform pg_temp.ok('08.03 historial de la cuadrilla: sus eventos (persona nula) y la entrada y salida de op1',
    (select count(*) from jsonb_array_elements(r -> 'eventos') x where x -> 'persona' = 'null'::jsonb and x ->> 'tipo_evento' like 'cuadrilla\_%' and x ->> 'clave' like 'c:%') = 5
    and (select count(*) from jsonb_array_elements(r -> 'eventos') x where x ->> 'persona' = 'ztcom.op1@emdupar.gov.co') = 2
    and exists (select 1 from jsonb_array_elements(r -> 'eventos') x where x ->> 'tipo_evento' = 'cuadrilla_agregar_actividad' and x ->> 'valor_nombre' = 'Corte')
    and r -> 'siguiente' = 'null'::jsonb, left(r::text, 400));
  r := pg_temp.rpc('public.geoportal_campo_historial_personal(' || SA || ', ''{"cuadrilla_id": 999999999}'')');
  perform pg_temp.ok('08.04 historial de una cuadrilla que no existe: 400', pg_temp.err(r) = '22023', r::text);

  -- 09: nada se borra; los CHECK de producción; permisos
  begin delete from campo.cuadrillas where id = c1; perform pg_temp.ok('09.01 una cuadrilla no se borra', false);
  exception when others then perform pg_temp.ok('09.01 una cuadrilla no se borra', sqlerrm like '%no se borra%', sqlerrm); end;
  begin update campo.areas_comercial set codigo = 'ztcom_otro' where codigo = 'ztcom_area_de_prueba'; perform pg_temp.ok('09.02 el código de un área no cambia', false);
  exception when others then perform pg_temp.ok('09.02 el código de un área no cambia', sqlerrm like '%no cambian%', sqlerrm); end;
  begin delete from campo.cuadrilla_eventos where cuadrilla_id = c1; perform pg_temp.ok('09.03 los eventos de cuadrilla son de solo agregar', false);
  exception when others then perform pg_temp.ok('09.03 los eventos de cuadrilla son de solo agregar', sqlerrm like '%solo agregar%', sqlerrm); end;
  begin truncate campo.actividades; perform pg_temp.ok('09.04 el catálogo de actividades no se vacía', false);
  exception when others then perform pg_temp.ok('09.04 el catálogo de actividades no se vacía', sqlerrm like '%no se borra%', sqlerrm); end;
  begin insert into campo.personal_eventos (persona, tipo_evento, autor) values ('ztcom.op1@emdupar.gov.co', 'fijar_area', 'ztcom.adm@emdupar.gov.co'); perform pg_temp.ok('09.05 CHECK: fijar_area sin valor', false);
  exception when check_violation then perform pg_temp.ok('09.05 CHECK: fijar_area sin valor', true); end;
  begin insert into campo.personal_eventos (persona, tipo_evento, valor, autor) values ('ztcom.op1@emdupar.gov.co', 'fijar_cuadrilla', 'abc', 'ztcom.adm@emdupar.gov.co'); perform pg_temp.ok('09.06 CHECK: cuadrilla no numérica', false);
  exception when check_violation then perform pg_temp.ok('09.06 CHECK: cuadrilla no numérica', true); end;
  perform pg_temp.ok('09.07 las 6 RPC nuevas: solo service_role las ejecuta', (select bool_and(has_function_privilege('service_role', f, 'execute') and not has_function_privilege('anon', f, 'execute')
      and not has_function_privilege('authenticated', f, 'execute')) from unnest(array['public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)', 'public.geoportal_campo_cuadrillas(text,jsonb,text)',
      'public.geoportal_campo_cuadrilla_cambiar(text,jsonb,text)', 'public.geoportal_campo_catalogos(text,text)', 'public.geoportal_campo_catalogo_cambiar(text,jsonb,text)', 'public.geoportal_campo_personal_actividad(text,text,text)']) f));
  perform pg_temp.ok('09.08 las funciones internas nuevas: nadie fuera del dueño', (select bool_and(not has_function_privilege(r_, f, 'execute')) from unnest(array['campo.f_quien_puede(text)', 'campo.f_actividades_persona(text)',
      'campo.f_persona_comercial(text)', 'campo.f_miembros_cuadrillas()', 'campo.f_motivo_personal(text,boolean)']) f, unnest(array['anon', 'authenticated', 'service_role']) r_));
  perform pg_temp.ok('09.09 las tablas nuevas: sin permisos para anon, authenticated ni service_role', (select bool_and(not has_table_privilege(r_, t, 'select') and not has_table_privilege(r_, t, 'insert'))
      from unnest(array['campo.areas_comercial', 'campo.actividades', 'campo.catalogo_eventos', 'campo.cuadrillas', 'campo.cuadrilla_eventos']) t, unnest(array['anon', 'authenticated', 'service_role']) r_));
  perform pg_temp.ok('09.10 las tablas nuevas tienen RLS', (select bool_and(relrowsecurity) from pg_class where oid in ('campo.areas_comercial'::regclass, 'campo.actividades'::regclass, 'campo.catalogo_eventos'::regclass,
      'campo.cuadrillas'::regclass, 'campo.cuadrilla_eventos'::regclass)));
  if to_regprocedure('redes.f_funciones_sin_where()') is not null then
    execute 'select count(*) from redes.f_funciones_sin_where()' into v;
  else v := '0'; end if;
  perform pg_temp.ok('09.11 ninguna función con DELETE o UPDATE sin WHERE: redes.f_funciones_sin_where (si existe) y la misma regla sobre campo y geoportal_campo_*',
    v = '0' and (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0, 'redes: ' || v);
  perform pg_temp.ok('09.12 la auditoría registró los cambios de las pruebas', (select count(*) from public.geoportal_auditoria where email like 'ztcom.%' and accion like 'campo\_%') >= 25);

  -- 10: tiempo (Personal completa como supervisor)
  t0 := clock_timestamp();
  r := pg_temp.rpc('public.geoportal_campo_personal(' || S || ')');
  perform pg_temp.ok('10.01 Personal completa en menos de 2 s', pg_temp.err(r) = 'OK' and clock_timestamp() - t0 < interval '2 s', (clock_timestamp() - t0)::text);
end $$;

do $$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from zt_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $$;

rollback;
