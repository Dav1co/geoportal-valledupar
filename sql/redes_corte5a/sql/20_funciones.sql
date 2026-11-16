-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 20 — FUNCIONES Y VISTA NUEVAS (internas: nadie de la API las ejecuta)
-- PROPUESTA. No se ha ejecutado en la base real.
--   · redes.f_fusionar_ficha: en una recarga GANA LO EDITADO EN LA FICHA (§26.3) y arma la lista de choques para el resumen (pendientes 17c).
--   · la capa MUE: candidatos, resumen, publicar y revertir sobre tecnica.puntos (solo agrega y cambia «activo» con evento) y tecnica.puntos_ubicacion.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. RECARGA: GANA LA FICHA (§26.3)
--    Trabaja sobre la tabla temporal _cand que arma f_preparar_candidatos (la usan resumen y publicar en la misma transacción).
--    · Campos «de la ficha»: los que alguna vez se editaron en la ficha del activo (redes.ficha_ediciones), salvo alias y placa (no van en la versión).
--      La capa no los pisa: la versión nueva toma el valor vigente en esos campos y el de la capa en los demás (la geometría siempre es de la capa).
--    · Fecha de instalación y barrio o sector no vienen en ninguna capa: se conservan siempre (antes una recarga los dejaba vacíos).
--    · El origen corregido en la ficha tampoco lo pisa la capa (lo respeta publicar).
--    · Choque = campo de la ficha que la capa TRAE con otro valor (si la capa no trae el dato, no es choque: simplemente gana la ficha).
--      Se listan en _choques; no bloquean la publicación.
--    · Con la fusión se recalcula la huella: si ya no hay diferencia, la fila queda «igual» y no crea versión.
-- ---------------------------------------------------------------------
create function redes.f_fusionar_ficha() returns integer
language plpgsql set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
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
end $f$;

-- ---------------------------------------------------------------------
-- 2. CAPA MUE (puntos de muestreo, 01 sección E)
-- ---------------------------------------------------------------------
-- Ubicación vigente de cada punto: la última que no sea de una carga revertida.
create view redes.v_punto_ubicacion_vigente as
select distinct on (u.punto_id) u.*
  from tecnica.puntos_ubicacion u
 where u.carga_id is null or not exists (select 1 from redes.carga_eventos e where e.carga_id = u.carga_id and e.tipo = 'revertir')
 order by u.punto_id, u.id desc;

-- Candidatos de una carga MUE (tabla temporal _mue). Columnas del archivo: codigo (la llave; vacía = el siguiente MUE-nn), nombre, zona, barrio,
-- exactitud (o «precision»: verificada | aproximada; por omisión aproximada) y fuente (david | barrio | carga; por omisión carga).
create function redes.f_candidatos_muestreo(p_carga bigint) returns void
language plpgsql set search_path to 'redes', 'tecnica', 'public', 'extensions', 'pg_temp' as $f$
begin
  if to_regclass('pg_temp._mue') is not null then drop table pg_temp._mue; end if;
  create temp table _mue on commit drop as
  select cf.orden, upper(nullif(btrim(cf.llave), '')) as codigo, nullif(btrim(cf.atributos ->> 'nombre'), '') as nombre,
         lower(nullif(btrim(cf.atributos ->> 'zona'), '')) as zona, nullif(btrim(cf.atributos ->> 'barrio'), '') as barrio,
         lower(coalesce(nullif(btrim(cf.atributos ->> 'exactitud'), ''), nullif(btrim(cf.atributos ->> 'precision'), ''), 'aproximada')) as exactitud,
         lower(coalesce(nullif(btrim(cf.atributos ->> 'fuente'), ''), 'carga')) as fuente,
         case when cf.geom is not null and ST_GeometryType(cf.geom) = 'ST_Point' then round(ST_Y(cf.geom)::numeric, 6) end as lat,
         case when cf.geom is not null and ST_GeometryType(cf.geom) = 'ST_Point' then round(ST_X(cf.geom)::numeric, 6) end as lon,
         coalesce(cf.error, case when ST_GeometryType(cf.geom) <> 'ST_Point' then 'No es un punto' end) as error,
         p.id as punto_id, p.tipo as tipo_vigente, p.activo as activo_vigente, p.nombre as nombre_vigente,
         u.lat as lat_vigente, u.lon as lon_vigente, u.exactitud as exactitud_vigente, null::text as accion, null::text as codigo_nuevo
    from redes.carga_filas cf
    left join tecnica.puntos p on p.codigo = upper(nullif(btrim(cf.llave), ''))
    left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
   where cf.carga_id = p_carga;
  update _mue set accion = case when codigo is null then 'nuevo_sin_codigo'
                                when punto_id is null then 'nuevo'
                                when not activo_vigente then 'reactivar'
                                when lat_vigente is distinct from lat or lon_vigente is distinct from lon or exactitud_vigente is distinct from exactitud then 'ubicacion'
                                else 'igual' end;
end $f$;

create function redes.f_resumen_muestreo(p_carga bigint) returns jsonb
language plpgsql set search_path to 'redes', 'tecnica', 'public', 'extensions', 'pg_temp' as $f$
declare c redes.v_cargas_estado%rowtype; v_rec integer; v_bloq text[] := '{}'; v_avisos text[] := '{}'; v_tabla jsonb; v_acc jsonb; v_desac jsonb; v_n integer;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  select count(*) into v_rec from redes.carga_filas where carga_id = p_carga;
  if c.estado <> 'abierta' then v_bloq := v_bloq || ('La carga está ' || c.estado); end if;
  if v_rec <> c.filas_esperadas then v_bloq := v_bloq || format('Llegaron %s de %s filas: falta algún lote', v_rec, c.filas_esperadas); end if;
  perform redes.f_candidatos_muestreo(p_carga);
  select count(*) into v_n from _mue where error is not null;
  if v_n > 0 then v_bloq := v_bloq || format('%s filas sin un punto válido: %s', v_n, (select string_agg(coalesce(codigo, 'fila ' || orden) || ' (' || error || ')', ', ') from _mue where error is not null)); end if;
  select count(*) into v_n from (select codigo from _mue where codigo is not null group by codigo having count(*) > 1) x;
  if v_n > 0 then v_bloq := v_bloq || format('%s códigos repetidos en el archivo', v_n); end if;
  if exists (select 1 from _mue where codigo is not null and codigo !~ '^MUE-[0-9]{2,4}$') then
    v_bloq := v_bloq || ('Los códigos de los puntos de muestreo son MUE-nn: ' || (select string_agg(codigo, ', ') from _mue where codigo is not null and codigo !~ '^MUE-[0-9]{2,4}$'));
  end if;
  if exists (select 1 from _mue where tipo_vigente is not null and tipo_vigente <> 'muestreo') then
    v_bloq := v_bloq || ('Estos códigos son de otro tipo de punto: ' || (select string_agg(codigo, ', ') from _mue where tipo_vigente is not null and tipo_vigente <> 'muestreo'));
  end if;
  if exists (select 1 from _mue where accion in ('nuevo', 'nuevo_sin_codigo') and (nombre is null or length(nombre) not between 2 and 120)) then
    v_bloq := v_bloq || 'Un punto nuevo necesita su nombre (2 a 120 caracteres)'::text;
  end if;
  if exists (select 1 from _mue where exactitud not in ('verificada', 'aproximada')) then v_bloq := v_bloq || 'La exactitud es «verificada» o «aproximada»'::text; end if;
  if exists (select 1 from _mue where fuente not in ('david', 'barrio', 'carga')) then v_bloq := v_bloq || 'La fuente es «david», «barrio» o «carga» (el GPS del operador entra por el formulario)'::text; end if;
  if exists (select 1 from _mue where zona is not null and zona not in ('norte', 'sur', 'medio')) then v_bloq := v_bloq || 'La zona es norte, sur o medio'::text; end if;
  if exists (select 1 from _mue where barrio is not null and length(barrio) > 120) then v_bloq := v_bloq || 'El barrio admite hasta 120 caracteres'::text; end if;
  if exists (select 1 from _mue where lat is not null and (lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max'))) then
    v_bloq := v_bloq || ('Puntos fuera de Valledupar (revise el sistema de coordenadas): ' || (select string_agg(coalesce(codigo, 'fila ' || orden), ', ') from _mue
                                  where lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max')));
  end if;
  if exists (select 1 from _mue where punto_id is not null and nombre is not null and redes.f_norm(nombre) <> redes.f_norm(nombre_vigente)) then
    v_avisos := v_avisos || ('El nombre del archivo no es el de tecnica.puntos (no se cambia): ' || (select string_agg(codigo || ' «' || nombre || '» / «' || nombre_vigente || '»', ', ')
                               from _mue where punto_id is not null and nombre is not null and redes.f_norm(nombre) <> redes.f_norm(nombre_vigente)));
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre) order by p.codigo), '[]'::jsonb) into v_desac
    from tecnica.puntos p where p.tipo = 'muestreo' and p.activo and not exists (select 1 from _mue m where m.codigo = p.codigo);
  if jsonb_array_length(v_desac) > 0 then
    v_avisos := v_avisos || format('%s puntos activos no vienen en el archivo: se DESACTIVAN y salen del formulario de Muestreo desde la publicación (sus registros siguen): %s',
                                   jsonb_array_length(v_desac), (select string_agg(x ->> 'codigo', ', ') from jsonb_array_elements(v_desac) x));
  end if;
  select coalesce(jsonb_object_agg(accion, n order by accion), '{}'::jsonb) into v_acc from (select accion, count(*) n from _mue group by accion) x;
  v_tabla := jsonb_build_array(
      jsonb_build_object('s', '1 carga', 'c', 'capa', 'v', 'muestreo'), jsonb_build_object('s', '1 carga', 'c', 'carga', 'v', c.id || ' (' || c.estado || ')'),
      jsonb_build_object('s', '1 carga', 'c', 'filas recibidas / esperadas', 'v', v_rec || ' / ' || c.filas_esperadas))
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '2 frente a lo vigente', 'c', key, 'v', value::text) order by key), '[]'::jsonb) from jsonb_each(v_acc))
    || jsonb_build_array(jsonb_build_object('s', '2 frente a lo vigente', 'c', 'desactivar (no vienen)', 'v', jsonb_array_length(v_desac)::text))
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '3 puntos', 'c', coalesce(m.codigo, 'fila ' || m.orden) || ' ' || coalesce(m.nombre, m.nombre_vigente, ''),
                                                    'v', m.accion || ' · ' || m.exactitud || ' (' || m.fuente || ')' || coalesce(' · barrio ' || m.barrio, '')
                                                         || coalesce(' · ' || m.lat || ', ' || m.lon, '')) order by m.codigo nulls last, m.orden), '[]'::jsonb) from _mue m)
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '7 avisos', 'c', 'aviso', 'v', a)), '[]'::jsonb) from unnest(v_avisos) a)
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '8 bloqueos', 'c', 'BLOQUEO', 'v', b)), '[]'::jsonb) from unnest(v_bloq) b)
    || jsonb_build_array(jsonb_build_object('s', '9 resultado', 'c', 'lista para publicar', 'v', case when cardinality(v_bloq) = 0 then 'SÍ' else 'NO' end));
  return jsonb_build_object('carga_id', c.id, 'capa', 'muestreo', 'estado', c.estado, 'recibidas', v_rec, 'esperadas', c.filas_esperadas, 'frente_a_vigente', v_acc,
    'desactivar', v_desac, 'puntos', (select coalesce(jsonb_agg(jsonb_build_object('orden', orden, 'codigo', codigo, 'nombre', coalesce(nombre, nombre_vigente), 'barrio', barrio,
                                        'exactitud', exactitud, 'fuente', fuente, 'lat', lat, 'lon', lon, 'accion', accion, 'error', error) order by codigo nulls last, orden), '[]'::jsonb) from _mue),
    'avisos', to_jsonb(v_avisos), 'bloqueos', to_jsonb(v_bloq), 'lista_para_publicar', cardinality(v_bloq) = 0, 'tabla', v_tabla);
end $f$;

-- Publicar una carga MUE: agrega los puntos nuevos a tecnica.puntos (con su evento «crear»), reactiva los que vuelven, DESACTIVA los activos que no vienen
-- (con su evento; nunca se borran y sus registros siguen) y agrega la ubicación nueva de lo que cambió. Un candado por capa y uno global de puntos.
create function redes.f_publicar_muestreo(p_carga bigint, p_autor text, p_motivo text) returns jsonb
language plpgsql set search_path to 'redes', 'tecnica', 'public', 'extensions', 'pg_temp' as $f$
declare c redes.v_cargas_estado%rowtype; v_res jsonb; v_sig integer; v_nuevos integer; v_reac integer; v_desac integer; v_ubic integer; v_version integer; v_mot text := btrim(p_motivo);
begin
  perform pg_advisory_xact_lock(hashtext('redes.carga.muestreo'));
  perform pg_advisory_xact_lock(hashtext('tecnica.puntos'));
  select * into c from redes.v_cargas_estado where id = p_carga;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: no se puede publicar', p_carga, c.estado)); end if;
  v_res := redes.f_resumen_muestreo(p_carga);          -- deja armada _mue
  if not (v_res ->> 'lista_para_publicar')::boolean then
    perform tecnica.f_error('La carga no está lista para publicar: ' || array_to_string(array(select jsonb_array_elements_text(v_res -> 'bloqueos')), '; '));
  end if;
  v_version := (select count(*) + 1 from redes.v_cargas_estado x where x.capa_codigo = 'muestreo' and x.estado = 'publicada');
  -- códigos para las filas sin código: el siguiente MUE-nn
  v_sig := coalesce((select max(substring(codigo from '^MUE-([0-9]+)$')::integer) from tecnica.puntos where codigo ~ '^MUE-[0-9]+$'), 0);
  update _mue m set codigo_nuevo = 'MUE-' || lpad((v_sig + x.rn)::text, 2, '0')
    from (select orden, row_number() over (order by orden) as rn from _mue where accion = 'nuevo_sin_codigo') x where x.orden = m.orden;
  update _mue set codigo = codigo_nuevo where accion = 'nuevo_sin_codigo';
  -- (a) puntos nuevos: solo se AGREGAN filas a tecnica.puntos
  insert into tecnica.puntos (codigo, nombre, tipo, zona, barrio)
  select codigo, nombre, 'muestreo', zona, barrio from _mue where accion in ('nuevo', 'nuevo_sin_codigo') order by codigo;
  get diagnostics v_nuevos = row_count;
  update _mue m set punto_id = p.id from tecnica.puntos p where p.codigo = m.codigo and m.accion in ('nuevo', 'nuevo_sin_codigo');
  insert into tecnica.punto_eventos (punto_id, tipo, motivo, carga_id, autor)
  select punto_id, 'crear', format('Punto nuevo de la carga %s de la capa de muestreo (versión %s): %s', p_carga, v_version, v_mot), p_carga, p_autor
    from _mue where accion in ('nuevo', 'nuevo_sin_codigo');
  -- (b) reactivar lo que vuelve
  update tecnica.puntos p set activo = true from _mue m where m.punto_id = p.id and m.accion = 'reactivar' and not p.activo;
  get diagnostics v_reac = row_count;
  insert into tecnica.punto_eventos (punto_id, tipo, motivo, carga_id, autor)
  select punto_id, 'reactivar', format('Volvió en la carga %s de la capa de muestreo (versión %s)', p_carga, v_version), p_carga, p_autor from _mue where accion = 'reactivar';
  -- (c) desactivar los activos que no vienen (nunca se borran; sus registros siguen)
  insert into tecnica.punto_eventos (punto_id, tipo, motivo, carga_id, autor)
  select p.id, 'desactivar', format('No vino en la carga %s de la capa de muestreo (versión %s): %s', p_carga, v_version, v_mot), p_carga, p_autor
    from tecnica.puntos p where p.tipo = 'muestreo' and p.activo and not exists (select 1 from _mue m where m.codigo = p.codigo);
  update tecnica.puntos p set activo = false where p.tipo = 'muestreo' and p.activo and not exists (select 1 from _mue m where m.codigo = p.codigo);
  get diagnostics v_desac = row_count;
  -- (d) ubicación: la de los nuevos y la de lo que cambió (o volvió con otra)
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, barrio_capa, carga_id, autor)
  select punto_id, lat, lon, exactitud, fuente, barrio, p_carga, p_autor from _mue
   where accion in ('nuevo', 'nuevo_sin_codigo', 'ubicacion')
      or (accion = 'reactivar' and (lat_vigente is distinct from lat or lon_vigente is distinct from lon or exactitud_vigente is distinct from exactitud));
  get diagnostics v_ubic = row_count;
  insert into redes.carga_eventos (carga_id, tipo, version_capa, nuevos, cambiados, iguales, retirados, reactivados, detalle, motivo, autor)
  values (p_carga, 'publicar', v_version, v_nuevos, v_ubic, (select count(*) from _mue where accion = 'igual'), v_desac, v_reac,
          jsonb_build_object('ubicaciones', v_ubic, 'codigos_asignados', (select coalesce(jsonb_agg(codigo_nuevo order by codigo_nuevo), '[]'::jsonb) from _mue where codigo_nuevo is not null)),
          v_mot, p_autor);
  delete from redes.carga_filas where carga_id = p_carga;
  return jsonb_build_object('carga_id', p_carga, 'capa', 'muestreo', 'version_capa', v_version, 'nuevos', v_nuevos, 'ubicaciones', v_ubic,
                            'reactivados', v_reac, 'desactivados', v_desac, 'iguales', (select count(*) from _mue where accion = 'igual'),
                            'codigos_asignados', (select coalesce(jsonb_agg(codigo_nuevo order by codigo_nuevo), '[]'::jsonb) from _mue where codigo_nuevo is not null));
end $f$;

-- Revertir la última carga MUE publicada: sus ubicaciones dejan de contar (la vista excluye las cargas revertidas); lo que desactivó se reactiva;
-- lo que creó o reactivó se desactiva (un punto creado no se puede borrar). Todo con eventos.
create function redes.f_revertir_muestreo(p_autor text, p_motivo text) returns jsonb
language plpgsql set search_path to 'redes', 'tecnica', 'public', 'extensions', 'pg_temp' as $f$
declare c redes.v_cargas_estado%rowtype; v_reac integer; v_desac integer;
begin
  perform pg_advisory_xact_lock(hashtext('redes.carga.muestreo'));
  perform pg_advisory_xact_lock(hashtext('tecnica.puntos'));
  select * into c from redes.v_cargas_estado where capa_codigo = 'muestreo' and estado = 'publicada' order by publicada_en desc limit 1;
  if not found then perform tecnica.f_error('La capa de muestreo no tiene una carga publicada para revertir'); end if;
  insert into redes.carga_eventos (carga_id, tipo, motivo, autor) values (c.id, 'revertir', btrim(p_motivo), p_autor);
  insert into tecnica.punto_eventos (punto_id, tipo, motivo, carga_id, autor)
  select e.punto_id, 'reactivar', format('Se revirtió la carga %s de la capa de muestreo, que lo había desactivado', c.id), null, p_autor
    from tecnica.punto_eventos e join tecnica.puntos p on p.id = e.punto_id where e.carga_id = c.id and e.tipo = 'desactivar' and not p.activo;
  update tecnica.puntos p set activo = true from tecnica.punto_eventos e where e.punto_id = p.id and e.carga_id = c.id and e.tipo = 'desactivar' and not p.activo;
  get diagnostics v_reac = row_count;
  insert into tecnica.punto_eventos (punto_id, tipo, motivo, carga_id, autor)
  select e.punto_id, 'desactivar', format('Se revirtió la carga %s de la capa de muestreo, que lo había %s', c.id, case e.tipo when 'crear' then 'creado' else 'reactivado' end), null, p_autor
    from tecnica.punto_eventos e join tecnica.puntos p on p.id = e.punto_id where e.carga_id = c.id and e.tipo in ('crear', 'reactivar') and p.activo;
  update tecnica.puntos p set activo = false from tecnica.punto_eventos e where e.punto_id = p.id and e.carga_id = c.id and e.tipo in ('crear', 'reactivar') and p.activo;
  get diagnostics v_desac = row_count;
  return jsonb_build_object('carga_id', c.id, 'capa', 'muestreo', 'reactivados', v_reac, 'desactivados', v_desac);
end $f$;
