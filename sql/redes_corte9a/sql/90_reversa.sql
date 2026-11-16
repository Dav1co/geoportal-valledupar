-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones y la vista redes.v_nodo_vigente como estaban con el 7a (texto exacto) y quita lo nuevo del 9a.
-- SE NIEGA si las funciones cambiaron después de la migración, o si YA HAY DATOS: cargas de referencia (redes.ref_cargas) o nodos clasificados
-- sin activo (eventos «clasificar»). Nada se borra: con datos cargados, lo que corresponde es apagar las capas en el geovisor (Capas al abrir) y avisar.
-- Lo que NO deshace (no se borra): los catálogos sembrados quedan desactivados (clases de SEC, capas del geovisor como «preparada» e inactivas)
-- y los 4 parámetros de presión quedan sin uso. Los activos SEC y SUM que haya cargado el motor se manejan con «Volver a la versión anterior» del Cargue.
-- =====================================================================
do $$
begin
  if to_regclass('redes.ref_cargas') is null then raise exception 'No hay nada que revertir: el Corte 9a no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '4a46069fc3c71c305c49bafd764f316e' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 9a: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.ref_cargas) then raise exception 'Ya hay cargas de referencia del Plan Maestro: la reversa no borra datos; apague las capas y avise'; end if;
  if exists (select 1 from redes.nodo_eventos where tipo = 'clasificar') then raise exception 'Ya hay nodos clasificados sin activo: la reversa no borra hechos; avise'; end if;
end $$;

-- 1. lo nuevo
drop view redes.v_pm_por_verificar;
drop function public.geoportal_redes_activo_verificar(text,text,text);
drop function public.geoportal_redes_por_verificar(text,text,bigint,integer);
drop function public.geoportal_redes_nodo_clasificar(text,bigint,text,text);
drop function public.geoportal_redes_nodo_preliminar(text,bigint);
drop function public.geoportal_redes_referencia(text,text,text);
drop function public.geoportal_redes_geovisor_mvt_ref(text,text,integer,integer,integer);
drop function redes.f_pm_marcar_por_verificar(text);
drop function redes.f_ficha_referencia(bigint);
drop function redes.f_nodo_modelo(text);
drop function redes.f_pm_sugerencia(text,text,text,text);
drop function redes.f_pm_nivel_presion(numeric);
drop function redes.f_sector_de(geometry);
drop function redes.f_ref_vigente(text);
drop view redes.v_ref_carga_vigente;
drop table redes.pm_campana_lecturas, redes.ref_elementos, redes.pm_alc_pozos, redes.pm_alc_conductos, redes.pm_presion_hora, redes.pm_valvulas, redes.pm_tramos, redes.pm_nodos,
           redes.ref_carga_eventos, redes.ref_cargas;

-- 2. la vista de nodos y el evento, como en el 1a
create or replace view redes.v_nodo_vigente as
SELECT n.id AS nodo_id,
    n.sistema,
    n.llave_modelo,
    n.nombre_modelo,
    n.geom,
    n.dispersion_m,
    n.carga_id,
    n.creado_en,
    COALESCE(ev.activo_id,
        CASE
            WHEN (ev.tipo = 'desenlazar'::text) THEN NULL::bigint
            ELSE n.activo_id
        END) AS activo_id,
        CASE
            WHEN (ev.tipo = 'enlazar_activo'::text) THEN 'activo'::text
            WHEN ((ev.tipo = 'desenlazar'::text) AND (n.clase_nodo = 'activo'::text)) THEN 'por_clasificar'::text
            ELSE n.clase_nodo
        END AS clase_nodo
   FROM (( SELECT DISTINCT ON (x.sistema, x.llave_modelo) x.id,
            x.sistema,
            x.llave_modelo,
            x.nombre_modelo,
            x.clase_nodo,
            x.geom,
            x.activo_id,
            x.dispersion_m,
            x.carga_id,
            x.creado_en
           FROM redes.nodos x
          WHERE (NOT (EXISTS ( SELECT 1
                   FROM redes.carga_eventos e
                  WHERE ((e.carga_id = x.carga_id) AND (e.tipo = 'revertir'::text)))))
          ORDER BY x.sistema, x.llave_modelo, x.id DESC) n
     LEFT JOIN LATERAL ( SELECT ne.tipo,
            ne.activo_id
           FROM redes.nodo_eventos ne
          WHERE ((ne.nodo_id = n.id) AND (ne.tipo = ANY (ARRAY['enlazar_activo'::text, 'desenlazar'::text])))
          ORDER BY ne.id DESC
         LIMIT 1) ev ON (true));
alter table redes.nodo_eventos drop constraint nodo_eventos_clase_check;
alter table redes.nodo_eventos drop constraint nodo_eventos_tipo_check;
alter table redes.nodo_eventos add constraint nodo_eventos_tipo_check check (tipo in ('enlazar_activo', 'desenlazar', 'nota'));
alter table redes.nodo_eventos drop column clase;

-- 3. catálogos: se desactivan (no se borran)
update redes.geovisor_capas set fuente = 'preparada', estado = 'espera_dato', activa = false where codigo in ('plan_valvulas', 'pluvial', 'pluvial_2043', 'presion_modelo', 'campana_2014');
alter table redes.geovisor_capas drop constraint geovisor_capas_fuente_check;
alter table redes.geovisor_capas add constraint geovisor_capas_fuente_check check (fuente in ('tesela', 'geojson', 'preparada', 'contratos'));
update redes.geovisor_capas set nombre = 'Sectores hidráulicos', nota = 'Se ven cuando se carguen los polígonos (Cargue de capas)' where codigo = 'sectores';
update redes.capas_por_perfil set encendida = false, actualizado_en = clock_timestamp(), actualizado_por = 'reversa@redes_corte9a'
 where capa = 'sectores' and actualizado_por = 'migracion@redes_corte9a';
update redes.clases_activo set activo = false where prefijo = 'SEC' and codigo in ('sector', 'subsector');
update redes.parametros set descripcion = 'Sin uso (reversa del Corte 9a)' where clave in ('presion_baja_naranja_mca', 'presion_baja_roja_mca', 'presion_alta_naranja_mca', 'presion_alta_roja_mca');

-- 4. las funciones reemplazadas, con su texto del 7a
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
           'tramos', (select count(*) from redes.v_tramo_nodos_vigente x where x.nodo_ini = n.nodo_id or x.nodo_fin = n.nodo_id))
    into v_nodo from redes.v_nodo_visible n where n.activo_id = p_activo limit 1;
  -- si es un tramo: sus dos extremos (con el activo de cada nodo, si lo tiene)
  select jsonb_build_object('metodo', tn.metodo,
           'inicio', (select jsonb_build_object('nombre', n.nombre_visible, 'activo', redes.f_activo_corto(n.activo_id)) from redes.v_nodo_visible n where n.nodo_id = tn.nodo_ini),
           'fin', (select jsonb_build_object('nombre', n.nombre_visible, 'activo', redes.f_activo_corto(n.activo_id)) from redes.v_nodo_visible n where n.nodo_id = tn.nodo_fin))
    into v_tramo from redes.v_tramo_nodos_vigente tn where tn.activo_id = p_activo;
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
revoke all on function redes.f_ficha(bigint,text) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor_mvt(p_solicitante text, p_z integer, p_x integer, p_y integer)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare a record; v_env geometry; v_env4326 geometry; v bytea; v_pref text[]; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        z_min numeric := redes.f_param('geovisor_zoom_min'); z_red numeric := redes.f_param('geovisor_zoom_red_completa');
        z_nod numeric := redes.f_param('geovisor_zoom_nodos'); z_acc numeric := redes.f_param('geovisor_zoom_acc');
        d_acu numeric := redes.f_param('geovisor_diam_principal_acu_mm'); d_alc numeric := redes.f_param('geovisor_diam_principal_alc_mm');
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < z_min then return ''; end if;
  select array_agg(distinct p) into v_pref from redes.geovisor_capas g cross join unnest(g.prefijos) p where g.activa and g.fuente = 'tesela' and (a.completo or not g.solo_completo);
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4326 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'activos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, m.codigo, m.prefijo, m.sistema,
           case GeometryType(m.geom) when 'POINT' then 'nodo' when 'POLYGON' then 'area' when 'MULTIPOLYGON' then 'area' else 'tramo' end as forma,
           coalesce(m.clase, '') as clase, coalesce(m.material_codigo, '') as material, m.diametro_mm::real as diametro,
           case when m.fecha_instalacion is not null then greatest(0, extract(year from age(v_hoy, m.fecha_instalacion)))::integer end as edad,
           m.estado_codigo as estado, m.punteado
      from redes.activo_vigente_mat m
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
revoke all on function public.geoportal_redes_geovisor_mvt(text,integer,integer,integer) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_geovisor_mvt(text,integer,integer,integer) to service_role;

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
             'estado', x.estado, 't_detectado', x.t_detectado, 'riesgo', x.riesgo, 'causa_clase', x.causa_clase, 'sector', x.sector_num, 'origen', x.origen, 'autor', x.autor,
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
revoke all on function public.geoportal_redes_danos(text,text,integer) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_danos(text,text,integer) to service_role;

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
             'recursos', x.recursos, 'sin_evidencia', x.sin_evidencia, 'fotos', x.fotos, 'estado', x.estado,
             'fuentes', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('n', f.n, 'aportante', f.aportante_codigo, 'aportante_nombre', e.nombre, 'entidad', f.entidad, 'valor', f.valor,
                                                                               'porcentaje', f.porcentaje, 'soporte', f.soporte)) order by f.n)
                           from redes.v_intervencion_fuentes f join redes.entidades_aportantes e on e.codigo = f.aportante_codigo where f.intervencion_id = x.id))
             order by x.registrado_en desc)
      from (select * from redes.v_intervencion v
             where v.estado <> 'oculta' and (p_filtro = 'recientes' or v.recursos = 'por_completar')
             order by v.registrado_en desc limit v_lim) x), '[]'::jsonb));
end $function$;
revoke all on function public.geoportal_redes_intervenciones(text,text,integer) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_intervenciones(text,text,integer) to service_role;

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
    'suscriptor', jsonb_build_object(                                  -- DATO PERSONAL: solo en pantalla
      'nombre', case when v_personal then nullif(btrim(cs.nombre), '') end,
      'direccion', case when v_personal then coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')) end,
      'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), ''))),
    'datos_personales', v_personal,
    'corte', cs.periodo_carga);
end $function$;
revoke all on function public.geoportal_redes_contrato_tarjeta(text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_contrato_tarjeta(text,text,text) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_nodos_por_clasificar(p_solicitante text, p_buscar text DEFAULT NULL::text, p_despues_de bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_admin(p_solicitante); v_q text := nullif(lower(btrim(coalesce(p_buscar, ''))), ''); v_lim integer := coalesce(p_limite, 50); v_items jsonb;
begin
  if v_lim < 1 or v_lim > 200 then perform tecnica.f_error('Se piden de 1 a 200'); end if;
  if v_q is not null and length(v_q) > 60 then perform tecnica.f_error('La búsqueda es demasiado larga'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('nodo_id', x.nodo_id, 'sistema', x.sistema, 'llave_modelo', x.llave_modelo, 'nombre_modelo', x.nombre_modelo,
           'nombre_visible', x.nombre_visible, 'alias', case when x.nombre_visible is distinct from coalesce(x.nombre_modelo, x.llave_modelo) then x.nombre_visible end,
           'lat', round(ST_Y(x.geom)::numeric, 6), 'lon', round(ST_X(x.geom)::numeric, 6),
           'tramos', (select count(*) from redes.v_tramo_nodos_vigente t where t.nodo_ini = x.nodo_id or t.nodo_fin = x.nodo_id)) order by x.nodo_id), '[]'::jsonb) into v_items
    from (select n.* from redes.v_nodo_visible n
           where n.clase_nodo = 'por_clasificar' and (p_despues_de is null or n.nodo_id > p_despues_de)
             and (v_q is null or position(v_q in lower(coalesce(n.nombre_modelo, '') || ' ' || n.nombre_visible || ' ' || n.llave_modelo)) > 0)
           order by n.nodo_id limit v_lim) x;
  return jsonb_build_object(
    'grupos', coalesce((select jsonb_agg(jsonb_build_object('grupo', g.grupo, 'n', g.n) order by g.n desc, g.grupo)
                          from (select coalesce(substring(n.nombre_modelo from '^[A-Za-zÁÉÍÓÚáéíóúñ]+'), '?') as grupo, count(*) as n
                                  from redes.v_nodo_vigente n where n.clase_nodo = 'por_clasificar' group by 1) g), '[]'::jsonb),
    'total', (select count(*) from redes.v_nodo_visible n where n.clase_nodo = 'por_clasificar'
               and (v_q is null or position(v_q in lower(coalesce(n.nombre_modelo, '') || ' ' || n.nombre_visible || ' ' || n.llave_modelo)) > 0)),
    'items', v_items,
    'siguiente', case when jsonb_array_length(v_items) = v_lim then (v_items -> (v_lim - 1) ->> 'nodo_id')::bigint end,
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre_visible, 'sistema', t.sistema,
                         'pide_clase', exists (select 1 from jsonb_array_elements(t.campos) c where c ->> 'clave' = 'clase' and (c ->> 'obligatorio')::boolean),
                         'clases', coalesce((select jsonb_agg(jsonb_build_object('codigo', k.codigo, 'nombre', k.nombre) order by k.orden) from redes.clases_activo k where k.prefijo = t.prefijo and k.activo), '[]'::jsonb))
                         order by t.sistema, t.orden)
                         from redes.v_tipo_visible t where t.geometria = 'punto' and t.activo and t.sistema in ('acueducto', 'alcantarillado')), '[]'::jsonb));
end $function$;
revoke all on function public.geoportal_redes_nodos_por_clasificar(text,text,bigint,integer) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_nodos_por_clasificar(text,text,bigint,integer) to service_role;

insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte9a', 'reversa_redes_corte9a', null, jsonb_build_object('motivo', 'reversa del Corte 9a (sin datos cargados)'), null);
