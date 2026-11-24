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
  if to_regprocedure('public.geoportal_campo_analisis_observar(text,text,text,text,text,jsonb,text)') is not null then
    raise exception 'Este paquete ya parece aplicado (existe geoportal_campo_analisis_observar): use la reversa antes de repetir';
  end if;
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
  for r in select * from (values ('public.geoportal_campo_preparar_subida(text,integer,text,text,text)', '6a2ef927316ed4aa2936eadfb9b0a0cd'), ('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)', '51ecb98ca2e7f940c66b9a1f3e828222'), ('public.geoportal_campo_obtener_formulario(text,boolean)', 'da253b2da0128848595788795f61479f'), ('campo.f_validar_datos(bigint,jsonb,boolean)', 'f3d09600df18aa558e5bc046d6934f70'), ('campo.f_derivada_json(bigint)', '2c92614fda3832cd4376533500cc0113'), ('public.geoportal_campo_derivadas(text,jsonb,text)', '35ac3ce1111ef01ec6c5ba08b8943782'), ('public.geoportal_campo_derivada_atender(text,bigint,text,uuid,text)', '7b622c0ea2113d37136d1e922ecd7e58'), ('public.geoportal_campo_derivadas_abiertas(text,text,text,text)', '1e4790a396c3927d7aad719be1b89779'), ('public.geoportal_campo_derivada_cerrar(text,bigint,text,text,text)', '1b619e3df442094c608664736ddf2c88'), ('public.geoportal_campo_analisis_contrato(text,text,text)', 'fedc868f147c9d3a92b1f9e938fa06ed'), ('public.geoportal_campo_datos_sensibles(text,uuid,text)', 'c5a5cabc783de55665b0cad3f2e57723'), ('campo.f_derivada_estado(bigint)', 'f612ec315fb7c6e90c373884a3104658'), ('campo.f_derivadas_al_registrar()', '1bd3428f82b6707496dffbc01906574a'), ('campo.f_registradas_filtradas(jsonb)', 'ce67a4c8520814af312f64d04a55ebed'), ('campo.f_motivo_personal(text,boolean)', '4d7f94c08ca8e75bb724e21d9b93e272'), ('campo.f_telefonos(text)', 'e176e6286eeccaf224ac72af5cfa9712'), ('campo.f_autorizar_supervision(text)', '5ac3368fa5f3a6347328285501894aec'), ('campo.f_autorizar_analisis(text)', 'e83b8d7eeeaede7665c3d25bb9ae4c36'), ('campo.f_autorizar_registradas(text)', '63cf95ebacedebc2622171f7df9b2df2'), ('campo.f_autorizar_documento(text,text,uuid)', 'a54711241d29ff33a8930a948d011b3f'), ('campo.f_solo_agregar()', '2a27744a1110ddd5bf835b2b65a3a671'), ('campo.f_error(text,text)', '6439032aae6fe0575c94fb32f85f109f'), ('campo.f_auditar(text,text,text,jsonb,text)', '67bbec1b5d638525595b52666ecb3bcd'), ('public.geoportal_puede(text,text)', '32f174a55b95788d3f8187b507303c2f'), ('public.geoportal_mis_permisos(text)', '83166fe17be58da67bbdedaae429bedb'), ('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)', '01fda69a9d912067b8b4dc153ac7957e'), ('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)', 'e5a90103b4a83440fd826f03266b7245')) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la publicada: deténgase y avise', r.f;
    end if;
  end loop;
  -- Estructura exacta de las tablas vivas (la misma expresión que calcula generar.py en el doble, que es copia exacta de producción)
  -- (m2: el estado que deja la reversa de este paquete, que conserva la estructura; nada se borra)
  for r in select * from (values ('campo.tipos_reporte', '3b9274b039c86b8079fee77b484ad5e1', null::text), ('campo.tipo_campos', '9628451c9105875e1c7b2ac2421691a5', null::text), ('campo.tipo_fotos', 'fcce3283ea598e0c1b4f2aeafdd0e9ae', null::text), ('campo.actividades', '9a20496e1319d07650a5e4460a523d64', null::text), ('campo.derivadas', '2ebfe8b36411e10e364231ddbbee8f67', '28a6a571a358b128740ef775974b1225'), ('campo.derivadas_catalogo', '4b406fe705b31222fad55e6abf064c28', null::text), ('campo.derivada_eventos', 'd01fd6ead43730a491b927f36c3136a9', null::text), ('campo.consultas_analisis', '1202c7e6e2999e2d5adaccd2e371320d', null::text), ('campo.causales_tipos', '71502cd2b2d048f6d3bf01a6cc188d0d', null::text), ('campo.formularios_documento', 'b83ea82f1765747e4b8ce6532aff3fc6', null::text), ('campo.grupos_reporte', 'ba97afc37aee73287dc7d000c664b749', null::text)) x(t, m, m2) loop
    if to_regclass(r.t) is null then raise exception 'No existe la tabla %: deténgase y avise', r.t; end if;
    select md5(concat_ws('#', (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped), (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel), (select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel), (select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal), (select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel))) into v from (select to_regclass(r.t) as rel) z;
    if v is distinct from r.m and v is distinct from coalesce(r.m2, r.m) then
      raise exception 'La estructura de % no es la de producción (columnas, restricciones, índices, disparadores, RLS o permisos): deténgase y avise', r.t;
    end if;
  end loop;
  -- Las tablas nuevas: no existen, o existen exactamente como las crea este paquete (las conservó una reversa)
  for r in select * from (values ('campo.analisis_observaciones', '8215ffbd87376df4a32f6572808058ed'), ('campo.analisis_observacion_datos', '63f4f4d56c7fdc55c87301a014a6aef8'), ('campo.analisis_observacion_anulaciones', '04b4d45b71109783285d3cc0f1eec1ab')) x(t, m) loop
    if to_regclass(r.t) is not null then
      select md5(concat_ws('#', (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped), (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel), (select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel), (select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal), (select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel))) into v from (select to_regclass(r.t) as rel) z;
      if v is distinct from r.m then raise exception 'La tabla % ya existe y no es la de este paquete: deténgase y avise', r.t; end if;
    end if;
  end loop;
  -- Sin políticas RLS en campo ni acta (David, 23-nov): el Dell lee porque homelab_lectura tiene BYPASSRLS; basta el GRANT SELECT explícito
  if exists (select 1 from pg_policies where schemaname in ('campo', 'acta')) then
    raise exception 'Hay políticas RLS en campo o acta: este paquete se preparó para ninguna; deténgase y avise';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'homelab_lectura' and rolbypassrls) then
    raise exception 'No existe el rol homelab_lectura con BYPASSRLS: deténgase y avise';
  end if;
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
-- Opcionales: hallazgo (deja de ser obligatorio), barrio (texto), ¿habitado? (sí o no), tipo de predio (opción), medidor (texto); y la descripción general «Observaciones».
-- Sin resultado (efectiva / inefectiva) ni causal; las 3 fotos opcionales y sin marca de soporte; de 0 a 6 fotos.
-- Se DESACTIVAN (no se borran): despeje_caja, despeje_observacion, visita_concertada, cita_acordada y observacion (queda una sola caja de texto: «Observaciones»).
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
  -- David (23-nov, revisión del commit 5): una sola caja de texto; se desactiva «observacion» y su aviso pasa a «Observaciones» (descripción general) en la pantalla
  update campo.tipo_campos set activo = false where tipo_id = v_t and codigo = 'observacion';
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
-- INVESTIGACIÓN Y ANÁLISIS · 30 — AVISOS DEL ANÁLISIS DE CONTRATO: estructura (decisiones de David del 23-nov, §2 y §6 del encargo)
-- Toda observación es un AVISO al supervisor (ninguna genera actividad sola). El aviso es una fila de campo.derivadas enlazada a la
-- observación por observacion_id (origen_id queda nulo en esas filas). Desde el aviso, el supervisor «Crea actividad» (otra derivada
-- con el mismo observacion_id y un destino propio) o lo cierra como hoy.
-- Datos personales de «Actualización de datos» (Ley 1581): tabla aparte, sin permisos para la API, solo la lee una RPC del supervisor.
-- Todas las tablas nuevas: solo inserción, RLS activa sin políticas (como todo campo), revoke all a public, anon, authenticated y
-- service_role, y SELECT explícito a homelab_lectura (respaldo cifrado del Dell; cambio de D2, 23-nov 22:42), sin ALTER DEFAULT PRIVILEGES.
-- Si una reversa conservó la estructura (nada se borra), no se repite: se reutiliza.
-- =====================================================================
do $estructura$
begin
  if to_regclass('campo.analisis_observaciones') is not null then
    raise notice 'La estructura de los avisos se conservó de una reversa: se reutiliza';
    return;
  end if;

  create table campo.analisis_observaciones (
    id                 uuid primary key default gen_random_uuid(),
    contrato           text not null check (contrato ~ '^\d{1,12}$' and contrato <> '99999999'),
    tipo               text not null check (tipo in ('desocupado', 'direccion_errada', 'actualizacion_datos', 'otra')),
    texto              text check (texto is null or (length(texto) between 3 and 120 and texto = btrim(texto))),
    direccion_correcta text check (direccion_correcta is null or (length(direccion_correcta) between 3 and 120 and direccion_correcta = btrim(direccion_correcta))),
    autor              text not null check (autor = lower(autor) and position('@' in autor) > 1),
    creado_en          timestamptz not null default clock_timestamp(),
    ip                 text check (ip is null or length(ip) <= 64),
    constraint analisis_observaciones_texto_ck check ((tipo = 'otra') = (texto is not null)),
    constraint analisis_observaciones_direccion_ck check (direccion_correcta is null or tipo = 'direccion_errada')
  );
  create index analisis_observaciones_contrato_idx on campo.analisis_observaciones (contrato, creado_en desc);
  create trigger t_solo_agregar before delete or update on campo.analisis_observaciones for each row execute function campo.f_solo_agregar();
  create trigger t_solo_agregar_trunc before truncate on campo.analisis_observaciones for each statement execute function campo.f_solo_agregar();
  comment on table campo.analisis_observaciones is 'Observaciones que marca quien tiene Análisis de contrato (desocupado, dirección errada, actualización de datos, otra). Cada una crea un aviso en campo.derivadas. Solo inserción. Sin nombres, cédulas ni teléfonos: esos van solo en campo.analisis_observacion_datos.';

  create table campo.analisis_observacion_datos (
    observacion_id uuid primary key references campo.analisis_observaciones (id),
    datos          jsonb not null check (jsonb_typeof(datos) = 'object' and datos <> '{}'::jsonb and octet_length(datos::text) <= 1024
                                         and (datos - array['nombre', 'cedula', 'telefono', 'correo', 'relacion']) = '{}'::jsonb),
    registrado_en  timestamptz not null default clock_timestamp()
  );
  create trigger t_solo_agregar before delete or update on campo.analisis_observacion_datos for each row execute function campo.f_solo_agregar();
  create trigger t_solo_agregar_trunc before truncate on campo.analisis_observacion_datos for each statement execute function campo.f_solo_agregar();
  comment on table campo.analisis_observacion_datos is 'SENSIBLE (Ley 1581): datos de contacto de «Actualización de datos» (nombre, cédula, teléfono, correo, relación con el predio). Solo los lee geoportal_campo_aviso_datos (supervisor de campo y administrador), con lectura auditada; nunca en listas, exportaciones generales ni mapa. homelab_lectura la lee solo para el respaldo cifrado. Solo inserción: si estaban mal, se anulan con motivo (campo.analisis_observacion_anulaciones).';

  create table campo.analisis_observacion_anulaciones (
    observacion_id uuid primary key references campo.analisis_observacion_datos (observacion_id),
    motivo         text not null check (length(btrim(motivo)) between 10 and 300),
    autor          text not null check (autor = lower(autor) and position('@' in autor) > 1),
    creado_en      timestamptz not null default clock_timestamp(),
    ip             text check (ip is null or length(ip) <= 64)
  );
  create trigger t_solo_agregar before delete or update on campo.analisis_observacion_anulaciones for each row execute function campo.f_solo_agregar();
  create trigger t_solo_agregar_trunc before truncate on campo.analisis_observacion_anulaciones for each statement execute function campo.f_solo_agregar();
  comment on table campo.analisis_observacion_anulaciones is 'Anulación de los datos de contacto de una observación (una por observación), con motivo. Los datos quedan guardados; anulados, ya no se muestran.';

  alter table campo.analisis_observaciones enable row level security;
  alter table campo.analisis_observacion_datos enable row level security;
  alter table campo.analisis_observacion_anulaciones enable row level security;
  revoke all on campo.analisis_observaciones, campo.analisis_observacion_datos, campo.analisis_observacion_anulaciones from public, anon, authenticated, service_role;
  grant select on campo.analisis_observaciones, campo.analisis_observacion_datos, campo.analisis_observacion_anulaciones to homelab_lectura;

  -- campo.derivadas: el aviso y la actividad que crea el supervisor se enlazan a la observación; las de las revisiones no cambian
  alter table campo.derivadas add column observacion_id uuid references campo.analisis_observaciones (id);
  alter table campo.derivadas add column destino text check (destino is null or destino ~ '^tipo:[a-z][a-z0-9_]{1,59}$');
  alter table campo.derivadas alter column origen_id drop not null;
  alter table campo.derivadas add constraint derivadas_origen_ck check (num_nonnulls(origen_id, observacion_id) = 1);
  alter table campo.derivadas add constraint derivadas_destino_ck check (destino is null or observacion_id is not null);
  alter table campo.derivadas add constraint derivadas_observacion_id_actividad_key unique (observacion_id, actividad);
end $estructura$;

-- Catálogo de derivadas: los 4 avisos y la actividad que crea el supervisor (sin destinos propios). Si una reversa los desactivó, se reactivan.
insert into campo.derivadas_catalogo (codigo, nombre, destinos, destino_omision, activa, orden, autor) values
  ('aviso_desocupado', 'Aviso: predio desocupado', '{}', null, true, 60, 'migracion@geoportal'),
  ('aviso_direccion_errada', 'Aviso: dirección errada', '{}', null, true, 61, 'migracion@geoportal'),
  ('aviso_actualizacion_datos', 'Aviso: actualización de datos', '{}', null, true, 62, 'migracion@geoportal'),
  ('aviso_otra', 'Aviso: otra observación', '{}', null, true, 63, 'migracion@geoportal'),
  ('actividad_supervisor', 'Actividad creada por el supervisor', '{}', null, true, 64, 'migracion@geoportal')
on conflict (codigo) do update set activa = true;

-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 40 — AVISOS DEL ANÁLISIS DE CONTRATO: funciones
-- Cambian (respaldo y md5 en la guardia y en la reversa): campo.f_derivada_json, geoportal_campo_derivadas (filtro «origen»),
-- geoportal_campo_derivada_atender y geoportal_campo_derivadas_abiertas (usan el destino propio de la derivada si lo hay).
-- Nuevas: campo.f_contacto y campo.f_texto_sin_datos (validan), geoportal_campo_analisis_observar (marca), geoportal_campo_aviso_crear_actividad,
-- geoportal_campo_aviso_datos y geoportal_campo_aviso_datos_anular (supervisor de campo y administrador).
-- Ninguna lleva DELETE ni UPDATE.
-- =====================================================================

-- Datos de contacto de «Actualización de datos»: valida y normaliza. Las casillas vacías no cuentan; ninguna casilla = null.
create function campo.f_contacto(p jsonb) returns jsonb
language plpgsql immutable set search_path = pg_catalog, campo, pg_temp as $f$
declare v jsonb := '{}'::jsonb; k text; x text;
begin
  if p is null or p = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p) <> 'object' then perform campo.f_error('Los datos de contacto no tienen el formato esperado'); end if;
  select min(key) into k from jsonb_object_keys(p) key where key not in ('nombre', 'cedula', 'telefono', 'correo', 'relacion');
  if k is not null then perform campo.f_error(format('El dato «%s» no se recibe', left(k, 40))); end if;
  for k in select key from jsonb_object_keys(p) key loop
    if jsonb_typeof(p -> k) not in ('string', 'null') then perform campo.f_error(format('El dato «%s» debe ser un texto', k)); end if;
  end loop;
  x := nullif(btrim(regexp_replace(coalesce(p ->> 'nombre', ''), '\s+', ' ', 'g')), '');
  if x is not null then
    if length(x) < 2 or length(x) > 80 or x ~ '\d' or x !~ '^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ .''-]*$' then
      perform campo.f_error('El nombre debe tener entre 2 y 80 letras, sin números');
    end if;
    v := v || jsonb_build_object('nombre', x);
  end if;
  x := nullif(btrim(coalesce(p ->> 'cedula', '')), '');
  if x is not null then
    if x !~ '^\d{5,10}$' then perform campo.f_error('La cédula debe tener solo números, entre 5 y 10'); end if;
    v := v || jsonb_build_object('cedula', x);
  end if;
  x := nullif(regexp_replace(coalesce(p ->> 'telefono', ''), '[\s()-]', '', 'g'), '');
  if x is not null then
    if x !~ '^(\d{7}|3\d{9}|60\d{8})$' then perform campo.f_error('El teléfono debe tener 7 o 10 números; si tiene 10, empieza por 3 o por 60'); end if;
    v := v || jsonb_build_object('telefono', x);
  end if;
  x := nullif(lower(btrim(coalesce(p ->> 'correo', ''))), '');
  if x is not null then
    if length(x) > 120 or x !~ '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$' then perform campo.f_error('El correo no tiene un formato válido'); end if;
    v := v || jsonb_build_object('correo', x);
  end if;
  x := nullif(btrim(coalesce(p ->> 'relacion', '')), '');
  if x is not null then
    if x not in ('propietario', 'arrendatario', 'familiar', 'encargado', 'otro') then
      perform campo.f_error('La relación con el predio debe ser propietario, arrendatario, familiar, encargado u otro');
    end if;
    v := v || jsonb_build_object('relacion', x);
  end if;
  return nullif(v, '{}'::jsonb);
end $f$;

-- Textos libres del aviso (texto de «Otra» y dirección correcta): sin teléfonos ni números largos (cédulas). Devuelve el texto limpio o null.
create function campo.f_texto_sin_datos(p_texto text, p_que text, p_min integer, p_max integer) returns text
language plpgsql immutable set search_path = pg_catalog, campo, pg_temp as $f$
declare v text := nullif(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), '');
begin
  if v is null then return null; end if;
  if length(v) < p_min or length(v) > p_max then perform campo.f_error(format('%s debe tener entre %s y %s caracteres', p_que, p_min, p_max)); end if;
  if coalesce(cardinality(campo.f_telefonos(v)), 0) > 0 or v ~ '\d{6,}' then
    perform campo.f_error(format('%s no puede llevar teléfonos ni cédulas: esos datos van en sus casillas de «Actualización de datos»', p_que));
  end if;
  return v;
end $f$;

CREATE OR REPLACE FUNCTION campo.f_derivada_json(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'campo', 'pg_temp'
AS $function$
  -- Investigación y Análisis (23-nov): el origen es un registro (revisión, PQR, instalación) o una observación del Análisis de contrato.
  -- Sin datos de contacto: solo «trae_datos» y «datos_anulados». El destino propio de la derivada (actividad creada por el supervisor) manda sobre el del catálogo.
  select jsonb_build_object('id', d.id, 'actividad', d.actividad, 'actividad_nombre', c.nombre, 'contrato', d.contrato, 'estado', campo.f_derivada_estado(d.id), 'creada_en', d.creado_en,
           'destinos', case when d.destino is not null then jsonb_build_array(d.destino) else to_jsonb(c.destinos) end,
           'destino_omision', coalesce(d.destino, c.destino_omision),
           'destino_nombre', (select t2.nombre from campo.tipos_reporte t2 where 'tipo:' || t2.codigo = d.destino),
           'origen', case when d.origen_id is not null then
               jsonb_build_object('clase', 'registro', 'registro_id', r.id, 'tipo', t.codigo, 'tipo_nombre', t.nombre, 'consecutivo', r.consecutivo, 'fecha', r.registrado_en, 'operario', r.autor)
             else
               jsonb_build_object('clase', 'analisis', 'observacion_id', o.id, 'tipo', 'analisis_contrato', 'tipo_nombre', 'Análisis de contrato', 'observacion', o.tipo,
                                  'observacion_nombre', case o.tipo when 'desocupado' then 'Desocupado' when 'direccion_errada' then 'Dirección errada'
                                                                    when 'actualizacion_datos' then 'Actualización de datos' else 'Otra' end,
                                  'texto', o.texto, 'direccion_correcta', o.direccion_correcta, 'fecha', o.creado_en, 'operario', o.autor,
                                  'trae_datos', exists (select 1 from campo.analisis_observacion_datos x where x.observacion_id = o.id),
                                  'datos_anulados', exists (select 1 from campo.analisis_observacion_anulaciones x where x.observacion_id = o.id),
                                  'aviso_id', (select a.id from campo.derivadas a where a.observacion_id = o.id and a.actividad like 'aviso\_%'),
                                  'actividad_creada_id', (select a.id from campo.derivadas a where a.observacion_id = o.id and a.actividad = 'actividad_supervisor'))
             end,
           'cierre', (select jsonb_build_object('tipo', e.tipo_evento, 'esquema', e.esquema, 'registro_id', e.registro_id, 'autor', e.autor, 'en', e.creado_en, 'motivo', e.motivo,
                                                 'consecutivo', case e.esquema when 'campo' then (select x.consecutivo from campo.reportes x where x.id = e.registro_id)
                                                                               when 'acta' then (select x.consecutivo from acta.actas x where x.id = e.registro_id) end)
                        from campo.derivada_eventos e where e.derivada_id = d.id))
    from campo.derivadas d join campo.derivadas_catalogo c on c.codigo = d.actividad
    left join campo.reportes r on r.id = d.origen_id left join campo.tipos_reporte t on t.id = r.tipo_id
    left join campo.analisis_observaciones o on o.id = d.observacion_id
   where d.id = p_id
$function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivadas(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_est text; v_con text; v_act text; v_desde date; v_hasta date; v_antes bigint; v_lim integer; v_filas jsonb; v_n integer;
  v_ori text;   -- Investigación y Análisis (23-nov): «registro» (revisiones, PQR, instalación) o «analisis» (avisos del Análisis de contrato)
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_est := nullif(f ->> 'estado', ''); v_con := nullif(btrim(coalesce(f ->> 'contrato', '')), ''); v_act := nullif(f ->> 'actividad', '');
    v_desde := nullif(f ->> 'desde', '')::date; v_hasta := nullif(f ->> 'hasta', '')::date; v_antes := nullif(f ->> 'antes', '')::bigint;
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 50), 1), 200);
    v_ori := nullif(f ->> 'origen', '');
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  if v_est is not null and v_est not in ('pendiente', 'atendida', 'atendida_fuera', 'anulada') then perform campo.f_error('El estado no es válido'); end if;
  if v_ori is not null and v_ori not in ('registro', 'analisis') then perform campo.f_error('El origen no es válido'); end if;
  select count(*), coalesce(jsonb_agg(campo.f_derivada_json(x.id) order by x.id desc) filter (where x.rn <= v_lim), '[]'::jsonb) into v_n, v_filas
    from (select d.id, row_number() over (order by d.id desc) as rn from campo.derivadas d
           where (v_est is null or campo.f_derivada_estado(d.id) = v_est) and (v_con is null or d.contrato = v_con) and (v_act is null or d.actividad = v_act)
             and (v_ori is null or (v_ori = 'registro' and d.origen_id is not null) or (v_ori = 'analisis' and d.observacion_id is not null))
             and (v_desde is null or (d.creado_en at time zone 'America/Bogota')::date >= v_desde) and (v_hasta is null or (d.creado_en at time zone 'America/Bogota')::date <= v_hasta)
             and (v_antes is null or d.id < v_antes) order by d.id desc limit v_lim + 1) x;
  return jsonb_build_object('filas', v_filas, 'siguiente', case when v_n > v_lim then (select min((e ->> 'id')::bigint) from jsonb_array_elements(v_filas) e) end);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivada_atender(p_solicitante text, p_derivada_id bigint, p_esquema text, p_registro_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'acta', 'pg_temp'
AS $function$
declare v_email text; v_d campo.derivadas; v_c campo.derivadas_catalogo; v_form text; v_con text; v_autor text;
begin
  v_email := campo.f_autorizar_documento(p_solicitante, p_esquema, p_registro_id);
  perform pg_advisory_xact_lock(hashtext('campo_derivada:' || p_derivada_id));
  select * into v_d from campo.derivadas where id = p_derivada_id;
  if v_d.id is null then perform campo.f_error('Esa actividad derivada no existe', 'P0002'); end if;
  select * into v_c from campo.derivadas_catalogo where codigo = v_d.actividad;
  if campo.f_derivada_estado(v_d.id) <> 'pendiente' then perform campo.f_error('Esa actividad derivada ya está cerrada', '55000'); end if;
  if p_esquema = 'campo' then select 'tipo:' || t.codigo, r.contrato, r.autor into v_form, v_con, v_autor from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id where r.id = p_registro_id;
  else select 'acta', a.contrato, a.autor into v_form, v_con, v_autor from acta.actas a where a.id = p_registro_id; end if;
  -- Investigación y Análisis (23-nov): la actividad que crea el supervisor trae su propio destino
  if not (v_form = any (case when v_d.destino is not null then array[v_d.destino] else v_c.destinos end)) then perform campo.f_error('Ese formulario no atiende esa actividad derivada'); end if;
  if v_con is distinct from v_d.contrato then perform campo.f_error('El registro es de otro contrato'); end if;
  if v_d.origen_id is not null and p_registro_id = v_d.origen_id then perform campo.f_error('Una revisión no atiende sus propias actividades derivadas'); end if;
  insert into campo.derivada_eventos (derivada_id, tipo_evento, esquema, registro_id, autor) values (v_d.id, 'atendida', p_esquema, p_registro_id, v_email);
  perform campo.f_auditar(v_email, 'campo_derivada_atender', v_d.id::text, jsonb_build_object('esquema', p_esquema, 'registro', p_registro_id), p_ip);
  return campo.f_derivada_json(v_d.id);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivadas_abiertas(p_solicitante text, p_contrato text, p_formulario text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'acta', 'pg_temp'
AS $function$
declare v_email text; v_con text := nullif(btrim(coalesce(p_contrato, '')), '');
begin
  if p_formulario = 'acta' then v_email := acta.f_autorizar(p_solicitante, 'capturar'); else v_email := campo.f_verificar(p_solicitante, 'campo'); end if;
  if v_con is null then return jsonb_build_object('derivadas', '[]'::jsonb); end if;
  -- Investigación y Análisis (23-nov): la actividad que crea el supervisor trae su propio destino; los avisos no tienen destino y no aparecen
  return jsonb_build_object('derivadas', (select coalesce(jsonb_agg(campo.f_derivada_json(d.id) order by d.id), '[]'::jsonb)
    from campo.derivadas d join campo.derivadas_catalogo c on c.codigo = d.actividad
   where d.contrato = v_con and p_formulario = any (case when d.destino is not null then array[d.destino] else c.destinos end) and campo.f_derivada_estado(d.id) = 'pendiente'));
end $function$;

-- Marcar una observación desde el Análisis de contrato (quien tenga Análisis y haya consultado ese contrato en las últimas 12 horas)
create function public.geoportal_campo_analisis_observar(p_solicitante text, p_contrato text, p_tipo text, p_texto text default null, p_direccion text default null,
                                                         p_contacto jsonb default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $f$
declare v_email text; v_c text := btrim(coalesce(p_contrato, '')); v_tipo text := btrim(coalesce(p_tipo, '')); v_txt text; v_dir text; v_con jsonb;
  v_obs uuid; v_der bigint; v_prev bigint;
begin
  v_email := campo.f_autorizar_analisis(p_solicitante);
  if v_c !~ '^\d{1,12}$' then perform campo.f_error('Escriba solo los números del contrato (hasta 12 dígitos)'); end if;
  if v_c = '99999999' then perform campo.f_error('El contrato comodín no admite observaciones'); end if;
  if v_tipo not in ('desocupado', 'direccion_errada', 'actualizacion_datos', 'otra') then
    perform campo.f_error('La observación debe ser desocupado, dirección errada, actualización de datos u otra');
  end if;
  if not exists (select 1 from campo.consultas_analisis q where q.autor = v_email and q.contrato = v_c and q.existe and q.consultado_en > clock_timestamp() - interval '12 hours') then
    perform campo.f_error('Primero consulte el contrato en el Análisis (la observación se marca sobre un contrato consultado en las últimas 12 horas)', '55000');
  end if;
  v_txt := campo.f_texto_sin_datos(p_texto, 'El texto de «Otra»', 3, 120);
  v_dir := campo.f_texto_sin_datos(p_direccion, 'La dirección correcta', 3, 120);
  v_con := campo.f_contacto(p_contacto);
  if (v_tipo = 'otra') <> (v_txt is not null) then
    perform campo.f_error(case when v_tipo = 'otra' then 'Escriba la observación (entre 3 y 120 caracteres)' else 'El texto corto solo va en «Otra»' end);
  end if;
  if v_dir is not null and v_tipo <> 'direccion_errada' then perform campo.f_error('La dirección correcta solo va en «Dirección errada»'); end if;
  if v_con is not null and v_tipo <> 'actualizacion_datos' then perform campo.f_error('Los datos de contacto solo van en «Actualización de datos»'); end if;

  perform pg_advisory_xact_lock(hashtext('campo_aviso:' || v_c));
  -- Sin doble registro: si ya hay un aviso pendiente del mismo contrato y la misma observación, se devuelve ese y no se guarda nada
  select d.id into v_prev from campo.derivadas d
   where d.contrato = v_c and d.actividad = 'aviso_' || v_tipo and campo.f_derivada_estado(d.id) = 'pendiente' order by d.id limit 1;
  if v_prev is not null then
    return jsonb_build_object('repetida', true, 'derivada_id', v_prev, 'tipo', v_tipo, 'contrato', v_c);
  end if;

  insert into campo.analisis_observaciones (contrato, tipo, texto, direccion_correcta, autor, ip) values (v_c, v_tipo, v_txt, v_dir, v_email, left(p_ip, 64)) returning id into v_obs;
  if v_con is not null then insert into campo.analisis_observacion_datos (observacion_id, datos) values (v_obs, v_con); end if;
  insert into campo.derivadas (observacion_id, contrato, actividad) values (v_obs, v_c, 'aviso_' || v_tipo) returning id into v_der;
  -- Auditoría sin el contrato (queda en la bitácora del análisis, decisión 15) ni los textos ni los datos de contacto
  perform campo.f_auditar(v_email, 'campo_analisis_observar', v_obs::text, jsonb_build_object('tipo', v_tipo, 'derivada', v_der, 'trae_datos', v_con is not null), p_ip);
  return jsonb_build_object('repetida', false, 'observacion_id', v_obs, 'derivada_id', v_der, 'tipo', v_tipo, 'contrato', v_c, 'trae_datos', v_con is not null);
end $f$;

-- «Crear actividad» desde un aviso (Q1): una sola por aviso; el aviso se cierra solo como «atendida fuera» con motivo automático
create function public.geoportal_campo_aviso_crear_actividad(p_solicitante text, p_derivada_id bigint, p_formulario text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $f$
declare v_email text; v_d campo.derivadas; v_t campo.tipos_reporte; v_nueva bigint; v_form text := btrim(coalesce(p_formulario, ''));
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  perform pg_advisory_xact_lock(hashtext('campo_derivada:' || p_derivada_id));
  select * into v_d from campo.derivadas where id = p_derivada_id;
  if v_d.id is null then perform campo.f_error('Ese aviso no existe', 'P0002'); end if;
  if v_d.observacion_id is null or v_d.actividad not like 'aviso\_%' then perform campo.f_error('Solo se crea una actividad desde un aviso del Análisis de contrato'); end if;
  if campo.f_derivada_estado(v_d.id) <> 'pendiente' then perform campo.f_error('Ese aviso ya está cerrado', '55000'); end if;
  select t.* into v_t from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where 'tipo:' || t.codigo = v_form and t.activo and g.activo and t.requiere_contrato = 'si';
  if v_t.id is null then perform campo.f_error('Elija un formulario activo que pida el contrato'); end if;
  insert into campo.derivadas (observacion_id, contrato, actividad, destino) values (v_d.observacion_id, v_d.contrato, 'actividad_supervisor', v_form) returning id into v_nueva;
  insert into campo.derivada_eventos (derivada_id, tipo_evento, motivo, autor) values (v_d.id, 'atendida_fuera', left('Se creó la actividad: ' || v_t.nombre, 300), v_email);
  perform campo.f_auditar(v_email, 'campo_aviso_crear_actividad', v_d.id::text, jsonb_build_object('actividad', v_nueva, 'formulario', v_form), p_ip);
  return jsonb_build_object('aviso', campo.f_derivada_json(v_d.id), 'actividad', campo.f_derivada_json(v_nueva));
end $f$;

-- Ver los datos de contacto de un aviso (supervisor de campo y administrador); lectura auditada sin los valores. Anulados: solo el motivo (Q2).
create function public.geoportal_campo_aviso_datos(p_solicitante text, p_derivada_id bigint, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $f$
declare v_email text; v_obs uuid; v_datos jsonb; v_an campo.analisis_observacion_anulaciones;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select d.observacion_id into v_obs from campo.derivadas d where d.id = p_derivada_id;
  if v_obs is null then perform campo.f_error('Ese aviso no existe o no es del Análisis de contrato', 'P0002'); end if;
  select x.datos into v_datos from campo.analisis_observacion_datos x where x.observacion_id = v_obs;
  if v_datos is null then perform campo.f_error('Ese aviso no tiene datos de contacto', 'P0002'); end if;
  select * into v_an from campo.analisis_observacion_anulaciones a where a.observacion_id = v_obs;
  perform campo.f_auditar(v_email, 'campo_ver_datos_contacto', p_derivada_id::text,
                          jsonb_build_object('campos', (select jsonb_agg(k order by k) from jsonb_object_keys(v_datos) k), 'anulados', v_an.observacion_id is not null), p_ip);
  if v_an.observacion_id is not null then
    return jsonb_build_object('derivada_id', p_derivada_id, 'anulados', true, 'motivo', v_an.motivo, 'anulados_en', v_an.creado_en, 'anulados_por', v_an.autor);
  end if;
  return jsonb_build_object('derivada_id', p_derivada_id, 'anulados', false, 'datos', v_datos);
end $f$;

-- Anular los datos de contacto (estaban mal): quedan guardados, ya no se muestran
create function public.geoportal_campo_aviso_datos_anular(p_solicitante text, p_derivada_id bigint, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $f$
declare v_email text; v_obs uuid; v_m text;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  v_m := campo.f_motivo_personal(p_motivo, true);
  select d.observacion_id into v_obs from campo.derivadas d where d.id = p_derivada_id;
  if v_obs is null then perform campo.f_error('Ese aviso no existe o no es del Análisis de contrato', 'P0002'); end if;
  perform pg_advisory_xact_lock(hashtext('campo_aviso_datos:' || v_obs));
  if not exists (select 1 from campo.analisis_observacion_datos x where x.observacion_id = v_obs) then perform campo.f_error('Ese aviso no tiene datos de contacto', 'P0002'); end if;
  if exists (select 1 from campo.analisis_observacion_anulaciones a where a.observacion_id = v_obs) then perform campo.f_error('Esos datos ya están anulados', '55000'); end if;
  insert into campo.analisis_observacion_anulaciones (observacion_id, motivo, autor, ip) values (v_obs, v_m, v_email, left(p_ip, 64));
  perform campo.f_auditar(v_email, 'campo_anular_datos_contacto', p_derivada_id::text, '{}'::jsonb, p_ip);
  return jsonb_build_object('derivada_id', p_derivada_id, 'anulados', true, 'motivo', v_m);
end $f$;

-- Permisos: las funciones nuevas, primero sin permisos para nadie; las 4 RPC, solo service_role (la Edge). CREATE OR REPLACE conserva los de las que cambian.
revoke all on function campo.f_contacto(jsonb), campo.f_texto_sin_datos(text, text, integer, integer),
  public.geoportal_campo_analisis_observar(text, text, text, text, text, jsonb, text), public.geoportal_campo_aviso_crear_actividad(text, bigint, text, text),
  public.geoportal_campo_aviso_datos(text, bigint, text), public.geoportal_campo_aviso_datos_anular(text, bigint, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_analisis_observar(text, text, text, text, text, jsonb, text), public.geoportal_campo_aviso_crear_actividad(text, bigint, text, text),
  public.geoportal_campo_aviso_datos(text, bigint, text), public.geoportal_campo_aviso_datos_anular(text, bigint, text, text) to service_role;

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
  perform pg_temp.ok('01.03 campos activos: solo la dirección es obligatoria; hallazgo, barrio, habitado, tipo de predio y medidor opcionales',
    (select string_agg(c.codigo || ':' || c.obligatorio, ',' order by c.orden) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id
      where t.codigo = 'investigacion_ubicacion' and c.activo) = 'hallazgo:false,direccion_encontrada:true,barrio:false,habitado:false,tipo_predio:false,medidor:false');
  perform pg_temp.ok('01.04 los 4 campos de despeje y visita y «observacion» están desactivados, no borrados',
    (select count(*) = 5 and bool_and(not c.activo) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id
      where t.codigo = 'investigacion_ubicacion' and c.codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada', 'cita_acordada', 'observacion')));
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
  perform pg_temp.ok('02.02 y con los 6 campos activos (los 5 desactivados no viajan: una sola caja de texto)',
    jsonb_array_length(t -> 'campos') = 6 and not exists (select 1 from jsonb_array_elements(t -> 'campos') c where c ->> 'codigo' in ('despeje_caja', 'cita_acordada', 'observacion')), left(coalesce(t::text, ''), 300));

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
  r := pg_temp.inv(S2, D || '{"hallazgo": "ubicado", "barrio": "[PRUEBA ZTINV] Centro", "habitado": true, "tipo_predio": "lote_desocupado", "medidor": "ZT-12345"}',
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
  r := pg_temp.inv(S3, D || '{"observacion": "[PRUEBA ZTINV] reja verde"}');
  perform pg_temp.ok('04.09b el campo «observacion» desactivado se rechaza (la observación va en la descripción general)', pg_temp.err(r) <> 'OK', r::text);
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

-- ===================== PARTE 2: avisos del Análisis de contrato =====================
create function pg_temp.obs(p_quien text, p_contrato text, p_tipo text, p_texto text default null, p_dir text default null, p_contacto jsonb default null) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_analisis_observar(%L, %L, %L, %L, %L, %L::jsonb)', p_quien, p_contrato, p_tipo, p_texto, p_dir, p_contacto)) $f$;
create function pg_temp.lista(p_quien text, p_filtros jsonb) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_derivadas(%L, %L::jsonb)', p_quien, p_filtros)) $f$;
create function pg_temp.fila(r jsonb, p_id bigint) returns jsonb language sql as $f$
  select x from jsonb_array_elements(r -> 'filas') x where (x ->> 'id')::bigint = p_id $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta, ver_analisis_contrato) values
  ('ztinv.ana@emdupar.gov.co', 'ZTINV Analista', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false, true),
  ('ztinv.ana2@emdupar.gov.co', 'ZTINV Analista 2', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false, true),
  ('ztinv.supacta@emdupar.gov.co', 'ZTINV Supervisor de actas', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true, true, false),
  ('ztinv.adm@emdupar.gov.co', 'ZTINV Administrador', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false, false);
-- La bitácora del Análisis: los contratos que consultó cada analista (datos de prueba)
insert into campo.consultas_analisis (autor, contrato, existe, consultado_en) values
  ('ztinv.ana@emdupar.gov.co', '990001', true, clock_timestamp()), ('ztinv.ana@emdupar.gov.co', '990002', true, clock_timestamp()),
  ('ztinv.ana@emdupar.gov.co', '990003', true, clock_timestamp()), ('ztinv.ana@emdupar.gov.co', '990004', false, clock_timestamp()),
  ('ztinv.ana@emdupar.gov.co', '990005', true, clock_timestamp() - interval '13 hours'), ('ztinv.ana@emdupar.gov.co', '99999999', true, clock_timestamp()),
  ('ztinv.ana2@emdupar.gov.co', '990001', true, clock_timestamp());

do $p2$
declare r jsonb; jx jsonb; A text := 'ztinv.ana@emdupar.gov.co'; A2 text := 'ztinv.ana2@emdupar.gov.co'; SUP text := 'ztinv.sup@emdupar.gov.co'; SA text := 'ztinv.supacta@emdupar.gov.co';
  ADM text := 'ztinv.adm@emdupar.gov.co'; OP text := 'ztinv.op1@emdupar.gov.co'; t0 timestamptz;
  d_des bigint; d_dir bigint; d_act bigint; d_otra bigint; d_nueva bigint; n0 bigint; n1 bigint; v_inv jsonb;
  C jsonb := '{"nombre": "ZTINV Persona Prueba", "cedula": "1065123456", "telefono": "300 123 4567", "correo": "ZTINV.Persona@Ejemplo.com", "relacion": "arrendatario"}';
begin
  -- 10: estructura y permisos
  perform pg_temp.ok('10.01 las 3 tablas nuevas existen con RLS activa y sin políticas (campo y acta siguen sin políticas)',
    (select count(*) = 3 and bool_and(relrowsecurity) from pg_class where oid in ('campo.analisis_observaciones'::regclass, 'campo.analisis_observacion_datos'::regclass, 'campo.analisis_observacion_anulaciones'::regclass))
    and not exists (select 1 from pg_policies where schemaname in ('campo', 'acta')));
  perform pg_temp.ok('10.02 sin permisos para anon, authenticated ni service_role; SELECT (y nada más) para homelab_lectura',
    (select bool_and(not has_table_privilege(rl, t, 'select') and not has_table_privilege(rl, t, 'insert'))
       from unnest(array['anon', 'authenticated', 'service_role']) rl, unnest(array['campo.analisis_observaciones', 'campo.analisis_observacion_datos', 'campo.analisis_observacion_anulaciones']) t)
    and (select bool_and(has_table_privilege('homelab_lectura', t, 'select') and not has_table_privilege('homelab_lectura', t, 'insert') and not has_table_privilege('homelab_lectura', t, 'update'))
       from unnest(array['campo.analisis_observaciones', 'campo.analisis_observacion_datos', 'campo.analisis_observacion_anulaciones']) t));
  perform pg_temp.ok('10.03 la tabla de datos de contacto está marcada SENSIBLE en su comentario',
    obj_description('campo.analisis_observacion_datos'::regclass, 'pg_class') like 'SENSIBLE (Ley 1581)%');
  perform pg_temp.ok('10.04 campo.derivadas: origen_id nulo solo con observación (exactamente uno de los dos)', exists (select 1 from pg_constraint where conname = 'derivadas_origen_ck'));

  -- 11: quién puede marcar y sobre qué contrato
  r := pg_temp.obs(OP, '990001', 'desocupado');
  perform pg_temp.ok('11.01 un operario sin Análisis de contrato no marca (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.obs(SA, '990001', 'desocupado');
  perform pg_temp.ok('11.02 el supervisor de actas sin Análisis no marca (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.obs(A, '990009', 'desocupado');
  perform pg_temp.ok('11.03 un contrato que el analista no consultó se rechaza', pg_temp.err(r) = '55000' and pg_temp.msg(r) like 'Primero consulte el contrato%', r::text);
  r := pg_temp.obs(A, '990005', 'desocupado');
  perform pg_temp.ok('11.04 un contrato consultado hace 13 horas se rechaza (12 h)', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.obs(A, '990004', 'desocupado');
  perform pg_temp.ok('11.05 un contrato que no existe (la consulta dio «no encontrado») se rechaza', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.obs(A, '99999999', 'desocupado');
  perform pg_temp.ok('11.06 el contrato comodín se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'El contrato comodín no admite observaciones', r::text);
  r := pg_temp.obs(A2, '990002', 'desocupado');
  perform pg_temp.ok('11.07 otro analista no marca un contrato que consultó el primero', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.obs(A, '99 0001', 'desocupado');
  perform pg_temp.ok('11.08 un contrato con algo distinto de números se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.obs(A, '990001', 'vendido');
  perform pg_temp.ok('11.09 una observación fuera de la lista se rechaza', pg_temp.err(r) <> 'OK', r::text);

  -- 12: los textos y los datos van solo donde corresponden
  r := pg_temp.obs(A, '990001', 'otra');
  perform pg_temp.ok('12.01 «Otra» sin texto se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like 'Escriba la observación%', r::text);
  r := pg_temp.obs(A, '990001', 'otra', 'ab');
  perform pg_temp.ok('12.02 «Otra» con menos de 3 caracteres se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.obs(A, '990001', 'otra', repeat('x', 121));
  perform pg_temp.ok('12.03 «Otra» con más de 120 caracteres se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.obs(A, '990001', 'otra', 'llamar al 300 123 4567');
  perform pg_temp.ok('12.04 «Otra» con un teléfono se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like '%no puede llevar teléfonos ni cédulas%', r::text);
  r := pg_temp.obs(A, '990001', 'otra', 'cédula 1065123456 del dueño');
  perform pg_temp.ok('12.05 «Otra» con una cédula (6 o más números seguidos) se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) like '%no puede llevar teléfonos ni cédulas%', r::text);
  r := pg_temp.obs(A, '990001', 'desocupado', 'texto de más');
  perform pg_temp.ok('12.06 un texto en «Desocupado» se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'El texto corto solo va en «Otra»', r::text);
  r := pg_temp.obs(A, '990001', 'desocupado', null, 'CRA 9 # 12-30');
  perform pg_temp.ok('12.07 una dirección en «Desocupado» se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'La dirección correcta solo va en «Dirección errada»', r::text);
  r := pg_temp.obs(A, '990001', 'otra', '[PRUEBA ZTINV] reja', null, '{"nombre": "Ana"}');
  perform pg_temp.ok('12.08 datos de contacto en «Otra» se rechazan', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Los datos de contacto solo van en «Actualización de datos»', r::text);
  r := pg_temp.obs(A, '990001', 'direccion_errada', null, 'CRA 9 tel 3001234567');
  perform pg_temp.ok('12.09 una dirección correcta con un teléfono se rechaza', pg_temp.err(r) <> 'OK', r::text);

  -- 13: formato de los datos de contacto (Q3)
  perform pg_temp.ok('13.01 cédula: letras, 4 números u 11 números se rechazan', pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"cedula": "12a45"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"cedula": "1234"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"cedula": "12345678901"}')) <> 'OK');
  perform pg_temp.ok('13.02 teléfono: 6 u 8 números, o 10 que no empiezan por 3 ni 60, se rechazan', pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"telefono": "123456"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"telefono": "12345678"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"telefono": "2123456789"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"telefono": "6123456789"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"telefono": "300123456a"}')) <> 'OK');
  perform pg_temp.ok('13.03 correo sin @ o sin dominio se rechaza', pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"correo": "ana.ejemplo.com"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"correo": "ana@ejemplo"}')) <> 'OK');
  perform pg_temp.ok('13.04 relación fuera de la lista, nombre con números y una casilla desconocida se rechazan',
    pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"relacion": "vecino"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"nombre": "Ana 2"}')) <> 'OK'
    and pg_temp.err(pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, '{"direccion": "CRA 1"}')) <> 'OK');
  perform pg_temp.ok('13.05 ningún intento rechazado dejó filas', not exists (select 1 from campo.analisis_observaciones where autor = A));
  perform pg_temp.ok('13.06 los formatos válidos: fijo de 7, celular de 10 con 3, fijo de 10 con 60, cédula de 5 y de 10, nombre con tildes',
    campo.f_contacto('{"telefono": "5701234"}') ->> 'telefono' = '5701234' and campo.f_contacto('{"telefono": "(300) 123-4567"}') ->> 'telefono' = '3001234567'
    and campo.f_contacto('{"telefono": "6055701234"}') ->> 'telefono' = '6055701234' and campo.f_contacto('{"cedula": "12345"}') ->> 'cedula' = '12345'
    and campo.f_contacto('{"cedula": "1065123456"}') ->> 'cedula' = '1065123456' and campo.f_contacto('{"nombre": "  María  José Núñez "}') ->> 'nombre' = 'María José Núñez'
    and campo.f_contacto('{"correo": " Ana.P@Ejemplo.COM.co "}') ->> 'correo' = 'ana.p@ejemplo.com.co' and campo.f_contacto('{"nombre": "", "cedula": ""}') is null);

  -- 14: marcar las 4 observaciones
  r := pg_temp.obs(A, '990001', 'desocupado'); d_des := (r ->> 'derivada_id')::bigint;
  perform pg_temp.ok('14.01 «Desocupado» crea su aviso pendiente', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'false'::jsonb
    and exists (select 1 from campo.derivadas where id = d_des and actividad = 'aviso_desocupado' and origen_id is null and contrato = '990001') and campo.f_derivada_estado(d_des) = 'pendiente', r::text);
  r := pg_temp.obs(A, '990001', 'direccion_errada', null, '[PRUEBA ZTINV] CRA 9 # 12-30 Barrio Centro'); d_dir := (r ->> 'derivada_id')::bigint;
  perform pg_temp.ok('14.02 «Dirección errada» con la dirección correcta crea su aviso', pg_temp.err(r) = 'OK'
    and (select o.direccion_correcta = '[PRUEBA ZTINV] CRA 9 # 12-30 Barrio Centro' from campo.derivadas d join campo.analisis_observaciones o on o.id = d.observacion_id where d.id = d_dir), r::text);
  r := pg_temp.obs(A, '990001', 'actualizacion_datos', null, null, C); d_act := (r ->> 'derivada_id')::bigint;
  perform pg_temp.ok('14.03 «Actualización de datos» con los 5 datos crea su aviso y guarda los datos aparte, normalizados', pg_temp.err(r) = 'OK' and r -> 'trae_datos' = 'true'::jsonb
    and (select x.datos = '{"nombre": "ZTINV Persona Prueba", "cedula": "1065123456", "telefono": "3001234567", "correo": "ztinv.persona@ejemplo.com", "relacion": "arrendatario"}'::jsonb
           from campo.derivadas d join campo.analisis_observacion_datos x on x.observacion_id = d.observacion_id where d.id = d_act), r::text);
  perform pg_temp.ok('14.04 la respuesta al analista NO devuelve los datos de contacto', r::text !~* 'ztinv persona|1065123456|3001234567|ztinv\.persona' and not (r ? 'datos'), r::text);
  r := pg_temp.obs(A, '990001', 'otra', '[PRUEBA ZTINV] tiene perro bravo'); d_otra := (r ->> 'derivada_id')::bigint;
  perform pg_temp.ok('14.05 «Otra» con texto corto crea su aviso', pg_temp.err(r) = 'OK' and d_otra is not null, r::text);
  select count(*) into n0 from campo.analisis_observaciones where autor = A;
  r := pg_temp.obs(A, '990001', 'desocupado');
  perform pg_temp.ok('14.06 repetir «Desocupado» con el aviso pendiente devuelve el mismo y no guarda nada', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'true'::jsonb
    and (r ->> 'derivada_id')::bigint = d_des and (select count(*) from campo.analisis_observaciones where autor = A) = n0, r::text);
  r := pg_temp.obs(A, '990002', 'actualizacion_datos');
  perform pg_temp.ok('14.07 «Actualización de datos» sin ninguna casilla guarda solo el aviso (sin fila de datos)', pg_temp.err(r) = 'OK' and r -> 'trae_datos' = 'false'::jsonb
    and not exists (select 1 from campo.analisis_observacion_datos x join campo.derivadas d on d.observacion_id = x.observacion_id where d.id = (r ->> 'derivada_id')::bigint), r::text);
  perform pg_temp.ok('14.08 la auditoría de las marcas no guarda el contrato, los textos ni los datos de contacto',
    (select count(*) = 5 and bool_and(detalle::text !~* '990001|ztinv persona|1065123456|3001234567|perro|cra 9') from public.geoportal_auditoria where accion = 'campo_analisis_observar' and email = A));
  t0 := clock_timestamp(); r := pg_temp.obs(A, '990003', 'desocupado');
  perform pg_temp.ok('14.09 marcar tarda menos de 1 s', pg_temp.err(r) = 'OK' and clock_timestamp() - t0 < interval '1 s', (clock_timestamp() - t0)::text);

  -- 15: «Actividades derivadas» con el filtro de origen
  r := pg_temp.lista(SUP, '{"origen": "analisis", "contrato": "990001"}');
  perform pg_temp.ok('15.01 el supervisor de campo ve los 4 avisos del contrato con el filtro Origen = Análisis de contrato',
    pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'filas') = 4 and (select bool_and(x -> 'origen' ->> 'clase' = 'analisis' and x -> 'origen' ->> 'tipo_nombre' = 'Análisis de contrato') from jsonb_array_elements(r -> 'filas') x), left(r::text, 400));
  jx := pg_temp.fila(r, d_act);
  perform pg_temp.ok('15.02 el aviso de actualización dice «trae datos», pero la lista NO trae los datos de contacto',
    jx -> 'origen' -> 'trae_datos' = 'true'::jsonb and r::text !~* 'ztinv persona|1065123456|3001234567|ztinv\.persona|arrendatario', left(coalesce(jx::text, r::text), 400));
  perform pg_temp.ok('15.03 el aviso trae la dirección correcta y el texto de «Otra», el operario y la fecha',
    pg_temp.fila(r, d_dir) -> 'origen' ->> 'direccion_correcta' = '[PRUEBA ZTINV] CRA 9 # 12-30 Barrio Centro' and pg_temp.fila(r, d_otra) -> 'origen' ->> 'texto' = '[PRUEBA ZTINV] tiene perro bravo'
    and pg_temp.fila(r, d_des) -> 'origen' ->> 'operario' = A and pg_temp.fila(r, d_des) -> 'destinos' = '[]'::jsonb);
  r := pg_temp.lista(SUP, '{"origen": "registro", "contrato": "990001"}');
  perform pg_temp.ok('15.04 con Origen = Revisiones no aparecen los avisos', pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'filas') = 0, left(r::text, 300));
  r := pg_temp.lista(SUP, '{"origen": "mapa"}');
  perform pg_temp.ok('15.05 un origen fuera de la lista se rechaza', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'El origen no es válido', r::text);
  r := pg_temp.lista(SA, '{"origen": "analisis", "contrato": "990001"}');
  perform pg_temp.ok('15.06 el supervisor de actas ve la lista (como hoy), también sin los datos', pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'filas') = 4 and r::text !~* '1065123456|3001234567', left(r::text, 200));
  r := pg_temp.lista(A, '{"origen": "analisis"}');
  perform pg_temp.ok('15.07 el analista no ve «Actividades derivadas» (42501)', pg_temp.err(r) = '42501', r::text);
  t0 := clock_timestamp(); r := pg_temp.lista(SUP, '{"origen": "analisis", "limite": 200}');
  perform pg_temp.ok('15.08 la lista tarda menos de 2 s', pg_temp.err(r) = 'OK' and clock_timestamp() - t0 < interval '2 s', (clock_timestamp() - t0)::text);

  -- 16: ver los datos de contacto (solo supervisor de campo y administrador, auditado)
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', A, d_act));
  perform pg_temp.ok('16.01 el analista que los guardó NO los vuelve a leer (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', SA, d_act));
  perform pg_temp.ok('16.02 el supervisor de actas no los lee (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', OP, d_act));
  perform pg_temp.ok('16.03 un operario no los lee (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', SUP, d_act));
  perform pg_temp.ok('16.04 el supervisor de campo los lee al abrir el aviso', pg_temp.err(r) = 'OK' and r -> 'anulados' = 'false'::jsonb and r -> 'datos' ->> 'cedula' = '1065123456' and r -> 'datos' ->> 'telefono' = '3001234567', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', ADM, d_act));
  perform pg_temp.ok('16.05 el administrador también', pg_temp.err(r) = 'OK' and r -> 'datos' ->> 'nombre' = 'ZTINV Persona Prueba', r::text);
  perform pg_temp.ok('16.06 cada lectura queda auditada, con los nombres de las casillas y sin los valores',
    (select count(*) = 2 and bool_and(detalle -> 'campos' = '["cedula", "correo", "nombre", "relacion", "telefono"]'::jsonb and detalle::text !~* '1065123456|3001234567|ztinv persona')
       from public.geoportal_auditoria where accion = 'campo_ver_datos_contacto' and referencia = d_act::text));
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', SUP, d_des));
  perform pg_temp.ok('16.07 un aviso sin datos de contacto lo dice', pg_temp.err(r) = 'P0002', r::text);

  -- 17: anular los datos de contacto (Q2)
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos_anular(%L, %s, %L)', A, d_act, 'el nombre estaba mal escrito'));
  perform pg_temp.ok('17.01 el analista no anula (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos_anular(%L, %s, %L)', SUP, d_act, 'mal'));
  perform pg_temp.ok('17.02 sin un motivo de 10 caracteres o más se rechaza', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos_anular(%L, %s, %L)', SUP, d_act, '[PRUEBA ZTINV] la cédula no corresponde'));
  perform pg_temp.ok('17.03 el supervisor anula con motivo', pg_temp.err(r) = 'OK' and r -> 'anulados' = 'true'::jsonb, r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos(%L, %s)', SUP, d_act));
  perform pg_temp.ok('17.04 anulados: se ve «Anulados» y el motivo, sin los valores', pg_temp.err(r) = 'OK' and r -> 'anulados' = 'true'::jsonb
    and r ->> 'motivo' = '[PRUEBA ZTINV] la cédula no corresponde' and not (r ? 'datos') and r::text !~* '1065123456|3001234567', r::text);
  perform pg_temp.ok('17.05 los datos siguen guardados (nada se borra)', exists (select 1 from campo.analisis_observacion_datos x join campo.derivadas d on d.observacion_id = x.observacion_id where d.id = d_act and x.datos ->> 'cedula' = '1065123456'));
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_datos_anular(%L, %s, %L)', SUP, d_act, '[PRUEBA ZTINV] otra vez la anulo'));
  perform pg_temp.ok('17.06 anular dos veces se rechaza', pg_temp.err(r) = '55000', r::text);
  perform pg_temp.ok('17.07 la lista marca «datos anulados»', (pg_temp.fila(pg_temp.lista(SUP, '{"origen": "analisis", "contrato": "990001"}'), d_act) -> 'origen' -> 'datos_anulados') = 'true'::jsonb);

  -- 18: «Crear actividad» desde el aviso (Q1)
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', A, d_dir, 'tipo:investigacion_ubicacion'));
  perform pg_temp.ok('18.01 el analista no crea actividades (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SA, d_dir, 'tipo:investigacion_ubicacion'));
  perform pg_temp.ok('18.02 el supervisor de actas tampoco (42501)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_dir, 'acta'));
  perform pg_temp.ok('18.03 el acta no se elige', pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Elija un formulario activo que pida el contrato', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_dir, 'tipo:cambio_medidor'));
  perform pg_temp.ok('18.04 un formulario desactivado (cambio de medidor) no se elige', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_dir, 'tipo:fraude'));
  perform pg_temp.ok('18.05 un reporte general (contrato opcional) no se elige', pg_temp.err(r) <> 'OK', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_dir, 'tipo:investigacion_ubicacion'));
  d_nueva := (r -> 'actividad' ->> 'id')::bigint;
  perform pg_temp.ok('18.06 el supervisor crea la Investigación de ubicación desde «Dirección errada»', pg_temp.err(r) = 'OK'
    and r -> 'actividad' ->> 'estado' = 'pendiente' and r -> 'actividad' -> 'destinos' = '["tipo:investigacion_ubicacion"]'::jsonb
    and r -> 'actividad' ->> 'destino_nombre' = 'Investigación de ubicación del predio' and r -> 'actividad' -> 'origen' ->> 'direccion_correcta' = '[PRUEBA ZTINV] CRA 9 # 12-30 Barrio Centro', left(r::text, 500));
  perform pg_temp.ok('18.07 el aviso se cerró solo: atendida fuera, con el motivo automático', r -> 'aviso' ->> 'estado' = 'atendida_fuera'
    and r -> 'aviso' -> 'cierre' ->> 'motivo' = 'Se creó la actividad: Investigación de ubicación del predio' and (r -> 'aviso' -> 'origen' ->> 'actividad_creada_id')::bigint = d_nueva, left(r::text, 500));
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_dir, 'tipo:suspension'));
  perform pg_temp.ok('18.08 una segunda actividad desde el mismo aviso se rechaza (ya está cerrado)', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, d_nueva, 'tipo:suspension'));
  perform pg_temp.ok('18.09 desde la actividad creada no se crea otra (no es un aviso)', pg_temp.err(r) <> 'OK', r::text);
  perform pg_temp.ok('18.10 quedó auditado', exists (select 1 from public.geoportal_auditoria where accion = 'campo_aviso_crear_actividad' and referencia = d_dir::text and email = SUP));

  -- 19: el operario la atiende con «¿Viene de…?»
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_abiertas(%L, %L, %L)', OP, '990001', 'tipo:investigacion_ubicacion'));
  perform pg_temp.ok('19.01 al operario que abre la Investigación con ese contrato le aparece la actividad (y no los avisos)',
    pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'derivadas') = 1 and (r -> 'derivadas' -> 0 ->> 'id')::bigint = d_nueva, left(r::text, 300));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_abiertas(%L, %L, %L)', OP, '990001', 'tipo:suspension'));
  perform pg_temp.ok('19.02 con otro formulario no aparece', pg_temp.err(r) = 'OK' and jsonb_array_length(r -> 'derivadas') = 0, r::text);
  v_inv := pg_temp.inv(OP, '{"direccion_encontrada": "[PRUEBA ZTINV] CRA 9 # 12-30"}', '{}', '990001');
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%L, %s, ''campo'', %L::uuid)', OP, d_des, v_inv ->> 'id'));
  perform pg_temp.ok('19.03 un aviso (sin destino) no se atiende con un registro', pg_temp.err(v_inv) = 'OK' and pg_temp.err(r) <> 'OK' and pg_temp.msg(r) = 'Ese formulario no atiende esa actividad derivada', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%L, %s, ''campo'', %L::uuid)', OP, d_nueva, v_inv ->> 'id'));
  perform pg_temp.ok('19.04 la Investigación registrada atiende la actividad: queda «atendida» con su consecutivo', pg_temp.err(r) = 'OK' and r ->> 'estado' = 'atendida'
    and r -> 'cierre' ->> 'consecutivo' = v_inv ->> 'consecutivo', left(r::text, 400));
  v_inv := pg_temp.inv(OP, '{"direccion_encontrada": "[PRUEBA ZTINV] otra"}', '{}', '990002');
  r := pg_temp.rpc(format('public.geoportal_campo_aviso_crear_actividad(%L, %s, %L)', SUP, (select id from campo.derivadas where contrato = '990002' and actividad = 'aviso_actualizacion_datos'), 'tipo:investigacion_ubicacion'));
  jx := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%L, %s, ''campo'', %L::uuid)', OP, (r -> 'actividad' ->> 'id')::bigint, (pg_temp.inv(OP, '{"direccion_encontrada": "[PRUEBA ZTINV] tercera"}', '{}', '990001')) ->> 'id'));
  perform pg_temp.ok('19.05 un registro de otro contrato no atiende la actividad', pg_temp.err(r) = 'OK' and pg_temp.err(jx) <> 'OK' and pg_temp.msg(jx) = 'El registro es de otro contrato', jx::text);

  -- 20: cerrar avisos como hoy
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_cerrar(%L, %s, ''atendida_fuera'', %L)', SUP, d_des, '[PRUEBA ZTINV] se confirmó por teléfono'));
  perform pg_temp.ok('20.01 «Desocupado» se cierra como atendida fuera con motivo', pg_temp.err(r) = 'OK' and r ->> 'estado' = 'atendida_fuera', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_cerrar(%L, %s, ''anulada'', %L)', SUP, d_otra, '[PRUEBA ZTINV] marcada por error'));
  perform pg_temp.ok('20.02 «Otra» se anula con motivo', pg_temp.err(r) = 'OK' and r ->> 'estado' = 'anulada', r::text);
  r := pg_temp.obs(A, '990001', 'desocupado');
  perform pg_temp.ok('20.03 con el aviso cerrado, «Desocupado» se puede volver a marcar (aviso nuevo)', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'false'::jsonb and (r ->> 'derivada_id')::bigint <> d_des, r::text);

  -- 21: las derivadas de las revisiones no cambian
  begin
    insert into campo.derivadas (origen_id, contrato, actividad) values ((v_inv ->> 'id')::uuid, '990002', 'otra') returning id into n1;
  exception when others then
    perform pg_temp.ok('21.00 se puede crear una derivada de prueba desde un registro', false, sqlerrm || ' · ' || coalesce(v_inv::text, ''));
  end;
  jx := campo.f_derivada_json(n1);
  perform pg_temp.ok('21.01 una derivada de un registro conserva sus claves de siempre (más «clase»: registro)',
    jx -> 'origen' ->> 'clase' = 'registro' and jx -> 'origen' ?& array['registro_id', 'tipo', 'tipo_nombre', 'consecutivo', 'fecha', 'operario'] and jx -> 'destinos' = '[]'::jsonb
    and jx ?& array['id', 'actividad', 'actividad_nombre', 'contrato', 'estado', 'creada_en', 'destinos', 'destino_omision', 'origen', 'cierre'], jx::text);
  perform pg_temp.ok('21.02 y aparece con el filtro Origen = Revisiones', pg_temp.fila(pg_temp.lista(SUP, '{"origen": "registro", "contrato": "990002"}'), n1) is not null);
  r := pg_temp.rpc(format('public.geoportal_campo_derivada_atender(%L, %s, ''campo'', %L::uuid)', OP, n1, v_inv ->> 'id'));
  perform pg_temp.ok('21.03 la regla de siempre: un registro no atiende sus propias derivadas', pg_temp.err(r) <> 'OK', r::text);
  begin
    insert into campo.derivadas (contrato, actividad) values ('990002', 'otra');
    perform pg_temp.ok('21.04 una derivada sin origen ni observación se rechaza', false);
  exception when check_violation then perform pg_temp.ok('21.04 una derivada sin origen ni observación se rechaza', true);
  end;
  begin
    insert into campo.derivadas (origen_id, observacion_id, contrato, actividad) values ((v_inv ->> 'id')::uuid, (select observacion_id from campo.derivadas where id = d_des), '990002', 'aviso_otra');
    perform pg_temp.ok('21.05 una derivada con origen Y observación se rechaza', false);
  exception when check_violation then perform pg_temp.ok('21.05 una derivada con origen Y observación se rechaza', true);
  end;
  begin
    insert into campo.derivadas (origen_id, contrato, actividad, destino) values ((v_inv ->> 'id')::uuid, '990002', 'accesorios', 'tipo:suspension');
    perform pg_temp.ok('21.06 un destino propio en una derivada de revisión se rechaza', false);
  exception when check_violation then perform pg_temp.ok('21.06 un destino propio en una derivada de revisión se rechaza', true);
  end;
  perform pg_temp.ok('21.07 los 5 códigos nuevos no se cuelan en «¿Da lugar a otras actividades?» de las revisiones',
    not exists (select 1 from campo.tipo_campos c, jsonb_array_elements(coalesce(c.opciones, '[]')) o where o ->> 'codigo' in ('aviso_desocupado', 'aviso_direccion_errada', 'aviso_actualizacion_datos', 'aviso_otra', 'actividad_supervisor')));

  -- 22: solo inserción y nada se borra
  begin
    update campo.analisis_observaciones set texto = 'x' where autor = A;
    perform pg_temp.ok('22.01 las observaciones no se modifican', false);
  exception when others then perform pg_temp.ok('22.01 las observaciones no se modifican', true);
  end;
  begin
    delete from campo.analisis_observacion_datos where true;
    perform pg_temp.ok('22.02 los datos de contacto no se borran', false);
  exception when others then perform pg_temp.ok('22.02 los datos de contacto no se borran', true);
  end;
  perform pg_temp.ok('22.03 ninguna función nueva lleva DELETE ni UPDATE', (select bool_and(pg_get_functiondef(p.oid) !~* '\m(delete|update)\M\s') from pg_proc p
     where p.oid in ('campo.f_contacto(jsonb)'::regprocedure, 'campo.f_texto_sin_datos(text,text,integer,integer)'::regprocedure,
                     'public.geoportal_campo_analisis_observar(text,text,text,text,text,jsonb,text)'::regprocedure, 'public.geoportal_campo_aviso_crear_actividad(text,bigint,text,text)'::regprocedure,
                     'public.geoportal_campo_aviso_datos(text,bigint,text)'::regprocedure, 'public.geoportal_campo_aviso_datos_anular(text,bigint,text,text)'::regprocedure)));
  perform pg_temp.ok('22.04 solo aviso_datos devuelve los datos de contacto: ninguna otra función de campo, exportación o mapa lee esa tabla',
    (select array_agg(p.proname::text order by p.proname) from pg_proc p where pg_get_functiondef(p.oid) ~ 'analisis_observacion_datos' and p.prokind = 'f')
     = array['f_derivada_json', 'geoportal_campo_analisis_observar', 'geoportal_campo_aviso_datos', 'geoportal_campo_aviso_datos_anular']::text[]);
  perform pg_temp.ok('22.05 ninguna función de campo con DELETE o UPDATE sin WHERE (con la parte 2)', (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0);
end $p2$;

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztinv_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;

rollback;
