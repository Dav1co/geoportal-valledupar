-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 20 — RPC del repartidor (y el contexto común)
-- Todas: SECURITY DEFINER, search_path fijo, solicitante = el correo del token (lo pone la Edge). Solo las ejecuta service_role.
-- Ninguna lleva UPDATE ni DELETE. Lo que lee de rutas: bi.v_rutas_geoportal (último período), nunca la tabla entera de hechos.
-- =====================================================================

-- Lista de la jornada para la pantalla: solo los códigos pendientes en orden de lectura (sin el número de orden), con su marca de saltado
create function reparto.f_lista(p_jornada bigint) returns jsonb
language sql stable security definer set search_path = reparto, public, pg_temp as $$
  select jsonb_build_object(
    'jornada', (select jsonb_build_object('id', j.id, 'fecha', j.fecha, 'origen', j.origen, 'periodo', j.periodo, 'ciclo', j.ciclo, 'ruta', j.ruta,
                                          'lote_id', j.lote_id, 'nombre_archivo', l.nombre_archivo, 'total', j.total)
                  from reparto.jornadas j left join reparto.lotes l on l.id = j.lote_id where j.id = p_jornada),
    'entregadas_mias', (select count(*) from reparto.entregas e where e.jornada_id = p_jornada and not exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = e.id)),
    'siguiente', (select coalesce(max(e.consecutivo), 0) + 1 from reparto.entregas e where e.jornada_id = p_jornada),
    'pendientes', (select coalesce(jsonb_agg(jsonb_build_object('c', s.contrato, 's', s.saltado) order by s.orden_lectura), '[]'::jsonb)
                     from reparto.f_estado_lista(p_jornada) s where not s.entregada),
    'ultimas', (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'contrato', u.contrato, 'consecutivo', u.consecutivo, 'hora', u.registrado_en) order by u.consecutivo desc), '[]'::jsonb)
                  from (select e.id, e.contrato, e.consecutivo, e.registrado_en from reparto.entregas e
                         where e.jornada_id = p_jornada and not exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = e.id)
                         order by e.consecutivo desc limit 5) u))
$$;

-- Contexto: quién es (repartidor, supervisor o ambos), las rutas del último período por ciclo, los archivos vigentes y sus jornadas de hoy
create function public.geoportal_reparto_contexto(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text; v_rep boolean := false; v_sup boolean := false; v_rutas jsonb; v_periodo text;
begin
  begin v_email := reparto.f_autorizar_repartidor(p_solicitante); v_rep := true; exception when sqlstate '42501' then null; end;
  begin v_email := reparto.f_autorizar_supervisor(p_solicitante); v_sup := true; exception when sqlstate '42501' then null; end;
  if not (v_rep or v_sup) then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  -- rutas del último período (ciclo 9999 «sin ciclo» no se ofrece: P4). Una sola lectura agrupada de la vista.
  with g as (select r.periodo_carga, r.ciclo, r.ruta, count(distinct r.contrato) as n from bi.v_rutas_geoportal r
              -- filtros en línea (no reparto.f_contrato ni f_num: con su search_path fijo no se incrustan y se llamarían ~114 mil veces)
              where r.ciclo is distinct from '9999' and r.contrato ~ '^[0-9]{1,12}$' and btrim(r.ruta) <> '' and r.ciclo ~ '^[0-9]{1,4}$'
              group by 1, 2, 3),
       c as (select g.ciclo, jsonb_agg(jsonb_build_object('ruta', g.ruta, 'n', g.n) order by reparto.f_num(g.ruta) nulls last, g.ruta) as rutas
               from g group by g.ciclo)
  select (select max(periodo_carga) from g), coalesce(jsonb_agg(jsonb_build_object('ciclo', c.ciclo, 'rutas', c.rutas) order by reparto.f_num(c.ciclo)), '[]'::jsonb)
    into v_periodo, v_rutas from c;
  return jsonb_build_object(
    'correo', v_email, 'es_repartidor', v_rep, 'es_supervisor', v_sup, 'es_admin', public.geoportal_es_admin(v_email), 'hoy', reparto.f_hoy(),
    'periodo', v_periodo, 'anterior', v_rutas,
    'nuevas', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'nombre_archivo', l.nombre_archivo, 'tipo', l.tipo, 'ciclo', l.ciclo, 'ruta', l.ruta,
                                                            'filas', l.filas, 'cargado_en', l.creado_en) order by reparto.f_num(l.ciclo), l.ruta nulls first, l.creado_en desc), '[]'::jsonb)
                 from reparto.lotes l
                where not exists (select 1 from reparto.lotes_anulados a where a.lote_id = l.id)
                  and l.creado_en >= now() - make_interval(days => (reparto.f_param('lote_vigencia_dias'))::int)),
    'mis_jornadas_hoy', (select coalesce(jsonb_agg(jsonb_build_object('id', v.jornada_id, 'origen', v.origen, 'ciclo', v.ciclo, 'ruta', v.ruta, 'nombre_archivo', v.nombre_archivo,
                                                                     'total', v.total, 'entregadas', v.entregadas, 'ultima', v.ultima) order by v.jornada_id), '[]'::jsonb)
                           from reparto.v_avance v where v.fecha = reparto.f_hoy() and v.repartidor = v_email),
    'parametros', jsonb_build_object('precision_mala_m', reparto.f_param('precision_mala_m'), 'ventana_dias', reparto.f_param('ventana_dias'),
                                     'tope_filas_lote', reparto.f_param('tope_filas_lote')));
end $$;

-- Empezar (o retomar) una jornada: el repartidor escoge el origen y la ruta. Idempotente: la misma persona, el mismo día y la misma fuente → la misma jornada.
create function public.geoportal_reparto_empezar(p_solicitante text, p_origen text, p_ciclo text default null, p_ruta text default null,
                                                 p_lote uuid default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_repartidor(p_solicitante); v_hoy date := reparto.f_hoy(); v_fuente text; v_periodo text; v_id bigint;
        v_lista text[]; v_lote record; v_ciclo text := btrim(coalesce(p_ciclo, '')); v_ruta text := btrim(coalesce(p_ruta, ''));
begin
  if p_origen is null or p_origen not in ('anterior', 'nueva', 'inventada') then perform reparto.f_err('Origen de la ruta no válido'); end if;
  if p_origen = 'anterior' then
    if v_ciclo !~ '^[0-9]{1,4}$' or v_ruta = '' or length(v_ruta) > 20 then perform reparto.f_err('Escoja el ciclo y la ruta'); end if;
    if v_ciclo = '9999' then perform reparto.f_err('El ciclo 9999 (sin ciclo) no se reparte por ruta: use «Repartir sin ruta»'); end if;
    select max(r.periodo_carga) into v_periodo from bi.v_rutas_geoportal r where r.ciclo = v_ciclo and r.ruta = v_ruta;
    if v_periodo is null then perform reparto.f_err('Esa ruta no está en el último período cargado'); end if;
    v_fuente := 'anterior:' || v_periodo || ':' || v_ciclo || ':' || v_ruta;
  elsif p_origen = 'nueva' then
    select l.* into v_lote from reparto.lotes l where l.id = p_lote;
    if not found then perform reparto.f_err('Ese archivo de ruta no existe'); end if;
    if exists (select 1 from reparto.lotes_anulados a where a.lote_id = p_lote) then perform reparto.f_err('El supervisor anuló ese archivo de ruta'); end if;
    if v_lote.creado_en < now() - make_interval(days => (reparto.f_param('lote_vigencia_dias'))::int) then perform reparto.f_err('Ese archivo de ruta ya venció: pida al supervisor que lo cargue de nuevo'); end if;
    v_fuente := 'nueva:' || p_lote::text;
  else
    v_fuente := 'inventada';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('reparto_jornada:' || v_hoy::text || ':' || v_email || ':' || v_fuente, 0));
  select j.id into v_id from reparto.jornadas j where j.fecha = v_hoy and j.repartidor = v_email and j.fuente = v_fuente;
  if v_id is not null then return reparto.f_lista(v_id) || jsonb_build_object('retomada', true); end if;
  if p_origen = 'anterior' then
    -- Orden de lectura (P1): consecutivo_ruta y, en los empates, consecutivo_predio; al final el contrato. Un contrato repetido en el período cuenta una vez (su primer lugar).
    select array_agg(x.contrato order by x.cr nulls last, x.cp nulls last, x.contrato) into v_lista
      from (select distinct on (r.contrato) r.contrato, reparto.f_num(r.consecutivo_ruta) as cr, reparto.f_num(r.consecutivo_predio) as cp
              from bi.v_rutas_geoportal r
             where r.ciclo = v_ciclo and r.ruta = v_ruta and r.periodo_carga = v_periodo and reparto.f_contrato(r.contrato) is not null
             order by r.contrato, reparto.f_num(r.consecutivo_ruta) nulls last, reparto.f_num(r.consecutivo_predio) nulls last) x;
    insert into reparto.jornadas (fecha, repartidor, origen, fuente, periodo, ciclo, ruta, total)
      values (v_hoy, v_email, 'anterior', v_fuente, v_periodo, v_ciclo, v_ruta, coalesce(cardinality(v_lista), 0)) returning id into v_id;
  elsif p_origen = 'nueva' then
    select array_agg(f.contrato order by f.orden) into v_lista from reparto.lote_filas f where f.lote_id = p_lote;
    insert into reparto.jornadas (fecha, repartidor, origen, fuente, ciclo, ruta, lote_id, total)
      values (v_hoy, v_email, 'nueva', v_fuente, v_lote.ciclo, v_lote.ruta, p_lote, coalesce(cardinality(v_lista), 0)) returning id into v_id;
  else
    insert into reparto.jornadas (fecha, repartidor, origen, fuente, total) values (v_hoy, v_email, 'inventada', v_fuente, 0) returning id into v_id;
  end if;
  if v_lista is not null then
    insert into reparto.jornada_items (jornada_id, orden_lectura, contrato) select v_id, u.o, u.c from unnest(v_lista) with ordinality u(c, o);
  end if;
  return reparto.f_lista(v_id) || jsonb_build_object('retomada', false);
end $$;

-- La lista de una jornada propia (para refrescar al volver la señal o tras recargar la página)
create function public.geoportal_reparto_lista(p_solicitante text, p_jornada bigint, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_repartidor(p_solicitante);
begin
  if not exists (select 1 from reparto.jornadas j where j.id = p_jornada and j.repartidor = v_email) then perform reparto.f_err('Esa lista no es suya', '42501'); end if;
  return reparto.f_lista(p_jornada);
end $$;

-- Registrar una entrega en el momento, con su XY. Doble toque y reintentos:
--  · el mismo id_cliente (uuid del toque) devuelve la MISMA entrega (repetida = true), sin error;
--  · un contrato con una entrega vigente en la ventana (cualquier repartidor u origen) no se registra otra vez;
--  · el consecutivo se calcula bajo el bloqueo de la jornada: no hay dos iguales.
create function public.geoportal_reparto_entregar(p_solicitante text, p_jornada bigint, p_contrato text, p_lon numeric, p_lat numeric, p_precision_m numeric,
                                                  p_por_buscador boolean, p_id_cliente uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text := reparto.f_autorizar_repartidor(p_solicitante); v_c text := reparto.f_contrato(p_contrato); v_j record; v_orden integer;
        v_prev record; v_cons integer; v_id bigint; v_hora timestamptz; v_vig bigint;
begin
  if p_id_cliente is null then perform reparto.f_err('Falta el identificador del toque'); end if;
  -- primero el bloqueo de la jornada: así un reintento que llega A LA VEZ espera al primero y después lo encuentra por su uuid
  select j.* into v_j from reparto.jornadas j where j.id = p_jornada for update;
  if not found or v_j.repartidor <> v_email then perform reparto.f_err('Esa lista no es suya', '42501'); end if;
  select e.id, e.consecutivo, e.contrato, e.autor, e.registrado_en into v_prev from reparto.entregas e where e.id_cliente = p_id_cliente;
  if found then
    if v_prev.autor <> v_email then perform reparto.f_err('Identificador de toque no válido'); end if;
    return jsonb_build_object('entrega_id', v_prev.id, 'consecutivo', v_prev.consecutivo, 'contrato', v_prev.contrato, 'registrado_en', v_prev.registrado_en, 'repetida', true);
  end if;
  if v_c is null then perform reparto.f_err('El código del contrato no es válido (solo números)'); end if;
  if p_lon is null or p_lat is null or p_precision_m is null then perform reparto.f_err('Sin ubicación del GPS: la entrega no se guardó. Active la ubicación e intente de nuevo.'); end if;
  if p_lon not between -82 and -66 or p_lat not between -5 and 14 or p_precision_m < 0 or p_precision_m > 5000 then
    perform reparto.f_err('La ubicación del GPS no es válida: la entrega no se guardó');
  end if;
  if v_j.fecha <> reparto.f_hoy() then perform reparto.f_err('Esta lista es de otro día: vuelva a escoger la ruta', '55000'); end if;
  if v_j.lote_id is not null and exists (select 1 from reparto.lotes_anulados a where a.lote_id = v_j.lote_id) then
    perform reparto.f_err('El supervisor anuló el archivo de esta ruta', '55000');
  end if;
  if v_j.origen = 'inventada' then
    if not exists (select 1 from public.cartera_suscripcion s where s.contrato = v_c)
       and not exists (select 1 from bi.v_rutas_geoportal r where r.contrato = v_c) then
      perform reparto.f_err('No hay ningún contrato con el código ' || v_c);
    end if;
  else
    select it.orden_lectura into v_orden from reparto.jornada_items it where it.jornada_id = p_jornada and it.contrato = v_c;
    if v_orden is null then perform reparto.f_err('El contrato ' || v_c || ' no está en esta ruta'); end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('reparto_contrato:' || v_c, 0));
  v_vig := reparto.f_entrega_vigente(v_c, reparto.f_desde());
  if v_vig is not null then
    select e.id, e.consecutivo, e.autor, e.registrado_en into v_prev from reparto.entregas e where e.id = v_vig;
    perform reparto.f_err(format('La factura del contrato %s ya se registró el %s%s', v_c,
              to_char(v_prev.registrado_en at time zone 'America/Bogota', 'DD/MM "a las" HH24:MI'),
              case when v_prev.autor = v_email then ' (entrega ' || v_prev.consecutivo || ')' else ', por otro repartidor' end), '23505');
  end if;
  select coalesce(max(e.consecutivo), 0) + 1 into v_cons from reparto.entregas e where e.jornada_id = p_jornada;
  begin
    insert into reparto.entregas (jornada_id, contrato, consecutivo, orden_lectura, lon, lat, precision_m, por_buscador, id_cliente, autor)
      values (p_jornada, v_c, v_cons, v_orden, round(p_lon, 6), round(p_lat, 6), round(p_precision_m, 1), coalesce(p_por_buscador, false), p_id_cliente, v_email)
      returning id, registrado_en into v_id, v_hora;
  exception when unique_violation then
    -- el mismo toque llegó dos veces a la vez: gana el primero y este devuelve el mismo
    select e.id, e.consecutivo, e.contrato, e.autor, e.registrado_en into v_prev from reparto.entregas e where e.id_cliente = p_id_cliente;
    if found and v_prev.autor = v_email then
      return jsonb_build_object('entrega_id', v_prev.id, 'consecutivo', v_prev.consecutivo, 'contrato', v_prev.contrato, 'registrado_en', v_prev.registrado_en, 'repetida', true);
    end if;
    raise;
  end;
  return jsonb_build_object('entrega_id', v_id, 'consecutivo', v_cons, 'contrato', v_c, 'registrado_en', v_hora, 'repetida', false,
                            'precision_mala', p_precision_m > (reparto.f_param('precision_mala_m'))::numeric);
end $$;

-- Anular una entrega con motivo (P7): el supervisor, cualquiera; el repartidor, solo las suyas del mismo día. Nada se borra y el consecutivo no se renumera.
create function public.geoportal_reparto_anular(p_solicitante text, p_entrega bigint, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, reparto as $$
declare v_email text; v_sup boolean := false; v_e record; v_m text := btrim(coalesce(p_motivo, ''));
begin
  begin v_email := reparto.f_autorizar_supervisor(p_solicitante); v_sup := true; exception when sqlstate '42501' then null; end;
  if not v_sup then v_email := reparto.f_autorizar_repartidor(p_solicitante); end if;
  if length(v_m) not between 10 and 300 then perform reparto.f_err('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
  select e.* into v_e from reparto.entregas e where e.id = p_entrega;
  if not found then perform reparto.f_err('Esa entrega no existe'); end if;
  if not v_sup and (v_e.autor <> v_email or (v_e.registrado_en at time zone 'America/Bogota')::date <> reparto.f_hoy()) then
    perform reparto.f_err('Solo puede anular sus propias entregas de hoy; las demás las anula el supervisor', '42501');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('reparto_contrato:' || v_e.contrato, 0));
  if exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = p_entrega) then perform reparto.f_err('Esa entrega ya estaba anulada', '55000'); end if;
  insert into reparto.entregas_anuladas (entrega_id, motivo, autor) values (p_entrega, v_m, v_email);
  if v_sup then perform reparto.f_auditar(v_email, 'reparto_anular_entrega', p_entrega::text, jsonb_build_object('contrato', v_e.contrato), p_ip); end if;
  return jsonb_build_object('ok', true, 'entrega_id', p_entrega, 'contrato', v_e.contrato);
end $$;
