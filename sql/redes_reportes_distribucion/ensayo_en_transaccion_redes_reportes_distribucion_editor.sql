begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · DESCARGAS DE DISTRIBUCIÓN (pestaña «Descargas» del Dashboard distribución) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Encargo de David del 19-nov: cada formulario tiene su propia descarga. «Daños y fallas» e «Intervenciones» siguen con la ruta «descarga» de siempre
-- (no se toca); aquí van las siete nuevas: Encontrar o reportar activo, Válvulas cerradas, Eventos de suspensión, Línea 116, Reportes del bot,
-- Usuarios sensibles y Activos de la red.
-- · Presupone el aviso por contrato publicado: huella del conjunto de funciones de redes b474fbbe3e0f7a3a7e6dbc04c53e02e7.
-- · Solo AGREGA: 2 tablas (las descargas y sus cierres, solo inserción), funciones internas de lectura y 4 RPC (la cuarta, la lista del filtro de sector). No reemplaza nada.
-- =====================================================================
do $$
begin
  if to_regclass('redes.reporte_descargas') is not null or to_regprocedure('public.geoportal_redes_reporte_iniciar(text,text,jsonb,text,boolean,text)') is not null then
    raise exception 'Las descargas de Distribución ya están aplicadas: deténgase y avise';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'b474fbbe3e0f7a3a7e6dbc04c53e02e7' then
    raise exception 'Las funciones de redes no son las del aviso por contrato publicado (huella b474fbbe3e0f7a3a7e6dbc04c53e02e7): deténgase y avise';
  end if;
  if to_regclass('redes.v_levantar_punto') is null or to_regclass('redes.valvula_maniobras') is null or to_regclass('redes.v_evento_suspension') is null
     or to_regclass('redes.l116_vigente') is null or to_regclass('redes.v_reporte_externo') is null or to_regclass('redes.v_usuario_sensible') is null
     or to_regclass('redes.activo_vigente_mat') is null or to_regprocedure('redes.f_supervisor(text,text)') is null or to_regprocedure('redes.f_sector_de(geometry)') is null
     or to_regprocedure('redes.f_evento_reportes(bigint)') is null or to_regprocedure('tecnica.f_auditar(text,text,text,jsonb,text)') is null then
    raise exception 'Faltan tablas o funciones de los cortes publicados: deténgase y avise';
  end if;
end $$;

create table redes.reporte_descargas (
  id         bigint generated always as identity primary key,
  email      text not null check (email = lower(email) and position('@' in email) > 1),
  reporte    text not null check (reporte ~ '^[a-z0-9_]{3,30}$'),
  filtros    jsonb not null check (jsonb_typeof(filtros) = 'object'),
  incluir    boolean not null,
  formato    text not null check (formato in ('csv', 'xlsx')),
  total      integer not null check (total >= 0),
  corte_en   timestamptz not null,
  ip         text,
  creado_en  timestamptz not null default clock_timestamp()
);
create index ix_redes_rep_descargas_email on redes.reporte_descargas (email, id desc);
create table redes.reporte_descarga_cierres (
  descarga_id bigint primary key references redes.reporte_descargas (id),
  filas       integer not null check (filas >= 0),
  resultado   text not null check (resultado in ('completa', 'cancelada', 'error')),
  ip          text,
  creado_en   timestamptz not null default clock_timestamp()
);
create trigger t_solo_agregar before update or delete on redes.reporte_descargas for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.reporte_descargas for each statement execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar before update or delete on redes.reporte_descarga_cierres for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.reporte_descarga_cierres for each statement execute function tecnica.f_solo_agregar();
alter table redes.reporte_descargas enable row level security;
alter table redes.reporte_descarga_cierres enable row level security;
revoke all on redes.reporte_descargas, redes.reporte_descarga_cierres from public, anon, authenticated, service_role;
revoke all on sequence redes.reporte_descargas_id_seq from public, anon, authenticated, service_role;
-- =====================================================================
-- 20 — FUNCIONES INTERNAS de las descargas de Distribución (nadie de la API las ejecuta; las llaman las RPC del 26).
-- Cada reporte devuelve (k, fila): «k» es la llave de orden y de paginación y «fila» el objeto con las claves de sus columnas.
-- Sin textos libres (observaciones, motivos, la causa ESCRITA del evento, descripción y dirección del ciudadano, la palabra del nombre que marcó a un sensible).
-- Contrato sí. Del evento sí salen el tipo y la causa DE CATÁLOGO del daño asociado (David, 20-nov). El filtro de sector es el código de un sector o subsector
-- de la capa (activo SEC, como en el Corte 15); la lista la da geoportal_redes_reporte_sectores.
-- =====================================================================

create function redes.f_rep_catalogo() returns table (clave text, titulo text, orden integer, filtros text[], usa_ocultos boolean, periodo boolean, periodo_sobre text)
language sql immutable set search_path to 'pg_catalog' as $$
  values ('levantamientos', 'Encontrar o reportar activo', 3, array['sector'],         true,  true,  'el día del reporte'),
         ('valvulas',       'Válvulas cerradas',           4, array['sector'],         false, true,  'el día del cierre'),
         ('eventos',        'Eventos de suspensión',       5, array['sector'],         true,  true,  'el evento: sale si estuvo vigente algún momento del periodo'),
         ('l116',           'Línea 116',                   6, array['sector'],         true,  true,  'el día del reporte en la 116'),
         ('bot',            'Reportes del bot',            7, array['sector'],         true,  true,  'el día en que se recibió'),
         ('sensibles',      'Usuarios sensibles',          8, array['tipo'],           true,  false, null),
         ('activos',        'Activos de la red',           9, array['tipo', 'sistema'], true, false, null) $$;

create function redes.f_rep_max_filas() returns integer language sql immutable set search_path to 'pg_catalog' as $$ select 50000 $$;
create function redes.f_rep_ts(p timestamptz) returns text language sql stable set search_path to 'pg_catalog' as $$
  select to_char(p at time zone 'America/Bogota', 'YYYY-MM-DD"T"HH24:MI:SS') $$;
create function redes.f_rep_col(p_clave text, p_titulo text, p_tipo text, p_unidad text default null, p_decimales integer default null) returns jsonb
language sql immutable set search_path to 'pg_catalog' as $$
  select jsonb_build_object('clave', p_clave, 'titulo', p_titulo, 'unidad', p_unidad, 'tipo', p_tipo)
         || case when p_decimales is not null then jsonb_build_object('decimales', p_decimales) else '{}'::jsonb end $$;
-- «en_atencion» → «En atención»… para los estados guardados como clave
create function redes.f_rep_rotulo(p text) returns text language sql immutable set search_path to 'pg_catalog' as $$
  select case p when 'en_atencion' then 'En atención' when 'por_confirmar' then 'Por confirmar' when 'en_revision' then 'En revisión'
                else upper(left(p, 1)) || replace(substr(p, 2), '_', ' ') end $$;
-- La zona de un sector o subsector de la capa de sectores (por su código SEC-…, vigente), para filtrar por sector.
create function redes.f_rep_sector_geom(p_codigo text) returns geometry
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $$
  select m.geom from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.codigo = p_codigo $$;
-- Los sectores y subsectores de la capa (los mismos del Corte 15), con su número de sector y su subsector del modelo, para la lista del filtro.
create function redes.f_rep_sectores() returns table (codigo text, nombre text, clase text, sector integer, subsector text)
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $$
  select m.codigo, coalesce(nullif(btrim(m.nombre), ''), m.codigo), coalesce(m.clase, 'sector'),
         redes.f_num(v.atributos -> 'modelo' -> 'sector')::integer, nullif(btrim(v.atributos -> 'modelo' ->> 'subsector'), '')
    from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
   where m.prefijo = 'SEC' and not m.retirado and not m.oculto $$;
-- Un punto del activo para las columnas lat/lon (el mismo si es un punto; sobre la línea si es un tramo).
create function redes.f_rep_punto(p geometry) returns geometry language sql immutable set search_path to 'public', 'extensions', 'pg_temp' as $$
  select case when p is null then null when GeometryType(p) = 'POINT' then p else ST_PointOnSurface(p) end $$;

create function redes.f_rep_filtros(p_reporte text, p_filtros jsonb) returns jsonb
language plpgsql stable set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_f jsonb := coalesce(p_filtros, '{}'::jsonb); c record; v_desde date; v_hasta date; v_k text; v_r jsonb := '{}'::jsonb; v_t text; v_n text;
begin
  select * into c from redes.f_rep_catalogo() x where x.clave = p_reporte;
  if not found then perform tecnica.f_error('Ese reporte no existe.'); end if;
  if jsonb_typeof(v_f) <> 'object' then perform tecnica.f_error('Los filtros no son válidos.'); end if;
  for v_k in select jsonb_object_keys(v_f) loop
    if v_k not in ('desde', 'hasta') and not v_k = any (c.filtros) then perform tecnica.f_error('Ese filtro no aplica a este reporte.'); end if;
    if jsonb_typeof(v_f -> v_k) <> 'string' then perform tecnica.f_error('Un filtro no es válido.'); end if;
  end loop;
  if c.periodo then
    begin
      v_desde := (v_f ->> 'desde')::date; v_hasta := (v_f ->> 'hasta')::date;
    exception when others then perform tecnica.f_error('Elija el periodo (desde y hasta, como AAAA-MM-DD).');
    end;
    if v_desde is null or v_hasta is null then perform tecnica.f_error('Elija el periodo (desde y hasta).'); end if;
    if v_hasta < v_desde then perform tecnica.f_error('La fecha inicial no puede ser posterior a la final.'); end if;
    if v_hasta - v_desde > 365 then perform tecnica.f_error('El periodo va hasta de un año: acórtelo.'); end if;
    v_r := jsonb_build_object('desde', v_desde, 'hasta', v_hasta);
  end if;
  v_t := upper(nullif(btrim(v_f ->> 'sector'), ''));
  if v_t is not null then
    if v_t !~ '^SEC-[0-9]{1,9}$' then perform tecnica.f_error('Elija el sector de la lista.'); end if;
    select s.nombre into v_n from redes.f_rep_sectores() s where s.codigo = v_t;
    if not found then perform tecnica.f_error('Ese sector no está en la capa de sectores.'); end if;
    v_r := v_r || jsonb_build_object('sector', v_t, 'sector_nombre', v_n);
  end if;
  v_t := nullif(btrim(v_f ->> 'tipo'), '');
  if v_t is not null and p_reporte = 'sensibles' then
    select t.nombre into v_n from redes.tipos_sensible t where t.codigo = lower(v_t);
    if not found then perform tecnica.f_error('Ese tipo de usuario sensible no existe.'); end if;
    v_r := v_r || jsonb_build_object('tipo', lower(v_t), 'tipo_nombre', v_n);
  elsif v_t is not null then
    select t.nombre_visible into v_n from redes.v_tipo_visible t where t.prefijo = upper(v_t);
    if not found then perform tecnica.f_error('Ese tipo de activo no existe.'); end if;
    v_r := v_r || jsonb_build_object('tipo', upper(v_t), 'tipo_nombre', v_n);
  end if;
  v_t := nullif(lower(btrim(v_f ->> 'sistema')), '');
  if v_t is not null then
    if not exists (select 1 from redes.sistemas s where s.codigo = v_t) then perform tecnica.f_error('Ese sistema no existe.'); end if;
    v_r := v_r || jsonb_build_object('sistema', v_t);
  end if;
  return v_r;
end $$;

create function redes.f_rep_columnas(p_reporte text) returns jsonb
language plpgsql immutable set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare ubic jsonb := jsonb_build_array(redes.f_rep_col('sector', 'Sector', 'entero'), redes.f_rep_col('lat', 'Latitud', 'decimal', null, 6), redes.f_rep_col('lon', 'Longitud', 'decimal', null, 6));
begin
  return case p_reporte
  when 'levantamientos' then jsonb_build_array(
    redes.f_rep_col('codigo', 'Código', 'texto'), redes.f_rep_col('reportado', 'Reportado', 'fecha_hora'), redes.f_rep_col('servicio', 'Servicio', 'texto'),
    redes.f_rep_col('tipo', 'Qué se reportó', 'texto'), redes.f_rep_col('area', 'Área', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'),
    redes.f_rep_col('estado_desde', 'Estado desde', 'fecha_hora'), redes.f_rep_col('activo', 'Activo creado', 'texto'), redes.f_rep_col('fotos', 'Fotos', 'entero'),
    redes.f_rep_col('precision_m', 'Precisión del GPS', 'decimal', 'm', 1), redes.f_rep_col('precision_baja', 'Precisión baja', 'si_no'))
    || ubic || jsonb_build_array(redes.f_rep_col('reporto', 'Reportó (correo)', 'texto'))
  when 'valvulas' then jsonb_build_array(
    redes.f_rep_col('valvula', 'Válvula', 'texto'), redes.f_rep_col('cerrada', 'Cerrada', 'fecha_hora'), redes.f_rep_col('regreso_estimado', 'Regreso estimado vigente', 'fecha_hora'),
    redes.f_rep_col('cambios_regreso', 'Cambios del regreso estimado', 'entero'), redes.f_rep_col('abierta', 'Abierta', 'fecha_hora'),
    redes.f_rep_col('duracion_h', 'Duración', 'decimal', 'h', 1), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('dano', 'Daño', 'texto'),
    redes.f_rep_col('intervencion', 'Intervención', 'texto'))
    || ubic || jsonb_build_array(redes.f_rep_col('cerro', 'Cerró (correo)', 'texto'), redes.f_rep_col('abrio', 'Abrió (correo)', 'texto'))
  when 'eventos' then jsonb_build_array(
    redes.f_rep_col('evento', 'Evento', 'texto'), redes.f_rep_col('alcance', 'Alcance', 'texto'), redes.f_rep_col('zona', 'Zona', 'texto'), redes.f_rep_col('planta', 'Planta', 'texto'),
    redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('desde', 'Sin agua desde', 'fecha_hora'),
    redes.f_rep_col('regreso_estimado_inicial', 'Regreso estimado al declarar', 'fecha_hora'), redes.f_rep_col('regreso_estimado', 'Regreso estimado vigente', 'fecha_hora'),
    redes.f_rep_col('cambios_regreso', 'Cambios del regreso estimado', 'entero'), redes.f_rep_col('fin', 'Cerrado o anulado', 'fecha_hora'),
    redes.f_rep_col('duracion_h', 'Duración', 'decimal', 'h', 1), redes.f_rep_col('contratos', 'Contratos afectados', 'entero'),
    redes.f_rep_col('sensibles', 'Usuarios sensibles afectados', 'entero'), redes.f_rep_col('reportes', 'Reportes asociados', 'entero'),
    redes.f_rep_col('reportes_bot', 'Del bot', 'entero'), redes.f_rep_col('reportes_116', 'De la 116', 'entero'), redes.f_rep_col('reportes_danos', 'Daños', 'entero'),
    redes.f_rep_col('reportes_campo', 'De campo', 'entero'), redes.f_rep_col('dano', 'Daño', 'texto'), redes.f_rep_col('tipo', 'Tipo de daño o falla', 'texto'),
    redes.f_rep_col('causa', 'Causa del daño', 'texto'), redes.f_rep_col('intervencion', 'Intervención', 'texto'), redes.f_rep_col('tipo_intervencion', 'Tipo de intervención', 'texto'),
    redes.f_rep_col('declaro', 'Declaró (correo)', 'texto'), redes.f_rep_col('cerro', 'Cerró o anuló (correo)', 'texto'))
  when 'l116' then jsonb_build_array(
    redes.f_rep_col('reporte', 'Reporte de la 116', 'entero'), redes.f_rep_col('registrado_116', 'Registrado en la 116', 'fecha_hora'), redes.f_rep_col('dia', 'Día', 'fecha'),
    redes.f_rep_col('servicio', 'Servicio', 'texto'), redes.f_rep_col('causal', 'Causal', 'texto'), redes.f_rep_col('comuna', 'Comuna', 'texto'),
    redes.f_rep_col('contrato', 'Contrato', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('estado_desde', 'Estado desde', 'fecha_hora'),
    redes.f_rep_col('ubicacion', 'Ubicación', 'texto'), redes.f_rep_col('sector', 'Sector', 'entero'), redes.f_rep_col('subsector', 'Subsector', 'texto'),
    redes.f_rep_col('oculto', 'Oculto', 'si_no'), redes.f_rep_col('lat', 'Latitud', 'decimal', null, 6), redes.f_rep_col('lon', 'Longitud', 'decimal', null, 6))
  when 'bot' then jsonb_build_array(
    redes.f_rep_col('radicado', 'Radicado', 'texto'), redes.f_rep_col('recibido', 'Recibido', 'fecha_hora'), redes.f_rep_col('canal', 'Canal', 'texto'),
    redes.f_rep_col('tipo', 'Tipo', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('ultimo_movimiento', 'Último movimiento', 'fecha_hora'),
    redes.f_rep_col('dano', 'Daño', 'texto'), redes.f_rep_col('dano_estado', 'Estado del daño', 'texto'), redes.f_rep_col('fotos', 'Fotos', 'entero')) || ubic
  when 'sensibles' then jsonb_build_array(
    redes.f_rep_col('contrato', 'Contrato', 'texto'), redes.f_rep_col('tipo', 'Tipo', 'texto'), redes.f_rep_col('estado', 'Estado', 'texto'),
    redes.f_rep_col('desde', 'Desde', 'fecha_hora'), redes.f_rep_col('origen', 'Origen', 'texto'), redes.f_rep_col('sector', 'Sector', 'entero'))
  when 'activos' then jsonb_build_array(
    redes.f_rep_col('codigo', 'Código', 'texto'), redes.f_rep_col('tipo', 'Tipo', 'texto'), redes.f_rep_col('prefijo', 'Prefijo', 'texto'), redes.f_rep_col('sistema', 'Sistema', 'texto'),
    redes.f_rep_col('clase', 'Clase', 'texto'), redes.f_rep_col('material', 'Material', 'texto'), redes.f_rep_col('diametro_mm', 'Diámetro', 'decimal', 'mm', 1),
    redes.f_rep_col('longitud_m', 'Longitud', 'decimal', 'm', 2), redes.f_rep_col('profundidad_m', 'Profundidad', 'decimal', 'm', 2),
    redes.f_rep_col('instalacion', 'Instalación', 'fecha'), redes.f_rep_col('estado', 'Estado', 'texto'), redes.f_rep_col('retirado', 'Retirado', 'si_no'),
    redes.f_rep_col('oculto', 'Oculto', 'si_no'), redes.f_rep_col('codigo_anterior', 'Código anterior', 'texto')) || ubic
  end;
end $$;

-- 3. Encontrar o reportar activo (puntos LEV)
create function redes.f_rep_levantamientos(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $$
  with sg as (select redes.f_rep_sector_geom(p_f ->> 'sector') as g where p_f ? 'sector'),
  x as (select p.* from redes.v_levantar_punto p
         where p.registrado_en >= ((p_f ->> 'desde')::date::timestamp at time zone 'America/Bogota')
           and p.registrado_en < (((p_f ->> 'hasta')::date + 1)::timestamp at time zone 'America/Bogota') and p.registrado_en <= p_corte
           and (p_incl or p.estado <> 'descartado') and (not p_f ? 'sector' or ST_Intersects(p.geom, (select g from sg)))
           and (p_cursor is null or p.codigo > p_cursor)
         order by p.codigo limit p_limite)
  select x.codigo, case when p_solo_llave then null else jsonb_build_object('codigo', x.codigo, 'reportado', redes.f_rep_ts(x.registrado_en), 'servicio', redes.f_rep_rotulo(x.servicio),
           'tipo', case x.tipo when 'tuberia' then 'Tubería' when 'valvula' then 'Válvula' else redes.f_rep_rotulo(x.tipo) end,
           'area', case x.area when 'tecnica' then 'Técnica' else 'Comercial' end, 'estado', redes.f_rep_rotulo(x.estado), 'estado_desde', redes.f_rep_ts(x.estado_desde),
           'activo', (select a.codigo from redes.activos a where a.id = x.activo_id), 'fotos', x.fotos, 'precision_m', x.precision_m, 'precision_baja', x.precision_baja,
           'sector', (redes.f_sector_de(x.geom)).sector, 'lat', x.lat, 'lon', x.lon, 'reporto', x.autor) end
    from x order by x.codigo $$;

-- 4. Válvulas cerradas: una fila por cierre, con su apertura y los cambios de regreso.
create function redes.f_rep_valvulas(p_f jsonb, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $$
  with sg as (select redes.f_rep_sector_geom(p_f ->> 'sector') as g where p_f ? 'sector'),
  x as (select c.*, a.codigo as valvula, a.geom as vgeom from redes.valvula_maniobras c join redes.activo_vigente_mat a on a.activo_id = c.valvula_id
         where c.tipo = 'cerrar' and c.hecho_en >= ((p_f ->> 'desde')::date::timestamp at time zone 'America/Bogota')
           and c.hecho_en < (((p_f ->> 'hasta')::date + 1)::timestamp at time zone 'America/Bogota') and c.registrado_en <= p_corte
           and (not p_f ? 'sector' or ST_Intersects(a.geom, (select g from sg)))
           and (p_cursor is null or c.id > p_cursor::bigint)
         order by c.id limit p_limite)
  select lpad(x.id::text, 19, '0'),
         case when p_solo_llave then null else jsonb_build_object('valvula', x.valvula, 'cerrada', redes.f_rep_ts(x.hecho_en),
           'regreso_estimado', redes.f_rep_ts(coalesce((select r.regreso_estimado from redes.valvula_maniobras r where r.cierre_id = x.id and r.tipo = 'regreso' order by r.id desc limit 1), x.regreso_estimado)),
           'cambios_regreso', (select count(*) from redes.valvula_maniobras r where r.cierre_id = x.id and r.tipo = 'regreso'),
           'abierta', redes.f_rep_ts(ab.hecho_en), 'duracion_h', case when ab.hecho_en is not null then round(extract(epoch from ab.hecho_en - x.hecho_en) / 3600.0, 1) end,
           'estado', case when ab.id is null then 'Cerrada' else 'Abierta' end,
           'dano', (select d.codigo from redes.danos d where d.id = x.dano_id), 'intervencion', (select i.codigo from redes.intervenciones i where i.id = x.intervencion_id),
           'sector', (redes.f_sector_de(x.vgeom)).sector, 'lat', round(ST_Y(redes.f_rep_punto(x.vgeom))::numeric, 6), 'lon', round(ST_X(redes.f_rep_punto(x.vgeom))::numeric, 6),
           'cerro', x.autor, 'abrio', ab.autor) end
    from x left join lateral (select r.id, r.hecho_en, r.autor from redes.valvula_maniobras r where r.cierre_id = x.id and r.tipo = 'abrir' and r.registrado_en <= p_corte limit 1) ab on true
   order by x.id $$;

-- 5. Eventos de suspensión (todos los alcances). Contratos y sensibles como números. Sin la causa escrita (texto libre); sí el tipo y la causa de catálogo
--    del daño asociado (el del evento o el de su intervención) y el tipo de la intervención.
create function redes.f_rep_eventos(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language sql stable set search_path to 'redes', 'public', 'tecnica', 'extensions', 'pg_temp' as $$
  with sg as (select redes.f_rep_sector_geom(p_f ->> 'sector') as g where p_f ? 'sector'),
  x as (select e.* from redes.v_evento_suspension e
         where e.creado_en <= p_corte
           and e.desde < (((p_f ->> 'hasta')::date + 1)::timestamp at time zone 'America/Bogota')
           and coalesce(e.fin_en, 'infinity'::timestamptz) >= ((p_f ->> 'desde')::date::timestamp at time zone 'America/Bogota')
           and (p_incl or e.estado <> 'anulado') and (not p_f ? 'sector' or e.todo or ST_Intersects(e.geom, (select g from sg)))
           and (p_cursor is null or e.id > p_cursor::bigint)
         order by e.id limit p_limite)
  select lpad(x.id::text, 19, '0'),
         case when p_solo_llave then null else jsonb_build_object('evento', x.codigo,
           'alcance', case when x.planta_id is not null then 'Planta' when x.alcance = 'sectores' then 'Sectores' when x.alcance = 'circulo' then 'Círculo' else 'Toda la ciudad' end,
           'zona', x.zona_nombre, 'planta', (select pl.nombre from tecnica.plantas pl where pl.id = x.planta_id), 'estado', redes.f_rep_rotulo(x.estado),
           'desde', redes.f_rep_ts(x.desde), 'regreso_estimado_inicial', redes.f_rep_ts(x.regreso_estimado), 'regreso_estimado', redes.f_rep_ts(x.regreso_vigente),
           'cambios_regreso', (select count(*) from redes.evento_suspension_eventos z where z.evento_id = x.id and z.tipo = 'regreso'),
           'fin', redes.f_rep_ts(x.fin_en), 'duracion_h', case when x.fin_en is not null then round(extract(epoch from x.fin_en - x.desde) / 3600.0, 1) end,
           'contratos', x.contratos, 'sensibles', x.sensibles, 'reportes', r.n, 'reportes_bot', r.bot, 'reportes_116', r.l116, 'reportes_danos', r.dano, 'reportes_campo', r.campo,
           'dano', cat.dano, 'tipo', cat.tipo, 'causa', cat.causa, 'intervencion', cat.intervencion, 'tipo_intervencion', cat.tipo_intervencion,
           'declaro', x.autor, 'cerro', x.fin_autor) end
    from x
    left join lateral (select case when x.dano_id is not null then d.codigo end as dano, td.nombre as tipo, i.codigo as intervencion, ti.nombre as tipo_intervencion,
                              case d.causa_clase when 'propia' then coalesce(ca.nombre, 'Propia') when 'terceros' then 'Terceros' || coalesce(': ' || tt.nombre, '')
                                                 when 'desconocida' then 'Desconocida' end as causa
                         from (select 1) u
                         left join redes.intervenciones i on i.id = x.intervencion_id
                         left join redes.tipos_intervencion ti on ti.codigo = i.tipo_codigo
                         left join redes.danos d on d.id = coalesce(x.dano_id, i.dano_id)
                         left join redes.tipos_dano td on td.codigo = d.tipo_codigo
                         left join redes.causas ca on ca.codigo = d.causa_codigo
                         left join redes.tipos_tercero tt on tt.codigo = d.tercero_tipo) cat on not p_solo_llave
    cross join lateral (select count(*) as n, count(*) filter (where v.origen = 'bot') as bot, count(*) filter (where v.origen = 'l116') as l116,
                                      count(*) filter (where v.origen = 'dano') as dano, count(*) filter (where v.origen = 'campo') as campo
                                 from redes.f_evento_reportes(x.id) v) r
   order by x.id $$;

-- 6. Línea 116 (lo vigente de cada reporte cargado)
create function redes.f_rep_l116(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $$
  select lpad(v.reporte_id::text, 19, '0'),
         case when p_solo_llave then null else jsonb_build_object('reporte', v.reporte, 'registrado_116', redes.f_rep_ts(v.fecha_registro), 'dia', v.dia, 'servicio', v.servicio, 'causal', v.causal, 'comuna', r.comuna,
           'contrato', v.contrato, 'estado', redes.f_rep_rotulo(v.estado), 'estado_desde', redes.f_rep_ts(v.estado_desde),
           'ubicacion', case v.metodo when 'contrato' then 'Por contrato' else 'Sin ubicar' end, 'sector', v.sector, 'subsector', v.subsector, 'oculto', v.oculto,
           'lat', round(ST_Y(v.geom)::numeric, 6), 'lon', round(ST_X(v.geom)::numeric, 6)) end
    from redes.l116_vigente v join redes.l116_reportes r on r.id = v.reporte_id
   where v.dia between (p_f ->> 'desde')::date and (p_f ->> 'hasta')::date and r.creado_en <= p_corte
     and (p_incl or not v.oculto) and (not p_f ? 'sector' or ST_Intersects(v.geom, (select redes.f_rep_sector_geom(p_f ->> 'sector'))))
     and (p_cursor is null or v.reporte_id > p_cursor::bigint)
   order by v.reporte_id limit p_limite $$;

-- 7. Reportes del bot (sin la descripción ni la dirección que escribió el ciudadano)
create function redes.f_rep_bot(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $$
  with sg as (select redes.f_rep_sector_geom(p_f ->> 'sector') as g where p_f ? 'sector'),
  x as (select b.*, to_char(b.recibido_en at time zone 'UTC', 'YYYYMMDDHH24MISSUS') || '|' || b.id::text as kk from redes.v_reporte_externo b
         where b.recibido_en >= ((p_f ->> 'desde')::date::timestamp at time zone 'America/Bogota')
           and b.recibido_en < (((p_f ->> 'hasta')::date + 1)::timestamp at time zone 'America/Bogota') and b.registrado_en <= p_corte
           and (p_incl or b.estado_bot <> 'descartado') and (not p_f ? 'sector' or ST_Intersects(b.geom, (select g from sg)))
           and (p_cursor is null or b.recibido_en >= (to_timestamp(left(p_cursor, 14), 'YYYYMMDDHH24MISS') at time zone 'UTC'))
       ),
  y as (select * from x where p_cursor is null or x.kk > p_cursor order by x.kk limit p_limite)
  select y.kk, case when p_solo_llave then null else jsonb_build_object('radicado', y.radicado, 'recibido', redes.f_rep_ts(y.recibido_en), 'canal', y.canal, 'tipo', y.tipo_bot, 'estado', redes.f_rep_rotulo(y.estado_bot),
           'ultimo_movimiento', redes.f_rep_ts((select max(e.creado_en) from redes.reporte_externo_eventos e where e.reporte_id = y.id)),
           'dano', y.dano_codigo, 'dano_estado', redes.f_rep_rotulo(y.dano_estado), 'fotos', y.fotos,
           'sector', (redes.f_sector_de(y.geom)).sector, 'lat', y.lat, 'lon', y.lon) end
    from y order by y.kk $$;

-- 8. Usuarios sensibles (inventario a hoy; sin teléfono, sin nombre y sin la palabra del nombre que lo marcó)
create function redes.f_rep_sensibles(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $$
  with x as (select s.* from redes.v_usuario_sensible s join redes.usuarios_sensibles u on u.contrato = s.contrato
              where u.creado_en <= p_corte and (p_incl or s.estado <> 'descartado') and (not p_f ? 'tipo' or s.tipo = p_f ->> 'tipo')
                and (p_cursor is null or s.contrato > p_cursor)
              order by s.contrato limit p_limite)
  select x.contrato, case when p_solo_llave then null else jsonb_build_object('contrato', x.contrato, 'tipo', coalesce((select t.nombre from redes.tipos_sensible t where t.codigo = x.tipo), x.tipo),
           'estado', redes.f_rep_rotulo(x.estado), 'desde', redes.f_rep_ts(x.desde), 'origen', case x.origen when 'nombre' then 'Por el nombre' else 'Manual' end,
           'sector', (select (redes.f_sector_de(a.geom)).sector from redes.contrato_tramo ct join redes.activo_vigente_mat a on a.activo_id = ct.activo_id where ct.contrato = x.contrato limit 1)) end
    from x order by x.contrato $$;

-- 9. Activos de la red (inventario a hoy; retirados y ocultos solo con «Incluir ocultos»)
create function redes.f_rep_activos(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $$
  with x as (select a.* from redes.activo_vigente_mat a
              where (p_incl or not (a.retirado or a.oculto)) and (not p_f ? 'tipo' or a.prefijo = p_f ->> 'tipo') and (not p_f ? 'sistema' or a.sistema = p_f ->> 'sistema')
                and (p_cursor is null or a.activo_id > p_cursor::bigint)
              order by a.activo_id limit p_limite)
  select lpad(x.activo_id::text, 19, '0'),
         case when p_solo_llave then null else jsonb_build_object('codigo', x.codigo, 'tipo', t.nombre_visible, 'prefijo', x.prefijo, 'sistema', redes.f_rep_rotulo(x.sistema),
           'clase', coalesce((select c.nombre from redes.clases_activo c where c.prefijo = x.prefijo and c.codigo = x.clase), x.clase),
           'material', coalesce((select m.nombre from redes.materiales m where m.codigo = x.material_codigo), x.material_codigo),
           'diametro_mm', x.diametro_mm, 'longitud_m', round(x.longitud_m, 2), 'profundidad_m', x.profundidad_m, 'instalacion', x.fecha_instalacion,
           'estado', coalesce((select e.nombre from redes.estados_activo e where e.codigo = x.estado_codigo), x.estado_codigo), 'retirado', x.retirado, 'oculto', x.oculto,
           'codigo_anterior', x.codigo_anterior, 'sector', (redes.f_sector_de(x.geom)).sector,
           'lat', round(ST_Y(redes.f_rep_punto(x.geom))::numeric, 6), 'lon', round(ST_X(redes.f_rep_punto(x.geom))::numeric, 6)) end
    from x left join redes.v_tipo_visible t on t.prefijo = x.prefijo
   order by x.activo_id $$;

create function redes.f_rep_filas(p_reporte text, p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language plpgsql stable set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
begin
  case p_reporte
  when 'levantamientos' then return query select * from redes.f_rep_levantamientos(p_f, p_incl, p_corte, p_cursor, p_limite, p_solo_llave);
  when 'valvulas' then return query select * from redes.f_rep_valvulas(p_f, p_corte, p_cursor, p_limite, p_solo_llave);
  when 'eventos' then return query select * from redes.f_rep_eventos(p_f, p_incl, p_corte, p_cursor, p_limite, p_solo_llave);
  when 'l116' then return query select * from redes.f_rep_l116(p_f, p_incl, p_corte, p_cursor, p_limite, p_solo_llave);
  when 'bot' then return query select * from redes.f_rep_bot(p_f, p_incl, p_corte, p_cursor, p_limite, p_solo_llave);
  when 'sensibles' then return query select * from redes.f_rep_sensibles(p_f, p_incl, p_corte, p_cursor, p_limite, p_solo_llave);
  when 'activos' then return query select * from redes.f_rep_activos(p_f, p_incl, p_corte, p_cursor, p_limite, p_solo_llave);
  else perform tecnica.f_error('Ese reporte no existe.');
  end case;
end $$;

-- Cuántas filas (sin armar las filas: lo mismo que f_rep_filas, contado)
create function redes.f_rep_contar(p_reporte text, p_f jsonb, p_incl boolean, p_corte timestamptz) returns bigint
language sql stable set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
  select count(*) from redes.f_rep_filas(p_reporte, p_f, p_incl, p_corte, null, null, true) $$;

create function redes.f_rep_leame(p_reporte text, p_f jsonb, p_incl boolean, p_email text, p_corte timestamptz) returns jsonb
language plpgsql stable set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare c record; v_trae text[]; v_no text[] := array['Textos libres (descripciones, observaciones, motivos y causas escritas): pueden traer datos de personas y se ven solo en pantalla.',
                                                       'Teléfonos y nombres de suscriptores, del ciudadano que reporta o de terceros.'];
  v_filtros text[] := '{}'; v_ex text;
begin
  select * into c from redes.f_rep_catalogo() x where x.clave = p_reporte;
  v_trae := case p_reporte
    when 'levantamientos' then array['Una fila por punto de «Encontrar o reportar activo» (código LEV), con su estado vigente, el activo creado si se levantó y su ubicación.']
    when 'valvulas' then array['Una fila por cierre de una válvula, con el regreso estimado vigente, la apertura y la duración. Una válvula que sigue cerrada no tiene apertura.']
    when 'eventos' then array['Una fila por evento de suspensión vigente algún momento del periodo: zona, desde cuándo, regreso estimado (al declarar y el vigente), fin y duración.',
                              'Contratos y usuarios sensibles afectados como números (los que se calcularon al declarar) y los reportes asociados hoy, por origen.',
                              'El tipo de daño o falla y la causa del daño salen del catálogo del daño asociado (el del evento o el de su intervención); vacíos si el evento no tiene daño.']
    when 'l116' then array['Una fila por reporte de la línea 116 cargado, con su estado vigente, el contrato y la ubicación (por contrato o sin ubicar).']
    when 'bot' then array['Una fila por reporte recibido del bot, con su estado y el daño en que se convirtió, si se convirtió.']
    when 'sensibles' then array['Una fila por contrato marcado como usuario sensible, con su tipo y estado de hoy (inventario a la fecha de la descarga).']
    when 'activos' then array['Una fila por activo de la red tal como está hoy (inventario a la fecha de la descarga), con un punto del activo para ubicarlo.']
  end;
  if p_reporte = 'bot' then v_no := v_no || array['La descripción y la dirección que escribió el ciudadano.']; end if;
  if p_reporte = 'sensibles' then v_no := v_no || array['El nombre del suscriptor ni la palabra del nombre que lo marcó.']; end if;
  if p_reporte = 'eventos' then v_no := v_no || array['La causa escrita al declarar el evento ni los motivos de cierre o anulación (texto libre).']; end if;
  if c.periodo then
    v_filtros := array['Periodo: ' || to_char((p_f ->> 'desde')::date, 'DD/MM/YYYY') || ' a ' || to_char((p_f ->> 'hasta')::date, 'DD/MM/YYYY') || ' (según ' || c.periodo_sobre || ')'];
  else
    v_filtros := array['Inventario al ' || to_char(p_corte at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI')];
  end if;
  if p_f ? 'sector' then v_filtros := v_filtros || ('Sector: ' || (p_f ->> 'sector_nombre') || ' (' || (p_f ->> 'sector') || ')'); end if;
  if p_f ? 'tipo' then v_filtros := v_filtros || ('Tipo: ' || (p_f ->> 'tipo_nombre')); end if;
  if p_f ? 'sistema' then v_filtros := v_filtros || ('Sistema: ' || redes.f_rep_rotulo(p_f ->> 'sistema')); end if;
  v_ex := case when not c.usa_ocultos then null
               when p_reporte in ('levantamientos', 'bot', 'sensibles') then case when p_incl then 'Descartados: incluidos' else 'Descartados: no incluidos' end
               when p_reporte = 'eventos' then case when p_incl then 'Eventos anulados: incluidos' else 'Eventos anulados: no incluidos' end
               when p_reporte = 'activos' then case when p_incl then 'Retirados y ocultos: incluidos' else 'Retirados y ocultos: no incluidos' end
               else case when p_incl then 'Ocultos: incluidos' else 'Ocultos: no incluidos' end end;
  if v_ex is not null then v_filtros := v_filtros || v_ex; end if;
  return jsonb_build_object('que_trae', to_jsonb(v_trae), 'que_no_trae', to_jsonb(v_no), 'filtros', to_jsonb(v_filtros),
                            'generado_por', p_email, 'generado_en', redes.f_rep_ts(p_corte));
end $$;
-- =====================================================================
-- 26 — RPC de las descargas de Distribución (solo supervisor de distribución y administrador: redes.f_supervisor). Solo service_role las ejecuta (la Edge).
--   iniciar → valida, cuenta, guarda la descarga (filtros y el instante de la foto) y la deja en la auditoría;
--   pagina  → hasta 5.000 filas con los filtros GUARDADOS, solo lo que existía al iniciar; vence a las 2 horas y no sirve a otra persona;
--   cerrar  → guarda el cierre (una vez) y lo deja en la auditoría;
--   sectores → la lista del filtro de sector: los sectores y subsectores de la capa (código, nombre, clase, número de sector y subsector). No se audita.
-- =====================================================================
create function public.geoportal_redes_reporte_iniciar(p_solicitante text, p_reporte text, p_filtros jsonb default '{}'::jsonb, p_formato text default 'xlsx',
                                                       p_incluir_excluidos boolean default false, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'descargan los datos de distribución'); v_rep text := lower(btrim(coalesce(p_reporte, '')));
  v_formato text := lower(btrim(coalesce(p_formato, ''))); c record; v_f jsonb; v_incl boolean; v_corte timestamptz := clock_timestamp(); v_total bigint;
  v_max integer := redes.f_rep_max_filas(); v_id bigint;
begin
  select * into c from redes.f_rep_catalogo() x where x.clave = v_rep;
  if not found then perform tecnica.f_error('Ese reporte no existe.'); end if;
  if v_formato not in ('csv', 'xlsx') then perform tecnica.f_error('El formato debe ser Excel o CSV.'); end if;
  v_f := redes.f_rep_filtros(v_rep, p_filtros);
  v_incl := coalesce(p_incluir_excluidos, false) and c.usa_ocultos;
  v_total := redes.f_rep_contar(v_rep, v_f, v_incl, v_corte);
  if v_total = 0 then perform tecnica.f_error('No hay datos con esos filtros.', 'P0002'); end if;
  if v_total > v_max then
    perform tecnica.f_error('La descarga supera el máximo de ' || replace(to_char(v_max, 'FM999G999'), ',', '.') || ' filas (hay '
                            || replace(to_char(v_total, 'FM999G999G999'), ',', '.') || '). Acote el periodo o los filtros.');
  end if;
  insert into redes.reporte_descargas (email, reporte, filtros, incluir, formato, total, corte_en, ip)
  values (v_email, v_rep, v_f, v_incl, v_formato, v_total, v_corte, p_ip) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'redes_reporte_iniciar', v_id::text,
                            jsonb_build_object('reporte', v_rep, 'filtros', v_f, 'incluir_ocultos', v_incl, 'formato', v_formato, 'filas', v_total), p_ip);
  return jsonb_build_object('descarga_id', v_id, 'reporte', v_rep, 'titulo', c.titulo,
                            'archivo', 'distribucion_' || v_rep || coalesce('_' || (v_f ->> 'desde') || '_a_' || (v_f ->> 'hasta'), '_' || to_char(v_corte at time zone 'America/Bogota', 'YYYY-MM-DD')),
                            'total', v_total, 'max', v_max, 'formato', v_formato, 'incluir_excluidos', v_incl, 'filtros', v_f - 'tipo_nombre' - 'sector_nombre',
                            'columnas', redes.f_rep_columnas(v_rep), 'leame', redes.f_rep_leame(v_rep, v_f, v_incl, v_email, v_corte));
end $$;

create function public.geoportal_redes_reporte_pagina(p_solicitante text, p_descarga_id bigint, p_cursor text default null, p_limite integer default 5000) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'descargan los datos de distribución'); d redes.reporte_descargas;
  v_lim integer := least(greatest(coalesce(p_limite, 5000), 1), 5000); v_plantilla jsonb; v_filas jsonb; v_n integer; v_ultimo text;
begin
  select * into d from redes.reporte_descargas x where x.id = p_descarga_id;
  if not found or d.email <> v_email then perform tecnica.f_error('La descarga no existe.', 'P0002'); end if;
  if exists (select 1 from redes.reporte_descarga_cierres c where c.descarga_id = d.id) then perform tecnica.f_error('La descarga ya terminó. Vuelva a iniciarla.', '55000'); end if;
  if d.creado_en < clock_timestamp() - interval '2 hours' then perform tecnica.f_error('La descarga venció. Vuelva a iniciarla.', '55000'); end if;
  if p_cursor is not null and (length(p_cursor) > 200 or p_cursor !~ '^[0-9A-Za-z_|-]+$') then perform tecnica.f_error('La página pedida no es válida.'); end if;
  select jsonb_object_agg(x ->> 'clave', 'null'::jsonb) into v_plantilla from jsonb_array_elements(redes.f_rep_columnas(d.reporte)) x;
  select coalesce(jsonb_agg(v_plantilla || r.fila order by r.k), '[]'::jsonb), count(*), max(r.k) into v_filas, v_n, v_ultimo
    from redes.f_rep_filas(d.reporte, d.filtros, d.incluir, d.corte_en, p_cursor, v_lim) r;
  return jsonb_build_object('filas', v_filas, 'devueltos', v_n, 'cursor', case when v_n = v_lim then v_ultimo end);
end $$;

create function public.geoportal_redes_reporte_cerrar(p_solicitante text, p_descarga_id bigint, p_filas integer default 0, p_resultado text default 'completa', p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'descargan los datos de distribución'); v_res text := lower(btrim(coalesce(p_resultado, ''))); d redes.reporte_descargas; v_n integer;
begin
  if v_res not in ('completa', 'cancelada', 'error') then perform tecnica.f_error('Resultado de descarga no válido.'); end if;
  if p_filas is null or p_filas < 0 then perform tecnica.f_error('El número de filas no es válido.'); end if;
  select * into d from redes.reporte_descargas x where x.id = p_descarga_id;
  if not found or d.email <> v_email then perform tecnica.f_error('La descarga no existe.', 'P0002'); end if;
  insert into redes.reporte_descarga_cierres (descarga_id, filas, resultado, ip) values (d.id, p_filas, v_res, p_ip) on conflict (descarga_id) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('descarga_id', d.id, 'cerrada', true, 'repetida', true); end if;
  perform tecnica.f_auditar(v_email, 'redes_reporte_cerrar', d.id::text, jsonb_build_object('reporte', d.reporte, 'filas_entregadas', p_filas, 'resultado', v_res), p_ip);
  return jsonb_build_object('descarga_id', d.id, 'cerrada', true, 'repetida', false);
end $$;

create function public.geoportal_redes_reporte_sectores(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'descargan los datos de distribución');
begin
  return jsonb_build_object('sectores', coalesce((select jsonb_agg(jsonb_build_object('codigo', s.codigo, 'nombre', s.nombre, 'clase', s.clase, 'sector', s.sector, 'subsector', s.subsector)
                                                     order by s.sector nulls last, s.clase = 'subsector', s.subsector nulls first, s.nombre, s.codigo)
                                                    from redes.f_rep_sectores() s), '[]'::jsonb));
end $$;
-- =====================================================================
-- 40 — PERMISOS: todo lo nuevo sin permisos para nadie; las 4 RPC solo para service_role (la Edge). Por NOMBRE EXACTO, nunca por patrón:
--      «geoportal_redes_reporte_%» también abarca las publicadas reporte_convertir y reporte_descartar, que no se tocan.
-- =====================================================================
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where (p.pronamespace = 'redes'::regnamespace and p.proname = any (array['f_rep_catalogo', 'f_rep_max_filas', 'f_rep_ts', 'f_rep_col', 'f_rep_rotulo', 'f_rep_sector_geom', 'f_rep_sectores', 'f_rep_punto', 'f_rep_filtros', 'f_rep_columnas', 'f_rep_levantamientos', 'f_rep_valvulas', 'f_rep_eventos', 'f_rep_l116', 'f_rep_bot', 'f_rep_sensibles', 'f_rep_activos', 'f_rep_filas', 'f_rep_contar', 'f_rep_leame']))
               or (p.pronamespace = 'public'::regnamespace and p.proname = any (array['geoportal_redes_reporte_iniciar', 'geoportal_redes_reporte_pagina', 'geoportal_redes_reporte_cerrar', 'geoportal_redes_reporte_sectores']))
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end $$;
grant execute on function public.geoportal_redes_reporte_iniciar(text, text, jsonb, text, boolean, text) to service_role;
grant execute on function public.geoportal_redes_reporte_pagina(text, bigint, text, integer) to service_role;
grant execute on function public.geoportal_redes_reporte_cerrar(text, bigint, integer, text, text) to service_role;
grant execute on function public.geoportal_redes_reporte_sectores(text) to service_role;
notify pgrst, 'reload schema';
-- =====================================================================
-- TÉCNICA · FASE 1 · DESCARGAS DE DISTRIBUCIÓN · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- Todo es SIMULADO y se deshace: sus personas (prueba.rep.*), una red de prueba ZTREP en un rincón de la caja (2 sectores, 2 válvulas, 1 tramo), puntos LEV,
-- maniobras de válvula, eventos declarados con la RPC publicada del Corte 15, reportes de la 116 y del bot, y usuarios sensibles con contratos de prueba.
-- Los textos libres de prueba llevan un nombre y un teléfono inventados («ZTREP Pedro Prueba 3009990000») para comprobar que NO salen.
-- Mide con el volumen real: «Activos de la red» completo (iniciar y la primera página de 5.000).
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · descargas de Distribución … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.1300 + y * 0.0000090437, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.5800 + x * 0.0000091290, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.caja(x1 numeric, y1 numeric, x2 numeric, y2 numeric) returns geometry language sql as $$
  select ST_Multi(ST_MakeEnvelope(pg_temp.lon(x1), pg_temp.lat(y1), pg_temp.lon(x2), pg_temp.lat(y2), 4326)) $$;
create temp table _zt (nombre text primary key, activo_id bigint, codigo text);
create function pg_temp.activo(p_nombre text, p_prefijo text, p_geom geometry, p_clase text default null, p_atributos jsonb default '{}') returns text language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.rep.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, 'carga', q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, material_codigo, diametro_mm, estado_codigo, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZTREP ' || p_nombre, p_clase, case when p_prefijo = 'RED' then (select codigo from redes.materiales order by orden limit 1) end,
          case when p_prefijo = 'RED' then 110 end, 'en_operacion', p_atributos, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZTREP activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  insert into _zt values (p_nombre, v_id, v_cod);
  return v_cod;
end $$;
create function pg_temp.id(p_nombre text) returns bigint language sql as $$ select activo_id from _zt where nombre = p_nombre $$;
create function pg_temp.cod(p_nombre text) returns text language sql as $$ select codigo from _zt where nombre = p_nombre $$;
create function pg_temp.claves(j jsonb) returns text language sql as $$ select string_agg(k, ',' order by k) from jsonb_object_keys(j) k $$;
create function pg_temp.cols(p_rep text) returns text language sql as $$ select string_agg(x ->> 'clave', ',' order by x ->> 'clave') from jsonb_array_elements(redes.f_rep_columnas(p_rep)) x $$;
-- todas las filas de una descarga, página por página (con p_lim por página); devuelve el arreglo completo
create function pg_temp.todas(p_quien text, p_id bigint, p_lim integer default 5000) returns jsonb language plpgsql as $$
declare v_c text; v_r jsonb; v_todas jsonb := '[]'; i integer := 0;
begin
  loop
    v_r := public.geoportal_redes_reporte_pagina(p_quien, p_id, v_c, p_lim);
    v_todas := v_todas || (v_r -> 'filas'); v_c := v_r ->> 'cursor'; i := i + 1;
    exit when v_c is null or i > 2000;
  end loop;
  return v_todas;
end $$;
-- iniciar y traer todo; devuelve {ini, filas}
create function pg_temp.bajar(p_quien text, p_rep text, p_f jsonb, p_incl boolean default false, p_lim integer default 5000) returns jsonb language plpgsql as $$
declare v_i jsonb;
begin
  v_i := public.geoportal_redes_reporte_iniciar(p_quien, p_rep, p_f, 'xlsx', p_incl, '10.0.0.1');
  return jsonb_build_object('ini', v_i, 'filas', pg_temp.todas(p_quien, (v_i ->> 'descarga_id')::bigint, p_lim));
end $$;
-- solo las filas de PRUEBA (la base real puede tener filas en el mismo sector o del mismo tipo: los conteos se hacen sobre las de prueba)
create function pg_temp.de_prueba(p_filas jsonb, p_clave text, p_patron text) returns jsonb language sql as $$
  select coalesce(jsonb_agg(f), '[]'::jsonb) from jsonb_array_elements(p_filas) f where f ->> p_clave like p_patron $$;
create function pg_temp.hay(p_filas jsonb, p_clave text, p_valor text) returns boolean language sql as $$
  select exists (select 1 from jsonb_array_elements(p_filas) f where f ->> p_clave = p_valor) $$;

do $prueba$
declare
  adm text := 'prueba.rep.adm@emdupar.gov.co'; sd text := 'prueba.rep.sd@emdupar.gov.co'; sd2 text := 'prueba.rep.sd2@emdupar.gov.co'; sp text := 'prueba.rep.sp@emdupar.gov.co';
  op text := 'prueba.rep.op@emdupar.gov.co'; ex text := 'prueba.rep.explorar@emdupar.gov.co';
  libre text := 'ZTREP Pedro Prueba 3009990000';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; per jsonb; j jsonb; j2 jsonb; f jsonb; v_id bigint; v_id2 bigint; v_n integer; v_m integer; v_txt text;
  v_carga bigint; v_lev1 uuid := gen_random_uuid(); v_lev2 uuid := gen_random_uuid(); v_lev3 uuid := gen_random_uuid(); v_c1 bigint; v_c2 bigint; v_rep uuid; v_rep2 uuid;
  e1 text; e2 text; e3 text; v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_info text; v_total integer; v_bien integer; v_fallas text; v_aud integer;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTREP Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZTREP Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd2, 'ZTREP Otro supervisor', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZTREP Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZTREP Operador', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_explorar, horario, dias) values (ex, 'ZTREP Explorar', 'consulta', true, 'sin_restriccion', 'todos');
  per := jsonb_build_object('desde', (hoy - 30)::text, 'hasta', hoy::text);

  -- ---------- la red de prueba: sector 97 (con un subsector) y sector 98, una válvula en cada uno y un tramo ----------
  perform pg_temp.activo('S97', 'SEC', pg_temp.caja(0, -50, 400, 250), 'sector', '{"modelo": {"sector": 97}}');
  perform pg_temp.activo('S97A', 'SEC', pg_temp.caja(0, -50, 200, 250), 'subsector', '{"modelo": {"sector": 97, "subsector": "97A"}}');
  perform pg_temp.activo('S98', 'SEC', pg_temp.caja(500, -50, 900, 250), 'sector', '{"modelo": {"sector": 98}}');
  perform pg_temp.activo('V1', 'VAL', pg_temp.pt(100, 100), 'compuerta');
  perform pg_temp.activo('V2', 'VAL', pg_temp.pt(700, 100), 'compuerta');
  perform pg_temp.activo('T1', 'RED', ST_MakeLine(pg_temp.pt(50, 0), pg_temp.pt(350, 0)));

  -- ---------- 01. Quién entra ----------
  perform pg_temp.reg('01.01 el supervisor de distribución inicia una descarga (Activos de la red, tipo VAL)',
    (public.geoportal_redes_reporte_iniciar(sd, 'activos', '{"tipo": "VAL"}', 'xlsx', false, null) ->> 'total')::integer = (select count(*) from redes.activo_vigente_mat where prefijo = 'VAL' and not retirado and not oculto));
  perform pg_temp.reg('01.02 el administrador también', (public.geoportal_redes_reporte_iniciar(adm, 'activos', '{"tipo": "SEC"}', 'csv', false, null) ->> 'total')::integer >= 3);
  perform pg_temp.err('01.03 el supervisor de planta no (403)', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L, %L)', sp, 'activos', '{}', 'xlsx'), '42501');
  perform pg_temp.err('01.04 el operador no (403)', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L, %L)', op, 'activos', '{}', 'xlsx'), '42501');
  perform pg_temp.err('01.05 alguien sin Técnica no (403)', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L, %L)', ex, 'activos', '{}', 'xlsx'), '42501');
  perform pg_temp.err('01.06 ni página ni cierre para el supervisor de planta (403)', format('select public.geoportal_redes_reporte_pagina(%L, 1)', sp), '42501');

  -- ---------- 02. Lo que se rechaza ----------
  perform pg_temp.err('02.01 un reporte que no existe', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'danos', per), null, 'Ese reporte no existe');
  perform pg_temp.err('02.02 un formato que no es Excel ni CSV', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L, %L)', sd, 'eventos', per, 'pdf'), null, 'Excel o CSV');
  perform pg_temp.err('02.03 un filtro que no aplica al reporte', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'eventos', per || '{"tipo": "VAL"}'), null, 'no aplica');
  perform pg_temp.err('02.04 sin periodo en un reporte con periodo', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'l116', '{}'), null, 'Elija el periodo');
  perform pg_temp.err('02.05 más de un año', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'l116', jsonb_build_object('desde', (hoy - 366)::text, 'hasta', hoy::text)), null, 'hasta de un año');
  perform pg_temp.err('02.06 desde después de hasta', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'l116', jsonb_build_object('desde', hoy::text, 'hasta', (hoy - 1)::text)), null, 'posterior');
  perform pg_temp.err('02.07 un sector escrito como número ya no vale: se elige de la lista', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'l116', per || '{"sector": "99"}'), null, 'de la lista');
  perform pg_temp.err('02.07b un código de sector que no está en la capa', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'l116', per || '{"sector": "SEC-999999999"}'), null, 'capa de sectores');
  perform pg_temp.err('02.08 un tipo de activo que no existe', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'activos', '{"tipo": "XYZ"}'), null, 'tipo de activo');
  perform pg_temp.err('02.09 sin datos con esos filtros: 404', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'valvulas', jsonb_build_object('desde', '2001-01-01', 'hasta', '2001-01-31')), 'P0002', 'No hay datos');
  perform pg_temp.reg('02.10 un año exacto (366 días con los dos extremos) sí se acepta', (redes.f_rep_filtros('l116', jsonb_build_object('desde', (hoy - 365)::text, 'hasta', hoy::text)) ->> 'desde') = (hoy - 365)::text);

  -- ---------- 03. Encontrar o reportar activo ----------
  insert into redes.levantar_puntos (id, codigo, servicio, tipo, observacion, lat, lon, geom, precision_m, precision_baja, area, autor, registrado_en) values
    (v_lev1, 'LEV-9' || lpad('1', 5, '0'), 'acueducto', 'valvula', libre, pg_temp.lat(100), pg_temp.lon(150), pg_temp.pt(150, 100), 4, false, 'tecnica', op, clock_timestamp() - interval '2 days'),
    (v_lev2, 'LEV-9' || lpad('2', 5, '0'), 'alcantarillado', 'pozo', null, pg_temp.lat(100), pg_temp.lon(700), pg_temp.pt(700, 100), 30, true, 'comercial', op, clock_timestamp() - interval '1 day'),
    (v_lev3, 'LEV-9' || lpad('3', 5, '0'), 'acueducto', 'otro', libre, pg_temp.lat(100), pg_temp.lon(160), pg_temp.pt(160, 100), 5, false, 'tecnica', op, clock_timestamp() - interval '3 hours');
  insert into redes.levantar_eventos (punto_id, tipo, activo_id, autor) values (v_lev1, 'levantado', pg_temp.id('V1'), sd);
  insert into redes.levantar_eventos (punto_id, tipo, motivo, autor) values (v_lev3, 'descartado', libre, sd);
  j := pg_temp.bajar(sd, 'levantamientos', per);
  perform pg_temp.reg('03.01 los LEV del periodo sin los descartados; el levantado trae el código del activo; columnas = claves de cada fila',
    pg_temp.hay(j -> 'filas', 'codigo', 'LEV-900001') and pg_temp.hay(j -> 'filas', 'codigo', 'LEV-900002') and not pg_temp.hay(j -> 'filas', 'codigo', 'LEV-900003')
    and pg_temp.hay(j -> 'filas', 'activo', pg_temp.cod('V1')) and pg_temp.hay(j -> 'filas', 'estado', 'Levantado')
    and pg_temp.claves(j -> 'filas' -> 0) = pg_temp.cols('levantamientos') and pg_temp.claves(j -> 'filas' -> 0) = (select string_agg(x ->> 'clave', ',' order by x ->> 'clave') from jsonb_array_elements(j -> 'ini' -> 'columnas') x),
    left((j -> 'filas')::text, 300));
  j := pg_temp.bajar(sd, 'levantamientos', per || jsonb_build_object('sector', pg_temp.cod('S97')), true);
  perform pg_temp.reg('03.02 por sector 97 y con «Incluir ocultos»: los dos del sector 97 (el descartado también), con su número de sector; el del 98 no',
    jsonb_array_length(pg_temp.de_prueba(j -> 'filas', 'codigo', 'LEV-9000__')) = 2 and pg_temp.hay(j -> 'filas', 'codigo', 'LEV-900003') and pg_temp.hay(pg_temp.de_prueba(j -> 'filas', 'codigo', 'LEV-9000__'), 'estado', 'Descartado')
    and not pg_temp.hay(j -> 'filas', 'codigo', 'LEV-900002') and (select bool_and((x ->> 'sector')::integer = 97) from jsonb_array_elements(pg_temp.de_prueba(j -> 'filas', 'codigo', 'LEV-9000__')) x), (j -> 'filas')::text);
  perform pg_temp.reg('03.03 la observación y el motivo (texto libre) no salen', position('Pedro' in (j)::text) = 0);
  j := pg_temp.bajar(sd, 'levantamientos', per || jsonb_build_object('sector', lower(pg_temp.cod('S97A'))), true);
  perform pg_temp.reg('03.04 por subsector (S97A, el código en minúsculas también vale): los dos que caen en él; el Léame dice el nombre y el código del sector',
    jsonb_array_length(pg_temp.de_prueba(j -> 'filas', 'codigo', 'LEV-9000__')) = 2 and j -> 'ini' -> 'filtros' ->> 'sector' = pg_temp.cod('S97A') and not (j -> 'ini' -> 'filtros') ? 'sector_nombre'
    and (j -> 'ini' -> 'leame' -> 'filtros')::text like '%Sector: ZTREP S97A (' || pg_temp.cod('S97A') || ')%', (j -> 'ini')::text);

  -- ---------- 04. Válvulas cerradas ----------
  insert into redes.valvula_maniobras (valvula_id, tipo, motivo, regreso_estimado, hecho_en, autor) values (pg_temp.id('V1'), 'cerrar', libre, clock_timestamp() - interval '1 day', clock_timestamp() - interval '2 days', sd) returning id into v_c1;
  insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, regreso_estimado, hecho_en, autor) values (pg_temp.id('V1'), 'regreso', v_c1, clock_timestamp() - interval '20 hours', clock_timestamp() - interval '30 hours', sd);
  insert into redes.valvula_maniobras (valvula_id, tipo, cierre_id, hecho_en, autor) values (pg_temp.id('V1'), 'abrir', v_c1, clock_timestamp() - interval '2 days' + interval '30 hours', sd2);
  insert into redes.valvula_maniobras (valvula_id, tipo, motivo, hecho_en, autor) values (pg_temp.id('V2'), 'cerrar', libre, clock_timestamp() - interval '5 hours', sd) returning id into v_c2;
  j := pg_temp.bajar(sd, 'valvulas', per);
  select x into f from jsonb_array_elements(j -> 'filas') x where x ->> 'valvula' = pg_temp.cod('V1');
  perform pg_temp.reg('04.01 un cierre con su cambio de regreso y su apertura: Abierta, 30 h, 1 cambio, quién cerró y quién abrió',
    f ->> 'estado' = 'Abierta' and (f ->> 'duracion_h')::numeric = 30.0 and (f ->> 'cambios_regreso')::integer = 1 and f ->> 'cerro' = sd and f ->> 'abrio' = sd2 and (f ->> 'sector')::integer = 97, f::text);
  select x into f from jsonb_array_elements(j -> 'filas') x where x ->> 'valvula' = pg_temp.cod('V2');
  perform pg_temp.reg('04.02 la que sigue cerrada: Cerrada, sin apertura ni duración; sector 98', f ->> 'estado' = 'Cerrada' and f -> 'abierta' = 'null' and f -> 'duracion_h' = 'null' and (f ->> 'sector')::integer = 98, f::text);
  perform pg_temp.reg('04.03 por sector 98 solo sale la V2, y el motivo no sale',
    (select count(*) from jsonb_array_elements((pg_temp.bajar(sd, 'valvulas', per || jsonb_build_object('sector', pg_temp.cod('S98')))) -> 'filas') x
      where x ->> 'valvula' in (pg_temp.cod('V1'), pg_temp.cod('V2'))) = 1
    and pg_temp.hay((pg_temp.bajar(sd, 'valvulas', per || jsonb_build_object('sector', pg_temp.cod('S98')))) -> 'filas', 'valvula', pg_temp.cod('V2')) and position('Pedro' in (j)::text) = 0);

  -- ---------- 05. Eventos de suspensión ----------
  -- dos daños de prueba, fuera de las zonas (no se asocian solos): una falla de bombeo por desgaste y una fuga causada por un vehículo; su descripción no debe salir
  v_txt := (select coalesce(max(substr(d.codigo, 5)::integer), 0) from redes.danos d);
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, causa_codigo, tercero_tipo, descripcion, autor)
  values (gen_random_uuid(), 'DAN-' || lpad((v_txt::integer + 1)::text, 6, '0'), 'falla', 'bombeo', 'acueducto', pg_temp.id('T1'), pg_temp.lat(100), pg_temp.lon(1500), 'gps', clock_timestamp() - interval '1 hour', 'medio', 'propia', 'desgaste', null, libre, sd),
         (gen_random_uuid(), 'DAN-' || lpad((v_txt::integer + 2)::text, 6, '0'), 'dano', 'fuga', 'acueducto', pg_temp.id('T1'), pg_temp.lat(100), pg_temp.lon(1600), 'gps', clock_timestamp() - interval '1 hour', 'bajo', 'terceros', null, 'vehiculo', libre, sd);
  e1 := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S97')), 'causa', libre,
                                                                      'registro', 'DAN-' || lpad((v_txt::integer + 1)::text, 6, '0'),
                                                                      'regreso', to_char(clock_timestamp() + interval '4 hours', 'YYYY-MM-DD"T"HH24:MI:SSOF'))) ->> 'codigo';
  e2 := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'sectores', 'sectores', jsonb_build_array(pg_temp.cod('S98')), 'causa', 'ZTREP evento que se anula',
                                                                      'registro', 'DAN-' || lpad((v_txt::integer + 2)::text, 6, '0'))) ->> 'codigo';
  perform public.geoportal_redes_evento_anular(sd, e2, 'ZTREP se declaró por error');
  j := pg_temp.bajar(sd, 'eventos', per);
  select x into f from jsonb_array_elements(j -> 'filas') x where x ->> 'evento' = e1;
  perform pg_temp.reg('05.01 el evento abierto sale con su zona, alcance «Sectores», regreso estimado y conteos; el anulado no sale; la causa tampoco',
    f is not null and f ->> 'alcance' = 'Sectores' and f ->> 'estado' = 'Abierto' and f ->> 'regreso_estimado' is not null and f ->> 'zona' like '%ZTREP S97%'
    and (f ->> 'contratos') is not null and (f ->> 'reportes')::integer = 0 and not pg_temp.hay(j -> 'filas', 'evento', e2) and position('Pedro' in (j)::text) = 0
    and pg_temp.claves(f) = pg_temp.cols('eventos'), f::text);
  perform pg_temp.reg('05.01b del catálogo del daño asociado: tipo «Falla de bombeo» y causa «Desgaste o vejez de la tubería»; sin intervención; ni la causa escrita ni la descripción del daño',
    f ->> 'dano' = 'DAN-' || lpad((v_txt::integer + 1)::text, 6, '0') and f ->> 'tipo' = 'Falla de bombeo' and f ->> 'causa' = 'Desgaste o vejez de la tubería'
    and f -> 'intervencion' = 'null' and f -> 'tipo_intervencion' = 'null' and position('Pedro' in (j)::text) = 0
    and (j -> 'ini' -> 'leame' -> 'que_no_trae')::text like '%causa escrita al declarar%', f::text);
  j := pg_temp.bajar(sd, 'eventos', per || jsonb_build_object('sector', pg_temp.cod('S98')), true);
  perform pg_temp.reg('05.02 por sector 98 y con «Incluir ocultos»: el anulado (con su fin y quién lo anuló), y no el del 97; su daño: «Fuga o tubería rota», causa «Terceros: Vehículo»',
    pg_temp.hay(j -> 'filas', 'evento', e2) and pg_temp.hay(j -> 'filas', 'estado', 'Anulado') and pg_temp.hay(j -> 'filas', 'cerro', sd) and not pg_temp.hay(j -> 'filas', 'evento', e1)
    and pg_temp.hay(j -> 'filas', 'tipo', 'Fuga o tubería rota') and pg_temp.hay(j -> 'filas', 'causa', 'Terceros: Vehículo'), (j -> 'filas')::text);
  -- un evento declarado sobre una INTERVENCIÓN que nace de un daño (falla eléctrica, causa desconocida): el tipo y la causa salen del daño de la intervención
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, descripcion, autor)
  values (gen_random_uuid(), 'DAN-' || lpad((v_txt::integer + 3)::text, 6, '0'), 'falla', 'electrica', 'acueducto', pg_temp.id('T1'), pg_temp.lat(100), pg_temp.lon(1700), 'gps', clock_timestamp() - interval '1 hour', 'alto', 'desconocida', libre, sd);
  v_n := (select coalesce(max(substr(i.codigo, 5)::integer), 0) + 1 from redes.intervenciones i);
  insert into redes.intervenciones (id, codigo, nace_de, dano_id, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_inicio, t_fin, descripcion, ejecutor, autor)
  select gen_random_uuid(), 'ITV-' || lpad(v_n::text, 6, '0'), 'dano', d.id, 'reparacion', 'acueducto', pg_temp.id('T1'), pg_temp.lat(100), pg_temp.lon(1700), 'gps',
         clock_timestamp() - interval '50 minutes', clock_timestamp() - interval '10 minutes', libre, 'emdupar', sd
    from redes.danos d where d.codigo = 'DAN-' || lpad((v_txt::integer + 3)::text, 6, '0');
  e3 := public.geoportal_redes_evento_declarar(sd, jsonb_build_object('alcance', 'circulo', 'lat', pg_temp.lat(100), 'lon', pg_temp.lon(3000), 'radio_m', 30, 'causa', 'ZTREP evento por una intervención',
                                                                      'registro', 'ITV-' || lpad(v_n::text, 6, '0'))) ->> 'codigo';
  perform public.geoportal_redes_evento_anular(sd, e3, 'ZTREP solo para la prueba del tipo');
  select x into f from jsonb_array_elements((pg_temp.bajar(sd, 'eventos', per, true)) -> 'filas') x where x ->> 'evento' = e3;
  perform pg_temp.reg('05.03 evento sobre una intervención: «Reparación», y del daño de la intervención «Falla eléctrica» y causa «Desconocida»; alcance «Círculo»',
    f ->> 'intervencion' = 'ITV-' || lpad(v_n::text, 6, '0') and f ->> 'tipo_intervencion' = 'Reparación' and f ->> 'tipo' = 'Falla eléctrica' and f ->> 'causa' = 'Desconocida'
    and f -> 'dano' = 'null' and f ->> 'alcance' = 'Círculo' and position('Pedro' in f::text) = 0, f::text);

  -- ---------- 06. Línea 116 ----------
  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)
  values ('acueducto', md5('ztrep-a') || md5('ztrep-b'), 'csv', 4326, 'reporte', 3, 'ZTREP carga de prueba de la 116', adm) returning id into v_carga;
  insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, comuna, contrato, carga_id) values
    (990000001, clock_timestamp() - interval '2 days', 'Acueducto', 'Sin servicio de agua', 'Comuna 9', '999999990001', v_carga),
    (990000002, clock_timestamp() - interval '1 day', 'Acueducto', 'Fuga', null, null, v_carga),
    (990000003, clock_timestamp() - interval '3 hours', 'Alcantarillado', 'Rebose', null, '999999990003', v_carga);
  insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, contrato, estado, estado_desde, metodo, geom, sector, subsector, oculto)
  select r.id, r.reporte, r.fecha_registro, (r.fecha_registro at time zone 'America/Bogota')::date, r.servicio, r.causal, r.contrato,
         case when r.reporte = 990000002 then 'atendido' else 'registrado' end, r.fecha_registro, case when r.contrato is null then 'sin_ubicar' else 'contrato' end,
         case when r.contrato is not null then pg_temp.pt(120, 80) end, case when r.contrato is not null then 97 end, case when r.contrato is not null then '97A' end, r.reporte = 990000003
    from redes.l116_reportes r where r.carga_id = v_carga;
  j := pg_temp.bajar(sd, 'l116', per);
  perform pg_temp.reg('06.01 los de la 116 sin el oculto, con contrato, comuna, «Por contrato» o «Sin ubicar» y el estado vigente',
    pg_temp.hay(j -> 'filas', 'reporte', '990000001') and pg_temp.hay(j -> 'filas', 'reporte', '990000002') and not pg_temp.hay(j -> 'filas', 'reporte', '990000003')
    and pg_temp.hay(j -> 'filas', 'contrato', '999999990001') and pg_temp.hay(j -> 'filas', 'comuna', 'Comuna 9') and pg_temp.hay(j -> 'filas', 'ubicacion', 'Sin ubicar')
    and pg_temp.hay(j -> 'filas', 'estado', 'Atendido'), (j -> 'filas')::text);
  j := pg_temp.bajar(sd, 'l116', per || jsonb_build_object('sector', pg_temp.cod('S97')), true);
  perform pg_temp.reg('06.02 por sector 97 y con «Incluir ocultos»: los dos ubicados (el oculto marcado «sí»), no el sin ubicar',
    jsonb_array_length(pg_temp.de_prueba(j -> 'filas', 'reporte', '99000000_')) = 2 and pg_temp.hay(pg_temp.de_prueba(j -> 'filas', 'reporte', '99000000_'), 'oculto', 'true')
    and not pg_temp.hay(j -> 'filas', 'reporte', '990000002'), (j -> 'filas')::text);

  -- ---------- 07. Reportes del bot ----------
  insert into redes.reportes_externos (radicado, canal, tipo_bot, lat, lon, direccion, descripcion, recibido_en) values
    ('ZTREP-B1', 'telegram', 'Fuga en la calle', pg_temp.lat(100), pg_temp.lon(300), 'Calle de ' || libre, 'Me llamo ' || libre, clock_timestamp() - interval '2 days') returning id into v_rep;
  insert into redes.reportes_externos (radicado, canal, tipo_bot, lat, lon, direccion, descripcion, recibido_en) values
    ('ZTREP-B2', 'whatsapp', 'Sin agua', pg_temp.lat(100), pg_temp.lon(800), null, libre, clock_timestamp() - interval '1 day') returning id into v_rep2;
  insert into redes.reporte_externo_eventos (reporte_id, tipo, motivo, autor) values (v_rep2, 'descartado', 'ZTREP repetido de otro reporte', sd);
  j := pg_temp.bajar(sd, 'bot', per);
  perform pg_temp.reg('07.01 los del bot sin el descartado, con radicado, canal, tipo, estado y sector; sin la descripción ni la dirección',
    pg_temp.hay(j -> 'filas', 'radicado', 'ZTREP-B1') and not pg_temp.hay(j -> 'filas', 'radicado', 'ZTREP-B2') and pg_temp.hay(j -> 'filas', 'estado', 'Recibido')
    and position('Pedro' in (j)::text) = 0 and (select (x ->> 'sector')::integer from jsonb_array_elements(j -> 'filas') x where x ->> 'radicado' = 'ZTREP-B1') = 97, (j -> 'filas')::text);
  j := pg_temp.bajar(sd, 'bot', per || jsonb_build_object('sector', pg_temp.cod('S98')), true);
  perform pg_temp.reg('07.02 por sector 98 y con «Incluir ocultos»: el descartado (de los de prueba, solo el ZTREP-B2)',
    jsonb_array_length(pg_temp.de_prueba(j -> 'filas', 'radicado', 'ZTREP-B%')) = 1 and pg_temp.hay(j -> 'filas', 'radicado', 'ZTREP-B2')
    and pg_temp.hay(pg_temp.de_prueba(j -> 'filas', 'radicado', 'ZTREP-B%'), 'estado', 'Descartado'), (j -> 'filas')::text);

  -- ---------- 08. Usuarios sensibles (inventario a hoy) ----------
  insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor) values ('999999990001', 'hospital', 'ZTREPHOSPITALPEDRO', 'nombre', adm),
    ('999999990002', 'colegio', null, 'manual', adm), ('999999990003', 'clinica', 'ZTREPCLINICAPEDRO', 'nombre', adm);
  insert into redes.usuario_sensible_eventos (contrato, accion, tipo, autor) values ('999999990001', 'confirmar', 'hospital', sd);
  insert into redes.usuario_sensible_eventos (contrato, accion, motivo, autor) values ('999999990003', 'descartar', 'ZTREP no es una clínica', sd);
  j := pg_temp.bajar(sd, 'sensibles', '{}');
  perform pg_temp.reg('08.01 sin periodo: los sensibles de hoy sin el descartado, con tipo, estado y origen; sin la palabra del nombre',
    pg_temp.hay(j -> 'filas', 'contrato', '999999990001') and pg_temp.hay(j -> 'filas', 'contrato', '999999990002') and not pg_temp.hay(j -> 'filas', 'contrato', '999999990003')
    and pg_temp.hay(pg_temp.de_prueba(j -> 'filas', 'contrato', '99999999000_'), 'estado', 'Confirmado') and pg_temp.hay(pg_temp.de_prueba(j -> 'filas', 'contrato', '99999999000_'), 'tipo', 'Hospital')
    and pg_temp.hay(pg_temp.de_prueba(j -> 'filas', 'contrato', '99999999000_'), 'origen', 'Por el nombre') and jsonb_array_length(pg_temp.de_prueba(j -> 'filas', 'contrato', '99999999000_')) = 2
    and position('ZTREPHOSPITAL' in (j)::text) = 0 and position('Periodo' in (j -> 'ini' -> 'leame')::text) = 0 and position('Inventario al' in (j -> 'ini' -> 'leame')::text) > 0, left((j -> 'filas')::text, 300));
  j := pg_temp.bajar(sd, 'sensibles', '{"tipo": "clinica"}', true);
  perform pg_temp.reg('08.02 por tipo «clinica» y con «Incluir ocultos»: de los de prueba solo sale la clínica descartada (999999990003); todas las filas son clínicas',
    jsonb_array_length(pg_temp.de_prueba(j -> 'filas', 'contrato', '99999999000_')) = 1 and pg_temp.hay(pg_temp.de_prueba(j -> 'filas', 'contrato', '99999999000_'), 'contrato', '999999990003')
    and pg_temp.hay(pg_temp.de_prueba(j -> 'filas', 'contrato', '99999999000_'), 'estado', 'Descartado')
    and (select bool_and(x ->> 'tipo' = (select t.nombre from redes.tipos_sensible t where t.codigo = 'clinica')) from jsonb_array_elements(j -> 'filas') x), left((j -> 'filas')::text, 300));

  -- ---------- 09. Activos de la red ----------
  j := pg_temp.bajar(sd, 'activos', '{"tipo": "SEC"}');
  select x into f from jsonb_array_elements(j -> 'filas') x where x ->> 'codigo' = pg_temp.cod('S97A');
  perform pg_temp.reg('09.01 por tipo SEC: los 3 sectores de prueba (y los reales), con tipo, estado, clase y un punto para ubicarlos',
    (select count(*) from jsonb_array_elements(j -> 'filas') x where x ->> 'codigo' in (pg_temp.cod('S97'), pg_temp.cod('S97A'), pg_temp.cod('S98'))) = 3
    and f ->> 'prefijo' = 'SEC' and f ->> 'estado' = 'En operación' and (f ->> 'lat') is not null and (f ->> 'sector')::integer = 97
    and jsonb_array_length(j -> 'filas') = (select count(*) from redes.activo_vigente_mat where prefijo = 'SEC' and not retirado and not oculto), f::text);
  j := pg_temp.bajar(sd, 'activos', '{"tipo": "RED", "sistema": "acueducto"}');
  select x into f from jsonb_array_elements(j -> 'filas') x where x ->> 'codigo' = pg_temp.cod('T1');
  perform pg_temp.reg('09.02 un tramo sale con su material, diámetro y longitud, y su punto queda sobre la línea',
    f ->> 'material' is not null and (f ->> 'diametro_mm')::numeric = 110 and (f ->> 'sector')::integer = 97
    and ST_DWithin(ST_SetSRID(ST_MakePoint((f ->> 'lon')::float8, (f ->> 'lat')::float8), 4326)::geography, ST_MakeLine(pg_temp.pt(50, 0), pg_temp.pt(350, 0))::geography, 1), f::text);

  -- ---------- 10. Paginación: de una en una, el mismo resultado que de una vez, sin repetir ni saltar ----------
  j := pg_temp.bajar(sd, 'valvulas', per, false, 5000); j2 := pg_temp.bajar(sd, 'valvulas', per, false, 1);
  perform pg_temp.reg('10.01 válvulas de una en una = de una vez (mismo orden y mismas filas)', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = (j -> 'ini' ->> 'total')::integer, jsonb_array_length(j2 -> 'filas')::text);
  j := pg_temp.bajar(sd, 'bot', per, true, 5000); j2 := pg_temp.bajar(sd, 'bot', per, true, 1);
  perform pg_temp.reg('10.02 bot (llave con la hora) de uno en uno = de una vez', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = (j -> 'ini' ->> 'total')::integer);
  j := pg_temp.bajar(sd, 'levantamientos', per, true, 5000); j2 := pg_temp.bajar(sd, 'levantamientos', per, true, 2);
  perform pg_temp.reg('10.03 levantamientos de dos en dos = de una vez', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = (j -> 'ini' ->> 'total')::integer);
  j := public.geoportal_redes_reporte_iniciar(sd, 'activos', '{"tipo": "SEC"}', 'xlsx', false, null);
  j2 := public.geoportal_redes_reporte_pagina(sd, (j ->> 'descarga_id')::bigint, null, (j ->> 'total')::integer);
  perform pg_temp.reg('10.04 una página exacta deja cursor; la siguiente viene vacía y sin cursor',
    j2 ->> 'cursor' is not null and (public.geoportal_redes_reporte_pagina(sd, (j ->> 'descarga_id')::bigint, j2 ->> 'cursor', 10) ->> 'devueltos')::integer = 0
    and public.geoportal_redes_reporte_pagina(sd, (j ->> 'descarga_id')::bigint, j2 ->> 'cursor', 10) -> 'cursor' = 'null');
  perform pg_temp.err('10.05 un cursor con caracteres raros se rechaza', format('select public.geoportal_redes_reporte_pagina(%L, %s, %L)', sd, j ->> 'descarga_id', 'x''; drop'), null, 'no es válida');

  -- ---------- 11. La foto: lo que llega después de iniciar no entra ----------
  j := public.geoportal_redes_reporte_iniciar(sd, 'levantamientos', per, 'xlsx', true, null);
  insert into redes.levantar_puntos (id, codigo, servicio, tipo, lat, lon, geom, precision_m, precision_baja, area, autor)
  values (gen_random_uuid(), 'LEV-900004', 'acueducto', 'hidrante', pg_temp.lat(90), pg_temp.lon(90), pg_temp.pt(90, 90), 3, false, 'tecnica', op);
  perform pg_temp.reg('11.01 un LEV reportado después de iniciar no sale en las páginas de esa descarga (sí en una nueva)',
    not pg_temp.hay(pg_temp.todas(sd, (j ->> 'descarga_id')::bigint), 'codigo', 'LEV-900004') and pg_temp.hay(pg_temp.bajar(sd, 'levantamientos', per) -> 'filas', 'codigo', 'LEV-900004'));

  -- ---------- 12. La descarga es de quien la inició, vence y se cierra una vez ----------
  v_id := (public.geoportal_redes_reporte_iniciar(sd, 'eventos', per, 'csv', false, '10.0.0.2') ->> 'descarga_id')::bigint;
  perform pg_temp.err('12.01 otra persona no puede pedir sus páginas (404)', format('select public.geoportal_redes_reporte_pagina(%L, %s)', sd2, v_id), 'P0002');
  perform pg_temp.err('12.02 ni cerrarla (404)', format('select public.geoportal_redes_reporte_cerrar(%L, %s, 1)', sd2, v_id), 'P0002');
  j := public.geoportal_redes_reporte_cerrar(sd, v_id, 1, 'completa', '10.0.0.2');
  j2 := public.geoportal_redes_reporte_cerrar(sd, v_id, 1, 'completa', '10.0.0.2');
  perform pg_temp.reg('12.03 cerrarla dos veces no es error: la segunda dice «repetida»', (j ->> 'repetida')::boolean = false and (j2 ->> 'repetida')::boolean = true);
  perform pg_temp.err('12.04 cerrada, sus páginas ya no salen (409)', format('select public.geoportal_redes_reporte_pagina(%L, %s)', sd, v_id), '55000', 'ya terminó');
  insert into redes.reporte_descargas (email, reporte, filtros, incluir, formato, total, corte_en, creado_en)
  values (sd, 'eventos', per, false, 'xlsx', 1, clock_timestamp() - interval '3 hours', clock_timestamp() - interval '3 hours') returning id into v_id2;
  perform pg_temp.err('12.05 iniciada hace más de 2 horas: venció (409)', format('select public.geoportal_redes_reporte_pagina(%L, %s)', sd, v_id2), '55000', 'venció');
  perform pg_temp.err('12.06 un resultado de cierre que no existe', format('select public.geoportal_redes_reporte_cerrar(%L, %s, 1, %L)', sd, v_id2, 'otra'), null, 'no válido');

  -- ---------- 13. Auditoría ----------
  select count(*) into v_aud from public.geoportal_auditoria a where a.accion = 'redes_reporte_iniciar' and a.referencia = v_id::text and a.email = sd and a.ip = '10.0.0.2'
     and a.detalle ->> 'reporte' = 'eventos' and (a.detalle ->> 'filas')::integer >= 1 and a.detalle -> 'filtros' ->> 'desde' = (hoy - 30)::text;
  perform pg_temp.reg('13.01 iniciar queda en la auditoría: quién, qué reporte, filtros, filas, formato e IP', v_aud = 1);
  perform pg_temp.reg('13.02 cerrar queda una sola vez en la auditoría, con las filas entregadas y el resultado',
    (select count(*) from public.geoportal_auditoria a where a.accion = 'redes_reporte_cerrar' and a.referencia = v_id::text and (a.detalle ->> 'filas_entregadas')::integer = 1 and a.detalle ->> 'resultado' = 'completa') = 1);
  perform pg_temp.reg('13.03 la auditoría de estas descargas no guarda filas ni textos libres', not exists (select 1 from public.geoportal_auditoria a where a.accion like 'redes\_reporte\_%' and (a.detalle ? 'filas_json' or position('Pedro' in a.detalle::text) > 0)));

  -- ---------- 14. Seguridad del esquema ----------
  perform pg_temp.reg('14.01 las 4 RPC: security definer, search_path fijo, solo service_role (ni anon, ni authenticated, ni PUBLIC)',
    (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array['geoportal_redes_reporte_iniciar', 'geoportal_redes_reporte_pagina', 'geoportal_redes_reporte_cerrar', 'geoportal_redes_reporte_sectores']) and p.prosecdef and p.proconfig is not null
       and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 4);
  perform pg_temp.reg('14.02 las funciones internas f_rep_*: nadie más que su dueño',
    not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname = any (array['f_rep_catalogo', 'f_rep_max_filas', 'f_rep_ts', 'f_rep_col', 'f_rep_rotulo', 'f_rep_sector_geom', 'f_rep_sectores', 'f_rep_punto', 'f_rep_filtros', 'f_rep_columnas', 'f_rep_levantamientos', 'f_rep_valvulas', 'f_rep_eventos', 'f_rep_l116', 'f_rep_bot', 'f_rep_sensibles', 'f_rep_activos', 'f_rep_filas', 'f_rep_contar', 'f_rep_leame']) and exists (select 1 from aclexplode(p.proacl) x where x.grantee <> p.proowner)));
  perform pg_temp.reg('14.03 las 2 tablas nuevas: RLS y sin permisos para la API',
    (select count(*) from pg_class c where c.oid in ('redes.reporte_descargas'::regclass, 'redes.reporte_descarga_cierres'::regclass) and c.relrowsecurity
       and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')) = 2);
  perform pg_temp.err('14.04 las descargas son de solo inserción: no se cambian', format('update redes.reporte_descargas set total = 0 where id = %s', v_id));
  perform pg_temp.err('14.05 ni se borran', format('delete from redes.reporte_descarga_cierres where descarga_id = %s', v_id));
  perform pg_temp.reg('14.07 las rutas publicadas del bot de nombre parecido (reporte_convertir y reporte_descartar) siguen para service_role',
    has_function_privilege('service_role', 'public.geoportal_redes_reporte_convertir(text,uuid,jsonb)', 'execute') and has_function_privilege('service_role', 'public.geoportal_redes_reporte_descartar(text,uuid,text)', 'execute'));
  perform pg_temp.reg('14.06 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));

  -- ---------- 15. Tiempos con el volumen real: Activos de la red completo ----------
  v_t0 := clock_timestamp(); j := public.geoportal_redes_reporte_iniciar(sd, 'activos', '{}', 'xlsx', false, null); v_ms1 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_t0 := clock_timestamp(); j2 := public.geoportal_redes_reporte_pagina(sd, (j ->> 'descarga_id')::bigint, null, 5000); v_ms2 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_info := format('TIEMPOS con el volumen real: Activos de la red (%s activos) iniciar %s ms · primera página de 5.000 %s ms (tope de la API: 30 s por llamada)',
                   j ->> 'total', round(v_ms1), round(v_ms2));
  perform pg_temp.reg('15.01 TIEMPOS: iniciar «Activos de la red» completo y su primera página de 5.000, cada uno en menos de 5 s', (j2 ->> 'devueltos')::integer = least(5000, (j ->> 'total')::integer) and v_ms1 < 5000 and v_ms2 < 5000, v_info);

  -- ---------- 17. La lista del filtro de sector ----------
  j := public.geoportal_redes_reporte_sectores(sd);
  select x into f from jsonb_array_elements(j -> 'sectores') x where x ->> 'codigo' = pg_temp.cod('S97A');
  perform pg_temp.reg('17.01 la lista trae todos los sectores y subsectores vigentes de la capa, con código, nombre, clase, número de sector y subsector',
    jsonb_array_length(j -> 'sectores') = (select count(*) from redes.activo_vigente_mat where prefijo = 'SEC' and not retirado and not oculto)
    and f ->> 'nombre' = 'ZTREP S97A' and f ->> 'clase' = 'subsector' and (f ->> 'sector')::integer = 97 and f ->> 'subsector' = '97A'
    and pg_temp.claves(f) = 'clase,codigo,nombre,sector,subsector', f::text);
  perform pg_temp.reg('17.02 en orden: el sector 97, luego su subsector 97A, luego el 98',
    (select array_agg(x ->> 'codigo' order by o) from jsonb_array_elements(j -> 'sectores') with ordinality t(x, o) where x ->> 'codigo' in (pg_temp.cod('S97'), pg_temp.cod('S97A'), pg_temp.cod('S98')))
      = array[pg_temp.cod('S97'), pg_temp.cod('S97A'), pg_temp.cod('S98')], (j -> 'sectores')::text);
  perform pg_temp.err('17.03 la lista es solo del supervisor de distribución y el administrador (el de planta: 403)', format('select public.geoportal_redes_reporte_sectores(%L)', sp), '42501');
  perform pg_temp.reg('17.04 la lista no se audita', not exists (select 1 from public.geoportal_auditoria a where a.accion like '%sectores%' and a.email = sd));

  -- ---------- 16. El tope de filas (se baja solo dentro de esta prueba) ----------
  create or replace function redes.f_rep_max_filas() returns integer language sql immutable set search_path to 'pg_catalog' as $f$ select 2 $f$;
  perform pg_temp.err('16.01 más filas que el tope: «Acote el periodo o los filtros»', format('select public.geoportal_redes_reporte_iniciar(%L, %L, %L)', sd, 'activos', '{"tipo": "SEC"}'), null, 'Acote el periodo');

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · descargas de Distribución (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
