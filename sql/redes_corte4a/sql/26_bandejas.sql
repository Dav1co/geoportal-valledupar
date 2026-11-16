-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 26 — RPC NUEVAS DEL DASHBOARD DISTRIBUCIÓN: perfil del usuario, daños y fallas (lista, ocultar, reincluir, reabrir,
-- nombre del tercero con lectura auditada), intervenciones (ocultar, reincluir, anular), reportes del bot (lista) y crear el activo desde la bandeja.
-- PROPUESTA. No se ha ejecutado en la base real. Todas security definer, search_path fijo, mensajes con HINT msg_usuario; solo service_role.
-- Supervisión = administrador o supervisor de distribución (redes.f_supervisor sobre el perfil de 24). Nada se borra: todo es un evento con motivo.
-- =====================================================================

-- ---------- El perfil de redes de quien entra (para mostrar el Dashboard distribución) ----------
create function public.geoportal_redes_mi_perfil(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  return jsonb_build_object('perfil', p.perfil, 'dashboard_redes', p.perfil in ('admin', 'supervisor'), 'dashboard_ptap', public.geoportal_puede(p.email, 'dashboard_tecnico'));
end $f$;

-- ---------- Daños y fallas ----------
create function public.geoportal_redes_danos(p_solicitante text, p_filtro text default 'abiertos', p_limite integer default 100)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 've la lista de daños y fallas'); v_lim integer := coalesce(p_limite, 100);
begin
  if coalesce(p_filtro, '') not in ('abiertos', 'todos', 'ocultos', 'no_identificados') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_lim < 1 or v_lim > 300 then perform tecnica.f_error('Se piden de 1 a 300'); end if;
  return jsonb_build_object('filtro', p_filtro, 'danos', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'clase', x.clase, 'tipo', x.tipo_nombre, 'sistema', x.sistema, 'activo', x.activo_codigo, 'no_identificado', x.no_ident_que_es,
             'estado', x.estado, 't_detectado', x.t_detectado, 'riesgo', x.riesgo, 'causa_clase', x.causa_clase, 'sector', x.sector_num, 'origen', x.origen, 'autor', x.autor,
             'total_s', x.total_s, 'fotos', x.fotos, 'intervenciones', x.itv, 'tiene_tercero', x.tercero) order by x.t_detectado desc)
      from (select d.*, n.sector_num,
                   (select count(*) from redes.dano_fotos f where f.dano_id = d.id) as fotos,
                   (select count(*) from redes.intervenciones i where i.dano_id = d.id) as itv,
                   exists (select 1 from redes.dano_datos_sensibles s where s.dano_id = d.id) as tercero
              from redes.v_dano d join redes.danos n on n.id = d.id
             where case p_filtro when 'abiertos' then d.estado in ('reportado', 'en_atencion') when 'ocultos' then d.estado = 'oculto'
                                 when 'no_identificados' then d.activo_id is null and d.estado <> 'oculto' else true end
             order by d.t_detectado desc limit v_lim) x), '[]'::jsonb));
end $f$;

-- Ocultar (con motivo, p. ej. un dato de prueba), reincluir o reabrir un daño. Solo eventos: el daño no se cambia ni se borra.
create function public.geoportal_redes_dano_evento(p_solicitante text, p_codigo text, p_tipo text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ocultan, reincluyen o reabren daños'); d redes.v_dano%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if coalesce(p_tipo, '') not in ('ocultar', 'reincluir', 'reabrir') then perform tecnica.f_error('Esa acción no existe'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.dano.' || upper(btrim(coalesce(p_codigo, '')))));
  select * into d from redes.v_dano where codigo = upper(btrim(coalesce(p_codigo, '')));
  if not found then perform tecnica.f_error('No existe ese daño', 'P0002'); end if;
  if p_tipo = 'ocultar' and d.estado = 'oculto' then perform tecnica.f_error('Ese daño ya está oculto'); end if;
  if p_tipo = 'reincluir' and d.estado <> 'oculto' then perform tecnica.f_error('Ese daño no está oculto'); end if;
  if p_tipo = 'reabrir' and d.estado <> 'atendido' then perform tecnica.f_error('Solo se reabre un daño atendido'); end if;
  insert into redes.dano_eventos (dano_id, tipo, motivo, autor) values (d.id, p_tipo, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_dano_' || p_tipo, d.codigo, jsonb_build_object('motivo', v_mot), null);
  return jsonb_build_object('codigo', d.codigo, 'estado', (select estado from redes.v_dano where id = d.id));
end $f$;

-- El nombre o la placa del tercero que causó el daño (D-26): dato personal. Lo leen el supervisor de distribución y el administrador (§ respuesta 3 al
-- Corte 2), y cada lectura queda auditada (quién, cuándo y de qué daño; nunca el valor).
create function public.geoportal_redes_dano_tercero(p_solicitante text, p_codigo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el nombre o la placa del tercero'); v_id uuid; v_cod text; v_nom text;
begin
  select id, codigo into v_id, v_cod from redes.danos where codigo = upper(btrim(coalesce(p_codigo, '')));
  if v_id is null then perform tecnica.f_error('No existe ese daño', 'P0002'); end if;
  select tercero_nombre into v_nom from redes.dano_datos_sensibles where dano_id = v_id;
  if v_nom is null then perform tecnica.f_error('Ese daño no tiene nombre ni placa del tercero', 'P0002'); end if;
  perform tecnica.f_auditar(v_email, 'redes_ver_tercero', v_cod, '{}'::jsonb, null);
  return jsonb_build_object('codigo', v_cod, 'tercero', v_nom);
end $f$;

-- ---------- Intervenciones: ocultar (p. ej. de prueba), reincluir o anular, con motivo ----------
create function public.geoportal_redes_intervencion_evento(p_solicitante text, p_codigo text, p_tipo text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ocultan, reincluyen o anulan intervenciones'); i redes.v_intervencion%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if coalesce(p_tipo, '') not in ('ocultar', 'reincluir', 'anulada') then perform tecnica.f_error('Esa acción no existe'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.itv.' || upper(btrim(coalesce(p_codigo, '')))));
  select * into i from redes.v_intervencion where codigo = upper(btrim(coalesce(p_codigo, '')));
  if not found then perform tecnica.f_error('No existe esa intervención', 'P0002'); end if;
  if p_tipo = 'ocultar' and i.estado = 'oculta' then perform tecnica.f_error('Esa intervención ya está oculta'); end if;
  if p_tipo = 'reincluir' and i.estado <> 'oculta' then perform tecnica.f_error('Esa intervención no está oculta'); end if;
  if p_tipo = 'anulada' and i.estado <> 'cerrada' then perform tecnica.f_error('Solo se anula una intervención cerrada'); end if;
  insert into redes.intervencion_eventos (intervencion_id, tipo, motivo, autor) values (i.id, p_tipo, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_intervencion_' || p_tipo, i.codigo, jsonb_build_object('motivo', v_mot), null);
  return jsonb_build_object('codigo', i.codigo, 'estado', (select estado from redes.v_intervencion where id = i.id),
                            'aviso', case when p_tipo = 'anulada' and i.dano_codigo is not null and i.resuelve_dano
                                          then format('El daño %s sigue atendido: si debe volver a quedar abierto, reábralo en «Daños y fallas».', i.dano_codigo) end);
end $f$;

-- ---------- Reportes del bot (N-14): la bandeja. Convertir y descartar ya existen (Corte 2). ----------
create function public.geoportal_redes_reportes_bot(p_solicitante text, p_filtro text default 'pendientes', p_limite integer default 100)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven los reportes del bot'); v_lim integer := coalesce(p_limite, 100);
begin
  if coalesce(p_filtro, '') not in ('pendientes', 'todos') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_lim < 1 or v_lim > 300 then perform tecnica.f_error('Se piden de 1 a 300'); end if;
  return jsonb_build_object('filtro', p_filtro, 'reportes', coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'radicado', r.radicado, 'canal', r.canal, 'tipo', r.tipo_bot, 'lat', r.lat, 'lon', r.lon, 'direccion', r.direccion,
             'descripcion', r.descripcion, 'recibido_en', r.recibido_en, 'estado_bot', r.estado_bot, 'dano', r.dano_codigo, 'fotos', r.fotos) order by r.recibido_en desc)
      from (select * from redes.v_reporte_externo x where p_filtro = 'todos' or x.ultimo_evento = 'recibido' order by x.recibido_en desc limit v_lim) r), '[]'::jsonb));
end $f$;

-- ---------- Bandeja de no identificados: CREAR el activo (respuesta 4 de David al 3a) y asociarlo ----------
-- Solo tipos de PUNTO (válvula, hidrante, pozo, sumidero…), en el punto del registro. Un tramo nuevo se dibuja en el Cargue de capas (Corte 5).
-- El activo nace «por verificar», con origen EMDUPAR por omisión (el administrador lo corrige en la ficha si es de un tercero).
create function public.geoportal_redes_crear_activo_bandeja(p_solicitante text, p_clase text, p_ref text, p_prefijo text, p_clase_activo text, p_nombre text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare
  v_email text := redes.f_supervisor(p_solicitante, 'crean activos desde la bandeja'); v_id uuid; v_sis text; v_actual bigint; v_lat numeric; v_lon numeric;
  t redes.v_tipo_visible%rowtype; v_mot text := btrim(coalesce(p_motivo, '')); v_nom text := nullif(btrim(coalesce(p_nombre, '')), ''); v_cl text := nullif(p_clase_activo, '');
  v_cons bigint; v_cod text; v_act bigint; v_geom geometry; v_ref text := upper(btrim(coalesce(p_ref, '')));
begin
  if coalesce(p_clase, '') not in ('intervencion', 'dano') then perform tecnica.f_error('Diga si es una intervención o un daño'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  if v_nom is not null and length(v_nom) > 120 then perform tecnica.f_error('El nombre admite hasta 120 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.asociar.' || v_ref));
  if p_clase = 'intervencion' then
    select id, sistema, activo_id, lat, lon into v_id, v_sis, v_actual, v_lat, v_lon from redes.v_intervencion where codigo = v_ref and estado <> 'oculta';
  else
    select id, sistema, activo_id, lat, lon into v_id, v_sis, v_actual, v_lat, v_lon from redes.v_dano where codigo = v_ref and estado <> 'oculto';
  end if;
  if v_id is null then perform tecnica.f_error('No existe ese registro (o está oculto)', 'P0002'); end if;
  if v_actual is not null then perform tecnica.f_error('Ese registro ya tiene activo'); end if;
  select * into t from redes.v_tipo_visible where prefijo = upper(coalesce(p_prefijo, '')) and sistema = v_sis;
  if not found then perform tecnica.f_error('Elija un tipo de activo del mismo sistema'); end if;
  if t.geometria <> 'punto' then perform tecnica.f_error('Un tramo nuevo se dibuja en el Cargue de capas: por ahora asocie el registro a un tramo existente'); end if;
  if v_cl is not null and not exists (select 1 from redes.clases_activo where prefijo = t.prefijo and codigo = v_cl) then perform tecnica.f_error('Esa clase no existe para el tipo elegido'); end if;
  if v_cl is null and exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean) then
    perform tecnica.f_error(format('Elija la clase del activo (%s)', t.nombre_visible));
  end if;
  if v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
    perform tecnica.f_error('El registro está fuera de Valledupar: no se crea el activo ahí');
  end if;
  v_geom := ST_SetSRID(ST_MakePoint(v_lon::double precision, v_lat::double precision), 4326);
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = t.prefijo returning ultimo into v_cons;
  v_cod := t.prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, t.prefijo, 'asociacion', v_email) returning id into v_act;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, estado_codigo, atributos, huella, autor)
  values (v_act, 1, v_geom, v_nom, v_cl, 'en_operacion', jsonb_build_object('creado_desde', v_ref),
          redes.f_huella(v_geom, jsonb_build_object('p', t.prefijo, 'n', v_nom, 'c', v_cl, 'e', null, 'm', null, 'd', null, 'l', null, 'pr', null, 'ca', null, 's', 'en_operacion',
                                                     'ant', null, 'a', jsonb_build_object('creado_desde', v_ref))), v_email);
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (v_act, 'por_verificar', left(format('Creado desde la bandeja de no identificados (%s): %s', v_ref, v_mot), 1000), v_email);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_act, 1, 'emdupar', 'Creado desde la bandeja; origen por confirmar', v_email);
  perform redes.f_mat_refrescar_uno(v_act);
  perform redes.f_subir_tesela(v_sis);
  if p_clase = 'intervencion' then
    insert into redes.intervencion_eventos (intervencion_id, tipo, activo_id, motivo, autor) values (v_id, 'crear_activo', v_act, v_mot, v_email);
    insert into redes.intervencion_eventos (intervencion_id, tipo, activo_id, motivo, autor) values (v_id, 'asociar_activo', v_act, v_mot, v_email);
  else
    insert into redes.dano_eventos (dano_id, tipo, activo_id, motivo, autor) values (v_id, 'asociar_activo', v_act, v_mot, v_email);
  end if;
  perform tecnica.f_auditar(v_email, 'redes_crear_activo_bandeja', v_ref, jsonb_build_object('clase', p_clase, 'activo', v_cod), null);
  return jsonb_build_object('clase', p_clase, 'codigo', v_ref, 'activo', v_cod, 'por_verificar', true);
end $f$;
