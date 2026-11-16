-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja campo.f_autorizar_reporte y tecnica.f_formularios con su texto anterior, el dominio con sus 7 claves, la vista del geovisor vacía (como en el 6b), sin las
-- funciones nuevas y sin la columna «area». Los dos tipos agregados NO se borran: se desactivan.
-- SE NIEGA (nada se borra) si ya hay reportes hechos desde Técnica o si alguien tiene asignado un formulario compartido.
-- =====================================================================
do $$
begin
  if to_regprocedure('campo.f_tecnica_claves(text)') is null then raise exception 'No hay nada que revertir: el Corte 8 no está aplicado'; end if;
  if exists (select 1 from campo.reportes where area is not null) then raise exception 'Ya hay reportes hechos desde Técnica: la reversa se niega (nada se borra)'; end if;
  if exists (select 1 from tecnica.personal_tecnico_eventos where formulario in ('anomalia_compartida', 'revision_compartida')) then
    raise exception 'Ya hay personas con un formulario compartido asignado: la reversa se niega (nada se borra)';
  end if;
  if (select count(*) from (values {{CAMBIADAS_8}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2
     or (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 6 then
    raise exception 'Las funciones cambiaron después de la migración del Corte 8: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. la vista del geovisor, vacía como la dejó el 6b
create or replace view redes.v_reportes_comercial as
select null::text as codigo, null::text as tipo, null::text as subtipo, null::text as area, null::boolean as con_contrato, null::text as estado,
       null::timestamptz as registrado_en, null::numeric(9, 6) as lat, null::numeric(9, 6) as lon
 where false;
comment on view redes.v_reportes_comercial is 'Corte 6b: capa de reportes de Comercial del geovisor, vacía hasta el Corte 8. Sin datos del suscriptor ni textos.';

-- 2. las 2 funciones reemplazadas, con su texto anterior
{{TEXTOS_ANTES}}
-- 3. lo nuevo
drop function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamptz);
drop function public.geoportal_campo_tec_preparar_subida(text, integer, text, text);
drop function public.geoportal_campo_tec_formulario(text);
drop function campo.f_tecnica_entrar(text, text);
drop function campo.f_tecnica_claves(text);
drop function campo.f_tipo_general(text);
alter domain tecnica.formulario_clave drop constraint formulario_clave_ck;
alter domain tecnica.formulario_clave add constraint formulario_clave_ck check (value in ('entrada', 'salida', 'muestreo', 'danos_fallas', 'mantenimiento', 'uso_quimicos', 'entrada_quimicos'));
alter table campo.reportes alter column area drop default;
alter table campo.reportes drop constraint reportes_area_ck;
alter table campo.reportes drop column area;      -- vacía: la guardia de arriba comprobó que ningún reporte la usa
update campo.tipos_reporte set activo = false where codigo in ('fuga_acometida', 'caja_medidor_danada') and activo;      -- no se borran: se desactivan

do $$
begin
  if md5(pg_get_functiondef('campo.f_autorizar_reporte(text)'::regprocedure)) <> '{{MD5_AUTORIZAR}}' or md5(pg_get_functiondef('tecnica.f_formularios()'::regprocedure)) <> '{{MD5_FORMULARIOS}}'
     or (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') <> '{{DEF_DOMINIO}}' then
    raise exception 'La reversa no dejó las funciones o el dominio como estaban';
  end if;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values ('migracion@tecnica_corte8', 'reversa_tecnica_corte8', null, '{}'::jsonb, null);
