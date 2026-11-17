begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 10 — GUARDIA Y ESQUEMA («Encontrar o reportar activo» y los puntos por levantar)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code B). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte14_encontrar_reportar_activo.md (17-nov) y el plan de David del 17-nov (14:05–14:48): todo el corte lo hace Code B, por etapas.
-- · Presupone el Corte 9b publicado completo (huella del conjunto de funciones de redes a327aa51f43bb5cc2112a6db089718ed).
-- · Los puntos por levantar son HECHOS de solo inserción (punto, fotos y eventos). El estado vigente es su último evento: reportado → asignado a
--   levantamiento → levantado (con el activo nuevo) | descartado con motivo. Nada se borra; «reabrir» es otro evento.
-- · El formulario «Encontrar o reportar activo» (clave activo_campo) se asigna en Personal de distribución (como los demás) y queda en la lista de
--   Personal de Comercial (allá la asignación solo se registra, como todas las de Comercial).
-- · ⚠ Fuera de redes se tocan tres cosas, las tres con guardia: el dominio tecnica.formulario_clave (una clave más), el CHECK de campo.personal_eventos
--   (una clave más) y campo.f_formularios_personal (una fila más). Ninguna cambia lo que ya existe.
-- · Sin datos de suscriptores. La posición y la precisión del GPS son las del funcionario al reportar.
-- =====================================================================
do $$
begin
  if to_regclass('redes.levantar_puntos') is not null then raise exception 'El Corte 14 ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'a327aa51f43bb5cc2112a6db089718ed' then
    raise exception 'Las funciones de redes no son las del Corte 9b publicado completo (huella a327aa51f43bb5cc2112a6db089718ed): deténgase y avise';
  end if;
  if to_regclass('redes.formularios_distribucion') is null or to_regclass('redes.consecutivos') is null or to_regclass('tecnica.personal_tecnico_eventos') is null then
    raise exception 'Faltan tablas de los cortes anteriores (5a): deténgase y avise';
  end if;
  -- 9 claves (Corte 8) o, si hubo una reversa del 14, las 10 (la reversa no puede quitar la clave: el formulario queda desactivado, no borrado)
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck')
     not in ('CHECK ((VALUE = ANY (ARRAY[''entrada''::text, ''salida''::text, ''muestreo''::text, ''danos_fallas''::text, ''mantenimiento''::text, ''uso_quimicos''::text, ''entrada_quimicos''::text, ''anomalia_compartida''::text, ''revision_compartida''::text])))', 'CHECK ((VALUE = ANY (ARRAY[''entrada''::text, ''salida''::text, ''muestreo''::text, ''danos_fallas''::text, ''mantenimiento''::text, ''uso_quimicos''::text, ''entrada_quimicos''::text, ''anomalia_compartida''::text, ''revision_compartida''::text, ''activo_campo''::text])))') then
    raise exception 'El dominio tecnica.formulario_clave no tiene las 9 claves esperadas (Corte 8): deténgase y avise';
  end if;
  if to_regprocedure('campo.f_formularios_personal()') is null or md5(pg_get_functiondef('campo.f_formularios_personal()'::regprocedure)) <> '51b26c1209ae8403560888ca29902fb5' then
    raise exception 'campo.f_formularios_personal no es la de la pasada del 14-nov (huella 51b26c1209ae8403560888ca29902fb5): deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamptz)'::regprocedure)) <> '2a7989bead5fd35d3a4d0c4e45bcb92b' then
    raise exception 'tecnica.f_avisos no es la de la Fase 2 del 9b (huella 2a7989bead5fd35d3a4d0c4e45bcb92b): deténgase y avise';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_eventos_formulario_check') is distinct from 'CHECK (((formulario IS NULL) OR (formulario ~ ''^(reporte_general|acta|tipo:[a-z][a-z0-9_]{1,59})$''::text)))' then
    raise exception 'El CHECK de campo.personal_eventos.formulario no es el esperado (pasada del 14-nov): deténgase y avise';
  end if;
end $$;

-- ---------- 1. El punto por levantar (hecho de solo inserción) ----------
create table redes.levantar_puntos (
  id             uuid primary key,
  codigo         text not null unique check (codigo ~ '^LEV-[0-9]{6}$'),
  servicio       text not null check (servicio in ('acueducto', 'alcantarillado')),
  tipo           text not null check (tipo in ('tuberia', 'valvula', 'hidrante', 'pozo', 'caja', 'otro')),
  observacion    text check (observacion is null or length(btrim(observacion)) between 3 and 500),
  lat            numeric(9, 6) not null,
  lon            numeric(9, 6) not null,
  geom           geometry(Point, 4326) not null,
  precision_m    numeric(7, 1) not null check (precision_m > 0 and precision_m <= 5000),      -- la precisión del GPS del celular al reportar
  precision_baja boolean not null,                                                             -- pasó del tope (parámetro levantar_radio_max_m) y se envió igual
  area           text not null check (area in ('tecnica', 'comercial')),                       -- desde dónde se reportó
  autor          text not null check (autor = lower(autor) and position('@' in autor) > 1),
  registrado_en  timestamptz not null default clock_timestamp(),
  check (tipo <> 'otro' or observacion is not null)                                             -- «otro» dice qué es
);
comment on table redes.levantar_puntos is 'Corte 14: activo encontrado en la calle que no está en la red («No está en la lista»). Hecho de solo inserción; su estado sale de redes.levantar_eventos.';
create index ix_levantar_puntos_geom on redes.levantar_puntos using gist (geom);
create index ix_levantar_puntos_fecha on redes.levantar_puntos (registrado_en desc);

create table redes.levantar_preparaciones (
  punto_id  uuid primary key,
  autor     text not null check (autor = lower(autor) and position('@' in autor) > 1),
  fotos     smallint not null check (fotos between 1 and 3),
  creado_en timestamptz not null default clock_timestamp()
);
comment on table redes.levantar_preparaciones is 'Corte 14: subida preparada de las fotos de un punto por levantar (como redes.dano_preparaciones).';

create table redes.levantar_fotos (
  punto_id     uuid not null references redes.levantar_puntos (id),
  n            smallint not null check (n between 1 and 3),      -- 1 obligatoria y 2 opcionales
  ruta_storage text not null unique check (ruta_storage ~ '^levantar/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}/[1-3]\.jpg$'),
  bytes        integer not null check (bytes > 0),
  mime         text not null check (mime = 'image/jpeg'),
  creado_en    timestamptz not null default clock_timestamp(),
  primary key (punto_id, n)
);
comment on table redes.levantar_fotos is 'Corte 14: fotos del punto por levantar (cámara de campo, con sello de hora y GPS). Bucket privado redes-evidencias.';

create table redes.levantar_eventos (
  id        bigint generated always as identity primary key,
  punto_id  uuid not null references redes.levantar_puntos (id),
  tipo      text not null check (tipo in ('asignado', 'levantado', 'descartado', 'reabierto')),
  activo_id bigint references redes.activos (id),      -- el activo nuevo con el que quedó levantado
  motivo    text check (motivo is null or length(btrim(motivo)) between 3 and 500),
  autor     text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp(),
  check ((tipo = 'levantado') = (activo_id is not null)),
  check (tipo not in ('descartado', 'reabierto') or motivo is not null)
);
comment on table redes.levantar_eventos is 'Corte 14: eventos de un punto por levantar, de solo agregar. Estado vigente = el último (sin eventos o «reabierto» = reportado). El «posiblemente levantado» no se guarda: se calcula al leer la bandeja (un activo NUEVO a pocos metros) y lo confirma el supervisor.';
create index ix_levantar_eventos_punto on redes.levantar_eventos (punto_id, id desc);

do $$
declare t text;
begin
  foreach t in array array['levantar_puntos', 'levantar_preparaciones', 'levantar_fotos', 'levantar_eventos'] loop
    execute format('alter table redes.%I enable row level security', t);
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', t);
  end loop;
end $$;
revoke all on sequence redes.levantar_eventos_id_seq from public, anon, authenticated, service_role;

-- El punto con su estado vigente (la leen solo las funciones SECURITY DEFINER)
create view redes.v_levantar_punto as
select p.id, p.codigo, p.servicio, p.tipo, p.observacion, p.lat, p.lon, p.geom, p.precision_m, p.precision_baja, p.area, p.autor, p.registrado_en,
       case when u.tipo is null or u.tipo = 'reabierto' then 'reportado' else u.tipo end as estado,
       coalesce(u.creado_en, p.registrado_en) as estado_desde, u.autor as estado_autor, u.motivo as estado_motivo,
       case when u.tipo = 'levantado' then u.activo_id end as activo_id,
       (select count(*) from redes.levantar_fotos f where f.punto_id = p.id)::integer as fotos
  from redes.levantar_puntos p
  left join lateral (select e.tipo, e.creado_en, e.autor, e.motivo, e.activo_id from redes.levantar_eventos e
                      where e.punto_id = p.id order by e.id desc limit 1) u on true;
revoke all on table redes.v_levantar_punto from public, anon, authenticated, service_role;

-- ---------- 2. Consecutivo, parámetros y el formulario asignable ----------
insert into redes.consecutivos (prefijo, ultimo) values ('LEV', 0) on conflict (prefijo) do nothing;
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('levantar_radio_min_m', 15, 'm', 5, 50, 'Encontrar o reportar activo (Corte 14): radio mínimo de búsqueda alrededor de la persona. El radio es el mayor entre este y la precisión del GPS'),
  ('levantar_radio_max_m', 30, 'm', 10, 100, 'Encontrar o reportar activo (Corte 14): tope del radio de búsqueda y de la precisión del GPS. Con peor precisión la pantalla avisa «señal débil» y el punto queda «precisión baja»'),
  ('levantar_duplicado_m', 10, 'm', 1, 50, 'Reportar activo (Corte 14): si ya hay un punto por levantar a menos de esta distancia, se muestra antes de crear otro'),
  ('levantar_lista_max', 30, 'activos', 5, 100, 'Encontrar activo (Corte 14): cuántos activos cercanos se listan como máximo (los más cercanos primero)'),
  ('levantar_propuesta_m', 5, 'm', 1, 50, 'Cierre casi automático (Corte 14): un activo NUEVO (cargado después del reporte) a menos de esta distancia de un punto por levantar se propone como «posiblemente levantado»; lo confirma el supervisor'),
  ('levantar_hoja_max', 60, 'activos', 5, 200, 'Hoja de levantamiento en PDF (Corte 14): cuántos puntos caben como máximo en una hoja (los más antiguos primero)')
on conflict (clave) do update set estado = 'vigente', descripcion = excluded.descripcion;

do $$
begin      -- la clave nueva del dominio (si hubo una reversa del 14, ya está)
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') = 'CHECK ((VALUE = ANY (ARRAY[''entrada''::text, ''salida''::text, ''muestreo''::text, ''danos_fallas''::text, ''mantenimiento''::text, ''uso_quimicos''::text, ''entrada_quimicos''::text, ''anomalia_compartida''::text, ''revision_compartida''::text])))' then
    alter domain tecnica.formulario_clave drop constraint formulario_clave_ck;
    alter domain tecnica.formulario_clave add constraint formulario_clave_ck check (value in
      ('entrada', 'salida', 'muestreo', 'danos_fallas', 'mantenimiento', 'uso_quimicos', 'entrada_quimicos', 'anomalia_compartida', 'revision_compartida', 'activo_campo'));
  end if;
end $$;
insert into redes.formularios_distribucion (clave, nombre, orden) values ('activo_campo', 'Encontrar o reportar activo', 5)
on conflict (clave) do update set activo = true, nombre = excluded.nombre;

-- Comercial: la misma clave en la lista de Personal (allá la asignación solo se registra: no restringe; quien tiene Formularios de campo puede usarlo)
alter table campo.personal_eventos drop constraint personal_eventos_formulario_check;
alter table campo.personal_eventos add constraint personal_eventos_formulario_check
  check (formulario is null or formulario ~ '^(reporte_general|acta|activo_campo|tipo:[a-z][a-z0-9_]{1,59})$');

-- ---------- 3. Etapa 2: el aviso (Corte 12) y la capa «Por levantar» del geovisor ----------
insert into tecnica.aviso_parametros (clave, area, valor, minimo, maximo, unidad, orden, nombre, descripcion) values
  ('levantar_naranja_dias', 'distribucion', 30, 1, 365, 'días', 180, 'Activos por levantar: naranja',
   'Los activos reportados por levantar salen como aviso informativo; pasa a naranja si alguno lleva más de estos días sin levantar.')
on conflict (clave) do nothing;
insert into redes.geovisor_capas (codigo, nombre, grupo, fuente, estado, prefijos, por_fecha, solo_completo, nota, orden, activa) values
  ('por_levantar', 'Por levantar (activos reportados)', 'actividades', 'geojson', 'activa', '{}', false, true,
   'Activos encontrados en la calle que no están en la red («Encontrar o reportar activo»). Solo los que siguen por levantar. Supervisores y administrador', 42, true)
on conflict (codigo) do update set activa = true, estado = 'activa';
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 20 — FUNCIONES INTERNAS (nadie de la API las ejecuta)
-- PROPUESTA. No se ha ejecutado en la base real.
-- =====================================================================

-- Quién entra a «Encontrar o reportar activo» (lo decide SIEMPRE la base):
--   · administrador y supervisor de distribución;
--   · en Técnica: el supervisor de planta, y el operador que tenga el formulario «activo_campo» asignado (Personal de distribución);
--   · en Comercial: quien tiene Formularios de campo (operario o supervisor). Allá la asignación solo se registra, como las demás de Comercial.
-- perfil: admin | supervisor | operador | comercial.   area: tecnica | comercial (queda en el punto que reporte).
create function redes.f_levantar_acceso(p_solicitante text, out email text, out perfil text, out area text) returns record
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
begin
  email := lower(btrim(coalesce(p_solicitante, '')));
  if email = '' or position('@' in email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if public.geoportal_es_admin(email) then perfil := 'admin'; area := 'tecnica'; return; end if;
  if (public.geoportal_puede(email, 'dashboard_redes') or tecnica.f_perfil(email) is not null) and tecnica.f_tecnica_activa(email) then
    if public.geoportal_puede(email, 'dashboard_redes') then perfil := 'supervisor'; area := 'tecnica'; return; end if;
    if public.geoportal_puede(email, 'dashboard_tecnico') or tecnica.f_formulario_asignado(email, 'activo_campo') then perfil := 'operador'; area := 'tecnica'; return; end if;
  end if;
  if public.geoportal_puede(email, 'campo') then perfil := 'comercial'; area := 'comercial'; return; end if;
  raise exception 'Sin permiso para «Encontrar o reportar activo»: pídale a su supervisor que le asigne el formulario' using errcode = '42501';      -- la Edge responde 403 con su texto fijo; la pantalla dice a quién pedirlo
end $$;

create function redes.f_levantar_puede(p_email text) returns boolean
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
begin
  perform 1 from redes.f_levantar_acceso(p_email);
  return true;
exception when others then
  return false;
end $$;

create function redes.f_levantar_tipo_nombre(p_tipo text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case p_tipo when 'tuberia' then 'Tubería' when 'valvula' then 'Válvula' when 'hidrante' then 'Hidrante' when 'pozo' then 'Pozo' when 'caja' then 'Caja' when 'otro' then 'Otro' end
$$;

create function redes.f_levantar_estado_nombre(p_estado text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case p_estado when 'reportado' then 'Reportado' when 'asignado' then 'Asignado a levantamiento' when 'levantado' then 'Levantado' when 'descartado' then 'Descartado' end
$$;

-- Nombre del funcionario (nunca de un suscriptor): el de la lista blanca o, si no tiene, lo que va antes de la arroba
create function redes.f_levantar_quien(p_email text) returns text
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = p_email), split_part(p_email, '@', 1))
$$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 26 — RPC NUEVAS (public.geoportal_redes_levantar_*; solo service_role, desde la Edge geoportal-redes)
-- PROPUESTA. No se ha ejecutado en la base real.
-- Ninguna recorre tablas enteras: la búsqueda de cercanos entra por el índice espacial de redes.activo_vigente_mat (caja de pocos metros).
-- =====================================================================

-- ---------- Abrir la pantalla: quién es, los parámetros y los tipos ----------
create function public.geoportal_redes_levantar_inicio(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare a record;
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  return jsonb_build_object('perfil', a.perfil, 'area', a.area,
    'ficha_completa', a.area = 'tecnica',                                            -- en Técnica se abre la ficha de siempre (la edita quien ya podía)
    'reporta_dano', a.area = 'tecnica' and redes.f_puede_formulario(a.email, 'danos_fallas'),      -- «Reportar daño en este activo» (quien tiene el formulario de daños)
    'radio_min_m', redes.f_param('levantar_radio_min_m'), 'radio_max_m', redes.f_param('levantar_radio_max_m'), 'duplicado_m', redes.f_param('levantar_duplicado_m'),
    'min_fotos', 1, 'max_fotos', 3,
    'servicios', jsonb_build_array(jsonb_build_object('codigo', 'acueducto', 'nombre', 'Acueducto'), jsonb_build_object('codigo', 'alcantarillado', 'nombre', 'Alcantarillado')),
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', t, 'nombre', redes.f_levantar_tipo_nombre(t)) order by o)
                from unnest(array['tuberia', 'valvula', 'hidrante', 'pozo', 'caja', 'otro']) with ordinality x(t, o)));
end $$;

-- ---------- Encontrar: los activos cercanos a la persona (y los puntos por levantar que ya hay ahí) ----------
-- Radio = el mayor entre el mínimo (15 m) y la precisión del GPS, con tope (30 m). La posición no se guarda.
create function public.geoportal_redes_levantar_cerca(p_solicitante text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_servicio text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare a record; v_min numeric := redes.f_param('levantar_radio_min_m'); v_max numeric := redes.f_param('levantar_radio_max_m'); v_dup numeric := redes.f_param('levantar_duplicado_m');
        v_lim integer := redes.f_param('levantar_lista_max')::integer; v_radio numeric; v_pto geometry; v_g geography; v_caja geometry; v_recorte geometry;
        v_act jsonb; v_total integer; v_ptos jsonb;
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if p_lat is null or p_lon is null or p_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max')
     or p_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
    perform tecnica.f_error('La posición está fuera de Valledupar');
  end if;
  if p_servicio is null or p_servicio not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija acueducto o alcantarillado'); end if;
  if p_precision_m is not null and (p_precision_m <= 0 or p_precision_m > 5000) then perform tecnica.f_error('La precisión del GPS no es válida'); end if;
  v_radio := greatest(v_min, least(coalesce(p_precision_m, v_min), v_max));
  v_pto := ST_SetSRID(ST_MakePoint(p_lon::double precision, p_lat::double precision), 4326); v_g := v_pto::geography;
  v_caja := ST_Expand(v_pto, (greatest(v_radio, v_dup) + 5) / 100000.0);      -- caja en grados (1 grado ≈ 110 km): entra por el índice espacial
  v_recorte := ST_Buffer(v_g, 4 * v_max)::geometry;                            -- los tramos se dibujan recortados alrededor de la persona
  with c as (
    select m.activo_id, m.codigo, m.prefijo, m.material_codigo, m.diametro_mm, m.estado_codigo, m.geom,
           case when GeometryType(m.geom) in ('POINT', 'MULTIPOINT') then 'punto' when GeometryType(m.geom) in ('POLYGON', 'MULTIPOLYGON') then 'area' else 'linea' end as forma,
           ST_Distance(m.geom::geography, v_g) as d
      from redes.activo_vigente_mat m
     where not m.retirado and not m.oculto and m.sistema = p_servicio and m.geom && v_caja and ST_DWithin(m.geom::geography, v_g, v_radio)
  ), o as (
    -- a igual distancia (al decímetro), primero los puntos (válvula, pozo) y después los tramos que llegan a ellos
    select c.*, row_number() over (order by round(c.d::numeric, 1), (c.forma <> 'punto'), c.codigo) as n, count(*) over () as total from c
  )
  select coalesce(max(o.total), 0)::integer,
         coalesce(jsonb_agg(jsonb_build_object('n', o.n, 'codigo', o.codigo, 'prefijo', o.prefijo, 'tipo', redes.f_tipo_nombre(o.prefijo), 'forma', o.forma,
                    'material', (select mt.nombre from redes.materiales mt where mt.codigo = o.material_codigo), 'diametro_mm', o.diametro_mm,
                    'estado', (select s.nombre from redes.estados_activo s where s.codigo = o.estado_codigo), 'proyectado', o.estado_codigo = 'proyectado',
                    'distancia_m', round(o.d::numeric, 1),
                    'lat', round(ST_Y(ST_ClosestPoint(o.geom, v_pto))::numeric, 6), 'lon', round(ST_X(ST_ClosestPoint(o.geom, v_pto))::numeric, 6),
                    'geometria', ST_AsGeoJSON(case when o.forma = 'punto' then o.geom else ST_Intersection(o.geom, v_recorte) end, 6)::jsonb) order by o.n)
                  filter (where o.n <= v_lim), '[]'::jsonb)
    into v_total, v_act from o;
  select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'servicio', x.servicio, 'tipo', x.tipo, 'tipo_nombre', redes.f_levantar_tipo_nombre(x.tipo), 'estado', x.estado,
                    'registrado_en', x.registrado_en, 'distancia_m', round(x.d::numeric, 1), 'lat', x.lat, 'lon', x.lon, 'posible_duplicado', x.d <= v_dup) order by x.d, x.codigo), '[]'::jsonb)
    into v_ptos
    from (select p.codigo, p.servicio, p.tipo, p.estado, p.registrado_en, p.lat, p.lon, ST_Distance(p.geom::geography, v_g) as d
            from redes.v_levantar_punto p
           where p.geom && v_caja and ST_DWithin(p.geom::geography, v_g, greatest(v_radio, v_dup)) and p.estado in ('reportado', 'asignado')) x;
  return jsonb_build_object('servicio', p_servicio, 'radio_m', v_radio, 'precision_m', p_precision_m, 'senal_debil', p_precision_m is null or p_precision_m > v_max,
    'tope_m', v_max, 'duplicado_m', v_dup, 'total', v_total, 'activos', v_act, 'puntos', v_ptos);
end $$;

-- ---------- La ficha corta (solo lectura) de un activo, para quien no entra a la ficha de Técnica ----------
create function public.geoportal_redes_levantar_ficha(p_solicitante text, p_codigo text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare a record; m redes.activo_vigente_mat%rowtype; v_cod text := upper(btrim(coalesce(p_codigo, '')));
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if v_cod !~ '^[A-Z]{3}-[0-9]{1,8}$' then perform tecnica.f_error('Ese código de activo no es válido'); end if;
  select * into m from redes.activo_vigente_mat x where x.codigo = v_cod and not x.retirado and not x.oculto;
  if not found then perform tecnica.f_error('Ese activo no existe', 'P0002'); end if;
  return jsonb_build_object('codigo', m.codigo, 'prefijo', m.prefijo, 'tipo', redes.f_tipo_nombre(m.prefijo), 'sistema', m.sistema,
    'clase', (select c.nombre from redes.clases_activo c where c.prefijo = m.prefijo and c.codigo = m.clase), 'nombre', m.nombre,
    'material', (select mt.nombre from redes.materiales mt where mt.codigo = m.material_codigo), 'diametro_mm', m.diametro_mm,
    'longitud_m', case when GeometryType(m.geom) in ('LINESTRING', 'MULTILINESTRING') then round(coalesce(m.longitud_m, ST_Length(m.geom::geography)::numeric), 1) end, 'profundidad_m', m.profundidad_m, 'fecha_instalacion', m.fecha_instalacion,
    'estado', (select s.nombre from redes.estados_activo s where s.codigo = m.estado_codigo), 'codigo_anterior', m.codigo_anterior,
    'sector', (select s.nombre from redes.f_sector_de(ST_PointOnSurface(m.geom)) s),
    'lat', round(ST_Y(ST_PointOnSurface(m.geom))::numeric, 6), 'lon', round(ST_X(ST_PointOnSurface(m.geom))::numeric, 6),
    'ficha_completa', a.area = 'tecnica');
end $$;

-- ---------- Reportar activo: preparar la subida de las fotos (1 obligatoria y 2 opcionales) ----------
create function public.geoportal_redes_levantar_preparar(p_solicitante text, p_fotos integer) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare a record; v_id uuid := gen_random_uuid(); v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM');
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if p_fotos is null or p_fotos < 1 or p_fotos > 3 then perform tecnica.f_error('Un activo por levantar lleva de 1 a 3 fotos'); end if;
  insert into redes.levantar_preparaciones (punto_id, autor, fotos) values (v_id, a.email, p_fotos);
  return jsonb_build_object('punto_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_dano')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', (select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'levantar/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n) from generate_series(1, p_fotos) n));
end $$;

-- ---------- Reportar activo: crear el punto por levantar ----------
-- p_datos: servicio, tipo, observacion, lat, lon, precision_m, fotos [{n, ruta}], no_es_duplicado (la persona ya vio el punto cercano y dijo que no es el mismo).
-- Si hay un punto por levantar a menos de levantar_duplicado_m y no viene «no_es_duplicado», NO crea nada: devuelve creado = false y los puntos.
create function public.geoportal_redes_levantar_crear(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'storage', 'pg_temp' as $$
declare a record; d jsonb := coalesce(p_datos, '{}'::jsonb); v_prev redes.levantar_puntos%rowtype; v_prep redes.levantar_preparaciones%rowtype;
        v_obs text; v_lat numeric; v_lon numeric; v_prec numeric; v_max numeric := redes.f_param('levantar_radio_max_m'); v_dup numeric := redes.f_param('levantar_duplicado_m');
        v_pto geometry; v_dups jsonb; v_fotos jsonb; v_n integer; v_f jsonb; v_ruta text; v_size bigint; v_mime text; v_max_bytes bigint := redes.f_param('max_bytes_foto_dano')::bigint;
        v_ref jsonb := '[]'::jsonb; v_cons bigint; v_codigo text; v_en timestamptz := clock_timestamp();
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if p_id is null then perform tecnica.f_error('Falta el identificador: prepare la subida de las fotos primero'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos no tienen el formato esperado'); end if;
  perform pg_advisory_xact_lock(hashtextextended('lev|' || p_id::text, 0));
  select * into v_prev from redes.levantar_puntos where id = p_id;
  if found then      -- reintento del mismo envío (sin señal): se devuelve lo ya guardado
    if v_prev.autor <> a.email then perform tecnica.f_error('Primero debe prepararse la subida de las fotos'); end if;
    return jsonb_build_object('creado', true, 'repetido', true, 'id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'precision_baja', v_prev.precision_baja, 'estado', 'reportado');
  end if;
  select * into v_prep from redes.levantar_preparaciones where punto_id = p_id and autor = a.email;
  if not found then perform tecnica.f_error('Primero debe prepararse la subida de las fotos'); end if;
  if coalesce(d ->> 'servicio', '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el servicio: acueducto o alcantarillado'); end if;
  if coalesce(d ->> 'tipo', '') not in ('tuberia', 'valvula', 'hidrante', 'pozo', 'caja', 'otro') then perform tecnica.f_error('Elija qué activo encontró'); end if;
  v_obs := nullif(btrim(coalesce(d ->> 'observacion', '')), '');
  if v_obs is not null and (length(v_obs) < 3 or length(v_obs) > 500) then perform tecnica.f_error('La observación va de 3 a 500 caracteres'); end if;
  if d ->> 'tipo' = 'otro' and v_obs is null then perform tecnica.f_error('Escriba en la observación qué activo es'); end if;
  begin
    v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric; v_prec := (d ->> 'precision_m')::numeric;
  exception when others then perform tecnica.f_error('La posición del GPS no es válida');
  end;
  if v_lat is null or v_lon is null then perform tecnica.f_error('Falta la posición del GPS: active la ubicación del celular'); end if;
  if v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
    perform tecnica.f_error('La posición está fuera de Valledupar');
  end if;
  if v_prec is null or v_prec <= 0 or v_prec > 5000 then perform tecnica.f_error('Falta la precisión del GPS: active la ubicación del celular'); end if;
  v_pto := ST_SetSRID(ST_MakePoint(v_lon::double precision, v_lat::double precision), 4326);

  -- duplicados (regla 2): un punto por levantar a pocos metros se muestra antes de crear otro
  if d -> 'no_es_duplicado' is distinct from 'true'::jsonb then
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'servicio', x.servicio, 'tipo', x.tipo, 'tipo_nombre', redes.f_levantar_tipo_nombre(x.tipo), 'registrado_en', x.registrado_en,
                     'distancia_m', round(x.dist::numeric, 1), 'lat', x.lat, 'lon', x.lon) order by x.dist, x.codigo)
      into v_dups
      from (select p.codigo, p.servicio, p.tipo, p.registrado_en, p.lat, p.lon, ST_Distance(p.geom::geography, v_pto::geography) as dist
              from redes.v_levantar_punto p
             where p.geom && ST_Expand(v_pto, (v_dup + 5) / 100000.0) and ST_DWithin(p.geom::geography, v_pto::geography, v_dup) and p.estado in ('reportado', 'asignado')) x;
    if v_dups is not null then return jsonb_build_object('creado', false, 'duplicados', v_dups, 'duplicado_m', v_dup); end if;
  end if;

  -- fotos: el tamaño y el tipo se leen de Storage (nunca se le creen al celular)
  v_fotos := coalesce(d -> 'fotos', '[]'::jsonb);
  if jsonb_typeof(v_fotos) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n < 1 or v_n > 3 or v_n > v_prep.fotos then perform tecnica.f_error('Un activo por levantar lleva de 1 a 3 fotos'); end if;
  if (select count(distinct (e ->> 'n')) <> v_n or bool_or(coalesce(e ->> 'n', '') !~ '^[1-3]$') from jsonb_array_elements(v_fotos) e)
     or (select max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_fotos) e) then
    perform tecnica.f_error('El orden de las fotos debe ser 1, 2, 3 sin repetir ni saltar');
  end if;
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'n')::integer loop
    v_ruta := coalesce(v_f ->> 'ruta', '');
    if v_ruta !~ ('^levantar/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || '\.jpg$') then
      perform tecnica.f_error(format('La ruta de la foto %s no corresponde a este reporte', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró la foto %s: súbala de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('La foto %s está vacía', v_f ->> 'n')); end if;
    if v_size > v_max_bytes then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;

  -- código LEV-000123 (candado de fila del consecutivo) e inserción
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'LEV' returning ultimo into v_cons;
  v_codigo := 'LEV-' || lpad(v_cons::text, 6, '0');
  insert into redes.levantar_puntos (id, codigo, servicio, tipo, observacion, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en)
  values (p_id, v_codigo, d ->> 'servicio', d ->> 'tipo', v_obs, round(v_lat, 6), round(v_lon, 6), v_pto, round(v_prec, 1), v_prec > v_max, a.area, a.email, v_en);
  insert into redes.levantar_fotos (punto_id, n, ruta_storage, bytes, mime)
  select p_id, (e ->> 'n')::smallint, e ->> 'ruta', (e ->> 'bytes')::integer, e ->> 'mime' from jsonb_array_elements(v_ref) e;
  perform tecnica.f_auditar(a.email, 'redes_levantar_crear', v_codigo, jsonb_build_object('servicio', d ->> 'servicio', 'tipo', d ->> 'tipo', 'fotos', v_n,
          'precision_m', round(v_prec, 1), 'precision_baja', v_prec > v_max, 'area', a.area, 'no_es_duplicado', d -> 'no_es_duplicado' = 'true'::jsonb), p_ip);
  return jsonb_build_object('creado', true, 'repetido', false, 'id', p_id, 'codigo', v_codigo, 'registrado_en', v_en, 'precision_baja', v_prec > v_max, 'estado', 'reportado');
end $$;

-- ---------- Supervisor: la bandeja «Otros activos por levantamiento» (Dashboard distribución → Por verificar) ----------
create function public.geoportal_redes_levantar_lista(p_solicitante text, p_estado text default 'abiertos', p_despues_de text default null, p_limite integer default 50) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 've los activos por levantar'); v_lim integer := coalesce(p_limite, 50); v_est text := coalesce(p_estado, 'abiertos');
        v_desp text := nullif(upper(btrim(coalesce(p_despues_de, ''))), ''); v_items jsonb; v_cont jsonb; v_prop numeric := redes.f_param('levantar_propuesta_m');
begin
  if v_lim < 1 or v_lim > 200 then perform tecnica.f_error('Se piden de 1 a 200'); end if;
  if v_est not in ('abiertos', 'reportado', 'asignado', 'levantado', 'descartado', 'todos') then perform tecnica.f_error('Ese estado no existe'); end if;
  if v_desp is not null and v_desp !~ '^LEV-[0-9]{6}$' then perform tecnica.f_error('La página pedida no es válida'); end if;
  select coalesce(jsonb_object_agg(g.estado, g.n), '{}'::jsonb) into v_cont from (select p.estado, count(*) as n from redes.v_levantar_punto p group by 1) g;
  select coalesce(jsonb_agg(jsonb_build_object('codigo', p.codigo, 'servicio', p.servicio, 'tipo', p.tipo, 'tipo_nombre', redes.f_levantar_tipo_nombre(p.tipo), 'observacion', p.observacion,
           'lat', p.lat, 'lon', p.lon, 'precision_m', p.precision_m, 'precision_baja', p.precision_baja, 'registrado_en', p.registrado_en, 'area', p.area,
           'quien', redes.f_levantar_quien(p.autor), 'estado', p.estado, 'estado_nombre', redes.f_levantar_estado_nombre(p.estado), 'estado_desde', p.estado_desde,
           'estado_motivo', p.estado_motivo, 'estado_quien', case when p.estado_autor is not null then redes.f_levantar_quien(p.estado_autor) end,
           'activo', (select m.codigo from redes.activos m where m.id = p.activo_id), 'fotos', p.fotos,
           -- cierre casi automático (regla 4): un activo NUEVO (creado después del reporte) del mismo servicio a pocos metros; el supervisor confirma
           'propuesta', case when p.estado in ('reportado', 'asignado') then (
              select jsonb_build_object('activo', m.codigo, 'tipo', redes.f_tipo_nombre(m.prefijo), 'distancia_m', round(ST_Distance(m.geom::geography, p.geom::geography)::numeric, 1), 'cargado_en', a.creado_en)
                from redes.activo_vigente_mat m join redes.activos a on a.id = m.activo_id
               where not m.retirado and not m.oculto and m.sistema = p.servicio and a.creado_en > p.registrado_en
                 and m.geom && ST_Expand(p.geom, (v_prop + 5) / 100000.0) and ST_DWithin(m.geom::geography, p.geom::geography, v_prop)
               order by ST_Distance(m.geom::geography, p.geom::geography), m.codigo limit 1) end,
           'sector', (select s.nombre from redes.f_sector_de(p.geom) s)) order by p.codigo desc), '[]'::jsonb)
    into v_items
    from (select x.* from redes.v_levantar_punto x
           where (v_est = 'todos' or (v_est = 'abiertos' and x.estado in ('reportado', 'asignado')) or x.estado = v_est) and (v_desp is null or x.codigo < v_desp)
           order by x.codigo desc limit v_lim) p;
  return jsonb_build_object('estado', v_est, 'conteos', v_cont,
    'abiertos', coalesce((v_cont ->> 'reportado')::integer, 0) + coalesce((v_cont ->> 'asignado')::integer, 0),
    'items', v_items, 'siguiente', case when jsonb_array_length(v_items) = v_lim then v_items -> (v_lim - 1) ->> 'codigo' end);
end $$;

-- ---------- Supervisor: cambiar el estado (solo se agregan eventos; nada se borra) ----------
-- asignado (desde reportado) · levantado, con el activo nuevo (desde reportado o asignado) · descartado, con motivo (desde reportado o asignado) ·
-- reabierto, con motivo (desde levantado o descartado: vuelve a «reportado»).
create function public.geoportal_redes_levantar_evento(p_solicitante text, p_codigo text, p_tipo text, p_activo text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'cambian el estado de un activo por levantar'); v_cod text := upper(btrim(coalesce(p_codigo, '')));
        v_mot text := nullif(btrim(coalesce(p_motivo, '')), ''); v_act text := nullif(upper(btrim(coalesce(p_activo, ''))), ''); v_activo bigint; p record; v_id bigint;
begin
  if coalesce(p_tipo, '') not in ('asignado', 'levantado', 'descartado', 'reabierto') then perform tecnica.f_error('Ese cambio de estado no existe'); end if;
  if v_cod !~ '^LEV-[0-9]{6}$' then perform tecnica.f_error('Ese código no es de un activo por levantar'); end if;
  if v_mot is not null and (length(v_mot) < 3 or length(v_mot) > 500) then perform tecnica.f_error('El motivo va de 3 a 500 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtextextended('lev|' || v_cod, 0));
  select * into p from redes.v_levantar_punto x where x.codigo = v_cod;
  if not found then perform tecnica.f_error('Ese activo por levantar no existe', 'P0002'); end if;
  if p_tipo = 'reabierto' then
    if p.estado not in ('levantado', 'descartado') then perform tecnica.f_error('Solo se reabre un punto levantado o descartado', '55000'); end if;
  elsif p.estado not in ('reportado', 'asignado') then perform tecnica.f_error(format('Este punto ya está «%s»: reábralo primero', lower(redes.f_levantar_estado_nombre(p.estado))), '55000');
  elsif p_tipo = 'asignado' and p.estado = 'asignado' then perform tecnica.f_error('Ya está asignado a levantamiento', '55000');
  end if;
  if p_tipo in ('descartado', 'reabierto') and (v_mot is null or length(v_mot) < 10) then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  if p_tipo = 'levantado' then
    if v_act is null then perform tecnica.f_error('Diga con qué activo quedó levantado (su código)'); end if;
    select m.activo_id into v_activo from redes.activo_vigente_mat m where m.codigo = v_act and not m.retirado;
    if v_activo is null then perform tecnica.f_error('Ese activo no existe en la red: publique primero la carga de la capa', 'P0002'); end if;
  elsif v_act is not null then perform tecnica.f_error('El activo solo va al marcar «levantado»');
  end if;
  insert into redes.levantar_eventos (punto_id, tipo, activo_id, motivo, autor) values (p.id, p_tipo, v_activo, v_mot, v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'redes_levantar_' || p_tipo, v_cod, jsonb_build_object('evento', v_id, 'activo', v_act, 'antes', p.estado), p_ip);
  return (select jsonb_build_object('codigo', x.codigo, 'estado', x.estado, 'estado_nombre', redes.f_levantar_estado_nombre(x.estado), 'estado_desde', x.estado_desde, 'activo', v_act)
            from redes.v_levantar_punto x where x.id = p.id);
end $$;

-- ---------- Supervisor: las fotos de un punto (la Edge firma la lectura por 60 s; la lectura queda en la auditoría) ----------
create function public.geoportal_redes_levantar_fotos(p_solicitante text, p_codigo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 've las fotos de un activo por levantar'); v_cod text := upper(btrim(coalesce(p_codigo, ''))); v_id uuid; v_fotos jsonb;
begin
  if v_cod !~ '^LEV-[0-9]{6}$' then perform tecnica.f_error('Ese código no es de un activo por levantar'); end if;
  select p.id into v_id from redes.levantar_puntos p where p.codigo = v_cod;
  if v_id is null then perform tecnica.f_error('Ese activo por levantar no existe', 'P0002'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('n', f.n, 'ruta', f.ruta_storage, 'creado_en', f.creado_en) order by f.n), '[]'::jsonb) into v_fotos from redes.levantar_fotos f where f.punto_id = v_id;
  perform tecnica.f_auditar(v_email, 'redes_levantar_fotos', v_cod, jsonb_build_object('fotos', jsonb_array_length(v_fotos)), p_ip);
  return jsonb_build_object('codigo', v_cod, 'fotos', v_fotos);
end $$;

-- ---------- Supervisor: la hoja de levantamiento (PDF con la hoja membretada): los puntos numerados EN EL ORDEN DEL RECORRIDO ----------
-- Empieza por el punto más al norte y sigue siempre al más cercano que falte. Trae la primera foto de cada punto (la Edge firma la lectura) y la observación
-- (David, 17-nov: en este PDF sí va, le sirve a la cuadrilla). Sin quién reportó y sin datos de suscriptores. La descarga queda en la auditoría.
create function public.geoportal_redes_levantar_hoja(p_solicitante text, p_estado text default 'abiertos', p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'descargan la hoja de levantamiento'); v_est text := coalesce(p_estado, 'abiertos');
        v_max integer := redes.f_param('levantar_hoja_max')::integer; v_ids uuid[]; v_orden uuid[] := '{}'; v_act uuid; v_total integer; v_puntos jsonb;
begin
  if v_est not in ('abiertos', 'reportado', 'asignado') then perform tecnica.f_error('La hoja de levantamiento es de los puntos por levantar'); end if;
  select count(*) into v_total from redes.v_levantar_punto x where (v_est = 'abiertos' and x.estado in ('reportado', 'asignado')) or x.estado = v_est;
  select array_agg(y.id order by y.lat desc, y.lon, y.codigo) into v_ids
    from (select x.id, x.lat, x.lon, x.codigo from redes.v_levantar_punto x
           where (v_est = 'abiertos' and x.estado in ('reportado', 'asignado')) or x.estado = v_est order by x.codigo limit v_max) y;
  if v_ids is not null then
    v_act := v_ids[1];
    loop
      v_orden := v_orden || v_act;
      exit when cardinality(v_orden) >= cardinality(v_ids);
      select q.id into v_act from redes.levantar_puntos q, redes.levantar_puntos c
       where c.id = v_act and q.id = any (v_ids) and q.id <> all (v_orden) order by q.geom <-> c.geom, q.codigo limit 1;
    end loop;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('n', o.n, 'codigo', p.codigo, 'tipo_nombre', redes.f_levantar_tipo_nombre(p.tipo), 'servicio', p.servicio, 'registrado_en', p.registrado_en,
           'lat', p.lat, 'lon', p.lon, 'precision_m', p.precision_m, 'precision_baja', p.precision_baja, 'observacion', p.observacion, 'estado_nombre', redes.f_levantar_estado_nombre(p.estado),
           'sector', (select s.nombre from redes.f_sector_de(p.geom) s),
           'foto', (select f.ruta_storage from redes.levantar_fotos f where f.punto_id = p.id order by f.n limit 1)) order by o.n), '[]'::jsonb)
    into v_puntos from unnest(v_orden) with ordinality o(id, n) join redes.v_levantar_punto p on p.id = o.id;
  perform tecnica.f_auditar(v_email, 'redes_levantar_hoja', null, jsonb_build_object('estado', v_est, 'puntos', jsonb_array_length(v_puntos), 'total', v_total), p_ip);
  return jsonb_build_object('generado_en', clock_timestamp(), 'estado', v_est, 'total', v_total, 'recortada', v_total > jsonb_array_length(v_puntos), 'puntos', v_puntos);
end $$;

-- =====================================================================
-- ETAPA 3 · Parte 2: modo «Remuneración» del geovisor (antes «10-bis»). SOLO supervisor de distribución y administrador (es término tarifario: el operador
-- y el supervisor de planta no ven el modo, ni su leyenda, ni su tesela). Fuente: el amarre del Corte 10 (redes.val_amarre, con la hoja de alcantarillado
-- vigente por el parámetro) y la misma regla de redes.f_ficha_regulatorio. Nada nuevo se carga.
--   remunerado: tiene fila en la valoración vigente · no_remunerado: tiene fila, pero está fuera de servicio o es obra de un tercero (SIVA) ·
--   sin_fila: en la red, sin amarre a la valoración (o sin fila que le corresponda) · proyectado: del Plan, no construido.
-- =====================================================================
create function redes.f_remuneracion_estado(p_con boolean, p_aparte boolean, p_proyectado boolean) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case when p_con then 'remunerado' when p_aparte then 'no_remunerado' when p_proyectado then 'proyectado' else 'sin_fila' end
$$;

-- La leyenda y los conteos del modo (y si hay amarre cargado)
create function public.geoportal_redes_remuneracion(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el modo «Remuneración»'); v_am bigint := redes.f_ref_vigente('val_amarre'); v_val bigint := redes.f_ref_vigente('valoracion');
        v_hoja text := redes.f_val_hoja_alc(); v_pref text[] := redes.f_val_prefijos(); v_cont jsonb;
begin
  if v_am is not null and v_val is not null then
    select coalesce(jsonb_object_agg(g.estado, g.n), '{}'::jsonb) into v_cont from (
      select redes.f_remuneracion_estado(coalesce(r.con, false), coalesce(r.aparte, false), coalesce(r.proy, false) or m.estado_codigo = 'proyectado') as estado, count(*) as n
        from redes.activo_vigente_mat m
        left join (select am.activo_id, bool_or(am.situacion = 'con_fila') as con, bool_or(am.situacion like 'aparte\_%') as aparte, bool_or(am.situacion = 'proyectado') as proy
                     from redes.val_amarre am where am.carga_id = v_am and am.val_carga_id = v_val and am.hoja in ('acueducto', v_hoja) group by am.activo_id) r on r.activo_id = m.activo_id
       where not m.retirado and not m.oculto and (m.prefijo = any (v_pref) or r.activo_id is not null) group by 1) g;
  end if;
  return jsonb_build_object('cargado', v_am is not null and v_val is not null, 'version', v_am,
    'rotulo', 'Valoración técnica 2019, propuesta',
    'nota', 'Remuneración vía tarifa según la Valoración Técnica de 2019 (Res. CRA 688 de 2014), que es una PROPUESTA: su adopción no está confirmada.',
    'conteos', coalesce(v_cont, '{}'::jsonb),
    'leyenda', jsonb_build_array(
      jsonb_build_object('clave', 'remunerado', 'nombre', 'Remunerado', 'significa', 'Tiene fila en la valoración vigente'),
      jsonb_build_object('clave', 'no_remunerado', 'nombre', 'No remunerado', 'significa', 'Tiene fila, pero está fuera de servicio o es obra de un tercero (SIVA)'),
      jsonb_build_object('clave', 'sin_fila', 'nombre', 'Sin fila', 'significa', 'En la red, sin amarre a la valoración'),
      jsonb_build_object('clave', 'proyectado', 'nombre', 'Proyectado', 'significa', 'Del Plan, no construido')));
end $$;

-- La tesela del modo (aparte de la del geovisor, que no se toca): la misma red, con el estado de remuneración de cada activo
create function public.geoportal_redes_geovisor_mvt_remuneracion(p_solicitante text, p_z integer, p_x integer, p_y integer) returns text
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el modo «Remuneración»'); v_am bigint := redes.f_ref_vigente('val_amarre'); v_val bigint := redes.f_ref_vigente('valoracion');
        v_hoja text := redes.f_val_hoja_alc(); v_pref text[] := redes.f_val_prefijos(); v_env geometry; v_env4326 geometry; v bytea;
        z_min numeric := redes.f_param('geovisor_zoom_min'); z_red numeric := redes.f_param('geovisor_zoom_red_completa'); z_nod numeric := redes.f_param('geovisor_zoom_nodos');
        d_acu numeric := redes.f_param('geovisor_diam_principal_acu_mm'); d_alc numeric := redes.f_param('geovisor_diam_principal_alc_mm');
begin
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < z_min or v_am is null or v_val is null then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4326 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'remuneracion', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, m.codigo, m.prefijo, m.sistema,
           case GeometryType(m.geom) when 'POINT' then 'nodo' when 'POLYGON' then 'area' when 'MULTIPOLYGON' then 'area' else 'tramo' end as forma,
           redes.f_remuneracion_estado(coalesce(r.con, false), coalesce(r.aparte, false), coalesce(r.proy, false) or m.estado_codigo = 'proyectado') as rem
      from redes.activo_vigente_mat m
      left join lateral (select count(*) as n, bool_or(am.situacion = 'con_fila') as con, bool_or(am.situacion like 'aparte\_%') as aparte, bool_or(am.situacion = 'proyectado') as proy
                           from redes.val_amarre am
                          where am.activo_id = m.activo_id and am.carga_id = v_am and am.val_carga_id = v_val and am.hoja in ('acueducto', v_hoja)) r on true
     where not m.retirado and not m.oculto and m.geom && v_env4326 and (m.prefijo = any (v_pref) or r.n > 0)
       and case
             when m.prefijo in ('TAN', 'PTA', 'CAP', 'DES', 'PTR') then true
             when GeometryType(m.geom) = 'POINT' then p_z >= z_nod
             when p_z >= z_red then true
             else m.prefijo in ('CON', 'ADU', 'INT')
                  or (m.sistema = 'acueducto' and m.diametro_mm >= d_acu) or (m.sistema = 'alcantarillado' and m.diametro_mm >= d_alc)
           end) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $$;

-- La tarjeta del activo en este modo: «Remunerado vía tarifa: sí / no», el motivo y la fila (o filas) de la valoración. La misma regla de la ficha.
create function public.geoportal_redes_remuneracion_tarjeta(p_solicitante text, p_codigo text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el modo «Remuneración»'); v_cod text := upper(btrim(coalesce(p_codigo, ''))); m redes.activo_vigente_mat%rowtype; j jsonb; v_sit text;
begin
  if v_cod !~ '^[A-Z]{3}-[0-9]{1,8}$' then perform tecnica.f_error('Ese código de activo no es válido'); end if;
  select * into m from redes.activo_vigente_mat x where x.codigo = v_cod and not x.retirado and not x.oculto;
  if not found then perform tecnica.f_error('Ese activo no existe', 'P0002'); end if;
  j := redes.f_ficha_regulatorio(m.activo_id, m.prefijo);
  v_sit := j ->> 'situacion';
  return jsonb_strip_nulls(jsonb_build_object('codigo', m.codigo, 'tipo', redes.f_tipo_nombre(m.prefijo), 'sistema', m.sistema,
    'cargado', redes.f_ref_vigente('val_amarre') is not null,
    'estado', case when j is null then 'no_aplica' when v_sit = 'con_fila' then 'remunerado' when v_sit = 'aparte' then 'no_remunerado'
                   when v_sit = 'proyectado' or m.estado_codigo = 'proyectado' then 'proyectado' else 'sin_fila' end,
    'remunerado', coalesce((j ->> 'remunerado')::boolean, false),
    'rotulo', 'Valoración técnica 2019, propuesta',
    'motivo', case when j is null then 'Este tipo de activo no entra en la valoración.' else j ->> 'texto' end,
    'filas', (select jsonb_agg(jsonb_build_object('hoja', f ->> 'hoja', 'n', (f ->> 'n')::integer, 'nombre', f ->> 'nombre', 'caracteristica', f ->> 'caracteristica',
                                'cantidad', (f ->> 'cantidad')::numeric, 'unidad', f ->> 'unidad', 'anio_operacion', (f ->> 'anio_operacion')::integer) order by (f ->> 'n')::integer)
                from jsonb_array_elements(j -> 'filas') f)));
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el de producción al publicar) con cambios exactos, aplicados una sola vez.
--   · geoportal_redes_mi_perfil: «activo_campo» (la persona tiene «Encontrar o reportar activo»), para la tarjeta del inicio de Técnica;
--   · campo.f_formularios_personal: una fila más, «Encontrar o reportar activo», en la lista de Personal de Comercial.
--   · geoportal_redes_geovisor_capa: la capa «por_levantar» (los puntos que siguen por levantar; solo supervisores y administrador);
--   · tecnica.f_avisos: el aviso «activos por levantar» (informativo; naranja si alguno pasa de levantar_naranja_dias);
--   · geoportal_redes_geovisor: «remuneracion» (la versión del amarre), solo para supervisor de distribución y administrador.
-- =====================================================================
-- public.geoportal_redes_mi_perfil(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_mi_perfil(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  return jsonb_build_object('perfil', p.perfil, 'dashboard_redes', p.perfil in ('admin', 'supervisor'), 'dashboard_ptap', public.geoportal_puede(p.email, 'dashboard_tecnico'),
                            'geovisor', redes.f_geovisor_lectura(p.email),      -- Corte 6a
                            -- 9a-bis: la Ficha de activos en modo buscar (solo lectura) también para el operador de redes
                            'ficha_buscar', p.perfil in ('admin', 'supervisor') or redes.f_operador_redes(p.email),
                            'activo_campo', redes.f_levantar_puede(p.email));      -- Corte 14: «Encontrar o reportar activo»
end $function$;

-- campo.f_formularios_personal()
CREATE OR REPLACE FUNCTION campo.f_formularios_personal()
 RETURNS TABLE(clave text, nombre text, grupo text, orden integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'campo', 'pg_temp'
AS $function$
  select 'reporte_general', 'Reportar anomalía', 'Reportar anomalía', 0
  union all
  select 'tipo:' || t.codigo, t.nombre, g.nombre, (1000 + g.orden * 1000 + t.orden)::integer
    from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where t.activo and g.activo
     and (exists (select 1 from campo.tipo_campos c where c.tipo_id = t.id and c.activo) or exists (select 1 from campo.tipo_fotos f where f.tipo_id = t.id and f.activo)
          or t.genera_resultado or t.prefijo_consecutivo is not null)
  union all
  select 'acta', 'Reportar posible pérdida', 'Reportar posible pérdida', 2000000000
  union all      -- Corte 14 de Técnica: «Encontrar o reportar activo» (lo usa quien tiene Formularios de campo; aquí solo se registra a quién se le asigna)
  select 'activo_campo', 'Encontrar o reportar activo', 'Activos de la red', 2000000001
$function$;

-- public.geoportal_redes_geovisor_capa(text,text,date,date)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor_capa(p_solicitante text, p_capa text, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare a record; g redes.geovisor_capas%rowtype; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        v_desde date := coalesce(p_desde, v_hoy); v_hasta date := coalesce(p_hasta, v_hoy); v_max integer := floor(redes.f_param('geovisor_max_elementos'))::integer;
        v_ini timestamptz; v_fin timestamptz; v_f jsonb; v_n integer; v_sin integer;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into g from redes.geovisor_capas where codigo = p_capa and activa;
  if not found or g.fuente <> 'geojson' then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if g.solo_completo and not a.completo then raise exception 'Capa solo para supervisores' using errcode = '42501'; end if;
  if g.por_fecha then
    if v_desde > v_hasta then perform tecnica.f_error('La fecha inicial es posterior a la final'); end if;
    if v_hasta > v_hoy then perform tecnica.f_error('La fecha final no puede ser futura'); end if;
    if v_desde < (v_hasta - make_interval(months => floor(redes.f_param('geovisor_rango_meses'))::integer))::date then
      perform tecnica.f_error(format('El rango de fechas es de máximo %s meses', floor(redes.f_param('geovisor_rango_meses'))::integer));
    end if;
    if not a.completo and (v_desde <> v_hoy or v_hasta <> v_hoy) then raise exception 'El geovisor en solo lectura muestra solo las actividades del día' using errcode = '42501'; end if;
  end if;
  v_ini := v_desde::timestamp at time zone 'America/Bogota';
  v_fin := (v_hasta + 1)::timestamp at time zone 'America/Bogota';

  if p_capa = 'danos' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(d.lon, d.lat)),
               'properties', jsonb_build_object('codigo', d.codigo, 'clase', d.clase, 'tipo', d.tipo_nombre, 'sistema', d.sistema, 'estado', d.estado,
                                                'activo', d.activo_codigo, 'cuando', d.t_detectado, 'riesgo', d.riesgo, 'origen', d.origen)) as f, d.t_detectado as o
        from redes.v_dano d
       where d.estado <> 'oculto' and d.t_detectado >= v_ini and d.t_detectado < v_fin and d.lat is not null
       order by d.t_detectado desc limit v_max + 1) x;
  elsif p_capa = 'intervenciones' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(i.lon, i.lat)),
               'properties', jsonb_build_object('codigo', i.codigo, 'tipo_codigo', i.tipo_codigo, 'tipo', i.tipo_nombre, 'sistema', i.sistema, 'estado', i.estado,
                                                'activo', i.activo_codigo, 'dano', i.dano_codigo, 'cuando', i.t_inicio, 'fin', i.t_fin, 'ejecutor', i.ejecutor)) as f, i.t_inicio as o
        from redes.v_intervencion i
       where i.estado not in ('oculta', 'anulada') and i.t_inicio >= v_ini and i.t_inicio < v_fin and i.lat is not null
       order by i.t_inicio desc limit v_max + 1) x;
  elsif p_capa = 'reportes_bot' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.radicado, 'canal', r.canal, 'tipo', r.tipo_bot, 'estado', r.estado_bot, 'dano', r.dano_codigo,
                                                'cuando', r.recibido_en)) as f, r.recibido_en as o
        from redes.v_reporte_externo r
       where r.recibido_en >= v_ini and r.recibido_en < v_fin and r.lat is not null
       order by r.recibido_en desc limit v_max + 1) x;
  elsif p_capa = 'por_levantar' then      -- Corte 14: activos encontrados en la calle que siguen por levantar
    select coalesce(jsonb_agg(f order by o), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(p.lon, p.lat)),
               'properties', jsonb_build_object('codigo', p.codigo, 'tipo', redes.f_levantar_tipo_nombre(p.tipo), 'servicio', p.servicio, 'estado', p.estado,
                                                'cuando', p.registrado_en, 'precision_m', p.precision_m, 'precision_baja', p.precision_baja)) as f, p.codigo as o
        from redes.v_levantar_punto p
       where p.estado in ('reportado', 'asignado')
       order by p.codigo limit v_max + 1) x;
  elsif p_capa = 'muestreo' then
    select coalesce(jsonb_agg(f order by o), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(u.lon, u.lat)),
               'properties', jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'exactitud', u.exactitud) || redes.f_muestreo_calidad(p.id)) as f, p.codigo as o
        from tecnica.puntos p join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
       where p.tipo = 'muestreo' and p.activo
       order by p.codigo limit v_max + 1) x;
  elsif p_capa = 'reportes_comercial' then      -- Corte 6b (§30.4): la vista la llena el Corte 8; azul con contrato, rojo posible clandestino
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.codigo, 'tipo', r.tipo, 'subtipo', r.subtipo, 'area', r.area, 'con_contrato', coalesce(r.con_contrato, false),
                                                'estado', r.estado, 'cuando', r.registrado_en)) as f, r.registrado_en as o
        from redes.v_reportes_comercial r
       where r.registrado_en >= v_ini and r.registrado_en < v_fin and r.lat is not null
       order by r.registrado_en desc limit v_max + 1) x;
  elsif p_capa = 'pqr_116' then      -- Corte 5d: la línea 116. Los repetidos del mismo contrato, causal y día van en un solo punto. Sin nombre, dirección ni barrio
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(round(ST_X(z.geom)::numeric, 6), round(ST_Y(z.geom)::numeric, 6))),
               'properties', jsonb_build_object('codigo', z.reportes[1]::text, 'n', z.n, 'reportes', to_jsonb(z.reportes[1:20]), 'servicio', z.servicio,
                                                'grupo_servicio', case redes.f_norm(z.servicio) when 'acueducto' then 'acueducto' when 'alcantarillado' then 'alcantarillado' else 'otros' end,
                                                'causal', z.causal, 'estado', case when z.registrados > 0 then 'registrado' else 'atendido' end, 'registrados', z.registrados,
                                                'contrato', z.contrato, 'dia', z.dia, 'cuando', z.primero, 'ultimo', z.ultimo, 'metodo', z.metodo, 'sector', z.sector, 'subsector', z.subsector,
                                                'danos', (select jsonb_agg(distinct d.codigo) from redes.l116_danos ld join redes.danos d on d.id = ld.dano_id where ld.reporte_id = any (z.ids)))) as f,
             z.ultimo as o
        from (select v.contrato, v.causal, v.dia, count(*) as n, array_agg(v.reporte order by v.fecha_registro, v.reporte) as reportes, array_agg(v.reporte_id) as ids,
                     min(v.servicio) as servicio, count(*) filter (where v.estado = 'registrado') as registrados, min(v.fecha_registro) as primero, max(v.fecha_registro) as ultimo,
                     (array_agg(v.geom order by v.fecha_registro, v.reporte))[1] as geom, (array_agg(v.metodo order by v.fecha_registro, v.reporte))[1] as metodo,
                     (array_agg(v.sector order by v.fecha_registro, v.reporte))[1] as sector, (array_agg(v.subsector order by v.fecha_registro, v.reporte))[1] as subsector
                from redes.l116_vigente v
               where not v.oculto and v.geom is not null and v.fecha_registro >= v_ini and v.fecha_registro < v_fin
               group by coalesce(v.contrato, 'R' || v.reporte), v.contrato, v.causal, v.dia) z
       order by z.ultimo desc limit v_max + 1) x;
    select count(*) into v_sin from redes.l116_vigente v where not v.oculto and v.geom is null and v.fecha_registro >= v_ini and v.fecha_registro < v_fin;
  else
    perform tecnica.f_error('Esa capa todavía no tiene datos', 'P0002');
  end if;

  if v_n > v_max then v_f := v_f - v_max; end if;      -- se quitó el elemento de más (el último de la lista)
  return jsonb_build_object('type', 'FeatureCollection', 'capa', p_capa, 'desde', case when g.por_fecha then v_desde end, 'hasta', case when g.por_fecha then v_hasta end,
                            'recortada', v_n > v_max, 'features', v_f)
         || case when p_capa = 'pqr_116' then jsonb_build_object('sin_ubicar', v_sin) else '{}'::jsonb end;      -- Corte 5d: los del rango que no están en el mapa
end $function$;

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

-- public.geoportal_redes_geovisor(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare a record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  return jsonb_build_object(
    'perfil', case when a.admin then 'admin' when a.completo then 'supervisor' else 'operador' end,
    'completo', a.completo, 'perfiles', to_jsonb(a.perfiles),
    'hoy', (clock_timestamp() at time zone 'America/Bogota')::date,
    'rango_meses', floor(redes.f_param('geovisor_rango_meses'))::integer,
    'max_elementos', floor(redes.f_param('geovisor_max_elementos'))::integer,
    'zoom', jsonb_build_object('min', redes.f_param('geovisor_zoom_min'), 'red_completa', redes.f_param('geovisor_zoom_red_completa'),
                               'nodos', redes.f_param('geovisor_zoom_nodos'), 'accesorios', redes.f_param('geovisor_zoom_acc'),
                               'contratos', redes.f_param('geovisor_zoom_contratos')),
    'version', (select coalesce(sum(version), 0) from redes.tesela_version),
    'formularios', jsonb_build_object('danos_fallas', redes.f_puede_formulario(a.email, 'danos_fallas'),
                                      'mantenimiento', redes.f_puede_formulario(a.email, 'mantenimiento')),
    'ficha', a.completo, 'compartir', a.completo,
    'edad_ref', case when a.completo and redes.f_ref_vigente('val_amarre') is not null then true end,      -- Corte 10: hay amarre con la valoración
    -- Corte 14: el modo «Remuneración» (término tarifario): solo supervisor de distribución y administrador, y solo si hay amarre. Vale la versión del amarre
    'remuneracion', case when a.admin or 'supervisor_distribucion' = any (a.perfiles) then redes.f_ref_vigente('val_amarre') end,
    'contratos_corte', case when a.completo then (select max(s.periodo_carga) from public.cartera_suscripcion s) end,      -- Corte 7a: fecha (AAAAMMDD) del último corte de la cartera
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre, 'grupo', g.grupo, 'fuente', g.fuente, 'estado', g.estado, 'nota', g.nota,
                                          'prefijos', to_jsonb(g.prefijos), 'por_fecha', g.por_fecha,
                                          'encendida', exists (select 1 from redes.capas_por_perfil c where c.capa = g.codigo and c.encendida and c.perfil = any (a.perfiles)))
             order by g.orden)
        from redes.geovisor_capas g where g.activa and (a.completo or not g.solo_completo)), '[]'::jsonb),
    'tipos', coalesce((select jsonb_object_agg(t.prefijo, t.nombre_visible) from redes.v_tipo_visible t), '{}'::jsonb),
    'estados', coalesce((select jsonb_object_agg(e.codigo, e.nombre) from redes.estados_activo e), '{}'::jsonb),
    'materiales', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', m.nombre) order by m.codigo) from redes.materiales m), '[]'::jsonb),
    -- solo el administrador: la tabla de capas por omisión, para editarla (N-11)
    'por_perfil', case when a.admin then coalesce((
      select jsonb_agg(jsonb_build_object('perfil', c.perfil, 'capa', c.capa, 'encendida', c.encendida, 'actualizado_en', c.actualizado_en, 'actualizado_por', c.actualizado_por)
             order by c.perfil, c.capa) from redes.capas_por_perfil c), '[]'::jsonb) end);
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las funciones internas nuevas y las reemplazadas: nadie de la API. Las RPC nuevas y las reemplazadas: solo service_role (la Edge geoportal-redes).
-- Las tablas nuevas: nadie de la API (10_esquema.sql): las leen y escriben solo las funciones SECURITY DEFINER.
-- =====================================================================
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'redes'::regnamespace and (p.proname like 'f\_levantar\_%' or p.proname = 'f_remuneracion_estado') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
  end loop;
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\_redes\_levantar\_%' or p.proname like 'geoportal\_redes\_%remuneracion%'
                   or p.proname in ('geoportal_redes_mi_perfil', 'geoportal_redes_geovisor_capa', 'geoportal_redes_geovisor')) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
-- campo.f_formularios_personal: «create or replace» conserva sus permisos de la pasada del 14-nov (la llaman solo las RPC de campo); aquí no se tocan.

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte14', 'migracion_redes_corte14', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.levantar_puntos', 'redes.levantar_preparaciones', 'redes.levantar_fotos', 'redes.levantar_eventos'),
        'nuevas', (select jsonb_agg(p.proname order by p.proname) from pg_proc p
                    where (p.pronamespace = 'redes'::regnamespace and (p.proname like 'f\_levantar\_%' or p.proname = 'f_remuneracion_estado'))
                       or (p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\_redes\_levantar\_%' or p.proname like 'geoportal\_redes\_%remuneracion%'))),
        'reemplazadas', jsonb_build_array('geoportal_redes_mi_perfil', 'geoportal_redes_geovisor_capa', 'geoportal_redes_geovisor', 'tecnica.f_avisos', 'campo.f_formularios_personal'),
        'fuera_de_redes', jsonb_build_array('tecnica.formulario_clave (clave activo_campo)', 'campo.personal_eventos (CHECK del formulario)', 'campo.f_formularios_personal (una fila más)'),
        'parametros', jsonb_build_array('levantar_radio_min_m', 'levantar_radio_max_m', 'levantar_duplicado_m', 'levantar_lista_max', 'levantar_propuesta_m', 'levantar_hoja_max', 'levantar_naranja_dias (avisos)'),
        'motivo', '«Encontrar o reportar activo»: activos cercanos a la persona, puntos por levantar (solo inserción, con estados) y el formulario asignable en Personal; hoja de levantamiento, aviso, cierre casi automático y capa «Por levantar»; modo «Remuneración» del geovisor'), null);
commit;
