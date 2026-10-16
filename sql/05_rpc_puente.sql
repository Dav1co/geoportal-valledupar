-- =====================================================================
-- 05_rpc_puente.sql · ENTREGA 2 · RPC puente y blindaje de bi/bi_interno
-- ---------------------------------------------------------------------
-- NO ejecutar en la Entrega 1. Requiere 01_capa0, 02_capa1_resumen,
-- 03_v_kpi y 04_acceso ya aplicados.
--
-- ⚠ bi ES UN ESQUEMA COMPARTIDO. Además de las vistas del tablero
-- (archivos 01–08), contiene seis vistas PREEXISTENTES del geoportal,
-- todas en uso y algunas CON DATOS PERSONALES (p. ej.
-- bi.v_cartera_contrato trae identificación, nombre y dirección):
-- predios_comercial depende de v_cartera_geoportal y
-- v_causales_geoportal; geoportal_detalle_predio, geoportal_ruta,
-- geoportal_rutas_lista y geoportal_causales_lista usan las demás.
--
-- Por eso la protección NO es "bi no tiene PII", sino DOS CAPAS:
--   1. Blindaje de permisos: anon y authenticated no pueden leer bi.
--   2. La lista cerrada de este RPC, que autoriza VISTA POR VISTA.
--
-- REGLAS:
--   · NUNCA agregar una vista a la lista cerrada sin revisar sus
--     columnas. bi.v_cartera_contrato JAMÁS debe entrar.
--   · NO intentar "limpiar" bi: sus vistas sostienen el mapa en
--     producción. No se toca ninguna.
-- =====================================================================

-- ---------------------------------------------------------------------
-- RPC puente · public.geoportal_bi_consulta(p_vista, p_filtros)
-- Única puerta de entrada a los esquemas bi/bi_interno.
--   · Lista CERRADA de vistas: cada una es una rama estática del CASE.
--     Sin SQL dinámico: un valor no contemplado lanza excepción.
--   · SECURITY DEFINER con search_path fijo.
--   · Solo la invoca la Edge Function geoportal-bi (service_role), que
--     antes pasó por autorizar(req) + geoportal_puede(email,'dashboard').
-- Filtros admitidos por vista (claves opcionales de p_filtros):
--   v_kpi_mes               : periodo (exacto), desde, hasta (rango AAAAMM)
--   v_kpi_anio              : periodo (exacto)
--   v_facturacion_mes       : periodo (exacto), desde, hasta
--   v_facturacion_servicio  : periodo (exacto)
--   v_facturacion_ruta      : periodo (exacto)
--   v_tarifa_referencia     : periodo (exacto), desde, hasta
--   v_recaudo_mes           : periodo (exacto), desde, hasta
--   v_recaudo_servicio      : periodo (exacto)
--   v_recaudo_ruta          : periodo (exacto)
--   v_fact_vs_recaudo_servicio : periodo (exacto)
--   v_cartera_mes           : periodo (exacto), desde, hasta
--   v_cartera_tramo         : periodo (exacto)
--   v_cartera_servicio      : periodo (exacto)
--   v_cartera_ruta          : periodo (exacto)
--   v_recaudo_diario_cierre        : periodo (exacto) — curva diaria y acumulado
--   v_recaudo_detalle_dim   : periodo (exacto) — preagregado dia x concepto
--   v_concepto_mapa         : (ninguno) — mapa concepto -> ruta -> servicio
--   v_cartera_detalle_dim   : periodo (exacto) — preagregado territorial
--   v_cartera_contratos_dim : periodo (exacto) — contratos con deuda
--   v_periodos_fuente       : (ninguno) — mapa de huecos: que periodos
--                             tiene cada fuente. Base del estandar de huecos.
--   v_consolidado_mes       : (ninguno) — matriz mensual completa
--   v_consolidado_anio      : (ninguno) — tendencia por vigencia
--   v_cupones_mes           : periodo (exacto) — serie de cupones
--   v_cupones_canal         : periodo (exacto) — por entidad y agencia
--   v_notas_mes             : periodo (exacto) — serie de notas
--   v_notas_dim             : periodo (exacto) — preagregado de notas
--   v_notas_vs_pqr          : (ninguno) — cruce notas/reclamos (co-ocurrencia)
--   v_pqr_mes               : periodo (exacto) — serie de reclamos/recursos
--   v_pqr_dim               : periodo (exacto) — preagregado de PQR
--   v_fact_detalle_dim      : periodo (exacto) — preagregado del detalle;
--                             se trae completo y se filtra en el navegador
--   v_consumo_ciclo_dim     : periodo (exacto; sin él, el último con datos
--                             en esta tabla) — contratos por ciclo, medición
--                             y consumo cero (sql/26_consumo_ciclo_dim.sql)
--   v_desviacion_dim        : periodo (exacto; sin él, el último con datos
--                             en esta tabla) — contratos con desviación
--                             significativa, Res. CRA 943/2021 art. 1.13.1.6
--                             (sql/27_desviacion_dim.sql)
--   v_lectura_ciclo_dim     : periodo (exacto; sin él, el último con datos
--                             en esta tabla) — lectura efectiva y tiempos de
--                             lectura por ciclo (sql/28_lectura_ciclo_dim.sql)
--   v_observacion_dim       : ídem — observación de lectura por categoría,
--                             estrato y ciclo (sql/29_observacion_dim.sql)
--   v_medidor_antig_dim     : ídem — antigüedad del medidor por categoría y
--                             estrato, sin ciclo (sql/30_medidor_antig_dim.sql)
--   v_consumo_rango_dim     : ídem — contratos, m3 y facturado por rango de
--                             consumo (sql/31_consumo_rango_dim.sql)
--   v_consumo_basico_dim    : ídem — consumo básico, residencial estratos 1 a
--                             3 (sql/32_consumo_basico_dim.sql)
--   v_recaudo_eficiencia_dim: periodo (exacto), desde, hasta; sin ninguno, el ultimo
--                             con datos — recaudo frente a facturado por ciclo,
--                             uso y estrato (sql/33_recaudo_eficiencia_dim.sql)
--   v_recaudo_ritmo_dim     : ídem — recaudo diario acumulado del mes por fecha de
--                             grabacion (sql/34_recaudo_ritmo_dim.sql)
--   v_recaudo_edad_dim      : ídem — recaudo por edad de la deuda y servicio
--                             (sql/35_recaudo_edad_dim.sql)
--   v_notas_causal_dim      : ídem — notas por ciclo, categoria y causal
--                             (sql/36_notas_causal_dim.sql)
--   v_recaudo_entidad_dim   : ídem — recaudo por entidad y agencia
--                             (sql/37_recaudo_entidad_dim.sql)
--   v_cambio_medidor_dim    : periodo (exacto), desde, hasta; SIN filtro devuelve todos los
--                             periodos — cambios de medidor entre periodos consecutivos
--                             (sql/38_cambio_medidor_dim.sql)
--   v_submedicion_ref_dim   : periodo (exacto), desde, hasta; SIN filtro devuelve todos los
--   v_submedicion_ciclo_dim   periodos — submedicion por vejez del medidor: referencia por
--   v_submedicion_rango_dim   estrato y banda, sumas por ciclo y por rango de consumo
--                             (sql/39_submedicion_dim.sql)
--   v_reclamo_metodo_banda_dim: periodo (exacto), desde, hasta; SIN filtro devuelve todos los
--   v_reclamo_metodo_ciclo_dim  periodos — reclamos segun el metodo de facturacion: resumen sin
--                             ciclo y resumen por ciclo (sql/40 y sql/41)
--   v_mapa_calor_dim        : periodo (exacto), desde, hasta; SIN filtro devuelve todos los
--   v_mapa_calor_cobertura_dim  periodos — mapa de calor: celdas de 250 m publicadas por capa y
--                             su cobertura (sql/42_mapa_calor_dim.sql)
--   v_recaudo_diario        : periodo (exacto, sobre periodo_registro) —
--                             lotes de conciliacion bancaria del mes en curso
--   v_recaudo_diario_mes    : periodo (exacto), desde, hasta — serie diaria
--                             comparable entre meses al mismo dia de corte
--   v_ipuf                  : periodo (exacto), desde, hasta — serie
--                             historica de perdidas (IPUF), 114 periodos
-- ---------------------------------------------------------------------
create or replace function public.geoportal_bi_consulta(
  p_vista   text,
  p_filtros jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = bi, bi_interno, pg_temp
as $$
declare
  resultado jsonb;
begin
  p_filtros := coalesce(p_filtros, '{}'::jsonb);

  if p_vista = 'v_kpi_mes' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb)
      into resultado
    from bi.v_kpi_mes t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_kpi_anio' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb)
      into resultado
    from bi.v_kpi_anio t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_facturacion_mes' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb)
      into resultado
    from bi.v_facturacion_mes t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_facturacion_servicio' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.servicio), '[]'::jsonb)
      into resultado
    from bi.v_facturacion_servicio t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_facturacion_ruta' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.facturado desc), '[]'::jsonb)
      into resultado
    from bi.v_facturacion_ruta t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_tarifa_referencia' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.concepto_num), '[]'::jsonb)
      into resultado
    from bi.v_tarifa_referencia t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_recaudo_mes' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_mes t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_recaudo_servicio' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.servicio), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_servicio t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_recaudo_ruta' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.recaudo desc), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_ruta t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_fact_vs_recaudo_servicio' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.facturado desc), '[]'::jsonb)
      into resultado
    from bi.v_fact_vs_recaudo_servicio t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_cartera_mes' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb)
      into resultado
    from bi.v_cartera_mes t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_cartera_tramo' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.orden), '[]'::jsonb)
      into resultado
    from bi.v_cartera_tramo t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_cartera_servicio' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.servicio), '[]'::jsonb)
      into resultado
    from bi.v_cartera_servicio t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_cartera_ruta' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.cartera desc), '[]'::jsonb)
      into resultado
    from bi.v_cartera_ruta t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_fact_detalle_dim' then
    -- Preagregado del detalle: ~5.700 filas por período. La pantalla lo
    -- trae UNA vez y filtra en el navegador, así que el filtro por
    -- período es obligatorio (sin él serían los 6 períodos juntos).
    select coalesce(jsonb_agg(to_jsonb(t) order by t.ciclo, t.uso, t.subcategoria, t.concepto_num), '[]'::jsonb)
      into resultado
    from bi.v_fact_detalle_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select periodo from bi.v_ultimo_periodo));

  elsif p_vista = 'v_recaudo_diario_cierre' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.fecha), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_diario_cierre t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_recaudo_detalle_dim' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.fecha, t.concepto_num), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_detalle_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select periodo from bi.v_ultimo_periodo));

  elsif p_vista = 'v_concepto_mapa' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.concepto_num), '[]'::jsonb)
      into resultado
    from bi.v_concepto_mapa t;

  elsif p_vista = 'v_cartera_detalle_dim' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.barrio, t.ciclo, t.uso, t.subcategoria), '[]'::jsonb)
      into resultado
    from bi.v_cartera_detalle_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select periodo from bi.v_ultimo_periodo));

  elsif p_vista = 'v_consumo_ciclo_dim' then
    -- ~380 filas por período (ciclo x categoría x subcategoría x medidor). La
    -- pantalla lo trae UNA vez y filtra en el navegador. Sin período se usa el
    -- último con datos EN ESTA TABLA, no el último global: consumo_metodo puede
    -- ir un período atrás (p. ej. 202606 no existe).
    select coalesce(jsonb_agg(to_jsonb(t)
             order by length(t.ciclo), t.ciclo, t.categoria, t.subcategoria, t.con_medidor),
             '[]'::jsonb)
      into resultado
    from bi.v_consumo_ciclo_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select max(periodo) from bi.v_consumo_ciclo_dim));

  elsif p_vista = 'v_desviacion_dim' then
    -- ~1.000 filas por período (ciclo x categoría x subcategoría x tipo_desviacion
    -- x grupo_umbral). La pantalla lo trae UNA vez y agrega en el navegador. Sin
    -- período se usa el último con datos EN ESTA TABLA: los períodos sin 6
    -- anteriores no tienen filas (es lo correcto) y no deben dar una respuesta vacía.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by length(t.ciclo), t.ciclo, t.categoria, t.subcategoria,
                      t.tipo_desviacion, t.grupo_umbral),
             '[]'::jsonb)
      into resultado
    from bi.v_desviacion_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select max(periodo) from bi.v_desviacion_dim));

  elsif p_vista = 'v_lectura_ciclo_dim' then
    -- ~120-170 filas por período (ciclo x con_medidor x resultado_lectura x
    -- rango_dias). La pantalla lo trae UNA vez y agrega en el navegador. Sin
    -- período, el último con datos EN ESTA TABLA (consumo_metodo no tiene 202606).
    select coalesce(jsonb_agg(to_jsonb(t)
             order by length(t.ciclo), t.ciclo, t.con_medidor, t.resultado_lectura, t.rango_dias),
             '[]'::jsonb)
      into resultado
    from bi.v_lectura_ciclo_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select max(periodo) from bi.v_lectura_ciclo_dim));

  elsif p_vista = 'v_observacion_dim' then
    -- ~1.200-1.400 filas por período (categoría x subcategoría x ciclo x
    -- observación x con_medidor x resultado_lectura). Se trae UNA vez y se filtra
    -- (ciclo, uso, estrato) en el navegador.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by t.categoria, t.subcategoria, length(t.ciclo), t.ciclo,
                      t.codigo_observacion nulls first, t.observacion,
                      t.con_medidor, t.resultado_lectura),
             '[]'::jsonb)
      into resultado
    from bi.v_observacion_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select max(periodo) from bi.v_observacion_dim));

  elsif p_vista = 'v_medidor_antig_dim' then
    -- ~100-300 filas por período (categoría x subcategoría x banda_antiguedad x
    -- resultado_lectura), sin ciclo. 202601-202604 traen todo 'Sin fecha'.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by t.categoria, t.subcategoria, t.banda_antiguedad, t.resultado_lectura),
             '[]'::jsonb)
      into resultado
    from bi.v_medidor_antig_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select max(periodo) from bi.v_medidor_antig_dim));

  elsif p_vista = 'v_consumo_rango_dim' then
    -- ~1.400-1.550 filas por período (ciclo x categoría x subcategoría x
    -- con_medidor x rango_consumo). Se trae UNA vez y se filtra en el navegador.
    -- Sin período, el último con datos EN ESTA TABLA. Los rangos salen en orden de
    -- consumo, no alfabético.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by length(t.ciclo), t.ciclo, t.categoria, t.subcategoria, t.con_medidor,
                      case t.rango_consumo when '0' then 0 when '1-5' then 1 when '6-10' then 2
                        when '11-15' then 3 when '16-20' then 4 when '21-30' then 5
                        when '31-40' then 6 when '41-60' then 7 when '61-100' then 8
                        when '>100' then 9 else 10 end),
             '[]'::jsonb)
      into resultado
    from bi.v_consumo_rango_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select max(periodo) from bi.v_consumo_rango_dim));

  elsif p_vista = 'v_consumo_basico_dim' then
    -- ~120-140 filas por período (ciclo x subcategoría x con_medidor; solo
    -- Residencial estratos 1, 2 y 3).
    select coalesce(jsonb_agg(to_jsonb(t)
             order by length(t.ciclo), t.ciclo, t.categoria, t.subcategoria, t.con_medidor),
             '[]'::jsonb)
      into resultado
    from bi.v_consumo_basico_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select max(periodo) from bi.v_consumo_basico_dim));

  elsif p_vista = 'v_cartera_contratos_dim' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.ciclo, t.uso, t.estrato), '[]'::jsonb)
      into resultado
    from bi.v_cartera_contratos_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select periodo from bi.v_ultimo_periodo));

  elsif p_vista = 'v_periodos_fuente' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.fuente, t.periodo), '[]'::jsonb)
      into resultado
    from bi.v_periodos_fuente t;

  elsif p_vista = 'v_pqr_mes' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb)
      into resultado
    from bi.v_pqr_mes t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_pqr_dim' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.cantidad desc), '[]'::jsonb)
      into resultado
    from bi.v_pqr_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select periodo from bi.v_ultimo_periodo));

  elsif p_vista = 'v_notas_mes' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb) into resultado
    from bi.v_notas_mes t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_notas_dim' then
    select coalesce(jsonb_agg(to_jsonb(t) order by abs(t.valor) desc), '[]'::jsonb) into resultado
    from bi.v_notas_dim t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select periodo from bi.v_ultimo_periodo));

  elsif p_vista = 'v_notas_vs_pqr' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb) into resultado
    from bi.v_notas_vs_pqr t;

  elsif p_vista = 'v_cupones_mes' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb) into resultado
    from bi.v_cupones_mes t
    where (p_filtros ->> 'periodo' is null or t.periodo = p_filtros ->> 'periodo');

  elsif p_vista = 'v_cupones_canal' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.valor desc), '[]'::jsonb) into resultado
    from bi.v_cupones_canal t
    where t.periodo = coalesce(p_filtros ->> 'periodo',
                               (select periodo from bi.v_ultimo_periodo));

  elsif p_vista = 'v_consolidado_mes' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb) into resultado
    from bi.v_consolidado_mes t;

  elsif p_vista = 'v_consolidado_anio' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.anio), '[]'::jsonb) into resultado
    from bi.v_consolidado_anio t;

  -- ---- Recaudo diario: conciliaciones bancarias del mes en curso ----
  elsif p_vista = 'v_recaudo_diario' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.dia, t.entidad_recaudo), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_diario t
    where (p_filtros ->> 'periodo' is null or t.periodo_registro = p_filtros ->> 'periodo');

  -- ---- Serie diaria comparable entre meses (dia x mes) ----
  elsif p_vista = 'v_recaudo_diario_mes' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.dia), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_diario_mes t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  -- ---- Perdidas: serie historica completa del IPUF ----
  elsif p_vista = 'v_ipuf' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo), '[]'::jsonb)
      into resultado
    from bi.v_ipuf t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  -- Recaudo desagregada (sql/33 a 37)
  elsif p_vista = 'v_recaudo_eficiencia_dim' then
    -- Con periodo, desde o hasta se devuelven esos periodos; sin ninguno, el ultimo con
    -- datos EN ESTA TABLA.
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, length(t.ciclo), t.ciclo, t.categoria, t.subcategoria), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_eficiencia_dim t
    where case
            when p_filtros ->> 'periodo' is null and p_filtros ->> 'desde' is null
                 and p_filtros ->> 'hasta' is null
              then t.periodo = (select max(periodo) from bi.v_recaudo_eficiencia_dim)
            else (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
             and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
             and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta')
          end;

  elsif p_vista = 'v_recaudo_ritmo_dim' then
    -- Con periodo, desde o hasta se devuelven esos periodos; sin ninguno, el ultimo con
    -- datos EN ESTA TABLA.
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.dia), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_ritmo_dim t
    where case
            when p_filtros ->> 'periodo' is null and p_filtros ->> 'desde' is null
                 and p_filtros ->> 'hasta' is null
              then t.periodo = (select max(periodo) from bi.v_recaudo_ritmo_dim)
            else (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
             and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
             and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta')
          end;

  elsif p_vista = 'v_recaudo_edad_dim' then
    -- Con periodo, desde o hasta se devuelven esos periodos; sin ninguno, el ultimo con
    -- datos EN ESTA TABLA.
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.orden, t.servicio), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_edad_dim t
    where case
            when p_filtros ->> 'periodo' is null and p_filtros ->> 'desde' is null
                 and p_filtros ->> 'hasta' is null
              then t.periodo = (select max(periodo) from bi.v_recaudo_edad_dim)
            else (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
             and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
             and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta')
          end;

  elsif p_vista = 'v_notas_causal_dim' then
    -- Con periodo, desde o hasta se devuelven esos periodos; sin ninguno, el ultimo con
    -- datos EN ESTA TABLA.
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, length(t.ciclo), t.ciclo, t.categoria, t.causal), '[]'::jsonb)
      into resultado
    from bi.v_notas_causal_dim t
    where case
            when p_filtros ->> 'periodo' is null and p_filtros ->> 'desde' is null
                 and p_filtros ->> 'hasta' is null
              then t.periodo = (select max(periodo) from bi.v_notas_causal_dim)
            else (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
             and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
             and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta')
          end;

  elsif p_vista = 'v_recaudo_entidad_dim' then
    -- Con periodo, desde o hasta se devuelven esos periodos; sin ninguno, el ultimo con
    -- datos EN ESTA TABLA.
    select coalesce(jsonb_agg(to_jsonb(t) order by t.periodo, t.entidad, t.agencia, t.categoria), '[]'::jsonb)
      into resultado
    from bi.v_recaudo_entidad_dim t
    where case
            when p_filtros ->> 'periodo' is null and p_filtros ->> 'desde' is null
                 and p_filtros ->> 'hasta' is null
              then t.periodo = (select max(periodo) from bi.v_recaudo_entidad_dim)
            else (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
             and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
             and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta')
          end;

  elsif p_vista = 'v_cambio_medidor_dim' then
    -- Cambios de medidor entre periodos consecutivos (sql/38): ~530 a 2.000 filas por periodo, 7.502 en los 7
    -- periodos de hoy (~2 MB). Con periodo (exacto) devuelve solo ese periodo; SIN periodo devuelve TODOS (a
    -- diferencia de las otras dims, que sin periodo traen el ultimo): la serie por periodo es el uso de la vista.
    -- Tambien admite desde y hasta. Se trae una vez y se filtra en el navegador.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by t.periodo, length(t.ciclo), t.ciclo, t.uso, t.estrato, t.tipo_evento, t.banda_ant, t.metodo_act),
             '[]'::jsonb)
      into resultado
    from bi.v_cambio_medidor_dim t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_submedicion_ref_dim' then
    -- Submedicion por vejez del medidor (sql/39): referencia por estrato y banda de antiguedad, ~40 filas por periodo
    -- (159 en los 4 periodos de hoy). Con periodo (exacto), desde o hasta devuelve esos periodos; SIN filtro devuelve TODOS.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by t.periodo, t.estrato, case t.banda_antig when '0-3' then 1 when '3-5' then 2 when '5-10' then 3 when '10-15' then 4 when '>15 (fecha real)' then 5 when '>15 (1986-01-01)' then 6 else 7 end),
             '[]'::jsonb)
      into resultado
    from bi.v_submedicion_ref_dim t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_submedicion_ciclo_dim' then
    -- Submedicion por vejez (sql/39): sumas por ciclo y estrato, ~85 filas por periodo (338 hoy). Mismos filtros.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by t.periodo, length(t.ciclo), t.ciclo, t.estrato),
             '[]'::jsonb)
      into resultado
    from bi.v_submedicion_ciclo_dim t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_submedicion_rango_dim' then
    -- Submedicion por vejez (sql/39): sumas por ciclo, estrato y rango de consumo, ~600 filas por periodo (2.349 hoy).
    -- Mismos filtros.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by t.periodo, length(t.ciclo), t.ciclo, t.estrato, case t.rango_m3 when '1-5' then 1 when '6-10' then 2 when '11-15' then 3 when '16-20' then 4 when '21-30' then 5 when '31-40' then 6 when '41-60' then 7 when '61-100' then 8 else 9 end),
             '[]'::jsonb)
      into resultado
    from bi.v_submedicion_rango_dim t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_reclamo_metodo_banda_dim' then
    -- Reclamos segun el metodo de facturacion, resumen SIN ciclo (sql/41): ~730 filas por periodo, 3.539 en los 7 periodos de
    -- hoy (~1,6 MB sin comprimir). Con periodo (exacto), desde o hasta devuelve esos periodos; SIN filtro devuelve TODOS.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by t.periodo, t.metodo_ant, t.metodo_act, case t.banda_antig when '0-3' then 1 when '3-5' then 2 when '5-10' then 3 when '10-15' then 4 when '>15 (fecha real)' then 5 when '>15 (1986-01-01)' then 6 when 'Sin fecha' then 7 when 'Sin medidor' then 8 else 9 end, t.estrato, t.uso),
             '[]'::jsonb)
      into resultado
    from bi.v_reclamo_metodo_banda_dim t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_reclamo_metodo_ciclo_dim' then
    -- Reclamos segun el metodo de facturacion, resumen por ciclo y metodo del periodo (sql/41): ~110 filas por periodo, 786 hoy.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by t.periodo, length(t.ciclo), t.ciclo, t.metodo_act),
             '[]'::jsonb)
      into resultado
    from bi.v_reclamo_metodo_ciclo_dim t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_mapa_calor_dim' then
    -- Mapa de calor, celdas de 250 m publicadas por periodo y capa (sql/42): ~1.150 filas por periodo, 8.067 hoy. Solo celdas con
    -- >= 5 contratos de base; los conteos de 1 a 4 llegan como NULL (supresion hecha en la base).
    select coalesce(jsonb_agg(to_jsonb(t)
             order by t.periodo, t.capa, t.celda_x, t.celda_y),
             '[]'::jsonb)
      into resultado
    from bi.v_mapa_calor_dim t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  elsif p_vista = 'v_mapa_calor_cobertura_dim' then
    -- Cobertura del mapa de calor por periodo y capa (sql/42): 2 filas por periodo.
    select coalesce(jsonb_agg(to_jsonb(t)
             order by t.periodo, t.capa),
             '[]'::jsonb)
      into resultado
    from bi.v_mapa_calor_cobertura_dim t
    where (p_filtros ->> 'periodo' is null or t.periodo =  p_filtros ->> 'periodo')
      and (p_filtros ->> 'desde'   is null or t.periodo >= p_filtros ->> 'desde')
      and (p_filtros ->> 'hasta'   is null or t.periodo <= p_filtros ->> 'hasta');

  else
    raise exception 'vista_no_permitida: %', p_vista
      using errcode = 'P0001';
  end if;

  return resultado;
end $$;

-- ---------------------------------------------------------------------
-- Blindaje de acceso.
-- PostgREST solo expone public/graphql_public (config.toml), así que bi
-- y bi_interno ya no son alcanzables por la API REST; estos REVOKE
-- cierran además cualquier acceso directo por rol de la API.
-- El RPC queda ejecutable ÚNICAMENTE por service_role (la Edge Function).
-- ---------------------------------------------------------------------
revoke all on schema bi, bi_interno from public, anon, authenticated;
revoke all on all tables in schema bi, bi_interno from public, anon, authenticated;

revoke all on function public.geoportal_bi_consulta(text, jsonb)
  from public, anon, authenticated;
grant execute on function public.geoportal_bi_consulta(text, jsonb)
  to service_role;

-- =====================================================================
-- VERIFICACIONES (correr a mano tras ejecutar este archivo)
-- =====================================================================
-- 0) El ancla existe y es el período esperado:
--      select * from bi.v_ultimo_periodo;
--
-- 1) El RPC responde (como service_role / editor SQL):
--      select public.geoportal_bi_consulta('v_kpi_mes',
--        (select jsonb_build_object('periodo', periodo) from bi.v_ultimo_periodo));
--      select public.geoportal_bi_consulta('v_kpi_anio');
--    Debe traer facturado ≈ 5.983,9 M, recaudo ≈ 4.999,6 M,
--    contratos_activos = 111.579 para 202607.
--
-- 2) Una vista fuera de la lista cerrada es rechazada:
--      select public.geoportal_bi_consulta('v_cartera_contrato');
--      -- error esperado: vista_no_permitida
--
-- 3) Los roles de la API no pueden ni ejecutar el RPC ni leer bi:
--      set role authenticated;
--      select public.geoportal_bi_consulta('v_kpi_mes');   -- permission denied
--      select * from bi.v_kpi_mes;                          -- permission denied
--      reset role;
--      set role anon;
--      select * from bi.v_kpi_mes;                          -- permission denied
--      reset role;
--
-- 4) De extremo a extremo (tras desplegar la Edge Function geoportal-bi):
--      con un usuario CON el modo: la pantalla Resumen carga y en
--      public.geoportal_auditoria aparece accion = 'ver_dashboard';
--      con un usuario SIN el modo: la función responde 403.
-- =====================================================================

-- =====================================================================
-- ROLLBACK de las ramas v_lectura_ciclo_dim, v_observacion_dim y
-- v_medidor_antig_dim (35 -> 38 ramas): volver a la version de este archivo en el
-- commit a0a4295 (35 ramas, hasta v_desviacion_dim) y volver a ejecutarlo
-- (create or replace conserva el ACL). Antes de retirar las ramas, quitar las tres
-- vistas de VISTAS_PERMITIDAS en geoportal-bi y redesplegar la Edge Function.
-- =====================================================================

-- =====================================================================
-- ROLLBACK de las ramas v_consumo_rango_dim y v_consumo_basico_dim (38 -> 40
-- ramas): volver a la version de este archivo en el commit f77682b (38 ramas, hasta
-- v_medidor_antig_dim) y volver a ejecutarlo (create or replace conserva el ACL).
-- Antes de retirar las ramas, quitar las dos vistas de VISTAS_PERMITIDAS en
-- geoportal-bi y redesplegar la Edge Function.
-- =====================================================================

-- =====================================================================
-- ROLLBACK de las ramas de Recaudo desagregada (v_recaudo_eficiencia_dim,
-- v_recaudo_ritmo_dim, v_recaudo_edad_dim, v_notas_causal_dim y
-- v_recaudo_entidad_dim; 40 -> 45 ramas): volver a la version de este archivo en el
-- commit fc966b0 (40 ramas, hasta v_consumo_basico_dim) y volver a ejecutarlo
-- (create or replace conserva el ACL). Antes de retirar las ramas, quitar las cinco
-- vistas de VISTAS_PERMITIDAS en geoportal-bi y redesplegar la Edge Function.
-- =====================================================================

-- =====================================================================
-- ROLLBACK de la rama v_cambio_medidor_dim (45 -> 46 ramas): volver a la version de este archivo en el
-- commit 9bb866e (45 ramas, hasta v_recaudo_entidad_dim) y volver a ejecutarlo (create or replace conserva el
-- ACL). Antes de retirar la rama, quitar la vista de VISTAS_PERMITIDAS en geoportal-bi y redesplegar la
-- Edge Function (v18).
-- =====================================================================

-- =====================================================================
-- ROLLBACK de las ramas v_submedicion_ref_dim, v_submedicion_ciclo_dim y v_submedicion_rango_dim (46 -> 49 ramas):
-- volver a la version de este archivo con 46 ramas (hasta v_cambio_medidor_dim) y volver a ejecutarlo (create or replace
-- conserva el ACL). Antes de retirar las ramas, quitar las tres vistas de VISTAS_PERMITIDAS en geoportal-bi y
-- redesplegar la Edge Function (v19).
-- =====================================================================

-- =====================================================================
-- ROLLBACK de las ramas v_reclamo_metodo_banda_dim y v_reclamo_metodo_ciclo_dim (49 -> 51 ramas): volver a la version de este
-- archivo con 49 ramas (hasta v_submedicion_rango_dim) y volver a ejecutarlo (create or replace conserva el ACL). Antes de
-- retirar las ramas, quitar las dos vistas de VISTAS_PERMITIDAS en geoportal-bi y redesplegar la Edge Function (v20).
-- =====================================================================

-- =====================================================================
-- ROLLBACK de las ramas v_mapa_calor_dim y v_mapa_calor_cobertura_dim (51 -> 53 ramas): volver a la version de este archivo
-- con 51 ramas (hasta v_reclamo_metodo_ciclo_dim) y volver a ejecutarlo (create or replace conserva el ACL). Antes de
-- retirar las ramas, quitar las dos vistas de VISTAS_PERMITIDAS en geoportal-bi y redesplegar la Edge Function (v21).
-- =====================================================================
