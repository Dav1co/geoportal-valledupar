-- =====================================================================
-- ETIQUETA DEL ÚLTIMO PAGO (Code A, 27-nov; aprobado por David) · 30 — CAMBIO
-- geoportal_campo_analisis_contrato deja de quitar el «corte» del pago: la respuesta lleva pago.corte (periodo AAAAMM de la fuente: hechos.cupones_pagos
-- si fuente = cupones, hechos.cartera_contrato si fuente = cartera), para que la pantalla diga «pagos a oct-2026» o «cartera mensual a sep-2026».
-- Única diferencia con la publicada:  f.ultimo_pago - 'corte' || jsonb_build_object(...)  →  f.ultimo_pago || jsonb_build_object(...)
-- CREATE OR REPLACE conserva el dueño y los permisos (solo service_role); la verificación lo comprueba.
-- =====================================================================
{{FUNCION_NUEVA}}
