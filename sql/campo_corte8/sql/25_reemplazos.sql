-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo con UN cambio exacto:
--   · campo.f_autorizar_reporte: también pasa quien entra por las RPC de Técnica (la marca de la transacción). Sin la marca, igual que antes;
--   · tecnica.f_formularios: los dos formularios compartidos («Reportar anomalía» y «Revisiones generales»).
-- =====================================================================
-- campo.f_autorizar_reporte(text)
CREATE OR REPLACE FUNCTION campo.f_autorizar_reporte(p_solicitante text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  -- Corte 8 de Técnica: también pasa quien entra por las RPC geoportal_campo_tec_* (ya autorizado allá por su formulario de Técnica); la marca solo dura esa transacción
  if campo.f_perfil(v_email) is null and coalesce(current_setting('geoportal.via_tecnica', true), '') <> 'on' then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  return v_email;
end $function$;

-- tecnica.f_formularios()
CREATE OR REPLACE FUNCTION tecnica.f_formularios()
 RETURNS TABLE(clave text, nombre text, descripcion text, orden integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  values ('entrada',          'Entrada',                           'Agua cruda que ingresa a las plantas.', 1),
         ('salida',           'Salida',                            'Agua tratada que sale de las plantas.', 2),
         ('muestreo',         'Muestreo',                          'Muestreo en los puntos de la red y los tanques.', 3),
         ('danos_fallas',     'Daños o fallas',                    'Daños o fallas en la planta.', 4),
         ('mantenimiento',    'Mantenimiento, reparación e inversión', 'Mantenimiento, reparación e inversión.', 5),
         ('uso_quimicos',     'Uso de químicos',                   'Químicos usados en el proceso.', 6),
         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7),
         ('anomalia_compartida', 'Reportar anomalía',               'El mismo reporte de anomalías de Comercial, hecho desde Técnica.', 8),
         ('revision_compartida', 'Revisiones generales',            'La misma revisión general de Comercial, hecha desde Técnica.', 9);
$function$;
