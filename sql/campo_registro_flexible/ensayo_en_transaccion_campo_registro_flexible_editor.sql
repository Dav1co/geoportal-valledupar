-- [Code A] REGISTRO FLEXIBLE (25-nov) · ENSAYO (termina en ERROR esperado; no deja nada) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 70 — ENSAYO: registros de antes → MIGRACIÓN → pruebas → REVERSA → pruebas; termina en el ERROR esperado (todo se deshace)
-- Datos propios con prefijo ZTRF (correos ztrf.*@emdupar.gov.co; textos «[PRUEBA ZTRF]»; contratos 991xxx en las derivadas). Cada prueba cuenta SOLO sus filas.
-- Las RPC se llaman como service_role con los topes de producción (30 s, lock 8 s), como lo hace la Edge.
-- 5 perfiles (David, 24-nov): administrador, supervisor de Comercial, operador de campo, dual (supervisor de Comercial y operador de Técnica con «Reportar anomalía»)
-- y sin permisos; además, dos operadores de planta (PTAP: «entrada»), uno con «Reportar anomalía» de Técnica y otro sin él.
-- Sin tablas temporales que se borren al confirmar: la tabla de resultados se deshace con el ERROR esperado del final.
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztrf_res (n serial, nombre text, ok boolean, detalle text);
create temp table ztrf_val (k text primary key, v text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztrf_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
create function pg_temp.guardar(p_k text, p_v text) returns void language sql as $f$ insert into ztrf_val values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.val(p_k text) returns text language sql as $f$ select v from ztrf_val where k = p_k $f$;
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
-- Registra un reporte como lo hace la Edge: reserva (preparar_subida, o la de Técnica), «sube» cada foto al doble de Storage y crea.
-- p_fotos: arreglo de {etiqueta?, origen?} (una entrada por foto; «origen» solo si viene). p_registro: el bloque nuevo (nulo = la Edge de antes: llamada sin p_registro).
create function pg_temp.reg(p_quien text, p_tipo text, p_fotos jsonb default '[{}]', p_registro jsonb default null, p_lat numeric default 10.46, p_lon numeric default -73.25,
                            p_prec numeric default 5, p_contrato text default null, p_resultado text default null, p_causal text default null, p_tec boolean default false,
                            p_id uuid default null) returns jsonb language plpgsql as $f$
declare p jsonb; v_id uuid; v_f jsonb := '[]'::jsonb; v_ruta text; v_n integer := jsonb_array_length(coalesce(p_fotos, '[]'::jsonb)); v_e jsonb; q text;
begin
  if p_id is null then
    p := case when p_tec then pg_temp.rpc(format('public.geoportal_campo_tec_preparar_subida(%L, %s, null, %L)', p_quien, v_n, p_tipo))
              else pg_temp.rpc(format('public.geoportal_campo_preparar_subida(%L, %s, ''campo'', null, %L)', p_quien, v_n, p_tipo)) end;
    if p ? 'error' then return p; end if;
    v_id := (p ->> 'reporte_id')::uuid;
    for i in 1 .. v_n loop
      v_ruta := p -> 'fotos' -> (i - 1) ->> 'ruta';
      insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', v_ruta, jsonb_build_object('size', 300000, 'mimetype', 'image/jpeg'));
      v_e := jsonb_build_object('orden', i, 'ruta', v_ruta) || coalesce(p_fotos -> (i - 1), '{}'::jsonb);
      v_f := v_f || v_e;
    end loop;
    perform pg_temp.guardar('fotos:' || v_id, v_f::text);
    -- los formatos con firma del operario obligatoria (los de PDF): se firma antes de registrar, como lo hace la pantalla
    if not p_tec and exists (select 1 from campo.formularios_documento d where d.formulario = 'tipo:' || p_tipo and d.firma_operario = 'obligatoria') then
      p := pg_temp.rpc(format('public.geoportal_campo_firma_guardar(%L, ''campo'', %L::uuid, ''operario'', ''firmo'', null, %L)', p_quien, v_id,
                              encode('\xffd8ffe0'::bytea || convert_to(repeat('z', 400), 'UTF8'), 'base64')));
      if p ? 'error' then return p || jsonb_build_object('_id', v_id, '_paso', 'firma'); end if;
    end if;
  else
    v_id := p_id; v_f := coalesce(pg_temp.val('fotos:' || v_id), '[]')::jsonb;
  end if;
  if p_tec then
    q := format('public.geoportal_campo_tec_crear_reporte(%L, %L::uuid, %L, null, %L, %L, %s, %s, %s, false, %L::jsonb, null, null, %L, %L, null%s)',
                p_quien, v_id, p_tipo, '[PRUEBA ZTRF] ' || p_tipo, p_contrato, p_lat, p_lon, coalesce(p_prec::text, 'null'), v_f, p_resultado, p_causal,
                case when p_registro is null then '' else format(', %L::jsonb', p_registro) end);
  else
    q := format('public.geoportal_campo_crear_reporte(%L, %L::uuid, %L, null, %L, %L, %s, %s, %s, false, ''campo'', %L::jsonb, null, null, %L, %L, null, null%s)',
                p_quien, v_id, p_tipo, '[PRUEBA ZTRF] ' || p_tipo, p_contrato, p_lat, p_lon, coalesce(p_prec::text, 'null'), v_f, p_resultado, p_causal,
                case when p_registro is null then '' else format(', %L::jsonb', p_registro) end);
  end if;
  return pg_temp.rpc(q) || jsonb_build_object('_id', v_id);
end $f$;
create function pg_temp.pdf(p_quien text, p_id uuid) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_pdf_datos(%L, ''campo'', %L::uuid, null)', p_quien, p_id)) $f$;
create function pg_temp.lista(p_quien text, p_id uuid) returns jsonb language sql as $f$
  select e from jsonb_array_elements(pg_temp.rpc(format('public.geoportal_campo_listar_reportes(%L, %L::jsonb, null)', p_quien, '{"limite": 5000}')) -> 'reportes') e where (e ->> 'id')::uuid = p_id $f$;
create function pg_temp.detalle(p_quien text, p_id uuid) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_obtener_reporte(%L, %L::uuid, null)', p_quien, p_id)) $f$;
create function pg_temp.cab(p jsonb, p_k text) returns text language sql as $f$ select e ->> 1 from jsonb_array_elements(p -> 'cabecera') e where e ->> 0 = p_k $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico) values
  ('ztrf.admin@emdupar.gov.co', 'ZTRF Administrador', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false),
  ('ztrf.sup@emdupar.gov.co', 'ZTRF Supervisor de Comercial', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false),
  ('ztrf.op@emdupar.gov.co', 'ZTRF Operador de campo', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false),
  ('ztrf.op2@emdupar.gov.co', 'ZTRF Operador de campo 2', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false),
  ('ztrf.dual@emdupar.gov.co', 'ZTRF Dual (supervisor de Comercial y operador de Técnica)', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, true),
  ('ztrf.sin@emdupar.gov.co', 'ZTRF Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false),
  ('ztrf.planta@emdupar.gov.co', 'ZTRF Operador de planta con anomalía', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true),
  ('ztrf.planta2@emdupar.gov.co', 'ZTRF Operador de planta sin anomalía', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, true);
insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values
  ('ztrf.dual@emdupar.gov.co', 'asignar_formulario', 'anomalia_compartida', 'ztrf.admin@emdupar.gov.co'),
  ('ztrf.planta@emdupar.gov.co', 'asignar_formulario', 'entrada', 'ztrf.admin@emdupar.gov.co'),
  ('ztrf.planta@emdupar.gov.co', 'asignar_formulario', 'anomalia_compartida', 'ztrf.admin@emdupar.gov.co'),
  ('ztrf.planta2@emdupar.gov.co', 'asignar_formulario', 'entrada', 'ztrf.admin@emdupar.gov.co');

-- ===================== 00. ANTES de la migración: registros como los de hoy y su sello =====================
do $p0$
declare r jsonb; ADM text := 'ztrf.admin@emdupar.gov.co'; OP text := 'ztrf.op@emdupar.gov.co';
begin
  -- revisión previa inefectiva (lleva PDF) y un reporte general, con las funciones publicadas
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', null, 10.46, -73.25, 5, '123456', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('00.01 antes: una revisión previa inefectiva se registra con la función publicada', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('viejo', r ->> '_id');
  r := pg_temp.reg(OP, 'otro');
  perform pg_temp.ok('00.02 antes: un reporte general se registra con la función publicada', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('viejo_general', r ->> '_id');
  r := pg_temp.pdf(ADM, pg_temp.val('viejo')::uuid);
  perform pg_temp.ok('00.03 antes: datos del PDF con su sello', pg_temp.err(r) = 'OK' and length(r ->> 'sello') = 64, left(r::text, 300));
  perform pg_temp.guardar('sello_viejo', r ->> 'sello'); perform pg_temp.guardar('cab_viejo', (r -> 'cabecera')::text); perform pg_temp.guardar('fotos_viejo', (r -> 'fotos')::text);
  perform pg_temp.guardar('lista_vieja', (pg_temp.lista(ADM, pg_temp.val('viejo')::uuid))::text);
end $p0$;

-- ===================== MIGRACIÓN (guardia incluida), dentro de esta misma transacción =====================
-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 05 — GUARDIA: se detiene sin cambiar nada si la base no es la publicada
-- Comprueba: huella de campo cce593806f59d3d27c34d7f2070cc5c1 (todas las funciones de campo y las public.geoportal_campo_*, que incluyen la entrada de Técnica
-- geoportal_campo_tec_*), huella del acta 111506c690249ad3b56ebf572566434c, huella de Técnica 838b80984e51cc7873a666f85d657195 (esquema tecnica y public.geoportal_tec_*: este paquete
-- no la cambia; se comprueba antes y después porque cambia la firma de geoportal_campo_tec_crear_reporte), el md5 de cada función que se reemplaza o de la
-- que depende el cambio, la estructura exacta de las tablas vivas que el paquete lee o toca (columnas, tipos, NOT NULL, valores por omisión, identidad,
-- restricciones, índices, disparadores, RLS y permisos), sin políticas RLS en campo ni acta, y el rol homelab_lectura con BYPASSRLS.
-- =====================================================================
do $guardia$
declare v text; r record;
begin
  if to_regprocedure('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone,jsonb)') is not null then
    raise exception 'Este paquete ya parece aplicado (existe geoportal_campo_crear_reporte con p_registro): use la reversa antes de repetir';
  end if;
  if to_regprocedure('public.geoportal_campo_derivadas_descarga_iniciar(text,jsonb,text,boolean,text)') is not null then
    raise exception 'Este paquete ya parece aplicado (existe geoportal_campo_derivadas_descarga_iniciar): use la reversa antes de repetir';
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if coalesce(v, '(ninguna)') is distinct from 'cce593806f59d3d27c34d7f2070cc5c1' then
    raise exception 'Las funciones de campo no son las publicadas (huella cce593806f59d3d27c34d7f2070cc5c1; hay %): deténgase y avise', v;
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%');
  if coalesce(v, '(ninguna)') is distinct from '111506c690249ad3b56ebf572566434c' then
    raise exception 'Las funciones del acta no son las publicadas (huella 111506c690249ad3b56ebf572566434c; hay %): deténgase y avise', v;
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'));
  if coalesce(v, '(ninguna)') is distinct from '838b80984e51cc7873a666f85d657195' then
    raise exception 'Las funciones de Técnica no son las publicadas (huella 838b80984e51cc7873a666f85d657195; hay %): deténgase y avise', v;
  end if;
  for r in select * from (values ('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)', '51ecb98ca2e7f940c66b9a1f3e828222'), ('public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone)', '7281c4bbf3db56fdfc1c11bb42f645ff'), ('public.geoportal_campo_listar_reportes(text,jsonb,text)', '4daf2374e2d98fe23622f2bc7fdead2c'), ('public.geoportal_campo_obtener_reporte(text,uuid,text)', '588b24e4a98a988bfbdaa6120937dd88'), ('public.geoportal_campo_descarga_pagina(text,bigint,bigint,integer)', '0caba967a55836621e5b978c682e3cce'), ('public.geoportal_campo_pdf_datos(text,text,uuid,text)', '11cfa0ee01e7edef76e3c4a6587d5eb9'), ('public.geoportal_campo_derivadas(text,jsonb,text)', '9addead3b57c75986cc5eed52d6cb14a'), ('campo.f_derivada_json(bigint)', '9f59c5cc28a88a5a1f2962ff9d5cb3d2'), ('campo.f_derivada_estado(bigint)', 'f612ec315fb7c6e90c373884a3104658'), ('campo.f_autorizar_supervision(text)', '5ac3368fa5f3a6347328285501894aec'), ('campo.f_autorizar_registradas(text)', '63cf95ebacedebc2622171f7df9b2df2'), ('campo.f_autorizar_reporte(text)', '097a21e90766512921f185d213f3c779'), ('campo.f_autorizar_documento(text,text,uuid)', 'a54711241d29ff33a8930a948d011b3f'), ('campo.f_perfil(text)', '0d3da36f35a5adf8936789cef91405bb'), ('campo.f_tecnica_entrar(text,text)', '0b8a0b83e29192980e9d3f902e05b305'), ('campo.f_tecnica_claves(text)', '98c2f200b97968a30d9e2ba521c92d6b'), ('campo.f_tipo_general(text)', '4ede0bf1f2a69982fb033cea893b84e2'), ('campo.f_filtrar(jsonb)', 'eb39a3b7ea2600a60099907876552a6f'), ('campo.f_grupos_cercanos(numeric,uuid[])', '553f9186102b957b9c77d274a4480b0d'), ('campo.f_validar_datos(bigint,jsonb,boolean)', 'f3d09600df18aa558e5bc046d6934f70'), ('campo.f_solo_agregar()', '2a27744a1110ddd5bf835b2b65a3a671'), ('campo.f_error(text,text)', '6439032aae6fe0575c94fb32f85f109f'), ('campo.f_auditar(text,text,text,jsonb,text)', '67bbec1b5d638525595b52666ecb3bcd'), ('campo.f_param(text)', '23b13a57b5b26471cdf2f58824fe60c7'), ('campo.f_ahora_bogota()', 'fb7b7400b35f9403456997293e09f42b'), ('public.geoportal_campo_obtener_formulario(text,boolean)', 'da253b2da0128848595788795f61479f'), ('public.geoportal_campo_tec_formulario(text)', 'edaee27220655f13ce9ecc193e42c4b1'), ('public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'a00d66705d7a0c88a38ab5d882153669'), ('public.geoportal_campo_tec_preparar_subida(text,integer,text,text)', '52047247a4d6a68aba4140d3f293dd3d'), ('public.geoportal_campo_descarga_iniciar(text,jsonb,text,boolean,text)', 'c1ddc900ffc1c9425394b636b5530c66'), ('public.geoportal_campo_descarga_cerrar(text,bigint,integer,text,text)', '3c4ef0ea54112bb54304156acb3c6f24'), ('public.geoportal_puede(text,text)', '32f174a55b95788d3f8187b507303c2f'), ('public.geoportal_mis_permisos(text)', '83166fe17be58da67bbdedaae429bedb'), ('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)', '01fda69a9d912067b8b4dc153ac7957e'), ('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)', 'e5a90103b4a83440fd826f03266b7245')) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la publicada: deténgase y avise', r.f;
    end if;
  end loop;
  -- Estructura exacta de las tablas vivas (la misma expresión que calcula generar.py en el doble, que es copia exacta de producción)
  -- (m2: el estado que deja la reversa de este paquete, que conserva la columna nueva de campo.reporte_fotos; nada se borra)
  for r in select * from (values ('campo.reportes', '3528e465f4ee67349f16832ca3d05827', null::text), ('campo.reporte_fotos', 'c341433f90314544c5b06703f6b3ee3e', '72faae4ca1b8a54ff014301997b22ffc'), ('campo.reporte_datos_sensibles', '5d03ed6c45eb0047c143338e6ee060d7', null::text), ('campo.derivadas', '28a6a571a358b128740ef775974b1225', null::text), ('campo.derivada_eventos', 'd01fd6ead43730a491b927f36c3136a9', null::text), ('campo.tipos_reporte', '3b9274b039c86b8079fee77b484ad5e1', null::text), ('campo.parametros', 'fd9322f0721b931e71fa96b3010ed6f8', null::text), ('public.geoportal_auditoria', '4012748c34060e929d0a2418a7df9472', null::text)) x(t, m, m2) loop
    if to_regclass(r.t) is null then raise exception 'No existe la tabla %: deténgase y avise', r.t; end if;
    select md5(concat_ws('#', (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped), (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel), (select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel), (select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal), (select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel))) into v from (select to_regclass(r.t) as rel) z;
    if v is distinct from r.m and v is distinct from coalesce(r.m2, r.m) then
      raise exception 'La estructura de % no es la de producción (columnas, restricciones, índices, disparadores, RLS o permisos): deténgase y avise', r.t;
    end if;
  end loop;
  -- La tabla nueva: no existe, o existe exactamente como la crea este paquete (la conservó una reversa)
  for r in select * from (values ('campo.reporte_registro', '6bbcd353497807cfff9d4b0b5722da93')) x(t, m) loop
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
  -- Los 4 parámetros de la zona de Valledupar (el XY digitado se valida contra ellos)
  if (select count(*) from campo.parametros where clave in ('zona_lat_min', 'zona_lat_max', 'zona_lon_min', 'zona_lon_max')) <> 4 then
    raise exception 'Faltan los parámetros de la zona de Valledupar en campo.parametros: deténgase y avise';
  end if;
end $guardia$;

-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 10 — ESTRUCTURA
-- campo.reporte_registro: a lo sumo UNA fila por reporte (llave = reporte_id), de solo inserción (los mismos disparadores que campo.reporte_fotos y
-- campo.reporte_datos_sensibles), RLS activa sin políticas, sin permisos para la API y SELECT para homelab_lectura (decisión de David, 25-nov).
-- Va aparte de campo.reportes para que el sello del PDF de los registros viejos no cambie nunca (ni con este paquete ni tras su reversa):
-- el sello es md5 de to_jsonb(campo.reportes); esta tabla entra al sello solo cuando el reporte tiene su fila.
-- campo.reporte_fotos.origen: camara (por omisión: hasta hoy la cámara era obligatoria, así que es cierto para las fotos viejas), galeria o archivo.
-- =====================================================================
-- Si existe, es la que dejó la reversa de este paquete (la guardia exige su estructura exacta): se conserva tal cual.
create table if not exists campo.reporte_registro (
  reporte_id uuid primary key references campo.reportes (id),
  xy_manual boolean not null,                       -- el XY del punto lo digitó quien registró (solo supervisor o administrador)
  lat_registro numeric(9,6),                        -- dónde estaba quien registró (GPS del dispositivo); nulo = el dispositivo no dio ubicación
  lon_registro numeric(9,6),
  precision_registro_m numeric(8,1),
  direccion text,                                   -- dirección, barrio y referencia: opcionales («¿Quiere agregar dirección?»)
  barrio text,
  referencia text,
  creado_en timestamptz not null default clock_timestamp(),
  constraint reporte_registro_par_ck check ((lat_registro is null) = (lon_registro is null)),
  constraint reporte_registro_lat_ck check (lat_registro is null or (lat_registro between -90 and 90)),
  constraint reporte_registro_lon_ck check (lon_registro is null or (lon_registro between -180 and 180)),
  constraint reporte_registro_precision_ck check (precision_registro_m is null or (lat_registro is not null and precision_registro_m between 0 and 100000)),
  constraint reporte_registro_direccion_ck check (direccion is null or (length(direccion) between 1 and 120 and direccion = btrim(direccion))),
  constraint reporte_registro_barrio_ck check (barrio is null or (length(barrio) between 1 and 80 and barrio = btrim(barrio))),
  constraint reporte_registro_referencia_ck check (referencia is null or (length(referencia) between 1 and 200 and referencia = btrim(referencia)))
);
comment on table campo.reporte_registro is 'Registro flexible (25-nov): dónde estaba quien registró, si el XY fue digitado y la dirección opcional. Una fila por reporte; solo inserción. Sin fila = reporte anterior a este paquete.';
comment on column campo.reporte_registro.xy_manual is 'true = el XY del punto (campo.reportes.lat/lon) lo digitó un supervisor o administrador: «XY digitado — registrado desde otro punto».';
comment on column campo.reporte_registro.lat_registro is 'Posición del dispositivo al registrar (GPS). Nula = «sin ubicación del dispositivo».';
create or replace trigger t_solo_agregar before delete or update on campo.reporte_registro for each row execute function campo.f_solo_agregar();
create or replace trigger t_solo_agregar_trunc before truncate on campo.reporte_registro for each statement execute function campo.f_solo_agregar();
alter table campo.reporte_registro enable row level security;
revoke all on table campo.reporte_registro from public, anon, authenticated, service_role;
grant select on table campo.reporte_registro to homelab_lectura;

alter table campo.reporte_fotos add column if not exists origen text not null default 'camara';
do $origen$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'campo.reporte_fotos'::regclass and conname = 'reporte_fotos_origen_ck') then
    alter table campo.reporte_fotos add constraint reporte_fotos_origen_ck check (origen in ('camara', 'galeria', 'archivo'));
  end if;
end $origen$;
comment on column campo.reporte_fotos.origen is 'Registro flexible (25-nov): camara (la del formulario), galeria o archivo (adjuntadas: solo supervisor o administrador). Las fotos anteriores son de cámara.';

-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 20 — CREAR REPORTE (reporte general y formatos de actividad; también la entrada de Técnica)
-- Un solo parámetro nuevo al final, p_registro jsonb (opcional): {xy_manual, lat_registro, lon_registro, precision_registro_m, direccion, barrio, referencia}.
-- Y en p_fotos, cada foto puede traer «origen» (camara | galeria | archivo; camara si no viene).
-- Sin p_registro (la Edge de antes) todo sigue igual y no se guarda fila en campo.reporte_registro.
-- REGLA (en la base, no solo en la pantalla): XY digitado o una foto que no sea de cámara → solo supervisor o administrador (campo.f_autorizar_supervision),
-- y nunca desde la entrada de Técnica (geoportal.via_tecnica). El XY digitado se rechaza fuera de la zona de Valledupar (el del GPS sigue sin rechazarse).
-- La firma cambia (un parámetro más): se quita la anterior y se crea la nueva con sus permisos (DROP: por qué y alcance — solo esa firma; la nueva la reemplaza en la
-- misma transacción y la Edge de antes la sigue llamando igual porque p_registro tiene valor por omisión).
-- =====================================================================
drop function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone);
CREATE FUNCTION public.geoportal_campo_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_origen text, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_orden_trabajo_id uuid DEFAULT NULL::uuid, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone, p_registro jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'storage', 'pg_temp'
AS $function$
declare
  v_email text; v_perfil text; v_origen text := coalesce(p_origen, ''); v_maxdesc integer := campo.f_param('max_descripcion')::integer;
  v_t campo.tipos_reporte%rowtype; v_s campo.subtipos_reporte%rowtype; v_sub bigint;
  v_desc text; v_contrato text; v_verif boolean; v_fuera boolean; v_lat numeric; v_lon numeric;
  v_max_fotos integer; v_min_fotos integer; v_max_bytes bigint := campo.f_param('max_bytes_foto')::bigint;
  v_fotos jsonb := coalesce(p_fotos, '[]'::jsonb); v_n integer; v_f jsonb; v_orden integer; v_ruta text; v_size bigint; v_mime text;
  v_id uuid := p_id; v_prev campo.reportes%rowtype; v_reg timestamptz; v_ref jsonb := '[]'::jsonb;
  v_resultado text; v_causal_id bigint; v_causal_cod text; v_exigir boolean; v_val jsonb; v_gen jsonb; v_sen jsonb;
  v_con_etiquetas boolean; v_etq text; v_etqs text[] := '{}'; v_falta text; v_num bigint; v_consecutivo text;
  v_fin timestamptz; v_max_h numeric;   -- pasada 14/11: hora de inicio
  -- Registro flexible (25-nov)
  v_reg_in jsonb := p_registro; v_xy boolean := false; v_lat_r numeric; v_lon_r numeric; v_prec_r numeric; v_dir text; v_barrio text; v_refer text;
  v_forigen text; v_no_camara integer := 0; v_via_tec boolean := coalesce(current_setting('geoportal.via_tecnica', true), '') = 'on'; v_k text;
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);
  v_perfil := campo.f_perfil(v_email);

  -- Registro flexible: forma del bloque p_registro (solo estas claves; la Edge ya validó la forma y aquí se vuelve a validar)
  if v_reg_in is not null then
    if jsonb_typeof(v_reg_in) <> 'object' then perform campo.f_error('Los datos del registro no vienen en el formato esperado'); end if;
    for v_k in select jsonb_object_keys(v_reg_in) loop
      if v_k not in ('xy_manual', 'lat_registro', 'lon_registro', 'precision_registro_m', 'direccion', 'barrio', 'referencia') then
        perform campo.f_error(format('El dato «%s» no existe en el registro', left(v_k, 40)));
      end if;
    end loop;
    if v_reg_in ? 'xy_manual' and jsonb_typeof(v_reg_in -> 'xy_manual') not in ('boolean', 'null') then perform campo.f_error('xy_manual debe ser sí o no'); end if;
    v_xy := coalesce((v_reg_in ->> 'xy_manual')::boolean, false);
    if (v_reg_in ? 'lat_registro' and jsonb_typeof(v_reg_in -> 'lat_registro') not in ('number', 'null'))
       or (v_reg_in ? 'lon_registro' and jsonb_typeof(v_reg_in -> 'lon_registro') not in ('number', 'null'))
       or (v_reg_in ? 'precision_registro_m' and jsonb_typeof(v_reg_in -> 'precision_registro_m') not in ('number', 'null')) then
      perform campo.f_error('La ubicación del dispositivo no es válida');
    end if;
    v_lat_r := (v_reg_in ->> 'lat_registro')::numeric; v_lon_r := (v_reg_in ->> 'lon_registro')::numeric; v_prec_r := (v_reg_in ->> 'precision_registro_m')::numeric;
    if (v_lat_r is null) <> (v_lon_r is null) then perform campo.f_error('La ubicación del dispositivo debe traer latitud y longitud'); end if;
    if v_lat_r is not null and (v_lat_r < -90 or v_lat_r > 90 or v_lon_r < -180 or v_lon_r > 180) then perform campo.f_error('La ubicación del dispositivo está fuera de los rangos válidos'); end if;
    if v_prec_r is not null and (v_lat_r is null or v_prec_r < 0 or v_prec_r > 100000) then perform campo.f_error('La precisión de la ubicación del dispositivo no es válida'); end if;
    if v_lat_r is not null then v_lat_r := round(v_lat_r, 6); v_lon_r := round(v_lon_r, 6); end if;
    if v_prec_r is not null then v_prec_r := round(v_prec_r, 1); end if;
    if (v_reg_in ? 'direccion' and jsonb_typeof(v_reg_in -> 'direccion') not in ('string', 'null'))
       or (v_reg_in ? 'barrio' and jsonb_typeof(v_reg_in -> 'barrio') not in ('string', 'null'))
       or (v_reg_in ? 'referencia' and jsonb_typeof(v_reg_in -> 'referencia') not in ('string', 'null')) then
      perform campo.f_error('La dirección, el barrio y la referencia deben ser texto');
    end if;
    v_dir := nullif(btrim(coalesce(v_reg_in ->> 'direccion', '')), ''); v_barrio := nullif(btrim(coalesce(v_reg_in ->> 'barrio', '')), '');
    v_refer := nullif(btrim(coalesce(v_reg_in ->> 'referencia', '')), '');
    if length(coalesce(v_dir, '')) > 120 then perform campo.f_error('La dirección es demasiado larga (máximo 120 caracteres)'); end if;
    if length(coalesce(v_barrio, '')) > 80 then perform campo.f_error('El barrio es demasiado largo (máximo 80 caracteres)'); end if;
    if length(coalesce(v_refer, '')) > 200 then perform campo.f_error('La referencia es demasiado larga (máximo 200 caracteres)'); end if;
  end if;
  -- Origen de cada foto (camara si no viene)
  if jsonb_typeof(coalesce(p_fotos, '[]'::jsonb)) = 'array' then
    for v_f in select e from jsonb_array_elements(coalesce(p_fotos, '[]'::jsonb)) e loop
      if jsonb_typeof(v_f) = 'object' and v_f ? 'origen' then
        v_forigen := v_f ->> 'origen';
        if v_forigen is null or v_forigen not in ('camara', 'galeria', 'archivo') then perform campo.f_error('El origen de una foto debe ser cámara, galería o archivo'); end if;
        if v_forigen <> 'camara' then v_no_camara := v_no_camara + 1; end if;
      end if;
    end loop;
  end if;
  -- LA REGLA: XY digitado o foto adjuntada (galería o archivo) → solo supervisor o administrador de campo, y nunca desde la entrada de Técnica
  if v_xy or v_no_camara > 0 then
    if v_via_tec then
      raise exception 'Desde Técnica el registro se hace con la cámara y la ubicación del celular' using errcode = '42501';
    end if;
    if v_perfil is null or v_perfil not in ('admin', 'supervisor') then
      raise exception 'Solo el supervisor o el administrador pueden adjuntar fotos o digitar el XY' using errcode = '42501';
    end if;
    perform campo.f_autorizar_supervision(v_email);
  end if;
  if v_origen not in ('campo', 'escritorio') then perform campo.f_error('El origen debe ser campo o escritorio'); end if;
  if v_origen = 'escritorio' and v_perfil not in ('admin', 'supervisor') then
    raise exception 'Solo el supervisor o el administrador crean reportes desde el escritorio' using errcode = '42501';
  end if;

  -- Reenvío (red inestable): mismo identificador y mismo autor = misma respuesta, sin duplicar (y sin gastar cupo ni consecutivo)
  if v_id is not null then
    select * into v_prev from campo.reportes where id = v_id;
    if found then
      if v_prev.autor = v_email then
        return jsonb_build_object('id', v_prev.id, 'registrado_en', v_prev.registrado_en, 'repetido', true,
                                  'contrato_verificado', v_prev.contrato_verificado, 'aviso_zona', v_prev.fuera_de_zona, 'consecutivo', v_prev.consecutivo);
      end if;
      perform campo.f_error('Identificador de reporte no válido');
    end if;
  end if;

  -- Límite de ritmo (Paso B1): los reenvíos idempotentes de arriba NO consumen cupo; el cupo se verifica antes de validar el resto
  perform campo.f_cupo_reportes(v_email, v_perfil);

  -- Tipo, subtipo y texto
  select t.* into v_t from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where t.codigo = btrim(coalesce(p_tipo, '')) and t.activo and g.activo;
  if not found then perform campo.f_error('El tipo de reporte no existe o está desactivado'); end if;
  if nullif(btrim(coalesce(p_subtipo, '')), '') is not null then
    select s.* into v_s from campo.subtipos_reporte s where s.tipo_id = v_t.id and s.codigo = btrim(p_subtipo);
    if not found then perform campo.f_error('El subtipo no corresponde al tipo elegido'); end if;
    if not v_s.activo then perform campo.f_error('El subtipo está desactivado'); end if;
    v_sub := v_s.id;
  elsif v_t.exige_subtipo then
    perform campo.f_error('Elija un subtipo para este tipo de reporte');
  end if;
  v_desc := nullif(btrim(coalesce(p_descripcion, '')), '');
  if v_t.exige_texto and (v_desc is null or length(v_desc) < 3) then perform campo.f_error('Describa lo que encontró: este tipo de reporte lo exige'); end if;
  if length(coalesce(v_desc, '')) > v_maxdesc then perform campo.f_error(format('La descripción es demasiado larga (máximo %s caracteres)', replace(to_char(v_maxdesc, 'FM9G999'), ',', '.'))); end if;

  -- Resultado y causal (Paso D): solo en los tipos que lo llevan
  v_resultado := nullif(btrim(coalesce(p_resultado, '')), '');
  v_causal_cod := nullif(btrim(coalesce(p_causal, '')), '');
  if v_t.genera_resultado then
    if v_resultado is null then perform campo.f_error('Indique si la visita fue efectiva o inefectiva'); end if;
    if v_resultado not in ('efectivo', 'inefectivo') then perform campo.f_error('El resultado debe ser efectivo o inefectivo'); end if;
    if v_resultado = 'inefectivo' then
      if v_causal_cod is null then perform campo.f_error('Una visita inefectiva necesita la causal'); end if;
      select c.id into v_causal_id from campo.causales c
       where c.codigo = v_causal_cod and c.activo
         and (c.general or exists (select 1 from campo.causales_tipos ct where ct.causal_id = c.id and ct.tipo_id = v_t.id and ct.activo));
      if not found then perform campo.f_error('La causal no existe, está desactivada o no aplica a este formato'); end if;
    elsif v_causal_cod is not null then
      perform campo.f_error('La causal solo se informa cuando la visita es inefectiva');
    end if;
  elsif v_resultado is not null or v_causal_cod is not null then
    perform campo.f_error('Este tipo de reporte no lleva resultado ni causal');
  end if;
  v_exigir := v_resultado is distinct from 'inefectivo';

  -- Coordenada: dato numérico en rango; nunca se rechaza por la ubicación
  if p_lat is null or p_lon is null or p_lat = 'NaN'::numeric or p_lon = 'NaN'::numeric then perform campo.f_error('La coordenada no es válida'); end if;
  if p_lat < -90 or p_lat > 90 or p_lon < -180 or p_lon > 180 then perform campo.f_error('La coordenada está fuera de los rangos válidos de latitud y longitud'); end if;
  v_lat := round(p_lat, 6); v_lon := round(p_lon, 6);
  v_fuera := not (v_lat between campo.f_param('zona_lat_min') and campo.f_param('zona_lat_max')
              and v_lon between campo.f_param('zona_lon_min') and campo.f_param('zona_lon_max'));
  if p_precision_m is not null and (p_precision_m = 'NaN'::numeric or p_precision_m < 0 or p_precision_m > 100000) then perform campo.f_error('La precisión de la coordenada no es válida'); end if;
  -- Registro flexible: el XY digitado debe caer en la zona de Valledupar (ataja un dedazo; el del GPS sigue sin rechazarse) y no lleva precisión
  if v_xy and v_fuera then
    perform campo.f_error(format('El XY digitado está fuera de la zona de Valledupar (latitud %s a %s, longitud %s a %s): revíselo',
                                 trim_scale(campo.f_param('zona_lat_min')), trim_scale(campo.f_param('zona_lat_max')),
                                 trim_scale(campo.f_param('zona_lon_min')), trim_scale(campo.f_param('zona_lon_max'))));
  end if;
  if v_xy and p_precision_m is not null then perform campo.f_error('El XY digitado no lleva precisión: esa es la del GPS'); end if;
  -- La visita inefectiva con XY digitado (solo supervisor) no exige la precisión del GPS (aprobado por David, 25-nov)
  if v_resultado = 'inefectivo' and v_origen = 'campo' and not v_xy and p_precision_m is null then
    perform campo.f_error('Una visita inefectiva necesita la ubicación tomada por el celular (con su precisión): active la ubicación e intente de nuevo');
  end if;

  -- Contrato: según el tipo es obligatorio, opcional o no se pide. Solo se confirma si existe; no se lee ningún otro dato
  v_contrato := nullif(btrim(coalesce(p_contrato, '')), '');
  if v_t.requiere_contrato = 'si' and v_contrato is null then perform campo.f_error('Este formato necesita el número de contrato'); end if;
  if v_t.requiere_contrato = 'no' and v_contrato is not null then perform campo.f_error('Este formato no lleva número de contrato'); end if;
  if v_contrato is not null then
    if v_contrato !~ '^[A-Za-z0-9-]{1,20}$' then perform campo.f_error('El contrato solo puede llevar letras, números y guiones (máximo 20)'); end if;
    if v_t.limite_ventana is not null then
      perform campo.f_cupo_tipo(v_email, v_perfil, v_t.id, v_t.limite_ventana, v_t.nombre);   -- Paso D: tope propio del tipo, en vez del general de contratos
    else
      perform campo.f_cupo_contratos(v_email, v_perfil);   -- Paso B1: tope de reportes con contrato (impide enumerar contratos); antes de consultar si existe
    end if;
    perform campo.f_cupo_contratos_falsos(v_email, v_perfil);   -- Paso B1: tope de contratos NO verificados en 24 h; también antes de consultar si existe
    v_verif := exists (select 1 from public.predios_comercial pc where pc.cod_usuario = v_contrato);
  end if;

  -- Registro flexible: la dirección opcional va en Reportar anomalía (tipos generales) y en los formatos cuyo contrato no es obligatorio (David, 25-nov)
  if (v_dir is not null or v_barrio is not null or v_refer is not null) and not (campo.f_tipo_general(v_t.codigo) or v_t.requiere_contrato <> 'si') then
    perform campo.f_error('Este formato no lleva dirección: la del predio sale del contrato');
  end if;

  -- Campos propios (Paso D): validados contra la definición del tipo; los sensibles se separan
  v_val := campo.f_validar_datos(v_t.id, p_datos, v_exigir);
  v_gen := nullif(v_val -> 'general', '{}'::jsonb);
  v_sen := nullif(v_val -> 'sensibles', '{}'::jsonb);

  -- Orden de trabajo (Paso D): gancho para SCRR; hoy solo se guarda
  if p_orden_trabajo_id is not null then perform campo.f_validar_orden_trabajo(p_orden_trabajo_id, v_email, v_t.id); end if;

  -- Fotos: cantidad (mínimo y máximo del tipo), orden, etiqueta, ruta propia y objeto realmente subido (tamaño y tipo leídos de Storage)
  v_max_fotos := coalesce(v_t.fotos_max, campo.f_param('max_fotos')::integer);
  v_min_fotos := case when v_origen <> 'campo' then 0 when v_exigir then coalesce(v_t.fotos_min, 1) else least(coalesce(v_t.fotos_min, 1), 1) end;
  if jsonb_typeof(v_fotos) <> 'array' then perform campo.f_error('Las fotos no vienen en el formato esperado'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n < v_min_fotos then
    if v_min_fotos = 1 then perform campo.f_error('Un reporte de campo necesita al menos una foto'); end if;
    perform campo.f_error(format('Este formato necesita al menos %s fotos (lleva %s)', v_min_fotos, v_n));
  end if;
  if v_n > v_max_fotos then perform campo.f_error(format('Máximo %s fotos por reporte', v_max_fotos)); end if;
  if v_n > 0 and v_id is null then perform campo.f_error('Para adjuntar fotos primero debe reservarse el reporte (preparar la subida)'); end if;
  if v_n > 0 and (select count(distinct (e ->> 'orden')::integer) <> v_n or min((e ->> 'orden')::integer) <> 1 or max((e ->> 'orden')::integer) <> v_n
                    from jsonb_array_elements(v_fotos) e) then
    perform campo.f_error('El orden de las fotos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  v_con_etiquetas := exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo);
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'orden')::integer loop
    v_orden := (v_f ->> 'orden')::integer;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^reportes/[0-9]{4}-[0-9]{2}/' || v_id::text || '/' || v_orden || '\.jpg$') then
      perform campo.f_error(format('La ruta de la foto %s no corresponde a este reporte', v_orden));
    end if;
    v_etq := nullif(btrim(coalesce(v_f ->> 'etiqueta', '')), '');
    if v_con_etiquetas then
      if v_etq is null then perform campo.f_error(format('Indique qué muestra la foto %s', v_orden)); end if;
      if v_etq <> 'adicional' then
        if not exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.codigo = v_etq and tf.activo) then
          perform campo.f_error(format('La etiqueta de la foto %s no existe en este formato', v_orden));
        end if;
        if v_etq = any (v_etqs) then perform campo.f_error(format('Hay dos fotos con la misma etiqueta (foto %s)', v_orden)); end if;
      end if;
      v_etqs := v_etqs || v_etq;
    elsif v_etq is not null then
      perform campo.f_error('Este tipo de reporte no usa etiquetas de foto');
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime
      from storage.objects o where o.bucket_id = 'campo-fotos' and o.name = v_ruta;
    if not found then perform campo.f_error(format('No se encontró la foto %s: súbala de nuevo', v_orden)); end if;
    if coalesce(v_size, 0) <= 0 then perform campo.f_error(format('La foto %s está vacía', v_orden)); end if;
    if v_size > v_max_bytes then perform campo.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_orden, v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform campo.f_error(format('La foto %s debe ser JPEG', v_orden)); end if;
    v_ref := v_ref || jsonb_build_object('orden', v_orden, 'ruta', v_ruta, 'tamano', v_size, 'mime', v_mime, 'etiqueta', v_etq, 'origen', coalesce(v_f ->> 'origen', 'camara'));
  end loop;
  if v_con_etiquetas and v_exigir and v_origen = 'campo' then
    select tf.nombre into v_falta from campo.tipo_fotos tf
     where tf.tipo_id = v_t.id and tf.activo and tf.obligatoria and tf.codigo <> all (v_etqs) order by tf.orden, tf.id limit 1;
    if v_falta is not null then perform campo.f_error(format('Falta la foto obligatoria: «%s»', v_falta)); end if;
  end if;
  -- Visita inefectiva en campo: al menos una foto de la fachada o del predio (las etiquetas con soporte_inefectiva del tipo)
  if v_resultado = 'inefectivo' and v_origen = 'campo' and exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo and tf.soporte_inefectiva)
     and not exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo and tf.soporte_inefectiva and tf.codigo = any (v_etqs)) then
    perform campo.f_error('Una visita inefectiva necesita la foto de la fachada o del predio');
  end if;
  -- Pasada 14/11: hora de inicio = la del celular al abrir el formulario. Fin = la hora del servidor al registrar (v_fin: la MISMA que se guarda en registrado_en).
  v_fin := clock_timestamp();
  if p_inicio_dispositivo is not null then
    v_max_h := campo.f_param('max_horas_inicio');
    if p_inicio_dispositivo > v_fin + interval '2 minutes' then
      perform campo.f_error('La hora de su celular está adelantada. Corríjala y vuelva a enviar: lo escrito y las fotos no se pierden.');
    end if;
    if p_inicio_dispositivo < v_fin - v_max_h * interval '1 hour' then
      perform campo.f_error(format('Este formulario se abrió hace más de %s horas. Revise la hora de su celular o ábralo de nuevo.', trim_scale(v_max_h)));
    end if;
  end if;
  if v_id is null then v_id := gen_random_uuid(); end if;

  -- Inserción (una sola transacción; una carrera por el mismo id se resuelve como «repetido»).
  -- El consecutivo se toma AQUÍ, al final y dentro del mismo bloque: si la inserción falla, el número vuelve al contador (sin huecos).
  begin
    v_num := campo.f_siguiente_consecutivo(v_t.id);
    if v_num is not null then v_consecutivo := campo.f_texto_consecutivo(v_t.prefijo_consecutivo, v_num); end if;
    insert into campo.reportes (id, tipo_id, subtipo_id, descripcion, contrato, contrato_verificado, lat, lon, precision_m, riesgo_inmediato, origen, fuera_de_zona, autor,
                                datos, resultado, causal_id, consecutivo_num, consecutivo, orden_trabajo_id, registrado_en, inicio_en, inicio_origen)
    values (v_id, v_t.id, v_sub, v_desc, v_contrato, v_verif, v_lat, v_lon, p_precision_m, coalesce(p_riesgo_inmediato, false), v_origen, v_fuera, v_email,
            v_gen, v_resultado, v_causal_id, v_num, v_consecutivo, p_orden_trabajo_id, v_fin, p_inicio_dispositivo, case when p_inicio_dispositivo is not null then 'dispositivo' end)
    returning registrado_en into v_reg;
    insert into campo.reporte_fotos (reporte_id, orden, ruta_storage, tamano_bytes, tipo_mime, etiqueta, origen)
      select v_id, (x ->> 'orden')::smallint, x ->> 'ruta', (x ->> 'tamano')::integer, x ->> 'mime', x ->> 'etiqueta', x ->> 'origen' from jsonb_array_elements(v_ref) x;
    if v_sen is not null then insert into campo.reporte_datos_sensibles (reporte_id, datos) values (v_id, v_sen); end if;
    -- Registro flexible: una fila por reporte, solo si la Edge mandó el bloque (sin fila = como antes)
    if v_reg_in is not null then
      insert into campo.reporte_registro (reporte_id, xy_manual, lat_registro, lon_registro, precision_registro_m, direccion, barrio, referencia)
      values (v_id, v_xy, v_lat_r, v_lon_r, v_prec_r, v_dir, v_barrio, v_refer);
    end if;
  exception when unique_violation then
    select * into v_prev from campo.reportes where id = v_id;
    if found and v_prev.autor = v_email then
      return jsonb_build_object('id', v_prev.id, 'registrado_en', v_prev.registrado_en, 'repetido', true,
                                'contrato_verificado', v_prev.contrato_verificado, 'aviso_zona', v_prev.fuera_de_zona, 'consecutivo', v_prev.consecutivo);
    end if;
    perform campo.f_error('Una de las fotos ya está usada en otro reporte');
  end;

  -- Auditoría: nunca los valores de los campos propios, solo cuántos y si hubo sensibles
  perform campo.f_auditar(v_email, 'campo_crear_reporte', v_id::text,
    jsonb_build_object('tipo', v_t.codigo, 'subtipo', v_s.codigo, 'origen', v_origen, 'fotos', v_n, 'riesgo_inmediato', coalesce(p_riesgo_inmediato, false),
                       'fuera_de_zona', v_fuera, 'contrato_informado', v_contrato is not null, 'contrato_verificado', v_verif,
                       'consecutivo', v_consecutivo, 'resultado', v_resultado, 'causal', case when v_causal_id is not null then v_causal_cod end, 'con_inicio', p_inicio_dispositivo is not null,
                       'campos', (select count(*) from jsonb_object_keys(coalesce(v_gen, '{}'::jsonb))), 'campos_sensibles', v_sen is not null,
                       'orden_trabajo', p_orden_trabajo_id is not null)
    -- Registro flexible: solo marcas, nunca las coordenadas ni la dirección
    || case when v_reg_in is null then '{}'::jsonb else jsonb_build_object('xy_manual', v_xy, 'fotos_adjuntadas', v_no_camara, 'con_ubicacion_dispositivo', v_lat_r is not null,
                                                                        'con_direccion', v_dir is not null or v_barrio is not null or v_refer is not null) end, p_ip);
  return jsonb_build_object('id', v_id, 'registrado_en', v_reg, 'repetido', false, 'contrato_verificado', v_verif, 'aviso_zona', v_fuera, 'consecutivo', v_consecutivo);
end $function$;

revoke all on function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone, jsonb)
  to service_role;

-- Entrada de Técnica (Corte 8): la misma firma con p_registro al final. Desde Técnica solo viaja la ubicación del dispositivo y la dirección opcional;
-- el XY digitado y las fotos adjuntadas los rechaza geoportal_campo_crear_reporte (geoportal.via_tecnica). DROP: por qué y alcance — solo esa firma, reemplazada aquí.
drop function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone);
CREATE FUNCTION public.geoportal_campo_tec_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone, p_registro jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'tecnica', 'pg_temp'
AS $function$
declare v jsonb;
begin
  if p_tipo is null then raise exception 'Falta el tipo de reporte' using errcode = '22023'; end if;
  perform campo.f_tecnica_entrar(p_solicitante, p_tipo);
  v := public.geoportal_campo_crear_reporte(p_solicitante, p_id, p_tipo, p_subtipo, p_descripcion, p_contrato, p_lat, p_lon, p_precision_m, p_riesgo_inmediato, 'campo', p_fotos,
                                            p_ip, p_datos, p_resultado, p_causal, null, p_inicio_dispositivo, p_registro);
  perform set_config('geoportal.via_tecnica', '', true);
  return v || jsonb_build_object('area', 'tecnica');
end $function$;
revoke all on function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone, jsonb)
  to service_role;

-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 30 — LECTURAS DE SUPERVISIÓN: lista, detalle, descarga y datos del PDF
-- Agregan lo de campo.reporte_registro (por la llave; sin fila = reporte anterior: todo nulo) y el origen de las fotos:
--   xy_manual, sin_ubicacion_dispositivo, direccion, barrio, referencia, fotos_adjuntadas; el detalle y la descarga, además, la ubicación del dispositivo y la
--   distancia entre las dos posiciones. El PDF (solo esquema campo; el del acta no cambia) agrega la línea «XY digitado — registrado desde otro punto» y el origen
--   de cada foto adjuntada. EL SELLO de un reporte sin fila en reporte_registro es EXACTAMENTE el de antes (se le concatena '' ); con fila, la fila entra al sello.
-- Firmas iguales: create or replace.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.geoportal_campo_listar_reportes(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v_f jsonb := coalesce(p_filtros, '{}'::jsonb); v_ids uuid[]; v_total integer; v_eps numeric; v_lim integer; v_cur bigint;
        v_rows jsonb; v_min bigint; v_mas boolean;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  v_eps := campo.f_param('distancia_duplicados_m');
  v_lim := least(greatest(coalesce(nullif(v_f ->> 'limite', '')::integer, 1000), 1), 5000);
  v_cur := nullif(v_f ->> 'cursor', '')::bigint;
  select coalesce(array_agg(x.id), '{}'::uuid[]), count(*)::integer into v_ids, v_total from campo.f_filtrar(v_f) x;
  with pag as (
    select x.*, row_number() over (order by x.seq desc) as rn
      from campo.f_filtrar(v_f) x where v_cur is null or x.seq < v_cur order by x.seq desc limit v_lim + 1
  ), cl as (select * from campo.f_grupos_cercanos(v_eps, v_ids)),
  fila as (
    select p.*, t.codigo as tipo_codigo, t.nombre as tipo_nombre, g.codigo as grupo_codigo, g.nombre as grupo_nombre,
           s.codigo as sub_codigo, s.nombre as sub_nombre, cl.grupo_id as grupo_dup, cl.tamano as tam_dup,
           ca.codigo as causal_codigo, ca.nombre as causal_nombre,
           rr.reporte_id as rr_id, rr.xy_manual, rr.lat_registro, rr.direccion, rr.barrio, rr.referencia,
           (select count(*) from campo.reporte_fotos fo where fo.reporte_id = p.id and fo.origen <> 'camara')::integer as fotos_adjuntadas
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
      left join campo.reporte_registro rr on rr.reporte_id = p.id
     where p.rn <= v_lim
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'seq', f.seq,
           'tipo', jsonb_build_object('codigo', f.tipo_codigo, 'nombre', f.tipo_nombre),
           'grupo', jsonb_build_object('codigo', f.grupo_codigo, 'nombre', f.grupo_nombre),
           'subtipo', case when f.sub_codigo is null then null else jsonb_build_object('codigo', f.sub_codigo, 'nombre', f.sub_nombre) end,
           'descripcion', f.descripcion, 'contrato', f.contrato, 'contrato_verificado', f.contrato_verificado,
           'lat', f.lat, 'lon', f.lon, 'precision_m', f.precision_m, 'riesgo_inmediato', f.riesgo_inmediato, 'origen', f.origen,
           'fuera_de_zona', f.fuera_de_zona, 'autor', f.autor, 'registrado_en', f.registrado_en,
           'estado', f.estado, 'estado_desde', f.estado_desde, 'oculto', f.oculto, 'reporte_original_id', f.reporte_original_id,
           'grupo_duplicados', f.grupo_dup, 'tamano_grupo', f.tam_dup, 'n_fotos', f.n_fotos)
           -- Paso D
           || jsonb_build_object(
           'consecutivo', f.consecutivo, 'resultado', f.resultado,
           'causal', case when f.causal_codigo is null then null else jsonb_build_object('codigo', f.causal_codigo, 'nombre', f.causal_nombre) end,
           'orden_trabajo_id', f.orden_trabajo_id, 'datos', coalesce(f.datos, '{}'::jsonb), 'tiene_datos_sensibles', f.tiene_datos_sensibles,
           'inicio_en', f.inicio_en, 'inicio_origen', f.inicio_origen)
           -- Registro flexible (25-nov): nulos si el reporte no tiene fila (anterior a este paquete)
           || jsonb_build_object(
           'xy_manual', f.xy_manual, 'sin_ubicacion_dispositivo', case when f.rr_id is not null then f.lat_registro is null end,
           'direccion', f.direccion, 'barrio', f.barrio, 'referencia', f.referencia, 'fotos_adjuntadas', f.fotos_adjuntadas) order by f.seq desc), '[]'::jsonb),
         min(f.seq), (select count(*) from pag) > v_lim
    into v_rows, v_min, v_mas from fila f;
  return jsonb_build_object('reportes', v_rows, 'total', v_total, 'siguiente', case when v_mas then v_min end, 'distancia_duplicados_m', v_eps);
end $function$;


CREATE OR REPLACE FUNCTION public.geoportal_campo_obtener_reporte(p_solicitante text, p_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v campo.v_reportes_estado%rowtype; v_eps numeric := campo.f_param('distancia_duplicados_m');
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select * into v from campo.v_reportes_estado where id = p_id;
  if not found then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  -- Paso C: consultar el detalle (muestra autor y contrato) queda auditado
  perform campo.f_auditar(v_email, 'campo_ver_detalle', p_id::text, '{}'::jsonb, p_ip);
  return (
    select jsonb_build_object(
      'reporte', jsonb_build_object(
        'id', v.id, 'seq', v.seq,
        'tipo', jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre), 'grupo', jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre),
        'subtipo', case when s.id is null then null else jsonb_build_object('codigo', s.codigo, 'nombre', s.nombre) end,
        'descripcion', v.descripcion, 'contrato', v.contrato, 'contrato_verificado', v.contrato_verificado, 'lat', v.lat, 'lon', v.lon,
        'precision_m', v.precision_m, 'riesgo_inmediato', v.riesgo_inmediato, 'origen', v.origen, 'fuera_de_zona', v.fuera_de_zona,
        'autor', v.autor, 'registrado_en', v.registrado_en, 'estado', v.estado, 'estado_desde', v.estado_desde, 'oculto', v.oculto,
        'reporte_original_id', v.reporte_original_id)
        -- Paso D
        || jsonb_build_object(
        'consecutivo', v.consecutivo, 'resultado', v.resultado,
        'causal', (select jsonb_build_object('codigo', ca.codigo, 'nombre', ca.nombre) from campo.causales ca where ca.id = v.causal_id),
        'orden_trabajo_id', v.orden_trabajo_id, 'datos', coalesce(v.datos, '{}'::jsonb), 'tiene_datos_sensibles', v.tiene_datos_sensibles,
        'inicio_en', v.inicio_en, 'inicio_origen', v.inicio_origen)
        -- Registro flexible (25-nov): «registro» nulo si el reporte no tiene fila (anterior a este paquete)
        || jsonb_build_object('registro', (select jsonb_build_object('xy_manual', rr.xy_manual, 'lat_registro', rr.lat_registro, 'lon_registro', rr.lon_registro,
                                                   'precision_registro_m', rr.precision_registro_m, 'sin_ubicacion_dispositivo', rr.lat_registro is null,
                                                   'distancia_m', case when rr.lat_registro is not null then round(st_distance(v.geom::geography,
                                                     st_setsrid(st_makepoint(rr.lon_registro::double precision, rr.lat_registro::double precision), 4326)::geography)::numeric, 1) end,
                                                   'direccion', rr.direccion, 'barrio', rr.barrio, 'referencia', rr.referencia)
                                             from campo.reporte_registro rr where rr.reporte_id = v.id)),
      'campos', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'tipo_dato', c.tipo_dato, 'unidad', c.unidad,
                                  'opciones', (select jsonb_agg(jsonb_build_object('codigo', o ->> 'codigo', 'nombre', o ->> 'nombre')) from jsonb_array_elements(c.opciones) o),
                                  'sensible', c.sensible, 'activo', c.activo)) order by c.orden, c.id)
                           from campo.tipo_campos c where c.tipo_id = v.tipo_id), '[]'::jsonb),
      'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', f.orden, 'tamano_bytes', f.tamano_bytes, 'tipo_mime', f.tipo_mime, 'registrada_en', f.registrada_en,
                                  'etiqueta', f.etiqueta, 'origen', f.origen,
                                  'etiqueta_nombre', case when f.etiqueta = 'adicional' then 'Adicional'
                                                          else (select tf.nombre from campo.tipo_fotos tf where tf.tipo_id = v.tipo_id and tf.codigo = f.etiqueta) end) order by f.orden)
                           from campo.reporte_fotos f where f.reporte_id = v.id), '[]'::jsonb),
      'eventos', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'tipo_evento', e.tipo_evento, 'estado_nuevo', e.estado_nuevo,
                                  'reporte_original_id', e.reporte_original_id, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en) order by e.id)
                           from campo.reporte_eventos e where e.reporte_id = v.id), '[]'::jsonb),
      'cercanos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'distancia_m', c.d, 'registrado_en', c.registrado_en, 'estado', c.estado) order by c.d)
                              from (select o.id, round(st_distance(o.geom::geography, v.geom::geography)::numeric, 1) as d, o.registrado_en, o.estado
                                      from campo.v_reportes_estado o
                                     where o.id <> v.id and o.tipo_id = v.tipo_id and not o.oculto and st_dwithin(o.geom::geography, v.geom::geography, v_eps::double precision)
                                     order by st_distance(o.geom::geography, v.geom::geography) limit 20) c), '[]'::jsonb),
      'distancia_duplicados_m', v_eps)
    from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id left join campo.subtipos_reporte s on s.id = v.subtipo_id
   where t.id = v.tipo_id);
end $function$;


CREATE OR REPLACE FUNCTION public.geoportal_campo_descarga_pagina(p_solicitante text, p_descarga_id bigint, p_despues_de bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; a record; v_f jsonb; v_corte bigint; v_autor boolean; v_lim integer := least(greatest(coalesce(p_limite, 5000), 1), 5000); v_eps numeric := campo.f_param('distancia_duplicados_m');
        v_ids uuid[]; v_rows jsonb; v_min bigint; v_mas boolean;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select x.id, x.email, x.detalle into a from public.geoportal_auditoria x where x.id = p_descarga_id and x.accion = 'campo_descarga_iniciar';
  if not found or a.email <> v_email then perform campo.f_error('La descarga no existe', 'P0002'); end if;
  if exists (select 1 from public.geoportal_auditoria x where x.accion = 'campo_descarga_cerrar' and x.referencia = p_descarga_id::text) then perform campo.f_error('La descarga ya se cerró', '55000'); end if;
  v_f := a.detalle -> 'filtros'; v_corte := (a.detalle ->> 'hasta_seq')::bigint; v_autor := coalesce((a.detalle ->> 'incluir_autor')::boolean, false);
  select coalesce(array_agg(x.id), '{}'::uuid[]) into v_ids from campo.f_filtrar(v_f) x where x.seq <= v_corte;
  with pag as (
    select x.*, row_number() over (order by x.seq desc) as rn from campo.f_filtrar(v_f) x where x.seq <= v_corte and (p_despues_de is null or x.seq < p_despues_de) order by x.seq desc limit v_lim + 1
  ), cl as (select * from campo.f_grupos_cercanos(v_eps, v_ids)),
  fila as (
    select p.*, t.codigo as tipo_codigo, t.nombre as tipo_nombre, g.nombre as grupo_nombre, s.nombre as sub_nombre, es.nombre as estado_nombre, ca.nombre as causal_nombre,
           cl.grupo_id as grupo_dup, cl.tamano as tam_dup,
           rr.reporte_id as rr_id, rr.xy_manual, rr.lat_registro, rr.lon_registro, rr.precision_registro_m, rr.direccion, rr.barrio, rr.referencia,
           (select count(*) from campo.reporte_fotos fo where fo.reporte_id = p.id and fo.origen <> 'camara')::integer as fotos_adjuntadas
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join campo.estados_reporte es on es.codigo = p.estado left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
      left join campo.reporte_registro rr on rr.reporte_id = p.id
     where p.rn <= v_lim
  )
  select coalesce(jsonb_agg(
           jsonb_build_object('seq', f.seq, 'id', f.id, 'registrado_local', to_char(f.registrado_en at time zone 'America/Bogota', 'YYYY-MM-DD"T"HH24:MI:SS'),
             'tipo_codigo', f.tipo_codigo, 'tipo_nombre', f.tipo_nombre, 'grupo_nombre', f.grupo_nombre, 'subtipo_nombre', f.sub_nombre,
             'consecutivo', f.consecutivo, 'resultado', f.resultado, 'causal_nombre', f.causal_nombre,
             'estado', f.estado, 'estado_nombre', f.estado_nombre, 'oculto', f.oculto, 'riesgo_inmediato', f.riesgo_inmediato, 'fuera_de_zona', f.fuera_de_zona,
             'contrato', f.contrato, 'contrato_verificado', f.contrato_verificado, 'descripcion', f.descripcion,
             'lat', f.lat, 'lon', f.lon, 'precision_m', f.precision_m, 'origen', f.origen, 'n_fotos', f.n_fotos,
             'grupo_duplicados', f.grupo_dup, 'tamano_grupo', f.tam_dup, 'reporte_original_id', f.reporte_original_id,
             'orden_trabajo_id', f.orden_trabajo_id, 'datos', coalesce(f.datos, '{}'::jsonb),
             'inicio_local', to_char(f.inicio_en at time zone 'America/Bogota', 'YYYY-MM-DD"T"HH24:MI:SS'), 'inicio_origen', f.inicio_origen,
             'duracion_min', round(extract(epoch from (f.registrado_en - f.inicio_en)) / 60.0, 1))
           -- Registro flexible (25-nov): nulos si el reporte no tiene fila (anterior a este paquete)
           || jsonb_build_object('xy_manual', f.xy_manual, 'sin_ubicacion_dispositivo', case when f.rr_id is not null then f.lat_registro is null end,
             'lat_registro', f.lat_registro, 'lon_registro', f.lon_registro, 'precision_registro_m', f.precision_registro_m,
             'distancia_registro_m', case when f.lat_registro is not null then round(st_distance(f.geom::geography,
               st_setsrid(st_makepoint(f.lon_registro::double precision, f.lat_registro::double precision), 4326)::geography)::numeric, 1) end,
             'direccion', f.direccion, 'barrio', f.barrio, 'referencia', f.referencia, 'fotos_adjuntadas', f.fotos_adjuntadas)
           || case when v_autor then jsonb_build_object('autor', f.autor) else '{}'::jsonb end order by f.seq desc), '[]'::jsonb),
         min(f.seq), (select count(*) from pag) > v_lim
    into v_rows, v_min, v_mas from fila f;
  return jsonb_build_object('registros', v_rows, 'devueltos', jsonb_array_length(v_rows), 'ultimo_seq', v_min, 'hay_mas', v_mas);
end $function$;


CREATE OR REPLACE FUNCTION public.geoportal_campo_pdf_datos(p_solicitante text, p_esquema text, p_registro_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'acta', 'pg_temp'
AS $function$
declare v_email text; v_r campo.reportes; v_a acta.actas; v_t campo.tipos_reporte; v_d campo.formularios_documento; v_form text; v_sen jsonb; v_secc jsonb; v_cab jsonb;
        v_fotos jsonb; v_firmas jsonb; v_nombre text; v_sello text; v_doc jsonb; v_op text; v_ver integer := 1;
        v_rr campo.reporte_registro;   -- registro flexible (25-nov)
begin
  v_email := campo.f_autorizar_documento(p_solicitante, p_esquema, p_registro_id);
  if p_esquema = 'campo' then
    select * into v_r from campo.reportes where id = p_registro_id;
    select * into v_rr from campo.reporte_registro where reporte_id = p_registro_id;
    select * into v_t from campo.tipos_reporte where id = v_r.tipo_id;
    v_form := 'tipo:' || v_t.codigo;
  else
    select * into v_a from acta.actas where id = p_registro_id;
    v_form := 'acta'; v_ver := v_a.version;
  end if;
  v_d := campo.f_documento_de(v_form);
  if v_d.formulario is null or not v_d.lleva_pdf then perform campo.f_error('Ese formulario no lleva PDF'); end if;
  -- Firmas: las de este registro («esta»). En una corrección del acta (versión 2 en adelante) va la del operario que corrige más las tres del acta original («original»).
  select coalesce(jsonb_agg(jsonb_build_object('rol', x.rol, 'estado', x.estado, 'nombre', x.nombre, 'imagen', encode(x.imagen, 'base64'), 'huella', x.huella, 'de', x.de)
                            order by x.o1, array_position(array['operario', 'usuario', 'testigo'], x.rol)), '[]'::jsonb)
    into v_firmas
    from (select f.*, 'esta'::text as de, case when v_ver > 1 then 2 else 1 end as o1
            from campo.firmas f where f.esquema = p_esquema and f.registro_id = p_registro_id and f.estado <> 'quitada' and (v_ver = 1 or f.rol = 'operario')
          union all
          select f.*, 'original'::text, 1 from campo.firmas f
           where v_ver > 1 and f.esquema = 'acta' and f.estado <> 'quitada'
             and f.registro_id = (select o.id from acta.actas o where o.acta_raiz_id = v_a.acta_raiz_id and o.version = 1)) x;
  select coalesce(nullif(btrim(lb.nombre), ''), split_part(coalesce(v_r.autor, v_a.autor), '@', 1)) into v_op from public.geoportal_lista_blanca lb where lb.email = coalesce(v_r.autor, v_a.autor);
  if p_esquema = 'campo' then
    select d.datos into v_sen from campo.reporte_datos_sensibles d where d.reporte_id = v_r.id;
    v_cab := jsonb_build_array(jsonb_build_array('Formato', v_t.nombre), jsonb_build_array('Consecutivo', v_r.consecutivo), jsonb_build_array('Contrato', coalesce(v_r.contrato, '—')),
               jsonb_build_array('Resultado', case v_r.resultado when 'efectivo' then 'Efectivo (se realizó la actividad)' when 'inefectivo' then 'No efectivo (no se realizó)' else coalesce(v_r.resultado, '—') end
                 || coalesce(' · Causal: ' || (select c.nombre from campo.causales c where c.id = v_r.causal_id), '')), jsonb_build_array('Ubicación', v_r.lat || ', ' || v_r.lon || coalesce(' (precisión ' || v_r.precision_m || ' m)', '')
                 || case when v_rr.xy_manual then ' · XY digitado — registrado desde otro punto' else '' end));
    -- Registro flexible (25-nov): solo si el reporte tiene fila en reporte_registro (los anteriores quedan exactamente como antes)
    if v_rr.reporte_id is not null then
      v_cab := v_cab || jsonb_build_array(jsonb_build_array('Registrado desde', case when v_rr.lat_registro is null then 'Sin ubicación del dispositivo'
                 else v_rr.lat_registro || ', ' || v_rr.lon_registro || coalesce(' (precisión ' || v_rr.precision_registro_m || ' m)', '') end));
      if v_rr.direccion is not null then v_cab := v_cab || jsonb_build_array(jsonb_build_array('Dirección', v_rr.direccion)); end if;
      if v_rr.barrio is not null then v_cab := v_cab || jsonb_build_array(jsonb_build_array('Barrio', v_rr.barrio)); end if;
      if v_rr.referencia is not null then v_cab := v_cab || jsonb_build_array(jsonb_build_array('Referencia', v_rr.referencia)); end if;
    end if;
    with c as (
      select c.seccion, c.orden, c.nombre, c.tipo_dato, c.opciones, coalesce(v_r.datos -> c.codigo, v_sen -> c.codigo) as v
        from campo.tipo_campos c where c.tipo_id = v_t.id and (v_r.datos ? c.codigo or coalesce(v_sen, '{}'::jsonb) ? c.codigo)
    ), f as (
      select c.seccion, c.orden, jsonb_build_array(c.nombre,
               case c.tipo_dato when 'si_no' then case when c.v = 'true'::jsonb then 'Sí' when c.v = 'false'::jsonb then 'No' else c.v #>> '{}' end
                                when 'opcion' then coalesce((select o ->> 'nombre' from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = c.v #>> '{}'), c.v #>> '{}')
                                when 'opciones' then (select string_agg(coalesce((select o ->> 'nombre' from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = x), x), '; ')
                                                        from jsonb_array_elements_text(case when jsonb_typeof(c.v) = 'array' then c.v else '[]'::jsonb end) x)
                                when 'dia_hora' then replace(c.v #>> '{}', 'T', ' ')
                                else c.v #>> '{}' end) as par
        from c
    )
    select jsonb_agg(jsonb_build_object('titulo', s.seccion, 'campos', s.campos) order by s.o) into v_secc
      from (select coalesce(f.seccion, 'Datos') as seccion, min(f.orden) as o, jsonb_agg(f.par order by f.orden) as campos from f group by coalesce(f.seccion, 'Datos')) s;
    select coalesce(jsonb_agg(jsonb_build_object('bucket', 'campo-fotos', 'ruta', p.ruta_storage, 'etiqueta', coalesce(p.etiqueta, 'Foto ' || p.orden)
             || case p.origen when 'galeria' then ' · adjuntada desde la galería' when 'archivo' then ' · adjuntada desde un archivo' else '' end, 'bytes', p.tamano_bytes) order by p.orden), '[]'::jsonb)
      into v_fotos from campo.reporte_fotos p where p.reporte_id = v_r.id;
    v_nombre := campo.f_nombre_pdf(v_r.registrado_en, v_d.sigla, replace(v_r.consecutivo, '-', ''), 1);
    -- Sello: sin fila en reporte_registro se le concatena '' (el sello de un reporte anterior no cambia); con fila, la fila entra al sello
    v_sello := encode(sha256(convert_to(to_jsonb(v_r)::text || coalesce(v_sen::text, '') || case when v_rr.reporte_id is null then '' else to_jsonb(v_rr)::text end || coalesce((select string_agg(f.huella, ',' order by f.rol) from campo.firmas f
                 where f.esquema = 'campo' and f.registro_id = v_r.id and f.estado = 'firmo'), ''), 'UTF8')), 'hex');
  else
    v_cab := jsonb_build_array(jsonb_build_array('Consecutivo', v_a.consecutivo || case when v_a.version > 1 then ' (versión ' || v_a.version || ')' else '' end),
               jsonb_build_array('Acta física', coalesce(v_a.numero_acta_fisica, 'pendiente') || coalesce(' del ' || to_char(v_a.fecha_acta_fisica, 'YYYY-MM-DD'), '')),
               jsonb_build_array('Contrato', coalesce(v_a.contrato, '—')), jsonb_build_array('Dirección', coalesce(v_a.direccion, '—')), jsonb_build_array('Barrio', coalesce(v_a.barrio, '—')),
               jsonb_build_array('Ubicación', v_a.lat || ', ' || v_a.lon || coalesce(' (precisión ' || v_a.precision_m || ' m)', '')));
    v_secc := jsonb_build_array(
      jsonb_build_object('titulo', 'Medidor', 'campos', jsonb_build_array(
        jsonb_build_array('Tiene medidor', case when v_a.tiene_medidor then 'Sí' when v_a.tiene_medidor = false then 'No' else '—' end),
        jsonb_build_array('Serie', coalesce(v_a.medidor_serie, '—')), jsonb_build_array('Marca', coalesce(v_a.marca, '—')), jsonb_build_array('Lectura (m³)', coalesce(v_a.lectura_m3::text, '—')),
        jsonb_build_array('Serie de los sellos', coalesce(v_a.serie_sellos, '—')))),
      jsonb_build_object('titulo', 'Hallazgos', 'campos', jsonb_build_array(
        jsonb_build_array('Sin irregularidad', case when v_a.sin_irregularidad then 'Sí' else 'No' end),
        jsonb_build_array('Hallazgos', coalesce((select string_agg(coalesce(h.texto_otro, th.nombre), '; ') from acta.acta_hallazgos h join acta.tipos_hallazgo th on th.id = h.tipo_hallazgo_id where h.acta_id = v_a.id), '—')),
        jsonb_build_array('Descripción', coalesce(v_a.descripcion_hallazgos, '—')),
        jsonb_build_array('Acciones', coalesce((select string_agg(ac.nombre, '; ') from acta.acta_acciones x join acta.acciones_correctivas ac on ac.id = x.accion_id where x.acta_id = v_a.id), '—')))),
      jsonb_build_object('titulo', 'Quién atendió', 'campos', jsonb_build_array(
        jsonb_build_array('Nadie atendió', case when v_a.nadie_atendio then 'Sí' else 'No' end),
        jsonb_build_array('Atendió', coalesce((select p.nombre || coalesce(' (' || coalesce(ca.nombre, p.calidad_texto) || ')', '') from acta.acta_personas p left join acta.calidades_atendiente ca on ca.id = p.calidad_id
                                                where p.acta_id = v_a.id and p.rol = 'atendiente' limit 1), '—')),
        jsonb_build_array('Testigo', coalesce((select p.nombre from acta.acta_personas p where p.acta_id = v_a.id and p.rol = 'testigo' limit 1), '—')),
        jsonb_build_array('Observaciones', coalesce(v_a.observaciones, '—')))));
    select coalesce(jsonb_agg(jsonb_build_object('bucket', 'acta-evidencias', 'ruta', p.ruta_storage, 'etiqueta', coalesce(tf.nombre, 'Foto ' || p.orden), 'bytes', p.tamano_bytes) order by p.orden), '[]'::jsonb)
      into v_fotos from acta.acta_fotos p left join acta.tipos_foto tf on tf.id = p.tipo_foto_id where p.acta_id = v_a.id;
    v_nombre := campo.f_nombre_pdf(v_a.registrado_en, v_d.sigla, v_a.consecutivo, v_a.version);
    v_sello := encode(sha256(convert_to(coalesce((select s.sello_sha256 from acta.acta_sellos s where s.acta_id = v_a.id), '') || coalesce((select string_agg(x ->> 'huella', ',' order by x ->> 'de', x ->> 'rol')
                 from jsonb_array_elements(v_firmas) x where x ->> 'estado' = 'firmo'), ''), 'UTF8')), 'hex');
  end if;
  select jsonb_build_object('nombre', d.nombre, 'ruta', d.ruta, 'sha256', d.sha256, 'bytes', d.bytes, 'version', d.version) into v_doc
    from campo.documentos_pdf d where d.esquema = p_esquema and d.registro_id = p_registro_id;
  return jsonb_build_object('esquema', p_esquema, 'registro_id', p_registro_id, 'formulario', v_form, 'version', v_ver, 'nombre', v_nombre,
    'ruta', p_esquema || '/' || to_char(coalesce(v_r.registrado_en, v_a.registrado_en) at time zone 'America/Bogota', 'YYYY-MM') || '/' || p_registro_id || '/' || v_nombre,
    'titulo', case when p_esquema = 'acta' then 'ACTA DE INSPECCIÓN TÉCNICA · REPORTAR POSIBLE PÉRDIDA' else upper(v_t.nombre) end,
    'consecutivo', coalesce(v_r.consecutivo, v_a.consecutivo),
    'registrado_en', to_char(coalesce(v_r.registrado_en, v_a.registrado_en) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
    'inicio_en', to_char(coalesce(v_r.inicio_en, v_a.inicio_en) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
    'fin_en', to_char(coalesce(v_r.registrado_en, v_a.fin_en) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
    'operario', jsonb_build_object('nombre', v_op, 'correo', coalesce(v_r.autor, v_a.autor)),
    'cabecera', v_cab, 'secciones', coalesce(v_secc, '[]'::jsonb), 'fotos', v_fotos, 'firmas', v_firmas, 'sello', v_sello, 'documento', v_doc);
end $function$;



-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 40 — «AVISOS Y ACTIVIDADES DERIVADAS»: conteo de pendientes y descarga auditada (agregado del encargo, 25-nov 21:10)
-- campo.f_derivadas_filtradas(filtros): los ids de las derivadas que cumplen los filtros de la lista (estado, contrato, actividad, desde, hasta, origen), validados
--   igual que hoy. La usan la lista y la descarga, así que las dos filtran lo mismo.
-- geoportal_campo_derivadas: además de las filas, «total» (con los filtros) y «pendientes» (con los filtros, menos el de estado). Antes la pantalla veía «100+».
-- Descarga auditada, como la de Reportes: iniciar (cuenta y fija el corte, deja la auditoría), pagina (hasta 5.000 filas por página, por id) y cerrar.
--   SIN datos de contacto (aviso_datos nunca se lee aquí: f_derivada_json solo dice trae_datos y cuántas entregas) y sin texto libre (observación, dirección
--   correcta, motivo de cierre); los correos de las personas (quien registró, quien cerró, quien lo vio otra vez) solo para el administrador que lo pide.
-- Mismo permiso que la lista: campo.f_autorizar_registradas (administrador, supervisor de actas o de campo).
-- =====================================================================
create function campo.f_derivadas_filtradas(p_filtros jsonb)
 returns table (id bigint)
 language plpgsql
 stable security definer
 set search_path to 'campo', 'pg_temp'
as $function$
declare f jsonb := coalesce(p_filtros, '{}'::jsonb); v_est text; v_con text; v_act text; v_desde date; v_hasta date; v_ori text;
begin
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_est := nullif(f ->> 'estado', ''); v_con := nullif(btrim(coalesce(f ->> 'contrato', '')), ''); v_act := nullif(f ->> 'actividad', '');
    v_desde := nullif(f ->> 'desde', '')::date; v_hasta := nullif(f ->> 'hasta', '')::date; v_ori := nullif(f ->> 'origen', '');
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  if v_est is not null and v_est not in ('pendiente', 'atendida', 'atendida_fuera', 'anulada') then perform campo.f_error('El estado no es válido'); end if;
  if v_ori is not null and v_ori not in ('registro', 'analisis') then perform campo.f_error('El origen no es válido'); end if;
  return query
    select d.id from campo.derivadas d
     where (v_est is null or campo.f_derivada_estado(d.id) = v_est) and (v_con is null or d.contrato = v_con) and (v_act is null or d.actividad = v_act)
       and (v_ori is null or (v_ori = 'registro' and d.origen_id is not null) or (v_ori = 'analisis' and d.observacion_id is not null))
       and (v_desde is null or (d.creado_en at time zone 'America/Bogota')::date >= v_desde) and (v_hasta is null or (d.creado_en at time zone 'America/Bogota')::date <= v_hasta);
end $function$;
revoke all on function campo.f_derivadas_filtradas(jsonb) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivadas(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_antes bigint; v_lim integer; v_filas jsonb; v_n integer; v_total integer; v_pend integer;
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_antes := nullif(f ->> 'antes', '')::bigint;
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 50), 1), 200);
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  -- Registro flexible (25-nov, agregado de David): el total y los pendientes, con los mismos filtros (los pendientes, sin el filtro de estado)
  select count(*)::integer into v_total from campo.f_derivadas_filtradas(f - 'antes' - 'limite');
  select count(*)::integer into v_pend from campo.f_derivadas_filtradas((f - 'antes' - 'limite') || '{"estado": "pendiente"}'::jsonb);
  select count(*), coalesce(jsonb_agg(campo.f_derivada_json(x.id) order by x.id desc) filter (where x.rn <= v_lim), '[]'::jsonb) into v_n, v_filas
    from (select q.id, row_number() over (order by q.id desc) as rn from campo.f_derivadas_filtradas(f - 'antes' - 'limite') q
           where v_antes is null or q.id < v_antes order by q.id desc limit v_lim + 1) x;
  return jsonb_build_object('filas', v_filas, 'siguiente', case when v_n > v_lim then (select min((e ->> 'id')::bigint) from jsonb_array_elements(v_filas) e) end,
                            'total', v_total, 'pendientes', v_pend);
end $function$;

-- Una fila de f_derivada_json para la DESCARGA: nunca el texto libre (la observación escrita, la dirección correcta ni el motivo de cierre, que pueden traer datos de
-- personas); los correos de las personas (quien originó, quien cerró, quien lo vio otra vez) solo si p_con_correos (el administrador que los pidió).
create function campo.f_derivada_descarga(p jsonb, p_con_correos boolean)
 returns jsonb
 language sql
 immutable
 set search_path to 'pg_catalog'
as $function$
  select case when p_con_correos then x else x #- '{origen,operario}' #- '{cierre,autor}' #- '{origen,ultimo_visto,autor}' end
    from (select p #- '{origen,texto}' #- '{origen,direccion_correcta}' #- '{cierre,motivo}' as x) s
$function$;
revoke all on function campo.f_derivada_descarga(jsonb, boolean) from public, anon, authenticated, service_role;

create function public.geoportal_campo_derivadas_descarga_iniciar(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_formato text DEFAULT 'xlsx'::text,
                                                                  p_incluir_autor boolean DEFAULT false, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v_f jsonb := coalesce(p_filtros, '{}'::jsonb) - 'antes' - 'limite'; v_formato text := lower(btrim(coalesce(p_formato, '')));
        v_total bigint; v_corte bigint; v_id bigint; v_autor boolean := coalesce(p_incluir_autor, false);
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if v_formato not in ('csv', 'xlsx') then perform campo.f_error('El formato debe ser Excel o CSV'); end if;
  if v_autor and campo.f_perfil(v_email) is distinct from 'admin' then perform campo.f_error('Solo el administrador puede incluir los correos de las personas', '42501'); end if;
  if jsonb_typeof(v_f) <> 'object' then perform campo.f_error('Los filtros no son válidos'); end if;
  select count(*), max(x.id) into v_total, v_corte from campo.f_derivadas_filtradas(v_f) x;
  if v_total = 0 then perform campo.f_error('No hay avisos ni actividades con esos filtros'); end if;
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
  values (v_email, 'campo_derivadas_descarga_iniciar', v_formato, jsonb_build_object('filtros', v_f, 'incluir_autor', v_autor, 'filas_esperadas', v_total, 'hasta_id', v_corte), p_ip)
  returning id into v_id;
  return jsonb_build_object('descarga_id', v_id, 'total', v_total, 'formato', v_formato, 'filtros', v_f, 'incluir_autor', v_autor, 'hasta_id', v_corte,
                            'generado_por', v_email, 'generado_en', to_char(campo.f_ahora_bogota(), 'DD/MM/YYYY HH24:MI'));
end $function$;

create function public.geoportal_campo_derivadas_descarga_pagina(p_solicitante text, p_descarga_id bigint, p_despues_de bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; a record; v_f jsonb; v_corte bigint; v_autor boolean; v_lim integer := least(greatest(coalesce(p_limite, 5000), 1), 5000); v_rows jsonb; v_min bigint; v_n integer;
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  select x.id, x.email, x.detalle into a from public.geoportal_auditoria x where x.id = p_descarga_id and x.accion = 'campo_derivadas_descarga_iniciar';
  if not found or a.email <> v_email then perform campo.f_error('La descarga no existe', 'P0002'); end if;
  if exists (select 1 from public.geoportal_auditoria x where x.accion = 'campo_derivadas_descarga_cerrar' and x.referencia = p_descarga_id::text) then
    perform campo.f_error('La descarga ya se cerró', '55000');
  end if;
  v_f := a.detalle -> 'filtros'; v_corte := (a.detalle ->> 'hasta_id')::bigint; v_autor := coalesce((a.detalle ->> 'incluir_autor')::boolean, false);
  select count(*), coalesce(jsonb_agg(campo.f_derivada_descarga(campo.f_derivada_json(q.id), v_autor) order by q.id desc)
                                      filter (where q.rn <= v_lim), '[]'::jsonb), min(q.id) filter (where q.rn <= v_lim)
    into v_n, v_rows, v_min
    from (select x.id, row_number() over (order by x.id desc) as rn from campo.f_derivadas_filtradas(v_f) x
           where x.id <= v_corte and (p_despues_de is null or x.id < p_despues_de) order by x.id desc limit v_lim + 1) q;
  return jsonb_build_object('registros', v_rows, 'devueltos', jsonb_array_length(v_rows), 'ultimo_id', v_min, 'hay_mas', v_n > v_lim);
end $function$;

create function public.geoportal_campo_derivadas_descarga_cerrar(p_solicitante text, p_descarga_id bigint, p_filas integer, p_resultado text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; a record; v_res text := lower(btrim(coalesce(p_resultado, '')));
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if v_res not in ('completa', 'cancelada', 'error') then perform campo.f_error('El resultado debe ser completa, cancelada o error'); end if;
  if p_filas is null or p_filas < 0 then perform campo.f_error('El número de filas no es válido'); end if;
  select x.id, x.email, x.detalle into a from public.geoportal_auditoria x where x.id = p_descarga_id and x.accion = 'campo_derivadas_descarga_iniciar';
  if not found or a.email <> v_email then perform campo.f_error('La descarga no existe', 'P0002'); end if;
  if exists (select 1 from public.geoportal_auditoria x where x.accion = 'campo_derivadas_descarga_cerrar' and x.referencia = p_descarga_id::text) then
    return jsonb_build_object('cerrada', true, 'repetida', true);
  end if;
  perform campo.f_auditar(v_email, 'campo_derivadas_descarga_cerrar', p_descarga_id::text,
                          jsonb_build_object('filas', p_filas, 'resultado', v_res, 'filas_esperadas', a.detalle -> 'filas_esperadas'), p_ip);
  return jsonb_build_object('cerrada', true, 'repetida', false);
end $function$;

revoke all on function public.geoportal_campo_derivadas_descarga_iniciar(text, jsonb, text, boolean, text), public.geoportal_campo_derivadas_descarga_pagina(text, bigint, bigint, integer),
                       public.geoportal_campo_derivadas_descarga_cerrar(text, bigint, integer, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_derivadas_descarga_iniciar(text, jsonb, text, boolean, text), public.geoportal_campo_derivadas_descarga_pagina(text, bigint, bigint, integer),
                          public.geoportal_campo_derivadas_descarga_cerrar(text, bigint, integer, text, text)
  to service_role;


-- ===================== 01. Estructura =====================
do $p1$
begin
  perform pg_temp.ok('01.01 campo.reporte_registro: llave = reporte_id (a lo sumo una fila por reporte)',
    (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'campo.reporte_registro'::regclass and contype = 'p') = 'PRIMARY KEY (reporte_id)');
  perform pg_temp.ok('01.02 RLS activa, sin políticas, sin permisos para la API; SELECT (y nada más) para homelab_lectura',
    (select relrowsecurity from pg_class where oid = 'campo.reporte_registro'::regclass) and not exists (select 1 from pg_policies where schemaname in ('campo', 'acta'))
    and not has_table_privilege('anon', 'campo.reporte_registro', 'select') and not has_table_privilege('authenticated', 'campo.reporte_registro', 'select')
    and not has_table_privilege('service_role', 'campo.reporte_registro', 'select') and not has_table_privilege('service_role', 'campo.reporte_registro', 'insert')
    and has_table_privilege('homelab_lectura', 'campo.reporte_registro', 'select') and not has_table_privilege('homelab_lectura', 'campo.reporte_registro', 'insert')
    and not has_table_privilege('homelab_lectura', 'campo.reporte_registro', 'update'));
  perform pg_temp.ok('01.03 los mismos disparadores de solo inserción que campo.reporte_fotos',
    (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = 'campo.reporte_registro'::regclass and not tgisinternal)
    = (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = 'campo.reporte_fotos'::regclass and not tgisinternal));
  perform pg_temp.ok('01.04 las fotos de antes quedan como de cámara (origen camara)',
    (select bool_and(origen = 'camara') from campo.reporte_fotos where reporte_id in (pg_temp.val('viejo')::uuid, pg_temp.val('viejo_general')::uuid)));
  perform pg_temp.ok('01.05 los reportes de antes no tienen fila en reporte_registro',
    not exists (select 1 from campo.reporte_registro where reporte_id in (pg_temp.val('viejo')::uuid, pg_temp.val('viejo_general')::uuid)));
  perform pg_temp.ok('01.06 la huella del acta no cambió', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '111506c690249ad3b56ebf572566434c');
  perform pg_temp.ok('01.07 la huella de Técnica no cambió (cambia la firma de geoportal_campo_tec_crear_reporte, que no es de esa huella)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))) = '838b80984e51cc7873a666f85d657195');
  perform pg_temp.ok('01.08 solo quedan las firmas nuevas de crear_reporte y de la entrada de Técnica',
    to_regprocedure('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)') is null and to_regprocedure('public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone)') is null and to_regprocedure('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone,jsonb)') is not null and to_regprocedure('public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone,jsonb)') is not null);
  begin
    insert into campo.reporte_registro (reporte_id, xy_manual) values (pg_temp.val('viejo')::uuid, false);
    update campo.reporte_registro set xy_manual = true where reporte_id = pg_temp.val('viejo')::uuid;
    perform pg_temp.ok('01.09 reporte_registro no se modifica (solo inserción)', false);
  exception when others then perform pg_temp.ok('01.09 reporte_registro no se modifica (solo inserción)', true);
  end;
end $p1$;

-- ===================== 02. El sello y el PDF de un reporte de antes, después de migrar =====================
do $p2$
declare r jsonb; l jsonb; ADM text := 'ztrf.admin@emdupar.gov.co';
begin
  r := pg_temp.pdf(ADM, pg_temp.val('viejo')::uuid);
  perform pg_temp.ok('02.01 el sello de un reporte de antes es IGUAL después de la migración', r ->> 'sello' = pg_temp.val('sello_viejo'), (r ->> 'sello') || ' vs ' || pg_temp.val('sello_viejo'));
  perform pg_temp.ok('02.02 su cabecera y sus fotos en el PDF quedan iguales', (r -> 'cabecera')::text = pg_temp.val('cab_viejo') and (r -> 'fotos')::text = pg_temp.val('fotos_viejo'), (r -> 'cabecera')::text);
  l := pg_temp.lista(ADM, pg_temp.val('viejo')::uuid);
  perform pg_temp.ok('02.03 en la lista, lo de antes sigue igual y lo nuevo viene vacío (xy_manual y sin_ubicacion nulos, 0 fotos adjuntadas)',
    (l - array['xy_manual', 'sin_ubicacion_dispositivo', 'direccion', 'barrio', 'referencia', 'fotos_adjuntadas']) = pg_temp.val('lista_vieja')::jsonb
    and l -> 'xy_manual' = 'null'::jsonb and l -> 'sin_ubicacion_dispositivo' = 'null'::jsonb and (l ->> 'fotos_adjuntadas')::int = 0, l::text);
  r := pg_temp.detalle(ADM, pg_temp.val('viejo')::uuid);
  perform pg_temp.ok('02.04 el detalle de un reporte de antes trae «registro» nulo y las fotos con origen camara',
    r -> 'reporte' -> 'registro' = 'null'::jsonb and (select bool_and(f ->> 'origen' = 'camara') from jsonb_array_elements(r -> 'fotos') f), left(r::text, 400));
end $p2$;

-- ===================== 03. Operador de campo: sigue igual (cámara y GPS); queda dónde estaba =====================
do $p3$
declare r jsonb; n0 bigint; OP text := 'ztrf.op@emdupar.gov.co'; G jsonb := '{"lat_registro": 10.460001, "lon_registro": -73.250002, "precision_registro_m": 6.24}';
begin
  r := pg_temp.reg(OP, 'otro', '[{"origen": "camara"}]', G);
  perform pg_temp.ok('03.01 el operador registra con cámara y GPS (y la ubicación del dispositivo)', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.ok('03.02 queda su fila: XY no digitado, ubicación del dispositivo con 6 decimales y precisión con 1',
    exists (select 1 from campo.reporte_registro where reporte_id = (r ->> '_id')::uuid and not xy_manual and lat_registro = 10.460001 and lon_registro = -73.250002 and precision_registro_m = 6.2));
  perform pg_temp.ok('03.03 su foto queda de cámara', (select origen from campo.reporte_fotos where reporte_id = (r ->> '_id')::uuid) = 'camara');
  select count(*) into n0 from campo.reportes where autor = OP;
  r := pg_temp.reg(OP, 'otro', '[{"origen": "galeria"}]', G);
  perform pg_temp.ok('03.04 el operador NO puede adjuntar una foto de la galería (403)', pg_temp.err(r) = '42501' and pg_temp.msg(r) ~ 'supervisor', r::text);
  r := pg_temp.reg(OP, 'otro', '[{"origen": "archivo"}]', G);
  perform pg_temp.ok('03.05 el operador NO puede adjuntar una foto de un archivo (403)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', G || '{"xy_manual": true}', 10.47, -73.26, null);
  perform pg_temp.ok('03.06 el operador NO puede digitar el XY (403)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.reg(OP, 'otro', '[{"origen": "camara"}, {"origen": "galeria"}]', null);
  perform pg_temp.ok('03.07 tampoco sin el bloque del registro (una foto de galería basta para el rechazo)', pg_temp.err(r) = '42501', r::text);
  perform pg_temp.ok('03.08 los rechazos no dejaron reportes ni filas', (select count(*) from campo.reportes where autor = OP) = n0);
  r := pg_temp.reg(OP, 'otro', '[{"origen": "selfie"}]', G);
  perform pg_temp.ok('03.09 un origen de foto inventado se rechaza (400)', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', G, 10.46, -73.25, null, '123456', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('03.10 la visita inefectiva del operador sigue exigiendo la precisión del GPS', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'precisión', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', null);
  perform pg_temp.ok('03.11 la llamada de la Edge de antes (sin p_registro) sigue funcionando y no deja fila',
    pg_temp.err(r) = 'OK' and not exists (select 1 from campo.reporte_registro where reporte_id = (r ->> '_id')::uuid), r::text);
end $p3$;

-- ===================== 04. Sin permisos =====================
do $p4$
declare r jsonb; S text := 'ztrf.sin@emdupar.gov.co';
begin
  r := pg_temp.reg(S, 'otro', '[{}]', '{"lat_registro": 10.46, "lon_registro": -73.25}');
  perform pg_temp.ok('04.01 sin permisos no registra (403, ya en la reserva)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_listar_reportes(%L, ''{}''::jsonb, null)', S));
  perform pg_temp.ok('04.02 sin permisos no ve la lista (403)', pg_temp.err(r) = '42501', r::text);
end $p4$;

-- ===================== 05. Supervisor de Comercial: galería, archivo y XY digitado =====================
do $p5$
declare r jsonb; l jsonb; d jsonb; p jsonb; v_id uuid; SUP text := 'ztrf.sup@emdupar.gov.co'; ADM text := 'ztrf.admin@emdupar.gov.co';
  G jsonb := '{"xy_manual": true, "lat_registro": 10.4801, "lon_registro": -73.2701, "precision_registro_m": 12}';
begin
  r := pg_temp.reg(SUP, 'otro', '[{"origen": "galeria"}, {"origen": "archivo"}]', G, 10.461234, -73.251234, null);
  perform pg_temp.ok('05.01 el supervisor registra con galería, archivo y XY digitado', pg_temp.err(r) = 'OK', r::text);
  v_id := (r ->> '_id')::uuid; perform pg_temp.guardar('sup_flex', v_id::text);
  perform pg_temp.ok('05.02 queda marcado: xy_manual, el XY digitado como punto y la ubicación del dispositivo aparte',
    exists (select 1 from campo.reporte_registro rr join campo.reportes x on x.id = rr.reporte_id where rr.reporte_id = v_id and rr.xy_manual
              and x.lat = 10.461234 and x.lon = -73.251234 and x.precision_m is null and rr.lat_registro = 10.4801 and rr.lon_registro = -73.2701));
  perform pg_temp.ok('05.03 el origen de cada foto queda guardado (galeria, archivo)',
    (select string_agg(origen, ',' order by orden) from campo.reporte_fotos where reporte_id = v_id) = 'galeria,archivo');
  l := pg_temp.lista(SUP, v_id);
  perform pg_temp.ok('05.04 la lista lo marca: xy_manual, con ubicación del dispositivo y 2 fotos adjuntadas',
    l -> 'xy_manual' = 'true'::jsonb and l -> 'sin_ubicacion_dispositivo' = 'false'::jsonb and (l ->> 'fotos_adjuntadas')::int = 2, l::text);
  d := pg_temp.detalle(SUP, v_id);
  perform pg_temp.ok('05.05 el detalle trae las dos posiciones y la distancia entre ellas (unos 2,9 km)',
    d -> 'reporte' -> 'registro' -> 'xy_manual' = 'true'::jsonb and (d -> 'reporte' -> 'registro' ->> 'distancia_m')::numeric between 2500 and 3500
    and (select string_agg(f ->> 'origen', ',' order by (f ->> 'orden')::int) from jsonb_array_elements(d -> 'fotos') f) = 'galeria,archivo', left((d -> 'reporte')::text, 600));
  -- revisión previa inefectiva (lleva PDF) con XY digitado: exenta de la precisión del GPS
  r := pg_temp.reg(SUP, 'revision_previa', '[{"etiqueta": "fachada_predio", "origen": "galeria"}]', G, 10.462, -73.252, null, '123456', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('05.06 la visita inefectiva con XY digitado del supervisor no exige la precisión del GPS', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('sup_pdf', r ->> '_id');
  p := pg_temp.pdf(SUP, (r ->> '_id')::uuid);
  perform pg_temp.ok('05.07 el PDF dice «XY digitado — registrado desde otro punto», desde dónde y el origen de la foto',
    pg_temp.cab(p, 'Ubicación') ~ 'XY digitado — registrado desde otro punto' and pg_temp.cab(p, 'Registrado desde') = '10.480100, -73.270100 (precisión 12.0 m)'
    and p -> 'fotos' -> 0 ->> 'etiqueta' ~ 'adjuntada desde la galería', (p -> 'cabecera')::text || (p -> 'fotos')::text);
  -- sin ubicación del dispositivo
  r := pg_temp.reg(SUP, 'otro', '[{"origen": "galeria"}]', '{"xy_manual": true}', 10.463, -73.253, null);
  perform pg_temp.ok('05.08 sin ubicación del dispositivo, el supervisor registra igual', pg_temp.err(r) = 'OK', r::text);
  l := pg_temp.lista(SUP, (r ->> '_id')::uuid);
  perform pg_temp.ok('05.09 y queda la marca «sin ubicación del dispositivo» en la lista', l -> 'sin_ubicacion_dispositivo' = 'true'::jsonb, l::text);
  r := pg_temp.reg(SUP, 'revision_previa', '[{"etiqueta": "fachada_predio", "origen": "archivo"}]', '{"xy_manual": true}', 10.464, -73.254, null, '123456', 'inefectivo', 'nadie_atiende');
  p := pg_temp.pdf(SUP, (r ->> '_id')::uuid);
  perform pg_temp.ok('05.10 en el PDF: «Registrado desde: Sin ubicación del dispositivo»', pg_temp.cab(p, 'Registrado desde') = 'Sin ubicación del dispositivo', (p -> 'cabecera')::text);
  -- topes del XY digitado
  r := pg_temp.reg(SUP, 'otro', '[{}]', '{"xy_manual": true}', 4.711, -74.072, null);
  perform pg_temp.ok('05.11 un XY digitado fuera de la zona de Valledupar se rechaza (400) y dice el rango', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'fuera de la zona de Valledupar', r::text);
  r := pg_temp.reg(SUP, 'otro', '[{}]', '{"xy_manual": true}', 10.46, -73.25, 4);
  perform pg_temp.ok('05.12 un XY digitado no lleva precisión (400)', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'no lleva precisión', r::text);
  r := pg_temp.reg(SUP, 'otro', '[{}]', null, 4.711, -74.072, 5);
  perform pg_temp.ok('05.13 el XY del GPS fuera de la zona sigue sin rechazarse (aviso de zona)', pg_temp.err(r) = 'OK' and r -> 'aviso_zona' = 'true'::jsonb, r::text);
  -- descarga
  r := pg_temp.rpc(format('public.geoportal_campo_descarga_iniciar(%L, ''{}''::jsonb, ''xlsx'', false, null)', SUP));
  d := pg_temp.rpc(format('public.geoportal_campo_descarga_pagina(%L, %s, null, 5000)', SUP, r ->> 'descarga_id'));
  select e into l from jsonb_array_elements(d -> 'registros') e where (e ->> 'id')::uuid = pg_temp.val('sup_flex')::uuid;
  perform pg_temp.ok('05.14 la descarga trae xy_manual, la ubicación del dispositivo, la distancia y las fotos adjuntadas (y no el correo)',
    l -> 'xy_manual' = 'true'::jsonb and (l ->> 'lat_registro')::numeric = 10.4801 and (l ->> 'distancia_registro_m')::numeric > 2500 and (l ->> 'fotos_adjuntadas')::int = 2 and not (l ? 'autor'), l::text);
  perform pg_temp.rpc(format('public.geoportal_campo_descarga_cerrar(%L, %s, 1, ''completa'', null)', SUP, r ->> 'descarga_id'));
  -- reenvío idempotente
  r := pg_temp.reg(SUP, 'otro', null, G, 10.461234, -73.251234, null, null, null, null, false, pg_temp.val('sup_flex')::uuid);
  perform pg_temp.ok('05.15 el reenvío con el mismo id responde «repetido» y no agrega otra fila', pg_temp.err(r) = 'OK' and r -> 'repetido' = 'true'::jsonb
    and (select count(*) from campo.reporte_registro where reporte_id = pg_temp.val('sup_flex')::uuid) = 1, r::text);
  -- administrador
  r := pg_temp.reg(ADM, 'otro', '[{"origen": "archivo"}]', '{"xy_manual": true, "lat_registro": 10.45, "lon_registro": -73.24}', 10.465, -73.255, null);
  perform pg_temp.ok('05.16 el administrador también puede (archivo y XY digitado)', pg_temp.err(r) = 'OK', r::text);
end $p5$;

-- ===================== 06. Forma del bloque y dirección opcional =====================
do $p6$
declare r jsonb; v_id uuid; OP text := 'ztrf.op2@emdupar.gov.co'; SUP text := 'ztrf.sup@emdupar.gov.co';
begin
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"lat_registro": 10.46, "lon_registro": -73.25, "inventada": 1}');
  perform pg_temp.ok('06.01 una clave que no existe en el registro se rechaza y se nombra', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'inventada', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"lat_registro": 10.46}');
  perform pg_temp.ok('06.02 latitud sin longitud se rechaza', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"lat_registro": "10.46", "lon_registro": -73.25}');
  perform pg_temp.ok('06.03 una coordenada en texto se rechaza', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"precision_registro_m": 5}');
  perform pg_temp.ok('06.04 precisión sin ubicación se rechaza', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"xy_manual": "no"}');
  perform pg_temp.ok('06.05 xy_manual que no es sí o no se rechaza', pg_temp.err(r) = '22023', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', jsonb_build_object('direccion', repeat('x', 121)));
  perform pg_temp.ok('06.06 dirección de 121 caracteres se rechaza (tope 120)', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ '120', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', jsonb_build_object('barrio', repeat('x', 81)));
  perform pg_temp.ok('06.07 barrio de 81 caracteres se rechaza (tope 80)', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ '80', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', jsonb_build_object('referencia', repeat('x', 201)));
  perform pg_temp.ok('06.08 referencia de 201 caracteres se rechaza (tope 200)', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ '200', r::text);
  r := pg_temp.reg(OP, 'otro', '[{}]', jsonb_build_object('direccion', '  [PRUEBA ZTRF] CRA 9 # 12-30 ', 'barrio', 'Centro', 'referencia', 'Frente al parque', 'lat_registro', 10.46, 'lon_registro', -73.25));
  v_id := (r ->> '_id')::uuid;
  perform pg_temp.ok('06.09 Reportar anomalía con dirección, barrio y referencia (el operador también: es opcional, no es registro flexible)',
    pg_temp.err(r) = 'OK' and exists (select 1 from campo.reporte_registro where reporte_id = v_id and direccion = '[PRUEBA ZTRF] CRA 9 # 12-30' and barrio = 'Centro' and referencia = 'Frente al parque' and not xy_manual), r::text);
  perform pg_temp.ok('06.10 la lista y el detalle muestran la dirección',
    pg_temp.lista(SUP, v_id) ->> 'barrio' = 'Centro' and pg_temp.detalle(SUP, v_id) -> 'reporte' -> 'registro' ->> 'direccion' = '[PRUEBA ZTRF] CRA 9 # 12-30');
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"direccion": "   ", "lat_registro": 10.46, "lon_registro": -73.25}');
  perform pg_temp.ok('06.11 una dirección en blanco queda como vacía', pg_temp.err(r) = 'OK' and exists (select 1 from campo.reporte_registro where reporte_id = (r ->> '_id')::uuid and direccion is null), r::text);
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', '{"direccion": "CRA 1"}', 10.46, -73.25, 5, '123456', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('06.12 un formato con contrato obligatorio no lleva dirección (400)', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'no lleva dirección', r::text);
  r := pg_temp.reg(OP, 'instalacion_acometida', '[{"etiqueta": "fachada_predio"}]', '{"direccion": "[PRUEBA ZTRF] CLL 5 # 3-10", "barrio": "Primero de Mayo", "lat_registro": 10.46, "lon_registro": -73.25}',
                   10.46, -73.25, 5, null, 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('06.13 un formato con contrato opcional (instalación de acometida) sí lleva dirección, y su PDF la muestra', pg_temp.err(r) = 'OK'
    and pg_temp.cab(pg_temp.pdf(SUP, (r ->> '_id')::uuid), 'Barrio') = 'Primero de Mayo', r::text);
end $p6$;

-- ===================== 07. Entrada de Técnica (Reportar anomalía compartida) y el perfil dual =====================
do $p7$
declare r jsonb; PL text := 'ztrf.planta@emdupar.gov.co'; PL2 text := 'ztrf.planta2@emdupar.gov.co'; DU text := 'ztrf.dual@emdupar.gov.co';
  G jsonb := '{"lat_registro": 10.47, "lon_registro": -73.26, "precision_registro_m": 8, "direccion": "[PRUEBA ZTRF] Planta de tratamiento"}';
begin
  r := pg_temp.rpc(format('public.geoportal_campo_tec_formulario(%L)', PL));
  perform pg_temp.ok('07.01 el operador de planta con «Reportar anomalía» de Técnica abre el formulario (sin «supervisar»)',
    pg_temp.err(r) = 'OK' and r -> 'puede' -> 'supervisar' = 'false'::jsonb and r -> 'formularios' ? 'anomalia_compartida', left(r::text, 300));
  r := pg_temp.reg(PL, 'otro', '[{"origen": "camara"}]', G, 10.47, -73.26, 8, null, null, null, true);
  perform pg_temp.ok('07.02 el operador de planta registra desde Técnica, con la ubicación del dispositivo y la dirección', pg_temp.err(r) = 'OK' and r ->> 'area' = 'tecnica'
    and exists (select 1 from campo.reportes x join campo.reporte_registro rr on rr.reporte_id = x.id where x.id = (r ->> '_id')::uuid and x.area = 'tecnica' and not rr.xy_manual and rr.direccion is not null), r::text);
  r := pg_temp.reg(PL, 'otro', '[{}]', null, 10.47, -73.26, 8, null, null, null, true);
  perform pg_temp.ok('07.03 la entrada de Técnica de antes (sin p_registro) sigue funcionando', pg_temp.err(r) = 'OK' and r ->> 'area' = 'tecnica', r::text);
  r := pg_temp.reg(PL, 'otro', '[{"origen": "galeria"}]', G, 10.47, -73.26, 8, null, null, null, true);
  perform pg_temp.ok('07.04 desde Técnica no se adjuntan fotos (403)', pg_temp.err(r) = '42501' and pg_temp.msg(r) ~ 'Técnica', r::text);
  r := pg_temp.reg(PL2, 'otro', '[{}]', G, 10.47, -73.26, 8, null, null, null, true);
  perform pg_temp.ok('07.05 el operador de planta SIN «Reportar anomalía» sigue sin entrar (403)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.reg(DU, 'otro', '[{}]', G || '{"xy_manual": true}', 10.47, -73.26, null, null, null, null, true);
  perform pg_temp.ok('07.06 el dual, aunque es supervisor de Comercial, no digita el XY desde Técnica (403)', pg_temp.err(r) = '42501' and pg_temp.msg(r) ~ 'Técnica', r::text);
  r := pg_temp.reg(DU, 'otro', '[{"origen": "galeria"}]', '{"xy_manual": true, "lat_registro": 10.47, "lon_registro": -73.26}', 10.47, -73.26, null);
  perform pg_temp.ok('07.07 el dual, desde Comercial, sí puede (es supervisor de Comercial)', pg_temp.err(r) = 'OK' and r ->> 'area' is null, r::text);
  perform pg_temp.ok('07.08 el reporte de Técnica no queda marcado como de Comercial ni al revés',
    (select area from campo.reportes where id = (r ->> '_id')::uuid) is null);
end $p7$;

-- ===================== 08. El sello de un reporte NUEVO incluye su fila de reporte_registro =====================
do $p8$
declare s1 text; s2 text; v_id uuid := pg_temp.val('sup_pdf')::uuid; SUP text := 'ztrf.sup@emdupar.gov.co';
begin
  s1 := pg_temp.pdf(SUP, v_id) ->> 'sello';
  -- Solo en el ensayo (todo se deshace): se apaga el disparador de solo inserción para cambiar la fila y ver que el sello cambia
  alter table campo.reporte_registro disable trigger t_solo_agregar;
  update campo.reporte_registro set referencia = '[PRUEBA ZTRF] cambiada' where reporte_id = v_id;
  s2 := pg_temp.pdf(SUP, v_id) ->> 'sello';
  update campo.reporte_registro set referencia = null where reporte_id = v_id;
  alter table campo.reporte_registro enable trigger t_solo_agregar;
  perform pg_temp.ok('08.01 si cambia la fila de reporte_registro de un reporte nuevo, su sello cambia', s1 is not null and s2 is not null and s1 <> s2, s1 || ' / ' || s2);
  perform pg_temp.ok('08.02 y vuelve al mismo sello con la fila como estaba', pg_temp.pdf(SUP, v_id) ->> 'sello' = s1);
  perform pg_temp.ok('08.03 el sello de un reporte de antes sigue igual', pg_temp.pdf(SUP, pg_temp.val('viejo')::uuid) ->> 'sello' = pg_temp.val('sello_viejo'));
end $p8$;

-- ===================== 09. «Avisos y actividades derivadas»: conteo de pendientes y descarga auditada =====================
do $p9$
declare r jsonb; i jsonb; pg jsonb; v_o uuid := pg_temp.val('viejo')::uuid; v_d bigint; SUP text := 'ztrf.sup@emdupar.gov.co'; ADM text := 'ztrf.admin@emdupar.gov.co';
  OP text := 'ztrf.op@emdupar.gov.co'; n0 integer; p0 integer;
begin
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas(%L, ''{}''::jsonb, null)', SUP));
  n0 := (r ->> 'total')::int; p0 := (r ->> 'pendientes')::int;
  perform pg_temp.ok('09.01 la lista de derivadas trae «total» y «pendientes»', pg_temp.err(r) = 'OK' and n0 is not null and p0 is not null, left(r::text, 300));
  insert into campo.derivadas (origen_id, contrato, actividad) values (v_o, '991001', 'cambio_medidor'), (v_o, '991001', 'accesorios'), (v_o, '991001', 'reubicacion_cajilla') ;
  select min(id) into v_d from campo.derivadas where contrato = '991001';
  insert into campo.derivada_eventos (derivada_id, tipo_evento, motivo, autor) values (v_d, 'anulada', '[PRUEBA ZTRF] anulada en el ensayo', SUP);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas(%L, ''{"limite": 1}''::jsonb, null)', SUP));
  perform pg_temp.ok('09.02 total y pendientes cuentan todo, no solo la página (límite 1)', (r ->> 'total')::int = n0 + 3 and (r ->> 'pendientes')::int = p0 + 2
    and jsonb_array_length(r -> 'filas') = 1 and r ->> 'siguiente' is not null, left(r::text, 300));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas(%L, ''{"estado": "anulada", "contrato": "991001"}''::jsonb, null)', SUP));
  perform pg_temp.ok('09.03 con filtro de estado: el total sigue el filtro y los pendientes no (2 pendientes del contrato)',
    (r ->> 'total')::int = 1 and (r ->> 'pendientes')::int = 2, left(r::text, 300));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas(%L, ''{"estado": "inventado"}''::jsonb, null)', SUP));
  perform pg_temp.ok('09.04 un estado inventado se rechaza como antes', pg_temp.err(r) = '22023', r::text);
  -- descarga
  i := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{"contrato": "991001"}''::jsonb, ''xlsx'', false, null)', SUP));
  perform pg_temp.ok('09.05 el supervisor inicia la descarga: 3 filas y queda auditada', pg_temp.err(i) = 'OK' and (i ->> 'total')::int = 3
    and exists (select 1 from public.geoportal_auditoria where id = (i ->> 'descarga_id')::bigint and accion = 'campo_derivadas_descarga_iniciar' and email = SUP), i::text);
  pg := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_pagina(%L, %s, null, 2)', SUP, i ->> 'descarga_id'));
  perform pg_temp.ok('09.06 primera página de 2, sin los correos de las personas, sin datos de contacto y sin texto libre ni motivo de cierre', pg_temp.err(pg) = 'OK'
    and (pg ->> 'devueltos')::int = 2 and pg -> 'hay_mas' = 'true'::jsonb
    and pg::text !~ 'ztrf\.(op|sup)@' and pg::text !~ '"(cedula|telefono|celular|correo|texto|direccion_correcta|motivo)"' and pg::text !~ 'anulada en el ensayo', left(pg::text, 400));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_pagina(%L, %s, %s, 2)', SUP, i ->> 'descarga_id', pg ->> 'ultimo_id'));
  perform pg_temp.ok('09.07 la segunda página trae la que falta', (r ->> 'devueltos')::int = 1 and r -> 'hay_mas' = 'false'::jsonb, left(r::text, 200));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_pagina(%L, %s, null, 10)', ADM, i ->> 'descarga_id'));
  perform pg_temp.ok('09.08 otra persona no lee la descarga ajena (404)', pg_temp.err(r) = 'P0002', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_cerrar(%L, %s, 3, ''completa'', null)', SUP, i ->> 'descarga_id'));
  perform pg_temp.ok('09.09 se cierra y queda auditada', pg_temp.err(r) = 'OK' and r -> 'repetida' = 'false'::jsonb
    and exists (select 1 from public.geoportal_auditoria where accion = 'campo_derivadas_descarga_cerrar' and referencia = i ->> 'descarga_id'), r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_pagina(%L, %s, null, 10)', SUP, i ->> 'descarga_id'));
  perform pg_temp.ok('09.10 cerrada, ya no se leen páginas (409)', pg_temp.err(r) = '55000', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_cerrar(%L, %s, 3, ''completa'', null)', SUP, i ->> 'descarga_id'));
  perform pg_temp.ok('09.11 cerrar otra vez responde «repetida»', r -> 'repetida' = 'true'::jsonb, r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{}''::jsonb, ''xlsx'', true, null)', SUP));
  perform pg_temp.ok('09.12 el supervisor no puede pedir los correos (403)', pg_temp.err(r) = '42501', r::text);
  i := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{"contrato": "991001"}''::jsonb, ''csv'', true, null)', ADM));
  pg := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_pagina(%L, %s, null, 10)', ADM, i ->> 'descarga_id'));
  perform pg_temp.ok('09.13 el administrador que los pide sí recibe el correo de quien registró', pg::text ~ 'ztrf\.op@', left(pg::text, 300));
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{}''::jsonb, ''xlsx'', false, null)', OP));
  perform pg_temp.ok('09.14 el operador no descarga derivadas (403)', pg_temp.err(r) = '42501', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{"contrato": "000000"}''::jsonb, ''xlsx'', false, null)', SUP));
  perform pg_temp.ok('09.15 sin filas no se abre la descarga', pg_temp.err(r) = '22023' and pg_temp.msg(r) ~ 'No hay', r::text);
  r := pg_temp.rpc(format('public.geoportal_campo_derivadas_descarga_iniciar(%L, ''{}''::jsonb, ''pdf'', false, null)', SUP));
  perform pg_temp.ok('09.16 formato distinto de Excel o CSV se rechaza', pg_temp.err(r) = '22023', r::text);
end $p9$;

-- ===================== 10. Reglas de producción =====================
do $p10$
begin
  perform pg_temp.ok('10.01 ninguna función de campo con DELETE o UPDATE sin WHERE', (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0);
  perform pg_temp.ok('10.02 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
  perform pg_temp.ok('10.03 las RPC nuevas y cambiadas, solo para service_role',
    has_function_privilege('service_role', 'public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone,jsonb)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone,jsonb)', 'execute') and not has_function_privilege('anon', 'public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone,jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone,jsonb)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone,jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.geoportal_campo_derivadas_descarga_pagina(text,bigint,bigint,integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.geoportal_campo_derivadas_descarga_pagina(text,bigint,bigint,integer)', 'execute')
    and not has_function_privilege('service_role', 'campo.f_derivadas_filtradas(jsonb)', 'execute') and not has_function_privilege('service_role', 'campo.f_derivada_descarga(jsonb,boolean)', 'execute'));
  perform pg_temp.ok('10.04 las 4 funciones de permisos vivas no cambiaron', md5(pg_get_functiondef(to_regprocedure('public.geoportal_puede(text,text)'))) = '32f174a55b95788d3f8187b507303c2f' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_mis_permisos(text)'))) = '83166fe17be58da67bbdedaae429bedb' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)'))) = '01fda69a9d912067b8b4dc153ac7957e' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'))) = 'e5a90103b4a83440fd826f03266b7245');
  perform pg_temp.ok('10.05 la auditoría de crear no lleva coordenadas ni dirección, solo marcas',
    (select bool_and(detalle ? 'xy_manual' and detalle::text !~ '10\.4801|PRUEBA ZTRF\] CRA|Centro') from public.geoportal_auditoria
      where accion = 'campo_crear_reporte' and email in ('ztrf.sup@emdupar.gov.co', 'ztrf.op2@emdupar.gov.co') and detalle ? 'xy_manual'));
end $p10$;

-- ===================== REVERSA, dentro de esta misma transacción =====================
-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 90 — REVERSA
-- Devuelve crear_reporte y la entrada de Técnica a su firma y texto publicados, y la lista, el detalle, la descarga, los datos del PDF y la lista de derivadas a
-- su texto publicado; quita las 5 funciones nuevas (filtro y correos de las derivadas, y las 3 de la descarga auditada). La huella de campo vuelve a cce593806f59d3d27c34d7f2070cc5c1.
-- NADA SE BORRA: campo.reporte_registro y la columna campo.reporte_fotos.origen se conservan con sus datos (las funciones publicadas no las leen; el sello del
-- PDF de cualquier reporte vuelve a ser el de antes porque campo.reportes no cambió).
-- =====================================================================
do $rev$
declare r record; v_xy bigint; v_adj bigint;
begin
  for r in select * from (values ('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone,jsonb)', 'cfb2dbb022ae0f6e93989dcc6579e4d8'), ('public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone,jsonb)', '8ae23410abdba2194377b5ae19abc417'), ('public.geoportal_campo_listar_reportes(text,jsonb,text)', 'c6a74c023f37e5e0de7527b71d7cb369'), ('public.geoportal_campo_obtener_reporte(text,uuid,text)', 'bf9900e35a4051a00fec8b87cb34f153'), ('public.geoportal_campo_descarga_pagina(text,bigint,bigint,integer)', '0f4ce407e77abe49b1e6cc6132507f86'), ('public.geoportal_campo_pdf_datos(text,text,uuid,text)', '52d496ead7c6ea884b1c58b8c80541eb'), ('public.geoportal_campo_derivadas(text,jsonb,text)', '87250167e19a0b95ff7c40c351638a52')) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise', r.f;
    end if;
  end loop;
  select count(*) filter (where xy_manual) into v_xy from campo.reporte_registro;
  select count(*) into v_adj from campo.reporte_fotos where origen <> 'camara';
  raise notice 'Reversa del registro flexible: % reportes con XY digitado y % fotos adjuntadas conservan su marca en campo.reporte_registro y campo.reporte_fotos.origen (las pantallas de antes no la muestran)', v_xy, v_adj;
end $rev$;

-- DROP (por qué y alcance): las dos firmas con p_registro las creó este paquete y se reemplazan aquí mismo por las publicadas. Alcance: SOLO esas 2 firmas.
drop function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone, jsonb);
drop function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone, jsonb);

CREATE OR REPLACE FUNCTION public.geoportal_campo_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_origen text, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_orden_trabajo_id uuid DEFAULT NULL::uuid, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'storage', 'pg_temp'
AS $function$
declare
  v_email text; v_perfil text; v_origen text := coalesce(p_origen, ''); v_maxdesc integer := campo.f_param('max_descripcion')::integer;
  v_t campo.tipos_reporte%rowtype; v_s campo.subtipos_reporte%rowtype; v_sub bigint;
  v_desc text; v_contrato text; v_verif boolean; v_fuera boolean; v_lat numeric; v_lon numeric;
  v_max_fotos integer; v_min_fotos integer; v_max_bytes bigint := campo.f_param('max_bytes_foto')::bigint;
  v_fotos jsonb := coalesce(p_fotos, '[]'::jsonb); v_n integer; v_f jsonb; v_orden integer; v_ruta text; v_size bigint; v_mime text;
  v_id uuid := p_id; v_prev campo.reportes%rowtype; v_reg timestamptz; v_ref jsonb := '[]'::jsonb;
  v_resultado text; v_causal_id bigint; v_causal_cod text; v_exigir boolean; v_val jsonb; v_gen jsonb; v_sen jsonb;
  v_con_etiquetas boolean; v_etq text; v_etqs text[] := '{}'; v_falta text; v_num bigint; v_consecutivo text;
  v_fin timestamptz; v_max_h numeric;   -- pasada 14/11: hora de inicio
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);
  v_perfil := campo.f_perfil(v_email);
  if v_origen not in ('campo', 'escritorio') then perform campo.f_error('El origen debe ser campo o escritorio'); end if;
  if v_origen = 'escritorio' and v_perfil not in ('admin', 'supervisor') then
    raise exception 'Solo el supervisor o el administrador crean reportes desde el escritorio' using errcode = '42501';
  end if;

  -- Reenvío (red inestable): mismo identificador y mismo autor = misma respuesta, sin duplicar (y sin gastar cupo ni consecutivo)
  if v_id is not null then
    select * into v_prev from campo.reportes where id = v_id;
    if found then
      if v_prev.autor = v_email then
        return jsonb_build_object('id', v_prev.id, 'registrado_en', v_prev.registrado_en, 'repetido', true,
                                  'contrato_verificado', v_prev.contrato_verificado, 'aviso_zona', v_prev.fuera_de_zona, 'consecutivo', v_prev.consecutivo);
      end if;
      perform campo.f_error('Identificador de reporte no válido');
    end if;
  end if;

  -- Límite de ritmo (Paso B1): los reenvíos idempotentes de arriba NO consumen cupo; el cupo se verifica antes de validar el resto
  perform campo.f_cupo_reportes(v_email, v_perfil);

  -- Tipo, subtipo y texto
  select t.* into v_t from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where t.codigo = btrim(coalesce(p_tipo, '')) and t.activo and g.activo;
  if not found then perform campo.f_error('El tipo de reporte no existe o está desactivado'); end if;
  if nullif(btrim(coalesce(p_subtipo, '')), '') is not null then
    select s.* into v_s from campo.subtipos_reporte s where s.tipo_id = v_t.id and s.codigo = btrim(p_subtipo);
    if not found then perform campo.f_error('El subtipo no corresponde al tipo elegido'); end if;
    if not v_s.activo then perform campo.f_error('El subtipo está desactivado'); end if;
    v_sub := v_s.id;
  elsif v_t.exige_subtipo then
    perform campo.f_error('Elija un subtipo para este tipo de reporte');
  end if;
  v_desc := nullif(btrim(coalesce(p_descripcion, '')), '');
  if v_t.exige_texto and (v_desc is null or length(v_desc) < 3) then perform campo.f_error('Describa lo que encontró: este tipo de reporte lo exige'); end if;
  if length(coalesce(v_desc, '')) > v_maxdesc then perform campo.f_error(format('La descripción es demasiado larga (máximo %s caracteres)', replace(to_char(v_maxdesc, 'FM9G999'), ',', '.'))); end if;

  -- Resultado y causal (Paso D): solo en los tipos que lo llevan
  v_resultado := nullif(btrim(coalesce(p_resultado, '')), '');
  v_causal_cod := nullif(btrim(coalesce(p_causal, '')), '');
  if v_t.genera_resultado then
    if v_resultado is null then perform campo.f_error('Indique si la visita fue efectiva o inefectiva'); end if;
    if v_resultado not in ('efectivo', 'inefectivo') then perform campo.f_error('El resultado debe ser efectivo o inefectivo'); end if;
    if v_resultado = 'inefectivo' then
      if v_causal_cod is null then perform campo.f_error('Una visita inefectiva necesita la causal'); end if;
      select c.id into v_causal_id from campo.causales c
       where c.codigo = v_causal_cod and c.activo
         and (c.general or exists (select 1 from campo.causales_tipos ct where ct.causal_id = c.id and ct.tipo_id = v_t.id and ct.activo));
      if not found then perform campo.f_error('La causal no existe, está desactivada o no aplica a este formato'); end if;
    elsif v_causal_cod is not null then
      perform campo.f_error('La causal solo se informa cuando la visita es inefectiva');
    end if;
  elsif v_resultado is not null or v_causal_cod is not null then
    perform campo.f_error('Este tipo de reporte no lleva resultado ni causal');
  end if;
  v_exigir := v_resultado is distinct from 'inefectivo';

  -- Coordenada: dato numérico en rango; nunca se rechaza por la ubicación
  if p_lat is null or p_lon is null or p_lat = 'NaN'::numeric or p_lon = 'NaN'::numeric then perform campo.f_error('La coordenada no es válida'); end if;
  if p_lat < -90 or p_lat > 90 or p_lon < -180 or p_lon > 180 then perform campo.f_error('La coordenada está fuera de los rangos válidos de latitud y longitud'); end if;
  v_lat := round(p_lat, 6); v_lon := round(p_lon, 6);
  v_fuera := not (v_lat between campo.f_param('zona_lat_min') and campo.f_param('zona_lat_max')
              and v_lon between campo.f_param('zona_lon_min') and campo.f_param('zona_lon_max'));
  if p_precision_m is not null and (p_precision_m = 'NaN'::numeric or p_precision_m < 0 or p_precision_m > 100000) then perform campo.f_error('La precisión de la coordenada no es válida'); end if;
  if v_resultado = 'inefectivo' and v_origen = 'campo' and p_precision_m is null then
    perform campo.f_error('Una visita inefectiva necesita la ubicación tomada por el celular (con su precisión): active la ubicación e intente de nuevo');
  end if;

  -- Contrato: según el tipo es obligatorio, opcional o no se pide. Solo se confirma si existe; no se lee ningún otro dato
  v_contrato := nullif(btrim(coalesce(p_contrato, '')), '');
  if v_t.requiere_contrato = 'si' and v_contrato is null then perform campo.f_error('Este formato necesita el número de contrato'); end if;
  if v_t.requiere_contrato = 'no' and v_contrato is not null then perform campo.f_error('Este formato no lleva número de contrato'); end if;
  if v_contrato is not null then
    if v_contrato !~ '^[A-Za-z0-9-]{1,20}$' then perform campo.f_error('El contrato solo puede llevar letras, números y guiones (máximo 20)'); end if;
    if v_t.limite_ventana is not null then
      perform campo.f_cupo_tipo(v_email, v_perfil, v_t.id, v_t.limite_ventana, v_t.nombre);   -- Paso D: tope propio del tipo, en vez del general de contratos
    else
      perform campo.f_cupo_contratos(v_email, v_perfil);   -- Paso B1: tope de reportes con contrato (impide enumerar contratos); antes de consultar si existe
    end if;
    perform campo.f_cupo_contratos_falsos(v_email, v_perfil);   -- Paso B1: tope de contratos NO verificados en 24 h; también antes de consultar si existe
    v_verif := exists (select 1 from public.predios_comercial pc where pc.cod_usuario = v_contrato);
  end if;

  -- Campos propios (Paso D): validados contra la definición del tipo; los sensibles se separan
  v_val := campo.f_validar_datos(v_t.id, p_datos, v_exigir);
  v_gen := nullif(v_val -> 'general', '{}'::jsonb);
  v_sen := nullif(v_val -> 'sensibles', '{}'::jsonb);

  -- Orden de trabajo (Paso D): gancho para SCRR; hoy solo se guarda
  if p_orden_trabajo_id is not null then perform campo.f_validar_orden_trabajo(p_orden_trabajo_id, v_email, v_t.id); end if;

  -- Fotos: cantidad (mínimo y máximo del tipo), orden, etiqueta, ruta propia y objeto realmente subido (tamaño y tipo leídos de Storage)
  v_max_fotos := coalesce(v_t.fotos_max, campo.f_param('max_fotos')::integer);
  v_min_fotos := case when v_origen <> 'campo' then 0 when v_exigir then coalesce(v_t.fotos_min, 1) else least(coalesce(v_t.fotos_min, 1), 1) end;
  if jsonb_typeof(v_fotos) <> 'array' then perform campo.f_error('Las fotos no vienen en el formato esperado'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n < v_min_fotos then
    if v_min_fotos = 1 then perform campo.f_error('Un reporte de campo necesita al menos una foto'); end if;
    perform campo.f_error(format('Este formato necesita al menos %s fotos (lleva %s)', v_min_fotos, v_n));
  end if;
  if v_n > v_max_fotos then perform campo.f_error(format('Máximo %s fotos por reporte', v_max_fotos)); end if;
  if v_n > 0 and v_id is null then perform campo.f_error('Para adjuntar fotos primero debe reservarse el reporte (preparar la subida)'); end if;
  if v_n > 0 and (select count(distinct (e ->> 'orden')::integer) <> v_n or min((e ->> 'orden')::integer) <> 1 or max((e ->> 'orden')::integer) <> v_n
                    from jsonb_array_elements(v_fotos) e) then
    perform campo.f_error('El orden de las fotos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  v_con_etiquetas := exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo);
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'orden')::integer loop
    v_orden := (v_f ->> 'orden')::integer;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^reportes/[0-9]{4}-[0-9]{2}/' || v_id::text || '/' || v_orden || '\.jpg$') then
      perform campo.f_error(format('La ruta de la foto %s no corresponde a este reporte', v_orden));
    end if;
    v_etq := nullif(btrim(coalesce(v_f ->> 'etiqueta', '')), '');
    if v_con_etiquetas then
      if v_etq is null then perform campo.f_error(format('Indique qué muestra la foto %s', v_orden)); end if;
      if v_etq <> 'adicional' then
        if not exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.codigo = v_etq and tf.activo) then
          perform campo.f_error(format('La etiqueta de la foto %s no existe en este formato', v_orden));
        end if;
        if v_etq = any (v_etqs) then perform campo.f_error(format('Hay dos fotos con la misma etiqueta (foto %s)', v_orden)); end if;
      end if;
      v_etqs := v_etqs || v_etq;
    elsif v_etq is not null then
      perform campo.f_error('Este tipo de reporte no usa etiquetas de foto');
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime
      from storage.objects o where o.bucket_id = 'campo-fotos' and o.name = v_ruta;
    if not found then perform campo.f_error(format('No se encontró la foto %s: súbala de nuevo', v_orden)); end if;
    if coalesce(v_size, 0) <= 0 then perform campo.f_error(format('La foto %s está vacía', v_orden)); end if;
    if v_size > v_max_bytes then perform campo.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_orden, v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform campo.f_error(format('La foto %s debe ser JPEG', v_orden)); end if;
    v_ref := v_ref || jsonb_build_object('orden', v_orden, 'ruta', v_ruta, 'tamano', v_size, 'mime', v_mime, 'etiqueta', v_etq);
  end loop;
  if v_con_etiquetas and v_exigir and v_origen = 'campo' then
    select tf.nombre into v_falta from campo.tipo_fotos tf
     where tf.tipo_id = v_t.id and tf.activo and tf.obligatoria and tf.codigo <> all (v_etqs) order by tf.orden, tf.id limit 1;
    if v_falta is not null then perform campo.f_error(format('Falta la foto obligatoria: «%s»', v_falta)); end if;
  end if;
  -- Visita inefectiva en campo: al menos una foto de la fachada o del predio (las etiquetas con soporte_inefectiva del tipo)
  if v_resultado = 'inefectivo' and v_origen = 'campo' and exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo and tf.soporte_inefectiva)
     and not exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo and tf.soporte_inefectiva and tf.codigo = any (v_etqs)) then
    perform campo.f_error('Una visita inefectiva necesita la foto de la fachada o del predio');
  end if;
  -- Pasada 14/11: hora de inicio = la del celular al abrir el formulario. Fin = la hora del servidor al registrar (v_fin: la MISMA que se guarda en registrado_en).
  v_fin := clock_timestamp();
  if p_inicio_dispositivo is not null then
    v_max_h := campo.f_param('max_horas_inicio');
    if p_inicio_dispositivo > v_fin + interval '2 minutes' then
      perform campo.f_error('La hora de su celular está adelantada. Corríjala y vuelva a enviar: lo escrito y las fotos no se pierden.');
    end if;
    if p_inicio_dispositivo < v_fin - v_max_h * interval '1 hour' then
      perform campo.f_error(format('Este formulario se abrió hace más de %s horas. Revise la hora de su celular o ábralo de nuevo.', trim_scale(v_max_h)));
    end if;
  end if;
  if v_id is null then v_id := gen_random_uuid(); end if;

  -- Inserción (una sola transacción; una carrera por el mismo id se resuelve como «repetido»).
  -- El consecutivo se toma AQUÍ, al final y dentro del mismo bloque: si la inserción falla, el número vuelve al contador (sin huecos).
  begin
    v_num := campo.f_siguiente_consecutivo(v_t.id);
    if v_num is not null then v_consecutivo := campo.f_texto_consecutivo(v_t.prefijo_consecutivo, v_num); end if;
    insert into campo.reportes (id, tipo_id, subtipo_id, descripcion, contrato, contrato_verificado, lat, lon, precision_m, riesgo_inmediato, origen, fuera_de_zona, autor,
                                datos, resultado, causal_id, consecutivo_num, consecutivo, orden_trabajo_id, registrado_en, inicio_en, inicio_origen)
    values (v_id, v_t.id, v_sub, v_desc, v_contrato, v_verif, v_lat, v_lon, p_precision_m, coalesce(p_riesgo_inmediato, false), v_origen, v_fuera, v_email,
            v_gen, v_resultado, v_causal_id, v_num, v_consecutivo, p_orden_trabajo_id, v_fin, p_inicio_dispositivo, case when p_inicio_dispositivo is not null then 'dispositivo' end)
    returning registrado_en into v_reg;
    insert into campo.reporte_fotos (reporte_id, orden, ruta_storage, tamano_bytes, tipo_mime, etiqueta)
      select v_id, (x ->> 'orden')::smallint, x ->> 'ruta', (x ->> 'tamano')::integer, x ->> 'mime', x ->> 'etiqueta' from jsonb_array_elements(v_ref) x;
    if v_sen is not null then insert into campo.reporte_datos_sensibles (reporte_id, datos) values (v_id, v_sen); end if;
  exception when unique_violation then
    select * into v_prev from campo.reportes where id = v_id;
    if found and v_prev.autor = v_email then
      return jsonb_build_object('id', v_prev.id, 'registrado_en', v_prev.registrado_en, 'repetido', true,
                                'contrato_verificado', v_prev.contrato_verificado, 'aviso_zona', v_prev.fuera_de_zona, 'consecutivo', v_prev.consecutivo);
    end if;
    perform campo.f_error('Una de las fotos ya está usada en otro reporte');
  end;

  -- Auditoría: nunca los valores de los campos propios, solo cuántos y si hubo sensibles
  perform campo.f_auditar(v_email, 'campo_crear_reporte', v_id::text,
    jsonb_build_object('tipo', v_t.codigo, 'subtipo', v_s.codigo, 'origen', v_origen, 'fotos', v_n, 'riesgo_inmediato', coalesce(p_riesgo_inmediato, false),
                       'fuera_de_zona', v_fuera, 'contrato_informado', v_contrato is not null, 'contrato_verificado', v_verif,
                       'consecutivo', v_consecutivo, 'resultado', v_resultado, 'causal', case when v_causal_id is not null then v_causal_cod end, 'con_inicio', p_inicio_dispositivo is not null,
                       'campos', (select count(*) from jsonb_object_keys(coalesce(v_gen, '{}'::jsonb))), 'campos_sensibles', v_sen is not null,
                       'orden_trabajo', p_orden_trabajo_id is not null), p_ip);
  return jsonb_build_object('id', v_id, 'registrado_en', v_reg, 'repetido', false, 'contrato_verificado', v_verif, 'aviso_zona', v_fuera, 'consecutivo', v_consecutivo);
end $function$;
revoke all on function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone)
  to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_campo_tec_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'tecnica', 'pg_temp'
AS $function$
declare v jsonb;
begin
  if p_tipo is null then raise exception 'Falta el tipo de reporte' using errcode = '22023'; end if;
  perform campo.f_tecnica_entrar(p_solicitante, p_tipo);
  v := public.geoportal_campo_crear_reporte(p_solicitante, p_id, p_tipo, p_subtipo, p_descripcion, p_contrato, p_lat, p_lon, p_precision_m, p_riesgo_inmediato, 'campo', p_fotos,
                                            p_ip, p_datos, p_resultado, p_causal, null, p_inicio_dispositivo);
  perform set_config('geoportal.via_tecnica', '', true);
  return v || jsonb_build_object('area', 'tecnica');
end $function$;
revoke all on function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone)
  from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone)
  to service_role;

CREATE OR REPLACE FUNCTION public.geoportal_campo_listar_reportes(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v_f jsonb := coalesce(p_filtros, '{}'::jsonb); v_ids uuid[]; v_total integer; v_eps numeric; v_lim integer; v_cur bigint;
        v_rows jsonb; v_min bigint; v_mas boolean;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  v_eps := campo.f_param('distancia_duplicados_m');
  v_lim := least(greatest(coalesce(nullif(v_f ->> 'limite', '')::integer, 1000), 1), 5000);
  v_cur := nullif(v_f ->> 'cursor', '')::bigint;
  select coalesce(array_agg(x.id), '{}'::uuid[]), count(*)::integer into v_ids, v_total from campo.f_filtrar(v_f) x;
  with pag as (
    select x.*, row_number() over (order by x.seq desc) as rn
      from campo.f_filtrar(v_f) x where v_cur is null or x.seq < v_cur order by x.seq desc limit v_lim + 1
  ), cl as (select * from campo.f_grupos_cercanos(v_eps, v_ids)),
  fila as (
    select p.*, t.codigo as tipo_codigo, t.nombre as tipo_nombre, g.codigo as grupo_codigo, g.nombre as grupo_nombre,
           s.codigo as sub_codigo, s.nombre as sub_nombre, cl.grupo_id as grupo_dup, cl.tamano as tam_dup,
           ca.codigo as causal_codigo, ca.nombre as causal_nombre
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
     where p.rn <= v_lim
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'seq', f.seq,
           'tipo', jsonb_build_object('codigo', f.tipo_codigo, 'nombre', f.tipo_nombre),
           'grupo', jsonb_build_object('codigo', f.grupo_codigo, 'nombre', f.grupo_nombre),
           'subtipo', case when f.sub_codigo is null then null else jsonb_build_object('codigo', f.sub_codigo, 'nombre', f.sub_nombre) end,
           'descripcion', f.descripcion, 'contrato', f.contrato, 'contrato_verificado', f.contrato_verificado,
           'lat', f.lat, 'lon', f.lon, 'precision_m', f.precision_m, 'riesgo_inmediato', f.riesgo_inmediato, 'origen', f.origen,
           'fuera_de_zona', f.fuera_de_zona, 'autor', f.autor, 'registrado_en', f.registrado_en,
           'estado', f.estado, 'estado_desde', f.estado_desde, 'oculto', f.oculto, 'reporte_original_id', f.reporte_original_id,
           'grupo_duplicados', f.grupo_dup, 'tamano_grupo', f.tam_dup, 'n_fotos', f.n_fotos)
           -- Paso D
           || jsonb_build_object(
           'consecutivo', f.consecutivo, 'resultado', f.resultado,
           'causal', case when f.causal_codigo is null then null else jsonb_build_object('codigo', f.causal_codigo, 'nombre', f.causal_nombre) end,
           'orden_trabajo_id', f.orden_trabajo_id, 'datos', coalesce(f.datos, '{}'::jsonb), 'tiene_datos_sensibles', f.tiene_datos_sensibles,
           'inicio_en', f.inicio_en, 'inicio_origen', f.inicio_origen) order by f.seq desc), '[]'::jsonb),
         min(f.seq), (select count(*) from pag) > v_lim
    into v_rows, v_min, v_mas from fila f;
  return jsonb_build_object('reportes', v_rows, 'total', v_total, 'siguiente', case when v_mas then v_min end, 'distancia_duplicados_m', v_eps);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_obtener_reporte(p_solicitante text, p_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v campo.v_reportes_estado%rowtype; v_eps numeric := campo.f_param('distancia_duplicados_m');
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select * into v from campo.v_reportes_estado where id = p_id;
  if not found then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  -- Paso C: consultar el detalle (muestra autor y contrato) queda auditado
  perform campo.f_auditar(v_email, 'campo_ver_detalle', p_id::text, '{}'::jsonb, p_ip);
  return (
    select jsonb_build_object(
      'reporte', jsonb_build_object(
        'id', v.id, 'seq', v.seq,
        'tipo', jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre), 'grupo', jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre),
        'subtipo', case when s.id is null then null else jsonb_build_object('codigo', s.codigo, 'nombre', s.nombre) end,
        'descripcion', v.descripcion, 'contrato', v.contrato, 'contrato_verificado', v.contrato_verificado, 'lat', v.lat, 'lon', v.lon,
        'precision_m', v.precision_m, 'riesgo_inmediato', v.riesgo_inmediato, 'origen', v.origen, 'fuera_de_zona', v.fuera_de_zona,
        'autor', v.autor, 'registrado_en', v.registrado_en, 'estado', v.estado, 'estado_desde', v.estado_desde, 'oculto', v.oculto,
        'reporte_original_id', v.reporte_original_id)
        -- Paso D
        || jsonb_build_object(
        'consecutivo', v.consecutivo, 'resultado', v.resultado,
        'causal', (select jsonb_build_object('codigo', ca.codigo, 'nombre', ca.nombre) from campo.causales ca where ca.id = v.causal_id),
        'orden_trabajo_id', v.orden_trabajo_id, 'datos', coalesce(v.datos, '{}'::jsonb), 'tiene_datos_sensibles', v.tiene_datos_sensibles,
        'inicio_en', v.inicio_en, 'inicio_origen', v.inicio_origen),
      'campos', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'tipo_dato', c.tipo_dato, 'unidad', c.unidad,
                                  'opciones', (select jsonb_agg(jsonb_build_object('codigo', o ->> 'codigo', 'nombre', o ->> 'nombre')) from jsonb_array_elements(c.opciones) o),
                                  'sensible', c.sensible, 'activo', c.activo)) order by c.orden, c.id)
                           from campo.tipo_campos c where c.tipo_id = v.tipo_id), '[]'::jsonb),
      'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', f.orden, 'tamano_bytes', f.tamano_bytes, 'tipo_mime', f.tipo_mime, 'registrada_en', f.registrada_en,
                                  'etiqueta', f.etiqueta,
                                  'etiqueta_nombre', case when f.etiqueta = 'adicional' then 'Adicional'
                                                          else (select tf.nombre from campo.tipo_fotos tf where tf.tipo_id = v.tipo_id and tf.codigo = f.etiqueta) end) order by f.orden)
                           from campo.reporte_fotos f where f.reporte_id = v.id), '[]'::jsonb),
      'eventos', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'tipo_evento', e.tipo_evento, 'estado_nuevo', e.estado_nuevo,
                                  'reporte_original_id', e.reporte_original_id, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en) order by e.id)
                           from campo.reporte_eventos e where e.reporte_id = v.id), '[]'::jsonb),
      'cercanos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'distancia_m', c.d, 'registrado_en', c.registrado_en, 'estado', c.estado) order by c.d)
                              from (select o.id, round(st_distance(o.geom::geography, v.geom::geography)::numeric, 1) as d, o.registrado_en, o.estado
                                      from campo.v_reportes_estado o
                                     where o.id <> v.id and o.tipo_id = v.tipo_id and not o.oculto and st_dwithin(o.geom::geography, v.geom::geography, v_eps::double precision)
                                     order by st_distance(o.geom::geography, v.geom::geography) limit 20) c), '[]'::jsonb),
      'distancia_duplicados_m', v_eps)
    from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id left join campo.subtipos_reporte s on s.id = v.subtipo_id
   where t.id = v.tipo_id);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_descarga_pagina(p_solicitante text, p_descarga_id bigint, p_despues_de bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; a record; v_f jsonb; v_corte bigint; v_autor boolean; v_lim integer := least(greatest(coalesce(p_limite, 5000), 1), 5000); v_eps numeric := campo.f_param('distancia_duplicados_m');
        v_ids uuid[]; v_rows jsonb; v_min bigint; v_mas boolean;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select x.id, x.email, x.detalle into a from public.geoportal_auditoria x where x.id = p_descarga_id and x.accion = 'campo_descarga_iniciar';
  if not found or a.email <> v_email then perform campo.f_error('La descarga no existe', 'P0002'); end if;
  if exists (select 1 from public.geoportal_auditoria x where x.accion = 'campo_descarga_cerrar' and x.referencia = p_descarga_id::text) then perform campo.f_error('La descarga ya se cerró', '55000'); end if;
  v_f := a.detalle -> 'filtros'; v_corte := (a.detalle ->> 'hasta_seq')::bigint; v_autor := coalesce((a.detalle ->> 'incluir_autor')::boolean, false);
  select coalesce(array_agg(x.id), '{}'::uuid[]) into v_ids from campo.f_filtrar(v_f) x where x.seq <= v_corte;
  with pag as (
    select x.*, row_number() over (order by x.seq desc) as rn from campo.f_filtrar(v_f) x where x.seq <= v_corte and (p_despues_de is null or x.seq < p_despues_de) order by x.seq desc limit v_lim + 1
  ), cl as (select * from campo.f_grupos_cercanos(v_eps, v_ids)),
  fila as (
    select p.*, t.codigo as tipo_codigo, t.nombre as tipo_nombre, g.nombre as grupo_nombre, s.nombre as sub_nombre, es.nombre as estado_nombre, ca.nombre as causal_nombre,
           cl.grupo_id as grupo_dup, cl.tamano as tam_dup
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join campo.estados_reporte es on es.codigo = p.estado left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
     where p.rn <= v_lim
  )
  select coalesce(jsonb_agg(
           jsonb_build_object('seq', f.seq, 'id', f.id, 'registrado_local', to_char(f.registrado_en at time zone 'America/Bogota', 'YYYY-MM-DD"T"HH24:MI:SS'),
             'tipo_codigo', f.tipo_codigo, 'tipo_nombre', f.tipo_nombre, 'grupo_nombre', f.grupo_nombre, 'subtipo_nombre', f.sub_nombre,
             'consecutivo', f.consecutivo, 'resultado', f.resultado, 'causal_nombre', f.causal_nombre,
             'estado', f.estado, 'estado_nombre', f.estado_nombre, 'oculto', f.oculto, 'riesgo_inmediato', f.riesgo_inmediato, 'fuera_de_zona', f.fuera_de_zona,
             'contrato', f.contrato, 'contrato_verificado', f.contrato_verificado, 'descripcion', f.descripcion,
             'lat', f.lat, 'lon', f.lon, 'precision_m', f.precision_m, 'origen', f.origen, 'n_fotos', f.n_fotos,
             'grupo_duplicados', f.grupo_dup, 'tamano_grupo', f.tam_dup, 'reporte_original_id', f.reporte_original_id,
             'orden_trabajo_id', f.orden_trabajo_id, 'datos', coalesce(f.datos, '{}'::jsonb),
             'inicio_local', to_char(f.inicio_en at time zone 'America/Bogota', 'YYYY-MM-DD"T"HH24:MI:SS'), 'inicio_origen', f.inicio_origen,
             'duracion_min', round(extract(epoch from (f.registrado_en - f.inicio_en)) / 60.0, 1))
           || case when v_autor then jsonb_build_object('autor', f.autor) else '{}'::jsonb end order by f.seq desc), '[]'::jsonb),
         min(f.seq), (select count(*) from pag) > v_lim
    into v_rows, v_min, v_mas from fila f;
  return jsonb_build_object('registros', v_rows, 'devueltos', jsonb_array_length(v_rows), 'ultimo_seq', v_min, 'hay_mas', v_mas);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_pdf_datos(p_solicitante text, p_esquema text, p_registro_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'acta', 'pg_temp'
AS $function$
declare v_email text; v_r campo.reportes; v_a acta.actas; v_t campo.tipos_reporte; v_d campo.formularios_documento; v_form text; v_sen jsonb; v_secc jsonb; v_cab jsonb;
        v_fotos jsonb; v_firmas jsonb; v_nombre text; v_sello text; v_doc jsonb; v_op text; v_ver integer := 1;
begin
  v_email := campo.f_autorizar_documento(p_solicitante, p_esquema, p_registro_id);
  if p_esquema = 'campo' then
    select * into v_r from campo.reportes where id = p_registro_id;
    select * into v_t from campo.tipos_reporte where id = v_r.tipo_id;
    v_form := 'tipo:' || v_t.codigo;
  else
    select * into v_a from acta.actas where id = p_registro_id;
    v_form := 'acta'; v_ver := v_a.version;
  end if;
  v_d := campo.f_documento_de(v_form);
  if v_d.formulario is null or not v_d.lleva_pdf then perform campo.f_error('Ese formulario no lleva PDF'); end if;
  -- Firmas: las de este registro («esta»). En una corrección del acta (versión 2 en adelante) va la del operario que corrige más las tres del acta original («original»).
  select coalesce(jsonb_agg(jsonb_build_object('rol', x.rol, 'estado', x.estado, 'nombre', x.nombre, 'imagen', encode(x.imagen, 'base64'), 'huella', x.huella, 'de', x.de)
                            order by x.o1, array_position(array['operario', 'usuario', 'testigo'], x.rol)), '[]'::jsonb)
    into v_firmas
    from (select f.*, 'esta'::text as de, case when v_ver > 1 then 2 else 1 end as o1
            from campo.firmas f where f.esquema = p_esquema and f.registro_id = p_registro_id and f.estado <> 'quitada' and (v_ver = 1 or f.rol = 'operario')
          union all
          select f.*, 'original'::text, 1 from campo.firmas f
           where v_ver > 1 and f.esquema = 'acta' and f.estado <> 'quitada'
             and f.registro_id = (select o.id from acta.actas o where o.acta_raiz_id = v_a.acta_raiz_id and o.version = 1)) x;
  select coalesce(nullif(btrim(lb.nombre), ''), split_part(coalesce(v_r.autor, v_a.autor), '@', 1)) into v_op from public.geoportal_lista_blanca lb where lb.email = coalesce(v_r.autor, v_a.autor);
  if p_esquema = 'campo' then
    select d.datos into v_sen from campo.reporte_datos_sensibles d where d.reporte_id = v_r.id;
    v_cab := jsonb_build_array(jsonb_build_array('Formato', v_t.nombre), jsonb_build_array('Consecutivo', v_r.consecutivo), jsonb_build_array('Contrato', coalesce(v_r.contrato, '—')),
               jsonb_build_array('Resultado', case v_r.resultado when 'efectivo' then 'Efectivo (se realizó la actividad)' when 'inefectivo' then 'No efectivo (no se realizó)' else coalesce(v_r.resultado, '—') end
                 || coalesce(' · Causal: ' || (select c.nombre from campo.causales c where c.id = v_r.causal_id), '')), jsonb_build_array('Ubicación', v_r.lat || ', ' || v_r.lon || coalesce(' (precisión ' || v_r.precision_m || ' m)', '')));
    with c as (
      select c.seccion, c.orden, c.nombre, c.tipo_dato, c.opciones, coalesce(v_r.datos -> c.codigo, v_sen -> c.codigo) as v
        from campo.tipo_campos c where c.tipo_id = v_t.id and (v_r.datos ? c.codigo or coalesce(v_sen, '{}'::jsonb) ? c.codigo)
    ), f as (
      select c.seccion, c.orden, jsonb_build_array(c.nombre,
               case c.tipo_dato when 'si_no' then case when c.v = 'true'::jsonb then 'Sí' when c.v = 'false'::jsonb then 'No' else c.v #>> '{}' end
                                when 'opcion' then coalesce((select o ->> 'nombre' from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = c.v #>> '{}'), c.v #>> '{}')
                                when 'opciones' then (select string_agg(coalesce((select o ->> 'nombre' from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = x), x), '; ')
                                                        from jsonb_array_elements_text(case when jsonb_typeof(c.v) = 'array' then c.v else '[]'::jsonb end) x)
                                when 'dia_hora' then replace(c.v #>> '{}', 'T', ' ')
                                else c.v #>> '{}' end) as par
        from c
    )
    select jsonb_agg(jsonb_build_object('titulo', s.seccion, 'campos', s.campos) order by s.o) into v_secc
      from (select coalesce(f.seccion, 'Datos') as seccion, min(f.orden) as o, jsonb_agg(f.par order by f.orden) as campos from f group by coalesce(f.seccion, 'Datos')) s;
    select coalesce(jsonb_agg(jsonb_build_object('bucket', 'campo-fotos', 'ruta', p.ruta_storage, 'etiqueta', coalesce(p.etiqueta, 'Foto ' || p.orden), 'bytes', p.tamano_bytes) order by p.orden), '[]'::jsonb)
      into v_fotos from campo.reporte_fotos p where p.reporte_id = v_r.id;
    v_nombre := campo.f_nombre_pdf(v_r.registrado_en, v_d.sigla, replace(v_r.consecutivo, '-', ''), 1);
    v_sello := encode(sha256(convert_to(to_jsonb(v_r)::text || coalesce(v_sen::text, '') || coalesce((select string_agg(f.huella, ',' order by f.rol) from campo.firmas f
                 where f.esquema = 'campo' and f.registro_id = v_r.id and f.estado = 'firmo'), ''), 'UTF8')), 'hex');
  else
    v_cab := jsonb_build_array(jsonb_build_array('Consecutivo', v_a.consecutivo || case when v_a.version > 1 then ' (versión ' || v_a.version || ')' else '' end),
               jsonb_build_array('Acta física', coalesce(v_a.numero_acta_fisica, 'pendiente') || coalesce(' del ' || to_char(v_a.fecha_acta_fisica, 'YYYY-MM-DD'), '')),
               jsonb_build_array('Contrato', coalesce(v_a.contrato, '—')), jsonb_build_array('Dirección', coalesce(v_a.direccion, '—')), jsonb_build_array('Barrio', coalesce(v_a.barrio, '—')),
               jsonb_build_array('Ubicación', v_a.lat || ', ' || v_a.lon || coalesce(' (precisión ' || v_a.precision_m || ' m)', '')));
    v_secc := jsonb_build_array(
      jsonb_build_object('titulo', 'Medidor', 'campos', jsonb_build_array(
        jsonb_build_array('Tiene medidor', case when v_a.tiene_medidor then 'Sí' when v_a.tiene_medidor = false then 'No' else '—' end),
        jsonb_build_array('Serie', coalesce(v_a.medidor_serie, '—')), jsonb_build_array('Marca', coalesce(v_a.marca, '—')), jsonb_build_array('Lectura (m³)', coalesce(v_a.lectura_m3::text, '—')),
        jsonb_build_array('Serie de los sellos', coalesce(v_a.serie_sellos, '—')))),
      jsonb_build_object('titulo', 'Hallazgos', 'campos', jsonb_build_array(
        jsonb_build_array('Sin irregularidad', case when v_a.sin_irregularidad then 'Sí' else 'No' end),
        jsonb_build_array('Hallazgos', coalesce((select string_agg(coalesce(h.texto_otro, th.nombre), '; ') from acta.acta_hallazgos h join acta.tipos_hallazgo th on th.id = h.tipo_hallazgo_id where h.acta_id = v_a.id), '—')),
        jsonb_build_array('Descripción', coalesce(v_a.descripcion_hallazgos, '—')),
        jsonb_build_array('Acciones', coalesce((select string_agg(ac.nombre, '; ') from acta.acta_acciones x join acta.acciones_correctivas ac on ac.id = x.accion_id where x.acta_id = v_a.id), '—')))),
      jsonb_build_object('titulo', 'Quién atendió', 'campos', jsonb_build_array(
        jsonb_build_array('Nadie atendió', case when v_a.nadie_atendio then 'Sí' else 'No' end),
        jsonb_build_array('Atendió', coalesce((select p.nombre || coalesce(' (' || coalesce(ca.nombre, p.calidad_texto) || ')', '') from acta.acta_personas p left join acta.calidades_atendiente ca on ca.id = p.calidad_id
                                                where p.acta_id = v_a.id and p.rol = 'atendiente' limit 1), '—')),
        jsonb_build_array('Testigo', coalesce((select p.nombre from acta.acta_personas p where p.acta_id = v_a.id and p.rol = 'testigo' limit 1), '—')),
        jsonb_build_array('Observaciones', coalesce(v_a.observaciones, '—')))));
    select coalesce(jsonb_agg(jsonb_build_object('bucket', 'acta-evidencias', 'ruta', p.ruta_storage, 'etiqueta', coalesce(tf.nombre, 'Foto ' || p.orden), 'bytes', p.tamano_bytes) order by p.orden), '[]'::jsonb)
      into v_fotos from acta.acta_fotos p left join acta.tipos_foto tf on tf.id = p.tipo_foto_id where p.acta_id = v_a.id;
    v_nombre := campo.f_nombre_pdf(v_a.registrado_en, v_d.sigla, v_a.consecutivo, v_a.version);
    v_sello := encode(sha256(convert_to(coalesce((select s.sello_sha256 from acta.acta_sellos s where s.acta_id = v_a.id), '') || coalesce((select string_agg(x ->> 'huella', ',' order by x ->> 'de', x ->> 'rol')
                 from jsonb_array_elements(v_firmas) x where x ->> 'estado' = 'firmo'), ''), 'UTF8')), 'hex');
  end if;
  select jsonb_build_object('nombre', d.nombre, 'ruta', d.ruta, 'sha256', d.sha256, 'bytes', d.bytes, 'version', d.version) into v_doc
    from campo.documentos_pdf d where d.esquema = p_esquema and d.registro_id = p_registro_id;
  return jsonb_build_object('esquema', p_esquema, 'registro_id', p_registro_id, 'formulario', v_form, 'version', v_ver, 'nombre', v_nombre,
    'ruta', p_esquema || '/' || to_char(coalesce(v_r.registrado_en, v_a.registrado_en) at time zone 'America/Bogota', 'YYYY-MM') || '/' || p_registro_id || '/' || v_nombre,
    'titulo', case when p_esquema = 'acta' then 'ACTA DE INSPECCIÓN TÉCNICA · REPORTAR POSIBLE PÉRDIDA' else upper(v_t.nombre) end,
    'consecutivo', coalesce(v_r.consecutivo, v_a.consecutivo),
    'registrado_en', to_char(coalesce(v_r.registrado_en, v_a.registrado_en) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
    'inicio_en', to_char(coalesce(v_r.inicio_en, v_a.inicio_en) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
    'fin_en', to_char(coalesce(v_r.registrado_en, v_a.fin_en) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
    'operario', jsonb_build_object('nombre', v_op, 'correo', coalesce(v_r.autor, v_a.autor)),
    'cabecera', v_cab, 'secciones', coalesce(v_secc, '[]'::jsonb), 'fotos', v_fotos, 'firmas', v_firmas, 'sello', v_sello, 'documento', v_doc);
end $function$;

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

-- DROP (por qué y alcance): las 5 funciones las creó este paquete; con la lista de derivadas ya devuelta a su texto publicado, nadie las usa. Alcance: SOLO esas 5 firmas;
-- no toca tablas, datos ni otras funciones.
drop function public.geoportal_campo_derivadas_descarga_cerrar(text, bigint, integer, text, text);
drop function public.geoportal_campo_derivadas_descarga_pagina(text, bigint, bigint, integer);
drop function public.geoportal_campo_derivadas_descarga_iniciar(text, jsonb, text, boolean, text);
drop function campo.f_derivada_descarga(jsonb, boolean);
drop function campo.f_derivadas_filtradas(jsonb);


-- ===================== 11. Después de la reversa =====================
do $p11$
declare r jsonb; OP text := 'ztrf.op@emdupar.gov.co'; ADM text := 'ztrf.admin@emdupar.gov.co';
begin
  perform pg_temp.ok('11.01 la huella de campo vuelve a la publicada', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) = 'cce593806f59d3d27c34d7f2070cc5c1');
  perform pg_temp.ok('11.02 el sello de un reporte de antes es IGUAL después de la reversa', pg_temp.pdf(ADM, pg_temp.val('viejo')::uuid) ->> 'sello' = pg_temp.val('sello_viejo'));
  perform pg_temp.ok('11.03 vuelven las firmas publicadas (sin p_registro)', to_regprocedure('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)') is not null and to_regprocedure('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone,jsonb)') is null
    and to_regprocedure('public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone)') is not null and to_regprocedure('public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone,jsonb)') is null);
  r := pg_temp.reg(OP, 'otro', '[{}]', null);
  perform pg_temp.ok('11.04 con la función publicada se registra igual que antes', pg_temp.err(r) = 'OK' and (select origen from campo.reporte_fotos where reporte_id = (r ->> '_id')::uuid) = 'camara', r::text);
  perform pg_temp.ok('11.05 nada se borró: las filas de reporte_registro y el origen de las fotos siguen',
    exists (select 1 from campo.reporte_registro where reporte_id = pg_temp.val('sup_flex')::uuid and xy_manual)
    and (select string_agg(origen, ',' order by orden) from campo.reporte_fotos where reporte_id = pg_temp.val('sup_flex')::uuid) = 'galeria,archivo');
  perform pg_temp.ok('11.06 las 5 funciones nuevas ya no están', to_regprocedure('campo.f_derivadas_filtradas(jsonb)') is null
    and to_regprocedure('public.geoportal_campo_derivadas_descarga_iniciar(text,jsonb,text,boolean,text)') is null);
  perform pg_temp.ok('11.07 la huella del acta y la de Técnica siguen iguales', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '111506c690249ad3b56ebf572566434c' and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))) = '838b80984e51cc7873a666f85d657195');
end $p11$;

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztrf_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;

rollback;
