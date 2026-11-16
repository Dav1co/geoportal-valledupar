begin;
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
  if (select count(*) from (values ('redes.f_param(text)', 'fb51278a5e07f3a0825be0155a76fd8b'), ('redes.f_muestreo_calidad(bigint)', 'a800598f12b1a46c768deffcc42671c1')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2 then
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
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 20 — FUNCIONES INTERNAS: el cálculo de los avisos (una sola consulta) y la cola de salida del Dell
-- · tecnica.f_avisos(planta, distribucion, ahora): TODOS los avisos de la persona en una llamada. «ahora» solo lo fijan las pruebas (nulo = la hora del servidor).
-- · Los avisos no se guardan: se calculan en cada llamada con lo que hay en las tablas; desaparecen cuando se resuelve la causa.
-- · Ninguna función de redes se crea ni cambia; de redes solo se leen vistas y tablas, y se llaman redes.f_param y redes.f_muestreo_calidad.
-- =====================================================================

-- Valor de un parámetro de los avisos
create function tecnica.f_aparam(p_clave text) returns numeric language sql stable set search_path to 'tecnica', 'pg_temp' as $$
  select valor from tecnica.aviso_parametros where clave = p_clave $$;

-- «1 daño», «3 daños»
create function tecnica.f_cuantos(p_n bigint, p_uno text, p_varios text) returns text language sql immutable set search_path to 'pg_catalog' as $$
  select p_n || ' ' || case when p_n = 1 then p_uno else p_varios end $$;

-- Horas transcurridas en palabras: «menos de 1 h», «5 h», «3 días»
create function tecnica.f_texto_horas(p_horas numeric) returns text language sql immutable set search_path to 'pg_catalog' as $$
  select case when p_horas is null then '' when p_horas < 1 then 'menos de 1 h' when p_horas < 48 then floor(p_horas)::integer || ' h'
              else floor(p_horas / 24)::integer || ' días' end $$;

-- Un número para la pantalla, como en el resto de Técnica: punto de miles, coma decimal y sin ceros de más («2.000», «0,05»). No depende del idioma de la base.
create function tecnica.f_texto_num(p numeric) returns text language sql immutable set search_path to 'pg_catalog' as $$
  select case when p is null then '' else
           case when round(p, 2) < 0 then '-' else '' end
           || regexp_replace(trunc(abs(round(p, 2)))::text, '(\d)(?=(\d{3})+$)', '\1.', 'g')
           || coalesce(',' || nullif(split_part(trim_scale(abs(round(p, 2)) - trunc(abs(round(p, 2))))::text, '.', 2), ''), '') end $$;

-- Quién pide los avisos y de qué áreas: supervisor de planta (Dashboard PTAP), supervisor de distribución (Dashboard distribución) o administrador (todo).
-- Personal: los dos supervisores y el administrador. Cualquier otra persona: 42501.
create function tecnica.f_avisos_perfil(p_solicitante text, out email text, out admin boolean, out planta boolean, out distribucion boolean) returns record
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
begin
  email := lower(btrim(coalesce(p_solicitante, '')));
  if email = '' or position('@' in email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  admin := public.geoportal_es_admin(email);
  planta := admin or public.geoportal_puede(email, 'dashboard_tecnico');
  distribucion := admin or public.geoportal_puede(email, 'dashboard_redes');
  if not (planta or distribucion) then raise exception 'Solo los supervisores y el administrador ven los avisos' using errcode = '42501'; end if;
  if not admin and not tecnica.f_tecnica_activa(email) then raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501'; end if;
end $$;

-- ---------------------------------------------------------------------
-- LOS AVISOS. Cada aviso: {clave, area (planta|distribucion|personal), nivel (rojo|naranja|info), titulo, detalle, n, items (hasta 5 textos cortos),
-- bandeja {tablero (ptap|distribucion|personal), pestana}, desde, orden}. Ordenados: rojo, naranja, info; dentro, por área y por orden.
-- ---------------------------------------------------------------------
create function tecnica.f_avisos(p_planta boolean, p_distribucion boolean, p_ahora timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $$
declare
  v_ahora timestamptz := coalesce(p_ahora, clock_timestamp());
  v_loc timestamp := coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota';
  v_hoy date := (coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota')::date;
  v_h numeric := extract(hour from (coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota')) + extract(minute from (coalesce(p_ahora, clock_timestamp()) at time zone 'America/Bogota')) / 60.0;
  v_av jsonb := '[]'::jsonb;
  r record; v_n bigint; v_items jsonb; v_items2 jsonb; v_dz jsonb; v_desde timestamptz; v_dias integer; v_x numeric; v_y numeric; v_z numeric;
  v_ini numeric; v_fin numeric; v_primer numeric; v_sin numeric;
begin
  -- ===================== PLANTAS =====================
  if p_planta then
    v_ini := tecnica.f_aparam('horario_inicio'); v_fin := tecnica.f_aparam('horario_fin');
    v_primer := tecnica.f_aparam('planta_primer_registro_hora'); v_sin := tecnica.f_aparam('planta_horas_sin_registro');
    -- P1. Entrada y Salida sin registrar hoy, por planta, dentro del horario del personal (8 a. m. a 6 p. m.)
    if v_h >= greatest(v_ini, v_primer) then
      for r in select p.codigo, p.nombre, f.form, f.titulo, f.ord,
                      (select max(x.muestra_ts) from tecnica.v_registros_estado x
                        where x.formulario::text = f.form and x.planta_id = p.id and x.fecha_muestra = v_hoy and not x.excluido and x.muestra_ts <= v_ahora) as ultimo
                 from tecnica.plantas p cross join (values ('entrada', 'Entrada', 1), ('salida', 'Salida', 2)) f(form, titulo, ord)
                where p.activa order by p.id, f.ord loop
        if r.ultimo is null and v_h >= v_fin then
          v_av := v_av || jsonb_build_object('clave', 'planta_' || r.form || ':' || r.codigo, 'area', 'planta', 'nivel', 'rojo', 'orden', 10 + r.ord,
                    'titulo', format('%s sin registros hoy en %s', r.titulo, r.nombre), 'detalle', 'Cerró el horario del personal sin ningún registro del día.',
                    'n', 1, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'registros'), 'desde', null);
        elsif r.ultimo is null and v_h < v_fin then
          v_av := v_av || jsonb_build_object('clave', 'planta_' || r.form || ':' || r.codigo, 'area', 'planta', 'nivel', 'naranja', 'orden', 10 + r.ord,
                    'titulo', format('%s sin el primer registro del día en %s', r.titulo, r.nombre),
                    'detalle', format('Ningún registro hoy; el primero se espera antes de las %s:00.', v_primer),
                    'n', 1, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'registros'), 'desde', null);
        elsif r.ultimo is not null and v_h < v_fin and v_ahora - r.ultimo > make_interval(secs => (v_sin * 3600)::double precision) then
          v_av := v_av || jsonb_build_object('clave', 'planta_' || r.form || ':' || r.codigo, 'area', 'planta', 'nivel', 'naranja', 'orden', 10 + r.ord,
                    'titulo', format('%s sin registro hace %s en %s', r.titulo, tecnica.f_texto_horas(extract(epoch from v_ahora - r.ultimo)::numeric / 3600), r.nombre),
                    'detalle', format('El último registro de hoy fue a las %s.', to_char(r.ultimo at time zone 'America/Bogota', 'HH24:MI')),
                    'n', 1, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'registros'), 'desde', r.ultimo);
        end if;
      end loop;
    end if;

    -- P2. Puntos de muestreo sin muestra en los últimos días (el mismo parámetro del geovisor: geovisor_muestreo_dias, 35)
    v_dias := floor(redes.f_param('geovisor_muestreo_dias'))::integer;
    select count(*), coalesce(jsonb_agg(s.codigo || ' · ' || s.nombre order by s.o, s.codigo) filter (where s.rn <= 5), '[]'::jsonb) into v_n, v_items
      from (select p.codigo, p.nombre, coalesce(p.orden, 999999) as o, row_number() over (order by coalesce(p.orden, 999999), p.codigo) as rn
              from tecnica.puntos p
             where p.tipo = 'muestreo' and p.activo
               and p.id not in (select x.punto_id from tecnica.v_registros_estado x
                                 where x.formulario::text = 'muestreo' and x.punto_id is not null and not x.excluido
                                   and x.muestra_ts >= v_ahora - make_interval(days => v_dias) and x.muestra_ts <= v_ahora)) s;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'muestreo_sin_muestra', 'area', 'planta', 'nivel', 'naranja', 'orden', 20,
                'titulo', format('%s sin muestra en %s días', tecnica.f_cuantos(v_n, 'punto de muestreo', 'puntos de muestreo'), v_dias), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'puntos'), 'desde', null);
    end if;

    -- P3. Último cloro o última turbiedad fuera de rango (la misma calidad que pinta el geovisor: redes.f_muestreo_calidad)
    select count(*), coalesce(jsonb_agg(s.txt order by s.o, s.codigo) filter (where s.rn <= 5), '[]'::jsonb) into v_n, v_items
      from (select c.codigo, c.o, row_number() over (order by c.o, c.codigo) as rn,
                   c.codigo || ' · ' || (select string_agg(format('%s %s %s', m ->> 'nombre', tecnica.f_texto_num((m ->> 'valor')::numeric), coalesce(m ->> 'unidad', '')), ', ')
                                           from jsonb_array_elements(c.cal -> 'medidas') m where (m ->> 'reciente')::boolean and (m ->> 'dentro')::boolean is false) as txt
              from (select p.codigo, coalesce(p.orden, 999999) as o, redes.f_muestreo_calidad(p.id) as cal from tecnica.puntos p where p.tipo = 'muestreo' and p.activo) c
             where c.cal ->> 'calidad' = 'fuera') s;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'muestreo_fuera_rango', 'area', 'planta', 'nivel', 'rojo', 'orden', 21,
                'titulo', format('%s con el último cloro o la última turbiedad fuera de rango', tecnica.f_cuantos(v_n, 'punto', 'puntos')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'eventos'), 'desde', null);
    end if;

    -- P4. Químicos: días con dosis y caudal sin uso, y desvío de esperado contra usado (los últimos días cerrados, hasta ayer; la misma cuenta del Corte 7a)
    v_dias := floor(tecnica.f_aparam('quimicos_dias_revisar'))::integer;
    v_x := tecnica.f_qparam('desvio_pct');
    with filas as (
      select d.dia, p.nombre as planta, v.nombre as quimico, qi.qi,
             coalesce((select m.dosis_optima_ppm from tecnica.quimico_movimientos m where m.tipo = 'uso' and m.para_que = 'dosificacion' and m.quimico_id = v.quimico_id
                        and m.planta_id = p.id and m.dia = d.dia and m.dosis_optima_ppm is not null order by m.id desc limit 1),
                      tecnica.f_dosis_optima_en(v.quimico_id, ((d.dia + 1)::timestamp at time zone 'America/Bogota'))) as dosis,
             coalesce((select -sum(m.cantidad_kg) from tecnica.quimico_movimientos m where m.tipo = 'uso' and m.para_que = 'dosificacion' and m.quimico_id = v.quimico_id
                        and m.planta_id = p.id and m.dia = d.dia), 0) as usado
        from generate_series(v_hoy - v_dias, v_hoy - 1, interval '1 day') d0(t) cross join lateral (select d0.t::date as dia) d
        cross join tecnica.plantas p cross join tecnica.v_quimico_vigente v
        cross join lateral (select avg(r2.valor) as qi from tecnica.v_registros_estado r2
                             where r2.formulario::text = 'entrada' and r2.planta_id = p.id and r2.fecha_muestra = d.dia and not r2.excluido
                               and r2.variable_id = (select id from tecnica.variables where codigo = 'caudal_qi')) qi
       where p.activa and v.potabilizacion and v.activo and qi.qi is not null),
    calc as (select f.*, f.dosis * f.qi * 86.4 / 1000 as esperado from filas f where f.dosis is not null)
    select count(*) filter (where c.esperado > 0 and c.usado = 0),
           coalesce(jsonb_agg(to_char(c.dia, 'DD/MM') || ' · ' || c.planta || ' · ' || c.quimico order by c.dia desc, c.planta, c.quimico) filter (where c.esperado > 0 and c.usado = 0), '[]'::jsonb),
           count(*) filter (where c.esperado > 0 and c.usado > 0 and abs(c.usado - c.esperado) > c.esperado * v_x / 100),
           coalesce(jsonb_agg(to_char(c.dia, 'DD/MM') || ' · ' || c.planta || ' · ' || c.quimico || ' · ' || case when c.usado > c.esperado then '+' else '' end
                              || round((c.usado - c.esperado) / c.esperado * 100) || ' %' order by c.dia desc, c.planta, c.quimico)
                    filter (where c.esperado > 0 and c.usado > 0 and abs(c.usado - c.esperado) > c.esperado * v_x / 100), '[]'::jsonb)
      into v_n, v_items, v_y, v_items2
      from calc c;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_sin_uso', 'area', 'planta', 'nivel', 'naranja', 'orden', 30,
                'titulo', format('%s con dosis y caudal sin uso de químicos registrado', tecnica.f_cuantos(v_n, 'día', 'días')),
                'detalle', format('Revisados los últimos %s días cerrados.', v_dias),
                'n', v_n, 'items', (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(v_items) with ordinality t(e, i) where i <= 5) z), 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;
    if v_y > 0 and tecnica.f_qparam('marca_esperado_usado') = 1 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_desvio', 'area', 'planta', 'nivel', 'naranja', 'orden', 31,
                'titulo', format('%s con el uso de químicos fuera del %s %% de lo esperado', tecnica.f_cuantos(v_y::bigint, 'día', 'días'), tecnica.f_texto_num(v_x)),
                'detalle', format('Revisados los últimos %s días cerrados.', v_dias),
                'n', v_y, 'items', (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(v_items2) with ordinality t(e, i) where i <= 5) z),
                'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;

    -- P5. Químicos de potabilización sin dosis óptima o sin ficha técnica en PDF
    select count(*), coalesce(jsonb_agg(v.nombre || ' · ' || concat_ws(' y ', case when v.dosis_optima_ppm is null then 'sin dosis óptima' end,
                                                                     case when v.ficha_ruta is null then 'sin ficha en PDF' end) order by v.nombre), '[]'::jsonb)
      into v_n, v_items
      from tecnica.v_quimico_vigente v where v.activo and v.potabilizacion and (v.dosis_optima_ppm is null or v.ficha_ruta is null);
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_ficha', 'area', 'planta', 'nivel', 'naranja', 'orden', 32,
                'titulo', format('%s de potabilización sin dosis óptima o sin ficha técnica', tecnica.f_cuantos(v_n, 'químico', 'químicos')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;

    -- P6. Saldo por debajo del mínimo (el mínimo lo fija el supervisor de planta por químico; sin mínimo fijado no hay aviso)
    select count(*), coalesce(jsonb_agg(s.nombre || ' · ' || tecnica.f_texto_num(s.saldo_kg) || ' kg (mínimo ' || tecnica.f_texto_num(m.minimo_kg) || ' kg)' order by s.nombre), '[]'::jsonb)
      into v_n, v_items
      from tecnica.v_quimico_saldo s
      join tecnica.quimicos q on q.id = s.quimico_id and q.activo
      cross join lateral (select e.minimo_kg from tecnica.quimico_minimo_eventos e where e.quimico_id = s.quimico_id order by e.id desc limit 1) m
     where m.minimo_kg is not null and s.saldo_kg is not null and s.saldo_kg < m.minimo_kg;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'quimicos_saldo', 'area', 'planta', 'nivel', 'naranja', 'orden', 33,
                'titulo', format('%s por debajo del saldo mínimo', tecnica.f_cuantos(v_n, 'químico', 'químicos')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'quimicos'), 'desde', null);
    end if;

    -- P7. Ubicaciones de puntos de muestreo pendientes de aprobar (Corte 5b)
    select count(*), coalesce(jsonb_agg(s.codigo order by s.creado_en) filter (where s.rn <= 5), '[]'::jsonb), min(s.creado_en) into v_n, v_items, v_desde
      from (select p.codigo, pr.creado_en, row_number() over (order by pr.creado_en) as rn
              from tecnica.v_punto_propuestas pr join tecnica.puntos p on p.id = pr.punto_id where pr.estado = 'pendiente') s;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'ubicaciones_pendientes', 'area', 'planta', 'nivel', 'naranja', 'orden', 40,
                'titulo', format('%s de puntos de muestreo por aprobar', tecnica.f_cuantos(v_n, 'ubicación', 'ubicaciones')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'ptap', 'pestana', 'puntos'), 'desde', v_desde);
    end if;
  end if;

  -- ===================== DISTRIBUCIÓN =====================
  if p_distribucion then
    -- D1. Daños abiertos o en atención según su riesgo (alto: 2 h y 6 h; medio o sin riesgo: 24 h y 72 h; bajo: 72 h y 7 días). Avisan a cualquier hora.
    -- redes.v_dano se lee UNA sola vez para D1 y D2 (es la vista más cara): los abiertos o en atención y los atendidos de los últimos días
    select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'riesgo', coalesce(x.riesgo, 'medio'), 't', x.t_detectado, 'estado', x.estado,
                                                 'fin', coalesce(x.t_restablecido, x.registrado_en),
                                                 'itv', x.estado = 'atendido' and exists (select 1 from redes.intervenciones i where i.dano_id = x.id))), '[]'::jsonb) into v_dz
      from redes.v_dano x
     where x.t_detectado <= v_ahora
       and (x.estado in ('reportado', 'en_atencion')
            or (x.estado = 'atendido' and coalesce(x.t_restablecido, x.registrado_en) >= v_ahora - make_interval(days => floor(tecnica.f_aparam('dano_sin_itv_dias'))::integer)));
    with d as (
      select z.codigo, z.riesgo, z.t as t_detectado, extract(epoch from v_ahora - z.t)::numeric / 3600 as h
        from jsonb_to_recordset(v_dz) z(codigo text, riesgo text, t timestamptz, estado text) where z.estado in ('reportado', 'en_atencion')),
    n as (
      select d.*, case when d.h >= tecnica.f_aparam('dano_' || d.riesgo || '_rojo_h') then 'rojo'
                       when d.h >= tecnica.f_aparam('dano_' || d.riesgo || '_naranja_h') then 'naranja' end as nivel from d)
    select jsonb_agg(z.a) into v_items
      from (select jsonb_build_object('clave', 'danos_' || n.nivel, 'area', 'distribucion', 'nivel', n.nivel, 'orden', case n.nivel when 'rojo' then 100 else 101 end,
                     'titulo', case when n.nivel = 'rojo' and count(*) = 1 then '1 daño abierto pasó su plazo'
                                    when n.nivel = 'rojo' then count(*) || ' daños abiertos pasaron su plazo'
                                    when count(*) = 1 then '1 daño abierto se acerca a su plazo'
                                    else count(*) || ' daños abiertos se acercan a su plazo' end,
                     'detalle', format('Plazos: riesgo alto %s y %s h; medio %s y %s h; bajo %s y %s h.', tecnica.f_aparam('dano_alto_naranja_h'), tecnica.f_aparam('dano_alto_rojo_h'),
                                       tecnica.f_aparam('dano_medio_naranja_h'), tecnica.f_aparam('dano_medio_rojo_h'), tecnica.f_aparam('dano_bajo_naranja_h'), tecnica.f_aparam('dano_bajo_rojo_h')),
                     'n', count(*),
                     'items', (array_to_json((array_agg(n.codigo || ' · riesgo ' || n.riesgo || ' · abierto hace ' || tecnica.f_texto_horas(n.h)
                                                        order by case n.riesgo when 'alto' then 1 when 'medio' then 2 else 3 end, n.h desc))[1:5]))::jsonb,
                     'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'danos'), 'desde', min(n.t_detectado)) as a
              from n where n.nivel is not null group by n.nivel) z;
    v_av := v_av || coalesce(v_items, '[]'::jsonb);

    -- D2. Daños atendidos en los últimos días sin ninguna intervención registrada
    select count(*), coalesce((array_to_json((array_agg(z.codigo order by z.fin desc))[1:5]))::jsonb, '[]'::jsonb) into v_n, v_items
      from jsonb_to_recordset(v_dz) z(codigo text, estado text, fin timestamptz, itv boolean)
     where z.estado = 'atendido' and not z.itv;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'danos_sin_intervencion', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 110,
                'titulo', format('%s sin intervención registrada', tecnica.f_cuantos(v_n, 'daño atendido', 'daños atendidos')),
                'detalle', format('Atendidos en los últimos %s días.', tecnica.f_aparam('dano_sin_itv_dias')),
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'danos'), 'desde', null);
    end if;

    -- D3. Daños e intervenciones con el activo no identificado (por asociar o crear)
    select count(*), coalesce((array_to_json((array_agg(x.codigo order by x.registrado_en))[1:5]))::jsonb, '[]'::jsonb), min(x.registrado_en) into v_n, v_items, v_desde
      from redes.v_no_identificados x;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'no_identificados', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 120,
                'titulo', format('%s con el activo sin identificar', tecnica.f_cuantos(v_n, 'registro', 'registros')), 'detalle', 'Daños o intervenciones por asociar a un activo.',
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'no_identificados'), 'desde', v_desde);
    end if;

    -- D4. Intervenciones con los recursos sin completar
    select count(*), coalesce((array_to_json((array_agg(x.codigo order by x.registrado_en))[1:5]))::jsonb, '[]'::jsonb), min(x.registrado_en) into v_n, v_items, v_desde
      from redes.v_intervencion x where x.estado <> 'oculta' and x.recursos = 'por_completar';
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'recursos_por_completar', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 130,
                'titulo', format('%s con los recursos sin completar', tecnica.f_cuantos(v_n, 'intervención', 'intervenciones')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'intervenciones'), 'desde', v_desde);
    end if;

    -- D5. Reportes del bot sin convertir ni descartar
    select count(*), coalesce((array_to_json((array_agg(coalesce(x.radicado, 'Sin radicado') || ' · hace ' || tecnica.f_texto_horas(extract(epoch from v_ahora - x.recibido_en)::numeric / 3600)
                                                        order by x.recibido_en))[1:5]))::jsonb, '[]'::jsonb), min(x.recibido_en) into v_n, v_items, v_desde
      from redes.v_reporte_externo x where x.ultimo_evento = 'recibido';
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'reportes_bot', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 140,
                'titulo', format('%s sin atender', tecnica.f_cuantos(v_n, 'reporte del bot', 'reportes del bot')), 'detalle', 'Convertir en daño o descartar con motivo.',
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'bot'), 'desde', v_desde);
    end if;

    -- D6. Línea 116: reportes en «Registrado» desde hace más de N días. Queda listo y APAGADO hasta que el Corte 5d esté publicado (sin su tabla no hay aviso).
    if to_regclass('redes.l116_vigente') is not null then
      execute 'select count(*), min(estado_desde) from redes.l116_vigente where not oculto and estado = ''registrado'' and estado_desde < $1'
         into v_n, v_desde using v_ahora - make_interval(days => floor(tecnica.f_aparam('l116_registrado_dias'))::integer);
      if v_n > 0 then
        v_av := v_av || jsonb_build_object('clave', 'l116_registrado', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 150,
                  'titulo', format('%s de la línea 116 en «Registrado» hace más de %s días', tecnica.f_cuantos(v_n, 'reporte', 'reportes'), tecnica.f_aparam('l116_registrado_dias')),
                  'detalle', 'La línea 116 es de referencia: el cierre lo hace el sistema comercial.',
                  'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', v_desde);
      end if;
    end if;

    -- D7. Cargas de capas abiertas sin publicar ni anular
    select count(*), coalesce((array_to_json((array_agg(x.capa_codigo || ' · abierta hace ' || tecnica.f_texto_horas(extract(epoch from v_ahora - x.creado_en)::numeric / 3600) order by x.creado_en))[1:5]))::jsonb, '[]'::jsonb),
           min(x.creado_en) into v_n, v_items, v_desde
      from redes.v_cargas_estado x where x.estado = 'abierta' and x.creado_en < v_ahora - make_interval(secs => (tecnica.f_aparam('carga_abierta_horas') * 3600)::double precision);
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'cargas_abiertas', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 160,
                'titulo', format('%s del Cargue de capas sin publicar', tecnica.f_cuantos(v_n, 'carga abierta', 'cargas abiertas')), 'detalle', null,
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'cargue'), 'desde', v_desde);
    end if;

    -- D8. Activos «por verificar» (la misma regla de la bandeja: el último evento de verificación es «por_verificar» y el activo no está retirado)
    select count(*) into v_n
      from (select distinct on (e.activo_id) e.activo_id, e.tipo from redes.activo_eventos e where e.tipo in ('verificar', 'por_verificar') order by e.activo_id, e.id desc) u
     where u.tipo = 'por_verificar' and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = u.activo_id and not m.retirado);
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'por_verificar', 'area', 'distribucion', 'nivel', 'info', 'orden', 170,
                'titulo', format('%s por verificar', tecnica.f_cuantos(v_n, 'activo', 'activos')), 'detalle', null,
                'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'por_verificar'), 'desde', null);
    end if;

    -- D9. Nodos por clasificar
    select count(*) into v_n from redes.v_nodo_visible x where x.clase_nodo = 'por_clasificar';
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'nodos_por_clasificar', 'area', 'distribucion', 'nivel', 'info', 'orden', 180,
                'titulo', format('%s por clasificar', tecnica.f_cuantos(v_n, 'nodo', 'nodos')), 'detalle', null,
                'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', 'nodos'), 'desde', null);
    end if;
  end if;

  -- ===================== PERSONAL (los dos supervisores y el administrador) =====================
  if p_planta or p_distribucion then
    for r in
      with pob as (
        select lb.email, coalesce(nullif(btrim(lb.nombre), ''), lb.email) as nombre,
               (lb.ver_registro_tecnico and not lb.ver_dashboard_tecnico and not lb.ver_dashboard_redes) as operador, f.area, f.cuadrilla_id
          from public.geoportal_lista_blanca lb left join redes.v_personal_ficha f on f.persona = lb.email
         where lb.activo and lb.rol <> 'admin' and (lb.ver_registro_tecnico or lb.ver_dashboard_redes or lb.ver_dashboard_tecnico) and tecnica.f_tecnica_activa(lb.email)),
      cat as (
        select 'personal_sin_formularios' as clave, 300 as orden, 'persona activa sin formularios' as uno, 'personas activas sin formularios' as varios, p.nombre
          from pob p
         where p.operador and not exists (select 1 from (select distinct on (e.formulario) e.tipo_evento from tecnica.personal_tecnico_eventos e
                                                         where e.persona = p.email and e.tipo_evento in ('asignar_formulario', 'quitar_formulario') and e.formulario is not null
                                                         order by e.formulario, e.id desc) x where x.tipo_evento = 'asignar_formulario')
        union all select 'personal_sin_area', 301, 'persona activa sin área', 'personas activas sin área', p.nombre from pob p where p.area is null
        union all select 'personal_sin_cuadrilla', 302, 'persona de distribución sin cuadrilla', 'personas de distribución sin cuadrilla', p.nombre
          from pob p where p.operador and p.area in ('distribucion', 'ambas') and p.cuadrilla_id is null)
      select c.clave, c.orden, count(*) as n, min(c.uno) as uno, min(c.varios) as varios, (array_to_json((array_agg(c.nombre order by lower(c.nombre)))[1:5]))::jsonb as items
        from cat c group by c.clave, c.orden order by c.orden
    loop
      v_av := v_av || jsonb_build_object('clave', r.clave, 'area', 'personal', 'nivel', 'naranja', 'orden', r.orden,
                'titulo', tecnica.f_cuantos(r.n, r.uno, r.varios), 'detalle', null, 'n', r.n, 'items', r.items,
                'bandeja', jsonb_build_object('tablero', 'personal', 'pestana', 'personal'), 'desde', null);
    end loop;
  end if;

  return coalesce((select jsonb_agg(a order by case a ->> 'nivel' when 'rojo' then 1 when 'naranja' then 2 else 3 end, (a ->> 'orden')::integer, a ->> 'clave')
                     from jsonb_array_elements(v_av) a), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- COLA DE SALIDA (bot de avisos del Dell). Solo los daños de riesgo alto abiertos o en atención: un aviso al aparecer («nuevo»), otro al pasar a naranja
-- y otro al pasar a rojo. Si el daño ya pasó un nivel cuando se ve por primera vez, solo sale el más alto. La base encola cuando el Dell pide.
-- ---------------------------------------------------------------------
create function tecnica.f_nivel_rango(p_nivel text) returns integer language sql immutable set search_path to 'pg_catalog' as $$
  select case p_nivel when 'nuevo' then 1 when 'naranja' then 2 when 'rojo' then 3 end $$;

create function tecnica.f_avisos_encolar(p_ahora timestamptz default null) returns integer
language plpgsql security definer set search_path to 'public', 'tecnica', 'redes', 'pg_temp' as $$
declare v_ahora timestamptz := coalesce(p_ahora, clock_timestamp()); d record; v_nivel text; v_id uuid; v_n integer := 0;
begin
  for d in select x.id, x.codigo, x.tipo_nombre, x.sistema, x.estado, x.t_detectado, n.sector_num, extract(epoch from v_ahora - x.t_detectado)::numeric / 3600 as h
             from redes.v_dano x join redes.danos n on n.id = x.id
            where x.riesgo = 'alto' and x.estado in ('reportado', 'en_atencion') and x.t_detectado <= v_ahora loop
    v_nivel := case when d.h >= tecnica.f_aparam('dano_alto_rojo_h') then 'rojo' when d.h >= tecnica.f_aparam('dano_alto_naranja_h') then 'naranja' else 'nuevo' end;
    if exists (select 1 from tecnica.avisos_salida a where a.tipo = 'dano_alto' and a.ref_id = d.id and tecnica.f_nivel_rango(a.nivel) >= tecnica.f_nivel_rango(v_nivel)) then continue; end if;
    v_id := null;
    insert into tecnica.avisos_salida (clave, tipo, nivel, area, ref_id, mensaje)
    values ('dano_alto:' || d.id || ':' || v_nivel, 'dano_alto', v_nivel, 'distribucion', d.id,
            jsonb_build_object('titulo', case v_nivel when 'nuevo' then 'Daño de riesgo alto reportado' when 'naranja' then 'Daño de riesgo alto abierto hace ' || tecnica.f_texto_horas(d.h)
                                                     else 'Daño de riesgo alto pasó su plazo: abierto hace ' || tecnica.f_texto_horas(d.h) end,
                               'dano', d.codigo, 'tipo', d.tipo_nombre, 'sistema', d.sistema, 'riesgo', 'alto', 'nivel', v_nivel, 'estado', d.estado,
                               'horas_abierto', round(d.h, 1), 'detectado_bogota', to_char(d.t_detectado at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'), 'sector', d.sector_num))
    on conflict (clave) do nothing
    returning id into v_id;
    if v_id is not null then
      insert into tecnica.aviso_salida_eventos (aviso_id, estado, actor, detalle) values (v_id, 'pendiente', 'sistema', jsonb_build_object('motivo', 'encolado'));
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $$;

-- El Dell toma hasta p_limite avisos (FOR UPDATE SKIP LOCKED): primero encola lo nuevo; anula los de daños que ya no están abiertos; deja en error los arriendos
-- vencidos que agotaron sus intentos. Cada toma suma un intento y da un lease_id nuevo. Sin filas = nada que enviar.
create function tecnica.avisos_tomar(p_limite integer default 5, p_arriendo_segundos integer default 300)
returns table (aviso_id uuid, lease_id uuid, creado_en timestamptz, tipo text, nivel text, area text, mensaje jsonb, intentos integer)
language plpgsql security definer set search_path to 'public', 'tecnica', 'redes', 'pg_temp' as $$
declare v_max integer := floor(tecnica.f_aparam('salida_max_intentos'))::integer; r record; v_tomados uuid[] := '{}'; v_intentos integer; v_vivos uuid[];
begin
  if p_limite is null or p_limite < 1 or p_limite > 20 then raise exception 'p_limite va de 1 a 20' using errcode = '22023'; end if;
  if p_arriendo_segundos is null or p_arriendo_segundos < 30 or p_arriendo_segundos > 3600 then raise exception 'p_arriendo_segundos va de 30 a 3600' using errcode = '22023'; end if;
  perform tecnica.f_avisos_encolar();
  v_vivos := array(select x.id from redes.v_dano x where x.riesgo = 'alto' and x.estado in ('reportado', 'en_atencion'));      -- una sola lectura de la vista
  for r in select a.id, a.ref_id, u.estado
             from tecnica.avisos_salida a
             cross join lateral (select e.estado, e.tomado_hasta from tecnica.aviso_salida_eventos e where e.aviso_id = a.id order by e.id desc limit 1) u
            where u.estado = 'pendiente' or (u.estado = 'tomado' and u.tomado_hasta < clock_timestamp())
            order by a.creado_en, a.id
              for update of a skip locked loop
    select v.intentos into v_intentos from tecnica.v_avisos_salida v where v.id = r.id;
    if not (r.ref_id = any (v_vivos)) then
      insert into tecnica.aviso_salida_eventos (aviso_id, estado, actor, detalle) values (r.id, 'anulado', 'sistema', jsonb_build_object('motivo', 'dano_cerrado'));
    elsif v_intentos >= v_max then
      insert into tecnica.aviso_salida_eventos (aviso_id, estado, actor, detalle) values (r.id, 'error', 'sistema', jsonb_build_object('motivo', 'intentos_agotados'));
    elsif cardinality(v_tomados) < p_limite then
      insert into tecnica.aviso_salida_eventos (aviso_id, estado, lease_id, tomado_hasta, actor, detalle)
      values (r.id, 'tomado', gen_random_uuid(), clock_timestamp() + make_interval(secs => p_arriendo_segundos), 'dell', '{}'::jsonb);
      v_tomados := v_tomados || r.id;
    end if;
  end loop;
  return query select v.id, v.lease_id, v.creado_en, v.tipo, v.nivel, v.area, v.mensaje, v.intentos
                 from tecnica.v_avisos_salida v where v.id = any (v_tomados) order by v.creado_en, v.id;
end $$;

-- Cierra un aviso tomado: 'enviado' o 'error' (con p_reintentable vuelve a 'pendiente' mientras queden intentos). Repetir el mismo cierre es inocuo.
create function tecnica.avisos_marcar(p_aviso_id uuid, p_lease_id uuid, p_estado text, p_detalle jsonb default '{}'::jsonb, p_reintentable boolean default false) returns text
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v record; v_det jsonb := coalesce(p_detalle, '{}'::jsonb); v_nuevo text;
begin
  if p_estado is null or p_estado not in ('enviado', 'error') then raise exception 'Estado no válido: use enviado o error' using errcode = '22023'; end if;
  if jsonb_typeof(v_det) <> 'object' or length(v_det::text) > 2000 then raise exception 'El detalle es un objeto de hasta 2 KB' using errcode = '22023'; end if;
  perform 1 from tecnica.avisos_salida a where a.id = p_aviso_id for update;
  if not found then raise exception 'Ese aviso no existe' using errcode = 'P0002'; end if;
  select * into v from tecnica.v_avisos_salida x where x.id = p_aviso_id;
  if v.estado = p_estado then return v.estado; end if;
  if v.estado <> 'tomado' then raise exception 'El aviso no está tomado (estado %)', v.estado using errcode = '22023'; end if;
  if v.lease_id is distinct from p_lease_id then raise exception 'El lease_id no coincide: el aviso lo tomó otro ciclo' using errcode = '22023'; end if;
  v_nuevo := case when p_estado = 'error' and coalesce(p_reintentable, false) and v.intentos < floor(tecnica.f_aparam('salida_max_intentos')) then 'pendiente' else p_estado end;
  insert into tecnica.aviso_salida_eventos (aviso_id, estado, actor, detalle)
  values (p_aviso_id, v_nuevo, 'dell', (v_det - 'motivo') || case when v_nuevo = 'pendiente' then jsonb_build_object('motivo', 'reintento') else '{}'::jsonb end);
  return v_nuevo;
end $$;

-- Devuelve un aviso tomado a 'pendiente' sin gastar intento (el Dell se apaga o no puede enviar ahora)
create function tecnica.avisos_liberar(p_aviso_id uuid, p_lease_id uuid) returns text
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v record;
begin
  perform 1 from tecnica.avisos_salida a where a.id = p_aviso_id for update;
  if not found then raise exception 'Ese aviso no existe' using errcode = 'P0002'; end if;
  select * into v from tecnica.v_avisos_salida x where x.id = p_aviso_id;
  if v.estado = 'pendiente' then return v.estado; end if;
  if v.estado <> 'tomado' then raise exception 'El aviso no está tomado (estado %)', v.estado using errcode = '22023'; end if;
  if v.lease_id is distinct from p_lease_id then raise exception 'El lease_id no coincide: el aviso lo tomó otro ciclo' using errcode = '22023'; end if;
  insert into tecnica.aviso_salida_eventos (aviso_id, estado, actor, detalle) values (p_aviso_id, 'pendiente', 'dell', jsonb_build_object('motivo', 'liberado'));
  return 'pendiente';
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 30 — RPC (solo las llama la Edge geoportal-tecnica con service_role; el solicitante es el correo del token)
-- · geoportal_tec_avisos: todos los avisos de la persona, en una sola consulta (menos de 1 s en producción: el ensayo lo mide).
-- · geoportal_tec_avisos_parametros y geoportal_tec_aviso_parametro_fijar: los plazos y mínimos (cada supervisor los de su área; el administrador todos).
-- · geoportal_tec_quimico_minimos y geoportal_tec_quimico_minimo_fijar: el saldo mínimo de cada químico (supervisor de planta y administrador).
-- =====================================================================
create function public.geoportal_tec_avisos(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare p record; v jsonb; t0 timestamptz := clock_timestamp();
begin
  select * into p from tecnica.f_avisos_perfil(p_solicitante);
  v := tecnica.f_avisos(p.planta, p.distribucion, null);
  return jsonb_build_object('areas', jsonb_build_object('planta', p.planta, 'distribucion', p.distribucion, 'personal', true), 'admin', p.admin,
    'avisos', v, 'total', jsonb_array_length(v),
    'rojos', (select count(*) from jsonb_array_elements(v) a where a ->> 'nivel' = 'rojo'),
    'naranjas', (select count(*) from jsonb_array_elements(v) a where a ->> 'nivel' = 'naranja'),
    'calculado_en', clock_timestamp(), 'ms', round(extract(epoch from clock_timestamp() - t0)::numeric * 1000));
end $$;

create function public.geoportal_tec_avisos_parametros(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare p record;
begin
  select * into p from tecnica.f_avisos_perfil(p_solicitante);
  return jsonb_build_object('puede_minimos', p.planta, 'parametros', coalesce((
    select jsonb_agg(jsonb_build_object('clave', a.clave, 'area', a.area, 'nombre', a.nombre, 'descripcion', a.descripcion, 'valor', a.valor, 'minimo', a.minimo, 'maximo', a.maximo,
             'unidad', a.unidad, 'ultimo', (select jsonb_build_object('antes', e.antes, 'despues', e.despues, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en)
                                              from tecnica.aviso_parametro_eventos e where e.clave = a.clave order by e.id desc limit 1)) order by a.orden)
      from tecnica.aviso_parametros a
     where p.admin or (a.area = 'planta' and p.planta) or (a.area = 'distribucion' and p.distribucion)), '[]'::jsonb));
end $$;

create function public.geoportal_tec_aviso_parametro_fijar(p_solicitante text, p_clave text, p_valor numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare p record; a tecnica.aviso_parametros; v_mot text := btrim(coalesce(p_motivo, '')); v_par text; v_otro numeric;
begin
  select * into p from tecnica.f_avisos_perfil(p_solicitante);
  select * into a from tecnica.aviso_parametros where clave = p_clave for update;
  if not found then perform tecnica.f_error('Ese parámetro no existe'); end if;
  if not (p.admin or (a.area = 'planta' and p.planta) or (a.area = 'distribucion' and p.distribucion)) then
    perform tecnica.f_error('Ese parámetro lo cambia el supervisor de su área o el administrador', '42501');
  end if;
  if p_valor is null or p_valor <> trunc(p_valor) then perform tecnica.f_error('Escriba un número entero'); end if;
  if p_valor < a.minimo or p_valor > a.maximo then perform tecnica.f_error(format('El valor va de %s a %s %s', a.minimo, a.maximo, a.unidad)); end if;
  if p_valor = a.valor then perform tecnica.f_error('Ese ya es el valor vigente'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 caracteres)'); end if;
  -- coherencia: el horario empieza antes de terminar; el primer registro cae dentro del horario; en cada riesgo, naranja antes que rojo
  if p_clave = 'horario_inicio' and p_valor >= tecnica.f_aparam('horario_fin') then perform tecnica.f_error('El inicio del horario debe ser antes del fin'); end if;
  if p_clave = 'horario_fin' and p_valor <= tecnica.f_aparam('horario_inicio') then perform tecnica.f_error('El fin del horario debe ser después del inicio'); end if;
  if p_clave = 'planta_primer_registro_hora' and (p_valor < tecnica.f_aparam('horario_inicio') or p_valor >= tecnica.f_aparam('horario_fin')) then
    perform tecnica.f_error('La hora límite del primer registro debe caer dentro del horario del personal');
  end if;
  if p_clave ~ '^dano_(alto|medio|bajo)_(naranja|rojo)_h$' then
    v_par := regexp_replace(p_clave, '_(naranja|rojo)_h$', '') || case when p_clave like '%naranja%' then '_rojo_h' else '_naranja_h' end;
    v_otro := tecnica.f_aparam(v_par);
    if (p_clave like '%naranja%' and p_valor >= v_otro) or (p_clave like '%rojo%' and p_valor <= v_otro) then perform tecnica.f_error('El plazo naranja debe ser menor que el rojo'); end if;
  end if;
  insert into tecnica.aviso_parametro_eventos (clave, antes, despues, motivo, autor) values (a.clave, a.valor, p_valor, v_mot, p.email);
  update tecnica.aviso_parametros set valor = p_valor where clave = a.clave;
  perform tecnica.f_auditar(p.email, 'tec_aviso_parametro', a.clave, jsonb_build_object('antes', a.valor, 'despues', p_valor), null);
  return jsonb_build_object('clave', a.clave, 'antes', a.valor, 'valor', p_valor);
end $$;

create function public.geoportal_tec_quimico_minimos(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante);
begin
  return jsonb_build_object('quimicos', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', q.codigo, 'nombre', q.nombre, 'saldo_kg', s.saldo_kg, 'minimo_kg', m.minimo_kg,
             'bajo', m.minimo_kg is not null and s.saldo_kg is not null and s.saldo_kg < m.minimo_kg,
             'ultimo', case when m.id is not null then jsonb_build_object('minimo_kg', m.minimo_kg, 'motivo', m.motivo, 'autor', m.autor, 'creado_en', m.creado_en) end)
             order by q.nombre)
      from tecnica.quimicos q
      left join tecnica.v_quimico_saldo s on s.quimico_id = q.id
      left join lateral (select e.id, e.minimo_kg, e.motivo, e.autor, e.creado_en from tecnica.quimico_minimo_eventos e where e.quimico_id = q.id order by e.id desc limit 1) m on true
     where q.activo and q.codigo <> 'otro'), '[]'::jsonb));
end $$;

create function public.geoportal_tec_quimico_minimo_fijar(p_solicitante text, p_codigo text, p_minimo_kg numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo);
        v_mot text := btrim(coalesce(p_motivo, '')); v_antes numeric;
begin
  if q.codigo = 'otro' then perform tecnica.f_error('Elija el químico'); end if;
  if p_minimo_kg is not null and (p_minimo_kg <= 0 or p_minimo_kg > 10000000) then perform tecnica.f_error('El saldo mínimo va de más de 0 a 10.000.000 kg; déjelo vacío para quitarlo'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 caracteres)'); end if;
  perform 1 from tecnica.quimicos x where x.id = q.id for update;
  select e.minimo_kg into v_antes from tecnica.quimico_minimo_eventos e where e.quimico_id = q.id order by e.id desc limit 1;
  if v_antes is not distinct from p_minimo_kg then perform tecnica.f_error(case when p_minimo_kg is null then 'Ese químico no tiene saldo mínimo' else 'Ese ya es el saldo mínimo vigente' end); end if;
  insert into tecnica.quimico_minimo_eventos (quimico_id, minimo_kg, motivo, autor) values (q.id, p_minimo_kg, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'tec_quimico_minimo', q.codigo, jsonb_build_object('antes', v_antes, 'despues', p_minimo_kg), null);
  return jsonb_build_object('codigo', q.codigo, 'antes', v_antes, 'minimo_kg', p_minimo_kg);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vista nuevas: nadie de la API. Las 5 RPC: solo execute a service_role (la Edge geoportal-tecnica). Las internas: nadie.
-- Rol dell_avisos (el bot de avisos del Dell): nace SIN poder conectarse (NOLOGIN) y SIN CLAVE en este archivo. Solo ejecuta tomar, marcar y liberar.
--   Activar o rotar (a mano, fuera del repositorio): alter role dell_avisos login password '<clave>' valid until '<fecha>';   Apagar: alter role dell_avisos nologin;
-- =====================================================================
revoke all on table tecnica.aviso_parametros, tecnica.aviso_parametro_eventos, tecnica.quimico_minimo_eventos, tecnica.avisos_salida, tecnica.aviso_salida_eventos, tecnica.v_avisos_salida
  from public, anon, authenticated, service_role;
revoke all on sequence tecnica.aviso_parametro_eventos_id_seq, tecnica.quimico_minimo_eventos_id_seq, tecnica.aviso_salida_eventos_id_seq from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma, p.proname from pg_proc p
            where (p.pronamespace = 'tecnica'::regnamespace and p.proname in ('f_aparam', 'f_cuantos', 'f_texto_horas', 'f_texto_num', 'f_avisos_perfil', 'f_avisos', 'f_nivel_rango',
                                                                                'f_avisos_encolar', 'avisos_tomar', 'avisos_marcar', 'avisos_liberar'))
               or (p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_tec_avisos', 'geoportal_tec_avisos_parametros', 'geoportal_tec_aviso_parametro_fijar',
                                                                               'geoportal_tec_quimico_minimos', 'geoportal_tec_quimico_minimo_fijar')) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    if f.proname like 'geoportal\_tec\_%' then execute format('grant execute on function %s to service_role', f.firma); end if;
  end loop;
end $$;

create role dell_avisos nologin noinherit nosuperuser nocreatedb nocreaterole nobypassrls connection limit 2;
alter role dell_avisos set statement_timeout = '15s';
alter role dell_avisos set lock_timeout = '8s';
alter role dell_avisos set search_path = pg_catalog;
grant usage on schema tecnica to dell_avisos;
grant execute on function tecnica.avisos_tomar(integer, integer), tecnica.avisos_marcar(uuid, uuid, text, jsonb, boolean), tecnica.avisos_liberar(uuid, uuid) to dell_avisos;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@tecnica_corte12', 'migracion_tecnica_corte12', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.aviso_parametros', 'tecnica.aviso_parametro_eventos',
        'tecnica.quimico_minimo_eventos', 'tecnica.avisos_salida', 'tecnica.aviso_salida_eventos'), 'rpc_nuevas', 5, 'rol', 'dell_avisos (nologin)'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de la migración, en la misma transacción.
-- Arma sus personas (prueba.tec12.*), su planta («ZT12 Planta»), sus puntos (MUE-9121…), su químico, sus daños (DAN-9912xx), su intervención (ITV-9912xx),
-- su reporte del bot y su carga. No depende de los datos reales: cada prueba compara el conteo del aviso antes y después de lo que ella misma crea.
-- Mide el tiempo de la consulta de avisos con el volumen real y FALLA si pasa de 1 s. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · CORTE 12 … RESULTADO: N de N pruebas correctas — SIN FALLAS  (y la línea TIEMPOS)
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
-- el aviso de una clave (o nulo) y su conteo (0 si no está)
create function pg_temp.av(j jsonb, k text) returns jsonb language sql as $$ select a from jsonb_array_elements(coalesce(j, '[]'::jsonb)) a where a ->> 'clave' = k limit 1 $$;
create function pg_temp.n(j jsonb, k text) returns integer language sql as $$ select coalesce((pg_temp.av(j, k) ->> 'n')::integer, 0) $$;
-- una hora de HOY en Bogotá (8.5 = 8:30 a. m.)
create function pg_temp.h(p numeric) returns timestamptz language sql as
$$ select (((clock_timestamp() at time zone 'America/Bogota')::date)::timestamp + make_interval(mins => (p * 60)::integer)) at time zone 'America/Bogota' $$;
-- un PDF «subido» para la ficha de un químico
create function pg_temp.pdf(p_quien text) returns text language plpgsql as $$
declare v text := public.geoportal_tec_quimico_ficha_preparar(p_quien) ->> 'ruta';
begin
  insert into storage.objects (bucket_id, name, metadata) values ('tecnica-evidencias', v, '{"size": 300000, "mimetype": "application/pdf"}'::jsonb);
  return v;
end $$;

do $prueba$
declare
  a text := 'prueba.tec12.adm@emdupar.gov.co'; sp text := 'prueba.tec12.planta@emdupar.gov.co'; sd text := 'prueba.tec12.dist@emdupar.gov.co';
  op text := 'prueba.tec12.op@emdupar.gov.co'; op2 text := 'prueba.tec12.op2@emdupar.gov.co'; dz text := 'prueba.tec12.desactivada@emdupar.gov.co';
  v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_pl bigint; v_pt bigint; v_pt2 bigint; v_act bigint; v_act2 bigint; v_tipo text; v_cod text; v_rep uuid; v_carga bigint; v_reg bigint;
  d_alto uuid := gen_random_uuid(); d_medio uuid := gen_random_uuid(); d_bajo uuid := gen_random_uuid(); d_nuevo uuid := gen_random_uuid(); d_viejo uuid := gen_random_uuid(); d_ni uuid := gen_random_uuid();
  v_redes text; v_j jsonb; v_j0 jsonb; v_j1 jsonb; v_x jsonb; v_t timestamptz; v_ms numeric; v_ms_adm numeric := 0; v_ms_sp numeric := 0; v_ms_sd numeric := 0; v_i integer;
  v_lease uuid; v_e1 text; v_e2 text; v_av uuid; v_av2 uuid; v_n0 integer; v_n1 integer;
  v_total integer; v_bien integer; v_fallas text;
begin
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v_redes from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');

  -- ===================== 00. TIEMPO con los datos reales (antes de crear nada) =====================
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT12 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZT12 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_dashboard_redes, horario, dias) values (sd, 'ZT12 Supervisor de distribución', 'consulta', true, 'sin_restriccion', 'todos');
  for v_i in 1..3 loop
    v_t := clock_timestamp(); v_j := public.geoportal_tec_avisos(a); v_ms := extract(epoch from clock_timestamp() - v_t) * 1000; v_ms_adm := greatest(v_ms_adm, v_ms);
    v_t := clock_timestamp(); perform public.geoportal_tec_avisos(sp); v_ms := extract(epoch from clock_timestamp() - v_t) * 1000; v_ms_sp := greatest(v_ms_sp, v_ms);
    v_t := clock_timestamp(); perform public.geoportal_tec_avisos(sd); v_ms := extract(epoch from clock_timestamp() - v_t) * 1000; v_ms_sd := greatest(v_ms_sd, v_ms);
  end loop;
  perform pg_temp.reg('00.01 TIEMPO: todos los avisos del administrador en una sola consulta, con el volumen real, en menos de 1 s (el peor de 3)', v_ms_adm < 1000, round(v_ms_adm) || ' ms');
  perform pg_temp.reg('00.02 TIEMPO: los de cada supervisor también en menos de 1 s', v_ms_sp < 1000 and v_ms_sd < 1000, round(v_ms_sp) || ' ms y ' || round(v_ms_sd) || ' ms');

  -- personas y datos de la prueba
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT12 Operador', 'consulta', true, 'sin_restriccion', 'todos'),
         (dz, 'ZT12 Supervisor desactivado', 'consulta', true, 'sin_restriccion', 'todos');
  update public.geoportal_lista_blanca set ver_dashboard_tecnico = true where email = dz;
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, autor) values (dz, 'desactivar_tecnica', a);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'uso_quimicos', a);
  insert into tecnica.plantas (codigo, nombre, activa) values ('zt12_planta', 'ZT12 Planta', true) returning id into v_pl;
  select codigo into v_tipo from redes.tipos_dano where activo and 'acueducto' = any (sistemas) order by orden limit 1;
  select m.activo_id into v_act from redes.activo_vigente_mat m where m.sistema = 'acueducto' and not m.retirado and not m.oculto order by m.activo_id limit 1;
  select m.activo_id into v_act2 from redes.activo_vigente_mat m where not m.retirado
     and not exists (select 1 from redes.activo_eventos e where e.activo_id = m.activo_id and e.tipo in ('verificar', 'por_verificar')) order by m.activo_id desc limit 1;

  -- ===================== 01. Estructura y permisos =====================
  perform pg_temp.reg('01.01 los 15 plazos y mínimos con los valores de David: horario 8 a 18, alto 2 y 6 h, medio 24 y 72 h, bajo 72 y 168 h, 116 a 3 días',
     (select count(*) from tecnica.aviso_parametros) = 15 and tecnica.f_aparam('horario_inicio') = 8 and tecnica.f_aparam('horario_fin') = 18
     and tecnica.f_aparam('dano_alto_naranja_h') = 2 and tecnica.f_aparam('dano_alto_rojo_h') = 6 and tecnica.f_aparam('dano_medio_naranja_h') = 24 and tecnica.f_aparam('dano_medio_rojo_h') = 72
     and tecnica.f_aparam('dano_bajo_naranja_h') = 72 and tecnica.f_aparam('dano_bajo_rojo_h') = 168 and tecnica.f_aparam('l116_registrado_dias') = 3);
  perform pg_temp.err('01.02 un plazo no se borra', $$delete from tecnica.aviso_parametros where clave = 'horario_inicio'$$, '42501');
  perform pg_temp.reg('01.05b los números de los avisos van como en Técnica (punto de miles, coma decimal), sin depender del idioma de la base',
     tecnica.f_texto_num(2000) = '2.000' and tecnica.f_texto_num(0.05) = '0,05' and tecnica.f_texto_num(1234567.891) = '1.234.567,89' and tecnica.f_texto_num(-1500.5) = '-1.500,5'
     and tecnica.f_texto_horas(0.5) = 'menos de 1 h' and tecnica.f_texto_horas(7.9) = '7 h' and tecnica.f_texto_horas(200) = '8 días');
  perform pg_temp.reg('01.06 el rol del Dell nace sin poder conectarse, con 2 conexiones, y solo ejecuta tomar, marcar y liberar',
     (select not rolcanlogin and rolconnlimit = 2 and not rolsuper and not rolbypassrls from pg_roles where rolname = 'dell_avisos')
     and has_function_privilege('dell_avisos', 'tecnica.avisos_tomar(integer,integer)', 'execute') and has_function_privilege('dell_avisos', 'tecnica.avisos_marcar(uuid,uuid,text,jsonb,boolean)', 'execute')
     and has_function_privilege('dell_avisos', 'tecnica.avisos_liberar(uuid,uuid)', 'execute')
     and not has_function_privilege('dell_avisos', 'public.geoportal_tec_avisos(text)', 'execute') and not has_function_privilege('dell_avisos', 'tecnica.f_avisos(boolean,boolean,timestamptz)', 'execute')
     and not has_table_privilege('dell_avisos', 'tecnica.avisos_salida', 'select') and not has_table_privilege('dell_avisos', 'tecnica.registros', 'select'));
  perform pg_temp.reg('01.07 la API: service_role solo ejecuta las 5 RPC; anon y authenticated nada; nadie de la API lee las tablas ni toma la cola',
     has_function_privilege('service_role', 'public.geoportal_tec_avisos(text)', 'execute') and has_function_privilege('service_role', 'public.geoportal_tec_quimico_minimo_fijar(text,text,numeric,text)', 'execute')
     and not has_function_privilege('anon', 'public.geoportal_tec_avisos(text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_tec_avisos(text)', 'execute')
     and not has_function_privilege('service_role', 'tecnica.avisos_tomar(integer,integer)', 'execute') and not has_function_privilege('service_role', 'tecnica.f_avisos(boolean,boolean,timestamptz)', 'execute')
     and not has_table_privilege('service_role', 'tecnica.aviso_parametros', 'select') and not has_table_privilege('service_role', 'tecnica.avisos_salida', 'select')
     and not has_table_privilege('authenticated', 'tecnica.quimico_minimo_eventos', 'select'));

  -- ===================== 02. Quién ve qué =====================
  perform pg_temp.err('02.01 el operador no ve avisos', format($$select public.geoportal_tec_avisos(%L)$$, op), '42501');
  perform pg_temp.err('02.02 un supervisor con Técnica desactivada no ve avisos', format($$select public.geoportal_tec_avisos(%L)$$, dz), '42501', 'desactivado');
  perform pg_temp.err('02.03 alguien que no está en la lista blanca, tampoco', $$select public.geoportal_tec_avisos('prueba.tec12.nadie@emdupar.gov.co')$$, '42501');
  v_j := public.geoportal_tec_avisos(sp);
  perform pg_temp.reg('02.04 supervisor de planta: Plantas y Personal, nada de Distribución',
     (v_j -> 'areas' ->> 'planta')::boolean and not (v_j -> 'areas' ->> 'distribucion')::boolean
     and not exists (select 1 from jsonb_array_elements(v_j -> 'avisos') x where x ->> 'area' = 'distribucion'), (v_j -> 'areas')::text);
  v_j := public.geoportal_tec_avisos(sd);
  perform pg_temp.reg('02.05 supervisor de distribución: Distribución y Personal, nada de Plantas',
     (v_j -> 'areas' ->> 'distribucion')::boolean and not (v_j -> 'areas' ->> 'planta')::boolean
     and not exists (select 1 from jsonb_array_elements(v_j -> 'avisos') x where x ->> 'area' = 'planta'), (v_j -> 'areas')::text);
  v_j := public.geoportal_tec_avisos(a);
  perform pg_temp.reg('02.06 administrador: todo, con el total, los rojos y los naranjas contados; ordenados rojo, naranja e informativo',
     (v_j -> 'areas' ->> 'planta')::boolean and (v_j -> 'areas' ->> 'distribucion')::boolean and (v_j ->> 'total')::integer = jsonb_array_length(v_j -> 'avisos')
     and (v_j ->> 'rojos')::integer = (select count(*) from jsonb_array_elements(v_j -> 'avisos') x where x ->> 'nivel' = 'rojo')
     and not exists (select 1 from jsonb_array_elements(v_j -> 'avisos') with ordinality x(e, i) join jsonb_array_elements(v_j -> 'avisos') with ordinality y(e, k) on y.k = x.i + 1
                      where (case x.e ->> 'nivel' when 'rojo' then 1 when 'naranja' then 2 else 3 end) > (case y.e ->> 'nivel' when 'rojo' then 1 when 'naranja' then 2 else 3 end)));
  perform pg_temp.reg('02.07 cada aviso trae título, nivel, área y su bandeja', not exists (select 1 from jsonb_array_elements(v_j -> 'avisos') x
     where coalesce(x ->> 'titulo', '') = '' or x ->> 'nivel' not in ('rojo', 'naranja', 'info') or x ->> 'area' not in ('planta', 'distribucion', 'personal')
        or x -> 'bandeja' ->> 'tablero' not in ('ptap', 'distribucion', 'personal')));

  -- ===================== 03. Plantas: Entrada y Salida dentro del horario (8 a. m. a 6 p. m.) =====================
  perform pg_temp.reg('03.01 a las 9:30 (antes de la hora límite del primer registro, 10:00) no hay aviso de la planta',
     pg_temp.av(tecnica.f_avisos(true, false, pg_temp.h(9.5)), 'planta_entrada:zt12_planta') is null);
  v_j := tecnica.f_avisos(true, false, pg_temp.h(10.5));
  perform pg_temp.reg('03.02 a las 10:30 sin ningún registro: Entrada y Salida en naranja, «sin el primer registro del día en ZT12 Planta»',
     pg_temp.av(v_j, 'planta_entrada:zt12_planta') ->> 'nivel' = 'naranja' and pg_temp.av(v_j, 'planta_salida:zt12_planta') ->> 'nivel' = 'naranja'
     and pg_temp.av(v_j, 'planta_entrada:zt12_planta') ->> 'titulo' = 'Entrada sin el primer registro del día en ZT12 Planta'
     and pg_temp.av(v_j, 'planta_entrada:zt12_planta') -> 'bandeja' ->> 'pestana' = 'registros', pg_temp.av(v_j, 'planta_entrada:zt12_planta')::text);
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'entrada', v.id, v_pl, 100, v_hoy, time '10:15', op from tecnica.variables v where v.codigo = 'caudal_qi';
  v_j := tecnica.f_avisos(true, false, pg_temp.h(11));
  perform pg_temp.reg('03.03 con un registro de Entrada a las 10:15, a las 11:00 la Entrada desaparece sola y la Salida sigue',
     pg_temp.av(v_j, 'planta_entrada:zt12_planta') is null and pg_temp.av(v_j, 'planta_salida:zt12_planta') is not null);
  v_j := tecnica.f_avisos(true, false, pg_temp.h(14.5));
  perform pg_temp.reg('03.04 a las 14:30 (más de 4 h sin registro dentro del horario): naranja «Entrada sin registro hace 4 h», con la hora del último',
     pg_temp.av(v_j, 'planta_entrada:zt12_planta') ->> 'titulo' = 'Entrada sin registro hace 4 h en ZT12 Planta' and pg_temp.av(v_j, 'planta_entrada:zt12_planta') ->> 'detalle' like '%10:15%',
     pg_temp.av(v_j, 'planta_entrada:zt12_planta')::text);
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'entrada', v.id, v_pl, 100, v_hoy, time '14:00', op from tecnica.variables v where v.codigo = 'caudal_qi' returning id into v_reg;
  insert into tecnica.exclusiones (registro_id, accion, motivo, autor) values (v_reg, 'EXCLUIR', 'ZT12 registro de prueba excluido', sp);
  perform pg_temp.reg('03.05 un registro excluido no cuenta: a las 14:30 sigue el aviso', pg_temp.av(tecnica.f_avisos(true, false, pg_temp.h(14.5)), 'planta_entrada:zt12_planta') is not null);
  perform pg_temp.reg('03.06 a las 12:00 (1 h 45 después del último registro) no hay aviso de Entrada',
     pg_temp.av(tecnica.f_avisos(true, false, pg_temp.h(12)), 'planta_entrada:zt12_planta') is null);
  v_j := tecnica.f_avisos(true, false, pg_temp.h(18.5));
  perform pg_temp.reg('03.07 a las 18:30 (cerró el horario): la Salida sin registros del día en ROJO; la Entrada, que sí tuvo, ya no avisa',
     pg_temp.av(v_j, 'planta_salida:zt12_planta') ->> 'nivel' = 'rojo' and pg_temp.av(v_j, 'planta_salida:zt12_planta') ->> 'titulo' = 'Salida sin registros hoy en ZT12 Planta'
     and pg_temp.av(v_j, 'planta_entrada:zt12_planta') is null);
  perform pg_temp.reg('03.08 a las 7:00 (antes del horario) nada de la planta', pg_temp.av(tecnica.f_avisos(true, false, pg_temp.h(7)), 'planta_salida:zt12_planta') is null);
  perform pg_temp.reg('03.09 el supervisor de distribución no recibe los avisos de la planta', pg_temp.av(tecnica.f_avisos(false, true, pg_temp.h(18.5)), 'planta_salida:zt12_planta') is null);

  -- ===================== 04. Puntos de muestreo =====================
  v_n0 := pg_temp.n(tecnica.f_avisos(true, false, null), 'muestreo_sin_muestra');
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9121', 'ZT12 Uno', 'muestreo', 'norte') returning id into v_pt;
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9122', 'ZT12 Dos', 'muestreo', 'sur') returning id into v_pt2;
  perform pg_temp.reg('04.01 dos puntos nuevos sin muestra: el aviso de puntos sin muestra en 35 días sube en 2',
     pg_temp.n(tecnica.f_avisos(true, false, null), 'muestreo_sin_muestra') = v_n0 + 2, v_n0::text);
  v_n1 := pg_temp.n(tecnica.f_avisos(true, false, null), 'muestreo_fuera_rango');
  insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'muestreo', v.id, v_pt, 0.05, v_hoy - 3, time '09:00', op from tecnica.variables v where v.codigo = 'cloro_residual_libre';
  insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'muestreo', v.id, v_pt2, 1.0, v_hoy - 40, time '09:00', op from tecnica.variables v where v.codigo = 'cloro_residual_libre';
  perform pg_temp.reg('04.02 una muestra de hace 3 días saca al punto del aviso; una de hace 40 días no',
     pg_temp.n(tecnica.f_avisos(true, false, null), 'muestreo_sin_muestra') = v_n0 + 1);
  v_n0 := v_n1;
  insert into tecnica.referencias (variable_id, punto_id, ref_min, ref_max, origen, fuente)
  select id, v_pt, 0.3, 2.0, 'criterio_planta', 'ZT12 referencia de prueba del punto' from tecnica.variables where codigo = 'cloro_residual_libre';
  v_j := tecnica.f_avisos(true, false, null);
  perform pg_temp.reg('04.03 el último cloro (0,05) por debajo del rango del punto (0,3 a 2): el aviso rojo «fuera de rango» sube en 1, con el valor',
     pg_temp.n(v_j, 'muestreo_fuera_rango') = v_n0 + 1 and pg_temp.av(v_j, 'muestreo_fuera_rango') ->> 'nivel' = 'rojo'
     and (v_n0 >= 5 or exists (select 1 from jsonb_array_elements_text(pg_temp.av(v_j, 'muestreo_fuera_rango') -> 'items') t where t like 'MUE-9121 · %0,05%')),
     pg_temp.av(v_j, 'muestreo_fuera_rango')::text);
  v_n0 := pg_temp.n(tecnica.f_avisos(true, false, null), 'ubicaciones_pendientes');
  insert into tecnica.punto_ubicacion_propuestas (punto_id, lat, lon, precision_m, autor) values (v_pt, 10.47, -73.25, 8, op);
  perform pg_temp.reg('04.04 una ubicación propuesta sin revisar: el aviso de ubicaciones por aprobar sube en 1 y lleva a «Puntos» del Dashboard PTAP',
     pg_temp.n(tecnica.f_avisos(true, false, null), 'ubicaciones_pendientes') = v_n0 + 1
     and pg_temp.av(tecnica.f_avisos(true, false, null), 'ubicaciones_pendientes') -> 'bandeja' ->> 'pestana' = 'puntos');

  -- ===================== 05. Químicos =====================
  v_j0 := tecnica.f_avisos(true, false, clock_timestamp() + interval '1 day');
  v_cod := public.geoportal_tec_quimico_crear(sp, 'ZT12 Coagulante', 'coagulante', true, 20, pg_temp.pdf(sp), 'ZT12 coagulante de prueba') ->> 'codigo';
  perform public.geoportal_tec_quimico_inventario(sp, v_cod, 300, 'kg', v_hoy - 2, 'ZT12 conteo físico de bodega');
  v_n0 := pg_temp.n(tecnica.f_avisos(true, false, null), 'quimicos_saldo');
  perform pg_temp.reg('05.01 sin saldo mínimo fijado no hay aviso del químico (arranca vacío)', (public.geoportal_tec_quimico_minimos(sp) -> 'quimicos') @> jsonb_build_array(jsonb_build_object('codigo', v_cod, 'minimo_kg', null, 'bajo', false)));
  v_x := public.geoportal_tec_quimico_minimo_fijar(sp, v_cod, 500, 'ZT12 el jefe de planta fija el mínimo');
  perform pg_temp.reg('05.02 el supervisor de planta fija 500 kg (saldo 300): el aviso de saldo bajo sube en 1, con evento y auditoría',
     pg_temp.n(tecnica.f_avisos(true, false, null), 'quimicos_saldo') = v_n0 + 1 and (v_x ->> 'minimo_kg')::numeric = 500
     and exists (select 1 from tecnica.quimico_minimo_eventos e join tecnica.quimicos q on q.id = e.quimico_id where q.codigo = v_cod and e.minimo_kg = 500 and e.autor = sp)
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_quimico_minimo' and email = sp and referencia = v_cod), v_x::text);
  perform pg_temp.reg('05.03 la lista de mínimos lo marca bajo', (public.geoportal_tec_quimico_minimos(a) -> 'quimicos') @> jsonb_build_array(jsonb_build_object('codigo', v_cod, 'bajo', true)));
  perform pg_temp.err('05.04 el operador no fija mínimos', format($$select public.geoportal_tec_quimico_minimo_fijar(%L, %L, 100, 'ZT12 el operador no puede')$$, op, v_cod), '42501');
  perform pg_temp.err('05.05 el supervisor de distribución tampoco', format($$select public.geoportal_tec_quimico_minimo_fijar(%L, %L, 100, 'ZT12 distribución no puede')$$, sd, v_cod), '42501');
  perform pg_temp.err('05.06 el mismo mínimo no es un cambio', format($$select public.geoportal_tec_quimico_minimo_fijar(%L, %L, 500, 'ZT12 el mismo valor otra vez')$$, sp, v_cod), '22023', 'ya es');
  perform pg_temp.err('05.07 un mínimo de cero o negativo', format($$select public.geoportal_tec_quimico_minimo_fijar(%L, %L, 0, 'ZT12 cero no vale')$$, sp, v_cod), '22023', 'mínimo');
  perform pg_temp.err('05.08 sin motivo suficiente', format($$select public.geoportal_tec_quimico_minimo_fijar(%L, %L, 400, 'corto')$$, sp, v_cod), '22023', 'motivo');
  perform public.geoportal_tec_quimico_minimo_fijar(a, v_cod, 200, 'ZT12 el administrador baja el mínimo');
  perform pg_temp.reg('05.09 con el mínimo por debajo del saldo, el aviso desaparece solo', pg_temp.n(tecnica.f_avisos(true, false, null), 'quimicos_saldo') = v_n0);
  perform public.geoportal_tec_quimico_minimo_fijar(sp, v_cod, null, 'ZT12 se quita el mínimo del químico');
  perform pg_temp.reg('05.10 quitar el mínimo (vacío) es otro evento y deja el químico sin mínimo',
     (public.geoportal_tec_quimico_minimos(sp) -> 'quimicos') @> jsonb_build_array(jsonb_build_object('codigo', v_cod, 'minimo_kg', null))
     and (select count(*) from tecnica.quimico_minimo_eventos e join tecnica.quimicos q on q.id = e.quimico_id where q.codigo = v_cod) = 3);
  -- HOY, en la planta de prueba: caudal de 100 L/s y el coagulante con dosis óptima de 20 ppm (esperado 172,8 kg) sin ningún uso. Se revisa como si fuera mañana
  -- (los avisos de químicos miran solo días cerrados, y la dosis óptima del químico nuevo rige desde hoy).
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'entrada', v.id, v_pl, 100, v_hoy, time '09:00', op from tecnica.variables v where v.codigo = 'caudal_qi';
  v_j := tecnica.f_avisos(true, false, clock_timestamp() + interval '1 day');
  -- el coagulante nuevo vale para todas las plantas activas que hoy tienen caudal (la de prueba y las reales que ya registraron)
  select count(distinct p.id) into v_n1 from tecnica.plantas p join tecnica.v_registros_estado r2 on r2.planta_id = p.id
   where p.activa and r2.formulario::text = 'entrada' and r2.fecha_muestra = v_hoy and not r2.excluido and r2.variable_id = (select id from tecnica.variables where codigo = 'caudal_qi');
  perform pg_temp.reg('05.11 un día con dosis y caudal y sin uso registrado: el aviso de días sin uso sube en 1 por planta con caudal hoy y lleva a «Químicos»',
     pg_temp.n(v_j, 'quimicos_sin_uso') = pg_temp.n(v_j0, 'quimicos_sin_uso') + v_n1 and v_n1 >= 1 and pg_temp.av(v_j, 'quimicos_sin_uso') -> 'bandeja' ->> 'pestana' = 'quimicos',
     pg_temp.n(v_j0, 'quimicos_sin_uso') || ' → ' || pg_temp.n(v_j, 'quimicos_sin_uso'));
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'entrada', a);
  perform public.geoportal_tec_quimico_uso(op, jsonb_build_object('quimico', v_cod, 'cantidad', 400, 'unidad', 'kg', 'dia', v_hoy, 'planta', 'zt12_planta', 'para_que', 'dosificacion'), null);
  v_j1 := tecnica.f_avisos(true, false, clock_timestamp() + interval '1 day');
  perform pg_temp.reg('05.12 con un uso de 400 kg (esperado 172,8): sale de «sin uso» y entra al aviso de desvío, con el porcentaje',
     pg_temp.n(v_j1, 'quimicos_sin_uso') = pg_temp.n(v_j, 'quimicos_sin_uso') - 1 and pg_temp.n(v_j1, 'quimicos_desvio') = pg_temp.n(v_j0, 'quimicos_desvio') + 1
     and (pg_temp.n(v_j0, 'quimicos_desvio') >= 5 or exists (select 1 from jsonb_array_elements_text(pg_temp.av(v_j1, 'quimicos_desvio') -> 'items') t where t like '%ZT12 Planta · ZT12 Coagulante · +131 %%')),
     pg_temp.av(v_j1, 'quimicos_desvio')::text);
  perform pg_temp.reg('05.13 químicos de potabilización sin dosis óptima o sin ficha: el conteo es el de la tabla',
     pg_temp.n(v_j1, 'quimicos_ficha') = (select count(*) from tecnica.v_quimico_vigente where activo and potabilizacion and (dosis_optima_ppm is null or ficha_ruta is null)));

  -- ===================== 06. Distribución: daños según su riesgo (avisan a cualquier hora) =====================
  v_j0 := tecnica.f_avisos(false, true, null);
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor) values
    (d_alto, 'DAN-991201', 'dano', v_tipo, 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '3 hours', 'alto', 'desconocida', a),
    (d_medio, 'DAN-991202', 'dano', v_tipo, 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '30 hours', 'medio', 'desconocida', a),
    (d_bajo, 'DAN-991203', 'dano', v_tipo, 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '200 hours', 'bajo', 'desconocida', a),
    (d_nuevo, 'DAN-991204', 'dano', v_tipo, 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '30 minutes', 'alto', 'desconocida', a),
    (d_viejo, 'DAN-991205', 'dano', v_tipo, 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '7 hours', 'alto', 'desconocida', a);
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, no_ident_que_es, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor) values
    (d_ni, 'DAN-991206', 'dano', v_tipo, 'acueducto', null, 'ZT12 tubo sin identificar', 10.47, -73.24, 'mapa', clock_timestamp() - interval '10 minutes', 'bajo', 'desconocida', a);
  v_j := tecnica.f_avisos(false, true, null);
  perform pg_temp.reg('06.01 naranja: el alto de 3 h y el medio de 30 h (2 más); rojo: el alto de 7 h y el bajo de 200 h (2 más); el alto de 30 min aún no',
     pg_temp.n(v_j, 'danos_naranja') = pg_temp.n(v_j0, 'danos_naranja') + 2 and pg_temp.n(v_j, 'danos_rojo') = pg_temp.n(v_j0, 'danos_rojo') + 2,
     pg_temp.n(v_j0, 'danos_naranja') || '/' || pg_temp.n(v_j0, 'danos_rojo') || ' → ' || pg_temp.n(v_j, 'danos_naranja') || '/' || pg_temp.n(v_j, 'danos_rojo'));
  perform pg_temp.reg('06.02 el rojo dice «pasaron su plazo», lleva a «Daños y fallas» y nombra los plazos',
     pg_temp.av(v_j, 'danos_rojo') ->> 'titulo' ~ '^(1 daño abierto pasó|[0-9]+ daños abiertos pasaron) su plazo$' and pg_temp.av(v_j, 'danos_rojo') -> 'bandeja' ->> 'pestana' = 'danos'
     and pg_temp.av(v_j, 'danos_rojo') ->> 'detalle' like 'Plazos: riesgo alto 2 y 6 h%');
  perform pg_temp.reg('06.03 el daño no identificado sube el aviso de «activo sin identificar»', pg_temp.n(v_j, 'no_identificados') = pg_temp.n(v_j0, 'no_identificados') + 1);
  perform pg_temp.reg('06.04 a las 3 de la mañana el daño alto también avisa (no hay horario para distribución)',
     pg_temp.n(tecnica.f_avisos(false, true, pg_temp.h(3) + interval '1 day'), 'danos_rojo') >= 1);
  insert into redes.dano_eventos (dano_id, tipo, motivo, autor) values (d_bajo, 'atendido', 'ZT12 atendido sin intervención', sd);
  v_j1 := tecnica.f_avisos(false, true, null);
  perform pg_temp.reg('06.05 el bajo atendido sale solo del rojo y entra a «atendidos sin intervención registrada»',
     pg_temp.n(v_j1, 'danos_rojo') = pg_temp.n(v_j0, 'danos_rojo') + 1 and pg_temp.n(v_j1, 'danos_sin_intervencion') = pg_temp.n(v_j0, 'danos_sin_intervencion') + 1);
  insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_inicio, t_fin, descripcion, ejecutor, autor)
  values (gen_random_uuid(), 'ITV-991201', 'dano', d_bajo, 'reparacion', 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '5 hours', clock_timestamp() - interval '4 hours',
          'ZT12 reparación de prueba del daño', 'emdupar', sd);
  v_j1 := tecnica.f_avisos(false, true, null);
  perform pg_temp.reg('06.06 con su intervención registrada, sale de «sin intervención»; la intervención sin recursos entra a «recursos sin completar»',
     pg_temp.n(v_j1, 'danos_sin_intervencion') = pg_temp.n(v_j0, 'danos_sin_intervencion')
     and pg_temp.n(v_j1, 'recursos_por_completar') = pg_temp.n(v_j0, 'recursos_por_completar') + (select count(*) from redes.v_intervencion where codigo = 'ITV-991201' and recursos = 'por_completar'),
     (select recursos from redes.v_intervencion where codigo = 'ITV-991201'));
  -- reportes del bot, cargas abiertas, activos por verificar y nodos
  insert into redes.reportes_externos (radicado, canal, tipo_bot, lat, lon, descripcion, recibido_en) values ('ZT12-001', 'telegram', 'Fuga', 10.47, -73.24, 'ZT12 reporte de prueba', clock_timestamp() - interval '2 hours') returning id into v_rep;
  insert into redes.reporte_externo_eventos (reporte_id, tipo, autor) values (v_rep, 'recibido', 'bot');
  perform pg_temp.reg('06.07 un reporte del bot recibido sin atender sube el aviso y lleva a «Reportes del bot»',
     pg_temp.n(tecnica.f_avisos(false, true, null), 'reportes_bot') = pg_temp.n(v_j0, 'reportes_bot') + 1 and pg_temp.av(tecnica.f_avisos(false, true, null), 'reportes_bot') -> 'bandeja' ->> 'pestana' = 'bot');
  insert into redes.reporte_externo_eventos (reporte_id, tipo, motivo, autor) values (v_rep, 'descartado', 'ZT12 reporte de prueba descartado', sd);
  perform pg_temp.reg('06.08 descartado con motivo, desaparece solo', pg_temp.n(tecnica.f_avisos(false, true, null), 'reportes_bot') = pg_temp.n(v_j0, 'reportes_bot'));
  v_n0 := pg_temp.n(tecnica.f_avisos(false, true, clock_timestamp() + interval '25 hours'), 'cargas_abiertas');
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor) values ('acueducto', md5('zt12a') || md5('zt12b'), 'shp', 4326, 'ID', 1, 'ZT12 carga de prueba', a) returning id into v_carga;
  perform pg_temp.reg('06.09 una carga abierta: hoy no avisa; dentro de 25 h (más de 24 h sin publicar ni anular) sí',
     pg_temp.n(tecnica.f_avisos(false, true, null), 'cargas_abiertas') = pg_temp.n(v_j0, 'cargas_abiertas')
     and pg_temp.n(tecnica.f_avisos(false, true, clock_timestamp() + interval '25 hours'), 'cargas_abiertas') = v_n0 + 1);
  v_n0 := pg_temp.n(tecnica.f_avisos(false, true, null), 'por_verificar');
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (v_act2, 'por_verificar', 'ZT12 activo de prueba por verificar', a);
  v_n1 := pg_temp.n(tecnica.f_avisos(false, true, null), 'por_verificar');
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (v_act2, 'verificar', 'ZT12 activo de prueba verificado', a);
  perform pg_temp.reg('06.10 un activo marcado «por verificar» sube el aviso informativo en 1; verificado, vuelve',
     v_n1 = v_n0 + 1 and pg_temp.n(tecnica.f_avisos(false, true, null), 'por_verificar') = v_n0, v_n0 || ' → ' || v_n1);
  perform pg_temp.reg('06.11 nodos por clasificar: el conteo es el de la bandeja', pg_temp.n(tecnica.f_avisos(false, true, null), 'nodos_por_clasificar') = (select count(*) from redes.v_nodo_visible where clase_nodo = 'por_clasificar'));
  -- 06.12 línea 116 (5d publicado): un reporte en «Registrado» hace 4 días avisa; uno de ayer, no. Sin la tabla, no hay aviso (queda apagado).
  if to_regclass('redes.l116_vigente') is null then
    perform pg_temp.reg('06.12 línea 116: sin la tabla del 5d no hay aviso (apagado)', pg_temp.av(tecnica.f_avisos(false, true, null), 'l116_registrado') is null);
  else
    v_n0 := pg_temp.n(tecnica.f_avisos(false, true, null), 'l116_registrado');
    execute $s$insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, carga_id) values (991201, clock_timestamp() - interval '4 days', 'ZT12 Acueducto', 'ZT12 Fuga', $1), (991202, clock_timestamp() - interval '1 day', 'ZT12 Acueducto', 'ZT12 Fuga', $1)$s$ using v_carga;
    execute $s$insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, estado, estado_desde, metodo)
                select r.id, r.reporte, r.fecha_registro, (r.fecha_registro at time zone 'America/Bogota')::date, r.servicio, r.causal, 'registrado', r.fecha_registro, 'sin_ubicar'
                  from redes.l116_reportes r where r.reporte in (991201, 991202)$s$;
    v_j := tecnica.f_avisos(false, true, null);
    perform pg_temp.reg('06.12 línea 116 (5d publicado): el reporte en «Registrado» hace 4 días avisa y el de ayer no; lleva al Dashboard distribución',
       pg_temp.n(v_j, 'l116_registrado') = v_n0 + 1 and pg_temp.av(v_j, 'l116_registrado') -> 'bandeja' ->> 'tablero' = 'distribucion', v_n0 || ' → ' || pg_temp.n(v_j, 'l116_registrado'));
  end if;

  -- ===================== 07. Personal (los dos supervisores y el administrador) =====================
  v_j0 := tecnica.f_avisos(true, true, null);
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op2, 'ZT12 Operador nuevo', 'consulta', true, 'sin_restriccion', 'todos');
  v_j := tecnica.f_avisos(true, true, null);
  perform pg_temp.reg('07.01 una persona nueva sin formularios ni área: sube «sin formularios» y «sin área»',
     pg_temp.n(v_j, 'personal_sin_formularios') = pg_temp.n(v_j0, 'personal_sin_formularios') + 1 and pg_temp.n(v_j, 'personal_sin_area') = pg_temp.n(v_j0, 'personal_sin_area') + 1);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op2, 'asignar_formulario', 'danos_fallas', a);
  insert into tecnica.personal_ficha_eventos (persona, tipo_evento, valor, motivo, autor) values (op2, 'fijar_area', 'distribucion', 'ZT12 área de prueba', a);
  v_j := tecnica.f_avisos(true, true, null);
  perform pg_temp.reg('07.02 con un formulario y el área «distribución»: sale de los dos y entra a «sin cuadrilla»',
     pg_temp.n(v_j, 'personal_sin_formularios') = pg_temp.n(v_j0, 'personal_sin_formularios') and pg_temp.n(v_j, 'personal_sin_area') = pg_temp.n(v_j0, 'personal_sin_area')
     and pg_temp.n(v_j, 'personal_sin_cuadrilla') = pg_temp.n(v_j0, 'personal_sin_cuadrilla') + 1);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op2, 'quitar_formulario', 'danos_fallas', a);
  perform pg_temp.reg('07.03 quitarle el único formulario lo devuelve a «sin formularios»', pg_temp.n(tecnica.f_avisos(true, true, null), 'personal_sin_formularios') = pg_temp.n(v_j0, 'personal_sin_formularios') + 1);
  perform pg_temp.reg('07.04 el supervisor de planta y el de distribución ven los avisos de Personal',
     pg_temp.av(public.geoportal_tec_avisos(sp) -> 'avisos', 'personal_sin_cuadrilla') is not null and pg_temp.av(public.geoportal_tec_avisos(sd) -> 'avisos', 'personal_sin_cuadrilla') is not null);

  -- ===================== 08. Plazos y mínimos: parámetros editables =====================
  perform pg_temp.reg('08.01 cada supervisor ve los parámetros de su área (planta 5, distribución 9) y el administrador los 15',
     jsonb_array_length(public.geoportal_tec_avisos_parametros(sp) -> 'parametros') = 5 and jsonb_array_length(public.geoportal_tec_avisos_parametros(sd) -> 'parametros') = 9
     and jsonb_array_length(public.geoportal_tec_avisos_parametros(a) -> 'parametros') = 15
     and (public.geoportal_tec_avisos_parametros(sp) ->> 'puede_minimos')::boolean and not (public.geoportal_tec_avisos_parametros(sd) ->> 'puede_minimos')::boolean);
  v_x := public.geoportal_tec_aviso_parametro_fijar(sp, 'horario_fin', 17, 'ZT12 el turno de la planta cierra a las 5');
  perform pg_temp.reg('08.02 el supervisor de planta cierra el horario a las 17: evento con antes, después, motivo y autor; auditoría; a las 17:30 la Salida ya está en rojo',
     (v_x ->> 'valor')::numeric = 17 and (select antes = 18 and despues = 17 and autor = sp from tecnica.aviso_parametro_eventos where clave = 'horario_fin' order by id desc limit 1)
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_aviso_parametro' and email = sp and referencia = 'horario_fin')
     and pg_temp.av(tecnica.f_avisos(true, false, pg_temp.h(17.5)), 'planta_salida:zt12_planta') ->> 'nivel' = 'rojo'
     and (public.geoportal_tec_avisos_parametros(sp) -> 'parametros' -> 1 -> 'ultimo' ->> 'autor') = sp, v_x::text);
  perform pg_temp.err('08.03 el supervisor de planta no cambia plazos de distribución', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'dano_alto_rojo_h', 8, 'ZT12 no es de su área')$$, sp), '42501');
  perform pg_temp.err('08.04 ni el de distribución los de planta', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'horario_inicio', 7, 'ZT12 no es de su área')$$, sd), '42501');
  perform pg_temp.err('08.05 los intentos del bot solo los cambia el administrador', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'salida_max_intentos', 3, 'ZT12 solo el administrador')$$, sd), '42501');
  perform pg_temp.err('08.06 el operador, nada', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'horario_fin', 16, 'ZT12 el operador no puede')$$, op), '42501');
  v_x := public.geoportal_tec_aviso_parametro_fijar(sd, 'dano_alto_naranja_h', 4, 'ZT12 distribución alarga el naranja del alto');
  v_j := tecnica.f_avisos(false, true, null);
  perform pg_temp.reg('08.07 el supervisor de distribución sube el naranja del riesgo alto a 4 h: el daño alto de 3 h deja de avisar en naranja',
     pg_temp.n(v_j, 'danos_naranja') = pg_temp.n(v_j0, 'danos_naranja') - 1, pg_temp.n(v_j0, 'danos_naranja') || ' → ' || pg_temp.n(v_j, 'danos_naranja'));
  perform pg_temp.err('08.08 el naranja debe quedar antes que el rojo', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'dano_alto_naranja_h', 6, 'ZT12 igual al rojo no vale')$$, sd), '22023', 'naranja');
  perform pg_temp.err('08.09 el inicio del horario antes del fin', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'horario_inicio', 17, 'ZT12 inicio igual al fin')$$, sp), '22023', 'inicio');
  perform pg_temp.err('08.10 la hora límite del primer registro dentro del horario', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'planta_primer_registro_hora', 7, 'ZT12 antes del horario')$$, sp), '22023', 'dentro');
  perform pg_temp.err('08.11 enteros', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'planta_horas_sin_registro', 2.5, 'ZT12 con decimales')$$, sp), '22023', 'entero');
  perform pg_temp.err('08.12 dentro del rango', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'planta_horas_sin_registro', 30, 'ZT12 fuera del rango')$$, sp), '22023', 'va de');
  perform pg_temp.err('08.13 el mismo valor no es un cambio', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'horario_fin', 17, 'ZT12 el mismo valor')$$, sp), '22023', 'ya es');
  perform pg_temp.err('08.14 sin motivo suficiente', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'horario_fin', 16, 'corto')$$, sp), '22023', 'motivo');
  perform pg_temp.err('08.15 un parámetro que no existe', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'no_existe', 1, 'ZT12 no existe')$$, a), '22023', 'no existe');
  perform pg_temp.err('08.16 los eventos de los parámetros no se editan', $$update tecnica.aviso_parametro_eventos set motivo = 'ZT12 cambiado' where clave = 'horario_fin'$$, '42501');

  -- ===================== 09. Cola de avisos de salida (bot del Dell) =====================
  v_n0 := tecnica.f_avisos_encolar();
  perform pg_temp.reg('09.01 encolar: el alto de 30 min sale como «nuevo»; el de 7 h, visto por primera vez, solo como «rojo»; el de 3 h como «naranja» (con el naranja en 4 h: «nuevo»)',
     exists (select 1 from tecnica.v_avisos_salida where ref_id = d_nuevo and nivel = 'nuevo' and estado = 'pendiente')
     and (select array_agg(nivel) from tecnica.avisos_salida where ref_id = d_viejo) = array['rojo']
     and (select array_agg(nivel) from tecnica.avisos_salida where ref_id = d_alto) = array['nuevo']
     and not exists (select 1 from tecnica.avisos_salida where ref_id in (d_medio, d_bajo, d_ni)), v_n0::text);
  perform pg_temp.reg('09.02 encolar otra vez no repite nada', tecnica.f_avisos_encolar() = 0 and (select count(*) from tecnica.avisos_salida where ref_id in (d_nuevo, d_viejo, d_alto)) = 3);
  perform public.geoportal_tec_aviso_parametro_fijar(sd, 'dano_alto_naranja_h', 2, 'ZT12 distribución vuelve el naranja a 2 h');
  perform tecnica.f_avisos_encolar();
  perform pg_temp.reg('09.03 al pasar a naranja (el plazo vuelve a 2 h), el alto de 3 h deja un segundo aviso «naranja»',
     (select array_agg(nivel order by creado_en) from tecnica.avisos_salida where ref_id = d_alto) = array['nuevo', 'naranja']);
  perform pg_temp.reg('09.04 el mensaje no lleva descripción, autor, nombre ni coordenadas; sí el código, el tipo, el nivel y las horas',
     not exists (select 1 from tecnica.avisos_salida a2, jsonb_object_keys(a2.mensaje) k where a2.ref_id in (d_nuevo, d_viejo, d_alto) and k in ('descripcion', 'autor', 'nombre', 'lat', 'lon', 'telefono'))
     and (select mensaje ->> 'dano' = 'DAN-991205' and mensaje ->> 'nivel' = 'rojo' and (mensaje ->> 'horas_abierto')::numeric >= 7 from tecnica.avisos_salida where ref_id = d_viejo));
  select count(*) into v_n0 from tecnica.avisos_tomar(20, 300) t where t.mensaje ->> 'dano' in ('DAN-991204', 'DAN-991205', 'DAN-991201');
  perform pg_temp.reg('09.05 el Dell toma los 4 (con arriendo y lease_id, intento 1); tomar otra vez no los repite mientras dure el arriendo',
     v_n0 = 4 and (select bool_and(estado = 'tomado' and intentos = 1 and lease_id is not null and tomado_hasta > clock_timestamp()) from tecnica.v_avisos_salida where ref_id in (d_nuevo, d_viejo, d_alto))
     and not exists (select 1 from tecnica.avisos_tomar(20, 300) t where t.mensaje ->> 'dano' in ('DAN-991204', 'DAN-991205', 'DAN-991201')), v_n0::text);
  select id, lease_id into v_av, v_lease from tecnica.v_avisos_salida where ref_id = d_nuevo;
  perform pg_temp.err('09.06 marcar con otro lease_id no vale', format($$select tecnica.avisos_marcar(%L, gen_random_uuid(), 'enviado')$$, v_av), '22023', 'lease_id');
  perform pg_temp.err('09.07 un estado que no existe', format($$select tecnica.avisos_marcar(%L, %L, 'perdido')$$, v_av, v_lease), '22023', 'Estado');
  v_e1 := tecnica.avisos_marcar(v_av, v_lease, 'enviado', '{"telegram":"ok"}'); v_e2 := tecnica.avisos_marcar(v_av, v_lease, 'enviado');
  perform pg_temp.reg('09.08 enviado; repetirlo es inocuo; queda el evento del Dell con su detalle',
     v_e1 = 'enviado' and v_e2 = 'enviado'
     and (select count(*) from tecnica.aviso_salida_eventos where aviso_id = v_av and estado = 'enviado') = 1
     and (select detalle ->> 'telegram' from tecnica.aviso_salida_eventos where aviso_id = v_av and estado = 'enviado') = 'ok');
  select id, lease_id into v_av, v_lease from tecnica.v_avisos_salida where ref_id = d_viejo;
  v_e1 := tecnica.avisos_marcar(v_av, v_lease, 'error', '{"error":"sin red"}', true);
  perform pg_temp.reg('09.09 error reintentable: vuelve a pendiente; el Dell lo toma otra vez con intento 2',
     v_e1 = 'pendiente'
     and exists (select 1 from tecnica.avisos_tomar(20, 300) t where t.aviso_id = v_av and t.intentos = 2));
  select lease_id into v_lease from tecnica.v_avisos_salida where id = v_av;
  v_e1 := tecnica.avisos_liberar(v_av, v_lease);
  perform pg_temp.reg('09.10 liberar lo devuelve a pendiente sin gastar intento', v_e1 = 'pendiente' and (select intentos from tecnica.v_avisos_salida where id = v_av) = 1);
  perform public.geoportal_tec_aviso_parametro_fijar(a, 'salida_max_intentos', 1, 'ZT12 el administrador deja un solo intento');
  perform tecnica.avisos_tomar(20, 300);
  perform pg_temp.reg('09.11 con el tope bajado a 1 intento, el aviso que ya gastó uno no se entrega: queda en «error» (intentos_agotados)',
     (select estado = 'error' and ultimo_detalle ->> 'motivo' = 'intentos_agotados' from tecnica.v_avisos_salida where id = v_av));
  select id, lease_id into v_av2, v_lease from tecnica.v_avisos_salida where ref_id = d_alto and nivel = 'naranja';
  perform tecnica.avisos_liberar(v_av2, v_lease);
  insert into redes.dano_eventos (dano_id, tipo, motivo, autor) values (d_alto, 'atendido', 'ZT12 atendido antes del envío', sd);
  perform tecnica.avisos_tomar(20, 300);
  perform pg_temp.reg('09.12 el daño se atendió antes del envío: el Dell no lo recibe y el aviso queda «anulado» (motivo dano_cerrado)',
     (select estado = 'anulado' and ultimo_detalle ->> 'motivo' = 'dano_cerrado' from tecnica.v_avisos_salida where id = v_av2));
  perform pg_temp.err('09.13 límites de tomar', $$select * from tecnica.avisos_tomar(50, 300)$$, '22023', 'p_limite');
  perform pg_temp.reg('09.14 nada se borró: cada cambio de estado es un evento', (select count(*) from tecnica.aviso_salida_eventos e join tecnica.avisos_salida s on s.id = e.aviso_id where s.ref_id in (d_nuevo, d_viejo, d_alto)) >= 12);

  -- ===================== 10. Lo que ve producción =====================
  perform pg_temp.reg('10.01 pg-safeupdate: ninguna función de redes, tecnica, geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
     not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion || ' → ' || sentencia, ' | ') from redes.f_funciones_sin_where()));
  perform pg_temp.reg('10.02 la huella de las funciones de redes no cambió (el Corte 12 no toca redes)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = v_redes);

  perform pg_temp.err('10.03 los eventos de los mínimos son de solo inserción', $$update tecnica.quimico_minimo_eventos set motivo = 'ZT12 cambiado' where id > 0$$, '42501');
  perform pg_temp.err('10.04 la cola de salida es de solo inserción', $$update tecnica.avisos_salida set nivel = 'rojo' where id is not null$$, '42501');
  perform pg_temp.err('10.05 los estados de la cola, también', $$delete from tecnica.aviso_salida_eventos where id > 0$$, '42501');
  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · CORTE 12 (esperado: este ERROR deshace todo lo de la prueba)\n%\nTIEMPOS: avisos del administrador % ms, del supervisor de planta % ms, del de distribución % ms (tope 1.000 ms; el peor de 3)\nRESULTADO: % de % pruebas correctas — %',
    v_fallas, round(v_ms_adm), round(v_ms_sp), round(v_ms_sd), v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
