-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como estaban con el 6b y el hotfix de safeupdate (las 3 reemplazadas y las 2 retiradas, con su texto exacto), sin las 2
-- funciones nuevas, y vuelve a crear la copia derivada (redes.contratos_capa y su estado), VACÍA.
-- ⚠ Con la reversa vuelve el problema del 6b: el geovisor intenta rehacer la capa dentro de la petición y en producción se corta a los 30 s.
--   Después de la reversa hay que llenarla a mano en el editor: select redes.f_refrescar_contratos_capa();
-- SE NIEGA si alguna función cambió después de la migración. El 6c no guarda datos: no hay nada que perder.
-- =====================================================================
do $$
begin
  if to_regprocedure('redes.f_funciones_sin_where()') is null then raise exception 'No hay nada que revertir: el Corte 6c no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_6C}}' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 6c: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. la copia derivada, como la creó el 6b (vacía)
create table redes.contratos_capa (
  contrato      text primary key,
  geom          geometry(Point, 4326) not null,
  uso           text,
  estado        text not null check (estado in ('activo', 'retirado', 'otro', 'sin_dato')),
  consumo_prom  numeric,
  medidor_anios integer
);
create index ix_contratos_capa_geom on redes.contratos_capa using gist (geom);
comment on table redes.contratos_capa is 'Corte 6b: capa de contratos del geovisor técnico. Derivada (se rehace entera). Sin datos personales.';
create table redes.contratos_capa_estado (
  id           integer primary key check (id = 1),
  firma        text not null,
  filas        integer not null,
  calculado_en timestamptz not null,
  duracion_ms  integer not null
);
alter table redes.contratos_capa enable row level security;
alter table redes.contratos_capa_estado enable row level security;
revoke all on table redes.contratos_capa, redes.contratos_capa_estado from public, anon, authenticated, service_role;

-- 2. las 2 funciones retiradas y las 3 reemplazadas, con su texto del 6b + hotfix
{{TEXTOS_ANTES}}
-- 3. lo nuevo
drop function redes.f_funciones_sin_where();
drop function redes.f_contrato_uso(text, text);
update redes.parametros set descripcion = 'Geovisor: la capa de contratos se rehace si tiene más de estas horas o si cambió la ficha del contrato'
 where clave = 'geovisor_contratos_horas';
update redes.geovisor_capas set nota = 'Desde el zoom 16. Al tocar un contrato: su consumo, nombre y dirección (la consulta queda registrada)'
 where codigo = 'contratos';

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_HOTFIX}}' then
    raise exception 'La reversa no dejó la base como en el 6b con el hotfix';
  end if;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte6c', 'reversa_redes_corte6c', null, jsonb_build_object('nota', 'vuelve la copia derivada, vacía: llenarla con redes.f_refrescar_contratos_capa()'), null);
