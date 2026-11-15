-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 25, 30 y 40, en la misma transacción.
-- No deja rastro: crea sus usuarios (prueba.redes2.*), una red de prueba con el motor del 1a (llaves ZT-… e IDs 99100xx), fotos de
-- prueba en storage.objects y termina con un ERROR a propósito que deshace todo y trae el informe en el mensaje.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 2 … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.p(x numeric, y numeric) returns text language sql as $$ select (-73.2400 + x * 0.0000091)::text || ' ' || (10.4700 + y * 0.0000090)::text $$;
create function pg_temp.tramo(p_orden integer, p_id integer, p_label text, p_ini text, p_ini_nom text, p_fin text, p_fin_nom text, p_wkt text) returns jsonb language sql as $$
  select jsonb_build_object('orden', p_orden, 'wkt', p_wkt, 'atributos', jsonb_build_object('ID', p_id, 'LABEL', p_label, 'MATERIAL', 'PVC', 'D', 3, 'LENGTH', 100, 'ZONE', null,
         'IS_ACTIVE?', true, 'CHK_VLVE?', false, 'STARTNODID', p_ini, 'STARTNODE', p_ini_nom, 'STOPNODEID', p_fin, 'STOPNODE', p_fin_nom)) $$;
-- foto de prueba en Storage (la subida real la hace el celular con la URL firmada)
create function pg_temp.foto(p_ruta text, p_bytes integer default 300000, p_mime text default 'image/jpeg') returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', p_bytes, 'mimetype', p_mime)) $$;
-- datos base de un daño válido (se cambian claves en cada prueba)
create function pg_temp.datos(p_ruta text, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', 'RED-000001', 'lat', 10.47, 'lon', -73.2395, 'precision_m', 6, 'ubicacion_origen', 'gps',
         't_detectado', to_char(clock_timestamp() - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'tipo_rotura', 'parcial', 'largo_afectado_m', 2, 'riesgo', 'medio',
         'marcas', jsonb_build_array('via'), 'causa_clase', 'propia', 'causa', 'desgaste', 'descripcion', 'Fuga de prueba',
         'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', p_ruta))) || p_extra $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
-- tesela (z, x, y) que contiene un punto
create function pg_temp.tesela(z integer, lon numeric, lat numeric) returns integer[] language sql as $$
  select array[z, floor((lon + 180) / 360 * (1 << z))::integer,
               floor((1 - ln(tan(radians(lat::double precision)) + 1 / cos(radians(lat::double precision))) / pi()) / 2 * (1 << z))::integer] $$;

do $prueba$
declare
  a text := 'prueba.redes2.adm@emdupar.gov.co'; sv text := 'prueba.redes2.sup@emdupar.gov.co'; op text := 'prueba.redes2.op@emdupar.gov.co';
  sf text := 'prueba.redes2.sinform@emdupar.gov.co'; na text := 'prueba.redes2.nada@emdupar.gov.co';
  v_c bigint; v_r jsonb; v_x jsonb; v_p jsonb; v_id uuid; v_id2 uuid; v_id3 uuid; v_ruta text; v_rep uuid; v_rep2 uuid; v_rep3 uuid; v_t integer[]; v_s text;
  v_total integer; v_bien integer; v_fallas text;
  w1 text := 'LINESTRING(' || pg_temp.p(0, 0) || ',' || pg_temp.p(100, 0) || ')';
  w2 text := 'LINESTRING(' || pg_temp.p(100, 0) || ',' || pg_temp.p(200, 0) || ')';
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'Supervisor', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'Operador', 'consulta', true, 'sin_restriccion', 'todos'),
    (sf, 'Operador sin el formulario', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);

  -- red de prueba con el motor del 1a: 2 tramos de acueducto (V991 → Tee-991 → Torre-991) y 2 pozos con un conducto
  v_c := (public.geoportal_redes_carga_iniciar(a, 'acueducto', pg_temp.sha('zt2-acu'), 'shp', 4326, 'ID', 2) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    pg_temp.tramo(1, 9910001, 'Distribucion-ZT21', '99101', 'V991', '99102', 'Tee-991', w1), pg_temp.tramo(2, 9910002, 'Lateral-ZT22', '99102', 'Tee-991', '99103', 'Torre-991', w2)));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Red de prueba del Corte 2');
  v_c := (public.geoportal_redes_carga_iniciar(a, 'alc_pozos', pg_temp.sha('zt2-poz'), 'shp', 4326, 'LABEL', 2) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    jsonb_build_object('orden', 1, 'wkt', 'POINT(' || pg_temp.p(0, 300) || ')', 'atributos', jsonb_build_object('LABEL', 'ZT2-PA', 'EST_POZO', 'VISIBLE', 'ESTADO', 'Existente', 'C_RASANTE', 100, 'C_FONDO', 98)),
    jsonb_build_object('orden', 2, 'wkt', 'POINT(' || pg_temp.p(100, 300) || ')', 'atributos', jsonb_build_object('LABEL', 'ZT2-PB', 'EST_POZO', 'VISIBLE', 'ESTADO', 'Existente', 'C_RASANTE', 100, 'C_FONDO', 97))));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Pozos de prueba del Corte 2');
  v_c := (public.geoportal_redes_carga_iniciar(a, 'alc_conductos', pg_temp.sha('zt2-con'), 'shp', 4326, 'LABEL', 1) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(jsonb_build_object('orden', 1, 'wkt', 'LINESTRING(' || pg_temp.p(0, 300) || ',' || pg_temp.p(100, 300) || ')',
    'atributos', jsonb_build_object('LABEL', 'ZT2-PA-PB', 'PZ_INICIAL', 'ZT2-PA', 'PZ_FINAL', 'ZT2-PB', 'MATERIAL', 'PVC', 'DIAMETRO', 200, 'ESTADO', 'Existente'))));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Conducto de prueba del Corte 2');
  perform pg_temp.reg('00.01 red de prueba: RED-000001..2, VAL, ACC, TOR, POZ-000001..2 y COL-000001',
     (select count(*) from redes.activo_vigente_mat where codigo in ('RED-000001', 'RED-000002', 'VAL-000001', 'ACC-000001', 'TOR-000001', 'POZ-000001', 'POZ-000002', 'COL-000001')) = 8);

  -- ---------- 01 Catálogos, bucket y reglas ----------
  perform pg_temp.reg('01.01 13 tipos (7 daños y 6 fallas), 4 roturas, 6 causas, 6 terceros y 4 marcas',
     (select count(*) from redes.tipos_dano where clase = 'dano') = 7 and (select count(*) from redes.tipos_dano where clase = 'falla') = 6 and (select count(*) from redes.tipos_rotura) = 4
     and (select count(*) from redes.causas) = 6 and (select count(*) from redes.tipos_tercero) = 6 and (select count(*) from redes.marcas_riesgo) = 4);
  perform pg_temp.reg('01.02 caudales_fuga queda VACÍA (D-16)', not exists (select 1 from redes.caudales_fuga));
  perform pg_temp.reg('01.03 bucket redes-evidencias privado, 5 MB, JPEG y PDF, sin políticas', exists (select 1 from storage.buckets where id = 'redes-evidencias' and not public and file_size_limit = 5242880
     and allowed_mime_types = array['image/jpeg', 'application/pdf']) and not exists (select 1 from pg_policies where schemaname = 'storage' and (qual ilike '%redes-evidencias%' or with_check ilike '%redes-evidencias%')));
  perform pg_temp.reg('01.04 parámetros: 7 días atrás, 1 a 6 fotos de 1,5 MB, zoom 15 y accesorios desde 17', redes.f_param('dano_dias_atras_max') = 7 and redes.f_param('min_fotos_dano') = 1
     and redes.f_param('max_fotos_dano') = 6 and redes.f_param('max_bytes_foto_dano') = 1572864 and redes.f_param('mini_zoom_min') = 15 and redes.f_param('mini_zoom_acc') = 17);
  perform pg_temp.err('01.05 un tipo de daño no se borra', $$delete from redes.tipos_dano where codigo = 'otro_dano'$$, '42501');
  perform pg_temp.err('01.06 el código de un tipo de daño no cambia', $$update redes.tipos_dano set codigo = 'fuga2' where codigo = 'fuga'$$, '42501');

  -- ---------- 02 Permisos ----------
  perform pg_temp.reg('02.01 ningún privilegio de la API sobre las tablas y vistas nuevas; RLS activa en todas',
     not exists (select 1 from pg_class c cross join (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                  where c.relnamespace = 'redes'::regnamespace and c.relkind in ('r', 'v', 'S') and (has_table_privilege(r.rol, c.oid, 'select') or has_table_privilege(r.rol, c.oid, 'insert')))
     and not exists (select 1 from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'r' and not relrowsecurity));
  perform pg_temp.reg('02.02 las 8 RPC nuevas: security definer, search_path fijo y solo service_role', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
       ('geoportal_redes_formulario_dano', 'geoportal_redes_preparar_dano', 'geoportal_redes_crear_dano', 'geoportal_redes_activo_buscar', 'geoportal_redes_tramo_nodos', 'geoportal_redes_mvt',
        'geoportal_redes_reporte_convertir', 'geoportal_redes_reporte_descartar')
       and p.prosecdef and p.proconfig is not null and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
       and not has_function_privilege('authenticated', p.oid, 'execute') and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 8);
  perform pg_temp.reg('02.03 la entrada del bot (f_reporte_externo_recibir) es interna: nadie de la API la ejecuta',
     not has_function_privilege('service_role', 'redes.f_reporte_externo_recibir(jsonb)'::regprocedure, 'execute') and not has_function_privilege('anon', 'redes.f_reporte_externo_recibir(jsonb)'::regprocedure, 'execute'));

  -- ---------- 03 Formulario ----------
  v_r := public.geoportal_redes_formulario_dano(op);
  perform pg_temp.reg('03.01 operador con el formulario asignado: catálogos, reglas y «sin tabla de caudales»', jsonb_array_length(v_r -> 'tipos') = 13 and jsonb_array_length(v_r -> 'sistemas') = 2
     and (v_r -> 'reglas' ->> 'max_horas_inicio')::integer = 12 and not (v_r ->> 'hay_tabla_caudales')::boolean and v_r ->> 'perfil' = 'operador', left(v_r::text, 300));
  perform pg_temp.err('03.02 operador SIN el formulario asignado: 42501', format($$select public.geoportal_redes_formulario_dano(%L)$$, sf), '42501');
  perform pg_temp.err('03.03 sin Técnica: 42501', format($$select public.geoportal_redes_formulario_dano(%L)$$, na), '42501');
  perform pg_temp.reg('03.04 el supervisor pasa sin asignación', public.geoportal_redes_formulario_dano(sv) ->> 'perfil' = 'supervisor');

  -- ---------- 04 Preparar ----------
  perform pg_temp.err('04.01 preparar sin fotos (mínimo 1)', format($$select public.geoportal_redes_preparar_dano(%L, 0)$$, op), '22023', 'de 1 a 6 fotos');
  perform pg_temp.err('04.02 preparar 7 fotos', format($$select public.geoportal_redes_preparar_dano(%L, 7)$$, op), '22023');
  v_p := public.geoportal_redes_preparar_dano(op, 2);
  v_id := (v_p ->> 'dano_id')::uuid; v_ruta := v_p -> 'fotos' -> 0 ->> 'ruta';
  perform pg_temp.reg('04.03 preparar: id reservado y 2 rutas danos/AAAA-MM/<id>/n.jpg en redes-evidencias', v_p ->> 'bucket' = 'redes-evidencias' and jsonb_array_length(v_p -> 'fotos') = 2
     and v_ruta ~ ('^danos/[0-9]{4}-[0-9]{2}/' || v_id || '/1\.jpg$') and exists (select 1 from redes.dano_preparaciones where dano_id = v_id and autor = op));
  perform pg_temp.foto(v_ruta);

  -- ---------- 05 Crear: validaciones (cada una con el texto para la persona) ----------
  perform pg_temp.err('05.01 sin preparar', format($$select public.geoportal_redes_crear_dano(%L, gen_random_uuid(), %L)$$, op, pg_temp.datos(v_ruta)), '22023', 'prepararse');
  perform pg_temp.err('05.02 el id preparado por otra persona', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, sv, v_id, pg_temp.datos(v_ruta)), '22023', 'prepararse');
  perform pg_temp.err('05.03 tipo que no existe', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"tipo": "inventado"}')), '22023', 'qué pasó');
  perform pg_temp.err('05.04 clase que no es la del tipo', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"clase": "falla"}')), '22023', 'daño o falla');
  perform pg_temp.err('05.05 tipo que no aplica al sistema (rebose en acueducto)', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"tipo": "rebose", "tipo_rotura": null}')), '22023', 'no aplica');
  perform pg_temp.err('05.06 activo de otro sistema', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"activo": "POZ-000001"}')), '22023', 'no es de ese sistema');
  perform pg_temp.err('05.07 sin activo ni «qué es»', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"activo": null}')), '22023', 'diga qué es');
  perform pg_temp.err('05.08 hora de detección en el futuro', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, jsonb_build_object('t_detectado', pg_temp.iso('10 minutes')))), '22023', 'futuro');
  perform pg_temp.err('05.09 detección de hace más de 7 días', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, jsonb_build_object('t_detectado', pg_temp.iso('-8 days')))), '22023', '7 días');
  perform pg_temp.err('05.10 inicio del daño después de la detección', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, jsonb_build_object('t_inicio_dano', pg_temp.iso('-1 hour')))), '22023', 'inicio del daño');
  perform pg_temp.err('05.11 restablecido sin inicio de la reparación', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, jsonb_build_object('t_restablecido', pg_temp.iso('-1 hour')))), '22023', 'inicio de la reparación');
  perform pg_temp.err('05.12 restablecido antes del inicio de la reparación', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id,
     pg_temp.datos(v_ruta, jsonb_build_object('t_inicio_reparacion', pg_temp.iso('-30 minutes'), 't_restablecido', pg_temp.iso('-60 minutes')))), '22023');
  perform pg_temp.err('05.13 hora mal escrita', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"t_detectado": "ayer a las 3"}')), '22023', 'forma esperada');
  perform pg_temp.err('05.14 rotura en un tipo que no la lleva', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"tipo": "hundimiento"}')), '22023', 'rotura');
  perform pg_temp.err('05.15 sin riesgo', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"riesgo": null}')), '22023', 'riesgo');
  perform pg_temp.err('05.16 marca de riesgo que no existe', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"marcas": ["inventada"]}')), '22023', 'marca');
  perform pg_temp.err('05.17 causa propia sin la causa', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"causa": null}')), '22023', 'causa propia');
  perform pg_temp.err('05.18 causa de terceros sin quién', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"causa_clase": "terceros"}')), '22023', 'quién lo causó');
  perform pg_temp.err('05.19 sin fotos', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id, pg_temp.datos(v_ruta, '{"fotos": []}')), '22023', 'fotos');
  perform pg_temp.err('05.20 sin foto del daño (solo entorno)', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id,
     pg_temp.datos(v_ruta, jsonb_build_object('fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'entorno', 'ruta', v_ruta))))), '22023', 'foto del daño');
  perform pg_temp.err('05.21 foto que no se subió', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id,
     pg_temp.datos(v_ruta, jsonb_build_object('fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_ruta), jsonb_build_object('n', 2, 'momento', 'entorno', 'ruta', v_p -> 'fotos' -> 1 ->> 'ruta'))))), '22023', 'No se encontró la foto 2');
  perform pg_temp.foto(v_p -> 'fotos' -> 1 ->> 'ruta', 2000000);
  perform pg_temp.err('05.22 foto de más de 1,5 MB', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id,
     pg_temp.datos(v_ruta, jsonb_build_object('fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_ruta), jsonb_build_object('n', 2, 'momento', 'entorno', 'ruta', v_p -> 'fotos' -> 1 ->> 'ruta'))))), '22023', 'pesa más');
  perform pg_temp.err('05.23 ruta de otro daño', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id,
     pg_temp.datos('danos/2026-11/00000000-0000-4000-8000-000000000000/1.jpg')), '22023', 'no corresponde');
  perform pg_temp.err('05.24 formulario abierto hace más de 12 horas', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, op, v_id,
     pg_temp.datos(v_ruta, jsonb_build_object('inicio_dispositivo', pg_temp.iso('-13 hours')))), '22023', '12 horas');
  perform pg_temp.err('05.25 operador sin el formulario asignado no crea', format($$select public.geoportal_redes_crear_dano(%L, %L, %L)$$, sf, v_id, pg_temp.datos(v_ruta)), '42501');
  perform pg_temp.reg('05.26 ninguna validación dejó nada', not exists (select 1 from redes.danos) and (select ultimo from redes.consecutivos where prefijo = 'DAN') = 0);

  -- ---------- 06 Crear: los buenos ----------
  v_r := public.geoportal_redes_crear_dano(op, v_id, pg_temp.datos(v_ruta, jsonb_build_object('causa_clase', 'terceros', 'causa', null, 'tercero_tipo', 'vehiculo', 'tercero_nombre', 'Placa ZTX123',
            'inicio_dispositivo', pg_temp.iso('-20 minutes'), 'presion_mca', 25)), '10.0.0.1');
  perform pg_temp.reg('06.01 se guarda DAN-000001, reportado, sobre RED-000001', v_r ->> 'codigo' = 'DAN-000001' and v_r ->> 'estado' = 'reportado' and v_r ->> 'activo' = 'RED-000001'
     and not (v_r ->> 'repetido')::boolean and v_r ->> 'perdida_estado' = 'sin_tabla', v_r::text);
  perform pg_temp.reg('06.02 la placa del tercero va SOLO a dano_datos_sensibles (ni en el daño ni en la auditoría)',
     (select tercero_nombre from redes.dano_datos_sensibles where dano_id = v_id) = 'Placa ZTX123'
     and not exists (select 1 from public.geoportal_auditoria where accion = 'redes_crear_dano' and detalle::text like '%ZTX123%')
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_crear_dano' and referencia = 'DAN-000001' and ip = '10.0.0.1'));
  perform pg_temp.reg('06.03 la foto queda con su tamaño y tipo leídos de Storage', (select bytes || '/' || mime || '/' || momento from redes.dano_fotos where dano_id = v_id) = '300000/image/jpeg/dano');
  perform pg_temp.reg('06.04 hora de apertura del celular guardada', (select inicio_origen from redes.danos where id = v_id) = 'dispositivo');
  v_x := public.geoportal_redes_crear_dano(op, v_id, pg_temp.datos(v_ruta));
  perform pg_temp.reg('06.05 reenviar el mismo id devuelve lo guardado («repetido»), sin otro código', v_x ->> 'codigo' = 'DAN-000001' and (v_x ->> 'repetido')::boolean and (select count(*) from redes.danos) = 1);
  -- con la reparación completa (atendido) y «no identificado»
  v_p := public.geoportal_redes_preparar_dano(sv, 1); v_id2 := (v_p ->> 'dano_id')::uuid; perform pg_temp.foto(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_r := public.geoportal_redes_crear_dano(sv, v_id2, pg_temp.datos(v_p -> 'fotos' -> 0 ->> 'ruta', jsonb_build_object(
            't_inicio_dano', pg_temp.iso('-6 hours'), 't_detectado', pg_temp.iso('-5 hours'), 't_inicio_reparacion', pg_temp.iso('-4 hours'), 't_restablecido', pg_temp.iso('-1 hours'))));
  perform pg_temp.reg('06.06 con la reparación completa queda «atendido» y los tiempos salen solos (1 h, 3 h y 5 h)', v_r ->> 'estado' = 'atendido'
     and (v_r ->> 'respuesta_s')::integer between 3590 and 3610 and (v_r ->> 'reparacion_s')::integer between 10790 and 10810 and (v_r ->> 'total_s')::integer between 17990 and 18010, v_r::text);
  v_p := public.geoportal_redes_preparar_dano(op, 1); v_id3 := (v_p ->> 'dano_id')::uuid; perform pg_temp.foto(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_r := public.geoportal_redes_crear_dano(op, v_id3, pg_temp.datos(v_p -> 'fotos' -> 0 ->> 'ruta', jsonb_build_object('activo', null, 'no_identificado', 'Tubo que no sale en el mapa',
            'sistema', 'alcantarillado', 'tipo', 'rebose', 'tipo_rotura', null, 'ubicacion_origen', 'mapa', 'lat', 4.6, 'lon', -74.08, 't_inicio_reparacion', pg_temp.iso('-1 hour'))));
  perform pg_temp.reg('06.07 «no identificado», en alcantarillado, fuera de Valledupar: se guarda con marca y queda «en atención»', v_r ->> 'codigo' = 'DAN-000003' and v_r -> 'activo' = 'null'::jsonb
     and (v_r ->> 'fuera_de_zona')::boolean and v_r ->> 'estado' = 'en_atencion', v_r::text);

  -- ---------- 07 Epicrisis y ficha ----------
  v_r := public.geoportal_redes_epicrisis(op, 'RED-000001');
  perform pg_temp.reg('07.01 la epicrisis de RED-000001 trae los 2 daños como «hecho», del más reciente al más antiguo', (select count(*) from jsonb_array_elements(v_r -> 'items') i where i ->> 'grupo' = 'hecho') = 2
     and exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ->> 'clase' = 'dano' and i ->> 'resumen' like 'DAN-000001 · Fuga o tubería rota · Rotura parcial · riesgo medio · causa de terceros%' and i ->> 'estado' = 'Reportado')
     and exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ->> 'resumen' like 'DAN-000002 %duración 5 h 00 min%' and i ->> 'estado' = 'Atendido'), v_r::text);
  perform pg_temp.reg('07.02 la epicrisis nunca trae la placa del tercero; el operador no ve autores', v_r::text not like '%ZTX123%' and not exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ? 'autor'));
  v_r := public.geoportal_redes_activo(op, 'RED-000001');
  perform pg_temp.reg('07.03 la ficha cuenta 2 hechos y 2 daños en 12 meses', (v_r -> 'epicrisis' ->> 'hechos')::integer = 2 and (v_r -> 'epicrisis' ->> 'danos_12_meses')::integer = 2, (v_r -> 'epicrisis')::text);
  perform pg_temp.reg('07.04 el daño no identificado no está en ninguna epicrisis', not exists (select 1 from redes.v_epicrisis where ref_id = 3 and clase = 'dano'));
  perform pg_temp.reg('07.05 la epicrisis sigue con lo del 1a (las altas)', exists (select 1 from redes.v_epicrisis e join redes.activos x on x.id = e.activo_id where x.codigo = 'RED-000001' and e.clase = 'alta'));

  -- ---------- 08 Pérdida estimada ----------
  insert into redes.caudales_fuga (diametro_min_mm, diametro_max_mm, tipo_rotura, caudal_lps, fuente, autor) values (50, 100, 'parcial', 2.5, 'Prueba (no es la tabla de Técnica)', a);
  select row_to_json(x)::jsonb into v_r from redes.v_dano x where id = v_id2;
  perform pg_temp.reg('08.01 con fila en caudales_fuga: pérdida = 2,5 L/s × 5 h = 45 m³ (diámetro 76 mm, sin presión)', v_r ->> 'perdida_estado' = 'calculada' and (v_r ->> 'perdida_m3')::numeric between 44.9 and 45.1, v_r::text);
  select row_to_json(x)::jsonb into v_r from redes.v_dano x where id = v_id;
  perform pg_temp.reg('08.02 la fila sin rango de presión vale para cualquier presión (25 m.c.a.); abierto, la pérdida corre con el total', v_r ->> 'perdida_estado' = 'calculada' and (v_r ->> 'perdida_m3')::numeric > 0 and (v_r ->> 'total_corre')::boolean, v_r::text);
  insert into redes.caudales_fuga (diametro_min_mm, diametro_max_mm, tipo_rotura, presion_min_mca, presion_max_mca, caudal_lps, fuente, autor) values (200, 300, 'total', 10, 20, 9, 'Prueba', a);
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, tipo_rotura, riesgo, causa_clase, autor)
  select '00000000-0000-4000-8000-0000000000aa', 'DAN-900001', 'dano', 'fuga', 'acueducto', id, 10.47, -73.24, 'gps', now() - interval '1 hour', 'total', 'bajo', 'desconocida', a from redes.activos where codigo = 'RED-000002';
  perform pg_temp.reg('08.02b rotura total en 76 mm: no hay fila para ese diámetro y rotura → «sin_fila» y pérdida nula (no se inventa)',
     exists (select 1 from redes.v_dano where codigo = 'DAN-900001' and perdida_estado = 'sin_fila' and perdida_m3 is null));
  select row_to_json(x)::jsonb into v_r from redes.v_dano x where id = v_id3;
  perform pg_temp.reg('08.03 sin rotura (rebose): la pérdida «no aplica»', v_r ->> 'perdida_estado' = 'no_aplica');

  -- ---------- 09 Minimapa ----------
  v_r := public.geoportal_redes_activo_buscar(op, 'red-00', 'acueducto');
  perform pg_temp.reg('09.01 buscar «red-00» en acueducto: RED-000001 y RED-000002, con lat y lon', jsonb_array_length(v_r -> 'activos') = 2 and v_r -> 'activos' -> 0 ->> 'codigo' = 'RED-000001' and (v_r -> 'activos' -> 0 ->> 'lat') is not null, v_r::text);
  perform pg_temp.reg('09.02 buscar por el código de la capa (V991) y por el pozo en alcantarillado', public.geoportal_redes_activo_buscar(op, 'v991') -> 'activos' -> 0 ->> 'codigo' = 'VAL-000001'
     and (select array_agg(x ->> 'codigo' order by x ->> 'codigo') from jsonb_array_elements(public.geoportal_redes_activo_buscar(op, 'ZT2-P', 'alcantarillado') -> 'activos') x) = array['COL-000001', 'POZ-000001', 'POZ-000002']);
  perform pg_temp.err('09.03 buscar con 1 letra', format($$select public.geoportal_redes_activo_buscar(%L, 'r')$$, op), '22023');
  v_r := public.geoportal_redes_tramo_nodos(op, 'RED-000001');
  perform pg_temp.reg('09.04 nodos del tramo RED-000001: desde V991 (VAL-000001) hasta Tee-991 (ACC-000001), con posición', jsonb_array_length(v_r -> 'nodos') = 2
     and v_r -> 'nodos' -> 0 ->> 'rol' = 'inicio' and v_r -> 'nodos' -> 0 ->> 'nombre' = 'V991' and v_r -> 'nodos' -> 0 -> 'activo' ->> 'codigo' = 'VAL-000001'
     and v_r -> 'nodos' -> 1 -> 'activo' ->> 'codigo' = 'ACC-000001' and (v_r -> 'nodos' -> 1 ->> 'lat') is not null, v_r::text);
  perform pg_temp.err('09.05 nodos de algo que no es un tramo', format($$select public.geoportal_redes_tramo_nodos(%L, 'VAL-000001')$$, op), '22023', 'no es un tramo');
  v_t := pg_temp.tesela(17, -73.2395, 10.4700);
  v_s := public.geoportal_redes_mvt(op, v_t[1], v_t[2], v_t[3], 'acueducto');
  perform pg_temp.reg('09.06 tesela z17 de acueducto sobre la red de prueba: trae datos (MVT en base64)', length(v_s) > 50 and length(decode(v_s, 'base64')) > 30, length(v_s)::text);
  v_t := pg_temp.tesela(14, -73.2395, 10.4700);
  perform pg_temp.reg('09.07 bajo el zoom 15 la tesela viene vacía', public.geoportal_redes_mvt(op, v_t[1], v_t[2], v_t[3], 'acueducto') = '');
  v_t := pg_temp.tesela(16, -73.2395, 10.4700);
  perform pg_temp.reg('09.08 a z16 hay red pero no accesorios; a z17 sí (la tesela crece)',
     length(public.geoportal_redes_mvt(op, v_t[1], v_t[2], v_t[3], 'acueducto')) > 50
     and position('ACC'::bytea in decode(public.geoportal_redes_mvt(op, v_t[1], v_t[2], v_t[3], 'acueducto'), 'base64')) = 0
     and position('ACC'::bytea in decode(public.geoportal_redes_mvt(op, (pg_temp.tesela(17, -73.2391, 10.4700))[1], (pg_temp.tesela(17, -73.2391, 10.4700))[2], (pg_temp.tesela(17, -73.2391, 10.4700))[3], 'acueducto'), 'base64')) > 0);
  perform pg_temp.reg('09.09 la tesela de alcantarillado no trae acueducto', position('RED-'::bytea in decode(public.geoportal_redes_mvt(op, (pg_temp.tesela(17, -73.2395, 10.4727))[1],
       (pg_temp.tesela(17, -73.2395, 10.4727))[2], (pg_temp.tesela(17, -73.2395, 10.4727))[3], 'alcantarillado'), 'base64')) = 0
     and position('POZ-'::bytea in decode(public.geoportal_redes_mvt(op, (pg_temp.tesela(17, -73.2395, 10.4727))[1], (pg_temp.tesela(17, -73.2395, 10.4727))[2], (pg_temp.tesela(17, -73.2395, 10.4727))[3], 'alcantarillado'), 'base64')) > 0);
  perform pg_temp.err('09.10 tesela sin Técnica: 42501', format($$select public.geoportal_redes_mvt(%L, 17, 1, 1, 'acueducto')$$, na), '42501');
  perform pg_temp.err('09.11 tesela fuera de rango', format($$select public.geoportal_redes_mvt(%L, 3, 9, 0, 'acueducto')$$, op), '22023');

  -- ---------- 10 Reportes del bot (N-14) ----------
  perform pg_temp.err('10.01 el bot no puede mandar el nombre ni el teléfono de quien reporta',
     $$select redes.f_reporte_externo_recibir('{"radicado": "ZT-0001", "canal": "telegram", "tipo": "Fuga", "lat": 10.47, "lon": -73.2395, "telefono": "3000000000"}')$$, '22023', 'datos personales');
  v_rep := redes.f_reporte_externo_recibir(jsonb_build_object('radicado', 'ZT-0001', 'canal', 'telegram', 'tipo', 'Fuga en la calle', 'lat', 10.47, 'lon', -73.2396, 'descripcion', 'Sale agua del andén',
            'recibido_en', pg_temp.iso('-3 hours')));
  perform pg_temp.reg('10.02 recibir es idempotente por canal y radicado; estado «recibido»',
     redes.f_reporte_externo_recibir('{"radicado": "ZT-0001", "canal": "telegram", "tipo": "Fuga en la calle", "lat": 10.47, "lon": -73.2396}') = v_rep
     and (select estado_bot from redes.v_reporte_externo where id = v_rep) = 'recibido' and (select count(*) from redes.reportes_externos) = 1);
  perform pg_temp.reg('10.03 la tabla de reportes no tiene columnas de nombre ni de teléfono', not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'reportes_externos'
     and column_name ~ '(nombre|telefono|celular|cedula|correo|email)'));
  perform pg_temp.err('10.04 el operador no convierte reportes', format($$select public.geoportal_redes_reporte_convertir(%L, %L, '{"clase": "dano", "tipo": "fuga", "sistema": "acueducto", "riesgo": "medio"}')$$, op, v_rep), '42501');
  v_r := public.geoportal_redes_reporte_convertir(sv, v_rep, '{"clase": "dano", "tipo": "fuga", "sistema": "acueducto", "activo": "RED-000001", "riesgo": "alto"}');
  perform pg_temp.reg('10.05 el supervisor lo convierte: DAN-000004 enlazado al radicado, origen bot, en atención para el bot', v_r ->> 'dano_codigo' = 'DAN-000004' and v_r ->> 'estado_bot' = 'en_atencion'
     and exists (select 1 from redes.v_dano where codigo = 'DAN-000004' and origen = 'bot' and reporte_externo_id = v_rep and ubicacion_origen = 'bot' and autor = sv and descripcion like 'Reporte del bot ZT-0001%')
     and (select estado_bot from redes.v_reporte_externo where id = v_rep) = 'en_atencion', v_r::text);
  perform pg_temp.err('10.06 convertir dos veces', format($$select public.geoportal_redes_reporte_convertir(%L, %L, '{"clase": "dano", "tipo": "fuga", "sistema": "acueducto", "riesgo": "medio"}')$$, sv, v_rep), '22023', 'ya está convertido');
  insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor) select id, clock_timestamp() - interval '1 hour', clock_timestamp(), 'supervisor', sv from redes.danos where codigo = 'DAN-000004';
  perform pg_temp.reg('10.07 cuando el daño queda atendido, el bot recibe «atendido»', (select estado_bot from redes.v_reporte_externo where id = v_rep) = 'atendido');
  v_rep2 := redes.f_reporte_externo_recibir('{"radicado": "ZT-0002", "canal": "whatsapp", "tipo": "Alcantarilla", "direccion": "Calle 1 # 2-3"}');
  perform pg_temp.err('10.08 un reporte sin ubicación y sin activo no se puede convertir', format($$select public.geoportal_redes_reporte_convertir(%L, %L, '{"clase": "dano", "tipo": "rebose", "sistema": "alcantarillado", "riesgo": "bajo"}')$$, sv, v_rep2), '22023', 'ubicación');
  v_r := public.geoportal_redes_reporte_convertir(a, v_rep2, '{"clase": "dano", "tipo": "rebose", "sistema": "alcantarillado", "activo": "POZ-000002", "riesgo": "bajo"}');
  perform pg_temp.reg('10.09 sin ubicación, con el activo: el daño toma la posición del pozo', exists (select 1 from redes.danos d where d.codigo = v_r ->> 'dano_codigo' and d.ubicacion_origen = 'activo'
     and ST_DWithin(d.geom::geography, (select geom from redes.activo_vigente_mat where codigo = 'POZ-000002')::geography, 0.2)));
  v_rep3 := redes.f_reporte_externo_recibir('{"radicado": "ZT-0003", "canal": "telegram", "tipo": "Otro", "lat": 10.47, "lon": -73.2396}');
  perform pg_temp.err('10.10 descartar sin motivo suficiente', format($$select public.geoportal_redes_reporte_descartar(%L, %L, 'no')$$, sv, v_rep3), '22023', 'motivo');
  v_r := public.geoportal_redes_reporte_descartar(sv, v_rep3, 'Es un reporte repetido de la misma fuga');
  perform pg_temp.reg('10.11 descartar con motivo: el bot recibe «descartado»; no se puede convertir después', v_r ->> 'estado_bot' = 'descartado' and (select estado_bot from redes.v_reporte_externo where id = v_rep3) = 'descartado');
  perform pg_temp.err('10.12 convertir un descartado', format($$select public.geoportal_redes_reporte_convertir(%L, %L, '{"clase": "dano", "tipo": "fuga", "sistema": "acueducto", "riesgo": "medio", "activo": "RED-000001"}')$$, sv, v_rep3), '22023', 'descartado');

  -- ---------- 11 Hechos de solo inserción ----------
  perform pg_temp.err('11.01 un daño no se cambia', $$update redes.danos set riesgo = 'bajo'$$, '42501');
  perform pg_temp.err('11.02 una foto no se borra', $$delete from redes.dano_fotos$$, '42501');
  perform pg_temp.err('11.03 los datos sensibles no se vacían', $$truncate redes.dano_datos_sensibles$$, '42501');
  perform pg_temp.err('11.04 los eventos del bot no se cambian', $$update redes.reporte_externo_eventos set tipo = 'recibido'$$, '42501');
  perform pg_temp.err('11.05 el tipo de daño debe aplicar al sistema también por la regla de la tabla', $$insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor)
       select gen_random_uuid(), 'DAN-999999', 'dano', 'rebose', 'acueducto', id, 10.47, -73.24, 'gps', now(), 'bajo', 'desconocida', 'x' from redes.activos where codigo = 'RED-000001'$$, '23514');

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 2 (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
