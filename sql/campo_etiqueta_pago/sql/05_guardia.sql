-- =====================================================================
-- ETIQUETA DEL ÚLTIMO PAGO (Code A, 27-nov) · 05 — GUARDIA: se detiene sin cambiar nada si la base no es la publicada
-- Huella de campo {{HUELLA_CAMPO}} (Consultar direcciones publicado), ordenada con collate "C"; md5 de la función que se reemplaza; la línea que cambia está
-- una sola vez; la ficha guarda ultimo_pago como jsonb.
-- =====================================================================
do $guardia$
declare v text;
begin
  select ({{HUELLA_CAMPO_Q}}) into v;
  if v = '{{HUELLA_CAMPO_NUEVA}}' then
    raise exception 'Este paquete ya parece aplicado (la huella de campo es la de este cambio): use la reversa antes de repetir';
  end if;
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_CAMPO}}' then
    raise exception 'Las funciones de campo no son las publicadas (huella {{HUELLA_CAMPO}}; hay %): deténgase y avise', v;
  end if;
  if to_regprocedure('{{FUNCION}}') is null or md5(pg_get_functiondef(to_regprocedure('{{FUNCION}}'))) is distinct from '{{MD5_VIEJA}}' then
    raise exception 'La función {{FUNCION}} no es la publicada: deténgase y avise';
  end if;
  if (select count(*) from regexp_matches(pg_get_functiondef(to_regprocedure('{{FUNCION}}')), 'f\.ultimo_pago - ''corte'' \|\|', 'g')) <> 1 then
    raise exception 'La línea del pago no está una sola vez en {{FUNCION}}: deténgase y avise';
  end if;
  if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass('bi_interno.ficha_contrato') and a.attname = 'ultimo_pago' and not a.attisdropped and a.atttypid = 'jsonb'::regtype) then
    raise exception 'bi_interno.ficha_contrato.ultimo_pago no existe o no es jsonb: deténgase y avise';
  end if;
end $guardia$;
