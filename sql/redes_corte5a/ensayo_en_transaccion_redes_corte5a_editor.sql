begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 10 — GUARDIA Y TABLAS NUEVAS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: §28 y §26.3 de la bitácora, pendientes 17c y 17f, 01 sección E (capa MUE) y §4 de hallazgos_capas_redes_15nov.md.
-- · Presupone el 4b aplicado (huella del conjunto de funciones de redes, de v_dano y de v_epicrisis, y de las 4 funciones de permisos del 4a).
-- · ⚠ tecnica.puntos está VIVA: este corte no la altera. Solo le AGREGA filas (puntos nuevos de una carga MUE) y cambia «activo» con un evento en
--   tecnica.punto_eventos; nunca borra. La ubicación va en la tabla lateral tecnica.puntos_ubicacion (D-24), de solo inserción.
-- · ⚠ tecnica.personal_tecnico_eventos está VIVA: no se altera; la RPC nueva del supervisor de distribución solo INSERTA eventos de asignar o quitar
--   los formularios de distribución, igual que las de planta (que no se tocan).
-- · ⚠ Se reemplazan 4 funciones del motor del 1a (vivas) y 5 RPC de los Cortes 4a y 4b, con su texto exacto en la reversa (guardia por la huella del conjunto).
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.personal_ficha_eventos') is null or to_regclass('redes.cuadrillas') is null then raise exception 'Falta el Corte 4b: aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '55668dddf263065b5eb90aeb3001a3b7' then
    raise exception 'Las funciones de redes no son las del Corte 4b (o el Corte 5a ya está aplicado): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_dano'::regclass, true)) <> 'bee1b39d753fc55ae7cb85a3952896fb' or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> 'a1e45ec72cb5b254a67698111994746a' then
    raise exception 'Las vistas v_dano o v_epicrisis no son las del 4b: deténgase y avise';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_puede', '32f174a55b95788d3f8187b507303c2f'), ('geoportal_mis_permisos', '83166fe17be58da67bbdedaae429bedb'), ('geoportal_admin_permisos', 'e5a90103b4a83440fd826f03266b7245'), ('geoportal_admin_listar', 'd7311a32ea03cccd6c83691e63ba10bc'))) <> 4 then
    raise exception 'Las 4 funciones de permisos no son las del Corte 4a: deténgase y avise';
  end if;
  if to_regclass('tecnica.puntos_ubicacion') is not null or to_regclass('tecnica.punto_eventos') is not null or to_regclass('redes.formularios_distribucion') is not null
     or exists (select 1 from redes.capas where codigo = 'muestreo' and activa) then
    raise exception 'Las tablas del 5a o la capa «muestreo» ya existen: el Corte 5a parece aplicado';
  end if;
  -- lo vivo que se usa, con la forma esperada
  if (select count(*) from information_schema.columns where table_schema = 'tecnica' and table_name = 'puntos'
       and column_name in ('id', 'codigo', 'nombre', 'tipo', 'activo', 'zona', 'barrio', 'numero_informe')) <> 8 then
    raise exception 'tecnica.puntos no tiene las columnas esperadas (id, codigo, nombre, tipo, activo, zona, barrio, numero_informe): deténgase y avise';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'tecnica.puntos'::regclass and tgname = 't_no_borrar' and not tgisinternal) then
    raise exception 'tecnica.puntos no tiene su candado t_no_borrar: deténgase y avise';
  end if;
  if to_regclass('tecnica.senal_cambio') is null or to_regprocedure('tecnica.f_formulario_asignado(text,text)') is null then
    raise exception 'Faltan tecnica.senal_cambio o tecnica.f_formulario_asignado';
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'tecnica' and t.typname = 'formulario_clave') then
    raise exception 'Falta el dominio tecnica.formulario_clave';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. UBICACIÓN DE LOS PUNTOS DE MUESTREO (D-24): tabla lateral, solo inserción. La vigente es la última por punto que no sea de una carga revertida.
--    exactitud: verificada (David o GPS aprobado) o aproximada (centro del barrio). fuente: david, barrio, gps_operador (Corte 5b) o carga (archivo).
-- ---------------------------------------------------------------------
create table tecnica.puntos_ubicacion (
  id          bigint generated always as identity primary key,
  punto_id    bigint not null references tecnica.puntos (id),
  lat         numeric(9, 6) not null check (lat between -90 and 90),
  lon         numeric(9, 6) not null check (lon between -180 and 180),
  geom        geometry(Point, 4326) generated always as (ST_SetSRID(ST_MakePoint(lon::double precision, lat::double precision), 4326)) stored,
  exactitud   text not null check (exactitud in ('verificada', 'aproximada')),
  fuente      text not null check (fuente in ('david', 'barrio', 'gps_operador', 'carga')),
  barrio_capa text check (barrio_capa is null or length(btrim(barrio_capa)) between 1 and 120),
  carga_id    bigint references redes.cargas (id),
  autor       text not null,
  creado_en   timestamptz not null default clock_timestamp()
);
create index ix_pu_punto on tecnica.puntos_ubicacion (punto_id, id desc);
create index ix_pu_geom on tecnica.puntos_ubicacion using gist (geom);
comment on table tecnica.puntos_ubicacion is 'Ubicación de los puntos de tecnica.puntos (D-24). Solo inserción; la vigente es la última por punto que no sea de una carga revertida. La carga la capa MUE del Cargue de capas (Corte 5a).';

-- Eventos de los puntos que cambia una carga MUE: crear (punto nuevo), desactivar (no vino en la versión) y reactivar. Solo inserción.
create table tecnica.punto_eventos (
  id        bigint generated always as identity primary key,
  punto_id  bigint not null references tecnica.puntos (id),
  tipo      text not null check (tipo in ('crear', 'desactivar', 'reactivar')),
  motivo    text not null check (length(btrim(motivo)) between 10 and 1000),
  carga_id  bigint references redes.cargas (id),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
create index ix_pe_punto on tecnica.punto_eventos (punto_id, id desc);
comment on table tecnica.punto_eventos is 'Eventos de los puntos de muestreo que cambia la capa MUE (crear, desactivar, reactivar). Solo inserción. tecnica.puntos.activo sigue al último evento.';
do $$
declare t text;
begin
  foreach t in array array['puntos_ubicacion', 'punto_eventos'] loop
    execute format('create trigger t_solo_agregar before update or delete on tecnica.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on tecnica.%I for each statement execute function tecnica.f_solo_agregar()', t);
    execute format('alter table tecnica.%I enable row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2. FORMULARIOS DEL GRUPO DISTRIBUCIÓN (§28.2): los que el supervisor de distribución asigna desde Personal. El Corte 8 agrupa los formularios;
--    mientras tanto, esta lista. Se agregan filas; no se borran (se desactivan).
-- ---------------------------------------------------------------------
create table redes.formularios_distribucion (
  clave   tecnica.formulario_clave primary key,
  nombre  text not null check (length(btrim(nombre)) between 2 and 80),
  orden   integer not null default 0,
  activo  boolean not null default true
);
insert into redes.formularios_distribucion (clave, nombre, orden) values ('danos_fallas', 'Reportar daño o falla', 1), ('mantenimiento', 'Registrar intervención', 2);
create trigger t_no_borrar before delete on redes.formularios_distribucion for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on redes.formularios_distribucion for each statement execute function tecnica.f_solo_agregar();
alter table redes.formularios_distribucion enable row level security;

-- ---------------------------------------------------------------------
-- 3. CAPA MUE (01 sección E) y el tope de días atrás del supervisor (§28.1)
-- ---------------------------------------------------------------------
insert into redes.capas (codigo, nombre, grupo, sistema, geometria, prefijo, fuente, derivada_de, columna_llave, formatos, orden)
values ('muestreo', 'Puntos de muestreo de calidad del agua (MUE)', 'calidad_pqr', null, 'punto', null, 'carga', null, 'codigo', '{csv,xlsx,shp,geojson,kml}', 40)
on conflict (codigo) do update set activa = true;      -- si una reversa la dejó inactiva (las capas no se borran)
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('itv_dias_atras_max_supervisor', 30, 'días', 1, 90, 'Cuánto atrás puede empezar una intervención que registra el supervisor de distribución o el administrador (§28.1); el operador sigue con itv_dias_atras_max')
on conflict (clave) do nothing;      -- una reversa lo deja (los parámetros no se borran)
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 20 — FUNCIONES Y VISTA NUEVAS (internas: nadie de la API las ejecuta)
-- PROPUESTA. No se ha ejecutado en la base real.
--   · redes.f_fusionar_ficha: en una recarga GANA LO EDITADO EN LA FICHA (§26.3) y arma la lista de choques para el resumen (pendientes 17c).
--   · la capa MUE: candidatos, resumen, publicar y revertir sobre tecnica.puntos (solo agrega y cambia «activo» con evento) y tecnica.puntos_ubicacion.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. RECARGA: GANA LA FICHA (§26.3)
--    Trabaja sobre la tabla temporal _cand que arma f_preparar_candidatos (la usan resumen y publicar en la misma transacción).
--    · Campos «de la ficha»: los que alguna vez se editaron en la ficha del activo (redes.ficha_ediciones), salvo alias y placa (no van en la versión).
--      La capa no los pisa: la versión nueva toma el valor vigente en esos campos y el de la capa en los demás (la geometría siempre es de la capa).
--    · Fecha de instalación y barrio o sector no vienen en ninguna capa: se conservan siempre (antes una recarga los dejaba vacíos).
--    · El origen corregido en la ficha tampoco lo pisa la capa (lo respeta publicar).
--    · Choque = campo de la ficha que la capa TRAE con otro valor (si la capa no trae el dato, no es choque: simplemente gana la ficha).
--      Se listan en _choques; no bloquean la publicación.
--    · Con la fusión se recalcula la huella: si ya no hay diferencia, la fila queda «igual» y no crea versión.
-- ---------------------------------------------------------------------
create function redes.f_fusionar_ficha() returns integer
language plpgsql set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
declare n integer;
begin
  if to_regclass('pg_temp._choques') is not null then drop table pg_temp._choques; end if;
  create temp table _choques (activo_id bigint, codigo text, campo text, valor_ficha text, valor_capa text) on commit drop;
  alter table _cand add column campos_ficha text[], add column fecha_instalacion date, add column barrio_sector text;
  -- lo que no viene en ninguna capa se conserva siempre
  update _cand k set fecha_instalacion = v.fecha_instalacion, barrio_sector = v.barrio_sector
    from redes.v_activo_vigente v where v.activo_id = k.activo_id and k.accion in ('cambiado', 'igual', 'reactivar');
  update _cand k set campos_ficha = f.campos
    from (select e.activo_id, array_agg(distinct x ->> 'campo') as campos
            from redes.ficha_ediciones e cross join jsonb_array_elements(e.cambios) x
           where x ->> 'campo' not in ('alias', 'placa') group by e.activo_id) f
   where f.activo_id = k.activo_id and k.accion in ('cambiado', 'igual', 'reactivar');
  -- choques: lo que la capa trae distinto en un campo de la ficha (observaciones no viene de ninguna capa: no es choque)
  insert into _choques (activo_id, codigo, campo, valor_ficha, valor_capa)
  select k.activo_id, k.codigo, c.campo, c.vf, c.vc
    from _cand k join redes.v_activo_vigente v on v.activo_id = k.activo_id
   cross join lateral (values ('nombre', v.nombre, k.nombre), ('estado_codigo', v.estado_codigo, k.estado_codigo), ('clase', v.clase, k.clase),
                              ('efecto', v.efecto, k.efecto), ('material_codigo', v.material_codigo, k.material_codigo),
                              ('diametro_mm', trim_scale(v.diametro_mm)::text, trim_scale(k.diametro_mm)::text), ('capacidad', trim_scale(v.capacidad)::text, trim_scale(k.capacidad)::text),
                              ('profundidad_m', trim_scale(v.profundidad_m)::text, trim_scale(k.profundidad_m)::text)) c(campo, vf, vc)
   where k.campos_ficha is not null and c.campo = any (k.campos_ficha) and c.vc is not null and c.vf is distinct from c.vc
  union all
  select k.activo_id, k.codigo, x, v.atributos ->> substr(x, 11), k.atributos ->> substr(x, 11)
    from _cand k join redes.v_activo_vigente v on v.activo_id = k.activo_id cross join unnest(k.campos_ficha) x
   where x like 'atributos.%' and k.atributos ? substr(x, 11) and (v.atributos -> substr(x, 11)) is distinct from (k.atributos -> substr(x, 11))
  union all
  select k.activo_id, k.codigo, 'origen', coalesce(o.origen, '') || coalesce(' · ' || o.aportante_codigo, ''), coalesce(k.origen, '') || coalesce(' · ' || k.aportante_codigo, '')
    from _cand k join redes.v_activo_origen_vigente o on o.activo_id = k.activo_id
   where 'origen' = any (k.campos_ficha) and (o.origen is distinct from k.origen or o.aportante_codigo is distinct from k.aportante_codigo);
  -- la fusión: en los campos de la ficha queda el valor vigente
  update _cand k set
         nombre = case when 'nombre' = any (k.campos_ficha) then v.nombre else k.nombre end,
         estado_codigo = case when 'estado_codigo' = any (k.campos_ficha) then v.estado_codigo else k.estado_codigo end,
         clase = case when 'clase' = any (k.campos_ficha) then v.clase else k.clase end,
         efecto = case when 'efecto' = any (k.campos_ficha) then v.efecto else k.efecto end,
         material_codigo = case when 'material_codigo' = any (k.campos_ficha) then v.material_codigo else k.material_codigo end,
         diametro_mm = case when 'diametro_mm' = any (k.campos_ficha) then v.diametro_mm else k.diametro_mm end,
         capacidad = case when 'capacidad' = any (k.campos_ficha) then v.capacidad else k.capacidad end,
         profundidad_m = case when 'profundidad_m' = any (k.campos_ficha) then v.profundidad_m else k.profundidad_m end,
         atributos = k.atributos || coalesce((select jsonb_object_agg(a.key, a.value) from jsonb_each(v.atributos) a
                                               where a.key = 'observaciones' or ('atributos.' || a.key) = any (k.campos_ficha)), '{}'::jsonb)
                     - array(select substr(x, 11) from unnest(k.campos_ficha) x where x like 'atributos.%' and not (v.atributos ? substr(x, 11)))
    from redes.v_activo_vigente v
   where v.activo_id = k.activo_id and (k.campos_ficha is not null or v.atributos ? 'observaciones');
  -- huella y acción de nuevo, con lo fusionado
  update _cand k set huella = redes.f_huella(k.geom, jsonb_build_object('p', k.prefijo, 'n', k.nombre, 'c', k.clase, 'e', k.efecto, 'm', k.material_codigo, 'd', k.diametro_mm,
                                                                    'l', k.longitud_m, 'pr', k.profundidad_m, 'ca', k.capacidad, 's', k.estado_codigo,
                                                                    'ant', k.codigo_anterior, 'a', k.atributos))
   where k.accion in ('cambiado', 'igual', 'reactivar');
  update _cand k set accion = case when k.huella_vigente = k.huella then case when k.retirado_vigente then 'reactivar' else 'igual' end else 'cambiado' end
   where k.accion in ('cambiado', 'igual', 'reactivar');
  select count(*) into n from _choques;
  return n;
end $f$;

-- ---------------------------------------------------------------------
-- 2. CAPA MUE (puntos de muestreo, 01 sección E)
-- ---------------------------------------------------------------------
-- Ubicación vigente de cada punto: la última que no sea de una carga revertida.
create view redes.v_punto_ubicacion_vigente as
select distinct on (u.punto_id) u.*
  from tecnica.puntos_ubicacion u
 where u.carga_id is null or not exists (select 1 from redes.carga_eventos e where e.carga_id = u.carga_id and e.tipo = 'revertir')
 order by u.punto_id, u.id desc;

-- Candidatos de una carga MUE (tabla temporal _mue). Columnas del archivo: codigo (la llave; vacía = el siguiente MUE-nn), nombre, zona, barrio,
-- exactitud (o «precision»: verificada | aproximada; por omisión aproximada) y fuente (david | barrio | carga; por omisión carga).
create function redes.f_candidatos_muestreo(p_carga bigint) returns void
language plpgsql set search_path to 'redes', 'tecnica', 'public', 'extensions', 'pg_temp' as $f$
begin
  if to_regclass('pg_temp._mue') is not null then drop table pg_temp._mue; end if;
  create temp table _mue on commit drop as
  select cf.orden, upper(nullif(btrim(cf.llave), '')) as codigo, nullif(btrim(cf.atributos ->> 'nombre'), '') as nombre,
         lower(nullif(btrim(cf.atributos ->> 'zona'), '')) as zona, nullif(btrim(cf.atributos ->> 'barrio'), '') as barrio,
         lower(coalesce(nullif(btrim(cf.atributos ->> 'exactitud'), ''), nullif(btrim(cf.atributos ->> 'precision'), ''), 'aproximada')) as exactitud,
         lower(coalesce(nullif(btrim(cf.atributos ->> 'fuente'), ''), 'carga')) as fuente,
         case when cf.geom is not null and ST_GeometryType(cf.geom) = 'ST_Point' then round(ST_Y(cf.geom)::numeric, 6) end as lat,
         case when cf.geom is not null and ST_GeometryType(cf.geom) = 'ST_Point' then round(ST_X(cf.geom)::numeric, 6) end as lon,
         coalesce(cf.error, case when ST_GeometryType(cf.geom) <> 'ST_Point' then 'No es un punto' end) as error,
         p.id as punto_id, p.tipo as tipo_vigente, p.activo as activo_vigente, p.nombre as nombre_vigente,
         u.lat as lat_vigente, u.lon as lon_vigente, u.exactitud as exactitud_vigente, null::text as accion, null::text as codigo_nuevo
    from redes.carga_filas cf
    left join tecnica.puntos p on p.codigo = upper(nullif(btrim(cf.llave), ''))
    left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
   where cf.carga_id = p_carga;
  update _mue set accion = case when codigo is null then 'nuevo_sin_codigo'
                                when punto_id is null then 'nuevo'
                                when not activo_vigente then 'reactivar'
                                when lat_vigente is distinct from lat or lon_vigente is distinct from lon or exactitud_vigente is distinct from exactitud then 'ubicacion'
                                else 'igual' end;
end $f$;

create function redes.f_resumen_muestreo(p_carga bigint) returns jsonb
language plpgsql set search_path to 'redes', 'tecnica', 'public', 'extensions', 'pg_temp' as $f$
declare c redes.v_cargas_estado%rowtype; v_rec integer; v_bloq text[] := '{}'; v_avisos text[] := '{}'; v_tabla jsonb; v_acc jsonb; v_desac jsonb; v_n integer;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  select count(*) into v_rec from redes.carga_filas where carga_id = p_carga;
  if c.estado <> 'abierta' then v_bloq := v_bloq || ('La carga está ' || c.estado); end if;
  if v_rec <> c.filas_esperadas then v_bloq := v_bloq || format('Llegaron %s de %s filas: falta algún lote', v_rec, c.filas_esperadas); end if;
  perform redes.f_candidatos_muestreo(p_carga);
  select count(*) into v_n from _mue where error is not null;
  if v_n > 0 then v_bloq := v_bloq || format('%s filas sin un punto válido: %s', v_n, (select string_agg(coalesce(codigo, 'fila ' || orden) || ' (' || error || ')', ', ') from _mue where error is not null)); end if;
  select count(*) into v_n from (select codigo from _mue where codigo is not null group by codigo having count(*) > 1) x;
  if v_n > 0 then v_bloq := v_bloq || format('%s códigos repetidos en el archivo', v_n); end if;
  if exists (select 1 from _mue where codigo is not null and codigo !~ '^MUE-[0-9]{2,4}$') then
    v_bloq := v_bloq || ('Los códigos de los puntos de muestreo son MUE-nn: ' || (select string_agg(codigo, ', ') from _mue where codigo is not null and codigo !~ '^MUE-[0-9]{2,4}$'));
  end if;
  if exists (select 1 from _mue where tipo_vigente is not null and tipo_vigente <> 'muestreo') then
    v_bloq := v_bloq || ('Estos códigos son de otro tipo de punto: ' || (select string_agg(codigo, ', ') from _mue where tipo_vigente is not null and tipo_vigente <> 'muestreo'));
  end if;
  if exists (select 1 from _mue where accion in ('nuevo', 'nuevo_sin_codigo') and (nombre is null or length(nombre) not between 2 and 120)) then
    v_bloq := v_bloq || 'Un punto nuevo necesita su nombre (2 a 120 caracteres)'::text;
  end if;
  if exists (select 1 from _mue where exactitud not in ('verificada', 'aproximada')) then v_bloq := v_bloq || 'La exactitud es «verificada» o «aproximada»'::text; end if;
  if exists (select 1 from _mue where fuente not in ('david', 'barrio', 'carga')) then v_bloq := v_bloq || 'La fuente es «david», «barrio» o «carga» (el GPS del operador entra por el formulario)'::text; end if;
  if exists (select 1 from _mue where zona is not null and zona not in ('norte', 'sur', 'medio')) then v_bloq := v_bloq || 'La zona es norte, sur o medio'::text; end if;
  if exists (select 1 from _mue where barrio is not null and length(barrio) > 120) then v_bloq := v_bloq || 'El barrio admite hasta 120 caracteres'::text; end if;
  if exists (select 1 from _mue where lat is not null and (lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max'))) then
    v_bloq := v_bloq || ('Puntos fuera de Valledupar (revise el sistema de coordenadas): ' || (select string_agg(coalesce(codigo, 'fila ' || orden), ', ') from _mue
                                  where lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max')));
  end if;
  if exists (select 1 from _mue where punto_id is not null and nombre is not null and redes.f_norm(nombre) <> redes.f_norm(nombre_vigente)) then
    v_avisos := v_avisos || ('El nombre del archivo no es el de tecnica.puntos (no se cambia): ' || (select string_agg(codigo || ' «' || nombre || '» / «' || nombre_vigente || '»', ', ')
                               from _mue where punto_id is not null and nombre is not null and redes.f_norm(nombre) <> redes.f_norm(nombre_vigente)));
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre) order by p.codigo), '[]'::jsonb) into v_desac
    from tecnica.puntos p where p.tipo = 'muestreo' and p.activo and not exists (select 1 from _mue m where m.codigo = p.codigo);
  if jsonb_array_length(v_desac) > 0 then
    v_avisos := v_avisos || format('%s puntos activos no vienen en el archivo: se DESACTIVAN y salen del formulario de Muestreo desde la publicación (sus registros siguen): %s',
                                   jsonb_array_length(v_desac), (select string_agg(x ->> 'codigo', ', ') from jsonb_array_elements(v_desac) x));
  end if;
  select coalesce(jsonb_object_agg(accion, n order by accion), '{}'::jsonb) into v_acc from (select accion, count(*) n from _mue group by accion) x;
  v_tabla := jsonb_build_array(
      jsonb_build_object('s', '1 carga', 'c', 'capa', 'v', 'muestreo'), jsonb_build_object('s', '1 carga', 'c', 'carga', 'v', c.id || ' (' || c.estado || ')'),
      jsonb_build_object('s', '1 carga', 'c', 'filas recibidas / esperadas', 'v', v_rec || ' / ' || c.filas_esperadas))
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '2 frente a lo vigente', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_acc))
    || jsonb_build_array(jsonb_build_object('s', '2 frente a lo vigente', 'c', 'desactivar (no vienen)', 'v', jsonb_array_length(v_desac)::text))
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '3 puntos', 'c', coalesce(m.codigo, 'fila ' || m.orden) || ' ' || coalesce(m.nombre, m.nombre_vigente, ''),
                                                    'v', m.accion || ' · ' || m.exactitud || ' (' || m.fuente || ')' || coalesce(' · barrio ' || m.barrio, '')
                                                         || coalesce(' · ' || m.lat || ', ' || m.lon, '')) order by m.codigo nulls last, m.orden), '[]'::jsonb) from _mue m)
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '7 avisos', 'c', 'aviso', 'v', a)), '[]'::jsonb) from unnest(v_avisos) a)
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '8 bloqueos', 'c', 'BLOQUEO', 'v', b)), '[]'::jsonb) from unnest(v_bloq) b)
    || jsonb_build_array(jsonb_build_object('s', '9 resultado', 'c', 'lista para publicar', 'v', case when cardinality(v_bloq) = 0 then 'SÍ' else 'NO' end));
  return jsonb_build_object('carga_id', c.id, 'capa', 'muestreo', 'estado', c.estado, 'recibidas', v_rec, 'esperadas', c.filas_esperadas, 'frente_a_vigente', v_acc,
    'desactivar', v_desac, 'puntos', (select coalesce(jsonb_agg(jsonb_build_object('orden', orden, 'codigo', codigo, 'nombre', coalesce(nombre, nombre_vigente), 'barrio', barrio,
                                        'exactitud', exactitud, 'fuente', fuente, 'lat', lat, 'lon', lon, 'accion', accion, 'error', error) order by codigo nulls last, orden), '[]'::jsonb) from _mue),
    'avisos', to_jsonb(v_avisos), 'bloqueos', to_jsonb(v_bloq), 'lista_para_publicar', cardinality(v_bloq) = 0, 'tabla', v_tabla);
end $f$;

-- Publicar una carga MUE: agrega los puntos nuevos a tecnica.puntos (con su evento «crear»), reactiva los que vuelven, DESACTIVA los activos que no vienen
-- (con su evento; nunca se borran y sus registros siguen) y agrega la ubicación nueva de lo que cambió. Un candado por capa y uno global de puntos.
create function redes.f_publicar_muestreo(p_carga bigint, p_autor text, p_motivo text) returns jsonb
language plpgsql set search_path to 'redes', 'tecnica', 'public', 'extensions', 'pg_temp' as $f$
declare c redes.v_cargas_estado%rowtype; v_res jsonb; v_sig integer; v_nuevos integer; v_reac integer; v_desac integer; v_ubic integer; v_version integer; v_mot text := btrim(p_motivo);
begin
  perform pg_advisory_xact_lock(hashtext('redes.carga.muestreo'));
  perform pg_advisory_xact_lock(hashtext('tecnica.puntos'));
  select * into c from redes.v_cargas_estado where id = p_carga;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: no se puede publicar', p_carga, c.estado)); end if;
  v_res := redes.f_resumen_muestreo(p_carga);          -- deja armada _mue
  if not (v_res ->> 'lista_para_publicar')::boolean then
    perform tecnica.f_error('La carga no está lista para publicar: ' || array_to_string(array(select jsonb_array_elements_text(v_res -> 'bloqueos')), '; '));
  end if;
  v_version := (select count(*) + 1 from redes.v_cargas_estado x where x.capa_codigo = 'muestreo' and x.estado = 'publicada');
  -- códigos para las filas sin código: el siguiente MUE-nn
  v_sig := coalesce((select max(substring(codigo from '^MUE-([0-9]+)$')::integer) from tecnica.puntos where codigo ~ '^MUE-[0-9]+$'), 0);
  update _mue m set codigo_nuevo = 'MUE-' || lpad((v_sig + x.rn)::text, 2, '0')
    from (select orden, row_number() over (order by orden) as rn from _mue where accion = 'nuevo_sin_codigo') x where x.orden = m.orden;
  update _mue set codigo = codigo_nuevo where accion = 'nuevo_sin_codigo';
  -- (a) puntos nuevos: solo se AGREGAN filas a tecnica.puntos
  insert into tecnica.puntos (codigo, nombre, tipo, zona, barrio)
  select codigo, nombre, 'muestreo', zona, barrio from _mue where accion in ('nuevo', 'nuevo_sin_codigo') order by codigo;
  get diagnostics v_nuevos = row_count;
  update _mue m set punto_id = p.id from tecnica.puntos p where p.codigo = m.codigo and m.accion in ('nuevo', 'nuevo_sin_codigo');
  insert into tecnica.punto_eventos (punto_id, tipo, motivo, carga_id, autor)
  select punto_id, 'crear', format('Punto nuevo de la carga %s de la capa de muestreo (versión %s): %s', p_carga, v_version, v_mot), p_carga, p_autor
    from _mue where accion in ('nuevo', 'nuevo_sin_codigo');
  -- (b) reactivar lo que vuelve
  update tecnica.puntos p set activo = true from _mue m where m.punto_id = p.id and m.accion = 'reactivar' and not p.activo;
  get diagnostics v_reac = row_count;
  insert into tecnica.punto_eventos (punto_id, tipo, motivo, carga_id, autor)
  select punto_id, 'reactivar', format('Volvió en la carga %s de la capa de muestreo (versión %s)', p_carga, v_version), p_carga, p_autor from _mue where accion = 'reactivar';
  -- (c) desactivar los activos que no vienen (nunca se borran; sus registros siguen)
  insert into tecnica.punto_eventos (punto_id, tipo, motivo, carga_id, autor)
  select p.id, 'desactivar', format('No vino en la carga %s de la capa de muestreo (versión %s): %s', p_carga, v_version, v_mot), p_carga, p_autor
    from tecnica.puntos p where p.tipo = 'muestreo' and p.activo and not exists (select 1 from _mue m where m.codigo = p.codigo);
  update tecnica.puntos p set activo = false where p.tipo = 'muestreo' and p.activo and not exists (select 1 from _mue m where m.codigo = p.codigo);
  get diagnostics v_desac = row_count;
  -- (d) ubicación: la de los nuevos y la de lo que cambió (o volvió con otra)
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, barrio_capa, carga_id, autor)
  select punto_id, lat, lon, exactitud, fuente, barrio, p_carga, p_autor from _mue
   where accion in ('nuevo', 'nuevo_sin_codigo', 'ubicacion')
      or (accion = 'reactivar' and (lat_vigente is distinct from lat or lon_vigente is distinct from lon or exactitud_vigente is distinct from exactitud));
  get diagnostics v_ubic = row_count;
  insert into redes.carga_eventos (carga_id, tipo, version_capa, nuevos, cambiados, iguales, retirados, reactivados, detalle, motivo, autor)
  values (p_carga, 'publicar', v_version, v_nuevos, v_ubic, (select count(*) from _mue where accion = 'igual'), v_desac, v_reac,
          jsonb_build_object('ubicaciones', v_ubic, 'codigos_asignados', (select coalesce(jsonb_agg(codigo_nuevo order by codigo_nuevo), '[]'::jsonb) from _mue where codigo_nuevo is not null)),
          v_mot, p_autor);
  delete from redes.carga_filas where carga_id = p_carga;
  return jsonb_build_object('carga_id', p_carga, 'capa', 'muestreo', 'version_capa', v_version, 'nuevos', v_nuevos, 'ubicaciones', v_ubic,
                            'reactivados', v_reac, 'desactivados', v_desac, 'iguales', (select count(*) from _mue where accion = 'igual'),
                            'codigos_asignados', (select coalesce(jsonb_agg(codigo_nuevo order by codigo_nuevo), '[]'::jsonb) from _mue where codigo_nuevo is not null));
end $f$;

-- Revertir la última carga MUE publicada: sus ubicaciones dejan de contar (la vista excluye las cargas revertidas); lo que desactivó se reactiva;
-- lo que creó o reactivó se desactiva (un punto creado no se puede borrar). Todo con eventos.
create function redes.f_revertir_muestreo(p_autor text, p_motivo text) returns jsonb
language plpgsql set search_path to 'redes', 'tecnica', 'public', 'extensions', 'pg_temp' as $f$
declare c redes.v_cargas_estado%rowtype; v_reac integer; v_desac integer;
begin
  perform pg_advisory_xact_lock(hashtext('redes.carga.muestreo'));
  perform pg_advisory_xact_lock(hashtext('tecnica.puntos'));
  select * into c from redes.v_cargas_estado where capa_codigo = 'muestreo' and estado = 'publicada' order by publicada_en desc limit 1;
  if not found then perform tecnica.f_error('La capa de muestreo no tiene una carga publicada para revertir'); end if;
  insert into redes.carga_eventos (carga_id, tipo, motivo, autor) values (c.id, 'revertir', btrim(p_motivo), p_autor);
  insert into tecnica.punto_eventos (punto_id, tipo, motivo, carga_id, autor)
  select e.punto_id, 'reactivar', format('Se revirtió la carga %s de la capa de muestreo, que lo había desactivado', c.id), null, p_autor
    from tecnica.punto_eventos e join tecnica.puntos p on p.id = e.punto_id where e.carga_id = c.id and e.tipo = 'desactivar' and not p.activo;
  update tecnica.puntos p set activo = true from tecnica.punto_eventos e where e.punto_id = p.id and e.carga_id = c.id and e.tipo = 'desactivar' and not p.activo;
  get diagnostics v_reac = row_count;
  insert into tecnica.punto_eventos (punto_id, tipo, motivo, carga_id, autor)
  select e.punto_id, 'desactivar', format('Se revirtió la carga %s de la capa de muestreo, que lo había %s', c.id, case e.tipo when 'crear' then 'creado' else 'reactivado' end), null, p_autor
    from tecnica.punto_eventos e join tecnica.puntos p on p.id = e.punto_id where e.carga_id = c.id and e.tipo in ('crear', 'reactivar') and p.activo;
  update tecnica.puntos p set activo = false from tecnica.punto_eventos e where e.punto_id = p.id and e.carga_id = c.id and e.tipo in ('crear', 'reactivar') and p.activo;
  get diagnostics v_desac = row_count;
  return jsonb_build_object('carga_id', c.id, 'capa', 'muestreo', 'reactivados', v_reac, 'desactivados', v_desac);
end $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- es el texto vivo de cada una con cambios exactos, cada uno aplicado una sola vez:
--   · motor del 1a (f_preparar_candidatos, f_resumen, f_publicar, f_revertir): en una recarga gana lo editado en la ficha y los choques salen en el
--     resumen (§26.3, 17c); la fecha de instalación y el barrio se conservan; el origen corregido en la ficha no se pisa; los nodos clasificados en la
--     bandeja conservan su activo (17f); la capa MUE va por sus propias funciones (20);
--   · §28.1: el supervisor y el administrador ya no registran sin tope (72 h por intervención y hasta 30 días atrás);
--   · §28.2: los formularios de Personal salen de redes.formularios_distribucion; §28.5: las cuadrillas también las crea el supervisor de distribución.
-- =====================================================================

-- redes.f_preparar_candidatos(bigint)
CREATE OR REPLACE FUNCTION redes.f_preparar_candidatos(p_carga bigint)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare v_capa text := (select capa_codigo from redes.cargas where id = p_carga);
begin
  if to_regclass('pg_temp._cand') is not null then drop table pg_temp._cand; end if;
  create temp table _cand on commit drop as
  select c.*,
         redes.f_huella(c.geom, jsonb_build_object('p', c.prefijo, 'n', c.nombre, 'c', c.clase, 'e', c.efecto, 'm', c.material_codigo, 'd', c.diametro_mm,
                                                    'l', c.longitud_m, 'pr', c.profundidad_m, 'ca', c.capacidad, 's', c.estado_codigo,
                                                    'ant', c.codigo_anterior, 'a', c.atributos)) as huella,
         null::bigint as activo_id, null::text as codigo, null::integer as version_vigente, null::text as huella_vigente,
         null::text as prefijo_vigente, false as retirado_vigente, null::text as accion
    from redes.f_candidatos(p_carga) c;
  -- cruce con lo vigente por (capa, llave) (D-2: nunca por el id de public.redes_*)
  update _cand k set activo_id = v.activo_id, codigo = v.codigo, version_vigente = v.version, huella_vigente = v.huella, prefijo_vigente = v.prefijo, retirado_vigente = v.retirado
    from redes.v_activo_vigente v
   where k.crea_activo and k.llave is not null and v.capa_codigo = k.capa_codigo and v.llave_capa = k.llave;
  update _cand set accion = case when not crea_activo then null
                                 when activo_id is null then 'nuevo'
                                 when prefijo_vigente is distinct from prefijo then 'nuevo_por_tipo'      -- cambió de tipo: activo nuevo y el viejo se retira
                                 when huella_vigente = huella then case when retirado_vigente then 'reactivar' else 'igual' end
                                 else 'cambiado' end;
  create index on _cand (capa_codigo, llave);
  create index on _cand (activo_id);
  perform redes.f_fusionar_ficha();      -- Corte 5a (§26.3): en una recarga gana lo editado en la ficha; los choques quedan en _choques
  analyze _cand;
end $function$;

-- redes.f_resumen(bigint)
CREATE OR REPLACE FUNCTION redes.f_resumen(p_carga bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  c redes.v_cargas_estado%rowtype; v_tol numeric := redes.f_param('tolerancia_nodo_m');
  v_recibidas integer; v_errores integer; v_nulas integer; v_rep integer; v_bloq text[] := '{}'; v_avisos text[] := '{}'; v_tabla jsonb := '[]'::jsonb;
  v_por_prefijo jsonb; v_por_estado jsonb; v_por_accion jsonb; v_retirar integer; v_disp integer; v_sinmat integer; v_extra jsonb := '{}'::jsonb;
  v_nodos integer; v_nodos_activo integer; v_nodos_pc integer; v_nodos_virt integer; v_sin_ini integer; v_sin_fin integer; v_pend text[];
  r record; v_ch jsonb := '[]'::jsonb;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  if c.capa_codigo = 'muestreo' then return redes.f_resumen_muestreo(p_carga); end if;      -- capa MUE (Corte 5a)
  select count(*), count(*) filter (where error is not null), count(*) filter (where error is null and llave is null) into v_recibidas, v_errores, v_nulas
    from redes.carga_filas where carga_id = p_carga;
  select count(*) into v_rep from (select llave from redes.carga_filas where carga_id = p_carga and llave is not null group by llave having count(*) > 1) x;

  if c.estado <> 'abierta' then v_bloq := v_bloq || ('La carga está ' || c.estado); end if;
  if v_recibidas <> c.filas_esperadas then v_bloq := v_bloq || format('Llegaron %s de %s filas: falta algún lote', v_recibidas, c.filas_esperadas); end if;
  if v_errores > 0 then v_bloq := v_bloq || format('%s filas con error de geometría', v_errores); end if;
  if v_nulas > 0 then v_bloq := v_bloq || format('%s filas sin llave (%s)', v_nulas, c.columna_llave); end if;
  if v_rep > 0 then v_bloq := v_bloq || format('%s llaves repetidas en %s: el cruce por geometría (D-4) llega con el Cargue de capas', v_rep, c.columna_llave); end if;

  if c.estado = 'abierta' then
    perform redes.f_preparar_candidatos(p_carga);
    select coalesce(jsonb_object_agg(prefijo, n order by prefijo), '{}'::jsonb) into v_por_prefijo from (select prefijo, count(*) n from _cand where crea_activo group by prefijo) x;
    select coalesce(jsonb_object_agg(estado_codigo, n order by estado_codigo), '{}'::jsonb) into v_por_estado from (select estado_codigo, count(*) n from _cand where crea_activo group by estado_codigo) x;
    select coalesce(jsonb_object_agg(accion, n order by accion), '{}'::jsonb) into v_por_accion from (select accion, count(*) n from _cand where crea_activo group by accion) x;
    select count(*) into v_retirar from redes.v_activo_vigente v
     where v.capa_codigo = any (redes.f_capas_cubiertas(c.capa_codigo)) and not v.retirado
       and not exists (select 1 from _cand k where k.capa_codigo = v.capa_codigo and k.llave = v.llave_capa and k.crea_activo);
    select count(*) into v_sinmat from _cand where crea_activo and material_texto is not null and material_codigo is null;
    -- Corte 5a: choques con la ficha (gana la ficha, §26.3) y nodos ya clasificados en la bandeja (se conservan, 17f)
    select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'campo', campo, 'ficha', valor_ficha, 'capa', valor_capa) order by codigo, campo), '[]'::jsonb) into v_ch from _choques;
    if jsonb_array_length(v_ch) > 0 then
      v_avisos := v_avisos || format('%s campos editados en la ficha vienen distintos en la capa: gana la ficha (§26.3); la lista va en «choques con la ficha»', jsonb_array_length(v_ch));
    end if;
    v_extra := v_extra || jsonb_build_object('choques_con_la_ficha', jsonb_array_length(v_ch), 'nodos_clasificados_en_la_bandeja',
      (select count(*) from _cand k join redes.v_nodo_vigente n on n.sistema = k.nodo_sistema and n.llave_modelo = k.llave
        where k.crea_nodo and not k.crea_activo and k.clase_nodo = 'por_clasificar' and n.activo_id is not null));
    if v_sinmat > 0 then
      v_avisos := v_avisos || format('%s filas con material sin equivalencia (quedan sin material): %s', v_sinmat,
                    (select string_agg(distinct material_texto, ', ') from _cand where crea_activo and material_texto is not null and material_codigo is null));
    end if;
    select count(*) filter (where crea_nodo), count(*) filter (where crea_nodo and clase_nodo = 'activo'), count(*) filter (where clase_nodo = 'por_clasificar'),
           count(*) filter (where clase_nodo = 'pozo_virtual'), count(*) filter (where crea_nodo and dispersion_m > v_tol)
      into v_nodos, v_nodos_activo, v_nodos_pc, v_nodos_virt, v_disp from _cand;
    if v_disp > 0 then
      v_bloq := v_bloq || format('%s nodos con extremos separados más de %s m: revíselos antes de publicar (lista en nodos_dispersos)', v_disp, v_tol);
      v_extra := v_extra || jsonb_build_object('nodos_dispersos', (select jsonb_agg(jsonb_build_object('llave', llave, 'nombre', nodo_nombre, 'dispersion_m', round(dispersion_m, 2)) order by dispersion_m desc)
                                                                    from (select * from _cand where crea_nodo and dispersion_m > v_tol order by dispersion_m desc limit 50) z));
    end if;
    if exists (select 1 from _cand where nombres_distintos > 1) then
      v_avisos := v_avisos || format('%s nodos con más de un nombre en el modelo (se toma el primero)', (select count(*) from _cand where nombres_distintos > 1));
    end if;
    if c.capa_codigo = 'acueducto' then
      v_extra := v_extra || jsonb_build_object(
        'nodos_por_clasificar_por_prefijo', (select coalesce(jsonb_object_agg(p, n order by p), '{}'::jsonb) from
                                               (select coalesce(substring(nodo_nombre from '^[A-Za-zÁÉÍÓÚáéíóúñ]+'), '?') p, count(*) n from _cand where clase_nodo = 'por_clasificar' group by 1) z),
        'valvulas_por_clase', (select coalesce(jsonb_object_agg(clase, n order by clase), '{}'::jsonb) from (select clase, count(*) n from _cand where prefijo = 'VAL' group by clase) z),
        'accesorios_por_clase', (select coalesce(jsonb_object_agg(clase, n order by clase), '{}'::jsonb) from (select clase, count(*) n from _cand where prefijo = 'ACC' group by clase) z),
        'tramos_sin_nodo', (select count(*) from _cand where capa_codigo = 'acueducto' and (nodo_ini is null or nodo_fin is null)),
        'origen_tercero_siva', (select count(*) from _cand where aportante_codigo = 'siva'),
        'valvula_retencion', (select string_agg(codigo_anterior, ', ') from _cand where (atributos ->> 'valvula_retencion')::boolean),
        'macromedidores', (select jsonb_agg(jsonb_build_object('nodo', nodo_nombre, 'punto', 'MAC-' || lpad(macro_num::text, 2, '0'),
                                                               'existe_en_tecnica_puntos', exists (select 1 from tecnica.puntos p where p.codigo = 'MAC-' || lpad(k.macro_num::text, 2, '0'))) order by macro_num)
                             from _cand k where macro_num is not null));
      if (select count(*) from _cand where capa_codigo = 'acueducto' and (nodo_ini is null or nodo_fin is null)) > 0 then
        v_avisos := v_avisos || 'Hay tramos sin STARTNODID o STOPNODEID: quedan sin nodo en la topología';
      end if;
    elsif c.capa_codigo = 'alc_conductos' then
      if to_regclass('pg_temp._llaves_alc') is not null then drop table pg_temp._llaves_alc; end if;
      create temp table _llaves_alc on commit drop as select distinct llave from redes.f_llaves_nodo_alc_disponibles() where llave is not null;
      create unique index on _llaves_alc (llave);
      select count(*) filter (where k.nodo_ini is null or not exists (select 1 from _llaves_alc l where l.llave = k.nodo_ini)),
             count(*) filter (where k.nodo_fin is null or not exists (select 1 from _llaves_alc l where l.llave = k.nodo_fin))
        into v_sin_ini, v_sin_fin from _cand k;
      select array_agg(distinct capa_codigo order by capa_codigo) into v_pend from redes.v_cargas_estado where estado = 'abierta' and capa_codigo in ('alc_pozos', 'alc_descargas');
      v_extra := v_extra || jsonb_build_object('pz_inicial_sin_nodo', v_sin_ini, 'pz_final_sin_nodo', v_sin_fin,
                                               'publicar_antes', coalesce(to_jsonb(v_pend), '[]'::jsonb));
      v_extra := v_extra || jsonb_build_object('por_estado_fisico', (select coalesce(jsonb_object_agg(k, n order by k), '{}'::jsonb) from (select coalesce(atributos ->> 'estado_fisico', '(vacío)') k, count(*) n from _cand group by 1) z));
      if v_sin_ini + v_sin_fin > 0 then
        v_avisos := v_avisos || format('%s extremos de conducto sin pozo ni descarga con ese LABEL: se enlazan por extremos (%s m)', v_sin_ini + v_sin_fin, v_tol);
      end if;
      if v_pend is not null then v_avisos := v_avisos || ('Publique antes: ' || array_to_string(v_pend, ', ')); end if;
    elsif c.capa_codigo = 'alc_pozos' then
      v_extra := v_extra || jsonb_build_object('por_estado_pozo', (select coalesce(jsonb_object_agg(k, n order by k), '{}'::jsonb) from (select coalesce(atributos ->> 'estado_pozo', '(vacío)') k, count(*) n from _cand group by 1) z));
    end if;
  end if;

  -- tabla para mostrar en psql (sección, concepto, valor)
  v_tabla := jsonb_build_array(
    jsonb_build_object('s', '1 carga', 'c', 'capa', 'v', c.capa_codigo),
    jsonb_build_object('s', '1 carga', 'c', 'carga', 'v', c.id::text || ' (' || c.estado || ')'),
    jsonb_build_object('s', '1 carga', 'c', 'filas recibidas / esperadas', 'v', v_recibidas || ' / ' || c.filas_esperadas),
    jsonb_build_object('s', '1 carga', 'c', 'filas con error de geometría', 'v', v_errores::text),
    jsonb_build_object('s', '1 carga', 'c', 'llaves nulas / repetidas (' || c.columna_llave || ')', 'v', v_nulas || ' / ' || v_rep));
  if c.estado = 'abierta' then
    v_tabla := v_tabla
      || (select coalesce(jsonb_agg(jsonb_build_object('s', '2 activos por tipo', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_por_prefijo))
      || (select coalesce(jsonb_agg(jsonb_build_object('s', '3 activos por estado', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_por_estado))
      || (select coalesce(jsonb_agg(jsonb_build_object('s', '4 frente a lo vigente', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_por_accion))
      || jsonb_build_array(jsonb_build_object('s', '4 frente a lo vigente', 'c', 'retirados (no vienen)', 'v', v_retirar::text))
      || case when v_nodos > 0 then jsonb_build_array(
           jsonb_build_object('s', '5 nodos', 'c', 'nodos distintos', 'v', v_nodos::text),
           jsonb_build_object('s', '5 nodos', 'c', 'con activo', 'v', v_nodos_activo::text),
           jsonb_build_object('s', '5 nodos', 'c', 'por clasificar (solo nodo, N-3)', 'v', v_nodos_pc::text),
           jsonb_build_object('s', '5 nodos', 'c', 'pozos virtuales (solo nodo, N-4)', 'v', v_nodos_virt::text),
           jsonb_build_object('s', '5 nodos', 'c', 'cuadra: con activo + solo nodo = distintos', 'v', case when v_nodos_activo + v_nodos_pc + v_nodos_virt = v_nodos then 'sí' else 'NO' end),
           jsonb_build_object('s', '5 nodos', 'c', 'con extremos separados > ' || v_tol || ' m', 'v', v_disp::text)) else '[]'::jsonb end
      || (select coalesce(jsonb_agg(jsonb_build_object('s', '6 detalle', 'c', key, 'v', case when jsonb_typeof(value) = 'string' then value #>> '{}' else value::text end) order by key), '[]'::jsonb)
            from jsonb_each(v_extra - 'nodos_dispersos'));
  end if;
  v_tabla := v_tabla || (select coalesce(jsonb_agg(jsonb_build_object('s', '6b choques con la ficha (gana la ficha)', 'c', (x ->> 'codigo') || ' · ' || (x ->> 'campo'),
                           'v', 'ficha «' || coalesce(x ->> 'ficha', '—') || '» / capa «' || coalesce(x ->> 'capa', '—') || '»')), '[]'::jsonb)
                           from (select x from jsonb_array_elements(v_ch) x limit 200) z);
  v_tabla := v_tabla
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '7 avisos', 'c', 'aviso', 'v', a)), '[]'::jsonb) from unnest(v_avisos) a)
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '8 bloqueos', 'c', 'BLOQUEO', 'v', b)), '[]'::jsonb) from unnest(v_bloq) b)
    || jsonb_build_array(jsonb_build_object('s', '9 resultado', 'c', 'lista para publicar', 'v', case when cardinality(v_bloq) = 0 then 'SÍ' else 'NO' end));

  return jsonb_build_object('carga_id', c.id, 'capa', c.capa_codigo, 'estado', c.estado, 'recibidas', v_recibidas, 'esperadas', c.filas_esperadas,
    'errores', v_errores, 'llaves_nulas', v_nulas, 'llaves_repetidas', v_rep, 'por_prefijo', v_por_prefijo, 'por_estado', v_por_estado,
    'frente_a_vigente', v_por_accion, 'retirados', v_retirar, 'nodos', v_nodos, 'nodos_con_activo', v_nodos_activo, 'nodos_por_clasificar', v_nodos_pc,
    'pozos_virtuales', v_nodos_virt, 'nodos_dispersos', v_disp, 'detalle', v_extra, 'avisos', to_jsonb(v_avisos), 'bloqueos', to_jsonb(v_bloq),
    'lista_para_publicar', cardinality(v_bloq) = 0, 'choques', v_ch, 'tabla', v_tabla);
end $function$;

-- redes.f_publicar(bigint,text,text)
CREATE OR REPLACE FUNCTION redes.f_publicar(p_carga bigint, p_autor text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  c redes.v_cargas_estado%rowtype; v_res jsonb; v_tol numeric := redes.f_param('tolerancia_nodo_m'); v_sis text; v_cub text[];
  v_nuevos integer; v_cambiados integer; v_iguales integer; v_retirados integer; v_reactivados integer; v_nodos integer := 0; v_tn integer := 0;
  v_extremos integer := 0; v_sin_nodo integer := 0; v_ct integer; v_mat integer; v_version_capa integer; v_origen integer; v_mac integer;
  t0 timestamptz := clock_timestamp();
begin
  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo de la publicación (10 caracteres o más)'); end if;
  if (select capa_codigo from redes.cargas where id = p_carga) = 'muestreo' then return redes.f_publicar_muestreo(p_carga, p_autor, p_motivo); end if;      -- capa MUE (Corte 5a)
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.carga.' || c.capa_codigo));
  select * into c from redes.v_cargas_estado where id = p_carga;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: no se puede publicar', p_carga, c.estado)); end if;
  if c.capa_codigo = 'alc_conductos' and exists (select 1 from redes.v_cargas_estado where estado = 'abierta' and capa_codigo in ('alc_pozos', 'alc_descargas')) then
    perform tecnica.f_error('Publique primero los pozos y las descargas: los conductos se enlazan con ellos');
  end if;
  v_res := redes.f_resumen(p_carga);                         -- deja armada la tabla temporal _cand
  if not (v_res ->> 'lista_para_publicar')::boolean then
    perform tecnica.f_error('La carga no está lista para publicar: ' || array_to_string(array(select jsonb_array_elements_text(v_res -> 'bloqueos')), '; '));
  end if;
  v_sis := (select sistema from redes.capas where codigo = c.capa_codigo);
  v_cub := redes.f_capas_cubiertas(c.capa_codigo);

  alter table _cand add column activo_previo bigint, add column version_nueva integer;
  update _cand set activo_previo = activo_id, activo_id = null, codigo = null where accion = 'nuevo_por_tipo';

  -- (a) activos nuevos, con su código por prefijo (el update de consecutivos toma el candado de fila)
  if to_regclass('pg_temp._nuevos') is not null then drop table pg_temp._nuevos; end if; create temp table _nuevos on commit drop as
  select k.capa_codigo, k.llave, k.prefijo, row_number() over (partition by k.prefijo order by k.capa_codigo, k.orden, k.llave) as rn
    from _cand k where k.accion in ('nuevo', 'nuevo_por_tipo');
  if to_regclass('pg_temp._base') is not null then drop table pg_temp._base; end if; create temp table _base (prefijo text, base bigint) on commit drop;
  with req as (select prefijo, count(*) as n from _nuevos group by prefijo),
       upd as (update redes.consecutivos k set ultimo = k.ultimo + r.n from req r where k.prefijo = r.prefijo returning k.prefijo, k.ultimo - r.n as base)
  insert into _base select prefijo, base from upd;
  if exists (select 1 from _nuevos n where not exists (select 1 from _base b where b.prefijo = n.prefijo)) then
    perform tecnica.f_error('Falta el consecutivo de algún prefijo');
  end if;
  update _cand k set codigo = n.prefijo || '-' || lpad((b.base + n.rn)::text, 6, '0')
    from _nuevos n join _base b on b.prefijo = n.prefijo
   where n.capa_codigo = k.capa_codigo and n.llave = k.llave and k.accion in ('nuevo', 'nuevo_por_tipo');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por)
  select codigo, prefijo, 'carga', p_autor from _cand where accion in ('nuevo', 'nuevo_por_tipo') order by prefijo, codigo;
  get diagnostics v_nuevos = row_count;
  update _cand k set activo_id = a.id from redes.activos a where k.accion in ('nuevo', 'nuevo_por_tipo') and a.codigo = k.codigo;

  -- (b) versiones: la 1 de los nuevos y la siguiente de los cambiados
  update _cand k set version_nueva = case when k.accion in ('nuevo', 'nuevo_por_tipo') then 1
                                          else (select max(v.version) + 1 from redes.activo_versiones v where v.activo_id = k.activo_id) end
   where k.accion in ('nuevo', 'nuevo_por_tipo', 'cambiado');
  -- Corte 5a: la fecha de instalación y el barrio o sector (no vienen en ninguna capa) se conservan
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m,
         estado_codigo, atributos, codigo_anterior, capa_codigo, llave_capa, carga_id, huella, autor, fecha_instalacion, barrio_sector)
  select activo_id, version_nueva, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m,
         estado_codigo, atributos, codigo_anterior, capa_codigo, llave, p_carga, huella, p_autor, fecha_instalacion, barrio_sector
    from _cand where version_nueva is not null order by activo_id;
  select count(*) filter (where accion = 'cambiado'), count(*) filter (where accion in ('igual', 'reactivar')) into v_cambiados, v_iguales from _cand;
  -- Estadísticas al día: las tablas se acaban de llenar en esta misma transacción y, sin esto, el planificador
  -- elige bucles anidados (la publicación de conductos pasó de 90 s a pocos segundos en local).
  analyze redes.activos; analyze redes.activo_versiones; analyze _cand;

  -- (c) origen (solo lo ve el supervisor, D-11): cuando es nuevo o cambió. SIVA = tercero, sin soporte.
  insert into redes.activo_origen (activo_id, version, origen, aportante_codigo, nota, carga_id, autor)
  select k.activo_id, coalesce(k.version_nueva, k.version_vigente), k.origen, k.aportante_codigo,
         case when k.aportante_codigo = 'siva' then 'Zona SIVA del modelo de acueducto: obra de una entidad del Gobierno. Sin soporte todavía.' end, p_carga, p_autor
    from _cand k left join redes.v_activo_origen_vigente o on o.activo_id = k.activo_id
   where k.crea_activo and k.activo_id is not null
     and (o.activo_id is null or o.origen is distinct from k.origen or o.aportante_codigo is distinct from k.aportante_codigo)
     and not ('origen' = any (coalesce(k.campos_ficha, '{}')));      -- Corte 5a (§26.3): el origen corregido en la ficha no lo pisa la capa
  get diagnostics v_origen = row_count;

  -- (d) MACRO n del modelo ↔ MAC-nn de tecnica.puntos (N-8). Sin fk: tecnica.puntos no se toca.
  insert into redes.activo_punto (activo_id, punto_codigo, punto_id, motivo, carga_id, autor)
  select k.activo_id, 'MAC-' || lpad(k.macro_num::text, 2, '0'), (select p.id from tecnica.puntos p where p.codigo = 'MAC-' || lpad(k.macro_num::text, 2, '0')),
         'Enlace por el número del MACRO del modelo hidráulico (N-8)', p_carga, p_autor
    from _cand k left join redes.v_activo_punto_vigente ap on ap.activo_id = k.activo_id
   where k.macro_num is not null and k.activo_id is not null and ap.activo_id is null;
  get diagnostics v_mac = row_count;

  -- (e) retiros: lo vigente de las capas que cubre la carga y que no vino (con motivo), y el activo viejo cuando cambió de tipo
  insert into redes.activo_eventos (activo_id, tipo, motivo, carga_id, autor)
  select v.activo_id, 'retirar', format('No vino en la carga %s de la capa %s (versión %s de la capa)', p_carga, c.capa_codigo,
                                        (select count(*) + 1 from redes.v_cargas_estado x where x.capa_codigo = c.capa_codigo and x.estado = 'publicada')), p_carga, p_autor
    from redes.v_activo_vigente v
   where v.capa_codigo = any (v_cub) and not v.retirado
     and not exists (select 1 from _cand k where k.activo_id = v.activo_id);
  get diagnostics v_retirados = row_count;
  -- (f) reactivar lo que estaba retirado y volvió
  insert into redes.activo_eventos (activo_id, tipo, motivo, carga_id, autor)
  select k.activo_id, 'reactivar', format('Volvió en la carga %s de la capa %s', p_carga, c.capa_codigo), p_carga, p_autor
    from _cand k where k.retirado_vigente and k.accion in ('reactivar', 'cambiado');
  get diagnostics v_reactivados = row_count;

  -- Corte 5a (17f): los nodos que el administrador clasificó en la bandeja (activo enlazado con un evento) conservan su activo en la recarga
  if to_regclass('pg_temp._bandeja') is not null then drop table pg_temp._bandeja; end if;
  create temp table _bandeja on commit drop as
  select k.nodo_sistema as sistema, k.llave, n.activo_id from _cand k join redes.v_nodo_vigente n on n.sistema = k.nodo_sistema and n.llave_modelo = k.llave
   where k.crea_nodo and not k.crea_activo and k.clase_nodo = 'por_clasificar' and n.activo_id is not null;
  -- (g) nodos: se inserta solo si es nuevo o cambió (nombre, posición, activo o clase); el vigente idéntico se reutiliza
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id)
  select k.nodo_sistema, k.llave, k.nodo_nombre, k.clase_nodo, k.geom, case when k.crea_activo then k.activo_id end, round(k.dispersion_m, 3), p_carga
    from _cand k left join redes.v_nodo_vigente n on n.sistema = k.nodo_sistema and n.llave_modelo = k.llave
   where k.crea_nodo and k.llave is not null
     and (n.nodo_id is null or n.nombre_modelo is distinct from k.nodo_nombre or not ST_Equals(n.geom, k.geom)
          or ((n.activo_id is distinct from (case when k.crea_activo then k.activo_id end) or n.clase_nodo <> k.clase_nodo)
              and not exists (select 1 from _bandeja b where b.sistema = k.nodo_sistema and b.llave = k.llave)));
  get diagnostics v_nodos = row_count;
  -- 17f: si el nodo cambió de nombre o de posición, el nodo nuevo queda enlazado al mismo activo de la bandeja
  insert into redes.nodo_eventos (nodo_id, tipo, activo_id, motivo, autor)
  select n.id, 'enlazar_activo', b.activo_id, format('Se conserva el activo de la bandeja de nodos por clasificar en la carga %s', p_carga), p_autor
    from redes.nodos n join _bandeja b on b.sistema = n.sistema and b.llave = n.llave_modelo where n.carga_id = p_carga;
  analyze redes.nodos;

  -- (h) topología de los tramos con versión nueva: por el modelo (llaves de nodo) y, si falta, por extremos (tolerancia_nodo_m)
  if c.capa_codigo in ('acueducto', 'alc_conductos') then
    if to_regclass('pg_temp._vn') is not null then drop table pg_temp._vn; end if; create temp table _vn on commit drop as select nodo_id, llave_modelo, geom from redes.v_nodo_vigente where sistema = v_sis;
    create index on _vn (llave_modelo);
    create index on _vn using gist (geom);
    if to_regclass('pg_temp._tn') is not null then drop table pg_temp._tn; end if; create temp table _tn on commit drop as
    select k.activo_id, k.version_nueva as version, k.geom, ni.nodo_id as ini_m, nf.nodo_id as fin_m, null::bigint as ini_e, null::bigint as fin_e
      from _cand k
      left join _vn ni on ni.llave_modelo = k.nodo_ini
      left join _vn nf on nf.llave_modelo = k.nodo_fin
     where k.version_nueva is not null and k.capa_codigo in ('acueducto', 'alc_conductos');
    update _tn t set ini_e = (select n.nodo_id from _vn n where ST_DWithin(n.geom::geography, ST_StartPoint(t.geom)::geography, v_tol) order by n.geom <-> ST_StartPoint(t.geom) limit 1)
     where t.ini_m is null;
    update _tn t set fin_e = (select n.nodo_id from _vn n where ST_DWithin(n.geom::geography, ST_EndPoint(t.geom)::geography, v_tol) order by n.geom <-> ST_EndPoint(t.geom) limit 1)
     where t.fin_m is null;
    insert into redes.tramo_nodos (activo_id, version, nodo_ini, nodo_fin, metodo, carga_id)
    select activo_id, version, coalesce(ini_m, ini_e), coalesce(fin_m, fin_e),
           case when ini_m is not null and fin_m is not null then 'modelo'
                when coalesce(ini_m, ini_e) is not null and coalesce(fin_m, fin_e) is not null then 'extremos' else 'sin_nodo' end, p_carga
      from _tn;
    get diagnostics v_tn = row_count;
    select count(*) filter (where (ini_m is null or fin_m is null) and coalesce(ini_m, ini_e) is not null and coalesce(fin_m, fin_e) is not null),
           count(*) filter (where coalesce(ini_m, ini_e) is null or coalesce(fin_m, fin_e) is null)
      into v_extremos, v_sin_nodo from _tn;
  end if;

  -- (i) cierre: evento, staging vaciado, derivados
  v_version_capa := (select count(*) + 1 from redes.v_cargas_estado x where x.capa_codigo = c.capa_codigo and x.estado = 'publicada');
  v_mat := redes.f_refrescar_vigente();
  if c.capa_codigo = 'acueducto' then v_ct := redes.f_recalcular_contrato_tramo(); end if;
  perform redes.f_subir_tesela(v_sis);
  insert into redes.carga_eventos (carga_id, tipo, version_capa, nuevos, cambiados, iguales, retirados, reactivados, detalle, motivo, autor)
  values (p_carga, 'publicar', v_version_capa, v_nuevos, v_cambiados, v_iguales, v_retirados, v_reactivados,
          jsonb_build_object('por_prefijo', v_res -> 'por_prefijo', 'nodos_insertados', v_nodos, 'tramo_nodos', v_tn, 'tramos_por_extremos', v_extremos,
                             'tramos_sin_nodo', v_sin_nodo, 'origen', v_origen, 'enlaces_mac', v_mac, 'contrato_tramo', v_ct, 'activos_vigentes_mat', v_mat,
                             'segundos', round(extract(epoch from clock_timestamp() - t0)::numeric, 1)),
          btrim(p_motivo), p_autor);
  delete from redes.carga_filas where carga_id = p_carga;
  return jsonb_build_object('carga_id', p_carga, 'capa', c.capa_codigo, 'version_capa', v_version_capa, 'nuevos', v_nuevos, 'cambiados', v_cambiados,
    'iguales', v_iguales, 'retirados', v_retirados, 'reactivados', v_reactivados, 'nodos_insertados', v_nodos, 'tramo_nodos', v_tn,
    'tramos_por_extremos', v_extremos, 'tramos_sin_nodo', v_sin_nodo, 'origen', v_origen, 'enlaces_mac', v_mac, 'contrato_tramo', v_ct,
    'activos_vigentes', v_mat, 'segundos', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $function$;

-- redes.f_revertir(text,text,text)
CREATE OR REPLACE FUNCTION redes.f_revertir(p_capa text, p_autor text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare c redes.v_cargas_estado%rowtype; v_sis text; v_reac integer; v_ret integer; v_ct integer; v_mat integer;
begin
  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  if p_capa = 'muestreo' then return redes.f_revertir_muestreo(p_autor, p_motivo); end if;      -- capa MUE (Corte 5a)
  perform pg_advisory_xact_lock(hashtext('redes.carga.' || p_capa));
  select * into c from redes.v_cargas_estado where capa_codigo = p_capa and estado = 'publicada' order by publicada_en desc limit 1;
  if not found then perform tecnica.f_error(format('La capa %s no tiene una carga publicada para revertir', p_capa)); end if;
  if p_capa in ('alc_pozos', 'alc_descargas') and exists (select 1 from redes.v_cargas_estado x where x.capa_codigo = 'alc_conductos' and x.estado = 'publicada' and x.publicada_en > c.publicada_en) then
    perform tecnica.f_error('Revierta antes la carga de conductos que se publicó después: sus tramos se enlazan con estos nodos');
  end if;
  v_sis := (select sistema from redes.capas where codigo = p_capa);
  insert into redes.carga_eventos (carga_id, tipo, motivo, autor) values (c.id, 'revertir', btrim(p_motivo), p_autor);
  insert into redes.activo_eventos (activo_id, tipo, motivo, carga_id, autor)
  select e.activo_id, 'reactivar', format('Se revirtió la carga %s, que lo había retirado', c.id), null, p_autor
    from redes.activo_eventos e join redes.v_activo_estado s on s.activo_id = e.activo_id
   where e.carga_id = c.id and e.tipo = 'retirar' and s.retirado;
  get diagnostics v_reac = row_count;
  insert into redes.activo_eventos (activo_id, tipo, motivo, carga_id, autor)
  select e.activo_id, 'retirar', format('Se revirtió la carga %s, que lo había reactivado', c.id), null, p_autor
    from redes.activo_eventos e join redes.v_activo_estado s on s.activo_id = e.activo_id
   where e.carga_id = c.id and e.tipo = 'reactivar' and not s.retirado;
  get diagnostics v_ret = row_count;
  v_mat := redes.f_refrescar_vigente();
  if p_capa = 'acueducto' then v_ct := redes.f_recalcular_contrato_tramo(); end if;
  perform redes.f_subir_tesela(v_sis);
  return jsonb_build_object('carga_id', c.id, 'capa', p_capa, 'reactivados', v_reac, 'retirados', v_ret, 'activos_vigentes', v_mat, 'contrato_tramo', v_ct);
end $function$;

-- public.geoportal_redes_formulario_intervencion(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_formulario_intervencion(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento');
        v_perfil text := case when public.geoportal_es_admin(v_email) then 'admin' when redes.f_es_supervisor_redes(v_email) then 'supervisor' else 'operador' end;
begin
  return jsonb_build_object(
    'perfil', v_perfil,
    'sistemas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.sistemas where codigo in ('acueducto', 'alcantarillado')),
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'admite_dano', admite_dano, 'es_inversion', es_inversion) order by orden) from redes.tipos_intervencion where activo),
    'aportantes', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.entidades_aportantes where activo),
    'contratistas', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by nombre) from redes.contratistas where activo), '[]'::jsonb),
    'unidades', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.unidades_material where activo),
    -- tipos de activo que puede crear una inversión «activo nuevo», con sus clases (y si la clase es obligatoria)
    'tipos_nuevo', (select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre_visible, 'sistema', t.sistema, 'geometria', t.geometria,
                       'clases', coalesce((select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre) order by c.orden) from redes.clases_activo c where c.prefijo = t.prefijo), '[]'::jsonb),
                       'clase_obligatoria', exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean),
                       'lleva_diametro', exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'diametro_mm'))
                     order by t.orden)
                      from redes.v_tipo_visible t where t.sistema in ('acueducto', 'alcantarillado') and t.geometria in ('punto', 'linea')),
    'materiales', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.materiales),
    -- el operario conserva el tope de días y de horas; el supervisor y el administrador registran las obras largas sin ese tope (David, respuesta 1 al 3a)
    'reglas', jsonb_build_object('dias_atras_max', case when v_perfil in ('admin', 'supervisor') then redes.f_param('itv_dias_atras_max_supervisor') else redes.f_param('itv_dias_atras_max') end,
                                 'max_horas', redes.f_param('itv_max_horas'),
                                 'min_fotos', redes.f_param('min_fotos_itv'), 'puede_sin_fotos', false, 'pone_valores', v_perfil in ('admin', 'supervisor'),
                                 'max_fotos', redes.f_param('max_fotos_itv'), 'max_documentos', redes.f_param('max_docs_itv'),
                                 'max_bytes_foto', redes.f_param('max_bytes_foto_itv'), 'max_bytes_documento', redes.f_param('max_bytes_doc_itv'),
                                 'max_horas_inicio', tecnica.f_max_horas_inicio(), 'radio_cercanos_m', redes.f_param('distancia_activo_cercano_m'),
                                 'radio_danos_m', redes.f_param('itv_radio_danos_m'), 'max_tambien', redes.f_param('itv_max_activos_tambien'),
                                 'max_materiales', redes.f_param('itv_max_materiales'), 'zoom_min', redes.f_param('mini_zoom_min'), 'zoom_accesorios', redes.f_param('mini_zoom_acc')),
    'ahora', clock_timestamp());
end $function$;

-- public.geoportal_redes_crear_intervencion(text,uuid,jsonb,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_crear_intervencion(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento'); v_super boolean; d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_intervencion%rowtype; v_tipo redes.tipos_intervencion%rowtype; v_sis text; v_modo text;
  v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text; v_nuevo jsonb; v_tn redes.v_tipo_visible%rowtype; v_geom_nuevo geometry;
  v_clase_n text; v_mat_n text; v_diam_n numeric; v_nom_n text; v_pts jsonb; v_p jsonb; v_lat numeric; v_lon numeric; v_fuera boolean;
  v_t_ini timestamptz; v_t_fin timestamptz; v_inicio timestamptz; v_desc text := btrim(coalesce(d ->> 'descripcion', ''));
  v_dano redes.v_dano%rowtype; v_tambien bigint[] := '{}'; v_x text; v_xid bigint; v_mats jsonb := coalesce(d -> 'materiales', '[]'::jsonb); v_m jsonb;
  v_fuentes jsonb; v_arch jsonb := coalesce(d -> 'archivos', '[]'::jsonb); v_ref jsonb := '[]'::jsonb; v_nf integer := 0; v_nd integer := 0; v_n integer;
  v_f jsonb; v_ruta text; v_size bigint; v_mime text; v_prep redes.intervencion_preparaciones%rowtype; v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
  v_cons bigint; v_codigo text; v_ctr bigint; v_ctr_nom text; v_orden text := nullif(btrim(coalesce(d ->> 'contrato_orden', '')), '');
  v_comp text := nullif(btrim(coalesce(d ->> 'companeros', '')), ''); v_pto geometry; v_creado boolean := false; v_origen text; v_aport text; v_cod_nuevo text;
  v_dano_estado text; v_resuelve boolean := coalesce((p_datos ->> 'resuelve_dano')::boolean, false);
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador de la intervención: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_intervencion where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de esta intervención'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'activo_creado', v_prev.activo_creado, 'dano', v_prev.dano_codigo, 'sin_evidencia', v_prev.sin_evidencia, 'fuera_de_zona', v_prev.fuera_de_zona, 'repetido', true);
  end if;
  select * into v_prep from redes.intervencion_preparaciones where intervencion_id = p_id and autor = v_email;
  if not found then perform tecnica.f_error('Primero debe prepararse la subida de esta intervención'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos de la intervención no son válidos'); end if;
  v_super := redes.f_es_supervisor_redes(v_email);

  -- 1. de dónde nace y tipo
  if coalesce(d ->> 'nace_de', '') not in ('programada', 'dano') then perform tecnica.f_error('Elija de dónde nace: programada o mejora, o daño o falla'); end if;
  select * into v_tipo from redes.tipos_intervencion where codigo = d ->> 'tipo' and activo;
  if not found then perform tecnica.f_error('Elija el tipo de intervención'); end if;
  if d ->> 'nace_de' = 'dano' and not v_tipo.admite_dano then perform tecnica.f_error(format('«%s» no atiende un daño: elija correctivo, reparación o reposición', v_tipo.nombre)); end if;
  v_modo := d ->> 'inversion_modo';
  if v_tipo.es_inversion and coalesce(v_modo, '') not in ('nuevo', 'mejora') then perform tecnica.f_error('Diga qué tipo de inversión es: activo nuevo o mejora de un activo existente'); end if;
  if not v_tipo.es_inversion then v_modo := null; end if;
  v_sis := d ->> 'sistema';
  if coalesce(v_sis, '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;

  -- 2. activo: el elegido, «no identificado» o el que crea la inversión
  if v_modo = 'nuevo' then
    v_nuevo := d -> 'nuevo';
    if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null or d ->> 'no_identificado' is not null then perform tecnica.f_error('Una inversión en un activo nuevo no lleva un activo existente'); end if;
    if v_nuevo is null or jsonb_typeof(v_nuevo) <> 'object' then perform tecnica.f_error('Diga qué activo nuevo se construyó'); end if;
    select * into v_tn from redes.v_tipo_visible where prefijo = upper(coalesce(v_nuevo ->> 'prefijo', '')) and sistema = v_sis and geometria in ('punto', 'linea');
    if not found then perform tecnica.f_error('Elija el tipo del activo nuevo (del mismo sistema)'); end if;
    v_clase_n := nullif(v_nuevo ->> 'clase', '');
    if v_clase_n is not null and not exists (select 1 from redes.clases_activo where prefijo = v_tn.prefijo and codigo = v_clase_n) then perform tecnica.f_error('Esa clase no existe para el tipo elegido'); end if;
    if v_clase_n is null and exists (select 1 from jsonb_array_elements(v_tn.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean) then
      perform tecnica.f_error(format('Elija la clase del activo nuevo (%s)', v_tn.nombre_visible));
    end if;
    v_mat_n := nullif(v_nuevo ->> 'material', '');
    if v_mat_n is not null and not exists (select 1 from redes.materiales where codigo = v_mat_n) then perform tecnica.f_error('Ese material no existe'); end if;
    v_diam_n := (v_nuevo ->> 'diametro_mm')::numeric;
    if v_diam_n is not null and (v_diam_n <= 0 or v_diam_n > 5000) then perform tecnica.f_error('El diámetro va de 1 a 5.000 mm'); end if;
    v_nom_n := nullif(btrim(coalesce(v_nuevo ->> 'nombre', '')), '');
    if v_nom_n is not null and length(v_nom_n) > 120 then perform tecnica.f_error('El nombre del activo nuevo admite hasta 120 caracteres'); end if;
    v_pts := v_nuevo -> 'puntos';
    if v_pts is null or jsonb_typeof(v_pts) <> 'array' then perform tecnica.f_error('Marque en el mapa dónde quedó el activo nuevo'); end if;
    if v_tn.geometria = 'punto' and jsonb_array_length(v_pts) <> 1 then perform tecnica.f_error('Marque un solo punto para el activo nuevo'); end if;
    if v_tn.geometria = 'linea' and jsonb_array_length(v_pts) not between 2 and 50 then perform tecnica.f_error('Marque el inicio y el fin del tramo nuevo'); end if;
    for v_p in select e from jsonb_array_elements(v_pts) e loop
      if jsonb_typeof(v_p) <> 'array' or jsonb_array_length(v_p) <> 2 or (v_p ->> 0)::numeric not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max')
         or (v_p ->> 1)::numeric not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
        perform tecnica.f_error('El activo nuevo debe quedar dentro de Valledupar');
      end if;
    end loop;
    v_geom_nuevo := case when v_tn.geometria = 'punto' then ST_SetSRID(ST_MakePoint((v_pts -> 0 ->> 1)::double precision, (v_pts -> 0 ->> 0)::double precision), 4326)
                         else ST_SetSRID(ST_MakeLine(array(select ST_MakePoint((e ->> 1)::double precision, (e ->> 0)::double precision) from jsonb_array_elements(v_pts) with ordinality x(e, o) order by o)), 4326) end;
    if v_tn.geometria = 'linea' and ST_Length(v_geom_nuevo::geography) < 0.5 then perform tecnica.f_error('El tramo nuevo es demasiado corto: marque el inicio y el fin'); end if;
  elsif nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado then perform tecnica.f_error('El activo elegido no existe o está retirado: elíjalo de nuevo en el mapa'); end if;
    if v_act.sistema <> v_sis then perform tecnica.f_error('El activo elegido no es de ese sistema'); end if;
    v_activo := v_act.activo_id;
  else
    v_noid := nullif(btrim(coalesce(d ->> 'no_identificado', '')), '');
    if v_noid is null or length(v_noid) < 3 or length(v_noid) > 120 then perform tecnica.f_error('Elija el activo en el mapa o, si no lo identifica, diga qué es (3 a 120 caracteres)'); end if;
  end if;

  -- ubicación de la intervención: nunca se rechaza por estar fuera de la zona (se marca)
  v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric;
  if v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then perform tecnica.f_error('Falta la ubicación de la intervención'); end if;
  if coalesce(d ->> 'ubicacion_origen', '') not in ('gps', 'mapa', 'activo') then perform tecnica.f_error('Falta de dónde sale la ubicación'); end if;
  v_fuera := v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max');
  v_pto := ST_SetSRID(ST_MakePoint(v_lon, v_lat), 4326);

  -- activos también intervenidos (mismo sistema, vigentes, sin repetir y distintos del principal)
  if d -> 'tambien' is not null then
    if jsonb_typeof(d -> 'tambien') <> 'array' then perform tecnica.f_error('Los activos también intervenidos no son válidos'); end if;
    if jsonb_array_length(d -> 'tambien') > redes.f_param('itv_max_activos_tambien') then
      perform tecnica.f_error(format('Hasta %s activos también intervenidos', redes.f_param('itv_max_activos_tambien')::integer));
    end if;
    for v_x in select jsonb_array_elements_text(d -> 'tambien') loop
      select activo_id into v_xid from redes.activo_vigente_mat where codigo = upper(btrim(v_x)) and not retirado and sistema = v_sis;
      if v_xid is null then perform tecnica.f_error(format('El activo también intervenido «%s» no existe, está retirado o no es de ese sistema', v_x)); end if;
      if v_xid = v_activo then perform tecnica.f_error('El activo principal no va otra vez en «también intervenidos»'); end if;
      if v_xid = any (v_tambien) then perform tecnica.f_error(format('El activo «%s» está repetido en «también intervenidos»', v_x)); end if;
      v_tambien := v_tambien || v_xid;
    end loop;
  end if;

  -- 3. fechas y horas del trabajo (contra la hora del servidor)
  v_t_ini := redes.f_instante(d ->> 't_inicio', 'inicio');
  v_t_fin := redes.f_instante(d ->> 't_fin', 'fin');
  if v_t_ini is null or v_t_fin is null then perform tecnica.f_error('Escriba el inicio y el fin de la intervención'); end if;
  if v_t_fin > v_ahora + interval '2 minutes' then perform tecnica.f_error('El fin está en el futuro: la intervención se registra cuando ya se hizo'); end if;
  if v_t_ini > v_t_fin then perform tecnica.f_error('El inicio no puede ser después del fin'); end if;
  -- el tope de días y de horas es del operario; el supervisor y el administrador registran las obras largas desde el escritorio sin él
  -- §28.1 (Corte 5a): nadie registra sin tope. El supervisor y el administrador, hasta itv_dias_atras_max_supervisor días atrás; el operador, itv_dias_atras_max
  if v_t_ini < v_ahora - make_interval(days => redes.f_param(case when v_super then 'itv_dias_atras_max_supervisor' else 'itv_dias_atras_max' end)::integer) then
    perform tecnica.f_error(format('El inicio no puede ser de hace más de %s días', redes.f_param(case when v_super then 'itv_dias_atras_max_supervisor' else 'itv_dias_atras_max' end)::integer));
  end if;
  if v_t_fin - v_t_ini > make_interval(hours => redes.f_param('itv_max_horas')::integer) then      -- §28.1: el mismo tope para todos
    perform tecnica.f_error(format('Una intervención dura hasta %s horas: una obra larga se registra en varias intervenciones, cada una con su foto', redes.f_param('itv_max_horas')::integer));
  end if;
  v_inicio := redes.f_instante(d ->> 'inicio_dispositivo', 'apertura del formulario');
  if v_inicio is not null and (v_inicio > v_ahora + interval '2 minutes' or v_inicio < v_ahora - make_interval(hours => tecnica.f_max_horas_inicio())) then
    perform tecnica.f_error(format('Este formulario se abrió hace más de %s horas o la hora de su celular está adelantada. Revise la hora y vuelva a enviar.', tecnica.f_max_horas_inicio()));
  end if;

  -- daño que atiende: abierto, del mismo sistema y del activo, de un también intervenido o cercano
  if d ->> 'nace_de' = 'dano' then
    if nullif(btrim(coalesce(d ->> 'dano', '')), '') is null then perform tecnica.f_error('Elija el daño o falla que se atiende'); end if;
    perform pg_advisory_xact_lock(hashtext('redes.dano.' || upper(btrim(d ->> 'dano'))));
    select * into v_dano from redes.v_dano where codigo = upper(btrim(d ->> 'dano'));
    if not found then perform tecnica.f_error('Ese daño no existe'); end if;
    if v_dano.estado not in ('reportado', 'en_atencion') then perform tecnica.f_error(format('El daño %s ya está %s', v_dano.codigo, case v_dano.estado when 'atendido' then 'atendido' else 'oculto' end)); end if;
    if not redes.f_dano_elegible(v_dano, v_sis, array_remove(v_tambien || v_activo, null), v_pto) then
      perform tecnica.f_error(format('El daño %s no es de este activo ni de los cercanos (%s m)', v_dano.codigo, redes.f_param('itv_radio_danos_m')::integer));
    end if;
    if v_dano.t_inicio_reparacion is null and v_t_ini < v_dano.t_detectado then
      perform tecnica.f_error(format('La intervención empezó antes de que se detectara el daño %s: revise las horas', v_dano.codigo));
    end if;
    if v_resuelve and v_dano.t_inicio_reparacion is not null and v_t_fin < v_dano.t_inicio_reparacion then
      perform tecnica.f_error(format('La intervención terminó antes del inicio de la reparación que ya tenía el daño %s', v_dano.codigo));
    end if;
  elsif v_resuelve then
    perform tecnica.f_error('«Con esta queda resuelto el daño» solo va cuando la intervención nace de un daño');
  end if;

  -- 4. qué se hizo y materiales
  if length(v_desc) < 10 or length(v_desc) > 2000 then perform tecnica.f_error('Describa qué se hizo (10 a 2.000 caracteres)'); end if;
  if jsonb_typeof(v_mats) <> 'array' or jsonb_array_length(v_mats) > redes.f_param('itv_max_materiales') then perform tecnica.f_error(format('Hasta %s materiales', redes.f_param('itv_max_materiales')::integer)); end if;
  for v_m in select e from jsonb_array_elements(v_mats) e loop
    if jsonb_typeof(v_m) <> 'object' or length(btrim(coalesce(v_m ->> 'material', ''))) not between 2 and 80 then perform tecnica.f_error('Cada material lleva su nombre (2 a 80 caracteres)'); end if;
    if coalesce((v_m ->> 'cantidad')::numeric, 0) <= 0 or (v_m ->> 'cantidad')::numeric >= 1000000 then perform tecnica.f_error(format('La cantidad de «%s» no es válida', btrim(v_m ->> 'material'))); end if;
    if not exists (select 1 from redes.unidades_material where codigo = v_m ->> 'unidad' and activo) then perform tecnica.f_error(format('Elija la unidad de «%s»', btrim(v_m ->> 'material'))); end if;
  end loop;

  -- 5. quién la ejecuta
  if coalesce(d ->> 'ejecutor', '') not in ('emdupar', 'contratista') then perform tecnica.f_error('Diga quién la ejecuta: EMDUPAR o contratista'); end if;
  if d ->> 'ejecutor' = 'contratista' then
    if nullif(d ->> 'contratista', '') is not null then
      select id into v_ctr from redes.contratistas where codigo = d ->> 'contratista' and activo;
      if v_ctr is null then perform tecnica.f_error('Ese contratista no está en el catálogo'); end if;
    else
      v_ctr_nom := nullif(btrim(coalesce(d ->> 'contratista_nombre', '')), '');
      if v_ctr_nom is null or length(v_ctr_nom) not between 2 and 120 then perform tecnica.f_error('Elija o escriba el contratista'); end if;
    end if;
  elsif nullif(d ->> 'contratista', '') is not null or nullif(btrim(coalesce(d ->> 'contratista_nombre', '')), '') is not null then
    perform tecnica.f_error('El contratista solo va si la ejecuta un contratista');
  end if;
  if v_orden is not null and length(v_orden) > 60 then perform tecnica.f_error('El contrato u orden admite hasta 60 caracteres'); end if;
  if v_comp is not null and length(v_comp) not between 2 and 200 then perform tecnica.f_error('Los compañeros de cuadrilla admiten hasta 200 caracteres'); end if;

  -- 6. de dónde salen los recursos (D-8): el operario marca solo quién aporta; el supervisor y el administrador pueden poner valores
  v_fuentes := redes.f_fuentes_validas(d -> 'fuentes', v_super, false);

  -- 7. fotos (JPEG) y documentos (PDF): el tamaño y el tipo se leen de Storage (nunca se le creen al celular)
  if jsonb_typeof(v_arch) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_arch);
  if v_n > 0 and (select count(distinct (e ->> 'n')::integer) <> v_n or min((e ->> 'n')::integer) <> 1 or max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_arch) e) then
    perform tecnica.f_error('El orden de los archivos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  for v_f in select e from jsonb_array_elements(v_arch) e order by (e ->> 'n')::integer loop
    if coalesce(v_f ->> 'clase', '') not in ('antes', 'durante', 'despues', 'documento') then perform tecnica.f_error('Cada foto dice si es de antes, de durante o de después'); end if;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^intervenciones/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || case when v_f ->> 'clase' = 'documento' then '\.pdf$' else '\.jpg$' end) then
      perform tecnica.f_error(format('La ruta del archivo %s no corresponde a esta intervención', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró el archivo %s: súbalo de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('El archivo %s está vacío', v_f ->> 'n')); end if;
    if v_f ->> 'clase' = 'documento' then
      v_nd := v_nd + 1;
      if v_mime is distinct from 'application/pdf' then perform tecnica.f_error(format('El documento %s debe ser PDF', v_f ->> 'n')); end if;
      if v_size > redes.f_param('max_bytes_doc_itv') then perform tecnica.f_error(format('El documento %s pesa más de lo permitido (%s KB)', v_f ->> 'n', (redes.f_param('max_bytes_doc_itv') / 1024)::integer)); end if;
    else
      v_nf := v_nf + 1;
      if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
      if v_size > redes.f_param('max_bytes_foto_itv') then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', (redes.f_param('max_bytes_foto_itv') / 1024)::integer)); end if;
    end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'clase', v_f ->> 'clase', 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;
  if v_nf > v_prep.fotos or v_nd > v_prep.documentos or v_nf > redes.f_param('max_fotos_itv') or v_nd > redes.f_param('max_docs_itv') then
    perform tecnica.f_error(format('Una intervención lleva hasta %s fotos y %s documentos', redes.f_param('max_fotos_itv')::integer, redes.f_param('max_docs_itv')::integer));
  end if;
  -- en la calle, siempre al menos una foto; sin fotos solo el supervisor o el administrador (p. ej., desde el escritorio), con el motivo
  -- §25.8: nadie registra «sin evidencia fotográfica» (ni el supervisor ni el administrador); siempre al menos una foto
  if v_sinev is not null then
    perform tecnica.f_error('Ya no se registra «sin evidencia fotográfica»: tome al menos una foto de la intervención');
  end if;
  if v_nf < redes.f_param('min_fotos_itv') then
    perform tecnica.f_error(format('Tome al menos %s foto de la intervención', redes.f_param('min_fotos_itv')::integer));
  end if;

  -- código ITV-000123 (candado de fila del consecutivo)
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'ITV' returning ultimo into v_cons;
  v_codigo := 'ITV-' || lpad(v_cons::text, 6, '0');

  -- inversión, activo nuevo: el activo nace con la intervención, «por verificar», con su origen según quién aporta
  if v_modo = 'nuevo' then
    select case when bool_and(f ->> 'aportante' = 'emdupar') then 'emdupar' when bool_or(f ->> 'aportante' = 'emdupar') then 'mixto' else 'tercero' end,
           (select f2 ->> 'aportante' from jsonb_array_elements(v_fuentes) f2 where f2 ->> 'aportante' <> 'emdupar' order by (f2 ->> 'n')::integer limit 1)
      into v_origen, v_aport from jsonb_array_elements(v_fuentes) f;
    v_activo := redes.f_activo_crear(v_tn.prefijo, v_geom_nuevo, v_clase_n, v_mat_n, v_diam_n, v_nom_n, (v_t_fin at time zone 'America/Bogota')::date,
                                     jsonb_build_object('intervencion', v_codigo), v_origen, v_aport, v_email,
                                     format('Creado por la intervención %s (inversión, activo nuevo): por verificar', v_codigo));
    v_creado := true;
    v_cod_nuevo := (select codigo from redes.activos where id = v_activo);
  end if;

  insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, inversion_modo, sistema, activo_id, activo_creado, no_ident_que_es, lat, lon,
         ubicacion_origen, precision_m, fuera_de_zona, t_inicio, t_fin, inicio_en, inicio_origen, descripcion, ejecutor, contratista_id, contratista_nombre,
         contrato_orden, companeros, sin_evidencia_motivo, resuelve_dano, autor, registrado_en)
  values (p_id, v_codigo, d ->> 'nace_de', v_dano.id, v_tipo.codigo, v_modo, v_sis, v_activo, v_creado, v_noid, round(v_lat, 6), round(v_lon, 6),
          d ->> 'ubicacion_origen', (d ->> 'precision_m')::numeric, v_fuera, v_t_ini, v_t_fin, v_inicio, case when v_inicio is not null then 'dispositivo' end,
          v_desc, d ->> 'ejecutor', v_ctr, v_ctr_nom, v_orden, v_comp, v_sinev, v_resuelve, v_email, v_ahora);
  insert into redes.intervencion_activos (intervencion_id, activo_id, n) select p_id, x, o from unnest(v_tambien) with ordinality u(x, o);
  insert into redes.intervencion_materiales (intervencion_id, n, material, cantidad, unidad)
  select p_id, o, btrim(e ->> 'material'), (e ->> 'cantidad')::numeric, e ->> 'unidad' from jsonb_array_elements(v_mats) with ordinality x(e, o);
  insert into redes.intervencion_fuentes (intervencion_id, version, n, aportante_codigo, entidad, valor, porcentaje, soporte, fuente, autor)
  select p_id, 1, (f ->> 'n')::smallint, f ->> 'aportante', f ->> 'entidad', (f ->> 'valor')::numeric, (f ->> 'porcentaje')::numeric, f ->> 'soporte',
         case when v_super then 'supervisor' else 'formulario' end, v_email from jsonb_array_elements(v_fuentes) f;
  insert into redes.intervencion_archivos (intervencion_id, n, clase, ruta_storage, bytes, mime)
  select p_id, (x ->> 'n')::smallint, x ->> 'clase', x ->> 'ruta', (x ->> 'bytes')::integer, x ->> 'mime' from jsonb_array_elements(v_ref) x;
  insert into redes.intervencion_eventos (intervencion_id, tipo, autor) values (p_id, 'cerrada', v_email);       -- flujo A (D-6)
  if v_creado then
    insert into redes.intervencion_eventos (intervencion_id, tipo, activo_id, motivo, autor) values (p_id, 'crear_activo', v_activo, format('Inversión: se creó el activo %s, por verificar', v_cod_nuevo), v_email);
  end if;

  -- intervención que nace de un daño (un daño puede tener varias, David, respuesta 2 al 3a):
  --   · la primera le pone el inicio de la reparación (si no lo tenía) y el daño queda «en atención»;
  --   · la que marca «Con esta queda resuelto el daño» le pone el servicio restablecido y lo deja «atendido».
  if v_dano.id is not null then
    if v_dano.t_inicio_reparacion is null or v_resuelve then
      insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor)
      values (v_dano.id, case when v_dano.t_inicio_reparacion is null then v_t_ini end, case when v_resuelve then v_t_fin end, 'intervencion', v_email);
    end if;
    insert into redes.dano_eventos (dano_id, tipo, intervencion_id, motivo, autor)
    values (v_dano.id, case when v_resuelve then 'atendido' else 'en_atencion' end, p_id,
            case when v_resuelve then format('Resuelto con la intervención %s (%s)', v_codigo, v_tipo.nombre)
                 else format('Atendido en parte con la intervención %s (%s); sigue abierto', v_codigo, v_tipo.nombre) end, v_email);
    select x.estado into v_dano_estado from redes.v_dano x where x.id = v_dano.id;
  end if;

  -- auditoría sin la posición ni los valores
  perform tecnica.f_auditar(v_email, 'redes_crear_intervencion', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'nace_de', d ->> 'nace_de', 'dano', v_dano.codigo,
          'sistema', v_sis, 'activo', coalesce(v_act.codigo, v_cod_nuevo), 'activo_creado', v_creado, 'no_identificado', v_noid is not null, 'tambien', cardinality(v_tambien),
          'fotos', v_nf, 'documentos', v_nd, 'sin_evidencia', v_nf = 0, 'ejecutor', d ->> 'ejecutor', 'resuelve_dano', v_resuelve), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo, 'activo_creado', x.activo_creado,
                                    'dano', x.dano_codigo, 'dano_estado', v_dano_estado, 'recursos', x.recursos, 'sin_evidencia', x.sin_evidencia, 'fuera_de_zona', x.fuera_de_zona,
                                    'duracion_s', x.duracion_s, 'repetido', false) from redes.v_intervencion x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.intervenciones where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_intervencion x where x.id = p_id);
  end if;
  perform tecnica.f_error('Uno de los archivos ya está usado en otra intervención');
  return null;
end $function$;

-- public.geoportal_redes_cuadrilla_fijar(text,bigint,text,boolean,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_cuadrilla_fijar(p_solicitante text, p_id bigint, p_nombre text, p_activa boolean, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 'crean o cambian las cuadrillas (§28.5: también el supervisor de distribución)'); v_nom text := nullif(btrim(coalesce(p_nombre, '')), ''); v_mot text := btrim(coalesce(p_motivo, ''));
        c redes.cuadrillas%rowtype; v_id bigint;
begin
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (10 a 500 caracteres)'); end if;
  if v_nom is not null and length(v_nom) not between 2 and 60 then perform tecnica.f_error('El nombre de la cuadrilla lleva de 2 a 60 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.cuadrillas'));
  if v_nom is not null and exists (select 1 from redes.cuadrillas x where lower(btrim(x.nombre)) = lower(v_nom) and x.id is distinct from p_id) then
    perform tecnica.f_error('Ya existe una cuadrilla con ese nombre');
  end if;
  if p_id is null then
    if v_nom is null then perform tecnica.f_error('Escriba el nombre de la cuadrilla'); end if;
    insert into redes.cuadrillas (nombre, activa, orden, autor) values (v_nom, coalesce(p_activa, true), coalesce((select max(orden) from redes.cuadrillas), 0) + 1, v_email)
    returning id into v_id;
    perform tecnica.f_auditar(v_email, 'redes_cuadrilla_crear', v_id::text, jsonb_build_object('nombre', v_nom, 'motivo', v_mot), null);
    return jsonb_build_object('id', v_id, 'nombre', v_nom, 'activa', coalesce(p_activa, true), 'nueva', true);
  end if;
  select * into c from redes.cuadrillas where id = p_id for update;
  if not found then perform tecnica.f_error('No existe esa cuadrilla', 'P0002'); end if;
  if coalesce(v_nom, c.nombre) = c.nombre and coalesce(p_activa, c.activa) = c.activa then perform tecnica.f_error('Ya está así: no hay nada que cambiar'); end if;
  update redes.cuadrillas set nombre = coalesce(v_nom, nombre), activa = coalesce(p_activa, activa) where id = p_id;
  perform tecnica.f_auditar(v_email, 'redes_cuadrilla_cambiar', p_id::text, jsonb_build_object('antes', jsonb_build_object('nombre', c.nombre, 'activa', c.activa),
          'despues', jsonb_build_object('nombre', coalesce(v_nom, c.nombre), 'activa', coalesce(p_activa, c.activa)), 'motivo', v_mot), null);
  return jsonb_build_object('id', p_id, 'nombre', coalesce(v_nom, c.nombre), 'activa', coalesce(p_activa, c.activa), 'nueva', false);
end $function$;

-- public.geoportal_redes_catalogo(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_catalogo(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el catálogo de redes');
begin
  return jsonb_build_object('puede_editar', public.geoportal_es_admin(v_email), 'puede_cuadrillas', true,      -- §28.5
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre, 'nombre_visible', t.nombre_visible,
               'alias', case when t.nombre_visible <> t.nombre then t.nombre_visible end, 'sistema', t.sistema, 'geometria', t.geometria, 'es_base', t.es_base, 'activo', t.activo,
               'vigentes', coalesce(n.n, 0)) order by t.sistema, t.orden, t.prefijo)
        from redes.v_tipo_visible t
        left join (select m.prefijo, count(*) as n from redes.activo_vigente_mat m where not m.retirado and not m.oculto group by m.prefijo) n on n.prefijo = t.prefijo), '[]'::jsonb),
    'materiales', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden, nombre) from redes.materiales), '[]'::jsonb),
    'estados', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'cuenta_vigente', cuenta_vigente) order by orden) from redes.estados_activo), '[]'::jsonb),
    'contratistas', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by nombre) from redes.contratistas), '[]'::jsonb),
    'aportantes', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden) from redes.entidades_aportantes), '[]'::jsonb),
    'tipos_intervencion', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden) from redes.tipos_intervencion), '[]'::jsonb),
    'tipos_dano', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'clase', clase, 'activo', activo) order by clase, orden) from redes.tipos_dano), '[]'::jsonb),
    'causas', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden) from redes.causas), '[]'::jsonb),
    'cuadrillas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre, 'activa', c.activa,
                     'personas', (select count(*) from redes.v_personal_ficha f where f.cuadrilla_id = c.id)) order by c.orden, lower(c.nombre)) from redes.cuadrillas c), '[]'::jsonb));
end $function$;

-- public.geoportal_redes_personal(text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_personal(p_solicitante text, p_buscar text DEFAULT NULL::text, p_filtro text DEFAULT 'todas'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 've el personal de distribución'); v_q text := nullif(lower(btrim(coalesce(p_buscar, ''))), '');
begin
  if coalesce(p_filtro, '') not in ('todas', 'distribucion', 'planta', 'sin_area') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_q is not null and length(v_q) > 80 then perform tecnica.f_error('La búsqueda es demasiado larga'); end if;
  return jsonb_build_object('filtro', p_filtro, 'yo', v_email,
    'formularios', coalesce((select jsonb_agg(jsonb_build_object('clave', fd.clave, 'nombre', fd.nombre) order by fd.orden) from redes.formularios_distribucion fd where fd.activo), '[]'::jsonb),      -- §28.2
    'cuadrillas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre) order by c.orden, lower(c.nombre)) from redes.cuadrillas c where c.activa), '[]'::jsonb),
    'personas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'email', p.email, 'nombre', p.nombre, 'perfil', case when p.ver_dashboard_redes then 'supervisor' else 'operador' end,
               'dashboard_redes', p.ver_dashboard_redes, 'dashboard_ptap', p.ver_dashboard_tecnico, 'registro_tecnico', p.ver_registro_tecnico,
               'area', f.area, 'cargo', f.cargo,
               'cuadrilla', case when c.id is not null then jsonb_build_object('id', c.id, 'nombre', c.nombre, 'activa', c.activa) end,
               -- la casilla solo es del operador: los supervisores (de distribución o de planta) ven el geovisor por su permiso
               'geovisor', case when p.ver_dashboard_redes or p.ver_dashboard_tecnico then 'por_permiso' when coalesce(f.geovisor, false) then 'si' else 'no' end,
               'formularios', coalesce((select jsonb_agg(fd.clave order by fd.orden) from redes.formularios_distribucion fd where fd.activo and tecnica.f_formulario_asignado(p.email, fd.clave)), '[]'::jsonb),
               'activo_tecnica', tecnica.f_tecnica_activa(p.email), 'ultimo_cambio', f.ultimo_cambio)
             order by lower(coalesce(p.nombre, p.email)), p.email)
        from (select lb.email, nullif(btrim(lb.nombre), '') as nombre, lb.ver_dashboard_redes, lb.ver_dashboard_tecnico, lb.ver_registro_tecnico
                from public.geoportal_lista_blanca lb where lb.activo and lb.rol <> 'admin' and (lb.ver_registro_tecnico or lb.ver_dashboard_redes)) p
        left join redes.v_personal_ficha f on f.persona = p.email
        left join redes.cuadrillas c on c.id = f.cuadrilla_id
       where (v_q is null or position(v_q in lower(coalesce(p.nombre, '') || ' ' || p.email)) > 0)
         and case p_filtro when 'distribucion' then coalesce(f.area in ('distribucion', 'ambas'), false) when 'planta' then coalesce(f.area in ('planta', 'ambas'), false)
                           when 'sin_area' then f.area is null else true end), '[]'::jsonb));
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 26 — RPC NUEVA: el supervisor de distribución asigna o quita a su gente los formularios de distribución (§28.2)
-- PROPUESTA. No se ha ejecutado en la base real. security definer, search_path fijo, mensajes con HINT msg_usuario; solo service_role.
-- · Solo los formularios de redes.formularios_distribucion (hoy «Reportar daño o falla» y «Registrar intervención»). Los de planta siguen en
--   Personal del Dashboard PTAP, con sus RPC de siempre (geoportal_tec_asignar_formulario y geoportal_tec_quitar_formulario), que no se tocan.
-- · Escribe un EVENTO en tecnica.personal_tecnico_eventos (la misma tabla viva que ya filtra la captura), con la misma forma que las de planta,
--   y la señal de tiempo real en tecnica.senal_cambio. Nada se actualiza ni se borra. Siempre con motivo (10 caracteres o más).
-- =====================================================================
create function public.geoportal_redes_personal_formulario(p_solicitante text, p_persona text, p_formulario text, p_asignar boolean, p_motivo text, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare
  v_email text := redes.f_supervisor(p_solicitante, 'asignan los formularios de distribución'); v_p text := lower(btrim(coalesce(p_persona, '')));
  lb public.geoportal_lista_blanca; v_mot text := btrim(coalesce(p_motivo, '')); f redes.formularios_distribucion%rowtype; v_tiene boolean;
begin
  if p_asignar is null then perform tecnica.f_error('Diga si se asigna o se quita el formulario'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  select * into f from redes.formularios_distribucion where clave = p_formulario and activo;
  if not found then perform tecnica.f_error('Ese no es un formulario de distribución (los de planta se asignan en el Dashboard PTAP)'); end if;
  lb := redes.f_persona_tecnica(v_p);
  if lb.email is null then perform tecnica.f_error('Esa persona no está en Técnica (o su cuenta está inactiva)', 'P0002'); end if;
  if p_asignar and not lb.ver_registro_tecnico then perform tecnica.f_error('Esta persona no tiene «Registro técnico»: el administrador debe dárselo primero', '55000'); end if;
  if v_p = v_email then perform tecnica.f_error('No puede cambiar sus propios formularios: pídaselo a otro supervisor o al administrador'); end if;
  perform pg_advisory_xact_lock(hashtextextended('pte|' || v_p, 0));      -- el mismo candado que usan las RPC de planta
  v_tiene := tecnica.f_formulario_asignado(v_p, f.clave);
  if v_tiene = p_asignar then perform tecnica.f_error(case when p_asignar then 'Ya tiene ese formulario asignado' else 'No tiene ese formulario asignado' end); end if;
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, motivo, autor)
  values (v_p, case when p_asignar then 'asignar_formulario' else 'quitar_formulario' end, f.clave, v_mot, v_email);
  insert into tecnica.senal_cambio (tabla) values ('personal_tecnico_eventos');
  perform tecnica.f_auditar(v_email, case when p_asignar then 'redes_asignar_formulario' else 'redes_quitar_formulario' end, v_p, jsonb_build_object('formulario', f.clave, 'motivo', v_mot), p_ip);
  return jsonb_build_object('persona', v_p, 'formulario', f.clave, 'nombre', f.nombre, 'asignado', p_asignar);
end $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas, vista y funciones internas nuevas: nadie de la API. RPC public.geoportal_redes_* (las nuevas, las reemplazadas y las de antes): solo execute a service_role.
-- =====================================================================
revoke all on all tables in schema redes from public, anon, authenticated, service_role;
revoke all on all sequences in schema redes from public, anon, authenticated, service_role;
revoke all on all functions in schema redes from public, anon, authenticated, service_role;
revoke all on table tecnica.puntos_ubicacion, tecnica.punto_eventos from public, anon, authenticated, service_role;
revoke all on sequence tecnica.puntos_ubicacion_id_seq, tecnica.punto_eventos_id_seq from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte5a', 'migracion_redes_corte5a', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.puntos_ubicacion', 'tecnica.punto_eventos', 'redes.formularios_distribucion')), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 25, 26 y 40, en la misma transacción.
-- Como las de los cortes anteriores: corre después de la carga real y de los cortes publicados; NO supone códigos ni conteos de la base. Arma su red de
-- prueba (ID 99700xx; nodos V997, J-997 y Tee-997) y sus puntos de muestreo (MUE-99nn). Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 5a … RESULTADO: N de N pruebas correctas — SIN FALLAS
-- =====================================================================
create temp table _r (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.reg(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as
$$ insert into _r (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $$;
create function pg_temp.err(p_nombre text, p_sql text, p_estado text default null, p_texto text default null) returns void language plpgsql as $$
declare v_e text; v_m text;
begin
  begin
    execute p_sql;
    perform pg_temp.reg(p_nombre, false, 'No falló y debía fallar');
  exception when others then
    get stacked diagnostics v_e = returned_sqlstate, v_m = message_text;
    perform pg_temp.reg(p_nombre, (p_estado is null or v_e = p_estado) and (p_texto is null or position(p_texto in v_m) > 0), 'SQLSTATE ' || v_e || ': ' || left(v_m, 200));
  end;
end $$;
create function pg_temp.sha(p text) returns text language sql as $$ select encode(sha256(convert_to(p, 'UTF8')), 'hex') $$;
-- posición de prueba: x, y en metros aproximados desde un origen dentro de Valledupar
create function pg_temp.p(x numeric, y numeric) returns text language sql as $$ select (-73.2400 + x * 0.0000091)::text || ' ' || (10.4700 + y * 0.0000090)::text $$;
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4700 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.2400 + x * 0.0000091, 6) $$;
create function pg_temp.tramo(p_orden integer, p_id integer, p_label text, p_ini text, p_ini_nom text, p_fin text, p_fin_nom text, p_wkt text) returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', p_wkt, 'atributos', jsonb_build_object('ID', p_id, 'LABEL', p_label, 'MATERIAL', 'PVC', 'D', 3, 'LENGTH', 100, 'ZONE', null,
         'IS_ACTIVE?', true, 'CHK_VLVE?', false, 'STARTNODID', p_ini, 'STARTNODE', p_ini_nom, 'STOPNODEID', p_fin, 'STOPNODE', p_fin_nom)) $$;
-- archivo de prueba en Storage (la subida real la hace el celular con la URL firmada)
create function pg_temp.archivo(p_ruta text, p_bytes integer default 300000, p_mime text default 'image/jpeg') returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', p_bytes, 'mimetype', p_mime)) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
-- datos base de una intervención válida (se cambian claves en cada prueba)
create function pg_temp.itv(p_archivos jsonb, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('nace_de', 'programada', 'tipo', 'preventivo', 'sistema', 'acueducto', 'activo', current_setting('zt.red1'),
         'lat', pg_temp.lat(0), 'lon', pg_temp.lon(50), 'precision_m', 5, 'ubicacion_origen', 'gps', 't_inicio', pg_temp.iso('-3 hours'), 't_fin', pg_temp.iso('-1 hours'),
         'descripcion', 'Revisión y limpieza de prueba del tramo', 'materiales', '[]'::jsonb, 'ejecutor', 'emdupar',
         'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')), 'archivos', p_archivos) || p_extra $$;
create function pg_temp.a1(p_ruta text, p_clase text default 'despues') returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('n', 1, 'clase', p_clase, 'ruta', p_ruta)) $$;
-- un daño válido (para los que se atienden), con su foto ya en Storage
create function pg_temp.dano(p_quien text, p_extra jsonb) returns jsonb language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_dano(p_quien, 1);
begin
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  return public.geoportal_redes_crear_dano(p_quien, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', current_setting('zt.red1'),
         'lat', pg_temp.lat(0), 'lon', pg_temp.lon(40), 'ubicacion_origen', 'gps', 't_detectado', pg_temp.iso('-5 hours'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
         'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))) || p_extra);
end $$;
-- prepara una intervención y sube sus archivos de prueba; devuelve la preparación
create function pg_temp.preparar(p_quien text, p_fotos integer, p_docs integer default 0) returns jsonb language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_intervencion(p_quien, p_fotos, p_docs); x jsonb;
begin
  for x in select e from jsonb_array_elements(v_p -> 'fotos') e loop perform pg_temp.archivo(x ->> 'ruta'); end loop;
  for x in select e from jsonb_array_elements(v_p -> 'documentos') e loop perform pg_temp.archivo(x ->> 'ruta', 800000, 'application/pdf'); end loop;
  return v_p;
end $$;

-- una carga de acueducto de prueba, publicada, con las filas dadas
create function pg_temp.cargar_acu(p_admin text, p_huella text, p_filas jsonb) returns jsonb language plpgsql as $$
declare v_c bigint := (public.geoportal_redes_carga_iniciar(p_admin, 'acueducto', pg_temp.sha(p_huella), 'shp', 4326, 'ID', jsonb_array_length(p_filas)) ->> 'carga_id')::bigint;
begin
  perform public.geoportal_redes_carga_lote(p_admin, v_c, p_filas);
  return jsonb_build_object('carga_id', v_c, 'resumen', public.geoportal_redes_carga_resumen(p_admin, v_c));
end $$;
create function pg_temp.mue(p_orden integer, p_codigo text, p_lat numeric, p_lon numeric, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', 'POINT(' || p_lon || ' ' || p_lat || ')',
         'atributos', jsonb_strip_nulls(jsonb_build_object('codigo', p_codigo)) || p_extra) $$;
create function pg_temp.cargar_mue(p_admin text, p_huella text, p_filas jsonb) returns bigint language plpgsql as $$
declare v_c bigint := (public.geoportal_redes_carga_iniciar(p_admin, 'muestreo', pg_temp.sha(p_huella), 'csv', 4326, 'codigo', jsonb_array_length(p_filas)) ->> 'carga_id')::bigint;
begin
  perform public.geoportal_redes_carga_lote(p_admin, v_c, p_filas);
  return v_c;
end $$;

do $prueba$
declare
  a text := 'prueba.redes7.adm@emdupar.gov.co'; sv text := 'prueba.redes7.sup@emdupar.gov.co'; op text := 'prueba.redes7.op@emdupar.gov.co';
  o2 text := 'prueba.redes7.op2@emdupar.gov.co'; sd text := 'prueba.redes7.dist@emdupar.gov.co'; sd2 text := 'prueba.redes7.dist2@emdupar.gov.co';
  sr text := 'prueba.redes7.soloredes@emdupar.gov.co'; na text := 'prueba.redes7.nada@emdupar.gov.co';
  v_red1 text; v_red2 text; v_acc text; v_nj bigint; v_c bigint; v_r jsonb; v_x jsonb; v_p jsonb; v_n integer; v_m integer; v_k text; v_t text; v_id bigint;
  v_act_otros integer; v_puntos0 integer; v_sig integer; v_m1 bigint; v_m2 bigint;
  v_total integer; v_bien integer; v_fallas text;
  c1 jsonb; c2 jsonb; c3 jsonb;
  w1 text := 'LINESTRING(' || pg_temp.p(0, 0) || ',' || pg_temp.p(100, 0) || ')';
  w2 text := 'LINESTRING(' || pg_temp.p(100, 0) || ',' || pg_temp.p(200, 0) || ')';
  w1b text := 'LINESTRING(' || pg_temp.p(0, 0) || ',' || pg_temp.p(100, 6) || ')';
  w2b text := 'LINESTRING(' || pg_temp.p(100, 6) || ',' || pg_temp.p(200, 0) || ')';
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT7 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT7 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos'),
    (sd2, 'ZT7 Otro supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos'), (sr, 'ZT7 Solo dashboard de redes', 'consulta', false, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT7 Operador', 'consulta', true, 'sin_restriccion', 'todos'),
    (o2, 'ZT7 Operador sin formularios', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT7 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'mantenimiento', a), (op, 'asignar_formulario', 'danos_fallas', a);

  -- ===================== A. §28 =====================
  -- red de prueba con el motor del 1a (la primera carga)
  c1 := pg_temp.cargar_acu(a, 'zt7-acu-1', jsonb_build_array(
    pg_temp.tramo(1, 9970001, 'Distribucion-ZT71', '99701', 'V997', '99702', 'J-997', w1), pg_temp.tramo(2, 9970002, 'Lateral-ZT72', '99702', 'J-997', '99703', 'Tee-997', w2)));
  perform public.geoportal_redes_carga_publicar(a, (c1 ->> 'carga_id')::bigint, 'Red de prueba del Corte 5a (primera carga)');
  select codigo into v_red1 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9970001';
  select codigo into v_red2 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9970002';
  select nodo_id into v_nj from redes.v_nodo_vigente where sistema = 'acueducto' and llave_modelo = '99702';
  perform set_config('zt.red1', v_red1, true);
  perform pg_temp.reg('00.01 red de prueba: 2 RED; J-997 «por clasificar»', v_red1 like 'RED-%' and v_red2 like 'RED-%'
     and (select clase_nodo from redes.v_nodo_vigente where nodo_id = v_nj) = 'por_clasificar', concat_ws(' ', v_red1, v_red2, v_nj));

  -- §28.1: el supervisor y el administrador con tope (72 h y 30 días); el operador sigue con 7 días
  v_r := public.geoportal_redes_formulario_intervencion(sd);
  perform pg_temp.reg('01.01 el formulario del supervisor dice 30 días atrás y 72 h (antes: sin tope)', (v_r -> 'reglas' ->> 'dias_atras_max')::integer = 30 and (v_r -> 'reglas' ->> 'max_horas')::integer = 72, (v_r -> 'reglas')::text);
  v_r := public.geoportal_redes_formulario_intervencion(op);
  perform pg_temp.reg('01.02 el del operador sigue en 7 días y 72 h', (v_r -> 'reglas' ->> 'dias_atras_max')::integer = 7 and (v_r -> 'reglas' ->> 'max_horas')::integer = 72);
  v_p := pg_temp.preparar(sd, 1);
  v_r := public.geoportal_redes_crear_intervencion(sd, (v_p ->> 'intervencion_id')::uuid, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'),
            jsonb_build_object('t_inicio', pg_temp.iso('-20 days'), 't_fin', pg_temp.iso('-20 days') )));
  perform pg_temp.reg('01.03 el supervisor registra una intervención de hace 20 días', v_r ->> 'codigo' like 'ITV-%', left(v_r::text, 200));
  v_p := pg_temp.preparar(sd, 1);
  perform pg_temp.err('01.04 de hace 40 días, ya no', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sd, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('t_inicio', pg_temp.iso('-40 days'), 't_fin', pg_temp.iso('-39 days')))), '22023', 'más de 30 días');
  perform pg_temp.err('01.05 una de 5 días seguidos (120 h), tampoco: «varias intervenciones, cada una con su foto»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sd, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('t_inicio', pg_temp.iso('-10 days'), 't_fin', pg_temp.iso('-5 days')))), '22023', 'varias intervenciones');
  v_p := pg_temp.preparar(a, 1);
  perform pg_temp.err('01.06 el administrador también tiene tope', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, a, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('t_inicio', pg_temp.iso('-40 days'), 't_fin', pg_temp.iso('-39 days')))), '22023', 'más de 30 días');
  v_p := pg_temp.preparar(op, 1);
  perform pg_temp.err('01.07 el operador, de hace 10 días, no (sigue en 7)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('t_inicio', pg_temp.iso('-10 days'), 't_fin', pg_temp.iso('-10 days')))), '22023', 'más de 7 días');
  perform pg_temp.reg('01.08 el tope del supervisor es un parámetro (30 días, de 1 a 90)', (select valor = 30 and minimo = 1 and maximo = 90 from redes.parametros where clave = 'itv_dias_atras_max_supervisor'));

  -- §28.2: el supervisor de distribución asigna los formularios de distribución
  v_r := public.geoportal_redes_personal_formulario(sd, o2, 'mantenimiento', true, 'Empieza a registrar intervenciones', '10.0.0.7');
  perform pg_temp.reg('02.01 el supervisor de distribución asigna «Registrar intervención»: evento en la tabla de siempre, con su autor y motivo',
     v_r ->> 'asignado' = 'true' and tecnica.f_formulario_asignado(o2, 'mantenimiento')
     and exists (select 1 from tecnica.personal_tecnico_eventos where persona = o2 and formulario = 'mantenimiento' and tipo_evento = 'asignar_formulario' and autor = sd));
  perform pg_temp.reg('02.02 con eso el operador ya captura la intervención (la regla de planta de siempre)', public.geoportal_redes_formulario_intervencion(o2) ? 'reglas');
  perform pg_temp.reg('02.03 queda la señal de tiempo real y la auditoría (con la IP)', exists (select 1 from tecnica.senal_cambio where tabla = 'personal_tecnico_eventos')
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_asignar_formulario' and referencia = o2 and ip = '10.0.0.7'));
  perform pg_temp.err('02.04 asignarlo otra vez', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'mantenimiento', true, 'Otra vez el mismo')$$, sd, o2), '22023', 'Ya tiene');
  v_r := public.geoportal_redes_personal_formulario(sd2, o2, 'mantenimiento', false, 'Ya no hace intervenciones');
  perform pg_temp.reg('02.05 quitarlo (otro supervisor): evento «quitar» y ya no captura', not tecnica.f_formulario_asignado(o2, 'mantenimiento')
     and exists (select 1 from tecnica.personal_tecnico_eventos where persona = o2 and tipo_evento = 'quitar_formulario' and autor = sd2));
  perform pg_temp.err('02.06 sin el formulario, el operador ya no abre la intervención', format($$select public.geoportal_redes_formulario_intervencion(%L)$$, o2), '42501');
  perform pg_temp.err('02.07 un formulario de planta, no (se asigna en el Dashboard PTAP)', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'entrada', true, 'Formulario de planta')$$, sd, o2), '22023', 'Dashboard PTAP');
  perform pg_temp.err('02.08 sin motivo', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'corto')$$, sd, o2), '22023', 'motivo');
  perform pg_temp.err('02.09 a sí mismo, no', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'Me lo asigno a mí')$$, sd, sd), '22023', 'propios');
  perform pg_temp.err('02.10 a quien no tiene Registro técnico, no', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'Sin registro técnico')$$, sd, sr), '55000');
  perform pg_temp.err('02.11 el operador no asigna', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'Intento del operador')$$, op, o2), '42501');
  perform pg_temp.err('02.12 el supervisor de planta tampoco (lo hace en su Dashboard PTAP)', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'Intento del de planta')$$, sv, o2), '42501');
  perform pg_temp.err('02.13 quien no es de Técnica', format($$select public.geoportal_redes_personal_formulario(%L, %L, 'danos_fallas', true, 'Persona sin Técnica')$$, sd, na), 'P0002');
  v_r := public.geoportal_redes_personal(sd, 'zt7', 'todas');
  perform pg_temp.reg('02.14 Personal lista los formularios desde la tabla de distribución y los de cada uno', v_r -> 'formularios' @> '[{"clave": "danos_fallas"}, {"clave": "mantenimiento"}]'::jsonb
     and exists (select 1 from jsonb_array_elements(v_r -> 'personas') x where x ->> 'email' = op and x -> 'formularios' = '["danos_fallas", "mantenimiento"]'::jsonb)
     and exists (select 1 from jsonb_array_elements(v_r -> 'personas') x where x ->> 'email' = o2 and x -> 'formularios' = '[]'::jsonb));
  -- §28.5: las cuadrillas también las crea el supervisor de distribución
  v_r := public.geoportal_redes_cuadrilla_fijar(sd, null, 'ZT7 Cuadrilla del supervisor', null, 'La crea el supervisor de distribución');
  perform pg_temp.reg('03.01 el supervisor de distribución crea una cuadrilla y el catálogo se lo dice', (v_r ->> 'nueva')::boolean
     and (public.geoportal_redes_catalogo(sd) ->> 'puede_cuadrillas')::boolean and not (public.geoportal_redes_catalogo(sd) ->> 'puede_editar')::boolean);
  perform pg_temp.reg('03.02 y la desactiva', not (public.geoportal_redes_cuadrilla_fijar(sd, (v_r ->> 'id')::bigint, null, false, 'Cuadrilla de prueba que se cierra') ->> 'activa')::boolean);
  perform pg_temp.err('03.03 el operador no', format($$select public.geoportal_redes_cuadrilla_fijar(%L, null, 'ZT7 Otra', null, 'Intento del operador')$$, op), '42501');
  perform pg_temp.err('03.04 el alias de los tipos sigue siendo solo del administrador', format($$select public.geoportal_redes_alias_fijar(%L, 'tipo', 'TOR', 'Hidrante', 'Intento del supervisor')$$, sd), '42501');

  -- ===================== B. Recarga: gana la ficha (§26.3) y los choques en el resumen (17c); la bandeja de nodos se conserva (17f) =====================
  perform public.geoportal_redes_ficha_editar(sd, v_red1, '{"diametro_mm": 110, "fecha_instalacion": "2020-05-01", "observaciones": "Se cambió en 2020"}', 'Datos que trajo la cuadrilla');
  perform public.geoportal_redes_ficha_editar(a, v_red2, '{"origen": {"origen": "tercero", "aportante": "alcaldia"}}', 'Lo entregó la alcaldía');
  v_acc := public.geoportal_redes_nodo_crear_activo(a, v_nj, 'ACC', 'union', null, 'Técnica confirmó que la J-997 es una unión') ->> 'activo';
  -- segunda carga: tramo 1 con D = 4" (102 mm) y tramo 2 con D = 6" (152 mm) y zona SIVA (origen tercero, SIVA)
  c2 := pg_temp.cargar_acu(a, 'zt7-acu-2', jsonb_build_array(
    jsonb_set(pg_temp.tramo(1, 9970001, 'Distribucion-ZT71', '99701', 'V997', '99702', 'J-997', w1), '{atributos,D}', '4'),
    jsonb_set(jsonb_set(pg_temp.tramo(2, 9970002, 'Lateral-ZT72', '99702', 'J-997', '99703', 'Tee-997', w2), '{atributos,D}', '6'), '{atributos,ZONE}', '"SIVA"')));
  v_r := c2 -> 'resumen';
  perform pg_temp.reg('10.01 el resumen lista los choques con la ficha: el diámetro de RED-1 (ficha 110 / capa 102) y el origen de RED-2',
     exists (select 1 from jsonb_array_elements(v_r -> 'choques') x where x ->> 'codigo' = v_red1 and x ->> 'campo' = 'diametro_mm' and x ->> 'ficha' = '110' and x ->> 'capa' = '102')
     and exists (select 1 from jsonb_array_elements(v_r -> 'choques') x where x ->> 'codigo' = v_red2 and x ->> 'campo' = 'origen')
     and (v_r ->> 'lista_para_publicar')::boolean, left((v_r -> 'choques')::text, 400));
  perform pg_temp.reg('10.02 los choques no bloquean: van como aviso y en la tabla para psql (sección «6b choques con la ficha»)',
     exists (select 1 from jsonb_array_elements_text(v_r -> 'avisos') x where x like '%gana la ficha%')
     and exists (select 1 from jsonb_array_elements(v_r -> 'tabla') x where x ->> 's' like '6b choques%' and x ->> 'c' = v_red1 || ' · diametro_mm'));
  perform pg_temp.reg('10.03 el resumen cuenta el nodo clasificado en la bandeja (se conserva)', (v_r -> 'detalle' ->> 'nodos_clasificados_en_la_bandeja')::integer = 1);
  perform public.geoportal_redes_carga_publicar(a, (c2 ->> 'carga_id')::bigint, 'Segunda carga de prueba del Corte 5a');
  select * into v_x from (select to_jsonb(v) as j from redes.v_activo_vigente v where codigo = v_red1) z;
  perform pg_temp.reg('10.04 gana la ficha: RED-1 sigue en 110 mm, con su fecha de instalación y sus observaciones (la carga no las trae)',
     (v_x ->> 'diametro_mm')::numeric = 110 and v_x ->> 'fecha_instalacion' = '2020-05-01' and v_x -> 'atributos' ->> 'observaciones' = 'Se cambió en 2020', left(v_x::text, 400));
  perform pg_temp.reg('10.05 lo que no se editó en la ficha sí lo cambia la capa: RED-2 pasa a 152 mm', (select diametro_mm from redes.v_activo_vigente where codigo = v_red2) = 152);
  perform pg_temp.reg('10.06 el origen corregido en la ficha (alcaldía) no lo pisa la capa (SIVA)',
     (select o.aportante_codigo from redes.v_activo_origen_vigente o join redes.activos x on x.id = o.activo_id where x.codigo = v_red2) = 'alcaldia');
  perform pg_temp.reg('10.07 la J-997 sigue siendo el accesorio de la bandeja', (select clase_nodo = 'activo' and activo_id = (select id from redes.activos where codigo = v_acc)
     from redes.v_nodo_vigente where sistema = 'acueducto' and llave_modelo = '99702'));
  -- tercera carga: la J-997 se mueve 6 m (el nodo es nuevo en la topología); tramo 1 con D = 110 mm de la capa (ya no hay choque)
  c3 := pg_temp.cargar_acu(a, 'zt7-acu-3', jsonb_build_array(
    jsonb_set(pg_temp.tramo(1, 9970001, 'Distribucion-ZT71', '99701', 'V997', '99702', 'J-997', w1b), '{atributos,D}', '4.33'),
    jsonb_set(jsonb_set(pg_temp.tramo(2, 9970002, 'Lateral-ZT72', '99702', 'J-997', '99703', 'Tee-997', w2b), '{atributos,D}', '6'), '{atributos,ZONE}', '"SIVA"')));
  perform pg_temp.reg('10.08 cuando la capa trae lo mismo que la ficha, no hay choque', not exists (select 1 from jsonb_array_elements(c3 -> 'resumen' -> 'choques') x where x ->> 'campo' = 'diametro_mm'),
     left((c3 -> 'resumen' -> 'choques')::text, 300));
  perform public.geoportal_redes_carga_publicar(a, (c3 ->> 'carga_id')::bigint, 'Tercera carga de prueba del Corte 5a (la J se mueve)');
  perform pg_temp.reg('10.09 la J-997 se movió (nodo nuevo) y sigue enlazada al mismo accesorio (evento «enlazar_activo» de la carga)',
     (select n.nodo_id <> v_nj and n.clase_nodo = 'activo' and n.activo_id = (select id from redes.activos where codigo = v_acc) from redes.v_nodo_vigente n where n.sistema = 'acueducto' and n.llave_modelo = '99702')
     and exists (select 1 from redes.nodo_eventos e join redes.nodos n on n.id = e.nodo_id where n.llave_modelo = '99702' and n.carga_id = (c3 ->> 'carga_id')::bigint and e.tipo = 'enlazar_activo'));
  perform pg_temp.reg('10.10 el accesorio creado en el nodo no se retiró en ninguna recarga', not (select retirado from redes.v_activo_vigente where codigo = v_acc));
  perform public.geoportal_redes_carga_revertir(a, 'acueducto', 'Se revierte la tercera carga de prueba');
  perform pg_temp.reg('10.11 revertir la tercera carga: la J-997 vuelve a su nodo y a su accesorio', (select nodo_id = v_nj and activo_id = (select id from redes.activos where codigo = v_acc)
     from redes.v_nodo_vigente where sistema = 'acueducto' and llave_modelo = '99702'));
  perform pg_temp.reg('10.12 la ficha sigue ganando después de revertir (110 mm y la fecha de 2020)', (select diametro_mm = 110 and fecha_instalacion = date '2020-05-01' from redes.v_activo_vigente where codigo = v_red1));

  -- ===================== C. Capa MUE (puntos de muestreo; tecnica.puntos solo agrega y cambia «activo» con evento) =====================
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9901', 'ZT7 Punto uno', 'muestreo', 'norte'), ('MUE-9902', 'ZT7 Punto dos', 'muestreo', 'sur'),
    ('MUE-9950', 'ZT7 Tanque con código de muestreo', 'tanque', null);
  select count(*) into v_act_otros from tecnica.puntos where tipo = 'muestreo' and activo and codigo not in ('MUE-9901', 'MUE-9902');
  select count(*) into v_puntos0 from tecnica.puntos;
  v_sig := (select max(substring(codigo from '^MUE-([0-9]+)$')::integer) from tecnica.puntos where codigo ~ '^MUE-[0-9]+$');
  perform pg_temp.err('20.01 el supervisor de distribución no carga capas', format($$select public.geoportal_redes_carga_iniciar(%L, 'muestreo', %L, 'csv', 4326, 'codigo', 1)$$, sd, pg_temp.sha('x')), '42501');
  -- una carga con errores: todo lo que bloquea
  v_m1 := pg_temp.cargar_mue(a, 'zt7-mue-mala', jsonb_build_array(
    pg_temp.mue(1, 'ZZ-1', 10.47, -73.25, '{"nombre": "Código raro"}'), pg_temp.mue(2, 'MUE-9950', 10.47, -73.25), pg_temp.mue(3, 'MUE-9901', 4.60, -74.08),
    pg_temp.mue(4, 'MUE-9902', 10.47, -73.25), pg_temp.mue(5, 'MUE-9902', 10.47, -73.25), pg_temp.mue(6, null, 10.47, -73.25),
    pg_temp.mue(7, 'MUE-9903', 10.47, -73.25, '{"nombre": "ZT7 Nuevo", "fuente": "gps_operador"}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_m1);
  perform pg_temp.reg('20.02 el resumen bloquea: código que no es MUE-nn, código de otro tipo de punto, fuera de Valledupar, repetido, nuevo sin nombre y la fuente GPS',
     not (v_r ->> 'lista_para_publicar')::boolean and jsonb_array_length(v_r -> 'bloqueos') = 6
     and (v_r -> 'bloqueos')::text like '%MUE-nn%' and (v_r -> 'bloqueos')::text like '%otro tipo de punto%' and (v_r -> 'bloqueos')::text like '%Fuera de la caja de Valledupar%'
     and (v_r -> 'bloqueos')::text like '%repetidos%' and (v_r -> 'bloqueos')::text like '%necesita su nombre%' and (v_r -> 'bloqueos')::text like '%GPS del operador%', (v_r -> 'bloqueos')::text);
  perform pg_temp.err('20.03 y no se publica', format($$select public.geoportal_redes_carga_publicar(%L, %s, 'No debe publicarse')$$, a, v_m1), '22023', 'no está lista');
  perform public.geoportal_redes_carga_anular(a, v_m1, 'Archivo de prueba con errores');
  -- la buena: dos que existen (sin ubicación), uno nuevo con código y uno sin código
  v_m1 := pg_temp.cargar_mue(a, 'zt7-mue-1', jsonb_build_array(
    pg_temp.mue(1, 'MUE-9901', 10.48067, -73.25744, '{"exactitud": "verificada", "fuente": "david"}'),
    pg_temp.mue(2, 'mue-9902 ', 10.4600, -73.2500, '{"barrio": "ZT7 BARRIO", "fuente": "barrio", "nombre": "Otro nombre"}'),
    pg_temp.mue(3, 'MUE-9903', 10.4700, -73.2600, '{"nombre": "ZT7 Punto tres", "zona": "medio"}'),
    pg_temp.mue(4, null, 10.4650, -73.2550, '{"nombre": "ZT7 Punto sin código"}')));
  v_r := public.geoportal_redes_carga_resumen(a, v_m1);
  perform pg_temp.reg('20.04 resumen listo: 2 ubicaciones, 1 nuevo, 1 sin código, y avisa los activos que se desactivan y el nombre distinto (que no se cambia)',
     (v_r ->> 'lista_para_publicar')::boolean and (v_r -> 'frente_a_vigente' ->> 'ubicacion')::integer = 2 and (v_r -> 'frente_a_vigente' ->> 'nuevo')::integer = 1
     and (v_r -> 'frente_a_vigente' ->> 'nuevo_sin_codigo')::integer = 1 and jsonb_array_length(v_r -> 'desactivar') = v_act_otros
     and (v_r -> 'avisos')::text like '%no se cambia%' and (v_act_otros = 0 or (v_r -> 'avisos')::text like '%DESACTIVAN%'), left(v_r::text, 500));
  perform pg_temp.reg('20.05 el resumen no escribió nada en tecnica.puntos', (select count(*) from tecnica.puntos) = v_puntos0 and not exists (select 1 from tecnica.puntos_ubicacion));
  v_r := public.geoportal_redes_carga_publicar(a, v_m1, 'Primera carga de prueba de la capa de muestreo');
  v_k := 'MUE-' || lpad((greatest(v_sig, 9903) + 1)::text, 2, '0');
  perform pg_temp.reg('20.06 publicar: 2 puntos nuevos agregados (MUE-9903 y el siguiente consecutivo ' || v_k || '), con su evento «crear»',
     (v_r ->> 'nuevos')::integer = 2 and v_r -> 'codigos_asignados' = jsonb_build_array(v_k)
     and (select count(*) from tecnica.puntos) = v_puntos0 + 2 and exists (select 1 from tecnica.puntos where codigo = v_k and nombre = 'ZT7 Punto sin código' and tipo = 'muestreo' and activo)
     and (select count(*) from tecnica.punto_eventos e join tecnica.puntos p on p.id = e.punto_id where p.codigo in ('MUE-9903', v_k) and e.tipo = 'crear') = 2, v_r::text);
  perform pg_temp.reg('20.07 las 4 ubicaciones, con su exactitud y su fuente; el nombre del punto que ya existía no cambió',
     (select count(*) from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo in ('MUE-9901', 'MUE-9902', 'MUE-9903', v_k)) = 4
     and (select exactitud || '|' || fuente from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-9901') = 'verificada|david'
     and (select exactitud || '|' || fuente || '|' || barrio_capa from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-9902') = 'aproximada|barrio|ZT7 BARRIO'
     and (select nombre from tecnica.puntos where codigo = 'MUE-9902') = 'ZT7 Punto dos');
  perform pg_temp.reg('20.08 los activos que no vinieron quedaron DESACTIVADOS con su evento, no borrados',
     (v_r ->> 'desactivados')::integer = v_act_otros and (select count(*) from tecnica.puntos) = v_puntos0 + 2
     and not exists (select 1 from tecnica.puntos p where p.tipo = 'muestreo' and not p.activo and p.codigo not in ('MUE-9901', 'MUE-9902', 'MUE-9903', v_k)
                      and not exists (select 1 from tecnica.punto_eventos e where e.punto_id = p.id and e.tipo = 'desactivar' and e.carga_id = v_m1)));
  perform pg_temp.err('20.09 un punto no se puede borrar (candado de siempre)', $$delete from tecnica.puntos where codigo = 'MUE-9903'$$, '42501');
  perform pg_temp.err('20.10 la ubicación es de solo inserción', $$update tecnica.puntos_ubicacion set lat = 1$$, '42501');
  perform pg_temp.err('20.11 los eventos de los puntos también', $$delete from tecnica.punto_eventos$$, '42501');
  -- segunda carga: solo MUE-9901, igual; los demás se desactivan
  v_m2 := pg_temp.cargar_mue(a, 'zt7-mue-2', jsonb_build_array(pg_temp.mue(1, 'MUE-9901', 10.48067, -73.25744, '{"exactitud": "verificada", "fuente": "david"}')));
  v_r := public.geoportal_redes_carga_publicar(a, v_m2, 'Segunda carga de prueba: solo un punto');
  perform pg_temp.reg('20.12 segunda carga: MUE-9901 igual (sin ubicación nueva) y los otros 3 desactivados',
     (v_r ->> 'iguales')::integer = 1 and (v_r ->> 'ubicaciones')::integer = 0 and (v_r ->> 'desactivados')::integer = 3
     and (select count(*) from tecnica.puntos where codigo in ('MUE-9902', 'MUE-9903', v_k) and not activo) = 3, v_r::text);
  v_r := public.geoportal_redes_carga_revertir(a, 'muestreo', 'Se revierte la segunda carga de prueba');
  perform pg_temp.reg('20.13 revertir la segunda: los 3 vuelven a estar activos (eventos «reactivar»)', (v_r ->> 'reactivados')::integer = 3
     and (select count(*) from tecnica.puntos where codigo in ('MUE-9902', 'MUE-9903', v_k) and activo) = 3);
  v_r := public.geoportal_redes_carga_revertir(a, 'muestreo', 'Se revierte la primera carga de prueba');
  perform pg_temp.reg('20.14 revertir la primera: sus ubicaciones dejan de contar, los creados quedan inactivos (no se borran) y los desactivados vuelven',
     not exists (select 1 from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo in ('MUE-9901', 'MUE-9902', 'MUE-9903', v_k))
     and (select count(*) from tecnica.puntos where codigo in ('MUE-9903', v_k) and not activo) = 2 and (select count(*) from tecnica.puntos) = v_puntos0 + 2
     and (select count(*) from tecnica.puntos where tipo = 'muestreo' and activo and codigo not in ('MUE-9901', 'MUE-9902', 'MUE-9903', v_k)) = v_act_otros, v_r::text);
  perform pg_temp.reg('20.15 cada cambio de «activo» tiene su evento (la regla de la verificación 08)', not exists (select 1 from tecnica.puntos p where p.tipo = 'muestreo'
     and p.activo is distinct from coalesce((select e.tipo <> 'desactivar' from tecnica.punto_eventos e where e.punto_id = p.id order by e.id desc limit 1), p.activo)));
  perform pg_temp.err('20.16 no hay más cargas que revertir', format($$select public.geoportal_redes_carga_revertir(%L, 'muestreo', 'Otra reversa de prueba')$$, a), '22023', 'no tiene una carga publicada');

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 5a (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
