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
commit;
