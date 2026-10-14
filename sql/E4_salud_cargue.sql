-- Receta E4 · salud del último cargue (hechos.carga_log).
-- El filtro excluye solo 'omitido_retencion' (ruido esperado) en lugar de
-- listar los estados válidos: así un estado nuevo aparece en vez de
-- perderse en silencio.
--
-- Los estados alerta_* (alerta_dim, alerta_cabecera: avisos del cargador)
-- NO cuentan como "último estado": se escriben DESPUÉS del cargado/parcial
-- de la misma fuente y taparían el resultado del cargue. Se muestran aparte
-- en la columna "alertas" = cuántas filas alerta_* tiene el último período
-- cargado de cada fuente (el detalle está en carga_log.detalle).
with l as (
  select * from hechos.carga_log where estado <> 'omitido_retencion'
), base as (
  select * from l where left(estado, 7) <> 'alerta_'
), ult as (
  select fuente, max(periodo) as ultimo_periodo from base group by fuente
)
select b.fuente, u.ultimo_periodo,
       (array_agg(b.estado order by b.fecha_carga desc, b.id desc))[1] as ultimo_estado,
       (array_agg(b.filas  order by b.fecha_carga desc, b.id desc))[1] as filas,
       to_char(max(b.fecha_carga),'MM-DD HH24:MI') as cargado,
       (select count(*) from l a
         where a.fuente = b.fuente and a.periodo = u.ultimo_periodo
           and left(a.estado, 7) = 'alerta_') as alertas
from base b join ult u using (fuente)
group by b.fuente, u.ultimo_periodo
order by b.fuente;
