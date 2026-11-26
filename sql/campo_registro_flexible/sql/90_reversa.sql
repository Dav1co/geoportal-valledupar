-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 90 — REVERSA
-- Devuelve crear_reporte y la entrada de Técnica a su firma y texto publicados, y la lista, el detalle, la descarga, los datos del PDF y la lista de derivadas a
-- su texto publicado; quita las 5 funciones nuevas (filtro y correos de las derivadas, y las 3 de la descarga auditada). La huella de campo vuelve a {{HUELLA_CAMPO}}.
-- NADA SE BORRA: campo.reporte_registro y la columna campo.reporte_fotos.origen se conservan con sus datos (las funciones publicadas no las leen; el sello del
-- PDF de cualquier reporte vuelve a ser el de antes porque campo.reportes no cambió).
-- =====================================================================
do $rev$
declare r record; v_xy bigint; v_adj bigint;
begin
  for r in select * from (values {{MD5_CAMBIAN_NUEVA}}) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise', r.f;
    end if;
  end loop;
  select count(*) filter (where xy_manual) into v_xy from campo.reporte_registro;
  select count(*) into v_adj from campo.reporte_fotos where origen <> 'camara';
  raise notice 'Reversa del registro flexible: % reportes con XY digitado y % fotos adjuntadas conservan su marca en campo.reporte_registro y campo.reporte_fotos.origen (las pantallas de antes no la muestran)', v_xy, v_adj;
end $rev$;

-- DROP (por qué y alcance): las dos firmas con p_registro las creó este paquete y se reemplazan aquí mismo por las publicadas. Alcance: SOLO esas 2 firmas.
drop function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone, jsonb);
drop function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone, jsonb);

{{RESPALDO_CREAR}}
revoke all on function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone)
  to service_role;

{{RESPALDO_TEC_CREAR}}
revoke all on function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone)
  to service_role;

{{RESPALDO_LISTAR}}

{{RESPALDO_OBTENER}}

{{RESPALDO_DESCARGA_PAGINA}}

{{RESPALDO_PDF_DATOS}}

{{RESPALDO_DERIVADAS}}

-- DROP (por qué y alcance): las 5 funciones las creó este paquete; con la lista de derivadas ya devuelta a su texto publicado, nadie las usa. Alcance: SOLO esas 5 firmas;
-- no toca tablas, datos ni otras funciones.
drop function public.geoportal_campo_derivadas_descarga_cerrar(text, bigint, integer, text, text);
drop function public.geoportal_campo_derivadas_descarga_pagina(text, bigint, bigint, integer);
drop function public.geoportal_campo_derivadas_descarga_iniciar(text, jsonb, text, boolean, text);
drop function campo.f_derivada_sin_correos(jsonb);
drop function campo.f_derivadas_filtradas(jsonb);
