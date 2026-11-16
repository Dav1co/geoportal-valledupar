-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 30 — SEMILLA: los cinco tipos de intervención (maqueta Intervencion.dc.html), unidades de los materiales y parámetros
-- =====================================================================
insert into redes.tipos_intervencion (codigo, nombre, admite_dano, es_inversion, orden) values
  ('preventivo', 'Mantenimiento preventivo', false, false, 1),
  ('correctivo', 'Mantenimiento correctivo', true, false, 2),
  ('reparacion', 'Reparación', true, false, 3),
  ('reposicion', 'Reposición', true, false, 4),
  ('inversion', 'Inversión', false, true, 5);
insert into redes.unidades_material (codigo, nombre, orden) values
  ('und', 'unidad', 1), ('m', 'metro', 2), ('m2', 'm²', 3), ('m3', 'm³', 4), ('kg', 'kg', 5), ('l', 'litro', 6), ('bolsa', 'bolsa', 7), ('global', 'global', 9);
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('itv_dias_atras_max', 7, 'días', 1, 60, 'Cuánto atrás puede empezar una intervención que se registra después de hecha (flujo A)'),
  ('itv_max_horas', 72, 'horas', 1, 720, 'Duración máxima de una intervención (de su inicio a su fin); si duró más, se registra por partes'),
  ('min_fotos_itv', 1, 'fotos', 1, 10, 'Fotos mínimas de una intervención registrada en la calle (el supervisor o el administrador pueden registrar sin fotos, con motivo)'),
  ('max_fotos_itv', 9, 'fotos', 1, 20, 'Fotos máximas de una intervención (antes, durante y después)'),
  ('max_docs_itv', 3, 'documentos', 0, 10, 'Documentos PDF máximos de una intervención (orden, acta, factura)'),
  ('max_bytes_foto_itv', 1572864, 'bytes', 102400, 2097152, 'Tope fino de cada foto de la intervención (1,5 MB)'),
  ('max_bytes_doc_itv', 5242880, 'bytes', 102400, 5242880, 'Tope de cada documento PDF de la intervención (5 MB, el tope del bucket)'),
  ('itv_radio_danos_m', 150, 'm', 10, 1000, 'Radio para proponer los daños abiertos cercanos que atiende una intervención'),
  ('itv_radio_propuesta_m', 50, 'm', 5, 500, 'Radio para proponer los activos más cercanos a un registro «no identificado» (bandeja del supervisor)'),
  ('itv_max_activos_tambien', 10, 'activos', 1, 30, 'Activos también intervenidos, como máximo, además del principal'),
  ('itv_max_materiales', 20, 'materiales', 1, 50, 'Materiales por intervención, como máximo')
on conflict (clave) do nothing;   -- si una reversa anterior los conservó (redes.parametros no deja borrar filas), se reutilizan con su valor
