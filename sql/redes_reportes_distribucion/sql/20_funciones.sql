-- =====================================================================
-- 20 — FUNCIONES INTERNAS de las descargas de Distribución (nadie de la API las ejecuta; las llaman las RPC del 26).
-- Cada reporte devuelve (k, fila): «k» es la llave de orden y de paginación y «fila» el objeto con las claves de sus columnas.
-- Sin textos libres (observaciones, motivos, causas, descripción y dirección del ciudadano, la palabra del nombre que marcó a un sensible). Contrato sí.
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
-- La zona de un sector (todos sus polígonos y los de sus subsectores en la capa de sectores), para filtrar por sector.
create function redes.f_rep_sector_geom(p_sector integer) returns geometry
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $$
  select ST_Union(m.geom) from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
   where m.prefijo = 'SEC' and not m.retirado and not m.oculto and redes.f_num(v.atributos -> 'modelo' -> 'sector') = p_sector $$;
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
  v_t := nullif(btrim(v_f ->> 'sector'), '');
  if v_t is not null then
    if v_t !~ '^[0-9]{1,3}$' or v_t::integer not between 1 and 100 then perform tecnica.f_error('Ese sector no es válido.'); end if;
    if redes.f_rep_sector_geom(v_t::integer) is null then perform tecnica.f_error('Ese sector no está en la capa de sectores.'); end if;
    v_r := v_r || jsonb_build_object('sector', v_t::integer);
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
    redes.f_rep_col('reportes_campo', 'De campo', 'entero'), redes.f_rep_col('dano', 'Daño', 'texto'), redes.f_rep_col('intervencion', 'Intervención', 'texto'),
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
  with sg as (select redes.f_rep_sector_geom((p_f ->> 'sector')::integer) as g where p_f ? 'sector'),
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
  with sg as (select redes.f_rep_sector_geom((p_f ->> 'sector')::integer) as g where p_f ? 'sector'),
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

-- 5. Eventos de suspensión (todos los alcances). Contratos y sensibles como números. Sin la causa.
create function redes.f_rep_eventos(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language sql stable set search_path to 'redes', 'public', 'tecnica', 'extensions', 'pg_temp' as $$
  with sg as (select redes.f_rep_sector_geom((p_f ->> 'sector')::integer) as g where p_f ? 'sector'),
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
           'dano', (select d.codigo from redes.danos d where d.id = x.dano_id), 'intervencion', (select i.codigo from redes.intervenciones i where i.id = x.intervencion_id),
           'declaro', x.autor, 'cerro', x.fin_autor) end
    from x cross join lateral (select count(*) as n, count(*) filter (where v.origen = 'bot') as bot, count(*) filter (where v.origen = 'l116') as l116,
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
     and (p_incl or not v.oculto) and (not p_f ? 'sector' or v.sector = (p_f ->> 'sector')::integer)
     and (p_cursor is null or v.reporte_id > p_cursor::bigint)
   order by v.reporte_id limit p_limite $$;

-- 7. Reportes del bot (sin la descripción ni la dirección que escribió el ciudadano)
create function redes.f_rep_bot(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_solo_llave boolean default false) returns table (k text, fila jsonb)
language sql stable set search_path to 'redes', 'public', 'extensions', 'pg_temp' as $$
  with sg as (select redes.f_rep_sector_geom((p_f ->> 'sector')::integer) as g where p_f ? 'sector'),
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
declare c record; v_trae text[]; v_no text[] := array['Textos libres (descripciones, observaciones, motivos y causas): pueden traer datos de personas y se ven solo en pantalla.',
                                                       'Teléfonos y nombres de suscriptores, del ciudadano que reporta o de terceros.'];
  v_filtros text[] := '{}'; v_ex text;
begin
  select * into c from redes.f_rep_catalogo() x where x.clave = p_reporte;
  v_trae := case p_reporte
    when 'levantamientos' then array['Una fila por punto de «Encontrar o reportar activo» (código LEV), con su estado vigente, el activo creado si se levantó y su ubicación.']
    when 'valvulas' then array['Una fila por cierre de una válvula, con el regreso estimado vigente, la apertura y la duración. Una válvula que sigue cerrada no tiene apertura.']
    when 'eventos' then array['Una fila por evento de suspensión vigente algún momento del periodo: zona, desde cuándo, regreso estimado (al declarar y el vigente), fin y duración.',
                              'Contratos y usuarios sensibles afectados como números (los que se calcularon al declarar) y los reportes asociados hoy, por origen.']
    when 'l116' then array['Una fila por reporte de la línea 116 cargado, con su estado vigente, el contrato y la ubicación (por contrato o sin ubicar).']
    when 'bot' then array['Una fila por reporte recibido del bot, con su estado y el daño en que se convirtió, si se convirtió.']
    when 'sensibles' then array['Una fila por contrato marcado como usuario sensible, con su tipo y estado de hoy (inventario a la fecha de la descarga).']
    when 'activos' then array['Una fila por activo de la red tal como está hoy (inventario a la fecha de la descarga), con un punto del activo para ubicarlo.']
  end;
  if p_reporte = 'bot' then v_no := v_no || array['La descripción y la dirección que escribió el ciudadano.']; end if;
  if p_reporte = 'sensibles' then v_no := v_no || array['El nombre del suscriptor ni la palabra del nombre que lo marcó.']; end if;
  if c.periodo then
    v_filtros := array['Periodo: ' || to_char((p_f ->> 'desde')::date, 'DD/MM/YYYY') || ' a ' || to_char((p_f ->> 'hasta')::date, 'DD/MM/YYYY') || ' (según ' || c.periodo_sobre || ')'];
  else
    v_filtros := array['Inventario al ' || to_char(p_corte at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI')];
  end if;
  if p_f ? 'sector' then v_filtros := v_filtros || ('Sector: ' || (p_f ->> 'sector')); end if;
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
