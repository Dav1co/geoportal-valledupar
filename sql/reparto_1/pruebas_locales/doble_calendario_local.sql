-- =====================================================================
-- DOBLES SOLO LOCALES del Reparto de facturas: el calendario del SCRR y el rol del Dell (se cargan en la plantilla local; NUNCA en Supabase).
-- En producción scrr está publicado (huella 722fc84b… del 23-nov = la del repositorio, sql/scrr_corte2): scrr.calendario_ciclos es una TABLA con RLS,
-- 7 restricciones y su disparador de solo inserción, y scrr.v_calendario_vigente una VISTA. Aquí van copiados TAL CUAL de sql/scrr_corte2/sql/10 y 25
-- (misma clase, columnas, restricciones, disparador y definición: la guardia compara sus md5). No se aplica el SCRR entero: crearía el rol scrr_refresco del
-- clúster, que estorba a los guiones del SCRR.
-- homelab_lectura: rol del clúster (en producción existe y lee el respaldo del Dell). Se crea solo si falta, sin login.
-- =====================================================================
create schema if not exists scrr;
revoke all on schema scrr from public, anon, authenticated, service_role;
create or replace function scrr.f_solo_insercion() returns trigger
language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'La tabla %.% es de solo inserción: no se actualiza ni se borra (se anula u oculta con un evento nuevo)', tg_table_schema, tg_table_name
    using errcode = '55000', hint = 'msg_usuario';
end $$;
create table scrr.calendario_ciclos (
  periodo           char(6)     not null check (periodo ~ '^20[0-9]{2}(0[1-9]|1[0-2])$'),
  ciclo             smallint    not null check (ciclo between 1 and 99),
  pago_oportuno     date        not null,
  fecha_suspension  date        not null,
  etapas            jsonb       not null default '{}'::jsonb check (jsonb_typeof(etapas) = 'object'),
  motivo            text        check (motivo is null or length(btrim(motivo)) between 5 and 300),
  autor             text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  vigente_desde     timestamptz not null default clock_timestamp(),
  primary key (periodo, ciclo, vigente_desde),
  constraint fechas_ck check (fecha_suspension >= pago_oportuno)
);
create view scrr.v_calendario_vigente as
  select distinct on (periodo, ciclo) periodo, ciclo, pago_oportuno, fecha_suspension, etapas, motivo, autor, vigente_desde
    from scrr.calendario_ciclos order by periodo, ciclo, vigente_desde desc;
alter table scrr.calendario_ciclos enable row level security;
create trigger calendario_ciclos_solo_insercion before update or delete on scrr.calendario_ciclos for each row execute function scrr.f_solo_insercion();
revoke all on scrr.calendario_ciclos, scrr.v_calendario_vigente from public, anon, authenticated, service_role;
comment on table scrr.calendario_ciclos is 'DOBLE LOCAL (Code A, reparto): copia exacta de la tabla del SCRR (corte 2, publicada).';
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'homelab_lectura') then create role homelab_lectura nologin; end if;
end $$;
