begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 10 — GUARDIA, TABLAS, CATÁLOGOS Y PARÁMETROS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte15_eventos_suspension.md y las respuestas de David del 18 y del 19-nov.
-- · Presupone la corrección del 9b publicada: huella del conjunto de funciones de redes 63d917635b33e3696f28a3b0e579c002, y tecnica.f_avisos como la dejó el Corte 14.
-- · Tablas nuevas (solo agregar): eventos_suspension, evento_suspension_eventos, evento_suspension_reportes; dos catálogos ajustables con su historial
--   (qué reportes se asocian; qué sectores surte cada planta). Ninguna tabla existente cambia de forma: se agregan 3 disparadores AFTER INSERT (por
--   sentencia) en redes.reporte_externo_eventos, redes.l116_eventos, redes.danos y campo.reportes (el formato de campo de Comercial: David, 19-nov).
-- · Reemplaza DOS funciones (25_reemplazos.sql), cada una con su guardia md5: tecnica.f_avisos (dos bloques más) y redes.f_publicar_l116 (la publicación de la
--   línea 116 no revive lo que cerró un evento: David, 19-nov). Agrega el tipo «sin_agua» al catálogo de campo.
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
  if md5(pg_get_functiondef('redes.f_publicar_l116(bigint,text,text)'::regprocedure)) <> '1d70c1fe36186cf498504898e5098b64' then
    raise exception 'redes.f_publicar_l116 no es la publicada (Corte 5d, huella 1d70c1fe36186cf498504898e5098b64): deténgase y avise';
  end if;
  if to_regclass('campo.reportes') is null or to_regclass('campo.reporte_eventos') is null or to_regclass('campo.v_reportes_estado') is null
     or not exists (select 1 from campo.estados_reporte where codigo = 'atendido' and activo and cambio_manual and not exige_motivo)
     or not exists (select 1 from campo.estados_reporte where codigo = 'reportado' and inicial) then
    raise exception 'Los reportes de campo (campo.reportes, sus hechos o los estados «reportado» y «atendido») no son los esperados: deténgase y avise';
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
  origen             text not null check (origen in ('bot', 'l116', 'dano', 'campo')),
  reporte_externo_id uuid references redes.reportes_externos (id),
  l116_reporte_id    bigint references redes.l116_reportes (id),
  dano_id            uuid references redes.danos (id),
  campo_reporte_id   uuid references campo.reportes (id),      -- un reporte del formato de campo (Comercial o Técnica)
  ref                text generated always as (coalesce(reporte_externo_id::text, l116_reporte_id::text, dano_id::text, campo_reporte_id::text)) stored,
  tipo               text not null check (tipo in ('asociar', 'desasociar')),
  modo               text not null check (modo in ('automatica', 'al_declarar', 'manual')),
  motivo             text check (motivo is null or length(btrim(motivo)) between 10 and 500),
  autor              text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en          timestamptz not null default clock_timestamp(),
  check (num_nonnulls(reporte_externo_id, l116_reporte_id, dano_id, campo_reporte_id) = 1),
  check ((origen = 'bot') = (reporte_externo_id is not null) and (origen = 'l116') = (l116_reporte_id is not null) and (origen = 'dano') = (dano_id is not null)
         and (origen = 'campo') = (campo_reporte_id is not null)),
  check (modo <> 'manual' or motivo is not null),      -- lo que hace una persona, con motivo
  check (tipo <> 'desasociar' or modo = 'manual')
);
create index ix_evsr_evento on redes.evento_suspension_reportes (evento_id, id);
create index ix_evsr_ref on redes.evento_suspension_reportes (origen, ref, id desc);
comment on table redes.evento_suspension_reportes is 'Corte 15: reportes (bot, línea 116, daños, formato de campo) asociados a un evento de suspensión. Solo agregar: asociar y desasociar son hechos; vale el último de cada reporte.';

-- ---------- 3. Catálogos ajustables (estado + historial con motivo): qué se asocia y qué sectores surte cada planta ----------
create table redes.evento_tipos_asociables (
  origen  text not null check (origen in ('bot', 'l116', 'dano', 'campo')),
  codigo  text not null check (length(codigo) between 2 and 120 and codigo = lower(codigo)),      -- tipo del bot, causal de la 116 (en minúsculas, un espacio), tipo de daño o tipo del formato de campo
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
comment on table redes.evento_tipos_asociables is 'Corte 15: qué tipos del bot, causales de la línea 116, tipos de daño y tipos del formato de campo se asocian solos a un evento de suspensión. «sin_agua» además se avisa cuando llega fuera de un evento.';
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
  ('dano', 'electrica', 'Falla eléctrica', 'otro'),
  ('campo', 'sin_agua', 'No tengo agua o tengo baja presión', 'sin_agua');

-- ---------- 5. El tipo nuevo del catálogo de campo: «sin_agua» (David, 18-nov), en el grupo «red_acueducto», como los dos que agregó el Corte 8.
--    Lo puede escoger también quien reporta desde Comercial; esos reportes se asocian al evento y se cierran en bloque (David, 19-nov) ----------
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
   'Se avisan los reportes de falta de agua o baja presión (bot, línea 116 y formato de campo) de estas últimas horas que no están en un evento de suspensión.')
on conflict (clave) do update set nombre = excluded.nombre, descripcion = excluded.descripcion;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 20 — VISTA Y FUNCIONES INTERNAS (ninguna la ejecuta la API)
--   · quién puede qué; la zona de cada alcance; contratos y usuarios sensibles de la zona; los reportes que caen en una zona;
--   · la ASOCIACIÓN AUTOMÁTICA: tres disparadores AFTER INSERT por sentencia (con la tabla de filas nuevas: una consulta por sentencia, no por fila):
--       bot   → redes.reporte_externo_eventos (cuando entra el «recibido»);   116 → redes.l116_eventos (el «alta» al publicar);   daño → redes.danos;
--       formato de campo (Comercial o Técnica) → campo.reportes.
--     Sin eventos abiertos no hacen nada. Los eventos abiertos se leen UNA vez por sentencia («ab»), no una vez por reporte (crecía con el historial de eventos).
--     La pertenencia se decide por el punto del reporte (dentro de la zona; «toda la ciudad» no tiene geometría).
--     Si un punto cae en dos eventos abiertos gana EL MÁS ESPECÍFICO (David, 19-nov): círculo > sectores > total; entre dos de la misma clase, el de menor
--     área (un subsector antes que su sector) y, si empatan, el declarado más recientemente.
--   · lo que le llega a cada reporte: bot → «en_atencion» al asociar, «atendido» al cerrar, «recibido» al desasociar o anular; daño → una nota en su historial
--     (el daño NO se cierra con el evento: sigue hasta su reparación); 116 → «atendido» al cerrar; formato de campo → una nota al asociar, desasociar o
--     anular, y «atendido» al cerrar (si seguía «reportado» o «en revisión»).
--   · la publicación de la línea 116 NO revive lo que cerró un evento (redes.f_evento_l116_cerrado; el reemplazo está en 25_reemplazos.sql).
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

-- el evento que CERRÓ un reporte de la línea 116 (su último hecho es «asociar» a un evento que terminó en «cerrar»), o nulo. La usa la publicación de la 116:
-- lo que cerró un evento conserva «Atendido» aunque el archivo siga diciendo «Registrado»
create function redes.f_evento_l116_cerrado(p_reporte_id bigint) returns text
language sql stable security definer set search_path = redes, pg_temp as $$
  select e.codigo
    from (select y.tipo, y.evento_id from redes.evento_suspension_reportes y where y.origen = 'l116' and y.ref = p_reporte_id::text order by y.id desc limit 1) u
    join redes.eventos_suspension e on e.id = u.evento_id
   where u.tipo = 'asociar' and exists (select 1 from redes.evento_suspension_eventos z where z.evento_id = u.evento_id and z.tipo = 'cerrar') $$;

-- un reporte del formato de campo sigue abierto: «reportado» o «en revisión», y no está oculto
create function redes.f_evento_campo_abierto(p_id uuid) returns boolean
language sql stable security definer set search_path = redes, pg_temp as $$
  select campo.f_estado_actual(p_id) in ('reportado', 'en_revision')
     and coalesce((select x.tipo_evento from campo.reporte_eventos x where x.reporte_id = p_id and x.tipo_evento in ('ocultar', 'reincluir') order by x.id desc limit 1), 'reincluir') <> 'ocultar' $$;

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
returns table (origen text, reporte_externo_id uuid, l116_reporte_id bigint, dano_id uuid, campo_reporte_id uuid)
language sql stable security definer set search_path = redes, public, extensions, pg_temp as $$
  select 'bot', r.id, null::bigint, null::uuid, null::uuid
    from redes.reportes_externos r
   where r.recibido_en >= p_desde and r.geom is not null and (p_todo or (r.geom && p_geom and ST_Intersects(p_geom, r.geom)))
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'bot' and t.codigo = lower(btrim(r.tipo_bot)) and t.asocia)
     and (select x.tipo from redes.reporte_externo_eventos x where x.reporte_id = r.id order by x.id desc limit 1) = 'recibido'
     and redes.f_evento_ref_libre('bot', r.id::text)
  union all
  select 'l116', null::uuid, v.reporte_id, null::uuid, null::uuid
    from redes.l116_vigente v
   where not v.oculto and v.estado = 'registrado' and v.fecha_registro >= p_desde and v.geom is not null and (p_todo or (v.geom && p_geom and ST_Intersects(p_geom, v.geom)))
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'l116' and t.codigo = redes.f_evento_clave(v.causal) and t.asocia)
     and redes.f_evento_ref_libre('l116', v.reporte_id::text)
  union all
  select 'dano', null::uuid, null::bigint, d.id, null::uuid
    from redes.danos d
   where d.registrado_en >= p_desde and d.t_detectado >= p_desde and d.sistema = 'acueducto' and d.geom is not null and (p_todo or (d.geom && p_geom and ST_Intersects(p_geom, d.geom)))
     and (p_sin_dano is null or d.id <> p_sin_dano)
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'dano' and t.codigo = d.tipo_codigo and t.asocia)
     and (select vd.estado from redes.v_dano vd where vd.id = d.id) <> 'atendido'
     and redes.f_evento_ref_libre('dano', d.id::text)
  union all
  select 'campo', null::uuid, null::bigint, null::uuid, c.id
    from campo.reportes c join campo.tipos_reporte tc on tc.id = c.tipo_id
   where c.registrado_en >= p_desde and (p_todo or ST_Intersects(p_geom, c.geom))
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'campo' and t.codigo = tc.codigo and t.asocia)
     and redes.f_evento_campo_abierto(c.id)
     and redes.f_evento_ref_libre('campo', c.id::text) $$;

-- ---------- lo que le llega a cada reporte de unas asociaciones: bot → un hecho de su historial; daño → una nota; formato de campo → una nota, o «atendido»
-- cuando el evento se cierra (p_bot_tipo = 'atendido') y el reporte seguía abierto. «{evento}» = el código ----------
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
  insert into campo.reporte_eventos (reporte_id, tipo_evento, estado_nuevo, motivo, autor)
  select r.campo_reporte_id, case when k.cierra then 'cambio_estado' else 'nota' end, case when k.cierra then 'atendido' end,
         left(replace(p_texto, '{evento}', e.codigo), 1000), p_autor
    from redes.evento_suspension_reportes r join redes.eventos_suspension e on e.id = r.evento_id
   cross join lateral (select coalesce(p_bot_tipo = 'atendido', false) and redes.f_evento_campo_abierto(r.campo_reporte_id) as cierra) k
   where r.id = any (p_ids) and r.origen = 'campo' order by r.id;
end $$;

-- ---------- LA ASOCIACIÓN AUTOMÁTICA ----------
-- bot: cuando entra el «recibido» ORIGINAL de un reporte (sin motivo; el reporte ya está guardado). El «en_atencion» que escribe vuelve a disparar esto y sale
-- en la primera línea. Un «recibido» con motivo es el de un reporte que alguien desasoció o de un evento anulado: ese no se vuelve a asociar solo.
create function redes.f_evento_tg_bot() returns trigger
language plpgsql security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_ids bigint[];
begin
  if not exists (select 1 from nuevos x where x.tipo = 'recibido' and x.motivo is null) or not exists (select 1 from redes.f_eventos_abiertos()) then return null; end if;
  with ab as materialized (select e.id, e.desde, e.todo, e.geom, e.alcance from redes.f_eventos_abiertos() e),
  hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, tipo, modo, autor)
    select ev.id, 'bot', r.id, 'asociar', 'automatica', 'sistema@evento.suspension'
      from nuevos x join redes.reportes_externos r on r.id = x.reporte_id
     cross join lateral (select e.id from ab e
                          where e.desde <= r.recibido_en and (e.todo or ST_Intersects(e.geom, r.geom)) order by case e.alcance when 'circulo' then 1 when 'sectores' then 2 else 3 end, ST_Area(e.geom) nulls last, e.id desc limit 1) ev
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
  with ab as materialized (select e.id, e.desde, e.todo, e.geom, e.alcance from redes.f_eventos_abiertos() e)
  insert into redes.evento_suspension_reportes (evento_id, origen, l116_reporte_id, tipo, modo, autor)
  select ev.id, 'l116', r.id, 'asociar', 'automatica', 'sistema@evento.suspension'
    from nuevos x join redes.l116_reportes r on r.id = x.reporte_id
   cross join lateral (select e.id from ab e
                        where e.desde <= r.fecha_registro and (e.todo or ST_Intersects(e.geom, x.geom)) order by case e.alcance when 'circulo' then 1 when 'sectores' then 2 else 3 end, ST_Area(e.geom) nulls last, e.id desc limit 1) ev
   where x.tipo = 'alta' and x.estado = 'registrado' and x.geom is not null
     and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'l116' and t.codigo = redes.f_evento_clave(r.causal) and t.asocia);      -- (un «alta» es de un reporte nuevo: no puede estar ya en un evento)
  return null;
end $$;
create trigger t_evento_asociar after insert on redes.l116_eventos referencing new table as nuevos for each statement execute function redes.f_evento_tg_l116();

-- daños (formulario, o un reporte del bot convertido): el daño se guarda como siempre y queda asociado, con una nota en su historial
create function redes.f_evento_tg_dano() returns trigger
language plpgsql security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_ids bigint[];
begin
  if not exists (select 1 from redes.f_eventos_abiertos()) then return null; end if;
  with ab as materialized (select e.id, e.desde, e.todo, e.geom, e.alcance from redes.f_eventos_abiertos() e),
  hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, dano_id, tipo, modo, autor)
    select ev.id, 'dano', d.id, 'asociar', 'automatica', 'sistema@evento.suspension'
      from nuevos d
     cross join lateral (select e.id from ab e
                          where e.desde <= d.t_detectado and (e.todo or ST_Intersects(e.geom, d.geom)) order by case e.alcance when 'circulo' then 1 when 'sectores' then 2 else 3 end, ST_Area(e.geom) nulls last, e.id desc limit 1) ev
     where d.sistema = 'acueducto' and d.geom is not null
       and exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'dano' and t.codigo = d.tipo_codigo and t.asocia)
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, null, 'Asociado al evento de suspensión {evento} (el daño sigue abierto hasta su reparación)', 'sistema@evento.suspension');
  return null;
end $$;
create trigger t_evento_asociar after insert on redes.danos referencing new table as nuevos for each statement execute function redes.f_evento_tg_dano();

-- formato de campo (Comercial o Técnica): el reporte se guarda como siempre y queda asociado, con una nota en su historial (David, 19-nov)
create function redes.f_evento_tg_campo() returns trigger
language plpgsql security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_ids bigint[];
begin
  if not exists (select 1 from redes.f_eventos_abiertos()) then return null; end if;
  with ab as materialized (select e.id, e.desde, e.todo, e.geom, e.alcance from redes.f_eventos_abiertos() e),
  hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, campo_reporte_id, tipo, modo, autor)
    select ev.id, 'campo', c.id, 'asociar', 'automatica', 'sistema@evento.suspension'
      from nuevos c join campo.tipos_reporte tc on tc.id = c.tipo_id
     cross join lateral (select e.id from ab e
                          where e.desde <= c.registrado_en and (e.todo or ST_Intersects(e.geom, c.geom)) order by case e.alcance when 'circulo' then 1 when 'sectores' then 2 else 3 end, ST_Area(e.geom) nulls last, e.id desc limit 1) ev
     where exists (select 1 from redes.evento_tipos_asociables t where t.origen = 'campo' and t.codigo = tc.codigo and t.asocia)
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, null, 'Asociado al evento de suspensión {evento}', 'sistema@evento.suspension');
  return null;
end $$;
create trigger t_evento_asociar after insert on campo.reportes referencing new table as nuevos for each statement execute function redes.f_evento_tg_campo();

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
                                           'danos', count(*) filter (where r.origen = 'dano'), 'campo', count(*) filter (where r.origen = 'campo')) from redes.f_evento_reportes(e.id) r),
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
    from (select a.*, coalesce((select x.regreso_estimado from redes.evento_suspension_eventos x where x.evento_id = a.id and x.tipo = 'regreso' order by x.id desc limit 1),
                               a.regreso_estimado) as regreso_vigente
            from redes.f_eventos_abiertos() a) e      -- solo los abiertos: no recorre el historial de eventos
   cross join lateral (select count(*)::integer as n from redes.f_evento_reportes(e.id)) c
   where e.creado_en <= p_ahora $$;

-- Los avisos se consultan seguido. Los eventos abiertos y los tipos de «sin agua» se calculan UNA vez, y «está en un evento abierto» se resuelve por reporte
-- con el índice de las asociaciones (origen, ref), escrito aquí mismo (una función por fila no se integra en el plan y se llamaba miles de veces).
create function redes.f_sin_agua_para_avisos(p_ahora timestamptz, p_horas numeric) returns table (n integer, desde timestamptz, items jsonb)
language sql stable security definer set search_path = redes, public, pg_temp as $$
  with abiertos as materialized (select coalesce(array_agg(e.id), '{}') as ids from redes.f_eventos_abiertos() e),
  tipos as materialized (
    select coalesce(array_agg(t.codigo) filter (where t.origen = 'bot'), '{}') as bot, coalesce(array_agg(t.codigo) filter (where t.origen = 'l116'), '{}') as l116,
           coalesce(array_agg(t.codigo) filter (where t.origen = 'campo'), '{}') as campo
      from redes.evento_tipos_asociables t where t.clase = 'sin_agua'),
  s as (
    select r.recibido_en as cuando, 'Bot · ' || r.radicado as txt
      from redes.reportes_externos r
     where r.recibido_en > p_ahora - make_interval(secs => (p_horas * 3600)::double precision) and r.recibido_en <= p_ahora
       and lower(btrim(r.tipo_bot)) = any ((select bot from tipos)::text[])
       and (select x.tipo from redes.reporte_externo_eventos x where x.reporte_id = r.id order by x.id desc limit 1) = 'recibido'
       and not exists (select 1 from redes.evento_suspension_reportes y
                        where y.origen = 'bot' and y.ref = r.id::text and y.tipo = 'asociar'
                          and not exists (select 1 from redes.evento_suspension_reportes y2 where y2.origen = y.origen and y2.ref = y.ref and y2.id > y.id)
                          and y.evento_id = any ((select ids from abiertos)::bigint[]))
    union all
    select v.fecha_registro, 'Línea 116 · ' || v.reporte || coalesce(' · sector ' || v.sector, '')
      from redes.l116_vigente v
     where not v.oculto and v.estado = 'registrado' and v.fecha_registro > p_ahora - make_interval(secs => (p_horas * 3600)::double precision) and v.fecha_registro <= p_ahora
       and redes.f_evento_clave(v.causal) = any ((select l116 from tipos)::text[])
       and not exists (select 1 from redes.evento_suspension_reportes y
                        where y.origen = 'l116' and y.ref = v.reporte_id::text and y.tipo = 'asociar'
                          and not exists (select 1 from redes.evento_suspension_reportes y2 where y2.origen = y.origen and y2.ref = y.ref and y2.id > y.id)
                          and y.evento_id = any ((select ids from abiertos)::bigint[]))
    union all
    select c.registrado_en, 'Formato de campo · ' || coalesce(c.consecutivo, 'REP-' || lpad(c.seq::text, 6, '0'))
      from campo.reportes c join campo.tipos_reporte tc on tc.id = c.tipo_id
     where c.registrado_en > p_ahora - make_interval(secs => (p_horas * 3600)::double precision) and c.registrado_en <= p_ahora
       and tc.codigo = any ((select campo from tipos)::text[])
       and campo.f_estado_actual(c.id) = 'reportado' and redes.f_evento_campo_abierto(c.id)
       and not exists (select 1 from redes.evento_suspension_reportes y
                        where y.origen = 'campo' and y.ref = c.id::text and y.tipo = 'asociar'
                          and not exists (select 1 from redes.evento_suspension_reportes y2 where y2.origen = y.origen and y2.ref = y.ref and y2.id > y.id)
                          and y.evento_id = any ((select ids from abiertos)::bigint[])))
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
                                           'danos', count(*) filter (where k.origen = 'dano'), 'campo', count(*) filter (where k.origen = 'campo'))
                   from redes.f_evento_candidatos(z.geom, z.todo, v_desde) k),
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
    insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, campo_reporte_id, tipo, modo, autor)
    select v_id, k.origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, k.campo_reporte_id, 'asociar', 'al_declarar', v_email
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

-- «dar de alta»: cierra el evento y, con el mismo motivo y la misma hora, los reportes asociados del bot, de la 116 y del formato de campo. Los daños quedan con
-- la nota (siguen abiertos)
create function public.geoportal_redes_evento_cerrar(p_solicitante text, p_codigo text, p_motivo text, p_hecho_en text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; v_mot text := btrim(coalesce(p_motivo, '')); v_hecho timestamptz; v_ahora timestamptz := clock_timestamp(); v_ids bigint[]; v_l116 bigint[]; v_bot integer; v_dan integer; v_cam integer; v_txt text;
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo);
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo del cierre (de 10 a 500 letras)'); end if;
  v_hecho := coalesce(redes.f_instante(p_hecho_en, 'hora del cierre'), v_ahora);
  if v_hecho > v_ahora + interval '5 minutes' then perform tecnica.f_error('La hora del cierre no puede ser futura'); end if;
  if v_hecho < e.desde then perform tecnica.f_error('El evento no se puede cerrar antes de la hora en que empezó'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.eventos_suspension'));
  select array_agg(r.id), count(*) filter (where r.origen = 'bot'), count(*) filter (where r.origen = 'dano'),
         count(*) filter (where r.origen = 'campo' and redes.f_evento_campo_abierto(r.campo_reporte_id))      -- los de campo que siguen abiertos: los que se cierran
    into v_ids, v_bot, v_dan, v_cam from redes.f_evento_reportes(e.id) r;
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
  perform tecnica.f_auditar(e.email, 'redes_evento_cerrar', e.codigo, jsonb_build_object('reportes', coalesce(cardinality(v_ids), 0), 'bot', v_bot, 'l116', coalesce(cardinality(v_l116), 0), 'campo', v_cam, 'danos', v_dan), null);
  return redes.f_evento_json(e.id) || jsonb_build_object('cerrados', jsonb_build_object('bot', v_bot, 'l116', coalesce(cardinality(v_l116), 0), 'campo', v_cam), 'danos_siguen_abiertos', v_dan);
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

-- un reporte por su referencia: bot = su id (uuid) · l116 = el número del reporte · dano = DAN-000123 · campo = su código (REP-000123 o su consecutivo)
create function redes.f_evento_reporte_ref(p_origen text, p_ref text, out reporte_externo_id uuid, out l116_reporte_id bigint, out dano_id uuid, out campo_reporte_id uuid, out ref text) returns record
language plpgsql stable security definer set search_path = redes, tecnica, pg_temp as $$
declare v_ref text := btrim(coalesce(p_ref, ''));
begin
  if p_origen = 'bot' and v_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select r.id into reporte_externo_id from redes.reportes_externos r where r.id = v_ref::uuid;
  elsif p_origen = 'l116' and v_ref ~ '^[0-9]{1,15}$' then
    select r.id into l116_reporte_id from redes.l116_reportes r where r.reporte = v_ref::bigint;
  elsif p_origen = 'dano' and upper(v_ref) ~ '^DAN-[0-9]{6}$' then
    select d.id into dano_id from redes.danos d where d.codigo = upper(v_ref);
  elsif p_origen = 'campo' and upper(v_ref) ~ '^REP-[0-9]{1,15}$' then
    select c.id into campo_reporte_id from campo.reportes c where c.seq = substr(v_ref, 5)::bigint and c.consecutivo is null;
  elsif p_origen = 'campo' and length(v_ref) between 3 and 40 then
    select c.id into campo_reporte_id from campo.reportes c where c.consecutivo = upper(v_ref);
  else perform tecnica.f_error('Diga qué reporte es: del bot (su identificador), de la línea 116 (su número), un daño (DAN-000123) o un reporte de campo (REP-000123)');
  end if;
  ref := coalesce(reporte_externo_id::text, l116_reporte_id::text, dano_id::text, campo_reporte_id::text);
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
  insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, campo_reporte_id, tipo, modo, motivo, autor)
  values (e.id, p_origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, k.campo_reporte_id, 'desasociar', 'manual', v_mot, e.email) returning id into v_id;
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
  if p_origen = 'campo' and not redes.f_evento_campo_abierto(k.campo_reporte_id) then
    perform tecnica.f_error('Ese reporte de campo ya no está abierto (se atendió, se descartó, es un duplicado o está oculto)');
  end if;
  insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, campo_reporte_id, tipo, modo, motivo, autor)
  values (e.id, p_origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, k.campo_reporte_id, 'asociar', 'manual', v_mot, e.email) returning id into v_id;
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

-- el detalle: el evento, sus reportes asociados (sin nombres, direcciones, textos del ciudadano ni número de contrato), los sensibles confirmados (contrato y tipo) y el historial
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
                                      when 'campo' then (select coalesce(c.consecutivo, 'REP-' || lpad(c.seq::text, 6, '0')) from campo.reportes c where c.id = r.campo_reporte_id)
                                      else (select d.codigo from redes.danos d where d.id = r.dano_id) end,
                 'rotulo', case r.origen when 'bot' then (select 'Bot · ' || b.radicado from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                         when 'l116' then (select 'Línea 116 · ' || l.reporte from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                         when 'campo' then (select 'Formato de campo · ' || coalesce(c.consecutivo, 'REP-' || lpad(c.seq::text, 6, '0')) from campo.reportes c where c.id = r.campo_reporte_id)
                                         else (select d.codigo from redes.danos d where d.id = r.dano_id) end,
                 'tipo', case r.origen when 'bot' then (select coalesce(t.nombre, b.tipo_bot) from redes.reportes_externos b left join redes.evento_tipos_asociables t on t.origen = 'bot' and t.codigo = lower(btrim(b.tipo_bot)) where b.id = r.reporte_externo_id)
                                       when 'l116' then (select l.causal from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                       when 'campo' then (select tc.nombre from campo.reportes c join campo.tipos_reporte tc on tc.id = c.tipo_id where c.id = r.campo_reporte_id)
                                       else (select td.nombre from redes.danos d join redes.tipos_dano td on td.codigo = d.tipo_codigo where d.id = r.dano_id) end,
                 'cuando', case r.origen when 'bot' then (select b.recibido_en from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                         when 'l116' then (select l.fecha_registro from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                         when 'campo' then (select c.registrado_en from campo.reportes c where c.id = r.campo_reporte_id)
                                         else (select d.t_detectado from redes.danos d where d.id = r.dano_id) end,
                 'lat', case r.origen when 'bot' then (select b.lat from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                      when 'l116' then (select round(ST_Y(v.geom)::numeric, 6) from redes.l116_vigente v where v.reporte_id = r.l116_reporte_id)
                                      when 'campo' then (select c.lat from campo.reportes c where c.id = r.campo_reporte_id)
                                      else (select d.lat from redes.danos d where d.id = r.dano_id) end,
                 'lon', case r.origen when 'bot' then (select b.lon from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                      when 'l116' then (select round(ST_X(v.geom)::numeric, 6) from redes.l116_vigente v where v.reporte_id = r.l116_reporte_id)
                                      when 'campo' then (select c.lon from campo.reportes c where c.id = r.campo_reporte_id)
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
  if coalesce(p_origen, '') not in ('bot', 'l116', 'dano', 'campo') then perform tecnica.f_error('El origen es bot, l116, dano o campo'); end if;
  if length(v_cod) < 2 or length(v_cod) > 120 then perform tecnica.f_error('Escriba el tipo o la causal'); end if;
  if p_asocia is null then perform tecnica.f_error('Diga si se asocia o no'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  if v_cla is not null and v_cla not in ('sin_agua', 'dano_red', 'otro') then perform tecnica.f_error('La clase es sin_agua, dano_red u otro'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.evento_tipos_asociables'));
  select * into v_fila from redes.evento_tipos_asociables t where t.origen = p_origen and t.codigo = v_cod;
  if v_fila.codigo is null then
    if v_nom is null or v_cla is null then perform tecnica.f_error('Ese tipo no está en la lista: para agregarlo escriba su nombre y su clase'); end if;
    if p_origen = 'dano' and not exists (select 1 from redes.tipos_dano td where td.codigo = v_cod) then perform tecnica.f_error('Ese tipo de daño no existe', 'P0002'); end if;
    if p_origen = 'campo' and not exists (select 1 from campo.tipos_reporte tc where tc.codigo = v_cod) then perform tecnica.f_error('Ese tipo del formato de campo no existe', 'P0002'); end if;
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
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- son los textos vivos con cambios exactos (cada uno con su guardia md5 en 10_esquema.sql y su texto de antes en la reversa).
-- 1) tecnica.f_avisos (la del Corte 14): dos bloques nuevos antes del de Personal.
--   · D15: un aviso por evento de suspensión abierto (rojo si ya pasó la hora estimada de regreso);
--   · D15b: un aviso con los reportes de falta de agua (bot, línea 116 y formato de campo) que no están en ningún evento.
-- 2) redes.f_publicar_l116 (la del Corte 5d): la publicación de la línea 116 NO revive lo que cerró un evento de suspensión (David, 19-nov). Si el archivo
--    trae en «Registrado» un reporte que un evento dejó «Atendido», el reporte conserva «Atendido» y la diferencia con la fuente queda en su historial
--    (una vez). Lo demás de la publicación no cambia; el resultado gana la clave «conservados_por_evento».
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
  -- D15b. Reportes de falta de agua o baja presión (bot, línea 116 y formato de campo) de las últimas horas que NO están en ningún evento: un solo aviso
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

-- redes.f_publicar_l116(bigint,text,text)
CREATE OR REPLACE FUNCTION redes.f_publicar_l116(p_carga bigint, p_autor text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare c redes.v_cargas_estado%rowtype; v_res jsonb; v_rev bigint; v_version integer; v_nuevos integer; v_estado integer; v_mostrar integer; v_iguales integer; v_mot text := btrim(p_motivo);
        v_cons integer;      -- Corte 15: reportes que cerró un evento de suspensión y que el archivo trae otra vez en «Registrado»
begin
  perform pg_advisory_xact_lock(hashtext('redes.carga.linea_116'));
  select * into c from redes.v_cargas_estado where id = p_carga;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: no se puede publicar', p_carga, c.estado)); end if;
  v_res := redes.f_resumen_l116(p_carga);      -- la última revisión si sigue valiendo; si la 116 cambió desde entonces, una nueva
  if not (v_res ->> 'lista_para_publicar')::boolean then
    perform tecnica.f_error('La carga no está lista para publicar: ' || array_to_string(array(select jsonb_array_elements_text(v_res -> 'bloqueos')), '; '));
  end if;
  v_rev := (v_res ->> 'revision_id')::bigint;
  v_version := (select count(*) + 1 from redes.v_cargas_estado x where x.capa_codigo = 'linea_116' and x.estado = 'publicada');
  -- (a) nuevos
  insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, comuna, contrato, carga_id)
  select f.reporte, f.fecha, f.servicio, f.causal, f.comuna, f.contrato, p_carga
    from redes.l116_revision_filas f where f.revision_id = v_rev and f.accion = 'nuevo' order by f.reporte;
  get diagnostics v_nuevos = row_count;
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, sector, subsector, carga_id, motivo, autor)
  select r.id, 'alta', f.estado, f.metodo, f.geom, f.sector, f.subsector, p_carga, v_mot, p_autor
    from redes.l116_revision_filas f join redes.l116_reportes r on r.reporte = f.reporte
   where f.revision_id = v_rev and f.accion = 'nuevo' order by r.id;
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, contrato, estado, estado_desde, metodo, geom, sector, subsector)
  select r.id, f.reporte, f.fecha, (f.fecha at time zone 'America/Bogota')::date, f.servicio, f.causal, f.contrato, f.estado, f.fecha, f.metodo, f.geom, f.sector, f.subsector
    from redes.l116_revision_filas f join redes.l116_reportes r on r.reporte = f.reporte
   where f.revision_id = v_rev and f.accion = 'nuevo';
  -- Corte 15: lo que cerró un evento de suspensión y el archivo trae otra vez en «Registrado» («conservados»). Se calcula UNA vez, en una tabla temporal
  -- (como las de redes.f_l116_candidatos), y las sentencias de abajo solo la cruzan
  if to_regclass('pg_temp._l116_cons') is not null then drop table pg_temp._l116_cons; end if;
  create temp table _l116_cons on commit drop as
  select x.reporte_id, x.evento
    from (select f.reporte_id, redes.f_evento_l116_cerrado(f.reporte_id) as evento
            from redes.l116_revision_filas f
           where f.revision_id = v_rev and f.accion in ('estado', 'mostrar') and f.estado = 'registrado' and f.estado_vigente = 'atendido' offset 0) x
   where x.evento is not null;
  get diagnostics v_cons = row_count;
  if v_cons > 0 then create unique index on _l116_cons (reporte_id); analyze _l116_cons; end if;
  -- (b) cambios de estado (también los de los que vuelven a mostrarse)
  insert into redes.l116_eventos (reporte_id, tipo, estado, estado_antes, carga_id, motivo, autor)
  select f.reporte_id, 'estado', f.estado, f.estado_vigente, p_carga, v_mot, p_autor
    from redes.l116_revision_filas f where f.revision_id = v_rev and f.accion in ('estado', 'mostrar') and f.estado <> f.estado_vigente
     and not exists (select 1 from _l116_cons k where k.reporte_id = f.reporte_id)      -- Corte 15: lo que cerró un evento no se revive
   order by f.reporte_id;
  get diagnostics v_estado = row_count;
  -- (b2) Corte 15: lo conservado sigue «Atendido» aunque el archivo lo traiga en «Registrado». La diferencia con la fuente queda en el historial del reporte,
  --      una sola vez (sin carga_id: revertir la carga no tiene nada que devolver). Se busca por el reporte, con su índice
  if v_cons > 0 then
    insert into redes.l116_eventos (reporte_id, tipo, estado, estado_antes, motivo, autor)
    select k.reporte_id, 'estado', 'atendido', 'atendido',
           left(format('La carga %s de la línea 116 lo trae en «Registrado»: conserva «Atendido» porque lo cerró el evento de suspensión %s', p_carga, k.evento), 1000), p_autor
      from _l116_cons k
     where not exists (select 1 from redes.l116_eventos x where x.reporte_id = k.reporte_id and x.tipo = 'estado' and x.estado = 'atendido' and x.estado_antes = 'atendido'
                                                           and x.motivo like 'La carga % de la línea 116 lo trae en «Registrado»%')
     order by k.reporte_id;
  end if;
  -- (c) los que vuelven a mostrarse (los había ocultado la reversa de una carga)
  insert into redes.l116_eventos (reporte_id, tipo, carga_id, motivo, autor)
  select f.reporte_id, 'mostrar', p_carga, v_mot, p_autor from redes.l116_revision_filas f where f.revision_id = v_rev and f.accion = 'mostrar' order by f.reporte_id;
  get diagnostics v_mostrar = row_count;
  update redes.l116_vigente v set estado = case when k.reporte_id is not null then v.estado else f.estado end,
         estado_desde = case when k.reporte_id is null and v.estado <> f.estado then clock_timestamp() else v.estado_desde end,
         oculto = false, actualizado_en = clock_timestamp()
    from redes.l116_revision_filas f left join _l116_cons k on k.reporte_id = f.reporte_id
   where f.revision_id = v_rev and f.accion in ('estado', 'mostrar') and f.reporte_id = v.reporte_id;
  v_iguales := (v_res -> 'frente_a_vigente' ->> 'igual')::integer;
  insert into redes.carga_eventos (carga_id, tipo, version_capa, nuevos, cambiados, iguales, retirados, reactivados, detalle, motivo, autor)
  values (p_carga, 'publicar', v_version, v_nuevos, v_estado, v_iguales, 0, v_mostrar,
          jsonb_build_object('ubicacion', v_res -> 'ubicacion', 'con_sector', v_res -> 'con_sector', 'servicios', v_res -> 'servicios', 'revision_id', v_rev, 'conservados_por_evento', v_cons), v_mot, p_autor);
  return jsonb_build_object('carga_id', p_carga, 'capa', 'linea_116', 'version_capa', v_version, 'nuevos', v_nuevos, 'cambiados', v_estado, 'cambios_estado', v_estado,
                            'iguales', v_iguales, 'reactivados', v_mostrar, 'retirados', 0, 'ubicacion', v_res -> 'ubicacion', 'con_sector', v_res -> 'con_sector',
                            'conservados_por_evento', v_cons);
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
        'disparadores', jsonb_build_array('redes.reporte_externo_eventos', 'redes.l116_eventos', 'redes.danos', 'campo.reportes'),
        'reemplazadas', jsonb_build_array('tecnica.f_avisos', 'redes.f_publicar_l116'), 'tipo_de_campo', 'sin_agua',
        'motivo', 'Corte 15: evento de suspensión (por sectores, por círculo o total), asociación automática de reportes, cierre en bloque y un aviso por evento'), null);
commit;
