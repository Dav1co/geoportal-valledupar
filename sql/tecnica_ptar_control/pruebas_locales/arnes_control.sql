-- =====================================================================
-- ARNÉS LOCAL DEL SISTEMA DE CONTROL PTAR (solo la base local del Code C; NO va a producción). Requiere PTAR-1, PTAR-3 y la carga del mapa.
-- UN AÑO de Caracterización simulado: caudal diario en los 4 puntos y laboratorio semanal (DBO5, DQO, SST, N y P), con algunas exclusiones; además, la red de
-- registros que ya hay. Llama las RPC como la Edge: service_role, statement_timeout 30 s y lock_timeout 8 s. Termina en ERROR a propósito: no queda nada.
-- =====================================================================
\set ON_ERROR_STOP 1
begin;
set local client_min_messages = warning;
insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias)
values ('arnes.ptar3.jefe@emdupar.gov.co', 'ARNES Jefe de la PTAR', 'consulta', true, true, 'sin_restriccion', 'todos');
insert into tecnica.alcance_eventos (persona, alcance, tipo_evento, motivo, autor) values ('arnes.ptar3.jefe@emdupar.gov.co', 'ptar', 'asignar', 'ARNES jefe de la PTAR', 'arnes@emdupar.gov.co');
insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor, registrado_en)
select gen_random_uuid(), 'ptar_caracterizacion', v.id, p.id, 300 + random() * 200, d.f, '08:00', 'arnes.ptar3.jefe@emdupar.gov.co', d.f::timestamp at time zone 'America/Bogota' + interval '9 hours'
  from generate_series(0, 364) g(n) cross join lateral (select (clock_timestamp() at time zone 'America/Bogota')::date - g.n as f) d
  join tecnica.puntos p on p.tipo = 'ptar' join tecnica.variables v on v.codigo = 'ar_caudal';
insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor, registrado_en)
select gen_random_uuid(), 'ptar_caracterizacion', v.id, p.id, 50 + random() * 300, d.f, '09:00', 'arnes.ptar3.jefe@emdupar.gov.co', d.f::timestamp at time zone 'America/Bogota' + interval '10 hours'
  from generate_series(0, 51) g(n) cross join lateral (select (clock_timestamp() at time zone 'America/Bogota')::date - 7 * g.n as f) d
  join tecnica.puntos p on p.tipo = 'ptar' join tecnica.variables v on v.codigo in ('ar_dbo5', 'ar_dqo', 'ar_sst', 'ar_nitrogeno_total', 'ar_fosforo_total');
insert into tecnica.exclusiones (registro_id, accion, motivo, autor)
select r.id, 'EXCLUIR', 'ARNES valor mal digitado', 'arnes@emdupar.gov.co' from tecnica.registros r where r.formulario = 'ptar_caracterizacion' and random() < 0.02;
analyze tecnica.registros; analyze tecnica.exclusiones;
create temp table _t (paso text, ms numeric, dato text);
create temp table _c as select (select count(*) from tecnica.registros where formulario = 'ptar_caracterizacion') as n,
                               (select count(*) from tecnica.elementos_planta e join tecnica.instalaciones i on i.id = e.instalacion_id where i.codigo = 'ptar' and e.activo) as elementos;
grant all on _t, _c to service_role;
set local role service_role;
set local statement_timeout = '30s';
set local lock_timeout = '8s';
do $$
declare t0 timestamptz; j jsonb; i integer; v_max numeric := 0;
begin
  for i in 1..5 loop
    t0 := clock_timestamp(); j := public.geoportal_tec_ptar_mapa('arnes.ptar3.jefe@emdupar.gov.co', 'ptar');
    v_max := greatest(v_max, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
  insert into _t values ('mapa con los estados (peor de 5)', round(v_max, 1), (j ->> 'total') || ' elementos, ' || length(j::text) || ' bytes; registros de la Caracterización: ' || (select n from _c));
  v_max := 0;
  for i in 1..5 loop
    t0 := clock_timestamp(); j := public.geoportal_tec_ptar_elemento('arnes.ptar3.jefe@emdupar.gov.co', 'PTAR-PM-AFL');
    v_max := greatest(v_max, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
  insert into _t values ('ficha del afluente con sus 9 parámetros (peor de 5)', round(v_max, 1), j ->> 'estado');
  t0 := clock_timestamp(); j := public.geoportal_tec_obtener_formulario('arnes.ptar3.jefe@emdupar.gov.co', 'ptar_caracterizacion');
  insert into _t values ('formulario de la Caracterización', round(extract(epoch from clock_timestamp() - t0) * 1000, 1), jsonb_array_length(j -> 'puntos') || ' puntos');
  t0 := clock_timestamp(); j := public.geoportal_tec_registrar_medicion(p_solicitante => 'arnes.ptar3.jefe@emdupar.gov.co', p_formulario => 'ptar_caracterizacion', p_planta => null,
    p_hora_muestra => '07:00', p_valores => '[{"variable":"ar_caudal","valor":"401.2"}]'::jsonb, p_punto => 'PTAR-EFL');
  insert into _t values ('registrar un caudal', round(extract(epoch from clock_timestamp() - t0) * 1000, 1), j ->> 'guardados');
end $$;
reset role;
do $$
declare v_txt text; v_ok boolean;
begin
  select string_agg(format('  %s: %s ms · %s', paso, ms, left(dato, 200)), E'\n'), bool_and(ms < 2000) and (select dato like (select elementos from _c) || ' elementos%' from _t where paso like 'mapa%')
    into v_txt, v_ok from _t;
  raise exception E'ARNÉS DEL SISTEMA DE CONTROL PTAR (esperado: este ERROR deshace todo)\n%\nRESULTADO: %', v_txt, case when v_ok then 'cada llamada en menos de 2 s — SIN FALLAS' else 'REVISAR' end;
end $$;
