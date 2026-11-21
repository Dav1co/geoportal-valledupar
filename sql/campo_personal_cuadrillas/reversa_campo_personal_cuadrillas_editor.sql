-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · REVERSA (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 90 — REVERSA
-- Vuelve geoportal_campo_personal y geoportal_campo_historial_personal a los textos publicados (f8a83b02…, e82377f5…) y quita las RPC y funciones nuevas.
-- Nada se borra: si ya hay datos (cuadrillas, eventos nuevos de Personal o cambios de catálogo hechos por personas), las tablas, la columna «valor»
-- y los CHECK nuevos SE CONSERVAN (la migración se puede volver a aplicar encima). Solo si no hay datos se retiran tablas, columna y CHECK.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_campo_cuadrillas(text,jsonb,text)') is null then
    raise exception 'Personal y cuadrillas de Comercial no está aplicado (no existe geoportal_campo_cuadrillas): no hay nada que revertir';
  end if;
end $$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_personal(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_buscar text;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  v_buscar := nullif(btrim(coalesce(f ->> 'buscar', '')), '');
  return jsonb_build_object(
    'puede_editar', public.geoportal_es_admin(v_email),
    'formularios', (select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'nombre', x.nombre, 'grupo', x.grupo) order by x.orden, x.clave), '[]'::jsonb) from campo.f_formularios_personal() x),
    'personas', (select coalesce(jsonb_agg(p order by p ->> 'nombre_orden', p ->> 'email'), '[]'::jsonb) from (
      select jsonb_build_object('email', lb.email, 'nombre', nullif(btrim(lb.nombre), ''), 'nombre_orden', lower(coalesce(nullif(btrim(lb.nombre), ''), lb.email)),
               'perfil', case when coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_dashboard_acta, false) then 'supervisor' else 'operario' end,
               'permisos', jsonb_build_object('campo', coalesce(lb.ver_campo, false), 'dashboard_campo', coalesce(lb.ver_dashboard_campo, false),
                                              'acta', coalesce(lb.ver_acta, false), 'dashboard_acta', coalesce(lb.ver_dashboard_acta, false)),
               'cargo', campo.f_cargo_vigente(lb.email),
               'formularios', to_jsonb(campo.f_formularios_asignados(lb.email)),
               'sin_asignacion', cardinality(campo.f_formularios_asignados(lb.email)) = 0,
               'ultimo_cambio', (select max(e.creado_en) from campo.personal_eventos e where e.persona = lb.email)) as p
        from public.geoportal_lista_blanca lb
       where lb.activo and lb.rol <> 'admin'
         and (coalesce(lb.ver_campo, false) or coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_acta, false) or coalesce(lb.ver_dashboard_acta, false))
         and (v_buscar is null or lb.email ilike '%' || v_buscar || '%' or coalesce(lb.nombre, '') ilike '%' || v_buscar || '%')) s));
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_historial_personal(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_p text; v_desp bigint; v_lim integer; v_filas jsonb; v_n integer;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_p := nullif(lower(btrim(coalesce(f ->> 'persona', ''))), ''); v_desp := nullif(f ->> 'despues_de', '')::bigint;
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 100), 1), 500);
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  with ev as (
    select e.*, e.id = max(e.id) over (partition by e.persona, coalesce(e.formulario, 'cargo')) as vigente
      from campo.personal_eventos e where v_p is null or e.persona = v_p
  ), pag as (select * from ev where v_desp is null or ev.id < v_desp order by ev.id desc limit v_lim + 1)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'persona', p.persona, 'nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = p.persona),
           'tipo_evento', p.tipo_evento, 'formulario', p.formulario,
           'formulario_nombre', case when p.formulario is null then null else coalesce((select x.nombre from campo.f_formularios_personal() x where x.clave = p.formulario),
                                                                                     (select t.nombre from campo.tipos_reporte t where 'tipo:' || t.codigo = p.formulario), p.formulario) end,
           'cargo', p.cargo, 'motivo', p.motivo, 'autor', p.autor, 'creado_en', p.creado_en, 'vigente', p.vigente) order by p.id desc) filter (where rn <= v_lim), '[]'::jsonb)
    into v_n, v_filas from (select pag.*, row_number() over (order by pag.id desc) as rn from pag) p;
  return jsonb_build_object('eventos', v_filas, 'siguiente', case when v_n > v_lim then (select min((x ->> 'id')::bigint) from jsonb_array_elements(v_filas) x) end);
end $function$;

drop function public.geoportal_campo_personal_fijar(text, text, text, jsonb, text);
drop function public.geoportal_campo_cuadrillas(text, jsonb, text);
drop function public.geoportal_campo_cuadrilla_cambiar(text, jsonb, text);
drop function public.geoportal_campo_catalogos(text, text);
drop function public.geoportal_campo_catalogo_cambiar(text, jsonb, text);
drop function public.geoportal_campo_personal_actividad(text, text, text);
drop function campo.f_quien_puede(text);
drop function campo.f_actividades_persona(text);
drop function campo.f_miembros_cuadrillas();
drop function campo.f_cuadrilla_actividades(bigint);
drop function campo.f_actividades_propias(text);
drop function campo.f_cuadrilla_vigente(text);
drop function campo.f_area_vigente(text);
drop function campo.f_persona_comercial(text);
drop function campo.f_codigo_desde_nombre(text);
drop function campo.f_motivo_personal(text, boolean);

do $$
begin
  if exists (select 1 from campo.personal_eventos where tipo_evento in ('fijar_area', 'fijar_cuadrilla', 'asignar_actividad', 'quitar_actividad'))
     or exists (select 1 from campo.cuadrillas) or exists (select 1 from campo.catalogo_eventos where autor <> 'migracion@geoportal') then
    raise notice 'Hay datos de cuadrillas, actividades o áreas: las tablas, la columna valor y los CHECK nuevos se conservan (nada se borra)';
  else
    drop table campo.cuadrilla_eventos;
    drop table campo.cuadrillas;
    drop table campo.catalogo_eventos;
    drop table campo.actividades;
    drop table campo.areas_comercial;
    drop function campo.f_no_borrar_catalogo();
    alter table campo.personal_eventos drop constraint personal_ev_ck;
    alter table campo.personal_eventos drop constraint personal_eventos_tipo_evento_check;
    drop index campo.personal_eventos_tipo_valor_idx;
    alter table campo.personal_eventos drop column valor;
    alter table campo.personal_eventos add constraint personal_eventos_tipo_evento_check check (tipo_evento in ('fijar_cargo', 'asignar_formulario', 'quitar_formulario'));
    alter table campo.personal_eventos add constraint personal_ev_ck check (((tipo_evento = 'fijar_cargo') = (cargo is not null)) and ((tipo_evento = 'fijar_cargo') = (formulario is null))
                                     and (tipo_evento <> 'quitar_formulario' or motivo is not null));
  end if;
end $$;

commit;
