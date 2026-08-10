-- =====================================================================
-- 16_notas.sql · Capa 2: pantalla de Notas
-- ---------------------------------------------------------------------
-- Requiere 01, 02, 06. Fuente: hechos.notas — HISTÓRICA (43 períodos,
-- 202301–202607, 296.823 filas), sin retención y con el ancla incluida.
-- Vistas EN VIVO: la fuente es liviana.
--
-- ⚠ SIGNO: `valor` ya viene CON signo desde Acuo (verificado en 202607:
-- CR = 1.495 notas por −197.718.996,56 y DB = 913 por +14.097.901,26).
-- NO aplicar signo otra vez. El neto del ancla (−183.621.095,30) coincide
-- con bi.v_kpi_mes.notas_valor.
--
-- ⚠ El contrato solo se usa para CONTAR contratos distintos; ningún
-- identificador llega a bi.
--
-- QUÉ MIDE ESTA PANTALLA: las notas son ajustes a lo ya facturado. Una
-- nota crédito descuenta al usuario (por error de la empresa, tutela,
-- corrección de lectura…) y una débito le cobra de más. El volumen y la
-- causal dicen cuánta facturación hay que corregir después de emitida —
-- una medida directa de calidad del ciclo comercial.
-- =====================================================================

-- ---------------------------------------------------------------------
-- bi.v_notas_mes · serie mensual: valor neto, crédito, débito y cuántos
-- contratos resultaron afectados.
-- ---------------------------------------------------------------------
create or replace view bi.v_notas_mes as
select
  periodo,
  left(periodo, 4)::int  as anio,
  right(periodo, 2)::int as mes,
  count(*)                                                   as notas,
  count(*) filter (where upper(coalesce(tipo_signo,'')) = 'CR') as notas_credito,
  count(*) filter (where upper(coalesce(tipo_signo,'')) = 'DB') as notas_debito,
  sum(valor)                                                 as valor_neto,
  sum(valor) filter (where upper(coalesce(tipo_signo,'')) = 'CR') as valor_credito,
  sum(valor) filter (where upper(coalesce(tipo_signo,'')) = 'DB') as valor_debito,
  abs(sum(valor) filter (where upper(coalesce(tipo_signo,'')) = 'CR')) as valor_credito_abs,
  count(distinct contrato)                                   as contratos_afectados
from bi_interno.v_notas
group by periodo;

revoke all on bi.v_notas_mes from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_notas_dim · preagregado por causal, signo y servicio (vía la
-- ruta contable del concepto). 26 causales; el preagregado es pequeño.
-- ---------------------------------------------------------------------
create or replace view bi.v_notas_dim as
select
  n.periodo,
  coalesce(nullif(btrim(n.causal), ''), '(sin causal)')  as causal,
  upper(coalesce(nullif(btrim(n.tipo_signo), ''), '?'))  as signo,
  case
    when bi.f_ruta_concepto(n.concepto_num) like 'ACUEDUCTO -%'      then 'ACUEDUCTO'
    when bi.f_ruta_concepto(n.concepto_num) like 'ALCANTARILLADO -%' then 'ALCANTARILLADO'
    when bi.f_ruta_concepto(n.concepto_num) = 'PLUVIAL'              then 'PLUVIAL'
    when bi.f_ruta_concepto(n.concepto_num) = 'TERCERO'              then 'TERCERO'
    else 'OTROS'
  end                                                    as servicio,
  count(*)                                               as cantidad,
  sum(n.valor)                                           as valor,
  count(distinct n.contrato)                             as contratos
from bi_interno.v_notas n
group by n.periodo, 2, 3, 4;

revoke all on bi.v_notas_dim from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- bi.v_notas_vs_pqr · el cruce del indicador C4 (aprobado en fase 2):
-- ¿las notas responden a reclamos de los usuarios, o a correcciones que
-- la empresa detecta por su cuenta?
--
-- Ambas fuentes son históricas, así que la serie es larga. El cruce es
-- MENSUAL, no por causal: los catálogos de causal de notas (26 valores)
-- y de reclamos son distintos, y emparejarlos por texto sería inventar
-- una correspondencia que el dato no respalda.
--
-- Lectura honesta: esto muestra CO-OCURRENCIA en el tiempo, no que un
-- reclamo concreto haya generado una nota concreta. Para eso haría falta
-- cruzar por contrato y fecha, que sí es posible pero es otro trabajo.
-- ---------------------------------------------------------------------
create or replace view bi.v_notas_vs_pqr as
select
  coalesce(n.periodo, p.periodo)      as periodo,
  n.notas,
  n.valor_credito_abs,
  p.reclamos,
  p.valor_reclamado,
  round(n.notas::numeric / nullif(p.reclamos, 0), 2) as notas_por_reclamo
from bi.v_notas_mes n
full outer join bi.v_pqr_mes p using (periodo);

revoke all on bi.v_notas_vs_pqr from public, anon, authenticated;

-- =====================================================================
-- VERIFICACIONES
-- =====================================================================
-- 1) FUENTE INDEPENDIENTE — el neto contra bi.v_kpi_mes.notas_valor,
--    que se calcula por separado en 03_v_kpi.sql:
--      select n.periodo, n.valor_neto, k.notas_valor,
--             round(n.valor_neto - k.notas_valor, 2) dif
--      from bi.v_notas_mes n join bi.v_kpi_mes k using (periodo)
--      where abs(n.valor_neto - k.notas_valor) > 0.01;
--      -- debe devolver CERO filas; 202607: −183.621.095,30
-- 2) COHERENCIA — serie contra preagregado:
--      select m.periodo from bi.v_notas_mes m
--      join (select periodo, sum(cantidad) c, sum(valor) v from bi.v_notas_dim group by 1) d
--        using (periodo)
--      where m.notas <> d.c or abs(m.valor_neto - d.v) > 0.01;
--      -- debe devolver CERO filas
-- 3) Signos: crédito negativo, débito positivo, en todos los períodos:
--      select periodo from bi.v_notas_mes
--      where coalesce(valor_credito, 0) > 0 or coalesce(valor_debito, 0) < 0;
--      -- debe devolver CERO filas
-- 4) El cruce con PQR solo tiene ambas cifras donde ambas fuentes existen:
--      select count(*) filter (where notas is not null and reclamos is not null) con_ambos,
--             count(*) filter (where reclamos is null) solo_notas
--      from bi.v_notas_vs_pqr;
-- =====================================================================
