begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 10 · GUARDIA («Acta del reporte de activo», una por punto por levantar)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code B). Generado por pruebas_locales/generar.py.
-- · Presupone el Corte 14 publicado completo (huella del conjunto de funciones de redes 1a9ef250a74fb01962f463d98834cc4a).
-- · Solo agrega DOS funciones (una interna y una RPC). No crea tablas, no cambia ninguna función y no toca nada fuera de redes.
-- · Sin datos de suscriptores: «quién» es siempre un funcionario (nombre, área y cargo).
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_levantar_acta(text,text,text)') is not null then raise exception 'El acta del Corte 14 ya está aplicada: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '1a9ef250a74fb01962f463d98834cc4a' then
    raise exception 'Las funciones de redes no son las del Corte 14 publicado (huella 1a9ef250a74fb01962f463d98834cc4a): deténgase y avise';
  end if;
  if to_regclass('redes.levantar_puntos') is null or to_regprocedure('redes.f_levantar_acceso(text)') is null or to_regprocedure('campo.f_cargo_vigente(text)') is null
     or to_regclass('redes.v_personal_ficha') is null then
    raise exception 'Faltan objetos del Corte 14, del 4b o de la pasada del 14-nov de Comercial: deténgase y avise';
  end if;
end $$;
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
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 40 · PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- =====================================================================
revoke all on function redes.f_levantar_funcionario(text, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_redes_levantar_acta(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_levantar_acta(text, text, text) to service_role;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte14_acta', 'migracion_redes_corte14_acta', null, jsonb_build_object(
        'nuevas', jsonb_build_array('redes.f_levantar_funcionario', 'geoportal_redes_levantar_acta'),
        'motivo', 'Acta del reporte de activo (PDF, una por punto): quien reportó ve la suya; supervisor de distribución y administrador, todas'), null);
commit;
