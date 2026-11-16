begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las 2 RPC como las dejó el 7a, quita las 5 funciones nuevas, las 2 tablas y la columna de la foto. El parámetro max_bytes_remision se queda.
-- SE NIEGA (nada se borra) si ya hay entradas con foto, fotos reservadas o cambios de parámetros.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.quimico_parametro_eventos') is null then raise exception 'No hay nada que revertir: el Corte 7c no está aplicado'; end if;
  if exists (select 1 from tecnica.quimico_parametro_eventos) or exists (select 1 from tecnica.quimico_remision_preparaciones)
     or exists (select 1 from tecnica.quimico_movimientos where remision_foto is not null) then
    raise exception 'Ya hay fotos de remisión o cambios de parámetros: la reversa se niega (nada se borra)';
  end if;
  if (select count(*) from (values ('public.geoportal_tec_quimico_entrada(text,jsonb,text)', 'b98b131b312d3a370d96c288cfb565b0'), ('public.geoportal_tec_quimico_historial(text,text)', '2a02dcc13b3323d3f7b43778d3a8fdac')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2
     or (select count(*) from (values ('tecnica.f_remision_subida(text,text)', '01786c84892a2997a06a4cc70447dcc2'), ('tecnica.f_qparam_editable(text)', '8dd655218813ed42f4e573afc96197dd'), ('public.geoportal_tec_quimico_remision_preparar(text)', '0090d5936af9474875861efb60f7c6cb'), ('public.geoportal_tec_quimico_parametros(text)', '38fa1497fc33537e0f2b7ba682a10684'), ('public.geoportal_tec_quimico_parametro_fijar(text,text,numeric,text)', '73a15eef0783e83d4aeb81f902e77f31')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 5 then
    raise exception 'Las funciones cambiaron después de la migración del Corte 7c: la reversa se niega a pisarlas; avise';
  end if;
end $$;
-- 1. las 2 RPC reemplazadas, con su texto del 7a
CREATE OR REPLACE FUNCTION public.geoportal_tec_quimico_entrada(p_solicitante text, p_datos jsonb, p_clave text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'entrada_quimicos'); d jsonb := coalesce(p_datos, '{}'::jsonb); q tecnica.quimicos; v_id bigint;
        v_cant numeric; v_vence date; m tecnica.quimico_movimientos%rowtype;
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
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, lote_fabricante, vence, autor, clave_envio)
  values ('entrada', q.id, v_cant, d ->> 'unidad', case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end,
          tecnica.f_dia_movimiento((d ->> 'dia')::date, tecnica.f_qparam('dias_atras_entrada')),
          nullif(btrim(d ->> 'proveedor'), ''), nullif(btrim(d ->> 'remision'), ''), nullif(btrim(d ->> 'lote'), ''), v_vence, v_email, p_clave)
  returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_entrada', q.codigo, jsonb_build_object('movimiento_id', v_id), null);
  return jsonb_build_object('movimiento_id', v_id, 'cantidad_kg', case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end, 'repetido', false);
end $function$;
revoke all on function public.geoportal_tec_quimico_entrada(text,jsonb,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_tec_quimico_entrada(text,jsonb,text) to service_role;

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
                                 'proveedor', m.proveedor, 'remision', m.remision, 'lote', m.lote_fabricante, 'vence', m.vence, 'motivo', m.motivo, 'autor', m.autor,
                                 'registrado_en', m.registrado_en) order by m.id desc)
                               from (select * from tecnica.quimico_movimientos m where m.quimico_id = q.id order by m.id desc limit 100) m), '[]'::jsonb));
end $function$;
revoke all on function public.geoportal_tec_quimico_historial(text,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_tec_quimico_historial(text,text) to service_role;

-- 2. lo nuevo
drop function public.geoportal_tec_quimico_parametro_fijar(text, text, numeric, text);
drop function public.geoportal_tec_quimico_parametros(text);
drop function public.geoportal_tec_quimico_remision_preparar(text);
drop function tecnica.f_qparam_editable(text);
drop function tecnica.f_remision_subida(text, text);
drop index tecnica.ux_qmov_remision_foto;
alter table tecnica.quimico_movimientos drop constraint quimico_movimientos_remision_foto_ck;
alter table tecnica.quimico_movimientos drop column remision_foto;      -- vacía: la guardia de arriba lo comprobó
drop table tecnica.quimico_remision_preparaciones;
drop table tecnica.quimico_parametro_eventos;
do $$
begin
  if (select count(*) from (values ('public.geoportal_tec_quimico_entrada(text,jsonb,text)', '9daf6b0ef659b44d30a9260b003e0a31'), ('public.geoportal_tec_quimico_historial(text,text)', '9112d90a773971bacfb9d69310b2da89')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2 then raise exception 'La reversa no dejó las RPC como en el 7a'; end if;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values ('migracion@tecnica_corte7c', 'reversa_tecnica_corte7c', null, '{}'::jsonb, null);
commit;
