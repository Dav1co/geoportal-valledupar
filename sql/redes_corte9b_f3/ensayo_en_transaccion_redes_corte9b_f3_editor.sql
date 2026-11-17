begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 (capa «Flujo del agua (modelo)») · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- · Presupone la Fase 2 del 9b publicada: huella del conjunto de funciones de redes 7f9c0157c47e371e1d3d87ef6bda847b.
-- · SOLO AGREGA: no reemplaza ninguna función. Solo base de datos: las rutas de la Edge y la pantalla del geovisor son del Code B.
-- · El flujo es de MODELO, no medido (modeloV1 del Plan Maestro 2014, corrido en EPANET): va en tablas APARTE, de referencia y de solo inserción, por carga
--   (redes.ref_cargas, conjunto «flujo_modelo»): vale la última no anulada. La tabla queda vacía: se llena con el paquete de carga por psql (carga_flujo/).
-- =====================================================================
do $$
begin
  if to_regclass('redes.flujo_modelo') is not null then raise exception 'La Fase 3 del Corte 9b ya está aplicada: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '7f9c0157c47e371e1d3d87ef6bda847b' then
    raise exception 'Las funciones de redes no son las de la Fase 2 del Corte 9b (huella 7f9c0157c47e371e1d3d87ef6bda847b): deténgase y avise';
  end if;
  if to_regclass('redes.ref_cargas') is null or to_regclass('redes.usuarios_sensibles') is null then raise exception 'Faltan tablas del 9a o de la Fase 2: deténgase y avise'; end if;
end $$;

-- ---------- 1. El flujo por tubo del modelo, en la hora de mayor y en la de menor consumo ----------
create table redes.flujo_modelo (
  carga_id       bigint not null references redes.ref_cargas (id),
  llave          text not null check (length(llave) between 1 and 120),      -- el tubo en el modelo
  activo_id      bigint references redes.activos (id),      -- el tramo de la red con que amarra (nulo: no amarró; no se dibuja)
  amarre         text check (amarre in ('llave', 'geometria')),
  geom_mismo     boolean,      -- la geometría del tramo va del nodo inicial al final del tubo del modelo
  q_mayor_lps    numeric not null,      -- con signo: + del nodo inicial al final del modelo
  v_mayor_mps    numeric not null check (v_mayor_mps >= 0),
  sentido_mayor  text not null check (sentido_mayor in ('ini_fin', 'fin_ini', 'sin_flujo')),
  q_menor_lps    numeric not null,
  v_menor_mps    numeric not null check (v_menor_mps >= 0),
  sentido_menor  text not null check (sentido_menor in ('ini_fin', 'fin_ini', 'sin_flujo')),
  primary key (carga_id, llave),
  check ((activo_id is null) = (amarre is null)), check ((activo_id is null) = (geom_mismo is null))
);
create unique index ux_flujo_modelo_activo on redes.flujo_modelo (carga_id, activo_id) where activo_id is not null;      -- un tramo, un tubo
comment on table redes.flujo_modelo is 'Corte 9b (Fase 3): caudal, velocidad y sentido por tubo según el modelo (modeloV1, Plan Maestro 2014; EPANET), en la hora de mayor y de menor consumo. MODELO, no medido. Referencia, solo inserción, por carga.';
create table redes.flujo_modelo_horas (
  carga_id    bigint not null references redes.ref_cargas (id),
  cual        text not null check (cual in ('mayor', 'menor')),
  hora        integer not null check (hora between 0 and 23),
  consumo_lps numeric not null check (consumo_lps >= 0),
  primary key (carga_id, cual)
);
do $$
declare t text;
begin
  foreach t in array array['flujo_modelo', 'flujo_modelo_horas'] loop
    execute format('alter table redes.%I enable row level security', t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', t);
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
end $$;

-- ---------- 2. La capa en la lista del geovisor: queda «en espera» hasta que el Code B tenga la pantalla (flechas, selector de hora y leyenda) ----------
insert into redes.geovisor_capas (codigo, nombre, grupo, fuente, estado, prefijos, por_fecha, solo_completo, nota, orden, activa)
values ('flujo_modelo', 'Flujo del agua (modelo)', 'analisis', 'preparada', 'espera_dato', '{}', false, true,
        'Modelo, no medido (modeloV1, Plan Maestro 2014). Solo supervisores y administrador. Tesela: geoportal_redes_geovisor_mvt_flujo', 77, true)
on conflict (codigo) do update set activa = true, nota = excluded.nota, fuente = excluded.fuente, estado = excluded.estado;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 · 20 — FUNCIONES Y RPC de la capa «Flujo del agua (modelo)». PROPUESTA. Solo agrega.
-- · geoportal_redes_geovisor_mvt_flujo: la tesela. Cada tramo sale con la línea YA ORIENTADA en el sentido del agua de esa hora (la pantalla solo pone
--   flechas a lo largo de la línea), su caudal (L/s, sin signo), su velocidad (m/s) y su clase de caudal (1 a 5) para el grosor. Los tramos «sin flujo»
--   salen marcados (sin flecha). Solo supervisores y administrador.
-- · geoportal_redes_flujo_modelo: la leyenda, las horas, la cobertura y el rótulo «Modelo, no medido (modeloV1, Plan Maestro 2014)».
-- · geoportal_redes_flujo_tramo: la tarjeta de un tramo (las dos horas).
-- Sentido respecto a la geometría del tramo: «ini_fin» con la geometría en el mismo sentido del tubo, o «fin_ini» con la geometría al revés = a favor de la línea.
-- =====================================================================
create function redes.f_flujo_clase(p_q numeric) returns integer
language sql immutable set search_path = pg_catalog as $$
  select case when abs(p_q) < 1 then 1 when abs(p_q) < 5 then 2 when abs(p_q) < 20 then 3 when abs(p_q) < 100 then 4 else 5 end $$;

create function public.geoportal_redes_geovisor_mvt_flujo(p_solicitante text, p_hora text, p_z integer, p_x integer, p_y integer)
returns text
language plpgsql stable security definer set search_path = public, redes, extensions, pg_temp as $$
declare a record; v_env geometry; v_env4 geometry; v_c bigint; v bytea; v_mayor boolean := p_hora = 'mayor'; v_diam numeric;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'El flujo del agua (modelo) es para supervisores' using errcode = '42501'; end if;
  if p_hora is null or p_hora not in ('mayor', 'menor') then perform tecnica.f_error('La hora es «mayor» o «menor»'); end if;
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  v_c := redes.f_ref_vigente('flujo_modelo');
  if v_c is null or p_z < redes.f_param('geovisor_zoom_min') then return ''; end if;
  -- como la red: antes del zoom de «red completa», solo los diámetros principales
  v_diam := case when p_z < redes.f_param('geovisor_zoom_red_completa') then redes.f_param('geovisor_diam_principal_acu_mm') end;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'flujo_modelo', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(case when x.sentido <> 'sin_flujo' and (x.sentido = 'ini_fin') <> f.geom_mismo then ST_Reverse(m.geom) else m.geom end, 3857), v_env, 4096, 64, true) as geom,
           m.codigo, round(abs(x.q), 2)::real as q, round(x.v, 2)::real as v, redes.f_flujo_clase(x.q) as clase, (x.sentido = 'sin_flujo') as sin_flujo, m.diametro_mm::real as d
      from redes.activo_vigente_mat m
      join redes.flujo_modelo f on f.carga_id = v_c and f.activo_id = m.activo_id
     cross join lateral (select case when v_mayor then f.q_mayor_lps else f.q_menor_lps end as q, case when v_mayor then f.v_mayor_mps else f.v_menor_mps end as v,
                                case when v_mayor then f.sentido_mayor else f.sentido_menor end as sentido) x
     where m.geom && v_env4 and not m.retirado and not m.oculto and m.sistema = 'acueducto' and m.prefijo in ('RED', 'CON')
       and (v_diam is null or m.diametro_mm >= v_diam)) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $$;

create function public.geoportal_redes_flujo_modelo(p_solicitante text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; v_c bigint := redes.f_ref_vigente('flujo_modelo'); r redes.ref_cargas%rowtype;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'El flujo del agua (modelo) es para supervisores' using errcode = '42501'; end if;
  if v_c is null then return jsonb_build_object('cargado', false, 'rotulo', 'Modelo, no medido (modeloV1, Plan Maestro 2014)'); end if;
  select * into r from redes.ref_cargas where id = v_c;
  return jsonb_build_object(
    'cargado', true, 'rotulo', 'Modelo, no medido (modeloV1, Plan Maestro 2014)', 'origen', r.origen, 'nota', r.nota, 'version', v_c,
    'horas', (select jsonb_agg(jsonb_build_object('cual', h.cual, 'hora', h.hora, 'consumo_lps', h.consumo_lps,
                                                  'texto', case h.cual when 'mayor' then 'Hora de mayor consumo' else 'Hora de menor consumo' end || ' (' || h.hora || ':00)') order by h.cual)
                from redes.flujo_modelo_horas h where h.carga_id = v_c),
    'cobertura', (select jsonb_build_object('tubos_modelo', count(*), 'con_tramo', count(f.activo_id), 'sin_tramo', count(*) - count(f.activo_id),
                         'tramos_red', (select count(*) from redes.activo_vigente_mat m where m.sistema = 'acueducto' and m.prefijo in ('RED', 'CON') and not m.retirado and not m.oculto),
                         'sin_flujo_mayor', count(*) filter (where f.activo_id is not null and f.sentido_mayor = 'sin_flujo'),
                         'sin_flujo_menor', count(*) filter (where f.activo_id is not null and f.sentido_menor = 'sin_flujo'))
                    from redes.flujo_modelo f where f.carga_id = v_c),
    'leyenda', jsonb_build_object('titulo', 'Caudal según el modelo', 'unidad', 'L/s', 'clases', jsonb_build_array(
        jsonb_build_object('clase', 1, 'texto', 'Menos de 1'), jsonb_build_object('clase', 2, 'texto', '1 a 5'), jsonb_build_object('clase', 3, 'texto', '5 a 20'),
        jsonb_build_object('clase', 4, 'texto', '20 a 100'), jsonb_build_object('clase', 5, 'texto', 'Más de 100')),
      'sin_flujo', 'Sin flujo en el modelo', 'sin_dato', 'Los tramos que no están en el modelo no llevan flecha'));
end $$;

create function public.geoportal_redes_flujo_tramo(p_solicitante text, p_codigo text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; v_c bigint := redes.f_ref_vigente('flujo_modelo'); v_id bigint; f redes.flujo_modelo%rowtype;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'El flujo del agua (modelo) es para supervisores' using errcode = '42501'; end if;
  v_id := redes.f_buscar_activo(p_codigo);
  select * into f from redes.flujo_modelo x where x.carga_id = v_c and x.activo_id = v_id;
  if not found then return jsonb_build_object('tramo', redes.f_activo_corto(v_id), 'en_modelo', false, 'rotulo', 'Modelo, no medido (modeloV1, Plan Maestro 2014)',
                                              'texto', 'Este tramo no está en el modelo: sin dato de flujo.'); end if;
  return jsonb_build_object('tramo', redes.f_activo_corto(v_id), 'en_modelo', true, 'rotulo', 'Modelo, no medido (modeloV1, Plan Maestro 2014)', 'tubo_modelo', f.llave, 'amarre', f.amarre,
    'horas', (select jsonb_agg(jsonb_build_object('cual', h.cual, 'hora', h.hora,
                'caudal_lps', round(abs(case h.cual when 'mayor' then f.q_mayor_lps else f.q_menor_lps end), 2),
                'velocidad_mps', round(case h.cual when 'mayor' then f.v_mayor_mps else f.v_menor_mps end, 2),
                'sentido', case case h.cual when 'mayor' then f.sentido_mayor else f.sentido_menor end when 'sin_flujo' then 'sin_flujo'
                             else case when ((case h.cual when 'mayor' then f.sentido_mayor else f.sentido_menor end) = 'ini_fin') = f.geom_mismo then 'con_la_linea' else 'contra_la_linea' end end) order by h.cual)
                from redes.flujo_modelo_horas h where h.carga_id = v_c),
    'cambia_de_sentido', f.sentido_mayor <> f.sentido_menor and 'sin_flujo' not in (f.sentido_mayor, f.sentido_menor));
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 · 40 — PERMISOS: revoke all antes de dar permisos. La interna: nadie de la API. Las 3 RPC: solo service_role.
-- =====================================================================
revoke all on function redes.f_flujo_clase(numeric) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_geovisor_mvt_flujo', 'geoportal_redes_flujo_modelo', 'geoportal_redes_flujo_tramo') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte9b_f3', 'migracion_redes_corte9b_fase3', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.flujo_modelo', 'redes.flujo_modelo_horas'),
        'nuevas', jsonb_build_array('redes.f_flujo_clase', 'geoportal_redes_geovisor_mvt_flujo', 'geoportal_redes_flujo_modelo', 'geoportal_redes_flujo_tramo'),
        'capa', 'flujo_modelo (en espera)', 'motivo', 'capa «Flujo del agua (modelo)»: flujo por tubo de modeloV1 en la hora de mayor y de menor consumo'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 3 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes9g.*), la red de prueba ZT9B y su carga de flujo de prueba (que tapa la real dentro
-- de esta transacción). Mide con el volumen real: da flujo de prueba a TODOS los tramos de acueducto de la base donde corre y FALLA si una tesela pasa de 1 s.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 9b, Fase 3 … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- un rincón de la caja de Valledupar, lejos de la red (x, y en metros aproximados)
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.1300 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.5800 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create temp table _zt (nombre text primary key, activo_id bigint, nodo bigint, x numeric, y numeric);
-- un activo de prueba (versión 1); devuelve su id
create function pg_temp.activo(p_nombre text, p_prefijo text, p_geom geometry, p_clase text default null, p_efecto text default null, p_estado text default 'en_operacion')
returns bigint language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes9g.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZT9B ' || p_nombre, p_clase, p_efecto,
          case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end, case when p_prefijo = 'RED' then 110 end,
          p_estado, '{}'::jsonb, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT9B activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_id;
end $$;
-- un nodo de la red de prueba (con su activo si es válvula o tanque)
create function pg_temp.nodo(p_nombre text, x numeric, y numeric, p_carga bigint, p_prefijo text default null, p_clase text default null, p_efecto text default null)
returns void language plpgsql as $$
declare v_act bigint; v_n bigint;
begin
  if p_prefijo is not null then v_act := pg_temp.activo(p_nombre, p_prefijo, pg_temp.pt(x, y), p_clase, p_efecto); end if;
  insert into redes.nodos (sistema, llave_modelo, nombre_modelo, clase_nodo, geom, activo_id, dispersion_m, carga_id)
  values ('acueducto', 'ZT9B-' || p_nombre, 'ZT9B' || p_nombre, case when v_act is null then 'por_clasificar' else 'activo' end, pg_temp.pt(x, y), v_act, 0, p_carga)
  returning id into v_n;
  insert into _zt values (p_nombre, v_act, v_n, x, y);
end $$;
-- un tramo de la red de prueba entre dos nodos, con n contratos de prueba
create function pg_temp.tramo(p_nombre text, p_a text, p_b text, p_carga bigint, p_contratos integer, p_estado text default 'en_operacion')
returns void language plpgsql as $$
declare a _zt; b _zt; v_id bigint;
begin
  select * into a from _zt where nombre = p_a; select * into b from _zt where nombre = p_b;
  v_id := pg_temp.activo(p_nombre, 'RED', ST_MakeLine(pg_temp.pt(a.x, a.y), pg_temp.pt(b.x, b.y)), null, null, p_estado);
  insert into redes.tramo_nodos (activo_id, version, nodo_ini, nodo_fin, metodo, carga_id) values (v_id, 1, a.nodo, b.nodo, 'modelo', p_carga);
  insert into _zt values (p_nombre, v_id, null, (a.x + b.x) / 2, (a.y + b.y) / 2);
  insert into redes.contrato_tramo (contrato, activo_id, distancia_m, metodo)
  select '99999' || lpad((v_id % 100000)::text, 5, '0') || lpad(i::text, 5, '0'), v_id, 5, 'cercania' from generate_series(1, p_contratos) i;
end $$;
create function pg_temp.id(p_nombre text) returns bigint language sql as $$ select activo_id from _zt where nombre = p_nombre $$;
create function pg_temp.cod(p_nombre text) returns text language sql as $$ select a.codigo from redes.activos a join _zt z on z.activo_id = a.id where z.nombre = p_nombre $$;
create function pg_temp.cods(p jsonb) returns text language sql as $$ select coalesce(string_agg(x ->> 'codigo', ',' order by o), '') from jsonb_array_elements(p) with ordinality y(x, o) $$;
create function pg_temp.ncods(p text) returns text language sql as $$
  select coalesce(string_agg(pg_temp.cod(btrim(x)), ',' order by o), '') from unnest(string_to_array(p, ',')) with ordinality u(x, o) $$;
-- la tesela (z, x, y) que contiene un punto
create function pg_temp.tx(g geometry, z integer) returns integer language sql as $$ select floor((ST_X(g) + 180) / 360 * (1 << z))::integer $$;
create function pg_temp.ty(g geometry, z integer) returns integer language sql as $$
  select floor((1 - ln(tan(radians(ST_Y(g))) + 1 / cos(radians(ST_Y(g)))) / pi()) / 2 * (1 << z))::integer $$;
create function pg_temp.foto() returns redes.corte_fotos language sql as $$ select * from redes.corte_fotos order by id desc limit 1 $$;
create function pg_temp.archivo(p_ruta text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg')) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;

do $prueba$
declare
  a text := 'prueba.redes9g.adm@emdupar.gov.co'; sd text := 'prueba.redes9g.dist@emdupar.gov.co'; op text := 'prueba.redes9g.op@emdupar.gov.co';
  v_carga bigint; v_c bigint; j jsonb; v_z integer; v_x integer; v_y integer; v_m text; v_m2 text; v_n integer;
  v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_ms4 numeric; v_info text := ''; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9B Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT9B Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT9B Operador daños', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT9B prueba: el operador con el geovisor');

  -- ---------- la red de prueba ----------
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
  values ('acueducto', md5('zt9b-a') || md5('zt9b-b'), 'shp', 4326, 'ID', 1, 'ZT9B red de prueba', a) returning id into v_carga;
  perform pg_temp.nodo('F', 0, 0, v_carga, 'TAN');
  perform pg_temp.nodo('A', 100, 0, v_carga);
  perform pg_temp.nodo('V1', 200, 0, v_carga, 'VAL', 'cierre', 'cierra');
  perform pg_temp.nodo('B', 300, 0, v_carga);
  perform pg_temp.nodo('V2', 400, 0, v_carga, 'VAL', 'cierre', 'sin_definir');
  perform pg_temp.nodo('C', 500, 0, v_carga);
  perform pg_temp.nodo('V3', 600, 0, v_carga, 'VAL', 'cierre', 'cierra');
  perform pg_temp.nodo('D', 700, 0, v_carga);
  perform pg_temp.nodo('K', 800, 0, v_carga);
  perform pg_temp.nodo('V4', 300, 100, v_carga, 'VAL', 'cierre', 'deriva');
  perform pg_temp.nodo('E', 300, 200, v_carga);
  perform pg_temp.nodo('V5', 300, -100, v_carga, 'VAL', 'ventosa', 'cierra');
  perform pg_temp.nodo('G', 300, -200, v_carga);
  perform pg_temp.nodo('H', 500, 100, v_carga);
  perform pg_temp.nodo('F2', 500, -100, v_carga, 'TAN');
  perform pg_temp.tramo('T1', 'F', 'A', v_carga, 1);
  perform pg_temp.tramo('T2', 'A', 'V1', v_carga, 1);
  perform pg_temp.tramo('T3', 'V1', 'B', v_carga, 1);
  perform pg_temp.tramo('T4', 'B', 'V2', v_carga, 2);
  perform pg_temp.tramo('T5', 'V2', 'C', v_carga, 1);
  perform pg_temp.tramo('T6', 'C', 'V3', v_carga, 1);
  perform pg_temp.tramo('T7', 'V3', 'D', v_carga, 2);
  perform pg_temp.tramo('T8', 'B', 'V4', v_carga, 1);
  perform pg_temp.tramo('T9', 'V4', 'E', v_carga, 1);
  perform pg_temp.tramo('T10', 'B', 'V5', v_carga, 0);
  perform pg_temp.tramo('T11', 'V5', 'G', v_carga, 1);
  perform pg_temp.tramo('T12', 'C', 'H', v_carga, 3);
  perform pg_temp.tramo('T13', 'C', 'F2', v_carga, 0);
  perform pg_temp.tramo('T14', 'D', 'K', v_carga, 4, 'proyectado');


  -- ===================== 01. Estructura =====================
  perform pg_temp.reg('01.01 las 2 tablas del flujo existen, sin permisos de la API y de solo agregar; la capa está en la lista, en espera y solo para supervisores',
     not has_table_privilege('service_role', 'redes.flujo_modelo', 'select')
     and (select count(*) from pg_trigger t where t.tgrelid in ('redes.flujo_modelo'::regclass, 'redes.flujo_modelo_horas'::regclass) and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 4
     and (select x ->> 'estado' = 'espera_dato' from jsonb_array_elements(public.geoportal_redes_geovisor(sd) -> 'capas') x where x ->> 'codigo' = 'flujo_modelo')
     and not exists (select 1 from jsonb_array_elements(public.geoportal_redes_geovisor(op) -> 'capas') x where x ->> 'codigo' = 'flujo_modelo'));
  perform pg_temp.reg('01.02 sin carga: «no cargado», con el rótulo; la tesela sale vacía',
     not (public.geoportal_redes_flujo_modelo(sd) ->> 'cargado')::boolean or redes.f_ref_vigente('flujo_modelo') is not null);

  -- ===================== 02. Una carga de prueba =====================
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor) values ('flujo_modelo', 'zt9b_flujo.csv', md5('zt9b-flujo' || clock_timestamp()::text), 4, 'ZT9B modelo de prueba', 'ZT9B nota', a) returning id into v_c;
  insert into redes.flujo_modelo_horas (carga_id, cual, hora, consumo_lps) values (v_c, 'mayor', 17, 2944), (v_c, 'menor', 23, 2722);
  insert into redes.flujo_modelo (carga_id, llave, activo_id, amarre, geom_mismo, q_mayor_lps, v_mayor_mps, sentido_mayor, q_menor_lps, v_menor_mps, sentido_menor) values
    (v_c, 'ZT9B-P1', pg_temp.id('T1'), 'llave', true, 10, 1.05, 'ini_fin', -3, 0.32, 'fin_ini'),          -- cambia de sentido entre las dos horas
    (v_c, 'ZT9B-P2', pg_temp.id('T2'), 'geometria', false, 2, 0.21, 'ini_fin', 0, 0, 'sin_flujo'),        -- la geometría va al revés del tubo
    (v_c, 'ZT9B-P3', pg_temp.id('T3'), 'llave', true, -150, 2.5, 'fin_ini', -120, 2.0, 'fin_ini'),
    (v_c, 'ZT9B-P9', null, null, null, 5, 0.5, 'ini_fin', 5, 0.5, 'ini_fin');                             -- un tubo del modelo sin tramo en la red
  j := public.geoportal_redes_flujo_modelo(sd);
  perform pg_temp.reg('02.01 la información de la capa: rótulo «Modelo, no medido (modeloV1, Plan Maestro 2014)», las dos horas (17:00 y 23:00), la cobertura y la leyenda de 5 clases',
     (j ->> 'cargado')::boolean and j ->> 'rotulo' = 'Modelo, no medido (modeloV1, Plan Maestro 2014)'
     and (select string_agg(x ->> 'texto', ' · ' order by x ->> 'cual') from jsonb_array_elements(j -> 'horas') x) = 'Hora de mayor consumo (17:00) · Hora de menor consumo (23:00)'
     and (j -> 'cobertura' ->> 'tubos_modelo')::integer = 4 and (j -> 'cobertura' ->> 'con_tramo')::integer = 3 and (j -> 'cobertura' ->> 'sin_flujo_menor')::integer = 1
     and jsonb_array_length(j -> 'leyenda' -> 'clases') = 5, j::text);
  j := public.geoportal_redes_flujo_tramo(sd, pg_temp.cod('T1'));
  perform pg_temp.reg('02.02 la tarjeta de T1: 10 L/s a favor de la línea en la hora mayor, 3 L/s en contra en la menor; cambia de sentido',
     (j ->> 'en_modelo')::boolean and (j ->> 'cambia_de_sentido')::boolean
     and (select (x ->> 'caudal_lps')::numeric = 10 and x ->> 'sentido' = 'con_la_linea' from jsonb_array_elements(j -> 'horas') x where x ->> 'cual' = 'mayor')
     and (select (x ->> 'caudal_lps')::numeric = 3 and x ->> 'sentido' = 'contra_la_linea' from jsonb_array_elements(j -> 'horas') x where x ->> 'cual' = 'menor'), j::text);
  j := public.geoportal_redes_flujo_tramo(sd, pg_temp.cod('T2'));
  perform pg_temp.reg('02.03 la tarjeta de T2 (geometría al revés del tubo): «ini_fin» del modelo es en contra de la línea; en la hora menor, sin flujo',
     (select x ->> 'sentido' = 'contra_la_linea' from jsonb_array_elements(j -> 'horas') x where x ->> 'cual' = 'mayor')
     and (select x ->> 'sentido' = 'sin_flujo' from jsonb_array_elements(j -> 'horas') x where x ->> 'cual' = 'menor') and not (j ->> 'cambia_de_sentido')::boolean, j::text);
  perform pg_temp.reg('02.04 un tramo que no está en el modelo (T4): «sin dato de flujo»',
     not (public.geoportal_redes_flujo_tramo(sd, pg_temp.cod('T4')) ->> 'en_modelo')::boolean);
  perform pg_temp.reg('02.05 las clases de caudal para el grosor: 0,5 → 1; 3 → 2; 10 → 3; 50 → 4; −150 → 5',
     redes.f_flujo_clase(0.5) = 1 and redes.f_flujo_clase(3) = 2 and redes.f_flujo_clase(10) = 3 and redes.f_flujo_clase(50) = 4 and redes.f_flujo_clase(-150) = 5);

  -- ===================== 03. La tesela =====================
  v_z := 16; v_x := pg_temp.tx(pg_temp.pt(50, 0), v_z); v_y := pg_temp.ty(pg_temp.pt(50, 0), v_z);
  perform pg_temp.reg('03.01 la tesela de la hora mayor y la de la menor traen los tramos de prueba (z 16) y son distintas (T1 cambia de sentido)',
     length(public.geoportal_redes_geovisor_mvt_flujo(sd, 'mayor', v_z, v_x, v_y)) > 0 and length(public.geoportal_redes_geovisor_mvt_flujo(sd, 'menor', v_z, v_x, v_y)) > 0
     and public.geoportal_redes_geovisor_mvt_flujo(sd, 'mayor', v_z, v_x, v_y) <> public.geoportal_redes_geovisor_mvt_flujo(sd, 'menor', v_z, v_x, v_y));
  perform pg_temp.reg('03.02 la línea sale orientada en el sentido del agua: en la hora menor, T1 va al revés que su geometría (empieza en A y termina en el tanque F)',
     (select ST_Equals(ST_StartPoint(case when f.sentido_menor <> 'sin_flujo' and (f.sentido_menor = 'ini_fin') <> f.geom_mismo then ST_Reverse(m.geom) else m.geom end), pg_temp.pt(100, 0))
             and ST_Equals(ST_StartPoint(case when f.sentido_mayor <> 'sin_flujo' and (f.sentido_mayor = 'ini_fin') <> f.geom_mismo then ST_Reverse(m.geom) else m.geom end), pg_temp.pt(0, 0))
        from redes.flujo_modelo f join redes.activo_vigente_mat m on m.activo_id = f.activo_id where f.carga_id = v_c and f.activo_id = pg_temp.id('T1')));
  perform pg_temp.reg('03.03 lejos de la red de prueba, vacía; antes del zoom mínimo, vacía; antes del zoom de «red completa», sin los tramos de diámetro menor',
     public.geoportal_redes_geovisor_mvt_flujo(sd, 'mayor', v_z, pg_temp.tx(pg_temp.pt(9000, 9000), v_z), pg_temp.ty(pg_temp.pt(9000, 9000), v_z)) = ''
     and public.geoportal_redes_geovisor_mvt_flujo(sd, 'mayor', 10, pg_temp.tx(pg_temp.pt(50, 0), 10), pg_temp.ty(pg_temp.pt(50, 0), 10)) = ''
     and public.geoportal_redes_geovisor_mvt_flujo(sd, 'mayor', 13, pg_temp.tx(pg_temp.pt(50, 0), 13), pg_temp.ty(pg_temp.pt(50, 0), 13)) = '');
  perform pg_temp.err('03.04 el operador (aunque tenga el geovisor) no ve el flujo: 42501', format('select public.geoportal_redes_geovisor_mvt_flujo(%L, %L, %s, %s, %s)', op, 'mayor', v_z, v_x, v_y), '42501');
  perform pg_temp.err('03.05 … ni la información de la capa', format('select public.geoportal_redes_flujo_modelo(%L)', op), '42501');
  perform pg_temp.err('03.06 una hora que no existe', format('select public.geoportal_redes_geovisor_mvt_flujo(%L, %L, %s, %s, %s)', sd, 'tarde', v_z, v_x, v_y), null, 'hora');
  perform pg_temp.err('03.07 solo agregar: el flujo cargado no se cambia', format('update redes.flujo_modelo set q_mayor_lps = 0 where carga_id = %s', v_c));
  insert into redes.ref_carga_eventos (carga_id, tipo, motivo, autor) values (v_c, 'anular', 'ZT9B prueba: se anula la carga de flujo', a);
  perform pg_temp.reg('03.08 al anular la carga (con motivo), deja de valer: la tesela ya no trae esos tramos',
     redes.f_ref_vigente('flujo_modelo') is distinct from v_c);

  -- ===================== 04. Tiempos con el volumen real =====================
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, autor) values ('flujo_modelo', 'zt9b_flujo_volumen.csv', md5('zt9b-vol' || clock_timestamp()::text), 0, 'ZT9B modelo de volumen', a) returning id into v_c;
  insert into redes.flujo_modelo_horas (carga_id, cual, hora, consumo_lps) values (v_c, 'mayor', 17, 2944), (v_c, 'menor', 23, 2722);
  insert into redes.flujo_modelo (carga_id, llave, activo_id, amarre, geom_mismo, q_mayor_lps, v_mayor_mps, sentido_mayor, q_menor_lps, v_menor_mps, sentido_menor)
  select v_c, 'ZT9B-' || m.activo_id, m.activo_id, 'llave', (m.activo_id % 2 = 0), (m.activo_id % 200) - 100, 1, case when m.activo_id % 7 = 0 then 'sin_flujo' when m.activo_id % 3 = 0 then 'fin_ini' else 'ini_fin' end,
         (m.activo_id % 90) - 45, 0.5, case when m.activo_id % 5 = 0 then 'sin_flujo' else 'ini_fin' end
    from redes.activo_vigente_mat m where m.sistema = 'acueducto' and m.prefijo in ('RED', 'CON') and not m.retirado;
  get diagnostics v_n = row_count;
  analyze redes.flujo_modelo;
  v_z := floor(redes.f_param('geovisor_zoom_red_completa'))::integer;
  select t.x, t.y into v_x, v_y from (select pg_temp.tx(ST_PointOnSurface(m.geom), v_z) as x, pg_temp.ty(ST_PointOnSurface(m.geom), v_z) as y
                                        from redes.activo_vigente_mat m where m.sistema = 'acueducto' and m.prefijo = 'RED' and not m.retirado) t group by t.x, t.y order by count(*) desc limit 1;
  v_t0 := clock_timestamp(); v_m := public.geoportal_redes_geovisor_mvt_flujo(a, 'mayor', v_z, v_x, v_y); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_m2 := public.geoportal_redes_geovisor_mvt_flujo(a, 'menor', v_z - 1, v_x / 2, v_y / 2); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); j := public.geoportal_redes_flujo_modelo(a); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); perform public.geoportal_redes_flujo_tramo(a, (select codigo from redes.activo_vigente_mat where prefijo = 'RED' and not retirado order by activo_id limit 1)); v_ms4 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS con flujo en %s tramos (todos los de acueducto de esta base): tesela más cargada %s/%s/%s %s ms (%s kB) · tesela %s/%s/%s (solo diámetros principales) %s ms (%s kB) · información de la capa %s ms · tarjeta de un tramo %s ms',
                   v_n, v_z, v_x, v_y, v_ms1, round(length(v_m) * 0.75 / 1024), v_z - 1, v_x / 2, v_y / 2, v_ms2, round(length(v_m2) * 0.75 / 1024), v_ms3, v_ms4);
  perform pg_temp.reg('04.01 TIEMPOS: las teselas, la información y la tarjeta, cada una en menos de 1 s', v_n > 0 and length(v_m) > 0 and greatest(v_ms1, v_ms2, v_ms3, v_ms4) < 1000, v_info);
  perform pg_temp.reg('04.02 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 9b, Fase 3 (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
