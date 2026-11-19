-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · CORRECCIÓN «LA VÁLVULA QUE CERRÓ EL OPERADOR» · 40 — PERMISOS: revoke all antes de dar permisos. La RPC: solo service_role.
-- =====================================================================
revoke all on function public.geoportal_redes_cierres_registro(text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_cierres_registro(text, text) to service_role;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_9b_valvula_operador', 'migracion_redes_9b_valvula_operador', null, jsonb_build_object(
        'nuevas', jsonb_build_array('geoportal_redes_cierres_registro'),
        'motivo', 'el operador sin el geovisor ve cerradas, y puede abrir, las válvulas que cerró su daño o su intervención (lectura por registro; no da el geovisor)'), null);
