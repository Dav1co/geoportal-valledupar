-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 26 — RPC NUEVAS (solo service_role; el solicitante es el correo del token, lo pone la Edge)
-- Quién edita (patrón de Técnica, cortes 4b y 5a): el supervisor de campo cuadrillas, miembros, actividades y formularios; el administrador además área,
-- cargo y catálogos; el supervisor de actas solo ve. Nadie cambia su propia ficha. Mensajes con HINT msg_usuario (los ve el usuario); 55000 → 409.
-- =====================================================================

create function public.geoportal_campo_personal_fijar(p_solicitante text, p_persona text, p_tipo text, p_datos jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; v_admin boolean; d jsonb := coalesce(p_datos, '{}'::jsonb); v_p text := lower(btrim(coalesce(p_persona, '')));
        v_f text; v_c text; v_m text; v_val text; v_cuad bigint; v_ant bigint; v_q campo.cuadrillas; v_a campo.actividades; v_ar campo.areas_comercial; v_id bigint;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  v_admin := public.geoportal_es_admin(v_email);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del cambio no tienen el formato esperado'); end if;
  if p_tipo is null or p_tipo not in ('fijar_cargo', 'fijar_area', 'fijar_cuadrilla', 'asignar_formulario', 'quitar_formulario', 'asignar_actividad', 'quitar_actividad') then
    perform campo.f_error('El cambio debe ser fijar_cargo, fijar_area, fijar_cuadrilla, asignar_formulario, quitar_formulario, asignar_actividad o quitar_actividad');
  end if;
  if p_tipo in ('fijar_cargo', 'fijar_area') and not v_admin then raise exception 'Solo el administrador puede hacerlo' using errcode = '42501'; end if;
  if not campo.f_persona_comercial(v_p) then perform campo.f_error('Esa persona no tiene acceso activo a Formularios de campo ni al acta'); end if;
  if v_p = v_email then perform campo.f_error('No puede cambiar su propia ficha'); end if;
  perform pg_advisory_xact_lock(hashtext('campo_personal:' || v_p));
  v_m := campo.f_motivo_personal(d ->> 'motivo', p_tipo in ('quitar_formulario', 'quitar_actividad'));
  if p_tipo = 'fijar_cargo' then
    v_c := nullif(btrim(coalesce(d ->> 'cargo', '')), '');
    if v_c is null or length(v_c) < 2 or length(v_c) > 80 then perform campo.f_error('El cargo debe tener entre 2 y 80 caracteres'); end if;
    if v_c is not distinct from campo.f_cargo_vigente(v_p) then perform campo.f_error('Ese ya es el cargo vigente', '55000'); end if;
  elsif p_tipo = 'fijar_area' then
    select * into v_ar from campo.areas_comercial a where a.codigo = nullif(btrim(coalesce(d ->> 'area', '')), '');
    if v_ar.codigo is null then perform campo.f_error('Esa área no existe'); end if;
    if not v_ar.activa then perform campo.f_error('Esa área está desactivada'); end if;
    if v_ar.codigo is not distinct from campo.f_area_vigente(v_p) then perform campo.f_error('Ya tiene esa área', '55000'); end if;
    v_val := v_ar.codigo;
  elsif p_tipo = 'fijar_cuadrilla' then
    begin v_cuad := nullif(d ->> 'cuadrilla_id', '')::bigint; exception when others then perform campo.f_error('La cuadrilla no es válida'); end;
    v_ant := campo.f_cuadrilla_vigente(v_p);
    if v_cuad is not null then
      perform pg_advisory_xact_lock(hashtext('campo_cuadrilla:' || v_cuad));
      select * into v_q from campo.cuadrillas q where q.id = v_cuad;
      if v_q.id is null then perform campo.f_error('Esa cuadrilla no existe'); end if;
      if not v_q.activa then perform campo.f_error('Esa cuadrilla está desactivada'); end if;
    end if;
    if v_cuad is not distinct from v_ant then
      perform campo.f_error(case when v_cuad is null then 'No está en ninguna cuadrilla' else 'Ya está en esa cuadrilla' end, '55000');
    end if;
    if v_ant is not null and v_m is null then perform campo.f_error('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
    v_val := v_cuad::text;
  elsif p_tipo in ('asignar_formulario', 'quitar_formulario') then
    v_f := nullif(btrim(coalesce(d ->> 'formulario', '')), '');
    if v_f is null then perform campo.f_error('Indique el formulario'); end if;
    if p_tipo = 'asignar_formulario' then
      if not exists (select 1 from campo.f_formularios_personal() x where x.clave = v_f) then perform campo.f_error('Ese formulario no existe o está desactivado'); end if;
      if v_f = any (campo.f_formularios_asignados(v_p)) then perform campo.f_error('Ya tiene asignado ese formulario', '55000'); end if;
    elsif not (v_f = any (campo.f_formularios_asignados(v_p))) then perform campo.f_error('No tiene asignado ese formulario', '55000');
    end if;
  else
    select * into v_a from campo.actividades a where a.codigo = nullif(btrim(coalesce(d ->> 'actividad', '')), '');
    if v_a.codigo is null then perform campo.f_error('Esa actividad no existe'); end if;
    if p_tipo = 'asignar_actividad' then
      if not v_a.activa then perform campo.f_error('Esa actividad está desactivada'); end if;
      if v_a.codigo = any (campo.f_actividades_propias(v_p)) then perform campo.f_error('Ya tiene esa actividad', '55000'); end if;
    elsif not (v_a.codigo = any (campo.f_actividades_propias(v_p))) then
      if exists (select 1 from campo.f_actividades_persona(v_p) x where x.codigo = v_a.codigo) then
        perform campo.f_error('Esa actividad viene de la cuadrilla ' || (select q.nombre from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(v_p)) || ': se quita en la cuadrilla', '55000');
      end if;
      perform campo.f_error('No tiene esa actividad', '55000');
    end if;
    v_val := v_a.codigo;
  end if;
  insert into campo.personal_eventos (persona, tipo_evento, formulario, cargo, valor, motivo, autor) values (v_p, p_tipo, v_f, v_c, v_val, v_m, v_email) returning id into v_id;
  perform campo.f_auditar(v_email, 'campo_personal_' || p_tipo, v_p, jsonb_build_object('evento', v_id, 'formulario', v_f, 'valor', v_val, 'cargo', v_c is not null), p_ip);
  return jsonb_build_object('id', v_id, 'cambio', true);
end $$;

create function public.geoportal_campo_cuadrillas(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_todas boolean;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  if f ? 'incluir_inactivas' and jsonb_typeof(f -> 'incluir_inactivas') not in ('boolean', 'null') then perform campo.f_error('incluir_inactivas debe ser sí o no'); end if;
  v_todas := coalesce((f ->> 'incluir_inactivas')::boolean, false);
  return jsonb_build_object('cuadrillas', (
    with m as (select * from campo.f_miembros_cuadrillas())
    select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nombre', q.nombre, 'activa', q.activa, 'creada_en', q.creado_en, 'autor', q.autor,
             'n_miembros', (select count(*) from m where m.cuadrilla_id = q.id),
             'miembros', (select coalesce(jsonb_agg(jsonb_build_object('email', m.persona, 'nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = m.persona))
                                                    order by m.persona), '[]'::jsonb) from m where m.cuadrilla_id = q.id),
             'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'nombre', coalesce(a.nombre, x.codigo), 'activa', coalesce(a.activa, false)) order by a.orden, x.codigo), '[]'::jsonb)
                               from unnest(campo.f_cuadrilla_actividades(q.id)) as x(codigo) left join campo.actividades a on a.codigo = x.codigo))
             order by q.activa desc, lower(q.nombre), q.id), '[]'::jsonb)
      from campo.cuadrillas q where q.activa or v_todas));
end $$;

create function public.geoportal_campo_cuadrilla_cambiar(p_solicitante text, p_datos jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; d jsonb := coalesce(p_datos, '{}'::jsonb); v_tipo text; v_id bigint; v_q campo.cuadrillas; v_nombre text; v_m text; v_a campo.actividades; v_n integer; v_ev bigint; v_val text;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del cambio no tienen el formato esperado'); end if;
  v_tipo := d ->> 'tipo';
  if v_tipo is null or v_tipo not in ('crear', 'renombrar', 'desactivar', 'activar', 'agregar_actividad', 'quitar_actividad') then
    perform campo.f_error('El cambio debe ser crear, renombrar, desactivar, activar, agregar_actividad o quitar_actividad');
  end if;
  v_m := campo.f_motivo_personal(d ->> 'motivo', v_tipo in ('desactivar', 'quitar_actividad'));
  if v_tipo in ('crear', 'renombrar') then
    v_nombre := regexp_replace(btrim(coalesce(d ->> 'nombre', '')), '\s+', ' ', 'g');
    if length(v_nombre) < 2 or length(v_nombre) > 60 then perform campo.f_error('El nombre de la cuadrilla debe tener entre 2 y 60 caracteres'); end if;
  end if;
  if v_tipo = 'crear' then
    perform pg_advisory_xact_lock(hashtext('campo_cuadrillas'));
    if exists (select 1 from campo.cuadrillas q where lower(regexp_replace(q.nombre, '\s', '', 'g')) = lower(regexp_replace(v_nombre, '\s', '', 'g'))) then
      perform campo.f_error('Ya existe una cuadrilla con ese nombre', '55000');
    end if;
    insert into campo.cuadrillas (nombre, autor) values (v_nombre, v_email) returning id into v_id;
    insert into campo.cuadrilla_eventos (cuadrilla_id, tipo_evento, valor, autor) values (v_id, 'crear', v_nombre, v_email) returning id into v_ev;
    perform campo.f_auditar(v_email, 'campo_cuadrilla_crear', v_id::text, jsonb_build_object('evento', v_ev), p_ip);
    return jsonb_build_object('id', v_id, 'cambio', true);
  end if;
  begin v_id := (d ->> 'cuadrilla_id')::bigint; exception when others then perform campo.f_error('La cuadrilla no es válida'); end;
  if v_id is null then perform campo.f_error('Indique la cuadrilla'); end if;
  perform pg_advisory_xact_lock(hashtext('campo_cuadrillas'));
  perform pg_advisory_xact_lock(hashtext('campo_cuadrilla:' || v_id));
  select * into v_q from campo.cuadrillas q where q.id = v_id;
  if v_q.id is null then perform campo.f_error('Esa cuadrilla no existe'); end if;
  if v_tipo = 'renombrar' then
    if v_nombre = v_q.nombre then perform campo.f_error('La cuadrilla ya tiene ese nombre', '55000'); end if;
    if exists (select 1 from campo.cuadrillas q where q.id <> v_id and lower(regexp_replace(q.nombre, '\s', '', 'g')) = lower(regexp_replace(v_nombre, '\s', '', 'g'))) then
      perform campo.f_error('Ya existe una cuadrilla con ese nombre', '55000');
    end if;
    update campo.cuadrillas set nombre = v_nombre where id = v_id;
    v_val := v_nombre;
  elsif v_tipo = 'desactivar' then
    if not v_q.activa then perform campo.f_error('La cuadrilla ya está desactivada', '55000'); end if;
    select count(*) into v_n from campo.f_miembros_cuadrillas() m where m.cuadrilla_id = v_id;
    if v_n > 0 then
      perform campo.f_error(case when v_n = 1 then 'La cuadrilla tiene 1 miembro: sáquelo antes de desactivarla' else 'La cuadrilla tiene ' || v_n || ' miembros: sáquelos antes de desactivarla' end, '55000');
    end if;
    update campo.cuadrillas set activa = false where id = v_id;
  elsif v_tipo = 'activar' then
    if v_q.activa then perform campo.f_error('La cuadrilla ya está activa', '55000'); end if;
    update campo.cuadrillas set activa = true where id = v_id;
  else
    select * into v_a from campo.actividades a where a.codigo = nullif(btrim(coalesce(d ->> 'actividad', '')), '');
    if v_a.codigo is null then perform campo.f_error('Esa actividad no existe'); end if;
    if v_tipo = 'agregar_actividad' then
      if not v_q.activa then perform campo.f_error('Esa cuadrilla está desactivada'); end if;
      if not v_a.activa then perform campo.f_error('Esa actividad está desactivada'); end if;
      if v_a.codigo = any (campo.f_cuadrilla_actividades(v_id)) then perform campo.f_error('La cuadrilla ya tiene esa actividad', '55000'); end if;
    elsif not (v_a.codigo = any (campo.f_cuadrilla_actividades(v_id))) then perform campo.f_error('La cuadrilla no tiene esa actividad', '55000');
    end if;
    v_val := v_a.codigo;
  end if;
  insert into campo.cuadrilla_eventos (cuadrilla_id, tipo_evento, valor, motivo, autor) values (v_id, v_tipo, v_val, v_m, v_email) returning id into v_ev;
  perform campo.f_auditar(v_email, 'campo_cuadrilla_' || v_tipo, v_id::text, jsonb_build_object('evento', v_ev, 'valor', v_val), p_ip);
  return jsonb_build_object('id', v_id, 'cambio', true);
end $$;

create function public.geoportal_campo_catalogos(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  return jsonb_build_object(
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'activa', a.activa, 'orden', a.orden) order by a.orden, a.codigo), '[]'::jsonb) from campo.areas_comercial a),
    'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'activa', a.activa, 'orden', a.orden) order by a.orden, a.codigo), '[]'::jsonb) from campo.actividades a));
end $$;

create function public.geoportal_campo_catalogo_cambiar(p_solicitante text, p_datos jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; d jsonb := coalesce(p_datos, '{}'::jsonb); v_cat text; v_tipo text; v_cod text; v_nombre text; v_m text; v_activa boolean; v_actual text; v_ev bigint; v_que text;
begin
  v_email := campo.f_autorizar_admin(p_solicitante);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del cambio no tienen el formato esperado'); end if;
  v_cat := d ->> 'catalogo'; v_tipo := d ->> 'tipo';
  if v_cat is null or v_cat not in ('area', 'actividad') then perform campo.f_error('El catálogo debe ser area o actividad'); end if;
  if v_tipo is null or v_tipo not in ('crear', 'renombrar', 'desactivar', 'activar') then perform campo.f_error('El cambio debe ser crear, renombrar, desactivar o activar'); end if;
  v_que := case v_cat when 'area' then 'un área' else 'una actividad' end;
  v_m := campo.f_motivo_personal(d ->> 'motivo', v_tipo = 'desactivar');
  perform pg_advisory_xact_lock(hashtext('campo_catalogo:' || v_cat));
  if v_tipo in ('crear', 'renombrar') then
    v_nombre := regexp_replace(btrim(coalesce(d ->> 'nombre', '')), '\s+', ' ', 'g');
    if length(v_nombre) < 2 or length(v_nombre) > 60 then perform campo.f_error('El nombre debe tener entre 2 y 60 caracteres'); end if;
  end if;
  if v_tipo = 'crear' then
    v_cod := campo.f_codigo_desde_nombre(v_nombre);
    if v_cod !~ '^[a-z][a-z0-9_]{1,39}$' then perform campo.f_error('El nombre debe empezar con una letra'); end if;
    if (v_cat = 'area' and exists (select 1 from campo.areas_comercial a where lower(a.nombre) = lower(v_nombre) or a.codigo = v_cod))
       or (v_cat = 'actividad' and exists (select 1 from campo.actividades a where lower(a.nombre) = lower(v_nombre) or a.codigo = v_cod)) then
      perform campo.f_error('Ya existe ' || v_que || ' con ese nombre', '55000');
    end if;
    if v_cat = 'area' then
      insert into campo.areas_comercial (codigo, nombre, orden, autor) select v_cod, v_nombre, coalesce(max(orden), 0) + 1, v_email from campo.areas_comercial;
    else
      insert into campo.actividades (codigo, nombre, orden, autor) select v_cod, v_nombre, coalesce(max(orden), 0) + 1, v_email from campo.actividades;
    end if;
  else
    v_cod := nullif(btrim(coalesce(d ->> 'codigo', '')), '');
    if v_cat = 'area' then select a.nombre, a.activa into v_actual, v_activa from campo.areas_comercial a where a.codigo = v_cod;
    else select a.nombre, a.activa into v_actual, v_activa from campo.actividades a where a.codigo = v_cod; end if;
    if v_actual is null then perform campo.f_error('No existe ' || v_que || ' con ese código'); end if;
    if v_tipo = 'renombrar' then
      if v_nombre = v_actual then perform campo.f_error('Ya tiene ese nombre', '55000'); end if;
      if (v_cat = 'area' and exists (select 1 from campo.areas_comercial a where a.codigo <> v_cod and lower(a.nombre) = lower(v_nombre)))
         or (v_cat = 'actividad' and exists (select 1 from campo.actividades a where a.codigo <> v_cod and lower(a.nombre) = lower(v_nombre))) then
        perform campo.f_error('Ya existe ' || v_que || ' con ese nombre', '55000');
      end if;
    elsif v_tipo = 'desactivar' and not v_activa then perform campo.f_error('Ya está desactivada', '55000');
    elsif v_tipo = 'activar' and v_activa then perform campo.f_error('Ya está activa', '55000');
    end if;
    if v_cat = 'area' then
      update campo.areas_comercial set nombre = coalesce(v_nombre, nombre), activa = case v_tipo when 'desactivar' then false when 'activar' then true else activa end where codigo = v_cod;
    else
      update campo.actividades set nombre = coalesce(v_nombre, nombre), activa = case v_tipo when 'desactivar' then false when 'activar' then true else activa end where codigo = v_cod;
    end if;
  end if;
  insert into campo.catalogo_eventos (catalogo, codigo, tipo_evento, nombre, motivo, autor) values (v_cat, v_cod, v_tipo, v_nombre, v_m, v_email) returning id into v_ev;
  perform campo.f_auditar(v_email, 'campo_catalogo_' || v_cat || '_' || v_tipo, v_cod, jsonb_build_object('evento', v_ev), p_ip);
  return jsonb_build_object('codigo', v_cod, 'cambio', true);
end $$;

create function public.geoportal_campo_personal_actividad(p_solicitante text, p_actividad text, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; v_a campo.actividades;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  select * into v_a from campo.actividades a where a.codigo = nullif(btrim(coalesce(p_actividad, '')), '');
  if v_a.codigo is null then perform campo.f_error('Esa actividad no existe'); end if;
  return jsonb_build_object(
    'actividad', jsonb_build_object('codigo', v_a.codigo, 'nombre', v_a.nombre, 'activa', v_a.activa),
    'personas', (select coalesce(jsonb_agg(jsonb_build_object('email', x.persona, 'nombre', nullif(btrim(lb.nombre), ''),
                                                              'cuadrilla', (select jsonb_build_object('id', q.id, 'nombre', q.nombre) from campo.cuadrillas q where q.id = x.cuadrilla_id),
                                                              'origen', x.origen) order by lower(coalesce(nullif(btrim(lb.nombre), ''), x.persona)), x.persona), '[]'::jsonb)
                   from campo.f_quien_puede(v_a.codigo) x left join public.geoportal_lista_blanca lb on lb.email = x.persona));
end $$;
