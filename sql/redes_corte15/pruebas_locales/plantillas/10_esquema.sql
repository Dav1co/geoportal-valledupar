-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 10 — GUARDIA, TABLAS, CATÁLOGOS Y PARÁMETROS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte15_eventos_suspension.md y las respuestas de David del 18-nov.
-- · Presupone la corrección del 9b publicada: huella del conjunto de funciones de redes {{MD5_BASE}}, y tecnica.f_avisos como la dejó el Corte 14.
-- · Tablas nuevas (solo agregar): eventos_suspension, evento_suspension_eventos, evento_suspension_reportes; dos catálogos ajustables con su historial
--   (qué reportes se asocian; qué sectores surte cada planta). Ninguna tabla existente cambia de forma: se agregan 3 disparadores AFTER INSERT (por
--   sentencia) en redes.reporte_externo_eventos, redes.l116_eventos y redes.danos.
-- · Reemplaza UNA función: tecnica.f_avisos (dos bloques más; 25_reemplazos.sql). Agrega el tipo «sin_agua» al catálogo de campo.
-- =====================================================================
do $$
begin
  if to_regclass('redes.eventos_suspension') is not null then raise exception 'El Corte 15 ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_BASE}}' then
    raise exception 'Las funciones de redes no son las publicadas el 18-nov (huella {{MD5_BASE}}): deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamptz)'::regprocedure)) <> '{{MD5_AVISOS}}' then
    raise exception 'tecnica.f_avisos no es la del Corte 14 (huella {{MD5_AVISOS}}): deténgase y avise';
  end if;
  if to_regclass('redes.reporte_externo_eventos') is null or to_regclass('redes.l116_eventos') is null or to_regclass('redes.l116_vigente') is null
     or to_regclass('redes.usuarios_sensibles') is null or to_regclass('redes.contrato_tramo') is null or to_regclass('tecnica.plantas') is null
     or to_regclass('campo.tipos_reporte') is null or not exists (select 1 from campo.grupos_reporte where codigo = 'red_acueducto') then
    raise exception 'Faltan tablas de los cortes anteriores (bot, línea 116, sensibles, plantas o el catálogo de campo): deténgase y avise';
  end if;
end $$;

-- ---------- 1. El evento: lo declarado no cambia; su estado es su último hecho (abierto → cerrado | anulado) ----------
create table redes.eventos_suspension (
  id               bigint generated always as identity primary key,
  codigo           text not null unique check (codigo ~ '^EVS-[0-9]{6}$'),
  alcance          text not null check (alcance in ('sectores', 'circulo', 'total')),
  todo             boolean not null default false,      -- cierto: toda la ciudad (cualquier punto pertenece; sin geometría)
  geom             geometry(MultiPolygon, 4326),      -- la zona: la unión de los sectores, el círculo, o los sectores de la planta
  sectores         bigint[] not null default '{}',      -- los activos SEC escogidos (o los de la planta)
  planta_id        bigint references tecnica.plantas (id),
  centro_lat       numeric(9,6), centro_lon numeric(9,6), radio_m numeric(7,1),
  zona_nombre      text not null check (length(btrim(zona_nombre)) between 3 and 300),
  causa            text not null check (length(btrim(causa)) between 5 and 200),
  dano_id          uuid references redes.danos (id),
  intervencion_id  uuid references redes.intervenciones (id),
  desde            timestamptz not null,
  regreso_estimado timestamptz,
  contratos        integer not null check (contratos >= 0),      -- conteo al declarar (por el tramo más cercano de cada contrato: aproximado)
  sensibles        integer not null check (sensibles >= 0),      -- usuarios sensibles CONFIRMADOS en la zona al declarar
  autor            text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en        timestamptz not null default clock_timestamp(),
  check (num_nonnulls(dano_id, intervencion_id) <= 1),
  check (regreso_estimado is null or regreso_estimado > desde),
  check (todo = (geom is null)),
  check (not todo or alcance = 'total'),
  check ((alcance = 'circulo') = (centro_lat is not null and centro_lon is not null and radio_m is not null)),
  check (alcance <> 'sectores' or cardinality(sectores) >= 1),
  check (planta_id is null or alcance = 'total')
);
create index ix_evs_geom on redes.eventos_suspension using gist (geom);
create index ix_evs_desde on redes.eventos_suspension (desde desc);
comment on table redes.eventos_suspension is 'Corte 15: evento de suspensión del servicio (por sectores, por círculo o total). Solo agregar; el estado es su último hecho en evento_suspension_eventos.';

create table redes.evento_suspension_eventos (
  id               bigint generated always as identity primary key,
  evento_id        bigint not null references redes.eventos_suspension (id),
  tipo             text not null check (tipo in ('regreso', 'cerrar', 'anular')),
  regreso_estimado timestamptz,
  motivo           text check (motivo is null or length(btrim(motivo)) between 10 and 500),
  hecho_en         timestamptz not null,
  autor            text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en        timestamptz not null default clock_timestamp(),
  check ((tipo = 'regreso') = (regreso_estimado is not null)),
  check (tipo = 'regreso' or motivo is not null)      -- cerrar y anular, siempre con motivo
);
create unique index ux_evse_fin on redes.evento_suspension_eventos (evento_id) where tipo in ('cerrar', 'anular');      -- un evento termina una sola vez
create index ix_evse_evento on redes.evento_suspension_eventos (evento_id, id desc);
comment on table redes.evento_suspension_eventos is 'Corte 15: hechos de un evento de suspensión (ajuste de la hora de regreso, cierre, anulación). Solo agregar.';

-- ---------- 2. Las asociaciones: cada fila es un hecho (asociar o desasociar); vale la última de cada reporte ----------
create table redes.evento_suspension_reportes (
  id                 bigint generated always as identity primary key,
  evento_id          bigint not null references redes.eventos_suspension (id),
  origen             text not null check (origen in ('bot', 'l116', 'dano')),
  reporte_externo_id uuid references redes.reportes_externos (id),
  l116_reporte_id    bigint references redes.l116_reportes (id),
  dano_id            uuid references redes.danos (id),
  ref                text generated always as (coalesce(reporte_externo_id::text, l116_reporte_id::text, dano_id::text)) stored,
  tipo               text not null check (tipo in ('asociar', 'desasociar')),
  modo               text not null check (modo in ('automatica', 'al_declarar', 'manual')),
  motivo             text check (motivo is null or length(btrim(motivo)) between 10 and 500),
  autor              text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en          timestamptz not null default clock_timestamp(),
  check (num_nonnulls(reporte_externo_id, l116_reporte_id, dano_id) = 1),
  check ((origen = 'bot') = (reporte_externo_id is not null) and (origen = 'l116') = (l116_reporte_id is not null) and (origen = 'dano') = (dano_id is not null)),
  check (modo <> 'manual' or motivo is not null),      -- lo que hace una persona, con motivo
  check (tipo <> 'desasociar' or modo = 'manual')
);
create index ix_evsr_evento on redes.evento_suspension_reportes (evento_id, id);
create index ix_evsr_ref on redes.evento_suspension_reportes (origen, ref, id desc);
comment on table redes.evento_suspension_reportes is 'Corte 15: reportes (bot, línea 116, daños) asociados a un evento de suspensión. Solo agregar: asociar y desasociar son hechos; vale el último de cada reporte.';

-- ---------- 3. Catálogos ajustables (estado + historial con motivo): qué se asocia y qué sectores surte cada planta ----------
create table redes.evento_tipos_asociables (
  origen  text not null check (origen in ('bot', 'l116', 'dano')),
  codigo  text not null check (length(codigo) between 2 and 120 and codigo = lower(codigo)),      -- tipo del bot, causal de la 116 (en minúsculas, un espacio) o tipo de daño
  nombre  text not null check (length(btrim(nombre)) between 2 and 120),
  clase   text not null check (clase in ('sin_agua', 'dano_red', 'otro')),
  asocia  boolean not null default true,
  primary key (origen, codigo)
);
create table redes.evento_tipo_eventos (
  id bigint generated always as identity primary key, origen text not null, codigo text not null, nombre text not null, clase text not null, asocia boolean not null,
  motivo text not null check (length(btrim(motivo)) between 10 and 500), autor text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp()
);
comment on table redes.evento_tipos_asociables is 'Corte 15: qué tipos del bot, causales de la línea 116 y tipos de daño se asocian solos a un evento de suspensión. «sin_agua» además se avisa cuando llega fuera de un evento.';
create table redes.planta_sectores (
  planta_id bigint not null references tecnica.plantas (id),
  sector_id bigint not null references redes.activos (id),
  activo    boolean not null default true,
  primary key (planta_id, sector_id)
);
create table redes.planta_sector_eventos (
  id bigint generated always as identity primary key, planta_id bigint not null references tecnica.plantas (id), sectores bigint[] not null,
  motivo text not null check (length(btrim(motivo)) between 10 and 500), autor text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp()
);
comment on table redes.planta_sectores is 'Corte 15: sectores hidráulicos que surte cada planta (para el evento «total por planta»). Arranca vacía: la llena el administrador o el supervisor de distribución.';

do $$
declare v_t text;
begin
  foreach v_t in array array['eventos_suspension', 'evento_suspension_eventos', 'evento_suspension_reportes', 'evento_tipos_asociables', 'evento_tipo_eventos', 'planta_sectores', 'planta_sector_eventos'] loop
    execute format('alter table redes.%I enable row level security', v_t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', v_t);
  end loop;
  foreach v_t in array array['eventos_suspension', 'evento_suspension_eventos', 'evento_suspension_reportes', 'evento_tipo_eventos', 'planta_sector_eventos'] loop
    execute format('create trigger t_solo_agregar before delete or update on redes.%I for each row execute function tecnica.f_solo_agregar()', v_t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', v_t);
  end loop;
end $$;

-- ---------- 4. Lo que se asocia por omisión (ajustable después con motivo) ----------
insert into redes.evento_tipos_asociables (origen, codigo, nombre, clase) values
  ('bot', 'sin_agua', 'No tengo agua o tengo baja presión', 'sin_agua'),
  ('bot', 'dano_red_acueducto', 'Daño en la red (fuga visible)', 'dano_red'),
  ('l116', 'sin servicio de agua', 'Sin servicio de agua', 'sin_agua'),
  ('l116', 'poca presión de agua', 'Poca presión de agua', 'sin_agua'),
  ('l116', 'deficiencia de agua en el sector', 'Deficiencia de agua en el sector', 'sin_agua'),
  ('l116', 'no llega agua a la residencia', 'No llega agua a la residencia', 'sin_agua'),
  ('l116', 'fuga de agua potable', 'Fuga de agua potable', 'dano_red'),
  ('l116', 'fuga de agua potable en tubería matriz', 'Fuga de agua potable en tubería matriz', 'dano_red'),
  ('l116', 'tubería de agua potable rota', 'Tubería de agua potable rota', 'dano_red'),
  ('l116', 'tubería rota', 'Tubería rota', 'dano_red'),
  ('l116', 'escape de agua (hidrante, tubería)', 'Escape de Agua (Hidrante, Tubería)', 'dano_red'),
  ('dano', 'fuga', 'Fuga o tubería rota', 'dano_red'),
  ('dano', 'bombeo', 'Falla de bombeo', 'otro'),
  ('dano', 'electrica', 'Falla eléctrica', 'otro');

-- ---------- 5. El tipo nuevo del catálogo de campo: «sin_agua» (David, 18-nov), en el grupo «red_acueducto», como los dos que agregó el Corte 8 ----------
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden)
select g.id, 'sin_agua', 'No tengo agua o tengo baja presión', (select coalesce(max(t.orden), 0) from campo.tipos_reporte t where t.grupo_id = g.id) + 1
  from campo.grupos_reporte g
 where g.codigo = 'red_acueducto' and not exists (select 1 from campo.tipos_reporte t where t.codigo = 'sin_agua');
update campo.tipos_reporte set activo = true where codigo = 'sin_agua' and not activo;      -- si una reversa lo había desactivado

-- ---------- 6. Consecutivo y parámetros ----------
insert into redes.consecutivos (prefijo, ultimo) values ('EVS', 0) on conflict (prefijo) do nothing;
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('evento_radio_min_m', 20, 'm', 5, 500, 'Evento de suspensión (Corte 15): radio mínimo del círculo'),
  ('evento_radio_max_m', 5000, 'm', 100, 20000, 'Evento de suspensión (Corte 15): radio máximo del círculo'),
  ('evento_sectores_max', 40, 'sectores', 1, 100, 'Evento de suspensión (Corte 15): máximo de sectores o subsectores en un evento'),
  ('evento_horas_atras_max', 72, 'horas', 1, 720, 'Evento de suspensión (Corte 15): cuánto antes de ahora puede empezar un evento que se declara'),
  ('evento_lista_max', 200, 'reportes', 10, 2000, 'Evento de suspensión (Corte 15): máximo de reportes asociados que se listan en el detalle')
on conflict (clave) do update set estado = 'vigente', descripcion = excluded.descripcion;
insert into tecnica.aviso_parametros (clave, area, valor, minimo, maximo, unidad, orden, nombre, descripcion) values
  ('sin_agua_ventana_h', 'distribucion', 24, 1, 720, 'horas', 166, 'Reportes «sin agua» sin evento: ventana',
   'Se avisan los reportes de falta de agua o baja presión (bot y línea 116) de estas últimas horas que no están en un evento de suspensión.')
on conflict (clave) do update set nombre = excluded.nombre, descripcion = excluded.descripcion;
