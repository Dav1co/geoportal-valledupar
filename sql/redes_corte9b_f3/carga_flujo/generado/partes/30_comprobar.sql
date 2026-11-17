-- Corte 9b · Fase 3 · carga del flujo del modelo · 2. comprobaciones «N de N». Generado por carga_flujo.py. Si alguna falla, ERROR: la transacción no queda.
select set_config('redes.flujo_solicitante', lower(:'solicitante'), true) as quien \gset
do $$
declare v_q text := current_setting('redes.flujo_solicitante'); v_c bigint := redes.f_ref_vigente('flujo_modelo'); v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_ms4 numeric;
        v_j jsonb; v_f jsonb; v_cod text; v_z integer := floor(redes.f_param('geovisor_zoom_red_completa'))::integer; v_x integer; v_y integer; v_m1 text; v_m2 text;
        v_total integer; v_bien integer; v_fallas text; v_info text;
begin
  create temp table _fl_r (n integer, nombre text, ok boolean, detalle text) on commit drop;
  -- la tesela con más red, al zoom desde el que se ve toda, en las dos horas; la información de la capa y la tarjeta de un tramo
  select t.x, t.y into v_x, v_y from (
    select floor((ST_X(ST_PointOnSurface(m.geom)) + 180) / 360 * (1 << v_z))::integer as x,
           floor((1 - ln(tan(radians(ST_Y(ST_PointOnSurface(m.geom)))) + 1 / cos(radians(ST_Y(ST_PointOnSurface(m.geom))))) / pi()) / 2 * (1 << v_z))::integer as y
      from redes.activo_vigente_mat m join redes.flujo_modelo f on f.carga_id = v_c and f.activo_id = m.activo_id where not m.retirado) t group by t.x, t.y order by count(*) desc limit 1;
  v_t0 := clock_timestamp(); v_m1 := public.geoportal_redes_geovisor_mvt_flujo(v_q, 'mayor', v_z, v_x, v_y); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_m2 := public.geoportal_redes_geovisor_mvt_flujo(v_q, 'menor', v_z, v_x, v_y); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_j := public.geoportal_redes_flujo_modelo(v_q); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  select a.codigo into v_cod from redes.flujo_modelo f join redes.activos a on a.id = f.activo_id where f.carga_id = v_c and f.sentido_mayor <> 'sin_flujo' order by abs(f.q_mayor_lps) desc, f.llave limit 1;
  v_t0 := clock_timestamp(); v_f := public.geoportal_redes_flujo_tramo(v_q, v_cod); v_ms4 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS: tesela más cargada %s/%s/%s hora mayor %s ms (%s kB) · hora menor %s ms (%s kB) · información de la capa %s ms · tarjeta de %s %s ms',
                   v_z, v_x, v_y, v_ms1, round(length(v_m1) * 0.75 / 1024), v_ms2, round(length(v_m2) * 0.75 / 1024), v_ms3, v_cod, v_ms4);
  insert into _fl_r values
  (1, '01 el flujo vigente es el de este paquete (flujo_modelo_v1.csv, md5 2b0b8616…): 9580 tubos',
      (select md5 from redes.v_ref_carga_vigente where conjunto = 'flujo_modelo') = '2b0b8616697e22427f7019f766de1448' and (select count(*) from redes.flujo_modelo where carga_id = v_c) = 9580,
      (select count(*)::text from redes.flujo_modelo where carga_id = v_c)),
  (2, '02 los 8669 tubos que amarran son tramos de acueducto de esta base (por su código): ninguno quedó sin su tramo',
      current_setting('redes.flujo_sin_activo')::integer = 0 and (select count(activo_id) from redes.flujo_modelo where carga_id = v_c) = 8669,
      current_setting('redes.flujo_sin_activo') || ' código(s) del análisis sin tramo; amarrados ' || (select count(activo_id) from redes.flujo_modelo where carga_id = v_c)),
  (3, '03 3747 amarran por la llave y 4922 por geometría; 911 tubos del modelo quedan sin tramo (no se dibujan); 1 con la geometría al revés del tubo',
      (select count(*) filter (where amarre = 'llave') = 3747 and count(*) filter (where amarre = 'geometria') = 4922 and count(*) filter (where activo_id is null) = 911
              and count(*) filter (where geom_mismo is false) = 1 from redes.flujo_modelo where carga_id = v_c), null),
  (4, '04 las horas: mayor consumo a las 17:00 y menor a las 23:00',
      (select string_agg(cual || '=' || hora, ',' order by cual) from redes.flujo_modelo_horas where carga_id = v_c) = 'mayor=17,menor=23', null),
  (5, '05 sin flujo: 894 tubos en la hora mayor y 898 en la menor; 132 tramos cambian de sentido entre las dos horas',
      (select count(*) filter (where sentido_mayor = 'sin_flujo') = 894 and count(*) filter (where sentido_menor = 'sin_flujo') = 898
              and count(*) filter (where activo_id is not null and sentido_mayor <> sentido_menor and 'sin_flujo' not in (sentido_mayor, sentido_menor)) = 132
         from redes.flujo_modelo where carga_id = v_c), null),
  (6, '06 ningún tramo de la red con dos tubos; los tramos amarrados que hoy están retirados u ocultos no se dibujan (informativo)',
      not exists (select 1 from redes.flujo_modelo where carga_id = v_c and activo_id is not null group by activo_id having count(*) > 1),
      (select count(*) || ' amarrados a tramos retirados u ocultos' from redes.flujo_modelo f join redes.activo_vigente_mat m on m.activo_id = f.activo_id where f.carga_id = v_c and (m.retirado or m.oculto))),
  (7, '07 la información de la capa: cargada, con el rótulo «Modelo, no medido (modeloV1, Plan Maestro 2014)» y la cobertura',
      (v_j ->> 'cargado')::boolean and v_j ->> 'rotulo' = 'Modelo, no medido (modeloV1, Plan Maestro 2014)' and (v_j -> 'cobertura' ->> 'con_tramo')::integer = 8669,
      v_j ->> 'cobertura'),
  (8, '08 la tarjeta del tramo de más caudal trae las dos horas', (v_f ->> 'en_modelo')::boolean and jsonb_array_length(v_f -> 'horas') = 2, v_f::text),
  (9, '09 TIEMPOS: las teselas de las dos horas, la información y la tarjeta, cada una en menos de 1 s',
      length(v_m1) > 0 and greatest(v_ms1, v_ms2, v_ms3, v_ms4) < 1000, v_info),
  (10, '10 no cambió la ficha de ningún activo (ni versiones ni eventos nuevos por esta carga)',
      not exists (select 1 from redes.activo_versiones v where v.creado_en >= (select creado_en from redes.ref_cargas where id = v_c)), null);
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by n) filter (where not ok), '') into v_total, v_bien, v_fallas from _fl_r;
  if current_setting('redes.flujo_ensayo', true) = 'si' then
    raise exception E'CARGA DEL FLUJO DEL MODELO · CORTE 9b, Fase 3 (ENSAYO: este ERROR es el esperado y deshace todo)\n%\n%\nRESULTADO: % de % comprobaciones correctas — %', v_fallas, v_info, v_bien, v_total,
      case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
  elsif v_bien <> v_total then
    raise exception E'CARGA DEL FLUJO DEL MODELO: % FALLA(S); no se carga nada\n%', v_total - v_bien, v_fallas;
  end if;
  raise warning E'CARGA DEL FLUJO DEL MODELO · CORTE 9b, Fase 3\n%\nRESULTADO: % de % comprobaciones correctas — SIN FALLAS', v_info, v_bien, v_total;
end $$;
