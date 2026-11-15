-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 30 — SEMILLA: catálogos del daño (de la maqueta Dano.dc.html) y parámetros
-- =====================================================================
insert into redes.tipos_dano (codigo, clase, nombre, sistemas, pide_rotura, orden) values
  ('fuga', 'dano', 'Fuga o tubería rota', array['acueducto'], true, 1),
  ('valvula_danada', 'dano', 'Válvula dañada', array['acueducto'], true, 2),
  ('hundimiento', 'dano', 'Hundimiento o colapso', array['acueducto', 'alcantarillado'], false, 3),
  ('rebose', 'dano', 'Rebose de alcantarillado', array['alcantarillado'], false, 4),
  ('tubo_roto_alc', 'dano', 'Tubo roto o colapsado', array['alcantarillado'], false, 5),
  ('tapa', 'dano', 'Tapa o rejilla', array['alcantarillado'], false, 6),
  ('otro_dano', 'dano', 'Otro daño', array['acueducto', 'alcantarillado'], false, 9),
  ('bombeo', 'falla', 'Falla de bombeo', array['acueducto', 'alcantarillado'], false, 11),
  ('electrica', 'falla', 'Falla eléctrica', array['acueducto', 'alcantarillado'], false, 12),
  ('valvula_no_opera', 'falla', 'Válvula que no opera', array['acueducto'], false, 13),
  ('obstruccion', 'falla', 'Obstrucción', array['alcantarillado'], false, 14),
  ('sensor', 'falla', 'Sensor o equipo', array['acueducto', 'alcantarillado'], false, 15),
  ('otra_falla', 'falla', 'Otra falla', array['acueducto', 'alcantarillado'], false, 19);
insert into redes.tipos_rotura (codigo, nombre, orden) values ('fisura', 'Fisura', 1), ('union', 'Fuga en la unión', 2), ('parcial', 'Rotura parcial', 3), ('total', 'Rotura total', 4);
insert into redes.causas (codigo, nombre, orden) values
  ('desgaste', 'Desgaste o vejez de la tubería', 1), ('sobrepresion', 'Sobrepresión o golpe de ariete', 2), ('falla_material', 'Falla del material o de la unión', 3),
  ('asentamiento', 'Asentamiento del terreno', 4), ('obstruccion', 'Obstrucción (grasas, sedimentos, basura)', 5), ('otra', 'Otra', 9);
insert into redes.tipos_tercero (codigo, nombre, orden) values
  ('obra_alcaldia', 'Obra de la alcaldía', 1), ('contratista_obra', 'Contratista de obra', 2), ('empresa_servicio', 'Empresa de otro servicio (gas, energía, telecomunicaciones)', 3),
  ('particular', 'Particular', 4), ('vehiculo', 'Vehículo', 5), ('vandalismo', 'Vandalismo', 6);
insert into redes.marcas_riesgo (codigo, nombre, orden) values
  ('via', 'Hueco o hundimiento en la vía', 1), ('personas', 'Riesgo para personas o vehículos', 2), ('contaminacion', 'Posible contaminación del agua', 3),
  ('usuario_sensible', 'Afecta un hospital, colegio u otro usuario sensible', 4);
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('dano_dias_atras_max', 7, 'días', 1, 60, 'Cuánto atrás puede ser la hora de detección de un daño (D-25)'),
  ('min_fotos_dano', 1, 'fotos', 0, 10, 'Fotos mínimas de un daño o falla (al menos una del daño)'),
  ('max_fotos_dano', 6, 'fotos', 1, 10, 'Fotos máximas de un daño o falla'),
  ('max_bytes_foto_dano', 1572864, 'bytes', 102400, 2097152, 'Tope fino de cada foto del daño (1,5 MB); el bucket admite hasta 5 MB por los PDF'),
  ('mini_zoom_min', 15, 'zoom', 12, 18, 'Desde qué zoom el minimapa pide la red'),
  ('mini_zoom_acc', 17, 'zoom', 14, 20, 'Desde qué zoom el minimapa muestra los accesorios')
on conflict (clave) do nothing;   -- si una reversa anterior los conservó (redes.parametros no deja borrar filas), se reutilizan con su valor
