-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como las dejó el 5b (las 8 reemplazadas con su texto exacto), sin las 6 RPC nuevas, sin la función interna nueva y sin las 2 tablas nuevas;
-- el CHECK de fuente de tecnica.puntos_ubicacion vuelve al del 5a.
-- Las 11 capas nuevas quedan INACTIVAS (las capas no se borran) y el parámetro nuevo se queda (nadie lo lee).
-- SE NIEGA si ya hay devoluciones o correcciones, si alguna capa nueva o acometidas ya tiene cargas (nada se borra), o si alguna función cambió después de la migración.
-- =====================================================================
do $$
begin
  if to_regclass('redes.ficha_campo_devoluciones') is null then raise exception 'No hay nada que revertir: no existe redes.ficha_campo_devoluciones'; end if;
  if exists (select 1 from redes.ficha_campo_devoluciones) or exists (select 1 from tecnica.punto_ubicacion_correcciones) then
    raise exception 'Ya hay campos devueltos a la capa o ubicaciones corregidas: la reversa se niega (nada se borra)';
  end if;
  if exists (select 1 from redes.cargas where capa_codigo in ('captaciones', 'aduccion', 'desarenadores', 'bombeo_ap', 'sumideros', 'interceptores', 'bombeo_ar', 'ptar',
                                                              'sectores', 'sensores', 'scada', 'acometidas') or columna_llave = '(geometria)' or masiva_id is not null) then
    raise exception 'Ya hay cargas con el lector genérico, sin columna llave o masivas: la reversa se niega (las funciones del 5b no las leen)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_5C}}'
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in ({{RPC_NUEVAS}})) <> {{N_RPC}}
     or (select count(*) from (values {{CAMBIADAS_5C}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> {{N_CAMBIADAS}} then
    raise exception 'Las funciones cambiaron después de la migración del Corte 5c: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto del 5b
{{TEXTOS_5B}}
-- 2. lo nuevo
{{DROPS}}
drop table redes.ficha_campo_devoluciones;
drop table tecnica.punto_ubicacion_correcciones;
alter table tecnica.puntos_ubicacion drop constraint puntos_ubicacion_fuente_check;
alter table tecnica.puntos_ubicacion add constraint puntos_ubicacion_fuente_check check (fuente = any (array['david', 'barrio', 'gps_operador', 'carga']));
update redes.capas set activa = false
 where codigo in ('captaciones', 'aduccion', 'desarenadores', 'bombeo_ap', 'sumideros', 'interceptores', 'bombeo_ar', 'ptar', 'sectores', 'sensores', 'scada');

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_5B}}' then
    raise exception 'La reversa no dejó la base como en el 5b';
  end if;
end $$;
