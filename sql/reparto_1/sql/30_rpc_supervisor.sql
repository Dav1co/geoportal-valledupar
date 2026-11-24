-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 30 — RPC del supervisor: archivos de ruta, avance, detalle y mapa
-- Quién: el supervisor de campo (dashboard_campo) o el administrador (reparto.f_autorizar_supervisor → campo.f_autorizar_supervision).
-- Las filas de los archivos nunca se escriben en la auditoría (solo nombre, huella, tipo, ciclo, ruta y conteos).
-- =====================================================================

-- Las filas del archivo de rutas, ya normalizadas (función pura; sin tablas temporales): ciclo como número (sin ceros a la izquierda), ruta recortada,
-- consecutivos numéricos; y los textos tal como llegaron, para los mensajes de error.
create function reparto.f_filas_lote(p_filas jsonb) returns table (fila integer, contrato text, ciclo text, ruta text, cr numeric, cp numeric,
                                                                    bruto_c text, bruto_ci text, bruto_r text, bruto_cr text, bruto_cp text)
language sql immutable set search_path = pg_catalog as $$
  -- validaciones EN LÍNEA (sin llamar a f_num ni f_contrato por fila: con 10.000 filas serían decenas de miles de llamadas)
  select y.fila,
         case when y.c ~ '^[0-9]{1,12}$' then y.c end,
         case when y.ci ~ '^[0-9]{1,4}(\.0+)?$' then ((split_part(y.ci, '.', 1))::integer)::text end,
         case when y.r ~ '^[A-Za-z0-9 _.-]{1,20}$' then y.r end,
         case when y.cr ~ '^[0-9]{1,15}(\.0+)?$' then (split_part(y.cr, '.', 1))::numeric end,
         case when y.cp ~ '^[0-9]{1,15}(\.0+)?$' then (split_part(y.cp, '.', 1))::numeric end,
         y.c0, y.ci0, y.r0, y.cr0, nullif(y.cp, '')
    from (select x.o::integer + 1 as fila, x.v ->> 'contrato' as c0, x.v ->> 'ciclo' as ci0, x.v ->> 'ruta' as r0, x.v ->> 'consecutivo_ruta' as cr0,
                 btrim(coalesce(x.v ->> 'contrato', '')) as c, btrim(coalesce(x.v ->> 'ciclo', '')) as ci, btrim(coalesce(x.v ->> 'ruta', '')) as r,
                 btrim(coalesce(x.v ->> 'consecutivo_ruta', '')) as cr, btrim(coalesce(x.v ->> 'consecutivo_predio', '')) as cp
            from jsonb_array_elements(p_filas) with ordinality x(v, o)) y
$$;

-- Cargar un archivo de rutas (David, 24-nov: LA MISMA estructura del archivo de rutas de facturación que alimenta hechos.rutas_consecutivos).
-- Cada fila llega como {contrato, ciclo, ruta, consecutivo_ruta, consecutivo_predio}: la DIRECCIÓN la valida la pantalla como columna y NO se envía ni se guarda.
--  · ciclo y ruta salen de cada fila; un archivo puede traer varias rutas y varios ciclos: cada (ciclo, ruta) es una opción para el repartidor;
--  · el orden, dentro de cada (ciclo, ruta): CONSECUTIVO_EN_LA_RUTA (numérico) y, en el empate, NÚMERO_CONSECUTIVO_DE_PREDIO; al final el contrato;
--  · si el CICLO de una fila no coincide con bi.v_rutas_geoportal para ese contrato (comparación numérica), se avisa cuántos y cuáles, pero se carga
--    igual: manda el archivo;
--  · contratos repetidos en el archivo: se rechaza con la lista; los que no están ni en rutas ni en cartera se aceptan con aviso;
--  · p_confirmar = false es la VISTA PREVIA: valida y devuelve las rutas y los avisos sin escribir nada;
--  · forma: de 1 a tope_filas_lote filas; si hay errores no escribe nada y devuelve hasta 20, con su fila de Excel (la 1 es el encabezado);
--  · el mismo archivo (huella), de la misma persona, el mismo día y sin anular, devuelve el mismo lote (doble clic).
create function public.geoportal_reparto_lote_cargar(p_solicitante text, p_nombre text, p_sha256 text, p_filas jsonb, p_confirmar boolean default true,
                                                     p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_supervisor(p_solicitante); v_tope integer := (reparto.f_param('tope_filas_lote'))::integer; v_n integer;
        v_err jsonb; v_id uuid; v_sin integer; v_otro integer; v_otro_lista jsonb; v_rutas jsonb; v_nrutas integer;
begin
  if length(btrim(coalesce(p_nombre, ''))) not between 1 and 200 then perform reparto.f_err('Nombre de archivo no válido'); end if;
  if coalesce(p_sha256, '') !~ '^[0-9a-f]{64}$' then perform reparto.f_err('Huella del archivo no válida'); end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then perform reparto.f_err('El archivo no trae filas'); end if;
  v_n := jsonb_array_length(p_filas);
  if v_n < 1 or v_n > v_tope then perform reparto.f_err(format('El archivo debe tener entre 1 y %s filas (trae %s)', v_tope, v_n)); end if;
  -- 1. la forma de cada fila y los contratos repetidos
  with f as materialized (select * from reparto.f_filas_lote(p_filas)),
       e as (select fila, 'Fila ' || fila || ': el contrato «' || left(coalesce(bruto_c, ''), 20) || '» no es válido (solo números, de 1 a 12)' as m from f where contrato is null
             union all select fila, 'Fila ' || fila || ': el CICLO «' || left(coalesce(bruto_ci, ''), 12) || '» no es válido (número de hasta 4 cifras)' from f where ciclo is null
             union all select fila, 'Fila ' || fila || ': la RUTA «' || left(coalesce(bruto_r, ''), 24) || '» no es válida (hasta 20 letras o números)' from f where ruta is null
             union all select fila, 'Fila ' || fila || ': el CONSECUTIVO_EN_LA_RUTA «' || left(coalesce(bruto_cr, ''), 20) || '» no es un número' from f where cr is null
             union all select fila, 'Fila ' || fila || ': el NÚMERO_CONSECUTIVO_DE_PREDIO «' || left(bruto_cp, 20) || '» no es un número' from f where bruto_cp is not null and cp is null)
  select jsonb_agg(m order by fila) into v_err from (select * from e order by fila limit 20) z;
  if v_err is not null then return jsonb_build_object('ok', false, 'errores', v_err); end if;
  select jsonb_agg(format('El contrato %s está repetido (filas %s)', contrato, filas) order by primera) into v_err
    from (select contrato, string_agg(fila::text, ', ' order by fila) as filas, min(fila) as primera from reparto.f_filas_lote(p_filas) group by contrato having count(*) > 1 order by min(fila) limit 20) d;
  if v_err is not null then
    return jsonb_build_object('ok', false, 'errores', jsonb_build_array('El archivo trae contratos repetidos: cada contrato va una sola vez.') || v_err);
  end if;
  -- 2. avisos: CICLO distinto del de las rutas (manda el archivo) y contratos sin registro
  with f as materialized (select * from reparto.f_filas_lote(p_filas)),
       r as (select distinct on (r.contrato) r.contrato, r.ciclo from bi.v_rutas_geoportal r
              where r.contrato in (select contrato from f) order by r.contrato, reparto.f_num(r.consecutivo_ruta) nulls last),
       d as (select f.fila, f.contrato, f.ciclo, (reparto.f_num(r.ciclo)::bigint)::text as ciclo_rutas from f join r on r.contrato = f.contrato
              where reparto.f_num(r.ciclo) is not null and (reparto.f_num(r.ciclo)::bigint)::text <> f.ciclo),
       g as (select ciclo, ruta, count(*) as n from f group by 1, 2)
  select (select count(*) from d),
         (select jsonb_agg(jsonb_build_object('contrato', contrato, 'ciclo_archivo', ciclo, 'ciclo_rutas', ciclo_rutas) order by fila) from (select * from d order by fila limit 20) z),
         (select count(*) from f where not exists (select 1 from r where r.contrato = f.contrato)
             and not exists (select 1 from public.cartera_suscripcion s where s.contrato = f.contrato)),
         (select count(*) from g),
         (select jsonb_agg(jsonb_build_object('ciclo', ciclo, 'ruta', ruta, 'filas', n) order by ciclo::int, reparto.f_num(ruta) nulls last, ruta) from g)
    into v_otro, v_otro_lista, v_sin, v_nrutas, v_rutas;
  -- 3. vista previa: sin escribir nada
  if not coalesce(p_confirmar, true) then
    return jsonb_build_object('ok', true, 'previa', true, 'filas', v_n, 'rutas', v_rutas, 'otro_ciclo', v_otro, 'otro_ciclo_lista', coalesce(v_otro_lista, '[]'::jsonb), 'sin_registro', v_sin);
  end if;
  -- 4. cargar (doble clic = el mismo lote)
  perform pg_advisory_xact_lock(hashtextextended('reparto_lote:' || v_email || ':' || p_sha256, 0));
  select l.id into v_id from reparto.lotes l
   where l.archivo_sha256 = p_sha256 and l.autor = v_email and (l.creado_en at time zone 'America/Bogota')::date = reparto.f_hoy()
     and not exists (select 1 from reparto.lotes_anulados a where a.lote_id = l.id)
   order by l.creado_en desc limit 1;
  if v_id is not null then
    return jsonb_build_object('ok', true, 'lote_id', v_id, 'repetido', true, 'filas', v_n, 'rutas', v_rutas, 'otro_ciclo', v_otro, 'otro_ciclo_lista', coalesce(v_otro_lista, '[]'::jsonb), 'sin_registro', v_sin);
  end if;
  insert into reparto.lotes (nombre_archivo, archivo_sha256, filas, rutas, sin_registro, otro_ciclo, autor)
    values (btrim(p_nombre), p_sha256, v_n, v_nrutas, v_sin, v_otro, v_email) returning id into v_id;
  insert into reparto.lote_filas (lote_id, ciclo, ruta, orden, contrato, consecutivo_ruta, consecutivo_predio)
    select v_id, ciclo, ruta, row_number() over (partition by ciclo, ruta order by cr, cp nulls last, contrato), contrato, cr, cp from reparto.f_filas_lote(p_filas);
  perform reparto.f_auditar(v_email, 'reparto_lote_cargar', v_id::text,
            jsonb_build_object('nombre', btrim(p_nombre), 'sha256', p_sha256, 'filas', v_n, 'rutas', v_nrutas, 'otro_ciclo', v_otro, 'sin_registro', v_sin), p_ip);
  return jsonb_build_object('ok', true, 'lote_id', v_id, 'repetido', false, 'filas', v_n, 'rutas', v_rutas, 'otro_ciclo', v_otro, 'otro_ciclo_lista', coalesce(v_otro_lista, '[]'::jsonb), 'sin_registro', v_sin);
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
      'id', l.id, 'nombre_archivo', l.nombre_archivo, 'filas', l.filas, 'otro_ciclo', l.otro_ciclo, 'sin_registro', l.sin_registro, 'autor', l.autor, 'cargado_en', l.creado_en,
      'rutas', (select jsonb_agg(jsonb_build_object('ciclo', g.ciclo, 'ruta', g.ruta, 'filas', g.n) order by g.ciclo::int, reparto.f_num(g.ruta) nulls last, g.ruta)
                  from (select f.ciclo, f.ruta, count(*) as n from reparto.lote_filas f where f.lote_id = l.id group by 1, 2) g),
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
