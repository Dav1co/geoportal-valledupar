-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 10 — GUARDIA Y ESQUEMA («Encontrar o reportar activo» y los puntos por levantar)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code B). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte14_encontrar_reportar_activo.md (17-nov) y el plan de David del 17-nov (14:05–14:48): todo el corte lo hace Code B, por etapas.
-- · Presupone el Corte 9b publicado completo (huella del conjunto de funciones de redes {{MD5_BASE}}).
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
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_BASE}}' then
    raise exception 'Las funciones de redes no son las del Corte 9b publicado completo (huella {{MD5_BASE}}): deténgase y avise';
  end if;
  if to_regclass('redes.formularios_distribucion') is null or to_regclass('redes.consecutivos') is null or to_regclass('tecnica.personal_tecnico_eventos') is null then
    raise exception 'Faltan tablas de los cortes anteriores (5a): deténgase y avise';
  end if;
  -- 9 claves (Corte 8) o, si hubo una reversa del 14, las 10 (la reversa no puede quitar la clave: el formulario queda desactivado, no borrado)
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck')
     not in ('{{DEF_DOMINIO}}', '{{DEF_DOMINIO_14}}') then
    raise exception 'El dominio tecnica.formulario_clave no tiene las 9 claves esperadas (Corte 8): deténgase y avise';
  end if;
  if to_regprocedure('campo.f_formularios_personal()') is null or md5(pg_get_functiondef('campo.f_formularios_personal()'::regprocedure)) <> '{{MD5_CAMPO_FORM}}' then
    raise exception 'campo.f_formularios_personal no es la de la pasada del 14-nov (huella {{MD5_CAMPO_FORM}}): deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamptz)'::regprocedure)) <> '{{MD5_AVISOS}}' then
    raise exception 'tecnica.f_avisos no es la de la Fase 2 del 9b (huella {{MD5_AVISOS}}): deténgase y avise';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_eventos_formulario_check') is distinct from '{{DEF_CHECK_CAMPO}}' then
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
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') = '{{DEF_DOMINIO}}' then
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
