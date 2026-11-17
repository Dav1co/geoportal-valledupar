-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1: simulación de cierre, §17) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte9b_simulacion_alertas.md, §17 y N-9 de la bitácora, corte9b/analisis_cierre_valvulas.md (opción C).
-- · Presupone el Corte 10 publicado (huella del conjunto de funciones de redes {{MD5_BASE}}).
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
