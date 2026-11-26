-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 70 — PRUEBAS «N de N». Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- Todo es SIMULADO y se deshace: sus personas (prueba.cuad.*), sus cuadernos (título «ZTCUAD …») y sus archivos en el bucket (solo la fila de storage.objects).
-- Lee el catastro y los sectores reales solo para comparar números; no los cambia. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE ANÁLISIS · CUADERNOS … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- Un «guardar» con UNA marca que debe ser rechazada con 22023 y ese texto
create function pg_temp.mala(p_nombre text, p_quien text, p_id uuid, p_base integer, p_marca text, p_texto text, p_estado text default '22023') returns void language sql as $$
  select pg_temp.err(p_nombre, format('select public.geoportal_analisis_cuaderno_guardar(%L, %L, %s, null, null, null, %L::jsonb)', p_quien, p_id, p_base, '[' || p_marca || ']'), p_estado, p_texto) $$;
create function pg_temp.pt(p_x numeric, p_y numeric) returns text language sql as $$ select format('{"type":"Point","coordinates":[%s,%s]}', p_x, p_y) $$;
create function pg_temp.cuadro(p_x numeric, p_y numeric, p_l numeric) returns text language sql as $$
  select format('{"type":"Polygon","coordinates":[[[%s,%s],[%s,%s],[%s,%s],[%s,%s],[%s,%s]]]}', p_x, p_y, p_x + p_l, p_y, p_x + p_l, p_y + p_l, p_x, p_y + p_l, p_x, p_y) $$;

do $prueba$
declare
  adm text := 'prueba.cuad.adm@emdupar.gov.co'; sp text := 'prueba.cuad.sp@emdupar.gov.co'; sd text := 'prueba.cuad.sd@emdupar.gov.co';
  op text := 'prueba.cuad.op@emdupar.gov.co'; op2 text := 'prueba.cuad.op2@emdupar.gov.co'; dual text := 'prueba.cuad.dual@emdupar.gov.co';
  nadie text := 'prueba.cuad.nadie@emdupar.gov.co'; fuera text := 'prueba.cuad.fuera@emdupar.gov.co';
  tablas text[] := array['catalogo', 'parametros', 'cuadernos', 'cuaderno_versiones', 'cuaderno_eventos', 'marcas', 'marca_versiones', 'capturas', 'capturas_confirmadas', 'zona_consultas'];
  rpcs text[] := array['geoportal_analisis_perfil', 'geoportal_analisis_cuadernos', 'geoportal_analisis_cuaderno', 'geoportal_analisis_cuaderno_crear', 'geoportal_analisis_cuaderno_guardar',
                       'geoportal_analisis_cuaderno_estado', 'geoportal_analisis_zona', 'geoportal_analisis_captura_firmar', 'geoportal_analisis_captura_confirmar',
                       'geoportal_analisis_captura_ruta', 'geoportal_analisis_cuaderno_exportar'];
  llamadas text[]; t text; q text; quien text; i integer;
  j jsonb; m jsonb; v_id uuid; v_id2 uuid; v_adm uuid; v_cap uuid; v_cap2 uuid; v_ruta text; v_n integer; v_n2 integer; v_txt text; v_act text;
  m_prob uuid; m_act uuid; m_ref uuid; m_post uuid; m_mano uuid; m_circ uuid; m_lin uuid; m_zona uuid;
  zona text := pg_temp.cuadro(-73.2560, 10.4640, 0.0060);            -- ~0,44 km² dentro de la ciudad
  zona2 text := pg_temp.cuadro(-73.2500, 10.4700, 0.0040);
  mano text; v_total integer; v_bien integer; v_fallas text;
begin
  -- ---------- personas de prueba: los 5 perfiles (y un segundo supervisor, un operador sin la casilla y alguien fuera de la lista) ----------
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTCUAD Administrador', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZTCUAD Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZTCUAD Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values
    (op, 'ZTCUAD Operador con el geovisor', 'consulta', true, 'sin_restriccion', 'todos'), (op2, 'ZTCUAD Operador sin el geovisor', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_comercial, ver_registro_tecnico, horario, dias) values (dual, 'ZTCUAD Dual (Comercial y Técnica)', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (nadie, 'ZTCUAD Sin permisos', 'consulta', 'sin_restriccion', 'todos');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZTCUAD necesita ver la red en la calle');

  -- ===================== 00. Estructura y permisos =====================
  perform pg_temp.reg('00.01 las 10 tablas existen, con RLS activado y SIN políticas',
    (select count(*) = 10 and bool_and(c.relrowsecurity) from pg_class c where c.relnamespace = 'analisis'::regnamespace and c.relkind = 'r' and c.relname = any (tablas))
    and (select count(*) from pg_class c where c.relnamespace = 'analisis'::regnamespace and c.relkind = 'r') = 10
    and not exists (select 1 from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'analisis'::regnamespace));
  perform pg_temp.reg('00.02 ninguna tabla da privilegios a public, anon, authenticated ni service_role',
    not exists (select 1 from pg_class c, unnest(array['anon', 'authenticated', 'service_role']) r, unnest(array['select', 'insert', 'update', 'delete', 'truncate']) p
                 where c.relnamespace = 'analisis'::regnamespace and c.relkind = 'r' and has_table_privilege(r, c.oid, p))
    and not exists (select 1 from pg_class c, aclexplode(c.relacl) a where c.relnamespace = 'analisis'::regnamespace and a.grantee = 0));
  perform pg_temp.reg('00.03 el esquema no da USAGE a la API (solo al Dell)',
    not has_schema_privilege('anon', 'analisis', 'usage') and not has_schema_privilege('authenticated', 'analisis', 'usage') and not has_schema_privilege('service_role', 'analisis', 'usage')
    and has_schema_privilege('homelab_lectura', 'analisis', 'usage') and not has_schema_privilege('homelab_lectura', 'analisis', 'create'));
  perform pg_temp.reg('00.04 homelab_lectura: SELECT en las 10 tablas y nada más',
    (select bool_and(has_table_privilege('homelab_lectura', c.oid, 'select') and not has_table_privilege('homelab_lectura', c.oid, 'insert')
                     and not has_table_privilege('homelab_lectura', c.oid, 'update') and not has_table_privilege('homelab_lectura', c.oid, 'delete')
                     and not has_table_privilege('homelab_lectura', c.oid, 'truncate'))
       from pg_class c where c.relnamespace = 'analisis'::regnamespace and c.relkind = 'r'));
  perform pg_temp.reg('00.05 las 11 RPC public.geoportal_analisis_* son las del paquete',
    (select array_agg(distinct p.proname::text order by p.proname::text) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%')
      = (select array_agg(x order by x) from unnest(rpcs) x)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%') = 11);
  perform pg_temp.reg('00.06 las 11 RPC son SECURITY DEFINER con search_path fijo',
    (select bool_and(p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')) from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%'),
    (select string_agg(p.proname, ', ') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%'
        and not (p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))));
  perform pg_temp.reg('00.07 las 11 RPC: EXECUTE para service_role y NO para public, anon ni authenticated',
    (select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
                     and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%'));
  perform pg_temp.reg('00.08 las funciones internas del esquema analisis: sin EXECUTE para public, anon, authenticated ni service_role',
    (select count(*) > 10 and bool_and(not has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
                     and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0))
       from pg_proc p where p.pronamespace = 'analisis'::regnamespace));
  perform pg_temp.reg('00.09 TODA función del paquete lleva search_path fijo (también las que no son SECURITY DEFINER)',
    (select bool_and(exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')) from pg_proc p
      where p.pronamespace = 'analisis'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%')));
  perform pg_temp.reg('00.10 cada tabla tiene sus dos disparadores de solo agregar: por fila (UPDATE y DELETE) y por sentencia (TRUNCATE)',
    (select count(*) = 20 and count(*) filter (where (g.tgtype & 32) = 32 and (g.tgtype & 1) = 0) = 10            -- 32 = TRUNCATE, 1 = por fila
            and count(*) filter (where (g.tgtype & 16) = 16 and (g.tgtype & 8) = 8 and (g.tgtype & 1) = 1) = 10     -- 16 = UPDATE, 8 = DELETE
            and bool_and(g.tgenabled = 'O' and (g.tgtype & 2) = 2 and g.tgfoid = 'analisis.f_solo_agregar()'::regprocedure)
       from pg_trigger g join pg_class c on c.oid = g.tgrelid where not g.tgisinternal and c.relnamespace = 'analisis'::regnamespace));
  foreach t in array tablas loop
    perform pg_temp.err('00.11 TRUNCATE bloqueado en analisis.' || t, format('truncate analisis.%I cascade', t), '42501', 'TRUNCATE no permitido');
  end loop;
  perform pg_temp.reg('00.12 el catálogo: los 9 problemas con su color y los 12 íconos de activo (sin color: lo pone el sistema)',
    (select array_agg(codigo order by orden) from analisis.catalogo where grupo = 'problema') = array['falla_acueducto', 'falla_alcantarillado', 'sin_acueducto', 'sin_alcantarillado',
       'baja_presion', 'fuga_visible', 'agua_turbia', 'rebose_alcantarillado', 'valvula_revisar']
    and (select array_agg(codigo order by orden) from analisis.catalogo where grupo = 'activo') = array['tanque', 'tuberia', 'valvula', 'macromedidor', 'sensor', 'pozo', 'sumidero',
       'acometida', 'colector', 'torre', 'planta', 'vertimiento']
    and (select bool_and((grupo = 'problema') = (color is not null)) from analisis.catalogo));
  perform pg_temp.reg('00.13 los topes: 20 capturas, 1.600 px, 600 KB, 500 marcas, 500 vértices, 25 km², 120 conteos por hora',
    analisis.f_parametro('capturas_por_cuaderno') = 20 and analisis.f_parametro('captura_lado_max_px') = 1600 and analisis.f_parametro('captura_bytes_max') = 614400
    and analisis.f_parametro('marcas_por_cuaderno') = 500 and analisis.f_parametro('mano_vertices_max') = 500 and analisis.f_parametro('zona_area_max_km2') = 25
    and analisis.f_parametro('zona_conteos_por_hora') = 120 and analisis.f_parametro('cambios_por_guardado') = 500);
  perform pg_temp.reg('00.14 pg-safeupdate: ninguna función del paquete (ni de redes o técnica) con DELETE/UPDATE sin WHERE',
    not exists (select 1 from analisis.f_funciones_sin_where()) and not exists (select 1 from redes.f_funciones_sin_where()),
    (select string_agg(funcion, ', ') from analisis.f_funciones_sin_where()));
  perform pg_temp.reg('00.15 la revisión de «sin WHERE» sí mira las funciones del paquete (19 o más)',
    (select count(*) from pg_proc p where p.pronamespace = 'analisis'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%')) >= 19);
  perform pg_temp.reg('00.16 el bucket analisis-capturas es privado, solo JPEG y de 600 KB',
    exists (select 1 from storage.buckets where id = 'analisis-capturas' and not public and file_size_limit = 614400 and allowed_mime_types = array['image/jpeg']));
  perform pg_temp.reg('00.17 ninguna tabla guarda nombre, teléfono, dirección ni cédula de suscriptores (solo el nombre del catálogo)',
    not exists (select 1 from information_schema.columns where table_schema = 'analisis' and column_name ~ '(telefono|direccion|cedula|suscriptor|contrato$|cod_usuario)')
    and (select array_agg(table_name::text) from information_schema.columns where table_schema = 'analisis' and column_name = 'nombre') = array['catalogo']);

  -- ===================== 01. Quién entra (5 perfiles) =====================
  j := public.geoportal_analisis_perfil(sp);
  perform pg_temp.reg('01.01 el supervisor de planta entra: catálogo (21), topes (8), sistemas y categorías',
    jsonb_array_length(j -> 'catalogo') = 21 and (select count(*) from jsonb_object_keys(j -> 'topes')) = 8 and j ->> 'email' = sp and (j ->> 'admin')::boolean = false
    and j -> 'sistemas' ->> 'acueducto' = '#1F5FA8' and j -> 'sistemas' ->> 'alcantarillado' = '#8A5A2B' and jsonb_array_length(j -> 'categorias') = 4);
  perform pg_temp.reg('01.02 el supervisor de distribución y el administrador también entran',
    public.geoportal_analisis_perfil(sd) ->> 'email' = sd and (public.geoportal_analisis_perfil(adm) ->> 'admin')::boolean);
  perform pg_temp.reg('01.03 el correo se normaliza (mayúsculas y espacios)', public.geoportal_analisis_perfil('  ' || upper(sp) || ' ') ->> 'email' = sp);
  -- cada RPC, con cada perfil sin acceso: 42501 (403). Los argumentos son válidos de forma: el rechazo es por permiso, no por el dato
  v_id := gen_random_uuid();
  llamadas := array[
    'geoportal_analisis_perfil(%L)', 'geoportal_analisis_cuadernos(%L)', format('geoportal_analisis_cuaderno(%%L, %L)', v_id), 'geoportal_analisis_cuaderno_crear(%L, ''ZTCUAD no debe crearse'')',
    format('geoportal_analisis_cuaderno_guardar(%%L, %L, 1, ''ZTCUAD x'')', v_id), format('geoportal_analisis_cuaderno_estado(%%L, %L, ''archivar'', ''ZTCUAD motivo'')', v_id),
    format('geoportal_analisis_zona(%%L, %L::jsonb)', zona),
    format('geoportal_analisis_captura_firmar(%%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', v_id, repeat('a', 64)),
    format('geoportal_analisis_captura_confirmar(%%L, %L)', v_id), format('geoportal_analisis_captura_ruta(%%L, %L)', v_id), format('geoportal_analisis_cuaderno_exportar(%%L, %L)', v_id)];
  for i in 1 .. array_length(llamadas, 1) loop
    foreach quien in array array[op, op2, dual, nadie, fuera] loop
      perform pg_temp.err(format('01.04 %s · %s → 403', rpcs[i], split_part(split_part(quien, '@', 1), '.', 3)), 'select public.' || format(llamadas[i], quien), '42501');
    end loop;
    perform pg_temp.err(format('01.05 %s · sin solicitante → 401', rpcs[i]), 'select public.' || format(llamadas[i], ''), '28000');
  end loop;
  perform pg_temp.reg('01.06 los rechazados no dejaron nada escrito', not exists (select 1 from analisis.cuadernos) and not exists (select 1 from analisis.zona_consultas));
  perform pg_temp.reg('01.07 el operador con la casilla SÍ tiene el geovisor (solo lectura): el 403 es de los cuadernos, no del geovisor',
    redes.f_geovisor_lectura(op) and not redes.f_geovisor_lectura(op2) and not (redes.f_geovisor_acceso(op)).completo);

  -- ===================== 02. Crear y listar =====================
  j := public.geoportal_analisis_cuaderno_crear(sp, '  ZTCUAD Cuaderno del POIR  ', '  Zonas con baja presión  ', '{"centro":[-73.25,10.46],"zoom":14,"tematica":"edad"}');
  v_id := (j ->> 'id')::uuid;
  perform pg_temp.reg('02.01 crear: nace con la versión 1, del autor, con el título y la descripción recortados',
    (j ->> 'version')::integer = 1 and (select autor = sp and modulo = 'tecnica' from analisis.cuadernos where id = v_id)
    and (select titulo = 'ZTCUAD Cuaderno del POIR' and descripcion = 'Zonas con baja presión' and vista ->> 'tematica' = 'edad' and autor = sp from analisis.cuaderno_versiones where cuaderno_id = v_id and version = 1));
  perform pg_temp.err('02.02 un título de 2 letras no entra', format('select public.geoportal_analisis_cuaderno_crear(%L, ''ab'')', sp), '22023', 'título');
  perform pg_temp.err('02.03 un título de 121 letras no entra', format('select public.geoportal_analisis_cuaderno_crear(%L, %L)', sp, repeat('x', 121)), '22023', 'título');
  perform pg_temp.err('02.04 una vista que no es un objeto no entra', format('select public.geoportal_analisis_cuaderno_crear(%L, ''ZTCUAD x'', null, ''[1]''::jsonb)', sp), '22023', 'vista');
  v_adm := (public.geoportal_analisis_cuaderno_crear(adm, 'ZTCUAD Cuaderno del administrador') ->> 'id')::uuid;
  j := public.geoportal_analisis_cuadernos(sd);
  perform pg_temp.reg('02.05 el otro supervisor ve los dos cuadernos del equipo, sin ser suyos, con autor, versión y conteos en cero',
    (select count(*) = 2 and bool_and(not (x ->> 'es_mio')::boolean and (x ->> 'version')::integer = 1 and (x ->> 'marcas')::integer = 0 and (x ->> 'capturas')::integer = 0
                                      and not (x ->> 'archivado')::boolean)
       from jsonb_array_elements(j -> 'cuadernos') x where x ->> 'titulo' like 'ZTCUAD%')
    and (select x ->> 'autor_nombre' from jsonb_array_elements(j -> 'cuadernos') x where x ->> 'id' = v_id::text) = 'ZTCUAD Supervisor de planta');
  perform pg_temp.reg('02.06 el autor ve el suyo marcado como propio',
    (select (x ->> 'es_mio')::boolean from jsonb_array_elements(public.geoportal_analisis_cuadernos(sp) -> 'cuadernos') x where x ->> 'id' = v_id::text));

  -- ===================== 03. Guardar: marcas de los 8 tipos =====================
  select w.codigo into v_act from redes.v_activo_vigente w where w.prefijo = 'VAL' order by w.codigo limit 1;
  select string_agg(format('[%s,%s]', -73.2500 - g * 0.00002, 10.4600 + (g % 2) * 0.0000002 + g * 0.00002), ',' order by g) into mano from generate_series(0, 299) g;   -- 300 puntos casi en línea
  mano := '{"type":"LineString","coordinates":[' || mano || ']}';
  m_prob := gen_random_uuid(); m_act := gen_random_uuid(); m_ref := gen_random_uuid(); m_post := gen_random_uuid();
  m_mano := gen_random_uuid(); m_circ := gen_random_uuid(); m_lin := gen_random_uuid(); m_zona := gen_random_uuid();
  j := public.geoportal_analisis_cuaderno_guardar(sp, v_id, 1, null, null, null, format($j$[
    {"op":"nueva","marca_id":"%s","tipo":"problema","subtipo":"valvula_revisar","categoria":"problema","nota":"  ZTCUAD revisar esta válvula  ","geom":%s,"activo_codigo":"%s"},
    {"op":"nueva","marca_id":"%s","tipo":"activo","subtipo":"tanque","sistema":"acueducto","categoria":"propuesta","nota":"ZTCUAD aquí va un tanque nuevo","geom":%s},
    {"op":"nueva","marca_id":"%s","tipo":"referencia","estilo":{"color":"#00AA55"},"geom":%s},
    {"op":"nueva","marca_id":"%s","tipo":"postit","nota":"ZTCUAD post-it","estilo":{"color":"#FFE066"},"geom":%s},
    {"op":"nueva","marca_id":"%s","tipo":"mano","estilo":{"color":"#D00000","grosor":4},"geom":%s},
    {"op":"nueva","marca_id":"%s","tipo":"circulo","radio_m":150.26,"geom":%s},
    {"op":"nueva","marca_id":"%s","tipo":"linea","categoria":"obra","geom":{"type":"LineString","coordinates":[[-73.2550,10.4650],[-73.2540,10.4660]]}},
    {"op":"nueva","marca_id":"%s","tipo":"zona","nota":"ZTCUAD zona afectada","geom":%s}]$j$,
    m_prob, pg_temp.pt(-73.2530, 10.4660), v_act, m_act, pg_temp.pt(-73.2535, 10.4665), m_ref, pg_temp.pt(-73.2540, 10.4670), m_post, pg_temp.pt(-73.2545, 10.4675),
    m_mano, mano, m_circ, pg_temp.pt(-73.2520, 10.4655), m_lin, m_zona, zona)::jsonb);
  perform pg_temp.reg('03.01 guardar: versión 2 con las 8 marcas (una de cada tipo)',
    (j ->> 'version')::integer = 2 and jsonb_array_length(j -> 'marcas') = 8
    and (select count(distinct x ->> 'tipo') from jsonb_array_elements(j -> 'marcas') x) = 8 and (select count(*) from analisis.marcas where cuaderno_id = v_id and creada_en_version = 2) = 8);
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_prob::text;
  perform pg_temp.reg('03.02 el problema: subtipo, categoría, nota recortada y el activo real enlazado',
    m ->> 'subtipo' = 'valvula_revisar' and m ->> 'categoria' = 'problema' and m ->> 'nota' = 'ZTCUAD revisar esta válvula' and m ->> 'activo_codigo' = v_act and m ->> 'sistema' is null);
  perform pg_temp.reg('03.03 el sector y el subsector los anota el servidor (los mismos que da el mapa de sectores para ese punto)',
    m ->> 'sector' is not distinct from (select w.nombre from redes.v_activo_vigente w where w.prefijo = 'SEC' and w.clase = 'sector'
                                           and st_intersects(w.geom, st_setsrid(st_makepoint(-73.2530, 10.4660), 4326)) order by w.codigo limit 1)
    and m ->> 'subsector' is not distinct from (select w.nombre from redes.v_activo_vigente w where w.prefijo = 'SEC' and w.clase = 'subsector'
                                           and st_intersects(w.geom, st_setsrid(st_makepoint(-73.2530, 10.4660), 4326)) order by w.codigo limit 1)
    and (select count(*) from analisis.marca_versiones where cuaderno_id = v_id and sector is not null) > 0, m ->> 'sector' || ' · ' || coalesce(m ->> 'subsector', '—'));
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_act::text;
  perform pg_temp.reg('03.04 el ícono de activo: su código, el sistema y la categoría; no se enlaza a ningún activo real',
    m ->> 'subtipo' = 'tanque' and m ->> 'sistema' = 'acueducto' and m ->> 'categoria' = 'propuesta' and m ->> 'activo_codigo' is null);
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_mano::text;
  perform pg_temp.reg('03.05 la mano alzada se simplifica antes de guardar (300 puntos casi en línea quedan en muchos menos) y conserva su color y grosor',
    jsonb_array_length(m -> 'geom' -> 'coordinates') < 30 and m -> 'estilo' ->> 'color' = '#D00000' and (m -> 'estilo' ->> 'grosor')::integer = 4,
    jsonb_array_length(m -> 'geom' -> 'coordinates') || ' puntos');
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_circ::text;
  perform pg_temp.reg('03.06 el círculo: un punto con su radio en metros (un decimal)', (m ->> 'radio_m')::numeric = 150.3 and m -> 'geom' ->> 'type' = 'Point');
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_zona::text;
  select count(*), count(distinct cod_usuario) filter (where btrim(coalesce(cod_usuario, '')) <> '') into v_n, v_n2
    from public.catastro_valledupar where st_intersects(geom, st_setsrid(st_geomfromgeojson(zona), 4326));
  perform pg_temp.reg('03.07 la zona: los predios y los contratos los cuenta el servidor (iguales al catastro)',
    (m ->> 'conteo_predios')::integer = v_n and (m ->> 'conteo_contratos')::integer = v_n2 and v_n > 0, v_n || ' predios · ' || v_n2 || ' contratos');
  perform pg_temp.reg('03.08 las demás marcas no llevan conteos ni radio',
    (select bool_and(x ->> 'conteo_predios' is null and x ->> 'conteo_contratos' is null) from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' <> 'zona')
    and (select bool_and(x ->> 'radio_m' is null) from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' <> 'circulo'));
  perform pg_temp.reg('03.09 el conteo de la zona quedó en el registro de consultas (solo números)',
    (select count(*) = 1 and bool_and(predios = v_n and contratos = v_n2 and area_km2 between 0.3 and 0.6) from analisis.zona_consultas where solicitante = sp));
  perform pg_temp.reg('03.10 el título y la vista siguen los de la versión anterior cuando no se mandan',
    (select titulo = 'ZTCUAD Cuaderno del POIR' and vista ->> 'tematica' = 'edad' and descripcion = 'Zonas con baja presión' from analisis.cuaderno_versiones where cuaderno_id = v_id and version = 2));

  -- quién guarda
  perform pg_temp.mala('03.11 otro supervisor NO edita el cuaderno ajeno', sd, v_id, 2, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'Solo el autor', '42501');
  perform pg_temp.mala('03.12 el administrador tampoco edita el cuaderno ajeno', adm, v_id, 2, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'Solo el autor', '42501');
  perform pg_temp.mala('03.13 guardar sobre una versión vieja → 409 «cambió en otra pestaña»', sp, v_id, 1, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'otra pestaña', '55000');
  perform pg_temp.mala('03.14 guardar sobre una versión que aún no existe → 409', sp, v_id, 3, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'otra pestaña', '55000');
  perform pg_temp.err('03.15 guardar sin nada que cambiar no crea versión', format('select public.geoportal_analisis_cuaderno_guardar(%L, %L, 2)', sp, v_id), '22023', 'No hay cambios');
  perform pg_temp.err('03.16 un cuaderno que no existe → 404', format('select public.geoportal_analisis_cuaderno_guardar(%L, %L, 1, ''ZTCUAD x'')', sp, gen_random_uuid()), 'P0002');
  -- lo que no entra (cada regla, con su texto)
  perform pg_temp.mala('03.17 operación desconocida', sp, v_id, 2, '{"op":"borra"}', 'operación');
  perform pg_temp.mala('03.18 tipo desconocido', sp, v_id, 2, format('{"op":"nueva","tipo":"estrella","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'tipo');
  perform pg_temp.mala('03.19 un problema que no está en la lista', sp, v_id, 2, format('{"op":"nueva","tipo":"problema","subtipo":"otro","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'elija el problema');
  perform pg_temp.mala('03.20 un problema con código de activo', sp, v_id, 2, format('{"op":"nueva","tipo":"problema","subtipo":"tanque","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'elija el problema');
  perform pg_temp.mala('03.21 un ícono de activo sin sistema', sp, v_id, 2, format('{"op":"nueva","tipo":"activo","subtipo":"pozo","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'Acueducto o Alcantarillado');
  perform pg_temp.mala('03.22 un ícono de activo enlazado a un activo real', sp, v_id, 2,
    format('{"op":"nueva","tipo":"activo","subtipo":"valvula","sistema":"acueducto","activo_codigo":"%s","geom":%s}', v_act, pg_temp.pt(-73.25, 10.46)), 'no se enlaza');
  perform pg_temp.mala('03.23 un post-it con sistema', sp, v_id, 2, format('{"op":"nueva","tipo":"postit","nota":"x","sistema":"acueducto","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'sistema');
  perform pg_temp.mala('03.24 una referencia con subtipo', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","subtipo":"tanque","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'subtipo');
  perform pg_temp.mala('03.25 categoría desconocida', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","categoria":"urgente","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'categoría');
  perform pg_temp.mala('03.26 nota de 501 letras', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","nota":"%s","geom":%s}', repeat('n', 501), pg_temp.pt(-73.25, 10.46)), '500 letras');
  perform pg_temp.mala('03.27 post-it sin texto', sp, v_id, 2, format('{"op":"nueva","tipo":"postit","nota":"   ","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'necesita su texto');
  perform pg_temp.mala('03.28 estilo con una clave que no es color ni grosor', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","estilo":{"color":"#112233","url":"x"},"geom":%s}', pg_temp.pt(-73.25, 10.46)), 'color o el grosor');
  perform pg_temp.mala('03.29 color que no es #RRGGBB', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","estilo":{"color":"red"},"geom":%s}', pg_temp.pt(-73.25, 10.46)), 'color o el grosor');
  perform pg_temp.mala('03.30 grosor 40', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","estilo":{"grosor":40},"geom":%s}', pg_temp.pt(-73.25, 10.46)), 'color o el grosor');
  perform pg_temp.mala('03.31 sin figura', sp, v_id, 2, '{"op":"nueva","tipo":"referencia"}', 'figura no es válida');
  perform pg_temp.mala('03.32 figura ilegible', sp, v_id, 2, '{"op":"nueva","tipo":"referencia","geom":{"type":"Point","coordinates":"x"}}', 'figura no es válida');
  perform pg_temp.mala('03.33 un punto con tipo zona', sp, v_id, 2, format('{"op":"nueva","tipo":"zona","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'no corresponde');
  perform pg_temp.mala('03.34 un polígono con tipo problema', sp, v_id, 2, format('{"op":"nueva","tipo":"problema","subtipo":"fuga_visible","geom":%s}', zona), 'no corresponde');
  perform pg_temp.mala('03.35 un punto en Bogotá', sp, v_id, 2, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-74.08, 4.60)), 'fuera de Valledupar');
  perform pg_temp.mala('03.36 una zona en corbatín (inválida)', sp, v_id, 2,
    '{"op":"nueva","tipo":"zona","geom":{"type":"Polygon","coordinates":[[[-73.25,10.46],[-73.24,10.47],[-73.24,10.46],[-73.25,10.47],[-73.25,10.46]]]}}', 'figura no es válida');
  perform pg_temp.mala('03.37 una zona de más de 25 km²', sp, v_id, 2, format('{"op":"nueva","tipo":"zona","geom":%s}', pg_temp.cuadro(-73.30, 10.40, 0.09)), 'demasiado grande');
  perform pg_temp.mala('03.38 un círculo sin radio', sp, v_id, 2, format('{"op":"nueva","tipo":"circulo","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'radio');
  perform pg_temp.mala('03.39 un círculo de 6 km de radio', sp, v_id, 2, format('{"op":"nueva","tipo":"circulo","radio_m":6000,"geom":%s}', pg_temp.pt(-73.25, 10.46)), 'radio');
  perform pg_temp.mala('03.40 un activo real que no existe', sp, v_id, 2, format('{"op":"nueva","tipo":"problema","subtipo":"fuga_visible","activo_codigo":"VAL-999999999","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'no existe');
  perform pg_temp.mala('03.41 un código de activo con otra forma', sp, v_id, 2, format('{"op":"nueva","tipo":"problema","subtipo":"fuga_visible","activo_codigo":"x'' or 1=1","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'no existe');
  perform pg_temp.mala('03.42 una marca nueva con un identificador que ya existe', sp, v_id, 2, format('{"op":"nueva","marca_id":"%s","tipo":"referencia","geom":%s}', m_ref, pg_temp.pt(-73.25, 10.46)), 'ya existe');
  perform pg_temp.mala('03.43 identificador que no es UUID', sp, v_id, 2, format('{"op":"nueva","marca_id":"abc","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'identificador');
  perform pg_temp.mala('03.44 cambiar una marca que no es de este cuaderno', sp, v_id, 2, format('{"op":"cambia","marca_id":"%s","tipo":"referencia","geom":%s}', gen_random_uuid(), pg_temp.pt(-73.25, 10.46)), 'no existe en este cuaderno');
  perform pg_temp.mala('03.45 cambiarle el tipo a una marca', sp, v_id, 2, format('{"op":"cambia","marca_id":"%s","tipo":"postit","nota":"x","geom":%s}', m_ref, pg_temp.pt(-73.25, 10.46)), 'cambiar el tipo');
  perform pg_temp.mala('03.46 anular sin motivo', sp, v_id, 2, format('{"op":"anula","marca_id":"%s"}', m_ref), 'motivo');
  perform pg_temp.err('03.47 la misma marca dos veces en un guardado', format('select public.geoportal_analisis_cuaderno_guardar(%L, %L, 2, null, null, null, %L::jsonb)', sp, v_id,
    format('[{"op":"anula","marca_id":"%s","motivo":"ZTCUAD repetida"},{"op":"cambia","marca_id":"%s","tipo":"referencia","geom":%s}]', m_ref, m_ref, pg_temp.pt(-73.25, 10.46))), '22023', 'repetida');
  perform pg_temp.err('03.48 los cambios no son una lista', format('select public.geoportal_analisis_cuaderno_guardar(%L, %L, 2, null, null, null, ''{"op":"nueva"}''::jsonb)', sp, v_id), '22023', 'cambios');
  perform pg_temp.reg('03.49 ningún rechazo dejó una versión a medias: sigue en la 2 con 8 marcas',
    analisis.f_ultima_version(v_id) = 2 and (select count(*) from analisis.marcas where cuaderno_id = v_id) = 8 and (select count(*) from analisis.marca_versiones where cuaderno_id = v_id) = 8);

  -- cambiar, anular y leer versiones
  j := public.geoportal_analisis_cuaderno_guardar(sp, v_id, 2, 'ZTCUAD Cuaderno del POIR 2027', '', '{"zoom":15}', format($j$[
    {"op":"cambia","marca_id":"%s","tipo":"referencia","nota":"ZTCUAD movida","categoria":"observacion","estilo":{"color":"#0000FF"},"geom":%s},
    {"op":"anula","marca_id":"%s","motivo":"  ZTCUAD se puso por error  "},
    {"op":"cambia","marca_id":"%s","tipo":"zona","nota":"ZTCUAD la misma zona, otra nota","geom":%s}]$j$, m_ref, pg_temp.pt(-73.2600, 10.4700), m_post, m_zona, zona)::jsonb);
  perform pg_temp.reg('03.50 versión 3: título nuevo, descripción borrada con «», vista nueva; quedan 7 marcas vigentes',
    (j ->> 'version')::integer = 3 and jsonb_array_length(j -> 'marcas') = 7
    and (select titulo = 'ZTCUAD Cuaderno del POIR 2027' and descripcion is null and vista = '{"zoom":15}' from analisis.cuaderno_versiones where cuaderno_id = v_id and version = 3));
  select x into m from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_ref::text;
  perform pg_temp.reg('03.51 la marca cambiada: estado nuevo en la versión 3, nacida en la 2',
    m ->> 'nota' = 'ZTCUAD movida' and (m ->> 'version')::integer = 3 and (m ->> 'creada_en_version')::integer = 2 and (m -> 'geom' -> 'coordinates' ->> 0)::numeric = -73.26);
  perform pg_temp.reg('03.52 nada se borra: la marca anulada sigue en la tabla, con su motivo recortado y su estado anterior',
    (select count(*) = 2 and bool_or(anulada and motivo = 'ZTCUAD se puso por error' and nota = 'ZTCUAD post-it' and version = 3) and bool_or(not anulada and version = 2)
       from analisis.marca_versiones where marca_id = m_post));
  perform pg_temp.reg('03.53 la zona que no se movió conserva su conteo sin volver a contar (sigue 1 consulta)',
    (select (x ->> 'conteo_predios')::integer = v_n and x ->> 'nota' = 'ZTCUAD la misma zona, otra nota' from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_zona::text)
    and (select count(*) from analisis.zona_consultas where solicitante = sp) = 1);
  perform pg_temp.mala('03.54 una marca anulada ya no se cambia ni se anula otra vez', sp, v_id, 3, format('{"op":"anula","marca_id":"%s","motivo":"ZTCUAD otra vez"}', m_post), 'ya está anulada');
  j := public.geoportal_analisis_cuaderno(sd, v_id, 2);
  perform pg_temp.reg('03.55 la versión 2 se sigue leyendo tal como era: 8 marcas, el post-it vivo, la referencia en su sitio y el título viejo',
    jsonb_array_length(j -> 'marcas') = 8 and j ->> 'titulo' = 'ZTCUAD Cuaderno del POIR' and (j ->> 'version')::integer = 2 and (j ->> 'ultima_version')::integer = 3
    and (select (x -> 'geom' -> 'coordinates' ->> 0)::numeric = -73.254 from jsonb_array_elements(j -> 'marcas') x where x ->> 'id' = m_ref::text)
    and not (j ->> 'puede_editar')::boolean);
  j := public.geoportal_analisis_cuaderno(sp, v_id);
  perform pg_temp.reg('03.56 el autor abre la última: puede editar; trae 3 versiones y 7 marcas',
    (j ->> 'puede_editar')::boolean and (j ->> 'es_mio')::boolean and jsonb_array_length(j -> 'versiones') = 3 and jsonb_array_length(j -> 'marcas') = 7 and (j ->> 'version')::integer = 3);
  perform pg_temp.reg('03.57 el autor en una versión vieja NO puede editar (se edita solo sobre la última)', not (public.geoportal_analisis_cuaderno(sp, v_id, 2) ->> 'puede_editar')::boolean);
  j := public.geoportal_analisis_cuaderno(adm, v_id);
  perform pg_temp.reg('03.58 el administrador y el otro supervisor lo leen, sin poder editarlo',
    not (j ->> 'puede_editar')::boolean and not (j ->> 'es_mio')::boolean and jsonb_array_length(j -> 'marcas') = 7
    and not (public.geoportal_analisis_cuaderno(sd, v_id) ->> 'puede_editar')::boolean);
  perform pg_temp.err('03.59 una versión que no existe → 404', format('select public.geoportal_analisis_cuaderno(%L, %L, 9)', sp, v_id), 'P0002');
  perform pg_temp.err('03.60 un cuaderno que no existe → 404', format('select public.geoportal_analisis_cuaderno(%L, %L)', sp, gen_random_uuid()), 'P0002');
  -- tope de marcas
  insert into analisis.parametros (clave, valor, motivo, autor) values ('marcas_por_cuaderno', 7, 'ZTCUAD prueba del tope', 'prueba');
  perform pg_temp.mala('03.61 con el tope en 7, la octava marca no entra', sp, v_id, 3, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'no puede pasar de 7');
  j := public.geoportal_analisis_cuaderno_guardar(sp, v_id, 3, null, null, null, format('[{"op":"anula","marca_id":"%s","motivo":"ZTCUAD hace sitio"},{"op":"nueva","tipo":"referencia","geom":%s}]',
         m_circ, pg_temp.pt(-73.25, 10.46))::jsonb);
  perform pg_temp.reg('03.62 anular una y poner otra en el mismo guardado sí cabe (versión 4, 7 marcas; el servidor le pone identificador)',
    (j ->> 'version')::integer = 4 and jsonb_array_length(j -> 'marcas') = 7);
  insert into analisis.parametros (clave, valor, motivo, autor) values ('marcas_por_cuaderno', 500, 'ZTCUAD vuelve al valor', 'prueba');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('mano_vertices_max', 5, 'ZTCUAD prueba del tope', 'prueba');
  perform pg_temp.mala('03.63 un trazo que tras simplificarse pasa del tope de vértices', sp, v_id, 4,
    '{"op":"nueva","tipo":"mano","geom":{"type":"LineString","coordinates":[[-73.25,10.46],[-73.251,10.461],[-73.25,10.462],[-73.251,10.463],[-73.25,10.464],[-73.251,10.465],[-73.25,10.466]]}}', 'demasiado largo');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('mano_vertices_max', 500, 'ZTCUAD vuelve al valor', 'prueba');
  -- los CHECK de las tablas también lo impiden por debajo de las RPC
  perform pg_temp.err('03.64 CHECK: una marca fuera de Valledupar no entra ni por inserción directa',
    format('insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, geom) values (%L, %L, 4, ''referencia'', st_setsrid(st_makepoint(-74.08, 4.6), 4326))', m_ref, v_id), '23514');
  perform pg_temp.err('03.65 CHECK: un punto con tipo zona',
    format('insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, geom, conteo_predios, conteo_contratos) values (%L, %L, 4, ''zona'', st_setsrid(st_makepoint(-73.25, 10.46), 4326), 1, 1)', m_ref, v_id), '23514');
  perform pg_temp.err('03.66 CHECK: anulada sin motivo',
    format('insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, geom, anulada) values (%L, %L, 4, ''referencia'', st_setsrid(st_makepoint(-73.25, 10.46), 4326), true)', m_ref, v_id), '23514');
  perform pg_temp.err('03.67 LLAVE: un problema con un subtipo que no está en el catálogo',
    format('insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, subtipo, geom) values (%L, %L, 4, ''problema'', ''inventado'', st_setsrid(st_makepoint(-73.25, 10.46), 4326))', m_ref, v_id), '23503');
  perform pg_temp.err('03.68 LLAVE: una versión de marca en una versión de cuaderno que no existe',
    format('insert into analisis.marca_versiones (marca_id, cuaderno_id, version, tipo, geom) values (%L, %L, 99, ''referencia'', st_setsrid(st_makepoint(-73.25, 10.46), 4326))', m_ref, v_id), '23503');
  perform pg_temp.err('03.69 CHECK: un módulo que no es Técnica', format('insert into analisis.cuadernos (modulo, autor) values (''comercial'', %L)', sp), '23514');

  -- ===================== 04. Archivar y reabrir =====================
  perform pg_temp.err('04.01 otro supervisor no archiva el cuaderno ajeno', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''archivar'', ''ZTCUAD motivo'')', sd, v_id), '42501');
  perform pg_temp.err('04.02 el administrador tampoco', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''archivar'', ''ZTCUAD motivo'')', adm, v_id), '42501');
  perform pg_temp.err('04.03 archivar sin motivo', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''archivar'', ''  '')', sp, v_id), '22023', 'motivo');
  perform pg_temp.err('04.04 una acción que no existe', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''borrar'', ''ZTCUAD motivo'')', sp, v_id), '22023');
  perform pg_temp.err('04.05 reabrir lo que no está archivado → 409', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''reabrir'', ''ZTCUAD motivo'')', sp, v_id), '55000');
  j := public.geoportal_analisis_cuaderno_estado(sp, v_id, 'archivar', 'ZTCUAD ya se entregó el análisis');
  perform pg_temp.reg('04.06 el autor archiva con motivo', (j ->> 'archivado')::boolean and analisis.f_archivado(v_id));
  perform pg_temp.mala('04.07 un cuaderno archivado no se edita → 409', sp, v_id, 4, format('{"op":"nueva","tipo":"referencia","geom":%s}', pg_temp.pt(-73.25, 10.46)), 'archivado', '55000');
  perform pg_temp.err('04.08 archivarlo dos veces → 409', format('select public.geoportal_analisis_cuaderno_estado(%L, %L, ''archivar'', ''ZTCUAD motivo'')', sp, v_id), '55000');
  perform pg_temp.reg('04.09 sale de la lista normal y aparece en la de archivados; se sigue leyendo, sin edición',
    not exists (select 1 from jsonb_array_elements(public.geoportal_analisis_cuadernos(sd) -> 'cuadernos') x where x ->> 'id' = v_id::text)
    and exists (select 1 from jsonb_array_elements(public.geoportal_analisis_cuadernos(sd, true) -> 'cuadernos') x where x ->> 'id' = v_id::text and (x ->> 'archivado')::boolean and (x ->> 'marcas')::integer = 7)
    and not (public.geoportal_analisis_cuaderno(sp, v_id) ->> 'puede_editar')::boolean and (public.geoportal_analisis_cuaderno(sp, v_id) ->> 'archivado')::boolean);
  perform pg_temp.err('04.10 archivado: tampoco recibe capturas → 409',
    format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', sp, v_id, repeat('a', 64)), '55000');
  j := public.geoportal_analisis_cuaderno_estado(sp, v_id, 'reabrir', 'ZTCUAD faltaba una zona');
  perform pg_temp.reg('04.11 el autor lo reabre y vuelve a poder editar; quedan los dos eventos con su motivo',
    not analisis.f_archivado(v_id) and (public.geoportal_analisis_cuaderno(sp, v_id) ->> 'puede_editar')::boolean
    and jsonb_array_length(public.geoportal_analisis_cuaderno(sp, v_id) -> 'eventos') = 2);

  -- ===================== 05. Zona afectada =====================
  select count(*), count(distinct cod_usuario) filter (where btrim(coalesce(cod_usuario, '')) <> '') into v_n, v_n2
    from public.catastro_valledupar where st_intersects(geom, st_setsrid(st_geomfromgeojson(zona2), 4326));
  j := public.geoportal_analisis_zona(sd, zona2::jsonb);
  perform pg_temp.reg('05.01 la zona devuelve SOLO los dos números, iguales al catastro',
    (select array_agg(k order by k) from jsonb_object_keys(j) k) = array['contratos', 'predios'] and (j ->> 'predios')::integer = v_n and (j ->> 'contratos')::integer = v_n2, j::text);
  perform pg_temp.reg('05.02 los contratos nunca son más que los predios, y la respuesta no trae códigos ni direcciones', v_n2 <= v_n and j::text !~ '[A-Za-z]{3,}.*[0-9]{5,}');
  perform pg_temp.reg('05.03 una zona sin predios da cero y cero',
    public.geoportal_analisis_zona(sd, pg_temp.cuadro(-73.3400, 10.5400, 0.0010)::jsonb) = '{"predios":0,"contratos":0}'::jsonb);
  perform pg_temp.err('05.04 más de 25 km² → 400', format('select public.geoportal_analisis_zona(%L, %L::jsonb)', sd, pg_temp.cuadro(-73.30, 10.40, 0.09)), '22023', 'demasiado grande');
  perform pg_temp.err('05.05 fuera de Valledupar → 400', format('select public.geoportal_analisis_zona(%L, %L::jsonb)', sd, pg_temp.cuadro(-74.10, 4.60, 0.01)), '22023', 'fuera de Valledupar');
  perform pg_temp.err('05.06 una línea no es una zona → 400', format('select public.geoportal_analisis_zona(%L, ''{"type":"LineString","coordinates":[[-73.25,10.46],[-73.24,10.47]]}''::jsonb)', sd), '22023', 'polígono');
  perform pg_temp.err('05.07 sin geometría → 400', format('select public.geoportal_analisis_zona(%L, null)', sd), '22023', 'polígono');
  perform pg_temp.err('05.08 un multipolígono no es una zona → 400',
    format('select public.geoportal_analisis_zona(%L, ''{"type":"MultiPolygon","coordinates":[[[[-73.25,10.46],[-73.24,10.46],[-73.24,10.47],[-73.25,10.46]]]]}''::jsonb)', sd), '22023', 'polígono');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('zona_conteos_por_hora', 3, 'ZTCUAD prueba del tope', 'prueba');
  j := public.geoportal_analisis_zona(sd, zona2::jsonb);            -- la tercera del supervisor de distribución en esta hora
  perform pg_temp.err('05.09 con el tope en 3 por hora, la cuarta → 429', format('select public.geoportal_analisis_zona(%L, %L::jsonb)', sd, zona2), '54000', 'Demasiados conteos');
  perform pg_temp.reg('05.10 el tope es por persona: otro supervisor sigue contando', (public.geoportal_analisis_zona(adm, zona2::jsonb) ->> 'predios')::integer = v_n);
  v_id2 := (public.geoportal_analisis_cuaderno_crear(sd, 'ZTCUAD Cuaderno de distribución') ->> 'id')::uuid;
  perform pg_temp.mala('05.11 el tope también vale para las zonas que cuenta «guardar»', sd, v_id2, 1, format('{"op":"nueva","tipo":"zona","geom":%s}', zona2), 'Demasiados conteos', '54000');
  perform pg_temp.reg('05.12 las consultas rechazadas no cuentan ni quedan a medias: el supervisor de distribución tiene 3', (select count(*) from analisis.zona_consultas where solicitante = sd) = 3);
  insert into analisis.parametros (clave, valor, motivo, autor) values ('zona_conteos_por_hora', 120, 'ZTCUAD vuelve al valor', 'prueba');
  perform pg_temp.reg('05.13 el registro de consultas no guarda la geometría ni nada del predio',
    (select array_agg(column_name::text order by ordinal_position) from information_schema.columns where table_schema = 'analisis' and table_name = 'zona_consultas')
      = array['id', 'solicitante', 'area_km2', 'predios', 'contratos', 'creado_en']);

  -- ===================== 06. Capturas =====================
  perform pg_temp.err('06.01 otro supervisor no guarda capturas en un cuaderno ajeno',
    format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', sd, v_id, repeat('a', 64)), '42501');
  perform pg_temp.err('06.02 más de 1.600 px de lado', format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 1601, 600, 1000, %L)', sp, v_id, repeat('a', 64)), '22023', '1600 px');
  perform pg_temp.err('06.03 más de 600 KB', format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 1600, 900, 614401, %L)', sp, v_id, repeat('a', 64)), '22023', '600 KB');
  perform pg_temp.err('06.04 huella que no es sha256', format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, ''abc'')', sp, v_id), '22023', 'huella');
  perform pg_temp.err('06.05 extensión al revés (oeste mayor que este)', format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.25, 10.46, -73.26, 10.47, 800, 600, 1000, %L)', sp, v_id, repeat('a', 64)), '22023', 'extensión');
  perform pg_temp.err('06.06 sin título', format('select public.geoportal_analisis_captura_firmar(%L, %L, '' '', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', sp, v_id, repeat('a', 64)), '22023', 'título');
  j := public.geoportal_analisis_captura_firmar(sp, v_id, '  ZTCUAD Vista del sector 5  ', -73.26, 10.46, -73.25, 10.47, 1600, 900, 300000, repeat('a', 64));
  v_cap := (j ->> 'captura_id')::uuid; v_ruta := j ->> 'ruta';
  perform pg_temp.reg('06.07 firmar: reserva la ruta <cuaderno>/<captura>.jpg', v_ruta = v_id::text || '/' || v_cap::text || '.jpg' and (select titulo = 'ZTCUAD Vista del sector 5' from analisis.capturas where id = v_cap));
  perform pg_temp.err('06.08 confirmar antes de subir → 409', format('select public.geoportal_analisis_captura_confirmar(%L, %L)', sp, v_cap), '55000', 'almacenamiento');
  perform pg_temp.err('06.09 una captura sin confirmar no se puede abrir → 404', format('select public.geoportal_analisis_captura_ruta(%L, %L)', sp, v_cap), 'P0002');
  perform pg_temp.reg('06.10 una captura sin confirmar no sale en el cuaderno', jsonb_array_length(public.geoportal_analisis_cuaderno(sp, v_id) -> 'capturas') = 0);
  insert into storage.objects (bucket_id, name, metadata) values ('analisis-capturas', v_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/png'));
  perform pg_temp.err('06.11 llegó un PNG → 400', format('select public.geoportal_analisis_captura_confirmar(%L, %L)', sp, v_cap), '22023', 'JPEG');
  j := public.geoportal_analisis_captura_firmar(sp, v_id, 'ZTCUAD Otra vista', -73.26, 10.46, -73.25, 10.47, 800, 600, 200000, repeat('b', 64));
  v_cap2 := (j ->> 'captura_id')::uuid;
  insert into storage.objects (bucket_id, name, metadata) values ('analisis-capturas', j ->> 'ruta', jsonb_build_object('size', 250000, 'mimetype', 'image/jpeg'));
  perform pg_temp.err('06.12 llegó un archivo de otro tamaño que el anunciado → 400', format('select public.geoportal_analisis_captura_confirmar(%L, %L)', sp, v_cap2), '22023', 'no es la que se anunció');
  v_cap := (public.geoportal_analisis_captura_firmar(sp, v_id, 'ZTCUAD Vista buena', -73.26, 10.46, -73.25, 10.47, 1600, 900, 300000, repeat('c', 64)) ->> 'captura_id')::uuid;
  insert into storage.objects (bucket_id, name, metadata) select 'analisis-capturas', ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg') from analisis.capturas where id = v_cap;
  perform pg_temp.err('06.13 otro supervisor no confirma la captura ajena', format('select public.geoportal_analisis_captura_confirmar(%L, %L)', sd, v_cap), '42501');
  j := public.geoportal_analisis_captura_confirmar(sp, v_cap);
  perform pg_temp.reg('06.14 confirmar: el archivo está, es JPEG y pesa lo anunciado',
    (j ->> 'confirmada')::boolean and (select bytes_reales = 300000 and autor = sp from analisis.capturas_confirmadas where captura_id = v_cap));
  perform pg_temp.reg('06.15 confirmar dos veces no duplica', (public.geoportal_analisis_captura_confirmar(sp, v_cap) ->> 'confirmada')::boolean
    and (select count(*) from analisis.capturas_confirmadas where captura_id = v_cap) = 1);
  j := public.geoportal_analisis_captura_ruta(sd, v_cap);
  perform pg_temp.reg('06.16 el otro supervisor y el administrador sí la abren (lectura)',
    j ->> 'ruta' = (select ruta from analisis.capturas where id = v_cap) and public.geoportal_analisis_captura_ruta(adm, v_cap) ->> 'titulo' = 'ZTCUAD Vista buena');
  j := public.geoportal_analisis_cuaderno(sd, v_id);
  perform pg_temp.reg('06.17 el cuaderno muestra solo la captura confirmada, con su título, extensión y tamaño; SIN la ruta del archivo',
    jsonb_array_length(j -> 'capturas') = 1 and j -> 'capturas' -> 0 ->> 'titulo' = 'ZTCUAD Vista buena' and (j -> 'capturas' -> 0 ->> 'bytes')::integer = 300000
    and j -> 'capturas' -> 0 -> 'extension' = '[-73.26, 10.46, -73.25, 10.47]'::jsonb and not (j -> 'capturas' -> 0) ? 'ruta' and j::text not like '%.jpg%');
  perform pg_temp.err('06.18 una captura que no existe → 404', format('select public.geoportal_analisis_captura_confirmar(%L, %L)', sp, gen_random_uuid()), 'P0002');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('capturas_por_cuaderno', 3, 'ZTCUAD prueba del tope', 'prueba');
  perform pg_temp.err('06.19 con el tope en 3 (1 confirmada y 2 reservadas hace poco), la cuarta → 409',
    format('select public.geoportal_analisis_captura_firmar(%L, %L, ''ZTCUAD captura'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L)', sp, v_id, repeat('d', 64)), '55000', 'ya tiene sus 3 capturas');
  perform pg_temp.reg('06.20 el tope es por cuaderno: en otro cuaderno sí se puede',
    public.geoportal_analisis_captura_firmar(sd, v_id2, 'ZTCUAD captura de distribución', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, repeat('e', 64)) ? 'captura_id');
  insert into analisis.parametros (clave, valor, motivo, autor) values ('capturas_por_cuaderno', 20, 'ZTCUAD vuelve al valor', 'prueba');
  perform pg_temp.err('06.21 CHECK: una captura de 700 KB no entra ni por inserción directa',
    format('insert into analisis.capturas (id, cuaderno_id, ruta, titulo, oeste, sur, este, norte, ancho, alto, bytes, sha256, autor) values (%L, %L, %L, ''ZTCUAD x'', -73.26, 10.46, -73.25, 10.47, 800, 600, 700000, %L, %L)',
           v_cap2, v_id, v_id::text || '/' || v_cap2::text || '.jpg', repeat('a', 64), sp), '23514');
  perform pg_temp.err('06.22 CHECK: la ruta debe ser la del cuaderno y la captura',
    format('insert into analisis.capturas (cuaderno_id, ruta, titulo, oeste, sur, este, norte, ancho, alto, bytes, sha256, autor) values (%L, ''otra/cosa.jpg'', ''ZTCUAD x'', -73.26, 10.46, -73.25, 10.47, 800, 600, 1000, %L, %L)',
           v_id, repeat('a', 64), sp), '23514');

  -- ===================== 07. Exportar =====================
  j := public.geoportal_analisis_cuaderno_exportar(sd, v_id);
  perform pg_temp.reg('07.01 exportar (lo lee también el otro supervisor): las 7 marcas vigentes numeradas, sin las anuladas, y la captura confirmada',
    jsonb_array_length(j -> 'marcas') = 7 and (select array_agg((x ->> 'n')::integer order by (x ->> 'n')::integer) from jsonb_array_elements(j -> 'marcas') x) = array[1, 2, 3, 4, 5, 6, 7]
    and not exists (select 1 from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' in ('postit', 'circulo'))
    and jsonb_array_length(j -> 'capturas') = 1 and j -> 'cuaderno' ->> 'titulo' = 'ZTCUAD Cuaderno del POIR 2027' and (j -> 'cuaderno' ->> 'version')::integer = 4);
  perform pg_temp.reg('07.02 cada fila trae su punto (lon, lat), el nombre del catálogo, el sector y, según la figura, longitud, área o conteos',
    (select bool_and(x ->> 'lon' is not null and x ->> 'lat' is not null) from jsonb_array_elements(j -> 'marcas') x)
    and (select x ->> 'nombre' = 'Válvula por revisar' and x ->> 'activo_codigo' = v_act from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' = 'problema')
    and (select x ->> 'nombre' = 'Tanque' and x ->> 'sistema' = 'acueducto' from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' = 'activo')
    and (select (x ->> 'longitud_m')::numeric between 100 and 200 and x ->> 'area_m2' is null from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' = 'linea')
    and (select (x ->> 'area_m2')::numeric between 300000 and 600000 and (x ->> 'predios')::integer > 0 from jsonb_array_elements(j -> 'marcas') x where x ->> 'tipo' = 'zona'));
  perform pg_temp.reg('07.03 la exportación no trae la ruta de las capturas ni identificadores internos de las marcas',
    j::text not like '%.jpg%' and not exists (select 1 from jsonb_array_elements(j -> 'marcas') x where x ? 'id' or x ? 'geom'));
  perform pg_temp.err('07.04 exportar un cuaderno que no existe → 404', format('select public.geoportal_analisis_cuaderno_exportar(%L, %L)', sp, gen_random_uuid()), 'P0002');

  -- ===================== 08. Solo agregar, con datos en las 10 tablas =====================
  foreach t in array tablas loop
    execute format('select count(*) from analisis.%I', t) into v_n;
    perform pg_temp.reg('08.01 analisis.' || t || ' tiene filas para probar', v_n > 0, v_n::text);
    perform pg_temp.err('08.02 DELETE bloqueado en analisis.' || t, format('delete from analisis.%I where true', t), '42501', 'DELETE no permitido');
    select a.attname into q from pg_attribute a where a.attrelid = ('analisis.' || t)::regclass and a.attnum > 0 and not a.attisdropped and a.attidentity = '' order by a.attnum desc limit 1;
    perform pg_temp.err('08.03 UPDATE bloqueado en analisis.' || t, format('update analisis.%I set %I = %I where true', t, q, q), '42501', 'UPDATE no permitido');
  end loop;
  perform pg_temp.err('08.04 TRUNCATE de todas a la vez', 'truncate analisis.cuadernos, analisis.cuaderno_versiones, analisis.cuaderno_eventos, analisis.marcas, analisis.marca_versiones, '
    || 'analisis.capturas, analisis.capturas_confirmadas, analisis.zona_consultas, analisis.catalogo, analisis.parametros', '42501', 'TRUNCATE no permitido');

  -- ===================== 09. Lo que el paquete NO toca =====================
  perform pg_temp.reg('09.01 la huella de redes es la de antes (foto tomada antes de aplicar, en esta misma transacción)',
    (select a.v = d.v and a.v is not null from _foto_antes a join pg_temp.foto() d using (k) where k = 'huella_redes'), (select v from _foto_antes where k = 'huella_redes'));
  perform pg_temp.reg('09.02 la huella de técnica es la de antes',
    (select a.v = d.v and a.v is not null from _foto_antes a join pg_temp.foto() d using (k) where k = 'huella_tecnica'), (select v from _foto_antes where k = 'huella_tecnica'));
  perform pg_temp.reg('09.03 redes y técnica: los mismos objetos, columnas y disparadores; public, las mismas funciones más las 11 RPC',
    (select bool_and(a.v = d.v) from _foto_antes a join pg_temp.foto() d using (k) where k in ('objetos_redes_tecnica', 'columnas_redes_tecnica', 'disparadores_redes_tecnica', 'funciones_public')),
    (select string_agg(k || ' ' || a.v || '→' || d.v, ' · ') from _foto_antes a join pg_temp.foto() d using (k) where a.v <> d.v));

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE ANÁLISIS · CUADERNOS (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total,
    case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
