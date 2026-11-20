-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO · 20 — FUNCIONES INTERNAS (no las ejecuta la API)
-- =====================================================================
-- Los eventos ABIERTOS que tocan un contrato, del más específico al más general (la misma prioridad con que el Corte 15 asocia los reportes:
-- círculo, luego sectores, luego total; entre iguales, el de menor área; luego el más nuevo).
-- La regla de a quién afecta es la de redes.f_evento_contratos (Corte 15): el tramo amarrado al contrato toca la zona, o el evento es de toda la ciudad.
-- Un contrato sin amarre (no está en redes.contrato_tramo) solo puede estar en un evento de toda la ciudad.
create function redes.f_eventos_del_contrato(p_contrato text) returns table (evento_id bigint, orden integer)
language sql stable security definer set search_path = redes, public, extensions, pg_temp as $$
  with t as (select m.geom from redes.contrato_tramo ct join redes.activo_vigente_mat m on m.activo_id = ct.activo_id where ct.contrato = p_contrato)
  select e.id, (row_number() over (order by case e.alcance when 'circulo' then 1 when 'sectores' then 2 else 3 end, ST_Area(e.geom) nulls last, e.id desc))::integer
    from redes.f_eventos_abiertos() e
   where e.todo or exists (select 1 from t where t.geom && e.geom and ST_Intersects(t.geom, e.geom)) $$;

-- Quién consulta: los perfiles que buscan contratos en Comercial (geovisor comercial), en Campo (formularios de campo y su supervisor) y en el acta de
-- Comercial (quien la captura y su supervisor: el aviso sale al verificar el contrato del acta; David, 19-nov), y el administrador. Técnica sola, no.
-- Devuelve el correo normalizado o se niega (42501). Como las demás de redes: el acceso tiene que estar «ok» (lista blanca, horario).
create function redes.f_evento_contrato_acceso(p_solicitante text) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if not (public.geoportal_puede(v_email, 'comercial') or public.geoportal_puede(v_email, 'campo') or public.geoportal_puede(v_email, 'acta')) then
    raise exception 'Sin permiso para consultar si un contrato está en un evento de suspensión' using errcode = '42501';
  end if;
  return v_email;
end $$;
