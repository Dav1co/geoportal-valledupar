begin;
-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 · 90 — REVERSA. Solo si la Caracterización NO tiene registros (nada se borra: con datos, se detiene).
-- Vuelve las cinco funciones reemplazadas a como estaban (f_formularios, f_tipo_punto_texto, f_autorizar_captura, geoportal_tec_ptar_mapa y _elemento), quita las dos nuevas
-- y DESACTIVA (no borra) lo que se agregó: el formulario, su configuración, los cuatro puntos y las nueve variables. El dominio y los CHECK conservan «ptar_caracterizacion» y
-- «ptar», porque quedan filas (inactivas) que los usan.
-- =====================================================================
do $$
begin
  if to_regprocedure('tecnica.f_parametros_punto(bigint,integer)') is null then raise exception 'REVERSA PTAR-3: el paquete no está aplicado'; end if;
  if exists (select 1 from tecnica.registros r join tecnica.variables v on v.id = r.variable_id where v.codigo like 'ar\_%') then
    raise exception 'REVERSA PTAR-3: la Caracterización ya tiene registros. No se borra nada: avise';
  end if;
end $$;
CREATE OR REPLACE FUNCTION tecnica.f_formularios()
 RETURNS TABLE(clave text, nombre text, descripcion text, orden integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  values ('entrada',          'Entrada',                           'Agua cruda que ingresa a las plantas.', 1),
         ('salida',           'Salida',                            'Agua tratada que sale de las plantas.', 2),
         ('muestreo',         'Muestreo',                          'Muestreo en los puntos de la red y los tanques.', 3),
         ('danos_fallas',     'Daños o fallas',                    'Daños o fallas en la planta.', 4),
         ('mantenimiento',    'Mantenimiento, reparación e inversión', 'Mantenimiento, reparación e inversión.', 5),
         ('uso_quimicos',     'Uso de químicos',                   'Químicos usados en el proceso.', 6),
         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7),
         ('anomalia_compartida', 'Reportar anomalía',               'El mismo reporte de anomalías de Comercial, hecho desde Técnica.', 8),
         ('revision_compartida', 'Revisiones generales',            'La misma revisión general de Comercial, hecha desde Técnica.', 9);
$function$;
CREATE OR REPLACE FUNCTION tecnica.f_tipo_punto_texto(p_tipo text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select case p_tipo when 'muestreo' then 'punto de muestreo' when 'tanque' then 'tanque' when 'distribucion' then 'punto de distribución'
                     when 'macromedicion' then 'punto de macromedición' else 'punto' end
$function$;
CREATE OR REPLACE FUNCTION tecnica.f_autorizar_captura(p_solicitante text, p_formulario text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $function$
declare v_email text; v_perfil text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'registro_tecnico');       -- 28000 / 42501 si no hay sesión, acceso o permiso
  v_perfil := tecnica.f_perfil(v_email);
  if v_perfil = 'admin' then return v_email; end if;
  if not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  if v_perfil = 'supervisor' then return v_email; end if;
  if not tecnica.f_formulario_asignado(v_email, p_formulario) then
    raise exception 'No tiene asignado este formulario' using errcode = '42501';
  end if;
  return v_email;
end $function$;
CREATE OR REPLACE FUNCTION public.geoportal_tec_ptar_mapa(p_solicitante text, p_instalacion text DEFAULT 'ptar'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare i tecnica.instalaciones; v_fc jsonb; v_caja jsonb; v_tipos jsonb;
begin
  perform tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  i := tecnica.f_instalacion(p_instalacion);
  perform tecnica.f_autorizar_instalacion(p_solicitante, i.id);
  with al as (
    select distinct on (a.codigo) a.codigo, a.alias from tecnica.elemento_alias_eventos a where a.instalacion_id = i.id order by a.codigo, a.id desc
  ), el as (
    select e.*, al.alias, case e.tipo when 'perimetro' then 1 when 'laguna' then 2 when 'tramo' then 3 when 'pozo' then 4 when 'descarga' then 4 else 5 end as capa
      from tecnica.elementos_planta e left join al on al.codigo = e.codigo
     where e.instalacion_id = i.id and e.activo
  )
  select jsonb_build_object('type', 'FeatureCollection', 'features', coalesce(jsonb_agg(jsonb_build_object('type', 'Feature', 'id', el.id,
           'geometry', st_asgeojson(el.geom, 6)::jsonb,
           'properties', jsonb_strip_nulls(jsonb_build_object('codigo', el.codigo, 'tipo', el.tipo, 'nombre', el.nombre, 'alias', el.alias, 'orden', el.orden,
                                                              'activo', el.activo_codigo, 'origen', el.origen, 'tipo_laguna', el.atributos ->> 'tipo_laguna',
                                                              'tren', el.atributos ->> 'tren', 'estado', 'sin_variables')))
           order by el.capa, el.orden, el.codigo), '[]'::jsonb)),
         (select jsonb_build_array(round(st_xmin(x)::numeric, 6), round(st_ymin(x)::numeric, 6), round(st_xmax(x)::numeric, 6), round(st_ymax(x)::numeric, 6))
            from (select st_extent(geom)::geometry as x from el) c where x is not null),
         (select jsonb_object_agg(t, n) from (select tipo as t, count(*) as n from el group by tipo) z)
    into v_fc, v_caja, v_tipos
    from el;
  return jsonb_build_object('instalacion', jsonb_build_object('codigo', i.codigo, 'nombre', i.nombre, 'tipo', i.tipo, 'horas_sin_dato', i.horas_sin_dato),
                            'caja', v_caja, 'por_tipo', coalesce(v_tipos, '{}'::jsonb), 'total', jsonb_array_length(v_fc -> 'features'), 'elementos', v_fc);
end $function$;
CREATE OR REPLACE FUNCTION public.geoportal_tec_ptar_elemento(p_solicitante text, p_codigo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_cod text := upper(btrim(coalesce(p_codigo, ''))); e tecnica.elementos_planta; i tecnica.instalaciones; v_medida jsonb;
begin
  perform tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if v_cod !~ '^[A-Z0-9][A-Z0-9_-]{1,39}$' then perform tecnica.f_error('El código del elemento no es válido'); end if;
  select * into e from tecnica.elementos_planta x where x.codigo = v_cod and x.activo;
  if not found then perform tecnica.f_error('Ese elemento no existe', 'P0002'); end if;
  perform tecnica.f_autorizar_instalacion(p_solicitante, e.instalacion_id);
  select * into i from tecnica.instalaciones x where x.id = e.instalacion_id;
  v_medida := case when e.tipo in ('perimetro', 'laguna') then jsonb_build_object('area_m2', round(st_area(e.geom::geography)::numeric), 'area_ha', round((st_area(e.geom::geography) / 10000)::numeric, 2))
                   when e.tipo = 'tramo' then jsonb_build_object('longitud_m', round(st_length(e.geom::geography)::numeric, 1))
                   else jsonb_build_object('lat', round(st_y(e.geom)::numeric, 6), 'lon', round(st_x(e.geom)::numeric, 6)) end;
  return jsonb_strip_nulls(jsonb_build_object(
    'codigo', e.codigo, 'tipo', e.tipo, 'tipo_texto', tecnica.f_tipo_elemento_texto(e.tipo), 'nombre', e.nombre, 'alias', tecnica.f_alias_vigente(e.instalacion_id, e.codigo),
    'orden', e.orden, 'origen', e.origen, 'activo', e.activo_codigo, 'atributos', e.atributos, 'medida', v_medida,
    'instalacion', jsonb_build_object('codigo', i.codigo, 'nombre', i.nombre, 'tipo', i.tipo),
    'desde', (select jsonb_build_object('codigo', d.codigo, 'nombre', d.nombre) from tecnica.elementos_planta d where d.id = e.desde_id),
    'hasta', (select jsonb_build_object('codigo', h.codigo, 'nombre', h.nombre) from tecnica.elementos_planta h where h.id = e.hasta_id),
    'punto', (select jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre) from tecnica.puntos p where p.id = e.punto_id),
    'versiones', (select count(*) from tecnica.elementos_planta x where x.instalacion_id = e.instalacion_id and x.codigo = e.codigo),
    'alias_historial', coalesce((select jsonb_agg(jsonb_build_object('alias', a.alias, 'motivo', a.motivo, 'autor', a.autor, 'creado_en', a.creado_en) order by a.id desc)
                                   from (select * from tecnica.elemento_alias_eventos a where a.instalacion_id = e.instalacion_id and a.codigo = e.codigo order by a.id desc limit 10) a), '[]'::jsonb),
    'estado', 'sin_variables', 'indicadores', '[]'::jsonb, 'creado_en', e.creado_en));
end $function$;
drop function tecnica.f_estado_parametros(jsonb);
drop function tecnica.f_parametros_punto(bigint, integer);
update tecnica.formulario_variables set activa = false where formulario = 'ptar_caracterizacion' and activa;
update tecnica.formularios_config set activa = false where formulario = 'ptar_caracterizacion' and activa;
update tecnica.puntos set activo = false where tipo = 'ptar' and codigo in ('PTAR-AFL', 'PTAR-EFL', 'PTAR-RIO-ARR', 'PTAR-RIO-ABJ') and activo;
update tecnica.variables set activa = false where codigo like 'ar\_%' and activa;
do $$
begin
  if md5(pg_get_functiondef('tecnica.f_formularios()'::regprocedure)) <> 'a20a338b69efbcfbb5e90df54b1cb14d' or md5(pg_get_functiondef('tecnica.f_tipo_punto_texto(text)'::regprocedure)) <> '15e5bbe92e8cea94dbe92c66d01bea02' or md5(pg_get_functiondef('tecnica.f_autorizar_captura(text,text)'::regprocedure)) <> '6c27084e02548703ecd5c2c6f5cc41cd' or md5(pg_get_functiondef('public.geoportal_tec_ptar_mapa(text,text)'::regprocedure)) <> 'e4e70239e7e82441b803f29e5f38d535' or md5(pg_get_functiondef('public.geoportal_tec_ptar_elemento(text,text)'::regprocedure)) <> '817fd0406e1dabeeea8702cbf3bc308a' then raise exception 'REVERSA PTAR-3: las funciones no quedaron como antes'; end if;
end $$;
commit;
