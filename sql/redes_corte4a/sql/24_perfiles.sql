-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 24 — PERFILES DE REDES CON ver_dashboard_redes (D-12, §16 de la bitácora)
-- Hasta el 3b, «supervisor» en redes era ver_dashboard_tecnico (el supervisor de planta). Desde aquí:
--   · administrador: siempre;
--   · SUPERVISOR de distribución: ver_dashboard_redes (bandejas, valores, galería, editar la ficha salvo el origen, captura sin asignación);
--   · operador: cualquier otra persona de Técnica (incluido el supervisor de planta, que en redes ya no supervisa).
-- Reemplaza redes.f_perfil_lectura (1a) y redes.f_editor_ficha (3b), con la misma firma. Las demás funciones los llaman y cambian solas.
-- =====================================================================

-- ¿Supervisor de distribución (o administrador)?
create function redes.f_es_supervisor_redes(p_email text) returns boolean
language sql stable security definer set search_path to 'public', 'pg_temp' as $f$
  select public.geoportal_es_admin(p_email) or public.geoportal_puede(p_email, 'dashboard_redes') $f$;

-- Perfil de Técnica para leer redes: 'admin' | 'supervisor' (distribución) | 'operador'. Sin perfil, o desactivado en Técnica: 42501.
create or replace function redes.f_perfil_lectura(p_solicitante text, out email text, out perfil text)
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_tec text;
begin
  email := lower(btrim(coalesce(p_solicitante, '')));
  if email = '' or position('@' in email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if public.geoportal_es_admin(email) then perfil := 'admin'; return; end if;
  v_tec := tecnica.f_perfil(email);
  perfil := case when public.geoportal_puede(email, 'dashboard_redes') then 'supervisor' when v_tec is not null then 'operador' end;
  if perfil is null then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  if not tecnica.f_tecnica_activa(email) then raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501'; end if;
end $f$;

-- Captura (daño e intervención): el supervisor de distribución pasa sin tener el formulario asignado; los demás, con la regla de Técnica de siempre.
create function redes.f_autorizar_captura_redes(p_solicitante text, p_formulario text) returns text
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email <> '' and position('@' in v_email) > 1 and public.geoportal_estado_acceso(v_email) = 'ok' and public.geoportal_puede(v_email, 'dashboard_redes') then
    if not public.geoportal_es_admin(v_email) and not tecnica.f_tecnica_activa(v_email) then raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501'; end if;
    return v_email;
  end if;
  return tecnica.f_autorizar_captura(p_solicitante, p_formulario);
end $f$;

-- Editar la ficha: el administrador y el supervisor de distribución (§26.2). El origen solo el administrador (lo exige ficha_editar).
create or replace function redes.f_editor_ficha(p_solicitante text) returns text
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p.perfil not in ('admin', 'supervisor') then raise exception 'Solo el administrador o el supervisor de distribución editan la ficha del activo' using errcode = '42501'; end if;
  return p.email;
end $f$;
