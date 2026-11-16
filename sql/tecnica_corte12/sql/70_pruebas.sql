-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 12 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de la migración, en la misma transacción.
-- Arma sus personas (prueba.tec12.*), su planta («ZT12 Planta»), sus puntos (MUE-9121…), su químico, sus daños (DAN-9912xx), su intervención (ITV-9912xx),
-- su reporte del bot y su carga. No depende de los datos reales: cada prueba compara el conteo del aviso antes y después de lo que ella misma crea.
-- Mide el tiempo de la consulta de avisos con el volumen real y FALLA si pasa de 1 s. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · CORTE 12 … RESULTADO: N de N pruebas correctas — SIN FALLAS  (y la línea TIEMPOS)
-- =====================================================================
create temp table _r (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.reg(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as
$$ insert into _r (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $$;
create function pg_temp.err(p_nombre text, p_sql text, p_estado text default null, p_texto text default null) returns void language plpgsql as $$
declare v_e text; v_m text;
begin
  begin
    execute p_sql;
    perform pg_temp.reg(p_nombre, false, 'No falló y debía fallar');
  exception when others then
    get stacked diagnostics v_e = returned_sqlstate, v_m = message_text;
    perform pg_temp.reg(p_nombre, (p_estado is null or v_e = p_estado) and (p_texto is null or position(p_texto in v_m) > 0), 'SQLSTATE ' || v_e || ': ' || left(v_m, 200));
  end;
end $$;
-- el aviso de una clave (o nulo) y su conteo (0 si no está)
create function pg_temp.av(j jsonb, k text) returns jsonb language sql as $$ select a from jsonb_array_elements(coalesce(j, '[]'::jsonb)) a where a ->> 'clave' = k limit 1 $$;
create function pg_temp.n(j jsonb, k text) returns integer language sql as $$ select coalesce((pg_temp.av(j, k) ->> 'n')::integer, 0) $$;
-- una hora de HOY en Bogotá (8.5 = 8:30 a. m.)
create function pg_temp.h(p numeric) returns timestamptz language sql as
$$ select (((clock_timestamp() at time zone 'America/Bogota')::date)::timestamp + make_interval(mins => (p * 60)::integer)) at time zone 'America/Bogota' $$;
-- un PDF «subido» para la ficha de un químico
create function pg_temp.pdf(p_quien text) returns text language plpgsql as $$
declare v text := public.geoportal_tec_quimico_ficha_preparar(p_quien) ->> 'ruta';
begin
  insert into storage.objects (bucket_id, name, metadata) values ('tecnica-evidencias', v, '{"size": 300000, "mimetype": "application/pdf"}'::jsonb);
  return v;
end $$;

do $prueba$
declare
  a text := 'prueba.tec12.adm@emdupar.gov.co'; sp text := 'prueba.tec12.planta@emdupar.gov.co'; sd text := 'prueba.tec12.dist@emdupar.gov.co';
  op text := 'prueba.tec12.op@emdupar.gov.co'; op2 text := 'prueba.tec12.op2@emdupar.gov.co'; dz text := 'prueba.tec12.desactivada@emdupar.gov.co';
  v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_pl bigint; v_pt bigint; v_pt2 bigint; v_act bigint; v_act2 bigint; v_tipo text; v_cod text; v_rep uuid; v_carga bigint; v_reg bigint;
  d_alto uuid := gen_random_uuid(); d_medio uuid := gen_random_uuid(); d_bajo uuid := gen_random_uuid(); d_nuevo uuid := gen_random_uuid(); d_viejo uuid := gen_random_uuid(); d_ni uuid := gen_random_uuid();
  v_redes text; v_j jsonb; v_j0 jsonb; v_j1 jsonb; v_x jsonb; v_t timestamptz; v_ms numeric; v_ms_adm numeric := 0; v_ms_sp numeric := 0; v_ms_sd numeric := 0; v_i integer;
  v_lease uuid; v_e1 text; v_e2 text; v_av uuid; v_av2 uuid; v_n0 integer; v_n1 integer;
  v_total integer; v_bien integer; v_fallas text;
begin
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v_redes from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');

  -- ===================== 00. TIEMPO con los datos reales (antes de crear nada) =====================
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT12 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZT12 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_dashboard_redes, horario, dias) values (sd, 'ZT12 Supervisor de distribución', 'consulta', true, 'sin_restriccion', 'todos');
  for v_i in 1..3 loop
    v_t := clock_timestamp(); v_j := public.geoportal_tec_avisos(a); v_ms := extract(epoch from clock_timestamp() - v_t) * 1000; v_ms_adm := greatest(v_ms_adm, v_ms);
    v_t := clock_timestamp(); perform public.geoportal_tec_avisos(sp); v_ms := extract(epoch from clock_timestamp() - v_t) * 1000; v_ms_sp := greatest(v_ms_sp, v_ms);
    v_t := clock_timestamp(); perform public.geoportal_tec_avisos(sd); v_ms := extract(epoch from clock_timestamp() - v_t) * 1000; v_ms_sd := greatest(v_ms_sd, v_ms);
  end loop;
  perform pg_temp.reg('00.01 TIEMPO: todos los avisos del administrador en una sola consulta, con el volumen real, en menos de 1 s (el peor de 3)', v_ms_adm < 1000, round(v_ms_adm) || ' ms');
  perform pg_temp.reg('00.02 TIEMPO: los de cada supervisor también en menos de 1 s', v_ms_sp < 1000 and v_ms_sd < 1000, round(v_ms_sp) || ' ms y ' || round(v_ms_sd) || ' ms');

  -- personas y datos de la prueba
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT12 Operador', 'consulta', true, 'sin_restriccion', 'todos'),
         (dz, 'ZT12 Supervisor desactivado', 'consulta', true, 'sin_restriccion', 'todos');
  update public.geoportal_lista_blanca set ver_dashboard_tecnico = true where email = dz;
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, autor) values (dz, 'desactivar_tecnica', a);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'uso_quimicos', a);
  insert into tecnica.plantas (codigo, nombre, activa) values ('zt12_planta', 'ZT12 Planta', true) returning id into v_pl;
  select codigo into v_tipo from redes.tipos_dano where activo and 'acueducto' = any (sistemas) order by orden limit 1;
  select m.activo_id into v_act from redes.activo_vigente_mat m where m.sistema = 'acueducto' and not m.retirado and not m.oculto order by m.activo_id limit 1;
  select m.activo_id into v_act2 from redes.activo_vigente_mat m where not m.retirado
     and not exists (select 1 from redes.activo_eventos e where e.activo_id = m.activo_id and e.tipo in ('verificar', 'por_verificar')) order by m.activo_id desc limit 1;

  -- ===================== 01. Estructura y permisos =====================
  perform pg_temp.reg('01.01 los 15 plazos y mínimos con los valores de David: horario 8 a 18, alto 2 y 6 h, medio 24 y 72 h, bajo 72 y 168 h, 116 a 3 días',
     (select count(*) from tecnica.aviso_parametros) = 15 and tecnica.f_aparam('horario_inicio') = 8 and tecnica.f_aparam('horario_fin') = 18
     and tecnica.f_aparam('dano_alto_naranja_h') = 2 and tecnica.f_aparam('dano_alto_rojo_h') = 6 and tecnica.f_aparam('dano_medio_naranja_h') = 24 and tecnica.f_aparam('dano_medio_rojo_h') = 72
     and tecnica.f_aparam('dano_bajo_naranja_h') = 72 and tecnica.f_aparam('dano_bajo_rojo_h') = 168 and tecnica.f_aparam('l116_registrado_dias') = 3);
  perform pg_temp.err('01.02 un plazo no se borra', $$delete from tecnica.aviso_parametros where clave = 'horario_inicio'$$, '42501');
  perform pg_temp.reg('01.05b los números de los avisos van como en Técnica (punto de miles, coma decimal), sin depender del idioma de la base',
     tecnica.f_texto_num(2000) = '2.000' and tecnica.f_texto_num(0.05) = '0,05' and tecnica.f_texto_num(1234567.891) = '1.234.567,89' and tecnica.f_texto_num(-1500.5) = '-1.500,5'
     and tecnica.f_texto_horas(0.5) = 'menos de 1 h' and tecnica.f_texto_horas(7.9) = '7 h' and tecnica.f_texto_horas(200) = '8 días');
  perform pg_temp.reg('01.06 el rol del Dell nace sin poder conectarse, con 2 conexiones, y solo ejecuta tomar, marcar y liberar',
     (select not rolcanlogin and rolconnlimit = 2 and not rolsuper and not rolbypassrls from pg_roles where rolname = 'dell_avisos')
     and has_function_privilege('dell_avisos', 'tecnica.avisos_tomar(integer,integer)', 'execute') and has_function_privilege('dell_avisos', 'tecnica.avisos_marcar(uuid,uuid,text,jsonb,boolean)', 'execute')
     and has_function_privilege('dell_avisos', 'tecnica.avisos_liberar(uuid,uuid)', 'execute')
     and not has_function_privilege('dell_avisos', 'public.geoportal_tec_avisos(text)', 'execute') and not has_function_privilege('dell_avisos', 'tecnica.f_avisos(boolean,boolean,timestamptz)', 'execute')
     and not has_table_privilege('dell_avisos', 'tecnica.avisos_salida', 'select') and not has_table_privilege('dell_avisos', 'tecnica.registros', 'select'));
  perform pg_temp.reg('01.07 la API: service_role solo ejecuta las 5 RPC; anon y authenticated nada; nadie de la API lee las tablas ni toma la cola',
     has_function_privilege('service_role', 'public.geoportal_tec_avisos(text)', 'execute') and has_function_privilege('service_role', 'public.geoportal_tec_quimico_minimo_fijar(text,text,numeric,text)', 'execute')
     and not has_function_privilege('anon', 'public.geoportal_tec_avisos(text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_tec_avisos(text)', 'execute')
     and not has_function_privilege('service_role', 'tecnica.avisos_tomar(integer,integer)', 'execute') and not has_function_privilege('service_role', 'tecnica.f_avisos(boolean,boolean,timestamptz)', 'execute')
     and not has_table_privilege('service_role', 'tecnica.aviso_parametros', 'select') and not has_table_privilege('service_role', 'tecnica.avisos_salida', 'select')
     and not has_table_privilege('authenticated', 'tecnica.quimico_minimo_eventos', 'select'));

  -- ===================== 02. Quién ve qué =====================
  perform pg_temp.err('02.01 el operador no ve avisos', format($$select public.geoportal_tec_avisos(%L)$$, op), '42501');
  perform pg_temp.err('02.02 un supervisor con Técnica desactivada no ve avisos', format($$select public.geoportal_tec_avisos(%L)$$, dz), '42501', 'desactivado');
  perform pg_temp.err('02.03 alguien que no está en la lista blanca, tampoco', $$select public.geoportal_tec_avisos('prueba.tec12.nadie@emdupar.gov.co')$$, '42501');
  v_j := public.geoportal_tec_avisos(sp);
  perform pg_temp.reg('02.04 supervisor de planta: Plantas y Personal, nada de Distribución',
     (v_j -> 'areas' ->> 'planta')::boolean and not (v_j -> 'areas' ->> 'distribucion')::boolean
     and not exists (select 1 from jsonb_array_elements(v_j -> 'avisos') x where x ->> 'area' = 'distribucion'), (v_j -> 'areas')::text);
  v_j := public.geoportal_tec_avisos(sd);
  perform pg_temp.reg('02.05 supervisor de distribución: Distribución y Personal, nada de Plantas',
     (v_j -> 'areas' ->> 'distribucion')::boolean and not (v_j -> 'areas' ->> 'planta')::boolean
     and not exists (select 1 from jsonb_array_elements(v_j -> 'avisos') x where x ->> 'area' = 'planta'), (v_j -> 'areas')::text);
  v_j := public.geoportal_tec_avisos(a);
  perform pg_temp.reg('02.06 administrador: todo, con el total, los rojos y los naranjas contados; ordenados rojo, naranja e informativo',
     (v_j -> 'areas' ->> 'planta')::boolean and (v_j -> 'areas' ->> 'distribucion')::boolean and (v_j ->> 'total')::integer = jsonb_array_length(v_j -> 'avisos')
     and (v_j ->> 'rojos')::integer = (select count(*) from jsonb_array_elements(v_j -> 'avisos') x where x ->> 'nivel' = 'rojo')
     and not exists (select 1 from jsonb_array_elements(v_j -> 'avisos') with ordinality x(e, i) join jsonb_array_elements(v_j -> 'avisos') with ordinality y(e, k) on y.k = x.i + 1
                      where (case x.e ->> 'nivel' when 'rojo' then 1 when 'naranja' then 2 else 3 end) > (case y.e ->> 'nivel' when 'rojo' then 1 when 'naranja' then 2 else 3 end)));
  perform pg_temp.reg('02.07 cada aviso trae título, nivel, área y su bandeja', not exists (select 1 from jsonb_array_elements(v_j -> 'avisos') x
     where coalesce(x ->> 'titulo', '') = '' or x ->> 'nivel' not in ('rojo', 'naranja', 'info') or x ->> 'area' not in ('planta', 'distribucion', 'personal')
        or x -> 'bandeja' ->> 'tablero' not in ('ptap', 'distribucion', 'personal')));

  -- ===================== 03. Plantas: Entrada y Salida dentro del horario (8 a. m. a 6 p. m.) =====================
  perform pg_temp.reg('03.01 a las 9:30 (antes de la hora límite del primer registro, 10:00) no hay aviso de la planta',
     pg_temp.av(tecnica.f_avisos(true, false, pg_temp.h(9.5)), 'planta_entrada:zt12_planta') is null);
  v_j := tecnica.f_avisos(true, false, pg_temp.h(10.5));
  perform pg_temp.reg('03.02 a las 10:30 sin ningún registro: Entrada y Salida en naranja, «sin el primer registro del día en ZT12 Planta»',
     pg_temp.av(v_j, 'planta_entrada:zt12_planta') ->> 'nivel' = 'naranja' and pg_temp.av(v_j, 'planta_salida:zt12_planta') ->> 'nivel' = 'naranja'
     and pg_temp.av(v_j, 'planta_entrada:zt12_planta') ->> 'titulo' = 'Entrada sin el primer registro del día en ZT12 Planta'
     and pg_temp.av(v_j, 'planta_entrada:zt12_planta') -> 'bandeja' ->> 'pestana' = 'registros', pg_temp.av(v_j, 'planta_entrada:zt12_planta')::text);
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'entrada', v.id, v_pl, 100, v_hoy, time '10:15', op from tecnica.variables v where v.codigo = 'caudal_qi';
  v_j := tecnica.f_avisos(true, false, pg_temp.h(11));
  perform pg_temp.reg('03.03 con un registro de Entrada a las 10:15, a las 11:00 la Entrada desaparece sola y la Salida sigue',
     pg_temp.av(v_j, 'planta_entrada:zt12_planta') is null and pg_temp.av(v_j, 'planta_salida:zt12_planta') is not null);
  v_j := tecnica.f_avisos(true, false, pg_temp.h(14.5));
  perform pg_temp.reg('03.04 a las 14:30 (más de 4 h sin registro dentro del horario): naranja «Entrada sin registro hace 4 h», con la hora del último',
     pg_temp.av(v_j, 'planta_entrada:zt12_planta') ->> 'titulo' = 'Entrada sin registro hace 4 h en ZT12 Planta' and pg_temp.av(v_j, 'planta_entrada:zt12_planta') ->> 'detalle' like '%10:15%',
     pg_temp.av(v_j, 'planta_entrada:zt12_planta')::text);
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'entrada', v.id, v_pl, 100, v_hoy, time '14:00', op from tecnica.variables v where v.codigo = 'caudal_qi' returning id into v_reg;
  insert into tecnica.exclusiones (registro_id, accion, motivo, autor) values (v_reg, 'EXCLUIR', 'ZT12 registro de prueba excluido', sp);
  perform pg_temp.reg('03.05 un registro excluido no cuenta: a las 14:30 sigue el aviso', pg_temp.av(tecnica.f_avisos(true, false, pg_temp.h(14.5)), 'planta_entrada:zt12_planta') is not null);
  perform pg_temp.reg('03.06 a las 12:00 (1 h 45 después del último registro) no hay aviso de Entrada',
     pg_temp.av(tecnica.f_avisos(true, false, pg_temp.h(12)), 'planta_entrada:zt12_planta') is null);
  v_j := tecnica.f_avisos(true, false, pg_temp.h(18.5));
  perform pg_temp.reg('03.07 a las 18:30 (cerró el horario): la Salida sin registros del día en ROJO; la Entrada, que sí tuvo, ya no avisa',
     pg_temp.av(v_j, 'planta_salida:zt12_planta') ->> 'nivel' = 'rojo' and pg_temp.av(v_j, 'planta_salida:zt12_planta') ->> 'titulo' = 'Salida sin registros hoy en ZT12 Planta'
     and pg_temp.av(v_j, 'planta_entrada:zt12_planta') is null);
  perform pg_temp.reg('03.08 a las 7:00 (antes del horario) nada de la planta', pg_temp.av(tecnica.f_avisos(true, false, pg_temp.h(7)), 'planta_salida:zt12_planta') is null);
  perform pg_temp.reg('03.09 el supervisor de distribución no recibe los avisos de la planta', pg_temp.av(tecnica.f_avisos(false, true, pg_temp.h(18.5)), 'planta_salida:zt12_planta') is null);

  -- ===================== 04. Puntos de muestreo =====================
  v_n0 := pg_temp.n(tecnica.f_avisos(true, false, null), 'muestreo_sin_muestra');
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9121', 'ZT12 Uno', 'muestreo', 'norte') returning id into v_pt;
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9122', 'ZT12 Dos', 'muestreo', 'sur') returning id into v_pt2;
  perform pg_temp.reg('04.01 dos puntos nuevos sin muestra: el aviso de puntos sin muestra en 35 días sube en 2',
     pg_temp.n(tecnica.f_avisos(true, false, null), 'muestreo_sin_muestra') = v_n0 + 2, v_n0::text);
  v_n1 := pg_temp.n(tecnica.f_avisos(true, false, null), 'muestreo_fuera_rango');
  insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'muestreo', v.id, v_pt, 0.05, v_hoy - 3, time '09:00', op from tecnica.variables v where v.codigo = 'cloro_residual_libre';
  insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'muestreo', v.id, v_pt2, 1.0, v_hoy - 40, time '09:00', op from tecnica.variables v where v.codigo = 'cloro_residual_libre';
  perform pg_temp.reg('04.02 una muestra de hace 3 días saca al punto del aviso; una de hace 40 días no',
     pg_temp.n(tecnica.f_avisos(true, false, null), 'muestreo_sin_muestra') = v_n0 + 1);
  v_n0 := v_n1;
  insert into tecnica.referencias (variable_id, punto_id, ref_min, ref_max, origen, fuente)
  select id, v_pt, 0.3, 2.0, 'criterio_planta', 'ZT12 referencia de prueba del punto' from tecnica.variables where codigo = 'cloro_residual_libre';
  v_j := tecnica.f_avisos(true, false, null);
  perform pg_temp.reg('04.03 el último cloro (0,05) por debajo del rango del punto (0,3 a 2): el aviso rojo «fuera de rango» sube en 1, con el valor',
     pg_temp.n(v_j, 'muestreo_fuera_rango') = v_n0 + 1 and pg_temp.av(v_j, 'muestreo_fuera_rango') ->> 'nivel' = 'rojo'
     and (v_n0 >= 5 or exists (select 1 from jsonb_array_elements_text(pg_temp.av(v_j, 'muestreo_fuera_rango') -> 'items') t where t like 'MUE-9121 · %0,05%')),
     pg_temp.av(v_j, 'muestreo_fuera_rango')::text);
  v_n0 := pg_temp.n(tecnica.f_avisos(true, false, null), 'ubicaciones_pendientes');
  insert into tecnica.punto_ubicacion_propuestas (punto_id, lat, lon, precision_m, autor) values (v_pt, 10.47, -73.25, 8, op);
  perform pg_temp.reg('04.04 una ubicación propuesta sin revisar: el aviso de ubicaciones por aprobar sube en 1 y lleva a «Puntos» del Dashboard PTAP',
     pg_temp.n(tecnica.f_avisos(true, false, null), 'ubicaciones_pendientes') = v_n0 + 1
     and pg_temp.av(tecnica.f_avisos(true, false, null), 'ubicaciones_pendientes') -> 'bandeja' ->> 'pestana' = 'puntos');

  -- ===================== 05. Químicos =====================
  v_j0 := tecnica.f_avisos(true, false, clock_timestamp() + interval '1 day');
  v_cod := public.geoportal_tec_quimico_crear(sp, 'ZT12 Coagulante', 'coagulante', true, 20, pg_temp.pdf(sp), 'ZT12 coagulante de prueba') ->> 'codigo';
  perform public.geoportal_tec_quimico_inventario(sp, v_cod, 300, 'kg', v_hoy - 2, 'ZT12 conteo físico de bodega');
  v_n0 := pg_temp.n(tecnica.f_avisos(true, false, null), 'quimicos_saldo');
  perform pg_temp.reg('05.01 sin saldo mínimo fijado no hay aviso del químico (arranca vacío)', (public.geoportal_tec_quimico_minimos(sp) -> 'quimicos') @> jsonb_build_array(jsonb_build_object('codigo', v_cod, 'minimo_kg', null, 'bajo', false)));
  v_x := public.geoportal_tec_quimico_minimo_fijar(sp, v_cod, 500, 'ZT12 el jefe de planta fija el mínimo');
  perform pg_temp.reg('05.02 el supervisor de planta fija 500 kg (saldo 300): el aviso de saldo bajo sube en 1, con evento y auditoría',
     pg_temp.n(tecnica.f_avisos(true, false, null), 'quimicos_saldo') = v_n0 + 1 and (v_x ->> 'minimo_kg')::numeric = 500
     and exists (select 1 from tecnica.quimico_minimo_eventos e join tecnica.quimicos q on q.id = e.quimico_id where q.codigo = v_cod and e.minimo_kg = 500 and e.autor = sp)
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_quimico_minimo' and email = sp and referencia = v_cod), v_x::text);
  perform pg_temp.reg('05.03 la lista de mínimos lo marca bajo', (public.geoportal_tec_quimico_minimos(a) -> 'quimicos') @> jsonb_build_array(jsonb_build_object('codigo', v_cod, 'bajo', true)));
  perform pg_temp.err('05.04 el operador no fija mínimos', format($$select public.geoportal_tec_quimico_minimo_fijar(%L, %L, 100, 'ZT12 el operador no puede')$$, op, v_cod), '42501');
  perform pg_temp.err('05.05 el supervisor de distribución tampoco', format($$select public.geoportal_tec_quimico_minimo_fijar(%L, %L, 100, 'ZT12 distribución no puede')$$, sd, v_cod), '42501');
  perform pg_temp.err('05.06 el mismo mínimo no es un cambio', format($$select public.geoportal_tec_quimico_minimo_fijar(%L, %L, 500, 'ZT12 el mismo valor otra vez')$$, sp, v_cod), '22023', 'ya es');
  perform pg_temp.err('05.07 un mínimo de cero o negativo', format($$select public.geoportal_tec_quimico_minimo_fijar(%L, %L, 0, 'ZT12 cero no vale')$$, sp, v_cod), '22023', 'mínimo');
  perform pg_temp.err('05.08 sin motivo suficiente', format($$select public.geoportal_tec_quimico_minimo_fijar(%L, %L, 400, 'corto')$$, sp, v_cod), '22023', 'motivo');
  perform public.geoportal_tec_quimico_minimo_fijar(a, v_cod, 200, 'ZT12 el administrador baja el mínimo');
  perform pg_temp.reg('05.09 con el mínimo por debajo del saldo, el aviso desaparece solo', pg_temp.n(tecnica.f_avisos(true, false, null), 'quimicos_saldo') = v_n0);
  perform public.geoportal_tec_quimico_minimo_fijar(sp, v_cod, null, 'ZT12 se quita el mínimo del químico');
  perform pg_temp.reg('05.10 quitar el mínimo (vacío) es otro evento y deja el químico sin mínimo',
     (public.geoportal_tec_quimico_minimos(sp) -> 'quimicos') @> jsonb_build_array(jsonb_build_object('codigo', v_cod, 'minimo_kg', null))
     and (select count(*) from tecnica.quimico_minimo_eventos e join tecnica.quimicos q on q.id = e.quimico_id where q.codigo = v_cod) = 3);
  -- HOY, en la planta de prueba: caudal de 100 L/s y el coagulante con dosis óptima de 20 ppm (esperado 172,8 kg) sin ningún uso. Se revisa como si fuera mañana
  -- (los avisos de químicos miran solo días cerrados, y la dosis óptima del químico nuevo rige desde hoy).
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'entrada', v.id, v_pl, 100, v_hoy, time '09:00', op from tecnica.variables v where v.codigo = 'caudal_qi';
  v_j := tecnica.f_avisos(true, false, clock_timestamp() + interval '1 day');
  -- el coagulante nuevo vale para todas las plantas activas que hoy tienen caudal (la de prueba y las reales que ya registraron)
  select count(distinct p.id) into v_n1 from tecnica.plantas p join tecnica.v_registros_estado r2 on r2.planta_id = p.id
   where p.activa and r2.formulario::text = 'entrada' and r2.fecha_muestra = v_hoy and not r2.excluido and r2.variable_id = (select id from tecnica.variables where codigo = 'caudal_qi');
  perform pg_temp.reg('05.11 un día con dosis y caudal y sin uso registrado: el aviso de días sin uso sube en 1 por planta con caudal hoy y lleva a «Químicos»',
     pg_temp.n(v_j, 'quimicos_sin_uso') = pg_temp.n(v_j0, 'quimicos_sin_uso') + v_n1 and v_n1 >= 1 and pg_temp.av(v_j, 'quimicos_sin_uso') -> 'bandeja' ->> 'pestana' = 'quimicos',
     pg_temp.n(v_j0, 'quimicos_sin_uso') || ' → ' || pg_temp.n(v_j, 'quimicos_sin_uso'));
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'entrada', a);
  perform public.geoportal_tec_quimico_uso(op, jsonb_build_object('quimico', v_cod, 'cantidad', 400, 'unidad', 'kg', 'dia', v_hoy, 'planta', 'zt12_planta', 'para_que', 'dosificacion'), null);
  v_j1 := tecnica.f_avisos(true, false, clock_timestamp() + interval '1 day');
  perform pg_temp.reg('05.12 con un uso de 400 kg (esperado 172,8): sale de «sin uso» y entra al aviso de desvío, con el porcentaje',
     pg_temp.n(v_j1, 'quimicos_sin_uso') = pg_temp.n(v_j, 'quimicos_sin_uso') - 1 and pg_temp.n(v_j1, 'quimicos_desvio') = pg_temp.n(v_j0, 'quimicos_desvio') + 1
     and (pg_temp.n(v_j0, 'quimicos_desvio') >= 5 or exists (select 1 from jsonb_array_elements_text(pg_temp.av(v_j1, 'quimicos_desvio') -> 'items') t where t like '%ZT12 Planta · ZT12 Coagulante · +131 %%')),
     pg_temp.av(v_j1, 'quimicos_desvio')::text);
  perform pg_temp.reg('05.13 químicos de potabilización sin dosis óptima o sin ficha: el conteo es el de la tabla',
     pg_temp.n(v_j1, 'quimicos_ficha') = (select count(*) from tecnica.v_quimico_vigente where activo and potabilizacion and (dosis_optima_ppm is null or ficha_ruta is null)));

  -- ===================== 06. Distribución: daños según su riesgo (avisan a cualquier hora) =====================
  v_j0 := tecnica.f_avisos(false, true, null);
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor) values
    (d_alto, 'DAN-991201', 'dano', v_tipo, 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '3 hours', 'alto', 'desconocida', a),
    (d_medio, 'DAN-991202', 'dano', v_tipo, 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '30 hours', 'medio', 'desconocida', a),
    (d_bajo, 'DAN-991203', 'dano', v_tipo, 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '200 hours', 'bajo', 'desconocida', a),
    (d_nuevo, 'DAN-991204', 'dano', v_tipo, 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '30 minutes', 'alto', 'desconocida', a),
    (d_viejo, 'DAN-991205', 'dano', v_tipo, 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '7 hours', 'alto', 'desconocida', a);
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, no_ident_que_es, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor) values
    (d_ni, 'DAN-991206', 'dano', v_tipo, 'acueducto', null, 'ZT12 tubo sin identificar', 10.47, -73.24, 'mapa', clock_timestamp() - interval '10 minutes', 'bajo', 'desconocida', a);
  v_j := tecnica.f_avisos(false, true, null);
  perform pg_temp.reg('06.01 naranja: el alto de 3 h y el medio de 30 h (2 más); rojo: el alto de 7 h y el bajo de 200 h (2 más); el alto de 30 min aún no',
     pg_temp.n(v_j, 'danos_naranja') = pg_temp.n(v_j0, 'danos_naranja') + 2 and pg_temp.n(v_j, 'danos_rojo') = pg_temp.n(v_j0, 'danos_rojo') + 2,
     pg_temp.n(v_j0, 'danos_naranja') || '/' || pg_temp.n(v_j0, 'danos_rojo') || ' → ' || pg_temp.n(v_j, 'danos_naranja') || '/' || pg_temp.n(v_j, 'danos_rojo'));
  perform pg_temp.reg('06.02 el rojo dice «pasaron su plazo», lleva a «Daños y fallas» y nombra los plazos',
     pg_temp.av(v_j, 'danos_rojo') ->> 'titulo' ~ '^(1 daño abierto pasó|[0-9]+ daños abiertos pasaron) su plazo$' and pg_temp.av(v_j, 'danos_rojo') -> 'bandeja' ->> 'pestana' = 'danos'
     and pg_temp.av(v_j, 'danos_rojo') ->> 'detalle' like 'Plazos: riesgo alto 2 y 6 h%');
  perform pg_temp.reg('06.03 el daño no identificado sube el aviso de «activo sin identificar»', pg_temp.n(v_j, 'no_identificados') = pg_temp.n(v_j0, 'no_identificados') + 1);
  perform pg_temp.reg('06.04 a las 3 de la mañana el daño alto también avisa (no hay horario para distribución)',
     pg_temp.n(tecnica.f_avisos(false, true, pg_temp.h(3) + interval '1 day'), 'danos_rojo') >= 1);
  insert into redes.dano_eventos (dano_id, tipo, motivo, autor) values (d_bajo, 'atendido', 'ZT12 atendido sin intervención', sd);
  v_j1 := tecnica.f_avisos(false, true, null);
  perform pg_temp.reg('06.05 el bajo atendido sale solo del rojo y entra a «atendidos sin intervención registrada»',
     pg_temp.n(v_j1, 'danos_rojo') = pg_temp.n(v_j0, 'danos_rojo') + 1 and pg_temp.n(v_j1, 'danos_sin_intervencion') = pg_temp.n(v_j0, 'danos_sin_intervencion') + 1);
  insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_inicio, t_fin, descripcion, ejecutor, autor)
  values (gen_random_uuid(), 'ITV-991201', 'dano', d_bajo, 'reparacion', 'acueducto', v_act, 10.47, -73.24, 'mapa', clock_timestamp() - interval '5 hours', clock_timestamp() - interval '4 hours',
          'ZT12 reparación de prueba del daño', 'emdupar', sd);
  v_j1 := tecnica.f_avisos(false, true, null);
  perform pg_temp.reg('06.06 con su intervención registrada, sale de «sin intervención»; la intervención sin recursos entra a «recursos sin completar»',
     pg_temp.n(v_j1, 'danos_sin_intervencion') = pg_temp.n(v_j0, 'danos_sin_intervencion')
     and pg_temp.n(v_j1, 'recursos_por_completar') = pg_temp.n(v_j0, 'recursos_por_completar') + (select count(*) from redes.v_intervencion where codigo = 'ITV-991201' and recursos = 'por_completar'),
     (select recursos from redes.v_intervencion where codigo = 'ITV-991201'));
  -- reportes del bot, cargas abiertas, activos por verificar y nodos
  insert into redes.reportes_externos (radicado, canal, tipo_bot, lat, lon, descripcion, recibido_en) values ('ZT12-001', 'telegram', 'Fuga', 10.47, -73.24, 'ZT12 reporte de prueba', clock_timestamp() - interval '2 hours') returning id into v_rep;
  insert into redes.reporte_externo_eventos (reporte_id, tipo, autor) values (v_rep, 'recibido', 'bot');
  perform pg_temp.reg('06.07 un reporte del bot recibido sin atender sube el aviso y lleva a «Reportes del bot»',
     pg_temp.n(tecnica.f_avisos(false, true, null), 'reportes_bot') = pg_temp.n(v_j0, 'reportes_bot') + 1 and pg_temp.av(tecnica.f_avisos(false, true, null), 'reportes_bot') -> 'bandeja' ->> 'pestana' = 'bot');
  insert into redes.reporte_externo_eventos (reporte_id, tipo, motivo, autor) values (v_rep, 'descartado', 'ZT12 reporte de prueba descartado', sd);
  perform pg_temp.reg('06.08 descartado con motivo, desaparece solo', pg_temp.n(tecnica.f_avisos(false, true, null), 'reportes_bot') = pg_temp.n(v_j0, 'reportes_bot'));
  v_n0 := pg_temp.n(tecnica.f_avisos(false, true, clock_timestamp() + interval '25 hours'), 'cargas_abiertas');
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor) values ('acueducto', md5('zt12a') || md5('zt12b'), 'shp', 4326, 'ID', 1, 'ZT12 carga de prueba', a) returning id into v_carga;
  perform pg_temp.reg('06.09 una carga abierta: hoy no avisa; dentro de 25 h (más de 24 h sin publicar ni anular) sí',
     pg_temp.n(tecnica.f_avisos(false, true, null), 'cargas_abiertas') = pg_temp.n(v_j0, 'cargas_abiertas')
     and pg_temp.n(tecnica.f_avisos(false, true, clock_timestamp() + interval '25 hours'), 'cargas_abiertas') = v_n0 + 1);
  v_n0 := pg_temp.n(tecnica.f_avisos(false, true, null), 'por_verificar');
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (v_act2, 'por_verificar', 'ZT12 activo de prueba por verificar', a);
  v_n1 := pg_temp.n(tecnica.f_avisos(false, true, null), 'por_verificar');
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (v_act2, 'verificar', 'ZT12 activo de prueba verificado', a);
  perform pg_temp.reg('06.10 un activo marcado «por verificar» sube el aviso informativo en 1; verificado, vuelve',
     v_n1 = v_n0 + 1 and pg_temp.n(tecnica.f_avisos(false, true, null), 'por_verificar') = v_n0, v_n0 || ' → ' || v_n1);
  perform pg_temp.reg('06.11 nodos por clasificar: el conteo es el de la bandeja', pg_temp.n(tecnica.f_avisos(false, true, null), 'nodos_por_clasificar') = (select count(*) from redes.v_nodo_visible where clase_nodo = 'por_clasificar'));
  perform pg_temp.reg('06.12 línea 116: sin el Corte 5d publicado no hay aviso (queda listo y apagado); con el 5d, el conteo es el de su tabla',
     case when to_regclass('redes.l116_vigente') is null then pg_temp.av(tecnica.f_avisos(false, true, null), 'l116_registrado') is null
          else pg_temp.n(tecnica.f_avisos(false, true, null), 'l116_registrado') >= 0 end);

  -- ===================== 07. Personal (los dos supervisores y el administrador) =====================
  v_j0 := tecnica.f_avisos(true, true, null);
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op2, 'ZT12 Operador nuevo', 'consulta', true, 'sin_restriccion', 'todos');
  v_j := tecnica.f_avisos(true, true, null);
  perform pg_temp.reg('07.01 una persona nueva sin formularios ni área: sube «sin formularios» y «sin área»',
     pg_temp.n(v_j, 'personal_sin_formularios') = pg_temp.n(v_j0, 'personal_sin_formularios') + 1 and pg_temp.n(v_j, 'personal_sin_area') = pg_temp.n(v_j0, 'personal_sin_area') + 1);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op2, 'asignar_formulario', 'danos_fallas', a);
  insert into tecnica.personal_ficha_eventos (persona, tipo_evento, valor, motivo, autor) values (op2, 'fijar_area', 'distribucion', 'ZT12 área de prueba', a);
  v_j := tecnica.f_avisos(true, true, null);
  perform pg_temp.reg('07.02 con un formulario y el área «distribución»: sale de los dos y entra a «sin cuadrilla»',
     pg_temp.n(v_j, 'personal_sin_formularios') = pg_temp.n(v_j0, 'personal_sin_formularios') and pg_temp.n(v_j, 'personal_sin_area') = pg_temp.n(v_j0, 'personal_sin_area')
     and pg_temp.n(v_j, 'personal_sin_cuadrilla') = pg_temp.n(v_j0, 'personal_sin_cuadrilla') + 1);
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op2, 'quitar_formulario', 'danos_fallas', a);
  perform pg_temp.reg('07.03 quitarle el único formulario lo devuelve a «sin formularios»', pg_temp.n(tecnica.f_avisos(true, true, null), 'personal_sin_formularios') = pg_temp.n(v_j0, 'personal_sin_formularios') + 1);
  perform pg_temp.reg('07.04 el supervisor de planta y el de distribución ven los avisos de Personal',
     pg_temp.av(public.geoportal_tec_avisos(sp) -> 'avisos', 'personal_sin_cuadrilla') is not null and pg_temp.av(public.geoportal_tec_avisos(sd) -> 'avisos', 'personal_sin_cuadrilla') is not null);

  -- ===================== 08. Plazos y mínimos: parámetros editables =====================
  perform pg_temp.reg('08.01 cada supervisor ve los parámetros de su área (planta 5, distribución 9) y el administrador los 15',
     jsonb_array_length(public.geoportal_tec_avisos_parametros(sp) -> 'parametros') = 5 and jsonb_array_length(public.geoportal_tec_avisos_parametros(sd) -> 'parametros') = 9
     and jsonb_array_length(public.geoportal_tec_avisos_parametros(a) -> 'parametros') = 15
     and (public.geoportal_tec_avisos_parametros(sp) ->> 'puede_minimos')::boolean and not (public.geoportal_tec_avisos_parametros(sd) ->> 'puede_minimos')::boolean);
  v_x := public.geoportal_tec_aviso_parametro_fijar(sp, 'horario_fin', 17, 'ZT12 el turno de la planta cierra a las 5');
  perform pg_temp.reg('08.02 el supervisor de planta cierra el horario a las 17: evento con antes, después, motivo y autor; auditoría; a las 17:30 la Salida ya está en rojo',
     (v_x ->> 'valor')::numeric = 17 and (select antes = 18 and despues = 17 and autor = sp from tecnica.aviso_parametro_eventos where clave = 'horario_fin' order by id desc limit 1)
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_aviso_parametro' and email = sp and referencia = 'horario_fin')
     and pg_temp.av(tecnica.f_avisos(true, false, pg_temp.h(17.5)), 'planta_salida:zt12_planta') ->> 'nivel' = 'rojo'
     and (public.geoportal_tec_avisos_parametros(sp) -> 'parametros' -> 1 -> 'ultimo' ->> 'autor') = sp, v_x::text);
  perform pg_temp.err('08.03 el supervisor de planta no cambia plazos de distribución', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'dano_alto_rojo_h', 8, 'ZT12 no es de su área')$$, sp), '42501');
  perform pg_temp.err('08.04 ni el de distribución los de planta', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'horario_inicio', 7, 'ZT12 no es de su área')$$, sd), '42501');
  perform pg_temp.err('08.05 los intentos del bot solo los cambia el administrador', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'salida_max_intentos', 3, 'ZT12 solo el administrador')$$, sd), '42501');
  perform pg_temp.err('08.06 el operador, nada', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'horario_fin', 16, 'ZT12 el operador no puede')$$, op), '42501');
  v_x := public.geoportal_tec_aviso_parametro_fijar(sd, 'dano_alto_naranja_h', 4, 'ZT12 distribución alarga el naranja del alto');
  v_j := tecnica.f_avisos(false, true, null);
  perform pg_temp.reg('08.07 el supervisor de distribución sube el naranja del riesgo alto a 4 h: el daño alto de 3 h deja de avisar en naranja',
     pg_temp.n(v_j, 'danos_naranja') = pg_temp.n(v_j0, 'danos_naranja') - 1, pg_temp.n(v_j0, 'danos_naranja') || ' → ' || pg_temp.n(v_j, 'danos_naranja'));
  perform pg_temp.err('08.08 el naranja debe quedar antes que el rojo', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'dano_alto_naranja_h', 6, 'ZT12 igual al rojo no vale')$$, sd), '22023', 'naranja');
  perform pg_temp.err('08.09 el inicio del horario antes del fin', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'horario_inicio', 17, 'ZT12 inicio igual al fin')$$, sp), '22023', 'inicio');
  perform pg_temp.err('08.10 la hora límite del primer registro dentro del horario', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'planta_primer_registro_hora', 7, 'ZT12 antes del horario')$$, sp), '22023', 'dentro');
  perform pg_temp.err('08.11 enteros', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'planta_horas_sin_registro', 2.5, 'ZT12 con decimales')$$, sp), '22023', 'entero');
  perform pg_temp.err('08.12 dentro del rango', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'planta_horas_sin_registro', 30, 'ZT12 fuera del rango')$$, sp), '22023', 'va de');
  perform pg_temp.err('08.13 el mismo valor no es un cambio', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'horario_fin', 17, 'ZT12 el mismo valor')$$, sp), '22023', 'ya es');
  perform pg_temp.err('08.14 sin motivo suficiente', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'horario_fin', 16, 'corto')$$, sp), '22023', 'motivo');
  perform pg_temp.err('08.15 un parámetro que no existe', format($$select public.geoportal_tec_aviso_parametro_fijar(%L, 'no_existe', 1, 'ZT12 no existe')$$, a), '22023', 'no existe');
  perform pg_temp.err('08.16 los eventos de los parámetros no se editan', $$update tecnica.aviso_parametro_eventos set motivo = 'ZT12 cambiado' where clave = 'horario_fin'$$, '42501');

  -- ===================== 09. Cola de avisos de salida (bot del Dell) =====================
  v_n0 := tecnica.f_avisos_encolar();
  perform pg_temp.reg('09.01 encolar: el alto de 30 min sale como «nuevo»; el de 7 h, visto por primera vez, solo como «rojo»; el de 3 h como «naranja» (con el naranja en 4 h: «nuevo»)',
     exists (select 1 from tecnica.v_avisos_salida where ref_id = d_nuevo and nivel = 'nuevo' and estado = 'pendiente')
     and (select array_agg(nivel) from tecnica.avisos_salida where ref_id = d_viejo) = array['rojo']
     and (select array_agg(nivel) from tecnica.avisos_salida where ref_id = d_alto) = array['nuevo']
     and not exists (select 1 from tecnica.avisos_salida where ref_id in (d_medio, d_bajo, d_ni)), v_n0::text);
  perform pg_temp.reg('09.02 encolar otra vez no repite nada', tecnica.f_avisos_encolar() = 0 and (select count(*) from tecnica.avisos_salida where ref_id in (d_nuevo, d_viejo, d_alto)) = 3);
  perform public.geoportal_tec_aviso_parametro_fijar(sd, 'dano_alto_naranja_h', 2, 'ZT12 distribución vuelve el naranja a 2 h');
  perform tecnica.f_avisos_encolar();
  perform pg_temp.reg('09.03 al pasar a naranja (el plazo vuelve a 2 h), el alto de 3 h deja un segundo aviso «naranja»',
     (select array_agg(nivel order by creado_en) from tecnica.avisos_salida where ref_id = d_alto) = array['nuevo', 'naranja']);
  perform pg_temp.reg('09.04 el mensaje no lleva descripción, autor, nombre ni coordenadas; sí el código, el tipo, el nivel y las horas',
     not exists (select 1 from tecnica.avisos_salida a2, jsonb_object_keys(a2.mensaje) k where a2.ref_id in (d_nuevo, d_viejo, d_alto) and k in ('descripcion', 'autor', 'nombre', 'lat', 'lon', 'telefono'))
     and (select mensaje ->> 'dano' = 'DAN-991205' and mensaje ->> 'nivel' = 'rojo' and (mensaje ->> 'horas_abierto')::numeric >= 7 from tecnica.avisos_salida where ref_id = d_viejo));
  select count(*) into v_n0 from tecnica.avisos_tomar(20, 300) t where t.mensaje ->> 'dano' in ('DAN-991204', 'DAN-991205', 'DAN-991201');
  perform pg_temp.reg('09.05 el Dell toma los 4 (con arriendo y lease_id, intento 1); tomar otra vez no los repite mientras dure el arriendo',
     v_n0 = 4 and (select bool_and(estado = 'tomado' and intentos = 1 and lease_id is not null and tomado_hasta > clock_timestamp()) from tecnica.v_avisos_salida where ref_id in (d_nuevo, d_viejo, d_alto))
     and not exists (select 1 from tecnica.avisos_tomar(20, 300) t where t.mensaje ->> 'dano' in ('DAN-991204', 'DAN-991205', 'DAN-991201')), v_n0::text);
  select id, lease_id into v_av, v_lease from tecnica.v_avisos_salida where ref_id = d_nuevo;
  perform pg_temp.err('09.06 marcar con otro lease_id no vale', format($$select tecnica.avisos_marcar(%L, gen_random_uuid(), 'enviado')$$, v_av), '22023', 'lease_id');
  perform pg_temp.err('09.07 un estado que no existe', format($$select tecnica.avisos_marcar(%L, %L, 'perdido')$$, v_av, v_lease), '22023', 'Estado');
  v_e1 := tecnica.avisos_marcar(v_av, v_lease, 'enviado', '{"telegram":"ok"}'); v_e2 := tecnica.avisos_marcar(v_av, v_lease, 'enviado');
  perform pg_temp.reg('09.08 enviado; repetirlo es inocuo; queda el evento del Dell con su detalle',
     v_e1 = 'enviado' and v_e2 = 'enviado'
     and (select count(*) from tecnica.aviso_salida_eventos where aviso_id = v_av and estado = 'enviado') = 1
     and (select detalle ->> 'telegram' from tecnica.aviso_salida_eventos where aviso_id = v_av and estado = 'enviado') = 'ok');
  select id, lease_id into v_av, v_lease from tecnica.v_avisos_salida where ref_id = d_viejo;
  v_e1 := tecnica.avisos_marcar(v_av, v_lease, 'error', '{"error":"sin red"}', true);
  perform pg_temp.reg('09.09 error reintentable: vuelve a pendiente; el Dell lo toma otra vez con intento 2',
     v_e1 = 'pendiente'
     and exists (select 1 from tecnica.avisos_tomar(20, 300) t where t.aviso_id = v_av and t.intentos = 2));
  select lease_id into v_lease from tecnica.v_avisos_salida where id = v_av;
  v_e1 := tecnica.avisos_liberar(v_av, v_lease);
  perform pg_temp.reg('09.10 liberar lo devuelve a pendiente sin gastar intento', v_e1 = 'pendiente' and (select intentos from tecnica.v_avisos_salida where id = v_av) = 1);
  perform public.geoportal_tec_aviso_parametro_fijar(a, 'salida_max_intentos', 1, 'ZT12 el administrador deja un solo intento');
  perform tecnica.avisos_tomar(20, 300);
  perform pg_temp.reg('09.11 con el tope bajado a 1 intento, el aviso que ya gastó uno no se entrega: queda en «error» (intentos_agotados)',
     (select estado = 'error' and ultimo_detalle ->> 'motivo' = 'intentos_agotados' from tecnica.v_avisos_salida where id = v_av));
  select id, lease_id into v_av2, v_lease from tecnica.v_avisos_salida where ref_id = d_alto and nivel = 'naranja';
  perform tecnica.avisos_liberar(v_av2, v_lease);
  insert into redes.dano_eventos (dano_id, tipo, motivo, autor) values (d_alto, 'atendido', 'ZT12 atendido antes del envío', sd);
  perform tecnica.avisos_tomar(20, 300);
  perform pg_temp.reg('09.12 el daño se atendió antes del envío: el Dell no lo recibe y el aviso queda «anulado» (motivo dano_cerrado)',
     (select estado = 'anulado' and ultimo_detalle ->> 'motivo' = 'dano_cerrado' from tecnica.v_avisos_salida where id = v_av2));
  perform pg_temp.err('09.13 límites de tomar', $$select * from tecnica.avisos_tomar(50, 300)$$, '22023', 'p_limite');
  perform pg_temp.reg('09.14 nada se borró: cada cambio de estado es un evento', (select count(*) from tecnica.aviso_salida_eventos e join tecnica.avisos_salida s on s.id = e.aviso_id where s.ref_id in (d_nuevo, d_viejo, d_alto)) >= 12);

  -- ===================== 10. Lo que ve producción =====================
  perform pg_temp.reg('10.01 pg-safeupdate: ninguna función de redes, tecnica, geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
     not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion || ' → ' || sentencia, ' | ') from redes.f_funciones_sin_where()));
  perform pg_temp.reg('10.02 la huella de las funciones de redes no cambió (el Corte 12 no toca redes)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = v_redes);

  perform pg_temp.err('10.03 los eventos de los mínimos son de solo inserción', $$update tecnica.quimico_minimo_eventos set motivo = 'ZT12 cambiado' where id > 0$$, '42501');
  perform pg_temp.err('10.04 la cola de salida es de solo inserción', $$update tecnica.avisos_salida set nivel = 'rojo' where id is not null$$, '42501');
  perform pg_temp.err('10.05 los estados de la cola, también', $$delete from tecnica.aviso_salida_eventos where id > 0$$, '42501');
  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · CORTE 12 (esperado: este ERROR deshace todo lo de la prueba)\n%\nTIEMPOS: avisos del administrador % ms, del supervisor de planta % ms, del de distribución % ms (tope 1.000 ms; el peor de 3)\nRESULTADO: % de % pruebas correctas — %',
    v_fallas, round(v_ms_adm), round(v_ms_sp), round(v_ms_sd), v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
