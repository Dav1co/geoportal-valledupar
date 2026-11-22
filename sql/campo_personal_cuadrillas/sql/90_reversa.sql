-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 90 — REVERSA
-- Vuelve geoportal_campo_personal y geoportal_campo_historial_personal a los textos publicados (f8a83b02…, e82377f5…) y quita las RPC y funciones nuevas.
-- Nada se borra: si ya hay datos (cuadrillas, eventos nuevos de Personal o cambios de catálogo hechos por personas), las tablas, la columna «valor»
-- y los CHECK nuevos SE CONSERVAN (la migración se puede volver a aplicar encima). Solo si no hay datos se retiran tablas, columna y CHECK.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_campo_cuadrillas(text,jsonb,text)') is null then
    raise exception 'Personal y cuadrillas de Comercial no está aplicado (no existe geoportal_campo_cuadrillas): no hay nada que revertir';
  end if;
end $$;

{{RESPALDO_PERSONAL}}

{{RESPALDO_HISTORIAL}}

drop function public.geoportal_campo_personal_fijar(text, text, text, jsonb, text);
drop function public.geoportal_campo_cuadrillas(text, jsonb, text);
drop function public.geoportal_campo_cuadrilla_cambiar(text, jsonb, text);
drop function public.geoportal_campo_catalogos(text, text);
drop function public.geoportal_campo_catalogo_cambiar(text, jsonb, text);
drop function public.geoportal_campo_personal_actividad(text, text, text);
drop function campo.f_quien_puede(text);
drop function campo.f_actividades_persona(text);
drop function campo.f_miembros_cuadrillas();
drop function campo.f_cuadrilla_actividades(bigint);
drop function campo.f_actividades_propias(text);
drop function campo.f_cuadrilla_vigente(text);
drop function campo.f_area_vigente(text);
drop function campo.f_persona_comercial(text);
drop function campo.f_codigo_desde_nombre(text);
drop function campo.f_motivo_personal(text, boolean);

do $$
begin
  if exists (select 1 from campo.personal_eventos where tipo_evento in ('fijar_area', 'fijar_cuadrilla', 'asignar_actividad', 'quitar_actividad'))
     or exists (select 1 from campo.cuadrillas) or exists (select 1 from campo.catalogo_eventos where autor <> 'migracion@geoportal') then
    raise notice 'Hay datos de cuadrillas, actividades o áreas: las tablas, la columna valor y los CHECK nuevos se conservan (nada se borra)';
  else
    drop table campo.cuadrilla_eventos;
    drop table campo.cuadrillas;
    drop table campo.catalogo_eventos;
    drop table campo.actividades;
    drop table campo.areas_comercial;
    drop function campo.f_no_borrar_catalogo();
    alter table campo.personal_eventos drop constraint personal_ev_ck;
    alter table campo.personal_eventos drop constraint personal_eventos_tipo_evento_check;
    drop index campo.personal_eventos_tipo_valor_idx;
    alter table campo.personal_eventos drop column valor;
    alter table campo.personal_eventos add constraint personal_eventos_tipo_evento_check check (tipo_evento in ('fijar_cargo', 'asignar_formulario', 'quitar_formulario'));
    alter table campo.personal_eventos add constraint personal_ev_ck check (((tipo_evento = 'fijar_cargo') = (cargo is not null)) and ((tipo_evento = 'fijar_cargo') = (formulario is null))
                                     and (tipo_evento <> 'quitar_formulario' or motivo is not null));
  end if;
end $$;
