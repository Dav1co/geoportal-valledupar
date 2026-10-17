-- =====================================================================
-- 44_horario_sin_restriccion.sql · tercera opcion de horario: 'sin_restriccion'
-- ---------------------------------------------------------------------
-- Aplicado el 2026-10-16 con el rol propietario. No cambia datos: ningun usuario se reasigna aqui.
-- Valor nuevo de public.geoportal_lista_blanca.horario: 'sin_restriccion' (rotulo en pantalla: «Sin restriccion horaria»).
--   geoportal_estado_acceso: despues de dominio, usuario activo, rol admin, pausa y regla de dias, 'sin_restriccion' omite SOLO la
--     validacion de horas. Sigue sujeto a la pausa de emergencia y a dias = 'habiles'. La ventana real (07:00) no cambia.
--   geoportal_admin_permisos: 'sin_restriccion' entra en la lista permitida de horario (mismo mensaje de error para otros valores).
-- Las funciones son create or replace: conservan el ACL (postgres y service_role), SECURITY DEFINER y search_path = public.
-- No se tocan _shared/auth.ts, geoportal-admin ni las Edge Functions.
--
-- ROLLBACK: ejecutar las dos funciones de la seccion final (version anterior). ANTES de revertir hay que REASIGNAR a 'laboral'
-- o 'extendido' a quien tenga horario = 'sin_restriccion' (la funcion anterior lo trataria como laboral y quedaria bloqueado fuera
-- de 7:00 a 18:00):
--   update public.geoportal_lista_blanca set horario = 'laboral' where horario = 'sin_restriccion';
-- Y quitar la tercera <option> de Admin.tsx (git revert del commit del desplegable).
-- =====================================================================

-- >>> NUEVAS ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.geoportal_estado_acceso(p_email text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ahora as (
    select now() at time zone 'America/Bogota' as ts
  ), u as (
    select lb.rol, lb.horario, lb.dias
    from public.geoportal_lista_blanca lb
    where lb.email = lower(p_email) and lb.activo
    limit 1
  ), cfg as (
    select pausado from public.geoportal_config where id = 1
  )
  select case
    when not (
      public.geoportal_dominio_ok(p_email)
      and exists (select 1 from u)
    ) then 'denegado'
    when (select rol from u) = 'admin' then 'ok'
    when coalesce((select pausado from cfg), false) then 'pausado'
    when (select dias from u) = 'habiles'
     and extract(dow from (select ts from ahora)) not between 1 and 5
      then 'fuera_horario'
    when (select horario from u) = 'sin_restriccion' then 'ok'
    when (select ts from ahora)::time between time '07:00'
         and (case when (select horario from u) = 'extendido'
                   then time '22:00' else time '18:00' end)
      then 'ok'
    else 'fuera_horario'
  end;
$function$;

CREATE OR REPLACE FUNCTION public.geoportal_admin_permisos(p_solicitante text, p_email text, p_explorar boolean, p_focalizacion boolean, p_comercial boolean, p_rutas boolean, p_horario text, p_dias text, p_dashboard boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.geoportal_es_admin(p_solicitante) then
    raise exception 'No autorizado';
  end if;
  if p_horario not in ('laboral','extendido','sin_restriccion') then
    raise exception 'Horario inválido';
  end if;
  if p_dias not in ('habiles','todos') then
    raise exception 'Días inválidos';
  end if;
  update public.geoportal_lista_blanca
  set ver_explorar = p_explorar,
      ver_focalizacion = p_focalizacion,
      ver_comercial = p_comercial,
      ver_rutas = p_rutas,
      ver_dashboard = p_dashboard,
      horario = p_horario,
      dias = p_dias
  where email = lower(p_email);
  return found;
end;
$function$;

-- >>> ROLLBACK: versiones anteriores (ver nota de reasignar antes de ejecutar) ------
CREATE OR REPLACE FUNCTION public.geoportal_estado_acceso(p_email text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ahora as (
    select now() at time zone 'America/Bogota' as ts
  ), u as (
    select lb.rol, lb.horario, lb.dias
    from public.geoportal_lista_blanca lb
    where lb.email = lower(p_email) and lb.activo
    limit 1
  ), cfg as (
    select pausado from public.geoportal_config where id = 1
  )
  select case
    when not (
      public.geoportal_dominio_ok(p_email)
      and exists (select 1 from u)
    ) then 'denegado'
    when (select rol from u) = 'admin' then 'ok'
    when coalesce((select pausado from cfg), false) then 'pausado'
    when (select dias from u) = 'habiles'
     and extract(dow from (select ts from ahora)) not between 1 and 5
      then 'fuera_horario'
    when (select ts from ahora)::time between time '07:00'
         and (case when (select horario from u) = 'extendido'
                   then time '22:00' else time '18:00' end)
      then 'ok'
    else 'fuera_horario'
  end;
$function$;

CREATE OR REPLACE FUNCTION public.geoportal_admin_permisos(p_solicitante text, p_email text, p_explorar boolean, p_focalizacion boolean, p_comercial boolean, p_rutas boolean, p_horario text, p_dias text, p_dashboard boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.geoportal_es_admin(p_solicitante) then
    raise exception 'No autorizado';
  end if;
  if p_horario not in ('laboral','extendido') then
    raise exception 'Horario inválido';
  end if;
  if p_dias not in ('habiles','todos') then
    raise exception 'Días inválidos';
  end if;
  update public.geoportal_lista_blanca
  set ver_explorar = p_explorar,
      ver_focalizacion = p_focalizacion,
      ver_comercial = p_comercial,
      ver_rutas = p_rutas,
      ver_dashboard = p_dashboard,
      horario = p_horario,
      dias = p_dias
  where email = lower(p_email);
  return found;
end;
$function$;
