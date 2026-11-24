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

commit;
