-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 10 — GUARDIA Y ESTRUCTURA: «Avisos» (solo supervisores y administrador) y la cola de avisos de salida para el Dell
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- · Todo es del esquema tecnica y de public.geoportal_tec_*. NINGUNA función de redes ni public.geoportal_redes_* se crea ni cambia (su huella sigue igual):
--   de redes solo se LEE (vistas y tablas) y se llaman dos funciones que ya existen (redes.f_param y redes.f_muestreo_calidad), con guardia md5.
-- · Los avisos se CALCULAN en cada consulta: no se guardan ni se marcan como vistos; desaparecen solos cuando se resuelve la causa.
-- · Lo único que se guarda: los plazos y mínimos (parámetros, con su evento), el saldo mínimo de cada químico (eventos) y la cola de salida de los daños
--   de riesgo alto (solo inserción: cada cambio de estado es un evento nuevo). Nada se borra.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.quimico_parametro_eventos') is null then raise exception 'Falta el Corte 7c (químicos de planta): aplíquelo antes'; end if;
  if to_regclass('tecnica.aviso_parametros') is not null or to_regclass('tecnica.avisos_salida') is not null then raise exception 'El Corte 12 ya está aplicado: deténgase y avise'; end if;
  if (select count(*) from (values {{REDES_USADAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> {{N_REDES_USADAS}} then
    raise exception 'Las funciones de redes que lee el Corte 12 cambiaron: deténgase y avise';
  end if;
  if exists (select 1 from pg_roles where rolname = 'dell_avisos') then raise exception 'El rol dell_avisos ya existe: deténgase y avise'; end if;
  if to_regclass('redes.v_dano') is null or to_regclass('redes.v_intervencion') is null or to_regclass('redes.v_no_identificados') is null or to_regclass('redes.v_nodo_visible') is null
     or to_regclass('redes.v_reporte_externo') is null or to_regclass('redes.v_cargas_estado') is null or to_regclass('redes.v_personal_ficha') is null or to_regclass('tecnica.v_punto_propuestas') is null
     or to_regclass('tecnica.v_quimico_saldo') is null or to_regclass('tecnica.v_quimico_vigente') is null or to_regclass('tecnica.v_registros_estado') is null then
    raise exception 'Falta una vista de redes o de tecnica que leen los avisos: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. PLAZOS Y MÍNIMOS DE LOS AVISOS (parámetros editables; cada cambio deja su evento con motivo)
--    area: planta (supervisor de planta), distribucion (supervisor de distribución), sistema (solo el administrador). El administrador edita todos.
-- ---------------------------------------------------------------------
create table tecnica.aviso_parametros (
  clave text primary key check (clave ~ '^[a-z][a-z0-9_]{2,40}$'),
  area text not null check (area in ('planta', 'distribucion', 'sistema')),
  valor numeric not null, minimo numeric not null, maximo numeric not null,
  unidad text not null check (length(unidad) between 1 and 20),
  orden integer not null,
  nombre text not null check (length(nombre) between 3 and 120),
  descripcion text not null check (length(descripcion) between 3 and 400),
  check (minimo <= maximo and valor between minimo and maximo));
comment on table tecnica.aviso_parametros is 'Corte 12: plazos y mínimos de los avisos de Técnica. Se cambian con geoportal_tec_aviso_parametro_fijar (con motivo y evento).';
insert into tecnica.aviso_parametros (clave, area, valor, minimo, maximo, unidad, orden, nombre, descripcion) values
  ('horario_inicio', 'planta', 8, 0, 23, 'hora', 10, 'Inicio del horario del personal', 'Hora en que empieza el turno de planta (David, 16-nov: 8 a. m.). Antes de esta hora no se avisa de Entrada ni Salida.'),
  ('horario_fin', 'planta', 18, 1, 24, 'hora', 20, 'Fin del horario del personal', 'Hora del cierre (6 p. m.). Desde esta hora, una planta sin registros del día sale en rojo.'),
  ('planta_primer_registro_hora', 'planta', 10, 0, 23, 'hora', 30, 'Hora límite del primer registro', 'Si a esta hora una planta no tiene su primer registro de Entrada o de Salida del día, sale en naranja.'),
  ('planta_horas_sin_registro', 'planta', 4, 1, 12, 'horas', 40, 'Horas sin registro dentro del horario', 'Si pasan más de estas horas desde el último registro del día (dentro del horario), sale en naranja.'),
  ('quimicos_dias_revisar', 'planta', 3, 1, 14, 'días', 50, 'Días de químicos que se revisan', 'Días cerrados (hasta ayer) en que se buscan días con dosis y caudal sin uso, y el desvío de esperado contra usado.'),
  ('dano_alto_naranja_h', 'distribucion', 2, 1, 720, 'horas', 110, 'Daño de riesgo alto: naranja', 'Un daño de riesgo alto abierto o en atención sale en naranja desde estas horas (avisa a cualquier hora).'),
  ('dano_alto_rojo_h', 'distribucion', 6, 1, 720, 'horas', 120, 'Daño de riesgo alto: rojo', 'Un daño de riesgo alto abierto o en atención sale en rojo desde estas horas.'),
  ('dano_medio_naranja_h', 'distribucion', 24, 1, 720, 'horas', 130, 'Daño de riesgo medio: naranja', 'Un daño de riesgo medio (o sin riesgo marcado) sale en naranja desde estas horas.'),
  ('dano_medio_rojo_h', 'distribucion', 72, 1, 720, 'horas', 140, 'Daño de riesgo medio: rojo', 'Un daño de riesgo medio (o sin riesgo marcado) sale en rojo desde estas horas.'),
  ('dano_bajo_naranja_h', 'distribucion', 72, 1, 720, 'horas', 150, 'Daño de riesgo bajo: naranja', 'Un daño de riesgo bajo sale en naranja desde estas horas.'),
  ('dano_bajo_rojo_h', 'distribucion', 168, 1, 720, 'horas', 160, 'Daño de riesgo bajo: rojo', 'Un daño de riesgo bajo sale en rojo desde estas horas (7 días).'),
  ('dano_sin_itv_dias', 'distribucion', 30, 1, 365, 'días', 170, 'Daños atendidos sin intervención: días', 'Se avisan los daños atendidos en estos últimos días que no tienen ninguna intervención registrada.'),
  ('l116_registrado_dias', 'distribucion', 3, 1, 60, 'días', 180, 'Línea 116 en «Registrado»', 'Un reporte de la línea 116 que sigue en «Registrado» desde hace más de estos días se avisa (cuando el Corte 5d esté publicado).'),
  ('carga_abierta_horas', 'distribucion', 24, 1, 720, 'horas', 190, 'Carga de capa abierta sin publicar', 'Una carga del Cargue de capas abierta hace más de estas horas, sin publicar ni anular, se avisa.'),
  ('salida_max_intentos', 'sistema', 5, 1, 20, 'intentos', 310, 'Intentos de envío del bot de avisos', 'Veces que el bot de avisos del Dell puede tomar un aviso de salida antes de dejarlo en error.');
create trigger t_no_borrar before delete on tecnica.aviso_parametros for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on tecnica.aviso_parametros for each statement execute function tecnica.f_solo_agregar();

create table tecnica.aviso_parametro_eventos (
  id bigint generated always as identity primary key,
  clave text not null references tecnica.aviso_parametros(clave),
  antes numeric not null, despues numeric not null,
  motivo text not null check (length(btrim(motivo)) between 10 and 500),
  autor text not null,
  creado_en timestamptz not null default clock_timestamp());
create index ix_aviso_param_ev on tecnica.aviso_parametro_eventos (clave, id desc);
create trigger t_solo_agregar before update or delete on tecnica.aviso_parametro_eventos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.aviso_parametro_eventos for each statement execute function tecnica.f_solo_agregar();

-- ---------------------------------------------------------------------
-- 2. SALDO MÍNIMO DE CADA QUÍMICO (en kg; lo fija el supervisor de planta). Arranca vacío: sin mínimo fijado no hay aviso. Quitarlo = un evento con mínimo nulo.
-- ---------------------------------------------------------------------
create table tecnica.quimico_minimo_eventos (
  id bigint generated always as identity primary key,
  quimico_id bigint not null references tecnica.quimicos(id),
  minimo_kg numeric check (minimo_kg is null or (minimo_kg > 0 and minimo_kg <= 10000000)),
  motivo text not null check (length(btrim(motivo)) between 10 and 500),
  autor text not null,
  creado_en timestamptz not null default clock_timestamp());
create index ix_qmin_quimico on tecnica.quimico_minimo_eventos (quimico_id, id desc);
create trigger t_solo_agregar before update or delete on tecnica.quimico_minimo_eventos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.quimico_minimo_eventos for each statement execute function tecnica.f_solo_agregar();

-- ---------------------------------------------------------------------
-- 3. COLA DE AVISOS DE SALIDA (daños de riesgo alto; la lee el bot de avisos del Dell: n8n, Telegram y luego WhatsApp). Como la cola de constancias
--    (salida.tomar_envios), pero de SOLO INSERCIÓN: el aviso no cambia nunca; su estado es el último evento (pendiente → tomado → enviado | error | anulado).
--    Una fila por daño y por nivel (nuevo, naranja, rojo): la base encola sola cuando el Dell pide (tecnica.avisos_tomar), sin cron ni disparadores en redes.
-- ---------------------------------------------------------------------
create table tecnica.avisos_salida (
  id uuid primary key default gen_random_uuid(),
  clave text not null unique check (length(clave) between 5 and 120),
  tipo text not null check (tipo in ('dano_alto')),
  nivel text not null check (nivel in ('nuevo', 'naranja', 'rojo')),
  area text not null check (area in ('distribucion')),
  ref_id uuid not null,
  mensaje jsonb not null check (jsonb_typeof(mensaje) = 'object'),
  creado_en timestamptz not null default clock_timestamp());
create index ix_avsal_ref on tecnica.avisos_salida (tipo, ref_id);
create index ix_avsal_creado on tecnica.avisos_salida (creado_en);
create trigger t_solo_agregar before update or delete on tecnica.avisos_salida for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.avisos_salida for each statement execute function tecnica.f_solo_agregar();

create table tecnica.aviso_salida_eventos (
  id bigint generated always as identity primary key,
  aviso_id uuid not null references tecnica.avisos_salida(id),
  estado text not null check (estado in ('pendiente', 'tomado', 'enviado', 'error', 'anulado')),
  lease_id uuid,
  tomado_hasta timestamptz,
  actor text not null check (actor in ('sistema', 'dell')),
  detalle jsonb not null default '{}'::jsonb check (jsonb_typeof(detalle) = 'object' and length(detalle::text) <= 2048),
  creado_en timestamptz not null default clock_timestamp(),
  check ((estado = 'tomado') = (lease_id is not null and tomado_hasta is not null)));
create index ix_avsal_ev on tecnica.aviso_salida_eventos (aviso_id, id desc);
create trigger t_solo_agregar before update or delete on tecnica.aviso_salida_eventos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.aviso_salida_eventos for each statement execute function tecnica.f_solo_agregar();

-- Estado vigente de cada aviso de salida (el último evento) y sus intentos (cada toma suma uno; liberar lo devuelve)
create view tecnica.v_avisos_salida as
select a.id, a.clave, a.tipo, a.nivel, a.area, a.ref_id, a.mensaje, a.creado_en,
       u.estado, u.lease_id, u.tomado_hasta, u.creado_en as estado_desde, u.detalle as ultimo_detalle,
       (select count(*) filter (where e.estado = 'tomado') - count(*) filter (where e.estado = 'pendiente' and e.detalle ->> 'motivo' = 'liberado')
          from tecnica.aviso_salida_eventos e where e.aviso_id = a.id)::integer as intentos
  from tecnica.avisos_salida a
  cross join lateral (select e.estado, e.lease_id, e.tomado_hasta, e.creado_en, e.detalle from tecnica.aviso_salida_eventos e where e.aviso_id = a.id order by e.id desc limit 1) u;
