-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 10 — GUARDIA, TABLAS Y CATÁLOGO (la línea 116)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code B). Generado por pruebas_locales/generar.py.
-- · Presupone el 9a-bis publicado (huella del conjunto de funciones de redes 814eac39ac5deae2943751b8c190f969) y el Corte 8 publicado (las claves «anomalia_compartida» y
--   «revision_compartida» en el dominio tecnica.formulario_clave).
-- · Los reportes de la línea 116 entran por el Cargue de capas (capa «linea_116», CSV o Excel) o por el paquete de psql (carga_116/). Se reconocen por su número:
--   la primera vez se guarda el reporte (solo se agrega) y su ubicación; después, cada cambio de estado es un evento con fecha. Nada se borra.
-- · NOMBRE, DIRECCION y BARRIO no se guardan nunca (ni en la carga). La ubicación es SOLO por el contrato cruzado con el catastro (David, 16-nov): el reporte
--   cuyo contrato no cruza queda «sin ubicar» (se guarda y se cuenta; no se pinta en el mapa).
-- · Punto 8 (pedido del Code A): los dos formularios compartidos con Comercial entran a los formularios de distribución.
-- =====================================================================
do $$
begin
  if to_regclass('redes.l116_reportes') is not null then raise exception 'El Corte 5d ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '814eac39ac5deae2943751b8c190f969' then
    raise exception 'Las funciones de redes no son las del Corte 9a-bis publicado (huella 814eac39ac5deae2943751b8c190f969): deténgase y avise';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') not like '%''anomalia_compartida''%''revision_compartida''%' then
    raise exception 'El dominio tecnica.formulario_clave no tiene las claves del Corte 8 (anomalia_compartida y revision_compartida): publique antes el Corte 8';
  end if;
  if not exists (select 1 from redes.geovisor_capas where codigo = 'pqr_116' and fuente = 'preparada') then
    raise exception 'La capa «pqr_116» del geovisor no está como la dejó el Corte 6a (preparada): deténgase y avise';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catastro_valledupar' and column_name in ('cod_usuario', 'geom')) <> 2 then
    raise exception 'public.catastro_valledupar no tiene cod_usuario y geom: deténgase y avise';
  end if;
  if exists (select 1 from redes.capas where codigo = 'linea_116' and activa) then raise exception 'Ya existe la capa linea_116: deténgase y avise'; end if;
  if exists (select 1 from redes.formularios_distribucion where clave in ('anomalia_compartida', 'revision_compartida') and activo) then
    raise exception 'Los formularios compartidos ya están en distribución: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. Los reportes (la primera vez que llegan; solo se agregan)
-- ---------------------------------------------------------------------
create table redes.l116_reportes (
  id bigint generated always as identity primary key,
  reporte bigint not null unique check (reporte > 0),
  fecha_registro timestamptz not null,
  servicio text not null check (length(btrim(servicio)) between 1 and 60),
  causal text not null check (length(btrim(causal)) between 1 and 120),
  comuna text check (comuna is null or length(comuna) <= 60),
  contrato text check (contrato is null or contrato ~ '^[0-9]{1,15}$'),
  carga_id bigint not null references redes.cargas(id),
  creado_en timestamptz not null default clock_timestamp());
comment on table redes.l116_reportes is 'Corte 5d: reportes de la línea 116 (uno por número de reporte). Sin nombre, dirección ni barrio: se ubican solo por el contrato (punto del predio).';
create index ix_l116_rep_carga on redes.l116_reportes (carga_id);

-- ---------------------------------------------------------------------
-- 2. Los eventos (alta, cambio de estado, ocultar al revertir una carga, volver a mostrar): solo se agregan
-- ---------------------------------------------------------------------
create table redes.l116_eventos (
  id bigint generated always as identity primary key,
  reporte_id bigint not null references redes.l116_reportes(id),
  tipo text not null check (tipo in ('alta', 'estado', 'ocultar', 'mostrar')),
  estado text check (estado in ('registrado', 'atendido')),
  estado_antes text check (estado_antes in ('registrado', 'atendido')),
  metodo text check (metodo in ('contrato', 'sin_ubicar')),
  geom geometry(Point, 4326),
  sector smallint, subsector text,
  carga_id bigint references redes.cargas(id),
  motivo text check (motivo is null or length(motivo) <= 1000),
  autor text not null,
  creado_en timestamptz not null default clock_timestamp(),
  check ((tipo in ('alta', 'estado')) = (estado is not null)),
  check ((tipo = 'alta') = (metodo is not null)),
  check (geom is null or tipo = 'alta'));
create index ix_l116_ev_rep on redes.l116_eventos (reporte_id, id);
create index ix_l116_ev_carga on redes.l116_eventos (carga_id);

-- ---------------------------------------------------------------------
-- 3. Lo vigente de cada reporte (lo mantiene la publicación a partir de los eventos; es lo que lee la capa del geovisor)
-- ---------------------------------------------------------------------
create table redes.l116_vigente (
  reporte_id bigint primary key references redes.l116_reportes(id),
  reporte bigint not null,
  fecha_registro timestamptz not null,
  dia date not null,      -- día del registro en Bogotá (para agrupar los repetidos)
  servicio text not null, causal text not null, contrato text,
  estado text not null check (estado in ('registrado', 'atendido')),
  estado_desde timestamptz not null,
  metodo text not null check (metodo in ('contrato', 'sin_ubicar')),
  geom geometry(Point, 4326),
  sector smallint, subsector text,
  oculto boolean not null default false,
  actualizado_en timestamptz not null default clock_timestamp());
create index ix_l116_vig_fecha on redes.l116_vigente (fecha_registro) where not oculto;

-- ---------------------------------------------------------------------
-- 4. «Convertir en daño» (todavía sin botón): qué daño salió de qué reporte. Solo se agrega
-- ---------------------------------------------------------------------
create table redes.l116_danos (
  id bigint generated always as identity primary key,
  reporte_id bigint not null references redes.l116_reportes(id),
  dano_id uuid not null references redes.danos(id),
  motivo text not null check (length(btrim(motivo)) between 10 and 1000),
  autor text not null,
  creado_en timestamptz not null default clock_timestamp(),
  unique (reporte_id, dano_id));

-- ---------------------------------------------------------------------
-- 4b. La revisión de una carga (lo que el resumen ya calculó: lo nuevo, lo que cambia de estado y lo que vuelve, con su ubicación). La publicación la usa tal
--     cual: no vuelve a leer el archivo ni a ubicar. Solo se agrega (una carga puede tener varias revisiones; vale la última si la 116 no cambió desde entonces).
-- ---------------------------------------------------------------------
create table redes.l116_revisiones (
  id bigint generated always as identity primary key,
  carga_id bigint not null references redes.cargas(id),
  ultimo_evento bigint not null,      -- el último evento de la 116 cuando se revisó: si después hubo otro, la revisión ya no vale
  resumen jsonb not null,
  creado_en timestamptz not null default clock_timestamp());
create index ix_l116_rev_carga on redes.l116_revisiones (carga_id, id);
create table redes.l116_revision_filas (
  revision_id bigint not null references redes.l116_revisiones(id),
  orden integer not null,
  accion text not null check (accion in ('nuevo', 'estado', 'mostrar')),
  reporte bigint not null, reporte_id bigint,
  fecha timestamptz not null, estado text not null, estado_vigente text,
  servicio text not null, causal text not null, comuna text, contrato text,
  metodo text, geom geometry(Point, 4326), sector smallint, subsector text,
  primary key (revision_id, orden));
create trigger t_solo_agregar before update or delete on redes.l116_revisiones for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.l116_revisiones for each statement execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar before update or delete on redes.l116_revision_filas for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.l116_revision_filas for each statement execute function tecnica.f_solo_agregar();

create trigger t_solo_agregar before update or delete on redes.l116_reportes for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.l116_reportes for each statement execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar before update or delete on redes.l116_eventos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.l116_eventos for each statement execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar before update or delete on redes.l116_danos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.l116_danos for each statement execute function tecnica.f_solo_agregar();

revoke all on table redes.l116_reportes, redes.l116_eventos, redes.l116_vigente, redes.l116_danos, redes.l116_revisiones, redes.l116_revision_filas from public, anon, authenticated, service_role;
revoke all on sequence redes.l116_reportes_id_seq, redes.l116_eventos_id_seq, redes.l116_danos_id_seq, redes.l116_revisiones_id_seq from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5. Catálogo: la capa del Cargue, la del geovisor y los formularios de distribución
-- ---------------------------------------------------------------------
insert into redes.capas (codigo, nombre, grupo, sistema, geometria, prefijo, fuente, derivada_de, columna_llave, formatos, periodicidad_dias, activa, orden, carga_supervisor)
values ('linea_116', 'Reportes de la línea 116', 'calidad_pqr', null, 'punto', null, 'carga', null, 'reporte', '{csv,xlsx}', 31, true, 45, true)
on conflict (codigo) do update set nombre = excluded.nombre, grupo = excluded.grupo, geometria = excluded.geometria, fuente = excluded.fuente, columna_llave = excluded.columna_llave,
  formatos = excluded.formatos, periodicidad_dias = excluded.periodicidad_dias, activa = true, orden = excluded.orden, carga_supervisor = excluded.carga_supervisor;      -- si una reversa la desactivó

update redes.geovisor_capas set fuente = 'geojson', estado = 'activa', por_fecha = true, solo_completo = true, nombre = 'Línea 116 (reportes)',
       nota = 'Por fecha de registro, en el predio de su contrato. Color por servicio (acueducto, alcantarillado, otros); lleno si está registrado, hueco si ya se atendió. Los repetidos del mismo contrato, causal y día van juntos'
 where codigo = 'pqr_116';

-- Punto 8 (pedido del Code A, Corte 8): el supervisor de distribución asigna los dos formularios compartidos con Comercial desde Personal
insert into redes.formularios_distribucion (clave, nombre, orden, activo)
values ('anomalia_compartida', 'Reportar anomalía', 3, true), ('revision_compartida', 'Revisiones generales', 4, true)
on conflict (clave) do update set nombre = excluded.nombre, orden = excluded.orden, activo = true;      -- si una reversa los dejó desactivados, vuelven
