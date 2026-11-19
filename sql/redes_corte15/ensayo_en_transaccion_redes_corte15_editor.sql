begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 10 — GUARDIA, TABLAS, CATÁLOGOS Y PARÁMETROS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte15_eventos_suspension.md y las respuestas de David del 18-nov.
-- · Presupone la corrección del 9b publicada: huella del conjunto de funciones de redes 63d917635b33e3696f28a3b0e579c002, y tecnica.f_avisos como la dejó el Corte 14.
-- · Tablas nuevas (solo agregar): eventos_suspension, evento_suspension_eventos, evento_suspension_reportes; dos catálogos ajustables con su historial
--   (qué reportes se asocian; qué sectores surte cada planta). Ninguna tabla existente cambia de forma: se agregan 3 disparadores AFTER INSERT (por
--   sentencia) en redes.reporte_externo_eventos, redes.l116_eventos y redes.danos.
-- · Reemplaza UNA función: tecnica.f_avisos (dos bloques más; 25_reemplazos.sql). Agrega el tipo «sin_agua» al catálogo de campo.
-- =====================================================================
do $$
begin
  if to_regclass('redes.eventos_suspension') is not null then raise exception 'El Corte 15 ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '63d917635b33e3696f28a3b0e579c002' then
    raise exception 'Las funciones de redes no son las publicadas el 18-nov (huella 63d917635b33e3696f28a3b0e579c002): deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamptz)'::regprocedure)) <> 'b7ec2303f95153684963ded7bdb0a5c0' then
    raise exception 'tecnica.f_avisos no es la del Corte 14 (huella b7ec2303f95153684963ded7bdb0a5c0): deténgase y avise';
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
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 20 — VISTA Y FUNCIONES INTERNAS (ninguna la ejecuta la API)
--   · quién puede qué; la zona de cada alcance; contratos y usuarios sensibles de la zona; los reportes que caen en una zona;
--   · la ASOCIACIÓN AUTOMÁTICA: tres disparadores AFTER INSERT por sentencia (con la tabla de filas nuevas: una consulta por sentencia, no por fila):
--       bot   → redes.reporte_externo_eventos (cuando entra el «recibido»);   116 → redes.l116_eventos (el «alta» al publicar);   daño → redes.danos.
--     Sin eventos abiertos no hacen nada. La pertenencia se decide por el punto del reporte (dentro de la zona; «toda la ciudad» no tiene geometría).
--   · lo que le llega a cada reporte: bot → «en_atencion» al asociar, «atendido» al cerrar, «recibido» al desasociar o anular; daño → una nota en su historial
--     (el daño NO se cierra con el evento: sigue hasta su reparación); 116 → «atendido» al cerrar.
--   · los dos bloques para Avisos y la respuesta para el bot.
-- =====================================================================

-- ---------- estado de un evento: abierto → cerrado | anulado; la hora de regreso vigente es la del último ajuste ----------
create view redes.v_evento_suspension as
select e.*, coalesce(f.estado, 'abierto') as estado, f.hecho_en as fin_en, f.motivo as fin_motivo, f.autor as fin_autor,
       coalesce((select x.regreso_estimado from redes.evento_suspension_eventos x where x.evento_id = e.id and x.tipo = 'regreso' order by x.id desc limit 1), e.regreso_estimado) as regreso_vigente
  from redes.eventos_suspension e
  left join lateral (select case x.tipo when 'cerrar' then 'cerrado' else 'anulado' end as estado, x.hecho_en, x.motivo, x.autor
                       from redes.evento_suspension_eventos x where x.evento_id = e.id and x.tipo in ('cerrar', 'anular') limit 1) f on true;
revoke all on table redes.v_evento_suspension from public, anon, authenticated, service_role;

create function redes.f_eventos_abiertos() returns setof redes.eventos_suspension
language sql stable security definer set search_path = redes, pg_temp as $$
  select e.* from redes.eventos_suspension e
   where not exists (select 1 from redes.evento_suspension_eventos x where x.evento_id = e.id and x.tipo in ('cerrar', 'anular')) $$;

-- un reporte está «libre» si su último hecho no es «asociar» a un evento que siga abierto. SQL sin SET: se integra en la consulta que la llama
create function redes.f_evento_ref_libre(p_origen text, p_ref text) returns boolean
language sql stable as $$
  select not exists (
    select 1 from (select y.tipo, y.evento_id from redes.evento_suspension_reportes y where y.origen = p_origen and y.ref = p_ref order by y.id desc limit 1) u
     where u.tipo = 'asociar'
       and not exists (select 1 from redes.evento_suspension_eventos z where z.evento_id = u.evento_id and z.tipo in ('cerrar', 'anular'))) $$;

-- los reportes asociados HOY a un evento (su último hecho es «asociar» a este evento)
create function redes.f_evento_reportes(p_evento bigint) returns setof redes.evento_suspension_reportes
language sql stable security definer set search_path = redes, pg_temp as $$
  select r.* from redes.evento_suspension_reportes r
   where r.evento_id = p_evento and r.tipo = 'asociar'
     and not exists (select 1 from redes.evento_suspension_reportes x where x.origen = r.origen and x.ref = r.ref and x.id > r.id) $$;

-- la causal de la 116 como clave del catálogo: minúsculas y un solo espacio
create function redes.f_evento_clave(p_texto text) returns text
language sql immutable as $$ select lower(regexp_replace(btrim(coalesce(p_texto, '')), '\s+', ' ', 'g')) $$;

-- «18/11, 9:40 p. m.» (hora de Bogotá)
create function redes.f_evento_hora(p_cuando timestamptz) returns text
language sql stable as $$
  select to_char(p_cuando at time zone 'America/Bogota', 'DD/MM, FMHH12:MI') || case when extract(hour from p_cuando at time zone 'America/Bogota') < 12 then ' a. m.' else ' p. m.' end $$;

-- ---------- quién puede qué ----------
--   lectura: cualquiera de Técnica · detalle y catálogo: los dos supervisores · zona (sectores o círculo) y reportes: supervisor de distribución
--   total: supervisor de planta · el administrador, todo.
create function redes.f_evento_autorizar(p_solicitante text, p_para text) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_p record; v_sd boolean; v_sp boolean;
begin
  select * into v_p from redes.f_perfil_lectura(p_solicitante);
  if v_p.perfil = 'admin' or p_para = 'lectura' then return v_p.email; end if;
  v_sd := v_p.perfil = 'supervisor';
  v_sp := public.geoportal_puede(v_p.email, 'dashboard_tecnico');
  if (p_para in ('zona', 'reportes') and v_sd) or (p_para = 'total' and v_sp) or (p_para = 'detalle' and (v_sd or v_sp)) then return v_p.email; end if;
  raise exception '%', case p_para
      when 'total' then 'Un evento total lo declara, ajusta o cierra el supervisor de planta o el administrador'
      when 'zona' then 'Un evento por sectores o por círculo lo declara, ajusta o cierra el supervisor de distribución o el administrador'
      when 'reportes' then 'Los reportes de un evento y sus catálogos los maneja el supervisor de distribución o el administrador'
      else 'Solo los supervisores o el administrador ven el detalle de un evento' end using errcode = '42501';
end $$;

-- ---------- la zona de cada alcance (no revisa permisos) ----------
create function redes.f_evento_zona(p jsonb, out alcance text, out todo boolean, out geom geometry, out sectores bigint[], out planta_id bigint,
                                    out centro_lat numeric, out centro_lon numeric, out radio_m numeric, out zona_nombre text) returns record
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_cods text[]; v_cuantos integer; v_pl tecnica.plantas%rowtype; v_sector text; v_pt geometry;
begin
  alcance := coalesce(p ->> 'alcance', ''); todo := false; sectores := '{}';
  if alcance = 'sectores' then
    if jsonb_typeof(p -> 'sectores') is distinct from 'array' or jsonb_array_length(p -> 'sectores') = 0 then perform tecnica.f_error('Escoja al menos un sector o subsector'); end if;
    if jsonb_array_length(p -> 'sectores') > coalesce(redes.f_param('evento_sectores_max'), 40) then
      perform tecnica.f_error(format('Un evento admite máximo %s sectores o subsectores', coalesce(redes.f_param('evento_sectores_max'), 40)));
    end if;
    select array_agg(distinct upper(btrim(x))) into v_cods from jsonb_array_elements_text(p -> 'sectores') x;
    select array_agg(m.activo_id order by m.codigo), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(m.geom)), 3)),
           string_agg(coalesce(nullif(btrim(m.nombre), ''), m.codigo), ', ' order by m.codigo), count(*)
      into sectores, geom, zona_nombre, v_cuantos
      from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.codigo = any (v_cods);
    if v_cuantos is distinct from cardinality(v_cods) then perform tecnica.f_error('Alguno de los sectores no existe o ya no está vigente', 'P0002'); end if;
    zona_nombre := left(zona_nombre, 300);
  elsif alcance = 'circulo' then
    centro_lat := round(redes.f_num(p -> 'lat'), 6); centro_lon := round(redes.f_num(p -> 'lon'), 6); radio_m := round(redes.f_num(p -> 'radio_m'), 1);
    if centro_lat is null or centro_lon is null or centro_lat not between -90 and 90 or centro_lon not between -180 and 180 then perform tecnica.f_error('Marque el centro del círculo en el mapa'); end if;
    if radio_m is null or radio_m < coalesce(redes.f_param('evento_radio_min_m'), 20) or radio_m > coalesce(redes.f_param('evento_radio_max_m'), 5000) then
      perform tecnica.f_error(format('El radio del círculo va de %s a %s metros', coalesce(redes.f_param('evento_radio_min_m'), 20), coalesce(redes.f_param('evento_radio_max_m'), 5000)));
    end if;
    v_pt := ST_SetSRID(ST_MakePoint(centro_lon, centro_lat), 4326);
    geom := ST_Multi(ST_Buffer(v_pt::geography, radio_m, 16)::geometry);
    select s.nombre into v_sector from redes.f_sector_de(v_pt) s;
    zona_nombre := format('un círculo de %s m', round(radio_m)) || coalesce(' en ' || nullif(btrim(v_sector), ''), '');
  elsif alcance = 'total' then
    if coalesce(p ->> 'total', '') = 'ciudad' then
      todo := true; zona_nombre := 'toda la ciudad';
    elsif coalesce(p ->> 'total', '') = 'planta' then
      select * into v_pl from tecnica.plantas pl where pl.codigo = lower(btrim(coalesce(p ->> 'planta', ''))) and pl.activa;
      if v_pl.id is null then perform tecnica.f_error('Escoja la planta', 'P0002'); end if;
      planta_id := v_pl.id;
      select array_agg(m.activo_id order by m.codigo), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(m.geom)), 3))
        into sectores, geom
        from redes.planta_sectores ps join redes.activo_vigente_mat m on m.activo_id = ps.sector_id
       where ps.planta_id = v_pl.id and ps.activo and m.prefijo = 'SEC' and not m.retirado and not m.oculto;
      if sectores is null then
        perform tecnica.f_error(format('La planta %s todavía no tiene sectores asignados: asígnelos primero, o declare el evento para toda la ciudad', v_pl.nombre));
      end if;
      zona_nombre := 'lo que surte la planta ' || v_pl.nombre;
    else perform tecnica.f_error('El evento total es de toda la ciudad o de una planta');
    end if;
  else perform tecnica.f_error('Escoja el alcance: por sectores, por círculo o total');
  end if;
  if not todo and (geom is null or ST_IsEmpty(geom)) then perform tecnica.f_error('No se pudo armar la zona del evento'); end if;
end $$;

-- ---------- contratos de la zona (por el tramo más cercano de cada contrato: aproximado) y usuarios sensibles CONFIRMADOS. Sin nombres ----------
create function redes.f_evento_contratos(p_geom geometry, p_todo boolean, p_lista boolean default false) returns jsonb
language plpgsql stable security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_contratos integer; v_sens integer; v_lista jsonb;
begin
  if p_todo then
    select count(*) into v_contratos from redes.contrato_tramo;
    select count(*), case when p_lista then coalesce(jsonb_agg(jsonb_build_object('contrato', s.contrato, 'tipo', ts.nombre) order by ts.orden, s.contrato), '[]'::jsonb) end
      into v_sens, v_lista
      from redes.v_usuario_sensible s join redes.tipos_sensible ts on ts.codigo = s.tipo where s.estado = 'confirmado';
  else
    select count(*) into v_contratos
      from redes.activo_vigente_mat m join redes.contrato_tramo ct on ct.activo_id = m.activo_id
     where m.geom && p_geom and ST_Intersects(m.geom, p_geom);
    select count(*), case when p_lista then coalesce(jsonb_agg(jsonb_build_object('contrato', s.contrato, 'tipo', ts.nombre) order by ts.orden, s.contrato), '[]'::jsonb) end
      into v_sens, v_lista
      from redes.v_usuario_sensible s join redes.tipos_sensible ts on ts.codigo = s.tipo
      join redes.contrato_tramo ct on ct.contrato = s.contrato join redes.activo_vigente_mat m on m.activo_id = ct.activo_id
     where s.estado = 'confirmado' and ST_Intersects(m.geom, p_geom);
  end if;
  return jsonb_build_object('contratos', v_contratos, 'sensibles', v_sens) || case when p_lista then jsonb_build_object('sensibles_lista', v_lista) else '{}'::jsonb end;
end $$;

-- ---------- los reportes ABIERTOS que caen en una zona desde una hora (al declarar y en la vista previa) ----------
create function redes.f_evento_candidatos(p_geom geometry, p_todo boolean, p_desde timestamptz, p_sin_dano uuid default null)
returns table (origen text, reporte_externo_id uuid, l116_reporte_id bigint, dano_id uuid)
language sql stable security definer set search_path = redes, public, extensions, pg_temp as $$
  select 'bot', r.id, null::bigint, null::uuid
    from redes.reportes_externos r
   where r.recibido_en >= p_desde and r.geom is not null and (p_todo or (r.geom && p_geom and ST_Intersects(p_geom, r.geom)))
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'bot' and t.codigo = lower(btrim(r.tipo_bot)) and t.asocia)
     and (select x.tipo from redes.reporte_externo_eventos x where x.reporte_id = r.id order by x.id desc limit 1) = 'recibido'
     and redes.f_evento_ref_libre('bot', r.id::text)
  union all
  select 'l116', null::uuid, v.reporte_id, null::uuid
    from redes.l116_vigente v
   where not v.oculto and v.estado = 'registrado' and v.fecha_registro >= p_desde and v.geom is not null and (p_todo or (v.geom && p_geom and ST_Intersects(p_geom, v.geom)))
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'l116' and t.codigo = redes.f_evento_clave(v.causal) and t.asocia)
     and redes.f_evento_ref_libre('l116', v.reporte_id::text)
  union all
  select 'dano', null::uuid, null::bigint, d.id
    from redes.danos d
   where d.registrado_en >= p_desde and d.t_detectado >= p_desde and d.sistema = 'acueducto' and d.geom is not null and (p_todo or (d.geom && p_geom and ST_Intersects(p_geom, d.geom)))
     and (p_sin_dano is null or d.id <> p_sin_dano)
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'dano' and t.codigo = d.tipo_codigo and t.asocia)
     and (select vd.estado from redes.v_dano vd where vd.id = d.id) <> 'atendido'
     and redes.f_evento_ref_libre('dano', d.id::text) $$;

-- ---------- lo que le llega a cada reporte de unas asociaciones: bot → un hecho de su historial; daño → una nota. «{evento}» = el código ----------
create function redes.f_evento_marcar(p_ids bigint[], p_bot_tipo text, p_texto text, p_autor text) returns void
language plpgsql volatile security definer set search_path = redes, pg_temp as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then return; end if;
  insert into redes.reporte_externo_eventos (reporte_id, tipo, motivo, autor)
  select r.reporte_externo_id, p_bot_tipo, left(replace(p_texto, '{evento}', e.codigo), 1000), p_autor
    from redes.evento_suspension_reportes r join redes.eventos_suspension e on e.id = r.evento_id
   where r.id = any (p_ids) and r.origen = 'bot' order by r.id;
  insert into redes.dano_eventos (dano_id, tipo, motivo, autor)
  select r.dano_id, 'nota', left(replace(p_texto, '{evento}', e.codigo), 1000), p_autor
    from redes.evento_suspension_reportes r join redes.eventos_suspension e on e.id = r.evento_id
   where r.id = any (p_ids) and r.origen = 'dano' order by r.id;
end $$;

-- ---------- LA ASOCIACIÓN AUTOMÁTICA ----------
-- bot: cuando entra el «recibido» ORIGINAL de un reporte (sin motivo; el reporte ya está guardado). El «en_atencion» que escribe vuelve a disparar esto y sale
-- en la primera línea. Un «recibido» con motivo es el de un reporte que alguien desasoció o de un evento anulado: ese no se vuelve a asociar solo.
create function redes.f_evento_tg_bot() returns trigger
language plpgsql security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_ids bigint[];
begin
  if not exists (select 1 from nuevos x where x.tipo = 'recibido' and x.motivo is null) or not exists (select 1 from redes.f_eventos_abiertos()) then return null; end if;
  with hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, tipo, modo, autor)
    select ev.id, 'bot', r.id, 'asociar', 'automatica', 'sistema@evento.suspension'
      from nuevos x join redes.reportes_externos r on r.id = x.reporte_id
     cross join lateral (select e.id from redes.f_eventos_abiertos() e
                          where e.desde <= r.recibido_en and (e.todo or ST_Intersects(e.geom, r.geom)) order by e.id desc limit 1) ev
     where x.tipo = 'recibido' and x.motivo is null and r.geom is not null
       and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'bot' and t.codigo = lower(btrim(r.tipo_bot)) and t.asocia)
       and redes.f_evento_ref_libre('bot', r.id::text)
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, 'en_atencion', 'Asociado al evento de suspensión {evento}', 'sistema@evento.suspension');
  return null;
end $$;
create trigger t_evento_asociar after insert on redes.reporte_externo_eventos referencing new table as nuevos for each statement execute function redes.f_evento_tg_bot();

-- línea 116: el «alta» de cada reporte nuevo al publicar una carga (trae el punto del contrato). Solo los que llegan en «Registrado»
create function redes.f_evento_tg_l116() returns trigger
language plpgsql security definer set search_path = redes, public, extensions, pg_temp as $$
begin
  if not exists (select 1 from nuevos x where x.tipo = 'alta' and x.geom is not null) or not exists (select 1 from redes.f_eventos_abiertos()) then return null; end if;
  insert into redes.evento_suspension_reportes (evento_id, origen, l116_reporte_id, tipo, modo, autor)
  select ev.id, 'l116', r.id, 'asociar', 'automatica', 'sistema@evento.suspension'
    from nuevos x join redes.l116_reportes r on r.id = x.reporte_id
   cross join lateral (select e.id from redes.f_eventos_abiertos() e
                        where e.desde <= r.fecha_registro and (e.todo or ST_Intersects(e.geom, x.geom)) order by e.id desc limit 1) ev
   where x.tipo = 'alta' and x.estado = 'registrado' and x.geom is not null
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'l116' and t.codigo = redes.f_evento_clave(r.causal) and t.asocia)
     and redes.f_evento_ref_libre('l116', r.id::text);
  return null;
end $$;
create trigger t_evento_asociar after insert on redes.l116_eventos referencing new table as nuevos for each statement execute function redes.f_evento_tg_l116();

-- daños (formulario, o un reporte del bot convertido): el daño se guarda como siempre y queda asociado, con una nota en su historial
create function redes.f_evento_tg_dano() returns trigger
language plpgsql security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_ids bigint[];
begin
  if not exists (select 1 from redes.f_eventos_abiertos()) then return null; end if;
  with hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, dano_id, tipo, modo, autor)
    select ev.id, 'dano', d.id, 'asociar', 'automatica', 'sistema@evento.suspension'
      from nuevos d
     cross join lateral (select e.id from redes.f_eventos_abiertos() e
                          where e.desde <= d.t_detectado and (e.todo or ST_Intersects(e.geom, d.geom)) order by e.id desc limit 1) ev
     where d.sistema = 'acueducto' and d.geom is not null
       and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'dano' and t.codigo = d.tipo_codigo and t.asocia)
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, null, 'Asociado al evento de suspensión {evento} (el daño sigue abierto hasta su reparación)', 'sistema@evento.suspension');
  return null;
end $$;
create trigger t_evento_asociar after insert on redes.danos referencing new table as nuevos for each statement execute function redes.f_evento_tg_dano();

-- ---------- el evento como lo ven las pantallas (sin datos de suscriptores; «quién» es el nombre del funcionario) ----------
create function redes.f_evento_franja(p_zona text, p_desde timestamptz, p_causa text, p_regreso timestamptz) returns text
language sql stable as $$
  select format('Sin agua en %s desde las %s por %s. Regreso estimado: %s', p_zona, redes.f_evento_hora(p_desde), rtrim(btrim(p_causa), '.'),
                coalesce(redes.f_evento_hora(p_regreso), 'sin definir.')) $$;      -- la hora ya termina en punto («p. m.»)

create function redes.f_evento_json(p_evento bigint, p_geo boolean default false) returns jsonb
language sql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
  select jsonb_build_object(
    'codigo', e.codigo, 'estado', e.estado, 'alcance', e.alcance,
    'total', case when e.alcance = 'total' then case when e.todo then 'ciudad' else 'planta' end end,
    'planta', (select pl.nombre from tecnica.plantas pl where pl.id = e.planta_id),
    'zona', e.zona_nombre, 'causa', e.causa,
    'registro', coalesce((select d.codigo from redes.danos d where d.id = e.dano_id), (select i.codigo from redes.intervenciones i where i.id = e.intervencion_id)),
    'desde', e.desde, 'regreso_estimado', e.regreso_vigente, 'declarado_en', e.creado_en,
    'declarado_por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = e.autor), 'Funcionario de EMDUPAR'),
    'contratos', e.contratos, 'sensibles', e.sensibles,
    'reportes', (select jsonb_build_object('total', count(*), 'bot', count(*) filter (where r.origen = 'bot'), 'l116', count(*) filter (where r.origen = 'l116'),
                                           'danos', count(*) filter (where r.origen = 'dano')) from redes.f_evento_reportes(e.id) r),
    'franja', redes.f_evento_franja(e.zona_nombre, e.desde, e.causa, e.regreso_vigente),
    'fin', case when e.estado <> 'abierto' then jsonb_build_object('cuando', e.fin_en, 'motivo', e.fin_motivo,
              'por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = e.fin_autor), 'Funcionario de EMDUPAR')) end,
    'circulo', case when e.alcance = 'circulo' then jsonb_build_object('lat', e.centro_lat, 'lon', e.centro_lon, 'radio_m', e.radio_m) end,
    'sectores', (select coalesce(jsonb_agg(m.codigo order by m.codigo), '[]'::jsonb) from redes.activo_vigente_mat m where m.activo_id = any (e.sectores)))
    || case when p_geo then jsonb_build_object('zona_geojson', case when e.geom is not null then ST_AsGeoJSON(ST_Multi(ST_SimplifyPreserveTopology(e.geom, 0.00002)), 6)::jsonb end) else '{}'::jsonb end
    from redes.v_evento_suspension e where e.id = p_evento $$;

-- ---------- para Avisos (Corte 12): UN aviso por evento abierto, y los «sin agua» que no están en ningún evento ----------
create function redes.f_eventos_para_avisos(p_ahora timestamptz) returns table (codigo text, alcance text, nivel text, titulo text, detalle text, n integer, desde timestamptz)
language sql stable security definer set search_path = redes, public, pg_temp as $$
  select e.codigo, e.alcance, case when e.regreso_vigente is not null and e.regreso_vigente < p_ahora then 'rojo' else 'naranja' end,
         format('Sin agua en %s desde las %s', e.zona_nombre, redes.f_evento_hora(e.desde)),
         format('%s. %s. Regreso estimado: %s%s', rtrim(btrim(e.causa), '.'),
                case c.n when 0 then 'Sin reportes asociados' when 1 then '1 reporte asociado' else c.n || ' reportes asociados' end,
                coalesce(redes.f_evento_hora(e.regreso_vigente), 'sin definir.'),      -- la hora ya termina en punto («p. m.»)
                case when e.regreso_vigente is not null and e.regreso_vigente < p_ahora then ' Ya pasó: ajuste la hora o cierre el evento.' else '' end),
         c.n, e.desde
    from redes.v_evento_suspension e cross join lateral (select count(*)::integer as n from redes.f_evento_reportes(e.id)) c
   where e.estado = 'abierto' and e.creado_en <= p_ahora $$;

create function redes.f_sin_agua_para_avisos(p_ahora timestamptz, p_horas numeric) returns table (n integer, desde timestamptz, items jsonb)
language sql stable security definer set search_path = redes, public, pg_temp as $$
  with s as (
    select r.recibido_en as cuando, 'Bot · ' || r.radicado as txt
      from redes.reportes_externos r
     where r.recibido_en > p_ahora - make_interval(secs => (p_horas * 3600)::double precision) and r.recibido_en <= p_ahora
       and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'bot' and t.codigo = lower(btrim(r.tipo_bot)) and t.clase = 'sin_agua')
       and (select x.tipo from redes.reporte_externo_eventos x where x.reporte_id = r.id order by x.id desc limit 1) = 'recibido'
       and redes.f_evento_ref_libre('bot', r.id::text)
    union all
    select v.fecha_registro, 'Línea 116 · ' || v.reporte || coalesce(' · sector ' || v.sector, '')
      from redes.l116_vigente v
     where not v.oculto and v.estado = 'registrado' and v.fecha_registro > p_ahora - make_interval(secs => (p_horas * 3600)::double precision) and v.fecha_registro <= p_ahora
       and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'l116' and t.codigo = redes.f_evento_clave(v.causal) and t.clase = 'sin_agua')
       and redes.f_evento_ref_libre('l116', v.reporte_id::text))
  select count(*)::integer, min(s.cuando), coalesce((array_to_json((array_agg(s.txt order by s.cuando desc))[1:5]))::jsonb, '[]'::jsonb) from s $$;

-- ---------- para el bot (n8n en el Dell): recibe el reporte como siempre y dice si quedó en un evento abierto, con el texto listo ----------
-- No se da permiso a ningún rol aquí: el permiso para el Dell va cuando se conecte el bot. La función anterior (f_reporte_externo_recibir) no se toca.
create function redes.f_reporte_externo_recibir_evento(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_id uuid := redes.f_reporte_externo_recibir(p); v_ev redes.v_evento_suspension%rowtype;
begin
  select e.* into v_ev from redes.evento_suspension_reportes r join redes.v_evento_suspension e on e.id = r.evento_id
   where r.origen = 'bot' and r.ref = v_id::text and r.tipo = 'asociar' and e.estado = 'abierto'
     and not exists (select 1 from redes.evento_suspension_reportes x where x.origen = 'bot' and x.ref = r.ref and x.id > r.id);
  return jsonb_build_object('id', v_id, 'radicado', p ->> 'radicado', 'evento', v_ev.codigo, 'regreso_estimado', v_ev.regreso_vigente,
    'mensaje', case when v_ev.id is null then null
                    when v_ev.regreso_vigente is null then 'Ya sabemos del corte en tu sector. Todavía no hay hora estimada de regreso.'
                    else 'Ya sabemos del corte en tu sector. Regreso estimado: ' || redes.f_evento_hora(v_ev.regreso_vigente) end);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 26 — RPC (las llama la Edge geoportal-redes; las pantallas son del Code B)
--   Lectura:  evento_catalogo · evento_vista_previa · eventos_vigentes · eventos · evento
--   Escribe:  evento_declarar · evento_regreso · evento_cerrar · evento_anular · evento_asociar · evento_desasociar · evento_tipo_fijar · planta_sectores_fijar
-- Quién puede cada cosa lo decide redes.f_evento_autorizar. Solo conteos de contratos; la lista de usuarios sensibles (contrato y tipo, sin nombre) solo va
-- en el detalle, a supervisores y administrador. «Quién» es siempre el nombre del funcionario.
-- =====================================================================

-- lo que necesita la pantalla para declarar: sectores, plantas con sus sectores, qué se asocia, límites y qué puede esta persona
create function public.geoportal_redes_evento_catalogo(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'detalle'); v_p record;
begin
  select * into v_p from redes.f_perfil_lectura(v_email);
  return jsonb_build_object(
    'puede', jsonb_build_object('zona', v_p.perfil in ('admin', 'supervisor'), 'reportes', v_p.perfil in ('admin', 'supervisor'),
                                'total', v_p.perfil = 'admin' or public.geoportal_puede(v_email, 'dashboard_tecnico')),
    'limites', jsonb_build_object('radio_min_m', redes.f_param('evento_radio_min_m'), 'radio_max_m', redes.f_param('evento_radio_max_m'),
                                  'sectores_max', redes.f_param('evento_sectores_max'), 'horas_atras_max', redes.f_param('evento_horas_atras_max')),
    'sectores', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', coalesce(nullif(btrim(m.nombre), ''), m.codigo), 'clase', m.clase) order by m.clase, m.nombre, m.codigo)
                            from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto), '[]'::jsonb),
    'plantas', coalesce((select jsonb_agg(jsonb_build_object('codigo', pl.codigo, 'nombre', pl.nombre,
                           'sectores', coalesce((select jsonb_agg(m.codigo order by m.codigo) from redes.planta_sectores ps join redes.activo_vigente_mat m on m.activo_id = ps.sector_id
                                                  where ps.planta_id = pl.id and ps.activo and not m.retirado and not m.oculto), '[]'::jsonb)) order by pl.id)
                           from tecnica.plantas pl where pl.activa), '[]'::jsonb),
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('origen', t.origen, 'codigo', t.codigo, 'nombre', t.nombre, 'clase', t.clase, 'asocia', t.asocia) order by t.origen, t.clase, t.nombre)
                         from redes.evento_tipos_asociables t), '[]'::jsonb));
end $$;

-- antes de declarar: la zona, los contratos, los sensibles confirmados y cuántos reportes ya recibidos quedarían asociados. No guarda nada
create function public.geoportal_redes_evento_vista_previa(p_solicitante text, p jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text; z record; v_desde timestamptz; c jsonb;
begin
  v_email := redes.f_evento_autorizar(p_solicitante, case when coalesce(p ->> 'alcance', '') = 'total' then 'total' else 'zona' end);
  select * into z from redes.f_evento_zona(p);
  v_desde := coalesce(redes.f_instante(p ->> 'desde', 'desde cuándo'), clock_timestamp());
  c := redes.f_evento_contratos(z.geom, z.todo);
  return jsonb_build_object('alcance', z.alcance, 'zona', z.zona_nombre, 'contratos', c -> 'contratos', 'sensibles', c -> 'sensibles',
    'reportes', (select jsonb_build_object('total', count(*), 'bot', count(*) filter (where k.origen = 'bot'), 'l116', count(*) filter (where k.origen = 'l116'),
                                           'danos', count(*) filter (where k.origen = 'dano')) from redes.f_evento_candidatos(z.geom, z.todo, v_desde) k),
    'ya_abierto', (select e.codigo from redes.f_eventos_abiertos() e where (z.todo and e.todo) or (not z.todo and not e.todo and ST_Equals(e.geom, z.geom)) limit 1),
    'zona_geojson', case when z.geom is not null then ST_AsGeoJSON(ST_Multi(ST_SimplifyPreserveTopology(z.geom, 0.00002)), 6)::jsonb end);
end $$;

-- declarar: guarda el evento y asocia de una vez los reportes abiertos que ya estaban en la zona desde la hora de inicio
create function public.geoportal_redes_evento_declarar(p_solicitante text, p jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare
  v_email text; z record; v_causa text := btrim(coalesce(p ->> 'causa', '')); v_reg text := nullif(upper(btrim(coalesce(p ->> 'registro', ''))), '');
  v_dano uuid; v_itv uuid; v_sis text; v_desde timestamptz; v_regreso timestamptz; v_ahora timestamptz := clock_timestamp(); v_ya text; c jsonb;
  v_cons bigint; v_id bigint; v_ids bigint[]; v_max numeric := coalesce(redes.f_param('evento_horas_atras_max'), 72);
begin
  if exists (select 1 from jsonb_object_keys(p) k where k not in ('alcance', 'sectores', 'lat', 'lon', 'radio_m', 'total', 'planta', 'causa', 'registro', 'desde', 'regreso')) then
    perform tecnica.f_error('El evento trae un dato que no corresponde');
  end if;
  v_email := redes.f_evento_autorizar(p_solicitante, case when coalesce(p ->> 'alcance', '') = 'total' then 'total' else 'zona' end);
  select * into z from redes.f_evento_zona(p);
  if length(v_causa) < 5 or length(v_causa) > 200 then perform tecnica.f_error('Escriba la causa (de 5 a 200 letras)'); end if;
  if v_reg ~ '^DAN-[0-9]{6}$' then
    select d.id, d.sistema into v_dano, v_sis from redes.danos d where d.codigo = v_reg;
    if v_dano is null then perform tecnica.f_error(format('No hay ningún daño o falla con el código «%s»', v_reg), 'P0002'); end if;
  elsif v_reg ~ '^ITV-[0-9]{6}$' then
    select i.id, i.sistema into v_itv, v_sis from redes.intervenciones i where i.codigo = v_reg;
    if v_itv is null then perform tecnica.f_error(format('No hay ninguna intervención con el código «%s»', v_reg), 'P0002'); end if;
  elsif v_reg is not null then perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
  end if;
  if v_sis is not null and v_sis <> 'acueducto' then perform tecnica.f_error('Ese daño o intervención no es de acueducto'); end if;
  v_desde := coalesce(redes.f_instante(p ->> 'desde', 'desde cuándo'), v_ahora);
  if v_desde > v_ahora + interval '5 minutes' then perform tecnica.f_error('El evento no puede empezar en el futuro'); end if;
  if v_desde < v_ahora - make_interval(secs => (v_max * 3600)::double precision) then perform tecnica.f_error(format('El evento no puede haber empezado hace más de %s horas', v_max)); end if;
  v_regreso := redes.f_instante(p ->> 'regreso', 'regreso estimado del servicio');
  if v_regreso is not null and (v_regreso <= v_desde or v_regreso > v_desde + interval '30 days') then
    perform tecnica.f_error('La hora estimada de regreso debe ser después del inicio y antes de 30 días');
  end if;
  -- un evento a la vez: el consecutivo y la revisión de «ya hay uno abierto para esa zona»
  perform pg_advisory_xact_lock(hashtext('redes.eventos_suspension'));
  select e.codigo into v_ya from redes.f_eventos_abiertos() e where (z.todo and e.todo) or (not z.todo and not e.todo and ST_Equals(e.geom, z.geom)) limit 1;
  if v_ya is not null then raise exception 'Ya hay un evento abierto para esa misma zona: %', v_ya using errcode = '55000', hint = 'msg_usuario'; end if;
  c := redes.f_evento_contratos(z.geom, z.todo);
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'EVS' returning ultimo into v_cons;
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, planta_id, centro_lat, centro_lon, radio_m, zona_nombre, causa, dano_id, intervencion_id,
                                        desde, regreso_estimado, contratos, sensibles, autor)
  values ('EVS-' || lpad(v_cons::text, 6, '0'), z.alcance, z.todo, z.geom, z.sectores, z.planta_id, z.centro_lat, z.centro_lon, z.radio_m, z.zona_nombre, v_causa, v_dano, v_itv,
          v_desde, v_regreso, (c ->> 'contratos')::integer, (c ->> 'sensibles')::integer, v_email)
  returning id into v_id;
  with hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, tipo, modo, autor)
    select v_id, k.origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, 'asociar', 'al_declarar', v_email
      from redes.f_evento_candidatos(z.geom, z.todo, v_desde, v_dano) k
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, 'en_atencion', 'Asociado al evento de suspensión {evento} (ya estaba recibido al declararlo)', v_email);
  perform tecnica.f_auditar(v_email, 'redes_evento_declarar', 'EVS-' || lpad(v_cons::text, 6, '0'),
          jsonb_build_object('alcance', z.alcance, 'zona', z.zona_nombre, 'contratos', c -> 'contratos', 'sensibles', c -> 'sensibles', 'asociados', coalesce(cardinality(v_ids), 0)), null);
  return redes.f_evento_json(v_id, true) || jsonb_build_object('asociados_al_declarar', coalesce(cardinality(v_ids), 0));
end $$;

-- el evento por su código, abierto y con el permiso de su alcance (lo usan regreso, cerrar y anular)
create function redes.f_evento_abierto(p_solicitante text, p_codigo text, p_para text default null, out email text, out id bigint, out codigo text, out desde timestamptz, out alcance text) returns record
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_cod text := upper(btrim(coalesce(p_codigo, ''))); e redes.v_evento_suspension%rowtype;
begin
  if v_cod !~ '^EVS-[0-9]{6}$' then perform tecnica.f_error('Escriba el código del evento (EVS-000123)'); end if;
  select * into e from redes.v_evento_suspension x where x.codigo = v_cod;
  email := redes.f_evento_autorizar(p_solicitante, coalesce(p_para, case when e.alcance = 'total' then 'total' else 'zona' end));
  if e.id is null then perform tecnica.f_error(format('No hay ningún evento con el código «%s»', v_cod), 'P0002'); end if;
  if e.estado <> 'abierto' then raise exception 'El evento % ya está %', e.codigo, e.estado using errcode = '55000', hint = 'msg_usuario'; end if;
  id := e.id; codigo := e.codigo; desde := e.desde; alcance := e.alcance;
end $$;

create function public.geoportal_redes_evento_regreso(p_solicitante text, p_codigo text, p_regreso text, p_motivo text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; v_reg timestamptz; v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo);
  v_reg := redes.f_instante(p_regreso, 'regreso estimado del servicio');
  if v_reg is null then perform tecnica.f_error('Escriba la hora estimada de regreso del servicio'); end if;
  if v_reg <= e.desde or v_reg > e.desde + interval '30 days' then perform tecnica.f_error('La hora estimada de regreso debe ser después del inicio y antes de 30 días'); end if;
  if v_mot is not null and (length(v_mot) < 10 or length(v_mot) > 500) then perform tecnica.f_error('El motivo lleva de 10 a 500 letras'); end if;
  insert into redes.evento_suspension_eventos (evento_id, tipo, regreso_estimado, motivo, hecho_en, autor) values (e.id, 'regreso', v_reg, v_mot, clock_timestamp(), e.email);
  return redes.f_evento_json(e.id);
end $$;

-- «dar de alta»: cierra el evento y, con el mismo motivo y la misma hora, los reportes asociados del bot y de la 116. Los daños quedan con la nota (siguen abiertos)
create function public.geoportal_redes_evento_cerrar(p_solicitante text, p_codigo text, p_motivo text, p_hecho_en text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; v_mot text := btrim(coalesce(p_motivo, '')); v_hecho timestamptz; v_ahora timestamptz := clock_timestamp(); v_ids bigint[]; v_l116 bigint[]; v_bot integer; v_dan integer; v_txt text;
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo);
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo del cierre (de 10 a 500 letras)'); end if;
  v_hecho := coalesce(redes.f_instante(p_hecho_en, 'hora del cierre'), v_ahora);
  if v_hecho > v_ahora + interval '5 minutes' then perform tecnica.f_error('La hora del cierre no puede ser futura'); end if;
  if v_hecho < e.desde then perform tecnica.f_error('El evento no se puede cerrar antes de la hora en que empezó'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.eventos_suspension'));
  select array_agg(r.id), count(*) filter (where r.origen = 'bot'), count(*) filter (where r.origen = 'dano') into v_ids, v_bot, v_dan from redes.f_evento_reportes(e.id) r;
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) values (e.id, 'cerrar', v_mot, v_hecho, e.email);
  v_txt := format('Evento de suspensión {evento} cerrado (%s): %s', redes.f_evento_hora(v_hecho), v_mot);
  perform redes.f_evento_marcar(v_ids, 'atendido', v_txt, e.email);
  -- línea 116: los asociados que siguen en «Registrado» pasan a «Atendido», con su hecho en el historial
  select array_agg(r.l116_reporte_id) into v_l116 from redes.f_evento_reportes(e.id) r join redes.l116_vigente v on v.reporte_id = r.l116_reporte_id
   where r.origen = 'l116' and v.estado = 'registrado';
  if v_l116 is not null then
    insert into redes.l116_eventos (reporte_id, tipo, estado, estado_antes, motivo, autor)
    select x, 'estado', 'atendido', 'registrado', left(replace(v_txt, '{evento}', e.codigo), 1000), e.email from unnest(v_l116) x order by x;
    update redes.l116_vigente set estado = 'atendido', estado_desde = v_hecho, actualizado_en = clock_timestamp() where reporte_id = any (v_l116) and estado = 'registrado';
  end if;
  perform tecnica.f_auditar(e.email, 'redes_evento_cerrar', e.codigo, jsonb_build_object('reportes', coalesce(cardinality(v_ids), 0), 'bot', v_bot, 'l116', coalesce(cardinality(v_l116), 0), 'danos', v_dan), null);
  return redes.f_evento_json(e.id) || jsonb_build_object('cerrados', jsonb_build_object('bot', v_bot, 'l116', coalesce(cardinality(v_l116), 0)), 'danos_siguen_abiertos', v_dan);
end $$;

-- anular (se declaró por error): los reportes asociados vuelven a su flujo normal
create function public.geoportal_redes_evento_anular(p_solicitante text, p_codigo text, p_motivo text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; v_mot text := btrim(coalesce(p_motivo, '')); v_ids bigint[];
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo);
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo de la anulación (de 10 a 500 letras)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.eventos_suspension'));
  select array_agg(r.id) into v_ids from redes.f_evento_reportes(e.id) r;
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) values (e.id, 'anular', v_mot, clock_timestamp(), e.email);
  perform redes.f_evento_marcar(v_ids, 'recibido', 'Evento de suspensión {evento} anulado: ' || v_mot, e.email);
  perform tecnica.f_auditar(e.email, 'redes_evento_anular', e.codigo, jsonb_build_object('reportes_liberados', coalesce(cardinality(v_ids), 0)), null);
  return redes.f_evento_json(e.id) || jsonb_build_object('reportes_liberados', coalesce(cardinality(v_ids), 0));
end $$;

-- un reporte por su referencia: bot = su id (uuid) · l116 = el número del reporte · dano = DAN-000123
create function redes.f_evento_reporte_ref(p_origen text, p_ref text, out reporte_externo_id uuid, out l116_reporte_id bigint, out dano_id uuid, out ref text) returns record
language plpgsql stable security definer set search_path = redes, tecnica, pg_temp as $$
declare v_ref text := btrim(coalesce(p_ref, ''));
begin
  if p_origen = 'bot' and v_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select r.id into reporte_externo_id from redes.reportes_externos r where r.id = v_ref::uuid;
  elsif p_origen = 'l116' and v_ref ~ '^[0-9]{1,15}$' then
    select r.id into l116_reporte_id from redes.l116_reportes r where r.reporte = v_ref::bigint;
  elsif p_origen = 'dano' and upper(v_ref) ~ '^DAN-[0-9]{6}$' then
    select d.id into dano_id from redes.danos d where d.codigo = upper(v_ref);
  else perform tecnica.f_error('Diga qué reporte es: del bot (su identificador), de la línea 116 (su número) o un daño (DAN-000123)');
  end if;
  ref := coalesce(reporte_externo_id::text, l116_reporte_id::text, dano_id::text);
  if ref is null then perform tecnica.f_error('Ese reporte no existe', 'P0002'); end if;
end $$;

create function public.geoportal_redes_evento_desasociar(p_solicitante text, p_codigo text, p_origen text, p_ref text, p_motivo text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; k record; v_mot text := btrim(coalesce(p_motivo, '')); v_id bigint;
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo, 'reportes');
  select * into k from redes.f_evento_reporte_ref(p_origen, p_ref);
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  if not exists (select 1 from redes.f_evento_reportes(e.id) r where r.origen = p_origen and r.ref = k.ref) then perform tecnica.f_error(format('Ese reporte no está asociado al evento %s', e.codigo)); end if;
  insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, tipo, modo, motivo, autor)
  values (e.id, p_origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, 'desasociar', 'manual', v_mot, e.email) returning id into v_id;
  perform redes.f_evento_marcar(array[v_id], 'recibido', 'Desasociado del evento de suspensión {evento}: ' || v_mot, e.email);
  return redes.f_evento_json(e.id);
end $$;

-- asociar a mano un reporte que no entró solo (llegó antes, es de otro tipo o quedó por fuera de la zona). No revisa la zona: lo decide el supervisor, con motivo
create function public.geoportal_redes_evento_asociar(p_solicitante text, p_codigo text, p_origen text, p_ref text, p_motivo text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; k record; v_mot text := btrim(coalesce(p_motivo, '')); v_id bigint; v_otro text;
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo, 'reportes');
  select * into k from redes.f_evento_reporte_ref(p_origen, p_ref);
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  if not redes.f_evento_ref_libre(p_origen, k.ref) then
    select x.codigo into v_otro from redes.evento_suspension_reportes r join redes.eventos_suspension x on x.id = r.evento_id where r.origen = p_origen and r.ref = k.ref order by r.id desc limit 1;
    perform tecnica.f_error(format('Ese reporte ya está asociado al evento %s', v_otro));
  end if;
  if p_origen = 'bot' and (select x.tipo from redes.reporte_externo_eventos x where x.reporte_id = k.reporte_externo_id order by x.id desc limit 1) <> 'recibido' then
    perform tecnica.f_error('Ese reporte del bot ya no está en «Recibido» (se convirtió en daño, se descartó o se atendió)');
  end if;
  insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, tipo, modo, motivo, autor)
  values (e.id, p_origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, 'asociar', 'manual', v_mot, e.email) returning id into v_id;
  perform redes.f_evento_marcar(array[v_id], 'en_atencion', 'Asociado a mano al evento de suspensión {evento}: ' || v_mot, e.email);
  return redes.f_evento_json(e.id);
end $$;

-- los eventos abiertos, para el mapa (modo «Afectaciones») y la franja: los ve cualquiera de Técnica. Con la zona en GeoJSON
create function public.geoportal_redes_eventos_vigentes(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'lectura');
begin
  return jsonb_build_object('eventos', coalesce((select jsonb_agg(redes.f_evento_json(e.id, true) order by e.id desc) from redes.f_eventos_abiertos() e), '[]'::jsonb),
                            'leyenda', jsonb_build_array(jsonb_build_object('clave', 'evento', 'texto', 'Zona sin agua (evento de suspensión)')));
end $$;

-- la lista (abiertos, o todos con los últimos primero) para el supervisor
create function public.geoportal_redes_eventos(p_solicitante text, p_estado text default 'abierto', p_limite integer default 50)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'detalle'); v_est text := coalesce(nullif(btrim(p_estado), ''), 'abierto'); v_lim integer := least(greatest(coalesce(p_limite, 50), 1), 200);
begin
  if v_est not in ('abierto', 'cerrado', 'anulado', 'todos') then perform tecnica.f_error('El estado es abierto, cerrado, anulado o todos'); end if;
  return jsonb_build_object('estado', v_est, 'eventos', coalesce((
    select jsonb_agg(redes.f_evento_json(s.id) order by s.id desc)
      from (select e.id from redes.v_evento_suspension e where v_est = 'todos' or e.estado = v_est order by e.id desc limit v_lim) s), '[]'::jsonb));
end $$;

-- el detalle: el evento, sus reportes asociados (sin nombres, direcciones ni textos del ciudadano), los sensibles confirmados (contrato y tipo) y el historial
create function public.geoportal_redes_evento(p_solicitante text, p_codigo text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'detalle'); v_cod text := upper(btrim(coalesce(p_codigo, ''))); e redes.eventos_suspension%rowtype;
        v_max integer := coalesce(redes.f_param('evento_lista_max'), 200)::integer;
begin
  if v_cod !~ '^EVS-[0-9]{6}$' then perform tecnica.f_error('Escriba el código del evento (EVS-000123)'); end if;
  select * into e from redes.eventos_suspension x where x.codigo = v_cod;
  if e.id is null then perform tecnica.f_error(format('No hay ningún evento con el código «%s»', v_cod), 'P0002'); end if;
  return redes.f_evento_json(e.id, true) || jsonb_build_object(
    'lista_max', v_max,
    'asociados', coalesce((
      select jsonb_agg(s.j order by s.id desc) from (
        select r.id, jsonb_build_object('origen', r.origen, 'modo', r.modo, 'asociado_en', r.creado_en,
                 'ref', case r.origen when 'bot' then r.ref when 'l116' then (select l.reporte::text from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                      else (select d.codigo from redes.danos d where d.id = r.dano_id) end,
                 'rotulo', case r.origen when 'bot' then (select 'Bot · ' || b.radicado from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                         when 'l116' then (select 'Línea 116 · ' || l.reporte from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                         else (select d.codigo from redes.danos d where d.id = r.dano_id) end,
                 'tipo', case r.origen when 'bot' then (select coalesce(t.nombre, b.tipo_bot) from redes.reportes_externos b left join redes.evento_tipos_asociables t on t.origen = 'bot' and t.codigo = lower(btrim(b.tipo_bot)) where b.id = r.reporte_externo_id)
                                       when 'l116' then (select l.causal from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                       else (select td.nombre from redes.danos d join redes.tipos_dano td on td.codigo = d.tipo_codigo where d.id = r.dano_id) end,
                 'cuando', case r.origen when 'bot' then (select b.recibido_en from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                         when 'l116' then (select l.fecha_registro from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                         else (select d.t_detectado from redes.danos d where d.id = r.dano_id) end,
                 'lat', case r.origen when 'bot' then (select b.lat from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                      when 'l116' then (select round(ST_Y(v.geom)::numeric, 6) from redes.l116_vigente v where v.reporte_id = r.l116_reporte_id)
                                      else (select d.lat from redes.danos d where d.id = r.dano_id) end,
                 'lon', case r.origen when 'bot' then (select b.lon from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                      when 'l116' then (select round(ST_X(v.geom)::numeric, 6) from redes.l116_vigente v where v.reporte_id = r.l116_reporte_id)
                                      else (select d.lon from redes.danos d where d.id = r.dano_id) end) as j
          from redes.f_evento_reportes(e.id) r order by r.id desc limit v_max) s), '[]'::jsonb),
    'sensibles_lista', redes.f_evento_contratos(e.geom, e.todo, true) -> 'sensibles_lista',
    'historial', coalesce((
      select jsonb_agg(h.j order by h.cuando, h.o) from (
        select x.creado_en as cuando, x.id as o, jsonb_build_object('que', x.tipo, 'cuando', x.hecho_en, 'regreso_estimado', x.regreso_estimado, 'motivo', x.motivo,
                 'por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = x.autor), 'Funcionario de EMDUPAR')) as j
          from redes.evento_suspension_eventos x where x.evento_id = e.id
        union all
        select r.creado_en, r.id, jsonb_build_object('que', case r.tipo when 'asociar' then 'asociar_a_mano' else 'desasociar' end, 'cuando', r.creado_en, 'motivo', r.motivo, 'origen', r.origen,
                 'por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = r.autor), 'Funcionario de EMDUPAR'))
          from redes.evento_suspension_reportes r where r.evento_id = e.id and r.modo = 'manual') h), '[]'::jsonb));
end $$;

-- la lista ajustable de lo que se asocia: cambia una fila (o agrega una nueva, con nombre y clase), con motivo
create function public.geoportal_redes_evento_tipo_fijar(p_solicitante text, p_origen text, p_codigo text, p_asocia boolean, p_motivo text, p_nombre text default null, p_clase text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'reportes'); v_cod text := redes.f_evento_clave(p_codigo); v_mot text := btrim(coalesce(p_motivo, ''));
        v_fila redes.evento_tipos_asociables%rowtype; v_nom text := nullif(btrim(coalesce(p_nombre, '')), ''); v_cla text := nullif(btrim(coalesce(p_clase, '')), '');
begin
  if coalesce(p_origen, '') not in ('bot', 'l116', 'dano') then perform tecnica.f_error('El origen es bot, l116 o dano'); end if;
  if length(v_cod) < 2 or length(v_cod) > 120 then perform tecnica.f_error('Escriba el tipo o la causal'); end if;
  if p_asocia is null then perform tecnica.f_error('Diga si se asocia o no'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  if v_cla is not null and v_cla not in ('sin_agua', 'dano_red', 'otro') then perform tecnica.f_error('La clase es sin_agua, dano_red u otro'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.evento_tipos_asociables'));
  select * into v_fila from redes.evento_tipos_asociables t where t.origen = p_origen and t.codigo = v_cod;
  if v_fila.codigo is null then
    if v_nom is null or v_cla is null then perform tecnica.f_error('Ese tipo no está en la lista: para agregarlo escriba su nombre y su clase'); end if;
    if p_origen = 'dano' and not exists (select 1 from redes.tipos_dano td where td.codigo = v_cod) then perform tecnica.f_error('Ese tipo de daño no existe', 'P0002'); end if;
    insert into redes.evento_tipos_asociables (origen, codigo, nombre, clase, asocia) values (p_origen, v_cod, left(v_nom, 120), v_cla, p_asocia);
  else
    update redes.evento_tipos_asociables set asocia = p_asocia, clase = coalesce(v_cla, clase), nombre = coalesce(left(v_nom, 120), nombre) where origen = p_origen and codigo = v_cod;
  end if;
  select * into v_fila from redes.evento_tipos_asociables t where t.origen = p_origen and t.codigo = v_cod;
  insert into redes.evento_tipo_eventos (origen, codigo, nombre, clase, asocia, motivo, autor) values (v_fila.origen, v_fila.codigo, v_fila.nombre, v_fila.clase, v_fila.asocia, v_mot, v_email);
  return jsonb_build_object('origen', v_fila.origen, 'codigo', v_fila.codigo, 'nombre', v_fila.nombre, 'clase', v_fila.clase, 'asocia', v_fila.asocia);
end $$;

-- qué sectores surte una planta (la lista completa cada vez; vacía = ninguno), con motivo
create function public.geoportal_redes_planta_sectores_fijar(p_solicitante text, p_planta text, p_sectores text[], p_motivo text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'reportes'); v_mot text := btrim(coalesce(p_motivo, '')); v_pl tecnica.plantas%rowtype; v_cods text[]; v_ids bigint[];
begin
  select * into v_pl from tecnica.plantas pl where pl.codigo = lower(btrim(coalesce(p_planta, ''))) and pl.activa;
  if v_pl.id is null then perform tecnica.f_error('Escoja la planta', 'P0002'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  select coalesce(array_agg(distinct upper(btrim(x))), '{}') into v_cods from unnest(coalesce(p_sectores, '{}')) x where btrim(coalesce(x, '')) <> '';
  select coalesce(array_agg(m.activo_id order by m.codigo), '{}') into v_ids from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.codigo = any (v_cods);
  if cardinality(v_ids) <> cardinality(v_cods) then perform tecnica.f_error('Alguno de los sectores no existe o ya no está vigente', 'P0002'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.planta_sectores'));
  update redes.planta_sectores set activo = false where planta_id = v_pl.id and activo and sector_id <> all (v_ids);
  insert into redes.planta_sectores (planta_id, sector_id) select v_pl.id, x from unnest(v_ids) x
  on conflict (planta_id, sector_id) do update set activo = true;
  insert into redes.planta_sector_eventos (planta_id, sectores, motivo, autor) values (v_pl.id, v_ids, v_mot, v_email);
  return jsonb_build_object('planta', v_pl.codigo, 'nombre', v_pl.nombre, 'sectores', to_jsonb(v_cods));
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 25 — REEMPLAZO (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- es el texto vivo de tecnica.f_avisos (el del Corte 14) con UN cambio exacto: dos bloques nuevos antes del de Personal.
--   · D15: un aviso por evento de suspensión abierto (rojo si ya pasó la hora estimada de regreso);
--   · D15b: un aviso con los reportes de falta de agua (bot y línea 116) que no están en ningún evento.
-- =====================================================================

-- tecnica.f_avisos(boolean,boolean,timestamptz)
CREATE OR REPLACE FUNCTION tecnica.f_avisos(p_planta boolean, p_distribucion boolean, p_ahora timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'redes', 'extensions', 'pg_temp'
AS $function$
declare
  v_ahora timestamptz := coalesce(p_ahora, clock_timestamp());
  v_loc timestamp := coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota';
  v_hoy date := (coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota')::date;
  v_h numeric := extract(hour from (coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota')) + extract(minute from (coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota')) / 60.0;
  v_av jsonb := '[]'::jsonb;
  r record; v_n bigint; v_items jsonb; v_items2 jsonb; v_dz jsonb; v_desde timestamptz; v_dias integer; v_x numeric; v_y numeric; v_z numeric;
  v_ini numeric; v_fin numeric; v_primer numeric; v_sin numeric;
begin
  -- ===================== PLANTAS =====================
  if p_planta then
    v_ini := tecnica.f_aparam('horario_inicio'); v_fin := tecnica.f_aparam('horario_fin');
    v_primer := tecnica.f_aparam('planta_primer_registro_hora'); v_sin := tecnica.f_aparam('planta_horas_sin_registro');
    -- P1. Entrada y Salida sin registrar hoy, por planta, dentro del horario del personal (8 a. m. a 6 p. m.)
    if v_h >= greatest(v_ini, v_primer) then
      for r in select p.codigo, p.nombre, f.form, f.titulo, f.ord,
                      (select max(x.muestra_ts) from tecnica.v_registros_estado x
                        where x.formulario::text = f.form and x.planta_id = p.id and x.fecha_muestra = v_hoy and not x.excluido and x.muestra_ts <= v_ahora) as ultimo
                 from tecnica.plantas p cross join (values ('entrada', 'Entrada', 1), ('salida', 'Salida', 2)) f(form, titulo, ord)
                where p.activa order by p.id, f.ord loop
        if r.ultimo is null and v_h >= v_fin then
          v_av := v_av || jsonb_build_object('clave', 'planta_' || r.form || ':' || r.codigo, 'area', 'planta', 'nivel', 'rojo', 'orden', 10 + r.ord,
                    'titulo', format('%s sin registros hoy en %s', r.titulo, r.nombre), 'detalle', 'Cerró el horario del personal sin ningún registro del día.',
                    'n', 1, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'registros'), 'desde', null);
        elsif r.ultimo is null and v_h < v_fin then
          v_av := v_av || jsonb_build_object('clave', 'planta_' || r.form || ':' || r.codigo, 'area', 'planta', 'nivel', 'naranja', 'orden', 10 + r.ord,
                    'titulo', format('%s sin el primer registro del día en %s', r.titulo, r.nombre),
                    'detalle', format('Ningún registro hoy; el primero se espera antes de las %s:00.', v_primer),
                    'n', 1, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'registros'), 'desde', null);
        elsif r.ultimo is not null and v_h < v_fin and v_ahora - r.ultimo > make_interval(secs => (v_sin * 3600)::double precision) then
          v_av := v_av || jsonb_build_object('clave', 'planta_' || r.form || ':' || r.codigo, 'area', 'planta', 'nivel', 'naranja', 'orden', 10 + r.ord,
                    'titulo', format('%s sin registro hace %s en %s', r.titulo, tecnica.f_texto_horas(extract(epoch from v_ahora - r.ultimo)::numeric / 3600), r.nombre),
                    'detalle', format('El último registro de hoy fue a las %s.', to_char(r.ultimo at time zone 'America/Bogota', 'HH24:MI')),
                    'n', 1, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'registros'), 'desde', r.ultimo);
        end if;
      end loop;
    end if;

    -- P2. Puntos de muestreo sin muestra en los últimos días (el mismo parámetro del geovisor: geovisor_muestreo_dias, 35)
    v_dias := floor(redes.f_param('geovisor_muestreo_dias'))::integer;
    select count(*), coalesce(jsonb_agg(s.codigo || ' · ' || s.nombre order by s.o, s.codigo) filter (where s.rn <= 5), '[]'::jsonb) into v_n, v_items
      from (select p.codigo, p.nombre, coalesce(p.orden, 999999) as o, row_number() over (order by coalesce(p.orden, 999999), p.codigo) as rn
              from tecnica.puntos p
             where p.tipo = 'muestreo' and p.activo
               and p.id not in (select x.punto_id from tecnica.v_registros_estado x
                                 where x.formulario::text = 'muestreo' and x.punto_id is not null and not x.excluido
                                   and x.muestra_ts >= v_ahora - make_interval(days => v_dias) and x.muestra_ts <= v_ahora)) s;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'muestreo_sin_muestra', 'area', 'planta', 'nivel', 'naranja', 'orden', 20,
                'titulo', format('%s sin muestra en %s días', tecnica.f_cuantos(v_n, 'punto de muestreo', 'puntos de muestreo'), v_dias), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'puntos'), 'desde', null);
    end if;

    -- P3. Último cloro o última turbiedad fuera de rango (la misma calidad que pinta el geovisor: redes.f_muestreo_calidad)
    select count(*), coalesce(jsonb_agg(s.txt order by s.o, s.codigo) filter (where s.rn <= 5), '[]'::jsonb) into v_n, v_items
      from (select c.codigo, c.o, row_number() over (order by c.o, c.codigo) as rn,
                   c.codigo || ' · ' || (select string_agg(format('%s %s %s', m ->> 'nombre', tecnica.f_texto_num((m ->> 'valor')::numeric), coalesce(m ->> 'unidad', '')), ', ')
                                           from jsonb_array_elements(c.cal -> 'medidas') m where (m ->> 'reciente')::boolean and (m ->> 'dentro')::boolean is false) as txt
              from (select p.codigo, coalesce(p.orden, 999999) as o, redes.f_muestreo_calidad(p.id) as cal from tecnica.puntos p where p.tipo = 'muestreo' and p.activo) c
             where c.cal ->> 'calidad' = 'fuera') s;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'muestreo_fuera_rango', 'area', 'planta', 'nivel', 'rojo', 'orden', 21,
                'titulo', format('%s con el último cloro o la última turbiedad fuera de rango', tecnica.f_cuantos(v_n, 'punto', 'puntos')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'eventos'), 'desde', null);
    end if;

    -- P4. Químicos: días con dosis y caudal sin uso, y desvío de esperado contra usado (los últimos días cerrados, hasta ayer; la misma cuenta del Corte 7a)
    v_dias := floor(tecnica.f_aparam('quimicos_dias_revisar'))::integer;
    v_x := tecnica.f_qparam('desvio_pct');
    with filas as (
      select d.dia, p.nombre as planta, v.nombre as quimico, qi.qi,
             coalesce((select m.dosis_optima_ppm from tecnica.quimico_movimientos m where m.tipo = 'uso' and m.para_que = 'dosificacion' and m.quimico_id = v.quimico_id
                        and m.planta_id = p.id and m.dia = d.dia and m.dosis_optima_ppm is not null order by m.id desc limit 1),
                      tecnica.f_dosis_optima_en(v.quimico_id, ((d.dia + 1)::timestamp at time zone 'America/Bogota'))) as dosis,
             coalesce((select -sum(m.cantidad_kg) from tecnica.quimico_movimientos m where m.tipo = 'uso' and m.para_que = 'dosificacion' and m.quimico_id = v.quimico_id
                        and m.planta_id = p.id and m.dia = d.dia), 0) as usado
        from generate_series(v_hoy - v_dias, v_hoy - 1, interval '1 day') d0(t) cross join lateral (select d0.t::date as dia) d
        cross join tecnica.plantas p cross join tecnica.v_quimico_vigente v
        cross join lateral (select avg(r2.valor) as qi from tecnica.v_registros_estado r2
                             where r2.formulario::text = 'entrada' and r2.planta_id = p.id and r2.fecha_muestra = d.dia and not r2.excluido
                               and r2.variable_id = (select id from tecnica.variables where codigo = 'caudal_qi')) qi
       where p.activa and v.potabilizacion and v.activo and qi.qi is not null),
    calc as (select f.*, f.dosis * f.qi * 86.4 / 1000 as esperado from filas f where f.dosis is not null)
    select count(*) filter (where c.esperado > 0 and c.usado = 0),
           coalesce(jsonb_agg(to_char(c.dia, 'DD/MM') || ' · ' || c.planta || ' · ' || c.quimico order by c.dia desc, c.planta, c.quimico) filter (where c.esperado > 0 and c.usado = 0), '[]'::jsonb),
           count(*) filter (where c.esperado > 0 and c.usado > 0 and abs(c.usado - c.esperado) > c.esperado * v_x / 100),
           coalesce(jsonb_agg(to_char(c.dia, 'DD/MM') || ' · ' || c.planta || ' · ' || c.quimico || ' · ' || case when c.usado > c.esperado then '+' else '' end
                              || round((c.usado - c.esperado) / c.esperado * 100) || ' %' order by c.dia desc, c.planta, c.quimico)
                    filter (where c.esperado > 0 and c.usado > 0 and abs(c.usado - c.esperado) > c.esperado * v_x / 100), '[]'::jsonb)
      into v_n, v_items, v_y, v_items2
      from calc c;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_sin_uso', 'area', 'planta', 'nivel', 'naranja', 'orden', 30,
                'titulo', format('%s con dosis y caudal sin uso de químicos registrado', tecnica.f_cuantos(v_n, 'día', 'días')),
                'detalle', format('Revisados los últimos %s días cerrados.', v_dias),
                'n', v_n, 'items', (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(v_items) with ordinality t(e, i) where i <= 5) z), 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;
    if v_y > 0 and tecnica.f_qparam('marca_esperado_usado') = 1 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_desvio', 'area', 'planta', 'nivel', 'naranja', 'orden', 31,
                'titulo', format('%s con el uso de químicos fuera del %s %% de lo esperado', tecnica.f_cuantos(v_y::bigint, 'día', 'días'), tecnica.f_texto_num(v_x)),
                'detalle', format('Revisados los últimos %s días cerrados.', v_dias),
                'n', v_y, 'items', (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(v_items2) with ordinality t(e, i) where i <= 5) z),
                'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;

    -- P5. Químicos de potabilización sin dosis óptima o sin ficha técnica en PDF
    select count(*), coalesce(jsonb_agg(v.nombre || ' · ' || concat_ws(' y ', case when v.dosis_optima_ppm is null then 'sin dosis óptima' end,
                                                                     case when v.ficha_ruta is null then 'sin ficha en PDF' end) order by v.nombre), '[]'::jsonb)
      into v_n, v_items
      from tecnica.v_quimico_vigente v where v.activo and v.potabilizacion and (v.dosis_optima_ppm is null or v.ficha_ruta is null);
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_ficha', 'area', 'planta', 'nivel', 'naranja', 'orden', 32,
                'titulo', format('%s de potabilización sin dosis óptima o sin ficha técnica', tecnica.f_cuantos(v_n, 'químico', 'químicos')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;

    -- P6. Saldo por debajo del mínimo (el mínimo lo fija el supervisor de planta por químico; sin mínimo fijado no hay aviso)
    select count(*), coalesce(jsonb_agg(s.nombre || ' · ' || tecnica.f_texto_num(s.saldo_kg) || ' kg (mínimo ' || tecnica.f_texto_num(m.minimo_kg) || ' kg)' order by s.nombre), '[]'::jsonb)
      into v_n, v_items
      from tecnica.v_quimico_saldo s
      join tecnica.quimicos q on q.id = s.quimico_id and q.activo
      cross join lateral (select e.minimo_kg from tecnica.quimico_minimo_eventos e where e.quimico_id = s.quimico_id order by e.id desc limit 1) m
     where m.minimo_kg is not null and s.saldo_kg is not null and s.saldo_kg < m.minimo_kg;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_saldo', 'area', 'planta', 'nivel', 'naranja', 'orden', 33,
                'titulo', format('%s por debajo del saldo mínimo', tecnica.f_cuantos(v_n, 'químico', 'químicos')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;

    -- P7. Ubicaciones de puntos de muestreo pendientes de aprobar (Corte 5b)
    select count(*), coalesce(jsonb_agg(s.codigo order by s.creado_en) filter (where s.rn <= 5), '[]'::jsonb), min(s.creado_en) into v_n, v_items, v_desde
      from (select p.codigo, pr.creado_en, row_number() over (order by pr.creado_en) as rn
              from tecnica.v_punto_propuestas pr join tecnica.puntos p on p.id = pr.punto_id where pr.estado = 'pendiente') s;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'ubicaciones_pendientes', 'area', 'planta', 'nivel', 'naranja', 'orden', 40,
                'titulo', format('%s de puntos de muestreo por aprobar', tecnica.f_cuantos(v_n, 'ubicación', 'ubicaciones')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'puntos'), 'desde', v_desde);
    end if;
  end if;

  -- ===================== DISTRIBUCIÓN =====================
  if p_distribucion then
    -- D1. Daños abiertos o en atención según su riesgo (alto: 2 h y 6 h; medio o sin riesgo: 24 h y 72 h; bajo: 72 h y 7 días). Avisan a cualquier hora.
    -- redes.v_dano se lee UNA sola vez para D1 y D2 (es la vista más cara): los abiertos o en atención y los atendidos de los últimos días
    select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'riesgo', coalesce(x.riesgo, 'medio'), 't', x.t_detectado, 'estado', x.estado,
                                                 'fin', coalesce(x.t_restablecido, x.registrado_en),
                                                 'itv', x.estado = 'atendido' and exists (select 1 from redes.intervenciones i where i.dano_id = x.id))), '[]'::jsonb) into v_dz
      from redes.v_dano x
     where x.t_detectado <= v_ahora
       and (x.estado in ('reportado', 'en_atencion')
            or (x.estado = 'atendido' and coalesce(x.t_restablecido, x.registrado_en) >= v_ahora - make_interval(days => floor(tecnica.f_aparam('dano_sin_itv_dias'))::integer)));
    with d as (
      select z.codigo, z.riesgo, z.t as t_detectado, extract(epoch from v_ahora - z.t)::numeric / 3600 as h
        from jsonb_to_recordset(v_dz) z(codigo text, riesgo text, t timestamptz, estado text) where z.estado in ('reportado', 'en_atencion')),
    n as (
      select d.*, case when d.h >= tecnica.f_aparam('dano_' || d.riesgo || '_rojo_h') then 'rojo'
                       when d.h >= tecnica.f_aparam('dano_' || d.riesgo || '_naranja_h') then 'naranja' end as nivel from d)
    select jsonb_agg(z.a) into v_items
      from (select jsonb_build_object('clave', 'danos_' || n.nivel, 'area', 'distribucion', 'nivel', n.nivel, 'orden', case n.nivel when 'rojo' then 100 else 101 end,
                     'titulo', case when n.nivel = 'rojo' and count(*) = 1 then '1 daño abierto pasó su plazo'
                                    when n.nivel = 'rojo' then count(*) || ' daños abiertos pasaron su plazo'
                                    when count(*) = 1 then '1 daño abierto se acerca a su plazo'
                                    else count(*) || ' daños abiertos se acercan a su plazo' end,
                     'detalle', format('Plazos: riesgo alto %s y %s h; medio %s y %s h; bajo %s y %s h.', tecnica.f_aparam('dano_alto_naranja_h'), tecnica.f_aparam('dano_alto_rojo_h'),
                                       tecnica.f_aparam('dano_medio_naranja_h'), tecnica.f_aparam('dano_medio_rojo_h'), tecnica.f_aparam('dano_bajo_naranja_h'), tecnica.f_aparam('dano_bajo_rojo_h')),
                     'n', count(*),
                     'items', (array_to_json((array_agg(n.codigo || ' · riesgo ' || n.riesgo || ' · abierto hace ' || tecnica.f_texto_horas(n.h)
                                                        order by case n.riesgo when 'alto' then 1 when 'medio' then 2 else 3 end, n.h desc))[1:5]))::jsonb,
                     'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'danos'), 'desde', min(n.t_detectado)) as a
              from n where n.nivel is not null group by n.nivel) z;
    v_av := v_av || coalesce(v_items, '[]'::jsonb);

    -- D2. Daños atendidos en los últimos días sin ninguna intervención registrada
    select count(*), coalesce((array_to_json((array_agg(z.codigo order by z.fin desc))[1:5]))::jsonb, '[]'::jsonb) into v_n, v_items
      from jsonb_to_recordset(v_dz) z(codigo text, estado text, fin timestamptz, itv boolean)
     where z.estado = 'atendido' and not z.itv;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'danos_sin_intervencion', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 110,
                'titulo', format('%s sin intervención registrada', tecnica.f_cuantos(v_n, 'daño atendido', 'daños atendidos')),
                'detalle', format('Atendidos en los últimos %s días.', tecnica.f_aparam('dano_sin_itv_dias')),
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'danos'), 'desde', null);
    end if;

    -- D3. Daños e intervenciones con el activo no identificado (por asociar o crear)
    select count(*), coalesce((array_to_json((array_agg(x.codigo order by x.registrado_en))[1:5]))::jsonb, '[]'::jsonb), min(x.registrado_en) into v_n, v_items, v_desde
      from redes.v_no_identificados x;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'no_identificados', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 120,
                'titulo', format('%s con el activo sin identificar', tecnica.f_cuantos(v_n, 'registro', 'registros')), 'detalle', 'Daños o intervenciones por asociar a un activo.',
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'no_identificados'), 'desde', v_desde);
    end if;

    -- D4. Intervenciones con los recursos sin completar
    select count(*), coalesce((array_to_json((array_agg(x.codigo order by x.registrado_en))[1:5]))::jsonb, '[]'::jsonb), min(x.registrado_en) into v_n, v_items, v_desde
      from redes.v_intervencion x where x.estado <> 'oculta' and x.recursos = 'por_completar';
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'recursos_por_completar', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 130,
                'titulo', format('%s con los recursos sin completar', tecnica.f_cuantos(v_n, 'intervención', 'intervenciones')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'intervenciones'), 'desde', v_desde);
    end if;

    -- D5. Reportes del bot sin convertir ni descartar
    select count(*), coalesce((array_to_json((array_agg(coalesce(x.radicado, 'Sin radicado') || ' · hace ' || tecnica.f_texto_horas(extract(epoch from v_ahora - x.recibido_en)::numeric / 3600)
                                                        order by x.recibido_en))[1:5]))::jsonb, '[]'::jsonb), min(x.recibido_en) into v_n, v_items, v_desde
      from redes.v_reporte_externo x where x.ultimo_evento = 'recibido';
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'reportes_bot', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 140,
                'titulo', format('%s sin atender', tecnica.f_cuantos(v_n, 'reporte del bot', 'reportes del bot')), 'detalle', 'Convertir en daño o descartar con motivo.',
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'bot'), 'desde', v_desde);
    end if;

    -- D6. Línea 116: reportes en «Registrado» desde hace más de N días. Queda listo y APAGADO hasta que el Corte 5d esté publicado (sin su tabla no hay aviso).
    if to_regclass('redes.l116_vigente') is not null then
      execute 'select count(*), min(estado_desde) from redes.l116_vigente where not oculto and estado = ''registrado'' and estado_desde < $1'
         into v_n, v_desde using v_ahora - make_interval(days => floor(tecnica.f_aparam('l116_registrado_dias'))::integer);
      if v_n > 0 then
        v_av := v_av || jsonb_build_object('clave', 'l116_registrado', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 150,
                  'titulo', format('%s de la línea 116 en «Registrado» hace más de %s días', tecnica.f_cuantos(v_n, 'reporte', 'reportes'), tecnica.f_aparam('l116_registrado_dias')),
                  'detalle', 'La línea 116 es de referencia: el cierre lo hace el sistema comercial.',
                  'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', v_desde);
      end if;
    end if;

    -- D7. Cargas de capas abiertas sin publicar ni anular
    select count(*), coalesce((array_to_json((array_agg(x.capa_codigo || ' · abierta hace ' || tecnica.f_texto_horas(extract(epoch from v_ahora - x.creado_en)::numeric / 3600) order by x.creado_en))[1:5]))::jsonb, '[]'::jsonb),
           min(x.creado_en) into v_n, v_items, v_desde
      from redes.v_cargas_estado x where x.estado = 'abierta' and x.creado_en < v_ahora - make_interval(secs => (tecnica.f_aparam('carga_abierta_horas') * 3600)::double precision);
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'cargas_abiertas', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 160,
                'titulo', format('%s del Cargue de capas sin publicar', tecnica.f_cuantos(v_n, 'carga abierta', 'cargas abiertas')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'cargue'), 'desde', v_desde);
    end if;

    -- D8. Activos «por verificar» (la misma regla de la bandeja: el último evento de verificación es «por_verificar» y el activo no está retirado)
    select count(*) into v_n
      from (select distinct on (e.activo_id) e.activo_id, e.tipo from redes.activo_eventos e where e.tipo in ('verificar', 'por_verificar') order by e.activo_id, e.id desc) u
     where u.tipo = 'por_verificar' and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = u.activo_id and not m.retirado);
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'por_verificar', 'area', 'distribucion', 'nivel', 'info', 'orden', 170,
                'titulo', format('%s por verificar', tecnica.f_cuantos(v_n, 'activo', 'activos')), 'detalle', null,
                'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'por_verificar'), 'desde', null);
    end if;

    -- D9. Nodos por clasificar
    select count(*) into v_n from redes.v_nodo_visible x where x.clase_nodo = 'por_clasificar';
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'nodos_por_clasificar', 'area', 'distribucion', 'nivel', 'info', 'orden', 180,
                'titulo', format('%s por clasificar', tecnica.f_cuantos(v_n, 'nodo', 'nodos')), 'detalle', null,
                'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'nodos'), 'desde', null);
    end if;
  end if;

  -- D10 (Corte 9b, Fase 1b). Válvulas cerradas (sin «abrir») hace más de X horas: naranja desde valvula_cerrada_naranja_h, rojo desde valvula_cerrada_rojo_h
  if p_distribucion then
    for r in select c.nivel, count(*) as n, min(c.hecho_en) as desde,
                    (array_to_json((array_agg(c.codigo || coalesce(' · ' || c.registro, '') || ' · hace ' || tecnica.f_texto_horas(c.horas) order by c.hecho_en))[1:5]))::jsonb as items
               from redes.f_cortes_para_avisos(v_ahora, tecnica.f_aparam('valvula_cerrada_naranja_h'), tecnica.f_aparam('valvula_cerrada_rojo_h')) c
              group by c.nivel loop
      v_av := v_av || jsonb_build_object('clave', 'valvulas_cerradas_' || r.nivel, 'area', 'distribucion', 'nivel', r.nivel, 'orden', case r.nivel when 'rojo' then 102 else 103 end,
                'titulo', format('%s hace más de %s', tecnica.f_cuantos(r.n, 'válvula cerrada', 'válvulas cerradas'),
                                 tecnica.f_texto_horas(tecnica.f_aparam(case r.nivel when 'rojo' then 'valvula_cerrada_rojo_h' else 'valvula_cerrada_naranja_h' end))),
                'detalle', 'Abra la válvula cuando vuelva el servicio, o ajuste la hora estimada de regreso.',
                'n', r.n, 'items', r.items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', r.desde);
    end loop;
  end if;

  -- D11 (Corte 9b, Fase 2). Presión de MODELO fuera de rango (Res. 0330 de 2017): un solo aviso informativo. APAGADO por omisión: solo sale si el
  -- parámetro «presion_modelo_aviso» vale 1 (lo enciende Técnica). Solo con las horas confiables del modelo (redes.f_presion_nodos). Los umbrales se leen una vez
  if p_distribucion and coalesce(tecnica.f_aparam('presion_modelo_aviso'), 0) >= 1 then
    v_x := redes.f_param('presion_baja_naranja_mca'); v_y := redes.f_param('presion_alta_naranja_mca');
    select count(*) into v_n from redes.f_presion_nodos('existente') x where x.p_min < v_x or x.p_max > v_y;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'presion_modelo', 'area', 'distribucion', 'nivel', 'info', 'orden', 175,
                'titulo', format('%s %s fuera de rango según el modelo', tecnica.f_texto_num(v_n), case when v_n = 1 then 'nodo' else 'nodos' end),      -- con punto de miles
                'detalle', format('Presión de modelo, no medida (Plan Maestro 2014): mínima bajo %s o máxima sobre %s m.c.a., sin las horas en que el modelo no es confiable.', v_x, v_y),
                'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', null);
    end if;
  end if;

  -- D14 (Corte 14). Activos por levantar («Encontrar o reportar activo»): informativo; naranja si alguno lleva más de levantar_naranja_dias sin levantar
  if p_distribucion then
    v_dias := floor(coalesce(tecnica.f_aparam('levantar_naranja_dias'), 30))::integer;
    select count(*), min(s.registrado_en), count(*) filter (where s.registrado_en < v_ahora - make_interval(days => v_dias)),
           coalesce(jsonb_agg(s.txt order by s.registrado_en, s.codigo) filter (where s.rn <= 5), '[]'::jsonb)
      into v_n, v_desde, v_x, v_items
      from (select p.codigo, p.registrado_en, row_number() over (order by p.registrado_en, p.codigo) as rn,
                   p.codigo || ' · ' || redes.f_levantar_tipo_nombre(p.tipo) || ' de ' || p.servicio as txt
              from redes.v_levantar_punto p where p.estado in ('reportado', 'asignado') and p.registrado_en <= v_ahora) s;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'activos_por_levantar', 'area', 'distribucion', 'nivel', case when v_x > 0 then 'naranja' else 'info' end, 'orden', 180,
                'titulo', format('%s por levantar', tecnica.f_cuantos(v_n, 'activo reportado', 'activos reportados')),
                'detalle', case when v_x > 0 then format('%s más de %s días sin levantar.', case when v_x = 1 then '1 lleva' else v_x::integer || ' llevan' end, v_dias)
                                else 'Encontrados en la calle y no están en la red: asígnelos a levantamiento.' end,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'por_verificar', 'filtro', 'levantar'), 'desde', v_desde);
    end if;
  end if;

  -- D15 (Corte 15). Eventos de suspensión: UN aviso por evento abierto (no uno por reporte); rojo si ya pasó la hora estimada de regreso.
  -- Al supervisor de distribución, todos; al de planta, los eventos totales.
  if p_distribucion or p_planta then
    for r in select x.codigo, x.alcance, x.nivel, x.titulo, x.detalle, x.n, x.desde from redes.f_eventos_para_avisos(v_ahora) x
              where p_distribucion or x.alcance = 'total' order by x.desde loop
      v_av := v_av || jsonb_build_object('clave', 'evento_suspension_' || lower(r.codigo), 'area', case when p_distribucion then 'distribucion' else 'planta' end,
                'nivel', r.nivel, 'orden', 100, 'titulo', r.titulo, 'detalle', r.detalle, 'n', r.n, 'items', '[]'::jsonb,
                'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null, 'evento', r.codigo), 'desde', r.desde);
    end loop;
  end if;
  -- D15b. Reportes de falta de agua o baja presión (bot y línea 116) de las últimas horas que NO están en ningún evento: un solo aviso
  if p_distribucion then
    select x.n, x.desde, x.items into v_n, v_desde, v_items from redes.f_sin_agua_para_avisos(v_ahora, coalesce(tecnica.f_aparam('sin_agua_ventana_h'), 24)) x;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'sin_agua_sin_evento', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 101,
                'titulo', format('%s de falta de agua sin evento', tecnica.f_cuantos(v_n, 'reporte', 'reportes')),
                'detalle', format('Llegaron en las últimas %s horas y no están en ningún evento de suspensión: revise si hay que declarar uno.', coalesce(tecnica.f_aparam('sin_agua_ventana_h'), 24)),
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', v_desde);
    end if;
  end if;

  -- ===================== PERSONAL (los dos supervisores y el administrador) =====================
  if p_planta or p_distribucion then
    for r in
      with pob as (
        select lb.email, coalesce(nullif(btrim(lb.nombre), ''), lb.email) as nombre,
               (lb.ver_registro_tecnico and not lb.ver_dashboard_tecnico and not lb.ver_dashboard_redes) as operador, f.area, f.cuadrilla_id
          from public.geoportal_lista_blanca lb left join redes.v_personal_ficha f on f.persona = lb.email
         where lb.activo and lb.rol <> 'admin' and (lb.ver_registro_tecnico or lb.ver_dashboard_redes or lb.ver_dashboard_tecnico) and tecnica.f_tecnica_activa(lb.email)),
      cat as (
        select 'personal_sin_formularios' as clave, 300 as orden, 'persona activa sin formularios' as uno, 'personas activas sin formularios' as varios, p.nombre
          from pob p
         where p.operador and not exists (select 1 from (select distinct on (e.formulario) e.tipo_evento from tecnica.personal_tecnico_eventos e
                                                         where e.persona = p.email and e.tipo_evento in ('asignar_formulario', 'quitar_formulario') and e.formulario is not null
                                                         order by e.formulario, e.id desc) x where x.tipo_evento = 'asignar_formulario')
        union all select 'personal_sin_area', 301, 'persona activa sin área', 'personas activas sin área', p.nombre from pob p where p.area is null
        union all select 'personal_sin_cuadrilla', 302, 'persona de distribución sin cuadrilla', 'personas de distribución sin cuadrilla', p.nombre
          from pob p where p.operador and p.area in ('distribucion', 'ambas') and p.cuadrilla_id is null)
      select c.clave, c.orden, count(*) as n, min(c.uno) as uno, min(c.varios) as varios, (array_to_json((array_agg(c.nombre order by lower(c.nombre)))[1:5]))::jsonb as items
        from cat c group by c.clave, c.orden order by c.orden
    loop
      v_av := v_av || jsonb_build_object('clave', r.clave, 'area', 'personal', 'nivel', 'naranja', 'orden', r.orden,
                'titulo', tecnica.f_cuantos(r.n, r.uno, r.varios), 'detalle', null, 'n', r.n, 'items', r.items,
                'bandeja', jsonb_build_object('tablero', 'personal', 'pestana', 'personal'), 'desde', null);
    end loop;
  end if;

  return coalesce((select jsonb_agg(a order by case a ->> 'nivel' when 'rojo' then 1 when 'naranja' then 2 else 3 end, (a ->> 'orden')::integer, a ->> 'clave')
                     from jsonb_array_elements(v_av) a), '[]'::jsonb);
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 40 — PERMISOS: revoke all antes de dar permisos.
-- Las internas de redes (y la del bot): nadie de la API. Las 13 RPC: solo service_role. El permiso del Dell para la función del bot va en otro paquete.
-- =====================================================================
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as f, p.pronamespace = 'public'::regnamespace as rpc from pg_proc p
            where (p.pronamespace = 'redes'::regnamespace and (p.proname like 'f\_evento%' or p.proname in ('f_sin_agua_para_avisos', 'f_reporte_externo_recibir_evento')))
               or (p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\_redes\_evento%' or p.proname = 'geoportal_redes_planta_sectores_fijar')) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', r.f);
    if r.rpc then execute format('grant execute on function %s to service_role', r.f); end if;
  end loop;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte15', 'migracion_redes_corte15', null, jsonb_build_object(
        'tablas', jsonb_build_array('eventos_suspension', 'evento_suspension_eventos', 'evento_suspension_reportes', 'evento_tipos_asociables', 'evento_tipo_eventos', 'planta_sectores', 'planta_sector_eventos'),
        'disparadores', jsonb_build_array('redes.reporte_externo_eventos', 'redes.l116_eventos', 'redes.danos'),
        'reemplazada', 'tecnica.f_avisos', 'tipo_de_campo', 'sin_agua',
        'motivo', 'Corte 15: evento de suspensión (por sectores, por círculo o total), asociación automática de reportes, cierre en bloque y un aviso por evento'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes9b.*), tres sectores de prueba y su red ZT9B (en un rincón de la caja), sus contratos
-- (99999…), dos usuarios sensibles confirmados, reportes del bot, de la línea 116 y daños, y los eventos con las RPC del corte.
-- Mide con volumen: la zona grande cubre la red real de la base (todos sus contratos), 300 eventos viejos y una carga de 5.000 reportes de la 116.
-- FALLA si la asociación de un reporte, declarar, cerrar o los avisos pasan de 1 s. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 15, evento de suspensión … RESULTADO: N de N pruebas correctas — SIN FALLAS
-- =====================================================================
create temp table _r (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.reg(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as
$$ insert into _r (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $$;
create function pg_temp.err(p_nombre text, p_sql text, p_estado text default null, p_texto text default null) returns void language plpgsql as $$
declare v_e text; v_m text;
begin
  begin
    execute p_sql;
    perform pg_temp.reg(p_nombre, false, 'No falló y debía fallar');
  exception when others then
    get stacked diagnostics v_e = returned_sqlstate, v_m = message_text;
    perform pg_temp.reg(p_nombre, (p_estado is null or v_e = p_estado) and (p_texto is null or position(p_texto in v_m) > 0), 'SQLSTATE ' || v_e || ': ' || left(v_m, 200));
  end;
end $$;
-- un rincón de la caja de Valledupar, lejos de la red (x, y en metros aproximados)
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.1300 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.5800 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create temp table _zt (nombre text primary key, activo_id bigint, nodo bigint, x numeric, y numeric);
-- un activo de prueba (versión 1); devuelve su id
create function pg_temp.activo(p_nombre text, p_prefijo text, p_geom geometry, p_clase text default null, p_efecto text default null, p_estado text default 'en_operacion')
returns bigint language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes9b.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZT9B ' || p_nombre, p_clase, p_efecto,
          case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end, case when p_prefijo = 'RED' then 110 end,
          p_estado, '{}'::jsonb, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT9B activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_id;
end $$;
-- un nodo de la red de prueba (con su activo si es válvula o tanque)
create function pg_temp.nodo(p_nombre text, x numeric, y numeric, p_carga bigint, p_prefijo text default null, p_clase text default null, p_efecto text default null)
returns void language plpgsql as $$
declare v_act bigint; v_n bigint;
begin
  if p_prefijo is not null then v_act := pg_temp.activo(p_nombre, p_prefijo, pg_temp.pt(x, y), p_clase, p_efecto); end if;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id)
  values ('acueducto', 'ZT9B-' || p_nombre, 'ZT9B' || p_nombre, case when v_act is null then 'por_clasificar' else 'activo' end, pg_temp.pt(x, y), v_act, 0, p_carga)
  returning id into v_n;
  insert into _zt values (p_nombre, v_act, v_n, x, y);
end $$;
-- un tramo de la red de prueba entre dos nodos, con n contratos de prueba
create function pg_temp.tramo(p_nombre text, p_a text, p_b text, p_carga bigint, p_contratos integer, p_estado text default 'en_operacion')
returns void language plpgsql as $$
declare a _zt; b _zt; v_id bigint;
begin
  select * into a from _zt where nombre = p_a; select * into b from _zt where nombre = p_b;
  v_id := pg_temp.activo(p_nombre, 'RED', ST_MakeLine(pg_temp.pt(a.x, a.y), pg_temp.pt(b.x, b.y)), null, null, p_estado);
  insert into redes.tramo_nodos (activo_id, version, nodo_ini, nodo_fin, metodo, carga_id) values (v_id, 1, a.nodo, b.nodo, 'modelo', p_carga);
  insert into _zt values (p_nombre, v_id, null, (a.x + b.x) / 2, (a.y + b.y) / 2);
  insert into redes.contrato_tramo (contrato, activo_id, distancia_m, metodo)
  select '99999' || lpad((v_id % 100000)::text, 5, '0') || lpad(i::text, 5, '0'), v_id, 5, 'cercania' from generate_series(1, p_contratos) i;
end $$;
create function pg_temp.id(p_nombre text) returns bigint language sql as $$ select activo_id from _zt where nombre = p_nombre $$;
create function pg_temp.cod(p_nombre text) returns text language sql as $$ select a.codigo from redes.activos a join _zt z on z.activo_id = a.id where z.nombre = p_nombre $$;
create function pg_temp.cods(p jsonb) returns text language sql as $$ select coalesce(string_agg(x ->> 'codigo', ',' order by o), '') from jsonb_array_elements(p) with ordinality y(x, o) $$;
create function pg_temp.ncods(p text) returns text language sql as $$
  select coalesce(string_agg(pg_temp.cod(btrim(x)), ',' order by o), '') from unnest(string_to_array(p, ',')) with ordinality u(x, o) $$;
-- la tesela (z, x, y) que contiene un punto
create function pg_temp.tx(g geometry, z integer) returns integer language sql as $$ select floor((ST_X(g) + 180) / 360 * (1 << z))::integer $$;
create function pg_temp.ty(g geometry, z integer) returns integer language sql as $$
  select floor((1 - ln(tan(radians(ST_Y(g))) + 1 / cos(radians(ST_Y(g)))) / pi()) / 2 * (1 << z))::integer $$;
create function pg_temp.foto() returns redes.corte_fotos language sql as $$ select * from redes.corte_fotos order by id desc limit 1 $$;
create function pg_temp.archivo(p_ruta text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg')) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
-- ---------- ayudantes del Corte 15 ----------
create temp table _c15 (carga bigint);
create function pg_temp.poli(x1 numeric, y1 numeric, x2 numeric, y2 numeric) returns geometry language sql as $$
  select ST_SetSRID(ST_MakeEnvelope(pg_temp.lon(x1), pg_temp.lat(y1), pg_temp.lon(x2), pg_temp.lat(y2)), 4326) $$;
-- un reporte del bot en (x, y), por la función nueva; devuelve lo que recibiría el bot
create function pg_temp.bot(p_rad text, x numeric, y numeric, p_tipo text default 'sin_agua', p_cuando interval default '0') returns jsonb language sql as $$
  select redes.f_reporte_externo_recibir_evento(jsonb_build_object('radicado', p_rad, 'canal', 'telegram', 'tipo', p_tipo, 'lat', pg_temp.lat(y), 'lon', pg_temp.lon(x),
           'recibido_en', clock_timestamp() + p_cuando)) $$;
create function pg_temp.ebot(p_rad text) returns text language sql as $$ select v.estado_bot from redes.v_reporte_externo v where v.radicado = p_rad $$;
create function pg_temp.idbot(p_rad text) returns text language sql as $$ select r.id::text from redes.reportes_externos r where r.radicado = p_rad $$;
-- un reporte de la línea 116, como lo deja la publicación de una carga (reporte, su «alta» con el punto del contrato, y la fila vigente)
create function pg_temp.l116(p_num bigint, x numeric, y numeric, p_causal text default 'Sin servicio de agua', p_estado text default 'registrado', p_cuando interval default '0') returns bigint
language plpgsql as $$
declare v_id bigint; v_f timestamptz := clock_timestamp() + p_cuando; v_c bigint := (select carga from _c15);
begin
  insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, carga_id) values (p_num, v_f, 'Acueducto', p_causal, v_c) returning id into v_id;
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, carga_id, motivo, autor)
  values (v_id, 'alta', p_estado, 'contrato', pg_temp.pt(x, y), v_c, 'ZT9B carga de prueba', 'prueba.redes9b.adm@emdupar.gov.co');
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, estado, estado_desde, metodo, geom)
  values (v_id, p_num, v_f, (v_f at time zone 'America/Bogota')::date, 'Acueducto', p_causal, p_estado, v_f, 'contrato', pg_temp.pt(x, y));
  return v_id;
end $$;
-- un daño por formulario sobre un tramo de prueba, en (x, y); devuelve su código
create function pg_temp.dano(p_quien text, p_tramo text, x numeric, y numeric, p_tipo text default 'fuga', p_cuando interval default '-5 minutes') returns text language plpgsql as $$
declare v_p jsonb;
begin
  v_p := public.geoportal_redes_preparar_dano(p_quien, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  return public.geoportal_redes_crear_dano(p_quien, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', p_tipo, 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           'activo', pg_temp.cod(p_tramo), 'lat', pg_temp.lat(y), 'lon', pg_temp.lon(x), 't_detectado', pg_temp.iso(p_cuando), 'tipo_rotura', 'parcial', 'riesgo', 'medio',
           'causa_clase', 'desconocida', 'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
end $$;
-- a qué evento ABIERTO está asociado hoy un reporte (o nulo)
create function pg_temp.en(p_origen text, p_ref text) returns text language sql as $$
  select e.codigo from redes.f_eventos_abiertos() e join lateral redes.f_evento_reportes(e.id) r on true where r.origen = p_origen and r.ref = p_ref $$;
create function pg_temp.iddano(p_cod text) returns text language sql as $$ select d.id::text from redes.danos d where d.codigo = p_cod $$;
create function pg_temp.aviso(p jsonb, p_clave text) returns jsonb language sql as $$ select x from jsonb_array_elements(p) x where x ->> 'clave' like p_clave limit 1 $$;

do $prueba$
declare
  a text := 'prueba.redes9b.adm@emdupar.gov.co'; sd text := 'prueba.redes9b.dist@emdupar.gov.co'; sp text := 'prueba.redes9b.planta@emdupar.gov.co';
  op text := 'prueba.redes9b.op@emdupar.gov.co'; na text := 'prueba.redes9b.nada@emdupar.gov.co';
  v_carga bigint; j jsonb; j2 jsonb; v_e1 text; v_e2 text; v_e3 text; v_e4 text; v_d1 text; v_d2 text; v_d3 text; v_d4 text; v_md5 text; v_txt text; v_num integer; v_num2 integer; v_id bigint;
  v_c1 text; v_c2 text; v_c3 text; v_reales integer; v_gran text; v_t0 timestamptz; v_ms numeric; v_ms_bot numeric; v_ms_dano numeric; v_ms_116 numeric; v_ms_decl numeric; v_ms_cerrar numeric;
  v_ms_av numeric; v_ms_vp numeric; v_ms_det numeric; v_info text := ''; v_total integer; v_bien integer; v_fallas text; v_av jsonb; v_caja geometry;
begin
  -- ---------- personas de prueba ----------
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9B Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT9B Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZT9B Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT9B Operador daños', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT9B Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);
  v_md5 := md5(pg_get_functiondef('redes.f_reporte_externo_recibir(jsonb)'::regprocedure)) || md5(pg_get_functiondef('redes.f_publicar_l116(bigint,text,text)'::regprocedure))
           || md5(pg_get_functiondef('public.geoportal_redes_crear_dano(text,uuid,jsonb,text)'::regprocedure));

  -- ---------- tres sectores de prueba y su red: S1 (con el subsector S1A adentro) y S2, lejos de la red real ----------
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
  values ('acueducto', md5('zt15-a') || md5('zt15-b'), 'shp', 4326, 'ID', 1, 'ZT9B red de prueba', a) returning id into v_carga;
  insert into _c15 values (v_carga);
  insert into _zt select 'S1', pg_temp.activo('Sector S1', 'SEC', pg_temp.poli(0, -50, 400, 250), 'sector'), null, 200, 100;
  insert into _zt select 'S1A', pg_temp.activo('Subsector S1A', 'SEC', pg_temp.poli(0, -50, 200, 250), 'subsector'), null, 100, 100;
  insert into _zt select 'S2', pg_temp.activo('Sector S2', 'SEC', pg_temp.poli(500, -50, 900, 250), 'sector'), null, 700, 100;
  perform pg_temp.nodo('A', 50, 0, v_carga); perform pg_temp.nodo('B', 150, 0, v_carga); perform pg_temp.nodo('C', 350, 0, v_carga);
  perform pg_temp.nodo('D', 550, 0, v_carga); perform pg_temp.nodo('E', 750, 0, v_carga);
  perform pg_temp.tramo('T1', 'A', 'B', v_carga, 3);      -- en S1 (y en S1A)
  perform pg_temp.tramo('T2', 'B', 'C', v_carga, 2);      -- en S1
  perform pg_temp.tramo('T3', 'D', 'E', v_carga, 4);      -- en S2
  select min(contrato) into v_c1 from redes.contrato_tramo where activo_id = pg_temp.id('T1');
  select min(contrato) into v_c2 from redes.contrato_tramo where activo_id = pg_temp.id('T2');
  select min(contrato) into v_c3 from redes.contrato_tramo where activo_id = pg_temp.id('T3');
  -- usuarios sensibles: uno CONFIRMADO en S1, uno confirmado en S2 y uno solo propuesto en S1 (no cuenta)
  insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor) values (v_c1, 'hospital', null, 'manual', a), (v_c3, 'colegio', null, 'manual', a), (v_c2, 'clinica', null, 'manual', a);
  insert into redes.usuario_sensible_eventos (contrato, accion, tipo, motivo, autor) values (v_c1, 'confirmar', 'hospital', 'ZT9B sensible de prueba', a), (v_c3, 'confirmar', 'colegio', 'ZT9B sensible de prueba', a);
  select count(*) into v_reales from redes.contrato_tramo;

  -- ===================== 01. Estructura =====================
  perform pg_temp.reg('01.01 las 7 tablas con RLS y sin permisos para la API; las 13 RPC solo para service_role; las internas (y la del bot), para nadie de la API',
     (select count(*) from pg_class c where c.relnamespace = 'redes'::regnamespace and c.relrowsecurity and c.relname in ('eventos_suspension', 'evento_suspension_eventos', 'evento_suspension_reportes',
             'evento_tipos_asociables', 'evento_tipo_eventos', 'planta_sectores', 'planta_sector_eventos') and not has_table_privilege('service_role', c.oid, 'select')) = 7
     and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\_redes\_evento%' or p.proname = 'geoportal_redes_planta_sectores_fijar')
             and p.prosecdef and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')) = 13
     and not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and has_function_privilege('service_role', p.oid, 'execute')));
  perform pg_temp.reg('01.02 el tipo «sin_agua» quedó activo en el catálogo de campo (grupo red_acueducto) y en la lista de lo que se asocia; lo que había en el catálogo no cambió',
     (select t.activo and t.nombre = 'No tengo agua o tengo baja presión' and g.codigo = 'red_acueducto' from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id where t.codigo = 'sin_agua')
     and (select count(*) from campo.tipos_reporte where codigo <> 'sin_agua') = 2
     and (select clase = 'sin_agua' and asocia from redes.evento_tipos_asociables where origen = 'bot' and codigo = 'sin_agua'));
  perform pg_temp.reg('01.03 la lista por omisión: 4 causales de la 116 son «sin agua» (sin servicio, poca presión, deficiencia, no llega) y 5 son daño en la red; del bot, 2; de daños, 3',
     (select count(*) filter (where origen = 'l116' and clase = 'sin_agua') = 4 and count(*) filter (where origen = 'l116' and clase = 'dano_red') = 5
             and count(*) filter (where origen = 'bot') = 2 and count(*) filter (where origen = 'dano') = 3 and bool_and(asocia) from redes.evento_tipos_asociables));
  perform pg_temp.reg('01.04 los 3 disparadores de la asociación están puestos y no se reemplazó recibir del bot, publicar la 116 ni crear daño',
     (select count(*) from pg_trigger t where t.tgname = 't_evento_asociar' and t.tgrelid in ('redes.reporte_externo_eventos'::regclass, 'redes.l116_eventos'::regclass, 'redes.danos'::regclass)) = 3
     and v_md5 = md5(pg_get_functiondef('redes.f_reporte_externo_recibir(jsonb)'::regprocedure)) || md5(pg_get_functiondef('redes.f_publicar_l116(bigint,text,text)'::regprocedure))
                 || md5(pg_get_functiondef('public.geoportal_redes_crear_dano(text,uuid,jsonb,text)'::regprocedure)));

  -- ===================== 02. Sin eventos, todo sigue como antes; el «sin agua» suelto se avisa =====================
  j := pg_temp.bot('ZT15-0001', 100, 10, 'sin_agua', '-10 minutes');      -- en S1
  perform pg_temp.reg('02.01 sin eventos abiertos, un «sin agua» del bot entra como siempre («Recibido») y al bot no se le dice nada de un corte',
     pg_temp.ebot('ZT15-0001') = 'recibido' and j ->> 'evento' is null and j ->> 'mensaje' is null and j ->> 'radicado' = 'ZT15-0001' and j ->> 'id' = pg_temp.idbot('ZT15-0001'), j::text);
  perform pg_temp.l116(990000001, 120, 20, 'Sin servicio de agua', 'registrado', '-8 minutes');      -- en S1
  perform pg_temp.l116(990000002, 600, 20, 'Poca presión  de AGUA', 'registrado', '-8 minutes');      -- en S2 (la causal con otro uso de mayúsculas y espacios)
  perform pg_temp.l116(990000003, 130, 20, 'Fuga en el medidor', 'registrado', '-8 minutes');      -- en S1, pero no es de los que se asocian
  v_d1 := pg_temp.dano(op, 'T1', 100, 0, 'fuga', '-6 minutes');      -- en S1
  perform pg_temp.bot('ZT15-0002', 110, 10, 'tapa_caja_acueducto', '-9 minutes');      -- en S1, tipo que no se asocia
  perform pg_temp.bot('ZT15-0003', 105, 10, 'sin_agua', '-3 hours');      -- en S1, pero de antes del evento
  v_av := tecnica.f_avisos(false, true);
  perform pg_temp.reg('02.02 AVISO: los «sin agua» que no están en ningún evento salen en UN aviso al supervisor de distribución (2 del bot y 2 de la 116), no uno por reporte',
     (pg_temp.aviso(v_av, 'sin_agua_sin_evento') ->> 'n')::integer = 4 and pg_temp.aviso(v_av, 'sin_agua_sin_evento') ->> 'nivel' = 'naranja'
     and pg_temp.aviso(v_av, 'sin_agua_sin_evento') ->> 'titulo' = '4 reportes de falta de agua sin evento' and jsonb_array_length(pg_temp.aviso(v_av, 'sin_agua_sin_evento') -> 'items') = 4
     and pg_temp.aviso(v_av, 'evento_suspension_%') is null, pg_temp.aviso(v_av, 'sin_agua_sin_evento')::text);
  perform pg_temp.reg('02.03 … al supervisor de planta no le sale', pg_temp.aviso(tecnica.f_avisos(true, false), 'sin_agua_sin_evento') is null);

  -- ===================== 03. Quién puede; el catálogo; la vista previa =====================
  j := public.geoportal_redes_evento_catalogo(sd);
  perform pg_temp.reg('03.01 el catálogo para el supervisor de distribución: puede zona y reportes, no total; trae los sectores de prueba, las 2 plantas (sin sectores) y los 14 tipos',
     (j -> 'puede' ->> 'zona')::boolean and (j -> 'puede' ->> 'reportes')::boolean and not (j -> 'puede' ->> 'total')::boolean
     and (select count(*) from jsonb_array_elements(j -> 'sectores') x where x ->> 'codigo' in (pg_temp.cod('S1'), pg_temp.cod('S1A'), pg_temp.cod('S2'))) = 3
     and jsonb_array_length(j -> 'plantas') = (select count(*) from tecnica.plantas where activa) and j -> 'plantas' -> 0 -> 'sectores' = '[]'::jsonb and jsonb_array_length(j -> 'tipos') = 14, left(j::text, 500));
  j := public.geoportal_redes_evento_catalogo(sp);
  perform pg_temp.reg('03.02 … para el supervisor de planta: puede total, no zona ni reportes', (j -> 'puede' ->> 'total')::boolean and not (j -> 'puede' ->> 'zona')::boolean and not (j -> 'puede' ->> 'reportes')::boolean, (j -> 'puede')::text);
  perform pg_temp.err('03.03 el operador no ve el catálogo ni la lista de eventos (42501)', format('select public.geoportal_redes_evento_catalogo(%L)', op), '42501');
  perform pg_temp.err('03.04 … ni declara (42501)', format('select public.geoportal_redes_evento_declarar(%L, %L)', op, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba')), '42501');
  perform pg_temp.err('03.05 alguien sin Técnica no ve ni los eventos vigentes (42501); sin solicitante, 28000', format('select public.geoportal_redes_eventos_vigentes(%L)', na), '42501');
  perform pg_temp.err('03.06 … sin solicitante: 28000', 'select public.geoportal_redes_eventos_vigentes('''')', '28000');
  perform pg_temp.err('03.07 el supervisor de distribución no declara un evento total (42501)', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'total', 'total', 'ciudad', 'causa', 'ZT9B falla de planta')), '42501', 'supervisor de planta');
  perform pg_temp.err('03.08 el supervisor de planta no declara uno por sectores (42501)', format('select public.geoportal_redes_evento_declarar(%L, %L)', sp, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba')), '42501', 'supervisor de distribución');
  j := public.geoportal_redes_evento_vista_previa(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'desde', pg_temp.iso('-30 minutes')));
  perform pg_temp.reg('03.09 VISTA PREVIA de S1 desde hace 30 minutos: 5 contratos, 1 usuario sensible confirmado (el propuesto no cuenta) y 3 reportes que quedarían asociados (1 bot, 1 de la 116, 1 daño); trae la zona; no guarda',
     (j ->> 'contratos')::integer = 5 and (j ->> 'sensibles')::integer = 1 and j -> 'reportes' = jsonb_build_object('total', 3, 'bot', 1, 'l116', 1, 'danos', 1)
     and j -> 'zona_geojson' ->> 'type' = 'MultiPolygon' and j ->> 'ya_abierto' is null and j ->> 'zona' = 'ZT9B Sector S1' and not exists (select 1 from redes.eventos_suspension), j::text);

  -- ===================== 04. Declarar por sectores: asocia lo que ya estaba =====================
  perform pg_temp.err('04.01 sin causa', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')))), '22023', 'causa');
  perform pg_temp.err('04.02 un sector que no existe: P0002', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array('SEC-999999'), 'causa', 'ZT9B daño de prueba')), 'P0002');
  perform pg_temp.err('04.03 un dato que no corresponde', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba', 'autor', 'otro@emdupar.gov.co')), '22023', 'no corresponde');
  perform pg_temp.err('04.04 no puede empezar en el futuro', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba', 'desde', pg_temp.iso('2 hours'))), '22023', 'futuro');
  perform pg_temp.err('04.05 ni hace más de 72 horas', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba', 'desde', pg_temp.iso('-80 hours'))), '22023', '72');
  perform pg_temp.err('04.06 el regreso estimado debe ser después del inicio', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B daño de prueba', 'desde', pg_temp.iso('-30 minutes'), 'regreso', pg_temp.iso('-40 minutes'))), '22023', 'regreso');
  select count(*) into v_num from redes.dano_eventos;
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'Daño en la tubería matriz de la calle 44',
         'desde', pg_temp.iso('-30 minutes'), 'regreso', pg_temp.iso('3 hours')));
  v_e1 := j ->> 'codigo';
  perform pg_temp.reg('04.07 el supervisor de distribución DECLARA el evento por sectores (S1): código EVS-…, abierto, con su zona, 5 contratos, 1 sensible y quién lo declaró (nombre del funcionario)',
     v_e1 ~ '^EVS-[0-9]{6}$' and j ->> 'estado' = 'abierto' and j ->> 'alcance' = 'sectores' and j ->> 'zona' = 'ZT9B Sector S1' and (j ->> 'contratos')::integer = 5 and (j ->> 'sensibles')::integer = 1
     and j ->> 'declarado_por' = 'ZT9B Supervisor de distribución' and j -> 'sectores' = jsonb_build_array(pg_temp.cod('S1')) and j -> 'zona_geojson' ->> 'type' = 'MultiPolygon', j::text);
  perform pg_temp.reg('04.08 … la franja: «Sin agua en <zona> desde las <hora> por <causa>. Regreso estimado: <hora>»',
     j ->> 'franja' ~ '^Sin agua en ZT9B Sector S1 desde las [0-9]{2}/[0-9]{2}, [0-9]{1,2}:[0-9]{2} [ap]\. m\. por Daño en la tubería matriz de la calle 44\. Regreso estimado: [0-9]{2}/[0-9]{2}, [0-9]{1,2}:[0-9]{2} [ap]\. m\.$', j ->> 'franja');
  perform pg_temp.reg('04.09 … y asoció de una vez los 3 reportes que ya estaban en la zona desde el inicio (bot, 116 y daño)',
     (j ->> 'asociados_al_declarar')::integer = 3 and j -> 'reportes' = jsonb_build_object('total', 3, 'bot', 1, 'l116', 1, 'danos', 1)
     and pg_temp.en('bot', pg_temp.idbot('ZT15-0001')) = v_e1 and pg_temp.en('dano', pg_temp.iddano(v_d1)) = v_e1
     and (select count(*) from redes.evento_suspension_reportes where modo = 'al_declarar') = 3, j::text);
  perform pg_temp.reg('04.10 el reporte del bot asociado pasa a «En atención» con el evento en su historial; el daño recibe una nota y SIGUE abierto',
     pg_temp.ebot('ZT15-0001') = 'en_atencion'
     and (select x.motivo like 'Asociado al evento de suspensión ' || v_e1 || '%' from redes.reporte_externo_eventos x join redes.reportes_externos r on r.id = x.reporte_id where r.radicado = 'ZT15-0001' order by x.id desc limit 1)
     and (select count(*) from redes.dano_eventos) = v_num + 1 and (select e.tipo = 'nota' and e.motivo like '%' || v_e1 || '%' from redes.dano_eventos e order by e.id desc limit 1)
     and (select estado from redes.v_dano where codigo = v_d1) <> 'atendido');
  perform pg_temp.reg('04.11 lo que NO se asoció: el de otro sector (S2), el tipo que no está en la lista (tapa; fuga en el medidor) y el que llegó antes del inicio',
     pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000002)) is null and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000003)) is null
     and pg_temp.en('bot', pg_temp.idbot('ZT15-0002')) is null and pg_temp.en('bot', pg_temp.idbot('ZT15-0003')) is null and pg_temp.ebot('ZT15-0002') = 'recibido');
  perform pg_temp.err('04.12 otro evento para la misma zona, mientras ese siga abierto, se niega (55000)',
     format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZT9B otro daño de prueba')), '55000', v_e1);
  perform pg_temp.reg('04.13 queda en la auditoría quién lo declaró (sin datos de suscriptores)',
     (select count(*) = 1 and bool_and(x.detalle ->> 'zona' = 'ZT9B Sector S1') from public.geoportal_auditoria x where x.email = sd and x.accion = 'redes_evento_declarar' and x.referencia = v_e1));

  -- ===================== 05. La asociación automática de lo que llega mientras está abierto =====================
  j := pg_temp.bot('ZT15-0010', 300, 30, 'sin_agua');
  perform pg_temp.reg('05.01 BOT: un «sin agua» nuevo dentro de la zona queda asociado solo, en «En atención», y al bot se le responde «Ya sabemos del corte en tu sector. Regreso estimado: <hora>»',
     pg_temp.en('bot', pg_temp.idbot('ZT15-0010')) = v_e1 and pg_temp.ebot('ZT15-0010') = 'en_atencion' and j ->> 'evento' = v_e1 and j ->> 'radicado' = 'ZT15-0010'
     and j ->> 'mensaje' ~ '^Ya sabemos del corte en tu sector\. Regreso estimado: [0-9]{2}/[0-9]{2}, [0-9]{1,2}:[0-9]{2} [ap]\. m\.$' and (j ->> 'regreso_estimado')::timestamptz > clock_timestamp(), j::text);
  j2 := pg_temp.bot('ZT15-0010', 300, 30, 'sin_agua');
  perform pg_temp.reg('05.02 … si el bot reenvía el mismo radicado, recibe lo mismo y no se duplica nada',
     j2 = j and (select count(*) from redes.evento_suspension_reportes r where r.origen = 'bot' and r.ref = pg_temp.idbot('ZT15-0010')) = 1 and (select count(*) from redes.reportes_externos where radicado = 'ZT15-0010') = 1);
  j := pg_temp.bot('ZT15-0011', 310, 30, 'dano_red_acueducto');
  perform pg_temp.reg('05.03 … un «daño en la red» del bot dentro de la zona también se asocia (en vez de quedar para crear un daño nuevo)', j ->> 'evento' = v_e1 and pg_temp.ebot('ZT15-0011') = 'en_atencion');
  j := pg_temp.bot('ZT15-0012', 320, 30, 'tapa_caja_acueducto');
  j2 := pg_temp.bot('ZT15-0013', 700, 30, 'sin_agua');
  perform pg_temp.reg('05.04 … una tapa dentro de la zona, o un «sin agua» fuera de ella, siguen su flujo normal (sin evento ni mensaje)',
     j ->> 'evento' is null and j ->> 'mensaje' is null and pg_temp.ebot('ZT15-0012') = 'recibido' and j2 ->> 'evento' is null and pg_temp.ebot('ZT15-0013') = 'recibido');
  perform pg_temp.err('05.05 … el bot sigue sin poder mandar datos personales', $q$select redes.f_reporte_externo_recibir_evento('{"radicado": "ZT15-0014", "canal": "telegram", "tipo": "sin_agua", "lat": 10.13, "lon": -73.58, "telefono": "300"}')$q$, null, 'datos personales');
  -- línea 116: una «publicación» de varios reportes en una sola sentencia
  with r as (
    insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, carga_id)
    select x.num, clock_timestamp() + x.cuando, 'Acueducto', x.causal, v_carga
      from (values (990000010::bigint, 'No llega agua a la residencia', interval '0'), (990000011, 'Tubería rota', interval '0'), (990000012, 'Sin servicio de agua', interval '0'),
                   (990000013, 'Sin servicio de agua', interval '0'), (990000014, 'Sin servicio de agua', interval '-5 hours'), (990000015, 'Manjole tapado', interval '0')) x(num, causal, cuando)
    returning id, reporte)
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, carga_id, motivo, autor)
  select r.id, 'alta', case r.reporte when 990000013 then 'atendido' else 'registrado' end, 'contrato',
         case r.reporte when 990000012 then pg_temp.pt(650, 40) else pg_temp.pt(60 + (r.reporte - 990000010) * 10, 40) end, v_carga, 'ZT9B carga de prueba', a from r;
  perform pg_temp.reg('05.06 LÍNEA 116: al publicar una carga, los reportes nuevos de la zona se asocian (2 de 6): no el de fuera de la zona, ni el que ya viene «Atendido», ni el de antes del inicio, ni la causal que no aplica',
     (select count(*) from redes.evento_suspension_reportes r join redes.l116_reportes l on l.id = r.l116_reporte_id where l.reporte between 990000010 and 990000015) = 2
     and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000010)) = v_e1 and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000011)) = v_e1);
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, estado, estado_desde, metodo, geom)
  select l.id, l.reporte, l.fecha_registro, (l.fecha_registro at time zone 'America/Bogota')::date, l.servicio, l.causal, e.estado, l.fecha_registro, 'contrato', e.geom
    from redes.l116_reportes l join redes.l116_eventos e on e.reporte_id = l.id and e.tipo = 'alta' where l.reporte between 990000010 and 990000015;
  -- daños por formulario
  select count(*) into v_num from redes.danos;
  v_d2 := pg_temp.dano(op, 'T2', 250, 0, 'fuga');
  perform pg_temp.reg('05.07 DAÑO: el operador reporta un daño dentro de la zona: el daño SE CREA como siempre (su código, «Reportado») y queda asociado al evento, con la nota en su historial',
     v_d2 ~ '^DAN-[0-9]{6}$' and (select count(*) from redes.danos) = v_num + 1 and (select estado from redes.v_dano where codigo = v_d2) = 'reportado' and pg_temp.en('dano', pg_temp.iddano(v_d2)) = v_e1
     and (select e.tipo = 'nota' and e.motivo like '%' || v_e1 || '%sigue abierto%' and e.autor = 'sistema@evento.suspension' from redes.dano_eventos e where e.dano_id::text = pg_temp.iddano(v_d2)));
  v_d3 := pg_temp.dano(op, 'T3', 600, 0, 'fuga');
  v_d4 := pg_temp.dano(op, 'T2', 260, 0, 'valvula_danada');
  perform pg_temp.reg('05.08 … un daño fuera de la zona, o de un tipo que no está en la lista (válvula dañada), no se asocia ni recibe nota',
     pg_temp.en('dano', pg_temp.iddano(v_d3)) is null and pg_temp.en('dano', pg_temp.iddano(v_d4)) is null
     and not exists (select 1 from redes.dano_eventos e where e.dano_id::text in (pg_temp.iddano(v_d3), pg_temp.iddano(v_d4))));
  j := public.geoportal_redes_evento(sd, v_e1);
  perform pg_temp.reg('05.09 el evento lleva 8 reportes asociados: 3 del bot, 3 de la 116 y 2 daños', j -> 'reportes' = jsonb_build_object('total', 8, 'bot', 3, 'l116', 3, 'danos', 2), (j -> 'reportes')::text);

  -- ===================== 06. Avisos: uno por evento =====================
  v_av := tecnica.f_avisos(false, true);
  perform pg_temp.reg('06.01 AVISOS: UN solo aviso por el evento (naranja), con los 8 reportes asociados en el texto, y no uno por reporte',
     (select count(*) from jsonb_array_elements(v_av) x where x ->> 'clave' like 'evento_suspension_%') = 1
     and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'clave' = 'evento_suspension_' || lower(v_e1) and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'nivel' = 'naranja'
     and (pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'n')::integer = 8 and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'titulo' like 'Sin agua en ZT9B Sector S1 desde las %'
     and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'detalle' like 'Daño en la tubería matriz de la calle 44. 8 reportes asociados. Regreso estimado: %'
     and pg_temp.aviso(v_av, 'evento_suspension_%') -> 'bandeja' ->> 'evento' = v_e1, pg_temp.aviso(v_av, 'evento_suspension_%')::text);
  perform pg_temp.reg('06.02 … el aviso de «sin agua sin evento» ya solo cuenta los que quedaron por fuera (5): los 2 de la 116 y el del bot en S2, y los 2 de antes del inicio (uno del bot y uno de la 116)',
     (pg_temp.aviso(v_av, 'sin_agua_sin_evento') ->> 'n')::integer = 5, pg_temp.aviso(v_av, 'sin_agua_sin_evento')::text);
  perform pg_temp.reg('06.03 … el aviso de reportes del bot «Recibidos» no cuenta los asociados (están «En atención»)',
     not exists (select 1 from redes.v_reporte_externo v where v.radicado in ('ZT15-0001', 'ZT15-0010', 'ZT15-0011') and v.ultimo_evento = 'recibido'));
  perform pg_temp.reg('06.04 … al supervisor de planta no le sale un evento por sectores', pg_temp.aviso(tecnica.f_avisos(true, false), 'evento_suspension_%') is null);
  v_av := tecnica.f_avisos(false, true, clock_timestamp() + interval '4 hours');
  perform pg_temp.reg('06.05 … cuando pasa la hora estimada de regreso y sigue abierto, el aviso sale en ROJO y lo dice',
     pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'nivel' = 'rojo' and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'detalle' like '%Ya pasó: ajuste la hora o cierre el evento.', pg_temp.aviso(v_av, 'evento_suspension_%')::text);

  -- ===================== 07. Ajustar el regreso; desasociar y asociar a mano; el detalle =====================
  perform pg_temp.err('07.01 el operador no ajusta la hora de regreso (42501)', format('select public.geoportal_redes_evento_regreso(%L, %L, %L)', op, v_e1, pg_temp.iso('5 hours')), '42501');
  perform pg_temp.err('07.02 el supervisor de planta tampoco, en un evento por sectores (42501)', format('select public.geoportal_redes_evento_regreso(%L, %L, %L)', sp, v_e1, pg_temp.iso('5 hours')), '42501');
  j := public.geoportal_redes_evento_regreso(sd, v_e1, pg_temp.iso('6 hours'), 'ZT9B llegó el repuesto más tarde');
  perform pg_temp.reg('07.03 el supervisor de distribución ajusta el regreso estimado: vale la hora nueva (lo declarado no cambia) y el bot responde con ella',
     (j ->> 'regreso_estimado')::timestamptz > clock_timestamp() + interval '5 hours' and (select regreso_estimado < clock_timestamp() + interval '4 hours' from redes.eventos_suspension where codigo = v_e1)
     and (pg_temp.bot('ZT15-0020', 330, 30, 'sin_agua') ->> 'regreso_estimado')::timestamptz > clock_timestamp() + interval '5 hours');
  perform pg_temp.err('07.04 desasociar sin motivo', format('select public.geoportal_redes_evento_desasociar(%L, %L, %L, %L, %L)', sd, v_e1, 'bot', pg_temp.idbot('ZT15-0011'), 'corto'), '22023', 'motivo');
  perform pg_temp.err('07.05 el operador no desasocia (42501)', format('select public.geoportal_redes_evento_desasociar(%L, %L, %L, %L, %L)', op, v_e1, 'bot', pg_temp.idbot('ZT15-0011'), 'ZT9B es otro problema'), '42501');
  j := public.geoportal_redes_evento_desasociar(sd, v_e1, 'bot', pg_temp.idbot('ZT15-0011'), 'ZT9B es otra fuga, a tres cuadras');
  perform pg_temp.reg('07.06 el supervisor DESASOCIA un reporte del bot con motivo: sale del evento (quedan 8 con el que acaba de entrar) y vuelve a «Recibido», con el motivo en su historial',
     (j -> 'reportes' ->> 'total')::integer = 8 and pg_temp.en('bot', pg_temp.idbot('ZT15-0011')) is null and pg_temp.ebot('ZT15-0011') = 'recibido'
     and (select x.motivo like 'Desasociado del evento de suspensión ' || v_e1 || ': ZT9B es otra fuga%' from redes.reporte_externo_eventos x where x.reporte_id::text = pg_temp.idbot('ZT15-0011') order by x.id desc limit 1), j::text);
  perform pg_temp.err('07.07 desasociar uno que no está en el evento', format('select public.geoportal_redes_evento_desasociar(%L, %L, %L, %L, %L)', sd, v_e1, 'bot', pg_temp.idbot('ZT15-0011'), 'ZT9B es otro problema'), '22023', 'no está asociado');
  j := public.geoportal_redes_evento_desasociar(sd, v_e1, 'dano', v_d2, 'ZT9B ese daño es de otra tubería');
  perform pg_temp.reg('07.08 … desasocia un daño (por su código): sale del evento y queda la nota en su historial',
     pg_temp.en('dano', pg_temp.iddano(v_d2)) is null and (select count(*) from redes.dano_eventos e where e.dano_id::text = pg_temp.iddano(v_d2) and e.tipo = 'nota') = 2);
  j := public.geoportal_redes_evento_asociar(sd, v_e1, 'l116', '990000003', 'ZT9B sí es del mismo corte');
  perform pg_temp.reg('07.09 ASOCIA a mano uno de la 116 que no había entrado solo (por su número), con motivo',
     pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000003)) = v_e1
     and (select r.modo = 'manual' and r.motivo is not null from redes.evento_suspension_reportes r order by r.id desc limit 1));
  perform pg_temp.err('07.10 asociar uno que ya está en el evento', format('select public.geoportal_redes_evento_asociar(%L, %L, %L, %L, %L)', sd, v_e1, 'l116', '990000003', 'ZT9B sí es del mismo corte'), '22023', 'ya está asociado');
  perform pg_temp.err('07.11 un reporte que no existe: P0002', format('select public.geoportal_redes_evento_asociar(%L, %L, %L, %L, %L)', sd, v_e1, 'dano', 'DAN-999999', 'ZT9B sí es del mismo corte'), 'P0002');
  j := public.geoportal_redes_evento(sd, v_e1);
  perform pg_temp.reg('07.12 EL DETALLE: 8 asociados con origen, rótulo, tipo, cuándo y punto; el usuario sensible confirmado (contrato y tipo); y el historial (regreso, desasociaciones y la asociación a mano)',
     jsonb_array_length(j -> 'asociados') = 8 and (select bool_and(x ? 'rotulo' and x ->> 'cuando' is not null and x ->> 'lat' is not null and x ->> 'tipo' is not null) from jsonb_array_elements(j -> 'asociados') x)
     and j -> 'sensibles_lista' = jsonb_build_array(jsonb_build_object('contrato', v_c1, 'tipo', 'Hospital'))
     and (select count(*) filter (where x ->> 'que' = 'regreso') = 1 and count(*) filter (where x ->> 'que' = 'desasociar') = 2 and count(*) filter (where x ->> 'que' = 'asociar_a_mano') = 1 from jsonb_array_elements(j -> 'historial') x),
     left(j::text, 900));
  perform pg_temp.reg('07.13 … sin nombres, teléfonos, direcciones, textos del ciudadano ni correos',
     j::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n|descripcion|@emdupar' and public.geoportal_redes_eventos_vigentes(op)::text !~* 'suscriptor|tel[eé]fono|direcci[oó]n|@emdupar|contrato"');
  j := public.geoportal_redes_eventos_vigentes(op);
  perform pg_temp.reg('07.14 el OPERADOR sí ve los eventos vigentes (la zona en el mapa y la franja), sin la lista de reportes ni los sensibles',
     jsonb_array_length(j -> 'eventos') = 1 and j -> 'eventos' -> 0 ->> 'codigo' = v_e1 and j -> 'eventos' -> 0 -> 'zona_geojson' ->> 'type' = 'MultiPolygon'
     and j -> 'eventos' -> 0 ->> 'franja' like 'Sin agua en %' and not (j -> 'eventos' -> 0 ? 'asociados') and not (j -> 'eventos' -> 0 ? 'sensibles_lista'));
  perform pg_temp.err('07.15 … pero no el detalle ni la lista (42501)', format('select public.geoportal_redes_evento(%L, %L)', op, v_e1), '42501');

  -- ===================== 08. Por círculo; dos eventos que se cruzan =====================
  perform pg_temp.err('08.01 un radio fuera de rango', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'circulo', 'lat', pg_temp.lat(100), 'lon', pg_temp.lon(380), 'radio_m', 5, 'causa', 'ZT9B fuga localizada')), '22023', 'radio');
  perform pg_temp.err('08.02 sin centro', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd, jsonb_build_object('alcance', 'circulo', 'radio_m', 100, 'causa', 'ZT9B fuga localizada')), '22023', 'centro');
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'circulo', 'lat', pg_temp.lat(100), 'lon', pg_temp.lon(560), 'radio_m', 120, 'causa', 'Fuga en la carrera 9', 'desde', pg_temp.iso('-30 minutes')));
  v_e2 := j ->> 'codigo';
  perform pg_temp.reg('08.03 declara un evento POR CÍRCULO (centro y radio de 120 m) en S2: guarda el centro, el radio y la zona; cuenta los 4 contratos del tramo que toca y su sensible; sin hora de regreso',
     j ->> 'alcance' = 'circulo' and (j -> 'circulo' ->> 'radio_m')::numeric = 120 and j ->> 'zona' = 'un círculo de 120 m en ZT9B Sector S2' and (j ->> 'contratos')::integer = 4 and (j ->> 'sensibles')::integer = 1
     and j ->> 'regreso_estimado' is null and j ->> 'franja' like '%Regreso estimado: sin definir.'
     and (select abs(ST_Area(geom::geography) - pi() * 120 * 120) / (pi() * 120 * 120) < 0.02 from redes.eventos_suspension where codigo = v_e2), j::text);
  perform pg_temp.reg('08.04 … asoció al declarar lo que ya estaba dentro del círculo desde el inicio: los 2 «sin agua» de la 116 (a 89 y a 108 m del centro) y el daño (a 108 m); no el del bot que está a 156 m',
     (j ->> 'asociados_al_declarar')::integer = 3 and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000012)) = v_e2 and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000002)) = v_e2 and pg_temp.en('dano', pg_temp.iddano(v_d3)) = v_e2
     and pg_temp.en('bot', pg_temp.idbot('ZT15-0013')) is null, j::text);
  j := pg_temp.bot('ZT15-0030', 620, 80, 'sin_agua');
  j2 := pg_temp.bot('ZT15-0031', 800, 80, 'sin_agua');
  perform pg_temp.reg('08.05 la pertenencia se decide por el punto: un reporte a 63 m del centro entra al círculo; uno a 240 m, no. Sin hora de regreso, al bot se le dice que todavía no hay',
     j ->> 'evento' = v_e2 and j ->> 'mensaje' = 'Ya sabemos del corte en tu sector. Todavía no hay hora estimada de regreso.' and j2 ->> 'evento' is null, j::text);
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'circulo', 'lat', pg_temp.lat(100), 'lon', pg_temp.lon(380), 'radio_m', 60, 'causa', 'ZT9B válvula cerrada en la esquina'));
  v_e3 := j ->> 'codigo';
  j2 := pg_temp.bot('ZT15-0032', 370, 100, 'sin_agua');
  perform pg_temp.reg('08.06 si un punto cae en dos eventos abiertos (el sector S1 y un círculo adentro), queda en UNO solo: el declarado más recientemente',
     j2 ->> 'evento' = v_e3 and (select count(*) from redes.evento_suspension_reportes r where r.origen = 'bot' and r.ref = pg_temp.idbot('ZT15-0032')) = 1);
  v_av := tecnica.f_avisos(false, true);
  perform pg_temp.reg('08.07 con 3 eventos abiertos hay 3 avisos, uno por evento', (select count(*) from jsonb_array_elements(v_av) x where x ->> 'clave' like 'evento_suspension_%') = 3);

  -- ===================== 09. Anular: los reportes vuelven a su flujo =====================
  perform pg_temp.err('09.01 anular sin motivo', format('select public.geoportal_redes_evento_anular(%L, %L, %L)', sd, v_e3, ''), '22023', 'motivo');
  j := public.geoportal_redes_evento_anular(sd, v_e3, 'ZT9B se declaró por error, era el mismo corte');
  perform pg_temp.reg('09.02 el supervisor ANULA un evento con motivo: queda «anulado» (nada se borra), su reporte del bot vuelve a «Recibido» y ya no tiene aviso',
     j ->> 'estado' = 'anulado' and (j ->> 'reportes_liberados')::integer = 1 and j -> 'fin' ->> 'motivo' like 'ZT9B se declaró por error%' and pg_temp.ebot('ZT15-0032') = 'recibido'
     and pg_temp.en('bot', pg_temp.idbot('ZT15-0032')) is null and exists (select 1 from redes.eventos_suspension where codigo = v_e3)
     and (select count(*) from jsonb_array_elements(tecnica.f_avisos(false, true)) x where x ->> 'clave' like 'evento_suspension_%') = 2, j::text);
  perform pg_temp.err('09.03 un evento anulado no se cierra ni se vuelve a anular (55000)', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L)', sd, v_e3, 'ZT9B ya volvió el servicio'), '55000', 'anulado');
  j := public.geoportal_redes_evento_asociar(sd, v_e1, 'bot', pg_temp.idbot('ZT15-0032'), 'ZT9B era del corte del sector');
  perform pg_temp.reg('09.04 … y ese reporte, ya libre, se puede asociar a mano al evento del sector', pg_temp.en('bot', pg_temp.idbot('ZT15-0032')) = v_e1 and pg_temp.ebot('ZT15-0032') = 'en_atencion');

  -- ===================== 10. Cierre en bloque («dar de alta») =====================
  perform pg_temp.err('10.01 cerrar sin motivo', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L)', sd, v_e1, 'ya'), '22023', 'motivo');
  perform pg_temp.err('10.02 no se cierra antes de la hora en que empezó', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L, %L)', sd, v_e1, 'ZT9B ya volvió el servicio', pg_temp.iso('-2 hours')), '22023', 'antes');
  perform pg_temp.err('10.03 el operador no cierra (42501)', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L)', op, v_e1, 'ZT9B ya volvió el servicio'), '42501');
  select count(*) into v_num from redes.danos; select count(*) into v_num2 from redes.reportes_externos;
  j := public.geoportal_redes_evento_cerrar(sd, v_e1, 'Tubería reparada y servicio restablecido');
  perform pg_temp.reg('10.04 el supervisor CIERRA el evento: queda «cerrado» con motivo, hora y quién; cierra en bloque 4 reportes del bot y 4 de la 116; el daño asociado sigue abierto',
     j ->> 'estado' = 'cerrado' and j -> 'fin' ->> 'motivo' = 'Tubería reparada y servicio restablecido' and j -> 'fin' ->> 'por' = 'ZT9B Supervisor de distribución'
     and j -> 'cerrados' = jsonb_build_object('bot', 4, 'l116', 4) and (j ->> 'danos_siguen_abiertos')::integer = 1, j::text);
  perform pg_temp.reg('10.05 … cada reporte del bot quedó «Atendido» con el MISMO motivo y la MISMA hora en su historial',
     (select count(*) = 4 and count(distinct x.motivo) = 1 and bool_and(x.motivo like 'Evento de suspensión ' || v_e1 || ' cerrado (%): Tubería reparada y servicio restablecido' and x.autor = sd)
        from redes.reporte_externo_eventos x where x.tipo = 'atendido')
     and pg_temp.ebot('ZT15-0001') = 'atendido' and pg_temp.ebot('ZT15-0010') = 'atendido' and pg_temp.ebot('ZT15-0020') = 'atendido' and pg_temp.ebot('ZT15-0032') = 'atendido');
  perform pg_temp.reg('10.06 … cada reporte de la 116 quedó «Atendido», con su hecho en el historial (de «Registrado» a «Atendido», mismo motivo)',
     (select count(*) = 4 and count(distinct e.motivo) = 1 and bool_and(e.estado = 'atendido' and e.estado_antes = 'registrado' and e.motivo like '%' || v_e1 || '%Tubería reparada%') from redes.l116_eventos e where e.tipo = 'estado')
     and (select count(*) = 4 and bool_and(v.estado = 'atendido') from redes.l116_vigente v where v.reporte in (990000001, 990000003, 990000010, 990000011)));
  perform pg_temp.reg('10.07 … el daño NO se cerró: sigue «Reportado», con la nota del cierre del evento en su historial',
     (select estado from redes.v_dano where codigo = v_d1) = 'reportado'
     and (select e.motivo like 'Evento de suspensión ' || v_e1 || ' cerrado%' from redes.dano_eventos e where e.dano_id::text = pg_temp.iddano(v_d1) order by e.id desc limit 1));
  perform pg_temp.reg('10.08 … los desasociados no se tocaron (el del bot sigue «Recibido»; el daño, sin nota de cierre) y no se borró ni se creó ningún reporte ni daño',
     pg_temp.ebot('ZT15-0011') = 'recibido' and (select count(*) from redes.dano_eventos e where e.dano_id::text = pg_temp.iddano(v_d2)) = 2
     and (select count(*) from redes.danos) = v_num and (select count(*) from redes.reportes_externos) = v_num2);
  perform pg_temp.err('10.09 un evento cerrado no se vuelve a cerrar (55000)', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L)', sd, v_e1, 'ZT9B ya volvió el servicio'), '55000', 'cerrado');
  j := pg_temp.bot('ZT15-0040', 300, 30, 'sin_agua');
  perform pg_temp.reg('10.10 después del cierre, un reporte nuevo en esa zona ya no se asocia: entra como siempre y se avisa como «sin agua sin evento»',
     j ->> 'evento' is null and pg_temp.ebot('ZT15-0040') = 'recibido');
  j := public.geoportal_redes_eventos(sd, 'todos');
  perform pg_temp.reg('10.11 la lista del supervisor: 3 eventos (1 abierto, 1 cerrado, 1 anulado), los últimos primero; por estado, solo los de ese estado',
     jsonb_array_length(j -> 'eventos') = 3 and j -> 'eventos' -> 0 ->> 'codigo' = v_e3 and jsonb_array_length(public.geoportal_redes_eventos(sd, 'abierto') -> 'eventos') = 1
     and public.geoportal_redes_eventos(sd, 'cerrado') -> 'eventos' -> 0 ->> 'codigo' = v_e1);
  perform pg_temp.reg('10.12 el evento cerrado conserva sus 9 reportes y su historial en el detalle', (public.geoportal_redes_evento(sd, v_e1) -> 'reportes' ->> 'total')::integer = 9
     and jsonb_array_length(public.geoportal_redes_evento(sd, v_e1) -> 'historial') = 6);      -- 1 regreso, 2 desasociaciones, 2 asociaciones a mano y el cierre

  -- ===================== 11. Total: por planta y toda la ciudad =====================
  perform pg_temp.err('11.01 una planta sin sectores asignados no se puede declarar: lo dice', format('select public.geoportal_redes_evento_declarar(%L, %L)', sp, jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'huaricha', 'causa', 'ZT9B falla de energía')), '22023', 'no tiene sectores asignados');
  perform pg_temp.err('11.02 el supervisor de planta no asigna los sectores de una planta (42501)', format('select public.geoportal_redes_planta_sectores_fijar(%L, %L, %L, %L)', sp, 'huaricha', array[pg_temp.cod('S2')], 'ZT9B sectores de prueba'), '42501');
  j := public.geoportal_redes_planta_sectores_fijar(sd, 'huaricha', array[pg_temp.cod('S1'), pg_temp.cod('S2')], 'ZT9B sectores de prueba de la planta');
  j := public.geoportal_redes_planta_sectores_fijar(sd, 'huaricha', array[pg_temp.cod('S2')], 'ZT9B se corrige: solo el sector dos');
  perform pg_temp.reg('11.03 el supervisor de distribución asigna, y luego corrige, los sectores que surte una planta (con motivo; queda el historial): al final, solo S2',
     j -> 'sectores' = jsonb_build_array(pg_temp.cod('S2')) and (select count(*) from redes.planta_sector_eventos) = 2
     and (select count(*) filter (where activo) = 1 and count(*) = 2 from redes.planta_sectores)
     and (select x -> 'sectores' from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sp) -> 'plantas') x where x ->> 'codigo' = 'huaricha') = jsonb_build_array(pg_temp.cod('S2')));
  j := public.geoportal_redes_evento_declarar(sp, jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'huaricha', 'causa', 'Falla de energía en la planta', 'regreso', pg_temp.iso('2 hours')));
  v_e4 := j ->> 'codigo';
  perform pg_temp.reg('11.04 el supervisor de planta declara un TOTAL POR PLANTA: la zona es lo que surte la planta (S2), con sus 4 contratos y su sensible',
     j ->> 'alcance' = 'total' and j ->> 'total' = 'planta' and j ->> 'planta' = 'Huaricha' and j ->> 'zona' = 'lo que surte la planta Huaricha' and (j ->> 'contratos')::integer = 4 and (j ->> 'sensibles')::integer = 1
     and j -> 'sectores' = jsonb_build_array(pg_temp.cod('S2')), j::text);
  v_av := tecnica.f_avisos(true, false);
  perform pg_temp.reg('11.05 … su aviso le sale también al supervisor de planta (los totales), y no el del círculo',
     (select count(*) from jsonb_array_elements(v_av) x where x ->> 'clave' like 'evento_suspension_%') = 1 and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'clave' = 'evento_suspension_' || lower(v_e4)
     and pg_temp.aviso(v_av, 'evento_suspension_%') ->> 'area' = 'planta');
  perform pg_temp.err('11.06 el supervisor de distribución no cierra un evento total (42501)', format('select public.geoportal_redes_evento_cerrar(%L, %L, %L)', sd, v_e4, 'ZT9B ya volvió el servicio'), '42501');
  j := public.geoportal_redes_evento_desasociar(sd, v_e2, 'bot', pg_temp.idbot('ZT15-0030'), 'ZT9B se pasa al evento de la planta');
  j := public.geoportal_redes_evento_asociar(sd, v_e4, 'bot', pg_temp.idbot('ZT15-0030'), 'ZT9B se pasa al evento de la planta');
  perform pg_temp.reg('11.07 … pero sí maneja sus reportes: pasa uno del círculo al evento de la planta (desasociar y asociar, con motivo)', pg_temp.en('bot', pg_temp.idbot('ZT15-0030')) = v_e4);
  j := public.geoportal_redes_evento_cerrar(sp, v_e4, 'Volvió la energía y la planta bombea');
  perform pg_temp.reg('11.08 el supervisor de planta cierra su evento total', j ->> 'estado' = 'cerrado' and pg_temp.ebot('ZT15-0030') = 'atendido');
  j := public.geoportal_redes_evento_declarar(a, jsonb_build_object('alcance', 'total', 'total', 'ciudad', 'causa', 'Falla en la captación', 'desde', pg_temp.iso('-1 minutes')));
  v_e4 := j ->> 'codigo';
  perform pg_temp.reg('11.09 el administrador declara un TOTAL DE TODA LA CIUDAD: sin geometría, cuenta todos los contratos con tramo y todos los sensibles confirmados',
     j ->> 'total' = 'ciudad' and j ->> 'zona' = 'toda la ciudad' and (j ->> 'contratos')::integer = v_reales and (j ->> 'sensibles')::integer = (select count(*) from redes.v_usuario_sensible where estado = 'confirmado')
     and j -> 'zona_geojson' = 'null'::jsonb, j::text);
  j2 := pg_temp.bot('ZT15-0050', 5000, 5000, 'sin_agua');
  perform pg_temp.reg('11.10 … cualquier reporte nuevo, esté donde esté, queda en el evento de la ciudad', j2 ->> 'evento' = v_e4);
  perform pg_temp.err('11.11 un segundo evento de toda la ciudad se niega (55000)', format('select public.geoportal_redes_evento_declarar(%L, %L)', a, jsonb_build_object('alcance', 'total', 'total', 'ciudad', 'causa', 'ZT9B otra falla')), '55000');
  perform public.geoportal_redes_evento_anular(a, v_e4, 'ZT9B fin de la prueba del evento total');
  perform public.geoportal_redes_evento_cerrar(sd, v_e2, 'ZT9B fuga reparada en la carrera 9');

  -- ===================== 12. La lista ajustable de lo que se asocia =====================
  perform pg_temp.err('12.01 el operador no cambia la lista (42501)', format('select public.geoportal_redes_evento_tipo_fijar(%L, %L, %L, false, %L)', op, 'bot', 'dano_red_acueducto', 'ZT9B ya no se asocia'), '42501');
  perform pg_temp.err('12.02 sin motivo', format('select public.geoportal_redes_evento_tipo_fijar(%L, %L, %L, false, %L)', sd, 'bot', 'dano_red_acueducto', 'no'), '22023', 'motivo');
  perform pg_temp.err('12.03 un tipo nuevo necesita nombre y clase', format('select public.geoportal_redes_evento_tipo_fijar(%L, %L, %L, true, %L)', sd, 'l116', 'Agua turbia', 'ZT9B se agrega la causal'), '22023', 'nombre');
  j := public.geoportal_redes_evento_tipo_fijar(sd, 'bot', 'dano_red_acueducto', false, 'ZT9B el daño en la red sigue su flujo normal');
  j2 := public.geoportal_redes_evento_tipo_fijar(sd, 'l116', '  Fuga en  el MEDIDOR ', true, 'ZT9B se agrega la causal de prueba', 'Fuga en el medidor', 'otro');
  v_e1 := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1A')), 'causa', 'ZT9B corte programado del subsector')) ->> 'codigo';
  perform pg_temp.l116(990000020, 90, 60, 'fuga en el medidor');
  perform pg_temp.reg('12.04 el supervisor ajusta la lista con motivo (queda el historial): un «daño en la red» del bot ya no se asocia, y una causal nueva de la 116 sí (sin importar mayúsculas ni espacios)',
     not (j ->> 'asocia')::boolean and j2 ->> 'codigo' = 'fuga en el medidor' and (select count(*) from redes.evento_tipo_eventos) = 2
     and pg_temp.bot('ZT15-0060', 90, 50, 'dano_red_acueducto') ->> 'evento' is null and pg_temp.en('l116', (select id::text from redes.l116_reportes where reporte = 990000020)) = v_e1);
  perform pg_temp.reg('12.05 un evento por SUBSECTOR: la zona es la del subsector (un reporte en el resto del sector no entra)',
     pg_temp.bot('ZT15-0061', 90, 50, 'sin_agua') ->> 'evento' = v_e1 and pg_temp.bot('ZT15-0062', 300, 50, 'sin_agua') ->> 'evento' is null);
  perform public.geoportal_redes_evento_cerrar(sd, v_e1, 'ZT9B terminó el corte programado');

  -- ===================== 13. Solo agregar =====================
  perform pg_temp.err('13.01 solo agregar: un evento no se cambia', 'update redes.eventos_suspension set causa = ''otra causa'' where id = (select min(id) from redes.eventos_suspension)');
  perform pg_temp.err('13.02 solo agregar: un evento no se borra', 'delete from redes.eventos_suspension where id = (select min(id) from redes.eventos_suspension)');
  perform pg_temp.err('13.03 solo agregar: una asociación no se cambia ni se borra', 'delete from redes.evento_suspension_reportes where id = (select min(id) from redes.evento_suspension_reportes)');
  perform pg_temp.err('13.04 solo agregar: el cierre de un evento no se cambia', 'update redes.evento_suspension_eventos set motivo = ''otro motivo distinto'' where id = (select min(id) from redes.evento_suspension_eventos)');
  perform pg_temp.err('13.05 un evento termina una sola vez (la base lo impide aunque se salte la RPC)',
     format('insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) select id, ''anular'', ''ZT9B segundo final'', clock_timestamp(), %L from redes.eventos_suspension where codigo = %L', a, v_e1), '23505');
  perform pg_temp.reg('13.06 al final no queda ningún evento abierto y nadie recibió nada que no fuera suyo: 6 eventos en la base (4 cerrados y 2 anulados)',
     not exists (select 1 from redes.f_eventos_abiertos()) and (select count(*) filter (where estado = 'cerrado') = 4 and count(*) filter (where estado = 'anulado') = 2 and count(*) = 6 from redes.v_evento_suspension));

  -- ===================== 14. TIEMPOS con volumen: la zona cubre la red real de esta base, 300 eventos viejos y una carga de 5.000 reportes de la 116 =====================
  select ST_SetSRID(ST_Extent(m.geom)::geometry, 4326) into v_caja from redes.activo_vigente_mat m where m.prefijo = 'RED' and m.sistema = 'acueducto' and m.codigo not in (pg_temp.cod('T1'), pg_temp.cod('T2'), pg_temp.cod('T3'))
     and ST_Y(ST_StartPoint(m.geom)) > 10.3;
  if v_caja is null then v_caja := pg_temp.poli(-3000, -3000, -1000, -1000); end if;
  insert into _zt select 'GRAN', pg_temp.activo('Sector de toda la red', 'SEC', v_caja, 'sector'), null, 0, 0;
  -- 300 eventos viejos, ya cerrados (la búsqueda de «eventos abiertos» no debe depender de cuántos ha habido)
  with viejos as (
    insert into redes.eventos_suspension (codigo, alcance, geom, sectores, zona_nombre, causa, desde, contratos, sensibles, autor)
    select 'EVS-9' || lpad(i::text, 5, '0'), 'sectores', ST_Multi(pg_temp.poli(0, -50, 400, 250)), array[pg_temp.id('S1')], 'ZT9B Sector S1', 'ZT9B evento viejo de relleno',
           clock_timestamp() - interval '90 days' + make_interval(hours => i), 5, 1, a from generate_series(1, 300) i
    returning id, desde)
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) select id, 'cerrar', 'ZT9B cierre de relleno', desde + interval '2 hours', a from viejos;
  v_t0 := clock_timestamp();
  j := public.geoportal_redes_evento_vista_previa(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('GRAN')), 'desde', pg_temp.iso('-30 minutes')));
  v_ms_vp := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('GRAN')), 'causa', 'ZT9B evento grande para medir tiempos', 'desde', pg_temp.iso('-30 minutes')));
  v_ms_decl := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_gran := j ->> 'codigo';
  v_t0 := clock_timestamp();
  j2 := redes.f_reporte_externo_recibir_evento(jsonb_build_object('radicado', 'ZT15-9001', 'canal', 'telegram', 'tipo', 'sin_agua', 'lat', round(ST_Y(ST_Centroid(v_caja))::numeric, 6), 'lon', round(ST_X(ST_Centroid(v_caja))::numeric, 6)));
  v_ms_bot := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  -- una carga de 5.000 reportes nuevos de la 116 en una sentencia, todos dentro de la zona
  v_t0 := clock_timestamp();
  with r as (
    insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, carga_id)
    select 980000000 + i, clock_timestamp(), 'Acueducto', case when i % 2 = 0 then 'Sin servicio de agua' else 'Manjole tapado' end, v_carga from generate_series(1, 5000) i
    returning id, reporte)
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, carga_id, motivo, autor)
  select r.id, 'alta', 'registrado', 'contrato',
         ST_SetSRID(ST_MakePoint(ST_XMin(v_caja) + (ST_XMax(v_caja) - ST_XMin(v_caja)) * ((r.reporte % 97) / 97.0), ST_YMin(v_caja) + (ST_YMax(v_caja) - ST_YMin(v_caja)) * ((r.reporte % 89) / 89.0)), 4326),
         v_carga, 'ZT9B carga de relleno', a from r;
  v_ms_116 := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, estado, estado_desde, metodo, geom)
  select l.id, l.reporte, l.fecha_registro, (l.fecha_registro at time zone 'America/Bogota')::date, l.servicio, l.causal, 'registrado', l.fecha_registro, 'contrato', e.geom
    from redes.l116_reportes l join redes.l116_eventos e on e.reporte_id = l.id and e.tipo = 'alta' where l.reporte > 980000000 and l.reporte <= 980005000;
  v_t0 := clock_timestamp(); v_av := tecnica.f_avisos(false, true); v_ms_av := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp(); j2 := public.geoportal_redes_evento(sd, v_gran); v_ms_det := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  j := public.geoportal_redes_evento_cerrar(sd, v_gran, 'ZT9B fin de la medición de tiempos');
  v_ms_cerrar := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_info := format('TIEMPOS (zona con %s contratos; %s eventos en la base): asociar un reporte del bot %s ms · una carga de 5.000 reportes de la 116 (2.500 asociados) %s ms, %s ms por reporte · '
                   || 'vista previa %s ms · declarar %s ms · avisos %s ms · detalle (200 de %s asociados) %s ms · cerrar en bloque %s reportes %s ms',
                   j2 ->> 'contratos', (select count(*) from redes.eventos_suspension), v_ms_bot, v_ms_116, round(v_ms_116 / 5000, 3), v_ms_vp, v_ms_decl, v_ms_av, j2 -> 'reportes' ->> 'total', v_ms_det,
                   (j -> 'cerrados' ->> 'bot')::integer + (j -> 'cerrados' ->> 'l116')::integer, v_ms_cerrar);
  perform pg_temp.reg('14.01 con volumen, la carga de la 116 asoció los 2.500 «sin agua» (y ningún «manjole»), el detalle lista 200 y el cierre los dejó «Atendido»',
     (j2 -> 'reportes' ->> 'l116')::integer = 2500 and jsonb_array_length(j2 -> 'asociados') = 200 and (j -> 'cerrados' ->> 'l116')::integer = 2500
     and (select count(*) from redes.l116_vigente v where v.reporte > 980000000 and v.reporte <= 980005000 and v.estado = 'atendido') = 2500, (j -> 'cerrados')::text);
  perform pg_temp.reg('14.02 TIEMPOS: asociar un reporte nuevo (bot) en menos de 1 s', v_ms_bot < 1000, v_info);
  perform pg_temp.reg('14.03 TIEMPOS: la carga de 5.000 reportes de la 116, la vista previa, declarar, los avisos, el detalle y el cierre en bloque, cada uno en menos de 1 s (local; producción es unas 6 veces más lenta)',
     greatest(v_ms_116, v_ms_vp, v_ms_decl, v_ms_av, v_ms_det, v_ms_cerrar) < 1000, v_info);
  v_t0 := clock_timestamp(); v_d1 := pg_temp.dano(op, 'T1', 100, 0, 'fuga'); v_ms_dano := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_info := v_info || format(' · crear un daño sin eventos abiertos %s ms', v_ms_dano);
  perform pg_temp.reg('14.04 sin eventos abiertos, crear un daño no se demora por los disparadores (menos de 1 s) y no escribe nada del corte',
     v_ms_dano < 1000 and not exists (select 1 from redes.dano_eventos e where e.dano_id::text = pg_temp.iddano(v_d1)), v_info);
  perform pg_temp.reg('14.05 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion, ', ') from redes.f_funciones_sin_where()));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 15, evento de suspensión (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
