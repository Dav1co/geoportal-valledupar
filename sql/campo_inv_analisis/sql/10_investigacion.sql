-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 10 — Investigación de ubicación del predio (INV), decisiones de David del 23-nov
-- Obligatorios: contrato (ya), dirección encontrada en terreno (pasa a obligatoria) y XY (ya lo exigen la RPC y la pantalla).
-- Opcionales: hallazgo (deja de ser obligatorio), barrio (texto), ¿habitado? (sí o no), tipo de predio (opción), medidor (texto), observación.
-- Sin resultado (efectiva / inefectiva) ni causal; las 3 fotos opcionales y sin marca de soporte; de 0 a 6 fotos.
-- Se DESACTIVAN (no se borran): despeje_caja, despeje_observacion, visita_concertada y cita_acordada.
-- Las causales enlazadas quedan como están (Q4): sin resultado, ni la RPC ni la pantalla las piden.
-- Todo queda auditado (campo_catalogo) con el antes y el después.
-- =====================================================================
do $inv$
declare v_t bigint; v_antes jsonb; v_despues jsonb; v_n record;
begin
  select id into v_t from campo.tipos_reporte where codigo = 'investigacion_ubicacion';
  select jsonb_build_object('tipo', (select to_jsonb(t) from campo.tipos_reporte t where t.id = v_t),
                            'campos', (select jsonb_agg(to_jsonb(c) order by c.orden, c.id) from campo.tipo_campos c where c.tipo_id = v_t),
                            'fotos', (select jsonb_agg(to_jsonb(f) order by f.orden, f.id) from campo.tipo_fotos f where f.tipo_id = v_t)) into v_antes;

  update campo.tipos_reporte set genera_resultado = false, fotos_min = 0 where id = v_t;
  update campo.tipo_fotos set obligatoria = false, soporte_inefectiva = false
   where tipo_id = v_t and codigo in ('fachada_nomenclatura', 'predio_lote', 'vecino_referencia');
  update campo.tipo_campos set obligatorio = true where tipo_id = v_t and codigo = 'direccion_encontrada';
  update campo.tipo_campos set obligatorio = false where tipo_id = v_t and codigo = 'hallazgo';
  update campo.tipo_campos set activo = false where tipo_id = v_t and codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada', 'cita_acordada');
  -- Los 4 campos nuevos: se crean; si una reversa anterior los dejó desactivados, se reactivan (nada se borra ni se duplica)
  for v_n in select * from jsonb_to_recordset('[
      {"codigo": "barrio", "nombre": "Barrio", "tipo_dato": "texto", "opciones": null, "maximo": 80, "ayuda": null, "orden": 3},
      {"codigo": "habitado", "nombre": "¿El predio está habitado?", "tipo_dato": "si_no", "opciones": null, "maximo": null, "ayuda": null, "orden": 4},
      {"codigo": "tipo_predio", "nombre": "Tipo de predio", "tipo_dato": "opcion",
       "opciones": [{"codigo": "casa", "nombre": "Casa"}, {"codigo": "apartamento", "nombre": "Apartamento"}, {"codigo": "edificio", "nombre": "Edificio"},
                    {"codigo": "comercio", "nombre": "Comercio"}, {"codigo": "lote_desocupado", "nombre": "Lote desocupado"}, {"codigo": "demolido", "nombre": "Demolido"}],
       "maximo": null, "ayuda": null, "orden": 5},
      {"codigo": "medidor", "nombre": "Número del medidor (si se ve)", "tipo_dato": "texto", "opciones": null, "maximo": 20,
       "ayuda": "Tal como aparece en el medidor; si no hay o no se ve, déjelo vacío", "orden": 6}
    ]'::jsonb) as x(codigo text, nombre text, tipo_dato text, opciones jsonb, maximo numeric, ayuda text, orden integer) loop
    if exists (select 1 from campo.tipo_campos where tipo_id = v_t and codigo = v_n.codigo) then
      update campo.tipo_campos set activo = true, obligatorio = false where tipo_id = v_t and codigo = v_n.codigo;
    else
      insert into campo.tipo_campos (tipo_id, codigo, nombre, tipo_dato, obligatorio, opciones, maximo, ayuda, orden)
      values (v_t, v_n.codigo, v_n.nombre, v_n.tipo_dato, false, v_n.opciones, v_n.maximo, v_n.ayuda, v_n.orden);
    end if;
  end loop;

  select jsonb_build_object('tipo', (select to_jsonb(t) from campo.tipos_reporte t where t.id = v_t),
                            'campos', (select jsonb_agg(to_jsonb(c) order by c.orden, c.id) from campo.tipo_campos c where c.tipo_id = v_t),
                            'fotos', (select jsonb_agg(to_jsonb(f) order by f.orden, f.id) from campo.tipo_fotos f where f.tipo_id = v_t)) into v_despues;
  perform campo.f_auditar('migracion@geoportal', 'campo_catalogo', 'tipo:investigacion_ubicacion',
                          jsonb_build_object('paquete', 'campo_inv_analisis', 'antes', v_antes, 'despues', v_despues), null);
end $inv$;
