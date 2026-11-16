-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 25, 30 y 40, en la misma transacción.
-- Como las del 3a: corre después de la carga real y de los cortes publicados; NO supone códigos ni conteos de la base. Arma su red de prueba
-- (ID 99400xx, LABEL ZT4-…) con el motor del 1a y toma sus códigos por la llave. Al publicarla, lo real de esas capas queda «retirado» dentro de la
-- transacción, que se deshace al final con un ERROR a propósito que trae el informe.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 3b … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
  a text := 'prueba.redes4.adm@emdupar.gov.co'; sv text := 'prueba.redes4.sup@emdupar.gov.co'; op text := 'prueba.redes4.op@emdupar.gov.co';
  sf text := 'prueba.redes4.sinform@emdupar.gov.co'; na text := 'prueba.redes4.nada@emdupar.gov.co';
  v_red1 text; v_red2 text; v_val text; v_acc text; v_tor text; v_poz1 text; v_poz2 text; v_col text;
  v_c bigint; v_r jsonb; v_x jsonb; v_p jsonb; v_ruta text; v_tes0 integer; v_ver0 integer; v_ed0 bigint; v_d text; v_i text;
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

  -- red de prueba con el motor del 1a: 2 tramos de acueducto (V994 → Tee-994 → Torre-994) y 2 pozos con un conducto
  v_c := (public.geoportal_redes_carga_iniciar(a, 'acueducto', pg_temp.sha('zt4-acu'), 'shp', 4326, 'ID', 2) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    pg_temp.tramo(1, 9940001, 'Distribucion-ZT41', '99401', 'V994', '99402', 'Tee-994', w1), pg_temp.tramo(2, 9940002, 'Lateral-ZT42', '99402', 'Tee-994', '99403', 'Torre-994', w2)));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Red de prueba del Corte 3b');
  v_c := (public.geoportal_redes_carga_iniciar(a, 'alc_pozos', pg_temp.sha('zt4-poz'), 'shp', 4326, 'LABEL', 2) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    jsonb_build_object('orden', 1, 'wkt', 'POINT(' || pg_temp.p(0, 300) || ')', 'atributos', jsonb_build_object('LABEL', 'ZT4-PA', 'EST_POZO', 'VISIBLE', 'ESTADO', 'Existente', 'C_RASANTE', 100, 'C_FONDO', 98)),
    jsonb_build_object('orden', 2, 'wkt', 'POINT(' || pg_temp.p(100, 300) || ')', 'atributos', jsonb_build_object('LABEL', 'ZT4-PB', 'EST_POZO', 'VISIBLE', 'ESTADO', 'Existente', 'C_RASANTE', 100, 'C_FONDO', 97))));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Pozos de prueba del Corte 3b');
  v_c := (public.geoportal_redes_carga_iniciar(a, 'alc_conductos', pg_temp.sha('zt4-con'), 'shp', 4326, 'LABEL', 1) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(jsonb_build_object('orden', 1, 'wkt', 'LINESTRING(' || pg_temp.p(0, 300) || ',' || pg_temp.p(100, 300) || ')',
    'atributos', jsonb_build_object('LABEL', 'ZT4-PA-PB', 'PZ_INICIAL', 'ZT4-PA', 'PZ_FINAL', 'ZT4-PB', 'MATERIAL', 'PVC', 'DIAMETRO', 200, 'ESTADO', 'Existente'))));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Conducto de prueba del Corte 3b');
  select codigo into v_red1 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9940001';
  select codigo into v_red2 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9940002';
  select codigo into v_val from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99401';
  select codigo into v_acc from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99402';
  select codigo into v_tor from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99403';
  select codigo into v_poz1 from redes.v_activo_vigente where capa_codigo = 'alc_pozos' and llave_capa = 'ZT4-PA';
  select codigo into v_poz2 from redes.v_activo_vigente where capa_codigo = 'alc_pozos' and llave_capa = 'ZT4-PB';
  select codigo into v_col from redes.v_activo_vigente where capa_codigo = 'alc_conductos' and llave_capa = 'ZT4-PA-PB';
  perform set_config('zt.red1', v_red1, true);
  perform pg_temp.reg('00.01 red de prueba: 2 RED, VAL, ACC, TOR, 2 POZ y COL, encontrados por su llave',
     v_red1 like 'RED-%' and v_red2 like 'RED-%' and v_val like 'VAL-%' and v_acc like 'ACC-%' and v_tor like 'TOR-%' and v_poz1 like 'POZ-%' and v_poz2 like 'POZ-%' and v_col like 'COL-%'
     and (select count(*) from redes.activo_vigente_mat where codigo in (v_red1, v_red2, v_val, v_acc, v_tor, v_poz1, v_poz2, v_col) and not retirado) = 8,
     concat_ws(' ', v_red1, v_red2, v_val, v_acc, v_tor, v_poz1, v_poz2, v_col));
  select version into v_tes0 from redes.tesela_version where sistema = 'acueducto';
  select version into v_ver0 from redes.v_activo_vigente where codigo = v_red1;

  -- ---------- 01 Permisos ----------
  perform pg_temp.reg('01.01 ningún privilegio de la API sobre las tablas y vistas; RLS activa en todas',
     not exists (select 1 from pg_class c cross join (values ('anon'), ('authenticated'), ('service_role')) r(rol)
                  where c.relnamespace = 'redes'::regnamespace and c.relkind in ('r', 'v', 'S') and (has_table_privilege(r.rol, c.oid, 'select') or has_table_privilege(r.rol, c.oid, 'insert')))
     and not exists (select 1 from pg_class where relnamespace = 'redes'::regnamespace and relkind = 'r' and not relrowsecurity));
  perform pg_temp.reg('01.02 las 5 RPC nuevas y activo_buscar: security definer, search_path fijo y solo service_role', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('geoportal_redes_perfil', 'geoportal_redes_galeria', 'geoportal_redes_ficha_editar', 'geoportal_redes_foto_perfil_preparar', 'geoportal_redes_foto_perfil_fijar', 'geoportal_redes_activo_buscar')
       and p.prosecdef and p.proconfig is not null and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
       and not has_function_privilege('authenticated', p.oid, 'execute') and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 6);
  perform pg_temp.reg('01.03 las funciones internas (editor, fotos, textos) no las ejecuta la API',
     not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname in ('f_editor_ficha', 'f_fotos_activo', 'f_foto_principal', 'f_texto_valor')
                  and (has_function_privilege('service_role', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));

  -- ---------- 02 Perfil ----------
  v_r := public.geoportal_redes_perfil(op, v_red1);
  perform pg_temp.reg('02.01 el operador lee el perfil sin la foto principal, sin el conteo de fotos y sin la edición', v_r ->> 'codigo' = v_red1 and v_r ->> 'perfil' = 'operador'
     and not v_r ? 'foto_principal' and not v_r ? 'fotos' and not v_r ? 'edicion' and not (v_r ->> 'editable')::boolean, v_r::text);
  v_r := public.geoportal_redes_perfil(sv, v_red1);
  perform pg_temp.reg('02.02 el supervisor ve el conteo de fotos (0) pero no edita (por ahora solo el administrador, §23)', (v_r ->> 'fotos')::integer = 0 and not (v_r ->> 'editable')::boolean and not v_r ? 'edicion', v_r::text);
  v_r := public.geoportal_redes_perfil(a, v_val);
  perform pg_temp.reg('02.03 el administrador edita: valores actuales, estados, materiales, las clases de la válvula y que lleva efecto', (v_r ->> 'editable')::boolean
     and v_r -> 'edicion' -> 'valores' ->> 'clase' = 'cierre' and jsonb_array_length(v_r -> 'edicion' -> 'clases') = 5 and (v_r -> 'edicion' -> 'lleva' ->> 'efecto')::boolean
     and jsonb_array_length(v_r -> 'edicion' -> 'estados') >= 8, left(v_r::text, 400));
  perform pg_temp.reg('02.04 los campos del pozo que van en atributos (estado del pozo, de la tapa…) salen para editar; la profundidad no (es columna)',
     exists (select 1 from jsonb_array_elements(public.geoportal_redes_perfil(a, v_poz1) -> 'edicion' -> 'campos_tipo') x where x ->> 'clave' = 'estado_pozo')
     and not exists (select 1 from jsonb_array_elements(public.geoportal_redes_perfil(a, v_poz1) -> 'edicion' -> 'campos_tipo') x where x ->> 'clave' = 'profundidad_m'));
  perform pg_temp.err('02.05 sin Técnica no lee el perfil', format($$select public.geoportal_redes_perfil(%L, %L)$$, na, v_red1), '42501');

  -- ---------- 03 Editar: quién y validaciones ----------
  perform pg_temp.err('03.01 el operador no edita', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"nombre": "x"}', 'Prueba del operador')$$, op, v_red1), '42501');
  perform pg_temp.err('03.02 el supervisor tampoco, por ahora (desde el Corte 4)', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"nombre": "x"}', 'Prueba del supervisor')$$, sv, v_red1), '42501', 'solo el administrador');
  perform pg_temp.err('03.03 sin motivo', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"nombre": "Tramo"}', 'ok')$$, a, v_red1), '22023', 'motivo');
  perform pg_temp.err('03.04 sin cambios', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{}', 'Revisión sin cambios')$$, a, v_red1), '22023', 'No hay cambios');
  perform pg_temp.err('03.05 un campo que no se edita (la geometría)', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"geom": "POINT(0 0)"}', 'Mover el tramo de lugar')$$, a, v_red1), '22023', 'no se edita');
  perform pg_temp.err('03.06 un estado que no existe', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"estado_codigo": "roto"}', 'Cambio de estado')$$, a, v_red1), '22023', 'estado');
  perform pg_temp.err('03.07 la clase de la válvula es obligatoria', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"clase": null}', 'Quitar la clase')$$, a, v_val), '22023', 'obligatoria');
  perform pg_temp.err('03.08 el efecto solo en válvulas', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"efecto": "cierra"}', 'Efecto en un tubo')$$, a, v_red1), '22023', 'solo aplica');
  perform pg_temp.err('03.09 diámetro 0', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"diametro_mm": 0}', 'Diámetro corregido')$$, a, v_red1), '22023', 'diámetro');
  perform pg_temp.err('03.10 fecha de instalación futura', format($$select public.geoportal_redes_ficha_editar(%L, %L, %L, 'Fecha corregida')$$, a, v_red1,
     jsonb_build_object('fecha_instalacion', (current_date + 10)::text)), '22023', 'fecha de instalación');
  perform pg_temp.err('03.11 un campo de atributos que no es del tipo', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"atributos": {"estado_pozo": "x"}}', 'Campo de otro tipo')$$, a, v_red1), '22023', 'no es un campo');
  perform pg_temp.err('03.12 placa con símbolos', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"placa": "INV#1!"}', 'Placa del almacén')$$, a, v_val), '22023', 'placa');
  perform pg_temp.err('03.13 los mismos valores: no hay cambios', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"clase": "cierre"}', 'Revisión de la clase')$$, a, v_val), '22023', 'los mismos de la ficha');
  perform pg_temp.err('03.14 origen tercero sin aportante', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"origen": {"origen": "tercero"}}', 'Lo entregó un tercero')$$, a, v_red2), '22023', 'aportante');
  perform pg_temp.reg('03.15 ninguna validación dejó nada', not exists (select 1 from redes.ficha_ediciones) and (select version from redes.v_activo_vigente where codigo = v_red1) = v_ver0);

  -- ---------- 04 Editar: los buenos ----------
  v_r := public.geoportal_redes_ficha_editar(a, lower(v_red1), '{"diametro_mm": 110, "material_codigo": "HD", "estado_codigo": "por_reemplazar", "observaciones": "Tubo con fugas repetidas", "fecha_instalacion": "1998-05-20"}',
            'Revisión en campo del 15-nov: es hierro dúctil');
  select row_to_json(x)::jsonb into v_x from redes.v_activo_vigente x where codigo = v_red1;
  perform pg_temp.reg('04.01 editar datos crea una versión nueva (sin carga), vigente, con los valores y la huella nueva', (v_r ->> 'version_nueva')::boolean
     and (v_x ->> 'version')::integer = v_ver0 + 1 and v_x ->> 'carga_id' is null and (v_x ->> 'diametro_mm')::numeric = 110 and v_x ->> 'material_codigo' = 'HD'
     and v_x ->> 'estado_codigo' = 'por_reemplazar' and v_x -> 'atributos' ->> 'observaciones' = 'Tubo con fugas repetidas' and v_x ->> 'fecha_instalacion' = '1998-05-20'
     and v_x -> 'atributos' ? 'modelo' and (select count(*) from redes.activo_versiones v join redes.activos x on x.id = v.activo_id where x.codigo = v_red1) = v_ver0 + 1, v_x::text);
  perform pg_temp.reg('04.02 la versión anterior sigue ahí (nada se sobrescribe)', exists (select 1 from redes.activo_versiones v join redes.activos x on x.id = v.activo_id
     where x.codigo = v_red1 and v.version = v_ver0 and v.material_codigo = 'PVC'));
  perform pg_temp.reg('04.03 la edición guarda qué cambió, de A a B (con nombres), el motivo y el autor',
     (select string_agg(c ->> 'rotulo' || '=' || coalesce(c ->> 'antes', '∅') || '>' || coalesce(c ->> 'despues', '∅'), '|' order by o) from redes.ficha_ediciones f, jsonb_array_elements(f.cambios) with ordinality y(c, o)
       where f.id = (v_r ->> 'edicion')::bigint) = 'Estado=En operación>Por reemplazar|Material=PVC>Hierro dúctil|Diámetro (mm)=76>110|Fecha de instalación=∅>20/05/1998|Observaciones=∅>Tubo con fugas repetidas'
     and exists (select 1 from redes.ficha_ediciones where id = (v_r ->> 'edicion')::bigint and autor = a and motivo like 'Revisión en campo%' and version = v_ver0 + 1),
     (select cambios::text from redes.ficha_ediciones where id = (v_r ->> 'edicion')::bigint));
  perform pg_temp.reg('04.04 la tabla vigente se refresca sola (punteado por «por reemplazar») y la tesela sube de versión', exists (select 1 from redes.activo_vigente_mat where codigo = v_red1
     and diametro_mm = 110 and punteado and estado_codigo = 'por_reemplazar') and (select version from redes.tesela_version where sistema = 'acueducto') > v_tes0);
  v_r := public.geoportal_redes_ficha_editar(a, v_val, '{"alias": "Válvula del parque ZT4", "placa": "INV-ZT4-0001"}', 'Placa del inventario de almacén');
  perform pg_temp.reg('04.05 alias y placa no crean versión: quedan como eventos con su edición', not (v_r ->> 'version_nueva')::boolean
     and (select alias || '|' || placa from redes.v_activo_identificadores i join redes.activos x on x.id = i.activo_id where x.codigo = v_val) = 'Válvula del parque ZT4|INV-ZT4-0001'
     and (select count(*) from redes.activo_identificador_eventos e join redes.activos x on x.id = e.activo_id where x.codigo = v_val) = 2, v_r::text);
  perform pg_temp.err('04.06 la placa no se repite en otro activo', format($$select public.geoportal_redes_ficha_editar(%L, %L, '{"placa": "inv-zt4-0001"}', 'Placa del almacén')$$, a, v_tor), '22023', 'ya la tiene otro activo (' || v_val || ')');
  perform pg_temp.reg('04.07 buscar por la placa (sin distinguir mayúsculas) y por el alias encuentra la válvula',
     public.geoportal_redes_activo_buscar(op, 'inv-zt4-0001') -> 'activos' -> 0 ->> 'codigo' = v_val and public.geoportal_redes_activo_buscar(op, 'inv-zt4-0001') -> 'activos' -> 0 ->> 'placa' = 'INV-ZT4-0001'
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_activo_buscar(op, 'parque zt4', 'acueducto') -> 'activos') x where x ->> 'codigo' = v_val and x ->> 'alias' = 'Válvula del parque ZT4'));
  perform pg_temp.reg('04.08 buscar por código sigue igual', public.geoportal_redes_activo_buscar(op, v_red2, 'acueducto') -> 'activos' -> 0 ->> 'codigo' = v_red2);
  v_r := public.geoportal_redes_ficha_editar(a, v_val, '{"alias": null}', 'El alias no corresponde');
  perform pg_temp.reg('04.09 quitar el alias: queda sin alias (evento con valor nulo) y la placa sigue', (select coalesce(alias, '∅') || '|' || placa from redes.v_activo_identificadores i join redes.activos x on x.id = i.activo_id
     where x.codigo = v_val) = '∅|INV-ZT4-0001' and public.geoportal_redes_perfil(op, v_val) ->> 'placa' = 'INV-ZT4-0001' and not public.geoportal_redes_perfil(op, v_val) ? 'alias');
  v_r := public.geoportal_redes_ficha_editar(a, v_red2, '{"origen": {"origen": "tercero", "aportante": "alcaldia", "nota": "Lo construyó la alcaldía en 2019"}}', 'Acta de entrega de la alcaldía');
  perform pg_temp.reg('04.10 corregir el origen (respuesta 3 de David): fila nueva en activo_origen, sin versión; el supervisor la ve y el operador no',
     not (v_r ->> 'version_nueva')::boolean and public.geoportal_redes_activo(sv, v_red2) -> 'origen' ->> 'origen' = 'tercero' and public.geoportal_redes_activo(sv, v_red2) -> 'origen' ->> 'aportante' = 'alcaldia'
     and public.geoportal_redes_activo(op, v_red2) -> 'origen' is null and v_r::text not like '%alcaldia%', v_r::text);
  v_r := public.geoportal_redes_ficha_editar(a, v_poz1, '{"atributos": {"estado_tapa": "Tapa rota"}, "profundidad_m": 2.4}', 'Inspección del pozo con la cuadrilla');
  perform pg_temp.reg('04.11 en el pozo: un campo del tipo (estado de la tapa, en atributos) y la profundidad (columna)', (select atributos ->> 'estado_tapa' || '|' || profundidad_m from redes.v_activo_vigente where codigo = v_poz1)
     = 'Tapa rota|2.4' and exists (select 1 from redes.ficha_ediciones f join redes.activos x on x.id = f.activo_id, jsonb_array_elements(f.cambios) c where x.codigo = v_poz1 and c ->> 'rotulo' = 'Estado de la tapa'));

  -- ---------- 05 Epicrisis como muro ----------
  v_r := public.geoportal_redes_epicrisis(op, v_red1);
  perform pg_temp.reg('05.01 la epicrisis del tramo trae el cambio de la ficha («de A a B» y el motivo) y no repite la versión',
     exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ->> 'clase' = 'ficha'
              and i ->> 'resumen' = 'Estado: de «En operación» a «Por reemplazar»; Material: de «PVC» a «Hierro dúctil»; Diámetro (mm): de «76» a «110»; Fecha de instalación: de «sin dato» a «20/05/1998»; Observaciones: de «sin dato» a «Tubo con fugas repetidas» · Revisión en campo del 15-nov: es hierro dúctil')
     and not exists (select 1 from jsonb_array_elements(v_r -> 'items') i where i ->> 'clase' = 'version'), v_r::text);
  perform pg_temp.reg('05.02 la corrección del origen sale sin valores ni motivo (eso solo lo ve el supervisor en la ficha)', exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_red2) -> 'items') i
     where i ->> 'clase' = 'ficha' and i ->> 'resumen' = 'Se corrigió el origen del activo') and public.geoportal_redes_epicrisis(op, v_red2)::text not like '%alcald%');
  perform pg_temp.reg('05.03 alias y placa en la epicrisis de la válvula', exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_val) -> 'items') i
     where i ->> 'resumen' like 'Alias: de «sin dato» a «Válvula del parque ZT4»; Placa o número de inventario: de «sin dato» a «INV-ZT4-0001» · Placa%'));

  -- ---------- 06 Foto principal y galería ----------
  perform pg_temp.err('06.01 el operador no sube la foto principal', format($$select public.geoportal_redes_foto_perfil_preparar(%L, %L)$$, op, v_tor), '42501');
  v_p := public.geoportal_redes_foto_perfil_preparar(a, v_tor); v_ruta := v_p ->> 'ruta';
  perform pg_temp.reg('06.02 preparar: ruta activos/AAAA-MM/<id del activo>/<uuid>.jpg', v_ruta ~ ('^activos/[0-9]{4}-[0-9]{2}/' || (select id from redes.activos where codigo = v_tor) || '/[0-9a-f-]{36}\.jpg$'), v_ruta);
  perform pg_temp.err('06.03 fijar sin haberla subido', format($$select public.geoportal_redes_foto_perfil_fijar(%L, %L, %L, 'Foto de la torre')$$, a, v_tor, v_ruta), '22023', 'No se encontró');
  perform pg_temp.archivo(v_ruta, 400000);
  perform pg_temp.err('06.04 fijar sin motivo', format($$select public.geoportal_redes_foto_perfil_fijar(%L, %L, %L, 'x')$$, a, v_tor, v_ruta), '22023', 'motivo');
  perform pg_temp.err('06.05 fijar en otro activo', format($$select public.geoportal_redes_foto_perfil_fijar(%L, %L, %L, 'Foto de la torre')$$, a, v_val, v_ruta), '22023', 'prepararse');
  v_r := public.geoportal_redes_foto_perfil_fijar(a, v_tor, v_ruta, 'Foto de la torre tomada en la visita');
  perform pg_temp.reg('06.06 fijar la foto: queda de perfil, con su edición («Nueva foto principal»); repetir no duplica', not (v_r ->> 'repetido')::boolean
     and (public.geoportal_redes_foto_perfil_fijar(a, v_tor, v_ruta, 'Foto de la torre tomada en la visita') ->> 'repetido')::boolean
     and (select count(*) from redes.activo_fotos_perfil f join redes.activos x on x.id = f.activo_id where x.codigo = v_tor) = 1
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_epicrisis(op, v_tor) -> 'items') i where i ->> 'resumen' = 'Nueva foto principal · Foto de la torre tomada en la visita'));
  v_p := public.geoportal_redes_foto_perfil_preparar(a, v_tor); perform pg_temp.archivo(v_p ->> 'ruta', 2000000);
  perform pg_temp.err('06.07 una foto de más de 1,5 MB', format($$select public.geoportal_redes_foto_perfil_fijar(%L, %L, %L, 'Foto grande de la torre')$$, a, v_tor, v_p ->> 'ruta'), '22023', 'pesa más');
  -- un daño y una intervención con fotos sobre el tramo 2 (con los formularios de los Cortes 2 y 3a)
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a), (op, 'asignar_formulario', 'mantenimiento', a);
  v_p := public.geoportal_redes_preparar_dano(op, 1); perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_d := public.geoportal_redes_crear_dano(op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', v_red2, 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(150),
            'ubicacion_origen', 'gps', 't_detectado', pg_temp.iso('-5 hours'), 'tipo_rotura', 'parcial', 'riesgo', 'medio', 'causa_clase', 'desconocida',
            'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta')))) ->> 'codigo';
  v_p := public.geoportal_redes_preparar_intervencion(op, 2, 0); perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta'); perform pg_temp.archivo(v_p -> 'fotos' -> 1 ->> 'ruta');
  v_i := public.geoportal_redes_crear_intervencion(op, (v_p ->> 'intervencion_id')::uuid, jsonb_build_object('nace_de', 'dano', 'dano', v_d, 'resuelve_dano', true, 'tipo', 'reparacion', 'sistema', 'acueducto',
            'activo', v_red2, 'lat', pg_temp.lat(0), 'lon', pg_temp.lon(150), 'ubicacion_origen', 'gps', 't_inicio', pg_temp.iso('-3 hours'), 't_fin', pg_temp.iso('-1 hours'),
            'descripcion', 'Reparación de prueba del Corte 3b', 'ejecutor', 'emdupar', 'fuentes', '[{"aportante": "emdupar"}]'::jsonb,
            'archivos', jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'antes', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('n', 2, 'clase', 'despues', 'ruta', v_p -> 'fotos' -> 1 ->> 'ruta')))) ->> 'codigo';
  perform pg_temp.err('06.08 el operador no ve la galería (las fotos de un daño de terceros pueden mostrar una placa)', format($$select public.geoportal_redes_galeria(%L, %L)$$, op, v_red2), '42501');
  v_r := public.geoportal_redes_galeria(sv, v_red2);
  perform pg_temp.reg('06.09 galería del tramo 2: la foto del daño y las 2 de la intervención; la principal es la de «después»', (v_r ->> 'total')::integer = 3
     and v_r -> 'principal' ->> 'origen' = 'intervencion' and v_r -> 'principal' ->> 'clase' = 'despues' and v_r -> 'principal' ->> 'codigo' = v_i
     and exists (select 1 from jsonb_array_elements(v_r -> 'fotos') f where f ->> 'origen' = 'dano' and f ->> 'codigo' = v_d), v_r::text);
  perform pg_temp.reg('06.10 la lectura de la galería queda auditada', exists (select 1 from public.geoportal_auditoria where accion = 'redes_galeria' and referencia = v_red2 and email = sv));
  perform pg_temp.reg('06.11 en la torre, la principal es la de perfil, y el perfil del supervisor la trae (el del operador no)', public.geoportal_redes_galeria(sv, v_tor) -> 'principal' ->> 'origen' = 'perfil'
     and public.geoportal_redes_perfil(sv, v_tor) -> 'foto_principal' ->> 'ruta' = v_ruta and not public.geoportal_redes_perfil(op, v_tor) ? 'foto_principal');
  perform pg_temp.reg('06.12 la válvula también intervenida no se suma a la galería si no hay intervención sobre ella', (public.geoportal_redes_galeria(sv, v_val) ->> 'total')::integer = 0);

  -- ---------- 07 Hechos de solo inserción ----------
  perform pg_temp.err('07.01 una edición no se cambia', $$update redes.ficha_ediciones set motivo = 'cambiado a mano'$$, '42501');
  perform pg_temp.err('07.02 un alias no se borra', $$delete from redes.activo_identificador_eventos$$, '42501');
  perform pg_temp.err('07.03 las fotos de perfil no se vacían', $$truncate redes.activo_fotos_perfil$$, '42501');
  perform pg_temp.err('07.04 una versión de la ficha no se cambia (regla del 1a)', format($$update redes.activo_versiones set diametro_mm = 1 where activo_id = (select id from redes.activos where codigo = %L)$$, v_red1), '42501');

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 3b (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
