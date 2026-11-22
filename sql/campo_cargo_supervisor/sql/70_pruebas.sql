-- =====================================================================
-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · 70 — PRUEBAS (dentro del ensayo; todo se deshace al final con el ERROR esperado)
-- Datos propios con prefijo ZTCAR (correos ztcar.*@emdupar.gov.co, áreas «ZTCAR …»). Cada prueba cuenta SOLO sus filas.
-- Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- Sin tablas temporales que se borren al confirmar (regla de David, 21-nov): la tabla de resultados se deshace con el ERROR esperado del final.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztcar_res (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztcar_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
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
create function pg_temp.fijar(p_sol text, p_per text, p_tipo text, p_datos text) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_personal_fijar(%L, %L, %L, %L::jsonb)', p_sol, p_per, p_tipo, p_datos)) $f$;
create function pg_temp.eventos(p_per text) returns bigint language sql as $f$
  select count(*) from campo.personal_eventos e where e.persona = p_per and e.tipo_evento in ('fijar_cargo', 'fijar_area') $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta) values
  ('ztcar.adm@emdupar.gov.co', 'ZTCAR Admin', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('ztcar.adm2@emdupar.gov.co', 'ZTCAR Admin 2', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('ztcar.sup@emdupar.gov.co', 'ZTCAR Supervisor comercial', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, true, true),
  ('ztcar.supcampo@emdupar.gov.co', 'ZTCAR Supervisor de campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('ztcar.supacta@emdupar.gov.co', 'ZTCAR Supervisor de actas', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, true),
  ('ztcar.op1@emdupar.gov.co', 'ZTCAR Operario 1', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, true, false),
  ('ztcar.op2@emdupar.gov.co', 'ZTCAR Operario 2', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false);

do $$
declare
  A text := 'ztcar.adm@emdupar.gov.co'; S text := 'ztcar.sup@emdupar.gov.co'; SC text := 'ztcar.supcampo@emdupar.gov.co'; SA text := 'ztcar.supacta@emdupar.gov.co';
  O1 text := 'ztcar.op1@emdupar.gov.co'; O2 text := 'ztcar.op2@emdupar.gov.co'; A2 text := 'ztcar.adm2@emdupar.gov.co';
  r jsonb; p jsonb; t0 timestamptz; n0 bigint; Q bigint; M text := 'Las asignaciones de un supervisor las hace el administrador'; MA text := 'Las asignaciones de un administrador no se hacen desde Personal';
begin
  -- 00: áreas de prueba (las crea el administrador, como siempre)
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%L, %L::jsonb)', A, '{"catalogo": "area", "tipo": "crear", "nombre": "ZTCAR Facturación"}'));
  perform pg_temp.ok('00.01 área de prueba ZTCAR Facturación', r ->> 'codigo' = 'ztcar_facturacion', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%L, %L::jsonb)', A, '{"catalogo": "area", "tipo": "crear", "nombre": "ZTCAR PQR"}'));
  perform pg_temp.ok('00.02 área de prueba ZTCAR PQR', r ->> 'codigo' = 'ztcar_pqr', r::text);

  -- 01: el supervisor de campo cambia área y cargo de un OPERARIO (sí)
  r := pg_temp.fijar(S, O1, 'fijar_area', '{"area": "ztcar_facturacion"}');
  perform pg_temp.ok('01.01 el supervisor fija el área de un operario', pg_temp.err(r) = 'OK' and campo.f_area_vigente(O1) = 'ztcar_facturacion', r::text);
  r := pg_temp.fijar(S, O1, 'fijar_area', '{"area": "ztcar_pqr", "motivo": "ZTCAR rota a revisiones de PQR"}');
  perform pg_temp.ok('01.02 y lo rota a otra área (hoy Facturación, mañana PQR)', pg_temp.err(r) = 'OK' and campo.f_area_vigente(O1) = 'ztcar_pqr', r::text);
  r := pg_temp.fijar(S, O1, 'fijar_cargo', '{"cargo": "ZTCAR Lector y repartidor"}');
  perform pg_temp.ok('01.03 el supervisor fija el cargo de un operario', pg_temp.err(r) = 'OK' and campo.f_cargo_vigente(O1) = 'ZTCAR Lector y repartidor', r::text);
  r := pg_temp.fijar(S, O1, 'fijar_cargo', '{"cargo": "ZTCAR Lector y repartidor"}');
  perform pg_temp.ok('01.04 el mismo cargo otra vez: 55000 (como hoy)', pg_temp.err(r) = '55000' and r ->> 'msg' = 'Ese ya es el cargo vigente', r::text);
  r := pg_temp.fijar(S, O1, 'fijar_cargo', '{"cargo": "Z"}');
  perform pg_temp.ok('01.05 cargo de 1 carácter: 22023 con texto (como hoy)', pg_temp.err(r) = '22023' and r ->> 'msg' = 'El cargo debe tener entre 2 y 80 caracteres', r::text);
  r := pg_temp.fijar(SC, O2, 'fijar_cargo', '{"cargo": "ZTCAR Revisor"}');
  perform pg_temp.ok('01.06 el supervisor con solo dashboard_campo (sin acta) también puede', pg_temp.err(r) = 'OK' and campo.f_cargo_vigente(O2) = 'ZTCAR Revisor', r::text);
  perform pg_temp.ok('01.07 los eventos quedan con el supervisor como autor (3 de O1, 1 de O2)',
    (select count(*) from campo.personal_eventos e where e.persona = O1 and e.autor = S and e.tipo_evento in ('fijar_area', 'fijar_cargo')) = 3
    and (select count(*) from campo.personal_eventos e where e.persona = O2 and e.autor = SC and e.tipo_evento = 'fijar_cargo') = 1);
  perform pg_temp.ok('01.08 y la auditoría los registra (campo_personal_fijar_area / _cargo)',
    (select count(*) from public.geoportal_auditoria a where a.email in (S, SC) and a.referencia in (O1, O2) and a.accion in ('campo_personal_fijar_area', 'campo_personal_fijar_cargo')) = 4);

  -- 02: de otro SUPERVISOR (dashboard_campo o dashboard_acta) o de un ADMINISTRADOR (no, con mensaje claro)
  r := pg_temp.fijar(S, SC, 'fijar_area', '{"area": "ztcar_pqr"}');
  perform pg_temp.ok('02.01 área de otro supervisor de campo: 403 «… los cambia el administrador»', pg_temp.err(r) = '42501' and r ->> 'msg' = 'El área y el cargo de un supervisor los cambia el administrador', r::text);
  r := pg_temp.fijar(S, SC, 'fijar_cargo', '{"cargo": "ZTCAR Coordinador"}');
  perform pg_temp.ok('02.02 cargo de otro supervisor de campo: igual', pg_temp.err(r) = '42501' and r ->> 'msg' = 'El área y el cargo de un supervisor los cambia el administrador', r::text);
  r := pg_temp.fijar(S, SA, 'fijar_cargo', '{"cargo": "ZTCAR Coordinador"}');
  perform pg_temp.ok('02.03 cargo de un supervisor de actas (solo dashboard_acta): igual', pg_temp.err(r) = '42501' and r ->> 'msg' = 'El área y el cargo de un supervisor los cambia el administrador', r::text);
  r := pg_temp.fijar(SC, S, 'fijar_area', '{"area": "ztcar_pqr"}');
  perform pg_temp.ok('02.04 el de solo dashboard_campo tampoco toca al supervisor comercial', pg_temp.err(r) = '42501' and r ->> 'msg' = 'El área y el cargo de un supervisor los cambia el administrador', r::text);
  r := pg_temp.fijar(S, A2, 'fijar_cargo', '{"cargo": "ZTCAR Jefe"}');
  perform pg_temp.ok('02.05 cargo de un administrador: 403 con texto', pg_temp.err(r) = '42501' and r ->> 'msg' = 'El área y el cargo de un administrador no se cambian desde Personal', r::text);
  r := pg_temp.fijar(S, A2, 'fijar_area', '{"area": "ztcar_pqr"}');
  perform pg_temp.ok('02.06 área de un administrador: igual', pg_temp.err(r) = '42501' and r ->> 'msg' = 'El área y el cargo de un administrador no se cambian desde Personal', r::text);
  r := pg_temp.fijar(S, S, 'fijar_cargo', '{"cargo": "ZTCAR Autoascenso"}');
  perform pg_temp.ok('02.07 su propio cargo: no', pg_temp.err(r) = '42501', r::text);
  perform pg_temp.ok('02.08 ninguno de los rechazos escribió eventos', pg_temp.eventos(SC) = 0 and pg_temp.eventos(SA) = 0 and pg_temp.eventos(S) = 0 and pg_temp.eventos(A2) = 0);

  -- 03: quien NO es supervisor de campo no cambia área ni cargo
  r := pg_temp.fijar(SA, O1, 'fijar_cargo', '{"cargo": "ZTCAR Otro cargo"}');
  perform pg_temp.ok('03.01 solo dashboard_acta: no cambia el cargo de un operario (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.fijar(SA, O1, 'fijar_area', '{"area": "ztcar_facturacion"}');
  perform pg_temp.ok('03.02 ni el área', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.fijar(O2, O1, 'fijar_cargo', '{"cargo": "ZTCAR Otro cargo"}');
  perform pg_temp.ok('03.03 un operario: no (42501)', pg_temp.err(r) = '42501', r::text);
  perform pg_temp.ok('03.04 y nada cambió', campo.f_cargo_vigente(O1) = 'ZTCAR Lector y repartidor' and campo.f_area_vigente(O1) = 'ztcar_pqr');

  -- 04: el administrador sigue pudiendo con todos los de Comercial (también con los supervisores)
  r := pg_temp.fijar(A, SC, 'fijar_cargo', '{"cargo": "ZTCAR Coordinador de campo"}');
  perform pg_temp.ok('04.01 el administrador cambia el cargo de un supervisor', pg_temp.err(r) = 'OK' and campo.f_cargo_vigente(SC) = 'ZTCAR Coordinador de campo', r::text);
  r := pg_temp.fijar(A, SA, 'fijar_area', '{"area": "ztcar_facturacion"}');
  perform pg_temp.ok('04.02 y el área de un supervisor de actas', pg_temp.err(r) = 'OK' and campo.f_area_vigente(SA) = 'ztcar_facturacion', r::text);
  r := pg_temp.fijar(A, O1, 'fijar_area', '{"area": "ztcar_facturacion", "motivo": "ZTCAR vuelve a Facturación"}');
  perform pg_temp.ok('04.03 y la de un operario', pg_temp.err(r) = 'OK' and campo.f_area_vigente(O1) = 'ztcar_facturacion', r::text);

  -- 05: lo demás de Personal no cambia (formularios, cuadrilla y actividades siguen como se publicó el 21-nov)
  r := pg_temp.fijar(S, O2, 'asignar_formulario', '{"formulario": "acta"}');
  perform pg_temp.ok('05.01 el supervisor asigna formularios a un operario (como hoy)', pg_temp.err(r) = 'OK' and 'acta' = any (campo.f_formularios_asignados(O2)), r::text);
  r := pg_temp.fijar(SA, O2, 'quitar_formulario', '{"formulario": "acta", "motivo": "ZTCAR prueba de retiro de formulario"}');
  perform pg_temp.ok('05.02 el de solo dashboard_acta sigue sin cambiar fichas (como hoy)', pg_temp.err(r) = '42501', r::text);

  -- 09: «solo operarios» también para formularios, cuadrilla y actividades (David, 22-nov 11:25). Crear y desactivar cuadrillas no cambia.
  r := pg_temp.rpc(format('public.geoportal_campo_catalogo_cambiar(%L, %L::jsonb)', A, '{"catalogo": "actividad", "tipo": "crear", "nombre": "ZTCAR Lectura"}'));
  perform pg_temp.ok('09.00 actividad de prueba ZTCAR Lectura', r ->> 'codigo' = 'ztcar_lectura', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%L, %L::jsonb)', S, '{"tipo": "crear", "nombre": "ZTCAR Cuadrilla Norte"}'));
  Q := (r ->> 'id')::bigint;
  perform pg_temp.ok('09.01 el supervisor sigue creando cuadrillas', pg_temp.err(r) = 'OK' and Q is not null, r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%L, %L::jsonb)', S, jsonb_build_object('tipo', 'agregar_actividad', 'cuadrilla_id', Q, 'actividad', 'ztcar_lectura')::text));
  perform pg_temp.ok('09.02 y les agrega actividades', pg_temp.err(r) = 'OK' and 'ztcar_lectura' = any (campo.f_cuadrilla_actividades(Q)), r::text);
  -- a un OPERARIO: sí
  r := pg_temp.fijar(S, O2, 'fijar_cuadrilla', jsonb_build_object('cuadrilla_id', Q)::text);
  perform pg_temp.ok('09.03 pone a un operario en una cuadrilla', pg_temp.err(r) = 'OK' and campo.f_cuadrilla_vigente(O2) = Q, r::text);
  r := pg_temp.fijar(S, O2, 'asignar_actividad', '{"actividad": "ztcar_lectura"}');
  perform pg_temp.ok('09.04 le asigna una actividad propia', pg_temp.err(r) = 'OK' and 'ztcar_lectura' = any (campo.f_actividades_propias(O2)), r::text);
  r := pg_temp.fijar(S, O2, 'quitar_actividad', '{"actividad": "ztcar_lectura", "motivo": "ZTCAR ya la tiene por la cuadrilla"}');
  perform pg_temp.ok('09.05 y se la quita con motivo', pg_temp.err(r) = 'OK' and not ('ztcar_lectura' = any (campo.f_actividades_propias(O2))), r::text);
  -- a otro SUPERVISOR, a un ADMINISTRADOR o a SÍ MISMO: no, con mensaje claro y sin escribir nada
  n0 := (select count(*) from campo.personal_eventos e where e.persona in (SC, SA, A2, S) and e.tipo_evento in ('fijar_cuadrilla', 'asignar_formulario', 'quitar_formulario', 'asignar_actividad', 'quitar_actividad'));
  r := pg_temp.fijar(S, SC, 'fijar_cuadrilla', jsonb_build_object('cuadrilla_id', Q)::text);
  perform pg_temp.ok('09.06 no pone a otro supervisor en una cuadrilla: 403 «Las asignaciones de un supervisor las hace el administrador»', pg_temp.err(r) = '42501' and r ->> 'msg' = M, r::text);
  r := pg_temp.fijar(S, SC, 'asignar_formulario', '{"formulario": "acta"}');
  perform pg_temp.ok('09.07 no le asigna formularios', pg_temp.err(r) = '42501' and r ->> 'msg' = M, r::text);
  r := pg_temp.fijar(S, SC, 'asignar_actividad', '{"actividad": "ztcar_lectura"}');
  perform pg_temp.ok('09.08 ni actividades', pg_temp.err(r) = '42501' and r ->> 'msg' = M, r::text);
  r := pg_temp.fijar(S, SA, 'asignar_formulario', '{"formulario": "acta"}');
  perform pg_temp.ok('09.09 ni al supervisor de actas (solo dashboard_acta)', pg_temp.err(r) = '42501' and r ->> 'msg' = M, r::text);
  perform pg_temp.ok('09.10 a un administrador: cuadrilla, formularios y actividades, 403 «… no se hacen desde Personal»',
    pg_temp.fijar(S, A2, 'fijar_cuadrilla', jsonb_build_object('cuadrilla_id', Q)::text) ->> 'msg' = MA
    and pg_temp.fijar(S, A2, 'asignar_formulario', '{"formulario": "acta"}') ->> 'msg' = MA
    and pg_temp.fijar(S, A2, 'asignar_actividad', '{"actividad": "ztcar_lectura"}') ->> 'msg' = MA);
  perform pg_temp.ok('09.11 a sí mismo: cuadrilla, formularios y actividades, 403',
    pg_temp.err(pg_temp.fijar(S, S, 'fijar_cuadrilla', jsonb_build_object('cuadrilla_id', Q)::text)) = '42501'
    and pg_temp.err(pg_temp.fijar(S, S, 'asignar_formulario', '{"formulario": "acta"}')) = '42501'
    and pg_temp.err(pg_temp.fijar(S, S, 'asignar_actividad', '{"actividad": "ztcar_lectura"}')) = '42501'
    and pg_temp.err(pg_temp.fijar(SC, SC, 'asignar_actividad', '{"actividad": "ztcar_lectura"}')) = '42501');
  perform pg_temp.ok('09.12 ninguno de esos rechazos escribió eventos', (select count(*) from campo.personal_eventos e where e.persona in (SC, SA, A2, S)
    and e.tipo_evento in ('fijar_cuadrilla', 'asignar_formulario', 'quitar_formulario', 'asignar_actividad', 'quitar_actividad')) = n0);
  -- el administrador sigue pudiendo con todos
  r := pg_temp.fijar(A, SC, 'fijar_cuadrilla', jsonb_build_object('cuadrilla_id', Q)::text);
  perform pg_temp.ok('09.13 el administrador pone a un supervisor en la cuadrilla', pg_temp.err(r) = 'OK' and campo.f_cuadrilla_vigente(SC) = Q, r::text);
  r := pg_temp.fijar(A, SC, 'asignar_formulario', '{"formulario": "acta"}');
  perform pg_temp.ok('09.14 y le asigna formularios', pg_temp.err(r) = 'OK' and 'acta' = any (campo.f_formularios_asignados(SC)), r::text);
  -- un supervisor que ya está en una cuadrilla SIGUE apareciendo (el cambio solo decide quién lo cambia)
  perform pg_temp.ok('09.15 f_quien_puede sigue mostrando al supervisor que está en la cuadrilla (y al operario)',
    exists (select 1 from campo.f_quien_puede('ztcar_lectura') x where x.persona = SC and x.cuadrilla_id = Q and x.origen = 'cuadrilla')
    and exists (select 1 from campo.f_quien_puede('ztcar_lectura') x where x.persona = O2 and x.cuadrilla_id = Q));
  perform pg_temp.ok('09.16 y la lista de miembros de la cuadrilla también', (select count(*) from campo.f_miembros_cuadrillas() m where m.cuadrilla_id = Q and m.persona in (SC, O2)) = 2);
  r := pg_temp.rpc(format('public.geoportal_campo_personal_actividad(%L, %L)', S, 'ztcar_lectura'));
  perform pg_temp.ok('09.17 «quién puede» (personal_actividad) del supervisor lo muestra', exists (select 1 from jsonb_array_elements(r -> 'personas') x where x ->> 'email' = SC), left(r::text, 300));
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrillas(%L)', S));
  perform pg_temp.ok('09.18 y la lista de cuadrillas cuenta sus 2 miembros', pg_temp.err(r) = 'OK' and position(SC in r::text) > 0, left(r::text, 300));
  r := pg_temp.fijar(S, SC, 'fijar_cuadrilla', '{"cuadrilla_id": null, "motivo": "ZTCAR sacarlo de la cuadrilla"}');
  perform pg_temp.ok('09.19 el supervisor no lo saca de la cuadrilla (403): eso lo hace el administrador', pg_temp.err(r) = '42501' and r ->> 'msg' = M and campo.f_cuadrilla_vigente(SC) = Q, r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_cuadrilla_cambiar(%L, %L::jsonb)', S, jsonb_build_object('tipo', 'desactivar', 'cuadrilla_id', Q, 'motivo', 'ZTCAR cuadrilla que se retira')::text));
  perform pg_temp.ok('09.20 desactivar una cuadrilla con miembros sigue pidiendo sacarlos antes (como hoy)', pg_temp.err(r) = '55000', r::text);

  -- 06: la lista de Personal le dice a la pantalla qué puede cada quien
  r := pg_temp.rpc(format('public.geoportal_campo_personal(%L)', S));
  perform pg_temp.ok('06.01 supervisor de campo: puede.cargo y puede.area verdaderos; catálogos no', (r #>> '{puede,cargo}')::boolean and (r #>> '{puede,area}')::boolean
    and not (r #>> '{puede,catalogos}')::boolean and not (r ->> 'puede_editar')::boolean, left(r::text, 300));
  perform pg_temp.ok('06.02 puede_area_cargo y puede_asignar: operarios sí; otro supervisor, supervisor de actas y él mismo no',
    (pg_temp.persona(r, O1) ->> 'puede_area_cargo')::boolean and (pg_temp.persona(r, O2) ->> 'puede_area_cargo')::boolean
    and not (pg_temp.persona(r, SC) ->> 'puede_area_cargo')::boolean and not (pg_temp.persona(r, SA) ->> 'puede_area_cargo')::boolean
    and not (pg_temp.persona(r, S) ->> 'puede_area_cargo')::boolean
    and (pg_temp.persona(r, O1) ->> 'puede_asignar')::boolean and not (pg_temp.persona(r, SC) ->> 'puede_asignar')::boolean and not (pg_temp.persona(r, SA) ->> 'puede_asignar')::boolean
    and not (pg_temp.persona(r, S) ->> 'puede_asignar')::boolean);
  r := pg_temp.rpc(format('public.geoportal_campo_personal(%L)', SA));
  perform pg_temp.ok('06.03 solo dashboard_acta: ve Personal, pero puede.cargo falso y nadie editable', not (r #>> '{puede,cargo}')::boolean and not (r #>> '{puede,area}')::boolean
    and not (pg_temp.persona(r, O1) ->> 'puede_area_cargo')::boolean, left(r::text, 300));
  r := pg_temp.rpc(format('public.geoportal_campo_personal(%L)', A));
  perform pg_temp.ok('06.04 administrador: puede con supervisores y operarios', (pg_temp.persona(r, SC) ->> 'puede_area_cargo')::boolean and (pg_temp.persona(r, O1) ->> 'puede_area_cargo')::boolean
    and (r ->> 'puede_editar')::boolean);
  perform pg_temp.ok('06.05 el resto de la respuesta conserva sus campos publicados', r ?& array['puede_editar', 'yo', 'puede', 'formularios', 'areas', 'cuadrillas', 'actividades', 'personas']
    and pg_temp.persona(r, O1) ?& array['email', 'nombre', 'perfil', 'permisos', 'cargo', 'formularios', 'sin_asignacion', 'ultimo_cambio', 'propia', 'area', 'cuadrilla', 'actividades']);

  -- 07: higiene
  perform pg_temp.ok('07.01 la función nueva no la ejecuta ningún rol de la API',
    not has_function_privilege('service_role', 'campo.f_supervisor_comercial(text)', 'execute') and not has_function_privilege('authenticated', 'campo.f_supervisor_comercial(text)', 'execute')
    and not has_function_privilege('anon', 'campo.f_supervisor_comercial(text)', 'execute'));
  perform pg_temp.ok('07.02 las dos RPC siguen solo para service_role',
    has_function_privilege('service_role', 'public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)', 'execute') and has_function_privilege('service_role', 'public.geoportal_campo_personal(text,jsonb,text)', 'execute')
    and not has_function_privilege('anon', 'public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)', 'execute')
    and not has_function_privilege('anon', 'public.geoportal_campo_personal(text,jsonb,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_personal(text,jsonb,text)', 'execute'));
  perform pg_temp.ok('07.03 la huella del acta no cambió ({{HUELLA_ACTA}})', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '{{HUELLA_ACTA}}');
  perform pg_temp.ok('07.04 ninguna función de campo con DELETE o UPDATE sin WHERE', {{SIN_WHERE_CAMPO}} = 0);
  perform pg_temp.ok('07.05 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);

  -- 08: tiempo
  t0 := clock_timestamp();
  r := pg_temp.rpc(format('public.geoportal_campo_personal(%L)', S));
  perform pg_temp.ok('08.01 Personal completa en menos de 2 s', pg_temp.err(r) = 'OK' and clock_timestamp() - t0 < interval '2 s', (clock_timestamp() - t0)::text);
end $$;

do $$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztcar_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $$;
