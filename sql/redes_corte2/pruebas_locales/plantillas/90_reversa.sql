-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja el esquema redes como lo dejó el Corte 1a: quita las 8 RPC, las vistas y tablas de daños y del bot, el bucket, y devuelve
-- redes.v_epicrisis a su texto del 1a. Los 6 parámetros nuevos se conservan (redes.parametros no deja borrar filas).
-- SE NIEGA si hay daños, reportes del bot, filas en caudales_fuga u objetos en el bucket (nada se borra), o si alguna función cambió.
-- =====================================================================
do $$
begin
  if to_regclass('redes.danos') is null then raise exception 'No hay nada que revertir: no existe redes.danos'; end if;
  if exists (select 1 from redes.danos) or exists (select 1 from redes.reportes_externos) or exists (select 1 from redes.caudales_fuga)
     or exists (select 1 from storage.objects where bucket_id = 'redes-evidencias') then
    raise exception 'Ya hay daños, reportes del bot, caudales o fotos: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_2}}' then
    raise exception 'Las funciones de redes cambiaron después de la migración del Corte 2: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- la epicrisis vuelve al texto del 1a (mismas columnas; sin los daños)
create or replace view redes.v_epicrisis as
{{VISTA_EPICRISIS_1A}};

drop function public.geoportal_redes_formulario_dano(text);
drop function public.geoportal_redes_preparar_dano(text, integer);
drop function public.geoportal_redes_crear_dano(text, uuid, jsonb, text);
drop function public.geoportal_redes_activo_buscar(text, text, text, integer);
drop function public.geoportal_redes_tramo_nodos(text, text);
drop function public.geoportal_redes_mvt(text, integer, integer, integer, text);
drop function public.geoportal_redes_reporte_convertir(text, uuid, jsonb);
drop function public.geoportal_redes_reporte_descartar(text, uuid, text);
drop function redes.f_reporte_externo_recibir(jsonb);
drop function redes.f_instante(text, text);
drop view redes.v_reporte_externo;
drop view redes.v_dano;
drop view redes.v_dano_tiempos;
drop table redes.reporte_externo_eventos, redes.dano_fotos, redes.dano_eventos, redes.dano_tiempos, redes.dano_datos_sensibles, redes.danos, redes.dano_preparaciones,
           redes.reporte_externo_fotos, redes.reportes_externos, redes.caudales_fuga, redes.marcas_riesgo, redes.tipos_tercero, redes.causas, redes.tipos_rotura, redes.tipos_dano;
drop function redes.f_dano_coherente();
delete from storage.buckets where id = 'redes-evidencias';

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_1A}}'
     or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> '{{MD5_VISTA_1A}}' then
    raise exception 'La reversa no dejó redes como en el Corte 1a';
  end if;
end $$;
