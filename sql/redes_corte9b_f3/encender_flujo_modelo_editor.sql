-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 — ENCENDER la capa «Flujo del agua (modelo)» en el geovisor. PROPUESTA (apta para el editor SQL web).
-- Se corre AL FINAL: después de la Fase 3, de la carga del flujo, de la Edge geoportal-redes y del FRONTEND con las flechas (Code B).
-- Con un frontend anterior, la casilla se podría marcar y no pintaría nada: por eso va de último.
-- Solo cambia el estado de la capa en la lista (de «espera_dato» a «activa»). La fuente sigue «preparada» y la capa sigue siendo solo de supervisores y administrador.
-- Se niega si la Fase 3 no está aplicada o si el flujo no está cargado. Repetirlo no cambia nada.
-- Después de encenderla, la fila 06 de la verificación de la Fase 3 (que espera «espera_dato») deja de valer: vale la consulta del final de este archivo.
-- Para apagarla (no se borra):  update redes.geovisor_capas set estado = 'espera_dato' where codigo = 'flujo_modelo';
-- =====================================================================
do $$
begin
  if to_regclass('redes.flujo_modelo') is null or not exists (select 1 from redes.geovisor_capas where codigo = 'flujo_modelo' and activa) then
    raise exception 'La Fase 3 del Corte 9b no está aplicada: deténgase y avise';
  end if;
  if not exists (select 1 from redes.flujo_modelo f where f.carga_id = redes.f_ref_vigente('flujo_modelo')) then
    raise exception 'El flujo del modelo no está cargado (carga_flujo_modelo.sql): la capa no se enciende vacía';
  end if;
  update redes.geovisor_capas set estado = 'activa' where codigo = 'flujo_modelo' and estado <> 'activa';
end $$;
-- verificación: debe decir «activa · preparada · solo supervisores: sí» y los tubos cargados
select codigo, estado || ' · ' || fuente || ' · solo supervisores: ' || case when solo_completo then 'sí' else 'no' end as capa,
       (select count(*) from redes.flujo_modelo f where f.carga_id = redes.f_ref_vigente('flujo_modelo')) as tubos_cargados
  from redes.geovisor_capas where codigo = 'flujo_modelo';
