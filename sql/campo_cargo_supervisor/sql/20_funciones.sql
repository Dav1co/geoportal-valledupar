-- =====================================================================
-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · 20 — FUNCIÓN INTERNA NUEVA (sin permisos para los roles de la API; la usa la RPC SECURITY DEFINER)
-- =====================================================================
-- ¿Es supervisor de Comercial? Quien tenga dashboard_campo o dashboard_acta en una cuenta activa que no sea de administrador (el mismo criterio del «perfil»
-- que ya muestra geoportal_campo_personal). Sus áreas y cargos solo los cambia el administrador (David, 22-nov).
create function campo.f_supervisor_comercial(p_email text) returns boolean
language sql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
  select exists (select 1 from public.geoportal_lista_blanca lb where lb.email = lower(btrim(coalesce(p_email, ''))) and lb.activo and lb.rol <> 'admin'
                   and (coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_dashboard_acta, false)))
$$;
