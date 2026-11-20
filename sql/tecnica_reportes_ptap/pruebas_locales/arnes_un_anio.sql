-- =====================================================================
-- ARNÉS LOCAL DE TIEMPOS (solo la base local de Code A; NO va a producción): UN AÑO SIMULADO a escala de producción y cada reporte de punta a punta
-- (iniciar + TODAS las páginas de 5.000 + cerrar), llamado como lo llama la Edge: rol service_role, statement_timeout 30 s, lock_timeout 8 s.
-- Requiere los dos paquetes aplicados (sh rehacer_base.sh con_todo). Todo en una transacción que se deshace al final.
-- Volumen: Entrada 2 plantas × 24 envíos al día × 6 variables (105.120 valores) con su dosis; Salida 2 plantas × 12 × 4 + 6 tanques × 4 × 2;
-- Muestreo 30 puntos × 2 por semana × 6; 400 valores fuera de referencia; químicos 4 × (uso diario por planta + entrada semanal);
-- 30.000 reportes de la 116; 2.900 del bot; 1.000 LEV; 2.000 cierres de válvula; 300 eventos (60 de planta); 300 usuarios sensibles. Activos: los 35.781 reales.
-- =====================================================================
\set ON_ERROR_STOP 1
begin;
set local client_min_messages = warning;
-- ---------- datos (como postgres) ----------
insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, ver_dashboard_redes, horario, dias)
values ('arnes.rep.sup@emdupar.gov.co', 'ARNES Supervisor', 'consulta', true, true, true, 'sin_restriccion', 'todos');
insert into tecnica.variables (codigo, nombre, unidad, categoria, decimales)
select 'arnes_' || x.f || '_' || n, 'ARNES ' || x.f || ' ' || n, 'u', 'fisicoquimico', 2 from (values ('entrada', 6), ('salida', 4), ('muestreo', 6)) x(f, k) cross join generate_series(1, x.k) n;
create temp table _vars on commit drop as
  select split_part(substr(v.codigo, 7), '_', 1) as f, split_part(substr(v.codigo, 7), '_', 2)::integer as n, v.id from tecnica.variables v where v.codigo like 'arnes\_%';
insert into tecnica.formulario_variables (formulario, variable_id, orden, alcance, tipo_punto)
select f, id, 900 + n, case f when 'muestreo' then 'por_punto' when 'salida' then case when n <= 2 then 'por_planta' else 'por_punto' end else 'por_planta' end,
       case when f = 'salida' then 'tanque' else 'muestreo' end from _vars;
insert into tecnica.referencias (variable_id, ref_max, origen, fuente) select id, 199.5, 'criterio_planta', 'ARNES referencia' from _vars where n = 1;
insert into tecnica.plantas (codigo, nombre) values ('arnes_a', 'ARNES Planta A'), ('arnes_b', 'ARNES Planta B');
insert into tecnica.puntos (codigo, nombre, tipo, zona) select 'ARNES-M' || i, 'ARNES muestreo ' || i, 'muestreo', (array['norte', 'sur', 'medio'])[1 + i % 3] from generate_series(1, 30) i;
insert into tecnica.puntos (codigo, nombre, tipo) select 'ARNES-T' || i, 'ARNES tanque ' || i, 'tanque' from generate_series(1, 6) i;
insert into tecnica.quimicos (codigo, nombre, rol) select 'arnes_q' || i, 'ARNES químico ' || i, case when i = 1 then 'coagulante' else 'auxiliar' end from generate_series(1, 4) i;
-- Entrada: 2 plantas × 24 envíos al día × 6 variables, un año (unos pocos valores arriba de la referencia)
create temp table _lotes on commit drop as
  select gen_random_uuid() as lote, p.id as planta_id, d, h from tecnica.plantas p cross join generate_series(0, 364) d cross join generate_series(0, 23) h where p.codigo like 'arnes\_%';
insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor, registrado_en)
select l.lote, 'entrada', v.id, l.planta_id, case when v.n = 1 and (l.d * 24 + l.h) % 220 = 0 then 250 else 100 + (l.h % 7) end,
       (clock_timestamp() at time zone 'America/Bogota')::date - l.d, make_time(l.h, 0, 0), 'arnes.rep.op@emdupar.gov.co',
       ((clock_timestamp() at time zone 'America/Bogota')::date - l.d)::timestamp at time zone 'America/Bogota' + make_interval(hours => l.h, mins => 20)
  from _lotes l cross join _vars v where v.f = 'entrada';
insert into tecnica.uso_quimicos (lote_id, origen, tipo_uso, quimico_id, planta_id, dosis, fecha_muestra, hora_muestra, autor, registrado_en)
select l.lote, 'entrada', 'dosificacion', (select id from tecnica.quimicos where codigo = 'arnes_q1'), l.planta_id, 20 + l.h % 5,
       (clock_timestamp() at time zone 'America/Bogota')::date - l.d, make_time(l.h, 0, 0), 'arnes.rep.op@emdupar.gov.co',
       ((clock_timestamp() at time zone 'America/Bogota')::date - l.d)::timestamp at time zone 'America/Bogota' + make_interval(hours => l.h, mins => 20)
  from _lotes l;
-- Salida: plantas (12 al día, variables 1–2) y tanques (4 al día, variables 3–4)
insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, punto_id, valor, fecha_muestra, hora_muestra, autor, registrado_en)
select x.lote, 'salida', v.id, x.planta_id, x.punto_id, 1 + random(), (clock_timestamp() at time zone 'America/Bogota')::date - x.d, make_time(x.h, 0, 0), 'arnes.rep.op@emdupar.gov.co',
       ((clock_timestamp() at time zone 'America/Bogota')::date - x.d)::timestamp at time zone 'America/Bogota' + make_interval(hours => x.h, mins => 10)
  from (select gen_random_uuid() lote, p.id planta_id, null::bigint punto_id, d, h, true es_planta from tecnica.plantas p cross join generate_series(0, 364) d cross join generate_series(0, 22, 2) h where p.codigo like 'arnes\_%'
        union all
        select gen_random_uuid(), null, pu.id, d, h, false from tecnica.puntos pu cross join generate_series(0, 364) d cross join generate_series(6, 18, 4) h where pu.codigo like 'ARNES-T%') x
  join _vars v on v.f = 'salida' and ((x.es_planta and v.n <= 2) or (not x.es_planta and v.n > 2));
-- Muestreo: 30 puntos, 2 por semana, 6 parámetros
insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor, registrado_en)
select x.lote, 'muestreo', v.id, x.punto_id, 7 + random(), (clock_timestamp() at time zone 'America/Bogota')::date - x.d, '09:00', 'arnes.rep.op@emdupar.gov.co',
       ((clock_timestamp() at time zone 'America/Bogota')::date - x.d)::timestamp at time zone 'America/Bogota' + interval '2 days'
  from (select gen_random_uuid() lote, pu.id punto_id, d from tecnica.puntos pu cross join generate_series(2, 364, 3) d where pu.codigo like 'ARNES-M%') x
  cross join _vars v where v.f = 'muestreo';
-- Químicos: inventario hace un año, uso diario por planta, entrada semanal
insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor)
select 'inventario_inicial', q.id, 50000, 'kg', 50000, current_date - 365, 'ARNES inventario inicial', 'arnes.rep.sup@emdupar.gov.co' from tecnica.quimicos q where q.codigo like 'arnes\_q%';
insert into tecnica.quimico_movimientos (tipo, quimico_id, planta_id, para_que, cantidad, unidad, cantidad_kg, dia, autor)
select 'uso', q.id, p.id, 'dosificacion', 30, 'kg', -30, current_date - d, 'arnes.rep.op@emdupar.gov.co'
  from tecnica.quimicos q cross join tecnica.plantas p cross join generate_series(0, 363) d where q.codigo like 'arnes\_q%' and p.codigo like 'arnes\_%';
insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, autor)
select 'entrada', q.id, 0.5, 't', 500, current_date - d, 'ARNES Proveedor', 'R-' || d, 'arnes.rep.op@emdupar.gov.co'
  from tecnica.quimicos q cross join generate_series(0, 363, 7) d where q.codigo like 'arnes\_q%';
-- Redes: un sector grande, 30.000 de la 116, 3.000 del bot, 1.000 LEV, 2.000 cierres, 300 eventos (60 de planta)
do $$
declare v_id bigint; v_c bigint; v_cod text; g geometry;
begin
  select ST_Envelope(ST_Extent(geom)) into g from redes.activo_vigente_mat where prefijo = 'RED';
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'SEC' returning ultimo into v_c;
  v_cod := 'SEC-' || lpad(v_c::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, 'SEC', 'carga', 'arnes.rep.sup@emdupar.gov.co') returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, estado_codigo, atributos, huella, autor)
  values (v_id, 1, ST_Multi(ST_MakeEnvelope(ST_XMin(g), ST_YMin(g), (ST_XMin(g) + ST_XMax(g)) / 2, ST_YMax(g), 4326)), 'ARNES sector 5', 'sector', 'en_operacion', '{"modelo": {"sector": 5}}', md5(v_cod), 'arnes.rep.sup@emdupar.gov.co');
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ARNES', 'arnes.rep.sup@emdupar.gov.co');
  perform redes.f_mat_refrescar_uno(v_id);
end $$;
create temp table _pts on commit drop as
  select i, ST_SetSRID(ST_MakePoint(ST_XMin(g) + random() * (ST_XMax(g) - ST_XMin(g)), ST_YMin(g) + random() * (ST_YMax(g) - ST_YMin(g))), 4326) as geom
    from generate_series(1, 30000) i cross join (select ST_Envelope(ST_Extent(geom)) g from redes.activo_vigente_mat where prefijo = 'RED') e;
insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
values ('acueducto', md5('arnes-a') || md5('arnes-b'), 'csv', 4326, 'reporte', 30000, 'ARNES 116', 'arnes.rep.sup@emdupar.gov.co');
insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, comuna, contrato, carga_id, creado_en)
select 880000000 + i, clock_timestamp() - make_interval(mins => i * 17), 'Acueducto', 'Sin servicio de agua', 'Comuna ' || (i % 6 + 1), (100000 + i)::text,
       (select max(id) from redes.cargas), clock_timestamp() - make_interval(mins => i * 17) + interval '1 day' from generate_series(1, 30000) i;
insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, contrato, estado, estado_desde, metodo, geom, sector, subsector, oculto)
select r.id, r.reporte, r.fecha_registro, (r.fecha_registro at time zone 'America/Bogota')::date, r.servicio, r.causal, r.contrato, 'registrado', r.fecha_registro, 'contrato', p.geom, 1 + (p.i % 20), null, p.i % 50 = 0
  from redes.l116_reportes r join _pts p on p.i = r.reporte - 880000000;
insert into redes.reportes_externos (radicado, canal, tipo_bot, lat, lon, descripcion, recibido_en, registrado_en)
select 'ARNES-' || i, 'telegram', 'Fuga', round(ST_Y(p.geom)::numeric, 6), round(ST_X(p.geom)::numeric, 6), 'ARNES descripción', clock_timestamp() - make_interval(hours => i * 3), clock_timestamp() - make_interval(hours => i * 3)
  from _pts p where p.i <= 2900;
insert into redes.levantar_puntos (id, codigo, servicio, tipo, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en)
select gen_random_uuid(), 'LEV-8' || lpad(i::text, 5, '0'), 'acueducto', 'valvula', round(ST_Y(p.geom)::numeric, 6), round(ST_X(p.geom)::numeric, 6), p.geom, 5, false, 'tecnica', 'arnes.rep.op@emdupar.gov.co', clock_timestamp() - make_interval(hours => i * 8)
  from _pts p where p.i <= 1000;
insert into redes.valvula_maniobras (valvula_id, tipo, motivo, hecho_en, autor, registrado_en)
select v.activo_id, 'cerrar', 'ARNES cierre', clock_timestamp() - make_interval(hours => i * 4), 'arnes.rep.sup@emdupar.gov.co', clock_timestamp() - make_interval(hours => i * 4)
  from generate_series(1, 2000) i join lateral (select activo_id from redes.activo_vigente_mat where prefijo = 'VAL' order by activo_id offset (i % 700) limit 1) v on true;
insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, hecho_en, autor, registrado_en)
select c.valvula_id, 'abrir', c.id, c.hecho_en + interval '3 hours', c.autor, c.hecho_en + interval '3 hours' from redes.valvula_maniobras c where c.tipo = 'cerrar' and c.motivo = 'ARNES cierre' and c.id % 4 <> 0;
insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, planta_id, zona_nombre, causa, desde, regreso_estimado, contratos, sensibles, autor)
select 'EVS-7' || lpad(i::text, 5, '0'), 'total', false, ST_Multi(ST_Buffer(p.geom, 0.003)), '{}', case when i % 5 = 0 then (select id from tecnica.plantas where codigo = 'arnes_a') end,
       'ARNES zona', 'ARNES causa', clock_timestamp() - make_interval(hours => i * 29), clock_timestamp() - make_interval(hours => i * 29 - 6), 500, 2, 'arnes.rep.sup@emdupar.gov.co'
  from _pts p where p.i <= 300;
insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor)
select e.id, 'cerrar', 'ARNES se cerró el evento', e.desde + interval '8 hours', e.autor from redes.eventos_suspension e where e.causa = 'ARNES causa';
insert into redes.usuarios_sensibles (contrato, tipo, origen, autor)
select ct.contrato, (array['hospital', 'clinica', 'colegio', 'otro'])[1 + (row_number() over ()) % 4], 'manual', 'arnes.rep.sup@emdupar.gov.co'
  from (select distinct contrato from redes.contrato_tramo order by contrato limit 300) ct on conflict do nothing;
analyze;

-- ---------- las llamadas, como la Edge ----------
create temp table _t (reporte text, filtros text, total integer, paginas integer, ms_iniciar numeric, ms_pagina_max numeric, ms_total numeric) on commit drop;
grant all on _t to service_role;
set local role service_role;
set local statement_timeout = '30s';
set local lock_timeout = '8s';
do $$
declare r record; j jsonb; p jsonb; v_c text; v_n integer; t0 timestamptz; t1 timestamptz; v_ini numeric; v_max numeric; v_tot numeric; v_pag integer; v_filas integer; u text := 'arnes.rep.sup@emdupar.gov.co';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; anio jsonb := jsonb_build_object('desde', (hoy - 365)::text, 'hasta', hoy::text);
begin
  for r in select * from (values
      ('tec', 'entrada', anio), ('tec', 'entrada', anio || '{"planta": "arnes_a"}'), ('tec', 'salida', anio), ('tec', 'muestreo', anio), ('tec', 'uso_quimicos', anio),
      ('tec', 'entrada_quimicos', anio), ('tec', 'kardex_quimicos', anio), ('tec', 'eventos_planta', anio), ('tec', 'fuera_referencia', anio),
      ('redes', 'levantamientos', anio), ('redes', 'levantamientos', anio || '{"sector": "5"}'), ('redes', 'valvulas', anio), ('redes', 'eventos', anio), ('redes', 'l116', anio),
      ('redes', 'l116', anio || '{"sector": "5"}'), ('redes', 'bot', anio), ('redes', 'bot', anio || '{"sector": "5"}'), ('redes', 'sensibles', '{}'::jsonb), ('redes', 'activos', '{}'::jsonb)) x(esq, rep, f)
  loop
    t0 := clock_timestamp();
    j := case r.esq when 'tec' then public.geoportal_tec_reporte_iniciar(u, r.rep, r.f, 'xlsx', false, null) else public.geoportal_redes_reporte_iniciar(u, r.rep, r.f, 'xlsx', false, null) end;
    v_ini := extract(epoch from clock_timestamp() - t0) * 1000; v_c := null; v_max := 0; v_pag := 0; v_filas := 0;
    loop
      t1 := clock_timestamp();
      p := case r.esq when 'tec' then public.geoportal_tec_reporte_pagina(u, (j ->> 'descarga_id')::bigint, v_c, 5000) else public.geoportal_redes_reporte_pagina(u, (j ->> 'descarga_id')::bigint, v_c, 5000) end;
      v_max := greatest(v_max, extract(epoch from clock_timestamp() - t1) * 1000); v_pag := v_pag + 1; v_filas := v_filas + (p ->> 'devueltos')::integer; v_c := p ->> 'cursor';
      exit when v_c is null;
    end loop;
    perform case r.esq when 'tec' then public.geoportal_tec_reporte_cerrar(u, (j ->> 'descarga_id')::bigint, v_filas, 'completa', null) else public.geoportal_redes_reporte_cerrar(u, (j ->> 'descarga_id')::bigint, v_filas, 'completa', null) end;
    if v_filas <> (j ->> 'total')::integer then raise exception 'ARNES %: las páginas trajeron % filas y «iniciar» dijo %', r.rep, v_filas, j ->> 'total'; end if;
    insert into _t values (r.rep, (r.f - 'desde' - 'hasta')::text, v_filas, v_pag, round(v_ini), round(v_max), round(extract(epoch from clock_timestamp() - t0) * 1000));
  end loop;
end $$;
reset role;
select reporte, filtros, total, paginas, ms_iniciar as "iniciar ms", ms_pagina_max as "página más lenta ms", ms_total as "todo ms" from _t;
rollback;
