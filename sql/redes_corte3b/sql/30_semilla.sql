-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 30 — SEMILLA: parámetro de la foto principal
-- =====================================================================
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('max_bytes_foto_perfil', 1572864, 'bytes', 102400, 2097152, 'Tope de la foto principal (perfil) de un activo (1,5 MB)')
on conflict (clave) do nothing;   -- si una reversa anterior lo conservó (redes.parametros no deja borrar filas), se reutiliza con su valor
