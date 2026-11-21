-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 20 — FUNCIONES INTERNAS (sin permisos para los roles de la API; las usan las RPC SECURITY DEFINER).
-- =====================================================================

-- ¿La persona tiene el alcance? (D6) El administrador, los dos siempre. Sin eventos: PTAP sí, PTAR no. Si no, el último evento.
create function tecnica.f_tiene_alcance(p_email text, p_alcance text) returns boolean
language sql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
  select case when public.geoportal_es_admin(lower(p_email)) then true
              else coalesce((select e.tipo_evento = 'asignar' from tecnica.alcance_eventos e
                              where e.persona = lower(p_email) and e.alcance = p_alcance order by e.id desc limit 1), p_alcance = 'ptap') end
$$;

-- Puerta del Dashboard PTAP y de todo lo de supervisión de planta (la publicada + una línea, D6): quien solo tiene la PTAR no entra.
-- Mismo nombre y firma: las RPC que ya la llaman (Dashboard PTAP, químicos, puntos, reportes y descargas) no cambian. Para todos los que existen hoy no cambia nada (sin eventos, PTAP = sí).
create or replace function tecnica.f_autorizar_supervision(p_solicitante text) returns text
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if tecnica.f_perfil(v_email) <> 'admin' and not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  if not tecnica.f_tiene_alcance(v_email, 'ptap') then
    raise exception 'Su acceso es a la PTAR, no a las plantas de agua potable' using errcode = '42501';
  end if;
  return v_email;
end $$;

-- Puerta de la PTAR (D6): Dashboard técnico (supervisor o administrador), Técnica activa y el alcance PTAR.
create function tecnica.f_autorizar_ptar(p_solicitante text) returns text
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if tecnica.f_perfil(v_email) <> 'admin' and not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  if not tecnica.f_tiene_alcance(v_email, 'ptar') then
    raise exception 'No tiene el alcance de la PTAR' using errcode = '42501';
  end if;
  return v_email;
end $$;

-- Puerta por instalación: la PTAR pide el alcance PTAR; una PTAP, el de supervisión de planta (alcance PTAP).
create function tecnica.f_autorizar_instalacion(p_solicitante text, p_instalacion_id bigint) returns text
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_tipo text;
begin
  select i.tipo into v_tipo from tecnica.instalaciones i where i.id = p_instalacion_id;
  if v_tipo = 'residual' then return tecnica.f_autorizar_ptar(p_solicitante); end if;
  return tecnica.f_autorizar_supervision(p_solicitante);
end $$;

-- Alias vigente de un elemento (por código; nulo = sin alias).
create function tecnica.f_alias_vigente(p_instalacion_id bigint, p_codigo text) returns text
language sql stable set search_path to 'pg_catalog', 'pg_temp' as $$
  select a.alias from tecnica.elemento_alias_eventos a where a.instalacion_id = p_instalacion_id and a.codigo = p_codigo order by a.id desc limit 1
$$;

create function tecnica.f_tipo_elemento_texto(p_tipo text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case p_tipo when 'perimetro' then 'Perímetro' when 'laguna' then 'Laguna' when 'tramo' then 'Tramo' when 'punto_medicion' then 'Punto de medición'
                     when 'pozo' then 'Pozo' when 'descarga' then 'Descarga' else p_tipo end
$$;

-- Instalación por código (activa); error de usuario si no existe.
create function tecnica.f_instalacion(p_codigo text) returns tecnica.instalaciones
language plpgsql stable set search_path to 'pg_catalog', 'pg_temp' as $$
declare i tecnica.instalaciones;
begin
  select * into i from tecnica.instalaciones x where x.codigo = lower(btrim(coalesce(p_codigo, ''))) and x.activa;
  if not found then perform tecnica.f_error('Esa planta no existe', 'P0002'); end if;
  return i;
end $$;
