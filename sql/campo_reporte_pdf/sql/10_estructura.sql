-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov; plan aprobado por David) · 10 — ESTRUCTURA
-- campo.reporte_pdf: una fila por VERSIÓN del PDF de un reporte. Versión nueva solo si cambia el sello del contenido (estado, historial, datos); si no cambió,
-- se entrega la misma. Solo inserción (disparadores de campo.f_solo_agregar, como reporte_fotos), RLS sin políticas, sin permisos para la API, SELECT para
-- homelab_lectura. El archivo va al bucket privado actas-pdf (el de los PDF de los formatos); aquí solo su ruta, sha256 y tamaño. La ruta lleva los 16 primeros
-- caracteres del sha256 del PDF: cada intento de generación sube a su propia ruta y nunca pisa otro archivo (un intento que no llega a registrarse queda sin fila).
-- =====================================================================
-- Tras una reversa la tabla se conserva (nada se borra): si ya existe, la guardia exigió que fuera exactamente la de este paquete y aquí no se toca.
do $estructura$
begin
  if to_regclass('campo.reporte_pdf') is not null then return; end if;
  execute $ddl$
create table campo.reporte_pdf (
  id             bigint generated always as identity primary key,
  reporte_id     uuid not null references campo.reportes (id),
  version        integer not null check (version between 1 and 99),
  sello          text not null check (sello ~ '^[0-9a-f]{64}$'),
  nombre         text not null check (nombre ~ '^[0-9]{14}-RAN-[0-9]{6,12}(-v[0-9]{1,2})?\.pdf$'),
  ruta           text not null unique check (ruta ~ '^campo/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}/[0-9a-f]{16}/[0-9]{14}-RAN-[0-9]{6,12}(-v[0-9]{1,2})?\.pdf$'),
  sha256         text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  bytes          integer not null check (bytes between 200 and 26214400),
  fotos_omitidas integer not null default 0 check (fotos_omitidas >= 0),
  generado_por   text not null check (generado_por = lower(generado_por) and position('@' in generado_por) > 1),
  generado_en    timestamptz not null default clock_timestamp(),
  unique (reporte_id, version),
  unique (reporte_id, sello)
);
comment on table campo.reporte_pdf is 'PDF de cada reporte de «Reportar anomalía» (sigla RAN), por versión; solo inserción. Code A, 27-nov-2026.';
create trigger t_solo_agregar before delete or update on campo.reporte_pdf for each row execute function campo.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on campo.reporte_pdf for each statement execute function campo.f_solo_agregar();
alter table campo.reporte_pdf enable row level security;
revoke all on campo.reporte_pdf from public, anon, authenticated, service_role;
grant select on campo.reporte_pdf to homelab_lectura;
  $ddl$;
end $estructura$;
