-- Corte 10 · carga del inventario regulatorio · 3. comprobaciones «N de N». Generado por carga_val.py. Si alguna falla, ERROR: la transacción no queda.
select set_config('redes.val_solicitante', lower(:'solicitante'), true) as quien \gset
do $$
declare v_q text := current_setting('redes.val_solicitante'); v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_j jsonb; v_f jsonb; v_id bigint; v_cod text;
        v_z integer := floor(redes.f_param('geovisor_zoom_red_completa'))::integer; v_x integer; v_y integer; v_mvt text;
begin
  create temp table _val_r (n integer, nombre text, ok boolean, detalle text) on commit drop;
  -- la conciliación, como la pide la pantalla (con los topes de la Edge)
  v_t0 := clock_timestamp(); v_j := public.geoportal_redes_valoracion(v_q); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  -- la ficha de un tramo amarrado
  select am.activo_id, a.codigo into v_id, v_cod from redes.val_amarre am join redes.activos a on a.id = am.activo_id join redes.activo_vigente_mat m on m.activo_id = am.activo_id and not m.retirado
   where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'acueducto' and am.situacion = 'con_fila' and a.prefijo = 'RED' order by am.activo_id limit 1;
  v_t0 := clock_timestamp(); v_f := redes.f_ficha(v_id, 'admin'); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  -- la tesela con más red, al zoom desde el que se ve toda
  select t.x, t.y into v_x, v_y from (
    select floor((ST_X(ST_PointOnSurface(m.geom)) + 180) / 360 * (1 << v_z))::integer as x,
           floor((1 - ln(tan(radians(ST_Y(ST_PointOnSurface(m.geom)))) + 1 / cos(radians(ST_Y(ST_PointOnSurface(m.geom))))) / pi()) / 2 * (1 << v_z))::integer as y
      from redes.activo_vigente_mat m where m.prefijo in ('RED', 'COL') and not m.retirado) t group by t.x, t.y order by count(*) desc limit 1;
  v_t0 := clock_timestamp(); v_mvt := public.geoportal_redes_geovisor_mvt(v_q, v_z, v_x, v_y); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  insert into _val_r values
  (1, '01 la valoración vigente es la de este paquete: 3 hojas con 59, 39 y 68 filas',
      (select md5 from redes.v_ref_carga_vigente where conjunto = 'valoracion') = '16e6a5e96e756700de07e0c92cdf40c3'
      and (select string_agg(h.hoja || '=' || (select count(*) from redes.val_filas f where f.carga_id = h.carga_id and f.hoja = h.hoja), ',' order by h.hoja)
             from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion')) = 'acueducto=59,alcantarillado=39,alcantarillado_2=68',
      (select string_agg(h.hoja || '=' || h.filas, ', ' order by h.hoja) from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion'))),
  (2, '02 el BCR0 de cada hoja (hoja RESUMEN) es la suma del valor remanente de sus filas: acueducto 101.061 millones, alcantarillado 138.548 y alcantarillado (2) 176.452',
      not exists (select 1 from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion')
                   and abs(h.bcr0 - (select sum(coalesce(f.valor_remanente, 0)) from redes.val_filas f where f.carga_id = h.carga_id and f.hoja = h.hoja)) >= 1)
      and (select string_agg(round(h.bcr0 / 1e6)::text, ',' order by h.hoja) from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion')) = '101061,138548,176452',
      (select string_agg(h.nombre_hoja || ' ' || round(h.bcr0 / 1e6) || ' millones', ' · ' order by h.hoja) from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion'))),
  (3, '03 la hoja de alcantarillado que vale es «ALCANTARILLADO (2)» (parámetro valoracion_hoja_alcantarillado = 2; la otra queda de referencia)',
      redes.f_val_hoja_alc() = 'alcantarillado_2' and v_j ->> 'hoja_alcantarillado' = 'alcantarillado_2', redes.f_val_hoja_alc()),
  (4, '04 los 10578 tramos y los 9064 conductos del análisis son activos de la base (por su código) y quedaron amarrados',
      current_setting('redes.val_am_sin_activo')::integer = 0
      and (select count(*) from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'acueducto'
            and exists (select 1 from redes.activos a where a.id = am.activo_id and a.prefijo in ('RED', 'CON'))) >= 10578
      and (select count(distinct am.activo_id) from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'alcantarillado_2') >= 9064,
      current_setting('redes.val_am_sin_activo') || ' código(s) del análisis sin activo'),
  (5, '05 acueducto: las filas de tubería que calzan con la red (±2 %) son las del análisis (26 de 33, una más o una menos)',
      abs((select count(*) from redes.val_filas f
            left join (select am.n, sum(am.cantidad) as red from redes.val_amarre am join redes.activo_vigente_mat m on m.activo_id = am.activo_id and not m.retirado and not m.oculto
                        where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'acueducto' and am.n is not null group by am.n) r on r.n = f.n
           where f.carga_id = redes.f_ref_vigente('valoracion') and f.hoja = 'acueducto' and f.clase = 'tuberia'
             and abs(coalesce(r.red, 0) - coalesce(f.cantidad, 0)) <= coalesce(f.cantidad, 0) * redes.f_param('valoracion_tolerancia_pct') / 100) - 26) <= 1,
      (select count(*) from redes.val_filas f
            left join (select am.n, sum(am.cantidad) as red from redes.val_amarre am join redes.activo_vigente_mat m on m.activo_id = am.activo_id and not m.retirado and not m.oculto
                        where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'acueducto' and am.n is not null group by am.n) r on r.n = f.n
           where f.carga_id = redes.f_ref_vigente('valoracion') and f.hoja = 'acueducto' and f.clase = 'tuberia'
             and abs(coalesce(r.red, 0) - coalesce(f.cantidad, 0)) <= coalesce(f.cantidad, 0) * redes.f_param('valoracion_tolerancia_pct') / 100) || ' de 33 calzan'),
  (6, '06 alcantarillado (2): las filas de tubería que calzan con la red (±2 %) son las del análisis con el catastro (27 de 63, una más o una menos)',
      abs((select count(*) from redes.val_filas f
            left join (select am.n, sum(am.cantidad) as red from redes.val_amarre am join redes.activo_vigente_mat m on m.activo_id = am.activo_id and not m.retirado and not m.oculto
                        where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'alcantarillado_2' and am.n is not null group by am.n) r on r.n = f.n
           where f.carga_id = redes.f_ref_vigente('valoracion') and f.hoja = 'alcantarillado_2' and f.clase = 'tuberia'
             and abs(coalesce(r.red, 0) - coalesce(f.cantidad, 0)) <= coalesce(f.cantidad, 0) * redes.f_param('valoracion_tolerancia_pct') / 100) - 27) <= 1,
      (select count(*) from redes.val_filas f
            left join (select am.n, sum(am.cantidad) as red from redes.val_amarre am join redes.activo_vigente_mat m on m.activo_id = am.activo_id and not m.retirado and not m.oculto
                        where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'alcantarillado_2' and am.n is not null group by am.n) r on r.n = f.n
           where f.carga_id = redes.f_ref_vigente('valoracion') and f.hoja = 'alcantarillado_2' and f.clase = 'tuberia'
             and abs(coalesce(r.red, 0) - coalesce(f.cantidad, 0)) <= coalesce(f.cantidad, 0) * redes.f_param('valoracion_tolerancia_pct') / 100) || ' de 63 calzan (hoja de referencia «ALCANTARILLADO»: 4 de 34 en el análisis)'),
  (7, '07 hidrantes: todos los vigentes amarrados a la fila «HIDRANTES» (la valoración dice 259)',
      (select count(*) from redes.activo_vigente_mat m where m.prefijo in ('TOR', 'HID') and not m.retirado) > 0
      and not exists (select 1 from redes.activo_vigente_mat m where m.prefijo in ('TOR', 'HID') and not m.retirado
                       and not exists (select 1 from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.activo_id = m.activo_id and am.n = 44)),
      (select count(*) from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'acueducto' and am.n = 44)::text || ' hidrantes en la red'),
  (8, '08 válvulas: las 730 de cierre del modelo tienen su amarre por diámetro (con fila, o «sin fila» si la valoración no trae ese diámetro)',
      (select count(*) from redes.val_amarre am join redes.activos a on a.id = am.activo_id and a.prefijo = 'VAL' join redes.activo_vigente_mat m on m.activo_id = a.id
        where am.carga_id = redes.f_ref_vigente('val_amarre') and exists (select 1 from redes.pm_valvulas w where w.llave = m.llave_capa and w.carga_id = redes.f_ref_vigente('pm_valvulas'))) = 730,
      (select count(*) filter (where am.n is not null) || ' con fila · ' || count(*) filter (where am.n is null) || ' sin fila'
         from redes.val_amarre am join redes.activos a on a.id = am.activo_id and a.prefijo = 'VAL' where am.carga_id = redes.f_ref_vigente('val_amarre'))),
  (9, '09 puntuales uno a uno: la planta con sus dos filas (Huaricha y Gota Fría), La Pedregosa y La Popa con la suya',
      (select count(*) from redes.val_amarre am join redes.activos a on a.id = am.activo_id where am.carga_id = redes.f_ref_vigente('val_amarre') and a.prefijo = 'PTA' and am.n in (6, 7)) = 2
      and (select count(*) from redes.val_amarre am join redes.activos a on a.id = am.activo_id where am.carga_id = redes.f_ref_vigente('val_amarre') and a.prefijo = 'TAN' and am.n = 8) = 1
      and (select count(*) from redes.val_amarre am join redes.activos a on a.id = am.activo_id where am.carga_id = redes.f_ref_vigente('val_amarre') and a.prefijo = 'TAN' and am.n = 9) = 1,
      (select string_agg(a.codigo || '→' || am.n, ', ' order by am.n) from redes.val_amarre am join redes.activos a on a.id = am.activo_id
        where am.carga_id = redes.f_ref_vigente('val_amarre') and a.prefijo in ('PTA', 'TAN') and am.n is not null)),
  (10, '10 la ficha oficial no cambió: ninguna versión de activo ni evento se creó con la carga',
      not exists (select 1 from redes.activo_versiones v where v.creado_en >= transaction_timestamp())
      and not exists (select 1 from redes.activo_eventos e where e.creado_en >= transaction_timestamp()), null),
  (11, '11 la ficha de un tramo amarrado trae «Inventario regulatorio» para el administrador (remunerado, con su fila) y NO la trae para el operador',
      (v_f -> 'regulatorio' ->> 'remunerado')::boolean and jsonb_array_length(v_f -> 'regulatorio' -> 'filas') = 1 and (v_f -> 'regulatorio' ->> 'fuente') like '%propuesta%'
      and not (redes.f_ficha(v_id, 'operador') ? 'regulatorio'),
      v_cod || ': ' || (v_f -> 'regulatorio' -> 'filas' -> 0 ->> 'nombre') || ' ' || (v_f -> 'regulatorio' -> 'filas' -> 0 ->> 'caracteristica') || '"'),
  (12, '12 la conciliación responde con las 3 hojas y sus filas, y dice cuáles filas no tienen activos y cuáles activos no tienen fila',
      (v_j ->> 'cargada')::boolean and jsonb_array_length(v_j -> 'hojas') = 3 and jsonb_array_length(v_j -> 'filas') = 166
      and exists (select 1 from jsonb_array_elements(v_j -> 'filas') x where (x ->> 'activos')::integer = 0) and jsonb_array_length(v_j -> 'sin_fila') > 0,
      (select count(*) filter (where (x ->> 'activos')::integer = 0) || ' filas sin activos (las 3 hojas) · ' from jsonb_array_elements(v_j -> 'filas') x)
      || (select coalesce(sum((x ->> 'activos')::integer), 0) from jsonb_array_elements(v_j -> 'sin_fila') x) || ' activos sin fila'),
  (13, '13 TIEMPOS: la conciliación, la ficha y la tesela más cargada, cada una en menos de 5 s',
      greatest(v_ms1, v_ms2, v_ms3) < 5000,
      format('TIEMPOS: conciliación %s ms · ficha de %s %s ms · tesela %s/%s/%s %s ms (%s kB)', v_ms1, v_cod, v_ms2, v_z, v_x, v_y, v_ms3, round(length(v_mvt) * 0.75 / 1024))),
  (14, '14 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()), null);
end $$;
do $$
declare v_t integer; v_b integer; v_f text; v_i text;
begin
  select count(*), count(*) filter (where coalesce(ok, false)), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by n) filter (where not coalesce(ok, false)), ''),
         string_agg('  ' || lpad(n::text, 2, '0') || ' ' || coalesce(detalle, ''), E'\n' order by n) filter (where detalle is not null and coalesce(ok, false))
    into v_t, v_b, v_f, v_i from _val_r;
  if v_b <> v_t or coalesce(current_setting('redes.val_ensayo', true), '') = 'si' then
    raise exception E'CARGA DEL INVENTARIO REGULATORIO · CORTE 10%\n%\n%\nRESULTADO: % de % comprobaciones correctas — %',
      case when coalesce(current_setting('redes.val_ensayo', true), '') = 'si' then ' (ENSAYO: este ERROR es el esperado y deshace todo)' else ' (se deshace todo: no quedó nada cargado)' end,
      v_f, v_i, v_b, v_t, case when v_b = v_t then 'SIN FALLAS' else (v_t - v_b) || ' FALLA(S)' end;
  end if;
  raise notice E'CARGA DEL INVENTARIO REGULATORIO · CORTE 10\n%\n% de % comprobaciones correctas — SIN FALLAS', v_i, v_b, v_t;
end $$;
