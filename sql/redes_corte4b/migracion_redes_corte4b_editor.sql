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
commit;
