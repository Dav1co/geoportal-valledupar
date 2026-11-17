-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1: simulación de cierre) · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja f_param_entero como estaba con el 10 (texto exacto), quita las 9 funciones nuevas y la tabla de simulaciones (vacía) y deja los parámetros «sin uso».
-- SE NIEGA si alguna función cambió después de la migración o si ya hay simulaciones guardadas (la reversa no borra datos: avise).
-- =====================================================================
do $$
begin
  if to_regclass('redes.simulaciones_cierre') is null then raise exception 'No hay nada que revertir: el Corte 9b (Fase 1) no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'beafb93a12ff2e4b306281692e62dd93' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 9b: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.simulaciones_cierre) then
    raise exception 'Ya hay simulaciones guardadas: la reversa no borra datos; avise';
  end if;
end $$;

-- 1. la función reemplazada, con su texto del 10
CREATE OR REPLACE FUNCTION redes.f_param_entero(p_unidad text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select p_unidad in ('fotos', 'documentos', 'materiales', 'activos', 'días', 'horas', 'filas', 'bytes', 'zoom', 'hoja') $function$;
revoke all on function redes.f_param_entero(text) from public, anon, authenticated, service_role;

-- 2. lo nuevo (la tabla está vacía: lo comprobó la guardia)
drop function public.geoportal_redes_simulaciones(text,text);
drop function public.geoportal_redes_simulacion_guardar(text,text,text);
drop function public.geoportal_redes_simulacion_cierre(text,text,numeric,numeric);
drop function redes.f_sim_autorizar(text);
drop function redes.f_sim_tramo_cercano(numeric,numeric);
drop function redes.f_simular_cierre(bigint);
drop function redes.f_sim_escenario(bigint[],bigint,boolean,bigint[],geometry,integer);
drop function redes.f_sim_llenar_agua();
drop function redes.f_sim_grafo();
drop table redes.simulaciones_cierre;
-- 3. los parámetros no se borran: quedan marcados sin uso
update redes.parametros set descripcion = 'Sin uso (reversa del Corte 9b)' where clave in ('sim_segmento_grande_tramos', 'sim_segmento_grande_contratos', 'sim_no_cierra_max', 'sim_valvulas_lista_max', 'sim_contratos_guardar_max', 'sim_guardadas_max');
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte9b', 'reversa_redes_corte9b_fase1', null, jsonb_build_object('motivo', 'reversa del Corte 9b (Fase 1)'), null);
