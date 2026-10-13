-- Receta E4 · salud del último cargue (hechos.carga_log).
-- El filtro excluye solo 'omitido_retencion' (ruido esperado) en lugar de
-- listar los estados válidos: así un estado nuevo (p. ej. 'alerta_dim',
-- que escribe cargar_hechos.py cuando una vista por periodo queda vacía o
-- no cuadra) aparece en vez de perderse en silencio.
select fuente, max(periodo) as ultimo_periodo,
       (array_agg(estado order by fecha_carga desc))[1] as ultimo_estado,
       (array_agg(filas  order by fecha_carga desc))[1] as filas,
       to_char(max(fecha_carga),'MM-DD HH24:MI') as cargado
from hechos.carga_log
where estado <> 'omitido_retencion'      -- antes: lista cerrada
group by fuente order by fuente;
