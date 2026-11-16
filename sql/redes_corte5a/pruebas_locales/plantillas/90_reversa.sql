-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como las dejó el 4b (las 9 reemplazadas con su texto exacto), sin la RPC ni las funciones nuevas, sin la vista y sin las 3 tablas
-- nuevas. La capa «muestreo» queda inactiva (las capas no se borran) y el parámetro itv_dias_atras_max_supervisor se queda (no se borra; nadie lo lee).
-- SE NIEGA si ya hay cargas de la capa de muestreo o ubicaciones o eventos de puntos (nada se borra), o si alguna función cambió después de la migración.
-- Los eventos de formularios que el supervisor de distribución haya escrito en tecnica.personal_tecnico_eventos se quedan: son válidos para planta.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.puntos_ubicacion') is null then raise exception 'No hay nada que revertir: no existe tecnica.puntos_ubicacion'; end if;
  if exists (select 1 from tecnica.puntos_ubicacion) or exists (select 1 from tecnica.punto_eventos) or exists (select 1 from redes.cargas where capa_codigo = 'muestreo') then
    raise exception 'Ya hay cargas de la capa de muestreo, ubicaciones o eventos de puntos: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_5A}}' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 5a: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las 9 funciones reemplazadas, con su texto del 4b
{{TEXTOS_4B}}
-- 2. lo nuevo
{{DROPS}}
drop view redes.v_punto_ubicacion_vigente;
drop table tecnica.puntos_ubicacion;
drop table tecnica.punto_eventos;
drop table redes.formularios_distribucion;
update redes.capas set activa = false where codigo = 'muestreo';

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_4B}}' then
    raise exception 'La reversa no dejó la base como en el 4b';
  end if;
end $$;
