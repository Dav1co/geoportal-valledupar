-- =====================================================================
-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · 90 — REVERSA
-- Vuelve las dos RPC a los textos publicados el 21-nov (fc362a28…, 7028ce40…) y quita la función interna nueva.
-- No hay tablas ni datos nuevos: los cambios de cargo y área que hayan hecho los supervisores quedan como eventos (nada se borra).
-- =====================================================================
do $$
begin
  if to_regprocedure('campo.f_supervisor_comercial(text)') is null then
    raise exception 'El cambio de cargo y área por el supervisor no está aplicado (no existe campo.f_supervisor_comercial): no hay nada que revertir';
  end if;
  if md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)'))) is distinct from '{{MD5_FIJAR_NUEVA}}'
     or md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal(text,jsonb,text)'))) is distinct from '{{MD5_PERSONAL_NUEVA}}' then
    raise exception 'geoportal_campo_personal_fijar o geoportal_campo_personal cambiaron después de este paquete: la reversa no las pisa; deténgase y avise';
  end if;
end $$;

{{RESPALDO_FIJAR}}

{{RESPALDO_PERSONAL}}

-- DROP (por qué y alcance): campo.f_supervisor_comercial(text) la creó este paquete y, con las dos RPC ya devueltas a su texto publicado, nadie la usa.
-- Alcance: SOLO esa función (una firma); no toca tablas, datos ni otras funciones.
drop function campo.f_supervisor_comercial(text);
