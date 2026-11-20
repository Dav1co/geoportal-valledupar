-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO · 40 — PERMISOS: revoke all antes de dar permisos. La RPC: solo service_role. Las internas: nadie.
-- =====================================================================
revoke all on function redes.f_eventos_del_contrato(text) from public, anon, authenticated, service_role;
revoke all on function redes.f_evento_contrato_acceso(text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_redes_evento_contrato(text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_evento_contrato(text, text) to service_role;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_aviso_evento_contrato', 'migracion_redes_aviso_evento_contrato', null, jsonb_build_object(
        'nuevas', jsonb_build_array('redes.f_eventos_del_contrato', 'redes.f_evento_contrato_acceso', 'public.geoportal_redes_evento_contrato'),
        'motivo', 'primera regla de choque: al buscar o verificar un contrato, Comercial, Campo y el acta ven si está dentro de un evento de suspensión abierto (solo avisa)'), null);
