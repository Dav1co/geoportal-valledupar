-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 30 — RPC (solo las llama la Edge geoportal-tecnica con service_role; el solicitante es el correo del token)
-- · geoportal_tec_avisos: todos los avisos de la persona, en una sola consulta (menos de 1 s en producción: el ensayo lo mide).
-- · geoportal_tec_avisos_parametros y geoportal_tec_aviso_parametro_fijar: los plazos y mínimos (cada supervisor los de su área; el administrador todos).
-- · geoportal_tec_quimico_minimos y geoportal_tec_quimico_minimo_fijar: el saldo mínimo de cada químico (supervisor de planta y administrador).
-- =====================================================================
create function public.geoportal_tec_avisos(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare p record; v jsonb; t0 timestamptz := clock_timestamp();
begin
  select * into p from tecnica.f_avisos_perfil(p_solicitante);
  v := tecnica.f_avisos(p.planta, p.distribucion, null);
  return jsonb_build_object('areas', jsonb_build_object('planta', p.planta, 'distribucion', p.distribucion, 'personal', true), 'admin', p.admin,
    'avisos', v, 'total', jsonb_array_length(v),
    'rojos', (select count(*) from jsonb_array_elements(v) a where a ->> 'nivel' = 'rojo'),
    'naranjas', (select count(*) from jsonb_array_elements(v) a where a ->> 'nivel' = 'naranja'),
    'calculado_en', clock_timestamp(), 'ms', round(extract(epoch from clock_timestamp() - t0)::numeric * 1000));
end $$;

create function public.geoportal_tec_avisos_parametros(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare p record;
begin
  select * into p from tecnica.f_avisos_perfil(p_solicitante);
  return jsonb_build_object('puede_minimos', p.planta, 'parametros', coalesce((
    select jsonb_agg(jsonb_build_object('clave', a.clave, 'area', a.area, 'nombre', a.nombre, 'descripcion', a.descripcion, 'valor', a.valor, 'minimo', a.minimo, 'maximo', a.maximo,
             'unidad', a.unidad, 'ultimo', (select jsonb_build_object('antes', e.antes, 'despues', e.despues, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en)
                                              from tecnica.aviso_parametro_eventos e where e.clave = a.clave order by e.id desc limit 1)) order by a.orden)
      from tecnica.aviso_parametros a
     where p.admin or (a.area = 'planta' and p.planta) or (a.area = 'distribucion' and p.distribucion)), '[]'::jsonb));
end $$;

create function public.geoportal_tec_aviso_parametro_fijar(p_solicitante text, p_clave text, p_valor numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare p record; a tecnica.aviso_parametros; v_mot text := btrim(coalesce(p_motivo, '')); v_par text; v_otro numeric;
begin
  select * into p from tecnica.f_avisos_perfil(p_solicitante);
  select * into a from tecnica.aviso_parametros where clave = p_clave for update;
  if not found then perform tecnica.f_error('Ese parámetro no existe'); end if;
  if not (p.admin or (a.area = 'planta' and p.planta) or (a.area = 'distribucion' and p.distribucion)) then
    perform tecnica.f_error('Ese parámetro lo cambia el supervisor de su área o el administrador', '42501');
  end if;
  if p_valor is null or p_valor <> trunc(p_valor) then perform tecnica.f_error('Escriba un número entero'); end if;
  if p_valor < a.minimo or p_valor > a.maximo then perform tecnica.f_error(format('El valor va de %s a %s %s', a.minimo, a.maximo, a.unidad)); end if;
  if p_valor = a.valor then perform tecnica.f_error('Ese ya es el valor vigente'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 caracteres)'); end if;
  -- coherencia: el horario empieza antes de terminar; el primer registro cae dentro del horario; en cada riesgo, naranja antes que rojo
  if p_clave = 'horario_inicio' and p_valor >= tecnica.f_aparam('horario_fin') then perform tecnica.f_error('El inicio del horario debe ser antes del fin'); end if;
  if p_clave = 'horario_fin' and p_valor <= tecnica.f_aparam('horario_inicio') then perform tecnica.f_error('El fin del horario debe ser después del inicio'); end if;
  if p_clave = 'planta_primer_registro_hora' and (p_valor < tecnica.f_aparam('horario_inicio') or p_valor >= tecnica.f_aparam('horario_fin')) then
    perform tecnica.f_error('La hora límite del primer registro debe caer dentro del horario del personal');
  end if;
  if p_clave ~ '^dano_(alto|medio|bajo)_(naranja|rojo)_h$' then
    v_par := regexp_replace(p_clave, '_(naranja|rojo)_h$', '') || case when p_clave like '%naranja%' then '_rojo_h' else '_naranja_h' end;
    v_otro := tecnica.f_aparam(v_par);
    if (p_clave like '%naranja%' and p_valor >= v_otro) or (p_clave like '%rojo%' and p_valor <= v_otro) then perform tecnica.f_error('El plazo naranja debe ser menor que el rojo'); end if;
  end if;
  insert into tecnica.aviso_parametro_eventos (clave, antes, despues, motivo, autor) values (a.clave, a.valor, p_valor, v_mot, p.email);
  update tecnica.aviso_parametros set valor = p_valor where clave = a.clave;
  perform tecnica.f_auditar(p.email, 'tec_aviso_parametro', a.clave, jsonb_build_object('antes', a.valor, 'despues', p_valor), null);
  return jsonb_build_object('clave', a.clave, 'antes', a.valor, 'valor', p_valor);
end $$;

create function public.geoportal_tec_quimico_minimos(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante);
begin
  return jsonb_build_object('quimicos', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', q.codigo, 'nombre', q.nombre, 'saldo_kg', s.saldo_kg, 'minimo_kg', m.minimo_kg,
             'bajo', m.minimo_kg is not null and s.saldo_kg is not null and s.saldo_kg < m.minimo_kg,
             'ultimo', case when m.id is not null then jsonb_build_object('minimo_kg', m.minimo_kg, 'motivo', m.motivo, 'autor', m.autor, 'creado_en', m.creado_en) end)
             order by q.nombre)
      from tecnica.quimicos q
      left join tecnica.v_quimico_saldo s on s.quimico_id = q.id
      left join lateral (select e.id, e.minimo_kg, e.motivo, e.autor, e.creado_en from tecnica.quimico_minimo_eventos e where e.quimico_id = q.id order by e.id desc limit 1) m on true
     where q.activo and q.codigo <> 'otro'), '[]'::jsonb));
end $$;

create function public.geoportal_tec_quimico_minimo_fijar(p_solicitante text, p_codigo text, p_minimo_kg numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo);
        v_mot text := btrim(coalesce(p_motivo, '')); v_antes numeric;
begin
  if q.codigo = 'otro' then perform tecnica.f_error('Elija el químico'); end if;
  if p_minimo_kg is not null and (p_minimo_kg <= 0 or p_minimo_kg > 10000000) then perform tecnica.f_error('El saldo mínimo va de más de 0 a 10.000.000 kg; déjelo vacío para quitarlo'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 caracteres)'); end if;
  perform 1 from tecnica.quimicos x where x.id = q.id for update;
  select e.minimo_kg into v_antes from tecnica.quimico_minimo_eventos e where e.quimico_id = q.id order by e.id desc limit 1;
  if v_antes is not distinct from p_minimo_kg then perform tecnica.f_error(case when p_minimo_kg is null then 'Ese químico no tiene saldo mínimo' else 'Ese ya es el saldo mínimo vigente' end); end if;
  insert into tecnica.quimico_minimo_eventos (quimico_id, minimo_kg, motivo, autor) values (q.id, p_minimo_kg, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'tec_quimico_minimo', q.codigo, jsonb_build_object('antes', v_antes, 'despues', p_minimo_kg), null);
  return jsonb_build_object('codigo', q.codigo, 'antes', v_antes, 'minimo_kg', p_minimo_kg);
end $$;
