-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · ENSAYO (termina en ERROR esperado; no deja nada) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · 05 — GUARDIA (se detiene sin cambiar nada si la base no es la publicada el 21-nov 19:45)
-- Huellas: campo 3437a83d… (TODAS sus funciones y las public.geoportal_campo_*), acta 111506c6…, y las md5 de las dos funciones que se reemplazan.
-- =====================================================================
do $$
declare v text;
begin
  if to_regprocedure('campo.f_supervisor_comercial(text)') is not null then
    raise exception 'El cambio de cargo y área por el supervisor ya parece aplicado (existe campo.f_supervisor_comercial): use la reversa antes de repetir';
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if coalesce(v, '(ninguna)') is distinct from '3437a83d1d90055c9861b0964c8f8ffb' then
    raise exception 'Las funciones de campo no son las publicadas el 21-nov 19:45 (huella 3437a83d1d90055c9861b0964c8f8ffb; hay %): deténgase y avise', v;
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%');
  if coalesce(v, '(ninguna)') is distinct from '111506c690249ad3b56ebf572566434c' then
    raise exception 'Las funciones del acta no son las publicadas (huella 111506c690249ad3b56ebf572566434c; hay %): deténgase y avise', v;
  end if;
  if md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)'))) is distinct from 'fc362a2894e064767cfca039fa5ed299'
     or md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal(text,jsonb,text)'))) is distinct from '7028ce4016505ed5fd8ae706db91464c' then
    raise exception 'geoportal_campo_personal_fijar o geoportal_campo_personal no son las publicadas el 21-nov: deténgase y avise';
  end if;
end $$;

-- =====================================================================
-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · 20 — FUNCIÓN INTERNA NUEVA (sin permisos para los roles de la API; la usa la RPC SECURITY DEFINER)
-- =====================================================================
-- ¿Es supervisor de Comercial? Quien tenga dashboard_campo o dashboard_acta en una cuenta activa que no sea de administrador (el mismo criterio del «perfil»
-- que ya muestra geoportal_campo_personal). Su área, su cargo y sus asignaciones (formularios, cuadrilla y actividades) solo los cambia el administrador (David, 22-nov).
create function campo.f_supervisor_comercial(p_email text) returns boolean
language sql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
  select exists (select 1 from public.geoportal_lista_blanca lb where lb.email = lower(btrim(coalesce(p_email, ''))) and lb.activo and lb.rol <> 'admin'
                   and (coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_dashboard_acta, false)))
$$;

-- =====================================================================
-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · 26 — REEMPLAZOS (misma firma; los textos de partida son los publicados el 21-nov, paquete (a))
-- · geoportal_campo_personal_fijar (fc362a28…): el supervisor de campo cambia SOLO a los operarios (área, cargo, formularios, cuadrilla y actividades); a un
--   supervisor, a un administrador o a sí mismo, no (42501 con texto).
-- · geoportal_campo_personal (7028ce40…): puede.cargo y puede.area pasan a v_sup; cada persona trae «puede_area_cargo» y «puede_asignar» (campos nuevos; la respuesta de hoy no cambia).
-- La reversa vuelve a los dos textos publicados.
-- =====================================================================

create or replace function public.geoportal_campo_personal_fijar(p_solicitante text, p_persona text, p_tipo text, p_datos jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; v_admin boolean; d jsonb := coalesce(p_datos, '{}'::jsonb); v_p text := lower(btrim(coalesce(p_persona, '')));
        v_f text; v_c text; v_m text; v_val text; v_cuad bigint; v_ant bigint; v_q campo.cuadrillas; v_a campo.actividades; v_ar campo.areas_comercial; v_id bigint;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  v_admin := public.geoportal_es_admin(v_email);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del cambio no tienen el formato esperado'); end if;
  if p_tipo is null or p_tipo not in ('fijar_cargo', 'fijar_area', 'fijar_cuadrilla', 'asignar_formulario', 'quitar_formulario', 'asignar_actividad', 'quitar_actividad') then
    perform campo.f_error('El cambio debe ser fijar_cargo, fijar_area, fijar_cuadrilla, asignar_formulario, quitar_formulario, asignar_actividad o quitar_actividad');
  end if;
  -- 22-nov (David, 11:11 y 11:25): el supervisor de campo (dashboard_campo; ya lo exige f_autorizar_supervision) cambia SOLO a los operarios: área, cargo,
  -- formularios, cuadrilla (poner o sacar) y actividades. Lo de un supervisor (dashboard_campo o dashboard_acta, también él mismo) y lo de un administrador
  -- lo hace el administrador. Crear, renombrar y desactivar cuadrillas no cambia (geoportal_campo_cuadrilla_cambiar).
  if not v_admin then
    if public.geoportal_es_admin(v_p) then
      perform campo.f_error(case when p_tipo in ('fijar_cargo', 'fijar_area') then 'El área y el cargo de un administrador no se cambian desde Personal'
                                 else 'Las asignaciones de un administrador no se hacen desde Personal' end, '42501');
    end if;
    if campo.f_supervisor_comercial(v_p) then
      perform campo.f_error(case when p_tipo in ('fijar_cargo', 'fijar_area') then 'El área y el cargo de un supervisor los cambia el administrador'
                                 else 'Las asignaciones de un supervisor las hace el administrador' end, '42501');
    end if;
  end if;
  if not campo.f_persona_comercial(v_p) then perform campo.f_error('Esa persona no tiene acceso activo a Formularios de campo ni al acta'); end if;
  if v_p = v_email then perform campo.f_error('No puede cambiar su propia ficha'); end if;
  perform pg_advisory_xact_lock(hashtext('campo_personal:' || v_p));
  v_m := campo.f_motivo_personal(d ->> 'motivo', p_tipo in ('quitar_formulario', 'quitar_actividad'));
  if p_tipo = 'fijar_cargo' then
    v_c := nullif(btrim(coalesce(d ->> 'cargo', '')), '');
    if v_c is null or length(v_c) < 2 or length(v_c) > 80 then perform campo.f_error('El cargo debe tener entre 2 y 80 caracteres'); end if;
    if v_c is not distinct from campo.f_cargo_vigente(v_p) then perform campo.f_error('Ese ya es el cargo vigente', '55000'); end if;
  elsif p_tipo = 'fijar_area' then
    select * into v_ar from campo.areas_comercial a where a.codigo = nullif(btrim(coalesce(d ->> 'area', '')), '');
    if v_ar.codigo is null then perform campo.f_error('Esa área no existe'); end if;
    if not v_ar.activa then perform campo.f_error('Esa área está desactivada'); end if;
    if v_ar.codigo is not distinct from campo.f_area_vigente(v_p) then perform campo.f_error('Ya tiene esa área', '55000'); end if;
    v_val := v_ar.codigo;
  elsif p_tipo = 'fijar_cuadrilla' then
    begin v_cuad := nullif(d ->> 'cuadrilla_id', '')::bigint; exception when others then perform campo.f_error('La cuadrilla no es válida'); end;
    v_ant := campo.f_cuadrilla_vigente(v_p);
    if v_cuad is not null then
      perform pg_advisory_xact_lock(hashtext('campo_cuadrilla:' || v_cuad));
      select * into v_q from campo.cuadrillas q where q.id = v_cuad;
      if v_q.id is null then perform campo.f_error('Esa cuadrilla no existe'); end if;
      if not v_q.activa then perform campo.f_error('Esa cuadrilla está desactivada'); end if;
    end if;
    if v_cuad is not distinct from v_ant then
      perform campo.f_error(case when v_cuad is null then 'No está en ninguna cuadrilla' else 'Ya está en esa cuadrilla' end, '55000');
    end if;
    if v_ant is not null and v_m is null then perform campo.f_error('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
    v_val := v_cuad::text;
  elsif p_tipo in ('asignar_formulario', 'quitar_formulario') then
    v_f := nullif(btrim(coalesce(d ->> 'formulario', '')), '');
    if v_f is null then perform campo.f_error('Indique el formulario'); end if;
    if p_tipo = 'asignar_formulario' then
      if not exists (select 1 from campo.f_formularios_personal() x where x.clave = v_f) then perform campo.f_error('Ese formulario no existe o está desactivado'); end if;
      if v_f = any (campo.f_formularios_asignados(v_p)) then perform campo.f_error('Ya tiene asignado ese formulario', '55000'); end if;
    elsif not (v_f = any (campo.f_formularios_asignados(v_p))) then perform campo.f_error('No tiene asignado ese formulario', '55000');
    end if;
  else
    select * into v_a from campo.actividades a where a.codigo = nullif(btrim(coalesce(d ->> 'actividad', '')), '');
    if v_a.codigo is null then perform campo.f_error('Esa actividad no existe'); end if;
    if p_tipo = 'asignar_actividad' then
      if not v_a.activa then perform campo.f_error('Esa actividad está desactivada'); end if;
      if v_a.codigo = any (campo.f_actividades_propias(v_p)) then perform campo.f_error('Ya tiene esa actividad', '55000'); end if;
    elsif not (v_a.codigo = any (campo.f_actividades_propias(v_p))) then
      if exists (select 1 from campo.f_actividades_persona(v_p) x where x.codigo = v_a.codigo) then
        perform campo.f_error('Esa actividad viene de la cuadrilla ' || (select q.nombre from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(v_p)) || ': se quita en la cuadrilla', '55000');
      end if;
      perform campo.f_error('No tiene esa actividad', '55000');
    end if;
    v_val := v_a.codigo;
  end if;
  insert into campo.personal_eventos (persona, tipo_evento, formulario, cargo, valor, motivo, autor) values (v_p, p_tipo, v_f, v_c, v_val, v_m, v_email) returning id into v_id;
  perform campo.f_auditar(v_email, 'campo_personal_' || p_tipo, v_p, jsonb_build_object('evento', v_id, 'formulario', v_f, 'valor', v_val, 'cargo', v_c is not null), p_ip);
  return jsonb_build_object('id', v_id, 'cambio', true);
end $$;

create or replace function public.geoportal_campo_personal(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_buscar text; v_admin boolean; v_sup boolean;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  v_buscar := nullif(btrim(coalesce(f ->> 'buscar', '')), '');
  v_admin := public.geoportal_es_admin(v_email);
  v_sup := v_admin or public.geoportal_puede(v_email, 'dashboard_campo');
  return jsonb_build_object(
    'puede_editar', v_admin,
    'yo', v_email,
    'puede', jsonb_build_object('cargo', v_sup, 'area', v_sup, 'cuadrilla', v_sup, 'cuadrillas', v_sup, 'actividades', v_sup, 'formularios', v_sup, 'catalogos', v_admin),
    'formularios', (select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'nombre', x.nombre, 'grupo', x.grupo) order by x.orden, x.clave), '[]'::jsonb) from campo.f_formularios_personal() x),
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre) order by a.orden, a.codigo), '[]'::jsonb) from campo.areas_comercial a where a.activa),
    'cuadrillas', (select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nombre', q.nombre) order by lower(q.nombre), q.id), '[]'::jsonb) from campo.cuadrillas q where q.activa),
    'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre) order by a.orden, a.codigo), '[]'::jsonb) from campo.actividades a where a.activa),
    'personas', (select coalesce(jsonb_agg(p order by p ->> 'nombre_orden', p ->> 'email'), '[]'::jsonb) from (
      select jsonb_build_object('email', lb.email, 'nombre', nullif(btrim(lb.nombre), ''), 'nombre_orden', lower(coalesce(nullif(btrim(lb.nombre), ''), lb.email)),
               'perfil', case when coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_dashboard_acta, false) then 'supervisor' else 'operario' end,
               'permisos', jsonb_build_object('campo', coalesce(lb.ver_campo, false), 'dashboard_campo', coalesce(lb.ver_dashboard_campo, false),
                                              'acta', coalesce(lb.ver_acta, false), 'dashboard_acta', coalesce(lb.ver_dashboard_acta, false)),
               'cargo', campo.f_cargo_vigente(lb.email),
               'formularios', to_jsonb(campo.f_formularios_asignados(lb.email)),
               'sin_asignacion', cardinality(campo.f_formularios_asignados(lb.email)) = 0,
               'ultimo_cambio', (select max(e.creado_en) from campo.personal_eventos e where e.persona = lb.email),
               'propia', lb.email = v_email,
               -- 22-nov: ¿quien consulta puede cambiarle el área y el cargo a esta persona? (el administrador a todos; el supervisor de campo solo a los operarios; nadie a sí mismo)
               'puede_area_cargo', lb.email <> v_email and (v_admin or (v_sup and not (coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_dashboard_acta, false)))),
               -- 22-nov (11:25): y lo mismo para formularios, cuadrilla y actividades (hoy el mismo valor que puede_area_cargo)
               'puede_asignar', lb.email <> v_email and (v_admin or (v_sup and not (coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_dashboard_acta, false)))),
               'area', (select jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'activa', a.activa) from campo.areas_comercial a where a.codigo = campo.f_area_vigente(lb.email)),
               'cuadrilla', (select jsonb_build_object('id', q.id, 'nombre', q.nombre, 'activa', q.activa) from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(lb.email)),
               'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'nombre', coalesce(a.nombre, x.codigo), 'activa', coalesce(a.activa, false), 'origen', x.origen)
                                                         order by a.orden, x.codigo), '[]'::jsonb)
                                 from campo.f_actividades_persona(lb.email) x left join campo.actividades a on a.codigo = x.codigo)) as p
        from public.geoportal_lista_blanca lb
       where lb.activo and lb.rol <> 'admin'
         and (coalesce(lb.ver_campo, false) or coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_acta, false) or coalesce(lb.ver_dashboard_acta, false))
         and (v_buscar is null or lb.email ilike '%' || v_buscar || '%' or coalesce(lb.nombre, '') ilike '%' || v_buscar || '%')) s));
end $$;

-- =====================================================================
-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · 40 — PERMISOS
-- La función nueva es interna: se revoca todo y no se le da a nadie (la llama la RPC, que es SECURITY DEFINER).
-- Las dos RPC reemplazadas conservan sus permisos publicados (create or replace no los cambia: solo service_role).
-- =====================================================================
revoke all on function campo.f_supervisor_comercial(text) from public, anon, authenticated, service_role;

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
  perform pg_temp.ok('07.03 la huella del acta no cambió (111506c690249ad3b56ebf572566434c)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '111506c690249ad3b56ebf572566434c');
  perform pg_temp.ok('07.04 ninguna función de campo con DELETE o UPDATE sin WHERE', (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0);
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

rollback;
