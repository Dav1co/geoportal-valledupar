-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones reemplazadas como estaban (texto exacto), quita las 13 nuevas y las 4 tablas (vacías), devuelve el CHECK de Comercial y desactiva el formulario.
-- SE NIEGA si alguna función cambió después de la migración, si ya hay puntos por levantar (la reversa no borra datos: avise) o si alguien tiene
-- asignado el formulario «activo_campo» (en Técnica o en Comercial).
-- =====================================================================
do $$
begin
  if to_regclass('redes.levantar_puntos') is null then raise exception 'No hay nada que revertir: el Corte 14 no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '049a0b810545e71f0a87c096cb2a6f30' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 14: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.levantar_puntos) or exists (select 1 from redes.levantar_preparaciones) then
    raise exception 'Ya hay puntos por levantar (o subidas preparadas): la reversa no borra datos; avise';
  end if;
  if exists (select 1 from tecnica.personal_tecnico_eventos where formulario = 'activo_campo') or exists (select 1 from campo.personal_eventos where formulario = 'activo_campo') then
    raise exception 'Ya hay personas con el formulario «Encontrar o reportar activo» en su historial: la reversa no borra hechos; avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto de antes (antes de quitar las nuevas, que ellas usan)
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
                            'ficha_buscar', p.perfil in ('admin', 'supervisor') or redes.f_operador_redes(p.email));
end $function$;
revoke all on function public.geoportal_redes_mi_perfil(text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_mi_perfil(text) to service_role;

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
$function$;

-- 2. lo nuevo (las tablas están vacías: lo comprobó la guardia)
drop function public.geoportal_redes_levantar_cerca(text,numeric,numeric,numeric,text);
drop function public.geoportal_redes_levantar_crear(text,uuid,jsonb,text);
drop function public.geoportal_redes_levantar_evento(text,text,text,text,text,text);
drop function public.geoportal_redes_levantar_ficha(text,text);
drop function public.geoportal_redes_levantar_fotos(text,text,text);
drop function public.geoportal_redes_levantar_inicio(text);
drop function public.geoportal_redes_levantar_lista(text,text,text,integer);
drop function public.geoportal_redes_levantar_preparar(text,integer);
drop function redes.f_levantar_acceso(text);
drop function redes.f_levantar_estado_nombre(text);
drop function redes.f_levantar_puede(text);
drop function redes.f_levantar_quien(text);
drop function redes.f_levantar_tipo_nombre(text);
drop view redes.v_levantar_punto;
drop table redes.levantar_fotos, redes.levantar_eventos, redes.levantar_preparaciones, redes.levantar_puntos;
-- 3. el CHECK de Comercial, como estaba. El formulario de distribución se DESACTIVA (no se borra: nada se borra) y por eso el dominio de Técnica conserva
--    la clave «activo_campo» (sin el formulario activo no se puede asignar ni usar). Una nueva migración del 14 lo vuelve a activar.
alter table campo.personal_eventos drop constraint personal_eventos_formulario_check;
alter table campo.personal_eventos add constraint personal_eventos_formulario_check CHECK (((formulario IS NULL) OR (formulario ~ '^(reporte_general|acta|tipo:[a-z][a-z0-9_]{1,59})$'::text)));
update redes.formularios_distribucion set activo = false where clave = 'activo_campo';
-- 4. los parámetros y el consecutivo no se borran: quedan marcados sin uso
update redes.parametros set descripcion = 'Sin uso (reversa del Corte 14)' where clave in ('levantar_radio_min_m', 'levantar_radio_max_m', 'levantar_duplicado_m', 'levantar_lista_max');
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte14', 'reversa_redes_corte14', null, jsonb_build_object('motivo', 'reversa del Corte 14'), null);
