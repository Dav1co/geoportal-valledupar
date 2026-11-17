-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 90 — REVERSA (PROPUESTA). Quita las {{N_NUEVAS}} funciones, la vista y las 5 tablas (sin hechos) y vuelve a mostrar la capa de cortes.
-- SE NIEGA si alguna función cambió después de la migración o si ya hay usuarios sensibles o lecturas guardadas (la reversa no borra datos: avise).
-- =====================================================================
do $$
begin
  if to_regclass('redes.usuarios_sensibles') is null then raise exception 'No hay nada que revertir: la Fase 2 del Corte 9b no está aplicada'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_F2}}' then
    raise exception 'Las funciones cambiaron después de la migración de la Fase 2: la reversa se niega a pisarlas; avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure)) <> '{{MD5_AVISOS_F2}}' then
    raise exception 'tecnica.f_avisos cambió después de la migración de la Fase 2: la reversa se niega a pisarla; avise';
  end if;
  if exists (select 1 from redes.usuarios_sensibles) or exists (select 1 from redes.sensor_lecturas) then
    raise exception 'Ya hay usuarios sensibles o lecturas guardadas: la reversa no borra datos; avise';
  end if;
end $$;
-- tecnica.f_avisos vuelve a su texto del 9b (1b), sin el aviso de presiones
{{TEXTO_AVISOS_ANTES}}
revoke all on function tecnica.f_avisos(boolean, boolean, timestamptz) from public, anon, authenticated, service_role;
{{DROPS}}
drop view redes.v_usuario_sensible;
drop table redes.usuario_sensible_eventos, redes.usuarios_sensibles, redes.tipos_sensible, redes.presion_trabajo, redes.sensor_lecturas;
update redes.parametros set descripcion = 'Sin uso (reversa del Corte 9b, Fase 2)' where clave in ('sensor_sin_senal_min', 'presion_lista_max');
update redes.geovisor_capas set activa = true, nota = null where codigo = 'cortes';
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte9b_f2', 'reversa_redes_corte9b_fase2', null, jsonb_build_object('motivo', 'reversa del Corte 9b (Fase 2)'), null);
