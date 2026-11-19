-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 26 — RPC (las llama la Edge geoportal-redes; las pantallas son del Code B)
--   Lectura:  evento_catalogo · evento_vista_previa · eventos_vigentes · eventos · evento
--   Escribe:  evento_declarar · evento_regreso · evento_cerrar · evento_anular · evento_asociar · evento_desasociar · evento_tipo_fijar · planta_sectores_fijar
-- Quién puede cada cosa lo decide redes.f_evento_autorizar. Solo conteos de contratos; la lista de usuarios sensibles (contrato y tipo, sin nombre) solo va
-- en el detalle, a supervisores y administrador. «Quién» es siempre el nombre del funcionario.
-- =====================================================================

-- lo que necesita la pantalla para declarar: sectores, plantas con sus sectores, qué se asocia, límites y qué puede esta persona
create function public.geoportal_redes_evento_catalogo(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'detalle'); v_p record;
begin
  select * into v_p from redes.f_perfil_lectura(v_email);
  return jsonb_build_object(
    'puede', jsonb_build_object('zona', v_p.perfil in ('admin', 'supervisor'), 'reportes', v_p.perfil in ('admin', 'supervisor'),
                                'total', v_p.perfil = 'admin' or public.geoportal_puede(v_email, 'dashboard_tecnico')),
    'limites', jsonb_build_object('radio_min_m', redes.f_param('evento_radio_min_m'), 'radio_max_m', redes.f_param('evento_radio_max_m'),
                                  'sectores_max', redes.f_param('evento_sectores_max'), 'horas_atras_max', redes.f_param('evento_horas_atras_max')),
    'sectores', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', coalesce(nullif(btrim(m.nombre), ''), m.codigo), 'clase', m.clase) order by m.clase, m.nombre, m.codigo)
                            from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto), '[]'::jsonb),
    'plantas', coalesce((select jsonb_agg(jsonb_build_object('codigo', pl.codigo, 'nombre', pl.nombre,
                           'sectores', coalesce((select jsonb_agg(m.codigo order by m.codigo) from redes.planta_sectores ps join redes.activo_vigente_mat m on m.activo_id = ps.sector_id
                                                  where ps.planta_id = pl.id and ps.activo and not m.retirado and not m.oculto), '[]'::jsonb)) order by pl.id)
                           from tecnica.plantas pl where pl.activa), '[]'::jsonb),
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('origen', t.origen, 'codigo', t.codigo, 'nombre', t.nombre, 'clase', t.clase, 'asocia', t.asocia) order by t.origen, t.clase, t.nombre)
                         from redes.evento_tipos_asociables t), '[]'::jsonb));
end $$;

-- antes de declarar: la zona, los contratos, los sensibles confirmados y cuántos reportes ya recibidos quedarían asociados. No guarda nada
create function public.geoportal_redes_evento_vista_previa(p_solicitante text, p jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text; z record; v_desde timestamptz; c jsonb;
begin
  v_email := redes.f_evento_autorizar(p_solicitante, case when coalesce(p ->> 'alcance', '') = 'total' then 'total' else 'zona' end);
  select * into z from redes.f_evento_zona(p);
  v_desde := coalesce(redes.f_instante(p ->> 'desde', 'desde cuándo'), clock_timestamp());
  c := redes.f_evento_contratos(z.geom, z.todo);
  return jsonb_build_object('alcance', z.alcance, 'zona', z.zona_nombre, 'contratos', c -> 'contratos', 'sensibles', c -> 'sensibles',
    'reportes', (select jsonb_build_object('total', count(*), 'bot', count(*) filter (where k.origen = 'bot'), 'l116', count(*) filter (where k.origen = 'l116'),
                                           'danos', count(*) filter (where k.origen = 'dano')) from redes.f_evento_candidatos(z.geom, z.todo, v_desde) k),
    'ya_abierto', (select e.codigo from redes.f_eventos_abiertos() e where (z.todo and e.todo) or (not z.todo and not e.todo and ST_Equals(e.geom, z.geom)) limit 1),
    'zona_geojson', case when z.geom is not null then ST_AsGeoJSON(ST_Multi(ST_SimplifyPreserveTopology(z.geom, 0.00002)), 6)::jsonb end);
end $$;

-- declarar: guarda el evento y asocia de una vez los reportes abiertos que ya estaban en la zona desde la hora de inicio
create function public.geoportal_redes_evento_declarar(p_solicitante text, p jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare
  v_email text; z record; v_causa text := btrim(coalesce(p ->> 'causa', '')); v_reg text := nullif(upper(btrim(coalesce(p ->> 'registro', ''))), '');
  v_dano uuid; v_itv uuid; v_sis text; v_desde timestamptz; v_regreso timestamptz; v_ahora timestamptz := clock_timestamp(); v_ya text; c jsonb;
  v_cons bigint; v_id bigint; v_ids bigint[]; v_max numeric := coalesce(redes.f_param('evento_horas_atras_max'), 72);
begin
  if exists (select 1 from jsonb_object_keys(p) k where k not in ('alcance', 'sectores', 'lat', 'lon', 'radio_m', 'total', 'planta', 'causa', 'registro', 'desde', 'regreso')) then
    perform tecnica.f_error('El evento trae un dato que no corresponde');
  end if;
  v_email := redes.f_evento_autorizar(p_solicitante, case when coalesce(p ->> 'alcance', '') = 'total' then 'total' else 'zona' end);
  select * into z from redes.f_evento_zona(p);
  if length(v_causa) < 5 or length(v_causa) > 200 then perform tecnica.f_error('Escriba la causa (de 5 a 200 letras)'); end if;
  if v_reg ~ '^DAN-[0-9]{6}$' then
    select d.id, d.sistema into v_dano, v_sis from redes.danos d where d.codigo = v_reg;
    if v_dano is null then perform tecnica.f_error(format('No hay ningún daño o falla con el código «%s»', v_reg), 'P0002'); end if;
  elsif v_reg ~ '^ITV-[0-9]{6}$' then
    select i.id, i.sistema into v_itv, v_sis from redes.intervenciones i where i.codigo = v_reg;
    if v_itv is null then perform tecnica.f_error(format('No hay ninguna intervención con el código «%s»', v_reg), 'P0002'); end if;
  elsif v_reg is not null then perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
  end if;
  if v_sis is not null and v_sis <> 'acueducto' then perform tecnica.f_error('Ese daño o intervención no es de acueducto'); end if;
  v_desde := coalesce(redes.f_instante(p ->> 'desde', 'desde cuándo'), v_ahora);
  if v_desde > v_ahora + interval '5 minutes' then perform tecnica.f_error('El evento no puede empezar en el futuro'); end if;
  if v_desde < v_ahora - make_interval(secs => (v_max * 3600)::double precision) then perform tecnica.f_error(format('El evento no puede haber empezado hace más de %s horas', v_max)); end if;
  v_regreso := redes.f_instante(p ->> 'regreso', 'regreso estimado del servicio');
  if v_regreso is not null and (v_regreso <= v_desde or v_regreso > v_desde + interval '30 days') then
    perform tecnica.f_error('La hora estimada de regreso debe ser después del inicio y antes de 30 días');
  end if;
  -- un evento a la vez: el consecutivo y la revisión de «ya hay uno abierto para esa zona»
  perform pg_advisory_xact_lock(hashtext('redes.eventos_suspension'));
  select e.codigo into v_ya from redes.f_eventos_abiertos() e where (z.todo and e.todo) or (not z.todo and not e.todo and ST_Equals(e.geom, z.geom)) limit 1;
  if v_ya is not null then raise exception 'Ya hay un evento abierto para esa misma zona: %', v_ya using errcode = '55000', hint = 'msg_usuario'; end if;
  c := redes.f_evento_contratos(z.geom, z.todo);
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'EVS' returning ultimo into v_cons;
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, planta_id, centro_lat, centro_lon, radio_m, zona_nombre, causa, dano_id, intervencion_id,
                                        desde, regreso_estimado, contratos, sensibles, autor)
  values ('EVS-' || lpad(v_cons::text, 6, '0'), z.alcance, z.todo, z.geom, z.sectores, z.planta_id, z.centro_lat, z.centro_lon, z.radio_m, z.zona_nombre, v_causa, v_dano, v_itv,
          v_desde, v_regreso, (c ->> 'contratos')::integer, (c ->> 'sensibles')::integer, v_email)
  returning id into v_id;
  with hechas as (
    insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, tipo, modo, autor)
    select v_id, k.origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, 'asociar', 'al_declarar', v_email
      from redes.f_evento_candidatos(z.geom, z.todo, v_desde, v_dano) k
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, 'en_atencion', 'Asociado al evento de suspensión {evento} (ya estaba recibido al declararlo)', v_email);
  perform tecnica.f_auditar(v_email, 'redes_evento_declarar', 'EVS-' || lpad(v_cons::text, 6, '0'),
          jsonb_build_object('alcance', z.alcance, 'zona', z.zona_nombre, 'contratos', c -> 'contratos', 'sensibles', c -> 'sensibles', 'asociados', coalesce(cardinality(v_ids), 0)), null);
  return redes.f_evento_json(v_id, true) || jsonb_build_object('asociados_al_declarar', coalesce(cardinality(v_ids), 0));
end $$;

-- el evento por su código, abierto y con el permiso de su alcance (lo usan regreso, cerrar y anular)
create function redes.f_evento_abierto(p_solicitante text, p_codigo text, p_para text default null, out email text, out id bigint, out codigo text, out desde timestamptz, out alcance text) returns record
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_cod text := upper(btrim(coalesce(p_codigo, ''))); e redes.v_evento_suspension%rowtype;
begin
  if v_cod !~ '^EVS-[0-9]{6}$' then perform tecnica.f_error('Escriba el código del evento (EVS-000123)'); end if;
  select * into e from redes.v_evento_suspension x where x.codigo = v_cod;
  email := redes.f_evento_autorizar(p_solicitante, coalesce(p_para, case when e.alcance = 'total' then 'total' else 'zona' end));
  if e.id is null then perform tecnica.f_error(format('No hay ningún evento con el código «%s»', v_cod), 'P0002'); end if;
  if e.estado <> 'abierto' then raise exception 'El evento % ya está %', e.codigo, e.estado using errcode = '55000', hint = 'msg_usuario'; end if;
  id := e.id; codigo := e.codigo; desde := e.desde; alcance := e.alcance;
end $$;

create function public.geoportal_redes_evento_regreso(p_solicitante text, p_codigo text, p_regreso text, p_motivo text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; v_reg timestamptz; v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo);
  v_reg := redes.f_instante(p_regreso, 'regreso estimado del servicio');
  if v_reg is null then perform tecnica.f_error('Escriba la hora estimada de regreso del servicio'); end if;
  if v_reg <= e.desde or v_reg > e.desde + interval '30 days' then perform tecnica.f_error('La hora estimada de regreso debe ser después del inicio y antes de 30 días'); end if;
  if v_mot is not null and (length(v_mot) < 10 or length(v_mot) > 500) then perform tecnica.f_error('El motivo lleva de 10 a 500 letras'); end if;
  insert into redes.evento_suspension_eventos (evento_id, tipo, regreso_estimado, motivo, hecho_en, autor) values (e.id, 'regreso', v_reg, v_mot, clock_timestamp(), e.email);
  return redes.f_evento_json(e.id);
end $$;

-- «dar de alta»: cierra el evento y, con el mismo motivo y la misma hora, los reportes asociados del bot y de la 116. Los daños quedan con la nota (siguen abiertos)
create function public.geoportal_redes_evento_cerrar(p_solicitante text, p_codigo text, p_motivo text, p_hecho_en text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; v_mot text := btrim(coalesce(p_motivo, '')); v_hecho timestamptz; v_ahora timestamptz := clock_timestamp(); v_ids bigint[]; v_l116 bigint[]; v_bot integer; v_dan integer; v_txt text;
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo);
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo del cierre (de 10 a 500 letras)'); end if;
  v_hecho := coalesce(redes.f_instante(p_hecho_en, 'hora del cierre'), v_ahora);
  if v_hecho > v_ahora + interval '5 minutes' then perform tecnica.f_error('La hora del cierre no puede ser futura'); end if;
  if v_hecho < e.desde then perform tecnica.f_error('El evento no se puede cerrar antes de la hora en que empezó'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.eventos_suspension'));
  select array_agg(r.id), count(*) filter (where r.origen = 'bot'), count(*) filter (where r.origen = 'dano') into v_ids, v_bot, v_dan from redes.f_evento_reportes(e.id) r;
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) values (e.id, 'cerrar', v_mot, v_hecho, e.email);
  v_txt := format('Evento de suspensión {evento} cerrado (%s): %s', redes.f_evento_hora(v_hecho), v_mot);
  perform redes.f_evento_marcar(v_ids, 'atendido', v_txt, e.email);
  -- línea 116: los asociados que siguen en «Registrado» pasan a «Atendido», con su hecho en el historial
  select array_agg(r.l116_reporte_id) into v_l116 from redes.f_evento_reportes(e.id) r join redes.l116_vigente v on v.reporte_id = r.l116_reporte_id
   where r.origen = 'l116' and v.estado = 'registrado';
  if v_l116 is not null then
    insert into redes.l116_eventos (reporte_id, tipo, estado, estado_antes, motivo, autor)
    select x, 'estado', 'atendido', 'registrado', left(replace(v_txt, '{evento}', e.codigo), 1000), e.email from unnest(v_l116) x order by x;
    update redes.l116_vigente set estado = 'atendido', estado_desde = v_hecho, actualizado_en = clock_timestamp() where reporte_id = any (v_l116) and estado = 'registrado';
  end if;
  perform tecnica.f_auditar(e.email, 'redes_evento_cerrar', e.codigo, jsonb_build_object('reportes', coalesce(cardinality(v_ids), 0), 'bot', v_bot, 'l116', coalesce(cardinality(v_l116), 0), 'danos', v_dan), null);
  return redes.f_evento_json(e.id) || jsonb_build_object('cerrados', jsonb_build_object('bot', v_bot, 'l116', coalesce(cardinality(v_l116), 0)), 'danos_siguen_abiertos', v_dan);
end $$;

-- anular (se declaró por error): los reportes asociados vuelven a su flujo normal
create function public.geoportal_redes_evento_anular(p_solicitante text, p_codigo text, p_motivo text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; v_mot text := btrim(coalesce(p_motivo, '')); v_ids bigint[];
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo);
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo de la anulación (de 10 a 500 letras)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.eventos_suspension'));
  select array_agg(r.id) into v_ids from redes.f_evento_reportes(e.id) r;
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) values (e.id, 'anular', v_mot, clock_timestamp(), e.email);
  perform redes.f_evento_marcar(v_ids, 'recibido', 'Evento de suspensión {evento} anulado: ' || v_mot, e.email);
  perform tecnica.f_auditar(e.email, 'redes_evento_anular', e.codigo, jsonb_build_object('reportes_liberados', coalesce(cardinality(v_ids), 0)), null);
  return redes.f_evento_json(e.id) || jsonb_build_object('reportes_liberados', coalesce(cardinality(v_ids), 0));
end $$;

-- un reporte por su referencia: bot = su id (uuid) · l116 = el número del reporte · dano = DAN-000123
create function redes.f_evento_reporte_ref(p_origen text, p_ref text, out reporte_externo_id uuid, out l116_reporte_id bigint, out dano_id uuid, out ref text) returns record
language plpgsql stable security definer set search_path = redes, tecnica, pg_temp as $$
declare v_ref text := btrim(coalesce(p_ref, ''));
begin
  if p_origen = 'bot' and v_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select r.id into reporte_externo_id from redes.reportes_externos r where r.id = v_ref::uuid;
  elsif p_origen = 'l116' and v_ref ~ '^[0-9]{1,15}$' then
    select r.id into l116_reporte_id from redes.l116_reportes r where r.reporte = v_ref::bigint;
  elsif p_origen = 'dano' and upper(v_ref) ~ '^DAN-[0-9]{6}$' then
    select d.id into dano_id from redes.danos d where d.codigo = upper(v_ref);
  else perform tecnica.f_error('Diga qué reporte es: del bot (su identificador), de la línea 116 (su número) o un daño (DAN-000123)');
  end if;
  ref := coalesce(reporte_externo_id::text, l116_reporte_id::text, dano_id::text);
  if ref is null then perform tecnica.f_error('Ese reporte no existe', 'P0002'); end if;
end $$;

create function public.geoportal_redes_evento_desasociar(p_solicitante text, p_codigo text, p_origen text, p_ref text, p_motivo text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; k record; v_mot text := btrim(coalesce(p_motivo, '')); v_id bigint;
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo, 'reportes');
  select * into k from redes.f_evento_reporte_ref(p_origen, p_ref);
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  if not exists (select 1 from redes.f_evento_reportes(e.id) r where r.origen = p_origen and r.ref = k.ref) then perform tecnica.f_error(format('Ese reporte no está asociado al evento %s', e.codigo)); end if;
  insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, tipo, modo, motivo, autor)
  values (e.id, p_origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, 'desasociar', 'manual', v_mot, e.email) returning id into v_id;
  perform redes.f_evento_marcar(array[v_id], 'recibido', 'Desasociado del evento de suspensión {evento}: ' || v_mot, e.email);
  return redes.f_evento_json(e.id);
end $$;

-- asociar a mano un reporte que no entró solo (llegó antes, es de otro tipo o quedó por fuera de la zona). No revisa la zona: lo decide el supervisor, con motivo
create function public.geoportal_redes_evento_asociar(p_solicitante text, p_codigo text, p_origen text, p_ref text, p_motivo text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare e record; k record; v_mot text := btrim(coalesce(p_motivo, '')); v_id bigint; v_otro text;
begin
  select * into e from redes.f_evento_abierto(p_solicitante, p_codigo, 'reportes');
  select * into k from redes.f_evento_reporte_ref(p_origen, p_ref);
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  if not redes.f_evento_ref_libre(p_origen, k.ref) then
    select x.codigo into v_otro from redes.evento_suspension_reportes r join redes.eventos_suspension x on x.id = r.evento_id where r.origen = p_origen and r.ref = k.ref order by r.id desc limit 1;
    perform tecnica.f_error(format('Ese reporte ya está asociado al evento %s', v_otro));
  end if;
  if p_origen = 'bot' and (select x.tipo from redes.reporte_externo_eventos x where x.reporte_id = k.reporte_externo_id order by x.id desc limit 1) <> 'recibido' then
    perform tecnica.f_error('Ese reporte del bot ya no está en «Recibido» (se convirtió en daño, se descartó o se atendió)');
  end if;
  insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, tipo, modo, motivo, autor)
  values (e.id, p_origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, 'asociar', 'manual', v_mot, e.email) returning id into v_id;
  perform redes.f_evento_marcar(array[v_id], 'en_atencion', 'Asociado a mano al evento de suspensión {evento}: ' || v_mot, e.email);
  return redes.f_evento_json(e.id);
end $$;

-- los eventos abiertos, para el mapa (modo «Afectaciones») y la franja: los ve cualquiera de Técnica. Con la zona en GeoJSON
create function public.geoportal_redes_eventos_vigentes(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'lectura');
begin
  return jsonb_build_object('eventos', coalesce((select jsonb_agg(redes.f_evento_json(e.id, true) order by e.id desc) from redes.f_eventos_abiertos() e), '[]'::jsonb),
                            'leyenda', jsonb_build_array(jsonb_build_object('clave', 'evento', 'texto', 'Zona sin agua (evento de suspensión)')));
end $$;

-- la lista (abiertos, o todos con los últimos primero) para el supervisor
create function public.geoportal_redes_eventos(p_solicitante text, p_estado text default 'abierto', p_limite integer default 50)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'detalle'); v_est text := coalesce(nullif(btrim(p_estado), ''), 'abierto'); v_lim integer := least(greatest(coalesce(p_limite, 50), 1), 200);
begin
  if v_est not in ('abierto', 'cerrado', 'anulado', 'todos') then perform tecnica.f_error('El estado es abierto, cerrado, anulado o todos'); end if;
  return jsonb_build_object('estado', v_est, 'eventos', coalesce((
    select jsonb_agg(redes.f_evento_json(s.id) order by s.id desc)
      from (select e.id from redes.v_evento_suspension e where v_est = 'todos' or e.estado = v_est order by e.id desc limit v_lim) s), '[]'::jsonb));
end $$;

-- el detalle: el evento, sus reportes asociados (sin nombres, direcciones ni textos del ciudadano), los sensibles confirmados (contrato y tipo) y el historial
create function public.geoportal_redes_evento(p_solicitante text, p_codigo text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'detalle'); v_cod text := upper(btrim(coalesce(p_codigo, ''))); e redes.eventos_suspension%rowtype;
        v_max integer := coalesce(redes.f_param('evento_lista_max'), 200)::integer;
begin
  if v_cod !~ '^EVS-[0-9]{6}$' then perform tecnica.f_error('Escriba el código del evento (EVS-000123)'); end if;
  select * into e from redes.eventos_suspension x where x.codigo = v_cod;
  if e.id is null then perform tecnica.f_error(format('No hay ningún evento con el código «%s»', v_cod), 'P0002'); end if;
  return redes.f_evento_json(e.id, true) || jsonb_build_object(
    'lista_max', v_max,
    'asociados', coalesce((
      select jsonb_agg(s.j order by s.id desc) from (
        select r.id, jsonb_build_object('origen', r.origen, 'modo', r.modo, 'asociado_en', r.creado_en,
                 'ref', case r.origen when 'bot' then r.ref when 'l116' then (select l.reporte::text from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                      else (select d.codigo from redes.danos d where d.id = r.dano_id) end,
                 'rotulo', case r.origen when 'bot' then (select 'Bot · ' || b.radicado from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                         when 'l116' then (select 'Línea 116 · ' || l.reporte from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                         else (select d.codigo from redes.danos d where d.id = r.dano_id) end,
                 'tipo', case r.origen when 'bot' then (select coalesce(t.nombre, b.tipo_bot) from redes.reportes_externos b left join redes.evento_tipos_asociables t on t.origen = 'bot' and t.codigo = lower(btrim(b.tipo_bot)) where b.id = r.reporte_externo_id)
                                       when 'l116' then (select l.causal from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                       else (select td.nombre from redes.danos d join redes.tipos_dano td on td.codigo = d.tipo_codigo where d.id = r.dano_id) end,
                 'cuando', case r.origen when 'bot' then (select b.recibido_en from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                         when 'l116' then (select l.fecha_registro from redes.l116_reportes l where l.id = r.l116_reporte_id)
                                         else (select d.t_detectado from redes.danos d where d.id = r.dano_id) end,
                 'lat', case r.origen when 'bot' then (select b.lat from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                      when 'l116' then (select round(ST_Y(v.geom)::numeric, 6) from redes.l116_vigente v where v.reporte_id = r.l116_reporte_id)
                                      else (select d.lat from redes.danos d where d.id = r.dano_id) end,
                 'lon', case r.origen when 'bot' then (select b.lon from redes.reportes_externos b where b.id = r.reporte_externo_id)
                                      when 'l116' then (select round(ST_X(v.geom)::numeric, 6) from redes.l116_vigente v where v.reporte_id = r.l116_reporte_id)
                                      else (select d.lon from redes.danos d where d.id = r.dano_id) end) as j
          from redes.f_evento_reportes(e.id) r order by r.id desc limit v_max) s), '[]'::jsonb),
    'sensibles_lista', redes.f_evento_contratos(e.geom, e.todo, true) -> 'sensibles_lista',
    'historial', coalesce((
      select jsonb_agg(h.j order by h.cuando, h.o) from (
        select x.creado_en as cuando, x.id as o, jsonb_build_object('que', x.tipo, 'cuando', x.hecho_en, 'regreso_estimado', x.regreso_estimado, 'motivo', x.motivo,
                 'por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = x.autor), 'Funcionario de EMDUPAR')) as j
          from redes.evento_suspension_eventos x where x.evento_id = e.id
        union all
        select r.creado_en, r.id, jsonb_build_object('que', case r.tipo when 'asociar' then 'asociar_a_mano' else 'desasociar' end, 'cuando', r.creado_en, 'motivo', r.motivo, 'origen', r.origen,
                 'por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = r.autor), 'Funcionario de EMDUPAR'))
          from redes.evento_suspension_reportes r where r.evento_id = e.id and r.modo = 'manual') h), '[]'::jsonb));
end $$;

-- la lista ajustable de lo que se asocia: cambia una fila (o agrega una nueva, con nombre y clase), con motivo
create function public.geoportal_redes_evento_tipo_fijar(p_solicitante text, p_origen text, p_codigo text, p_asocia boolean, p_motivo text, p_nombre text default null, p_clase text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'reportes'); v_cod text := redes.f_evento_clave(p_codigo); v_mot text := btrim(coalesce(p_motivo, ''));
        v_fila redes.evento_tipos_asociables%rowtype; v_nom text := nullif(btrim(coalesce(p_nombre, '')), ''); v_cla text := nullif(btrim(coalesce(p_clase, '')), '');
begin
  if coalesce(p_origen, '') not in ('bot', 'l116', 'dano') then perform tecnica.f_error('El origen es bot, l116 o dano'); end if;
  if length(v_cod) < 2 or length(v_cod) > 120 then perform tecnica.f_error('Escriba el tipo o la causal'); end if;
  if p_asocia is null then perform tecnica.f_error('Diga si se asocia o no'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  if v_cla is not null and v_cla not in ('sin_agua', 'dano_red', 'otro') then perform tecnica.f_error('La clase es sin_agua, dano_red u otro'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.evento_tipos_asociables'));
  select * into v_fila from redes.evento_tipos_asociables t where t.origen = p_origen and t.codigo = v_cod;
  if v_fila.codigo is null then
    if v_nom is null or v_cla is null then perform tecnica.f_error('Ese tipo no está en la lista: para agregarlo escriba su nombre y su clase'); end if;
    if p_origen = 'dano' and not exists (select 1 from redes.tipos_dano td where td.codigo = v_cod) then perform tecnica.f_error('Ese tipo de daño no existe', 'P0002'); end if;
    insert into redes.evento_tipos_asociables (origen, codigo, nombre, clase, asocia) values (p_origen, v_cod, left(v_nom, 120), v_cla, p_asocia);
  else
    update redes.evento_tipos_asociables set asocia = p_asocia, clase = coalesce(v_cla, clase), nombre = coalesce(left(v_nom, 120), nombre) where origen = p_origen and codigo = v_cod;
  end if;
  select * into v_fila from redes.evento_tipos_asociables t where t.origen = p_origen and t.codigo = v_cod;
  insert into redes.evento_tipo_eventos (origen, codigo, nombre, clase, asocia, motivo, autor) values (v_fila.origen, v_fila.codigo, v_fila.nombre, v_fila.clase, v_fila.asocia, v_mot, v_email);
  return jsonb_build_object('origen', v_fila.origen, 'codigo', v_fila.codigo, 'nombre', v_fila.nombre, 'clase', v_fila.clase, 'asocia', v_fila.asocia);
end $$;

-- qué sectores surte una planta (la lista completa cada vez; vacía = ninguno), con motivo
create function public.geoportal_redes_planta_sectores_fijar(p_solicitante text, p_planta text, p_sectores text[], p_motivo text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'reportes'); v_mot text := btrim(coalesce(p_motivo, '')); v_pl tecnica.plantas%rowtype; v_cods text[]; v_ids bigint[];
begin
  select * into v_pl from tecnica.plantas pl where pl.codigo = lower(btrim(coalesce(p_planta, ''))) and pl.activa;
  if v_pl.id is null then perform tecnica.f_error('Escoja la planta', 'P0002'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  select coalesce(array_agg(distinct upper(btrim(x))), '{}') into v_cods from unnest(coalesce(p_sectores, '{}')) x where btrim(coalesce(x, '')) <> '';
  select coalesce(array_agg(m.activo_id order by m.codigo), '{}') into v_ids from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.codigo = any (v_cods);
  if cardinality(v_ids) <> cardinality(v_cods) then perform tecnica.f_error('Alguno de los sectores no existe o ya no está vigente', 'P0002'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.planta_sectores'));
  update redes.planta_sectores set activo = false where planta_id = v_pl.id and activo and sector_id <> all (v_ids);
  insert into redes.planta_sectores (planta_id, sector_id) select v_pl.id, x from unnest(v_ids) x
  on conflict (planta_id, sector_id) do update set activo = true;
  insert into redes.planta_sector_eventos (planta_id, sectores, motivo, autor) values (v_pl.id, v_ids, v_mot, v_email);
  return jsonb_build_object('planta', v_pl.codigo, 'nombre', v_pl.nombre, 'sectores', to_jsonb(v_cods));
end $$;
