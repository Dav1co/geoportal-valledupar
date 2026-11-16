begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 10 — GUARDIA Y CATÁLOGO
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code B). Generado por pruebas_locales/generar.py.
-- · Presupone el Corte 9a publicado (huella del conjunto de funciones de redes 4a46069fc3c71c305c49bafd764f316e).
-- · Respuestas de David del 16-nov: (1) clasifican nodos el supervisor de distribución y el administrador; (3) confirmar nodos por grupo (solo «no crear activo»),
--   con motivo y vista previa; (4) los 7 sectores del Plan SON los que se operan hoy: el sector calculado es el oficial y el formulario de daño lo propone.
-- · La ficha deja de recorrer tablas enteras (tardaba 4,4 s en producción).
-- · Sin tablas nuevas. Los sectores pasan a «En operación» con una carga nueva por el motor (carga_sectores/), no en esta migración.
-- =====================================================================
do $$
begin
  if to_regprocedure('redes.f_nodo_visible_id(bigint)') is not null then raise exception 'El Corte 9a-bis ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '4a46069fc3c71c305c49bafd764f316e' then
    raise exception 'Las funciones de redes no son las del Corte 9a publicado (huella 4a46069fc3c71c305c49bafd764f316e): deténgase y avise';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'redes' and indexname in ('ix_nodos_llave')) or not exists (select 1 from pg_indexes where schemaname = 'redes' and indexname = 'ix_tn_ini')
     or not exists (select 1 from pg_indexes where schemaname = 'redes' and indexname = 'ix_tn_fin') or not exists (select 1 from pg_indexes where schemaname = 'redes' and indexname = 'ix_nodos_activo') then
    raise exception 'Faltan los índices de nodos y tramo_nodos con que la ficha responde rápido: deténgase y avise';
  end if;
end $$;

-- los sectores del Plan son los de hoy (respuesta 4): cambia la nota de la capa (el estado de los polígonos lo cambia la carga de carga_sectores/)
update redes.geovisor_capas set nombre = 'Sectores hidráulicos',
       nota = '7 sectores y 29 subsectores con que se opera (los del Plan Maestro 2014). El sector de cada activo, daño y contrato sale de su ubicación'
 where codigo = 'sectores';
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 20 — FUNCIONES INTERNAS NUEVAS (nadie de la API las ejecuta)
--   · redes.f_nodo_visible_id, redes.f_nodo_de_activo y redes.f_tramos_de_nodo: el nodo vigente de un id o de un activo y los tramos que le llegan, POR ÍNDICE.
--     Antes, la ficha los buscaba en las vistas v_nodo_visible y v_tramo_nodos_vigente filtrando por una columna que no es su llave: cada ficha ordenaba
--     todos los nodos y recorría TODA la tabla de versiones de activos (con sus geometrías). En producción, 4,4 s por ficha.
--     Ahora se toma la llave del nodo (sistema y llave del modelo, la llave de la vista) y la vista se consulta solo por ella.
--   · redes.f_sector_en: el sector hidráulico de un punto (latitud y longitud), para el formulario de daño y para el daño que entra del bot.
--   · redes.f_operador_redes: quién es «operador de redes» (ve la Ficha de activos en modo buscar, solo lectura).
-- =====================================================================
create function redes.f_nodo_visible_id(p_nodo bigint) returns setof redes.v_nodo_visible
language plpgsql stable set search_path = redes, public, pg_temp as $$
declare v_s text; v_l text;
begin
  select x.sistema, x.llave_modelo into v_s, v_l from redes.nodos x where x.id = p_nodo;
  if v_s is null then return; end if;
  -- por la llave de la vista (sistema, llave_modelo): la condición entra en la vista y usa el índice ix_nodos_llave. Si el id no es el vigente de su llave, no sale (igual que antes).
  return query select * from redes.v_nodo_visible n where n.sistema = v_s and n.llave_modelo = v_l and n.nodo_id = p_nodo;
end $$;

create function redes.f_nodo_de_activo(p_activo bigint) returns setof redes.v_nodo_visible
language plpgsql stable set search_path = redes, public, pg_temp as $$
declare k record;
begin
  -- las llaves candidatas: el nodo que nació con el activo (carga) o al que se le enlazó (bandeja de nodos)
  for k in select x.sistema, x.llave_modelo from redes.nodos x where x.activo_id = p_activo
           union
           select x.sistema, x.llave_modelo from redes.nodo_eventos e join redes.nodos x on x.id = e.nodo_id where e.activo_id = p_activo and e.tipo = 'enlazar_activo' loop
    return query select * from redes.v_nodo_visible n where n.sistema = k.sistema and n.llave_modelo = k.llave_modelo and n.activo_id = p_activo;
  end loop;
end $$;

create function redes.f_tramos_de_nodo(p_nodo bigint) returns integer
language sql stable set search_path = redes, pg_temp as $$
  -- la versión vigente de cada tramo es la de activo_vigente_mat (la misma que daba la vista), por los índices de tramo_nodos
  select count(*)::integer from redes.tramo_nodos t join redes.activo_vigente_mat m on m.activo_id = t.activo_id and m.version = t.version
   where t.nodo_ini = p_nodo or t.nodo_fin = p_nodo $$;

create function redes.f_sector_en(p_lat numeric, p_lon numeric, out sector integer, out subsector text, out codigo text, out nombre text)
language plpgsql stable set search_path = redes, public, extensions, pg_temp as $$
begin
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then return; end if;
  select s.sector, s.subsector, s.codigo, s.nombre into sector, subsector, codigo, nombre
    from redes.f_sector_de(ST_SetSRID(ST_MakePoint(p_lon::double precision, p_lat::double precision), 4326)) s;
end $$;

create function redes.f_operador_redes(p_email text) returns boolean
language sql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
  -- área distribución (o las dos) en Personal, un formulario de distribución asignado o la casilla del geovisor
  select coalesce(redes.f_area(p_email) in ('distribucion', 'ambas'), false)
      or coalesce(redes.f_puede_formulario(p_email, 'danos_fallas'), false) or coalesce(redes.f_puede_formulario(p_email, 'mantenimiento'), false)
      or coalesce(redes.f_geovisor_lectura(p_email), false) $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 26 — RPC NUEVAS (solo service_role: la Edge geoportal-redes)
--   · geoportal_redes_sector_en: el sector hidráulico de un punto. El formulario de daño lo propone desde la ubicación (respuesta 4 de David, 16-nov).
--   · geoportal_redes_nodos_clasificar_grupo: confirmar de una vez un grupo de «no crear activo» (respuesta 3 de David): primero la vista previa (cuántos,
--     cuáles y en qué sectores, con una huella del grupo), luego confirmar con un motivo y esa huella. Si el grupo cambió entre la vista previa y la
--     confirmación, se niega. Un evento «clasificar» por nodo; nada se borra ni se crea ningún activo.
-- =====================================================================
create function public.geoportal_redes_sector_en(p_solicitante text, p_lat numeric, p_lon numeric) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare p record; s record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then perform tecnica.f_error('La posición no es válida'); end if;
  select * into s from redes.f_sector_en(p_lat, p_lon);
  return jsonb_build_object('sector', s.sector, 'subsector', s.subsector, 'nombre', s.nombre);
end $$;

create function public.geoportal_redes_nodos_clasificar_grupo(p_solicitante text, p_grupo text, p_huella text default null, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'clasifica nodos'); v_mot text := btrim(coalesce(p_motivo, ''));
        v_ids bigint[]; v_ids2 bigint[]; v_texto text; v_clase text; v_n integer; v_huella text;
begin
  if coalesce(p_grupo, '') not in ('valvula_propuesta', 'macro_proyectado', 'tanque_proyectado') then
    perform tecnica.f_error('Ese grupo no existe: por grupo solo se confirman los de «no crear activo»');
  end if;
  select array_agg(b.nodo_id order by b.nodo_id), min(b.sug ->> 'texto'), min(b.sug ->> 'clase') into v_ids, v_texto, v_clase
    from (select n.nodo_id, redes.f_pm_sugerencia(pm.tipo, pm.que_es, pm.nombre, pm.zona_modelo) as sug
            from redes.v_nodo_visible n
            join redes.pm_nodos pm on n.sistema = 'acueducto' and pm.llave = n.llave_modelo and pm.carga_id = redes.f_ref_vigente('pm_nodos')
           where n.clase_nodo = 'por_clasificar') b
   where b.sug ->> 'accion' = 'no_crear' and b.sug ->> 'grupo' = p_grupo;
  v_n := coalesce(cardinality(v_ids), 0);
  v_huella := md5(coalesce(array_to_string(v_ids, ','), ''));
  if p_huella is null then      -- vista previa: no escribe nada
    return jsonb_build_object('vista_previa', true, 'grupo', p_grupo, 'texto', v_texto, 'clase', v_clase, 'n', v_n, 'huella', v_huella,
      'muestra', coalesce((select jsonb_agg(jsonb_build_object('nodo_id', x.id, 'nombre', coalesce(x.nombre_modelo, x.llave_modelo)) order by x.id)
                             from redes.nodos x where x.id = any (v_ids[1:30])), '[]'::jsonb),
      'por_sector', coalesce((select jsonb_agg(jsonb_build_object('sector', s.sector, 'n', s.n) order by s.sector nulls last)
                                from (select (select z.sector from redes.f_sector_de(x.geom) z) as sector, count(*) as n
                                        from redes.nodos x where x.id = any (v_ids) group by 1) s), '[]'::jsonb));
  end if;
  if v_n = 0 then perform tecnica.f_error('No quedan nodos en ese grupo'); end if;
  if p_huella <> v_huella then perform tecnica.f_error('El grupo cambió desde la vista previa (alguien clasificó un nodo): vuelva a ver la vista previa'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  -- los mismos candados que la clasificación de uno en uno; con los candados puestos, el grupo se vuelve a armar y debe ser el mismo
  perform pg_advisory_xact_lock(hashtext('redes.nodo.' || x)) from unnest(v_ids) x;
  select array_agg(b.nodo_id order by b.nodo_id) into v_ids2
    from (select n.nodo_id, redes.f_pm_sugerencia(pm.tipo, pm.que_es, pm.nombre, pm.zona_modelo) as sug
            from redes.v_nodo_visible n
            join redes.pm_nodos pm on n.sistema = 'acueducto' and pm.llave = n.llave_modelo and pm.carga_id = redes.f_ref_vigente('pm_nodos')
           where n.clase_nodo = 'por_clasificar') b
   where b.sug ->> 'accion' = 'no_crear' and b.sug ->> 'grupo' = p_grupo;
  if v_ids2 is distinct from v_ids then perform tecnica.f_error('El grupo cambió desde la vista previa (alguien clasificó un nodo): vuelva a ver la vista previa'); end if;
  insert into redes.nodo_eventos (nodo_id, tipo, clase, motivo, autor) select x, 'clasificar', v_clase, v_mot, v_email from unnest(v_ids) x;
  perform tecnica.f_auditar(v_email, 'redes_nodos_clasificar_grupo', p_grupo, jsonb_build_object('n', v_n, 'huella', v_huella, 'clase', v_clase, 'motivo', v_mot), null);
  return jsonb_build_object('grupo', p_grupo, 'texto', v_texto, 'n', v_n, 'clase_nodo', v_clase);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del 9a publicado) con cambios exactos, aplicados una sola vez.
--   · redes.f_ficha y geoportal_redes_tramo_nodos: el nodo y los tramos por índice (la ficha tardaba 4,4 s en producción); «sector_hidraulico» (antes «sector_plan»);
--     la referencia del Plan solo para supervisor y administrador;
--   · nodos (crear el activo, ficha preliminar, clasificar y la bandeja): también el supervisor de distribución; la bandeja trae los grupos de «no crear activo»;
--   · redes.f_pm_sugerencia: el grupo de cada sugerencia de «no crear activo»;
--   · daños, intervenciones, tarjeta del contrato y tarjeta de referencia: «sector hidráulico» (el oficial);
--   · geoportal_redes_mi_perfil: «ficha_buscar» (la Ficha de activos en modo buscar para el operador de redes);
--   · crear el daño y convertir el reporte del bot: el sector sale de la ubicación si no viene escrito.
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

-- public.geoportal_redes_tramo_nodos(text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_tramo_nodos(p_solicitante text, p_codigo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare p record; v_id bigint; m redes.activo_vigente_mat%rowtype;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  v_id := redes.f_buscar_activo(p_codigo);
  select * into m from redes.activo_vigente_mat where activo_id = v_id;
  if GeometryType(m.geom) not in ('LINESTRING', 'MULTILINESTRING') then perform tecnica.f_error('Ese activo no es un tramo'); end if;
  return jsonb_build_object('tramo', redes.f_activo_corto(v_id) || jsonb_build_object('sistema', m.sistema, 'longitud_m', m.longitud_m, 'diametro_mm', m.diametro_mm),
    'nodos', coalesce((select jsonb_agg(jsonb_build_object('rol', x.rol, 'nombre', n.nombre_visible, 'lat', round(ST_Y(n.geom)::numeric, 6), 'lon', round(ST_X(n.geom)::numeric, 6),
                                                         'activo', case when n.activo_id is not null and exists (select 1 from redes.activo_vigente_mat a where a.activo_id = n.activo_id and not a.retirado)
                                                                        then redes.f_activo_corto(n.activo_id) end) order by x.o)
                         from redes.tramo_nodos tn join redes.activo_vigente_mat tv on tv.activo_id = tn.activo_id and tv.version = tn.version      -- 9a-bis: por índice
                         cross join lateral (values ('inicio', 1, tn.nodo_ini), ('fin', 2, tn.nodo_fin)) x(rol, o, nodo)
                         cross join lateral redes.f_nodo_visible_id(x.nodo) n
                        where tn.activo_id = v_id), '[]'::jsonb));
end $function$;

-- public.geoportal_redes_nodo_crear_activo(text,bigint,text,text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_nodo_crear_activo(p_solicitante text, p_nodo bigint, p_prefijo text, p_clase_activo text, p_nombre text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text := redes.f_supervisor(p_solicitante, 'clasifica nodos'); n redes.v_nodo_visible%rowtype; t redes.v_tipo_visible%rowtype;
  v_mot text := btrim(coalesce(p_motivo, '')); v_nom text := nullif(btrim(coalesce(p_nombre, '')), ''); v_cl text := nullif(p_clase_activo, '');
  v_cons bigint; v_cod text; v_act bigint; v_atr jsonb;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  if v_nom is not null and length(v_nom) > 120 then perform tecnica.f_error('El nombre admite hasta 120 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.nodo.' || coalesce(p_nodo, 0)));
  select * into n from redes.f_nodo_visible_id(p_nodo);      -- 9a-bis: por la llave del nodo (índice)
  if not found then perform tecnica.f_error('No existe ese nodo (o ya no es el vigente)', 'P0002'); end if;
  if n.clase_nodo <> 'por_clasificar' then perform tecnica.f_error('Ese nodo ya no está por clasificar'); end if;
  select * into t from redes.v_tipo_visible where prefijo = upper(coalesce(p_prefijo, '')) and sistema = n.sistema and activo;
  if not found then perform tecnica.f_error('Elija un tipo de activo del mismo sistema'); end if;
  if t.geometria <> 'punto' then perform tecnica.f_error('Un nodo es un punto: elija un tipo de punto'); end if;
  if v_cl is not null and not exists (select 1 from redes.clases_activo where prefijo = t.prefijo and codigo = v_cl) then perform tecnica.f_error('Esa clase no existe para el tipo elegido'); end if;
  if v_cl is null and exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean) then
    perform tecnica.f_error(format('Elija la clase del activo (%s)', t.nombre_visible));
  end if;
  v_atr := jsonb_build_object('nombre_modelo', n.nombre_modelo, 'creado_desde_nodo', n.llave_modelo);
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = t.prefijo returning ultimo into v_cons;
  v_cod := t.prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, t.prefijo, 'ficha', v_email) returning id into v_act;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, estado_codigo, atributos, codigo_anterior, huella, autor)
  values (v_act, 1, n.geom, v_nom, v_cl, 'en_operacion', v_atr, n.nombre_modelo,
          redes.f_huella(n.geom, jsonb_build_object('p', t.prefijo, 'n', v_nom, 'c', v_cl, 'e', null, 'm', null, 'd', null, 'l', null, 'pr', null, 'ca', null, 's', 'en_operacion',
                                                    'ant', n.nombre_modelo, 'a', v_atr)), v_email);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_act, 1, 'emdupar', 'Creado desde la bandeja de nodos por clasificar', v_email);
  insert into redes.nodo_eventos (nodo_id, tipo, activo_id, motivo, autor) values (n.nodo_id, 'enlazar_activo', v_act, v_mot, v_email);
  perform redes.f_mat_refrescar_uno(v_act);
  perform redes.f_subir_tesela(n.sistema);
  perform tecnica.f_auditar(v_email, 'redes_nodo_crear_activo', n.nodo_id::text, jsonb_build_object('nodo', n.nombre_modelo, 'llave', n.llave_modelo, 'activo', v_cod, 'motivo', v_mot), null);
  return jsonb_build_object('nodo_id', n.nodo_id, 'nombre_modelo', n.nombre_modelo, 'activo', v_cod, 'tipo', t.nombre_visible);
end $function$;

-- public.geoportal_redes_nodo_preliminar(text,bigint)
CREATE OR REPLACE FUNCTION public.geoportal_redes_nodo_preliminar(p_solicitante text, p_nodo bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 'clasifica nodos'); n redes.v_nodo_visible%rowtype; v_sec record; v_mod jsonb;
begin
  select * into n from redes.f_nodo_visible_id(p_nodo);      -- 9a-bis: por la llave del nodo (índice)
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
end $function$;

-- public.geoportal_redes_nodo_clasificar(text,bigint,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_nodo_clasificar(p_solicitante text, p_nodo bigint, p_clase text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 'clasifica nodos'); n redes.v_nodo_visible%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if coalesce(p_clase, '') not in ('nodo_calculo', 'propuesta_plan', 'por_clasificar') then perform tecnica.f_error('Esa clasificación no existe'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.nodo.' || coalesce(p_nodo, 0)));
  select * into n from redes.f_nodo_visible_id(p_nodo);      -- 9a-bis: por la llave del nodo (índice)
  if not found then perform tecnica.f_error('No existe ese nodo (o ya no es el vigente)', 'P0002'); end if;
  if n.clase_nodo in ('activo', 'pozo_virtual') then perform tecnica.f_error('Ese nodo ya es un activo (o un pozo virtual): no se clasifica aquí'); end if;
  if n.clase_nodo = p_clase then perform tecnica.f_error('Ese nodo ya está así'); end if;
  insert into redes.nodo_eventos (nodo_id, tipo, clase, motivo, autor) values (n.nodo_id, 'clasificar', p_clase, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_nodo_clasificar', n.nodo_id::text, jsonb_build_object('nodo', n.nombre_modelo, 'llave', n.llave_modelo, 'antes', n.clase_nodo, 'clase', p_clase, 'motivo', v_mot), null);
  return jsonb_build_object('nodo_id', n.nodo_id, 'nombre_modelo', n.nombre_modelo, 'clase_nodo', p_clase);
end $function$;

-- public.geoportal_redes_nodos_por_clasificar(text,text,bigint,integer)
CREATE OR REPLACE FUNCTION public.geoportal_redes_nodos_por_clasificar(p_solicitante text, p_buscar text DEFAULT NULL::text, p_despues_de bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 'clasifica nodos'); v_q text := nullif(lower(btrim(coalesce(p_buscar, ''))), ''); v_lim integer := coalesce(p_limite, 50);
        v_acc text; v_r jsonb;
begin
  if v_lim < 1 or v_lim > 200 then perform tecnica.f_error('Se piden de 1 a 200'); end if;
  if v_q is not null and length(v_q) > 60 then perform tecnica.f_error('La búsqueda es demasiado larga'); end if;
  -- Corte 9a: «sugerencia:<acción>» en la búsqueda deja solo los nodos con esa sugerencia del modelo
  -- (los tramos que llegan a cada nodo se cuentan por los índices de tramo_nodos; la vista de tramos vigentes recorría todas las versiones en cada nodo)
  if v_q like 'sugerencia:%' then
    v_acc := substring(v_q from 12); v_q := null;
    if v_acc not in ('crear', 'no_crear', 'dejar_nodo', 'revisar', 'sin_modelo') then perform tecnica.f_error('Esa sugerencia no existe'); end if;
  end if;
  with base as (
    select n.nodo_id, n.sistema, n.llave_modelo, n.nombre_modelo, n.nombre_visible, n.geom, pm.tipo, pm.que_es,
           redes.f_pm_sugerencia(pm.tipo, pm.que_es, pm.nombre, pm.zona_modelo) as sug
      from redes.v_nodo_visible n
      left join redes.pm_nodos pm on n.sistema = 'acueducto' and pm.llave = n.llave_modelo and pm.carga_id = redes.f_ref_vigente('pm_nodos')
     where n.clase_nodo = 'por_clasificar'),
  fil as (
    select b.* from base b
     where (v_q is null or position(v_q in lower(coalesce(b.nombre_modelo, '') || ' ' || b.nombre_visible || ' ' || b.llave_modelo || ' ' || coalesce(b.que_es, ''))) > 0)
       and (v_acc is null or coalesce(b.sug ->> 'accion', 'sin_modelo') = v_acc)),
  pag as (select f.* from fil f where p_despues_de is null or f.nodo_id > p_despues_de order by f.nodo_id limit v_lim)
  select jsonb_build_object(
    'grupos', coalesce((select jsonb_agg(jsonb_build_object('grupo', g.grupo, 'n', g.n) order by g.n desc, g.grupo)
                          from (select coalesce(substring(b.nombre_modelo from '^[A-Za-zÁÉÍÓÚáéíóúñ]+'), '?') as grupo, count(*) as n from base b group by 1) g), '[]'::jsonb),
    'sugerencias', coalesce((select jsonb_agg(jsonb_build_object('accion', g.accion, 'n', g.n) order by g.n desc, g.accion)
                               from (select coalesce(b.sug ->> 'accion', 'sin_modelo') as accion, count(*) as n from base b group by 1) g), '[]'::jsonb),
    -- 9a-bis: los grupos que se pueden confirmar de una vez (solo «no crear activo»)
    'grupos_no_crear', coalesce((select jsonb_agg(jsonb_build_object('grupo', g.grupo, 'texto', g.texto, 'n', g.n) order by g.n desc)
                                   from (select b.sug ->> 'grupo' as grupo, min(b.sug ->> 'texto') as texto, count(*) as n from base b
                                          where b.sug ->> 'accion' = 'no_crear' and b.sug ? 'grupo' group by 1) g), '[]'::jsonb),
    'total', (select count(*) from fil),
    'items', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('nodo_id', x.nodo_id, 'sistema', x.sistema, 'llave_modelo', x.llave_modelo, 'nombre_modelo', x.nombre_modelo,
                         'nombre_visible', x.nombre_visible, 'alias', case when x.nombre_visible is distinct from coalesce(x.nombre_modelo, x.llave_modelo) then x.nombre_visible end,
                         'lat', round(ST_Y(x.geom)::numeric, 6), 'lon', round(ST_X(x.geom)::numeric, 6),
                         'tramos', (select count(*) from redes.tramo_nodos t join redes.activo_vigente_mat m on m.activo_id = t.activo_id and m.version = t.version
                                    where t.nodo_ini = x.nodo_id or t.nodo_fin = x.nodo_id),
                         'tipo_modelo', x.tipo, 'que_es', nullif(x.que_es, 'otro'), 'sugerencia', x.sug)) order by x.nodo_id) from pag x), '[]'::jsonb),
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre_visible, 'sistema', t.sistema,
                         'pide_clase', exists (select 1 from jsonb_array_elements(t.campos) c where c ->> 'clave' = 'clase' and (c ->> 'obligatorio')::boolean),
                         'clases', coalesce((select jsonb_agg(jsonb_build_object('codigo', k.codigo, 'nombre', k.nombre) order by k.orden) from redes.clases_activo k where k.prefijo = t.prefijo and k.activo), '[]'::jsonb))
                         order by t.sistema, t.orden)
                         from redes.v_tipo_visible t where t.geometria = 'punto' and t.activo and t.sistema in ('acueducto', 'alcantarillado')), '[]'::jsonb)) into v_r;
  return v_r || jsonb_build_object('siguiente', case when jsonb_array_length(v_r -> 'items') = v_lim then (v_r -> 'items' -> (v_lim - 1) ->> 'nodo_id')::bigint end);
end $function$;

-- redes.f_pm_sugerencia(text,text,text,text)
CREATE OR REPLACE FUNCTION redes.f_pm_sugerencia(p_tipo text, p_que_es text, p_nombre text, p_zona text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select case
    when p_tipo is null and p_que_es is null then null
    when p_tipo = 'tanque' and coalesce(p_zona, '') <> 'Proyectado' and p_nombre !~* 'proyectado' then
      jsonb_build_object('accion', 'crear', 'prefijo', 'TAN', 'texto', 'Tanque existente (' || p_nombre || '): crear el activo TAN')
    when p_tipo = 'tanque' then
      jsonb_build_object('accion', 'no_crear', 'clase', 'propuesta_plan', 'grupo', 'tanque_proyectado', 'texto', 'Tanque proyectado por el Plan (no construido): no crear activo')
    when p_que_es like 'válvula de sectorización propuesta%' then
      jsonb_build_object('accion', 'no_crear', 'clase', 'propuesta_plan', 'grupo', 'valvula_propuesta', 'texto', 'Válvula propuesta por el Plan (no instalada): no crear activo')
    when p_que_es = 'macromedidor proyectado' then
      jsonb_build_object('accion', 'no_crear', 'clase', 'propuesta_plan', 'grupo', 'macro_proyectado', 'texto', 'Macromedidor proyectado por el Plan (no instalado): no crear activo')
    when p_que_es like 'nodo de cálculo%' then
      jsonb_build_object('accion', 'dejar_nodo', 'clase', 'nodo_calculo', 'texto', 'Nodo de cálculo del modelo: dejar como nodo')
    when p_que_es like 'unión corriente%' then
      jsonb_build_object('accion', 'dejar_nodo', 'clase', 'nodo_calculo', 'texto', 'Unión corriente del modelo (sin accesorio que inventariar): dejar como nodo')
    when p_tipo = 'hidrante' then
      jsonb_build_object('accion', 'crear', 'prefijo', 'TOR', 'texto', 'Hidrante en el modelo: si existe en campo, crear el activo (Torre = hidrante)')
    else jsonb_build_object('accion', 'revisar', 'texto', 'Sin sugerencia: revisar en campo') end $function$;

-- public.geoportal_redes_danos(text,text,integer)
CREATE OR REPLACE FUNCTION public.geoportal_redes_danos(p_solicitante text, p_filtro text DEFAULT 'abiertos'::text, p_limite integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 've la lista de daños y fallas'); v_lim integer := coalesce(p_limite, 100);
begin
  if coalesce(p_filtro, '') not in ('abiertos', 'todos', 'ocultos', 'no_identificados') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_lim < 1 or v_lim > 300 then perform tecnica.f_error('Se piden de 1 a 300'); end if;
  return jsonb_build_object('filtro', p_filtro, 'danos', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'clase', x.clase, 'tipo', x.tipo_nombre, 'sistema', x.sistema, 'activo', x.activo_codigo, 'no_identificado', x.no_ident_que_es,
             'estado', x.estado, 't_detectado', x.t_detectado, 'riesgo', x.riesgo, 'causa_clase', x.causa_clase, 'sector', x.sector_num, 'sector_hidraulico', (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector) from redes.f_sector_de(x.geom) s where s.sector is not null), 'origen', x.origen, 'autor', x.autor,
             'total_s', x.total_s, 'fotos', x.fotos, 'intervenciones', x.itv, 'tiene_tercero', x.tercero) order by x.t_detectado desc)
      from (select d.*, n.sector_num,
                   (select count(*) from redes.dano_fotos f where f.dano_id = d.id) as fotos,
                   (select count(*) from redes.intervenciones i where i.dano_id = d.id) as itv,
                   exists (select 1 from redes.dano_datos_sensibles s where s.dano_id = d.id) as tercero
              from redes.v_dano d join redes.danos n on n.id = d.id
             where case p_filtro when 'abiertos' then d.estado in ('reportado', 'en_atencion') when 'ocultos' then d.estado = 'oculto'
                                 when 'no_identificados' then d.activo_id is null and d.estado <> 'oculto' else true end
             order by d.t_detectado desc limit v_lim) x), '[]'::jsonb));
end $function$;

-- public.geoportal_redes_intervenciones(text,text,integer)
CREATE OR REPLACE FUNCTION public.geoportal_redes_intervenciones(p_solicitante text, p_filtro text DEFAULT 'recientes'::text, p_limite integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven la lista de intervenciones'); v_lim integer := coalesce(p_limite, 50);
begin
  if coalesce(p_filtro, '') not in ('recientes', 'recursos_por_completar') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_lim < 1 or v_lim > 100 then perform tecnica.f_error('Se piden de 1 a 100 intervenciones'); end if;
  return jsonb_build_object('filtro', p_filtro, 'intervenciones', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'tipo', x.tipo_nombre, 'inversion_modo', x.inversion_modo, 'sistema', x.sistema, 'activo', x.activo_codigo,
             'no_identificado', x.no_ident_que_es, 'dano', x.dano_codigo, 't_fin', x.t_fin, 'ejecutor', x.ejecutor, 'contratista', x.contratista, 'autor', x.autor,
             'sector_hidraulico', (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector) from redes.f_sector_de(x.geom) s where s.sector is not null),
             'recursos', x.recursos, 'sin_evidencia', x.sin_evidencia, 'fotos', x.fotos, 'estado', x.estado,
             'fuentes', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('n', f.n, 'aportante', f.aportante_codigo, 'aportante_nombre', e.nombre, 'entidad', f.entidad, 'valor', f.valor,
                                                                               'porcentaje', f.porcentaje, 'soporte', f.soporte)) order by f.n)
                           from redes.v_intervencion_fuentes f join redes.entidades_aportantes e on e.codigo = f.aportante_codigo where f.intervencion_id = x.id))
             order by x.registrado_en desc)
      from (select * from redes.v_intervencion v
             where v.estado <> 'oculta' and (p_filtro = 'recientes' or v.recursos = 'por_completar')
             order by v.registrado_en desc limit v_lim) x), '[]'::jsonb));
end $function$;

-- public.geoportal_redes_contrato_tarjeta(text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_contrato_tarjeta(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'bi_interno', 'pg_temp'
AS $function$
declare a record; cs record; pr record; f record; v_c text := btrim(coalesce(p_contrato, '')); v_personal boolean;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;
  -- Corte 7a (respuesta 1 de David al 6b): nombre y dirección solo para el administrador y el supervisor de distribución (su permiso, o área distribución o las dos)
  v_personal := a.admin or public.geoportal_puede(a.email, 'dashboard_redes') or coalesce(redes.f_area(a.email) in ('distribucion', 'ambas'), false);
  if v_c !~ '^[0-9]{1,12}$' then perform tecnica.f_error('Escriba solo los números del contrato'); end if;
  if v_c in ('0', '99999999') or not exists (select 1 from public.catastro_valledupar cv where cv.cod_usuario = v_c and cv.geom is not null) then
    perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002');
  end if;
  select s.nombre, s.estado, s.categoria, s.direccion, s.barrio, s.periodo_carga into cs
    from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select cv.direccion, cv.barrio into pr from public.catastro_valledupar cv where cv.cod_usuario = v_c order by cv.id limit 1;
  select fc.periodo_ultimo, fc.uso, fc.consumo_meses, fc.cons_prom, fc.meses_con_lectura, fc.medidor_anios into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  -- la lectura queda registrada: quién, cuándo y qué contrato (NUNCA el nombre ni la dirección)
  perform tecnica.f_auditar(a.email, 'redes_contrato_tarjeta', v_c, jsonb_build_object('datos', case when v_personal then 'nombre, dirección y barrio' else 'sin nombre ni dirección' end, 'desde', 'geovisor'), p_ip);
  return jsonb_build_object(
    'contrato', v_c,
    'estado', redes.f_estado_contrato(cs.estado), 'estado_texto', nullif(btrim(cs.estado), ''),
    'uso', redes.f_contrato_uso(f.uso, cs.categoria),
    'consumo', case when f.periodo_ultimo is not null then jsonb_build_object(
        'periodo_ultimo', f.periodo_ultimo, 'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura,
        'meses', (select coalesce(jsonb_agg(jsonb_build_object('periodo', m ->> 'periodo', 'm3', m -> 'm3', 'sin_dato', coalesce((m ->> 'sin_dato')::boolean, false),
                                                               'lectura_real', coalesce((m ->> 'lectura_real')::boolean, false)) order by k), '[]'::jsonb)
                    from jsonb_array_elements(f.consumo_meses) with ordinality x(m, k))) end,
    'medidor_anios', f.medidor_anios,
    'tramo', (select v.codigo from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id where t.contrato = v_c),
    'sector_hidraulico', (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector)      -- Corte 9a: el sector del contrato es el de su tramo (por geometría)
                      from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id cross join lateral redes.f_sector_de(v.geom) s
                     where t.contrato = v_c and s.sector is not null),
    'suscriptor', jsonb_build_object(                                  -- DATO PERSONAL: solo en pantalla
      'nombre', case when v_personal then nullif(btrim(cs.nombre), '') end,
      'direccion', case when v_personal then coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')) end,
      'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), ''))),
    'datos_personales', v_personal,
    'corte', cs.periodo_carga);
end $function$;

-- public.geoportal_redes_referencia(text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_referencia(p_solicitante text, p_capa text, p_llave text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
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
        (9, 'Sector hidráulico', to_jsonb(case when v_sec.sector is not null then v_sec.sector || coalesce(' · subsector ' || v_sec.subsector, '') end), null)) f(o, r, v, u)),
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
    'filas', e.datos || case when v_sec.sector is not null then jsonb_build_array(jsonb_build_object('r', 'Sector hidráulico', 'v', v_sec.sector || coalesce(' · subsector ' || v_sec.subsector, ''))) else '[]'::jsonb end,
    'series', case when p_capa = 'campana_2014' then (
      select jsonb_build_array(jsonb_build_object('nombre', 'Presión medida cada 15 min', 'unidad', 'm.c.a.', 'eje', 'tiempo',
               'puntos', coalesce(jsonb_agg(jsonb_build_array(to_char(l.cuando, 'YYYY-MM-DD"T"HH24:MI'), l.p_mca) order by l.n), '[]'::jsonb)))
        from redes.pm_campana_lecturas l where l.llave = v_ll and l.carga_id = redes.f_ref_vigente('campana_2014_lecturas')) end));
end $function$;

-- public.geoportal_redes_mi_perfil(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_mi_perfil(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  return jsonb_build_object('perfil', p.perfil, 'dashboard_redes', p.perfil in ('admin', 'supervisor'), 'dashboard_ptap', public.geoportal_puede(p.email, 'dashboard_tecnico'),
                            'geovisor', redes.f_geovisor_lectura(p.email),      -- Corte 6a
                            -- 9a-bis: la Ficha de activos en modo buscar (solo lectura) también para el operador de redes
                            'ficha_buscar', p.perfil in ('admin', 'supervisor') or redes.f_operador_redes(p.email));
end $function$;

-- public.geoportal_redes_crear_dano(text,uuid,jsonb,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_crear_dano(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'danos_fallas'); d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_dano%rowtype; v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text;
  v_t_ini timestamptz; v_t_det timestamptz; v_t_rep timestamptz; v_t_res timestamptz; v_inicio timestamptz;
  v_lat numeric; v_lon numeric; v_fuera boolean; v_fotos jsonb := coalesce(p_datos -> 'fotos', '[]'::jsonb); v_n integer; v_f jsonb; v_ruta text; v_size bigint; v_mime text;
  v_ref jsonb := '[]'::jsonb; v_cons bigint; v_codigo text; v_tipo redes.tipos_dano%rowtype; v_marcas text[]; v_causa text; v_ter text; v_ter_nom text;
  v_desc text := nullif(btrim(coalesce(d ->> 'descripcion', '')), ''); v_max_bytes bigint := redes.f_param('max_bytes_foto_dano')::bigint;
  v_super boolean := redes.f_es_supervisor_redes(v_email); v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
  v_sector smallint;
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador del daño: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_dano where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'fuera_de_zona', v_prev.fuera_de_zona, 'sin_evidencia', not exists (select 1 from redes.dano_fotos f where f.dano_id = p_id), 'repetido', true);
  end if;
  if not exists (select 1 from redes.dano_preparaciones where dano_id = p_id and autor = v_email) then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos del daño no son válidos'); end if;

  -- qué pasó
  select * into v_tipo from redes.tipos_dano where codigo = d ->> 'tipo' and activo;
  if not found then perform tecnica.f_error('Elija qué pasó'); end if;
  if d ->> 'clase' is distinct from v_tipo.clase then perform tecnica.f_error('El tipo elegido no corresponde a daño o falla'); end if;
  if coalesce(d ->> 'sistema', '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;
  if not ((d ->> 'sistema') = any (v_tipo.sistemas)) then perform tecnica.f_error(format('«%s» no aplica a %s', v_tipo.nombre, d ->> 'sistema')); end if;

  -- activo o «no identificado»
  if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado then perform tecnica.f_error('El activo elegido no existe o está retirado: elíjalo de nuevo en el mapa'); end if;
    if v_act.sistema <> d ->> 'sistema' then perform tecnica.f_error('El activo elegido no es de ese sistema'); end if;
    v_activo := v_act.activo_id;
  else
    v_noid := nullif(btrim(coalesce(d ->> 'no_identificado', '')), '');
    if v_noid is null or length(v_noid) < 3 or length(v_noid) > 120 then perform tecnica.f_error('Elija el activo en el mapa o, si no lo identifica, diga qué es (3 a 120 caracteres)'); end if;
  end if;

  -- ubicación: nunca se rechaza por estar fuera de la zona (se marca)
  v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric;
  if v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then perform tecnica.f_error('Falta la ubicación del daño'); end if;
  if coalesce(d ->> 'ubicacion_origen', '') not in ('gps', 'mapa', 'activo') then perform tecnica.f_error('Falta de dónde sale la ubicación'); end if;
  v_fuera := v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max');

  -- tiempos (contra la hora del servidor)
  v_t_ini := redes.f_instante(d ->> 't_inicio_dano', 'inicio del daño');
  v_t_det := redes.f_instante(d ->> 't_detectado', 'detectado');
  v_t_rep := redes.f_instante(d ->> 't_inicio_reparacion', 'inicio de la reparación');
  v_t_res := redes.f_instante(d ->> 't_restablecido', 'servicio restablecido');
  if v_t_det is null then perform tecnica.f_error('Escriba cuándo se detectó'); end if;
  if greatest(v_t_ini, v_t_det, v_t_rep, v_t_res) > v_ahora + interval '2 minutes' then perform tecnica.f_error('Hay una hora en el futuro: revise la hora de su celular'); end if;
  if v_t_det < v_ahora - make_interval(days => redes.f_param('dano_dias_atras_max')::integer) then
    perform tecnica.f_error(format('La detección no puede ser de hace más de %s días', redes.f_param('dano_dias_atras_max')::integer));
  end if;
  if v_t_ini is not null and v_t_ini > v_t_det then perform tecnica.f_error('El inicio del daño no puede ser después de la detección'); end if;
  if v_t_rep is not null and v_t_rep < v_t_det then perform tecnica.f_error('El inicio de la reparación no puede ser antes de la detección'); end if;
  if v_t_res is not null and v_t_rep is null then perform tecnica.f_error('Para el servicio restablecido, escriba también el inicio de la reparación'); end if;
  if v_t_res is not null and v_t_res < v_t_rep then perform tecnica.f_error('El servicio restablecido no puede ser antes del inicio de la reparación'); end if;
  v_inicio := redes.f_instante(d ->> 'inicio_dispositivo', 'apertura del formulario');
  if v_inicio is not null and (v_inicio > v_ahora + interval '2 minutes' or v_inicio < v_ahora - make_interval(hours => tecnica.f_max_horas_inicio())) then
    perform tecnica.f_error(format('Este formulario se abrió hace más de %s horas o la hora de su celular está adelantada. Revise la hora y vuelva a enviar.', tecnica.f_max_horas_inicio()));
  end if;

  -- §25.1: el sector es un número entero del 1 al 100 (hoy 1 a 7). El texto viejo (sector_texto) ya no se llena.
  if d -> 'sector' is not null and jsonb_typeof(d -> 'sector') <> 'null' then
    if jsonb_typeof(d -> 'sector') <> 'number' or (d ->> 'sector') !~ '^[0-9]{1,3}$' or (d ->> 'sector')::integer not between 1 and 100 then
      perform tecnica.f_error('El sector es un número entero del 1 al 100');
    end if;
    v_sector := (d ->> 'sector')::smallint;
  end if;
  -- 9a-bis (David, 16-nov): el formulario propone el sector hidráulico de la ubicación; si no llega ninguno, se toma de la ubicación (sin polígono, queda vacío)
  if v_sector is null then select s.sector into v_sector from redes.f_sector_en(v_lat, v_lon) s; end if;
  -- tamaño, afectación, riesgo y causa
  if d ->> 'tipo_rotura' is not null and not exists (select 1 from redes.tipos_rotura where codigo = d ->> 'tipo_rotura' and activo) then perform tecnica.f_error('El tipo de rotura no existe'); end if;
  if d ->> 'tipo_rotura' is not null and not v_tipo.pide_rotura then perform tecnica.f_error('Este tipo de daño no lleva tipo de rotura'); end if;
  if coalesce(d ->> 'riesgo', '') not in ('bajo', 'medio', 'alto') then perform tecnica.f_error('Elija el riesgo'); end if;
  if d -> 'marcas' is not null and jsonb_typeof(d -> 'marcas') <> 'array' then perform tecnica.f_error('Las marcas de riesgo no son válidas'); end if;
  v_marcas := coalesce(array(select distinct jsonb_array_elements_text(d -> 'marcas')), '{}');
  if exists (select 1 from unnest(v_marcas) m where not exists (select 1 from redes.marcas_riesgo r where r.codigo = m and r.activo)) then perform tecnica.f_error('Una marca de riesgo no existe'); end if;
  if coalesce(d ->> 'causa_clase', '') not in ('propia', 'terceros', 'desconocida') then perform tecnica.f_error('Elija la causa: propia, de terceros o desconocida'); end if;
  if d ->> 'causa_clase' = 'propia' then
    v_causa := d ->> 'causa';
    if not exists (select 1 from redes.causas where codigo = v_causa and activo) then perform tecnica.f_error('Elija la causa propia'); end if;
  elsif d ->> 'causa_clase' = 'terceros' then
    v_ter := d ->> 'tercero_tipo';
    if not exists (select 1 from redes.tipos_tercero where codigo = v_ter and activo) then perform tecnica.f_error('Elija quién lo causó'); end if;
    v_ter_nom := nullif(btrim(coalesce(d ->> 'tercero_nombre', '')), '');
    if v_ter_nom is not null and length(v_ter_nom) not between 2 and 120 then perform tecnica.f_error('El nombre, la empresa o la placa lleva de 2 a 120 caracteres'); end if;
  end if;
  if v_desc is not null and length(v_desc) > 1000 then perform tecnica.f_error('La descripción admite hasta 1.000 caracteres'); end if;

  -- fotos: el tamaño y el tipo se leen de Storage (nunca se le creen al celular). Sin fotos: solo supervisor o administrador, con el motivo.
  if jsonb_typeof(v_fotos) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_fotos);
  -- §25.8: nadie registra «sin evidencia fotográfica»; lo que llega sin foto entra por el reporte de anomalías
  if v_sinev is not null then
    perform tecnica.f_error('Ya no se registra «sin evidencia fotográfica»: tome al menos una foto del daño (lo que llega sin foto entra por el reporte de anomalías)');
  end if;
  if v_n < redes.f_param('min_fotos_dano') or v_n > redes.f_param('max_fotos_dano') or v_n > (select fotos from redes.dano_preparaciones where dano_id = p_id) then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', redes.f_param('min_fotos_dano')::integer, redes.f_param('max_fotos_dano')::integer));
  end if;
  if v_n > 0 and (select count(distinct (e ->> 'n')::integer) <> v_n or min((e ->> 'n')::integer) <> 1 or max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_fotos) e) then
    perform tecnica.f_error('El orden de las fotos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  if v_n > 0 and not exists (select 1 from jsonb_array_elements(v_fotos) e where e ->> 'momento' = 'dano') then perform tecnica.f_error('Falta una foto del daño'); end if;
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'n')::integer loop
    if coalesce(v_f ->> 'momento', '') not in ('dano', 'entorno', 'reparado') then perform tecnica.f_error('Cada foto dice si es del daño, del entorno o de la reparación'); end if;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^danos/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || '\.jpg$') then
      perform tecnica.f_error(format('La ruta de la foto %s no corresponde a este daño', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró la foto %s: súbala de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('La foto %s está vacía', v_f ->> 'n')); end if;
    if v_size > v_max_bytes then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'momento', v_f ->> 'momento', 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;

  -- código DAN-000123 (candado de fila del consecutivo) e inserción
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'DAN' returning ultimo into v_cons;
  v_codigo := 'DAN-' || lpad(v_cons::text, 6, '0');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, no_ident_que_es, lat, lon, ubicacion_origen, precision_m, fuera_de_zona,
         t_inicio_dano, t_detectado, inicio_en, inicio_origen, tipo_rotura, largo_afectado_m, presion_mca, usuarios_sin_servicio, sector_texto, sector_num,
         riesgo, marcas, causa_clase, causa_codigo, tercero_tipo, descripcion, origen, autor, registrado_en)
  values (p_id, v_codigo, v_tipo.clase, v_tipo.codigo, d ->> 'sistema', v_activo, v_noid, round(v_lat, 6), round(v_lon, 6), d ->> 'ubicacion_origen',
          (d ->> 'precision_m')::numeric, v_fuera, v_t_ini, v_t_det, v_inicio, case when v_inicio is not null then 'dispositivo' end,
          d ->> 'tipo_rotura', (d ->> 'largo_afectado_m')::numeric, (d ->> 'presion_mca')::numeric, (d ->> 'usuarios_sin_servicio')::integer,
          null, v_sector, d ->> 'riesgo', v_marcas, d ->> 'causa_clase', v_causa, v_ter, v_desc, 'formulario', v_email, v_ahora);
  if v_ter_nom is not null then insert into redes.dano_datos_sensibles (dano_id, tercero_nombre) values (p_id, v_ter_nom); end if;
  if v_t_rep is not null then insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor) values (p_id, v_t_rep, v_t_res, 'formulario', v_email); end if;
  insert into redes.dano_fotos (dano_id, n, momento, ruta_storage, bytes, mime)
  select p_id, (x ->> 'n')::smallint, x ->> 'momento', x ->> 'ruta', (x ->> 'bytes')::integer, x ->> 'mime' from jsonb_array_elements(v_ref) x;
  -- «sin evidencia fotográfica»: queda como nota del daño, con el motivo
  if v_n = 0 then insert into redes.dano_eventos (dano_id, tipo, motivo, autor) values (p_id, 'nota', 'Sin evidencia fotográfica: ' || v_sinev, v_email); end if;
  -- auditoría sin el nombre del tercero ni la posición
  perform tecnica.f_auditar(v_email, 'redes_crear_dano', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'sistema', d ->> 'sistema', 'activo', v_act.codigo,
          'no_identificado', v_noid is not null, 'fotos', v_n, 'sin_evidencia', v_n = 0, 'riesgo', d ->> 'riesgo'), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo,
                                    'fuera_de_zona', x.fuera_de_zona, 'respuesta_s', x.respuesta_s, 'reparacion_s', x.reparacion_s, 'total_s', x.total_s,
                                    'perdida_estado', x.perdida_estado, 'sin_evidencia', v_n = 0, 'repetido', false) from redes.v_dano x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.danos where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_dano x where x.id = p_id);
  end if;
  perform tecnica.f_error('Una de las fotos ya está usada en otro daño');
  return null;
end $function$;

-- public.geoportal_redes_reporte_convertir(text,uuid,jsonb)
CREATE OR REPLACE FUNCTION public.geoportal_redes_reporte_convertir(p_solicitante text, p_reporte uuid, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare p record; r redes.v_reporte_externo%rowtype; d jsonb := coalesce(p_datos, '{}'::jsonb); v_tipo redes.tipos_dano%rowtype; v_act redes.activo_vigente_mat%rowtype;
        v_id uuid := gen_random_uuid(); v_cons bigint; v_codigo text; v_lat numeric; v_lon numeric; v_noid text; v_pto geometry;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p.perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador convierten reportes del bot' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('redes.reporte.' || p_reporte::text));
  select * into r from redes.v_reporte_externo where id = p_reporte;
  if not found then perform tecnica.f_error('No existe ese reporte', 'P0002'); end if;
  if r.ultimo_evento in ('convertido', 'descartado') then perform tecnica.f_error(format('Ese reporte ya está %s', r.ultimo_evento)); end if;
  select * into v_tipo from redes.tipos_dano where codigo = d ->> 'tipo' and activo;
  if not found or v_tipo.clase is distinct from d ->> 'clase' then perform tecnica.f_error('Elija qué pasó'); end if;
  if coalesce(d ->> 'sistema', '') not in ('acueducto', 'alcantarillado') or not ((d ->> 'sistema') = any (v_tipo.sistemas)) then perform tecnica.f_error('Elija un sistema que corresponda al tipo'); end if;
  if coalesce(d ->> 'riesgo', '') not in ('bajo', 'medio', 'alto') then perform tecnica.f_error('Elija el riesgo'); end if;
  if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado or v_act.sistema <> d ->> 'sistema' then perform tecnica.f_error('El activo no existe, está retirado o no es de ese sistema'); end if;
  else
    v_noid := coalesce(nullif(btrim(coalesce(d ->> 'no_identificado', '')), ''), 'Reporte del bot ' || r.radicado);
  end if;
  if r.lat is not null then v_lat := r.lat; v_lon := r.lon;
  elsif v_act.activo_id is not null then
    v_pto := case when GeometryType(v_act.geom) = 'POINT' then v_act.geom else ST_PointOnSurface(v_act.geom) end;
    v_lat := round(ST_Y(v_pto)::numeric, 6); v_lon := round(ST_X(v_pto)::numeric, 6);
  else perform tecnica.f_error('El reporte no trae ubicación: elija el activo para ubicar el daño');
  end if;
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'DAN' returning ultimo into v_cons;
  v_codigo := 'DAN-' || lpad(v_cons::text, 6, '0');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, no_ident_que_es, lat, lon, ubicacion_origen, fuera_de_zona, t_detectado,
         riesgo, causa_clase, descripcion, origen, reporte_externo_id, autor, sector_num)
  values (v_id, v_codigo, v_tipo.clase, v_tipo.codigo, d ->> 'sistema', v_act.activo_id, v_noid, v_lat, v_lon, case when r.lat is not null then 'bot' else 'activo' end,
          v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max'),
          least(r.recibido_en, clock_timestamp()), d ->> 'riesgo', 'desconocida',
          left('Reporte del bot ' || r.radicado || ' (' || r.tipo_bot || ')' || coalesce(': ' || r.descripcion, '') || coalesce(' · ' || r.direccion, ''), 1000),
          'bot', p_reporte, p.email, (select s.sector from redes.f_sector_en(v_lat, v_lon) s));      -- 9a-bis: el sector de la ubicación
  insert into redes.reporte_externo_eventos (reporte_id, tipo, dano_id, motivo, autor)
  values (p_reporte, 'convertido', v_id, nullif(btrim(coalesce(d ->> 'motivo', '')), ''), p.email);
  perform tecnica.f_auditar(p.email, 'redes_reporte_convertir', r.radicado, jsonb_build_object('dano', v_codigo, 'tipo', v_tipo.codigo), null);
  return jsonb_build_object('reporte', r.radicado, 'dano_id', v_id, 'dano_codigo', v_codigo, 'estado_bot', 'en_atencion');
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las 5 funciones internas nuevas: nadie de la API. Las 2 RPC nuevas y las RPC reemplazadas: solo service_role (la Edge geoportal-redes).
-- =====================================================================
revoke all on function redes.f_nodo_visible_id(bigint), redes.f_nodo_de_activo(bigint), redes.f_tramos_de_nodo(bigint), redes.f_sector_en(numeric, numeric),
  redes.f_operador_redes(text) from public, anon, authenticated, service_role;
revoke all on function redes.f_ficha(bigint, text), redes.f_pm_sugerencia(text, text, text, text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_sector_en', 'geoportal_redes_nodos_clasificar_grupo', 'geoportal_redes_tramo_nodos', 'geoportal_redes_nodo_crear_activo',
                                'geoportal_redes_nodos_por_clasificar', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_nodo_clasificar', 'geoportal_redes_danos',
                                'geoportal_redes_intervenciones', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_referencia', 'geoportal_redes_mi_perfil',
                                'geoportal_redes_crear_dano', 'geoportal_redes_reporte_convertir') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9a_bis', 'migracion_redes_corte9a_bis', null, jsonb_build_object(
        'nuevas', jsonb_build_array('redes.f_nodo_visible_id', 'redes.f_nodo_de_activo', 'redes.f_tramos_de_nodo', 'redes.f_sector_en', 'redes.f_operador_redes',
                                    'geoportal_redes_sector_en', 'geoportal_redes_nodos_clasificar_grupo'),
        'motivo', 'ficha sin recorrer tablas enteras; sector hidráulico oficial; nodos por el supervisor y por grupo; ficha en modo buscar para el operador de redes'), null);
commit;
