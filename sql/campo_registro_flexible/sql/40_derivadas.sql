-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 40 — «AVISOS Y ACTIVIDADES DERIVADAS»: conteo de pendientes y descarga auditada (agregado del encargo, 25-nov 21:10)
-- campo.f_derivadas_filtradas(filtros): los ids de las derivadas que cumplen los filtros de la lista (estado, contrato, actividad, desde, hasta, origen), validados
--   igual que hoy. La usan la lista y la descarga, así que las dos filtran lo mismo.
-- geoportal_campo_derivadas: además de las filas, «total» (con los filtros) y «pendientes» (con los filtros, menos el de estado). Antes la pantalla veía «100+».
-- Descarga auditada, como la de Reportes: iniciar (cuenta y fija el corte, deja la auditoría), pagina (hasta 5.000 filas por página, por id) y cerrar.
--   SIN datos de contacto (aviso_datos nunca se lee aquí: f_derivada_json solo dice trae_datos y cuántas entregas) y sin texto libre (observación, dirección
--   correcta, motivo de cierre); los correos de las personas (quien registró, quien cerró, quien lo vio otra vez) solo para el administrador que lo pide.
-- Mismo permiso que la lista: campo.f_autorizar_registradas (administrador, supervisor de actas o de campo).
-- =====================================================================
create function campo.f_derivadas_filtradas(p_filtros jsonb)
 returns table (id bigint)
 language plpgsql
 stable security definer
 set search_path to 'campo', 'pg_temp'
as $function$
declare f jsonb := coalesce(p_filtros, '{}'::jsonb); v_est text; v_con text; v_act text; v_desde date; v_hasta date; v_ori text;
begin
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_est := nullif(f ->> 'estado', ''); v_con := nullif(btrim(coalesce(f ->> 'contrato', '')), ''); v_act := nullif(f ->> 'actividad', '');
    v_desde := nullif(f ->> 'desde', '')::date; v_hasta := nullif(f ->> 'hasta', '')::date; v_ori := nullif(f ->> 'origen', '');
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  if v_est is not null and v_est not in ('pendiente', 'atendida', 'atendida_fuera', 'anulada') then perform campo.f_error('El estado no es válido'); end if;
  if v_ori is not null and v_ori not in ('registro', 'analisis') then perform campo.f_error('El origen no es válido'); end if;
  return query
    select d.id from campo.derivadas d
     where (v_est is null or campo.f_derivada_estado(d.id) = v_est) and (v_con is null or d.contrato = v_con) and (v_act is null or d.actividad = v_act)
       and (v_ori is null or (v_ori = 'registro' and d.origen_id is not null) or (v_ori = 'analisis' and d.observacion_id is not null))
       and (v_desde is null or (d.creado_en at time zone 'America/Bogota')::date >= v_desde) and (v_hasta is null or (d.creado_en at time zone 'America/Bogota')::date <= v_hasta);
end $function$;
revoke all on function campo.f_derivadas_filtradas(jsonb) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivadas(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_antes bigint; v_lim integer; v_filas jsonb; v_n integer; v_total integer; v_pend integer;
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_antes := nullif(f ->> 'antes', '')::bigint;
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 50), 1), 200);
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  -- Registro flexible (25-nov, agregado de David): el total y los pendientes, con los mismos filtros (los pendientes, sin el filtro de estado)
  select count(*)::integer into v_total from campo.f_derivadas_filtradas(f - 'antes' - 'limite');
  select count(*)::integer into v_pend from campo.f_derivadas_filtradas((f - 'antes' - 'limite') || '{"estado": "pendiente"}'::jsonb);
  select count(*), coalesce(jsonb_agg(campo.f_derivada_json(x.id) order by x.id desc) filter (where x.rn <= v_lim), '[]'::jsonb) into v_n, v_filas
    from (select q.id, row_number() over (order by q.id desc) as rn from campo.f_derivadas_filtradas(f - 'antes' - 'limite') q
           where v_antes is null or q.id < v_antes order by q.id desc limit v_lim + 1) x;
  return jsonb_build_object('filas', v_filas, 'siguiente', case when v_n > v_lim then (select min((e ->> 'id')::bigint) from jsonb_array_elements(v_filas) e) end,
                            'total', v_total, 'pendientes', v_pend);
end $function$;

-- Una fila de f_derivada_json para la DESCARGA: nunca el texto libre (la observación escrita, la dirección correcta ni el motivo de cierre, que pueden traer datos de
-- personas); los correos de las personas (quien originó, quien cerró, quien lo vio otra vez) solo si p_con_correos (el administrador que los pidió).
create function campo.f_derivada_descarga(p jsonb, p_con_correos boolean)
 returns jsonb
 language sql
 immutable
 set search_path to 'pg_catalog'
as $function$
  select case when p_con_correos then x else x #- '{origen,operario}' #- '{cierre,autor}' #- '{origen,ultimo_visto,autor}' end
    from (select p #- '{origen,texto}' #- '{origen,direccion_correcta}' #- '{cierre,motivo}' as x) s
$function$;
revoke all on function campo.f_derivada_descarga(jsonb, boolean) from public, anon, authenticated, service_role;

create function public.geoportal_campo_derivadas_descarga_iniciar(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_formato text DEFAULT 'xlsx'::text,
                                                                  p_incluir_autor boolean DEFAULT false, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v_f jsonb := coalesce(p_filtros, '{}'::jsonb) - 'antes' - 'limite'; v_formato text := lower(btrim(coalesce(p_formato, '')));
        v_total bigint; v_corte bigint; v_id bigint; v_autor boolean := coalesce(p_incluir_autor, false);
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if v_formato not in ('csv', 'xlsx') then perform campo.f_error('El formato debe ser Excel o CSV'); end if;
  if v_autor and campo.f_perfil(v_email) is distinct from 'admin' then perform campo.f_error('Solo el administrador puede incluir los correos de las personas', '42501'); end if;
  if jsonb_typeof(v_f) <> 'object' then perform campo.f_error('Los filtros no son válidos'); end if;
  select count(*), max(x.id) into v_total, v_corte from campo.f_derivadas_filtradas(v_f) x;
  if v_total = 0 then perform campo.f_error('No hay avisos ni actividades con esos filtros'); end if;
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
  values (v_email, 'campo_derivadas_descarga_iniciar', v_formato, jsonb_build_object('filtros', v_f, 'incluir_autor', v_autor, 'filas_esperadas', v_total, 'hasta_id', v_corte), p_ip)
  returning id into v_id;
  return jsonb_build_object('descarga_id', v_id, 'total', v_total, 'formato', v_formato, 'filtros', v_f, 'incluir_autor', v_autor, 'hasta_id', v_corte,
                            'generado_por', v_email, 'generado_en', to_char(campo.f_ahora_bogota(), 'DD/MM/YYYY HH24:MI'));
end $function$;

create function public.geoportal_campo_derivadas_descarga_pagina(p_solicitante text, p_descarga_id bigint, p_despues_de bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; a record; v_f jsonb; v_corte bigint; v_autor boolean; v_lim integer := least(greatest(coalesce(p_limite, 5000), 1), 5000); v_rows jsonb; v_min bigint; v_n integer;
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  select x.id, x.email, x.detalle into a from public.geoportal_auditoria x where x.id = p_descarga_id and x.accion = 'campo_derivadas_descarga_iniciar';
  if not found or a.email <> v_email then perform campo.f_error('La descarga no existe', 'P0002'); end if;
  if exists (select 1 from public.geoportal_auditoria x where x.accion = 'campo_derivadas_descarga_cerrar' and x.referencia = p_descarga_id::text) then
    perform campo.f_error('La descarga ya se cerró', '55000');
  end if;
  v_f := a.detalle -> 'filtros'; v_corte := (a.detalle ->> 'hasta_id')::bigint; v_autor := coalesce((a.detalle ->> 'incluir_autor')::boolean, false);
  select count(*), coalesce(jsonb_agg(campo.f_derivada_descarga(campo.f_derivada_json(q.id), v_autor) order by q.id desc)
                                      filter (where q.rn <= v_lim), '[]'::jsonb), min(q.id) filter (where q.rn <= v_lim)
    into v_n, v_rows, v_min
    from (select x.id, row_number() over (order by x.id desc) as rn from campo.f_derivadas_filtradas(v_f) x
           where x.id <= v_corte and (p_despues_de is null or x.id < p_despues_de) order by x.id desc limit v_lim + 1) q;
  return jsonb_build_object('registros', v_rows, 'devueltos', jsonb_array_length(v_rows), 'ultimo_id', v_min, 'hay_mas', v_n > v_lim);
end $function$;

create function public.geoportal_campo_derivadas_descarga_cerrar(p_solicitante text, p_descarga_id bigint, p_filas integer, p_resultado text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; a record; v_res text := lower(btrim(coalesce(p_resultado, '')));
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if v_res not in ('completa', 'cancelada', 'error') then perform campo.f_error('El resultado debe ser completa, cancelada o error'); end if;
  if p_filas is null or p_filas < 0 then perform campo.f_error('El número de filas no es válido'); end if;
  select x.id, x.email, x.detalle into a from public.geoportal_auditoria x where x.id = p_descarga_id and x.accion = 'campo_derivadas_descarga_iniciar';
  if not found or a.email <> v_email then perform campo.f_error('La descarga no existe', 'P0002'); end if;
  if exists (select 1 from public.geoportal_auditoria x where x.accion = 'campo_derivadas_descarga_cerrar' and x.referencia = p_descarga_id::text) then
    return jsonb_build_object('cerrada', true, 'repetida', true);
  end if;
  perform campo.f_auditar(v_email, 'campo_derivadas_descarga_cerrar', p_descarga_id::text,
                          jsonb_build_object('filas', p_filas, 'resultado', v_res, 'filas_esperadas', a.detalle -> 'filas_esperadas'), p_ip);
  return jsonb_build_object('cerrada', true, 'repetida', false);
end $function$;

revoke all on function public.geoportal_campo_derivadas_descarga_iniciar(text, jsonb, text, boolean, text), public.geoportal_campo_derivadas_descarga_pagina(text, bigint, bigint, integer),
                       public.geoportal_campo_derivadas_descarga_cerrar(text, bigint, integer, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_derivadas_descarga_iniciar(text, jsonb, text, boolean, text), public.geoportal_campo_derivadas_descarga_pagina(text, bigint, bigint, integer),
                          public.geoportal_campo_derivadas_descarga_cerrar(text, bigint, integer, text, text)
  to service_role;
