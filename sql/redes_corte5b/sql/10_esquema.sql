-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 10 — GUARDIA Y TABLAS NUEVAS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: plan 02 (Corte 5b), 01 sección E e I, §4 de hallazgos_capas_redes_15nov.md («Guardar la ubicación de este punto») y lo pospuesto del 5a.
-- · Presupone el 5a aplicado (huella del conjunto de funciones de redes y sus tablas tecnica.puntos_ubicacion y tecnica.punto_eventos).
-- · ⚠ tecnica.puntos está VIVA: este corte no la altera ni le agrega filas. La ubicación aprobada se AGREGA a tecnica.puntos_ubicacion (solo inserción).
-- · ⚠ Se reemplaza 1 función interna del 5a (redes.f_candidatos_muestreo), con su texto exacto en la reversa.
-- · Las 4 RPC nuevas son de planta (public.geoportal_tec_punto*): las llama la Edge geoportal-tecnica en rutas NUEVAS; las de siempre no cambian.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.puntos_ubicacion') is null or to_regclass('tecnica.punto_eventos') is null or to_regclass('redes.v_punto_ubicacion_vigente') is null then
    raise exception 'Falta el Corte 5a: aplíquelo antes';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '5d104bb916ca0b055659c1b14902f519' then
    raise exception 'Las funciones de redes no son las del Corte 5a (o el Corte 5b ya está aplicado): deténgase y avise';
  end if;
  if to_regclass('tecnica.punto_ubicacion_propuestas') is not null or to_regclass('tecnica.punto_ubicacion_revisiones') is not null
     or exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_punto%') then
    raise exception 'Las tablas o las RPC del 5b ya existen: el Corte 5b parece aplicado';
  end if;
  -- lo vivo de planta que se usa, con la forma esperada
  if to_regprocedure('tecnica.f_autorizar_captura(text,text)') is null or to_regprocedure('tecnica.f_autorizar_supervision(text)') is null
     or to_regprocedure('tecnica.f_error(text,text)') is null or to_regprocedure('tecnica.f_auditar(text,text,text,jsonb,text)') is null then
    raise exception 'Faltan las puertas de planta (f_autorizar_captura, f_autorizar_supervision, f_error o f_auditar): deténgase y avise';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'tecnica.puntos_ubicacion'::regclass and tgname = 't_solo_agregar' and not tgisinternal) then
    raise exception 'tecnica.puntos_ubicacion no tiene su candado de solo inserción: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. «GUARDAR LA UBICACIÓN DE ESTE PUNTO» (§4 de los hallazgos): el operador propone con el GPS del celular; el supervisor aprueba o rechaza en el
--    Dashboard PTAP. Solo inserción. La propuesta aprobada AGREGA una fila a tecnica.puntos_ubicacion (exactitud verificada, fuente gps_operador).
-- ---------------------------------------------------------------------
create table tecnica.punto_ubicacion_propuestas (
  id            bigint generated always as identity primary key,
  punto_id      bigint not null references tecnica.puntos (id),
  lat           numeric(9, 6) not null check (lat between -90 and 90),
  lon           numeric(9, 6) not null check (lon between -180 and 180),
  geom          geometry(Point, 4326) generated always as (ST_SetSRID(ST_MakePoint(lon::double precision, lat::double precision), 4326)) stored,
  precision_m   numeric(6, 1) not null check (precision_m > 0 and precision_m <= 1000),
  ubicacion_previa_id bigint references tecnica.puntos_ubicacion (id),      -- la vigente cuando se propuso (nula si no tenía)
  autor         text not null,
  creado_en     timestamptz not null default clock_timestamp()
);
create index ix_pup_punto on tecnica.punto_ubicacion_propuestas (punto_id, id desc);
comment on table tecnica.punto_ubicacion_propuestas is 'Ubicación de un punto de muestreo tomada con el GPS del operador en el formulario de Muestreo (Corte 5b). Solo inserción. Queda pendiente hasta que el supervisor la revise.';

create table tecnica.punto_ubicacion_revisiones (
  id           bigint generated always as identity primary key,
  propuesta_id bigint not null unique references tecnica.punto_ubicacion_propuestas (id),
  decision     text not null check (decision in ('aprobar', 'rechazar')),
  motivo       text check (motivo is null or length(btrim(motivo)) between 10 and 1000),
  ubicacion_id bigint references tecnica.puntos_ubicacion (id),
  autor        text not null,
  creado_en    timestamptz not null default clock_timestamp(),
  constraint pur_aprobada_con_ubicacion check ((decision = 'aprobar') = (ubicacion_id is not null)),
  constraint pur_rechazo_con_motivo check (decision = 'aprobar' or motivo is not null)
);
comment on table tecnica.punto_ubicacion_revisiones is 'Decisión del supervisor sobre una ubicación propuesta (una sola por propuesta). Solo inserción. Al aprobar, ubicacion_id es la fila que se agregó a tecnica.puntos_ubicacion.';
do $$
declare t text;
begin
  foreach t in array array['punto_ubicacion_propuestas', 'punto_ubicacion_revisiones'] loop
    execute format('create trigger t_solo_agregar before update or delete on tecnica.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on tecnica.%I for each statement execute function tecnica.f_solo_agregar()', t);
    execute format('alter table tecnica.%I enable row level security', t);
  end loop;
end $$;

-- Estado de cada propuesta: pendiente, aprobada o rechazada.
create view tecnica.v_punto_propuestas as
select pr.id, pr.punto_id, pr.lat, pr.lon, pr.geom, pr.precision_m, pr.ubicacion_previa_id, pr.autor, pr.creado_en,
       case when rv.id is null then 'pendiente' when rv.decision = 'aprobar' then 'aprobada' else 'rechazada' end as estado,
       rv.id as revision_id, rv.motivo as revision_motivo, rv.autor as revisor, rv.creado_en as revisada_en, rv.ubicacion_id
  from tecnica.punto_ubicacion_propuestas pr
  left join tecnica.punto_ubicacion_revisiones rv on rv.propuesta_id = pr.id;

-- ---------------------------------------------------------------------
-- 2. PARÁMETROS (los edita el administrador en Parámetros del Dashboard distribución, con su historial)
-- ---------------------------------------------------------------------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('mue_gps_precision_max_m', 30, 'm', 5, 100, 'Precisión del GPS (radio en metros) que se exige para proponer la ubicación de un punto de muestreo desde el formulario de Muestreo (Corte 5b)'),
  ('mue_gps_distancia_aviso_m', 300, 'm', 20, 5000, 'Distancia a la ubicación vigente desde la que el Dashboard PTAP avisa «lejos» al revisar una ubicación propuesta (Corte 5b)')
on conflict (clave) do nothing;      -- una reversa los deja (los parámetros no se borran)
