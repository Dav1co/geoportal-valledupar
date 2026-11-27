-- [Code A] ETIQUETA DEL ÚLTIMO PAGO (27-nov) · MIGRACIÓN (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
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

commit;
