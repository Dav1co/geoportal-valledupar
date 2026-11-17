-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones reemplazadas como estaban (texto exacto), quita las {{N_NUEVAS}} nuevas y las 4 tablas (vacías), devuelve el CHECK de Comercial y desactiva el formulario.
-- SE NIEGA si alguna función cambió después de la migración, si ya hay puntos por levantar (la reversa no borra datos: avise) o si alguien tiene
-- asignado el formulario «activo_campo» (en Técnica o en Comercial).
-- =====================================================================
do $$
begin
  if to_regclass('redes.levantar_puntos') is null then raise exception 'No hay nada que revertir: el Corte 14 no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_14}}' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 14: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.levantar_puntos) or exists (select 1 from redes.levantar_preparaciones) then
    raise exception 'Ya hay puntos por levantar (o subidas preparadas): la reversa no borra datos; avise';
  end if;
  if exists (select 1 from tecnica.personal_tecnico_eventos where formulario = 'activo_campo') or exists (select 1 from campo.personal_eventos where formulario = 'activo_campo') then
    raise exception 'Ya hay personas con el formulario «Encontrar o reportar activo» en su historial: la reversa no borra hechos; avise';
  end if;
end $$;

-- 1. las funciones reemplazadas, con su texto de antes (antes de quitar las nuevas, que ellas usan)
{{TEXTOS_ANTES}}
-- 2. lo nuevo (las tablas están vacías: lo comprobó la guardia)
{{DROPS}}
drop view redes.v_levantar_punto;
{{DROP_TABLAS}}
-- 3. el CHECK de Comercial, como estaba. El formulario de distribución se DESACTIVA (no se borra: nada se borra) y por eso el dominio de Técnica conserva
--    la clave «activo_campo» (sin el formulario activo no se puede asignar ni usar). Una nueva migración del 14 lo vuelve a activar.
alter table campo.personal_eventos drop constraint personal_eventos_formulario_check;
alter table campo.personal_eventos add constraint personal_eventos_formulario_check {{DEF_CHECK_CAMPO_SQL}};
update redes.formularios_distribucion set activo = false where clave = 'activo_campo';
-- 4. los parámetros y el consecutivo no se borran: quedan marcados sin uso
update redes.parametros set descripcion = 'Sin uso (reversa del Corte 14)' where clave in ({{PARAMETROS}});
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte14', 'reversa_redes_corte14', null, jsonb_build_object('motivo', 'reversa del Corte 14'), null);
