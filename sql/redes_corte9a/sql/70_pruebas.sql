-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base, ni que el Plan Maestro esté cargado: arma sus personas (prueba.redes13.*), sus activos (ZT13, en un rincón de
-- Valledupar, lejos de los datos reales), sus polígonos de sector (números 91 y 92), sus nodos y sus cargas de referencia. Si el Plan ya está cargado,
-- las cargas de prueba lo tapan dentro de esta transacción y el ERROR final lo deja como estaba.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 9a … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- posición de prueba: x, y en metros aproximados desde un rincón de Valledupar, lejos de los datos reales
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4200 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.3000 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.caja(x0 numeric, y0 numeric, x1 numeric, y1 numeric) returns geometry language sql as $$
  select ST_SetSRID(ST_MakeEnvelope(pg_temp.lon(x0), pg_temp.lat(y0), pg_temp.lon(x1), pg_temp.lat(y1)), 4326) $$;
-- un activo de prueba COMO SI viniera de su capa (con capa y llave), para poder amarrarlo a los datos de referencia por su llave
create function pg_temp.activo(p_prefijo text, p_geom geometry, p_capa text, p_llave text, p_estado text default 'en_operacion', p_clase text default null,
                               p_attr jsonb default '{}'::jsonb, p_nombre text default null) returns text language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes13.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, estado_codigo, atributos, codigo_anterior, capa_codigo, llave_capa, huella, autor)
  values (v_id, 1, p_geom, coalesce(p_nombre, 'ZT13 ' || p_prefijo), p_clase, case when p_prefijo = 'VAL' then 'sin_definir' end,
          case when p_prefijo in ('RED', 'COL') then (select codigo from redes.materiales order by orden limit 1) end, case when p_prefijo in ('RED', 'COL') then 110 end,
          p_estado, p_attr, p_llave, p_capa, p_llave, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT13 activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_cod;
end $$;
create function pg_temp.carga_ref(p_conjunto text) returns bigint language sql as $$
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, autor) values (p_conjunto, 'zt13_' || p_conjunto || '.csv', md5('zt13' || p_conjunto || clock_timestamp()::text), 1,
         'ZT13 origen de prueba', 'prueba.redes13.adm@emdupar.gov.co') returning id $$;
create function pg_temp.trae(p_b64 text, p_txt text) returns boolean language sql as $$
  select coalesce(position(convert_to(p_txt, 'UTF8') in decode(nullif(p_b64, ''), 'base64')) > 0, false) $$;
create function pg_temp.tx(p_z integer, x numeric) returns integer language sql as $$ select floor((pg_temp.lon(x) + 180) / 360 * (1 << p_z))::integer $$;
create function pg_temp.ty(p_z integer, y numeric) returns integer language sql as $$
  select floor((1 - ln(tan(radians(pg_temp.lat(y))) + 1 / cos(radians(pg_temp.lat(y)))) / pi()) / 2 * (1 << p_z))::integer $$;
create function pg_temp.ref(p_quien text, p_capa text, p_z integer, x numeric, y numeric) returns text language sql as $$
  select public.geoportal_redes_geovisor_mvt_ref(p_quien, p_capa, p_z, pg_temp.tx(p_z, x), pg_temp.ty(p_z, y)) $$;
create function pg_temp.filas(p jsonb) returns text language sql as $$ select coalesce(string_agg((f ->> 'r') || '=' || (f ->> 'v'), ' | '), '') from jsonb_array_elements(p) f $$;
create function pg_temp.grupo(p jsonb, p_titulo text) returns jsonb language sql as $$ select g from jsonb_array_elements(coalesce(p, '[]'::jsonb)) g where g ->> 'titulo' = p_titulo limit 1 $$;
create function pg_temp.archivo(p_ruta text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg')) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;

do $prueba$
declare
  a text := 'prueba.redes13.adm@emdupar.gov.co'; sd text := 'prueba.redes13.dist@emdupar.gov.co'; sv text := 'prueba.redes13.planta@emdupar.gov.co';
  op text := 'prueba.redes13.op@emdupar.gov.co'; na text := 'prueba.redes13.nada@emdupar.gov.co';
  C1 text := '990000001301';
  v_r jsonb; v_x jsonb; v_t text; v_n integer; v_m integer; v_c bigint; v_c2 bigint; v_carga bigint; v_s record;
  v_sec text; v_sub1 text; v_sub2 text; v_sec2 text; v_red text; v_val text; v_tor text; v_col text; v_poz text; v_pozok text; v_tan text;
  n_val bigint; n_prop bigint; n_calc bigint; n_tan bigint; n_sin bigint;
  v_ver0 integer; v_p jsonb; v_dano jsonb; v_act0 bigint;
  v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_ms4 numeric; v_ms5 numeric;
  v_info text; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT13 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT13 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT13 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT13 Operador', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT13 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT13 necesita ver la red en la calle');

  -- ===================== 01. Esquema, permisos y lo que NO cambia =====================
  perform pg_temp.reg('01.01 las 10 tablas de referencia existen, con RLS y sin privilegios para anon, authenticated ni service_role',
     (select count(*) from pg_class c where c.relnamespace = 'redes'::regnamespace and c.relkind = 'r' and c.relrowsecurity
        and c.relname in ('ref_cargas', 'ref_carga_eventos', 'pm_nodos', 'pm_tramos', 'pm_valvulas', 'pm_presion_hora', 'pm_alc_conductos', 'pm_alc_pozos', 'ref_elementos', 'pm_campana_lecturas')
        and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select, insert')) = 10);
  v_carga := pg_temp.carga_ref('zt13_solo_agregar');
  perform pg_temp.err('01.02 las cargas de referencia son de solo inserción: no se pueden cambiar', format('update redes.ref_cargas set filas = 2 where id = %s', v_carga));
  perform pg_temp.err('01.03 … ni borrar', format('delete from redes.ref_cargas where id = %s', v_carga));
  perform pg_temp.reg('01.04 las 7 funciones internas nuevas no las ejecuta la API; las 6 RPC nuevas, solo service_role',
     not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname in ('f_ref_vigente', 'f_sector_de', 'f_pm_nivel_presion', 'f_pm_sugerencia', 'f_nodo_modelo', 'f_ficha_referencia', 'f_pm_marcar_por_verificar')
                   and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')))
     and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
            and p.proname in ('geoportal_redes_geovisor_mvt_ref', 'geoportal_redes_referencia', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_nodo_clasificar', 'geoportal_redes_por_verificar', 'geoportal_redes_activo_verificar')
            and p.prosecdef and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')) = 6);
  perform pg_temp.reg('01.05 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
     not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion || ' → ' || sentencia, ' | ') from redes.f_funciones_sin_where()));
  perform pg_temp.reg('01.06 todo lo que lee el 9a es STABLE (ninguna petición de lectura escribe ni recalcula): teselas, tarjetas, bandejas, ficha preliminar y la ficha',
     (select count(*) from pg_proc p where p.provolatile = 's' and ((p.pronamespace = 'public'::regnamespace
        and p.proname in ('geoportal_redes_geovisor_mvt_ref', 'geoportal_redes_referencia', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_por_verificar', 'geoportal_redes_nodos_por_clasificar',
                          'geoportal_redes_geovisor_mvt', 'geoportal_redes_danos', 'geoportal_redes_intervenciones'))
        or (p.pronamespace = 'redes'::regnamespace and p.proname in ('f_ficha', 'f_sector_de', 'f_ficha_referencia', 'f_nodo_modelo')))) = 12);
  perform pg_temp.reg('01.07 catálogo del geovisor: 5 capas de referencia activas y apagadas al abrir; 4 son solo de supervisores (la red pluvial existente la ve también el operador)',
     (select count(*) from redes.geovisor_capas where fuente = 'referencia' and activa) = 5 and (select count(*) from redes.geovisor_capas where fuente = 'referencia' and solo_completo) = 4
     and (select solo_completo from redes.geovisor_capas where codigo = 'pluvial') = false
     and not exists (select 1 from redes.capas_por_perfil c join redes.geovisor_capas g on g.codigo = c.capa where g.fuente = 'referencia' and c.encendida));
  perform pg_temp.reg('01.08 los sectores: encendidos al abrir para el supervisor de distribución y el operador, con la nota «Proyectados por el Plan Maestro 2014»',
     (select count(*) from redes.capas_por_perfil where capa = 'sectores' and encendida and perfil in ('supervisor_distribucion', 'operador_distribucion')) = 2
     and (select nota from redes.geovisor_capas where codigo = 'sectores') like 'Proyectados por el Plan Maestro 2014%');
  perform pg_temp.reg('01.09 los 4 umbrales de presión son parámetros editables (15, 10, 50 y 60 m.c.a.) y SEC tiene las clases «sector» y «subsector»',
     (select string_agg(trim_scale(valor)::text, ',' order by clave) from redes.parametros where clave like 'presion\_%\_mca') = '50,60,15,10'
     and (select count(*) from redes.clases_activo where prefijo = 'SEC' and codigo in ('sector', 'subsector') and activo) = 2,
     (select string_agg(clave || '=' || valor, ',' order by clave) from redes.parametros where clave like 'presion\_%\_mca'));
  perform pg_temp.reg('01.10 la vista de nodos conserva sus 10 columnas y un solo nodo vigente por llave', (select count(*) from information_schema.columns where table_schema = 'redes' and table_name = 'v_nodo_vigente') = 10
     and not exists (select 1 from redes.v_nodo_vigente group by sistema, llave_modelo having count(*) > 1));
  perform pg_temp.reg('01.11 ninguna función nueva del 9a escribe en la ficha oficial (activo_versiones): el «efecto» de las válvulas no se toca',
     not exists (select 1 from pg_proc p where (p.pronamespace = 'redes'::regnamespace and p.proname in ('f_ref_vigente', 'f_sector_de', 'f_pm_nivel_presion', 'f_pm_sugerencia', 'f_nodo_modelo', 'f_ficha_referencia', 'f_pm_marcar_por_verificar')
                   or p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_geovisor_mvt_ref', 'geoportal_redes_referencia', 'geoportal_redes_nodo_preliminar', 'geoportal_redes_nodo_clasificar', 'geoportal_redes_por_verificar', 'geoportal_redes_activo_verificar'))
                   and p.prosrc ~* '(insert\s+into|update)\s+redes\.activo_versiones'));

  -- ===================== 02. Sector y subsector por geometría (calculado, no escrito) =====================
  -- un sector (91) de 400 × 200 m con dos subsectores que cubren su mitad izquierda (91.1) y parte de la derecha (91.2); otro sector (92) aparte
  v_sec := pg_temp.activo('SEC', pg_temp.caja(0, 0, 400, 200), 'sectores', 'ZT13-SECTOR-91', 'proyectado', 'sector', '{"modelo": {"sector": 91, "origen": "ZT13"}}', 'ZT13 Sector 91');
  v_sub1 := pg_temp.activo('SEC', pg_temp.caja(0, 0, 200, 200), 'sectores', 'ZT13-SUB-91.1', 'proyectado', 'subsector', '{"modelo": {"sector": 91, "subsector": "91.1"}}', 'ZT13 Subsector 91.1');
  v_sub2 := pg_temp.activo('SEC', pg_temp.caja(200, 0, 300, 200), 'sectores', 'ZT13-SUB-91.2', 'proyectado', 'subsector', '{"modelo": {"sector": 91, "subsector": "91.2"}}', 'ZT13 Subsector 91.2');
  v_sec2 := pg_temp.activo('SEC', pg_temp.caja(0, 400, 200, 600), 'sectores', 'ZT13-SECTOR-92', 'proyectado', 'sector', '{"modelo": {"sector": 92}}', 'ZT13 Sector 92');
  select * into v_s from redes.f_sector_de(pg_temp.pt(50, 50));
  perform pg_temp.reg('02.01 un punto dentro de un subsector toma su sector y su subsector (91 y 91.1), con el código y el nombre del polígono', v_s.sector = 91 and v_s.subsector = '91.1' and v_s.codigo = v_sub1 and v_s.nombre = 'ZT13 Subsector 91.1', row_to_json(v_s)::text);
  select * into v_s from redes.f_sector_de(pg_temp.pt(350, 50));
  perform pg_temp.reg('02.02 un punto dentro del sector y fuera de todo subsector toma solo el sector (91, sin subsector)', v_s.sector = 91 and v_s.subsector is null and v_s.codigo = v_sec, row_to_json(v_s)::text);
  select * into v_s from redes.f_sector_de(pg_temp.pt(50, 500));
  perform pg_temp.reg('02.03 otro sector, sin subsectores: 92', v_s.sector = 92 and v_s.subsector is null, row_to_json(v_s)::text);
  select * into v_s from redes.f_sector_de(pg_temp.pt(900, 900));
  perform pg_temp.reg('02.04 fuera de todos los polígonos: sin sector (no se inventa)', v_s.sector is null and v_s.subsector is null and v_s.codigo is null);
  select * into v_s from redes.f_sector_de(ST_SetSRID(ST_MakeLine(pg_temp.pt(210, 100), pg_temp.pt(290, 100)), 4326));
  perform pg_temp.reg('02.05 un tramo toma el sector por un punto sobre su línea (91.2)', v_s.sector = 91 and v_s.subsector = '91.2', row_to_json(v_s)::text);
  -- activos de prueba dentro del 91.1
  v_red := pg_temp.activo('RED', ST_SetSRID(ST_MakeLine(pg_temp.pt(40, 50), pg_temp.pt(100, 50)), 4326), 'acueducto', 'ZT13-T1');
  v_val := pg_temp.activo('VAL', pg_temp.pt(40, 50), 'acueducto_nodos', 'ZT13-N1', 'en_operacion', 'cierre');
  v_tor := pg_temp.activo('TOR', pg_temp.pt(100, 50), 'acueducto_nodos', 'ZT13-N2');
  v_col := pg_temp.activo('COL', ST_SetSRID(ST_MakeLine(pg_temp.pt(40, 80), pg_temp.pt(100, 80)), 4326), 'alc_conductos', 'ZT13-C1');
  v_poz := pg_temp.activo('POZ', pg_temp.pt(40, 80), 'alc_pozos', 'ZT13-MHP1');
  v_pozok := pg_temp.activo('POZ', pg_temp.pt(100, 80), 'alc_pozos', 'ZT13-P2');
  v_r := public.geoportal_redes_activo(sd, v_red);
  perform pg_temp.reg('02.06 la ficha del tramo trae «sector_plan» (91, 91.1, con el polígono de donde sale); la del propio sector no',
     v_r -> 'sector_plan' ->> 'sector' = '91' and v_r -> 'sector_plan' ->> 'subsector' = '91.1' and v_r -> 'sector_plan' ->> 'codigo' = v_sub1
     and not (public.geoportal_redes_activo(sd, v_sec) ? 'sector_plan'), (v_r -> 'sector_plan')::text);
  perform pg_temp.reg('02.07 el operador también ve el sector en la ficha', public.geoportal_redes_activo(op, v_red) -> 'sector_plan' ->> 'sector' = '91');
  -- «otra versión de los polígonos»: se retira el subsector 91.1 (como cuando una carga nueva no lo trae). Sin recalcular nada, el sector cambia solo.
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) select id, 'retirar', 'ZT13 otra versión de los polígonos no lo trae', a from redes.activos where codigo = v_sub1;
  perform redes.f_mat_refrescar_uno((select id from redes.activos where codigo = v_sub1));
  perform pg_temp.reg('02.08 al cambiar los polígonos vigentes (se retira el 91.1), el mismo activo pasa a «91 sin subsector» sin recalcular ninguna tabla',
     public.geoportal_redes_activo(sd, v_red) -> 'sector_plan' ->> 'sector' = '91' and not (public.geoportal_redes_activo(sd, v_red) -> 'sector_plan' ? 'subsector'),
     (public.geoportal_redes_activo(sd, v_red) -> 'sector_plan')::text);
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) select id, 'reactivar', 'ZT13 vuelve el subsector 91.1', a from redes.activos where codigo = v_sub1;
  perform redes.f_mat_refrescar_uno((select id from redes.activos where codigo = v_sub1));
  perform pg_temp.reg('02.09 … y al volver el polígono, vuelve el subsector', public.geoportal_redes_activo(sd, v_red) -> 'sector_plan' ->> 'subsector' = '91.1');
  v_t := public.geoportal_redes_geovisor_mvt(sd, 14, pg_temp.tx(14, 100), pg_temp.ty(14, 100));
  perform pg_temp.reg('02.10 la tesela del geovisor trae los sectores con su nombre (para la tarjeta) y su clase', pg_temp.trae(v_t, v_sub1) and pg_temp.trae(v_t, 'ZT13 Subsector 91.1') and pg_temp.trae(v_t, 'subsector'));

  -- ===================== 03. Datos de referencia del Plan en la ficha (tablas aparte; la ficha oficial no cambia) =====================
  select count(*) into v_ver0 from redes.activo_versiones;
  v_c := pg_temp.carga_ref('pm_nodos');
  insert into redes.pm_nodos (carga_id, llave, nombre, tipo, que_es, zona_modelo, nota_modelo, activo_modelo, estado_modelo, estado_difiere, cota_m, n_tramos, demanda_exist_lps, demanda_futura_lps,
                              pres_exist_min, pres_exist_max, pres_exist_media, pres_exist_mediana, pres_exist_negativa, pres_futura_min, pres_futura_max, pres_futura_media, pres_futura_mediana, geom) values
    (v_c, 'ZT13-N1', 'ZT13V1', 'válvula', 'otro', null, 'Abierto', true, 'en_operacion', false, 180.5, 2, 0.5, 0.7, -3, 12, 8, 9, true, 30, 40, 35, 36, pg_temp.pt(40, 50)),
    (v_c, 'ZT13-N2', 'ZT13 Torre', 'hidrante', 'hidrante', 'Fuera de Servicio', null, false, 'fuera_servicio', true, 181, 1, 0, 0, 20, 30, 25, 26, false, 50, 70, 60, 61, pg_temp.pt(100, 50)),
    (v_c, 'ZT13-S1', 'ZT13S-1', 'válvula', 'válvula de sectorización propuesta (no instalada)', 'Proyectado', null, true, 'proyectado', false, 179, 2, 0, 0.2, null, null, null, null, null, 40, 45, 42, 43, pg_temp.pt(60, 50)),
    (v_c, 'ZT13-J1', 'ZT13J-1', 'unión', 'nodo de cálculo J-…', null, 'Normal', true, 'en_operacion', false, 178, 2, 0.1, 0.1, 5, 14, 11, 12, false, 30, 33, 31, 32, pg_temp.pt(80, 50)),
    (v_c, 'ZT13-TQ', 'ZT13 Módulo Existente', 'tanque', 'tanque', null, null, true, 'en_operacion', false, 212, 1, 0, 0, 18, 22, 20, 20, false, 2, 4, 3, 3, pg_temp.pt(120, 50));
  v_c := pg_temp.carga_ref('pm_valvulas');
  insert into redes.pm_valvulas (carga_id, llave, nombre, estado_existente, estado_futuro, difiere_entre_modelos, estado_catastro, estado_contradictorio, verificar_en_campo, efecto_sugerido, cierre_nodos_sin_agua, cierre_demanda_lps, diametro_mm)
  values (v_c, 'ZT13-N1', 'ZT13V1', 'abierta', 'cerrada', true, 'cerrada', true, true, 'cierra (deja nodos sin agua)', 105, 3.2, 152);
  v_c := pg_temp.carga_ref('pm_tramos');
  insert into redes.pm_tramos (carga_id, llave, clase_red, nota_modelo, zona_modelo, activo_modelo, estado_modelo, estado_difiere, frontera_sectores, q_max_futuro_lps, v_max_futuro_mps)
  values (v_c, 'ZT13-T1', 'existente activo', 'Fuera de Servicio', null, true, 'fuera_servicio', true, false, 12.5, 0.8);
  v_c := pg_temp.carga_ref('pm_alc_conductos');
  insert into redes.pm_alc_conductos (carga_id, llave, origen, cod_tubo_catastro, material, diametro_mm, diametro_nominal_pulg, estado_fisico, estado_operacional, tipo_red, prof_inicial_m, prof_final_m, datos)
  values (v_c, 'ZT13-C1', 'catastro, misma etiqueta', 'ZT13T1', 'PVC', 230, 10, 'Bueno', 'Limpio', 'Red Menor', 1.5, 1.8, '[{"r": "Pendiente", "v": 0.47, "u": "%"}]');
  v_c := pg_temp.carga_ref('pm_alc_pozos');
  insert into redes.pm_alc_pozos (carga_id, llave, familia, en_catastro, verificacion, por_verificar, estado_pozo, profundidad_m, fecha_inspeccion, datos) values
    (v_c, 'ZT13-MHP1', 'MHP', false, 'POR VERIFICAR: figura como existente en la Alternativa 1 y no está en el catastro levantado', true, null, null, null, '[]'),
    (v_c, 'ZT13-P2', 'P', true, 'en el catastro levantado', false, 'VISIBLE', 1.71, '2013-09-13', '[{"r": "Estado de la tapa", "v": "Buena"}]');
  v_r := public.geoportal_redes_activo(sd, v_val);
  v_x := pg_temp.grupo(v_r -> 'referencia', 'Válvula: sugerencia del modelo');
  perform pg_temp.reg('03.01 la ficha de la válvula trae la SUGERENCIA del modelo (efecto sugerido, nodos y demanda sin agua, estado en los dos modelos y en el catastro), con su advertencia',
     pg_temp.filas(v_x -> 'filas') like '%Efecto sugerido por el modelo=cierra (deja nodos sin agua)%' and pg_temp.filas(v_x -> 'filas') like '%nodos sin agua=105%'
     and pg_temp.filas(v_x -> 'filas') like '%Estado en la red existente (modeloV1)=abierta%' and pg_temp.filas(v_x -> 'filas') like '%Los dos modelos difieren=Sí%'
     and v_x ->> 'advertencia' like 'Es una sugerencia. El «Efecto en la red» oficial lo define el supervisor%Estado por verificar en campo.' and v_x ->> 'origen' = 'ZT13 origen de prueba', v_x::text);
  perform pg_temp.reg('03.02 el campo oficial «efecto» de la válvula sigue «Sin definir» y no se creó ninguna versión de ningún activo',
     (select efecto from redes.activo_vigente_mat where codigo = v_val) = 'sin_definir' and (select count(*) from redes.activo_versiones) = v_ver0
     and exists (select 1 from jsonb_array_elements(v_r -> 'activo' -> 'campos') c where c ->> 'clave' = 'efecto' and c ->> 'valor' like 'Sin definir%'));
  v_x := pg_temp.grupo(v_r -> 'referencia', 'Presión de modelo');
  perform pg_temp.reg('03.03 la presión va rotulada «Presión de MODELO, no medida» y avisa si el modelo da presión negativa',
     v_x ->> 'advertencia' = 'Presión de MODELO, no medida. El modelo de la red existente da presión negativa en este nodo a alguna hora.'
     and pg_temp.filas(v_x -> 'filas') like 'Red existente: mediana del día=9%' and pg_temp.filas(v_x -> 'filas') like '%Red futura del Plan: mediana=36%', v_x::text);
  v_x := pg_temp.grupo(public.geoportal_redes_activo(sd, v_red) -> 'referencia', 'Modelo hidráulico');
  perform pg_temp.reg('03.04 la ficha del tramo: clase de red, nota y estado según el modelo, caudal y velocidad futuros, y el aviso de que el estado difiere',
     pg_temp.filas(v_x -> 'filas') like 'Clase de red=existente activo%' and pg_temp.filas(v_x -> 'filas') like '%Estado según el modelo=Fuera de servicio%'
     and pg_temp.filas(v_x -> 'filas') like '%Caudal máximo (red futura del Plan)=12.5%' and v_x ->> 'advertencia' like 'El estado del modelo es distinto%', v_x::text);
  v_x := pg_temp.grupo(public.geoportal_redes_activo(sd, v_col) -> 'referencia', 'Catastro de alcantarillado 2014');
  perform pg_temp.reg('03.05 la ficha del conducto de alcantarillado: lo que aporta el catastro de 2014 (diámetro nominal, profundidades, estado) más lo demás, ya rotulado',
     pg_temp.filas(v_x -> 'filas') like '%Diámetro nominal=10%' and pg_temp.filas(v_x -> 'filas') like '%Profundidad inicial=1.5%' and pg_temp.filas(v_x -> 'filas') like '%Pendiente=0.47', v_x::text);
  v_x := pg_temp.grupo(public.geoportal_redes_activo(sd, v_poz) -> 'referencia', 'Catastro de alcantarillado 2014');
  perform pg_temp.reg('03.06 el pozo MHP: «por verificar en campo» en la referencia; el pozo del catastro trae su detalle y la fecha de inspección',
     v_x ->> 'advertencia' like 'Figura como existente en la Alternativa 1 del Plan y no está en el catastro levantado%'
     and pg_temp.filas(pg_temp.grupo(public.geoportal_redes_activo(sd, v_pozok) -> 'referencia', 'Catastro de alcantarillado 2014') -> 'filas') like '%Fecha de inspección=2013-09-13 | Estado de la tapa=Buena', v_x::text);
  perform pg_temp.reg('03.07 la ficha oficial de esos activos no cambió: mismas versiones (1) y mismo estado',
     (select count(*) from redes.activo_vigente_mat where codigo in (v_val, v_red, v_col, v_poz, v_pozok, v_tor) and version = 1 and estado_codigo = 'en_operacion') = 6
     and (select count(*) from redes.activo_versiones) = v_ver0);
  -- una carga más nueva gana; una anulada deja de valer (nada se borra)
  v_c2 := pg_temp.carga_ref('pm_valvulas');
  insert into redes.pm_valvulas (carga_id, llave, nombre, estado_existente, efecto_sugerido) values (v_c2, 'ZT13-N1', 'ZT13V1', 'cerrada', 'deriva (el agua llega por otro lado)');
  perform pg_temp.reg('03.08 si se carga otra versión de la referencia, la ficha muestra la nueva (la anterior no se borra)',
     pg_temp.filas(pg_temp.grupo(public.geoportal_redes_activo(sd, v_val) -> 'referencia', 'Válvula: sugerencia del modelo') -> 'filas') like 'Efecto sugerido por el modelo=deriva%'
     and (select count(*) from redes.pm_valvulas where llave = 'ZT13-N1') = 2);
  insert into redes.ref_carga_eventos (carga_id, tipo, motivo, autor) values (v_c2, 'anular', 'ZT13 la carga nueva estaba mal', a);
  perform pg_temp.reg('03.09 al anular esa carga (evento con motivo), vuelve a valer la anterior',
     pg_temp.filas(pg_temp.grupo(public.geoportal_redes_activo(sd, v_val) -> 'referencia', 'Válvula: sugerencia del modelo') -> 'filas') like 'Efecto sugerido por el modelo=cierra%');
  -- el activo creado desde un nodo (como el tanque La Popa) toma la referencia por la llave de su nodo
  v_c2 := redes.f_activo_crear('TAN', pg_temp.pt(120, 50), null, null, null, 'ZT13 Tanque', null, '{"creado_desde_nodo": "ZT13-TQ"}'::jsonb, 'emdupar', null, a, 'ZT13 tanque de prueba creado desde su nodo');
  select codigo into v_tan from redes.activos where id = v_c2;
  perform pg_temp.reg('03.10 un activo creado desde un nodo «por clasificar» (el caso del tanque La Popa) toma la referencia del modelo por la llave de su nodo',
     pg_temp.filas(pg_temp.grupo(public.geoportal_redes_activo(sd, v_tan) -> 'referencia', 'Modelo hidráulico') -> 'filas') like 'Tipo en el modelo=tanque%');

  -- ===================== 04. «Por verificar»: la marca, la bandeja y «verificado» =====================
  perform pg_temp.reg('04.01 la vista señala los 4 activos de prueba que el Plan deja por verificar: la torre y el tramo (estado), la válvula y el pozo MHP; no el pozo del catastro',
     (select array_agg(m.codigo || ':' || x.grupo order by m.codigo, x.grupo) from redes.v_pm_por_verificar x join redes.activo_vigente_mat m on m.activo_id = x.activo_id
       where m.codigo in (v_val, v_red, v_tor, v_poz, v_pozok, v_col)) = (select array_agg(c order by c) from unnest(array[v_val || ':valvula', v_red || ':estado', v_tor || ':estado', v_poz || ':pozo']) c),
     (select string_agg(m.codigo || ':' || x.grupo, ', ') from redes.v_pm_por_verificar x join redes.activo_vigente_mat m on m.activo_id = x.activo_id where m.codigo in (v_val, v_red, v_tor, v_poz, v_pozok, v_col)));
  select count(distinct activo_id) into v_n from redes.v_pm_por_verificar x
   where not exists (select 1 from redes.activo_eventos e where e.activo_id = x.activo_id and e.tipo = 'por_verificar' and e.motivo like 'Plan Maestro 2014:%');
  v_m := redes.f_pm_marcar_por_verificar(a);
  perform pg_temp.reg('04.02 marcar «por verificar» deja UN evento con motivo por activo señalado (y nada más)', v_m = v_n and v_m >= 4
     and (select count(*) from redes.activo_eventos e join redes.activos x on x.id = e.activo_id where x.codigo in (v_val, v_red, v_tor, v_poz) and e.tipo = 'por_verificar' and e.motivo like 'Plan Maestro 2014: %') = 4,
     format('%s marcados de %s', v_m, v_n));
  perform pg_temp.reg('04.03 repetir la marca no duplica nada', redes.f_pm_marcar_por_verificar(a) = 0);
  v_r := public.geoportal_redes_activo(sd, v_tor);
  perform pg_temp.reg('04.04 la ficha de la torre: «por verificar», con el motivo (el modelo la da «Fuera de servicio» y la ficha «En operación»); su estado oficial no cambió',
     (v_r -> 'activo' ->> 'por_verificar')::boolean and v_r ->> 'por_verificar_motivo' = 'Plan Maestro 2014: el modelo lo da «Fuera de servicio» y la ficha «En operación»'
     and v_r -> 'activo' ->> 'estado_codigo' = 'en_operacion', v_r ->> 'por_verificar_motivo');
  v_r := public.geoportal_redes_por_verificar(sd);
  perform pg_temp.reg('04.05 la bandeja del supervisor: los grupos con su cuenta y, por activo, código, tipo, estado, motivo y ubicación',
     (select (g ->> 'n')::integer from jsonb_array_elements(v_r -> 'grupos') g where g ->> 'grupo' = 'valvula') >= 1 and (v_r ->> 'total')::integer >= 4
     and jsonb_array_length(v_r -> 'items') between 4 and 50, (v_r -> 'grupos')::text);
  v_r := public.geoportal_redes_por_verificar(sd, 'pozo', null, 200);
  perform pg_temp.reg('04.06 el filtro por grupo: en «pozo» está el MHP de prueba con su motivo y no la válvula',
     (exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ->> 'codigo' = v_poz and i ->> 'motivo' like 'Plan Maestro 2014: pozo MHP que figura como existente%' and i ->> 'grupo' = 'pozo')
      or (v_r ->> 'total')::integer > 200)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ->> 'codigo' = v_val), left((v_r -> 'items')::text, 300));
  perform pg_temp.err('04.07 el operador no ve la bandeja', format('select public.geoportal_redes_por_verificar(%L)', op), '42501');
  perform pg_temp.err('04.08 … ni quien no es de Técnica', format('select public.geoportal_redes_por_verificar(%L)', na), '42501');
  perform pg_temp.err('04.09 un grupo que no existe se rechaza', format('select public.geoportal_redes_por_verificar(%L, %L)', sd, 'todo'), null, 'Ese grupo no existe');
  perform pg_temp.err('04.10 «verificado» exige decir lo que se encontró', format('select public.geoportal_redes_activo_verificar(%L, %L, %L)', sd, v_val, 'ok'), null, 'Escriba lo que se encontró');
  perform pg_temp.err('04.11 el operador no marca verificado', format('select public.geoportal_redes_activo_verificar(%L, %L, %L)', op, v_val, 'ZT13 se revisó en campo y opera'), '42501');
  v_r := public.geoportal_redes_activo_verificar(sd, v_val, 'ZT13 se abrió y se cerró en campo: opera bien');
  perform pg_temp.reg('04.12 el supervisor marca la válvula como verificada: evento con su motivo y su autor; la ficha (estado, efecto, versión) no cambia',
     (v_r ->> 'por_verificar')::boolean = false and (select e.tipo || '|' || e.autor from redes.activo_eventos e join redes.activos x on x.id = e.activo_id where x.codigo = v_val order by e.id desc limit 1) = 'verificar|' || sd
     and (select efecto || '|' || estado_codigo || '|' || version from redes.activo_vigente_mat where codigo = v_val) = 'sin_definir|en_operacion|1'
     and not (public.geoportal_redes_activo(sd, v_val) ? 'por_verificar_motivo'));
  perform pg_temp.reg('04.13 la válvula sale de la bandeja y la verificación queda en la auditoría',
     not exists (select 1 from jsonb_array_elements(public.geoportal_redes_por_verificar(sd, 'valvula', null, 200) -> 'items') i where i ->> 'codigo' = v_val)
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_activo_verificar' and referencia = v_val and email = sd));
  perform pg_temp.err('04.14 verificar dos veces el mismo activo se rechaza', format('select public.geoportal_redes_activo_verificar(%L, %L, %L)', sd, v_val, 'ZT13 otra vez el mismo activo'), null, 'no está por verificar');
  perform pg_temp.reg('04.15 volver a correr la marca del Plan NO vuelve a marcar lo que el supervisor ya verificó', redes.f_pm_marcar_por_verificar(a) = 0
     and not (select por_verificar from redes.v_activo_estado e join redes.activos x on x.id = e.activo_id where x.codigo = v_val));
  perform pg_temp.reg('04.16 el activo nuevo de una inversión (por verificar desde el Corte 3a) entra a la bandeja en el grupo «otros»',
     exists (select 1 from jsonb_array_elements(public.geoportal_redes_por_verificar(sd, 'otros', null, 200) -> 'items') i where i ->> 'codigo' = v_tan));

  -- ===================== 05. Nodos por clasificar: lo que dice el modelo, la sugerencia, la ficha preliminar y confirmar sin crear activo =====================
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor) values ('acueducto', md5('zt13a') || md5('zt13b'), 'shp', 4326, 'ID', 1, 'ZT13 nodos de prueba', a) returning id into v_carga;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values
    ('acueducto', 'ZT13-S1', 'ZT13S-1', 'por_clasificar', pg_temp.pt(60, 50), null, 0, v_carga) returning id into n_prop;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values
    ('acueducto', 'ZT13-J1', 'ZT13J-1', 'por_clasificar', pg_temp.pt(80, 50), null, 0, v_carga) returning id into n_calc;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values
    ('acueducto', 'ZT13-TQ', 'ZT13 Módulo Existente', 'por_clasificar', pg_temp.pt(120, 50), null, 0, v_carga) returning id into n_tan;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id) values
    ('acueducto', 'ZT13-X9', 'ZT13X-9', 'por_clasificar', pg_temp.pt(900, 900), null, 0, v_carga) returning id into n_sin;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id)
  select 'acueducto', 'ZT13-N1', 'ZT13V1', 'activo', pg_temp.pt(40, 50), id, 0, v_carga from redes.activos where codigo = v_val returning id into n_val;
  insert into redes.tramo_nodos (activo_id, version, nodo_ini, nodo_fin, metodo, carga_id) select id, 1, n_val, n_prop, 'modelo', v_carga from redes.activos where codigo = v_red;
  v_r := public.geoportal_redes_nodos_por_clasificar(a, 'zt13', null, 50);
  perform pg_temp.reg('05.01 la bandeja trae, por nodo, lo que es en el modelo y la sugerencia: válvula propuesta → no crear; nodo de cálculo → dejar como nodo; tanque existente → crear TAN',
     (v_r ->> 'total')::integer = 4
     and (select i -> 'sugerencia' ->> 'accion' || '|' || (i -> 'sugerencia' ->> 'clase') || '|' || (i ->> 'que_es') from jsonb_array_elements(v_r -> 'items') i where (i ->> 'nodo_id')::bigint = n_prop) = 'no_crear|propuesta_plan|válvula de sectorización propuesta (no instalada)'
     and (select i -> 'sugerencia' ->> 'accion' || '|' || (i -> 'sugerencia' ->> 'clase') from jsonb_array_elements(v_r -> 'items') i where (i ->> 'nodo_id')::bigint = n_calc) = 'dejar_nodo|nodo_calculo'
     and (select i -> 'sugerencia' ->> 'accion' || '|' || (i -> 'sugerencia' ->> 'prefijo') from jsonb_array_elements(v_r -> 'items') i where (i ->> 'nodo_id')::bigint = n_tan) = 'crear|TAN'
     and (select not (i ? 'sugerencia') and (i ->> 'tramos')::integer = 0 from jsonb_array_elements(v_r -> 'items') i where (i ->> 'nodo_id')::bigint = n_sin), left((v_r -> 'items')::text, 600));
  perform pg_temp.reg('05.02 conserva lo de antes (grupos por nombre, tipos para crear el activo, cuántos tramos llegan) y suma los grupos por sugerencia',
     jsonb_array_length(v_r -> 'tipos') > 0 and jsonb_array_length(v_r -> 'grupos') > 0 and (select (i ->> 'tramos')::integer from jsonb_array_elements(v_r -> 'items') i where (i ->> 'nodo_id')::bigint = n_prop) = 1
     and (select (s ->> 'n')::integer from jsonb_array_elements(v_r -> 'sugerencias') s where s ->> 'accion' = 'sin_modelo') >= 1);
  v_r := public.geoportal_redes_nodos_por_clasificar(a, 'sugerencia:no_crear', null, 200);
  perform pg_temp.reg('05.03 el filtro «sugerencia:no_crear» deja la válvula propuesta y no el nodo de cálculo',
     (exists (select 1 from jsonb_array_elements(v_r -> 'items') i where (i ->> 'nodo_id')::bigint = n_prop) or (v_r ->> 'total')::integer > 200)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'items') i where (i ->> 'nodo_id')::bigint = n_calc));
  perform pg_temp.reg('05.04 la búsqueda también encuentra por lo que el nodo ES en el modelo',
     (public.geoportal_redes_nodos_por_clasificar(a, 'nodo de cálculo', null, 200) ->> 'total')::integer >= 1
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_nodos_por_clasificar(a, 'zt13j', null, 200) -> 'items') i where (i ->> 'nodo_id')::bigint = n_calc and i ->> 'que_es' like 'nodo de cálculo%'));
  perform pg_temp.err('05.05 una sugerencia que no existe se rechaza', format('select public.geoportal_redes_nodos_por_clasificar(%L, %L)', a, 'sugerencia:borrar'), null, 'Esa sugerencia no existe');
  perform pg_temp.err('05.06 la bandeja sigue siendo solo del administrador', format('select public.geoportal_redes_nodos_por_clasificar(%L)', sd), '42501');
  v_r := public.geoportal_redes_nodo_preliminar(a, n_prop);
  perform pg_temp.reg('05.07 ficha preliminar: el punto, el tramo que llega (código, material, diámetro, longitud, su línea para el minimapa y en qué extremo queda el nodo)',
     v_r ->> 'lat' = pg_temp.lat(50)::text and jsonb_array_length(v_r -> 'tramos') = 1 and v_r -> 'tramos' -> 0 ->> 'codigo' = v_red and v_r -> 'tramos' -> 0 ->> 'diametro_mm' = '110'
     and v_r -> 'tramos' -> 0 ->> 'material' is not null and v_r -> 'tramos' -> 0 -> 'linea' ->> 'type' = 'LineString' and v_r -> 'tramos' -> 0 ->> 'extremo' = 'fin', (v_r -> 'tramos')::text);
  perform pg_temp.reg('05.08 ficha preliminar: su sector y subsector (91, 91.1), la cota, y lo que dice el modelo (tipo, qué es, demanda y presión de referencia), con la sugerencia',
     v_r -> 'sector' ->> 'sector' = '91' and v_r -> 'sector' ->> 'subsector' = '91.1' and v_r -> 'modelo' ->> 'cota_m' = '179' and v_r -> 'modelo' ->> 'tipo' = 'válvula'
     and v_r -> 'modelo' ->> 'demanda_futura_lps' = '0.2' and v_r -> 'modelo' ->> 'pres_futura_mediana' = '43' and not (v_r -> 'modelo' ? 'sugerencia')
     and v_r -> 'sugerencia' ->> 'texto' = 'Válvula propuesta por el Plan (no instalada): no crear activo', (v_r - 'tramos')::text);
  v_r := public.geoportal_redes_nodo_preliminar(a, n_sin);
  perform pg_temp.reg('05.09 un nodo que no está en el modelo cargado ni en ningún sector: ficha preliminar sin sugerencia, sin sector y sin tramos (no se inventa nada)',
     not (v_r ? 'sugerencia') and not (v_r ? 'sector') and not (v_r ? 'modelo') and jsonb_array_length(v_r -> 'tramos') = 0, v_r::text);
  perform pg_temp.err('05.10 la ficha preliminar es solo del administrador', format('select public.geoportal_redes_nodo_preliminar(%L, %s)', sd, n_prop), '42501');
  perform pg_temp.err('05.11 un nodo que no existe: no encontrado', format('select public.geoportal_redes_nodo_preliminar(%L, %s)', a, -5), 'P0002');
  select count(*) into v_act0 from redes.activos;
  perform pg_temp.err('05.12 clasificar exige el motivo', format('select public.geoportal_redes_nodo_clasificar(%L, %s, %L, %L)', a, n_prop, 'propuesta_plan', 'corto'), null, 'Escriba el motivo');
  perform pg_temp.err('05.13 … y una clasificación que exista', format('select public.geoportal_redes_nodo_clasificar(%L, %s, %L, %L)', a, n_prop, 'activo', 'ZT13 esto no existe como clase'), null, 'Esa clasificación no existe');
  perform pg_temp.err('05.14 el supervisor no clasifica nodos', format('select public.geoportal_redes_nodo_clasificar(%L, %s, %L, %L)', sd, n_prop, 'propuesta_plan', 'ZT13 válvula que no se instaló'), '42501');
  v_r := public.geoportal_redes_nodo_clasificar(a, n_prop, 'propuesta_plan', 'ZT13 válvula del Plan que no se instaló');
  perform pg_temp.reg('05.15 confirmar la sugerencia: el nodo queda «propuesto por el Plan», sale de la bandeja, NO se crea ningún activo y queda el evento con su motivo y la auditoría',
     (select clase_nodo from redes.v_nodo_vigente where nodo_id = n_prop) = 'propuesta_plan' and (select activo_id from redes.v_nodo_vigente where nodo_id = n_prop) is null
     and (select count(*) from redes.activos) = v_act0 and (public.geoportal_redes_nodos_por_clasificar(a, 'zt13', null, 50) ->> 'total')::integer = 3
     and (select tipo || '|' || clase || '|' || autor from redes.nodo_eventos where nodo_id = n_prop order by id desc limit 1) = 'clasificar|propuesta_plan|' || a
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_nodo_clasificar' and referencia = n_prop::text));
  perform pg_temp.err('05.16 clasificarlo igual dos veces se rechaza', format('select public.geoportal_redes_nodo_clasificar(%L, %s, %L, %L)', a, n_prop, 'propuesta_plan', 'ZT13 otra vez lo mismo'), null, 'ya está así');
  perform pg_temp.err('05.17 un nodo que ya es activo no se clasifica aquí', format('select public.geoportal_redes_nodo_clasificar(%L, %s, %L, %L)', a, n_val, 'nodo_calculo', 'ZT13 esta válvula ya es un activo'), null, 'ya es un activo');
  perform pg_temp.err('05.18 ni se le crea un activo a un nodo ya clasificado', format('select public.geoportal_redes_nodo_crear_activo(%L, %s, %L, %L, %L, %L)', a, n_prop, 'VAL', 'cierre', null, 'ZT13 no debe dejar crear el activo'), null, 'ya no está por clasificar');
  perform public.geoportal_redes_nodo_clasificar(a, n_prop, 'por_clasificar', 'ZT13 sí la instalaron: vuelve a la bandeja');
  v_r := public.geoportal_redes_nodo_crear_activo(a, n_prop, 'VAL', 'cierre', null, 'ZT13 la válvula sí existe en campo');
  perform pg_temp.reg('05.19 nada es definitivo: el nodo vuelve a la bandeja con otro evento y entonces sí se puede crear su activo (queda enlazado)',
     (select clase_nodo || '|' || (activo_id is not null) from redes.v_nodo_vigente where nodo_id = n_prop) = 'activo|true' and v_r ->> 'activo' like 'VAL-%');
  perform public.geoportal_redes_nodo_clasificar(a, n_calc, 'nodo_calculo', 'ZT13 nodo de cálculo del modelo');
  perform pg_temp.reg('05.20 «dejar como nodo»: el nodo de cálculo sale de la bandeja y sigue siendo nodo de la topología (los tramos lo siguen nombrando)',
     (select clase_nodo from redes.v_nodo_vigente where nodo_id = n_calc) = 'nodo_calculo' and (public.geoportal_redes_nodos_por_clasificar(a, 'zt13', null, 50) ->> 'total')::integer = 2);

  -- ===================== 06. Geovisor: capas de referencia (no son activos) =====================
  v_r := public.geoportal_redes_geovisor(sd);
  perform pg_temp.reg('06.01 el supervisor ve las 5 capas de referencia (fuente «referencia», apagadas) y los sectores encendidos',
     (select count(*) from jsonb_array_elements(v_r -> 'capas') c where c ->> 'fuente' = 'referencia' and not (c ->> 'encendida')::boolean) = 5
     and (select (c ->> 'encendida')::boolean from jsonb_array_elements(v_r -> 'capas') c where c ->> 'codigo' = 'sectores'));
  v_r := public.geoportal_redes_geovisor(op);
  perform pg_temp.reg('06.02 el operador en solo lectura ve la red pluvial y los sectores (encendidos), y ninguna capa de supervisión',
     (select array_agg(c ->> 'codigo') from jsonb_array_elements(v_r -> 'capas') c where c ->> 'fuente' = 'referencia') = array['pluvial']
     and (select (c ->> 'encendida')::boolean from jsonb_array_elements(v_r -> 'capas') c where c ->> 'codigo' = 'sectores'));
  v_c := pg_temp.carga_ref('plan_valvulas');
  insert into redes.ref_elementos (carga_id, capa, llave, nombre, clase, estado, valor, datos, geom) values
    (v_c, 'plan_valvulas', 'ZT13-PV1', 'ZT13S-PROP', 'propuesta', 'abierta', 152, '[{"r": "Diámetro", "v": 152, "u": "mm"}]', pg_temp.pt(60, 60));
  v_c := pg_temp.carga_ref('campana_2014');
  insert into redes.ref_elementos (carga_id, capa, llave, nombre, clase, valor, datos, geom) values
    (v_c, 'campana_2014', 'ZT13-CAMP1', 'ZT13 Punto 1 · Cra de prueba', 'medida', 3.2, '[{"r": "Dirección", "v": "ZT13 Cra de prueba"}]', pg_temp.pt(70, 70)),
    (v_c, 'campana_2014', 'ZT13-CAMP6', 'ZT13 Punto 6 · sin coordenada', 'medida', 3.1, '[]', null);
  v_c := pg_temp.carga_ref('campana_2014_lecturas');
  insert into redes.pm_campana_lecturas (carga_id, llave, n, cuando, p_mca) select v_c, 'ZT13-CAMP1', g, timestamp '2014-01-31 14:15' + (g - 1) * interval '15 minutes', 2 + g * 0.1 from generate_series(1, 40) g;
  v_c := pg_temp.carga_ref('pluvial');
  insert into redes.ref_elementos (carga_id, capa, llave, nombre, clase, estado, valor, datos, geom) values
    (v_c, 'pluvial', 'con:ZT13-PL1', 'ZT13-PL1', 'conducto', 'Bueno', 450, '[{"r": "Elemento", "v": "Conducto pluvial"}]', ST_SetSRID(ST_MakeLine(pg_temp.pt(40, 120), pg_temp.pt(100, 120)), 4326)),
    (v_c, 'pluvial', 'poz:ZT13-PP1', 'ZT13-PP1', 'pozo', 'VISIBLE', 1.2, '[{"r": "Elemento", "v": "Pozo pluvial"}]', pg_temp.pt(40, 120));
  v_c := pg_temp.carga_ref('pm_presion_existente');
  insert into redes.pm_presion_hora (carga_id, llave, escenario, p_min, hora_min, p_max, hora_max, p_media, p_mediana, horas) values (v_c, 'ZT13-N1', 'existente', -3, 17, 12, 0, 8, 9, (select array_agg(9 + g * 0.1) from generate_series(0, 24) g));
  v_c := pg_temp.carga_ref('pm_presion_futura');
  insert into redes.pm_presion_hora (carga_id, llave, escenario, p_min, hora_min, p_max, hora_max, p_media, p_mediana, horas) values (v_c, 'ZT13-N1', 'futura', 30, 9, 40, 1, 35, 36, (select array_agg(36 - g * 0.1) from generate_series(0, 24) g));
  perform pg_temp.reg('06.03 los niveles de presión siguen los umbrales de Parámetros: <10 roja, <15 naranja, 15 a 50 normal, >50 naranja, >60 roja; sin dato',
     redes.f_pm_nivel_presion(9) = 'baja_roja' and redes.f_pm_nivel_presion(12) = 'baja_naranja' and redes.f_pm_nivel_presion(15) = 'normal' and redes.f_pm_nivel_presion(50) = 'normal'
     and redes.f_pm_nivel_presion(55) = 'alta_naranja' and redes.f_pm_nivel_presion(61) = 'alta_roja' and redes.f_pm_nivel_presion(null) = 'sin_dato' and redes.f_pm_nivel_presion(-7) = 'baja_roja');
  v_t := pg_temp.ref(sd, 'presion_modelo', 17, 40, 50);
  perform pg_temp.reg('06.04 la tesela de «presión de modelo» trae el nodo con su nivel (9 m.c.a. → roja) y no los nodos sin presión de la red existente',
     pg_temp.trae(v_t, 'ZT13V1') and pg_temp.trae(v_t, 'baja_roja') and not pg_temp.trae(v_t, 'ZT13S-1'));
  perform public.geoportal_redes_parametro_fijar(a, 'presion_baja_roja_mca', 8, 'ZT13 prueba del umbral de presión');
  perform pg_temp.reg('06.05 al cambiar un umbral en Parámetros, la misma tesela cambia de color sin recalcular nada (el único nodo rojo, de 9 m.c.a., pasa a naranja)',
     redes.f_pm_nivel_presion(9) = 'baja_naranja' and pg_temp.trae(pg_temp.ref(sd, 'presion_modelo', 17, 40, 50), 'baja_naranja') and not pg_temp.trae(pg_temp.ref(sd, 'presion_modelo', 17, 40, 50), 'baja_roja'));
  perform pg_temp.reg('06.06 las demás capas de referencia salen en su tesela y solo en la suya: válvulas propuestas, campaña (también de lejos) y pluvial (línea siempre; pozo, de cerca)',
     pg_temp.trae(pg_temp.ref(sd, 'plan_valvulas', 17, 60, 60), 'ZT13S-PROP') and not pg_temp.trae(pg_temp.ref(sd, 'pluvial', 17, 60, 60), 'ZT13S-PROP')
     and pg_temp.trae(pg_temp.ref(sd, 'campana_2014', 13, 70, 70), 'ZT13 Punto 1') and pg_temp.trae(pg_temp.ref(sd, 'pluvial', 17, 40, 120), 'ZT13-PL1') and pg_temp.trae(pg_temp.ref(sd, 'pluvial', 17, 40, 120), 'ZT13-PP1')
     and not pg_temp.trae(pg_temp.ref(sd, 'pluvial', 13, 40, 120), 'ZT13-PP1') and pg_temp.trae(pg_temp.ref(sd, 'pluvial', 13, 40, 120), 'ZT13-PL1'));
  perform pg_temp.reg('06.07 más lejos que el zoom mínimo del geovisor, la tesela de referencia sale vacía', pg_temp.ref(sd, 'pluvial', 11, 40, 120) = '');
  perform pg_temp.reg('06.08 el operador en solo lectura recibe la tesela de la red pluvial', pg_temp.trae(pg_temp.ref(op, 'pluvial', 17, 40, 120), 'ZT13-PL1'));
  perform pg_temp.err('06.09 … pero no las de supervisión', format('select public.geoportal_redes_geovisor_mvt_ref(%L, %L, 17, 1, 1)', op, 'presion_modelo'), '42501');
  perform pg_temp.err('06.10 una capa que no es de referencia (o no existe) no se sirve por aquí', format('select public.geoportal_redes_geovisor_mvt_ref(%L, %L, 17, 1, 1)', sd, 'contratos'), 'P0002');
  perform pg_temp.err('06.11 quien no tiene el geovisor no recibe nada', format('select public.geoportal_redes_geovisor_mvt_ref(%L, %L, 17, 1, 1)', na, 'pluvial'), '42501');
  perform pg_temp.err('06.12 una tesela fuera de rango se rechaza', format('select public.geoportal_redes_geovisor_mvt_ref(%L, %L, 3, 99, 1)', sd, 'pluvial'), null, 'Tesela fuera de rango');
  perform pg_temp.reg('06.13 las válvulas propuestas no son activos: no salen en la tesela de la red ni existe un activo con ese nombre',
     not pg_temp.trae(public.geoportal_redes_geovisor_mvt(sd, 17, pg_temp.tx(17, 60), pg_temp.ty(17, 60)), 'ZT13S-PROP') and not exists (select 1 from redes.activo_vigente_mat where codigo_anterior = 'ZT13S-PROP' or nombre = 'ZT13S-PROP'));
  v_r := public.geoportal_redes_referencia(sd, 'campana_2014', 'ZT13-CAMP1');
  perform pg_temp.reg('06.14 tarjeta de la campaña: «Presión MEDIDA», su nivel, las filas rotuladas con el sector y la serie de 15 min completa (40 lecturas en orden)',
     v_r ->> 'advertencia' like 'Presión MEDIDA en campo en 2014%' and v_r ->> 'nivel' = 'baja_roja' and pg_temp.filas(v_r -> 'filas') like 'Dirección=ZT13 Cra de prueba | Sector según el Plan=91 · subsector 91.1'
     and jsonb_array_length(v_r -> 'series' -> 0 -> 'puntos') = 40 and v_r -> 'series' -> 0 -> 'puntos' -> 0 ->> 0 = '2014-01-31T14:15' and (v_r -> 'series' -> 0 -> 'puntos' -> 39 ->> 1)::numeric = 6.0, left(v_r::text, 400));
  v_r := public.geoportal_redes_referencia(sd, 'campana_2014', 'ZT13-CAMP6');
  perform pg_temp.reg('06.15 el punto de la campaña sin coordenada no sale en el mapa, pero su tarjeta existe (sin sector)', not pg_temp.trae(pg_temp.ref(sd, 'campana_2014', 13, 70, 70), 'ZT13 Punto 6')
     and v_r ->> 'titulo' = 'ZT13 Punto 6 · sin coordenada' and pg_temp.filas(v_r -> 'filas') = '');
  v_r := public.geoportal_redes_referencia(sd, 'presion_modelo', 'ZT13-N1');
  perform pg_temp.reg('06.16 tarjeta de un nodo del modelo: «Presión de MODELO, no medida», el perfil horario de los dos escenarios (25 horas cada uno) y el activo del nodo, para abrir su ficha',
     v_r ->> 'advertencia' like 'Presión de MODELO, no medida.%negativa%' and jsonb_array_length(v_r -> 'series') = 2 and jsonb_array_length(v_r -> 'series' -> 0 -> 'valores') = 25
     and v_r -> 'series' -> 0 ->> 'escenario' = 'existente' and v_r ->> 'activo' = v_val and pg_temp.filas(v_r -> 'filas') like 'Red existente: mediana del día=9%', left(v_r::text, 400));
  perform pg_temp.reg('06.17 tarjeta de una válvula propuesta: «no está instalada, no es un activo y no entra en ninguna simulación»',
     public.geoportal_redes_referencia(sd, 'plan_valvulas', 'ZT13-PV1') ->> 'advertencia' = 'Válvula PROPUESTA por el Plan: no está instalada, no es un activo y no entra en ninguna simulación.');
  perform pg_temp.err('06.18 un elemento que no está en la capa: no encontrado', format('select public.geoportal_redes_referencia(%L, %L, %L)', sd, 'pluvial', 'ZT13-NO'), 'P0002');
  perform pg_temp.err('06.19 el operador no abre tarjetas de las capas de supervisión', format('select public.geoportal_redes_referencia(%L, %L, %L)', op, 'campana_2014', 'ZT13-CAMP1'), '42501');
  perform pg_temp.reg('06.20 … y sí la de la red pluvial', public.geoportal_redes_referencia(op, 'pluvial', 'con:ZT13-PL1') ->> 'advertencia' = 'Capa de referencia: no es un activo.');

  -- ===================== 07. Sector del daño, de la intervención y del contrato =====================
  v_p := public.geoportal_redes_preparar_dano(op, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_dano := public.geoportal_redes_crear_dano(op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', v_red,
         'lat', pg_temp.lat(50), 'lon', pg_temp.lon(250), 'ubicacion_origen', 'mapa', 't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio',
         'causa_clase', 'desconocida', 'sector', 9, 'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))));
  v_x := (select d from jsonb_array_elements(public.geoportal_redes_danos(sd, 'todos', 300) -> 'danos') d where d ->> 'codigo' = v_dano ->> 'codigo');
  perform pg_temp.reg('07.01 el daño conserva el sector escrito a mano (9) y, al lado, trae el «sector según Plan» calculado por su ubicación (91, 91.2)',
     v_x ->> 'sector' = '9' and v_x -> 'sector_plan' ->> 'sector' = '91' and v_x -> 'sector_plan' ->> 'subsector' = '91.2'
     and (select sector_num from redes.danos where codigo = v_dano ->> 'codigo') = 9, v_x::text);
  perform pg_temp.reg('07.02 la lista de intervenciones lleva «sector_plan», calculado igual (por la ubicación), y sigue respondiendo',
     (select prosrc from pg_proc where proname = 'geoportal_redes_intervenciones' and pronamespace = 'public'::regnamespace) like '%''sector_plan'', (select jsonb_build_object(''sector'', s.sector, ''subsector'', s.subsector) from redes.f_sector_de(x.geom) s%'
     and jsonb_typeof(public.geoportal_redes_intervenciones(sd, 'recientes', 5) -> 'intervenciones') = 'array');
  insert into public.cartera_suscripcion (contrato, estado, nombre, direccion, barrio, categoria, periodo_carga) values (C1, 'ACTIVO', 'NOMBRE DE PRUEBA TRECE', 'CRA ZT13 1', 'ZT13 BARRIO', '1 Residencial', '29991231');
  insert into public.catastro_valledupar (cod_usuario, direccion, barrio, geom) values (C1, 'CRA ZT13 1', 'ZT13 BARRIO', pg_temp.pt(60, 55));
  insert into redes.contrato_tramo (contrato, activo_id, distancia_m, metodo) select C1, id, 5, 'cercania' from redes.activos where codigo = v_red;
  v_r := public.geoportal_redes_contrato_tarjeta(sd, C1);
  perform pg_temp.reg('07.03 la tarjeta del contrato toma el sector de su tramo de acueducto (91, 91.1) y conserva todo lo demás (tramo, suscriptor y corte)',
     v_r -> 'sector_plan' ->> 'sector' = '91' and v_r -> 'sector_plan' ->> 'subsector' = '91.1' and v_r ->> 'tramo' = v_red and v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA TRECE'
     and v_r ? 'datos_personales' and v_r ->> 'corte' = '29991231', v_r::text);

  -- ===================== 08. Tiempos con los datos de esta base (en producción: el volumen real). Topes: 8 s (authenticated) y 30 s (service_role) =====================
  v_t0 := clock_timestamp(); perform public.geoportal_redes_nodos_por_clasificar(a, null, null, 50); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_por_verificar(sd, null, null, 50); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_activo(sd, v_val); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_geovisor_mvt(sd, 14, pg_temp.tx(14, 100), pg_temp.ty(14, 100)); perform pg_temp.ref(sd, 'presion_modelo', 14, 40, 50);
  v_ms4 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_danos(sd, 'todos', 200); v_ms5 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS: nodos por clasificar (%s en la base): %s ms · bandeja por verificar: %s ms · ficha con referencia y sector: %s ms · tesela de la red más tesela de presión (z14): %s ms · lista de daños con sector: %s ms',
                   (select count(*) from redes.v_nodo_vigente where clase_nodo = 'por_clasificar'), v_ms1, v_ms2, v_ms3, v_ms4, v_ms5);
  perform pg_temp.reg('08.01 las lecturas del 9a responden en menos de 8 s (el tope más corto de las peticiones) con los datos de esta base', greatest(v_ms1, v_ms2, v_ms3, v_ms4, v_ms5) < 8000, v_info);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 9a (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
