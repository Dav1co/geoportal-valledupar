-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1) · 26 — RPC de la simulación de cierre (las llama la Edge geoportal-redes; las rutas van en la Fase 4).
--   · geoportal_redes_simulacion_cierre: «¿Qué válvulas cierro?» desde un tramo o nodo (o el tramo más cercano a un punto). No guarda nada.
--   · geoportal_redes_simulacion_guardar: la recalcula en el servidor y la guarda con el daño (DAN-…) o la intervención (ITV-…). Solo agregar.
--   · geoportal_redes_simulaciones: las guardadas de un daño o una intervención.
-- Quién: quien captura daños y fallas o intervenciones, el supervisor y el administrador. Guardar: quien registró el daño o la intervención, o el supervisor.
-- Volátiles: la simulación arma tablas temporales de la transacción (la Edge llama por POST).
-- =====================================================================
create function public.geoportal_redes_simulacion_cierre(p_solicitante text, p_activo text default null, p_lat numeric default null, p_lon numeric default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_sim_autorizar(p_solicitante); v_id bigint;
begin
  if nullif(btrim(coalesce(p_activo, '')), '') is not null then v_id := redes.f_buscar_activo(p_activo);
  else v_id := redes.f_sim_tramo_cercano(p_lat, p_lon);
  end if;
  return redes.f_simular_cierre(v_id) - '_contratos';
end $$;

create function public.geoportal_redes_simulacion_guardar(p_solicitante text, p_registro text, p_activo text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare
  v_cod text := upper(btrim(coalesce(p_registro, ''))); v_email text; v_super boolean;
  v_dano uuid; v_itv uuid; v_act bigint; v_sis text; v_lat numeric; v_lon numeric; v_autor text; v_id bigint; j jsonb; v_sid bigint;
begin
  if v_cod ~ '^DAN-[0-9]{6}$' then
    v_email := redes.f_autorizar_captura_redes(p_solicitante, 'danos_fallas');
    select d.id, d.activo_id, d.sistema, d.lat, d.lon, d.autor into v_dano, v_act, v_sis, v_lat, v_lon, v_autor from redes.danos d where d.codigo = v_cod;
    if v_dano is null then perform tecnica.f_error(format('No hay ningún daño o falla con el código «%s»', v_cod), 'P0002'); end if;
  elsif v_cod ~ '^ITV-[0-9]{6}$' then
    v_email := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento');
    select i.id, i.activo_id, i.sistema, i.lat, i.lon, i.autor into v_itv, v_act, v_sis, v_lat, v_lon, v_autor from redes.intervenciones i where i.codigo = v_cod;
    if v_itv is null then perform tecnica.f_error(format('No hay ninguna intervención con el código «%s»', v_cod), 'P0002'); end if;
  else
    perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
  end if;
  v_super := (select p.perfil in ('admin', 'supervisor') from redes.f_perfil_lectura(v_email) p);
  if not v_super and v_autor <> v_email then
    raise exception 'Solo quien lo registró, el supervisor o el administrador guardan la simulación' using errcode = '42501';
  end if;
  if v_sis <> 'acueducto' then perform tecnica.f_error('La simulación de cierre es solo para acueducto'); end if;
  if (select count(*) from redes.simulaciones_cierre s where s.dano_id = v_dano or s.intervencion_id = v_itv) >= coalesce(redes.f_param('sim_guardadas_max'), 20) then
    perform tecnica.f_error(format('%s ya tiene %s simulaciones guardadas (el máximo)', v_cod, coalesce(redes.f_param('sim_guardadas_max'), 20)));
  end if;
  v_id := case when nullif(btrim(coalesce(p_activo, '')), '') is not null then redes.f_buscar_activo(p_activo)
               when v_act is not null then v_act
               else redes.f_sim_tramo_cercano(v_lat, v_lon) end;
  j := redes.f_simular_cierre(v_id);
  insert into redes.simulaciones_cierre (dano_id, intervencion_id, activo_id, red_huella, valvulas, contratos_min, contratos_max, segmento_grande, resultado, contratos, ms, autor)
  values (v_dano, v_itv, v_id, j -> 'red' ->> 'huella', (j -> 'estrecho' ->> 'valvulas_total')::integer, (j ->> 'contratos_min')::integer, (j ->> 'contratos_max')::integer,
          (j ->> 'segmento_grande')::boolean, j - '_contratos',
          case when jsonb_typeof(j -> '_contratos') = 'array' then array(select jsonb_array_elements_text(j -> '_contratos')) end,
          (j ->> 'ms')::integer, v_email)
  returning id into v_sid;
  perform tecnica.f_auditar(v_email, 'redes_simulacion_guardar', v_cod, jsonb_build_object('simulacion', v_sid, 'activo', j -> 'activo' ->> 'codigo',
          'contratos_min', j -> 'contratos_min', 'contratos_max', j -> 'contratos_max', 'valvulas', j -> 'estrecho' -> 'valvulas_total'), null);
  return jsonb_build_object('id', v_sid, 'registro', v_cod) || (j - '_contratos');
end $$;

create function public.geoportal_redes_simulaciones(p_solicitante text, p_registro text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_sim_autorizar(p_solicitante); v_cod text := upper(btrim(coalesce(p_registro, ''))); v_dano uuid; v_itv uuid;
begin
  if v_cod ~ '^DAN-[0-9]{6}$' then select id into v_dano from redes.danos where codigo = v_cod;
  elsif v_cod ~ '^ITV-[0-9]{6}$' then select id into v_itv from redes.intervenciones where codigo = v_cod;
  else perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
  end if;
  if v_dano is null and v_itv is null then perform tecnica.f_error(format('No hay ningún daño ni intervención con el código «%s»', v_cod), 'P0002'); end if;
  return jsonb_build_object('registro', v_cod, 'simulaciones', coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'creado_en', s.creado_en, 'autor', s.autor, 'activo', a.codigo,
                                        'valvulas', s.valvulas, 'contratos_min', s.contratos_min, 'contratos_max', s.contratos_max,
                                        'segmento_grande', s.segmento_grande, 'red_huella', s.red_huella, 'resultado', s.resultado) order by s.id desc)
      from redes.simulaciones_cierre s join redes.activos a on a.id = s.activo_id
     where (v_dano is not null and s.dano_id = v_dano) or (v_itv is not null and s.intervencion_id = v_itv)), '[]'::jsonb));
end $$;

-- =====================================================================
-- Fase 1b · el cierre real (David, 17-nov):
--   · geoportal_redes_valvula_maniobra: «válvula cerrada» / «válvula abierta». Ligada a un daño o una intervención: el operador de redes (daños y fallas o
--     mantenimiento) o el supervisor. Sin daño ni intervención: solo el supervisor y con motivo. Saca la foto del corte vigente en la misma transacción.
--   · geoportal_redes_corte_regreso: ajusta la hora estimada de regreso del servicio (quien cerró o el supervisor).
--   · geoportal_redes_cortes_vigentes: zonas sin agua, válvulas cerradas y conteos (la franja, las tarjetas y la leyenda). Lee la última foto.
--   · geoportal_redes_cortes_recalcular: el supervisor saca una foto nueva (si la red cambió después de la última maniobra).
--   · geoportal_redes_geovisor_mvt_cortes: la tesela del modo «Afectaciones» (tramos cerrados y afectados, válvulas cerradas). Lee la última foto.
-- =====================================================================
create function public.geoportal_redes_valvula_maniobra(p_solicitante text, p_valvula text, p_tipo text, p_registro text default null, p_motivo text default null,
                                                       p_hecho_en text default null, p_regreso text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare
  v_email text; v_super boolean; v_cod text := nullif(upper(btrim(coalesce(p_registro, ''))), ''); v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_val bigint; m redes.activo_vigente_mat%rowtype; v_dano uuid; v_itv uuid; v_sis text; v_hecho timestamptz; v_regreso timestamptz;
  c record; v_man bigint; v_foto bigint; f redes.corte_fotos%rowtype; v_ahora timestamptz := clock_timestamp();
begin
  if coalesce(p_tipo, '') not in ('cerrar', 'abrir') then perform tecnica.f_error('Elija: válvula cerrada o válvula abierta'); end if;
  -- una maniobra a la vez: la foto debe ver todas las válvulas cerradas en este momento
  perform pg_advisory_xact_lock(hashtext('redes.cortes_vigentes'));
  v_val := redes.f_buscar_activo(p_valvula);
  select * into m from redes.activo_vigente_mat where activo_id = v_val;
  if m.prefijo <> 'VAL' or m.sistema <> 'acueducto' then perform tecnica.f_error(format('%s no es una válvula de acueducto', m.codigo)); end if;
  if m.retirado then perform tecnica.f_error(format('La válvula %s está retirada', m.codigo)); end if;
  select * into c from redes.f_cierres_vigentes() x where x.valvula_id = v_val;
  if p_tipo = 'abrir' then
    if c.cierre_id is null then perform tecnica.f_error(format('La válvula %s no está cerrada', m.codigo)); end if;
    v_dano := c.dano_id; v_itv := c.intervencion_id;      -- la apertura pertenece al mismo daño o intervención que el cierre
  else
    if c.cierre_id is not null then
      perform tecnica.f_error(format('La válvula %s ya está cerrada desde %s', m.codigo, to_char(c.hecho_en at time zone 'America/Bogota', 'DD/MM HH24:MI')));
    end if;
    if v_cod ~ '^DAN-[0-9]{6}$' then
      select d.id, d.sistema into v_dano, v_sis from redes.danos d where d.codigo = v_cod;
      if v_dano is null then perform tecnica.f_error(format('No hay ningún daño o falla con el código «%s»', v_cod), 'P0002'); end if;
    elsif v_cod ~ '^ITV-[0-9]{6}$' then
      select i.id, i.sistema into v_itv, v_sis from redes.intervenciones i where i.codigo = v_cod;
      if v_itv is null then perform tecnica.f_error(format('No hay ninguna intervención con el código «%s»', v_cod), 'P0002'); end if;
    elsif v_cod is not null then perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
    end if;
    if v_sis is not null and v_sis <> 'acueducto' then perform tecnica.f_error('Ese daño o intervención no es de acueducto'); end if;
  end if;
  -- quién: con daño, quien captura daños y fallas; con intervención, mantenimiento; sin ninguno, solo el supervisor (y con motivo)
  if v_dano is not null then v_email := redes.f_autorizar_captura_redes(p_solicitante, 'danos_fallas');
  elsif v_itv is not null then v_email := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento');
  else
    v_email := redes.f_supervisor(p_solicitante, 'cierran o abren una válvula sin daño ni intervención');
    if v_motivo is null or length(v_motivo) < 10 then perform tecnica.f_error('Sin daño ni intervención, escriba el motivo (al menos 10 letras)'); end if;
  end if;
  -- cuándo: ahora, o lo hecho en campo y registrado después (con tope); nunca en el futuro ni antes del cierre
  v_hecho := coalesce(redes.f_instante(p_hecho_en, 'hora de la maniobra'), v_ahora);
  if v_hecho > v_ahora + interval '5 minutes' then perform tecnica.f_error('La hora de la maniobra no puede ser futura'); end if;
  if v_hecho < v_ahora - make_interval(secs => (coalesce(redes.f_param('corte_horas_atras_max'), 48) * 3600)::double precision) then
    perform tecnica.f_error(format('La hora de la maniobra no puede ser de hace más de %s horas', coalesce(redes.f_param('corte_horas_atras_max'), 48)));
  end if;
  if p_tipo = 'abrir' and v_hecho < c.hecho_en then perform tecnica.f_error('La válvula no se puede abrir antes de la hora en que se cerró'); end if;
  v_regreso := redes.f_instante(p_regreso, 'regreso estimado del servicio');
  if v_regreso is not null and p_tipo <> 'cerrar' then perform tecnica.f_error('La hora estimada de regreso se pone al cerrar'); end if;
  if v_regreso is not null and (v_regreso <= v_hecho or v_regreso > v_hecho + interval '30 days') then
    perform tecnica.f_error('La hora estimada de regreso debe ser después del cierre y antes de 30 días');
  end if;
  insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, dano_id, intervencion_id, motivo, regreso_estimado, hecho_en, autor)
  values (v_val, p_tipo, case when p_tipo = 'abrir' then c.cierre_id end, v_dano, v_itv, v_motivo, v_regreso, v_hecho, v_email)
  returning id into v_man;
  v_foto := redes.f_cortes_foto(v_man, v_email);
  select * into f from redes.corte_fotos where id = v_foto;
  perform tecnica.f_auditar(v_email, 'redes_valvula_' || p_tipo, m.codigo, jsonb_build_object('maniobra', v_man, 'registro', coalesce(v_cod, (select codigo from redes.danos where id = v_dano),
          (select codigo from redes.intervenciones where id = v_itv)), 'foto', v_foto, 'zonas', f.zonas, 'ms', f.ms), null);
  return jsonb_build_object('maniobra', v_man, 'valvula', m.codigo, 'estado', case when p_tipo = 'cerrar' then 'cerrada' else 'abierta' end, 'hecho_en', v_hecho,
    'en_red', exists (select 1 from redes.corte_foto_valvulas fv where fv.foto_id = v_foto and fv.valvula_id = v_val and fv.en_red) or p_tipo = 'abrir',
    'zona', (select fv.zona from redes.corte_foto_valvulas fv where fv.foto_id = v_foto and fv.valvula_id = v_val),
    'vigente', jsonb_build_object('zonas', f.zonas, 'valvulas_cerradas', f.valvulas_cerradas, 'contratos', f.contratos_cerrados + f.contratos_afectados,
                                  'tramos_cerrados', f.tramos_cerrados, 'tramos_afectados', f.tramos_afectados, 'ms', f.ms));
end $$;

create function public.geoportal_redes_corte_regreso(p_solicitante text, p_valvula text, p_regreso text, p_motivo text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_sim_autorizar(p_solicitante); v_val bigint := redes.f_buscar_activo(p_valvula); c record; v_reg timestamptz; v_man bigint; v_super boolean;
begin
  select * into c from redes.f_cierres_vigentes() x where x.valvula_id = v_val;
  if c.cierre_id is null then perform tecnica.f_error('Esa válvula no está cerrada'); end if;
  v_super := (select p.perfil in ('admin', 'supervisor') from redes.f_perfil_lectura(v_email) p);
  if not v_super and c.autor <> v_email then raise exception 'Solo quien cerró la válvula o el supervisor ajustan la hora de regreso' using errcode = '42501'; end if;
  v_reg := redes.f_instante(p_regreso, 'regreso estimado del servicio');
  if v_reg is null then perform tecnica.f_error('Escriba la hora estimada de regreso del servicio'); end if;
  if v_reg <= c.hecho_en or v_reg > c.hecho_en + interval '30 days' then perform tecnica.f_error('La hora estimada de regreso debe ser después del cierre y antes de 30 días'); end if;
  insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, dano_id, intervencion_id, motivo, regreso_estimado, hecho_en, autor)
  values (v_val, 'regreso', c.cierre_id, c.dano_id, c.intervencion_id, nullif(btrim(coalesce(p_motivo, '')), ''), v_reg, clock_timestamp(), v_email)
  returning id into v_man;
  return jsonb_build_object('maniobra', v_man, 'regreso_estimado', v_reg);
end $$;

-- lo que ve cualquiera que entra al geovisor (todos los perfiles del geovisor): solo conteos; quién = el nombre del funcionario de la lista blanca
create function public.geoportal_redes_cortes_vigentes(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; f redes.corte_fotos%rowtype;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into f from redes.corte_fotos order by id desc limit 1;
  if f.id is null or f.valvulas_cerradas = 0 then return jsonb_build_object('hay', false, 'zonas', '[]'::jsonb, 'valvulas', '[]'::jsonb); end if;
  return jsonb_build_object(
    'hay', true, 'foto', jsonb_build_object('id', f.id, 'calculada_en', f.creado_en, 'red_huella', f.red_huella),
    'resumen', jsonb_build_object('zonas', f.zonas, 'valvulas_cerradas', f.valvulas_cerradas, 'contratos', f.contratos_cerrados + f.contratos_afectados),
    'leyenda', jsonb_build_array(jsonb_build_object('clave', 'afectado', 'texto', 'Sin agua'), jsonb_build_object('clave', 'cerrado', 'texto', 'Tubería cerrada'),
                                 jsonb_build_object('clave', 'valvula', 'texto', 'Válvula cerrada')),
    'zonas', coalesce((
      select jsonb_agg(jsonb_build_object('zona', z.zona, 'lat', z.lat, 'lon', z.lon, 'caja', to_jsonb(z.caja),
               'contratos', z.contratos_cerrados + z.contratos_afectados, 'tramos', z.tramos_cerrados + z.tramos_afectados,
               'desde', (select min(m.hecho_en) from redes.corte_foto_valvulas fv join redes.valvula_maniobras m on m.id = fv.cierre_id where fv.foto_id = f.id and fv.zona = z.zona),
               'regreso_estimado', (select max(redes.f_cierre_regreso(fv.cierre_id)) from redes.corte_foto_valvulas fv where fv.foto_id = f.id and fv.zona = z.zona),
               'por', (select coalesce(jsonb_agg(distinct jsonb_build_object('registro', coalesce(d.codigo, i.codigo),
                                 'que', case when d.id is not null then coalesce((select t.nombre from redes.tipos_dano t where t.codigo = d.tipo_codigo), 'daño')
                                             when i.id is not null then case when i.nace_de = 'programada' then 'trabajo programado' else 'reparación' end
                                             else 'maniobra del supervisor' end)), '[]'::jsonb)
                         from redes.corte_foto_valvulas fv join redes.valvula_maniobras m on m.id = fv.cierre_id
                         left join redes.danos d on d.id = m.dano_id left join redes.intervenciones i on i.id = m.intervencion_id
                        where fv.foto_id = f.id and fv.zona = z.zona)) order by z.contratos_cerrados + z.contratos_afectados desc, z.zona)
        from redes.corte_foto_zonas z where z.foto_id = f.id), '[]'::jsonb),
    'valvulas', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', v.codigo, 'nombre', coalesce(v.codigo_anterior, v.codigo), 'zona', fv.zona, 'en_red', fv.en_red,
               'lat', round(ST_Y(ST_PointOnSurface(v.geom))::numeric, 6), 'lon', round(ST_X(ST_PointOnSurface(v.geom))::numeric, 6),
               'desde', m.hecho_en, 'quien', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = m.autor), 'Funcionario de EMDUPAR'),
               'registro', coalesce(d.codigo, i.codigo), 'regreso_estimado', redes.f_cierre_regreso(m.id)) order by m.hecho_en)
        from redes.corte_foto_valvulas fv join redes.valvula_maniobras m on m.id = fv.cierre_id join redes.activo_vigente_mat v on v.activo_id = fv.valvula_id
        left join redes.danos d on d.id = m.dano_id left join redes.intervenciones i on i.id = m.intervencion_id
       where fv.foto_id = f.id), '[]'::jsonb));
end $$;

create function public.geoportal_redes_cortes_recalcular(p_solicitante text, p_motivo text)
returns jsonb
language plpgsql volatile security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'recalculan los cortes vigentes'); v_foto bigint; f redes.corte_fotos%rowtype;
begin
  if length(btrim(coalesce(p_motivo, ''))) < 10 then perform tecnica.f_error('Escriba el motivo (al menos 10 letras)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.cortes_vigentes'));
  v_foto := redes.f_cortes_foto(null, v_email, btrim(p_motivo));
  select * into f from redes.corte_fotos where id = v_foto;
  return jsonb_build_object('foto', v_foto, 'zonas', f.zonas, 'valvulas_cerradas', f.valvulas_cerradas, 'contratos', f.contratos_cerrados + f.contratos_afectados, 'ms', f.ms);
end $$;

-- la tesela del modo «Afectaciones»: capas «corte_tramos» (papel: cerrado | afectado, zona) y «corte_valvulas» (código, zona). Todos los perfiles del geovisor.
create function public.geoportal_redes_geovisor_mvt_cortes(p_solicitante text, p_z integer, p_x integer, p_y integer)
returns text
language plpgsql stable security definer set search_path = public, redes, extensions, pg_temp as $$
declare a record; v_env geometry; v_env4 geometry; v_foto bigint; v1 bytea; v2 bytea;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  select max(id) into v_foto from redes.corte_fotos;
  if v_foto is null or p_z < 10 then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'corte_tramos', 4096, 'geom') into v1 from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, ft.papel, ft.zona, m.codigo
      from redes.activo_vigente_mat m join redes.corte_foto_tramos ft on ft.foto_id = v_foto and ft.activo_id = m.activo_id
     where m.geom && v_env4) t where t.geom is not null;
  select ST_AsMVT(t, 'corte_valvulas', 4096, 'geom') into v2 from (
    select ST_AsMVTGeom(ST_Transform(ST_PointOnSurface(m.geom), 3857), v_env, 4096, 64, true) as geom, m.codigo, fv.zona
      from redes.activo_vigente_mat m join redes.corte_foto_valvulas fv on fv.foto_id = v_foto and fv.valvula_id = m.activo_id
     where m.geom && v_env4) t where t.geom is not null;
  return replace(encode(coalesce(v1, ''::bytea) || coalesce(v2, ''::bytea), 'base64'), E'\n', '');
end $$;
