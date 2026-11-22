-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · REVERSA (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · 90 — REVERSA
-- Vuelve las dos RPC a los textos publicados el 21-nov (fc362a28…, 7028ce40…) y quita la función interna nueva.
-- No hay tablas ni datos nuevos: los cambios de cargo y área que hayan hecho los supervisores quedan como eventos (nada se borra).
-- =====================================================================
do $$
begin
  if to_regprocedure('campo.f_supervisor_comercial(text)') is null then
    raise exception 'El cambio de cargo y área por el supervisor no está aplicado (no existe campo.f_supervisor_comercial): no hay nada que revertir';
  end if;
  if md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)'))) is distinct from '8baf8468c6a9178df700cd94830cdd41'
     or md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal(text,jsonb,text)'))) is distinct from '8298374d98bd0cfedb7f205e838ccf65' then
    raise exception 'geoportal_campo_personal_fijar o geoportal_campo_personal cambiaron después de este paquete: la reversa no las pisa; deténgase y avise';
  end if;
end $$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_personal_fijar(p_solicitante text, p_persona text, p_tipo text, p_datos jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_personal(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_buscar text; v_admin boolean; v_sup boolean;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  v_buscar := nullif(btrim(coalesce(f ->> 'buscar', '')), '');
  v_admin := public.geoportal_es_admin(v_email);
  v_sup := v_admin or public.geoportal_puede(v_email, 'dashboard_campo');
  return jsonb_build_object(
    'puede_editar', v_admin,
    'yo', v_email,
    'puede', jsonb_build_object('cargo', v_admin, 'area', v_admin, 'cuadrilla', v_sup, 'cuadrillas', v_sup, 'actividades', v_sup, 'formularios', v_sup, 'catalogos', v_admin),
    'formularios', (select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'nombre', x.nombre, 'grupo', x.grupo) order by x.orden, x.clave), '[]'::jsonb) from campo.f_formularios_personal() x),
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre) order by a.orden, a.codigo), '[]'::jsonb) from campo.areas_comercial a where a.activa),
    'cuadrillas', (select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nombre', q.nombre) order by lower(q.nombre), q.id), '[]'::jsonb) from campo.cuadrillas q where q.activa),
    'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre) order by a.orden, a.codigo), '[]'::jsonb) from campo.actividades a where a.activa),
    'personas', (select coalesce(jsonb_agg(p order by p ->> 'nombre_orden', p ->> 'email'), '[]'::jsonb) from (
      select jsonb_build_object('email', lb.email, 'nombre', nullif(btrim(lb.nombre), ''), 'nombre_orden', lower(coalesce(nullif(btrim(lb.nombre), ''), lb.email)),
               'perfil', case when coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_dashboard_acta, false) then 'supervisor' else 'operario' end,
               'permisos', jsonb_build_object('campo', coalesce(lb.ver_campo, false), 'dashboard_campo', coalesce(lb.ver_dashboard_campo, false),
                                              'acta', coalesce(lb.ver_acta, false), 'dashboard_acta', coalesce(lb.ver_dashboard_acta, false)),
               'cargo', campo.f_cargo_vigente(lb.email),
               'formularios', to_jsonb(campo.f_formularios_asignados(lb.email)),
               'sin_asignacion', cardinality(campo.f_formularios_asignados(lb.email)) = 0,
               'ultimo_cambio', (select max(e.creado_en) from campo.personal_eventos e where e.persona = lb.email),
               'propia', lb.email = v_email,
               'area', (select jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'activa', a.activa) from campo.areas_comercial a where a.codigo = campo.f_area_vigente(lb.email)),
               'cuadrilla', (select jsonb_build_object('id', q.id, 'nombre', q.nombre, 'activa', q.activa) from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(lb.email)),
               'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'nombre', coalesce(a.nombre, x.codigo), 'activa', coalesce(a.activa, false), 'origen', x.origen)
                                                         order by a.orden, x.codigo), '[]'::jsonb)
                                 from campo.f_actividades_persona(lb.email) x left join campo.actividades a on a.codigo = x.codigo)) as p
        from public.geoportal_lista_blanca lb
       where lb.activo and lb.rol <> 'admin'
         and (coalesce(lb.ver_campo, false) or coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_acta, false) or coalesce(lb.ver_dashboard_acta, false))
         and (v_buscar is null or lb.email ilike '%' || v_buscar || '%' or coalesce(lb.nombre, '') ilike '%' || v_buscar || '%')) s));
end $function$;

-- DROP (por qué y alcance): campo.f_supervisor_comercial(text) la creó este paquete y, con las dos RPC ya devueltas a su texto publicado, nadie la usa.
-- Alcance: SOLO esa función (una firma); no toca tablas, datos ni otras funciones.
drop function campo.f_supervisor_comercial(text);

commit;
