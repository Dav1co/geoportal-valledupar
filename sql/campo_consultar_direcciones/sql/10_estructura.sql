-- =====================================================================
-- CONSULTAR DIRECCIONES (Code A, 25-nov) · 10 — ESTRUCTURA
-- 1. campo.consultas_analisis.via: la MISMA bitácora de consultas registra ahora también la dirección del contrato pedida desde un formato (decisión de David).
--    «analisis» por omisión (lo de antes); «formato» = la ruta direccion_contrato. Nada se borra; la columna es de la bitácora de solo inserción.
-- 2. Parámetro limite_direccion_hora (60 consultas por hora; el supervisor, × multiplo_supervisor; el administrador, sin tope). Los inexistentes también cuentan.
-- 3. campo.reporte_direccion_contrato: FOTO de las dos direcciones del contrato al registrar (base comercial y catastro). Una fila por reporte, solo inserción,
--    RLS sin políticas, sin permisos para la API, SELECT para homelab_lectura. Entra al sello del PDF solo si existe la fila (los reportes de antes no cambian).
-- =====================================================================
alter table campo.consultas_analisis add column if not exists via text not null default 'analisis';
do $via$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'campo.consultas_analisis'::regclass and conname = 'consultas_analisis_via_ck') then
    alter table campo.consultas_analisis add constraint consultas_analisis_via_ck check (via in ('analisis', 'formato'));
  end if;
end $via$;
comment on column campo.consultas_analisis.via is 'Consultar direcciones (25-nov): analisis = Análisis de contrato (Consultar); formato = dirección del contrato pedida desde un formato o Reportar anomalía.';

insert into campo.parametros (clave, valor, unidad, descripcion, minimo, maximo, actualizado_por)
values ('limite_direccion_hora', 60, 'consultas',
        'Consultas por hora de la dirección del contrato desde los formatos (operario; el supervisor, por el múltiplo; el administrador, sin tope). Los contratos inexistentes también cuentan.',
        1, 1000, 'migracion@geoportal')
on conflict (clave) do nothing;

create table if not exists campo.reporte_direccion_contrato (
  reporte_id uuid primary key references campo.reportes (id),
  contrato text not null,
  direccion_comercial text,          -- cartera_suscripcion, último corte
  barrio_comercial text,
  direccion_catastro text,           -- catastro_valledupar, predio principal (menor id)
  barrio_catastro text,
  predios_catastro integer not null default 0,
  creado_en timestamptz not null default clock_timestamp(),
  constraint reporte_direccion_contrato_contrato_ck check (contrato ~ '^[A-Za-z0-9-]{1,20}$'),
  constraint reporte_direccion_contrato_predios_ck check (predios_catastro >= 0)
);
comment on table campo.reporte_direccion_contrato is 'Consultar direcciones (25-nov): las dos direcciones del contrato tal como estaban al registrar el reporte. Una fila por reporte con contrato; solo inserción. Sin fila = reporte anterior a este paquete o sin contrato.';
create or replace trigger t_solo_agregar before delete or update on campo.reporte_direccion_contrato for each row execute function campo.f_solo_agregar();
create or replace trigger t_solo_agregar_trunc before truncate on campo.reporte_direccion_contrato for each statement execute function campo.f_solo_agregar();
alter table campo.reporte_direccion_contrato enable row level security;
revoke all on table campo.reporte_direccion_contrato from public, anon, authenticated, service_role;
grant select on table campo.reporte_direccion_contrato to homelab_lectura;
