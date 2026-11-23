-- =====================================================================
-- DOBLES SOLO LOCALES para el Motor SCRR, corte 2 (se cargan en la plantilla local «scrr_plantilla»; NUNCA en Supabase).
-- En producción existen de verdad: hechos.facturacion_sspd (tabla de texto del ETL mensual, 223 mil filas) y redes.f_eventos_del_contrato(text)
-- (aviso de evento por contrato, Técnica, publicado). El doble tiene la MISMA clase de objeto (tabla y función) y la misma firma.
-- =====================================================================
create table if not exists hechos.facturacion_sspd (
  periodo text, contrato text, ruta_lectura text, serial_medidor text, estado_medidor text, determinacion_consumo text,
  lectura_anterior text, lectura_actual text, consumo_periodo text, total_facturado text);
create index if not exists facturacion_sspd_periodo_idx on hechos.facturacion_sspd (periodo);
comment on table hechos.facturacion_sspd is 'DOBLE LOCAL (Code A, SCRR corte 2): misma clase y columnas que la tabla del ETL.';

-- DOBLE de la función de Técnica: devuelve los eventos abiertos que tocan el contrato. Aquí se alimenta de una tabla local de prueba.
create table if not exists redes.zz_doble_eventos_contrato (contrato text not null, evento_id bigint not null);
create or replace function redes.f_eventos_del_contrato(p_contrato text) returns table (evento_id bigint, orden integer)
language sql stable security definer set search_path = redes, public, pg_temp as $$
  select d.evento_id, (row_number() over (order by d.evento_id))::integer from redes.zz_doble_eventos_contrato d where d.contrato = p_contrato $$;
comment on function redes.f_eventos_del_contrato(text) is 'DOBLE LOCAL (Code A, SCRR corte 2): en producción es la función del aviso de evento por contrato.';
revoke all on function redes.f_eventos_del_contrato(text) from public;

-- DOBLE de redes.f_eventos_abiertos(): en producción devuelve setof redes.eventos_suspension; el SCRR solo pregunta si hay alguno abierto
-- (para no consultar contrato por contrato cuando no hay eventos). Aquí: los eventos de la tabla local de prueba.
create table if not exists redes.zz_doble_eventos_abiertos (id bigint primary key);
create or replace function redes.f_eventos_abiertos() returns setof redes.zz_doble_eventos_abiertos
language sql stable security definer set search_path = redes, pg_temp as $$ select distinct d.evento_id from redes.zz_doble_eventos_contrato d $$;
comment on function redes.f_eventos_abiertos() is 'DOBLE LOCAL (Code A, SCRR corte 2): en producción devuelve los eventos de suspensión abiertos.';
revoke all on function redes.f_eventos_abiertos() from public;

-- public.cartera_suscripcion con la estructura EXACTA de producción (David, 22-nov, tras la guardia del ensayo): 23 columnas, id bigint PRIMARY KEY
-- default nextval('cartera_suscripcion_id_seq') al principio y cargado_en timestamptz default now() al final; índices cartera_suscripcion_pkey (id),
-- idx_cartera_contrato (btree contrato) y gin con trigramas sobre upper(direccion), upper(nombre) y serial_medidor. Sin más restricciones.
-- El doble traía 21 columnas (vacía): no se borra, se RENOMBRA (queda aparte, sin uso) y se crea la tabla con el orden de columnas de producción.
create extension if not exists pg_trgm;
alter table public.cartera_suscripcion rename to zz_cartera_suscripcion_21col_doble_viejo;
alter index public.idx_cartera_contrato rename to zz_idx_cartera_contrato_doble_viejo;
create sequence public.cartera_suscripcion_id_seq;
create table public.cartera_suscripcion (
  id bigint not null default nextval('cartera_suscripcion_id_seq'::regclass),
  contrato text not null, estado text, identificacion text, nombre text, correo text, telefono text, direccion text, barrio text, categoria text, subcategoria text, ciclo text,
  facturas_pendientes numeric, deuda_total numeric, saldo_pendiente numeric, saldo_a_favor numeric, valor_reclamo numeric, saldo_financiado numeric,
  serial_medidor text, codigo_reparto text, ruta text, periodo_carga text not null,
  cargado_en timestamp with time zone not null default now(),
  constraint cartera_suscripcion_pkey primary key (id));
alter sequence public.cartera_suscripcion_id_seq owned by public.cartera_suscripcion.id;
create index idx_cartera_contrato on public.cartera_suscripcion using btree (contrato);
create index idx_cartera_direccion_trgm on public.cartera_suscripcion using gin (upper(direccion) gin_trgm_ops);
create index idx_cartera_nombre_trgm on public.cartera_suscripcion using gin (upper(nombre) gin_trgm_ops);
create index idx_cartera_serial_trgm on public.cartera_suscripcion using gin (serial_medidor gin_trgm_ops);
comment on table public.cartera_suscripcion is 'DOBLE LOCAL (Code A, SCRR corte 2): misma estructura e índices que producción (23 columnas).';

-- (David, 22-nov 22:43) NOT NULL de producción: contrato, periodo_carga (sin default), cargado_en (default now()) e id. RLS activado SIN políticas; sin disparadores.
-- En producción dependen de la tabla predios_comercial, predios_comercial_anterior y dos «previa_20261113». Aquí, para que pase lo mismo (una vista que
-- amarra TODAS las columnas y una vista materializada), dos objetos del doble que no se tocan en las pruebas salvo para leerlos y refrescar la materializada.
alter table public.cartera_suscripcion enable row level security;
create view public.zz_doble_depende_cartera as select * from public.cartera_suscripcion;
create materialized view public.zz_doble_depende_cartera_mv as select contrato, saldo_pendiente, periodo_carga, cargado_en from public.cartera_suscripcion;
comment on view public.zz_doble_depende_cartera is 'DOBLE LOCAL: depende de cartera_suscripcion como predios_comercial y sus copias en producción.';
