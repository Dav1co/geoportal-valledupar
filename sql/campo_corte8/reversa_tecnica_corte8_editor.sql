begin;
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
  if (select count(*) from (values ('campo.f_autorizar_reporte(text)', '097a21e90766512921f185d213f3c779'), ('tecnica.f_formularios()', 'a20a338b69efbcfbb5e90df54b1cb14d')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2
     or (select count(*) from (values ('campo.f_tipo_general(text)', '4ede0bf1f2a69982fb033cea893b84e2'), ('campo.f_tecnica_claves(text)', '98c2f200b97968a30d9e2ba521c92d6b'), ('campo.f_tecnica_entrar(text,text)', '0b8a0b83e29192980e9d3f902e05b305'), ('public.geoportal_campo_tec_formulario(text)', 'edaee27220655f13ce9ecc193e42c4b1'), ('public.geoportal_campo_tec_preparar_subida(text,integer,text,text)', '52047247a4d6a68aba4140d3f293dd3d'), ('public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone)', '7281c4bbf3db56fdfc1c11bb42f645ff')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 6 then
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
CREATE OR REPLACE FUNCTION campo.f_autorizar_reporte(p_solicitante text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if campo.f_perfil(v_email) is null then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  return v_email;
end $function$;
revoke all on function campo.f_autorizar_reporte(text) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION tecnica.f_formularios()
 RETURNS TABLE(clave text, nombre text, descripcion text, orden integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  values ('entrada',          'Entrada',                           'Agua cruda que ingresa a las plantas.', 1),
         ('salida',           'Salida',                            'Agua tratada que sale de las plantas.', 2),
         ('muestreo',         'Muestreo',                          'Muestreo en los puntos de la red y los tanques.', 3),
         ('danos_fallas',     'Daños o fallas',                    'Daños o fallas en la planta.', 4),
         ('mantenimiento',    'Mantenimiento, reparación e inversión', 'Mantenimiento, reparación e inversión.', 5),
         ('uso_quimicos',     'Uso de químicos',                   'Químicos usados en el proceso.', 6),
         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7);
$function$;
revoke all on function tecnica.f_formularios() from public, anon, authenticated, service_role;

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
  if md5(pg_get_functiondef('campo.f_autorizar_reporte(text)'::regprocedure)) <> 'aac8af95274e11b2f3e5ed1eb1e5025a' or md5(pg_get_functiondef('tecnica.f_formularios()'::regprocedure)) <> '11b0b586919d0d7240d1dd84f3edbe6b'
     or (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') <> 'CHECK ((VALUE = ANY (ARRAY[''entrada''::text, ''salida''::text, ''muestreo''::text, ''danos_fallas''::text, ''mantenimiento''::text, ''uso_quimicos''::text, ''entrada_quimicos''::text])))' then
    raise exception 'La reversa no dejó las funciones o el dominio como estaban';
  end if;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values ('migracion@tecnica_corte8', 'reversa_tecnica_corte8', null, '{}'::jsonb, null);
commit;
