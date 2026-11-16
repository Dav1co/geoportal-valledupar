-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 5c con cambios exactos, aplicados una sola vez:
--   · geoportal_redes_carga_lote, _resumen, _publicar, _anular, _muestra, _revertir, _devolver_campo y geoportal_redes_cargue_iniciar: quién puede deja de ser
--     solo el administrador (redes.f_autorizar_admin) y pasa a redes.f_autorizar_carga: el supervisor de distribución también, en las capas que no vienen
--     del modelo (David, 16-nov 01:30). El origen del activo sigue siendo solo del administrador al devolver un campo;
--   · geoportal_redes_cargue_capas: «puede_cargar» por capa (y «solo_admin» en las del modelo);
--   · geoportal_redes_mi_perfil: el dato «geovisor» para el menú (N-13).
-- La RPC de psql del 1a (geoportal_redes_carga_iniciar) NO cambia: la carga por psql sigue siendo del administrador.
-- =====================================================================

-- public.geoportal_redes_carga_lote(text,bigint,jsonb)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_lote(p_solicitante text, p_carga bigint, p_filas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
begin
  perform redes.f_autorizar_carga_id(p_solicitante, p_carga);
  return redes.f_lote(p_carga, p_filas);
end $function$;

-- public.geoportal_redes_carga_resumen(text,bigint)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_resumen(p_solicitante text, p_carga bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
begin
  perform redes.f_autorizar_carga_id(p_solicitante, p_carga);
  return redes.f_resumen(p_carga);
end $function$;

-- public.geoportal_redes_carga_publicar(text,bigint,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_publicar(p_solicitante text, p_carga bigint, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga_id(p_solicitante, p_carga); r jsonb;
begin
  r := redes.f_publicar(p_carga, v_email, p_motivo);
  perform tecnica.f_auditar(v_email, 'redes_carga_publicar', p_carga::text, r, null);
  return r;
end $function$;

-- public.geoportal_redes_carga_anular(text,bigint,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_anular(p_solicitante text, p_carga bigint, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga_id(p_solicitante, p_carga); r jsonb;
begin
  r := redes.f_anular(p_carga, v_email, p_motivo);
  perform tecnica.f_auditar(v_email, 'redes_carga_anular', p_carga::text, jsonb_build_object('motivo', p_motivo), null);
  return r;
end $function$;

-- public.geoportal_redes_carga_muestra(text,bigint)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_muestra(p_solicitante text, p_carga bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga_id(p_solicitante, p_carga); c redes.v_cargas_estado%rowtype; v_n integer; v_paso integer; v_caja jsonb;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga', 'P0002'); end if;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: ya no tiene vista previa', p_carga, c.estado), '55000'); end if;
  select count(*) into v_n from redes.carga_filas where carga_id = p_carga and geom is not null;
  v_paso := greatest(1, ceil(v_n / 400.0)::integer);
  select jsonb_build_array(round(ST_XMin(e)::numeric, 6), round(ST_YMin(e)::numeric, 6), round(ST_XMax(e)::numeric, 6), round(ST_YMax(e)::numeric, 6)) into v_caja
    from (select ST_Extent(geom)::geometry as e from redes.carga_filas where carga_id = p_carga and geom is not null) x where e is not null;
  return jsonb_build_object('carga_id', p_carga, 'capa', c.capa_codigo, 'esperadas', c.filas_esperadas,
    'recibidas', (select count(*) from redes.carga_filas where carga_id = p_carga), 'con_geometria', v_n,
    'con_error', (select count(*) from redes.carga_filas where carga_id = p_carga and error is not null),
    'errores', coalesce((select jsonb_agg(jsonb_build_object('orden', orden, 'llave', llave, 'error', error) order by orden)
                           from (select orden, llave, error from redes.carga_filas where carga_id = p_carga and error is not null order by orden limit 20) z), '[]'::jsonb),
    'caja', v_caja,
    'muestra', jsonb_build_object('type', 'FeatureCollection', 'features', coalesce((
      select jsonb_agg(jsonb_build_object('type', 'Feature', 'geometry', ST_AsGeoJSON(ST_SimplifyPreserveTopology(z.geom, 0.000005), 6)::jsonb,
                                          'properties', jsonb_build_object('orden', z.orden, 'llave', z.llave)) order by z.orden)
        from (select f.orden, f.llave, f.geom, row_number() over (order by f.orden) as rn from redes.carga_filas f where f.carga_id = p_carga and f.geom is not null) z
       where (z.rn - 1) % v_paso = 0), '[]'::jsonb)));
end $function$;

-- public.geoportal_redes_carga_revertir(text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_revertir(p_solicitante text, p_capa text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga(p_solicitante, p_capa); r jsonb;
begin
  r := redes.f_revertir(p_capa, v_email, p_motivo);
  perform tecnica.f_auditar(v_email, 'redes_carga_revertir', r ->> 'carga_id', r || jsonb_build_object('motivo', p_motivo), null);
  return r;
end $function$;

-- public.geoportal_redes_cargue_iniciar(text,text,text,text,integer,text,integer,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_cargue_iniciar(p_solicitante text, p_capa text, p_sha256 text, p_formato text, p_srid integer, p_columna_llave text, p_filas integer, p_nota text DEFAULT NULL::text, p_masiva text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga(p_solicitante, p_capa); c redes.capas%rowtype; r jsonb; v_llave text := btrim(coalesce(p_columna_llave, ''));
begin
  select * into c from redes.capas where codigo = p_capa;
  if not found then perform tecnica.f_error('No existe esa capa', 'P0002'); end if;
  if p_srid is null or p_srid not in (4326, 4686, 3114, 3115, 3116, 3117, 3118, 9377) then
    perform tecnica.f_error('El sistema de coordenadas no es uno de los que se aceptan (WGS 84, MAGNA-SIRGAS geográficas, sus zonas planas o el Origen Nacional 9377)');
  end if;
  if p_formato is null or p_formato not in ('shp', 'gpkg', 'geojson', 'kml', 'csv', 'xlsx') then perform tecnica.f_error('Ese formato de archivo no se acepta'); end if;
  if not (p_formato = any (c.formatos)) and not (p_formato = 'xlsx' and 'csv' = any (c.formatos)) then
    perform tecnica.f_error(format('La capa %s no se carga con %s (acepta: %s)', c.nombre, p_formato, array_to_string(c.formatos, ', ')));
  end if;
  if v_llave = '' or length(v_llave) > 64 then perform tecnica.f_error('Elija la columna llave'); end if;
  if c.columna_llave is not null and v_llave <> c.columna_llave then
    perform tecnica.f_error(format('La capa %s se carga siempre con la columna llave %s (N-5)', c.nombre, c.columna_llave));
  end if;
  if v_llave = '(geometria)' and not (c.fuente = 'carga' and c.prefijo is not null and c.columna_llave is null) then
    perform tecnica.f_error('Esta capa no se puede cargar sin columna llave');
  end if;
  if p_masiva is not null then
    if p_masiva !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then perform tecnica.f_error('El identificador de la carga masiva no es válido'); end if;
    perform set_config('redes.masiva_id', p_masiva, true);
  end if;
  r := redes.f_iniciar(p_capa, lower(p_sha256), p_formato, p_srid, v_llave, p_filas, p_nota, v_email);
  perform set_config('redes.masiva_id', '', true);
  if (r ->> 'nueva')::boolean then
    perform tecnica.f_auditar(v_email, 'redes_carga_iniciar', r ->> 'carga_id', jsonb_build_object('capa', p_capa, 'filas', p_filas, 'formato', p_formato, 'srid', p_srid,
                                                                                                  'columna_llave', v_llave, 'masiva', p_masiva, 'desde', 'pantalla'), null);
  end if;
  return r;
end $function$;

-- public.geoportal_redes_carga_devolver_campo(text,bigint,text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_devolver_campo(p_solicitante text, p_carga bigint, p_codigo text, p_campo text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga_id(p_solicitante, p_carga); c redes.v_cargas_estado%rowtype; v redes.v_activo_vigente%rowtype; v_campo text := btrim(coalesce(p_campo, ''));
        v_mot text := btrim(coalesce(p_motivo, '')); v_ficha text; v_id bigint;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres): por ejemplo, «Técnica corrigió el modelo»'); end if;
  if v_campo = 'origen' and not public.geoportal_es_admin(v_email) then raise exception 'El origen del activo lo cambia solo el administrador' using errcode = '42501'; end if;      -- Corte 6a (§26.2)
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga', 'P0002'); end if;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: el campo se devuelve desde una carga abierta', p_carga, c.estado), '55000'); end if;
  if c.capa_codigo = 'muestreo' then perform tecnica.f_error('Los puntos de muestreo no tienen ficha de activo'); end if;
  select * into v from redes.v_activo_vigente where codigo = upper(btrim(coalesce(p_codigo, '')));
  if not found then perform tecnica.f_error('No existe ese activo', 'P0002'); end if;
  if not coalesce(v.capa_codigo = any (redes.f_capas_cubiertas(c.capa_codigo)), false) then
    perform tecnica.f_error(format('El activo %s no es de la capa de esta carga', v.codigo));
  end if;
  perform pg_advisory_xact_lock(hashtext('redes.carga.' || c.capa_codigo));
  if not exists (select 1 from redes.ficha_ediciones e cross join jsonb_array_elements(e.cambios) x
                  where e.activo_id = v.activo_id and x ->> 'campo' = v_campo
                    and not exists (select 1 from redes.ficha_campo_devoluciones d where d.activo_id = e.activo_id and d.campo = v_campo and d.creado_en > e.creado_en)) then
    perform tecnica.f_error(format('El campo %s de %s no está editado en la ficha: ya lo manda la capa', v_campo, v.codigo), '55000');
  end if;
  v_ficha := case when v_campo like 'atributos.%' then v.atributos ->> substr(v_campo, 11)
                  when v_campo = 'origen' then (select coalesce(o.origen, '') || coalesce(' · ' || o.aportante_codigo, '') from redes.v_activo_origen_vigente o where o.activo_id = v.activo_id)
                  else to_jsonb(v) ->> v_campo end;
  insert into redes.ficha_campo_devoluciones (activo_id, campo, carga_id, valor_ficha, motivo, autor)
  values (v.activo_id, v_campo, p_carga, left(v_ficha, 500), v_mot, v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'redes_ficha_campo_devolver', v.codigo, jsonb_build_object('campo', v_campo, 'carga_id', p_carga, 'valor_ficha', left(v_ficha, 500), 'motivo', v_mot), null);
  return jsonb_build_object('devolucion_id', v_id, 'carga_id', p_carga, 'codigo', v.codigo, 'campo', v_campo, 'valor_ficha', v_ficha);
end $function$;

-- public.geoportal_redes_cargue_capas(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_cargue_capas(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v record;
begin
  select * into v from redes.f_perfil_lectura(p_solicitante);
  if v.perfil not in ('admin', 'supervisor') then perform tecnica.f_error('Solo el supervisor de distribución o el administrador ven el Cargue de capas', '42501'); end if;
  return jsonb_build_object(
    'puede_cargar', v.perfil = 'admin' or exists (select 1 from redes.capas x where x.activa and x.carga_supervisor),      -- Corte 6a: el supervisor carga las que no son del modelo
    'max_filas', redes.f_param('carga_max_filas'), 'lote_max_filas', redes.f_param('lote_max_filas'), 'tolerancia_geometria_m', redes.f_param('cruce_geometria_tol_m'),
    'caja', jsonb_build_array(redes.f_param('caja_lon_min'), redes.f_param('caja_lat_min'), redes.f_param('caja_lon_max'), redes.f_param('caja_lat_max')),
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'codigo', c.codigo, 'nombre', c.nombre, 'puede_cargar', v.perfil = 'admin' or c.carga_supervisor, 'solo_admin', not c.carga_supervisor, 'grupo', c.grupo, 'sistema', c.sistema, 'geometria', c.geometria, 'prefijo', c.prefijo, 'fuente', c.fuente,
               'derivada_de', c.derivada_de, 'columna_llave', c.columna_llave, 'formatos', to_jsonb(c.formatos),
               'lector', case when c.codigo = 'muestreo' then 'muestreo' when c.codigo in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas') then 'modelo'
                              when c.fuente = 'carga' and c.prefijo is not null then 'generico' end,
               'version', x.version, 'ultima', x.ultima, 'abierta', x.abierta, 'vigentes', x.vigentes,
               'estado', case when c.fuente = 'derivada' then 'derivada' when c.fuente <> 'carga' then 'otro_modulo' when x.version = 0 then 'sin_cargar'
                              when c.periodicidad_dias is not null and (x.ultima ->> 'publicada_en')::timestamptz < clock_timestamp() - make_interval(days => c.periodicidad_dias) then 'desactualizada'
                              else 'al_dia' end)
             order by c.orden, c.codigo)
        from redes.capas c
        cross join lateral (
          select (select count(*) from redes.v_cargas_estado e where e.capa_codigo = c.codigo and e.estado = 'publicada') as version,
                 (select jsonb_build_object('carga_id', e.id, 'publicada_en', e.publicada_en, 'autor', e.autor, 'formato', e.formato, 'filas', e.filas_esperadas, 'nota', e.nota,
                                            'motivo', (select ev.motivo from redes.carga_eventos ev where ev.carga_id = e.id and ev.tipo = 'publicar'))
                    from redes.v_cargas_estado e where e.capa_codigo = c.codigo and e.estado = 'publicada' order by e.publicada_en desc limit 1) as ultima,
                 (select jsonb_build_object('carga_id', e.id, 'creado_en', e.creado_en, 'autor', e.autor, 'formato', e.formato, 'filas', e.filas_esperadas, 'sha256', e.sha256,
                                            'columna_llave', e.columna_llave, 'srid', e.srid_origen, 'masiva', e.masiva_id is not null,
                                            'recibidas', (select count(*) from redes.carga_filas f where f.carga_id = e.id))
                    from redes.v_cargas_estado e where e.capa_codigo = c.codigo and e.estado = 'abierta' order by e.id desc limit 1) as abierta,
                 case when c.codigo = 'muestreo' then (select count(*) from tecnica.puntos p where p.tipo = 'muestreo' and p.activo)
                      else (select count(*) from redes.activo_vigente_mat m where m.capa_codigo = c.codigo and not m.retirado) end as vigentes
        ) x
       where c.activa), '[]'::jsonb));
end $function$;

-- public.geoportal_redes_mi_perfil(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_mi_perfil(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  return jsonb_build_object('perfil', p.perfil, 'dashboard_redes', p.perfil in ('admin', 'supervisor'), 'dashboard_ptap', public.geoportal_puede(p.email, 'dashboard_tecnico'),
                            'geovisor', redes.f_geovisor_lectura(p.email));      -- Corte 6a
end $function$;
