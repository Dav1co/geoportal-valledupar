-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 40 — PERMISOS: revoke all antes de dar permisos.
-- Las internas de redes (y la del bot): nadie de la API. Las 13 RPC: solo service_role. El permiso del Dell para la función del bot va en otro paquete.
-- =====================================================================
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as f, p.pronamespace = 'public'::regnamespace as rpc from pg_proc p
            where (p.pronamespace = 'redes'::regnamespace and (p.proname like 'f\_evento%' or p.proname in ('f_sin_agua_para_avisos', 'f_reporte_externo_recibir_evento')))
               or (p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\_redes\_evento%' or p.proname = 'geoportal_redes_planta_sectores_fijar')) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', r.f);
    if r.rpc then execute format('grant execute on function %s to service_role', r.f); end if;
  end loop;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte15', 'migracion_redes_corte15', null, jsonb_build_object(
        'tablas', jsonb_build_array('eventos_suspension', 'evento_suspension_eventos', 'evento_suspension_reportes', 'evento_tipos_asociables', 'evento_tipo_eventos', 'planta_sectores', 'planta_sector_eventos'),
        'disparadores', jsonb_build_array('redes.reporte_externo_eventos', 'redes.l116_eventos', 'redes.danos'),
        'reemplazada', 'tecnica.f_avisos', 'tipo_de_campo', 'sin_agua',
        'motivo', 'Corte 15: evento de suspensión (por sectores, por círculo o total), asociación automática de reportes, cierre en bloque y un aviso por evento'), null);
