-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja el esquema redes como lo dejó el Corte 3a: devuelve activo_buscar y v_epicrisis a su texto del 3a y quita las 5 RPC, las vistas, las tablas y las
-- funciones del 3b. El parámetro nuevo se conserva (redes.parametros no deja borrar filas).
-- SE NIEGA si hay ediciones de la ficha, preparaciones o fotos de perfil, u objetos en activos/ del bucket (nada se borra), o si alguna función cambió.
-- =====================================================================
do $$
begin
  if to_regclass('redes.ficha_ediciones') is null then raise exception 'No hay nada que revertir: no existe redes.ficha_ediciones'; end if;
  if exists (select 1 from redes.ficha_ediciones) or exists (select 1 from redes.foto_perfil_preparaciones)
     or exists (select 1 from storage.objects where bucket_id = 'redes-evidencias' and name like 'activos/%') then
    raise exception 'Ya hay ediciones de la ficha o fotos de perfil: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_3B}}' then
    raise exception 'Las funciones de redes cambiaron después de la migración del Corte 3b: la reversa se niega a pisarlas; avise';
  end if;
end $$;

create or replace view redes.v_epicrisis as
{{VISTA_EPICRISIS_3A}};

{{FUNCION_ACTIVO_BUSCAR_3A}};

drop function public.geoportal_redes_perfil(text, text);
drop function public.geoportal_redes_galeria(text, text, integer);
drop function public.geoportal_redes_ficha_editar(text, text, jsonb, text);
drop function public.geoportal_redes_foto_perfil_preparar(text, text);
drop function public.geoportal_redes_foto_perfil_fijar(text, text, text, text);
drop function redes.f_foto_principal(bigint);
drop function redes.f_texto_valor(text, text, text);
drop function redes.f_editor_ficha(text);
drop function redes.f_fotos_activo(bigint);
drop view redes.v_activo_identificadores;
drop table redes.activo_fotos_perfil, redes.foto_perfil_preparaciones, redes.activo_identificador_eventos, redes.ficha_ediciones;

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_3A}}'
     or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> '{{MD5_V_EPICRISIS_3A}}' then
    raise exception 'La reversa no dejó redes como en el Corte 3a';
  end if;
end $$;
