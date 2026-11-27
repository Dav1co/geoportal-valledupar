-- [Code A] ETIQUETA DEL ÚLTIMO PAGO (27-nov) · ENSAYO (termina en ERROR esperado; no deja nada) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- ETIQUETA DEL ÚLTIMO PAGO (Code A, 27-nov) · 70 — ENSAYO: datos de prueba y respuestas de ANTES → MIGRACIÓN → pruebas → REVERSA → pruebas; termina en el
-- ERROR esperado (todo se deshace). Datos propios con prefijo ZTPAG (correos ztpag.*@emdupar.gov.co; contratos de 12 dígitos 9918000001NN, que se comprueba
-- que no existen). Las filas de prueba de cartera_suscripcion y bi_interno.ficha_contrato también se deshacen. Las RPC corren como service_role con los topes
-- de producción. Cinco perfiles: administrador, supervisor de Comercial, operador de campo (sin Análisis), dual (campo y Análisis) y sin permisos.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztpag_res (n serial, nombre text, ok boolean, detalle text);
create temp table ztpag_val (k text primary key, v text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztpag_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
create function pg_temp.guardar(p_k text, p_v text) returns void language sql as $f$ insert into ztpag_val values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.val(p_k text) returns text language sql as $f$ select v from ztpag_val where k = p_k $f$;
-- llama una RPC como service_role; devuelve su jsonb o {"error": sqlstate, "msg": mensaje}
create function pg_temp.rpc(q text) returns jsonb language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  begin
    execute 'set local role service_role';
    execute 'select (' || q || ')::jsonb' into r;
    execute 'reset role';
    return coalesce(r, 'null'::jsonb);
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    return jsonb_build_object('error', e, 'msg', m);
  end;
end $f$;
create function pg_temp.err(r jsonb) returns text language sql as $f$ select coalesce(r ->> 'error', 'OK') $f$;
create function pg_temp.consultar(p_quien text, p_contrato text) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_analisis_contrato(%L, %L, null)', p_quien, p_contrato)) $f$;
-- huella de campo SIN la función que cambia (para comprobar que no cambió nada más)
create function pg_temp.huella_resto() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text collate "C", p.proname, p.oid::regprocedure::text collate "C")) from pg_proc p
   where (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))
     and p.oid <> to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)') $f$;
-- lo que cada perfil recibe por cada contrato de prueba (respuesta completa) → ztpag_val 'r:<perfil>:<contrato>'
create function pg_temp.foto(p_pref text) returns void language plpgsql as $f$
declare u text; c text;
begin
  foreach u in array array['admin', 'sup', 'op', 'dual', 'sin'] loop
    foreach c in array array['991800000101', '991800000102', '991800000103', '991800000199'] loop
      perform pg_temp.guardar(p_pref || ':' || u || ':' || c, pg_temp.consultar('ztpag.' || u || '@emdupar.gov.co', c)::text);
    end loop;
  end loop;
end $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico, ver_analisis_contrato) values
  ('ztpag.admin@emdupar.gov.co', 'ZTPAG Administrador', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('ztpag.sup@emdupar.gov.co', 'ZTPAG Supervisor', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('ztpag.op@emdupar.gov.co', 'ZTPAG Operario sin Análisis', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztpag.dual@emdupar.gov.co', 'ZTPAG Dual campo y Análisis', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, true),
  ('ztpag.sin@emdupar.gov.co', 'ZTPAG Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false);

-- ===================== 00. Datos de prueba y lo de ANTES de la migración =====================
do $p0$
declare r jsonb; v_meses jsonb;
begin
  perform pg_temp.ok('00.01 los contratos de prueba no existen (cartera, censo, ficha)',
    not exists (select 1 from public.cartera_suscripcion where contrato like '9918000001__') and not exists (select 1 from public.catastro_valledupar where cod_usuario like '9918000001__')
    and not exists (select 1 from bi_interno.ficha_contrato where contrato like '9918000001__'));
  -- la ficha a la que se le escribe tiene las restricciones de producción (las 4 que crea el paquete de Análisis de contrato) y ningún disparador
  perform pg_temp.ok('00.02 bi_interno.ficha_contrato: llave, 3 CHECK y sin disparadores',
    (select string_agg(conname, ',' order by conname) from pg_constraint where conrelid = 'bi_interno.ficha_contrato'::regclass)
      = 'ficha_contrato_consumo_meses_check,ficha_contrato_medidor_fecha_estado_check,ficha_contrato_periodo_ultimo_check,ficha_contrato_pkey'
    and not exists (select 1 from pg_trigger where tgrelid = 'bi_interno.ficha_contrato'::regclass and not tgisinternal));
  select jsonb_agg(jsonb_build_object('periodo', p, 'sin_dato', false, 'm3', 10 + k, 'metodo', 'lectura', 'lectura_real', true, 'causal', '99 LECTURA NORMAL') order by k) into v_meses
    from unnest(array['202604', '202605', '202606', '202607', '202608', '202609']) with ordinality u(p, k);
  -- 101: pago por cupones (corte 202610) · 102: pago de la cartera mensual (corte 202609) · 103: sin pago · 199: no existe
  insert into public.cartera_suscripcion (contrato, estado, nombre, telefono, direccion, barrio, deuda_total, periodo_carga) values
    ('991800000101', 'ACTIVO', 'ZTPAG PERSONA UNO', '3001112233', 'CRA 9 # 12-30', 'CENTRO', 45000, '20261123'),
    ('991800000102', 'ACTIVO', 'ZTPAG PERSONA DOS', '3002223344', 'CLL 5 # 3-10', 'LOS MAYALES', 0, '20261123'),
    ('991800000103', 'ACTIVO', 'ZTPAG PERSONA TRES', null, 'MZ 4 CASA 7', 'PRIMERO DE MAYO', 0, '20261123');
  insert into bi_interno.ficha_contrato (contrato, periodo_ultimo, uso, estrato, consumo_meses, meses_con_lectura, medidor_fecha_estado, ultimo_pago) values
    ('991800000101', '202609', 'Residencial', 'Estrato 2', v_meses, 6, 'sin_dato', jsonb_build_object('fecha', date '2026-10-20', 'valor', 45000, 'fuente', 'cupones', 'corte', '202610')),
    ('991800000102', '202609', 'Residencial', 'Estrato 2', v_meses, 6, 'sin_dato', jsonb_build_object('fecha', date '2026-09-03', 'valor', 30000.5, 'fuente', 'cartera', 'corte', '202609')),
    ('991800000103', '202609', 'Residencial', 'Estrato 2', v_meses, 6, 'sin_dato', null);
  perform pg_temp.guardar('huella_resto', pg_temp.huella_resto());
  perform pg_temp.foto('antes');
  r := pg_temp.val('antes:dual:991800000101')::jsonb;
  perform pg_temp.ok('00.03 antes: el pago (cupones) llega sin «corte»', pg_temp.err(r) = 'OK' and r -> 'pago' ->> 'fuente' = 'cupones' and not (r -> 'pago' ? 'corte'), left(r::text, 300));
  r := pg_temp.val('antes:dual:991800000102')::jsonb;
  perform pg_temp.ok('00.04 antes: el pago (cartera) llega sin «corte»; sin pago llega null',
    r -> 'pago' ->> 'fuente' = 'cartera' and not (r -> 'pago' ? 'corte') and jsonb_typeof(pg_temp.val('antes:dual:991800000103')::jsonb -> 'pago') = 'null', left(r::text, 300));
end $p0$;

-- ===================== MIGRACIÓN (guardia incluida) =====================
-- =====================================================================
-- ETIQUETA DEL ÚLTIMO PAGO (Code A, 27-nov) · 05 — GUARDIA: se detiene sin cambiar nada si la base no es la publicada
-- Huella de campo c476f14d495ea7bdf6c3f42101e9a583 (Consultar direcciones publicado), ordenada con collate "C"; md5 de la función que se reemplaza; la línea que cambia está
-- una sola vez; la ficha guarda ultimo_pago como jsonb.
-- =====================================================================
do $guardia$
declare v text;
begin
  select (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text collate "C", p.proname, p.oid::regprocedure::text collate "C")) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) into v;
  if v = '9f8b8ec55fc7e1c56fdf74a5f4e7f3c4' then
    raise exception 'Este paquete ya parece aplicado (la huella de campo es la de este cambio): use la reversa antes de repetir';
  end if;
  if coalesce(v, '(ninguna)') is distinct from 'c476f14d495ea7bdf6c3f42101e9a583' then
    raise exception 'Las funciones de campo no son las publicadas (huella c476f14d495ea7bdf6c3f42101e9a583; hay %): deténgase y avise', v;
  end if;
  if to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)') is null or md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)'))) is distinct from '6ed039f4949ca17daeae67b0a9e249d7' then
    raise exception 'La función public.geoportal_campo_analisis_contrato(text,text,text) no es la publicada: deténgase y avise';
  end if;
  if (select count(*) from regexp_matches(pg_get_functiondef(to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)')), 'f\.ultimo_pago - ''corte'' \|\|', 'g')) <> 1 then
    raise exception 'La línea del pago no está una sola vez en public.geoportal_campo_analisis_contrato(text,text,text): deténgase y avise';
  end if;
  if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass('bi_interno.ficha_contrato') and a.attname = 'ultimo_pago' and not a.attisdropped and a.atttypid = 'jsonb'::regtype) then
    raise exception 'bi_interno.ficha_contrato.ultimo_pago no existe o no es jsonb: deténgase y avise';
  end if;
end $guardia$;

-- =====================================================================
-- ETIQUETA DEL ÚLTIMO PAGO (Code A, 27-nov; aprobado por David) · 30 — CAMBIO
-- geoportal_campo_analisis_contrato deja de quitar el «corte» del pago: la respuesta lleva pago.corte (periodo AAAAMM de la fuente: hechos.cupones_pagos
-- si fuente = cupones, hechos.cartera_contrato si fuente = cartera), para que la pantalla diga «pagos a oct-2026» o «cartera mensual a sep-2026».
-- Única diferencia con la publicada:  f.ultimo_pago - 'corte' || jsonb_build_object(...)  →  f.ultimo_pago || jsonb_build_object(...)
-- CREATE OR REPLACE conserva el dueño y los permisos (solo service_role); la verificación lo comprueba.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.geoportal_campo_analisis_contrato(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'bi', 'bi_interno', 'pg_temp'
AS $function$
declare
  v_email   text;
  v_c       text := btrim(coalesce(p_contrato, ''));
  v_existe  boolean;
  v_id      bigint;
  cs        record;
  pr        record;
  f         bi_interno.ficha_contrato%rowtype;
  v_ficha   boolean;
  v_estado  record;
  v_tel     text[];
  v_tel_f   text;
  v_barrio  text;
  v_meses   text[];
  v_hoy     date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_predios jsonb;
  v_n_pred  integer;
  v_prom    jsonb;
begin
  v_email := campo.f_autorizar_analisis(p_solicitante);
  if v_c !~ '^\d{1,12}$' then
    raise exception 'Escriba solo los números del contrato (hasta 12 dígitos).' using errcode = '22023', hint = 'msg_usuario';
  end if;
  -- SIN límite diario (decisión de David, 14/11): cada consulta queda en la bitácora (quién, cuándo, qué contrato), sin tope.

  -- ¿existe? (todo por índice: cartera_suscripcion.contrato, catastro_valledupar.cod_usuario, clave de la ficha)
  select s.* into cs from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select count(*) into v_n_pred from public.catastro_valledupar c where c.cod_usuario = v_c;
  select * into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  v_ficha := found;
  v_existe := cs.contrato is not null or v_n_pred > 0 or v_ficha;

  insert into campo.consultas_analisis (autor, contrato, existe, ip) values (v_email, v_c, v_existe, left(p_ip, 64)) returning id into v_id;
  perform campo.f_auditar(v_email, 'campo_analisis_contrato', v_id::text, jsonb_build_object('existe', v_existe), p_ip);   -- el contrato queda en la bitácora, no en la auditoría (decisión 15)

  if v_c = '99999999' then
    return jsonb_build_object('encontrado', true, 'comodin', true, 'contrato', v_c);
  end if;
  if not v_existe then
    return jsonb_build_object('encontrado', false, 'contrato', v_c);
  end if;

  -- predio principal (menor id) y hasta 5 predios con coordenadas (decisión 20)
  select c.id, c.direccion, c.barrio, c.diam_med, c.telefono, c.telefono_propie, p.estado_predio, p.tramo_mora,
         c.unih, c.uninh, c.clase_uso, c.act_eco into pr   -- Consultar direcciones (25-nov): datos del predio en el censo
    from public.catastro_valledupar c left join public.predios_comercial p on p.id = c.id
   where c.cod_usuario = v_c order by c.id limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('direccion', nullif(btrim(x.direccion), ''), 'barrio', nullif(btrim(x.barrio), ''),
                                               'lat', round(st_y(x.geom)::numeric, 6), 'lon', round(st_x(x.geom)::numeric, 6)) order by x.id), '[]'::jsonb)
    into v_predios
    from (select c.id, c.direccion, c.barrio, c.geom from public.catastro_valledupar c where c.cod_usuario = v_c order by c.id limit 5) x;

  -- teléfonos: los de la cartera diaria; si no hay, los del censo con su rótulo (decisión 11)
  v_tel := campo.f_telefonos(cs.telefono);
  v_tel_f := case when cardinality(v_tel) > 0 then 'cartera' end;
  if cardinality(v_tel) = 0 and pr.id is not null then
    v_tel := campo.f_telefonos(concat_ws(' / ', pr.telefono, pr.telefono_propie));
    v_tel_f := case when cardinality(v_tel) > 0 then 'censo' end;
  end if;

  select * into v_estado from bi_interno.ficha_contrato_estado where id = 1;
  v_barrio := nullif(upper(btrim(coalesce(cs.barrio, ''))), '');

  -- promedios de su estrato, barrio y uso en los mismos 6 meses (null en el mes si el grupo no llega a 30 o falta el mes)
  if v_ficha then
    select array_agg(m ->> 'periodo' order by k) into v_meses from jsonb_array_elements(f.consumo_meses) with ordinality t(m, k);
    select jsonb_object_agg(d.dimension, case when d.grupo is null then null else jsonb_build_object('grupo', d.grupo, 'meses',
             (select jsonb_agg(jsonb_build_object('periodo', mp, 'media', pd.media_m3, 'contratos', pd.contratos) order by mk)
                from unnest(v_meses) with ordinality u(mp, mk)
                left join bi.v_consumo_promedio_dim pd on pd.periodo = u.mp and pd.dimension = d.dimension and pd.grupo = d.grupo)) end)
      into v_prom
      from (values ('estrato', nullif(f.estrato, '(sin dato)')), ('barrio', v_barrio), ('uso', nullif(f.uso, '(sin dato)'))) d(dimension, grupo);
  end if;

  return jsonb_build_object(
    'encontrado', true, 'comodin', false, 'contrato', v_c,
    'suscriptor', jsonb_build_object('nombre', nullif(btrim(cs.nombre), ''), 'telefonos', to_jsonb(coalesce(v_tel, '{}'::text[])), 'telefono_fuente', v_tel_f, 'corte', cs.periodo_carga),
    'comercial', jsonb_build_object(
       'estado', nullif(btrim(cs.estado), ''), 'categoria', nullif(btrim(cs.categoria), ''), 'subcategoria', nullif(btrim(cs.subcategoria), ''),
       'ciclo', nullif(btrim(cs.ciclo), ''), 'ruta', nullif(btrim(cs.ruta), ''),
       'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), '')), 'direccion', coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')),
       'deuda_total', cs.deuda_total, 'saldo_pendiente', cs.saldo_pendiente, 'facturas_pendientes', cs.facturas_pendientes, 'saldo_financiado', cs.saldo_financiado,
       'valor_reclamo', cs.valor_reclamo, 'saldo_a_favor', cs.saldo_a_favor,
       'tramo_mora', pr.tramo_mora, 'estado_predio', nullif(btrim(pr.estado_predio), ''), 'facturas_vencidas', f.facturas_vencidas, 'corte', cs.periodo_carga),
    'medidor', jsonb_build_object(
       'serial', coalesce(case when v_ficha then f.medidor_serial end, nullif(upper(btrim(cs.serial_medidor)), '')),
       'diametro', nullif(btrim(pr.diam_med::text), ''),
       'fecha_instalacion', f.medidor_fecha, 'fecha_estado', coalesce(f.medidor_fecha_estado, 'sin_dato'), 'anios', f.medidor_anios,
       'cambio', coalesce(f.cambio, jsonb_build_object('confirmado', null, 'recodificado', null))),
    'consumo', case when v_ficha then jsonb_build_object('periodo_ultimo', f.periodo_ultimo, 'meses', f.consumo_meses, 'maximo', f.cons_max, 'minimo', f.cons_min,
                                                         'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura) end,
    'promedios', coalesce(v_prom, jsonb_build_object('estrato', null, 'barrio', null, 'uso', null)),
    'submedicion', f.submedicion,
    'pago', case when f.ultimo_pago is not null then f.ultimo_pago || jsonb_build_object('dias', v_hoy - (f.ultimo_pago ->> 'fecha')::date) end,
    'gestiones', jsonb_build_object(
       'emd_facturados', coalesce(f.emd, '[]'::jsonb),
       'terreno', coalesce((select jsonb_agg(jsonb_build_object('tipo', x.codigo, 'tipo_nombre', x.nombre, 'consecutivo', x.consecutivo, 'fecha', x.registrado_en, 'estado', x.estado) order by x.registrado_en desc)
                              from (select distinct on (t.codigo) t.codigo, t.nombre, r.consecutivo, r.registrado_en, r.estado
                                      from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                     where r.contrato = v_c and not r.oculto and t.codigo in ('suspension', 'corte', 'reconexion_servicio', 'reinstalacion', 'verificacion_posterior')
                                     order by t.codigo, r.registrado_en desc) x), '[]'::jsonb),
       'pqr', f.pqr,
       'reportes', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', x.consecutivo, 'tipo', x.codigo, 'tipo_nombre', x.nombre, 'fecha', x.registrado_en, 'estado', x.estado, 'resultado', x.resultado) order by x.registrado_en desc)
                               from (select t.codigo, t.nombre, r.consecutivo, r.registrado_en, r.estado, r.resultado
                                       from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                      where r.contrato = v_c and not r.oculto order by r.registrado_en desc limit 15) x), '[]'::jsonb),
       'reportes_total', (select count(*) from campo.reportes r where r.contrato = v_c),
       'actas', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', a.consecutivo, 'fecha', a.fecha_acta_fisica, 'registrado_en', a.registrado_en) order by a.registrado_en desc)
                            from (select a.consecutivo, a.fecha_acta_fisica, a.registrado_en from acta.v_actas_vigentes a where a.contrato = v_c order by a.registrado_en desc limit 10) a), '[]'::jsonb),
       -- actividades derivadas pendientes (decisión 19, provisional): revisiones con «¿Se requiere cambio de medidor?» = sí y sin instalación posterior
       'pendientes', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', r.consecutivo, 'tipo_nombre', t.nombre, 'fecha', r.registrado_en, 'sugiere', 'cambio_medidor') order by r.registrado_en desc)
                                 from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                where r.contrato = v_c and not r.oculto and t.codigo in ('revision_previa', 'revision_pqr') and r.datos -> 'req_cambio_medidor' = 'true'::jsonb
                                  and r.estado not in ('descartado', 'duplicado')
                                  and not exists (select 1 from campo.reportes i join campo.tipos_reporte ti on ti.id = i.tipo_id
                                                   where i.contrato = v_c and ti.codigo = 'instalacion_medidor' and i.registrado_en > r.registrado_en)), '[]'::jsonb)),
    'ubicacion', jsonb_build_object('predios_total', v_n_pred, 'predios', v_predios),
    -- Consultar direcciones (25-nov, David): las dos direcciones POR SEPARADO (sin coalesce) y los datos del predio principal en el censo, con limpieza mínima
    'direcciones', jsonb_build_object(
       'comercial', case when cs.contrato is not null then jsonb_build_object('direccion', campo.f_texto_censo(cs.direccion), 'barrio', campo.f_texto_censo(cs.barrio), 'corte', cs.periodo_carga) end,
       'catastro', case when pr.id is not null then jsonb_build_object('direccion', campo.f_texto_censo(pr.direccion), 'barrio', campo.f_texto_censo(pr.barrio)) end),
    'predio', case when pr.id is not null then jsonb_build_object('unih', campo.f_texto_censo(pr.unih), 'uninh', campo.f_texto_censo(pr.uninh),
       'clase_uso', campo.f_texto_censo(pr.clase_uso, true), 'act_eco', campo.f_texto_censo(pr.act_eco), 'predios_total', v_n_pred) end,
    'fotos', '[]'::jsonb,
    'cortes', jsonb_build_object('cartera', cs.periodo_carga, 'consumo', f.periodo_ultimo, 'ficha', v_estado.calculado_en),
    'ficha_disponible', v_estado.id is not null);
end $function$;


-- ===================== 01. Funciones y permisos =====================
do $p1$
begin
  perform pg_temp.ok('01.01 la huella de campo es la de este cambio', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text collate "C", p.proname, p.oid::regprocedure::text collate "C")) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) = '9f8b8ec55fc7e1c56fdf74a5f4e7f3c4');
  perform pg_temp.ok('01.02 la función nueva tiene su md5 y el resto de campo no cambió',
    md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)'))) = '81d0967ea34e183d397f0ff846332a32' and pg_temp.huella_resto() = pg_temp.val('huella_resto'));
  perform pg_temp.ok('01.03 la huella del acta y la de Técnica no cambiaron', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '111506c690249ad3b56ebf572566434c' and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))) = '838b80984e51cc7873a666f85d657195');
  perform pg_temp.ok('01.04 la RPC sigue solo para service_role (ni anon ni authenticated) y SECURITY DEFINER',
    has_function_privilege('service_role', 'public.geoportal_campo_analisis_contrato(text,text,text)', 'execute') and not has_function_privilege('anon', 'public.geoportal_campo_analisis_contrato(text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.geoportal_campo_analisis_contrato(text,text,text)', 'execute') and (select prosecdef from pg_proc where oid = to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)')));
  perform pg_temp.ok('01.05 la línea quedó sin «- ''corte''» y no quedan otras',
    position('f.ultimo_pago - ''corte''' in pg_get_functiondef(to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)'))) = 0
    and position('f.ultimo_pago || jsonb_build_object(''dias''' in pg_get_functiondef(to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)'))) > 0);
end $p1$;

-- ===================== 02. La respuesta =====================
do $p2$
declare r jsonb; a jsonb; u text; c text; v_dif text := ''; t0 timestamptz; v_ms numeric;
        v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
begin
  t0 := clock_timestamp();
  perform pg_temp.foto('despues');
  v_ms := extract(epoch from clock_timestamp() - t0) * 1000 / 20;
  r := pg_temp.val('despues:dual:991800000101')::jsonb;
  perform pg_temp.ok('02.01 cupones: pago.corte = 202610 y lo demás del pago igual (fecha, valor, fuente, días)',
    r -> 'pago' ->> 'corte' = '202610' and r -> 'pago' ->> 'fuente' = 'cupones' and r -> 'pago' ->> 'fecha' = '2026-10-20'
    and (r -> 'pago' ->> 'valor')::numeric = 45000 and (r -> 'pago' ->> 'dias')::int = v_hoy - date '2026-10-20', (r -> 'pago')::text);
  r := pg_temp.val('despues:dual:991800000102')::jsonb;
  perform pg_temp.ok('02.02 cartera mensual: pago.corte = 202609 (no el periodo del consumo ni el de cupones)',
    r -> 'pago' ->> 'corte' = '202609' and r -> 'pago' ->> 'fuente' = 'cartera' and (r -> 'pago' ->> 'valor')::numeric = 30000.5, (r -> 'pago')::text);
  perform pg_temp.ok('02.03 las claves del pago son exactamente fecha, valor, fuente, corte y días',
    (select string_agg(k, ',' order by k) from jsonb_object_keys(r -> 'pago') k) = 'corte,dias,fecha,fuente,valor', (r -> 'pago')::text);
  perform pg_temp.ok('02.04 sin pago: sigue null', jsonb_typeof(pg_temp.val('despues:dual:991800000103')::jsonb -> 'pago') = 'null');
  -- los 5 perfiles × 4 contratos: todo lo demás de la respuesta igual que antes; el pago, igual salvo «corte»
  foreach u in array array['admin', 'sup', 'op', 'dual', 'sin'] loop
    foreach c in array array['991800000101', '991800000102', '991800000103', '991800000199'] loop
      a := pg_temp.val('antes:' || u || ':' || c)::jsonb; r := pg_temp.val('despues:' || u || ':' || c)::jsonb;
      if (a - 'pago') is distinct from (r - 'pago') or (a -> 'pago') is distinct from (case when jsonb_typeof(r -> 'pago') = 'object' then (r -> 'pago') - 'corte' else r -> 'pago' end) then
        v_dif := v_dif || u || ':' || c || ' ';
      end if;
    end loop;
  end loop;
  perform pg_temp.ok('02.05 5 perfiles × 4 contratos: la respuesta es la de antes salvo pago.corte', v_dif = '', v_dif);
  perform pg_temp.ok('02.06 los perfiles sin Análisis siguen sin acceso (operador y sin permisos: mismo error que antes)',
    pg_temp.err(pg_temp.val('despues:op:991800000101')::jsonb) <> 'OK' and pg_temp.err(pg_temp.val('despues:sin:991800000101')::jsonb) <> 'OK'
    and pg_temp.err(pg_temp.val('despues:op:991800000101')::jsonb) = pg_temp.err(pg_temp.val('antes:op:991800000101')::jsonb),
    pg_temp.val('despues:op:991800000101'));
  perform pg_temp.ok('02.07 el contrato que no existe responde igual que antes',
    pg_temp.val('despues:dual:991800000199')::jsonb = pg_temp.val('antes:dual:991800000199')::jsonb, pg_temp.val('despues:dual:991800000199'));
  perform pg_temp.ok('02.08 una consulta tarda menos de 1 s como service_role (con 30 s de tope)', v_ms < 1000, round(v_ms, 1)::text || ' ms');
end $p2$;

-- ===================== 03. Reglas de producción =====================
do $p3$
begin
  perform pg_temp.ok('03.01 ninguna función de campo con DELETE o UPDATE sin WHERE', (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0);
  perform pg_temp.ok('03.02 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
end $p3$;

-- ===================== REVERSA =====================
-- =====================================================================
-- ETIQUETA DEL ÚLTIMO PAGO (Code A, 27-nov) · 90 — REVERSA
-- Devuelve geoportal_campo_analisis_contrato a su texto publicado (md5 6ed039f4949ca17daeae67b0a9e249d7); la huella de campo vuelve a c476f14d495ea7bdf6c3f42101e9a583. No toca tablas ni datos.
-- Con la Edge y la pantalla de este paquete, sin el campo la pantalla vuelve a mostrar el periodo del consumo.
-- =====================================================================
do $rev$
begin
  if to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)') is null or md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)'))) is distinct from '81d0967ea34e183d397f0ff846332a32' then
    raise exception 'La función public.geoportal_campo_analisis_contrato(text,text,text) no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise';
  end if;
end $rev$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_analisis_contrato(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'bi', 'bi_interno', 'pg_temp'
AS $function$
declare
  v_email   text;
  v_c       text := btrim(coalesce(p_contrato, ''));
  v_existe  boolean;
  v_id      bigint;
  cs        record;
  pr        record;
  f         bi_interno.ficha_contrato%rowtype;
  v_ficha   boolean;
  v_estado  record;
  v_tel     text[];
  v_tel_f   text;
  v_barrio  text;
  v_meses   text[];
  v_hoy     date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_predios jsonb;
  v_n_pred  integer;
  v_prom    jsonb;
begin
  v_email := campo.f_autorizar_analisis(p_solicitante);
  if v_c !~ '^\d{1,12}$' then
    raise exception 'Escriba solo los números del contrato (hasta 12 dígitos).' using errcode = '22023', hint = 'msg_usuario';
  end if;
  -- SIN límite diario (decisión de David, 14/11): cada consulta queda en la bitácora (quién, cuándo, qué contrato), sin tope.

  -- ¿existe? (todo por índice: cartera_suscripcion.contrato, catastro_valledupar.cod_usuario, clave de la ficha)
  select s.* into cs from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select count(*) into v_n_pred from public.catastro_valledupar c where c.cod_usuario = v_c;
  select * into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  v_ficha := found;
  v_existe := cs.contrato is not null or v_n_pred > 0 or v_ficha;

  insert into campo.consultas_analisis (autor, contrato, existe, ip) values (v_email, v_c, v_existe, left(p_ip, 64)) returning id into v_id;
  perform campo.f_auditar(v_email, 'campo_analisis_contrato', v_id::text, jsonb_build_object('existe', v_existe), p_ip);   -- el contrato queda en la bitácora, no en la auditoría (decisión 15)

  if v_c = '99999999' then
    return jsonb_build_object('encontrado', true, 'comodin', true, 'contrato', v_c);
  end if;
  if not v_existe then
    return jsonb_build_object('encontrado', false, 'contrato', v_c);
  end if;

  -- predio principal (menor id) y hasta 5 predios con coordenadas (decisión 20)
  select c.id, c.direccion, c.barrio, c.diam_med, c.telefono, c.telefono_propie, p.estado_predio, p.tramo_mora,
         c.unih, c.uninh, c.clase_uso, c.act_eco into pr   -- Consultar direcciones (25-nov): datos del predio en el censo
    from public.catastro_valledupar c left join public.predios_comercial p on p.id = c.id
   where c.cod_usuario = v_c order by c.id limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('direccion', nullif(btrim(x.direccion), ''), 'barrio', nullif(btrim(x.barrio), ''),
                                               'lat', round(st_y(x.geom)::numeric, 6), 'lon', round(st_x(x.geom)::numeric, 6)) order by x.id), '[]'::jsonb)
    into v_predios
    from (select c.id, c.direccion, c.barrio, c.geom from public.catastro_valledupar c where c.cod_usuario = v_c order by c.id limit 5) x;

  -- teléfonos: los de la cartera diaria; si no hay, los del censo con su rótulo (decisión 11)
  v_tel := campo.f_telefonos(cs.telefono);
  v_tel_f := case when cardinality(v_tel) > 0 then 'cartera' end;
  if cardinality(v_tel) = 0 and pr.id is not null then
    v_tel := campo.f_telefonos(concat_ws(' / ', pr.telefono, pr.telefono_propie));
    v_tel_f := case when cardinality(v_tel) > 0 then 'censo' end;
  end if;

  select * into v_estado from bi_interno.ficha_contrato_estado where id = 1;
  v_barrio := nullif(upper(btrim(coalesce(cs.barrio, ''))), '');

  -- promedios de su estrato, barrio y uso en los mismos 6 meses (null en el mes si el grupo no llega a 30 o falta el mes)
  if v_ficha then
    select array_agg(m ->> 'periodo' order by k) into v_meses from jsonb_array_elements(f.consumo_meses) with ordinality t(m, k);
    select jsonb_object_agg(d.dimension, case when d.grupo is null then null else jsonb_build_object('grupo', d.grupo, 'meses',
             (select jsonb_agg(jsonb_build_object('periodo', mp, 'media', pd.media_m3, 'contratos', pd.contratos) order by mk)
                from unnest(v_meses) with ordinality u(mp, mk)
                left join bi.v_consumo_promedio_dim pd on pd.periodo = u.mp and pd.dimension = d.dimension and pd.grupo = d.grupo)) end)
      into v_prom
      from (values ('estrato', nullif(f.estrato, '(sin dato)')), ('barrio', v_barrio), ('uso', nullif(f.uso, '(sin dato)'))) d(dimension, grupo);
  end if;

  return jsonb_build_object(
    'encontrado', true, 'comodin', false, 'contrato', v_c,
    'suscriptor', jsonb_build_object('nombre', nullif(btrim(cs.nombre), ''), 'telefonos', to_jsonb(coalesce(v_tel, '{}'::text[])), 'telefono_fuente', v_tel_f, 'corte', cs.periodo_carga),
    'comercial', jsonb_build_object(
       'estado', nullif(btrim(cs.estado), ''), 'categoria', nullif(btrim(cs.categoria), ''), 'subcategoria', nullif(btrim(cs.subcategoria), ''),
       'ciclo', nullif(btrim(cs.ciclo), ''), 'ruta', nullif(btrim(cs.ruta), ''),
       'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), '')), 'direccion', coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')),
       'deuda_total', cs.deuda_total, 'saldo_pendiente', cs.saldo_pendiente, 'facturas_pendientes', cs.facturas_pendientes, 'saldo_financiado', cs.saldo_financiado,
       'valor_reclamo', cs.valor_reclamo, 'saldo_a_favor', cs.saldo_a_favor,
       'tramo_mora', pr.tramo_mora, 'estado_predio', nullif(btrim(pr.estado_predio), ''), 'facturas_vencidas', f.facturas_vencidas, 'corte', cs.periodo_carga),
    'medidor', jsonb_build_object(
       'serial', coalesce(case when v_ficha then f.medidor_serial end, nullif(upper(btrim(cs.serial_medidor)), '')),
       'diametro', nullif(btrim(pr.diam_med::text), ''),
       'fecha_instalacion', f.medidor_fecha, 'fecha_estado', coalesce(f.medidor_fecha_estado, 'sin_dato'), 'anios', f.medidor_anios,
       'cambio', coalesce(f.cambio, jsonb_build_object('confirmado', null, 'recodificado', null))),
    'consumo', case when v_ficha then jsonb_build_object('periodo_ultimo', f.periodo_ultimo, 'meses', f.consumo_meses, 'maximo', f.cons_max, 'minimo', f.cons_min,
                                                         'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura) end,
    'promedios', coalesce(v_prom, jsonb_build_object('estrato', null, 'barrio', null, 'uso', null)),
    'submedicion', f.submedicion,
    'pago', case when f.ultimo_pago is not null then f.ultimo_pago - 'corte' || jsonb_build_object('dias', v_hoy - (f.ultimo_pago ->> 'fecha')::date) end,
    'gestiones', jsonb_build_object(
       'emd_facturados', coalesce(f.emd, '[]'::jsonb),
       'terreno', coalesce((select jsonb_agg(jsonb_build_object('tipo', x.codigo, 'tipo_nombre', x.nombre, 'consecutivo', x.consecutivo, 'fecha', x.registrado_en, 'estado', x.estado) order by x.registrado_en desc)
                              from (select distinct on (t.codigo) t.codigo, t.nombre, r.consecutivo, r.registrado_en, r.estado
                                      from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                     where r.contrato = v_c and not r.oculto and t.codigo in ('suspension', 'corte', 'reconexion_servicio', 'reinstalacion', 'verificacion_posterior')
                                     order by t.codigo, r.registrado_en desc) x), '[]'::jsonb),
       'pqr', f.pqr,
       'reportes', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', x.consecutivo, 'tipo', x.codigo, 'tipo_nombre', x.nombre, 'fecha', x.registrado_en, 'estado', x.estado, 'resultado', x.resultado) order by x.registrado_en desc)
                               from (select t.codigo, t.nombre, r.consecutivo, r.registrado_en, r.estado, r.resultado
                                       from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                      where r.contrato = v_c and not r.oculto order by r.registrado_en desc limit 15) x), '[]'::jsonb),
       'reportes_total', (select count(*) from campo.reportes r where r.contrato = v_c),
       'actas', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', a.consecutivo, 'fecha', a.fecha_acta_fisica, 'registrado_en', a.registrado_en) order by a.registrado_en desc)
                            from (select a.consecutivo, a.fecha_acta_fisica, a.registrado_en from acta.v_actas_vigentes a where a.contrato = v_c order by a.registrado_en desc limit 10) a), '[]'::jsonb),
       -- actividades derivadas pendientes (decisión 19, provisional): revisiones con «¿Se requiere cambio de medidor?» = sí y sin instalación posterior
       'pendientes', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', r.consecutivo, 'tipo_nombre', t.nombre, 'fecha', r.registrado_en, 'sugiere', 'cambio_medidor') order by r.registrado_en desc)
                                 from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                where r.contrato = v_c and not r.oculto and t.codigo in ('revision_previa', 'revision_pqr') and r.datos -> 'req_cambio_medidor' = 'true'::jsonb
                                  and r.estado not in ('descartado', 'duplicado')
                                  and not exists (select 1 from campo.reportes i join campo.tipos_reporte ti on ti.id = i.tipo_id
                                                   where i.contrato = v_c and ti.codigo = 'instalacion_medidor' and i.registrado_en > r.registrado_en)), '[]'::jsonb)),
    'ubicacion', jsonb_build_object('predios_total', v_n_pred, 'predios', v_predios),
    -- Consultar direcciones (25-nov, David): las dos direcciones POR SEPARADO (sin coalesce) y los datos del predio principal en el censo, con limpieza mínima
    'direcciones', jsonb_build_object(
       'comercial', case when cs.contrato is not null then jsonb_build_object('direccion', campo.f_texto_censo(cs.direccion), 'barrio', campo.f_texto_censo(cs.barrio), 'corte', cs.periodo_carga) end,
       'catastro', case when pr.id is not null then jsonb_build_object('direccion', campo.f_texto_censo(pr.direccion), 'barrio', campo.f_texto_censo(pr.barrio)) end),
    'predio', case when pr.id is not null then jsonb_build_object('unih', campo.f_texto_censo(pr.unih), 'uninh', campo.f_texto_censo(pr.uninh),
       'clase_uso', campo.f_texto_censo(pr.clase_uso, true), 'act_eco', campo.f_texto_censo(pr.act_eco), 'predios_total', v_n_pred) end,
    'fotos', '[]'::jsonb,
    'cortes', jsonb_build_object('cartera', cs.periodo_carga, 'consumo', f.periodo_ultimo, 'ficha', v_estado.calculado_en),
    'ficha_disponible', v_estado.id is not null);
end $function$;


-- ===================== 04. Después de la reversa =====================
do $p4$
declare r jsonb;
begin
  perform pg_temp.ok('04.01 la huella de campo vuelve a la publicada', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text collate "C", p.proname, p.oid::regprocedure::text collate "C")) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) = 'c476f14d495ea7bdf6c3f42101e9a583');
  perform pg_temp.ok('04.02 la función vuelve a su md5 publicado', md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_analisis_contrato(text,text,text)'))) = '6ed039f4949ca17daeae67b0a9e249d7');
  r := pg_temp.consultar('ztpag.dual@emdupar.gov.co', '991800000101');
  perform pg_temp.ok('04.03 la respuesta vuelve a ser la de antes (sin «corte»)', r = pg_temp.val('antes:dual:991800000101')::jsonb, left(r::text, 300));
  perform pg_temp.ok('04.04 la RPC sigue solo para service_role', has_function_privilege('service_role', 'public.geoportal_campo_analisis_contrato(text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.geoportal_campo_analisis_contrato(text,text,text)', 'execute') and not has_function_privilege('anon', 'public.geoportal_campo_analisis_contrato(text,text,text)', 'execute'));
end $p4$;

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztpag_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;

rollback;
