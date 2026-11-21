begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · EVENTOS: ORIGEN Y TUBOS · 90 — REVERSA (PROPUESTA). Generada por pruebas_locales/generar.py.
-- Deja las 11 funciones con su texto de antes, quita las nuevas y las 6 tablas, y VUELVE A ACTIVAR los sectores por planta que la migración desactivó
-- (los del último hecho de cada planta antes de la migración), con un hecho nuevo y su motivo.
-- SE NIEGA si alguna función cambió después de la migración, o si ya hay hechos nuevos: eventos con causal o por tubo, sectores asignados a un tubo o
-- causales ajustadas (la reversa no borra hechos: avise). Antes, devuelva la Edge a la anterior.
-- =====================================================================
do $$
begin
  if to_regclass('redes.evento_causales') is null then raise exception 'No hay nada que revertir: el corte de eventos (origen y tubos) no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '1ba192724c2fddcf321104700829f3cc'
     or (select count(*) from (values ('redes.f_evento_zona(jsonb)', '795f3c6c45b34306060d375ebe1f370d'), ('public.geoportal_redes_evento_declarar(text,jsonb)', 'fdf51a96463dac4088a66632fb926d06'), ('public.geoportal_redes_evento_catalogo(text)', '845a7401e73af489e42e716241bbd06f'), ('redes.f_evento_json(bigint,boolean)', '45f59666e3984baa767aa251e20ef79a'), ('public.geoportal_redes_planta_sectores_fijar(text,text,text[],text)', '147efbf990088feecd07994db03732aa'), ('redes.f_rep_columnas(text)', 'a6955a401c14a8692d68402294db810e'), ('redes.f_rep_eventos(jsonb,boolean,timestamp with time zone,text,integer,boolean)', 'bef95e9511f4eaf360ede1023e8c40a4'), ('redes.f_rep_leame(text,jsonb,boolean,text,timestamp with time zone)', '41c7b3680290ba3bcfe7a98cae9fe7dc'), ('tecnica.f_rep_columnas(text,jsonb)', '433cc539c24e1e14b07f96d79e974f65'), ('tecnica.f_rep_eventos_planta(jsonb,boolean,timestamp with time zone,text,integer)', '1f3ac41ec397b2ce20d0d818c63b0b15'), ('tecnica.f_rep_leame(text,jsonb,boolean,text,timestamp with time zone)', 'fe08987ea0b82be59420fc5d964459ff')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 11 then
    raise exception 'Las funciones cambiaron después de la migración: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.evento_causal) or exists (select 1 from redes.evento_tubos) or exists (select 1 from redes.tubo_sector_eventos) or exists (select 1 from redes.evento_causal_eventos) then
    raise exception 'Ya hay hechos nuevos (eventos con causal o por tubo, sectores de un tubo o causales ajustadas): la reversa no los borra. Avise';
  end if;
end $$;
-- 1. las funciones reemplazadas, con su texto de antes
CREATE OR REPLACE FUNCTION redes.f_evento_zona(p jsonb, OUT alcance text, OUT todo boolean, OUT geom geometry, OUT sectores bigint[], OUT planta_id bigint, OUT centro_lat numeric, OUT centro_lon numeric, OUT radio_m numeric, OUT zona_nombre text)
 RETURNS record
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_cods text[]; v_cuantos integer; v_pl tecnica.plantas%rowtype; v_sector text; v_pt geometry;
begin
  alcance := coalesce(p ->> 'alcance', ''); todo := false; sectores := '{}';
  if alcance = 'sectores' then
    if jsonb_typeof(p -> 'sectores') is distinct from 'array' or jsonb_array_length(p -> 'sectores') = 0 then perform tecnica.f_error('Escoja al menos un sector o subsector'); end if;
    if jsonb_array_length(p -> 'sectores') > coalesce(redes.f_param('evento_sectores_max'), 40) then
      perform tecnica.f_error(format('Un evento admite máximo %s sectores o subsectores', coalesce(redes.f_param('evento_sectores_max'), 40)));
    end if;
    select array_agg(distinct upper(btrim(x))) into v_cods from jsonb_array_elements_text(p -> 'sectores') x;
    select array_agg(m.activo_id order by m.codigo), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(m.geom)), 3)),
           string_agg(coalesce(nullif(btrim(m.nombre), ''), m.codigo), ', ' order by m.codigo), count(*)
      into sectores, geom, zona_nombre, v_cuantos
      from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.codigo = any (v_cods);
    if v_cuantos is distinct from cardinality(v_cods) then perform tecnica.f_error('Alguno de los sectores no existe o ya no está vigente', 'P0002'); end if;
    zona_nombre := left(zona_nombre, 300);
  elsif alcance = 'circulo' then
    centro_lat := round(redes.f_num(p -> 'lat'), 6); centro_lon := round(redes.f_num(p -> 'lon'), 6); radio_m := round(redes.f_num(p -> 'radio_m'), 1);
    if centro_lat is null or centro_lon is null or centro_lat not between -90 and 90 or centro_lon not between -180 and 180 then perform tecnica.f_error('Marque el centro del círculo en el mapa'); end if;
    if radio_m is null or radio_m < coalesce(redes.f_param('evento_radio_min_m'), 20) or radio_m > coalesce(redes.f_param('evento_radio_max_m'), 5000) then
      perform tecnica.f_error(format('El radio del círculo va de %s a %s metros', coalesce(redes.f_param('evento_radio_min_m'), 20), coalesce(redes.f_param('evento_radio_max_m'), 5000)));
    end if;
    v_pt := ST_SetSRID(ST_MakePoint(centro_lon, centro_lat), 4326);
    geom := ST_Multi(ST_Buffer(v_pt::geography, radio_m, 16)::geometry);
    select s.nombre into v_sector from redes.f_sector_de(v_pt) s;
    zona_nombre := format('un círculo de %s m', round(radio_m)) || coalesce(' en ' || nullif(btrim(v_sector), ''), '');
  elsif alcance = 'total' then
    if coalesce(p ->> 'total', '') = 'ciudad' then
      todo := true; zona_nombre := 'toda la ciudad';
    elsif coalesce(p ->> 'total', '') = 'planta' then
      select * into v_pl from tecnica.plantas pl where pl.codigo = lower(btrim(coalesce(p ->> 'planta', ''))) and pl.activa;
      if v_pl.id is null then perform tecnica.f_error('Escoja la planta', 'P0002'); end if;
      planta_id := v_pl.id;
      select array_agg(m.activo_id order by m.codigo), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(m.geom)), 3))
        into sectores, geom
        from redes.planta_sectores ps join redes.activo_vigente_mat m on m.activo_id = ps.sector_id
       where ps.planta_id = v_pl.id and ps.activo and m.prefijo = 'SEC' and not m.retirado and not m.oculto;
      if sectores is null then
        perform tecnica.f_error(format('La planta %s todavía no tiene sectores asignados: asígnelos primero, o declare el evento para toda la ciudad', v_pl.nombre));
      end if;
      zona_nombre := 'lo que surte la planta ' || v_pl.nombre;
    else perform tecnica.f_error('El evento total es de toda la ciudad o de una planta');
    end if;
  else perform tecnica.f_error('Escoja el alcance: por sectores, por círculo o total');
  end if;
  if not todo and (geom is null or ST_IsEmpty(geom)) then perform tecnica.f_error('No se pudo armar la zona del evento'); end if;
end $function$;
CREATE OR REPLACE FUNCTION public.geoportal_redes_evento_declarar(p_solicitante text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
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
    insert into redes.evento_suspension_reportes (evento_id, origen, reporte_externo_id, l116_reporte_id, dano_id, campo_reporte_id, tipo, modo, autor)
    select v_id, k.origen, k.reporte_externo_id, k.l116_reporte_id, k.dano_id, k.campo_reporte_id, 'asociar', 'al_declarar', v_email
      from redes.f_evento_candidatos(z.geom, z.todo, v_desde, v_dano) k
    returning id)
  select array_agg(id) into v_ids from hechas;
  perform redes.f_evento_marcar(v_ids, 'en_atencion', 'Asociado al evento de suspensión {evento} (ya estaba recibido al declararlo)', v_email);
  perform tecnica.f_auditar(v_email, 'redes_evento_declarar', 'EVS-' || lpad(v_cons::text, 6, '0'),
          jsonb_build_object('alcance', z.alcance, 'zona', z.zona_nombre, 'contratos', c -> 'contratos', 'sensibles', c -> 'sensibles', 'asociados', coalesce(cardinality(v_ids), 0)), null);
  return redes.f_evento_json(v_id, true) || jsonb_build_object('asociados_al_declarar', coalesce(cardinality(v_ids), 0));
end $function$;
CREATE OR REPLACE FUNCTION public.geoportal_redes_evento_catalogo(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
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
end $function$;
CREATE OR REPLACE FUNCTION redes.f_evento_json(p_evento bigint, p_geo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'codigo', e.codigo, 'estado', e.estado, 'alcance', e.alcance,
    'total', case when e.alcance = 'total' then case when e.todo then 'ciudad' else 'planta' end end,
    'planta', (select pl.nombre from tecnica.plantas pl where pl.id = e.planta_id),
    'zona', e.zona_nombre, 'causa', e.causa,
    'registro', coalesce((select d.codigo from redes.danos d where d.id = e.dano_id), (select i.codigo from redes.intervenciones i where i.id = e.intervencion_id)),
    'desde', e.desde, 'regreso_estimado', e.regreso_vigente, 'declarado_en', e.creado_en,
    'declarado_por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = e.autor), 'Funcionario de EMDUPAR'),
    'contratos', e.contratos, 'sensibles', e.sensibles,
    'reportes', (select jsonb_build_object('total', count(*), 'bot', count(*) filter (where r.origen = 'bot'), 'l116', count(*) filter (where r.origen = 'l116'),
                                           'danos', count(*) filter (where r.origen = 'dano'), 'campo', count(*) filter (where r.origen = 'campo')) from redes.f_evento_reportes(e.id) r),
    'franja', redes.f_evento_franja(e.zona_nombre, e.desde, e.causa, e.regreso_vigente),
    'fin', case when e.estado <> 'abierto' then jsonb_build_object('cuando', e.fin_en, 'motivo', e.fin_motivo,
              'por', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = e.fin_autor), 'Funcionario de EMDUPAR')) end,
    'circulo', case when e.alcance = 'circulo' then jsonb_build_object('lat', e.centro_lat, 'lon', e.centro_lon, 'radio_m', e.radio_m) end,
    'sectores', (select coalesce(jsonb_agg(m.codigo order by m.codigo), '[]'::jsonb) from redes.activo_vigente_mat m where m.activo_id = any (e.sectores)))
    || case when p_geo then jsonb_build_object('zona_geojson', case when e.geom is not null then ST_AsGeoJSON(ST_Multi(ST_SimplifyPreserveTopology(e.geom, 0.00002)), 6)::jsonb end) else '{}'::jsonb end
    from redes.v_evento_suspension e where e.id = p_evento $function$;
CREATE OR REPLACE FUNCTION public.geoportal_redes_planta_sectores_fijar(p_solicitante text, p_planta text, p_sectores text[], p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
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
end $function$;
CREATE OR REPLACE FUNCTION redes.f_rep_columnas(p_reporte text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare ubic jsonb := jsonb_build_array(redes.f_rep_col('sector', 'Sector', 'entero'), redes.f_rep_col('lat', 'Latitud', 'decimal', null, 6), redes.f_rep_col('lon', 'Longitud', 'decimal', null, 6));
begin
  return case p_reporte
  when 'levantamientos' then jsonb_build_array(
    redes.f_rep_col('codigo', 'Código', 'texto'), redes.f_rep_col('reportado', 'Reportado', 'fecha_hora'), redes.f_rep_col('servicio', 'Servicio', 'texto'),
    redes.f_rep_col('tipo', 'Qué se reportó', 'texto'), redes.f_rep_col('area', 'Área', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'),
    redes.f_rep_col('estado_desde', 'Estado desde', 'fecha_hora'), redes.f_rep_col('activo', 'Activo creado', 'texto'), redes.f_rep_col('fotos', 'Fotos', 'entero'),
    redes.f_rep_col('precision_m', 'Precisión del GPS', 'decimal', 'm', 1), redes.f_rep_col('precision_baja', 'Precisión baja', 'si_no'))
    || ubic || jsonb_build_array(redes.f_rep_col('reporto', 'Reportó (correo)', 'texto'))
  when 'valvulas' then jsonb_build_array(
    redes.f_rep_col('valvula', 'Válvula', 'texto'), redes.f_rep_col('cerrada', 'Cerrada', 'fecha_hora'), redes.f_rep_col('regreso_estimado', 'Regreso estimado vigente', 'fecha_hora'),
    redes.f_rep_col('cambios_regreso', 'Cambios del regreso estimado', 'entero'), redes.f_rep_col('abierta', 'Abierta', 'fecha_hora'),
    redes.f_rep_col('duracion_h', 'Duración', 'decimal', 'h', 1), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('dano', 'Daño', 'texto'),
    redes.f_rep_col('intervencion', 'Intervención', 'texto'))
    || ubic || jsonb_build_array(redes.f_rep_col('cerro', 'Cerró (correo)', 'texto'), redes.f_rep_col('abrio', 'Abrió (correo)', 'texto'))
  when 'eventos' then jsonb_build_array(
    redes.f_rep_col('evento', 'Evento', 'texto'), redes.f_rep_col('alcance', 'Alcance', 'texto'), redes.f_rep_col('zona', 'Zona', 'texto'), redes.f_rep_col('planta', 'Planta', 'texto'),
    redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('desde', 'Sin agua desde', 'fecha_hora'),
    redes.f_rep_col('regreso_estimado_inicial', 'Regreso estimado al declarar', 'fecha_hora'), redes.f_rep_col('regreso_estimado', 'Regreso estimado vigente', 'fecha_hora'),
    redes.f_rep_col('cambios_regreso', 'Cambios del regreso estimado', 'entero'), redes.f_rep_col('fin', 'Cerrado o anulado', 'fecha_hora'),
    redes.f_rep_col('duracion_h', 'Duración', 'decimal', 'h', 1), redes.f_rep_col('contratos', 'Contratos afectados', 'entero'),
    redes.f_rep_col('sensibles', 'Usuarios sensibles afectados', 'entero'), redes.f_rep_col('reportes', 'Reportes asociados', 'entero'),
    redes.f_rep_col('reportes_bot', 'Del bot', 'entero'), redes.f_rep_col('reportes_116', 'De la 116', 'entero'), redes.f_rep_col('reportes_danos', 'Daños', 'entero'),
    redes.f_rep_col('reportes_campo', 'De campo', 'entero'), redes.f_rep_col('dano', 'Daño', 'texto'), redes.f_rep_col('tipo', 'Tipo de daño o falla', 'texto'),
    redes.f_rep_col('causa', 'Causa del daño', 'texto'), redes.f_rep_col('intervencion', 'Intervención', 'texto'), redes.f_rep_col('tipo_intervencion', 'Tipo de intervención', 'texto'),
    redes.f_rep_col('declaro', 'Declaró (correo)', 'texto'), redes.f_rep_col('cerro', 'Cerró o anuló (correo)', 'texto'))
  when 'l116' then jsonb_build_array(
    redes.f_rep_col('reporte', 'Reporte de la 116', 'entero'), redes.f_rep_col('registrado_116', 'Registrado en la 116', 'fecha_hora'), redes.f_rep_col('dia', 'Día', 'fecha'),
    redes.f_rep_col('servicio', 'Servicio', 'texto'), redes.f_rep_col('causal', 'Causal', 'texto'), redes.f_rep_col('comuna', 'Comuna', 'texto'),
    redes.f_rep_col('contrato', 'Contrato', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('estado_desde', 'Estado desde', 'fecha_hora'),
    redes.f_rep_col('ubicacion', 'Ubicación', 'texto'), redes.f_rep_col('sector', 'Sector', 'entero'), redes.f_rep_col('subsector', 'Subsector', 'texto'),
    redes.f_rep_col('oculto', 'Oculto', 'si_no'), redes.f_rep_col('lat', 'Latitud', 'decimal', null, 6), redes.f_rep_col('lon', 'Longitud', 'decimal', null, 6))
  when 'bot' then jsonb_build_array(
    redes.f_rep_col('radicado', 'Radicado', 'texto'), redes.f_rep_col('recibido', 'Recibido', 'fecha_hora'), redes.f_rep_col('canal', 'Canal', 'texto'),
    redes.f_rep_col('tipo', 'Tipo', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('ultimo_movimiento', 'Último movimiento', 'fecha_hora'),
    redes.f_rep_col('dano', 'Daño', 'texto'), redes.f_rep_col('dano_estado', 'Estado del daño', 'texto'), redes.f_rep_col('fotos', 'Fotos', 'entero')) || ubic
  when 'sensibles' then jsonb_build_array(
    redes.f_rep_col('contrato', 'Contrato', 'texto'), redes.f_rep_col('tipo', 'Tipo', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'),
    redes.f_rep_col('desde', 'Desde', 'fecha_hora'), redes.f_rep_col('origen', 'Origen', 'texto'), redes.f_rep_col('sector', 'Sector', 'entero'))
  when 'activos' then jsonb_build_array(
    redes.f_rep_col('codigo', 'Código', 'texto'), redes.f_rep_col('tipo', 'Tipo', 'texto'), redes.f_rep_col('prefijo', 'Prefijo', 'texto'), redes.f_rep_col('sistema', 'Sistema', 'texto'),
    redes.f_rep_col('clase', 'Clase', 'texto'), redes.f_rep_col('material', 'Material', 'texto'), redes.f_rep_col('diametro_mm', 'Diámetro', 'decimal', 'mm', 1),
    redes.f_rep_col('longitud_m', 'Longitud', 'decimal', 'm', 2), redes.f_rep_col('profundidad_m', 'Profundidad', 'decimal', 'm', 2),
    redes.f_rep_col('instalacion', 'Instalación', 'fecha'), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('retirado', 'Retirado', 'si_no'),
    redes.f_rep_col('oculto', 'Oculto', 'si_no'), redes.f_rep_col('codigo_anterior', 'Código anterior', 'texto')) || ubic
  end;
end $function$;
CREATE OR REPLACE FUNCTION redes.f_rep_eventos(p_f jsonb, p_incl boolean, p_corte timestamp with time zone, p_cursor text, p_limite integer, p_solo_llave boolean DEFAULT false)
 RETURNS TABLE(k text, fila jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO 'redes', 'public', 'tecnica', 'extensions', 'pg_temp'
AS $function$
  with sg as (select redes.f_rep_sector_geom(p_f ->> 'sector') as g where p_f ? 'sector'),
  x as (select e.* from redes.v_evento_suspension e
         where e.creado_en <= p_corte
           and e.desde < (((p_f ->> 'hasta')::date + 1)::timestamp at time zone 'America/Bogota')
           and coalesce(e.fin_en, 'infinity'::timestamptz) >= ((p_f ->> 'desde')::date::timestamp at time zone 'America/Bogota')
           and (p_incl or e.estado <> 'anulado') and (not p_f ? 'sector' or e.todo or ST_Intersects(e.geom, (select g from sg)))
           and (p_cursor is null or e.id > p_cursor::bigint)
         order by e.id limit p_limite)
  select lpad(x.id::text, 19, '0'),
         case when p_solo_llave then null else jsonb_build_object('evento', x.codigo,
           'alcance', case when x.planta_id is not null then 'Planta' when x.alcance = 'sectores' then 'Sectores' when x.alcance = 'circulo' then 'Círculo' else 'Toda la ciudad' end,
           'zona', x.zona_nombre, 'planta', (select pl.nombre from tecnica.plantas pl where pl.id = x.planta_id), 'estado', redes.f_rep_rotulo(x.estado),
           'desde', redes.f_rep_ts(x.desde), 'regreso_estimado_inicial', redes.f_rep_ts(x.regreso_estimado), 'regreso_estimado', redes.f_rep_ts(x.regreso_vigente),
           'cambios_regreso', (select count(*) from redes.evento_suspension_eventos z where z.evento_id = x.id and z.tipo = 'regreso'),
           'fin', redes.f_rep_ts(x.fin_en), 'duracion_h', case when x.fin_en is not null then round(extract(epoch from x.fin_en - x.desde) / 3600.0, 1) end,
           'contratos', x.contratos, 'sensibles', x.sensibles, 'reportes', r.n, 'reportes_bot', r.bot, 'reportes_116', r.l116, 'reportes_danos', r.dano, 'reportes_campo', r.campo,
           'dano', cat.dano, 'tipo', cat.tipo, 'causa', cat.causa, 'intervencion', cat.intervencion, 'tipo_intervencion', cat.tipo_intervencion,
           'declaro', x.autor, 'cerro', x.fin_autor) end
    from x
    left join lateral (select case when x.dano_id is not null then d.codigo end as dano, td.nombre as tipo, i.codigo as intervencion, ti.nombre as tipo_intervencion,
                              case d.causa_clase when 'propia' then coalesce(ca.nombre, 'Propia') when 'terceros' then 'Terceros' || coalesce(': ' || tt.nombre, '')
                                                 when 'desconocida' then 'Desconocida' end as causa
                         from (select 1) u
                         left join redes.intervenciones i on i.id = x.intervencion_id
                         left join redes.tipos_intervencion ti on ti.codigo = i.tipo_codigo
                         left join redes.danos d on d.id = coalesce(x.dano_id, i.dano_id)
                         left join redes.tipos_dano td on td.codigo = d.tipo_codigo
                         left join redes.causas ca on ca.codigo = d.causa_codigo
                         left join redes.tipos_tercero tt on tt.codigo = d.tercero_tipo) cat on not p_solo_llave
    cross join lateral (select count(*) as n, count(*) filter (where v.origen = 'bot') as bot, count(*) filter (where v.origen = 'l116') as l116,
                                      count(*) filter (where v.origen = 'dano') as dano, count(*) filter (where v.origen = 'campo') as campo
                                 from redes.f_evento_reportes(x.id) v) r
   order by x.id $function$;
CREATE OR REPLACE FUNCTION redes.f_rep_leame(p_reporte text, p_f jsonb, p_incl boolean, p_email text, p_corte timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare c record; v_trae text[]; v_no text[] := array['Textos libres (descripciones, observaciones, motivos y causas escritas): pueden traer datos de personas y se ven solo en pantalla.',
                                                       'Teléfonos y nombres de suscriptores, del ciudadano que reporta o de terceros.'];
  v_filtros text[] := '{}'; v_ex text;
begin
  select * into c from redes.f_rep_catalogo() x where x.clave = p_reporte;
  v_trae := case p_reporte
    when 'levantamientos' then array['Una fila por punto de «Encontrar o reportar activo» (código LEV), con su estado vigente, el activo creado si se levantó y su ubicación.']
    when 'valvulas' then array['Una fila por cierre de una válvula, con el regreso estimado vigente, la apertura y la duración. Una válvula que sigue cerrada no tiene apertura.']
    when 'eventos' then array['Una fila por evento de suspensión vigente algún momento del periodo: zona, desde cuándo, regreso estimado (al declarar y el vigente), fin y duración.',
                              'Contratos y usuarios sensibles afectados como números (los que se calcularon al declarar) y los reportes asociados hoy, por origen.',
                              'El tipo de daño o falla y la causa del daño salen del catálogo del daño asociado (el del evento o el de su intervención); vacíos si el evento no tiene daño.']
    when 'l116' then array['Una fila por reporte de la línea 116 cargado, con su estado vigente, el contrato y la ubicación (por contrato o sin ubicar).']
    when 'bot' then array['Una fila por reporte recibido del bot, con su estado y el daño en que se convirtió, si se convirtió.']
    when 'sensibles' then array['Una fila por contrato marcado como usuario sensible, con su tipo y estado de hoy (inventario a la fecha de la descarga).']
    when 'activos' then array['Una fila por activo de la red tal como está hoy (inventario a la fecha de la descarga), con un punto del activo para ubicarlo.']
  end;
  if p_reporte = 'bot' then v_no := v_no || array['La descripción y la dirección que escribió el ciudadano.']; end if;
  if p_reporte = 'sensibles' then v_no := v_no || array['El nombre del suscriptor ni la palabra del nombre que lo marcó.']; end if;
  if p_reporte = 'eventos' then v_no := v_no || array['La causa escrita al declarar el evento ni los motivos de cierre o anulación (texto libre).']; end if;
  if c.periodo then
    v_filtros := array['Periodo: ' || to_char((p_f ->> 'desde')::date, 'DD/MM/YYYY') || ' a ' || to_char((p_f ->> 'hasta')::date, 'DD/MM/YYYY') || ' (según ' || c.periodo_sobre || ')'];
  else
    v_filtros := array['Inventario al ' || to_char(p_corte at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI')];
  end if;
  if p_f ? 'sector' then v_filtros := v_filtros || ('Sector: ' || (p_f ->> 'sector_nombre') || ' (' || (p_f ->> 'sector') || ')'); end if;
  if p_f ? 'tipo' then v_filtros := v_filtros || ('Tipo: ' || (p_f ->> 'tipo_nombre')); end if;
  if p_f ? 'sistema' then v_filtros := v_filtros || ('Sistema: ' || redes.f_rep_rotulo(p_f ->> 'sistema')); end if;
  v_ex := case when not c.usa_ocultos then null
               when p_reporte in ('levantamientos', 'bot', 'sensibles') then case when p_incl then 'Descartados: incluidos' else 'Descartados: no incluidos' end
               when p_reporte = 'eventos' then case when p_incl then 'Eventos anulados: incluidos' else 'Eventos anulados: no incluidos' end
               when p_reporte = 'activos' then case when p_incl then 'Retirados y ocultos: incluidos' else 'Retirados y ocultos: no incluidos' end
               else case when p_incl then 'Ocultos: incluidos' else 'Ocultos: no incluidos' end end;
  if v_ex is not null then v_filtros := v_filtros || v_ex; end if;
  return jsonb_build_object('que_trae', to_jsonb(v_trae), 'que_no_trae', to_jsonb(v_no), 'filtros', to_jsonb(v_filtros),
                            'generado_por', p_email, 'generado_en', redes.f_rep_ts(p_corte));
end $function$;
CREATE OR REPLACE FUNCTION tecnica.f_rep_columnas(p_reporte text, p_f jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $function$
declare c jsonb; v_desde date := (p_f ->> 'desde')::date; v_hasta date := (p_f ->> 'hasta')::date;
  fin_envio jsonb := jsonb_build_array(
    tecnica.f_rep_col('fuera_referencia', 'Valores fuera de referencia', 'entero'),
    tecnica.f_rep_col('estado', 'Estado', 'texto'),
    tecnica.f_rep_col('fuente', 'Fuente', 'texto'),
    tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'),
    tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'),
    tecnica.f_rep_col('envio', 'Envío (identificador)', 'texto'));
begin
  case p_reporte
  when 'entrada' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('planta', 'Planta', 'texto'))
         || tecnica.f_rep_cols_variables('entrada', v_desde, v_hasta)
         || jsonb_build_array(tecnica.f_rep_col('coagulante', 'Coagulante', 'texto'), tecnica.f_rep_col('dosis_ppm', 'Dosis de coagulante', 'decimal', 'ppm', 2))
         || fin_envio;
  when 'salida' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('planta', 'Planta', 'texto'),
                           tecnica.f_rep_col('punto', 'Punto', 'texto'), tecnica.f_rep_col('punto_nombre', 'Nombre del punto', 'texto'))
         || tecnica.f_rep_cols_variables('salida', v_desde, v_hasta) || fin_envio;
  when 'muestreo' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('punto', 'Punto', 'texto'),
                           tecnica.f_rep_col('punto_nombre', 'Nombre del punto', 'texto'), tecnica.f_rep_col('tipo_punto', 'Tipo de punto', 'texto'),
                           tecnica.f_rep_col('zona', 'Zona', 'texto'), tecnica.f_rep_col('numero_informe', 'Número en el informe', 'entero'))
         || tecnica.f_rep_cols_variables('muestreo', v_desde, v_hasta) || fin_envio;
  when 'uso_quimicos' then
    c := jsonb_build_array(tecnica.f_rep_col('movimiento', 'Movimiento', 'entero'), tecnica.f_rep_col('dia', 'Día', 'fecha'), tecnica.f_rep_col('quimico', 'Químico', 'texto'),
                           tecnica.f_rep_col('planta', 'Planta', 'texto'), tecnica.f_rep_col('para_que', 'Para qué', 'texto'),
                           tecnica.f_rep_col('cantidad', 'Cantidad digitada', 'decimal', null, 3), tecnica.f_rep_col('unidad', 'Unidad digitada', 'texto'),
                           tecnica.f_rep_col('cantidad_kg', 'Cantidad', 'decimal', 'kg', 3), tecnica.f_rep_col('dosis_optima_ppm', 'Dosis óptima vigente', 'decimal', 'ppm', 2),
                           tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'), tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'));
  when 'entrada_quimicos' then
    c := jsonb_build_array(tecnica.f_rep_col('movimiento', 'Movimiento', 'entero'), tecnica.f_rep_col('dia', 'Día', 'fecha'), tecnica.f_rep_col('quimico', 'Químico', 'texto'),
                           tecnica.f_rep_col('cantidad', 'Cantidad digitada', 'decimal', null, 3), tecnica.f_rep_col('unidad', 'Unidad digitada', 'texto'),
                           tecnica.f_rep_col('cantidad_kg', 'Cantidad', 'decimal', 'kg', 3), tecnica.f_rep_col('proveedor', 'Proveedor', 'texto'),
                           tecnica.f_rep_col('remision', 'Remisión', 'texto'), tecnica.f_rep_col('lote_fabricante', 'Lote del fabricante', 'texto'),
                           tecnica.f_rep_col('vence', 'Vence', 'fecha'), tecnica.f_rep_col('foto_remision', 'Foto de la remisión', 'enlace'),
                           tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'), tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'));
  when 'kardex_quimicos' then
    c := jsonb_build_array(tecnica.f_rep_col('quimico', 'Químico', 'texto'), tecnica.f_rep_col('bodega', 'Bodega', 'texto'), tecnica.f_rep_col('dia', 'Día', 'fecha'),
                           tecnica.f_rep_col('movimiento', 'Movimiento', 'entero'), tecnica.f_rep_col('tipo', 'Tipo', 'texto'), tecnica.f_rep_col('planta', 'Planta', 'texto'),
                           tecnica.f_rep_col('detalle', 'Detalle', 'texto'), tecnica.f_rep_col('entra_kg', 'Entra', 'decimal', 'kg', 3),
                           tecnica.f_rep_col('sale_kg', 'Sale', 'decimal', 'kg', 3), tecnica.f_rep_col('conteo_kg', 'Conteo físico', 'decimal', 'kg', 3),
                           tecnica.f_rep_col('saldo_kg', 'Saldo', 'decimal', 'kg', 3), tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'));
  when 'eventos_planta' then
    c := jsonb_build_array(tecnica.f_rep_col('evento', 'Evento', 'texto'), tecnica.f_rep_col('planta', 'Planta', 'texto'), tecnica.f_rep_col('estado', 'Estado', 'texto'),
                           tecnica.f_rep_col('suspendido', 'Suspendido desde', 'fecha_hora'), tecnica.f_rep_col('regreso_estimado_inicial', 'Regreso estimado al declarar', 'fecha_hora'),
                           tecnica.f_rep_col('regreso_estimado', 'Regreso estimado vigente', 'fecha_hora'), tecnica.f_rep_col('cambios_regreso', 'Cambios del regreso estimado', 'entero'),
                           tecnica.f_rep_col('reanudado', 'Reanudado', 'fecha_hora'), tecnica.f_rep_col('duracion_h', 'Duración', 'decimal', 'h', 1),
                           tecnica.f_rep_col('contratos', 'Contratos afectados', 'entero'), tecnica.f_rep_col('sensibles', 'Usuarios sensibles afectados', 'entero'),
                           tecnica.f_rep_col('reportes', 'Reportes asociados', 'entero'), tecnica.f_rep_col('dano', 'Daño', 'texto'),
                           tecnica.f_rep_col('tipo', 'Tipo de daño o falla', 'texto'), tecnica.f_rep_col('causa', 'Causa del daño', 'texto'),
                           tecnica.f_rep_col('intervencion', 'Intervención', 'texto'), tecnica.f_rep_col('tipo_intervencion', 'Tipo de intervención', 'texto'),
                           tecnica.f_rep_col('declaro', 'Declaró (correo)', 'texto'),
                           tecnica.f_rep_col('cerro', 'Cerró o anuló (correo)', 'texto'));
  when 'fuera_referencia' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('formulario', 'Formulario', 'texto'),
                           tecnica.f_rep_col('planta', 'Planta', 'texto'), tecnica.f_rep_col('punto', 'Punto', 'texto'), tecnica.f_rep_col('variable', 'Variable', 'texto'),
                           tecnica.f_rep_col('valor', 'Valor', 'decimal', null, 6), tecnica.f_rep_col('unidad', 'Unidad', 'texto'), tecnica.f_rep_col('marca', 'Marca', 'texto'),
                           tecnica.f_rep_col('ref_min', 'Referencia mínima', 'decimal', null, 6), tecnica.f_rep_col('ref_max', 'Referencia máxima', 'decimal', null, 6),
                           tecnica.f_rep_col('ref_origen', 'Origen de la referencia', 'texto'), tecnica.f_rep_col('revision', 'Revisión', 'texto'),
                           tecnica.f_rep_col('revisado_por', 'Revisó (correo)', 'texto'), tecnica.f_rep_col('revisado_en', 'Revisado', 'fecha_hora'),
                           tecnica.f_rep_col('excluido', 'Excluido', 'si_no'), tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'),
                           tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'), tecnica.f_rep_col('registro_id', 'Registro', 'entero'));
  else perform tecnica.f_error('Ese reporte no existe.');
  end case;
  return c;
end $function$;
CREATE OR REPLACE FUNCTION tecnica.f_rep_eventos_planta(p_f jsonb, p_incl boolean, p_corte timestamp with time zone, p_cursor text, p_limite integer)
 RETURNS TABLE(k text, fila jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'tecnica', 'redes', 'pg_temp'
AS $function$
  select lpad(e.id::text, 19, '0'),
         jsonb_build_object('evento', e.codigo, 'planta', pl.nombre, 'estado', case e.estado when 'abierto' then 'Abierto' when 'cerrado' then 'Cerrado' else 'Anulado' end,
           'suspendido', tecnica.f_rep_ts(e.desde), 'regreso_estimado_inicial', tecnica.f_rep_ts(e.regreso_estimado), 'regreso_estimado', tecnica.f_rep_ts(e.regreso_vigente),
           'cambios_regreso', (select count(*) from redes.evento_suspension_eventos x where x.evento_id = e.id and x.tipo = 'regreso'),
           'reanudado', case when e.estado = 'cerrado' then tecnica.f_rep_ts(e.fin_en) end,
           'duracion_h', case when e.estado = 'cerrado' then round(extract(epoch from e.fin_en - e.desde) / 3600.0, 1) end,
           'contratos', e.contratos, 'sensibles', e.sensibles, 'reportes', (select count(*) from redes.f_evento_reportes(e.id)),
           'dano', cat.dano, 'tipo', cat.tipo, 'causa', cat.causa, 'intervencion', cat.intervencion, 'tipo_intervencion', cat.tipo_intervencion,
           'declaro', e.autor, 'cerro', e.fin_autor)
    from redes.v_evento_suspension e join tecnica.plantas pl on pl.id = e.planta_id
    -- del catálogo (David, 20-nov): el tipo y la causa del daño asociado (el del evento o el de su intervención) y el tipo de la intervención; la causa ESCRITA no
    left join lateral (select case when e.dano_id is not null then d.codigo end as dano, td.nombre as tipo, i.codigo as intervencion, ti.nombre as tipo_intervencion,
                              case d.causa_clase when 'propia' then coalesce(ca.nombre, 'Propia') when 'terceros' then 'Terceros' || coalesce(': ' || tt.nombre, '')
                                                 when 'desconocida' then 'Desconocida' end as causa
                         from (select 1) u
                         left join redes.intervenciones i on i.id = e.intervencion_id
                         left join redes.tipos_intervencion ti on ti.codigo = i.tipo_codigo
                         left join redes.danos d on d.id = coalesce(e.dano_id, i.dano_id)
                         left join redes.tipos_dano td on td.codigo = d.tipo_codigo
                         left join redes.causas ca on ca.codigo = d.causa_codigo
                         left join redes.tipos_tercero tt on tt.codigo = d.tercero_tipo) cat on true
   where e.planta_id is not null and e.creado_en <= p_corte
     and e.desde < (((p_f ->> 'hasta')::date + 1)::timestamp at time zone 'America/Bogota')
     and coalesce(e.fin_en, 'infinity'::timestamptz) >= ((p_f ->> 'desde')::date::timestamp at time zone 'America/Bogota')
     and (p_incl or e.estado <> 'anulado') and (p_f ->> 'planta' is null or pl.codigo = p_f ->> 'planta')
     and (p_cursor is null or e.id > p_cursor::bigint)
   order by e.id
   limit p_limite $function$;
CREATE OR REPLACE FUNCTION tecnica.f_rep_leame(p_reporte text, p_f jsonb, p_incl boolean, p_email text, p_corte timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $function$
declare c record; v_trae text[]; v_no text[] := array['Textos libres (descripciones, observaciones, motivos y notas): pueden traer datos de personas y se ven solo en pantalla.',
                                                       'Teléfonos y nombres de suscriptores o de terceros.'];
  v_filtros text[]; v_ex text;
begin
  select * into c from tecnica.f_rep_catalogo() x where x.clave = p_reporte;
  v_trae := case p_reporte
    when 'entrada' then array['Una fila por envío del formulario Entrada y por planta, con una columna por variable (las unidades van en el encabezado).',
                              'La dosis de coagulante registrada con el mismo envío («Otro» sale sin su nombre).',
                              'Cuántos valores del envío quedaron fuera de referencia y si el envío está vigente o excluido.']
    when 'salida' then array['Una fila por envío del formulario Salida y por lugar (planta o punto), con una columna por variable.',
                             'Cuántos valores del envío quedaron fuera de referencia y si el envío está vigente o excluido.']
    when 'muestreo' then array['Una fila por muestra (envío de un punto), con una columna por parámetro.',
                               'Si los resultados de una misma muestra llegaron en varios envíos, sale una fila por envío.',
                               'Cuántos valores quedaron fuera de referencia y si el envío está vigente o excluido.']
    when 'uso_quimicos' then array['Una fila por uso registrado (formulario Uso de químicos), con la cantidad digitada y en kg, y la dosis óptima vigente al registrarlo.']
    when 'entrada_quimicos' then array['Una fila por entrada a la bodega (formulario Entrada de químicos).',
                                       'La foto de la remisión va como enlace: se abre en el geoportal con su sesión (solo supervisor de planta y administrador).']
    when 'kardex_quimicos' then array['Por químico: el saldo al empezar el periodo, cada movimiento (inventario inicial, entrada, uso y ajuste por conteo) con el saldo corrido, y el saldo al cierre.',
                                      'Orden: por día y, el mismo día, por número de movimiento. Un inventario inicial reemplaza el saldo por lo contado.',
                                      'Antes del primer inventario inicial de un químico el saldo es desconocido y la celda va vacía.',
                                      'Hoy hay una sola bodega de químicos.']
    when 'eventos_planta' then array['Una fila por evento de suspensión declarado para una planta, vigente algún momento del periodo: suspensión, regreso estimado (al declarar y el vigente), reanudación y duración.',
                                     'Contratos y usuarios sensibles afectados como números (los que se calcularon al declarar), y cuántos reportes tiene asociados hoy.',
                                     'El tipo de daño o falla y la causa del daño salen del catálogo del daño asociado (el del evento o el de su intervención); vacíos si el evento no tiene daño.']
    when 'fuera_referencia' then array['Una fila por valor de Entrada, Salida o Muestreo fuera de su referencia vigente, con la revisión vigente (la más reciente): su estado, quién y cuándo. No trae el historial de revisiones.']
  end;
  if p_reporte = 'eventos_planta' then v_no := v_no || array['La causa escrita al declarar el evento ni los motivos de cierre o anulación (texto libre).']; end if;
  if p_reporte = 'fuera_referencia' then v_no := v_no || array['La nota de la revisión (texto libre).']; end if;
  if p_reporte in ('uso_quimicos', 'entrada_quimicos', 'kardex_quimicos') then v_no := v_no || array['Los motivos de inventarios y ajustes (texto libre).']; end if;
  v_filtros := array['Periodo: ' || to_char((p_f ->> 'desde')::date, 'DD/MM/YYYY') || ' a ' || to_char((p_f ->> 'hasta')::date, 'DD/MM/YYYY') || ' (según ' || c.periodo_sobre || ')'];
  if p_f ? 'planta' then v_filtros := v_filtros || ('Planta: ' || (p_f ->> 'planta_nombre')); end if;
  if p_f ? 'punto' then v_filtros := v_filtros || ('Punto: ' || (p_f ->> 'punto') || ' · ' || (p_f ->> 'punto_nombre')); end if;
  if p_f ? 'zona' then v_filtros := v_filtros || ('Zona: ' || initcap(p_f ->> 'zona')); end if;
  if p_f ? 'quimico' then v_filtros := v_filtros || ('Químico: ' || (p_f ->> 'quimico_nombre')); end if;
  if p_f ? 'formulario' then v_filtros := v_filtros || ('Formulario: ' || initcap(p_f ->> 'formulario')); end if;
  v_ex := case when not c.usa_excluidos then null
               when p_reporte = 'eventos_planta' then case when p_incl then 'Eventos anulados: incluidos' else 'Eventos anulados: no incluidos' end
               else case when p_incl then 'Valores excluidos: incluidos' else 'Valores excluidos: no incluidos' end end;
  if v_ex is not null then v_filtros := v_filtros || v_ex; end if;
  return jsonb_build_object('que_trae', to_jsonb(v_trae), 'que_no_trae', to_jsonb(v_no), 'filtros', to_jsonb(v_filtros),
                            'generado_por', p_email, 'generado_en', tecnica.f_rep_ts(p_corte));
end $function$;
-- 2. los sectores por planta vuelven a estar activos: los del último hecho de cada planta antes de la migración (con un hecho nuevo y su motivo)
with mig as (select planta_id, min(id) as id from redes.planta_sector_eventos where motivo = 'el sistema es único; los sectores pasan a los tubos de salida' group by planta_id),
     antes as (select distinct on (e.planta_id) e.planta_id, e.sectores from redes.planta_sector_eventos e join mig on mig.planta_id = e.planta_id and e.id < mig.id order by e.planta_id, e.id desc),
     act as (update redes.planta_sectores ps set activo = true from antes a where ps.planta_id = a.planta_id and ps.sector_id = any (a.sectores) and not ps.activo returning ps.planta_id)
insert into redes.planta_sector_eventos (planta_id, sectores, motivo, autor)
select a.planta_id, a.sectores, 'reversa del corte de eventos: vuelven los sectores por planta', 'reversa@redes_eventos_origen_tubos' from antes a;
-- 3. lo nuevo (las tablas de hechos están vacías: lo comprobó la guardia)
drop function redes.f_evento_origen(bigint);
drop function redes.f_tubo_zona(text[]);
drop function public.geoportal_redes_evento_causal_fijar(text,text,text,boolean,text);
drop function public.geoportal_redes_tubo_sectores_fijar(text,text,text[],text);
drop table redes.evento_tubos;
drop table redes.evento_causal;
drop table redes.evento_causal_eventos;
drop table redes.evento_causales;
drop table redes.tubo_sector_eventos;
drop table redes.tubo_sectores;
drop function redes.f_tubo_es_distribucion();
notify pgrst, 'reload schema';
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_eventos_origen_tubos', 'reversa_redes_eventos_origen_tubos', null, jsonb_build_object('motivo', 'reversa del corte de eventos (origen y tubos)'), null);
commit;
