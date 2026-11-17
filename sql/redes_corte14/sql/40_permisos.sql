-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las funciones internas nuevas y las reemplazadas: nadie de la API. Las RPC nuevas y las reemplazadas: solo service_role (la Edge geoportal-redes).
-- Las tablas nuevas: nadie de la API (10_esquema.sql): las leen y escriben solo las funciones SECURITY DEFINER.
-- =====================================================================
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname like 'f\_levantar\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
  end loop;
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\_redes\_levantar\_%' or p.proname in ('geoportal_redes_mi_perfil')) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
-- campo.f_formularios_personal: «create or replace» conserva sus permisos de la pasada del 14-nov (la llaman solo las RPC de campo); aquí no se tocan.

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte14', 'migracion_redes_corte14', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.levantar_puntos', 'redes.levantar_preparaciones', 'redes.levantar_fotos', 'redes.levantar_eventos'),
        'nuevas', (select jsonb_agg(p.proname order by p.proname) from pg_proc p
                    where (p.pronamespace = 'redes'::regnamespace and p.proname like 'f\_levantar\_%') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_levantar\_%')),
        'reemplazadas', jsonb_build_array('geoportal_redes_mi_perfil', 'campo.f_formularios_personal'),
        'fuera_de_redes', jsonb_build_array('tecnica.formulario_clave (clave activo_campo)', 'campo.personal_eventos (CHECK del formulario)', 'campo.f_formularios_personal (una fila más)'),
        'parametros', jsonb_build_array('levantar_radio_min_m', 'levantar_radio_max_m', 'levantar_duplicado_m', 'levantar_lista_max'),
        'motivo', '«Encontrar o reportar activo»: activos cercanos a la persona, puntos por levantar (solo inserción, con estados) y el formulario asignable en Personal'), null);
