-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 10 — GUARDIA, CAPA DE CONTRATOS, VISTAS COMPARTIDAS, RANGOS DE MUESTREO, CAPA DE REPORTES DE COMERCIAL Y PARÁMETROS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: §30.1, §30.2 y §30.4 de la bitácora; respuestas de David al 6a (16-nov 10:55); plan 02 (Corte 6) y 01 sección D.
-- · Presupone el 6a aplicado (huella del conjunto de funciones de redes). Se publica junto con el 6a, después de él.
-- · Lee (no escribe) lo vivo de Comercial: public.catastro_valledupar, public.cartera_suscripcion, bi_interno.ficha_contrato y su estado; y de planta:
--   tecnica.v_registros_estado, tecnica.variables y tecnica.f_referencia_vigente. Nada de eso cambia.
-- · ⚠ Se reemplazan 2 RPC del 6a (geoportal_redes_geovisor y geoportal_redes_geovisor_capa), con su texto exacto en la reversa.
-- · ⚠ redes.geovisor_capas (del 6a): se amplía el CHECK de «fuente» con «contratos» y se ponen al día 3 filas (contratos, reportes de Comercial y muestreo).
-- =====================================================================
do $$
begin
  if to_regclass('redes.geovisor_capas') is null then raise exception 'Falta el Corte 6a: aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '91a4d3e6e1c3539d8a447cb00a52d735' then
    raise exception 'Las funciones de redes no son las del Corte 6a (o el Corte 6b ya está aplicado): deténgase y avise';
  end if;
  if to_regclass('redes.contratos_capa') is not null or to_regclass('redes.vistas_compartidas') is not null then
    raise exception 'Las tablas del 6b ya existen: el Corte 6b parece aplicado';
  end if;
  -- lo vivo que se lee
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catastro_valledupar' and column_name in ('id', 'cod_usuario', 'direccion', 'barrio', 'geom')) <> 5
     or (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion'
          and column_name in ('contrato', 'estado', 'nombre', 'direccion', 'barrio', 'categoria', 'periodo_carga')) <> 7
     or (select count(*) from information_schema.columns where table_schema = 'bi_interno' and table_name = 'ficha_contrato'
          and column_name in ('contrato', 'periodo_ultimo', 'uso', 'consumo_meses', 'cons_prom', 'meses_con_lectura', 'medidor_anios')) <> 7
     or to_regclass('bi_interno.ficha_contrato_estado') is null then
    raise exception 'Las tablas de Comercial (catastro, cartera diaria o ficha del contrato) no tienen las columnas esperadas: deténgase y avise';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'tecnica' and table_name = 'v_registros_estado'
        and column_name in ('formulario', 'variable_id', 'punto_id', 'valor', 'muestra_ts', 'excluido')) <> 6
     or to_regprocedure('tecnica.f_referencia_vigente(bigint,bigint,bigint)') is null
     or (select count(*) from tecnica.variables where codigo in ('cloro_residual_libre', 'turbiedad', 'cloro_libre_tanque', 'turbiedad_salida')) <> 4 then
    raise exception 'Faltan las variables de Muestreo o de Salida, la vista de registros o el resolutor de referencias: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. CAPA DE CONTRATOS (§30.1; 01 sección D). Una fila por contrato con su punto (el predio de menor id, como contrato_tramo), uso, estado comercial,
--    consumo promedio y años del medidor. SIN nombre, teléfono, dirección ni deuda: esos van solo en la tarjeta, pedidos al tocar.
--    Es derivada: se rehace entera con redes.f_refrescar_contratos_capa() cuando cambia la ficha del contrato o tiene más de un día.
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- 2. VISTAS COMPARTIDAS (§30.2): el enlace guarda capas, colores, fechas, centro y zoom; nunca datos personales. Quien lo abre inicia sesión y ve solo
--    las capas para las que tiene permiso. Solo inserción.
-- ---------------------------------------------------------------------
create table redes.vistas_compartidas (
  id        text primary key check (id ~ '^[a-z0-9]{10}$'),
  capas     text[] not null check (cardinality(capas) between 0 and 40),
  colores   text not null check (colores in ('tipo', 'material', 'edad')),
  periodo   jsonb not null,
  lon       numeric(9, 6) not null,
  lat       numeric(9, 6) not null,
  zoom      numeric(4, 2) not null check (zoom between 10 and 20),
  atenuadas text[] not null default '{}',
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
comment on table redes.vistas_compartidas is 'Corte 6b (§30.2): vistas del geovisor compartidas por enlace. Sin datos personales. Solo inserción.';

-- ---------------------------------------------------------------------
-- 3. RANGOS DEL MUESTREO (respuesta 4 de David al 6a): el color del punto sale de la referencia de la variable de Muestreo si la tiene (por punto o general);
--    si no, de la referencia de la variable equivalente de Salida (Res. 2115 de 2007 y criterio de planta). Una fila por variable que colorea.
-- ---------------------------------------------------------------------
create table redes.muestreo_rangos (
  variable_muestreo text primary key,
  variable_salida   text not null,
  orden             integer not null
);
insert into redes.muestreo_rangos values ('cloro_residual_libre', 'cloro_libre_tanque', 1), ('turbiedad', 'turbiedad_salida', 2);
comment on table redes.muestreo_rangos is 'Corte 6b: qué variables colorean un punto de muestreo y de qué variable de Salida toman el rango cuando no tienen el suyo.';

do $$
begin
  execute 'create trigger t_solo_agregar before update or delete on redes.vistas_compartidas for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on redes.vistas_compartidas for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_no_borrar before delete on redes.muestreo_rangos for each row execute function tecnica.f_solo_agregar()';
  execute 'alter table redes.contratos_capa enable row level security';
  execute 'alter table redes.contratos_capa_estado enable row level security';
  execute 'alter table redes.vistas_compartidas enable row level security';
  execute 'alter table redes.muestreo_rangos enable row level security';
end $$;

-- ---------------------------------------------------------------------
-- 4. CAPA DE REPORTES DE COMERCIAL (§30.4), lista para que el Corte 8 la llene: la vista vacía con sus columnas. El Corte 8 la reemplaza (create or replace)
--    leyendo los reportes compartidos (anomalías y revisiones). con_contrato: azul si trae código de contrato, rojo si es un posible clandestino.
-- ---------------------------------------------------------------------
create view redes.v_reportes_comercial as
select null::text as codigo, null::text as tipo, null::text as subtipo, null::text as area, null::boolean as con_contrato, null::text as estado,
       null::timestamptz as registrado_en, null::numeric(9, 6) as lat, null::numeric(9, 6) as lon
 where false;
comment on view redes.v_reportes_comercial is 'Corte 6b: capa de reportes de Comercial del geovisor, vacía hasta el Corte 8. Sin datos del suscriptor ni textos.';

-- ---------------------------------------------------------------------
-- 5. EL CATÁLOGO DEL GEOVISOR: contratos pasa a capa propia; reportes de Comercial se puede encender (vacía hasta el 8); muestreo con su color.
-- ---------------------------------------------------------------------
alter table redes.geovisor_capas drop constraint geovisor_capas_fuente_check;
alter table redes.geovisor_capas add constraint geovisor_capas_fuente_check check (fuente in ('tesela', 'geojson', 'preparada', 'contratos'));
update redes.geovisor_capas set fuente = 'contratos', estado = 'activa', nota = 'Desde el zoom 16. Al tocar un contrato: su consumo, nombre y dirección (la consulta queda registrada)'
 where codigo = 'contratos';
update redes.geovisor_capas set fuente = 'geojson', por_fecha = true, nota = 'Se llena con el Corte 8: azul con contrato, rojo posible clandestino. Se puede atenuar'
 where codigo = 'reportes_comercial';
update redes.geovisor_capas set nota = 'Color por el último cloro y la turbiedad frente a los rangos de Salida (Res. 2115 de 2007 y criterio de planta)'
 where codigo = 'muestreo';

-- ---------------------------------------------------------------------
-- 6. PARÁMETROS
-- ---------------------------------------------------------------------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('geovisor_zoom_contratos', 16, 'zoom', 13, 20, 'Geovisor (Corte 6b): desde este zoom se ven los contratos'),
  ('geovisor_contratos_horas', 24, 'horas', 1, 720, 'Geovisor: la capa de contratos se rehace si tiene más de estas horas o si cambió la ficha del contrato'),
  ('geovisor_muestreo_dias', 30, 'días', 1, 365, 'Geovisor: un resultado de muestreo más viejo que esto no colorea el punto («sin muestra reciente»)')
on conflict (clave) do nothing;
