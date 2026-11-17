-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 · 20 — FUNCIONES Y RPC de la capa «Flujo del agua (modelo)». PROPUESTA. Solo agrega.
-- · geoportal_redes_geovisor_mvt_flujo: la tesela. Cada tramo sale con la línea YA ORIENTADA en el sentido del agua de esa hora (la pantalla solo pone
--   flechas a lo largo de la línea), su caudal (L/s, sin signo), su velocidad (m/s) y su clase de caudal (1 a 5) para el grosor. Los tramos «sin flujo»
--   salen marcados (sin flecha). Solo supervisores y administrador.
-- · geoportal_redes_flujo_modelo: la leyenda, las horas, la cobertura y el rótulo «Modelo, no medido (modeloV1, Plan Maestro 2014)».
-- · geoportal_redes_flujo_tramo: la tarjeta de un tramo (las dos horas).
-- Sentido respecto a la geometría del tramo: «ini_fin» con la geometría en el mismo sentido del tubo, o «fin_ini» con la geometría al revés = a favor de la línea.
-- =====================================================================
create function redes.f_flujo_clase(p_q numeric) returns integer
language sql immutable set search_path = pg_catalog as $$
  select case when abs(p_q) < 1 then 1 when abs(p_q) < 5 then 2 when abs(p_q) < 20 then 3 when abs(p_q) < 100 then 4 else 5 end $$;

create function public.geoportal_redes_geovisor_mvt_flujo(p_solicitante text, p_hora text, p_z integer, p_x integer, p_y integer)
returns text
language plpgsql stable security definer set search_path = public, redes, extensions, pg_temp as $$
declare a record; v_env geometry; v_env4 geometry; v_c bigint; v bytea; v_mayor boolean := p_hora = 'mayor'; v_diam numeric;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'El flujo del agua (modelo) es para supervisores' using errcode = '42501'; end if;
  if p_hora is null or p_hora not in ('mayor', 'menor') then perform tecnica.f_error('La hora es «mayor» o «menor»'); end if;
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  v_c := redes.f_ref_vigente('flujo_modelo');
  if v_c is null or p_z < redes.f_param('geovisor_zoom_min') then return ''; end if;
  -- como la red: antes del zoom de «red completa», solo los diámetros principales
  v_diam := case when p_z < redes.f_param('geovisor_zoom_red_completa') then redes.f_param('geovisor_diam_principal_acu_mm') end;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'flujo_modelo', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(case when x.sentido <> 'sin_flujo' and (x.sentido = 'ini_fin') <> f.geom_mismo then ST_Reverse(m.geom) else m.geom end, 3857), v_env, 4096, 64, true) as geom,
           m.codigo, round(abs(x.q), 2)::real as q, round(x.v, 2)::real as v, redes.f_flujo_clase(x.q) as clase, (x.sentido = 'sin_flujo') as sin_flujo, m.diametro_mm::real as d
      from redes.activo_vigente_mat m
      join redes.flujo_modelo f on f.carga_id = v_c and f.activo_id = m.activo_id
     cross join lateral (select case when v_mayor then f.q_mayor_lps else f.q_menor_lps end as q, case when v_mayor then f.v_mayor_mps else f.v_menor_mps end as v,
                                case when v_mayor then f.sentido_mayor else f.sentido_menor end as sentido) x
     where m.geom && v_env4 and not m.retirado and not m.oculto and m.sistema = 'acueducto' and m.prefijo in ('RED', 'CON')
       and (v_diam is null or m.diametro_mm >= v_diam)) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $$;

create function public.geoportal_redes_flujo_modelo(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; v_c bigint := redes.f_ref_vigente('flujo_modelo'); r redes.ref_cargas%rowtype;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'El flujo del agua (modelo) es para supervisores' using errcode = '42501'; end if;
  if v_c is null then return jsonb_build_object('cargado', false, 'rotulo', 'Modelo, no medido (modeloV1, Plan Maestro 2014)'); end if;
  select * into r from redes.ref_cargas where id = v_c;
  return jsonb_build_object(
    'cargado', true, 'rotulo', 'Modelo, no medido (modeloV1, Plan Maestro 2014)', 'origen', r.origen, 'nota', r.nota, 'version', v_c,
    'horas', (select jsonb_agg(jsonb_build_object('cual', h.cual, 'hora', h.hora, 'consumo_lps', h.consumo_lps,
                                                  'texto', case h.cual when 'mayor' then 'Hora de mayor consumo' else 'Hora de menor consumo' end || ' (' || h.hora || ':00)') order by h.cual)
                from redes.flujo_modelo_horas h where h.carga_id = v_c),
    'cobertura', (select jsonb_build_object('tubos_modelo', count(*), 'con_tramo', count(f.activo_id), 'sin_tramo', count(*) - count(f.activo_id),
                         'tramos_red', (select count(*) from redes.activo_vigente_mat m where m.sistema = 'acueducto' and m.prefijo in ('RED', 'CON') and not m.retirado and not m.oculto),
                         'sin_flujo_mayor', count(*) filter (where f.activo_id is not null and f.sentido_mayor = 'sin_flujo'),
                         'sin_flujo_menor', count(*) filter (where f.activo_id is not null and f.sentido_menor = 'sin_flujo'))
                    from redes.flujo_modelo f where f.carga_id = v_c),
    'leyenda', jsonb_build_object('titulo', 'Caudal según el modelo', 'unidad', 'L/s', 'clases', jsonb_build_array(
        jsonb_build_object('clase', 1, 'texto', 'Menos de 1'), jsonb_build_object('clase', 2, 'texto', '1 a 5'), jsonb_build_object('clase', 3, 'texto', '5 a 20'),
        jsonb_build_object('clase', 4, 'texto', '20 a 100'), jsonb_build_object('clase', 5, 'texto', 'Más de 100')),
      'sin_flujo', 'Sin flujo en el modelo', 'sin_dato', 'Los tramos que no están en el modelo no llevan flecha'));
end $$;

create function public.geoportal_redes_flujo_tramo(p_solicitante text, p_codigo text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; v_c bigint := redes.f_ref_vigente('flujo_modelo'); v_id bigint; f redes.flujo_modelo%rowtype;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'El flujo del agua (modelo) es para supervisores' using errcode = '42501'; end if;
  v_id := redes.f_buscar_activo(p_codigo);
  select * into f from redes.flujo_modelo x where x.carga_id = v_c and x.activo_id = v_id;
  if not found then return jsonb_build_object('tramo', redes.f_activo_corto(v_id), 'en_modelo', false, 'rotulo', 'Modelo, no medido (modeloV1, Plan Maestro 2014)',
                                              'texto', 'Este tramo no está en el modelo: sin dato de flujo.'); end if;
  return jsonb_build_object('tramo', redes.f_activo_corto(v_id), 'en_modelo', true, 'rotulo', 'Modelo, no medido (modeloV1, Plan Maestro 2014)', 'tubo_modelo', f.llave, 'amarre', f.amarre,
    'horas', (select jsonb_agg(jsonb_build_object('cual', h.cual, 'hora', h.hora,
                'caudal_lps', round(abs(case h.cual when 'mayor' then f.q_mayor_lps else f.q_menor_lps end), 2),
                'velocidad_mps', round(case h.cual when 'mayor' then f.v_mayor_mps else f.v_menor_mps end, 2),
                'sentido', case case h.cual when 'mayor' then f.sentido_mayor else f.sentido_menor end when 'sin_flujo' then 'sin_flujo'
                             else case when ((case h.cual when 'mayor' then f.sentido_mayor else f.sentido_menor end) = 'ini_fin') = f.geom_mismo then 'con_la_linea' else 'contra_la_linea' end end) order by h.cual)
                from redes.flujo_modelo_horas h where h.carga_id = v_c),
    'cambia_de_sentido', f.sentido_mayor <> f.sentido_menor and 'sin_flujo' not in (f.sentido_mayor, f.sentido_menor));
end $$;
