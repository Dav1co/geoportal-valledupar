-- =====================================================================
-- 02_capa1_resumen.sql · Capa 1: casting de la landing, SIN agregar
-- ---------------------------------------------------------------------
-- Vistas 1:1 sobre hechos.* con tipos ya saneados (bi.f_num / f_fecha /
-- f_concepto_num). Solo las fuentes que necesita la pantalla Resumen
-- ejecutivo. Viven en bi_interno: NUNCA se sirven directo al frontend.
-- Requiere 01_capa0.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Facturación agrupada por concepto y mes (histórico completo).
-- consumo SOLO significa m³ en los conceptos 2 y 4; en 26–33 y otros
-- trae la base de cálculo. Cualquier suma de consumo debe filtrar
-- por concepto_num.
--
-- ⚠ EXCLUYE LA FILA DE TOTALES DEL EXCEL. Los archivos de 202309,
-- 202310 y 202311 traen al final una fila con la suma de todo lo
-- facturado y sin concepto, año ni mes; el cargador solo descarta las
-- que empiezan por "TOTAL" y estas no lo dicen, así que entraron a la
-- landing. Sumaban ~5.400 M por mes y DUPLICABAN la facturación de esos
-- tres meses (10.852 M contra los ~5.100 M reales), hundiendo el
-- % de recaudo de 2023 a 62,5 %.
-- La regla que lo resuelve es la misma de todo el tablero: un concepto
-- se identifica por su NÚMERO — una fila sin número no es un concepto.
-- Verificado que el problema solo afecta a esta fuente: recaudo_agrupado,
-- cartera_resumen y notas están limpias.
-- ---------------------------------------------------------------------
create or replace view bi_interno.v_facturacion_agrupado as
select
  periodo,
  bi.f_num(anio)::int              as anio,
  bi.f_num(mes)::int               as mes,
  bi.f_concepto_num(concepto)      as concepto_num,
  concepto,
  bi.f_num(facturado)              as facturado,
  bi.f_num(facturado_debito)       as facturado_debito,
  bi.f_num(facturado_credito)      as facturado_credito,
  bi.f_num(consumo)                as consumo
from hechos.facturacion_agrupado
where bi.f_concepto_num(concepto) is not null;

-- ---------------------------------------------------------------------
-- Recaudo agrupado por concepto con apertura por edad (histórico).
-- id_concepto ya es el número; el nombre solo acompaña.
-- ---------------------------------------------------------------------
create or replace view bi_interno.v_recaudo_agrupado as
select
  periodo,
  bi.f_num(id_concepto)::int       as concepto_num,
  concepto,
  bi.f_num(recaudo_total)          as recaudo_total,
  bi.f_num(rec_0)                  as rec_0,
  bi.f_num(rec_30)                 as rec_30,
  bi.f_num(rec_60)                 as rec_60,
  bi.f_num(rec_90)                 as rec_90,
  bi.f_num(rec_120)                as rec_120,
  bi.f_num(rec_150)                as rec_150,
  bi.f_num(rec_180)                as rec_180,
  bi.f_num(rec_210)                as rec_210,
  bi.f_num(rec_240)                as rec_240,
  bi.f_num(rec_270)                as rec_270,
  bi.f_num(rec_300)                as rec_300,
  bi.f_num(rec_330)                as rec_330,
  bi.f_num(rec_360)                as rec_360,
  bi.f_num(rec_may360)             as rec_may360
from hechos.recaudo_agrupado;

-- ---------------------------------------------------------------------
-- Cartera resumida por concepto al corte (histórico), con la apertura
-- completa por edad. Los nombres cf_cartN son el CORTE INFERIOR de cada
-- cubeta (misma convención que el recaudo).
-- ⚠ Las cubetas cubren SOLO la cartera NO financiada: su suma no iguala
-- cartera_total. La diferencia es la cartera financiada — verificado
-- contra hechos.cartera_contrato.saldo_financiado (desviación 0,07 %).
-- Ver el encabezado de 10_cartera.sql.
-- ---------------------------------------------------------------------
create or replace view bi_interno.v_cartera_resumen as
select
  periodo,
  bi.f_num(recaconc)::int          as concepto_num,
  concepto,
  bi.f_num(cartera_total)          as cartera_total,
  bi.f_num(cf_cart0)               as cf_cart0,
  bi.f_num(cf_cart30)              as cf_cart30,
  bi.f_num(cf_cart60)              as cf_cart60,
  bi.f_num(cf_cart90)              as cf_cart90,
  bi.f_num(cf_cart120)             as cf_cart120,
  bi.f_num(cf_cart150)             as cf_cart150,
  bi.f_num(cf_cart180)             as cf_cart180,
  bi.f_num(cf_cart210)             as cf_cart210,
  bi.f_num(cf_cart240)             as cf_cart240,
  bi.f_num(cf_cart270)             as cf_cart270,
  bi.f_num(cf_cart300)             as cf_cart300,
  bi.f_num(cf_cart330)             as cf_cart330,
  bi.f_num(cf_cart360)             as cf_cart360,
  bi.f_num(cf_cartmay)             as cf_cartmay,
  archivo_origen
from hechos.cartera_resumen;

-- ---------------------------------------------------------------------
-- Notas por período (histórico, grano contrato-nota).
-- VALOR ya viene CON signo desde Acuo (verificado en 202607):
-- crédito (CR) negativo, débito (DB) positivo. No aplicar signo de nuevo.
-- ---------------------------------------------------------------------
create or replace view bi_interno.v_notas as
select
  periodo,
  bi.f_num(anio)::int              as anio,
  bi.f_num(mes)::int               as mes,
  contrato,
  bi.f_concepto_num(concepto)      as concepto_num,
  concepto,
  causal,
  tipo_signo,
  bi.f_num(valor)                  as valor,
  bi.f_fecha(fecha_nota)           as fecha_nota
from hechos.notas;

-- ---------------------------------------------------------------------
-- Facturación por contrato y concepto (detalle, retención 6 períodos).
-- Base de: suscriptores por servicio (concepto 1 acueducto, 3 alcanta-
-- rillado), m³ (conceptos 2 y 4) y subsidios/contribuciones (26–33).
-- ---------------------------------------------------------------------
create or replace view bi_interno.v_facturacion_contratos as
select
  periodo,
  ciclo,
  contrato,
  bi.f_num(anio)::int              as anio,
  bi.f_num(mes)::int               as mes,
  bi.f_concepto_num(concepto)      as concepto_num,
  concepto,
  categoria,
  subcategoria,
  bi.f_num(facturado)              as facturado,
  bi.f_num(consumo)                as consumo
from hechos.facturacion_contratos;

-- ---------------------------------------------------------------------
-- Cartera a nivel contrato (detalle, retención 6 períodos).
-- ADICIÓN respecto al alcance pedido: v_kpi_mes necesita
-- "contratos_con_cartera" y ninguna de las otras cuatro fuentes tiene
-- contratos con saldo. Se exponen SOLO columnas sin datos personales
-- (la tabla hechos.cartera_contrato sí trae nombre/cédula/dirección;
-- aquí se dejan fuera deliberadamente).
-- ---------------------------------------------------------------------
create or replace view bi_interno.v_cartera_contrato as
select
  periodo,
  contrato,
  ciclo,
  bi.f_num(total_cartera)          as total_cartera,
  bi.f_num(facturas_vencidas)      as facturas_vencidas,
  bi.f_num(saldo_financiado)       as saldo_financiado
from hechos.cartera_contrato;
