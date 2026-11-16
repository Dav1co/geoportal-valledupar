-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 26 — FUNCIONES NUEVAS
--   · tecnica.f_remision_subida: la foto es de quien la pide, ya subió, es JPEG y no pasa del tamaño.
--   · geoportal_tec_quimico_remision_preparar: reserva la ruta de la foto (quien tiene «Entrada de químicos»).
--   · geoportal_tec_quimico_parametros: los parámetros que se pueden editar, con su rango y su último cambio (supervisor de planta y administrador).
--   · geoportal_tec_quimico_parametro_fijar: cambia uno, con motivo; queda en el historial y en la auditoría.
-- =====================================================================
create function tecnica.f_remision_subida(p_ruta text, p_email text) returns bigint language plpgsql stable security definer set search_path = tecnica, storage, pg_temp as $$
declare v_b bigint; v_m text;
begin
  if p_ruta is null or not exists (select 1 from tecnica.quimico_remision_preparaciones where ruta = p_ruta and autor = p_email) then
    perform tecnica.f_error('Tome de nuevo la foto de la remisión');
  end if;
  select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_b, v_m from storage.objects o where o.bucket_id = 'tecnica-evidencias' and o.name = p_ruta;
  if not found then perform tecnica.f_error('La foto de la remisión no terminó de subir: intente de nuevo'); end if;
  if v_m is distinct from 'image/jpeg' then perform tecnica.f_error('La foto de la remisión debe ser una imagen JPEG'); end if;
  if v_b > tecnica.f_qparam('max_bytes_remision') then perform tecnica.f_error('La foto de la remisión pasa del tamaño permitido'); end if;
  return v_b;
end $$;

create function public.geoportal_tec_quimico_remision_preparar(p_solicitante text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'entrada_quimicos'); v_ruta text;
begin
  v_ruta := 'remisiones/' || to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM') || '/' || gen_random_uuid() || '.jpg';
  insert into tecnica.quimico_remision_preparaciones (ruta, autor) values (v_ruta, v_email);
  return jsonb_build_object('ruta', v_ruta, 'max_bytes', tecnica.f_qparam('max_bytes_remision'), 'tipo_mime', 'image/jpeg');
end $$;

-- Los que se editan desde la pantalla (los tamaños máximos de archivos no: dependen del bucket).
create function tecnica.f_qparam_editable(p_clave text) returns boolean language sql immutable set search_path = pg_catalog as $$
  select p_clave in ('desvio_pct', 'marca_esperado_usado', 'dias_atras_uso', 'dias_atras_entrada') $$;

create function public.geoportal_tec_quimico_parametros(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante);
begin
  return jsonb_build_object('parametros', coalesce((
    select jsonb_agg(jsonb_build_object('clave', p.clave, 'valor', p.valor, 'minimo', p.minimo, 'maximo', p.maximo, 'descripcion', p.descripcion,
             'ultimo', (select jsonb_build_object('antes', e.antes, 'despues', e.despues, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en)
                          from tecnica.quimico_parametro_eventos e where e.clave = p.clave order by e.id desc limit 1))
           order by case p.clave when 'desvio_pct' then 1 when 'marca_esperado_usado' then 2 when 'dias_atras_uso' then 3 else 4 end)
      from tecnica.quimico_parametros p where tecnica.f_qparam_editable(p.clave)), '[]'::jsonb));
end $$;

create function public.geoportal_tec_quimico_parametro_fijar(p_solicitante text, p_clave text, p_valor numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); p tecnica.quimico_parametros%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if not coalesce(tecnica.f_qparam_editable(p_clave), false) then perform tecnica.f_error('Ese parámetro no se cambia desde la pantalla'); end if;
  select * into p from tecnica.quimico_parametros where clave = p_clave for update;
  if not found then perform tecnica.f_error('Ese parámetro no existe', 'P0002'); end if;
  if p_valor is null or p_valor < p.minimo or p_valor > p.maximo then perform tecnica.f_error(format('El valor debe estar entre %s y %s', p.minimo, p.maximo)); end if;
  if p.clave in ('marca_esperado_usado', 'dias_atras_uso', 'dias_atras_entrada') and p_valor <> floor(p_valor) then perform tecnica.f_error('Ese parámetro es un número entero'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  if p_valor = p.valor then perform tecnica.f_error('El parámetro ya tiene ese valor'); end if;
  insert into tecnica.quimico_parametro_eventos (clave, antes, despues, motivo, autor) values (p.clave, p.valor, p_valor, v_mot, v_email);
  update tecnica.quimico_parametros set valor = p_valor where clave = p.clave;
  perform tecnica.f_auditar(v_email, 'tec_quimico_parametro', p.clave, jsonb_build_object('antes', p.valor, 'despues', p_valor), null);
  return jsonb_build_object('clave', p.clave, 'antes', p.valor, 'valor', p_valor);
end $$;
