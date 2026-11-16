begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 10 — GUARDIA, TABLAS NUEVAS, CAPAS Y PARÁMETRO
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: plan 02 (Corte 5c), 01 sección E, D-4 y D-20 de 03, §31.1 y §32.1-2 de la bitácora.
-- · Presupone el 5b aplicado (huella del conjunto de funciones de redes y las 2 RPC de planta del 5b que se reemplazan).
-- · ⚠ Se reemplazan 6 funciones internas de redes (motor del 1a y del 5a) y 2 RPC de planta del 5b, con su texto exacto en la reversa.
-- · ⚠ tecnica.puntos_ubicacion (5a): se amplía su CHECK de «fuente» con «correccion» (§32.2). Solo inserción, como siempre.
-- · tecnica.puntos (viva): no se toca.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.punto_ubicacion_propuestas') is null or to_regclass('tecnica.v_punto_propuestas') is null then
    raise exception 'Falta el Corte 5b: aplíquelo antes';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'cbff4ee6e25826251d90496c833ac3de' then
    raise exception 'Las funciones de redes no son las del Corte 5b (o el Corte 5c ya está aplicado): deténgase y avise';
  end if;
  if (select count(*) from (values ('public.geoportal_tec_punto_ubicacion_revisar(text,bigint,text,text,text)', '450f01d67ca644905a223c1e99ca062a'), ('public.geoportal_tec_punto_ubicaciones(text)', '22930b502a1d1ee412f5288a3bb3c27e')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2 then
    raise exception 'Las RPC de planta del 5b (revisar y listar ubicaciones) no son las del Corte 5b: deténgase y avise';
  end if;
  if to_regclass('redes.ficha_campo_devoluciones') is not null or to_regclass('tecnica.punto_ubicacion_correcciones') is not null then
    raise exception 'Las tablas del 5c ya existen: el Corte 5c parece aplicado';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'tecnica.puntos_ubicacion'::regclass and conname = 'puntos_ubicacion_fuente_check')
     <> 'CHECK ((fuente = ANY (ARRAY[''david''::text, ''barrio''::text, ''gps_operador''::text, ''carga''::text])))' then
    raise exception 'El CHECK de fuente de tecnica.puntos_ubicacion no es el del 5a: deténgase y avise';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'tecnica.puntos_ubicacion'::regclass and tgname = 't_solo_agregar' and not tgisinternal) then
    raise exception 'tecnica.puntos_ubicacion no tiene su candado de solo inserción: deténgase y avise';
  end if;
  if to_regprocedure('extensions.st_transform(geometry,text,integer)') is null and to_regprocedure('public.st_transform(geometry,text,integer)') is null then
    raise exception 'Este PostGIS no tiene ST_Transform(geometría, proj, srid) (PostGIS 3): deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. «DEVOLVER ESTE CAMPO A LA CAPA» (§31.1). Un campo editado en la ficha gana en cada recarga (5a, §26.3); con una devolución, ese campo
--    vuelve a mandarlo la capa desde la próxima publicación, hasta que alguien lo edite otra vez en la ficha. Solo inserción, con motivo.
-- ---------------------------------------------------------------------
create table redes.ficha_campo_devoluciones (
  id          bigint generated always as identity primary key,
  activo_id   bigint not null references redes.activos (id),
  campo       text not null check (campo in ('nombre', 'estado_codigo', 'clase', 'efecto', 'material_codigo', 'diametro_mm', 'capacidad', 'profundidad_m', 'origen')
                                   or campo ~ '^atributos\.[A-Za-z0-9_]{1,60}$'),
  carga_id    bigint references redes.cargas (id),          -- la carga abierta en la que se pidió (la lista de choques)
  valor_ficha text check (valor_ficha is null or length(valor_ficha) <= 500),      -- el valor que tenía la ficha al devolverlo (queda en el historial)
  motivo      text not null check (length(btrim(motivo)) between 10 and 1000),
  autor       text not null,
  creado_en   timestamptz not null default clock_timestamp()
);
create index ix_fcd_activo on redes.ficha_campo_devoluciones (activo_id, campo, creado_en desc);
comment on table redes.ficha_campo_devoluciones is 'Corte 5c (§31.1): «Devolver este campo a la capa». Desde aquí la capa vuelve a mandar en ese campo del activo, hasta otra edición en la ficha. Solo inserción.';

-- ---------------------------------------------------------------------
-- 2. CORREGIR UNA UBICACIÓN VERIFICADA (§32.2), con motivo obligatorio. La ubicación nueva se AGREGA a tecnica.puntos_ubicacion (fuente «correccion»);
--    la anterior queda en el historial. Solo inserción.
-- ---------------------------------------------------------------------
alter table tecnica.puntos_ubicacion drop constraint puntos_ubicacion_fuente_check;
alter table tecnica.puntos_ubicacion add constraint puntos_ubicacion_fuente_check check (fuente = any (array['david', 'barrio', 'gps_operador', 'carga', 'correccion']));

create table tecnica.punto_ubicacion_correcciones (
  id                  bigint generated always as identity primary key,
  punto_id            bigint not null references tecnica.puntos (id),
  ubicacion_id        bigint not null unique references tecnica.puntos_ubicacion (id),      -- la que se agregó
  ubicacion_previa_id bigint not null references tecnica.puntos_ubicacion (id),             -- la verificada que se corrigió
  metodo              text not null check (metodo in ('mapa', 'coordenadas', 'gps')),
  precision_m         numeric(6, 1) check (precision_m is null or (precision_m > 0 and precision_m <= 1000)),
  distancia_m         numeric(9, 1) not null check (distancia_m >= 0),
  motivo              text not null check (length(btrim(motivo)) between 10 and 1000),
  autor               text not null,
  creado_en           timestamptz not null default clock_timestamp(),
  constraint puc_gps_con_precision check ((metodo = 'gps') = (precision_m is not null))
);
create index ix_puc_punto on tecnica.punto_ubicacion_correcciones (punto_id, id desc);
comment on table tecnica.punto_ubicacion_correcciones is 'Corte 5c (§32.2): corrección de una ubicación verificada de un punto de muestreo, desde «Puntos» del Dashboard PTAP, con motivo. Solo inserción.';

do $$
begin
  execute 'create trigger t_solo_agregar before update or delete on redes.ficha_campo_devoluciones for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on redes.ficha_campo_devoluciones for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar before update or delete on tecnica.punto_ubicacion_correcciones for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on tecnica.punto_ubicacion_correcciones for each statement execute function tecnica.f_solo_agregar()';
  execute 'alter table redes.ficha_campo_devoluciones enable row level security';
  execute 'alter table tecnica.punto_ubicacion_correcciones enable row level security';
end $$;

-- ---------------------------------------------------------------------
-- 3. CAPAS DEL CARGUE (01 sección E, maqueta «Cargue de capas»): las de un solo tipo de activo, con el lector genérico del 5c.
--    Las válvulas, torres, accesorios, macromedidores y tanques siguen saliendo del modelo de acueducto (acueducto_nodos). Las PQR, la línea 116,
--    los barrios y el APS no son activos: no van aquí (ver el INFORME).
-- ---------------------------------------------------------------------
insert into redes.capas (codigo, nombre, grupo, sistema, geometria, prefijo, fuente, columna_llave, formatos, orden) values
  ('captaciones',    'Captaciones (bocatoma, pozo profundo)',           'acueducto',           'acueducto',      'punto',    'CAP', 'carga', null, '{shp,gpkg,geojson,kml,csv,xlsx}', 110),
  ('aduccion',       'Tubería de aducción',                             'acueducto',           'acueducto',      'linea',    'ADU', 'carga', null, '{shp,gpkg,geojson,kml}', 120),
  ('desarenadores',  'Desarenadores',                                   'acueducto',           'acueducto',      'punto',    'DES', 'carga', null, '{shp,gpkg,geojson,kml,csv,xlsx}', 130),
  ('bombeo_ap',      'Estaciones de bombeo de agua potable',            'acueducto',           'acueducto',      'punto',    'EBA', 'carga', null, '{shp,gpkg,geojson,kml,csv,xlsx}', 140),
  ('sumideros',      'Sumideros',                                       'alcantarillado',      'alcantarillado', 'punto',    'SUM', 'carga', null, '{shp,gpkg,geojson,kml,csv,xlsx}', 210),
  ('interceptores',  'Interceptores y emisarios',                       'alcantarillado',      'alcantarillado', 'linea',    'INT', 'carga', null, '{shp,gpkg,geojson,kml}', 220),
  ('bombeo_ar',      'Estaciones de bombeo de aguas residuales',        'alcantarillado',      'alcantarillado', 'punto',    'EBR', 'carga', null, '{shp,gpkg,geojson,kml,csv,xlsx}', 230),
  ('ptar',           'Plantas de tratamiento de aguas residuales (PTAR)', 'alcantarillado',    'alcantarillado', 'punto',    'PTR', 'carga', null, '{shp,gpkg,geojson,kml,csv,xlsx}', 240),
  ('sectores',       'Sectores hidráulicos',                            'tecnologia_perdidas', 'tecnologia',     'poligono', 'SEC', 'carga', null, '{shp,gpkg,geojson,kml}', 310),
  ('sensores',       'Sensores (nivel, presión, caudal, calidad)',      'tecnologia_perdidas', 'tecnologia',     'punto',    'SEN', 'carga', null, '{shp,gpkg,geojson,kml,csv,xlsx}', 320),
  ('scada',          'Equipos SCADA y telemetría',                      'tecnologia_perdidas', 'tecnologia',     'punto',    'SCA', 'carga', null, '{shp,gpkg,geojson,kml,csv,xlsx}', 330)
on conflict (codigo) do nothing;
update redes.capas set activa = true      -- si una reversa del 5c las dejó inactivas
 where not activa and codigo in ('captaciones', 'aduccion', 'desarenadores', 'bombeo_ap', 'sumideros', 'interceptores', 'bombeo_ar', 'ptar', 'sectores', 'sensores', 'scada');
-- acometidas (ACO, D-3) ya existe vacía desde el 1a: queda lista con el lector genérico (sin llave fija: la elige quien carga, o va por geometría).

-- ---------------------------------------------------------------------
-- 4. PARÁMETRO del cruce por geometría (D-4)
-- ---------------------------------------------------------------------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('cruce_geometria_tol_m', 2, 'm', 0.1, 50, 'Tolerancia del cruce por geometría de una capa sin columna llave (D-4): puntos a menos de esta distancia; líneas y polígonos con la distancia de Hausdorff por debajo (Corte 5c)')
on conflict (clave) do nothing;      -- una reversa lo deja (los parámetros no se borran)
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 5b con cambios exactos, aplicados una sola vez:
--   · redes.f_geo_desde_wkt: EPSG 9377 con su definición cuando el PostGIS no lo trae; el punto suelto que viene como multipunto;
--   · redes.f_candidatos: lector genérico de las capas de un solo tipo (acometidas y las capas nuevas);
--   · redes.f_preparar_candidatos: cruce por geometría (D-4) de una carga sin columna llave;
--   · redes.f_resumen: «sin columna llave», el resultado del cruce, la geometría que no es la del tipo y los atributos demasiado grandes;
--   · redes.f_fusionar_ficha: «Devolver este campo a la capa» (§31.1);
--   · redes.f_iniciar: la marca de la carga masiva;
--   · public.geoportal_tec_punto_ubicacion_revisar y _ubicaciones (planta, 5b): el administrador aprueba lo suyo (§32.1) y la lista de correcciones (§32.2).
-- =====================================================================

-- redes.f_geo_desde_wkt(text,integer)
CREATE OR REPLACE FUNCTION redes.f_geo_desde_wkt(p_wkt text, p_srid integer, OUT geom geometry, OUT error text)
 RETURNS record
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare g geometry;
begin
  if p_wkt is null or btrim(p_wkt) = '' then error := 'Sin geometría'; return; end if;
  begin
    g := ST_GeomFromText(p_wkt, p_srid);
    if p_srid = 9377 and not exists (select 1 from spatial_ref_sys where srid = 9377) then
      -- Corte 5c: MAGNA-SIRGAS Origen Nacional (EPSG 9377, Resolución IGAC 471 de 2020) no viene en todos los PostGIS: se reproyecta con su definición
      g := ST_Transform(ST_SetSRID(g, 0), '+proj=tmerc +lat_0=4 +lon_0=-73 +k=0.9992 +x_0=5000000 +y_0=2000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs', 4326);
    elsif p_srid <> 4326 then g := ST_Transform(g, 4326); end if;
    g := ST_Force2D(g);
  exception when others then error := left('No se pudo leer la geometría: ' || sqlerrm, 300); return;
  end;
  if ST_IsEmpty(g) then error := 'La geometría está vacía'; return; end if;
  if GeometryType(g) = 'MULTIPOINT' and ST_NumGeometries(g) = 1 then g := ST_GeometryN(g, 1); end if;      -- Corte 5c: SHP y GeoPackage guardan a veces el punto así
  if GeometryType(g) not in ('POINT', 'LINESTRING', 'MULTILINESTRING', 'POLYGON', 'MULTIPOLYGON') then error := 'Tipo de geometría no admitido: ' || GeometryType(g); return; end if;
  if GeometryType(g) = 'MULTILINESTRING' and ST_NumGeometries(g) = 1 then g := ST_GeometryN(g, 1); end if;
  if ST_XMin(g) < redes.f_param('caja_lon_min') or ST_XMax(g) > redes.f_param('caja_lon_max')
     or ST_YMin(g) < redes.f_param('caja_lat_min') or ST_YMax(g) > redes.f_param('caja_lat_max') then
    error := 'Fuera de la caja de Valledupar: revise el sistema de coordenadas del archivo'; return;
  end if;
  geom := g;
end $function$;

-- redes.f_candidatos(bigint)
CREATE OR REPLACE FUNCTION redes.f_candidatos(p_carga bigint)
 RETURNS TABLE(capa_codigo text, llave text, orden integer, prefijo text, geom geometry, nombre text, clase text, efecto text, material_codigo text, material_texto text, diametro_mm numeric, longitud_m numeric, profundidad_m numeric, capacidad numeric, estado_codigo text, origen text, aportante_codigo text, codigo_anterior text, atributos jsonb, macro_num integer, crea_activo boolean, crea_nodo boolean, nodo_sistema text, nodo_nombre text, clase_nodo text, dispersion_m numeric, nodo_ini text, nodo_fin text, nombres_distintos integer)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare v_capa text := (select c.capa_codigo from redes.cargas c where c.id = p_carga);
begin
  if v_capa = 'acueducto' then
    return query
    with f as (select cf.orden, cf.llave, cf.atributos a, cf.geom from redes.carga_filas cf where cf.carga_id = p_carga and cf.error is null)
    -- tramos (RED o CON)
    select 'acueducto'::text, f.llave, f.orden,
           case when f.a ->> 'LABEL' ~* '^conducci[oó]n' then 'CON' else 'RED' end,
           f.geom, null::text, null::text, null::text,
           (select e.material_codigo from redes.material_equivalencias e where e.texto_norm = redes.f_norm(f.a ->> 'MATERIAL')),
           f.a ->> 'MATERIAL',
           round(redes.f_num(f.a -> 'D') * 25.4),                                          -- N-6: pulgadas del modelo → mm
           round(ST_Length(f.geom::geography)::numeric, 2), null::numeric, null::numeric,
           case when f.a ->> 'ZONE' = 'Proyectado' then 'proyectado' when redes.f_bool(f.a -> 'IS_ACTIVE?') is false then 'inactivo_modelo' else 'en_operacion' end,
           case when f.a ->> 'ZONE' = 'SIVA' then 'tercero' else 'emdupar' end,
           case when f.a ->> 'ZONE' = 'SIVA' then 'siva' end,
           f.a ->> 'LABEL',
           jsonb_strip_nulls(jsonb_build_object('diametro_pulg', redes.f_num(f.a -> 'D'), 'longitud_modelo_m', redes.f_num(f.a -> 'LENGTH'),
             'valvula_retencion', case when redes.f_bool(f.a -> 'CHK_VLVE?') then true end, 'zona_modelo', f.a ->> 'ZONE',
             'modelo', f.a - array['LABEL', 'MATERIAL', 'D', 'LENGTH', 'STARTNODID', 'STARTNODE', 'STOPNODEID', 'STOPNODE'])),
           null::integer, true, false, null::text, null::text, null::text, null::numeric,
           nullif(btrim(f.a ->> 'STARTNODID'), ''), nullif(btrim(f.a ->> 'STOPNODEID'), ''), null::integer
      from f
    union all
    -- nodos del modelo, armados desde los extremos de los tramos (A.0)
    select 'acueducto_nodos'::text, x.llave, x.orden, k.prefijo, x.pto, null::text, k.clase, k.efecto, null::text, null::text,
           null::numeric, null::numeric, null::numeric, null::numeric, k.estado, 'emdupar'::text, null::text, x.nombre,
           jsonb_build_object('nombre_modelo', x.nombre), k.macro_num,
           k.prefijo is not null, true, 'acueducto'::text, x.nombre, case when k.prefijo is null then 'por_clasificar' else 'activo' end,
           x.dispersion, null::text, null::text, x.nombres
      from (
        -- el punto del nodo es el del primer extremo que lo nombra; la dispersión, la mayor distancia de los demás extremos a ese punto
        select x0.llave, x0.orden, x0.nombre, x0.pto, x0.nombres,
               coalesce((select max(ST_Distance(q::geography, x0.pto::geography)) from unnest(x0.ptos) q), 0)::numeric as dispersion
          from (select e.llave, min(e.orden) as orden,
                       (array_agg(e.nombre order by e.orden, e.lado))[1] as nombre,
                       (array_agg(e.pto order by e.orden, e.lado))[1] as pto,
                       count(distinct e.nombre)::integer as nombres,
                       array_agg(e.pto) as ptos
                  from (select nullif(btrim(f.a ->> 'STARTNODID'), '') as llave, f.a ->> 'STARTNODE' as nombre, ST_StartPoint(f.geom) as pto, f.orden, 0 as lado from f
                        union all
                        select nullif(btrim(f.a ->> 'STOPNODEID'), ''), f.a ->> 'STOPNODE', ST_EndPoint(f.geom), f.orden, 1 from f) e
                 where e.llave is not null
                 group by e.llave) x0) x
      cross join lateral redes.f_clasificar_nodo_acueducto(x.nombre) k;

  elsif v_capa = 'alc_conductos' then
    return query
    select 'alc_conductos'::text, cf.llave, cf.orden, 'COL'::text, cf.geom, null::text, null::text, null::text,
           (select e.material_codigo from redes.material_equivalencias e where e.texto_norm = redes.f_norm(cf.atributos ->> 'MATERIAL')),
           cf.atributos ->> 'MATERIAL',
           redes.f_num(cf.atributos -> 'DIAMETRO'), round(ST_Length(cf.geom::geography)::numeric, 2), null::numeric, null::numeric,
           redes.f_estado_alcantarillado(cf.atributos ->> 'ESTADO'), 'emdupar'::text, null::text, cf.atributos ->> 'LABEL',
           jsonb_strip_nulls(jsonb_build_object('estado_fisico', cf.atributos ->> 'EDO_FiSICO', 'estado_operativo', cf.atributos ->> 'EDO_OPENAL',
             'estado_capa', cf.atributos ->> 'ESTADO', 'pendiente', redes.f_num(cf.atributos -> 'PENDIENTE'),
             'longitud_modelo_m', redes.f_num(cf.atributos -> 'LONGITUD'), 'descarga', cf.atributos ->> 'DESCARGA',
             'modelo', cf.atributos - array['LABEL', 'MATERIAL', 'DIAMETRO', 'ESTADO', 'EDO_FiSICO', 'EDO_OPENAL', 'PZ_INICIAL', 'PZ_FINAL'])),
           null::integer, true, false, null::text, null::text, null::text, null::numeric,
           nullif(btrim(cf.atributos ->> 'PZ_INICIAL'), ''), nullif(btrim(cf.atributos ->> 'PZ_FINAL'), ''), null::integer
      from redes.carga_filas cf where cf.carga_id = p_carga and cf.error is null;

  elsif v_capa = 'alc_pozos' then
    return query
    select 'alc_pozos'::text, cf.llave, cf.orden,
           case when redes.f_norm(cf.atributos ->> 'EST_POZO') = 'virtual' then null else 'POZ' end,      -- N-4: los virtuales son solo nodo
           cf.geom, null::text, null::text, null::text, null::text, null::text, null::numeric, null::numeric,
           round(redes.f_num(cf.atributos -> 'C_RASANTE') - redes.f_num(cf.atributos -> 'C_FONDO'), 3), null::numeric,
           redes.f_estado_alcantarillado(cf.atributos ->> 'ESTADO'), 'emdupar'::text, null::text, cf.atributos ->> 'LABEL',
           jsonb_strip_nulls(jsonb_build_object('estado_pozo', redes.f_sin_dato(cf.atributos ->> 'EST_POZO'), 'estado_tapa', redes.f_sin_dato(cf.atributos ->> 'EST_TAPA'),
             'estado_canuela', redes.f_sin_dato(cf.atributos ->> 'ESTADO_CAn'), 'estado_operativo', redes.f_sin_dato(cf.atributos ->> 'EST_OPERA'), 'estado_capa', cf.atributos ->> 'ESTADO',
             'cota_rasante', redes.f_num(cf.atributos -> 'C_RASANTE'), 'cota_fondo', redes.f_num(cf.atributos -> 'C_FONDO'),
             'modelo', cf.atributos - array['LABEL', 'EST_POZO', 'EST_TAPA', 'ESTADO_CAn', 'EST_OPERA', 'ESTADO', 'C_RASANTE', 'C_FONDO', 'X', 'Y'])),
           null::integer,
           redes.f_norm(cf.atributos ->> 'EST_POZO') is distinct from 'virtual', true, 'alcantarillado'::text, cf.atributos ->> 'LABEL',
           case when redes.f_norm(cf.atributos ->> 'EST_POZO') = 'virtual' then 'pozo_virtual' else 'activo' end, 0::numeric,
           null::text, null::text, null::integer
      from redes.carga_filas cf where cf.carga_id = p_carga and cf.error is null;

  elsif v_capa = 'alc_descargas' then
    return query
    select 'alc_descargas'::text, cf.llave, cf.orden, 'VER'::text, cf.geom, null::text, null::text, null::text, null::text, null::text,
           null::numeric, null::numeric, round(redes.f_num(cf.atributos -> 'C_RASANTE') - redes.f_num(cf.atributos -> 'C_FONDO'), 3), null::numeric,
           'en_operacion'::text, 'emdupar'::text, null::text, cf.atributos ->> 'LABEL',
           jsonb_strip_nulls(jsonb_build_object('cota_rasante', redes.f_num(cf.atributos -> 'C_RASANTE'), 'cota_fondo', redes.f_num(cf.atributos -> 'C_FONDO'),
             'caudal', redes.f_num(cf.atributos -> 'CAUDAL'), 'modelo', cf.atributos - array['LABEL', 'C_RASANTE', 'C_FONDO', 'CAUDAL', 'X', 'Y'])),
           null::integer, true, true, 'alcantarillado'::text, cf.atributos ->> 'LABEL', 'activo'::text, 0::numeric,
           null::text, null::text, null::integer
      from redes.carga_filas cf where cf.carga_id = p_carga and cf.error is null;
  elsif v_capa <> 'muestreo' and (select x.prefijo from redes.capas x where x.codigo = v_capa) is not null then
    -- Corte 5c: lector GENÉRICO de las capas de un solo tipo (acometidas y las del Cargue de capas). Columnas que reconoce, sin importar mayúsculas:
    -- NOMBRE, CLASE (si existe para el tipo), MATERIAL, DIAMETRO o DIAMETRO_MM (mm), ESTADO, PROFUNDIDAD o PROFUNDIDAD_M (m), CAPACIDAD y CODIGO_ANTERIOR.
    -- Lo demás va a atributos.modelo. Lo que no cabe en la ficha (clase que no existe, número fuera de rango) se guarda en atributos y no se inventa.
    return query
    with f as (select cf.orden, cf.llave, cf.geom, cf.atributos as crudo,
                      coalesce((select jsonb_object_agg(lower(e.key), e.value) from jsonb_each(cf.atributos) e), '{}'::jsonb) as a
                 from redes.carga_filas cf where cf.carga_id = p_carga and cf.error is null),
         t as (select x.prefijo from redes.capas x where x.codigo = v_capa),
         g as (select f.*, t.prefijo,
                      (select c.codigo from redes.clases_activo c where c.prefijo = t.prefijo and c.activo
                          and (c.codigo = redes.f_norm(f.a ->> 'clase') or redes.f_norm(c.nombre) = redes.f_norm(f.a ->> 'clase'))) as clase_ok,
                      redes.f_num(coalesce(f.a -> 'diametro_mm', f.a -> 'diametro')) as dia,
                      redes.f_num(coalesce(f.a -> 'profundidad_m', f.a -> 'profundidad')) as prof,
                      redes.f_num(f.a -> 'capacidad') as cap
                 from f cross join t)
    select v_capa, g.llave, g.orden, g.prefijo, g.geom,
           left(nullif(btrim(g.a ->> 'nombre'), ''), 120), g.clase_ok, null::text,
           (select e.material_codigo from redes.material_equivalencias e where e.texto_norm = redes.f_norm(g.a ->> 'material')),
           nullif(btrim(g.a ->> 'material'), ''),
           case when g.dia between 0 and 5000 then g.dia end,
           case when ST_Dimension(g.geom) = 1 then round(ST_Length(g.geom::geography)::numeric, 2) end,
           case when g.prof >= 0 then g.prof end, case when g.cap >= 0 then g.cap end,
           coalesce((select s.codigo from redes.estados_activo s where s.codigo = redes.f_norm(g.a ->> 'estado') or redes.f_norm(s.nombre) = redes.f_norm(g.a ->> 'estado')),
                    case when nullif(btrim(g.a ->> 'estado'), '') is null then 'en_operacion' else redes.f_estado_alcantarillado(g.a ->> 'estado') end),      -- «Existente», «Proyectado»…
           'emdupar'::text, null::text, left(coalesce(nullif(btrim(g.a ->> 'codigo_anterior'), ''), g.llave), 120),
           jsonb_strip_nulls(jsonb_build_object(
             'estado_capa', g.a ->> 'estado',
             'clase_capa', case when g.clase_ok is null then nullif(btrim(g.a ->> 'clase'), '') end,
             'diametro_capa', case when g.dia is not null and not (g.dia between 0 and 5000) then g.dia end,
             'modelo', nullif((select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) from jsonb_each(g.crudo) e
                                where lower(e.key) not in ('nombre', 'clase', 'material', 'diametro', 'diametro_mm', 'estado', 'profundidad', 'profundidad_m', 'capacidad', 'codigo_anterior')),
                             '{}'::jsonb))),
           null::integer, true, false, null::text, null::text, null::text, null::numeric, null::text, null::text, null::integer
      from g;
  else
    perform tecnica.f_error(format('La capa %s no tiene lector en el motor', v_capa));
  end if;
end $function$;

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
  -- Corte 5c (D-4): una carga «sin columna llave» se cruza por GEOMETRÍA con lo vigente de la misma capa y el mismo tipo (redes.f_cruzar_por_geometria):
  -- lo cruzado toma la llave del vigente y lo demás queda «nuevo», con una llave propia. Después sigue el cruce por llave de siempre.
  if (select x.columna_llave from redes.cargas x where x.id = p_carga) = '(geometria)' then perform redes.f_cruzar_por_geometria(p_carga); end if;
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

-- redes.f_fusionar_ficha()
CREATE OR REPLACE FUNCTION redes.f_fusionar_ficha()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
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
           where x ->> 'campo' not in ('alias', 'placa')
             -- Corte 5c (§31.1): un campo «devuelto a la capa» deja de ser de la ficha, hasta que alguien lo vuelva a editar en la ficha
             and not exists (select 1 from redes.ficha_campo_devoluciones d where d.activo_id = e.activo_id and d.campo = x ->> 'campo' and d.creado_en > e.creado_en)
           group by e.activo_id) f
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
  -- Corte 5c: también es «igual» lo que trae los mismos valores escritos de otra forma (130 y 130.0, según el programa que exportó el archivo):
  -- la misma geometría (binaria) y los mismos campos por valor (igualdad de jsonb). Así una recarga desde la pantalla no crea versiones sin cambios.
  alter table _cand add column mismo_valor boolean not null default false;
  update _cand k set mismo_valor = true
    from redes.v_activo_vigente v
   where v.activo_id = k.activo_id and k.accion in ('cambiado', 'igual', 'reactivar') and k.huella is distinct from k.huella_vigente
     and ST_AsEWKB(v.geom) = ST_AsEWKB(k.geom)
     and jsonb_build_object('p', v.prefijo, 'n', v.nombre, 'c', v.clase, 'e', v.efecto, 'm', v.material_codigo, 'd', v.diametro_mm, 'l', v.longitud_m, 'pr', v.profundidad_m,
                            'ca', v.capacidad, 's', v.estado_codigo, 'ant', v.codigo_anterior, 'a', v.atributos)
       = jsonb_build_object('p', k.prefijo, 'n', k.nombre, 'c', k.clase, 'e', k.efecto, 'm', k.material_codigo, 'd', k.diametro_mm, 'l', k.longitud_m, 'pr', k.profundidad_m,
                            'ca', k.capacidad, 's', k.estado_codigo, 'ant', k.codigo_anterior, 'a', k.atributos);
  update _cand k set accion = case when k.huella_vigente = k.huella or k.mismo_valor then case when k.retirado_vigente then 'reactivar' else 'igual' end else 'cambiado' end
   where k.accion in ('cambiado', 'igual', 'reactivar');
  select count(*) into n from _choques;
  return n;
end $function$;

-- redes.f_iniciar(text,text,text,integer,text,integer,text,text)
CREATE OR REPLACE FUNCTION redes.f_iniciar(p_capa text, p_sha256 text, p_formato text, p_srid integer, p_columna_llave text, p_filas integer, p_nota text, p_autor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare v_capa redes.capas%rowtype; v_c redes.v_cargas_estado%rowtype; v_id bigint;
begin
  select * into v_capa from redes.capas where codigo = p_capa;
  if not found then perform tecnica.f_error(format('No existe la capa %s', p_capa)); end if;
  if v_capa.fuente <> 'carga' or not v_capa.activa then perform tecnica.f_error(format('La capa %s no se carga por archivo', p_capa)); end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then perform tecnica.f_error('Falta la huella sha256 del archivo'); end if;
  if p_filas is null or p_filas < 1 or p_filas > redes.f_param('carga_max_filas') then
    perform tecnica.f_error(format('Una carga admite de 1 a %s filas', redes.f_param('carga_max_filas')::integer));
  end if;
  perform pg_advisory_xact_lock(hashtext('redes.carga.' || p_capa));
  select * into v_c from redes.v_cargas_estado where capa_codigo = p_capa and sha256 = p_sha256 and estado in ('abierta', 'publicada') order by id desc limit 1;
  if found then
    if v_c.estado = 'publicada' then perform tecnica.f_error(format('Este archivo ya se publicó en la carga %s de la capa %s', v_c.id, p_capa)); end if;
    if v_c.filas_esperadas <> p_filas or v_c.columna_llave <> p_columna_llave or v_c.srid_origen <> p_srid then
      perform tecnica.f_error(format('La carga abierta %s de este archivo tiene otros datos (filas, llave o sistema): anúlela antes', v_c.id));
    end if;
    return jsonb_build_object('carga_id', v_c.id, 'nueva', false, 'recibidas', (select count(*) from redes.carga_filas where carga_id = v_c.id));
  end if;
  if exists (select 1 from redes.v_cargas_estado where capa_codigo = p_capa and estado = 'abierta') then
    perform tecnica.f_error(format('Hay otra carga abierta de la capa %s (la %s): publíquela o anúlela antes', p_capa,
      (select id from redes.v_cargas_estado where capa_codigo = p_capa and estado = 'abierta' order by id desc limit 1)));
  end if;
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor, masiva_id)
  values (p_capa, p_sha256, p_formato, p_srid, btrim(p_columna_llave), p_filas, nullif(btrim(coalesce(p_nota, '')), ''), p_autor,
          nullif(current_setting('redes.masiva_id', true), '')::uuid)      -- Corte 5c: la pone geoportal_redes_cargue_iniciar en una carga masiva
  returning id into v_id;
  return jsonb_build_object('carga_id', v_id, 'nueva', true, 'recibidas', 0);
end $function$;

-- public.geoportal_tec_punto_ubicacion_revisar(text,bigint,text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_tec_punto_ubicacion_revisar(p_solicitante text, p_propuesta_id bigint, p_decision text, p_motivo text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'redes', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text := tecnica.f_autorizar_supervision(p_solicitante); x record; p tecnica.puntos%rowtype; u record;
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), ''); v_ubic bigint; v_rev bigint;
begin
  if p_decision is null or p_decision not in ('aprobar', 'rechazar') then perform tecnica.f_error('Diga si aprueba o rechaza la ubicación'); end if;
  if p_decision = 'rechazar' and (v_mot is null or length(v_mot) < 10) then perform tecnica.f_error('Escriba el motivo del rechazo (10 caracteres o más)'); end if;
  if v_mot is not null and (length(v_mot) < 10 or length(v_mot) > 1000) then perform tecnica.f_error('El motivo, si lo escribe, va de 10 a 1.000 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('tecnica.puntos'));          -- el mismo candado que la publicación de la capa MUE (Corte 5a)
  select * into x from tecnica.v_punto_propuestas where id = p_propuesta_id;
  if not found then perform tecnica.f_error('No existe esa ubicación propuesta', 'P0002'); end if;
  if x.estado <> 'pendiente' then perform tecnica.f_error(format('Esta ubicación ya fue %s por %s', x.estado, x.revisor), '55000'); end if;
  if x.autor = v_email and not public.geoportal_es_admin(v_email) then perform tecnica.f_error(      -- Corte 5c (§32.1): el administrador sí puede
                                                                      'No puede revisar una ubicación que usted mismo tomó: pídaselo a otro supervisor o al administrador'); end if;
  select * into p from tecnica.puntos where id = x.punto_id;
  if p_decision = 'aprobar' then
    if not p.activo then perform tecnica.f_error('El punto está desactivado: no se puede aprobar su ubicación (puede rechazarla)'); end if;
    select * into u from redes.v_punto_ubicacion_vigente where punto_id = p.id;
    insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, barrio_capa, carga_id, autor)
    values (p.id, x.lat, x.lon, 'verificada', 'gps_operador', u.barrio_capa, null, x.autor) returning id into v_ubic;
  end if;
  insert into tecnica.punto_ubicacion_revisiones (propuesta_id, decision, motivo, ubicacion_id, autor)
  values (x.id, p_decision, v_mot, v_ubic, v_email) returning id into v_rev;
  perform tecnica.f_auditar(v_email, 'tec_punto_ubicacion_' || p_decision, p.codigo, jsonb_build_object('propuesta_id', x.id, 'propuso', x.autor, 'motivo', v_mot, 'ubicacion_id', v_ubic), p_ip);
  return jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'decision', p_decision, 'estado', case when p_decision = 'aprobar' then 'aprobada' else 'rechazada' end,
                            'ubicacion_id', v_ubic, 'revision_id', v_rev);
end $function$;

-- public.geoportal_tec_punto_ubicaciones(text)
CREATE OR REPLACE FUNCTION public.geoportal_tec_punto_ubicaciones(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_aviso numeric := redes.f_param('mue_gps_distancia_aviso_m');
        v_admin boolean := public.geoportal_es_admin(v_email);      -- Corte 5c (§32.1)
begin
  return jsonb_build_object(
    'precision_max_m', redes.f_param('mue_gps_precision_max_m'), 'distancia_aviso_m', v_aviso, 'soy_admin', v_admin,
    'pendientes', coalesce((
      select jsonb_agg(jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'activo', p.activo,
               'lat', x.lat, 'lon', x.lon, 'precision_m', x.precision_m, 'autor', x.autor, 'autor_nombre', lb.nombre, 'creado_en', x.creado_en, 'propia', x.autor = v_email, 'puede_revisar', x.autor <> v_email or v_admin,
               'vigente', case when u.punto_id is not null then jsonb_build_object('lat', u.lat, 'lon', u.lon, 'exactitud', u.exactitud, 'fuente', u.fuente) end,
               'distancia_m', d.m, 'lejos', coalesce(d.m > v_aviso, false)) order by x.id)
        from tecnica.v_punto_propuestas x join tecnica.puntos p on p.id = x.punto_id
        left join redes.v_punto_ubicacion_vigente u on u.punto_id = x.punto_id
        left join public.geoportal_lista_blanca lb on lb.email = x.autor
        cross join lateral (select round(ST_Distance(x.geom::geography, u.geom::geography)::numeric) as m) d
       where x.estado = 'pendiente'), '[]'::jsonb),
    'puntos', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'lat', u.lat, 'lon', u.lon, 'exactitud', u.exactitud, 'fuente', u.fuente,
               'desde', u.creado_en, 'en_revision', exists (select 1 from tecnica.v_punto_propuestas x where x.punto_id = p.id and x.estado = 'pendiente')) order by p.codigo)
        from tecnica.puntos p left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
       where p.tipo = 'muestreo' and p.activo), '[]'::jsonb),
    'revisadas', coalesce((
      select jsonb_agg(r order by (r ->> 'revisada_en') desc) from (
        select jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'nombre', p.nombre, 'decision', x.estado, 'motivo', x.revision_motivo,
                                  'autor', x.autor, 'revisor', x.revisor, 'revisada_en', x.revisada_en, 'precision_m', x.precision_m) as r
          from tecnica.v_punto_propuestas x join tecnica.puntos p on p.id = x.punto_id
         where x.estado <> 'pendiente' order by x.revisada_en desc limit 50) z), '[]'::jsonb),
    -- Corte 5c (§32.2): las últimas correcciones de una ubicación verificada, con su motivo
    'correcciones', coalesce((
      select jsonb_agg(r order by (r ->> 'id')::bigint desc) from (
        select jsonb_build_object('id', c.id, 'punto', p.codigo, 'nombre', p.nombre, 'metodo', c.metodo, 'distancia_m', c.distancia_m, 'motivo', c.motivo,
                                  'autor', c.autor, 'creado_en', c.creado_en) as r
          from tecnica.punto_ubicacion_correcciones c join tecnica.puntos p on p.id = c.punto_id order by c.id desc limit 50) z), '[]'::jsonb));
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 26 — FUNCIÓN INTERNA Y RPC NUEVAS
-- PROPUESTA. No se ha ejecutado en la base real. security definer, search_path fijo, mensajes con HINT msg_usuario (tecnica.f_error); solo service_role.
-- Redes (las llama la Edge geoportal-redes, rutas nuevas «cargue_*»):
--   · geoportal_redes_cargue_capas: las capas del Cargue con su estado, versión, última carga y carga abierta (supervisor de distribución y administrador);
--   · geoportal_redes_cargue_historial: las cargas de una capa con sus eventos (supervisor y administrador);
--   · geoportal_redes_cargue_iniciar: abre una carga desde la pantalla (administrador), con las reglas de la llave, el sistema y la carga masiva;
--   · geoportal_redes_carga_muestra: vista previa de una carga abierta (caja, errores y una muestra de geometrías) para confirmar que cae en Valledupar;
--   · geoportal_redes_carga_devolver_campo: «Devolver este campo a la capa» desde la lista de choques (§31.1), con motivo.
--   Los lotes, el resumen, publicar, revertir y anular siguen siendo las RPC del 1a (geoportal_redes_carga_*), sin cambios.
-- Planta (las llama la Edge geoportal-tecnica, ruta nueva «ubicacion_corregir»):
--   · geoportal_tec_punto_ubicacion_corregir: corregir una ubicación verificada, con motivo (§32.2).
-- Nada se actualiza ni se borra: todo es inserción con autor y hora.
-- =====================================================================

-- D-4: cruce por GEOMETRÍA de una carga sin columna llave, sobre la tabla temporal _cand que arma redes.f_preparar_candidatos.
-- Con lo vigente (también lo retirado, que así se reactiva) de la MISMA capa y el MISMO tipo, tomado de redes.activo_vigente_mat (con índice espacial):
-- puntos a menos de cruce_geometria_tol_m metros; líneas y polígonos con la distancia de Hausdorff (en metros, MAGNA-SIRGAS Bogotá 3116) por debajo de la
-- misma tolerancia. Uno a uno, por rondas: en cada ronda se casan los pares en que cada uno es el más cercano del otro entre los que siguen libres (así dos
-- elementos en el mismo sitio se reparten). Lo cruzado toma la llave del vigente; lo demás, una llave propia «G<carga>-<orden>» (nuevo).
create function redes.f_cruzar_por_geometria(p_carga bigint)
returns integer language plpgsql set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
declare v_tol numeric := redes.f_param('cruce_geometria_tol_m'); v_capa text := (select capa_codigo from redes.cargas where id = p_carga);
        v_grados double precision := redes.f_param('cruce_geometria_tol_m') / 100000.0 * 1.5;      -- prefiltro en grados, holgado (1° ≈ 109 km en Valledupar)
        n integer := 0; k integer; v_ronda integer := 0;
begin
  if to_regclass('pg_temp._geo_vig') is not null then drop table pg_temp._geo_vig; end if;
  create temp table _geo_vig on commit drop as
  select m.llave_capa, m.prefijo, m.geom from redes.activo_vigente_mat m
   where m.capa_codigo = v_capa and m.llave_capa is not null and m.prefijo in (select distinct prefijo from _cand where crea_activo);
  create index on _geo_vig using gist (geom);
  analyze _geo_vig;
  if to_regclass('pg_temp._geo_par') is not null then drop table pg_temp._geo_par; end if;
  create temp table _geo_par on commit drop as
  select x.orden, x.llave_capa, x.m from (
    select k.orden, v.llave_capa,
           case when GeometryType(k.geom) = 'POINT' then ST_Distance(k.geom::geography, v.geom::geography)
                else ST_HausdorffDistance(ST_Transform(k.geom, 3116), ST_Transform(v.geom, 3116)) end as m
      from _cand k join _geo_vig v on v.prefijo = k.prefijo and ST_DWithin(k.geom, v.geom, v_grados)
     where k.crea_activo and k.geom is not null) x
   where x.m <= v_tol;
  create index on _geo_par (orden); create index on _geo_par (llave_capa);
  loop
    v_ronda := v_ronda + 1;
    with r as (select orden, llave_capa, row_number() over (partition by orden order by m, llave_capa) as rc,
                      row_number() over (partition by llave_capa order by m, orden) as rv from _geo_par),
         casados as (update _cand k set llave = r.llave_capa from r where r.orden = k.orden and r.rc = 1 and r.rv = 1 and k.crea_activo returning k.orden, k.llave)
    select count(*) into k from casados;
    exit when k = 0 or v_ronda > 50;
    n := n + k;
    delete from _geo_par g using _cand c where c.crea_activo and c.llave is not null and c.orden = g.orden;
    delete from _geo_par g using _cand c where c.crea_activo and c.llave is not null and c.llave = g.llave_capa;
  end loop;
  update _cand set llave = 'G' || p_carga || '-' || orden where crea_activo and llave is null;
  return n;
end $f$;

-- Las capas del Cargue de capas. Lectura del supervisor de distribución y del administrador (puede_cargar solo el administrador).
-- estado: al_dia, desactualizada (si la capa tiene periodicidad), sin_cargar, derivada (sale de otra capa) u otro_modulo.
create function public.geoportal_redes_cargue_capas(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare v record;
begin
  select * into v from redes.f_perfil_lectura(p_solicitante);
  if v.perfil not in ('admin', 'supervisor') then perform tecnica.f_error('Solo el supervisor de distribución o el administrador ven el Cargue de capas', '42501'); end if;
  return jsonb_build_object(
    'puede_cargar', v.perfil = 'admin',
    'max_filas', redes.f_param('carga_max_filas'), 'lote_max_filas', redes.f_param('lote_max_filas'), 'tolerancia_geometria_m', redes.f_param('cruce_geometria_tol_m'),
    'caja', jsonb_build_array(redes.f_param('caja_lon_min'), redes.f_param('caja_lat_min'), redes.f_param('caja_lon_max'), redes.f_param('caja_lat_max')),
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'codigo', c.codigo, 'nombre', c.nombre, 'grupo', c.grupo, 'sistema', c.sistema, 'geometria', c.geometria, 'prefijo', c.prefijo, 'fuente', c.fuente,
               'derivada_de', c.derivada_de, 'columna_llave', c.columna_llave, 'formatos', to_jsonb(c.formatos),
               'lector', case when c.codigo = 'muestreo' then 'muestreo' when c.codigo in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas') then 'modelo'
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
                      else (select count(*) from redes.activo_vigente_mat m where m.capa_codigo = c.codigo and not m.retirado) end as vigentes
        ) x
       where c.activa), '[]'::jsonb));
end $f$;

-- Historial de una capa: sus cargas (la más reciente primero, hasta 30) con sus eventos (publicar, revertir, anular) y lo que cambió.
create function public.geoportal_redes_cargue_historial(p_solicitante text, p_capa text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare v record;
begin
  select * into v from redes.f_perfil_lectura(p_solicitante);
  if v.perfil not in ('admin', 'supervisor') then perform tecnica.f_error('Solo el supervisor de distribución o el administrador ven el Cargue de capas', '42501'); end if;
  if not exists (select 1 from redes.capas where codigo = p_capa) then perform tecnica.f_error('No existe esa capa', 'P0002'); end if;
  return jsonb_build_object('capa', p_capa, 'cargas', coalesce((
    select jsonb_agg(z.j order by z.id desc) from (
      select e.id, jsonb_build_object('carga_id', e.id, 'estado', e.estado, 'formato', e.formato, 'srid', e.srid_origen, 'columna_llave', e.columna_llave, 'filas', e.filas_esperadas,
               'nota', e.nota, 'autor', e.autor, 'creado_en', e.creado_en, 'masiva', e.masiva_id is not null,
               'eventos', coalesce((select jsonb_agg(jsonb_build_object('tipo', ev.tipo, 'version_capa', ev.version_capa, 'nuevos', ev.nuevos, 'cambiados', ev.cambiados,
                                                                       'iguales', ev.iguales, 'retirados', ev.retirados, 'reactivados', ev.reactivados, 'motivo', ev.motivo,
                                                                       'autor', ev.autor, 'creado_en', ev.creado_en) order by ev.id)
                                      from redes.carga_eventos ev where ev.carga_id = e.id), '[]'::jsonb)) as j
        from redes.v_cargas_estado e where e.capa_codigo = p_capa order by e.id desc limit 30) z), '[]'::jsonb));
end $f$;

-- Abrir una carga desde la pantalla (solo el administrador). Además de lo que revisa redes.f_iniciar:
--   · el sistema de coordenadas es uno de los de Colombia que se aceptan (WGS 84, MAGNA geográficas y planas, Origen Nacional);
--   · las capas con llave fija (las del modelo: acueducto ID; conductos, pozos y descargas LABEL; muestreo codigo) solo se cargan con esa llave;
--   · «(geometria)» (sin columna llave, D-4) solo en las capas del lector genérico;
--   · en una carga masiva, todas las cargas del mismo archivo llevan el mismo identificador (masiva_id).
create function public.geoportal_redes_cargue_iniciar(p_solicitante text, p_capa text, p_sha256 text, p_formato text, p_srid integer, p_columna_llave text,
                                                      p_filas integer, p_nota text default null, p_masiva text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
declare v_email text := redes.f_autorizar_admin(p_solicitante); c redes.capas%rowtype; r jsonb; v_llave text := btrim(coalesce(p_columna_llave, ''));
begin
  select * into c from redes.capas where codigo = p_capa;
  if not found then perform tecnica.f_error('No existe esa capa', 'P0002'); end if;
  if p_srid is null or p_srid not in (4326, 4686, 3114, 3115, 3116, 3117, 3118, 9377) then
    perform tecnica.f_error('El sistema de coordenadas no es uno de los que se aceptan (WGS 84, MAGNA-SIRGAS geográficas, sus zonas planas o el Origen Nacional 9377)');
  end if;
  if p_formato is null or p_formato not in ('shp', 'gpkg', 'geojson', 'kml', 'csv', 'xlsx') then perform tecnica.f_error('Ese formato de archivo no se acepta'); end if;
  if not (p_formato = any (c.formatos)) and not (p_formato = 'xlsx' and 'csv' = any (c.formatos)) then
    perform tecnica.f_error(format('La capa %s no se carga con %s (acepta: %s)', c.nombre, p_formato, array_to_string(c.formatos, ', ')));
  end if;
  if v_llave = '' or length(v_llave) > 64 then perform tecnica.f_error('Elija la columna llave'); end if;
  if c.columna_llave is not null and v_llave <> c.columna_llave then
    perform tecnica.f_error(format('La capa %s se carga siempre con la columna llave %s (N-5)', c.nombre, c.columna_llave));
  end if;
  if v_llave = '(geometria)' and not (c.fuente = 'carga' and c.prefijo is not null and c.columna_llave is null) then
    perform tecnica.f_error('Esta capa no se puede cargar sin columna llave');
  end if;
  if p_masiva is not null then
    if p_masiva !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then perform tecnica.f_error('El identificador de la carga masiva no es válido'); end if;
    perform set_config('redes.masiva_id', p_masiva, true);
  end if;
  r := redes.f_iniciar(p_capa, lower(p_sha256), p_formato, p_srid, v_llave, p_filas, p_nota, v_email);
  perform set_config('redes.masiva_id', '', true);
  if (r ->> 'nueva')::boolean then
    perform tecnica.f_auditar(v_email, 'redes_carga_iniciar', r ->> 'carga_id', jsonb_build_object('capa', p_capa, 'filas', p_filas, 'formato', p_formato, 'srid', p_srid,
                                                                                                  'columna_llave', v_llave, 'masiva', p_masiva, 'desde', 'pantalla'), null);
  end if;
  return r;
end $f$;

-- Vista previa de una carga ABIERTA (solo el administrador): la caja de lo que llegó, las filas con error (fuera de Valledupar, sin geometría…) y una muestra
-- de hasta 400 geometrías, repartida en todo el archivo y simplificada, para dibujarla sobre el mapa antes de publicar.
create function public.geoportal_redes_carga_muestra(p_solicitante text, p_carga bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
declare v_email text := redes.f_autorizar_admin(p_solicitante); c redes.v_cargas_estado%rowtype; v_n integer; v_paso integer; v_caja jsonb;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga', 'P0002'); end if;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: ya no tiene vista previa', p_carga, c.estado), '55000'); end if;
  select count(*) into v_n from redes.carga_filas where carga_id = p_carga and geom is not null;
  v_paso := greatest(1, ceil(v_n / 400.0)::integer);
  select jsonb_build_array(round(ST_XMin(e)::numeric, 6), round(ST_YMin(e)::numeric, 6), round(ST_XMax(e)::numeric, 6), round(ST_YMax(e)::numeric, 6)) into v_caja
    from (select ST_Extent(geom)::geometry as e from redes.carga_filas where carga_id = p_carga and geom is not null) x where e is not null;
  return jsonb_build_object('carga_id', p_carga, 'capa', c.capa_codigo, 'esperadas', c.filas_esperadas,
    'recibidas', (select count(*) from redes.carga_filas where carga_id = p_carga), 'con_geometria', v_n,
    'con_error', (select count(*) from redes.carga_filas where carga_id = p_carga and error is not null),
    'errores', coalesce((select jsonb_agg(jsonb_build_object('orden', orden, 'llave', llave, 'error', error) order by orden)
                           from (select orden, llave, error from redes.carga_filas where carga_id = p_carga and error is not null order by orden limit 20) z), '[]'::jsonb),
    'caja', v_caja,
    'muestra', jsonb_build_object('type', 'FeatureCollection', 'features', coalesce((
      select jsonb_agg(jsonb_build_object('type', 'Feature', 'geometry', ST_AsGeoJSON(ST_SimplifyPreserveTopology(z.geom, 0.000005), 6)::jsonb,
                                          'properties', jsonb_build_object('orden', z.orden, 'llave', z.llave)) order by z.orden)
        from (select f.orden, f.llave, f.geom, row_number() over (order by f.orden) as rn from redes.carga_filas f where f.carga_id = p_carga and f.geom is not null) z
       where (z.rn - 1) % v_paso = 0), '[]'::jsonb)));
end $f$;

-- «Devolver este campo a la capa» (§31.1), desde la lista de choques del resumen de una carga ABIERTA (solo el administrador, con motivo).
-- El campo deja de ser «de la ficha»: en esta carga (al volver a pedir el resumen) y en las siguientes, lo manda la capa, hasta que alguien lo vuelva a
-- editar en la ficha. La ficha no cambia ahora: cambia al publicar. El valor que tenía la ficha queda en el historial.
create function public.geoportal_redes_carga_devolver_campo(p_solicitante text, p_carga bigint, p_codigo text, p_campo text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare v_email text := redes.f_autorizar_admin(p_solicitante); c redes.v_cargas_estado%rowtype; v redes.v_activo_vigente%rowtype; v_campo text := btrim(coalesce(p_campo, ''));
        v_mot text := btrim(coalesce(p_motivo, '')); v_ficha text; v_id bigint;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres): por ejemplo, «Técnica corrigió el modelo»'); end if;
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga', 'P0002'); end if;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: el campo se devuelve desde una carga abierta', p_carga, c.estado), '55000'); end if;
  if c.capa_codigo = 'muestreo' then perform tecnica.f_error('Los puntos de muestreo no tienen ficha de activo'); end if;
  select * into v from redes.v_activo_vigente where codigo = upper(btrim(coalesce(p_codigo, '')));
  if not found then perform tecnica.f_error('No existe ese activo', 'P0002'); end if;
  if not coalesce(v.capa_codigo = any (redes.f_capas_cubiertas(c.capa_codigo)), false) then
    perform tecnica.f_error(format('El activo %s no es de la capa de esta carga', v.codigo));
  end if;
  perform pg_advisory_xact_lock(hashtext('redes.carga.' || c.capa_codigo));
  if not exists (select 1 from redes.ficha_ediciones e cross join jsonb_array_elements(e.cambios) x
                  where e.activo_id = v.activo_id and x ->> 'campo' = v_campo
                    and not exists (select 1 from redes.ficha_campo_devoluciones d where d.activo_id = e.activo_id and d.campo = v_campo and d.creado_en > e.creado_en)) then
    perform tecnica.f_error(format('El campo %s de %s no está editado en la ficha: ya lo manda la capa', v_campo, v.codigo), '55000');
  end if;
  v_ficha := case when v_campo like 'atributos.%' then v.atributos ->> substr(v_campo, 11)
                  when v_campo = 'origen' then (select coalesce(o.origen, '') || coalesce(' · ' || o.aportante_codigo, '') from redes.v_activo_origen_vigente o where o.activo_id = v.activo_id)
                  else to_jsonb(v) ->> v_campo end;
  insert into redes.ficha_campo_devoluciones (activo_id, campo, carga_id, valor_ficha, motivo, autor)
  values (v.activo_id, v_campo, p_carga, left(v_ficha, 500), v_mot, v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'redes_ficha_campo_devolver', v.codigo, jsonb_build_object('campo', v_campo, 'carga_id', p_carga, 'valor_ficha', left(v_ficha, 500), 'motivo', v_mot), null);
  return jsonb_build_object('devolucion_id', v_id, 'carga_id', p_carga, 'codigo', v.codigo, 'campo', v_campo, 'valor_ficha', v_ficha);
end $f$;

-- Corregir una ubicación VERIFICADA de un punto de muestreo (§32.2), desde «Puntos» del Dashboard PTAP (supervisor de planta o administrador), con motivo.
-- La ubicación nueva se AGREGA (verificada, fuente «correccion») y la anterior queda en el historial. Reglas:
--   · el punto existe, es de muestreo, está activo y su ubicación vigente está verificada (la aproximada se cambia desde Muestreo o con una carga);
--   · no tiene una ubicación propuesta en revisión (primero se aprueba o se rechaza);
--   · cae en la caja de Valledupar y queda a 1 m o más de la de ahora; con el GPS, la precisión es de mue_gps_precision_max_m o menos.
create function public.geoportal_tec_punto_ubicacion_corregir(p_solicitante text, p_punto text, p_lat numeric, p_lon numeric, p_metodo text, p_precision_m numeric,
                                                              p_motivo text, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_supervision(p_solicitante); p tecnica.puntos%rowtype; u record; v_mot text := btrim(coalesce(p_motivo, ''));
  v_lat numeric := round(p_lat, 6); v_lon numeric := round(p_lon, 6); v_dist numeric; v_ubic bigint; v_cor bigint;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo de la corrección (10 a 1.000 caracteres)'); end if;
  if p_metodo is null or p_metodo not in ('mapa', 'coordenadas', 'gps') then perform tecnica.f_error('Diga cómo tomó la ubicación nueva (mapa, coordenadas o GPS)'); end if;
  if p_lat is null or p_lon is null then perform tecnica.f_error('Falta la ubicación nueva'); end if;
  if p_metodo = 'gps' then
    if p_precision_m is null or p_precision_m <= 0 or p_precision_m > 1000 then perform tecnica.f_error('La precisión del GPS no es válida'); end if;
    if p_precision_m > redes.f_param('mue_gps_precision_max_m') then
      perform tecnica.f_error(format('El GPS tiene una precisión de %s m y se necesita de %s m o menos', ceil(p_precision_m)::integer, redes.f_param('mue_gps_precision_max_m')::integer));
    end if;
  elsif p_precision_m is not null then perform tecnica.f_error('La precisión solo va con el GPS');
  end if;
  if v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
    perform tecnica.f_error('La ubicación nueva está fuera de Valledupar');
  end if;
  perform pg_advisory_xact_lock(hashtext('tecnica.puntos'));          -- el mismo candado que revisar y que la publicación de la capa MUE
  select * into p from tecnica.puntos where codigo = upper(btrim(coalesce(p_punto, ''))) and tipo = 'muestreo';
  if not found then perform tecnica.f_error('No existe ese punto de muestreo', 'P0002'); end if;
  if not p.activo then perform tecnica.f_error('Ese punto de muestreo está desactivado'); end if;
  select * into u from redes.v_punto_ubicacion_vigente where punto_id = p.id;
  if not found or u.exactitud <> 'verificada' then
    perform tecnica.f_error('Solo se corrige una ubicación verificada. La aproximada se cambia con «Guardar la ubicación de este punto» en Muestreo, o con una carga de la capa', '55000');
  end if;
  if exists (select 1 from tecnica.v_punto_propuestas x where x.punto_id = p.id and x.estado = 'pendiente') then
    perform tecnica.f_error('Este punto tiene una ubicación en revisión: apruébela o recházela antes de corregir', '55000');
  end if;
  v_dist := round(ST_Distance(ST_SetSRID(ST_MakePoint(v_lon::double precision, v_lat::double precision), 4326)::geography, u.geom::geography)::numeric, 1);
  if v_dist < 1 then perform tecnica.f_error('La ubicación nueva es la misma de ahora (menos de 1 m)'); end if;
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, barrio_capa, carga_id, autor)
  values (p.id, v_lat, v_lon, 'verificada', 'correccion', u.barrio_capa, null, v_email) returning id into v_ubic;
  insert into tecnica.punto_ubicacion_correcciones (punto_id, ubicacion_id, ubicacion_previa_id, metodo, precision_m, distancia_m, motivo, autor)
  values (p.id, v_ubic, u.id, p_metodo, case when p_metodo = 'gps' then round(p_precision_m, 1) end, v_dist, v_mot, v_email) returning id into v_cor;
  perform tecnica.f_auditar(v_email, 'tec_punto_ubicacion_corregir', p.codigo, jsonb_build_object('correccion_id', v_cor, 'ubicacion_id', v_ubic, 'previa_id', u.id, 'metodo', p_metodo,
                                                                                               'distancia_m', v_dist, 'motivo', v_mot), p_ip);
  return jsonb_build_object('punto', p.codigo, 'correccion_id', v_cor, 'ubicacion_id', v_ubic, 'lat', v_lat, 'lon', v_lon, 'distancia_m', v_dist);
end $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas nuevas: nadie de la API. Las 6 RPC nuevas: solo execute a service_role (las Edges geoportal-redes y geoportal-tecnica).
-- La función interna nueva (redes.f_cruzar_por_geometria) y las reemplazadas siguen sin permisos para la API (create or replace conserva los permisos).
-- =====================================================================
revoke all on table redes.ficha_campo_devoluciones, tecnica.punto_ubicacion_correcciones from public, anon, authenticated, service_role;
revoke all on sequence redes.ficha_campo_devoluciones_id_seq, tecnica.punto_ubicacion_correcciones_id_seq from public, anon, authenticated, service_role;
revoke all on function redes.f_cruzar_por_geometria(bigint) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_cargue_capas', 'geoportal_redes_cargue_historial', 'geoportal_redes_cargue_iniciar', 'geoportal_redes_carga_muestra',
                                'geoportal_redes_carga_devolver_campo', 'geoportal_tec_punto_ubicacion_corregir') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte5c', 'migracion_redes_corte5c', null, jsonb_build_object('tablas', jsonb_build_array('redes.ficha_campo_devoluciones', 'tecnica.punto_ubicacion_correcciones'),
        'rpc', jsonb_build_array('geoportal_redes_cargue_capas', 'geoportal_redes_cargue_historial', 'geoportal_redes_cargue_iniciar', 'geoportal_redes_carga_muestra',
                                 'geoportal_redes_carga_devolver_campo', 'geoportal_tec_punto_ubicacion_corregir'),
        'capas_nuevas', 11), null);
commit;
