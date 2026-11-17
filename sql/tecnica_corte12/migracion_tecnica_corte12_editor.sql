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
commit;
