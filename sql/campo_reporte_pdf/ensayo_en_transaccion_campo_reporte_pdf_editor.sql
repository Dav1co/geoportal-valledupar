-- [Code A] PDF DE «REPORTAR ANOMALÍA» (27-nov) · ENSAYO (termina en ERROR esperado; no deja nada) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov) · 70 — ENSAYO: datos de prueba y reportes de ANTES → MIGRACIÓN → pruebas → REVERSA → pruebas; termina en el
-- ERROR esperado (todo se deshace). Datos propios con prefijo ZTRAN (correos ztran.*@emdupar.gov.co; contrato de 12 dígitos 991800000201, que se comprueba que
-- no existe). Las RPC corren como service_role con los topes de producción (30 s y 8 s). Cinco perfiles: administrador, supervisor de Comercial, operador de
-- campo, dual (operador de campo y de Técnica, sin supervisión) y sin permisos. El mapa se mide con las capas REALES de la base (redes y predios).
-- =====================================================================
set local statement_timeout = '30s';
set local lock_timeout = '8s';
create temp table ztran_res (n serial, nombre text, ok boolean, detalle text);
create temp table ztran_val (k text primary key, v text);
create function pg_temp.ok(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as $f$
  insert into ztran_res (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $f$;
create function pg_temp.guardar(p_k text, p_v text) returns void language sql as $f$ insert into ztran_val values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.val(p_k text) returns text language sql as $f$ select v from ztran_val where k = p_k $f$;
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
                p_quien, v_id, p_tipo, '[PRUEBA ZTRAN] ' || p_tipo, p_contrato, p_lat, p_lon, coalesce(p_prec::text, 'null'), v_f, p_resultado, p_causal,
                case when p_registro is null then '' else format(', %L::jsonb', p_registro) end);
  else
    q := format('public.geoportal_campo_crear_reporte(%L, %L::uuid, %L, null, %L, %L, %s, %s, %s, false, ''campo'', %L::jsonb, null, null, %L, %L, null, null%s)',
                p_quien, v_id, p_tipo, '[PRUEBA ZTRAN] ' || p_tipo, p_contrato, p_lat, p_lon, coalesce(p_prec::text, 'null'), v_f, p_resultado, p_causal,
                case when p_registro is null then '' else format(', %L::jsonb', p_registro) end);
  end if;
  return pg_temp.rpc(q) || jsonb_build_object('_id', v_id);
end $f$;
create function pg_temp.datos(p_quien text, p_id uuid) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_ran_datos(%L, %L::uuid, null)', p_quien, p_id)) $f$;
create function pg_temp.registrar(p_quien text, p_id uuid, p_sello text, p_sha text default repeat('ab', 32), p_bytes integer default 150000) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_ran_registrar(%L, %L::uuid, %L, %L, %s, 0, null)', p_quien, p_id, p_sello, p_sha, p_bytes)) $f$;
create function pg_temp.obtener(p_quien text, p_id uuid) returns jsonb language sql as $f$
  select pg_temp.rpc(format('public.geoportal_campo_ran_obtener(%L, %L::uuid, null)', p_quien, p_id)) $f$;
create function pg_temp.audit(p_quien text, p_accion text, p_id text) returns bigint language sql as $f$
  select count(*) from public.geoportal_auditoria where email = p_quien and accion = p_accion and referencia = p_id $f$;

insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_registro_tecnico, ver_analisis_contrato) values
  ('ztran.adm@emdupar.gov.co', 'ZTRAN Administración', 'admin', true, 'sin_restriccion', 'todos', false, false, false, false, false),
  ('ztran.sup@emdupar.gov.co', 'ZTRAN Supervisora', 'consulta', true, 'sin_restriccion', 'todos', false, true, true, false, false),
  ('ztran.op@emdupar.gov.co', 'ZTRAN Operario', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false),
  ('ztran.dual@emdupar.gov.co', 'ZTRAN Dual sin supervisión', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, true, false),
  ('ztran.sin@emdupar.gov.co', 'ZTRAN Sin permisos', 'consulta', true, 'sin_restriccion', 'todos', false, false, false, false, false);
insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('ztran.dual@emdupar.gov.co', 'asignar_formulario', 'anomalia_compartida', 'ztran.adm@emdupar.gov.co');

-- ===================== 00. Datos de prueba y lo de ANTES =====================
do $p0$
declare r jsonb; OP text := 'ztran.op@emdupar.gov.co'; SUP text := 'ztran.sup@emdupar.gov.co';
begin
  perform pg_temp.ok('00.01 el contrato de prueba no existe (cartera, censo, reportes)',
    not exists (select 1 from public.cartera_suscripcion where contrato = '991800000201') and not exists (select 1 from public.catastro_valledupar where cod_usuario = '991800000201')
    and not exists (select 1 from campo.reportes where contrato = '991800000201'));
  insert into public.cartera_suscripcion (contrato, estado, nombre, telefono, direccion, barrio, deuda_total, periodo_carga) values
    ('991800000201', 'ACTIVO', 'ZTRAN PERSONA', '3001112233', 'CRA 9 # 12-30', 'CENTRO', 0, '20261123');
  -- A: el operario, con contrato y dirección encontrada en terreno, foto de cámara, punto real de la ciudad
  r := pg_temp.reg(OP, 'otro', '[{}]', '{"lat_registro": 10.476071, "lon_registro": -73.251529, "precision_registro_m": 6, "direccion": "[PRUEBA ZTRAN] CRA 9 # 12-32", "barrio": "CENTRO", "referencia": "Casa de rejas verdes"}',
                   10.476071, -73.251529, 6, '991800000201');
  perform pg_temp.ok('00.02 antes: un reporte de «Reportar anomalía» del operario se registra', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('A', r ->> '_id');
  -- B: la supervisora, foto de la galería y XY digitado (registrado desde otro punto)
  r := pg_temp.reg(SUP, 'otro', '[{"origen": "galeria"}]', '{"xy_manual": true, "lat_registro": 10.4762, "lon_registro": -73.2512, "precision_registro_m": 9}', 10.476071, -73.251529, null);
  perform pg_temp.ok('00.03 antes: un reporte con galería y XY digitado se registra', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('B', r ->> '_id');
  -- F: un formato (revisión previa): tiene su propio PDF
  r := pg_temp.reg(OP, 'revision_previa', '[{"etiqueta": "fachada_predio"}]', null, 10.476071, -73.251529, 5, '991800000201', 'inefectivo', 'nadie_atiende');
  perform pg_temp.ok('00.04 antes: un formato con contrato se registra', pg_temp.err(r) = 'OK', r::text);
  perform pg_temp.guardar('F', r ->> '_id');
  perform pg_temp.ok('00.05 antes: no existe la ruta del PDF del reporte', to_regprocedure('public.geoportal_campo_ran_datos(text,uuid,text)') is null);
end $p0$;

-- ===================== MIGRACIÓN (guardia incluida) =====================
-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov) · 05 — GUARDIA: se detiene sin cambiar nada si la base no es la esperada
-- Huella de campo 9f8b8ec55fc7e1c56fdf74a5f4e7f3c4 (con la etiqueta del último pago), ordenada con collate "C"; acta y Técnica publicadas; las funciones de permisos vivas;
-- las columnas que se leen de las tablas de campo, acta y la lista blanca; las capas del mapa con sus índices GiST de producción; el bucket privado de los PDF.
-- =====================================================================
do $guardia$
declare v text; r record;
begin
  if to_regprocedure('public.geoportal_campo_ran_datos(text,uuid,text)') is not null then
    raise exception 'Este paquete ya parece aplicado (existe geoportal_campo_ran_datos): use la reversa antes de repetir';
  end if;
  select (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text collate "C", p.proname, p.oid::regprocedure::text collate "C")) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) into v;
  if coalesce(v, '(ninguna)') is distinct from '9f8b8ec55fc7e1c56fdf74a5f4e7f3c4' then
    raise exception 'Las funciones de campo no son las esperadas (huella 9f8b8ec55fc7e1c56fdf74a5f4e7f3c4; hay %): deténgase y avise', v;
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) is distinct from '111506c690249ad3b56ebf572566434c' then raise exception 'Las funciones del acta no son las publicadas: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))) is distinct from '838b80984e51cc7873a666f85d657195' then raise exception 'Las funciones de Técnica no son las publicadas: deténgase y avise'; end if;
  for r in select * from (values ('public.geoportal_puede(text,text)', '32f174a55b95788d3f8187b507303c2f'), ('public.geoportal_mis_permisos(text)', '83166fe17be58da67bbdedaae429bedb'), ('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)', '01fda69a9d912067b8b4dc153ac7957e'), ('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)', 'e5a90103b4a83440fd826f03266b7245')) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la publicada: deténgase y avise', r.f;
    end if;
  end loop;
  -- la tabla nueva, si quedó de una reversa, debe ser exactamente la de este paquete
  if to_regclass('campo.reporte_pdf') is not null then
    select md5(concat_ws('#', (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped), (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel), (select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel), (select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal), (select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel))) into v from (select to_regclass('campo.reporte_pdf') as rel) z;
    if v is distinct from '5c28826d6ba13de024a0583384601d36' then raise exception 'La tabla campo.reporte_pdf ya existe y no es la de este paquete: deténgase y avise'; end if;
  end if;
  if to_regclass('campo.reporte_ran') is not null then
    select md5(concat_ws('#', (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped), (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel), (select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel), (select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal), (select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel))) into v from (select to_regclass('campo.reporte_ran') as rel) z;
    if v is distinct from '4e74e40510a7c46d9c5e15824a946ae9' then raise exception 'La tabla campo.reporte_ran ya existe y no es la de este paquete: deténgase y avise'; end if;
  end if;
  -- columnas que se leen (con su tipo)
  for r in select * from (values ('campo.reportes', 'id', 'uuid'), ('campo.reportes', 'seq', 'bigint'), ('campo.reportes', 'tipo_id', 'bigint'), ('campo.reportes', 'subtipo_id', 'bigint'), ('campo.reportes', 'descripcion', 'text'), ('campo.reportes', 'contrato', 'text'), ('campo.reportes', 'lat', 'numeric(9,6)'), ('campo.reportes', 'lon', 'numeric(9,6)'), ('campo.reportes', 'precision_m', 'numeric(8,1)'), ('campo.reportes', 'autor', 'text'), ('campo.reportes', 'registrado_en', 'timestamp with time zone'), ('campo.reportes', 'inicio_en', 'timestamp with time zone'), ('campo.reportes', 'inicio_origen', 'text'), ('campo.reporte_fotos', 'orden', 'smallint'), ('campo.reporte_fotos', 'ruta_storage', 'text'), ('campo.reporte_fotos', 'etiqueta', 'text'), ('campo.reporte_fotos', 'origen', 'text'), ('campo.reporte_eventos', 'tipo_evento', 'text'), ('campo.reporte_eventos', 'estado_nuevo', 'text'), ('campo.reporte_eventos', 'motivo', 'text'), ('campo.reporte_eventos', 'acta_id', 'uuid'), ('campo.reporte_eventos', 'reporte_original_id', 'uuid'), ('campo.reporte_registro', 'xy_manual', 'boolean'), ('campo.reporte_registro', 'lat_registro', 'numeric(9,6)'), ('campo.reporte_registro', 'direccion', 'text'), ('campo.reporte_direccion_contrato', 'direccion_comercial', 'text'), ('campo.reporte_direccion_contrato', 'direccion_catastro', 'text'), ('campo.estados_reporte', 'nombre', 'text'), ('public.geoportal_lista_blanca', 'nombre', 'text'), ('acta.actas', 'consecutivo', 'text')) x(t, c, ty) loop
    if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass(r.t) and a.attname = r.c and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = r.ty) then
      raise exception 'La columna %.% no existe o no es %: deténgase y avise', r.t, r.c, r.ty;
    end if;
  end loop;
  -- capas del mapa: dos tablas y una vista materializada, con geom y su índice GiST
  for r in select * from (values ('public.redes_acueducto', 'r', 'idx_redes_acu_geom'), ('public.redes_alcantarillado', 'r', 'idx_redes_alc_geom'),
                                 ('public.predios_comercial', 'm', 'idx_predcom_geom_n')) x(t, k, i) loop
    if to_regclass(r.t) is null or (select relkind::text from pg_class where oid = to_regclass(r.t)) <> r.k then
      raise exception 'La capa % no existe o no es de la clase esperada (%): deténgase y avise', r.t, r.k;
    end if;
    if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass(r.t) and a.attname = 'geom' and not a.attisdropped and format_type(a.atttypid, a.atttypmod) like 'geometry%') then
      raise exception 'La capa % no tiene la columna geom (geometry): deténgase y avise', r.t;
    end if;
    if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid where i.indrelid = to_regclass(r.t) and c.relname = r.i
                    and pg_get_indexdef(i.indexrelid) ~ 'USING gist \(geom\)') then
      raise exception 'Falta el índice % (GiST sobre geom) en %: deténgase y avise', r.i, r.t;
    end if;
  end loop;
  if not exists (select 1 from public.spatial_ref_sys where srid = 3116) then raise exception 'Falta el sistema de referencia 3116 (MAGNA-SIRGAS Bogotá): deténgase y avise'; end if;
  if not exists (select 1 from storage.buckets where id = 'actas-pdf' and not public) then raise exception 'Falta el bucket privado actas-pdf: deténgase y avise'; end if;
  if exists (select 1 from pg_policies where schemaname in ('campo', 'acta')) then raise exception 'Hay políticas RLS en campo o acta: deténgase y avise'; end if;
  if not exists (select 1 from pg_roles where rolname = 'homelab_lectura') then raise exception 'No existe el rol homelab_lectura: deténgase y avise'; end if;
end $guardia$;

-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov; plan aprobado por David) · 10 — ESTRUCTURA
-- campo.reporte_pdf: una fila por VERSIÓN del PDF de un reporte. Versión nueva solo si cambia el sello del contenido (estado, historial, datos); si no cambió,
-- se entrega la misma. Solo inserción (disparadores de campo.f_solo_agregar, como reporte_fotos), RLS sin políticas, sin permisos para la API, SELECT para
-- homelab_lectura. El archivo va al bucket privado actas-pdf (el de los PDF de los formatos); aquí solo su ruta, sha256 y tamaño. La ruta lleva los 16 primeros
-- caracteres del sha256 del PDF: cada intento de generación sube a su propia ruta y nunca pisa otro archivo (un intento que no llega a registrarse queda sin fila).
-- =====================================================================
-- Tras una reversa la tabla se conserva (nada se borra): si ya existe, la guardia exigió que fuera exactamente la de este paquete y aquí no se toca.
do $estructura$
begin
  if to_regclass('campo.reporte_pdf') is not null then return; end if;
  execute $ddl$
create table campo.reporte_pdf (
  id             bigint generated always as identity primary key,
  reporte_id     uuid not null references campo.reportes (id),
  version        integer not null check (version between 1 and 99),
  sello          text not null check (sello ~ '^[0-9a-f]{64}$'),
  nombre         text not null check (nombre ~ '^[0-9]{14}-RAN-[0-9]{6,12}(-v[0-9]{1,2})?\.pdf$'),
  ruta           text not null unique check (ruta ~ '^campo/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}/[0-9a-f]{16}/[0-9]{14}-RAN-[0-9]{6,12}(-v[0-9]{1,2})?\.pdf$'),
  sha256         text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  bytes          integer not null check (bytes between 200 and 26214400),
  fotos_omitidas integer not null default 0 check (fotos_omitidas >= 0),
  generado_por   text not null check (generado_por = lower(generado_por) and position('@' in generado_por) > 1),
  generado_en    timestamptz not null default clock_timestamp(),
  unique (reporte_id, version),
  unique (reporte_id, sello)
);
comment on table campo.reporte_pdf is 'PDF de cada reporte de «Reportar anomalía» (sigla RAN), por versión; solo inserción. Code A, 27-nov-2026.';
create trigger t_solo_agregar before delete or update on campo.reporte_pdf for each row execute function campo.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on campo.reporte_pdf for each statement execute function campo.f_solo_agregar();
alter table campo.reporte_pdf enable row level security;
revoke all on campo.reporte_pdf from public, anon, authenticated, service_role;
grant select on campo.reporte_pdf to homelab_lectura;
  $ddl$;
end $estructura$;

-- campo.reporte_ran (27-nov, David): el NÚMERO RAN seguido (RAN-000001, 000002…), propio de «Reportar anomalía». Los reportes existentes se numeran al migrar
-- en orden de fecha de registro (empate: seq); los nuevos, la primera vez que se pide su PDF, junto con todo reporte anterior que aún no lo tenga (así el orden
-- sigue siendo el de registro, no el de los pedidos). Solo inserción, RLS sin políticas, sin permisos para la API, SELECT para homelab_lectura.
do $estructura_ran$
begin
  if to_regclass('campo.reporte_ran') is not null then return; end if;
  execute $ddl$
create table campo.reporte_ran (
  numero      bigint primary key check (numero >= 1),
  reporte_id  uuid not null unique references campo.reportes (id),
  asignado_en timestamptz not null default clock_timestamp()
);
comment on table campo.reporte_ran is 'Número RAN seguido de cada reporte de «Reportar anomalía», en orden de fecha de registro; solo inserción. Code A, 27-nov-2026.';
create trigger t_solo_agregar before delete or update on campo.reporte_ran for each row execute function campo.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on campo.reporte_ran for each statement execute function campo.f_solo_agregar();
alter table campo.reporte_ran enable row level security;
revoke all on campo.reporte_ran from public, anon, authenticated, service_role;
grant select on campo.reporte_ran to homelab_lectura;
  $ddl$;
end $estructura_ran$;

-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov) · 20 — FUNCIONES
-- Internas (nadie de la API): f_ran_autorizar, f_ran_persona, f_ran_contenido, f_ran_destino, f_ran_mapa.
-- RPC (solo service_role, desde la Edge geoportal-campo): geoportal_campo_ran_datos, geoportal_campo_ran_registrar, geoportal_campo_ran_obtener.
-- Reglas (David, 27-nov): sin firmas; solo supervisión de Comercial y administrador (los demás, 403); nunca los datos sensibles ni las rutas en el PDF;
-- nombre del operario (el correo solo si no tiene nombre); versión nueva solo si cambia el sello; mapa vectorial armado en el servidor.
-- =====================================================================

-- Supervisión de Comercial (dashboard_campo) o administrador; después, que exista y que sea de «Reportar anomalía» (tipo general: los formatos tienen su PDF).
create function campo.f_ran_autorizar(p_solicitante text, p_id uuid) returns text
language plpgsql security definer set search_path = public, campo, pg_temp as $$
declare v_email text; v_cod text;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select t.codigo into v_cod from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id where r.id = p_id;
  if v_cod is null then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  if not campo.f_tipo_general(v_cod) then
    perform campo.f_error('Ese reporte es un formato: su PDF es el del formato, no el de «Reportar anomalía»');
  end if;
  return v_email;
end $$;

-- Nombre de la persona (lista blanca); el correo solo si no tiene nombre (David, 27-nov)
create function campo.f_ran_persona(p_email text) returns text
language sql stable security definer set search_path = public, campo, pg_temp as $$
  select coalesce((select nullif(btrim(b.nombre), '') from public.geoportal_lista_blanca b where b.email = lower(btrim(p_email)) limit 1), lower(btrim(p_email)))
$$;

-- Número RAN: numera, en orden de (registrado_en, seq), todos los reportes generales sin número hasta p_hasta (nulo = todos) y devuelve el de p_hasta.
-- Con candado de transacción: dos pedidos a la vez no reparten el mismo número ni dejan huecos.
create function campo.f_ran_numerar(p_hasta uuid) returns bigint
language plpgsql security definer set search_path = public, campo, pg_temp as $$
declare v_reg timestamptz; v_seq bigint; v_n bigint;
begin
  if p_hasta is not null then
    select numero into v_n from campo.reporte_ran where reporte_id = p_hasta;
    if v_n is not null then return v_n; end if;
    select registrado_en, seq into v_reg, v_seq from campo.reportes where id = p_hasta;
  end if;
  perform pg_advisory_xact_lock(hashtext('campo.reporte_ran'));
  insert into campo.reporte_ran (numero, reporte_id)
  select (select coalesce(max(numero), 0) from campo.reporte_ran) + row_number() over (order by r.registrado_en, r.seq), r.id
    from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id
   where campo.f_tipo_general(t.codigo)
     and not exists (select 1 from campo.reporte_ran x where x.reporte_id = r.id)
     and (p_hasta is null or (r.registrado_en, r.seq) <= (v_reg, v_seq))
   order by r.registrado_en, r.seq;
  return (select numero from campo.reporte_ran where reporte_id = p_hasta);
end $$;

-- Todo lo que va al PDF (menos el mapa y el pie de generación). Solo caracteres de WinAnsi (el escritor del PDF no tiene «→»). Su sha256 es el sello: si cambia (estado, historial, datos), hay versión nueva.
-- NUNCA lee campo.reporte_datos_sensibles. Las rutas de las fotos van solo para que la Edge las lea; el PDF no las imprime.
create function campo.f_ran_contenido(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, campo, acta, pg_temp as $$
declare v campo.v_reportes_estado%rowtype; v_rr campo.reporte_registro; v_dc campo.reporte_direccion_contrato; r jsonb;
        f_hora constant text := 'DD/MM/YYYY HH24:MI';
begin
  select * into v from campo.v_reportes_estado where id = p_id;
  if not found then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  select * into v_rr from campo.reporte_registro where reporte_id = p_id;
  select * into v_dc from campo.reporte_direccion_contrato where reporte_id = p_id;
  select jsonb_build_object(
    'identificador', (select 'RAN-' || case when n.numero < 1000000 then lpad(n.numero::text, 6, '0') else n.numero::text end from campo.reporte_ran n where n.reporte_id = p_id),
    'numero_interno', v.seq,
    'grupo', g.nombre, 'tipo', t.nombre, 'subtipo', s.nombre,
    'estado', coalesce((select e.nombre from campo.estados_reporte e where e.codigo = v.estado), v.estado),
    'oculto', v.oculto, 'riesgo_inmediato', v.riesgo_inmediato, 'fuera_de_zona', v.fuera_de_zona,
    'contrato', v.contrato, 'contrato_verificado', v.contrato_verificado,
    'direccion_contrato', case when v_dc.reporte_id is not null then jsonb_build_object(
        'comercial', v_dc.direccion_comercial, 'barrio_comercial', v_dc.barrio_comercial, 'catastro', v_dc.direccion_catastro, 'barrio_catastro', v_dc.barrio_catastro) end,
    'terreno', case when v_rr.reporte_id is not null and coalesce(v_rr.direccion, v_rr.barrio, v_rr.referencia) is not null then jsonb_build_object(
        'direccion', v_rr.direccion, 'barrio', v_rr.barrio, 'referencia', v_rr.referencia) end,
    'ubicacion', jsonb_build_object('lat', v.lat, 'lon', v.lon, 'precision_m', v.precision_m,
        'xy_digitado', coalesce(v_rr.xy_manual, false), 'sin_ubicacion_dispositivo', v_rr.reporte_id is not null and v_rr.lat_registro is null,
        'lat_registro', v_rr.lat_registro, 'lon_registro', v_rr.lon_registro, 'precision_registro_m', v_rr.precision_registro_m),
    'descripcion', v.descripcion,
    'reporto', campo.f_ran_persona(v.autor),
    'inicio', to_char(v.inicio_en at time zone 'America/Bogota', f_hora) || case v.inicio_origen when 'dispositivo' then ' (celular)' when 'servidor' then ' (hora del servidor)' else '' end,
    'fin', to_char(v.registrado_en at time zone 'America/Bogota', f_hora),
    'duracion', case when v.inicio_en is null or v.registrado_en < v.inicio_en then null
                     else (select case when s < 60 then s || ' s' when s < 3600 then (s / 60) || ' min'
                                       else (s / 3600) || ' h ' || lpad(((s % 3600) / 60)::text, 2, '0') || ' min' end
                             from (select floor(extract(epoch from v.registrado_en - v.inicio_en))::bigint as s) q) end,
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', f.orden, 'ruta', f.ruta_storage, 'bytes', f.tamano_bytes,
                         'etiqueta', coalesce(case when f.etiqueta = 'adicional' then 'Adicional' else (select tf.nombre from campo.tipo_fotos tf where tf.tipo_id = v.tipo_id and tf.codigo = f.etiqueta) end,
                                              'Foto ' || f.orden)
                                     || case f.origen when 'galeria' then ' · adjuntada desde la galería' when 'archivo' then ' · adjuntada desde un archivo' else ' · tomada con la cámara' end)
                         order by f.orden) from campo.reporte_fotos f where f.reporte_id = p_id), '[]'::jsonb),
    'historial', jsonb_build_array(jsonb_build_object('fecha', to_char(v.registrado_en at time zone 'America/Bogota', f_hora), 'texto', 'Reportado', 'quien', campo.f_ran_persona(v.autor)))
      || coalesce((select jsonb_agg(jsonb_build_object('fecha', to_char(e.creado_en at time zone 'America/Bogota', f_hora),
                     'texto', case e.tipo_evento
                                when 'cambio_estado' then 'Cambio de estado a ' || coalesce((select x.nombre from campo.estados_reporte x where x.codigo = e.estado_nuevo), e.estado_nuevo)
                                when 'ocultar' then 'Se ocultó el reporte'
                                when 'reincluir' then 'Se reincluyó el reporte'
                                when 'vincular_duplicado' then 'Se vinculó como duplicado del reporte ' || coalesce((select coalesce((select 'RAN-' || lpad(x.numero::text, 6, '0') from campo.reporte_ran x where x.reporte_id = o.id), 'interno ' || o.seq) from campo.reportes o where o.id = e.reporte_original_id), 'original')
                                when 'nota' then 'Nota'
                                when 'vincular_acta' then 'Se vinculó el acta ' || coalesce((select a.consecutivo from acta.actas a where a.id = e.acta_id), '')
                                else e.tipo_evento end
                              || coalesce(' · ' || nullif(btrim(e.motivo), ''), ''),
                     'quien', campo.f_ran_persona(e.autor)) order by e.id)
                     from campo.reporte_eventos e where e.reporte_id = p_id), '[]'::jsonb)
  ) into r
  from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id left join campo.subtipos_reporte s on s.id = v.subtipo_id
  where t.id = v.tipo_id;
  return r;
end $$;

-- Versión, nombre y carpeta para un sello: la versión ya registrada con ese sello, o la siguiente. La ruta = carpeta || 16 primeros del sha256 del PDF || '/' || nombre.
create function campo.f_ran_destino(p_id uuid, p_sello text) returns jsonb
language plpgsql stable security definer set search_path = public, campo, pg_temp as $$
declare v_r campo.reportes; v_doc campo.reporte_pdf; v_ver integer; v_nombre text;
begin
  select * into v_r from campo.reportes where id = p_id;
  select * into v_doc from campo.reporte_pdf where reporte_id = p_id and sello = p_sello;
  v_ver := coalesce(v_doc.version, (select coalesce(max(version), 0) + 1 from campo.reporte_pdf where reporte_id = p_id));
  if v_ver > 99 then perform campo.f_error('Este reporte ya tiene 99 versiones de PDF', '55000'); end if;
  v_nombre := campo.f_nombre_pdf(v_r.registrado_en, 'RAN',
                (select case when n.numero < 1000000 then lpad(n.numero::text, 6, '0') else n.numero::text end from campo.reporte_ran n where n.reporte_id = p_id), v_ver);
  if v_nombre is null then perform campo.f_error('El reporte no tiene número RAN', '55000'); end if;
  return jsonb_build_object('version', v_ver, 'nombre', v_nombre,
    'carpeta', 'campo/' || to_char(v_r.registrado_en at time zone 'America/Bogota', 'YYYY-MM') || '/' || p_id || '/',
    'documento', case when v_doc.id is not null then jsonb_build_object('nombre', v_doc.nombre, 'ruta', v_doc.ruta, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes,
                   'version', v_doc.version, 'generado_en', v_doc.generado_en) end);
end $$;

-- Mapa pequeño, vectorial, en metros (MAGNA-SIRGAS Bogotá, 3116) relativo al punto del reporte: ventana de 400 × 200 m con las redes de acueducto y alcantarillado
-- recortadas y simplificadas (0,5 m) y los predios. Usa los índices GiST de producción (idx_redes_acu_geom, idx_redes_alc_geom, idx_predcom_geom_n) por el filtro &&.
-- Topes: 1.500 trozos de red y 3.000 predios. Sin teselas ni servicios externos.
create function campo.f_ran_mapa(p_lat numeric, p_lon numeric, p_lat_reg numeric default null, p_lon_reg numeric default null) returns jsonb
language plpgsql stable security definer set search_path = public, campo, pg_temp as $$
declare v_c geometry; v_x0 double precision; v_y0 double precision; v_env geometry; v_env_g geometry; v_lin jsonb; v_pred jsonb; v_reg jsonb;
        c_ax constant double precision := 200; c_ay constant double precision := 100;
begin
  if p_lat is null or p_lon is null then return null; end if;
  v_c := st_transform(st_setsrid(st_makepoint(p_lon::double precision, p_lat::double precision), 4326), 3116);
  v_x0 := st_x(v_c); v_y0 := st_y(v_c);
  v_env := st_makeenvelope(v_x0 - c_ax, v_y0 - c_ay, v_x0 + c_ax, v_y0 + c_ay, 3116);
  v_env_g := st_transform(v_env, 4326);
  with l as (
    select 'acueducto'::text as capa, a.geom from public.redes_acueducto a where a.geom && v_env_g
    union all
    select 'alcantarillado', b.geom from public.redes_alcantarillado b where b.geom && v_env_g
  ), c as (
    select l.capa, (st_dump(st_collectionextract(st_simplify(st_intersection(st_transform(l.geom, 3116), v_env), 0.5), 2))).geom as g from l
  )
  select coalesce(jsonb_agg(jsonb_build_object('capa', x.capa, 'p', st_asgeojson(st_translate(x.g, -v_x0, -v_y0), 1)::jsonb -> 'coordinates') order by x.capa), '[]'::jsonb) into v_lin
    from (select c.capa, c.g from c where not st_isempty(c.g) and st_npoints(c.g) >= 2 limit 1500) x;
  select coalesce(jsonb_agg(jsonb_build_array(round((st_x(x.t) - v_x0)::numeric, 1), round((st_y(x.t) - v_y0)::numeric, 1))), '[]'::jsonb) into v_pred
    from (select st_transform(p.geom, 3116) as t from public.predios_comercial p where p.geom && v_env_g limit 3000) x
   where st_intersects(x.t, v_env);
  if p_lat_reg is not null and p_lon_reg is not null then
    select jsonb_build_array(round((st_x(q) - v_x0)::numeric, 1), round((st_y(q) - v_y0)::numeric, 1)) into v_reg
      from (select st_transform(st_setsrid(st_makepoint(p_lon_reg::double precision, p_lat_reg::double precision), 4326), 3116) as q) z;
  end if;
  return jsonb_build_object('ancho_m', 2 * c_ax, 'alto_m', 2 * c_ay, 'lineas', v_lin, 'predios', v_pred, 'registro', v_reg);
end $$;

-- RPC 1: lo que la Edge necesita para armar el PDF (o para saber que ya existe el de este sello). Lectura: no audita (audita registrar u obtener).
create function public.geoportal_campo_ran_datos(p_solicitante text, p_reporte_id uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $$
declare v_email text; v_cont jsonb; v_sello text; v_dest jsonb;
begin
  v_email := campo.f_ran_autorizar(p_solicitante, p_reporte_id);
  perform campo.f_ran_numerar(p_reporte_id);
  v_cont := campo.f_ran_contenido(p_reporte_id);
  v_sello := encode(sha256(convert_to(v_cont::text, 'UTF8')), 'hex');
  v_dest := campo.f_ran_destino(p_reporte_id, v_sello);
  return v_cont || v_dest || jsonb_build_object('reporte_id', p_reporte_id, 'sello', v_sello,
    'mapa', case when v_dest -> 'documento' = 'null'::jsonb then campo.f_ran_mapa((v_cont -> 'ubicacion' ->> 'lat')::numeric, (v_cont -> 'ubicacion' ->> 'lon')::numeric,
              case when (v_cont -> 'ubicacion' ->> 'xy_digitado')::boolean then (v_cont -> 'ubicacion' ->> 'lat_registro')::numeric end,
              case when (v_cont -> 'ubicacion' ->> 'xy_digitado')::boolean then (v_cont -> 'ubicacion' ->> 'lon_registro')::numeric end) end,
    'generado_por', campo.f_ran_persona(v_email), 'generado_en', to_char(clock_timestamp() at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI'));
end $$;

-- RPC 2: la Edge ya subió el PDF de este sello: queda la versión (solo inserción) y la auditoría. Si el reporte cambió mientras tanto, 409 y se vuelve a pedir.
create function public.geoportal_campo_ran_registrar(p_solicitante text, p_reporte_id uuid, p_sello text, p_sha256 text, p_bytes integer, p_fotos_omitidas integer default 0,
                                                     p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $$
declare v_email text; v_sello text; v_dest jsonb; v_id bigint; v_doc campo.reporte_pdf;
begin
  v_email := campo.f_ran_autorizar(p_solicitante, p_reporte_id);
  perform campo.f_ran_numerar(p_reporte_id);
  v_sello := encode(sha256(convert_to(campo.f_ran_contenido(p_reporte_id)::text, 'UTF8')), 'hex');
  if p_sello is distinct from v_sello then perform campo.f_error('El reporte cambió mientras se armaba el PDF: vuelva a pedirlo', '55000'); end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then perform campo.f_error('La huella del PDF no es válida'); end if;
  if p_bytes is null or p_bytes < 200 or p_bytes > 26214400 then perform campo.f_error('El tamaño del PDF no es válido'); end if;
  v_dest := campo.f_ran_destino(p_reporte_id, v_sello);
  insert into campo.reporte_pdf (reporte_id, version, sello, nombre, ruta, sha256, bytes, fotos_omitidas, generado_por)
  values (p_reporte_id, (v_dest ->> 'version')::integer, v_sello, v_dest ->> 'nombre', (v_dest ->> 'carpeta') || left(p_sha256, 16) || '/' || (v_dest ->> 'nombre'), p_sha256, p_bytes,
          greatest(coalesce(p_fotos_omitidas, 0), 0), v_email)
  on conflict do nothing returning id into v_id;
  select * into v_doc from campo.reporte_pdf where reporte_id = p_reporte_id and sello = v_sello;
  if v_doc.id is null then perform campo.f_error('Otro supervisor generó una versión al mismo tiempo: vuelva a pedirlo', '55000'); end if;
  perform campo.f_auditar(v_email, case when v_id is not null then 'campo_ran_pdf_generar' else 'campo_ran_pdf_descargar' end, p_reporte_id::text,
    jsonb_build_object('nombre', v_doc.nombre, 'version', v_doc.version, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes, 'fotos_omitidas', v_doc.fotos_omitidas), p_ip);
  return jsonb_build_object('nombre', v_doc.nombre, 'ruta', v_doc.ruta, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes, 'version', v_doc.version, 'nuevo', v_id is not null);
end $$;

-- RPC 3: el PDF del sello VIGENTE ya existe: se entrega y la descarga queda auditada
create function public.geoportal_campo_ran_obtener(p_solicitante text, p_reporte_id uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, campo, pg_temp as $$
declare v_email text; v_sello text; v_doc campo.reporte_pdf;
begin
  v_email := campo.f_ran_autorizar(p_solicitante, p_reporte_id);
  perform campo.f_ran_numerar(p_reporte_id);
  v_sello := encode(sha256(convert_to(campo.f_ran_contenido(p_reporte_id)::text, 'UTF8')), 'hex');
  select * into v_doc from campo.reporte_pdf where reporte_id = p_reporte_id and sello = v_sello;
  if v_doc.id is null then perform campo.f_error('El PDF de la versión vigente de este reporte todavía no existe', 'P0002'); end if;
  perform campo.f_auditar(v_email, 'campo_ran_pdf_descargar', p_reporte_id::text, jsonb_build_object('nombre', v_doc.nombre, 'version', v_doc.version), p_ip);
  return jsonb_build_object('nombre', v_doc.nombre, 'ruta', v_doc.ruta, 'sha256', v_doc.sha256, 'bytes', v_doc.bytes, 'version', v_doc.version, 'nuevo', false);
end $$;

-- Permisos: las internas, para nadie de la API; las RPC, solo service_role (la Edge)
revoke all on function campo.f_ran_numerar(uuid), campo.f_ran_autorizar(text, uuid), campo.f_ran_persona(text), campo.f_ran_contenido(uuid), campo.f_ran_destino(uuid, text),
                       campo.f_ran_mapa(numeric, numeric, numeric, numeric) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_campo_ran_datos(text, uuid, text), public.geoportal_campo_ran_registrar(text, uuid, text, text, integer, integer, text),
                       public.geoportal_campo_ran_obtener(text, uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_ran_datos(text, uuid, text), public.geoportal_campo_ran_registrar(text, uuid, text, text, integer, integer, text),
                          public.geoportal_campo_ran_obtener(text, uuid, text) to service_role;

-- Los reportes que ya existen: número RAN en orden de fecha de registro (si la tabla quedó de una reversa, se sigue desde su último número)
select campo.f_ran_numerar(null);


-- ===================== 01. Estructura y permisos =====================
do $p1$
begin
  perform pg_temp.ok('01.01 la huella de campo es la de este cambio; acta y Técnica no cambiaron',
    (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text collate "C", p.proname, p.oid::regprocedure::text collate "C")) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) = '68942f699d39f30bacf4f231be57e131' and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '111506c690249ad3b56ebf572566434c' and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'))) = '838b80984e51cc7873a666f85d657195');
  perform pg_temp.ok('01.02 campo.reporte_pdf: RLS sin políticas, sin permisos para la API, SELECT para homelab_lectura',
    (select relrowsecurity from pg_class where oid = 'campo.reporte_pdf'::regclass) and not exists (select 1 from pg_policies where schemaname = 'campo')
    and not has_table_privilege('service_role', 'campo.reporte_pdf', 'select') and not has_table_privilege('authenticated', 'campo.reporte_pdf', 'select')
    and not has_table_privilege('anon', 'campo.reporte_pdf', 'select') and has_table_privilege('homelab_lectura', 'campo.reporte_pdf', 'select')
    and not has_table_privilege('homelab_lectura', 'campo.reporte_pdf', 'insert'));
  perform pg_temp.ok('01.03 las 3 RPC solo para service_role; las 5 internas para nadie de la API',
    has_function_privilege('service_role', 'public.geoportal_campo_ran_datos(text,uuid,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_ran_datos(text,uuid,text)', 'execute')
    and has_function_privilege('service_role', 'public.geoportal_campo_ran_obtener(text,uuid,text)', 'execute') and not has_function_privilege('anon', 'public.geoportal_campo_ran_obtener(text,uuid,text)', 'execute')
    and has_function_privilege('service_role', 'public.geoportal_campo_ran_registrar(text,uuid,text,text,integer,integer,text)', 'execute')
    and not has_function_privilege('service_role', 'campo.f_ran_contenido(uuid)', 'execute') and not has_function_privilege('service_role', 'campo.f_ran_mapa(numeric,numeric,numeric,numeric)', 'execute')
    and not has_function_privilege('service_role', 'campo.f_ran_autorizar(text,uuid)', 'execute') and not has_function_privilege('service_role', 'campo.f_ran_numerar(uuid)', 'execute'));
end $p1$;

-- ===================== 01b. Número RAN seguido =====================
do $p1b$
declare A uuid := pg_temp.val('A')::uuid; B uuid := pg_temp.val('B')::uuid; F uuid := pg_temp.val('F')::uuid; C uuid; D uuid; r jsonb; v_c bigint; v_d bigint; v_max bigint;
begin
  perform pg_temp.ok('01b.01 al migrar, todos los reportes de «Reportar anomalía» que existían tienen número, seguidos desde 1 y sin huecos',
    not exists (select 1 from campo.reportes x join campo.tipos_reporte t on t.id = x.tipo_id where campo.f_tipo_general(t.codigo) and not exists (select 1 from campo.reporte_ran n where n.reporte_id = x.id))
    and (select min(numero) = 1 and max(numero) = count(*) from campo.reporte_ran));
  perform pg_temp.ok('01b.02 en orden de fecha de registro: ningún reporte posterior tiene un número menor',
    not exists (select 1 from campo.reporte_ran n1 join campo.reportes r1 on r1.id = n1.reporte_id, campo.reporte_ran n2 join campo.reportes r2 on r2.id = n2.reporte_id
                 where (r1.registrado_en, r1.seq) < (r2.registrado_en, r2.seq) and n1.numero > n2.numero));
  perform pg_temp.ok('01b.03 A (registrado antes) tiene un número menor que B; un formato no tiene número',
    (select numero from campo.reporte_ran where reporte_id = A) < (select numero from campo.reporte_ran where reporte_id = B)
    and not exists (select 1 from campo.reporte_ran where reporte_id = F));
  select coalesce(max(numero), 0) into v_max from campo.reporte_ran;
  -- dos reportes nuevos, después de migrar; se pide primero el PDF del más reciente (D)
  r := pg_temp.reg('ztran.op@emdupar.gov.co', 'otro', '[{}]', null, 10.476071, -73.251529, 6); C := (r ->> '_id')::uuid;
  r := pg_temp.reg('ztran.op@emdupar.gov.co', 'otro', '[{}]', null, 10.476071, -73.251529, 6); D := (r ->> '_id')::uuid;
  perform pg_temp.guardar('C', C::text); perform pg_temp.guardar('D', D::text);
  perform pg_temp.ok('01b.04 los reportes nuevos no tienen número hasta que se pide su PDF', not exists (select 1 from campo.reporte_ran where reporte_id in (C, D)));
  r := pg_temp.datos('ztran.sup@emdupar.gov.co', D);
  select numero into v_c from campo.reporte_ran where reporte_id = C; select numero into v_d from campo.reporte_ran where reporte_id = D;
  perform pg_temp.ok('01b.05 se pide primero el PDF del más reciente: igual queda en orden de registro (C = máx + 1, D = máx + 2)',
    v_c = v_max + 1 and v_d = v_max + 2 and r ->> 'identificador' = 'RAN-' || lpad(v_d::text, 6, '0'), format('max %s, C %s, D %s', v_max, v_c, v_d));
  r := pg_temp.datos('ztran.sup@emdupar.gov.co', C);
  perform pg_temp.ok('01b.06 pedirlo otra vez no cambia el número', (select numero from campo.reporte_ran where reporte_id = C) = v_c and r ->> 'identificador' = 'RAN-' || lpad(v_c::text, 6, '0'));
  perform pg_temp.ok('01b.07 un denegado no numera (el permiso va primero)',
    pg_temp.err(pg_temp.datos('ztran.op@emdupar.gov.co', (pg_temp.reg('ztran.op@emdupar.gov.co', 'otro', '[{}]') ->> '_id')::uuid)) = '42501'
    and (select max(numero) from campo.reporte_ran) = v_max + 2);
end $p1b$;

-- ===================== 02. Quién puede =====================
do $p2$
declare A uuid := pg_temp.val('A')::uuid; F uuid := pg_temp.val('F')::uuid;
begin
  perform pg_temp.ok('02.01 administrador y supervisora de Comercial: sí', pg_temp.err(pg_temp.datos('ztran.adm@emdupar.gov.co', A)) = 'OK' and pg_temp.err(pg_temp.datos('ztran.sup@emdupar.gov.co', A)) = 'OK',
    pg_temp.datos('ztran.adm@emdupar.gov.co', A)::text);
  perform pg_temp.ok('02.02 el operario (aunque sea el autor), el dual sin supervisión y el sin permisos: 403 (42501)',
    pg_temp.err(pg_temp.datos('ztran.op@emdupar.gov.co', A)) = '42501' and pg_temp.err(pg_temp.datos('ztran.dual@emdupar.gov.co', A)) = '42501'
    and pg_temp.err(pg_temp.datos('ztran.sin@emdupar.gov.co', A)) = '42501');
  perform pg_temp.ok('02.03 también 403 al registrar y al obtener',
    pg_temp.err(pg_temp.registrar('ztran.op@emdupar.gov.co', A, repeat('0', 64))) = '42501' and pg_temp.err(pg_temp.obtener('ztran.dual@emdupar.gov.co', A)) = '42501');
  perform pg_temp.ok('02.04 un reporte que no existe: 404 (P0002)', pg_temp.err(pg_temp.datos('ztran.sup@emdupar.gov.co', gen_random_uuid())) = 'P0002');
  perform pg_temp.ok('02.05 un formato: se rechaza (tiene su propio PDF)', pg_temp.err(pg_temp.datos('ztran.sup@emdupar.gov.co', F)) = '22023', pg_temp.datos('ztran.sup@emdupar.gov.co', F)::text);
  perform pg_temp.ok('02.06 antes de generarlo, obtener responde 404', pg_temp.err(pg_temp.obtener('ztran.sup@emdupar.gov.co', A)) = 'P0002');
end $p2$;

-- ===================== 03. El contenido =====================
do $p3$
declare A uuid := pg_temp.val('A')::uuid; B uuid := pg_temp.val('B')::uuid; d jsonb; e jsonb; v_seq bigint;
begin
  d := pg_temp.datos('ztran.sup@emdupar.gov.co', A);
  select seq into v_seq from campo.reportes where id = A;
  perform pg_temp.ok('03.01 identificador RAN-NNNNNN (su número RAN), número interno aparte, grupo, tipo y estado «Reportado»',
    d ->> 'identificador' = 'RAN-' || lpad((select numero from campo.reporte_ran where reporte_id = A)::text, 6, '0') and (d ->> 'numero_interno')::bigint = v_seq
    and d ->> 'tipo' = (select nombre from campo.tipos_reporte where codigo = 'otro') and d ->> 'estado' = 'Reportado' and d ->> 'grupo' is not null, left(d::text, 400));
  perform pg_temp.ok('03.02 reportó: el NOMBRE del operario (no el correo)', d ->> 'reporto' = 'ZTRAN Operario' and position('ztran.op@' in (d - 'fotos')::text) = 0, d ->> 'reporto');
  perform pg_temp.ok('03.03 sin nombre en la lista blanca: el correo', campo.f_ran_persona('ztran.nadie@emdupar.gov.co') = 'ztran.nadie@emdupar.gov.co'
    and campo.f_ran_persona('ZTRAN.SUP@emdupar.gov.co') = 'ZTRAN Supervisora');
  perform pg_temp.ok('03.04 contrato, dirección del contrato (base comercial) y dirección encontrada en terreno con barrio y referencia',
    d ->> 'contrato' = '991800000201' and d -> 'direccion_contrato' ->> 'comercial' is not null and d -> 'terreno' ->> 'direccion' = '[PRUEBA ZTRAN] CRA 9 # 12-32'
    and d -> 'terreno' ->> 'barrio' = 'CENTRO' and d -> 'terreno' ->> 'referencia' = 'Casa de rejas verdes', left(d::text, 600));
  perform pg_temp.ok('03.05 ubicación con precisión; foto de cámara con su origen; inicio, fin y duración',
    (d -> 'ubicacion' ->> 'precision_m')::numeric = 6 and jsonb_array_length(d -> 'fotos') = 1 and d -> 'fotos' -> 0 ->> 'etiqueta' like '% · tomada con la cámara'
    and d ->> 'fin' ~ '^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$' and d ? 'inicio' and d ? 'duracion', left(d::text, 600));
  perform pg_temp.ok('03.06 historial: «Reportado» por el operario', d -> 'historial' -> 0 ->> 'texto' = 'Reportado' and d -> 'historial' -> 0 ->> 'quien' = 'ZTRAN Operario');
  e := pg_temp.datos('ztran.sup@emdupar.gov.co', B);
  perform pg_temp.ok('03.07 galería y XY digitado: la foto dice su origen y la ubicación marca el XY con el punto de registro',
    e -> 'fotos' -> 0 ->> 'etiqueta' like '% · adjuntada desde la galería' and (e -> 'ubicacion' ->> 'xy_digitado')::boolean and (e -> 'ubicacion' ->> 'lat_registro')::numeric = 10.4762, left(e::text, 600));
  perform pg_temp.ok('03.08 sin firmas ni rutas sueltas: las únicas rutas son las de las fotos (para la Edge)',
    not (d ? 'firmas') and (select count(*) from jsonb_array_elements(d -> 'fotos') f where f ? 'ruta') = 1);
  perform pg_temp.guardar('sello_A1', d ->> 'sello');
end $p3$;

-- ===================== 04. Datos sensibles: nunca =====================
do $p4$
declare A uuid := pg_temp.val('A')::uuid; d jsonb;
begin
  insert into campo.reporte_datos_sensibles (reporte_id, datos, registrado_en) values (A, '{"telefono_contacto": "3009876543", "nombre_contacto": "ZTRAN CONTACTO SECRETO"}', clock_timestamp());
  d := pg_temp.datos('ztran.adm@emdupar.gov.co', A);
  perform pg_temp.ok('04.01 los datos sensibles no salen (ni al administrador) y no cambian el sello',
    position('3009876543' in d::text) = 0 and position('SECRETO' in d::text) = 0 and d ->> 'sello' = pg_temp.val('sello_A1'));
end $p4$;

-- ===================== 05. El mapa (capas reales) =====================
do $p5$
declare A uuid := pg_temp.val('A')::uuid; B uuid := pg_temp.val('B')::uuid; d jsonb; m jsonb; t0 timestamptz; v_ms numeric; v_fuera int;
begin
  t0 := clock_timestamp(); d := pg_temp.datos('ztran.sup@emdupar.gov.co', A); v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  m := d -> 'mapa';
  perform pg_temp.ok('05.01 el mapa trae red de acueducto alrededor del punto (ventana 400 × 200 m)',
    (m ->> 'ancho_m')::int = 400 and (m ->> 'alto_m')::int = 200 and (select count(*) from jsonb_array_elements(m -> 'lineas') l where l ->> 'capa' = 'acueducto') > 0, left(m::text, 300));
  perform pg_temp.ok('05.02 trae predios', jsonb_array_length(m -> 'predios') > 0, jsonb_array_length(m -> 'predios')::text);
  select count(*) into v_fuera from jsonb_array_elements(m -> 'lineas') l, jsonb_array_elements(l -> 'p') q where abs((q ->> 0)::numeric) > 200.05 or abs((q ->> 1)::numeric) > 100.05;
  select v_fuera + count(*) into v_fuera from jsonb_array_elements(m -> 'predios') q where abs((q ->> 0)::numeric) > 200.05 or abs((q ->> 1)::numeric) > 100.05;
  perform pg_temp.ok('05.03 todo queda recortado dentro de la ventana (metros relativos al punto)', v_fuera = 0, v_fuera::text);
  perform pg_temp.ok('05.04 la consulta con el mapa tarda menos de 3 s como service_role (con 30 s de tope)', v_ms < 3000, round(v_ms)::text || ' ms');
  m := pg_temp.datos('ztran.sup@emdupar.gov.co', B) -> 'mapa';
  perform pg_temp.ok('05.05 con XY digitado, el mapa trae el punto de registro (a unos 40 m)', jsonb_typeof(m -> 'registro') = 'array'
    and sqrt(power((m -> 'registro' ->> 0)::numeric, 2) + power((m -> 'registro' ->> 1)::numeric, 2)) between 20 and 80, (m -> 'registro')::text);
  m := campo.f_ran_mapa(4.6, -74.08);
  perform pg_temp.ok('05.06 un punto lejos de la ciudad: mapa vacío, sin error', jsonb_array_length(m -> 'lineas') = 0 and jsonb_array_length(m -> 'predios') = 0);
end $p5$;

-- ===================== 06. Generar, entregar y auditar =====================
do $p6$
declare A uuid := pg_temp.val('A')::uuid; SUP text := 'ztran.sup@emdupar.gov.co'; ADM text := 'ztran.adm@emdupar.gov.co'; d jsonb; r jsonb;
begin
  d := pg_temp.datos(SUP, A);
  perform pg_temp.ok('06.01 primera vez: versión 1, sin documento, nombre AAAAMMDDHHMMSS-RAN-NNNNNN.pdf y carpeta campo/AAAA-MM/<id>/',
    (d ->> 'version')::int = 1 and d -> 'documento' = 'null'::jsonb and d ->> 'nombre' ~ '^[0-9]{14}-RAN-[0-9]{6}\.pdf$'
    and d ->> 'carpeta' = 'campo/' || to_char((select registrado_en from campo.reportes where id = A) at time zone 'America/Bogota', 'YYYY-MM') || '/' || A || '/', d ->> 'carpeta');
  perform pg_temp.ok('06.02 registrar con un sello viejo: 409 (55000); con huella inválida: 400',
    pg_temp.err(pg_temp.registrar(SUP, A, repeat('0', 64))) = '55000' and pg_temp.err(pg_temp.registrar(SUP, A, d ->> 'sello', 'xyz')) = '22023');
  r := pg_temp.registrar(SUP, A, d ->> 'sello');
  perform pg_temp.ok('06.03 registrar: versión 1 nueva, auditada como generación', pg_temp.err(r) = 'OK' and (r ->> 'nuevo')::boolean and (r ->> 'version')::int = 1
    and pg_temp.audit(SUP, 'campo_ran_pdf_generar', A::text) = 1, r::text);
  r := pg_temp.registrar(ADM, A, d ->> 'sello', repeat('cd', 32));
  perform pg_temp.ok('06.04 otro registro del mismo sello: devuelve el primero (no hay otra versión) y se audita como descarga',
    not (r ->> 'nuevo')::boolean and r ->> 'sha256' = repeat('ab', 32) and (select count(*) from campo.reporte_pdf where reporte_id = A) = 1
    and pg_temp.audit(ADM, 'campo_ran_pdf_descargar', A::text) = 1, r::text);
  d := pg_temp.datos(ADM, A);
  perform pg_temp.ok('06.05 la siguiente consulta ve el documento y no arma el mapa', (d -> 'documento' ->> 'version')::int = 1 and d -> 'mapa' = 'null'::jsonb);
  r := pg_temp.obtener(SUP, A);
  perform pg_temp.ok('06.06 obtener: el mismo PDF, auditado', (r ->> 'version')::int = 1 and r ->> 'nombre' = d -> 'documento' ->> 'nombre' and pg_temp.audit(SUP, 'campo_ran_pdf_descargar', A::text) = 1, r::text);
  perform pg_temp.ok('06.07 la fila guarda quién lo generó, el sello, el tamaño, las fotos omitidas y la ruta con el sha256',
    exists (select 1 from campo.reporte_pdf where reporte_id = A and version = 1 and generado_por = SUP and sello = d ->> 'sello' and bytes = 150000 and fotos_omitidas = 0
            and ruta = (d ->> 'carpeta') || left(repeat('ab', 32), 16) || '/' || (d ->> 'nombre')));
end $p6$;

-- ===================== 07. Versión nueva solo si cambia el sello =====================
do $p7$
declare A uuid := pg_temp.val('A')::uuid; SUP text := 'ztran.sup@emdupar.gov.co'; d jsonb; r jsonb;
begin
  r := pg_temp.rpc(format('public.geoportal_campo_cambiar_estado(%L, %L::uuid, ''en_revision'', ''[PRUEBA ZTRAN] se revisa en terreno'', null)', SUP, A));
  perform pg_temp.ok('07.01 la supervisora cambia el estado', pg_temp.err(r) = 'OK', r::text);
  d := pg_temp.datos(SUP, A);
  perform pg_temp.ok('07.02 cambió el sello: versión 2, sin documento, nombre con -v2; el historial lo dice con su nombre',
    d ->> 'sello' <> pg_temp.val('sello_A1') and (d ->> 'version')::int = 2 and d -> 'documento' = 'null'::jsonb and d ->> 'nombre' ~ '-v2\.pdf$'
    and d -> 'historial' -> 1 ->> 'texto' = 'Cambio de estado a En revisión · [PRUEBA ZTRAN] se revisa en terreno' and d -> 'historial' -> 1 ->> 'quien' = 'ZTRAN Supervisora'
    and d ->> 'estado' = 'En revisión', left((d -> 'historial')::text, 400));
  perform pg_temp.ok('07.03 obtener responde 404 hasta generar la versión vigente', pg_temp.err(pg_temp.obtener(SUP, A)) = 'P0002');
  r := pg_temp.registrar(SUP, A, d ->> 'sello', repeat('ef', 32));
  perform pg_temp.ok('07.04 la versión 2 queda; la 1 sigue igual', (r ->> 'version')::int = 2 and (r ->> 'nuevo')::boolean
    and (select count(*) from campo.reporte_pdf where reporte_id = A) = 2 and exists (select 1 from campo.reporte_pdf where reporte_id = A and version = 1 and sha256 = repeat('ab', 32)), r::text);
  d := pg_temp.datos(SUP, A);
  perform pg_temp.ok('07.05 sin otro cambio, se entrega la versión 2', (d -> 'documento' ->> 'version')::int = 2);
end $p7$;

-- ===================== 08. Solo inserción y reglas de producción =====================
do $p8$
declare v_ok boolean;
begin
  begin update campo.reporte_pdf set bytes = bytes where reporte_id = pg_temp.val('A')::uuid; v_ok := false; exception when others then v_ok := true; end;
  perform pg_temp.ok('08.01 campo.reporte_pdf no se modifica (UPDATE rechazado)', v_ok);
  begin delete from campo.reporte_pdf where reporte_id = pg_temp.val('A')::uuid; v_ok := false; exception when others then v_ok := true; end;
  perform pg_temp.ok('08.02 ni se borra (DELETE rechazado)', v_ok);
  perform pg_temp.ok('08.03 ninguna función de campo con DELETE o UPDATE sin WHERE', (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0);
  perform pg_temp.ok('08.04 redes.f_funciones_sin_where() devuelve cero filas', (select count(*) from redes.f_funciones_sin_where()) = 0);
end $p8$;

-- ===================== REVERSA =====================
-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov) · 90 — REVERSA
-- Quita las 9 funciones de este paquete; la huella de campo vuelve a 9f8b8ec55fc7e1c56fdf74a5f4e7f3c4. NADA SE BORRA: campo.reporte_pdf y campo.reporte_ran (con sus filas) y los PDF del bucket
-- se conservan. Sin estas funciones, la Edge responde que la ruta no está disponible y la pantalla lo dice; no se rompe nada más.
-- =====================================================================
do $rev$
declare r record; v_n bigint;
begin
  for r in select * from (values ('campo.f_ran_numerar(uuid)', '0898fb8ef37395807d1840793995f410'), ('campo.f_ran_autorizar(text,uuid)', '2ad5312a05781ae680593c77f3567996'), ('campo.f_ran_persona(text)', '878cb032577259fc99a65a88a895e705'), ('campo.f_ran_contenido(uuid)', '28030cb66dc32ba930bd0221c5e3dfed'), ('campo.f_ran_destino(uuid,text)', '13b97f29ab83affef654dc8dfa662ba3'), ('campo.f_ran_mapa(numeric,numeric,numeric,numeric)', 'bb39c53123e8c511bf06315a3b07db1a'), ('public.geoportal_campo_ran_datos(text,uuid,text)', '9930d5e29c50156477392e6023319068'), ('public.geoportal_campo_ran_registrar(text,uuid,text,text,integer,integer,text)', 'e74aa08891b6578297c9ce365b1e94ee'), ('public.geoportal_campo_ran_obtener(text,uuid,text)', 'c131b87deffb9c5f32df5a61ba548f95')) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise', r.f;
    end if;
  end loop;
  select count(*) into v_n from campo.reporte_pdf;
  raise notice 'Reversa del PDF de Reportar anomalía: % versiones de PDF quedan en campo.reporte_pdf', v_n;
end $rev$;
-- DROP (por qué y alcance): las 9 funciones las creó este paquete y nada publicado las usa. Alcance: SOLO esas 9 firmas; no toca tablas ni datos.
drop function public.geoportal_campo_ran_obtener(text, uuid, text);
drop function public.geoportal_campo_ran_registrar(text, uuid, text, text, integer, integer, text);
drop function public.geoportal_campo_ran_datos(text, uuid, text);
drop function campo.f_ran_mapa(numeric, numeric, numeric, numeric);
drop function campo.f_ran_destino(uuid, text);
drop function campo.f_ran_contenido(uuid);
drop function campo.f_ran_persona(text);
drop function campo.f_ran_autorizar(text, uuid);
drop function campo.f_ran_numerar(uuid);


-- ===================== 09. Después de la reversa =====================
do $p9$
begin
  perform pg_temp.ok('09.01 la huella de campo vuelve a la de partida', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text collate "C", p.proname, p.oid::regprocedure::text collate "C")) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) = '9f8b8ec55fc7e1c56fdf74a5f4e7f3c4');
  perform pg_temp.ok('09.02 las RPC ya no están; nada se borró: las 2 versiones y los números RAN siguen', to_regprocedure('public.geoportal_campo_ran_datos(text,uuid,text)') is null
    and (select count(*) from campo.reporte_pdf where reporte_id = pg_temp.val('A')::uuid) = 2 and exists (select 1 from campo.reporte_ran where reporte_id = pg_temp.val('D')::uuid));
end $p9$;

do $fin$
declare v_b integer; v_t integer; v_fallas text;
begin
  select count(*) filter (where ok), count(*), string_agg('FALLA ' || nombre || coalesce(' → ' || detalle, ''), E'\n' order by n) filter (where not ok) into v_b, v_t, v_fallas from ztran_res;
  raise exception E'ENSAYO TERMINADO (ERROR esperado: todo se deshace). RESULTADO: % de % pruebas correctas%', v_b, v_t,
    case when v_b = v_t then ' — SIN FALLAS' else E'\n' || v_fallas end;
end $fin$;

rollback;
