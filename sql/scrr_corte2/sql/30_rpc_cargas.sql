-- =====================================================================
-- SCRR · CORTE 2 · 30 — RPC de la carga del día (cartera, pagos, actividades) y de la reversión de cartera_suscripcion
-- Convención del proyecto: SECURITY DEFINER, p_solicitante PRIMERO y p_ip AL FINAL, respuesta jsonb, mensajes para la persona con HINT = 'msg_usuario',
-- ejecutables solo por service_role. El solicitante lo pone la Edge con el correo del token. Auditoría en public.geoportal_auditoria.
-- SQLSTATE (la Edge los traduce): 42501 sin permiso (403), 22023 dato no válido (400), P0002 no existe (404), 55000 estado no permite (409),
-- 57P03 cargas en pausa (503).
-- Aplicar va POR LOTES (una llamada por lote de 2.000 filas y una de cierre): ninguna petición reescribe ni recalcula tablas enteras.
-- =====================================================================

create function scrr.f_err(p_mensaje text, p_codigo text default '22023') returns void
language plpgsql set search_path = pg_catalog as $$
begin
  raise exception '%', p_mensaje using errcode = p_codigo, hint = 'msg_usuario';
end $$;

-- Actividad del archivo (sin tildes, mayúsculas): 1 suspensión, 2 corte, 3 gestión de cobro, 4 reinstalación, 5 reconexión, 6 reconexión drástica
create function scrr.f_actividad(p text) returns smallint
language sql immutable parallel safe set search_path = pg_catalog as $$
  with t as (select regexp_replace(upper(translate(btrim(coalesce(p, '')), 'ÁÉÍÓÚáéíóúÑñ', 'AEIOUAEIOUNN')), '\s+', ' ', 'g') as x)
  select case when x like '%RECONEX%' or x like '%RECONECC%' then (case when x like '%DRASTIC%' then 6 else 5 end)
              when x like '%REINSTAL%' then 4
              when x like '%CORTE%' then 2
              when x like '%SUSPEN%' then 1
              when x like '%COBRO%' or x like '%GESTION%' then 3 end::smallint from t
$$;
-- Marca SÍ/NO del archivo: true, false o nulo si no se entiende
create function scrr.f_si_no(p text) returns boolean
language sql immutable parallel safe set search_path = pg_catalog as $$
  with t as (select upper(translate(btrim(coalesce(p, '')), 'Íí', 'II')) as x)
  select case when x in ('', 'NO', 'N', '0', 'FALSE', 'FALSO') then false when x in ('SI', 'S', '1', 'X', 'TRUE', 'VERDADERO') then true end from t
$$;

-- ---------------------------------------------------------------------
-- Contexto del modo «Cartera» (lo pide la pantalla al abrir)
-- ---------------------------------------------------------------------
create function public.geoportal_scrr_contexto(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante);
begin
  return jsonb_build_object('correo', v_email, 'es_admin', public.geoportal_es_admin(v_email),
    'parametros', jsonb_build_object('lote_filas', scrr.f_param('lote_filas'), 'tope_filas_archivo', scrr.f_param('tope_filas_archivo'),
                                     'comodin_contrato', scrr.f_param('comodin_contrato'), 'carga_pausada', scrr.f_param('carga_pausada'),
                                     'ventana_dias_historial', scrr.f_param('ventana_dias_historial'), 'retencion_meses_pagos', scrr.f_param('retencion_meses_pagos'),
                                     'tope_rechazo_pct', scrr.f_param('tope_rechazo_pct'), 'tope_salidas_suscripcion_pct', scrr.f_param('tope_salidas_suscripcion_pct')),
    'tipos_actividad', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'codigo', codigo, 'nombre', nombre, 'seleccionable', seleccionable, 'admite_drastico', admite_drastico) order by orden), '[]'::jsonb)
                          from scrr.tipos_actividad where activo),
    'anomalias', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'provisional', provisional) order by orden), '[]'::jsonb) from scrr.anomalias where activo));
end $$;

-- ---------------------------------------------------------------------
-- Cargas
-- ---------------------------------------------------------------------
-- Iniciar (idempotente: el mismo archivo de la misma persona con la carga aún abierta devuelve la misma carga)
create function public.geoportal_scrr_carga_iniciar(p_solicitante text, p_tipo text, p_fecha_dato date, p_nombre text, p_sha256 text, p_filas integer,
                                                    p_reemplaza uuid default null, p_motivo text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_id uuid; v_lote integer; v_tope integer; v_hoy date := (now() at time zone 'America/Bogota')::date;
        v_vig record; v_ver smallint := 1; v_ab uuid;
begin
  if p_tipo is null or p_tipo not in ('cartera','pagos','actividades') then perform scrr.f_err('Tipo de carga no válido'); end if;
  if p_fecha_dato is null or p_fecha_dato > v_hoy or p_fecha_dato < date '2020-01-01' then perform scrr.f_err('La fecha del dato no es válida (no puede ser futura)'); end if;
  if coalesce(p_sha256, '') !~ '^[0-9a-f]{64}$' then perform scrr.f_err('Huella del archivo no válida'); end if;
  if length(btrim(coalesce(p_nombre, ''))) not between 1 and 200 then perform scrr.f_err('Nombre de archivo no válido'); end if;
  v_lote := (scrr.f_param('lote_filas'))::integer; v_tope := (scrr.f_param('tope_filas_archivo'))::integer;
  if p_filas is null or p_filas < 1 or p_filas > v_tope then perform scrr.f_err(format('El archivo debe tener entre 1 y %s filas', v_tope)); end if;
  if scrr.f_param('carga_pausada') = 'true'::jsonb then perform scrr.f_err('Las cargas están en pausa. Intente más tarde.', '57P03'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_iniciar:' || p_tipo || ':' || p_fecha_dato::text, 0));
  select c.id into v_id from scrr.cargas c where c.tipo = p_tipo and c.fecha_dato = p_fecha_dato and c.archivo_sha256 = p_sha256 and c.autor = v_email
     and scrr.f_estado_carga(c.id) in ('en_paso','validada') order by c.creado_en desc limit 1;
  if v_id is not null then return jsonb_build_object('carga_id', v_id, 'lote_filas', v_lote, 'lotes', ceil(p_filas::numeric / v_lote)::int, 'repetido', true); end if;
  select * into v_vig from scrr.v_cargas_vigentes where tipo = p_tipo and fecha_dato = p_fecha_dato;
  if found then
    if p_reemplaza is distinct from v_vig.id then
      perform scrr.f_err('Ya hay una carga aplicada de este tipo con esa fecha del dato. Para reemplazarla indique cuál y el motivo.', '55000'); end if;
    if p_tipo <> 'cartera' then perform scrr.f_err('Las cargas de pagos y de actividades acumulan y no se reemplazan: cargue solo lo que falta', '55000'); end if;
    if length(btrim(coalesce(p_motivo, ''))) not between 10 and 300 then perform scrr.f_err('Reemplazar una carga exige un motivo de 10 a 300 caracteres'); end if;
  elsif p_reemplaza is not null then
    perform scrr.f_err('La carga que se quiere reemplazar no está vigente', '55000');
  end if;
  select c.id into v_ab from scrr.cargas c where c.tipo = p_tipo and scrr.f_estado_carga(c.id) in ('en_paso','validada','aplicando') limit 1;
  if v_ab is not null then perform scrr.f_err('Hay otra carga abierta de este tipo. Termínela o anúlela antes.', '55000'); end if;
  v_ver := coalesce((select max(c.version) from scrr.cargas c where c.tipo = p_tipo and c.fecha_dato = p_fecha_dato), 0) + 1;
  v_id := gen_random_uuid();
  insert into scrr.cargas (id, tipo, fecha_dato, version, reemplaza_id, archivo_nombre, archivo_sha256, filas_leidas, autor)
    values (v_id, p_tipo, p_fecha_dato, v_ver, case when p_reemplaza is not null then v_vig.id end, btrim(p_nombre), p_sha256, p_filas, v_email);
  insert into scrr.carga_eventos (carga_id, evento, resumen, motivo, autor)
    values (v_id, 'iniciada', jsonb_build_object('lote_filas', v_lote, 'filas', p_filas), case when p_reemplaza is not null then btrim(p_motivo) end, v_email);
  perform scrr.f_auditar(v_email, 'scrr_carga_iniciar', v_id::text, jsonb_build_object('tipo', p_tipo, 'fecha_dato', p_fecha_dato, 'filas', p_filas, 'version', v_ver), p_ip);
  return jsonb_build_object('carga_id', v_id, 'lote_filas', v_lote, 'lotes', ceil(p_filas::numeric / v_lote)::int, 'version', v_ver, 'repetido', false);
end $$;

-- Subir un lote (idempotente: reenviar el mismo lote no duplica; reenviarlo con otro contenido es un error). Valida cada fila y deja su error en el paso.
create function public.geoportal_scrr_carga_lote(p_solicitante text, p_carga uuid, p_lote integer, p_filas jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas; v_lote integer; v_n integer; v_esperadas integer; v_huella text; v_prev text;
        v_hoy date := (now() at time zone 'America/Bogota')::date; v_ret date;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found then perform scrr.f_err('La carga no existe', 'P0002'); end if;
  if scrr.f_estado_carga(p_carga) not in ('en_paso','validada') then perform scrr.f_err('La carga ya no admite lotes', '55000'); end if;
  if scrr.f_param('carga_pausada') = 'true'::jsonb then perform scrr.f_err('Las cargas están en pausa. Intente más tarde.', '57P03'); end if;
  v_lote := (scrr.f_param('lote_filas'))::integer;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then perform scrr.f_err('El lote no es una lista de filas'); end if;
  v_n := jsonb_array_length(p_filas);
  if p_lote is null or p_lote < 1 or p_lote > ceil(c.filas_leidas::numeric / v_lote) then perform scrr.f_err('Número de lote fuera de rango'); end if;
  v_esperadas := least(v_lote, c.filas_leidas - (p_lote - 1) * v_lote);
  if v_n <> v_esperadas then perform scrr.f_err(format('El lote %s debe traer %s filas y trae %s', p_lote, v_esperadas, v_n)); end if;
  v_huella := md5(p_filas::text);
  perform pg_advisory_xact_lock(hashtextextended('scrr_lote:' || p_carga::text || ':' || p_lote, 0));
  select huella into v_prev from scrr.carga_eventos where carga_id = p_carga and evento = 'lote_recibido' and lote = p_lote;
  if found then
    if v_prev = v_huella then return jsonb_build_object('lote', p_lote, 'repetido', true); end if;
    perform scrr.f_err(format('El lote %s ya se recibió con otro contenido', p_lote), '55000');
  end if;

  if c.tipo = 'cartera' then
    insert into scrr.paso_cartera (carga_id, lote, fila, contrato, estado, identificacion, nombre, correo, telefono, direccion, barrio, categoria, subcategoria, ciclo,
                                   facturas_pendientes, facturas_vencidas, deuda_total, saldo_pendiente, saldo_a_favor, valor_reclamo, saldo_financiado,
                                   serial_medidor, codigo_reparto, ruta, error)
    select p_carga, p_lote, e.o::int,
           case when btrim(e.v->>'contrato') ~ '^[0-9]{1,12}$' then btrim(e.v->>'contrato') end,
           scrr.f_txt(e.v->>'estado', 60), scrr.f_txt(e.v->>'identificacion', 40), scrr.f_txt(e.v->>'nombre', 200), scrr.f_txt(e.v->>'correo', 200),
           scrr.f_txt(e.v->>'telefono', 60), scrr.f_txt(e.v->>'direccion', 200), scrr.f_txt(e.v->>'barrio', 80), scrr.f_txt(e.v->>'categoria', 80),
           scrr.f_txt(e.v->>'subcategoria', 80), scrr.f_txt(e.v->>'ciclo', 10),
           case when scrr.f_num(e.v->>'facturas_pendientes') between 0 and 999 and scrr.f_num(e.v->>'facturas_pendientes') = trunc(scrr.f_num(e.v->>'facturas_pendientes')) then scrr.f_num(e.v->>'facturas_pendientes')::smallint end,
           case when scrr.f_num(e.v->>'facturas_vencidas') between 0 and 999 and scrr.f_num(e.v->>'facturas_vencidas') = trunc(scrr.f_num(e.v->>'facturas_vencidas')) then scrr.f_num(e.v->>'facturas_vencidas')::smallint end,
           scrr.f_num(e.v->>'deuda_total'), scrr.f_num(e.v->>'saldo_pendiente'), scrr.f_num(e.v->>'saldo_a_favor'), scrr.f_num(e.v->>'valor_reclamo'), scrr.f_num(e.v->>'saldo_financiado'),
           scrr.f_txt(e.v->>'serial_medidor', 60), scrr.f_txt(e.v->>'codigo_reparto', 40), scrr.f_txt(e.v->>'ruta', 80),
           case when btrim(coalesce(e.v->>'contrato','')) !~ '^[0-9]{1,12}$' then 'Contrato ausente o no numérico'
                when scrr.f_num(e.v->>'facturas_pendientes') is null or scrr.f_num(e.v->>'facturas_pendientes') not between 0 and 999
                     or scrr.f_num(e.v->>'facturas_pendientes') <> trunc(scrr.f_num(e.v->>'facturas_pendientes')) then 'Facturas pendientes ausentes o no válidas'
                when scrr.f_num(e.v->>'facturas_vencidas') is null or scrr.f_num(e.v->>'facturas_vencidas') not between 0 and 999
                     or scrr.f_num(e.v->>'facturas_vencidas') <> trunc(scrr.f_num(e.v->>'facturas_vencidas')) then 'Facturas vencidas ausentes o no válidas'
                when scrr.f_num(e.v->>'deuda_total') is null or scrr.f_num(e.v->>'saldo_pendiente') is null or scrr.f_num(e.v->>'saldo_a_favor') is null
                     or scrr.f_num(e.v->>'valor_reclamo') is null or scrr.f_num(e.v->>'saldo_financiado') is null then 'Cifra obligatoria ausente o con formato no válido'
                when nullif(btrim(coalesce(e.v->>'ciclo', '')), '') is not null and scrr.f_num(e.v->>'ciclo') is null then 'Ciclo no válido' end
      from jsonb_array_elements(p_filas) with ordinality as e(v, o);
  elsif c.tipo = 'pagos' then
    v_ret := (date_trunc('month', v_hoy) - make_interval(months => (scrr.f_param('retencion_meses_pagos'))::int))::date;
    insert into scrr.paso_pagos (carga_id, lote, fila, contrato, fecha_pago, monto, error)
    select p_carga, p_lote, e.o::int,
           case when btrim(e.v->>'contrato') ~ '^[0-9]{1,12}$' then btrim(e.v->>'contrato')::bigint end,
           scrr.f_fecha(e.v->>'fecha_pago'), scrr.f_num(e.v->>'monto'),
           case when btrim(coalesce(e.v->>'contrato','')) !~ '^[0-9]{1,12}$' then 'Contrato ausente o no numérico'
                when scrr.f_fecha(e.v->>'fecha_pago') is null then 'Fecha de pago ausente o no válida'
                when scrr.f_fecha(e.v->>'fecha_pago') > v_hoy then 'Fecha de pago futura'
                when scrr.f_fecha(e.v->>'fecha_pago') < v_ret then 'Fecha de pago fuera de la retención'
                when scrr.f_num(e.v->>'monto') is null or scrr.f_num(e.v->>'monto') = 0 then 'Monto ausente, en cero o no válido' end
      from jsonb_array_elements(p_filas) with ordinality as e(v, o);
  else
    insert into scrr.paso_actividades (carga_id, lote, fila, contrato, acta, actividad_texto, tipo_actividad_id, drastico, estado_original, anomalia, observacion,
                                       fecha_ejecucion, hora_inicio, hora_fin, lectura, medidor, marca, operario, error)
    select p_carga, p_lote, e.o::int,
           case when btrim(e.v->>'contrato') ~ '^[0-9]{1,12}$' then btrim(e.v->>'contrato')::bigint end,
           scrr.f_txt(e.v->>'acta', 40), scrr.f_txt(e.v->>'actividad', 60), scrr.f_actividad(e.v->>'actividad'),
           coalesce(scrr.f_si_no(e.v->>'drastico'), false) or (scrr.f_actividad(e.v->>'actividad') = 2 and upper(coalesce(e.v->>'actividad', '')) like '%DRASTIC%'),
           case when scrr.f_num(e.v->>'estado') in (3, 4) then scrr.f_num(e.v->>'estado')::smallint end,
           case when scrr.f_num(e.v->>'anomalia') between 1 and 99 and scrr.f_num(e.v->>'anomalia') = trunc(scrr.f_num(e.v->>'anomalia')) then scrr.f_num(e.v->>'anomalia')::smallint end,
           scrr.f_txt(e.v->>'observacion', 300), scrr.f_fecha(e.v->>'fecha'), scrr.f_hora(e.v->>'hora_inicial'), scrr.f_hora(e.v->>'hora_final'),
           case when scrr.f_num(e.v->>'lectura') between 0 and 99999999 and scrr.f_num(e.v->>'lectura') = trunc(scrr.f_num(e.v->>'lectura')) then scrr.f_num(e.v->>'lectura')::int end,
           scrr.f_txt(e.v->>'medidor', 40), scrr.f_txt(e.v->>'marca', 40), scrr.f_txt(e.v->>'operario', 80),
           case when btrim(coalesce(e.v->>'contrato','')) !~ '^[0-9]{1,12}$' then 'Contrato ausente o no numérico'
                when scrr.f_actividad(e.v->>'actividad') is null then 'Actividad no reconocida'
                when scrr.f_si_no(e.v->>'drastico') is null then 'Drástico debe ser SÍ o NO'
                when scrr.f_si_no(e.v->>'drastico') and scrr.f_actividad(e.v->>'actividad') <> 2 then 'La marca de drástico solo aplica a Corte'
                when scrr.f_num(e.v->>'estado') is null or scrr.f_num(e.v->>'estado') not in (3, 4) then 'Estado distinto de 3 (efectiva) o 4 (inefectiva)'
                when nullif(btrim(coalesce(e.v->>'anomalia', '')), '') is not null
                     and not exists (select 1 from scrr.anomalias a where a.activo and a.codigo::numeric = scrr.f_num(e.v->>'anomalia')) then 'Anomalía fuera del catálogo (1 a 17)'
                when scrr.f_num(e.v->>'estado') = 4 and nullif(btrim(coalesce(e.v->>'anomalia', '')), '') is null then 'Inefectiva sin anomalía'
                when scrr.f_fecha(e.v->>'fecha') is null then 'Fecha ausente o no válida'
                when scrr.f_fecha(e.v->>'fecha') > v_hoy then 'Fecha futura'
                when nullif(btrim(coalesce(e.v->>'hora_inicial', '')), '') is not null and scrr.f_hora(e.v->>'hora_inicial') is null then 'Hora inicial no válida'
                when nullif(btrim(coalesce(e.v->>'hora_final', '')), '') is not null and scrr.f_hora(e.v->>'hora_final') is null then 'Hora final no válida'
                when nullif(btrim(coalesce(e.v->>'lectura', '')), '') is not null
                     and not (scrr.f_num(e.v->>'lectura') between 0 and 99999999 and scrr.f_num(e.v->>'lectura') = trunc(scrr.f_num(e.v->>'lectura'))) then 'Lectura no válida' end
      from jsonb_array_elements(p_filas) with ordinality as e(v, o);
  end if;
  insert into scrr.carga_eventos (carga_id, evento, lote, huella, resumen, autor) values (p_carga, 'lote_recibido', p_lote, v_huella, jsonb_build_object('filas', v_n), v_email);
  return jsonb_build_object('lote', p_lote, 'repetido', false, 'filas', v_n);
end $$;

-- Validar en el servidor: cobertura de lotes, rechazos y resumen. No escribe en las tablas finales.
create function public.geoportal_scrr_carga_validar(p_solicitante text, p_carga uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas; v_lote integer; v_lotes integer; v_faltan jsonb; v_tot bigint; v_mal bigint; v_res jsonb; v_pct numeric; v_tope numeric;
        v_prev record; v_com text;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found then perform scrr.f_err('La carga no existe', 'P0002'); end if;
  if scrr.f_estado_carga(p_carga) not in ('en_paso','validada') then perform scrr.f_err('La carga ya no se puede validar', '55000'); end if;
  v_lote := (scrr.f_param('lote_filas'))::integer; v_lotes := ceil(c.filas_leidas::numeric / v_lote)::int; v_tope := (scrr.f_param('tope_rechazo_pct'))::numeric;
  v_com := scrr.f_param('comodin_contrato') #>> '{}';
  select coalesce(jsonb_agg(g), '[]'::jsonb) into v_faltan from generate_series(1, v_lotes) g
   where not exists (select 1 from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_recibido' and e.lote = g);

  if c.tipo = 'cartera' then
    select count(*), count(*) filter (where error is not null) into v_tot, v_mal from scrr.paso_cartera where carga_id = p_carga;
    select jsonb_build_object('contratos_distintos', count(distinct contrato) filter (where error is null),
             'contratos_repetidos', count(*) filter (where error is null) - count(distinct contrato) filter (where error is null),
             'con_saldo_pendiente', count(distinct contrato) filter (where error is null and saldo_pendiente > 0),
             'con_facturas_vencidas', count(distinct contrato) filter (where error is null and facturas_vencidas > 0),
             'saldo_pendiente_total', coalesce(sum(saldo_pendiente) filter (where error is null and saldo_pendiente > 0), 0),
             'con_valor_reclamo', count(*) filter (where error is null and valor_reclamo > 0),
             'comodin_o_categoria_menos_1', count(*) filter (where error is null and (contrato = v_com or categoria ~ '^-1')),
             'sin_ciclo_o_sin_ruta', count(*) filter (where error is null and saldo_pendiente > 0 and (scrr.f_num(ciclo) is null or scrr.f_num(ciclo) in (0, 9999) or ruta is null)),
             'sin_barrio', count(*) filter (where error is null and saldo_pendiente > 0 and barrio is null)) into v_res
      from scrr.paso_cartera where carga_id = p_carga;
    select v.fecha_dato, v.id into v_prev from scrr.v_cargas_vigentes v where v.tipo = 'cartera' and v.fecha_dato < c.fecha_dato order by v.fecha_dato desc limit 1;
    if found then
      v_res := v_res || jsonb_build_object('foto_anterior', v_prev.fecha_dato,
         'con_saldo_en_la_anterior', (select count(*) from scrr.cartera_historial h where h.fecha_dato = v_prev.fecha_dato and h.carga_id = v_prev.id and h.en_cartera));
    end if;
    v_res := v_res || jsonb_build_object('filas_en_cartera_suscripcion_hoy', (select count(*) from public.cartera_suscripcion));
  elsif c.tipo = 'pagos' then
    select count(*), count(*) filter (where error is not null) into v_tot, v_mal from scrr.paso_pagos where carga_id = p_carga;
    select jsonb_build_object('pagos_validos', count(*) filter (where error is null), 'monto_total', coalesce(sum(monto) filter (where error is null), 0),
             'primer_pago', min(fecha_pago) filter (where error is null), 'ultimo_pago', max(fecha_pago) filter (where error is null),
             'contratos_distintos', count(distinct contrato) filter (where error is null),
             'identicos_en_el_archivo', count(*) filter (where error is null)
                - (select count(*) from (select 1 from scrr.paso_pagos q where q.carga_id = p_carga and q.error is null group by q.contrato, q.fecha_pago, q.monto) z)) into v_res
      from scrr.paso_pagos where carga_id = p_carga;
  else
    select count(*), count(*) filter (where error is not null) into v_tot, v_mal from scrr.paso_actividades where carga_id = p_carga;
    select jsonb_build_object('efectivas', count(*) filter (where error is null and estado_original = 3), 'inefectivas', count(*) filter (where error is null and estado_original = 4),
             'cortes_drasticos', count(*) filter (where error is null and drastico),
             'por_actividad', coalesce((select jsonb_object_agg(t.codigo, z.n) from (select tipo_actividad_id, count(*) n from scrr.paso_actividades
                                         where carga_id = p_carga and error is null group by 1) z join scrr.tipos_actividad t on t.id = z.tipo_actividad_id), '{}'::jsonb),
             'repetidas_en_el_archivo', count(*) filter (where error is null)
                - (select count(*) from (select 1 from scrr.paso_actividades q where q.carga_id = p_carga and q.error is null group by q.contrato, q.tipo_actividad_id, q.fecha_ejecucion) z),
             'primera', min(fecha_ejecucion) filter (where error is null), 'ultima', max(fecha_ejecucion) filter (where error is null)) into v_res
      from scrr.paso_actividades where carga_id = p_carga;
  end if;
  v_pct := case when v_tot = 0 then 100 else round(v_mal * 100.0 / v_tot, 2) end;
  v_res := v_res || jsonb_build_object('filas_en_paso', v_tot, 'filas_esperadas', c.filas_leidas, 'filas_rechazadas', v_mal, 'pct_rechazadas', v_pct, 'lotes_faltantes', v_faltan,
             'causas_rechazo', coalesce((select jsonb_object_agg(error, n) from (select error, count(*) n from (
                 select error from scrr.paso_cartera where carga_id = p_carga and error is not null
                 union all select error from scrr.paso_pagos where carga_id = p_carga and error is not null
                 union all select error from scrr.paso_actividades where carga_id = p_carga and error is not null) u group by error) z), '{}'::jsonb));
  v_res := v_res || jsonb_build_object('puede_aplicar', (jsonb_array_length(v_faltan) = 0 and v_tot = c.filas_leidas and v_pct <= v_tope and v_tot - v_mal > 0),
                                       'tope_rechazo_pct', v_tope, 'lotes', v_lotes);
  insert into scrr.carga_eventos (carga_id, evento, resumen, autor) values (p_carga, 'validada', v_res, v_email);
  perform scrr.f_auditar(v_email, 'scrr_carga_validar', p_carga::text, jsonb_build_object('rechazadas', v_mal, 'filas', v_tot), p_ip);
  return v_res;
end $$;

-- Aplicar UN LOTE (p_lote) o CERRAR la carga (p_lote nulo, cuando todos los lotes están aplicados).
--  · cartera, por lote: historial de los contratos con saldo pendiente y reemplazo de sus filas en public.cartera_suscripcion con respaldo previo.
--    cierre: filas de salida del historial y retiro, con respaldo, de los contratos de cartera_suscripcion que no vinieron en el archivo. Si son más del tope
--    (tope_salidas_suscripcion_pct de la tabla), se exige confirmarlo con motivo: protege contra un archivo incompleto.
--  · pagos y actividades: acumulan sin duplicar (pagos por contrato + fecha + monto + ordinal; actas por contrato + actividad + fecha).
create function public.geoportal_scrr_carga_aplicar(p_solicitante text, p_carga uuid, p_lote integer default null, p_confirmar_salidas boolean default false,
                                                    p_motivo text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas; v_val jsonb; v_est text; v_lotes integer; v_vig record; v_prev record;
        v_com text; n1 bigint := 0; n2 bigint := 0; n3 bigint := 0; n4 bigint := 0; v_min date; v_max date; v_res jsonb; v_tot bigint; v_tope numeric;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found then perform scrr.f_err('La carga no existe', 'P0002'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_aplicar:' || c.tipo, 0));
  v_est := scrr.f_estado_carga(p_carga);
  if v_est not in ('validada','aplicando') then perform scrr.f_err('La carga debe estar validada antes de aplicarse', '55000'); end if;
  select resumen into v_val from scrr.carga_eventos where carga_id = p_carga and evento = 'validada' order by id desc limit 1;
  if coalesce((v_val->>'puede_aplicar')::boolean, false) is not true then perform scrr.f_err('La validación no permite aplicar: revise lotes faltantes y filas rechazadas', '55000'); end if;
  if scrr.f_param('carga_pausada') = 'true'::jsonb then perform scrr.f_err('Las cargas están en pausa. Intente más tarde.', '57P03'); end if;
  select * into v_vig from scrr.v_cargas_vigentes where tipo = c.tipo and fecha_dato = c.fecha_dato;
  if found and v_vig.id is distinct from c.reemplaza_id then perform scrr.f_err('Ya hay una carga aplicada con esa fecha del dato', '55000'); end if;
  v_lotes := (v_val->>'lotes')::int;
  v_com := scrr.f_param('comodin_contrato') #>> '{}';

  -- ======================= UN LOTE =======================
  if p_lote is not null then
    if p_lote < 1 or p_lote > v_lotes then perform scrr.f_err('Número de lote fuera de rango'); end if;
    if exists (select 1 from scrr.carga_eventos where carga_id = p_carga and evento = 'lote_aplicado' and lote = p_lote) then
      return jsonb_build_object('lote', p_lote, 'repetido', true);
    end if;
    if c.tipo = 'cartera' then
      if to_regclass('scrr.cartera_historial_' || to_char(c.fecha_dato, 'YYYYMMDD')) is null then
        set local lock_timeout = '5s';
        perform scrr.f_preparar_historial(c.fecha_dato, c.fecha_dato);
      end if;
      insert into scrr.barrios (nombre_norm)
        select distinct scrr.f_barrio_norm(barrio) from scrr.paso_cartera where carga_id = p_carga and lote = p_lote and error is null and scrr.f_barrio_norm(barrio) is not null
        on conflict (nombre_norm) do nothing;
      -- historial: contratos con saldo pendiente (un contrato repetido en el archivo cuenta una vez: la fila de mayor saldo dentro del lote; entre lotes, la primera)
      insert into scrr.cartera_historial (fecha_dato, version, contrato, en_cartera, marca, estado, categoria, ciclo, ruta, codigo_reparto, barrio_id,
                                          facturas_pendientes, facturas_vencidas, deuda_total, saldo_pendiente, saldo_a_favor, saldo_financiado, valor_reclamo, carga_id)
        select c.fecha_dato, c.version, s.contrato::bigint, true,
               case when s.contrato = v_com or s.categoria ~ '^-1' then 1 else 0 end, s.estado, s.categoria,
               case when scrr.f_num(s.ciclo) between 0 and 9999 then scrr.f_num(s.ciclo)::smallint end, s.ruta, s.codigo_reparto, b.id,
               s.facturas_pendientes, s.facturas_vencidas, s.deuda_total, s.saldo_pendiente, s.saldo_a_favor, s.saldo_financiado, s.valor_reclamo, p_carga
          from (select distinct on (contrato) * from scrr.paso_cartera where carga_id = p_carga and lote = p_lote and error is null and saldo_pendiente > 0
                 order by contrato, saldo_pendiente desc, fila) s
          left join scrr.barrios b on b.nombre_norm = scrr.f_barrio_norm(s.barrio)
        on conflict (fecha_dato, version, contrato) do nothing;
      get diagnostics n1 = row_count;
      -- cartera_suscripcion: respaldo de lo que había (solo la primera vez que la carga toca el contrato), retiro de esas filas e inserción de las del archivo
      with tocados as (select distinct p.contrato from scrr.paso_cartera p where p.carga_id = p_carga and p.lote = p_lote and p.error is null),
           nuevos as (select t.contrato from tocados t where not exists (select 1 from scrr.suscripcion_respaldo r where r.carga_id = p_carga and r.contrato = t.contrato)),
           resp as (insert into scrr.suscripcion_respaldo (carga_id, contrato, filas, origen)
                      select p_carga, n.contrato, coalesce((select jsonb_agg(to_jsonb(s)) from public.cartera_suscripcion s where s.contrato = n.contrato), '[]'::jsonb), 'archivo'
                        from nuevos n
                    returning contrato)
      delete from public.cartera_suscripcion s using resp where s.contrato = resp.contrato;
      get diagnostics n2 = row_count;
      insert into public.cartera_suscripcion (contrato, estado, identificacion, nombre, correo, telefono, direccion, barrio, categoria, subcategoria, ciclo,
                                              facturas_pendientes, deuda_total, saldo_pendiente, saldo_a_favor, valor_reclamo, saldo_financiado,
                                              serial_medidor, codigo_reparto, ruta, periodo_carga)
        select p.contrato, p.estado, p.identificacion, p.nombre, p.correo, p.telefono, p.direccion, p.barrio, p.categoria, p.subcategoria, p.ciclo,
               p.facturas_pendientes, p.deuda_total, p.saldo_pendiente, p.saldo_a_favor, p.valor_reclamo, p.saldo_financiado,
               p.serial_medidor, p.codigo_reparto, p.ruta, to_char(c.fecha_dato, 'YYYYMMDD')
          from scrr.paso_cartera p where p.carga_id = p_carga and p.lote = p_lote and p.error is null order by p.fila;
      get diagnostics n3 = row_count;
      v_res := jsonb_build_object('lote', p_lote, 'historial', n1, 'suscripcion_filas_retiradas', n2, 'suscripcion_filas_nuevas', n3);
    elsif c.tipo = 'pagos' then
      select min(fecha_pago), max(fecha_pago) into v_min, v_max from scrr.paso_pagos where carga_id = p_carga and lote = p_lote and error is null;
      if v_min is not null and (to_regclass('scrr.pagos_contrato_' || to_char(v_min, 'YYYYMM')) is null or to_regclass('scrr.pagos_contrato_' || to_char(v_max, 'YYYYMM')) is null) then
        set local lock_timeout = '5s';
        perform scrr.f_preparar_pagos(v_min, v_max);
      end if;
      -- ordinal: cuántos pagos idénticos (contrato, fecha, monto) hay ANTES en el archivo, en todos los lotes, más uno
      insert into scrr.pagos_contrato (contrato, fecha_pago, monto, ordinal, carga_id)
        select q.contrato, q.fecha_pago, q.monto, q.ord::smallint, p_carga
          from (select p.lote, p.contrato, p.fecha_pago, p.monto, row_number() over (partition by p.contrato, p.fecha_pago, p.monto order by p.lote, p.fila) as ord
                  from scrr.paso_pagos p
                 where p.carga_id = p_carga and p.error is null
                   and (p.contrato, p.fecha_pago, p.monto) in (select x.contrato, x.fecha_pago, x.monto from scrr.paso_pagos x where x.carga_id = p_carga and x.lote = p_lote and x.error is null)) q
         where q.lote = p_lote and q.ord < 32000
        on conflict do nothing;
      get diagnostics n1 = row_count;
      select count(*) into v_tot from scrr.paso_pagos where carga_id = p_carga and lote = p_lote and error is null;
      v_res := jsonb_build_object('lote', p_lote, 'pagos_nuevos', n1, 'pagos_ya_existentes', v_tot - n1);
    else
      insert into scrr.actas (id, contrato, tipo_actividad_id, drastico, fecha_ejecucion, version, resultado, anomalia, acta_numero, observacion, hora_inicio, hora_fin,
                              lectura, medidor, marca_medidor, operario, origen, estado_original, carga_id, creado_por)
        select gen_random_uuid(), s.contrato, s.tipo_actividad_id, s.drastico, s.fecha_ejecucion, 1, case s.estado_original when 3 then 'efectiva' else 'inefectiva' end,
               s.anomalia, s.acta, s.observacion, s.hora_inicio, s.hora_fin, s.lectura, s.medidor, s.marca, s.operario, 'archivo', s.estado_original, p_carga, c.autor
          from (select distinct on (contrato, tipo_actividad_id, fecha_ejecucion) * from scrr.paso_actividades
                 where carga_id = p_carga and lote = p_lote and error is null order by contrato, tipo_actividad_id, fecha_ejecucion, fila) s
        on conflict do nothing;
      get diagnostics n1 = row_count;
      select count(*) into v_tot from scrr.paso_actividades where carga_id = p_carga and lote = p_lote and error is null;
      v_res := jsonb_build_object('lote', p_lote, 'actas_nuevas', n1, 'actas_ya_existentes', v_tot - n1);
    end if;
    insert into scrr.carga_eventos (carga_id, evento, lote, resumen, autor) values (p_carga, 'lote_aplicado', p_lote, v_res, v_email);
    return v_res || jsonb_build_object('repetido', false);
  end if;

  -- ======================= CIERRE =======================
  if (select count(*) from scrr.carga_eventos where carga_id = p_carga and evento = 'lote_aplicado') <> v_lotes then
    perform scrr.f_err('Faltan lotes por aplicar antes de cerrar la carga', '55000');
  end if;
  if c.tipo = 'cartera' then
    -- filas de salida del historial: con saldo en la foto vigente anterior y hoy sin saldo (valores reales del archivo si vino; 0 si ya no figura)
    select v.fecha_dato, v.id into v_prev from scrr.v_cargas_vigentes v where v.tipo = 'cartera' and v.fecha_dato < c.fecha_dato order by v.fecha_dato desc limit 1;
    if v_prev.id is not null then
      insert into scrr.cartera_historial (fecha_dato, version, contrato, en_cartera, marca, estado, categoria, ciclo, ruta, codigo_reparto, barrio_id,
                                          facturas_pendientes, facturas_vencidas, deuda_total, saldo_pendiente, saldo_a_favor, saldo_financiado, valor_reclamo, carga_id)
        select c.fecha_dato, c.version, h.contrato, false, h.marca, coalesce(s.estado, h.estado), coalesce(s.categoria, h.categoria), h.ciclo, coalesce(s.ruta, h.ruta),
               coalesce(s.codigo_reparto, h.codigo_reparto), h.barrio_id,
               coalesce(s.facturas_pendientes, 0), coalesce(s.facturas_vencidas, 0), coalesce(s.deuda_total, 0), coalesce(s.saldo_pendiente, 0), coalesce(s.saldo_a_favor, 0),
               coalesce(s.saldo_financiado, 0), coalesce(s.valor_reclamo, 0), p_carga
          from scrr.cartera_historial h
          left join lateral (select * from scrr.paso_cartera p where p.carga_id = p_carga and p.contrato = h.contrato::text and p.error is null order by p.saldo_pendiente desc limit 1) s on true
         where h.fecha_dato = v_prev.fecha_dato and h.carga_id = v_prev.id and h.en_cartera
           and not exists (select 1 from scrr.cartera_historial n where n.fecha_dato = c.fecha_dato and n.version = c.version and n.contrato = h.contrato);
      get diagnostics n1 = row_count;
    end if;
    -- contratos de cartera_suscripcion que no vinieron en el archivo (ni con error): se retiran con respaldo. Guardia contra un archivo incompleto.
    select count(distinct s.contrato) into n2 from public.cartera_suscripcion s
     where s.contrato is not null
       and not exists (select 1 from scrr.suscripcion_respaldo r where r.carga_id = p_carga and r.contrato = s.contrato)
       and not exists (select 1 from scrr.paso_cartera p where p.carga_id = p_carga and p.contrato = s.contrato);
    select count(*) into v_tot from public.cartera_suscripcion;
    v_tope := (scrr.f_param('tope_salidas_suscripcion_pct'))::numeric;
    if n2 > 0 and n2 * 100.0 > v_tope * greatest(v_tot, 1) and not coalesce(p_confirmar_salidas, false) then
      perform scrr.f_err(format('%s contratos de la cartera de hoy no vienen en el archivo (más del %s %%). Revise que el archivo esté completo; si es correcto, confírmelo con un motivo.',
                                n2, v_tope), '55000');
    end if;
    if n2 > 0 and coalesce(p_confirmar_salidas, false) and length(btrim(coalesce(p_motivo, ''))) not between 10 and 300 then
      perform scrr.f_err('Confirmar las salidas exige un motivo de 10 a 300 caracteres');
    end if;
    with sal as (select distinct s.contrato from public.cartera_suscripcion s
                  where s.contrato is not null
                    and not exists (select 1 from scrr.suscripcion_respaldo r where r.carga_id = p_carga and r.contrato = s.contrato)
                    and not exists (select 1 from scrr.paso_cartera p where p.carga_id = p_carga and p.contrato = s.contrato)),
         resp as (insert into scrr.suscripcion_respaldo (carga_id, contrato, filas, origen)
                    select p_carga, sal.contrato, (select jsonb_agg(to_jsonb(s)) from public.cartera_suscripcion s where s.contrato = sal.contrato), 'salida' from sal
                  returning contrato)
    delete from public.cartera_suscripcion s using resp where s.contrato = resp.contrato;
    get diagnostics n3 = row_count;
    v_res := jsonb_build_object('filas_de_salida_historial', n1, 'suscripcion_contratos_salientes', n2, 'suscripcion_filas_retiradas', n3,
                                'historial', (select coalesce(sum((e.resumen->>'historial')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'),
                                'suscripcion_filas_nuevas', (select coalesce(sum((e.resumen->>'suscripcion_filas_nuevas')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'),
                                'salidas_confirmadas', n2 > 0 and coalesce(p_confirmar_salidas, false));
  elsif c.tipo = 'pagos' then
    v_res := jsonb_build_object('pagos_nuevos', (select coalesce(sum((e.resumen->>'pagos_nuevos')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'),
                                'pagos_ya_existentes', (select coalesce(sum((e.resumen->>'pagos_ya_existentes')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'));
  else
    v_res := jsonb_build_object('actas_nuevas', (select coalesce(sum((e.resumen->>'actas_nuevas')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'),
                                'actas_ya_existentes', (select coalesce(sum((e.resumen->>'actas_ya_existentes')::bigint), 0) from scrr.carga_eventos e where e.carga_id = p_carga and e.evento = 'lote_aplicado'));
  end if;
  v_res := v_res || jsonb_build_object('rechazadas', v_val->'filas_rechazadas');
  if c.reemplaza_id is not null then
    insert into scrr.carga_eventos (carga_id, evento, resumen, motivo, autor)
      select c.reemplaza_id, 'reemplazada', jsonb_build_object('reemplazada_por', p_carga), (select motivo from scrr.carga_eventos where carga_id = p_carga and evento = 'iniciada'), v_email;
  end if;
  insert into scrr.carga_eventos (carga_id, evento, resumen, motivo, autor)
    values (p_carga, 'aplicada', v_res, case when n2 > 0 and coalesce(p_confirmar_salidas, false) then btrim(p_motivo) end, v_email);
  perform scrr.f_auditar(v_email, 'scrr_carga_aplicar', p_carga::text, jsonb_build_object('tipo', c.tipo, 'fecha_dato', c.fecha_dato) || v_res, p_ip);
  return jsonb_build_object('ok', true, 'tipo', c.tipo, 'fecha_dato', c.fecha_dato, 'resultado', v_res);
end $$;

-- Revertir cartera_suscripcion a como estaba antes de una carga de cartera (hasta 5.000 contratos por llamada; se repite hasta pendientes = 0).
-- Solo la última carga de cartera que la tocó y mientras su respaldo exista (7 días).
create function public.geoportal_scrr_suscripcion_revertir(p_solicitante text, p_carga uuid, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas; n1 bigint; n2 bigint; v_pend bigint;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found or c.tipo <> 'cartera' then perform scrr.f_err('La carga de cartera no existe', 'P0002'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 300 then perform scrr.f_err('Revertir exige un motivo de 10 a 300 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_aplicar:cartera', 0));
  if not exists (select 1 from scrr.suscripcion_respaldo where carga_id = p_carga) then
    perform scrr.f_err('Esa carga no tiene respaldo de la cartera (no tocó la tabla o ya pasaron los 7 días)', '55000'); end if;
  if exists (select 1 from scrr.cargas c2 where c2.tipo = 'cartera' and c2.creado_en > c.creado_en
               and exists (select 1 from scrr.suscripcion_respaldo r where r.carga_id = c2.id and r.revertido_en is null)) then
    perform scrr.f_err('Hay una carga de cartera posterior que también cambió la tabla: revierta primero esa', '55000'); end if;
  with lote as (select r.contrato, r.filas from scrr.suscripcion_respaldo r where r.carga_id = p_carga and r.revertido_en is null order by r.contrato limit 5000),
       quitar as (delete from public.cartera_suscripcion s using lote where s.contrato = lote.contrato returning 1)
  select count(*) into n1 from quitar;
  insert into public.cartera_suscripcion
    select x.* from scrr.suscripcion_respaldo r
      cross join lateral jsonb_populate_recordset(null::public.cartera_suscripcion, r.filas) x
     where r.carga_id = p_carga and r.revertido_en is null
       and r.contrato in (select r2.contrato from scrr.suscripcion_respaldo r2 where r2.carga_id = p_carga and r2.revertido_en is null order by r2.contrato limit 5000);
  get diagnostics n2 = row_count;
  update scrr.suscripcion_respaldo r set revertido_en = clock_timestamp()
   where r.carga_id = p_carga and r.revertido_en is null
     and r.contrato in (select r2.contrato from scrr.suscripcion_respaldo r2 where r2.carga_id = p_carga and r2.revertido_en is null order by r2.contrato limit 5000);
  select count(*) into v_pend from scrr.suscripcion_respaldo where carga_id = p_carga and revertido_en is null;
  if v_pend = 0 then
    insert into scrr.carga_eventos (carga_id, evento, motivo, resumen, autor) values (p_carga, 'suscripcion_revertida', btrim(p_motivo), '{}'::jsonb, v_email);
  end if;
  perform scrr.f_auditar(v_email, 'scrr_suscripcion_revertir', p_carga::text, jsonb_build_object('filas_quitadas', n1, 'filas_restauradas', n2, 'pendientes', v_pend), p_ip);
  return jsonb_build_object('filas_quitadas', n1, 'filas_restauradas', n2, 'pendientes', v_pend);
end $$;

-- Anular (con motivo). Cartera aplicada o a medias: solo después de revertir cartera_suscripcion (su historial queda oculto, nunca borrado). Si la carga
-- anulada había reemplazado a otra, esa vuelve a quedar vigente.
-- Pagos y actividades aplicados acumulan y no se anulan: se corrigen con una carga posterior.
create function public.geoportal_scrr_carga_anular(p_solicitante text, p_carga uuid, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas; v_est text;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found then perform scrr.f_err('La carga no existe', 'P0002'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 300 then perform scrr.f_err('Anular exige un motivo de 10 a 300 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_aplicar:' || c.tipo, 0));
  v_est := scrr.f_estado_carga(p_carga);
  if v_est in ('rechazada','reemplazada','anulada') then perform scrr.f_err(format('La carga ya está %s', v_est), '55000'); end if;
  if v_est in ('aplicada','aplicando') and c.tipo <> 'cartera' then
    perform scrr.f_err('Las cargas de pagos y de actividades acumulan y no se anulan: se corrigen con una carga posterior', '55000'); end if;
  if c.tipo = 'cartera' and exists (select 1 from scrr.suscripcion_respaldo where carga_id = p_carga and revertido_en is null) then
    perform scrr.f_err('Esta carga ya cambió la cartera de suscripción: revierta primero la tabla y después anule', '55000'); end if;
  if c.tipo = 'cartera' and v_est in ('aplicada','aplicando') and not exists (select 1 from scrr.suscripcion_respaldo where carga_id = p_carga) then
    perform scrr.f_err('Ya no hay respaldo para revertir la cartera de suscripción de esta carga: corríjala con una carga nueva', '55000'); end if;
  insert into scrr.carga_eventos (carga_id, evento, motivo, resumen, autor) values (p_carga, 'anulada', btrim(p_motivo), jsonb_build_object('estado_previo', v_est), v_email);
  -- si esta carga había reemplazado a otra, la reemplazada vuelve a quedar vigente (evento nuevo; nada se borra)
  if v_est = 'aplicada' and c.reemplaza_id is not null then
    insert into scrr.carga_eventos (carga_id, evento, resumen, autor)
      values (c.reemplaza_id, 'aplicada', jsonb_build_object('vigente_de_nuevo_por_anulacion_de', p_carga), v_email);
  end if;
  perform scrr.f_auditar(v_email, 'scrr_carga_anular', p_carga::text, jsonb_build_object('tipo', c.tipo, 'estado_previo', v_est), p_ip);
  return jsonb_build_object('ok', true, 'estado', 'anulada');
end $$;

create function public.geoportal_scrr_carga_estado(p_solicitante text, p_carga uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found then perform scrr.f_err('La carga no existe', 'P0002'); end if;
  return jsonb_build_object('carga_id', c.id, 'tipo', c.tipo, 'fecha_dato', c.fecha_dato, 'version', c.version, 'archivo', c.archivo_nombre, 'filas', c.filas_leidas,
    'estado', scrr.f_estado_carga(c.id),
    'lotes_recibidos', (select coalesce(jsonb_agg(lote order by lote), '[]'::jsonb) from scrr.carga_eventos where carga_id = c.id and evento = 'lote_recibido'),
    'lotes_aplicados', (select coalesce(jsonb_agg(lote order by lote), '[]'::jsonb) from scrr.carga_eventos where carga_id = c.id and evento = 'lote_aplicado'),
    'resumen', (select resumen from scrr.carga_eventos where carga_id = c.id and evento in ('validada','aplicada') order by id desc limit 1),
    'respaldo_pendiente', (select count(*) from scrr.suscripcion_respaldo where carga_id = c.id and revertido_en is null),
    'creada_en', c.creado_en);
end $$;

-- ¿Falta cargar hoy? (hora de Bogotá). Cartera: la foto de hoy; pagos y actividades: hasta ayer.
create function public.geoportal_scrr_cargas_hoy(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  return jsonb_build_object('hoy', v_hoy, 'tipos', (
    select jsonb_agg(jsonb_build_object('tipo', t.tipo, 'ultima_fecha_dato', u.fecha_dato, 'aplicada_en', u.aplicada_en, 'requerida_desde', t.requerida,
             'al_dia', coalesce(u.fecha_dato >= t.requerida, false),
             'abierta', (select c.id from scrr.cargas c where c.tipo = t.tipo and scrr.f_estado_carga(c.id) in ('en_paso','validada','aplicando') order by c.creado_en desc limit 1)) order by t.ord)
      from (values (1, 'cartera', v_hoy), (2, 'pagos', v_hoy - 1), (3, 'actividades', v_hoy - 1)) as t(ord, tipo, requerida)
      left join lateral (select c.fecha_dato, (select max(e.creado_en) from scrr.carga_eventos e where e.carga_id = c.id and e.evento = 'aplicada') as aplicada_en
                           from scrr.v_cargas_vigentes c where c.tipo = t.tipo order by c.fecha_dato desc limit 1) u on true));
end $$;

create function public.geoportal_scrr_cargas_lista(p_solicitante text, p_limite integer default 30, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante);
begin
  return jsonb_build_object('cargas', (select coalesce(jsonb_agg(x order by (x->>'creada_en') desc), '[]'::jsonb) from (
     select jsonb_build_object('carga_id', c.id, 'tipo', c.tipo, 'fecha_dato', c.fecha_dato, 'version', c.version, 'archivo', c.archivo_nombre, 'filas', c.filas_leidas,
                               'estado', scrr.f_estado_carga(c.id), 'creada_en', c.creado_en, 'autor', c.autor) x
       from scrr.cargas c order by c.creado_en desc limit greatest(1, least(coalesce(p_limite, 30), 100))) q));
end $$;

-- Vaciado de la copia técnica (paso y respaldo) de las cargas con más de paso_dias días (lo corre el supervisor o el administrador; deja un evento por carga)
create function public.geoportal_scrr_vaciar_paso(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); r jsonb;
begin
  r := scrr.f_vaciar_paso((scrr.f_param('paso_dias'))::int);
  perform scrr.f_auditar(v_email, 'scrr_paso_vaciar', null, r, p_ip);
  return r;
end $$;
