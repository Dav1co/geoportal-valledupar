-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 26 — FUNCIÓN INTERNA Y RPC NUEVAS
-- PROPUESTA. No se ha ejecutado en la base real. security definer, search_path fijo, mensajes con HINT msg_usuario (tecnica.f_error); solo service_role.
-- Redes (las llama la Edge geoportal-redes, rutas nuevas «cargue_*»):
--   · geoportal_redes_cargue_capas: las capas del Cargue con su estado, versión, última carga y carga abierta (supervisor de distribución y administrador);
--   · geoportal_redes_cargue_historial: las cargas de una capa con sus eventos (supervisor y administrador);
--   · geoportal_redes_cargue_iniciar: abre una carga desde la pantalla (administrador), con las reglas de la llave, el sistema y la carga masiva;
--   · geoportal_redes_carga_muestra: vista previa de una carga abierta (caja, errores y una muestra de geometrías) para confirmar que cae en Valledupar;
--   · geoportal_redes_carga_devolver_campo: «Devolver este campo a la capa» desde la lista de choques (§31.1), con motivo.
--   Los lotes, el resumen, publicar, revertir y anular siguen siendo las RPC del 1a (geoportal_redes_carga_*), sin cambios.
-- Planta (las llama la Edge geoportal-tecnica, ruta nueva «ubicacion_corregir»):
--   · geoportal_tec_punto_ubicacion_corregir: corregir una ubicación verificada, con motivo (§32.2).
-- Nada se actualiza ni se borra: todo es inserción con autor y hora.
-- =====================================================================

-- D-4: cruce por GEOMETRÍA de una carga sin columna llave, sobre la tabla temporal _cand que arma redes.f_preparar_candidatos.
-- Con lo vigente (también lo retirado, que así se reactiva) de la MISMA capa y el MISMO tipo, tomado de redes.activo_vigente_mat (con índice espacial):
-- puntos a menos de cruce_geometria_tol_m metros; líneas y polígonos con la distancia de Hausdorff (en metros, MAGNA-SIRGAS Bogotá 3116) por debajo de la
-- misma tolerancia. Uno a uno, por rondas: en cada ronda se casan los pares en que cada uno es el más cercano del otro entre los que siguen libres (así dos
-- elementos en el mismo sitio se reparten). Lo cruzado toma la llave del vigente; lo demás, una llave propia «G<carga>-<orden>» (nuevo).
create function redes.f_cruzar_por_geometria(p_carga bigint)
returns integer language plpgsql set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
declare v_tol numeric := redes.f_param('cruce_geometria_tol_m'); v_capa text := (select capa_codigo from redes.cargas where id = p_carga);
        v_grados double precision := redes.f_param('cruce_geometria_tol_m') / 100000.0 * 1.5;      -- prefiltro en grados, holgado (1° ≈ 109 km en Valledupar)
        n integer := 0; k integer; v_ronda integer := 0;
begin
  if to_regclass('pg_temp._geo_vig') is not null then drop table pg_temp._geo_vig; end if;
  create temp table _geo_vig on commit drop as
  select m.llave_capa, m.prefijo, m.geom from redes.activo_vigente_mat m
   where m.capa_codigo = v_capa and m.llave_capa is not null and m.prefijo in (select distinct prefijo from _cand where crea_activo);
  create index on _geo_vig using gist (geom);
  analyze _geo_vig;
  if to_regclass('pg_temp._geo_par') is not null then drop table pg_temp._geo_par; end if;
  create temp table _geo_par on commit drop as
  select x.orden, x.llave_capa, x.m from (
    select k.orden, v.llave_capa,
           case when GeometryType(k.geom) = 'POINT' then ST_Distance(k.geom::geography, v.geom::geography)
                else ST_HausdorffDistance(ST_Transform(k.geom, 3116), ST_Transform(v.geom, 3116)) end as m
      from _cand k join _geo_vig v on v.prefijo = k.prefijo and ST_DWithin(k.geom, v.geom, v_grados)
     where k.crea_activo and k.geom is not null) x
   where x.m <= v_tol;
  create index on _geo_par (orden); create index on _geo_par (llave_capa);
  loop
    v_ronda := v_ronda + 1;
    with r as (select orden, llave_capa, row_number() over (partition by orden order by m, llave_capa) as rc,
                      row_number() over (partition by llave_capa order by m, orden) as rv from _geo_par),
         casados as (update _cand k set llave = r.llave_capa from r where r.orden = k.orden and r.rc = 1 and r.rv = 1 and k.crea_activo returning k.orden, k.llave)
    select count(*) into k from casados;
    exit when k = 0 or v_ronda > 50;
    n := n + k;
    delete from _geo_par g using _cand c where c.crea_activo and c.llave is not null and c.orden = g.orden;
    delete from _geo_par g using _cand c where c.crea_activo and c.llave is not null and c.llave = g.llave_capa;
  end loop;
  update _cand set llave = 'G' || p_carga || '-' || orden where crea_activo and llave is null;
  return n;
end $f$;

-- Las capas del Cargue de capas. Lectura del supervisor de distribución y del administrador (puede_cargar solo el administrador).
-- estado: al_dia, desactualizada (si la capa tiene periodicidad), sin_cargar, derivada (sale de otra capa) u otro_modulo.
create function public.geoportal_redes_cargue_capas(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
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
end $f$;

-- Historial de una capa: sus cargas (la más reciente primero, hasta 30) con sus eventos (publicar, revertir, anular) y lo que cambió.
create function public.geoportal_redes_cargue_historial(p_solicitante text, p_capa text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare v record;
begin
  select * into v from redes.f_perfil_lectura(p_solicitante);
  if v.perfil not in ('admin', 'supervisor') then perform tecnica.f_error('Solo el supervisor de distribución o el administrador ven el Cargue de capas', '42501'); end if;
  if not exists (select 1 from redes.capas where codigo = p_capa) then perform tecnica.f_error('No existe esa capa', 'P0002'); end if;
  return jsonb_build_object('capa', p_capa, 'cargas', coalesce((
    select jsonb_agg(z.j order by z.id desc) from (
      select e.id, jsonb_build_object('carga_id', e.id, 'estado', e.estado, 'formato', e.formato, 'srid', e.srid_origen, 'columna_llave', e.columna_llave, 'filas', e.filas_esperadas,
               'nota', e.nota, 'autor', e.autor, 'creado_en', e.creado_en, 'masiva', e.masiva_id is not null,
               'eventos', coalesce((select jsonb_agg(jsonb_build_object('tipo', ev.tipo, 'version_capa', ev.version_capa, 'nuevos', ev.nuevos, 'cambiados', ev.cambiados,
                                                                       'iguales', ev.iguales, 'retirados', ev.retirados, 'reactivados', ev.reactivados, 'motivo', ev.motivo,
                                                                       'autor', ev.autor, 'creado_en', ev.creado_en) order by ev.id)
                                      from redes.carga_eventos ev where ev.carga_id = e.id), '[]'::jsonb)) as j
        from redes.v_cargas_estado e where e.capa_codigo = p_capa order by e.id desc limit 30) z), '[]'::jsonb));
end $f$;

-- Abrir una carga desde la pantalla (solo el administrador). Además de lo que revisa redes.f_iniciar:
--   · el sistema de coordenadas es uno de los de Colombia que se aceptan (WGS 84, MAGNA geográficas y planas, Origen Nacional);
--   · las capas con llave fija (las del modelo: acueducto ID; conductos, pozos y descargas LABEL; muestreo codigo) solo se cargan con esa llave;
--   · «(geometria)» (sin columna llave, D-4) solo en las capas del lector genérico;
--   · en una carga masiva, todas las cargas del mismo archivo llevan el mismo identificador (masiva_id).
create function public.geoportal_redes_cargue_iniciar(p_solicitante text, p_capa text, p_sha256 text, p_formato text, p_srid integer, p_columna_llave text,
                                                      p_filas integer, p_nota text default null, p_masiva text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
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
end $f$;

-- Vista previa de una carga ABIERTA (solo el administrador): la caja de lo que llegó, las filas con error (fuera de Valledupar, sin geometría…) y una muestra
-- de hasta 400 geometrías, repartida en todo el archivo y simplificada, para dibujarla sobre el mapa antes de publicar.
create function public.geoportal_redes_carga_muestra(p_solicitante text, p_carga bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
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
end $f$;

-- «Devolver este campo a la capa» (§31.1), desde la lista de choques del resumen de una carga ABIERTA (solo el administrador, con motivo).
-- El campo deja de ser «de la ficha»: en esta carga (al volver a pedir el resumen) y en las siguientes, lo manda la capa, hasta que alguien lo vuelva a
-- editar en la ficha. La ficha no cambia ahora: cambia al publicar. El valor que tenía la ficha queda en el historial.
create function public.geoportal_redes_carga_devolver_campo(p_solicitante text, p_carga bigint, p_codigo text, p_campo text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
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
end $f$;

-- Corregir una ubicación VERIFICADA de un punto de muestreo (§32.2), desde «Puntos» del Dashboard PTAP (supervisor de planta o administrador), con motivo.
-- La ubicación nueva se AGREGA (verificada, fuente «correccion») y la anterior queda en el historial. Reglas:
--   · el punto existe, es de muestreo, está activo y su ubicación vigente está verificada (la aproximada se cambia desde Muestreo o con una carga);
--   · no tiene una ubicación propuesta en revisión (primero se aprueba o se rechaza);
--   · cae en la caja de Valledupar y queda a 1 m o más de la de ahora; con el GPS, la precisión es de mue_gps_precision_max_m o menos.
create function public.geoportal_tec_punto_ubicacion_corregir(p_solicitante text, p_punto text, p_lat numeric, p_lon numeric, p_metodo text, p_precision_m numeric,
                                                              p_motivo text, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'tecnica', 'redes', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_supervision(p_solicitante); p tecnica.puntos%rowtype; u record; v_mot text := btrim(coalesce(p_motivo, ''));
  v_lat numeric := round(p_lat, 6); v_lon numeric := round(p_lon, 6); v_dist numeric; v_ubic bigint; v_cor bigint;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo de la corrección (10 a 1.000 caracteres)'); end if;
  if p_metodo is null or p_metodo not in ('mapa', 'coordenadas', 'gps') then perform tecnica.f_error('Diga cómo tomó la ubicación nueva (mapa, coordenadas o GPS)'); end if;
  if p_lat is null or p_lon is null then perform tecnica.f_error('Falta la ubicación nueva'); end if;
  if p_metodo = 'gps' then
    if p_precision_m is null or p_precision_m <= 0 or p_precision_m > 1000 then perform tecnica.f_error('La precisión del GPS no es válida'); end if;
    if p_precision_m > redes.f_param('mue_gps_precision_max_m') then
      perform tecnica.f_error(format('El GPS tiene una precisión de %s m y se necesita de %s m o menos', ceil(p_precision_m)::integer, redes.f_param('mue_gps_precision_max_m')::integer));
    end if;
  elsif p_precision_m is not null then perform tecnica.f_error('La precisión solo va con el GPS');
  end if;
  if v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
    perform tecnica.f_error('La ubicación nueva está fuera de Valledupar');
  end if;
  perform pg_advisory_xact_lock(hashtext('tecnica.puntos'));          -- el mismo candado que revisar y que la publicación de la capa MUE
  select * into p from tecnica.puntos where codigo = upper(btrim(coalesce(p_punto, ''))) and tipo = 'muestreo';
  if not found then perform tecnica.f_error('No existe ese punto de muestreo', 'P0002'); end if;
  if not p.activo then perform tecnica.f_error('Ese punto de muestreo está desactivado'); end if;
  select * into u from redes.v_punto_ubicacion_vigente where punto_id = p.id;
  if not found or u.exactitud <> 'verificada' then
    perform tecnica.f_error('Solo se corrige una ubicación verificada. La aproximada se cambia con «Guardar la ubicación de este punto» en Muestreo, o con una carga de la capa', '55000');
  end if;
  if exists (select 1 from tecnica.v_punto_propuestas x where x.punto_id = p.id and x.estado = 'pendiente') then
    perform tecnica.f_error('Este punto tiene una ubicación en revisión: apruébela o recházela antes de corregir', '55000');
  end if;
  v_dist := round(ST_Distance(ST_SetSRID(ST_MakePoint(v_lon::double precision, v_lat::double precision), 4326)::geography, u.geom::geography)::numeric, 1);
  if v_dist < 1 then perform tecnica.f_error('La ubicación nueva es la misma de ahora (menos de 1 m)'); end if;
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, barrio_capa, carga_id, autor)
  values (p.id, v_lat, v_lon, 'verificada', 'correccion', u.barrio_capa, null, v_email) returning id into v_ubic;
  insert into tecnica.punto_ubicacion_correcciones (punto_id, ubicacion_id, ubicacion_previa_id, metodo, precision_m, distancia_m, motivo, autor)
  values (p.id, v_ubic, u.id, p_metodo, case when p_metodo = 'gps' then round(p_precision_m, 1) end, v_dist, v_mot, v_email) returning id into v_cor;
  perform tecnica.f_auditar(v_email, 'tec_punto_ubicacion_corregir', p.codigo, jsonb_build_object('correccion_id', v_cor, 'ubicacion_id', v_ubic, 'previa_id', u.id, 'metodo', p_metodo,
                                                                                               'distancia_m', v_dist, 'motivo', v_mot), p_ip);
  return jsonb_build_object('punto', p.codigo, 'correccion_id', v_cor, 'ubicacion_id', v_ubic, 'lat', v_lat, 'lon', v_lon, 'distancia_m', v_dist);
end $f$;
