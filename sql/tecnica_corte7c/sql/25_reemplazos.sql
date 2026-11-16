-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 7a con cambios exactos, aplicados una sola vez:
--   · geoportal_tec_quimico_entrada: acepta la foto de la remisión (opcional) y la guarda con la entrada;
--   · geoportal_tec_quimico_historial: cada movimiento trae la ruta de su foto (la Edge la cambia por una URL firmada).
-- =====================================================================
-- public.geoportal_tec_quimico_entrada(text,jsonb,text)
CREATE OR REPLACE FUNCTION public.geoportal_tec_quimico_entrada(p_solicitante text, p_datos jsonb, p_clave text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'entrada_quimicos'); d jsonb := coalesce(p_datos, '{}'::jsonb); q tecnica.quimicos; v_id bigint;
        v_cant numeric; v_vence date; m tecnica.quimico_movimientos%rowtype; v_foto text := nullif(btrim(coalesce(p_datos, '{}'::jsonb) ->> 'foto'), '');
begin
  if p_clave is not null then
    select * into m from tecnica.quimico_movimientos where clave_envio = p_clave;
    if found then
      if m.autor <> v_email then perform tecnica.f_error('Esa clave de envío no es suya'); end if;
      return jsonb_build_object('movimiento_id', m.id, 'cantidad_kg', m.cantidad_kg, 'repetido', true);
    end if;
  end if;
  q := tecnica.f_quimico_por_codigo(d ->> 'quimico');
  if not q.activo then perform tecnica.f_error('Ese químico está desactivado'); end if;
  if jsonb_typeof(d -> 'cantidad') <> 'number' then perform tecnica.f_error('Escriba la cantidad recibida'); end if;
  v_cant := (d ->> 'cantidad')::numeric;
  if v_cant <= 0 or v_cant > 1000000 then perform tecnica.f_error('La cantidad recibida debe ser mayor que 0'); end if;
  if coalesce(d ->> 'unidad', '') not in ('t', 'kg') then perform tecnica.f_error('La unidad es toneladas o kg'); end if;
  begin v_vence := (d ->> 'vence')::date; exception when others then perform tecnica.f_error('La fecha de vencimiento no es válida'); end;
  -- Corte 7c: la foto de la remisión es opcional; si viene, debe ser suya, estar subida, ser JPEG y no estar ya en otra entrada
  if v_foto is not null then
    perform tecnica.f_remision_subida(v_foto, v_email);
    if exists (select 1 from tecnica.quimico_movimientos x where x.remision_foto = v_foto) then perform tecnica.f_error('Esa foto ya quedó en otra entrada: tome una nueva'); end if;
  end if;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, lote_fabricante, vence, remision_foto, autor, clave_envio)
  values ('entrada', q.id, v_cant, d ->> 'unidad', case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end,
          tecnica.f_dia_movimiento((d ->> 'dia')::date, tecnica.f_qparam('dias_atras_entrada')),
          nullif(btrim(d ->> 'proveedor'), ''), nullif(btrim(d ->> 'remision'), ''), nullif(btrim(d ->> 'lote'), ''), v_vence, v_foto, v_email, p_clave)
  returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_entrada', q.codigo, jsonb_build_object('movimiento_id', v_id, 'con_foto', v_foto is not null), null);
  return jsonb_build_object('movimiento_id', v_id, 'cantidad_kg', case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end, 'repetido', false);
end $function$;

-- public.geoportal_tec_quimico_historial(text,text)
CREATE OR REPLACE FUNCTION public.geoportal_tec_quimico_historial(p_solicitante text, p_codigo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo);
begin
  return jsonb_build_object('codigo', q.codigo, 'nombre', q.nombre,
    'eventos', coalesce((select jsonb_agg(jsonb_build_object('tipo', e.tipo, 'dosis_optima_ppm', e.dosis_optima_ppm, 'potabilizacion', e.potabilizacion, 'activo', e.activo,
                                 'ficha_ruta', e.ficha_ruta, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en) order by e.id desc)
                           from tecnica.quimico_ficha_eventos e where e.quimico_id = q.id), '[]'::jsonb),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'dia', m.dia, 'cantidad', m.cantidad, 'unidad', m.unidad, 'cantidad_kg', m.cantidad_kg,
                                 'planta', (select p.codigo from tecnica.plantas p where p.id = m.planta_id), 'para_que', m.para_que, 'dosis_optima_ppm', m.dosis_optima_ppm,
                                 'proveedor', m.proveedor, 'remision', m.remision, 'lote', m.lote_fabricante, 'vence', m.vence, 'remision_foto_ruta', m.remision_foto, 'motivo', m.motivo, 'autor', m.autor,
                                 'registrado_en', m.registrado_en) order by m.id desc)
                               from (select * from tecnica.quimico_movimientos m where m.quimico_id = q.id order by m.id desc limit 100) m), '[]'::jsonb));
end $function$;
