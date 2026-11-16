-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como las dejó el 5a (redes.f_candidatos_muestreo con su texto exacto), sin las 4 RPC nuevas, sin la vista y sin las 2 tablas nuevas.
-- Los 2 parámetros nuevos se quedan (no se borran; nadie los lee).
-- SE NIEGA si ya hay ubicaciones propuestas (nada se borra), o si alguna función cambió después de la migración.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.punto_ubicacion_propuestas') is null then raise exception 'No hay nada que revertir: no existe tecnica.punto_ubicacion_propuestas'; end if;
  if exists (select 1 from tecnica.punto_ubicacion_propuestas) then
    raise exception 'Ya hay ubicaciones propuestas desde Muestreo: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_5B}}'
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) <> 4 then
    raise exception 'Las funciones cambiaron después de la migración del Corte 5b: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. la función reemplazada, con su texto del 5a
{{TEXTOS_5A}}
revoke all on function redes.f_candidatos_muestreo(bigint) from public, anon, authenticated, service_role;
-- 2. lo nuevo
{{DROPS}}
drop view tecnica.v_punto_propuestas;
drop table tecnica.punto_ubicacion_revisiones;
drop table tecnica.punto_ubicacion_propuestas;

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_5A}}' then
    raise exception 'La reversa no dejó la base como en el 5a';
  end if;
end $$;
