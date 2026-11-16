-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 20 — FUNCIONES INTERNAS NUEVAS (la línea 116). Nadie de la API las ejecuta (40_permisos).
-- Ninguna lleva DELETE ni UPDATE sin WHERE (pg-safeupdate). Ninguna recorre tablas enteras: el catastro se lee solo por contrato (índice), y solo para los
-- reportes nuevos; lo que ya está cargado y sigue igual solo se cuenta.
-- =====================================================================

-- La función de fecha se llama una vez por fila (23 mil reportes). No lleva «set search_path» a propósito: solo usa funciones y operadores de pg_catalog (que
-- siempre se busca primero) y así no paga el cambio de configuración en cada llamada. Nadie de la API la ejecuta (40_permisos).

-- Solo las columnas que se cargan, con el nombre en minúscula. NOMBRE, DIRECCION, BARRIO (y cualquier otra) no pasan: ni a la carga ni a ninguna tabla.
-- (David, 16-nov: la 116 se ubica SOLO por el contrato; la dirección y el barrio ya no tienen uso y no se guardan.)
create function redes.f_l116_atributos(p jsonb) returns jsonb language sql immutable parallel safe set search_path = pg_catalog as $$
  select coalesce(jsonb_object_agg(lower(btrim(e.k)), e.v), '{}'::jsonb)
    from jsonb_each(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) e(k, v)
   where lower(btrim(e.k)) in ('reporte', 'estado', 'fecha_registro', 'contrato', 'comuna', 'desc_causal', 'servicio') $$;

-- La fecha de registro: AAAA-MM-DD [HH:MM[:SS]], DD/MM/AAAA [HH:MM[:SS]] o el número de serie de Excel; hora de Bogotá. Nulo si no se entiende.
-- Sin bloques de excepción (cada uno abre una subtransacción: con 23 mil filas se nota en producción): la fecha se valida con cuentas.
create function redes.f_l116_fecha(p text) returns timestamptz language plpgsql stable as $$
declare s text := btrim(coalesce(p, '')); m text[]; y integer; mo integer; d integer; h integer := 0; mi integer := 0; se integer := 0; v timestamp;
begin
  if s = '' then return null; end if;
  if s ~ '^[0-9]{5}(\.[0-9]+)?$' then
    v := timestamp '1899-12-30' + make_interval(secs => round(s::numeric * 86400));
  else
    m := regexp_match(s, '^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})(?:[ T]([0-9]{1,2}):([0-9]{2})(?::([0-9]{2})(?:\.[0-9]+)?)?)?$');
    if m is not null then y := m[1]::integer; mo := m[2]::integer; d := m[3]::integer;
    else
      m := regexp_match(s, '^([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})(?: ([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?)?$');
      if m is null then return null; end if;
      d := m[1]::integer; mo := m[2]::integer; y := m[3]::integer;
    end if;
    h := coalesce(m[4], '0')::integer; mi := coalesce(m[5], '0')::integer; se := coalesce(m[6], '0')::integer;
    if y not between 1900 and 2200 or mo not between 1 and 12 or d not between 1 and 31 or h > 23 or mi > 59 or se > 59 then return null; end if;
    if extract(month from make_date(y, mo, 1) + (d - 1)) <> mo then return null; end if;      -- el día no existe en ese mes (31 de febrero)
    v := (make_date(y, mo, 1) + (d - 1))::timestamp + make_interval(hours => h, mins => mi, secs => se);
  end if;
  if v < timestamp '2000-01-01' or v > (clock_timestamp() at time zone 'America/Bogota') + interval '1 day' then return null; end if;
  return v at time zone 'America/Bogota';
end $$;

-- Las filas de una carga de la 116, leídas y comparadas con lo vigente, en la tabla temporal _l116 (la usa el resumen).
-- Todo en una pasada: lo que ya está cargado y sigue igual solo se cuenta. La ubicación (y el sector) solo se calcula para los reportes NUEVOS, y SOLO por el
-- contrato cruzado con el catastro (el punto del predio; decisión de David, 16-nov). El que no cruza queda «sin ubicar»: se guarda y no se pinta en el mapa.
create function redes.f_l116_candidatos(p_carga bigint) returns void language plpgsql set search_path = redes, public, extensions, pg_temp as $$
begin
  if to_regclass('pg_temp._l116') is not null then drop table pg_temp._l116; end if;
  create temp table _l116 on commit drop as
  with f as materialized (
    select c.orden,
           nullif(btrim(c.atributos ->> 'reporte'), '') as reporte_txt,
           case when btrim(c.atributos ->> 'reporte') ~ '^[0-9]{1,15}(\.0+)?$' then split_part(btrim(c.atributos ->> 'reporte'), '.', 1)::bigint end as reporte,
           -- la forma más común (AAAA-MM-DD HH:MM:SS, día 1 a 28) se convierte directo: no puede fallar; lo demás, por redes.f_l116_fecha
           case when c.atributos ->> 'fecha_registro' ~ '^20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|1[0-9]|2[0-8]) ([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$'
                then case when (c.atributos ->> 'fecha_registro')::timestamp <= (clock_timestamp() at time zone 'America/Bogota') + interval '1 day'
                          then (c.atributos ->> 'fecha_registro')::timestamp at time zone 'America/Bogota' end
                else redes.f_l116_fecha(c.atributos ->> 'fecha_registro') end as fecha,
           case lower(btrim(c.atributos ->> 'estado')) when 'registrado' then 'registrado' when 'atendido' then 'atendido' end as estado,
           left(nullif(btrim(c.atributos ->> 'servicio'), ''), 60) as servicio,
           left(nullif(btrim(c.atributos ->> 'desc_causal'), ''), 120) as causal,
           left(nullif(btrim(c.atributos ->> 'comuna'), ''), 60) as comuna,
           case when btrim(c.atributos ->> 'contrato') ~ '^[0-9]{1,15}(\.0+)?$' then split_part(btrim(c.atributos ->> 'contrato'), '.', 1) end as contrato
      from redes.carga_filas c where c.carga_id = p_carga),
  e as (
    select f.*, case when f.reporte is null then 'el número de reporte no es un número' when f.fecha is null then 'la fecha de registro no se entiende'
                     when f.estado is null then 'el estado no es «Registrado» ni «Atendido»' when f.servicio is null then 'falta el servicio'
                     when f.causal is null then 'falta la causal (DESC_CAUSAL)' end as error
      from f)
  select e.*, r.id as reporte_id, v.estado as estado_vigente,
         coalesce(r.fecha_registro <> e.fecha or r.servicio <> e.servicio or r.causal <> e.causal or r.contrato is distinct from e.contrato, false) as otros_distintos,
         case when e.error is not null then 'error' when r.id is null then 'nuevo' when v.oculto then 'mostrar' when e.estado <> v.estado then 'estado' else 'igual' end as accion,
         null::text as metodo, null::geometry as geom, null::smallint as sector, null::text as subsector
    from e
    left join redes.l116_reportes r on r.reporte = e.reporte
    left join redes.l116_vigente v on v.reporte_id = r.id;
  -- desde aquí solo se trabaja con los nuevos (en una carga de cada mes son unos cientos)
  if to_regclass('pg_temp._l116_n') is not null then drop table pg_temp._l116_n; end if;
  create temp table _l116_n on commit drop as select orden, contrato from _l116 where accion = 'nuevo';
  if not exists (select 1 from _l116_n) then return; end if;
  analyze _l116_n;

  -- la ubicación: el punto del predio del contrato (índice por cod_usuario). El comodín 99999999 y el «0» no son contratos
  if to_regclass('pg_temp._l116_u') is not null then drop table pg_temp._l116_u; end if;
  create temp table _l116_u (orden integer primary key, geom geometry) on commit drop;
  insert into _l116_u (orden, geom)
  select n.orden, ST_SetSRID(ST_MakePoint(round(ST_X(c.geom)::numeric, 6), round(ST_Y(c.geom)::numeric, 6)), 4326)
    from _l116_n n
    join (select distinct on (cv.cod_usuario) cv.cod_usuario, case when ST_SRID(cv.geom) = 4326 then cv.geom else ST_Transform(cv.geom, 4326) end as geom
            from public.catastro_valledupar cv
           where cv.cod_usuario in (select distinct x.contrato from _l116_n x where x.contrato is not null and x.contrato not in ('0', '99999999')) and cv.geom is not null
           order by cv.cod_usuario, cv.id) c on c.cod_usuario = n.contrato;

  -- el sector hidráulico de cada reporte ubicado (el oficial, la misma regla de redes.f_sector_de: primero el subsector, luego el de menor área).
  -- Se recorren los polígonos vigentes (36) y, para cada uno, los puntos que caen dentro (índice espacial sobre los puntos): cada polígono se prepara una vez.
  if to_regclass('pg_temp._l116_sec') is not null then drop table pg_temp._l116_sec; end if;
  create temp table _l116_sec on commit drop as
  select m.activo_id, m.geom, (m.clase = 'subsector') as es_sub, ST_Area(m.geom) as area,
         case when redes.f_num(v.atributos -> 'modelo' -> 'sector') between 1 and 100 then redes.f_num(v.atributos -> 'modelo' -> 'sector')::smallint end as sector,
         case when m.clase = 'subsector' then nullif(btrim(v.atributos -> 'modelo' ->> 'subsector'), '') end as subsector
    from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
   where m.prefijo = 'SEC' and not m.retirado and not m.oculto;
  create index on _l116_u using gist (geom);
  analyze _l116_sec;
  analyze _l116_u;
  if to_regclass('pg_temp._l116_s') is not null then drop table pg_temp._l116_s; end if;
  create temp table _l116_s on commit drop as
  select distinct on (u.orden) u.orden, p.sector, p.subsector
    from _l116_sec p join _l116_u u on u.geom && p.geom and ST_Intersects(p.geom, u.geom)
   order by u.orden, p.es_sub desc, p.area, p.activo_id;
  analyze _l116_s;
  -- una sola escritura sobre los nuevos
  update _l116 l set metodo = case when u.orden is null then 'sin_ubicar' else 'contrato' end, geom = u.geom, sector = s.sector, subsector = s.subsector
    from _l116_n n left join _l116_u u on u.orden = n.orden left join _l116_s s on s.orden = n.orden
   where l.orden = n.orden;
end $$;

-- El resumen de una carga de la 116 (lo que muestra el paso «Revisar» y el paquete de psql). Cuando la carga está completa y sin bloqueos, deja guardada la
-- REVISIÓN (lo nuevo, lo que cambia de estado y lo que vuelve a mostrarse, con su ubicación ya calculada): la publicación la usa tal cual y no vuelve a ubicar nada.
-- Si nada cambió en la 116 desde la última revisión de esa carga, se devuelve la misma.
create function redes.f_resumen_l116(p_carga bigint) returns jsonb language plpgsql set search_path = redes, public, extensions, pg_temp as $$
declare c redes.v_cargas_estado%rowtype; v_rec integer; v_bloq text[] := '{}'; v_avisos text[] := '{}'; v_acc jsonb; v_ubic jsonb; v_serv jsonb; v_n integer; v_tabla jsonb;
        v_sin jsonb; v_sector integer; v_ult bigint; rv redes.l116_revisiones%rowtype; v_res jsonb; v_rev bigint;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  v_ult := coalesce((select max(id) from redes.l116_eventos), 0);
  if c.estado = 'abierta' then
    select * into rv from redes.l116_revisiones where carga_id = p_carga order by id desc limit 1;
    if found and rv.ultimo_evento = v_ult then return rv.resumen; end if;
  end if;
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
  if v_n > 0 then v_avisos := v_avisos || format('%s reportes nuevos quedan sin ubicar: su contrato no está en el catastro (no salen en el mapa; se guardan igual)', v_n); end if;
  select count(*) into v_n from _l116 where accion = 'mostrar';
  if v_n > 0 then v_avisos := v_avisos || format('%s reportes de una carga revertida vuelven a mostrarse', v_n); end if;

  select jsonb_build_object('nuevo', count(*) filter (where accion = 'nuevo'), 'estado', count(*) filter (where accion = 'estado'),
                            'igual', count(*) filter (where accion = 'igual'), 'mostrar', count(*) filter (where accion = 'mostrar'), 'error', count(*) filter (where accion = 'error'))
    into v_acc from _l116;
  select jsonb_build_object('contrato', count(*) filter (where metodo = 'contrato'), 'sin_ubicar', count(*) filter (where metodo = 'sin_ubicar')),
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
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'sin ubicar (el contrato no está en el catastro)', 'v', (v_ubic ->> 'sin_ubicar')),
      jsonb_build_object('s', '3 ubicación de los nuevos', 'c', 'con sector hidráulico', 'v', v_sector::text))
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '4 servicio de los nuevos', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_serv))
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '7 avisos', 'c', 'aviso', 'v', a)), '[]'::jsonb) from unnest(v_avisos) a)
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '8 bloqueos', 'c', 'BLOQUEO', 'v', b)), '[]'::jsonb) from unnest(v_bloq) b)
    || jsonb_build_array(jsonb_build_object('s', '9 resultado', 'c', 'lista para publicar', 'v', case when cardinality(v_bloq) = 0 then 'SÍ' else 'NO' end));
  v_res := jsonb_build_object('carga_id', c.id, 'capa', 'linea_116', 'estado', c.estado, 'recibidas', v_rec, 'esperadas', c.filas_esperadas,
    'frente_a_vigente', v_acc, 'ubicacion', v_ubic, 'con_sector', v_sector, 'servicios', v_serv, 'sin_ubicar_muestra', v_sin,
    'avisos', to_jsonb(v_avisos), 'bloqueos', to_jsonb(v_bloq), 'lista_para_publicar', cardinality(v_bloq) = 0, 'tabla', v_tabla);
  if cardinality(v_bloq) = 0 then
    -- la revisión: solo se agrega (una carga puede tener varias; vale la última si la 116 no cambió desde entonces). Los iguales no se guardan: solo se cuentan
    v_rev := nextval(pg_get_serial_sequence('redes.l116_revisiones', 'id'));
    v_res := v_res || jsonb_build_object('revision_id', v_rev);
    insert into redes.l116_revisiones (id, carga_id, ultimo_evento, resumen) overriding system value values (v_rev, p_carga, v_ult, v_res);
    insert into redes.l116_revision_filas (revision_id, orden, accion, reporte, reporte_id, fecha, estado, estado_vigente, servicio, causal, comuna, contrato,
                                           metodo, geom, sector, subsector)
    select v_rev, orden, accion, reporte, reporte_id, fecha, estado, estado_vigente, servicio, causal, comuna, contrato, metodo, geom, sector, subsector
      from _l116 where accion in ('nuevo', 'estado', 'mostrar');
  end if;
  return v_res;
end $$;

-- Publicar una carga de la 116 a partir de su revisión (no vuelve a leer el archivo ni a ubicar): los nuevos (reporte, alta con su ubicación y lo vigente), los
-- cambios de estado (evento con fecha) y los que vuelven. Nada se borra.
create function redes.f_publicar_l116(p_carga bigint, p_autor text, p_motivo text) returns jsonb language plpgsql set search_path = redes, public, extensions, pg_temp as $$
declare c redes.v_cargas_estado%rowtype; v_res jsonb; v_rev bigint; v_version integer; v_nuevos integer; v_estado integer; v_mostrar integer; v_iguales integer; v_mot text := btrim(p_motivo);
begin
  perform pg_advisory_xact_lock(hashtext('redes.carga.linea_116'));
  select * into c from redes.v_cargas_estado where id = p_carga;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: no se puede publicar', p_carga, c.estado)); end if;
  v_res := redes.f_resumen_l116(p_carga);      -- la última revisión si sigue valiendo; si la 116 cambió desde entonces, una nueva
  if not (v_res ->> 'lista_para_publicar')::boolean then
    perform tecnica.f_error('La carga no está lista para publicar: ' || array_to_string(array(select jsonb_array_elements_text(v_res -> 'bloqueos')), '; '));
  end if;
  v_rev := (v_res ->> 'revision_id')::bigint;
  v_version := (select count(*) + 1 from redes.v_cargas_estado x where x.capa_codigo = 'linea_116' and x.estado = 'publicada');
  -- (a) nuevos
  insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, comuna, contrato, carga_id)
  select f.reporte, f.fecha, f.servicio, f.causal, f.comuna, f.contrato, p_carga
    from redes.l116_revision_filas f where f.revision_id = v_rev and f.accion = 'nuevo' order by f.reporte;
  get diagnostics v_nuevos = row_count;
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, sector, subsector, carga_id, motivo, autor)
  select r.id, 'alta', f.estado, f.metodo, f.geom, f.sector, f.subsector, p_carga, v_mot, p_autor
    from redes.l116_revision_filas f join redes.l116_reportes r on r.reporte = f.reporte
   where f.revision_id = v_rev and f.accion = 'nuevo' order by r.id;
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, contrato, estado, estado_desde, metodo, geom, sector, subsector)
  select r.id, f.reporte, f.fecha, (f.fecha at time zone 'America/Bogota')::date, f.servicio, f.causal, f.contrato, f.estado, f.fecha, f.metodo, f.geom, f.sector, f.subsector
    from redes.l116_revision_filas f join redes.l116_reportes r on r.reporte = f.reporte
   where f.revision_id = v_rev and f.accion = 'nuevo';
  -- (b) cambios de estado (también los de los que vuelven a mostrarse)
  insert into redes.l116_eventos (reporte_id, tipo, estado, estado_antes, carga_id, motivo, autor)
  select f.reporte_id, 'estado', f.estado, f.estado_vigente, p_carga, v_mot, p_autor
    from redes.l116_revision_filas f where f.revision_id = v_rev and f.accion in ('estado', 'mostrar') and f.estado <> f.estado_vigente order by f.reporte_id;
  get diagnostics v_estado = row_count;
  -- (c) los que vuelven a mostrarse (los había ocultado la reversa de una carga)
  insert into redes.l116_eventos (reporte_id, tipo, carga_id, motivo, autor)
  select f.reporte_id, 'mostrar', p_carga, v_mot, p_autor from redes.l116_revision_filas f where f.revision_id = v_rev and f.accion = 'mostrar' order by f.reporte_id;
  get diagnostics v_mostrar = row_count;
  update redes.l116_vigente v set estado = f.estado, estado_desde = case when v.estado <> f.estado then clock_timestamp() else v.estado_desde end,
         oculto = false, actualizado_en = clock_timestamp()
    from redes.l116_revision_filas f where f.revision_id = v_rev and f.accion in ('estado', 'mostrar') and f.reporte_id = v.reporte_id;
  v_iguales := (v_res -> 'frente_a_vigente' ->> 'igual')::integer;
  insert into redes.carga_eventos (carga_id, tipo, version_capa, nuevos, cambiados, iguales, retirados, reactivados, detalle, motivo, autor)
  values (p_carga, 'publicar', v_version, v_nuevos, v_estado, v_iguales, 0, v_mostrar,
          jsonb_build_object('ubicacion', v_res -> 'ubicacion', 'con_sector', v_res -> 'con_sector', 'servicios', v_res -> 'servicios', 'revision_id', v_rev), v_mot, p_autor);
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
