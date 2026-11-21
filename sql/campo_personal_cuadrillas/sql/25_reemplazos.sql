-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 25 — REEMPLAZOS (misma firma; la respuesta de hoy no cambia, solo se le agregan campos)
-- public.geoportal_campo_personal (f8a83b02…) y public.geoportal_campo_historial_personal (e82377f5…). La reversa vuelve a los textos publicados.
-- public.geoportal_campo_personal_cambiar (c0302a7b…) NO se toca: la sigue usando la Edge publicada; la nueva ruta usa geoportal_campo_personal_fijar (26).
-- =====================================================================

create or replace function public.geoportal_campo_personal(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
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
end $$;

-- Historial: las mismas filas de hoy más los tipos nuevos, con valor_codigo y valor_nombre (y «clave» única: p:<id> de persona, c:<id> de cuadrilla).
-- Con cuadrilla_id: los eventos de esa cuadrilla (persona nula, tipo_evento cuadrilla_<tipo>) más las entradas y salidas de personas; sin paginar (los 500 más nuevos).
create or replace function public.geoportal_campo_historial_personal(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_p text; v_desp bigint; v_lim integer; v_cuad bigint; v_filas jsonb; v_n integer;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_p := nullif(lower(btrim(coalesce(f ->> 'persona', ''))), ''); v_desp := nullif(f ->> 'despues_de', '')::bigint;
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 100), 1), 500);
    v_cuad := nullif(f ->> 'cuadrilla_id', '')::bigint;
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  if v_cuad is not null then
    if not exists (select 1 from campo.cuadrillas q where q.id = v_cuad) then perform campo.f_error('Esa cuadrilla no existe'); end if;
    with ce as (
      select e.creado_en, jsonb_build_object('clave', 'c:' || e.id, 'id', e.id, 'persona', null, 'nombre', null, 'tipo_evento', 'cuadrilla_' || e.tipo_evento,
               'cuadrilla', jsonb_build_object('id', q.id, 'nombre', q.nombre),
               'formulario', null, 'formulario_nombre', null, 'cargo', null,
               'valor_codigo', case when e.tipo_evento in ('agregar_actividad', 'quitar_actividad') then e.valor end,
               'valor_nombre', case when e.tipo_evento in ('agregar_actividad', 'quitar_actividad') then coalesce((select a.nombre from campo.actividades a where a.codigo = e.valor), e.valor) else e.valor end,
               'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en, 'vigente', null) as fila
        from campo.cuadrilla_eventos e join campo.cuadrillas q on q.id = e.cuadrilla_id where e.cuadrilla_id = v_cuad
    ), pe as (
      select x.*, lag(x.valor) over (partition by x.persona order by x.id) as anterior from campo.personal_eventos x where x.tipo_evento = 'fijar_cuadrilla'
    ), pm as (
      select pe.creado_en, jsonb_build_object('clave', 'p:' || pe.id, 'id', pe.id, 'persona', pe.persona, 'nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = pe.persona),
               'tipo_evento', pe.tipo_evento, 'cuadrilla', jsonb_build_object('id', q.id, 'nombre', q.nombre),
               'formulario', null, 'formulario_nombre', null, 'cargo', null,
               'valor_codigo', pe.valor, 'valor_nombre', (select c.nombre from campo.cuadrillas c where c.id = pe.valor::bigint),
               'entra', pe.valor = v_cuad::text, 'motivo', pe.motivo, 'autor', pe.autor, 'creado_en', pe.creado_en, 'vigente', null) as fila
        from pe join campo.cuadrillas q on q.id = v_cuad where pe.valor = v_cuad::text or pe.anterior = v_cuad::text
    ), todo as (select * from ce union all select * from pm order by 1 desc limit 500)
    select coalesce(jsonb_agg(fila order by creado_en desc), '[]'::jsonb) into v_filas from todo;
    return jsonb_build_object('eventos', v_filas, 'siguiente', null);
  end if;
  with ev as (
    select e.*, e.id = max(e.id) over (partition by e.persona, case when e.tipo_evento in ('asignar_formulario', 'quitar_formulario') then 'f:' || e.formulario
                                                                    when e.tipo_evento in ('asignar_actividad', 'quitar_actividad') then 'a:' || e.valor
                                                                    else e.tipo_evento end) as vigente
      from campo.personal_eventos e where v_p is null or e.persona = v_p
  ), pag as (select * from ev where v_desp is null or ev.id < v_desp order by ev.id desc limit v_lim + 1)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'persona', p.persona, 'nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = p.persona),
           'tipo_evento', p.tipo_evento, 'formulario', p.formulario,
           'formulario_nombre', case when p.formulario is null then null else coalesce((select x.nombre from campo.f_formularios_personal() x where x.clave = p.formulario),
                                                                                     (select t.nombre from campo.tipos_reporte t where 'tipo:' || t.codigo = p.formulario), p.formulario) end,
           'cargo', p.cargo, 'motivo', p.motivo, 'autor', p.autor, 'creado_en', p.creado_en, 'vigente', p.vigente,
           'clave', 'p:' || p.id, 'valor_codigo', p.valor,
           'valor_nombre', case p.tipo_evento when 'fijar_area' then (select a.nombre from campo.areas_comercial a where a.codigo = p.valor)
                                              when 'fijar_cuadrilla' then (select q.nombre from campo.cuadrillas q where q.id = p.valor::bigint)
                                              when 'asignar_actividad' then (select a.nombre from campo.actividades a where a.codigo = p.valor)
                                              when 'quitar_actividad' then (select a.nombre from campo.actividades a where a.codigo = p.valor) end) order by p.id desc) filter (where rn <= v_lim), '[]'::jsonb)
    into v_n, v_filas from (select pag.*, row_number() over (order by pag.id desc) as rn from pag) p;
  return jsonb_build_object('eventos', v_filas, 'siguiente', case when v_n > v_lim then (select min((x ->> 'id')::bigint) from jsonb_array_elements(v_filas) x) end);
end $$;
