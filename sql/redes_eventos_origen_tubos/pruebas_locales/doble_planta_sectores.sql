-- Doble local de los sectores por planta de producción (allí: 36 sectores × 2 plantas = 72 filas activas, asignadas con planta_sectores_fijar).
-- Aquí: 3 sectores ZTBASE en un rincón de la caja de la red, asignados a las dos plantas con la RPC PUBLICADA (deja su historial, como en producción).
do $$
declare v_c bigint; v_id bigint; v_cod text; g geometry; i integer; q text := 'ztbase.admin@emdupar.gov.co'; v_cods text[] := '{}';
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (q, 'ZTBASE Admin', 'admin', 'sin_restriccion', 'todos') on conflict do nothing;
  select ST_Envelope(ST_Extent(geom)) into g from redes.activo_vigente_mat where prefijo = 'RED';
  for i in 1..3 loop
    update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'SEC' returning ultimo into v_c;
    v_cod := 'SEC-' || lpad(v_c::text, 6, '0');
    insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, 'SEC', 'carga', q) returning id into v_id;
    insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, estado_codigo, atributos, huella, autor)
    values (v_id, 1, ST_Multi(ST_MakeEnvelope(ST_XMax(g) - 0.01 * i, ST_YMax(g) - 0.01, ST_XMax(g) - 0.01 * (i - 1), ST_YMax(g), 4326)), 'ZTBASE Sector ' || i, 'sector', 'en_operacion',
            jsonb_build_object('modelo', jsonb_build_object('sector', 90 + i)), md5(v_cod), q);
    insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZTBASE doble de los sectores', q);
    perform redes.f_mat_refrescar_uno(v_id);
    v_cods := v_cods || v_cod;
  end loop;
  perform public.geoportal_redes_planta_sectores_fijar(q, pl.codigo, v_cods, 'ZTBASE doble de producción: los sectores de la planta') from tecnica.plantas pl where pl.activa;
end $$;
