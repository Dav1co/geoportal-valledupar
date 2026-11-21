-- =====================================================================
-- ARNÉS LOCAL DEL MAPA DE LA PTAR (solo la base local del Code C; NO va a producción). Requiere la migración de PTAR-1 y la carga inicial del mapa
-- (914 elementos con el GeoJSON del 21-nov: 35 del dibujo y 879 copiados de redes). Llama las RPC como la Edge: rol service_role, statement_timeout 30 s,
-- lock_timeout 8 s. Todo en una transacción que termina en un ERROR a propósito: no queda nada.
-- =====================================================================
\set ON_ERROR_STOP 1
begin;
set local client_min_messages = warning;
insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias)
values ('arnes.ptar.jefe@emdupar.gov.co', 'ARNES Jefe de la PTAR', 'consulta', true, true, 'sin_restriccion', 'todos');
insert into tecnica.alcance_eventos (persona, alcance, tipo_evento, motivo, autor) values ('arnes.ptar.jefe@emdupar.gov.co', 'ptar', 'asignar', 'ARNES jefe de la PTAR', 'arnes@emdupar.gov.co'),
  ('arnes.ptar.jefe@emdupar.gov.co', 'ptap', 'quitar', 'ARNES jefe de la PTAR', 'arnes@emdupar.gov.co');
create temp table _t (paso text, ms numeric, dato text);
create temp table _c as select (select codigo from tecnica.elementos_planta where origen = 'redes' and tipo = 'tramo' and activo order by codigo limit 1) as tramo;
grant all on _t, _c to service_role;
set local role service_role;
set local statement_timeout = '30s';
set local lock_timeout = '8s';
do $$
declare t0 timestamptz; j jsonb; i integer; v_max numeric := 0;
begin
  for i in 1..5 loop
    t0 := clock_timestamp(); j := public.geoportal_tec_ptar_mapa('arnes.ptar.jefe@emdupar.gov.co', 'ptar');
    v_max := greatest(v_max, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
  insert into _t values ('mapa (peor de 5)', round(v_max, 1), (j ->> 'total') || ' elementos, ' || length(j::text) || ' bytes, ' || (j -> 'por_tipo')::text);
  t0 := clock_timestamp(); j := public.geoportal_tec_ptar_elemento('arnes.ptar.jefe@emdupar.gov.co', 'PTAR-PER');
  insert into _t values ('ficha del perímetro', round(extract(epoch from clock_timestamp() - t0) * 1000, 1), (j -> 'medida')::text);
  t0 := clock_timestamp(); j := public.geoportal_tec_ptar_elemento('arnes.ptar.jefe@emdupar.gov.co', (select tramo from _c));
  insert into _t values ('ficha de un conducto copiado de redes', round(extract(epoch from clock_timestamp() - t0) * 1000, 1), coalesce(j ->> 'activo', '') || ' ' || coalesce((j -> 'medida')::text, ''));
  t0 := clock_timestamp(); j := public.geoportal_tec_ptar_alias_fijar('arnes.ptar.jefe@emdupar.gov.co', 'PTAR-LAG-1', 'A-N1', 'ARNES nombre corto de la laguna');
  insert into _t values ('alias', round(extract(epoch from clock_timestamp() - t0) * 1000, 1), j::text);
  t0 := clock_timestamp(); j := public.geoportal_tec_ptar_perfil('arnes.ptar.jefe@emdupar.gov.co');
  insert into _t values ('perfil', round(extract(epoch from clock_timestamp() - t0) * 1000, 1), j::text);
end $$;
reset role;
do $$
declare v_txt text; v_ok boolean;
begin
  select string_agg(format('  %s: %s ms · %s', paso, ms, left(dato, 220)), E'\n'), bool_and(ms < 2000) and (select dato like '914 elementos%' from _t where paso like 'mapa%')
    into v_txt, v_ok from _t;
  raise exception E'ARNÉS DEL MAPA DE LA PTAR (esperado: este ERROR deshace todo)\n%\nRESULTADO: %', v_txt, case when v_ok then 'cada llamada en menos de 2 s y 914 elementos — SIN FALLAS' else 'REVISAR' end;
end $$;
