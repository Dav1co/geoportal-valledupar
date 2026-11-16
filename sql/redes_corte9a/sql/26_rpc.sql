-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 26 — RPC NUEVAS (solo service_role: la Edge geoportal-redes). Todas leen, salvo nodo_clasificar y activo_verificar,
-- que insertan UN evento con motivo. Ninguna rehace ni recalcula tablas.
--   · geoportal_redes_geovisor_mvt_ref: tesela de una capa de referencia del geovisor (fuente «referencia»).
--   · geoportal_redes_referencia: la tarjeta de un elemento de referencia (con la serie de la campaña o el perfil horario del modelo).
--   · geoportal_redes_nodo_preliminar: ficha preliminar, de solo lectura, de un nodo «por clasificar» (encargo, punto 13).
--   · geoportal_redes_nodo_clasificar: el administrador confirma «dejar como nodo» o «propuesto por el Plan: no crear activo» (o lo devuelve a la bandeja).
--   · geoportal_redes_por_verificar y geoportal_redes_activo_verificar: la bandeja «Por verificar» del supervisor y la marca «verificado», con lo que se encontró.
-- =====================================================================
create function public.geoportal_redes_geovisor_mvt_ref(p_solicitante text, p_capa text, p_z integer, p_x integer, p_y integer) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; g redes.geovisor_capas%rowtype; v_env geometry; v_env4 geometry; v bytea;
        z_min numeric := redes.f_param('geovisor_zoom_min'); z_nod numeric := redes.f_param('geovisor_zoom_nodos');
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into g from redes.geovisor_capas where codigo = p_capa and activa and fuente = 'referencia';
  if not found then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if g.solo_completo and not a.completo then raise exception 'Capa solo para supervisores' using errcode = '42501'; end if;
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < z_min then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4 := ST_Transform(v_env, 4326);
  if p_capa = 'presion_modelo' then
    -- un punto por nodo con presión de la red existente. De lejos, solo los nodos que son activo «grande» no se distinguen: se muestran todos desde el zoom de nodos
    -- y, antes, uno de cada cuatro (por su llave), para que la tesela no pese.
    select ST_AsMVT(t, 'ref', 4096, 'geom') into v from (
      select ST_AsMVTGeom(ST_Transform(n.geom, 3857), v_env, 4096, 32, true) as geom, n.llave, 'nodo'::text as forma, coalesce(n.nombre, n.llave) as nombre,
             n.pres_exist_mediana::real as valor, redes.f_pm_nivel_presion(n.pres_exist_mediana) as nivel
        from redes.pm_nodos n
       where n.carga_id = redes.f_ref_vigente('pm_nodos') and n.pres_exist_mediana is not null and n.geom && v_env4
         and (p_z >= z_nod or abs(hashtext(n.llave)) % 4 = 0)) t
     where t.geom is not null;
  else
    select ST_AsMVT(t, 'ref', 4096, 'geom') into v from (
      select ST_AsMVTGeom(ST_Transform(e.geom, 3857), v_env, 4096, 64, true) as geom, e.llave,
             case GeometryType(e.geom) when 'POINT' then 'nodo' when 'POLYGON' then 'area' when 'MULTIPOLYGON' then 'area' else 'tramo' end as forma,
             coalesce(e.nombre, e.llave) as nombre, coalesce(e.clase, '') as clase, coalesce(e.estado, '') as estado, e.valor::real as valor,
             case when p_capa = 'campana_2014' then redes.f_pm_nivel_presion(e.valor) end as nivel
        from redes.ref_elementos e
       where e.capa = p_capa and e.carga_id in (select id from redes.v_ref_carga_vigente) and e.geom is not null and e.geom && v_env4
         and (p_capa = 'campana_2014' or GeometryType(e.geom) <> 'POINT' or p_z >= z_nod)) t
     where t.geom is not null;
  end if;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $$;

create function public.geoportal_redes_referencia(p_solicitante text, p_capa text, p_llave text) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; g redes.geovisor_capas%rowtype; e redes.ref_elementos%rowtype; n redes.pm_nodos%rowtype; v_ll text := btrim(coalesce(p_llave, '')); v_act bigint; v_sec record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into g from redes.geovisor_capas where codigo = p_capa and activa and fuente = 'referencia';
  if not found then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if g.solo_completo and not a.completo then raise exception 'Capa solo para supervisores' using errcode = '42501'; end if;
  if v_ll = '' or length(v_ll) > 120 then perform tecnica.f_error('Falta el elemento'); end if;
  if p_capa = 'presion_modelo' then
    select * into n from redes.pm_nodos x where x.llave = v_ll and x.carga_id = redes.f_ref_vigente('pm_nodos');
    if not found then perform tecnica.f_error('Ese nodo no está en el modelo', 'P0002'); end if;
    select * into v_sec from redes.f_sector_de(n.geom);
    select k.activo_id into v_act from redes.v_nodo_vigente k where k.sistema = 'acueducto' and k.llave_modelo = v_ll and k.activo_id is not null
       and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = k.activo_id and not m.retirado);
    return jsonb_strip_nulls(jsonb_build_object('capa', p_capa, 'llave', v_ll, 'titulo', coalesce(n.nombre, v_ll), 'subtitulo', 'Nodo del modelo · ' || coalesce(n.tipo, 'sin tipo'),
      'origen', (select origen from redes.ref_cargas where id = n.carga_id),
      'advertencia', 'Presión de MODELO, no medida.' || case when n.pres_exist_negativa then ' El modelo de la red existente da presión negativa en este nodo a alguna hora del día.' else '' end,
      'nivel', redes.f_pm_nivel_presion(n.pres_exist_mediana),
      'activo', case when v_act is not null then (select codigo from redes.activos where id = v_act) end,
      'filas', (select coalesce(jsonb_agg(jsonb_build_object('r', f.r, 'v', f.v, 'u', f.u) order by f.o) filter (where f.v is not null), '[]'::jsonb) from (values
        (1, 'Red existente: mediana del día', to_jsonb(n.pres_exist_mediana), 'm.c.a.'), (2, 'Red existente: mínima', to_jsonb(n.pres_exist_min), 'm.c.a.'),
        (3, 'Red existente: máxima', to_jsonb(n.pres_exist_max), 'm.c.a.'), (4, 'Red futura del Plan: mediana', to_jsonb(n.pres_futura_mediana), 'm.c.a.'),
        (5, 'Red futura del Plan: mínima', to_jsonb(n.pres_futura_min), 'm.c.a.'), (6, 'Red futura del Plan: máxima', to_jsonb(n.pres_futura_max), 'm.c.a.'),
        (7, 'Cota', to_jsonb(n.cota_m), 'm'), (8, 'Demanda (red existente)', to_jsonb(n.demanda_exist_lps), 'L/s'),
        (9, 'Sector según el Plan', to_jsonb(case when v_sec.sector is not null then v_sec.sector || coalesce(' · subsector ' || v_sec.subsector, '') end), null)) f(o, r, v, u)),
      'series', (select jsonb_agg(jsonb_build_object('nombre', case p.escenario when 'existente' then 'Red existente (modeloV1)' else 'Red futura del Plan (ModeloVF)' end,
                                                     'escenario', p.escenario, 'unidad', 'm.c.a.', 'eje', 'hora', 'valores', to_jsonb(p.horas)) order by p.escenario)
                   from redes.pm_presion_hora p
                  where p.llave = v_ll and p.carga_id in (redes.f_ref_vigente('pm_presion_existente'), redes.f_ref_vigente('pm_presion_futura')))));
  end if;
  select x.* into e from redes.ref_elementos x where x.capa = p_capa and x.llave = v_ll and x.carga_id in (select id from redes.v_ref_carga_vigente) order by x.carga_id desc limit 1;
  if not found then perform tecnica.f_error('Ese elemento no está en la capa', 'P0002'); end if;
  select * into v_sec from redes.f_sector_de(e.geom);
  return jsonb_strip_nulls(jsonb_build_object('capa', p_capa, 'llave', v_ll, 'titulo', coalesce(e.nombre, v_ll), 'subtitulo', g.nombre,
    'origen', (select origen from redes.ref_cargas where id = e.carga_id),
    'advertencia', case p_capa when 'campana_2014' then 'Presión MEDIDA en campo en 2014 (no es la presión de hoy).'
                               when 'plan_valvulas' then 'Válvula PROPUESTA por el Plan: no está instalada, no es un activo y no entra en ninguna simulación.'
                               when 'pluvial_2043' then 'Alternativa del Plan a 2043: incluye lo existente y lo propuesto.' else 'Capa de referencia: no es un activo.' end,
    'nivel', case when p_capa = 'campana_2014' then redes.f_pm_nivel_presion(e.valor) end,
    'filas', e.datos || case when v_sec.sector is not null then jsonb_build_array(jsonb_build_object('r', 'Sector según el Plan', 'v', v_sec.sector || coalesce(' · subsector ' || v_sec.subsector, ''))) else '[]'::jsonb end,
    'series', case when p_capa = 'campana_2014' then (
      select jsonb_build_array(jsonb_build_object('nombre', 'Presión medida cada 15 min', 'unidad', 'm.c.a.', 'eje', 'tiempo',
               'puntos', coalesce(jsonb_agg(jsonb_build_array(to_char(l.cuando, 'YYYY-MM-DD"T"HH24:MI'), l.p_mca) order by l.n), '[]'::jsonb)))
        from redes.pm_campana_lecturas l where l.llave = v_ll and l.carga_id = redes.f_ref_vigente('campana_2014_lecturas')) end));
end $$;

-- Ficha preliminar de un nodo «por clasificar»: solo lectura. Con qué se decide: dónde está, qué tramos le llegan, su cota, su sector y lo que dice el modelo.
create function public.geoportal_redes_nodo_preliminar(p_solicitante text, p_nodo bigint) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_autorizar_admin(p_solicitante); n redes.v_nodo_visible%rowtype; v_sec record; v_mod jsonb;
begin
  select * into n from redes.v_nodo_visible where nodo_id = p_nodo;
  if not found then perform tecnica.f_error('No existe ese nodo (o ya no es el vigente)', 'P0002'); end if;
  select * into v_sec from redes.f_sector_de(n.geom);
  v_mod := redes.f_nodo_modelo(n.llave_modelo);
  return jsonb_strip_nulls(jsonb_build_object(
    'nodo_id', n.nodo_id, 'sistema', n.sistema, 'llave_modelo', n.llave_modelo, 'nombre_modelo', n.nombre_modelo, 'nombre_visible', n.nombre_visible, 'clase_nodo', n.clase_nodo,
    'lat', round(ST_Y(n.geom)::numeric, 6), 'lon', round(ST_X(n.geom)::numeric, 6),
    'sector', case when v_sec.sector is not null then jsonb_build_object('sector', v_sec.sector, 'subsector', v_sec.subsector, 'codigo', v_sec.codigo, 'nombre', v_sec.nombre) end,
    'modelo', v_mod - 'sugerencia',
    'sugerencia', v_mod -> 'sugerencia',
    'tramos', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'prefijo', m.prefijo, 'nombre', m.codigo_anterior,
                                 'material', (select x.nombre from redes.materiales x where x.codigo = m.material_codigo), 'diametro_mm', m.diametro_mm, 'longitud_m', m.longitud_m,
                                 'estado', (select s.nombre from redes.estados_activo s where s.codigo = m.estado_codigo), 'extremo', case when t.nodo_ini = n.nodo_id then 'inicio' else 'fin' end,
                                 'linea', ST_AsGeoJSON(m.geom, 6)::jsonb) order by m.codigo)
                          from redes.tramo_nodos t join redes.activo_vigente_mat m on m.activo_id = t.activo_id and m.version = t.version and not m.retirado
                         where t.nodo_ini = n.nodo_id or t.nodo_fin = n.nodo_id), '[]'::jsonb)));
end $$;

create function public.geoportal_redes_nodo_clasificar(p_solicitante text, p_nodo bigint, p_clase text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_autorizar_admin(p_solicitante); n redes.v_nodo_visible%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if coalesce(p_clase, '') not in ('nodo_calculo', 'propuesta_plan', 'por_clasificar') then perform tecnica.f_error('Esa clasificación no existe'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.nodo.' || coalesce(p_nodo, 0)));
  select * into n from redes.v_nodo_visible where nodo_id = p_nodo;
  if not found then perform tecnica.f_error('No existe ese nodo (o ya no es el vigente)', 'P0002'); end if;
  if n.clase_nodo in ('activo', 'pozo_virtual') then perform tecnica.f_error('Ese nodo ya es un activo (o un pozo virtual): no se clasifica aquí'); end if;
  if n.clase_nodo = p_clase then perform tecnica.f_error('Ese nodo ya está así'); end if;
  insert into redes.nodo_eventos (nodo_id, tipo, clase, motivo, autor) values (n.nodo_id, 'clasificar', p_clase, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_nodo_clasificar', n.nodo_id::text, jsonb_build_object('nodo', n.nombre_modelo, 'llave', n.llave_modelo, 'antes', n.clase_nodo, 'clase', p_clase, 'motivo', v_mot), null);
  return jsonb_build_object('nodo_id', n.nodo_id, 'nombre_modelo', n.nombre_modelo, 'clase_nodo', p_clase);
end $$;

-- Bandeja «Por verificar» (supervisor de distribución y administrador): los activos con la marca vigente, con su motivo. Grupos: lo que dejó el Plan
-- (estado, válvula, pozo) y «otros» (los activos nuevos de una inversión, que ya quedaban por verificar desde el Corte 3a).
create function public.geoportal_redes_por_verificar(p_solicitante text, p_grupo text default null, p_despues_de bigint default null, p_limite integer default 50) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 've la bandeja de activos por verificar'); v_lim integer := coalesce(p_limite, 50); v_items jsonb; v_grupos jsonb;
begin
  if v_lim < 1 or v_lim > 200 then perform tecnica.f_error('Se piden de 1 a 200'); end if;
  if p_grupo is not null and p_grupo not in ('estado', 'valvula', 'pozo', 'otros') then perform tecnica.f_error('Ese grupo no existe'); end if;
  -- el último evento de verificación de cada activo; queda en la lista si es «por_verificar»
  with ult as (select distinct on (e.activo_id) e.activo_id, e.tipo, e.motivo, e.creado_en, e.id
                 from redes.activo_eventos e where e.tipo in ('verificar', 'por_verificar') order by e.activo_id, e.id desc),
       pv as (select u.activo_id, u.motivo, u.creado_en,
                     -- el grupo sale del motivo guardado (un hecho), no de la referencia vigente: si se carga otra versión del Plan, la bandeja no cambia de grupo
                     case when u.motivo not like 'Plan Maestro 2014:%' then 'otros' when u.motivo like '%válvula con el estado por verificar%' then 'valvula'
                          when u.motivo like '%que figura como existente en la Alternativa 1%' then 'pozo' else 'estado' end as grupo
                from ult u where u.tipo = 'por_verificar'
                 and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = u.activo_id and not m.retirado)),
       pag as (select p.* from pv p where (p_grupo is null or p.grupo = p_grupo) and (p_despues_de is null or p.activo_id > p_despues_de) order by p.activo_id limit v_lim)
  select (select coalesce(jsonb_agg(jsonb_build_object('grupo', g.grupo, 'n', g.n) order by g.grupo), '[]'::jsonb) from (select grupo, count(*) as n from pv group by 1) g),
         (select coalesce(jsonb_agg(jsonb_build_object('activo_id', p.activo_id, 'codigo', m.codigo, 'prefijo', m.prefijo, 'tipo', (select t.nombre_visible from redes.v_tipo_visible t where t.prefijo = m.prefijo),
                    'nombre', coalesce(m.nombre, m.codigo_anterior), 'sistema', m.sistema, 'estado', (select s.nombre from redes.estados_activo s where s.codigo = m.estado_codigo),
                    'grupo', p.grupo, 'motivo', p.motivo, 'desde', p.creado_en,
                    'lat', round(ST_Y(ST_PointOnSurface(m.geom))::numeric, 6), 'lon', round(ST_X(ST_PointOnSurface(m.geom))::numeric, 6)) order by p.activo_id), '[]'::jsonb)
            from pag p join redes.activo_vigente_mat m on m.activo_id = p.activo_id)
    into v_grupos, v_items;
  return jsonb_build_object('grupos', v_grupos, 'total', (select coalesce(sum((g ->> 'n')::integer), 0) from jsonb_array_elements(v_grupos) g where p_grupo is null or g ->> 'grupo' = p_grupo),
    'items', v_items, 'siguiente', case when jsonb_array_length(v_items) = v_lim then (v_items -> (v_lim - 1) ->> 'activo_id')::bigint end);
end $$;

create function public.geoportal_redes_activo_verificar(p_solicitante text, p_ref text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'marca un activo como verificado'); v_id bigint; v_mot text := btrim(coalesce(p_motivo, '')); v_cod text;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba lo que se encontró al verificar (10 caracteres o más)'); end if;
  v_id := redes.f_buscar_activo(p_ref);
  perform pg_advisory_xact_lock(hashtext('redes.activo.' || v_id));
  if not (select e.por_verificar from redes.v_activo_estado e where e.activo_id = v_id) then perform tecnica.f_error('Ese activo no está por verificar'); end if;
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (v_id, 'verificar', v_mot, v_email);
  select codigo into v_cod from redes.activos where id = v_id;
  perform tecnica.f_auditar(v_email, 'redes_activo_verificar', v_cod, jsonb_build_object('motivo', v_mot), null);
  return jsonb_build_object('codigo', v_cod, 'por_verificar', false);
end $$;
