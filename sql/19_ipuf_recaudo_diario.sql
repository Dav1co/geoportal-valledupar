-- =====================================================================
-- 19_ipuf_recaudo_diario.sql
-- Capa 2 (bi) para las dos pantallas que faltaban del tablero:
--   · bi.v_ipuf              -> pantalla "Pérdidas (IPUF)"
--   · bi.v_recaudo_diario_mes-> pantalla "Recaudo diario", comparación
--                               del mes en curso contra meses anteriores
--                               al mismo día de corte.
--
-- bi.v_recaudo_diario ya existía y NO se toca.
-- Ninguna de las dos vistas contiene datos personales.
-- =====================================================================


-- ---------------------------------------------------------------------
-- bi.v_ipuf  (EXTENSIÓN de una vista que ya existía)
-- ---------------------------------------------------------------------
-- Fuente: hechos.ipuf (42 columnas TEXT, 114 períodos desde 201701).
--
-- La vista ya existía con 21 columnas. Se CONSERVAN íntegras, con sus
-- nombres y su orden -create or replace no permite renombrar, y además
-- cambiar el contrato de algo ya creado no aporta nada-, y se AÑADEN al
-- final las nueve que le faltaban a la pantalla de Pérdidas:
-- las referencias contra las que se juzga el índice (estándar, año
-- corrido), las cuatro brechas ya calculadas en el origen, la
-- diferencia contra la meta, el agua facturada de alcantarillado y el
-- año tarifario.
--
-- Quedan deliberadamente FUERA (13 columnas del origen), porque
-- pertenecen al análisis tarifario y no a la lectura de pérdidas:
--   cf_acu, cc_acu, cf_alc, cc_alc, ccp_mas_facturada,
--   demanda_tarifa_ccp, demanda_tarifa_ccp_alc,
--   facturado_demanda_acu, facturado_real_acu,
--   facturado_demanda_alc, facturado_real_alc,
--   diferencia_facturado_demanda, diferencia_fac_demanda_pesos
--
-- Reglas aplicadas:
--   · período = ano || lpad(mes,2,'0')
--   · todo valor numérico pasa por bi.f_num() (bloquea NaN/Infinity y
--     los textos no numéricos), nunca ::numeric crudo
--   · fecha e inicio_de_mes son SERIAL DE EXCEL: se convierten con
--     date '1899-12-30' + n. Verificado: 42736 -> 2017-01-01
-- ---------------------------------------------------------------------
create or replace view bi.v_ipuf as
select
    -- ---- las 21 columnas originales, sin tocar ----
    ano || lpad(mes, 2, '0'::text)                          as periodo,
    ano::integer                                            as ano,
    mes::integer                                            as mes,
    '1899-12-30'::date + bi.f_num(fecha)::integer           as fecha,
    '1899-12-30'::date + bi.f_num(inicio_de_mes)::integer   as inicio_de_mes,
    bi.f_num(agua_potable)                                  as agua_potable,
    bi.f_num(agua_facturada)                                as agua_facturada,
    bi.f_num(numero_de_suscriptores)                        as numero_de_suscriptores,
    bi.f_num(ipuf)                                          as ipuf,
    bi.f_num(icuf)                                          as icuf,
    bi.f_num(isuf)                                          as isuf,
    bi.f_num(isuf_meta)                                     as isuf_meta,
    bi.f_num(ianc)                                          as ianc,
    bi.f_num(meta_ipuf_emdupar)                             as meta_ipuf_emdupar,
    bi.f_num(perdida_total)                                 as perdida_total,
    bi.f_num(perdida_total_pesos)                           as perdida_total_pesos,
    bi.f_num(perdida_sin_admisible)                         as perdida_sin_admisible,
    bi.f_num(perdida_sin_admisible_pesos)                   as perdida_sin_admisible_pesos,
    bi.f_num(perdidas_superiores_meta)                      as perdidas_superiores_meta,
    bi.f_num(perdidas_superiores_meta_pesos)                as perdidas_superiores_meta_pesos,
    bi.f_num(tarifa_m3)                                     as tarifa_m3,

    -- ---- añadidas para la pantalla de Pérdidas ----
    -- Referencias contra las que se juzga el IPUF del mes.
    bi.f_num(ipuf_estandar)                                 as ipuf_estandar,
    bi.f_num(ipufar_ano)                                    as ipuf_anio_corrido,
    -- Brechas ya calculadas en el origen: contra el real y contra el
    -- acumulado del año, para el estándar y para la meta.
    bi.f_num(ipufe_ipufr)                                   as brecha_estandar_real,
    bi.f_num(ipufe_ipufar)                                  as brecha_estandar_anio,
    bi.f_num(ipufm_ipufr)                                   as brecha_meta_real,
    bi.f_num(ipufm_ipufar)                                  as brecha_meta_anio,
    bi.f_num(diferencia_en_meta_ipuf)                       as diferencia_meta,
    bi.f_num(agua_facturada_alc)                            as agua_facturada_alc,
    btrim(ano_tarifario)                                    as ano_tarifario
from hechos.ipuf
where ano is not null and mes is not null;

comment on view bi.v_ipuf is
  'Índices de pérdidas por período (IPUF/ICUF/ISUF/IANC), volúmenes y '
  'pérdidas en m3 y pesos. Serie histórica completa desde 201701. '
  'Los seriales de Excel de fecha e inicio_de_mes ya vienen convertidos. '
  'Sin datos personales.';


-- ---------------------------------------------------------------------
-- bi.v_recaudo_diario_mes
-- ---------------------------------------------------------------------
-- Serie diaria comparable entre meses: una fila por (período, día del
-- mes) con el valor del día y el acumulado corrido.
--
-- Une DOS fuentes que miden cosas distintas, y por eso la columna
-- "origen" viaja hasta la pantalla en vez de esconderse:
--
--   'cierre' -> bi.v_recaudo_diario_cierre, que sale de
--               hechos.recaudo_detalle: el mes YA CERRADO, por fecha
--               de pago. Seis períodos de retención.
--   'curso'  -> bi.v_recaudo_diario, que sale de las conciliaciones
--               bancarias: el mes EN CURSO, que aún no tiene cierre.
--
-- Comparar al mismo día de corte es legítimo -y es justo lo que pide
-- la pantalla-, pero las dos series no son la misma medición: la de
-- cierre es el recaudo aplicado al contrato y la del mes en curso es
-- lo conciliado con el banco. La pantalla lo advierte.
-- ---------------------------------------------------------------------
create or replace view bi.v_recaudo_diario_mes as
select
    c.periodo,
    c.dia,
    c.fecha,
    c.valor_dia,
    c.valor_acumulado,
    c.transacciones,
    'cierre'::text as origen
from bi.v_recaudo_diario_cierre c
union all
select
    d.periodo_registro                                      as periodo,
    extract(day from d.dia)::int                            as dia,
    d.dia                                                   as fecha,
    sum(d.valor_procesado)                                  as valor_dia,
    sum(sum(d.valor_procesado)) over (
        partition by d.periodo_registro order by d.dia)     as valor_acumulado,
    count(*)::bigint                                        as transacciones,
    'curso'::text as origen
from bi.v_recaudo_diario d
group by d.periodo_registro, d.dia;

comment on view bi.v_recaudo_diario_mes is
  'Serie diaria por período con acumulado corrido, para comparar el mes '
  'en curso contra meses anteriores al mismo día de corte. La columna '
  'origen distingue el mes cerrado (recaudo_detalle) del mes en curso '
  '(conciliaciones bancarias): no son la misma medición.';
