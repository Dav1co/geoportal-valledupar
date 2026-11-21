-- =====================================================================
-- 26 — RPC de los reportes del PTAP (solo supervisor de planta y administrador: tecnica.f_autorizar_supervision). Solo service_role las ejecuta (la Edge).
--   iniciar → valida, cuenta, guarda la descarga (con la foto de las columnas y el instante) y la deja en la auditoría;
--   pagina  → entrega hasta 5.000 filas con los filtros GUARDADOS, solo lo que existía al iniciar; vence a las 2 horas y no sirve a otra persona;
--   cerrar  → guarda el cierre (una vez) y lo deja en la auditoría;
--   remision_foto → la ruta de la foto de la remisión de una entrada de químicos (la Edge la firma por 60 s); queda en la auditoría.
-- =====================================================================
create function public.geoportal_tec_reporte_iniciar(p_solicitante text, p_reporte text, p_filtros jsonb default '{}'::jsonb, p_formato text default 'xlsx',
                                                     p_incluir_excluidos boolean default false, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text; v_rep text := lower(btrim(coalesce(p_reporte, ''))); v_formato text := lower(btrim(coalesce(p_formato, ''))); c record;
  v_f jsonb; v_incl boolean; v_corte timestamptz := clock_timestamp(); v_cols jsonb; v_plantilla jsonb; v_total bigint; v_max integer := tecnica.f_rep_max_filas(); v_id bigint;
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  select * into c from tecnica.f_rep_catalogo() x where x.clave = v_rep;
  if not found then perform tecnica.f_error('Ese reporte no existe.'); end if;
  if v_formato not in ('csv', 'xlsx') then perform tecnica.f_error('El formato debe ser Excel o CSV.'); end if;
  v_f := tecnica.f_rep_filtros(v_rep, p_filtros);
  v_incl := coalesce(p_incluir_excluidos, false) and c.usa_excluidos;
  v_cols := tecnica.f_rep_columnas(v_rep, v_f);
  select jsonb_object_agg(x ->> 'clave', 'null'::jsonb) into v_plantilla from jsonb_array_elements(v_cols) x;
  select count(*) into v_total from tecnica.f_rep_filas(v_rep, v_f, v_incl, v_corte, null, null, v_plantilla, true);
  if v_total = 0 then perform tecnica.f_error('No hay datos con esos filtros.', 'P0002'); end if;
  if v_total > v_max then
    perform tecnica.f_error('La descarga supera el máximo de ' || replace(to_char(v_max, 'FM999G999'), ',', '.') || ' filas (hay '
                            || replace(to_char(v_total, 'FM999G999G999'), ',', '.') || '). Acote el periodo o los filtros.');
  end if;
  insert into tecnica.reporte_descargas (email, reporte, filtros, incluir, formato, columnas, total, corte_en, ip)
  values (v_email, v_rep, v_f, v_incl, v_formato, v_cols, v_total, v_corte, p_ip) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_reporte_iniciar', v_id::text,
                            jsonb_build_object('reporte', v_rep, 'filtros', v_f, 'incluir_excluidos', v_incl, 'formato', v_formato, 'filas', v_total), p_ip);
  return jsonb_build_object('descarga_id', v_id, 'reporte', v_rep, 'titulo', c.titulo,
                            'archivo', 'ptap_' || v_rep || '_' || (v_f ->> 'desde') || '_a_' || (v_f ->> 'hasta'),
                            'total', v_total, 'max', v_max, 'formato', v_formato, 'incluir_excluidos', v_incl,
                            'filtros', v_f - 'planta_nombre' - 'punto_nombre' - 'quimico_nombre', 'columnas', v_cols,
                            'leame', tecnica.f_rep_leame(v_rep, v_f, v_incl, v_email, v_corte));
end $$;

create function public.geoportal_tec_reporte_pagina(p_solicitante text, p_descarga_id bigint, p_cursor text default null, p_limite integer default 5000) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text; d tecnica.reporte_descargas; v_lim integer := least(greatest(coalesce(p_limite, 5000), 1), tecnica.f_rep_max_pagina());
  v_plantilla jsonb; v_filas jsonb; v_n integer; v_ultimo text;
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  select * into d from tecnica.reporte_descargas x where x.id = p_descarga_id;
  if not found or d.email <> v_email then perform tecnica.f_error('La descarga no existe.', 'P0002'); end if;
  if exists (select 1 from tecnica.reporte_descarga_cierres c where c.descarga_id = d.id) then perform tecnica.f_error('La descarga ya terminó. Vuelva a iniciarla.', '55000'); end if;
  if d.creado_en < clock_timestamp() - interval '2 hours' then perform tecnica.f_error('La descarga venció. Vuelva a iniciarla.', '55000'); end if;
  if p_cursor is not null and (length(p_cursor) > 200 or p_cursor !~ '^[0-9A-Za-z_|-]+$') then perform tecnica.f_error('La página pedida no es válida.'); end if;
  select jsonb_object_agg(x ->> 'clave', 'null'::jsonb) into v_plantilla from jsonb_array_elements(d.columnas) x;
  select coalesce(jsonb_agg(r.fila order by r.k), '[]'::jsonb), count(*), max(r.k) into v_filas, v_n, v_ultimo
    from tecnica.f_rep_filas(d.reporte, d.filtros, d.incluir, d.corte_en, p_cursor, v_lim, v_plantilla) r;
  return jsonb_build_object('filas', v_filas, 'devueltos', v_n, 'cursor', case when v_n = v_lim then v_ultimo end);
end $$;

create function public.geoportal_tec_reporte_cerrar(p_solicitante text, p_descarga_id bigint, p_filas integer default 0, p_resultado text default 'completa', p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text; v_res text := lower(btrim(coalesce(p_resultado, ''))); d tecnica.reporte_descargas; v_n integer;
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  if v_res not in ('completa', 'cancelada', 'error') then perform tecnica.f_error('Resultado de descarga no válido.'); end if;
  if p_filas is null or p_filas < 0 then perform tecnica.f_error('El número de filas no es válido.'); end if;
  select * into d from tecnica.reporte_descargas x where x.id = p_descarga_id;
  if not found or d.email <> v_email then perform tecnica.f_error('La descarga no existe.', 'P0002'); end if;
  insert into tecnica.reporte_descarga_cierres (descarga_id, filas, resultado, ip) values (d.id, p_filas, v_res, p_ip) on conflict (descarga_id) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('descarga_id', d.id, 'cerrada', true, 'repetida', true); end if;
  perform tecnica.f_auditar(v_email, 'tec_reporte_cerrar', d.id::text, jsonb_build_object('reporte', d.reporte, 'filas_entregadas', p_filas, 'resultado', v_res), p_ip);
  return jsonb_build_object('descarga_id', d.id, 'cerrada', true, 'repetida', false);
end $$;

create function public.geoportal_tec_reporte_remision_foto(p_solicitante text, p_movimiento bigint, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text; v_ruta text;
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  select m.remision_foto into v_ruta from tecnica.quimico_movimientos m where m.id = p_movimiento and m.tipo = 'entrada';
  if v_ruta is null then perform tecnica.f_error('Ese movimiento no tiene foto de la remisión.', 'P0002'); end if;
  perform tecnica.f_auditar(v_email, 'tec_reporte_remision_foto', p_movimiento::text, '{}'::jsonb, p_ip);
  return jsonb_build_object('movimiento', p_movimiento, 'ruta', v_ruta);
end $$;
