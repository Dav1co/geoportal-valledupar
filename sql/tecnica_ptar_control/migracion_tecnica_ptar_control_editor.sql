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
commit;
