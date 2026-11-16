begin;
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
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 25 — REEMPLAZO (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- es el texto del 5a con un cambio exacto, aplicado una sola vez:
--   · redes.f_candidatos_muestreo (capa MUE): una ubicación verificada no la pisa un archivo que la trae aproximada («conserva_verificada»).
-- =====================================================================

-- redes.f_candidatos_muestreo(bigint)
CREATE OR REPLACE FUNCTION redes.f_candidatos_muestreo(p_carga bigint)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'tecnica', 'public', 'extensions', 'pg_temp'
AS $function$
begin
  if to_regclass('pg_temp._mue') is not null then drop table pg_temp._mue; end if;
  create temp table _mue on commit drop as
  select cf.orden, upper(nullif(btrim(cf.llave), '')) as codigo, nullif(btrim(cf.atributos ->> 'nombre'), '') as nombre,
         lower(nullif(btrim(cf.atributos ->> 'zona'), '')) as zona, nullif(btrim(cf.atributos ->> 'barrio'), '') as barrio,
         lower(coalesce(nullif(btrim(cf.atributos ->> 'exactitud'), ''), nullif(btrim(cf.atributos ->> 'precision'), ''), 'aproximada')) as exactitud,
         lower(coalesce(nullif(btrim(cf.atributos ->> 'fuente'), ''), 'carga')) as fuente,
         case when cf.geom is not null and ST_GeometryType(cf.geom) = 'ST_Point' then round(ST_Y(cf.geom)::numeric, 6) end as lat,
         case when cf.geom is not null and ST_GeometryType(cf.geom) = 'ST_Point' then round(ST_X(cf.geom)::numeric, 6) end as lon,
         coalesce(cf.error, case when ST_GeometryType(cf.geom) <> 'ST_Point' then 'No es un punto' end) as error,
         p.id as punto_id, p.tipo as tipo_vigente, p.activo as activo_vigente, p.nombre as nombre_vigente,
         u.lat as lat_vigente, u.lon as lon_vigente, u.exactitud as exactitud_vigente, null::text as accion, null::text as codigo_nuevo
    from redes.carga_filas cf
    left join tecnica.puntos p on p.codigo = upper(nullif(btrim(cf.llave), ''))
    left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
   where cf.carga_id = p_carga;
  update _mue set accion = case when codigo is null then 'nuevo_sin_codigo'
                                when punto_id is null then 'nuevo'
                                when not activo_vigente then 'reactivar'
                                when lat_vigente is distinct from lat or lon_vigente is distinct from lon or exactitud_vigente is distinct from exactitud then 'ubicacion'
                                else 'igual' end;
  -- Corte 5b: una ubicación verificada (David o el GPS del operador aprobado en el Dashboard PTAP) no la pisa un archivo que la trae aproximada:
  -- se conserva la vigente («conserva_verificada» en el resumen). Un archivo con la ubicación verificada sí la cambia (es una corrección explícita).
  update _mue set lat = lat_vigente, lon = lon_vigente, exactitud = 'verificada',
                  accion = case when accion = 'ubicacion' then 'conserva_verificada' else accion end
   where exactitud_vigente = 'verificada' and exactitud = 'aproximada' and lat is not null and error is null;
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 26 — RPC NUEVAS DE PLANTA (las llama la Edge geoportal-tecnica en rutas nuevas)
-- PROPUESTA. No se ha ejecutado en la base real. security definer, search_path fijo, mensajes con HINT msg_usuario (tecnica.f_error); solo service_role.
--   · geoportal_tec_puntos_mapa: los puntos de muestreo activos con su ubicación vigente, para el minimapa de Muestreo (quien captura Muestreo).
--   · geoportal_tec_punto_ubicacion_proponer: «Guardar la ubicación de este punto» con el GPS (quien captura Muestreo). Queda pendiente.
--   · geoportal_tec_punto_ubicaciones: lo que revisa el supervisor en el Dashboard PTAP (pendientes, puntos y revisadas).
--   · geoportal_tec_punto_ubicacion_revisar: aprobar (agrega la ubicación verificada) o rechazar (con motivo). Nadie revisa lo que propuso.
-- Nada se actualiza ni se borra: todo es inserción con autor y hora.
-- =====================================================================

-- Minimapa de Muestreo. GeoJSON (FeatureCollection) de los puntos de muestreo ACTIVOS que tienen ubicación vigente; los que no la tienen van en «sin_ubicacion».
-- No trae autores ni nombres de personas: solo si hay una propuesta en revisión y si es de quien pregunta.
create function public.geoportal_tec_puntos_mapa(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'muestreo');
begin
  return jsonb_build_object(
    'type', 'FeatureCollection',
    'precision_max_m', redes.f_param('mue_gps_precision_max_m'),
    'features', coalesce((
      select jsonb_agg(jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(u.lon, u.lat)),
               'properties', jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'exactitud', u.exactitud, 'fuente', u.fuente,
                                                'en_revision', pr.id is not null, 'propuesta_mia', coalesce(pr.autor = v_email, false)))
             order by p.codigo)
        from tecnica.puntos p
        join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
        left join lateral (select x.id, x.autor from tecnica.v_punto_propuestas x where x.punto_id = p.id and x.estado = 'pendiente' order by x.id desc limit 1) pr on true
       where p.tipo = 'muestreo' and p.activo), '[]'::jsonb),
    'sin_ubicacion', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre,
                                          'en_revision', exists (select 1 from tecnica.v_punto_propuestas x where x.punto_id = p.id and x.estado = 'pendiente')) order by p.codigo)
        from tecnica.puntos p where p.tipo = 'muestreo' and p.activo and not exists (select 1 from redes.v_punto_ubicacion_vigente u where u.punto_id = p.id)), '[]'::jsonb));
end $f$;

-- «Guardar la ubicación de este punto». La propone quien captura Muestreo, parado en el punto, con el GPS del celular. Reglas:
--   · el punto existe, es de muestreo y está activo; su ubicación vigente NO está verificada (si lo está, se corrige desde el Dashboard o por archivo);
--   · la precisión del GPS es de mue_gps_precision_max_m metros o menos, y la posición cae en la caja de Valledupar (la misma del cargue de capas);
--   · una sola propuesta pendiente por punto: si la pendiente es de la misma persona, se devuelve esa (doble toque o reintento); si es de otra, se rechaza.
create function public.geoportal_tec_punto_ubicacion_proponer(p_solicitante text, p_punto text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_captura(p_solicitante, 'muestreo');
  p tecnica.puntos%rowtype; u record; pr record; v_max numeric := redes.f_param('mue_gps_precision_max_m'); v_id bigint; v_dist numeric;
  v_lat numeric := round(p_lat, 6); v_lon numeric := round(p_lon, 6);
begin
  if p_lat is null or p_lon is null or p_precision_m is null then perform tecnica.f_error('Falta la ubicación del GPS. Espere a que el celular la encuentre.'); end if;
  select * into p from tecnica.puntos where codigo = upper(btrim(coalesce(p_punto, ''))) and tipo = 'muestreo';
  if not found then perform tecnica.f_error('No existe ese punto de muestreo', 'P0002'); end if;
  if not p.activo then perform tecnica.f_error('Ese punto de muestreo está desactivado'); end if;
  if p_precision_m <= 0 or p_precision_m > 1000 then perform tecnica.f_error('La precisión del GPS no es válida'); end if;
  if p_precision_m > v_max then
    perform tecnica.f_error(format('El GPS tiene una precisión de %s m y se necesita de %s m o menos. Espere unos segundos junto al punto, a cielo abierto, y vuelva a intentarlo.',
                                   ceil(p_precision_m)::integer, v_max::integer));
  end if;
  if v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
    perform tecnica.f_error('La ubicación del GPS está fuera de Valledupar. Revise el GPS del celular.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('tecnica.punto_ubicacion|' || p.id, 0));
  select * into u from redes.v_punto_ubicacion_vigente where punto_id = p.id;
  if found and u.exactitud = 'verificada' then
    perform tecnica.f_error('La ubicación de este punto ya está verificada. Si está mal, avise a su supervisor.', '55000');
  end if;
  select * into pr from tecnica.v_punto_propuestas where punto_id = p.id and estado = 'pendiente' order by id desc limit 1;
  if found then
    if pr.autor = v_email then
      return jsonb_build_object('propuesta_id', pr.id, 'punto', p.codigo, 'estado', 'pendiente', 'duplicado', true, 'lat', pr.lat, 'lon', pr.lon, 'precision_m', pr.precision_m);
    end if;
    perform tecnica.f_error('Ya hay una ubicación de este punto en revisión del supervisor.', '55000');
  end if;
  insert into tecnica.punto_ubicacion_propuestas (punto_id, lat, lon, precision_m, ubicacion_previa_id, autor)
  values (p.id, v_lat, v_lon, round(p_precision_m, 1), u.id, v_email) returning id into v_id;
  if u.id is not null then
    v_dist := round(ST_Distance(ST_SetSRID(ST_MakePoint(v_lon::double precision, v_lat::double precision), 4326)::geography, u.geom::geography)::numeric);
  end if;
  perform tecnica.f_auditar(v_email, 'tec_punto_ubicacion_proponer', p.codigo, jsonb_build_object('propuesta_id', v_id, 'precision_m', round(p_precision_m, 1), 'distancia_m', v_dist), p_ip);
  return jsonb_build_object('propuesta_id', v_id, 'punto', p.codigo, 'estado', 'pendiente', 'duplicado', false, 'lat', v_lat, 'lon', v_lon, 'precision_m', round(p_precision_m, 1),
                            'distancia_m', v_dist);
end $f$;

-- Lo que revisa el supervisor (Dashboard PTAP, pestaña «Puntos»): las propuestas pendientes con la distancia a la ubicación vigente, todos los puntos de
-- muestreo activos con su ubicación y las 50 últimas revisiones. El correo de quien propuso y de quien revisó es dato de supervisión (como el autor de un registro).
create function public.geoportal_tec_punto_ubicaciones(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_aviso numeric := redes.f_param('mue_gps_distancia_aviso_m');
begin
  return jsonb_build_object(
    'precision_max_m', redes.f_param('mue_gps_precision_max_m'), 'distancia_aviso_m', v_aviso,
    'pendientes', coalesce((
      select jsonb_agg(jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'activo', p.activo,
               'lat', x.lat, 'lon', x.lon, 'precision_m', x.precision_m, 'autor', x.autor, 'autor_nombre', lb.nombre, 'creado_en', x.creado_en, 'propia', x.autor = v_email,
               'vigente', case when u.punto_id is not null then jsonb_build_object('lat', u.lat, 'lon', u.lon, 'exactitud', u.exactitud, 'fuente', u.fuente) end,
               'distancia_m', d.m, 'lejos', coalesce(d.m > v_aviso, false)) order by x.id)
        from tecnica.v_punto_propuestas x join tecnica.puntos p on p.id = x.punto_id
        left join redes.v_punto_ubicacion_vigente u on u.punto_id = x.punto_id
        left join public.geoportal_lista_blanca lb on lb.email = x.autor
        cross join lateral (select round(ST_Distance(x.geom::geography, u.geom::geography)::numeric) as m) d
       where x.estado = 'pendiente'), '[]'::jsonb),
    'puntos', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'lat', u.lat, 'lon', u.lon, 'exactitud', u.exactitud, 'fuente', u.fuente,
               'desde', u.creado_en, 'en_revision', exists (select 1 from tecnica.v_punto_propuestas x where x.punto_id = p.id and x.estado = 'pendiente')) order by p.codigo)
        from tecnica.puntos p left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
       where p.tipo = 'muestreo' and p.activo), '[]'::jsonb),
    'revisadas', coalesce((
      select jsonb_agg(r order by (r ->> 'revisada_en') desc) from (
        select jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'nombre', p.nombre, 'decision', x.estado, 'motivo', x.revision_motivo,
                                  'autor', x.autor, 'revisor', x.revisor, 'revisada_en', x.revisada_en, 'precision_m', x.precision_m) as r
          from tecnica.v_punto_propuestas x join tecnica.puntos p on p.id = x.punto_id
         where x.estado <> 'pendiente' order by x.revisada_en desc limit 50) z), '[]'::jsonb));
end $f$;

-- Aprobar o rechazar una ubicación propuesta. Al aprobar se AGREGA la ubicación a tecnica.puntos_ubicacion (verificada, fuente gps_operador; el autor
-- es quien la tomó) y queda como la vigente. El rechazo pide motivo (10 caracteres o más). Nadie revisa una ubicación que propuso (como en Personal).
create function public.geoportal_tec_punto_ubicacion_revisar(p_solicitante text, p_propuesta_id bigint, p_decision text, p_motivo text, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_supervision(p_solicitante); x record; p tecnica.puntos%rowtype; u record;
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), ''); v_ubic bigint; v_rev bigint;
begin
  if p_decision is null or p_decision not in ('aprobar', 'rechazar') then perform tecnica.f_error('Diga si aprueba o rechaza la ubicación'); end if;
  if p_decision = 'rechazar' and (v_mot is null or length(v_mot) < 10) then perform tecnica.f_error('Escriba el motivo del rechazo (10 caracteres o más)'); end if;
  if v_mot is not null and (length(v_mot) < 10 or length(v_mot) > 1000) then perform tecnica.f_error('El motivo, si lo escribe, va de 10 a 1.000 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('tecnica.puntos'));          -- el mismo candado que la publicación de la capa MUE (Corte 5a)
  select * into x from tecnica.v_punto_propuestas where id = p_propuesta_id;
  if not found then perform tecnica.f_error('No existe esa ubicación propuesta', 'P0002'); end if;
  if x.estado <> 'pendiente' then perform tecnica.f_error(format('Esta ubicación ya fue %s por %s', x.estado, x.revisor), '55000'); end if;
  if x.autor = v_email then perform tecnica.f_error('No puede revisar una ubicación que usted mismo tomó: pídaselo a otro supervisor o al administrador'); end if;
  select * into p from tecnica.puntos where id = x.punto_id;
  if p_decision = 'aprobar' then
    if not p.activo then perform tecnica.f_error('El punto está desactivado: no se puede aprobar su ubicación (puede rechazarla)'); end if;
    select * into u from redes.v_punto_ubicacion_vigente where punto_id = p.id;
    insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, barrio_capa, carga_id, autor)
    values (p.id, x.lat, x.lon, 'verificada', 'gps_operador', u.barrio_capa, null, x.autor) returning id into v_ubic;
  end if;
  insert into tecnica.punto_ubicacion_revisiones (propuesta_id, decision, motivo, ubicacion_id, autor)
  values (x.id, p_decision, v_mot, v_ubic, v_email) returning id into v_rev;
  perform tecnica.f_auditar(v_email, 'tec_punto_ubicacion_' || p_decision, p.codigo, jsonb_build_object('propuesta_id', x.id, 'propuso', x.autor, 'motivo', v_mot, 'ubicacion_id', v_ubic), p_ip);
  return jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'decision', p_decision, 'estado', case when p_decision = 'aprobar' then 'aprobada' else 'rechazada' end,
                            'ubicacion_id', v_ubic, 'revision_id', v_rev);
end $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vista nuevas: nadie de la API. Las 4 RPC nuevas: solo execute a service_role (la Edge geoportal-tecnica).
-- La función interna reemplazada (redes.f_candidatos_muestreo) sigue sin permisos para la API.
-- =====================================================================
revoke all on table tecnica.punto_ubicacion_propuestas, tecnica.punto_ubicacion_revisiones, tecnica.v_punto_propuestas from public, anon, authenticated, service_role;
revoke all on sequence tecnica.punto_ubicacion_propuestas_id_seq, tecnica.punto_ubicacion_revisiones_id_seq from public, anon, authenticated, service_role;
revoke all on function redes.f_candidatos_muestreo(bigint) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_punto%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte5b', 'migracion_redes_corte5b', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.punto_ubicacion_propuestas', 'tecnica.punto_ubicacion_revisiones'),
        'rpc', jsonb_build_array('geoportal_tec_puntos_mapa', 'geoportal_tec_punto_ubicacion_proponer', 'geoportal_tec_punto_ubicaciones', 'geoportal_tec_punto_ubicacion_revisar')), null);
commit;
