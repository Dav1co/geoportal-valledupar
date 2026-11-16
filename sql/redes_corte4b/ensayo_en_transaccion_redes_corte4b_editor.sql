begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 10 — GUARDIA Y TABLAS NUEVAS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: 02 fila 4b, D-18, D-19, N-12, N-13 y §27 de la bitácora.
-- · Presupone el 4a aplicado (huella del conjunto de funciones de redes, de v_dano y de v_epicrisis, y de las 4 funciones de permisos del 4a).
-- · NO toca ninguna función viva ni de permisos: solo agrega tablas, una vista, funciones internas y RPC nuevas (ningún create or replace de lo existente).
-- · Tablas nuevas: tecnica.personal_ficha_eventos (D-18: área, cargo, cuadrilla y geovisor; solo inserción) y redes.cuadrillas (catálogo).
--   No se toca el CHECK de tecnica.personal_tecnico_eventos, que sigue filtrando la captura.
-- =====================================================================
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_lista_blanca' and column_name = 'ver_dashboard_redes') then
    raise exception 'Falta el Corte 4a (ver_dashboard_redes): aplíquelo antes';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '1a2be013019c9a59f1c1e0f2241661f0' then
    raise exception 'Las funciones de redes no son las del Corte 4a (o el Corte 4b ya está aplicado): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_dano'::regclass, true)) <> 'bee1b39d753fc55ae7cb85a3952896fb' or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> 'a1e45ec72cb5b254a67698111994746a' then
    raise exception 'Las vistas v_dano o v_epicrisis no son las del 4a: deténgase y avise';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_puede', '32f174a55b95788d3f8187b507303c2f'), ('geoportal_mis_permisos', '83166fe17be58da67bbdedaae429bedb'), ('geoportal_admin_permisos', 'e5a90103b4a83440fd826f03266b7245'), ('geoportal_admin_listar', 'd7311a32ea03cccd6c83691e63ba10bc'))) <> 4 then
    raise exception 'Las 4 funciones de permisos no son las del Corte 4a: deténgase y avise';
  end if;
  if to_regclass('tecnica.personal_ficha_eventos') is not null or to_regclass('redes.cuadrillas') is not null then
    raise exception 'tecnica.personal_ficha_eventos o redes.cuadrillas ya existen: el Corte 4b parece aplicado';
  end if;
  if to_regprocedure('tecnica.f_solo_agregar()') is null or to_regprocedure('tecnica.f_tecnica_activa(text)') is null or to_regprocedure('tecnica.f_formulario_asignado(text,text)') is null then
    raise exception 'Faltan tecnica.f_solo_agregar, f_tecnica_activa o f_formulario_asignado';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. CUADRILLAS (catálogo de redes, D-18). Solo el administrador las crea, les cambia el nombre o las desactiva (nada se borra).
-- ---------------------------------------------------------------------
create table redes.cuadrillas (
  id         bigint generated always as identity primary key,
  nombre     text not null check (length(btrim(nombre)) between 2 and 60),
  activa     boolean not null default true,
  orden      integer not null default 0,
  autor      text not null,
  creado_en  timestamptz not null default clock_timestamp()
);
create unique index ux_cuadrillas_nombre on redes.cuadrillas (lower(btrim(nombre)));
comment on table redes.cuadrillas is 'Cuadrillas de distribución (D-18). Las crea y edita el administrador desde Catálogo, con motivo en la auditoría. Nada se borra: se desactiva.';
create trigger t_no_borrar before delete on redes.cuadrillas for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on redes.cuadrillas for each statement execute function tecnica.f_solo_agregar();
alter table redes.cuadrillas enable row level security;

-- ---------------------------------------------------------------------
-- 2. FICHA DEL PERSONAL DE TÉCNICA (D-18 y N-13). Solo inserción: lo vigente es el último evento por persona y tipo.
--    · fijar_area: planta | distribucion | ambas (decide en qué dashboard sale la persona; §16);
--    · fijar_cargo: texto de 2 a 80, o nulo para quitarlo;
--    · fijar_cuadrilla: id de redes.cuadrillas, o nulo para quitarla;
--    · fijar_geovisor: si | no (geovisor principal en solo lectura del operador de distribución; Corte 6). Una sola casilla, en Personal del
--      Dashboard distribución (§27.3): Administración la muestra sin editarla.
-- ---------------------------------------------------------------------
create table tecnica.personal_ficha_eventos (
  id          bigint generated always as identity primary key,
  persona     text not null check (persona = lower(btrim(persona)) and position('@' in persona) > 1),
  tipo_evento text not null check (tipo_evento in ('fijar_area', 'fijar_cargo', 'fijar_cuadrilla', 'fijar_geovisor')),
  valor       text,
  motivo      text not null check (length(btrim(motivo)) between 10 and 500),
  autor       text not null,
  creado_en   timestamptz not null default clock_timestamp(),
  check (case tipo_evento
           when 'fijar_area' then valor in ('planta', 'distribucion', 'ambas')
           when 'fijar_geovisor' then valor in ('si', 'no')
           when 'fijar_cargo' then valor is null or length(btrim(valor)) between 2 and 80
           when 'fijar_cuadrilla' then valor is null or valor ~ '^[0-9]{1,18}$' end)
);
create index ix_pfe_persona on tecnica.personal_ficha_eventos (persona, tipo_evento, id desc);
comment on table tecnica.personal_ficha_eventos is 'Área, cargo, cuadrilla y geovisor del personal de Técnica (D-18, N-13). Solo inserción. La pone el supervisor de distribución o el administrador desde Personal del Dashboard distribución, siempre con motivo.';
create trigger t_solo_agregar before update or delete on tecnica.personal_ficha_eventos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.personal_ficha_eventos for each statement execute function tecnica.f_solo_agregar();
alter table tecnica.personal_ficha_eventos enable row level security;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 20 — VISTA DE LA FICHA DEL PERSONAL Y FUNCIONES INTERNAS (nadie de la API las ejecuta)
-- PROPUESTA. No se ha ejecutado en la base real.
-- =====================================================================

-- Ficha vigente de cada persona: el último evento de cada tipo (nulo = sin definir).
create view redes.v_personal_ficha as
select x.persona,
       max(x.valor) filter (where x.tipo_evento = 'fijar_area') as area,
       max(x.valor) filter (where x.tipo_evento = 'fijar_cargo') as cargo,
       max(x.valor) filter (where x.tipo_evento = 'fijar_cuadrilla')::bigint as cuadrilla_id,
       coalesce(max(x.valor) filter (where x.tipo_evento = 'fijar_geovisor') = 'si', false) as geovisor,
       max(x.creado_en) as ultimo_cambio
  from (select distinct on (e.persona, e.tipo_evento) e.persona, e.tipo_evento, e.valor, e.creado_en
          from tecnica.personal_ficha_eventos e order by e.persona, e.tipo_evento, e.id desc) x
 group by x.persona;

-- Área de una persona (planta | distribucion | ambas), o nulo si nadie la ha fijado.
create function redes.f_area(p_email text) returns text
language sql stable security definer set search_path to 'redes', 'tecnica', 'pg_temp' as $f$
  select area from redes.v_personal_ficha where persona = lower(btrim(coalesce(p_email, ''))) $f$;

-- ¿Ve el geovisor principal? (lo usará el Corte 6). El administrador, el supervisor de distribución, el supervisor de planta (abre con muestreo y
-- tanques) y el operador al que se le activó la casilla en Personal (solo lectura, N-13). Tener un formulario de distribución ya no basta.
-- Con el acceso a Técnica desactivado, nadie que no sea el administrador.
create function redes.f_geovisor_lectura(p_email text) returns boolean
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v text := lower(btrim(coalesce(p_email, '')));
begin
  if v = '' or position('@' in v) < 2 or public.geoportal_estado_acceso(v) <> 'ok' then return false; end if;
  if public.geoportal_es_admin(v) then return true; end if;
  if not tecnica.f_tecnica_activa(v) then return false; end if;
  return public.geoportal_puede(v, 'dashboard_redes') or public.geoportal_puede(v, 'dashboard_tecnico')
      or (public.geoportal_puede(v, 'registro_tecnico') and coalesce((select geovisor from redes.v_personal_ficha where persona = v), false));
end $f$;

-- Personas que salen en Personal del Dashboard distribución: activas en la lista blanca, que no sean administradores, con Registro técnico o
-- Dashboard distribución. Devuelve la fila de la lista blanca o nada.
create function redes.f_persona_tecnica(p_email text) returns public.geoportal_lista_blanca
language sql stable security definer set search_path to 'public', 'pg_temp' as $f$
  select lb.* from public.geoportal_lista_blanca lb
   where lb.email = lower(btrim(coalesce(p_email, ''))) and lb.activo and lb.rol <> 'admin' and (lb.ver_registro_tecnico or lb.ver_dashboard_redes) $f$;

-- Valor entero para los parámetros que se cuentan (fotos, días, horas, filas, bytes, zoom…).
create function redes.f_param_entero(p_unidad text) returns boolean
language sql immutable set search_path to 'pg_catalog' as $f$
  select p_unidad in ('fotos', 'documentos', 'materiales', 'activos', 'días', 'horas', 'filas', 'bytes', 'zoom') $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 26 — RPC NUEVAS DEL DASHBOARD DISTRIBUCIÓN (gestión): Personal (área, cargo, cuadrilla y geovisor), Catálogo
-- (alias y cuadrillas), Parámetros, Gráficas (D-19), descargas en Excel (auditadas) y la bandeja de nodos por clasificar (administrador).
-- PROPUESTA. No se ha ejecutado en la base real. Todas security definer, search_path fijo, mensajes con HINT msg_usuario; solo service_role.
-- Quién: supervisor de distribución o administrador (redes.f_supervisor); lo que edita el catálogo, los parámetros y los nodos, solo el
-- administrador (redes.f_autorizar_admin). Nada se borra: todo es un evento con motivo, o un cambio de catálogo con su antes y después auditado.
-- Sin datos de suscriptores. Las descargas no llevan el nombre ni la placa del tercero, ni textos libres (descripción, compañeros).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PERSONAL (D-18, N-13, §27.3)
-- ---------------------------------------------------------------------
create function public.geoportal_redes_personal(p_solicitante text, p_buscar text default null, p_filtro text default 'todas')
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 've el personal de distribución'); v_q text := nullif(lower(btrim(coalesce(p_buscar, ''))), '');
begin
  if coalesce(p_filtro, '') not in ('todas', 'distribucion', 'planta', 'sin_area') then perform tecnica.f_error('Ese filtro no existe'); end if;
  if v_q is not null and length(v_q) > 80 then perform tecnica.f_error('La búsqueda es demasiado larga'); end if;
  return jsonb_build_object('filtro', p_filtro, 'yo', v_email,
    'formularios', jsonb_build_array(jsonb_build_object('clave', 'danos_fallas', 'nombre', 'Reportar daño o falla'), jsonb_build_object('clave', 'mantenimiento', 'nombre', 'Registrar intervención')),
    'cuadrillas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre) order by c.orden, lower(c.nombre)) from redes.cuadrillas c where c.activa), '[]'::jsonb),
    'personas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'email', p.email, 'nombre', p.nombre, 'perfil', case when p.ver_dashboard_redes then 'supervisor' else 'operador' end,
               'dashboard_redes', p.ver_dashboard_redes, 'dashboard_ptap', p.ver_dashboard_tecnico, 'registro_tecnico', p.ver_registro_tecnico,
               'area', f.area, 'cargo', f.cargo,
               'cuadrilla', case when c.id is not null then jsonb_build_object('id', c.id, 'nombre', c.nombre, 'activa', c.activa) end,
               -- la casilla solo es del operador: los supervisores (de distribución o de planta) ven el geovisor por su permiso
               'geovisor', case when p.ver_dashboard_redes or p.ver_dashboard_tecnico then 'por_permiso' when coalesce(f.geovisor, false) then 'si' else 'no' end,
               'formularios', to_jsonb(array_remove(array[case when tecnica.f_formulario_asignado(p.email, 'danos_fallas') then 'danos_fallas' end,
                                                          case when tecnica.f_formulario_asignado(p.email, 'mantenimiento') then 'mantenimiento' end], null)),
               'activo_tecnica', tecnica.f_tecnica_activa(p.email), 'ultimo_cambio', f.ultimo_cambio)
             order by lower(coalesce(p.nombre, p.email)), p.email)
        from (select lb.email, nullif(btrim(lb.nombre), '') as nombre, lb.ver_dashboard_redes, lb.ver_dashboard_tecnico, lb.ver_registro_tecnico
                from public.geoportal_lista_blanca lb where lb.activo and lb.rol <> 'admin' and (lb.ver_registro_tecnico or lb.ver_dashboard_redes)) p
        left join redes.v_personal_ficha f on f.persona = p.email
        left join redes.cuadrillas c on c.id = f.cuadrilla_id
       where (v_q is null or position(v_q in lower(coalesce(p.nombre, '') || ' ' || p.email)) > 0)
         and case p_filtro when 'distribucion' then coalesce(f.area in ('distribucion', 'ambas'), false) when 'planta' then coalesce(f.area in ('planta', 'ambas'), false)
                           when 'sin_area' then f.area is null else true end), '[]'::jsonb));
end $f$;

-- Fija el área, el cargo, la cuadrilla o la casilla del geovisor de una persona. Un evento nuevo, con motivo; el anterior no se toca.
create function public.geoportal_redes_personal_fijar(p_solicitante text, p_persona text, p_tipo text, p_valor text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare
  v_email text := redes.f_supervisor(p_solicitante, 'cambian el área, el cargo, la cuadrilla o el geovisor del personal');
  v_p text := lower(btrim(coalesce(p_persona, ''))); lb public.geoportal_lista_blanca; f redes.v_personal_ficha%rowtype;
  v_val text := nullif(btrim(coalesce(p_valor, '')), ''); v_mot text := btrim(coalesce(p_motivo, '')); v_antes text; v_id bigint;
begin
  if coalesce(p_tipo, '') not in ('area', 'cargo', 'cuadrilla', 'geovisor') then perform tecnica.f_error('Ese dato de la ficha no existe'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (10 a 500 caracteres)'); end if;
  lb := redes.f_persona_tecnica(v_p);
  if lb.email is null then perform tecnica.f_error('Esa persona no está en Técnica (o su cuenta está inactiva)', 'P0002'); end if;
  if v_p = v_email then perform tecnica.f_error('No puede cambiar su propia ficha: pídaselo a otro supervisor o al administrador'); end if;
  perform pg_advisory_xact_lock(hashtext('tecnica.ficha.' || v_p));
  select * into f from redes.v_personal_ficha where persona = v_p;
  if p_tipo = 'area' then
    if v_val is null or v_val not in ('planta', 'distribucion', 'ambas') then perform tecnica.f_error('El área es planta, distribución o las dos'); end if;
    v_antes := f.area;
  elsif p_tipo = 'cargo' then
    if v_val is not null and length(v_val) not between 2 and 80 then perform tecnica.f_error('El cargo lleva de 2 a 80 caracteres'); end if;
    v_antes := f.cargo;
  elsif p_tipo = 'cuadrilla' then
    if v_val is not null and (v_val !~ '^[0-9]{1,18}$' or not exists (select 1 from redes.cuadrillas c where c.id = v_val::bigint and c.activa)) then
      perform tecnica.f_error('Elija una cuadrilla activa del catálogo');
    end if;
    v_antes := f.cuadrilla_id::text;
  else
    if v_val is null or v_val not in ('si', 'no') then perform tecnica.f_error('Diga si se le activa o no el geovisor'); end if;
    if lb.ver_dashboard_redes or lb.ver_dashboard_tecnico then perform tecnica.f_error('Esta persona ya ve el geovisor por su permiso de supervisor: la casilla es solo del operador'); end if;
    v_antes := case when coalesce(f.geovisor, false) then 'si' else 'no' end;
  end if;
  if v_antes is not distinct from v_val then perform tecnica.f_error('Ya está así: no hay nada que cambiar'); end if;
  insert into tecnica.personal_ficha_eventos (persona, tipo_evento, valor, motivo, autor) values (v_p, 'fijar_' || p_tipo, v_val, v_mot, v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'redes_personal_' || p_tipo, v_p, jsonb_build_object('antes', v_antes, 'despues', v_val, 'motivo', v_mot), null);
  return jsonb_build_object('evento_id', v_id, 'persona', v_p, 'tipo', p_tipo, 'antes', v_antes, 'despues', v_val);
end $f$;

-- Historial de la ficha del personal (más reciente primero), de una persona o de todas.
create function public.geoportal_redes_personal_historial(p_solicitante text, p_persona text default null, p_despues_de bigint default null, p_limite integer default 50)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el historial del personal'); v_p text := nullif(lower(btrim(coalesce(p_persona, ''))), ''); v_lim integer := coalesce(p_limite, 50);
begin
  if v_lim < 1 or v_lim > 200 then perform tecnica.f_error('Se piden de 1 a 200'); end if;
  return jsonb_build_object(
    'total', (select count(*) from tecnica.personal_ficha_eventos e where v_p is null or e.persona = v_p),
    'eventos', coalesce((select jsonb_agg(x.j order by x.id desc) from (
      select e.id, jsonb_build_object('id', e.id, 'persona', e.persona, 'persona_nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = e.persona),
               'tipo', substr(e.tipo_evento, 7), 'valor', e.valor,
               'valor_nombre', case when e.tipo_evento = 'fijar_cuadrilla' and e.valor is not null then (select c.nombre from redes.cuadrillas c where c.id = e.valor::bigint) end,
               'motivo', e.motivo, 'autor', e.autor, 'autor_nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = e.autor),
               'creado_en', e.creado_en) as j
        from tecnica.personal_ficha_eventos e
       where (v_p is null or e.persona = v_p) and (p_despues_de is null or e.id < p_despues_de)
       order by e.id desc limit v_lim) x), '[]'::jsonb));
end $f$;

-- ---------------------------------------------------------------------
-- 2. CATÁLOGO (N-12): lo lee el supervisor; el alias y las cuadrillas los edita solo el administrador (el alias con geoportal_redes_alias_fijar del 1a)
-- ---------------------------------------------------------------------
create function public.geoportal_redes_catalogo(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el catálogo de redes');
begin
  return jsonb_build_object('puede_editar', public.geoportal_es_admin(v_email),
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre, 'nombre_visible', t.nombre_visible,
               'alias', case when t.nombre_visible <> t.nombre then t.nombre_visible end, 'sistema', t.sistema, 'geometria', t.geometria, 'es_base', t.es_base, 'activo', t.activo,
               'vigentes', coalesce(n.n, 0)) order by t.sistema, t.orden, t.prefijo)
        from redes.v_tipo_visible t
        left join (select m.prefijo, count(*) as n from redes.activo_vigente_mat m where not m.retirado and not m.oculto group by m.prefijo) n on n.prefijo = t.prefijo), '[]'::jsonb),
    'materiales', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden, nombre) from redes.materiales), '[]'::jsonb),
    'estados', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'cuenta_vigente', cuenta_vigente) order by orden) from redes.estados_activo), '[]'::jsonb),
    'contratistas', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by nombre) from redes.contratistas), '[]'::jsonb),
    'aportantes', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden) from redes.entidades_aportantes), '[]'::jsonb),
    'tipos_intervencion', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden) from redes.tipos_intervencion), '[]'::jsonb),
    'tipos_dano', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'clase', clase, 'activo', activo) order by clase, orden) from redes.tipos_dano), '[]'::jsonb),
    'causas', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'activo', activo) order by orden) from redes.causas), '[]'::jsonb),
    'cuadrillas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre, 'activa', c.activa,
                     'personas', (select count(*) from redes.v_personal_ficha f where f.cuadrilla_id = c.id)) order by c.orden, lower(c.nombre)) from redes.cuadrillas c), '[]'::jsonb));
end $f$;

-- Historial del nombre visible (alias) de un tipo o de un nodo.
create function public.geoportal_redes_alias_historial(p_solicitante text, p_objeto text, p_ref text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven el historial de los nombres visibles'); v_nodo bigint;
begin
  if coalesce(p_objeto, '') not in ('tipo', 'nodo') then perform tecnica.f_error('El alias es de un tipo o de un nodo'); end if;
  if p_objeto = 'nodo' then v_nodo := case when p_ref ~ '^[0-9]{1,18}$' then p_ref::bigint end; end if;
  return jsonb_build_object('objeto', p_objeto, 'ref', p_ref, 'eventos', coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'alias', a.alias, 'motivo', a.motivo, 'autor', a.autor, 'creado_en', a.creado_en) order by a.id desc)
      from redes.alias_eventos a
     where a.objeto = p_objeto and ((p_objeto = 'tipo' and a.prefijo = upper(btrim(coalesce(p_ref, '')))) or (p_objeto = 'nodo' and a.nodo_id = v_nodo))), '[]'::jsonb));
end $f$;

-- Crea una cuadrilla (p_id nulo) o le cambia el nombre o la activa/desactiva. Solo el administrador. Nada se borra.
create function public.geoportal_redes_cuadrilla_fijar(p_solicitante text, p_id bigint, p_nombre text, p_activa boolean, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_autorizar_admin(p_solicitante); v_nom text := nullif(btrim(coalesce(p_nombre, '')), ''); v_mot text := btrim(coalesce(p_motivo, ''));
        c redes.cuadrillas%rowtype; v_id bigint;
begin
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (10 a 500 caracteres)'); end if;
  if v_nom is not null and length(v_nom) not between 2 and 60 then perform tecnica.f_error('El nombre de la cuadrilla lleva de 2 a 60 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.cuadrillas'));
  if v_nom is not null and exists (select 1 from redes.cuadrillas x where lower(btrim(x.nombre)) = lower(v_nom) and x.id is distinct from p_id) then
    perform tecnica.f_error('Ya existe una cuadrilla con ese nombre');
  end if;
  if p_id is null then
    if v_nom is null then perform tecnica.f_error('Escriba el nombre de la cuadrilla'); end if;
    insert into redes.cuadrillas (nombre, activa, orden, autor) values (v_nom, coalesce(p_activa, true), coalesce((select max(orden) from redes.cuadrillas), 0) + 1, v_email)
    returning id into v_id;
    perform tecnica.f_auditar(v_email, 'redes_cuadrilla_crear', v_id::text, jsonb_build_object('nombre', v_nom, 'motivo', v_mot), null);
    return jsonb_build_object('id', v_id, 'nombre', v_nom, 'activa', coalesce(p_activa, true), 'nueva', true);
  end if;
  select * into c from redes.cuadrillas where id = p_id for update;
  if not found then perform tecnica.f_error('No existe esa cuadrilla', 'P0002'); end if;
  if coalesce(v_nom, c.nombre) = c.nombre and coalesce(p_activa, c.activa) = c.activa then perform tecnica.f_error('Ya está así: no hay nada que cambiar'); end if;
  update redes.cuadrillas set nombre = coalesce(v_nom, nombre), activa = coalesce(p_activa, activa) where id = p_id;
  perform tecnica.f_auditar(v_email, 'redes_cuadrilla_cambiar', p_id::text, jsonb_build_object('antes', jsonb_build_object('nombre', c.nombre, 'activa', c.activa),
          'despues', jsonb_build_object('nombre', coalesce(v_nom, c.nombre), 'activa', coalesce(p_activa, c.activa)), 'motivo', v_mot), null);
  return jsonb_build_object('id', p_id, 'nombre', coalesce(v_nom, c.nombre), 'activa', coalesce(p_activa, c.activa), 'nueva', false);
end $f$;

-- ---------------------------------------------------------------------
-- 3. PARÁMETROS: el supervisor los lee; el administrador los cambia con motivo (antes y después en parametro_eventos y en la auditoría).
--    La caja de Valledupar (caja_*) no se cambia desde la pantalla. Las fotos mínimas nunca bajan de 1 (§25.8: nadie registra sin foto).
-- ---------------------------------------------------------------------
create function public.geoportal_redes_parametros(p_solicitante text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven los parámetros de redes'); v_admin boolean := public.geoportal_es_admin(v_email);
begin
  return jsonb_build_object('puede_editar', v_admin,
    'parametros', coalesce((select jsonb_agg(jsonb_build_object('clave', p.clave, 'valor', p.valor, 'unidad', p.unidad, 'minimo', p.minimo, 'maximo', p.maximo,
                     'estado', p.estado, 'descripcion', p.descripcion, 'entero', redes.f_param_entero(p.unidad), 'editable', v_admin and p.clave not like 'caja\_%',
                     'ultimo_cambio', (select max(e.creado_en) from redes.parametro_eventos e where e.clave = p.clave)) order by p.clave)
        from redes.parametros p), '[]'::jsonb),
    'historial', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'clave', e.clave, 'antes', e.antes, 'despues', e.despues, 'motivo', e.motivo, 'autor', e.autor,
                     'creado_en', e.creado_en) order by e.id desc)
        from (select * from redes.parametro_eventos order by id desc limit 50) e), '[]'::jsonb));
end $f$;

create function public.geoportal_redes_parametro_fijar(p_solicitante text, p_clave text, p_valor numeric, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_autorizar_admin(p_solicitante); p redes.parametros%rowtype; v_mot text := btrim(coalesce(p_motivo, '')); v_id bigint; r record;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo del cambio (10 caracteres o más)'); end if;
  select * into p from redes.parametros where clave = p_clave for update;
  if not found then perform tecnica.f_error('No existe ese parámetro', 'P0002'); end if;
  if p.clave like 'caja\_%' then perform tecnica.f_error('La caja de Valledupar no se cambia desde la pantalla: avise para hacerlo con SQL'); end if;
  if p_valor is null then perform tecnica.f_error('Escriba el valor nuevo'); end if;
  if redes.f_param_entero(p.unidad) and p_valor <> trunc(p_valor) then perform tecnica.f_error(format('Este parámetro va en %s enteros', p.unidad)); end if;
  if (p.minimo is not null and p_valor < p.minimo) or (p.maximo is not null and p_valor > p.maximo) then
    perform tecnica.f_error(format('El valor va de %s a %s %s', coalesce(p.minimo::text, '—'), coalesce(p.maximo::text, '—'), p.unidad));
  end if;
  if p.clave in ('min_fotos_dano', 'min_fotos_itv') and p_valor < 1 then perform tecnica.f_error('Las fotos mínimas no bajan de 1: nadie registra sin foto (§25.8)'); end if;
  -- parejas que deben seguir en orden (el mínimo no pasa al máximo)
  for r in select * from (values ('min_fotos_dano', 'max_fotos_dano'), ('min_fotos_itv', 'max_fotos_itv'), ('distancia_activo_cercano_m', 'activos_cerca_max_m'),
                                 ('mini_zoom_min', 'mini_zoom_acc')) x(menor, mayor) where p.clave in (x.menor, x.mayor) loop
    if (p.clave = r.menor and p_valor > (select valor from redes.parametros where clave = r.mayor))
       or (p.clave = r.mayor and p_valor < (select valor from redes.parametros where clave = r.menor)) then
      perform tecnica.f_error(format('«%s» no puede quedar por encima de «%s»', r.menor, r.mayor));
    end if;
  end loop;
  if p.valor is not distinct from p_valor then perform tecnica.f_error('Ya tiene ese valor: no hay nada que cambiar'); end if;
  update redes.parametros set valor = p_valor where clave = p.clave;
  insert into redes.parametro_eventos (clave, antes, despues, motivo, autor) values (p.clave, p.valor, p_valor, v_mot, v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'redes_parametro', p.clave, jsonb_build_object('antes', p.valor, 'despues', p_valor, 'motivo', v_mot), null);
  return jsonb_build_object('evento_id', v_id, 'clave', p.clave, 'antes', p.valor, 'despues', p_valor, 'unidad', p.unidad);
end $f$;

-- ---------------------------------------------------------------------
-- 4. GRÁFICAS (D-19): intervenciones por mes, tipo y sistema; valor por fuente; daños por clase y causa con los tiempos medios;
--    los 10 activos con más correctivos. Sin ocultos ni anuladas. Meses del calendario de Bogotá.
-- ---------------------------------------------------------------------
create function public.geoportal_redes_graficas(p_solicitante text, p_meses integer default 12)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven las gráficas de distribución'); v_m integer := coalesce(p_meses, 12); v_desde timestamptz; v_mes0 date;
begin
  if v_m < 1 or v_m > 24 then perform tecnica.f_error('Se piden de 1 a 24 meses'); end if;
  v_mes0 := (date_trunc('month', clock_timestamp() at time zone 'America/Bogota') - make_interval(months => v_m - 1))::date;
  v_desde := v_mes0::timestamp at time zone 'America/Bogota';
  return jsonb_build_object('meses', (select jsonb_agg(to_char(v_mes0 + make_interval(months => g), 'YYYY-MM') order by g) from generate_series(0, v_m - 1) g),
    'desde', v_desde,
    'intervenciones_mes', coalesce((select jsonb_agg(jsonb_build_object('mes', x.mes, 'tipo', x.tipo_codigo, 'tipo_nombre', x.tipo_nombre, 'sistema', x.sistema, 'n', x.n) order by x.mes, x.tipo_codigo, x.sistema)
        from (select to_char(i.t_fin at time zone 'America/Bogota', 'YYYY-MM') as mes, i.tipo_codigo, i.tipo_nombre, i.sistema, count(*) as n
                from redes.v_intervencion i where i.estado not in ('oculta', 'anulada') and i.t_fin >= v_desde group by 1, 2, 3, 4) x), '[]'::jsonb),
    'valor_fuente', coalesce((select jsonb_agg(jsonb_build_object('aportante', x.aportante_codigo, 'nombre', x.nombre, 'valor', x.valor, 'intervenciones', x.n, 'sin_valor', x.sin_valor) order by x.valor desc nulls last, x.nombre)
        from (select f.aportante_codigo, e.nombre, sum(f.valor) as valor, count(distinct f.intervencion_id) as n, count(*) filter (where f.valor is null) as sin_valor
                from redes.v_intervencion_fuentes f join redes.v_intervencion i on i.id = f.intervencion_id join redes.entidades_aportantes e on e.codigo = f.aportante_codigo
               where i.estado not in ('oculta', 'anulada') and i.t_fin >= v_desde group by 1, 2) x), '[]'::jsonb),
    'danos_causa', coalesce((select jsonb_agg(jsonb_build_object('clase', x.clase, 'causa_clase', x.causa_clase, 'n', x.n, 'atendidos', x.atendidos,
                     'respuesta_media_min', x.resp, 'reparacion_media_min', x.rep) order by x.clase, x.causa_clase)
        from (select d.clase, coalesce(d.causa_clase, 'sin_dato') as causa_clase, count(*) as n, count(*) filter (where d.estado = 'atendido') as atendidos,
                     round(avg(d.respuesta_s) / 60.0) as resp, round(avg(d.reparacion_s) / 60.0) as rep
                from redes.v_dano d where d.estado <> 'oculto' and d.t_detectado >= v_desde group by 1, 2) x), '[]'::jsonb),
    'top_correctivos', coalesce((select jsonb_agg(jsonb_build_object('activo', x.codigo, 'tipo', x.tipo_visible, 'n', x.n) order by x.n desc, x.codigo)
        from (select i.activo_codigo as codigo, (select t.nombre_visible from redes.v_tipo_visible t where t.prefijo = left(i.activo_codigo, 3)) as tipo_visible, count(*) as n
                from redes.v_intervencion i join redes.tipos_intervencion t on t.codigo = i.tipo_codigo and t.admite_dano
               where i.estado not in ('oculta', 'anulada') and i.activo_id is not null and i.t_fin >= v_desde
               group by 1 order by 3 desc, 1 limit 10) x), '[]'::jsonb));
end $f$;

-- ---------------------------------------------------------------------
-- 5. DESCARGAS EN EXCEL (auditadas). El archivo se arma en el navegador; los datos salen solo por aquí y cada descarga queda en la auditoría
--    (quién, cuándo, qué conjunto, el rango y cuántas filas). Columnas fijas: con el nombre visible del tipo y su prefijo (N-12). Sin el nombre ni la
--    placa del tercero, ni textos libres (descripción, compañeros), ni datos de suscriptores.
-- ---------------------------------------------------------------------
create function public.geoportal_redes_descarga(p_solicitante text, p_conjunto text, p_desde date, p_hasta date, p_incluir_ocultos boolean default false, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'descargan los datos de distribución'); v_ini timestamptz; v_fin timestamptz; v_n integer; v_filas jsonb; v_tope integer := 20000;
begin
  if coalesce(p_conjunto, '') not in ('intervenciones', 'danos') then perform tecnica.f_error('Ese conjunto no existe'); end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde then perform tecnica.f_error('Elija el rango de fechas (desde y hasta)'); end if;
  if p_hasta - p_desde > 366 then perform tecnica.f_error('El rango va hasta de un año: acórtelo'); end if;
  v_ini := p_desde::timestamp at time zone 'America/Bogota'; v_fin := (p_hasta + 1)::timestamp at time zone 'America/Bogota';
  if p_conjunto = 'intervenciones' then
    select count(*) into v_n from redes.v_intervencion i where i.t_fin >= v_ini and i.t_fin < v_fin and (coalesce(p_incluir_ocultos, false) or i.estado <> 'oculta');
    if v_n > v_tope then perform tecnica.f_error(format('Son %s filas: el tope es %s; acorte el rango', v_n, v_tope)); end if;
    select coalesce(jsonb_agg(jsonb_build_object(
             'codigo', i.codigo, 'nace_de', i.nace_de, 'dano', i.dano_codigo, 'tipo', i.tipo_nombre, 'inversion_modo', i.inversion_modo, 'sistema', i.sistema,
             'activo', i.activo_codigo, 'prefijo', left(i.activo_codigo, 3), 'tipo_activo', (select t.nombre_visible from redes.v_tipo_visible t where t.prefijo = left(i.activo_codigo, 3)),
             'no_identificado', i.no_ident_que_es, 't_inicio', i.t_inicio, 't_fin', i.t_fin, 'duracion_min', round(i.duracion_s / 60.0),
             'ejecutor', i.ejecutor, 'contratista', i.contratista, 'contrato_orden', i.contrato_orden, 'estado', i.estado, 'resuelve_dano', i.resuelve_dano,
             'fotos', i.fotos, 'documentos', i.documentos, 'recursos', i.recursos, 'aportantes', array_to_string(i.aportantes, ' · '),
             'valor_total', (select sum(f.valor) from redes.v_intervencion_fuentes f where f.intervencion_id = i.id),
             'lat', i.lat, 'lon', i.lon, 'autor', i.autor, 'registrado_en', i.registrado_en) order by i.t_fin, i.codigo), '[]'::jsonb) into v_filas
      from redes.v_intervencion i where i.t_fin >= v_ini and i.t_fin < v_fin and (coalesce(p_incluir_ocultos, false) or i.estado <> 'oculta');
  else
    select count(*) into v_n from redes.v_dano d where d.t_detectado >= v_ini and d.t_detectado < v_fin and (coalesce(p_incluir_ocultos, false) or d.estado <> 'oculto');
    if v_n > v_tope then perform tecnica.f_error(format('Son %s filas: el tope es %s; acorte el rango', v_n, v_tope)); end if;
    select coalesce(jsonb_agg(jsonb_build_object(
             'codigo', d.codigo, 'clase', d.clase, 'tipo', d.tipo_nombre, 'sistema', d.sistema, 'activo', d.activo_codigo, 'prefijo', left(d.activo_codigo, 3),
             'tipo_activo', (select t.nombre_visible from redes.v_tipo_visible t where t.prefijo = left(d.activo_codigo, 3)), 'no_identificado', d.no_ident_que_es, 'estado', d.estado,
             't_inicio_dano', d.t_inicio_dano, 't_detectado', d.t_detectado, 't_inicio_reparacion', d.t_inicio_reparacion, 't_restablecido', d.t_restablecido,
             'respuesta_min', round(d.respuesta_s / 60.0), 'reparacion_min', round(d.reparacion_s / 60.0), 'total_min', case when not d.total_corre then round(d.total_s / 60.0) end,
             'tipo_rotura', d.tipo_rotura, 'largo_afectado_m', d.largo_afectado_m, 'presion_mca', d.presion_mca, 'usuarios_sin_servicio', d.usuarios_sin_servicio,
             'sector', n.sector_num, 'riesgo', d.riesgo, 'causa_clase', d.causa_clase, 'causa', (select c.nombre from redes.causas c where c.codigo = d.causa_codigo),
             'tercero_tipo', d.tercero_tipo, 'origen', d.origen,
             'intervenciones', (select count(*) from redes.intervenciones i where i.dano_id = d.id), 'fotos', (select count(*) from redes.dano_fotos f where f.dano_id = d.id),
             'lat', d.lat, 'lon', d.lon, 'autor', d.autor, 'registrado_en', d.registrado_en) order by d.t_detectado, d.codigo), '[]'::jsonb) into v_filas
      from redes.v_dano d join redes.danos n on n.id = d.id
     where d.t_detectado >= v_ini and d.t_detectado < v_fin and (coalesce(p_incluir_ocultos, false) or d.estado <> 'oculto');
  end if;
  perform tecnica.f_auditar(v_email, 'redes_descarga', p_conjunto, jsonb_build_object('desde', p_desde, 'hasta', p_hasta, 'incluir_ocultos', coalesce(p_incluir_ocultos, false), 'filas', v_n), p_ip);
  return jsonb_build_object('conjunto', p_conjunto, 'desde', p_desde, 'hasta', p_hasta, 'incluir_ocultos', coalesce(p_incluir_ocultos, false), 'total', v_n,
                            'generado_en', clock_timestamp(), 'generado_por', v_email, 'filas', v_filas);
end $f$;

-- ---------------------------------------------------------------------
-- 6. NODOS POR CLASIFICAR (N-3; solo el administrador): S, J, M, Pila y Módulos del modelo de acueducto. Se les pone un nombre visible (alias, con
--    geoportal_redes_alias_fijar del 1a) o se crea el activo que son, enlazado al nodo con un evento (el nodo no se reescribe).
-- ---------------------------------------------------------------------
create function public.geoportal_redes_nodos_por_clasificar(p_solicitante text, p_buscar text default null, p_despues_de bigint default null, p_limite integer default 50)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare v_email text := redes.f_autorizar_admin(p_solicitante); v_q text := nullif(lower(btrim(coalesce(p_buscar, ''))), ''); v_lim integer := coalesce(p_limite, 50); v_items jsonb;
begin
  if v_lim < 1 or v_lim > 200 then perform tecnica.f_error('Se piden de 1 a 200'); end if;
  if v_q is not null and length(v_q) > 60 then perform tecnica.f_error('La búsqueda es demasiado larga'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('nodo_id', x.nodo_id, 'sistema', x.sistema, 'llave_modelo', x.llave_modelo, 'nombre_modelo', x.nombre_modelo,
           'nombre_visible', x.nombre_visible, 'alias', case when x.nombre_visible is distinct from coalesce(x.nombre_modelo, x.llave_modelo) then x.nombre_visible end,
           'lat', round(ST_Y(x.geom)::numeric, 6), 'lon', round(ST_X(x.geom)::numeric, 6),
           'tramos', (select count(*) from redes.v_tramo_nodos_vigente t where t.nodo_ini = x.nodo_id or t.nodo_fin = x.nodo_id)) order by x.nodo_id), '[]'::jsonb) into v_items
    from (select n.* from redes.v_nodo_visible n
           where n.clase_nodo = 'por_clasificar' and (p_despues_de is null or n.nodo_id > p_despues_de)
             and (v_q is null or position(v_q in lower(coalesce(n.nombre_modelo, '') || ' ' || n.nombre_visible || ' ' || n.llave_modelo)) > 0)
           order by n.nodo_id limit v_lim) x;
  return jsonb_build_object(
    'grupos', coalesce((select jsonb_agg(jsonb_build_object('grupo', g.grupo, 'n', g.n) order by g.n desc, g.grupo)
                          from (select coalesce(substring(n.nombre_modelo from '^[A-Za-zÁÉÍÓÚáéíóúñ]+'), '?') as grupo, count(*) as n
                                  from redes.v_nodo_vigente n where n.clase_nodo = 'por_clasificar' group by 1) g), '[]'::jsonb),
    'total', (select count(*) from redes.v_nodo_visible n where n.clase_nodo = 'por_clasificar'
               and (v_q is null or position(v_q in lower(coalesce(n.nombre_modelo, '') || ' ' || n.nombre_visible || ' ' || n.llave_modelo)) > 0)),
    'items', v_items,
    'siguiente', case when jsonb_array_length(v_items) = v_lim then (v_items -> (v_lim - 1) ->> 'nodo_id')::bigint end,
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre_visible, 'sistema', t.sistema,
                         'pide_clase', exists (select 1 from jsonb_array_elements(t.campos) c where c ->> 'clave' = 'clase' and (c ->> 'obligatorio')::boolean),
                         'clases', coalesce((select jsonb_agg(jsonb_build_object('codigo', k.codigo, 'nombre', k.nombre) order by k.orden) from redes.clases_activo k where k.prefijo = t.prefijo and k.activo), '[]'::jsonb))
                         order by t.sistema, t.orden)
                         from redes.v_tipo_visible t where t.geometria = 'punto' and t.activo and t.sistema in ('acueducto', 'alcantarillado')), '[]'::jsonb));
end $f$;

-- Crea el activo que es un nodo por clasificar, en la posición del nodo, y lo enlaza con un evento («enlazar_activo»). El nombre del modelo queda
-- como código anterior (como en la carga). Sin capa: el Corte 5 lo vuelve a enlazar en una recarga por la llave del nodo (pendiente anotado).
create function public.geoportal_redes_nodo_crear_activo(p_solicitante text, p_nodo bigint, p_prefijo text, p_clase_activo text, p_nombre text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare
  v_email text := redes.f_autorizar_admin(p_solicitante); n redes.v_nodo_visible%rowtype; t redes.v_tipo_visible%rowtype;
  v_mot text := btrim(coalesce(p_motivo, '')); v_nom text := nullif(btrim(coalesce(p_nombre, '')), ''); v_cl text := nullif(p_clase_activo, '');
  v_cons bigint; v_cod text; v_act bigint; v_atr jsonb;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  if v_nom is not null and length(v_nom) > 120 then perform tecnica.f_error('El nombre admite hasta 120 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.nodo.' || coalesce(p_nodo, 0)));
  select * into n from redes.v_nodo_visible where nodo_id = p_nodo;
  if not found then perform tecnica.f_error('No existe ese nodo (o ya no es el vigente)', 'P0002'); end if;
  if n.clase_nodo <> 'por_clasificar' then perform tecnica.f_error('Ese nodo ya no está por clasificar'); end if;
  select * into t from redes.v_tipo_visible where prefijo = upper(coalesce(p_prefijo, '')) and sistema = n.sistema and activo;
  if not found then perform tecnica.f_error('Elija un tipo de activo del mismo sistema'); end if;
  if t.geometria <> 'punto' then perform tecnica.f_error('Un nodo es un punto: elija un tipo de punto'); end if;
  if v_cl is not null and not exists (select 1 from redes.clases_activo where prefijo = t.prefijo and codigo = v_cl) then perform tecnica.f_error('Esa clase no existe para el tipo elegido'); end if;
  if v_cl is null and exists (select 1 from jsonb_array_elements(t.campos) x where x ->> 'clave' = 'clase' and (x ->> 'obligatorio')::boolean) then
    perform tecnica.f_error(format('Elija la clase del activo (%s)', t.nombre_visible));
  end if;
  v_atr := jsonb_build_object('nombre_modelo', n.nombre_modelo, 'creado_desde_nodo', n.llave_modelo);
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = t.prefijo returning ultimo into v_cons;
  v_cod := t.prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, t.prefijo, 'ficha', v_email) returning id into v_act;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, estado_codigo, atributos, codigo_anterior, huella, autor)
  values (v_act, 1, n.geom, v_nom, v_cl, 'en_operacion', v_atr, n.nombre_modelo,
          redes.f_huella(n.geom, jsonb_build_object('p', t.prefijo, 'n', v_nom, 'c', v_cl, 'e', null, 'm', null, 'd', null, 'l', null, 'pr', null, 'ca', null, 's', 'en_operacion',
                                                    'ant', n.nombre_modelo, 'a', v_atr)), v_email);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_act, 1, 'emdupar', 'Creado desde la bandeja de nodos por clasificar', v_email);
  insert into redes.nodo_eventos (nodo_id, tipo, activo_id, motivo, autor) values (n.nodo_id, 'enlazar_activo', v_act, v_mot, v_email);
  perform redes.f_mat_refrescar_uno(v_act);
  perform redes.f_subir_tesela(n.sistema);
  perform tecnica.f_auditar(v_email, 'redes_nodo_crear_activo', n.nodo_id::text, jsonb_build_object('nodo', n.nombre_modelo, 'llave', n.llave_modelo, 'activo', v_cod, 'motivo', v_mot), null);
  return jsonb_build_object('nodo_id', n.nodo_id, 'nombre_modelo', n.nombre_modelo, 'activo', v_cod, 'tipo', t.nombre_visible);
end $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas, vista y funciones internas nuevas: nadie de la API. RPC public.geoportal_redes_* (las nuevas y las de antes): solo execute a service_role.
-- =====================================================================
revoke all on all tables in schema redes from public, anon, authenticated, service_role;
revoke all on all sequences in schema redes from public, anon, authenticated, service_role;
revoke all on all functions in schema redes from public, anon, authenticated, service_role;
revoke all on table tecnica.personal_ficha_eventos from public, anon, authenticated, service_role;
revoke all on sequence tecnica.personal_ficha_eventos_id_seq from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte4b', 'migracion_redes_corte4b', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.personal_ficha_eventos', 'redes.cuadrillas')), null);
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
rollback;
