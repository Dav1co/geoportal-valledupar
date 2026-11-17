-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 — PROPUESTA DE USUARIOS SENSIBLES (se corre UNA vez después de la migración, por psql o en el editor SQL; se puede repetir).
-- Recorre el último período de la cartera y propone los contratos cuyo nombre trae una palabra de la lista (hospital, clínica, colegio…).
-- Guarda el contrato, el tipo y la PALABRA que coincidió; nunca el nombre. Quedan «por confirmar»: el supervisor los confirma o descarta en su bandeja.
-- Cambie el correo por el de un administrador. Devuelve cuántos propuso (los que ya estaban no se repiten).
-- =====================================================================
select redes.f_sensibles_proponer('CORREO_DEL_ADMINISTRADOR@emdupar.gov.co') as propuestos;
select t.nombre as tipo, count(*) as por_confirmar from redes.v_usuario_sensible v join redes.tipos_sensible t on t.codigo = v.tipo where v.estado = 'por_confirmar' group by t.nombre, t.orden order by t.orden;
