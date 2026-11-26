-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 20 — FUNCIONES INTERNAS (esquema analisis; nadie de la API las ejecuta directamente)
-- =====================================================================
-- Error con texto para la persona (la Edge solo reenvía los mensajes con HINT = msg_usuario).
-- 22023 → 400 · 42501 → 403 · P0002 → 404 · 55000 → 409 · 54000 → 429
create function analisis.f_err(p_mensaje text, p_codigo text default '22023') returns void
language plpgsql set search_path = pg_catalog as $f$
begin
  raise exception '%', p_mensaje using errcode = p_codigo, hint = 'msg_usuario';
end $f$;

create function analisis.f_parametro(p_clave text) returns numeric
language sql stable security definer set search_path = analisis, pg_catalog as $f$
  select p.valor from analisis.parametros p where p.clave = p_clave order by p.id desc limit 1
$f$;

-- Quién entra a los cuadernos de Técnica: SOLO el supervisor de Técnica (distribución o planta) y el administrador.
-- La decisión es la del geovisor técnico (redes.f_geovisor_acceso, que no se toca): «completo» = supervisor o administrador.
-- El operador con la casilla del geovisor (solo lectura) y quien no tiene el geovisor reciben 42501 (403).
create function analisis.f_acceso(p_solicitante text, out email text, out admin boolean) returns record
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record;
begin
  a := redes.f_geovisor_acceso(p_solicitante);      -- 28000 sin solicitante · 42501 sin el geovisor técnico
  if not coalesce(a.completo, false) then
    raise exception 'Los cuadernos de análisis son del supervisor de Técnica' using errcode = '42501';
  end if;
  email := a.email; admin := coalesce(a.admin, false);
end $f$;

create function analisis.f_archivado(p_cuaderno uuid) returns boolean
language sql stable security definer set search_path = analisis, pg_catalog as $f$
  select coalesce((select e.tipo = 'archivar' from analisis.cuaderno_eventos e where e.cuaderno_id = p_cuaderno order by e.id desc limit 1), false)
$f$;

create function analisis.f_ultima_version(p_cuaderno uuid) returns integer
language sql stable security definer set search_path = analisis, pg_catalog as $f$
  select max(v.version) from analisis.cuaderno_versiones v where v.cuaderno_id = p_cuaderno
$f$;

-- El cuaderno, si el solicitante puede LEERLO (el autor, cualquier supervisor de Técnica y el administrador: todos pasaron f_acceso). Con p_autor, además debe ser SUYO.
-- A propósito no distingue «no existe» de «no es de este módulo»: 404 en los dos casos.
create function analisis.f_cuaderno(p_email text, p_id uuid, p_autor boolean default false) returns analisis.cuadernos
language plpgsql stable security definer set search_path = analisis, pg_catalog as $f$
declare c analisis.cuadernos;
begin
  if p_id is null then perform analisis.f_err('Falta el cuaderno'); end if;
  select * into c from analisis.cuadernos k where k.id = p_id and k.modulo = 'tecnica';
  if not found then perform analisis.f_err('El cuaderno no existe', 'P0002'); end if;
  if p_autor and c.autor <> p_email then
    raise exception 'Solo el autor edita el cuaderno' using errcode = '42501';
  end if;
  return c;
end $f$;

-- Punto que representa a la figura (para anotar el sector y para la exportación): el punto mismo, la mitad de la línea o un punto dentro del polígono.
create function analisis.f_punto(p_geom geometry) returns geometry
language sql immutable parallel safe set search_path = public, pg_catalog as $f$
  select case geometrytype(p_geom) when 'POINT' then p_geom
                                    when 'LINESTRING' then st_lineinterpolatepoint(p_geom, 0.5)
                                    else st_pointonsurface(p_geom) end
$f$;

-- Predios y contratos dentro de una zona. SOLO los dos números (ni direcciones ni códigos). Contratos = cod_usuario distintos y no vacíos.
create function analisis.f_conteo_zona(p_geom geometry, out predios integer, out contratos integer) returns record
language sql stable security definer set search_path = public, pg_catalog as $f$
  select count(*)::integer, (count(distinct c.cod_usuario) filter (where btrim(coalesce(c.cod_usuario, '')) <> ''))::integer
    from public.catastro_valledupar c where st_intersects(c.geom, p_geom)
$f$;

-- Tope de conteos por hora del solicitante (los de «zona» y los que hace «guardar» al calcular sus zonas).
create function analisis.f_cupo_zona(p_email text, p_nuevos integer) returns void
language plpgsql stable security definer set search_path = analisis, pg_catalog as $f$
begin
  if (select count(*) from analisis.zona_consultas z where z.solicitante = p_email and z.creado_en > now() - interval '1 hour') + p_nuevos
     > analisis.f_parametro('zona_conteos_por_hora') then
    perform analisis.f_err('Demasiados conteos de zona en la última hora. Espere unos minutos e intente de nuevo', '54000');
  end if;
end $f$;

-- Una zona lista para contar: polígono válido, dentro de Valledupar y bajo el área máxima.
create function analisis.f_zona_valida(p_geom geometry) returns numeric
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare v_km2 numeric;
begin
  if p_geom is null or geometrytype(p_geom) <> 'POLYGON' or not st_isvalid(p_geom) then perform analisis.f_err('La zona no es un polígono válido'); end if;
  if st_npoints(p_geom) > 2000 then perform analisis.f_err('La zona tiene demasiados vértices'); end if;
  if not analisis.f_en_valledupar(p_geom) then perform analisis.f_err('La zona está fuera de Valledupar'); end if;
  v_km2 := round((st_area(p_geom::geography) / 1e6)::numeric, 4);
  if v_km2 > analisis.f_parametro('zona_area_max_km2') then
    perform analisis.f_err(format('La zona es demasiado grande (%s km²; el máximo es %s km²)', round(v_km2, 1), analisis.f_parametro('zona_area_max_km2')));
  end if;
  return v_km2;
end $f$;

-- Geometría desde el GeoJSON del dispositivo (siempre 4326). Un GeoJSON ilegible es 400, no 500.
create function analisis.f_geom(p jsonb) returns geometry
language plpgsql immutable set search_path = public, pg_temp as $f$
declare g geometry;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return null; end if;
  begin
    g := st_setsrid(st_force2d(st_geomfromgeojson(p::text)), 4326);
  exception when others then
    return null;
  end;
  return g;
end $f$;

-- Las marcas de un cuaderno tal como estaban en una versión (la última fila de cada marca hasta esa versión; las anuladas no salen).
create function analisis.f_marcas(p_cuaderno uuid, p_version integer) returns jsonb
language sql stable security definer set search_path = public, analisis, pg_temp as $f$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', u.marca_id, 'version', u.version, 'creada_en_version', u.creada_en_version, 'tipo', u.tipo, 'subtipo', u.subtipo, 'sistema', u.sistema,
           'categoria', u.categoria, 'nota', u.nota, 'estilo', u.estilo, 'geom', st_asgeojson(u.geom, 7)::jsonb, 'radio_m', u.radio_m,
           'conteo_predios', u.conteo_predios, 'conteo_contratos', u.conteo_contratos, 'activo_codigo', u.activo_codigo, 'sector', u.sector, 'subsector', u.subsector)
           order by u.creada_en_version, u.creado_en, u.marca_id), '[]'::jsonb)
    from (select distinct on (mv.marca_id) mv.*, m.creada_en_version, m.creado_en
            from analisis.marca_versiones mv join analisis.marcas m on m.id = mv.marca_id
           where mv.cuaderno_id = p_cuaderno and mv.version <= p_version
           order by mv.marca_id, mv.version desc) u
   where not u.anulada
$f$;

-- pg-safeupdate: las funciones de este paquete sin DELETE/UPDATE sin WHERE. Es la misma revisión de redes.f_funciones_sin_where(), sobre `analisis` y
-- public.geoportal_analisis_* (la de redes no se toca para no cambiar su huella).
create function analisis.f_funciones_sin_where() returns table (funcion text, sentencia text)
language sql stable set search_path = pg_catalog as $f$
  with f as (
    select p.oid::regprocedure::text as funcion,
           regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace in (select n.oid from pg_namespace n where n.nspname = 'analisis')
            or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select s.funcion, left(s.st, 200) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')
   order by 1, 2
$f$;
