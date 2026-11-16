-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 25 — RPC: formulario, preparar y crear la intervención (flujo A, cierre del daño, inversión que crea
-- un activo); daños abiertos cercanos; bandeja de no identificados y «asociar activo»; recursos del supervisor; y el daño sin fotos.
-- PROPUESTA. No se ha ejecutado en la base real. Todas security definer, search_path fijo, mensajes con HINT msg_usuario; solo service_role.
-- Captura: tecnica.f_autorizar_captura(correo, 'mantenimiento') — la clave ya existe (00_inspeccion): el operador necesita el formulario
-- asignado en Personal; supervisor y administrador pasan siempre. Supervisión: el perfil del 1b (hasta el Corte 4, ver_dashboard_tecnico).
-- =====================================================================

-- ---------- Ayudantes internos (nadie de la API los ejecuta) ----------
-- Supervisor o administrador de Técnica; si no, 42501.
create function redes.f_supervisor(p_solicitante text, p_que text) returns text
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p.perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador %', p_que using errcode = '42501'; end if;
  return p.email;
end $f$;

-- Reconstruye UNA fila de activo_vigente_mat (alta por inversión, asociar, edición de la ficha): no se recalcula la tabla entera.
create function redes.f_mat_refrescar_uno(p_activo bigint) returns void
language plpgsql set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
begin
  delete from redes.activo_vigente_mat where activo_id = p_activo;
  insert into redes.activo_vigente_mat (activo_id, codigo, prefijo, sistema, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m,
         profundidad_m, fecha_instalacion, estado_codigo, cuenta_vigente, punteado, retirado, oculto, capa_codigo, llave_capa, codigo_anterior, carga_id)
  select activo_id, codigo, prefijo, sistema, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m,
         profundidad_m, fecha_instalacion, estado_codigo, cuenta_vigente, punteado, retirado, oculto, capa_codigo, llave_capa, codigo_anterior, carga_id
    from redes.v_activo_vigente where activo_id = p_activo;
end $f$;

-- Alta de un activo que crea una intervención (inversión, activo nuevo): código propio, versión 1 sin carga, «por verificar» y su origen.
-- La topología (nodos) y el enlace con los contratos se completan cuando el supervisor lo verifica o llega en una carga (Cortes 4 y 5).
create function redes.f_activo_crear(p_prefijo text, p_geom geometry, p_clase text, p_material text, p_diametro numeric, p_nombre text, p_fecha date,
                                     p_atributos jsonb, p_origen text, p_aportante text, p_autor text, p_motivo text) returns bigint
language plpgsql set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
declare v_cons bigint; v_cod text; v_id bigint; v_long numeric; v_attr jsonb := coalesce(p_atributos, '{}'::jsonb);
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  if v_cons is null then perform tecnica.f_error('Ese tipo de activo no tiene consecutivo'); end if;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'intervencion', p_autor) returning id into v_id;
  v_long := case when GeometryType(p_geom) in ('LINESTRING', 'MULTILINESTRING') then round(ST_Length(p_geom::geography)::numeric, 2) end;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, material_codigo, diametro_mm, longitud_m, fecha_instalacion, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, p_nombre, p_clase, p_material, p_diametro, v_long, p_fecha, 'en_operacion', v_attr,
          redes.f_huella(p_geom, jsonb_build_object('p', p_prefijo, 'n', p_nombre, 'c', p_clase, 'e', null, 'm', p_material, 'd', p_diametro, 'l', v_long,
                                                    'pr', null, 'ca', null, 's', 'en_operacion', 'ant', null, 'a', v_attr)), p_autor);
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (v_id, 'por_verificar', p_motivo, p_autor);
  insert into redes.activo_origen (activo_id, version, origen, aportante_codigo, nota, autor) values (v_id, 1, p_origen, p_aportante, left(p_motivo, 500), p_autor);
  perform redes.f_mat_refrescar_uno(v_id);
  perform redes.f_subir_tesela((select sistema from redes.tipos_activo where prefijo = p_prefijo));
  return v_id;
end $f$;

-- Fuentes de los recursos (D-8) → lista limpia {n, aportante, entidad, valor, porcentaje, soporte}.
--   p_con_valores = falso (operario): solo quién aporta; si trae valor, porcentaje o soporte, se rechaza.
--   p_exigir_valor (el supervisor completa): cada fuente lleva su valor o su porcentaje. Los porcentajes no suman más de 100.
create function redes.f_fuentes_validas(p jsonb, p_con_valores boolean, p_exigir_valor boolean) returns jsonb
language plpgsql stable set search_path to 'redes', 'tecnica', 'pg_temp' as $f$
declare f jsonb; v_out jsonb := '[]'::jsonb; v_n integer := 0; v_pct numeric := 0; v_ap text; v_ent text; v_val numeric; v_por numeric; v_sop text; v_vistos text[] := '{}';
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) = 0 then perform tecnica.f_error('Marque quién aporta los recursos (al menos una fuente)'); end if;
  if jsonb_array_length(p) > 10 then perform tecnica.f_error('Hasta 10 fuentes de recursos'); end if;
  for f in select e from jsonb_array_elements(p) e loop
    if jsonb_typeof(f) <> 'object' then perform tecnica.f_error('Las fuentes de los recursos no son válidas'); end if;
    v_ap := f ->> 'aportante';
    if not exists (select 1 from redes.entidades_aportantes where codigo = v_ap and activo) then perform tecnica.f_error('Una de las fuentes de los recursos no existe'); end if;
    v_ent := nullif(btrim(coalesce(f ->> 'entidad', '')), '');
    if v_ap = 'otro' and v_ent is null then perform tecnica.f_error('Diga cuál es la otra entidad que aporta'); end if;
    if v_ent is not null and length(v_ent) not between 2 and 120 then perform tecnica.f_error('El nombre de la entidad lleva de 2 a 120 caracteres'); end if;
    if (v_ap || '|' || coalesce(lower(v_ent), '')) = any (v_vistos) then perform tecnica.f_error('Hay una fuente de recursos repetida'); end if;
    v_vistos := v_vistos || (v_ap || '|' || coalesce(lower(v_ent), ''));
    v_val := (f ->> 'valor')::numeric; v_por := (f ->> 'porcentaje')::numeric; v_sop := nullif(btrim(coalesce(f ->> 'soporte', '')), '');
    if not p_con_valores and (v_val is not null or v_por is not null or v_sop is not null) then
      perform tecnica.f_error('El valor, el porcentaje y el soporte de los recursos los pone el supervisor');
    end if;
    if v_val is not null and (v_val < 0 or v_val >= 100000000000000) then perform tecnica.f_error('El valor de una fuente no es válido'); end if;
    if v_por is not null and (v_por <= 0 or v_por > 100) then perform tecnica.f_error('El porcentaje de una fuente va de 0 a 100'); end if;
    if p_exigir_valor and v_val is null and v_por is null then perform tecnica.f_error('Cada fuente lleva su valor o su porcentaje'); end if;
    if v_sop is not null and length(v_sop) not between 2 and 200 then perform tecnica.f_error('El soporte lleva de 2 a 200 caracteres'); end if;
    v_pct := v_pct + coalesce(v_por, 0); v_n := v_n + 1;
    v_out := v_out || jsonb_build_object('n', v_n, 'aportante', v_ap, 'entidad', v_ent, 'valor', v_val, 'porcentaje', v_por, 'soporte', v_sop);
  end loop;
  if v_pct > 100 then perform tecnica.f_error('Los porcentajes de las fuentes suman más de 100'); end if;
  return v_out;
end $f$;

-- ¿El daño se puede atender con esta intervención? Abierto, del mismo sistema y del activo (o de uno también intervenido) o cercano.
create function redes.f_dano_elegible(p_dano redes.v_dano, p_sistema text, p_activos bigint[], p_pto geometry) returns boolean
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
  select coalesce(p_dano.estado in ('reportado', 'en_atencion') and p_dano.sistema = p_sistema
     and (coalesce(p_dano.activo_id = any (p_activos), false)
          or ST_DWithin(p_dano.geom::geography, p_pto::geography, redes.f_param('itv_radio_danos_m'))
          or exists (select 1 from redes.activo_vigente_mat m where m.activo_id = any (p_activos) and ST_DWithin(m.geom::geography, p_dano.geom::geography, redes.f_param('itv_radio_danos_m')))), false) $f$;

-- ---------- Formulario: catálogos y reglas para la pantalla ----------
create function public.geoportal_redes_formulario_intervencion(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'mantenimiento'); v_perfil text := tecnica.f_perfil(v_email);
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
    'reglas', jsonb_build_object('dias_atras_max', redes.f_param('itv_dias_atras_max'), 'max_horas', redes.f_param('itv_max_horas'),
                                 'min_fotos', case when v_perfil in ('admin', 'supervisor') then 0 else redes.f_param('min_fotos_itv') end,
                                 'puede_sin_fotos', v_perfil in ('admin', 'supervisor'), 'pone_valores', v_perfil in ('admin', 'supervisor'),
                                 'max_fotos', redes.f_param('max_fotos_itv'), 'max_documentos', redes.f_param('max_docs_itv'),
                                 'max_bytes_foto', redes.f_param('max_bytes_foto_itv'), 'max_bytes_documento', redes.f_param('max_bytes_doc_itv'),
                                 'max_horas_inicio', tecnica.f_max_horas_inicio(), 'radio_cercanos_m', redes.f_param('distancia_activo_cercano_m'),
                                 'radio_danos_m', redes.f_param('itv_radio_danos_m'), 'max_tambien', redes.f_param('itv_max_activos_tambien'),
                                 'max_materiales', redes.f_param('itv_max_materiales'), 'zoom_min', redes.f_param('mini_zoom_min'), 'zoom_accesorios', redes.f_param('mini_zoom_acc')),
    'ahora', clock_timestamp());
end $f$;

-- ---------- Daños abiertos que puede atender (del activo, de los también intervenidos o cercanos). La posición no se guarda. ----------
create function public.geoportal_redes_danos_abiertos(p_solicitante text, p_sistema text, p_activo text default null, p_lat numeric default null, p_lon numeric default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'mantenimiento'); v_id bigint; v_ref geometry; v_radio numeric := redes.f_param('itv_radio_danos_m');
begin
  if coalesce(p_sistema, '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;
  if nullif(btrim(coalesce(p_activo, '')), '') is not null then
    v_id := redes.f_buscar_activo(p_activo);
    select geom into v_ref from redes.activo_vigente_mat where activo_id = v_id;
  elsif p_lat is not null and p_lon is not null and p_lat between -90 and 90 and p_lon between -180 and 180 then
    v_ref := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326);
  else perform tecnica.f_error('Elija primero el activo o marque el punto');
  end if;
  return jsonb_build_object('radio_m', v_radio, 'danos', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'clase', x.clase, 'tipo', x.tipo_nombre, 'activo', x.activo_codigo, 'no_identificado', x.no_ident_que_es,
                                        't_detectado', x.t_detectado, 'estado', x.estado, 'mismo_activo', x.mismo, 'distancia_m', x.dist) order by x.mismo desc, x.dist, x.t_detectado desc)
      from (select d.codigo, d.clase, d.tipo_nombre, d.activo_codigo, d.no_ident_que_es, d.t_detectado, d.estado,
                   coalesce(d.activo_id = v_id, false) as mismo, round(ST_Distance(d.geom::geography, v_ref::geography)::numeric, 0) as dist
              from redes.v_dano d
             where d.estado in ('reportado', 'en_atencion') and d.sistema = p_sistema
               and (d.activo_id = v_id or ST_DWithin(d.geom::geography, v_ref::geography, v_radio))
             order by 8 desc, 9, d.t_detectado desc limit 10) x), '[]'::jsonb));
end $f$;

-- ---------- Preparar: reserva el id y las rutas de las fotos (1…F, .jpg) y de los documentos (F+1…F+D, .pdf) ----------
create function public.geoportal_redes_preparar_intervencion(p_solicitante text, p_fotos integer, p_documentos integer default 0)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'mantenimiento'); v_id uuid := gen_random_uuid();
        v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM'); v_min integer; v_max integer := redes.f_param('max_fotos_itv')::integer;
        v_maxd integer := redes.f_param('max_docs_itv')::integer; v_d integer := coalesce(p_documentos, 0);
begin
  v_min := case when tecnica.f_perfil(v_email) in ('admin', 'supervisor') then 0 else redes.f_param('min_fotos_itv')::integer end;
  if p_fotos is null or p_fotos < v_min or p_fotos > v_max then perform tecnica.f_error(format('Una intervención lleva de %s a %s fotos', v_min, v_max)); end if;
  if v_d < 0 or v_d > v_maxd then perform tecnica.f_error(format('Se adjuntan hasta %s documentos', v_maxd)); end if;
  insert into redes.intervencion_preparaciones (intervencion_id, autor, fotos, documentos) values (v_id, v_email, p_fotos, v_d);
  return jsonb_build_object('intervencion_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_itv')::bigint,
    'max_bytes_documento', redes.f_param('max_bytes_doc_itv')::bigint,
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'intervenciones/' || v_mes || '/' || v_id::text || '/' || n || '.jpg', 'tipo_mime', 'image/jpeg') order by n)
                         from generate_series(1, p_fotos) n), '[]'::jsonb),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object('n', p_fotos + n, 'ruta', 'intervenciones/' || v_mes || '/' || v_id::text || '/' || (p_fotos + n) || '.pdf', 'tipo_mime', 'application/pdf') order by n)
                              from generate_series(1, v_d) n), '[]'::jsonb));
end $f$;

-- ---------- Crear la intervención (flujo A, D-6: queda «cerrada»). Una sola transacción. Hora oficial = servidor; autor = solicitante verificado. ----------
-- p_datos: {nace_de, dano, tipo, inversion_modo, sistema, activo | no_identificado | nuevo{prefijo, clase, material, diametro_mm, nombre, puntos[[lat, lon]…]},
--           lat, lon, precision_m, ubicacion_origen, t_inicio, t_fin, inicio_dispositivo, descripcion, materiales[{material, cantidad, unidad}],
--           ejecutor, contratista, contratista_nombre, contrato_orden, companeros, tambien[códigos], fuentes[{aportante, entidad, valor, porcentaje, soporte}],
--           sin_evidencia_motivo, archivos[{n, clase, ruta}]}
-- Si nace de un daño abierto: el daño recibe sus tiempos de reparación (inicio y fin del trabajo) y queda «atendido» con el código de la intervención.
create function public.geoportal_redes_crear_intervencion(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_captura(p_solicitante, 'mantenimiento'); v_super boolean; d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_intervencion%rowtype; v_tipo redes.tipos_intervencion%rowtype; v_sis text; v_modo text;
  v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text; v_nuevo jsonb; v_tn redes.v_tipo_visible%rowtype; v_geom_nuevo geometry;
  v_clase_n text; v_mat_n text; v_diam_n numeric; v_nom_n text; v_pts jsonb; v_p jsonb; v_lat numeric; v_lon numeric; v_fuera boolean;
  v_t_ini timestamptz; v_t_fin timestamptz; v_inicio timestamptz; v_desc text := btrim(coalesce(d ->> 'descripcion', ''));
  v_dano redes.v_dano%rowtype; v_tambien bigint[] := '{}'; v_x text; v_xid bigint; v_mats jsonb := coalesce(d -> 'materiales', '[]'::jsonb); v_m jsonb;
  v_fuentes jsonb; v_arch jsonb := coalesce(d -> 'archivos', '[]'::jsonb); v_ref jsonb := '[]'::jsonb; v_nf integer := 0; v_nd integer := 0; v_n integer;
  v_f jsonb; v_ruta text; v_size bigint; v_mime text; v_prep redes.intervencion_preparaciones%rowtype; v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
  v_cons bigint; v_codigo text; v_ctr bigint; v_ctr_nom text; v_orden text := nullif(btrim(coalesce(d ->> 'contrato_orden', '')), '');
  v_comp text := nullif(btrim(coalesce(d ->> 'companeros', '')), ''); v_pto geometry; v_creado boolean := false; v_origen text; v_aport text; v_cod_nuevo text;
  v_dano_estado text;
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
  v_super := tecnica.f_perfil(v_email) in ('admin', 'supervisor');

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
  if v_t_ini < v_ahora - make_interval(days => redes.f_param('itv_dias_atras_max')::integer) then
    perform tecnica.f_error(format('El inicio no puede ser de hace más de %s días', redes.f_param('itv_dias_atras_max')::integer));
  end if;
  if v_t_fin - v_t_ini > make_interval(hours => redes.f_param('itv_max_horas')::integer) then
    perform tecnica.f_error(format('Una intervención dura hasta %s horas: si duró más, regístrela por partes', redes.f_param('itv_max_horas')::integer));
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
    if v_dano.t_inicio_reparacion is not null and v_t_fin < v_dano.t_inicio_reparacion then
      perform tecnica.f_error(format('La intervención terminó antes del inicio de la reparación que ya tenía el daño %s', v_dano.codigo));
    end if;
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
  if v_nf = 0 then
    if not v_super then perform tecnica.f_error(format('Tome al menos %s foto de la intervención', redes.f_param('min_fotos_itv')::integer)); end if;
    if v_sinev is null or length(v_sinev) not between 10 and 300 then
      perform tecnica.f_error('Sin fotos, escriba por qué no hay evidencia fotográfica (10 a 300 caracteres)');
    end if;
  elsif v_nf < redes.f_param('min_fotos_itv') and not v_super then
    perform tecnica.f_error(format('Tome al menos %s foto de la intervención', redes.f_param('min_fotos_itv')::integer));
  elsif v_sinev is not null then
    perform tecnica.f_error('Con fotos, no marque «sin evidencia fotográfica»');
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
         contrato_orden, companeros, sin_evidencia_motivo, autor, registrado_en)
  values (p_id, v_codigo, d ->> 'nace_de', v_dano.id, v_tipo.codigo, v_modo, v_sis, v_activo, v_creado, v_noid, round(v_lat, 6), round(v_lon, 6),
          d ->> 'ubicacion_origen', (d ->> 'precision_m')::numeric, v_fuera, v_t_ini, v_t_fin, v_inicio, case when v_inicio is not null then 'dispositivo' end,
          v_desc, d ->> 'ejecutor', v_ctr, v_ctr_nom, v_orden, v_comp, v_sinev, v_email, v_ahora);
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

  -- al cerrar una intervención que nace de un daño: el daño recibe sus tiempos de reparación y queda atendido
  if v_dano.id is not null then
    insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor)
    values (v_dano.id, case when v_dano.t_inicio_reparacion is null then v_t_ini end, v_t_fin, 'intervencion', v_email);
    insert into redes.dano_eventos (dano_id, tipo, intervencion_id, motivo, autor)
    values (v_dano.id, 'atendido', p_id, format('Atendido con la intervención %s (%s)', v_codigo, v_tipo.nombre), v_email);
    select x.estado into v_dano_estado from redes.v_dano x where x.id = v_dano.id;
  end if;

  -- auditoría sin la posición ni los valores
  perform tecnica.f_auditar(v_email, 'redes_crear_intervencion', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'nace_de', d ->> 'nace_de', 'dano', v_dano.codigo,
          'sistema', v_sis, 'activo', coalesce(v_act.codigo, v_cod_nuevo), 'activo_creado', v_creado, 'no_identificado', v_noid is not null, 'tambien', cardinality(v_tambien),
          'fotos', v_nf, 'documentos', v_nd, 'sin_evidencia', v_nf = 0, 'ejecutor', d ->> 'ejecutor'), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo, 'activo_creado', x.activo_creado,
                                    'dano', x.dano_codigo, 'dano_estado', v_dano_estado, 'recursos', x.recursos, 'sin_evidencia', x.sin_evidencia, 'fuera_de_zona', x.fuera_de_zona,
                                    'duracion_s', x.duracion_s, 'repetido', false) from redes.v_intervencion x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.intervenciones where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_intervencion x where x.id = p_id);
  end if;
  perform tecnica.f_error('Uno de los archivos ya está usado en otra intervención');
  return null;
end $f$;

-- ---------- Supervisor: recursos (D-8). Versión nueva de las fuentes con el valor o el porcentaje y el soporte. ----------
create function public.geoportal_redes_intervencion_recursos(p_solicitante text, p_ref text, p_fuentes jsonb, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'completa los recursos'); i redes.v_intervencion%rowtype; v_f jsonb; v_ver integer; v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform pg_advisory_xact_lock(hashtext('redes.itv.' || upper(btrim(coalesce(p_ref, '')))));
  select * into i from redes.v_intervencion where codigo = upper(btrim(coalesce(p_ref, '')));
  if not found then perform tecnica.f_error('No existe esa intervención', 'P0002'); end if;
  if i.estado = 'oculta' then perform tecnica.f_error('Esa intervención está oculta'); end if;
  v_f := redes.f_fuentes_validas(p_fuentes, true, true);
  if v_mot is not null and length(v_mot) not between 10 and 1000 then perform tecnica.f_error('El motivo lleva de 10 a 1.000 caracteres'); end if;
  if i.recursos = 'completos' and v_mot is null then perform tecnica.f_error('Los recursos ya estaban completos: para cambiarlos, escriba el motivo'); end if;
  v_ver := (select max(version) from redes.intervencion_fuentes where intervencion_id = i.id) + 1;
  insert into redes.intervencion_fuentes (intervencion_id, version, n, aportante_codigo, entidad, valor, porcentaje, soporte, fuente, autor)
  select i.id, v_ver, (f ->> 'n')::smallint, f ->> 'aportante', f ->> 'entidad', (f ->> 'valor')::numeric, (f ->> 'porcentaje')::numeric, f ->> 'soporte', 'supervisor', v_email
    from jsonb_array_elements(v_f) f;
  insert into redes.intervencion_eventos (intervencion_id, tipo, motivo, autor) values (i.id, 'completar_recursos', coalesce(v_mot, 'Recursos completados por el supervisor (versión ' || v_ver || ')'), v_email);
  perform tecnica.f_auditar(v_email, 'redes_intervencion_recursos', i.codigo, jsonb_build_object('version', v_ver, 'fuentes', jsonb_array_length(v_f)), null);
  return jsonb_build_object('codigo', i.codigo, 'version', v_ver, 'recursos', (select recursos from redes.v_intervencion where id = i.id));
end $f$;

-- ---------- Supervisor: lista de intervenciones (recientes, o con recursos por completar), con sus fuentes vigentes ----------
create function public.geoportal_redes_intervenciones(p_solicitante text, p_filtro text default 'recientes', p_limite integer default 50)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven la lista de intervenciones'); v_lim integer := coalesce(p_limite, 50);
begin
  if coalesce(p_filtro, '') not in ('recientes', 'recursos_por_completar') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_lim < 1 or v_lim > 100 then perform tecnica.f_error('Se piden de 1 a 100 intervenciones'); end if;
  return jsonb_build_object('filtro', p_filtro, 'intervenciones', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'tipo', x.tipo_nombre, 'inversion_modo', x.inversion_modo, 'sistema', x.sistema, 'activo', x.activo_codigo,
             'no_identificado', x.no_ident_que_es, 'dano', x.dano_codigo, 't_fin', x.t_fin, 'ejecutor', x.ejecutor, 'contratista', x.contratista, 'autor', x.autor,
             'recursos', x.recursos, 'sin_evidencia', x.sin_evidencia, 'fotos', x.fotos, 'estado', x.estado,
             'fuentes', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('n', f.n, 'aportante', f.aportante_codigo, 'aportante_nombre', e.nombre, 'entidad', f.entidad, 'valor', f.valor,
                                                                               'porcentaje', f.porcentaje, 'soporte', f.soporte)) order by f.n)
                           from redes.v_intervencion_fuentes f join redes.entidades_aportantes e on e.codigo = f.aportante_codigo where f.intervencion_id = x.id))
             order by x.registrado_en desc)
      from (select * from redes.v_intervencion v
             where v.estado <> 'oculta' and (p_filtro = 'recientes' or v.recursos = 'por_completar')
             order by v.registrado_en desc limit v_lim) x), '[]'::jsonb));
end $f$;

-- ---------- Supervisor: bandeja de «activo no identificado» con la propuesta de los activos más cercanos ----------
create function public.geoportal_redes_no_identificados(p_solicitante text, p_limite integer default 50)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven la bandeja de no identificados'); v_lim integer := coalesce(p_limite, 50); v_radio numeric := redes.f_param('itv_radio_propuesta_m');
begin
  if v_lim < 1 or v_lim > 100 then perform tecnica.f_error('Se piden de 1 a 100'); end if;
  return jsonb_build_object('radio_m', v_radio, 'pendientes', (select count(*) from redes.v_no_identificados), 'items', coalesce((
    select jsonb_agg(jsonb_build_object('clase', n.clase, 'codigo', n.codigo, 'sistema', n.sistema, 'que_es', n.que_es, 'resumen', n.resumen, 'estado', n.estado,
             'cuando', n.cuando, 'autor', n.autor, 'lat', n.lat, 'lon', n.lon,
             -- a igual distancia (al decímetro), primero los puntos (pozo, válvula…) y después los tramos que llegan a ellos, como en «cerca de mí»
             'propuestos', coalesce((select jsonb_agg(redes.f_activo_corto(c.activo_id) || jsonb_build_object('distancia_m', c.dist) order by c.dist, c.es_linea, c.codigo)
                                      from (select m.activo_id, m.codigo, round(ST_Distance(m.geom::geography, n.geom::geography)::numeric, 1) as dist, GeometryType(m.geom) <> 'POINT' as es_linea
                                              from redes.activo_vigente_mat m
                                             where m.sistema = n.sistema and not m.retirado and not m.oculto and ST_DWithin(m.geom::geography, n.geom::geography, v_radio)
                                             order by m.geom <-> n.geom limit 3) c), '[]'::jsonb))
             order by n.registrado_en desc)
      from (select * from redes.v_no_identificados order by registrado_en desc limit v_lim) n), '[]'::jsonb));
end $f$;

-- ---------- Supervisor: asociar un activo a una intervención o a un daño «no identificado» (evento; no se reescribe nada) ----------
create function public.geoportal_redes_asociar_activo(p_solicitante text, p_clase text, p_ref text, p_activo text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'asocian activos'); v_id uuid; v_sis text; v_actual bigint; a redes.activo_vigente_mat%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if coalesce(p_clase, '') not in ('intervencion', 'dano') then perform tecnica.f_error('Diga si es una intervención o un daño'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.asociar.' || upper(btrim(coalesce(p_ref, '')))));
  if p_clase = 'intervencion' then
    select id, sistema, activo_id into v_id, v_sis, v_actual from redes.v_intervencion where codigo = upper(btrim(coalesce(p_ref, ''))) and estado <> 'oculta';
  else
    select id, sistema, activo_id into v_id, v_sis, v_actual from redes.v_dano where codigo = upper(btrim(coalesce(p_ref, ''))) and estado <> 'oculto';
  end if;
  if v_id is null then perform tecnica.f_error('No existe ese registro (o está oculto)', 'P0002'); end if;
  if v_actual is not null then perform tecnica.f_error('Ese registro ya tiene activo'); end if;
  select * into a from redes.activo_vigente_mat where activo_id = redes.f_buscar_activo(p_activo);
  if a.retirado then perform tecnica.f_error('Ese activo está retirado'); end if;
  if a.sistema <> v_sis then perform tecnica.f_error('Ese activo no es del mismo sistema'); end if;
  if p_clase = 'intervencion' then
    if exists (select 1 from redes.intervencion_activos where intervencion_id = v_id and activo_id = a.activo_id) then perform tecnica.f_error('Ese activo ya está entre los también intervenidos'); end if;
    insert into redes.intervencion_eventos (intervencion_id, tipo, activo_id, motivo, autor) values (v_id, 'asociar_activo', a.activo_id, v_mot, v_email);
  else
    insert into redes.dano_eventos (dano_id, tipo, activo_id, motivo, autor) values (v_id, 'asociar_activo', a.activo_id, v_mot, v_email);
  end if;
  perform tecnica.f_auditar(v_email, 'redes_asociar_activo', upper(btrim(p_ref)), jsonb_build_object('clase', p_clase, 'activo', a.codigo), null);
  return jsonb_build_object('clase', p_clase, 'codigo', upper(btrim(p_ref)), 'activo', a.codigo);
end $f$;

-- ---------- Daño o falla (Corte 2), con la respuesta 2 de David: sin fotos solo el supervisor o el administrador, con el motivo ----------
create or replace function public.geoportal_redes_preparar_dano(p_solicitante text, p_fotos integer)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas'); v_id uuid := gen_random_uuid();
        v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM'); v_max integer := redes.f_param('max_fotos_dano')::integer; v_min integer;
begin
  v_min := case when tecnica.f_perfil(v_email) in ('admin', 'supervisor') then 0 else redes.f_param('min_fotos_dano')::integer end;
  if p_fotos is null or p_fotos < v_min or p_fotos > v_max then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', v_min, v_max));
  end if;
  insert into redes.dano_preparaciones (dano_id, autor, fotos) values (v_id, v_email, p_fotos);
  return jsonb_build_object('dano_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_dano')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'danos/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n) from generate_series(1, p_fotos) n), '[]'::jsonb));
end $f$;

create or replace function public.geoportal_redes_crear_dano(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas'); d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_dano%rowtype; v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text;
  v_t_ini timestamptz; v_t_det timestamptz; v_t_rep timestamptz; v_t_res timestamptz; v_inicio timestamptz;
  v_lat numeric; v_lon numeric; v_fuera boolean; v_fotos jsonb := coalesce(p_datos -> 'fotos', '[]'::jsonb); v_n integer; v_f jsonb; v_ruta text; v_size bigint; v_mime text;
  v_ref jsonb := '[]'::jsonb; v_cons bigint; v_codigo text; v_tipo redes.tipos_dano%rowtype; v_marcas text[]; v_causa text; v_ter text; v_ter_nom text;
  v_desc text := nullif(btrim(coalesce(d ->> 'descripcion', '')), ''); v_max_bytes bigint := redes.f_param('max_bytes_foto_dano')::bigint;
  v_super boolean := tecnica.f_perfil(v_email) in ('admin', 'supervisor'); v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador del daño: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_dano where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'fuera_de_zona', v_prev.fuera_de_zona, 'sin_evidencia', not exists (select 1 from redes.dano_fotos f where f.dano_id = p_id), 'repetido', true);
  end if;
  if not exists (select 1 from redes.dano_preparaciones where dano_id = p_id and autor = v_email) then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos del daño no son válidos'); end if;

  -- qué pasó
  select * into v_tipo from redes.tipos_dano where codigo = d ->> 'tipo' and activo;
  if not found then perform tecnica.f_error('Elija qué pasó'); end if;
  if d ->> 'clase' is distinct from v_tipo.clase then perform tecnica.f_error('El tipo elegido no corresponde a daño o falla'); end if;
  if coalesce(d ->> 'sistema', '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;
  if not ((d ->> 'sistema') = any (v_tipo.sistemas)) then perform tecnica.f_error(format('«%s» no aplica a %s', v_tipo.nombre, d ->> 'sistema')); end if;

  -- activo o «no identificado»
  if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado then perform tecnica.f_error('El activo elegido no existe o está retirado: elíjalo de nuevo en el mapa'); end if;
    if v_act.sistema <> d ->> 'sistema' then perform tecnica.f_error('El activo elegido no es de ese sistema'); end if;
    v_activo := v_act.activo_id;
  else
    v_noid := nullif(btrim(coalesce(d ->> 'no_identificado', '')), '');
    if v_noid is null or length(v_noid) < 3 or length(v_noid) > 120 then perform tecnica.f_error('Elija el activo en el mapa o, si no lo identifica, diga qué es (3 a 120 caracteres)'); end if;
  end if;

  -- ubicación: nunca se rechaza por estar fuera de la zona (se marca)
  v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric;
  if v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then perform tecnica.f_error('Falta la ubicación del daño'); end if;
  if coalesce(d ->> 'ubicacion_origen', '') not in ('gps', 'mapa', 'activo') then perform tecnica.f_error('Falta de dónde sale la ubicación'); end if;
  v_fuera := v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max');

  -- tiempos (contra la hora del servidor)
  v_t_ini := redes.f_instante(d ->> 't_inicio_dano', 'inicio del daño');
  v_t_det := redes.f_instante(d ->> 't_detectado', 'detectado');
  v_t_rep := redes.f_instante(d ->> 't_inicio_reparacion', 'inicio de la reparación');
  v_t_res := redes.f_instante(d ->> 't_restablecido', 'servicio restablecido');
  if v_t_det is null then perform tecnica.f_error('Escriba cuándo se detectó'); end if;
  if greatest(v_t_ini, v_t_det, v_t_rep, v_t_res) > v_ahora + interval '2 minutes' then perform tecnica.f_error('Hay una hora en el futuro: revise la hora de su celular'); end if;
  if v_t_det < v_ahora - make_interval(days => redes.f_param('dano_dias_atras_max')::integer) then
    perform tecnica.f_error(format('La detección no puede ser de hace más de %s días', redes.f_param('dano_dias_atras_max')::integer));
  end if;
  if v_t_ini is not null and v_t_ini > v_t_det then perform tecnica.f_error('El inicio del daño no puede ser después de la detección'); end if;
  if v_t_rep is not null and v_t_rep < v_t_det then perform tecnica.f_error('El inicio de la reparación no puede ser antes de la detección'); end if;
  if v_t_res is not null and v_t_rep is null then perform tecnica.f_error('Para el servicio restablecido, escriba también el inicio de la reparación'); end if;
  if v_t_res is not null and v_t_res < v_t_rep then perform tecnica.f_error('El servicio restablecido no puede ser antes del inicio de la reparación'); end if;
  v_inicio := redes.f_instante(d ->> 'inicio_dispositivo', 'apertura del formulario');
  if v_inicio is not null and (v_inicio > v_ahora + interval '2 minutes' or v_inicio < v_ahora - make_interval(hours => tecnica.f_max_horas_inicio())) then
    perform tecnica.f_error(format('Este formulario se abrió hace más de %s horas o la hora de su celular está adelantada. Revise la hora y vuelva a enviar.', tecnica.f_max_horas_inicio()));
  end if;

  -- tamaño, afectación, riesgo y causa
  if d ->> 'tipo_rotura' is not null and not exists (select 1 from redes.tipos_rotura where codigo = d ->> 'tipo_rotura' and activo) then perform tecnica.f_error('El tipo de rotura no existe'); end if;
  if d ->> 'tipo_rotura' is not null and not v_tipo.pide_rotura then perform tecnica.f_error('Este tipo de daño no lleva tipo de rotura'); end if;
  if coalesce(d ->> 'riesgo', '') not in ('bajo', 'medio', 'alto') then perform tecnica.f_error('Elija el riesgo'); end if;
  if d -> 'marcas' is not null and jsonb_typeof(d -> 'marcas') <> 'array' then perform tecnica.f_error('Las marcas de riesgo no son válidas'); end if;
  v_marcas := coalesce(array(select distinct jsonb_array_elements_text(d -> 'marcas')), '{}');
  if exists (select 1 from unnest(v_marcas) m where not exists (select 1 from redes.marcas_riesgo r where r.codigo = m and r.activo)) then perform tecnica.f_error('Una marca de riesgo no existe'); end if;
  if coalesce(d ->> 'causa_clase', '') not in ('propia', 'terceros', 'desconocida') then perform tecnica.f_error('Elija la causa: propia, de terceros o desconocida'); end if;
  if d ->> 'causa_clase' = 'propia' then
    v_causa := d ->> 'causa';
    if not exists (select 1 from redes.causas where codigo = v_causa and activo) then perform tecnica.f_error('Elija la causa propia'); end if;
  elsif d ->> 'causa_clase' = 'terceros' then
    v_ter := d ->> 'tercero_tipo';
    if not exists (select 1 from redes.tipos_tercero where codigo = v_ter and activo) then perform tecnica.f_error('Elija quién lo causó'); end if;
    v_ter_nom := nullif(btrim(coalesce(d ->> 'tercero_nombre', '')), '');
    if v_ter_nom is not null and length(v_ter_nom) not between 2 and 120 then perform tecnica.f_error('El nombre, la empresa o la placa lleva de 2 a 120 caracteres'); end if;
  end if;
  if v_desc is not null and length(v_desc) > 1000 then perform tecnica.f_error('La descripción admite hasta 1.000 caracteres'); end if;

  -- fotos: el tamaño y el tipo se leen de Storage (nunca se le creen al celular). Sin fotos: solo supervisor o administrador, con el motivo.
  if jsonb_typeof(v_fotos) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n = 0 and v_super then
    if v_sinev is null or length(v_sinev) not between 10 and 300 then
      perform tecnica.f_error('Sin fotos, escriba por qué no hay evidencia fotográfica (10 a 300 caracteres), por ejemplo «llegó por la línea 116»');
    end if;
  elsif v_n < redes.f_param('min_fotos_dano') or v_n > redes.f_param('max_fotos_dano') or v_n > (select fotos from redes.dano_preparaciones where dano_id = p_id) then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', redes.f_param('min_fotos_dano')::integer, redes.f_param('max_fotos_dano')::integer));
  elsif v_sinev is not null then
    perform tecnica.f_error('Con fotos, no marque «sin evidencia fotográfica»');
  end if;
  if v_n > 0 and (select count(distinct (e ->> 'n')::integer) <> v_n or min((e ->> 'n')::integer) <> 1 or max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_fotos) e) then
    perform tecnica.f_error('El orden de las fotos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  if v_n > 0 and not exists (select 1 from jsonb_array_elements(v_fotos) e where e ->> 'momento' = 'dano') then perform tecnica.f_error('Falta una foto del daño'); end if;
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'n')::integer loop
    if coalesce(v_f ->> 'momento', '') not in ('dano', 'entorno', 'reparado') then perform tecnica.f_error('Cada foto dice si es del daño, del entorno o de la reparación'); end if;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^danos/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || '\.jpg$') then
      perform tecnica.f_error(format('La ruta de la foto %s no corresponde a este daño', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró la foto %s: súbala de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('La foto %s está vacía', v_f ->> 'n')); end if;
    if v_size > v_max_bytes then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'momento', v_f ->> 'momento', 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;

  -- código DAN-000123 (candado de fila del consecutivo) e inserción
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'DAN' returning ultimo into v_cons;
  v_codigo := 'DAN-' || lpad(v_cons::text, 6, '0');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, no_ident_que_es, lat, lon, ubicacion_origen, precision_m, fuera_de_zona,
         t_inicio_dano, t_detectado, inicio_en, inicio_origen, tipo_rotura, largo_afectado_m, presion_mca, usuarios_sin_servicio, sector_texto,
         riesgo, marcas, causa_clase, causa_codigo, tercero_tipo, descripcion, origen, autor, registrado_en)
  values (p_id, v_codigo, v_tipo.clase, v_tipo.codigo, d ->> 'sistema', v_activo, v_noid, round(v_lat, 6), round(v_lon, 6), d ->> 'ubicacion_origen',
          (d ->> 'precision_m')::numeric, v_fuera, v_t_ini, v_t_det, v_inicio, case when v_inicio is not null then 'dispositivo' end,
          d ->> 'tipo_rotura', (d ->> 'largo_afectado_m')::numeric, (d ->> 'presion_mca')::numeric, (d ->> 'usuarios_sin_servicio')::integer,
          nullif(btrim(coalesce(d ->> 'sector', '')), ''), d ->> 'riesgo', v_marcas, d ->> 'causa_clase', v_causa, v_ter, v_desc, 'formulario', v_email, v_ahora);
  if v_ter_nom is not null then insert into redes.dano_datos_sensibles (dano_id, tercero_nombre) values (p_id, v_ter_nom); end if;
  if v_t_rep is not null then insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor) values (p_id, v_t_rep, v_t_res, 'formulario', v_email); end if;
  insert into redes.dano_fotos (dano_id, n, momento, ruta_storage, bytes, mime)
  select p_id, (x ->> 'n')::smallint, x ->> 'momento', x ->> 'ruta', (x ->> 'bytes')::integer, x ->> 'mime' from jsonb_array_elements(v_ref) x;
  -- «sin evidencia fotográfica»: queda como nota del daño, con el motivo
  if v_n = 0 then insert into redes.dano_eventos (dano_id, tipo, motivo, autor) values (p_id, 'nota', 'Sin evidencia fotográfica: ' || v_sinev, v_email); end if;
  -- auditoría sin el nombre del tercero ni la posición
  perform tecnica.f_auditar(v_email, 'redes_crear_dano', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'sistema', d ->> 'sistema', 'activo', v_act.codigo,
          'no_identificado', v_noid is not null, 'fotos', v_n, 'sin_evidencia', v_n = 0, 'riesgo', d ->> 'riesgo'), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo,
                                    'fuera_de_zona', x.fuera_de_zona, 'respuesta_s', x.respuesta_s, 'reparacion_s', x.reparacion_s, 'total_s', x.total_s,
                                    'perdida_estado', x.perdida_estado, 'sin_evidencia', v_n = 0, 'repetido', false) from redes.v_dano x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.danos where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_dano x where x.id = p_id);
  end if;
  perform tecnica.f_error('Una de las fotos ya está usada en otro daño');
  return null;
end $f$;
