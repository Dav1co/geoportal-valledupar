-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como las dejó el 4b (las 9 reemplazadas con su texto exacto), sin la RPC ni las funciones nuevas, sin la vista y sin las 3 tablas
-- nuevas. La capa «muestreo» queda inactiva (las capas no se borran) y el parámetro itv_dias_atras_max_supervisor se queda (no se borra; nadie lo lee).
-- SE NIEGA si ya hay cargas de la capa de muestreo o ubicaciones o eventos de puntos (nada se borra), o si alguna función cambió después de la migración.
-- Los eventos de formularios que el supervisor de distribución haya escrito en tecnica.personal_tecnico_eventos se quedan: son válidos para planta.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.puntos_ubicacion') is null then raise exception 'No hay nada que revertir: no existe tecnica.puntos_ubicacion'; end if;
  if exists (select 1 from tecnica.puntos_ubicacion) or exists (select 1 from tecnica.punto_eventos) or exists (select 1 from redes.cargas where capa_codigo = 'muestreo') then
    raise exception 'Ya hay cargas de la capa de muestreo, ubicaciones o eventos de puntos: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '5d104bb916ca0b055659c1b14902f519' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 5a: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las 9 funciones reemplazadas, con su texto del 4b
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
  analyze _cand;
end $function$;

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
  r record;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga'); end if;
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
  v_tabla := v_tabla
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '7 avisos', 'c', 'aviso', 'v', a)), '[]'::jsonb) from unnest(v_avisos) a)
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '8 bloqueos', 'c', 'BLOQUEO', 'v', b)), '[]'::jsonb) from unnest(v_bloq) b)
    || jsonb_build_array(jsonb_build_object('s', '9 resultado', 'c', 'lista para publicar', 'v', case when cardinality(v_bloq) = 0 then 'SÍ' else 'NO' end));

  return jsonb_build_object('carga_id', c.id, 'capa', c.capa_codigo, 'estado', c.estado, 'recibidas', v_recibidas, 'esperadas', c.filas_esperadas,
    'errores', v_errores, 'llaves_nulas', v_nulas, 'llaves_repetidas', v_rep, 'por_prefijo', v_por_prefijo, 'por_estado', v_por_estado,
    'frente_a_vigente', v_por_accion, 'retirados', v_retirar, 'nodos', v_nodos, 'nodos_con_activo', v_nodos_activo, 'nodos_por_clasificar', v_nodos_pc,
    'pozos_virtuales', v_nodos_virt, 'nodos_dispersos', v_disp, 'detalle', v_extra, 'avisos', to_jsonb(v_avisos), 'bloqueos', to_jsonb(v_bloq),
    'lista_para_publicar', cardinality(v_bloq) = 0, 'tabla', v_tabla);
end $function$;

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
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m,
         estado_codigo, atributos, codigo_anterior, capa_codigo, llave_capa, carga_id, huella, autor)
  select activo_id, version_nueva, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m,
         estado_codigo, atributos, codigo_anterior, capa_codigo, llave, p_carga, huella, p_autor
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
     and (o.activo_id is null or o.origen is distinct from k.origen or o.aportante_codigo is distinct from k.aportante_codigo);
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

  -- (g) nodos: se inserta solo si es nuevo o cambió (nombre, posición, activo o clase); el vigente idéntico se reutiliza
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id)
  select k.nodo_sistema, k.llave, k.nodo_nombre, k.clase_nodo, k.geom, case when k.crea_activo then k.activo_id end, round(k.dispersion_m, 3), p_carga
    from _cand k left join redes.v_nodo_vigente n on n.sistema = k.nodo_sistema and n.llave_modelo = k.llave
   where k.crea_nodo and k.llave is not null
     and (n.nodo_id is null or n.nombre_modelo is distinct from k.nodo_nombre or not ST_Equals(n.geom, k.geom)
          or n.activo_id is distinct from (case when k.crea_activo then k.activo_id end) or n.clase_nodo <> k.clase_nodo);
  get diagnostics v_nodos = row_count;
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

CREATE OR REPLACE FUNCTION redes.f_revertir(p_capa text, p_autor text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare c redes.v_cargas_estado%rowtype; v_sis text; v_reac integer; v_ret integer; v_ct integer; v_mat integer;
begin
  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
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

CREATE OR REPLACE FUNCTION public.geoportal_redes_formulario_intervencion(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento');
        v_perfil text := case when public.geoportal_es_admin(v_email) then 'admin' when redes.f_es_supervisor_redes(v_email) then 'supervisor' else 'operador' end;
begin
  return jsonb_build_object(
    'perfil', v_perfil,
    'sistemas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.sistemas where codigo in ('acueducto', 'alcantarillado')),
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'admite_dano', admite_dano, 'es_inversion', es_inversion) order by orden) from redes.tipos_intervencion where activo),
    'aportantes', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.entidades_aportantes where activo),
    'contratistas', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by nombre) from redes.contratistas where activo), '[]'::jsonb),
    'unidades', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.unidades_material where activo),
    -- tipos de activo que puede crear una inversión «activo nuevo», con sus clases (y si la clase es obligatoria)
    'tipos_nuevo', (select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre_visible, 'sistema', t.sistema, 'geometria', t.geometria,
                       'clases', coalesce((select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre) order by c.orden) from redes.clases_activo c where c.prefijo = t.prefijo), '[]'::jsonb),
                       'clase_obligatoria', exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean),
                       'lleva_diametro', exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'diametro_mm'))
                     order by t.orden)
                      from redes.v_tipo_visible t where t.sistema in ('acueducto', 'alcantarillado') and t.geometria in ('punto', 'linea')),
    'materiales', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.materiales),
    -- el operario conserva el tope de días y de horas; el supervisor y el administrador registran las obras largas sin ese tope (David, respuesta 1 al 3a)
    'reglas', jsonb_build_object('dias_atras_max', case when v_perfil in ('admin', 'supervisor') then null else redes.f_param('itv_dias_atras_max') end,
                                 'max_horas', case when v_perfil in ('admin', 'supervisor') then null else redes.f_param('itv_max_horas') end,
                                 'min_fotos', redes.f_param('min_fotos_itv'), 'puede_sin_fotos', false, 'pone_valores', v_perfil in ('admin', 'supervisor'),
                                 'max_fotos', redes.f_param('max_fotos_itv'), 'max_documentos', redes.f_param('max_docs_itv'),
                                 'max_bytes_foto', redes.f_param('max_bytes_foto_itv'), 'max_bytes_documento', redes.f_param('max_bytes_doc_itv'),
                                 'max_horas_inicio', tecnica.f_max_horas_inicio(), 'radio_cercanos_m', redes.f_param('distancia_activo_cercano_m'),
                                 'radio_danos_m', redes.f_param('itv_radio_danos_m'), 'max_tambien', redes.f_param('itv_max_activos_tambien'),
                                 'max_materiales', redes.f_param('itv_max_materiales'), 'zoom_min', redes.f_param('mini_zoom_min'), 'zoom_accesorios', redes.f_param('mini_zoom_acc')),
    'ahora', clock_timestamp());
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_redes_crear_intervencion(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento'); v_super boolean; d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_intervencion%rowtype; v_tipo redes.tipos_intervencion%rowtype; v_sis text; v_modo text;
  v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text; v_nuevo jsonb; v_tn redes.v_tipo_visible%rowtype; v_geom_nuevo geometry;
  v_clase_n text; v_mat_n text; v_diam_n numeric; v_nom_n text; v_pts jsonb; v_p jsonb; v_lat numeric; v_lon numeric; v_fuera boolean;
  v_t_ini timestamptz; v_t_fin timestamptz; v_inicio timestamptz; v_desc text := btrim(coalesce(d ->> 'descripcion', ''));
  v_dano redes.v_dano%rowtype; v_tambien bigint[] := '{}'; v_x text; v_xid bigint; v_mats jsonb := coalesce(d -> 'materiales', '[]'::jsonb); v_m jsonb;
  v_fuentes jsonb; v_arch jsonb := coalesce(d -> 'archivos', '[]'::jsonb); v_ref jsonb := '[]'::jsonb; v_nf integer := 0; v_nd integer := 0; v_n integer;
  v_f jsonb; v_ruta text; v_size bigint; v_mime text; v_prep redes.intervencion_preparaciones%rowtype; v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
  v_cons bigint; v_codigo text; v_ctr bigint; v_ctr_nom text; v_orden text := nullif(btrim(coalesce(d ->> 'contrato_orden', '')), '');
  v_comp text := nullif(btrim(coalesce(d ->> 'companeros', '')), ''); v_pto geometry; v_creado boolean := false; v_origen text; v_aport text; v_cod_nuevo text;
  v_dano_estado text; v_resuelve boolean := coalesce((p_datos ->> 'resuelve_dano')::boolean, false);
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador de la intervención: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_intervencion where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de esta intervención'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'activo_creado', v_prev.activo_creado, 'dano', v_prev.dano_codigo, 'sin_evidencia', v_prev.sin_evidencia, 'fuera_de_zona', v_prev.fuera_de_zona, 'repetido', true);
  end if;
  select * into v_prep from redes.intervencion_preparaciones where intervencion_id = p_id and autor = v_email;
  if not found then perform tecnica.f_error('Primero debe prepararse la subida de esta intervención'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos de la intervención no son válidos'); end if;
  v_super := redes.f_es_supervisor_redes(v_email);

  -- 1. de dónde nace y tipo
  if coalesce(d ->> 'nace_de', '') not in ('programada', 'dano') then perform tecnica.f_error('Elija de dónde nace: programada o mejora, o daño o falla'); end if;
  select * into v_tipo from redes.tipos_intervencion where codigo = d ->> 'tipo' and activo;
  if not found then perform tecnica.f_error('Elija el tipo de intervención'); end if;
  if d ->> 'nace_de' = 'dano' and not v_tipo.admite_dano then perform tecnica.f_error(format('«%s» no atiende un daño: elija correctivo, reparación o reposición', v_tipo.nombre)); end if;
  v_modo := d ->> 'inversion_modo';
  if v_tipo.es_inversion and coalesce(v_modo, '') not in ('nuevo', 'mejora') then perform tecnica.f_error('Diga qué tipo de inversión es: activo nuevo o mejora de un activo existente'); end if;
  if not v_tipo.es_inversion then v_modo := null; end if;
  v_sis := d ->> 'sistema';
  if coalesce(v_sis, '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;

  -- 2. activo: el elegido, «no identificado» o el que crea la inversión
  if v_modo = 'nuevo' then
    v_nuevo := d -> 'nuevo';
    if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null or d ->> 'no_identificado' is not null then perform tecnica.f_error('Una inversión en un activo nuevo no lleva un activo existente'); end if;
    if v_nuevo is null or jsonb_typeof(v_nuevo) <> 'object' then perform tecnica.f_error('Diga qué activo nuevo se construyó'); end if;
    select * into v_tn from redes.v_tipo_visible where prefijo = upper(coalesce(v_nuevo ->> 'prefijo', '')) and sistema = v_sis and geometria in ('punto', 'linea');
    if not found then perform tecnica.f_error('Elija el tipo del activo nuevo (del mismo sistema)'); end if;
    v_clase_n := nullif(v_nuevo ->> 'clase', '');
    if v_clase_n is not null and not exists (select 1 from redes.clases_activo where prefijo = v_tn.prefijo and codigo = v_clase_n) then perform tecnica.f_error('Esa clase no existe para el tipo elegido'); end if;
    if v_clase_n is null and exists (select 1 from jsonb_array_elements(v_tn.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean) then
      perform tecnica.f_error(format('Elija la clase del activo nuevo (%s)', v_tn.nombre_visible));
    end if;
    v_mat_n := nullif(v_nuevo ->> 'material', '');
    if v_mat_n is not null and not exists (select 1 from redes.materiales where codigo = v_mat_n) then perform tecnica.f_error('Ese material no existe'); end if;
    v_diam_n := (v_nuevo ->> 'diametro_mm')::numeric;
    if v_diam_n is not null and (v_diam_n <= 0 or v_diam_n > 5000) then perform tecnica.f_error('El diámetro va de 1 a 5.000 mm'); end if;
    v_nom_n := nullif(btrim(coalesce(v_nuevo ->> 'nombre', '')), '');
    if v_nom_n is not null and length(v_nom_n) > 120 then perform tecnica.f_error('El nombre del activo nuevo admite hasta 120 caracteres'); end if;
    v_pts := v_nuevo -> 'puntos';
    if v_pts is null or jsonb_typeof(v_pts) <> 'array' then perform tecnica.f_error('Marque en el mapa dónde quedó el activo nuevo'); end if;
    if v_tn.geometria = 'punto' and jsonb_array_length(v_pts) <> 1 then perform tecnica.f_error('Marque un solo punto para el activo nuevo'); end if;
    if v_tn.geometria = 'linea' and jsonb_array_length(v_pts) not between 2 and 50 then perform tecnica.f_error('Marque el inicio y el fin del tramo nuevo'); end if;
    for v_p in select e from jsonb_array_elements(v_pts) e loop
      if jsonb_typeof(v_p) <> 'array' or jsonb_array_length(v_p) <> 2 or (v_p ->> 0)::numeric not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max')
         or (v_p ->> 1)::numeric not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
        perform tecnica.f_error('El activo nuevo debe quedar dentro de Valledupar');
      end if;
    end loop;
    v_geom_nuevo := case when v_tn.geometria = 'punto' then ST_SetSRID(ST_MakePoint((v_pts -> 0 ->> 1)::double precision, (v_pts -> 0 ->> 0)::double precision), 4326)
                         else ST_SetSRID(ST_MakeLine(array(select ST_MakePoint((e ->> 1)::double precision, (e ->> 0)::double precision) from jsonb_array_elements(v_pts) with ordinality x(e, o) order by o)), 4326) end;
    if v_tn.geometria = 'linea' and ST_Length(v_geom_nuevo::geography) < 0.5 then perform tecnica.f_error('El tramo nuevo es demasiado corto: marque el inicio y el fin'); end if;
  elsif nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado then perform tecnica.f_error('El activo elegido no existe o está retirado: elíjalo de nuevo en el mapa'); end if;
    if v_act.sistema <> v_sis then perform tecnica.f_error('El activo elegido no es de ese sistema'); end if;
    v_activo := v_act.activo_id;
  else
    v_noid := nullif(btrim(coalesce(d ->> 'no_identificado', '')), '');
    if v_noid is null or length(v_noid) < 3 or length(v_noid) > 120 then perform tecnica.f_error('Elija el activo en el mapa o, si no lo identifica, diga qué es (3 a 120 caracteres)'); end if;
  end if;

  -- ubicación de la intervención: nunca se rechaza por estar fuera de la zona (se marca)
  v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric;
  if v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then perform tecnica.f_error('Falta la ubicación de la intervención'); end if;
  if coalesce(d ->> 'ubicacion_origen', '') not in ('gps', 'mapa', 'activo') then perform tecnica.f_error('Falta de dónde sale la ubicación'); end if;
  v_fuera := v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max');
  v_pto := ST_SetSRID(ST_MakePoint(v_lon, v_lat), 4326);

  -- activos también intervenidos (mismo sistema, vigentes, sin repetir y distintos del principal)
  if d -> 'tambien' is not null then
    if jsonb_typeof(d -> 'tambien') <> 'array' then perform tecnica.f_error('Los activos también intervenidos no son válidos'); end if;
    if jsonb_array_length(d -> 'tambien') > redes.f_param('itv_max_activos_tambien') then
      perform tecnica.f_error(format('Hasta %s activos también intervenidos', redes.f_param('itv_max_activos_tambien')::integer));
    end if;
    for v_x in select jsonb_array_elements_text(d -> 'tambien') loop
      select activo_id into v_xid from redes.activo_vigente_mat where codigo = upper(btrim(v_x)) and not retirado and sistema = v_sis;
      if v_xid is null then perform tecnica.f_error(format('El activo también intervenido «%s» no existe, está retirado o no es de ese sistema', v_x)); end if;
      if v_xid = v_activo then perform tecnica.f_error('El activo principal no va otra vez en «también intervenidos»'); end if;
      if v_xid = any (v_tambien) then perform tecnica.f_error(format('El activo «%s» está repetido en «también intervenidos»', v_x)); end if;
      v_tambien := v_tambien || v_xid;
    end loop;
  end if;

  -- 3. fechas y horas del trabajo (contra la hora del servidor)
  v_t_ini := redes.f_instante(d ->> 't_inicio', 'inicio');
  v_t_fin := redes.f_instante(d ->> 't_fin', 'fin');
  if v_t_ini is null or v_t_fin is null then perform tecnica.f_error('Escriba el inicio y el fin de la intervención'); end if;
  if v_t_fin > v_ahora + interval '2 minutes' then perform tecnica.f_error('El fin está en el futuro: la intervención se registra cuando ya se hizo'); end if;
  if v_t_ini > v_t_fin then perform tecnica.f_error('El inicio no puede ser después del fin'); end if;
  -- el tope de días y de horas es del operario; el supervisor y el administrador registran las obras largas desde el escritorio sin él
  if not v_super and v_t_ini < v_ahora - make_interval(days => redes.f_param('itv_dias_atras_max')::integer) then
    perform tecnica.f_error(format('El inicio no puede ser de hace más de %s días', redes.f_param('itv_dias_atras_max')::integer));
  end if;
  if not v_super and v_t_fin - v_t_ini > make_interval(hours => redes.f_param('itv_max_horas')::integer) then
    perform tecnica.f_error(format('Una intervención dura hasta %s horas: si duró más, la registra el supervisor desde el escritorio', redes.f_param('itv_max_horas')::integer));
  end if;
  v_inicio := redes.f_instante(d ->> 'inicio_dispositivo', 'apertura del formulario');
  if v_inicio is not null and (v_inicio > v_ahora + interval '2 minutes' or v_inicio < v_ahora - make_interval(hours => tecnica.f_max_horas_inicio())) then
    perform tecnica.f_error(format('Este formulario se abrió hace más de %s horas o la hora de su celular está adelantada. Revise la hora y vuelva a enviar.', tecnica.f_max_horas_inicio()));
  end if;

  -- daño que atiende: abierto, del mismo sistema y del activo, de un también intervenido o cercano
  if d ->> 'nace_de' = 'dano' then
    if nullif(btrim(coalesce(d ->> 'dano', '')), '') is null then perform tecnica.f_error('Elija el daño o falla que se atiende'); end if;
    perform pg_advisory_xact_lock(hashtext('redes.dano.' || upper(btrim(d ->> 'dano'))));
    select * into v_dano from redes.v_dano where codigo = upper(btrim(d ->> 'dano'));
    if not found then perform tecnica.f_error('Ese daño no existe'); end if;
    if v_dano.estado not in ('reportado', 'en_atencion') then perform tecnica.f_error(format('El daño %s ya está %s', v_dano.codigo, case v_dano.estado when 'atendido' then 'atendido' else 'oculto' end)); end if;
    if not redes.f_dano_elegible(v_dano, v_sis, array_remove(v_tambien || v_activo, null), v_pto) then
      perform tecnica.f_error(format('El daño %s no es de este activo ni de los cercanos (%s m)', v_dano.codigo, redes.f_param('itv_radio_danos_m')::integer));
    end if;
    if v_dano.t_inicio_reparacion is null and v_t_ini < v_dano.t_detectado then
      perform tecnica.f_error(format('La intervención empezó antes de que se detectara el daño %s: revise las horas', v_dano.codigo));
    end if;
    if v_resuelve and v_dano.t_inicio_reparacion is not null and v_t_fin < v_dano.t_inicio_reparacion then
      perform tecnica.f_error(format('La intervención terminó antes del inicio de la reparación que ya tenía el daño %s', v_dano.codigo));
    end if;
  elsif v_resuelve then
    perform tecnica.f_error('«Con esta queda resuelto el daño» solo va cuando la intervención nace de un daño');
  end if;

  -- 4. qué se hizo y materiales
  if length(v_desc) < 10 or length(v_desc) > 2000 then perform tecnica.f_error('Describa qué se hizo (10 a 2.000 caracteres)'); end if;
  if jsonb_typeof(v_mats) <> 'array' or jsonb_array_length(v_mats) > redes.f_param('itv_max_materiales') then perform tecnica.f_error(format('Hasta %s materiales', redes.f_param('itv_max_materiales')::integer)); end if;
  for v_m in select e from jsonb_array_elements(v_mats) e loop
    if jsonb_typeof(v_m) <> 'object' or length(btrim(coalesce(v_m ->> 'material', ''))) not between 2 and 80 then perform tecnica.f_error('Cada material lleva su nombre (2 a 80 caracteres)'); end if;
    if coalesce((v_m ->> 'cantidad')::numeric, 0) <= 0 or (v_m ->> 'cantidad')::numeric >= 1000000 then perform tecnica.f_error(format('La cantidad de «%s» no es válida', btrim(v_m ->> 'material'))); end if;
    if not exists (select 1 from redes.unidades_material where codigo = v_m ->> 'unidad' and activo) then perform tecnica.f_error(format('Elija la unidad de «%s»', btrim(v_m ->> 'material'))); end if;
  end loop;

  -- 5. quién la ejecuta
  if coalesce(d ->> 'ejecutor', '') not in ('emdupar', 'contratista') then perform tecnica.f_error('Diga quién la ejecuta: EMDUPAR o contratista'); end if;
  if d ->> 'ejecutor' = 'contratista' then
    if nullif(d ->> 'contratista', '') is not null then
      select id into v_ctr from redes.contratistas where codigo = d ->> 'contratista' and activo;
      if v_ctr is null then perform tecnica.f_error('Ese contratista no está en el catálogo'); end if;
    else
      v_ctr_nom := nullif(btrim(coalesce(d ->> 'contratista_nombre', '')), '');
      if v_ctr_nom is null or length(v_ctr_nom) not between 2 and 120 then perform tecnica.f_error('Elija o escriba el contratista'); end if;
    end if;
  elsif nullif(d ->> 'contratista', '') is not null or nullif(btrim(coalesce(d ->> 'contratista_nombre', '')), '') is not null then
    perform tecnica.f_error('El contratista solo va si la ejecuta un contratista');
  end if;
  if v_orden is not null and length(v_orden) > 60 then perform tecnica.f_error('El contrato u orden admite hasta 60 caracteres'); end if;
  if v_comp is not null and length(v_comp) not between 2 and 200 then perform tecnica.f_error('Los compañeros de cuadrilla admiten hasta 200 caracteres'); end if;

  -- 6. de dónde salen los recursos (D-8): el operario marca solo quién aporta; el supervisor y el administrador pueden poner valores
  v_fuentes := redes.f_fuentes_validas(d -> 'fuentes', v_super, false);

  -- 7. fotos (JPEG) y documentos (PDF): el tamaño y el tipo se leen de Storage (nunca se le creen al celular)
  if jsonb_typeof(v_arch) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_arch);
  if v_n > 0 and (select count(distinct (e ->> 'n')::integer) <> v_n or min((e ->> 'n')::integer) <> 1 or max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_arch) e) then
    perform tecnica.f_error('El orden de los archivos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  for v_f in select e from jsonb_array_elements(v_arch) e order by (e ->> 'n')::integer loop
    if coalesce(v_f ->> 'clase', '') not in ('antes', 'durante', 'despues', 'documento') then perform tecnica.f_error('Cada foto dice si es de antes, de durante o de después'); end if;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^intervenciones/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || case when v_f ->> 'clase' = 'documento' then '\.pdf$' else '\.jpg$' end) then
      perform tecnica.f_error(format('La ruta del archivo %s no corresponde a esta intervención', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró el archivo %s: súbalo de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('El archivo %s está vacío', v_f ->> 'n')); end if;
    if v_f ->> 'clase' = 'documento' then
      v_nd := v_nd + 1;
      if v_mime is distinct from 'application/pdf' then perform tecnica.f_error(format('El documento %s debe ser PDF', v_f ->> 'n')); end if;
      if v_size > redes.f_param('max_bytes_doc_itv') then perform tecnica.f_error(format('El documento %s pesa más de lo permitido (%s KB)', v_f ->> 'n', (redes.f_param('max_bytes_doc_itv') / 1024)::integer)); end if;
    else
      v_nf := v_nf + 1;
      if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
      if v_size > redes.f_param('max_bytes_foto_itv') then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', (redes.f_param('max_bytes_foto_itv') / 1024)::integer)); end if;
    end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'clase', v_f ->> 'clase', 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;
  if v_nf > v_prep.fotos or v_nd > v_prep.documentos or v_nf > redes.f_param('max_fotos_itv') or v_nd > redes.f_param('max_docs_itv') then
    perform tecnica.f_error(format('Una intervención lleva hasta %s fotos y %s documentos', redes.f_param('max_fotos_itv')::integer, redes.f_param('max_docs_itv')::integer));
  end if;
  -- en la calle, siempre al menos una foto; sin fotos solo el supervisor o el administrador (p. ej., desde el escritorio), con el motivo
  -- §25.8: nadie registra «sin evidencia fotográfica» (ni el supervisor ni el administrador); siempre al menos una foto
  if v_sinev is not null then
    perform tecnica.f_error('Ya no se registra «sin evidencia fotográfica»: tome al menos una foto de la intervención');
  end if;
  if v_nf < redes.f_param('min_fotos_itv') then
    perform tecnica.f_error(format('Tome al menos %s foto de la intervención', redes.f_param('min_fotos_itv')::integer));
  end if;

  -- código ITV-000123 (candado de fila del consecutivo)
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'ITV' returning ultimo into v_cons;
  v_codigo := 'ITV-' || lpad(v_cons::text, 6, '0');

  -- inversión, activo nuevo: el activo nace con la intervención, «por verificar», con su origen según quién aporta
  if v_modo = 'nuevo' then
    select case when bool_and(f ->> 'aportante' = 'emdupar') then 'emdupar' when bool_or(f ->> 'aportante' = 'emdupar') then 'mixto' else 'tercero' end,
           (select f2 ->> 'aportante' from jsonb_array_elements(v_fuentes) f2 where f2 ->> 'aportante' <> 'emdupar' order by (f2 ->> 'n')::integer limit 1)
      into v_origen, v_aport from jsonb_array_elements(v_fuentes) f;
    v_activo := redes.f_activo_crear(v_tn.prefijo, v_geom_nuevo, v_clase_n, v_mat_n, v_diam_n, v_nom_n, (v_t_fin at time zone 'America/Bogota')::date,
                                     jsonb_build_object('intervencion', v_codigo), v_origen, v_aport, v_email,
                                     format('Creado por la intervención %s (inversión, activo nuevo): por verificar', v_codigo));
    v_creado := true;
    v_cod_nuevo := (select codigo from redes.activos where id = v_activo);
  end if;

  insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, inversion_modo, sistema, activo_id, activo_creado, no_ident_que_es, lat, lon,
         ubicacion_origen, precision_m, fuera_de_zona, t_inicio, t_fin, inicio_en, inicio_origen, descripcion, ejecutor, contratista_id, contratista_nombre,
         contrato_orden, companeros, sin_evidencia_motivo, resuelve_dano, autor, registrado_en)
  values (p_id, v_codigo, d ->> 'nace_de', v_dano.id, v_tipo.codigo, v_modo, v_sis, v_activo, v_creado, v_noid, round(v_lat, 6), round(v_lon, 6),
          d ->> 'ubicacion_origen', (d ->> 'precision_m')::numeric, v_fuera, v_t_ini, v_t_fin, v_inicio, case when v_inicio is not null then 'dispositivo' end,
          v_desc, d ->> 'ejecutor', v_ctr, v_ctr_nom, v_orden, v_comp, v_sinev, v_resuelve, v_email, v_ahora);
  insert into redes.intervencion_activos (intervencion_id, activo_id, n) select p_id, x, o from unnest(v_tambien) with ordinality u(x, o);
  insert into redes.intervencion_materiales (intervencion_id, n, material, cantidad, unidad)
  select p_id, o, btrim(e ->> 'material'), (e ->> 'cantidad')::numeric, e ->> 'unidad' from jsonb_array_elements(v_mats) with ordinality x(e, o);
  insert into redes.intervencion_fuentes (intervencion_id, version, n, aportante_codigo, entidad, valor, porcentaje, soporte, fuente, autor)
  select p_id, 1, (f ->> 'n')::smallint, f ->> 'aportante', f ->> 'entidad', (f ->> 'valor')::numeric, (f ->> 'porcentaje')::numeric, f ->> 'soporte',
         case when v_super then 'supervisor' else 'formulario' end, v_email from jsonb_array_elements(v_fuentes) f;
  insert into redes.intervencion_archivos (intervencion_id, n, clase, ruta_storage, bytes, mime)
  select p_id, (x ->> 'n')::smallint, x ->> 'clase', x ->> 'ruta', (x ->> 'bytes')::integer, x ->> 'mime' from jsonb_array_elements(v_ref) x;
  insert into redes.intervencion_eventos (intervencion_id, tipo, autor) values (p_id, 'cerrada', v_email);       -- flujo A (D-6)
  if v_creado then
    insert into redes.intervencion_eventos (intervencion_id, tipo, activo_id, motivo, autor) values (p_id, 'crear_activo', v_activo, format('Inversión: se creó el activo %s, por verificar', v_cod_nuevo), v_email);
  end if;

  -- intervención que nace de un daño (un daño puede tener varias, David, respuesta 2 al 3a):
  --   · la primera le pone el inicio de la reparación (si no lo tenía) y el daño queda «en atención»;
  --   · la que marca «Con esta queda resuelto el daño» le pone el servicio restablecido y lo deja «atendido».
  if v_dano.id is not null then
    if v_dano.t_inicio_reparacion is null or v_resuelve then
      insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor)
      values (v_dano.id, case when v_dano.t_inicio_reparacion is null then v_t_ini end, case when v_resuelve then v_t_fin end, 'intervencion', v_email);
    end if;
    insert into redes.dano_eventos (dano_id, tipo, intervencion_id, motivo, autor)
    values (v_dano.id, case when v_resuelve then 'atendido' else 'en_atencion' end, p_id,
            case when v_resuelve then format('Resuelto con la intervención %s (%s)', v_codigo, v_tipo.nombre)
                 else format('Atendido en parte con la intervención %s (%s); sigue abierto', v_codigo, v_tipo.nombre) end, v_email);
    select x.estado into v_dano_estado from redes.v_dano x where x.id = v_dano.id;
  end if;

  -- auditoría sin la posición ni los valores
  perform tecnica.f_auditar(v_email, 'redes_crear_intervencion', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'nace_de', d ->> 'nace_de', 'dano', v_dano.codigo,
          'sistema', v_sis, 'activo', coalesce(v_act.codigo, v_cod_nuevo), 'activo_creado', v_creado, 'no_identificado', v_noid is not null, 'tambien', cardinality(v_tambien),
          'fotos', v_nf, 'documentos', v_nd, 'sin_evidencia', v_nf = 0, 'ejecutor', d ->> 'ejecutor', 'resuelve_dano', v_resuelve), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo, 'activo_creado', x.activo_creado,
                                    'dano', x.dano_codigo, 'dano_estado', v_dano_estado, 'recursos', x.recursos, 'sin_evidencia', x.sin_evidencia, 'fuera_de_zona', x.fuera_de_zona,
                                    'duracion_s', x.duracion_s, 'repetido', false) from redes.v_intervencion x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.intervenciones where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_intervencion x where x.id = p_id);
  end if;
  perform tecnica.f_error('Uno de los archivos ya está usado en otra intervención');
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_redes_cuadrilla_fijar(p_solicitante text, p_id bigint, p_nombre text, p_activa boolean, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_admin(p_solicitante); v_nom text := nullif(btrim(coalesce(p_nombre, '')), ''); v_mot text := btrim(coalesce(p_motivo, ''));
        c redes.cuadrillas%rowtype; v_id bigint;
begin
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (10 a 500 caracteres)'); end if;
  if v_nom is not null and length(v_nom) not between 2 and 60 then perform tecnica.f_error('El nombre de la cuadrilla lleva de 2 a 60 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.cuadrillas'));
  if v_nom is not null and exists (select 1 from redes.cuadrillas x where lower(btrim(x.nombre)) = lower(v_nom) and x.id is distinct from p_id) then
    perform tecnica.f_error('Ya existe una cuadrilla con ese nombre');
  end if;
  if p_id is null then
    if v_nom is null then perform tecnica.f_error('Escriba el nombre de la cuadrilla'); end if;
    insert into redes.cuadrillas (nombre, activa, orden, autor) values (v_nom, coalesce(p_activa, true), coalesce((select max(orden) from redes.cuadrillas), 0) + 1, v_email)
    returning id into v_id;
    perform tecnica.f_auditar(v_email, 'redes_cuadrilla_crear', v_id::text, jsonb_build_object('nombre', v_nom, 'motivo', v_mot), null);
    return jsonb_build_object('id', v_id, 'nombre', v_nom, 'activa', coalesce(p_activa, true), 'nueva', true);
  end if;
  select * into c from redes.cuadrillas where id = p_id for update;
  if not found then perform tecnica.f_error('No existe esa cuadrilla', 'P0002'); end if;
  if coalesce(v_nom, c.nombre) = c.nombre and coalesce(p_activa, c.activa) = c.activa then perform tecnica.f_error('Ya está así: no hay nada que cambiar'); end if;
  update redes.cuadrillas set nombre = coalesce(v_nom, nombre), activa = coalesce(p_activa, activa) where id = p_id;
  perform tecnica.f_auditar(v_email, 'redes_cuadrilla_cambiar', p_id::text, jsonb_build_object('antes', jsonb_build_object('nombre', c.nombre, 'activa', c.activa),
          'despues', jsonb_build_object('nombre', coalesce(v_nom, c.nombre), 'activa', coalesce(p_activa, c.activa)), 'motivo', v_mot), null);
  return jsonb_build_object('id', p_id, 'nombre', coalesce(v_nom, c.nombre), 'activa', coalesce(p_activa, c.activa), 'nueva', false);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_redes_catalogo(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el catálogo de redes');
begin
  return jsonb_build_object('puede_editar', public.geoportal_es_admin(v_email),
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre, 'nombre_visible', t.nombre_visible,
               'alias', case when t.nombre_visible <> t.nombre then t.nombre_visible end, 'sistema', t.sistema, 'geometria', t.geometria, 'es_base', t.es_base, 'activo', t.activo,
               'vigentes', coalesce(n.n, 0)) order by t.sistema, t.orden, t.prefijo)
        from redes.v_tipo_visible t
        left join (select m.prefijo, count(*) as n from redes.activo_vigente_mat m where not m.retirado and not m.oculto group by m.prefijo) n on n.prefijo = t.prefijo), '[]'::jsonb),
    'materiales', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden, nombre) from redes.materiales), '[]'::jsonb),
    'estados', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'cuenta_vigente', cuenta_vigente) order by orden) from redes.estados_activo), '[]'::jsonb),
    'contratistas', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by nombre) from redes.contratistas), '[]'::jsonb),
    'aportantes', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden) from redes.entidades_aportantes), '[]'::jsonb),
    'tipos_intervencion', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden) from redes.tipos_intervencion), '[]'::jsonb),
    'tipos_dano', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'clase', clase, 'activo', activo) order by clase, orden) from redes.tipos_dano), '[]'::jsonb),
    'causas', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden) from redes.causas), '[]'::jsonb),
    'cuadrillas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre, 'activa', c.activa,
                     'personas', (select count(*) from redes.v_personal_ficha f where f.cuadrilla_id = c.id)) order by c.orden, lower(c.nombre)) from redes.cuadrillas c), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_redes_personal(p_solicitante text, p_buscar text DEFAULT NULL::text, p_filtro text DEFAULT 'todas'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 've el personal de distribución'); v_q text := nullif(lower(btrim(coalesce(p_buscar, ''))), '');
begin
  if coalesce(p_filtro, '') not in ('todas', 'distribucion', 'planta', 'sin_area') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_q is not null and length(v_q) > 80 then perform tecnica.f_error('La búsqueda es demasiado larga'); end if;
  return jsonb_build_object('filtro', p_filtro, 'yo', v_email,
    'formularios', jsonb_build_array(jsonb_build_object('clave', 'danos_fallas', 'nombre', 'Reportar daño o falla'), jsonb_build_object('clave', 'mantenimiento', 'nombre', 'Registrar intervención')),
    'cuadrillas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre) order by c.orden, lower(c.nombre)) from redes.cuadrillas c where c.activa), '[]'::jsonb),
    'personas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'email', p.email, 'nombre', p.nombre, 'perfil', case when p.ver_dashboard_redes then 'supervisor' else 'operador' end,
               'dashboard_redes', p.ver_dashboard_redes, 'dashboard_ptap', p.ver_dashboard_tecnico, 'registro_tecnico', p.ver_registro_tecnico,
               'area', f.area, 'cargo', f.cargo,
               'cuadrilla', case when c.id is not null then jsonb_build_object('id', c.id, 'nombre', c.nombre, 'activa', c.activa) end,
               -- la casilla solo es del operador: los supervisores (de distribución o de planta) ven el geovisor por su permiso
               'geovisor', case when p.ver_dashboard_redes or p.ver_dashboard_tecnico then 'por_permiso' when coalesce(f.geovisor, false) then 'si' else 'no' end,
               'formularios', to_jsonb(array_remove(array[case when tecnica.f_formulario_asignado(p.email, 'danos_fallas') then 'danos_fallas' end,
                                                          case when tecnica.f_formulario_asignado(p.email, 'mantenimiento') then 'mantenimiento' end], null)),
               'activo_tecnica', tecnica.f_tecnica_activa(p.email), 'ultimo_cambio', f.ultimo_cambio)
             order by lower(coalesce(p.nombre, p.email)), p.email)
        from (select lb.email, nullif(btrim(lb.nombre), '') as nombre, lb.ver_dashboard_redes, lb.ver_dashboard_tecnico, lb.ver_registro_tecnico
                from public.geoportal_lista_blanca lb where lb.activo and lb.rol <> 'admin' and (lb.ver_registro_tecnico or lb.ver_dashboard_redes)) p
        left join redes.v_personal_ficha f on f.persona = p.email
        left join redes.cuadrillas c on c.id = f.cuadrilla_id
       where (v_q is null or position(v_q in lower(coalesce(p.nombre, '') || ' ' || p.email)) > 0)
         and case p_filtro when 'distribucion' then coalesce(f.area in ('distribucion', 'ambas'), false) when 'planta' then coalesce(f.area in ('planta', 'ambas'), false)
                           when 'sin_area' then f.area is null else true end), '[]'::jsonb));
end $function$;

-- 2. lo nuevo
drop function geoportal_redes_personal_formulario(text,text,text,boolean,text,text);
drop function redes.f_fusionar_ficha();
drop function redes.f_candidatos_muestreo(bigint);
drop function redes.f_resumen_muestreo(bigint);
drop function redes.f_publicar_muestreo(bigint,text,text);
drop function redes.f_revertir_muestreo(text,text);
drop view redes.v_punto_ubicacion_vigente;
drop table tecnica.puntos_ubicacion;
drop table tecnica.punto_eventos;
drop table redes.formularios_distribucion;
update redes.capas set activa = false where codigo = 'muestreo';

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '55668dddf263065b5eb90aeb3001a3b7' then
    raise exception 'La reversa no dejó la base como en el 4b';
  end if;
end $$;
