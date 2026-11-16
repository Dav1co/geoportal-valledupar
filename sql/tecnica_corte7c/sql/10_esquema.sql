-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 10 — GUARDIA Y ESTRUCTURA: foto de la remisión y parámetros de químicos editables (lo pospuesto del 7a y del 7b)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- · Presupone el 7a publicado (químicos de planta). Todo es del esquema tecnica; ninguna función de redes cambia (su huella sigue igual).
-- · ⚠ Se reemplazan 2 RPC del 7a (geoportal_tec_quimico_entrada y geoportal_tec_quimico_historial), con guardia md5 y su texto exacto en la reversa.
-- · tecnica.quimico_movimientos: UNA columna nueva, «remision_foto» (nula en todo lo que ya existe; solo para las entradas).
-- · Nada se borra; los hechos son de solo inserción. La foto va al bucket privado tecnica-evidencias (ya admite JPEG), con URL firmada desde la Edge.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.quimico_movimientos') is null or to_regclass('tecnica.quimico_parametros') is null then raise exception 'Falta el Corte 7a (químicos de planta): aplíquelo antes'; end if;
  if to_regclass('tecnica.quimico_parametro_eventos') is not null or to_regclass('tecnica.quimico_remision_preparaciones') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'tecnica' and table_name = 'quimico_movimientos' and column_name = 'remision_foto') then
    raise exception 'El Corte 7c ya está aplicado: deténgase y avise';
  end if;
  if (select count(*) from (values {{CAMBIADAS_ANTES}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2 then
    raise exception 'Las RPC de entrada o de historial de químicos no son las del Corte 7a: deténgase y avise';
  end if;
  if not exists (select 1 from storage.buckets where id = 'tecnica-evidencias' and not public and allowed_mime_types @> array['image/jpeg']) then
    raise exception 'El bucket tecnica-evidencias no existe, es público o no admite JPEG: deténgase y avise';
  end if;
  if (select count(*) from tecnica.quimico_parametros where clave in ('desvio_pct', 'marca_esperado_usado', 'dias_atras_uso', 'dias_atras_entrada')) <> 4 then
    raise exception 'Faltan parámetros de químicos del 7a: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. FOTO DE LA REMISIÓN (una por entrada, opcional). La ruta la genera la base y queda anotada a nombre de quien la pidió; la entrada solo acepta una ruta suya y ya subida.
-- ---------------------------------------------------------------------
create table tecnica.quimico_remision_preparaciones (
  ruta      text primary key check (ruta ~ '^remisiones/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.jpg$'),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
comment on table tecnica.quimico_remision_preparaciones is 'Corte 7c: rutas reservadas para la foto de la remisión de una entrada de químicos. Solo inserción.';
alter table tecnica.quimico_movimientos add column remision_foto text;
alter table tecnica.quimico_movimientos add constraint quimico_movimientos_remision_foto_ck
  check (remision_foto is null or (tipo = 'entrada' and remision_foto ~ '^remisiones/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.jpg$'));
create unique index ux_qmov_remision_foto on tecnica.quimico_movimientos (remision_foto) where remision_foto is not null;      -- una foto, una entrada
comment on column tecnica.quimico_movimientos.remision_foto is 'Corte 7c: ruta de la foto de la remisión en el bucket tecnica-evidencias (solo entradas). La ruta nunca sale al navegador: se entrega una URL firmada de 60 s.';

-- ---------------------------------------------------------------------
-- 2. PARÁMETROS EDITABLES, con historial, autor y motivo. Los edita el supervisor de planta o el administrador (el jefe de planta ajusta el desvío del 25 %).
-- ---------------------------------------------------------------------
create table tecnica.quimico_parametro_eventos (
  id        bigint generated always as identity primary key,
  clave     text not null references tecnica.quimico_parametros (clave),
  antes     numeric not null,
  despues   numeric not null,
  motivo    text not null check (length(btrim(motivo)) between 10 and 1000),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
comment on table tecnica.quimico_parametro_eventos is 'Corte 7c: historial de cambios de los parámetros de químicos. Solo inserción.';
insert into tecnica.quimico_parametros values
  ('max_bytes_remision', 3145728, 100000, 5242880, 'Tamaño máximo de la foto de la remisión (bytes)')
on conflict (clave) do nothing;

do $$
begin
  execute 'create trigger t_solo_agregar before update or delete on tecnica.quimico_remision_preparaciones for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on tecnica.quimico_remision_preparaciones for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar before update or delete on tecnica.quimico_parametro_eventos for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on tecnica.quimico_parametro_eventos for each statement execute function tecnica.f_solo_agregar()';
  execute 'alter table tecnica.quimico_remision_preparaciones enable row level security';
  execute 'alter table tecnica.quimico_parametro_eventos enable row level security';
end $$;
