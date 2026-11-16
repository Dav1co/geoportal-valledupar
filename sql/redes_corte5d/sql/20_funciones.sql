-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 20 — FUNCIONES INTERNAS NUEVAS (la línea 116). Nadie de la API las ejecuta (40_permisos).
-- Ninguna lleva DELETE ni UPDATE sin WHERE (pg-safeupdate). Ninguna recorre tablas enteras de redes: el catastro se lee por contrato (índice) y, solo
-- si quedan reportes nuevos sin contrato en el catastro, una pasada por él para la dirección y el barrio de esos reportes.
-- =====================================================================

-- La dirección normalizada (la misma regla para el reporte y para el catastro): mayúsculas sin tildes, sin signos; CALLE/CLL → CL, CARRERA/KRA/CRA → CR,
-- DIAGONAL → DG, TRANSVERSAL → TV, AVENIDA → AV, MANZANA → MZ, CASA → CS, APARTAMENTO/APTO → AP; «9 A» → «9A»; sin ceros a la izquierda; sin «No».
create function redes.f_dir_norm(p text) returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(btrim(regexp_replace(
    regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
      regexp_replace(regexp_replace(upper(translate(coalesce(p, ''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')), '\m(NRO|NO|N)\s*[°º.]', ' ', 'g'), '[^A-Z0-9]+', ' ', 'g'),
      '\m(CALLE|CALL|CLL|CL)\M', 'CL', 'g'),
      '\m(CARRERA|CARR|CRA|KRA|KR|CR|K)\M', 'CR', 'g'),
      '\m(DIAGONAL|DIAG|DG)\M', 'DG', 'g'),
      '\m(TRANSVERSAL|TRANSV|TRANS|TV|TR)\M', 'TV', 'g'),
      '\m(AVENIDA|AVE|AV)\M', 'AV', 'g'),
      '\m(MANZANA|MZA|MZN|MZ)\M', 'MZ', 'g'),
      '\m(CASA|CS)\M', 'CS', 'g'),
      '\m(APARTAMENTO|APTO|APT|AP)\M', 'AP', 'g'),
      '\m(NUMERO|NUM|NRO|NO)\M', ' ', 'g'),
      '\m0+([0-9])', '\1', 'g'),
      '\m([0-9]+) ([A-H])\M', '\1\2', 'g'),
    '\s+', ' ', 'g')), '') $$;

-- La misma dirección sin apartamento, local, piso, interior, oficina, bloque ni torre (segundo intento)
create function redes.f_dir_base(p_norm text) returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(btrim(regexp_replace(coalesce(p_norm, ''), '\m(AP|LC|LOCAL|PISO|INT|INTERIOR|OF|OFICINA|BL|BLOQUE|TORRE)\M.*$', '')), '') $$;

-- El barrio normalizado: mayúsculas sin tildes ni signos, sin «BARRIO» ni «URBANIZACIÓN» delante
create function redes.f_barrio_norm(p text) returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(btrim(regexp_replace(regexp_replace(
    regexp_replace(upper(translate(coalesce(p, ''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')), '[^A-Z0-9]+', ' ', 'g'),
    '^\s*(BARRIO|BRR|URBANIZACION|URB)\M', ''), '\s+', ' ', 'g')), '') $$;

-- Solo las columnas que se cargan, con el nombre en minúscula. NOMBRE (y cualquier otra) no pasa: ni a la carga ni a ninguna tabla.
create function redes.f_l116_atributos(p jsonb) returns jsonb language sql immutable parallel safe set search_path = pg_catalog as $$
  select coalesce(jsonb_object_agg(lower(btrim(e.k)), e.v), '{}'::jsonb)
    from jsonb_each(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) e(k, v)
   where lower(btrim(e.k)) in ('reporte', 'estado', 'fecha_registro', 'contrato', 'direccion', 'barrio', 'comuna', 'desc_causal', 'servicio') $$;

-- La fecha de registro: AAAA-MM-DD [HH:MM[:SS]], DD/MM/AAAA [HH:MM[:SS]] o el número de serie de Excel; hora de Bogotá. Nulo si no se entiende.
create function redes.f_l116_fecha(p text) returns timestamptz language plpgsql stable set search_path = pg_catalog as $$
declare t text := btrim(coalesce(p, '')); v timestamp;
begin
  if t = '' then return null; end if;
  begin
    if t ~ '^[0-9]{5}(\.[0-9]+)?$' then v := timestamp '1899-12-30' + make_interval(secs => round(t::numeric * 86400));
    elsif t ~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}([ T][0-9]{1,2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?)?$' then v := replace(t, 'T', ' ')::timestamp;
    elsif t ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' then v := to_timestamp(t, 'DD/MM/YYYY')::timestamp;
    elsif t ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{2}$' then v := to_timestamp(t, 'DD/MM/YYYY HH24:MI')::timestamp;
    elsif t ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{2}:[0-9]{2}$' then v := to_timestamp(t, 'DD/MM/YYYY HH24:MI:SS')::timestamp;
    else return null; end if;
  exception when others then return null;
  end;
  if v < timestamp '2000-01-01' or v > (clock_timestamp() at time zone 'America/Bogota') + interval '1 day' then return null; end if;
  return v at time zone 'America/Bogota';
end $$;

-- Las filas de una carga de la 116, leídas y comparadas con lo vigente, en la tabla temporal _l116 (la usan el resumen y la publicación).
-- La ubicación (y el sector) solo se calcula para los reportes nuevos: 1) el punto del predio del contrato; 2) la dirección normalizada cruzada con el catastro
-- (todos los predios con esa dirección a 100 m o menos de su centro; si no, con la misma dirección y el mismo barrio); 3) el centro del barrio (aproximada);
-- 4) sin ubicar.
create function redes.f_l116_candidatos(p_carga bigint) returns void language plpgsql set search_path = redes, public, extensions, pg_temp as $$
declare v_falta boolean;
begin
  if to_regclass('pg_temp._l116') is not null then drop table pg_temp._l116; end if;
  create temp table _l116 on commit drop as
  select f.orden,
         nullif(btrim(f.atributos ->> 'reporte'), '') as reporte_txt,
         case when btrim(f.atributos ->> 'reporte') ~ '^[0-9]{1,15}(\.0+)?$' then split_part(btrim(f.atributos ->> 'reporte'), '.', 1)::bigint end as reporte,
         nullif(btrim(f.atributos ->> 'fecha_registro'), '') as fecha_txt,
         redes.f_l116_fecha(f.atributos ->> 'fecha_registro') as fecha,
         nullif(btrim(f.atributos ->> 'estado'), '') as estado_txt,
         case redes.f_norm(f.atributos ->> 'estado') when 'registrado' then 'registrado' when 'atendido' then 'atendido' end as estado,
         left(nullif(btrim(f.atributos ->> 'servicio'), ''), 60) as servicio,
         left(nullif(btrim(f.atributos ->> 'desc_causal'), ''), 120) as causal,
         left(nullif(btrim(f.atributos ->> 'comuna'), ''), 60) as comuna,
         case when btrim(f.atributos ->> 'contrato') ~ '^[0-9]{1,15}(\.0+)?$' then split_part(btrim(f.atributos ->> 'contrato'), '.', 1) end as contrato,
         left(nullif(btrim(f.atributos ->> 'direccion'), ''), 200) as direccion,
         left(nullif(btrim(f.atributos ->> 'barrio'), ''), 120) as barrio,
         null::text as error, null::bigint as reporte_id, null::text as estado_vigente, false as oculto_vigente, false as otros_distintos, null::text as accion,
         null::text as metodo, null::geometry as geom, null::smallint as sector, null::text as subsector, null::text as k1, null::text as k2, null::text as kb
    from redes.carga_filas f where f.carga_id = p_carga;
  update _l116 set error = case when reporte is null then 'el número de reporte no es un número' when fecha is null then 'la fecha de registro no se entiende'
                                when estado is null then 'el estado no es «Registrado» ni «Atendido»' when servicio is null then 'falta el servicio'
                                when causal is null then 'falta la causal (DESC_CAUSAL)' end
   where reporte is null or fecha is null or estado is null or servicio is null or causal is null;
  create index on _l116 (reporte);
  analyze _l116;

  -- frente a lo vigente (por el número de reporte)
  update _l116 l set reporte_id = r.id, estado_vigente = v.estado, oculto_vigente = v.oculto,
         otros_distintos = (r.fecha_registro <> l.fecha or r.servicio <> l.servicio or r.causal <> l.causal or r.contrato is distinct from l.contrato)
    from redes.l116_reportes r join redes.l116_vigente v on v.reporte_id = r.id
   where r.reporte = l.reporte and l.error is null;
  update _l116 set accion = case when error is not null then 'error' when reporte_id is null then 'nuevo' when oculto_vigente then 'mostrar'
                                 when estado <> estado_vigente then 'estado' else 'igual' end
   where true;
  analyze _l116;      -- con las estadísticas de antes, el planificador cree que no hay nuevos y cruza fila por fila (35 s con 23 mil)

  -- 1) por contrato: el punto del predio (índice por cod_usuario)
  if to_regclass('pg_temp._l116_pred') is not null then drop table pg_temp._l116_pred; end if;
  create temp table _l116_pred on commit drop as
  select distinct on (cv.cod_usuario) cv.cod_usuario, case when ST_SRID(cv.geom) = 4326 then cv.geom else ST_Transform(cv.geom, 4326) end as geom
    from public.catastro_valledupar cv
   where cv.cod_usuario in (select distinct x.contrato from _l116 x where x.accion = 'nuevo' and x.contrato is not null and x.contrato not in ('0', '99999999'))
     and cv.geom is not null
   order by cv.cod_usuario, cv.id;
  analyze _l116_pred;
  update _l116 l set geom = c.geom, metodo = 'contrato' from _l116_pred c where l.accion = 'nuevo' and c.cod_usuario = l.contrato;

  -- 2) y 3) por dirección y por barrio: una sola pasada por el catastro, y solo si quedan reportes nuevos sin ubicar
  update _l116 set k1 = redes.f_dir_norm(direccion), kb = redes.f_barrio_norm(barrio) where accion = 'nuevo' and metodo is null;
  update _l116 set k2 = redes.f_dir_base(k1) where accion = 'nuevo' and metodo is null;
  analyze _l116;
  v_falta := exists (select 1 from _l116 where accion = 'nuevo' and metodo is null and (k1 is not null or kb is not null));
  if v_falta then
    if to_regclass('pg_temp._l116_cat') is not null then drop table pg_temp._l116_cat; end if;
    -- solo los predios cuya dirección o barrio coincide con alguno de los reportes que faltan (listas con hash: una pasada, sin cruces fila por fila)
    create temp table _l116_cat on commit drop as
    select z.k1, z.k2, z.kb, z.geom
      from (select y.k1, redes.f_dir_base(y.k1) as k2, y.kb, y.geom
              from (select redes.f_dir_norm(cv.direccion) as k1, redes.f_barrio_norm(cv.barrio) as kb,
                           case when ST_SRID(cv.geom) = 4326 then cv.geom else ST_Transform(cv.geom, 4326) end as geom
                      from public.catastro_valledupar cv where cv.geom is not null and (cv.direccion is not null or cv.barrio is not null)) y) z
     where z.k1 in (select l.k1 from _l116 l where l.accion = 'nuevo' and l.metodo is null and l.k1 is not null)
        or z.k2 in (select l.k2 from _l116 l where l.accion = 'nuevo' and l.metodo is null and l.k2 is not null)
        or z.kb in (select l.kb from _l116 l where l.accion = 'nuevo' and l.metodo is null and l.kb is not null);
    analyze _l116_cat;
    -- dirección completa; dirección sin apartamento ni local; las dos con el mismo barrio (cuando la dirección sola está en varios sitios)
    update _l116 l set geom = d.c, metodo = 'direccion'
      from (select k1, ST_Centroid(ST_Collect(geom)) as c from _l116_cat where k1 is not null group by k1
             having ST_MaxDistance(ST_Centroid(ST_Collect(geom)), ST_Collect(geom)) <= 0.0009) d
     where l.accion = 'nuevo' and l.metodo is null and l.k1 = d.k1;
    update _l116 l set geom = d.c, metodo = 'direccion'
      from (select k2, ST_Centroid(ST_Collect(geom)) as c from _l116_cat where k2 is not null group by k2
             having ST_MaxDistance(ST_Centroid(ST_Collect(geom)), ST_Collect(geom)) <= 0.0009) d
     where l.accion = 'nuevo' and l.metodo is null and l.k2 = d.k2;
    update _l116 l set geom = d.c, metodo = 'direccion'
      from (select k2, kb, ST_Centroid(ST_Collect(geom)) as c from _l116_cat where k2 is not null and kb is not null group by k2, kb
             having ST_MaxDistance(ST_Centroid(ST_Collect(geom)), ST_Collect(geom)) <= 0.0009) d
     where l.accion = 'nuevo' and l.metodo is null and l.k2 = d.k2 and l.kb = d.kb;
    update _l116 l set geom = d.c, metodo = 'barrio'
      from (select kb, ST_Centroid(ST_Collect(geom)) as c from _l116_cat where kb is not null group by kb) d
     where l.accion = 'nuevo' and l.metodo is null and l.kb = d.kb;
  end if;
  update _l116 set metodo = 'sin_ubicar' where accion = 'nuevo' and metodo is null;
  update _l116 set geom = ST_SetSRID(ST_MakePoint(round(ST_X(geom)::numeric, 6), round(ST_Y(geom)::numeric, 6)), 4326) where geom is not null;
  analyze _l116;

  -- 4) el sector hidráulico de cada reporte ubicado (el oficial, la misma regla de redes.f_sector_de: primero el subsector, luego el de menor área).
  --    Se recorren los polígonos vigentes (36) y, para cada uno, los puntos que caen dentro (índice espacial sobre los puntos): cada polígono se prepara una vez.
  if exists (select 1 from _l116 where accion = 'nuevo' and geom is not null) then
    if to_regclass('pg_temp._l116_sec') is not null then drop table pg_temp._l116_sec; end if;
    create temp table _l116_sec on commit drop as
    select m.activo_id, m.geom, (m.clase = 'subsector') as es_sub, ST_Area(m.geom) as area,
           case when redes.f_num(v.atributos -> 'modelo' -> 'sector') between 1 and 100 then redes.f_num(v.atributos -> 'modelo' -> 'sector')::smallint end as sector,
           case when m.clase = 'subsector' then nullif(btrim(v.atributos -> 'modelo' ->> 'subsector'), '') end as subsector
      from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
     where m.prefijo = 'SEC' and not m.retirado and not m.oculto;
    create index on _l116 using gist (geom);
    analyze _l116_sec;
    analyze _l116;
    update _l116 l set sector = s.sector, subsector = s.subsector
      from (select distinct on (x.orden) x.orden, p.sector, p.subsector
              from _l116_sec p join _l116 x on x.geom && p.geom and ST_Intersects(p.geom, x.geom)
             where x.accion = 'nuevo'
             order by x.orden, p.es_sub desc, p.area, p.activo_id) s
     where s.orden = l.orden;
  end if;
end $$;

-- El resumen de una carga de la 116 (lo que muestra el paso «Revisar» y el paquete de psql)
create function redes.f_resumen_l116(p_carga bigint) returns jsonb language plpgsql set search_path = redes, public, extensions, pg_temp as $$
declare c redes.v_cargas_estado%rowtype; v_rec integer; v_bloq text[] := '{}'; v_avisos text[] := '{}'; v_acc jsonb; v_ubic jsonb; v_serv jsonb; v_n integer; v_tabla jsonb;
        v_sin jsonb; v_sector integer;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  select count(*) into v_rec from redes.carga_filas where carga_id = p_carga;
  if c.estado <> 'abierta' then v_bloq := v_bloq || ('La carga está ' || c.estado); end if;
  if v_rec <> c.filas_esperadas then v_bloq := v_bloq || format('Llegaron %s de %s filas: falta algún lote', v_rec, c.filas_esperadas); end if;
  if c.columna_llave <> 'reporte' then v_bloq := v_bloq || 'La llave de la línea 116 es el número de reporte (columna REPORTE)'::text; end if;
  perform redes.f_l116_candidatos(p_carga);
  select count(*) into v_n from _l116 where error is not null;
  if v_n > 0 then
    v_bloq := v_bloq || format('%s filas con error: %s', v_n, (select string_agg(x.t, '; ') from (select 'fila ' || orden || coalesce(' (reporte ' || reporte_txt || ')', '') || ': ' || error as t
                                                                                                  from _l116 where error is not null order by orden limit 10) x)
                               || case when v_n > 10 then format(' y %s más', v_n - 10) else '' end);
  end if;
  select count(*) into v_n from (select reporte from _l116 where reporte is not null group by reporte having count(*) > 1) x;
  if v_n > 0 then
    v_bloq := v_bloq || format('%s números de reporte repetidos en el archivo: %s', v_n, (select string_agg(r::text, ', ') from (select reporte as r from _l116 where reporte is not null
                                                                                                                                  group by reporte having count(*) > 1 order by reporte limit 10) x));
  end if;
  select count(*) into v_n from _l116 where accion in ('estado', 'igual', 'mostrar') and otros_distintos;
  if v_n > 0 then v_avisos := v_avisos || format('%s reportes ya cargados traen otra fecha, servicio, causal o contrato: se conservan los de la primera carga', v_n); end if;
  select count(*) into v_n from _l116 where accion = 'nuevo' and metodo = 'sin_ubicar';
  if v_n > 0 then v_avisos := v_avisos || format('%s reportes nuevos quedan sin ubicar (no están en el mapa; se guardan igual)', v_n); end if;
  select count(*) into v_n from _l116 where accion = 'mostrar';
  if v_n > 0 then v_avisos := v_avisos || format('%s reportes de una carga revertida vuelven a mostrarse', v_n); end if;

  select jsonb_build_object('nuevo', count(*) filter (where accion = 'nuevo'), 'estado', count(*) filter (where accion = 'estado'),
                            'igual', count(*) filter (where accion = 'igual'), 'mostrar', count(*) filter (where accion = 'mostrar'), 'error', count(*) filter (where accion = 'error'))
    into v_acc from _l116;
  select jsonb_build_object('contrato', count(*) filter (where metodo = 'contrato'), 'direccion', count(*) filter (where metodo = 'direccion'),
                            'barrio', count(*) filter (where metodo = 'barrio'), 'sin_ubicar', count(*) filter (where metodo = 'sin_ubicar')),
         count(*) filter (where sector is not null)
    into v_ubic, v_sector from _l116 where accion = 'nuevo';
  select coalesce(jsonb_object_agg(servicio, n order by servicio), '{}'::jsonb) into v_serv from (select servicio, count(*) n from _l116 where accion = 'nuevo' group by servicio) x;
  select coalesce(jsonb_agg(reporte order by reporte), '[]'::jsonb) into v_sin from (select reporte from _l116 where accion = 'nuevo' and metodo = 'sin_ubicar' order by reporte limit 20) x;
  v_tabla := jsonb_build_array(
      jsonb_build_object('s', '1 carga', 'c', 'capa', 'v', 'linea_116'), jsonb_build_object('s', '1 carga', 'c', 'carga', 'v', c.id || ' (' || c.estado || ')'),
      jsonb_build_object('s', '1 carga', 'c', 'filas recibidas / esperadas', 'v', v_rec || ' / ' || c.filas_esperadas),
      jsonb_build_object('s', '2 frente a lo vigente', 'c', 'nuevos', 'v', (v_acc ->> 'nuevo')),
      jsonb_build_object('s', '2 frente a lo vigente', 'c', 'con cambio de estado', 'v', (v_acc ->> 'estado')),
      jsonb_build_object('s', '2 frente a lo vigente', 'c', 'iguales', 'v', (v_acc ->> 'igual')),
      jsonb_build_object('s', '2 frente a lo vigente', 'c', 'vuelven a mostrarse', 'v', (v_acc ->> 'mostrar')),
      jsonb_build_object('s', '2 frente a lo vigente', 'c', 'con error', 'v', (v_acc ->> 'error')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'por contrato (punto del predio)', 'v', (v_ubic ->> 'contrato')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'por dirección (catastro)', 'v', (v_ubic ->> 'direccion')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'por barrio (aproximada)', 'v', (v_ubic ->> 'barrio')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'sin ubicar', 'v', (v_ubic ->> 'sin_ubicar')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'con sector hidráulico', 'v', v_sector::text))
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '4 servicio de los nuevos', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_serv))
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '7 avisos', 'c', 'aviso', 'v', a)), '[]'::jsonb) from unnest(v_avisos) a)
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '8 bloqueos', 'c', 'BLOQUEO', 'v', b)), '[]'::jsonb) from unnest(v_bloq) b)
    || jsonb_build_array(jsonb_build_object('s', '9 resultado', 'c', 'lista para publicar', 'v', case when cardinality(v_bloq) = 0 then 'SÍ' else 'NO' end));
  return jsonb_build_object('carga_id', c.id, 'capa', 'linea_116', 'estado', c.estado, 'recibidas', v_rec, 'esperadas', c.filas_esperadas,
    'frente_a_vigente', v_acc, 'ubicacion', v_ubic, 'con_sector', v_sector, 'servicios', v_serv, 'sin_ubicar_muestra', v_sin,
    'avisos', to_jsonb(v_avisos), 'bloqueos', to_jsonb(v_bloq), 'lista_para_publicar', cardinality(v_bloq) = 0, 'tabla', v_tabla);
end $$;

-- Publicar una carga de la 116: los nuevos (reporte, alta con su ubicación y lo vigente), los cambios de estado (evento con fecha) y los que vuelven. Nada se borra.
create function redes.f_publicar_l116(p_carga bigint, p_autor text, p_motivo text) returns jsonb language plpgsql set search_path = redes, public, extensions, pg_temp as $$
declare c redes.v_cargas_estado%rowtype; v_res jsonb; v_version integer; v_nuevos integer; v_estado integer; v_mostrar integer; v_iguales integer; v_mot text := btrim(p_motivo);
begin
  perform pg_advisory_xact_lock(hashtext('redes.carga.linea_116'));
  select * into c from redes.v_cargas_estado where id = p_carga;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: no se puede publicar', p_carga, c.estado)); end if;
  v_res := redes.f_resumen_l116(p_carga);      -- deja armada _l116
  if not (v_res ->> 'lista_para_publicar')::boolean then
    perform tecnica.f_error('La carga no está lista para publicar: ' || array_to_string(array(select jsonb_array_elements_text(v_res -> 'bloqueos')), '; '));
  end if;
  v_version := (select count(*) + 1 from redes.v_cargas_estado x where x.capa_codigo = 'linea_116' and x.estado = 'publicada');
  -- (a) nuevos
  insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, comuna, contrato, direccion, barrio, carga_id)
  select reporte, fecha, servicio, causal, comuna, contrato, direccion, barrio, p_carga from _l116 where accion = 'nuevo' order by reporte;
  get diagnostics v_nuevos = row_count;
  update _l116 l set reporte_id = r.id from redes.l116_reportes r where r.reporte = l.reporte and l.accion = 'nuevo';
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, sector, subsector, carga_id, motivo, autor)
  select reporte_id, 'alta', estado, metodo, geom, sector, subsector, p_carga, v_mot, p_autor from _l116 where accion = 'nuevo' order by reporte_id;
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, contrato, estado, estado_desde, metodo, geom, sector, subsector)
  select l.reporte_id, l.reporte, l.fecha, (l.fecha at time zone 'America/Bogota')::date, l.servicio, l.causal, l.contrato, l.estado, l.fecha, l.metodo, l.geom, l.sector, l.subsector
    from _l116 l where l.accion = 'nuevo';
  -- (b) cambios de estado (también los de los que vuelven a mostrarse)
  insert into redes.l116_eventos (reporte_id, tipo, estado, estado_antes, carga_id, motivo, autor)
  select reporte_id, 'estado', estado, estado_vigente, p_carga, v_mot, p_autor from _l116 where accion in ('estado', 'mostrar') and estado <> estado_vigente order by reporte_id;
  get diagnostics v_estado = row_count;
  -- (c) los que vuelven a mostrarse (los había ocultado la reversa de una carga)
  insert into redes.l116_eventos (reporte_id, tipo, carga_id, motivo, autor)
  select reporte_id, 'mostrar', p_carga, v_mot, p_autor from _l116 where accion = 'mostrar' order by reporte_id;
  get diagnostics v_mostrar = row_count;
  update redes.l116_vigente v set estado = l.estado, estado_desde = case when v.estado <> l.estado then clock_timestamp() else v.estado_desde end,
         oculto = false, actualizado_en = clock_timestamp()
    from _l116 l where l.reporte_id = v.reporte_id and l.accion in ('estado', 'mostrar');
  select count(*) into v_iguales from _l116 where accion = 'igual';
  insert into redes.carga_eventos (carga_id, tipo, version_capa, nuevos, cambiados, iguales, retirados, reactivados, detalle, motivo, autor)
  values (p_carga, 'publicar', v_version, v_nuevos, v_estado, v_iguales, 0, v_mostrar,
          jsonb_build_object('ubicacion', v_res -> 'ubicacion', 'con_sector', v_res -> 'con_sector', 'servicios', v_res -> 'servicios'), v_mot, p_autor);
  return jsonb_build_object('carga_id', p_carga, 'capa', 'linea_116', 'version_capa', v_version, 'nuevos', v_nuevos, 'cambiados', v_estado, 'cambios_estado', v_estado,
                            'iguales', v_iguales, 'reactivados', v_mostrar, 'retirados', 0, 'ubicacion', v_res -> 'ubicacion', 'con_sector', v_res -> 'con_sector');
end $$;

-- Volver atrás la última carga publicada de la 116: sus reportes nuevos se ocultan (con motivo) y sus cambios de estado se devuelven con un evento nuevo. Nada se borra.
create function redes.f_revertir_l116(p_autor text, p_motivo text) returns jsonb language plpgsql set search_path = redes, public, extensions, pg_temp as $$
declare c redes.v_cargas_estado%rowtype; v_ocultos integer; v_estados integer; v_mot text;
begin
  perform pg_advisory_xact_lock(hashtext('redes.carga.linea_116'));
  select * into c from redes.v_cargas_estado where capa_codigo = 'linea_116' and estado = 'publicada' order by publicada_en desc limit 1;
  if not found then perform tecnica.f_error('La capa de la línea 116 no tiene una carga publicada para revertir'); end if;
  v_mot := left(format('Se revirtió la carga %s de la línea 116: %s', c.id, btrim(p_motivo)), 1000);
  insert into redes.carga_eventos (carga_id, tipo, motivo, autor) values (c.id, 'revertir', btrim(p_motivo), p_autor);
  -- los cambios de estado de esa carga vuelven al estado anterior (si no cambió después)
  insert into redes.l116_eventos (reporte_id, tipo, estado, estado_antes, carga_id, motivo, autor)
  select e.reporte_id, 'estado', e.estado_antes, v.estado, null, v_mot, p_autor
    from redes.l116_eventos e join redes.l116_vigente v on v.reporte_id = e.reporte_id
   where e.carga_id = c.id and e.tipo = 'estado' and v.estado = e.estado
   order by e.reporte_id;
  get diagnostics v_estados = row_count;
  update redes.l116_vigente v set estado = e.estado_antes, estado_desde = clock_timestamp(), actualizado_en = clock_timestamp()
    from redes.l116_eventos e where e.carga_id = c.id and e.tipo = 'estado' and e.reporte_id = v.reporte_id and v.estado = e.estado;
  -- los reportes que esa carga creó o volvió a mostrar se ocultan
  insert into redes.l116_eventos (reporte_id, tipo, carga_id, motivo, autor)
  select v.reporte_id, 'ocultar', null, v_mot, p_autor from redes.l116_vigente v
   where not v.oculto and (v.reporte_id in (select r.id from redes.l116_reportes r where r.carga_id = c.id)
                           or v.reporte_id in (select e.reporte_id from redes.l116_eventos e where e.carga_id = c.id and e.tipo = 'mostrar'))
   order by v.reporte_id;
  get diagnostics v_ocultos = row_count;
  update redes.l116_vigente v set oculto = true, actualizado_en = clock_timestamp()
   where not v.oculto and (v.reporte_id in (select r.id from redes.l116_reportes r where r.carga_id = c.id)
                           or v.reporte_id in (select e.reporte_id from redes.l116_eventos e where e.carga_id = c.id and e.tipo = 'mostrar'));
  return jsonb_build_object('carga_id', c.id, 'capa', 'linea_116', 'ocultados', v_ocultos, 'estados_devueltos', v_estados);
end $$;
