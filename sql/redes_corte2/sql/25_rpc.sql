-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 25 — RPC: formulario, preparar y crear el daño; minimapa (buscar, nodos de un tramo y tesela);
-- reportes del bot (recibir, convertir en daño y descartar)
-- PROPUESTA. No se ha ejecutado en la base real. Todas security definer, search_path fijo, mensajes con HINT msg_usuario; solo service_role.
-- Captura: tecnica.f_autorizar_captura(correo, 'danos_fallas') — la clave ya existe: el operador necesita el formulario asignado en Personal;
-- supervisor y administrador pasan siempre. Minimapa: el perfil de lectura del 1b (operador, supervisor o administrador de Técnica).
-- =====================================================================

-- Texto ISO con zona → timestamptz, o error para la persona.
create function redes.f_instante(p_valor text, p_rotulo text) returns timestamptz
language plpgsql stable set search_path to 'pg_catalog' as $f$
begin
  if p_valor is null or btrim(p_valor) = '' then return null; end if;
  if length(p_valor) > 40 or p_valor !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}(:?\d{2})?)$' then
    perform tecnica.f_error(format('La hora «%s» no viene en la forma esperada', p_rotulo));
  end if;
  return p_valor::timestamptz;
exception when others then
  if sqlstate = '22023' then raise; end if;
  perform tecnica.f_error(format('La hora «%s» no es válida', p_rotulo));
  return null;
end $f$;

-- ---------- Formulario: catálogos y reglas para la pantalla ----------
create function public.geoportal_redes_formulario_dano(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas');
begin
  return jsonb_build_object(
    'perfil', tecnica.f_perfil(v_email),
    'sistemas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.sistemas where codigo in ('acueducto', 'alcantarillado')),
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'clase', clase, 'nombre', nombre, 'sistemas', to_jsonb(sistemas), 'pide_rotura', pide_rotura) order by orden) from redes.tipos_dano where activo),
    'roturas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.tipos_rotura where activo),
    'causas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.causas where activo),
    'terceros', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.tipos_tercero where activo),
    'marcas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.marcas_riesgo where activo),
    'reglas', jsonb_build_object('dias_atras_max', redes.f_param('dano_dias_atras_max'), 'min_fotos', redes.f_param('min_fotos_dano'), 'max_fotos', redes.f_param('max_fotos_dano'),
                                 'max_bytes_foto', redes.f_param('max_bytes_foto_dano'), 'max_horas_inicio', tecnica.f_max_horas_inicio(),
                                 'radio_cercanos_m', redes.f_param('distancia_activo_cercano_m'), 'zoom_min', redes.f_param('mini_zoom_min'), 'zoom_accesorios', redes.f_param('mini_zoom_acc')),
    'hay_tabla_caudales', exists (select 1 from redes.caudales_fuga),
    'ahora', clock_timestamp());
end $f$;

-- ---------- Preparar: reserva el id del daño y las rutas de las fotos (la Edge firma las URL de subida) ----------
create function public.geoportal_redes_preparar_dano(p_solicitante text, p_fotos integer)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas'); v_id uuid := gen_random_uuid();
        v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM'); v_max integer := redes.f_param('max_fotos_dano')::integer;
begin
  if p_fotos is null or p_fotos < redes.f_param('min_fotos_dano') or p_fotos > v_max then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', redes.f_param('min_fotos_dano')::integer, v_max));
  end if;
  insert into redes.dano_preparaciones (dano_id, autor, fotos) values (v_id, v_email, p_fotos);
  return jsonb_build_object('dano_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_dano')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', (select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'danos/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n) from generate_series(1, p_fotos) n));
end $f$;

-- ---------- Crear el daño (una sola transacción). Hora oficial = servidor; autor = solicitante verificado; el reenvío con el mismo id no duplica. ----------
-- p_datos: {clase, tipo, sistema, activo | no_identificado, lat, lon, precision_m, ubicacion_origen, t_inicio_dano, t_detectado,
--           t_inicio_reparacion, t_restablecido, inicio_dispositivo, tipo_rotura, largo_afectado_m, presion_mca, usuarios_sin_servicio, sector,
--           riesgo, marcas[], causa_clase, causa, tercero_tipo, tercero_nombre, descripcion, fotos[{n, momento, ruta}]}
create function public.geoportal_redes_crear_dano(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp' as $f$
declare
  v_email text := tecnica.f_autorizar_captura(p_solicitante, 'danos_fallas'); d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_dano%rowtype; v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text;
  v_t_ini timestamptz; v_t_det timestamptz; v_t_rep timestamptz; v_t_res timestamptz; v_inicio timestamptz;
  v_lat numeric; v_lon numeric; v_fuera boolean; v_fotos jsonb := coalesce(p_datos -> 'fotos', '[]'::jsonb); v_n integer; v_f jsonb; v_ruta text; v_size bigint; v_mime text;
  v_ref jsonb := '[]'::jsonb; v_cons bigint; v_codigo text; v_tipo redes.tipos_dano%rowtype; v_marcas text[]; v_causa text; v_ter text; v_ter_nom text;
  v_desc text := nullif(btrim(coalesce(d ->> 'descripcion', '')), ''); v_max_bytes bigint := redes.f_param('max_bytes_foto_dano')::bigint;
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador del daño: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_dano where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'fuera_de_zona', v_prev.fuera_de_zona, 'repetido', true);
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

  -- fotos: el tamaño y el tipo se leen de Storage (nunca se le creen al celular)
  if jsonb_typeof(v_fotos) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n < redes.f_param('min_fotos_dano') or v_n > redes.f_param('max_fotos_dano') or v_n > (select fotos from redes.dano_preparaciones where dano_id = p_id) then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', redes.f_param('min_fotos_dano')::integer, redes.f_param('max_fotos_dano')::integer));
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
  -- auditoría sin el nombre del tercero ni la posición
  perform tecnica.f_auditar(v_email, 'redes_crear_dano', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'sistema', d ->> 'sistema', 'activo', v_act.codigo,
          'no_identificado', v_noid is not null, 'fotos', v_n, 'riesgo', d ->> 'riesgo'), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo,
                                    'fuera_de_zona', x.fuera_de_zona, 'respuesta_s', x.respuesta_s, 'reparacion_s', x.reparacion_s, 'total_s', x.total_s,
                                    'perdida_estado', x.perdida_estado, 'repetido', false) from redes.v_dano x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.danos where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_dano x where x.id = p_id);
  end if;
  perform tecnica.f_error('Una de las fotos ya está usada en otro daño');
  return null;
end $f$;

-- ---------- Minimapa ----------
-- Búsqueda por código (del geoportal o de la capa) o por el nombre visible del tipo; máximo 10. Sin GPS, o si el activo no aparece.
create function public.geoportal_redes_activo_buscar(p_solicitante text, p_texto text, p_sistema text default null, p_limite integer default 10)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
declare p record; v text := btrim(coalesce(p_texto, '')); v_lim integer := coalesce(p_limite, 10);
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if length(v) < 2 or length(v) > 60 then perform tecnica.f_error('Escriba de 2 a 60 caracteres'); end if;
  if p_sistema is not null and p_sistema not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Ese sistema no existe'); end if;
  if v_lim < 1 or v_lim > 10 then perform tecnica.f_error('Se piden de 1 a 10 activos'); end if;
  return jsonb_build_object('activos', coalesce((
    select jsonb_agg(redes.f_activo_corto(x.activo_id) || jsonb_build_object('sistema', x.sistema, 'lat', x.lat, 'lon', x.lon) order by x.rango, x.codigo)
      from (select m.activo_id, m.codigo, m.sistema,
                   round(ST_Y(case when GeometryType(m.geom) = 'POINT' then m.geom else ST_PointOnSurface(m.geom) end)::numeric, 6) as lat,
                   round(ST_X(case when GeometryType(m.geom) = 'POINT' then m.geom else ST_PointOnSurface(m.geom) end)::numeric, 6) as lon,
                   case when m.codigo = upper(v) or lower(m.codigo_anterior) = lower(v) then 0 else 1 end as rango
              from redes.activo_vigente_mat m
             where not m.retirado and not m.oculto and (p_sistema is null or m.sistema = p_sistema)
               and (m.codigo like upper(v) || '%' or lower(m.codigo_anterior) like lower(v) || '%')
             order by rango, m.codigo limit v_lim) x), '[]'::jsonb));
end $f$;

-- Un tramo y sus nodos (los dos extremos), para elegir el tramo o uno de sus nodos en el minimapa.
create function public.geoportal_redes_tramo_nodos(p_solicitante text, p_codigo text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
declare p record; v_id bigint; m redes.activo_vigente_mat%rowtype;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  v_id := redes.f_buscar_activo(p_codigo);
  select * into m from redes.activo_vigente_mat where activo_id = v_id;
  if GeometryType(m.geom) not in ('LINESTRING', 'MULTILINESTRING') then perform tecnica.f_error('Ese activo no es un tramo'); end if;
  return jsonb_build_object('tramo', redes.f_activo_corto(v_id) || jsonb_build_object('sistema', m.sistema, 'longitud_m', m.longitud_m, 'diametro_mm', m.diametro_mm),
    'nodos', coalesce((select jsonb_agg(jsonb_build_object('rol', x.rol, 'nombre', n.nombre_visible, 'lat', round(ST_Y(n.geom)::numeric, 6), 'lon', round(ST_X(n.geom)::numeric, 6),
                                                         'activo', case when n.activo_id is not null and exists (select 1 from redes.activo_vigente_mat a where a.activo_id = n.activo_id and not a.retirado)
                                                                        then redes.f_activo_corto(n.activo_id) end) order by x.o)
                         from redes.v_tramo_nodos_vigente tn
                         cross join lateral (values ('inicio', 1, tn.nodo_ini), ('fin', 2, tn.nodo_fin)) x(rol, o, nodo)
                         join redes.v_nodo_visible n on n.nodo_id = x.nodo
                        where tn.activo_id = v_id), '[]'::jsonb));
end $f$;

-- Tesela liviana del minimapa (perfil «mini», 01 §I): una sola red, desde el zoom mini_zoom_min; los accesorios desde mini_zoom_acc.
-- Atributos: código, prefijo, clase, forma (tramo o nodo) y si va punteado. Nada de material, edad ni origen. Devuelve la tesela MVT en base64.
create function public.geoportal_redes_mvt(p_solicitante text, p_z integer, p_x integer, p_y integer, p_sistema text)
returns text language plpgsql stable security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
declare p record; v_env geometry; v bytea;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p_sistema not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija acueducto o alcantarillado'); end if;
  if p_z is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < redes.f_param('mini_zoom_min') then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  select ST_AsMVT(t, 'red', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, m.codigo, m.prefijo, coalesce(m.clase, '') as clase,
           case when GeometryType(m.geom) = 'POINT' then 'nodo' else 'tramo' end as forma, m.punteado
      from redes.activo_vigente_mat m
     where m.sistema = p_sistema and not m.retirado and not m.oculto
       and m.geom && ST_Transform(v_env, 4326)
       and (m.prefijo <> 'ACC' or p_z >= redes.f_param('mini_zoom_acc'))) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $f$;

-- ---------- Reportes del bot (N-14) ----------
-- Entrada (interna; la función pública para n8n, con su credencial propia, va DESPUÉS de la fase 1). Idempotente por (canal, radicado).
-- NO recibe nombre ni teléfono: si vienen en el JSON, se rechaza.
create function redes.f_reporte_externo_recibir(p jsonb) returns uuid
language plpgsql set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $f$
declare v_id uuid;
begin
  if p ?| array['nombre', 'telefono', 'teléfono', 'celular', 'cedula', 'cédula', 'correo', 'email'] then
    perform tecnica.f_error('El reporte del bot no puede traer datos personales de quien reporta (se quedan en el Dell)');
  end if;
  select id into v_id from redes.reportes_externos where canal = p ->> 'canal' and radicado = p ->> 'radicado';
  if found then return v_id; end if;
  insert into redes.reportes_externos (radicado, canal, tipo_bot, lat, lon, direccion, descripcion, recibido_en)
  values (p ->> 'radicado', p ->> 'canal', p ->> 'tipo', (p ->> 'lat')::numeric, (p ->> 'lon')::numeric, p ->> 'direccion', p ->> 'descripcion',
          coalesce((p ->> 'recibido_en')::timestamptz, clock_timestamp()))
  returning id into v_id;
  insert into redes.reporte_externo_eventos (reporte_id, tipo, autor) values (v_id, 'recibido', 'bot:' || (p ->> 'canal'));
  return v_id;
end $f$;

-- Convertir un reporte del bot en daño o falla (supervisor o administrador; la bandeja va en el Corte 4).
-- p_datos: {clase, tipo, sistema, activo | no_identificado, riesgo, causa_clase?, motivo?}. El daño queda enlazado al radicado y toma
-- la ubicación (o la del activo, si el reporte solo trae dirección), la hora de recepción como detectado y la descripción del reporte.
create function public.geoportal_redes_reporte_convertir(p_solicitante text, p_reporte uuid, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare p record; r redes.v_reporte_externo%rowtype; d jsonb := coalesce(p_datos, '{}'::jsonb); v_tipo redes.tipos_dano%rowtype; v_act redes.activo_vigente_mat%rowtype;
        v_id uuid := gen_random_uuid(); v_cons bigint; v_codigo text; v_lat numeric; v_lon numeric; v_noid text; v_pto geometry;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p.perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador convierten reportes del bot' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('redes.reporte.' || p_reporte::text));
  select * into r from redes.v_reporte_externo where id = p_reporte;
  if not found then perform tecnica.f_error('No existe ese reporte', 'P0002'); end if;
  if r.ultimo_evento in ('convertido', 'descartado') then perform tecnica.f_error(format('Ese reporte ya está %s', r.ultimo_evento)); end if;
  select * into v_tipo from redes.tipos_dano where codigo = d ->> 'tipo' and activo;
  if not found or v_tipo.clase is distinct from d ->> 'clase' then perform tecnica.f_error('Elija qué pasó'); end if;
  if coalesce(d ->> 'sistema', '') not in ('acueducto', 'alcantarillado') or not ((d ->> 'sistema') = any (v_tipo.sistemas)) then perform tecnica.f_error('Elija un sistema que corresponda al tipo'); end if;
  if coalesce(d ->> 'riesgo', '') not in ('bajo', 'medio', 'alto') then perform tecnica.f_error('Elija el riesgo'); end if;
  if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado or v_act.sistema <> d ->> 'sistema' then perform tecnica.f_error('El activo no existe, está retirado o no es de ese sistema'); end if;
  else
    v_noid := coalesce(nullif(btrim(coalesce(d ->> 'no_identificado', '')), ''), 'Reporte del bot ' || r.radicado);
  end if;
  if r.lat is not null then v_lat := r.lat; v_lon := r.lon;
  elsif v_act.activo_id is not null then
    v_pto := case when GeometryType(v_act.geom) = 'POINT' then v_act.geom else ST_PointOnSurface(v_act.geom) end;
    v_lat := round(ST_Y(v_pto)::numeric, 6); v_lon := round(ST_X(v_pto)::numeric, 6);
  else perform tecnica.f_error('El reporte no trae ubicación: elija el activo para ubicar el daño');
  end if;
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'DAN' returning ultimo into v_cons;
  v_codigo := 'DAN-' || lpad(v_cons::text, 6, '0');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, no_ident_que_es, lat, lon, ubicacion_origen, fuera_de_zona, t_detectado,
         riesgo, causa_clase, descripcion, origen, reporte_externo_id, autor)
  values (v_id, v_codigo, v_tipo.clase, v_tipo.codigo, d ->> 'sistema', v_act.activo_id, v_noid, v_lat, v_lon, case when r.lat is not null then 'bot' else 'activo' end,
          v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max'),
          least(r.recibido_en, clock_timestamp()), d ->> 'riesgo', 'desconocida',
          left('Reporte del bot ' || r.radicado || ' (' || r.tipo_bot || ')' || coalesce(': ' || r.descripcion, '') || coalesce(' · ' || r.direccion, ''), 1000),
          'bot', p_reporte, p.email);
  insert into redes.reporte_externo_eventos (reporte_id, tipo, dano_id, motivo, autor)
  values (p_reporte, 'convertido', v_id, nullif(btrim(coalesce(d ->> 'motivo', '')), ''), p.email);
  perform tecnica.f_auditar(p.email, 'redes_reporte_convertir', r.radicado, jsonb_build_object('dano', v_codigo, 'tipo', v_tipo.codigo), null);
  return jsonb_build_object('reporte', r.radicado, 'dano_id', v_id, 'dano_codigo', v_codigo, 'estado_bot', 'en_atencion');
end $f$;

create function public.geoportal_redes_reporte_descartar(p_solicitante text, p_reporte uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare p record; r redes.v_reporte_externo%rowtype;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p.perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador descartan reportes del bot' using errcode = '42501'; end if;
  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo del descarte (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.reporte.' || p_reporte::text));
  select * into r from redes.v_reporte_externo where id = p_reporte;
  if not found then perform tecnica.f_error('No existe ese reporte', 'P0002'); end if;
  if r.ultimo_evento in ('convertido', 'descartado') then perform tecnica.f_error(format('Ese reporte ya está %s', r.ultimo_evento)); end if;
  insert into redes.reporte_externo_eventos (reporte_id, tipo, motivo, autor) values (p_reporte, 'descartado', btrim(p_motivo), p.email);
  perform tecnica.f_auditar(p.email, 'redes_reporte_descartar', r.radicado, jsonb_build_object('motivo', btrim(p_motivo)), null);
  return jsonb_build_object('reporte', r.radicado, 'estado_bot', 'descartado');
end $f$;
