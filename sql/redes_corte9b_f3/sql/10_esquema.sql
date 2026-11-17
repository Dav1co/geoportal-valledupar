-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 (capa «Flujo del agua (modelo)») · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- · Presupone la Fase 2 del 9b publicada: huella del conjunto de funciones de redes 24e62e151ff418ea6acf631572d72683.
-- · SOLO AGREGA: no reemplaza ninguna función. Solo base de datos: las rutas de la Edge y la pantalla del geovisor son del Code B.
-- · El flujo es de MODELO, no medido (modeloV1 del Plan Maestro 2014, corrido en EPANET): va en tablas APARTE, de referencia y de solo inserción, por carga
--   (redes.ref_cargas, conjunto «flujo_modelo»): vale la última no anulada. La tabla queda vacía: se llena con el paquete de carga por psql (carga_flujo/).
-- =====================================================================
do $$
begin
  if to_regclass('redes.flujo_modelo') is not null then raise exception 'La Fase 3 del Corte 9b ya está aplicada: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '24e62e151ff418ea6acf631572d72683' then
    raise exception 'Las funciones de redes no son las de la Fase 2 del Corte 9b (huella 24e62e151ff418ea6acf631572d72683): deténgase y avise';
  end if;
  if to_regclass('redes.ref_cargas') is null or to_regclass('redes.usuarios_sensibles') is null then raise exception 'Faltan tablas del 9a o de la Fase 2: deténgase y avise'; end if;
end $$;

-- ---------- 1. El flujo por tubo del modelo, en la hora de mayor y en la de menor consumo ----------
create table redes.flujo_modelo (
  carga_id       bigint not null references redes.ref_cargas (id),
  llave          text not null check (length(llave) between 1 and 120),      -- el tubo en el modelo
  activo_id      bigint references redes.activos (id),      -- el tramo de la red con que amarra (nulo: no amarró; no se dibuja)
  amarre         text check (amarre in ('llave', 'geometria')),
  geom_mismo     boolean,      -- la geometría del tramo va del nodo inicial al final del tubo del modelo
  q_mayor_lps    numeric not null,      -- con signo: + del nodo inicial al final del modelo
  v_mayor_mps    numeric not null check (v_mayor_mps >= 0),
  sentido_mayor  text not null check (sentido_mayor in ('ini_fin', 'fin_ini', 'sin_flujo')),
  q_menor_lps    numeric not null,
  v_menor_mps    numeric not null check (v_menor_mps >= 0),
  sentido_menor  text not null check (sentido_menor in ('ini_fin', 'fin_ini', 'sin_flujo')),
  primary key (carga_id, llave),
  check ((activo_id is null) = (amarre is null)), check ((activo_id is null) = (geom_mismo is null))
);
create unique index ux_flujo_modelo_activo on redes.flujo_modelo (carga_id, activo_id) where activo_id is not null;      -- un tramo, un tubo
comment on table redes.flujo_modelo is 'Corte 9b (Fase 3): caudal, velocidad y sentido por tubo según el modelo (modeloV1, Plan Maestro 2014; EPANET), en la hora de mayor y de menor consumo. MODELO, no medido. Referencia, solo inserción, por carga.';
create table redes.flujo_modelo_horas (
  carga_id    bigint not null references redes.ref_cargas (id),
  cual        text not null check (cual in ('mayor', 'menor')),
  hora        integer not null check (hora between 0 and 23),
  consumo_lps numeric not null check (consumo_lps >= 0),
  primary key (carga_id, cual)
);
do $$
declare t text;
begin
  foreach t in array array['flujo_modelo', 'flujo_modelo_horas'] loop
    execute format('alter table redes.%I enable row level security', t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', t);
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
end $$;

-- ---------- 2. La capa en la lista del geovisor: queda «en espera» hasta que el Code B tenga la pantalla (flechas, selector de hora y leyenda) ----------
insert into redes.geovisor_capas (codigo, nombre, grupo, fuente, estado, prefijos, por_fecha, solo_completo, nota, orden, activa)
values ('flujo_modelo', 'Flujo del agua (modelo)', 'analisis', 'preparada', 'espera_dato', '{}', false, true,
        'Modelo, no medido (modeloV1, Plan Maestro 2014). Solo supervisores y administrador. Tesela: geoportal_redes_geovisor_mvt_flujo', 77, true)
on conflict (codigo) do update set activa = true, nota = excluded.nota, fuente = excluded.fuente, estado = excluded.estado;
