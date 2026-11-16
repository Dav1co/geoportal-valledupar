begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 10 — GUARDIA Y COLUMNAS NUEVAS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew).
-- Fuente: 02 fila 4, §16, §25 y §26 de la bitácora, y lo pospuesto de los Cortes 2, 3a y 3b.
-- · Presupone el 3b aplicado (huella del conjunto de funciones de redes, de v_dano y de v_epicrisis).
-- · ⚠ Toca las 4 funciones de permisos VIVAS (15): exige su huella md5 del 14-nov (paquete de Análisis de contrato). Si alguna cambió, se detiene
--   y dice la huella que encontró, para revisarla antes de seguir.
-- · Columnas nuevas (nada se borra): public.geoportal_lista_blanca.ver_dashboard_redes (15) y redes.danos.sector_num (aquí).
-- =====================================================================
do $$
declare v_esp jsonb := jsonb_build_object('geoportal_puede', '72b422973f0627aa2bf4a966855bc980', 'geoportal_mis_permisos', '5cf2e4f476e6ad9b75a185a6a225fc5f',
                                          'geoportal_admin_permisos', 'adc8edcc7708441dd91b584d326f297a', 'geoportal_admin_listar', 'fa675b8611c5c74fb77f7853facb8479');
        k text; v_n integer; v_m text;
begin
  if to_regclass('redes.ficha_ediciones') is null then raise exception 'Falta el Corte 3b: aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '45971067176a3d30286b6227f0447c0d' then
    raise exception 'Las funciones de redes no son las del Corte 3b (o el Corte 4a ya está aplicado): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_dano'::regclass, true)) <> 'bee1b39d753fc55ae7cb85a3952896fb' or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> 'a1e45ec72cb5b254a67698111994746a' then
    raise exception 'Las vistas v_dano o v_epicrisis no son las del 3b: deténgase y avise';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_lista_blanca' and column_name = 'ver_dashboard_redes')
     or exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'danos' and column_name = 'sector_num') then
    raise exception 'ver_dashboard_redes o sector_num ya existen: el Corte 4a parece aplicado';
  end if;
  for k in select jsonb_object_keys(v_esp) loop
    select count(*), max(md5(pg_get_functiondef(p.oid))) into v_n, v_m from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = k;
    if v_n <> 1 then raise exception 'GUARDIA: public.% tiene % firmas (se esperaba 1)', k, v_n; end if;
    if v_m <> v_esp ->> k then raise exception 'GUARDIA: public.% cambió desde el 14-nov (huella % y se esperaba %). No se aplica nada: avise.', k, v_m, v_esp ->> k; end if;
  end loop;
  if to_regprocedure('public.geoportal_aislamiento_verificado()') is null then raise exception 'Falta public.geoportal_aislamiento_verificado()'; end if;
end $$;

-- §25.1: el sector del daño es un número entero del 1 al 100 (hoy 1 a 7). sector_texto se queda (no se borra) y deja de llenarse.
alter table redes.danos add column sector_num smallint check (sector_num between 1 and 100);
comment on column redes.danos.sector_num is 'Sector hidráulico del daño: número del 1 al 100 (David, 15-nov 20:00). Reemplaza en la pantalla a sector_texto, que queda sin uso y sin borrar.';
comment on column redes.danos.sector_texto is 'Sin uso desde el Corte 4a (el sector pasó a sector_num, número del 1 al 100). No se borra: nada se borra.';
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 15 — PERMISO NUEVO ver_dashboard_redes (D-12): el supervisor de distribución.
-- ⚠ Toca las 4 funciones de permisos VIVAS, con el patrón exacto de ver_analisis_contrato (14-nov): su texto vivo + lo mínimo para el permiso nuevo.
--   · geoportal_puede: modo 'dashboard_redes'.   · geoportal_mis_permisos: 'dashboard_redes' y torre_b.
--   · geoportal_admin_permisos: 19 → 20 parámetros (p_dashboard_redes, con la compuerta de aislamiento como los demás permisos técnicos).
--   · geoportal_admin_listar: + la columna ver_dashboard_redes al final.
-- La guardia (10) exige la huella md5 viva de las 4; la reversa (90) las deja con su texto del 14-nov.
-- La columna nace en falso para todos: ningún marcado inicial (el administrador lo asigna en Administración).
-- =====================================================================
alter table public.geoportal_lista_blanca add column ver_dashboard_redes boolean not null default false;
comment on column public.geoportal_lista_blanca.ver_dashboard_redes is 'Técnica fase 1 (D-12): supervisor de distribución (Dashboard distribución, bandejas y edición de la ficha de redes salvo el origen). El administrador pasa siempre.';

create or replace function public.geoportal_puede(p_email text, p_modo text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((
    select case
      when lb.rol = 'admin' then true
      when p_modo = 'explorar' then lb.ver_explorar
      when p_modo = 'focalizacion' then lb.ver_focalizacion
      when p_modo = 'comercial' then lb.ver_comercial
      when p_modo = 'rutas' then lb.ver_rutas
      when p_modo = 'dashboard' then lb.ver_dashboard
      when p_modo = 'registro_tecnico' then lb.ver_registro_tecnico
      when p_modo = 'dashboard_tecnico' then lb.ver_dashboard_tecnico
      when p_modo = 'campo' then (lb.ver_campo or lb.ver_dashboard_campo)
      when p_modo = 'dashboard_campo' then lb.ver_dashboard_campo
      when p_modo = 'acta' then (lb.ver_acta or lb.ver_dashboard_acta)
      when p_modo = 'dashboard_acta' then lb.ver_dashboard_acta
      when p_modo = 'aseo' then (lb.ver_aseo or lb.ver_dashboard_aseo)          -- el supervisor de aseo también captura
      when p_modo = 'dashboard_aseo' then lb.ver_dashboard_aseo
      when p_modo = 'analisis_contrato' then lb.ver_analisis_contrato   -- Análisis de contrato (consulta con nombre y teléfono)
      when p_modo = 'dashboard_redes' then lb.ver_dashboard_redes       -- Técnica fase 1, Corte 4a: supervisor de distribución (D-12)
      else false
    end
    from public.geoportal_lista_blanca lb
    where lb.email = lower(p_email) and lb.activo
    limit 1), false);
$function$;

create or replace function public.geoportal_mis_permisos(p_email text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(
    (select jsonb_build_object(
       'rol', lb.rol, 'explorar', lb.ver_explorar, 'focalizacion', lb.ver_focalizacion, 'comercial', lb.ver_comercial,
       'rutas', lb.ver_rutas, 'dashboard', lb.ver_dashboard,
       'registro_tecnico', lb.ver_registro_tecnico, 'dashboard_tecnico', lb.ver_dashboard_tecnico,
       'dashboard_redes', (lb.rol = 'admin' or lb.ver_dashboard_redes),
       'campo', (lb.rol = 'admin' or lb.ver_campo or lb.ver_dashboard_campo),
       'dashboard_campo', (lb.rol = 'admin' or lb.ver_dashboard_campo),
       'acta', (lb.rol = 'admin' or lb.ver_acta or lb.ver_dashboard_acta),
       'dashboard_acta', (lb.rol = 'admin' or lb.ver_dashboard_acta),
       'aseo', (lb.rol = 'admin' or lb.ver_aseo or lb.ver_dashboard_aseo),
       'dashboard_aseo', (lb.rol = 'admin' or lb.ver_dashboard_aseo),
       'analisis_contrato', (lb.rol = 'admin' or lb.ver_analisis_contrato),
       'torre_a', (lb.rol = 'admin' or lb.ver_explorar or lb.ver_focalizacion or lb.ver_comercial or lb.ver_rutas or lb.ver_dashboard
                   or lb.ver_campo or lb.ver_dashboard_campo or lb.ver_acta or lb.ver_dashboard_acta or lb.ver_analisis_contrato),
       'torre_b', (lb.rol = 'admin' or lb.ver_registro_tecnico or lb.ver_dashboard_tecnico or lb.ver_dashboard_redes),
       'torre_c', (lb.rol = 'admin' or lb.ver_aseo or lb.ver_dashboard_aseo))
     from public.geoportal_lista_blanca lb
     where lb.email = lower(p_email) and lb.activo limit 1),
    jsonb_build_object('rol','consulta','explorar',true,'focalizacion',false,'comercial',false,'rutas',false,'dashboard',false,
                       'registro_tecnico',false,'dashboard_tecnico',false,'dashboard_redes',false,'campo',false,'dashboard_campo',false,'acta',false,'dashboard_acta',false,
                       'aseo',false,'dashboard_aseo',false,'analisis_contrato',false,'torre_a',false,'torre_b',false,'torre_c',false));
$function$;


drop function public.geoportal_admin_permisos(text, text, boolean, boolean, boolean, boolean, text, text, boolean, boolean, boolean, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean);

create function public.geoportal_admin_permisos(p_solicitante text, p_email text, p_explorar boolean, p_focalizacion boolean, p_comercial boolean, p_rutas boolean, p_horario text, p_dias text, p_dashboard boolean default false, p_registro_tecnico boolean default null, p_dashboard_tecnico boolean default null, p_ip text default null, p_campo boolean default null, p_dashboard_campo boolean default null, p_acta boolean default null, p_dashboard_acta boolean default null, p_aseo boolean default null, p_dashboard_aseo boolean default null, p_analisis_contrato boolean default null, p_dashboard_redes boolean default null)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_antes jsonb; v_despues jsonb;
begin
  if not public.geoportal_es_admin(p_solicitante) then raise exception 'No autorizado'; end if;
  if p_horario not in ('laboral','extendido','sin_restriccion') then raise exception 'Horario inválido'; end if;
  if p_dias not in ('habiles','todos') then raise exception 'Días inválidos'; end if;
  select to_jsonb(lb) - 'creado_en' - 'creado_por' into v_antes from public.geoportal_lista_blanca lb where lb.email = lower(p_email);
  if v_antes is not null and v_antes->>'rol' <> 'admin' and not public.geoportal_aislamiento_verificado()
     and ((p_registro_tecnico is true and (v_antes->>'ver_registro_tecnico')::boolean is not true)
       or (p_dashboard_tecnico is true and (v_antes->>'ver_dashboard_tecnico')::boolean is not true)
       or (p_dashboard_redes is true and (v_antes->>'ver_dashboard_redes')::boolean is not true)
       or (p_campo is true and (v_antes->>'ver_campo')::boolean is not true)
       or (p_dashboard_campo is true and (v_antes->>'ver_dashboard_campo')::boolean is not true)
       or (p_acta is true and (v_antes->>'ver_acta')::boolean is not true)
       or (p_dashboard_acta is true and (v_antes->>'ver_dashboard_acta')::boolean is not true)
       or (p_aseo is true and (v_antes->>'ver_aseo')::boolean is not true)
       or (p_dashboard_aseo is true and (v_antes->>'ver_dashboard_aseo')::boolean is not true)) then
    raise exception 'Antes de dar permisos técnicos, de campo, de acta o de aseo debe verificarse el bloqueo de las funciones comerciales (aislamiento)';
  end if;
  update public.geoportal_lista_blanca
  set ver_explorar = p_explorar, ver_focalizacion = p_focalizacion, ver_comercial = p_comercial, ver_rutas = p_rutas, ver_dashboard = p_dashboard,
      ver_registro_tecnico  = coalesce(p_registro_tecnico, ver_registro_tecnico),
      ver_dashboard_tecnico = coalesce(p_dashboard_tecnico, ver_dashboard_tecnico),
      ver_campo             = coalesce(p_campo, ver_campo),
      ver_dashboard_campo   = coalesce(p_dashboard_campo, ver_dashboard_campo),
      ver_acta              = coalesce(p_acta, ver_acta),
      ver_dashboard_acta    = coalesce(p_dashboard_acta, ver_dashboard_acta),
      ver_aseo              = coalesce(p_aseo, ver_aseo),
      ver_dashboard_aseo    = coalesce(p_dashboard_aseo, ver_dashboard_aseo),
      ver_analisis_contrato = coalesce(p_analisis_contrato, ver_analisis_contrato),
      ver_dashboard_redes   = coalesce(p_dashboard_redes, ver_dashboard_redes),
      horario = p_horario, dias = p_dias
  where email = lower(p_email);
  if not found then return false; end if;
  select to_jsonb(lb) - 'creado_en' - 'creado_por' into v_despues from public.geoportal_lista_blanca lb where lb.email = lower(p_email);
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
  values (lower(p_solicitante), 'admin_cambiar_permisos', lower(p_email), jsonb_build_object('antes', v_antes, 'despues', v_despues), p_ip);
  return true;
end;
$function$;


drop function public.geoportal_admin_listar(text);

create function public.geoportal_admin_listar(p_solicitante text)
 returns table(email text, nombre text, rol text, activo boolean, creado_en timestamp with time zone, ver_explorar boolean, ver_focalizacion boolean, ver_comercial boolean, ver_rutas boolean, ver_dashboard boolean, horario text, dias text, ver_registro_tecnico boolean, ver_dashboard_tecnico boolean, ver_campo boolean, ver_dashboard_campo boolean, ver_acta boolean, ver_dashboard_acta boolean, ver_aseo boolean, ver_dashboard_aseo boolean, ver_analisis_contrato boolean, ver_dashboard_redes boolean)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select lb.email, lb.nombre, lb.rol, lb.activo, lb.creado_en, lb.ver_explorar, lb.ver_focalizacion, lb.ver_comercial, lb.ver_rutas, lb.ver_dashboard,
         lb.horario, lb.dias, lb.ver_registro_tecnico, lb.ver_dashboard_tecnico, lb.ver_campo, lb.ver_dashboard_campo, lb.ver_acta, lb.ver_dashboard_acta, lb.ver_aseo, lb.ver_dashboard_aseo, lb.ver_analisis_contrato, lb.ver_dashboard_redes
  from public.geoportal_lista_blanca lb
  where public.geoportal_es_admin(p_solicitante)
  order by lb.creado_en;
$function$;

revoke all on function public.geoportal_admin_permisos(text, text, boolean, boolean, boolean, boolean, text, text, boolean, boolean, boolean, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_admin_listar(text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_puede(text, text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_mis_permisos(text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_admin_permisos(text, text, boolean, boolean, boolean, boolean, text, text, boolean, boolean, boolean, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) to service_role;
grant execute on function public.geoportal_admin_listar(text) to service_role;
grant execute on function public.geoportal_puede(text, text) to service_role;
grant execute on function public.geoportal_mis_permisos(text) to service_role;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 24 — PERFILES DE REDES CON ver_dashboard_redes (D-12, §16 de la bitácora)
-- Hasta el 3b, «supervisor» en redes era ver_dashboard_tecnico (el supervisor de planta). Desde aquí:
--   · administrador: siempre;
--   · SUPERVISOR de distribución: ver_dashboard_redes (bandejas, valores, galería, editar la ficha salvo el origen, captura sin asignación);
--   · operador: cualquier otra persona de Técnica (incluido el supervisor de planta, que en redes ya no supervisa).
-- Reemplaza redes.f_perfil_lectura (1a) y redes.f_editor_ficha (3b), con la misma firma. Las demás funciones los llaman y cambian solas.
-- =====================================================================

-- ¿Supervisor de distribución (o administrador)?
create function redes.f_es_supervisor_redes(p_email text) returns boolean
language sql stable security definer set search_path to 'public', 'pg_temp' as $f$
  select public.geoportal_es_admin(p_email) or public.geoportal_puede(p_email, 'dashboard_redes') $f$;

-- Perfil de Técnica para leer redes: 'admin' | 'supervisor' (distribución) | 'operador'. Sin perfil, o desactivado en Técnica: 42501.
create or replace function redes.f_perfil_lectura(p_solicitante text, out email text, out perfil text)
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_tec text;
begin
  email := lower(btrim(coalesce(p_solicitante, '')));
  if email = '' or position('@' in email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if public.geoportal_es_admin(email) then perfil := 'admin'; return; end if;
  v_tec := tecnica.f_perfil(email);
  perfil := case when public.geoportal_puede(email, 'dashboard_redes') then 'supervisor' when v_tec is not null then 'operador' end;
  if perfil is null then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  if not tecnica.f_tecnica_activa(email) then raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501'; end if;
end $f$;

-- Captura (daño e intervención): el supervisor de distribución pasa sin tener el formulario asignado; los demás, con la regla de Técnica de siempre.
create function redes.f_autorizar_captura_redes(p_solicitante text, p_formulario text) returns text
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email <> '' and position('@' in v_email) > 1 and public.geoportal_estado_acceso(v_email) = 'ok' and public.geoportal_puede(v_email, 'dashboard_redes') then
    if not public.geoportal_es_admin(v_email) and not tecnica.f_tecnica_activa(v_email) then raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501'; end if;
    return v_email;
  end if;
  return tecnica.f_autorizar_captura(p_solicitante, p_formulario);
end $f$;

-- Editar la ficha: el administrador y el supervisor de distribución (§26.2). El origen solo el administrador (lo exige ficha_editar).
create or replace function redes.f_editor_ficha(p_solicitante text) returns text
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p.perfil not in ('admin', 'supervisor') then raise exception 'Solo el administrador o el supervisor de distribución editan la ficha del activo' using errcode = '42501'; end if;
  return p.email;
end $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 25 — REEMPLAZOS DE RPC DEL 3b (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- es el texto vivo de cada una con cambios exactos, cada uno aplicado una sola vez:
--   · captura con redes.f_autorizar_captura_redes (el supervisor de distribución pasa sin el formulario asignado);
--   · «supervisor» = administrador o supervisor de distribución (redes.f_es_supervisor_redes), no el de planta;
--   · §25.8: nadie registra «sin evidencia fotográfica»; siempre al menos una foto (daño e intervención);
--   · §25.1: el sector del daño es un número del 1 al 100 (columna nueva sector_num);
--   · §26.1: la galería y la foto principal también para el operador; §26.2: edita el supervisor de distribución; el origen solo el administrador.
-- =====================================================================

-- geoportal_redes_formulario_dano
CREATE OR REPLACE FUNCTION public.geoportal_redes_formulario_dano(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'danos_fallas');
begin
  return jsonb_build_object(
    'perfil', tecnica.f_perfil(v_email),
    'sistemas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.sistemas where codigo in ('acueducto', 'alcantarillado')),
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'clase', clase, 'nombre', nombre, 'sistemas', to_jsonb(sistemas), 'pide_rotura', pide_rotura) order by orden) from redes.tipos_dano where activo),
    'roturas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.tipos_rotura where activo),
    'causas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.causas where activo),
    'terceros', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.tipos_tercero where activo),
    'marcas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.marcas_riesgo where activo),
    'reglas', jsonb_build_object('dias_atras_max', redes.f_param('dano_dias_atras_max'), 'min_fotos', redes.f_param('min_fotos_dano'), 'max_fotos', redes.f_param('max_fotos_dano'),
                                 'max_bytes_foto', redes.f_param('max_bytes_foto_dano'), 'max_horas_inicio', tecnica.f_max_horas_inicio(),
                                 'radio_cercanos_m', redes.f_param('distancia_activo_cercano_m'), 'zoom_min', redes.f_param('mini_zoom_min'), 'zoom_accesorios', redes.f_param('mini_zoom_acc')),
    'hay_tabla_caudales', exists (select 1 from redes.caudales_fuga),
    'ahora', clock_timestamp());
end $function$;

-- geoportal_redes_preparar_dano
CREATE OR REPLACE FUNCTION public.geoportal_redes_preparar_dano(p_solicitante text, p_fotos integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'danos_fallas'); v_id uuid := gen_random_uuid();
        v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM'); v_max integer := redes.f_param('max_fotos_dano')::integer; v_min integer;
begin
  v_min := redes.f_param('min_fotos_dano')::integer;      -- §25.8: al menos una foto, para todos
  if p_fotos is null or p_fotos < v_min or p_fotos > v_max then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', v_min, v_max));
  end if;
  insert into redes.dano_preparaciones (dano_id, autor, fotos) values (v_id, v_email, p_fotos);
  return jsonb_build_object('dano_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_dano')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'danos/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n) from generate_series(1, p_fotos) n), '[]'::jsonb));
end $function$;

-- geoportal_redes_crear_dano
CREATE OR REPLACE FUNCTION public.geoportal_redes_crear_dano(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'danos_fallas'); d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_dano%rowtype; v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text;
  v_t_ini timestamptz; v_t_det timestamptz; v_t_rep timestamptz; v_t_res timestamptz; v_inicio timestamptz;
  v_lat numeric; v_lon numeric; v_fuera boolean; v_fotos jsonb := coalesce(p_datos -> 'fotos', '[]'::jsonb); v_n integer; v_f jsonb; v_ruta text; v_size bigint; v_mime text;
  v_ref jsonb := '[]'::jsonb; v_cons bigint; v_codigo text; v_tipo redes.tipos_dano%rowtype; v_marcas text[]; v_causa text; v_ter text; v_ter_nom text;
  v_desc text := nullif(btrim(coalesce(d ->> 'descripcion', '')), ''); v_max_bytes bigint := redes.f_param('max_bytes_foto_dano')::bigint;
  v_super boolean := redes.f_es_supervisor_redes(v_email); v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
  v_sector smallint;
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador del daño: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_dano where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'fuera_de_zona', v_prev.fuera_de_zona, 'sin_evidencia', not exists (select 1 from redes.dano_fotos f where f.dano_id = p_id), 'repetido', true);
  end if;
  if not exists (select 1 from redes.dano_preparaciones where dano_id = p_id and autor = v_email) then perform tecnica.f_error('Primero debe prepararse la subida de este daño'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos del daño no son válidos'); end if;

  -- qué pasó
  select * into v_tipo from redes.tipos_dano where codigo = d ->> 'tipo' and activo;
  if not found then perform tecnica.f_error('Elija qué pasó'); end if;
  if d ->> 'clase' is distinct from v_tipo.clase then perform tecnica.f_error('El tipo elegido no corresponde a daño o falla'); end if;
  if coalesce(d ->> 'sistema', '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;
  if not ((d ->> 'sistema') = any (v_tipo.sistemas)) then perform tecnica.f_error(format('«%s» no aplica a %s', v_tipo.nombre, d ->> 'sistema')); end if;

  -- activo o «no identificado»
  if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado then perform tecnica.f_error('El activo elegido no existe o está retirado: elíjalo de nuevo en el mapa'); end if;
    if v_act.sistema <> d ->> 'sistema' then perform tecnica.f_error('El activo elegido no es de ese sistema'); end if;
    v_activo := v_act.activo_id;
  else
    v_noid := nullif(btrim(coalesce(d ->> 'no_identificado', '')), '');
    if v_noid is null or length(v_noid) < 3 or length(v_noid) > 120 then perform tecnica.f_error('Elija el activo en el mapa o, si no lo identifica, diga qué es (3 a 120 caracteres)'); end if;
  end if;

  -- ubicación: nunca se rechaza por estar fuera de la zona (se marca)
  v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric;
  if v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then perform tecnica.f_error('Falta la ubicación del daño'); end if;
  if coalesce(d ->> 'ubicacion_origen', '') not in ('gps', 'mapa', 'activo') then perform tecnica.f_error('Falta de dónde sale la ubicación'); end if;
  v_fuera := v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max');

  -- tiempos (contra la hora del servidor)
  v_t_ini := redes.f_instante(d ->> 't_inicio_dano', 'inicio del daño');
  v_t_det := redes.f_instante(d ->> 't_detectado', 'detectado');
  v_t_rep := redes.f_instante(d ->> 't_inicio_reparacion', 'inicio de la reparación');
  v_t_res := redes.f_instante(d ->> 't_restablecido', 'servicio restablecido');
  if v_t_det is null then perform tecnica.f_error('Escriba cuándo se detectó'); end if;
  if greatest(v_t_ini, v_t_det, v_t_rep, v_t_res) > v_ahora + interval '2 minutes' then perform tecnica.f_error('Hay una hora en el futuro: revise la hora de su celular'); end if;
  if v_t_det < v_ahora - make_interval(days => redes.f_param('dano_dias_atras_max')::integer) then
    perform tecnica.f_error(format('La detección no puede ser de hace más de %s días', redes.f_param('dano_dias_atras_max')::integer));
  end if;
  if v_t_ini is not null and v_t_ini > v_t_det then perform tecnica.f_error('El inicio del daño no puede ser después de la detección'); end if;
  if v_t_rep is not null and v_t_rep < v_t_det then perform tecnica.f_error('El inicio de la reparación no puede ser antes de la detección'); end if;
  if v_t_res is not null and v_t_rep is null then perform tecnica.f_error('Para el servicio restablecido, escriba también el inicio de la reparación'); end if;
  if v_t_res is not null and v_t_res < v_t_rep then perform tecnica.f_error('El servicio restablecido no puede ser antes del inicio de la reparación'); end if;
  v_inicio := redes.f_instante(d ->> 'inicio_dispositivo', 'apertura del formulario');
  if v_inicio is not null and (v_inicio > v_ahora + interval '2 minutes' or v_inicio < v_ahora - make_interval(hours => tecnica.f_max_horas_inicio())) then
    perform tecnica.f_error(format('Este formulario se abrió hace más de %s horas o la hora de su celular está adelantada. Revise la hora y vuelva a enviar.', tecnica.f_max_horas_inicio()));
  end if;

  -- §25.1: el sector es un número entero del 1 al 100 (hoy 1 a 7). El texto viejo (sector_texto) ya no se llena.
  if d -> 'sector' is not null and jsonb_typeof(d -> 'sector') <> 'null' then
    if jsonb_typeof(d -> 'sector') <> 'number' or (d ->> 'sector') !~ '^[0-9]{1,3}$' or (d ->> 'sector')::integer not between 1 and 100 then
      perform tecnica.f_error('El sector es un número entero del 1 al 100');
    end if;
    v_sector := (d ->> 'sector')::smallint;
  end if;
  -- tamaño, afectación, riesgo y causa
  if d ->> 'tipo_rotura' is not null and not exists (select 1 from redes.tipos_rotura where codigo = d ->> 'tipo_rotura' and activo) then perform tecnica.f_error('El tipo de rotura no existe'); end if;
  if d ->> 'tipo_rotura' is not null and not v_tipo.pide_rotura then perform tecnica.f_error('Este tipo de daño no lleva tipo de rotura'); end if;
  if coalesce(d ->> 'riesgo', '') not in ('bajo', 'medio', 'alto') then perform tecnica.f_error('Elija el riesgo'); end if;
  if d -> 'marcas' is not null and jsonb_typeof(d -> 'marcas') <> 'array' then perform tecnica.f_error('Las marcas de riesgo no son válidas'); end if;
  v_marcas := coalesce(array(select distinct jsonb_array_elements_text(d -> 'marcas')), '{}');
  if exists (select 1 from unnest(v_marcas) m where not exists (select 1 from redes.marcas_riesgo r where r.codigo = m and r.activo)) then perform tecnica.f_error('Una marca de riesgo no existe'); end if;
  if coalesce(d ->> 'causa_clase', '') not in ('propia', 'terceros', 'desconocida') then perform tecnica.f_error('Elija la causa: propia, de terceros o desconocida'); end if;
  if d ->> 'causa_clase' = 'propia' then
    v_causa := d ->> 'causa';
    if not exists (select 1 from redes.causas where codigo = v_causa and activo) then perform tecnica.f_error('Elija la causa propia'); end if;
  elsif d ->> 'causa_clase' = 'terceros' then
    v_ter := d ->> 'tercero_tipo';
    if not exists (select 1 from redes.tipos_tercero where codigo = v_ter and activo) then perform tecnica.f_error('Elija quién lo causó'); end if;
    v_ter_nom := nullif(btrim(coalesce(d ->> 'tercero_nombre', '')), '');
    if v_ter_nom is not null and length(v_ter_nom) not between 2 and 120 then perform tecnica.f_error('El nombre, la empresa o la placa lleva de 2 a 120 caracteres'); end if;
  end if;
  if v_desc is not null and length(v_desc) > 1000 then perform tecnica.f_error('La descripción admite hasta 1.000 caracteres'); end if;

  -- fotos: el tamaño y el tipo se leen de Storage (nunca se le creen al celular). Sin fotos: solo supervisor o administrador, con el motivo.
  if jsonb_typeof(v_fotos) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_fotos);
  -- §25.8: nadie registra «sin evidencia fotográfica»; lo que llega sin foto entra por el reporte de anomalías
  if v_sinev is not null then
    perform tecnica.f_error('Ya no se registra «sin evidencia fotográfica»: tome al menos una foto del daño (lo que llega sin foto entra por el reporte de anomalías)');
  end if;
  if v_n < redes.f_param('min_fotos_dano') or v_n > redes.f_param('max_fotos_dano') or v_n > (select fotos from redes.dano_preparaciones where dano_id = p_id) then
    perform tecnica.f_error(format('Un daño lleva de %s a %s fotos', redes.f_param('min_fotos_dano')::integer, redes.f_param('max_fotos_dano')::integer));
  end if;
  if v_n > 0 and (select count(distinct (e ->> 'n')::integer) <> v_n or min((e ->> 'n')::integer) <> 1 or max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_fotos) e) then
    perform tecnica.f_error('El orden de las fotos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  if v_n > 0 and not exists (select 1 from jsonb_array_elements(v_fotos) e where e ->> 'momento' = 'dano') then perform tecnica.f_error('Falta una foto del daño'); end if;
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'n')::integer loop
    if coalesce(v_f ->> 'momento', '') not in ('dano', 'entorno', 'reparado') then perform tecnica.f_error('Cada foto dice si es del daño, del entorno o de la reparación'); end if;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^danos/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || '\.jpg$') then
      perform tecnica.f_error(format('La ruta de la foto %s no corresponde a este daño', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró la foto %s: súbala de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('La foto %s está vacía', v_f ->> 'n')); end if;
    if v_size > v_max_bytes then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'momento', v_f ->> 'momento', 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;

  -- código DAN-000123 (candado de fila del consecutivo) e inserción
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'DAN' returning ultimo into v_cons;
  v_codigo := 'DAN-' || lpad(v_cons::text, 6, '0');
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, no_ident_que_es, lat, lon, ubicacion_origen, precision_m, fuera_de_zona,
         t_inicio_dano, t_detectado, inicio_en, inicio_origen, tipo_rotura, largo_afectado_m, presion_mca, usuarios_sin_servicio, sector_texto, sector_num,
         riesgo, marcas, causa_clase, causa_codigo, tercero_tipo, descripcion, origen, autor, registrado_en)
  values (p_id, v_codigo, v_tipo.clase, v_tipo.codigo, d ->> 'sistema', v_activo, v_noid, round(v_lat, 6), round(v_lon, 6), d ->> 'ubicacion_origen',
          (d ->> 'precision_m')::numeric, v_fuera, v_t_ini, v_t_det, v_inicio, case when v_inicio is not null then 'dispositivo' end,
          d ->> 'tipo_rotura', (d ->> 'largo_afectado_m')::numeric, (d ->> 'presion_mca')::numeric, (d ->> 'usuarios_sin_servicio')::integer,
          null, v_sector, d ->> 'riesgo', v_marcas, d ->> 'causa_clase', v_causa, v_ter, v_desc, 'formulario', v_email, v_ahora);
  if v_ter_nom is not null then insert into redes.dano_datos_sensibles (dano_id, tercero_nombre) values (p_id, v_ter_nom); end if;
  if v_t_rep is not null then insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor) values (p_id, v_t_rep, v_t_res, 'formulario', v_email); end if;
  insert into redes.dano_fotos (dano_id, n, momento, ruta_storage, bytes, mime)
  select p_id, (x ->> 'n')::smallint, x ->> 'momento', x ->> 'ruta', (x ->> 'bytes')::integer, x ->> 'mime' from jsonb_array_elements(v_ref) x;
  -- «sin evidencia fotográfica»: queda como nota del daño, con el motivo
  if v_n = 0 then insert into redes.dano_eventos (dano_id, tipo, motivo, autor) values (p_id, 'nota', 'Sin evidencia fotográfica: ' || v_sinev, v_email); end if;
  -- auditoría sin el nombre del tercero ni la posición
  perform tecnica.f_auditar(v_email, 'redes_crear_dano', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'sistema', d ->> 'sistema', 'activo', v_act.codigo,
          'no_identificado', v_noid is not null, 'fotos', v_n, 'sin_evidencia', v_n = 0, 'riesgo', d ->> 'riesgo'), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo,
                                    'fuera_de_zona', x.fuera_de_zona, 'respuesta_s', x.respuesta_s, 'reparacion_s', x.reparacion_s, 'total_s', x.total_s,
                                    'perdida_estado', x.perdida_estado, 'sin_evidencia', v_n = 0, 'repetido', false) from redes.v_dano x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.danos where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_dano x where x.id = p_id);
  end if;
  perform tecnica.f_error('Una de las fotos ya está usada en otro daño');
  return null;
end $function$;

-- geoportal_redes_formulario_intervencion
CREATE OR REPLACE FUNCTION public.geoportal_redes_formulario_intervencion(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento');
        v_perfil text := case when public.geoportal_es_admin(v_email) then 'admin' when redes.f_es_supervisor_redes(v_email) then 'supervisor' else 'operador' end;
begin
  return jsonb_build_object(
    'perfil', v_perfil,
    'sistemas', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.sistemas where codigo in ('acueducto', 'alcantarillado')),
    'tipos', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'admite_dano', admite_dano, 'es_inversion', es_inversion) order by orden) from redes.tipos_intervencion where activo),
    'aportantes', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.entidades_aportantes where activo),
    'contratistas', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by nombre) from redes.contratistas where activo), '[]'::jsonb),
    'unidades', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.unidades_material where activo),
    -- tipos de activo que puede crear una inversión «activo nuevo», con sus clases (y si la clase es obligatoria)
    'tipos_nuevo', (select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre_visible, 'sistema', t.sistema, 'geometria', t.geometria,
                       'clases', coalesce((select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre) order by c.orden) from redes.clases_activo c where c.prefijo = t.prefijo), '[]'::jsonb),
                       'clase_obligatoria', exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean),
                       'lleva_diametro', exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'diametro_mm'))
                     order by t.orden)
                      from redes.v_tipo_visible t where t.sistema in ('acueducto', 'alcantarillado') and t.geometria in ('punto', 'linea')),
    'materiales', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.materiales),
    -- el operario conserva el tope de días y de horas; el supervisor y el administrador registran las obras largas sin ese tope (David, respuesta 1 al 3a)
    'reglas', jsonb_build_object('dias_atras_max', case when v_perfil in ('admin', 'supervisor') then null else redes.f_param('itv_dias_atras_max') end,
                                 'max_horas', case when v_perfil in ('admin', 'supervisor') then null else redes.f_param('itv_max_horas') end,
                                 'min_fotos', redes.f_param('min_fotos_itv'), 'puede_sin_fotos', false, 'pone_valores', v_perfil in ('admin', 'supervisor'),
                                 'max_fotos', redes.f_param('max_fotos_itv'), 'max_documentos', redes.f_param('max_docs_itv'),
                                 'max_bytes_foto', redes.f_param('max_bytes_foto_itv'), 'max_bytes_documento', redes.f_param('max_bytes_doc_itv'),
                                 'max_horas_inicio', tecnica.f_max_horas_inicio(), 'radio_cercanos_m', redes.f_param('distancia_activo_cercano_m'),
                                 'radio_danos_m', redes.f_param('itv_radio_danos_m'), 'max_tambien', redes.f_param('itv_max_activos_tambien'),
                                 'max_materiales', redes.f_param('itv_max_materiales'), 'zoom_min', redes.f_param('mini_zoom_min'), 'zoom_accesorios', redes.f_param('mini_zoom_acc')),
    'ahora', clock_timestamp());
end $function$;

-- geoportal_redes_danos_abiertos
CREATE OR REPLACE FUNCTION public.geoportal_redes_danos_abiertos(p_solicitante text, p_sistema text, p_activo text DEFAULT NULL::text, p_lat numeric DEFAULT NULL::numeric, p_lon numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento'); v_id bigint; v_ref geometry; v_radio numeric := redes.f_param('itv_radio_danos_m');
begin
  if coalesce(p_sistema, '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;
  if nullif(btrim(coalesce(p_activo, '')), '') is not null then
    v_id := redes.f_buscar_activo(p_activo);
    select geom into v_ref from redes.activo_vigente_mat where activo_id = v_id;
  elsif p_lat is not null and p_lon is not null and p_lat between -90 and 90 and p_lon between -180 and 180 then
    v_ref := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326);
  else perform tecnica.f_error('Elija primero el activo o marque el punto');
  end if;
  return jsonb_build_object('radio_m', v_radio, 'danos', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'clase', x.clase, 'tipo', x.tipo_nombre, 'activo', x.activo_codigo, 'no_identificado', x.no_ident_que_es,
                                        't_detectado', x.t_detectado, 'estado', x.estado, 'mismo_activo', x.mismo, 'distancia_m', x.dist) order by x.mismo desc, x.dist, x.t_detectado desc)
      from (select d.codigo, d.clase, d.tipo_nombre, d.activo_codigo, d.no_ident_que_es, d.t_detectado, d.estado,
                   coalesce(d.activo_id = v_id, false) as mismo, round(ST_Distance(d.geom::geography, v_ref::geography)::numeric, 0) as dist
              from redes.v_dano d
             where d.estado in ('reportado', 'en_atencion') and d.sistema = p_sistema
               and (d.activo_id = v_id or ST_DWithin(d.geom::geography, v_ref::geography, v_radio))
             order by 8 desc, 9, d.t_detectado desc limit 10) x), '[]'::jsonb));
end $function$;

-- geoportal_redes_preparar_intervencion
CREATE OR REPLACE FUNCTION public.geoportal_redes_preparar_intervencion(p_solicitante text, p_fotos integer, p_documentos integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento'); v_id uuid := gen_random_uuid();
        v_mes text := to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM'); v_min integer; v_max integer := redes.f_param('max_fotos_itv')::integer;
        v_maxd integer := redes.f_param('max_docs_itv')::integer; v_d integer := coalesce(p_documentos, 0);
begin
  v_min := redes.f_param('min_fotos_itv')::integer;      -- §25.8: al menos una foto, para todos
  if p_fotos is null or p_fotos < v_min or p_fotos > v_max then perform tecnica.f_error(format('Una intervención lleva de %s a %s fotos', v_min, v_max)); end if;
  if v_d < 0 or v_d > v_maxd then perform tecnica.f_error(format('Se adjuntan hasta %s documentos', v_maxd)); end if;
  insert into redes.intervencion_preparaciones (intervencion_id, autor, fotos, documentos) values (v_id, v_email, p_fotos, v_d);
  return jsonb_build_object('intervencion_id', v_id, 'bucket', 'redes-evidencias', 'max_bytes_foto', redes.f_param('max_bytes_foto_itv')::bigint,
    'max_bytes_documento', redes.f_param('max_bytes_doc_itv')::bigint,
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('n', n, 'ruta', 'intervenciones/' || v_mes || '/' || v_id::text || '/' || n || '.jpg', 'tipo_mime', 'image/jpeg') order by n)
                         from generate_series(1, p_fotos) n), '[]'::jsonb),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object('n', p_fotos + n, 'ruta', 'intervenciones/' || v_mes || '/' || v_id::text || '/' || (p_fotos + n) || '.pdf', 'tipo_mime', 'application/pdf') order by n)
                              from generate_series(1, v_d) n), '[]'::jsonb));
end $function$;

-- geoportal_redes_crear_intervencion
CREATE OR REPLACE FUNCTION public.geoportal_redes_crear_intervencion(p_solicitante text, p_id uuid, p_datos jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'storage', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento'); v_super boolean; d jsonb := coalesce(p_datos, '{}'::jsonb);
  v_ahora timestamptz := clock_timestamp(); v_prev redes.v_intervencion%rowtype; v_tipo redes.tipos_intervencion%rowtype; v_sis text; v_modo text;
  v_act redes.activo_vigente_mat%rowtype; v_activo bigint; v_noid text; v_nuevo jsonb; v_tn redes.v_tipo_visible%rowtype; v_geom_nuevo geometry;
  v_clase_n text; v_mat_n text; v_diam_n numeric; v_nom_n text; v_pts jsonb; v_p jsonb; v_lat numeric; v_lon numeric; v_fuera boolean;
  v_t_ini timestamptz; v_t_fin timestamptz; v_inicio timestamptz; v_desc text := btrim(coalesce(d ->> 'descripcion', ''));
  v_dano redes.v_dano%rowtype; v_tambien bigint[] := '{}'; v_x text; v_xid bigint; v_mats jsonb := coalesce(d -> 'materiales', '[]'::jsonb); v_m jsonb;
  v_fuentes jsonb; v_arch jsonb := coalesce(d -> 'archivos', '[]'::jsonb); v_ref jsonb := '[]'::jsonb; v_nf integer := 0; v_nd integer := 0; v_n integer;
  v_f jsonb; v_ruta text; v_size bigint; v_mime text; v_prep redes.intervencion_preparaciones%rowtype; v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
  v_cons bigint; v_codigo text; v_ctr bigint; v_ctr_nom text; v_orden text := nullif(btrim(coalesce(d ->> 'contrato_orden', '')), '');
  v_comp text := nullif(btrim(coalesce(d ->> 'companeros', '')), ''); v_pto geometry; v_creado boolean := false; v_origen text; v_aport text; v_cod_nuevo text;
  v_dano_estado text; v_resuelve boolean := coalesce((p_datos ->> 'resuelve_dano')::boolean, false);
begin
  if p_id is null then perform tecnica.f_error('Falta el identificador de la intervención: prepare la subida primero'); end if;
  -- reintento: mismo id y mismo autor devuelve lo guardado, sin revalidar
  select * into v_prev from redes.v_intervencion where id = p_id;
  if found then
    if v_prev.autor <> v_email then perform tecnica.f_error('Primero debe prepararse la subida de esta intervención'); end if;
    return jsonb_build_object('id', v_prev.id, 'codigo', v_prev.codigo, 'registrado_en', v_prev.registrado_en, 'estado', v_prev.estado, 'activo', v_prev.activo_codigo,
                              'activo_creado', v_prev.activo_creado, 'dano', v_prev.dano_codigo, 'sin_evidencia', v_prev.sin_evidencia, 'fuera_de_zona', v_prev.fuera_de_zona, 'repetido', true);
  end if;
  select * into v_prep from redes.intervencion_preparaciones where intervencion_id = p_id and autor = v_email;
  if not found then perform tecnica.f_error('Primero debe prepararse la subida de esta intervención'); end if;
  if jsonb_typeof(d) <> 'object' then perform tecnica.f_error('Los datos de la intervención no son válidos'); end if;
  v_super := redes.f_es_supervisor_redes(v_email);

  -- 1. de dónde nace y tipo
  if coalesce(d ->> 'nace_de', '') not in ('programada', 'dano') then perform tecnica.f_error('Elija de dónde nace: programada o mejora, o daño o falla'); end if;
  select * into v_tipo from redes.tipos_intervencion where codigo = d ->> 'tipo' and activo;
  if not found then perform tecnica.f_error('Elija el tipo de intervención'); end if;
  if d ->> 'nace_de' = 'dano' and not v_tipo.admite_dano then perform tecnica.f_error(format('«%s» no atiende un daño: elija correctivo, reparación o reposición', v_tipo.nombre)); end if;
  v_modo := d ->> 'inversion_modo';
  if v_tipo.es_inversion and coalesce(v_modo, '') not in ('nuevo', 'mejora') then perform tecnica.f_error('Diga qué tipo de inversión es: activo nuevo o mejora de un activo existente'); end if;
  if not v_tipo.es_inversion then v_modo := null; end if;
  v_sis := d ->> 'sistema';
  if coalesce(v_sis, '') not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Elija el sistema: acueducto o alcantarillado'); end if;

  -- 2. activo: el elegido, «no identificado» o el que crea la inversión
  if v_modo = 'nuevo' then
    v_nuevo := d -> 'nuevo';
    if nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null or d ->> 'no_identificado' is not null then perform tecnica.f_error('Una inversión en un activo nuevo no lleva un activo existente'); end if;
    if v_nuevo is null or jsonb_typeof(v_nuevo) <> 'object' then perform tecnica.f_error('Diga qué activo nuevo se construyó'); end if;
    select * into v_tn from redes.v_tipo_visible where prefijo = upper(coalesce(v_nuevo ->> 'prefijo', '')) and sistema = v_sis and geometria in ('punto', 'linea');
    if not found then perform tecnica.f_error('Elija el tipo del activo nuevo (del mismo sistema)'); end if;
    v_clase_n := nullif(v_nuevo ->> 'clase', '');
    if v_clase_n is not null and not exists (select 1 from redes.clases_activo where prefijo = v_tn.prefijo and codigo = v_clase_n) then perform tecnica.f_error('Esa clase no existe para el tipo elegido'); end if;
    if v_clase_n is null and exists (select 1 from jsonb_array_elements(v_tn.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean) then
      perform tecnica.f_error(format('Elija la clase del activo nuevo (%s)', v_tn.nombre_visible));
    end if;
    v_mat_n := nullif(v_nuevo ->> 'material', '');
    if v_mat_n is not null and not exists (select 1 from redes.materiales where codigo = v_mat_n) then perform tecnica.f_error('Ese material no existe'); end if;
    v_diam_n := (v_nuevo ->> 'diametro_mm')::numeric;
    if v_diam_n is not null and (v_diam_n <= 0 or v_diam_n > 5000) then perform tecnica.f_error('El diámetro va de 1 a 5.000 mm'); end if;
    v_nom_n := nullif(btrim(coalesce(v_nuevo ->> 'nombre', '')), '');
    if v_nom_n is not null and length(v_nom_n) > 120 then perform tecnica.f_error('El nombre del activo nuevo admite hasta 120 caracteres'); end if;
    v_pts := v_nuevo -> 'puntos';
    if v_pts is null or jsonb_typeof(v_pts) <> 'array' then perform tecnica.f_error('Marque en el mapa dónde quedó el activo nuevo'); end if;
    if v_tn.geometria = 'punto' and jsonb_array_length(v_pts) <> 1 then perform tecnica.f_error('Marque un solo punto para el activo nuevo'); end if;
    if v_tn.geometria = 'linea' and jsonb_array_length(v_pts) not between 2 and 50 then perform tecnica.f_error('Marque el inicio y el fin del tramo nuevo'); end if;
    for v_p in select e from jsonb_array_elements(v_pts) e loop
      if jsonb_typeof(v_p) <> 'array' or jsonb_array_length(v_p) <> 2 or (v_p ->> 0)::numeric not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max')
         or (v_p ->> 1)::numeric not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
        perform tecnica.f_error('El activo nuevo debe quedar dentro de Valledupar');
      end if;
    end loop;
    v_geom_nuevo := case when v_tn.geometria = 'punto' then ST_SetSRID(ST_MakePoint((v_pts -> 0 ->> 1)::double precision, (v_pts -> 0 ->> 0)::double precision), 4326)
                         else ST_SetSRID(ST_MakeLine(array(select ST_MakePoint((e ->> 1)::double precision, (e ->> 0)::double precision) from jsonb_array_elements(v_pts) with ordinality x(e, o) order by o)), 4326) end;
    if v_tn.geometria = 'linea' and ST_Length(v_geom_nuevo::geography) < 0.5 then perform tecnica.f_error('El tramo nuevo es demasiado corto: marque el inicio y el fin'); end if;
  elsif nullif(btrim(coalesce(d ->> 'activo', '')), '') is not null then
    select * into v_act from redes.activo_vigente_mat where codigo = upper(btrim(d ->> 'activo'));
    if not found or v_act.retirado then perform tecnica.f_error('El activo elegido no existe o está retirado: elíjalo de nuevo en el mapa'); end if;
    if v_act.sistema <> v_sis then perform tecnica.f_error('El activo elegido no es de ese sistema'); end if;
    v_activo := v_act.activo_id;
  else
    v_noid := nullif(btrim(coalesce(d ->> 'no_identificado', '')), '');
    if v_noid is null or length(v_noid) < 3 or length(v_noid) > 120 then perform tecnica.f_error('Elija el activo en el mapa o, si no lo identifica, diga qué es (3 a 120 caracteres)'); end if;
  end if;

  -- ubicación de la intervención: nunca se rechaza por estar fuera de la zona (se marca)
  v_lat := (d ->> 'lat')::numeric; v_lon := (d ->> 'lon')::numeric;
  if v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then perform tecnica.f_error('Falta la ubicación de la intervención'); end if;
  if coalesce(d ->> 'ubicacion_origen', '') not in ('gps', 'mapa', 'activo') then perform tecnica.f_error('Falta de dónde sale la ubicación'); end if;
  v_fuera := v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max');
  v_pto := ST_SetSRID(ST_MakePoint(v_lon, v_lat), 4326);

  -- activos también intervenidos (mismo sistema, vigentes, sin repetir y distintos del principal)
  if d -> 'tambien' is not null then
    if jsonb_typeof(d -> 'tambien') <> 'array' then perform tecnica.f_error('Los activos también intervenidos no son válidos'); end if;
    if jsonb_array_length(d -> 'tambien') > redes.f_param('itv_max_activos_tambien') then
      perform tecnica.f_error(format('Hasta %s activos también intervenidos', redes.f_param('itv_max_activos_tambien')::integer));
    end if;
    for v_x in select jsonb_array_elements_text(d -> 'tambien') loop
      select activo_id into v_xid from redes.activo_vigente_mat where codigo = upper(btrim(v_x)) and not retirado and sistema = v_sis;
      if v_xid is null then perform tecnica.f_error(format('El activo también intervenido «%s» no existe, está retirado o no es de ese sistema', v_x)); end if;
      if v_xid = v_activo then perform tecnica.f_error('El activo principal no va otra vez en «también intervenidos»'); end if;
      if v_xid = any (v_tambien) then perform tecnica.f_error(format('El activo «%s» está repetido en «también intervenidos»', v_x)); end if;
      v_tambien := v_tambien || v_xid;
    end loop;
  end if;

  -- 3. fechas y horas del trabajo (contra la hora del servidor)
  v_t_ini := redes.f_instante(d ->> 't_inicio', 'inicio');
  v_t_fin := redes.f_instante(d ->> 't_fin', 'fin');
  if v_t_ini is null or v_t_fin is null then perform tecnica.f_error('Escriba el inicio y el fin de la intervención'); end if;
  if v_t_fin > v_ahora + interval '2 minutes' then perform tecnica.f_error('El fin está en el futuro: la intervención se registra cuando ya se hizo'); end if;
  if v_t_ini > v_t_fin then perform tecnica.f_error('El inicio no puede ser después del fin'); end if;
  -- el tope de días y de horas es del operario; el supervisor y el administrador registran las obras largas desde el escritorio sin él
  if not v_super and v_t_ini < v_ahora - make_interval(days => redes.f_param('itv_dias_atras_max')::integer) then
    perform tecnica.f_error(format('El inicio no puede ser de hace más de %s días', redes.f_param('itv_dias_atras_max')::integer));
  end if;
  if not v_super and v_t_fin - v_t_ini > make_interval(hours => redes.f_param('itv_max_horas')::integer) then
    perform tecnica.f_error(format('Una intervención dura hasta %s horas: si duró más, la registra el supervisor desde el escritorio', redes.f_param('itv_max_horas')::integer));
  end if;
  v_inicio := redes.f_instante(d ->> 'inicio_dispositivo', 'apertura del formulario');
  if v_inicio is not null and (v_inicio > v_ahora + interval '2 minutes' or v_inicio < v_ahora - make_interval(hours => tecnica.f_max_horas_inicio())) then
    perform tecnica.f_error(format('Este formulario se abrió hace más de %s horas o la hora de su celular está adelantada. Revise la hora y vuelva a enviar.', tecnica.f_max_horas_inicio()));
  end if;

  -- daño que atiende: abierto, del mismo sistema y del activo, de un también intervenido o cercano
  if d ->> 'nace_de' = 'dano' then
    if nullif(btrim(coalesce(d ->> 'dano', '')), '') is null then perform tecnica.f_error('Elija el daño o falla que se atiende'); end if;
    perform pg_advisory_xact_lock(hashtext('redes.dano.' || upper(btrim(d ->> 'dano'))));
    select * into v_dano from redes.v_dano where codigo = upper(btrim(d ->> 'dano'));
    if not found then perform tecnica.f_error('Ese daño no existe'); end if;
    if v_dano.estado not in ('reportado', 'en_atencion') then perform tecnica.f_error(format('El daño %s ya está %s', v_dano.codigo, case v_dano.estado when 'atendido' then 'atendido' else 'oculto' end)); end if;
    if not redes.f_dano_elegible(v_dano, v_sis, array_remove(v_tambien || v_activo, null), v_pto) then
      perform tecnica.f_error(format('El daño %s no es de este activo ni de los cercanos (%s m)', v_dano.codigo, redes.f_param('itv_radio_danos_m')::integer));
    end if;
    if v_dano.t_inicio_reparacion is null and v_t_ini < v_dano.t_detectado then
      perform tecnica.f_error(format('La intervención empezó antes de que se detectara el daño %s: revise las horas', v_dano.codigo));
    end if;
    if v_resuelve and v_dano.t_inicio_reparacion is not null and v_t_fin < v_dano.t_inicio_reparacion then
      perform tecnica.f_error(format('La intervención terminó antes del inicio de la reparación que ya tenía el daño %s', v_dano.codigo));
    end if;
  elsif v_resuelve then
    perform tecnica.f_error('«Con esta queda resuelto el daño» solo va cuando la intervención nace de un daño');
  end if;

  -- 4. qué se hizo y materiales
  if length(v_desc) < 10 or length(v_desc) > 2000 then perform tecnica.f_error('Describa qué se hizo (10 a 2.000 caracteres)'); end if;
  if jsonb_typeof(v_mats) <> 'array' or jsonb_array_length(v_mats) > redes.f_param('itv_max_materiales') then perform tecnica.f_error(format('Hasta %s materiales', redes.f_param('itv_max_materiales')::integer)); end if;
  for v_m in select e from jsonb_array_elements(v_mats) e loop
    if jsonb_typeof(v_m) <> 'object' or length(btrim(coalesce(v_m ->> 'material', ''))) not between 2 and 80 then perform tecnica.f_error('Cada material lleva su nombre (2 a 80 caracteres)'); end if;
    if coalesce((v_m ->> 'cantidad')::numeric, 0) <= 0 or (v_m ->> 'cantidad')::numeric >= 1000000 then perform tecnica.f_error(format('La cantidad de «%s» no es válida', btrim(v_m ->> 'material'))); end if;
    if not exists (select 1 from redes.unidades_material where codigo = v_m ->> 'unidad' and activo) then perform tecnica.f_error(format('Elija la unidad de «%s»', btrim(v_m ->> 'material'))); end if;
  end loop;

  -- 5. quién la ejecuta
  if coalesce(d ->> 'ejecutor', '') not in ('emdupar', 'contratista') then perform tecnica.f_error('Diga quién la ejecuta: EMDUPAR o contratista'); end if;
  if d ->> 'ejecutor' = 'contratista' then
    if nullif(d ->> 'contratista', '') is not null then
      select id into v_ctr from redes.contratistas where codigo = d ->> 'contratista' and activo;
      if v_ctr is null then perform tecnica.f_error('Ese contratista no está en el catálogo'); end if;
    else
      v_ctr_nom := nullif(btrim(coalesce(d ->> 'contratista_nombre', '')), '');
      if v_ctr_nom is null or length(v_ctr_nom) not between 2 and 120 then perform tecnica.f_error('Elija o escriba el contratista'); end if;
    end if;
  elsif nullif(d ->> 'contratista', '') is not null or nullif(btrim(coalesce(d ->> 'contratista_nombre', '')), '') is not null then
    perform tecnica.f_error('El contratista solo va si la ejecuta un contratista');
  end if;
  if v_orden is not null and length(v_orden) > 60 then perform tecnica.f_error('El contrato u orden admite hasta 60 caracteres'); end if;
  if v_comp is not null and length(v_comp) not between 2 and 200 then perform tecnica.f_error('Los compañeros de cuadrilla admiten hasta 200 caracteres'); end if;

  -- 6. de dónde salen los recursos (D-8): el operario marca solo quién aporta; el supervisor y el administrador pueden poner valores
  v_fuentes := redes.f_fuentes_validas(d -> 'fuentes', v_super, false);

  -- 7. fotos (JPEG) y documentos (PDF): el tamaño y el tipo se leen de Storage (nunca se le creen al celular)
  if jsonb_typeof(v_arch) <> 'array' then perform tecnica.f_error('Las fotos no son válidas'); end if;
  v_n := jsonb_array_length(v_arch);
  if v_n > 0 and (select count(distinct (e ->> 'n')::integer) <> v_n or min((e ->> 'n')::integer) <> 1 or max((e ->> 'n')::integer) <> v_n from jsonb_array_elements(v_arch) e) then
    perform tecnica.f_error('El orden de los archivos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  for v_f in select e from jsonb_array_elements(v_arch) e order by (e ->> 'n')::integer loop
    if coalesce(v_f ->> 'clase', '') not in ('antes', 'durante', 'despues', 'documento') then perform tecnica.f_error('Cada foto dice si es de antes, de durante o de después'); end if;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^intervenciones/[0-9]{4}-[0-9]{2}/' || p_id::text || '/' || (v_f ->> 'n') || case when v_f ->> 'clase' = 'documento' then '\.pdf$' else '\.jpg$' end) then
      perform tecnica.f_error(format('La ruta del archivo %s no corresponde a esta intervención', v_f ->> 'n'));
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = v_ruta;
    if not found then perform tecnica.f_error(format('No se encontró el archivo %s: súbalo de nuevo', v_f ->> 'n')); end if;
    if coalesce(v_size, 0) <= 0 then perform tecnica.f_error(format('El archivo %s está vacío', v_f ->> 'n')); end if;
    if v_f ->> 'clase' = 'documento' then
      v_nd := v_nd + 1;
      if v_mime is distinct from 'application/pdf' then perform tecnica.f_error(format('El documento %s debe ser PDF', v_f ->> 'n')); end if;
      if v_size > redes.f_param('max_bytes_doc_itv') then perform tecnica.f_error(format('El documento %s pesa más de lo permitido (%s KB)', v_f ->> 'n', (redes.f_param('max_bytes_doc_itv') / 1024)::integer)); end if;
    else
      v_nf := v_nf + 1;
      if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error(format('La foto %s debe ser JPEG', v_f ->> 'n')); end if;
      if v_size > redes.f_param('max_bytes_foto_itv') then perform tecnica.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_f ->> 'n', (redes.f_param('max_bytes_foto_itv') / 1024)::integer)); end if;
    end if;
    v_ref := v_ref || jsonb_build_object('n', (v_f ->> 'n')::integer, 'clase', v_f ->> 'clase', 'ruta', v_ruta, 'bytes', v_size, 'mime', v_mime);
  end loop;
  if v_nf > v_prep.fotos or v_nd > v_prep.documentos or v_nf > redes.f_param('max_fotos_itv') or v_nd > redes.f_param('max_docs_itv') then
    perform tecnica.f_error(format('Una intervención lleva hasta %s fotos y %s documentos', redes.f_param('max_fotos_itv')::integer, redes.f_param('max_docs_itv')::integer));
  end if;
  -- en la calle, siempre al menos una foto; sin fotos solo el supervisor o el administrador (p. ej., desde el escritorio), con el motivo
  -- §25.8: nadie registra «sin evidencia fotográfica» (ni el supervisor ni el administrador); siempre al menos una foto
  if v_sinev is not null then
    perform tecnica.f_error('Ya no se registra «sin evidencia fotográfica»: tome al menos una foto de la intervención');
  end if;
  if v_nf < redes.f_param('min_fotos_itv') then
    perform tecnica.f_error(format('Tome al menos %s foto de la intervención', redes.f_param('min_fotos_itv')::integer));
  end if;

  -- código ITV-000123 (candado de fila del consecutivo)
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'ITV' returning ultimo into v_cons;
  v_codigo := 'ITV-' || lpad(v_cons::text, 6, '0');

  -- inversión, activo nuevo: el activo nace con la intervención, «por verificar», con su origen según quién aporta
  if v_modo = 'nuevo' then
    select case when bool_and(f ->> 'aportante' = 'emdupar') then 'emdupar' when bool_or(f ->> 'aportante' = 'emdupar') then 'mixto' else 'tercero' end,
           (select f2 ->> 'aportante' from jsonb_array_elements(v_fuentes) f2 where f2 ->> 'aportante' <> 'emdupar' order by (f2 ->> 'n')::integer limit 1)
      into v_origen, v_aport from jsonb_array_elements(v_fuentes) f;
    v_activo := redes.f_activo_crear(v_tn.prefijo, v_geom_nuevo, v_clase_n, v_mat_n, v_diam_n, v_nom_n, (v_t_fin at time zone 'America/Bogota')::date,
                                     jsonb_build_object('intervencion', v_codigo), v_origen, v_aport, v_email,
                                     format('Creado por la intervención %s (inversión, activo nuevo): por verificar', v_codigo));
    v_creado := true;
    v_cod_nuevo := (select codigo from redes.activos where id = v_activo);
  end if;

  insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, inversion_modo, sistema, activo_id, activo_creado, no_ident_que_es, lat, lon,
         ubicacion_origen, precision_m, fuera_de_zona, t_inicio, t_fin, inicio_en, inicio_origen, descripcion, ejecutor, contratista_id, contratista_nombre,
         contrato_orden, companeros, sin_evidencia_motivo, resuelve_dano, autor, registrado_en)
  values (p_id, v_codigo, d ->> 'nace_de', v_dano.id, v_tipo.codigo, v_modo, v_sis, v_activo, v_creado, v_noid, round(v_lat, 6), round(v_lon, 6),
          d ->> 'ubicacion_origen', (d ->> 'precision_m')::numeric, v_fuera, v_t_ini, v_t_fin, v_inicio, case when v_inicio is not null then 'dispositivo' end,
          v_desc, d ->> 'ejecutor', v_ctr, v_ctr_nom, v_orden, v_comp, v_sinev, v_resuelve, v_email, v_ahora);
  insert into redes.intervencion_activos (intervencion_id, activo_id, n) select p_id, x, o from unnest(v_tambien) with ordinality u(x, o);
  insert into redes.intervencion_materiales (intervencion_id, n, material, cantidad, unidad)
  select p_id, o, btrim(e ->> 'material'), (e ->> 'cantidad')::numeric, e ->> 'unidad' from jsonb_array_elements(v_mats) with ordinality x(e, o);
  insert into redes.intervencion_fuentes (intervencion_id, version, n, aportante_codigo, entidad, valor, porcentaje, soporte, fuente, autor)
  select p_id, 1, (f ->> 'n')::smallint, f ->> 'aportante', f ->> 'entidad', (f ->> 'valor')::numeric, (f ->> 'porcentaje')::numeric, f ->> 'soporte',
         case when v_super then 'supervisor' else 'formulario' end, v_email from jsonb_array_elements(v_fuentes) f;
  insert into redes.intervencion_archivos (intervencion_id, n, clase, ruta_storage, bytes, mime)
  select p_id, (x ->> 'n')::smallint, x ->> 'clase', x ->> 'ruta', (x ->> 'bytes')::integer, x ->> 'mime' from jsonb_array_elements(v_ref) x;
  insert into redes.intervencion_eventos (intervencion_id, tipo, autor) values (p_id, 'cerrada', v_email);       -- flujo A (D-6)
  if v_creado then
    insert into redes.intervencion_eventos (intervencion_id, tipo, activo_id, motivo, autor) values (p_id, 'crear_activo', v_activo, format('Inversión: se creó el activo %s, por verificar', v_cod_nuevo), v_email);
  end if;

  -- intervención que nace de un daño (un daño puede tener varias, David, respuesta 2 al 3a):
  --   · la primera le pone el inicio de la reparación (si no lo tenía) y el daño queda «en atención»;
  --   · la que marca «Con esta queda resuelto el daño» le pone el servicio restablecido y lo deja «atendido».
  if v_dano.id is not null then
    if v_dano.t_inicio_reparacion is null or v_resuelve then
      insert into redes.dano_tiempos (dano_id, t_inicio_reparacion, t_restablecido, fuente, autor)
      values (v_dano.id, case when v_dano.t_inicio_reparacion is null then v_t_ini end, case when v_resuelve then v_t_fin end, 'intervencion', v_email);
    end if;
    insert into redes.dano_eventos (dano_id, tipo, intervencion_id, motivo, autor)
    values (v_dano.id, case when v_resuelve then 'atendido' else 'en_atencion' end, p_id,
            case when v_resuelve then format('Resuelto con la intervención %s (%s)', v_codigo, v_tipo.nombre)
                 else format('Atendido en parte con la intervención %s (%s); sigue abierto', v_codigo, v_tipo.nombre) end, v_email);
    select x.estado into v_dano_estado from redes.v_dano x where x.id = v_dano.id;
  end if;

  -- auditoría sin la posición ni los valores
  perform tecnica.f_auditar(v_email, 'redes_crear_intervencion', v_codigo, jsonb_build_object('tipo', v_tipo.codigo, 'nace_de', d ->> 'nace_de', 'dano', v_dano.codigo,
          'sistema', v_sis, 'activo', coalesce(v_act.codigo, v_cod_nuevo), 'activo_creado', v_creado, 'no_identificado', v_noid is not null, 'tambien', cardinality(v_tambien),
          'fotos', v_nf, 'documentos', v_nd, 'sin_evidencia', v_nf = 0, 'ejecutor', d ->> 'ejecutor', 'resuelve_dano', v_resuelve), p_ip);
  return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'activo', x.activo_codigo, 'activo_creado', x.activo_creado,
                                    'dano', x.dano_codigo, 'dano_estado', v_dano_estado, 'recursos', x.recursos, 'sin_evidencia', x.sin_evidencia, 'fuera_de_zona', x.fuera_de_zona,
                                    'duracion_s', x.duracion_s, 'repetido', false) from redes.v_intervencion x where x.id = p_id);
exception when unique_violation then
  if exists (select 1 from redes.intervenciones where id = p_id and autor = v_email) then
    return (select jsonb_build_object('id', x.id, 'codigo', x.codigo, 'registrado_en', x.registrado_en, 'estado', x.estado, 'repetido', true) from redes.v_intervencion x where x.id = p_id);
  end if;
  perform tecnica.f_error('Uno de los archivos ya está usado en otra intervención');
  return null;
end $function$;

-- geoportal_redes_perfil
CREATE OR REPLACE FUNCTION public.geoportal_redes_perfil(p_solicitante text, p_ref text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare p record; v_id bigint; v redes.v_activo_vigente%rowtype; t redes.v_tipo_visible%rowtype; i redes.v_activo_identificadores%rowtype;
        v_super boolean; v_edita boolean; v_campos jsonb; o redes.v_activo_origen_vigente%rowtype; v_n integer;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  v_id := redes.f_buscar_activo(p_ref);
  select * into v from redes.v_activo_vigente where activo_id = v_id;
  select * into t from redes.v_tipo_visible where prefijo = v.prefijo;
  select * into i from redes.v_activo_identificadores where activo_id = v_id;
  v_super := true; v_edita := p.perfil in ('admin', 'supervisor');      -- §26: fotos para todos; edita el supervisor de distribución
  if v_super then select count(*) into v_n from redes.f_fotos_activo(v_id); end if;
  if v_edita then
    if p.perfil = 'admin' then select * into o from redes.v_activo_origen_vigente where activo_id = v_id; end if;      -- el origen solo el administrador
    -- campos por tipo que van en «atributos» (los demás son columnas de la versión). La longitud se calcula y el punto de macromedición es un enlace: no se editan.
    select coalesce(jsonb_agg(jsonb_build_object('clave', c ->> 'clave', 'rotulo', c ->> 'rotulo', 'tipo', coalesce(c ->> 'tipo', 'texto'), 'unidad', c ->> 'unidad',
                                                 'valor', v.atributos -> (c ->> 'clave')) order by o2), '[]'::jsonb)
      into v_campos from jsonb_array_elements(t.campos) with ordinality e(c, o2)
     where c ->> 'clave' not in ('diametro_mm', 'longitud_m', 'capacidad', 'profundidad_m', 'material_codigo', 'clase', 'efecto', 'punto_codigo');
  end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'codigo', v.codigo, 'alias', i.alias, 'placa', i.placa, 'sistema', v.sistema, 'geometria', t.geometria, 'perfil', p.perfil, 'editable', v_edita and not v.retirado,
    'foto_principal', case when v_super then redes.f_foto_principal(v_id) end,
    'fotos', case when v_super then v_n end,
    'edicion', case when v_edita then jsonb_build_object(
      'valores', jsonb_build_object('nombre', v.nombre, 'estado_codigo', v.estado_codigo, 'material_codigo', v.material_codigo, 'diametro_mm', v.diametro_mm, 'capacidad', v.capacidad,
                                    'profundidad_m', v.profundidad_m, 'fecha_instalacion', v.fecha_instalacion, 'barrio_sector', v.barrio_sector, 'clase', v.clase, 'efecto', v.efecto,
                                    'observaciones', v.atributos ->> 'observaciones', 'alias', i.alias, 'placa', i.placa,
                                    'origen', o.origen, 'aportante', o.aportante_codigo, 'origen_nota', o.nota),
      'campos_tipo', v_campos,
      'lleva', jsonb_build_object('diametro_mm', exists (select 1 from jsonb_array_elements(t.campos) c where c ->> 'clave' = 'diametro_mm'),
                                  'capacidad', exists (select 1 from jsonb_array_elements(t.campos) c where c ->> 'clave' = 'capacidad'),
                                  'profundidad_m', exists (select 1 from jsonb_array_elements(t.campos) c where c ->> 'clave' = 'profundidad_m'),
                                  'clase', exists (select 1 from redes.clases_activo c where c.prefijo = v.prefijo), 'efecto', v.prefijo = 'VAL'),
      'estados', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.estados_activo),
      'materiales', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.materiales),
      'clases', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.clases_activo where prefijo = v.prefijo), '[]'::jsonb),
      'efectos', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.efectos_valvula),
      'aportantes', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden) from redes.entidades_aportantes where activo),
      'max_bytes_foto', redes.f_param('max_bytes_foto_perfil'), 'puede_origen', p.perfil = 'admin') end));
end $function$;

-- geoportal_redes_galeria
CREATE OR REPLACE FUNCTION public.geoportal_redes_galeria(p_solicitante text, p_ref text, p_limite integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := (redes.f_perfil_lectura(p_solicitante)).email; v_id bigint := redes.f_buscar_activo(p_ref); v_lim integer := coalesce(p_limite, 30); v_r jsonb;
begin
  if v_lim < 1 or v_lim > 60 then perform tecnica.f_error('Se piden de 1 a 60 fotos'); end if;
  v_r := jsonb_build_object('codigo', (select codigo from redes.activos where id = v_id), 'total', (select count(*) from redes.f_fotos_activo(v_id)),
    'principal', redes.f_foto_principal(v_id),
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('origen', f.origen, 'codigo', f.codigo, 'clase', f.clase, 'ruta', f.ruta, 'cuando', f.cuando) order by f.cuando desc, f.ruta)
                         from (select * from redes.f_fotos_activo(v_id) order by cuando desc, ruta limit v_lim) f), '[]'::jsonb));
  perform tecnica.f_auditar(v_email, 'redes_galeria', v_r ->> 'codigo', jsonb_build_object('fotos', jsonb_array_length(v_r -> 'fotos')), null);
  return v_r;
end $function$;

-- geoportal_redes_ficha_editar
CREATE OR REPLACE FUNCTION public.geoportal_redes_ficha_editar(p_solicitante text, p_ref text, p_cambios jsonb, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare
  v_email text := redes.f_editor_ficha(p_solicitante); c jsonb := coalesce(p_cambios, '{}'::jsonb); v_id bigint; v redes.v_activo_vigente%rowtype;
  t redes.v_tipo_visible%rowtype; i redes.v_activo_identificadores%rowtype; o redes.v_activo_origen_vigente%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
  v_lista jsonb := '[]'::jsonb; v_k text; v_txt text; v_num numeric; v_fecha date; v_ver integer; v_ed bigint; v_hay_version boolean := false;
  n_nombre text; n_estado text; n_mat text; n_diam numeric; n_cap numeric; n_prof numeric; n_fecha date; n_barrio text; n_clase text; n_efecto text; n_attr jsonb;
  n_alias text; n_placa text; v_campos_attr text[]; v_rot text; v_or jsonb; n_origen text; n_aport text; n_nota text; v_cambia_origen boolean := false;
  v_alias_cambia boolean := false; v_placa_cambia boolean := false;
  -- rótulos fijos de las columnas
  r jsonb := '{"nombre": "Nombre", "estado_codigo": "Estado", "material_codigo": "Material", "diametro_mm": "Diámetro (mm)", "capacidad": "Capacidad",
               "profundidad_m": "Profundidad (m)", "fecha_instalacion": "Fecha de instalación", "barrio_sector": "Barrio o sector", "clase": "Clase",
               "efecto": "Efecto en la red", "observaciones": "Observaciones", "alias": "Alias", "placa": "Placa o número de inventario"}';
begin
  if jsonb_typeof(c) <> 'object' or c = '{}'::jsonb then perform tecnica.f_error('No hay cambios'); end if;
  if c ? 'origen' and not public.geoportal_es_admin(v_email) then raise exception 'El origen del activo solo lo corrige el administrador' using errcode = '42501'; end if;      -- §26.2
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo del cambio (10 caracteres o más)'); end if;
  for v_k in select jsonb_object_keys(c) loop
    if not (r ? v_k) and v_k not in ('atributos', 'origen') then perform tecnica.f_error(format('«%s» no se edita en la ficha', v_k)); end if;
  end loop;
  v_id := redes.f_buscar_activo(p_ref);
  perform pg_advisory_xact_lock(hashtext('redes.ficha.' || v_id));
  select * into v from redes.v_activo_vigente where activo_id = v_id;
  if v.retirado then perform tecnica.f_error('Ese activo está retirado: su ficha no se edita'); end if;
  select * into t from redes.v_tipo_visible where prefijo = v.prefijo;
  select * into i from redes.v_activo_identificadores where activo_id = v_id;
  n_nombre := v.nombre; n_estado := v.estado_codigo; n_mat := v.material_codigo; n_diam := v.diametro_mm; n_cap := v.capacidad; n_prof := v.profundidad_m;
  n_fecha := v.fecha_instalacion; n_barrio := v.barrio_sector; n_clase := v.clase; n_efecto := v.efecto; n_attr := v.atributos; n_alias := i.alias; n_placa := i.placa;
  v_campos_attr := array(select c2 ->> 'clave' from jsonb_array_elements(t.campos) c2
                          where c2 ->> 'clave' not in ('diametro_mm', 'longitud_m', 'capacidad', 'profundidad_m', 'material_codigo', 'clase', 'efecto', 'punto_codigo'));

  -- textos
  if c ? 'nombre' then n_nombre := nullif(btrim(coalesce(c ->> 'nombre', '')), ''); if length(n_nombre) > 120 then perform tecnica.f_error('El nombre admite hasta 120 caracteres'); end if; end if;
  if c ? 'barrio_sector' then n_barrio := nullif(btrim(coalesce(c ->> 'barrio_sector', '')), ''); if length(n_barrio) > 120 then perform tecnica.f_error('El barrio o sector admite hasta 120 caracteres'); end if; end if;
  -- catálogos
  if c ? 'estado_codigo' then
    n_estado := c ->> 'estado_codigo';
    if not exists (select 1 from redes.estados_activo where codigo = n_estado) then perform tecnica.f_error('Ese estado no existe'); end if;
  end if;
  if c ? 'material_codigo' then
    n_mat := nullif(c ->> 'material_codigo', '');
    if n_mat is not null and not exists (select 1 from redes.materiales where codigo = n_mat) then perform tecnica.f_error('Ese material no existe'); end if;
  end if;
  if c ? 'clase' then
    n_clase := nullif(c ->> 'clase', '');
    if n_clase is not null and not exists (select 1 from redes.clases_activo where prefijo = v.prefijo and codigo = n_clase) then perform tecnica.f_error('Esa clase no existe para este tipo'); end if;
    if n_clase is null and exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean) then perform tecnica.f_error('La clase de este tipo es obligatoria'); end if;
  end if;
  if c ? 'efecto' then
    n_efecto := nullif(c ->> 'efecto', '');
    if v.prefijo <> 'VAL' and n_efecto is not null then perform tecnica.f_error('El efecto solo aplica a las válvulas'); end if;
    if n_efecto is not null and not exists (select 1 from redes.efectos_valvula where codigo = n_efecto) then perform tecnica.f_error('Ese efecto no existe'); end if;
  end if;
  -- números
  if c ? 'diametro_mm' then n_diam := (c ->> 'diametro_mm')::numeric; if n_diam is not null and (n_diam <= 0 or n_diam > 5000) then perform tecnica.f_error('El diámetro va de 1 a 5.000 mm'); end if; end if;
  if c ? 'capacidad' then n_cap := (c ->> 'capacidad')::numeric; if n_cap is not null and n_cap < 0 then perform tecnica.f_error('La capacidad no puede ser negativa'); end if; end if;
  if c ? 'profundidad_m' then n_prof := (c ->> 'profundidad_m')::numeric; if n_prof is not null and (n_prof < 0 or n_prof > 200) then perform tecnica.f_error('La profundidad va de 0 a 200 m'); end if; end if;
  if c ? 'fecha_instalacion' then
    n_fecha := nullif(c ->> 'fecha_instalacion', '')::date;
    if n_fecha is not null and (n_fecha < date '1900-01-01' or n_fecha > (clock_timestamp() at time zone 'America/Bogota')::date) then perform tecnica.f_error('La fecha de instalación no es válida (ni futura ni antes de 1900)'); end if;
  end if;
  -- observaciones y campos por tipo (en atributos)
  if c ? 'observaciones' then
    v_txt := nullif(btrim(coalesce(c ->> 'observaciones', '')), '');
    if length(v_txt) > 1000 then perform tecnica.f_error('Las observaciones admiten hasta 1.000 caracteres'); end if;
    n_attr := case when v_txt is null then n_attr - 'observaciones' else jsonb_set(n_attr, '{observaciones}', to_jsonb(v_txt)) end;
  end if;
  if c ? 'atributos' then
    if jsonb_typeof(c -> 'atributos') <> 'object' then perform tecnica.f_error('Los campos del tipo no son válidos'); end if;
    for v_k in select jsonb_object_keys(c -> 'atributos') loop
      if not (v_k = any (v_campos_attr)) then perform tecnica.f_error(format('«%s» no es un campo de este tipo de activo', v_k)); end if;
      if jsonb_typeof(c -> 'atributos' -> v_k) not in ('number', 'string', 'null') or length(c -> 'atributos' ->> v_k) > 120 then perform tecnica.f_error(format('El valor de «%s» no es válido', v_k)); end if;
      n_attr := case when jsonb_typeof(c -> 'atributos' -> v_k) = 'null' or btrim(c -> 'atributos' ->> v_k) = '' then n_attr - v_k else jsonb_set(n_attr, array[v_k], c -> 'atributos' -> v_k) end;
    end loop;
  end if;
  -- alias y placa (la placa no se repite entre activos)
  if c ? 'alias' then
    n_alias := nullif(btrim(coalesce(c ->> 'alias', '')), '');
    if n_alias is not null and length(n_alias) not between 2 and 60 then perform tecnica.f_error('El alias lleva de 2 a 60 caracteres'); end if;
  end if;
  if c ? 'placa' then
    n_placa := nullif(btrim(coalesce(c ->> 'placa', '')), '');
    if n_placa is not null and n_placa !~ '^[A-Za-z0-9][A-Za-z0-9./ _-]{0,39}$' then perform tecnica.f_error('La placa o número de inventario lleva de 1 a 40 letras, números, punto, guion o barra'); end if;
    perform pg_advisory_xact_lock(hashtext('redes.placa'));
    if n_placa is not null and exists (select 1 from redes.v_activo_identificadores x where lower(x.placa) = lower(n_placa) and x.activo_id <> v_id) then
      perform tecnica.f_error(format('La placa «%s» ya la tiene otro activo (%s)', n_placa,
        (select a.codigo from redes.v_activo_identificadores x join redes.activos a on a.id = x.activo_id where lower(x.placa) = lower(n_placa) and x.activo_id <> v_id limit 1)));
    end if;
  end if;
  -- origen (solo lo ve el supervisor; aquí lo corrige quien edita la ficha)
  if c ? 'origen' then
    v_or := c -> 'origen';
    if jsonb_typeof(v_or) <> 'object' then perform tecnica.f_error('El origen no es válido'); end if;
    select * into o from redes.v_activo_origen_vigente where activo_id = v_id;
    n_origen := v_or ->> 'origen'; n_aport := nullif(v_or ->> 'aportante', ''); n_nota := nullif(btrim(coalesce(v_or ->> 'nota', '')), '');
    if coalesce(n_origen, '') not in ('emdupar', 'tercero', 'mixto') then perform tecnica.f_error('Elija el origen: EMDUPAR, tercero o tercero y EMDUPAR'); end if;
    if n_origen = 'emdupar' then n_aport := null; end if;
    if n_origen <> 'emdupar' and not exists (select 1 from redes.entidades_aportantes where codigo = n_aport and activo) then perform tecnica.f_error('Diga quién lo entregó (el aportante)'); end if;
    if length(n_nota) > 500 then perform tecnica.f_error('La nota del origen admite hasta 500 caracteres'); end if;
    v_cambia_origen := o.origen is distinct from n_origen or o.aportante_codigo is distinct from n_aport or o.nota is distinct from n_nota;
  end if;

  -- qué cambió, de A a B (solo lo que de verdad cambia)
  select coalesce(jsonb_agg(jsonb_build_object('campo', x.campo, 'rotulo', rr.rotulo, 'antes', redes.f_texto_valor(x.campo, x.antes, v.prefijo),
                                               'despues', redes.f_texto_valor(x.campo, x.despues, v.prefijo)) order by x.o), '[]'::jsonb)
    into v_lista
    from (values (1, 'nombre', v.nombre, n_nombre), (2, 'estado_codigo', v.estado_codigo, n_estado), (3, 'clase', v.clase, n_clase), (4, 'efecto', v.efecto, n_efecto),
                 (5, 'material_codigo', v.material_codigo, n_mat), (6, 'diametro_mm', trim_scale(v.diametro_mm)::text, trim_scale(n_diam)::text), (7, 'capacidad', trim_scale(v.capacidad)::text, trim_scale(n_cap)::text),
                 (8, 'profundidad_m', trim_scale(v.profundidad_m)::text, trim_scale(n_prof)::text), (9, 'fecha_instalacion', v.fecha_instalacion::text, n_fecha::text),
                 (10, 'barrio_sector', v.barrio_sector, n_barrio), (11, 'observaciones', v.atributos ->> 'observaciones', n_attr ->> 'observaciones'),
                 (12, 'alias', i.alias, n_alias), (13, 'placa', i.placa, n_placa)) x(o, campo, antes, despues)
         cross join lateral (select r ->> x.campo as rotulo) rr
   where x.antes is distinct from x.despues;
  v_alias_cambia := i.alias is distinct from n_alias; v_placa_cambia := i.placa is distinct from n_placa;
  -- campos del tipo que cambiaron
  v_lista := v_lista || coalesce((select jsonb_agg(jsonb_build_object('campo', 'atributos.' || k, 'rotulo', coalesce((select c2 ->> 'rotulo' from jsonb_array_elements(t.campos) c2 where c2 ->> 'clave' = k), k),
                                                                      'antes', v.atributos ->> k, 'despues', n_attr ->> k) order by k)
                                    from unnest(v_campos_attr) k where (v.atributos -> k) is distinct from (n_attr -> k)), '[]'::jsonb);
  if v_cambia_origen then v_lista := v_lista || jsonb_build_array(jsonb_build_object('campo', 'origen', 'rotulo', 'Origen', 'antes', o.origen, 'despues', n_origen)); end if;
  if jsonb_array_length(v_lista) = 0 then perform tecnica.f_error('No hay cambios: los valores son los mismos de la ficha'); end if;
  v_hay_version := exists (select 1 from jsonb_array_elements(v_lista) x where x ->> 'campo' not in ('alias', 'placa', 'origen'));

  -- versión nueva (datos del activo), con la huella del motor de carga
  if v_hay_version then
    v_ver := (select max(version) from redes.activo_versiones where activo_id = v_id) + 1;
    insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m, fecha_instalacion,
           estado_codigo, barrio_sector, atributos, codigo_anterior, capa_codigo, llave_capa, carga_id, huella, autor)
    values (v_id, v_ver, v.geom, n_nombre, n_clase, n_efecto, n_mat, n_diam, v.longitud_m, n_cap, n_prof, n_fecha, n_estado, n_barrio, n_attr, v.codigo_anterior,
            v.capa_codigo, v.llave_capa, null,
            redes.f_huella(v.geom, jsonb_build_object('p', v.prefijo, 'n', n_nombre, 'c', n_clase, 'e', n_efecto, 'm', n_mat, 'd', n_diam, 'l', v.longitud_m, 'pr', n_prof,
                                                      'ca', n_cap, 's', n_estado, 'ant', v.codigo_anterior, 'a', n_attr)), v_email);
  end if;
  insert into redes.ficha_ediciones (activo_id, version, cambios, motivo, autor) values (v_id, v_ver, v_lista, v_mot, v_email) returning id into v_ed;
  if v_alias_cambia then insert into redes.activo_identificador_eventos (activo_id, campo, valor, edicion_id, autor) values (v_id, 'alias', n_alias, v_ed, v_email); end if;
  if v_placa_cambia then insert into redes.activo_identificador_eventos (activo_id, campo, valor, edicion_id, autor) values (v_id, 'placa', n_placa, v_ed, v_email); end if;
  if v_cambia_origen then
    insert into redes.activo_origen (activo_id, version, origen, aportante_codigo, soporte_ruta, nota, autor)
    values (v_id, coalesce(v_ver, v.version), n_origen, n_aport, o.soporte_ruta, n_nota, v_email);
  end if;
  if v_hay_version then
    perform redes.f_mat_refrescar_uno(v_id);
    perform redes.f_subir_tesela(v.sistema);
  end if;
  perform tecnica.f_auditar(v_email, 'redes_ficha_editar', v.codigo, jsonb_build_object('version', v_ver, 'campos', (select jsonb_agg(x ->> 'campo') from jsonb_array_elements(v_lista) x)), null);
  return jsonb_build_object('codigo', v.codigo, 'version', coalesce(v_ver, v.version), 'version_nueva', v_hay_version, 'edicion', v_ed,
    'cambios', (select jsonb_agg(case when x ->> 'campo' = 'origen' then jsonb_build_object('campo', 'origen', 'rotulo', 'Origen') else x end) from jsonb_array_elements(v_lista) x));
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 26 — RPC NUEVAS DEL DASHBOARD DISTRIBUCIÓN: perfil del usuario, daños y fallas (lista, ocultar, reincluir, reabrir,
-- nombre del tercero con lectura auditada), intervenciones (ocultar, reincluir, anular), reportes del bot (lista) y crear el activo desde la bandeja.
-- PROPUESTA. No se ha ejecutado en la base real. Todas security definer, search_path fijo, mensajes con HINT msg_usuario; solo service_role.
-- Supervisión = administrador o supervisor de distribución (redes.f_supervisor sobre el perfil de 24). Nada se borra: todo es un evento con motivo.
-- =====================================================================

-- ---------- El perfil de redes de quien entra (para mostrar el Dashboard distribución) ----------
create function public.geoportal_redes_mi_perfil(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  return jsonb_build_object('perfil', p.perfil, 'dashboard_redes', p.perfil in ('admin', 'supervisor'), 'dashboard_ptap', public.geoportal_puede(p.email, 'dashboard_tecnico'));
end $f$;

-- ---------- Daños y fallas ----------
create function public.geoportal_redes_danos(p_solicitante text, p_filtro text default 'abiertos', p_limite integer default 100)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 've la lista de daños y fallas'); v_lim integer := coalesce(p_limite, 100);
begin
  if coalesce(p_filtro, '') not in ('abiertos', 'todos', 'ocultos', 'no_identificados') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_lim < 1 or v_lim > 300 then perform tecnica.f_error('Se piden de 1 a 300'); end if;
  return jsonb_build_object('filtro', p_filtro, 'danos', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'clase', x.clase, 'tipo', x.tipo_nombre, 'sistema', x.sistema, 'activo', x.activo_codigo, 'no_identificado', x.no_ident_que_es,
             'estado', x.estado, 't_detectado', x.t_detectado, 'riesgo', x.riesgo, 'causa_clase', x.causa_clase, 'sector', x.sector_num, 'origen', x.origen, 'autor', x.autor,
             'total_s', x.total_s, 'fotos', x.fotos, 'intervenciones', x.itv, 'tiene_tercero', x.tercero) order by x.t_detectado desc)
      from (select d.*, n.sector_num,
                   (select count(*) from redes.dano_fotos f where f.dano_id = d.id) as fotos,
                   (select count(*) from redes.intervenciones i where i.dano_id = d.id) as itv,
                   exists (select 1 from redes.dano_datos_sensibles s where s.dano_id = d.id) as tercero
              from redes.v_dano d join redes.danos n on n.id = d.id
             where case p_filtro when 'abiertos' then d.estado in ('reportado', 'en_atencion') when 'ocultos' then d.estado = 'oculto'
                                 when 'no_identificados' then d.activo_id is null and d.estado <> 'oculto' else true end
             order by d.t_detectado desc limit v_lim) x), '[]'::jsonb));
end $f$;

-- Ocultar (con motivo, p. ej. un dato de prueba), reincluir o reabrir un daño. Solo eventos: el daño no se cambia ni se borra.
create function public.geoportal_redes_dano_evento(p_solicitante text, p_codigo text, p_tipo text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ocultan, reincluyen o reabren daños'); d redes.v_dano%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if coalesce(p_tipo, '') not in ('ocultar', 'reincluir', 'reabrir') then perform tecnica.f_error('Esa acción no existe'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.dano.' || upper(btrim(coalesce(p_codigo, '')))));
  select * into d from redes.v_dano where codigo = upper(btrim(coalesce(p_codigo, '')));
  if not found then perform tecnica.f_error('No existe ese daño', 'P0002'); end if;
  if p_tipo = 'ocultar' and d.estado = 'oculto' then perform tecnica.f_error('Ese daño ya está oculto'); end if;
  if p_tipo = 'reincluir' and d.estado <> 'oculto' then perform tecnica.f_error('Ese daño no está oculto'); end if;
  if p_tipo = 'reabrir' and d.estado <> 'atendido' then perform tecnica.f_error('Solo se reabre un daño atendido'); end if;
  insert into redes.dano_eventos (dano_id, tipo, motivo, autor) values (d.id, p_tipo, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_dano_' || p_tipo, d.codigo, jsonb_build_object('motivo', v_mot), null);
  return jsonb_build_object('codigo', d.codigo, 'estado', (select estado from redes.v_dano where id = d.id));
end $f$;

-- El nombre o la placa del tercero que causó el daño (D-26): dato personal. Lo leen el supervisor de distribución y el administrador (§ respuesta 3 al
-- Corte 2), y cada lectura queda auditada (quién, cuándo y de qué daño; nunca el valor).
create function public.geoportal_redes_dano_tercero(p_solicitante text, p_codigo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el nombre o la placa del tercero'); v_id uuid; v_cod text; v_nom text;
begin
  select id, codigo into v_id, v_cod from redes.danos where codigo = upper(btrim(coalesce(p_codigo, '')));
  if v_id is null then perform tecnica.f_error('No existe ese daño', 'P0002'); end if;
  select tercero_nombre into v_nom from redes.dano_datos_sensibles where dano_id = v_id;
  if v_nom is null then perform tecnica.f_error('Ese daño no tiene nombre ni placa del tercero', 'P0002'); end if;
  perform tecnica.f_auditar(v_email, 'redes_ver_tercero', v_cod, '{}'::jsonb, null);
  return jsonb_build_object('codigo', v_cod, 'tercero', v_nom);
end $f$;

-- ---------- Intervenciones: ocultar (p. ej. de prueba), reincluir o anular, con motivo ----------
create function public.geoportal_redes_intervencion_evento(p_solicitante text, p_codigo text, p_tipo text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ocultan, reincluyen o anulan intervenciones'); i redes.v_intervencion%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if coalesce(p_tipo, '') not in ('ocultar', 'reincluir', 'anulada') then perform tecnica.f_error('Esa acción no existe'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.itv.' || upper(btrim(coalesce(p_codigo, '')))));
  select * into i from redes.v_intervencion where codigo = upper(btrim(coalesce(p_codigo, '')));
  if not found then perform tecnica.f_error('No existe esa intervención', 'P0002'); end if;
  if p_tipo = 'ocultar' and i.estado = 'oculta' then perform tecnica.f_error('Esa intervención ya está oculta'); end if;
  if p_tipo = 'reincluir' and i.estado <> 'oculta' then perform tecnica.f_error('Esa intervención no está oculta'); end if;
  if p_tipo = 'anulada' and i.estado <> 'cerrada' then perform tecnica.f_error('Solo se anula una intervención cerrada'); end if;
  insert into redes.intervencion_eventos (intervencion_id, tipo, motivo, autor) values (i.id, p_tipo, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_intervencion_' || p_tipo, i.codigo, jsonb_build_object('motivo', v_mot), null);
  return jsonb_build_object('codigo', i.codigo, 'estado', (select estado from redes.v_intervencion where id = i.id),
                            'aviso', case when p_tipo = 'anulada' and i.dano_codigo is not null and i.resuelve_dano
                                          then format('El daño %s sigue atendido: si debe volver a quedar abierto, reábralo en «Daños y fallas».', i.dano_codigo) end);
end $f$;

-- ---------- Reportes del bot (N-14): la bandeja. Convertir y descartar ya existen (Corte 2). ----------
create function public.geoportal_redes_reportes_bot(p_solicitante text, p_filtro text default 'pendientes', p_limite integer default 100)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven los reportes del bot'); v_lim integer := coalesce(p_limite, 100);
begin
  if coalesce(p_filtro, '') not in ('pendientes', 'todos') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_lim < 1 or v_lim > 300 then perform tecnica.f_error('Se piden de 1 a 300'); end if;
  return jsonb_build_object('filtro', p_filtro, 'reportes', coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'radicado', r.radicado, 'canal', r.canal, 'tipo', r.tipo_bot, 'lat', r.lat, 'lon', r.lon, 'direccion', r.direccion,
             'descripcion', r.descripcion, 'recibido_en', r.recibido_en, 'estado_bot', r.estado_bot, 'dano', r.dano_codigo, 'fotos', r.fotos) order by r.recibido_en desc)
      from (select * from redes.v_reporte_externo x where p_filtro = 'todos' or x.ultimo_evento = 'recibido' order by x.recibido_en desc limit v_lim) r), '[]'::jsonb));
end $f$;

-- ---------- Bandeja de no identificados: CREAR el activo (respuesta 4 de David al 3a) y asociarlo ----------
-- Solo tipos de PUNTO (válvula, hidrante, pozo, sumidero…), en el punto del registro. Un tramo nuevo se dibuja en el Cargue de capas (Corte 5).
-- El activo nace «por verificar», con origen EMDUPAR por omisión (el administrador lo corrige en la ficha si es de un tercero).
create function public.geoportal_redes_crear_activo_bandeja(p_solicitante text, p_clase text, p_ref text, p_prefijo text, p_clase_activo text, p_nombre text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare
  v_email text := redes.f_supervisor(p_solicitante, 'crean activos desde la bandeja'); v_id uuid; v_sis text; v_actual bigint; v_lat numeric; v_lon numeric;
  t redes.v_tipo_visible%rowtype; v_mot text := btrim(coalesce(p_motivo, '')); v_nom text := nullif(btrim(coalesce(p_nombre, '')), ''); v_cl text := nullif(p_clase_activo, '');
  v_cons bigint; v_cod text; v_act bigint; v_geom geometry; v_ref text := upper(btrim(coalesce(p_ref, '')));
begin
  if coalesce(p_clase, '') not in ('intervencion', 'dano') then perform tecnica.f_error('Diga si es una intervención o un daño'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  if v_nom is not null and length(v_nom) > 120 then perform tecnica.f_error('El nombre admite hasta 120 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.asociar.' || v_ref));
  if p_clase = 'intervencion' then
    select id, sistema, activo_id, lat, lon into v_id, v_sis, v_actual, v_lat, v_lon from redes.v_intervencion where codigo = v_ref and estado <> 'oculta';
  else
    select id, sistema, activo_id, lat, lon into v_id, v_sis, v_actual, v_lat, v_lon from redes.v_dano where codigo = v_ref and estado <> 'oculto';
  end if;
  if v_id is null then perform tecnica.f_error('No existe ese registro (o está oculto)', 'P0002'); end if;
  if v_actual is not null then perform tecnica.f_error('Ese registro ya tiene activo'); end if;
  select * into t from redes.v_tipo_visible where prefijo = upper(coalesce(p_prefijo, '')) and sistema = v_sis;
  if not found then perform tecnica.f_error('Elija un tipo de activo del mismo sistema'); end if;
  if t.geometria <> 'punto' then perform tecnica.f_error('Un tramo nuevo se dibuja en el Cargue de capas: por ahora asocie el registro a un tramo existente'); end if;
  if v_cl is not null and not exists (select 1 from redes.clases_activo where prefijo = t.prefijo and codigo = v_cl) then perform tecnica.f_error('Esa clase no existe para el tipo elegido'); end if;
  if v_cl is null and exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean) then
    perform tecnica.f_error(format('Elija la clase del activo (%s)', t.nombre_visible));
  end if;
  if v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') or v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') then
    perform tecnica.f_error('El registro está fuera de Valledupar: no se crea el activo ahí');
  end if;
  v_geom := ST_SetSRID(ST_MakePoint(v_lon::double precision, v_lat::double precision), 4326);
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = t.prefijo returning ultimo into v_cons;
  v_cod := t.prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, t.prefijo, 'asociacion', v_email) returning id into v_act;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, estado_codigo, atributos, huella, autor)
  values (v_act, 1, v_geom, v_nom, v_cl, 'en_operacion', jsonb_build_object('creado_desde', v_ref),
          redes.f_huella(v_geom, jsonb_build_object('p', t.prefijo, 'n', v_nom, 'c', v_cl, 'e', null, 'm', null, 'd', null, 'l', null, 'pr', null, 'ca', null, 's', 'en_operacion',
                                                     'ant', null, 'a', jsonb_build_object('creado_desde', v_ref))), v_email);
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor) values (v_act, 'por_verificar', left(format('Creado desde la bandeja de no identificados (%s): %s', v_ref, v_mot), 1000), v_email);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_act, 1, 'emdupar', 'Creado desde la bandeja; origen por confirmar', v_email);
  perform redes.f_mat_refrescar_uno(v_act);
  perform redes.f_subir_tesela(v_sis);
  if p_clase = 'intervencion' then
    insert into redes.intervencion_eventos (intervencion_id, tipo, activo_id, motivo, autor) values (v_id, 'crear_activo', v_act, v_mot, v_email);
    insert into redes.intervencion_eventos (intervencion_id, tipo, activo_id, motivo, autor) values (v_id, 'asociar_activo', v_act, v_mot, v_email);
  else
    insert into redes.dano_eventos (dano_id, tipo, activo_id, motivo, autor) values (v_id, 'asociar_activo', v_act, v_mot, v_email);
  end if;
  perform tecnica.f_auditar(v_email, 'redes_crear_activo_bandeja', v_ref, jsonb_build_object('clase', p_clase, 'activo', v_cod), null);
  return jsonb_build_object('clase', p_clase, 'codigo', v_ref, 'activo', v_cod, 'por_verificar', true);
end $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Funciones internas nuevas de redes: nadie de la API. RPC public.geoportal_redes_* nuevas y reemplazadas: solo execute a service_role.
-- (Las 4 funciones de permisos vivas reciben sus permisos en 15, como en el paquete de Análisis de contrato.)
-- =====================================================================
revoke all on all tables in schema redes from public, anon, authenticated, service_role;
revoke all on all sequences in schema redes from public, anon, authenticated, service_role;
revoke all on all functions in schema redes from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración (la verificación 08 cuenta desde aquí los registros nuevos sin fotos)
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte4a', 'migracion_redes_corte4a', null, jsonb_build_object('permiso', 'ver_dashboard_redes', 'marcados', 0), null);
commit;
