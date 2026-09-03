-- =====================================================================
-- 22 — Extracción para la presentación gerencial (agosto 2026)
--
-- SOLO LECTURA. No crea, no altera y no borra nada: son SELECT sobre
-- vistas del esquema bi que ya existen. Se puede correr entero en el
-- SQL Editor de Supabase y copiar cada resultado a PowerPoint.
--
-- Orden: 0) qué períodos existen de verdad  ·  1) 2026 mes a mes  ·
-- 2) cierres de contexto  ·  3) cortes de detalle  ·  4) comparación
-- del último mes contra los anclas.
--
-- ADVERTENCIA DE ALCANCE (retención): las vistas agregadas
-- (v_facturacion_mes, v_recaudo_mes, v_cartera_mes, v_ipuf) son
-- históricas. Las de DETALLE (v_fact_detalle_dim, v_cartera_detalle_dim)
-- salen de tablas con retención de 6 períodos: para cierres viejos
-- (202301, 202412, 202512) NO hay detalle y la consulta devolverá
-- cero filas. Eso no es un error: es que el dato no está.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. VERIFICACIÓN PREVIA — no seguir sin leer esto
-- ---------------------------------------------------------------------

-- 0.1 Período ancla (último con las tres fuentes agregadas cargadas).
SELECT * FROM bi.v_ultimo_periodo;

-- 0.2 Cobertura real de cada fuente: primer y último período y cuántos
--     hay. Aquí se responde si 202212 existe o no.
SELECT 'v_facturacion_mes' AS fuente, min(periodo) AS primero, max(periodo) AS ultimo, count(*) AS periodos FROM bi.v_facturacion_mes
UNION ALL SELECT 'v_recaudo_mes',  min(periodo), max(periodo), count(*) FROM bi.v_recaudo_mes
UNION ALL SELECT 'v_cartera_mes',  min(periodo), max(periodo), count(*) FROM bi.v_cartera_mes
UNION ALL SELECT 'v_ipuf',         min(periodo), max(periodo), count(*) FROM bi.v_ipuf
ORDER BY 1;

-- 0.3 Prueba directa de los períodos que pide la presentación.
--     'SÍ' / 'NO' por fuente. Si 202212 sale NO en las tres agregadas,
--     el cierre más antiguo de la presentación es 202301.
WITH pedidos(periodo) AS (
  VALUES ('202212'), ('202301'), ('202412'), ('202512'), ('202607')
)
SELECT p.periodo,
       CASE WHEN EXISTS (SELECT 1 FROM bi.v_facturacion_mes f WHERE f.periodo = p.periodo) THEN 'SÍ' ELSE 'NO' END AS facturacion,
       CASE WHEN EXISTS (SELECT 1 FROM bi.v_recaudo_mes     r WHERE r.periodo = p.periodo) THEN 'SÍ' ELSE 'NO' END AS recaudo,
       CASE WHEN EXISTS (SELECT 1 FROM bi.v_cartera_mes     c WHERE c.periodo = p.periodo) THEN 'SÍ' ELSE 'NO' END AS cartera,
       CASE WHEN EXISTS (SELECT 1 FROM bi.v_ipuf            i WHERE i.periodo = p.periodo) THEN 'SÍ' ELSE 'NO' END AS ipuf
FROM pedidos p
ORDER BY p.periodo;

-- 0.4 Períodos con DETALLE disponible (retención 6). Marca hasta dónde
--     se puede bajar a comuna, uso y estrato.
SELECT * FROM bi.v_periodos_fuente ORDER BY 1, 2;


-- ---------------------------------------------------------------------
-- 1. BLOQUE 1 — 2026 mes a mes (202601 → último cargado)
-- ---------------------------------------------------------------------

-- 1.1 Facturación · fuente: bi.v_facturacion_mes
--     Cadena oficial: bruta + subsidios (26–29, negativos) +
--     contribuciones (30–33, positivos) = neta.
SELECT periodo, bruta, subsidios, contribuciones, neta,
       deficit, deficit_abs, pct_deficit_bruta,
       m3_acueducto, m3_alcantarillado
FROM bi.v_facturacion_mes
WHERE periodo LIKE '2026%'
ORDER BY periodo;

-- 1.2 Recaudo · fuente: bi.v_recaudo_mes
--     Corriente 0–30 = rec_0 + rec_30 (definición confirmada; no tocar).
SELECT periodo, recaudo_total, recaudo_0_30,
       recuperacion_cartera, recaudo_60_360, recaudo_may360,
       pct_0_30, pct_recuperacion,
       variacion, variacion_pct
FROM bi.v_recaudo_mes
WHERE periodo LIKE '2026%'
ORDER BY periodo;

-- 1.3 Cartera · fuente: bi.v_cartera_mes
--     `variacion` ya es el delta contra el mes anterior: no recalcular.
SELECT periodo, cartera_total, no_financiada, financiada,
       variacion AS delta_mes_anterior, variacion_pct,
       pct_financiada, pct_may_360
FROM bi.v_cartera_mes
WHERE periodo LIKE '2026%'
ORDER BY periodo;

-- 1.4 IPUF · fuente: bi.v_ipuf
--     OJO: la serie va un mes atrasada respecto del cierre comercial.
--     Se muestran el período propio y el comercial al que acompaña.
SELECT periodo AS periodo_ipuf,
       to_char((to_date(periodo, 'YYYYMM') + interval '1 month'), 'YYYYMM') AS periodo_comercial_asociado,
       ipuf, meta_ipuf_emdupar AS meta_ipuf, brecha_meta_real,
       ipuf_anio_corrido, ipuf_estandar,
       agua_potable, agua_facturada,
       perdida_total AS perdida_total_m3, perdida_total_pesos
FROM bi.v_ipuf
WHERE periodo LIKE '2026%' OR periodo = '202512'
ORDER BY periodo;


-- ---------------------------------------------------------------------
-- 2. BLOQUE 2 — cierres de contexto
--     202512 y el más antiguo disponible. Si 0.3 dice que 202212 no
--     existe, la lista de abajo ya trae 202301 en su lugar; si sí
--     existe, agregar '202212' a la lista.
-- ---------------------------------------------------------------------

-- 2.1 Facturación de los cierres.
SELECT periodo, bruta, subsidios, contribuciones, neta,
       deficit_abs, pct_deficit_bruta, m3_acueducto, m3_alcantarillado
FROM bi.v_facturacion_mes
WHERE periodo IN ('202301', '202412', '202512')
ORDER BY periodo;

-- 2.2 Recaudo de los cierres.
SELECT periodo, recaudo_total, recaudo_0_30, recuperacion_cartera,
       recaudo_60_360, recaudo_may360, pct_0_30, pct_recuperacion
FROM bi.v_recaudo_mes
WHERE periodo IN ('202301', '202412', '202512')
ORDER BY periodo;

-- 2.3 Cartera de los cierres.
SELECT periodo, cartera_total, no_financiada, financiada,
       variacion AS delta_mes_anterior, pct_financiada, pct_may_360
FROM bi.v_cartera_mes
WHERE periodo IN ('202301', '202412', '202512')
ORDER BY periodo;

-- 2.4 IPUF de los cierres.
SELECT periodo, ipuf, meta_ipuf_emdupar AS meta_ipuf, brecha_meta_real, ipuf_anio_corrido
FROM bi.v_ipuf
WHERE periodo IN ('202212', '202301', '202412', '202512')
ORDER BY periodo;


-- ---------------------------------------------------------------------
-- 3. CORTES DE DETALLE (solo períodos dentro de la retención de 6)
-- ---------------------------------------------------------------------

-- 3.1 Cartera por edades del último período · bi.v_cartera_tramo
SELECT periodo, orden, tramo, valor, pct_periodo
FROM bi.v_cartera_tramo
WHERE periodo = (SELECT periodo FROM bi.v_ultimo_periodo)
ORDER BY orden;

-- 3.2 Cartera por comuna, top 5 · bi.v_cartera_detalle_dim
--     `comuna_confiable` distingue la comuna que vino de Acuo de la
--     inferida por barrio: la lámina debe decirlo, no esconderlo.
SELECT comuna,
       sum(cartera)      AS cartera,
       sum(t_may_360)    AS mora_may_360,
       round(100.0 * sum(cartera) / nullif(sum(sum(cartera)) OVER (), 0), 1) AS pct_del_total,
       bool_and(comuna_confiable) AS comuna_confiable
FROM bi.v_cartera_detalle_dim
WHERE periodo = (SELECT periodo FROM bi.v_ultimo_periodo)
GROUP BY comuna
ORDER BY cartera DESC
LIMIT 5;

-- 3.2b Cuánta cartera del corte anterior es comuna INFERIDA (control de
--      calidad del dato: va en la nota al pie de la lámina).
SELECT comuna_origen, sum(cartera) AS cartera,
       round(100.0 * sum(cartera) / nullif(sum(sum(cartera)) OVER (), 0), 1) AS pct
FROM bi.v_cartera_detalle_dim
WHERE periodo = (SELECT periodo FROM bi.v_ultimo_periodo)
GROUP BY comuna_origen
ORDER BY cartera DESC;

-- 3.3 Recaudo por entidad bancaria del mes en curso.
--     FUENTE CORREGIDA: bi.v_recaudo_diario, no hechos.recaudo_diario.
--     La tabla de hechos es zona de aterrizaje en TEXT; la vista ya
--     castea y es la que lee el tablero. El "mes en curso" es el que
--     traen las conciliaciones, que va por delante del cierre.
SELECT entidad,
       sum(valor_procesado)     AS valor_procesado,
       sum(cupones_procesados)  AS cupones,
       count(*)                 AS lotes,
       count(*) FILTER (WHERE conciliacion_cerrada = 'S') AS lotes_cerrados
FROM bi.v_recaudo_diario
WHERE periodo_registro = (
  SELECT max(periodo) FROM bi.v_recaudo_diario_mes WHERE origen = 'curso'
)
GROUP BY entidad
ORDER BY valor_procesado DESC;

-- 3.4 Facturación por uso y estrato del último período · bi.v_fact_detalle_dim
--     REGLA CRÍTICA: `consumo` solo es m³ en los conceptos 2 y 4. En
--     cargos fijos (1, 3) es NULL y en 26–33 es base de cálculo. Por eso
--     el m³ se suma FILTRADO y jamás la columna completa.
SELECT uso,
       subcategoria AS estrato,
       sum(facturado)                                         AS facturado,
       sum(consumo) FILTER (WHERE concepto_num = 2)           AS m3_acueducto,
       sum(consumo) FILTER (WHERE concepto_num = 4)           AS m3_alcantarillado,
       max(contratos) FILTER (WHERE concepto_num = 1)         AS contratos_acueducto
FROM bi.v_fact_detalle_dim
WHERE periodo = (SELECT periodo FROM bi.v_ultimo_periodo)
GROUP BY uso, subcategoria
ORDER BY uso, subcategoria;


-- ---------------------------------------------------------------------
-- 4. COMPARACIÓN — último mes cargado contra los anclas
--     202301 (o 202212 si existe), 202412, 202512 y 202607.
--     Una sola tabla ancha, lista para pegar como lámina resumen.
-- ---------------------------------------------------------------------
WITH anclas(periodo, etiqueta) AS (
  VALUES ('202301', 'Ene 2023 (más antiguo disponible)'),
         ('202412', 'Dic 2024 (cierre)'),
         ('202512', 'Dic 2025 (cierre)'),
         ('202607', 'Jul 2026'),
         ((SELECT periodo FROM bi.v_ultimo_periodo), 'Último cargado')
)
SELECT a.etiqueta,
       a.periodo,
       f.bruta, f.subsidios, f.contribuciones, f.neta,
       f.m3_acueducto,
       r.recaudo_total, r.recaudo_0_30, r.recuperacion_cartera, r.pct_0_30,
       c.cartera_total, c.no_financiada, c.variacion AS delta_cartera_mes,
       i.ipuf, i.meta_ipuf_emdupar AS meta_ipuf, i.brecha_meta_real
FROM anclas a
LEFT JOIN bi.v_facturacion_mes f ON f.periodo = a.periodo
LEFT JOIN bi.v_recaudo_mes     r ON r.periodo = a.periodo
LEFT JOIN bi.v_cartera_mes     c ON c.periodo = a.periodo
LEFT JOIN bi.v_ipuf            i ON i.periodo = a.periodo
ORDER BY a.periodo;

-- 4.1 El mismo corte en variación: último cargado contra cada ancla.
--     Se calcula sobre las cifras de 4; si algún ancla sale en NULL es
--     que ese período no existe — reportarlo, no rellenarlo.
WITH ult AS (
  SELECT f.periodo, f.neta, r.recaudo_total, c.cartera_total
  FROM bi.v_facturacion_mes f
  JOIN bi.v_recaudo_mes r ON r.periodo = f.periodo
  JOIN bi.v_cartera_mes c ON c.periodo = f.periodo
  WHERE f.periodo = (SELECT periodo FROM bi.v_ultimo_periodo)
),
anclas(periodo) AS (VALUES ('202301'), ('202412'), ('202512'), ('202607'))
SELECT a.periodo AS ancla,
       u.periodo AS ultimo,
       round(100.0 * (u.neta          - f.neta)          / nullif(f.neta, 0), 1)          AS var_pct_facturacion_neta,
       round(100.0 * (u.recaudo_total - r.recaudo_total) / nullif(r.recaudo_total, 0), 1) AS var_pct_recaudo,
       round(100.0 * (u.cartera_total - c.cartera_total) / nullif(c.cartera_total, 0), 1) AS var_pct_cartera
FROM anclas a
CROSS JOIN ult u
LEFT JOIN bi.v_facturacion_mes f ON f.periodo = a.periodo
LEFT JOIN bi.v_recaudo_mes     r ON r.periodo = a.periodo
LEFT JOIN bi.v_cartera_mes     c ON c.periodo = a.periodo
ORDER BY a.periodo;
