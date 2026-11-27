-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 26 — RPC public.geoportal_analisis_* (las llama SOLO la Edge geoportal-analisis, con service_role)
-- Todas: SECURITY DEFINER con search_path fijo, p_solicitante = el correo del token (lo pone la Edge) y la decisión de permiso aquí, en SQL.
-- Lee: el autor, cualquier supervisor de Técnica y el administrador. Edita: SOLO el autor (también si es administrador). Operador y sin permisos: 42501 (403).
-- =====================================================================

-- ---------- perfil: quién es, el catálogo y los topes (para armar la barra) ----------
create function public.geoportal_analisis_perfil(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record;
begin
  a := analisis.f_acceso(p_solicitante);
  return jsonb_build_object(
    'email', a.email, 'admin', a.admin, 'puede_crear', true,
    'catalogo', (select jsonb_agg(jsonb_build_object('grupo', c.grupo, 'codigo', c.codigo, 'nombre', c.nombre, 'color', c.color, 'orden', c.orden) order by c.grupo desc, c.orden)
                   from analisis.catalogo c where c.activo),
    'sistemas', jsonb_build_object('acueducto', '#1F5FA8', 'alcantarillado', '#8A5A2B'),
    'categorias', jsonb_build_array('problema', 'propuesta', 'obra', 'observacion'),
    'topes', (select jsonb_object_agg(x.clave, x.valor) from (select distinct on (p.clave) p.clave, p.valor from analisis.parametros p order by p.clave, p.id desc) x));
end $f$;

-- ---------- lista de cuadernos (los míos y los del equipo) ----------
create function public.geoportal_analisis_cuadernos(p_solicitante text, p_archivados boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record;
begin
  a := analisis.f_acceso(p_solicitante);
  return jsonb_build_object('cuadernos', coalesce((
    select jsonb_agg(to_jsonb(x) order by x.actualizado_en desc, x.id)
      from (select c.id, v.titulo, v.descripcion, c.autor, (select lb.nombre from public.geoportal_lista_blanca lb where lower(lb.email) = c.autor limit 1) as autor_nombre,
                   c.creado_en, v.version, v.creado_en as actualizado_en, c.autor = a.email as es_mio, analisis.f_archivado(c.id) as archivado,
                   (select count(*) from (select distinct on (mv.marca_id) mv.anulada from analisis.marca_versiones mv where mv.cuaderno_id = c.id
                                           order by mv.marca_id, mv.version desc) u where not u.anulada) as marcas,
                   (select count(*) from analisis.capturas k join analisis.capturas_confirmadas kc on kc.captura_id = k.id where k.cuaderno_id = c.id and not exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = k.id)) as capturas
              from analisis.cuadernos c
              join analisis.cuaderno_versiones v on v.cuaderno_id = c.id and v.version = analisis.f_ultima_version(c.id)
             where c.modulo = 'tecnica' and analisis.f_archivado(c.id) = coalesce(p_archivados, false)
             order by v.creado_en desc limit 500) x), '[]'::jsonb));
end $f$;

-- ---------- un cuaderno: la última versión o la pedida, con sus marcas vigentes y sus capturas ----------
create function public.geoportal_analisis_cuaderno(p_solicitante text, p_id uuid, p_version integer default null) returns jsonb
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record; c analisis.cuadernos; v analisis.cuaderno_versiones; v_ult integer;
begin
  a := analisis.f_acceso(p_solicitante);
  c := analisis.f_cuaderno(a.email, p_id);
  v_ult := analisis.f_ultima_version(c.id);
  select * into v from analisis.cuaderno_versiones x where x.cuaderno_id = c.id and x.version = coalesce(p_version, v_ult);
  if not found then perform analisis.f_err('Esa versión del cuaderno no existe', 'P0002'); end if;
  return jsonb_build_object(
    'id', c.id, 'modulo', c.modulo, 'autor', c.autor, 'creado_en', c.creado_en, 'es_mio', c.autor = a.email, 'archivado', analisis.f_archivado(c.id),
    'autor_nombre', (select lb.nombre from public.geoportal_lista_blanca lb where lower(lb.email) = c.autor limit 1),
    'version', v.version, 'ultima_version', v_ult, 'titulo', v.titulo, 'descripcion', v.descripcion, 'vista', v.vista, 'guardado_en', v.creado_en,
    'puede_editar', c.autor = a.email and v.version = v_ult and not analisis.f_archivado(c.id),
    'versiones', (select jsonb_agg(jsonb_build_object('version', x.version, 'creado_en', x.creado_en, 'titulo', x.titulo) order by x.version desc)
                    from analisis.cuaderno_versiones x where x.cuaderno_id = c.id),
    'marcas', analisis.f_marcas(c.id, v.version),
    'capturas', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'titulo', k.titulo, 'extension', jsonb_build_array(k.oeste, k.sur, k.este, k.norte),
                                 'ancho', k.ancho, 'alto', k.alto, 'bytes', kc.bytes_reales, 'creado_en', k.creado_en) order by k.creado_en, k.id)
                            from analisis.capturas k join analisis.capturas_confirmadas kc on kc.captura_id = k.id where k.cuaderno_id = c.id and not exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = k.id)), '[]'::jsonb),
    'eventos', coalesce((select jsonb_agg(jsonb_build_object('tipo', e.tipo, 'motivo', e.motivo, 'creado_en', e.creado_en) order by e.id)
                           from analisis.cuaderno_eventos e where e.cuaderno_id = c.id), '[]'::jsonb));
end $f$;

-- ---------- crear: nace con la versión 1, sin marcas ----------
create function public.geoportal_analisis_cuaderno_crear(p_solicitante text, p_titulo text, p_descripcion text default null, p_vista jsonb default null) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; v_id uuid; v_titulo text := btrim(coalesce(p_titulo, '')); v_desc text := nullif(btrim(coalesce(p_descripcion, '')), '');
begin
  a := analisis.f_acceso(p_solicitante);
  if length(v_titulo) not between 3 and 120 then perform analisis.f_err('El título debe tener entre 3 y 120 letras'); end if;
  if length(v_desc) > 1000 then perform analisis.f_err('La descripción no puede pasar de 1.000 letras'); end if;
  if p_vista is not null and (jsonb_typeof(p_vista) <> 'object' or length(p_vista::text) > 4000) then perform analisis.f_err('La vista del mapa no es válida'); end if;
  insert into analisis.cuadernos (modulo, autor) values ('tecnica', a.email) returning id into v_id;
  insert into analisis.cuaderno_versiones (cuaderno_id, version, titulo, descripcion, vista, autor) values (v_id, 1, v_titulo, v_desc, p_vista, a.email);
  return jsonb_build_object('id', v_id, 'version', 1);
end $f$;

-- ---------- guardar: SOLO el autor. Cada llamada es una versión nueva (version_base + 1) ----------
-- p_cambios = [{op: 'nueva' | 'cambia' | 'anula', marca_id, …}]. «nueva» y «cambia» traen el estado COMPLETO de la marca; «anula», el motivo.
-- Si version_base no es la última: 55000 (409) «Este cuaderno cambió en otra pestaña». El sector, el subsector y los conteos de las zonas los calcula el servidor.
create function public.geoportal_analisis_cuaderno_guardar(p_solicitante text, p_id uuid, p_version_base integer, p_titulo text default null, p_descripcion text default null,
                                                           p_vista jsonb default null, p_cambios jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare
  a record; c analisis.cuadernos; v_prev analisis.cuaderno_versiones; v_ult integer; v_ver integer;
  v_titulo text; v_desc text; v_cambios jsonb := coalesce(p_cambios, '[]'::jsonb);
  x jsonb; i integer := 0; v_op text; v_mid uuid; v_tipo text; v_sub text; v_sis text; v_cat text; v_nota text; v_est jsonb; g geometry; v_radio numeric; v_act text; v_mot text;
  v_viejo analisis.marca_versiones; v_filas jsonb := '[]'::jsonb; v_ids uuid[] := '{}'; v_nuevas integer := 0; v_anuladas integer := 0; v_zonas integer := 0;
  v_vigentes integer; v_km2 numeric; v_pred integer; v_cont integer; v_mano_max integer; v_pre text; v_forma text;
begin
  a := analisis.f_acceso(p_solicitante);
  c := analisis.f_cuaderno(a.email, p_id, true);
  perform pg_advisory_xact_lock(hashtextextended('analisis.cuaderno:' || c.id::text, 0));        -- dos «Guardar» a la vez del mismo cuaderno: de a uno
  if analisis.f_archivado(c.id) then perform analisis.f_err('El cuaderno está archivado: reábralo para seguir editando', '55000'); end if;
  v_ult := analisis.f_ultima_version(c.id);
  if p_version_base is null then perform analisis.f_err('Falta la versión de la que parte el cambio'); end if;
  if p_version_base <> v_ult then perform analisis.f_err('Este cuaderno cambió en otra pestaña. Ábralo de nuevo para ver la última versión', '55000'); end if;
  select * into v_prev from analisis.cuaderno_versiones k where k.cuaderno_id = c.id and k.version = v_ult;
  v_ver := v_ult + 1;

  v_titulo := case when p_titulo is null then v_prev.titulo else btrim(p_titulo) end;
  if length(v_titulo) not between 3 and 120 then perform analisis.f_err('El título debe tener entre 3 y 120 letras'); end if;
  v_desc := case when p_descripcion is null then v_prev.descripcion else nullif(btrim(p_descripcion), '') end;       -- '' la borra; sin el dato, queda la anterior
  if length(v_desc) > 1000 then perform analisis.f_err('La descripción no puede pasar de 1.000 letras'); end if;
  if p_vista is not null and (jsonb_typeof(p_vista) <> 'object' or length(p_vista::text) > 4000) then perform analisis.f_err('La vista del mapa no es válida'); end if;
  if jsonb_typeof(v_cambios) <> 'array' then perform analisis.f_err('Los cambios no son válidos'); end if;
  if jsonb_array_length(v_cambios) > analisis.f_parametro('cambios_por_guardado') then perform analisis.f_err('Demasiados cambios en un solo guardado'); end if;
  if jsonb_array_length(v_cambios) = 0 and p_titulo is null and p_descripcion is null and p_vista is null then perform analisis.f_err('No hay cambios para guardar'); end if;
  v_mano_max := analisis.f_parametro('mano_vertices_max');

  for x in select e from jsonb_array_elements(v_cambios) e loop
    i := i + 1; v_pre := 'Marca ' || i || ': ';
    if jsonb_typeof(x) <> 'object' then perform analisis.f_err(v_pre || 'no es válida'); end if;
    v_op := x ->> 'op';
    if v_op is null or v_op not in ('nueva', 'cambia', 'anula') then perform analisis.f_err(v_pre || 'la operación no es válida'); end if;
    begin
      v_mid := nullif(x ->> 'marca_id', '')::uuid;
    exception when others then
      perform analisis.f_err(v_pre || 'el identificador no es válido');
    end;
    if v_op = 'nueva' then
      v_mid := coalesce(v_mid, gen_random_uuid());
      if exists (select 1 from analisis.marcas m where m.id = v_mid) then perform analisis.f_err(v_pre || 'ya existe'); end if;
      v_nuevas := v_nuevas + 1;
    else
      if v_mid is null then perform analisis.f_err(v_pre || 'falta el identificador'); end if;
      select mv.* into v_viejo from analisis.marca_versiones mv where mv.marca_id = v_mid and mv.cuaderno_id = c.id order by mv.version desc limit 1;
      if not found or v_viejo.anulada then perform analisis.f_err(v_pre || 'no existe en este cuaderno o ya está anulada'); end if;
    end if;
    if v_mid = any (v_ids) then perform analisis.f_err(v_pre || 'está repetida en este guardado'); end if;
    v_ids := v_ids || v_mid;

    if v_op = 'anula' then
      v_mot := btrim(coalesce(x ->> 'motivo', ''));
      if length(v_mot) not between 5 and 300 then perform analisis.f_err(v_pre || 'para anularla escriba el motivo (de 5 a 300 letras)'); end if;
      v_anuladas := v_anuladas + 1;
      v_filas := v_filas || jsonb_build_object('marca_id', v_mid, 'nueva', false, 'tipo', v_viejo.tipo, 'subtipo', v_viejo.subtipo, 'sistema', v_viejo.sistema, 'categoria', v_viejo.categoria,
        'nota', v_viejo.nota, 'estilo', v_viejo.estilo, 'geom', v_viejo.geom::text, 'radio_m', v_viejo.radio_m, 'conteo_predios', v_viejo.conteo_predios,
        'conteo_contratos', v_viejo.conteo_contratos, 'activo_codigo', v_viejo.activo_codigo, 'anulada', true, 'motivo', v_mot);
      continue;
    end if;

    v_tipo := x ->> 'tipo';
    if v_tipo is null or v_tipo not in ('problema', 'activo', 'referencia', 'postit', 'mano', 'circulo', 'linea', 'zona') then perform analisis.f_err(v_pre || 'el tipo no es válido'); end if;
    if v_op = 'cambia' and v_tipo <> v_viejo.tipo then perform analisis.f_err(v_pre || 'no se le puede cambiar el tipo'); end if;
    v_sub := nullif(x ->> 'subtipo', ''); v_sis := nullif(x ->> 'sistema', ''); v_cat := nullif(x ->> 'categoria', '');
    v_nota := nullif(btrim(coalesce(x ->> 'nota', '')), ''); v_act := nullif(btrim(coalesce(x ->> 'activo_codigo', '')), '');
    v_est := coalesce(nullif(x -> 'estilo', 'null'::jsonb), '{}'::jsonb);
    if v_tipo in ('problema', 'activo') then
      if v_sub is null or not exists (select 1 from analisis.catalogo k where k.grupo = v_tipo and k.codigo = v_sub and k.activo) then
        perform analisis.f_err(v_pre || case v_tipo when 'problema' then 'elija el problema de la lista' else 'elija el activo de la lista' end);
      end if;
    elsif v_sub is not null then perform analisis.f_err(v_pre || 'ese tipo de marca no lleva subtipo');
    end if;
    if v_tipo = 'activo' then
      if v_sis is null or v_sis not in ('acueducto', 'alcantarillado') then perform analisis.f_err(v_pre || 'elija Acueducto o Alcantarillado'); end if;
      if v_act is not null then perform analisis.f_err(v_pre || 'un ícono de activo es una propuesta y no se enlaza a un activo real'); end if;
    elsif v_sis is not null then perform analisis.f_err(v_pre || 'solo los íconos de activo llevan sistema');
    end if;
    if v_cat is not null and v_cat not in ('problema', 'propuesta', 'obra', 'observacion') then perform analisis.f_err(v_pre || 'la categoría no es válida'); end if;
    if length(v_nota) > 500 then perform analisis.f_err(v_pre || 'la nota no puede pasar de 500 letras'); end if;
    if v_tipo = 'postit' and v_nota is null then perform analisis.f_err(v_pre || 'el post-it necesita su texto'); end if;
    if not analisis.f_estilo_valido(v_est) then perform analisis.f_err(v_pre || 'el color o el grosor no son válidos'); end if;

    g := analisis.f_geom(x -> 'geom');
    if g is null or st_isempty(g) then perform analisis.f_err(v_pre || 'la figura no es válida'); end if;
    v_forma := case when v_tipo in ('mano', 'linea') then 'LINESTRING' when v_tipo = 'zona' then 'POLYGON' else 'POINT' end;
    if geometrytype(g) <> v_forma then perform analisis.f_err(v_pre || 'la figura no corresponde al tipo de marca'); end if;
    if st_npoints(g) > 5000 then perform analisis.f_err(v_pre || 'la figura tiene demasiados puntos'); end if;
    if v_tipo = 'mano' then g := st_simplifypreservetopology(g, 0.00001); end if;                       -- ~1 m: la mano alzada se aligera antes de guardar
    if not st_isvalid(g) then perform analisis.f_err(v_pre || 'la figura no es válida'); end if;
    if not analisis.f_en_valledupar(g) then perform analisis.f_err(v_pre || 'está fuera de Valledupar'); end if;
    if v_tipo = 'mano' and st_npoints(g) > v_mano_max then perform analisis.f_err(v_pre || 'el trazo es demasiado largo: divídalo en dos'); end if;
    if v_tipo = 'linea' and st_npoints(g) > 100 then perform analisis.f_err(v_pre || 'la línea tiene demasiados puntos'); end if;

    v_radio := null; v_pred := null; v_cont := null;
    if v_tipo = 'circulo' then
      begin
        v_radio := round((x ->> 'radio_m')::numeric, 1);
      exception when others then
        v_radio := null;
      end;
      if v_radio is null or v_radio not between 1 and 5000 then perform analisis.f_err(v_pre || 'el radio del círculo debe estar entre 1 y 5.000 m'); end if;
    end if;
    if v_tipo = 'zona' then
      v_km2 := analisis.f_zona_valida(g);
      if v_op = 'cambia' and st_equals(g, v_viejo.geom) then
        v_pred := v_viejo.conteo_predios; v_cont := v_viejo.conteo_contratos;                           -- la zona no se movió: vale su conteo
      else
        v_zonas := v_zonas + 1;
        perform analisis.f_cupo_zona(a.email, 1);
        select z.predios, z.contratos into v_pred, v_cont from analisis.f_conteo_zona(g) z;
        insert into analisis.zona_consultas (solicitante, area_km2, predios, contratos) values (a.email, v_km2, v_pred, v_cont);
      end if;
    end if;
    if v_act is not null then
      if v_act !~ '^[A-Z]{3}-[0-9]{1,9}$' or not exists (select 1 from redes.v_activo_vigente w where w.codigo = v_act) then
        perform analisis.f_err(v_pre || 'el activo ' || left(v_act, 14) || ' no existe');
      end if;
    end if;
    v_filas := v_filas || jsonb_build_object('marca_id', v_mid, 'nueva', v_op = 'nueva', 'tipo', v_tipo, 'subtipo', v_sub, 'sistema', v_sis, 'categoria', v_cat, 'nota', v_nota,
      'estilo', v_est, 'geom', g::text, 'radio_m', v_radio, 'conteo_predios', v_pred, 'conteo_contratos', v_cont, 'activo_codigo', v_act, 'anulada', false, 'motivo', null);
  end loop;

  select count(*) into v_vigentes from (select distinct on (mv.marca_id) mv.anulada from analisis.marca_versiones mv where mv.cuaderno_id = c.id
                                         order by mv.marca_id, mv.version desc) u where not u.anulada;
  if v_vigentes + v_nuevas - v_anuladas > analisis.f_parametro('marcas_por_cuaderno') then
    perform analisis.f_err(format('El cuaderno no puede pasar de %s marcas', analisis.f_parametro('marcas_por_cuaderno')));
  end if;

  insert into analisis.cuaderno_versiones (cuaderno_id, version, titulo, descripcion, vista, autor)
  values (c.id, v_ver, v_titulo, v_desc, coalesce(p_vista, v_prev.vista), a.email);
  insert into analisis.marcas (id, cuaderno_id, creada_en_version)
  select f.marca_id, c.id, v_ver from jsonb_to_recordset(v_filas) as f (marca_id uuid, nueva boolean) where f.nueva;
  -- El sector y el subsector donde cae la marca (su punto, la mitad de la línea o un punto dentro de la zona), de una sola vez
  with sec as materialized (select w.codigo, w.nombre, w.clase, w.geom from redes.v_activo_vigente w where w.prefijo = 'SEC'),
       f as (select t.*, analisis.f_punto(t.geom::geometry) as pt
               from jsonb_to_recordset(v_filas) as t (marca_id uuid, tipo text, subtipo text, sistema text, categoria text, nota text, estilo jsonb, geom text, radio_m numeric,
                                                      conteo_predios integer, conteo_contratos integer, activo_codigo text, anulada boolean, motivo text))
  insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, subtipo, sistema, categoria, nota, estilo, geom, radio_m, conteo_predios, conteo_contratos,
                                        activo_codigo, sector, subsector, anulada, motivo)
  select f.marca_id, c.id, v_ver, f.tipo, f.subtipo, f.sistema, f.categoria, f.nota, f.estilo, f.geom::geometry, f.radio_m, f.conteo_predios, f.conteo_contratos, f.activo_codigo,
         (select left(s.nombre, 80) from sec s where s.clase = 'sector' and st_intersects(s.geom, f.pt) order by s.codigo limit 1),
         (select left(s.nombre, 80) from sec s where s.clase = 'subsector' and st_intersects(s.geom, f.pt) order by s.codigo limit 1),
         f.anulada, f.motivo
    from f;
  return jsonb_build_object('id', c.id, 'version', v_ver, 'marcas', analisis.f_marcas(c.id, v_ver));
end $f$;

-- ---------- archivar o reabrir, con motivo: SOLO el autor ----------
create function public.geoportal_analisis_cuaderno_estado(p_solicitante text, p_id uuid, p_tipo text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; c analisis.cuadernos; v_mot text := btrim(coalesce(p_motivo, '')); v_arch boolean;
begin
  a := analisis.f_acceso(p_solicitante);
  c := analisis.f_cuaderno(a.email, p_id, true);
  if p_tipo is null or p_tipo not in ('archivar', 'reabrir') then perform analisis.f_err('La acción no es válida'); end if;
  if length(v_mot) not between 5 and 300 then perform analisis.f_err('Escriba el motivo (de 5 a 300 letras)'); end if;
  perform pg_advisory_xact_lock(hashtextextended('analisis.cuaderno:' || c.id::text, 0));
  v_arch := analisis.f_archivado(c.id);
  if p_tipo = 'archivar' and v_arch then perform analisis.f_err('El cuaderno ya está archivado', '55000'); end if;
  if p_tipo = 'reabrir' and not v_arch then perform analisis.f_err('El cuaderno no está archivado', '55000'); end if;
  insert into analisis.cuaderno_eventos (cuaderno_id, tipo, motivo, autor) values (c.id, p_tipo, v_mot, a.email);
  return jsonb_build_object('id', c.id, 'archivado', p_tipo = 'archivar');
end $f$;

-- ---------- zona afectada: SOLO los dos números, con tope por hora y área máxima ----------
create function public.geoportal_analisis_zona(p_solicitante text, p_geom jsonb) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; g geometry; v_km2 numeric; v_pred integer; v_cont integer;
begin
  a := analisis.f_acceso(p_solicitante);
  g := analisis.f_geom(p_geom);
  v_km2 := analisis.f_zona_valida(g);
  perform analisis.f_cupo_zona(a.email, 1);
  select z.predios, z.contratos into v_pred, v_cont from analisis.f_conteo_zona(g) z;
  insert into analisis.zona_consultas (solicitante, area_km2, predios, contratos) values (a.email, v_km2, v_pred, v_cont);
  return jsonb_build_object('predios', v_pred, 'contratos', v_cont);
end $f$;

-- ---------- captura · 1: reservar la ruta (la Edge firma la subida de ESA ruta) ----------
create function public.geoportal_analisis_captura_firmar(p_solicitante text, p_id uuid, p_titulo text, p_oeste numeric, p_sur numeric, p_este numeric, p_norte numeric,
                                                         p_ancho integer, p_alto integer, p_bytes integer, p_sha256 text) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; c analisis.cuadernos; v_titulo text := btrim(coalesce(p_titulo, '')); v_id uuid := gen_random_uuid(); v_ruta text; v_n integer; v_lado integer;
begin
  a := analisis.f_acceso(p_solicitante);
  c := analisis.f_cuaderno(a.email, p_id, true);
  if analisis.f_archivado(c.id) then perform analisis.f_err('El cuaderno está archivado: reábralo para guardar capturas', '55000'); end if;
  if length(v_titulo) not between 3 and 120 then perform analisis.f_err('El título de la captura debe tener entre 3 y 120 letras'); end if;
  if p_oeste is null or p_sur is null or p_este is null or p_norte is null or p_oeste not between -180 and 180 or p_este not between -180 and 180
     or p_sur not between -90 and 90 or p_norte not between -90 and 90 or p_oeste >= p_este or p_sur >= p_norte then
    perform analisis.f_err('La extensión de la captura no es válida');
  end if;
  v_lado := analisis.f_parametro('captura_lado_max_px');
  if p_ancho is null or p_alto is null or p_ancho < 16 or p_alto < 16 or greatest(p_ancho, p_alto) > v_lado then
    perform analisis.f_err(format('La captura no puede pasar de %s px de lado', v_lado));
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > analisis.f_parametro('captura_bytes_max') then
    perform analisis.f_err(format('La captura no puede pesar más de %s KB', (analisis.f_parametro('captura_bytes_max') / 1024)::integer));
  end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then perform analisis.f_err('La huella de la captura no es válida'); end if;
  perform pg_advisory_xact_lock(hashtextextended('analisis.cuaderno:' || c.id::text, 0));
  -- Cuentan las confirmadas y las reservadas en los últimos 15 minutos que aún no se confirman (una subida a medias no ocupa el cupo para siempre).
  -- Las ANULADAS no cuentan.
  select count(*) into v_n from analisis.capturas k
   where k.cuaderno_id = c.id and not exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = k.id) and (exists (select 1 from analisis.capturas_confirmadas kc where kc.captura_id = k.id) or k.creado_en > now() - interval '15 minutes');
  if v_n >= analisis.f_parametro('capturas_por_cuaderno') then
    perform analisis.f_err(format('El cuaderno ya tiene sus %s capturas', analisis.f_parametro('capturas_por_cuaderno')::integer), '55000');
  end if;
  v_ruta := c.id::text || '/' || v_id::text || '.jpg';
  insert into analisis.capturas (id, cuaderno_id, ruta, titulo, oeste, sur, este, norte, ancho, alto, bytes, sha256, autor)
  values (v_id, c.id, v_ruta, v_titulo, p_oeste, p_sur, p_este, p_norte, p_ancho, p_alto, p_bytes, p_sha256, a.email);
  return jsonb_build_object('captura_id', v_id, 'ruta', v_ruta);
end $f$;

-- ---------- captura · 2: confirmar que el archivo llegó al bucket, con su tamaño y su tipo ----------
create function public.geoportal_analisis_captura_confirmar(p_solicitante text, p_captura uuid) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; k analisis.capturas; c analisis.cuadernos; v_size bigint; v_mime text;
begin
  a := analisis.f_acceso(p_solicitante);
  select * into k from analisis.capturas x where x.id = p_captura;
  if not found then perform analisis.f_err('La captura no existe', 'P0002'); end if;
  c := analisis.f_cuaderno(a.email, k.cuaderno_id, true);
  if exists (select 1 from analisis.capturas_confirmadas kc where kc.captura_id = k.id) then return jsonb_build_object('captura_id', k.id, 'confirmada', true); end if;
  select nullif(o.metadata ->> 'size', '')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime
    from storage.objects o where o.bucket_id = 'analisis-capturas' and o.name = k.ruta;
  if not found then perform analisis.f_err('La imagen todavía no está en el almacenamiento. Intente de nuevo', '55000'); end if;
  if v_mime is distinct from 'image/jpeg' then perform analisis.f_err('La captura debe ser una imagen JPEG'); end if;
  if v_size is null or v_size < 1 or v_size > analisis.f_parametro('captura_bytes_max') then perform analisis.f_err('La captura pesa más de lo permitido'); end if;
  if v_size <> k.bytes then perform analisis.f_err('La imagen que llegó no es la que se anunció'); end if;
  insert into analisis.capturas_confirmadas (captura_id, bytes_reales, autor) values (k.id, v_size::integer, a.email);
  return jsonb_build_object('captura_id', k.id, 'confirmada', true);
end $f$;

-- ---------- captura · anular: SOLO el autor, con motivo. No se borra el archivo ni la fila; deja de mostrarse y de contar para el tope ----------
create function public.geoportal_analisis_captura_anular(p_solicitante text, p_captura uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, analisis, pg_temp as $f$
declare a record; k analisis.capturas; c analisis.cuadernos; v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  a := analisis.f_acceso(p_solicitante);
  select x.* into k from analisis.capturas x join analisis.capturas_confirmadas kc on kc.captura_id = x.id where x.id = p_captura;
  if not found then perform analisis.f_err('La captura no existe', 'P0002'); end if;
  c := analisis.f_cuaderno(a.email, k.cuaderno_id, true);
  if analisis.f_archivado(c.id) then perform analisis.f_err('El cuaderno está archivado: reábralo para anular capturas', '55000'); end if;
  if length(v_motivo) not between 5 and 300 then perform analisis.f_err('Para anular la captura escriba el motivo (de 5 a 300 letras)'); end if;
  perform pg_advisory_xact_lock(hashtextextended('analisis.cuaderno:' || c.id::text, 0));
  if exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = k.id) then perform analisis.f_err('La captura ya está anulada', '55000'); end if;
  insert into analisis.capturas_anuladas (captura_id, motivo, autor) values (k.id, v_motivo, a.email);
  return jsonb_build_object('captura_id', k.id, 'anulada', true);
end $f$;

-- ---------- captura · 3: la ruta de una captura confirmada (la Edge firma la lectura de 60 s) ----------
create function public.geoportal_analisis_captura_ruta(p_solicitante text, p_captura uuid) returns jsonb
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record; k analisis.capturas; c analisis.cuadernos;
begin
  a := analisis.f_acceso(p_solicitante);
  select x.* into k from analisis.capturas x join analisis.capturas_confirmadas kc on kc.captura_id = x.id where x.id = p_captura
     and not exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = x.id);        -- una captura anulada ya no se abre
  if not found then perform analisis.f_err('La captura no existe', 'P0002'); end if;
  c := analisis.f_cuaderno(a.email, k.cuaderno_id);
  return jsonb_build_object('captura_id', k.id, 'ruta', k.ruta, 'titulo', k.titulo);
end $f$;

-- ---------- exportar: las marcas vigentes de la última versión, en filas, y la lista de capturas ----------
create function public.geoportal_analisis_cuaderno_exportar(p_solicitante text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, analisis, pg_temp as $f$
declare a record; c analisis.cuadernos; v analisis.cuaderno_versiones;
begin
  a := analisis.f_acceso(p_solicitante);
  c := analisis.f_cuaderno(a.email, p_id);
  select * into v from analisis.cuaderno_versiones x where x.cuaderno_id = c.id and x.version = analisis.f_ultima_version(c.id);
  return jsonb_build_object(
    'cuaderno', jsonb_build_object('id', c.id, 'titulo', v.titulo, 'descripcion', v.descripcion, 'autor', c.autor, 'version', v.version, 'guardado_en', v.creado_en),
    'marcas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'n', u.n, 'tipo', u.tipo, 'subtipo', u.subtipo, 'nombre', (select k.nombre from analisis.catalogo k where k.grupo = u.tipo and k.codigo = u.subtipo),
               'sistema', u.sistema, 'categoria', u.categoria, 'nota', u.nota, 'sector', u.sector, 'subsector', u.subsector, 'activo_codigo', u.activo_codigo,
               'predios', u.conteo_predios, 'contratos', u.conteo_contratos, 'radio_m', u.radio_m,
               'longitud_m', case when geometrytype(u.geom) = 'LINESTRING' then round(st_length(u.geom::geography)::numeric, 1) end,
               'area_m2', case when geometrytype(u.geom) = 'POLYGON' then round(st_area(u.geom::geography)::numeric, 0) end,
               'lon', round(st_x(analisis.f_punto(u.geom))::numeric, 6), 'lat', round(st_y(analisis.f_punto(u.geom))::numeric, 6),
               'creada_en_version', u.creada_en_version, 'cambiada_en_version', u.version) order by u.n)
        from (select w.*, row_number() over (order by w.creada_en_version, w.creado_en, w.marca_id) as n
                from (select distinct on (mv.marca_id) mv.*, m.creada_en_version, m.creado_en
                        from analisis.marca_versiones mv join analisis.marcas m on m.id = mv.marca_id
                       where mv.cuaderno_id = c.id order by mv.marca_id, mv.version desc) w
               where not w.anulada) u), '[]'::jsonb),
    'capturas', coalesce((select jsonb_agg(jsonb_build_object('titulo', k.titulo, 'creado_en', k.creado_en, 'ancho', k.ancho, 'alto', k.alto, 'bytes', kc.bytes_reales,
                                 'oeste', k.oeste, 'sur', k.sur, 'este', k.este, 'norte', k.norte) order by k.creado_en, k.id)
                            from analisis.capturas k join analisis.capturas_confirmadas kc on kc.captura_id = k.id where k.cuaderno_id = c.id and not exists (select 1 from analisis.capturas_anuladas ka where ka.captura_id = k.id)), '[]'::jsonb));
end $f$;
