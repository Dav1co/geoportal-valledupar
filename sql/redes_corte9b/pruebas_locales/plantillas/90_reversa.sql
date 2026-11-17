-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1: simulación de cierre) · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja f_param_entero (del 10) y tecnica.f_avisos (del 12) como estaban (texto exacto), quita las {{N_NUEVAS}} funciones nuevas y las 6 tablas (vacías) y deja los parámetros «sin uso».
-- SE NIEGA si alguna función cambió después de la migración o si ya hay simulaciones guardadas (la reversa no borra datos: avise).
-- =====================================================================
do $$
begin
  if to_regclass('redes.simulaciones_cierre') is null then raise exception 'No hay nada que revertir: el Corte 9b (Fase 1) no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_9B}}' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 9b: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.simulaciones_cierre) or exists (select 1 from redes.valvula_maniobras) or exists (select 1 from redes.corte_fotos) then
    raise exception 'Ya hay simulaciones o maniobras de válvula guardadas: la reversa no borra datos; avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto de producción (f_param_entero del 10 y tecnica.f_avisos del 12)
{{TEXTOS_ANTES}}
-- 2. lo nuevo (la tabla está vacía: lo comprobó la guardia)
{{DROPS}}
{{DROP_TABLAS}}
-- 3. los parámetros no se borran: quedan marcados sin uso
update redes.parametros set descripcion = 'Sin uso (reversa del Corte 9b)' where clave in ({{PARAMS}});
update tecnica.aviso_parametros set descripcion = 'Sin uso (reversa del Corte 9b)' where clave in ('valvula_cerrada_naranja_h', 'valvula_cerrada_rojo_h');
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte9b', 'reversa_redes_corte9b_fase1', null, jsonb_build_object('motivo', 'reversa del Corte 9b (Fase 1)'), null);
