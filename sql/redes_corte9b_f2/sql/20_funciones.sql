-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 20 — FUNCIONES INTERNAS. PROPUESTA. Solo agrega (no reemplaza nada).
-- · Alertas de presión (§30.7, Res. 0330 de 2017, arts. 61 y 62): con los 4 parámetros del 9a (15 y 10 m.c.a. de mínima; 50 y 60 de máxima) sobre la presión
--   de MODELO por nodo (redes.pm_nodos, carga vigente; red existente o futura). Y por material: nodos cuya presión máxima pasa la presión de trabajo de un tramo
--   que llega a ellos. Es presión de modelo, no medida: así se rotula.
-- · Usuarios sensibles: propuesta por una palabra del nombre (cartera_suscripcion, último período) — se corre por psql o editor, NUNCA en una petición.
-- · Afectación de un daño o una intervención: contratos sin agua y usuarios sensibles, del cierre real (la foto) si tiene válvulas cerradas, o de la simulación.
-- · Sensores: estado derivado de las lecturas («por conectar» mientras no haya).
-- =====================================================================

-- ---------- nivel de alerta de un nodo por su presión mínima y máxima del día (nulo: en rango). La baja manda sobre la alta; el rojo sobre el naranja ----------
create function redes.f_presion_nivel(p_min numeric, p_max numeric) returns text
language sql stable set search_path = redes, pg_temp as $$
  select case when p_min < redes.f_param('presion_baja_roja_mca') then 'baja_roja'
              when p_max > redes.f_param('presion_alta_roja_mca') then 'alta_roja'
              when p_min < redes.f_param('presion_baja_naranja_mca') then 'baja_naranja'
              when p_max > redes.f_param('presion_alta_naranja_mca') then 'alta_naranja' end $$;

-- ---------- las alertas de presión de un escenario (existente | futura): conteos por nivel, los peores nodos y la alerta por material ----------
create function redes.f_alertas_presion(p_escenario text) returns jsonb
language plpgsql stable security definer set search_path = redes, public, extensions, pg_temp as $$
declare v_c bigint := redes.f_ref_vigente('pm_nodos'); v_lim integer := coalesce(redes.f_param('presion_lista_max'), 50)::integer; v_fut boolean := p_escenario = 'futura'; j jsonb;
  -- los 4 umbrales se leen UNA vez (la misma regla de redes.f_presion_nivel; por nodo costaba 4 lecturas de parámetros)
  v_bn numeric := redes.f_param('presion_baja_naranja_mca'); v_br numeric := redes.f_param('presion_baja_roja_mca');
  v_an numeric := redes.f_param('presion_alta_naranja_mca'); v_ar numeric := redes.f_param('presion_alta_roja_mca');
begin
  if p_escenario not in ('existente', 'futura') then perform tecnica.f_error('El escenario es «existente» o «futura»'); end if;
  if v_c is null then return jsonb_build_object('cargado', false, 'escenario', p_escenario); end if;
  with n as (
    select x.llave, coalesce(x.nombre, x.llave) as nombre, x.zona_modelo, x.geom,
           case when v_fut then x.pres_futura_min else x.pres_exist_min end as p_min, case when v_fut then x.pres_futura_max else x.pres_exist_max end as p_max
      from redes.pm_nodos x where x.carga_id = v_c),
  c as materialized (select n.*, case when n.p_min < v_br then 'baja_roja' when n.p_max > v_ar then 'alta_roja' when n.p_min < v_bn then 'baja_naranja' when n.p_max > v_an then 'alta_naranja' end as nivel
          from n where n.p_min is not null or n.p_max is not null),
  -- por material: el tramo de menor presión de trabajo que llega al nodo (el nodo de la red se amarra por la llave del modelo)
  m as (
    select c.llave, c.nombre, c.p_max, c.geom, min(pt.presion_mca) as trabajo, (array_agg(t.codigo order by pt.presion_mca, t.codigo))[1] as tramo,
           (array_agg(t.material_codigo order by pt.presion_mca, t.codigo))[1] as material
      from c join redes.nodos nd on nd.sistema = 'acueducto' and nd.llave_modelo = c.llave
      join redes.tramo_nodos tn on nd.id in (tn.nodo_ini, tn.nodo_fin)
      join redes.activo_vigente_mat t on t.activo_id = tn.activo_id and t.version = tn.version and t.cuenta_vigente and not t.retirado
      join redes.presion_trabajo pt on pt.material_codigo = t.material_codigo and coalesce(pt.clase, '') = coalesce(t.clase, '')
     where c.p_max > (select min(presion_mca) from redes.presion_trabajo) group by c.llave, c.nombre, c.p_max, c.geom having c.p_max > min(pt.presion_mca))
  select jsonb_build_object(
    'cargado', true, 'escenario', p_escenario, 'fuente', (select origen from redes.ref_cargas where id = v_c),
    'aviso', 'Presión de MODELO, no medida.',
    'umbrales', jsonb_build_object('baja_naranja', v_bn, 'baja_roja', v_br, 'alta_naranja', v_an, 'alta_roja', v_ar),
    'nodos', (select count(*) from c),
    'niveles', (select coalesce(jsonb_object_agg(g.nivel, g.n), '{}') from (select c.nivel, count(*) as n from c where c.nivel is not null group by 1) g),
    'peores', (select coalesce(jsonb_agg(jsonb_build_object('nodo', w.nombre, 'nivel', w.nivel, 'p_min', w.p_min, 'p_max', w.p_max, 'zona', w.zona_modelo,
                                                           'lat', round(ST_Y(w.geom)::numeric, 6), 'lon', round(ST_X(w.geom)::numeric, 6)) order by w.nivel, w.o), '[]')
                 from (select c.*, row_number() over (partition by c.nivel order by case when c.nivel like 'baja%' then c.p_min else -c.p_max end, c.llave) as o
                         from c where c.nivel is not null) w where w.o <= v_lim),
    'por_material', jsonb_build_object('n', (select count(*) from m),
      'nodos', (select coalesce(jsonb_agg(jsonb_build_object('nodo', y.nombre, 'p_max', y.p_max, 'presion_trabajo', y.trabajo, 'tramo', y.tramo, 'material', y.material,
                                                            'lat', round(ST_Y(y.geom)::numeric, 6), 'lon', round(ST_X(y.geom)::numeric, 6)) order by y.exceso desc, y.llave), '[]')
                  from (select m.*, m.p_max - m.trabajo as exceso from m order by m.p_max - m.trabajo desc, m.llave limit v_lim) y),
      'nota', 'Presión de trabajo por material y clase: por verificar con la ficha del fabricante.'))
    into j;
  return j;
end $$;
comment on function redes.f_alertas_presion(text) is 'Corte 9b (Fase 2): alertas de presión de modelo por nodo (Res. 0330 de 2017; 4 parámetros editables) y por material. Lectura.';

-- ---------- lista para los Avisos del 12 (NO está conectada: sumarla pide un bloque en tecnica.f_avisos, que no se toca sin avisar) ----------
create function redes.f_presion_para_avisos() returns table (nivel text, n bigint)
language sql stable security definer set search_path = redes, pg_temp as $$
  select redes.f_presion_nivel(x.pres_exist_min, x.pres_exist_max), count(*)
    from redes.pm_nodos x where x.carga_id = redes.f_ref_vigente('pm_nodos') and redes.f_presion_nivel(x.pres_exist_min, x.pres_exist_max) is not null group by 1 $$;

-- ---------- el tipo de usuario sensible que sugiere un nombre (y la palabra que coincidió); sin filas si no sugiere ninguno ----------
create function redes.f_sensible_tipo(p_nombre text) returns table (tipo text, palabra text)
language sql stable security definer set search_path = redes, pg_temp as $$
  select x.codigo, left((regexp_match(n.nom, x.patron))[1], 60)
    from (select upper(translate(coalesce(p_nombre, ''), 'ÁÉÍÓÚÜáéíóúü', 'AEIOUUaeiouu')) as nom) n      -- primero sin tildes: con configuración regional «C», upper() no cambia las vocales con tilde
    join redes.tipos_sensible x on x.activo and n.nom ~ x.patron order by x.orden limit 1 $$;

-- ---------- propone usuarios sensibles por una palabra del nombre (último período de la cartera). Recorre la cartera: se corre por psql o editor, no en peticiones ----------
create function redes.f_sensibles_proponer(p_autor text) returns integer
language plpgsql volatile security definer set search_path = redes, public, pg_temp as $$
declare v_n integer; v_autor text := lower(btrim(coalesce(p_autor, '')));
begin
  if not public.geoportal_es_admin(v_autor) then raise exception 'Ese correo no es de un administrador' using errcode = '42501'; end if;
  insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor)
  select s.contrato, t.tipo, t.palabra, 'nombre', v_autor
    from (select distinct on (c.contrato) c.contrato, c.nombre
            from public.cartera_suscripcion c where c.contrato ~ '^[0-9]{1,15}$' and c.contrato not in ('0', '99999999')
           order by c.contrato, c.periodo_carga desc nulls last) s
    cross join lateral redes.f_sensible_tipo(s.nombre) t
  on conflict (contrato) do nothing;
  get diagnostics v_n = row_count;
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values (v_autor, 'redes_sensibles_proponer', null, jsonb_build_object('nuevos', v_n), null);
  return v_n;
end $$;
comment on function redes.f_sensibles_proponer(text) is 'Corte 9b (Fase 2): propone usuarios sensibles por una palabra del nombre. Guarda contrato, tipo y la palabra; nunca el nombre. Solo por psql o editor (recorre la cartera).';

-- ---------- los usuarios sensibles entre unos contratos: confirmados y por confirmar (los descartados no) ----------
create function redes.f_sensibles_en(p_contratos text[]) returns jsonb
language sql stable security definer set search_path = redes, pg_temp as $$
  select jsonb_build_object(
    'confirmados', count(*) filter (where v.estado = 'confirmado'), 'por_confirmar', count(*) filter (where v.estado = 'por_confirmar'),
    'lista', coalesce(jsonb_agg(jsonb_build_object('contrato', v.contrato, 'tipo', t.nombre, 'tipo_codigo', v.tipo, 'estado', v.estado) order by t.orden, v.contrato), '[]'))
    from redes.v_usuario_sensible v join redes.tipos_sensible t on t.codigo = v.tipo
   where v.contrato = any (p_contratos) and v.estado <> 'descartado' $$;

-- ---------- el estado de un sensor (activo SEN): por conectar (sin lecturas), en línea o sin señal ----------
create function redes.f_sensor_estado(p_activo bigint) returns text
language sql stable security definer set search_path = redes, pg_temp as $$
  select case when u.medido_en is null then 'por_conectar'
              when u.medido_en >= clock_timestamp() - make_interval(mins => coalesce(redes.f_param('sensor_sin_senal_min'), 60)::integer) then 'en_linea' else 'sin_senal' end
    from (select max(l.medido_en) as medido_en from redes.sensor_lecturas l where l.activo_id = p_activo) u $$;
