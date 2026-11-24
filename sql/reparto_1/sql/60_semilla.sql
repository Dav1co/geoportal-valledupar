-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 60 — SEMILLA: los parámetros iniciales (versionados; un cambio es una fila nueva)
-- =====================================================================
insert into reparto.parametros (clave, valor, nota, autor) values
  ('ventana_dias', '5', 'Días (contando hoy) en que una factura entregada no se vuelve a ofrecer ni se deja registrar otra vez (cualquier repartidor u origen).', 'migracion@geoportal'),
  ('lote_vigencia_dias', '45', 'Días en que un archivo de ruta cargado por el supervisor se ofrece a los repartidores.', 'migracion@geoportal'),
  ('tope_filas_lote', '10000', 'Filas máximas de un archivo de ruta o de ciclo (el ciclo más grande tiene unos 9.100 contratos).', 'migracion@geoportal'),
  ('precision_mala_m', '30', 'Precisión del GPS (metros) desde la que una entrega queda marcada como imprecisa (P8). Se registra igual.', 'migracion@geoportal');
