-- =====================================================================
-- SCRR · CORTE 2 · 20 — cargas del día, tablas de paso, historial de cartera, pagos, actas y respaldo de cartera_suscripcion
-- Tablas de hechos de solo inserción; el estado de una carga se deriva de carga_eventos.
-- Historial de cartera en particiones DIARIAS (se guardan 10 días: P7 del 22-nov); pagos en particiones MENSUALES (13 meses: decisión 3 del 20-nov).
-- Las tablas de paso de cartera y el respaldo de cartera_suscripcion llevan datos personales (P4 del 22-nov: el cargador actualiza cartera_suscripcion
-- COMPLETA): son copia técnica y se vacían a los 7 días (scrr.f_vaciar_paso), igual que en la fase 0. El historial NO lleva datos personales.
-- =====================================================================

-- 1. Cargas: encabezado inmutable + eventos (estado derivado)
create table scrr.cargas (
  id               uuid        primary key,
  tipo             text        not null check (tipo in ('cartera','pagos','actividades')),
  fecha_dato       date        not null,
  version          smallint    not null default 1 check (version >= 1),   -- 1, 2, 3… por tipo y fecha del dato (las anuladas también ocupan su número)
  reemplaza_id     uuid        references scrr.cargas (id),            -- la carga vigente que esta reemplaza (con motivo)
  archivo_nombre   text        not null check (length(archivo_nombre) between 1 and 200),
  archivo_sha256   text        not null check (archivo_sha256 ~ '^[0-9a-f]{64}$'),
  filas_leidas     integer     not null check (filas_leidas between 1 and 1000000),
  autor            text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en        timestamptz not null default clock_timestamp(),
  unique (tipo, fecha_dato, version),
  constraint reemplazo_ck check (reemplaza_id is null or version > 1)
);
create table scrr.carga_eventos (
  id           bigint generated always as identity primary key,
  carga_id     uuid        not null references scrr.cargas (id),
  evento       text        not null check (evento in ('iniciada','lote_recibido','validada','lote_aplicado','aplicada','rechazada','reemplazada','anulada',
                                                       'paso_vaciado','suscripcion_revertida')),
  lote         integer,
  huella       text,
  resumen      jsonb       not null default '{}'::jsonb,
  motivo       text        check (motivo is null or length(btrim(motivo)) between 10 and 300),
  autor        text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en    timestamptz not null default clock_timestamp(),
  constraint lote_ck check ((evento in ('lote_recibido','lote_aplicado')) = (lote is not null)),
  constraint motivo_ck check (evento not in ('reemplazada','anulada','rechazada','suscripcion_revertida') or motivo is not null)
);
create index carga_eventos_carga_idx on scrr.carga_eventos (carga_id, id desc);
create unique index carga_eventos_lote_uk on scrr.carga_eventos (carga_id, lote) where evento = 'lote_recibido';
create unique index carga_eventos_lote_aplicado_uk on scrr.carga_eventos (carga_id, lote) where evento = 'lote_aplicado';
create unique index carga_eventos_vaciado_uk on scrr.carga_eventos (carga_id) where evento = 'paso_vaciado';

-- Estado derivado: en_paso | validada | aplicando | aplicada | rechazada | reemplazada | anulada | inexistente
create function scrr.f_estado_carga(p_carga uuid) returns text
language sql stable security definer set search_path = scrr as $$
  select coalesce((select case e.evento when 'iniciada' then 'en_paso' when 'lote_aplicado' then 'aplicando' else e.evento end
                     from scrr.carga_eventos e
                    where e.carga_id = p_carga and e.evento in ('iniciada','validada','lote_aplicado','aplicada','rechazada','reemplazada','anulada')
                    order by e.id desc limit 1), 'inexistente')
$$;
-- Cargas VIGENTES: la última decisión sobre la carga fue «aplicada» (no reemplazada, anulada ni rechazada)
create view scrr.v_cargas_vigentes as
  select c.* from scrr.cargas c
   where (select e.evento from scrr.carga_eventos e where e.carga_id = c.id and e.evento in ('aplicada','reemplazada','anulada','rechazada') order by e.id desc limit 1) = 'aplicada';

-- 2. Tablas de paso (copia técnica; llave (carga_id, lote, fila): reenviar un lote no duplica). Se vacían a los 7 días.
create table scrr.paso_cartera (
  carga_id uuid not null references scrr.cargas (id), lote integer not null, fila integer not null,
  contrato text, estado text, identificacion text, nombre text, correo text, telefono text, direccion text, barrio text, categoria text, subcategoria text,
  ciclo text, facturas_pendientes smallint, deuda_total numeric(14,2), saldo_pendiente numeric(14,2), saldo_a_favor numeric(14,2),
  valor_reclamo numeric(14,2), saldo_financiado numeric(14,2), serial_medidor text, codigo_reparto text, ruta text,
  error text,
  primary key (carga_id, lote, fila)
);
create index paso_cartera_contrato_idx on scrr.paso_cartera (carga_id, contrato);
create table scrr.paso_pagos (
  carga_id uuid not null references scrr.cargas (id), lote integer not null, fila integer not null,
  contrato bigint, fecha_pago date, monto numeric(14,2),
  error text,
  primary key (carga_id, lote, fila)
);
create table scrr.paso_actividades (
  carga_id uuid not null references scrr.cargas (id), lote integer not null, fila integer not null,
  contrato bigint, acta text, actividad_texto text, tipo_actividad_id smallint, drastico boolean, estado_original smallint, anomalia smallint,
  observacion text, fecha_ejecucion date, hora_inicio time, hora_fin time, lectura integer, medidor text, marca text, operario text,
  error text,
  primary key (carga_id, lote, fila)
);

-- 3. Barrios normalizados y historial diario de cartera (solo contratos con saldo pendiente + fila de salida). SIN datos personales.
create table scrr.barrios (
  id          smallint generated always as identity primary key,
  nombre_norm text not null unique check (nombre_norm = upper(nombre_norm) and length(nombre_norm) between 1 and 80),
  creado_en   timestamptz not null default clock_timestamp()
);
create table scrr.cartera_historial (
  fecha_dato          date          not null,
  version             smallint      not null default 1,
  contrato            bigint        not null,
  en_cartera          boolean       not null default true,    -- false = fila de salida (con saldo en la foto anterior y hoy no)
  marca               smallint      not null default 0,       -- 0 normal; 1 comodín (contrato 99999999 o categoría «-1 …»). Sin corporativos (decisión 5 del 20-nov)
  estado              text,
  categoria           text,
  ciclo               smallint,
  ruta                text,
  codigo_reparto      text,
  barrio_id           smallint,
  facturas_pendientes smallint      not null default 0,
  facturas_vencidas   smallint      not null default 0,       -- decisión 2 del 20-nov; las DERIVA el motor al aplicar (scrr.f_vencidas, 22-nov)
  deuda_total         numeric(14,2) not null default 0,
  saldo_pendiente     numeric(14,2) not null default 0,
  saldo_a_favor       numeric(14,2) not null default 0,
  saldo_financiado    numeric(14,2) not null default 0,
  valor_reclamo       numeric(14,2) not null default 0,
  carga_id            uuid          not null,
  primary key (fecha_dato, version, contrato)
) partition by range (fecha_dato);
create view scrr.v_cartera_vigente as
  select h.* from scrr.cartera_historial h join scrr.v_cargas_vigentes v on v.id = h.carga_id;

-- 4. Pagos del día (plantilla PROVISIONAL de 3 columnas: decisión 7 del 22-nov). Llave contra duplicados al recargar: contrato + fecha + monto + ordinal.
--    Fácil de ampliar: las columnas del archivo real entran como columnas nuevas nulas, sin cambiar la llave.
create table scrr.pagos_contrato (
  contrato   bigint        not null,
  fecha_pago date          not null,
  monto      numeric(14,2) not null,
  ordinal    smallint      not null default 1,     -- 1 para el primer pago idéntico del archivo, 2 para el segundo, etc.
  carga_id   uuid          not null,
  primary key (contrato, fecha_pago, monto, ordinal)
) partition by range (fecha_pago);

-- 5. Actas del archivo de actividades (decisión 10 del 20-nov; marca de drástico en Corte). Acumulables; repetida = se ignora con conteo.
create table scrr.actas (
  id                uuid        primary key,
  contrato          bigint      not null check (contrato > 0),
  tipo_actividad_id smallint    not null references scrr.tipos_actividad (id),
  drastico          boolean     not null default false,
  fecha_ejecucion   date        not null,
  version           smallint    not null default 1 check (version >= 1),
  resultado         text        not null check (resultado in ('efectiva','inefectiva')),
  anomalia          smallint    references scrr.anomalias (codigo),
  acta_numero       text,
  observacion       text        check (observacion is null or length(observacion) <= 300),
  hora_inicio       time,
  hora_fin          time,
  lectura           integer     check (lectura is null or lectura >= 0),
  medidor           text,
  marca_medidor     text,
  operario          text,
  origen            text        not null check (origen in ('archivo','campo')),
  estado_original   smallint,
  reporte_campo_id  uuid,
  carga_id          uuid        references scrr.cargas (id),
  creado_en         timestamptz not null default clock_timestamp(),
  creado_por        text        not null check (creado_por = lower(creado_por) and position('@' in creado_por) > 1),
  unique (contrato, tipo_actividad_id, fecha_ejecucion, version),
  constraint inefectiva_con_anomalia_ck check (resultado = 'efectiva' or anomalia is not null),
  constraint drastico_solo_corte_ck check (not drastico or tipo_actividad_id = 2),
  constraint origen_ck check ((origen = 'archivo' and carga_id is not null) or (origen = 'campo' and reporte_campo_id is not null))
);
create index actas_contrato_idx on scrr.actas (contrato, fecha_ejecucion desc);
create table scrr.acta_eventos (
  id bigint generated always as identity primary key,
  acta_id uuid not null references scrr.actas (id),
  tipo_evento text not null check (tipo_evento in ('ocultar','reincluir')),
  motivo text not null check (length(btrim(motivo)) between 10 and 300),
  autor text not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en timestamptz not null default clock_timestamp()
);
create index acta_eventos_idx on scrr.acta_eventos (acta_id, id desc);
create view scrr.v_actas_vigentes as
  select a.* from scrr.actas a
   where not exists (select 1 from scrr.actas b where b.contrato = a.contrato and b.tipo_actividad_id = a.tipo_actividad_id and b.fecha_ejecucion = a.fecha_ejecucion and b.version > a.version)
     and coalesce((select e.tipo_evento from scrr.acta_eventos e where e.acta_id = a.id order by e.id desc limit 1), 'reincluir') <> 'ocultar';
-- Estado del servicio derivado: la última acta efectiva que cambia el estado. Corte con marca de drástico → «cortado_drastico» (el retorno lo distingue).
create view scrr.v_estado_servicio as
  select distinct on (a.contrato) a.contrato,
         case when t.estado_resultante = 'cortado' and a.drastico then 'cortado_drastico' else t.estado_resultante end as estado,
         a.fecha_ejecucion as desde, a.tipo_actividad_id, a.id as acta_id
    from scrr.v_actas_vigentes a join scrr.tipos_actividad t on t.id = a.tipo_actividad_id
   where a.resultado = 'efectiva' and t.estado_resultante is not null
   order by a.contrato, a.fecha_ejecucion desc, a.creado_en desc;

-- 6. Respaldo de public.cartera_suscripcion por carga (P4 del 22-nov): antes de reemplazar las filas de un contrato se guardan las que había
--    (lista vacía = el contrato no existía). Sirve para revertir la carga. Copia técnica con datos personales: se vacía con el paso (7 días).
create table scrr.suscripcion_respaldo (
  carga_id      uuid        not null references scrr.cargas (id),
  contrato      text        not null,
  filas         jsonb       not null check (jsonb_typeof(filas) = 'array'),
  origen        text        not null check (origen in ('archivo','salida')),   -- 'salida' = estaba en la tabla y no vino en el archivo
  revertido_en  timestamptz,
  primary key (carga_id, contrato)
);

-- 7. RLS y solo inserción
do $$
declare t text;
begin
  foreach t in array array['cargas','carga_eventos','paso_cartera','paso_pagos','paso_actividades','barrios','cartera_historial','pagos_contrato','actas','acta_eventos','suscripcion_respaldo'] loop
    execute format('alter table scrr.%I enable row level security', t);
  end loop;
  foreach t in array array['cargas','carga_eventos','actas','acta_eventos'] loop
    execute format('create trigger %I before update or delete on scrr.%I for each row execute function scrr.f_solo_insercion()', t || '_solo_insercion', t);
  end loop;
end $$;
-- Historial y pagos: solo inserción también en cada partición (el disparador del padre se hereda en las particiones)
create trigger cartera_historial_solo_insercion before update or delete on scrr.cartera_historial for each row execute function scrr.f_solo_insercion();
create trigger pagos_contrato_solo_insercion before update or delete on scrr.pagos_contrato for each row execute function scrr.f_solo_insercion();

-- 8. Particiones. Se crean de antemano (migración: historial 45 días hacia adelante; pagos 13 meses atrás y 2 adelante). Si al aplicar una carga falta la
--    del día (pasaron más de 45 días sin retiro), la crea con un tope de bloqueo de 5 s. No borra nada.
create function scrr.f_preparar_historial(p_desde date, p_hasta date) returns integer
language plpgsql security definer set search_path = pg_catalog, scrr as $$
declare d date; v_nom text; n integer := 0;
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 120 then raise exception 'Rango de particiones del historial no válido'; end if;
  for d in select generate_series(p_desde, p_hasta, interval '1 day')::date loop
    v_nom := 'cartera_historial_' || to_char(d, 'YYYYMMDD');
    if to_regclass('scrr.' || v_nom) is null then
      execute format('create table scrr.%I partition of scrr.cartera_historial for values from (%L) to (%L)', v_nom, d, d + 1);
      execute format('alter table scrr.%I enable row level security', v_nom);
      execute format('revoke all on scrr.%I from public, anon, authenticated, service_role', v_nom);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
create function scrr.f_preparar_pagos(p_desde date, p_hasta date) returns integer
language plpgsql security definer set search_path = pg_catalog, scrr as $$
declare m date; v_nom text; n integer := 0;
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 800 then raise exception 'Rango de particiones de pagos no válido'; end if;
  for m in select generate_series(date_trunc('month', p_desde)::date, date_trunc('month', p_hasta)::date, interval '1 month')::date loop
    v_nom := 'pagos_contrato_' || to_char(m, 'YYYYMM');
    if to_regclass('scrr.' || v_nom) is null then
      execute format('create table scrr.%I partition of scrr.pagos_contrato for values from (%L) to (%L)', v_nom, m, (m + interval '1 month')::date);
      execute format('alter table scrr.%I enable row level security', v_nom);
      execute format('revoke all on scrr.%I from public, anon, authenticated, service_role', v_nom);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- 9. Vaciado de la copia técnica (tablas de paso y respaldo de cartera_suscripcion) a los N días de la última actividad de la carga.
--    POR QUÉ se borra: son copia técnica del archivo (con datos personales en cartera), no un dato de registro; queda un evento «paso_vaciado» por carga con
--    los conteos y la huella SHA-256 del archivo (decisión de David en la fase 0). ALCANCE: solo scrr.paso_cartera, scrr.paso_pagos, scrr.paso_actividades y
--    scrr.suscripcion_respaldo, y solo las filas de las cargas vencidas (where carga_id = …). Después de vaciar el respaldo, esa carga ya no se puede revertir.
create function scrr.f_vaciar_paso(p_dias integer) returns jsonb
language plpgsql security definer set search_path = pg_catalog, scrr as $$
declare r record; n1 bigint; n2 bigint; n3 bigint; n4 bigint; v_cargas integer := 0; v_filas bigint := 0;
begin
  if p_dias is null or p_dias < 1 then raise exception 'Días no válidos'; end if;
  for r in
    select c.id, c.archivo_sha256,
           (select max(e.creado_en) from scrr.carga_eventos e where e.carga_id = c.id and e.evento <> 'paso_vaciado') as ultimo
      from scrr.cargas c
     where not exists (select 1 from scrr.carga_eventos e where e.carga_id = c.id and e.evento = 'paso_vaciado')
  loop
    continue when r.ultimo > clock_timestamp() - make_interval(days => p_dias);
    delete from scrr.paso_cartera where carga_id = r.id;          get diagnostics n1 = row_count;
    delete from scrr.paso_pagos where carga_id = r.id;            get diagnostics n2 = row_count;
    delete from scrr.paso_actividades where carga_id = r.id;      get diagnostics n3 = row_count;
    delete from scrr.suscripcion_respaldo where carga_id = r.id;  get diagnostics n4 = row_count;
    insert into scrr.carga_eventos (carga_id, evento, resumen, autor)
      values (r.id, 'paso_vaciado', jsonb_build_object('filas_paso', n1 + n2 + n3, 'filas_respaldo', n4, 'huella_archivo', r.archivo_sha256,
                                                       'decision', scrr.f_estado_carga(r.id), 'dias', p_dias), 'sistema@emdupar.gov.co');
    v_cargas := v_cargas + 1; v_filas := v_filas + n1 + n2 + n3 + n4;
  end loop;
  return jsonb_build_object('cargas', v_cargas, 'filas', v_filas);
end $$;

-- 10. Retiro del historial diario y de los pagos viejos (P7 del 22-nov). NO CORRE SOLA: ninguna RPC la llama y solo la ejecuta el dueño (David, desde el editor).
--     POR QUÉ: el historial diario de cartera se guarda 10 días (la ventana de facturación); el cierre de cada mes sigue en hechos.cartera_contrato. Los pagos
--     se guardan 13 meses (decisión 3 del 20-nov). Sin retiro, un año de fotos diarias son ~2,7 GB (tope del SCRR: 500 MB el primer año).
--     ALCANCE EXACTO de cada DROP: una partición diaria scrr.cartera_historial_AAAAMMDD cuyo día es anterior a (hoy − ventana_dias_historial), o una partición
--     mensual scrr.pagos_contrato_AAAAMM cuyo mes termina antes de (hoy − retencion_meses_pagos). Primero se separa (detach) y luego se borra; cada una
--     queda en public.geoportal_auditoria con su nombre, sus filas y el motivo. Nada más se borra. Al final prepara las particiones de los próximos 45 días.
create function scrr.f_retirar_historial(p_autor text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, scrr as $$
declare r record; v_hoy date := (now() at time zone 'America/Bogota')::date; v_lim_h date; v_lim_p date; v_n bigint; v_res jsonb := '[]'::jsonb;
        v_autor text := lower(btrim(coalesce(p_autor, '')));
begin
  if position('@' in v_autor) < 2 then raise exception 'Indique el correo de quien retira'; end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 300 then raise exception 'Escriba un motivo de 10 a 300 caracteres'; end if;
  v_lim_h := v_hoy - (scrr.f_param('ventana_dias_historial'))::int;
  v_lim_p := (date_trunc('month', v_hoy) - make_interval(months => (scrr.f_param('retencion_meses_pagos'))::int))::date;
  for r in
    select c.relname, (regexp_match(pg_get_expr(c.relpartbound, c.oid), 'TO \(''([0-9-]+)''\)'))[1]::date as hasta, case when i.inhparent = 'scrr.cartera_historial'::regclass then 'scrr.cartera_historial' else 'scrr.pagos_contrato' end as padre
      from pg_inherits i join pg_class c on c.oid = i.inhrelid
     where i.inhparent in ('scrr.cartera_historial'::regclass, 'scrr.pagos_contrato'::regclass)
     order by c.relname
  loop
    continue when not ((r.padre = 'scrr.cartera_historial' and r.hasta <= v_lim_h) or (r.padre = 'scrr.pagos_contrato' and r.hasta <= v_lim_p));
    execute format('select count(*) from scrr.%I', r.relname) into v_n;
    execute format('alter table %s detach partition scrr.%I', r.padre, r.relname);
    execute format('drop table scrr.%I', r.relname);
    perform scrr.f_auditar(v_autor, 'scrr_retiro_particion', r.relname, jsonb_build_object('filas', v_n, 'hasta', r.hasta, 'motivo', btrim(p_motivo)), null);
    v_res := v_res || jsonb_build_object('particion', r.relname, 'filas', v_n);
  end loop;
  perform scrr.f_preparar_historial(v_hoy, v_hoy + 45);
  perform scrr.f_preparar_pagos(v_hoy, (v_hoy + interval '2 months')::date);
  return jsonb_build_object('retiradas', v_res, 'limite_historial', v_lim_h, 'limite_pagos', v_lim_p);
end $$;
