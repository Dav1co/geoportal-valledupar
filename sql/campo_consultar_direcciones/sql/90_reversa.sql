-- =====================================================================
-- CONSULTAR DIRECCIONES (Code A, 25-nov) · 90 — REVERSA
-- Devuelve las 7 funciones a su texto publicado y quita las 4 nuevas. La huella de campo vuelve a {{HUELLA_CAMPO}}.
-- NADA SE BORRA: campo.reporte_direccion_contrato (con sus filas), la columna campo.consultas_analisis.via (con lo registrado) y el parámetro
-- limite_direccion_hora se conservan. Ojo: con la función publicada de «observar», una dirección pedida desde un formato vuelve a contar como «consultado».
-- =====================================================================
do $rev$
declare r record; v_n bigint;
begin
  for r in select * from (values {{MD5_CAMBIAN_NUEVA}}) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise', r.f;
    end if;
  end loop;
  select count(*) into v_n from campo.consultas_analisis where via = 'formato';
  raise notice 'Reversa de consultar direcciones: % consultas desde formatos quedan en la bitácora (via = formato) y las fotos de direcciones en campo.reporte_direccion_contrato', v_n;
end $rev$;

{{RESPALDOS}}

-- DROP (por qué y alcance): las 4 funciones las creó este paquete; con las publicadas de vuelta, nadie las usa. Alcance: SOLO esas 4 firmas; no toca tablas ni datos.
drop function public.geoportal_campo_tec_direccion_contrato(text, text, text);
drop function public.geoportal_campo_direccion_contrato(text, text, text);
drop function campo.f_direcciones_contrato(text);
drop function campo.f_texto_censo(text, boolean);
