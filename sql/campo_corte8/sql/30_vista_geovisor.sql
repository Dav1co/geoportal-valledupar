-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 30 — LA CAPA «REPORTES DE COMERCIAL» DEL GEOVISOR (§30.4): se reemplaza la vista vacía del 6b, con las mismas columnas.
-- Lo que muestra: los reportes de anomalía (reporte general) y las revisiones generales de campo.reportes, de Comercial y de Técnica, que no estén ocultos.
-- SIN datos del suscriptor: no lleva el número de contrato (solo si lo trae: azul con contrato, rojo posible clandestino), ni la descripción, ni fotos, ni autor.
-- Ninguna función de redes cambia: geoportal_redes_geovisor_capa ya lee esta vista.
-- =====================================================================
create or replace view redes.v_reportes_comercial as
select coalesce(e.consecutivo, 'REP-' || lpad(e.seq::text, 6, '0'))::text as codigo,
       t.nombre::text as tipo,
       s.nombre::text as subtipo,
       coalesce(r.area, 'comercial')::text as area,
       (e.contrato is not null) as con_contrato,
       coalesce(x.nombre, e.estado)::text as estado,
       e.registrado_en,
       e.lat::numeric(9, 6) as lat,
       e.lon::numeric(9, 6) as lon
  from campo.v_reportes_estado e
  join campo.reportes r on r.id = e.id
  join campo.tipos_reporte t on t.id = e.tipo_id
  left join campo.subtipos_reporte s on s.id = e.subtipo_id
  left join campo.estados_reporte x on x.codigo = e.estado
 where not e.oculto
   and (t.codigo = 'revision_previa' or campo.f_tipo_general(t.codigo));
comment on view redes.v_reportes_comercial is 'Corte 8: reportes de anomalía y revisiones generales de campo.reportes para el geovisor técnico. Sin contrato, descripción, fotos ni autor.';
