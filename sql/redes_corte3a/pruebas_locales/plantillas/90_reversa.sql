-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja el esquema redes como lo dejó el Corte 2: devuelve preparar_dano, crear_dano, v_dano y v_epicrisis a su texto del Corte 2 y quita las
-- 8 RPC, las vistas, las tablas y las funciones del 3a. Los 11 parámetros nuevos se conservan (redes.parametros no deja borrar filas).
-- SE NIEGA si hay intervenciones, preparaciones, archivos de intervenciones en el bucket, activos creados por intervenciones o daños asociados
-- desde la bandeja (nada se borra; y sin el 3a, v_dano dejaría de ver el activo asociado), o si alguna función cambió.
-- =====================================================================
do $$
begin
  if to_regclass('redes.intervenciones') is null then raise exception 'No hay nada que revertir: no existe redes.intervenciones'; end if;
  if exists (select 1 from redes.intervenciones) or exists (select 1 from redes.intervencion_preparaciones)
     or exists (select 1 from storage.objects where bucket_id = 'redes-evidencias' and name like 'intervenciones/%')
     or exists (select 1 from redes.activos where origen_alta = 'intervencion') or exists (select 1 from redes.dano_eventos where tipo = 'asociar_activo') then
    raise exception 'Ya hay intervenciones, archivos, activos creados por intervenciones o daños asociados: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_3A}}' then
    raise exception 'Las funciones de redes cambiaron después de la migración del Corte 3a: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- la epicrisis y el daño vuelven al texto del Corte 2 (mismas columnas)
create or replace view redes.v_epicrisis as
{{VISTA_EPICRISIS_2}};
create or replace view redes.v_dano as
{{VISTA_DANO_2}};

-- preparar y crear el daño vuelven al texto del Corte 2 (la ACL no cambia con create or replace)
{{FUNCION_PREPARAR_DANO_2}};
{{FUNCION_CREAR_DANO_2}};

drop function public.geoportal_redes_formulario_intervencion(text);
drop function public.geoportal_redes_danos_abiertos(text, text, text, numeric, numeric);
drop function public.geoportal_redes_preparar_intervencion(text, integer, integer);
drop function public.geoportal_redes_crear_intervencion(text, uuid, jsonb, text);
drop function public.geoportal_redes_intervencion_recursos(text, text, jsonb, text);
drop function public.geoportal_redes_intervenciones(text, text, integer);
drop function public.geoportal_redes_no_identificados(text, integer);
drop function public.geoportal_redes_asociar_activo(text, text, text, text, text);
drop function redes.f_dano_elegible(redes.v_dano, text, bigint[], geometry);
drop function redes.f_fuentes_validas(jsonb, boolean, boolean);
drop function redes.f_activo_crear(text, geometry, text, text, numeric, text, date, jsonb, text, text, text, text);
drop function redes.f_mat_refrescar_uno(bigint);
drop function redes.f_supervisor(text, text);
drop view redes.v_no_identificados;
drop view redes.v_intervencion;
drop view redes.v_intervencion_fuentes;
drop table redes.intervencion_eventos, redes.intervencion_archivos, redes.intervencion_fuentes, redes.intervencion_materiales, redes.intervencion_activos,
           redes.intervenciones, redes.intervencion_preparaciones, redes.unidades_material, redes.tipos_intervencion;
drop function redes.f_intervencion_activo_coherente();
drop function redes.f_intervencion_coherente();

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_2}}'
     or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> '{{MD5_V_EPICRISIS_2}}' or md5(pg_get_viewdef('redes.v_dano'::regclass, true)) <> '{{MD5_V_DANO_2}}' then
    raise exception 'La reversa no dejó redes como en el Corte 2';
  end if;
end $$;
