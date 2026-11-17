-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 (presiones y alertas, sensores vacíos, usuarios sensibles y afectación del daño) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte9b_simulacion_alertas.md (Fase 2), §30.7 y §17 de la bitácora, respuestas de David del 17-nov.
-- · Presupone el paquete del 9b (1a + 1b) publicado: huella del conjunto de funciones de redes 895517fb68f74d6d6c20079c83bdf7c4.
-- · No reemplaza ninguna función de redes. Reemplaza UNA de tecnica: tecnica.f_avisos (del 9b 1b, md5 898bafa5adddfcc08d65adf138d0114a), para sumar el aviso informativo
--   de presiones (David, 17-nov): APAGADO por omisión (parámetro de Avisos «presion_modelo_aviso») y calculado solo con las horas confiables del modelo.
--   Solo base de datos: las rutas de la Edge y las pantallas son del Code B.
-- · Sin datos de personas: de un usuario sensible se guarda el contrato, el tipo y la PALABRA que coincidió (nunca el nombre).
-- =====================================================================
do $$
begin
  if to_regclass('redes.usuarios_sensibles') is not null then raise exception 'La Fase 2 del Corte 9b ya está aplicada: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '895517fb68f74d6d6c20079c83bdf7c4' then
    raise exception 'Las funciones de redes no son las del Corte 9b (1a + 1b) publicado (huella 895517fb68f74d6d6c20079c83bdf7c4): deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) <> '898bafa5adddfcc08d65adf138d0114a' then
    raise exception 'tecnica.f_avisos no es la publicada con el Corte 9b (1b) (md5 898bafa5adddfcc08d65adf138d0114a): deténgase y avise';
  end if;
  if to_regclass('redes.corte_fotos') is null or to_regclass('redes.pm_nodos') is null then raise exception 'Faltan tablas del 9b (1b) o del 9a: deténgase y avise'; end if;
end $$;

-- ---------- 1. Usuarios sensibles (hospitales, clínicas, colegios…): propuesta por el nombre y confirmación del supervisor ----------
create table redes.tipos_sensible (
  codigo text primary key check (codigo ~ '^[a-z][a-z0-9_]{2,29}$'),
  nombre text not null check (length(btrim(nombre)) between 3 and 60),
  patron text not null check (length(patron) between 3 and 500),      -- expresión regular sobre el nombre en mayúsculas y sin tildes
  orden  integer not null,
  activo boolean not null default true
);
insert into redes.tipos_sensible (codigo, nombre, patron, orden) values
  ('hospital', 'Hospital', '\m(HOSPITAL|HOSPITALARIO)\M', 10),
  ('clinica', 'Clínica o centro de salud', '\m(CLINICA|CENTRO DE SALUD|PUESTO DE SALUD|UNIDAD RENAL|DIALISIS|CENTRO MEDICO)\M', 20),
  ('colegio', 'Colegio, institución educativa u hogar infantil', '\m(COLEGIO|ESCUELA|INSTITUCION EDUCATIVA|INST EDUCATIVA|JARDIN INFANTIL|HOGAR INFANTIL|CDI|UNIVERSIDAD|SENA)\M', 30),
  ('otro', 'Otro (cárcel, bomberos, policía, hogar geriátrico…)', '\m(BOMBEROS|POLICIA|CARCEL|PENITENCIARI[AO]|ANCIANATO|HOGAR GERIATRICO|ASILO|BATALLON)\M', 40),
  ('sede_propia', 'Sede de EMDUPAR', '\m(ACUEDUCTO|EMDUPAR)\M', 50);      -- David, 17-nov: las sedes propias. «IPS» y «E.S.E.» quedan fuera (muchos falsos positivos)
create table redes.usuarios_sensibles (
  contrato  text primary key check (contrato ~ '^[0-9]{1,15}$'),
  tipo      text not null references redes.tipos_sensible (codigo),
  palabra   text check (palabra is null or length(palabra) <= 60),      -- la palabra del nombre que coincidió (no el nombre)
  origen    text not null check (origen in ('nombre', 'manual')),
  autor     text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp()
);
create table redes.usuario_sensible_eventos (
  id        bigint generated always as identity primary key,
  contrato  text not null references redes.usuarios_sensibles (contrato),
  accion    text not null check (accion in ('confirmar', 'descartar')),
  tipo      text references redes.tipos_sensible (codigo),      -- al confirmar, el tipo que vale (puede corregir el propuesto)
  motivo    text check (motivo is null or length(btrim(motivo)) between 10 and 500),
  autor     text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp(),
  check ((accion = 'confirmar') = (tipo is not null)),
  check (accion <> 'descartar' or motivo is not null)
);
create index ix_sensible_eventos on redes.usuario_sensible_eventos (contrato, id desc);
comment on table redes.usuarios_sensibles is 'Corte 9b (Fase 2): contratos de usuarios sensibles (propuestos por una palabra del nombre o agregados a mano). Solo agregar; sin el nombre. El estado es su último evento.';
-- el estado vigente: por_confirmar (sin eventos), confirmado o descartado; el tipo que vale es el del último «confirmar»
create view redes.v_usuario_sensible as
select u.contrato, coalesce(e.tipo, u.tipo) as tipo, u.palabra, u.origen,
       case e.accion when 'confirmar' then 'confirmado' when 'descartar' then 'descartado' else 'por_confirmar' end as estado, coalesce(e.creado_en, u.creado_en) as desde
  from redes.usuarios_sensibles u
  left join lateral (select x.accion, x.tipo, x.creado_en from redes.usuario_sensible_eventos x where x.contrato = u.contrato order by x.id desc limit 1) e on true;
revoke all on table redes.v_usuario_sensible from public, anon, authenticated, service_role;

-- ---------- 2. Presión de trabajo por material y clase (§30.7; para la alerta por material). «por_verificar»: falta la ficha del fabricante ----------
create table redes.presion_trabajo (
  id              bigint generated always as identity primary key,
  material_codigo text not null references redes.materiales (codigo),
  clase           text check (clase is null or length(btrim(clase)) between 1 and 40),      -- p. ej. «RDE 21»; nula: la que se usa si el tramo no dice su clase
  presion_mca     numeric not null check (presion_mca > 0 and presion_mca <= 1000),
  fuente          text not null check (length(btrim(fuente)) between 3 and 200),
  por_verificar   boolean not null default true,
  creado_en       timestamptz not null default clock_timestamp()
);
create unique index ux_presion_trabajo on redes.presion_trabajo (material_codigo, coalesce(clase, ''));
insert into redes.presion_trabajo (material_codigo, clase, presion_mca, fuente)
select m.codigo, x.clase, x.p, x.fuente from redes.materiales m
  join (values ('RDE 21', 140, 'PVC RDE 21 = 200 psi (§30.7; por verificar con Técnica)'), ('RDE 26', 112, 'PVC RDE 26 = 160 psi (§30.7; por verificar con Técnica)'),
               ('RDE 32,5', 88, 'PVC RDE 32,5 = 125 psi (§30.7; por verificar con Técnica)'),
               (null, 88, 'PVC sin clase en la ficha: se toma la menor (RDE 32,5 = 125 psi; por verificar con Técnica)')) x(clase, p, fuente) on m.codigo = 'PVC';
comment on table redes.presion_trabajo is 'Corte 9b (Fase 2): presión de trabajo por material y clase del tubo, para la alerta por material. Valores por verificar con la ficha del fabricante.';

-- ---------- 2b. Horas del día en que el modelo NO es confiable (David, 17-nov). En la red existente (modeloV1) el modelo colapsa en las horas de consumo
--                5, 7, 10, 12 y 14 (Fase 0 del 9b): las alertas y el aviso de presiones se calculan sin esas horas. La capa de presión del geovisor NO cambia ----------
create table redes.presion_horas_no_confiables (
  escenario text not null check (escenario in ('existente', 'futura')),
  hora      integer not null check (hora between 0 and 24),      -- la hora del modelo (0 a 24): el valor horas[hora + 1] de redes.pm_presion_hora
  motivo    text not null check (length(btrim(motivo)) between 10 and 300),
  activa    boolean not null default true,      -- para volver a contar una hora: activa = false (no se borra)
  creado_en timestamptz not null default clock_timestamp(),
  primary key (escenario, hora)
);
insert into redes.presion_horas_no_confiables (escenario, hora, motivo)
select 'existente', h, 'El modelo de la red existente (modeloV1, Plan Maestro 2014) colapsa a esta hora: presiones no confiables (Fase 0 del Corte 9b)' from unnest(array[5, 7, 10, 12, 14]) h;
create trigger t_no_borrar before delete on redes.presion_horas_no_confiables for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on redes.presion_horas_no_confiables for each statement execute function tecnica.f_solo_agregar();
comment on table redes.presion_horas_no_confiables is 'Corte 9b (Fase 2): horas del día en que la presión del modelo no es confiable; las alertas y el aviso de presiones no las cuentan. No se borra: activa = false.';

-- ---------- 3. Lecturas de sensores: queda VACÍA (los sensores son activos SEN; «por conectar» mientras no haya lecturas). Sin ruta de escritura en la fase 1 ----------
create table redes.sensor_lecturas (
  id          bigint generated always as identity primary key,
  activo_id   bigint not null references redes.activos (id),
  variable    text not null check (variable in ('presion', 'caudal', 'nivel', 'cloro')),
  valor       numeric not null check (valor::text not in ('NaN', 'Infinity', '-Infinity')),
  unidad      text not null check (length(unidad) between 1 and 20),
  medido_en   timestamptz not null,
  fuente      text not null check (length(btrim(fuente)) between 2 and 80),
  recibido_en timestamptz not null default clock_timestamp()
);
create index ix_sensor_lecturas on redes.sensor_lecturas (activo_id, medido_en desc);
comment on table redes.sensor_lecturas is 'Corte 9b (Fase 2): lecturas de sensores (activos SEN). Solo agregar. Vacía: la conexión del SCADA está fuera de la fase 1.';

do $$
declare t text;
begin
  foreach t in array array['tipos_sensible', 'usuarios_sensibles', 'usuario_sensible_eventos', 'presion_trabajo', 'presion_horas_no_confiables', 'sensor_lecturas'] loop
    execute format('alter table redes.%I enable row level security', t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', t);
  end loop;
  foreach t in array array['usuarios_sensibles', 'usuario_sensible_eventos', 'sensor_lecturas'] loop
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
end $$;

-- ---------- 4. Parámetros ----------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('sensor_sin_senal_min', 60, 'minutos', 5, 10080,
   'Sensores (Corte 9b): minutos sin lecturas desde los que un sensor conectado sale «sin señal»'),
  ('presion_lista_max', 50, 'nodos', 5, 500,
   'Alertas de presión (Corte 9b): cuántos nodos se listan como máximo por cada nivel (los peores primero); el total siempre se dice')
on conflict (clave) do update set estado = 'vigente', descripcion = excluded.descripcion;
-- el aviso informativo de presiones sale APAGADO (David, 17-nov): lo enciende Técnica cuando lo revise, en los parámetros de Avisos (0 apagado, 1 encendido)
insert into tecnica.aviso_parametros (clave, area, valor, minimo, maximo, unidad, orden, nombre, descripcion) values
  ('presion_modelo_aviso', 'distribucion', 0, 0, 1, '(0 no, 1 sí)', 175, 'Aviso de presiones del modelo',
   '0: apagado. 1: encendido. Encendido, sale un aviso informativo con los nodos fuera de rango según el modelo (presión de modelo, no medida; sin las horas en que el modelo no es confiable).')
on conflict (clave) do update set valor = 0, descripcion = excluded.descripcion;

-- ---------- 5. La capa «Cortes programados vigentes» se OCULTA de la lista de capas (David, 17-nov): ahora vive en el modo «Afectaciones». No se borra ----------
update redes.geovisor_capas set activa = false, nota = 'Oculta el 17-nov-2026 (Corte 9b): los cortes vigentes se ven en el modo «Afectaciones» del geovisor'
 where codigo = 'cortes';
