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
  tipo      text not null check (tipo in ('asignado', 'levantado', 'descartado', 'reabierto', 'propuesto')),
  activo_id bigint references redes.activos (id),      -- el activo nuevo (levantado) o el que el sistema propone (propuesto)
  motivo    text check (motivo is null or length(btrim(motivo)) between 3 and 500),
  autor     text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp(),
  check ((tipo in ('levantado', 'propuesto')) = (activo_id is not null)),
  check (tipo not in ('descartado', 'reabierto') or motivo is not null)
);
comment on table redes.levantar_eventos is 'Corte 14: eventos de un punto por levantar, de solo agregar. Estado vigente = el último que no es «propuesto» (sin eventos o «reabierto» = reportado). «propuesto» = el sistema cree que ya se levantó (lo confirma el supervisor).';
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
                      where e.punto_id = p.id and e.tipo <> 'propuesto' order by e.id desc limit 1) u on true;
revoke all on table redes.v_levantar_punto from public, anon, authenticated, service_role;

-- ---------- 2. Consecutivo, parámetros y el formulario asignable ----------
insert into redes.consecutivos (prefijo, ultimo) values ('LEV', 0) on conflict (prefijo) do nothing;
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('levantar_radio_min_m', 15, 'm', 5, 50, 'Encontrar o reportar activo (Corte 14): radio mínimo de búsqueda alrededor de la persona. El radio es el mayor entre este y la precisión del GPS'),
  ('levantar_radio_max_m', 30, 'm', 10, 100, 'Encontrar o reportar activo (Corte 14): tope del radio de búsqueda y de la precisión del GPS. Con peor precisión la pantalla avisa «señal débil» y el punto queda «precisión baja»'),
  ('levantar_duplicado_m', 10, 'm', 1, 50, 'Reportar activo (Corte 14): si ya hay un punto por levantar a menos de esta distancia, se muestra antes de crear otro'),
  ('levantar_lista_max', 30, 'activos', 5, 100, 'Encontrar activo (Corte 14): cuántos activos cercanos se listan como máximo (los más cercanos primero)')
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
        v_desp text := nullif(upper(btrim(coalesce(p_despues_de, ''))), ''); v_items jsonb; v_cont jsonb;
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
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el de producción al publicar) con cambios exactos, aplicados una sola vez.
--   · geoportal_redes_mi_perfil: «activo_campo» (la persona tiene «Encontrar o reportar activo»), para la tarjeta del inicio de Técnica;
--   · campo.f_formularios_personal: una fila más, «Encontrar o reportar activo», en la lista de Personal de Comercial.
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
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las funciones internas nuevas y las reemplazadas: nadie de la API. Las RPC nuevas y las reemplazadas: solo service_role (la Edge geoportal-redes).
-- Las tablas nuevas: nadie de la API (10_esquema.sql): las leen y escriben solo las funciones SECURITY DEFINER.
-- =====================================================================
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname like 'f\_levantar\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
  end loop;
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\_redes\_levantar\_%' or p.proname in ('geoportal_redes_mi_perfil')) loop
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
                    where (p.pronamespace = 'redes'::regnamespace and p.proname like 'f\_levantar\_%') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_levantar\_%')),
        'reemplazadas', jsonb_build_array('geoportal_redes_mi_perfil', 'campo.f_formularios_personal'),
        'fuera_de_redes', jsonb_build_array('tecnica.formulario_clave (clave activo_campo)', 'campo.personal_eventos (CHECK del formulario)', 'campo.f_formularios_personal (una fila más)'),
        'parametros', jsonb_build_array('levantar_radio_min_m', 'levantar_radio_max_m', 'levantar_duplicado_m', 'levantar_lista_max'),
        'motivo', '«Encontrar o reportar activo»: activos cercanos a la persona, puntos por levantar (solo inserción, con estados) y el formulario asignable en Personal'), null);
commit;
