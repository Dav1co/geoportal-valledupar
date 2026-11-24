-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 20 — preparar_subida admite 0 fotos SOLO si el formato informado tiene fotos_min = 0
-- Lo demás no cambia: sin tipo, o con un tipo de mínimo 1 o más (o sin mínimo), desde campo se sigue exigiendo al menos 1 foto.
-- La preparación con 0 fotos reserva el identificador y cuenta en el cupo, como hoy. CREATE OR REPLACE conserva los permisos.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.geoportal_campo_preparar_subida(p_solicitante text, p_cantidad integer, p_origen text DEFAULT 'campo'::text, p_ip text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v_perfil text; v_id uuid := gen_random_uuid(); v_mes text := to_char(campo.f_ahora_bogota(), 'YYYY-MM'); v_max integer := campo.f_param('max_fotos')::integer; v_tmax smallint; v_tmin smallint; v_min integer;
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);
  v_perfil := campo.f_perfil(v_email);
  if coalesce(p_origen, '') not in ('campo', 'escritorio') then perform campo.f_error('El origen debe ser campo o escritorio'); end if;
  if p_origen = 'escritorio' and v_perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador crean reportes desde el escritorio' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_tipo, '')), '') is not null then
    select t.fotos_max, t.fotos_min into v_tmax, v_tmin from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id where t.codigo = btrim(p_tipo) and t.activo and g.activo;
    if not found then perform campo.f_error('El tipo de reporte no existe o está desactivado'); end if;
    v_max := coalesce(v_tmax, v_max);
  end if;
  -- Investigación y Análisis (23-nov): desde campo se exige al menos 1 foto, salvo que el formato informado tenga fotos_min = 0
  v_min := case when p_origen = 'campo' and v_tmin is distinct from 0 then 1 else 0 end;
  if p_cantidad is null or p_cantidad < v_min or p_cantidad > v_max then
    perform campo.f_error(format('La cantidad de fotos debe estar entre %s y %s', v_min, v_max));
  end if;
  perform campo.f_cupo_preparaciones(v_email, v_perfil);   -- Paso B1
  insert into campo.preparaciones (reporte_id, autor) values (v_id, v_email);
  return jsonb_build_object('reporte_id', v_id, 'bucket', 'campo-fotos', 'max_bytes_foto', campo.f_param('max_bytes_foto')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', n, 'ruta', 'reportes/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n)
                         from generate_series(1, p_cantidad) n), '[]'::jsonb));
end $function$;
