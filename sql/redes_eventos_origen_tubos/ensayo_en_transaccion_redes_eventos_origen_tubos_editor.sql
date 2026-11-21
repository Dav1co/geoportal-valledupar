begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · EVENTOS: ORIGEN OBLIGATORIO Y SECTORES POR TUBO DE SALIDA · 10 — GUARDIA, ESQUEMA Y DATOS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Encargo y decisiones de David del 20-nov (eventos_origen_tubos/ENTRADA_BITACORA.md y DECISION_VIGENTE.md):
-- · ORIGEN: al declarar, un daño o una intervención (lo de hoy) O un trabajo con su causal de catálogo; la observación (el campo «causa») sigue obligatoria.
--   El origen se DERIVA: daño, intervención, causal o «No registrado (anterior al cambio)». Nada viejo se completa.
-- · TUBOS: los sectores se asignan a los tubos de salida (tecnica.puntos tipo «distribucion»), no a las plantas. Un evento «por tubo» se guarda como un
--   evento POR SECTORES (alcance «sectores»: evento_contrato, el aviso «sin agua», el SCRR, los disparadores y el bot no cambian) y se anota de qué tubos salió.
-- · PLANTA: el sistema es único; un evento de planta nuevo cubre toda la ciudad. Las filas de redes.planta_sectores NO se borran: se desactivan con motivo.
-- Exige la huella de redes publicada 3f3c89e603629d92e1cc5065de33d0c1 (reportes del PTAP y descargas de Distribución, 20-nov 21:08) y las 3 funciones de técnica que reemplaza.
-- =====================================================================
do $$
begin
  if to_regclass('redes.evento_causales') is not null or to_regclass('redes.tubo_sectores') is not null then
    raise exception 'El corte de eventos (origen y tubos) ya está aplicado: deténgase y avise';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '3f3c89e603629d92e1cc5065de33d0c1' then
    raise exception 'Las funciones de redes no son las publicadas (huella 3f3c89e603629d92e1cc5065de33d0c1): deténgase y avise';
  end if;
  if (select count(*) from (values ('tecnica.f_rep_columnas(text,jsonb)', 'd178a29b3e4408b96b07bbaeae20f476'), ('tecnica.f_rep_eventos_planta(jsonb,boolean,timestamp with time zone,text,integer)', '5b97ed0684b94b94c14ec420aa1c212a'), ('tecnica.f_rep_leame(text,jsonb,boolean,text,timestamp with time zone)', '5f894b795ad896a7cc965b3ec5d37745')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 3 then
    raise exception 'Las funciones de los reportes del PTAP que este paquete reemplaza no son las publicadas: deténgase y avise';
  end if;
  if to_regclass('redes.planta_sectores') is null or to_regclass('redes.planta_sector_eventos') is null or to_regclass('tecnica.puntos') is null
     or not exists (select 1 from pg_constraint where conrelid = 'tecnica.puntos'::regclass and pg_get_constraintdef(oid) like '%distribucion%') then
    raise exception 'Faltan los sectores por planta del Corte 15 o los puntos de distribución de técnica: deténgase y avise';
  end if;
end $$;

-- ---------- 1. Causales de un evento declarado como trabajo (catálogo ajustable con historial) ----------
create table redes.evento_causales (
  codigo text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,39}$'),
  nombre text not null unique check (length(btrim(nombre)) between 3 and 80),
  activa boolean not null default true,
  orden  integer not null default 50
);
create table redes.evento_causal_eventos (
  id bigint generated always as identity primary key,
  codigo text not null references redes.evento_causales (codigo),
  accion text not null check (accion in ('crear', 'cambiar')),
  nombre text not null, activa boolean not null,
  motivo text not null check (length(btrim(motivo)) between 10 and 500), autor text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp()
);
-- la causal de cada evento declarado como trabajo (una por evento; solo inserción)
create table redes.evento_causal (
  evento_id bigint primary key references redes.eventos_suspension (id),
  causal    text not null references redes.evento_causales (codigo),
  creado_en timestamptz not null default clock_timestamp()
);
-- ---------- 2. Tubos de salida → sectores (como planta → sectores, con historial) y de qué tubos salió cada evento ----------
create table redes.tubo_sectores (
  punto_id  bigint not null references tecnica.puntos (id),
  sector_id bigint not null references redes.activos (id),
  activo    boolean not null default true,
  primary key (punto_id, sector_id)
);
create table redes.tubo_sector_eventos (
  id bigint generated always as identity primary key, punto_id bigint not null references tecnica.puntos (id), sectores bigint[] not null,
  motivo text not null check (length(btrim(motivo)) between 10 and 500), autor text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp()
);
create table redes.evento_tubos (
  evento_id bigint not null references redes.eventos_suspension (id),
  punto_id  bigint not null references tecnica.puntos (id),
  primary key (evento_id, punto_id)
);
-- un tubo es un punto de tipo «distribucion» (la llave foránea no lo puede decir)
create function redes.f_tubo_es_distribucion() returns trigger language plpgsql set search_path to 'redes', 'tecnica', 'pg_temp' as $$
begin
  if not exists (select 1 from tecnica.puntos p where p.id = new.punto_id and p.tipo = 'distribucion') then
    raise exception 'Ese punto no es un tubo de salida (tipo distribución)' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t_tubo_es_distribucion before insert or update on redes.tubo_sectores for each row execute function redes.f_tubo_es_distribucion();
create trigger t_tubo_es_distribucion before insert or update on redes.tubo_sector_eventos for each row execute function redes.f_tubo_es_distribucion();
create trigger t_tubo_es_distribucion before insert or update on redes.evento_tubos for each row execute function redes.f_tubo_es_distribucion();
comment on table redes.tubo_sectores is 'Sectores y subsectores que abastece cada tubo de salida (tecnica.puntos tipo distribucion). Arranca vacía: la llena el administrador o el supervisor de distribución (David, 20-nov).';
comment on table redes.evento_tubos is 'De qué tubos de salida se declaró un evento «por tubo» (el evento queda por sectores).';
comment on table redes.evento_causal is 'La causal de catálogo de un evento declarado como trabajo o actividad (no por un daño ni una intervención).';

do $$
declare v_t text;
begin
  foreach v_t in array array['evento_causales', 'evento_causal_eventos', 'evento_causal', 'tubo_sectores', 'tubo_sector_eventos', 'evento_tubos'] loop
    execute format('alter table redes.%I enable row level security', v_t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', v_t);
  end loop;
  foreach v_t in array array['evento_causal_eventos', 'evento_causal', 'tubo_sector_eventos', 'evento_tubos'] loop
    execute format('create trigger t_solo_agregar before delete or update on redes.%I for each row execute function tecnica.f_solo_agregar()', v_t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', v_t);
  end loop;
end $$;
revoke all on sequence redes.evento_causal_eventos_id_seq, redes.tubo_sector_eventos_id_seq from public, anon, authenticated, service_role;
revoke all on function redes.f_tubo_es_distribucion() from public, anon, authenticated, service_role;

-- ---------- 3. Las causales de David (20-nov) ----------
insert into redes.evento_causales (codigo, nombre, orden) values
  ('trabajo_programado', 'Trabajo programado en redes', 1),
  ('parametros_entrada', 'Parámetros de entrada que impiden operar', 2),
  ('falla_planta', 'Falla en la planta', 3),
  ('mantenimiento_planta', 'Limpieza o mantenimiento de planta', 4),
  ('otra', 'Otra', 9);

-- ---------- 4. Planta → sectores: se DESACTIVAN (no se borran), con un hecho por planta y el motivo de David ----------
insert into redes.planta_sector_eventos (planta_id, sectores, motivo, autor)
select distinct ps.planta_id, '{}'::bigint[], 'el sistema es único; los sectores pasan a los tubos de salida', 'migracion@redes_eventos_origen_tubos'
  from redes.planta_sectores ps where ps.activo;
update redes.planta_sectores set activo = false where activo;
-- =====================================================================
-- 20 — FUNCIONES INTERNAS NUEVAS (nadie de la API las ejecuta)
-- =====================================================================
-- El origen de un evento, DERIVADO (nada viejo se completa): daño, intervención, trabajo (con su causal) o «No registrado (anterior al cambio)».
create function redes.f_evento_origen(p_evento bigint) returns jsonb
language sql stable set search_path to 'redes', 'pg_temp' as $$
  select case when e.dano_id is not null then jsonb_build_object('codigo', 'dano', 'nombre', 'Daño')
              when e.intervencion_id is not null then jsonb_build_object('codigo', 'intervencion', 'nombre', 'Intervención')
              when c.causal is not null then jsonb_build_object('codigo', 'trabajo', 'nombre', 'Trabajo')
              else jsonb_build_object('codigo', 'no_registrado', 'nombre', 'No registrado (anterior al cambio)') end
    from redes.eventos_suspension e left join redes.evento_causal c on c.evento_id = e.id where e.id = p_evento $$;

-- Los tubos de salida pedidos → sus ids, la unión de sus sectores y subsectores ACTIVOS y el nombre de la zona.
-- Un tubo que no existe o está inactivo, o que no tiene sectores asignados, es error (David, 20-nov).
create function redes.f_tubo_zona(p_codigos text[], out ids bigint[], out sectores bigint[], out geom geometry, out zona_nombre text) returns record
language plpgsql stable set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_cods text[]; v_c text; v_sin text;
begin
  select array_agg(distinct upper(btrim(x)) order by upper(btrim(x))) into v_cods from unnest(coalesce(p_codigos, '{}')) x where btrim(coalesce(x, '')) <> '';
  if coalesce(cardinality(v_cods), 0) = 0 then perform tecnica.f_error('Escoja al menos un tubo de salida'); end if;
  foreach v_c in array v_cods loop
    if not exists (select 1 from tecnica.puntos p where p.codigo = v_c and p.tipo = 'distribucion' and p.activo) then
      perform tecnica.f_error('Ese tubo de salida no existe o está inactivo.');
    end if;
  end loop;
  select string_agg(p.codigo, ', ' order by p.codigo) into v_sin from tecnica.puntos p
   where p.codigo = any (v_cods) and p.tipo = 'distribucion'
     and not exists (select 1 from redes.tubo_sectores ts join redes.activo_vigente_mat m on m.activo_id = ts.sector_id
                      where ts.punto_id = p.id and ts.activo and m.prefijo = 'SEC' and not m.retirado and not m.oculto);
  if v_sin is not null then perform tecnica.f_error(format('Ese tubo no tiene sectores asignados (%s).', v_sin)); end if;
  select array_agg(p.id order by p.codigo) into ids from tecnica.puntos p where p.codigo = any (v_cods) and p.tipo = 'distribucion';
  select array_agg(distinct m.activo_id order by m.activo_id), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(m.geom)), 3)) into sectores, geom
    from redes.tubo_sectores ts join redes.activo_vigente_mat m on m.activo_id = ts.sector_id
   where ts.punto_id = any (ids) and ts.activo and m.prefijo = 'SEC' and not m.retirado and not m.oculto;
  select case when count(*) = 1 then 'lo que sale por ' || max(coalesce(nullif(btrim(p.nombre), ''), p.codigo)) || ' (' || max(p.codigo) || ')'
              else 'lo que sale por los tubos ' || string_agg(p.codigo, ', ' order by p.codigo) end
    into zona_nombre from tecnica.puntos p where p.id = any (ids);
  zona_nombre := left(zona_nombre, 300);
end $$;
-- =====================================================================
-- 25 — REEMPLAZOS (create or replace; la reversa deja el texto de antes). Lo demás del Corte 15, evento_contrato, el aviso, el SCRR,
-- los disparadores y el bot NO se tocan (la verificación guarda sus md5).
-- =====================================================================

-- 1. La zona del evento: suma «tubos» y la planta cubre toda la ciudad
create or replace function redes.f_evento_zona(p jsonb, OUT alcance text, OUT todo boolean, OUT geom geometry, OUT sectores bigint[], OUT planta_id bigint, OUT centro_lat numeric, OUT centro_lon numeric, OUT radio_m numeric, OUT zona_nombre text)
 RETURNS record
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_cods text[]; v_cuantos integer; v_pl tecnica.plantas%rowtype; v_sector text; v_pt geometry;
begin
  alcance := coalesce(p ->> 'alcance', ''); todo := false; sectores := '{}';
  if alcance = 'sectores' then
    if jsonb_typeof(p -> 'sectores') is distinct from 'array' or jsonb_array_length(p -> 'sectores') = 0 then perform tecnica.f_error('Escoja al menos un sector o subsector'); end if;
    if jsonb_array_length(p -> 'sectores') > coalesce(redes.f_param('evento_sectores_max'), 40) then
      perform tecnica.f_error(format('Un evento admite máximo %s sectores o subsectores', coalesce(redes.f_param('evento_sectores_max'), 40)));
    end if;
    select array_agg(distinct upper(btrim(x))) into v_cods from jsonb_array_elements_text(p -> 'sectores') x;
    select array_agg(m.activo_id order by m.codigo), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(m.geom)), 3)),
           string_agg(coalesce(nullif(btrim(m.nombre), ''), m.codigo), ', ' order by m.codigo), count(*)
      into sectores, geom, zona_nombre, v_cuantos
      from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.codigo = any (v_cods);
    if v_cuantos is distinct from cardinality(v_cods) then perform tecnica.f_error('Alguno de los sectores no existe o ya no está vigente', 'P0002'); end if;
    zona_nombre := left(zona_nombre, 300);
  elsif alcance = 'circulo' then
    centro_lat := round(redes.f_num(p -> 'lat'), 6); centro_lon := round(redes.f_num(p -> 'lon'), 6); radio_m := round(redes.f_num(p -> 'radio_m'), 1);
    if centro_lat is null or centro_lon is null or centro_lat not between -90 and 90 or centro_lon not between -180 and 180 then perform tecnica.f_error('Marque el centro del círculo en el mapa'); end if;
    if radio_m is null or radio_m < coalesce(redes.f_param('evento_radio_min_m'), 20) or radio_m > coalesce(redes.f_param('evento_radio_max_m'), 5000) then
      perform tecnica.f_error(format('El radio del círculo va de %s a %s metros', coalesce(redes.f_param('evento_radio_min_m'), 20), coalesce(redes.f_param('evento_radio_max_m'), 5000)));
    end if;
    v_pt := ST_SetSRID(ST_MakePoint(centro_lon, centro_lat), 4326);
    geom := ST_Multi(ST_Buffer(v_pt::geography, radio_m, 16)::geometry);
    select s.nombre into v_sector from redes.f_sector_de(v_pt) s;
    zona_nombre := format('un círculo de %s m', round(radio_m)) || coalesce(' en ' || nullif(btrim(v_sector), ''), '');
  elsif alcance = 'total' then
    if coalesce(p ->> 'total', '') = 'ciudad' then
      todo := true; zona_nombre := 'toda la ciudad';
    elsif coalesce(p ->> 'total', '') = 'planta' then
      select * into v_pl from tecnica.plantas pl where pl.codigo = lower(btrim(coalesce(p ->> 'planta', ''))) and pl.activa;
      if v_pl.id is null then perform tecnica.f_error('Escoja la planta', 'P0002'); end if;
      -- el sistema es único (David, 20-nov): un evento de planta cubre TODA LA CIUDAD y guarda la planta; ya no se leen los sectores por planta
      planta_id := v_pl.id; todo := true;
      zona_nombre := 'Toda la ciudad (planta ' || v_pl.nombre || ')';
    else perform tecnica.f_error('El evento total es de toda la ciudad o de una planta');
    end if;
  elsif alcance = 'tubos' then
    -- «Por tubo» (David, 20-nov): uno o varios tubos de salida → la unión de sus sectores y subsectores; el evento queda POR SECTORES
    if jsonb_typeof(p -> 'tubos') is distinct from 'array' or jsonb_array_length(p -> 'tubos') = 0 then perform tecnica.f_error('Escoja al menos un tubo de salida'); end if;
    select t.sectores, t.geom, t.zona_nombre into sectores, geom, zona_nombre
      from redes.f_tubo_zona(array(select jsonb_array_elements_text(p -> 'tubos'))) t;
    alcance := 'sectores';
  else perform tecnica.f_error('Escoja el alcance: por sectores, por tubo, por círculo o total');
  end if;
  if not todo and (geom is null or ST_IsEmpty(geom)) then perform tecnica.f_error('No se pudo armar la zona del evento'); end if;
end $function$;

-- 2. Declarar: origen obligatorio (registro o causal), la causal y de qué tubos salió
create or replace function public.geoportal_redes_evento_declarar(p_solicitante text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text; z record; v_causa text := btrim(coalesce(p ->> 'causa', '')); v_reg text := nullif(upper(btrim(coalesce(p ->> 'registro', ''))), '');
  v_dano uuid; v_itv uuid; v_sis text; v_desde timestamptz; v_regreso timestamptz; v_ahora timestamptz := clock_timestamp(); v_ya text; c jsonb;
  v_cons bigint; v_id bigint; v_ids bigint[]; v_max numeric := coalesce(redes.f_param('evento_horas_atras_max'), 72);
  v_causal text := nullif(lower(btrim(coalesce(p ->> 'causal', ''))), ''); v_tubos bigint[];
begin
  if exists (select 1 from jsonb_object_keys(p) k where k not in ('alcance', 'sectores', 'tubos', 'lat', 'lon', 'radio_m', 'total', 'planta', 'causa', 'registro', 'causal', 'desde', 'regreso')) then
    perform tecnica.f_error('El evento trae un dato que no corresponde');
  end if;
  v_email := redes.f_evento_autorizar(p_solicitante, case when coalesce(p ->> 'alcance', '') = 'total' then 'total' else 'zona' end);
  select * into z from redes.f_evento_zona(p);
  -- el origen es obligatorio (David, 20-nov): el daño o la intervención («registro») O la causal del trabajo, nunca los dos ni ninguno
  if v_reg is null and v_causal is null then perform tecnica.f_error('Indique el origen: el daño o la intervención, o la causal del trabajo.'); end if;
  if v_reg is not null and v_causal is not null then perform tecnica.f_error('Elija un solo origen: el daño o la intervención, o la causal.'); end if;
  if v_causal is not null and not exists (select 1 from redes.evento_causales c where c.codigo = v_causal and c.activa) then
    perform tecnica.f_error('Esa causal no existe o está desactivada.');
  end if;
  -- la observación (antes «causa») sigue obligatoria siempre, también con «Otra»; se ve solo en pantalla
  if length(v_causa) < 5 or length(v_causa) > 200 then perform tecnica.f_error('Escriba la observación (de 5 a 200 letras)'); end if;
  if v_reg ~ '^DAN-[0-9]{6}$' then
    select d.id, d.sistema into v_dano, v_sis from redes.danos d where d.codigo = v_reg;
    if v_dano is null then perform tecnica.f_error(format('No hay ningún daño o falla con el código «%s»', v_reg), 'P0002'); end if;
  elsif v_reg ~ '^ITV-[0-9]{6}$' then
    select i.id, i.sistema into v_itv, v_sis from redes.intervenciones i where i.codigo = v_reg;
    if v_itv is null then perform tecnica.f_error(format('No hay ninguna intervención con el código «%s»', v_reg), 'P0002'); end if;
  elsif v_reg is not null then perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
  end if;
  if v_sis is not null and v_sis <> 'acueducto' then perform tecnica.f_error('Ese daño o intervención no es de acueducto'); end if;
  v_desde := coalesce(redes.f_instante(p ->> 'desde', 'desde cuándo'), v_ahora);
  if v_desde > v_ahora + interval '5 minutes' then perform tecnica.f_error('El evento no puede empezar en el futuro'); end if;
  if v_desde < v_ahora - make_interval(secs => (v_max * 3600)::double precision) then perform tecnica.f_error(format('El evento no puede haber empezado hace más de %s horas', v_max)); end if;
  v_regreso := redes.f_instante(p ->> 'regreso', 'regreso estimado del servicio');
  if v_regreso is not null and (v_regreso <= v_desde or v_regreso > v_desde + interval '30 days') then
    perform tecnica.f_error('La hora estimada de regreso debe ser después del inicio y antes de 30 días');
  end if;
  -- un evento a la vez: el consecutivo y la revisión de «ya hay uno abierto para esa zona»
  perform pg_advisory_xact_lock(hashtext('redes.eventos_suspension'));
  select e.codigo into v_ya from redes.f_eventos_abiertos() e where (z.todo and e.todo) or (not z.todo and not e.todo and ST_Equals(e.geom, z.geom)) limit 1;
  if v_ya is not null then raise exception 'Ya hay un evento abierto para esa misma zona: %', v_ya using errcode = '55000', hint = 'msg_usuario'; end if;
  c := redes.f_evento_contratos(z.geom, z.todo);
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'EVS' returning ultimo into v_cons;
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, planta_id, centro_lat, centro_lon, radio_m, zona_nombre, causa, dano_id, intervencion_id,
                                        desde, regreso_estimado, contratos, sensibles, autor)
  values ('EVS-' || lpad(v_cons::text, 6, '0'), z.alcance, z.todo, z.geom, z.sectores, z.planta_id, z.centro_lat, z.centro_lon, z.radio_m, z.zona_nombre, v_causa, v_dano, v_itv,
          v_desde, v_regreso, (c ->> 'contratos')::integer, (c ->> 'sensibles')::integer, v_email)
  returning id into v_id;
  if v_causal is not null then insert into redes.evento_causal (evento_id, causal) values (v_id, v_causal); end if;
  if coalesce(p ->> 'alcance', '') = 'tubos' then
    select t.ids into v_tubos from redes.f_tubo_zona(array(select jsonb_array_elements_text(p -> 'tubos'))) t;
    insert into redes.evento_tubos (evento_id, punto_id) select v_id, x from unnest(v_tubos) x;
  end if;
  with hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, campo_reporte_id, tipo, modo, autor)
    select v_id, k.origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, k.campo_reporte_id, 'asociar', 'al_declarar', v_email
      from redes.f_evento_candidatos(z.geom, z.todo, v_desde, v_dano) k
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, 'en_atencion', 'Asociado al evento de suspensión {evento} (ya estaba recibido al declararlo)', v_email);
  perform tecnica.f_auditar(v_email, 'redes_evento_declarar', 'EVS-' || lpad(v_cons::text, 6, '0'),
          jsonb_build_object('alcance', z.alcance, 'zona', z.zona_nombre, 'origen', redes.f_evento_origen(v_id) ->> 'codigo', 'causal', v_causal,
                             'tubos', (select jsonb_agg(p2.codigo order by p2.codigo) from tecnica.puntos p2 where p2.id = any (v_tubos)), 'contratos', c -> 'contratos', 'sensibles', c -> 'sensibles', 'asociados', coalesce(cardinality(v_ids), 0)), null);
  return redes.f_evento_json(v_id, true) || jsonb_build_object('asociados_al_declarar', coalesce(cardinality(v_ids), 0));
end $function$;

-- 3. El catálogo: suma las causales y los tubos de salida (con sus sectores); los sectores por planta quedan vacíos
create or replace function public.geoportal_redes_evento_catalogo(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'detalle'); v_p record;
begin
  select * into v_p from redes.f_perfil_lectura(v_email);
  return jsonb_build_object(
    'puede', jsonb_build_object('zona', v_p.perfil in ('admin', 'supervisor'), 'reportes', v_p.perfil in ('admin', 'supervisor'),
                                'total', v_p.perfil = 'admin' or public.geoportal_puede(v_email, 'dashboard_tecnico')),
    'limites', jsonb_build_object('radio_min_m', redes.f_param('evento_radio_min_m'), 'radio_max_m', redes.f_param('evento_radio_max_m'),
                                  'sectores_max', redes.f_param('evento_sectores_max'), 'horas_atras_max', redes.f_param('evento_horas_atras_max')),
    'sectores', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', coalesce(nullif(btrim(m.nombre), ''), m.codigo), 'clase', m.clase) order by m.clase, m.nombre, m.codigo)
                            from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto), '[]'::jsonb),
    'plantas', coalesce((select jsonb_agg(jsonb_build_object('codigo', pl.codigo, 'nombre', pl.nombre,
                           'sectores', '[]'::jsonb) order by pl.id)      -- obsoleta (20-nov): los sectores son de los tubos de salida
                           from tecnica.plantas pl where pl.activa), '[]'::jsonb),
    'causales', coalesce((select jsonb_agg(jsonb_build_object('codigo', k.codigo, 'nombre', k.nombre, 'activa', k.activa) order by not k.activa, k.orden, k.nombre)
                            from redes.evento_causales k), '[]'::jsonb),
    'tubos', coalesce((select jsonb_agg(jsonb_build_object('codigo', pu.codigo, 'nombre', coalesce(nullif(btrim(pu.nombre), ''), pu.codigo),
                         'planta', (select pl.nombre from tecnica.plantas pl where pl.id = pu.planta_id), 'activo', pu.activo,
                         'sectores', coalesce((select jsonb_agg(m.codigo order by m.codigo) from redes.tubo_sectores ts join redes.activo_vigente_mat m on m.activo_id = ts.sector_id
                                               where ts.punto_id = pu.id and ts.activo and not m.retirado and not m.oculto), '[]'::jsonb)) order by pu.orden nulls last, pu.codigo)
                         from tecnica.puntos pu where pu.tipo = 'distribucion'), '[]'::jsonb),
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('origen', t.origen, 'codigo', t.codigo, 'nombre', t.nombre, 'clase', t.clase, 'asocia', t.asocia) order by t.origen, t.clase, t.nombre)
                         from redes.evento_tipos_asociables t), '[]'::jsonb));
end $function$;

-- 4. El evento como objeto (detalle, lista, vigentes y respuestas): suma origen, causal y tubos; «total» = planta cuando hay planta
create or replace function redes.f_evento_json(p_evento bigint, p_geo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'codigo', e.codigo, 'estado', e.estado, 'alcance', e.alcance,
    'total', case when e.alcance = 'total' then case when e.planta_id is not null then 'planta' else 'ciudad' end end,
    'planta', (select pl.nombre from tecnica.plantas pl where pl.id = e.planta_id),
    'zona', e.zona_nombre, 'causa', e.causa,
    'origen', redes.f_evento_origen(e.id),
    'causal', (select jsonb_build_object('codigo', k.codigo, 'nombre', k.nombre) from redes.evento_causal c join redes.evento_causales k on k.codigo = c.causal where c.evento_id = e.id),
    'tubos', (select coalesce(jsonb_agg(jsonb_build_object('codigo', pu.codigo, 'nombre', coalesce(nullif(btrim(pu.nombre), ''), pu.codigo)) order by pu.codigo), '[]'::jsonb)
                from redes.evento_tubos t join tecnica.puntos pu on pu.id = t.punto_id where t.evento_id = e.id),
    'registro', coalesce((select d.codigo from redes.danos d where d.id = e.dano_id), (select i.codigo from redes.intervenciones i where i.id = e.intervencion_id)),
    'desde', e.desde, 'regreso_estimado', e.regreso_vigente, 'declarado_en', e.creado_en,
    'declarado_por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = e.autor), 'Funcionario de EMDUPAR'),
    'contratos', e.contratos, 'sensibles', e.sensibles,
    'reportes', (select jsonb_build_object('total', count(*), 'bot', count(*) filter (where r.origen = 'bot'), 'l116', count(*) filter (where r.origen = 'l116'),
                                           'danos', count(*) filter (where r.origen = 'dano'), 'campo', count(*) filter (where r.origen = 'campo')) from redes.f_evento_reportes(e.id) r),
    'franja', redes.f_evento_franja(e.zona_nombre, e.desde, e.causa, e.regreso_vigente),
    'fin', case when e.estado <> 'abierto' then jsonb_build_object('cuando', e.fin_en, 'motivo', e.fin_motivo,
              'por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = e.fin_autor), 'Funcionario de EMDUPAR')) end,
    'circulo', case when e.alcance = 'circulo' then jsonb_build_object('lat', e.centro_lat, 'lon', e.centro_lon, 'radio_m', e.radio_m) end,
    'sectores', (select coalesce(jsonb_agg(m.codigo order by m.codigo), '[]'::jsonb) from redes.activo_vigente_mat m where m.activo_id = any (e.sectores)))
    || case when p_geo then jsonb_build_object('zona_geojson', case when e.geom is not null then ST_AsGeoJSON(ST_Multi(ST_SimplifyPreserveTopology(e.geom, 0.00002)), 6)::jsonb end) else '{}'::jsonb end
    from redes.v_evento_suspension e where e.id = p_evento $function$;

-- 5. Planta → sectores: ya no se asignan
create or replace function public.geoportal_redes_planta_sectores_fijar(p_solicitante text, p_planta text, p_sectores text[], p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'reportes');
begin
  -- el sistema es único (David, 20-nov): los sectores ya no se asignan por planta (las filas se desactivaron con motivo; nada se borró)
  perform tecnica.f_error('Los sectores ya no se asignan por planta: el sistema es único. Asígnelos a los tubos de salida.');
  return null;
end $function$;

-- 6. Descargas de Distribución: las columnas de Eventos suman tubos, origen y causal
create or replace function redes.f_rep_columnas(p_reporte text) returns jsonb
language plpgsql immutable set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare ubic jsonb := jsonb_build_array(redes.f_rep_col('sector', 'Sector', 'entero'), redes.f_rep_col('lat', 'Latitud', 'decimal', null, 6), redes.f_rep_col('lon', 'Longitud', 'decimal', null, 6));
begin
  return case p_reporte
  when 'levantamientos' then jsonb_build_array(
    redes.f_rep_col('codigo', 'Código', 'texto'), redes.f_rep_col('reportado', 'Reportado', 'fecha_hora'), redes.f_rep_col('servicio', 'Servicio', 'texto'),
    redes.f_rep_col('tipo', 'Qué se reportó', 'texto'), redes.f_rep_col('area', 'Área', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'),
    redes.f_rep_col('estado_desde', 'Estado desde', 'fecha_hora'), redes.f_rep_col('activo', 'Activo creado', 'texto'), redes.f_rep_col('fotos', 'Fotos', 'entero'),
    redes.f_rep_col('precision_m', 'Precisión del GPS', 'decimal', 'm', 1), redes.f_rep_col('precision_baja', 'Precisión baja', 'si_no'))
    || ubic || jsonb_build_array(redes.f_rep_col('reporto', 'Reportó (correo)', 'texto'))
  when 'valvulas' then jsonb_build_array(
    redes.f_rep_col('valvula', 'Válvula', 'texto'), redes.f_rep_col('cerrada', 'Cerrada', 'fecha_hora'), redes.f_rep_col('regreso_estimado', 'Regreso estimado vigente', 'fecha_hora'),
    redes.f_rep_col('cambios_regreso', 'Cambios del regreso estimado', 'entero'), redes.f_rep_col('abierta', 'Abierta', 'fecha_hora'),
    redes.f_rep_col('duracion_h', 'Duración', 'decimal', 'h', 1), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('dano', 'Daño', 'texto'),
    redes.f_rep_col('intervencion', 'Intervención', 'texto'))
    || ubic || jsonb_build_array(redes.f_rep_col('cerro', 'Cerró (correo)', 'texto'), redes.f_rep_col('abrio', 'Abrió (correo)', 'texto'))
  when 'eventos' then jsonb_build_array(
    redes.f_rep_col('evento', 'Evento', 'texto'), redes.f_rep_col('alcance', 'Alcance', 'texto'), redes.f_rep_col('zona', 'Zona', 'texto'), redes.f_rep_col('tubos', 'Tubos de salida', 'texto'),
    redes.f_rep_col('planta', 'Planta', 'texto'), redes.f_rep_col('origen', 'Origen', 'texto'), redes.f_rep_col('causal', 'Causal', 'texto'),
    redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('desde', 'Sin agua desde', 'fecha_hora'),
    redes.f_rep_col('regreso_estimado_inicial', 'Regreso estimado al declarar', 'fecha_hora'), redes.f_rep_col('regreso_estimado', 'Regreso estimado vigente', 'fecha_hora'),
    redes.f_rep_col('cambios_regreso', 'Cambios del regreso estimado', 'entero'), redes.f_rep_col('fin', 'Cerrado o anulado', 'fecha_hora'),
    redes.f_rep_col('duracion_h', 'Duración', 'decimal', 'h', 1), redes.f_rep_col('contratos', 'Contratos afectados', 'entero'),
    redes.f_rep_col('sensibles', 'Usuarios sensibles afectados', 'entero'), redes.f_rep_col('reportes', 'Reportes asociados', 'entero'),
    redes.f_rep_col('reportes_bot', 'Del bot', 'entero'), redes.f_rep_col('reportes_116', 'De la 116', 'entero'), redes.f_rep_col('reportes_danos', 'Daños', 'entero'),
    redes.f_rep_col('reportes_campo', 'De campo', 'entero'), redes.f_rep_col('dano', 'Daño', 'texto'), redes.f_rep_col('tipo', 'Tipo de daño o falla', 'texto'),
    redes.f_rep_col('causa', 'Causa del daño', 'texto'), redes.f_rep_col('intervencion', 'Intervención', 'texto'), redes.f_rep_col('tipo_intervencion', 'Tipo de intervención', 'texto'),
    redes.f_rep_col('declaro', 'Declaró (correo)', 'texto'), redes.f_rep_col('cerro', 'Cerró o anuló (correo)', 'texto'))
  when 'l116' then jsonb_build_array(
    redes.f_rep_col('reporte', 'Reporte de la 116', 'entero'), redes.f_rep_col('registrado_116', 'Registrado en la 116', 'fecha_hora'), redes.f_rep_col('dia', 'Día', 'fecha'),
    redes.f_rep_col('servicio', 'Servicio', 'texto'), redes.f_rep_col('causal', 'Causal', 'texto'), redes.f_rep_col('comuna', 'Comuna', 'texto'),
    redes.f_rep_col('contrato', 'Contrato', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('estado_desde', 'Estado desde', 'fecha_hora'),
    redes.f_rep_col('ubicacion', 'Ubicación', 'texto'), redes.f_rep_col('sector', 'Sector', 'entero'), redes.f_rep_col('subsector', 'Subsector', 'texto'),
    redes.f_rep_col('oculto', 'Oculto', 'si_no'), redes.f_rep_col('lat', 'Latitud', 'decimal', null, 6), redes.f_rep_col('lon', 'Longitud', 'decimal', null, 6))
  when 'bot' then jsonb_build_array(
    redes.f_rep_col('radicado', 'Radicado', 'texto'), redes.f_rep_col('recibido', 'Recibido', 'fecha_hora'), redes.f_rep_col('canal', 'Canal', 'texto'),
    redes.f_rep_col('tipo', 'Tipo', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('ultimo_movimiento', 'Último movimiento', 'fecha_hora'),
    redes.f_rep_col('dano', 'Daño', 'texto'), redes.f_rep_col('dano_estado', 'Estado del daño', 'texto'), redes.f_rep_col('fotos', 'Fotos', 'entero')) || ubic
  when 'sensibles' then jsonb_build_array(
    redes.f_rep_col('contrato', 'Contrato', 'texto'), redes.f_rep_col('tipo', 'Tipo', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'),
    redes.f_rep_col('desde', 'Desde', 'fecha_hora'), redes.f_rep_col('origen', 'Origen', 'texto'), redes.f_rep_col('sector', 'Sector', 'entero'))
  when 'activos' then jsonb_build_array(
    redes.f_rep_col('codigo', 'Código', 'texto'), redes.f_rep_col('tipo', 'Tipo', 'texto'), redes.f_rep_col('prefijo', 'Prefijo', 'texto'), redes.f_rep_col('sistema', 'Sistema', 'texto'),
    redes.f_rep_col('clase', 'Clase', 'texto'), redes.f_rep_col('material', 'Material', 'texto'), redes.f_rep_col('diametro_mm', 'Diámetro', 'decimal', 'mm', 1),
    redes.f_rep_col('longitud_m', 'Longitud', 'decimal', 'm', 2), redes.f_rep_col('profundidad_m', 'Profundidad', 'decimal', 'm', 2),
    redes.f_rep_col('instalacion', 'Instalación', 'fecha'), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('retirado', 'Retirado', 'si_no'),
    redes.f_rep_col('oculto', 'Oculto', 'si_no'), redes.f_rep_col('codigo_anterior', 'Código anterior', 'texto')) || ubic
  end;
end $$;

-- 7. Descargas de Distribución: Eventos con «Por tubo», los tubos, el origen y la causal
create or replace function redes.f_rep_eventos(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language sql stable set search_path to 'redes', 'public', 'tecnica', 'extensions', 'pg_temp' as $$
  with sg as (select redes.f_rep_sector_geom(p_f ->> 'sector') as g where p_f ? 'sector'),
  x as (select e.* from redes.v_evento_suspension e
         where e.creado_en <= p_corte
           and e.desde < (((p_f ->> 'hasta')::date + 1)::timestamp at time zone 'America/Bogota')
           and coalesce(e.fin_en, 'infinity'::timestamptz) >= ((p_f ->> 'desde')::date::timestamp at time zone 'America/Bogota')
           and (p_incl or e.estado <> 'anulado') and (not p_f ? 'sector' or e.todo or ST_Intersects(e.geom, (select g from sg)))
           and (p_cursor is null or e.id > p_cursor::bigint)
         order by e.id limit p_limite)
  select lpad(x.id::text, 19, '0'),
         case when p_solo_llave then null else jsonb_build_object('evento', x.codigo,
           'alcance', case when x.planta_id is not null then 'Planta' when tb.tubos is not null then 'Por tubo' when x.alcance = 'sectores' then 'Sectores' when x.alcance = 'circulo' then 'Círculo' else 'Toda la ciudad' end,
           'zona', x.zona_nombre, 'tubos', tb.tubos, 'origen', redes.f_evento_origen(x.id) ->> 'nombre',
           'causal', (select k.nombre from redes.evento_causal c join redes.evento_causales k on k.codigo = c.causal where c.evento_id = x.id), 'planta', (select pl.nombre from tecnica.plantas pl where pl.id = x.planta_id), 'estado', redes.f_rep_rotulo(x.estado),
           'desde', redes.f_rep_ts(x.desde), 'regreso_estimado_inicial', redes.f_rep_ts(x.regreso_estimado), 'regreso_estimado', redes.f_rep_ts(x.regreso_vigente),
           'cambios_regreso', (select count(*) from redes.evento_suspension_eventos z where z.evento_id = x.id and z.tipo = 'regreso'),
           'fin', redes.f_rep_ts(x.fin_en), 'duracion_h', case when x.fin_en is not null then round(extract(epoch from x.fin_en - x.desde) / 3600.0, 1) end,
           'contratos', x.contratos, 'sensibles', x.sensibles, 'reportes', r.n, 'reportes_bot', r.bot, 'reportes_116', r.l116, 'reportes_danos', r.dano, 'reportes_campo', r.campo,
           'dano', cat.dano, 'tipo', cat.tipo, 'causa', cat.causa, 'intervencion', cat.intervencion, 'tipo_intervencion', cat.tipo_intervencion,
           'declaro', x.autor, 'cerro', x.fin_autor) end
    from x
    left join lateral (select case when x.dano_id is not null then d.codigo end as dano, td.nombre as tipo, i.codigo as intervencion, ti.nombre as tipo_intervencion,
                              case d.causa_clase when 'propia' then coalesce(ca.nombre, 'Propia') when 'terceros' then 'Terceros' || coalesce(': ' || tt.nombre, '')
                                                 when 'desconocida' then 'Desconocida' end as causa
                         from (select 1) u
                         left join redes.intervenciones i on i.id = x.intervencion_id
                         left join redes.tipos_intervencion ti on ti.codigo = i.tipo_codigo
                         left join redes.danos d on d.id = coalesce(x.dano_id, i.dano_id)
                         left join redes.tipos_dano td on td.codigo = d.tipo_codigo
                         left join redes.causas ca on ca.codigo = d.causa_codigo
                         left join redes.tipos_tercero tt on tt.codigo = d.tercero_tipo) cat on not p_solo_llave
    left join lateral (select string_agg(pu.codigo, ', ' order by pu.codigo) as tubos from redes.evento_tubos t join tecnica.puntos pu on pu.id = t.punto_id
                        where t.evento_id = x.id) tb on not p_solo_llave
    cross join lateral (select count(*) as n, count(*) filter (where v.origen = 'bot') as bot, count(*) filter (where v.origen = 'l116') as l116,
                                      count(*) filter (where v.origen = 'dano') as dano, count(*) filter (where v.origen = 'campo') as campo
                                 from redes.f_evento_reportes(x.id) v) r
   order by x.id $$;

-- 8. Descargas de Distribución: el Léame de Eventos
create or replace function redes.f_rep_leame(p_reporte text, p_f jsonb, p_incl boolean, p_email text, p_corte timestamptz) returns jsonb
language plpgsql stable set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare c record; v_trae text[]; v_no text[] := array['Textos libres (descripciones, observaciones, motivos y causas escritas): pueden traer datos de personas y se ven solo en pantalla.',
                                                       'Teléfonos y nombres de suscriptores, del ciudadano que reporta o de terceros.'];
  v_filtros text[] := '{}'; v_ex text;
begin
  select * into c from redes.f_rep_catalogo() x where x.clave = p_reporte;
  v_trae := case p_reporte
    when 'levantamientos' then array['Una fila por punto de «Encontrar o reportar activo» (código LEV), con su estado vigente, el activo creado si se levantó y su ubicación.']
    when 'valvulas' then array['Una fila por cierre de una válvula, con el regreso estimado vigente, la apertura y la duración. Una válvula que sigue cerrada no tiene apertura.']
    when 'eventos' then array['Una fila por evento de suspensión vigente algún momento del periodo: zona, desde cuándo, regreso estimado (al declarar y el vigente), fin y duración.',
                              'Contratos y usuarios sensibles afectados como números (los que se calcularon al declarar) y los reportes asociados hoy, por origen.',
                              'El tipo de daño o falla y la causa del daño salen del catálogo del daño asociado (el del evento o el de su intervención); vacíos si el evento no tiene daño.',
                              'Origen: Daño, Intervención, Trabajo (con su causal de catálogo) o «No registrado (anterior al cambio)». Un evento «Por tubo» dice de qué tubos de salida se declaró y cubre sus sectores.']
    when 'l116' then array['Una fila por reporte de la línea 116 cargado, con su estado vigente, el contrato y la ubicación (por contrato o sin ubicar).']
    when 'bot' then array['Una fila por reporte recibido del bot, con su estado y el daño en que se convirtió, si se convirtió.']
    when 'sensibles' then array['Una fila por contrato marcado como usuario sensible, con su tipo y estado de hoy (inventario a la fecha de la descarga).']
    when 'activos' then array['Una fila por activo de la red tal como está hoy (inventario a la fecha de la descarga), con un punto del activo para ubicarlo.']
  end;
  if p_reporte = 'bot' then v_no := v_no || array['La descripción y la dirección que escribió el ciudadano.']; end if;
  if p_reporte = 'sensibles' then v_no := v_no || array['El nombre del suscriptor ni la palabra del nombre que lo marcó.']; end if;
  if p_reporte = 'eventos' then v_no := v_no || array['La observación escrita al declarar el evento ni los motivos de cierre o anulación (texto libre): se ven solo en pantalla.']; end if;
  if c.periodo then
    v_filtros := array['Periodo: ' || to_char((p_f ->> 'desde')::date, 'DD/MM/YYYY') || ' a ' || to_char((p_f ->> 'hasta')::date, 'DD/MM/YYYY') || ' (según ' || c.periodo_sobre || ')'];
  else
    v_filtros := array['Inventario al ' || to_char(p_corte at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI')];
  end if;
  if p_f ? 'sector' then v_filtros := v_filtros || ('Sector: ' || (p_f ->> 'sector_nombre') || ' (' || (p_f ->> 'sector') || ')'); end if;
  if p_f ? 'tipo' then v_filtros := v_filtros || ('Tipo: ' || (p_f ->> 'tipo_nombre')); end if;
  if p_f ? 'sistema' then v_filtros := v_filtros || ('Sistema: ' || redes.f_rep_rotulo(p_f ->> 'sistema')); end if;
  v_ex := case when not c.usa_ocultos then null
               when p_reporte in ('levantamientos', 'bot', 'sensibles') then case when p_incl then 'Descartados: incluidos' else 'Descartados: no incluidos' end
               when p_reporte = 'eventos' then case when p_incl then 'Eventos anulados: incluidos' else 'Eventos anulados: no incluidos' end
               when p_reporte = 'activos' then case when p_incl then 'Retirados y ocultos: incluidos' else 'Retirados y ocultos: no incluidos' end
               else case when p_incl then 'Ocultos: incluidos' else 'Ocultos: no incluidos' end end;
  if v_ex is not null then v_filtros := v_filtros || v_ex; end if;
  return jsonb_build_object('que_trae', to_jsonb(v_trae), 'que_no_trae', to_jsonb(v_no), 'filtros', to_jsonb(v_filtros),
                            'generado_por', p_email, 'generado_en', redes.f_rep_ts(p_corte));
end $$;

-- 9. Reportes del PTAP: las columnas de Eventos de planta suman origen y causal
create or replace function tecnica.f_rep_columnas(p_reporte text, p_f jsonb) returns jsonb
language plpgsql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare c jsonb; v_desde date := (p_f ->> 'desde')::date; v_hasta date := (p_f ->> 'hasta')::date;
  fin_envio jsonb := jsonb_build_array(
    tecnica.f_rep_col('fuera_referencia', 'Valores fuera de referencia', 'entero'),
    tecnica.f_rep_col('estado', 'Estado', 'texto'),
    tecnica.f_rep_col('fuente', 'Fuente', 'texto'),
    tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'),
    tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'),
    tecnica.f_rep_col('envio', 'Envío (identificador)', 'texto'));
begin
  case p_reporte
  when 'entrada' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('planta', 'Planta', 'texto'))
         || tecnica.f_rep_cols_variables('entrada', v_desde, v_hasta)
         || jsonb_build_array(tecnica.f_rep_col('coagulante', 'Coagulante', 'texto'), tecnica.f_rep_col('dosis_ppm', 'Dosis de coagulante', 'decimal', 'ppm', 2))
         || fin_envio;
  when 'salida' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('planta', 'Planta', 'texto'),
                           tecnica.f_rep_col('punto', 'Punto', 'texto'), tecnica.f_rep_col('punto_nombre', 'Nombre del punto', 'texto'))
         || tecnica.f_rep_cols_variables('salida', v_desde, v_hasta) || fin_envio;
  when 'muestreo' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('punto', 'Punto', 'texto'),
                           tecnica.f_rep_col('punto_nombre', 'Nombre del punto', 'texto'), tecnica.f_rep_col('tipo_punto', 'Tipo de punto', 'texto'),
                           tecnica.f_rep_col('zona', 'Zona', 'texto'), tecnica.f_rep_col('numero_informe', 'Número en el informe', 'entero'))
         || tecnica.f_rep_cols_variables('muestreo', v_desde, v_hasta) || fin_envio;
  when 'uso_quimicos' then
    c := jsonb_build_array(tecnica.f_rep_col('movimiento', 'Movimiento', 'entero'), tecnica.f_rep_col('dia', 'Día', 'fecha'), tecnica.f_rep_col('quimico', 'Químico', 'texto'),
                           tecnica.f_rep_col('planta', 'Planta', 'texto'), tecnica.f_rep_col('para_que', 'Para qué', 'texto'),
                           tecnica.f_rep_col('cantidad', 'Cantidad digitada', 'decimal', null, 3), tecnica.f_rep_col('unidad', 'Unidad digitada', 'texto'),
                           tecnica.f_rep_col('cantidad_kg', 'Cantidad', 'decimal', 'kg', 3), tecnica.f_rep_col('dosis_optima_ppm', 'Dosis óptima vigente', 'decimal', 'ppm', 2),
                           tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'), tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'));
  when 'entrada_quimicos' then
    c := jsonb_build_array(tecnica.f_rep_col('movimiento', 'Movimiento', 'entero'), tecnica.f_rep_col('dia', 'Día', 'fecha'), tecnica.f_rep_col('quimico', 'Químico', 'texto'),
                           tecnica.f_rep_col('cantidad', 'Cantidad digitada', 'decimal', null, 3), tecnica.f_rep_col('unidad', 'Unidad digitada', 'texto'),
                           tecnica.f_rep_col('cantidad_kg', 'Cantidad', 'decimal', 'kg', 3), tecnica.f_rep_col('proveedor', 'Proveedor', 'texto'),
                           tecnica.f_rep_col('remision', 'Remisión', 'texto'), tecnica.f_rep_col('lote_fabricante', 'Lote del fabricante', 'texto'),
                           tecnica.f_rep_col('vence', 'Vence', 'fecha'), tecnica.f_rep_col('foto_remision', 'Foto de la remisión', 'enlace'),
                           tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'), tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'));
  when 'kardex_quimicos' then
    c := jsonb_build_array(tecnica.f_rep_col('quimico', 'Químico', 'texto'), tecnica.f_rep_col('bodega', 'Bodega', 'texto'), tecnica.f_rep_col('dia', 'Día', 'fecha'),
                           tecnica.f_rep_col('movimiento', 'Movimiento', 'entero'), tecnica.f_rep_col('tipo', 'Tipo', 'texto'), tecnica.f_rep_col('planta', 'Planta', 'texto'),
                           tecnica.f_rep_col('detalle', 'Detalle', 'texto'), tecnica.f_rep_col('entra_kg', 'Entra', 'decimal', 'kg', 3),
                           tecnica.f_rep_col('sale_kg', 'Sale', 'decimal', 'kg', 3), tecnica.f_rep_col('conteo_kg', 'Conteo físico', 'decimal', 'kg', 3),
                           tecnica.f_rep_col('saldo_kg', 'Saldo', 'decimal', 'kg', 3), tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'));
  when 'eventos_planta' then
    c := jsonb_build_array(tecnica.f_rep_col('evento', 'Evento', 'texto'), tecnica.f_rep_col('planta', 'Planta', 'texto'), tecnica.f_rep_col('estado', 'Estado', 'texto'),
                           tecnica.f_rep_col('suspendido', 'Suspendido desde', 'fecha_hora'), tecnica.f_rep_col('regreso_estimado_inicial', 'Regreso estimado al declarar', 'fecha_hora'),
                           tecnica.f_rep_col('regreso_estimado', 'Regreso estimado vigente', 'fecha_hora'), tecnica.f_rep_col('cambios_regreso', 'Cambios del regreso estimado', 'entero'),
                           tecnica.f_rep_col('reanudado', 'Reanudado', 'fecha_hora'), tecnica.f_rep_col('duracion_h', 'Duración', 'decimal', 'h', 1),
                           tecnica.f_rep_col('contratos', 'Contratos afectados', 'entero'), tecnica.f_rep_col('sensibles', 'Usuarios sensibles afectados', 'entero'),
                           tecnica.f_rep_col('reportes', 'Reportes asociados', 'entero'), tecnica.f_rep_col('dano', 'Daño', 'texto'),
                           tecnica.f_rep_col('tipo', 'Tipo de daño o falla', 'texto'), tecnica.f_rep_col('causa', 'Causa del daño', 'texto'),
                           tecnica.f_rep_col('intervencion', 'Intervención', 'texto'), tecnica.f_rep_col('tipo_intervencion', 'Tipo de intervención', 'texto'),
                           tecnica.f_rep_col('origen', 'Origen', 'texto'), tecnica.f_rep_col('causal', 'Causal', 'texto'),
                           tecnica.f_rep_col('declaro', 'Declaró (correo)', 'texto'),
                           tecnica.f_rep_col('cerro', 'Cerró o anuló (correo)', 'texto'));
  when 'fuera_referencia' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('formulario', 'Formulario', 'texto'),
                           tecnica.f_rep_col('planta', 'Planta', 'texto'), tecnica.f_rep_col('punto', 'Punto', 'texto'), tecnica.f_rep_col('variable', 'Variable', 'texto'),
                           tecnica.f_rep_col('valor', 'Valor', 'decimal', null, 6), tecnica.f_rep_col('unidad', 'Unidad', 'texto'), tecnica.f_rep_col('marca', 'Marca', 'texto'),
                           tecnica.f_rep_col('ref_min', 'Referencia mínima', 'decimal', null, 6), tecnica.f_rep_col('ref_max', 'Referencia máxima', 'decimal', null, 6),
                           tecnica.f_rep_col('ref_origen', 'Origen de la referencia', 'texto'), tecnica.f_rep_col('revision', 'Revisión', 'texto'),
                           tecnica.f_rep_col('revisado_por', 'Revisó (correo)', 'texto'), tecnica.f_rep_col('revisado_en', 'Revisado', 'fecha_hora'),
                           tecnica.f_rep_col('excluido', 'Excluido', 'si_no'), tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'),
                           tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'), tecnica.f_rep_col('registro_id', 'Registro', 'entero'));
  else perform tecnica.f_error('Ese reporte no existe.');
  end case;
  return c;
end $$;

-- 10. Reportes del PTAP: Eventos de planta con el origen y la causal
create or replace function tecnica.f_rep_eventos_planta(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer) returns table (k text, fila jsonb)
language sql stable set search_path to 'public', 'tecnica', 'redes', 'pg_temp' as $$
  select lpad(e.id::text, 19, '0'),
         jsonb_build_object('evento', e.codigo, 'planta', pl.nombre, 'estado', case e.estado when 'abierto' then 'Abierto' when 'cerrado' then 'Cerrado' else 'Anulado' end,
           'suspendido', tecnica.f_rep_ts(e.desde), 'regreso_estimado_inicial', tecnica.f_rep_ts(e.regreso_estimado), 'regreso_estimado', tecnica.f_rep_ts(e.regreso_vigente),
           'cambios_regreso', (select count(*) from redes.evento_suspension_eventos x where x.evento_id = e.id and x.tipo = 'regreso'),
           'reanudado', case when e.estado = 'cerrado' then tecnica.f_rep_ts(e.fin_en) end,
           'duracion_h', case when e.estado = 'cerrado' then round(extract(epoch from e.fin_en - e.desde) / 3600.0, 1) end,
           'contratos', e.contratos, 'sensibles', e.sensibles, 'reportes', (select count(*) from redes.f_evento_reportes(e.id)),
           'dano', cat.dano, 'tipo', cat.tipo, 'causa', cat.causa, 'intervencion', cat.intervencion, 'tipo_intervencion', cat.tipo_intervencion,
           'origen', redes.f_evento_origen(e.id) ->> 'nombre',
           'causal', (select k.nombre from redes.evento_causal c join redes.evento_causales k on k.codigo = c.causal where c.evento_id = e.id),
           'declaro', e.autor, 'cerro', e.fin_autor)
    from redes.v_evento_suspension e join tecnica.plantas pl on pl.id = e.planta_id
    -- del catálogo (David, 20-nov): el tipo y la causa del daño asociado (el del evento o el de su intervención) y el tipo de la intervención; la causa ESCRITA no
    left join lateral (select case when e.dano_id is not null then d.codigo end as dano, td.nombre as tipo, i.codigo as intervencion, ti.nombre as tipo_intervencion,
                              case d.causa_clase when 'propia' then coalesce(ca.nombre, 'Propia') when 'terceros' then 'Terceros' || coalesce(': ' || tt.nombre, '')
                                                 when 'desconocida' then 'Desconocida' end as causa
                         from (select 1) u
                         left join redes.intervenciones i on i.id = e.intervencion_id
                         left join redes.tipos_intervencion ti on ti.codigo = i.tipo_codigo
                         left join redes.danos d on d.id = coalesce(e.dano_id, i.dano_id)
                         left join redes.tipos_dano td on td.codigo = d.tipo_codigo
                         left join redes.causas ca on ca.codigo = d.causa_codigo
                         left join redes.tipos_tercero tt on tt.codigo = d.tercero_tipo) cat on true
   where e.planta_id is not null and e.creado_en <= p_corte
     and e.desde < (((p_f ->> 'hasta')::date + 1)::timestamp at time zone 'America/Bogota')
     and coalesce(e.fin_en, 'infinity'::timestamptz) >= ((p_f ->> 'desde')::date::timestamp at time zone 'America/Bogota')
     and (p_incl or e.estado <> 'anulado') and (p_f ->> 'planta' is null or pl.codigo = p_f ->> 'planta')
     and (p_cursor is null or e.id > p_cursor::bigint)
   order by e.id
   limit p_limite $$;

-- 11. Reportes del PTAP: el Léame de Eventos de planta
create or replace function tecnica.f_rep_leame(p_reporte text, p_f jsonb, p_incl boolean, p_email text, p_corte timestamptz) returns jsonb
language plpgsql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare c record; v_trae text[]; v_no text[] := array['Textos libres (descripciones, observaciones, motivos y notas): pueden traer datos de personas y se ven solo en pantalla.',
                                                       'Teléfonos y nombres de suscriptores o de terceros.'];
  v_filtros text[]; v_ex text;
begin
  select * into c from tecnica.f_rep_catalogo() x where x.clave = p_reporte;
  v_trae := case p_reporte
    when 'entrada' then array['Una fila por envío del formulario Entrada y por planta, con una columna por variable (las unidades van en el encabezado).',
                              'La dosis de coagulante registrada con el mismo envío («Otro» sale sin su nombre).',
                              'Cuántos valores del envío quedaron fuera de referencia y si el envío está vigente o excluido.']
    when 'salida' then array['Una fila por envío del formulario Salida y por lugar (planta o punto), con una columna por variable.',
                             'Cuántos valores del envío quedaron fuera de referencia y si el envío está vigente o excluido.']
    when 'muestreo' then array['Una fila por muestra (envío de un punto), con una columna por parámetro.',
                               'Si los resultados de una misma muestra llegaron en varios envíos, sale una fila por envío.',
                               'Cuántos valores quedaron fuera de referencia y si el envío está vigente o excluido.']
    when 'uso_quimicos' then array['Una fila por uso registrado (formulario Uso de químicos), con la cantidad digitada y en kg, y la dosis óptima vigente al registrarlo.']
    when 'entrada_quimicos' then array['Una fila por entrada a la bodega (formulario Entrada de químicos).',
                                       'La foto de la remisión va como enlace: se abre en el geoportal con su sesión (solo supervisor de planta y administrador).']
    when 'kardex_quimicos' then array['Por químico: el saldo al empezar el periodo, cada movimiento (inventario inicial, entrada, uso y ajuste por conteo) con el saldo corrido, y el saldo al cierre.',
                                      'Orden: por día y, el mismo día, por número de movimiento. Un inventario inicial reemplaza el saldo por lo contado.',
                                      'Antes del primer inventario inicial de un químico el saldo es desconocido y la celda va vacía.',
                                      'Hoy hay una sola bodega de químicos.']
    when 'eventos_planta' then array['Una fila por evento de suspensión declarado para una planta, vigente algún momento del periodo: suspensión, regreso estimado (al declarar y el vigente), reanudación y duración.',
                                     'Contratos y usuarios sensibles afectados como números (los que se calcularon al declarar), y cuántos reportes tiene asociados hoy.',
                                     'El tipo de daño o falla y la causa del daño salen del catálogo del daño asociado (el del evento o el de su intervención); vacíos si el evento no tiene daño.',
                                     'Origen: Daño, Intervención, Trabajo (con su causal de catálogo) o «No registrado (anterior al cambio)». Desde el 20-nov un evento de planta cubre toda la ciudad (el sistema es único).']
    when 'fuera_referencia' then array['Una fila por valor de Entrada, Salida o Muestreo fuera de su referencia vigente, con la revisión vigente (la más reciente): su estado, quién y cuándo. No trae el historial de revisiones.']
  end;
  if p_reporte = 'eventos_planta' then v_no := v_no || array['La observación escrita al declarar el evento ni los motivos de cierre o anulación (texto libre): se ven solo en pantalla.']; end if;
  if p_reporte = 'fuera_referencia' then v_no := v_no || array['La nota de la revisión (texto libre).']; end if;
  if p_reporte in ('uso_quimicos', 'entrada_quimicos', 'kardex_quimicos') then v_no := v_no || array['Los motivos de inventarios y ajustes (texto libre).']; end if;
  v_filtros := array['Periodo: ' || to_char((p_f ->> 'desde')::date, 'DD/MM/YYYY') || ' a ' || to_char((p_f ->> 'hasta')::date, 'DD/MM/YYYY') || ' (según ' || c.periodo_sobre || ')'];
  if p_f ? 'planta' then v_filtros := v_filtros || ('Planta: ' || (p_f ->> 'planta_nombre')); end if;
  if p_f ? 'punto' then v_filtros := v_filtros || ('Punto: ' || (p_f ->> 'punto') || ' · ' || (p_f ->> 'punto_nombre')); end if;
  if p_f ? 'zona' then v_filtros := v_filtros || ('Zona: ' || initcap(p_f ->> 'zona')); end if;
  if p_f ? 'quimico' then v_filtros := v_filtros || ('Químico: ' || (p_f ->> 'quimico_nombre')); end if;
  if p_f ? 'formulario' then v_filtros := v_filtros || ('Formulario: ' || initcap(p_f ->> 'formulario')); end if;
  v_ex := case when not c.usa_excluidos then null
               when p_reporte = 'eventos_planta' then case when p_incl then 'Eventos anulados: incluidos' else 'Eventos anulados: no incluidos' end
               else case when p_incl then 'Valores excluidos: incluidos' else 'Valores excluidos: no incluidos' end end;
  if v_ex is not null then v_filtros := v_filtros || v_ex; end if;
  return jsonb_build_object('que_trae', to_jsonb(v_trae), 'que_no_trae', to_jsonb(v_no), 'filtros', to_jsonb(v_filtros),
                            'generado_por', p_email, 'generado_en', tecnica.f_rep_ts(p_corte));
end $$;
-- =====================================================================
-- 26 — RPC NUEVAS (las llama la Edge geoportal-redes). Quién puede lo decide redes.f_evento_autorizar(…, 'reportes'), como evento_tipo_fijar
-- y planta_sectores_fijar: el supervisor de distribución y el administrador.
-- =====================================================================
-- Las causales de un evento de trabajo: crear (sin código) o cambiar el nombre, activarla o desactivarla (con código). Siempre con motivo; queda el historial.
create function public.geoportal_redes_evento_causal_fijar(p_solicitante text, p_codigo text, p_nombre text, p_activa boolean, p_motivo text) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'reportes'); v_cod text := nullif(lower(btrim(coalesce(p_codigo, ''))), '');
  v_nom text := nullif(regexp_replace(btrim(coalesce(p_nombre, '')), '\s+', ' ', 'g'), ''); v_mot text := btrim(coalesce(p_motivo, '')); k redes.evento_causales%rowtype; v_acc text;
begin
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  if v_nom is not null and (length(v_nom) < 3 or length(v_nom) > 80) then perform tecnica.f_error('El nombre de la causal va de 3 a 80 letras'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.evento_causales'));
  if v_cod is null then
    if v_nom is null then perform tecnica.f_error('Escriba el nombre de la causal'); end if;
    v_cod := left(trim(both '_' from regexp_replace(translate(lower(v_nom), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', '_', 'g')), 40);
    if v_cod !~ '^[a-z][a-z0-9_]{1,39}$' then perform tecnica.f_error('El nombre de la causal debe empezar con una letra'); end if;
    if exists (select 1 from redes.evento_causales c where c.codigo = v_cod or lower(c.nombre) = lower(v_nom)) then perform tecnica.f_error('Ya hay una causal con ese nombre'); end if;
    insert into redes.evento_causales (codigo, nombre, activa, orden) values (v_cod, v_nom, coalesce(p_activa, true), 50);
    v_acc := 'crear';
  else
    select * into k from redes.evento_causales c where c.codigo = v_cod;
    if k.codigo is null then perform tecnica.f_error('Esa causal no existe', 'P0002'); end if;
    if v_nom is null and p_activa is null then perform tecnica.f_error('Diga qué cambia: el nombre o si está activa'); end if;
    if v_nom is not null and exists (select 1 from redes.evento_causales c where c.codigo <> v_cod and lower(c.nombre) = lower(v_nom)) then perform tecnica.f_error('Ya hay una causal con ese nombre'); end if;
    update redes.evento_causales set nombre = coalesce(v_nom, nombre), activa = coalesce(p_activa, activa) where codigo = v_cod;
    v_acc := 'cambiar';
  end if;
  select * into k from redes.evento_causales c where c.codigo = v_cod;
  insert into redes.evento_causal_eventos (codigo, accion, nombre, activa, motivo, autor) values (k.codigo, v_acc, k.nombre, k.activa, v_mot, v_email);
  return jsonb_build_object('codigo', k.codigo, 'nombre', k.nombre, 'activa', k.activa);
end $$;

-- Qué sectores o subsectores abastece un tubo de salida (la lista completa cada vez, como planta_sectores_fijar). Con motivo; queda el historial.
create function public.geoportal_redes_tubo_sectores_fijar(p_solicitante text, p_tubo text, p_sectores text[], p_motivo text) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'reportes'); v_mot text := btrim(coalesce(p_motivo, '')); v_tubo tecnica.puntos%rowtype; v_cods text[]; v_ids bigint[];
begin
  select * into v_tubo from tecnica.puntos pu where pu.codigo = upper(btrim(coalesce(p_tubo, ''))) and pu.tipo = 'distribucion' and pu.activo;
  if v_tubo.id is null then perform tecnica.f_error('Ese tubo de salida no existe o está inactivo.'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  select coalesce(array_agg(distinct upper(btrim(x))), '{}') into v_cods from unnest(coalesce(p_sectores, '{}')) x where btrim(coalesce(x, '')) <> '';
  select coalesce(array_agg(m.activo_id order by m.codigo), '{}') into v_ids from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.codigo = any (v_cods);
  if cardinality(v_ids) <> cardinality(v_cods) then perform tecnica.f_error('Alguno de los sectores no existe o ya no está vigente', 'P0002'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.tubo_sectores'));
  update redes.tubo_sectores set activo = false where punto_id = v_tubo.id and activo and sector_id <> all (v_ids);
  insert into redes.tubo_sectores (punto_id, sector_id) select v_tubo.id, x from unnest(v_ids) x
  on conflict (punto_id, sector_id) do update set activo = true;
  insert into redes.tubo_sector_eventos (punto_id, sectores, motivo, autor) values (v_tubo.id, v_ids, v_mot, v_email);
  return jsonb_build_object('tubo', v_tubo.codigo, 'nombre', coalesce(nullif(btrim(v_tubo.nombre), ''), v_tubo.codigo),
                            'sectores', (select coalesce(jsonb_agg(m.codigo order by m.codigo), '[]'::jsonb) from redes.activo_vigente_mat m where m.activo_id = any (v_ids)));
end $$;
-- =====================================================================
-- 40 — PERMISOS: lo nuevo, por NOMBRE EXACTO (nunca por patrón). Las 2 RPC nuevas solo para service_role (la Edge); las internas, para nadie.
-- Las funciones reemplazadas conservan sus permisos (create or replace no los cambia).
-- =====================================================================
revoke all on function redes.f_evento_origen(bigint) from public, anon, authenticated, service_role;
revoke all on function redes.f_tubo_zona(text[]) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_redes_evento_causal_fijar(text, text, text, boolean, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_redes_tubo_sectores_fijar(text, text, text[], text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_evento_causal_fijar(text, text, text, boolean, text) to service_role;
grant execute on function public.geoportal_redes_tubo_sectores_fijar(text, text, text[], text) to service_role;
notify pgrst, 'reload schema';
-- =====================================================================
-- TÉCNICA · FASE 1 · EVENTOS: ORIGEN Y TUBOS · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 25, 26 y 40, en la misma transacción.
-- Todo es SIMULADO y se deshace: personas prueba.evt.*, una planta ZTEVT, 3 tubos de salida ZTEVT (uno sin sectores), un punto de muestreo ZTEVT,
-- 3 sectores ZTEVT en un rincón de la caja, un tramo y un contrato de prueba (999999991001), daños e intervención de prueba.
-- CADA PRUEBA CUENTA SOLO SUS FILAS DE PRUEBA (lección del 20-nov: 08.02 y 17.01 dependían de que la base real estuviera vacía).
-- Los textos libres de prueba llevan un nombre y un teléfono inventados («ZTEVT Pedro Prueba 3009990000») para comprobar que no salen en las descargas.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · eventos (origen y tubos) … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.1300 + y * 0.0000090437, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.5800 + x * 0.0000091290, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.caja(x1 numeric, y1 numeric, x2 numeric, y2 numeric) returns geometry language sql as $$
  select ST_Multi(ST_MakeEnvelope(pg_temp.lon(x1), pg_temp.lat(y1), pg_temp.lon(x2), pg_temp.lat(y2), 4326)) $$;
create temp table _zt (nombre text primary key, activo_id bigint, codigo text);
create function pg_temp.activo(p_nombre text, p_prefijo text, p_geom geometry, p_clase text default null, p_atributos jsonb default '{}') returns text language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.evt.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZTEVT ' || p_nombre, p_clase, case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end,
          case when p_prefijo = 'RED' then 110 end, 'en_operacion', p_atributos, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZTEVT activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  insert into _zt values (p_nombre, v_id, v_cod);
  return v_cod;
end $$;
create function pg_temp.id(p_nombre text) returns bigint language sql as $$ select activo_id from _zt where nombre = p_nombre $$;
create function pg_temp.cod(p_nombre text) returns text language sql as $$ select codigo from _zt where nombre = p_nombre $$;
create function pg_temp.claves(j jsonb) returns text language sql as $$ select string_agg(k, ',' order by k) from jsonb_object_keys(j) k $$;
-- todas las filas de una descarga de Distribución o del PTAP, página por página
create function pg_temp.bajar(p_esq text, p_quien text, p_rep text, p_f jsonb, p_incl boolean default true) returns jsonb language plpgsql as $$
declare v_i jsonb; v_c text; v_r jsonb; v_todas jsonb := '[]'; i integer := 0;
begin
  v_i := case p_esq when 'redes' then public.geoportal_redes_reporte_iniciar(p_quien, p_rep, p_f, 'xlsx', p_incl, null) else public.geoportal_tec_reporte_iniciar(p_quien, p_rep, p_f, 'xlsx', p_incl, null) end;
  loop
    v_r := case p_esq when 'redes' then public.geoportal_redes_reporte_pagina(p_quien, (v_i ->> 'descarga_id')::bigint, v_c, 5000) else public.geoportal_tec_reporte_pagina(p_quien, (v_i ->> 'descarga_id')::bigint, v_c, 5000) end;
    v_todas := v_todas || (v_r -> 'filas'); v_c := v_r ->> 'cursor'; i := i + 1;
    exit when v_c is null or i > 200;
  end loop;
  return jsonb_build_object('ini', v_i, 'filas', v_todas);
end $$;
create function pg_temp.fila(p_filas jsonb, p_clave text, p_valor text) returns jsonb language sql as $$
  select f from jsonb_array_elements(p_filas) f where f ->> p_clave = p_valor limit 1 $$;
-- la respuesta de evento_contrato sin lo que depende del código o del nombre de la zona (para comparar un evento por tubo con el mismo por sectores)
create function pg_temp.contrato_sin_codigo(j jsonb) returns jsonb language sql as $$
  select (j - 'consultado_en' - 'otros_eventos') || jsonb_build_object('evento', (j -> 'evento') - 'codigo' - 'zona_nombre' - 'texto') $$;

do $prueba$
declare
  adm text := 'prueba.evt.adm@emdupar.gov.co'; sd text := 'prueba.evt.sd@emdupar.gov.co'; sp text := 'prueba.evt.sp@emdupar.gov.co'; op text := 'prueba.evt.op@emdupar.gov.co';
  libre text := 'ZTEVT Pedro Prueba 3009990000'; ct text := '999999991001';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; per jsonb; j jsonb; j2 jsonb; f jsonb; v_txt text; v_pl bigint; v_t1 bigint; v_t2 bigint; v_t3 bigint; v_m1 bigint;
  v_dan text; v_itv text; v_viejo bigint; v_viejo2 bigint; e_tubo text; e_sec text; e_pl text; e_dan text; e_otra text; v_desde text; r_tubo jsonb; r_sec jsonb; v_hay_todo boolean;
  v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_info text; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTEVT Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZTEVT Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZTEVT Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZTEVT Operador', 'consulta', true, 'sin_restriccion', 'todos');
  per := jsonb_build_object('desde', (hoy - 2)::text, 'hasta', hoy::text);
  v_desde := to_char(clock_timestamp() - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SSOF');

  -- ---------- datos de prueba: planta, 3 tubos (T3 sin sectores), un punto de muestreo, 3 sectores, un tramo y un contrato ----------
  insert into tecnica.plantas (codigo, nombre) values ('zt_evt_pl', 'ZTEVT Planta') returning id into v_pl;
  insert into tecnica.puntos (codigo, nombre, tipo, planta_id, orden) values ('ZTEVT-T1', 'ZTEVT Distrito Uno', 'distribucion', v_pl, 9991) returning id into v_t1;
  insert into tecnica.puntos (codigo, nombre, tipo, planta_id, orden) values ('ZTEVT-T2', 'ZTEVT Distrito Dos', 'distribucion', v_pl, 9992) returning id into v_t2;
  insert into tecnica.puntos (codigo, nombre, tipo, planta_id, orden) values ('ZTEVT-T3', 'ZTEVT Distrito Tres', 'distribucion', v_pl, 9993) returning id into v_t3;
  insert into tecnica.puntos (codigo, nombre, tipo) values ('ZTEVT-M1', 'ZTEVT Muestreo', 'muestreo') returning id into v_m1;
  perform pg_temp.activo('S1', 'SEC', pg_temp.caja(0, -50, 300, 250), 'sector', '{"modelo": {"sector": 71}}');
  perform pg_temp.activo('S2', 'SEC', pg_temp.caja(300, -50, 600, 250), 'sector', '{"modelo": {"sector": 72}}');
  perform pg_temp.activo('S3', 'SEC', pg_temp.caja(600, -50, 900, 250), 'sector', '{"modelo": {"sector": 73}}');
  perform pg_temp.activo('T1', 'RED', ST_MakeLine(pg_temp.pt(50, 0), pg_temp.pt(250, 0)));
  insert into redes.contrato_tramo (contrato, activo_id, distancia_m, metodo) values (ct, pg_temp.id('T1'), 3, 'cercania');
  -- daños e intervención de prueba FUERA de las zonas (no se asocian solos)
  v_txt := (select coalesce(max(substr(d.codigo, 5)::integer), 0) from redes.danos d);
  v_dan := 'DAN-' || lpad((v_txt::integer + 1)::text, 6, '0');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, causa_codigo, descripcion, autor)
  values (gen_random_uuid(), v_dan, 'dano', 'fuga', 'acueducto', pg_temp.id('T1'), pg_temp.lat(100), pg_temp.lon(3000), 'gps', clock_timestamp() - interval '2 hours', 'medio', 'propia', 'desgaste', libre, sd),
         (gen_random_uuid(), 'DAN-' || lpad((v_txt::integer + 2)::text, 6, '0'), 'falla', 'electrica', 'acueducto', pg_temp.id('T1'), pg_temp.lat(100), pg_temp.lon(3100), 'gps', clock_timestamp() - interval '2 hours', 'alto', 'desconocida', null, libre, sd);
  v_itv := 'ITV-' || lpad(((select coalesce(max(substr(i.codigo, 5)::integer), 0) from redes.intervenciones i) + 1)::text, 6, '0');
  insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_inicio, t_fin, descripcion, ejecutor, autor)
  select gen_random_uuid(), v_itv, 'dano', d.id, 'reparacion', 'acueducto', pg_temp.id('T1'), pg_temp.lat(100), pg_temp.lon(3100), 'gps', clock_timestamp() - interval '90 minutes', clock_timestamp() - interval '80 minutes', libre, 'emdupar', sd
    from redes.danos d where d.codigo = 'DAN-' || lpad((v_txt::integer + 2)::text, 6, '0');

  -- ---------- 01. Origen obligatorio ----------
  perform pg_temp.err('01.01 ni registro ni causal: «Indique el origen…»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZTEVT observación de prueba')), null, 'Indique el origen: el daño o la intervención, o la causal del trabajo.');
  perform pg_temp.err('01.02 los dos a la vez: «Elija un solo origen…»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZTEVT observación de prueba', 'registro', v_dan, 'causal', 'otra')), null, 'Elija un solo origen: el daño o la intervención, o la causal.');
  perform pg_temp.err('01.03 una causal que no existe: «Esa causal no existe o está desactivada.»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZTEVT observación de prueba', 'causal', 'zt_no_existe')), null, 'Esa causal no existe o está desactivada.');
  perform pg_temp.err('01.04 «Otra» sin observación: «Escriba la observación…»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ab', 'causal', 'otra')), null, 'Escriba la observación (de 5 a 200 letras)');
  perform pg_temp.err('01.05 una clave que no corresponde sigue siendo error', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1')), 'causa', 'ZTEVT observación de prueba', 'causal', 'otra', 'origen', 'x')), null, 'no corresponde');
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S3')), 'causa', libre, 'causal', 'otra', 'desde', v_desde));
  e_otra := j ->> 'codigo';
  perform pg_temp.reg('01.06 declarado como trabajo con «Otra» y su observación: origen Trabajo, causal {otra, Otra}, sin tubos; queda la causal del evento',
    j -> 'origen' = '{"codigo": "trabajo", "nombre": "Trabajo"}' and j -> 'causal' = '{"codigo": "otra", "nombre": "Otra"}' and j -> 'tubos' = '[]' and j ->> 'causa' = libre
    and exists (select 1 from redes.evento_causal c join redes.eventos_suspension e on e.id = c.evento_id where e.codigo = e_otra and c.causal = 'otra'), j::text);
  perform public.geoportal_redes_evento_anular(sd, e_otra, 'ZTEVT se anula para seguir la prueba');
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S3')), 'causa', 'ZTEVT por el daño', 'registro', v_dan));
  e_dan := j ->> 'codigo';
  perform pg_temp.reg('01.07 declarado por un daño: origen Daño, sin causal', j -> 'origen' ->> 'codigo' = 'dano' and j -> 'origen' ->> 'nombre' = 'Daño' and j -> 'causal' = 'null', j::text);
  perform public.geoportal_redes_evento_anular(sd, e_dan, 'ZTEVT se anula para seguir la prueba');
  -- dos eventos «como antes» (sin causal): uno sin nada y otro con una intervención
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, zona_nombre, causa, desde, contratos, sensibles, autor)
  values ('EVS-991001', 'sectores', false, pg_temp.caja(2000, 0, 2100, 100), array[pg_temp.id('S1')], 'ZTEVT zona vieja', 'ZTEVT evento de antes del cambio', clock_timestamp() - interval '3 hours', 0, 0, sd) returning id into v_viejo;
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, zona_nombre, causa, intervencion_id, desde, contratos, sensibles, autor)
  select 'EVS-991002', 'sectores', false, pg_temp.caja(2200, 0, 2300, 100), array[pg_temp.id('S1')], 'ZTEVT zona vieja 2', 'ZTEVT evento de antes con intervención', i.id, clock_timestamp() - interval '3 hours', 0, 0, sd
    from redes.intervenciones i where i.codigo = v_itv returning id into v_viejo2;
  perform pg_temp.reg('01.08 un evento de antes, sin daño, intervención ni causal: «No registrado (anterior al cambio)»',
    redes.f_evento_json(v_viejo) -> 'origen' = '{"codigo": "no_registrado", "nombre": "No registrado (anterior al cambio)"}' and redes.f_evento_json(v_viejo) -> 'causal' = 'null', (redes.f_evento_json(v_viejo) -> 'origen')::text);
  perform pg_temp.reg('01.09 un evento de antes con intervención sale con su origen real: Intervención', redes.f_evento_json(v_viejo2) -> 'origen' ->> 'nombre' = 'Intervención');

  -- ---------- 02. Causales (catálogo ajustable con historial) ----------
  j := public.geoportal_redes_evento_causal_fijar(adm, null, 'ZTEVT Causal de prueba', true, 'ZTEVT se crea una causal de prueba');
  perform pg_temp.reg('02.01 crear una causal: código armado del nombre, activa, con su hecho «crear»',
    j ->> 'codigo' = 'ztevt_causal_de_prueba' and (j ->> 'activa')::boolean and exists (select 1 from redes.evento_causal_eventos where codigo = 'ztevt_causal_de_prueba' and accion = 'crear' and autor = adm), j::text);
  perform pg_temp.err('02.02 sin motivo: 400', format('select public.geoportal_redes_evento_causal_fijar(%L, null, %L, true, %L)', adm, 'ZTEVT Otra más', 'corto'), null, 'motivo');
  perform pg_temp.err('02.03 un nombre repetido: 400', format('select public.geoportal_redes_evento_causal_fijar(%L, null, %L, true, %L)', adm, 'ztevt causal de prueba', 'ZTEVT nombre repetido a propósito'), null, 'Ya hay una causal');
  j := public.geoportal_redes_evento_causal_fijar(sd, 'ztevt_causal_de_prueba', 'ZTEVT Causal renombrada', false, 'ZTEVT se renombra y se desactiva');
  perform pg_temp.reg('02.04 el supervisor de distribución la renombra y la desactiva; queda el hecho «cambiar»; el catálogo la trae inactiva',
    j ->> 'nombre' = 'ZTEVT Causal renombrada' and not (j ->> 'activa')::boolean and (select count(*) from redes.evento_causal_eventos where codigo = 'ztevt_causal_de_prueba') = 2
    and (select (x ->> 'activa')::boolean = false from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sd) -> 'causales') x where x ->> 'codigo' = 'ztevt_causal_de_prueba'), j::text);
  perform pg_temp.err('02.05 con la causal desactivada no se declara', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S3')), 'causa', 'ZTEVT observación de prueba', 'causal', 'ztevt_causal_de_prueba')), null, 'Esa causal no existe o está desactivada.');
  perform pg_temp.err('02.06 el operador no ajusta causales (403)', format('select public.geoportal_redes_evento_causal_fijar(%L, null, %L, true, %L)', op, 'ZTEVT del operador', 'ZTEVT no debería poder'), '42501');
  perform pg_temp.reg('02.07 el catálogo trae las 5 causales de David activas', (select count(*) from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sd) -> 'causales') x
     where x ->> 'codigo' in ('trabajo_programado', 'parametros_entrada', 'falla_planta', 'mantenimiento_planta', 'otra') and (x ->> 'activa')::boolean) = 5);

  -- ---------- 03. Tubos de salida → sectores, y el evento «por tubo» ----------
  j := public.geoportal_redes_tubo_sectores_fijar(sd, 'ztevt-t1', array[pg_temp.cod('S1'), pg_temp.cod('S2')], 'ZTEVT el tubo uno abastece los sectores uno y dos');
  perform public.geoportal_redes_tubo_sectores_fijar(adm, 'ZTEVT-T2', array[pg_temp.cod('S2'), pg_temp.cod('S3')], 'ZTEVT el tubo dos abastece los sectores dos y tres');
  f := (select x from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sd) -> 'tubos') x where x ->> 'codigo' = 'ZTEVT-T1');
  perform pg_temp.reg('03.01 fijar un tubo (el código en minúsculas vale): su lista, el hecho con motivo; el catálogo trae el tubo con nombre, planta y sectores',
    j ->> 'tubo' = 'ZTEVT-T1' and j ->> 'nombre' = 'ZTEVT Distrito Uno' and jsonb_array_length(j -> 'sectores') = 2 and (select count(*) from redes.tubo_sector_eventos where punto_id = v_t1) = 1
    and f ->> 'nombre' = 'ZTEVT Distrito Uno' and f ->> 'planta' = 'ZTEVT Planta' and (f ->> 'activo')::boolean and f -> 'sectores' = jsonb_build_array(pg_temp.cod('S1'), pg_temp.cod('S2'))
    and pg_temp.claves(f) = 'activo,codigo,nombre,planta,sectores', f::text);
  perform pg_temp.reg('03.02 el tubo sin sectores también sale en el catálogo, con la lista vacía',
    (select x -> 'sectores' from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sd) -> 'tubos') x where x ->> 'codigo' = 'ZTEVT-T3') = '[]');
  perform pg_temp.err('03.03 «Por tubo» con un tubo sin sectores: «Ese tubo no tiene sectores asignados (ZTEVT-T3).»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T1', 'ZTEVT-T3'), 'causa', 'ZTEVT observación de prueba', 'causal', 'trabajo_programado')), null, 'Ese tubo no tiene sectores asignados (ZTEVT-T3).');
  perform pg_temp.err('03.04 un tubo que no existe: «Ese tubo de salida no existe o está inactivo.»', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T9'), 'causa', 'ZTEVT observación de prueba', 'causal', 'trabajo_programado')), null, 'Ese tubo de salida no existe o está inactivo.');
  perform pg_temp.err('03.05 un punto de muestreo no es un tubo (al declarar)', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-M1'), 'causa', 'ZTEVT observación de prueba', 'causal', 'trabajo_programado')), null, 'Ese tubo de salida no existe o está inactivo.');
  perform pg_temp.err('03.06 ni al fijar sus sectores', format('select public.geoportal_redes_tubo_sectores_fijar(%L, %L, %L, %L)', sd, 'ZTEVT-M1', array[pg_temp.cod('S1')], 'ZTEVT un punto de muestreo no es un tubo'), null, 'Ese tubo de salida no existe o está inactivo.');
  perform pg_temp.err('03.07 ni escribiendo directo en la tabla (lo cuida el disparador)', format('insert into redes.tubo_sectores (punto_id, sector_id) values (%s, %s)', v_m1, pg_temp.id('S1')), '23514', 'no es un tubo de salida');
  perform pg_temp.err('03.08 el operador no fija tubos (403)', format('select public.geoportal_redes_tubo_sectores_fijar(%L, %L, %L, %L)', op, 'ZTEVT-T1', array[pg_temp.cod('S1')], 'ZTEVT no debería poder'), '42501');
  j := public.geoportal_redes_evento_vista_previa(sd, jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T1', 'ZTEVT-T2')));
  j2 := public.geoportal_redes_evento_vista_previa(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1'), pg_temp.cod('S2'), pg_temp.cod('S3'))));
  perform pg_temp.reg('03.09 la vista previa por los dos tubos = la de sus 3 sectores (zona, contratos, sensibles y reportes); sin guardar nada',
    j ->> 'alcance' = 'sectores' and j -> 'zona_geojson' = j2 -> 'zona_geojson' and j -> 'contratos' = j2 -> 'contratos' and j -> 'sensibles' = j2 -> 'sensibles' and j -> 'reportes' = j2 -> 'reportes'
    and not exists (select 1 from redes.evento_tubos t where t.punto_id in (v_t1, v_t2)), j::text);
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T2', 'ztevt-t1'), 'causa', libre, 'causal', 'trabajo_programado', 'desde', v_desde));
  e_tubo := j ->> 'codigo';
  perform pg_temp.reg('03.10 declarado por dos tubos: queda POR SECTORES con la unión (3 sectores), guarda los dos tubos; zona «lo que sale por los tubos …»; origen Trabajo',
    j ->> 'alcance' = 'sectores' and jsonb_array_length(j -> 'sectores') = 3 and j -> 'tubos' = '[{"codigo": "ZTEVT-T1", "nombre": "ZTEVT Distrito Uno"}, {"codigo": "ZTEVT-T2", "nombre": "ZTEVT Distrito Dos"}]'
    and j ->> 'zona' = 'lo que sale por los tubos ZTEVT-T1, ZTEVT-T2' and j -> 'causal' ->> 'nombre' = 'Trabajo programado en redes' and j -> 'origen' ->> 'codigo' = 'trabajo'
    and (select count(*) from redes.evento_tubos t join redes.eventos_suspension e on e.id = t.evento_id where e.codigo = e_tubo) = 2, j::text);
  perform pg_temp.reg('03.11 el detalle (evento) trae los mismos origen, causal y tubos',
    public.geoportal_redes_evento(sd, e_tubo) -> 'tubos' = j -> 'tubos' and public.geoportal_redes_evento(sd, e_tubo) -> 'causal' = j -> 'causal'
    and public.geoportal_redes_evento(sd, e_tubo) -> 'origen' = j -> 'origen', (public.geoportal_redes_evento(sd, e_tubo))::text);

  -- ---------- 04. Lo que NO cambia: evento_contrato, la asociación automática, el bot ----------
  -- el contrato de prueba (tramo en el sector 1) frente al evento por tubo y frente al mismo evento declarado por sus sectores
  r_tubo := public.geoportal_redes_evento_contrato(adm, ct);
  perform public.geoportal_redes_evento_anular(sd, e_tubo, 'ZTEVT se anula para comparar con el mismo por sectores');
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S1'), pg_temp.cod('S2'), pg_temp.cod('S3')), 'causa', libre,
                                                                     'causal', 'trabajo_programado', 'desde', v_desde));
  e_sec := j ->> 'codigo';
  r_sec := public.geoportal_redes_evento_contrato(adm, ct);
  perform pg_temp.reg('04.01 evento_contrato: el evento por tubo y el mismo por sectores dan la misma respuesta (salvo el código y el nombre de la zona): en_evento, tipo, zona «sectores», desde',
    r_tubo -> 'evento' ->> 'codigo' = e_tubo and r_sec -> 'evento' ->> 'codigo' = e_sec and (r_tubo ->> 'en_evento')::boolean and r_tubo -> 'evento' ->> 'zona' = 'sectores'
    and pg_temp.contrato_sin_codigo(r_tubo) = pg_temp.contrato_sin_codigo(r_sec), r_tubo::text || ' / ' || r_sec::text);
  perform public.geoportal_redes_evento_anular(sd, e_sec, 'ZTEVT se anula para volver al evento por tubo');
  j := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T1'), 'causa', 'ZTEVT por el tubo uno', 'causal', 'trabajo_programado'));
  e_tubo := j ->> 'codigo';
  j2 := redes.f_reporte_externo_recibir_evento(jsonb_build_object('radicado', 'ZTEVT-B1', 'canal', 'telegram', 'tipo', 'sin_agua', 'lat', pg_temp.lat(100), 'lon', pg_temp.lon(150), 'descripcion', libre));
  perform pg_temp.reg('04.02 un reporte del bot dentro de la zona del tubo se asocia solo al evento por tubo y el bot responde como siempre',
    j2 ->> 'evento' = e_tubo and j2 ->> 'mensaje' like 'Ya sabemos del corte en tu sector.%', j2::text);
  perform pg_temp.reg('04.03 las funciones que no se tocan siguen con su md5 (evento_contrato, aviso, SCRR, disparadores, bot y demás rutas de eventos)',
    (select count(*) from (values ('geoportal_redes_evento_anular(text,text,text)', '8947de32c9f76c9bfc937a31e8bf2c39'), ('geoportal_redes_evento_asociar(text,text,text,text,text)', 'd97df5946041079714a86de12e1d1902'), ('geoportal_redes_evento_cerrar(text,text,text,text)', '1ae6ea7e5c0c5f71b5d41f752775f343'), ('geoportal_redes_evento_contrato(text,text)', 'f82b45906c62feca8b431020284e8bbf'), ('geoportal_redes_evento_desasociar(text,text,text,text,text)', 'cf6f1f7a378e8ab653be26aa9a78a4ee'), ('geoportal_redes_evento_regreso(text,text,text,text)', 'daa542d7d0b0f8cbb09c4f4429fbfd6a'), ('geoportal_redes_evento_tipo_fijar(text,text,text,boolean,text,text,text)', '72a0f1537529089418bd981a30f2fdca'), ('geoportal_redes_evento_vista_previa(text,jsonb)', 'cb22112ec60088390648e3394f1376d7'), ('geoportal_redes_evento(text,text)', 'e1c60d1fdc53332d64db9360ed164461'), ('geoportal_redes_eventos_vigentes(text)', '30d3b3306038af969a1e7e1b75e6f5ef'), ('geoportal_redes_eventos(text,text,integer)', '5b6e1f23c3985e69cfe4908dc3752b8a'), ('geoportal_redes_reporte_iniciar(text,text,jsonb,text,boolean,text)', '05ee00808781f3af88db3d3a57c68f22'), ('geoportal_redes_reporte_pagina(text,bigint,text,integer)', '5e55735ae8f7ad024627f1393aedefdd'), ('geoportal_redes_reporte_sectores(text)', 'b4c7e051d0f41881fc24550a7297f538'), ('redes.f_evento_abierto(text,text,text)', '59df33f21167b73cbc9a5049b505859e'), ('redes.f_evento_autorizar(text,text)', '1c1dc3406cf363dbe6c7a6de06e12954'), ('redes.f_evento_candidatos(geometry,boolean,timestamp with time zone,uuid)', 'dc09e88af2c5c2daa62f2c53fa8ee842'), ('redes.f_evento_contratos(geometry,boolean,boolean)', '8dafa57412c9b41aca0a0e3652f3bf2a'), ('redes.f_evento_franja(text,timestamp with time zone,text,timestamp with time zone)', 'fb9de8c4ada4a35de44889aea9f17b62'), ('redes.f_evento_marcar(bigint[],text,text,text)', 'f067be6b5b0344e0d9c044f8ade679de'), ('redes.f_evento_reportes(bigint)', 'e9d6c5b2d72868e188e2bc5eeda47ddd'), ('redes.f_evento_tg_bot()', '857c47e052a5204c1c437c07d4cd77d1'), ('redes.f_evento_tg_campo()', '8a755c25a340e331b233ccadf99bb099'), ('redes.f_evento_tg_dano()', '430048038207e8bcfeedbf537e75faf8'), ('redes.f_evento_tg_l116()', 'a3959ab3a96e37539fd6507cddc3e075'), ('redes.f_eventos_abiertos()', '2d265a26461ea19a01e9a81bb927b120'), ('redes.f_eventos_para_avisos(timestamp with time zone)', '755cc3b1a15fbd9c82fd34991a97216a'), ('redes.f_reporte_externo_recibir_evento(jsonb)', '92be46589b80d60ce38139e3fe44550d'), ('redes.f_sector_de(geometry)', '455378c9b8cf43343ff821a2896eae37'), ('redes.f_sin_agua_para_avisos(timestamp with time zone,numeric)', '6a370c60ddcc409b06104f599110915a'), ('tecnica.f_avisos(boolean,boolean,timestamp with time zone)', 'aaa81ee57ec79080b9e76213ecea006c')) c(fn, m) where md5(pg_get_functiondef(to_regprocedure(c.fn))) = c.m) = 31);
  -- re-fijar el tubo 1 solo con el sector 1: el 2 queda inactivo (no se borra) y hay un segundo hecho
  perform public.geoportal_redes_tubo_sectores_fijar(sd, 'ZTEVT-T1', array[pg_temp.cod('S1')], 'ZTEVT el tubo uno ya no abastece el sector dos');
  perform pg_temp.reg('04.04 cambiar los sectores de un tubo desactiva el que sale (no se borra) y deja su hecho; el evento ya declarado no cambia',
    (select activo from redes.tubo_sectores where punto_id = v_t1 and sector_id = pg_temp.id('S2')) = false and (select count(*) from redes.tubo_sector_eventos where punto_id = v_t1) = 2
    and (select cardinality(sectores) from redes.eventos_suspension where codigo = e_tubo) = 2);

  -- ---------- 05. Planta: el sistema es único ----------
  perform pg_temp.err('05.01 los sectores ya no se asignan por planta (400)', format('select public.geoportal_redes_planta_sectores_fijar(%L, %L, %L, %L)', sd, 'zt_evt_pl', array[pg_temp.cod('S1')], 'ZTEVT ya no se puede por planta'),
    null, 'Los sectores ya no se asignan por planta: el sistema es único. Asígnelos a los tubos de salida.');
  perform pg_temp.err('05.02 y el operador sigue recibiendo 403', format('select public.geoportal_redes_planta_sectores_fijar(%L, %L, %L, %L)', op, 'zt_evt_pl', array[pg_temp.cod('S1')], 'ZTEVT ya no se puede por planta'), '42501');
  perform pg_temp.reg('05.03 la migración dejó inactivos todos los sectores por planta, con UN hecho por cada planta que tenía (nada se borró)',
    not exists (select 1 from redes.planta_sectores where activo)
    and not exists (select ps.planta_id from redes.planta_sectores ps group by ps.planta_id
                    having (select count(*) from redes.planta_sector_eventos e where e.planta_id = ps.planta_id and e.motivo = 'el sistema es único; los sectores pasan a los tubos de salida') <> 1));
  perform pg_temp.reg('05.04 el catálogo deja vacíos los sectores de cada planta', not exists (select 1 from jsonb_array_elements(public.geoportal_redes_evento_catalogo(sd) -> 'plantas') x where x -> 'sectores' <> '[]'));
  -- un evento de planta nuevo cubre toda la ciudad (si en la base ya hay uno de toda la ciudad abierto, la regla «uno por zona» lo impide: se comprueba eso)
  v_hay_todo := exists (select 1 from redes.f_eventos_abiertos() e where e.todo);
  if v_hay_todo then
    perform pg_temp.err('05.05 (hay un evento de toda la ciudad abierto en la base) uno de planta choca con él: «Ya hay un evento abierto para esa misma zona»', format('select public.geoportal_redes_evento_declarar(%L, %L)', adm,
      jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'zt_evt_pl', 'causa', 'ZTEVT falla de la planta', 'causal', 'falla_planta')), '55000', 'misma zona');
  else
    j := public.geoportal_redes_evento_declarar(adm, jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'zt_evt_pl', 'causa', 'ZTEVT falla de la planta', 'causal', 'falla_planta'));
    e_pl := j ->> 'codigo';
    perform pg_temp.reg('05.05 un evento de planta nuevo cubre TODA LA CIUDAD y guarda la planta: zona «Toda la ciudad (planta ZTEVT Planta)», total «planta», sin zona dibujada',
      j ->> 'alcance' = 'total' and j ->> 'total' = 'planta' and j ->> 'planta' = 'ZTEVT Planta' and j ->> 'zona' = 'Toda la ciudad (planta ZTEVT Planta)' and j -> 'zona_geojson' = 'null'
      and (select todo and geom is null and planta_id = v_pl from redes.eventos_suspension where codigo = e_pl), j::text);
    perform pg_temp.reg('05.06 con el evento de planta, el contrato de prueba también está dentro (toda la ciudad)',
      exists (select 1 from redes.f_eventos_del_contrato(ct) x join redes.eventos_suspension e on e.id = x.evento_id where e.codigo = e_pl));
  end if;
  perform pg_temp.err('05.07 el supervisor de distribución no declara un evento de planta (es total: 403)', format('select public.geoportal_redes_evento_declarar(%L, %L)', sd,
    jsonb_build_object('alcance', 'total', 'total', 'planta', 'planta', 'zt_evt_pl', 'causa', 'ZTEVT falla de la planta', 'causal', 'falla_planta')), '42501');

  -- ---------- 06. Las descargas de eventos (solo filas de prueba) ----------
  j := pg_temp.bajar('redes', sd, 'eventos', per);
  f := pg_temp.fila(j -> 'filas', 'evento', e_tubo);
  perform pg_temp.reg('06.01 Distribución · Eventos: el de tubo dice «Por tubo», su tubo, origen Trabajo y la causal; las columnas = claves de la fila',
    f ->> 'alcance' = 'Por tubo' and f ->> 'tubos' = 'ZTEVT-T1' and f ->> 'origen' = 'Trabajo' and f ->> 'causal' = 'Trabajo programado en redes'
    and pg_temp.claves(f) = (select string_agg(x ->> 'clave', ',' order by x ->> 'clave') from jsonb_array_elements(j -> 'ini' -> 'columnas') x), f::text);
  perform pg_temp.reg('06.02 el evento de antes sale «No registrado (anterior al cambio)» y sin causal; el de antes con intervención, «Intervención»; el de «Otra», su causal',
    pg_temp.fila(j -> 'filas', 'evento', 'EVS-991001') ->> 'origen' = 'No registrado (anterior al cambio)' and pg_temp.fila(j -> 'filas', 'evento', 'EVS-991001') -> 'causal' = 'null'
    and pg_temp.fila(j -> 'filas', 'evento', 'EVS-991002') ->> 'origen' = 'Intervención' and pg_temp.fila(j -> 'filas', 'evento', e_otra) ->> 'causal' = 'Otra');
  perform pg_temp.reg('06.03 la observación (texto libre) no sale en la descarga; el Léame lo dice', position('Pedro' in (j)::text) = 0 and (j -> 'ini' -> 'leame' -> 'que_no_trae')::text like '%observación escrita%');
  if not v_hay_todo then
    j := pg_temp.bajar('tec', sp, 'eventos_planta', per || '{"planta": "zt_evt_pl"}');
    f := pg_temp.fila(j -> 'filas', 'evento', e_pl);
    perform pg_temp.reg('06.04 PTAP · Eventos de planta: el de la planta de prueba, origen Trabajo, causal «Falla en la planta»; el Léame dice que cubre toda la ciudad',
      jsonb_array_length(j -> 'filas') = 1 and f ->> 'origen' = 'Trabajo' and f ->> 'causal' = 'Falla en la planta' and (j -> 'ini' -> 'leame' -> 'que_trae')::text like '%toda la ciudad%'
      and pg_temp.claves(f) = (select string_agg(x ->> 'clave', ',' order by x ->> 'clave') from jsonb_array_elements(j -> 'ini' -> 'columnas') x), f::text);
  else
    perform pg_temp.reg('06.04 PTAP · Eventos de planta: las columnas origen y causal están (no se declaró el de planta: hay uno de toda la ciudad abierto)',
      (select count(*) from jsonb_array_elements(tecnica.f_rep_columnas('eventos_planta', '{}')) x where x ->> 'clave' in ('origen', 'causal')) = 2);
  end if;

  -- ---------- 07. Seguridad del esquema ----------
  perform pg_temp.reg('07.01 las 2 RPC nuevas: security definer, search_path fijo, solo service_role',
    (select count(*) from pg_proc p where p.oid in ('public.geoportal_redes_evento_causal_fijar(text,text,text,boolean,text)'::regprocedure, 'public.geoportal_redes_tubo_sectores_fijar(text,text,text[],text)'::regprocedure)
       and p.prosecdef and p.proconfig is not null and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
       and not has_function_privilege('authenticated', p.oid, 'execute') and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 2);
  perform pg_temp.reg('07.02 las internas nuevas: nadie más que su dueño',
    not exists (select 1 from pg_proc p where p.oid in ('redes.f_evento_origen(bigint)'::regprocedure, 'redes.f_tubo_zona(text[])'::regprocedure, 'redes.f_tubo_es_distribucion()'::regprocedure)
                  and exists (select 1 from aclexplode(p.proacl) x where x.grantee <> p.proowner)));
  perform pg_temp.reg('07.03 las 6 tablas nuevas: RLS y sin permisos para la API',
    (select count(*) from pg_class c where c.oid in ('redes.evento_causales'::regclass, 'redes.evento_causal_eventos'::regclass, 'redes.evento_causal'::regclass, 'redes.tubo_sectores'::regclass,
       'redes.tubo_sector_eventos'::regclass, 'redes.evento_tubos'::regclass) and c.relrowsecurity and not has_table_privilege('anon', c.oid, 'select')
       and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')) = 6);
  perform pg_temp.err('07.04 de qué tubos salió un evento es de solo inserción', format('delete from redes.evento_tubos where punto_id = %s', v_t1));
  perform pg_temp.err('07.05 la causal de un evento tampoco se cambia', format('update redes.evento_causal set causal = %L where causal = %L', 'otra', 'trabajo_programado'));
  perform pg_temp.reg('07.06 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  -- ---------- 08. Tiempos con el volumen real ----------
  v_t0 := clock_timestamp(); j := public.geoportal_redes_evento_catalogo(sd); v_ms1 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_t0 := clock_timestamp(); j2 := public.geoportal_redes_evento_vista_previa(sd, jsonb_build_object('alcance', 'tubos', 'tubos', jsonb_build_array('ZTEVT-T2'))); v_ms2 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_info := format('TIEMPOS: catálogo de eventos %s ms (%s tubos, %s sectores) · vista previa por tubo %s ms (tope de la API: 30 s por llamada)',
                   round(v_ms1), jsonb_array_length(j -> 'tubos'), jsonb_array_length(j -> 'sectores'), round(v_ms2));
  perform pg_temp.reg('08.01 TIEMPOS: el catálogo y la vista previa por tubo, cada uno en menos de 5 s', v_ms1 < 5000 and v_ms2 < 5000, v_info);

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · eventos (origen y tubos) (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
