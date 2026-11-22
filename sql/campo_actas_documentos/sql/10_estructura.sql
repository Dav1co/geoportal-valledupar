-- =====================================================================
-- COMERCIAL 21-NOV · (b) ACTAS · 10 — ESTRUCTURA
-- D7 y B5 (David, 21-nov): 9 formularios con PDF y tres firmas (operario obligatoria; usuario y testigo opcionales). D8: corrección = PDF nuevo -v2.
-- D10: el PDF se guarda en un bucket privado con su sha256; salida.envios NO cambia. D12/D13: actividades derivadas y absorción de req_cambio_medidor.
-- Nada se borra: catálogos y firmas en borrador se actualizan solo antes de registrar; lo registrado y los eventos son de solo agregar.
-- =====================================================================

-- ---------- 1. Formularios con PDF y firmas (el servidor marca; la pantalla no fija la lista) ----------
create table campo.formularios_documento (
  formulario      text primary key check (formulario ~ '^(acta|tipo:[a-z][a-z0-9_]{1,59})$'),
  sigla           text not null check (sigla ~ '^[A-Z]{2,6}$'),
  lleva_pdf       boolean not null default true,
  firma_operario  text not null check (firma_operario in ('obligatoria', 'no')),
  firma_usuario   text not null check (firma_usuario in ('opcional', 'no')),
  firma_testigo   text not null check (firma_testigo in ('opcional', 'no')),
  activo          boolean not null default true,
  autor           text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en       timestamptz not null default clock_timestamp()
);
comment on table campo.formularios_documento is 'Comercial 21-nov (D7, B5): formularios con valor probatorio que llevan PDF y firmas con el dedo. Sigla del nombre del PDF (contrato del Dell §1: ITEC, REV; SCRR es propuesta). No se borra: se desactiva.';
insert into campo.formularios_documento (formulario, sigla, firma_operario, firma_usuario, firma_testigo, autor) values
  ('acta', 'ITEC', 'obligatoria', 'opcional', 'opcional', 'migracion@geoportal'),
  ('tipo:revision_previa', 'REV', 'obligatoria', 'opcional', 'opcional', 'migracion@geoportal'),
  ('tipo:revision_pqr', 'REV', 'obligatoria', 'opcional', 'opcional', 'migracion@geoportal'),
  ('tipo:instalacion_medidor', 'REV', 'obligatoria', 'opcional', 'opcional', 'migracion@geoportal'),
  ('tipo:instalacion_acometida', 'REV', 'obligatoria', 'opcional', 'opcional', 'migracion@geoportal'),
  ('tipo:suspension', 'SCRR', 'obligatoria', 'opcional', 'opcional', 'migracion@geoportal'),
  ('tipo:corte', 'SCRR', 'obligatoria', 'opcional', 'opcional', 'migracion@geoportal'),
  ('tipo:reinstalacion', 'SCRR', 'obligatoria', 'opcional', 'opcional', 'migracion@geoportal'),
  ('tipo:reconexion_servicio', 'SCRR', 'obligatoria', 'opcional', 'opcional', 'migracion@geoportal');

-- ---------- 2. Firmas con el dedo (JPEG pequeño, como en Aseo) ----------
-- Se guardan ANTES de registrar (el id del registro ya existe: reporte_id de preparar_subida o acta_id) y se pueden repetir hasta registrar; al registrar
-- quedan definitivas (el disparador impide cambiarlas). El nombre del usuario o del testigo es dato personal: solo en el PDF interno y en pantalla con permiso.
create table campo.firmas (
  id            bigint generated always as identity primary key,
  esquema       text not null check (esquema in ('campo', 'acta')),
  registro_id   uuid not null,
  rol           text not null check (rol in ('operario', 'usuario', 'testigo')),
  estado        text not null check (estado in ('firmo', 'no_firmo', 'nadie_atendio', 'quitada')),
  nombre        text check (nombre is null or length(btrim(nombre)) between 2 and 120),
  imagen        bytea check (imagen is null or octet_length(imagen) between 200 and 40960),
  huella        text check (huella is null or huella ~ '^[0-9a-f]{64}$'),
  autor         text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en     timestamptz not null default clock_timestamp(),
  cambiado_en   timestamptz not null default clock_timestamp(),
  unique (esquema, registro_id, rol),
  constraint firmas_imagen_ck check ((estado = 'firmo') = (imagen is not null) and (imagen is null) = (huella is null)),
  constraint firmas_rol_ck check ((rol = 'operario' and estado in ('firmo', 'quitada')) or (rol = 'usuario') or (rol = 'testigo' and estado in ('firmo', 'quitada'))),
  constraint firmas_nombre_ck check (estado not in ('nadie_atendio', 'quitada') or nombre is null)
);
comment on table campo.firmas is 'Comercial 21-nov (B5): firmas del operario (obligatoria), del usuario y del testigo (opcionales) de los formularios con PDF. Borrador hasta registrar; después, definitivas. No se borran: «quitada» antes de registrar.';
create index firmas_registro_idx on campo.firmas (esquema, registro_id);

-- ---------- 3. PDF guardados (uno por registro; nunca se reescribe) ----------
create table campo.documentos_pdf (
  id            bigint generated always as identity primary key,
  esquema       text not null check (esquema in ('campo', 'acta')),
  registro_id   uuid not null,
  formulario    text not null references campo.formularios_documento (formulario),
  version       integer not null check (version between 1 and 99),
  nombre        text not null check (nombre ~ '^[0-9]{14}-[A-Z]{2,6}-[A-Z0-9-]{3,40}(-v[0-9]{1,2})?\.pdf$'),
  ruta          text not null unique check (ruta ~ '^(campo|acta)/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}/[^/]+\.pdf$'),
  sha256        text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  bytes         integer not null check (bytes between 200 and 26214400),
  fotos_omitidas integer not null default 0 check (fotos_omitidas >= 0),
  generado_por  text not null check (generado_por = lower(generado_por) and position('@' in generado_por) > 1),
  generado_en   timestamptz not null default clock_timestamp(),
  unique (esquema, registro_id)
);
comment on table campo.documentos_pdf is 'Comercial 21-nov (D6, D8, D10): el PDF único de cada registro con valor probatorio, guardado en el bucket privado actas-pdf con su sha256. Se genera una sola vez; nunca se reescribe. Solo agregar.';
create table campo.documento_intentos (
  id           bigint generated always as identity primary key,
  esquema      text not null check (esquema in ('campo', 'acta')),
  registro_id  uuid not null,
  resultado    text not null check (resultado in ('fallo')),
  detalle      text check (detalle is null or length(detalle) <= 300),
  autor        text not null,
  creado_en    timestamptz not null default clock_timestamp()
);
comment on table campo.documento_intentos is 'Comercial 21-nov: intentos fallidos de generar el PDF (el registro no se pierde; se reintenta desde las pantallas). Solo agregar.';

-- ---------- 4. Actividades derivadas (D12, D13) ----------
create table campo.derivadas_catalogo (
  codigo          text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,39}$'),
  nombre          text not null check (length(btrim(nombre)) between 2 and 80),
  destinos        text[] not null default '{}',
  destino_omision text,
  activa          boolean not null default true,
  orden           integer not null,
  autor           text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en       timestamptz not null default clock_timestamp(),
  constraint derivadas_catalogo_destino_ck check (destino_omision is null or destino_omision = any (destinos))
);
comment on table campo.derivadas_catalogo is 'Comercial 21-nov (D12): actividades que puede originar una revisión («¿Da lugar a otras actividades?») y qué formulario las atiende. Fuga por fuera de la casa: por omisión Instalación de medidor; se puede escoger Revisiones generales. Dentro de la casa no se atiende.';
insert into campo.derivadas_catalogo (codigo, nombre, destinos, destino_omision, orden, autor) values
  ('cambio_medidor', 'Cambio de medidor', '{tipo:instalacion_medidor}', 'tipo:instalacion_medidor', 1, 'migracion@geoportal'),
  ('instalacion_medidor', 'Instalación de medidor', '{tipo:instalacion_medidor}', 'tipo:instalacion_medidor', 2, 'migracion@geoportal'),
  ('accesorios', 'Instalación o cambio de accesorios', '{tipo:instalacion_medidor}', 'tipo:instalacion_medidor', 3, 'migracion@geoportal'),
  ('reubicacion_cajilla', 'Reubicación de cajilla', '{tipo:instalacion_medidor}', 'tipo:instalacion_medidor', 4, 'migracion@geoportal'),
  ('fuga_externa', 'Reparación de fuga por fuera de la casa (acometida, antes del medidor)', '{tipo:instalacion_medidor,tipo:revision_previa}', 'tipo:instalacion_medidor', 5, 'migracion@geoportal'),
  ('posible_perdida', 'Posible pérdida', '{acta}', 'acta', 6, 'migracion@geoportal'),
  ('otra', 'Otra', '{}', null, 7, 'migracion@geoportal');

create table campo.derivadas (
  id           bigint generated always as identity primary key,
  origen_id    uuid not null references campo.reportes (id),
  contrato     text,
  actividad    text not null references campo.derivadas_catalogo (codigo),
  creado_en    timestamptz not null default clock_timestamp(),
  unique (origen_id, actividad)
);
comment on table campo.derivadas is 'Comercial 21-nov: una fila por actividad marcada en «¿Da lugar a otras actividades?» de una revisión o instalación. La crea el disparador al registrar. Solo agregar; pendiente o atendida sale de campo.derivada_eventos.';
create table campo.derivada_eventos (
  id            bigint generated always as identity primary key,
  derivada_id   bigint not null references campo.derivadas (id),
  tipo_evento   text not null check (tipo_evento in ('atendida', 'atendida_fuera', 'anulada')),
  esquema       text check (esquema in ('campo', 'acta')),
  registro_id   uuid,
  motivo        text check (motivo is null or length(btrim(motivo)) between 10 and 300),
  autor         text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en     timestamptz not null default clock_timestamp(),
  constraint derivada_eventos_ck check ((tipo_evento = 'atendida') = (registro_id is not null and esquema is not null) and (tipo_evento = 'atendida' or motivo is not null))
);
create unique index derivada_eventos_una_idx on campo.derivada_eventos (derivada_id);
comment on table campo.derivada_eventos is 'Comercial 21-nov: cierre de cada derivada (una sola vez): atendida por un registro, atendida fuera del sistema o anulada (estas dos con motivo). Solo agregar.';
create table campo.origen_vinculos (
  id          bigint generated always as identity primary key,
  reporte_id  uuid not null unique references campo.reportes (id),
  acta_id     uuid not null references acta.actas (id),
  autor       text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en   timestamptz not null default clock_timestamp()
);
comment on table campo.origen_vinculos is 'Comercial 21-nov: posible pérdida → revisión. La revisión indica qué acta de posible pérdida (AI) la originó. Solo agregar.';

-- ---------- 5. Campos nuevos en los 4 REV: «¿Da lugar a otras actividades?» ----------
insert into campo.tipo_campos (tipo_id, codigo, nombre, tipo_dato, obligatorio, opciones, maximo, ayuda, sensible, orden, activo, seccion, visible_si)
select t.id, x.codigo, x.nombre, x.tipo_dato, false, x.opciones, x.maximo, x.ayuda, false, x.orden, true, '11. Actividades derivadas', x.visible_si
  from campo.tipos_reporte t
 cross join (values
   ('da_lugar', '¿Da lugar a otras actividades?', 'opciones',
    (select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre) order by c.orden) from campo.derivadas_catalogo c), null::numeric,
    'Marque las que correspondan; el supervisor las ve como pendientes hasta que se atiendan.', 1101, null::jsonb),
   ('da_lugar_otra', '¿Cuál otra actividad?', 'texto', null::jsonb, 120::numeric, null, 1102, '{"campo": "da_lugar", "es": "otra"}'::jsonb)
 ) as x(codigo, nombre, tipo_dato, opciones, maximo, ayuda, orden, visible_si)
 where t.codigo in ('revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida')
   and not exists (select 1 from campo.tipo_campos c where c.tipo_id = t.id and c.codigo = x.codigo);

-- ---------- 6. Bucket privado de los PDF ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('actas-pdf', 'actas-pdf', false, 26214400, array['application/pdf']);

-- ---------- 7. Protección ----------
create trigger t_no_borrar before update or delete on campo.formularios_documento for each row execute function campo.f_no_borrar_catalogo();
create trigger t_no_vaciar before truncate on campo.formularios_documento for each statement execute function campo.f_no_borrar_catalogo();
create trigger t_no_borrar before update or delete on campo.derivadas_catalogo for each row execute function campo.f_no_borrar_catalogo();
create trigger t_no_vaciar before truncate on campo.derivadas_catalogo for each statement execute function campo.f_no_borrar_catalogo();
create trigger t_solo_agregar before update or delete on campo.documentos_pdf for each row execute function campo.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on campo.documentos_pdf for each statement execute function campo.f_solo_agregar();
create trigger t_solo_agregar before update or delete on campo.documento_intentos for each row execute function campo.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on campo.documento_intentos for each statement execute function campo.f_solo_agregar();
create trigger t_solo_agregar before update or delete on campo.derivadas for each row execute function campo.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on campo.derivadas for each statement execute function campo.f_solo_agregar();
create trigger t_solo_agregar before update or delete on campo.derivada_eventos for each row execute function campo.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on campo.derivada_eventos for each statement execute function campo.f_solo_agregar();
create trigger t_solo_agregar before update or delete on campo.origen_vinculos for each row execute function campo.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on campo.origen_vinculos for each statement execute function campo.f_solo_agregar();
alter table campo.formularios_documento enable row level security;
alter table campo.firmas enable row level security;
alter table campo.documentos_pdf enable row level security;
alter table campo.documento_intentos enable row level security;
alter table campo.derivadas_catalogo enable row level security;
alter table campo.derivadas enable row level security;
alter table campo.derivada_eventos enable row level security;
alter table campo.origen_vinculos enable row level security;
revoke all on table campo.formularios_documento, campo.firmas, campo.documentos_pdf, campo.documento_intentos, campo.derivadas_catalogo, campo.derivadas, campo.derivada_eventos, campo.origen_vinculos
  from public, anon, authenticated, service_role;
revoke all on sequence campo.firmas_id_seq, campo.documentos_pdf_id_seq, campo.documento_intentos_id_seq, campo.derivadas_id_seq, campo.derivada_eventos_id_seq, campo.origen_vinculos_id_seq
  from public, anon, authenticated, service_role;

-- ---------- 8. Firmas definitivas al registrar (en la estructura: si una reversa conserva las firmas, se conservan con su protección) ----------
-- ¿Ya está registrado? (las firmas quedan definitivas)
create function campo.f_registro_existe(p_esquema text, p_id uuid) returns boolean
language sql stable security definer set search_path to 'campo', 'acta', 'pg_temp' as $$
  select case p_esquema when 'campo' then exists (select 1 from campo.reportes r where r.id = p_id)
                        when 'acta' then exists (select 1 from acta.actas a where a.id = p_id) else false end
$$;
-- Firmas: antes de registrar se pueden cambiar; después, no. Nunca se borran.
create function campo.f_firmas_definitivas() returns trigger
language plpgsql security definer set search_path to 'campo', 'pg_temp' as $$
begin
  if tg_op in ('DELETE', 'TRUNCATE') then raise exception 'Las firmas no se borran' using errcode = '42501'; end if;
  if campo.f_registro_existe(old.esquema, old.registro_id) then
    raise exception 'El registro ya está hecho: la firma es definitiva' using errcode = '55000', hint = 'msg_usuario';
  end if;
  if new.esquema is distinct from old.esquema or new.registro_id is distinct from old.registro_id or new.rol is distinct from old.rol or new.autor is distinct from old.autor then
    raise exception 'De una firma no cambian el registro, el rol ni el autor' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger t_firmas_definitivas before update or delete on campo.firmas for each row execute function campo.f_firmas_definitivas();
create trigger t_firmas_no_vaciar before truncate on campo.firmas for each statement execute function campo.f_firmas_definitivas();
revoke all on function campo.f_registro_existe(text, uuid) from public, anon, authenticated, service_role;
revoke all on function campo.f_firmas_definitivas() from public, anon, authenticated, service_role;
