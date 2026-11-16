-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes15.*), sus predios de catastro (contratos 995150xx, en un rincón de Valledupar),
-- su polígono de sector (número 95) y sus reportes sintéticos (números 99515xxxx y 9952xxxxx). Ningún dato real de la línea 116.
-- Mide la carga completa con el volumen real (22.978 reportes sintéticos, contratos tomados del catastro de la base donde corre) y la capa del geovisor:
-- FALLA si un lote pasa de 8 s, si el resumen o la publicación pasan de 30 s, o si la capa pasa de 8 s.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 5d … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4300 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.2900 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.caja(x0 numeric, y0 numeric, x1 numeric, y1 numeric) returns geometry language sql as $$
  select ST_SetSRID(ST_MakeEnvelope(pg_temp.lon(x0), pg_temp.lat(y0), pg_temp.lon(x1), pg_temp.lat(y1)), 4326) $$;
-- distancia en metros entre un punto y el de la cuadrícula de prueba
create function pg_temp.dist(g geometry, x numeric, y numeric) returns numeric language sql as $$ select round(ST_Distance(g::geography, pg_temp.pt(x, y)::geography)::numeric, 1) $$;
create function pg_temp.activo(p_prefijo text, p_geom geometry, p_capa text, p_llave text, p_clase text default null, p_attr jsonb default '{}'::jsonb, p_nombre text default null)
returns text language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes15.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, estado_codigo, atributos, codigo_anterior, capa_codigo, llave_capa, huella, autor)
  values (v_id, 1, p_geom, coalesce(p_nombre, 'ZT15 ' || p_prefijo), p_clase, null, null, null, 'en_operacion', p_attr, p_llave, p_capa, p_llave, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT15 activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_cod;
end $$;
create function pg_temp.archivo(p_ruta text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg')) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
create function pg_temp.dano(p_op text, p_datos jsonb) returns text language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_dano(p_op, 1);
begin
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  return public.geoportal_redes_crear_dano(p_op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'ubicacion_origen', 'mapa',
           't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
           'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))) || p_datos) ->> 'codigo';
end $$;
-- hoy en Bogotá a las HH:MM (texto como lo trae el archivo)
create function pg_temp.hoy(p_min integer) returns text language sql as $$
  select to_char(((clock_timestamp() at time zone 'America/Bogota')::date)::timestamp + make_interval(mins => p_min), 'YYYY-MM-DD HH24:MI:SS') $$;
-- una fila del archivo, con NOMBRE (que no se debe guardar nunca)
create function pg_temp.fila(p_orden integer, p_rep bigint, p_estado text, p_fecha text, p_contrato text, p_dir text, p_barrio text, p_causal text, p_servicio text)
returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', null, 'atributos', jsonb_build_object('REPORTE', p_rep, 'ESTADO', p_estado, 'FECHA_REGISTRO', p_fecha, 'CONTRATO', p_contrato,
           'NOMBRE', 'ZT15 NOMBRE QUE NO SE GUARDA', 'DIRECCION', p_dir, 'BARRIO', p_barrio, 'COMUNA', 'COMUNA 5', 'DESC_CAUSAL', p_causal, 'SERVICIO', p_servicio)) $$;
-- sube un archivo por el motor (como la pantalla: iniciar, lotes de 200) y devuelve la carga
create function pg_temp.subir(p_sd text, p_filas jsonb, p_sha text) returns bigint language plpgsql as $$
declare v_c bigint; k integer := 0; n integer := jsonb_array_length(p_filas);
begin
  v_c := (public.geoportal_redes_cargue_iniciar(p_sd, 'linea_116', p_sha, 'xlsx', 4326, 'reporte', n, 'ZT15 archivo de prueba') ->> 'carga_id')::bigint;
  while k < n loop
    perform public.geoportal_redes_carga_lote(p_sd, v_c, (select jsonb_agg(e order by o) from jsonb_array_elements(p_filas) with ordinality x(e, o) where o > k and o <= k + 200));
    k := k + 200;
  end loop;
  return v_c;
end $$;
-- las propiedades de los puntos de la capa, por su primer reporte
create function pg_temp.punto(p_capa jsonb, p_rep bigint) returns jsonb language sql as $$
  select f -> 'properties' from jsonb_array_elements(p_capa -> 'features') f where (f -> 'properties' -> 'reportes') @> to_jsonb(array[p_rep]) limit 1 $$;

do $prueba$
declare
  a text := 'prueba.redes15.adm@emdupar.gov.co'; sd text := 'prueba.redes15.dist@emdupar.gov.co'; op text := 'prueba.redes15.op@emdupar.gov.co';
  C1 text := '99515001'; C2 text := '99515002'; C3 text := '99515003';
  v_base bigint := 995150000; v_r jsonb; v_x jsonb; v_c1 bigint; v_c2 bigint; v_c3 bigint; v_c4 bigint; v_g jsonb; v_dano text; v_sub text;
  v_cods text[]; v_nc integer; v_n integer := 22978; v_lote jsonb; v_cv bigint; k integer;
  v_t0 timestamptz; v_ms numeric; v_ms_lote numeric := 0; v_ms_res numeric; v_ms_pub numeric; v_ms_capa numeric; v_ms_capa_hoy numeric; v_ms_ini numeric;
  v_info text := ''; v_total integer; v_bien integer; v_fallas text; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT15 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT15 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT15 Operador de redes', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);

  -- ===================== 01. Esquema, permisos y catálogo =====================
  perform pg_temp.reg('01.01 las 9 funciones internas nuevas no las ejecuta la API; la RPC nueva, solo service_role (security definer)',
     not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                   and p.proname in ('f_dir_norm', 'f_dir_base', 'f_barrio_norm', 'f_l116_atributos', 'f_l116_fecha', 'f_l116_candidatos', 'f_resumen_l116', 'f_publicar_l116', 'f_revertir_l116')
                   and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')))
     and (select count(*) from pg_proc p where p.pronamespace = 'redes'::regnamespace
            and p.proname in ('f_dir_norm', 'f_dir_base', 'f_barrio_norm', 'f_l116_atributos', 'f_l116_fecha', 'f_l116_candidatos', 'f_resumen_l116', 'f_publicar_l116', 'f_revertir_l116')) = 9
     and exists (select 1 from pg_proc p where p.oid = 'public.geoportal_redes_l116_vincular_dano(text,bigint,text,text,text)'::regprocedure and p.prosecdef
                   and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')));
  perform pg_temp.reg('01.02 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
     not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion || ' → ' || sentencia, ' | ') from redes.f_funciones_sin_where()));
  perform pg_temp.reg('01.03 las 4 tablas de la 116: ningún permiso para la API; reportes, eventos y daños con el disparador de solo agregar',
     not has_table_privilege('service_role', 'redes.l116_reportes', 'select') and not has_table_privilege('anon', 'redes.l116_vigente', 'select')
     and not has_table_privilege('authenticated', 'redes.l116_eventos', 'select') and not has_table_privilege('service_role', 'redes.l116_danos', 'insert')
     and (select count(*) from pg_trigger t where t.tgrelid in ('redes.l116_reportes'::regclass, 'redes.l116_eventos'::regclass, 'redes.l116_danos'::regclass) and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 6);
  perform pg_temp.reg('01.04 ninguna tabla de la 116 tiene columna de nombre ni de teléfono',
     not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name like 'l116\_%' and column_name ~ 'nombre|telefono|celular'));
  perform pg_temp.reg('01.05 la capa «linea_116» del Cargue (CSV o Excel, llave «reporte», la carga el supervisor) y «pqr_116» en el geovisor (por fecha, solo supervisores)',
     exists (select 1 from redes.capas where codigo = 'linea_116' and fuente = 'carga' and activa and carga_supervisor and columna_llave = 'reporte' and formatos = '{csv,xlsx}')
     and exists (select 1 from redes.geovisor_capas where codigo = 'pqr_116' and fuente = 'geojson' and estado = 'activa' and por_fecha and solo_completo));
  perform pg_temp.reg('01.06 punto 8: «Reportar anomalía» y «Revisiones generales» están en los formularios de distribución',
     (select count(*) from redes.formularios_distribucion where clave in ('anomalia_compartida', 'revision_compartida') and activo) = 2);

  -- ===================== 02. Dirección, barrio, fecha y columnas =====================
  perform pg_temp.reg('02.01 la dirección se normaliza igual escrita de varias formas (Calle/CLL/CL, #, N°, No., guiones, ceros)',
     redes.f_dir_norm('Calle 12 # 5-30') = 'CL 12 5 30' and redes.f_dir_norm('CLL 12 N° 5 - 30') = 'CL 12 5 30' and redes.f_dir_norm('cl. 12 no. 05-30') = 'CL 12 5 30'
     and redes.f_dir_norm('Carrera 9 A No. 18-05') = 'CR 9A 18 5' and redes.f_dir_norm('KRA 9a 18 05') = 'CR 9A 18 5' and redes.f_dir_norm('Diagonal 21 Transversal 4') = 'DG 21 TV 4',
     redes.f_dir_norm('Calle 12 # 5-30') || ' / ' || redes.f_dir_norm('CLL 12 N° 5 - 30') || ' / ' || redes.f_dir_norm('Carrera 9 A No. 18-05') || ' / ' || redes.f_dir_norm('KRA 9a 18 05'));
  perform pg_temp.reg('02.02 «N» suelta (norte) se conserva; sin apartamento, local ni torre para el segundo intento; vacío → nulo',
     redes.f_dir_norm('CL 9 N CR 9 - 9') = 'CL 9 N CR 9 9' and redes.f_dir_base(redes.f_dir_norm('Cra 9A # 18-05 Apto 201')) = 'CR 9A 18 5'
     and redes.f_dir_base(redes.f_dir_norm('MZ 4 CASA 7 TORRE 2')) = 'MZ 4 CS 7' and redes.f_dir_norm('  - ') is null);
  perform pg_temp.reg('02.03 el barrio se normaliza sin tildes, sin signos y sin «Barrio»/«Urbanización» delante',
     redes.f_barrio_norm('Barrio Los Cortijos') = 'LOS CORTIJOS' and redes.f_barrio_norm('URB. los cortijos') = 'LOS CORTIJOS' and redes.f_barrio_norm('Villa Castro (II etapa)') = 'VILLA CASTRO II ETAPA');
  perform pg_temp.reg('02.04 la fecha: AAAA-MM-DD, DD/MM/AAAA y el número de Excel, en hora de Bogotá; lo que no se entiende o es futuro, nulo',
     redes.f_l116_fecha('2026-01-01 11:21:28') = timestamptz '2026-01-01 11:21:28-05' and redes.f_l116_fecha('01/02/2026 08:30') = timestamptz '2026-02-01 08:30-05'
     and redes.f_l116_fecha('46023.5') = timestamptz '2026-01-01 12:00-05' and redes.f_l116_fecha('2026-01-01T07:05') = timestamptz '2026-01-01 07:05-05'
     and redes.f_l116_fecha('ayer') is null and redes.f_l116_fecha('2099-01-01') is null and redes.f_l116_fecha('31/02/2026') is null and redes.f_l116_fecha(null) is null);
  perform pg_temp.reg('02.05 de cada fila solo pasan las 9 columnas que se cargan (con nombre en minúscula): NOMBRE no pasa',
     (select array_agg(x.c order by x.c) from jsonb_object_keys(redes.f_l116_atributos((pg_temp.fila(1, 1, 'Atendido', '2026-01-01', '1', 'x', 'y', 'z', 'w') -> 'atributos')
                                                                                   || '{"Teléfono": "300", "nombre": "x"}')) x(c))
       = array['barrio', 'comuna', 'contrato', 'desc_causal', 'direccion', 'estado', 'fecha_registro', 'reporte', 'servicio']);

  -- ===================== 03. Los predios y el sector de prueba =====================
  insert into public.catastro_valledupar (cod_usuario, direccion, barrio, geom)
  values (C1, 'CL ZT15 1 # 2-3', 'ZT15 BARRIO UNO', pg_temp.pt(0, 0)),
         (C2, 'CR ZT15 5 A No. 7-09', 'ZT15 BARRIO UNO', pg_temp.pt(30, 0)),
         (C3, 'Carrera ZT15 5A 7 09', 'ZT15 BARRIO UNO', pg_temp.pt(34, 4)),
         ('99515004', 'MZ ZT15 1 CS 1', 'ZT15 BARRIO UNO', pg_temp.pt(0, 100)),
         ('99515005', 'MZ ZT15 1 CS 1', 'ZT15 BARRIO DOS', pg_temp.pt(900, 900)),
         ('99515006', 'CL ZT15 9 9', 'Barrio ZT15 Barrio Dos', pg_temp.pt(920, 900));
  v_sub := pg_temp.activo('SEC', pg_temp.caja(-50, -50, 200, 200), 'sectores', 'ZT15-SUB-95.1', 'subsector', '{"modelo": {"sector": 95, "subsector": "95.1"}}', 'ZT15 Subsector 95.1');

  -- ===================== 04. Primera carga por el motor (como la pantalla) =====================
  v_r := public.geoportal_redes_cargue_capas(sd);
  perform pg_temp.reg('04.01 el supervisor de distribución ve la capa en el Cargue, con su lector y sin reportes todavía',
     exists (select 1 from jsonb_array_elements(v_r -> 'capas') c where c ->> 'codigo' = 'linea_116' and c ->> 'lector' = 'linea_116' and (c ->> 'puede_cargar')::boolean and (c ->> 'vigentes')::integer = 0));
  perform pg_temp.err('04.02 el operador no entra al Cargue', format('select public.geoportal_redes_cargue_capas(%L)', op), '42501');
  perform pg_temp.err('04.03 la llave de la capa es «reporte» (no otra columna)',
     format('select public.geoportal_redes_cargue_iniciar(%L, %L, %L, %L, 4326, %L, 3)', sd, 'linea_116', md5('zt15x') || md5('zt15y'), 'csv', 'CONTRATO'), null, 'reporte');
  v_c1 := pg_temp.subir(sd, jsonb_build_array(
      pg_temp.fila(1, v_base + 1, 'Registrado', pg_temp.hoy(1), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto'),
      pg_temp.fila(2, v_base + 2, 'Registrado', pg_temp.hoy(2), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto'),
      pg_temp.fila(3, v_base + 3, 'Registrado', pg_temp.hoy(3), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(4, v_base + 4, 'Registrado', pg_temp.hoy(4), '99515099', 'Carrera ZT15 5 A # 7 - 09', 'ZT15 BARRIO UNO', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(5, v_base + 5, 'Registrado', pg_temp.hoy(5), '99515098', 'MZ ZT15 1 CS 1 AP 2', 'Barrio ZT15 Barrio Dos', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(6, v_base + 6, 'Registrado', pg_temp.hoy(6), '99515097', 'ZT15 dirección sin catastro', 'ZT15 BARRIO DOS', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(7, v_base + 7, 'Registrado', pg_temp.hoy(7), '99515096', 'ZT15 otra sin catastro', 'ZT15 BARRIO QUE NO EXISTE', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(8, v_base + 8, 'Atendido', pg_temp.hoy(8), C2, 'x', 'x', 'ZT15 REBOSE DE ALCANTARILLA', 'Alcantarillado'),
      pg_temp.fila(9, v_base + 9, 'Atendido', pg_temp.hoy(9), C2, 'x', 'x', 'ZT15 HUECO EN LA VÍA', 'Incidentes Externos'),
      pg_temp.fila(10, v_base + 11, 'Registrado', pg_temp.hoy(10), '99999999', 'Calle ZT15 1 # 2 - 3', 'ZT15 BARRIO UNO', 'ZT15 SIN AGUA', 'Acueducto')), md5('zt15-1') || md5('zt15-1b'));
  perform pg_temp.reg('04.04 NOMBRE no llega a la base: la carga guarda solo las 9 columnas (ni la palabra en ninguna fila)',
     not exists (select 1 from redes.carga_filas where carga_id = v_c1 and (atributos ? 'nombre' or atributos ? 'NOMBRE' or atributos::text like '%NOMBRE QUE NO SE GUARDA%'))
     and (select count(*) from redes.carga_filas where carga_id = v_c1 and llave is not null) = 10);
  v_r := public.geoportal_redes_carga_resumen(sd, v_c1);
  perform pg_temp.reg('04.05 el resumen: 10 nuevos, lista para publicar; ubicados 5 por contrato, 3 por dirección, 1 por barrio y 1 sin ubicar',
     (v_r ->> 'lista_para_publicar')::boolean and (v_r -> 'frente_a_vigente' ->> 'nuevo')::integer = 10
     and v_r -> 'ubicacion' = '{"contrato": 5, "direccion": 3, "barrio": 1, "sin_ubicar": 1}'::jsonb, (v_r - 'tabla')::text);
  perform pg_temp.reg('04.06 el resumen dice el sector de los ubicados dentro del polígono y avisa los sin ubicar; no trae direcciones, barrios ni nombres',
     (v_r ->> 'con_sector')::integer = 7 and v_r -> 'sin_ubicar_muestra' = to_jsonb(array[v_base + 7]) and v_r::text not like '%ZT15 BARRIO%' and v_r::text not like '%NOMBRE%'
     and v_r::text not like '%dirección sin catastro%', (v_r - 'tabla')::text);
  v_x := public.geoportal_redes_carga_publicar(sd, v_c1, 'ZT15 primera carga de la línea 116 de prueba');
  perform pg_temp.reg('04.07 publicar: 10 nuevos (versión 1); 10 reportes, 10 altas con método y 10 vigentes',
     (v_x ->> 'nuevos')::integer = 10 and (v_x ->> 'version_capa')::integer = 1
     and (select count(*) from redes.l116_reportes where carga_id = v_c1) = 10 and (select count(*) from redes.l116_eventos where carga_id = v_c1 and tipo = 'alta' and metodo is not null) = 10
     and (select count(*) from redes.l116_vigente v join redes.l116_reportes r on r.id = v.reporte_id where r.carga_id = v_c1) = 10, v_x::text);
  perform pg_temp.reg('04.08 por contrato: el punto del predio (y el sector 95, subsector 95.1); el comodín 99999999 no ubica por contrato, sí por su dirección',
     (select pg_temp.dist(geom, 0, 0) < 1 and metodo = 'contrato' and sector = 95 and subsector = '95.1' from redes.l116_vigente where reporte = v_base + 1)
     and (select pg_temp.dist(geom, 30, 0) < 1 and metodo = 'contrato' from redes.l116_vigente where reporte = v_base + 8)
     and (select pg_temp.dist(geom, 0, 0) < 1 and metodo = 'direccion' from redes.l116_vigente where reporte = v_base + 11));
  perform pg_temp.reg('04.09 por dirección: el centro de los predios con esa dirección (a 100 m o menos); si está en dos sitios, la del mismo barrio',
     (select pg_temp.dist(geom, 32, 2) < 2 and metodo = 'direccion' from redes.l116_vigente where reporte = v_base + 4)
     and (select pg_temp.dist(geom, 900, 900) < 1 and metodo = 'direccion' and sector is null from redes.l116_vigente where reporte = v_base + 5),
     (select string_agg(reporte || ' ' || metodo || ' ' || coalesce(ST_AsText(geom), '-'), ' | ') from redes.l116_vigente where reporte in (v_base + 4, v_base + 5)));
  perform pg_temp.reg('04.10 por barrio: el centro de sus predios (aproximada); sin contrato, dirección ni barrio en el catastro: sin ubicar (sin punto)',
     (select pg_temp.dist(geom, 910, 900) < 1 and metodo = 'barrio' from redes.l116_vigente where reporte = v_base + 6)
     and (select geom is null and metodo = 'sin_ubicar' from redes.l116_vigente where reporte = v_base + 7));

  -- ===================== 05. La capa del geovisor =====================
  v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', null, null);
  perform pg_temp.reg('05.01 hoy: 8 puntos (los dos reportes del mismo contrato, causal y día van juntos) y 1 sin ubicar',
     jsonb_array_length(v_g -> 'features') = 8 and (v_g ->> 'sin_ubicar')::integer = 1 and (pg_temp.punto(v_g, v_base + 1) ->> 'n')::integer = 2
     and pg_temp.punto(v_g, v_base + 1) -> 'reportes' = to_jsonb(array[v_base + 1, v_base + 2]) and (pg_temp.punto(v_g, v_base + 3) ->> 'n')::integer = 1,
     jsonb_array_length(v_g -> 'features') || ' puntos · ' || coalesce(pg_temp.punto(v_g, v_base + 1)::text, '-'));
  perform pg_temp.reg('05.02 color por servicio (acueducto, alcantarillado, otros) y estado (registrado o atendido)',
     pg_temp.punto(v_g, v_base + 1) ->> 'grupo_servicio' = 'acueducto' and pg_temp.punto(v_g, v_base + 1) ->> 'estado' = 'registrado'
     and pg_temp.punto(v_g, v_base + 8) ->> 'grupo_servicio' = 'alcantarillado' and pg_temp.punto(v_g, v_base + 8) ->> 'estado' = 'atendido'
     and pg_temp.punto(v_g, v_base + 9) ->> 'grupo_servicio' = 'otros' and pg_temp.punto(v_g, v_base + 4) ->> 'metodo' = 'direccion' and pg_temp.punto(v_g, v_base + 6) ->> 'metodo' = 'barrio');
  perform pg_temp.reg('05.03 la capa no trae nombre, dirección ni barrio (solo las propiedades previstas)',
     not exists (select 1 from jsonb_array_elements(v_g -> 'features') f, jsonb_object_keys(f -> 'properties') kk
                  where kk not in ('codigo', 'n', 'reportes', 'servicio', 'grupo_servicio', 'causal', 'estado', 'registrados', 'contrato', 'dia', 'cuando', 'ultimo', 'metodo', 'sector', 'subsector', 'danos'))
     and v_g::text not like '%BARRIO%' and v_g::text not like '%NOMBRE%' and v_g::text not like '%CL ZT15%');
  perform pg_temp.err('05.04 el operador no ve la capa (es de supervisores)', format('select public.geoportal_redes_geovisor_capa(%L, %L, null, null)', op, 'pqr_116'), '42501');
  v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', v_hoy - 3, v_hoy - 1);
  perform pg_temp.reg('05.05 por fecha: en los tres días anteriores no sale ninguno de hoy', not exists (select 1 from jsonb_array_elements(v_g -> 'features') f
                                                                                                        where (f -> 'properties' ->> 'codigo')::bigint between v_base and v_base + 99));

  -- ===================== 06. Cargas siguientes: cambio de estado, iguales, errores =====================
  perform pg_temp.err('06.01 el mismo archivo no se publica dos veces', format('select public.geoportal_redes_cargue_iniciar(%L, %L, %L, %L, 4326, %L, 10)', sd, 'linea_116', md5('zt15-1') || md5('zt15-1b'), 'xlsx', 'reporte'),
     null, 'ya se publicó');
  v_c2 := pg_temp.subir(sd, jsonb_build_array(
      pg_temp.fila(1, v_base + 1, 'Atendido', pg_temp.hoy(1), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto'),
      pg_temp.fila(2, v_base + 2, 'Registrado', pg_temp.hoy(2), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto'),
      pg_temp.fila(3, v_base + 3, 'Registrado', pg_temp.hoy(3), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 OTRA CAUSAL ESCRITA', 'Acueducto'),
      pg_temp.fila(4, v_base + 12, 'Registrado', pg_temp.hoy(12), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto')), md5('zt15-2') || md5('zt15-2b'));
  v_r := public.geoportal_redes_carga_resumen(sd, v_c2);
  perform pg_temp.reg('06.02 la segunda carga reconoce los reportes por su número: 1 nuevo, 1 con cambio de estado y 2 iguales (uno con otra causal: aviso, se conserva la primera)',
     (v_r ->> 'lista_para_publicar')::boolean and (v_r -> 'frente_a_vigente' ->> 'nuevo')::integer = 1 and (v_r -> 'frente_a_vigente' ->> 'estado')::integer = 1
     and (v_r -> 'frente_a_vigente' ->> 'igual')::integer = 2 and exists (select 1 from jsonb_array_elements_text(v_r -> 'avisos') x where x like '1 reportes ya cargados traen otra%'),
     (v_r - 'tabla')::text);
  v_x := public.geoportal_redes_carga_publicar(sd, v_c2, 'ZT15 segunda carga de la línea 116 de prueba');
  perform pg_temp.reg('06.03 publicar: el cambio de estado es un evento con fecha (antes registrado, ahora atendido); la causal del primero no cambia',
     (v_x ->> 'nuevos')::integer = 1 and (v_x ->> 'cambios_estado')::integer = 1 and (v_x ->> 'iguales')::integer = 2 and (v_x ->> 'version_capa')::integer = 2
     and (select array_agg(e.tipo || ':' || e.estado || ':' || coalesce(e.estado_antes, '-') order by e.id) from redes.l116_eventos e join redes.l116_reportes r on r.id = e.reporte_id where r.reporte = v_base + 1)
         = array['alta:registrado:-', 'estado:atendido:registrado']
     and (select estado from redes.l116_vigente where reporte = v_base + 1) = 'atendido' and (select causal from redes.l116_reportes where reporte = v_base + 3) = 'ZT15 SIN AGUA', v_x::text);
  v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', null, null);
  perform pg_temp.reg('06.04 en el mapa el grupo del contrato, causal y día tiene ahora 3 reportes (2 registrados: sigue «registrado»)',
     (pg_temp.punto(v_g, v_base + 1) ->> 'n')::integer = 3 and (pg_temp.punto(v_g, v_base + 1) ->> 'registrados')::integer = 2 and pg_temp.punto(v_g, v_base + 1) ->> 'estado' = 'registrado',
     coalesce(pg_temp.punto(v_g, v_base + 1)::text, '-'));
  v_c3 := pg_temp.subir(sd, jsonb_build_array(
      pg_temp.fila(1, v_base + 20, 'Registrado', 'ayer', C1, 'x', 'x', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(2, v_base + 21, 'Cerrado', pg_temp.hoy(20), C1, 'x', 'x', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(3, v_base + 22, 'Registrado', pg_temp.hoy(21), C1, 'x', 'x', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(4, v_base + 22, 'Registrado', pg_temp.hoy(22), C1, 'x', 'x', 'ZT15 SIN AGUA', 'Acueducto'),
      pg_temp.fila(5, v_base + 23, 'Registrado', pg_temp.hoy(23), C1, 'x', 'x', null, 'Acueducto')), md5('zt15-3') || md5('zt15-3b'));
  v_r := public.geoportal_redes_carga_resumen(sd, v_c3);
  perform pg_temp.reg('06.05 con errores no se publica: fecha que no se entiende, estado desconocido, causal vacía y número repetido (dice la fila y el reporte)',
     not (v_r ->> 'lista_para_publicar')::boolean and (v_r -> 'frente_a_vigente' ->> 'error')::integer = 3
     and exists (select 1 from jsonb_array_elements_text(v_r -> 'bloqueos') b where b like '3 filas con error: fila 1 (reporte ' || (v_base + 20) || '): la fecha%' and b like '%fila 2 (reporte%el estado no es%'
                                                                                and b like '%falta la causal%')
     and exists (select 1 from jsonb_array_elements_text(v_r -> 'bloqueos') b where b = '1 números de reporte repetidos en el archivo: ' || (v_base + 22)), (v_r -> 'bloqueos')::text);
  perform pg_temp.err('06.06 … y la publicación se niega', format('select public.geoportal_redes_carga_publicar(%L, %s, %L)', sd, v_c3, 'ZT15 no debe publicarse'), null, 'no está lista');
  perform public.geoportal_redes_carga_anular(sd, v_c3, 'ZT15 se anula la carga con errores');

  -- ===================== 07. Volver atrás una carga (nada se borra) =====================
  v_x := public.geoportal_redes_carga_revertir(sd, 'linea_116', 'ZT15 se revierte la segunda carga de prueba');
  perform pg_temp.reg('07.01 revertir la segunda carga: su reporte nuevo se oculta y el cambio de estado vuelve con un evento nuevo (los eventos siguen)',
     (v_x ->> 'ocultados')::integer = 1 and (v_x ->> 'estados_devueltos')::integer = 1
     and (select oculto from redes.l116_vigente where reporte = v_base + 12) and (select estado from redes.l116_vigente where reporte = v_base + 1) = 'registrado'
     and (select count(*) from redes.l116_eventos e join redes.l116_reportes r on r.id = e.reporte_id where r.reporte in (v_base + 1, v_base + 12)) = 5
     and exists (select 1 from redes.l116_reportes where reporte = v_base + 12), v_x::text);
  v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', null, null);
  perform pg_temp.reg('07.02 en el mapa el grupo vuelve a 2 reportes', (pg_temp.punto(v_g, v_base + 1) ->> 'n')::integer = 2);
  v_c4 := pg_temp.subir(sd, jsonb_build_array(
      pg_temp.fila(1, v_base + 1, 'Atendido', pg_temp.hoy(1), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto'),
      pg_temp.fila(2, v_base + 12, 'Atendido', pg_temp.hoy(12), C1, 'CL ZT15 1 2 3', 'ZT15 BARRIO UNO', 'ZT15 FUGA EN ACOMETIDA', 'Acueducto')), md5('zt15-2') || md5('zt15-2b'));
  v_r := public.geoportal_redes_carga_resumen(sd, v_c4);
  v_x := public.geoportal_redes_carga_publicar(sd, v_c4, 'ZT15 se vuelve a cargar el archivo revertido');
  perform pg_temp.reg('07.03 el archivo revertido se puede volver a cargar: el reporte oculto vuelve (evento «mostrar») con su estado nuevo',
     (v_r -> 'frente_a_vigente' ->> 'mostrar')::integer = 1 and (v_r -> 'frente_a_vigente' ->> 'estado')::integer = 1
     and not (select oculto from redes.l116_vigente where reporte = v_base + 12) and (select estado from redes.l116_vigente where reporte = v_base + 12) = 'atendido'
     and exists (select 1 from redes.l116_eventos e join redes.l116_reportes r on r.id = e.reporte_id where r.reporte = v_base + 12 and e.tipo = 'mostrar'), (v_r - 'tabla')::text);
  perform pg_temp.err('07.04 solo agregar: no se cambia un reporte', format('update redes.l116_reportes set causal = %L where reporte = %s', 'x', v_base + 1), '42501');
  perform pg_temp.err('07.05 solo agregar: no se borra un evento', format('delete from redes.l116_eventos where reporte_id = (select id from redes.l116_reportes where reporte = %s)', v_base + 1), '42501');
  perform pg_temp.reg('07.06 el Cargue cuenta los reportes que se ven (12 de prueba; el oculto vuelve)',
     (select (c ->> 'vigentes')::integer from jsonb_array_elements(public.geoportal_redes_cargue_capas(sd) -> 'capas') c where c ->> 'codigo' = 'linea_116')
       = (select count(*) from redes.l116_vigente where not oculto));

  -- ===================== 08. «Convertir en daño» (la RPC, sin botón) =====================
  v_dano := pg_temp.dano(op, jsonb_build_object('lat', pg_temp.lat(0), 'lon', pg_temp.lon(0), 'no_identificado', 'ZT15 tubería del reporte'));
  v_x := public.geoportal_redes_l116_vincular_dano(sd, v_base + 1, v_dano, 'ZT15 el reporte de la 116 resultó ser este daño');
  v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', null, null);
  perform pg_temp.reg('08.01 el supervisor une el reporte con el daño (con motivo, auditado) y el punto del mapa lo muestra',
     (v_x ->> 'unido')::boolean and pg_temp.punto(v_g, v_base + 1) -> 'danos' = to_jsonb(array[v_dano])
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_l116_vincular_dano' and referencia = (v_base + 1)::text), v_x::text);
  perform pg_temp.err('08.02 el operador no lo hace', format('select public.geoportal_redes_l116_vincular_dano(%L, %s, %L, %L)', op, v_base + 1, v_dano, 'ZT15 no debe poder'), '42501');
  perform pg_temp.err('08.03 no se une dos veces', format('select public.geoportal_redes_l116_vincular_dano(%L, %s, %L, %L)', sd, v_base + 1, v_dano, 'ZT15 otra vez lo mismo'), null, 'ya está unido');
  perform pg_temp.err('08.04 sin motivo, no', format('select public.geoportal_redes_l116_vincular_dano(%L, %s, %L, %L)', sd, v_base + 3, v_dano, 'corto'), null, 'motivo');
  perform pg_temp.err('08.05 un reporte que no existe, no', format('select public.geoportal_redes_l116_vincular_dano(%L, %s, %L, %L)', sd, v_base + 99, v_dano, 'ZT15 reporte que no existe'), 'P0002');

  -- ===================== 09. Punto 8: los formularios compartidos en Personal del Dashboard distribución =====================
  v_r := public.geoportal_redes_personal(sd, 'prueba.redes15', 'todas');
  perform pg_temp.reg('09.01 Personal lista «Reportar anomalía» y «Revisiones generales» entre los formularios de distribución',
     (select count(*) from jsonb_array_elements(v_r -> 'formularios') f where f ->> 'clave' in ('anomalia_compartida', 'revision_compartida')) = 2);
  perform public.geoportal_redes_personal_formulario(sd, op, 'anomalia_compartida', true, 'ZT15 el operador reporta anomalías desde Técnica');
  perform public.geoportal_redes_personal_formulario(sd, op, 'revision_compartida', true, 'ZT15 el operador hace revisiones generales');
  v_r := public.geoportal_redes_personal(sd, 'prueba.redes15.op', 'todas');
  perform pg_temp.reg('09.02 el supervisor de distribución se los asigna a un operador (quedan en sus formularios)',
     tecnica.f_formulario_asignado(op, 'anomalia_compartida') and tecnica.f_formulario_asignado(op, 'revision_compartida')
     and (v_r -> 'personas' -> 0 -> 'formularios') @> '["anomalia_compartida", "revision_compartida"]'::jsonb, (v_r -> 'personas' -> 0 -> 'formularios')::text);

  -- ===================== 10. Tiempos con el volumen real: 22.978 reportes sintéticos por el motor =====================
  -- Contratos tomados del catastro de esta base (como en el archivo: ~86 % con predio; el resto con un contrato que no existe, una dirección y un barrio
  -- de prueba que tampoco: así se mide el peor caso, la pasada por el catastro). Las fechas, repartidas en los últimos 12 meses.
  select array_agg(cod_usuario) into v_cods from (select distinct cod_usuario from public.catastro_valledupar where cod_usuario ~ '^[0-9]{1,8}$' and cod_usuario not in ('0', '99999999')
                                                    and cod_usuario not like '995150%' order by cod_usuario limit 20000) x;
  v_nc := coalesce(cardinality(v_cods), 0);
  v_t0 := clock_timestamp();
  v_cv := (public.geoportal_redes_cargue_iniciar(sd, 'linea_116', md5('zt15-volumen') || md5('zt15-volumen-b'), 'xlsx', 4326, 'reporte', v_n, 'ZT15 volumen real') ->> 'carga_id')::bigint;
  v_ms_ini := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  k := 0;
  while k < v_n loop
    select jsonb_agg(pg_temp.fila(i, 995200000 + i, case when i % 11 = 0 then 'Registrado' else 'Atendido' end,
                                  to_char((clock_timestamp() at time zone 'America/Bogota') - make_interval(days => i % 360, mins => i % 1440), 'YYYY-MM-DD HH24:MI:SS'),
                                  case when i % 7 = 0 or v_nc = 0 then '9952' || i else v_cods[1 + (i * 7919) % v_nc] end,
                                  'ZT15 DIR ' || i, 'ZT15 BARRIO ' || (i % 50), 'ZT15 CAUSAL ' || (i % 29),
                                  case when i % 3 = 0 then 'Alcantarillado' when i % 41 = 0 then 'Incidentes Externos' else 'Acueducto' end) order by i)
      into v_lote from generate_series(k + 1, least(k + 200, v_n)) i;
    v_t0 := clock_timestamp();
    perform public.geoportal_redes_carga_lote(sd, v_cv, v_lote);
    v_ms_lote := greatest(v_ms_lote, round(extract(epoch from clock_timestamp() - v_t0) * 1000));
    k := k + 200;
  end loop;
  v_t0 := clock_timestamp(); v_r := public.geoportal_redes_carga_resumen(sd, v_cv); v_ms_res := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_x := public.geoportal_redes_carga_publicar(sd, v_cv, 'ZT15 carga de volumen real'); v_ms_pub := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_g := public.geoportal_redes_geovisor_capa(sd, 'pqr_116', (v_hoy - interval '12 months')::date, v_hoy); v_ms_capa := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_geovisor_capa(sd, 'pqr_116', v_hoy - 6, v_hoy); v_ms_capa_hoy := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS con %s reportes (%s contratos del catastro): iniciar %s ms · lote más lento %s ms · resumen %s ms · publicar %s ms · capa de 12 meses %s ms (%s puntos%s) · capa de 7 días %s ms · ubicación %s',
                   v_n, v_nc, v_ms_ini, v_ms_lote, v_ms_res, v_ms_pub, v_ms_capa, jsonb_array_length(v_g -> 'features'), case when (v_g ->> 'recortada')::boolean then ', recortada' else '' end,
                   v_ms_capa_hoy, v_x -> 'ubicacion');
  perform pg_temp.reg('10.01 la carga completa se publica: 22.978 nuevos', (v_x ->> 'nuevos')::integer = v_n and (v_r ->> 'lista_para_publicar')::boolean, v_info);
  perform pg_temp.reg('10.02 cada lote en menos de 8 s; el resumen y la publicación, cada uno en menos de 30 s (el tope de la Edge)',
     v_ms_lote < 8000 and v_ms_res < 30000 and v_ms_pub < 30000, v_info);
  perform pg_temp.reg('10.03 la capa del geovisor (12 meses y 7 días) en menos de 8 s', greatest(v_ms_capa, v_ms_capa_hoy) < 8000, v_info);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 5d (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
