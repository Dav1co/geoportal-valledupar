-- =====================================================================
-- DOBLES SOLO LOCALES para el Motor SCRR, corte 2 (se cargan en la plantilla local «scrr_plantilla»; NUNCA en Supabase).
-- En producción existen de verdad: hechos.facturacion_sspd (tabla de texto del ETL mensual, 223 mil filas) y redes.f_eventos_del_contrato(text)
-- (aviso de evento por contrato, Técnica, publicado). El doble tiene la MISMA clase de objeto (tabla y función) y la misma firma.
-- =====================================================================
create table if not exists hechos.facturacion_sspd (
  periodo text, contrato text, ruta_lectura text, serial_medidor text, estado_medidor text, determinacion_consumo text,
  lectura_anterior text, lectura_actual text, consumo_periodo text, total_facturado text);
create index if not exists facturacion_sspd_periodo_idx on hechos.facturacion_sspd (periodo);
comment on table hechos.facturacion_sspd is 'DOBLE LOCAL (Code A, SCRR corte 2): misma clase y columnas que la tabla del ETL.';

-- DOBLE de la función de Técnica: devuelve los eventos abiertos que tocan el contrato. Aquí se alimenta de una tabla local de prueba.
create table if not exists redes.zz_doble_eventos_contrato (contrato text not null, evento_id bigint not null);
create or replace function redes.f_eventos_del_contrato(p_contrato text) returns table (evento_id bigint, orden integer)
language sql stable security definer set search_path = redes, public, pg_temp as $$
  select d.evento_id, (row_number() over (order by d.evento_id))::integer from redes.zz_doble_eventos_contrato d where d.contrato = p_contrato $$;
comment on function redes.f_eventos_del_contrato(text) is 'DOBLE LOCAL (Code A, SCRR corte 2): en producción es la función del aviso de evento por contrato.';
revoke all on function redes.f_eventos_del_contrato(text) from public;

-- DOBLE de redes.f_eventos_abiertos(): en producción devuelve setof redes.eventos_suspension; el SCRR solo pregunta si hay alguno abierto
-- (para no consultar contrato por contrato cuando no hay eventos). Aquí: los eventos de la tabla local de prueba.
create table if not exists redes.zz_doble_eventos_abiertos (id bigint primary key);
create or replace function redes.f_eventos_abiertos() returns setof redes.zz_doble_eventos_abiertos
language sql stable security definer set search_path = redes, pg_temp as $$ select distinct d.evento_id from redes.zz_doble_eventos_contrato d $$;
comment on function redes.f_eventos_abiertos() is 'DOBLE LOCAL (Code A, SCRR corte 2): en producción devuelve los eventos de suspensión abiertos.';
revoke all on function redes.f_eventos_abiertos() from public;
