-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 70 — PRUEBAS (dentro del ensayo; todo se deshace al final con el ERROR esperado)
-- Datos propios con prefijo ZTCOM (correos ztcom.*@emdupar.gov.co, cuadrillas «ZTCOM …», áreas y actividades «ZTCOM …»). Cada prueba cuenta SOLO sus filas.
-- Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table zt_res (n serial, nombre text, ok boolean, detalle text) on commit drop;
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into zt_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
-- llama una RPC como service_role; devuelve su jsonb o {"error": sqlstate, "msg": mensaje}
create function pg_temp.rpc(q text) returns jsonb language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  begin
    execute 'set local role service_role';
    execute 'select (' || q || ')::jsonb' into r;
    execute 'reset role';
    return coalesce(r, 'null'::jsonb);
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    return jsonb_build_object('error', e, 'msg', m);
  end;
end $f$;
create function pg_temp.err(r jsonb) returns text language sql as $f$ select coalesce(r ->> 'error', 'OK') $f$;
create function pg_temp.persona(r jsonb, p_email text) returns jsonb language sql as $f$
  select x from jsonb_array_elements(r -> 'personas') x where x ->> 'email' = p_email $f$;
create function pg_temp.act(p jsonb, p_codigo text) returns text language sql as $f$
  select x ->> 'origen' from jsonb_array_elements(p -> 'actividades') x where x ->> 'codigo' = p_codigo $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta) values
  ('ztcom.adm@emdupar.gov.co', 'ZTCOM Admin', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('ztcom.sup@emdupar.gov.co', 'ZTCOM Supervisor', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('ztcom.supacta@emdupar.gov.co', 'ZTCOM Sup Actas', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, true),
  ('ztcom.op1@emdupar.gov.co', 'ZTCOM Operario 1', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztcom.op2@emdupar.gov.co', 'ZTCOM Operario 2', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, true, false),
  ('ztcom.op3@emdupar.gov.co', 'ZTCOM Operario 3', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztcom.nada@emdupar.gov.co', 'ZTCOM Sin acceso', 'consulta', true, 'sin_restriccion', 'todos', true, false, false, false, false);

do $$
declare r jsonb; p jsonb; c1 bigint; c2 bigint; t0 timestamptz; v text;
  S constant text := '''ztcom.sup@emdupar.gov.co'''; A constant text := '''ztcom.adm@emdupar.gov.co'''; SA constant text := '''ztcom.supacta@emdupar.gov.co''';
begin
  -- 01 a 03: lectura y semilla
  r := pg_temp.rpc('public.geoportal_campo_personal(' || SA || ')');
  perform pg_temp.ok('01.01 el supervisor de actas ve Personal; puede todo en falso; yo = su correo', pg_temp.err(r) = 'OK' and r ->> 'yo' = 'ztcom.supacta@emdupar.gov.co'
    and not exists (select 1 from jsonb_each(r -> 'puede') x where x.value = 'true'::jsonb), left(r::text, 300));
  perform pg_temp.ok('01.02 la semilla trae las 4 áreas de D2', (select count(*) from jsonb_array_elements(r -> 'areas') x where x ->> 'codigo' in ('facturacion', 'cartera_scrr', 'perdidas', 'pqr_atencion')) = 4);
  perform pg_temp.ok('01.03 la semilla trae las 10 actividades de D4 (SCRR en tres)', (select count(*) from jsonb_array_elements(r -> 'actividades') x
    where x ->> 'codigo' in ('suspension', 'corte', 'reconexion', 'lectura', 'reparto', 'revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida', 'posible_perdida')) = 10);
  p := pg_temp.persona(r, 'ztcom.op1@emdupar.gov.co');
  perform pg_temp.ok('01.04 la persona conserva las claves de hoy y trae las nuevas', p ?& array['email', 'nombre', 'perfil', 'permisos', 'cargo', 'formularios', 'sin_asignacion', 'ultimo_cambio', 'propia', 'area', 'cuadrilla', 'actividades']
    and r ?& array['puede_editar', 'formularios', 'personas', 'yo', 'puede', 'areas', 'cuadrillas', 'actividades'] and p -> 'actividades' = '[]'::jsonb and p -> 'propia' = 'false'::jsonb, left(p::text, 300));
  perform pg_temp.ok('01.05 propia: true en la ficha de quien consulta', pg_temp.persona(r, 'ztcom.supacta@emdupar.gov.co') -> 'propia' = 'true'::jsonb);
  r := pg_temp.rpc('public.geoportal_campo_personal(' || S || ')');
  perform pg_temp.ok('01.06 el supervisor de campo puede cuadrilla, cuadrillas, actividades y formularios; no cargo, área ni catálogos',
    r -> 'puede' = '{"area": false, "cargo": false, "cuadrilla": true, "catalogos": false, "cuadrillas": true, "actividades": true, "formularios": true}'::jsonb, (r -> 'puede')::text);
  r := pg_temp.rpc('public.geoportal_campo_personal(' || A || ')');
  perform pg_temp.ok('01.07 el administrador puede todo', not exists (select 1 from jsonb_each(r -> 'puede') x where x.value <> 'true'::jsonb), (r -> 'puede')::text);
  r := pg_temp.rpc('public.geoportal_campo_personal(''ztcom.op1@emdupar.gov.co'')');
  perform pg_temp.ok('01.08 un operario no ve Personal (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc('public.geoportal_campo_cuadrillas(''ztcom.nada@emdupar.gov.co'')');
  perform pg_temp.ok('01.09 alguien sin acceso a campo no ve las cuadrillas (42501)', pg_temp.err(r) = '42501', r::text);

  -- 02: cuadrillas
  r := pg_temp.rpc('public.geoportal_campo_cuadrilla_cambiar(' || S || ', ''{"tipo": "crear", "nombre": "ZTCOM  Norte"}'')');
  c1 := (r ->> 'id')::bigint;
  perform pg_temp.ok('02.01 el supervisor crea una cuadrilla (espacios repetidos se reducen)', c1 is not null and (select nombre from campo.cuadrillas where id = c1) = 'ZTCOM Norte', r::text);
  r := pg_temp.rpc('public.geoportal_campo_cuadrilla_cambiar(' || S || ', ''{"tipo": "crear", "nombre": "ztcom norte"}'')');
  perform pg_temp.ok('02.02 nombre repetido sin distinguir mayúsculas ni espacios: 55000 con texto', pg_temp.err(r) = '55000' and r ->> 'msg' = 'Ya existe una cuadrilla con ese nombre', r::text);
  r := pg_temp.rpc('public.geoportal_campo_cuadrilla_cambiar(' || SA || ', ''{"tipo": "crear", "nombre": "ZTCOM Actas"}'')');
  perform pg_temp.ok('02.03 el supervisor de actas no crea cuadrillas (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc('public.geoportal_campo_cuadrilla_cambiar(' || S || ', ''{"tipo": "crear", "nombre": "ZTCOM Sur"}'')');
  c2 := (r ->> 'id')::bigint;
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "renombrar", "cuadrilla_id": %s, "nombre": "ZTCOM Sur"}'')', S, c2));
  perform pg_temp.ok('02.04 renombrar con el mismo nombre: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "renombrar", "cuadrilla_id": %s, "nombre": "ZTCOM Norte"}'')', S, c2));
  perform pg_temp.ok('02.05 renombrar al nombre de otra cuadrilla: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "renombrar", "cuadrilla_id": %s, "nombre": "ZTCOM Sur Oriente"}'')', S, c2));
  perform pg_temp.ok('02.06 renombrar', pg_temp.err(r) = 'OK' and (select nombre from campo.cuadrillas where id = c2) = 'ZTCOM Sur Oriente', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "suspension"}'')', S, c1));
  perform pg_temp.ok('02.07 agregar una actividad a la cuadrilla', pg_temp.err(r) = 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "corte"}'')', S, c1));
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "corte"}'')', S, c1));
  perform pg_temp.ok('02.08 agregar la misma actividad otra vez: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "no_existe"}'')', S, c1));
  perform pg_temp.ok('02.09 una actividad que no existe: 22023 con texto', pg_temp.err(r) = '22023' and r ->> 'msg' = 'Esa actividad no existe', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "suspension"}'')', S, c2));
  perform pg_temp.ok('02.10 la cuadrilla tiene sus actividades (y solo esas)', campo.f_cuadrilla_actividades(c1) = '{corte,suspension}' and campo.f_cuadrilla_actividades(c2) = '{suspension}');

  -- 03: personas en cuadrillas y actividades propias (D3)
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": 999999999}'')', S));
  perform pg_temp.ok('03.01 una cuadrilla que no existe', r ->> 'msg' = 'Esa cuadrilla no existe', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('03.02 el supervisor mete a una persona en la cuadrilla', pg_temp.err(r) = 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('03.03 meterla otra vez: 55000', pg_temp.err(r) = '55000' and r ->> 'msg' = 'Ya está en esa cuadrilla', r::text);
  p := pg_temp.persona(pg_temp.rpc('public.geoportal_campo_personal(' || S || ')'), 'ztcom.op1@emdupar.gov.co');
  perform pg_temp.ok('03.04 hereda las actividades de la cuadrilla (origen cuadrilla) y se ve la cuadrilla', pg_temp.act(p, 'suspension') = 'cuadrilla' and pg_temp.act(p, 'corte') = 'cuadrilla'
    and jsonb_array_length(p -> 'actividades') = 2 and p -> 'cuadrilla' = jsonb_build_object('id', c1, 'nombre', 'ZTCOM Norte', 'activa', true), left(p::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "corte"}'')', S));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "lectura"}'')', S));
  p := pg_temp.persona(pg_temp.rpc('public.geoportal_campo_personal(' || S || ')'), 'ztcom.op1@emdupar.gov.co');
  perform pg_temp.ok('03.05 además tiene propias: corte queda «ambas», lectura «propia»', pg_temp.act(p, 'corte') = 'ambas' and pg_temp.act(p, 'lectura') = 'propia' and jsonb_array_length(p -> 'actividades') = 3, left(p::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''quitar_actividad'', ''{"actividad": "suspension", "motivo": "ZTCOM prueba de quitar heredada"}'')', S));
  perform pg_temp.ok('03.06 quitar como propia una que viene de la cuadrilla: 55000 con el nombre de la cuadrilla', pg_temp.err(r) = '55000'
    and r ->> 'msg' = 'Esa actividad viene de la cuadrilla ZTCOM Norte: se quita en la cuadrilla', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''quitar_actividad'', ''{"actividad": "corte"}'')', S));
  perform pg_temp.ok('03.07 quitar una propia exige motivo', pg_temp.err(r) = '22023' and r ->> 'msg' like 'Escriba el motivo%', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''quitar_actividad'', ''{"actividad": "corte", "motivo": "corto"}'')', S));
  perform pg_temp.ok('03.08 motivo de menos de 10 caracteres: rechazado', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''quitar_actividad'', ''{"actividad": "corte", "motivo": "ZTCOM ya no hace cortes por su cuenta"}'')', S));
  p := pg_temp.persona(pg_temp.rpc('public.geoportal_campo_personal(' || S || ')'), 'ztcom.op1@emdupar.gov.co');
  perform pg_temp.ok('03.09 al quitar la propia, «ambas» vuelve a «cuadrilla»', pg_temp.err(r) = 'OK' and pg_temp.act(p, 'corte') = 'cuadrilla', left(p::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op2@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "suspension"}'')', S));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op3@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": %s}'')', S, c2));
  perform pg_temp.ok('03.10 persona sin cuadrilla con varias actividades propias (op2) y otra en la cuadrilla Sur (op3)', pg_temp.err(r) = 'OK');
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.sup@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('03.11 nadie cambia su propia ficha (400 con texto)', pg_temp.err(r) = '22023' and r ->> 'msg' = 'No puede cambiar su propia ficha', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "reparto"}'')', SA));
  perform pg_temp.ok('03.12 el supervisor de actas no cambia fichas (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.nada@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "reparto"}'')', S));
  perform pg_temp.ok('03.13 una persona sin acceso a campo ni acta no se gestiona', r ->> 'msg' = 'Esa persona no tiene acceso activo a Formularios de campo ni al acta', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''asignar_formulario'', ''{"formulario": "acta"}'')', S));
  perform pg_temp.ok('03.14 el supervisor de campo asigna formularios (antes solo el administrador)', pg_temp.err(r) = 'OK' and 'acta' = any (campo.f_formularios_asignados('ztcom.op1@emdupar.gov.co')), r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''quitar_formulario'', ''{"formulario": "acta", "motivo": "ZTCOM prueba de retiro de formulario"}'')', S));
  perform pg_temp.ok('03.15 y lo retira con motivo', pg_temp.err(r) = 'OK' and not ('acta' = any (campo.f_formularios_asignados('ztcom.op1@emdupar.gov.co'))), r::text);

  -- 04: área y cargo (solo administrador)
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_area'', ''{"area": "perdidas"}'')', S));
  perform pg_temp.ok('04.01 el supervisor no fija el área (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cargo'', ''{"cargo": "Operario"}'')', S));
  perform pg_temp.ok('04.02 el supervisor no fija el cargo (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_area'', ''{"area": "perdidas"}'')', A));
  perform pg_temp.ok('04.03 el administrador fija el área', pg_temp.err(r) = 'OK' and campo.f_area_vigente('ztcom.op1@emdupar.gov.co') = 'perdidas', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_area'', ''{"area": "perdidas"}'')', A));
  perform pg_temp.ok('04.04 la misma área otra vez: 55000', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cargo'', ''{"cargo": "ZTCOM Operario de pérdidas"}'')', A));
  perform pg_temp.ok('04.05 el administrador fija el cargo con la ruta nueva', pg_temp.err(r) = 'OK' and campo.f_cargo_vigente('ztcom.op1@emdupar.gov.co') = 'ZTCOM Operario de pérdidas', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_cambiar(%s, ''ztcom.op2@emdupar.gov.co'', ''fijar_cargo'', null, ''ZTCOM Operario antiguo'')', A));
  perform pg_temp.ok('04.06 la RPC publicada (la que usa la Edge de hoy) sigue funcionando igual', pg_temp.err(r) = 'OK' and campo.f_cargo_vigente('ztcom.op2@emdupar.gov.co') = 'ZTCOM Operario antiguo', r::text);

  -- 05: catálogos (solo administrador)
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "crear", "nombre": "ZTCOM Área de Prueba"}'')', S));
  perform pg_temp.ok('05.01 el supervisor no edita catálogos (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "crear", "nombre": "ZTCOM Área de Prueba"}'')', A));
  perform pg_temp.ok('05.02 crear un área: el servidor genera el código', r ->> 'codigo' = 'ztcom_area_de_prueba', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "crear", "nombre": "ztcom área de prueba"}'')', A));
  perform pg_temp.ok('05.03 nombre repetido: 55000 con texto', pg_temp.err(r) = '55000' and r ->> 'msg' = 'Ya existe un área con ese nombre', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "actividad", "tipo": "crear", "nombre": "ZTCOM Toma de lectura especial"}'')', A));
  perform pg_temp.ok('05.04 crear una actividad', r ->> 'codigo' = 'ztcom_toma_de_lectura_especial', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op3@emdupar.gov.co'', ''fijar_area'', ''{"area": "ztcom_area_de_prueba"}'')', A));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op3@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "ztcom_toma_de_lectura_especial"}'')', S));
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "desactivar", "codigo": "ztcom_area_de_prueba"}'')', A));
  perform pg_temp.ok('05.05 desactivar exige motivo', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "desactivar", "codigo": "ztcom_area_de_prueba", "motivo": "ZTCOM área de prueba que se retira"}'')', A));
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "actividad", "tipo": "desactivar", "codigo": "ztcom_toma_de_lectura_especial", "motivo": "ZTCOM actividad de prueba que se retira"}'')', A));
  p := pg_temp.persona(pg_temp.rpc('public.geoportal_campo_personal(' || S || ')'), 'ztcom.op3@emdupar.gov.co');
  perform pg_temp.ok('05.06 lo desactivado sigue en la persona con activa: false', p -> 'area' = '{"codigo": "ztcom_area_de_prueba", "nombre": "ZTCOM Área de Prueba", "activa": false}'::jsonb
    and exists (select 1 from jsonb_array_elements(p -> 'actividades') x where x ->> 'codigo' = 'ztcom_toma_de_lectura_especial' and x -> 'activa' = 'false'::jsonb), left(p::text, 500));
  r := pg_temp.rpc('public.geoportal_campo_personal(' || S || ')');
  perform pg_temp.ok('05.07 y no sale en los catálogos para asignar', not exists (select 1 from jsonb_array_elements(r -> 'areas') x where x ->> 'codigo' = 'ztcom_area_de_prueba')
    and not exists (select 1 from jsonb_array_elements(r -> 'actividades') x where x ->> 'codigo' = 'ztcom_toma_de_lectura_especial'));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_area'', ''{"area": "ztcom_area_de_prueba"}'')', A));
  perform pg_temp.ok('05.08 asignar un área desactivada: 400 con texto', r ->> 'msg' = 'Esa área está desactivada', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''asignar_actividad'', ''{"actividad": "ztcom_toma_de_lectura_especial"}'')', S));
  perform pg_temp.ok('05.09 asignar una actividad desactivada: 400 con texto', r ->> 'msg' = 'Esa actividad está desactivada', r::text);
  r := pg_temp.rpc('public.geoportal_campo_catalogos(' || SA || ')');
  perform pg_temp.ok('05.10 catalogos trae también las inactivas', exists (select 1 from jsonb_array_elements(r -> 'areas') x where x ->> 'codigo' = 'ztcom_area_de_prueba' and x -> 'activa' = 'false'::jsonb), left(r::text, 200));
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%s, ''{"catalogo": "area", "tipo": "activar", "codigo": "ztcom_area_de_prueba"}'')', A));
  perform pg_temp.ok('05.11 activar de nuevo', pg_temp.err(r) = 'OK' and (select activa from campo.areas_comercial where codigo = 'ztcom_area_de_prueba'), r::text);

  -- 06: quién puede hacer la actividad X
  r := pg_temp.rpc('public.geoportal_campo_personal_actividad(' || SA || ', ''suspension'')');
  perform pg_temp.ok('06.01 «quién puede» suspensión: op1 y op3 por cuadrilla, op2 propia (solo ZTCOM)',
    (select jsonb_object_agg(x ->> 'email', x ->> 'origen') from jsonb_array_elements(r -> 'personas') x where x ->> 'email' like 'ztcom.%')
      = '{"ztcom.op1@emdupar.gov.co": "cuadrilla", "ztcom.op2@emdupar.gov.co": "propia", "ztcom.op3@emdupar.gov.co": "cuadrilla"}'::jsonb, left(r::text, 500));
  perform pg_temp.ok('06.02 con la cuadrilla de cada uno', (select x -> 'cuadrilla' ->> 'nombre' from jsonb_array_elements(r -> 'personas') x where x ->> 'email' = 'ztcom.op3@emdupar.gov.co') = 'ZTCOM Sur Oriente'
    and (select x -> 'cuadrilla' from jsonb_array_elements(r -> 'personas') x where x ->> 'email' = 'ztcom.op2@emdupar.gov.co') = 'null'::jsonb);
  r := pg_temp.rpc('public.geoportal_campo_personal_actividad(' || SA || ', ''no_existe'')');
  perform pg_temp.ok('06.03 una actividad que no existe: 400', pg_temp.err(r) = '22023', r::text);

  -- 07: desactivar cuadrilla, sacar personas
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "desactivar", "cuadrilla_id": %s, "motivo": "ZTCOM se cierra la cuadrilla"}'')', S, c1));
  perform pg_temp.ok('07.01 no se desactiva una cuadrilla con miembros: 55000 con cuántos', pg_temp.err(r) = '55000' and r ->> 'msg' = 'La cuadrilla tiene 1 miembro: sáquelo antes de desactivarla', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": null}'')', S));
  perform pg_temp.ok('07.02 sacar a alguien de la cuadrilla exige motivo', pg_temp.err(r) = '22023' and r ->> 'msg' like 'Escriba el motivo%', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": null, "motivo": "ZTCOM pasa a trabajar sin cuadrilla"}'')', S));
  p := pg_temp.persona(pg_temp.rpc('public.geoportal_campo_personal(' || S || ')'), 'ztcom.op1@emdupar.gov.co');
  perform pg_temp.ok('07.03 al salir pierde las heredadas y conserva las propias', pg_temp.err(r) = 'OK' and p -> 'cuadrilla' = 'null'::jsonb
    and (select jsonb_agg(x ->> 'codigo') from jsonb_array_elements(p -> 'actividades') x) = '["lectura"]'::jsonb, left(p::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op1@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": null, "motivo": "ZTCOM otra vez sin cuadrilla"}'')', S));
  perform pg_temp.ok('07.04 sacarla otra vez: 55000', pg_temp.err(r) = '55000' and r ->> 'msg' = 'No está en ninguna cuadrilla', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "desactivar", "cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('07.05 desactivar exige motivo', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "desactivar", "cuadrilla_id": %s, "motivo": "ZTCOM se cierra la cuadrilla"}'')', S, c1));
  perform pg_temp.ok('07.06 sin miembros sí se desactiva (no se borra)', pg_temp.err(r) = 'OK' and (select not activa from campo.cuadrillas where id = c1), r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%s, ''ztcom.op2@emdupar.gov.co'', ''fijar_cuadrilla'', ''{"cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('07.07 meter a alguien en una cuadrilla desactivada: 400 con texto', r ->> 'msg' = 'Esa cuadrilla está desactivada', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "agregar_actividad", "cuadrilla_id": %s, "actividad": "lectura"}'')', S, c1));
  perform pg_temp.ok('07.08 agregar actividad a una cuadrilla desactivada: 400', r ->> 'msg' = 'Esa cuadrilla está desactivada', r::text);
  r := pg_temp.rpc('public.geoportal_campo_cuadrillas(' || SA || ')');
  perform pg_temp.ok('07.09 cuadrillas: por omisión solo las activas', not exists (select 1 from jsonb_array_elements(r -> 'cuadrillas') x where (x ->> 'id')::bigint = c1)
    and exists (select 1 from jsonb_array_elements(r -> 'cuadrillas') x where (x ->> 'id')::bigint = c2 and (x ->> 'n_miembros')::int = 1 and x -> 'miembros' -> 0 ->> 'email' = 'ztcom.op3@emdupar.gov.co'
                and x -> 'actividades' = '[{"codigo": "suspension", "nombre": "Suspensión", "activa": true}]'::jsonb), left(r::text, 500));
  r := pg_temp.rpc('public.geoportal_campo_cuadrillas(' || SA || ', ''{"incluir_inactivas": true}'')');
  perform pg_temp.ok('07.10 con incluir_inactivas sale la desactivada', exists (select 1 from jsonb_array_elements(r -> 'cuadrillas') x where (x ->> 'id')::bigint = c1 and x -> 'activa' = 'false'::jsonb));
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%s, ''{"tipo": "activar", "cuadrilla_id": %s}'')', S, c1));
  perform pg_temp.ok('07.11 activar de nuevo', pg_temp.err(r) = 'OK' and (select activa from campo.cuadrillas where id = c1), r::text);

  -- 08: historial
  r := pg_temp.rpc('public.geoportal_campo_historial_personal(' || SA || ', ''{"persona": "ztcom.op1@emdupar.gov.co"}'')');
  perform pg_temp.ok('08.01 historial de la persona: tipos nuevos con valor_codigo, valor_nombre y clave', (select count(*) from jsonb_array_elements(r -> 'eventos') x
     where x ->> 'tipo_evento' in ('fijar_cuadrilla', 'asignar_actividad', 'quitar_actividad', 'fijar_area') and x ? 'valor_codigo' and x ->> 'clave' like 'p:%') = 6
    and exists (select 1 from jsonb_array_elements(r -> 'eventos') x where x ->> 'tipo_evento' = 'fijar_area' and x ->> 'valor_nombre' = 'Pérdidas' and x -> 'vigente' = 'true'::jsonb), left(r::text, 300));
  perform pg_temp.ok('08.02 vigente: el último por grupo (la cuadrilla vigente es la salida)', (select x -> 'vigente' from jsonb_array_elements(r -> 'eventos') x where x ->> 'tipo_evento' = 'fijar_cuadrilla' order by (x ->> 'id')::bigint desc limit 1) = 'true'::jsonb
    and (select count(*) from jsonb_array_elements(r -> 'eventos') x where x ->> 'tipo_evento' = 'fijar_cuadrilla' and x -> 'vigente' = 'true'::jsonb) = 1);
  r := pg_temp.rpc(format('public.geoportal_campo_historial_personal(%s, ''{"cuadrilla_id": %s}'')', SA, c1));
  perform pg_temp.ok('08.03 historial de la cuadrilla: sus eventos (persona nula) y la entrada y salida de op1',
    (select count(*) from jsonb_array_elements(r -> 'eventos') x where x -> 'persona' = 'null'::jsonb and x ->> 'tipo_evento' like 'cuadrilla\_%' and x ->> 'clave' like 'c:%') = 5
    and (select count(*) from jsonb_array_elements(r -> 'eventos') x where x ->> 'persona' = 'ztcom.op1@emdupar.gov.co') = 2
    and exists (select 1 from jsonb_array_elements(r -> 'eventos') x where x ->> 'tipo_evento' = 'cuadrilla_agregar_actividad' and x ->> 'valor_nombre' = 'Corte')
    and r -> 'siguiente' = 'null'::jsonb, left(r::text, 400));
  r := pg_temp.rpc('public.geoportal_campo_historial_personal(' || SA || ', ''{"cuadrilla_id": 999999999}'')');
  perform pg_temp.ok('08.04 historial de una cuadrilla que no existe: 400', pg_temp.err(r) = '22023', r::text);

  -- 09: nada se borra; los CHECK de producción; permisos
  begin delete from campo.cuadrillas where id = c1; perform pg_temp.ok('09.01 una cuadrilla no se borra', false);
  exception when others then perform pg_temp.ok('09.01 una cuadrilla no se borra', sqlerrm like '%no se borra%', sqlerrm); end;
  begin update campo.areas_comercial set codigo = 'ztcom_otro' where codigo = 'ztcom_area_de_prueba'; perform pg_temp.ok('09.02 el código de un área no cambia', false);
  exception when others then perform pg_temp.ok('09.02 el código de un área no cambia', sqlerrm like '%no cambian%', sqlerrm); end;
  begin delete from campo.cuadrilla_eventos where cuadrilla_id = c1; perform pg_temp.ok('09.03 los eventos de cuadrilla son de solo agregar', false);
  exception when others then perform pg_temp.ok('09.03 los eventos de cuadrilla son de solo agregar', sqlerrm like '%solo agregar%', sqlerrm); end;
  begin truncate campo.actividades; perform pg_temp.ok('09.04 el catálogo de actividades no se vacía', false);
  exception when others then perform pg_temp.ok('09.04 el catálogo de actividades no se vacía', sqlerrm like '%no se borra%', sqlerrm); end;
  begin insert into campo.personal_eventos (persona, tipo_evento, autor) values ('ztcom.op1@emdupar.gov.co', 'fijar_area', 'ztcom.adm@emdupar.gov.co'); perform pg_temp.ok('09.05 CHECK: fijar_area sin valor', false);
  exception when check_violation then perform pg_temp.ok('09.05 CHECK: fijar_area sin valor', true); end;
  begin insert into campo.personal_eventos (persona, tipo_evento, valor, autor) values ('ztcom.op1@emdupar.gov.co', 'fijar_cuadrilla', 'abc', 'ztcom.adm@emdupar.gov.co'); perform pg_temp.ok('09.06 CHECK: cuadrilla no numérica', false);
  exception when check_violation then perform pg_temp.ok('09.06 CHECK: cuadrilla no numérica', true); end;
  perform pg_temp.ok('09.07 las 6 RPC nuevas: solo service_role las ejecuta', (select bool_and(has_function_privilege('service_role', f, 'execute') and not has_function_privilege('anon', f, 'execute')
      and not has_function_privilege('authenticated', f, 'execute')) from unnest(array['public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)', 'public.geoportal_campo_cuadrillas(text,jsonb,text)',
      'public.geoportal_campo_cuadrilla_cambiar(text,jsonb,text)', 'public.geoportal_campo_catalogos(text,text)', 'public.geoportal_campo_catalogo_cambiar(text,jsonb,text)', 'public.geoportal_campo_personal_actividad(text,text,text)']) f));
  perform pg_temp.ok('09.08 las funciones internas nuevas: nadie fuera del dueño', (select bool_and(not has_function_privilege(r_, f, 'execute')) from unnest(array['campo.f_quien_puede(text)', 'campo.f_actividades_persona(text)',
      'campo.f_persona_comercial(text)', 'campo.f_miembros_cuadrillas()', 'campo.f_motivo_personal(text,boolean)']) f, unnest(array['anon', 'authenticated', 'service_role']) r_));
  perform pg_temp.ok('09.09 las tablas nuevas: sin permisos para anon, authenticated ni service_role', (select bool_and(not has_table_privilege(r_, t, 'select') and not has_table_privilege(r_, t, 'insert'))
      from unnest(array['campo.areas_comercial', 'campo.actividades', 'campo.catalogo_eventos', 'campo.cuadrillas', 'campo.cuadrilla_eventos']) t, unnest(array['anon', 'authenticated', 'service_role']) r_));
  perform pg_temp.ok('09.10 las tablas nuevas tienen RLS', (select bool_and(relrowsecurity) from pg_class where oid in ('campo.areas_comercial'::regclass, 'campo.actividades'::regclass, 'campo.catalogo_eventos'::regclass,
      'campo.cuadrillas'::regclass, 'campo.cuadrilla_eventos'::regclass)));
  if to_regprocedure('redes.f_funciones_sin_where()') is not null then
    execute 'select count(*) from redes.f_funciones_sin_where()' into v;
  else v := '0'; end if;
  perform pg_temp.ok('09.11 ninguna función con DELETE o UPDATE sin WHERE: redes.f_funciones_sin_where (si existe) y la misma regla sobre campo y geoportal_campo_*',
    v = '0' and (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0, 'redes: ' || v);
  perform pg_temp.ok('09.12 la auditoría registró los cambios de las pruebas', (select count(*) from public.geoportal_auditoria where email like 'ztcom.%' and accion like 'campo\_%') >= 25);

  -- 10: tiempo (Personal completa como supervisor)
  t0 := clock_timestamp();
  r := pg_temp.rpc('public.geoportal_campo_personal(' || S || ')');
  perform pg_temp.ok('10.01 Personal completa en menos de 2 s', pg_temp.err(r) = 'OK' and clock_timestamp() - t0 < interval '2 s', (clock_timestamp() - t0)::text);
end $$;

do $$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from zt_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $$;
