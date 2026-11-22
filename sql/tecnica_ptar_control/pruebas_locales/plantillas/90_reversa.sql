-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 · 90 — REVERSA. Solo si la Caracterización NO tiene registros (nada se borra: con datos, se detiene).
-- Vuelve las cinco funciones reemplazadas a como estaban (f_formularios, f_tipo_punto_texto, f_autorizar_captura, geoportal_tec_ptar_mapa y _elemento), quita las dos nuevas
-- y DESACTIVA (no borra) lo que se agregó: el formulario, su configuración, los cuatro puntos y las nueve variables. El dominio y los CHECK conservan «ptar_caracterizacion» y
-- «ptar», porque quedan filas (inactivas) que los usan.
-- =====================================================================
do $$
begin
  if to_regprocedure('tecnica.f_parametros_punto(bigint,integer)') is null then raise exception 'REVERSA PTAR-3: el paquete no está aplicado'; end if;
  if exists (select 1 from tecnica.registros r join tecnica.variables v on v.id = r.variable_id where v.codigo like 'ar\_%') then
    raise exception 'REVERSA PTAR-3: la Caracterización ya tiene registros. No se borra nada: avise';
  end if;
end $$;
{{RESTAURAR}}
drop function tecnica.f_estado_parametros(jsonb);
drop function tecnica.f_parametros_punto(bigint, integer);
update tecnica.formulario_variables set activa = false where formulario = 'ptar_caracterizacion' and activa;
update tecnica.formularios_config set activa = false where formulario = 'ptar_caracterizacion' and activa;
update tecnica.puntos set activo = false where tipo = 'ptar' and codigo in ('PTAR-AFL', 'PTAR-EFL', 'PTAR-RIO-ARR', 'PTAR-RIO-ABJ') and activo;
update tecnica.variables set activa = false where codigo like 'ar\_%' and activa;
do $$
begin
  if {{COMPROBAR}} then raise exception 'REVERSA PTAR-3: las funciones no quedaron como antes'; end if;
end $$;
