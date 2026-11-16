-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como las dejó el 5c (las 10 reemplazadas con su texto exacto), sin las 4 RPC nuevas, sin las 4 funciones internas nuevas, sin las
-- 3 tablas nuevas y sin la columna carga_supervisor. Los parámetros nuevos se quedan (nadie los lee; los parámetros no se borran).
-- SE NIEGA si ya hay cambios de las capas por omisión (nada se borra), si alguna carga la abrió alguien que no es administrador, o si alguna función
-- cambió después de la migración.
-- =====================================================================
do $$
begin
  if to_regclass('redes.geovisor_capas') is null then raise exception 'No hay nada que revertir: no existe redes.geovisor_capas'; end if;
  if exists (select 1 from redes.capas_por_perfil_eventos) then
    raise exception 'Ya hay cambios de las capas por omisión del geovisor: la reversa se niega (nada se borra)';
  end if;
  if exists (select 1 from redes.cargas c where not public.geoportal_es_admin(c.autor)
              and c.creado_en > (select max(a.creado_en) from public.geoportal_auditoria a where a.accion = 'migracion_redes_corte6a')) then
    raise exception 'Ya hay cargas abiertas por el supervisor de distribución: la reversa se niega (el 5c no las conoce)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '91a4d3e6e1c3539d8a447cb00a52d735'
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_redes_geovisor', 'c6eaa9bd7840c2827ecd2991938f8439'), ('geoportal_redes_geovisor_capa', 'f53157aafba91cb1b5c6f1712b9a26ce'), ('geoportal_redes_geovisor_capas_fijar', 'f2498ee99743b202b4ba36a5beb402e9'), ('geoportal_redes_geovisor_mvt', 'a2b1806a5200e2a3119f7a4592c5db05'))) <> 4
     or (select count(*) from (values ('public.geoportal_redes_carga_lote(text,bigint,jsonb)', 'c231d11e9e1a8d7da92e9e1d24538597'), ('public.geoportal_redes_carga_resumen(text,bigint)', '080cc0adc4fe187c6b7b32ddbffef36d'), ('public.geoportal_redes_carga_publicar(text,bigint,text)', '34e7db499d5b673dbfd255a244cde06c'), ('public.geoportal_redes_carga_anular(text,bigint,text)', 'a37619ca3507f73f89647e469ca3e52c'), ('public.geoportal_redes_carga_muestra(text,bigint)', '221d72397ec45c2ff0384490d64feadd'), ('public.geoportal_redes_carga_revertir(text,text,text)', 'c67e42afd8d8322ef747216ff55fbe44'), ('public.geoportal_redes_cargue_iniciar(text,text,text,text,integer,text,integer,text,text)', '49e0bfc8069af69cec997b6e61c939bf'), ('public.geoportal_redes_carga_devolver_campo(text,bigint,text,text,text)', '3d539b299226e7a018c8755454c74854'), ('public.geoportal_redes_cargue_capas(text)', '039d0c5240a323af540bc34e448a6c25'), ('public.geoportal_redes_mi_perfil(text)', '63f796c3777a4b46cebc82c08d1c81bd')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 10 then
    raise exception 'Las funciones cambiaron después de la migración del Corte 6a: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto del 5c
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_lote(p_solicitante text, p_carga bigint, p_filas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
begin
  perform redes.f_autorizar_admin(p_solicitante);
  return redes.f_lote(p_carga, p_filas);
end $function$;
revoke all on function public.geoportal_redes_carga_lote(text,bigint,jsonb) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_carga_lote(text,bigint,jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_resumen(p_solicitante text, p_carga bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
begin
  perform redes.f_autorizar_admin(p_solicitante);
  return redes.f_resumen(p_carga);
end $function$;
revoke all on function public.geoportal_redes_carga_resumen(text,bigint) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_carga_resumen(text,bigint) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_publicar(p_solicitante text, p_carga bigint, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_admin(p_solicitante); r jsonb;
begin
  r := redes.f_publicar(p_carga, v_email, p_motivo);
  perform tecnica.f_auditar(v_email, 'redes_carga_publicar', p_carga::text, r, null);
  return r;
end $function$;
revoke all on function public.geoportal_redes_carga_publicar(text,bigint,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_carga_publicar(text,bigint,text) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_anular(p_solicitante text, p_carga bigint, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_admin(p_solicitante); r jsonb;
begin
  r := redes.f_anular(p_carga, v_email, p_motivo);
  perform tecnica.f_auditar(v_email, 'redes_carga_anular', p_carga::text, jsonb_build_object('motivo', p_motivo), null);
  return r;
end $function$;
revoke all on function public.geoportal_redes_carga_anular(text,bigint,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_carga_anular(text,bigint,text) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_muestra(p_solicitante text, p_carga bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_admin(p_solicitante); c redes.v_cargas_estado%rowtype; v_n integer; v_paso integer; v_caja jsonb;
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
revoke all on function public.geoportal_redes_carga_muestra(text,bigint) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_carga_muestra(text,bigint) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_revertir(p_solicitante text, p_capa text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_admin(p_solicitante); r jsonb;
begin
  r := redes.f_revertir(p_capa, v_email, p_motivo);
  perform tecnica.f_auditar(v_email, 'redes_carga_revertir', r ->> 'carga_id', r || jsonb_build_object('motivo', p_motivo), null);
  return r;
end $function$;
revoke all on function public.geoportal_redes_carga_revertir(text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_carga_revertir(text,text,text) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_cargue_iniciar(p_solicitante text, p_capa text, p_sha256 text, p_formato text, p_srid integer, p_columna_llave text, p_filas integer, p_nota text DEFAULT NULL::text, p_masiva text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_admin(p_solicitante); c redes.capas%rowtype; r jsonb; v_llave text := btrim(coalesce(p_columna_llave, ''));
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
revoke all on function public.geoportal_redes_cargue_iniciar(text,text,text,text,integer,text,integer,text,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_cargue_iniciar(text,text,text,text,integer,text,integer,text,text) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_devolver_campo(p_solicitante text, p_carga bigint, p_codigo text, p_campo text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_admin(p_solicitante); c redes.v_cargas_estado%rowtype; v redes.v_activo_vigente%rowtype; v_campo text := btrim(coalesce(p_campo, ''));
        v_mot text := btrim(coalesce(p_motivo, '')); v_ficha text; v_id bigint;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres): por ejemplo, «Técnica corrigió el modelo»'); end if;
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
revoke all on function public.geoportal_redes_carga_devolver_campo(text,bigint,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_carga_devolver_campo(text,bigint,text,text,text) to service_role;

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
    'puede_cargar', v.perfil = 'admin',
    'max_filas', redes.f_param('carga_max_filas'), 'lote_max_filas', redes.f_param('lote_max_filas'), 'tolerancia_geometria_m', redes.f_param('cruce_geometria_tol_m'),
    'caja', jsonb_build_array(redes.f_param('caja_lon_min'), redes.f_param('caja_lat_min'), redes.f_param('caja_lon_max'), redes.f_param('caja_lat_max')),
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'codigo', c.codigo, 'nombre', c.nombre, 'grupo', c.grupo, 'sistema', c.sistema, 'geometria', c.geometria, 'prefijo', c.prefijo, 'fuente', c.fuente,
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
revoke all on function public.geoportal_redes_cargue_capas(text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_cargue_capas(text) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_mi_perfil(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  return jsonb_build_object('perfil', p.perfil, 'dashboard_redes', p.perfil in ('admin', 'supervisor'), 'dashboard_ptap', public.geoportal_puede(p.email, 'dashboard_tecnico'));
end $function$;
revoke all on function public.geoportal_redes_mi_perfil(text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_mi_perfil(text) to service_role;

-- 2. lo nuevo
drop function geoportal_redes_geovisor(text);
drop function geoportal_redes_geovisor_mvt(text,integer,integer,integer);
drop function geoportal_redes_geovisor_capa(text,text,date,date);
drop function geoportal_redes_geovisor_capas_fijar(text,text,text,boolean,text);
drop function redes.f_autorizar_carga(text,text);
drop function redes.f_autorizar_carga_id(text,bigint);
drop function redes.f_geovisor_acceso(text);
drop function redes.f_puede_formulario(text,text);
drop table redes.capas_por_perfil_eventos;
drop table redes.capas_por_perfil;
drop table redes.geovisor_capas;
alter table redes.capas drop column carga_supervisor;

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'a5ce1ff8c5659de3b853e30f4d3025e6' then
    raise exception 'La reversa no dejó la base como en el 5c';
  end if;
end $$;
