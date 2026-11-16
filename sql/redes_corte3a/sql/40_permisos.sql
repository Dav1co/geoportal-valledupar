-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vistas nuevas de redes: RLS activa sin políticas y ningún privilegio para la API. Funciones internas: nadie de la API.
-- RPC public.geoportal_redes_* nuevas: solo execute a service_role. Las dos que se reemplazan (preparar_dano y crear_dano) conservan su ACL
-- (create or replace no la cambia) y aquí se vuelve a dejar igual, por si acaso.
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
           ('geoportal_redes_formulario_intervencion', 'geoportal_redes_danos_abiertos', 'geoportal_redes_preparar_intervencion', 'geoportal_redes_crear_intervencion',
            'geoportal_redes_intervencion_recursos', 'geoportal_redes_intervenciones', 'geoportal_redes_no_identificados', 'geoportal_redes_asociar_activo',
            'geoportal_redes_preparar_dano', 'geoportal_redes_crear_dano') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
