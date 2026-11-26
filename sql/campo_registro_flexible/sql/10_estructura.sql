-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 10 — ESTRUCTURA
-- campo.reporte_registro: a lo sumo UNA fila por reporte (llave = reporte_id), de solo inserción (los mismos disparadores que campo.reporte_fotos y
-- campo.reporte_datos_sensibles), RLS activa sin políticas, sin permisos para la API y SELECT para homelab_lectura (decisión de David, 25-nov).
-- Va aparte de campo.reportes para que el sello del PDF de los registros viejos no cambie nunca (ni con este paquete ni tras su reversa):
-- el sello es md5 de to_jsonb(campo.reportes); esta tabla entra al sello solo cuando el reporte tiene su fila.
-- campo.reporte_fotos.origen: camara (por omisión: hasta hoy la cámara era obligatoria, así que es cierto para las fotos viejas), galeria o archivo.
-- =====================================================================
-- Si existe, es la que dejó la reversa de este paquete (la guardia exige su estructura exacta): se conserva tal cual.
create table if not exists campo.reporte_registro (
  reporte_id uuid primary key references campo.reportes (id),
  xy_manual boolean not null,                       -- el XY del punto lo digitó quien registró (solo supervisor o administrador)
  lat_registro numeric(9,6),                        -- dónde estaba quien registró (GPS del dispositivo); nulo = el dispositivo no dio ubicación
  lon_registro numeric(9,6),
  precision_registro_m numeric(8,1),
  direccion text,                                   -- dirección, barrio y referencia: opcionales («¿Quiere agregar dirección?»)
  barrio text,
  referencia text,
  creado_en timestamptz not null default clock_timestamp(),
  constraint reporte_registro_par_ck check ((lat_registro is null) = (lon_registro is null)),
  constraint reporte_registro_lat_ck check (lat_registro is null or (lat_registro between -90 and 90)),
  constraint reporte_registro_lon_ck check (lon_registro is null or (lon_registro between -180 and 180)),
  constraint reporte_registro_precision_ck check (precision_registro_m is null or (lat_registro is not null and precision_registro_m between 0 and 100000)),
  constraint reporte_registro_direccion_ck check (direccion is null or (length(direccion) between 1 and 120 and direccion = btrim(direccion))),
  constraint reporte_registro_barrio_ck check (barrio is null or (length(barrio) between 1 and 80 and barrio = btrim(barrio))),
  constraint reporte_registro_referencia_ck check (referencia is null or (length(referencia) between 1 and 200 and referencia = btrim(referencia)))
);
comment on table campo.reporte_registro is 'Registro flexible (25-nov): dónde estaba quien registró, si el XY fue digitado y la dirección opcional. Una fila por reporte; solo inserción. Sin fila = reporte anterior a este paquete.';
comment on column campo.reporte_registro.xy_manual is 'true = el XY del punto (campo.reportes.lat/lon) lo digitó un supervisor o administrador: «XY digitado — registrado desde otro punto».';
comment on column campo.reporte_registro.lat_registro is 'Posición del dispositivo al registrar (GPS). Nula = «sin ubicación del dispositivo».';
create or replace trigger t_solo_agregar before delete or update on campo.reporte_registro for each row execute function campo.f_solo_agregar();
create or replace trigger t_solo_agregar_trunc before truncate on campo.reporte_registro for each statement execute function campo.f_solo_agregar();
alter table campo.reporte_registro enable row level security;
revoke all on table campo.reporte_registro from public, anon, authenticated, service_role;
grant select on table campo.reporte_registro to homelab_lectura;

alter table campo.reporte_fotos add column if not exists origen text not null default 'camara';
do $origen$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'campo.reporte_fotos'::regclass and conname = 'reporte_fotos_origen_ck') then
    alter table campo.reporte_fotos add constraint reporte_fotos_origen_ck check (origen in ('camara', 'galeria', 'archivo'));
  end if;
end $origen$;
comment on column campo.reporte_fotos.origen is 'Registro flexible (25-nov): camara (la del formulario), galeria o archivo (adjuntadas: solo supervisor o administrador). Las fotos anteriores son de cámara.';
