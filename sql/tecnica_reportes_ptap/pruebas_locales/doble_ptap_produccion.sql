-- =====================================================================
-- DOBLE LOCAL (solo pruebas; NO va en la migración): lo vivo de PLANTA que leen los reportes del PTAP y que el doble de la base de Code A no traía.
-- Copiado de los paquetes publicados de la Torre B (rutas en ~/geoportal-consultas/tecnica/):
--   corte1_paso_a/sql/10_tablas.sql y 20_funciones_internas.sql (f_formularios, f_ahora_bogota, f_marca_rango, índices de registros y exclusiones),
--   corte2_paso_a/sql/20_vistas.sql (v_registros_estado), corte3_paso_a/sql/10_estructura.sql (tipo_punto) y 20_funciones.sql (v_registros_detalle),
--   corte4_resumen_eventos/sql/10_migracion_c4.sql (revisiones_fuera_referencia) y paquete_quimicos_dosis/sql_dosis/10_migracion_dosis.sql (uso_quimicos y sus vistas).
-- Los CHECK de tablas viejas van NOT VALID (rigen para lo que se inserte desde ahora, que es lo que prueban el ensayo y el arnés).
-- =====================================================================
create or replace function tecnica.f_formularios() returns table (clave text, nombre text, descripcion text, orden int)
language sql immutable set search_path to 'pg_catalog' as $$
  values ('entrada',          'Entrada',                           'Agua cruda que ingresa a las plantas.', 1),
         ('salida',           'Salida',                            'Agua tratada que sale de las plantas.', 2),
         ('muestreo',         'Muestreo',                          'Muestreo en los puntos de la red y los tanques.', 3),
         ('danos_fallas',     'Daños o fallas',                    'Daños o fallas en la planta.', 4),
         ('mantenimiento',    'Mantenimiento, reparación e inversión', 'Mantenimiento, reparación e inversión.', 5),
         ('uso_quimicos',     'Uso de químicos',                   'Químicos usados en el proceso.', 6),
         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7);
$$;
create or replace function tecnica.f_ahora_bogota() returns timestamp language sql stable set search_path to 'pg_catalog' as $$
  select clock_timestamp() at time zone 'America/Bogota';
$$;
create or replace function tecnica.f_marca_rango(p_valor numeric, p_min numeric, p_max numeric) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case when p_min is not null and p_valor < p_min then 'bajo'
              when p_max is not null and p_valor > p_max then 'alto' end;
$$;
revoke all on function tecnica.f_formularios(), tecnica.f_ahora_bogota(), tecnica.f_marca_rango(numeric, numeric, numeric) from public, anon, authenticated;

-- variables (Corte 1)
alter table tecnica.variables add column if not exists creado_en timestamptz not null default clock_timestamp();
alter table tecnica.variables add constraint variables_codigo_check check (codigo ~ '^[a-z][a-z0-9_]{1,39}$') not valid;
alter table tecnica.variables add constraint variables_nombre_check check (length(btrim(nombre)) between 2 and 100) not valid;
alter table tecnica.variables add constraint variables_unidad_check check (length(btrim(unidad)) between 1 and 20) not valid;
alter table tecnica.variables add constraint variables_categoria_check check (categoria in ('fisicoquimico', 'caudal', 'nivel', 'otro')) not valid;
alter table tecnica.variables add constraint variables_decimales_check check (decimales between 0 and 6) not valid;

-- formulario_variables (Corte 1, Corte 2 «por_punto» y Corte 3 «tipo_punto»)
alter table tecnica.formulario_variables add column if not exists obligatoria boolean not null default false;
alter table tecnica.formulario_variables add column if not exists punto_id bigint references tecnica.puntos (id);
alter table tecnica.formulario_variables add column if not exists creado_en timestamptz not null default clock_timestamp();
alter table tecnica.formulario_variables add column if not exists tipo_punto text not null default 'muestreo'
  check (tipo_punto in ('macromedicion', 'muestreo', 'tanque', 'distribucion'));
alter table tecnica.formulario_variables add constraint formulario_variables_alcance_check check (alcance in ('por_planta', 'ambas_plantas', 'por_punto')) not valid;
alter table tecnica.formulario_variables add constraint formulario_variables_orden_check check (orden between 1 and 999) not valid;


-- Coherencia de registros (Corte 3, la publicada): una variable «por punto» exige un punto ACTIVO del tipo que declara (tipo_punto). El doble traía la del Corte 2.
create or replace function tecnica.f_tipo_punto_texto(p_tipo text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case p_tipo when 'muestreo' then 'punto de muestreo' when 'tanque' then 'tanque' when 'distribucion' then 'punto de distribución'
                     when 'macromedicion' then 'punto de macromedición' else 'punto' end
$$;
CREATE OR REPLACE FUNCTION tecnica.f_registro_coherente()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $$
declare v_alcance text; v_tipo_req text; v_tipo text; v_activo boolean;
begin
  select fv.alcance, fv.tipo_punto into v_alcance, v_tipo_req from tecnica.formulario_variables fv
   where fv.formulario = new.formulario and fv.variable_id = new.variable_id;
  if v_alcance = 'por_planta' then
    if new.planta_id is null then
      raise exception 'La variable es por planta: falta la planta' using errcode = '22023';
    end if;
    if new.punto_id is not null and tecnica.f_regla_planta_con_punto() then
      raise exception 'La variable es por planta: no lleva punto' using errcode = '22023';
    end if;
  elsif v_alcance = 'ambas_plantas' then
    if new.planta_id is not null then
      raise exception 'La variable es para las dos plantas: no lleva planta' using errcode = '22023';
    end if;
  elsif v_alcance = 'por_punto' then
    if new.punto_id is null then
      raise exception 'La variable es por punto: falta el punto' using errcode = '22023';
    end if;
    if new.planta_id is not null then
      raise exception 'La variable es por punto: no lleva planta' using errcode = '22023';
    end if;
    select pu.tipo, pu.activo into v_tipo, v_activo from tecnica.puntos pu where pu.id = new.punto_id;
    if v_tipo is distinct from v_tipo_req or v_activo is not true then
      raise exception 'La variable es por punto: el punto debe ser un % activo', tecnica.f_tipo_punto_texto(v_tipo_req) using errcode = '22023';
    end if;
  end if;
  return new;
end $$;

-- puntos (Corte 3): el tipo admite también «distribucion» (el doble traía dos CHECK viejos sin él)
alter table tecnica.puntos drop constraint if exists puntos_tipo_check;
alter table tecnica.puntos drop constraint if exists puntos_tipo_check2;
alter table tecnica.puntos add constraint puntos_tipo_check check (tipo in ('macromedicion', 'muestreo', 'tanque', 'distribucion'));

-- registros (Corte 1): índices
create unique index if not exists uq_registro_lote_variable_planta on tecnica.registros (lote_id, variable_id, coalesce(planta_id, 0));
create unique index if not exists uq_registro_clave_envio on tecnica.registros (autor, clave_envio, variable_id, coalesce(planta_id, 0)) where clave_envio is not null;
create index if not exists ix_registros_muestra    on tecnica.registros (muestra_ts desc);
create index if not exists ix_registros_form_fecha on tecnica.registros (formulario, fecha_muestra desc);
create index if not exists ix_registros_variable   on tecnica.registros (variable_id, planta_id, muestra_ts desc);
create index if not exists ix_registros_autor      on tecnica.registros (autor, id desc);
create index if not exists ix_registros_lote       on tecnica.registros (lote_id);
-- exclusiones (Corte 1): índices
create index if not exists ix_exclusiones_registro on tecnica.exclusiones (registro_id, id desc) where registro_id is not null;
create index if not exists ix_exclusiones_lote     on tecnica.exclusiones (lote_id, id desc) where lote_id is not null;

-- v_registros_detalle (Corte 3; la vista de estado es la del Corte 2, que el doble ya tiene igual)
create or replace view tecnica.v_registros_detalle as
select s.id as registro_id, s.lote_id, s.formulario,
       v.codigo as variable, v.nombre as variable_nombre, v.unidad, v.categoria, v.decimales,
       s.valor,
       pl.codigo as planta, pl.nombre as planta_nombre,
       pu.codigo as punto, pu.nombre as punto_nombre,
       s.fecha_muestra, s.hora_muestra, s.muestra_ts, s.registrado_en, s.autor,
       tecnica.f_marca_rango(s.valor, rf.ref_min, rf.ref_max) as fuera_de_rango,
       s.excluido, s.exclusion_motivo, s.exclusion_autor, s.exclusion_en,
       pu.zona, s.fuente,
       rf.ref_min, rf.ref_max, rf.origen as ref_origen, rf.fuente as ref_fuente
from tecnica.v_registros_estado s
join tecnica.variables v on v.id = s.variable_id
left join tecnica.plantas pl on pl.id = s.planta_id
left join tecnica.puntos  pu on pu.id = s.punto_id
left join lateral tecnica.f_referencia_vigente(s.variable_id, coalesce(s.planta_id, pu.planta_id), s.punto_id) rf on true;
revoke all on tecnica.v_registros_detalle from public, anon, authenticated;

-- revisiones_fuera_referencia (Corte 4)
create table if not exists tecnica.revisiones_fuera_referencia (
  id          bigint generated always as identity primary key,
  registro_id bigint not null references tecnica.registros (id),
  accion      text not null check (accion in ('revisado', 'reabierto')),
  nota        text,
  creado_por  text not null check (creado_por = lower(creado_por) and position('@' in creado_por) > 1),
  creado_en   timestamptz not null default clock_timestamp(),
  constraint revisiones_nota_check check (
    (accion = 'revisado' and (nota is null or length(btrim(nota)) between 1 and 500))
    or (accion = 'reabierto' and nota is not null and length(btrim(nota)) between 10 and 500))
);
create index if not exists ix_revisiones_registro on tecnica.revisiones_fuera_referencia (registro_id, id desc);
create trigger t_solo_agregar before update or delete on tecnica.revisiones_fuera_referencia for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.revisiones_fuera_referencia for each statement execute function tecnica.f_solo_agregar();
alter table tecnica.revisiones_fuera_referencia enable row level security;
revoke all on tecnica.revisiones_fuera_referencia from public, anon, authenticated;

-- uso_quimicos (paquete «químicos y dosis»): el doble del 7a era más pobre; está vacío y se rehace igual al publicado
drop table tecnica.uso_quimicos;
create table tecnica.uso_quimicos (
  id            bigint generated always as identity primary key,
  lote_id       uuid not null,
  origen        text not null check (origen in ('entrada', 'uso_quimicos')),
  tipo_uso      text not null check (tipo_uso in ('dosificacion', 'produccion', 'limpieza_filtros', 'otro')),
  quimico_id    bigint not null references tecnica.quimicos (id),
  otro_nombre   text check (otro_nombre is null or length(btrim(otro_nombre)) between 1 and 60),
  planta_id     bigint not null references tecnica.plantas (id),
  dosis         numeric not null check (dosis > 0 and dosis::text not in ('NaN', 'Infinity')),
  unidad        text not null default 'ppm' check (unidad = 'ppm'),
  fecha_muestra date not null,
  hora_muestra  time(0) not null,
  muestra_ts    timestamptz generated always as (((fecha_muestra + hora_muestra) at time zone 'America/Bogota')) stored,
  registrado_en timestamptz not null default clock_timestamp(),
  autor         text not null check (autor = lower(autor) and position('@' in autor) > 1),
  clave_envio   text check (clave_envio is null or clave_envio ~ '^[A-Za-z0-9_-]{8,80}$'),
  constraint ck_uso_quimicos_fecha check (
    fecha_muestra <= (registrado_en at time zone 'America/Bogota')::date
    and fecha_muestra >= (registrado_en at time zone 'America/Bogota')::date - 31),
  constraint ck_uso_quimicos_entrada check (origen <> 'entrada' or tipo_uso = 'dosificacion')
);
create unique index uq_uso_quimicos_entrada on tecnica.uso_quimicos (lote_id, planta_id, tipo_uso) where origen = 'entrada';
create index ix_uso_quimicos_muestra on tecnica.uso_quimicos (muestra_ts desc);
create index ix_uso_quimicos_lote    on tecnica.uso_quimicos (lote_id);
create index ix_uso_quimicos_planta  on tecnica.uso_quimicos (planta_id, fecha_muestra desc);
create trigger t_solo_agregar       before update or delete on tecnica.uso_quimicos for each row       execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate         on tecnica.uso_quimicos for each statement execute function tecnica.f_solo_agregar();
create or replace function tecnica.f_uso_quimicos_coherente() returns trigger
language plpgsql set search_path to 'pg_catalog', 'tecnica', 'pg_temp' as $$
declare q record;
begin
  select qq.activo, qq.pide_nombre, qq.rol into q from tecnica.quimicos qq where qq.id = new.quimico_id;
  if not found or not q.activo then raise exception 'El químico no existe o está desactivado' using errcode = '22023'; end if;
  new.otro_nombre := nullif(btrim(new.otro_nombre), '');
  if q.pide_nombre and new.otro_nombre is null then raise exception 'Falta el nombre del otro químico' using errcode = '22023'; end if;
  if not q.pide_nombre and new.otro_nombre is not null then raise exception 'Solo «Otro» lleva nombre' using errcode = '22023'; end if;
  if new.origen = 'entrada' and q.rol not in ('coagulante', 'otro') then raise exception 'Desde Entrada solo se registra la dosis de un coagulante' using errcode = '22023'; end if;
  if not exists (select 1 from tecnica.plantas p where p.id = new.planta_id and p.activa) then raise exception 'La planta no existe o está inactiva' using errcode = '22023'; end if;
  return new;
end $$;
create trigger t_uso_quimicos_coherente before insert on tecnica.uso_quimicos for each row execute function tecnica.f_uso_quimicos_coherente();
alter table tecnica.uso_quimicos enable row level security;
revoke all on tecnica.uso_quimicos from public, anon, authenticated;
create or replace view tecnica.v_uso_quimicos_estado as
select u.*,
       coalesce(ult.accion = 'EXCLUIR', false) as excluido,
       ult.id        as exclusion_id,
       ult.motivo    as exclusion_motivo,
       ult.autor     as exclusion_autor,
       ult.creado_en as exclusion_en
from tecnica.uso_quimicos u
left join lateral (
  select e.id, e.accion, e.motivo, e.autor, e.creado_en
  from tecnica.exclusiones e
  where e.lote_id = u.lote_id and e.registro_id is null
  order by e.id desc
  limit 1
) ult on true;
revoke all on tecnica.v_uso_quimicos_estado from public, anon, authenticated;
