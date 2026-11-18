-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 26 · FUNCIONES
-- =====================================================================
-- Quién es un funcionario para el acta: nombre, área y cargo. En Técnica, el área y el cargo de Personal de distribución; en Comercial, el cargo de su Personal.
create function redes.f_levantar_funcionario(p_email text, p_area text default null) returns jsonb
language sql stable security definer set search_path to 'public', 'redes', 'campo', 'pg_temp' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'nombre', redes.f_levantar_quien(p_email),
    'area', case when p_area = 'comercial' then 'Comercial'
                 else coalesce((select case f.area when 'distribucion' then 'Técnica · Distribución' when 'planta' then 'Técnica · Plantas' when 'ambas' then 'Técnica · Plantas y Distribución' end
                                  from redes.v_personal_ficha f where f.persona = p_email), 'Técnica') end,
    'cargo', case when p_area = 'comercial' then campo.f_cargo_vigente(p_email)
                  else coalesce((select nullif(btrim(f.cargo), '') from redes.v_personal_ficha f where f.persona = p_email), campo.f_cargo_vigente(p_email)) end))
$$;

-- El acta de un punto por levantar (para el PDF con la hoja membretada). La ve quien reportó el punto (la suya) y el supervisor de distribución y el
-- administrador (todas). La Edge firma la lectura de las fotos (60 s). La consulta queda en la auditoría.
create function public.geoportal_redes_levantar_acta(p_solicitante text, p_codigo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'campo', 'extensions', 'pg_temp' as $$
declare a record; v_cod text := upper(btrim(coalesce(p_codigo, ''))); p record; v_fotos jsonb; v_hist jsonb;
begin
  select * into a from redes.f_levantar_acceso(p_solicitante);
  if v_cod !~ '^LEV-[0-9]{6}$' then perform tecnica.f_error('Ese código no es de un activo por levantar'); end if;
  select * into p from redes.v_levantar_punto x where x.codigo = v_cod;
  if not found then perform tecnica.f_error('Ese activo por levantar no existe', 'P0002'); end if;
  if a.perfil not in ('admin', 'supervisor') and p.autor <> a.email then
    raise exception 'Solo quien reportó el activo, el supervisor de distribución o el administrador ven esta acta' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('n', f.n, 'ruta', f.ruta_storage, 'creado_en', f.creado_en) order by f.n), '[]'::jsonb) into v_fotos from redes.levantar_fotos f where f.punto_id = p.id;
  select coalesce(jsonb_agg(jsonb_build_object('que', case e.tipo when 'asignado' then 'Asignado a levantamiento' when 'levantado' then 'Levantado' when 'descartado' then 'Descartado' else 'Reabierto' end,
                    'tipo', e.tipo, 'cuando', e.creado_en, 'quien', redes.f_levantar_funcionario(e.autor) ->> 'nombre', 'motivo', e.motivo,
                    'activo', (select x.codigo from redes.activos x where x.id = e.activo_id)) order by e.id), '[]'::jsonb)
    into v_hist from redes.levantar_eventos e where e.punto_id = p.id;
  perform tecnica.f_auditar(a.email, 'redes_levantar_acta', v_cod, jsonb_build_object('fotos', jsonb_array_length(v_fotos), 'propia', p.autor = a.email), p_ip);
  return jsonb_build_object('codigo', p.codigo, 'generado_en', clock_timestamp(), 'servicio', p.servicio, 'tipo', p.tipo, 'tipo_nombre', redes.f_levantar_tipo_nombre(p.tipo),
    'observacion', p.observacion, 'lat', p.lat, 'lon', p.lon, 'precision_m', p.precision_m, 'precision_baja', p.precision_baja, 'registrado_en', p.registrado_en,
    'sector', (select s.nombre from redes.f_sector_de(p.geom) s),
    'reporto', redes.f_levantar_funcionario(p.autor, p.area),
    'estado', p.estado, 'estado_nombre', redes.f_levantar_estado_nombre(p.estado), 'estado_desde', p.estado_desde,
    'activo', (select x.codigo from redes.activos x where x.id = p.activo_id),
    'historial', jsonb_build_array(jsonb_build_object('que', 'Reportado', 'tipo', 'reportado', 'cuando', p.registrado_en, 'quien', redes.f_levantar_funcionario(p.autor, p.area) ->> 'nombre')) || v_hist,
    'fotos', v_fotos);
end $$;
