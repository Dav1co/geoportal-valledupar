-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 90 — REVERSA
-- Vuelve preparar_subida y las 4 funciones de las derivadas a su texto publicado, quita las 6 funciones nuevas, desactiva los 5 códigos del
-- catálogo de derivadas (las tablas nuevas y las columnas de campo.derivadas se conservan: nada se borra) y deja la Investigación de ubicación como estaba en producción el 23-nov:
-- con resultado, fotos 3 a 6, las 3 fotos obligatorias (fachada y predio como soporte de la inefectiva), dirección opcional, hallazgo
-- obligatorio y los 4 campos de despeje y visita y la observación activos. Nada se borra: los 4 campos nuevos quedan DESACTIVADOS (activo = false), y los
-- registros que se hayan hecho con ellos conservan sus datos.
-- =====================================================================
do $rev$
declare v_t bigint; r record; v_n bigint;
begin
  if md5(pg_get_functiondef('public.geoportal_campo_preparar_subida(text,integer,text,text,text)'::regprocedure)) is distinct from '{{MD5_PREPARAR_NUEVA}}' then
    raise exception 'preparar_subida no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise';
  end if;
  for r in select * from (values {{MD5_CAMBIAN_NUEVA}}) x(f, m) loop
    if md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % cambió después de este paquete: la reversa no la pisa; deténgase y avise', r.f;
    end if;
  end loop;
  -- Con avisos guardados, las funciones publicadas de las derivadas (join estricto con campo.reportes) dejarían filas vacías en «Actividades derivadas»
  select count(*) into v_n from campo.derivadas where observacion_id is not null;
  if v_n > 0 then
    raise exception 'Hay % avisos o actividades del Análisis de contrato: revertir dejaría filas vacías en «Actividades derivadas». Deténgase y avise (no se revierte nada)', v_n;
  end if;
  select id into v_t from campo.tipos_reporte where codigo = 'investigacion_ubicacion' and not genera_resultado and fotos_min = 0;
  if not found then raise exception 'La Investigación de ubicación no está como la deja este paquete: deténgase y avise'; end if;
end $rev$;

{{RESPALDO_PREPARAR}}

{{RESPALDO_DERIVADA_JSON}}

{{RESPALDO_DERIVADAS}}

{{RESPALDO_ATENDER}}

{{RESPALDO_ABIERTAS}}

-- DROP (por qué y alcance): las 6 funciones las creó este paquete; con las 4 de las derivadas ya devueltas a su texto publicado, nadie las usa,
-- y la huella de campo vuelve a {{HUELLA_CAMPO}}. Alcance: SOLO esas 6 firmas; no toca tablas, datos ni otras funciones.
drop function public.geoportal_campo_aviso_datos_anular(text, bigint, text, text);
drop function public.geoportal_campo_aviso_datos(text, bigint, text);
drop function public.geoportal_campo_aviso_crear_actividad(text, bigint, text, text);
drop function public.geoportal_campo_analisis_observar(text, text, text, text, text, jsonb, text);
drop function campo.f_texto_sin_datos(text, text, integer, integer);
drop function campo.f_contacto(jsonb);

-- Los 5 códigos del catálogo de derivadas quedan desactivados (nada se borra). Las tablas nuevas y las columnas de campo.derivadas se conservan.
update campo.derivadas_catalogo set activa = false
 where codigo in ('aviso_desocupado', 'aviso_direccion_errada', 'aviso_actualizacion_datos', 'aviso_otra', 'actividad_supervisor');

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
  update campo.tipo_campos set activo = true where tipo_id = v_t and codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada', 'cita_acordada', 'observacion');
  update campo.tipo_campos set activo = false where tipo_id = v_t and codigo in ('barrio', 'habitado', 'tipo_predio', 'medidor');
  select jsonb_build_object('tipo', (select to_jsonb(t) from campo.tipos_reporte t where t.id = v_t),
                            'campos', (select jsonb_agg(to_jsonb(c) order by c.orden, c.id) from campo.tipo_campos c where c.tipo_id = v_t),
                            'fotos', (select jsonb_agg(to_jsonb(f) order by f.orden, f.id) from campo.tipo_fotos f where f.tipo_id = v_t)) into v_despues;
  perform campo.f_auditar('migracion@geoportal', 'campo_catalogo', 'tipo:investigacion_ubicacion',
                          jsonb_build_object('paquete', 'campo_inv_analisis', 'reversa', true, 'antes', v_antes, 'despues', v_despues), null);
end $rev_inv$;
