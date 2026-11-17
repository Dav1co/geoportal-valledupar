-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 20 — FUNCIONES INTERNAS (nadie de la API las ejecuta: ver 40_permisos.sql)
-- =====================================================================
-- La hoja de alcantarillado que vale hoy (parámetro; la decide David)
create function redes.f_val_hoja_alc() returns text language sql stable set search_path to 'redes', 'pg_temp' as $$
  select case when redes.f_param('valoracion_hoja_alcantarillado') = 1 then 'alcantarillado' else 'alcantarillado_2' end $$;

-- Los tipos de activo que la valoración cubre: solo en ellos la ficha dice «fuera de la valoración» cuando no hay amarre (un pozo o un accesorio no llevan la sección)
create function redes.f_val_prefijos() returns text[] language sql immutable set search_path to 'pg_catalog' as $$
  select array['RED', 'CON', 'ADU', 'COL', 'INT', 'TOR', 'HID', 'VAL', 'TAN', 'PTA', 'PTR', 'CAP', 'DES'] $$;

-- La sección «Inventario regulatorio» de la ficha (solo la piden supervisor y administrador: lo decide redes.f_ficha).
-- Los valores son DE LA FILA (agregados): no se reparten por activo. «Vida útil remanente a hoy» = vida útil − años desde la entrada en operación regulatoria.
create function redes.f_ficha_regulatorio(p_activo bigint, p_prefijo text) returns jsonb
language plpgsql stable set search_path to 'redes', 'public', 'pg_temp' as $$
declare v_val bigint := redes.f_ref_vigente('valoracion'); v_am bigint; v_hoja text; c redes.ref_cargas%rowtype;
        v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; v_filas jsonb; v_sit text; v_nota text; v_n integer;
begin
  if v_val is null then return null; end if;      -- todavía no se ha cargado la valoración
  v_am := redes.f_ref_vigente('val_amarre'); v_hoja := redes.f_val_hoja_alc();
  select count(*), min(am.situacion) filter (where am.n is null), min(am.nota) filter (where am.n is null) into v_n, v_sit, v_nota
    from redes.val_amarre am where am.activo_id = p_activo and am.carga_id = v_am and am.val_carga_id = v_val and am.hoja in ('acueducto', v_hoja);
  if v_n = 0 and not (p_prefijo = any (redes.f_val_prefijos())) then return null; end if;
  select * into c from redes.ref_cargas where id = v_val;
  select jsonb_agg(jsonb_build_object(
           'hoja', h.nombre_hoja, 'n', f.n, 'nombre', f.nombre, 'clase', f.clase, 'caracteristica', f.caracteristica, 'diametro_pulg', f.diametro_pulg,
           'cantidad', f.cantidad, 'unidad', f.unidad,
           'activos', (select count(*) from redes.val_amarre x where x.carga_id = v_am and x.hoja = f.hoja and x.n = f.n and x.val_carga_id = v_val),
           'anio_operacion', f.anio_operacion, 'fecha_operacion', f.fecha_operacion, 'fecha_tarifa', f.fecha_tarifa, 'vida_util', f.vida_util,
           'vida_remanente_hoy', case when f.vida_util is not null and f.fecha_operacion is not null
                                      then greatest(0, round(f.vida_util - (v_hoy - f.fecha_operacion) / 365.25, 1)) end,
           'fin_vida_util', case when f.vida_util is not null and f.fecha_operacion is not null then (f.fecha_operacion + make_interval(months => round(f.vida_util * 12)::integer))::date end,
           'valor_total', round(f.valor_total), 'valor_remanente', round(f.valor_remanente), 'depreciacion_anual', round(f.depreciacion_anual),
           'aporte', am.cantidad, 'nota', am.nota) order by f.n)
    into v_filas
    from redes.val_amarre am
    join redes.val_filas f on f.carga_id = am.val_carga_id and f.hoja = am.hoja and f.n = am.n
    join redes.val_hojas h on h.carga_id = f.carga_id and h.hoja = f.hoja
   where am.activo_id = p_activo and am.carga_id = v_am and am.val_carga_id = v_val and am.hoja in ('acueducto', v_hoja);
  if v_filas is null then v_sit := case when v_n = 0 then 'fuera' else coalesce(v_sit, 'sin_fila') end; else v_sit := 'con_fila'; end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'fuente', 'Valoración técnica 2019 (Res. CRA 688 de 2014), propuesta',
    'archivo', c.archivo, 'cargada_en', c.creado_en,
    'remunerado', v_filas is not null,
    'situacion', v_sit,
    'texto', case v_sit when 'con_fila' then null
                        when 'fuera' then 'Fuera de la valoración 2019: el activo no estaba en la red con que se amarró la valoración (por ejemplo, uno nuevo de una inversión). Queda así hasta que haya una valoración nueva.'
                        when 'proyectado' then 'Proyectado por el Plan Maestro: no entra en la valoración 2019.'
                        else 'Sin fila en la valoración 2019: ninguna fila corresponde a su material y diámetro.' end,
    'nota', case when v_filas is null then v_nota end,
    'filas', v_filas));
end $$;
