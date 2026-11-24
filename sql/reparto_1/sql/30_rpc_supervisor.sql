-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 30 — RPC del supervisor: archivos de ruta, avance, detalle y mapa
-- Quién: el supervisor de campo (dashboard_campo) o el administrador (reparto.f_autorizar_supervisor → campo.f_autorizar_supervision).
-- Las filas de los archivos nunca se escriben en la auditoría (solo nombre, huella, tipo, ciclo, ruta y conteos).
-- =====================================================================

-- Cargar un archivo de una ruta o de un ciclo (plantilla: Contrato y, opcional, Orden). «Todo comienza con el archivo de rutas» (David, 24-nov):
--  · EL CICLO NO LO ESCRIBE EL SUPERVISOR: se deduce de los contratos según bi.v_rutas_geoportal (último período); si un contrato no está ahí, según
--    public.cartera_suscripcion (su fila más reciente); si discrepan, manda la tabla de rutas. La comparación es numérica («098» = «98»);
--  · si los contratos con ciclo conocido son de MÁS DE UN ciclo, se rechaza sin escribir nada, con el detalle por ciclo («98: 30 · 15: 10»);
--  · los contratos sin registro (ni en rutas ni en cartera) se aceptan con aviso, como antes, y NO cuentan para decidir el ciclo; si TODOS son sin registro,
--    el supervisor escoge el ciclo a mano (p_ciclo; si no viene, se le pide: «pide_ciclo»). Si el ciclo se deduce, p_ciclo se ignora;
--  · la ruta la escribe el supervisor, como rótulo, sin validarla contra los contratos;
--  · p_confirmar = false es la VISTA PREVIA: valida, deduce y devuelve el ciclo y los conteos sin escribir nada (la pantalla lo muestra antes de confirmar);
--  · forma: de 1 a tope_filas_lote filas; contrato solo dígitos (1 a 12) y sin repetir; Orden en todas las filas o en ninguna, entero ≥ 1 y sin repetir;
--    si hay errores no escribe nada y devuelve hasta 20, con su fila de Excel (la 1 es el encabezado);
--  · el mismo archivo (huella), de la misma persona, con el mismo tipo, ciclo y ruta, el mismo día y sin anular, devuelve el mismo lote (doble clic).
create function public.geoportal_reparto_lote_cargar(p_solicitante text, p_nombre text, p_sha256 text, p_tipo text, p_ciclo text, p_ruta text,
                                                     p_filas jsonb, p_confirmar boolean default true, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_tope integer := (reparto.f_param('tope_filas_lote'))::integer; v_n integer;
        v_err jsonb; v_id uuid; v_ciclo text; v_ruta text := nullif(btrim(coalesce(p_ruta, '')), ''); v_con_orden integer;
        v_sin integer; v_por_ciclo jsonb; v_ciclos integer; v_texto text; v_deducido boolean;
begin
  if p_tipo is null or p_tipo not in ('ruta', 'ciclo') then perform reparto.f_err('Indique si el archivo es de una ruta o de un ciclo'); end if;
  if p_tipo = 'ruta' and (v_ruta is null or v_ruta !~ '^[A-Za-z0-9 _.-]{1,20}$') then perform reparto.f_err('Indique la ruta (hasta 20 letras o números)'); end if;
  if p_tipo = 'ciclo' then v_ruta := null; end if;
  if length(btrim(coalesce(p_nombre, ''))) not between 1 and 200 then perform reparto.f_err('Nombre de archivo no válido'); end if;
  if coalesce(p_sha256, '') !~ '^[0-9a-f]{64}$' then perform reparto.f_err('Huella del archivo no válida'); end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then perform reparto.f_err('El archivo no trae filas'); end if;
  v_n := jsonb_array_length(p_filas);
  if v_n < 1 or v_n > v_tope then perform reparto.f_err(format('El archivo debe tener entre 1 y %s filas (trae %s)', v_tope, v_n)); end if;
  -- 1. la forma
  with f as (select x.o::integer + 1 as fila, x.v from jsonb_array_elements(p_filas) with ordinality x(v, o)),
       c as (select f.fila, f.v ->> 'contrato' as bruto, reparto.f_contrato(f.v ->> 'contrato') as contrato,
                    nullif(btrim(coalesce(f.v ->> 'orden', '')), '') as orden_txt from f),
       e as (select c.fila, 'Fila ' || c.fila || ': el contrato «' || left(coalesce(c.bruto, ''), 20) || '» no es válido (solo números, de 1 a 12)' as m from c where c.contrato is null
             union all
             select c.fila, 'Fila ' || c.fila || ': el contrato ' || c.contrato || ' está repetido' from c
              where c.contrato is not null and exists (select 1 from c c2 where c2.contrato = c.contrato and c2.fila < c.fila)
             union all
             select c.fila, 'Fila ' || c.fila || ': el Orden «' || left(c.orden_txt, 12) || '» no es un entero mayor que cero' from c
              where c.orden_txt is not null and c.orden_txt !~ '^[1-9][0-9]{0,6}$'
             union all
             select c.fila, 'Fila ' || c.fila || ': el Orden ' || c.orden_txt || ' está repetido' from c
              where c.orden_txt ~ '^[1-9][0-9]{0,6}$' and exists (select 1 from c c2 where c2.orden_txt = c.orden_txt and c2.fila < c.fila))
  select (select count(*) from c where c.orden_txt is not null), (select jsonb_agg(m order by fila) from (select * from e order by fila limit 20) z)
    into v_con_orden, v_err;
  if v_con_orden not in (0, v_n) then
    v_err := coalesce(v_err, '[]'::jsonb) || jsonb_build_array('La columna Orden debe venir en todas las filas o en ninguna');
  end if;
  if v_err is not null then return jsonb_build_object('ok', false, 'errores', v_err); end if;
  -- 2. el ciclo de cada contrato: rutas (último período) y, si no está, cartera; manda rutas; comparación numérica
  with f as (select distinct reparto.f_contrato(x.v ->> 'contrato') as contrato from jsonb_array_elements(p_filas) x(v)),
       r as (select distinct on (r.contrato) r.contrato, r.ciclo from bi.v_rutas_geoportal r
              where r.contrato in (select contrato from f) order by r.contrato, reparto.f_num(r.consecutivo_ruta) nulls last),
       s as (select distinct on (s.contrato) s.contrato, s.ciclo from public.cartera_suscripcion s
              where s.contrato in (select contrato from f) and not exists (select 1 from r where r.contrato = s.contrato) order by s.contrato, s.cargado_en desc),
       k as (select case when btrim(coalesce(x.ciclo, '')) ~ '^[0-9]{1,9}$' then (btrim(x.ciclo)::bigint)::text end as ciclo from (select ciclo from r union all select ciclo from s) x),
       g as (select k.ciclo, count(*) as n from k where k.ciclo is not null group by k.ciclo)
  select (select count(*) from f) - (select count(*) from r) - (select count(*) from s), (select count(*) from g),
         (select jsonb_agg(jsonb_build_object('ciclo', g.ciclo, 'contratos', g.n) order by g.n desc, g.ciclo::bigint) from g),
         (select string_agg(g.ciclo || ': ' || g.n, ' · ' order by g.n desc, g.ciclo::bigint) from g),
         (select min(g.ciclo) from g)
    into v_sin, v_ciclos, v_por_ciclo, v_texto, v_ciclo;
  if v_ciclos > 1 then
    return jsonb_build_object('ok', false, 'por_ciclo', v_por_ciclo,
      'errores', jsonb_build_array(format('El archivo tiene contratos de más de un ciclo: %s. Un archivo debe ser de un solo ciclo.', v_texto)));
  end if;
  v_deducido := v_ciclos = 1;
  if not v_deducido then
    v_ciclo := btrim(coalesce(p_ciclo, ''));
    if v_ciclo = '' then
      return jsonb_build_object('ok', false, 'pide_ciclo', true, 'sin_registro', v_sin,
        'errores', jsonb_build_array(format('Ninguno de los %s contratos está en las rutas ni en la cartera: escoja el ciclo a mano.', v_n)));
    end if;
    if v_ciclo !~ '^[0-9]{1,4}$' then perform reparto.f_err('Indique el ciclo (solo números)'); end if;
    v_ciclo := (v_ciclo::integer)::text;
  end if;
  if v_ciclo !~ '^[0-9]{1,4}$' then perform reparto.f_err(format('El ciclo deducido (%s) no es válido', v_ciclo)); end if;
  -- 3. vista previa: sin escribir nada
  if not coalesce(p_confirmar, true) then
    return jsonb_build_object('ok', true, 'previa', true, 'ciclo', v_ciclo, 'ciclo_deducido', v_deducido, 'filas', v_n, 'sin_registro', v_sin, 'por_ciclo', coalesce(v_por_ciclo, '[]'::jsonb));
  end if;
  -- 4. cargar (doble clic = el mismo lote)
  perform pg_advisory_xact_lock(hashtextextended('reparto_lote:' || v_email || ':' || p_sha256, 0));
  select l.id into v_id from reparto.lotes l
   where l.archivo_sha256 = p_sha256 and l.autor = v_email and l.tipo = p_tipo and l.ciclo = v_ciclo and l.ruta is not distinct from v_ruta
     and (l.creado_en at time zone 'America/Bogota')::date = reparto.f_hoy() and not exists (select 1 from reparto.lotes_anulados a where a.lote_id = l.id)
   order by l.creado_en desc limit 1;
  if v_id is not null then
    return jsonb_build_object('ok', true, 'lote_id', v_id, 'repetido', true, 'ciclo', v_ciclo, 'ciclo_deducido', v_deducido, 'filas', (select filas from reparto.lotes where id = v_id),
                              'sin_registro', (select sin_registro from reparto.lotes where id = v_id));
  end if;
  insert into reparto.lotes (nombre_archivo, archivo_sha256, tipo, ciclo, ruta, filas, sin_registro, autor)
    values (btrim(p_nombre), p_sha256, p_tipo, v_ciclo, v_ruta, v_n, v_sin, v_email) returning id into v_id;
  -- el orden: el de la columna Orden (renumerado 1…N) o, si no viene, el de las filas
  insert into reparto.lote_filas (lote_id, orden, contrato)
    select v_id, row_number() over (order by coalesce(nullif(btrim(coalesce(x.v ->> 'orden', '')), '')::integer, x.o::integer), x.o), reparto.f_contrato(x.v ->> 'contrato')
      from jsonb_array_elements(p_filas) with ordinality x(v, o);
  perform reparto.f_auditar(v_email, 'reparto_lote_cargar', v_id::text,
            jsonb_build_object('nombre', btrim(p_nombre), 'sha256', p_sha256, 'tipo', p_tipo, 'ciclo', v_ciclo, 'ciclo_deducido', v_deducido, 'ruta', v_ruta, 'filas', v_n, 'sin_registro', v_sin), p_ip);
  return jsonb_build_object('ok', true, 'lote_id', v_id, 'repetido', false, 'ciclo', v_ciclo, 'ciclo_deducido', v_deducido, 'filas', v_n, 'sin_registro', v_sin);
end $$;

create function public.geoportal_reparto_lote_anular(p_solicitante text, p_lote uuid, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_m text := btrim(coalesce(p_motivo, ''));
begin
  if length(v_m) not between 10 and 300 then perform reparto.f_err('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
  if not exists (select 1 from reparto.lotes l where l.id = p_lote) then perform reparto.f_err('Ese archivo de ruta no existe'); end if;
  perform pg_advisory_xact_lock(hashtextextended('reparto_lote_anular:' || p_lote::text, 0));
  if exists (select 1 from reparto.lotes_anulados a where a.lote_id = p_lote) then perform reparto.f_err('Ese archivo ya estaba anulado', '55000'); end if;
  insert into reparto.lotes_anulados (lote_id, motivo, autor) values (p_lote, v_m, v_email);
  perform reparto.f_auditar(v_email, 'reparto_lote_anular', p_lote::text, jsonb_build_object('motivo', v_m), p_ip);
  return jsonb_build_object('ok', true, 'lote_id', p_lote);
end $$;

-- Archivos cargados (los últimos 60 días), con su estado y cuántas jornadas salieron de cada uno
create function public.geoportal_reparto_lotes(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante);
begin
  return jsonb_build_object('lotes', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'nombre_archivo', l.nombre_archivo, 'tipo', l.tipo, 'ciclo', l.ciclo, 'ruta', l.ruta, 'filas', l.filas, 'autor', l.autor, 'cargado_en', l.creado_en,
      'vigente', a.lote_id is null and l.creado_en >= now() - make_interval(days => (reparto.f_param('lote_vigencia_dias'))::int),
      'anulado', a.lote_id is not null, 'motivo_anulacion', a.motivo, 'anulado_por', a.autor, 'anulado_en', a.creado_en,
      'jornadas', (select count(*) from reparto.jornadas j where j.lote_id = l.id)) order by l.creado_en desc), '[]'::jsonb)
    from reparto.lotes l left join reparto.lotes_anulados a on a.lote_id = l.id where l.creado_en >= now() - interval '60 days'));
end $$;

-- Avance de un día: por repartidor y ruta (una fila por jornada): total, entregadas, pendientes, saltadas, anuladas y la última entrega.
-- Las pendientes descuentan lo que entregó cualquier repartidor en la ventana (dos personas pueden repartir la misma ruta).
create function public.geoportal_reparto_avance(p_solicitante text, p_fecha date default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_fecha date := coalesce(p_fecha, reparto.f_hoy());
begin
  if v_fecha < date '2026-01-01' or v_fecha > reparto.f_hoy() then perform reparto.f_err('Fecha no válida'); end if;
  return jsonb_build_object('fecha', v_fecha, 'filas', (select coalesce(jsonb_agg(jsonb_build_object(
      'jornada_id', v.jornada_id, 'repartidor', v.repartidor, 'nombre', (select b.nombre from public.geoportal_lista_blanca b where b.email = v.repartidor),
      'origen', v.origen, 'periodo', v.periodo, 'ciclo', v.ciclo, 'ruta', v.ruta, 'nombre_archivo', v.nombre_archivo, 'total', v.total,
      'periodo_reparto', v.periodo_reparto, 'reparto_desde', v.reparto_desde, 'respaldo', v.respaldo,
      'entregadas', v.entregadas, 'anuladas', v.anuladas, 'ultima', v.ultima,
      'pendientes', case when v.origen = 'inventada' then null else s.pendientes end,
      'saltadas', case when v.origen = 'inventada' then null else s.saltadas end) order by v.repartidor, v.jornada_id), '[]'::jsonb)
    from reparto.v_avance v
    left join lateral (select count(*) filter (where not x.entregada) as pendientes, count(*) filter (where x.saltado) as saltadas
                         from reparto.f_estado_lista(v.jornada_id) x) s on true
   where v.fecha = v_fecha));
end $$;

-- Detalle de una jornada: el orden real (consecutivo) frente al de lectura, los saltados y las anuladas con su motivo
create function public.geoportal_reparto_detalle(p_solicitante text, p_jornada bigint, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante);
begin
  if not exists (select 1 from reparto.jornadas j where j.id = p_jornada) then perform reparto.f_err('Esa jornada no existe'); end if;
  return jsonb_build_object(
    'jornada', (select to_jsonb(v) - 'lote_id' || jsonb_build_object('nombre', (select b.nombre from public.geoportal_lista_blanca b where b.email = v.repartidor))
                  from reparto.v_avance v where v.jornada_id = p_jornada),
    'entregas', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'contrato', e.contrato, 'consecutivo', e.consecutivo, 'orden_lectura', e.orden_lectura,
                   'periodo_reparto', e.periodo_reparto,
                   'hora', e.registrado_en, 'lon', e.lon, 'lat', e.lat, 'precision_m', e.precision_m, 'por_buscador', e.por_buscador,
                   'anulada', e.anulada, 'motivo_anulacion', e.motivo_anulacion, 'anulada_por', e.anulada_por, 'anulada_en', e.anulada_en) order by e.consecutivo), '[]'::jsonb)
                   from reparto.v_entregas e where e.jornada_id = p_jornada),
    'saltados', (select coalesce(jsonb_agg(jsonb_build_object('contrato', s.contrato, 'orden_lectura', s.orden_lectura) order by s.orden_lectura), '[]'::jsonb)
                   from reparto.f_estado_lista(p_jornada) s where s.saltado),
    'pendientes', (select count(*) from reparto.f_estado_lista(p_jornada) s where not s.entregada));
end $$;

-- Mapa EN VIVO (David, 23-nov): los XY de un día (o de una jornada), numerados por el orden real. La pantalla lo consulta cada pocos segundos:
-- con p_despues (el último id que ya tiene) solo vienen los puntos nuevos, más la lista de ids anulados del día (pocos) para tacharlos.
create function public.geoportal_reparto_mapa(p_solicitante text, p_fecha date default null, p_jornada bigint default null, p_despues bigint default null,
                                              p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_fecha date := coalesce(p_fecha, reparto.f_hoy());
begin
  if v_fecha < date '2026-01-01' or v_fecha > reparto.f_hoy() then perform reparto.f_err('Fecha no válida'); end if;
  if p_despues is not null and p_despues < 0 then perform reparto.f_err('Cursor no válido'); end if;
  return (with j as (select jo.id, jo.repartidor from reparto.jornadas jo where jo.fecha = v_fecha and (p_jornada is null or jo.id = p_jornada)),
               e as (select e.*, j.repartidor from reparto.v_entregas e join j on j.id = e.jornada_id)
    select jsonb_build_object('fecha', v_fecha,
      'puntos', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'jornada_id', e.jornada_id, 'repartidor', e.repartidor, 'contrato', e.contrato, 'consecutivo', e.consecutivo,
                   'hora', e.registrado_en, 'lon', e.lon, 'lat', e.lat, 'precision_m', e.precision_m, 'anulada', e.anulada) order by e.jornada_id, e.consecutivo), '[]'::jsonb)
                   from e where p_despues is null or e.id > p_despues),
      'anuladas', (select coalesce(jsonb_agg(e.id order by e.id), '[]'::jsonb) from e where e.anulada),
      'ultimo_id', (select max(e.id) from e)));
end $$;

-- Calendario de reparto en SOLO LECTURA para el supervisor de reparto (David, 23-nov): lo llena quien tiene dashboard_campo en Cartera → Calendario.
-- Por ciclo: la fecha de reparto del período pedido (o nula: falta) y el período que se reparte hoy. «puede_cambiar» decide si se muestra el enlace.
create function public.geoportal_reparto_calendario(p_solicitante text, p_periodo text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto, scrr as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_per text := coalesce(nullif(btrim(coalesce(p_periodo, '')), ''), to_char(reparto.f_hoy(), 'YYYYMM'));
begin
  if v_per !~ '^20[0-9]{2}(0[1-9]|1[0-2])$' then perform reparto.f_err('Período no válido (aaaamm)'); end if;
  return jsonb_build_object('periodo', v_per, 'hoy', reparto.f_hoy(), 'puede_cambiar', reparto.f_puede_calendario(v_email),
    'ciclos', (select coalesce(jsonb_agg(jsonb_build_object('ciclo', v.ciclo, 'reparto', reparto.f_fecha(v.etapas ->> 'reparto'),
                 'en_reparto_hoy', (select jsonb_build_object('periodo', p.periodo, 'desde', p.desde) from reparto.f_periodo_reparto(v.ciclo::text) p)) order by v.ciclo), '[]'::jsonb)
                 from scrr.v_calendario_vigente v where v.periodo = v_per));
end $$;
