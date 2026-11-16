-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como las dejó el 5b (las 8 reemplazadas con su texto exacto), sin las 6 RPC nuevas, sin la función interna nueva y sin las 2 tablas nuevas;
-- el CHECK de fuente de tecnica.puntos_ubicacion vuelve al del 5a.
-- Las 11 capas nuevas quedan INACTIVAS (las capas no se borran) y el parámetro nuevo se queda (nadie lo lee).
-- SE NIEGA si ya hay devoluciones o correcciones, si alguna capa nueva o acometidas ya tiene cargas (nada se borra), o si alguna función cambió después de la migración.
-- =====================================================================
do $$
begin
  if to_regclass('redes.ficha_campo_devoluciones') is null then raise exception 'No hay nada que revertir: no existe redes.ficha_campo_devoluciones'; end if;
  if exists (select 1 from redes.ficha_campo_devoluciones) or exists (select 1 from tecnica.punto_ubicacion_correcciones) then
    raise exception 'Ya hay campos devueltos a la capa o ubicaciones corregidas: la reversa se niega (nada se borra)';
  end if;
  if exists (select 1 from redes.cargas where capa_codigo in ('captaciones', 'aduccion', 'desarenadores', 'bombeo_ap', 'sumideros', 'interceptores', 'bombeo_ar', 'ptar',
                                                              'sectores', 'sensores', 'scada', 'acometidas') or columna_llave = '(geometria)' or masiva_id is not null) then
    raise exception 'Ya hay cargas con el lector genérico, sin columna llave o masivas: la reversa se niega (las funciones del 5b no las leen)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'a5ce1ff8c5659de3b853e30f4d3025e6'
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_redes_carga_devolver_campo', 'b36ed8f42ee53116db9862d5506d6178'), ('geoportal_redes_carga_muestra', 'dbeb32df95032c73b63a8d0ba2e7f916'), ('geoportal_redes_cargue_capas', 'ece3cdd5b0930ad6c978e0918767241d'), ('geoportal_redes_cargue_historial', '2931fb96f354077feb8f55f7e8c9eae1'), ('geoportal_redes_cargue_iniciar', 'bb82f2257259cef249565c18a537836c'), ('geoportal_tec_punto_ubicacion_corregir', '5518a3d3bd764c7801b089d7e48f2a1e'))) <> 6
     or (select count(*) from (values ('redes.f_geo_desde_wkt(text,integer)', '275df2e3a71fcd4fcf8623858f7a02d4'), ('redes.f_candidatos(bigint)', 'e8b1b1c04a4e826e9b631c489a4d4716'), ('redes.f_preparar_candidatos(bigint)', '140cd3d91986bea1a9e5f772c78a23e3'), ('redes.f_resumen(bigint)', '94f7e7b146a554d882a481a9f0973027'), ('redes.f_fusionar_ficha()', '490965f220573ec3bee6423f7c63ab2d'), ('redes.f_iniciar(text,text,text,integer,text,integer,text,text)', 'fa0b7dffda7a7c04bec4265d99633cb8'), ('public.geoportal_tec_punto_ubicacion_revisar(text,bigint,text,text,text)', '763c90cacdab105969966721b27f4c98'), ('public.geoportal_tec_punto_ubicaciones(text)', 'dcf5e4a013481f2d0077a9de32a0db72')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 8 then
    raise exception 'Las funciones cambiaron después de la migración del Corte 5c: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto del 5b
CREATE OR REPLACE FUNCTION redes.f_geo_desde_wkt(p_wkt text, p_srid integer, OUT geom geometry, OUT error text)
 RETURNS record
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare g geometry;
begin
  if p_wkt is null or btrim(p_wkt) = '' then error := 'Sin geometría'; return; end if;
  begin
    g := ST_GeomFromText(p_wkt, p_srid);
    if p_srid <> 4326 then g := ST_Transform(g, 4326); end if;
    g := ST_Force2D(g);
  exception when others then error := left('No se pudo leer la geometría: ' || sqlerrm, 300); return;
  end;
  if ST_IsEmpty(g) then error := 'La geometría está vacía'; return; end if;
  if GeometryType(g) not in ('POINT', 'LINESTRING', 'MULTILINESTRING', 'POLYGON', 'MULTIPOLYGON') then error := 'Tipo de geometría no admitido: ' || GeometryType(g); return; end if;
  if GeometryType(g) = 'MULTILINESTRING' and ST_NumGeometries(g) = 1 then g := ST_GeometryN(g, 1); end if;
  if ST_XMin(g) < redes.f_param('caja_lon_min') or ST_XMax(g) > redes.f_param('caja_lon_max')
     or ST_YMin(g) < redes.f_param('caja_lat_min') or ST_YMax(g) > redes.f_param('caja_lat_max') then
    error := 'Fuera de la caja de Valledupar: revise el sistema de coordenadas del archivo'; return;
  end if;
  geom := g;
end $function$;
revoke all on function redes.f_geo_desde_wkt(text,integer) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION redes.f_candidatos(p_carga bigint)
 RETURNS TABLE(capa_codigo text, llave text, orden integer, prefijo text, geom geometry, nombre text, clase text, efecto text, material_codigo text, material_texto text, diametro_mm numeric, longitud_m numeric, profundidad_m numeric, capacidad numeric, estado_codigo text, origen text, aportante_codigo text, codigo_anterior text, atributos jsonb, macro_num integer, crea_activo boolean, crea_nodo boolean, nodo_sistema text, nodo_nombre text, clase_nodo text, dispersion_m numeric, nodo_ini text, nodo_fin text, nombres_distintos integer)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare v_capa text := (select c.capa_codigo from redes.cargas c where c.id = p_carga);
begin
  if v_capa = 'acueducto' then
    return query
    with f as (select cf.orden, cf.llave, cf.atributos a, cf.geom from redes.carga_filas cf where cf.carga_id = p_carga and cf.error is null)
    -- tramos (RED o CON)
    select 'acueducto'::text, f.llave, f.orden,
           case when f.a ->> 'LABEL' ~* '^conducci[oó]n' then 'CON' else 'RED' end,
           f.geom, null::text, null::text, null::text,
           (select e.material_codigo from redes.material_equivalencias e where e.texto_norm = redes.f_norm(f.a ->> 'MATERIAL')),
           f.a ->> 'MATERIAL',
           round(redes.f_num(f.a -> 'D') * 25.4),                                          -- N-6: pulgadas del modelo → mm
           round(ST_Length(f.geom::geography)::numeric, 2), null::numeric, null::numeric,
           case when f.a ->> 'ZONE' = 'Proyectado' then 'proyectado' when redes.f_bool(f.a -> 'IS_ACTIVE?') is false then 'inactivo_modelo' else 'en_operacion' end,
           case when f.a ->> 'ZONE' = 'SIVA' then 'tercero' else 'emdupar' end,
           case when f.a ->> 'ZONE' = 'SIVA' then 'siva' end,
           f.a ->> 'LABEL',
           jsonb_strip_nulls(jsonb_build_object('diametro_pulg', redes.f_num(f.a -> 'D'), 'longitud_modelo_m', redes.f_num(f.a -> 'LENGTH'),
             'valvula_retencion', case when redes.f_bool(f.a -> 'CHK_VLVE?') then true end, 'zona_modelo', f.a ->> 'ZONE',
             'modelo', f.a - array['LABEL', 'MATERIAL', 'D', 'LENGTH', 'STARTNODID', 'STARTNODE', 'STOPNODEID', 'STOPNODE'])),
           null::integer, true, false, null::text, null::text, null::text, null::numeric,
           nullif(btrim(f.a ->> 'STARTNODID'), ''), nullif(btrim(f.a ->> 'STOPNODEID'), ''), null::integer
      from f
    union all
    -- nodos del modelo, armados desde los extremos de los tramos (A.0)
    select 'acueducto_nodos'::text, x.llave, x.orden, k.prefijo, x.pto, null::text, k.clase, k.efecto, null::text, null::text,
           null::numeric, null::numeric, null::numeric, null::numeric, k.estado, 'emdupar'::text, null::text, x.nombre,
           jsonb_build_object('nombre_modelo', x.nombre), k.macro_num,
           k.prefijo is not null, true, 'acueducto'::text, x.nombre, case when k.prefijo is null then 'por_clasificar' else 'activo' end,
           x.dispersion, null::text, null::text, x.nombres
      from (
        -- el punto del nodo es el del primer extremo que lo nombra; la dispersión, la mayor distancia de los demás extremos a ese punto
        select x0.llave, x0.orden, x0.nombre, x0.pto, x0.nombres,
               coalesce((select max(ST_Distance(q::geography, x0.pto::geography)) from unnest(x0.ptos) q), 0)::numeric as dispersion
          from (select e.llave, min(e.orden) as orden,
                       (array_agg(e.nombre order by e.orden, e.lado))[1] as nombre,
                       (array_agg(e.pto order by e.orden, e.lado))[1] as pto,
                       count(distinct e.nombre)::integer as nombres,
                       array_agg(e.pto) as ptos
                  from (select nullif(btrim(f.a ->> 'STARTNODID'), '') as llave, f.a ->> 'STARTNODE' as nombre, ST_StartPoint(f.geom) as pto, f.orden, 0 as lado from f
                        union all
                        select nullif(btrim(f.a ->> 'STOPNODEID'), ''), f.a ->> 'STOPNODE', ST_EndPoint(f.geom), f.orden, 1 from f) e
                 where e.llave is not null
                 group by e.llave) x0) x
      cross join lateral redes.f_clasificar_nodo_acueducto(x.nombre) k;

  elsif v_capa = 'alc_conductos' then
    return query
    select 'alc_conductos'::text, cf.llave, cf.orden, 'COL'::text, cf.geom, null::text, null::text, null::text,
           (select e.material_codigo from redes.material_equivalencias e where e.texto_norm = redes.f_norm(cf.atributos ->> 'MATERIAL')),
           cf.atributos ->> 'MATERIAL',
           redes.f_num(cf.atributos -> 'DIAMETRO'), round(ST_Length(cf.geom::geography)::numeric, 2), null::numeric, null::numeric,
           redes.f_estado_alcantarillado(cf.atributos ->> 'ESTADO'), 'emdupar'::text, null::text, cf.atributos ->> 'LABEL',
           jsonb_strip_nulls(jsonb_build_object('estado_fisico', cf.atributos ->> 'EDO_FiSICO', 'estado_operativo', cf.atributos ->> 'EDO_OPENAL',
             'estado_capa', cf.atributos ->> 'ESTADO', 'pendiente', redes.f_num(cf.atributos -> 'PENDIENTE'),
             'longitud_modelo_m', redes.f_num(cf.atributos -> 'LONGITUD'), 'descarga', cf.atributos ->> 'DESCARGA',
             'modelo', cf.atributos - array['LABEL', 'MATERIAL', 'DIAMETRO', 'ESTADO', 'EDO_FiSICO', 'EDO_OPENAL', 'PZ_INICIAL', 'PZ_FINAL'])),
           null::integer, true, false, null::text, null::text, null::text, null::numeric,
           nullif(btrim(cf.atributos ->> 'PZ_INICIAL'), ''), nullif(btrim(cf.atributos ->> 'PZ_FINAL'), ''), null::integer
      from redes.carga_filas cf where cf.carga_id = p_carga and cf.error is null;

  elsif v_capa = 'alc_pozos' then
    return query
    select 'alc_pozos'::text, cf.llave, cf.orden,
           case when redes.f_norm(cf.atributos ->> 'EST_POZO') = 'virtual' then null else 'POZ' end,      -- N-4: los virtuales son solo nodo
           cf.geom, null::text, null::text, null::text, null::text, null::text, null::numeric, null::numeric,
           round(redes.f_num(cf.atributos -> 'C_RASANTE') - redes.f_num(cf.atributos -> 'C_FONDO'), 3), null::numeric,
           redes.f_estado_alcantarillado(cf.atributos ->> 'ESTADO'), 'emdupar'::text, null::text, cf.atributos ->> 'LABEL',
           jsonb_strip_nulls(jsonb_build_object('estado_pozo', redes.f_sin_dato(cf.atributos ->> 'EST_POZO'), 'estado_tapa', redes.f_sin_dato(cf.atributos ->> 'EST_TAPA'),
             'estado_canuela', redes.f_sin_dato(cf.atributos ->> 'ESTADO_CAn'), 'estado_operativo', redes.f_sin_dato(cf.atributos ->> 'EST_OPERA'), 'estado_capa', cf.atributos ->> 'ESTADO',
             'cota_rasante', redes.f_num(cf.atributos -> 'C_RASANTE'), 'cota_fondo', redes.f_num(cf.atributos -> 'C_FONDO'),
             'modelo', cf.atributos - array['LABEL', 'EST_POZO', 'EST_TAPA', 'ESTADO_CAn', 'EST_OPERA', 'ESTADO', 'C_RASANTE', 'C_FONDO', 'X', 'Y'])),
           null::integer,
           redes.f_norm(cf.atributos ->> 'EST_POZO') is distinct from 'virtual', true, 'alcantarillado'::text, cf.atributos ->> 'LABEL',
           case when redes.f_norm(cf.atributos ->> 'EST_POZO') = 'virtual' then 'pozo_virtual' else 'activo' end, 0::numeric,
           null::text, null::text, null::integer
      from redes.carga_filas cf where cf.carga_id = p_carga and cf.error is null;

  elsif v_capa = 'alc_descargas' then
    return query
    select 'alc_descargas'::text, cf.llave, cf.orden, 'VER'::text, cf.geom, null::text, null::text, null::text, null::text, null::text,
           null::numeric, null::numeric, round(redes.f_num(cf.atributos -> 'C_RASANTE') - redes.f_num(cf.atributos -> 'C_FONDO'), 3), null::numeric,
           'en_operacion'::text, 'emdupar'::text, null::text, cf.atributos ->> 'LABEL',
           jsonb_strip_nulls(jsonb_build_object('cota_rasante', redes.f_num(cf.atributos -> 'C_RASANTE'), 'cota_fondo', redes.f_num(cf.atributos -> 'C_FONDO'),
             'caudal', redes.f_num(cf.atributos -> 'CAUDAL'), 'modelo', cf.atributos - array['LABEL', 'C_RASANTE', 'C_FONDO', 'CAUDAL', 'X', 'Y'])),
           null::integer, true, true, 'alcantarillado'::text, cf.atributos ->> 'LABEL', 'activo'::text, 0::numeric,
           null::text, null::text, null::integer
      from redes.carga_filas cf where cf.carga_id = p_carga and cf.error is null;
  else
    perform tecnica.f_error(format('La capa %s no tiene todavía su lector en el motor (llega con el Cargue de capas, Corte 5)', v_capa));
  end if;
end $function$;
revoke all on function redes.f_candidatos(bigint) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION redes.f_preparar_candidatos(p_carga bigint)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare v_capa text := (select capa_codigo from redes.cargas where id = p_carga);
begin
  if to_regclass('pg_temp._cand') is not null then drop table pg_temp._cand; end if;
  create temp table _cand on commit drop as
  select c.*,
         redes.f_huella(c.geom, jsonb_build_object('p', c.prefijo, 'n', c.nombre, 'c', c.clase, 'e', c.efecto, 'm', c.material_codigo, 'd', c.diametro_mm,
                                                    'l', c.longitud_m, 'pr', c.profundidad_m, 'ca', c.capacidad, 's', c.estado_codigo,
                                                    'ant', c.codigo_anterior, 'a', c.atributos)) as huella,
         null::bigint as activo_id, null::text as codigo, null::integer as version_vigente, null::text as huella_vigente,
         null::text as prefijo_vigente, false as retirado_vigente, null::text as accion
    from redes.f_candidatos(p_carga) c;
  -- cruce con lo vigente por (capa, llave) (D-2: nunca por el id de public.redes_*)
  update _cand k set activo_id = v.activo_id, codigo = v.codigo, version_vigente = v.version, huella_vigente = v.huella, prefijo_vigente = v.prefijo, retirado_vigente = v.retirado
    from redes.v_activo_vigente v
   where k.crea_activo and k.llave is not null and v.capa_codigo = k.capa_codigo and v.llave_capa = k.llave;
  update _cand set accion = case when not crea_activo then null
                                 when activo_id is null then 'nuevo'
                                 when prefijo_vigente is distinct from prefijo then 'nuevo_por_tipo'      -- cambió de tipo: activo nuevo y el viejo se retira
                                 when huella_vigente = huella then case when retirado_vigente then 'reactivar' else 'igual' end
                                 else 'cambiado' end;
  create index on _cand (capa_codigo, llave);
  create index on _cand (activo_id);
  perform redes.f_fusionar_ficha();      -- Corte 5a (§26.3): en una recarga gana lo editado en la ficha; los choques quedan en _choques
  analyze _cand;
end $function$;
revoke all on function redes.f_preparar_candidatos(bigint) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION redes.f_resumen(p_carga bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  c redes.v_cargas_estado%rowtype; v_tol numeric := redes.f_param('tolerancia_nodo_m');
  v_recibidas integer; v_errores integer; v_nulas integer; v_rep integer; v_bloq text[] := '{}'; v_avisos text[] := '{}'; v_tabla jsonb := '[]'::jsonb;
  v_por_prefijo jsonb; v_por_estado jsonb; v_por_accion jsonb; v_retirar integer; v_disp integer; v_sinmat integer; v_extra jsonb := '{}'::jsonb;
  v_nodos integer; v_nodos_activo integer; v_nodos_pc integer; v_nodos_virt integer; v_sin_ini integer; v_sin_fin integer; v_pend text[];
  r record; v_ch jsonb := '[]'::jsonb;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  if c.capa_codigo = 'muestreo' then return redes.f_resumen_muestreo(p_carga); end if;      -- capa MUE (Corte 5a)
  select count(*), count(*) filter (where error is not null), count(*) filter (where error is null and llave is null) into v_recibidas, v_errores, v_nulas
    from redes.carga_filas where carga_id = p_carga;
  select count(*) into v_rep from (select llave from redes.carga_filas where carga_id = p_carga and llave is not null group by llave having count(*) > 1) x;

  if c.estado <> 'abierta' then v_bloq := v_bloq || ('La carga está ' || c.estado); end if;
  if v_recibidas <> c.filas_esperadas then v_bloq := v_bloq || format('Llegaron %s de %s filas: falta algún lote', v_recibidas, c.filas_esperadas); end if;
  if v_errores > 0 then v_bloq := v_bloq || format('%s filas con error de geometría', v_errores); end if;
  if v_nulas > 0 then v_bloq := v_bloq || format('%s filas sin llave (%s)', v_nulas, c.columna_llave); end if;
  if v_rep > 0 then v_bloq := v_bloq || format('%s llaves repetidas en %s: el cruce por geometría (D-4) llega con el Cargue de capas', v_rep, c.columna_llave); end if;

  if c.estado = 'abierta' then
    perform redes.f_preparar_candidatos(p_carga);
    select coalesce(jsonb_object_agg(prefijo, n order by prefijo), '{}'::jsonb) into v_por_prefijo from (select prefijo, count(*) n from _cand where crea_activo group by prefijo) x;
    select coalesce(jsonb_object_agg(estado_codigo, n order by estado_codigo), '{}'::jsonb) into v_por_estado from (select estado_codigo, count(*) n from _cand where crea_activo group by estado_codigo) x;
    select coalesce(jsonb_object_agg(accion, n order by accion), '{}'::jsonb) into v_por_accion from (select accion, count(*) n from _cand where crea_activo group by accion) x;
    select count(*) into v_retirar from redes.v_activo_vigente v
     where v.capa_codigo = any (redes.f_capas_cubiertas(c.capa_codigo)) and not v.retirado
       and not exists (select 1 from _cand k where k.capa_codigo = v.capa_codigo and k.llave = v.llave_capa and k.crea_activo);
    select count(*) into v_sinmat from _cand where crea_activo and material_texto is not null and material_codigo is null;
    -- Corte 5a: choques con la ficha (gana la ficha, §26.3) y nodos ya clasificados en la bandeja (se conservan, 17f)
    select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'campo', campo, 'ficha', valor_ficha, 'capa', valor_capa) order by codigo, campo), '[]'::jsonb) into v_ch from _choques;
    if jsonb_array_length(v_ch) > 0 then
      v_avisos := v_avisos || format('%s campos editados en la ficha vienen distintos en la capa: gana la ficha (§26.3); la lista va en «choques con la ficha»', jsonb_array_length(v_ch));
    end if;
    v_extra := v_extra || jsonb_build_object('choques_con_la_ficha', jsonb_array_length(v_ch), 'nodos_clasificados_en_la_bandeja',
      (select count(*) from _cand k join redes.v_nodo_vigente n on n.sistema = k.nodo_sistema and n.llave_modelo = k.llave
        where k.crea_nodo and not k.crea_activo and k.clase_nodo = 'por_clasificar' and n.activo_id is not null));
    if v_sinmat > 0 then
      v_avisos := v_avisos || format('%s filas con material sin equivalencia (quedan sin material): %s', v_sinmat,
                    (select string_agg(distinct material_texto, ', ') from _cand where crea_activo and material_texto is not null and material_codigo is null));
    end if;
    select count(*) filter (where crea_nodo), count(*) filter (where crea_nodo and clase_nodo = 'activo'), count(*) filter (where clase_nodo = 'por_clasificar'),
           count(*) filter (where clase_nodo = 'pozo_virtual'), count(*) filter (where crea_nodo and dispersion_m > v_tol)
      into v_nodos, v_nodos_activo, v_nodos_pc, v_nodos_virt, v_disp from _cand;
    if v_disp > 0 then
      v_bloq := v_bloq || format('%s nodos con extremos separados más de %s m: revíselos antes de publicar (lista en nodos_dispersos)', v_disp, v_tol);
      v_extra := v_extra || jsonb_build_object('nodos_dispersos', (select jsonb_agg(jsonb_build_object('llave', llave, 'nombre', nodo_nombre, 'dispersion_m', round(dispersion_m, 2)) order by dispersion_m desc)
                                                                    from (select * from _cand where crea_nodo and dispersion_m > v_tol order by dispersion_m desc limit 50) z));
    end if;
    if exists (select 1 from _cand where nombres_distintos > 1) then
      v_avisos := v_avisos || format('%s nodos con más de un nombre en el modelo (se toma el primero)', (select count(*) from _cand where nombres_distintos > 1));
    end if;
    if c.capa_codigo = 'acueducto' then
      v_extra := v_extra || jsonb_build_object(
        'nodos_por_clasificar_por_prefijo', (select coalesce(jsonb_object_agg(p, n order by p), '{}'::jsonb) from
                                               (select coalesce(substring(nodo_nombre from '^[A-Za-zÁÉÍÓÚáéíóúñ]+'), '?') p, count(*) n from _cand where clase_nodo = 'por_clasificar' group by 1) z),
        'valvulas_por_clase', (select coalesce(jsonb_object_agg(clase, n order by clase), '{}'::jsonb) from (select clase, count(*) n from _cand where prefijo = 'VAL' group by clase) z),
        'accesorios_por_clase', (select coalesce(jsonb_object_agg(clase, n order by clase), '{}'::jsonb) from (select clase, count(*) n from _cand where prefijo = 'ACC' group by clase) z),
        'tramos_sin_nodo', (select count(*) from _cand where capa_codigo = 'acueducto' and (nodo_ini is null or nodo_fin is null)),
        'origen_tercero_siva', (select count(*) from _cand where aportante_codigo = 'siva'),
        'valvula_retencion', (select string_agg(codigo_anterior, ', ') from _cand where (atributos ->> 'valvula_retencion')::boolean),
        'macromedidores', (select jsonb_agg(jsonb_build_object('nodo', nodo_nombre, 'punto', 'MAC-' || lpad(macro_num::text, 2, '0'),
                                                               'existe_en_tecnica_puntos', exists (select 1 from tecnica.puntos p where p.codigo = 'MAC-' || lpad(k.macro_num::text, 2, '0'))) order by macro_num)
                             from _cand k where macro_num is not null));
      if (select count(*) from _cand where capa_codigo = 'acueducto' and (nodo_ini is null or nodo_fin is null)) > 0 then
        v_avisos := v_avisos || 'Hay tramos sin STARTNODID o STOPNODEID: quedan sin nodo en la topología';
      end if;
    elsif c.capa_codigo = 'alc_conductos' then
      if to_regclass('pg_temp._llaves_alc') is not null then drop table pg_temp._llaves_alc; end if;
      create temp table _llaves_alc on commit drop as select distinct llave from redes.f_llaves_nodo_alc_disponibles() where llave is not null;
      create unique index on _llaves_alc (llave);
      select count(*) filter (where k.nodo_ini is null or not exists (select 1 from _llaves_alc l where l.llave = k.nodo_ini)),
             count(*) filter (where k.nodo_fin is null or not exists (select 1 from _llaves_alc l where l.llave = k.nodo_fin))
        into v_sin_ini, v_sin_fin from _cand k;
      select array_agg(distinct capa_codigo order by capa_codigo) into v_pend from redes.v_cargas_estado where estado = 'abierta' and capa_codigo in ('alc_pozos', 'alc_descargas');
      v_extra := v_extra || jsonb_build_object('pz_inicial_sin_nodo', v_sin_ini, 'pz_final_sin_nodo', v_sin_fin,
                                               'publicar_antes', coalesce(to_jsonb(v_pend), '[]'::jsonb));
      v_extra := v_extra || jsonb_build_object('por_estado_fisico', (select coalesce(jsonb_object_agg(k, n order by k), '{}'::jsonb) from (select coalesce(atributos ->> 'estado_fisico', '(vacío)') k, count(*) n from _cand group by 1) z));
      if v_sin_ini + v_sin_fin > 0 then
        v_avisos := v_avisos || format('%s extremos de conducto sin pozo ni descarga con ese LABEL: se enlazan por extremos (%s m)', v_sin_ini + v_sin_fin, v_tol);
      end if;
      if v_pend is not null then v_avisos := v_avisos || ('Publique antes: ' || array_to_string(v_pend, ', ')); end if;
    elsif c.capa_codigo = 'alc_pozos' then
      v_extra := v_extra || jsonb_build_object('por_estado_pozo', (select coalesce(jsonb_object_agg(k, n order by k), '{}'::jsonb) from (select coalesce(atributos ->> 'estado_pozo', '(vacío)') k, count(*) n from _cand group by 1) z));
    end if;
  end if;

  -- tabla para mostrar en psql (sección, concepto, valor)
  v_tabla := jsonb_build_array(
    jsonb_build_object('s', '1 carga', 'c', 'capa', 'v', c.capa_codigo),
    jsonb_build_object('s', '1 carga', 'c', 'carga', 'v', c.id::text || ' (' || c.estado || ')'),
    jsonb_build_object('s', '1 carga', 'c', 'filas recibidas / esperadas', 'v', v_recibidas || ' / ' || c.filas_esperadas),
    jsonb_build_object('s', '1 carga', 'c', 'filas con error de geometría', 'v', v_errores::text),
    jsonb_build_object('s', '1 carga', 'c', 'llaves nulas / repetidas (' || c.columna_llave || ')', 'v', v_nulas || ' / ' || v_rep));
  if c.estado = 'abierta' then
    v_tabla := v_tabla
      || (select coalesce(jsonb_agg(jsonb_build_object('s', '2 activos por tipo', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_por_prefijo))
      || (select coalesce(jsonb_agg(jsonb_build_object('s', '3 activos por estado', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_por_estado))
      || (select coalesce(jsonb_agg(jsonb_build_object('s', '4 frente a lo vigente', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_por_accion))
      || jsonb_build_array(jsonb_build_object('s', '4 frente a lo vigente', 'c', 'retirados (no vienen)', 'v', v_retirar::text))
      || case when v_nodos > 0 then jsonb_build_array(
           jsonb_build_object('s', '5 nodos', 'c', 'nodos distintos', 'v', v_nodos::text),
           jsonb_build_object('s', '5 nodos', 'c', 'con activo', 'v', v_nodos_activo::text),
           jsonb_build_object('s', '5 nodos', 'c', 'por clasificar (solo nodo, N-3)', 'v', v_nodos_pc::text),
           jsonb_build_object('s', '5 nodos', 'c', 'pozos virtuales (solo nodo, N-4)', 'v', v_nodos_virt::text),
           jsonb_build_object('s', '5 nodos', 'c', 'cuadra: con activo + solo nodo = distintos', 'v', case when v_nodos_activo + v_nodos_pc + v_nodos_virt = v_nodos then 'sí' else 'NO' end),
           jsonb_build_object('s', '5 nodos', 'c', 'con extremos separados > ' || v_tol || ' m', 'v', v_disp::text)) else '[]'::jsonb end
      || (select coalesce(jsonb_agg(jsonb_build_object('s', '6 detalle', 'c', key, 'v', case when jsonb_typeof(value) = 'string' then value #>> '{}' else value::text end) order by key), '[]'::jsonb)
            from jsonb_each(v_extra - 'nodos_dispersos'));
  end if;
  v_tabla := v_tabla || (select coalesce(jsonb_agg(jsonb_build_object('s', '6b choques con la ficha (gana la ficha)', 'c', (x ->> 'codigo') || ' · ' || (x ->> 'campo'),
                           'v', 'ficha «' || coalesce(x ->> 'ficha', '—') || '» / capa «' || coalesce(x ->> 'capa', '—') || '»')), '[]'::jsonb)
                           from (select x from jsonb_array_elements(v_ch) x limit 200) z);
  v_tabla := v_tabla
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '7 avisos', 'c', 'aviso', 'v', a)), '[]'::jsonb) from unnest(v_avisos) a)
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '8 bloqueos', 'c', 'BLOQUEO', 'v', b)), '[]'::jsonb) from unnest(v_bloq) b)
    || jsonb_build_array(jsonb_build_object('s', '9 resultado', 'c', 'lista para publicar', 'v', case when cardinality(v_bloq) = 0 then 'SÍ' else 'NO' end));

  return jsonb_build_object('carga_id', c.id, 'capa', c.capa_codigo, 'estado', c.estado, 'recibidas', v_recibidas, 'esperadas', c.filas_esperadas,
    'errores', v_errores, 'llaves_nulas', v_nulas, 'llaves_repetidas', v_rep, 'por_prefijo', v_por_prefijo, 'por_estado', v_por_estado,
    'frente_a_vigente', v_por_accion, 'retirados', v_retirar, 'nodos', v_nodos, 'nodos_con_activo', v_nodos_activo, 'nodos_por_clasificar', v_nodos_pc,
    'pozos_virtuales', v_nodos_virt, 'nodos_dispersos', v_disp, 'detalle', v_extra, 'avisos', to_jsonb(v_avisos), 'bloqueos', to_jsonb(v_bloq),
    'lista_para_publicar', cardinality(v_bloq) = 0, 'choques', v_ch, 'tabla', v_tabla);
end $function$;
revoke all on function redes.f_resumen(bigint) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION redes.f_fusionar_ficha()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare n integer;
begin
  if to_regclass('pg_temp._choques') is not null then drop table pg_temp._choques; end if;
  create temp table _choques (activo_id bigint, codigo text, campo text, valor_ficha text, valor_capa text) on commit drop;
  alter table _cand add column campos_ficha text[], add column fecha_instalacion date, add column barrio_sector text;
  -- lo que no viene en ninguna capa se conserva siempre
  update _cand k set fecha_instalacion = v.fecha_instalacion, barrio_sector = v.barrio_sector
    from redes.v_activo_vigente v where v.activo_id = k.activo_id and k.accion in ('cambiado', 'igual', 'reactivar');
  update _cand k set campos_ficha = f.campos
    from (select e.activo_id, array_agg(distinct x ->> 'campo') as campos
            from redes.ficha_ediciones e cross join jsonb_array_elements(e.cambios) x
           where x ->> 'campo' not in ('alias', 'placa') group by e.activo_id) f
   where f.activo_id = k.activo_id and k.accion in ('cambiado', 'igual', 'reactivar');
  -- choques: lo que la capa trae distinto en un campo de la ficha (observaciones no viene de ninguna capa: no es choque)
  insert into _choques (activo_id, codigo, campo, valor_ficha, valor_capa)
  select k.activo_id, k.codigo, c.campo, c.vf, c.vc
    from _cand k join redes.v_activo_vigente v on v.activo_id = k.activo_id
   cross join lateral (values ('nombre', v.nombre, k.nombre), ('estado_codigo', v.estado_codigo, k.estado_codigo), ('clase', v.clase, k.clase),
                              ('efecto', v.efecto, k.efecto), ('material_codigo', v.material_codigo, k.material_codigo),
                              ('diametro_mm', trim_scale(v.diametro_mm)::text, trim_scale(k.diametro_mm)::text), ('capacidad', trim_scale(v.capacidad)::text, trim_scale(k.capacidad)::text),
                              ('profundidad_m', trim_scale(v.profundidad_m)::text, trim_scale(k.profundidad_m)::text)) c(campo, vf, vc)
   where k.campos_ficha is not null and c.campo = any (k.campos_ficha) and c.vc is not null and c.vf is distinct from c.vc
  union all
  select k.activo_id, k.codigo, x, v.atributos ->> substr(x, 11), k.atributos ->> substr(x, 11)
    from _cand k join redes.v_activo_vigente v on v.activo_id = k.activo_id cross join unnest(k.campos_ficha) x
   where x like 'atributos.%' and k.atributos ? substr(x, 11) and (v.atributos -> substr(x, 11)) is distinct from (k.atributos -> substr(x, 11))
  union all
  select k.activo_id, k.codigo, 'origen', coalesce(o.origen, '') || coalesce(' · ' || o.aportante_codigo, ''), coalesce(k.origen, '') || coalesce(' · ' || k.aportante_codigo, '')
    from _cand k join redes.v_activo_origen_vigente o on o.activo_id = k.activo_id
   where 'origen' = any (k.campos_ficha) and (o.origen is distinct from k.origen or o.aportante_codigo is distinct from k.aportante_codigo);
  -- la fusión: en los campos de la ficha queda el valor vigente
  update _cand k set
         nombre = case when 'nombre' = any (k.campos_ficha) then v.nombre else k.nombre end,
         estado_codigo = case when 'estado_codigo' = any (k.campos_ficha) then v.estado_codigo else k.estado_codigo end,
         clase = case when 'clase' = any (k.campos_ficha) then v.clase else k.clase end,
         efecto = case when 'efecto' = any (k.campos_ficha) then v.efecto else k.efecto end,
         material_codigo = case when 'material_codigo' = any (k.campos_ficha) then v.material_codigo else k.material_codigo end,
         diametro_mm = case when 'diametro_mm' = any (k.campos_ficha) then v.diametro_mm else k.diametro_mm end,
         capacidad = case when 'capacidad' = any (k.campos_ficha) then v.capacidad else k.capacidad end,
         profundidad_m = case when 'profundidad_m' = any (k.campos_ficha) then v.profundidad_m else k.profundidad_m end,
         atributos = k.atributos || coalesce((select jsonb_object_agg(a.key, a.value) from jsonb_each(v.atributos) a
                                               where a.key = 'observaciones' or ('atributos.' || a.key) = any (k.campos_ficha)), '{}'::jsonb)
                     - array(select substr(x, 11) from unnest(k.campos_ficha) x where x like 'atributos.%' and not (v.atributos ? substr(x, 11)))
    from redes.v_activo_vigente v
   where v.activo_id = k.activo_id and (k.campos_ficha is not null or v.atributos ? 'observaciones');
  -- huella y acción de nuevo, con lo fusionado
  update _cand k set huella = redes.f_huella(k.geom, jsonb_build_object('p', k.prefijo, 'n', k.nombre, 'c', k.clase, 'e', k.efecto, 'm', k.material_codigo, 'd', k.diametro_mm,
                                                                    'l', k.longitud_m, 'pr', k.profundidad_m, 'ca', k.capacidad, 's', k.estado_codigo,
                                                                    'ant', k.codigo_anterior, 'a', k.atributos))
   where k.accion in ('cambiado', 'igual', 'reactivar');
  update _cand k set accion = case when k.huella_vigente = k.huella then case when k.retirado_vigente then 'reactivar' else 'igual' end else 'cambiado' end
   where k.accion in ('cambiado', 'igual', 'reactivar');
  select count(*) into n from _choques;
  return n;
end $function$;
revoke all on function redes.f_fusionar_ficha() from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION redes.f_iniciar(p_capa text, p_sha256 text, p_formato text, p_srid integer, p_columna_llave text, p_filas integer, p_nota text, p_autor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare v_capa redes.capas%rowtype; v_c redes.v_cargas_estado%rowtype; v_id bigint;
begin
  select * into v_capa from redes.capas where codigo = p_capa;
  if not found then perform tecnica.f_error(format('No existe la capa %s', p_capa)); end if;
  if v_capa.fuente <> 'carga' or not v_capa.activa then perform tecnica.f_error(format('La capa %s no se carga por archivo', p_capa)); end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then perform tecnica.f_error('Falta la huella sha256 del archivo'); end if;
  if p_filas is null or p_filas < 1 or p_filas > redes.f_param('carga_max_filas') then
    perform tecnica.f_error(format('Una carga admite de 1 a %s filas', redes.f_param('carga_max_filas')::integer));
  end if;
  perform pg_advisory_xact_lock(hashtext('redes.carga.' || p_capa));
  select * into v_c from redes.v_cargas_estado where capa_codigo = p_capa and sha256 = p_sha256 and estado in ('abierta', 'publicada') order by id desc limit 1;
  if found then
    if v_c.estado = 'publicada' then perform tecnica.f_error(format('Este archivo ya se publicó en la carga %s de la capa %s', v_c.id, p_capa)); end if;
    if v_c.filas_esperadas <> p_filas or v_c.columna_llave <> p_columna_llave or v_c.srid_origen <> p_srid then
      perform tecnica.f_error(format('La carga abierta %s de este archivo tiene otros datos (filas, llave o sistema): anúlela antes', v_c.id));
    end if;
    return jsonb_build_object('carga_id', v_c.id, 'nueva', false, 'recibidas', (select count(*) from redes.carga_filas where carga_id = v_c.id));
  end if;
  if exists (select 1 from redes.v_cargas_estado where capa_codigo = p_capa and estado = 'abierta') then
    perform tecnica.f_error(format('Hay otra carga abierta de la capa %s (la %s): publíquela o anúlela antes', p_capa,
      (select id from redes.v_cargas_estado where capa_codigo = p_capa and estado = 'abierta' order by id desc limit 1)));
  end if;
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
  values (p_capa, p_sha256, p_formato, p_srid, btrim(p_columna_llave), p_filas, nullif(btrim(coalesce(p_nota, '')), ''), p_autor)
  returning id into v_id;
  return jsonb_build_object('carga_id', v_id, 'nueva', true, 'recibidas', 0);
end $function$;
revoke all on function redes.f_iniciar(text,text,text,integer,text,integer,text,text) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.geoportal_tec_punto_ubicacion_revisar(p_solicitante text, p_propuesta_id bigint, p_decision text, p_motivo text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'redes', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text := tecnica.f_autorizar_supervision(p_solicitante); x record; p tecnica.puntos%rowtype; u record;
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), ''); v_ubic bigint; v_rev bigint;
begin
  if p_decision is null or p_decision not in ('aprobar', 'rechazar') then perform tecnica.f_error('Diga si aprueba o rechaza la ubicación'); end if;
  if p_decision = 'rechazar' and (v_mot is null or length(v_mot) < 10) then perform tecnica.f_error('Escriba el motivo del rechazo (10 caracteres o más)'); end if;
  if v_mot is not null and (length(v_mot) < 10 or length(v_mot) > 1000) then perform tecnica.f_error('El motivo, si lo escribe, va de 10 a 1.000 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('tecnica.puntos'));          -- el mismo candado que la publicación de la capa MUE (Corte 5a)
  select * into x from tecnica.v_punto_propuestas where id = p_propuesta_id;
  if not found then perform tecnica.f_error('No existe esa ubicación propuesta', 'P0002'); end if;
  if x.estado <> 'pendiente' then perform tecnica.f_error(format('Esta ubicación ya fue %s por %s', x.estado, x.revisor), '55000'); end if;
  if x.autor = v_email then perform tecnica.f_error('No puede revisar una ubicación que usted mismo tomó: pídaselo a otro supervisor o al administrador'); end if;
  select * into p from tecnica.puntos where id = x.punto_id;
  if p_decision = 'aprobar' then
    if not p.activo then perform tecnica.f_error('El punto está desactivado: no se puede aprobar su ubicación (puede rechazarla)'); end if;
    select * into u from redes.v_punto_ubicacion_vigente where punto_id = p.id;
    insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, barrio_capa, carga_id, autor)
    values (p.id, x.lat, x.lon, 'verificada', 'gps_operador', u.barrio_capa, null, x.autor) returning id into v_ubic;
  end if;
  insert into tecnica.punto_ubicacion_revisiones (propuesta_id, decision, motivo, ubicacion_id, autor)
  values (x.id, p_decision, v_mot, v_ubic, v_email) returning id into v_rev;
  perform tecnica.f_auditar(v_email, 'tec_punto_ubicacion_' || p_decision, p.codigo, jsonb_build_object('propuesta_id', x.id, 'propuso', x.autor, 'motivo', v_mot, 'ubicacion_id', v_ubic), p_ip);
  return jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'decision', p_decision, 'estado', case when p_decision = 'aprobar' then 'aprobada' else 'rechazada' end,
                            'ubicacion_id', v_ubic, 'revision_id', v_rev);
end $function$;
revoke all on function public.geoportal_tec_punto_ubicacion_revisar(text,bigint,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_tec_punto_ubicacion_revisar(text,bigint,text,text,text) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_tec_punto_ubicaciones(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_aviso numeric := redes.f_param('mue_gps_distancia_aviso_m');
begin
  return jsonb_build_object(
    'precision_max_m', redes.f_param('mue_gps_precision_max_m'), 'distancia_aviso_m', v_aviso,
    'pendientes', coalesce((
      select jsonb_agg(jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'activo', p.activo,
               'lat', x.lat, 'lon', x.lon, 'precision_m', x.precision_m, 'autor', x.autor, 'autor_nombre', lb.nombre, 'creado_en', x.creado_en, 'propia', x.autor = v_email,
               'vigente', case when u.punto_id is not null then jsonb_build_object('lat', u.lat, 'lon', u.lon, 'exactitud', u.exactitud, 'fuente', u.fuente) end,
               'distancia_m', d.m, 'lejos', coalesce(d.m > v_aviso, false)) order by x.id)
        from tecnica.v_punto_propuestas x join tecnica.puntos p on p.id = x.punto_id
        left join redes.v_punto_ubicacion_vigente u on u.punto_id = x.punto_id
        left join public.geoportal_lista_blanca lb on lb.email = x.autor
        cross join lateral (select round(ST_Distance(x.geom::geography, u.geom::geography)::numeric) as m) d
       where x.estado = 'pendiente'), '[]'::jsonb),
    'puntos', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'lat', u.lat, 'lon', u.lon, 'exactitud', u.exactitud, 'fuente', u.fuente,
               'desde', u.creado_en, 'en_revision', exists (select 1 from tecnica.v_punto_propuestas x where x.punto_id = p.id and x.estado = 'pendiente')) order by p.codigo)
        from tecnica.puntos p left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
       where p.tipo = 'muestreo' and p.activo), '[]'::jsonb),
    'revisadas', coalesce((
      select jsonb_agg(r order by (r ->> 'revisada_en') desc) from (
        select jsonb_build_object('propuesta_id', x.id, 'punto', p.codigo, 'nombre', p.nombre, 'decision', x.estado, 'motivo', x.revision_motivo,
                                  'autor', x.autor, 'revisor', x.revisor, 'revisada_en', x.revisada_en, 'precision_m', x.precision_m) as r
          from tecnica.v_punto_propuestas x join tecnica.puntos p on p.id = x.punto_id
         where x.estado <> 'pendiente' order by x.revisada_en desc limit 50) z), '[]'::jsonb));
end $function$;
revoke all on function public.geoportal_tec_punto_ubicaciones(text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_tec_punto_ubicaciones(text) to service_role;

-- 2. lo nuevo
drop function geoportal_redes_cargue_capas(text);
drop function geoportal_redes_cargue_historial(text,text);
drop function geoportal_redes_cargue_iniciar(text,text,text,text,integer,text,integer,text,text);
drop function geoportal_redes_carga_muestra(text,bigint);
drop function geoportal_redes_carga_devolver_campo(text,bigint,text,text,text);
drop function geoportal_tec_punto_ubicacion_corregir(text,text,numeric,numeric,text,numeric,text,text);
drop function redes.f_cruzar_por_geometria(bigint);
drop table redes.ficha_campo_devoluciones;
drop table tecnica.punto_ubicacion_correcciones;
alter table tecnica.puntos_ubicacion drop constraint puntos_ubicacion_fuente_check;
alter table tecnica.puntos_ubicacion add constraint puntos_ubicacion_fuente_check check (fuente = any (array['david', 'barrio', 'gps_operador', 'carga']));
update redes.capas set activa = false
 where codigo in ('captaciones', 'aduccion', 'desarenadores', 'bombeo_ap', 'sumideros', 'interceptores', 'bombeo_ar', 'ptar', 'sectores', 'sensores', 'scada');

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'cbff4ee6e25826251d90496c833ac3de' then
    raise exception 'La reversa no dejó la base como en el 5b';
  end if;
end $$;
