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
  if v_redes is distinct from '{{MD5_REDES}}' then
    raise exception 'GUARDIA PTAR-1: la huella de redes es % y se esperaba {{MD5_REDES}} (corte de eventos publicado). Deténgase y avise', v_redes;
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v_tec from pg_proc p
   where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'));
  if v_tec is distinct from '{{MD5_TECNICA}}' then
    raise exception 'GUARDIA PTAR-1: la huella de técnica es % y se esperaba {{MD5_TECNICA}}. Deténgase y avise', v_tec;
  end if;
  select md5(pg_get_functiondef('tecnica.f_autorizar_supervision(text)'::regprocedure)) into v_sup;
  if v_sup is distinct from '{{MD5_AUT_SUP}}' then
    raise exception 'GUARDIA PTAR-1: tecnica.f_autorizar_supervision no es la publicada (md5 %, se esperaba {{MD5_AUT_SUP}}). Deténgase y avise', v_sup;
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
