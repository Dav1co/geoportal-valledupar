-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del 5d publicado) con cambios exactos, aplicados una sola vez.
--   · redes.f_ficha: la sección «regulatorio» (solo supervisor y administrador);
--   · redes.f_param_entero: la unidad «hoja» es un número entero;
--   · geoportal_redes_geovisor: «edad_ref» (hay amarre vigente), para la nota de la leyenda, solo a quien ve el geovisor completo;
--   · geoportal_redes_geovisor_mvt: sin fecha de instalación, la edad sale de la fecha regulatoria de la fila (propiedad «edad_reg»), para quien ve el geovisor completo.
-- =====================================================================
-- redes.f_ficha(bigint,text)
CREATE OR REPLACE FUNCTION redes.f_ficha(p_activo bigint, p_perfil text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v redes.v_activo_vigente%rowtype; t redes.v_tipo_visible%rowtype; v_super boolean := p_perfil in ('admin', 'supervisor');
  v_campos jsonb; v_origen jsonb; v_nodo jsonb; v_tramo jsonb; v_pto geometry;
begin
  select * into v from redes.v_activo_vigente where activo_id = p_activo;
  if not found then perform tecnica.f_error('Ese activo no está vigente', 'P0002'); end if;
  select * into t from redes.v_tipo_visible where prefijo = v.prefijo;
  v_pto := case when GeometryType(v.geom) = 'POINT' then v.geom else ST_PointOnSurface(v.geom) end;
  -- campos por tipo (tipos_activo.campos): el valor sale de la columna o de atributos; nulo = «sin dato»
  select coalesce(jsonb_agg(jsonb_build_object('clave', c ->> 'clave', 'rotulo', c ->> 'rotulo', 'unidad', c ->> 'unidad',
           'valor', case c ->> 'clave'
                      when 'diametro_mm' then to_jsonb(v.diametro_mm)
                      when 'longitud_m' then to_jsonb(v.longitud_m)
                      when 'capacidad' then to_jsonb(v.capacidad)
                      when 'profundidad_m' then to_jsonb(v.profundidad_m)
                      when 'material_codigo' then to_jsonb((select m.nombre from redes.materiales m where m.codigo = v.material_codigo))
                      when 'clase' then to_jsonb((select x.nombre from redes.clases_activo x where x.prefijo = v.prefijo and x.codigo = v.clase))
                      when 'efecto' then to_jsonb((select e.nombre from redes.efectos_valvula e where e.codigo = v.efecto))
                      when 'punto_codigo' then (select to_jsonb(ap.punto_codigo) from redes.v_activo_punto_vigente ap where ap.activo_id = p_activo)
                      else v.atributos -> (c ->> 'clave') end) order by o), '[]'::jsonb)
    into v_campos
    from jsonb_array_elements(t.campos) with ordinality as e(c, o);
  if v_super then
    select jsonb_build_object('origen', o.origen, 'aportante', o.aportante_codigo, 'aportante_nombre', a.nombre, 'tiene_soporte', o.soporte_ruta is not null, 'nota', o.nota)
      into v_origen from redes.v_activo_origen_vigente o left join redes.entidades_aportantes a on a.codigo = o.aportante_codigo where o.activo_id = p_activo;
  end if;
  -- si el activo es un nodo de la topología: cuántos tramos llegan
  select jsonb_build_object('nombre_modelo', n.nombre_modelo, 'nombre_visible', n.nombre_visible,
           'tramos', redes.f_tramos_de_nodo(n.nodo_id))
    into v_nodo from redes.f_nodo_de_activo(p_activo) n limit 1;      -- 9a-bis: por índice
  -- si es un tramo: sus dos extremos (con el activo de cada nodo, si lo tiene)
  select jsonb_build_object('metodo', tn.metodo,
           'inicio', (select jsonb_build_object('nombre', n.nombre_visible, 'activo', redes.f_activo_corto(n.activo_id)) from redes.f_nodo_visible_id(tn.nodo_ini) n),
           'fin', (select jsonb_build_object('nombre', n.nombre_visible, 'activo', redes.f_activo_corto(n.activo_id)) from redes.f_nodo_visible_id(tn.nodo_fin) n))
    into v_tramo from redes.tramo_nodos tn join redes.activo_vigente_mat tv on tv.activo_id = tn.activo_id and tv.version = tn.version where tn.activo_id = p_activo;
  return jsonb_strip_nulls(jsonb_build_object(
    'perfil', p_perfil,
    'activo', jsonb_build_object(
      'codigo', v.codigo, 'prefijo', v.prefijo, 'tipo', t.nombre_visible, 'tipo_catalogo', t.nombre,
      'sistema', v.sistema, 'sistema_nombre', (select s.nombre from redes.sistemas s where s.codigo = v.sistema), 'etapa', t.etapa, 'geometria', t.geometria,
      'nombre', v.nombre, 'clase', (select x.nombre from redes.clases_activo x where x.prefijo = v.prefijo and x.codigo = v.clase),
      'estado', (select s.nombre from redes.estados_activo s where s.codigo = v.estado_codigo), 'estado_codigo', v.estado_codigo,
      'cuenta_vigente', v.cuenta_vigente, 'punteado', v.punteado, 'retirado', v.retirado, 'oculto', v.oculto, 'por_verificar', v.por_verificar,
      'material', (select m.nombre from redes.materiales m where m.codigo = v.material_codigo),
      'fecha_instalacion', v.fecha_instalacion, 'barrio_sector', v.barrio_sector, 'codigo_anterior', v.codigo_anterior,
      'version', v.version, 'version_creada_en', v.version_creada_en, 'lat', round(ST_Y(v_pto)::numeric, 6), 'lon', round(ST_X(v_pto)::numeric, 6),
      'campos', v_campos),
    -- Corte 9a: se lee de las tablas de referencia y de los polígonos vigentes de sectores. 9a-bis: el sector hidráulico (por la ubicación) es el oficial
    'sector_hidraulico', case when v.prefijo <> 'SEC' then (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector, 'codigo', s.codigo, 'nombre', s.nombre)
                                                        from redes.f_sector_de(v.geom) s where s.sector is not null) end,
    'referencia', case when v_super then nullif(redes.f_ficha_referencia(p_activo), '[]'::jsonb) end,
    -- Corte 10: inventario regulatorio (la fila de la Valoración Técnica 2019 a la que está amarrado). Solo supervisor y administrador
    'regulatorio', case when v_super then redes.f_ficha_regulatorio(p_activo, v.prefijo) end,
    'por_verificar_motivo', case when v.por_verificar then (select e.motivo from redes.activo_eventos e where e.activo_id = p_activo and e.tipo = 'por_verificar' order by e.id desc limit 1) end,
    'origen', v_origen,
    'modelo', case when v_super then v.atributos -> 'modelo' end,
    'nodo', v_nodo,
    'tramo', v_tramo,
    'contratos_enlazados', case when v.prefijo in ('RED', 'CON') then (select count(*) from redes.contrato_tramo ct where ct.activo_id = p_activo) end,
    'componentes', (select coalesce(jsonb_agg(redes.f_activo_corto(c.hijo_id) order by h.codigo), '[]'::jsonb)
                      from redes.v_componentes_vigentes c join redes.activos h on h.id = c.hijo_id where c.padre_id = p_activo
                       and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = c.hijo_id)),
    'parte_de', (select coalesce(jsonb_agg(redes.f_activo_corto(c.padre_id) order by p.codigo), '[]'::jsonb)
                   from redes.v_componentes_vigentes c join redes.activos p on p.id = c.padre_id where c.hijo_id = p_activo
                    and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = c.padre_id)),
    'admite_componentes', (select admite_componentes from redes.tipos_activo where prefijo = v.prefijo),
    -- «hechos»: daños, fallas e intervenciones (los suma la epicrisis desde los Cortes 2 y 3); «registro»: altas, versiones, retiros y componentes
    'epicrisis', jsonb_build_object(
      'hechos', (select count(*) from redes.v_epicrisis e where e.activo_id = p_activo and e.clase in ('dano', 'falla', 'intervencion')),
      'registro', (select count(*) from redes.v_epicrisis e where e.activo_id = p_activo and e.clase not in ('dano', 'falla', 'intervencion')),
      'danos_12_meses', (select count(*) from redes.v_epicrisis e where e.activo_id = p_activo and e.clase in ('dano', 'falla') and e.cuando >= now() - interval '12 months'))));
end $function$;

-- redes.f_param_entero(text)
CREATE OR REPLACE FUNCTION redes.f_param_entero(p_unidad text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select p_unidad in ('fotos', 'documentos', 'materiales', 'activos', 'días', 'horas', 'filas', 'bytes', 'zoom', 'hoja') $function$;

-- public.geoportal_redes_geovisor_mvt(text,integer,integer,integer)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor_mvt(p_solicitante text, p_z integer, p_x integer, p_y integer)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare a record; v_am bigint; v_val bigint; v_hoja text; v_env geometry; v_env4326 geometry; v bytea; v_pref text[]; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        z_min numeric := redes.f_param('geovisor_zoom_min'); z_red numeric := redes.f_param('geovisor_zoom_red_completa');
        z_nod numeric := redes.f_param('geovisor_zoom_nodos'); z_acc numeric := redes.f_param('geovisor_zoom_acc');
        d_acu numeric := redes.f_param('geovisor_diam_principal_acu_mm'); d_alc numeric := redes.f_param('geovisor_diam_principal_alc_mm');
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if a.completo then v_val := redes.f_ref_vigente('valoracion'); v_am := redes.f_ref_vigente('val_amarre'); v_hoja := redes.f_val_hoja_alc(); end if;      -- Corte 10
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < z_min then return ''; end if;
  select array_agg(distinct p) into v_pref from redes.geovisor_capas g cross join unnest(g.prefijos) p where g.activa and g.fuente = 'tesela' and (a.completo or not g.solo_completo);
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4326 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'activos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, m.codigo, m.prefijo, m.sistema,
           case GeometryType(m.geom) when 'POINT' then 'nodo' when 'POLYGON' then 'area' when 'MULTIPOLYGON' then 'area' else 'tramo' end as forma,
           coalesce(m.clase, '') as clase, coalesce(m.material_codigo, '') as material, m.diametro_mm::real as diametro,
           case when m.fecha_instalacion is not null then greatest(0, extract(year from age(v_hoy, m.fecha_instalacion)))::integer
                when r.fecha is not null then greatest(0, extract(year from age(v_hoy, r.fecha)))::integer end as edad,
           case when m.fecha_instalacion is null and r.fecha is not null then true end as edad_reg,      -- Corte 10: fecha regulatoria, no de instalación
           m.estado_codigo as estado, m.punteado,
           case when m.prefijo in ('SEC', 'TAN', 'PTA', 'CAP', 'DES', 'EBA', 'EBR', 'PTR') then m.nombre end as nombre
      from redes.activo_vigente_mat m
      left join lateral (select min(f.fecha_operacion) as fecha
                           from redes.val_amarre am join redes.val_filas f on f.carga_id = am.val_carga_id and f.hoja = am.hoja and f.n = am.n
                          where v_am is not null and m.fecha_instalacion is null and am.activo_id = m.activo_id and am.carga_id = v_am and am.val_carga_id = v_val
                            and am.hoja in ('acueducto', v_hoja) and am.n is not null) r on true
     where not m.retirado and not m.oculto and m.prefijo = any (v_pref)
       and m.geom && v_env4326
       and case
             when m.prefijo = 'ACC' then p_z >= z_acc
             when m.prefijo in ('TAN', 'PTA', 'CAP', 'DES', 'EBA', 'EBR', 'PTR', 'SEC') then true
             when GeometryType(m.geom) = 'POINT' then p_z >= z_nod
             when p_z >= z_red then true
             else m.prefijo in ('CON', 'ADU', 'INT')
                  or (m.sistema = 'acueducto' and m.diametro_mm >= d_acu) or (m.sistema = 'alcantarillado' and m.diametro_mm >= d_alc)
           end) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $function$;

-- public.geoportal_redes_geovisor(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare a record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  return jsonb_build_object(
    'perfil', case when a.admin then 'admin' when a.completo then 'supervisor' else 'operador' end,
    'completo', a.completo, 'perfiles', to_jsonb(a.perfiles),
    'hoy', (clock_timestamp() at time zone 'America/Bogota')::date,
    'rango_meses', floor(redes.f_param('geovisor_rango_meses'))::integer,
    'max_elementos', floor(redes.f_param('geovisor_max_elementos'))::integer,
    'zoom', jsonb_build_object('min', redes.f_param('geovisor_zoom_min'), 'red_completa', redes.f_param('geovisor_zoom_red_completa'),
                               'nodos', redes.f_param('geovisor_zoom_nodos'), 'accesorios', redes.f_param('geovisor_zoom_acc'),
                               'contratos', redes.f_param('geovisor_zoom_contratos')),
    'version', (select coalesce(sum(version), 0) from redes.tesela_version),
    'formularios', jsonb_build_object('danos_fallas', redes.f_puede_formulario(a.email, 'danos_fallas'),
                                      'mantenimiento', redes.f_puede_formulario(a.email, 'mantenimiento')),
    'ficha', a.completo, 'compartir', a.completo,
    'edad_ref', case when a.completo and redes.f_ref_vigente('val_amarre') is not null then true end,      -- Corte 10: hay amarre con la valoración
    'contratos_corte', case when a.completo then (select max(s.periodo_carga) from public.cartera_suscripcion s) end,      -- Corte 7a: fecha (AAAAMMDD) del último corte de la cartera
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre, 'grupo', g.grupo, 'fuente', g.fuente, 'estado', g.estado, 'nota', g.nota,
                                          'prefijos', to_jsonb(g.prefijos), 'por_fecha', g.por_fecha,
                                          'encendida', exists (select 1 from redes.capas_por_perfil c where c.capa = g.codigo and c.encendida and c.perfil = any (a.perfiles)))
             order by g.orden)
        from redes.geovisor_capas g where g.activa and (a.completo or not g.solo_completo)), '[]'::jsonb),
    'tipos', coalesce((select jsonb_object_agg(t.prefijo, t.nombre_visible) from redes.v_tipo_visible t), '{}'::jsonb),
    'estados', coalesce((select jsonb_object_agg(e.codigo, e.nombre) from redes.estados_activo e), '{}'::jsonb),
    'materiales', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', m.nombre) order by m.codigo) from redes.materiales m), '[]'::jsonb),
    -- solo el administrador: la tabla de capas por omisión, para editarla (N-11)
    'por_perfil', case when a.admin then coalesce((
      select jsonb_agg(jsonb_build_object('perfil', c.perfil, 'capa', c.capa, 'encendida', c.encendida, 'actualizado_en', c.actualizado_en, 'actualizado_por', c.actualizado_por)
             order by c.perfil, c.capa) from redes.capas_por_perfil c), '[]'::jsonb) end);
end $function$;
