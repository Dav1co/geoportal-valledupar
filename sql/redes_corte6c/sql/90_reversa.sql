-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones como estaban con el 6b y el hotfix de safeupdate (las 3 reemplazadas y las 2 retiradas, con su texto exacto), sin las 2
-- funciones nuevas, y vuelve a crear la copia derivada (redes.contratos_capa y su estado), VACÍA.
-- ⚠ Con la reversa vuelve el problema del 6b: el geovisor intenta rehacer la capa dentro de la petición y en producción se corta a los 30 s.
--   Después de la reversa hay que llenarla a mano en el editor: select redes.f_refrescar_contratos_capa();
-- SE NIEGA si alguna función cambió después de la migración. El 6c no guarda datos: no hay nada que perder.
-- =====================================================================
do $$
begin
  if to_regprocedure('redes.f_funciones_sin_where()') is null then raise exception 'No hay nada que revertir: el Corte 6c no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '2c2658002d114d755f19a7b5f5dfe542' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 6c: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. la copia derivada, como la creó el 6b (vacía)
create table redes.contratos_capa (
  contrato      text primary key,
  geom          geometry(Point, 4326) not null,
  uso           text,
  estado        text not null check (estado in ('activo', 'retirado', 'otro', 'sin_dato')),
  consumo_prom  numeric,
  medidor_anios integer
);
create index ix_contratos_capa_geom on redes.contratos_capa using gist (geom);
comment on table redes.contratos_capa is 'Corte 6b: capa de contratos del geovisor técnico. Derivada (se rehace entera). Sin datos personales.';
create table redes.contratos_capa_estado (
  id           integer primary key check (id = 1),
  firma        text not null,
  filas        integer not null,
  calculado_en timestamptz not null,
  duracion_ms  integer not null
);
alter table redes.contratos_capa enable row level security;
alter table redes.contratos_capa_estado enable row level security;
revoke all on table redes.contratos_capa, redes.contratos_capa_estado from public, anon, authenticated, service_role;

-- 2. las 2 funciones retiradas y las 3 reemplazadas, con su texto del 6b + hotfix
CREATE OR REPLACE FUNCTION redes.f_refrescar_contratos_capa()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'bi_interno', 'extensions', 'pg_temp'
AS $function$
declare t0 timestamptz := clock_timestamp(); n integer;
begin
  delete from redes.contratos_capa where true;
  insert into redes.contratos_capa (contrato, geom, uso, estado, consumo_prom, medidor_anios)
  select c.cod_usuario, c.geom,
         coalesce(nullif(btrim(f.uso), '(sin dato)'), nullif(regexp_replace(btrim(coalesce(cs.categoria, '')), '^-?[0-9]+\s+', ''), '')),
         redes.f_estado_contrato(cs.estado), f.cons_prom, f.medidor_anios
    from (select distinct on (cv.cod_usuario) cv.cod_usuario, cv.geom from public.catastro_valledupar cv
           where cv.cod_usuario ~ '^[0-9]{1,12}$' and cv.cod_usuario not in ('0', '99999999') and cv.geom is not null
           order by cv.cod_usuario, cv.id) c
    left join bi_interno.ficha_contrato f on f.contrato = c.cod_usuario
    left join lateral (select s.estado, s.categoria from public.cartera_suscripcion s where s.contrato = c.cod_usuario order by s.periodo_carga desc nulls last limit 1) cs on true;
  get diagnostics n = row_count;
  insert into redes.contratos_capa_estado (id, firma, filas, calculado_en, duracion_ms)
  values (1, coalesce((select calculado_en::text from bi_interno.ficha_contrato_estado where id = 1), 'sin ficha'), n, clock_timestamp(),
          (extract(epoch from clock_timestamp() - t0) * 1000)::integer)
  on conflict (id) do update set firma = excluded.firma, filas = excluded.filas, calculado_en = excluded.calculado_en, duracion_ms = excluded.duracion_ms;
  return n;
end $function$;
revoke all on function redes.f_refrescar_contratos_capa() from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION redes.f_contratos_capa_al_dia()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'bi_interno', 'pg_temp'
AS $function$
declare e redes.contratos_capa_estado%rowtype;
begin
  select * into e from redes.contratos_capa_estado where id = 1;
  if found and e.firma = coalesce((select calculado_en::text from bi_interno.ficha_contrato_estado where id = 1), 'sin ficha')
     and e.calculado_en > clock_timestamp() - make_interval(hours => floor(redes.f_param('geovisor_contratos_horas'))::integer) then
    return false;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('redes.contratos_capa')) then return false; end if;
  perform redes.f_refrescar_contratos_capa();
  return true;
end $function$;
revoke all on function redes.f_contratos_capa_al_dia() from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare a record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if a.completo then perform redes.f_contratos_capa_al_dia(); end if;      -- Corte 6b: la capa de contratos se rehace sola si cambió la ficha o tiene más de un día
  return jsonb_build_object(
    'perfil', case when a.admin then 'admin' when a.completo then 'supervisor' else 'operador' end,
    'completo', a.completo, 'perfiles', to_jsonb(a.perfiles),
    'hoy', (clock_timestamp() at time zone 'America/Bogota')::date,
    'rango_meses', floor(redes.f_param('geovisor_rango_meses'))::integer,
    'max_elementos', floor(redes.f_param('geovisor_max_elementos'))::integer,
    'zoom', jsonb_build_object('min', redes.f_param('geovisor_zoom_min'), 'red_completa', redes.f_param('geovisor_zoom_red_completa'),
                               'nodos', redes.f_param('geovisor_zoom_nodos'), 'accesorios', redes.f_param('geovisor_zoom_acc'),
                               'contratos', redes.f_param('geovisor_zoom_contratos')),
    'version', (select coalesce(sum(version), 0) from redes.tesela_version),
    'formularios', jsonb_build_object('danos_fallas', redes.f_puede_formulario(a.email, 'danos_fallas'),
                                      'mantenimiento', redes.f_puede_formulario(a.email, 'mantenimiento')),
    'ficha', a.completo, 'compartir', a.completo,
    'contratos_capa', case when a.completo then (select jsonb_build_object('filas', e.filas, 'calculado_en', e.calculado_en) from redes.contratos_capa_estado e where e.id = 1) end,
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre, 'grupo', g.grupo, 'fuente', g.fuente, 'estado', g.estado, 'nota', g.nota,
                                          'prefijos', to_jsonb(g.prefijos), 'por_fecha', g.por_fecha,
                                          'encendida', exists (select 1 from redes.capas_por_perfil c where c.capa = g.codigo and c.encendida and c.perfil = any (a.perfiles)))
             order by g.orden)
        from redes.geovisor_capas g where g.activa and (a.completo or not g.solo_completo)), '[]'::jsonb),
    'tipos', coalesce((select jsonb_object_agg(t.prefijo, t.nombre_visible) from redes.v_tipo_visible t), '{}'::jsonb),
    'estados', coalesce((select jsonb_object_agg(e.codigo, e.nombre) from redes.estados_activo e), '{}'::jsonb),
    'materiales', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', m.nombre) order by m.codigo) from redes.materiales m), '[]'::jsonb),
    -- solo el administrador: la tabla de capas por omisión, para editarla (N-11)
    'por_perfil', case when a.admin then coalesce((
      select jsonb_agg(jsonb_build_object('perfil', c.perfil, 'capa', c.capa, 'encendida', c.encendida, 'actualizado_en', c.actualizado_en, 'actualizado_por', c.actualizado_por)
             order by c.perfil, c.capa) from redes.capas_por_perfil c), '[]'::jsonb) end);
end $function$;
revoke all on function public.geoportal_redes_geovisor(text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_geovisor(text) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor_mvt_contratos(p_solicitante text, p_z integer, p_x integer, p_y integer)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare a record; v_env geometry; v bytea;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La capa de contratos es para supervisores' using errcode = '42501'; end if;
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < redes.f_param('geovisor_zoom_contratos') then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  select ST_AsMVT(t, 'contratos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(c.geom, 3857), v_env, 4096, 32, true) as geom, c.contrato, coalesce(c.uso, '') as uso, c.estado,
           c.consumo_prom::real as consumo, c.medidor_anios as medidor_anios
      from redes.contratos_capa c where c.geom && ST_Transform(v_env, 4326)) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $function$;
revoke all on function public.geoportal_redes_geovisor_mvt_contratos(text,integer,integer,integer) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_geovisor_mvt_contratos(text,integer,integer,integer) to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_contrato_tarjeta(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'bi_interno', 'pg_temp'
AS $function$
declare a record; c redes.contratos_capa%rowtype; cs record; pr record; f record; v_c text := btrim(coalesce(p_contrato, ''));
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;
  if v_c !~ '^[0-9]{1,12}$' then perform tecnica.f_error('Escriba solo los números del contrato'); end if;
  select * into c from redes.contratos_capa where contrato = v_c;
  if not found then perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002'); end if;
  select s.nombre, s.estado, s.categoria, s.direccion, s.barrio, s.periodo_carga into cs
    from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select cv.direccion, cv.barrio into pr from public.catastro_valledupar cv where cv.cod_usuario = v_c order by cv.id limit 1;
  select fc.periodo_ultimo, fc.uso, fc.consumo_meses, fc.cons_prom, fc.meses_con_lectura, fc.medidor_anios into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  -- la lectura queda registrada: quién, cuándo y qué contrato (NUNCA el nombre ni la dirección)
  perform tecnica.f_auditar(a.email, 'redes_contrato_tarjeta', v_c, jsonb_build_object('datos', 'nombre, dirección y barrio', 'desde', 'geovisor'), p_ip);
  return jsonb_build_object(
    'contrato', v_c,
    'estado', c.estado, 'estado_texto', nullif(btrim(cs.estado), ''),
    'uso', c.uso,
    'consumo', case when f.periodo_ultimo is not null then jsonb_build_object(
        'periodo_ultimo', f.periodo_ultimo, 'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura,
        'meses', (select coalesce(jsonb_agg(jsonb_build_object('periodo', m ->> 'periodo', 'm3', m -> 'm3', 'sin_dato', coalesce((m ->> 'sin_dato')::boolean, false),
                                                               'lectura_real', coalesce((m ->> 'lectura_real')::boolean, false)) order by k), '[]'::jsonb)
                    from jsonb_array_elements(f.consumo_meses) with ordinality x(m, k))) end,
    'medidor_anios', f.medidor_anios,
    'tramo', (select v.codigo from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id where t.contrato = v_c),
    'suscriptor', jsonb_build_object(                                  -- DATO PERSONAL: solo en pantalla
      'nombre', nullif(btrim(cs.nombre), ''),
      'direccion', coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')),
      'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), ''))),
    'corte', cs.periodo_carga);
end $function$;
revoke all on function public.geoportal_redes_contrato_tarjeta(text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_contrato_tarjeta(text,text,text) to service_role;

-- 3. lo nuevo
drop function redes.f_funciones_sin_where();
drop function redes.f_contrato_uso(text, text);
update redes.parametros set descripcion = 'Geovisor: la capa de contratos se rehace si tiene más de estas horas o si cambió la ficha del contrato'
 where clave = 'geovisor_contratos_horas';
update redes.geovisor_capas set nota = 'Desde el zoom 16. Al tocar un contrato: su consumo, nombre y dirección (la consulta queda registrada)'
 where codigo = 'contratos';

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '8113af17c6bd862d62a6cbc4bc4cba1f' then
    raise exception 'La reversa no dejó la base como en el 6b con el hotfix';
  end if;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte6c', 'reversa_redes_corte6c', null, jsonb_build_object('nota', 'vuelve la copia derivada, vacía: llenarla con redes.f_refrescar_contratos_capa()'), null);
