-- [Code B] INVESTIGACIÓN Y ANÁLISIS (23-nov) · ENSAYO (termina en ERROR esperado; no deja nada) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS (Code B, 23-nov) · 05 — GUARDIA: se detiene sin cambiar nada si la base no es la publicada
-- Comprueba: huella de campo 261bed3c9242f6261f845ec4e1374b3a (todas las funciones de campo y las public.geoportal_campo_*), huella del acta 111506c690249ad3b56ebf572566434c,
-- el md5 de cada función que se reemplaza, la estructura exacta de las tablas vivas que el paquete lee o toca (columnas, tipos, NOT NULL,
-- valores por omisión, identidad, restricciones, índices, disparadores, RLS y permisos), y el estado de partida de la Investigación de
-- ubicación tal como está en producción (consulta del 23-nov 22:37): id 35, activa, con resultado, fotos 3 a 6, contrato «si», sus 7 campos,
-- sus 3 fotos obligatorias, 0 registros y presente en campo.actividades.
-- =====================================================================
do $guardia$
declare v text; r record; v_t campo.tipos_reporte%rowtype; v_campos text; v_fotos text;
begin
  if to_regprocedure('public.geoportal_campo_preparar_subida(text,integer,text,text,text)') is not null
     and md5(pg_get_functiondef('public.geoportal_campo_preparar_subida(text,integer,text,text,text)'::regprocedure)) = 'a00d66705d7a0c88a38ab5d882153669' then
    raise exception 'Este paquete ya parece aplicado (preparar_subida ya es la de este cambio): use la reversa antes de repetir';
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if coalesce(v, '(ninguna)') is distinct from '261bed3c9242f6261f845ec4e1374b3a' then
    raise exception 'Las funciones de campo no son las publicadas (huella 261bed3c9242f6261f845ec4e1374b3a; hay %): deténgase y avise', v;
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%');
  if coalesce(v, '(ninguna)') is distinct from '111506c690249ad3b56ebf572566434c' then
    raise exception 'Las funciones del acta no son las publicadas (huella 111506c690249ad3b56ebf572566434c; hay %): deténgase y avise', v;
  end if;
  for r in select * from (values ('public.geoportal_campo_preparar_subida(text,integer,text,text,text)', '6a2ef927316ed4aa2936eadfb9b0a0cd'), ('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)', '51ecb98ca2e7f940c66b9a1f3e828222'), ('public.geoportal_campo_obtener_formulario(text,boolean)', 'da253b2da0128848595788795f61479f'), ('campo.f_validar_datos(bigint,jsonb,boolean)', 'f3d09600df18aa558e5bc046d6934f70'), ('public.geoportal_puede(text,text)', '32f174a55b95788d3f8187b507303c2f'), ('public.geoportal_mis_permisos(text)', '83166fe17be58da67bbdedaae429bedb'), ('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)', '01fda69a9d912067b8b4dc153ac7957e'), ('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)', 'e5a90103b4a83440fd826f03266b7245')) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la publicada: deténgase y avise', r.f;
    end if;
  end loop;
  -- Estructura exacta de las tablas vivas (la misma expresión que calcula generar.py en el doble, que es copia exacta de producción)
  for r in select * from (values ('campo.tipos_reporte', '3b9274b039c86b8079fee77b484ad5e1'), ('campo.tipo_campos', '9628451c9105875e1c7b2ac2421691a5'), ('campo.tipo_fotos', 'fcce3283ea598e0c1b4f2aeafdd0e9ae'), ('campo.actividades', '9a20496e1319d07650a5e4460a523d64'), ('campo.derivadas', '2ebfe8b36411e10e364231ddbbee8f67'), ('campo.derivadas_catalogo', '4b406fe705b31222fad55e6abf064c28'), ('campo.derivada_eventos', 'd01fd6ead43730a491b927f36c3136a9'), ('campo.consultas_analisis', '1202c7e6e2999e2d5adaccd2e371320d'), ('campo.causales_tipos', '71502cd2b2d048f6d3bf01a6cc188d0d'), ('campo.formularios_documento', 'b83ea82f1765747e4b8ce6532aff3fc6'), ('campo.grupos_reporte', 'ba97afc37aee73287dc7d000c664b749')) x(t, m) loop
    if to_regclass(r.t) is null then raise exception 'No existe la tabla %: deténgase y avise', r.t; end if;
    select md5(concat_ws('#', (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped), (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel), (select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel), (select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal), (select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel))) into v from (select to_regclass(r.t) as rel) z;
    if v is distinct from r.m then
      raise exception 'La estructura de % no es la de producción (columnas, restricciones, índices, disparadores, RLS o permisos): deténgase y avise', r.t;
    end if;
  end loop;
  -- Estado de partida de la Investigación de ubicación
  select * into v_t from campo.tipos_reporte where codigo = 'investigacion_ubicacion';
  if not found then raise exception 'No existe la Investigación de ubicación: deténgase y avise'; end if;
  if (v_t.id, v_t.activo, v_t.genera_resultado, v_t.fotos_min, v_t.fotos_max, v_t.requiere_contrato, v_t.prefijo_consecutivo)
     is distinct from (35::bigint, true, true, 3::smallint, 6::smallint, 'si'::text, 'INV'::text) then
    raise exception 'La Investigación de ubicación no está como en producción (id 35, activa, con resultado, fotos 3 a 6, contrato si, prefijo INV): deténgase y avise';
  end if;
  select string_agg(c.codigo || ':' || c.tipo_dato || ':' || c.obligatorio::text || ':' || c.activo::text, ',' order by c.codigo) into v_campos
    from campo.tipo_campos c where c.tipo_id = v_t.id;
  -- Se acepta también el estado que deja la reversa de este paquete (los 4 campos nuevos desactivados, nada se borra)
  if v_campos is distinct from 'cita_acordada:dia_hora:false:true,despeje_caja:si_no:false:true,despeje_observacion:texto:false:true,direccion_encontrada:texto:false:true,hallazgo:opcion:true:true,observacion:texto:false:true,visita_concertada:si_no:false:true' and v_campos is distinct from 'barrio:texto:false:false,cita_acordada:dia_hora:false:true,despeje_caja:si_no:false:true,despeje_observacion:texto:false:true,direccion_encontrada:texto:false:true,habitado:si_no:false:false,hallazgo:opcion:true:true,medidor:texto:false:false,observacion:texto:false:true,tipo_predio:opcion:false:false,visita_concertada:si_no:false:true' then
    raise exception 'Los campos de la Investigación no son los de producción (hay %): deténgase y avise', v_campos;
  end if;
  select string_agg(f.codigo || ':' || f.obligatoria::text || ':' || f.soporte_inefectiva::text || ':' || f.activo::text, ',' order by f.codigo) into v_fotos
    from campo.tipo_fotos f where f.tipo_id = v_t.id;
  if v_fotos is distinct from 'fachada_nomenclatura:true:true:true,predio_lote:true:true:true,vecino_referencia:true:false:true' then
    raise exception 'Las fotos de la Investigación no son las de producción (hay %): deténgase y avise', v_fotos;
  end if;
  -- 0 registros, salvo que la Investigación esté como la deja la reversa de este paquete (esos registros se hicieron con este paquete)
  if v_campos = 'cita_acordada:dia_hora:false:true,despeje_caja:si_no:false:true,despeje_observacion:texto:false:true,direccion_encontrada:texto:false:true,hallazgo:opcion:true:true,observacion:texto:false:true,visita_concertada:si_no:false:true' and exists (select 1 from campo.reportes where tipo_id = v_t.id) then
    raise exception 'La Investigación de ubicación ya tiene registros: este paquete se preparó para 0; deténgase y avise';
  end if;
  if not exists (select 1 from campo.actividades a where a.codigo = 'investigacion_ubicacion' and a.activa and 'tipo:investigacion_ubicacion' = any (a.formularios)) then
    raise exception 'La actividad investigacion_ubicacion no está activa en campo.actividades: deténgase y avise';
  end if;
  if exists (select 1 from campo.tipo_campos where tipo_id = v_t.id and codigo in ('barrio', 'habitado', 'tipo_predio', 'medidor') and activo) then
    raise exception 'Algún campo nuevo de la Investigación ya existe y está activo: deténgase y avise';
  end if;
end $guardia$;

-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 10 — Investigación de ubicación del predio (INV), decisiones de David del 23-nov
-- Obligatorios: contrato (ya), dirección encontrada en terreno (pasa a obligatoria) y XY (ya lo exigen la RPC y la pantalla).
-- Opcionales: hallazgo (deja de ser obligatorio), barrio (texto), ¿habitado? (sí o no), tipo de predio (opción), medidor (texto), observación.
-- Sin resultado (efectiva / inefectiva) ni causal; las 3 fotos opcionales y sin marca de soporte; de 0 a 6 fotos.
-- Se DESACTIVAN (no se borran): despeje_caja, despeje_observacion, visita_concertada y cita_acordada.
-- Las causales enlazadas quedan como están (Q4): sin resultado, ni la RPC ni la pantalla las piden.
-- Todo queda auditado (campo_catalogo) con el antes y el después.
-- =====================================================================
do $inv$
declare v_t bigint; v_antes jsonb; v_despues jsonb; v_n record;
begin
  select id into v_t from campo.tipos_reporte where codigo = 'investigacion_ubicacion';
  select jsonb_build_object('tipo', (select to_jsonb(t) from campo.tipos_reporte t where t.id = v_t),
                            'campos', (select jsonb_agg(to_jsonb(c) order by c.orden, c.id) from campo.tipo_campos c where c.tipo_id = v_t),
                            'fotos', (select jsonb_agg(to_jsonb(f) order by f.orden, f.id) from campo.tipo_fotos f where f.tipo_id = v_t)) into v_antes;

  update campo.tipos_reporte set genera_resultado = false, fotos_min = 0 where id = v_t;
  update campo.tipo_fotos set obligatoria = false, soporte_inefectiva = false
   where tipo_id = v_t and codigo in ('fachada_nomenclatura', 'predio_lote', 'vecino_referencia');
  update campo.tipo_campos set obligatorio = true where tipo_id = v_t and codigo = 'direccion_encontrada';
  update campo.tipo_campos set obligatorio = false where tipo_id = v_t and codigo = 'hallazgo';
  update campo.tipo_campos set activo = false where tipo_id = v_t and codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada', 'cita_acordada');
  -- Los 4 campos nuevos: se crean; si una reversa anterior los dejó desactivados, se reactivan (nada se borra ni se duplica)
  for v_n in select * from jsonb_to_recordset('[
      {"codigo": "barrio", "nombre": "Barrio", "tipo_dato": "texto", "opciones": null, "maximo": 80, "ayuda": null, "orden": 3},
      {"codigo": "habitado", "nombre": "¿El predio está habitado?", "tipo_dato": "si_no", "opciones": null, "maximo": null, "ayuda": null, "orden": 4},
      {"codigo": "tipo_predio", "nombre": "Tipo de predio", "tipo_dato": "opcion",
       "opciones": [{"codigo": "casa", "nombre": "Casa"}, {"codigo": "apartamento", "nombre": "Apartamento"}, {"codigo": "edificio", "nombre": "Edificio"},
                    {"codigo": "comercio", "nombre": "Comercio"}, {"codigo": "lote_desocupado", "nombre": "Lote desocupado"}, {"codigo": "demolido", "nombre": "Demolido"}],
       "maximo": null, "ayuda": null, "orden": 5},
      {"codigo": "medidor", "nombre": "Número del medidor (si se ve)", "tipo_dato": "texto", "opciones": null, "maximo": 20,
       "ayuda": "Tal como aparece en el medidor; si no hay o no se ve, déjelo vacío", "orden": 6}
    ]'::jsonb) as x(codigo text, nombre text, tipo_dato text, opciones jsonb, maximo numeric, ayuda text, orden integer) loop
    if exists (select 1 from campo.tipo_campos where tipo_id = v_t and codigo = v_n.codigo) then
      update campo.tipo_campos set activo = true, obligatorio = false where tipo_id = v_t and codigo = v_n.codigo;
    else
      insert into campo.tipo_campos (tipo_id, codigo, nombre, tipo_dato, obligatorio, opciones, maximo, ayuda, orden)
      values (v_t, v_n.codigo, v_n.nombre, v_n.tipo_dato, false, v_n.opciones, v_n.maximo, v_n.ayuda, v_n.orden);
    end if;
  end loop;

  select jsonb_build_object('tipo', (select to_jsonb(t) from campo.tipos_reporte t where t.id = v_t),
                            'campos', (select jsonb_agg(to_jsonb(c) order by c.orden, c.id) from campo.tipo_campos c where c.tipo_id = v_t),
                            'fotos', (select jsonb_agg(to_jsonb(f) order by f.orden, f.id) from campo.tipo_fotos f where f.tipo_id = v_t)) into v_despues;
  perform campo.f_auditar('migracion@geoportal', 'campo_catalogo', 'tipo:investigacion_ubicacion',
                          jsonb_build_object('paquete', 'campo_inv_analisis', 'antes', v_antes, 'despues', v_despues), null);
end $inv$;

-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 20 — preparar_subida admite 0 fotos SOLO si el formato informado tiene fotos_min = 0
-- Lo demás no cambia: sin tipo, o con un tipo de mínimo 1 o más (o sin mínimo), desde campo se sigue exigiendo al menos 1 foto.
-- La preparación con 0 fotos reserva el identificador y cuenta en el cupo, como hoy. CREATE OR REPLACE conserva los permisos.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.geoportal_campo_preparar_subida(p_solicitante text, p_cantidad integer, p_origen text DEFAULT 'campo'::text, p_ip text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v_perfil text; v_id uuid := gen_random_uuid(); v_mes text := to_char(campo.f_ahora_bogota(), 'YYYY-MM'); v_max integer := campo.f_param('max_fotos')::integer; v_tmax smallint; v_tmin smallint; v_min integer;
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);
  v_perfil := campo.f_perfil(v_email);
  if coalesce(p_origen, '') not in ('campo', 'escritorio') then perform campo.f_error('El origen debe ser campo o escritorio'); end if;
  if p_origen = 'escritorio' and v_perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador crean reportes desde el escritorio' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_tipo, '')), '') is not null then
    select t.fotos_max, t.fotos_min into v_tmax, v_tmin from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id where t.codigo = btrim(p_tipo) and t.activo and g.activo;
    if not found then perform campo.f_error('El tipo de reporte no existe o está desactivado'); end if;
    v_max := coalesce(v_tmax, v_max);
  end if;
  -- Investigación y Análisis (23-nov): desde campo se exige al menos 1 foto, salvo que el formato informado tenga fotos_min = 0
  v_min := case when p_origen = 'campo' and v_tmin is distinct from 0 then 1 else 0 end;
  if p_cantidad is null or p_cantidad < v_min or p_cantidad > v_max then
    perform campo.f_error(format('La cantidad de fotos debe estar entre %s y %s', v_min, v_max));
  end if;
  perform campo.f_cupo_preparaciones(v_email, v_perfil);   -- Paso B1
  insert into campo.preparaciones (reporte_id, autor) values (v_id, v_email);
  return jsonb_build_object('reporte_id', v_id, 'bucket', 'campo-fotos', 'max_bytes_foto', campo.f_param('max_bytes_foto')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', n, 'ruta', 'reportes/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n)
                         from generate_series(1, p_cantidad) n), '[]'::jsonb));
end $function$;

-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 70 — PRUEBAS (dentro del ensayo; todo se deshace al final con el ERROR esperado)
-- Datos propios con prefijo ZTINV (correos ztinv.*@emdupar.gov.co; textos «[PRUEBA ZTINV]»). Cada prueba cuenta SOLO sus filas.
-- Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- Sin tablas temporales que se borren al confirmar: la tabla de resultados se deshace con el ERROR esperado del final.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztinv_res (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztinv_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
-- llama una RPC como service_role; devuelve su jsonb o {"error": sqlstate, "msg": mensaje}
create function pg_temp.rpc(q text) returns jsonb language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  begin
    execute 'set local role service_role';
    execute 'select (' || q || ')::jsonb' into r;
    execute 'reset role';
    return coalesce(r, 'null'::jsonb);
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    return jsonb_build_object('error', e, 'msg', m);
  end;
end $f$;
create function pg_temp.err(r jsonb) returns text language sql as $f$ select coalesce(r ->> 'error', 'OK') $f$;
create function pg_temp.msg(r jsonb) returns text language sql as $f$ select coalesce(r ->> 'msg', '') $f$;
create function pg_temp.prep(p_quien text, p_cant integer, p_tipo text, p_origen text default 'campo') returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_preparar_subida(%L, %s, %L, null, %L)', p_quien, p_cant, p_origen, p_tipo)) $f$;
-- Registra una Investigación (o el formato que se indique): reserva con preparar_subida, sube las fotos al doble de Storage y crea el reporte
create function pg_temp.inv(p_quien text, p_datos jsonb, p_etqs text[] default '{}', p_contrato text default '123456', p_tipo text default 'investigacion_ubicacion',
                            p_resultado text default null, p_causal text default null, p_lat numeric default 10.46) returns jsonb language plpgsql as $f$
declare p jsonb; v_id uuid; v_f jsonb := '[]'::jsonb; v_ruta text;
begin
  p := pg_temp.prep(p_quien, coalesce(cardinality(p_etqs), 0), p_tipo);
  if p ? 'error' then return p; end if;
  v_id := (p ->> 'reporte_id')::uuid;
  for i in 1 .. coalesce(cardinality(p_etqs), 0) loop
    v_ruta := p -> 'fotos' -> (i - 1) ->> 'ruta';
    insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', v_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg'));
    v_f := v_f || jsonb_build_object('orden', i, 'ruta', v_ruta, 'etiqueta', p_etqs[i]);
  end loop;
  return pg_temp.rpc(format('public.geoportal_campo_crear_reporte(%L, %L::uuid, %L, null, %L, %L, %s, -73.25, 5, false, ''campo'', %L::jsonb, null, %L::jsonb, %L, %L, null)',
                            p_quien, v_id, p_tipo, '[PRUEBA ZTINV] investigación', p_contrato, coalesce(p_lat::text, 'null'), v_f, p_datos, p_resultado, p_causal));
end $f$;
create function pg_temp.tipo_inv(r jsonb) returns jsonb language sql as $f$
  select t from jsonb_array_elements(r -> 'grupos') g, jsonb_array_elements(g -> 'tipos') t where t ->> 'codigo' = 'investigacion_ubicacion' $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo) values
  ('ztinv.op1@emdupar.gov.co', 'ZTINV Operario 1', 'consulta', true, 'sin_restriccion', 'todos', false, true, false),
  ('ztinv.op2@emdupar.gov.co', 'ZTINV Operario 2', 'consulta', true, 'sin_restriccion', 'todos', false, true, false),
  ('ztinv.op3@emdupar.gov.co', 'ZTINV Operario 3', 'consulta', true, 'sin_restriccion', 'todos', false, true, false),
  ('ztinv.sup@emdupar.gov.co', 'ZTINV Supervisor de campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, true);

do $p1$
declare r jsonb; t jsonb; n0 bigint; v_aud bigint; S text := 'ztinv.op1@emdupar.gov.co'; S2 text := 'ztinv.op2@emdupar.gov.co'; S3 text := 'ztinv.op3@emdupar.gov.co';
  D jsonb := '{"direccion_encontrada": "[PRUEBA ZTINV] CRA 9 # 12-30"}';
begin
  -- 01: el catálogo de la Investigación como lo decidió David
  perform pg_temp.ok('01.01 Investigación: sin resultado, fotos de 0 a 6, contrato obligatorio, activa, id 35',
    (select not genera_resultado and fotos_min = 0 and fotos_max = 6 and requiere_contrato = 'si' and activo and id = 35 from campo.tipos_reporte where codigo = 'investigacion_ubicacion'));
  perform pg_temp.ok('01.02 las 3 fotos quedan opcionales y sin marca de soporte (siguen activas)',
    (select count(*) = 3 and bool_and(not f.obligatoria and not f.soporte_inefectiva and f.activo) from campo.tipo_fotos f join campo.tipos_reporte t on t.id = f.tipo_id where t.codigo = 'investigacion_ubicacion'));
  perform pg_temp.ok('01.03 campos activos: solo la dirección es obligatoria; hallazgo, barrio, habitado, tipo de predio, medidor y observación opcionales',
    (select string_agg(c.codigo || ':' || c.obligatorio, ',' order by c.orden) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id
      where t.codigo = 'investigacion_ubicacion' and c.activo) = 'hallazgo:false,direccion_encontrada:true,barrio:false,habitado:false,tipo_predio:false,medidor:false,observacion:false');
  perform pg_temp.ok('01.04 los 4 campos de despeje y visita están desactivados, no borrados',
    (select count(*) = 4 and bool_and(not c.activo) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id
      where t.codigo = 'investigacion_ubicacion' and c.codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada', 'cita_acordada')));
  perform pg_temp.ok('01.05 los campos nuevos tienen su tipo y su tope (barrio texto 80, habitado sí o no, tipo de predio 6 opciones, medidor texto 20)',
    (select string_agg(c.codigo || ':' || c.tipo_dato || ':' || coalesce(c.maximo::int::text, '-') || ':' || coalesce(jsonb_array_length(c.opciones)::text, '-'), ',' order by c.orden)
       from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id where t.codigo = 'investigacion_ubicacion' and c.codigo in ('barrio', 'habitado', 'tipo_predio', 'medidor'))
     = 'barrio:texto:80:-,habitado:si_no:-:-,tipo_predio:opcion:-:6,medidor:texto:20:-');
  perform pg_temp.ok('01.06 el cambio de catálogo quedó auditado (campo_catalogo, con antes y después)',
    exists (select 1 from public.geoportal_auditoria where accion = 'campo_catalogo' and referencia = 'tipo:investigacion_ubicacion' and detalle ->> 'paquete' = 'campo_inv_analisis'
             and detalle -> 'antes' -> 'tipo' ->> 'fotos_min' = '3' and detalle -> 'despues' -> 'tipo' ->> 'fotos_min' = '0'));
  perform pg_temp.ok('01.07 la Investigación sigue fuera del catálogo de documentos (sin PDF ni firmas)',
    not exists (select 1 from campo.formularios_documento where formulario = 'tipo:investigacion_ubicacion' and lleva_pdf));

  -- 02: lo que recibe la pantalla
  r := pg_temp.rpc(format('public.geoportal_campo_obtener_formulario(%L)', S)); t := pg_temp.tipo_inv(r);
  perform pg_temp.ok('02.01 obtener_formulario entrega la Investigación con fotos_min 0, sin resultado y sin causales',
    pg_temp.err(r) = 'OK' and (t ->> 'fotos_min')::int = 0 and (t ->> 'fotos_max')::int = 6 and t -> 'genera_resultado' = 'false'::jsonb and t -> 'causales' = '[]'::jsonb, left(coalesce(t::text, r::text), 300));
  perform pg_temp.ok('02.02 y con los 7 campos activos (los 4 desactivados no viajan)',
    jsonb_array_length(t -> 'campos') = 7 and not exists (select 1 from jsonb_array_elements(t -> 'campos') c where c ->> 'codigo' in ('despeje_caja', 'cita_acordada')), left(coalesce(t::text, ''), 300));

  -- 03: preparar_subida
  r := pg_temp.prep(S, 0, 'investigacion_ubicacion');
  perform pg_temp.ok('03.01 con la Investigación, preparar 0 fotos desde campo se acepta y reserva el identificador',
    pg_temp.err(r) = 'OK' and r ? 'reporte_id' and r -> 'fotos' = '[]'::jsonb and exists (select 1 from campo.preparaciones where reporte_id = (r ->> 'reporte_id')::uuid), r::text);
  r := pg_temp.prep(S, 0, null);
  perform pg_temp.ok('03.02 sin tipo, 0 fotos desde campo se sigue rechazando (entre 1 y …)', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like 'La cantidad de fotos debe estar entre 1 y %', r::text);
  r := pg_temp.prep(S, 0, 'suspension');
  perform pg_temp.ok('03.03 con otro formato de mínimo 3 (suspensión), 0 fotos se sigue rechazando', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like '%entre 1 y%', r::text);
  r := pg_temp.prep(S, 0, 'fraude');
  perform pg_temp.ok('03.04 con un reporte general (sin mínimo propio), 0 fotos se sigue rechazando', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like '%entre 1 y%', r::text);
  r := pg_temp.prep(S, 7, 'investigacion_ubicacion');
  perform pg_temp.ok('03.05 con la Investigación, más de 6 fotos se rechaza (entre 0 y 6)', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'La cantidad de fotos debe estar entre 0 y 6', r::text);
  r := pg_temp.prep(S, -1, 'investigacion_ubicacion');
  perform pg_temp.ok('03.06 una cantidad negativa se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.prep('ztinv.sup@emdupar.gov.co', 0, null, 'escritorio');
  perform pg_temp.ok('03.07 desde el escritorio el supervisor sigue pudiendo preparar 0 fotos (como hoy)', pg_temp.err(r) = 'OK', r::text);
  r := pg_temp.prep(S, 2, 'investigacion_ubicacion');
  perform pg_temp.ok('03.08 con la Investigación, preparar 2 fotos sigue funcionando', pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'fotos') = 2, r::text);

  -- 04: registrar una Investigación
  r := pg_temp.inv(S, D);
  perform pg_temp.ok('04.01 se registra SIN fotos y SIN los campos opcionales (contrato, dirección y XY)', pg_temp.err(r) = 'OK' and r ->> 'consecutivo' like '%INV%', r::text);
  perform pg_temp.ok('04.02 queda sin resultado ni causal y sin fotos',
    (select resultado is null and causal_id is null from campo.reportes where id = (r ->> 'id')::uuid) and not exists (select 1 from campo.reporte_fotos where reporte_id = (r ->> 'id')::uuid), r::text);
  r := pg_temp.inv(S2, D || '{"hallazgo": "ubicado", "barrio": "[PRUEBA ZTINV] Centro", "habitado": true, "tipo_predio": "lote_desocupado", "medidor": "ZT-12345", "observacion": "[PRUEBA ZTINV] reja verde"}',
                   array['fachada_nomenclatura', 'vecino_referencia']);
  perform pg_temp.ok('04.03 se registra con todos los opcionales y 2 fotos', pg_temp.err(r) = 'OK'
    and (select datos ->> 'tipo_predio' = 'lote_desocupado' and datos -> 'habitado' = 'true'::jsonb and datos ->> 'barrio' = '[PRUEBA ZTINV] Centro' from campo.reportes where id = (r ->> 'id')::uuid), r::text);
  r := pg_temp.inv(S3, '{"hallazgo": "ubicado"}');
  perform pg_temp.ok('04.04 sin la dirección encontrada se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) ilike '%dirección encontrada%', r::text);
  r := pg_temp.inv(S3, D, '{}', null);
  perform pg_temp.ok('04.05 sin contrato se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Este formato necesita el número de contrato', r::text);
  r := pg_temp.inv(S3, D, '{}', '123456', 'investigacion_ubicacion', null, null, null);
  perform pg_temp.ok('04.06 sin coordenada se rechaza (el XY sigue obligatorio)', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) ilike '%coordenada%', r::text);
  r := pg_temp.inv(S3, D, '{}', '123456', 'investigacion_ubicacion', 'efectivo');
  perform pg_temp.ok('04.07 con resultado (efectivo) se rechaza: ya no lleva resultado', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Este tipo de reporte no lleva resultado ni causal', r::text);
  r := pg_temp.inv(S3, D, '{}', '123456', 'investigacion_ubicacion', 'inefectivo', 'no_ubicado');
  perform pg_temp.ok('04.08 con resultado inefectivo y causal se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Este tipo de reporte no lleva resultado ni causal', r::text);
  r := pg_temp.inv(S3, D || '{"despeje_caja": true}');
  perform pg_temp.ok('04.09 un campo desactivado (despeje_caja) se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D || '{"tipo_predio": "bodega"}');
  perform pg_temp.ok('04.10 un tipo de predio fuera de la lista se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D || '{"habitado": "si"}');
  perform pg_temp.ok('04.11 «habitado» que no es sí o no (booleano) se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D || jsonb_build_object('barrio', repeat('B', 81)));
  perform pg_temp.ok('04.12 un barrio de más de 80 caracteres se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D || jsonb_build_object('medidor', repeat('9', 21)));
  perform pg_temp.ok('04.13 un medidor de más de 20 caracteres se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.inv(S3, D, array['fachada_nomenclatura', 'fachada_nomenclatura']);
  perform pg_temp.ok('04.14 dos fotos con la misma etiqueta se siguen rechazando', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like 'Hay dos fotos con la misma etiqueta%', r::text);

  -- 05: los demás formularios no cambian
  perform pg_temp.ok('05.01 los demás formatos de cartera conservan su resultado y su mínimo de fotos',
    (select bool_and(genera_resultado) and min(fotos_min) >= 1 from campo.tipos_reporte where codigo in ('suspension', 'corte', 'levantamiento_acometida', 'verificacion_posterior', 'reinstalacion')));
  perform pg_temp.ok('05.02 las fotos y los campos de los demás formatos no cambiaron (ningún cambio fuera de la Investigación)',
    not exists (select 1 from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id where t.codigo <> 'investigacion_ubicacion' and c.codigo in ('barrio', 'habitado', 'tipo_predio', 'medidor') and c.creado_en > now() - interval '1 hour'));
  r := pg_temp.rpc(format('public.geoportal_campo_obtener_formulario(%L)', S));
  select x into t from jsonb_array_elements(r -> 'grupos') g, jsonb_array_elements(g -> 'tipos') x where x ->> 'codigo' = 'suspension';
  perform pg_temp.ok('05.03 la pantalla sigue recibiendo la suspensión con mínimo 3 fotos, con resultado y con causales',
    (t ->> 'fotos_min')::int = 3 and t -> 'genera_resultado' = 'true'::jsonb and jsonb_array_length(t -> 'causales') > 0, left(coalesce(t::text, r::text), 300));

  -- 06: lo que no se toca
  perform pg_temp.ok('06.01 la huella del acta no cambió (111506c690249ad3b56ebf572566434c)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '111506c690249ad3b56ebf572566434c');
  perform pg_temp.ok('06.02 crear_reporte no cambió', md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)'))) = '51ecb98ca2e7f940c66b9a1f3e828222');
  perform pg_temp.ok('06.03 las 4 funciones de permisos vivas no cambiaron', md5(pg_get_functiondef(to_regprocedure('public.geoportal_puede(text,text)'))) = '32f174a55b95788d3f8187b507303c2f' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_mis_permisos(text)'))) = '83166fe17be58da67bbdedaae429bedb' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)'))) = '01fda69a9d912067b8b4dc153ac7957e' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'))) = 'e5a90103b4a83440fd826f03266b7245');
  perform pg_temp.ok('06.04 preparar_subida sigue solo para service_role',
    has_function_privilege('service_role', 'public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'execute'));
  perform pg_temp.ok('06.05 ninguna función de campo con DELETE o UPDATE sin WHERE', (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0);
  perform pg_temp.ok('06.06 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
end $p1$;

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztinv_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;

rollback;
