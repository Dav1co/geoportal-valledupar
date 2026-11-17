-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 26 — RPC (las llamará la Edge geoportal-redes; las rutas y las pantallas son del Code B).
--   · geoportal_redes_alertas_presion: alertas de presión de modelo (supervisor y administrador).
--   · geoportal_redes_sensibles / geoportal_redes_sensible_fijar: bandeja de usuarios sensibles; el supervisor confirma, descarta o agrega uno a mano.
--   · geoportal_redes_afectacion: contratos sin agua y usuarios sensibles de un daño o una intervención (cierre real si lo hay; si no, simulación).
--   · geoportal_redes_sensores: los sensores (activos SEN) con su estado («por conectar» sin lecturas).
--   · geoportal_redes_afectaciones_danos: TODOS los daños abiertos o en atención, sin límite de fecha, para el modo «Afectaciones» (supervisor y administrador).
-- Sin nombres ni teléfonos: contrato, tipo y conteos.
-- =====================================================================
create function public.geoportal_redes_alertas_presion(p_solicitante text, p_escenario text default 'existente')
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven las alertas de presión');
begin
  return redes.f_alertas_presion(coalesce(p_escenario, 'existente'));
end $$;

create function public.geoportal_redes_sensibles(p_solicitante text, p_estado text default null, p_despues_de text default null, p_limite integer default 100)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven los usuarios sensibles'); v_lim integer := coalesce(p_limite, 100); v_items jsonb;
begin
  if v_lim < 1 or v_lim > 500 then perform tecnica.f_error('Se piden de 1 a 500'); end if;
  if p_estado is not null and p_estado not in ('por_confirmar', 'confirmado', 'descartado') then perform tecnica.f_error('Ese estado no existe'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('contrato', x.contrato, 'tipo', x.tipo, 'tipo_nombre', x.nombre, 'palabra', x.palabra, 'origen', x.origen, 'estado', x.estado,
                                               'desde', x.desde, 'tramo', x.tramo, 'lat', x.lat, 'lon', x.lon) order by x.contrato), '[]') into v_items
    from (select v.*, t.nombre, (select a.codigo from redes.contrato_tramo ct join redes.activos a on a.id = ct.activo_id where ct.contrato = v.contrato) as tramo,
                 (select round(ST_Y(c.geom)::numeric, 6) from public.catastro_valledupar c where c.cod_usuario = v.contrato and c.geom is not null order by c.id limit 1) as lat,
                 (select round(ST_X(c.geom)::numeric, 6) from public.catastro_valledupar c where c.cod_usuario = v.contrato and c.geom is not null order by c.id limit 1) as lon
            from redes.v_usuario_sensible v join redes.tipos_sensible t on t.codigo = v.tipo
           where (p_estado is null or v.estado = p_estado) and (p_despues_de is null or v.contrato > p_despues_de)
           order by v.contrato limit v_lim) x;
  return jsonb_build_object(
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre) order by t.orden) from redes.tipos_sensible t where t.activo),
    'totales', (select coalesce(jsonb_object_agg(g.estado, g.n), '{}') from (select v.estado, count(*) as n from redes.v_usuario_sensible v group by 1) g),
    'items', v_items, 'siguiente', case when jsonb_array_length(v_items) = v_lim then v_items -> (v_lim - 1) ->> 'contrato' end);
end $$;

create function public.geoportal_redes_sensible_fijar(p_solicitante text, p_contrato text, p_accion text, p_tipo text default null, p_motivo text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'confirman los usuarios sensibles'); v_c text := btrim(coalesce(p_contrato, '')); v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
        u redes.v_usuario_sensible%rowtype; v_tipo text; v_nuevo text;
begin
  if v_c !~ '^[0-9]{1,15}$' then perform tecnica.f_error('Escriba el número del contrato'); end if;
  if coalesce(p_accion, '') not in ('confirmar', 'descartar') then perform tecnica.f_error('Elija: confirmar o descartar'); end if;
  if p_tipo is not null and not exists (select 1 from redes.tipos_sensible where codigo = p_tipo and activo) then perform tecnica.f_error('Ese tipo no existe'); end if;
  select * into u from redes.v_usuario_sensible where contrato = v_c;
  if not found then
    -- agregar uno a mano: solo confirmando, con su tipo y un motivo, y si el contrato está en el catastro
    if p_accion <> 'confirmar' or p_tipo is null or v_mot is null or length(v_mot) < 10 then perform tecnica.f_error('Ese contrato no está en la lista: para agregarlo, confirme con el tipo y el motivo (al menos 10 letras)'); end if;
    if not exists (select 1 from public.catastro_valledupar c where c.cod_usuario = v_c) then perform tecnica.f_error(format('El contrato %s no está en el catastro', v_c), 'P0002'); end if;
    insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor) values (v_c, p_tipo, null, 'manual', v_email);
  end if;
  if p_accion = 'descartar' and (v_mot is null or length(v_mot) < 10) then perform tecnica.f_error('Para descartar, escriba el motivo (al menos 10 letras)'); end if;
  v_tipo := case when p_accion = 'confirmar' then coalesce(p_tipo, u.tipo) end;
  v_nuevo := case p_accion when 'confirmar' then 'confirmado' else 'descartado' end;      -- (fuera del «if»: un «case … then» dentro de la condición la corta)
  if u.estado = v_nuevo and u.tipo is not distinct from coalesce(v_tipo, u.tipo) then
    return jsonb_build_object('contrato', v_c, 'estado', u.estado, 'tipo', u.tipo, 'cambio', false);
  end if;
  insert into redes.usuario_sensible_eventos (contrato, accion, tipo, motivo, autor) values (v_c, p_accion, v_tipo, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_sensible_' || p_accion, v_c, jsonb_build_object('tipo', v_tipo, 'motivo', v_mot), null);
  return jsonb_build_object('contrato', v_c, 'estado', case p_accion when 'confirmar' then 'confirmado' else 'descartado' end, 'tipo', v_tipo, 'cambio', true);
end $$;

-- contratos sin agua y usuarios sensibles de un daño o una intervención. Con válvulas cerradas vigentes de ese registro: lo real (la última foto, sin recalcular);
-- si no: la simulación sobre su activo (o el tramo más cercano a su punto). Volátil por la simulación (tablas temporales).
create function public.geoportal_redes_afectacion(p_solicitante text, p_registro text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare
  v_email text := redes.f_sim_autorizar(p_solicitante); v_cod text := upper(btrim(coalesce(p_registro, '')));
  v_dano uuid; v_itv uuid; v_act bigint; v_sis text; v_lat numeric; v_lon numeric; v_foto bigint; v_zonas integer[]; v_con text[]; j jsonb;
begin
  if v_cod ~ '^DAN-[0-9]{6}$' then select d.id, d.activo_id, d.sistema, d.lat, d.lon into v_dano, v_act, v_sis, v_lat, v_lon from redes.danos d where d.codigo = v_cod;
  elsif v_cod ~ '^ITV-[0-9]{6}$' then select i.id, i.activo_id, i.sistema, i.lat, i.lon into v_itv, v_act, v_sis, v_lat, v_lon from redes.intervenciones i where i.codigo = v_cod;
  else perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
  end if;
  if v_dano is null and v_itv is null then perform tecnica.f_error(format('No hay ningún daño ni intervención con el código «%s»', v_cod), 'P0002'); end if;
  if v_sis <> 'acueducto' then perform tecnica.f_error('La afectación por cierre es solo para acueducto'); end if;
  select max(id) into v_foto from redes.corte_fotos;
  select array_agg(distinct fv.zona) filter (where fv.zona is not null) into v_zonas
    from redes.f_cierres_vigentes() c join redes.corte_foto_valvulas fv on fv.foto_id = v_foto and fv.cierre_id = c.cierre_id
   where c.dano_id = v_dano or c.intervencion_id = v_itv;
  if exists (select 1 from redes.f_cierres_vigentes() c where c.dano_id = v_dano or c.intervencion_id = v_itv) then
    select coalesce(array_agg(distinct ct.contrato), '{}') into v_con
      from redes.corte_foto_tramos ft join redes.contrato_tramo ct on ct.activo_id = ft.activo_id where ft.foto_id = v_foto and ft.zona = any (coalesce(v_zonas, '{}'));
    return jsonb_build_object('registro', v_cod, 'fuente', 'cierre_real', 'texto', 'Según las válvulas cerradas en este momento',
      'valvulas_cerradas', (select count(*) from redes.f_cierres_vigentes() c where c.dano_id = v_dano or c.intervencion_id = v_itv),
      'zonas', coalesce(cardinality(v_zonas), 0), 'contratos', cardinality(v_con), 'contratos_min', cardinality(v_con), 'contratos_max', cardinality(v_con),
      'sensibles', redes.f_sensibles_en(v_con));
  end if;
  j := redes.f_simular_cierre(coalesce(v_act, redes.f_sim_tramo_cercano(v_lat, v_lon)));
  return jsonb_build_object('registro', v_cod, 'fuente', 'simulacion', 'texto', 'Propuesta según la simulación de cierre (todavía no hay válvulas cerradas)',
    'activo', j -> 'activo' ->> 'codigo', 'valvulas_a_cerrar', j -> 'estrecho' -> 'valvulas_total', 'segmento_grande', j -> 'segmento_grande',
    'contratos_min', j -> 'contratos_min', 'contratos_max', j -> 'contratos_max',
    -- los sensibles del escenario estrecho (el número menor); si el sector es tan grande que no se listan los contratos, no se calculan
    'sensibles', case when jsonb_typeof(j -> '_contratos') = 'array' then redes.f_sensibles_en(array(select jsonb_array_elements_text(j -> '_contratos'))) end);
end $$;

create function public.geoportal_redes_sensores(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  return jsonb_build_object('sensores', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', coalesce(m.nombre, m.codigo), 'tipo', redes.f_tipo_nombre(m.prefijo), 'estado', redes.f_sensor_estado(m.activo_id),
                                        'lat', round(ST_Y(ST_PointOnSurface(m.geom))::numeric, 6), 'lon', round(ST_X(ST_PointOnSurface(m.geom))::numeric, 6),
                                        'ultima', (select jsonb_build_object('variable', l.variable, 'valor', l.valor, 'unidad', l.unidad, 'medido_en', l.medido_en)
                                                     from redes.sensor_lecturas l where l.activo_id = m.activo_id order by l.medido_en desc limit 1)) order by m.codigo)
      from redes.activo_vigente_mat m where m.prefijo in ('SEN', 'SCA') and not m.retirado and not m.oculto), '[]'::jsonb),
    'nota', 'Los sensores sin lecturas están «por conectar»: todavía no envían datos.');
end $$;

-- todos los daños abiertos («reportado») o en atención, SIN límite de fecha (David, 17-nov): para el modo «Afectaciones» del geovisor. Supervisor y administrador.
-- La misma forma que la capa «danos» de geoportal_redes_geovisor_capa (las mismas propiedades), más «total». Acueducto y alcantarillado.
create function public.geoportal_redes_afectaciones_danos(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven todos los daños abiertos'); v_max integer := floor(redes.f_param('geovisor_max_elementos'))::integer;
        v_f jsonb; v_n integer;
begin
  with ab as materialized (      -- redes.v_dano se lee una sola vez
    select d.codigo, d.clase, d.tipo_nombre, d.sistema, d.estado, d.activo_codigo, d.t_detectado, d.riesgo, d.origen, d.lat, d.lon
      from redes.v_dano d where d.estado in ('reportado', 'en_atencion'))
  select coalesce((select jsonb_agg(x.f order by x.o desc, x.codigo) from (
           select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(ab.lon, ab.lat)),
                    'properties', jsonb_build_object('codigo', ab.codigo, 'clase', ab.clase, 'tipo', ab.tipo_nombre, 'sistema', ab.sistema, 'estado', ab.estado,
                                                     'activo', ab.activo_codigo, 'cuando', ab.t_detectado, 'riesgo', ab.riesgo, 'origen', ab.origen)) as f, ab.t_detectado as o, ab.codigo
             from ab order by ab.t_detectado desc, ab.codigo limit v_max) x), '[]'::jsonb),
         (select count(*) from ab)
    into v_f, v_n;
  return jsonb_build_object('type', 'FeatureCollection', 'capa', 'afectaciones_danos', 'total', v_n, 'recortada', v_n > v_max, 'features', v_f);
end $$;
