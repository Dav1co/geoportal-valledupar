-- DOBLE LOCAL (solo pruebas; NO va en la migración): lo vivo que el Corte 6b lee y que la base local de redes no trae.
-- Columnas tomadas de los paquetes vivos: Análisis de contrato (cartera_suscripcion, catastro_valledupar, bi_interno.ficha_contrato y su estado) y
-- Técnica de planta (variables, formulario_variables, registros con «fuente», exclusiones, referencias, v_registros_estado y f_referencia_vigente).
-- Nada de datos reales: las filas las siembra base_chrome.sh (sintéticas) o el ensayo.
alter table public.catastro_valledupar add column if not exists direccion text, add column if not exists barrio text;
create table if not exists public.cartera_suscripcion (contrato text, estado text, identificacion text, nombre text, correo text, telefono text, direccion text, barrio text, categoria text,
  subcategoria text, ciclo text, facturas_pendientes numeric, deuda_total numeric, saldo_pendiente numeric, saldo_a_favor numeric, valor_reclamo numeric, saldo_financiado numeric,
  serial_medidor text, codigo_reparto text, ruta text, periodo_carga text);
create index if not exists idx_cartera_contrato on public.cartera_suscripcion (contrato);
create schema if not exists bi_interno;
create table if not exists bi_interno.ficha_contrato (
  contrato text primary key, periodo_ultimo text not null, uso text, estrato text, ciclo text, consumo_meses jsonb not null, cons_max numeric, cons_min numeric, cons_prom numeric,
  meses_con_lectura integer not null default 0, medidor_serial text, medidor_fecha date, medidor_fecha_estado text not null default 'sin_dato', medidor_anios integer,
  cambio jsonb, submedicion jsonb, emd jsonb not null default '[]', ultimo_pago jsonb, pqr jsonb, facturas_vencidas integer, calculado_en timestamptz not null default clock_timestamp());
create table if not exists bi_interno.ficha_contrato_estado (id integer primary key check (id = 1), firma text not null, filas integer not null, calculado_en timestamptz not null, duracion_ms integer not null);

-- planta (muestreo y referencias)
create table if not exists tecnica.plantas (id bigint generated always as identity primary key, codigo text unique, nombre text);
create table if not exists tecnica.variables (id bigint generated always as identity primary key, codigo text not null unique, nombre text not null, unidad text not null,
  categoria text not null default 'fisicoquimico', decimales smallint not null default 2, ref_min numeric, ref_max numeric, activa boolean not null default true);
create table if not exists tecnica.formulario_variables (id bigint generated always as identity primary key, formulario text not null, variable_id bigint not null references tecnica.variables (id),
  orden smallint not null default 1, alcance text not null default 'por_punto', activa boolean not null default true, unique (formulario, variable_id));
create table if not exists tecnica.registros (id bigint generated always as identity primary key, lote_id uuid not null, formulario text not null, variable_id bigint not null,
  planta_id bigint, punto_id bigint references tecnica.puntos (id), valor numeric not null, fecha_muestra date not null, hora_muestra time(0) not null,
  registrado_en timestamptz not null default clock_timestamp(), autor text not null, clave_envio text, fuente text not null default 'manual' check (fuente in ('manual', 'telemetria')),
  muestra_ts timestamptz generated always as (((fecha_muestra + hora_muestra) at time zone 'America/Bogota')) stored,
  constraint fk_registro_formulario_variable foreign key (formulario, variable_id) references tecnica.formulario_variables (formulario, variable_id));
create table if not exists tecnica.exclusiones (id bigint generated always as identity primary key, registro_id bigint references tecnica.registros (id), lote_id uuid,
  accion text not null default 'EXCLUIR' check (accion in ('EXCLUIR', 'REINCLUIR')), motivo text not null, autor text not null, creado_en timestamptz not null default clock_timestamp());
create table if not exists tecnica.referencias (id bigint generated always as identity primary key, variable_id bigint not null references tecnica.variables (id), planta_id bigint, punto_id bigint,
  ref_min numeric, ref_max numeric, origen text not null, fuente text not null, activa boolean not null default true, creado_en timestamptz not null default clock_timestamp());
create or replace view tecnica.v_registros_estado as
select r.*, coalesce(ult.accion = 'EXCLUIR', false) as excluido, ult.id as exclusion_id, ult.motivo as exclusion_motivo, ult.autor as exclusion_autor, ult.creado_en as exclusion_en
  from tecnica.registros r
  left join lateral (select e.id, e.accion, e.motivo, e.autor, e.creado_en from tecnica.exclusiones e where e.registro_id = r.id or e.lote_id = r.lote_id order by e.id desc limit 1) ult on true;
create or replace function tecnica.f_referencia_vigente(p_variable_id bigint, p_planta_id bigint, p_punto_id bigint)
returns table (ref_min numeric, ref_max numeric, origen text, fuente text)
language sql stable set search_path to 'pg_catalog', 'tecnica' as $$
  select r.ref_min, r.ref_max, r.origen, r.fuente from tecnica.referencias r
   where r.activa and r.variable_id = p_variable_id
     and ((r.punto_id is not null and r.punto_id = p_punto_id) or (r.punto_id is null and r.planta_id is not null and r.planta_id = p_planta_id) or (r.punto_id is null and r.planta_id is null))
   order by case when r.punto_id is not null then 3 when r.planta_id is not null then 2 else 1 end desc limit 1 $$;
insert into tecnica.plantas (codigo, nombre) values ('huaricha', 'Huaricha'), ('gota_fria', 'Gota Fría') on conflict do nothing;
insert into tecnica.variables (codigo, nombre, unidad) values ('turbiedad', 'Turbiedad', 'NTU'), ('cloro_residual_libre', 'Cloro residual libre', 'mg/L'), ('ph', 'pH', 'pH'),
  ('cloro_libre_tanque', 'Cloro libre en tanque', 'mg/L'), ('turbiedad_salida', 'Turbiedad de salida', 'NTU') on conflict do nothing;
insert into tecnica.formulario_variables (formulario, variable_id, orden) select 'muestreo', id, 1 from tecnica.variables where codigo in ('turbiedad', 'cloro_residual_libre', 'ph') on conflict do nothing;
insert into tecnica.formulario_variables (formulario, variable_id, orden, alcance) select 'salida', id, 1, 'por_planta' from tecnica.variables where codigo in ('cloro_libre_tanque', 'turbiedad_salida') on conflict do nothing;
-- referencias de Salida como las vivas (Res. 2115 de 2007): cloro 0,3 a 2,0 mg/L; turbiedad hasta 2 NTU. Una por planta para la turbiedad (prueba la regla «la más estricta»).
insert into tecnica.referencias (variable_id, ref_min, ref_max, origen, fuente)
select id, 0.3, 2.0, 'norma', 'Res. 2115 de 2007, art. 9' from tecnica.variables where codigo = 'cloro_libre_tanque' and not exists (select 1 from tecnica.referencias);
insert into tecnica.referencias (variable_id, planta_id, ref_max, origen, fuente)
select v.id, p.id, case p.codigo when 'huaricha' then 2.0 else 1.5 end, 'criterio_planta', 'Criterio de planta'
  from tecnica.variables v cross join tecnica.plantas p where v.codigo = 'turbiedad_salida' and (select count(*) from tecnica.referencias) = 1;
