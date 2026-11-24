-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 60 — SEMILLA: los parámetros iniciales (versionados; un cambio es una fila nueva)
-- =====================================================================
insert into reparto.parametros (clave, valor, nota, autor) values
  ('respaldo_dias', '15', 'Respaldo cuando al ciclo le falta la fecha de reparto en el calendario: días (contando hoy) en que una factura entregada no se vuelve a ofrecer.', 'migracion@geoportal'),
  ('lote_vigencia_dias', '45', 'Días en que un archivo de ruta cargado por el supervisor se ofrece a los repartidores.', 'migracion@geoportal'),
  ('tope_filas_lote', '10000', 'Filas máximas de un archivo de ruta o de ciclo (el ciclo más grande tiene unos 9.100 contratos).', 'migracion@geoportal'),
  ('precision_mala_m', '30', 'Precisión del GPS (metros) desde la que una entrega queda marcada como imprecisa (P8). Se registra igual.', 'migracion@geoportal');

-- La actividad «Supervisión de reparto» en Personal de Comercial (David, 23-nov). Es una fila del catálogo de campo (dato, no función: la huella de campo no
-- cambia). Si ya existiera (una reaplicación tras la reversa, que la desactiva), se vuelve a activar.
insert into campo.actividades (codigo, nombre, orden, formularios, autor) values ('supervision_reparto', 'Supervisión de reparto', 11, '{}', 'migracion@geoportal')
  on conflict (codigo) do update set activa = true;
