-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 90 — REVERSA
-- Vuelve preparar_subida a su texto publicado ({{MD5_PREPARAR}}) y deja la Investigación de ubicación como estaba en producción el 23-nov:
-- con resultado, fotos 3 a 6, las 3 fotos obligatorias (fachada y predio como soporte de la inefectiva), dirección opcional, hallazgo
-- obligatorio y los 4 campos de despeje y visita activos. Nada se borra: los 4 campos nuevos quedan DESACTIVADOS (activo = false), y los
-- registros que se hayan hecho con ellos conservan sus datos.
-- =====================================================================
do $rev$
declare v_t bigint;
begin
  if md5(pg_get_functiondef('public.geoportal_campo_preparar_subida(text,integer,text,text,text)'::regprocedure)) is distinct from '{{MD5_PREPARAR_NUEVA}}' then
    raise exception 'preparar_subida no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise';
  end if;
  select id into v_t from campo.tipos_reporte where codigo = 'investigacion_ubicacion' and not genera_resultado and fotos_min = 0;
  if not found then raise exception 'La Investigación de ubicación no está como la deja este paquete: deténgase y avise'; end if;
end $rev$;

{{RESPALDO_PREPARAR}}

do $rev_inv$
declare v_t bigint; v_antes jsonb; v_despues jsonb;
begin
  select id into v_t from campo.tipos_reporte where codigo = 'investigacion_ubicacion';
  select jsonb_build_object('tipo', (select to_jsonb(t) from campo.tipos_reporte t where t.id = v_t),
                            'campos', (select jsonb_agg(to_jsonb(c) order by c.orden, c.id) from campo.tipo_campos c where c.tipo_id = v_t),
                            'fotos', (select jsonb_agg(to_jsonb(f) order by f.orden, f.id) from campo.tipo_fotos f where f.tipo_id = v_t)) into v_antes;
  update campo.tipos_reporte set genera_resultado = true, fotos_min = 3 where id = v_t;
  update campo.tipo_fotos set obligatoria = true where tipo_id = v_t and codigo in ('fachada_nomenclatura', 'predio_lote', 'vecino_referencia');
  update campo.tipo_fotos set soporte_inefectiva = true where tipo_id = v_t and codigo in ('fachada_nomenclatura', 'predio_lote');
  update campo.tipo_campos set obligatorio = false where tipo_id = v_t and codigo = 'direccion_encontrada';
  update campo.tipo_campos set obligatorio = true where tipo_id = v_t and codigo = 'hallazgo';
  update campo.tipo_campos set activo = true where tipo_id = v_t and codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada', 'cita_acordada');
  update campo.tipo_campos set activo = false where tipo_id = v_t and codigo in ('barrio', 'habitado', 'tipo_predio', 'medidor');
  select jsonb_build_object('tipo', (select to_jsonb(t) from campo.tipos_reporte t where t.id = v_t),
                            'campos', (select jsonb_agg(to_jsonb(c) order by c.orden, c.id) from campo.tipo_campos c where c.tipo_id = v_t),
                            'fotos', (select jsonb_agg(to_jsonb(f) order by f.orden, f.id) from campo.tipo_fotos f where f.tipo_id = v_t)) into v_despues;
  perform campo.f_auditar('migracion@geoportal', 'campo_catalogo', 'tipo:investigacion_ubicacion',
                          jsonb_build_object('paquete', 'campo_inv_analisis', 'reversa', true, 'antes', v_antes, 'despues', v_despues), null);
end $rev_inv$;
