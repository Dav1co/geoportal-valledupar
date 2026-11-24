-- [Code B] INVESTIGACIÓN Y ANÁLISIS (23-nov) · REVERSA (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 90 — REVERSA
-- Vuelve preparar_subida a su texto publicado (6a2ef927316ed4aa2936eadfb9b0a0cd) y deja la Investigación de ubicación como estaba en producción el 23-nov:
-- con resultado, fotos 3 a 6, las 3 fotos obligatorias (fachada y predio como soporte de la inefectiva), dirección opcional, hallazgo
-- obligatorio y los 4 campos de despeje y visita activos. Nada se borra: los 4 campos nuevos quedan DESACTIVADOS (activo = false), y los
-- registros que se hayan hecho con ellos conservan sus datos.
-- =====================================================================
do $rev$
declare v_t bigint;
begin
  if md5(pg_get_functiondef('public.geoportal_campo_preparar_subida(text,integer,text,text,text)'::regprocedure)) is distinct from 'a00d66705d7a0c88a38ab5d882153669' then
    raise exception 'preparar_subida no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise';
  end if;
  select id into v_t from campo.tipos_reporte where codigo = 'investigacion_ubicacion' and not genera_resultado and fotos_min = 0;
  if not found then raise exception 'La Investigación de ubicación no está como la deja este paquete: deténgase y avise'; end if;
end $rev$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_preparar_subida(p_solicitante text, p_cantidad integer, p_origen text DEFAULT 'campo'::text, p_ip text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v_perfil text; v_id uuid := gen_random_uuid(); v_mes text := to_char(campo.f_ahora_bogota(), 'YYYY-MM'); v_max integer := campo.f_param('max_fotos')::integer; v_tmax smallint;
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);
  v_perfil := campo.f_perfil(v_email);
  if coalesce(p_origen, '') not in ('campo', 'escritorio') then perform campo.f_error('El origen debe ser campo o escritorio'); end if;
  if p_origen = 'escritorio' and v_perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador crean reportes desde el escritorio' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_tipo, '')), '') is not null then
    select t.fotos_max into v_tmax from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id where t.codigo = btrim(p_tipo) and t.activo and g.activo;
    if not found then perform campo.f_error('El tipo de reporte no existe o está desactivado'); end if;
    v_max := coalesce(v_tmax, v_max);
  end if;
  if p_cantidad is null or p_cantidad < (case when p_origen = 'campo' then 1 else 0 end) or p_cantidad > v_max then
    perform campo.f_error(format('La cantidad de fotos debe estar entre %s y %s', case when p_origen = 'campo' then 1 else 0 end, v_max));
  end if;
  perform campo.f_cupo_preparaciones(v_email, v_perfil);   -- Paso B1
  insert into campo.preparaciones (reporte_id, autor) values (v_id, v_email);
  return jsonb_build_object('reporte_id', v_id, 'bucket', 'campo-fotos', 'max_bytes_foto', campo.f_param('max_bytes_foto')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', n, 'ruta', 'reportes/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n)
                         from generate_series(1, p_cantidad) n), '[]'::jsonb));
end $function$;

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

commit;
