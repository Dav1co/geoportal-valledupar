-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las 5 funciones internas nuevas: nadie de la API. Las 2 RPC nuevas y las RPC reemplazadas: solo service_role (la Edge geoportal-redes).
-- =====================================================================
revoke all on function redes.f_nodo_visible_id(bigint), redes.f_nodo_de_activo(bigint), redes.f_tramos_de_nodo(bigint), redes.f_sector_en(numeric, numeric),
  redes.f_operador_redes(text) from public, anon, authenticated, service_role;
revoke all on function redes.f_ficha(bigint, text), redes.f_pm_sugerencia(text, text, text, text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_sector_en', 'geoportal_redes_nodos_clasificar_grupo', 'geoportal_redes_tramo_nodos', 'geoportal_redes_nodo_crear_activo',
                                'geoportal_redes_nodos_por_clasificar', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_nodo_clasificar', 'geoportal_redes_danos',
                                'geoportal_redes_intervenciones', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_referencia', 'geoportal_redes_mi_perfil',
                                'geoportal_redes_crear_dano', 'geoportal_redes_reporte_convertir') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9a_bis', 'migracion_redes_corte9a_bis', null, jsonb_build_object(
        'nuevas', jsonb_build_array('redes.f_nodo_visible_id', 'redes.f_nodo_de_activo', 'redes.f_tramos_de_nodo', 'redes.f_sector_en', 'redes.f_operador_redes',
                                    'geoportal_redes_sector_en', 'geoportal_redes_nodos_clasificar_grupo'),
        'motivo', 'ficha sin recorrer tablas enteras; sector hidráulico oficial; nodos por el supervisor y por grupo; ficha en modo buscar para el operador de redes'), null);
