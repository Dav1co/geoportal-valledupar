-- =====================================================================
-- DOBLE LOCAL (Corte 5a) de lo vivo de planta que toca la capa MUE. SOLO PARA PRUEBAS EN EL POSTGIS DE HOMEBREW.
--   · tecnica.puntos con las columnas y reglas vivas (Cortes 1 Paso A, 2 Paso A y 3 Paso B de planta) y sus candados (no borrar, no vaciar);
--   · los 27 puntos de muestreo MUE-01..27 con su zona y número del informe (corte2_paso_a/puntos_muestreo.csv; barrio y ubicación vacíos, como en la base viva);
--   · tecnica.senal_cambio (señal de tiempo real; las RPC de planta que asignan formularios escriben ahí).
-- =====================================================================
alter table tecnica.puntos
  add column if not exists zona text, add column if not exists ubicacion text, add column if not exists referencia text, add column if not exists barrio text,
  add column if not exists diametro_pulg numeric, add column if not exists observacion text, add column if not exists numero_informe smallint,
  add column if not exists orden integer;
alter table tecnica.puntos
  add constraint puntos_codigo_check2 check (codigo ~ '^[A-Z0-9][A-Z0-9_-]{1,39}$'),
  add constraint puntos_nombre_check2 check (length(btrim(nombre)) between 2 and 120),
  add constraint puntos_tipo_check2 check (tipo in ('macromedicion', 'muestreo', 'tanque')),
  add constraint puntos_zona_check check (zona is null or zona in ('norte', 'sur', 'medio')),
  add constraint puntos_barrio_check check (barrio is null or length(btrim(barrio)) between 1 and 120),
  add constraint puntos_numero_informe_check check (numero_informe is null or numero_informe >= 1),
  add constraint puntos_orden_check check (orden is null or orden between 1 and 9999);
create unique index if not exists uq_puntos_codigo on tecnica.puntos (codigo);
create unique index if not exists uq_puntos_tipo_numero_informe on tecnica.puntos (tipo, numero_informe) where numero_informe is not null;
create trigger t_no_borrar before delete on tecnica.puntos for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on tecnica.puntos for each statement execute function tecnica.f_solo_agregar();
insert into tecnica.puntos (codigo, nombre, tipo, zona, numero_informe) values
  ('MUE-01', 'Novalito', 'muestreo', 'norte', 1),
  ('MUE-02', 'Villalva', 'muestreo', 'norte', 2),
  ('MUE-03', 'El Refugio', 'muestreo', 'norte', 3),
  ('MUE-04', 'La Nevada', 'muestreo', 'norte', 4),
  ('MUE-05', 'OGB', 'muestreo', 'sur', 5),
  ('MUE-06', 'Panamá', 'muestreo', 'sur', 6),
  ('MUE-07', 'Don Carmelo', 'muestreo', 'sur', 7),
  ('MUE-08', 'La Victoria', 'muestreo', 'sur', 8),
  ('MUE-09', '7 de Agosto', 'muestreo', 'sur', 9),
  ('MUE-10', 'Mayales', 'muestreo', 'sur', 10),
  ('MUE-11', 'Los Cocos', 'muestreo', 'sur', 11),
  ('MUE-12', 'El Cerrito', 'muestreo', 'sur', 12),
  ('MUE-13', 'Los Fundadores', 'muestreo', 'sur', 13),
  ('MUE-14', 'Álamos', 'muestreo', 'sur', 14),
  ('MUE-15', 'Nando Marín', 'muestreo', 'sur', 15),
  ('MUE-16', 'Tobías Daza', 'muestreo', 'sur', 16),
  ('MUE-17', 'Alfonso López', 'muestreo', 'medio', 17),
  ('MUE-18', 'Hospital', 'muestreo', 'medio', 18),
  ('MUE-19', 'Loperena', 'muestreo', 'medio', 19),
  ('MUE-20', 'El Amparo', 'muestreo', 'medio', 20),
  ('MUE-21', 'El Carmen', 'muestreo', 'medio', 21),
  ('MUE-22', 'Sicarare', 'muestreo', 'medio', 22),
  ('MUE-23', 'La Granja', 'muestreo', 'medio', 23),
  ('MUE-24', 'San Joaquín', 'muestreo', 'medio', 24),
  ('MUE-25', 'Divino Niño', 'muestreo', 'medio', 25),
  ('MUE-26', 'Guatapurí', 'muestreo', 'medio', 26),
  ('MUE-27', 'Don Alberto', 'muestreo', 'medio', 27);
create table if not exists tecnica.senal_cambio (
  id bigint generated always as identity primary key,
  tabla text not null check (tabla in ('registros', 'exclusiones', 'personal_tecnico_eventos')),
  planta_id bigint,
  creado_en timestamptz not null default clock_timestamp());
-- el dominio vivo de las claves de formulario (Corte 1 Paso A de planta), con sus 7 valores
create domain tecnica.formulario_clave as text
  constraint formulario_clave_ck check (value in ('entrada', 'salida', 'muestreo', 'danos_fallas', 'mantenimiento', 'uso_quimicos', 'entrada_quimicos'));
