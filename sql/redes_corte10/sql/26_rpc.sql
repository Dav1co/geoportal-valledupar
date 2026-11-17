-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 26 — RPC NUEVA (solo service_role: la llama la Edge geoportal-redes)
-- =====================================================================
-- La conciliación del inventario regulatorio con la red (pantalla del administrador y su descarga en Excel). Solo lectura.
-- Por fila de la valoración: lo que dice el libro contra lo que suma la red amarrada (activos vigentes, sin los retirados ni los ocultos), diferencia y porcentaje.
-- Además: las filas sin activos y los activos sin fila (agrupados por tipo, material y diámetro). Sin datos de personas. No recalcula nada: lee el amarre vigente.
create function public.geoportal_redes_valoracion(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'pg_temp' as $$
declare v_email text := redes.f_autorizar_admin(p_solicitante);
        v_val bigint := redes.f_ref_vigente('valoracion'); v_am bigint := redes.f_ref_vigente('val_amarre'); v_hoja text := redes.f_val_hoja_alc();
        v_tol numeric := redes.f_param('valoracion_tolerancia_pct'); v_pref text[] := redes.f_val_prefijos();
        v_hojas jsonb; v_filas jsonb; v_sin jsonb; c redes.ref_cargas%rowtype; a redes.ref_cargas%rowtype;
begin
  if v_val is null then
    return jsonb_build_object('cargada', false, 'hoja_alcantarillado', v_hoja, 'tolerancia_pct', v_tol);
  end if;
  select * into c from redes.ref_cargas where id = v_val;
  select * into a from redes.ref_cargas where id = v_am;
  with red as (
    select am.hoja, am.n, count(*) as activos, sum(am.cantidad) as cantidad, coalesce(sum(am.cantidad) filter (where am.situacion <> 'con_fila'), 0) as aparte,
           case when count(*) <= 4 then string_agg(m.codigo, ', ' order by m.codigo) end as codigos
      from redes.val_amarre am
      join redes.activo_vigente_mat m on m.activo_id = am.activo_id and not m.retirado and not m.oculto
     where am.carga_id = v_am and am.val_carga_id = v_val and am.n is not null
     group by am.hoja, am.n),
  fil as (
    select f.*, coalesce(r.activos, 0) as activos, r.cantidad as red, r.aparte, r.codigos,
           f.clase in ('tuberia', 'valvula', 'hidrante') as comparable
      from redes.val_filas f left join red r on r.hoja = f.hoja and r.n = f.n
     where f.carga_id = v_val)
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'hoja', x.hoja, 'n', x.n, 'nombre', x.nombre, 'clase', x.clase, 'caracteristica', x.caracteristica, 'unidad', x.unidad, 'cantidad', x.cantidad,
           'anio_operacion', x.anio_operacion, 'vida_util', x.vida_util, 'valor_total', round(x.valor_total), 'valor_remanente', round(x.valor_remanente),
           'depreciacion_anual', round(x.depreciacion_anual),
           'activos', x.activos, 'codigos', x.codigos, 'comparable', x.comparable,
           'red', case when x.comparable then round(coalesce(x.red, 0), 1) end,
           'aparte', case when x.comparable and x.aparte > 0 then round(x.aparte, 1) end,
           'diferencia', case when x.comparable then round(coalesce(x.red, 0) - coalesce(x.cantidad, 0), 1) end,
           'pct', case when x.comparable and x.cantidad > 0 then round(100 * coalesce(x.red, 0) / x.cantidad, 1) end,
           'calza', case when x.comparable then abs(coalesce(x.red, 0) - coalesce(x.cantidad, 0)) <= coalesce(x.cantidad, 0) * v_tol / 100 end,
           'nota', x.nota)) order by x.hoja, x.n)
    into v_filas from fil x;
  select jsonb_agg(jsonb_build_object('hoja', h.hoja, 'nombre', h.nombre_hoja, 'servicio', h.servicio, 'filas', h.filas, 'bcr0', round(h.bcr0), 'valor_total', round(h.valor_total),
                                      'depreciacion_anual', round(h.depreciacion_anual), 'vigente', h.hoja in ('acueducto', v_hoja)) order by h.hoja)
    into v_hojas from redes.val_hojas h where h.carga_id = v_val;
  -- activos de los tipos que la valoración cubre y que no tienen fila en la hoja vigente de su servicio
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('prefijo', g.prefijo, 'tipo', (select t.nombre_visible from redes.v_tipo_visible t where t.prefijo = g.prefijo),
                                                                 'sistema', g.sistema, 'material', (select mt.nombre from redes.materiales mt where mt.codigo = g.material_codigo),
                                                                 'diametro_mm', g.diametro_mm, 'motivo', g.motivo, 'activos', g.activos, 'longitud_m', round(g.longitud, 1)))
                            order by g.sistema, g.prefijo, g.motivo, g.activos desc), '[]'::jsonb)
    into v_sin
    from (select m.prefijo, m.sistema, m.material_codigo, m.diametro_mm, coalesce(x.situacion, 'fuera') as motivo, count(*) as activos, sum(coalesce(x.cantidad, m.longitud_m)) as longitud
            from redes.activo_vigente_mat m
            left join lateral (select am.situacion, am.cantidad, am.n from redes.val_amarre am
                                where am.activo_id = m.activo_id and am.carga_id = v_am and am.val_carga_id = v_val and am.hoja in ('acueducto', v_hoja)
                                order by am.n nulls last limit 1) x on true
           where not m.retirado and not m.oculto and m.prefijo = any (v_pref) and x.n is null
           group by m.prefijo, m.sistema, m.material_codigo, m.diametro_mm, coalesce(x.situacion, 'fuera')) g;
  return jsonb_build_object(
    'cargada', true,
    'fuente', 'Valoración técnica 2019 (Res. CRA 688 de 2014), propuesta',
    'valoracion', jsonb_build_object('archivo', c.archivo, 'md5', c.md5, 'filas', c.filas, 'cargada_en', c.creado_en, 'origen', c.origen),
    'amarre', case when a.id is not null then jsonb_build_object('archivo', a.archivo, 'md5', a.md5, 'filas', a.filas, 'cargado_en', a.creado_en, 'nota', a.nota) end,
    'hoja_alcantarillado', v_hoja, 'tolerancia_pct', v_tol,
    'generado_en', clock_timestamp(), 'generado_por', v_email,
    'hojas', coalesce(v_hojas, '[]'::jsonb), 'filas', coalesce(v_filas, '[]'::jsonb), 'sin_fila', v_sin);
end $$;
