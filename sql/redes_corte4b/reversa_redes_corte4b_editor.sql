begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja la base como la dejó el 4a: sin las 12 RPC nuevas, sin las funciones internas, la vista y las 2 tablas nuevas. No toca nada más (el 4b no
-- reemplazó ninguna función).
-- SE NIEGA si la ficha del personal o las cuadrillas tienen datos (nada se borra), o si alguna función cambió después de la migración.
-- Lo que se hizo con las RPC del 4b en tablas de antes se queda (cambios de parámetros, alias, activos creados en nodos): son hechos.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.personal_ficha_eventos') is null then raise exception 'No hay nada que revertir: no existe tecnica.personal_ficha_eventos'; end if;
  if exists (select 1 from tecnica.personal_ficha_eventos) or exists (select 1 from redes.cuadrillas) then
    raise exception 'Ya hay fichas del personal o cuadrillas: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '55668dddf263065b5eb90aeb3001a3b7' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 4b: la reversa se niega a pisarlas; avise';
  end if;
end $$;

drop function geoportal_redes_personal(text,text,text);
drop function geoportal_redes_personal_fijar(text,text,text,text,text);
drop function geoportal_redes_personal_historial(text,text,bigint,integer);
drop function geoportal_redes_catalogo(text);
drop function geoportal_redes_alias_historial(text,text,text);
drop function geoportal_redes_cuadrilla_fijar(text,bigint,text,boolean,text);
drop function geoportal_redes_parametros(text);
drop function geoportal_redes_parametro_fijar(text,text,numeric,text);
drop function geoportal_redes_graficas(text,integer);
drop function geoportal_redes_descarga(text,text,date,date,boolean,text);
drop function geoportal_redes_nodos_por_clasificar(text,text,bigint,integer);
drop function geoportal_redes_nodo_crear_activo(text,bigint,text,text,text,text);
drop function redes.f_area(text);
drop function redes.f_geovisor_lectura(text);
drop function redes.f_persona_tecnica(text);
drop function redes.f_param_entero(text);
drop view redes.v_personal_ficha;
drop table tecnica.personal_ficha_eventos;
drop table redes.cuadrillas;

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '1a2be013019c9a59f1c1e0f2241661f0' then
    raise exception 'La reversa no dejó la base como en el 4a';
  end if;
end $$;
commit;
