-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- Como las del 3a, 3b y 4a: corre después de la carga real y de los cortes publicados; NO supone códigos ni conteos de la base. Arma su red de prueba
-- (ID 99600xx; nodos V996, J-996 y S-996) con el motor del 1a. Termina con un ERROR a propósito que deshace todo y trae el informe.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 4b … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
  a text := 'prueba.redes6.adm@emdupar.gov.co'; sv text := 'prueba.redes6.sup@emdupar.gov.co'; op text := 'prueba.redes6.op@emdupar.gov.co';
  o2 text := 'prueba.redes6.op2@emdupar.gov.co'; na text := 'prueba.redes6.nada@emdupar.gov.co'; sd text := 'prueba.redes6.dist@emdupar.gov.co';
  sr text := 'prueba.redes6.soloredes@emdupar.gov.co'; ina text := 'prueba.redes6.inactivo@emdupar.gov.co'; sd2 text := 'prueba.redes6.dist2@emdupar.gov.co';
  v_red1 text; v_red2 text; v_val text; v_nj bigint; v_ns bigint; v_c bigint; v_r jsonb; v_x jsonb; v_p jsonb; v_q1 bigint; v_q2 bigint;
  v_d1 text; v_d2 text; v_i1 text; v_i2 text; v_n integer; v_k text; v_nuevo text;
  v_total integer; v_bien integer; v_fallas text;
  w1 text := 'LINESTRING(' || pg_temp.p(0, 0) || ',' || pg_temp.p(100, 0) || ')';
  w2 text := 'LINESTRING(' || pg_temp.p(100, 0) || ',' || pg_temp.p(200, 0) || ')';
  w3 text := 'LINESTRING(' || pg_temp.p(200, 0) || ',' || pg_temp.p(300, 0) || ')';
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT6 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT6 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos'),
    (sd2, 'ZT6 Otro supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos'), (sr, 'ZT6 Solo dashboard de redes', 'consulta', false, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT6 Operador Uno', 'consulta', true, 'sin_restriccion', 'todos'),
    (o2, 'ZT6 Operador Dos', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, activo, horario, dias) values (ina, 'ZT6 Inactivo', 'consulta', true, false, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT6 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'mantenimiento', a), (op, 'asignar_formulario', 'danos_fallas', a);

  -- red de prueba con el motor del 1a: V996 → J-996 → S-996 → Tee-996 (J y S quedan «por clasificar», N-3)
  v_c := (public.geoportal_redes_carga_iniciar(a, 'acueducto', pg_temp.sha('zt6-acu'), 'shp', 4326, 'ID', 3) ->> 'carga_id')::bigint;
  perform public.geoportal_redes_carga_lote(a, v_c, jsonb_build_array(
    pg_temp.tramo(1, 9960001, 'Distribucion-ZT61', '99601', 'V996', '99602', 'J-996', w1), pg_temp.tramo(2, 9960002, 'Lateral-ZT62', '99602', 'J-996', '99603', 'S-996', w2),
    pg_temp.tramo(3, 9960003, 'Lateral-ZT63', '99603', 'S-996', '99604', 'Tee-996', w3)));
  perform public.geoportal_redes_carga_publicar(a, v_c, 'Red de prueba del Corte 4b');
  select codigo into v_red1 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9960001';
  select codigo into v_red2 from redes.v_activo_vigente where capa_codigo = 'acueducto' and llave_capa = '9960002';
  select codigo into v_val from redes.v_activo_vigente where capa_codigo = 'acueducto_nodos' and llave_capa = '99601';
  select nodo_id into v_nj from redes.v_nodo_vigente where sistema = 'acueducto' and llave_modelo = '99602';
  select nodo_id into v_ns from redes.v_nodo_vigente where sistema = 'acueducto' and llave_modelo = '99603';
  perform set_config('zt.red1', v_red1, true);
  perform pg_temp.reg('00.01 red de prueba: 2 RED y VAL por su llave; J-996 y S-996 quedan «por clasificar»',
     v_red1 like 'RED-%' and v_red2 like 'RED-%' and v_val like 'VAL-%'
     and (select count(*) from redes.v_nodo_vigente where nodo_id in (v_nj, v_ns) and clase_nodo = 'por_clasificar') = 2, concat_ws(' ', v_red1, v_red2, v_val, v_nj, v_ns));

  -- ---------- 01 Tablas nuevas: sin API, RLS, solo inserción ----------
  perform pg_temp.reg('01.01 tablas y vista nuevas sin privilegios para anon, authenticated ni service_role, con RLS',
     not has_table_privilege('anon', 'tecnica.personal_ficha_eventos', 'select') and not has_table_privilege('authenticated', 'tecnica.personal_ficha_eventos', 'select')
     and not has_table_privilege('service_role', 'tecnica.personal_ficha_eventos', 'select') and not has_table_privilege('service_role', 'redes.cuadrillas', 'select')
     and not has_table_privilege('authenticated', 'redes.v_personal_ficha', 'select')
     and (select relrowsecurity from pg_class where oid = 'tecnica.personal_ficha_eventos'::regclass) and (select relrowsecurity from pg_class where oid = 'redes.cuadrillas'::regclass));
  insert into tecnica.personal_ficha_eventos (persona, tipo_evento, valor, motivo, autor) values ('zt6.directo@emdupar.gov.co', 'fijar_cargo', 'Fontanero', 'Prueba directa de la tabla', a);
  perform pg_temp.err('01.02 la ficha del personal es de solo inserción (update)', $$update tecnica.personal_ficha_eventos set valor = 'Otro' where persona = 'zt6.directo@emdupar.gov.co'$$, '42501');
  perform pg_temp.err('01.03 la ficha del personal es de solo inserción (delete)', $$delete from tecnica.personal_ficha_eventos where persona = 'zt6.directo@emdupar.gov.co'$$, '42501');
  perform pg_temp.err('01.04 la regla de la tabla: el área es planta, distribución o ambas', $$insert into tecnica.personal_ficha_eventos (persona, tipo_evento, valor, motivo, autor)
     values ('zt6.directo@emdupar.gov.co', 'fijar_area', 'oficina', 'Área que no existe', 'x')$$, '23514');
  perform pg_temp.err('01.05 la regla de la tabla: el geovisor es sí o no', $$insert into tecnica.personal_ficha_eventos (persona, tipo_evento, valor, motivo, autor)
     values ('zt6.directo@emdupar.gov.co', 'fijar_geovisor', 'tal vez', 'Valor que no existe', 'x')$$, '23514');

  -- ---------- 02 Personal: la lista (supervisor de distribución y administrador) ----------
  v_r := public.geoportal_redes_personal(sd, 'zt6', 'todas');
  perform pg_temp.reg('02.01 el supervisor de distribución ve al personal de Técnica: operadores, supervisores y el de solo dashboard; ni el administrador, ni el inactivo, ni el que no es de Técnica',
     (select count(*) from jsonb_array_elements(v_r -> 'personas') x where x ->> 'email' in (op, o2, sv, sd, sd2, sr)) = 6
     and not exists (select 1 from jsonb_array_elements(v_r -> 'personas') x where x ->> 'email' in (a, ina, na)), left(v_r::text, 300));
  perform pg_temp.reg('02.02 perfil, geovisor y formularios: el operador sin casilla y con sus 2 formularios; los supervisores con el geovisor por su permiso',
     exists (select 1 from jsonb_array_elements(v_r -> 'personas') x where x ->> 'email' = op and x ->> 'perfil' = 'operador' and x ->> 'geovisor' = 'no'
             and x -> 'formularios' = '["danos_fallas", "mantenimiento"]'::jsonb and x ->> 'area' is null)
     and exists (select 1 from jsonb_array_elements(v_r -> 'personas') x where x ->> 'email' = sd and x ->> 'perfil' = 'supervisor' and x ->> 'geovisor' = 'por_permiso')
     and exists (select 1 from jsonb_array_elements(v_r -> 'personas') x where x ->> 'email' = sv and x ->> 'perfil' = 'operador' and x ->> 'geovisor' = 'por_permiso' and (x ->> 'dashboard_ptap')::boolean));
  perform pg_temp.reg('02.03 el administrador también la ve; la búsqueda filtra por nombre', jsonb_array_length(public.geoportal_redes_personal(a, 'operador dos', 'todas') -> 'personas') = 1);
  perform pg_temp.err('02.04 el operador no ve el personal', format($$select public.geoportal_redes_personal(%L)$$, op), '42501');
  perform pg_temp.err('02.05 el supervisor de planta tampoco (en redes es operador)', format($$select public.geoportal_redes_personal(%L)$$, sv), '42501');
  perform pg_temp.err('02.06 filtro que no existe', format($$select public.geoportal_redes_personal(%L, null, 'oficina')$$, sd), '22023', 'filtro');
  perform pg_temp.err('02.07 quien no es de Técnica', format($$select public.geoportal_redes_personal(%L)$$, na), '42501');

  -- ---------- 03 Personal: área, cargo, cuadrilla y geovisor, con motivo ----------
  v_r := public.geoportal_redes_personal_fijar(sd, op, 'area', 'distribucion', 'Trabaja en las cuadrillas de redes');
  perform pg_temp.reg('03.01 el supervisor de distribución fija el área del operador: evento nuevo, antes vacío', v_r ->> 'antes' is null and v_r ->> 'despues' = 'distribucion'
     and redes.f_area(op) = 'distribucion' and exists (select 1 from public.geoportal_auditoria where accion = 'redes_personal_area' and referencia = op and email = sd));
  perform pg_temp.err('03.02 repetir el mismo valor: «Ya está así»', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'area', 'distribucion', 'Otra vez lo mismo')$$, sd, op), '22023', 'Ya está así');
  perform pg_temp.err('03.03 un área que no existe', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'area', 'oficina', 'Área que no existe')$$, sd, op), '22023', 'planta, distribución o las dos');
  perform pg_temp.err('03.04 sin motivo', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'area', 'planta', 'corto')$$, sd, op), '22023', 'motivo');
  perform pg_temp.err('03.05 nadie cambia su propia ficha', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'area', 'ambas', 'Me cambio el área a mí mismo')$$, sd, sd), '22023', 'propia ficha');
  perform pg_temp.reg('03.06 otro supervisor de distribución sí cambia la del primero', public.geoportal_redes_personal_fijar(sd2, sd, 'area', 'ambas', 'Supervisa planta y redes los fines de semana') ->> 'despues' = 'ambas');
  perform pg_temp.err('03.07 una persona que no es de Técnica', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'area', 'planta', 'Persona sin Técnica')$$, sd, na), 'P0002', 'no está en Técnica');
  perform pg_temp.err('03.08 el administrador no figura en Personal', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'area', 'planta', 'El administrador no tiene ficha')$$, sd, a), 'P0002');
  perform pg_temp.err('03.09 una cuenta inactiva', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'area', 'planta', 'Cuenta inactiva en la lista')$$, sd, ina), 'P0002');
  perform pg_temp.err('03.10 el operador no fija nada', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'area', 'planta', 'Intento del operador')$$, op, o2), '42501');
  perform pg_temp.err('03.11 el supervisor de planta tampoco', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'area', 'planta', 'Intento del de planta')$$, sv, o2), '42501');
  perform pg_temp.err('03.12 un dato que no existe', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'sueldo', '1', 'Dato que no existe')$$, sd, op), '22023');
  perform pg_temp.reg('03.13 el cargo: se fija y se quita (nulo), cada vez con su evento',
     public.geoportal_redes_personal_fijar(sd, op, 'cargo', 'Fontanero', 'Cargo según el contrato') ->> 'despues' = 'Fontanero'
     and public.geoportal_redes_personal_fijar(sd, op, 'cargo', null, 'El cargo se revisa con Talento Humano') ->> 'antes' = 'Fontanero'
     and (select cargo from redes.v_personal_ficha where persona = op) is null);
  perform pg_temp.err('03.14 un cargo de una letra', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'cargo', 'F', 'Cargo demasiado corto')$$, sd, op), '22023', 'de 2 a 80');
  perform pg_temp.err('03.15 una cuadrilla que no existe', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'cuadrilla', '999999999', 'Cuadrilla que no existe')$$, sd, op), '22023', 'cuadrilla activa');
  v_q1 := (public.geoportal_redes_cuadrilla_fijar(a, null, 'ZT6 Cuadrilla Norte', null, 'Cuadrilla nueva de prueba') ->> 'id')::bigint;
  v_r := public.geoportal_redes_personal_fijar(sd, op, 'cuadrilla', v_q1::text, 'Pasa a la cuadrilla norte');
  perform pg_temp.reg('03.16 la cuadrilla del catálogo se asigna; la lista la muestra con su nombre', v_r ->> 'despues' = v_q1::text
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_personal(sd, 'operador uno') -> 'personas') x where x -> 'cuadrilla' ->> 'nombre' = 'ZT6 Cuadrilla Norte'));
  v_r := public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'Necesita ver la red en la calle');
  perform pg_temp.reg('03.17 la casilla del geovisor del operador (N-13): sí → lo ve en solo lectura', v_r ->> 'antes' = 'no' and redes.f_geovisor_lectura(op)
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_personal(sd, 'operador uno') -> 'personas') x where x ->> 'geovisor' = 'si'));
  perform pg_temp.err('03.18 la casilla no es para los supervisores (ya lo ven por su permiso)', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'geovisor', 'si', 'Casilla para el de planta')$$, sd, sv), '22023', 'por su permiso');
  perform pg_temp.err('03.19 el geovisor es sí o no', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'geovisor', 'tal vez', 'Valor que no existe')$$, sd, o2), '22023', 'geovisor');
  perform pg_temp.reg('03.20 quién ve el geovisor: administrador, supervisores (de distribución y de planta) y el operador con la casilla; no el operador sin ella ni quien no es de Técnica',
     redes.f_geovisor_lectura(a) and redes.f_geovisor_lectura(sd) and redes.f_geovisor_lectura(sv) and redes.f_geovisor_lectura(op)
     and not redes.f_geovisor_lectura(o2) and not redes.f_geovisor_lectura(na) and not redes.f_geovisor_lectura(ina));
  perform public.geoportal_redes_personal_fijar(sd, o2, 'geovisor', 'si', 'Prueba de desactivar en Técnica');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, motivo, autor) values (o2, 'desactivar_tecnica', 'Prueba del Corte 4b', a);
  perform pg_temp.reg('03.21 con el acceso a Técnica desactivado, la casilla no basta', not redes.f_geovisor_lectura(o2));
  perform pg_temp.reg('03.22 filtros: «distribución» trae al operador; «sin área» no lo trae y sí al operador dos; «planta» trae al supervisor de las dos áreas',
     exists (select 1 from jsonb_array_elements(public.geoportal_redes_personal(sd, 'zt6', 'distribucion') -> 'personas') x where x ->> 'email' = op)
     and not exists (select 1 from jsonb_array_elements(public.geoportal_redes_personal(sd, 'zt6', 'sin_area') -> 'personas') x where x ->> 'email' = op)
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_personal(sd, 'zt6', 'sin_area') -> 'personas') x where x ->> 'email' = o2)
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_personal(sd2, 'zt6', 'planta') -> 'personas') x where x ->> 'email' = sd));
  v_r := public.geoportal_redes_personal_historial(sd, op, null, 50);
  perform pg_temp.reg('03.23 el historial del operador: 5 eventos, el más reciente primero, con el nombre de la cuadrilla y el motivo', (v_r ->> 'total')::integer = 5
     and v_r -> 'eventos' -> 0 ->> 'tipo' = 'geovisor' and exists (select 1 from jsonb_array_elements(v_r -> 'eventos') x where x ->> 'valor_nombre' = 'ZT6 Cuadrilla Norte')
     and v_r -> 'eventos' -> 0 ->> 'autor_nombre' = 'ZT6 Supervisor de distribución', left(v_r::text, 300));
  perform pg_temp.reg('03.24 el historial pagina con «después de»', jsonb_array_length(public.geoportal_redes_personal_historial(sd, op, (v_r -> 'eventos' -> 1 ->> 'id')::bigint, 50) -> 'eventos') = 3);
  perform pg_temp.err('03.25 el operador no ve el historial', format($$select public.geoportal_redes_personal_historial(%L)$$, op), '42501');

  -- ---------- 04 Catálogo: lo lee el supervisor; el alias y las cuadrillas, solo el administrador ----------
  v_r := public.geoportal_redes_catalogo(sd);
  perform pg_temp.reg('04.01 el supervisor lee el catálogo (tipos con sus activos vigentes, materiales, estados, cuadrillas…) sin poder editar',
     not (v_r ->> 'puede_editar')::boolean and exists (select 1 from jsonb_array_elements(v_r -> 'tipos') x where x ->> 'prefijo' = 'RED' and (x ->> 'vigentes')::integer >= 2)
     and jsonb_array_length(v_r -> 'materiales') > 0 and jsonb_array_length(v_r -> 'estados') > 0 and jsonb_array_length(v_r -> 'tipos_intervencion') = 5
     and exists (select 1 from jsonb_array_elements(v_r -> 'cuadrillas') x where x ->> 'nombre' = 'ZT6 Cuadrilla Norte' and (x ->> 'personas')::integer = 1));
  perform pg_temp.reg('04.02 el administrador puede editar', (public.geoportal_redes_catalogo(a) ->> 'puede_editar')::boolean);
  perform pg_temp.err('04.03 el operador no lee el catálogo de gestión', format($$select public.geoportal_redes_catalogo(%L)$$, op), '42501');
  perform public.geoportal_redes_alias_fijar(a, 'tipo', 'TOR', 'Hidrante', 'Técnica confirmó que las torres son hidrantes');
  perform pg_temp.reg('04.04 alias del tipo TOR = «Hidrante» (N-12): el catálogo lo muestra; el prefijo y el nombre original no cambian',
     exists (select 1 from jsonb_array_elements(public.geoportal_redes_catalogo(sd) -> 'tipos') x where x ->> 'prefijo' = 'TOR' and x ->> 'alias' = 'Hidrante' and x ->> 'nombre_visible' = 'Hidrante'
             and x ->> 'nombre' <> 'Hidrante'));
  perform pg_temp.err('04.05 el supervisor de distribución no cambia el alias', format($$select public.geoportal_redes_alias_fijar(%L, 'tipo', 'TOR', 'Torre', 'Intento del supervisor')$$, sd), '42501');
  perform public.geoportal_redes_alias_fijar(a, 'tipo', 'TOR', null, 'Se vuelve al nombre original del modelo');
  v_r := public.geoportal_redes_alias_historial(sd, 'tipo', 'TOR');
  perform pg_temp.reg('04.06 volver al nombre original (alias nulo) y el historial con los dos cambios y sus motivos',
     (select nombre_visible = nombre from redes.v_tipo_visible where prefijo = 'TOR') and jsonb_array_length(v_r -> 'eventos') >= 2
     and v_r -> 'eventos' -> 0 ->> 'alias' is null and v_r -> 'eventos' -> 1 ->> 'alias' = 'Hidrante');
  perform pg_temp.err('04.07 el supervisor no crea cuadrillas', format($$select public.geoportal_redes_cuadrilla_fijar(%L, null, 'ZT6 Sur', null, 'Cuadrilla del supervisor')$$, sd), '42501');
  perform pg_temp.err('04.08 dos cuadrillas con el mismo nombre (sin importar mayúsculas)', format($$select public.geoportal_redes_cuadrilla_fijar(%L, null, ' zt6 cuadrilla norte ', null, 'Repetida a propósito')$$, a), '22023', 'Ya existe');
  v_q2 := (public.geoportal_redes_cuadrilla_fijar(a, null, 'ZT6 Cuadrilla Sur', null, 'Segunda cuadrilla de prueba') ->> 'id')::bigint;
  v_r := public.geoportal_redes_cuadrilla_fijar(a, v_q2, 'ZT6 Cuadrilla Sur Oriente', null, 'Cambió de zona');
  v_x := public.geoportal_redes_cuadrilla_fijar(a, v_q2, null, false, 'La cuadrilla se fusionó con la norte');
  perform pg_temp.reg('04.09 renombrar y desactivar una cuadrilla (con su antes y después en la auditoría)',
     v_r ->> 'nombre' = 'ZT6 Cuadrilla Sur Oriente' and not (v_x ->> 'activa')::boolean
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_cuadrilla_cambiar' and referencia = v_q2::text and detalle -> 'antes' ->> 'activa' = 'true'));
  perform pg_temp.err('04.10 una cuadrilla desactivada no se asigna', format($$select public.geoportal_redes_personal_fijar(%L, %L, 'cuadrilla', %L, 'Asignar la desactivada')$$, sd, o2, v_q2::text), '22023', 'cuadrilla activa');
  perform pg_temp.reg('04.11 la desactivada no sale para elegir en Personal, pero sí en el catálogo',
     not exists (select 1 from jsonb_array_elements(public.geoportal_redes_personal(sd) -> 'cuadrillas') x where (x ->> 'id')::bigint = v_q2)
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_catalogo(sd) -> 'cuadrillas') x where (x ->> 'id')::bigint = v_q2 and not (x ->> 'activa')::boolean));
  perform pg_temp.err('04.12 una cuadrilla no se borra', format($$delete from redes.cuadrillas where id = %s$$, v_q2), '42501');
  perform pg_temp.err('04.13 «Ya está así»', format($$select public.geoportal_redes_cuadrilla_fijar(%L, %L, null, false, 'Otra vez desactivada')$$, a, v_q2), '22023', 'Ya está así');

  -- ---------- 05 Parámetros: lo lee el supervisor; los cambia el administrador ----------
  v_r := public.geoportal_redes_parametros(sd);
  perform pg_temp.reg('05.01 el supervisor los lee, ninguno editable para él', not (v_r ->> 'puede_editar')::boolean and jsonb_array_length(v_r -> 'parametros') > 20
     and not exists (select 1 from jsonb_array_elements(v_r -> 'parametros') x where (x ->> 'editable')::boolean));
  v_r := public.geoportal_redes_parametros(a);
  perform pg_temp.reg('05.02 para el administrador todos editables, menos la caja de Valledupar; los de fotos y días van enteros',
     (v_r ->> 'puede_editar')::boolean and not exists (select 1 from jsonb_array_elements(v_r -> 'parametros') x where x ->> 'clave' like 'caja\_%' and (x ->> 'editable')::boolean)
     and exists (select 1 from jsonb_array_elements(v_r -> 'parametros') x where x ->> 'clave' = 'itv_radio_danos_m' and (x ->> 'editable')::boolean)
     and exists (select 1 from jsonb_array_elements(v_r -> 'parametros') x where x ->> 'clave' = 'max_fotos_itv' and (x ->> 'entero')::boolean));
  v_n := redes.f_param('itv_radio_danos_m')::integer;
  v_r := public.geoportal_redes_parametro_fijar(a, 'itv_radio_danos_m', v_n + 25, 'Se amplía el radio de los daños cercanos');
  perform pg_temp.reg('05.03 el administrador cambia un parámetro: queda el evento con el antes y el después, y la función lo lee', (v_r ->> 'antes')::numeric = v_n
     and redes.f_param('itv_radio_danos_m') = v_n + 25 and exists (select 1 from redes.parametro_eventos where clave = 'itv_radio_danos_m' and antes = v_n and despues = v_n + 25)
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_parametro' and referencia = 'itv_radio_danos_m')
     and (public.geoportal_redes_parametros(sd) -> 'historial' -> 0 ->> 'clave') = 'itv_radio_danos_m');
  perform pg_temp.err('05.04 fuera del rango', format($$select public.geoportal_redes_parametro_fijar(%L, 'itv_radio_danos_m', 5000, 'Radio demasiado grande')$$, a), '22023', 'El valor va de');
  perform pg_temp.err('05.05 un parámetro que se cuenta no lleva decimales', format($$select public.geoportal_redes_parametro_fijar(%L, 'max_fotos_itv', 8.5, 'Medias fotos no existen')$$, a), '22023', 'enteros');
  perform pg_temp.err('05.06 la caja de Valledupar no se cambia desde la pantalla', format($$select public.geoportal_redes_parametro_fijar(%L, 'caja_lat_min', 10.0, 'Mover la caja')$$, a), '22023', 'caja');
  perform pg_temp.err('05.07 las fotos mínimas no bajan de 1 (§25.8)', format($$select public.geoportal_redes_parametro_fijar(%L, 'min_fotos_dano', 0, 'Permitir daños sin foto')$$, a), '22023', 'no bajan de 1');
  perform pg_temp.err('05.08 el mínimo no pasa al máximo', format($$select public.geoportal_redes_parametro_fijar(%L, 'min_fotos_itv', %s, 'Más mínimas que máximas')$$, a, redes.f_param('max_fotos_itv') + 1), '22023', 'por encima');
  perform pg_temp.err('05.09 el mismo valor', format($$select public.geoportal_redes_parametro_fijar(%L, 'itv_radio_danos_m', %s, 'El mismo valor otra vez')$$, a, v_n + 25), '22023', 'Ya tiene ese valor');
  perform pg_temp.err('05.10 el supervisor de distribución no los cambia', format($$select public.geoportal_redes_parametro_fijar(%L, 'itv_radio_danos_m', 100, 'Intento del supervisor')$$, sd), '42501');
  perform pg_temp.err('05.11 un parámetro que no existe', format($$select public.geoportal_redes_parametro_fijar(%L, 'no_existe', 1, 'Parámetro que no existe')$$, a), 'P0002');

  -- ---------- 06 Gráficas (D-19) ----------
  v_p := pg_temp.preparar(op, 1);
  v_i1 := public.geoportal_redes_crear_intervencion(op, (v_p ->> 'intervencion_id')::uuid, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'))) ->> 'codigo';
  v_d1 := pg_temp.dano(op, '{"causa_clase": "terceros", "causa": "vehiculo", "tercero_tipo": "vehiculo", "tercero_nombre": "Placa ZT6-321"}') ->> 'codigo';
  v_p := pg_temp.preparar(sd, 1);
  v_i2 := public.geoportal_redes_crear_intervencion(sd, (v_p ->> 'intervencion_id')::uuid, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'),
            jsonb_build_object('nace_de', 'dano', 'tipo', 'reparacion', 'dano', v_d1, 'resuelve_dano', true, 'fuentes', '[{"aportante": "emdupar", "valor": 950000}]'::jsonb))) ->> 'codigo';
  v_r := public.geoportal_redes_graficas(sd, 12);
  v_k := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM');
  perform pg_temp.reg('06.01 12 meses, el último es el actual; la intervención de prueba cuenta en su mes, tipo y sistema',
     jsonb_array_length(v_r -> 'meses') = 12 and v_r -> 'meses' ->> 11 = v_k
     and exists (select 1 from jsonb_array_elements(v_r -> 'intervenciones_mes') x where x ->> 'mes' = v_k and x ->> 'tipo' = 'preventivo' and x ->> 'sistema' = 'acueducto' and (x ->> 'n')::integer >= 1));
  v_n := (select sum((x ->> 'n')::integer) from jsonb_array_elements(v_r -> 'intervenciones_mes') x where x ->> 'mes' = v_k and x ->> 'tipo' = 'preventivo' and x ->> 'sistema' = 'acueducto');
  perform public.geoportal_redes_intervencion_evento(sd, v_i1, 'ocultar', 'Dato de prueba del Corte 4b');
  perform pg_temp.reg('06.02 una intervención oculta no cuenta', coalesce((select sum((x ->> 'n')::integer) from jsonb_array_elements(public.geoportal_redes_graficas(sd, 12) -> 'intervenciones_mes') x
     where x ->> 'mes' = v_k and x ->> 'tipo' = 'preventivo' and x ->> 'sistema' = 'acueducto'), 0) = v_n - 1);
  perform public.geoportal_redes_intervencion_evento(sd, v_i1, 'reincluir', 'Se reincluye para las demás pruebas');
  perform pg_temp.reg('06.03 el valor por fuente suma el valor de la reparación del supervisor', exists (select 1 from jsonb_array_elements(v_r -> 'valor_fuente') x
     where x ->> 'aportante' = 'emdupar' and (x ->> 'valor')::numeric >= 950000));
  perform pg_temp.reg('06.04 daños por clase y causa: el de terceros, atendido, con el tiempo medio de reparación', exists (select 1 from jsonb_array_elements(v_r -> 'danos_causa') x
     where x ->> 'clase' = 'dano' and x ->> 'causa_clase' = 'terceros' and (x ->> 'n')::integer >= 1 and (x ->> 'atendidos')::integer >= 1));
  perform pg_temp.reg('06.05 los activos con más correctivos traen el tramo de la reparación, con el nombre visible del tipo', exists (select 1 from jsonb_array_elements(v_r -> 'top_correctivos') x
     where x ->> 'activo' = v_red1 and (x ->> 'n')::integer >= 1 and x ->> 'tipo' is not null) and jsonb_array_length(v_r -> 'top_correctivos') <= 10);
  perform pg_temp.err('06.06 meses fuera de rango', format($$select public.geoportal_redes_graficas(%L, 25)$$, sd), '22023', 'de 1 a 24');
  perform pg_temp.err('06.07 el operador no ve las gráficas', format($$select public.geoportal_redes_graficas(%L)$$, op), '42501');

  -- ---------- 07 Descargas (auditadas; sin el tercero, sin textos libres) ----------
  v_r := public.geoportal_redes_descarga(sd, 'intervenciones', current_date - 1, current_date + 1, false, '10.0.0.1');
  perform pg_temp.reg('07.01 descarga de intervenciones: trae las de prueba con el nombre visible del tipo y su prefijo, y sin descripción ni compañeros',
     exists (select 1 from jsonb_array_elements(v_r -> 'filas') x where x ->> 'codigo' = v_i2 and x ->> 'prefijo' = 'RED' and x ->> 'tipo_activo' is not null and (x ->> 'valor_total')::numeric = 950000)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'filas') x where x ? 'descripcion' or x ? 'companeros') and (v_r ->> 'total')::integer = jsonb_array_length(v_r -> 'filas'));
  perform pg_temp.reg('07.02 cada descarga queda en la auditoría (quién, qué, rango, filas e IP)', exists (select 1 from public.geoportal_auditoria where accion = 'redes_descarga' and email = sd
     and referencia = 'intervenciones' and (detalle ->> 'filas')::integer = (v_r ->> 'total')::integer and ip = '10.0.0.1'));
  v_r := public.geoportal_redes_descarga(sd, 'danos', current_date - 1, current_date + 1);
  perform pg_temp.reg('07.03 descarga de daños: el de terceros con el tipo de tercero, pero nunca su nombre ni su placa', exists (select 1 from jsonb_array_elements(v_r -> 'filas') x
     where x ->> 'codigo' = v_d1 and x ->> 'tercero_tipo' = 'vehiculo' and x ->> 'causa_clase' = 'terceros' and (x ->> 'intervenciones')::integer = 1 and x ->> 'reparacion_min' is not null)
     and position('ZT6-321' in v_r::text) = 0 and not exists (select 1 from jsonb_array_elements(v_r -> 'filas') x where x ? 'tercero_nombre' or x ? 'descripcion'));
  perform public.geoportal_redes_dano_evento(sd, v_d1, 'ocultar', 'Dato de prueba del Corte 4b');
  perform pg_temp.reg('07.04 los ocultos no salen, salvo que se pidan', not exists (select 1 from jsonb_array_elements(public.geoportal_redes_descarga(sd, 'danos', current_date - 1, current_date + 1) -> 'filas') x where x ->> 'codigo' = v_d1)
     and exists (select 1 from jsonb_array_elements(public.geoportal_redes_descarga(sd, 'danos', current_date - 1, current_date + 1, true) -> 'filas') x where x ->> 'codigo' = v_d1 and x ->> 'estado' = 'oculto'));
  perform pg_temp.err('07.05 más de un año', format($$select public.geoportal_redes_descarga(%L, 'danos', current_date - 400, current_date)$$, sd), '22023', 'un año');
  perform pg_temp.err('07.06 «hasta» antes de «desde»', format($$select public.geoportal_redes_descarga(%L, 'danos', current_date, current_date - 3)$$, sd), '22023', 'rango');
  perform pg_temp.err('07.07 un conjunto que no existe', format($$select public.geoportal_redes_descarga(%L, 'contratos', current_date - 3, current_date)$$, sd), '22023', 'conjunto');
  perform pg_temp.err('07.08 el operador no descarga', format($$select public.geoportal_redes_descarga(%L, 'danos', current_date - 3, current_date)$$, op), '42501');

  -- ---------- 08 Nodos por clasificar (solo el administrador, N-3) ----------
  perform pg_temp.err('08.01 el supervisor de distribución no abre la bandeja de nodos', format($$select public.geoportal_redes_nodos_por_clasificar(%L)$$, sd), '42501');
  v_r := public.geoportal_redes_nodos_por_clasificar(a, 'J-996');
  perform pg_temp.reg('08.02 el administrador busca J-996: 1 nodo con sus 2 tramos; los grupos J y S; los tipos de punto para crear el activo',
     (v_r ->> 'total')::integer = 1 and v_r -> 'items' -> 0 ->> 'nombre_modelo' = 'J-996' and (v_r -> 'items' -> 0 ->> 'tramos')::integer = 2
     and exists (select 1 from jsonb_array_elements(v_r -> 'grupos') x where x ->> 'grupo' = 'J') and exists (select 1 from jsonb_array_elements(v_r -> 'grupos') x where x ->> 'grupo' = 'S')
     and exists (select 1 from jsonb_array_elements(v_r -> 'tipos') x where x ->> 'prefijo' = 'VAL' and (x ->> 'pide_clase')::boolean), left(v_r::text, 300));
  perform public.geoportal_redes_alias_fijar(a, 'nodo', v_ns::text, 'Salida del sector ZT6', 'Técnica dice que es la salida del sector');
  v_r := public.geoportal_redes_nodos_por_clasificar(a, 'salida del sector zt6');
  perform pg_temp.reg('08.03 el alias del nodo: se busca por él y sale como nombre visible; el nombre del modelo no cambia', (v_r ->> 'total')::integer = 1
     and v_r -> 'items' -> 0 ->> 'alias' = 'Salida del sector ZT6' and v_r -> 'items' -> 0 ->> 'nombre_modelo' = 'S-996');
  perform pg_temp.err('08.04 una válvula sin clase', format($$select public.geoportal_redes_nodo_crear_activo(%L, %s, 'VAL', null, null, 'Es una válvula de cierre')$$, a, v_nj), '22023', 'clase');
  perform pg_temp.err('08.05 un tipo de otro sistema', format($$select public.geoportal_redes_nodo_crear_activo(%L, %s, 'POZ', null, null, 'Un pozo en el acueducto')$$, a, v_nj), '22023', 'mismo sistema');
  perform pg_temp.err('08.06 un tipo de línea', format($$select public.geoportal_redes_nodo_crear_activo(%L, %s, 'RED', null, null, 'Una red no es un nodo')$$, a, v_nj), '22023');
  v_r := public.geoportal_redes_nodo_crear_activo(a, v_nj, 'VAL', 'cierre', null, 'Técnica confirmó que la J-996 es una válvula de cierre');
  v_nuevo := v_r ->> 'activo';
  perform pg_temp.reg('08.07 crear el activo del nodo: VAL nueva en la posición del nodo, con J-996 como código anterior; el nodo queda enlazado y sale de la bandeja',
     v_nuevo like 'VAL-%' and (select activo_id from redes.v_nodo_vigente where nodo_id = v_nj) = (select id from redes.activos where codigo = v_nuevo)
     and (select clase_nodo from redes.v_nodo_vigente where nodo_id = v_nj) = 'activo'
     and (select codigo_anterior from redes.activo_vigente_mat where codigo = v_nuevo) = 'J-996'
     and ST_Equals((select geom from redes.activo_vigente_mat where codigo = v_nuevo), (select geom from redes.v_nodo_vigente where nodo_id = v_nj))
     and (public.geoportal_redes_nodos_por_clasificar(a, 'J-996') ->> 'total')::integer = 0
     and exists (select 1 from redes.nodo_eventos where nodo_id = v_nj and tipo = 'enlazar_activo'), v_r::text);
  v_x := public.geoportal_redes_activo(sd, v_nuevo);
  perform pg_temp.reg('08.08 la ficha del activo nuevo lo muestra como el nodo del modelo y en el tramo', v_x -> 'nodo' ->> 'nombre_visible' = 'J-996' and (v_x -> 'nodo' ->> 'tramos')::integer = 2
     and (public.geoportal_redes_tramo_nodos(sd, v_red1) -> 'nodos' -> 1 -> 'activo' ->> 'codigo') = v_nuevo, left(v_x::text, 300));
  perform pg_temp.err('08.09 crear dos veces', format($$select public.geoportal_redes_nodo_crear_activo(%L, %s, 'VAL', 'cierre', null, 'Otra vez la misma válvula')$$, a, v_nj), '22023', 'ya no está por clasificar');
  perform pg_temp.err('08.10 un nodo que no existe', $$select public.geoportal_redes_nodo_crear_activo('prueba.redes6.adm@emdupar.gov.co', -1, 'VAL', 'cierre', null, 'Nodo que no existe')$$, 'P0002');
  v_r := public.geoportal_redes_nodos_por_clasificar(a, null, null, 1);
  perform pg_temp.reg('08.11 la bandeja pagina («siguiente» = el último de la página)', jsonb_array_length(v_r -> 'items') = 1 and (v_r ->> 'siguiente')::bigint = (v_r -> 'items' -> 0 ->> 'nodo_id')::bigint
     and (public.geoportal_redes_nodos_por_clasificar(a, null, (v_r ->> 'siguiente')::bigint, 1) -> 'items' -> 0 ->> 'nodo_id')::bigint > (v_r ->> 'siguiente')::bigint);
  perform pg_temp.err('08.12 el supervisor de distribución no crea activos en los nodos', format($$select public.geoportal_redes_nodo_crear_activo(%L, %s, 'TAN', null, null, 'Intento del supervisor')$$, sd, v_ns), '42501');

  -- ---------- 09 §27: un PDF no cuenta como evidencia; el registro «sin tope» del supervisor sigue como está (propuesta en la bitácora) ----------
  perform pg_temp.err('09.01 sin fotos, solo con un PDF, ni se prepara', format($$select public.geoportal_redes_preparar_intervencion(%L, 0, 1)$$, sd), '22023', 'de 1 a');
  v_p := public.geoportal_redes_preparar_intervencion(sd, 1, 0);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta', 800000, 'application/pdf');      -- en el lugar de la foto se sube un PDF
  perform pg_temp.err('09.02 un PDF en el lugar de la foto no pasa como foto', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, sd, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'))), '22023', 'JPEG');
  v_p := pg_temp.preparar(sd, 1);
  v_r := public.geoportal_redes_crear_intervencion(sd, (v_p ->> 'intervencion_id')::uuid, pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'),
            jsonb_build_object('t_inicio', pg_temp.iso('-10 days'), 't_fin', pg_temp.iso('-5 days'))));
  perform pg_temp.reg('09.03 el supervisor de distribución sigue sin tope de tiempos (5 días de obra, hace 10): sin cambios en este corte', v_r ->> 'codigo' like 'ITV-%', v_r::text);
  v_p := pg_temp.preparar(op, 1);
  perform pg_temp.err('09.04 el operador sigue con su tope (72 h y 7 días atrás)', format($$select public.geoportal_redes_crear_intervencion(%L, %L, %L)$$, op, v_p ->> 'intervencion_id',
     pg_temp.itv(pg_temp.a1(v_p -> 'fotos' -> 0 ->> 'ruta'), jsonb_build_object('t_inicio', pg_temp.iso('-10 days'), 't_fin', pg_temp.iso('-5 days')))), '22023', '7 días');

  -- ---------- 10 No toca lo vivo ----------
  perform pg_temp.reg('10.01 la regla de captura de planta no cambió: el operador sigue con sus formularios asignados en personal_tecnico_eventos',
     tecnica.f_formulario_asignado(op, 'mantenimiento') and not tecnica.f_formulario_asignado(o2, 'mantenimiento'));
  perform pg_temp.reg('10.02 las 4 funciones de permisos tienen una sola firma cada una', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('geoportal_puede', 'geoportal_mis_permisos', 'geoportal_admin_permisos', 'geoportal_admin_listar')) = 4);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 4b (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
