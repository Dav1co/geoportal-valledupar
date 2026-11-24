-- [Code B] INVESTIGACIÓN Y ANÁLISIS (23-nov) · MIGRACIÓN (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
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

commit;
