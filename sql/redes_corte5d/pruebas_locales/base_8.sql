-- Doble local de lo que el Corte 8 (Code A, publicado el 16-nov) dejó en producción y que el 5d toca o necesita. Solo en el clúster de Code B.
-- · el dominio tecnica.formulario_clave con las dos claves nuevas (texto exacto de migracion_tecnica_corte8_editor.sql, sección 2);
-- · public.predios_comercial como VISTA MATERIALIZADA, como en producción (nadie la escribe ni la refresca; el arnés comprueba que escribir en ella falla).
alter domain tecnica.formulario_clave drop constraint formulario_clave_ck;
alter domain tecnica.formulario_clave add constraint formulario_clave_ck check (value in
  ('entrada', 'salida', 'muestreo', 'danos_fallas', 'mantenimiento', 'uso_quimicos', 'entrada_quimicos', 'anomalia_compartida', 'revision_compartida'));
create materialized view if not exists public.predios_comercial as
  select distinct on (cod_usuario) cod_usuario, ST_Y(geom) as lat, ST_X(geom) as lon, barrio from public.catastro_valledupar
   where cod_usuario ~ '^[0-9]+$' and cod_usuario <> '0' order by cod_usuario, id;
