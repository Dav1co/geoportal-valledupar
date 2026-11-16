-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 15 — PERMISO NUEVO ver_dashboard_redes (D-12): el supervisor de distribución.
-- ⚠ Toca las 4 funciones de permisos VIVAS, con el patrón exacto de ver_analisis_contrato (14-nov): su texto vivo + lo mínimo para el permiso nuevo.
--   · geoportal_puede: modo 'dashboard_redes'.   · geoportal_mis_permisos: 'dashboard_redes' y torre_b.
--   · geoportal_admin_permisos: 19 → 20 parámetros (p_dashboard_redes, con la compuerta de aislamiento como los demás permisos técnicos).
--   · geoportal_admin_listar: + la columna ver_dashboard_redes al final.
-- La guardia (10) exige la huella md5 viva de las 4; la reversa (90) las deja con su texto del 14-nov.
-- La columna nace en falso para todos: ningún marcado inicial (el administrador lo asigna en Administración).
-- =====================================================================
alter table public.geoportal_lista_blanca add column ver_dashboard_redes boolean not null default false;
comment on column public.geoportal_lista_blanca.ver_dashboard_redes is 'Técnica fase 1 (D-12): supervisor de distribución (Dashboard distribución, bandejas y edición de la ficha de redes salvo el origen). El administrador pasa siempre.';

create or replace function public.geoportal_puede(p_email text, p_modo text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((
    select case
      when lb.rol = 'admin' then true
      when p_modo = 'explorar' then lb.ver_explorar
      when p_modo = 'focalizacion' then lb.ver_focalizacion
      when p_modo = 'comercial' then lb.ver_comercial
      when p_modo = 'rutas' then lb.ver_rutas
      when p_modo = 'dashboard' then lb.ver_dashboard
      when p_modo = 'registro_tecnico' then lb.ver_registro_tecnico
      when p_modo = 'dashboard_tecnico' then lb.ver_dashboard_tecnico
      when p_modo = 'campo' then (lb.ver_campo or lb.ver_dashboard_campo)
      when p_modo = 'dashboard_campo' then lb.ver_dashboard_campo
      when p_modo = 'acta' then (lb.ver_acta or lb.ver_dashboard_acta)
      when p_modo = 'dashboard_acta' then lb.ver_dashboard_acta
      when p_modo = 'aseo' then (lb.ver_aseo or lb.ver_dashboard_aseo)          -- el supervisor de aseo también captura
      when p_modo = 'dashboard_aseo' then lb.ver_dashboard_aseo
      when p_modo = 'analisis_contrato' then lb.ver_analisis_contrato   -- Análisis de contrato (consulta con nombre y teléfono)
      when p_modo = 'dashboard_redes' then lb.ver_dashboard_redes       -- Técnica fase 1, Corte 4a: supervisor de distribución (D-12)
      else false
    end
    from public.geoportal_lista_blanca lb
    where lb.email = lower(p_email) and lb.activo
    limit 1), false);
$function$;

create or replace function public.geoportal_mis_permisos(p_email text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(
    (select jsonb_build_object(
       'rol', lb.rol, 'explorar', lb.ver_explorar, 'focalizacion', lb.ver_focalizacion, 'comercial', lb.ver_comercial,
       'rutas', lb.ver_rutas, 'dashboard', lb.ver_dashboard,
       'registro_tecnico', lb.ver_registro_tecnico, 'dashboard_tecnico', lb.ver_dashboard_tecnico,
       'dashboard_redes', (lb.rol = 'admin' or lb.ver_dashboard_redes),
       'campo', (lb.rol = 'admin' or lb.ver_campo or lb.ver_dashboard_campo),
       'dashboard_campo', (lb.rol = 'admin' or lb.ver_dashboard_campo),
       'acta', (lb.rol = 'admin' or lb.ver_acta or lb.ver_dashboard_acta),
       'dashboard_acta', (lb.rol = 'admin' or lb.ver_dashboard_acta),
       'aseo', (lb.rol = 'admin' or lb.ver_aseo or lb.ver_dashboard_aseo),
       'dashboard_aseo', (lb.rol = 'admin' or lb.ver_dashboard_aseo),
       'analisis_contrato', (lb.rol = 'admin' or lb.ver_analisis_contrato),
       'torre_a', (lb.rol = 'admin' or lb.ver_explorar or lb.ver_focalizacion or lb.ver_comercial or lb.ver_rutas or lb.ver_dashboard
                   or lb.ver_campo or lb.ver_dashboard_campo or lb.ver_acta or lb.ver_dashboard_acta or lb.ver_analisis_contrato),
       'torre_b', (lb.rol = 'admin' or lb.ver_registro_tecnico or lb.ver_dashboard_tecnico or lb.ver_dashboard_redes),
       'torre_c', (lb.rol = 'admin' or lb.ver_aseo or lb.ver_dashboard_aseo))
     from public.geoportal_lista_blanca lb
     where lb.email = lower(p_email) and lb.activo limit 1),
    jsonb_build_object('rol','consulta','explorar',true,'focalizacion',false,'comercial',false,'rutas',false,'dashboard',false,
                       'registro_tecnico',false,'dashboard_tecnico',false,'dashboard_redes',false,'campo',false,'dashboard_campo',false,'acta',false,'dashboard_acta',false,
                       'aseo',false,'dashboard_aseo',false,'analisis_contrato',false,'torre_a',false,'torre_b',false,'torre_c',false));
$function$;


drop function public.geoportal_admin_permisos(text, text, boolean, boolean, boolean, boolean, text, text, boolean, boolean, boolean, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean);

create function public.geoportal_admin_permisos(p_solicitante text, p_email text, p_explorar boolean, p_focalizacion boolean, p_comercial boolean, p_rutas boolean, p_horario text, p_dias text, p_dashboard boolean default false, p_registro_tecnico boolean default null, p_dashboard_tecnico boolean default null, p_ip text default null, p_campo boolean default null, p_dashboard_campo boolean default null, p_acta boolean default null, p_dashboard_acta boolean default null, p_aseo boolean default null, p_dashboard_aseo boolean default null, p_analisis_contrato boolean default null, p_dashboard_redes boolean default null)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_antes jsonb; v_despues jsonb;
begin
  if not public.geoportal_es_admin(p_solicitante) then raise exception 'No autorizado'; end if;
  if p_horario not in ('laboral','extendido','sin_restriccion') then raise exception 'Horario inválido'; end if;
  if p_dias not in ('habiles','todos') then raise exception 'Días inválidos'; end if;
  select to_jsonb(lb) - 'creado_en' - 'creado_por' into v_antes from public.geoportal_lista_blanca lb where lb.email = lower(p_email);
  if v_antes is not null and v_antes->>'rol' <> 'admin' and not public.geoportal_aislamiento_verificado()
     and ((p_registro_tecnico is true and (v_antes->>'ver_registro_tecnico')::boolean is not true)
       or (p_dashboard_tecnico is true and (v_antes->>'ver_dashboard_tecnico')::boolean is not true)
       or (p_dashboard_redes is true and (v_antes->>'ver_dashboard_redes')::boolean is not true)
       or (p_campo is true and (v_antes->>'ver_campo')::boolean is not true)
       or (p_dashboard_campo is true and (v_antes->>'ver_dashboard_campo')::boolean is not true)
       or (p_acta is true and (v_antes->>'ver_acta')::boolean is not true)
       or (p_dashboard_acta is true and (v_antes->>'ver_dashboard_acta')::boolean is not true)
       or (p_aseo is true and (v_antes->>'ver_aseo')::boolean is not true)
       or (p_dashboard_aseo is true and (v_antes->>'ver_dashboard_aseo')::boolean is not true)) then
    raise exception 'Antes de dar permisos técnicos, de campo, de acta o de aseo debe verificarse el bloqueo de las funciones comerciales (aislamiento)';
  end if;
  update public.geoportal_lista_blanca
  set ver_explorar = p_explorar, ver_focalizacion = p_focalizacion, ver_comercial = p_comercial, ver_rutas = p_rutas, ver_dashboard = p_dashboard,
      ver_registro_tecnico  = coalesce(p_registro_tecnico, ver_registro_tecnico),
      ver_dashboard_tecnico = coalesce(p_dashboard_tecnico, ver_dashboard_tecnico),
      ver_campo             = coalesce(p_campo, ver_campo),
      ver_dashboard_campo   = coalesce(p_dashboard_campo, ver_dashboard_campo),
      ver_acta              = coalesce(p_acta, ver_acta),
      ver_dashboard_acta    = coalesce(p_dashboard_acta, ver_dashboard_acta),
      ver_aseo              = coalesce(p_aseo, ver_aseo),
      ver_dashboard_aseo    = coalesce(p_dashboard_aseo, ver_dashboard_aseo),
      ver_analisis_contrato = coalesce(p_analisis_contrato, ver_analisis_contrato),
      ver_dashboard_redes   = coalesce(p_dashboard_redes, ver_dashboard_redes),
      horario = p_horario, dias = p_dias
  where email = lower(p_email);
  if not found then return false; end if;
  select to_jsonb(lb) - 'creado_en' - 'creado_por' into v_despues from public.geoportal_lista_blanca lb where lb.email = lower(p_email);
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
  values (lower(p_solicitante), 'admin_cambiar_permisos', lower(p_email), jsonb_build_object('antes', v_antes, 'despues', v_despues), p_ip);
  return true;
end;
$function$;


drop function public.geoportal_admin_listar(text);

create function public.geoportal_admin_listar(p_solicitante text)
 returns table(email text, nombre text, rol text, activo boolean, creado_en timestamp with time zone, ver_explorar boolean, ver_focalizacion boolean, ver_comercial boolean, ver_rutas boolean, ver_dashboard boolean, horario text, dias text, ver_registro_tecnico boolean, ver_dashboard_tecnico boolean, ver_campo boolean, ver_dashboard_campo boolean, ver_acta boolean, ver_dashboard_acta boolean, ver_aseo boolean, ver_dashboard_aseo boolean, ver_analisis_contrato boolean, ver_dashboard_redes boolean)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select lb.email, lb.nombre, lb.rol, lb.activo, lb.creado_en, lb.ver_explorar, lb.ver_focalizacion, lb.ver_comercial, lb.ver_rutas, lb.ver_dashboard,
         lb.horario, lb.dias, lb.ver_registro_tecnico, lb.ver_dashboard_tecnico, lb.ver_campo, lb.ver_dashboard_campo, lb.ver_acta, lb.ver_dashboard_acta, lb.ver_aseo, lb.ver_dashboard_aseo, lb.ver_analisis_contrato, lb.ver_dashboard_redes
  from public.geoportal_lista_blanca lb
  where public.geoportal_es_admin(p_solicitante)
  order by lb.creado_en;
$function$;

revoke all on function public.geoportal_admin_permisos(text, text, boolean, boolean, boolean, boolean, text, text, boolean, boolean, boolean, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_admin_listar(text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_puede(text, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_mis_permisos(text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_admin_permisos(text, text, boolean, boolean, boolean, boolean, text, text, boolean, boolean, boolean, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) to service_role;
grant execute on function public.geoportal_admin_listar(text) to service_role;
grant execute on function public.geoportal_puede(text, text) to service_role;
grant execute on function public.geoportal_mis_permisos(text) to service_role;
