-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como estaban con el 5d (texto exacto), quita las {{N_NUEVAS}} nuevas y las 3 tablas de la valoración (vacías) y deja los dos parámetros «sin uso».
-- SE NIEGA si alguna función cambió después de la migración o si la valoración ya está cargada (la reversa no borra datos: avise).
-- =====================================================================
do $$
begin
  if to_regclass('redes.val_filas') is null then raise exception 'No hay nada que revertir: el Corte 10 no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_10}}' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 10: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.val_hojas) or exists (select 1 from redes.val_filas) or exists (select 1 from redes.val_amarre)
     or exists (select 1 from redes.ref_cargas where conjunto in ('valoracion', 'val_amarre')) then
    raise exception 'La valoración ya está cargada: la reversa no borra datos; avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto del 5d (antes de quitar las nuevas, que ellas usan)
{{TEXTOS_ANTES}}
-- 2. lo nuevo (las tablas están vacías: lo comprobó la guardia)
{{DROPS}}
{{DROP_TABLAS}}
-- 3. los parámetros no se borran: quedan marcados sin uso
update redes.parametros set descripcion = 'Sin uso (reversa del Corte 10)' where clave in ('valoracion_hoja_alcantarillado', 'valoracion_tolerancia_pct');
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte10', 'reversa_redes_corte10', null, jsonb_build_object('motivo', 'reversa del Corte 10'), null);
