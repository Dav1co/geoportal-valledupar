-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el de producción al publicar) con cambios exactos, aplicados una sola vez.
--   · geoportal_redes_mi_perfil: «activo_campo» (la persona tiene «Encontrar o reportar activo»), para la tarjeta del inicio de Técnica;
--   · campo.f_formularios_personal: una fila más, «Encontrar o reportar activo», en la lista de Personal de Comercial.
-- =====================================================================
-- public.geoportal_redes_mi_perfil(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_mi_perfil(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  return jsonb_build_object('perfil', p.perfil, 'dashboard_redes', p.perfil in ('admin', 'supervisor'), 'dashboard_ptap', public.geoportal_puede(p.email, 'dashboard_tecnico'),
                            'geovisor', redes.f_geovisor_lectura(p.email),      -- Corte 6a
                            -- 9a-bis: la Ficha de activos en modo buscar (solo lectura) también para el operador de redes
                            'ficha_buscar', p.perfil in ('admin', 'supervisor') or redes.f_operador_redes(p.email),
                            'activo_campo', redes.f_levantar_puede(p.email));      -- Corte 14: «Encontrar o reportar activo»
end $function$;

-- campo.f_formularios_personal()
CREATE OR REPLACE FUNCTION campo.f_formularios_personal()
 RETURNS TABLE(clave text, nombre text, grupo text, orden integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'campo', 'pg_temp'
AS $function$
  select 'reporte_general', 'Reportar anomalía', 'Reportar anomalía', 0
  union all
  select 'tipo:' || t.codigo, t.nombre, g.nombre, (1000 + g.orden * 1000 + t.orden)::integer
    from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where t.activo and g.activo
     and (exists (select 1 from campo.tipo_campos c where c.tipo_id = t.id and c.activo) or exists (select 1 from campo.tipo_fotos f where f.tipo_id = t.id and f.activo)
          or t.genera_resultado or t.prefijo_consecutivo is not null)
  union all
  select 'acta', 'Reportar posible pérdida', 'Reportar posible pérdida', 2000000000
  union all      -- Corte 14 de Técnica: «Encontrar o reportar activo» (lo usa quien tiene Formularios de campo; aquí solo se registra a quién se le asigna)
  select 'activo_campo', 'Encontrar o reportar activo', 'Activos de la red', 2000000001
$function$;
