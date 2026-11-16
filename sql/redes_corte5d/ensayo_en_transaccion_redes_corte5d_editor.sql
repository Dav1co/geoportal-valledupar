begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 10 — GUARDIA, TABLAS Y CATÁLOGO (la línea 116)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code B). Generado por pruebas_locales/generar.py.
-- · Presupone el 9a-bis publicado (huella del conjunto de funciones de redes 814eac39ac5deae2943751b8c190f969) y el Corte 8 publicado (las claves «anomalia_compartida» y
--   «revision_compartida» en el dominio tecnica.formulario_clave).
-- · Los reportes de la línea 116 entran por el Cargue de capas (capa «linea_116», CSV o Excel) o por el paquete de psql (carga_116/). Se reconocen por su número:
--   la primera vez se guarda el reporte (solo se agrega) y su ubicación; después, cada cambio de estado es un evento con fecha. Nada se borra.
-- · NOMBRE no se guarda nunca (ni en la carga). Dirección y barrio se guardan solo para ubicar: no salen en el geovisor, ni en descargas, listados ni PDF.
-- · Punto 8 (pedido del Code A): los dos formularios compartidos con Comercial entran a los formularios de distribución.
-- =====================================================================
do $$
begin
  if to_regclass('redes.l116_reportes') is not null then raise exception 'El Corte 5d ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '814eac39ac5deae2943751b8c190f969' then
    raise exception 'Las funciones de redes no son las del Corte 9a-bis publicado (huella 814eac39ac5deae2943751b8c190f969): deténgase y avise';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') not like '%''anomalia_compartida''%''revision_compartida''%' then
    raise exception 'El dominio tecnica.formulario_clave no tiene las claves del Corte 8 (anomalia_compartida y revision_compartida): publique antes el Corte 8';
  end if;
  if not exists (select 1 from redes.geovisor_capas where codigo = 'pqr_116' and fuente = 'preparada') then
    raise exception 'La capa «pqr_116» del geovisor no está como la dejó el Corte 6a (preparada): deténgase y avise';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catastro_valledupar' and column_name in ('cod_usuario', 'geom', 'direccion', 'barrio')) <> 4 then
    raise exception 'public.catastro_valledupar no tiene cod_usuario, geom, direccion y barrio: deténgase y avise';
  end if;
  if exists (select 1 from redes.capas where codigo = 'linea_116' and activa) then raise exception 'Ya existe la capa linea_116: deténgase y avise'; end if;
  if exists (select 1 from redes.formularios_distribucion where clave in ('anomalia_compartida', 'revision_compartida') and activo) then
    raise exception 'Los formularios compartidos ya están en distribución: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. Los reportes (la primera vez que llegan; solo se agregan)
-- ---------------------------------------------------------------------
create table redes.l116_reportes (
  id bigint generated always as identity primary key,
  reporte bigint not null unique check (reporte > 0),
  fecha_registro timestamptz not null,
  servicio text not null check (length(btrim(servicio)) between 1 and 60),
  causal text not null check (length(btrim(causal)) between 1 and 120),
  comuna text check (comuna is null or length(comuna) <= 60),
  contrato text check (contrato is null or contrato ~ '^[0-9]{1,15}$'),
  direccion text check (direccion is null or length(direccion) <= 200),      -- solo para ubicar
  barrio text check (barrio is null or length(barrio) <= 120),               -- solo para ubicar
  carga_id bigint not null references redes.cargas(id),
  creado_en timestamptz not null default clock_timestamp());
comment on table redes.l116_reportes is 'Corte 5d: reportes de la línea 116 (uno por número de reporte). Sin nombre. Dirección y barrio solo para ubicar: nunca en geovisor, descargas, listados ni PDF.';
create index ix_l116_rep_carga on redes.l116_reportes (carga_id);

-- ---------------------------------------------------------------------
-- 2. Los eventos (alta, cambio de estado, ocultar al revertir una carga, volver a mostrar): solo se agregan
-- ---------------------------------------------------------------------
create table redes.l116_eventos (
  id bigint generated always as identity primary key,
  reporte_id bigint not null references redes.l116_reportes(id),
  tipo text not null check (tipo in ('alta', 'estado', 'ocultar', 'mostrar')),
  estado text check (estado in ('registrado', 'atendido')),
  estado_antes text check (estado_antes in ('registrado', 'atendido')),
  metodo text check (metodo in ('contrato', 'direccion', 'barrio', 'sin_ubicar')),
  geom geometry(Point, 4326),
  sector smallint, subsector text,
  carga_id bigint references redes.cargas(id),
  motivo text check (motivo is null or length(motivo) <= 1000),
  autor text not null,
  creado_en timestamptz not null default clock_timestamp(),
  check ((tipo in ('alta', 'estado')) = (estado is not null)),
  check ((tipo = 'alta') = (metodo is not null)),
  check (geom is null or tipo = 'alta'));
create index ix_l116_ev_rep on redes.l116_eventos (reporte_id, id);
create index ix_l116_ev_carga on redes.l116_eventos (carga_id);

-- ---------------------------------------------------------------------
-- 3. Lo vigente de cada reporte (lo mantiene la publicación a partir de los eventos; es lo que lee la capa del geovisor)
-- ---------------------------------------------------------------------
create table redes.l116_vigente (
  reporte_id bigint primary key references redes.l116_reportes(id),
  reporte bigint not null,
  fecha_registro timestamptz not null,
  dia date not null,      -- día del registro en Bogotá (para agrupar los repetidos)
  servicio text not null, causal text not null, contrato text,
  estado text not null check (estado in ('registrado', 'atendido')),
  estado_desde timestamptz not null,
  metodo text not null check (metodo in ('contrato', 'direccion', 'barrio', 'sin_ubicar')),
  geom geometry(Point, 4326),
  sector smallint, subsector text,
  oculto boolean not null default false,
  actualizado_en timestamptz not null default clock_timestamp());
create index ix_l116_vig_fecha on redes.l116_vigente (fecha_registro) where not oculto;

-- ---------------------------------------------------------------------
-- 4. «Convertir en daño» (todavía sin botón): qué daño salió de qué reporte. Solo se agrega
-- ---------------------------------------------------------------------
create table redes.l116_danos (
  id bigint generated always as identity primary key,
  reporte_id bigint not null references redes.l116_reportes(id),
  dano_id uuid not null references redes.danos(id),
  motivo text not null check (length(btrim(motivo)) between 10 and 1000),
  autor text not null,
  creado_en timestamptz not null default clock_timestamp(),
  unique (reporte_id, dano_id));

create trigger t_solo_agregar before update or delete on redes.l116_reportes for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.l116_reportes for each statement execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar before update or delete on redes.l116_eventos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.l116_eventos for each statement execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar before update or delete on redes.l116_danos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.l116_danos for each statement execute function tecnica.f_solo_agregar();

revoke all on table redes.l116_reportes, redes.l116_eventos, redes.l116_vigente, redes.l116_danos from public, anon, authenticated, service_role;
revoke all on sequence redes.l116_reportes_id_seq, redes.l116_eventos_id_seq, redes.l116_danos_id_seq from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5. Catálogo: la capa del Cargue, la del geovisor y los formularios de distribución
-- ---------------------------------------------------------------------
insert into redes.capas (codigo, nombre, grupo, sistema, geometria, prefijo, fuente, derivada_de, columna_llave, formatos, periodicidad_dias, activa, orden, carga_supervisor)
values ('linea_116', 'Reportes de la línea 116', 'calidad_pqr', null, 'punto', null, 'carga', null, 'reporte', '{csv,xlsx}', 31, true, 45, true)
on conflict (codigo) do update set nombre = excluded.nombre, grupo = excluded.grupo, geometria = excluded.geometria, fuente = excluded.fuente, columna_llave = excluded.columna_llave,
  formatos = excluded.formatos, periodicidad_dias = excluded.periodicidad_dias, activa = true, orden = excluded.orden, carga_supervisor = excluded.carga_supervisor;      -- si una reversa la desactivó

update redes.geovisor_capas set fuente = 'geojson', estado = 'activa', por_fecha = true, solo_completo = true, nombre = 'Línea 116 (reportes)',
       nota = 'Por fecha de registro. Color por servicio (acueducto, alcantarillado, otros); lleno si está registrado, hueco si ya se atendió. Los repetidos del mismo contrato, causal y día van juntos'
 where codigo = 'pqr_116';

-- Punto 8 (pedido del Code A, Corte 8): el supervisor de distribución asigna los dos formularios compartidos con Comercial desde Personal
insert into redes.formularios_distribucion (clave, nombre, orden, activo)
values ('anomalia_compartida', 'Reportar anomalía', 3, true), ('revision_compartida', 'Revisiones generales', 4, true)
on conflict (clave) do update set nombre = excluded.nombre, orden = excluded.orden, activo = true;      -- si una reversa los dejó desactivados, vuelven
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 20 — FUNCIONES INTERNAS NUEVAS (la línea 116). Nadie de la API las ejecuta (40_permisos).
-- Ninguna lleva DELETE ni UPDATE sin WHERE (pg-safeupdate). Ninguna recorre tablas enteras de redes: el catastro se lee por contrato (índice) y, solo
-- si quedan reportes nuevos sin contrato en el catastro, una pasada por él para la dirección y el barrio de esos reportes.
-- =====================================================================

-- La dirección normalizada (la misma regla para el reporte y para el catastro): mayúsculas sin tildes, sin signos; CALLE/CLL → CL, CARRERA/KRA/CRA → CR,
-- DIAGONAL → DG, TRANSVERSAL → TV, AVENIDA → AV, MANZANA → MZ, CASA → CS, APARTAMENTO/APTO → AP; «9 A» → «9A»; sin ceros a la izquierda; sin «No».
create function redes.f_dir_norm(p text) returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(btrim(regexp_replace(
    regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
      regexp_replace(regexp_replace(upper(translate(coalesce(p, ''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')), '\m(NRO|NO|N)\s*[°º.]', ' ', 'g'), '[^A-Z0-9]+', ' ', 'g'),
      '\m(CALLE|CALL|CLL|CL)\M', 'CL', 'g'),
      '\m(CARRERA|CARR|CRA|KRA|KR|CR|K)\M', 'CR', 'g'),
      '\m(DIAGONAL|DIAG|DG)\M', 'DG', 'g'),
      '\m(TRANSVERSAL|TRANSV|TRANS|TV|TR)\M', 'TV', 'g'),
      '\m(AVENIDA|AVE|AV)\M', 'AV', 'g'),
      '\m(MANZANA|MZA|MZN|MZ)\M', 'MZ', 'g'),
      '\m(CASA|CS)\M', 'CS', 'g'),
      '\m(APARTAMENTO|APTO|APT|AP)\M', 'AP', 'g'),
      '\m(NUMERO|NUM|NRO|NO)\M', ' ', 'g'),
      '\m0+([0-9])', '\1', 'g'),
      '\m([0-9]+) ([A-H])\M', '\1\2', 'g'),
    '\s+', ' ', 'g')), '') $$;

-- La misma dirección sin apartamento, local, piso, interior, oficina, bloque ni torre (segundo intento)
create function redes.f_dir_base(p_norm text) returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(btrim(regexp_replace(coalesce(p_norm, ''), '\m(AP|LC|LOCAL|PISO|INT|INTERIOR|OF|OFICINA|BL|BLOQUE|TORRE)\M.*$', '')), '') $$;

-- El barrio normalizado: mayúsculas sin tildes ni signos, sin «BARRIO» ni «URBANIZACIÓN» delante
create function redes.f_barrio_norm(p text) returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(btrim(regexp_replace(regexp_replace(
    regexp_replace(upper(translate(coalesce(p, ''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')), '[^A-Z0-9]+', ' ', 'g'),
    '^\s*(BARRIO|BRR|URBANIZACION|URB)\M', ''), '\s+', ' ', 'g')), '') $$;

-- Solo las columnas que se cargan, con el nombre en minúscula. NOMBRE (y cualquier otra) no pasa: ni a la carga ni a ninguna tabla.
create function redes.f_l116_atributos(p jsonb) returns jsonb language sql immutable parallel safe set search_path = pg_catalog as $$
  select coalesce(jsonb_object_agg(lower(btrim(e.k)), e.v), '{}'::jsonb)
    from jsonb_each(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) e(k, v)
   where lower(btrim(e.k)) in ('reporte', 'estado', 'fecha_registro', 'contrato', 'direccion', 'barrio', 'comuna', 'desc_causal', 'servicio') $$;

-- La fecha de registro: AAAA-MM-DD [HH:MM[:SS]], DD/MM/AAAA [HH:MM[:SS]] o el número de serie de Excel; hora de Bogotá. Nulo si no se entiende.
create function redes.f_l116_fecha(p text) returns timestamptz language plpgsql stable set search_path = pg_catalog as $$
declare t text := btrim(coalesce(p, '')); v timestamp;
begin
  if t = '' then return null; end if;
  begin
    if t ~ '^[0-9]{5}(\.[0-9]+)?$' then v := timestamp '1899-12-30' + make_interval(secs => round(t::numeric * 86400));
    elsif t ~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}([ T][0-9]{1,2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?)?$' then v := replace(t, 'T', ' ')::timestamp;
    elsif t ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' then v := to_timestamp(t, 'DD/MM/YYYY')::timestamp;
    elsif t ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{2}$' then v := to_timestamp(t, 'DD/MM/YYYY HH24:MI')::timestamp;
    elsif t ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{2}:[0-9]{2}$' then v := to_timestamp(t, 'DD/MM/YYYY HH24:MI:SS')::timestamp;
    else return null; end if;
  exception when others then return null;
  end;
  if v < timestamp '2000-01-01' or v > (clock_timestamp() at time zone 'America/Bogota') + interval '1 day' then return null; end if;
  return v at time zone 'America/Bogota';
end $$;

-- Las filas de una carga de la 116, leídas y comparadas con lo vigente, en la tabla temporal _l116 (la usan el resumen y la publicación).
-- La ubicación (y el sector) solo se calcula para los reportes nuevos: 1) el punto del predio del contrato; 2) la dirección normalizada cruzada con el catastro
-- (todos los predios con esa dirección a 100 m o menos de su centro; si no, con la misma dirección y el mismo barrio); 3) el centro del barrio (aproximada);
-- 4) sin ubicar.
create function redes.f_l116_candidatos(p_carga bigint) returns void language plpgsql set search_path = redes, public, extensions, pg_temp as $$
declare v_falta boolean;
begin
  if to_regclass('pg_temp._l116') is not null then drop table pg_temp._l116; end if;
  create temp table _l116 on commit drop as
  select f.orden,
         nullif(btrim(f.atributos ->> 'reporte'), '') as reporte_txt,
         case when btrim(f.atributos ->> 'reporte') ~ '^[0-9]{1,15}(\.0+)?$' then split_part(btrim(f.atributos ->> 'reporte'), '.', 1)::bigint end as reporte,
         nullif(btrim(f.atributos ->> 'fecha_registro'), '') as fecha_txt,
         redes.f_l116_fecha(f.atributos ->> 'fecha_registro') as fecha,
         nullif(btrim(f.atributos ->> 'estado'), '') as estado_txt,
         case redes.f_norm(f.atributos ->> 'estado') when 'registrado' then 'registrado' when 'atendido' then 'atendido' end as estado,
         left(nullif(btrim(f.atributos ->> 'servicio'), ''), 60) as servicio,
         left(nullif(btrim(f.atributos ->> 'desc_causal'), ''), 120) as causal,
         left(nullif(btrim(f.atributos ->> 'comuna'), ''), 60) as comuna,
         case when btrim(f.atributos ->> 'contrato') ~ '^[0-9]{1,15}(\.0+)?$' then split_part(btrim(f.atributos ->> 'contrato'), '.', 1) end as contrato,
         left(nullif(btrim(f.atributos ->> 'direccion'), ''), 200) as direccion,
         left(nullif(btrim(f.atributos ->> 'barrio'), ''), 120) as barrio,
         null::text as error, null::bigint as reporte_id, null::text as estado_vigente, false as oculto_vigente, false as otros_distintos, null::text as accion,
         null::text as metodo, null::geometry as geom, null::smallint as sector, null::text as subsector, null::text as k1, null::text as k2, null::text as kb
    from redes.carga_filas f where f.carga_id = p_carga;
  update _l116 set error = case when reporte is null then 'el número de reporte no es un número' when fecha is null then 'la fecha de registro no se entiende'
                                when estado is null then 'el estado no es «Registrado» ni «Atendido»' when servicio is null then 'falta el servicio'
                                when causal is null then 'falta la causal (DESC_CAUSAL)' end
   where reporte is null or fecha is null or estado is null or servicio is null or causal is null;
  create index on _l116 (reporte);
  analyze _l116;

  -- frente a lo vigente (por el número de reporte)
  update _l116 l set reporte_id = r.id, estado_vigente = v.estado, oculto_vigente = v.oculto,
         otros_distintos = (r.fecha_registro <> l.fecha or r.servicio <> l.servicio or r.causal <> l.causal or r.contrato is distinct from l.contrato)
    from redes.l116_reportes r join redes.l116_vigente v on v.reporte_id = r.id
   where r.reporte = l.reporte and l.error is null;
  update _l116 set accion = case when error is not null then 'error' when reporte_id is null then 'nuevo' when oculto_vigente then 'mostrar'
                                 when estado <> estado_vigente then 'estado' else 'igual' end
   where true;
  analyze _l116;      -- con las estadísticas de antes, el planificador cree que no hay nuevos y cruza fila por fila (35 s con 23 mil)

  -- 1) por contrato: el punto del predio (índice por cod_usuario)
  if to_regclass('pg_temp._l116_pred') is not null then drop table pg_temp._l116_pred; end if;
  create temp table _l116_pred on commit drop as
  select distinct on (cv.cod_usuario) cv.cod_usuario, case when ST_SRID(cv.geom) = 4326 then cv.geom else ST_Transform(cv.geom, 4326) end as geom
    from public.catastro_valledupar cv
   where cv.cod_usuario in (select distinct x.contrato from _l116 x where x.accion = 'nuevo' and x.contrato is not null and x.contrato not in ('0', '99999999'))
     and cv.geom is not null
   order by cv.cod_usuario, cv.id;
  analyze _l116_pred;
  update _l116 l set geom = c.geom, metodo = 'contrato' from _l116_pred c where l.accion = 'nuevo' and c.cod_usuario = l.contrato;

  -- 2) y 3) por dirección y por barrio: una sola pasada por el catastro, y solo si quedan reportes nuevos sin ubicar
  update _l116 set k1 = redes.f_dir_norm(direccion), kb = redes.f_barrio_norm(barrio) where accion = 'nuevo' and metodo is null;
  update _l116 set k2 = redes.f_dir_base(k1) where accion = 'nuevo' and metodo is null;
  analyze _l116;
  v_falta := exists (select 1 from _l116 where accion = 'nuevo' and metodo is null and (k1 is not null or kb is not null));
  if v_falta then
    if to_regclass('pg_temp._l116_cat') is not null then drop table pg_temp._l116_cat; end if;
    -- solo los predios cuya dirección o barrio coincide con alguno de los reportes que faltan (listas con hash: una pasada, sin cruces fila por fila)
    create temp table _l116_cat on commit drop as
    select z.k1, z.k2, z.kb, z.geom
      from (select y.k1, redes.f_dir_base(y.k1) as k2, y.kb, y.geom
              from (select redes.f_dir_norm(cv.direccion) as k1, redes.f_barrio_norm(cv.barrio) as kb,
                           case when ST_SRID(cv.geom) = 4326 then cv.geom else ST_Transform(cv.geom, 4326) end as geom
                      from public.catastro_valledupar cv where cv.geom is not null and (cv.direccion is not null or cv.barrio is not null)) y) z
     where z.k1 in (select l.k1 from _l116 l where l.accion = 'nuevo' and l.metodo is null and l.k1 is not null)
        or z.k2 in (select l.k2 from _l116 l where l.accion = 'nuevo' and l.metodo is null and l.k2 is not null)
        or z.kb in (select l.kb from _l116 l where l.accion = 'nuevo' and l.metodo is null and l.kb is not null);
    analyze _l116_cat;
    -- dirección completa; dirección sin apartamento ni local; las dos con el mismo barrio (cuando la dirección sola está en varios sitios)
    update _l116 l set geom = d.c, metodo = 'direccion'
      from (select k1, ST_Centroid(ST_Collect(geom)) as c from _l116_cat where k1 is not null group by k1
             having ST_MaxDistance(ST_Centroid(ST_Collect(geom)), ST_Collect(geom)) <= 0.0009) d
     where l.accion = 'nuevo' and l.metodo is null and l.k1 = d.k1;
    update _l116 l set geom = d.c, metodo = 'direccion'
      from (select k2, ST_Centroid(ST_Collect(geom)) as c from _l116_cat where k2 is not null group by k2
             having ST_MaxDistance(ST_Centroid(ST_Collect(geom)), ST_Collect(geom)) <= 0.0009) d
     where l.accion = 'nuevo' and l.metodo is null and l.k2 = d.k2;
    update _l116 l set geom = d.c, metodo = 'direccion'
      from (select k2, kb, ST_Centroid(ST_Collect(geom)) as c from _l116_cat where k2 is not null and kb is not null group by k2, kb
             having ST_MaxDistance(ST_Centroid(ST_Collect(geom)), ST_Collect(geom)) <= 0.0009) d
     where l.accion = 'nuevo' and l.metodo is null and l.k2 = d.k2 and l.kb = d.kb;
    update _l116 l set geom = d.c, metodo = 'barrio'
      from (select kb, ST_Centroid(ST_Collect(geom)) as c from _l116_cat where kb is not null group by kb) d
     where l.accion = 'nuevo' and l.metodo is null and l.kb = d.kb;
  end if;
  update _l116 set metodo = 'sin_ubicar' where accion = 'nuevo' and metodo is null;
  update _l116 set geom = ST_SetSRID(ST_MakePoint(round(ST_X(geom)::numeric, 6), round(ST_Y(geom)::numeric, 6)), 4326) where geom is not null;
  analyze _l116;

  -- 4) el sector hidráulico de cada reporte ubicado (el oficial, la misma regla de redes.f_sector_de: primero el subsector, luego el de menor área).
  --    Se recorren los polígonos vigentes (36) y, para cada uno, los puntos que caen dentro (índice espacial sobre los puntos): cada polígono se prepara una vez.
  if exists (select 1 from _l116 where accion = 'nuevo' and geom is not null) then
    if to_regclass('pg_temp._l116_sec') is not null then drop table pg_temp._l116_sec; end if;
    create temp table _l116_sec on commit drop as
    select m.activo_id, m.geom, (m.clase = 'subsector') as es_sub, ST_Area(m.geom) as area,
           case when redes.f_num(v.atributos -> 'modelo' -> 'sector') between 1 and 100 then redes.f_num(v.atributos -> 'modelo' -> 'sector')::smallint end as sector,
           case when m.clase = 'subsector' then nullif(btrim(v.atributos -> 'modelo' ->> 'subsector'), '') end as subsector
      from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
     where m.prefijo = 'SEC' and not m.retirado and not m.oculto;
    create index on _l116 using gist (geom);
    analyze _l116_sec;
    analyze _l116;
    update _l116 l set sector = s.sector, subsector = s.subsector
      from (select distinct on (x.orden) x.orden, p.sector, p.subsector
              from _l116_sec p join _l116 x on x.geom && p.geom and ST_Intersects(p.geom, x.geom)
             where x.accion = 'nuevo'
             order by x.orden, p.es_sub desc, p.area, p.activo_id) s
     where s.orden = l.orden;
  end if;
end $$;

-- El resumen de una carga de la 116 (lo que muestra el paso «Revisar» y el paquete de psql)
create function redes.f_resumen_l116(p_carga bigint) returns jsonb language plpgsql set search_path = redes, public, extensions, pg_temp as $$
declare c redes.v_cargas_estado%rowtype; v_rec integer; v_bloq text[] := '{}'; v_avisos text[] := '{}'; v_acc jsonb; v_ubic jsonb; v_serv jsonb; v_n integer; v_tabla jsonb;
        v_sin jsonb; v_sector integer;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  select count(*) into v_rec from redes.carga_filas where carga_id = p_carga;
  if c.estado <> 'abierta' then v_bloq := v_bloq || ('La carga está ' || c.estado); end if;
  if v_rec <> c.filas_esperadas then v_bloq := v_bloq || format('Llegaron %s de %s filas: falta algún lote', v_rec, c.filas_esperadas); end if;
  if c.columna_llave <> 'reporte' then v_bloq := v_bloq || 'La llave de la línea 116 es el número de reporte (columna REPORTE)'::text; end if;
  perform redes.f_l116_candidatos(p_carga);
  select count(*) into v_n from _l116 where error is not null;
  if v_n > 0 then
    v_bloq := v_bloq || format('%s filas con error: %s', v_n, (select string_agg(x.t, '; ') from (select 'fila ' || orden || coalesce(' (reporte ' || reporte_txt || ')', '') || ': ' || error as t
                                                                                                  from _l116 where error is not null order by orden limit 10) x)
                               || case when v_n > 10 then format(' y %s más', v_n - 10) else '' end);
  end if;
  select count(*) into v_n from (select reporte from _l116 where reporte is not null group by reporte having count(*) > 1) x;
  if v_n > 0 then
    v_bloq := v_bloq || format('%s números de reporte repetidos en el archivo: %s', v_n, (select string_agg(r::text, ', ') from (select reporte as r from _l116 where reporte is not null
                                                                                                                                  group by reporte having count(*) > 1 order by reporte limit 10) x));
  end if;
  select count(*) into v_n from _l116 where accion in ('estado', 'igual', 'mostrar') and otros_distintos;
  if v_n > 0 then v_avisos := v_avisos || format('%s reportes ya cargados traen otra fecha, servicio, causal o contrato: se conservan los de la primera carga', v_n); end if;
  select count(*) into v_n from _l116 where accion = 'nuevo' and metodo = 'sin_ubicar';
  if v_n > 0 then v_avisos := v_avisos || format('%s reportes nuevos quedan sin ubicar (no están en el mapa; se guardan igual)', v_n); end if;
  select count(*) into v_n from _l116 where accion = 'mostrar';
  if v_n > 0 then v_avisos := v_avisos || format('%s reportes de una carga revertida vuelven a mostrarse', v_n); end if;

  select jsonb_build_object('nuevo', count(*) filter (where accion = 'nuevo'), 'estado', count(*) filter (where accion = 'estado'),
                            'igual', count(*) filter (where accion = 'igual'), 'mostrar', count(*) filter (where accion = 'mostrar'), 'error', count(*) filter (where accion = 'error'))
    into v_acc from _l116;
  select jsonb_build_object('contrato', count(*) filter (where metodo = 'contrato'), 'direccion', count(*) filter (where metodo = 'direccion'),
                            'barrio', count(*) filter (where metodo = 'barrio'), 'sin_ubicar', count(*) filter (where metodo = 'sin_ubicar')),
         count(*) filter (where sector is not null)
    into v_ubic, v_sector from _l116 where accion = 'nuevo';
  select coalesce(jsonb_object_agg(servicio, n order by servicio), '{}'::jsonb) into v_serv from (select servicio, count(*) n from _l116 where accion = 'nuevo' group by servicio) x;
  select coalesce(jsonb_agg(reporte order by reporte), '[]'::jsonb) into v_sin from (select reporte from _l116 where accion = 'nuevo' and metodo = 'sin_ubicar' order by reporte limit 20) x;
  v_tabla := jsonb_build_array(
      jsonb_build_object('s', '1 carga', 'c', 'capa', 'v', 'linea_116'), jsonb_build_object('s', '1 carga', 'c', 'carga', 'v', c.id || ' (' || c.estado || ')'),
      jsonb_build_object('s', '1 carga', 'c', 'filas recibidas / esperadas', 'v', v_rec || ' / ' || c.filas_esperadas),
      jsonb_build_object('s', '2 frente a lo vigente', 'c', 'nuevos', 'v', (v_acc ->> 'nuevo')),
      jsonb_build_object('s', '2 frente a lo vigente', 'c', 'con cambio de estado', 'v', (v_acc ->> 'estado')),
      jsonb_build_object('s', '2 frente a lo vigente', 'c', 'iguales', 'v', (v_acc ->> 'igual')),
      jsonb_build_object('s', '2 frente a lo vigente', 'c', 'vuelven a mostrarse', 'v', (v_acc ->> 'mostrar')),
      jsonb_build_object('s', '2 frente a lo vigente', 'c', 'con error', 'v', (v_acc ->> 'error')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'por contrato (punto del predio)', 'v', (v_ubic ->> 'contrato')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'por dirección (catastro)', 'v', (v_ubic ->> 'direccion')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'por barrio (aproximada)', 'v', (v_ubic ->> 'barrio')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'sin ubicar', 'v', (v_ubic ->> 'sin_ubicar')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'con sector hidráulico', 'v', v_sector::text))
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '4 servicio de los nuevos', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_serv))
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '7 avisos', 'c', 'aviso', 'v', a)), '[]'::jsonb) from unnest(v_avisos) a)
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '8 bloqueos', 'c', 'BLOQUEO', 'v', b)), '[]'::jsonb) from unnest(v_bloq) b)
    || jsonb_build_array(jsonb_build_object('s', '9 resultado', 'c', 'lista para publicar', 'v', case when cardinality(v_bloq) = 0 then 'SÍ' else 'NO' end));
  return jsonb_build_object('carga_id', c.id, 'capa', 'linea_116', 'estado', c.estado, 'recibidas', v_rec, 'esperadas', c.filas_esperadas,
    'frente_a_vigente', v_acc, 'ubicacion', v_ubic, 'con_sector', v_sector, 'servicios', v_serv, 'sin_ubicar_muestra', v_sin,
    'avisos', to_jsonb(v_avisos), 'bloqueos', to_jsonb(v_bloq), 'lista_para_publicar', cardinality(v_bloq) = 0, 'tabla', v_tabla);
end $$;

-- Publicar una carga de la 116: los nuevos (reporte, alta con su ubicación y lo vigente), los cambios de estado (evento con fecha) y los que vuelven. Nada se borra.
create function redes.f_publicar_l116(p_carga bigint, p_autor text, p_motivo text) returns jsonb language plpgsql set search_path = redes, public, extensions, pg_temp as $$
declare c redes.v_cargas_estado%rowtype; v_res jsonb; v_version integer; v_nuevos integer; v_estado integer; v_mostrar integer; v_iguales integer; v_mot text := btrim(p_motivo);
begin
  perform pg_advisory_xact_lock(hashtext('redes.carga.linea_116'));
  select * into c from redes.v_cargas_estado where id = p_carga;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: no se puede publicar', p_carga, c.estado)); end if;
  v_res := redes.f_resumen_l116(p_carga);      -- deja armada _l116
  if not (v_res ->> 'lista_para_publicar')::boolean then
    perform tecnica.f_error('La carga no está lista para publicar: ' || array_to_string(array(select jsonb_array_elements_text(v_res -> 'bloqueos')), '; '));
  end if;
  v_version := (select count(*) + 1 from redes.v_cargas_estado x where x.capa_codigo = 'linea_116' and x.estado = 'publicada');
  -- (a) nuevos
  insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, comuna, contrato, direccion, barrio, carga_id)
  select reporte, fecha, servicio, causal, comuna, contrato, direccion, barrio, p_carga from _l116 where accion = 'nuevo' order by reporte;
  get diagnostics v_nuevos = row_count;
  update _l116 l set reporte_id = r.id from redes.l116_reportes r where r.reporte = l.reporte and l.accion = 'nuevo';
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, sector, subsector, carga_id, motivo, autor)
  select reporte_id, 'alta', estado, metodo, geom, sector, subsector, p_carga, v_mot, p_autor from _l116 where accion = 'nuevo' order by reporte_id;
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, contrato, estado, estado_desde, metodo, geom, sector, subsector)
  select l.reporte_id, l.reporte, l.fecha, (l.fecha at time zone 'America/Bogota')::date, l.servicio, l.causal, l.contrato, l.estado, l.fecha, l.metodo, l.geom, l.sector, l.subsector
    from _l116 l where l.accion = 'nuevo';
  -- (b) cambios de estado (también los de los que vuelven a mostrarse)
  insert into redes.l116_eventos (reporte_id, tipo, estado, estado_antes, carga_id, motivo, autor)
  select reporte_id, 'estado', estado, estado_vigente, p_carga, v_mot, p_autor from _l116 where accion in ('estado', 'mostrar') and estado <> estado_vigente order by reporte_id;
  get diagnostics v_estado = row_count;
  -- (c) los que vuelven a mostrarse (los había ocultado la reversa de una carga)
  insert into redes.l116_eventos (reporte_id, tipo, carga_id, motivo, autor)
  select reporte_id, 'mostrar', p_carga, v_mot, p_autor from _l116 where accion = 'mostrar' order by reporte_id;
  get diagnostics v_mostrar = row_count;
  update redes.l116_vigente v set estado = l.estado, estado_desde = case when v.estado <> l.estado then clock_timestamp() else v.estado_desde end,
         oculto = false, actualizado_en = clock_timestamp()
    from _l116 l where l.reporte_id = v.reporte_id and l.accion in ('estado', 'mostrar');
  select count(*) into v_iguales from _l116 where accion = 'igual';
  insert into redes.carga_eventos (carga_id, tipo, version_capa, nuevos, cambiados, iguales, retirados, reactivados, detalle, motivo, autor)
  values (p_carga, 'publicar', v_version, v_nuevos, v_estado, v_iguales, 0, v_mostrar,
          jsonb_build_object('ubicacion', v_res -> 'ubicacion', 'con_sector', v_res -> 'con_sector', 'servicios', v_res -> 'servicios'), v_mot, p_autor);
  return jsonb_build_object('carga_id', p_carga, 'capa', 'linea_116', 'version_capa', v_version, 'nuevos', v_nuevos, 'cambiados', v_estado, 'cambios_estado', v_estado,
                            'iguales', v_iguales, 'reactivados', v_mostrar, 'retirados', 0, 'ubicacion', v_res -> 'ubicacion', 'con_sector', v_res -> 'con_sector');
end $$;

-- Volver atrás la última carga publicada de la 116: sus reportes nuevos se ocultan (con motivo) y sus cambios de estado se devuelven con un evento nuevo. Nada se borra.
create function redes.f_revertir_l116(p_autor text, p_motivo text) returns jsonb language plpgsql set search_path = redes, public, extensions, pg_temp as $$
declare c redes.v_cargas_estado%rowtype; v_ocultos integer; v_estados integer; v_mot text;
begin
  perform pg_advisory_xact_lock(hashtext('redes.carga.linea_116'));
  select * into c from redes.v_cargas_estado where capa_codigo = 'linea_116' and estado = 'publicada' order by publicada_en desc limit 1;
  if not found then perform tecnica.f_error('La capa de la línea 116 no tiene una carga publicada para revertir'); end if;
  v_mot := left(format('Se revirtió la carga %s de la línea 116: %s', c.id, btrim(p_motivo)), 1000);
  insert into redes.carga_eventos (carga_id, tipo, motivo, autor) values (c.id, 'revertir', btrim(p_motivo), p_autor);
  -- los cambios de estado de esa carga vuelven al estado anterior (si no cambió después)
  insert into redes.l116_eventos (reporte_id, tipo, estado, estado_antes, carga_id, motivo, autor)
  select e.reporte_id, 'estado', e.estado_antes, v.estado, null, v_mot, p_autor
    from redes.l116_eventos e join redes.l116_vigente v on v.reporte_id = e.reporte_id
   where e.carga_id = c.id and e.tipo = 'estado' and v.estado = e.estado
   order by e.reporte_id;
  get diagnostics v_estados = row_count;
  update redes.l116_vigente v set estado = e.estado_antes, estado_desde = clock_timestamp(), actualizado_en = clock_timestamp()
    from redes.l116_eventos e where e.carga_id = c.id and e.tipo = 'estado' and e.reporte_id = v.reporte_id and v.estado = e.estado;
  -- los reportes que esa carga creó o volvió a mostrar se ocultan
  insert into redes.l116_eventos (reporte_id, tipo, carga_id, motivo, autor)
  select v.reporte_id, 'ocultar', null, v_mot, p_autor from redes.l116_vigente v
   where not v.oculto and (v.reporte_id in (select r.id from redes.l116_reportes r where r.carga_id = c.id)
                           or v.reporte_id in (select e.reporte_id from redes.l116_eventos e where e.carga_id = c.id and e.tipo = 'mostrar'))
   order by v.reporte_id;
  get diagnostics v_ocultos = row_count;
  update redes.l116_vigente v set oculto = true, actualizado_en = clock_timestamp()
   where not v.oculto and (v.reporte_id in (select r.id from redes.l116_reportes r where r.carga_id = c.id)
                           or v.reporte_id in (select e.reporte_id from redes.l116_eventos e where e.carga_id = c.id and e.tipo = 'mostrar'));
  return jsonb_build_object('carga_id', c.id, 'capa', 'linea_116', 'ocultados', v_ocultos, 'estados_devueltos', v_estados);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 26 — RPC NUEVA (solo service_role, por la Edge geoportal-redes)
-- «Convertir en daño», todavía sin botón (encargo del 5d, punto 6): deja anotado de qué reporte de la 116 salió un daño ya creado con el formulario de daño.
-- El camino previsto: el botón de la tarjeta del geovisor abrirá el formulario de daño en el punto del reporte y, al guardarlo, llamará a esta RPC.
-- Solo el supervisor de distribución o el administrador. Con motivo. Solo se agrega (no se desvincula).
-- =====================================================================
create function public.geoportal_redes_l116_vincular_dano(p_solicitante text, p_reporte bigint, p_dano text, p_motivo text, p_ip text default null)
returns jsonb language plpgsql security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'convierten los reportes de la línea 116 en daño'); v_mot text := btrim(coalesce(p_motivo, ''));
        v_rep redes.l116_reportes%rowtype; v_dano record;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  select * into v_rep from redes.l116_reportes where reporte = p_reporte;
  if not found then perform tecnica.f_error('No existe ese reporte de la línea 116', 'P0002'); end if;
  if (select oculto from redes.l116_vigente where reporte_id = v_rep.id) then perform tecnica.f_error('Ese reporte está oculto (su carga se revirtió)', '55000'); end if;
  select d.id, d.codigo, d.estado into v_dano from redes.v_dano d where d.codigo = upper(btrim(coalesce(p_dano, '')));
  if v_dano.id is null then perform tecnica.f_error('No existe ese daño', 'P0002'); end if;
  if v_dano.estado = 'oculto' then perform tecnica.f_error('Ese daño está oculto', '55000'); end if;
  if exists (select 1 from redes.l116_danos where reporte_id = v_rep.id and dano_id = v_dano.id) then perform tecnica.f_error('Ese reporte ya está unido a ese daño'); end if;
  insert into redes.l116_danos (reporte_id, dano_id, motivo, autor) values (v_rep.id, v_dano.id, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_l116_vincular_dano', p_reporte::text, jsonb_build_object('dano', v_dano.codigo, 'motivo', v_mot), p_ip);
  return jsonb_build_object('reporte', p_reporte, 'dano', v_dano.codigo, 'unido', true);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del 9a-bis publicado) con cambios exactos, aplicados una sola vez.
--   · redes.f_lote: de la capa «linea_116» solo se guardan las columnas que se cargan (NOMBRE nunca llega a la base);
--   · redes.f_resumen, f_publicar y f_revertir: la capa «linea_116» va por sus funciones (como la de muestreo);
--   · geoportal_redes_cargue_capas: el lector «linea_116» y cuántos reportes hay;
--   · geoportal_redes_geovisor_capa: la capa «pqr_116» (línea 116) por fecha, agrupada por contrato, causal y día, y cuántos quedan sin ubicar.
-- =====================================================================
-- redes.f_lote(bigint,jsonb)
CREATE OR REPLACE FUNCTION redes.f_lote(p_carga bigint, p_filas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare c redes.v_cargas_estado%rowtype; v_n integer; v_nuevas integer;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: no recibe lotes', p_carga, c.estado)); end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then perform tecnica.f_error('El lote debe ser una lista de filas'); end if;
  v_n := jsonb_array_length(p_filas);
  if v_n < 1 or v_n > redes.f_param('lote_max_filas') then perform tecnica.f_error(format('Un lote lleva de 1 a %s filas', redes.f_param('lote_max_filas')::integer)); end if;
  if exists (select 1 from jsonb_array_elements(p_filas) e
              where jsonb_typeof(e) <> 'object' or jsonb_typeof(e -> 'orden') <> 'number' or jsonb_typeof(e -> 'atributos') <> 'object'
                 or (e ->> 'orden')::numeric <> trunc((e ->> 'orden')::numeric) or (e ->> 'orden')::integer < 1 or (e ->> 'orden')::integer > c.filas_esperadas) then
    perform tecnica.f_error(format('Cada fila lleva orden (1 a %s), atributos y wkt', c.filas_esperadas));
  end if;
  insert into redes.carga_filas (carga_id, orden, llave, atributos, geom, error)
  select p_carga, (e ->> 'orden')::integer, nullif(btrim(a.atr ->> c.columna_llave), ''), a.atr, g.geom, g.error
    from jsonb_array_elements(p_filas) e
    -- Corte 5d: de la línea 116 solo se guardan las columnas que se cargan (NOMBRE nunca llega a la base); no trae geometría (se ubica al revisar)
    cross join lateral (select case when c.capa_codigo = 'linea_116' then redes.f_l116_atributos(e -> 'atributos') else e -> 'atributos' end as atr) a
    cross join lateral redes.f_geo_desde_wkt(e ->> 'wkt', c.srid_origen) g
  on conflict (carga_id, orden) do nothing;
  get diagnostics v_nuevas = row_count;
  return jsonb_build_object('carga_id', p_carga, 'nuevas', v_nuevas, 'repetidas', v_n - v_nuevas,
                            'recibidas', (select count(*) from redes.carga_filas where carga_id = p_carga));
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
  if c.capa_codigo = 'linea_116' then return redes.f_resumen_l116(p_carga); end if;      -- línea 116 (Corte 5d)
  select count(*), count(*) filter (where error is not null), count(*) filter (where error is null and llave is null) into v_recibidas, v_errores, v_nulas
    from redes.carga_filas where carga_id = p_carga;
  select count(*) into v_rep from (select llave from redes.carga_filas where carga_id = p_carga and llave is not null group by llave having count(*) > 1) x;

  if c.estado <> 'abierta' then v_bloq := v_bloq || ('La carga está ' || c.estado); end if;
  if v_recibidas <> c.filas_esperadas then v_bloq := v_bloq || format('Llegaron %s de %s filas: falta algún lote', v_recibidas, c.filas_esperadas); end if;
  if v_errores > 0 then v_bloq := v_bloq || format('%s filas con error de geometría', v_errores); end if;
  if v_nulas > 0 and c.columna_llave <> '(geometria)' then v_bloq := v_bloq || format('%s filas sin llave (%s)', v_nulas, c.columna_llave); end if;      -- Corte 5c: sin llave = por geometría
  if v_rep > 0 then v_bloq := v_bloq || format('%s llaves repetidas en %s: elija otra columna llave o cargue «sin columna llave» (cruce por geometría, D-4)', v_rep, c.columna_llave); end if;

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
    -- Corte 5c: el cruce por geometría (D-4) y la geometría que no corresponde al tipo de la capa
    if c.columna_llave = '(geometria)' then
      v_extra := v_extra || jsonb_build_object('cruce_por_geometria', jsonb_build_object('tolerancia_m', redes.f_param('cruce_geometria_tol_m'),
        'cruzados', (select count(*) from _cand where crea_activo and llave not like 'G' || p_carga || '-%'),
        'sin_par_nuevos', (select count(*) from _cand where crea_activo and llave like 'G' || p_carga || '-%')));
    end if;
    if exists (select 1 from _cand k join redes.tipos_activo t on t.prefijo = k.prefijo where k.crea_activo
                  and not ((t.geometria = 'punto' and GeometryType(k.geom) = 'POINT') or (t.geometria = 'linea' and GeometryType(k.geom) in ('LINESTRING', 'MULTILINESTRING'))
                           or (t.geometria = 'poligono' and GeometryType(k.geom) in ('POLYGON', 'MULTIPOLYGON')))) then
      v_bloq := v_bloq || format('%s filas con una geometría que no es la del tipo (%s): revise el archivo o la capa elegida',
        (select count(*) from _cand k join redes.tipos_activo t on t.prefijo = k.prefijo where k.crea_activo
            and not ((t.geometria = 'punto' and GeometryType(k.geom) = 'POINT') or (t.geometria = 'linea' and GeometryType(k.geom) in ('LINESTRING', 'MULTILINESTRING'))
                     or (t.geometria = 'poligono' and GeometryType(k.geom) in ('POLYGON', 'MULTIPOLYGON')))),
        (select string_agg(distinct t.geometria, ', ') from _cand k join redes.tipos_activo t on t.prefijo = k.prefijo where k.crea_activo));
    end if;
    if exists (select 1 from _cand where crea_activo and pg_column_size(atributos) > 16000) then
      v_bloq := v_bloq || format('%s filas con demasiados atributos (más de 16 KB): quite columnas del archivo', (select count(*) from _cand where crea_activo and pg_column_size(atributos) > 16000));
    end if;
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
  if (select capa_codigo from redes.cargas where id = p_carga) = 'linea_116' then return redes.f_publicar_l116(p_carga, p_autor, p_motivo); end if;      -- línea 116 (Corte 5d)
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
  if p_capa = 'linea_116' then return redes.f_revertir_l116(p_autor, p_motivo); end if;      -- línea 116 (Corte 5d)
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

-- public.geoportal_redes_cargue_capas(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_cargue_capas(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v record;
begin
  select * into v from redes.f_perfil_lectura(p_solicitante);
  if v.perfil not in ('admin', 'supervisor') then perform tecnica.f_error('Solo el supervisor de distribución o el administrador ven el Cargue de capas', '42501'); end if;
  return jsonb_build_object(
    'puede_cargar', v.perfil = 'admin' or exists (select 1 from redes.capas x where x.activa and x.carga_supervisor),      -- Corte 6a: el supervisor carga las que no son del modelo
    'max_filas', redes.f_param('carga_max_filas'), 'lote_max_filas', redes.f_param('lote_max_filas'), 'tolerancia_geometria_m', redes.f_param('cruce_geometria_tol_m'),
    'caja', jsonb_build_array(redes.f_param('caja_lon_min'), redes.f_param('caja_lat_min'), redes.f_param('caja_lon_max'), redes.f_param('caja_lat_max')),
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'codigo', c.codigo, 'nombre', c.nombre, 'puede_cargar', v.perfil = 'admin' or c.carga_supervisor, 'solo_admin', not c.carga_supervisor, 'grupo', c.grupo, 'sistema', c.sistema, 'geometria', c.geometria, 'prefijo', c.prefijo, 'fuente', c.fuente,
               'derivada_de', c.derivada_de, 'columna_llave', c.columna_llave, 'formatos', to_jsonb(c.formatos),
               'lector', case when c.codigo = 'muestreo' then 'muestreo' when c.codigo = 'linea_116' then 'linea_116' when c.codigo in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas') then 'modelo'
                              when c.fuente = 'carga' and c.prefijo is not null then 'generico' end,
               'version', x.version, 'ultima', x.ultima, 'abierta', x.abierta, 'vigentes', x.vigentes,
               'estado', case when c.fuente = 'derivada' then 'derivada' when c.fuente <> 'carga' then 'otro_modulo' when x.version = 0 then 'sin_cargar'
                              when c.periodicidad_dias is not null and (x.ultima ->> 'publicada_en')::timestamptz < clock_timestamp() - make_interval(days => c.periodicidad_dias) then 'desactualizada'
                              else 'al_dia' end)
             order by c.orden, c.codigo)
        from redes.capas c
        cross join lateral (
          select (select count(*) from redes.v_cargas_estado e where e.capa_codigo = c.codigo and e.estado = 'publicada') as version,
                 (select jsonb_build_object('carga_id', e.id, 'publicada_en', e.publicada_en, 'autor', e.autor, 'formato', e.formato, 'filas', e.filas_esperadas, 'nota', e.nota,
                                            'motivo', (select ev.motivo from redes.carga_eventos ev where ev.carga_id = e.id and ev.tipo = 'publicar'))
                    from redes.v_cargas_estado e where e.capa_codigo = c.codigo and e.estado = 'publicada' order by e.publicada_en desc limit 1) as ultima,
                 (select jsonb_build_object('carga_id', e.id, 'creado_en', e.creado_en, 'autor', e.autor, 'formato', e.formato, 'filas', e.filas_esperadas, 'sha256', e.sha256,
                                            'columna_llave', e.columna_llave, 'srid', e.srid_origen, 'masiva', e.masiva_id is not null,
                                            'recibidas', (select count(*) from redes.carga_filas f where f.carga_id = e.id))
                    from redes.v_cargas_estado e where e.capa_codigo = c.codigo and e.estado = 'abierta' order by e.id desc limit 1) as abierta,
                 case when c.codigo = 'muestreo' then (select count(*) from tecnica.puntos p where p.tipo = 'muestreo' and p.activo)
                      when c.codigo = 'linea_116' then (select count(*) from redes.l116_vigente l where not l.oculto)      -- Corte 5d
                      else (select count(*) from redes.activo_vigente_mat m where m.capa_codigo = c.codigo and not m.retirado) end as vigentes
        ) x
       where c.activa), '[]'::jsonb));
end $function$;

-- public.geoportal_redes_geovisor_capa(text,text,date,date)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor_capa(p_solicitante text, p_capa text, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare a record; g redes.geovisor_capas%rowtype; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        v_desde date := coalesce(p_desde, v_hoy); v_hasta date := coalesce(p_hasta, v_hoy); v_max integer := floor(redes.f_param('geovisor_max_elementos'))::integer;
        v_ini timestamptz; v_fin timestamptz; v_f jsonb; v_n integer; v_sin integer;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into g from redes.geovisor_capas where codigo = p_capa and activa;
  if not found or g.fuente <> 'geojson' then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if g.solo_completo and not a.completo then raise exception 'Capa solo para supervisores' using errcode = '42501'; end if;
  if g.por_fecha then
    if v_desde > v_hasta then perform tecnica.f_error('La fecha inicial es posterior a la final'); end if;
    if v_hasta > v_hoy then perform tecnica.f_error('La fecha final no puede ser futura'); end if;
    if v_desde < (v_hasta - make_interval(months => floor(redes.f_param('geovisor_rango_meses'))::integer))::date then
      perform tecnica.f_error(format('El rango de fechas es de máximo %s meses', floor(redes.f_param('geovisor_rango_meses'))::integer));
    end if;
    if not a.completo and (v_desde <> v_hoy or v_hasta <> v_hoy) then raise exception 'El geovisor en solo lectura muestra solo las actividades del día' using errcode = '42501'; end if;
  end if;
  v_ini := v_desde::timestamp at time zone 'America/Bogota';
  v_fin := (v_hasta + 1)::timestamp at time zone 'America/Bogota';

  if p_capa = 'danos' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(d.lon, d.lat)),
               'properties', jsonb_build_object('codigo', d.codigo, 'clase', d.clase, 'tipo', d.tipo_nombre, 'sistema', d.sistema, 'estado', d.estado,
                                                'activo', d.activo_codigo, 'cuando', d.t_detectado, 'riesgo', d.riesgo, 'origen', d.origen)) as f, d.t_detectado as o
        from redes.v_dano d
       where d.estado <> 'oculto' and d.t_detectado >= v_ini and d.t_detectado < v_fin and d.lat is not null
       order by d.t_detectado desc limit v_max + 1) x;
  elsif p_capa = 'intervenciones' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(i.lon, i.lat)),
               'properties', jsonb_build_object('codigo', i.codigo, 'tipo_codigo', i.tipo_codigo, 'tipo', i.tipo_nombre, 'sistema', i.sistema, 'estado', i.estado,
                                                'activo', i.activo_codigo, 'dano', i.dano_codigo, 'cuando', i.t_inicio, 'fin', i.t_fin, 'ejecutor', i.ejecutor)) as f, i.t_inicio as o
        from redes.v_intervencion i
       where i.estado not in ('oculta', 'anulada') and i.t_inicio >= v_ini and i.t_inicio < v_fin and i.lat is not null
       order by i.t_inicio desc limit v_max + 1) x;
  elsif p_capa = 'reportes_bot' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.radicado, 'canal', r.canal, 'tipo', r.tipo_bot, 'estado', r.estado_bot, 'dano', r.dano_codigo,
                                                'cuando', r.recibido_en)) as f, r.recibido_en as o
        from redes.v_reporte_externo r
       where r.recibido_en >= v_ini and r.recibido_en < v_fin and r.lat is not null
       order by r.recibido_en desc limit v_max + 1) x;
  elsif p_capa = 'muestreo' then
    select coalesce(jsonb_agg(f order by o), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(u.lon, u.lat)),
               'properties', jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'exactitud', u.exactitud) || redes.f_muestreo_calidad(p.id)) as f, p.codigo as o
        from tecnica.puntos p join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
       where p.tipo = 'muestreo' and p.activo
       order by p.codigo limit v_max + 1) x;
  elsif p_capa = 'reportes_comercial' then      -- Corte 6b (§30.4): la vista la llena el Corte 8; azul con contrato, rojo posible clandestino
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.codigo, 'tipo', r.tipo, 'subtipo', r.subtipo, 'area', r.area, 'con_contrato', coalesce(r.con_contrato, false),
                                                'estado', r.estado, 'cuando', r.registrado_en)) as f, r.registrado_en as o
        from redes.v_reportes_comercial r
       where r.registrado_en >= v_ini and r.registrado_en < v_fin and r.lat is not null
       order by r.registrado_en desc limit v_max + 1) x;
  elsif p_capa = 'pqr_116' then      -- Corte 5d: la línea 116. Los repetidos del mismo contrato, causal y día van en un solo punto. Sin nombre, dirección ni barrio
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(round(ST_X(z.geom)::numeric, 6), round(ST_Y(z.geom)::numeric, 6))),
               'properties', jsonb_build_object('codigo', z.reportes[1]::text, 'n', z.n, 'reportes', to_jsonb(z.reportes[1:20]), 'servicio', z.servicio,
                                                'grupo_servicio', case redes.f_norm(z.servicio) when 'acueducto' then 'acueducto' when 'alcantarillado' then 'alcantarillado' else 'otros' end,
                                                'causal', z.causal, 'estado', case when z.registrados > 0 then 'registrado' else 'atendido' end, 'registrados', z.registrados,
                                                'contrato', z.contrato, 'dia', z.dia, 'cuando', z.primero, 'ultimo', z.ultimo, 'metodo', z.metodo, 'sector', z.sector, 'subsector', z.subsector,
                                                'danos', (select jsonb_agg(distinct d.codigo) from redes.l116_danos ld join redes.danos d on d.id = ld.dano_id where ld.reporte_id = any (z.ids)))) as f,
             z.ultimo as o
        from (select v.contrato, v.causal, v.dia, count(*) as n, array_agg(v.reporte order by v.fecha_registro, v.reporte) as reportes, array_agg(v.reporte_id) as ids,
                     min(v.servicio) as servicio, count(*) filter (where v.estado = 'registrado') as registrados, min(v.fecha_registro) as primero, max(v.fecha_registro) as ultimo,
                     (array_agg(v.geom order by v.fecha_registro, v.reporte))[1] as geom, (array_agg(v.metodo order by v.fecha_registro, v.reporte))[1] as metodo,
                     (array_agg(v.sector order by v.fecha_registro, v.reporte))[1] as sector, (array_agg(v.subsector order by v.fecha_registro, v.reporte))[1] as subsector
                from redes.l116_vigente v
               where not v.oculto and v.geom is not null and v.fecha_registro >= v_ini and v.fecha_registro < v_fin
               group by coalesce(v.contrato, 'R' || v.reporte), v.contrato, v.causal, v.dia) z
       order by z.ultimo desc limit v_max + 1) x;
    select count(*) into v_sin from redes.l116_vigente v where not v.oculto and v.geom is null and v.fecha_registro >= v_ini and v.fecha_registro < v_fin;
  else
    perform tecnica.f_error('Esa capa todavía no tiene datos', 'P0002');
  end if;

  if v_n > v_max then v_f := v_f - v_max; end if;      -- se quitó el elemento de más (el último de la lista)
  return jsonb_build_object('type', 'FeatureCollection', 'capa', p_capa, 'desde', case when g.por_fecha then v_desde end, 'hasta', case when g.por_fecha then v_hasta end,
                            'recortada', v_n > v_max, 'features', v_f)
         || case when p_capa = 'pqr_116' then jsonb_build_object('sin_ubicar', v_sin) else '{}'::jsonb end;      -- Corte 5d: los del rango que no están en el mapa
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las funciones internas nuevas y las reemplazadas: nadie de la API. La RPC nueva y las RPC reemplazadas: solo service_role (la Edge geoportal-redes).
-- Las tablas nuevas: nadie de la API (las leen y escriben solo las funciones SECURITY DEFINER).
-- =====================================================================
revoke all on function redes.f_dir_norm(text), redes.f_dir_base(text), redes.f_barrio_norm(text), redes.f_l116_atributos(jsonb), redes.f_l116_fecha(text),
  redes.f_l116_candidatos(bigint), redes.f_resumen_l116(bigint), redes.f_publicar_l116(bigint, text, text), redes.f_revertir_l116(text, text)
  from public, anon, authenticated, service_role;
revoke all on function redes.f_lote(bigint, jsonb), redes.f_resumen(bigint), redes.f_publicar(bigint, text, text), redes.f_revertir(text, text, text)
  from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_l116_vincular_dano', 'geoportal_redes_geovisor_capa', 'geoportal_redes_cargue_capas') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte5d', 'migracion_redes_corte5d', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.l116_reportes', 'redes.l116_eventos', 'redes.l116_vigente', 'redes.l116_danos'),
        'nuevas', jsonb_build_array('redes.f_dir_norm', 'redes.f_dir_base', 'redes.f_barrio_norm', 'redes.f_l116_atributos', 'redes.f_l116_fecha', 'redes.f_l116_candidatos',
                                    'redes.f_resumen_l116', 'redes.f_publicar_l116', 'redes.f_revertir_l116', 'geoportal_redes_l116_vincular_dano'),
        'formularios_distribucion', jsonb_build_array('anomalia_compartida', 'revision_compartida'),
        'motivo', 'línea 116 por el Cargue de capas (sin nombre), ubicada por contrato, dirección o barrio, en el geovisor por fecha; formularios compartidos en distribución'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes15.*), sus predios de catastro (contratos 995150xx, en un rincón de Valledupar),
-- su polígono de sector (número 95) y sus reportes sintéticos (números 99515xxxx y 9952xxxxx). Ningún dato real de la línea 116.
-- Mide la carga completa con el volumen real (22.978 reportes sintéticos, contratos tomados del catastro de la base donde corre) y la capa del geovisor:
-- FALLA si un lote pasa de 8 s, si el resumen o la publicación pasan de 30 s, o si la capa pasa de 8 s.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 5d … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4300 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.2900 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.caja(x0 numeric, y0 numeric, x1 numeric, y1 numeric) returns geometry language sql as $$
  select ST_SetSRID(ST_MakeEnvelope(pg_temp.lon(x0), pg_temp.lat(y0), pg_temp.lon(x1), pg_temp.lat(y1)), 4326) $$;
-- distancia en metros entre un punto y el de la cuadrícula de prueba
create function pg_temp.dist(g geometry, x numeric, y numeric) returns numeric language sql as $$ select round(ST_Distance(g::geography, pg_temp.pt(x, y)::geography)::numeric, 1) $$;
create function pg_temp.activo(p_prefijo text, p_geom geometry, p_capa text, p_llave text, p_clase text default null, p_attr jsonb default '{}'::jsonb, p_nombre text default null)
returns text language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes15.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, estado_codigo, atributos, codigo_anterior, capa_codigo, llave_capa, huella, autor)
  values (v_id, 1, p_geom, coalesce(p_nombre, 'ZT15 ' || p_prefijo), p_clase, null, null, null, 'en_operacion', p_attr, p_llave, p_capa, p_llave, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT15 activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_cod;
end $$;
create function pg_temp.archivo(p_ruta text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg')) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
create function pg_temp.dano(p_op text, p_datos jsonb) returns text language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_dano(p_op, 1);
begin
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  return public.geoportal_redes_crear_dano(p_op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
           'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))) || p_datos) ->> 'codigo';
end $$;
-- hoy en Bogotá a las HH:MM (texto como lo trae el archivo)
create function pg_temp.hoy(p_min integer) returns text language sql as $$
  select to_char(((clock_timestamp() at time zone 'America/Bogota')::date)::timestamp + make_interval(mins => p_min), 'YYYY-MM-DD HH24:MI:SS') $$;
-- una fila del archivo, con NOMBRE (que no se debe guardar nunca)
create function pg_temp.fila(p_orden integer, p_rep bigint, p_estado text, p_fecha text, p_contrato text, p_dir text, p_barrio text, p_causal text, p_servicio text)
returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', null, 'atributos', jsonb_build_object('REPORTE', p_rep, 'ESTADO', p_estado, 'FECHA_REGISTRO', p_fecha, 'CONTRATO', p_contrato,
           'NOMBRE', 'ZT15 NOMBRE QUE NO SE GUARDA', 'DIRECCION', p_dir, 'BARRIO', p_barrio, 'COMUNA', 'COMUNA 5', 'DESC_CAUSAL', p_causal, 'SERVICIO', p_servicio)) $$;
-- sube un archivo por el motor (como la pantalla: iniciar, lotes de 200) y devuelve la carga
create function pg_temp.subir(p_sd text, p_filas jsonb, p_sha text) returns bigint language plpgsql as $$
declare v_c bigint; k integer := 0; n integer := jsonb_array_length(p_filas);
begin
  v_c := (public.geoportal_redes_cargue_iniciar(p_sd, 'linea_116', p_sha, 'xlsx', 4326, 'reporte', n, 'ZT15 archivo de prueba') ->> 'carga_id')::bigint;
  while k < n loop
    perform public.geoportal_redes_carga_lote(p_sd, v_c, (select jsonb_agg(e order by o) from jsonb_array_elements(p_filas) with ordinality x(e, o) where o > k and o <= k + 200));
    k := k + 200;
  end loop;
  return v_c;
end $$;
-- las propiedades de los puntos de la capa, por su primer reporte
create function pg_temp.punto(p_capa jsonb, p_rep bigint) returns jsonb language sql as $$
  select f -> 'properties' from jsonb_array_elements(p_capa -> 'features') f where (f -> 'properties' -> 'reportes') @> to_jsonb(array[p_rep]) limit 1 $$;

do $prueba$
declare
  a text := 'prueba.redes15.adm@emdupar.gov.co'; sd text := 'prueba.redes15.dist@emdupar.gov.co'; op text := 'prueba.redes15.op@emdupar.gov.co';
  C1 text := '99515001'; C2 text := '99515002'; C3 text := '99515003';
  v_base bigint := 995150000; v_r jsonb; v_x jsonb; v_c1 bigint; v_c2 bigint; v_c3 bigint; v_c4 bigint; v_g jsonb; v_dano text; v_sub text;
  v_cods text[]; v_nc integer; v_n integer := 22978; v_lote jsonb; v_cv bigint; k integer;
  v_t0 timestamptz; v_ms numeric; v_ms_lote numeric := 0; v_ms_res numeric; v_ms_pub numeric; v_ms_capa numeric; v_ms_capa_hoy numeric; v_ms_ini numeric;
  v_info text := ''; v_total integer; v_bien integer; v_fallas text; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT15 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT15 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT15 Operador de redes', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);

  -- ===================== 01. Esquema, permisos y catálogo =====================
  perform pg_temp.reg('01.01 las 9 funciones internas nuevas no las ejecuta la API; la RPC nueva, solo service_role (security definer)',
     not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                   and p.proname in ('f_dir_norm', 'f_dir_base', 'f_barrio_norm', 'f_l116_atributos', 'f_l116_fecha', 'f_l116_candidatos', 'f_resumen_l116', 'f_publicar_l116', 'f_revertir_l116')
                   and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')))
     and (select count(*) from pg_proc p where p.pronamespace = 'redes'::regnamespace
            and p.proname in ('f_dir_norm', 'f_dir_base', 'f_barrio_norm', 'f_l116_atributos', 'f_l116_fecha', 'f_l116_candidatos', 'f_resumen_l116', 'f_publicar_l116', 'f_revertir_l116')) = 9
     and exists (select 1 from pg_proc p where p.oid = 'public.geoportal_redes_l116_vincular_dano(text,bigint,text,text,text)'::regprocedure and p.prosecdef
                   and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')));
  perform pg_temp.reg('01.02 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
     not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion || ' → ' || sentencia, ' | ') from redes.f_funciones_sin_where()));
  perform pg_temp.reg('01.03 las 4 tablas de la 116: ningún permiso para la API; reportes, eventos y daños con el disparador de solo agregar',
     not has_table_privilege('service_role', 'redes.l116_reportes', 'select') and not has_table_privilege('anon', 'redes.l116_vigente', 'select')
     and not has_table_privilege('authenticated', 'redes.l116_eventos', 'select') and not has_table_privilege('service_role', 'redes.l116_danos', 'insert')
     and (select count(*) from pg_trigger t where t.tgrelid in ('redes.l116_reportes'::regclass, 'redes.l116_eventos'::regclass, 'redes.l116_danos'::regclass) and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 6);
  perform pg_temp.reg('01.04 ninguna tabla de la 116 tiene columna de nombre ni de teléfono',
     not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name like 'l116\_%' and column_name ~ 'nombre|telefono|celular'));
  perform pg_temp.reg('01.05 la capa «linea_116» del Cargue (CSV o Excel, llave «reporte», la carga el supervisor) y «pqr_116» en el geovisor (por fecha, solo supervisores)',
     exists (select 1 from redes.capas where codigo = 'linea_116' and fuente = 'carga' and activa and carga_supervisor and columna_llave = 'reporte' and formatos = '{csv,xlsx}')
     and exists (select 1 from redes.geovisor_capas where codigo = 'pqr_116' and fuente = 'geojson' and estado = 'activa' and por_fecha and solo_completo));
  perform pg_temp.reg('01.06 punto 8: «Reportar anomalía» y «Revisiones generales» están en los formularios de distribución',
     (select count(*) from redes.formularios_distribucion where clave in ('anomalia_compartida', 'revision_compartida') and activo) = 2);

  -- ===================== 02. Dirección, barrio, fecha y columnas =====================
  perform pg_temp.reg('02.01 la dirección se normaliza igual escrita de varias formas (Calle/CLL/CL, #, N°, No., guiones, ceros)',
     redes.f_dir_norm('Calle 12 # 5-30') = 'CL 12 5 30' and redes.f_dir_norm('CLL 12 N° 5 - 30') = 'CL 12 5 30' and redes.f_dir_norm('cl. 12 no. 05-30') = 'CL 12 5 30'
     and redes.f_dir_norm('Carrera 9 A No. 18-05') = 'CR 9A 18 5' and redes.f_dir_norm('KRA 9a 18 05') = 'CR 9A 18 5' and redes.f_dir_norm('Diagonal 21 Transversal 4') = 'DG 21 TV 4',
     redes.f_dir_norm('Calle 12 # 5-30') || ' / ' || redes.f_dir_norm('CLL 12 N° 5 - 30') || ' / ' || redes.f_dir_norm('Carrera 9 A No. 18-05') || ' / ' || redes.f_dir_norm('KRA 9a 18 05'));
  perform pg_temp.reg('02.02 «N» suelta (norte) se conserva; sin apartamento, local ni torre para el segundo intento; vacío → nulo',
     redes.f_dir_norm('CL 9 N CR 9 - 9') = 'CL 9 N CR 9 9' and redes.f_dir_base(redes.f_dir_norm('Cra 9A # 18-05 Apto 201')) = 'CR 9A 18 5'
     and redes.f_dir_base(redes.f_dir_norm('MZ 4 CASA 7 TORRE 2')) = 'MZ 4 CS 7' and redes.f_dir_norm('  - ') is null);
  perform pg_temp.reg('02.03 el barrio se normaliza sin tildes, sin signos y sin «Barrio»/«Urbanización» delante',
     redes.f_barrio_norm('Barrio Los Cortijos') = 'LOS CORTIJOS' and redes.f_barrio_norm('URB. los cortijos') = 'LOS CORTIJOS' and redes.f_barrio_norm('Villa Castro (II etapa)') = 'VILLA CASTRO II ETAPA');
  perform pg_temp.reg('02.04 la fecha: AAAA-MM-DD, DD/MM/AAAA y el número de Excel, en hora de Bogotá; lo que no se entiende o es futuro, nulo',
     redes.f_l116_fecha('2026-01-01 11:21:28') = timestamptz '2026-01-01 11:21:28-05' and redes.f_l116_fecha('01/02/2026 08:30') = timestamptz '2026-02-01 08:30-05'
     and redes.f_l116_fecha('46023.5') = timestamptz '2026-01-01 12:00-05' and redes.f_l116_fecha('2026-01-01T07:05') = timestamptz '2026-01-01 07:05-05'
     and redes.f_l116_fecha('ayer') is null and redes.f_l116_fecha('2099-01-01') is null and redes.f_l116_fecha('31/02/2026') is null and redes.f_l116_fecha(null) is null);
  perform pg_temp.reg('02.05 de cada fila solo pasan las 9 columnas que se cargan (con nombre en minúscula): NOMBRE no pasa',
     (select array_agg(x.c order by x.c) from jsonb_object_keys(redes.f_l116_atributos((pg_temp.fila(1, 1, 'Atendido', '2026-01-01', '1', 'x', 'y', 'z', 'w') -> 'atributos')
                                                                                   || '{"Teléfono": "300", "nombre": "x"}')) x(c))
       = array['barrio', 'comuna', 'contrato', 'desc_causal', 'direccion', 'estado', 'fecha_registro', 'reporte', 'servicio']);

  -- ===================== 03. Los predios y el sector de prueba =====================
  insert into public.catastro_valledupar (cod_usuario, direccion, barrio, geom)
  values (C1, 'CL ZT15 1 # 2-3', 'ZT15 BARRIO UNO', pg_temp.pt(0, 0)),
         (C2, 'CR ZT15 5 A No. 7-09', 'ZT15 BARRIO UNO', pg_temp.pt(30, 0)),
         (C3, 'Carrera ZT15 5A 7 09', 'ZT15 BARRIO UNO', pg_temp.pt(34, 4)),
         ('99515004', 'MZ ZT15 1 CS 1', 'ZT15 BARRIO UNO', pg_temp.pt(0, 100)),
         ('99515005', 'MZ ZT15 1 CS 1', 'ZT15 BARRIO DOS', pg_temp.pt(900, 900)),
         ('99515006', 'CL ZT15 9 9', 'Barrio ZT15 Barrio Dos', pg_temp.pt(920, 900));
  v_sub := pg_temp.activo('SEC', pg_temp.caja(-50, -50, 200, 200), 'sectores', 'ZT15-SUB-95.1', 'subsector', '{"modelo": {"sector": 95, "subsector": "95.1"}}', 'ZT15 Subsector 95.1');

  -- ===================== 04. Primera carga por el motor (como la pantalla) =====================
  v_r := public.geoportal_redes_cargue_capas(sd);
  perform pg_temp.reg('04.01 el supervisor de distribución ve la capa en el Cargue, con su lector y sin reportes todavía',
     exists (select 1 from jsonb_array_elements(v_r -> 'capas') c where c ->> 'codigo' = 'linea_116' and c ->> 'lector' = 'linea_116' and (c ->> 'puede_cargar')::boolean and (c ->> 'vigentes')::integer = 0));
  perform pg_temp.err('04.02 el operador no entra al Cargue', format('select public.geoportal_redes_cargue_capas(%L)', op), '42501');
  perform pg_temp.err('04.03 la llave de la capa es «reporte» (no otra columna)',
     format('select public.geoportal_redes_cargue_iniciar(%L, %L, %L, %L, 4326, %L, 3)', sd, 'linea_116', md5('zt15x') || md5('zt15y'), 'csv', 'CONTRATO'), null, 'reporte');
  v_c1 := pg_temp.subir(sd, jsonb_build_array(
      pg_temp.fila(1, v_base + 1, 'Registrado', pg_temp.hoy(1), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto'),
      pg_temp.fila(2, v_base + 2, 'Registrado', pg_temp.hoy(2), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto'),
      pg_temp.fila(3, v_base + 3, 'Registrado', pg_temp.hoy(3), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(4, v_base + 4, 'Registrado', pg_temp.hoy(4), '99515099', 'Carrera ZT15 5 A # 7 - 09', 'ZT15 BARRIO UNO', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(5, v_base + 5, 'Registrado', pg_temp.hoy(5), '99515098', 'MZ ZT15 1 CS 1 AP 2', 'Barrio ZT15 Barrio Dos', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(6, v_base + 6, 'Registrado', pg_temp.hoy(6), '99515097', 'ZT15 dirección sin catastro', 'ZT15 BARRIO DOS', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(7, v_base + 7, 'Registrado', pg_temp.hoy(7), '99515096', 'ZT15 otra sin catastro', 'ZT15 BARRIO QUE NO EXISTE', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(8, v_base + 8, 'Atendido', pg_temp.hoy(8), C2, 'x', 'x', 'ZT15 REBOSE DE ALCANTARILLA', 'Alcantarillado'),
      pg_temp.fila(9, v_base + 9, 'Atendido', pg_temp.hoy(9), C2, 'x', 'x', 'ZT15 HUECO EN LA VÍA', 'Incidentes Externos'),
      pg_temp.fila(10, v_base + 11, 'Registrado', pg_temp.hoy(10), '99999999', 'Calle ZT15 1 # 2 - 3', 'ZT15 BARRIO UNO', 'ZT15 SIN AGUA', 'Acueducto')), md5('zt15-1') || md5('zt15-1b'));
  perform pg_temp.reg('04.04 NOMBRE no llega a la base: la carga guarda solo las 9 columnas (ni la palabra en ninguna fila)',
     not exists (select 1 from redes.carga_filas where carga_id = v_c1 and (atributos ? 'nombre' or atributos ? 'NOMBRE' or atributos::text like '%NOMBRE QUE NO SE GUARDA%'))
     and (select count(*) from redes.carga_filas where carga_id = v_c1 and llave is not null) = 10);
  v_r := public.geoportal_redes_carga_resumen(sd, v_c1);
  perform pg_temp.reg('04.05 el resumen: 10 nuevos, lista para publicar; ubicados 5 por contrato, 3 por dirección, 1 por barrio y 1 sin ubicar',
     (v_r ->> 'lista_para_publicar')::boolean and (v_r -> 'frente_a_vigente' ->> 'nuevo')::integer = 10
     and v_r -> 'ubicacion' = '{"contrato": 5, "direccion": 3, "barrio": 1, "sin_ubicar": 1}'::jsonb, (v_r - 'tabla')::text);
  perform pg_temp.reg('04.06 el resumen dice el sector de los ubicados dentro del polígono y avisa los sin ubicar; no trae direcciones, barrios ni nombres',
     (v_r ->> 'con_sector')::integer = 7 and v_r -> 'sin_ubicar_muestra' = to_jsonb(array[v_base + 7]) and v_r::text not like '%ZT15 BARRIO%' and v_r::text not like '%NOMBRE%'
     and v_r::text not like '%dirección sin catastro%', (v_r - 'tabla')::text);
  v_x := public.geoportal_redes_carga_publicar(sd, v_c1, 'ZT15 primera carga de la línea 116 de prueba');
  perform pg_temp.reg('04.07 publicar: 10 nuevos (versión 1); 10 reportes, 10 altas con método y 10 vigentes',
     (v_x ->> 'nuevos')::integer = 10 and (v_x ->> 'version_capa')::integer = 1
     and (select count(*) from redes.l116_reportes where carga_id = v_c1) = 10 and (select count(*) from redes.l116_eventos where carga_id = v_c1 and tipo = 'alta' and metodo is not null) = 10
     and (select count(*) from redes.l116_vigente v join redes.l116_reportes r on r.id = v.reporte_id where r.carga_id = v_c1) = 10, v_x::text);
  perform pg_temp.reg('04.08 por contrato: el punto del predio (y el sector 95, subsector 95.1); el comodín 99999999 no ubica por contrato, sí por su dirección',
     (select pg_temp.dist(geom, 0, 0) < 1 and metodo = 'contrato' and sector = 95 and subsector = '95.1' from redes.l116_vigente where reporte = v_base + 1)
     and (select pg_temp.dist(geom, 30, 0) < 1 and metodo = 'contrato' from redes.l116_vigente where reporte = v_base + 8)
     and (select pg_temp.dist(geom, 0, 0) < 1 and metodo = 'direccion' from redes.l116_vigente where reporte = v_base + 11));
  perform pg_temp.reg('04.09 por dirección: el centro de los predios con esa dirección (a 100 m o menos); si está en dos sitios, la del mismo barrio',
     (select pg_temp.dist(geom, 32, 2) < 2 and metodo = 'direccion' from redes.l116_vigente where reporte = v_base + 4)
     and (select pg_temp.dist(geom, 900, 900) < 1 and metodo = 'direccion' and sector is null from redes.l116_vigente where reporte = v_base + 5),
     (select string_agg(reporte || ' ' || metodo || ' ' || coalesce(ST_AsText(geom), '-'), ' | ') from redes.l116_vigente where reporte in (v_base + 4, v_base + 5)));
  perform pg_temp.reg('04.10 por barrio: el centro de sus predios (aproximada); sin contrato, dirección ni barrio en el catastro: sin ubicar (sin punto)',
     (select pg_temp.dist(geom, 910, 900) < 1 and metodo = 'barrio' from redes.l116_vigente where reporte = v_base + 6)
     and (select geom is null and metodo = 'sin_ubicar' from redes.l116_vigente where reporte = v_base + 7));

  -- ===================== 05. La capa del geovisor =====================
  v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', null, null);
  perform pg_temp.reg('05.01 hoy: 8 puntos (los dos reportes del mismo contrato, causal y día van juntos) y 1 sin ubicar',
     jsonb_array_length(v_g -> 'features') = 8 and (v_g ->> 'sin_ubicar')::integer = 1 and (pg_temp.punto(v_g, v_base + 1) ->> 'n')::integer = 2
     and pg_temp.punto(v_g, v_base + 1) -> 'reportes' = to_jsonb(array[v_base + 1, v_base + 2]) and (pg_temp.punto(v_g, v_base + 3) ->> 'n')::integer = 1,
     jsonb_array_length(v_g -> 'features') || ' puntos · ' || coalesce(pg_temp.punto(v_g, v_base + 1)::text, '-'));
  perform pg_temp.reg('05.02 color por servicio (acueducto, alcantarillado, otros) y estado (registrado o atendido)',
     pg_temp.punto(v_g, v_base + 1) ->> 'grupo_servicio' = 'acueducto' and pg_temp.punto(v_g, v_base + 1) ->> 'estado' = 'registrado'
     and pg_temp.punto(v_g, v_base + 8) ->> 'grupo_servicio' = 'alcantarillado' and pg_temp.punto(v_g, v_base + 8) ->> 'estado' = 'atendido'
     and pg_temp.punto(v_g, v_base + 9) ->> 'grupo_servicio' = 'otros' and pg_temp.punto(v_g, v_base + 4) ->> 'metodo' = 'direccion' and pg_temp.punto(v_g, v_base + 6) ->> 'metodo' = 'barrio');
  perform pg_temp.reg('05.03 la capa no trae nombre, dirección ni barrio (solo las propiedades previstas)',
     not exists (select 1 from jsonb_array_elements(v_g -> 'features') f, jsonb_object_keys(f -> 'properties') kk
                  where kk not in ('codigo', 'n', 'reportes', 'servicio', 'grupo_servicio', 'causal', 'estado', 'registrados', 'contrato', 'dia', 'cuando', 'ultimo', 'metodo', 'sector', 'subsector', 'danos'))
     and v_g::text not like '%BARRIO%' and v_g::text not like '%NOMBRE%' and v_g::text not like '%CL ZT15%');
  perform pg_temp.err('05.04 el operador no ve la capa (es de supervisores)', format('select public.geoportal_redes_geovisor_capa(%L, %L, null, null)', op, 'pqr_116'), '42501');
  v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', v_hoy - 3, v_hoy - 1);
  perform pg_temp.reg('05.05 por fecha: en los tres días anteriores no sale ninguno de hoy', not exists (select 1 from jsonb_array_elements(v_g -> 'features') f
                                                                                                        where (f -> 'properties' ->> 'codigo')::bigint between v_base and v_base + 99));

  -- ===================== 06. Cargas siguientes: cambio de estado, iguales, errores =====================
  perform pg_temp.err('06.01 el mismo archivo no se publica dos veces', format('select public.geoportal_redes_cargue_iniciar(%L, %L, %L, %L, 4326, %L, 10)', sd, 'linea_116', md5('zt15-1') || md5('zt15-1b'), 'xlsx', 'reporte'),
     null, 'ya se publicó');
  v_c2 := pg_temp.subir(sd, jsonb_build_array(
      pg_temp.fila(1, v_base + 1, 'Atendido', pg_temp.hoy(1), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto'),
      pg_temp.fila(2, v_base + 2, 'Registrado', pg_temp.hoy(2), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto'),
      pg_temp.fila(3, v_base + 3, 'Registrado', pg_temp.hoy(3), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 OTRA CAUSAL ESCRITA', 'Acueducto'),
      pg_temp.fila(4, v_base + 12, 'Registrado', pg_temp.hoy(12), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto')), md5('zt15-2') || md5('zt15-2b'));
  v_r := public.geoportal_redes_carga_resumen(sd, v_c2);
  perform pg_temp.reg('06.02 la segunda carga reconoce los reportes por su número: 1 nuevo, 1 con cambio de estado y 2 iguales (uno con otra causal: aviso, se conserva la primera)',
     (v_r ->> 'lista_para_publicar')::boolean and (v_r -> 'frente_a_vigente' ->> 'nuevo')::integer = 1 and (v_r -> 'frente_a_vigente' ->> 'estado')::integer = 1
     and (v_r -> 'frente_a_vigente' ->> 'igual')::integer = 2 and exists (select 1 from jsonb_array_elements_text(v_r -> 'avisos') x where x like '1 reportes ya cargados traen otra%'),
     (v_r - 'tabla')::text);
  v_x := public.geoportal_redes_carga_publicar(sd, v_c2, 'ZT15 segunda carga de la línea 116 de prueba');
  perform pg_temp.reg('06.03 publicar: el cambio de estado es un evento con fecha (antes registrado, ahora atendido); la causal del primero no cambia',
     (v_x ->> 'nuevos')::integer = 1 and (v_x ->> 'cambios_estado')::integer = 1 and (v_x ->> 'iguales')::integer = 2 and (v_x ->> 'version_capa')::integer = 2
     and (select array_agg(e.tipo || ':' || e.estado || ':' || coalesce(e.estado_antes, '-') order by e.id) from redes.l116_eventos e join redes.l116_reportes r on r.id = e.reporte_id where r.reporte = v_base + 1)
         = array['alta:registrado:-', 'estado:atendido:registrado']
     and (select estado from redes.l116_vigente where reporte = v_base + 1) = 'atendido' and (select causal from redes.l116_reportes where reporte = v_base + 3) = 'ZT15 SIN AGUA', v_x::text);
  v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', null, null);
  perform pg_temp.reg('06.04 en el mapa el grupo del contrato, causal y día tiene ahora 3 reportes (2 registrados: sigue «registrado»)',
     (pg_temp.punto(v_g, v_base + 1) ->> 'n')::integer = 3 and (pg_temp.punto(v_g, v_base + 1) ->> 'registrados')::integer = 2 and pg_temp.punto(v_g, v_base + 1) ->> 'estado' = 'registrado',
     coalesce(pg_temp.punto(v_g, v_base + 1)::text, '-'));
  v_c3 := pg_temp.subir(sd, jsonb_build_array(
      pg_temp.fila(1, v_base + 20, 'Registrado', 'ayer', C1, 'x', 'x', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(2, v_base + 21, 'Cerrado', pg_temp.hoy(20), C1, 'x', 'x', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(3, v_base + 22, 'Registrado', pg_temp.hoy(21), C1, 'x', 'x', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(4, v_base + 22, 'Registrado', pg_temp.hoy(22), C1, 'x', 'x', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(5, v_base + 23, 'Registrado', pg_temp.hoy(23), C1, 'x', 'x', null, 'Acueducto')), md5('zt15-3') || md5('zt15-3b'));
  v_r := public.geoportal_redes_carga_resumen(sd, v_c3);
  perform pg_temp.reg('06.05 con errores no se publica: fecha que no se entiende, estado desconocido, causal vacía y número repetido (dice la fila y el reporte)',
     not (v_r ->> 'lista_para_publicar')::boolean and (v_r -> 'frente_a_vigente' ->> 'error')::integer = 3
     and exists (select 1 from jsonb_array_elements_text(v_r -> 'bloqueos') b where b like '3 filas con error: fila 1 (reporte ' || (v_base + 20) || '): la fecha%' and b like '%fila 2 (reporte%el estado no es%'
                                                                                and b like '%falta la causal%')
     and exists (select 1 from jsonb_array_elements_text(v_r -> 'bloqueos') b where b = '1 números de reporte repetidos en el archivo: ' || (v_base + 22)), (v_r -> 'bloqueos')::text);
  perform pg_temp.err('06.06 … y la publicación se niega', format('select public.geoportal_redes_carga_publicar(%L, %s, %L)', sd, v_c3, 'ZT15 no debe publicarse'), null, 'no está lista');
  perform public.geoportal_redes_carga_anular(sd, v_c3, 'ZT15 se anula la carga con errores');

  -- ===================== 07. Volver atrás una carga (nada se borra) =====================
  v_x := public.geoportal_redes_carga_revertir(sd, 'linea_116', 'ZT15 se revierte la segunda carga de prueba');
  perform pg_temp.reg('07.01 revertir la segunda carga: su reporte nuevo se oculta y el cambio de estado vuelve con un evento nuevo (los eventos siguen)',
     (v_x ->> 'ocultados')::integer = 1 and (v_x ->> 'estados_devueltos')::integer = 1
     and (select oculto from redes.l116_vigente where reporte = v_base + 12) and (select estado from redes.l116_vigente where reporte = v_base + 1) = 'registrado'
     and (select count(*) from redes.l116_eventos e join redes.l116_reportes r on r.id = e.reporte_id where r.reporte in (v_base + 1, v_base + 12)) = 5
     and exists (select 1 from redes.l116_reportes where reporte = v_base + 12), v_x::text);
  v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', null, null);
  perform pg_temp.reg('07.02 en el mapa el grupo vuelve a 2 reportes', (pg_temp.punto(v_g, v_base + 1) ->> 'n')::integer = 2);
  v_c4 := pg_temp.subir(sd, jsonb_build_array(
      pg_temp.fila(1, v_base + 1, 'Atendido', pg_temp.hoy(1), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto'),
      pg_temp.fila(2, v_base + 12, 'Atendido', pg_temp.hoy(12), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto')), md5('zt15-2') || md5('zt15-2b'));
  v_r := public.geoportal_redes_carga_resumen(sd, v_c4);
  v_x := public.geoportal_redes_carga_publicar(sd, v_c4, 'ZT15 se vuelve a cargar el archivo revertido');
  perform pg_temp.reg('07.03 el archivo revertido se puede volver a cargar: el reporte oculto vuelve (evento «mostrar») con su estado nuevo',
     (v_r -> 'frente_a_vigente' ->> 'mostrar')::integer = 1 and (v_r -> 'frente_a_vigente' ->> 'estado')::integer = 1
     and not (select oculto from redes.l116_vigente where reporte = v_base + 12) and (select estado from redes.l116_vigente where reporte = v_base + 12) = 'atendido'
     and exists (select 1 from redes.l116_eventos e join redes.l116_reportes r on r.id = e.reporte_id where r.reporte = v_base + 12 and e.tipo = 'mostrar'), (v_r - 'tabla')::text);
  perform pg_temp.err('07.04 solo agregar: no se cambia un reporte', format('update redes.l116_reportes set causal = %L where reporte = %s', 'x', v_base + 1), '42501');
  perform pg_temp.err('07.05 solo agregar: no se borra un evento', format('delete from redes.l116_eventos where reporte_id = (select id from redes.l116_reportes where reporte = %s)', v_base + 1), '42501');
  perform pg_temp.reg('07.06 el Cargue cuenta los reportes que se ven (12 de prueba; el oculto vuelve)',
     (select (c ->> 'vigentes')::integer from jsonb_array_elements(public.geoportal_redes_cargue_capas(sd) -> 'capas') c where c ->> 'codigo' = 'linea_116')
       = (select count(*) from redes.l116_vigente where not oculto));

  -- ===================== 08. «Convertir en daño» (la RPC, sin botón) =====================
  v_dano := pg_temp.dano(op, jsonb_build_object('lat', pg_temp.lat(0), 'lon', pg_temp.lon(0), 'no_identificado', 'ZT15 tubería del reporte'));
  v_x := public.geoportal_redes_l116_vincular_dano(sd, v_base + 1, v_dano, 'ZT15 el reporte de la 116 resultó ser este daño');
  v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', null, null);
  perform pg_temp.reg('08.01 el supervisor une el reporte con el daño (con motivo, auditado) y el punto del mapa lo muestra',
     (v_x ->> 'unido')::boolean and pg_temp.punto(v_g, v_base + 1) -> 'danos' = to_jsonb(array[v_dano])
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_l116_vincular_dano' and referencia = (v_base + 1)::text), v_x::text);
  perform pg_temp.err('08.02 el operador no lo hace', format('select public.geoportal_redes_l116_vincular_dano(%L, %s, %L, %L)', op, v_base + 1, v_dano, 'ZT15 no debe poder'), '42501');
  perform pg_temp.err('08.03 no se une dos veces', format('select public.geoportal_redes_l116_vincular_dano(%L, %s, %L, %L)', sd, v_base + 1, v_dano, 'ZT15 otra vez lo mismo'), null, 'ya está unido');
  perform pg_temp.err('08.04 sin motivo, no', format('select public.geoportal_redes_l116_vincular_dano(%L, %s, %L, %L)', sd, v_base + 3, v_dano, 'corto'), null, 'motivo');
  perform pg_temp.err('08.05 un reporte que no existe, no', format('select public.geoportal_redes_l116_vincular_dano(%L, %s, %L, %L)', sd, v_base + 99, v_dano, 'ZT15 reporte que no existe'), 'P0002');

  -- ===================== 09. Punto 8: los formularios compartidos en Personal del Dashboard distribución =====================
  v_r := public.geoportal_redes_personal(sd, 'prueba.redes15', 'todas');
  perform pg_temp.reg('09.01 Personal lista «Reportar anomalía» y «Revisiones generales» entre los formularios de distribución',
     (select count(*) from jsonb_array_elements(v_r -> 'formularios') f where f ->> 'clave' in ('anomalia_compartida', 'revision_compartida')) = 2);
  perform public.geoportal_redes_personal_formulario(sd, op, 'anomalia_compartida', true, 'ZT15 el operador reporta anomalías desde Técnica');
  perform public.geoportal_redes_personal_formulario(sd, op, 'revision_compartida', true, 'ZT15 el operador hace revisiones generales');
  v_r := public.geoportal_redes_personal(sd, 'prueba.redes15.op', 'todas');
  perform pg_temp.reg('09.02 el supervisor de distribución se los asigna a un operador (quedan en sus formularios)',
     tecnica.f_formulario_asignado(op, 'anomalia_compartida') and tecnica.f_formulario_asignado(op, 'revision_compartida')
     and (v_r -> 'personas' -> 0 -> 'formularios') @> '["anomalia_compartida", "revision_compartida"]'::jsonb, (v_r -> 'personas' -> 0 -> 'formularios')::text);

  -- ===================== 10. Tiempos con el volumen real: 22.978 reportes sintéticos por el motor =====================
  -- Contratos tomados del catastro de esta base (como en el archivo: ~86 % con predio; el resto con un contrato que no existe, una dirección y un barrio
  -- de prueba que tampoco: así se mide el peor caso, la pasada por el catastro). Las fechas, repartidas en los últimos 12 meses.
  select array_agg(cod_usuario) into v_cods from (select distinct cod_usuario from public.catastro_valledupar where cod_usuario ~ '^[0-9]{1,8}$' and cod_usuario not in ('0', '99999999')
                                                    and cod_usuario not like '995150%' order by cod_usuario limit 20000) x;
  v_nc := coalesce(cardinality(v_cods), 0);
  v_t0 := clock_timestamp();
  v_cv := (public.geoportal_redes_cargue_iniciar(sd, 'linea_116', md5('zt15-volumen') || md5('zt15-volumen-b'), 'xlsx', 4326, 'reporte', v_n, 'ZT15 volumen real') ->> 'carga_id')::bigint;
  v_ms_ini := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  k := 0;
  while k < v_n loop
    select jsonb_agg(pg_temp.fila(i, 995200000 + i, case when i % 11 = 0 then 'Registrado' else 'Atendido' end,
                                  to_char((clock_timestamp() at time zone 'America/Bogota') - make_interval(days => i % 360, mins => i % 1440), 'YYYY-MM-DD HH24:MI:SS'),
                                  case when i % 7 = 0 or v_nc = 0 then '9952' || i else v_cods[1 + (i * 7919) % v_nc] end,
                                  'ZT15 DIR ' || i, 'ZT15 BARRIO ' || (i % 50), 'ZT15 CAUSAL ' || (i % 29),
                                  case when i % 3 = 0 then 'Alcantarillado' when i % 41 = 0 then 'Incidentes Externos' else 'Acueducto' end) order by i)
      into v_lote from generate_series(k + 1, least(k + 200, v_n)) i;
    v_t0 := clock_timestamp();
    perform public.geoportal_redes_carga_lote(sd, v_cv, v_lote);
    v_ms_lote := greatest(v_ms_lote, round(extract(epoch from clock_timestamp() - v_t0) * 1000));
    k := k + 200;
  end loop;
  v_t0 := clock_timestamp(); v_r := public.geoportal_redes_carga_resumen(sd, v_cv); v_ms_res := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_x := public.geoportal_redes_carga_publicar(sd, v_cv, 'ZT15 carga de volumen real'); v_ms_pub := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', (v_hoy - interval '12 months')::date, v_hoy); v_ms_capa := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_geovisor_capa(sd, 'pqr_116', v_hoy - 6, v_hoy); v_ms_capa_hoy := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS con %s reportes (%s contratos del catastro): iniciar %s ms · lote más lento %s ms · resumen %s ms · publicar %s ms · capa de 12 meses %s ms (%s puntos%s) · capa de 7 días %s ms · ubicación %s',
                   v_n, v_nc, v_ms_ini, v_ms_lote, v_ms_res, v_ms_pub, v_ms_capa, jsonb_array_length(v_g -> 'features'), case when (v_g ->> 'recortada')::boolean then ', recortada' else '' end,
                   v_ms_capa_hoy, v_x -> 'ubicacion');
  perform pg_temp.reg('10.01 la carga completa se publica: 22.978 nuevos', (v_x ->> 'nuevos')::integer = v_n and (v_r ->> 'lista_para_publicar')::boolean, v_info);
  perform pg_temp.reg('10.02 cada lote en menos de 8 s; el resumen y la publicación, cada uno en menos de 30 s (el tope de la Edge)',
     v_ms_lote < 8000 and v_ms_res < 30000 and v_ms_pub < 30000, v_info);
  perform pg_temp.reg('10.03 la capa del geovisor (12 meses y 7 días) en menos de 8 s', greatest(v_ms_capa, v_ms_capa_hoy) < 8000, v_info);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 5d (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
