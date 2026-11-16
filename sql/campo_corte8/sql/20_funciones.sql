-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 20 — FUNCIONES
--   · campo.f_tipo_general: «Reportar anomalía» = los tipos que NO son formato de actividad (la misma regla de la pantalla y de campo.f_formularios_personal).
--   · campo.f_tecnica_claves: qué formularios compartidos tiene la persona en Técnica (lo decide tecnica.f_autorizar_captura, sin copiar su lógica).
--   · campo.f_tecnica_entrar: autoriza la entrada desde Técnica para un tipo y pone la marca de la transacción.
--   · 3 RPC nuevas que llama la MISMA Edge geoportal-campo cuando la pantalla se abre desde Técnica (?area=tecnica): formulario, preparar la subida y crear.
--     Cada una autoriza por Técnica y llama a la RPC de campo de siempre, en la misma transacción. El reporte queda en campo.reportes con area = 'tecnica'.
--   · ⚠ campo.f_autorizar_reporte: una condición más (la marca). Sin la marca se comporta exactamente como antes.
--   · tecnica.f_formularios: los dos formularios compartidos, para asignarlos en Personal y que salgan en el inicio de Técnica.
-- =====================================================================
create function campo.f_tipo_general(p_codigo text) returns boolean
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select exists (select 1 from campo.tipos_reporte t
                  where t.codigo = p_codigo
                    and not (exists (select 1 from campo.tipo_campos c where c.tipo_id = t.id and c.activo) or exists (select 1 from campo.tipo_fotos f where f.tipo_id = t.id and f.activo)
                             or t.genera_resultado or t.prefijo_consecutivo is not null)) $$;

create function campo.f_tecnica_claves(p_solicitante text) returns text[]
language plpgsql security definer set search_path to 'public', 'campo', 'tecnica', 'pg_temp' as $$
declare v text[] := '{}'; k text;
begin
  foreach k in array array['anomalia_compartida', 'revision_compartida'] loop
    begin
      perform tecnica.f_autorizar_captura(p_solicitante, k);
      v := v || k;
    exception when insufficient_privilege then null;      -- no tiene ese formulario: se sigue con el otro
    end;
  end loop;
  return v;
end $$;

-- Autoriza por Técnica el tipo pedido (nulo = el reporte general) y pone la marca. Devuelve el correo. Cada RPC apaga la marca al volver de la RPC de campo.
create function campo.f_tecnica_entrar(p_solicitante text, p_tipo text) returns text
language plpgsql security definer set search_path to 'public', 'campo', 'tecnica', 'pg_temp' as $$
declare v_email text; v_clave text;
begin
  v_clave := case when p_tipo = 'revision_previa' then 'revision_compartida'
                  when p_tipo is null or campo.f_tipo_general(p_tipo) then 'anomalia_compartida' end;
  if v_clave is null then raise exception 'Ese formato no se llena desde Técnica' using errcode = '42501'; end if;
  v_email := tecnica.f_autorizar_captura(p_solicitante, v_clave);
  perform set_config('geoportal.via_tecnica', 'on', true);      -- solo dura esta transacción; solo la ponen estas funciones (nadie de la API las ejecuta salvo la Edge)
  return v_email;
end $$;

-- El formulario, como lo ve un reportante, solo con lo que la persona tiene en Técnica: los tipos del reporte general y/o «Revisiones generales».
create function public.geoportal_campo_tec_formulario(p_solicitante text) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'tecnica', 'pg_temp' as $$
declare v_claves text[] := campo.f_tecnica_claves(p_solicitante); v jsonb;
begin
  if cardinality(v_claves) = 0 then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  perform set_config('geoportal.via_tecnica', 'on', true);
  v := public.geoportal_campo_obtener_formulario(p_solicitante, false);
  perform set_config('geoportal.via_tecnica', '', true);      -- la marca se apaga en cuanto vuelve la RPC de campo
  return jsonb_build_object(
    'perfil', 'reportante', 'area', 'tecnica', 'formularios', to_jsonb(v_claves),
    'puede', jsonb_build_object('reportar', true, 'crear_desde_escritorio', false, 'supervisar', false, 'administrar_catalogo', false),
    'limites', v -> 'limites', 'zona', v -> 'zona',
    'estados', null, 'causales', null, 'definiciones', null, 'parametros', null,
    'grupos', coalesce((
      select jsonb_agg(g.j || jsonb_build_object('tipos', g.tipos) order by g.n)
        from (select x.j - 'tipos' as j, x.n,
                     (select jsonb_agg(t.j order by t.n) from jsonb_array_elements(x.j -> 'tipos') with ordinality t(j, n)
                       where ('anomalia_compartida' = any (v_claves) and campo.f_tipo_general(t.j ->> 'codigo'))
                          or ('revision_compartida' = any (v_claves) and t.j ->> 'codigo' = 'revision_previa')) as tipos
                from jsonb_array_elements(v -> 'grupos') with ordinality x(j, n)) g
       where g.tipos is not null), '[]'::jsonb));
end $$;

create function public.geoportal_campo_tec_preparar_subida(p_solicitante text, p_cantidad integer, p_ip text default null, p_tipo text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'tecnica', 'pg_temp' as $$
declare v jsonb;
begin
  perform campo.f_tecnica_entrar(p_solicitante, p_tipo);
  v := public.geoportal_campo_preparar_subida(p_solicitante, p_cantidad, 'campo', p_ip, p_tipo);
  perform set_config('geoportal.via_tecnica', '', true);
  return v;
end $$;

-- Mismos datos que el crear de campo (sin «origen»: desde Técnica siempre es captura en campo; sin orden de trabajo: las órdenes son de Comercial).
create function public.geoportal_campo_tec_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text,
  p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_fotos jsonb,
  p_ip text default null, p_datos jsonb default null, p_resultado text default null, p_causal text default null, p_inicio_dispositivo timestamptz default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'tecnica', 'pg_temp' as $$
declare v jsonb;
begin
  if p_tipo is null then raise exception 'Falta el tipo de reporte' using errcode = '22023'; end if;
  perform campo.f_tecnica_entrar(p_solicitante, p_tipo);
  v := public.geoportal_campo_crear_reporte(p_solicitante, p_id, p_tipo, p_subtipo, p_descripcion, p_contrato, p_lat, p_lon, p_precision_m, p_riesgo_inmediato, 'campo', p_fotos,
                                            p_ip, p_datos, p_resultado, p_causal, null, p_inicio_dispositivo);
  perform set_config('geoportal.via_tecnica', '', true);
  return v || jsonb_build_object('area', 'tecnica');
end $$;
