begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 10 — GUARDIA Y TABLAS DE LA FICHA COMO «PERFIL» DEL ACTIVO (§22 y §23 de la bitácora)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew).
-- · Presupone el Corte 3a aplicado (y por lo tanto el 1a y el 2): lo comprueba con la huella md5 del conjunto de funciones de redes y de v_epicrisis.
-- · No toca ningún objeto vivo de otros esquemas. Del 1a solo AGREGA filas a redes.activo_versiones (versión nueva por edición, carga_id nulo)
--   y a redes.activo_origen (corrección del origen); las dos ya son de solo inserción y admiten filas de la ficha.
-- · Del 3a REEMPLAZA (create or replace, mismas columnas y firma): la vista redes.v_epicrisis (le suma los cambios de la ficha) y la RPC
--   geoportal_redes_activo_buscar (busca también por alias y placa). La reversa deja las dos con su texto del 3a.
-- · Todo objeto nuevo: revoke all a public, anon, authenticated y service_role (40); RLS activa sin políticas.
-- =====================================================================
do $$
begin
  if to_regclass('redes.intervenciones') is null then raise exception 'Falta el Corte 3a (redes.intervenciones): aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'b1511119a1014345b4287dc7a45cfcfc' then
    raise exception 'Las funciones de redes no son las del Corte 3a (o el Corte 3b ya está aplicado): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> '4769d9dc85bdb6b6cc81364b3ab7dec7' then raise exception 'La vista v_epicrisis no es la del Corte 3a: deténgase y avise'; end if;
  if to_regclass('redes.ficha_ediciones') is not null then raise exception 'redes.ficha_ediciones ya existe: el Corte 3b parece aplicado'; end if;
  if not exists (select 1 from storage.buckets where id = 'redes-evidencias' and not public) then raise exception 'Falta el bucket privado redes-evidencias del Corte 2'; end if;
end $$;

-- Cada edición de la ficha (datos, alias, placa, origen o foto principal): qué cambió (de A a B), con autor, fecha y motivo. Solo inserción.
-- Si la edición toca datos del activo, crea una VERSIÓN nueva en activo_versiones (carga_id nulo) y aquí queda su número.
create table redes.ficha_ediciones (
  id        bigint generated always as identity primary key,
  activo_id bigint not null references redes.activos (id),
  version   integer,                                          -- la versión que creó (nula si solo cambió alias, placa, origen o foto)
  cambios   jsonb not null check (jsonb_typeof(cambios) = 'array' and jsonb_array_length(cambios) between 1 and 40),   -- [{campo, rotulo, antes, despues}]
  motivo    text not null check (length(btrim(motivo)) between 10 and 1000),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
create index ix_fe_activo on redes.ficha_ediciones (activo_id, id desc);

-- Alias propio del activo («Tanque de La Popa») y placa de almacén o número de inventario. Eventos; lo vigente es el último por campo (nulo = se quitó).
create table redes.activo_identificador_eventos (
  id         bigint generated always as identity primary key,
  activo_id  bigint not null references redes.activos (id),
  campo      text not null check (campo in ('alias', 'placa')),
  valor      text check (valor is null or length(btrim(valor)) between 1 and 60),
  edicion_id bigint not null references redes.ficha_ediciones (id),
  autor      text not null,
  creado_en  timestamptz not null default clock_timestamp()
);
create index ix_aie_activo on redes.activo_identificador_eventos (activo_id, campo, id desc);
create index ix_aie_valor on redes.activo_identificador_eventos (lower(valor));

-- Foto de perfil del activo (la sube el administrador; el supervisor de distribución desde el Corte 4). Reserva de la ruta y la foto fijada.
create table redes.foto_perfil_preparaciones (
  ruta      text primary key check (ruta ~ '^activos/[0-9]{4}-[0-9]{2}/[0-9]{1,12}/[0-9a-f-]{36}\.jpg$'),
  activo_id bigint not null references redes.activos (id),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
create table redes.activo_fotos_perfil (
  id           bigint generated always as identity primary key,
  activo_id    bigint not null references redes.activos (id),
  ruta_storage text not null unique references redes.foto_perfil_preparaciones (ruta),
  bytes        integer not null check (bytes > 0),
  mime         text not null check (mime = 'image/jpeg'),
  edicion_id   bigint not null references redes.ficha_ediciones (id),
  autor        text not null,
  creado_en    timestamptz not null default clock_timestamp()
);
create index ix_afp_activo on redes.activo_fotos_perfil (activo_id, id desc);

do $$
declare t text;
begin
  foreach t in array array['ficha_ediciones', 'activo_identificador_eventos', 'foto_perfil_preparaciones', 'activo_fotos_perfil'] loop
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 20 — VISTAS: alias y placa vigentes, fotos del activo y la epicrisis como muro (con los cambios de la ficha)
-- PROPUESTA. No se ha ejecutado en la base real.
-- =====================================================================

-- Alias propio y placa (o número de inventario) vigentes de cada activo que tenga alguno.
create view redes.v_activo_identificadores as
select x.activo_id,
       (select e.valor from redes.activo_identificador_eventos e where e.activo_id = x.activo_id and e.campo = 'alias' order by e.id desc limit 1) as alias,
       (select e.valor from redes.activo_identificador_eventos e where e.activo_id = x.activo_id and e.campo = 'placa' order by e.id desc limit 1) as placa
  from (select distinct activo_id from redes.activo_identificador_eventos) x;

-- Todas las fotos de un activo: las de perfil, las de sus daños (no ocultos) y las de sus intervenciones (principal o también intervenido; sin los PDF).
create function redes.f_fotos_activo(p_activo bigint)
returns table (origen text, codigo text, clase text, ruta text, cuando timestamptz, autor text)
language sql stable set search_path to 'redes', 'pg_temp' as $f$
  select 'perfil', null::text, 'perfil', p.ruta_storage, p.creado_en, p.autor from redes.activo_fotos_perfil p where p.activo_id = p_activo
  union all
  select 'dano', d.codigo, f.momento, f.ruta_storage, d.t_detectado, d.autor from redes.v_dano d join redes.dano_fotos f on f.dano_id = d.id
   where d.activo_id = p_activo and d.estado <> 'oculto'
  union all
  select 'intervencion', i.codigo, a.clase, a.ruta_storage, i.t_fin, i.autor from redes.v_intervencion i join redes.intervencion_archivos a on a.intervencion_id = i.id
   where a.clase <> 'documento' and i.estado <> 'oculta'
     and (i.activo_id = p_activo or exists (select 1 from redes.intervencion_activos x where x.intervencion_id = i.id and x.activo_id = p_activo)) $f$;

-- Epicrisis: la del Corte 3a MÁS los cambios de la ficha. Mismas columnas. La reversa deja el texto del 3a.
create or replace view redes.v_epicrisis as
select v.activo_id, v.creado_en as cuando, case when v.version = 1 then 'alta' else 'version' end as clase, v.id as ref_id,
       case when v.version = 1 then 'Alta del activo' else 'Versión ' || v.version end
         || case when v.carga_id is not null then ' (carga ' || v.carga_id || ')'
                 when v.version = 1 and exists (select 1 from redes.activos x where x.id = v.activo_id and x.origen_alta = 'intervencion')
                   then coalesce(' (inversión ' || (select i.codigo from redes.intervenciones i where i.activo_id = v.activo_id and i.activo_creado limit 1) || ')', ' (intervención)')
                 else ' (ficha)' end as resumen,
       case when v.carga_id is not null and exists (select 1 from redes.carga_eventos e where e.carga_id = v.carga_id and e.tipo = 'revertir') then 'revertida' else 'vigente' end as estado,
       v.autor
  from redes.activo_versiones v
 -- las versiones que creó una edición de la ficha salen una sola vez, como «ficha», con lo que cambió y el motivo (abajo)
 where not exists (select 1 from redes.ficha_ediciones f where f.activo_id = v.activo_id and f.version = v.version)
union all
select e.activo_id, e.creado_en, 'evento_' || e.tipo, e.id, e.motivo, null, e.autor from redes.activo_eventos e
union all
select c.padre_id, c.creado_en, 'componente_' || c.accion, c.id, 'Componente ' || h.codigo || ': ' || c.motivo, null, c.autor
  from redes.activo_componentes c join redes.activos h on h.id = c.hijo_id
union all
select c.hijo_id, c.creado_en, 'es_componente_' || c.accion, c.id, 'Parte de ' || p.codigo || ': ' || c.motivo, null, c.autor
  from redes.activo_componentes c join redes.activos p on p.id = c.padre_id
union all
-- Daños y fallas: el ref_id es el número del código (DAN-000123 → 123), para paginar con el mismo cursor.
select d.activo_id, d.t_detectado, d.clase, substring(d.codigo from 5)::bigint,
       d.codigo || ' · ' || d.tipo_nombre
         || coalesce(' · ' || (select r.nombre from redes.tipos_rotura r where r.codigo = d.tipo_rotura), '')
         || ' · riesgo ' || d.riesgo
         || case d.causa_clase when 'propia' then ' · causa propia' when 'terceros' then ' · causa de terceros' else ' · causa desconocida' end
         || case when d.total_corre then '' else ' · duración ' || (d.total_s / 3600) || ' h ' || lpad(((d.total_s % 3600) / 60)::text, 2, '0') || ' min' end
         || case when d.perdida_m3 is not null then ' · pérdida ≈ ' || d.perdida_m3 || ' m³' else '' end
         || case when not exists (select 1 from redes.dano_fotos f where f.dano_id = d.id) then ' · sin evidencia fotográfica' else '' end,
       case d.estado when 'reportado' then 'Reportado' when 'en_atencion' then 'En atención' when 'atendido' then 'Atendido' else 'Oculto' end,
       d.autor
  from redes.v_dano d
 where d.activo_id is not null and d.estado <> 'oculto'
union all
-- Intervenciones: en el activo principal…
select i.activo_id, i.t_fin, 'intervencion', substring(i.codigo from 5)::bigint,
       i.codigo || ' · ' || i.tipo_nombre
         || case i.inversion_modo when 'nuevo' then ' (activo nuevo)' when 'mejora' then ' (mejora)' else '' end
         || case when i.dano_codigo is not null then ' · atiende ' || i.dano_codigo || case when i.resuelve_dano then ' (lo resuelve)' else ' (sigue abierto)' end else ' · programada o mejora' end
         || case i.ejecutor when 'emdupar' then ' · EMDUPAR' else ' · contratista' || coalesce(' ' || i.contratista, '') end
         || ' · duración ' || (i.duracion_s / 3600) || ' h ' || lpad(((i.duracion_s % 3600) / 60)::text, 2, '0') || ' min'
         || case when i.tambien > 0 then ' · ' || i.tambien || ' activo(s) más' else '' end
         || case when i.sin_evidencia then ' · sin evidencia fotográfica' else ' · ' || i.fotos || ' foto(s)' end,
       case i.estado when 'cerrada' then 'Cerrada' when 'anulada' then 'Anulada' when 'programada' then 'Programada' when 'en_ejecucion' then 'En ejecución' else 'Oculta' end,
       i.autor
  from redes.v_intervencion i
 where i.activo_id is not null and i.estado <> 'oculta'
union all
-- … y en cada activo también intervenido
select x.activo_id, i.t_fin, 'intervencion', substring(i.codigo from 5)::bigint,
       i.codigo || ' · ' || i.tipo_nombre || ' · también intervenido' || coalesce(' (principal ' || i.activo_codigo || ')', ''),
       case i.estado when 'cerrada' then 'Cerrada' when 'anulada' then 'Anulada' when 'programada' then 'Programada' when 'en_ejecucion' then 'En ejecución' else 'Oculta' end,
       i.autor
  from redes.intervencion_activos x join redes.v_intervencion i on i.id = x.intervencion_id
 where i.estado <> 'oculta' and x.activo_id is distinct from i.activo_id
union all
-- Cambios de la ficha (Corte 3b): «Se cambió X de A a B», con el motivo. La corrección del origen no muestra valores ni motivo (solo lo ve el supervisor).
select f.activo_id, f.creado_en, 'ficha', f.id,
       (select string_agg(case c ->> 'campo' when 'origen' then 'Se corrigió el origen del activo'
                                             when 'foto' then 'Nueva foto principal'
                                             else (c ->> 'rotulo') || ': de «' || coalesce(c ->> 'antes', 'sin dato') || '» a «' || coalesce(c ->> 'despues', 'sin dato') || '»' end,
                          '; ' order by o) from jsonb_array_elements(f.cambios) with ordinality y(c, o))
         || case when exists (select 1 from jsonb_array_elements(f.cambios) c where c ->> 'campo' = 'origen') then '' else ' · ' || f.motivo end,
       null, f.autor
  from redes.ficha_ediciones f;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 25 — RPC: perfil del activo, galería (auditada), edición de la ficha con versiones, foto principal y la
-- búsqueda por alias y placa.
-- PROPUESTA. No se ha ejecutado en la base real. Todas security definer, search_path fijo, mensajes con HINT msg_usuario; solo service_role.
-- Quién: leen el perfil el operador, el supervisor y el administrador de Técnica (f_perfil_lectura del 1b). La galería y la foto principal, solo
-- supervisor y administrador (las fotos de un daño de terceros pueden mostrar una placa: dato personal). Editar la ficha y su foto, POR AHORA solo
-- el administrador (§23); el supervisor de distribución desde el Corte 4, con ver_dashboard_redes (se cambia solo redes.f_editor_ficha).
-- =====================================================================

-- ---------- Ayudantes internos (nadie de la API los ejecuta) ----------
create function redes.f_editor_ficha(p_solicitante text) returns text
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if p.perfil <> 'admin' then raise exception 'Por ahora solo el administrador edita la ficha del activo' using errcode = '42501'; end if;
  return p.email;
end $f$;

-- Texto para mostrar «de A a B» (nombres de catálogo, fechas dd/mm/aaaa, números sin ceros de más).
create function redes.f_texto_valor(p_campo text, p_valor text, p_prefijo text) returns text
language sql stable set search_path to 'redes', 'pg_temp' as $f$
  select case when p_valor is null then null
              when p_campo = 'estado_codigo' then (select nombre from redes.estados_activo where codigo = p_valor)
              when p_campo = 'material_codigo' then (select nombre from redes.materiales where codigo = p_valor)
              when p_campo = 'clase' then (select nombre from redes.clases_activo where prefijo = p_prefijo and codigo = p_valor)
              when p_campo = 'efecto' then (select nombre from redes.efectos_valvula where codigo = p_valor)
              when p_campo = 'fecha_instalacion' then to_char(p_valor::date, 'DD/MM/YYYY')
              when p_valor ~ '^-?[0-9]+(\.[0-9]+)?$' then trim(trailing '.' from trim(trailing '0' from case when position('.' in p_valor) > 0 then p_valor else p_valor || '.' end))
              else p_valor end $f$;

-- Foto principal: la de perfil más reciente; si no hay, la más reciente «después» de una intervención; si no, la más reciente de todas.
create function redes.f_foto_principal(p_activo bigint) returns jsonb
language sql stable set search_path to 'redes', 'pg_temp' as $f$
  select jsonb_build_object('origen', f.origen, 'codigo', f.codigo, 'clase', f.clase, 'ruta', f.ruta, 'cuando', f.cuando)
    from redes.f_fotos_activo(p_activo) f
   order by (f.origen = 'perfil') desc, (f.origen = 'intervencion' and f.clase = 'despues') desc, f.cuando desc limit 1 $f$;

-- ---------- Perfil del activo: alias, placa, foto principal y, para quien edita, los catálogos y los valores actuales ----------
create function public.geoportal_redes_perfil(p_solicitante text, p_ref text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
declare p record; v_id bigint; v redes.v_activo_vigente%rowtype; t redes.v_tipo_visible%rowtype; i redes.v_activo_identificadores%rowtype;
        v_super boolean; v_edita boolean; v_campos jsonb; o redes.v_activo_origen_vigente%rowtype; v_n integer;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  v_id := redes.f_buscar_activo(p_ref);
  select * into v from redes.v_activo_vigente where activo_id = v_id;
  select * into t from redes.v_tipo_visible where prefijo = v.prefijo;
  select * into i from redes.v_activo_identificadores where activo_id = v_id;
  v_super := p.perfil in ('admin', 'supervisor'); v_edita := p.perfil = 'admin';
  if v_super then select count(*) into v_n from redes.f_fotos_activo(v_id); end if;
  if v_edita then
    select * into o from redes.v_activo_origen_vigente where activo_id = v_id;
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
      'max_bytes_foto', redes.f_param('max_bytes_foto_perfil')) end));
end $f$;

-- ---------- Galería: todas las fotos del activo (perfil, daños e intervenciones). Solo supervisor y administrador; la lectura queda auditada. ----------
create function public.geoportal_redes_galeria(p_solicitante text, p_ref text, p_limite integer default 30)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_supervisor(p_solicitante, 'ven la galería de fotos del activo'); v_id bigint := redes.f_buscar_activo(p_ref); v_lim integer := coalesce(p_limite, 30); v_r jsonb;
begin
  if v_lim < 1 or v_lim > 60 then perform tecnica.f_error('Se piden de 1 a 60 fotos'); end if;
  v_r := jsonb_build_object('codigo', (select codigo from redes.activos where id = v_id), 'total', (select count(*) from redes.f_fotos_activo(v_id)),
    'principal', redes.f_foto_principal(v_id),
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('origen', f.origen, 'codigo', f.codigo, 'clase', f.clase, 'ruta', f.ruta, 'cuando', f.cuando) order by f.cuando desc, f.ruta)
                         from (select * from redes.f_fotos_activo(v_id) order by cuando desc, ruta limit v_lim) f), '[]'::jsonb));
  perform tecnica.f_auditar(v_email, 'redes_galeria', v_r ->> 'codigo', jsonb_build_object('fotos', jsonb_array_length(v_r -> 'fotos')), null);
  return v_r;
end $f$;

-- ---------- Editar la ficha: versión nueva (datos), eventos (alias y placa) y origen corregido; cada edición con autor, fecha y motivo ----------
-- p_cambios: solo las claves que cambian; nulo = dejarlo «sin dato». Claves: nombre, estado_codigo, material_codigo, diametro_mm, capacidad, profundidad_m,
--   fecha_instalacion, barrio_sector, clase, efecto, observaciones, atributos{clave: valor}, alias, placa, origen{origen, aportante, nota}.
create function public.geoportal_redes_ficha_editar(p_solicitante text, p_ref text, p_cambios jsonb, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $f$
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
end $f$;

-- ---------- Foto principal (perfil): preparar la ruta (la Edge firma la subida) y fijarla con su motivo ----------
create function public.geoportal_redes_foto_perfil_preparar(p_solicitante text, p_ref text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v_email text := redes.f_editor_ficha(p_solicitante); v_id bigint := redes.f_buscar_activo(p_ref); v_ruta text;
begin
  if (select retirado from redes.activo_vigente_mat where activo_id = v_id) then perform tecnica.f_error('Ese activo está retirado: su ficha no se edita'); end if;
  v_ruta := 'activos/' || to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM') || '/' || v_id || '/' || gen_random_uuid() || '.jpg';
  insert into redes.foto_perfil_preparaciones (ruta, activo_id, autor) values (v_ruta, v_id, v_email);
  return jsonb_build_object('ruta', v_ruta, 'tipo_mime', 'image/jpeg', 'max_bytes_foto', redes.f_param('max_bytes_foto_perfil')::bigint);
end $f$;

create function public.geoportal_redes_foto_perfil_fijar(p_solicitante text, p_ref text, p_ruta text, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'storage', 'pg_temp' as $f$
declare v_email text := redes.f_editor_ficha(p_solicitante); v_id bigint := redes.f_buscar_activo(p_ref); v_size bigint; v_mime text; v_ed bigint; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo del cambio (10 caracteres o más)'); end if;
  if not exists (select 1 from redes.foto_perfil_preparaciones where ruta = p_ruta and activo_id = v_id and autor = v_email) then perform tecnica.f_error('Primero debe prepararse la subida de esta foto'); end if;
  if exists (select 1 from redes.activo_fotos_perfil where ruta_storage = p_ruta) then
    return jsonb_build_object('codigo', (select codigo from redes.activos where id = v_id), 'repetido', true);
  end if;
  select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'redes-evidencias' and o.name = p_ruta;
  if not found then perform tecnica.f_error('No se encontró la foto: súbala de nuevo'); end if;
  if coalesce(v_size, 0) <= 0 or v_size > redes.f_param('max_bytes_foto_perfil') then perform tecnica.f_error(format('La foto pesa más de lo permitido (%s KB)', (redes.f_param('max_bytes_foto_perfil') / 1024)::integer)); end if;
  if v_mime is distinct from 'image/jpeg' then perform tecnica.f_error('La foto debe ser JPEG'); end if;
  insert into redes.ficha_ediciones (activo_id, cambios, motivo, autor) values (v_id, '[{"campo": "foto", "rotulo": "Foto principal"}]', v_mot, v_email) returning id into v_ed;
  insert into redes.activo_fotos_perfil (activo_id, ruta_storage, bytes, mime, edicion_id, autor) values (v_id, p_ruta, v_size, v_mime, v_ed, v_email);
  perform tecnica.f_auditar(v_email, 'redes_foto_perfil', (select codigo from redes.activos where id = v_id), jsonb_build_object('bytes', v_size), null);
  return jsonb_build_object('codigo', (select codigo from redes.activos where id = v_id), 'repetido', false);
end $f$;

-- ---------- Búsqueda (Corte 2) que además encuentra por la placa (exacta o por su comienzo) y por el alias (contiene) ----------
create or replace function public.geoportal_redes_activo_buscar(p_solicitante text, p_texto text, p_sistema text default null, p_limite integer default 10)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'redes', 'extensions', 'pg_temp' as $f$
declare p record; v text := btrim(coalesce(p_texto, '')); v_lim integer := coalesce(p_limite, 10);
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  if length(v) < 2 or length(v) > 60 then perform tecnica.f_error('Escriba de 2 a 60 caracteres'); end if;
  if p_sistema is not null and p_sistema not in ('acueducto', 'alcantarillado') then perform tecnica.f_error('Ese sistema no existe'); end if;
  if v_lim < 1 or v_lim > 10 then perform tecnica.f_error('Se piden de 1 a 10 activos'); end if;
  return jsonb_build_object('activos', coalesce((
    select jsonb_agg(redes.f_activo_corto(x.activo_id) || jsonb_strip_nulls(jsonb_build_object('sistema', x.sistema, 'lat', x.lat, 'lon', x.lon, 'alias', x.alias, 'placa', x.placa))
                     order by x.rango, x.codigo)
      from (select m.activo_id, m.codigo, m.sistema, i.alias, i.placa,
                   round(ST_Y(case when GeometryType(m.geom) = 'POINT' then m.geom else ST_PointOnSurface(m.geom) end)::numeric, 6) as lat,
                   round(ST_X(case when GeometryType(m.geom) = 'POINT' then m.geom else ST_PointOnSurface(m.geom) end)::numeric, 6) as lon,
                   case when m.codigo = upper(v) or lower(m.codigo_anterior) = lower(v) or lower(i.placa) = lower(v) then 0 else 1 end as rango
              from redes.activo_vigente_mat m
              left join redes.v_activo_identificadores i on i.activo_id = m.activo_id
             where not m.retirado and not m.oculto and (p_sistema is null or m.sistema = p_sistema)
               and (m.codigo like upper(v) || '%' or lower(m.codigo_anterior) like lower(v) || '%'
                    or lower(i.placa) like lower(v) || '%' or lower(i.alias) like '%' || lower(v) || '%')
             order by rango, m.codigo limit v_lim) x), '[]'::jsonb));
end $f$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 30 — SEMILLA: parámetro de la foto principal
-- =====================================================================
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('max_bytes_foto_perfil', 1572864, 'bytes', 102400, 2097152, 'Tope de la foto principal (perfil) de un activo (1,5 MB)')
on conflict (clave) do nothing;   -- si una reversa anterior lo conservó (redes.parametros no deja borrar filas), se reutiliza con su valor
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vistas nuevas de redes: RLS activa sin políticas y ningún privilegio para la API. Funciones internas: nadie de la API.
-- RPC public.geoportal_redes_* nuevas (y activo_buscar, que se reemplaza y conserva su ACL): solo execute a service_role.
-- =====================================================================
revoke all on all tables in schema redes from public, anon, authenticated, service_role;
revoke all on all sequences in schema redes from public, anon, authenticated, service_role;
revoke all on all functions in schema redes from public, anon, authenticated, service_role;
do $$
declare t record; f record;
begin
  for t in select c.relname from pg_class c where c.relnamespace = 'redes'::regnamespace and c.relkind in ('r', 'p') and not c.relrowsecurity loop
    execute format('alter table redes.%I enable row level security', t.relname);
  end loop;
  for f in select p.oid::regprocedure as firma from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
           ('geoportal_redes_perfil', 'geoportal_redes_galeria', 'geoportal_redes_ficha_editar', 'geoportal_redes_foto_perfil_preparar', 'geoportal_redes_foto_perfil_fijar',
            'geoportal_redes_activo_buscar') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;
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
rollback;
