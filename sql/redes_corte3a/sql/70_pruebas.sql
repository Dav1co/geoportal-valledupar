-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 25, 30 y 40, en la misma transacción.
-- Se corre DESPUÉS de la carga real del 1a y del Corte 2 publicados: NO supone códigos (RED-000001 es un tubo real; DAN-… e ITV-… pueden
-- existir), ni conteos de la base, ni que no haya daños reales cerca. Toma sus códigos de lo que crea (por la llave de su red de prueba,
-- ID 99300xx y LABEL ZT3-…) y compara siempre contra lo suyo. Al publicar su red, lo real de esas capas queda «retirado» dentro de la
-- transacción, que se deshace al final.
-- No deja rastro: crea sus usuarios (prueba.redes3.*), su red, sus daños, sus archivos de prueba en storage.objects y termina con un ERROR
-- a propósito que deshace todo y trae el informe en el mensaje.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 3a … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.sha(p text) returns text language sql as $$ select encode(sha256(convert_to(p, 'UTF8')), 'hex') $$;
-- posición de prueba: x, y en metros aproximados desde un origen dentro de Valledupar
create function pg_temp.p(x numeric, y numeric) returns text language sql as $$ select (-73.2400 + x * 0.0000091)::text || ' ' || (10.4700 + y * 0.0000090)::text $$;
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4700 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.2400 + x * 0.0000091, 6) $$;
create function pg_temp.tramo(p_orden integer, p_id integer, p_label text, p_ini text, p_ini_nom text, p_fin text, p_fin_nom text, p_wkt text) returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', p_wkt, 'atributos', jsonb_build_object('ID', p_id, 'LABEL', p_label, 'MATERIAL', 'PVC', 'D', 3, 'LENGTH', 100, 'ZONE', null,
         'IS_ACTIVE?', true, 'CHK_VLVE?', false, 'STARTNODID', p_ini, 'STARTNODE', p_ini_nom, 'STOPNODEID', p_fin, 'STOPNODE', p_fin_nom)) $$;
-- archivo de prueba en Storage (la subida real la hace el celular con la URL firmada)
create function pg_temp.archivo(p_ruta text, p_bytes integer default 300000, p_mime text default 'image/jpeg') returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', p_bytes, 'mimetype', p_mime)) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
-- datos base de una intervención válida (se cambian claves en cada prueba)
create function pg_temp.itv(p_archivos jsonb, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('nace_de', 'programada', 'tipo', 'preventivo', 'sistema', 'acueducto', 'activo', current_setting('zt.red1'),
         'lat', pg_temp.lat(0), 'lon', pg_temp.lon(50), 'precision_m', 5, 'ubicacion_origen', 'gps', 't_inicio', pg_temp.iso('-3 hours'), 't_fin', pg_temp.iso('-1 hours'),
         'descripcion', 'Revisión y limpieza de prueba del tramo', 'materiales', '[]'::jsonb, 'ejecutor', 'emdupar',
         'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')), 'archivos', p_archivos) || p_extra $$;
create function pg_temp.a1(p_ruta text, p_clase text default 'despues') returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('n', 1, 'clase', p_clase, 'ruta', p_ruta)) $$;
-- un daño válido (para los que se atienden), con su foto ya en Storage
create function pg_temp.dano(p_quien text, p_extra jsonb) returns jsonb language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_dano(p_quien, 1);
begin
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  return public.geoportal_redes_crear_dano(p_quien, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', current_setting('zt.red1'),
         'lat', pg_temp.lat(0), 'lon', pg_temp.lon(40), 'ubicacion_origen', 'gps', 't_detectado', pg_temp.iso('-5 hours'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
         'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))) || p_extra);
end $$;
-- prepara una intervención y sube sus archivos de prueba; devuelve la preparación
create function pg_temp.preparar(p_quien text, p_fotos integer, p_docs integer default 0) returns jsonb language plpgsql as $$
declare v_p jsonb := public.geoportal_redes_preparar_intervencion(p_quien, p_fotos, p_docs); x jsonb;
begin
  for x in select e from jsonb_array_elements(v_p -> 'fotos') e loop perform pg_temp.archivo(x ->> 'ruta'); end loop;
  for x in select e from jsonb_array_elements(v_p -> 'documentos') e loop perform pg_temp.archivo(x ->> 'ruta', 800000, 'application/pdf'); end loop;
  return v_p;
end $$;

do $prueba$
declare
  a text := 'prueba.redes3.adm@emdupar.gov.co'; sv text := 'prueba.redes3.sup@emdupar.gov.co'; op text := 'prueba.redes3.op@emdupar.gov.co';
  sf text := 'prueba.redes3.sinform@emdupar.gov.co'; na text := 'prueba.redes3.nada@emdupar.gov.co';
  v_red1 text; v_red2 text; v_val text; v_acc text; v_tor text; v_poz1 text; v_poz2 text; v_col text;
  v_c bigint; v_r jsonb; v_x jsonb; v_p jsonb; v_id uuid; v_ruta text;
  v_d1 text; v_d2 text; v_d3 text; v_d4 text; v_d5 text; v_dn text; v_itv0 bigint; v_tes0 integer;
  v_ia text; v_ib text; v_ic text; v_id_txt text; v_ie text; v_if text; v_ig text; v_nuevo_red text; v_nuevo_val text; v_ida uuid;
  v_total integer; v_bien integer; v_fallas text;
  w1 text := 'LINESTRING(' || pg_temp.p(0, 0) || ',' || pg_temp.p(100, 0) || ')';
  w2 text := 'LINESTRING(' || pg_temp.p(100, 0) || ',' || pg_temp.p(200, 0) || ')';
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'Supervisor', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'Operador', 'consulta', true, 'sin_restriccion', 'todos'),
    (sf, 'Operador sin el formulario', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'mantenimiento', a), (op, 'asignar_formulario', 'danos_fallas', a),
    (sf, 'asignar_formulario', 'danos_fallas', a);

  -- red de prueba con el motor del 1a: 2 tramos de acueducto (V993 → Tee-993 → Torre-993) y 2 pozos con un conducto
  v_c := (public.geoportal_redes_carga_iniciar(a, 'acueducto', pg_temp.sha('zt3-acu'), 'shp', 4326, 'ID', 2) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    pg_temp.tramo(1, 9930001, 'Distribucion-ZT31', '99301', 'V993', '99302', 'Tee-993', w1), pg_temp.tramo(2, 9930002, 'Lateral-ZT32', '99302', 'Tee-993', '99303', 'Torre-993', w2)));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Red de prueba del Corte 3a');
  v_c := (public.geoportal_redes_carga_iniciar(a, 'alc_pozos', pg_temp.sha('zt3-poz'), 'shp', 4326, 'LABEL', 2) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    jsonb_build_object('orden', 1, 'wkt', 'POINT(' || pg_temp.p(0, 300) || ')', 'atributos', jsonb_build_object('LABEL', 'ZT3-PA', 'EST_POZO', 'VISIBLE', 'ESTADO', 'Existente', 'C_RASANTE', 100, 'C_FONDO', 98)),
    jsonb_build_object('orden', 2, 'wkt', 'POINT(' || pg_temp.p(100, 300) || ')', 'atributos', jsonb_build_object('LABEL', 'ZT3-PB', 'EST_POZO', 'VISIBLE', 'ESTADO', 'Existente', 'C_RASANTE', 100, 'C_FONDO', 97))));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Pozos de prueba del Corte 3a');
  v_c := (public.geoportal_redes_carga_iniciar(a, 'alc_conductos', pg_temp.sha('zt3-con'), 'shp', 4326, 'LABEL', 1) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(jsonb_build_object('orden', 1, 'wkt', 'LINESTRING(' || pg_temp.p(0, 300) || ',' || pg_temp.p(100, 300) || ')',
    'atributos', jsonb_build_object('LABEL', 'ZT3-PA-PB', 'PZ_INICIAL', 'ZT3-PA', 'PZ_FINAL', 'ZT3-PB', 'MATERIAL', 'PVC', 'DIAMETRO', 200, 'ESTADO', 'Existente'))));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Conducto de prueba del Corte 3a');
  select codigo into v_red1 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9930001';
  select codigo into v_red2 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9930002';
  select codigo into v_val from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99301';
  select codigo into v_acc from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99302';
  select codigo into v_tor from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99303';
  select codigo into v_poz1 from redes.v_activo_vigente where capa_codigo = 'alc_pozos' and llave_capa = 'ZT3-PA';
  select codigo into v_poz2 from redes.v_activo_vigente where capa_codigo = 'alc_pozos' and llave_capa = 'ZT3-PB';
  select codigo into v_col from redes.v_activo_vigente where capa_codigo = 'alc_conductos' and llave_capa = 'ZT3-PA-PB';
  perform set_config('zt.red1', v_red1, true);
  perform pg_temp.reg('00.01 red de prueba: 2 RED, VAL, ACC, TOR, 2 POZ y COL, encontrados por su llave',
     v_red1 like 'RED-%' and v_red2 like 'RED-%' and v_val like 'VAL-%' and v_acc like 'ACC-%' and v_tor like 'TOR-%' and v_poz1 like 'POZ-%' and v_poz2 like 'POZ-%' and v_col like 'COL-%'
     and (select count(*) from redes.activo_vigente_mat where codigo in (v_red1, v_red2, v_val, v_acc, v_tor, v_poz1, v_poz2, v_col) and not retirado) = 8,
     concat_ws(' ', v_red1, v_red2, v_val, v_acc, v_tor, v_poz1, v_poz2, v_col));
  select ultimo into v_itv0 from redes.consecutivos where prefijo = 'ITV';
  select version into v_tes0 from redes.tesela_version where sistema = 'acueducto';

  -- ---------- 01 Catálogo, parámetros y reglas ----------
  perform pg_temp.reg('01.01 cinco tipos (correctivo, reparación y reposición atienden daños; inversión aparte) y 8 unidades',
     (select string_agg(codigo, ',' order by orden) from redes.tipos_intervencion) = 'preventivo,correctivo,reparacion,reposicion,inversion'
     and (select string_agg(codigo, ',' order by orden) from redes.tipos_intervencion where admite_dano) = 'correctivo,reparacion,reposicion'
     and (select es_inversion from redes.tipos_intervencion where codigo = 'inversion') and (select count(*) from redes.unidades_material) = 8);
  perform pg_temp.reg('01.02 parámetros: 7 días atrás, 72 h, 1 a 9 fotos, 3 PDF, 150 m para los daños, 50 m para la propuesta',
     redes.f_param('itv_dias_atras_max') = 7 and redes.f_param('itv_max_horas') = 72 and redes.f_param('min_fotos_itv') = 1 and redes.f_param('max_fotos_itv') = 9
     and redes.f_param('max_docs_itv') = 3 and redes.f_param('itv_radio_danos_m') = 150 and redes.f_param('itv_radio_propuesta_m') = 50);
  perform pg_temp.err('01.03 un tipo de intervención no se borra', $$delete from redes.tipos_intervencion where codigo = 'preventivo'$$, '42501');
  perform pg_temp.err('01.04 el código de un tipo no cambia', $$update redes.tipos_intervencion set codigo = 'prev' where codigo = 'preventivo'$$, '42501');

  -- ---------- 02 Permisos ----------
  perform pg_temp.reg('02.01 ningún privilegio de la API sobre las tablas y vistas; RLS activa en todas',
     not exists (select 1 from pg_class c cross join (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                  where c.relnamespace = 'redes'::regnamespace and c.relkind in ('r', 'v', 'S') and (has_table_privilege(r.rol, c.oid, 'select') or has_table_privilege(r.rol, c.oid, 'insert')))
     and not exists (select 1 from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'r' and not relrowsecurity));
  perform pg_temp.reg('02.02 las 8 RPC nuevas y las 2 reemplazadas: security definer, search_path fijo y solo service_role', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
       ('geoportal_redes_formulario_intervencion', 'geoportal_redes_danos_abiertos', 'geoportal_redes_preparar_intervencion', 'geoportal_redes_crear_intervencion',
        'geoportal_redes_intervencion_recursos', 'geoportal_redes_intervenciones', 'geoportal_redes_no_identificados', 'geoportal_redes_asociar_activo',
        'geoportal_redes_preparar_dano', 'geoportal_redes_crear_dano')
       and p.prosecdef and p.proconfig is not null and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
       and not has_function_privilege('authenticated', p.oid, 'execute') and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 10);
  perform pg_temp.reg('02.03 las funciones internas (crear activo, fuentes, supervisor…) no las ejecuta la API',
     not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname in ('f_activo_crear', 'f_mat_refrescar_uno', 'f_fuentes_validas', 'f_supervisor', 'f_dano_elegible')
                  and (has_function_privilege('service_role', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))));

  -- ---------- 03 Formulario ----------
  v_r := public.geoportal_redes_formulario_intervencion(op);
  perform pg_temp.reg('03.01 operador con «mantenimiento»: 5 tipos, aportantes, unidades, tipos de activo nuevo; al menos 1 foto y sin valores',
     v_r ->> 'perfil' = 'operador' and jsonb_array_length(v_r -> 'tipos') = 5 and jsonb_array_length(v_r -> 'unidades') = 8
     and exists (select 1 from jsonb_array_elements(v_r -> 'aportantes') x where x ->> 'codigo' = 'alcaldia')
     and exists (select 1 from jsonb_array_elements(v_r -> 'tipos_nuevo') x where x ->> 'prefijo' = 'RED' and x ->> 'geometria' = 'linea')
     and exists (select 1 from jsonb_array_elements(v_r -> 'tipos_nuevo') x where x ->> 'prefijo' = 'VAL' and (x ->> 'clase_obligatoria')::boolean)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'tipos_nuevo') x where x ->> 'prefijo' in ('SEC', 'SEN', 'SCA'))
     and (v_r -> 'reglas' ->> 'min_fotos')::integer = 1 and not (v_r -> 'reglas' ->> 'puede_sin_fotos')::boolean and not (v_r -> 'reglas' ->> 'pone_valores')::boolean, left(v_r::text, 400));
  perform pg_temp.err('03.02 operador SIN «mantenimiento»: 42501', format($$select public.geoportal_redes_formulario_intervencion(%L)$$, sf), '42501');
  perform pg_temp.err('03.03 sin Técnica: 42501', format($$select public.geoportal_redes_formulario_intervencion(%L)$$, na), '42501');
  v_r := public.geoportal_redes_formulario_intervencion(sv);
  perform pg_temp.reg('03.04 el supervisor pasa sin asignación; puede registrar sin fotos y poner los valores',
     v_r ->> 'perfil' = 'supervisor' and (v_r -> 'reglas' ->> 'min_fotos')::integer = 0 and (v_r -> 'reglas' ->> 'puede_sin_fotos')::boolean and (v_r -> 'reglas' ->> 'pone_valores')::boolean);

  -- ---------- 04 Preparar ----------
  perform pg_temp.err('04.01 el operador no prepara sin fotos', format($$select public.geoportal_redes_preparar_intervencion(%L, 0)$$, op), '22023', 'de 1 a 9 fotos');
  perform pg_temp.err('04.02 diez fotos', format($$select public.geoportal_redes_preparar_intervencion(%L, 10)$$, op), '22023');
  perform pg_temp.err('04.03 cuatro documentos', format($$select public.geoportal_redes_preparar_intervencion(%L, 1, 4)$$, op), '22023', 'documentos');
  v_p := pg_temp.preparar(op, 2, 1);
  v_id := (v_p ->> 'intervencion_id')::uuid; v_ruta := v_p -> 'fotos' -> 0 ->> 'ruta';
  perform pg_temp.reg('04.04 preparar 2 fotos y 1 documento: id reservado; rutas 1.jpg, 2.jpg y 3.pdf bajo intervenciones/AAAA-MM/<id>/',
     jsonb_array_length(v_p -> 'fotos') = 2 and v_ruta ~ ('^intervenciones/[0-9]{4}-[0-9]{2}/' || v_id || '/1\.jpg$')
     and v_p -> 'documentos' -> 0 ->> 'ruta' ~ ('/' || v_id || '/3\.pdf$') and exists (select 1 from redes.intervencion_preparaciones where intervencion_id = v_id and autor = op), v_p::text);
  perform pg_temp.reg('04.05 el supervisor sí prepara sin fotos', jsonb_array_length(public.geoportal_redes_preparar_intervencion(sv, 0) -> 'fotos') = 0);

  -- ---------- 05 Daños de prueba y «daños abiertos» cercanos ----------
  v_d1 := pg_temp.dano(op, '{}') ->> 'codigo';                                                                          -- en el tramo 1, reportado
  v_d2 := pg_temp.dano(op, jsonb_build_object('activo', v_red2, 'lon', pg_temp.lon(150), 't_inicio_reparacion', pg_temp.iso('-4 hours'))) ->> 'codigo';   -- tramo 2, en atención
  v_d3 := pg_temp.dano(op, jsonb_build_object('t_inicio_reparacion', pg_temp.iso('-4 hours'), 't_restablecido', pg_temp.iso('-3 hours'))) ->> 'codigo';  -- atendido
  v_d4 := pg_temp.dano(op, jsonb_build_object('sistema', 'alcantarillado', 'tipo', 'rebose', 'tipo_rotura', null, 'activo', v_poz1, 'lat', pg_temp.lat(300), 'lon', pg_temp.lon(0))) ->> 'codigo';
  v_d5 := pg_temp.dano(op, jsonb_build_object('activo', null, 'no_identificado', 'Fuga lejos de la red de prueba', 'lat', pg_temp.lat(2000), 'lon', pg_temp.lon(0), 'ubicacion_origen', 'mapa')) ->> 'codigo';
  perform pg_temp.reg('05.01 cinco daños de prueba creados con el formulario del Corte 2', v_d1 like 'DAN-%' and v_d2 like 'DAN-%' and v_d3 like 'DAN-%' and v_d4 like 'DAN-%' and v_d5 like 'DAN-%'
     and (select estado from redes.v_dano where codigo = v_d2) = 'en_atencion' and (select estado from redes.v_dano where codigo = v_d3) = 'atendido', concat_ws(' ', v_d1, v_d2, v_d3, v_d4, v_d5));
  v_r := public.geoportal_redes_danos_abiertos(op, 'acueducto', v_red1);
  perform pg_temp.reg('05.02 daños abiertos del tramo 1: primero el suyo, luego el del tramo vecino (a ~100 m); no el atendido, ni el de alcantarillado, ni el lejano',
     v_r -> 'danos' -> 0 ->> 'codigo' = v_d1 and (v_r -> 'danos' -> 0 ->> 'mismo_activo')::boolean
     and exists (select 1 from jsonb_array_elements(v_r -> 'danos') x where x ->> 'codigo' = v_d2 and not (x ->> 'mismo_activo')::boolean)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'danos') x where x ->> 'codigo' in (v_d3, v_d4, v_d5)), v_r::text);
  v_r := public.geoportal_redes_danos_abiertos(op, 'alcantarillado', null, pg_temp.lat(300), pg_temp.lon(5));
  perform pg_temp.reg('05.03 por posición (sin activo), en alcantarillado: el rebose del pozo', exists (select 1 from jsonb_array_elements(v_r -> 'danos') x where x ->> 'codigo' = v_d4)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'danos') x where x ->> 'codigo' in (v_d1, v_d2)));
  perform pg_temp.reg('05.04 la lista no trae autores, nombres ni placas', position('@' in public.geoportal_redes_danos_abiertos(op, 'acueducto', v_red1)::text) = 0);
  perform pg_temp.err('05.05 daños abiertos sin el formulario: 42501', format($$select public.geoportal_redes_danos_abiertos(%L, 'acueducto', %L)$$, sf, v_red1), '42501');
  perform pg_temp.err('05.06 daños abiertos sin activo ni punto', format($$select public.geoportal_redes_danos_abiertos(%L, 'acueducto')$$, op), '22023', 'activo');

  -- ---------- 06 Crear: validaciones (cada una con el texto para la persona) ----------
  perform pg_temp.err('06.01 sin preparar', format($$select public.geoportal_redes_crear_intervencion(%L, gen_random_uuid(), %L)$$, op, pg_temp.itv(pg_temp.a1(v_ruta))), '22023', 'prepararse');
  perform pg_temp.err('06.02 el id preparado por otra persona', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sv, v_id, pg_temp.itv(pg_temp.a1(v_ruta))), '22023', 'prepararse');
  perform pg_temp.err('06.03 sin «de dónde nace»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"nace_de": null}')), '22023', 'de dónde nace');
  perform pg_temp.err('06.04 tipo que no existe', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"tipo": "pintura"}')), '22023', 'tipo de intervención');
  perform pg_temp.err('06.05 un preventivo no atiende un daño', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('nace_de', 'dano', 'dano', v_d1))), '22023', 'no atiende un daño');
  perform pg_temp.err('06.06 inversión sin decir si es activo nuevo o mejora', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"tipo": "inversion"}')), '22023', 'activo nuevo o mejora');
  perform pg_temp.err('06.07 sin sistema', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"sistema": "gas"}')), '22023', 'sistema');
  perform pg_temp.err('06.08 activo de otro sistema', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('activo', v_poz1))), '22023', 'no es de ese sistema');
  perform pg_temp.err('06.09 sin activo ni «qué es»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"activo": null}')), '22023', 'diga qué es');
  perform pg_temp.err('06.10 el principal repetido en «también intervenidos»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tambien', jsonb_build_array(v_red1)))), '22023', 'principal');
  perform pg_temp.err('06.11 también intervenido de otro sistema', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tambien', jsonb_build_array(v_col)))), '22023', 'no es de ese sistema');
  perform pg_temp.err('06.12 también intervenido repetido', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tambien', jsonb_build_array(v_val, lower(v_val))))), '22023', 'repetido');
  perform pg_temp.err('06.13 fin en el futuro', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('t_fin', pg_temp.iso('30 minutes')))), '22023', 'futuro');
  perform pg_temp.err('06.14 inicio después del fin', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('t_inicio', pg_temp.iso('-1 hours'), 't_fin', pg_temp.iso('-2 hours')))), '22023', 'después del fin');
  perform pg_temp.err('06.15 inicio de hace más de 7 días', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('t_inicio', pg_temp.iso('-8 days')))), '22023', '7 días');
  perform pg_temp.err('06.16 más de 72 horas', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('t_inicio', pg_temp.iso('-4 days')))), '22023', '72 horas');
  perform pg_temp.err('06.17 formulario abierto hace más de 12 horas', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('inicio_dispositivo', pg_temp.iso('-13 hours')))), '22023', '12 horas');
  perform pg_temp.err('06.18 hora mal escrita', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"t_fin": "hoy a las 3"}')), '22023', 'forma esperada');
  perform pg_temp.err('06.19 daño que no existe', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"nace_de": "dano", "tipo": "reparacion", "dano": "DAN-ZZZ"}')), '22023', 'no existe');
  perform pg_temp.err('06.20 daño ya atendido', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d3))), '22023', 'ya está atendido');
  perform pg_temp.err('06.21 daño lejano (a ~1,8 km)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d5))), '22023', 'ni de los cercanos');
  perform pg_temp.err('06.22 daño de otro sistema', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d4))), '22023', 'ni de los cercanos');
  perform pg_temp.err('06.23 la intervención empezó antes de que se detectara el daño', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d1, 't_inicio', pg_temp.iso('-6 hours')))), '22023', 'antes de que se detectara');
  perform pg_temp.err('06.24 descripción corta', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"descripcion": "listo"}')), '22023', 'Describa');
  perform pg_temp.err('06.25 material sin unidad', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"materiales": [{"material": "Tubo PVC 3 pulg", "cantidad": 6}]}')), '22023', 'unidad');
  perform pg_temp.err('06.26 material con cantidad 0', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"materiales": [{"material": "Tubo PVC 3 pulg", "cantidad": 0, "unidad": "m"}]}')), '22023', 'cantidad');
  perform pg_temp.err('06.27 ejecuta EMDUPAR pero trae contratista', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"contratista_nombre": "Obras ZT SAS"}')), '22023', 'contratista');
  perform pg_temp.err('06.28 contratista sin nombre', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"ejecutor": "contratista"}')), '22023', 'contratista');
  perform pg_temp.err('06.29 sin fuentes de recursos', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"fuentes": []}')), '22023', 'quién aporta');
  perform pg_temp.err('06.30 el operario no pone valores (D-8)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"fuentes": [{"aportante": "emdupar", "valor": 1000000}]}')), '22023', 'los pone el supervisor');
  perform pg_temp.err('06.31 «Otro» sin decir cuál', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id, pg_temp.itv(pg_temp.a1(v_ruta), '{"fuentes": [{"aportante": "otro"}]}')), '22023', 'otra entidad');
  perform pg_temp.err('06.32 fuente repetida', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"fuentes": [{"aportante": "emdupar"}, {"aportante": "emdupar"}]}')), '22023', 'repetida');
  perform pg_temp.err('06.33 foto que no se subió', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(replace(v_ruta, '/1.jpg', '/9.jpg')))), '22023');
  perform pg_temp.err('06.34 ruta de otra intervención', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1('intervenciones/2026-11/00000000-0000-4000-8000-000000000000/1.jpg'))), '22023', 'no corresponde');
  perform pg_temp.archivo(replace(v_ruta, '/1.jpg', '/1.pdf'), 400000, 'application/pdf');
  perform pg_temp.err('06.35 el operador sin fotos (solo un PDF)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'documento', 'ruta', replace(v_ruta, '/1.jpg', '/1.pdf'))))), '22023', 'al menos 1 foto');
  perform pg_temp.archivo(replace(v_ruta, '/1.jpg', '/2.pdf'));
  perform pg_temp.err('06.36 un documento que no es PDF (el archivo subido es JPEG)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'despues', 'ruta', v_ruta), jsonb_build_object('n', 2, 'clase', 'documento', 'ruta', replace(v_ruta, '/1.jpg', '/2.pdf'))))), '22023', 'debe ser PDF');
  perform pg_temp.archivo(replace(v_ruta, '/1.jpg', '/3.jpg'), 2000000);
  perform pg_temp.err('06.37 foto de más de 1,5 MB', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'antes', 'ruta', v_ruta), jsonb_build_object('n', 2, 'clase', 'despues', 'ruta', v_p -> 'fotos' -> 1 ->> 'ruta'),
                                   jsonb_build_object('n', 3, 'clase', 'despues', 'ruta', replace(v_ruta, '/1.jpg', '/3.jpg'))))), '22023');
  perform pg_temp.err('06.38 el operador no marca «sin evidencia»', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv('[]'::jsonb, '{"sin_evidencia_motivo": "Llegó por la línea 116"}')), '22023', 'al menos 1 foto');
  perform pg_temp.err('06.39 con fotos y «sin evidencia» a la vez', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), '{"sin_evidencia_motivo": "Llegó por la línea 116"}')), '22023', 'no marque');
  perform pg_temp.err('06.40 activo nuevo de otro sistema (pozo en acueducto)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
       'nuevo', jsonb_build_object('prefijo', 'POZ', 'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(10), pg_temp.lon(10))))))), '22023', 'tipo del activo nuevo');
  perform pg_temp.err('06.41 válvula nueva sin clase', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
       'nuevo', jsonb_build_object('prefijo', 'VAL', 'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(10), pg_temp.lon(10))))))), '22023', 'clase');
  perform pg_temp.err('06.42 tramo nuevo con un solo punto', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
       'nuevo', jsonb_build_object('prefijo', 'RED', 'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(10), pg_temp.lon(10))))))), '22023', 'inicio y el fin');
  perform pg_temp.err('06.43 activo nuevo fuera de Valledupar', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
       'nuevo', jsonb_build_object('prefijo', 'HID', 'puntos', jsonb_build_array(jsonb_build_array(4.6, -74.08)))))), '22023', 'dentro de Valledupar');
  perform pg_temp.err('06.44 activo nuevo y a la vez un activo existente', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_id,
     pg_temp.itv(pg_temp.a1(v_ruta), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo',
       'nuevo', jsonb_build_object('prefijo', 'HID', 'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(10), pg_temp.lon(10))))))), '22023', 'no lleva un activo existente');
  perform pg_temp.err('06.45 operador sin «mantenimiento» no crea', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sf, v_id, pg_temp.itv(pg_temp.a1(v_ruta))), '42501');
  perform pg_temp.reg('06.46 ninguna validación dejó nada (ni intervención, ni consecutivo, ni daño atendido)', not exists (select 1 from redes.intervenciones)
     and (select ultimo from redes.consecutivos where prefijo = 'ITV') = v_itv0 and (select estado from redes.v_dano where codigo = v_d1) = 'reportado');

  -- ---------- 07 Crear: los buenos ----------
  -- (a) operador: reparación que nace del daño 1, con la válvula también intervenida, materiales, 2 fotos y 1 PDF
  v_r := public.geoportal_redes_crear_intervencion(op, v_id, pg_temp.itv(jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'antes', 'ruta', v_ruta),
            jsonb_build_object('n', 2, 'clase', 'despues', 'ruta', v_p -> 'fotos' -> 1 ->> 'ruta'), jsonb_build_object('n', 3, 'clase', 'documento', 'ruta', v_p -> 'documentos' -> 0 ->> 'ruta')),
            jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d1, 't_inicio', pg_temp.iso('-4 hours'), 't_fin', pg_temp.iso('-2 hours'),
              'inicio_dispositivo', pg_temp.iso('-10 minutes'), 'tambien', jsonb_build_array(v_val), 'companeros', 'Cuadrilla 2',
              'materiales', jsonb_build_array(jsonb_build_object('material', 'Tubo PVC 3 pulg', 'cantidad', 6, 'unidad', 'm'), jsonb_build_object('material', 'Unión de reparación 3 pulg', 'cantidad', 2, 'unidad', 'und')),
              'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')))), '10.0.0.3');
  v_ia := v_r ->> 'codigo';
  perform pg_temp.reg('07.01 se guarda la reparación: ITV-…, cerrada, sobre el tramo 1; el daño queda atendido; recursos por completar',
     v_ia ~ '^ITV-[0-9]{6}$' and v_r ->> 'estado' = 'cerrada' and v_r ->> 'activo' = v_red1 and v_r ->> 'dano' = v_d1 and v_r ->> 'dano_estado' = 'atendido'
     and v_r ->> 'recursos' = 'por_completar' and not (v_r ->> 'sin_evidencia')::boolean and not (v_r ->> 'repetido')::boolean
     and (select ultimo from redes.consecutivos where prefijo = 'ITV') = v_itv0 + 1, v_r::text);
  select row_to_json(x)::jsonb into v_x from redes.v_dano x where codigo = v_d1;
  perform pg_temp.reg('07.02 el daño recibe los tiempos de la intervención: reparación de 2 h, respuesta de 1 h y el evento «atendido» con el código',
     (v_x ->> 'reparacion_s')::integer between 7190 and 7210 and (v_x ->> 'respuesta_s')::integer between 3590 and 3610
     and exists (select 1 from redes.dano_eventos e join redes.danos d on d.id = e.dano_id where d.codigo = v_d1 and e.tipo = 'atendido' and e.intervencion_id = v_id and e.motivo like '%' || v_ia || '%')
     and exists (select 1 from redes.dano_tiempos t join redes.danos d on d.id = t.dano_id where d.codigo = v_d1 and t.fuente = 'intervencion'), v_x::text);
  perform pg_temp.reg('07.03 quedan los materiales, la válvula también intervenida, la fuente sin valores, 2 fotos y 1 PDF leídos de Storage',
     (select count(*) from redes.intervencion_materiales where intervencion_id = v_id) = 2
     and (select array_agg(a.codigo) from redes.intervencion_activos x join redes.activos a on a.id = x.activo_id where x.intervencion_id = v_id) = array[v_val]
     and (select count(*) from redes.intervencion_fuentes where intervencion_id = v_id and version = 1 and valor is null and porcentaje is null and fuente = 'formulario') = 1
     and (select string_agg(clase || ':' || mime || ':' || bytes, ',' order by n) from redes.intervencion_archivos where intervencion_id = v_id)
         = 'antes:image/jpeg:300000,despues:image/jpeg:300000,documento:application/pdf:800000');
  perform pg_temp.reg('07.04 auditoría con el código y la IP, sin la posición', exists (select 1 from public.geoportal_auditoria where accion = 'redes_crear_intervencion' and referencia = v_ia and ip = '10.0.0.3'
     and detalle ->> 'dano' = v_d1 and not detalle ? 'lat'));
  v_x := public.geoportal_redes_crear_intervencion(op, v_id, pg_temp.itv(pg_temp.a1(v_ruta)));
  perform pg_temp.reg('07.05 reenviar el mismo id devuelve lo guardado («repetido»), sin otro código', v_x ->> 'codigo' = v_ia and (v_x ->> 'repetido')::boolean
     and (select count(*) from redes.intervenciones) = 1);
  v_p := pg_temp.preparar(op, 1);
  perform pg_temp.err('07.06 otra intervención no puede atender el mismo daño', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, (v_p ->> 'intervencion_id')::uuid,
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d1))), '22023', 'ya está atendido');

  -- (b) el daño 2 ya estaba en atención: se conserva su inicio de reparación y la intervención le pone el restablecido
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'),
            jsonb_build_object('nace_de', 'dano', 'tipo', 'correctivo', 'dano', v_d2, 'activo', v_red2, 't_inicio', pg_temp.iso('-3 hours'), 't_fin', pg_temp.iso('-90 minutes'))));
  v_ib := v_r ->> 'codigo';
  select row_to_json(x)::jsonb into v_x from redes.v_dano x where codigo = v_d2;
  perform pg_temp.reg('07.07 daño en atención: queda atendido, con su inicio de reparación de antes (hace 4 h) y el fin de la intervención (reparación 2,5 h)',
     v_r ->> 'dano_estado' = 'atendido' and (v_x ->> 'reparacion_s')::integer between 8990 and 9010, v_r::text || ' / ' || v_x::text);

  -- (c) supervisor desde el escritorio: preventivo SIN fotos, con el motivo; contratista escrito; los valores ya puestos
  v_p := public.geoportal_redes_preparar_intervencion(sv, 0); v_ida := (v_p ->> 'intervencion_id')::uuid;
  perform pg_temp.err('07.08 el supervisor sin fotos y sin motivo', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sv, v_ida, pg_temp.itv('[]'::jsonb)), '22023', 'por qué no hay evidencia');
  v_r := public.geoportal_redes_crear_intervencion(sv, v_ida, pg_temp.itv('[]'::jsonb, jsonb_build_object('activo', v_tor, 'sin_evidencia_motivo', 'Lo reportó el contratista por correo; no hay fotos',
            'ejecutor', 'contratista', 'contratista_nombre', 'Obras ZT SAS', 'contrato_orden', 'OT-ZT-77',
            'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar', 'porcentaje', 60, 'soporte', 'Presupuesto 2026'),
                                         jsonb_build_object('aportante', 'gobernacion', 'valor', 4000000, 'soporte', 'Convenio ZT-1')))));
  v_ic := v_r ->> 'codigo';
  perform pg_temp.reg('07.09 se guarda «sin evidencia fotográfica», con el contratista y los recursos completos',
     (v_r ->> 'sin_evidencia')::boolean and v_r ->> 'recursos' = 'completos'
     and exists (select 1 from redes.v_intervencion where codigo = v_ic and contratista = 'Obras ZT SAS' and contrato_orden = 'OT-ZT-77' and sin_evidencia_motivo like 'Lo reportó%'
                  and aportantes = array['EMDUPAR', 'Gobernación del Cesar']), v_r::text);

  -- (d) operador: inversión, tramo nuevo (dos puntos), aporta la alcaldía → activo nuevo «por verificar», origen tercero
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
            'lat', pg_temp.lat(50), 'lon', pg_temp.lon(250), 'ubicacion_origen', 'mapa',
            'nuevo', jsonb_build_object('prefijo', 'RED', 'material', 'PVC', 'diametro_mm', 110, 'nombre', 'Extensión de prueba',
                                        'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(0), pg_temp.lon(200)), jsonb_build_array(pg_temp.lat(100), pg_temp.lon(300)))),
            'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'alcaldia')))));
  v_id_txt := v_r ->> 'codigo'; v_nuevo_red := v_r ->> 'activo';
  perform pg_temp.reg('07.10 inversión en un tramo nuevo: crea RED-… (origen «intervención»), y la intervención queda sobre él',
     v_nuevo_red like 'RED-%' and (v_r ->> 'activo_creado')::boolean and v_nuevo_red not in (v_red1, v_red2)
     and exists (select 1 from redes.activos where codigo = v_nuevo_red and origen_alta = 'intervencion' and creado_por = op), v_r::text);
  perform pg_temp.reg('07.11 el tramo nuevo: «por verificar», en operación, PVC de 110 mm, ~140 m, instalado hoy, en la tabla vigente y con la tesela subida',
     exists (select 1 from redes.v_activo_vigente v where v.codigo = v_nuevo_red and v.por_verificar and v.estado_codigo = 'en_operacion' and v.material_codigo = 'PVC'
              and v.diametro_mm = 110 and v.longitud_m between 130 and 150 and v.fecha_instalacion = (clock_timestamp() at time zone 'America/Bogota')::date and v.atributos ->> 'intervencion' = v_id_txt)
     and exists (select 1 from redes.activo_vigente_mat where codigo = v_nuevo_red and not retirado)
     and (select version from redes.tesela_version where sistema = 'acueducto') > v_tes0);
  perform pg_temp.reg('07.12 el origen del tramo nuevo sale de quién aporta: tercero (alcaldía); solo lo ve el supervisor',
     exists (select 1 from redes.v_activo_origen_vigente o join redes.activos x on x.id = o.activo_id where x.codigo = v_nuevo_red and o.origen = 'tercero' and o.aportante_codigo = 'alcaldia')
     and public.geoportal_redes_activo(op, v_nuevo_red) -> 'origen' is null and public.geoportal_redes_activo(sv, v_nuevo_red) -> 'origen' ->> 'origen' = 'tercero');

  -- (e) operador: inversión, válvula nueva (punto, clase cierre); aportan EMDUPAR y la Nación → origen mixto
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'nuevo', 'activo', null,
            'nuevo', jsonb_build_object('prefijo', 'VAL', 'clase', 'cierre', 'puntos', jsonb_build_array(jsonb_build_array(pg_temp.lat(0), pg_temp.lon(60)))),
            'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar'), jsonb_build_object('aportante', 'nacion')))));
  v_ie := v_r ->> 'codigo'; v_nuevo_val := v_r ->> 'activo';
  perform pg_temp.reg('07.13 válvula nueva: VAL-… de clase cierre, origen mixto (EMDUPAR y Nación)', v_nuevo_val like 'VAL-%'
     and exists (select 1 from redes.v_activo_vigente where codigo = v_nuevo_val and clase = 'cierre' and GeometryType(geom) = 'POINT' and por_verificar)
     and exists (select 1 from redes.v_activo_origen_vigente o join redes.activos x on x.id = o.activo_id where x.codigo = v_nuevo_val and o.origen = 'mixto' and o.aportante_codigo = 'nacion'), v_r::text);

  -- (f) operador: correctivo en alcantarillado, activo no identificado (marcado en el mapa, al lado del pozo 2)
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('tipo', 'correctivo', 'sistema', 'alcantarillado', 'activo', null,
            'no_identificado', 'Cámara que no sale en el mapa', 'lat', pg_temp.lat(305), 'lon', pg_temp.lon(100), 'ubicacion_origen', 'mapa')));
  v_if := v_r ->> 'codigo';
  perform pg_temp.reg('07.14 «no identificado» en alcantarillado: se guarda sin activo', v_r -> 'activo' = 'null'::jsonb and v_r ->> 'estado' = 'cerrada', v_r::text);

  -- (g) operador: inversión, mejora del pozo 1
  v_p := pg_temp.preparar(op, 1); v_ida := (v_p ->> 'intervencion_id')::uuid;
  v_r := public.geoportal_redes_crear_intervencion(op, v_ida, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta', 'durante'), jsonb_build_object('tipo', 'inversion', 'inversion_modo', 'mejora',
            'sistema', 'alcantarillado', 'activo', v_poz1, 'lat', pg_temp.lat(300), 'lon', pg_temp.lon(0))));
  v_ig := v_r ->> 'codigo';
  perform pg_temp.reg('07.15 inversión de mejora del pozo 1: sin activo nuevo', v_r ->> 'activo' = v_poz1 and not (v_r ->> 'activo_creado')::boolean, v_r::text);

  -- ---------- 08 Epicrisis y ficha ----------
  v_r := public.geoportal_redes_epicrisis(op, v_red1);
  perform pg_temp.reg('08.01 epicrisis del tramo 1: la reparación es un «hecho», con el daño que atiende, la duración, «1 activo(s) más» y las fotos',
     exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ->> 'clase' = 'intervencion' and i ->> 'grupo' = 'hecho' and i ->> 'estado' = 'Cerrada'
              and i ->> 'resumen' = v_ia || ' · Reparación · atiende ' || v_d1 || ' · EMDUPAR · duración 2 h 00 min · 1 activo(s) más · 2 foto(s)')
     and exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ->> 'clase' = 'dano' and i ->> 'estado' = 'Atendido'), v_r::text);
  perform pg_temp.reg('08.02 la válvula también intervenida la tiene en su epicrisis, con el principal', exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_val) -> 'items') i
     where i ->> 'clase' = 'intervencion' and i ->> 'resumen' = v_ia || ' · Reparación · también intervenido (principal ' || v_red1 || ')'));
  perform pg_temp.reg('08.03 el tramo nuevo: su alta dice «(inversión ITV-…)» y tiene la intervención', exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_nuevo_red) -> 'items') i
     where i ->> 'clase' = 'alta' and i ->> 'resumen' = 'Alta del activo (inversión ' || v_id_txt || ')')
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_nuevo_red) -> 'items') i where i ->> 'clase' = 'intervencion' and i ->> 'resumen' like v_id_txt || ' · Inversión (activo nuevo) · programada o mejora%')
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_nuevo_red) -> 'items') i where i ->> 'clase' = 'evento_por_verificar'));
  perform pg_temp.reg('08.04 la ficha del tramo 1 cuenta 3 hechos (sus 2 daños y la intervención) y la del tramo nuevo dice «por verificar»',
     (public.geoportal_redes_activo(op, v_red1) -> 'epicrisis' ->> 'hechos')::integer = 3 and (public.geoportal_redes_activo(op, v_nuevo_red) -> 'activo' ->> 'por_verificar')::boolean);
  perform pg_temp.reg('08.05 el operador no ve autores en la epicrisis; el supervisor sí', not exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_red1) -> 'items') i where i ? 'autor')
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(sv, v_red1) -> 'items') i where i ->> 'autor' = op and i ->> 'clase' = 'intervencion'));
  perform pg_temp.reg('08.06 la intervención «sin evidencia» lo dice en la epicrisis de la torre', exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_tor) -> 'items') i
     where i ->> 'resumen' = v_ic || ' · Mantenimiento preventivo · programada o mejora · contratista Obras ZT SAS · duración 2 h 00 min · sin evidencia fotográfica'));

  -- ---------- 09 Supervisor: lista y recursos (D-8) ----------
  perform pg_temp.err('09.01 el operador no ve la lista de intervenciones', format($$select public.geoportal_redes_intervenciones(%L)$$, op), '42501');
  v_r := public.geoportal_redes_intervenciones(sv, 'recursos_por_completar');
  perform pg_temp.reg('09.02 «recursos por completar»: la reparación sí; la del supervisor (con valores) no',
     exists (select 1 from jsonb_array_elements(v_r -> 'intervenciones') x where x ->> 'codigo' = v_ia and x ->> 'autor' = op and x -> 'fuentes' -> 0 ->> 'aportante' = 'emdupar')
     and not exists (select 1 from jsonb_array_elements(v_r -> 'intervenciones') x where x ->> 'codigo' = v_ic), left(v_r::text, 600));
  perform pg_temp.err('09.03 el operador no completa recursos', format($$select public.geoportal_redes_intervencion_recursos(%L, %L, '[{"aportante": "emdupar", "valor": 1}]')$$, op, v_ia), '42501');
  perform pg_temp.err('09.04 completar sin valor ni porcentaje', format($$select public.geoportal_redes_intervencion_recursos(%L, %L, '[{"aportante": "emdupar"}]')$$, sv, v_ia), '22023', 'valor o su porcentaje');
  perform pg_temp.err('09.05 porcentajes que suman más de 100', format($$select public.geoportal_redes_intervencion_recursos(%L, %L, '[{"aportante": "emdupar", "porcentaje": 70}, {"aportante": "nacion", "porcentaje": 40}]')$$, sv, v_ia), '22023', 'más de 100');
  v_r := public.geoportal_redes_intervencion_recursos(sv, lower(v_ia), '[{"aportante": "emdupar", "valor": 2500000, "porcentaje": 100, "soporte": "Presupuesto de mantenimiento 2026"}]');
  perform pg_temp.reg('09.06 el supervisor completa: versión 2, recursos completos y el evento; la versión 1 sigue ahí', (v_r ->> 'version')::integer = 2 and v_r ->> 'recursos' = 'completos'
     and (select count(*) from redes.intervencion_fuentes x join redes.intervenciones i on i.id = x.intervencion_id where i.codigo = v_ia) = 2
     and exists (select 1 from redes.intervencion_eventos e join redes.intervenciones i on i.id = e.intervencion_id where i.codigo = v_ia and e.tipo = 'completar_recursos' and e.autor = sv), v_r::text);
  perform pg_temp.err('09.07 cambiar recursos completos sin motivo', format($$select public.geoportal_redes_intervencion_recursos(%L, %L, '[{"aportante": "emdupar", "valor": 1}]')$$, sv, v_ia), '22023', 'motivo');
  v_r := public.geoportal_redes_intervencion_recursos(a, v_ia, '[{"aportante": "emdupar", "valor": 2600000}]', 'Se corrigió el valor con la factura');
  perform pg_temp.reg('09.08 con motivo, el administrador los cambia (versión 3)', (v_r ->> 'version')::integer = 3);

  -- ---------- 10 Bandeja de no identificados y «asociar activo» ----------
  v_dn := pg_temp.dano(op, jsonb_build_object('activo', null, 'no_identificado', 'Fuga en un tubo que no sale', 'lat', pg_temp.lat(3), 'lon', pg_temp.lon(150), 'ubicacion_origen', 'mapa')) ->> 'codigo';
  perform pg_temp.err('10.01 el operador no ve la bandeja', format($$select public.geoportal_redes_no_identificados(%L)$$, op), '42501');
  v_r := public.geoportal_redes_no_identificados(sv, 100);
  perform pg_temp.reg('10.02 la bandeja trae la intervención y el daño no identificados, con los activos más cercanos propuestos',
     exists (select 1 from jsonb_array_elements(v_r -> 'items') x where x ->> 'clase' = 'intervencion' and x ->> 'codigo' = v_if and x ->> 'que_es' = 'Cámara que no sale en el mapa'
              and x -> 'propuestos' -> 0 ->> 'codigo' = v_poz2 and (x -> 'propuestos' -> 0 ->> 'distancia_m')::numeric < 10)
     and exists (select 1 from jsonb_array_elements(v_r -> 'items') x where x ->> 'clase' = 'dano' and x ->> 'codigo' = v_dn and x -> 'propuestos' -> 0 ->> 'codigo' = v_red2), left(v_r::text, 600));
  perform pg_temp.err('10.03 asociar sin motivo', format($$select public.geoportal_redes_asociar_activo(%L, 'intervencion', %L, %L, 'ok')$$, sv, v_if, v_poz2), '22023', 'motivo');
  perform pg_temp.err('10.04 asociar un activo de otro sistema', format($$select public.geoportal_redes_asociar_activo(%L, 'intervencion', %L, %L, 'Es la cámara de la esquina')$$, sv, v_if, v_red1), '22023', 'mismo sistema');
  perform pg_temp.err('10.05 el operador no asocia', format($$select public.geoportal_redes_asociar_activo(%L, 'intervencion', %L, %L, 'Es la cámara de la esquina')$$, op, v_if, v_poz2), '42501');
  v_r := public.geoportal_redes_asociar_activo(sv, 'intervencion', v_if, v_poz2, 'Es el pozo de la esquina, según el supervisor');
  perform pg_temp.reg('10.06 asociar la intervención al pozo 2: queda con activo (evento, sin reescribir), sale de la bandeja y entra a su epicrisis',
     v_r ->> 'activo' = v_poz2 and (select activo_codigo from redes.v_intervencion where codigo = v_if) = v_poz2
     and (select activo_id from redes.intervenciones where codigo = v_if) is null
     and not exists (select 1 from redes.v_no_identificados where codigo = v_if)
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_poz2) -> 'items') i where i ->> 'clase' = 'intervencion' and i ->> 'resumen' like v_if || ' ·%'));
  perform pg_temp.err('10.07 asociar dos veces', format($$select public.geoportal_redes_asociar_activo(%L, 'intervencion', %L, %L, 'Otra vez el mismo pozo')$$, sv, v_if, v_poz1), '22023', 'ya tiene activo');
  v_r := public.geoportal_redes_asociar_activo(a, 'dano', v_dn, v_red2, 'El tubo es el lateral de prueba');
  perform pg_temp.reg('10.08 asociar el daño no identificado al tramo 2: v_dano lo toma y entra a la epicrisis del tramo', (select activo_codigo from redes.v_dano where codigo = v_dn) = v_red2
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_red2) -> 'items') i where i ->> 'clase' = 'dano' and i ->> 'resumen' like v_dn || ' ·%'));

  -- ---------- 11 Daño sin fotos (respuesta 2 de David al Corte 2) ----------
  perform pg_temp.err('11.01 el operador no prepara un daño sin fotos', format($$select public.geoportal_redes_preparar_dano(%L, 0)$$, op), '22023', 'de 1 a 6 fotos');
  v_p := public.geoportal_redes_preparar_dano(sv, 0); v_ida := (v_p ->> 'dano_id')::uuid;
  perform pg_temp.reg('11.02 el supervisor sí, y la preparación no trae rutas', jsonb_array_length(v_p -> 'fotos') = 0);
  perform pg_temp.err('11.03 el supervisor sin fotos y sin el motivo', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, sv, v_ida,
     jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', v_red2, 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(160), 'ubicacion_origen', 'activo',
       't_detectado', pg_temp.iso('-1 hours'), 'tipo_rotura', 'fisura', 'riesgo', 'bajo', 'causa_clase', 'desconocida', 'fotos', '[]'::jsonb)), '22023', 'por qué no hay evidencia');
  v_r := public.geoportal_redes_crear_dano(sv, v_ida, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', v_red2, 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(160),
            'ubicacion_origen', 'activo', 't_detectado', pg_temp.iso('-1 hours'), 'tipo_rotura', 'fisura', 'riesgo', 'bajo', 'causa_clase', 'desconocida', 'fotos', '[]'::jsonb,
            'sin_evidencia_motivo', 'Llegó por la línea 116, sin fotos'));
  perform pg_temp.reg('11.04 se guarda «sin evidencia fotográfica», con su nota, y la epicrisis lo dice', (v_r ->> 'sin_evidencia')::boolean and v_r ->> 'estado' = 'reportado'
     and exists (select 1 from redes.dano_eventos where dano_id = v_ida and tipo = 'nota' and motivo = 'Sin evidencia fotográfica: Llegó por la línea 116, sin fotos')
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_red2) -> 'items') i where i ->> 'resumen' like (v_r ->> 'codigo') || ' %sin evidencia fotográfica'), v_r::text);
  v_p := public.geoportal_redes_preparar_dano(op, 1); v_ida := (v_p ->> 'dano_id')::uuid;
  perform pg_temp.err('11.05 el operador manda 0 fotos aunque escriba el motivo', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_ida,
     jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', v_red2, 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(160), 'ubicacion_origen', 'gps',
       't_detectado', pg_temp.iso('-1 hours'), 'tipo_rotura', 'fisura', 'riesgo', 'bajo', 'causa_clase', 'desconocida', 'fotos', '[]'::jsonb, 'sin_evidencia_motivo', 'No tengo cámara hoy')), '22023', 'de 1 a 6 fotos');
  perform pg_temp.reg('11.06 un daño con foto sigue igual que en el Corte 2 (no queda «sin evidencia»)', not (pg_temp.dano(op, '{}') ->> 'sin_evidencia')::boolean);

  -- ---------- 12 Hechos de solo inserción y coherencia ----------
  perform pg_temp.err('12.01 una intervención no se cambia', $$update redes.intervenciones set descripcion = 'cambiada a mano'$$, '42501');
  perform pg_temp.err('12.02 una fuente no se borra', $$delete from redes.intervencion_fuentes$$, '42501');
  perform pg_temp.err('12.03 los archivos no se vacían', $$truncate redes.intervencion_archivos$$, '42501');
  perform pg_temp.err('12.04 un evento no se cambia', $$update redes.intervencion_eventos set tipo = 'nota'$$, '42501');
  perform pg_temp.err('12.05 la regla de la tabla: un preventivo no nace de un daño', format($$insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, sistema, activo_id, lat, lon,
       ubicacion_origen, t_inicio, t_fin, descripcion, ejecutor, autor, no_ident_que_es) select gen_random_uuid(), 'ITV-999999', 'dano', d.id, 'preventivo', 'acueducto', null, 10.47, -73.24, 'mapa', now() - interval '1 hour', now(),
       'Directo a la tabla', 'emdupar', 'x', 'Prueba directa' from redes.danos d where d.codigo = %L$$, v_d1), '23514', 'no nace de un daño');
  perform pg_temp.err('12.06 la regla de la tabla: también intervenido de otro sistema', format($$insert into redes.intervencion_activos (intervencion_id, activo_id, n)
       select i.id, a.id, 9 from redes.intervenciones i, redes.activos a where i.codigo = %L and a.codigo = %L$$, v_ia, v_poz1), '23514');

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 3a (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
