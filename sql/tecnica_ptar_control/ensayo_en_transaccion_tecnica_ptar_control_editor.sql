begin;
-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 «Sistema de Control PTAR» · 10 — GUARDIA Y ESQUEMA. Va DESPUÉS de PTAR-1 (tecnica_ptar) y ANTES de la carga del mapa.
-- Pedido de David (21-nov, noche): la Caracterización se adelanta de PTAR-4.
--   · La clave de formulario ptar_caracterizacion (dominio y f_formularios, que se reescribe IGUAL a la publicada del Corte 8 + una fila).
--   · El tipo de punto «ptar» (CHECK de puntos y de formulario_variables) y cuatro puntos: PTAR-AFL, PTAR-EFL, PTAR-RIO-ARR y PTAR-RIO-ABJ.
--   · Variables: las de la Caracterización (caudal, DBO5, DQO, SST, nitrógeno y fósforo totales) y las de la sonda multiparámetro (pH, temperatura y OD; sin formulario
--     todavía: la ficha las muestra con «sin registros»). Referencias: ninguna («por definir»).
--   · Caracterización: por punto (tipo ptar), 7 días hacia atrás, ninguna obligatoria (el caudal es diario; los de laboratorio llegan después).
-- NO toca ninguna función ni tabla de redes. Afluente, Entre lagunas, Efluente y los puntos de laguna siguen en PTAR-4.
-- =====================================================================
do $$
declare v_redes text;
begin
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v_redes from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if v_redes is distinct from '1ba192724c2fddcf321104700829f3cc' then
    raise exception 'GUARDIA PTAR-3: la huella de redes es % y se esperaba 1ba192724c2fddcf321104700829f3cc. Deténgase y avise', v_redes;
  end if;
  if to_regclass('tecnica.elementos_planta') is null or to_regprocedure('public.geoportal_tec_ptar_mapa(text,text)') is null then
    raise exception 'GUARDIA PTAR-3: falta PTAR-1 (tecnica_ptar): aplíquelo antes';
  end if;
  if md5(pg_get_functiondef('tecnica.f_autorizar_supervision(text)'::regprocedure)) <> 'cf531900f6be5fc187b73395a2340e2b'
     or md5(pg_get_functiondef('public.geoportal_tec_ptar_mapa(text,text)'::regprocedure)) <> 'e4e70239e7e82441b803f29e5f38d535'
     or md5(pg_get_functiondef('public.geoportal_tec_ptar_elemento(text,text)'::regprocedure)) <> '817fd0406e1dabeeea8702cbf3bc308a' then
    raise exception 'GUARDIA PTAR-3: las funciones de PTAR-1 no son las esperadas. Deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_formularios()'::regprocedure)) <> 'a20a338b69efbcfbb5e90df54b1cb14d' then
    raise exception 'GUARDIA PTAR-3: tecnica.f_formularios no es la publicada del Corte 8 (9 claves). Deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_autorizar_captura(text,text)'::regprocedure)) <> '6c27084e02548703ecd5c2c6f5cc41cd' then
    raise exception 'GUARDIA PTAR-3: tecnica.f_autorizar_captura no es la publicada. Deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_tipo_punto_texto(text)'::regprocedure)) <> '15e5bbe92e8cea94dbe92c66d01bea02' then
    raise exception 'GUARDIA PTAR-3: tecnica.f_tipo_punto_texto no es la publicada (Corte 3). Deténgase y avise';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck')
     <> 'CHECK ((VALUE = ANY (ARRAY[''entrada''::text, ''salida''::text, ''muestreo''::text, ''danos_fallas''::text, ''mantenimiento''::text, ''uso_quimicos''::text, ''entrada_quimicos''::text, ''anomalia_compartida''::text, ''revision_compartida''::text, ''activo_campo''::text])))' then
    raise exception 'GUARDIA PTAR-3: el dominio tecnica.formulario_clave no tiene las 10 claves esperadas (Corte 14). Deténgase y avise';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'tecnica.puntos'::regclass and c.conname = 'puntos_tipo_check')
       <> 'CHECK ((tipo = ANY (ARRAY[''macromedicion''::text, ''muestreo''::text, ''tanque''::text, ''distribucion''::text])))'
     or (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'tecnica.formulario_variables'::regclass and c.conname = 'formulario_variables_tipo_punto_check')
       <> 'CHECK ((tipo_punto = ANY (ARRAY[''macromedicion''::text, ''muestreo''::text, ''tanque''::text, ''distribucion''::text])))'
     or (select count(*) from pg_constraint c where c.conrelid = 'tecnica.puntos'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%tipo = ANY%') <> 1 then
    raise exception 'GUARDIA PTAR-3: los CHECK del tipo de punto no son los esperados (Corte 3). Deténgase y avise';
  end if;
  if exists (select 1 from tecnica.variables where codigo like 'ar\_%') or exists (select 1 from tecnica.puntos where codigo like 'PTAR-%')
     or exists (select 1 from tecnica.formularios_config where formulario::text = 'ptar_caracterizacion') then
    raise exception 'GUARDIA PTAR-3: ya hay variables ar_*, puntos PTAR-* o la Caracterización: el paquete parece aplicado';
  end if;
end $$;

-- ---------- 1. La clave del formulario (dominio y f_formularios) ----------
alter domain tecnica.formulario_clave drop constraint formulario_clave_ck;
alter domain tecnica.formulario_clave add constraint formulario_clave_ck check (value in
  ('entrada', 'salida', 'muestreo', 'danos_fallas', 'mantenimiento', 'uso_quimicos', 'entrada_quimicos', 'anomalia_compartida', 'revision_compartida', 'activo_campo', 'ptar_caracterizacion'));

CREATE OR REPLACE FUNCTION tecnica.f_formularios()
 RETURNS TABLE(clave text, nombre text, descripcion text, orden integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  values ('entrada',          'Entrada',                           'Agua cruda que ingresa a las plantas.', 1),
         ('salida',           'Salida',                            'Agua tratada que sale de las plantas.', 2),
         ('muestreo',         'Muestreo',                          'Muestreo en los puntos de la red y los tanques.', 3),
         ('danos_fallas',     'Daños o fallas',                    'Daños o fallas en la planta.', 4),
         ('mantenimiento',    'Mantenimiento, reparación e inversión', 'Mantenimiento, reparación e inversión.', 5),
         ('uso_quimicos',     'Uso de químicos',                   'Químicos usados en el proceso.', 6),
         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7),
         ('anomalia_compartida', 'Reportar anomalía',               'El mismo reporte de anomalías de Comercial, hecho desde Técnica.', 8),
         ('revision_compartida', 'Revisiones generales',            'La misma revisión general de Comercial, hecha desde Técnica.', 9),
         ('ptar_caracterizacion', 'Caracterización',                'Caracterización del agua residual de la PTAR y del río Cesar.', 10);
$function$;

-- ---------- 2. El tipo de punto «ptar» ----------
alter table tecnica.puntos drop constraint puntos_tipo_check;
alter table tecnica.puntos add constraint puntos_tipo_check check (tipo in ('macromedicion', 'muestreo', 'tanque', 'distribucion', 'ptar'));
alter table tecnica.formulario_variables drop constraint formulario_variables_tipo_punto_check;
alter table tecnica.formulario_variables add constraint formulario_variables_tipo_punto_check check (tipo_punto in ('macromedicion', 'muestreo', 'tanque', 'distribucion', 'ptar'));

-- ---------- 3. Los cuatro puntos de la Caracterización (sin planta de agua potable; su lugar en el mapa es el elemento PTAR-PM-* del GeoJSON) ----------
insert into tecnica.puntos (codigo, nombre, tipo, planta_id) values
  ('PTAR-AFL',     'Afluente — llegada del alcantarillado', 'ptar', null),
  ('PTAR-EFL',     'Efluente — salida al río Cesar', 'ptar', null),
  ('PTAR-RIO-ARR', 'Río Cesar aguas arriba del vertimiento', 'ptar', null),
  ('PTAR-RIO-ABJ', 'Río Cesar aguas abajo del vertimiento', 'ptar', null);

-- ---------- 4. Variables (códigos propios ar_*: no heredan las referencias del agua potable) ----------
insert into tecnica.variables (codigo, nombre, unidad, categoria, decimales) values
  ('ar_caudal',          'Caudal',                      'L/s',            'caudal',        1),
  ('ar_dbo5',            'DBO5',                        'mg/L O2',        'fisicoquimico', 1),
  ('ar_dqo',             'DQO',                         'mg/L O2',        'fisicoquimico', 1),
  ('ar_sst',             'Sólidos suspendidos totales', 'mg/L',           'fisicoquimico', 1),
  ('ar_nitrogeno_total', 'Nitrógeno total',             'mg/L N',         'fisicoquimico', 2),
  ('ar_fosforo_total',   'Fósforo total',               'mg/L P',         'fisicoquimico', 2),
  ('ar_ph',              'pH',                          'unidades de pH', 'fisicoquimico', 2),
  ('ar_temperatura',     'Temperatura',                 '°C',             'fisicoquimico', 1),
  ('ar_od',              'Oxígeno disuelto',            'mg/L',           'fisicoquimico', 2);

-- ---------- 5. El formulario Caracterización: por punto (tipo ptar), ninguna obligatoria, 7 días hacia atrás ----------
insert into tecnica.formulario_variables (formulario, variable_id, orden, obligatoria, alcance, tipo_punto)
select 'ptar_caracterizacion', v.id, x.o, false, 'por_punto', 'ptar'
  from unnest(array['ar_caudal', 'ar_dbo5', 'ar_dqo', 'ar_sst', 'ar_nitrogeno_total', 'ar_fosforo_total']) with ordinality x(c, o)
  join tecnica.variables v on v.codigo = x.c;
insert into tecnica.formularios_config (formulario, dias_atras_max) values ('ptar_caracterizacion', 7);
-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 · 20 — FUNCIONES INTERNAS.
-- =====================================================================

-- El texto del tipo de punto (la publicada del Corte 3 + «ptar»): lo usan los mensajes de registrar_medicion y de f_registro_coherente.
create or replace function tecnica.f_tipo_punto_texto(p_tipo text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case p_tipo when 'muestreo' then 'punto de muestreo' when 'tanque' then 'tanque' when 'distribucion' then 'punto de distribución'
                     when 'macromedicion' then 'punto de macromedición' when 'ptar' then 'punto de la PTAR' else 'punto' end
$$;

-- Puerta de la CAPTURA (la publicada + el alcance, D6): el supervisor captura todo lo de su alcance, no lo del otro.
--   · Formularios de la PTAR (ptar_*): el supervisor necesita el alcance PTAR. · Formularios de planta de agua potable: el alcance PTAP.
--   · Los de distribución y los compartidos no cambian. El administrador, todo. El operador, como siempre: lo que tenga asignado.
create or replace function tecnica.f_autorizar_captura(p_solicitante text, p_formulario text) returns text
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text; v_perfil text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'registro_tecnico');       -- 28000 / 42501 si no hay sesión, acceso o permiso
  v_perfil := tecnica.f_perfil(v_email);
  if v_perfil = 'admin' then return v_email; end if;
  if not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  if v_perfil = 'supervisor' then
    if p_formulario like 'ptar\_%' and not tecnica.f_tiene_alcance(v_email, 'ptar') then
      raise exception 'No tiene el alcance de la PTAR' using errcode = '42501';
    end if;
    if p_formulario in ('entrada', 'salida', 'muestreo', 'uso_quimicos', 'entrada_quimicos') and not tecnica.f_tiene_alcance(v_email, 'ptap') then
      raise exception 'Su acceso es a la PTAR, no a las plantas de agua potable' using errcode = '42501';
    end if;
    return v_email;
  end if;
  if not tecnica.f_formulario_asignado(v_email, p_formulario) then
    raise exception 'No tiene asignado este formulario' using errcode = '42501';
  end if;
  return v_email;
end $$;

-- Los parámetros de un punto de la PTAR con su ÚLTIMO valor vigente (sin excluidos): primero los de la sonda multiparámetro (pH, temperatura, OD), luego los de
-- los formularios «por punto» de su tipo (Caracterización). Estado de cada uno: sin_registros · sin_dato_reciente (más viejo que la ventana de la instalación, D10)
-- · sin_referencia · normal · fuera (frente a la referencia vigente; marca, nunca rechaza). Las referencias de la PTAR están «por definir»: hoy, sin_referencia.
create function tecnica.f_parametros_punto(p_punto_id bigint, p_horas integer) returns jsonb
language sql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
  with pu as (select p.id, p.tipo from tecnica.puntos p where p.id = p_punto_id),
  par as (
    select v.id, v.codigo, v.nombre, v.unidad, v.decimales, 'Sonda multiparámetro'::text as grupo, x.o::integer as o
      from unnest(array['ar_ph', 'ar_temperatura', 'ar_od']) with ordinality x(c, o) join tecnica.variables v on v.codigo = x.c and v.activa
    union all
    select v.id, v.codigo, v.nombre, v.unidad, v.decimales, f.nombre, 100 * f.orden + fv.orden
      from tecnica.formulario_variables fv join tecnica.variables v on v.id = fv.variable_id join tecnica.f_formularios() f on f.clave = fv.formulario::text
      join pu on pu.tipo = fv.tipo_punto
     where fv.alcance = 'por_punto' and fv.activa and v.activa and (fv.punto_id is null or fv.punto_id = p_punto_id)
       and v.codigo not in ('ar_ph', 'ar_temperatura', 'ar_od')
  ),
  ult as (
    select par.*, r.valor, r.muestra_ts, r.formulario as r_form, rf.ref_min, rf.ref_max
      from par
      left join lateral (select r.valor, r.muestra_ts, r.formulario from tecnica.v_registros_estado r
                          where r.variable_id = par.id and r.punto_id = p_punto_id and not r.excluido order by r.muestra_ts desc, r.id desc limit 1) r on true
      left join lateral tecnica.f_referencia_vigente(par.id, null, p_punto_id) rf on true
  )
  select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'unidad', unidad, 'decimales', decimales, 'grupo', grupo,
           'valor', valor, 'muestra_ts', muestra_ts, 'ref_min', ref_min, 'ref_max', ref_max,
           'estado', case when muestra_ts is null then 'sin_registros'
                          when muestra_ts < clock_timestamp() - make_interval(hours => p_horas) then 'sin_dato_reciente'
                          when ref_min is null and ref_max is null then 'sin_referencia'
                          when tecnica.f_marca_rango(valor, ref_min, ref_max) is not null then 'fuera'
                          else 'normal' end) order by o), '[]'::jsonb)
    from ult
$$;

-- El estado de un elemento en el mapa a partir de sus parámetros: fuera > normal / sin_referencia (con dato reciente) > sin_dato_reciente > sin_registros.
create function tecnica.f_estado_parametros(p jsonb) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select case when p is null or jsonb_array_length(p) = 0 then 'sin_variables'
              when exists (select 1 from jsonb_array_elements(p) e where e ->> 'estado' = 'fuera') then 'fuera'
              when exists (select 1 from jsonb_array_elements(p) e where e ->> 'estado' in ('normal', 'sin_referencia')) then 'con_datos'
              when exists (select 1 from jsonb_array_elements(p) e where e ->> 'estado' = 'sin_dato_reciente') then 'sin_dato_reciente'
              else 'sin_registros' end
$$;
-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 · 26 — RPC: el mapa y la ficha (las de PTAR-1, ahora con los parámetros y el estado del punto). Misma firma; misma puerta (D6).
-- =====================================================================

-- El mapa de una instalación: todos sus elementos activos en un GeoJSON (6 decimales ≈ 0,1 m), en el orden de dibujo
-- (perímetro, lagunas, tramos, pozos y descargas, puntos de medición). PTAR-3: el punto de medición enlazado a un punto de la PTAR trae el estado de sus parámetros
-- (sin_registros, sin_dato_reciente, con_datos o fuera); los demás elementos, «sin_variables» mientras no tengan variables asignadas.
create or replace function public.geoportal_tec_ptar_mapa(p_solicitante text, p_instalacion text default 'ptar') returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare i tecnica.instalaciones; v_fc jsonb; v_caja jsonb; v_tipos jsonb;
begin
  perform tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  i := tecnica.f_instalacion(p_instalacion);
  perform tecnica.f_autorizar_instalacion(p_solicitante, i.id);
  with al as (
    select distinct on (a.codigo) a.codigo, a.alias from tecnica.elemento_alias_eventos a where a.instalacion_id = i.id order by a.codigo, a.id desc
  ), el as (
    select e.*, al.alias, case when e.punto_id is null then 'sin_variables' else tecnica.f_estado_parametros(tecnica.f_parametros_punto(e.punto_id, i.horas_sin_dato)) end as estado_calc,
           case e.tipo when 'perimetro' then 1 when 'laguna' then 2 when 'tramo' then 3 when 'pozo' then 4 when 'descarga' then 4 else 5 end as capa
      from tecnica.elementos_planta e left join al on al.codigo = e.codigo
     where e.instalacion_id = i.id and e.activo
  )
  select jsonb_build_object('type', 'FeatureCollection', 'features', coalesce(jsonb_agg(jsonb_build_object('type', 'Feature', 'id', el.id,
           'geometry', st_asgeojson(el.geom, 6)::jsonb,
           'properties', jsonb_strip_nulls(jsonb_build_object('codigo', el.codigo, 'tipo', el.tipo, 'nombre', el.nombre, 'alias', el.alias, 'orden', el.orden,
                                                              'activo', el.activo_codigo, 'origen', el.origen, 'tipo_laguna', el.atributos ->> 'tipo_laguna',
                                                              'tren', el.atributos ->> 'tren', 'punto', (select p.codigo from tecnica.puntos p where p.id = el.punto_id), 'estado', el.estado_calc)))
           order by el.capa, el.orden, el.codigo), '[]'::jsonb)),
         (select jsonb_build_array(round(st_xmin(x)::numeric, 6), round(st_ymin(x)::numeric, 6), round(st_xmax(x)::numeric, 6), round(st_ymax(x)::numeric, 6))
            from (select st_extent(geom)::geometry as x from el) c where x is not null),
         (select jsonb_object_agg(t, n) from (select tipo as t, count(*) as n from el group by tipo) z)
    into v_fc, v_caja, v_tipos
    from el;
  return jsonb_build_object('instalacion', jsonb_build_object('codigo', i.codigo, 'nombre', i.nombre, 'tipo', i.tipo, 'horas_sin_dato', i.horas_sin_dato),
                            'caja', v_caja, 'por_tipo', coalesce(v_tipos, '{}'::jsonb), 'total', jsonb_array_length(v_fc -> 'features'), 'elementos', v_fc);
end $$;

-- Ficha de un elemento (popup del mapa): nombre, alias, tipo, medida, flujo, activo de redes y atributos. PTAR-3: si el elemento tiene su punto de la PTAR, los
-- parámetros de ese punto (sonda multiparámetro y Caracterización) con su último valor, fecha y estado; si no, «sin_variables» y la lista vacía.
create or replace function public.geoportal_tec_ptar_elemento(p_solicitante text, p_codigo text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_cod text := upper(btrim(coalesce(p_codigo, ''))); e tecnica.elementos_planta; i tecnica.instalaciones; v_medida jsonb; v_par jsonb := '[]'::jsonb;
begin
  perform tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if v_cod !~ '^[A-Z0-9][A-Z0-9_-]{1,39}$' then perform tecnica.f_error('El código del elemento no es válido'); end if;
  select * into e from tecnica.elementos_planta x where x.codigo = v_cod and x.activo;
  if not found then perform tecnica.f_error('Ese elemento no existe', 'P0002'); end if;
  perform tecnica.f_autorizar_instalacion(p_solicitante, e.instalacion_id);
  select * into i from tecnica.instalaciones x where x.id = e.instalacion_id;
  if e.punto_id is not null then v_par := tecnica.f_parametros_punto(e.punto_id, i.horas_sin_dato); end if;
  v_medida := case when e.tipo in ('perimetro', 'laguna') then jsonb_build_object('area_m2', round(st_area(e.geom::geography)::numeric), 'area_ha', round((st_area(e.geom::geography) / 10000)::numeric, 2))
                   when e.tipo = 'tramo' then jsonb_build_object('longitud_m', round(st_length(e.geom::geography)::numeric, 1))
                   else jsonb_build_object('lat', round(st_y(e.geom)::numeric, 6), 'lon', round(st_x(e.geom)::numeric, 6)) end;
  return jsonb_strip_nulls(jsonb_build_object(
    'codigo', e.codigo, 'tipo', e.tipo, 'tipo_texto', tecnica.f_tipo_elemento_texto(e.tipo), 'nombre', e.nombre, 'alias', tecnica.f_alias_vigente(e.instalacion_id, e.codigo),
    'orden', e.orden, 'origen', e.origen, 'activo', e.activo_codigo, 'atributos', e.atributos, 'medida', v_medida,
    'instalacion', jsonb_build_object('codigo', i.codigo, 'nombre', i.nombre, 'tipo', i.tipo),
    'desde', (select jsonb_build_object('codigo', d.codigo, 'nombre', d.nombre) from tecnica.elementos_planta d where d.id = e.desde_id),
    'hasta', (select jsonb_build_object('codigo', h.codigo, 'nombre', h.nombre) from tecnica.elementos_planta h where h.id = e.hasta_id),
    'punto', (select jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre) from tecnica.puntos p where p.id = e.punto_id),
    'versiones', (select count(*) from tecnica.elementos_planta x where x.instalacion_id = e.instalacion_id and x.codigo = e.codigo),
    'alias_historial', coalesce((select jsonb_agg(jsonb_build_object('alias', a.alias, 'motivo', a.motivo, 'autor', a.autor, 'creado_en', a.creado_en) order by a.id desc)
                                   from (select * from tecnica.elemento_alias_eventos a where a.instalacion_id = e.instalacion_id and a.codigo = e.codigo order by a.id desc limit 10) a), '[]'::jsonb),
    'estado', case when e.punto_id is null then 'sin_variables' else tecnica.f_estado_parametros(v_par) end, 'indicadores', v_par,
    'horas_sin_dato', i.horas_sin_dato, 'creado_en', e.creado_en));
end $$;
-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 · 40 — PERMISOS. Funciones nuevas: revoke all a public, anon, authenticated y service_role (las usan las RPC SECURITY DEFINER).
-- Las reemplazadas con CREATE OR REPLACE (f_formularios, f_tipo_punto_texto, f_autorizar_captura, geoportal_tec_ptar_mapa y _elemento) conservan sus privilegios.
-- =====================================================================
revoke all on function tecnica.f_parametros_punto(bigint, integer), tecnica.f_estado_parametros(jsonb) from public, anon, authenticated, service_role;
-- Las internas reemplazadas: sin EXECUTE para los roles de la API (en producción ya lo estaban desde la Torre B; se repite por si acaso: es idempotente y las RPC
-- SECURITY DEFINER las siguen llamando como dueñas).
revoke all on function tecnica.f_autorizar_captura(text, text), tecnica.f_formularios(), tecnica.f_tipo_punto_texto(text) from public, anon, authenticated;
-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 · 70 — PRUEBAS «N de N». Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción. Todo SIMULADO y se deshace.
-- Personas prueba.ptar3.*; una instalación de prueba (prueba_ptar3) con elementos PRUEBA3-*; un punto de muestreo de prueba (PRUEBA3-MUE). Las variables ar_* y los
-- puntos PTAR-* los crea esta migración: sus registros en la prueba son SOLO de la prueba. Termina con un ERROR a propósito.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · PTAR-3 … RESULTADO: N de N pruebas correctas — SIN FALLAS
-- =====================================================================
create temp table _r (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.reg(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as
$$ insert into _r (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $$;
create function pg_temp.err(p_nombre text, p_sql text, p_estado text default null, p_texto text default null) returns void language plpgsql as $$
declare v_e text; v_m text;
begin
  begin
    execute p_sql;
    perform pg_temp.reg(p_nombre, false, 'No falló y debía fallar');
  exception when others then
    get stacked diagnostics v_e = returned_sqlstate, v_m = message_text;
    perform pg_temp.reg(p_nombre, (p_estado is null or v_e = p_estado) and (p_texto is null or position(p_texto in v_m) > 0), 'SQLSTATE ' || v_e || ': ' || left(v_m, 200));
  end;
end $$;
create function pg_temp.registrar(p_quien text, p_punto text, p_valores jsonb, p_dias integer) returns jsonb language sql as $$
  select public.geoportal_tec_registrar_medicion(p_solicitante => p_quien, p_formulario => 'ptar_caracterizacion', p_planta => null, p_hora_muestra => '08:00',
           p_valores => p_valores, p_punto => p_punto, p_fecha_muestra => (clock_timestamp() at time zone 'America/Bogota')::date - p_dias) $$;
create function pg_temp.par(j jsonb, p_cod text) returns jsonb language sql as $$ select e from jsonb_array_elements(j -> 'indicadores') e where e ->> 'codigo' = p_cod $$;

do $prueba$
declare
  adm text := 'prueba.ptar3.adm@emdupar.gov.co'; sr text := 'prueba.ptar3.jefe@emdupar.gov.co'; sp text := 'prueba.ptar3.sp@emdupar.gov.co';
  sx text := 'prueba.ptar3.sx@emdupar.gov.co'; op text := 'prueba.ptar3.op@emdupar.gov.co'; op2 text := 'prueba.ptar3.op2@emdupar.gov.co';
  v_inst bigint; v_afl bigint; v_efl bigint; v_abj bigint; j jsonb; v_total integer; v_bien integer; v_fallas text;
  pt text := '{"type":"Point","coordinates":[-74.5,4.5]}';
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTPTAR3 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values
    (sr, 'ZTPTAR3 Jefe de la PTAR', 'consulta', true, true, 'sin_restriccion', 'todos'), (sp, 'ZTPTAR3 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos'),
    (sx, 'ZTPTAR3 Supervisor técnico', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values
    (op, 'ZTPTAR3 Operador de la PTAR', 'consulta', true, 'sin_restriccion', 'todos'), (op2, 'ZTPTAR3 Operador sin el formulario', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.alcance_eventos (persona, alcance, tipo_evento, motivo, autor) values (sr, 'ptar', 'asignar', 'PRUEBA3 jefe de la PTAR', adm),
    (sr, 'ptap', 'quitar', 'PRUEBA3 el jefe no ve la PTAP', adm), (sx, 'ptar', 'asignar', 'PRUEBA3 supervisor técnico con los dos', adm);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'ptar_caracterizacion', adm);
  select id into v_afl from tecnica.puntos where codigo = 'PTAR-AFL';
  select id into v_efl from tecnica.puntos where codigo = 'PTAR-EFL';
  select id into v_abj from tecnica.puntos where codigo = 'PTAR-RIO-ABJ';

  -- ---------- 01. Lo que crea el paquete ----------
  perform pg_temp.reg('01.01 la clave ptar_caracterizacion en el dominio (11 claves)', (select pg_get_constraintdef(c.oid) from pg_constraint c
    where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') like '%''activo_campo''::text, ''ptar_caracterizacion''::text]%');
  perform pg_temp.reg('01.02 f_formularios: las 9 de siempre, iguales, y «Caracterización» al final (orden 10)', (select count(*) from tecnica.f_formularios()) = 10
    and (select string_agg(clave || ':' || orden, ',' order by orden) from tecnica.f_formularios()) = 'entrada:1,salida:2,muestreo:3,danos_fallas:4,mantenimiento:5,uso_quimicos:6,entrada_quimicos:7,anomalia_compartida:8,revision_compartida:9,ptar_caracterizacion:10'
    and (select nombre from tecnica.f_formularios() where clave = 'ptar_caracterizacion') = 'Caracterización');
  perform pg_temp.reg('01.03 cuatro puntos de la PTAR, tipo ptar, sin planta de agua potable', (select count(*) from tecnica.puntos where codigo in ('PTAR-AFL', 'PTAR-EFL', 'PTAR-RIO-ARR', 'PTAR-RIO-ABJ')
    and tipo = 'ptar' and planta_id is null and activo) = 4);
  perform pg_temp.reg('01.04 nueve variables ar_* (caracterización y sonda) y ninguna referencia («por definir»)', (select count(*) from tecnica.variables where codigo like 'ar\_%') = 9
    and not exists (select 1 from tecnica.referencias r join tecnica.variables v on v.id = r.variable_id where v.codigo like 'ar\_%'));
  perform pg_temp.reg('01.05 Caracterización: 6 variables por punto (tipo ptar), ninguna obligatoria, en su orden', (select string_agg(v.codigo, ',' order by fv.orden) from tecnica.formulario_variables fv
    join tecnica.variables v on v.id = fv.variable_id where fv.formulario = 'ptar_caracterizacion' and fv.alcance = 'por_punto' and fv.tipo_punto = 'ptar' and not fv.obligatoria and fv.activa)
    = 'ar_caudal,ar_dbo5,ar_dqo,ar_sst,ar_nitrogeno_total,ar_fosforo_total');
  perform pg_temp.reg('01.06 Caracterización admite 7 días hacia atrás', (select dias_atras_max from tecnica.formularios_config where formulario = 'ptar_caracterizacion' and activa) = 7);
  perform pg_temp.reg('01.07 el texto del tipo de punto: «punto de la PTAR» (los de siempre no cambian)', tecnica.f_tipo_punto_texto('ptar') = 'punto de la PTAR'
    and tecnica.f_tipo_punto_texto('muestreo') = 'punto de muestreo' and tecnica.f_tipo_punto_texto('tanque') = 'tanque');
  perform pg_temp.err('01.08 un tipo de punto desconocido no entra', $$insert into tecnica.puntos (codigo, nombre, tipo) values ('PRUEBA3-X', 'PRUEBA3 X', 'laguna')$$, '23514');

  -- ---------- 02. La puerta de la captura con el alcance (D6) ----------
  perform pg_temp.reg('02.01 Caracterización: el jefe de la PTAR, el de los dos alcances, el administrador y el operador con el formulario', tecnica.f_autorizar_captura(sr, 'ptar_caracterizacion') = sr
    and tecnica.f_autorizar_captura(sx, 'ptar_caracterizacion') = sx and tecnica.f_autorizar_captura(adm, 'ptar_caracterizacion') = adm and tecnica.f_autorizar_captura(op, 'ptar_caracterizacion') = op);
  perform pg_temp.err('02.02 Caracterización: el supervisor de la PTAP (sin la PTAR) no', format('select tecnica.f_autorizar_captura(%L, %L)', sp, 'ptar_caracterizacion'), '42501', 'PTAR');
  perform pg_temp.err('02.03 Caracterización: el operador sin el formulario asignado no', format('select tecnica.f_autorizar_captura(%L, %L)', op2, 'ptar_caracterizacion'), '42501', 'asignado');
  perform pg_temp.err('02.04 Entrada (PTAP): el jefe de la PTAR (sin la PTAP) no', format('select tecnica.f_autorizar_captura(%L, %L)', sr, 'entrada'), '42501', 'PTAR');
  perform pg_temp.reg('02.05 Entrada (PTAP): el supervisor de planta y el de los dos, como siempre', tecnica.f_autorizar_captura(sp, 'entrada') = sp and tecnica.f_autorizar_captura(sx, 'salida') = sx);
  perform pg_temp.reg('02.06 lo de distribución no cambia: el jefe de la PTAR (supervisor) sigue pudiendo «Daños o fallas»', tecnica.f_autorizar_captura(sr, 'danos_fallas') = sr);

  -- ---------- 03. El formulario y el registro (las RPC de siempre, sin cambios) ----------
  j := public.geoportal_tec_obtener_formulario(sr, 'ptar_caracterizacion');
  perform pg_temp.reg('03.01 obtener_formulario: los 4 puntos de la PTAR, las 6 variables y 7 días hacia atrás', (select string_agg(e ->> 'codigo', ',' order by e ->> 'codigo') from jsonb_array_elements(j -> 'puntos') e)
    = 'PTAR-AFL,PTAR-EFL,PTAR-RIO-ABJ,PTAR-RIO-ARR' and jsonb_array_length(j -> 'variables') = 6 and (j ->> 'dias_atras_max')::integer = 7, (j - 'plantas')::text);
  j := pg_temp.registrar(sr, 'PTAR-AFL', '[{"variable":"ar_caudal","valor":"412.5"}]', 0);
  perform pg_temp.reg('03.02 el jefe registra solo el caudal del afluente (las de laboratorio no son obligatorias)', (j ->> 'guardados')::integer = 1, j::text);
  j := pg_temp.registrar(op, 'PTAR-AFL', '[{"variable":"ar_dbo5","valor":180},{"variable":"ar_dqo","valor":"390"},{"variable":"ar_sst","valor":"120"}]', 3);
  perform pg_temp.reg('03.03 el operador registra los resultados del laboratorio de hace 3 días', (j ->> 'guardados')::integer = 3
    and j ->> 'fecha_muestra' = ((clock_timestamp() at time zone 'America/Bogota')::date - 3)::text, j::text);
  perform pg_temp.err('03.04 más de 7 días atrás: no', format('select pg_temp.registrar(%L, %L, %L, 8)', sr, 'PTAR-EFL', '[{"variable":"ar_caudal","valor":1}]'), '22023', '7 días');
  insert into tecnica.puntos (codigo, nombre, tipo) values ('PRUEBA3-MUE', 'PRUEBA3 punto de muestreo', 'muestreo');
  perform pg_temp.err('03.05 un punto de muestreo de la red no sirve para la Caracterización', format('select pg_temp.registrar(%L, %L, %L, 0)', sr, 'PRUEBA3-MUE', '[{"variable":"ar_caudal","valor":1}]'),
    '22023', 'punto de la PTAR');
  perform pg_temp.err('03.06 el supervisor de la PTAP no registra la Caracterización', format('select pg_temp.registrar(%L, %L, %L, 0)', sp, 'PTAR-AFL', '[{"variable":"ar_caudal","valor":1}]'), '42501');
  perform pg_temp.err('03.07 una variable de la sonda no está en la Caracterización', format('select pg_temp.registrar(%L, %L, %L, 0)', sr, 'PTAR-AFL', '[{"variable":"ar_ph","valor":7}]'), '22023', 'no pertenece');

  -- ---------- 04. Parámetros y estado en la ficha y en el mapa ----------
  insert into tecnica.instalaciones (codigo, nombre, tipo, horas_sin_dato) values ('prueba_ptar3', 'PRUEBA3 PTAR', 'residual', 168) returning id into v_inst;
  insert into tecnica.elementos_planta (instalacion_id, codigo, tipo, nombre, geom, punto_id, origen, creado_por) values
    (v_inst, 'PRUEBA3-PM-AFL', 'punto_medicion', 'PRUEBA3 afluente', st_setsrid(st_geomfromgeojson(pt), 4326), v_afl, 'dibujo', adm),
    (v_inst, 'PRUEBA3-PM-EFL', 'punto_medicion', 'PRUEBA3 efluente', st_setsrid(st_geomfromgeojson(pt), 4326), v_efl, 'dibujo', adm),
    (v_inst, 'PRUEBA3-PM-ABJ', 'punto_medicion', 'PRUEBA3 río abajo', st_setsrid(st_geomfromgeojson(pt), 4326), v_abj, 'dibujo', adm),
    (v_inst, 'PRUEBA3-POZ', 'pozo', 'PRUEBA3 pozo', st_setsrid(st_geomfromgeojson(pt), 4326), null, 'dibujo', adm);
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA3-PM-AFL');
  perform pg_temp.reg('04.01 ficha del afluente: primero la sonda (pH, temperatura, OD) «sin registros», luego la Caracterización',
    (select string_agg(e ->> 'codigo', ',' order by n) from jsonb_array_elements(j -> 'indicadores') with ordinality x(e, n)) = 'ar_ph,ar_temperatura,ar_od,ar_caudal,ar_dbo5,ar_dqo,ar_sst,ar_nitrogeno_total,ar_fosforo_total'
    and (select bool_and(e ->> 'estado' = 'sin_registros' and e ->> 'grupo' = 'Sonda multiparámetro') from jsonb_array_elements(j -> 'indicadores') e where e ->> 'codigo' in ('ar_ph', 'ar_temperatura', 'ar_od')), j::text);
  perform pg_temp.reg('04.02 el último valor con su fecha: caudal 412,5 de hoy y DBO5 180 de hace 3 días, «sin referencia» (por definir)', (pg_temp.par(j, 'ar_caudal') ->> 'valor')::numeric = 412.5
    and pg_temp.par(j, 'ar_caudal') ->> 'estado' = 'sin_referencia' and (pg_temp.par(j, 'ar_dbo5') ->> 'valor')::numeric = 180 and pg_temp.par(j, 'ar_dbo5') ->> 'muestra_ts' is not null
    and pg_temp.par(j, 'ar_fosforo_total') ->> 'estado' = 'sin_registros' and j ->> 'estado' = 'con_datos', j::text);
  -- una referencia de prueba en el efluente y un valor por encima: «fuera»
  insert into tecnica.referencias (variable_id, punto_id, ref_max, origen, fuente) select id, v_efl, 100, 'criterio_planta', 'PRUEBA3 referencia de prueba' from tecnica.variables where codigo = 'ar_dbo5';
  perform pg_temp.registrar(sr, 'PTAR-EFL', '[{"variable":"ar_dbo5","valor":150}]', 1);
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA3-PM-EFL');
  perform pg_temp.reg('04.03 con referencia y un valor por encima: «fuera» en el parámetro y en el elemento', pg_temp.par(j, 'ar_dbo5') ->> 'estado' = 'fuera' and j ->> 'estado' = 'fuera', j::text);
  -- un valor viejo (7 días, más que la ventana de 168 h): «sin dato reciente»
  perform pg_temp.registrar(sr, 'PTAR-RIO-ABJ', '[{"variable":"ar_caudal","valor":2000}]', 7);
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA3-PM-ABJ');
  perform pg_temp.reg('04.04 con un dato más viejo que la ventana (D10): «sin dato reciente»', pg_temp.par(j, 'ar_caudal') ->> 'estado' = 'sin_dato_reciente' and j ->> 'estado' = 'sin_dato_reciente', j::text);
  -- un registro excluido no cuenta (se toma el anterior)
  insert into tecnica.exclusiones (registro_id, accion, motivo, autor)
  select r.id, 'EXCLUIR', 'PRUEBA3 valor mal digitado', adm from tecnica.registros r join tecnica.variables v on v.id = r.variable_id where v.codigo = 'ar_caudal' and r.punto_id = v_afl;
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA3-PM-AFL');
  perform pg_temp.reg('04.05 un registro excluido no cuenta como último valor', pg_temp.par(j, 'ar_caudal') ->> 'estado' = 'sin_registros', j::text);
  j := public.geoportal_tec_ptar_elemento(sr, 'PRUEBA3-POZ');
  perform pg_temp.reg('04.06 un elemento sin punto: «sin_variables», sin parámetros', j ->> 'estado' = 'sin_variables' and jsonb_array_length(j -> 'indicadores') = 0, j::text);
  j := public.geoportal_tec_ptar_mapa(sr, 'prueba_ptar3');
  perform pg_temp.reg('04.07 el mapa trae el estado y el punto de cada punto de medición', (select string_agg(f -> 'properties' ->> 'codigo' || '=' || (f -> 'properties' ->> 'estado') || '@' || coalesce(f -> 'properties' ->> 'punto', '-'), ',' order by f -> 'properties' ->> 'codigo')
      from jsonb_array_elements(j -> 'elementos' -> 'features') f) = 'PRUEBA3-PM-ABJ=sin_dato_reciente@PTAR-RIO-ABJ,PRUEBA3-PM-AFL=con_datos@PTAR-AFL,PRUEBA3-PM-EFL=fuera@PTAR-EFL,PRUEBA3-POZ=sin_variables@-', j::text);
  perform pg_temp.err('04.08 el supervisor de la PTAP no abre la ficha de la PTAR', format('select public.geoportal_tec_ptar_elemento(%L, %L)', sp, 'PRUEBA3-PM-AFL'), '42501');

  -- ---------- 05. Lo que no cambia ----------
  perform pg_temp.reg('05.01 la huella de redes no cambia (1ba192724c2fddcf321104700829f3cc)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
      where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '1ba192724c2fddcf321104700829f3cc');
  perform pg_temp.reg('05.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));
  perform pg_temp.reg('05.03 las funciones nuevas sin EXECUTE para la API; las RPC del mapa y la ficha, solo service_role',
    (select bool_and(not has_function_privilege(r, p.oid, 'execute')) from pg_proc p cross join (values ('anon'), ('authenticated'), ('service_role')) x(r)
      where p.pronamespace = 'tecnica'::regnamespace and p.proname in ('f_parametros_punto', 'f_estado_parametros'))
    and (select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute'))
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_tec_ptar_mapa', 'geoportal_tec_ptar_elemento'))
    and not has_function_privilege('anon', 'tecnica.f_autorizar_captura(text,text)'::regprocedure, 'execute'));
  perform pg_temp.reg('05.04 la PTAR sigue fuera de tecnica.plantas', not exists (select 1 from tecnica.plantas where codigo like '%ptar%'));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · PTAR-3 (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total,
    case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
