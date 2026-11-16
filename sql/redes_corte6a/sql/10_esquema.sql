-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 10 — GUARDIA, COLUMNA NUEVA DE LAS CAPAS DEL CARGUE, CATÁLOGO DEL GEOVISOR, CAPAS POR PERFIL Y PARÁMETROS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: plan 02 (Corte 6), 01 sección D, N-11, N-13 y N-14; respuesta de David del 16-nov 01:30 (quién carga cada capa, al final de la bitácora).
-- · Presupone el 5c aplicado (huella del conjunto de funciones de redes).
-- · ⚠ Se reemplazan 10 RPC (las 5 del motor del 1a que abren el paso a la carga, las 4 de la pantalla del 5c y geoportal_redes_mi_perfil del 4a),
--   con su texto exacto en la reversa. El cambio es solo QUIÉN puede (redes.f_autorizar_carga en vez de redes.f_autorizar_admin) y el dato «geovisor».
-- · ⚠ redes.capas (viva, del 1a): se le AGREGA la columna carga_supervisor (por omisión false). No se cambia ninguna otra columna ni regla.
-- =====================================================================
do $$
begin
  if to_regclass('redes.ficha_campo_devoluciones') is null then
    raise exception 'Falta el Corte 5c: aplíquelo antes';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'a5ce1ff8c5659de3b853e30f4d3025e6' then
    raise exception 'Las funciones de redes no son las del Corte 5c (o el Corte 6a ya está aplicado): deténgase y avise';
  end if;
  if to_regclass('redes.geovisor_capas') is not null or to_regclass('redes.capas_por_perfil') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'capas' and column_name = 'carga_supervisor') then
    raise exception 'Lo del 6a ya existe: el Corte 6a parece aplicado';
  end if;
  if (select count(*) from redes.capas where codigo in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas', 'muestreo', 'acometidas', 'captaciones', 'aduccion',
        'desarenadores', 'bombeo_ap', 'sumideros', 'interceptores', 'bombeo_ar', 'ptar', 'sectores', 'sensores', 'scada')) <> 17 then
    raise exception 'Faltan capas del Cargue (1a, 5a o 5c): deténgase y avise';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'redes.capas'::regclass and tgname = 't_no_borrar' and not tgisinternal) then
    raise exception 'redes.capas no tiene su candado: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. QUIÉN CARGA CADA CAPA (David, 16-nov 01:30): las capas de la red que vienen del MODELO hidráulico (acueducto, conductos, pozos y descargas de
--    alcantarillado: topología, enlace de contratos y simulación de cierre) solo el administrador; las demás también el supervisor de distribución.
--    Es un dato de la capa (no una lista escrita en las funciones), para que una capa nueva se pueda abrir o cerrar al supervisor sin otra migración.
-- ---------------------------------------------------------------------
alter table redes.capas add column carga_supervisor boolean not null default false;
comment on column redes.capas.carga_supervisor is 'Corte 6a: el supervisor de distribución también carga esta capa. Las del modelo (acueducto, conductos, pozos y descargas) solo el administrador.';
update redes.capas set carga_supervisor = true
 where fuente = 'carga' and codigo not in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas');

-- ---------------------------------------------------------------------
-- 2. CATÁLOGO DE CAPAS DEL GEOVISOR (01 sección D). Distinto de redes.capas (que es lo que se CARGA): aquí está lo que se VE.
--    fuente: «tesela» (activos vigentes, por prefijo, en la tesela del geovisor), «geojson» (daños, intervenciones, muestreo y reportes del bot, por fecha)
--    o «preparada» (sin datos todavía: queda apagada y con su nota). solo_completo: el operador con el geovisor activado (N-13) no la ve.
-- ---------------------------------------------------------------------
create table redes.geovisor_capas (
  codigo        text primary key check (codigo ~ '^[a-z][a-z0-9_]{2,39}$'),
  nombre        text not null check (length(btrim(nombre)) between 2 and 80),
  grupo         text not null check (grupo in ('acueducto', 'alcantarillado', 'tecnologia', 'actividades', 'calidad', 'reportes', 'comercial', 'analisis')),
  fuente        text not null check (fuente in ('tesela', 'geojson', 'preparada')),
  estado        text not null default 'activa' check (estado in ('activa', 'por_conectar', 'espera_dato')),
  prefijos      text[] not null default '{}',
  por_fecha     boolean not null default false,
  solo_completo boolean not null default false,
  nota          text check (nota is null or length(nota) <= 300),
  orden         integer not null,
  activa        boolean not null default true,
  check ((fuente = 'tesela') = (cardinality(prefijos) > 0)),
  check (not por_fecha or fuente = 'geojson')
);
comment on table redes.geovisor_capas is 'Corte 6a: las capas del geovisor técnico (interruptores). No se borran: se desactivan.';

create table redes.capas_por_perfil (
  perfil         text not null check (perfil in ('supervisor_distribucion', 'supervisor_planta', 'operador_distribucion')),
  capa           text not null references redes.geovisor_capas (codigo),
  encendida      boolean not null,
  actualizado_en timestamptz not null default clock_timestamp(),
  actualizado_por text not null,
  primary key (perfil, capa)
);
comment on table redes.capas_por_perfil is 'Corte 6a (N-11): capas encendidas al abrir el geovisor, por perfil. El administrador abre con las de los dos supervisores; una persona con varios perfiles, con la unión. Las edita el administrador, con motivo (capas_por_perfil_eventos).';

create table redes.capas_por_perfil_eventos (
  id         bigint generated always as identity primary key,
  perfil     text not null,
  capa       text not null references redes.geovisor_capas (codigo),
  antes      boolean,
  despues    boolean not null,
  motivo     text not null check (length(btrim(motivo)) between 10 and 1000),
  autor      text not null,
  creado_en  timestamptz not null default clock_timestamp()
);
comment on table redes.capas_por_perfil_eventos is 'Corte 6a: historial de las capas por omisión del geovisor. Solo inserción.';

do $$
begin
  execute 'create trigger t_no_borrar before delete on redes.geovisor_capas for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_no_vaciar before truncate on redes.geovisor_capas for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_no_borrar before delete on redes.capas_por_perfil for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_no_vaciar before truncate on redes.capas_por_perfil for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar before update or delete on redes.capas_por_perfil_eventos for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on redes.capas_por_perfil_eventos for each statement execute function tecnica.f_solo_agregar()';
  execute 'alter table redes.geovisor_capas enable row level security';
  execute 'alter table redes.capas_por_perfil enable row level security';
  execute 'alter table redes.capas_por_perfil_eventos enable row level security';
end $$;

insert into redes.geovisor_capas (codigo, nombre, grupo, fuente, estado, prefijos, por_fecha, solo_completo, nota, orden) values
  ('acu_tramos',        'Tramos de acueducto',                                     'acueducto',      'tesela',    'activa',       '{RED,CON,ADU,ACO}',         false, false, null, 10),
  ('acu_nodos',         'Válvulas, torres, hidrantes y accesorios',                'acueducto',      'tesela',    'activa',       '{VAL,TOR,HID,ACC,MAC}',     false, false, null, 11),
  ('acu_instalaciones', 'Tanques, plantas, captaciones y bombeo',                  'acueducto',      'tesela',    'activa',       '{TAN,PTA,CAP,DES,EBA}',     false, false, null, 12),
  ('alc_conductos',     'Conductos de alcantarillado',                             'alcantarillado', 'tesela',    'activa',       '{COL,INT}',                 false, false, null, 20),
  ('alc_pozos',         'Pozos, sumideros y descargas',                            'alcantarillado', 'tesela',    'activa',       '{POZ,SUM,VER,EBR,PTR}',     false, false, null, 21),
  ('sectores',          'Sectores hidráulicos',                                    'tecnologia',     'tesela',    'activa',       '{SEC}',                     false, false, 'Se ven cuando se carguen los polígonos (Cargue de capas)', 30),
  ('sensores',          'Sensores y SCADA',                                        'tecnologia',     'tesela',    'por_conectar', '{SEN,SCA}',                 false, false, 'Se ve la ubicación; las lecturas se conectan con el SCADA (Corte 9 y siguientes)', 31),
  ('danos',             'Daños y fallas',                                          'actividades',    'geojson',   'activa',       '{}',                        true,  false, null, 40),
  ('intervenciones',    'Intervenciones',                                          'actividades',    'geojson',   'activa',       '{}',                        true,  false, null, 41),
  ('muestreo',          'Puntos de muestreo',                                      'calidad',        'geojson',   'activa',       '{}',                        false, true,  'El último cloro y la turbiedad llegan con los rangos del jefe de planta', 50),
  ('pqr_116',           'PQR técnicas y línea 116',                                'calidad',        'preparada', 'espera_dato',  '{}',                        false, true,  'Espera el archivo (Corte 5d)', 51),
  ('reportes_bot',      'Reportes del bot (Telegram)',                             'reportes',       'geojson',   'activa',       '{}',                        true,  true,  'Se llena cuando se conecte el bot (n8n)', 60),
  ('reportes_comercial','Reportes de Comercial (anomalías y revisiones)',          'reportes',       'preparada', 'espera_dato',  '{}',                        false, true,  'Azul con contrato, rojo posibles clandestinos (Corte 8)', 61),
  ('reporte_ciudadano', 'Reporte ciudadano (contratista)',                         'reportes',       'preparada', 'espera_dato',  '{}',                        false, true,  'Espera la interfaz con el contratista', 62),
  ('contratos',         'Contratos (consumo y edad del medidor)',                  'comercial',      'preparada', 'espera_dato',  '{}',                        false, true,  'Llega en el Corte 6b', 70),
  ('presion',           'Presión en la red (alertas)',                             'analisis',       'preparada', 'espera_dato',  '{}',                        false, true,  'Espera el modelo hidráulico (Corte 9)', 80),
  ('cuadrillas',        'Cuadrillas por GPS',                                      'analisis',       'preparada', 'espera_dato',  '{}',                        false, true,  'Espera la unificación con Acuo', 81),
  ('cortes',            'Cortes programados vigentes',                             'analisis',       'preparada', 'espera_dato',  '{}',                        false, true,  null, 82),
  ('mapa_calor',        'Mapa de calor de reportes',                               'analisis',       'preparada', 'espera_dato',  '{}',                        false, true,  null, 83);

-- Capas encendidas al abrir (01 sección D): supervisor de distribución, redes y las actividades; supervisor de planta, muestreo y tanques;
-- operador con el geovisor activado, redes y las actividades del día. El administrador abre con la unión de los dos supervisores.
insert into redes.capas_por_perfil (perfil, capa, encendida, actualizado_por)
select p, c, true, 'migracion@redes_corte6a'
  from (values ('supervisor_distribucion', 'acu_tramos'), ('supervisor_distribucion', 'acu_nodos'), ('supervisor_distribucion', 'acu_instalaciones'),
               ('supervisor_distribucion', 'alc_conductos'), ('supervisor_distribucion', 'alc_pozos'), ('supervisor_distribucion', 'danos'),
               ('supervisor_distribucion', 'intervenciones'),
               ('supervisor_planta', 'acu_instalaciones'), ('supervisor_planta', 'muestreo'),
               ('operador_distribucion', 'acu_tramos'), ('operador_distribucion', 'acu_nodos'), ('operador_distribucion', 'alc_conductos'),
               ('operador_distribucion', 'alc_pozos'), ('operador_distribucion', 'danos'), ('operador_distribucion', 'intervenciones')) x(p, c);

-- ---------------------------------------------------------------------
-- 3. PARÁMETROS DEL GEOVISOR (medidos con la red real en el PostGIS local: a zoom 12 la tesela completa del centro pesa 1,2 MB; a zoom 13 con la red
--    principal, unos 160 KB; a zoom 14 con todos los tramos, 115 KB; a zoom 15 con los nodos, 60 KB).
-- ---------------------------------------------------------------------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('geovisor_zoom_min', 13, 'zoom', 10, 16, 'Geovisor (Corte 6a): desde este zoom se ve la red principal (más lejos, solo el mapa base)'),
  ('geovisor_zoom_red_completa', 14, 'zoom', 10, 18, 'Geovisor: desde este zoom se ven todos los tramos (antes, solo la red principal)'),
  ('geovisor_zoom_nodos', 15, 'zoom', 10, 19, 'Geovisor: desde este zoom se ven válvulas, pozos y demás puntos (tanques y plantas, desde el zoom mínimo)'),
  ('geovisor_zoom_acc', 17, 'zoom', 12, 20, 'Geovisor: desde este zoom se ven los accesorios (tees, codos, tapones…)'),
  ('geovisor_diam_principal_acu_mm', 150, 'mm', 0, 2000, 'Geovisor: diámetro desde el que un tramo de acueducto es «red principal» (se ve desde el zoom mínimo)'),
  ('geovisor_diam_principal_alc_mm', 450, 'mm', 0, 3000, 'Geovisor: diámetro desde el que un conducto de alcantarillado es «red principal»'),
  ('geovisor_rango_meses', 12, 'meses', 1, 24, 'Geovisor: rango máximo de fechas de daños, intervenciones y reportes'),
  ('geovisor_max_elementos', 3000, 'elementos', 100, 20000, 'Geovisor: tope de elementos de una capa por fecha (si hay más, avisa que la lista está recortada)')
on conflict (clave) do nothing;      -- una reversa los deja (los parámetros no se borran)
