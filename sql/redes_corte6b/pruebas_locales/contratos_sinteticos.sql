-- Contratos SINTÉTICOS (ningún dato real): 111.950 predios sobre los tramos de acueducto publicados, corridos hasta ~45 m; su cartera diaria (con un nombre
-- y una dirección inventados, 2 cortes por contrato para probar que se toma el último), y su ficha con 6 meses de consumo. Además: 300 predios con el
-- contrato «0», el comodín 99999999 y 500 contratos repetidos en dos predios. Y muestras de cloro y turbiedad para los puntos MUE.
select setseed(0.27);
create temp table _red as select row_number() over (order by activo_id) as n, geom from redes.activo_vigente_mat where prefijo = 'RED' and not retirado;
insert into public.catastro_valledupar (cod_usuario, direccion, barrio, geom)
select (100000 + g)::text, 'CL ' || (g % 60) || ' # ' || (g % 30) || '-' || (g % 90), 'BARRIO SINTETICO ' || (g % 40),
       ST_SetSRID(ST_Translate(ST_LineInterpolatePoint(t.geom, random()), (random() - 0.5) * 0.0008, (random() - 0.5) * 0.0008), 4326)
  from generate_series(1, 111950) g
  join _red t on t.n = 1 + (g % (select count(*) from _red));
update public.catastro_valledupar set cod_usuario = '0' where id <= 300;
update public.catastro_valledupar set cod_usuario = '99999999' where id = 301;
insert into public.catastro_valledupar (cod_usuario, direccion, barrio, geom) select cod_usuario, direccion, barrio, ST_Translate(geom, 0.001, 0.001) from public.catastro_valledupar where id between 1000 and 1499;
insert into public.cartera_suscripcion (contrato, estado, nombre, telefono, direccion, barrio, categoria, deuda_total, periodo_carga)
select cod_usuario, case when id % 9 = 0 then 'RETIRADO' when id % 23 = 0 then 'SUSPENDIDO' else 'ACTIVO' end, 'SUSCRIPTOR SINTETICO ' || id, '3000000000',
       'DIRECCION CARTERA ' || id, 'BARRIO CARTERA ' || (id % 40), case when id % 7 = 0 then '2 Comercial' else '1 Residencial' end, 99999, p
  from public.catastro_valledupar cross join (values ('20261113'), ('20261114')) x(p) where cod_usuario ~ '^[1-9][0-9]+$' and id <= 112250;
insert into bi_interno.ficha_contrato (contrato, periodo_ultimo, uso, consumo_meses, cons_prom, meses_con_lectura, medidor_anios, medidor_fecha_estado)
select distinct on (cod_usuario) cod_usuario, '202610', case when id % 7 = 0 then 'Comercial' else 'Residencial' end,
       (select jsonb_agg(jsonb_build_object('periodo', p, 'sin_dato', p = '202606', 'm3', case when p = '202606' then null else 5 + (id % 20) + k end, 'metodo', 'lectura', 'lectura_real', p <> '202606', 'causal', '99 LECTURA NORMAL') order by k)
          from unnest(array['202605', '202606', '202607', '202608', '202609', '202610']) with ordinality u(p, k)),
       7 + (id % 20), 5, case when id % 5 = 0 then null else id % 25 end, 'real'
  from public.catastro_valledupar where cod_usuario ~ '^[1-9][0-9]+$' and cod_usuario <> '99999999' order by cod_usuario, id;
insert into bi_interno.ficha_contrato_estado (id, firma, filas, calculado_en, duracion_ms) values (1, 'sintetica', (select count(*) from bi_interno.ficha_contrato), clock_timestamp(), 1)
on conflict (id) do update set calculado_en = clock_timestamp();
-- muestras: el primer punto MUE con cloro bajo (fuera), el segundo con todo dentro, el tercero con una muestra vieja
insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor)
select gen_random_uuid(), 'muestreo', v.id, p.id, x.valor, (clock_timestamp() at time zone 'America/Bogota')::date - x.dias, '07:00', 'zt.oper@emdupar.gov.co'
  from (values (1, 'cloro_residual_libre', 0.1, 0), (1, 'turbiedad', 0.5, 0), (2, 'cloro_residual_libre', 1.1, 1), (2, 'turbiedad', 0.8, 1), (3, 'cloro_residual_libre', 1.0, 90)) x(n, cod, valor, dias)
  join tecnica.variables v on v.codigo = x.cod
  join (select id, row_number() over (order by codigo) as n from tecnica.puntos where tipo = 'muestreo' and activo) p on p.n = x.n;
analyze public.catastro_valledupar; analyze public.cartera_suscripcion; analyze bi_interno.ficha_contrato;
