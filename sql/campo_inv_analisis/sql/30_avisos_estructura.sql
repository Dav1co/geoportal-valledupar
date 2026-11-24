-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 30 — AVISOS DEL ANÁLISIS DE CONTRATO: estructura (decisiones de David del 23-nov, §2 y §6 del encargo)
-- Toda observación es un AVISO al supervisor (ninguna genera actividad sola). El aviso es una fila de campo.derivadas enlazada a la
-- observación por observacion_id (origen_id queda nulo en esas filas). Desde el aviso, el supervisor «Crea actividad» (otra derivada
-- con el mismo observacion_id y un destino propio) o lo cierra como hoy.
-- Datos personales de «Actualización de datos» (Ley 1581): tabla aparte, sin permisos para la API, solo la lee una RPC del supervisor.
-- Todas las tablas nuevas: solo inserción, RLS activa sin políticas (como todo campo), revoke all a public, anon, authenticated y
-- service_role, y SELECT explícito a homelab_lectura (respaldo cifrado del Dell; cambio de D2, 23-nov 22:42), sin ALTER DEFAULT PRIVILEGES.
-- Si una reversa conservó la estructura (nada se borra), no se repite: se reutiliza.
-- =====================================================================
do $estructura$
begin
  if to_regclass('campo.analisis_observaciones') is not null then
    raise notice 'La estructura de los avisos se conservó de una reversa: se reutiliza';
    return;
  end if;

  create table campo.analisis_observaciones (
    id                 uuid primary key default gen_random_uuid(),
    contrato           text not null check (contrato ~ '^\d{1,12}$' and contrato <> '99999999'),
    tipo               text not null check (tipo in ('desocupado', 'direccion_errada', 'actualizacion_datos', 'otra')),
    texto              text check (texto is null or (length(texto) between 3 and 120 and texto = btrim(texto))),
    direccion_correcta text check (direccion_correcta is null or (length(direccion_correcta) between 3 and 120 and direccion_correcta = btrim(direccion_correcta))),
    autor              text not null check (autor = lower(autor) and position('@' in autor) > 1),
    creado_en          timestamptz not null default clock_timestamp(),
    ip                 text check (ip is null or length(ip) <= 64),
    constraint analisis_observaciones_texto_ck check ((tipo = 'otra') = (texto is not null)),
    constraint analisis_observaciones_direccion_ck check (direccion_correcta is null or tipo = 'direccion_errada')
  );
  create index analisis_observaciones_contrato_idx on campo.analisis_observaciones (contrato, creado_en desc);
  create trigger t_solo_agregar before delete or update on campo.analisis_observaciones for each row execute function campo.f_solo_agregar();
  create trigger t_solo_agregar_trunc before truncate on campo.analisis_observaciones for each statement execute function campo.f_solo_agregar();
  comment on table campo.analisis_observaciones is 'Observaciones que marca quien tiene Análisis de contrato (desocupado, dirección errada, actualización de datos, otra). Cada una crea un aviso en campo.derivadas. Solo inserción. Sin nombres, cédulas ni teléfonos: esos van solo en campo.analisis_observacion_datos.';

  create table campo.analisis_observacion_datos (
    observacion_id uuid primary key references campo.analisis_observaciones (id),
    datos          jsonb not null check (jsonb_typeof(datos) = 'object' and datos <> '{}'::jsonb and octet_length(datos::text) <= 1024
                                         and (datos - array['nombre', 'cedula', 'telefono', 'correo', 'relacion']) = '{}'::jsonb),
    registrado_en  timestamptz not null default clock_timestamp()
  );
  create trigger t_solo_agregar before delete or update on campo.analisis_observacion_datos for each row execute function campo.f_solo_agregar();
  create trigger t_solo_agregar_trunc before truncate on campo.analisis_observacion_datos for each statement execute function campo.f_solo_agregar();
  comment on table campo.analisis_observacion_datos is 'SENSIBLE (Ley 1581): datos de contacto de «Actualización de datos» (nombre, cédula, teléfono, correo, relación con el predio). Solo los lee geoportal_campo_aviso_datos (supervisor de campo y administrador), con lectura auditada; nunca en listas, exportaciones generales ni mapa. homelab_lectura la lee solo para el respaldo cifrado. Solo inserción: si estaban mal, se anulan con motivo (campo.analisis_observacion_anulaciones).';

  create table campo.analisis_observacion_anulaciones (
    observacion_id uuid primary key references campo.analisis_observacion_datos (observacion_id),
    motivo         text not null check (length(btrim(motivo)) between 10 and 300),
    autor          text not null check (autor = lower(autor) and position('@' in autor) > 1),
    creado_en      timestamptz not null default clock_timestamp(),
    ip             text check (ip is null or length(ip) <= 64)
  );
  create trigger t_solo_agregar before delete or update on campo.analisis_observacion_anulaciones for each row execute function campo.f_solo_agregar();
  create trigger t_solo_agregar_trunc before truncate on campo.analisis_observacion_anulaciones for each statement execute function campo.f_solo_agregar();
  comment on table campo.analisis_observacion_anulaciones is 'Anulación de los datos de contacto de una observación (una por observación), con motivo. Los datos quedan guardados; anulados, ya no se muestran.';

  alter table campo.analisis_observaciones enable row level security;
  alter table campo.analisis_observacion_datos enable row level security;
  alter table campo.analisis_observacion_anulaciones enable row level security;
  revoke all on campo.analisis_observaciones, campo.analisis_observacion_datos, campo.analisis_observacion_anulaciones from public, anon, authenticated, service_role;
  grant select on campo.analisis_observaciones, campo.analisis_observacion_datos, campo.analisis_observacion_anulaciones to homelab_lectura;

  -- campo.derivadas: el aviso y la actividad que crea el supervisor se enlazan a la observación; las de las revisiones no cambian
  alter table campo.derivadas add column observacion_id uuid references campo.analisis_observaciones (id);
  alter table campo.derivadas add column destino text check (destino is null or destino ~ '^tipo:[a-z][a-z0-9_]{1,59}$');
  alter table campo.derivadas alter column origen_id drop not null;
  alter table campo.derivadas add constraint derivadas_origen_ck check (num_nonnulls(origen_id, observacion_id) = 1);
  alter table campo.derivadas add constraint derivadas_destino_ck check (destino is null or observacion_id is not null);
  alter table campo.derivadas add constraint derivadas_observacion_id_actividad_key unique (observacion_id, actividad);
end $estructura$;

-- Catálogo de derivadas: los 4 avisos y la actividad que crea el supervisor (sin destinos propios). Si una reversa los desactivó, se reactivan.
insert into campo.derivadas_catalogo (codigo, nombre, destinos, destino_omision, activa, orden, autor) values
  ('aviso_desocupado', 'Aviso: predio desocupado', '{}', null, true, 60, 'migracion@geoportal'),
  ('aviso_direccion_errada', 'Aviso: dirección errada', '{}', null, true, 61, 'migracion@geoportal'),
  ('aviso_actualizacion_datos', 'Aviso: actualización de datos', '{}', null, true, 62, 'migracion@geoportal'),
  ('aviso_otra', 'Aviso: otra observación', '{}', null, true, 63, 'migracion@geoportal'),
  ('actividad_supervisor', 'Actividad creada por el supervisor', '{}', null, true, 64, 'migracion@geoportal')
on conflict (codigo) do update set activa = true;
