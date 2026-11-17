-- Lo que el Corte 8 (ya publicado) cambió en tecnica: las dos claves de los reportes compartidos con Comercial en el dominio de formularios.
-- La base de redes de Code A no lo tenía (el 8 se probó en la base de campo); el 5d lo exige. Mismo texto que sql/campo_corte8/migracion_tecnica_corte8_editor.sql.
alter domain tecnica.formulario_clave drop constraint formulario_clave_ck;
alter domain tecnica.formulario_clave add constraint formulario_clave_ck check (value in
  ('entrada', 'salida', 'muestreo', 'danos_fallas', 'mantenimiento', 'uso_quimicos', 'entrada_quimicos', 'anomalia_compartida', 'revision_compartida'));
