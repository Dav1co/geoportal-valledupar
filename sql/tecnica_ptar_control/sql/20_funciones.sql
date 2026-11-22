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
