-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las 2 RPC como las dejó el 7a, quita las 5 funciones nuevas, las 2 tablas y la columna de la foto. El parámetro max_bytes_remision se queda.
-- SE NIEGA (nada se borra) si ya hay entradas con foto, fotos reservadas o cambios de parámetros.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.quimico_parametro_eventos') is null then raise exception 'No hay nada que revertir: el Corte 7c no está aplicado'; end if;
  if exists (select 1 from tecnica.quimico_parametro_eventos) or exists (select 1 from tecnica.quimico_remision_preparaciones)
     or exists (select 1 from tecnica.quimico_movimientos where remision_foto is not null) then
    raise exception 'Ya hay fotos de remisión o cambios de parámetros: la reversa se niega (nada se borra)';
  end if;
  if (select count(*) from (values {{CAMBIADAS_7C}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2
     or (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 5 then
    raise exception 'Las funciones cambiaron después de la migración del Corte 7c: la reversa se niega a pisarlas; avise';
  end if;
end $$;
-- 1. las 2 RPC reemplazadas, con su texto del 7a
{{TEXTOS_ANTES}}
-- 2. lo nuevo
drop function public.geoportal_tec_quimico_parametro_fijar(text, text, numeric, text);
drop function public.geoportal_tec_quimico_parametros(text);
drop function public.geoportal_tec_quimico_remision_preparar(text);
drop function tecnica.f_qparam_editable(text);
drop function tecnica.f_remision_subida(text, text);
drop index tecnica.ux_qmov_remision_foto;
alter table tecnica.quimico_movimientos drop constraint quimico_movimientos_remision_foto_ck;
alter table tecnica.quimico_movimientos drop column remision_foto;      -- vacía: la guardia de arriba lo comprobó
drop table tecnica.quimico_remision_preparaciones;
drop table tecnica.quimico_parametro_eventos;
do $$
begin
  if (select count(*) from (values {{CAMBIADAS_ANTES}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2 then raise exception 'La reversa no dejó las RPC como en el 7a'; end if;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values ('migracion@tecnica_corte7c', 'reversa_tecnica_corte7c', null, '{}'::jsonb, null);
