-- =====================================================================
-- REPARTO DE FACTURAS · COMMIT 1 · 55 — PERMISOS. Todo objeto nuevo: revoke all … from public, anon, authenticated, service_role ANTES de dar permisos.
-- Solo service_role ejecuta las RPC public.geoportal_reparto_* (la Edge geoportal-reparto). Nadie más toca el esquema reparto: las RPC son SECURITY DEFINER.
-- El Dell (respaldo cifrado, cambio de D2 del 23-nov): homelab_lectura recibe USAGE sobre reparto y SELECT sobre CADA tabla, con la lista explícita
-- (sin ALTER DEFAULT PRIVILEGES: una tabla futura no queda legible por accidente). Las tablas de reparto no tienen RLS: el SELECT basta.
-- =====================================================================
revoke all on all tables in schema reparto from public, anon, authenticated, service_role;
revoke all on all sequences in schema reparto from public, anon, authenticated, service_role;
revoke all on all functions in schema reparto from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
grant usage on schema reparto to homelab_lectura;
grant select on reparto.parametros, reparto.lotes, reparto.lote_filas, reparto.lotes_anulados,
                reparto.jornadas, reparto.jornada_items, reparto.entregas, reparto.entregas_anuladas to homelab_lectura;
