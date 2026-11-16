-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 20 — FUNCIONES INTERNAS (nadie de la API las ejecuta)
--   · redes.f_sector_de: sector y subsector de un punto, tramo o polígono, POR GEOMETRÍA, contra los polígonos vigentes de la capa «sectores» (SEC).
--     No guarda nada: se calcula al leer, así que otra versión de los polígonos cambia el resultado sin recalcular tablas.
--   · redes.f_ref_vigente: la carga de referencia que vale para un conjunto (la última no anulada).
--   · redes.f_pm_nivel_presion: color de una presión frente a los umbrales de Parámetros (§30.7).
--   · redes.f_pm_sugerencia y redes.f_nodo_modelo: lo que dice el modelo de un nodo y la SUGERENCIA de clasificación (nada se clasifica solo).
--   · redes.f_ficha_referencia: los datos de referencia del Plan Maestro para la ficha de un activo, ya rotulados y por grupos.
--   · redes.v_pm_por_verificar y redes.f_pm_marcar_por_verificar: los activos que el Plan deja «por verificar» (estado distinto en el modelo,
--     válvulas por verificar en campo y pozos MHP, MH y MHONE) y la función que los marca (evento «por_verificar»; la corre el paquete de carga).
-- =====================================================================
create function redes.f_ref_vigente(p_conjunto text) returns bigint language sql stable set search_path = redes, pg_temp as $$
  select v.id from redes.v_ref_carga_vigente v where v.conjunto = p_conjunto $$;

create function redes.f_sector_de(p_geom geometry, out sector integer, out subsector text, out codigo text, out nombre text)
language plpgsql stable set search_path = redes, public, extensions, pg_temp as $$
declare v_pt geometry;
begin
  if p_geom is null then return; end if;
  v_pt := case when GeometryType(p_geom) = 'POINT' then p_geom else ST_PointOnSurface(p_geom) end;
  -- primero el subsector que contiene el punto; si no cae en ninguno, el sector. El número va en los atributos de la capa (columnas «sector» y «subsector»).
  select case when redes.f_num(v.atributos -> 'modelo' -> 'sector') between 1 and 100 then redes.f_num(v.atributos -> 'modelo' -> 'sector')::integer end,
         case when m.clase = 'subsector' then nullif(btrim(v.atributos -> 'modelo' ->> 'subsector'), '') end, m.codigo, m.nombre
    into sector, subsector, codigo, nombre
    from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
   where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.geom && v_pt and ST_Intersects(m.geom, v_pt)
   order by (m.clase = 'subsector') desc nulls last, ST_Area(m.geom), m.activo_id limit 1;
end $$;

create function redes.f_pm_nivel_presion(p_mca numeric) returns text language sql stable set search_path = redes, pg_temp as $$
  select case when p_mca is null then 'sin_dato'
              when p_mca < redes.f_param('presion_baja_roja_mca') then 'baja_roja'
              when p_mca < redes.f_param('presion_baja_naranja_mca') then 'baja_naranja'
              when p_mca > redes.f_param('presion_alta_roja_mca') then 'alta_roja'
              when p_mca > redes.f_param('presion_alta_naranja_mca') then 'alta_naranja'
              else 'normal' end $$;

-- La sugerencia de clasificación de un nodo «por clasificar», según lo que dice el modelo. Es solo una sugerencia: el supervisor la confirma.
create function redes.f_pm_sugerencia(p_tipo text, p_que_es text, p_nombre text, p_zona text) returns jsonb language sql immutable set search_path = pg_catalog as $$
  select case
    when p_tipo is null and p_que_es is null then null
    when p_tipo = 'tanque' and coalesce(p_zona, '') <> 'Proyectado' and p_nombre !~* 'proyectado' then
      jsonb_build_object('accion', 'crear', 'prefijo', 'TAN', 'texto', 'Tanque existente (' || p_nombre || '): crear el activo TAN')
    when p_tipo = 'tanque' then
      jsonb_build_object('accion', 'no_crear', 'clase', 'propuesta_plan', 'texto', 'Tanque proyectado por el Plan (no construido): no crear activo')
    when p_que_es like 'válvula de sectorización propuesta%' then
      jsonb_build_object('accion', 'no_crear', 'clase', 'propuesta_plan', 'texto', 'Válvula propuesta por el Plan (no instalada): no crear activo')
    when p_que_es = 'macromedidor proyectado' then
      jsonb_build_object('accion', 'no_crear', 'clase', 'propuesta_plan', 'texto', 'Macromedidor proyectado por el Plan (no instalado): no crear activo')
    when p_que_es like 'nodo de cálculo%' then
      jsonb_build_object('accion', 'dejar_nodo', 'clase', 'nodo_calculo', 'texto', 'Nodo de cálculo del modelo: dejar como nodo')
    when p_que_es like 'unión corriente%' then
      jsonb_build_object('accion', 'dejar_nodo', 'clase', 'nodo_calculo', 'texto', 'Unión corriente del modelo (sin accesorio que inventariar): dejar como nodo')
    when p_tipo = 'hidrante' then
      jsonb_build_object('accion', 'crear', 'prefijo', 'TOR', 'texto', 'Hidrante en el modelo: si existe en campo, crear el activo (Torre = hidrante)')
    else jsonb_build_object('accion', 'revisar', 'texto', 'Sin sugerencia: revisar en campo') end $$;

create function redes.f_nodo_modelo(p_llave text) returns jsonb language sql stable set search_path = redes, public, extensions, pg_temp as $$
  select jsonb_strip_nulls(jsonb_build_object('tipo', n.tipo, 'que_es', n.que_es, 'zona', n.zona_modelo, 'nota', n.nota_modelo, 'activo_en_modelo', n.activo_modelo,
           'estado_modelo', n.estado_modelo, 'cota_m', n.cota_m, 'demanda_exist_lps', n.demanda_exist_lps, 'demanda_futura_lps', n.demanda_futura_lps,
           'pres_exist_mediana', n.pres_exist_mediana, 'pres_exist_min', n.pres_exist_min, 'pres_exist_max', n.pres_exist_max,
           'pres_futura_mediana', n.pres_futura_mediana, 'pres_futura_min', n.pres_futura_min, 'pres_futura_max', n.pres_futura_max,
           'sugerencia', redes.f_pm_sugerencia(n.tipo, n.que_es, n.nombre, n.zona_modelo)))
    from redes.pm_nodos n where n.llave = p_llave and n.carga_id = redes.f_ref_vigente('pm_nodos') $$;

-- Datos de referencia para la ficha. Devuelve una lista de grupos: {titulo, origen, advertencia, filas: [{r, v, u}]}. Solo las filas con valor.
create function redes.f_ficha_referencia(p_activo bigint) returns jsonb language plpgsql stable set search_path = redes, public, extensions, pg_temp as $$
declare
  v redes.v_activo_vigente%rowtype; v_llave text; v_grupos jsonb := '[]'::jsonb; v_f jsonb;
  n redes.pm_nodos%rowtype; t redes.pm_tramos%rowtype; w redes.pm_valvulas%rowtype; c redes.pm_alc_conductos%rowtype; z redes.pm_alc_pozos%rowtype;
  v_org text;
begin
  select * into v from redes.v_activo_vigente where activo_id = p_activo;
  if not found then return v_grupos; end if;
  -- el activo creado desde un nodo «por clasificar» (el tanque La Popa) no lleva capa: su llave del modelo está en los atributos
  v_llave := case when v.capa_codigo = 'acueducto_nodos' then v.llave_capa else v.atributos ->> 'creado_desde_nodo' end;

  if v_llave is not null and v.sistema = 'acueducto' and GeometryType(v.geom) = 'POINT' then
    select * into n from redes.pm_nodos x where x.llave = v_llave and x.carga_id = redes.f_ref_vigente('pm_nodos');
    if found then
      select origen into v_org from redes.ref_cargas where id = n.carga_id;
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'Tipo en el modelo', to_jsonb(n.tipo), null), (2, 'Lectura del modelo', to_jsonb(nullif(n.que_es, 'otro')), null), (3, 'Zona del modelo', to_jsonb(n.zona_modelo), null),
        (4, 'Nota del modelo', to_jsonb(n.nota_modelo), null),
        (5, 'Estado según el modelo', to_jsonb((select e.nombre from redes.estados_activo e where e.codigo = n.estado_modelo)), null),
        (6, 'Cota', to_jsonb(n.cota_m), 'm'), (7, 'Demanda (red existente)', to_jsonb(n.demanda_exist_lps), 'L/s'), (8, 'Demanda (red futura del Plan)', to_jsonb(n.demanda_futura_lps), 'L/s')
      ) f(o, r, v, u);
      if jsonb_array_length(v_f) > 0 then
        v_grupos := v_grupos || jsonb_build_object('titulo', 'Modelo hidráulico', 'origen', v_org, 'filas', v_f,
          'advertencia', case when n.estado_difiere then 'El estado del modelo es distinto del estado de la ficha: por verificar en campo.' end);
      end if;
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'Red existente: mediana del día', to_jsonb(n.pres_exist_mediana), 'm.c.a.'), (2, 'Red existente: mínima', to_jsonb(n.pres_exist_min), 'm.c.a.'),
        (3, 'Red existente: máxima', to_jsonb(n.pres_exist_max), 'm.c.a.'),
        (4, 'Red futura del Plan: mediana', to_jsonb(n.pres_futura_mediana), 'm.c.a.'), (5, 'Red futura del Plan: mínima', to_jsonb(n.pres_futura_min), 'm.c.a.'),
        (6, 'Red futura del Plan: máxima', to_jsonb(n.pres_futura_max), 'm.c.a.')
      ) f(o, r, v, u);
      if jsonb_array_length(v_f) > 0 then
        v_grupos := v_grupos || jsonb_build_object('titulo', 'Presión de modelo', 'origen', v_org, 'filas', v_f,
          'advertencia', 'Presión de MODELO, no medida.' || case when n.pres_exist_negativa then ' El modelo de la red existente da presión negativa en este nodo a alguna hora.' else '' end);
      end if;
    end if;
    select * into w from redes.pm_valvulas x where x.llave = v_llave and x.carga_id = redes.f_ref_vigente('pm_valvulas');
    if found then
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'Efecto sugerido por el modelo', to_jsonb(w.efecto_sugerido), null),
        (2, 'Si se cierra sola: nodos sin agua', to_jsonb(w.cierre_nodos_sin_agua), null), (3, 'Si se cierra sola: demanda sin agua', to_jsonb(w.cierre_demanda_lps), 'L/s'),
        (4, 'Estado en la red existente (modeloV1)', to_jsonb(w.estado_existente), null), (5, 'Estado en la red futura (ModeloVF)', to_jsonb(w.estado_futuro), null),
        (6, 'Estado en el catastro de 2014', to_jsonb(w.estado_catastro), null),
        (7, 'Los dos modelos difieren', case when w.difiere_entre_modelos then to_jsonb('Sí'::text) end, null),
        (8, 'Modelo y catastro se contradicen', case when w.estado_contradictorio then to_jsonb('Sí'::text) end, null)
      ) f(o, r, v, u);
      v_grupos := v_grupos || jsonb_build_object('titulo', 'Válvula: sugerencia del modelo', 'origen', (select origen from redes.ref_cargas where id = w.carga_id), 'filas', v_f,
        'advertencia', 'Es una sugerencia. El «Efecto en la red» oficial lo define el supervisor de distribución en la ficha.'
                       || case when w.verificar_en_campo then ' Estado por verificar en campo.' else '' end);
    end if;
  elsif v.capa_codigo = 'acueducto' then
    select * into t from redes.pm_tramos x where x.llave = v.llave_capa and x.carga_id = redes.f_ref_vigente('pm_tramos');
    if found then
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'Clase de red', to_jsonb(t.clase_red), null), (2, 'Nota del modelo', to_jsonb(t.nota_modelo), null), (3, 'Zona del modelo', to_jsonb(t.zona_modelo), null),
        (4, 'Estado según el modelo', to_jsonb((select e.nombre from redes.estados_activo e where e.codigo = t.estado_modelo)), null),
        (5, 'Cruza la frontera entre sectores', case when t.frontera_sectores then to_jsonb('Sí'::text) end, null),
        (6, 'Caudal máximo (red futura del Plan)', to_jsonb(t.q_max_futuro_lps), 'L/s'), (7, 'Velocidad máxima (red futura del Plan)', to_jsonb(t.v_max_futuro_mps), 'm/s')
      ) f(o, r, v, u);
      v_grupos := v_grupos || jsonb_build_object('titulo', 'Modelo hidráulico', 'origen', (select origen from redes.ref_cargas where id = t.carga_id), 'filas', v_f,
        'advertencia', case when t.estado_difiere then 'El estado del modelo es distinto del estado de la ficha: por verificar en campo.' end);
    end if;
  elsif v.capa_codigo = 'alc_conductos' then
    select * into c from redes.pm_alc_conductos x where x.llave = v.llave_capa and x.carga_id = redes.f_ref_vigente('pm_alc_conductos');
    if found then
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'Cómo se amarró', to_jsonb(c.origen), null), (2, 'Código en el catastro', to_jsonb(c.cod_tubo_catastro), null), (3, 'Material', to_jsonb(c.material), null),
        (4, 'Diámetro medido', to_jsonb(c.diametro_mm), 'mm'), (5, 'Diámetro nominal', to_jsonb(c.diametro_nominal_pulg), 'pulg'),
        (6, 'Estado físico', to_jsonb(c.estado_fisico), null), (7, 'Estado operacional', to_jsonb(c.estado_operacional), null), (8, 'Tipo de red', to_jsonb(c.tipo_red), null),
        (9, 'Profundidad inicial', to_jsonb(c.prof_inicial_m), 'm'), (10, 'Profundidad final', to_jsonb(c.prof_final_m), 'm')
      ) f(o, r, v, u);
      v_grupos := v_grupos || jsonb_build_object('titulo', 'Catastro de alcantarillado 2014', 'origen', (select origen from redes.ref_cargas where id = c.carga_id), 'filas', v_f || c.datos,
        'advertencia', case when c.cod_tubo_catastro is null then 'Sin datos del catastro levantado (conducto proyectado por el Plan).' end);
    end if;
  elsif v.capa_codigo = 'alc_pozos' then
    select * into z from redes.pm_alc_pozos x where x.llave = v.llave_capa and x.carga_id = redes.f_ref_vigente('pm_alc_pozos');
    if found then
      select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) into v_f from (values
        (1, 'En el catastro levantado', to_jsonb(case when z.en_catastro then 'Sí' else 'No' end), null), (2, 'Verificación', to_jsonb(z.verificacion), null),
        (3, 'Estado del pozo', to_jsonb(z.estado_pozo), null), (4, 'Profundidad', to_jsonb(z.profundidad_m), 'm'),
        (5, 'Fecha de inspección', to_jsonb(to_char(z.fecha_inspeccion, 'YYYY-MM-DD')), null)
      ) f(o, r, v, u);
      v_grupos := v_grupos || jsonb_build_object('titulo', 'Catastro de alcantarillado 2014', 'origen', (select origen from redes.ref_cargas where id = z.carga_id), 'filas', v_f || z.datos,
        'advertencia', case when z.por_verificar then 'Figura como existente en la Alternativa 1 del Plan y no está en el catastro levantado: por verificar en campo.' end);
    end if;
  end if;
  return (select coalesce(jsonb_agg(jsonb_strip_nulls(g) order by o), '[]'::jsonb) from jsonb_array_elements(v_grupos) with ordinality x(g, o));
end $$;

-- Lo que el Plan deja «por verificar», contra los activos vigentes (por la llave de su capa). Una fila por activo y motivo.
create view redes.v_pm_por_verificar as
  select m.activo_id, 'estado'::text as grupo,
         'el modelo lo da «' || coalesce((select e.nombre from redes.estados_activo e where e.codigo = n.estado_modelo), n.estado_modelo) || '» y la ficha «'
           || (select e.nombre from redes.estados_activo e where e.codigo = m.estado_codigo) || '»' as detalle
    from redes.pm_nodos n join redes.activo_vigente_mat m on m.capa_codigo = 'acueducto_nodos' and m.llave_capa = n.llave
   where n.carga_id = redes.f_ref_vigente('pm_nodos') and n.estado_difiere and not m.retirado and n.estado_modelo is distinct from m.estado_codigo
  union all
  select m.activo_id, 'estado', 'el modelo lo da «' || coalesce((select e.nombre from redes.estados_activo e where e.codigo = t.estado_modelo), t.estado_modelo) || '» y la ficha «'
           || (select e.nombre from redes.estados_activo e where e.codigo = m.estado_codigo) || '»'
    from redes.pm_tramos t join redes.activo_vigente_mat m on m.capa_codigo = 'acueducto' and m.llave_capa = t.llave
   where t.carga_id = redes.f_ref_vigente('pm_tramos') and t.estado_difiere and not m.retirado and t.estado_modelo is distinct from m.estado_codigo
  union all
  select m.activo_id, 'valvula', 'válvula con el estado por verificar en campo (modelo: ' || coalesce(w.estado_existente, 'sin dato') || '; catastro de 2014: ' || coalesce(w.estado_catastro, 'sin dato') || ')'
    from redes.pm_valvulas w join redes.activo_vigente_mat m on m.capa_codigo = 'acueducto_nodos' and m.llave_capa = w.llave
   where w.carga_id = redes.f_ref_vigente('pm_valvulas') and w.verificar_en_campo and not m.retirado
  union all
  select m.activo_id, 'pozo', 'pozo ' || coalesce(z.familia, '') || ' que figura como existente en la Alternativa 1 y no está en el catastro levantado'
    from redes.pm_alc_pozos z join redes.activo_vigente_mat m on m.capa_codigo = 'alc_pozos' and m.llave_capa = z.llave
   where z.carga_id = redes.f_ref_vigente('pm_alc_pozos') and z.por_verificar and not m.retirado;
revoke all on table redes.v_pm_por_verificar from public, anon, authenticated, service_role;

-- Marca «por verificar» (evento con motivo; nada cambia en la ficha) a los activos de la vista que no tengan ya una marca del Plan. No repite:
-- a quien el supervisor ya verificó no se le vuelve a marcar. La corre el paquete de carga, una vez, con el correo del administrador.
create function redes.f_pm_marcar_por_verificar(p_autor text) returns integer language plpgsql set search_path = redes, public, pg_temp as $$
declare v_n integer;
begin
  if p_autor is null or position('@' in p_autor) < 2 then perform tecnica.f_error('Falta quién marca'); end if;
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor)
  select x.activo_id, 'por_verificar', left('Plan Maestro 2014: ' || string_agg(x.detalle, '; ' order by x.grupo), 1000), p_autor
    from redes.v_pm_por_verificar x
   where not exists (select 1 from redes.activo_eventos e where e.activo_id = x.activo_id and e.tipo = 'por_verificar' and e.motivo like 'Plan Maestro 2014:%')
   group by x.activo_id;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
