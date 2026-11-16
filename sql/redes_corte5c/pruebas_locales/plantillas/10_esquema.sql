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
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_5B}}' then
    raise exception 'Las funciones de redes no son las del Corte 5b (o el Corte 5c ya está aplicado): deténgase y avise';
  end if;
  if (select count(*) from (values {{PLANTA_5B}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2 then
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
