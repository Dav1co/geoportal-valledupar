-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vistas nuevas de redes: RLS activa sin políticas y ningún privilegio para la API. Funciones internas: nadie de la API.
-- RPC public.geoportal_redes_* nuevas (y activo_buscar, que se reemplaza y conserva su ACL): solo execute a service_role.
-- =====================================================================
revoke all on all tables in schema redes from public, anon, authenticated, service_role;
revoke all on all sequences in schema redes from public, anon, authenticated, service_role;
revoke all on all functions in schema redes from public, anon, authenticated, service_role;
do $$
declare t record; f record;
begin
  for t in select c.relname from pg_class c where c.relnamespace = 'redes'::regnamespace and c.relkind in ('r', 'p') and not c.relrowsecurity loop
    execute format('alter table redes.%I enable row level security', t.relname);
  end loop;
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
           ('geoportal_redes_perfil', 'geoportal_redes_galeria', 'geoportal_redes_ficha_editar', 'geoportal_redes_foto_perfil_preparar', 'geoportal_redes_foto_perfil_fijar',
            'geoportal_redes_activo_buscar') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
