-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 20 — FUNCIONES INTERNAS (nadie de la API las ejecuta)
-- PROPUESTA. No se ha ejecutado en la base real.
-- =====================================================================

-- Quién entra a «Encontrar o reportar activo» (lo decide SIEMPRE la base):
--   · administrador y supervisor de distribución;
--   · en Técnica: el supervisor de planta, y el operador que tenga el formulario «activo_campo» asignado (Personal de distribución);
--   · en Comercial: quien tiene Formularios de campo (operario o supervisor). Allá la asignación solo se registra, como las demás de Comercial.
-- perfil: admin | supervisor | operador | comercial.   area: tecnica | comercial (queda en el punto que reporte).
create function redes.f_levantar_acceso(p_solicitante text, out email text, out perfil text, out area text) returns record
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
begin
  email := lower(btrim(coalesce(p_solicitante, '')));
  if email = '' or position('@' in email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if public.geoportal_es_admin(email) then perfil := 'admin'; area := 'tecnica'; return; end if;
  if (public.geoportal_puede(email, 'dashboard_redes') or tecnica.f_perfil(email) is not null) and tecnica.f_tecnica_activa(email) then
    if public.geoportal_puede(email, 'dashboard_redes') then perfil := 'supervisor'; area := 'tecnica'; return; end if;
    if public.geoportal_puede(email, 'dashboard_tecnico') or tecnica.f_formulario_asignado(email, 'activo_campo') then perfil := 'operador'; area := 'tecnica'; return; end if;
  end if;
  if public.geoportal_puede(email, 'campo') then perfil := 'comercial'; area := 'comercial'; return; end if;
  raise exception 'Sin permiso para «Encontrar o reportar activo»: pídale a su supervisor que le asigne el formulario' using errcode = '42501';      -- la Edge responde 403 con su texto fijo; la pantalla dice a quién pedirlo
end $$;

create function redes.f_levantar_puede(p_email text) returns boolean
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
begin
  perform 1 from redes.f_levantar_acceso(p_email);
  return true;
exception when others then
  return false;
end $$;

create function redes.f_levantar_tipo_nombre(p_tipo text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case p_tipo when 'tuberia' then 'Tubería' when 'valvula' then 'Válvula' when 'hidrante' then 'Hidrante' when 'pozo' then 'Pozo' when 'caja' then 'Caja' when 'otro' then 'Otro' end
$$;

create function redes.f_levantar_estado_nombre(p_estado text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case p_estado when 'reportado' then 'Reportado' when 'asignado' then 'Asignado a levantamiento' when 'levantado' then 'Levantado' when 'descartado' then 'Descartado' end
$$;

-- Nombre del funcionario (nunca de un suscriptor): el de la lista blanca o, si no tiene, lo que va antes de la arroba
create function redes.f_levantar_quien(p_email text) returns text
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = p_email), split_part(p_email, '@', 1))
$$;
