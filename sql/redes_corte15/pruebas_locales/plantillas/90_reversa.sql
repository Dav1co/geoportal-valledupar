-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja tecnica.f_avisos y redes.f_publicar_l116 como estaban (texto exacto), quita los 4 disparadores, las {{N_NUEVAS}} funciones, la vista y las 7 tablas, y DESACTIVA el tipo «sin_agua».
-- SE NIEGA si alguna función cambió después de la migración, si ya se declaró algún evento, o si alguien ajustó la lista de lo que se asocia o los
-- sectores de una planta (la reversa no borra hechos: avise). Antes, devuelva la Edge a la anterior.
-- =====================================================================
do $$
begin
  if to_regclass('redes.eventos_suspension') is null then raise exception 'No hay nada que revertir: el Corte 15 no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_15}}'
     or md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamptz)'::regprocedure)) <> '{{MD5_AVISOS_15}}'
     or md5(pg_get_functiondef('redes.f_publicar_l116(bigint,text,text)'::regprocedure)) <> '{{MD5_PUBLICAR_15}}' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 15: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.eventos_suspension) then raise exception 'Ya hay eventos de suspensión declarados: la reversa no borra hechos; avise'; end if;
  if exists (select 1 from redes.evento_tipo_eventos) or exists (select 1 from redes.planta_sector_eventos) then
    raise exception 'Ya se ajustó la lista de lo que se asocia o los sectores de una planta: la reversa no borra hechos; avise';
  end if;
end $$;

-- 1. tecnica.f_avisos, con su texto de antes (antes de quitar las funciones nuevas, que la del 15 usa)
{{TEXTO_AVISOS_ANTES}}
-- 1b. redes.f_publicar_l116, con su texto de antes (el del Corte 5d)
{{TEXTO_PUBLICAR_ANTES}}
-- 2. los disparadores y lo nuevo (las tablas de hechos están vacías: lo comprobó la guardia)
drop trigger t_evento_asociar on redes.reporte_externo_eventos;
drop trigger t_evento_asociar on redes.l116_eventos;
drop trigger t_evento_asociar on redes.danos;
drop trigger t_evento_asociar on campo.reportes;
{{DROPS}}
drop view redes.v_evento_suspension;
{{DROP_TABLAS}}
-- 3. el tipo «sin_agua» no se borra: se desactiva. El consecutivo y los parámetros quedan (marcados sin uso)
update campo.tipos_reporte set activo = false where codigo = 'sin_agua';
update redes.parametros set descripcion = 'Sin uso (reversa del Corte 15)' where clave in ({{PARAMETROS}});
update tecnica.aviso_parametros set descripcion = 'Sin uso (reversa del Corte 15).' where clave = 'sin_agua_ventana_h';
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte15', 'reversa_redes_corte15', null, jsonb_build_object('motivo', 'reversa del Corte 15'), null);
