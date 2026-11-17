-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1: simulación de cierre) · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja f_param_entero como estaba con el 10 (texto exacto), quita las {{N_NUEVAS}} funciones nuevas y la tabla de simulaciones (vacía) y deja los parámetros «sin uso».
-- SE NIEGA si alguna función cambió después de la migración o si ya hay simulaciones guardadas (la reversa no borra datos: avise).
-- =====================================================================
do $$
begin
  if to_regclass('redes.simulaciones_cierre') is null then raise exception 'No hay nada que revertir: el Corte 9b (Fase 1) no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_9B}}' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 9b: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.simulaciones_cierre) then
    raise exception 'Ya hay simulaciones guardadas: la reversa no borra datos; avise';
  end if;
end $$;

-- 1. la función reemplazada, con su texto del 10
{{TEXTOS_ANTES}}
-- 2. lo nuevo (la tabla está vacía: lo comprobó la guardia)
{{DROPS}}
{{DROP_TABLAS}}
-- 3. los parámetros no se borran: quedan marcados sin uso
update redes.parametros set descripcion = 'Sin uso (reversa del Corte 9b)' where clave in ({{PARAMS}});
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte9b', 'reversa_redes_corte9b_fase1', null, jsonb_build_object('motivo', 'reversa del Corte 9b (Fase 1)'), null);
