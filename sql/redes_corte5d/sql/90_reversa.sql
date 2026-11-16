-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como estaban con el 9a-bis (texto exacto), quita las 7 nuevas y las 6 tablas de la 116 (vacías), desactiva la capa «linea_116» del Cargue, devuelve la capa
-- «pqr_116» del geovisor a «preparada» y DESACTIVA (no borra) los dos formularios compartidos en distribución.
-- SE NIEGA si alguna función cambió después de la migración o si ya hay cargas de la 116 (la reversa no borra datos: revierta las cargas en el Cargue y avise).
-- Las asignaciones de esos formularios hechas en Personal no se tocan (son hechos de tecnica.personal_tecnico_eventos).
-- =====================================================================
do $$
begin
  if to_regclass('redes.l116_reportes') is null then raise exception 'No hay nada que revertir: el Corte 5d no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '5fd6d00efdaa1a798e2628a2cde23c61' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 5d: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.cargas where capa_codigo = 'linea_116') or exists (select 1 from redes.l116_reportes) or exists (select 1 from redes.l116_revisiones) then
    raise exception 'Ya hay cargas de la línea 116: la reversa no borra datos; apague la capa del geovisor y avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto del 9a-bis (antes de quitar las nuevas, que ellas usan)
CREATE OR REPLACE FUNCTION redes.f_lote(p_carga bigint, p_filas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare c redes.v_cargas_estado%rowtype; v_n integer; v_nuevas integer;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: no recibe lotes', p_carga, c.estado)); end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then perform tecnica.f_error('El lote debe ser una lista de filas'); end if;
  v_n := jsonb_array_length(p_filas);
  if v_n < 1 or v_n > redes.f_param('lote_max_filas') then perform tecnica.f_error(format('Un lote lleva de 1 a %s filas', redes.f_param('lote_max_filas')::integer)); end if;
  if exists (select 1 from jsonb_array_elements(p_filas) e
              where jsonb_typeof(e) <> 'object' or jsonb_typeof(e -> 'orden') <> 'number' or jsonb_typeof(e -> 'atributos') <> 'object'
                 or (e ->> 'orden')::numeric <> trunc((e ->> 'orden')::numeric) or (e ->> 'orden')::integer < 1 or (e ->> 'orden')::integer > c.filas_esperadas) then
    perform tecnica.f_error(format('Cada fila lleva orden (1 a %s), atributos y wkt', c.filas_esperadas));
  end if;
  insert into redes.carga_filas (carga_id, orden, llave, atributos, geom, error)
  select p_carga, (e ->> 'orden')::integer, nullif(btrim(e -> 'atributos' ->> c.columna_llave), ''), e -> 'atributos', g.geom, g.error
    from jsonb_array_elements(p_filas) e
    cross join lateral redes.f_geo_desde_wkt(e ->> 'wkt', c.srid_origen) g
  on conflict (carga_id, orden) do nothing;
  get diagnostics v_nuevas = row_count;
  return jsonb_build_object('carga_id', p_carga, 'nuevas', v_nuevas, 'repetidas', v_n - v_nuevas,
                            'recibidas', (select count(*) from redes.carga_filas where carga_id = p_carga));
end $function$;
revoke all on function redes.f_lote(bigint,jsonb) from public, anon, authenticated, service_role;

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
  if v_nulas > 0 and c.columna_llave <> '(geometria)' then v_bloq := v_bloq || format('%s filas sin llave (%s)', v_nulas, c.columna_llave); end if;      -- Corte 5c: sin llave = por geometría
  if v_rep > 0 then v_bloq := v_bloq || format('%s llaves repetidas en %s: elija otra columna llave o cargue «sin columna llave» (cruce por geometría, D-4)', v_rep, c.columna_llave); end if;

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
    -- Corte 5c: el cruce por geometría (D-4) y la geometría que no corresponde al tipo de la capa
    if c.columna_llave = '(geometria)' then
      v_extra := v_extra || jsonb_build_object('cruce_por_geometria', jsonb_build_object('tolerancia_m', redes.f_param('cruce_geometria_tol_m'),
        'cruzados', (select count(*) from _cand where crea_activo and llave not like 'G' || p_carga || '-%'),
        'sin_par_nuevos', (select count(*) from _cand where crea_activo and llave like 'G' || p_carga || '-%')));
    end if;
    if exists (select 1 from _cand k join redes.tipos_activo t on t.prefijo = k.prefijo where k.crea_activo
                  and not ((t.geometria = 'punto' and GeometryType(k.geom) = 'POINT') or (t.geometria = 'linea' and GeometryType(k.geom) in ('LINESTRING', 'MULTILINESTRING'))
                           or (t.geometria = 'poligono' and GeometryType(k.geom) in ('POLYGON', 'MULTIPOLYGON')))) then
      v_bloq := v_bloq || format('%s filas con una geometría que no es la del tipo (%s): revise el archivo o la capa elegida',
        (select count(*) from _cand k join redes.tipos_activo t on t.prefijo = k.prefijo where k.crea_activo
            and not ((t.geometria = 'punto' and GeometryType(k.geom) = 'POINT') or (t.geometria = 'linea' and GeometryType(k.geom) in ('LINESTRING', 'MULTILINESTRING'))
                     or (t.geometria = 'poligono' and GeometryType(k.geom) in ('POLYGON', 'MULTIPOLYGON')))),
        (select string_agg(distinct t.geometria, ', ') from _cand k join redes.tipos_activo t on t.prefijo = k.prefijo where k.crea_activo));
    end if;
    if exists (select 1 from _cand where crea_activo and pg_column_size(atributos) > 16000) then
      v_bloq := v_bloq || format('%s filas con demasiados atributos (más de 16 KB): quite columnas del archivo', (select count(*) from _cand where crea_activo and pg_column_size(atributos) > 16000));
    end if;
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

CREATE OR REPLACE FUNCTION redes.f_publicar(p_carga bigint, p_autor text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  c redes.v_cargas_estado%rowtype; v_res jsonb; v_tol numeric := redes.f_param('tolerancia_nodo_m'); v_sis text; v_cub text[];
  v_nuevos integer; v_cambiados integer; v_iguales integer; v_retirados integer; v_reactivados integer; v_nodos integer := 0; v_tn integer := 0;
  v_extremos integer := 0; v_sin_nodo integer := 0; v_ct integer; v_mat integer; v_version_capa integer; v_origen integer; v_mac integer;
  t0 timestamptz := clock_timestamp();
begin
  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo de la publicación (10 caracteres o más)'); end if;
  if (select capa_codigo from redes.cargas where id = p_carga) = 'muestreo' then return redes.f_publicar_muestreo(p_carga, p_autor, p_motivo); end if;      -- capa MUE (Corte 5a)
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.carga.' || c.capa_codigo));
  select * into c from redes.v_cargas_estado where id = p_carga;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: no se puede publicar', p_carga, c.estado)); end if;
  if c.capa_codigo = 'alc_conductos' and exists (select 1 from redes.v_cargas_estado where estado = 'abierta' and capa_codigo in ('alc_pozos', 'alc_descargas')) then
    perform tecnica.f_error('Publique primero los pozos y las descargas: los conductos se enlazan con ellos');
  end if;
  v_res := redes.f_resumen(p_carga);                         -- deja armada la tabla temporal _cand
  if not (v_res ->> 'lista_para_publicar')::boolean then
    perform tecnica.f_error('La carga no está lista para publicar: ' || array_to_string(array(select jsonb_array_elements_text(v_res -> 'bloqueos')), '; '));
  end if;
  v_sis := (select sistema from redes.capas where codigo = c.capa_codigo);
  v_cub := redes.f_capas_cubiertas(c.capa_codigo);

  alter table _cand add column activo_previo bigint, add column version_nueva integer;
  update _cand set activo_previo = activo_id, activo_id = null, codigo = null where accion = 'nuevo_por_tipo';

  -- (a) activos nuevos, con su código por prefijo (el update de consecutivos toma el candado de fila)
  if to_regclass('pg_temp._nuevos') is not null then drop table pg_temp._nuevos; end if; create temp table _nuevos on commit drop as
  select k.capa_codigo, k.llave, k.prefijo, row_number() over (partition by k.prefijo order by k.capa_codigo, k.orden, k.llave) as rn
    from _cand k where k.accion in ('nuevo', 'nuevo_por_tipo');
  if to_regclass('pg_temp._base') is not null then drop table pg_temp._base; end if; create temp table _base (prefijo text, base bigint) on commit drop;
  with req as (select prefijo, count(*) as n from _nuevos group by prefijo),
       upd as (update redes.consecutivos k set ultimo = k.ultimo + r.n from req r where k.prefijo = r.prefijo returning k.prefijo, k.ultimo - r.n as base)
  insert into _base select prefijo, base from upd;
  if exists (select 1 from _nuevos n where not exists (select 1 from _base b where b.prefijo = n.prefijo)) then
    perform tecnica.f_error('Falta el consecutivo de algún prefijo');
  end if;
  update _cand k set codigo = n.prefijo || '-' || lpad((b.base + n.rn)::text, 6, '0')
    from _nuevos n join _base b on b.prefijo = n.prefijo
   where n.capa_codigo = k.capa_codigo and n.llave = k.llave and k.accion in ('nuevo', 'nuevo_por_tipo');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por)
  select codigo, prefijo, 'carga', p_autor from _cand where accion in ('nuevo', 'nuevo_por_tipo') order by prefijo, codigo;
  get diagnostics v_nuevos = row_count;
  update _cand k set activo_id = a.id from redes.activos a where k.accion in ('nuevo', 'nuevo_por_tipo') and a.codigo = k.codigo;

  -- (b) versiones: la 1 de los nuevos y la siguiente de los cambiados
  update _cand k set version_nueva = case when k.accion in ('nuevo', 'nuevo_por_tipo') then 1
                                          else (select max(v.version) + 1 from redes.activo_versiones v where v.activo_id = k.activo_id) end
   where k.accion in ('nuevo', 'nuevo_por_tipo', 'cambiado');
  -- Corte 5a: la fecha de instalación y el barrio o sector (no vienen en ninguna capa) se conservan
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m,
         estado_codigo, atributos, codigo_anterior, capa_codigo, llave_capa, carga_id, huella, autor, fecha_instalacion, barrio_sector)
  select activo_id, version_nueva, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m,
         estado_codigo, atributos, codigo_anterior, capa_codigo, llave, p_carga, huella, p_autor, fecha_instalacion, barrio_sector
    from _cand where version_nueva is not null order by activo_id;
  select count(*) filter (where accion = 'cambiado'), count(*) filter (where accion in ('igual', 'reactivar')) into v_cambiados, v_iguales from _cand;
  -- Estadísticas al día: las tablas se acaban de llenar en esta misma transacción y, sin esto, el planificador
  -- elige bucles anidados (la publicación de conductos pasó de 90 s a pocos segundos en local).
  analyze redes.activos; analyze redes.activo_versiones; analyze _cand;

  -- (c) origen (solo lo ve el supervisor, D-11): cuando es nuevo o cambió. SIVA = tercero, sin soporte.
  insert into redes.activo_origen (activo_id, version, origen, aportante_codigo, nota, carga_id, autor)
  select k.activo_id, coalesce(k.version_nueva, k.version_vigente), k.origen, k.aportante_codigo,
         case when k.aportante_codigo = 'siva' then 'Zona SIVA del modelo de acueducto: obra de una entidad del Gobierno. Sin soporte todavía.' end, p_carga, p_autor
    from _cand k left join redes.v_activo_origen_vigente o on o.activo_id = k.activo_id
   where k.crea_activo and k.activo_id is not null
     and (o.activo_id is null or o.origen is distinct from k.origen or o.aportante_codigo is distinct from k.aportante_codigo)
     and not ('origen' = any (coalesce(k.campos_ficha, '{}')));      -- Corte 5a (§26.3): el origen corregido en la ficha no lo pisa la capa
  get diagnostics v_origen = row_count;

  -- (d) MACRO n del modelo ↔ MAC-nn de tecnica.puntos (N-8). Sin fk: tecnica.puntos no se toca.
  insert into redes.activo_punto (activo_id, punto_codigo, punto_id, motivo, carga_id, autor)
  select k.activo_id, 'MAC-' || lpad(k.macro_num::text, 2, '0'), (select p.id from tecnica.puntos p where p.codigo = 'MAC-' || lpad(k.macro_num::text, 2, '0')),
         'Enlace por el número del MACRO del modelo hidráulico (N-8)', p_carga, p_autor
    from _cand k left join redes.v_activo_punto_vigente ap on ap.activo_id = k.activo_id
   where k.macro_num is not null and k.activo_id is not null and ap.activo_id is null;
  get diagnostics v_mac = row_count;

  -- (e) retiros: lo vigente de las capas que cubre la carga y que no vino (con motivo), y el activo viejo cuando cambió de tipo
  insert into redes.activo_eventos (activo_id, tipo, motivo, carga_id, autor)
  select v.activo_id, 'retirar', format('No vino en la carga %s de la capa %s (versión %s de la capa)', p_carga, c.capa_codigo,
                                        (select count(*) + 1 from redes.v_cargas_estado x where x.capa_codigo = c.capa_codigo and x.estado = 'publicada')), p_carga, p_autor
    from redes.v_activo_vigente v
   where v.capa_codigo = any (v_cub) and not v.retirado
     and not exists (select 1 from _cand k where k.activo_id = v.activo_id);
  get diagnostics v_retirados = row_count;
  -- (f) reactivar lo que estaba retirado y volvió
  insert into redes.activo_eventos (activo_id, tipo, motivo, carga_id, autor)
  select k.activo_id, 'reactivar', format('Volvió en la carga %s de la capa %s', p_carga, c.capa_codigo), p_carga, p_autor
    from _cand k where k.retirado_vigente and k.accion in ('reactivar', 'cambiado');
  get diagnostics v_reactivados = row_count;

  -- Corte 5a (17f): los nodos que el administrador clasificó en la bandeja (activo enlazado con un evento) conservan su activo en la recarga
  if to_regclass('pg_temp._bandeja') is not null then drop table pg_temp._bandeja; end if;
  create temp table _bandeja on commit drop as
  select k.nodo_sistema as sistema, k.llave, n.activo_id from _cand k join redes.v_nodo_vigente n on n.sistema = k.nodo_sistema and n.llave_modelo = k.llave
   where k.crea_nodo and not k.crea_activo and k.clase_nodo = 'por_clasificar' and n.activo_id is not null;
  -- (g) nodos: se inserta solo si es nuevo o cambió (nombre, posición, activo o clase); el vigente idéntico se reutiliza
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id)
  select k.nodo_sistema, k.llave, k.nodo_nombre, k.clase_nodo, k.geom, case when k.crea_activo then k.activo_id end, round(k.dispersion_m, 3), p_carga
    from _cand k left join redes.v_nodo_vigente n on n.sistema = k.nodo_sistema and n.llave_modelo = k.llave
   where k.crea_nodo and k.llave is not null
     and (n.nodo_id is null or n.nombre_modelo is distinct from k.nodo_nombre or not ST_Equals(n.geom, k.geom)
          or ((n.activo_id is distinct from (case when k.crea_activo then k.activo_id end) or n.clase_nodo <> k.clase_nodo)
              and not exists (select 1 from _bandeja b where b.sistema = k.nodo_sistema and b.llave = k.llave)));
  get diagnostics v_nodos = row_count;
  -- 17f: si el nodo cambió de nombre o de posición, el nodo nuevo queda enlazado al mismo activo de la bandeja
  insert into redes.nodo_eventos (nodo_id, tipo, activo_id, motivo, autor)
  select n.id, 'enlazar_activo', b.activo_id, format('Se conserva el activo de la bandeja de nodos por clasificar en la carga %s', p_carga), p_autor
    from redes.nodos n join _bandeja b on b.sistema = n.sistema and b.llave = n.llave_modelo where n.carga_id = p_carga;
  analyze redes.nodos;

  -- (h) topología de los tramos con versión nueva: por el modelo (llaves de nodo) y, si falta, por extremos (tolerancia_nodo_m)
  if c.capa_codigo in ('acueducto', 'alc_conductos') then
    if to_regclass('pg_temp._vn') is not null then drop table pg_temp._vn; end if; create temp table _vn on commit drop as select nodo_id, llave_modelo, geom from redes.v_nodo_vigente where sistema = v_sis;
    create index on _vn (llave_modelo);
    create index on _vn using gist (geom);
    if to_regclass('pg_temp._tn') is not null then drop table pg_temp._tn; end if; create temp table _tn on commit drop as
    select k.activo_id, k.version_nueva as version, k.geom, ni.nodo_id as ini_m, nf.nodo_id as fin_m, null::bigint as ini_e, null::bigint as fin_e
      from _cand k
      left join _vn ni on ni.llave_modelo = k.nodo_ini
      left join _vn nf on nf.llave_modelo = k.nodo_fin
     where k.version_nueva is not null and k.capa_codigo in ('acueducto', 'alc_conductos');
    update _tn t set ini_e = (select n.nodo_id from _vn n where ST_DWithin(n.geom::geography, ST_StartPoint(t.geom)::geography, v_tol) order by n.geom <-> ST_StartPoint(t.geom) limit 1)
     where t.ini_m is null;
    update _tn t set fin_e = (select n.nodo_id from _vn n where ST_DWithin(n.geom::geography, ST_EndPoint(t.geom)::geography, v_tol) order by n.geom <-> ST_EndPoint(t.geom) limit 1)
     where t.fin_m is null;
    insert into redes.tramo_nodos (activo_id, version, nodo_ini, nodo_fin, metodo, carga_id)
    select activo_id, version, coalesce(ini_m, ini_e), coalesce(fin_m, fin_e),
           case when ini_m is not null and fin_m is not null then 'modelo'
                when coalesce(ini_m, ini_e) is not null and coalesce(fin_m, fin_e) is not null then 'extremos' else 'sin_nodo' end, p_carga
      from _tn;
    get diagnostics v_tn = row_count;
    select count(*) filter (where (ini_m is null or fin_m is null) and coalesce(ini_m, ini_e) is not null and coalesce(fin_m, fin_e) is not null),
           count(*) filter (where coalesce(ini_m, ini_e) is null or coalesce(fin_m, fin_e) is null)
      into v_extremos, v_sin_nodo from _tn;
  end if;

  -- (i) cierre: evento, staging vaciado, derivados
  v_version_capa := (select count(*) + 1 from redes.v_cargas_estado x where x.capa_codigo = c.capa_codigo and x.estado = 'publicada');
  v_mat := redes.f_refrescar_vigente();
  if c.capa_codigo = 'acueducto' then v_ct := redes.f_recalcular_contrato_tramo(); end if;
  perform redes.f_subir_tesela(v_sis);
  insert into redes.carga_eventos (carga_id, tipo, version_capa, nuevos, cambiados, iguales, retirados, reactivados, detalle, motivo, autor)
  values (p_carga, 'publicar', v_version_capa, v_nuevos, v_cambiados, v_iguales, v_retirados, v_reactivados,
          jsonb_build_object('por_prefijo', v_res -> 'por_prefijo', 'nodos_insertados', v_nodos, 'tramo_nodos', v_tn, 'tramos_por_extremos', v_extremos,
                             'tramos_sin_nodo', v_sin_nodo, 'origen', v_origen, 'enlaces_mac', v_mac, 'contrato_tramo', v_ct, 'activos_vigentes_mat', v_mat,
                             'segundos', round(extract(epoch from clock_timestamp() - t0)::numeric, 1)),
          btrim(p_motivo), p_autor);
  delete from redes.carga_filas where carga_id = p_carga;
  return jsonb_build_object('carga_id', p_carga, 'capa', c.capa_codigo, 'version_capa', v_version_capa, 'nuevos', v_nuevos, 'cambiados', v_cambiados,
    'iguales', v_iguales, 'retirados', v_retirados, 'reactivados', v_reactivados, 'nodos_insertados', v_nodos, 'tramo_nodos', v_tn,
    'tramos_por_extremos', v_extremos, 'tramos_sin_nodo', v_sin_nodo, 'origen', v_origen, 'enlaces_mac', v_mac, 'contrato_tramo', v_ct,
    'activos_vigentes', v_mat, 'segundos', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $function$;
revoke all on function redes.f_publicar(bigint,text,text) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION redes.f_revertir(p_capa text, p_autor text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare c redes.v_cargas_estado%rowtype; v_sis text; v_reac integer; v_ret integer; v_ct integer; v_mat integer;
begin
  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  if p_capa = 'muestreo' then return redes.f_revertir_muestreo(p_autor, p_motivo); end if;      -- capa MUE (Corte 5a)
  perform pg_advisory_xact_lock(hashtext('redes.carga.' || p_capa));
  select * into c from redes.v_cargas_estado where capa_codigo = p_capa and estado = 'publicada' order by publicada_en desc limit 1;
  if not found then perform tecnica.f_error(format('La capa %s no tiene una carga publicada para revertir', p_capa)); end if;
  if p_capa in ('alc_pozos', 'alc_descargas') and exists (select 1 from redes.v_cargas_estado x where x.capa_codigo = 'alc_conductos' and x.estado = 'publicada' and x.publicada_en > c.publicada_en) then
    perform tecnica.f_error('Revierta antes la carga de conductos que se publicó después: sus tramos se enlazan con estos nodos');
  end if;
  v_sis := (select sistema from redes.capas where codigo = p_capa);
  insert into redes.carga_eventos (carga_id, tipo, motivo, autor) values (c.id, 'revertir', btrim(p_motivo), p_autor);
  insert into redes.activo_eventos (activo_id, tipo, motivo, carga_id, autor)
  select e.activo_id, 'reactivar', format('Se revirtió la carga %s, que lo había retirado', c.id), null, p_autor
    from redes.activo_eventos e join redes.v_activo_estado s on s.activo_id = e.activo_id
   where e.carga_id = c.id and e.tipo = 'retirar' and s.retirado;
  get diagnostics v_reac = row_count;
  insert into redes.activo_eventos (activo_id, tipo, motivo, carga_id, autor)
  select e.activo_id, 'retirar', format('Se revirtió la carga %s, que lo había reactivado', c.id), null, p_autor
    from redes.activo_eventos e join redes.v_activo_estado s on s.activo_id = e.activo_id
   where e.carga_id = c.id and e.tipo = 'reactivar' and not s.retirado;
  get diagnostics v_ret = row_count;
  v_mat := redes.f_refrescar_vigente();
  if p_capa = 'acueducto' then v_ct := redes.f_recalcular_contrato_tramo(); end if;
  perform redes.f_subir_tesela(v_sis);
  return jsonb_build_object('carga_id', c.id, 'capa', p_capa, 'reactivados', v_reac, 'retirados', v_ret, 'activos_vigentes', v_mat, 'contrato_tramo', v_ct);
end $function$;
revoke all on function redes.f_revertir(text,text,text) from public, anon, authenticated, service_role;

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
revoke all on function public.geoportal_redes_cargue_capas(text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_cargue_capas(text) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor_capa(p_solicitante text, p_capa text, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare a record; g redes.geovisor_capas%rowtype; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        v_desde date := coalesce(p_desde, v_hoy); v_hasta date := coalesce(p_hasta, v_hoy); v_max integer := floor(redes.f_param('geovisor_max_elementos'))::integer;
        v_ini timestamptz; v_fin timestamptz; v_f jsonb; v_n integer;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into g from redes.geovisor_capas where codigo = p_capa and activa;
  if not found or g.fuente <> 'geojson' then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if g.solo_completo and not a.completo then raise exception 'Capa solo para supervisores' using errcode = '42501'; end if;
  if g.por_fecha then
    if v_desde > v_hasta then perform tecnica.f_error('La fecha inicial es posterior a la final'); end if;
    if v_hasta > v_hoy then perform tecnica.f_error('La fecha final no puede ser futura'); end if;
    if v_desde < (v_hasta - make_interval(months => floor(redes.f_param('geovisor_rango_meses'))::integer))::date then
      perform tecnica.f_error(format('El rango de fechas es de máximo %s meses', floor(redes.f_param('geovisor_rango_meses'))::integer));
    end if;
    if not a.completo and (v_desde <> v_hoy or v_hasta <> v_hoy) then raise exception 'El geovisor en solo lectura muestra solo las actividades del día' using errcode = '42501'; end if;
  end if;
  v_ini := v_desde::timestamp at time zone 'America/Bogota';
  v_fin := (v_hasta + 1)::timestamp at time zone 'America/Bogota';

  if p_capa = 'danos' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(d.lon, d.lat)),
               'properties', jsonb_build_object('codigo', d.codigo, 'clase', d.clase, 'tipo', d.tipo_nombre, 'sistema', d.sistema, 'estado', d.estado,
                                                'activo', d.activo_codigo, 'cuando', d.t_detectado, 'riesgo', d.riesgo, 'origen', d.origen)) as f, d.t_detectado as o
        from redes.v_dano d
       where d.estado <> 'oculto' and d.t_detectado >= v_ini and d.t_detectado < v_fin and d.lat is not null
       order by d.t_detectado desc limit v_max + 1) x;
  elsif p_capa = 'intervenciones' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(i.lon, i.lat)),
               'properties', jsonb_build_object('codigo', i.codigo, 'tipo_codigo', i.tipo_codigo, 'tipo', i.tipo_nombre, 'sistema', i.sistema, 'estado', i.estado,
                                                'activo', i.activo_codigo, 'dano', i.dano_codigo, 'cuando', i.t_inicio, 'fin', i.t_fin, 'ejecutor', i.ejecutor)) as f, i.t_inicio as o
        from redes.v_intervencion i
       where i.estado not in ('oculta', 'anulada') and i.t_inicio >= v_ini and i.t_inicio < v_fin and i.lat is not null
       order by i.t_inicio desc limit v_max + 1) x;
  elsif p_capa = 'reportes_bot' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.radicado, 'canal', r.canal, 'tipo', r.tipo_bot, 'estado', r.estado_bot, 'dano', r.dano_codigo,
                                                'cuando', r.recibido_en)) as f, r.recibido_en as o
        from redes.v_reporte_externo r
       where r.recibido_en >= v_ini and r.recibido_en < v_fin and r.lat is not null
       order by r.recibido_en desc limit v_max + 1) x;
  elsif p_capa = 'muestreo' then
    select coalesce(jsonb_agg(f order by o), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(u.lon, u.lat)),
               'properties', jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'exactitud', u.exactitud) || redes.f_muestreo_calidad(p.id)) as f, p.codigo as o
        from tecnica.puntos p join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
       where p.tipo = 'muestreo' and p.activo
       order by p.codigo limit v_max + 1) x;
  elsif p_capa = 'reportes_comercial' then      -- Corte 6b (§30.4): la vista la llena el Corte 8; azul con contrato, rojo posible clandestino
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.codigo, 'tipo', r.tipo, 'subtipo', r.subtipo, 'area', r.area, 'con_contrato', coalesce(r.con_contrato, false),
                                                'estado', r.estado, 'cuando', r.registrado_en)) as f, r.registrado_en as o
        from redes.v_reportes_comercial r
       where r.registrado_en >= v_ini and r.registrado_en < v_fin and r.lat is not null
       order by r.registrado_en desc limit v_max + 1) x;
  else
    perform tecnica.f_error('Esa capa todavía no tiene datos', 'P0002');
  end if;

  if v_n > v_max then v_f := v_f - v_max; end if;      -- se quitó el elemento de más (el último de la lista)
  return jsonb_build_object('type', 'FeatureCollection', 'capa', p_capa, 'desde', case when g.por_fecha then v_desde end, 'hasta', case when g.por_fecha then v_hasta end,
                            'recortada', v_n > v_max, 'features', v_f);
end $function$;
revoke all on function public.geoportal_redes_geovisor_capa(text,text,date,date) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_geovisor_capa(text,text,date,date) to service_role;

-- 2. lo nuevo (las tablas están vacías: lo comprobó la guardia)
drop function public.geoportal_redes_l116_vincular_dano(text,bigint,text,text,text);
drop function redes.f_revertir_l116(text,text);
drop function redes.f_publicar_l116(bigint,text,text);
drop function redes.f_resumen_l116(bigint);
drop function redes.f_l116_candidatos(bigint);
drop function redes.f_l116_fecha(text);
drop function redes.f_l116_atributos(jsonb);
drop table redes.l116_revision_filas, redes.l116_revisiones, redes.l116_danos, redes.l116_vigente, redes.l116_eventos, redes.l116_reportes;
update redes.capas set activa = false where codigo = 'linea_116';      -- el catálogo no se borra: se desactiva (sale del Cargue)
-- 3. la capa del geovisor, como la dejó el 6a; los formularios compartidos, desactivados
update redes.geovisor_capas set nombre = 'PQR técnicas y línea 116', nota = 'Espera el archivo (Corte 5d)', fuente = 'preparada', estado = 'espera_dato', por_fecha = False, solo_completo = False where codigo = 'pqr_116';
update redes.formularios_distribucion set activo = false where clave in ('anomalia_compartida', 'revision_compartida');
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte5d', 'reversa_redes_corte5d', null, jsonb_build_object('motivo', 'reversa del Corte 5d'), null);
