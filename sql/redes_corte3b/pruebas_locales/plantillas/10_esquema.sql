-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 10 — GUARDIA Y TABLAS DE LA FICHA COMO «PERFIL» DEL ACTIVO (§22 y §23 de la bitácora)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew).
-- · Presupone el Corte 3a aplicado (y por lo tanto el 1a y el 2): lo comprueba con la huella md5 del conjunto de funciones de redes y de v_epicrisis.
-- · No toca ningún objeto vivo de otros esquemas. Del 1a solo AGREGA filas a redes.activo_versiones (versión nueva por edición, carga_id nulo)
--   y a redes.activo_origen (corrección del origen); las dos ya son de solo inserción y admiten filas de la ficha.
-- · Del 3a REEMPLAZA (create or replace, mismas columnas y firma): la vista redes.v_epicrisis (le suma los cambios de la ficha) y la RPC
--   geoportal_redes_activo_buscar (busca también por alias y placa). La reversa deja las dos con su texto del 3a.
-- · Todo objeto nuevo: revoke all a public, anon, authenticated y service_role (40); RLS activa sin políticas.
-- =====================================================================
do $$
begin
  if to_regclass('redes.intervenciones') is null then raise exception 'Falta el Corte 3a (redes.intervenciones): aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_3A}}' then
    raise exception 'Las funciones de redes no son las del Corte 3a (o el Corte 3b ya está aplicado): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> '{{MD5_V_EPICRISIS_3A}}' then raise exception 'La vista v_epicrisis no es la del Corte 3a: deténgase y avise'; end if;
  if to_regclass('redes.ficha_ediciones') is not null then raise exception 'redes.ficha_ediciones ya existe: el Corte 3b parece aplicado'; end if;
  if not exists (select 1 from storage.buckets where id = 'redes-evidencias' and not public) then raise exception 'Falta el bucket privado redes-evidencias del Corte 2'; end if;
end $$;

-- Cada edición de la ficha (datos, alias, placa, origen o foto principal): qué cambió (de A a B), con autor, fecha y motivo. Solo inserción.
-- Si la edición toca datos del activo, crea una VERSIÓN nueva en activo_versiones (carga_id nulo) y aquí queda su número.
create table redes.ficha_ediciones (
  id        bigint generated always as identity primary key,
  activo_id bigint not null references redes.activos (id),
  version   integer,                                          -- la versión que creó (nula si solo cambió alias, placa, origen o foto)
  cambios   jsonb not null check (jsonb_typeof(cambios) = 'array' and jsonb_array_length(cambios) between 1 and 40),   -- [{campo, rotulo, antes, despues}]
  motivo    text not null check (length(btrim(motivo)) between 10 and 1000),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
create index ix_fe_activo on redes.ficha_ediciones (activo_id, id desc);

-- Alias propio del activo («Tanque de La Popa») y placa de almacén o número de inventario. Eventos; lo vigente es el último por campo (nulo = se quitó).
create table redes.activo_identificador_eventos (
  id         bigint generated always as identity primary key,
  activo_id  bigint not null references redes.activos (id),
  campo      text not null check (campo in ('alias', 'placa')),
  valor      text check (valor is null or length(btrim(valor)) between 1 and 60),
  edicion_id bigint not null references redes.ficha_ediciones (id),
  autor      text not null,
  creado_en  timestamptz not null default clock_timestamp()
);
create index ix_aie_activo on redes.activo_identificador_eventos (activo_id, campo, id desc);
create index ix_aie_valor on redes.activo_identificador_eventos (lower(valor));

-- Foto de perfil del activo (la sube el administrador; el supervisor de distribución desde el Corte 4). Reserva de la ruta y la foto fijada.
create table redes.foto_perfil_preparaciones (
  ruta      text primary key check (ruta ~ '^activos/[0-9]{4}-[0-9]{2}/[0-9]{1,12}/[0-9a-f-]{36}\.jpg$'),
  activo_id bigint not null references redes.activos (id),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
create table redes.activo_fotos_perfil (
  id           bigint generated always as identity primary key,
  activo_id    bigint not null references redes.activos (id),
  ruta_storage text not null unique references redes.foto_perfil_preparaciones (ruta),
  bytes        integer not null check (bytes > 0),
  mime         text not null check (mime = 'image/jpeg'),
  edicion_id   bigint not null references redes.ficha_ediciones (id),
  autor        text not null,
  creado_en    timestamptz not null default clock_timestamp()
);
create index ix_afp_activo on redes.activo_fotos_perfil (activo_id, id desc);

do $$
declare t text;
begin
  foreach t in array array['ficha_ediciones', 'activo_identificador_eventos', 'foto_perfil_preparaciones', 'activo_fotos_perfil'] loop
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
end $$;
