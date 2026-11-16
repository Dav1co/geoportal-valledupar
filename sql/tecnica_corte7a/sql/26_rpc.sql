-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 26 — FUNCIONES NUEVAS DE QUÍMICOS (planta; §29)
--   Supervisor de planta y administrador (tecnica.f_autorizar_supervision): catálogo y saldo, historial, preparar la subida del PDF de la ficha técnica,
--   crear un químico, cambiar su dosis óptima / «de potabilización» / ficha / activo, inventario inicial, ajuste y la comparación de esperado contra usado.
--   Captura (tecnica.f_autorizar_captura con 'entrada_quimicos' o 'uso_quimicos'): formulario, entrada (t o kg) y uso (guarda la dosis óptima vigente).
--   El operador NO ve el saldo. Las rutas de Storage no salen al navegador: la Edge las cambia por URL firmadas.
-- =====================================================================
create function tecnica.f_qparam(p_clave text) returns numeric language sql stable set search_path = tecnica, pg_temp as $$
  select valor from tecnica.quimico_parametros where clave = p_clave $$;

create function tecnica.f_quimico_por_codigo(p_codigo text) returns tecnica.quimicos language plpgsql stable set search_path = tecnica, pg_temp as $$
declare q tecnica.quimicos;
begin
  select * into q from tecnica.quimicos where codigo = lower(btrim(coalesce(p_codigo, ''))) and codigo <> 'otro';
  if not found then perform tecnica.f_error('Ese químico no existe', 'P0002'); end if;
  return q;
end $$;

-- El PDF de la ficha: preparado por esta persona y ya subido a Storage (PDF, tamaño tope). Devuelve sus bytes.
create function tecnica.f_ficha_subida(p_ruta text, p_email text) returns bigint language plpgsql stable security definer set search_path = tecnica, storage, pg_temp as $$
declare v_b bigint; v_m text;
begin
  if p_ruta is null or not exists (select 1 from tecnica.quimico_ficha_preparaciones where ruta = p_ruta and autor = p_email) then
    perform tecnica.f_error('Suba primero el PDF de la ficha técnica');
  end if;
  select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_b, v_m from storage.objects o where o.bucket_id = 'tecnica-evidencias' and o.name = p_ruta;
  if not found then perform tecnica.f_error('El PDF de la ficha técnica no terminó de subir: intente de nuevo'); end if;
  if v_m is distinct from 'application/pdf' then perform tecnica.f_error('La ficha técnica debe ser un PDF'); end if;
  if v_b > tecnica.f_qparam('max_bytes_ficha') then perform tecnica.f_error('El PDF de la ficha técnica pasa del tamaño permitido'); end if;
  return v_b;
end $$;

-- Dosis óptima vigente de un químico en un momento (la del último evento hasta entonces).
create function tecnica.f_dosis_optima_en(p_quimico bigint, p_hasta timestamptz) returns numeric language sql stable set search_path = tecnica, pg_temp as $$
  select e.dosis_optima_ppm from tecnica.quimico_ficha_eventos e where e.quimico_id = p_quimico and e.dosis_optima_ppm is not null and e.creado_en <= p_hasta order by e.id desc limit 1 $$;

-- ---------- Catálogo y saldo (supervisor) ----------
create function public.geoportal_tec_quimicos_catalogo(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante);
begin
  return jsonb_build_object(
    'quimicos', coalesce((select jsonb_agg(jsonb_build_object('codigo', v.codigo, 'nombre', v.nombre, 'rol', v.rol, 'activo', v.activo, 'dosis_optima_ppm', v.dosis_optima_ppm,
                                 'potabilizacion', v.potabilizacion, 'ficha_ruta', v.ficha_ruta, 'ficha_en', v.ficha_en,
                                 'saldo_kg', s.saldo_kg, 'inventario_dia', s.inventario_dia,
                                 'ultimo_movimiento', (select max(m.registrado_en) from tecnica.quimico_movimientos m where m.quimico_id = v.quimico_id))
                               order by v.activo desc, v.potabilizacion desc, v.nombre)
                            from tecnica.v_quimico_vigente v join tecnica.v_quimico_saldo s on s.quimico_id = v.quimico_id), '[]'::jsonb),
    'parametros', (select jsonb_object_agg(clave, valor) from tecnica.quimico_parametros),
    'puede_editar', true);
end $$;

create function public.geoportal_tec_quimico_historial(p_solicitante text, p_codigo text) returns jsonb
language plpgsql stable security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo);
begin
  return jsonb_build_object('codigo', q.codigo, 'nombre', q.nombre,
    'eventos', coalesce((select jsonb_agg(jsonb_build_object('tipo', e.tipo, 'dosis_optima_ppm', e.dosis_optima_ppm, 'potabilizacion', e.potabilizacion, 'activo', e.activo,
                                 'ficha_ruta', e.ficha_ruta, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en) order by e.id desc)
                           from tecnica.quimico_ficha_eventos e where e.quimico_id = q.id), '[]'::jsonb),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'dia', m.dia, 'cantidad', m.cantidad, 'unidad', m.unidad, 'cantidad_kg', m.cantidad_kg,
                                 'planta', (select p.codigo from tecnica.plantas p where p.id = m.planta_id), 'para_que', m.para_que, 'dosis_optima_ppm', m.dosis_optima_ppm,
                                 'proveedor', m.proveedor, 'remision', m.remision, 'lote', m.lote_fabricante, 'vence', m.vence, 'motivo', m.motivo, 'autor', m.autor,
                                 'registrado_en', m.registrado_en) order by m.id desc)
                               from (select * from tecnica.quimico_movimientos m where m.quimico_id = q.id order by m.id desc limit 100) m), '[]'::jsonb));
end $$;

-- ---------- PDF de la ficha técnica: la ruta donde se sube (la Edge firma la subida) ----------
create function public.geoportal_tec_quimico_ficha_preparar(p_solicitante text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_ruta text;
begin
  v_ruta := 'quimicos/' || to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM') || '/' || gen_random_uuid() || '.pdf';
  insert into tecnica.quimico_ficha_preparaciones (ruta, autor) values (v_ruta, v_email);
  return jsonb_build_object('ruta', v_ruta, 'max_bytes', tecnica.f_qparam('max_bytes_ficha'), 'tipo_mime', 'application/pdf');
end $$;

-- ---------- Crear un químico (§29): nombre (identidad), rol, de potabilización, dosis óptima (obligatoria si es de potabilización) y el PDF (obligatorio) ----------
create function public.geoportal_tec_quimico_crear(p_solicitante text, p_nombre text, p_rol text, p_potabilizacion boolean, p_dosis_optima numeric, p_ficha_ruta text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_nom text := regexp_replace(btrim(coalesce(p_nombre, '')), '\s+', ' ', 'g');
        v_base text; v_cod text; v_n integer := 1; v_id bigint; v_bytes bigint; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if length(v_nom) < 2 or length(v_nom) > 100 then perform tecnica.f_error('Escriba el nombre del químico (2 a 100 caracteres)'); end if;
  if coalesce(p_rol, '') not in ('coagulante', 'desinfectante', 'auxiliar') then perform tecnica.f_error('Elija para qué sirve: coagulante, desinfectante u otro uso (auxiliar)'); end if;
  if p_potabilizacion is null then perform tecnica.f_error('Diga si es de potabilización'); end if;
  if p_potabilizacion and p_dosis_optima is null then perform tecnica.f_error('Un químico de potabilización lleva su dosis óptima (ppm)'); end if;
  if p_dosis_optima is not null and (p_dosis_optima <= 0 or p_dosis_optima > 1000) then perform tecnica.f_error('La dosis óptima va de más de 0 a 1.000 ppm'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  if exists (select 1 from tecnica.quimicos where lower(translate(nombre, 'áéíóúÁÉÍÓÚñÑ', 'aeiouAEIOUnN')) = lower(translate(v_nom, 'áéíóúÁÉÍÓÚñÑ', 'aeiouAEIOUnN'))) then
    perform tecnica.f_error('Ya hay un químico con ese nombre (si está desactivado, actívelo en vez de crear otro)', '55000');
  end if;
  v_bytes := tecnica.f_ficha_subida(p_ficha_ruta, v_email);
  perform pg_advisory_xact_lock(hashtext('tecnica.quimicos.alta'));
  v_base := left(trim(both '_' from regexp_replace(lower(translate(v_nom, 'áéíóúÁÉÍÓÚñÑüÜ', 'aeiouAEIOUnNuU')), '[^a-z0-9]+', '_', 'g')), 26);
  if v_base !~ '^[a-z]' then v_base := 'q_' || v_base; end if;
  v_cod := v_base;
  while exists (select 1 from tecnica.quimicos where codigo = v_cod) loop v_n := v_n + 1; v_cod := v_base || '_' || v_n; end loop;
  insert into tecnica.quimicos (codigo, nombre, rol, pide_nombre) values (v_cod, v_nom, p_rol, false) returning id into v_id;
  insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, dosis_optima_ppm, potabilizacion, activo, ficha_ruta, ficha_bytes, motivo, autor)
  values (v_id, 'alta', p_dosis_optima, p_potabilizacion, true, p_ficha_ruta, v_bytes, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'tec_quimico_crear', v_cod, jsonb_build_object('nombre', v_nom, 'rol', p_rol, 'potabilizacion', p_potabilizacion, 'dosis_optima_ppm', p_dosis_optima), null);
  return jsonb_build_object('codigo', v_cod, 'nombre', v_nom);
end $$;

-- ---------- Cambiar lo que sí cambia (§29), cada cosa con su evento y el mismo motivo. La dosis óptima exige un PDF nuevo. ----------
create function public.geoportal_tec_quimico_fijar(p_solicitante text, p_codigo text, p_cambios jsonb, p_ficha_ruta text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo); v tecnica.v_quimico_vigente%rowtype;
        c jsonb := coalesce(p_cambios, '{}'::jsonb); v_mot text := btrim(coalesce(p_motivo, '')); v_bytes bigint; v_hechos text[] := '{}'; v_dosis numeric; v_ficha_usada boolean := false;
begin
  if jsonb_typeof(c) <> 'object' or exists (select 1 from jsonb_object_keys(c) k where k not in ('dosis_optima_ppm', 'potabilizacion', 'activo')) then
    perform tecnica.f_error('Esos cambios no corresponden: solo dosis óptima, de potabilización y activo (la identidad no se cambia)');
  end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  perform pg_advisory_xact_lock(hashtext('tecnica.quimico.' || q.codigo));
  select * into v from tecnica.v_quimico_vigente where quimico_id = q.id;
  if p_ficha_ruta is not null then v_bytes := tecnica.f_ficha_subida(p_ficha_ruta, v_email); end if;
  if c ? 'dosis_optima_ppm' then
    if jsonb_typeof(c -> 'dosis_optima_ppm') <> 'number' then perform tecnica.f_error('La dosis óptima es un número en ppm'); end if;
    v_dosis := (c ->> 'dosis_optima_ppm')::numeric;
    if v_dosis <= 0 or v_dosis > 1000 then perform tecnica.f_error('La dosis óptima va de más de 0 a 1.000 ppm'); end if;
    if v_dosis is distinct from v.dosis_optima_ppm then
      if p_ficha_ruta is null then perform tecnica.f_error('Para cambiar la dosis óptima suba el PDF de la ficha técnica'); end if;
      insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, dosis_optima_ppm, ficha_ruta, ficha_bytes, motivo, autor) values (q.id, 'dosis_optima', v_dosis, p_ficha_ruta, v_bytes, v_mot, v_email);
      v_hechos := v_hechos || 'dosis_optima'::text; v_ficha_usada := true;
    end if;
  end if;
  if c ? 'potabilizacion' then
    if jsonb_typeof(c -> 'potabilizacion') <> 'boolean' then perform tecnica.f_error('«De potabilización» es sí o no'); end if;
    if (c ->> 'potabilizacion')::boolean is distinct from v.potabilizacion then
      if (c ->> 'potabilizacion')::boolean and coalesce(v_dosis, v.dosis_optima_ppm) is null then perform tecnica.f_error('Para marcarlo de potabilización fije también su dosis óptima'); end if;
      insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, potabilizacion, motivo, autor) values (q.id, 'potabilizacion', (c ->> 'potabilizacion')::boolean, v_mot, v_email);
      v_hechos := v_hechos || 'potabilizacion'::text;
    end if;
  end if;
  if c ? 'activo' then
    if jsonb_typeof(c -> 'activo') <> 'boolean' then perform tecnica.f_error('Activo es sí o no'); end if;
    if (c ->> 'activo')::boolean is distinct from q.activo then
      update tecnica.quimicos set activo = (c ->> 'activo')::boolean where id = q.id;
      insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, activo, motivo, autor) values (q.id, 'activo', (c ->> 'activo')::boolean, v_mot, v_email);
      v_hechos := v_hechos || 'activo'::text;
    end if;
  end if;
  if p_ficha_ruta is not null and not v_ficha_usada then      -- solo una versión nueva de la ficha (sin cambiar la dosis)
    insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, ficha_ruta, ficha_bytes, motivo, autor) values (q.id, 'ficha', p_ficha_ruta, v_bytes, v_mot, v_email);
    v_hechos := v_hechos || 'ficha'::text;
  end if;
  if cardinality(v_hechos) = 0 then perform tecnica.f_error('No hay cambios que guardar'); end if;
  perform tecnica.f_auditar(v_email, 'tec_quimico_fijar', q.codigo, jsonb_build_object('cambios', to_jsonb(v_hechos), 'nuevo', c, 'motivo', v_mot), null);
  return jsonb_build_object('codigo', q.codigo, 'cambios', to_jsonb(v_hechos));
end $$;

-- ---------- Inventario inicial y ajuste (supervisor, con motivo) ----------
create function public.geoportal_tec_quimico_inventario(p_solicitante text, p_codigo text, p_cantidad numeric, p_unidad text, p_corte date, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo); v_id bigint;
        v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
begin
  if p_cantidad is null or p_cantidad < 0 or p_cantidad > 1000000 then perform tecnica.f_error('La cantidad contada va de 0 a 1.000.000'); end if;
  if coalesce(p_unidad, '') not in ('kg', 't') then perform tecnica.f_error('La unidad es kg o toneladas'); end if;
  if p_corte is null or p_corte > v_hoy or p_corte < v_hoy - 31 then perform tecnica.f_error('La fecha del conteo es de hoy o de hasta 31 días atrás'); end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más): por ejemplo, «conteo físico de la bodega»'); end if;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor)
  values ('inventario_inicial', q.id, p_cantidad, p_unidad, case p_unidad when 't' then p_cantidad * 1000 else p_cantidad end, p_corte, btrim(p_motivo), v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_inventario', q.codigo, jsonb_build_object('kg', case p_unidad when 't' then p_cantidad * 1000 else p_cantidad end, 'corte', p_corte), null);
  return jsonb_build_object('movimiento_id', v_id, 'saldo_kg', (select saldo_kg from tecnica.v_quimico_saldo where quimico_id = q.id));
end $$;

create function public.geoportal_tec_quimico_ajuste(p_solicitante text, p_codigo text, p_kg numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo); v_id bigint;
begin
  if p_kg is null or p_kg = 0 or abs(p_kg) > 1000000 then perform tecnica.f_error('El ajuste es un número de kg distinto de 0 (negativo si falta)'); end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then perform tecnica.f_error('Escriba el motivo del ajuste (10 caracteres o más)'); end if;
  if not exists (select 1 from tecnica.quimico_movimientos where quimico_id = q.id and tipo = 'inventario_inicial') then
    perform tecnica.f_error('Primero cargue el inventario inicial de este químico', '55000');
  end if;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor)
  values ('ajuste', q.id, abs(p_kg), 'kg', p_kg, (clock_timestamp() at time zone 'America/Bogota')::date, btrim(p_motivo), v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_ajuste', q.codigo, jsonb_build_object('kg', p_kg), null);
  return jsonb_build_object('movimiento_id', v_id, 'saldo_kg', (select saldo_kg from tecnica.v_quimico_saldo where quimico_id = q.id));
end $$;

-- ---------- Captura: formulario, entrada y uso (las pantallas del operador llegan en el 7b) ----------
create function public.geoportal_tec_quimicos_formulario(p_solicitante text, p_formulario text) returns jsonb
language plpgsql stable security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text;
begin
  if coalesce(p_formulario, '') not in ('entrada_quimicos', 'uso_quimicos') then perform tecnica.f_error('Ese formulario no es de químicos'); end if;
  v_email := tecnica.f_autorizar_captura(p_solicitante, p_formulario);
  return jsonb_build_object('formulario', p_formulario, 'hoy', (clock_timestamp() at time zone 'America/Bogota')::date,
    'dias_atras', tecnica.f_qparam(case p_formulario when 'uso_quimicos' then 'dias_atras_uso' else 'dias_atras_entrada' end),
    'quimicos', coalesce((select jsonb_agg(jsonb_build_object('codigo', v.codigo, 'nombre', v.nombre, 'potabilizacion', v.potabilizacion) order by v.potabilizacion desc, v.nombre)
                            from tecnica.v_quimico_vigente v where v.activo), '[]'::jsonb),
    'plantas', coalesce((select jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre) order by p.nombre) from tecnica.plantas p where p.activa), '[]'::jsonb),
    'para_que', case when p_formulario = 'uso_quimicos' then '["dosificacion", "limpieza", "otro"]'::jsonb end);
end $$;

create function tecnica.f_dia_movimiento(p_dia date, p_dias_atras numeric) returns date language plpgsql stable set search_path = tecnica, pg_temp as $$
declare v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
begin
  if p_dia is null then return v_hoy; end if;
  if p_dia > v_hoy then perform tecnica.f_error('El día no puede ser futuro'); end if;
  if p_dia < v_hoy - p_dias_atras::integer then perform tecnica.f_error(format('Se registra hasta %s días atrás', p_dias_atras::integer)); end if;
  return p_dia;
end $$;

-- Entrada: se recibe en toneladas (o kg) y se guarda en kg. Reintento con la misma clave: devuelve lo guardado.
create function public.geoportal_tec_quimico_entrada(p_solicitante text, p_datos jsonb, p_clave text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'entrada_quimicos'); d jsonb := coalesce(p_datos, '{}'::jsonb); q tecnica.quimicos; v_id bigint;
        v_cant numeric; v_vence date; m tecnica.quimico_movimientos%rowtype;
begin
  if p_clave is not null then
    select * into m from tecnica.quimico_movimientos where clave_envio = p_clave;
    if found then
      if m.autor <> v_email then perform tecnica.f_error('Esa clave de envío no es suya'); end if;
      return jsonb_build_object('movimiento_id', m.id, 'cantidad_kg', m.cantidad_kg, 'repetido', true);
    end if;
  end if;
  q := tecnica.f_quimico_por_codigo(d ->> 'quimico');
  if not q.activo then perform tecnica.f_error('Ese químico está desactivado'); end if;
  if jsonb_typeof(d -> 'cantidad') <> 'number' then perform tecnica.f_error('Escriba la cantidad recibida'); end if;
  v_cant := (d ->> 'cantidad')::numeric;
  if v_cant <= 0 or v_cant > 1000000 then perform tecnica.f_error('La cantidad recibida debe ser mayor que 0'); end if;
  if coalesce(d ->> 'unidad', '') not in ('t', 'kg') then perform tecnica.f_error('La unidad es toneladas o kg'); end if;
  begin v_vence := (d ->> 'vence')::date; exception when others then perform tecnica.f_error('La fecha de vencimiento no es válida'); end;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, lote_fabricante, vence, autor, clave_envio)
  values ('entrada', q.id, v_cant, d ->> 'unidad', case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end,
          tecnica.f_dia_movimiento((d ->> 'dia')::date, tecnica.f_qparam('dias_atras_entrada')),
          nullif(btrim(d ->> 'proveedor'), ''), nullif(btrim(d ->> 'remision'), ''), nullif(btrim(d ->> 'lote'), ''), v_vence, v_email, p_clave)
  returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_entrada', q.codigo, jsonb_build_object('movimiento_id', v_id), null);
  return jsonb_build_object('movimiento_id', v_id, 'cantidad_kg', case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end, 'repetido', false);
end $$;

-- Uso: en kg (o t), con la planta (obligatoria si es para dosificar) y para qué. Guarda la dosis óptima vigente (§29: la comparación no cambia hacia atrás).
create function public.geoportal_tec_quimico_uso(p_solicitante text, p_datos jsonb, p_clave text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'uso_quimicos'); d jsonb := coalesce(p_datos, '{}'::jsonb); q tecnica.quimicos; v_id bigint;
        v_cant numeric; v_planta bigint; v_dosis numeric; m tecnica.quimico_movimientos%rowtype;
begin
  if p_clave is not null then
    select * into m from tecnica.quimico_movimientos where clave_envio = p_clave;
    if found then
      if m.autor <> v_email then perform tecnica.f_error('Esa clave de envío no es suya'); end if;
      return jsonb_build_object('movimiento_id', m.id, 'cantidad_kg', m.cantidad_kg, 'dosis_optima_ppm', m.dosis_optima_ppm, 'repetido', true);
    end if;
  end if;
  q := tecnica.f_quimico_por_codigo(d ->> 'quimico');
  if not q.activo then perform tecnica.f_error('Ese químico está desactivado'); end if;
  if coalesce(d ->> 'para_que', '') not in ('dosificacion', 'limpieza', 'otro') then perform tecnica.f_error('Diga para qué se usó: dosificación, limpieza u otro'); end if;
  if jsonb_typeof(d -> 'cantidad') <> 'number' then perform tecnica.f_error('Escriba la cantidad usada'); end if;
  v_cant := (d ->> 'cantidad')::numeric;
  if v_cant <= 0 or v_cant > 1000000 then perform tecnica.f_error('La cantidad usada debe ser mayor que 0'); end if;
  if coalesce(d ->> 'unidad', 'kg') not in ('t', 'kg') then perform tecnica.f_error('La unidad es kg o toneladas'); end if;
  if nullif(d ->> 'planta', '') is not null then
    select id into v_planta from tecnica.plantas where codigo = d ->> 'planta' and activa;
    if v_planta is null then perform tecnica.f_error('Esa planta no existe o está inactiva'); end if;
  elsif d ->> 'para_que' = 'dosificacion' then
    perform tecnica.f_error('Para dosificar, elija la planta');
  end if;
  select dosis_optima_ppm into v_dosis from tecnica.v_quimico_vigente where quimico_id = q.id;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, planta_id, para_que, cantidad, unidad, cantidad_kg, dia, dosis_optima_ppm, autor, clave_envio)
  values ('uso', q.id, v_planta, d ->> 'para_que', v_cant, coalesce(d ->> 'unidad', 'kg'), - (case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end),
          tecnica.f_dia_movimiento((d ->> 'dia')::date, tecnica.f_qparam('dias_atras_uso')), v_dosis, v_email, p_clave)
  returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_uso', q.codigo, jsonb_build_object('movimiento_id', v_id), null);
  return jsonb_build_object('movimiento_id', v_id, 'cantidad_kg', -(case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end), 'dosis_optima_ppm', v_dosis, 'repetido', false);
end $$;

-- ---------- Esperado contra usado (supervisor), por planta, día y químico de potabilización ----------
-- Volumen del día = promedio del caudal de ingreso Qi (L/s, Entrada, sin excluidos) × 86,4 (m³ por L/s en un día).
-- Esperado (kg) = dosis óptima (ppm = g/m³) × volumen / 1.000. La dosis es la que guardaron los usos de ese día (§29: no cambia hacia atrás); sin usos, la vigente ese día.
-- Usado (kg) = los usos «dosificación» de ese químico en esa planta y ese día. La marca sale si se aparta más de desvio_pct. Solo marca: no rechaza nada.
create function public.geoportal_tec_quimicos_comparacion(p_solicitante text, p_desde date, p_hasta date) returns jsonb
language plpgsql stable security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        v_desde date := coalesce(p_desde, v_hoy - 13); v_hasta date := coalesce(p_hasta, v_hoy); v_pct numeric := tecnica.f_qparam('desvio_pct'); v_on boolean := tecnica.f_qparam('marca_esperado_usado') = 1;
begin
  if v_desde > v_hasta or v_hasta > v_hoy or v_hasta - v_desde > 92 then perform tecnica.f_error('El rango de fechas es de hasta 3 meses y hasta hoy'); end if;
  return jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'desvio_pct', v_pct, 'marca_activa', v_on,
    'filas', coalesce((
      select jsonb_agg(jsonb_build_object('dia', x.dia, 'planta', x.planta, 'planta_nombre', x.planta_nombre, 'quimico', x.codigo, 'quimico_nombre', x.nombre,
               'qi_lps', round(x.qi, 1), 'volumen_m3', round(x.qi * 86.4), 'dosis_optima_ppm', x.dosis,
               'esperado_kg', round(x.dosis * x.qi * 86.4 / 1000, 1), 'usado_kg', round(x.usado, 1),
               'desvio_pct', case when x.dosis * x.qi > 0 then round((x.usado - x.dosis * x.qi * 86.4 / 1000) / (x.dosis * x.qi * 86.4 / 1000) * 100, 1) end,
               'marca', v_on and x.dosis * x.qi > 0 and abs(x.usado - x.dosis * x.qi * 86.4 / 1000) > (x.dosis * x.qi * 86.4 / 1000) * v_pct / 100)
             order by x.dia desc, x.planta, x.codigo)
        from (select d.dia, p.codigo as planta, p.nombre as planta_nombre, v.codigo, v.nombre, qi.qi,
                     coalesce((select m.dosis_optima_ppm from tecnica.quimico_movimientos m where m.tipo = 'uso' and m.para_que = 'dosificacion' and m.quimico_id = v.quimico_id
                                and m.planta_id = p.id and m.dia = d.dia and m.dosis_optima_ppm is not null order by m.id desc limit 1),
                              tecnica.f_dosis_optima_en(v.quimico_id, ((d.dia + 1)::timestamp at time zone 'America/Bogota'))) as dosis,
                     coalesce((select -sum(m.cantidad_kg) from tecnica.quimico_movimientos m where m.tipo = 'uso' and m.para_que = 'dosificacion' and m.quimico_id = v.quimico_id
                                and m.planta_id = p.id and m.dia = d.dia), 0) as usado
                from generate_series(v_desde, v_hasta, interval '1 day') d0(t) cross join lateral (select d0.t::date as dia) d
                cross join tecnica.plantas p
                cross join tecnica.v_quimico_vigente v
                cross join lateral (select avg(r.valor) as qi from tecnica.v_registros_estado r
                                     where r.formulario::text = 'entrada' and r.planta_id = p.id and r.fecha_muestra = d.dia and not r.excluido
                                       and r.variable_id = (select id from tecnica.variables where codigo = 'caudal_qi')) qi
               where p.activa and v.potabilizacion and qi.qi is not null) x
       where x.dosis is not null or x.usado > 0), '[]'::jsonb));
end $$;
