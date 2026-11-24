-- =====================================================================
-- VOLUMEN SOLO LOCAL (Code A, reparto): el tamaño de producción para medir tiempos (consulta B del 23-nov).
--  · hechos.rutas_consecutivos: 6 períodos (202605 a 202610) de 113.801 filas; 361 rutas en 25 ciclos (el 9999 con 148 contratos); rutas de 1 a 977;
--    consecutivo_ruta disperso (saltos de ~1.000.000) con unos 160 empates; 3 contratos repetidos en el último período. Contratos sintéticos 1xxxxxxxx.
--  · public.cartera_suscripcion: 111.000 filas sintéticas (233 sin ruta).
-- Sin datos reales. Las pruebas usan otros contratos (88…) y otro ciclo (8801).
-- =====================================================================
insert into hechos.rutas_consecutivos (ciclo, consecutivo_ruta, ruta, contrato, direccion, consecutivo_predio, periodo, archivo_origen, fecha_carga)
select case when g <= 148 then '9999' else (1 + (g % 24))::text end,
       case when g % 700 = 0 then (((g / 361) - 1) * 1000000)::text else ((g / 361) * 1000000 + (g % 7))::text end,
       case when g <= 148 then '9999' || (g % 9) else (100000 + (1 + (g % 24)) * 1000 + (g % 352) / 24)::text end,
       (100000000 + g)::text, 'CALLE SINTÉTICA', (g % 5000)::text, p.periodo, 'INFORME_RUTAS_CONSECUTIVOS_' || p.periodo || '.xlsx', '2026-11-01'
  from generate_series(1, 113798) g, (values ('202605'), ('202606'), ('202607'), ('202608'), ('202609'), ('202610')) p(periodo);
insert into hechos.rutas_consecutivos (ciclo, consecutivo_ruta, ruta, contrato, direccion, consecutivo_predio, periodo, archivo_origen, fecha_carga)
select ciclo, (consecutivo_ruta::bigint + 5)::text, ruta, contrato, direccion, consecutivo_predio, periodo, archivo_origen, fecha_carga
  from hechos.rutas_consecutivos where periodo = '202610' and contrato in ('100000500', '100000600', '100000700');
insert into public.cartera_suscripcion (contrato, estado, ciclo, periodo_carga)
select (100000000 + g)::text, 'ACTIVO', (1 + (g % 24))::text, '202611' from generate_series(1, 110767) g
union all select (300000000 + g)::text, 'ACTIVO', '1', '202611' from generate_series(1, 233) g;
analyze hechos.rutas_consecutivos;
analyze public.cartera_suscripcion;
