-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como estaban con el 9a-bis (texto exacto), quita las {{N_NUEVAS}} nuevas y las 6 tablas de la 116 (vacías), desactiva la capa «linea_116» del Cargue, devuelve la capa
-- «pqr_116» del geovisor a «preparada» y DESACTIVA (no borra) los dos formularios compartidos en distribución.
-- SE NIEGA si alguna función cambió después de la migración o si ya hay cargas de la 116 (la reversa no borra datos: revierta las cargas en el Cargue y avise).
-- Las asignaciones de esos formularios hechas en Personal no se tocan (son hechos de tecnica.personal_tecnico_eventos).
-- =====================================================================
do $$
begin
  if to_regclass('redes.l116_reportes') is null then raise exception 'No hay nada que revertir: el Corte 5d no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_5D}}' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 5d: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.cargas where capa_codigo = 'linea_116') or exists (select 1 from redes.l116_reportes) or exists (select 1 from redes.l116_revisiones) then
    raise exception 'Ya hay cargas de la línea 116: la reversa no borra datos; apague la capa del geovisor y avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto del 9a-bis (antes de quitar las nuevas, que ellas usan)
{{TEXTOS_ANTES}}
-- 2. lo nuevo (las tablas están vacías: lo comprobó la guardia)
{{DROPS}}
{{DROP_TABLAS}}
update redes.capas set activa = false where codigo = 'linea_116';      -- el catálogo no se borra: se desactiva (sale del Cargue)
-- 3. la capa del geovisor, como la dejó el 6a; los formularios compartidos, desactivados
update redes.geovisor_capas set {{CAPA_ANTES}} where codigo = 'pqr_116';
update redes.formularios_distribucion set activo = false where clave in ('anomalia_compartida', 'revision_compartida');
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte5d', 'reversa_redes_corte5d', null, jsonb_build_object('motivo', 'reversa del Corte 5d'), null);
