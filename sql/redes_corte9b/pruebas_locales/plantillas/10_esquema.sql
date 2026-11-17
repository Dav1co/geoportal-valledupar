-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1a: simulación de cierre, §17; Fase 1b: cierre real) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte9b_simulacion_alertas.md, §17 y N-9 de la bitácora, corte9b/analisis_cierre_valvulas.md (opción C).
-- · Presupone el Corte 10 publicado (huella del conjunto de funciones de redes {{MD5_BASE}}) y tecnica.f_avisos del Corte 12 (md5 {{MD5_AVISOS}}).
-- · 1a y 1b se publican JUNTAS (David, 17-nov).
-- · La simulación se calcula en cada llamada sobre la red registrada (tablas temporales); aquí solo se guarda lo que el usuario decide guardar
--   con un daño o una intervención: el resultado completo, la huella de la red con la que se calculó y el autor. Solo agregar; nada se borra.
-- · Sin datos de personas: los contratos van como número (Técnica no muestra nombres ni teléfonos en listados).
-- =====================================================================
do $$
begin
  if to_regclass('redes.simulaciones_cierre') is not null then raise exception 'El Corte 9b (Fase 1) ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_BASE}}' then
    raise exception 'Las funciones de redes no son las del Corte 10 publicado (huella {{MD5_BASE}}): deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) <> '{{MD5_AVISOS}}' then
    raise exception 'tecnica.f_avisos no es la del Corte 12 publicado (md5 {{MD5_AVISOS}}): deténgase y avise';
  end if;
  if to_regclass('redes.tramo_nodos') is null or to_regclass('redes.nodos') is null or to_regclass('redes.contrato_tramo') is null or to_regclass('redes.val_amarre') is null then
    raise exception 'Faltan tablas de la red (tramo_nodos, nodos, contrato_tramo) o del Corte 10: deténgase y avise';
  end if;
end $$;

-- ---------- 1. Las simulaciones guardadas (con un daño o una intervención) ----------
create table redes.simulaciones_cierre (
  id              bigint generated always as identity primary key,
  dano_id         uuid references redes.danos (id),
  intervencion_id uuid references redes.intervenciones (id),
  activo_id       bigint not null references redes.activos (id),      -- el tramo o el nodo del trabajo
  red_huella      text not null check (red_huella ~ '^[0-9a-f]{32}$'),      -- la red con la que se calculó (tramos, nodos, válvulas y cómo cuentan)
  valvulas        integer not null check (valvulas >= 0),      -- cuántas válvulas cerrar (escenario estrecho)
  contratos_min   integer not null check (contratos_min >= 0),
  contratos_max   integer not null check (contratos_max >= contratos_min),
  segmento_grande boolean not null,
  resultado       jsonb not null check (jsonb_typeof(resultado) = 'object'),
  contratos       text[] check (contratos is null or cardinality(contratos) <= 200000),      -- los contratos sin agua del escenario estrecho (nulo si pasan del tope)
  ms              integer not null check (ms >= 0),
  autor           text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en       timestamptz not null default clock_timestamp(),
  check (num_nonnulls(dano_id, intervencion_id) = 1)
);
create index ix_sim_cierre_dano on redes.simulaciones_cierre (dano_id, id desc) where dano_id is not null;
create index ix_sim_cierre_itv on redes.simulaciones_cierre (intervencion_id, id desc) where intervencion_id is not null;
comment on table redes.simulaciones_cierre is 'Corte 9b (§17): simulaciones de cierre de válvulas guardadas con un daño o una intervención. Solo agregar. El resultado es el que vio el usuario, con la huella de la red con la que se calculó.';
alter table redes.simulaciones_cierre enable row level security;
revoke all on table redes.simulaciones_cierre from public, anon, authenticated, service_role;
create trigger t_solo_agregar before update or delete on redes.simulaciones_cierre for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.simulaciones_cierre for each statement execute function tecnica.f_solo_agregar();

-- ---------- 2. Parámetros (editables en Parámetros; sus cambios quedan en parametro_eventos) ----------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('sim_segmento_grande_tramos', 200, 'tramos', 10, 20000,
   'Simulación de cierre (Corte 9b): si el sector que se aísla tiene más tramos que esto, es «segmento grande»: con las válvulas registradas no se aísla en pequeño'),
  ('sim_segmento_grande_contratos', 2000, 'contratos', 10, 200000,
   'Simulación de cierre (Corte 9b): si el cierre deja sin agua más contratos que esto, es «segmento grande»'),
  ('sim_no_cierra_max', 4, 'válvulas', 0, 10,
   'Simulación de cierre (Corte 9b): de cuántas válvulas (las más cercanas) se calcula «si esta no cierra»'),
  ('sim_valvulas_lista_max', 30, 'válvulas', 5, 200,
   'Simulación de cierre (Corte 9b): cuántas válvulas se muestran como máximo (las más cercanas); el total siempre se dice'),
  ('sim_contratos_guardar_max', 20000, 'contratos', 0, 200000,
   'Simulación de cierre (Corte 9b): hasta cuántos contratos sin agua se guardan, uno por uno, con la simulación (si son más, solo el conteo)'),
  ('sim_guardadas_max', 20, 'simulaciones', 1, 100,
   'Simulación de cierre (Corte 9b): cuántas simulaciones se pueden guardar como máximo con un mismo daño o intervención')
on conflict (clave) do update set estado = 'vigente', descripcion = excluded.descripcion;

-- ---------- 3. Fase 1b: las maniobras de válvula (el cierre real). Solo agregar: el estado de una válvula es su último «cerrar» sin «abrir» ----------
create table redes.valvula_maniobras (
  id               bigint generated always as identity primary key,
  valvula_id       bigint not null references redes.activos (id),
  tipo             text not null check (tipo in ('cerrar', 'abrir', 'regreso')),      -- «regreso»: ajuste de la hora estimada de regreso del servicio
  cierre_id        bigint references redes.valvula_maniobras (id),      -- «abrir» y «regreso»: el cierre al que pertenecen
  dano_id          uuid references redes.danos (id),
  intervencion_id  uuid references redes.intervenciones (id),
  motivo           text check (motivo is null or length(btrim(motivo)) between 10 and 500),
  regreso_estimado timestamptz,      -- hora estimada de regreso del servicio (la pone quien cierra; el supervisor la ajusta con «regreso»)
  hecho_en         timestamptz not null,      -- cuándo se hizo en campo (puede ser antes del registro, con tope)
  autor            text not null check (autor = lower(autor) and position('@' in autor) > 1),
  registrado_en    timestamptz not null default clock_timestamp(),
  check (num_nonnulls(dano_id, intervencion_id) <= 1),
  check ((tipo = 'cerrar') = (cierre_id is null)),
  check (tipo <> 'regreso' or regreso_estimado is not null),
  check (tipo <> 'abrir' or regreso_estimado is null),
  check (regreso_estimado is null or regreso_estimado > hecho_en),
  check (tipo <> 'cerrar' or dano_id is not null or intervencion_id is not null or motivo is not null)      -- sin daño ni intervención, con motivo
);
create unique index ux_maniobra_abrir on redes.valvula_maniobras (cierre_id) where tipo = 'abrir';      -- un cierre se abre una sola vez
create index ix_maniobra_valvula on redes.valvula_maniobras (valvula_id, id desc);
create index ix_maniobra_cierre on redes.valvula_maniobras (cierre_id, id desc) where cierre_id is not null;
create index ix_maniobra_cerrar on redes.valvula_maniobras (id) where tipo = 'cerrar';
comment on table redes.valvula_maniobras is 'Corte 9b (1b): maniobras de válvula en campo (cerrar, abrir, ajuste de la hora de regreso), con quién, cuándo y el daño o la intervención. Solo agregar.';

-- ---------- 4. Fase 1b: la foto del corte vigente (se saca en cada maniobra; la leen la tesela, la franja y los avisos) ----------
create table redes.corte_fotos (
  id                    bigint generated always as identity primary key,
  maniobra_id           bigint references redes.valvula_maniobras (id),      -- nula si la sacó el supervisor a mano (la red cambió)
  motivo                text check (motivo is null or length(btrim(motivo)) between 10 and 500),
  red_huella            text not null check (red_huella ~ '^[0-9a-f]{32}$'),
  valvulas_cerradas     integer not null check (valvulas_cerradas >= 0),
  valvulas_fuera_de_red integer not null check (valvulas_fuera_de_red >= 0),
  tramos_cerrados       integer not null check (tramos_cerrados >= 0),
  tramos_afectados      integer not null check (tramos_afectados >= 0),
  contratos_cerrados    integer not null check (contratos_cerrados >= 0),
  contratos_afectados   integer not null check (contratos_afectados >= 0),
  zonas                 integer not null check (zonas >= 0),
  ms                    integer not null check (ms >= 0),
  autor                 text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en             timestamptz not null default clock_timestamp(),
  check (maniobra_id is not null or motivo is not null)
);
create table redes.corte_foto_zonas (
  foto_id             bigint not null references redes.corte_fotos (id),
  zona                integer not null check (zona >= 1),
  tramos_cerrados     integer not null check (tramos_cerrados >= 0),
  tramos_afectados    integer not null check (tramos_afectados >= 0),
  contratos_cerrados  integer not null check (contratos_cerrados >= 0),
  contratos_afectados integer not null check (contratos_afectados >= 0),
  lat                 numeric(9,6) not null,
  lon                 numeric(9,6) not null,
  caja                numeric[] not null check (cardinality(caja) = 4),      -- oeste, sur, este, norte (para llevar el mapa a la zona)
  primary key (foto_id, zona)
);
create table redes.corte_foto_tramos (
  foto_id   bigint not null references redes.corte_fotos (id),
  activo_id bigint not null references redes.activos (id),
  papel     text not null check (papel in ('cerrado', 'afectado')),
  zona      integer not null,
  primary key (foto_id, activo_id),
  foreign key (foto_id, zona) references redes.corte_foto_zonas (foto_id, zona) deferrable initially deferred
);
create table redes.corte_foto_valvulas (
  foto_id    bigint not null references redes.corte_fotos (id),
  cierre_id  bigint not null references redes.valvula_maniobras (id),
  valvula_id bigint not null references redes.activos (id),
  en_red     boolean not null,      -- falso: la válvula no es un nodo de la red en operación (no corta nada en el cálculo)
  zona       integer,      -- nula si su cierre no deja a nadie sin agua
  primary key (foto_id, cierre_id)
);
comment on table redes.corte_fotos is 'Corte 9b (1b): foto del corte vigente después de cada maniobra (tramos cerrados y afectados, zonas, contratos). Solo agregar; vale la última.';

do $$
declare t text;
begin
  foreach t in array array['valvula_maniobras', 'corte_fotos', 'corte_foto_zonas', 'corte_foto_tramos', 'corte_foto_valvulas'] loop
    execute format('alter table redes.%I enable row level security', t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', t);
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
end $$;

insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('corte_horas_atras_max', 48, 'horas', 1, 720,
   'Cierre real (Corte 9b): hasta cuántas horas atrás se puede registrar que una válvula se cerró o se abrió (lo hecho en campo y registrado después)')
on conflict (clave) do update set estado = 'vigente', descripcion = excluded.descripcion;

-- ---------- 5. Fase 1b: el aviso «válvula cerrada hace más de X horas» (Avisos del 12, distribución; David: 6 h naranja y 12 h rojo) ----------
insert into tecnica.aviso_parametros (clave, area, valor, minimo, maximo, unidad, orden, nombre, descripcion) values
  ('valvula_cerrada_naranja_h', 'distribucion', 6, 1, 720, 'horas', 162, 'Válvula cerrada: naranja',
   'Una válvula que sigue cerrada (sin «abrir») sale en naranja desde estas horas.'),
  ('valvula_cerrada_rojo_h', 'distribucion', 12, 1, 720, 'horas', 164, 'Válvula cerrada: rojo',
   'Una válvula que sigue cerrada sale en rojo desde estas horas.')
on conflict (clave) do nothing;
