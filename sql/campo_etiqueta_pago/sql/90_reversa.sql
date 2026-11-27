-- =====================================================================
-- ETIQUETA DEL ÚLTIMO PAGO (Code A, 27-nov) · 90 — REVERSA
-- Devuelve geoportal_campo_analisis_contrato a su texto publicado (md5 {{MD5_VIEJA}}); la huella de campo vuelve a {{HUELLA_CAMPO}}. No toca tablas ni datos.
-- Con la Edge y la pantalla de este paquete, sin el campo la pantalla vuelve a mostrar el periodo del consumo.
-- =====================================================================
do $rev$
begin
  if to_regprocedure('{{FUNCION}}') is null or md5(pg_get_functiondef(to_regprocedure('{{FUNCION}}'))) is distinct from '{{MD5_NUEVA}}' then
    raise exception 'La función {{FUNCION}} no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise';
  end if;
end $rev$;

{{FUNCION_VIEJA}}
