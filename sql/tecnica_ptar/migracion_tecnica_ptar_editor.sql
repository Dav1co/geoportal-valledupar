begin;
-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 10 — GUARDIA Y ESQUEMA. Va en la migración y en el ensayo.
-- Decisiones de David (DECISIONES_DAVID_21nov.md, carpeta paquete_fase1/ptar_cascaron): D1 (la PTAR no entra en tecnica.plantas: tabla aparte de instalaciones),
-- D6 (alcance PTAP / PTAR por persona, como evento, sin tocar _shared/auth.ts ni autorizar()), D9 (el dibujo no se edita: se desactiva con motivo y se crea la fila nueva),
-- D10 (horas «sin dato reciente» por instalación: 24 en la PTAP, 168 en la PTAR) y D12 (los activos de redes dentro del perímetro se copian como elementos de la planta).
-- NO toca ninguna función ni tabla de redes (la huella de redes no cambia). Ninguna tabla existente cambia de columnas.
-- =====================================================================

-- ---------- Guardia: lo que tiene que estar publicado (si algo no calza, se detiene sin cambiar nada) ----------
do $$
declare v_redes text; v_tec text; v_sup text;
begin
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v_redes from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if v_redes is distinct from '1ba192724c2fddcf321104700829f3cc' then
    raise exception 'GUARDIA PTAR-1: la huella de redes es % y se esperaba 1ba192724c2fddcf321104700829f3cc (corte de eventos publicado). Deténgase y avise', v_redes;
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v_tec from pg_proc p
   where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'));
  if v_tec is distinct from '3e9b0121e2b8beb313fad05de9e50f15' then
    raise exception 'GUARDIA PTAR-1: la huella de técnica es % y se esperaba 3e9b0121e2b8beb313fad05de9e50f15. Deténgase y avise', v_tec;
  end if;
  select md5(pg_get_functiondef('tecnica.f_autorizar_supervision(text)'::regprocedure)) into v_sup;
  if v_sup is distinct from '50f8be54db2465be1db2a03a37b26d20' then
    raise exception 'GUARDIA PTAR-1: tecnica.f_autorizar_supervision no es la publicada (md5 %, se esperaba 50f8be54db2465be1db2a03a37b26d20). Deténgase y avise', v_sup;
  end if;
  if to_regclass('tecnica.instalaciones') is not null or to_regclass('tecnica.elementos_planta') is not null or to_regclass('tecnica.alcance_eventos') is not null
     or to_regclass('tecnica.elemento_alias_eventos') is not null then
    raise exception 'GUARDIA PTAR-1: ya existen tablas de la PTAR: el paquete parece aplicado. Use la reversa antes de repetir';
  end if;
  if (select count(*) from tecnica.plantas where codigo in ('huaricha', 'gota_fria')) <> 2 then
    raise exception 'GUARDIA PTAR-1: faltan las plantas huaricha y gota_fria en tecnica.plantas';
  end if;
  if to_regtype('geometry') is null then
    raise exception 'GUARDIA PTAR-1: no se encuentra el tipo geometry (PostGIS) en el search_path';
  end if;
  if to_regprocedure('redes.f_funciones_sin_where()') is null then
    raise exception 'GUARDIA PTAR-1: falta redes.f_funciones_sin_where() (comprobación de pg-safeupdate)';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. Instalaciones (D1): las dos PTAP (enlazadas a su planta de tecnica.plantas) y la PTAR El Salguero (sin planta: no aparece en nada de agua potable).
-- ---------------------------------------------------------------------
create table tecnica.instalaciones (
  id               bigint generated always as identity primary key,
  codigo           text not null unique check (codigo ~ '^[a-z][a-z0-9_]{1,29}$'),
  nombre           text not null check (length(btrim(nombre)) between 2 and 80),
  tipo             text not null check (tipo in ('potable', 'residual')),
  planta_id        bigint unique references tecnica.plantas (id),
  horas_sin_dato   integer not null check (horas_sin_dato between 1 and 2160),       -- D10: ventana de «sin dato reciente» (24 h PTAP, 7 días PTAR)
  activa           boolean not null default true,
  motivo_inactiva  text check (motivo_inactiva is null or length(btrim(motivo_inactiva)) between 10 and 1000),
  creado_en        timestamptz not null default clock_timestamp(),
  constraint instalaciones_planta_por_tipo check ((tipo = 'potable') = (planta_id is not null)),
  constraint instalaciones_motivo check (activa = (motivo_inactiva is null))
);
comment on table tecnica.instalaciones is 'PTAR-1 (D1): plantas del mapa. Las PTAP enlazan su planta de tecnica.plantas; la PTAR no es una planta de agua potable. No se borra: se desactiva con motivo.';

insert into tecnica.instalaciones (codigo, nombre, tipo, planta_id, horas_sin_dato)
select 'ptap_huaricha', 'PTAP Huaricha', 'potable', id, 24 from tecnica.plantas where codigo = 'huaricha'
union all select 'ptap_gota_fria', 'PTAP Gota Fría', 'potable', id, 24 from tecnica.plantas where codigo = 'gota_fria'
union all select 'ptar', 'PTAR El Salguero', 'residual', null, 168;

-- ---------------------------------------------------------------------
-- 2. Elementos de la planta (mapa): perímetro, lagunas, tramos (entre lagunas, colectores y conductos internos), puntos de medición, pozos y descargas (VER).
--    origen 'dibujo' = GeoJSON de David; 'redes' = copia de solo lectura de un activo de redes (D12). El activo sigue siendo uno solo, el de redes: aquí solo su código.
--    D9: ninguna columna se edita; corregir = desactivar con motivo y crear la fila nueva con reemplaza_id (mismo código).
-- ---------------------------------------------------------------------
create table tecnica.elementos_planta (
  id               bigint generated always as identity primary key,
  codigo           text not null check (codigo ~ '^[A-Z0-9][A-Z0-9_-]{1,39}$'),
  instalacion_id   bigint not null references tecnica.instalaciones (id),
  tipo             text not null check (tipo in ('perimetro', 'laguna', 'tramo', 'punto_medicion', 'pozo', 'descarga')),
  nombre           text not null check (length(btrim(nombre)) between 2 and 120),
  orden            smallint not null default 0 check (orden between 0 and 999),
  geom             geometry(Geometry, 4326) not null,
  punto_id         bigint references tecnica.puntos (id),
  desde_id         bigint references tecnica.elementos_planta (id),
  hasta_id         bigint references tecnica.elementos_planta (id),
  activo_codigo    text check (activo_codigo is null or activo_codigo ~ '^[A-Z]{3}-[0-9]{6}$'),
  atributos        jsonb not null default '{}'::jsonb check (jsonb_typeof(atributos) = 'object'),
  origen           text not null check (origen in ('dibujo', 'redes')),
  activo           boolean not null default true,
  motivo_inactivo  text check (motivo_inactivo is null or length(btrim(motivo_inactivo)) between 10 and 1000),
  inactivado_en    timestamptz,
  reemplaza_id     bigint references tecnica.elementos_planta (id),
  creado_por       text not null check (creado_por = lower(creado_por) and position('@' in creado_por) > 1),
  creado_en        timestamptz not null default clock_timestamp(),
  constraint elementos_planta_forma check (
       (tipo in ('perimetro', 'laguna') and geometrytype(geom) in ('POLYGON', 'MULTIPOLYGON'))
    or (tipo = 'tramo' and geometrytype(geom) in ('LINESTRING', 'MULTILINESTRING'))
    or (tipo in ('punto_medicion', 'pozo', 'descarga') and geometrytype(geom) = 'POINT')),
  constraint elementos_planta_valida check (st_isvalid(geom) and not st_isempty(geom)),
  constraint elementos_planta_punto check (punto_id is null or tipo = 'punto_medicion'),
  constraint elementos_planta_flujo check ((desde_id is null and hasta_id is null) or tipo = 'tramo'),
  constraint elementos_planta_redes check (origen <> 'redes' or activo_codigo is not null),
  constraint elementos_planta_inactivo check ((activo and motivo_inactivo is null and inactivado_en is null) or (not activo and motivo_inactivo is not null and inactivado_en is not null))
);
create unique index uq_elementos_planta_codigo_activo on tecnica.elementos_planta (codigo) where activo;
create unique index uq_elementos_planta_activo_redes on tecnica.elementos_planta (instalacion_id, activo_codigo) where activo and activo_codigo is not null;
create index ix_elementos_planta_instalacion on tecnica.elementos_planta (instalacion_id, tipo, orden) where activo;
create index ix_elementos_planta_codigo on tecnica.elementos_planta (codigo, id desc);
create index ix_elementos_planta_geom on tecnica.elementos_planta using gist (geom);
comment on table tecnica.elementos_planta is 'PTAR-1: elementos del mapa de cada instalación (D7, D9, D12). Solo se agregan filas; lo único que cambia de una fila es desactivarla con motivo.';

-- Al insertar: la instalación activa; desde/hasta y reemplaza_id de la misma instalación; reemplaza_id = misma pieza (mismo código) ya desactivada.
create function tecnica.f_elemento_coherente() returns trigger
language plpgsql set search_path to 'pg_catalog', 'pg_temp' as $$
declare v_inst bigint; v_cod text; v_act boolean;
begin
  if not exists (select 1 from tecnica.instalaciones i where i.id = new.instalacion_id and i.activa) then
    raise exception 'La instalación del elemento no existe o está inactiva' using errcode = '22023';
  end if;
  if new.desde_id is not null and not exists (select 1 from tecnica.elementos_planta e where e.id = new.desde_id and e.instalacion_id = new.instalacion_id and e.activo) then
    raise exception 'El tramo debe salir de un elemento activo de la misma planta' using errcode = '22023';
  end if;
  if new.hasta_id is not null and not exists (select 1 from tecnica.elementos_planta e where e.id = new.hasta_id and e.instalacion_id = new.instalacion_id and e.activo) then
    raise exception 'El tramo debe llegar a un elemento activo de la misma planta' using errcode = '22023';
  end if;
  if new.reemplaza_id is not null then
    select e.instalacion_id, e.codigo, e.activo into v_inst, v_cod, v_act from tecnica.elementos_planta e where e.id = new.reemplaza_id;
    if v_inst is distinct from new.instalacion_id or v_cod is distinct from new.codigo or v_act then
      raise exception 'Solo se reemplaza un elemento ya desactivado, del mismo código y de la misma planta' using errcode = '22023';
    end if;
  end if;
  if not new.activo then
    raise exception 'Un elemento nuevo entra activo' using errcode = '22023';
  end if;
  return new;
end $$;

-- Al actualizar (D9): solo se desactiva, con motivo; la fecha la pone el servidor. Nada más se edita y un elemento inactivo no se reactiva.
create function tecnica.f_elemento_protegido() returns trigger
language plpgsql set search_path to 'pg_catalog', 'pg_temp' as $$
begin
  if new.id is distinct from old.id or new.codigo is distinct from old.codigo or new.instalacion_id is distinct from old.instalacion_id or new.tipo is distinct from old.tipo
     or new.nombre is distinct from old.nombre or new.orden is distinct from old.orden or new.geom::text is distinct from old.geom::text or new.punto_id is distinct from old.punto_id
     or new.desde_id is distinct from old.desde_id or new.hasta_id is distinct from old.hasta_id or new.activo_codigo is distinct from old.activo_codigo
     or new.atributos is distinct from old.atributos or new.origen is distinct from old.origen or new.reemplaza_id is distinct from old.reemplaza_id
     or new.creado_por is distinct from old.creado_por or new.creado_en is distinct from old.creado_en then
    raise exception 'Un elemento de la planta no se edita: desactívelo con motivo y cree la fila nueva' using errcode = '55000';
  end if;
  if old.activo and not new.activo then
    if new.motivo_inactivo is null or length(btrim(new.motivo_inactivo)) < 10 then
      raise exception 'Escriba el motivo para desactivar el elemento (10 a 1.000 caracteres)' using errcode = '22023';
    end if;
    new.inactivado_en := clock_timestamp();
  elsif new.activo is distinct from old.activo or new.motivo_inactivo is distinct from old.motivo_inactivo or new.inactivado_en is distinct from old.inactivado_en then
    raise exception 'Un elemento desactivado no se reactiva ni se cambia: cree la fila nueva' using errcode = '55000';
  end if;
  return new;
end $$;

create trigger t_elemento_coherente before insert on tecnica.elementos_planta for each row execute function tecnica.f_elemento_coherente();
create trigger t_elemento_protegido before update on tecnica.elementos_planta for each row execute function tecnica.f_elemento_protegido();
create trigger t_no_borrar before delete on tecnica.elementos_planta for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on tecnica.elementos_planta for each statement execute function tecnica.f_solo_agregar();
create trigger t_no_borrar before delete on tecnica.instalaciones for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on tecnica.instalaciones for each statement execute function tecnica.f_solo_agregar();

-- ---------------------------------------------------------------------
-- 3. Alias de etiqueta de un elemento (el nombre corto que ve el jefe de planta). Por código, así sigue a la pieza cuando se reemplaza la fila (D9).
--    Solo se agrega: el alias vigente es el último evento; alias nulo = sin alias.
-- ---------------------------------------------------------------------
create table tecnica.elemento_alias_eventos (
  id               bigint generated always as identity primary key,
  instalacion_id   bigint not null references tecnica.instalaciones (id),
  codigo           text not null check (codigo ~ '^[A-Z0-9][A-Z0-9_-]{1,39}$'),
  alias            text check (alias is null or length(btrim(alias)) between 1 and 60),
  motivo           text not null check (length(btrim(motivo)) between 10 and 1000),
  autor            text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en        timestamptz not null default clock_timestamp()
);
create index ix_elemento_alias on tecnica.elemento_alias_eventos (instalacion_id, codigo, id desc);
create trigger t_solo_agregar before update or delete on tecnica.elemento_alias_eventos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.elemento_alias_eventos for each statement execute function tecnica.f_solo_agregar();

-- ---------------------------------------------------------------------
-- 4. Alcance por persona (D6): PTAP y PTAR. Solo se agrega; el vigente es el último evento de (persona, alcance).
--    Sin eventos: PTAP sí (lo de siempre: nadie pierde nada con este paquete) y PTAR no. El administrador tiene los dos siempre.
-- ---------------------------------------------------------------------
create table tecnica.alcance_eventos (
  id           bigint generated always as identity primary key,
  persona      text not null check (persona = lower(persona) and position('@' in persona) > 1),
  alcance      text not null check (alcance in ('ptap', 'ptar')),
  tipo_evento  text not null check (tipo_evento in ('asignar', 'quitar')),
  motivo       text not null check (length(btrim(motivo)) between 10 and 1000),
  autor        text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en    timestamptz not null default clock_timestamp()
);
create index ix_alcance_persona on tecnica.alcance_eventos (persona, alcance, id desc);
create trigger t_solo_agregar before update or delete on tecnica.alcance_eventos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.alcance_eventos for each statement execute function tecnica.f_solo_agregar();
comment on table tecnica.alcance_eventos is 'PTAR-1 (D6): alcance PTAP / PTAR por persona, como eventos (solo inserción). Sin eventos: PTAP sí, PTAR no. El administrador tiene los dos.';

-- RLS activa sin políticas, como el resto de tecnica (el acceso es solo por las RPC)
alter table tecnica.instalaciones enable row level security;
alter table tecnica.elementos_planta enable row level security;
alter table tecnica.elemento_alias_eventos enable row level security;
alter table tecnica.alcance_eventos enable row level security;
-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 20 — FUNCIONES INTERNAS (sin permisos para los roles de la API; las usan las RPC SECURITY DEFINER).
-- =====================================================================

-- ¿La persona tiene el alcance? (D6) El administrador, los dos siempre. Sin eventos: PTAP sí, PTAR no. Si no, el último evento.
create function tecnica.f_tiene_alcance(p_email text, p_alcance text) returns boolean
language sql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
  select case when public.geoportal_es_admin(lower(p_email)) then true
              else coalesce((select e.tipo_evento = 'asignar' from tecnica.alcance_eventos e
                              where e.persona = lower(p_email) and e.alcance = p_alcance order by e.id desc limit 1), p_alcance = 'ptap') end
$$;

-- Puerta del Dashboard PTAP y de todo lo de supervisión de planta (la publicada + una línea, D6): quien solo tiene la PTAR no entra.
-- Mismo nombre y firma: las RPC que ya la llaman (Dashboard PTAP, químicos, puntos, reportes y descargas) no cambian. Para todos los que existen hoy no cambia nada (sin eventos, PTAP = sí).
create or replace function tecnica.f_autorizar_supervision(p_solicitante text) returns text
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if tecnica.f_perfil(v_email) <> 'admin' and not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  if not tecnica.f_tiene_alcance(v_email, 'ptap') then
    raise exception 'Su acceso es a la PTAR, no a las plantas de agua potable' using errcode = '42501';
  end if;
  return v_email;
end $$;

-- Puerta de la PTAR (D6): Dashboard técnico (supervisor o administrador), Técnica activa y el alcance PTAR.
create function tecnica.f_autorizar_ptar(p_solicitante text) returns text
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if tecnica.f_perfil(v_email) <> 'admin' and not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  if not tecnica.f_tiene_alcance(v_email, 'ptar') then
    raise exception 'No tiene el alcance de la PTAR' using errcode = '42501';
  end if;
  return v_email;
end $$;

-- Puerta por instalación: la PTAR pide el alcance PTAR; una PTAP, el de supervisión de planta (alcance PTAP).
create function tecnica.f_autorizar_instalacion(p_solicitante text, p_instalacion_id bigint) returns text
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_tipo text;
begin
  select i.tipo into v_tipo from tecnica.instalaciones i where i.id = p_instalacion_id;
  if v_tipo = 'residual' then return tecnica.f_autorizar_ptar(p_solicitante); end if;
  return tecnica.f_autorizar_supervision(p_solicitante);
end $$;

-- Alias vigente de un elemento (por código; nulo = sin alias).
create function tecnica.f_alias_vigente(p_instalacion_id bigint, p_codigo text) returns text
language sql stable set search_path to 'pg_catalog', 'pg_temp' as $$
  select a.alias from tecnica.elemento_alias_eventos a where a.instalacion_id = p_instalacion_id and a.codigo = p_codigo order by a.id desc limit 1
$$;

create function tecnica.f_tipo_elemento_texto(p_tipo text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case p_tipo when 'perimetro' then 'Perímetro' when 'laguna' then 'Laguna' when 'tramo' then 'Tramo' when 'punto_medicion' then 'Punto de medición'
                     when 'pozo' then 'Pozo' when 'descarga' then 'Descarga' else p_tipo end
$$;

-- Instalación por código (activa); error de usuario si no existe.
create function tecnica.f_instalacion(p_codigo text) returns tecnica.instalaciones
language plpgsql stable set search_path to 'pg_catalog', 'pg_temp' as $$
declare i tecnica.instalaciones;
begin
  select * into i from tecnica.instalaciones x where x.codigo = lower(btrim(coalesce(p_codigo, ''))) and x.activa;
  if not found then perform tecnica.f_error('Esa planta no existe', 'P0002'); end if;
  return i;
end $$;
-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 26 — RPC (public, SECURITY DEFINER, solo service_role; las llama la Edge geoportal-tecnica con el correo del token).
-- Seis RPC nuevas: perfil, mapa, ficha de un elemento, alias, y alcance (lista y fijar, solo el administrador). Ninguna RPC existente cambia de firma.
-- Sin datos personales del suscriptor ni términos tarifarios. Los mensajes para la persona llevan HINT 'msg_usuario' (tecnica.f_error).
-- =====================================================================

-- Lo que ve la persona en Técnica respecto de las plantas (lo usa el inicio para el modo PTAR y el selector de dashboards).
create function public.geoportal_tec_ptar_perfil(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v text := lower(btrim(coalesce(p_solicitante, ''))); v_perfil text; v_activa boolean; v_ptap boolean; v_ptar boolean;
begin
  v_perfil := tecnica.f_perfil(v);
  perform tecnica.f_verificar(p_solicitante, case when v_perfil = 'operador' then 'registro_tecnico' else 'dashboard_tecnico' end);   -- 28000 / 42501 si no hay acceso
  v_activa := v_perfil = 'admin' or tecnica.f_tecnica_activa(v);
  v_ptap := v_perfil in ('admin', 'supervisor') and v_activa and tecnica.f_tiene_alcance(v, 'ptap');
  v_ptar := v_perfil in ('admin', 'supervisor') and v_activa and tecnica.f_tiene_alcance(v, 'ptar');
  return jsonb_build_object('perfil', v_perfil, 'activa', v_activa, 'admin', v_perfil = 'admin', 'ptap', v_ptap, 'ptar', v_ptar,
    'instalaciones', coalesce((select jsonb_agg(jsonb_build_object('codigo', i.codigo, 'nombre', i.nombre, 'tipo', i.tipo,
                                                 'elementos', (select count(*) from tecnica.elementos_planta e where e.instalacion_id = i.id and e.activo)) order by i.tipo desc, i.id)
                                 from tecnica.instalaciones i where i.activa and ((i.tipo = 'residual' and v_ptar) or (i.tipo = 'potable' and v_ptap))), '[]'::jsonb));
end $$;

-- El mapa de una instalación: todos sus elementos activos en un GeoJSON (6 decimales ≈ 0,1 m), en el orden de dibujo
-- (perímetro, lagunas, tramos, pozos y descargas, puntos de medición). Mientras un elemento no tenga variables asignadas, su estado es «sin_variables».
create function public.geoportal_tec_ptar_mapa(p_solicitante text, p_instalacion text default 'ptar') returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare i tecnica.instalaciones; v_fc jsonb; v_caja jsonb; v_tipos jsonb;
begin
  perform tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  i := tecnica.f_instalacion(p_instalacion);
  perform tecnica.f_autorizar_instalacion(p_solicitante, i.id);
  with al as (
    select distinct on (a.codigo) a.codigo, a.alias from tecnica.elemento_alias_eventos a where a.instalacion_id = i.id order by a.codigo, a.id desc
  ), el as (
    select e.*, al.alias, case e.tipo when 'perimetro' then 1 when 'laguna' then 2 when 'tramo' then 3 when 'pozo' then 4 when 'descarga' then 4 else 5 end as capa
      from tecnica.elementos_planta e left join al on al.codigo = e.codigo
     where e.instalacion_id = i.id and e.activo
  )
  select jsonb_build_object('type', 'FeatureCollection', 'features', coalesce(jsonb_agg(jsonb_build_object('type', 'Feature', 'id', el.id,
           'geometry', st_asgeojson(el.geom, 6)::jsonb,
           'properties', jsonb_strip_nulls(jsonb_build_object('codigo', el.codigo, 'tipo', el.tipo, 'nombre', el.nombre, 'alias', el.alias, 'orden', el.orden,
                                                              'activo', el.activo_codigo, 'origen', el.origen, 'tipo_laguna', el.atributos ->> 'tipo_laguna',
                                                              'tren', el.atributos ->> 'tren', 'estado', 'sin_variables')))
           order by el.capa, el.orden, el.codigo), '[]'::jsonb)),
         (select jsonb_build_array(round(st_xmin(x)::numeric, 6), round(st_ymin(x)::numeric, 6), round(st_xmax(x)::numeric, 6), round(st_ymax(x)::numeric, 6))
            from (select st_extent(geom)::geometry as x from el) c where x is not null),
         (select jsonb_object_agg(t, n) from (select tipo as t, count(*) as n from el group by tipo) z)
    into v_fc, v_caja, v_tipos
    from el;
  return jsonb_build_object('instalacion', jsonb_build_object('codigo', i.codigo, 'nombre', i.nombre, 'tipo', i.tipo, 'horas_sin_dato', i.horas_sin_dato),
                            'caja', v_caja, 'por_tipo', coalesce(v_tipos, '{}'::jsonb), 'total', jsonb_array_length(v_fc -> 'features'), 'elementos', v_fc);
end $$;

-- Ficha de un elemento (popup del mapa): nombre, alias, tipo, medida, flujo, activo de redes y atributos. Indicadores: vacíos mientras no tenga variables asignadas.
create function public.geoportal_tec_ptar_elemento(p_solicitante text, p_codigo text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_cod text := upper(btrim(coalesce(p_codigo, ''))); e tecnica.elementos_planta; i tecnica.instalaciones; v_medida jsonb;
begin
  perform tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if v_cod !~ '^[A-Z0-9][A-Z0-9_-]{1,39}$' then perform tecnica.f_error('El código del elemento no es válido'); end if;
  select * into e from tecnica.elementos_planta x where x.codigo = v_cod and x.activo;
  if not found then perform tecnica.f_error('Ese elemento no existe', 'P0002'); end if;
  perform tecnica.f_autorizar_instalacion(p_solicitante, e.instalacion_id);
  select * into i from tecnica.instalaciones x where x.id = e.instalacion_id;
  v_medida := case when e.tipo in ('perimetro', 'laguna') then jsonb_build_object('area_m2', round(st_area(e.geom::geography)::numeric), 'area_ha', round((st_area(e.geom::geography) / 10000)::numeric, 2))
                   when e.tipo = 'tramo' then jsonb_build_object('longitud_m', round(st_length(e.geom::geography)::numeric, 1))
                   else jsonb_build_object('lat', round(st_y(e.geom)::numeric, 6), 'lon', round(st_x(e.geom)::numeric, 6)) end;
  return jsonb_strip_nulls(jsonb_build_object(
    'codigo', e.codigo, 'tipo', e.tipo, 'tipo_texto', tecnica.f_tipo_elemento_texto(e.tipo), 'nombre', e.nombre, 'alias', tecnica.f_alias_vigente(e.instalacion_id, e.codigo),
    'orden', e.orden, 'origen', e.origen, 'activo', e.activo_codigo, 'atributos', e.atributos, 'medida', v_medida,
    'instalacion', jsonb_build_object('codigo', i.codigo, 'nombre', i.nombre, 'tipo', i.tipo),
    'desde', (select jsonb_build_object('codigo', d.codigo, 'nombre', d.nombre) from tecnica.elementos_planta d where d.id = e.desde_id),
    'hasta', (select jsonb_build_object('codigo', h.codigo, 'nombre', h.nombre) from tecnica.elementos_planta h where h.id = e.hasta_id),
    'punto', (select jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre) from tecnica.puntos p where p.id = e.punto_id),
    'versiones', (select count(*) from tecnica.elementos_planta x where x.instalacion_id = e.instalacion_id and x.codigo = e.codigo),
    'alias_historial', coalesce((select jsonb_agg(jsonb_build_object('alias', a.alias, 'motivo', a.motivo, 'autor', a.autor, 'creado_en', a.creado_en) order by a.id desc)
                                   from (select * from tecnica.elemento_alias_eventos a where a.instalacion_id = e.instalacion_id and a.codigo = e.codigo order by a.id desc limit 10) a), '[]'::jsonb),
    'estado', 'sin_variables', 'indicadores', '[]'::jsonb, 'creado_en', e.creado_en));
end $$;

-- Fijar o quitar el alias de un elemento (alias vacío = quitar). Con motivo; solo se agrega un evento.
create function public.geoportal_tec_ptar_alias_fijar(p_solicitante text, p_codigo text, p_alias text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text; v_cod text := upper(btrim(coalesce(p_codigo, ''))); e tecnica.elementos_planta; v_alias text := nullif(btrim(coalesce(p_alias, '')), '');
        v_mot text := btrim(coalesce(p_motivo, '')); v_antes text;
begin
  perform tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if v_cod !~ '^[A-Z0-9][A-Z0-9_-]{1,39}$' then perform tecnica.f_error('El código del elemento no es válido'); end if;
  select * into e from tecnica.elementos_planta x where x.codigo = v_cod and x.activo;
  if not found then perform tecnica.f_error('Ese elemento no existe', 'P0002'); end if;
  v_email := tecnica.f_autorizar_instalacion(p_solicitante, e.instalacion_id);
  if v_alias is not null and (length(v_alias) > 60 or v_alias ~ '[[:cntrl:]]') then perform tecnica.f_error('El alias va de 1 a 60 caracteres, sin saltos de línea'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  v_antes := tecnica.f_alias_vigente(e.instalacion_id, e.codigo);
  if v_antes is not distinct from v_alias then
    perform tecnica.f_error(case when v_alias is null then 'El elemento no tiene alias' else 'El elemento ya tiene ese alias' end);
  end if;
  insert into tecnica.elemento_alias_eventos (instalacion_id, codigo, alias, motivo, autor) values (e.instalacion_id, e.codigo, v_alias, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'tec_ptar_alias', e.codigo, jsonb_build_object('antes', v_antes, 'despues', v_alias), p_ip);
  return jsonb_build_object('codigo', e.codigo, 'antes', v_antes, 'alias', v_alias);
end $$;

-- Alcance PTAP / PTAR de las personas (D6). Solo el administrador.
create function public.geoportal_tec_ptar_alcances(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
begin
  if not public.geoportal_es_admin(v_email) then
    raise exception 'Solo el administrador asigna el alcance PTAP o PTAR' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'personas', coalesce((select jsonb_agg(jsonb_build_object('persona', x.persona, 'perfil', tecnica.f_perfil(x.persona),
                                                              'ptap', tecnica.f_tiene_alcance(x.persona, 'ptap'), 'ptar', tecnica.f_tiene_alcance(x.persona, 'ptar')) order by x.persona)
                            from (select distinct a.persona from tecnica.alcance_eventos a) x), '[]'::jsonb),
    'historial', coalesce((select jsonb_agg(jsonb_build_object('persona', h.persona, 'alcance', h.alcance, 'tipo', h.tipo_evento, 'motivo', h.motivo, 'autor', h.autor, 'creado_en', h.creado_en) order by h.id desc)
                             from (select * from tecnica.alcance_eventos order by id desc limit 50) h), '[]'::jsonb),
    'regla', 'Sin asignación: PTAP sí, PTAR no. El administrador tiene los dos.');
end $$;

create function public.geoportal_tec_ptar_alcance_fijar(p_solicitante text, p_persona text, p_alcance text, p_accion text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico'); v_per text := lower(btrim(coalesce(p_persona, '')));
        v_alc text := lower(btrim(coalesce(p_alcance, ''))); v_acc text := lower(btrim(coalesce(p_accion, ''))); v_mot text := btrim(coalesce(p_motivo, '')); v_perfil text;
begin
  if not public.geoportal_es_admin(v_email) then
    raise exception 'Solo el administrador asigna el alcance PTAP o PTAR' using errcode = '42501';
  end if;
  if v_per !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' then perform tecnica.f_error('El correo de la persona no es válido'); end if;
  if v_alc not in ('ptap', 'ptar') then perform tecnica.f_error('El alcance es PTAP o PTAR'); end if;
  if v_acc not in ('asignar', 'quitar') then perform tecnica.f_error('La acción es asignar o quitar'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  v_perfil := tecnica.f_perfil(v_per);
  if v_perfil is null then perform tecnica.f_error('Esa persona no tiene acceso a Técnica'); end if;
  if v_perfil = 'admin' then perform tecnica.f_error('El administrador tiene los dos alcances siempre'); end if;
  if tecnica.f_tiene_alcance(v_per, v_alc) = (v_acc = 'asignar') then
    perform tecnica.f_error(case when v_acc = 'asignar' then 'Esa persona ya tiene ese alcance' else 'Esa persona no tiene ese alcance' end);
  end if;
  insert into tecnica.alcance_eventos (persona, alcance, tipo_evento, motivo, autor) values (v_per, v_alc, v_acc, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'tec_ptar_alcance', v_per, jsonb_build_object('alcance', v_alc, 'accion', v_acc), p_ip);
  return jsonb_build_object('persona', v_per, 'perfil', v_perfil, 'ptap', tecnica.f_tiene_alcance(v_per, 'ptap'), 'ptar', tecnica.f_tiene_alcance(v_per, 'ptar'));
end $$;
-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 40 — PERMISOS. Todo objeto nuevo: revoke all a public, anon, authenticated y service_role; luego solo lo necesario.
-- Tablas: sin privilegios para ningún rol de la API (RLS activa sin políticas). Funciones internas: sin EXECUTE para nadie de la API.
-- RPC: EXECUTE solo service_role (la Edge). f_autorizar_supervision se reemplazó con CREATE OR REPLACE: conserva sus privilegios.
-- =====================================================================
revoke all on table tecnica.instalaciones, tecnica.elementos_planta, tecnica.elemento_alias_eventos, tecnica.alcance_eventos from public, anon, authenticated, service_role;

revoke all on function tecnica.f_elemento_coherente(), tecnica.f_elemento_protegido(), tecnica.f_tiene_alcance(text, text), tecnica.f_autorizar_ptar(text),
  tecnica.f_autorizar_instalacion(text, bigint), tecnica.f_alias_vigente(bigint, text), tecnica.f_tipo_elemento_texto(text), tecnica.f_instalacion(text)
  from public, anon, authenticated, service_role;

revoke all on function public.geoportal_tec_ptar_perfil(text), public.geoportal_tec_ptar_mapa(text, text), public.geoportal_tec_ptar_elemento(text, text),
  public.geoportal_tec_ptar_alias_fijar(text, text, text, text, text), public.geoportal_tec_ptar_alcances(text),
  public.geoportal_tec_ptar_alcance_fijar(text, text, text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_tec_ptar_perfil(text), public.geoportal_tec_ptar_mapa(text, text), public.geoportal_tec_ptar_elemento(text, text),
  public.geoportal_tec_ptar_alias_fijar(text, text, text, text, text), public.geoportal_tec_ptar_alcances(text),
  public.geoportal_tec_ptar_alcance_fijar(text, text, text, text, text, text)
  to service_role;
commit;
