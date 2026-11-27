-- [Code A] PDF DE «REPORTAR ANOMALÍA» (27-nov) · MIGRACIÓN (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
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
  -- capas de los dos mapas (paso 0 de producción, David, 27-nov): clase, geometría y su índice GiST con la definición EXACTA
  for r in select * from (values
      ('public.redes_acueducto', 'r', 'CREATE INDEX idx_redes_acu_geom ON public.redes_acueducto USING gist (geom)'),
      ('public.redes_alcantarillado', 'r', 'CREATE INDEX idx_redes_alc_geom ON public.redes_alcantarillado USING gist (geom)'),
      ('public.predios_comercial', 'm', 'CREATE INDEX idx_predcom_geom_n ON public.predios_comercial USING gist (geom)'),
      ('public.catastro_valledupar', 'r', 'CREATE INDEX idx_catastro_geom ON public.catastro_valledupar USING gist (geom)'),
      ('public.terrenos_valledupar', 'r', 'CREATE INDEX terrenos_valledupar_geom_geom_idx ON public.terrenos_valledupar USING gist (geom)'),
      ('public.barrios_valledupar', 'r', 'CREATE INDEX idx_barrios_geom ON public.barrios_valledupar USING gist (geom)'),
      ('tecnica.elementos_planta', 'r', 'CREATE INDEX ix_elementos_planta_geom ON tecnica.elementos_planta USING gist (geom)')) x(t, k, i) loop
    if to_regclass(r.t) is null or (select relkind::text from pg_class where oid = to_regclass(r.t)) <> r.k then
      raise exception 'La capa % no existe o no es de la clase esperada (%): deténgase y avise', r.t, r.k;
    end if;
    if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass(r.t) and a.attname = 'geom' and not a.attisdropped and format_type(a.atttypid, a.atttypmod) like 'geometry%') then
      raise exception 'La capa % no tiene la columna geom (geometry): deténgase y avise', r.t;
    end if;
    if not exists (select 1 from pg_index i where i.indrelid = to_regclass(r.t) and pg_get_indexdef(i.indexrelid) = r.i) then
      raise exception 'Falta el índice GiST de % con la definición «%»: deténgase y avise', r.t, r.i;
    end if;
  end loop;
  -- las columnas de las capas que se leen (de predios_comercial SOLO cod_usuario y sin_contrato)
  for r in select * from (values ('public.predios_comercial', 'cod_usuario', 'text'), ('public.predios_comercial', 'sin_contrato', 'boolean'),
                                 ('public.barrios_valledupar', 'nombre', 'text'), ('tecnica.elementos_planta', 'tipo', 'text'),
                                 ('tecnica.elementos_planta', 'codigo', 'text'), ('tecnica.elementos_planta', 'activo', 'boolean')) x(t, c, ty) loop
    if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass(r.t) and a.attname = r.c and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = r.ty) then
      raise exception 'La columna %.% no existe o no es %: deténgase y avise', r.t, r.c, r.ty;
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
declare v campo.v_reportes_estado%rowtype; v_rr campo.reporte_registro; v_dc campo.reporte_direccion_contrato; r jsonb; v_resp jsonb;
        f_hora constant text := 'DD/MM/YYYY HH24:MI';
begin
  select * into v from campo.v_reportes_estado where id = p_id;
  if not found then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  select * into v_rr from campo.reporte_registro where reporte_id = p_id;
  select * into v_dc from campo.reporte_direccion_contrato where reporte_id = p_id;
  -- Respuestas propias del tipo (27-nov, David: «todo lo que el operario registró»): las mismas que el detalle de Supervisión y el Excel (campo.tipo_campos, en el orden
  -- del formulario, con su etiqueta), las activas siempre (con «—» si no hay respuesta) y las inactivas si tienen respuesta; las claves de `datos` sin definición van al final
  -- con su código. NUNCA las sensibles (ni su definición ni campo.reporte_datos_sensibles). Hoy los tipos de «Reportar anomalía» no tienen preguntas propias: sale vacío.
  with c as (
    select c.codigo, c.nombre, c.unidad, c.tipo_dato, c.opciones, c.orden, c.id, c.activo, v.datos -> c.codigo as val
      from campo.tipo_campos c where c.tipo_id = v.tipo_id and not coalesce(c.sensible, false) and (c.activo or v.datos ? c.codigo)
  )
  select coalesce(jsonb_agg(x.par order by x.o1, x.o2, x.o3), '[]'::jsonb) into v_resp from (
    select 0 as o1, c.orden as o2, c.id::text as o3, jsonb_build_array(c.nombre || coalesce(' (' || c.unidad || ')', ''),
             case when c.val is null or c.val = 'null'::jsonb or c.val = '""'::jsonb then '—'
                  when c.tipo_dato = 'si_no' then case when c.val = 'true'::jsonb then 'Sí' when c.val = 'false'::jsonb then 'No' else c.val #>> '{}' end
                  when c.tipo_dato = 'opcion' then coalesce((select o ->> 'nombre' from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = c.val #>> '{}'), c.val #>> '{}')
                  when c.tipo_dato = 'opciones' then coalesce((select string_agg(coalesce((select o ->> 'nombre' from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = e), e), '; ')
                                                               from jsonb_array_elements_text(case when jsonb_typeof(c.val) = 'array' then c.val else '[]'::jsonb end) e), '—')
                  when c.tipo_dato = 'dia_hora' then replace(c.val #>> '{}', 'T', ' ')
                  when c.tipo_dato in ('entero', 'decimal') then replace(c.val #>> '{}', '.', ',')
                  else c.val #>> '{}' end) as par
      from c
    union all
    select 1, 0, k.key, jsonb_build_array(k.key, coalesce(k.value #>> '{}', '—'))
      from jsonb_each(coalesce(v.datos, '{}'::jsonb)) k
     where not exists (select 1 from campo.tipo_campos c where c.tipo_id = v.tipo_id and c.codigo = k.key)
  ) x;
  select jsonb_build_object(
    'identificador', (select 'RAN-' || case when n.numero < 1000000 then lpad(n.numero::text, 6, '0') else n.numero::text end from campo.reporte_ran n where n.reporte_id = p_id),
    'numero_interno', v.seq,
    'grupo', g.nombre, 'tipo', t.nombre, 'subtipo', s.nombre,
    'estado', coalesce((select e.nombre from campo.estados_reporte e where e.codigo = v.estado), v.estado),
    'oculto', v.oculto, 'riesgo_inmediato', v.riesgo_inmediato, 'fuera_de_zona', v.fuera_de_zona,
    'resultado', case v.resultado when 'efectivo' then 'Efectivo' when 'inefectivo' then 'Inefectivo' else v.resultado end
                 || coalesce(' · ' || (select ca.nombre from campo.causales ca where ca.id = v.causal_id), ''),
    'origen', case v.origen when 'campo' then 'Campo' when 'escritorio' then 'Escritorio' else v.origen end,
    'orden_trabajo_id', v.orden_trabajo_id,
    'contrato', v.contrato, 'contrato_verificado', v.contrato_verificado,
    'direccion_contrato', case when v_dc.reporte_id is not null then jsonb_build_object(
        'comercial', v_dc.direccion_comercial, 'barrio_comercial', v_dc.barrio_comercial, 'catastro', v_dc.direccion_catastro, 'barrio_catastro', v_dc.barrio_catastro) end,
    'terreno', case when v_rr.reporte_id is not null and coalesce(v_rr.direccion, v_rr.barrio, v_rr.referencia) is not null then jsonb_build_object(
        'direccion', v_rr.direccion, 'barrio', v_rr.barrio, 'referencia', v_rr.referencia) end,
    'ubicacion', jsonb_build_object('lat', v.lat, 'lon', v.lon, 'precision_m', v.precision_m,
        'registro', case when v_rr.reporte_id is null then null when v_rr.xy_manual then 'XY digitado — registrado desde otro punto' else 'En el sitio (GPS)' end
                    || case when v_rr.reporte_id is not null and v_rr.lat_registro is null then ' · sin ubicación del dispositivo' else '' end,
        'xy_digitado', coalesce(v_rr.xy_manual, false), 'sin_ubicacion_dispositivo', v_rr.reporte_id is not null and v_rr.lat_registro is null,
        'lat_registro', v_rr.lat_registro, 'lon_registro', v_rr.lon_registro, 'precision_registro_m', v_rr.precision_registro_m,
        'distancia_registro_m', case when v_rr.lat_registro is not null then round(st_distance(v.geom::geography,
                                  st_setsrid(st_makepoint(v_rr.lon_registro::double precision, v_rr.lat_registro::double precision), 4326)::geography)::numeric, 1) end),
    'descripcion', v.descripcion,
    'respuestas', v_resp,
    'reporto', campo.f_ran_persona(v.autor),
    'inicio', to_char(v.inicio_en at time zone 'America/Bogota', f_hora) || case v.inicio_origen when 'dispositivo' then ' (celular)' else '' end,   -- como textoInicio del detalle
    'fin', to_char(v.registrado_en at time zone 'America/Bogota', f_hora),
    'duracion_s', case when v.inicio_en is not null then round(extract(epoch from v.registrado_en - v.inicio_en)::numeric, 1) end,   -- la Edge la escribe como el detalle (fmtDuracion)
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

-- Los DOS mapas del PDF (David, 27-nov), vectoriales, en metros (MAGNA-SIRGAS Bogotá, 3116) relativos al punto del reporte (x al este, y al norte):
--   cercano  (120 × 60 m): terrenos (solo polígonos, sin label), redes de acueducto y alcantarillado, predios de predios_comercial con su cod_usuario (= contrato; los
--            sin_contrato van sin número), elementos ACTIVOS de Técnica con su tipo, el punto y el XY digitado;
--   contexto (400 × 200 m): barrios (con su nombre), redes y predios sin labels, el punto y el XY digitado.
-- De predios_comercial SOLO la geometría, cod_usuario y sin_contrato (nada de deuda, consumo ni cartera). Todo por los índices GiST de producción (filtro &&).
-- Topes por capa para que el PDF no crezca sin control. Sin teselas ni servicios externos.
create function campo.f_ran_mapa(p_lat numeric, p_lon numeric, p_lat_reg numeric default null, p_lon_reg numeric default null) returns jsonb
language plpgsql stable security definer set search_path = public, campo, tecnica, pg_temp as $$
declare v_c geometry; v_x0 double precision; v_y0 double precision; v_reg jsonb; v_cerca jsonb; v_ctx jsonb; v_ax double precision; v_ay double precision; v_env geometry; v_env_g geometry;
        v_terr jsonb; v_lin jsonb; v_pred jsonb; v_elem jsonb; v_barr jsonb; v_barrio text;
begin
  if p_lat is null or p_lon is null then return null; end if;
  v_c := st_transform(st_setsrid(st_makepoint(p_lon::double precision, p_lat::double precision), 4326), 3116);
  v_x0 := st_x(v_c); v_y0 := st_y(v_c);
  if p_lat_reg is not null and p_lon_reg is not null then
    select jsonb_build_array(round((st_x(q) - v_x0)::numeric, 1), round((st_y(q) - v_y0)::numeric, 1)) into v_reg
      from (select st_transform(st_setsrid(st_makepoint(p_lon_reg::double precision, p_lat_reg::double precision), 4326), 3116) as q) z;
  end if;
  select b.nombre into v_barrio from public.barrios_valledupar b where b.geom && st_transform(v_c, 4326) and st_intersects(b.geom, st_transform(v_c, 4326)) order by b.id limit 1;

  -- ===== cercano: 120 × 60 m =====
  v_ax := 60; v_ay := 30;
  v_env := st_makeenvelope(v_x0 - v_ax, v_y0 - v_ay, v_x0 + v_ax, v_y0 + v_ay, 3116); v_env_g := st_transform(v_env, 4326);
  select coalesce(jsonb_agg(st_asgeojson(st_translate(x.g, -v_x0, -v_y0), 1)::jsonb -> 'coordinates'), '[]'::jsonb) into v_terr
    from (select st_multi(st_collectionextract(st_simplify(st_intersection(st_transform(t.geom, 3116), v_env), 0.2), 3)) as g
            from public.terrenos_valledupar t where t.geom && v_env_g limit 400) x where not st_isempty(x.g);
  with l as (select 'acueducto'::text as capa, a.geom from public.redes_acueducto a where a.geom && v_env_g
             union all select 'alcantarillado', b.geom from public.redes_alcantarillado b where b.geom && v_env_g),
       c as (select l.capa, (st_dump(st_collectionextract(st_simplify(st_intersection(st_transform(l.geom, 3116), v_env), 0.2), 2))).geom as g from l)
  select coalesce(jsonb_agg(jsonb_build_object('capa', c.capa, 'p', st_asgeojson(st_translate(c.g, -v_x0, -v_y0), 1)::jsonb -> 'coordinates') order by c.capa), '[]'::jsonb) into v_lin
    from (select * from c where not st_isempty(c.g) and st_npoints(c.g) >= 2 limit 600) c;
  select coalesce(jsonb_agg(jsonb_build_object('p', jsonb_build_array(round((st_x(x.t) - v_x0)::numeric, 1), round((st_y(x.t) - v_y0)::numeric, 1)),
                                               'cod', case when x.sin then null else x.cod end, 'sin', x.sin)
                            order by st_distance(x.t, v_c)), '[]'::jsonb) into v_pred
    from (select st_transform(p.geom, 3116) as t, nullif(btrim(p.cod_usuario), '') as cod, coalesce(p.sin_contrato, false) as sin
            from public.predios_comercial p where p.geom && v_env_g limit 1500) x
   where st_intersects(x.t, v_env);
  select coalesce(jsonb_agg(jsonb_build_object('tipo', x.tipo, 'g', st_asgeojson(st_translate(x.g, -v_x0, -v_y0), 1)::jsonb,
                                               'ancla', jsonb_build_array(round((st_x(st_pointonsurface(x.g)) - v_x0)::numeric, 1), round((st_y(st_pointonsurface(x.g)) - v_y0)::numeric, 1)))
                            order by x.tipo, x.codigo), '[]'::jsonb) into v_elem
    from (select e.tipo, e.codigo, st_intersection(st_transform(e.geom, 3116), v_env) as g
            from tecnica.elementos_planta e where e.activo and e.geom && v_env_g limit 300) x where not st_isempty(x.g);
  v_cerca := jsonb_build_object('ancho_m', 2 * v_ax, 'alto_m', 2 * v_ay, 'terrenos', v_terr, 'lineas', v_lin, 'predios', v_pred, 'elementos', v_elem, 'registro', v_reg);

  -- ===== contexto: 400 × 200 m =====
  v_ax := 200; v_ay := 100;
  v_env := st_makeenvelope(v_x0 - v_ax, v_y0 - v_ay, v_x0 + v_ax, v_y0 + v_ay, 3116); v_env_g := st_transform(v_env, 4326);
  select coalesce(jsonb_agg(jsonb_build_object('nombre', x.nombre, 'propio', x.nombre is not distinct from v_barrio,
                                               'g', st_asgeojson(st_translate(x.g, -v_x0, -v_y0), 1)::jsonb -> 'coordinates',
                                               'ancla', jsonb_build_array(round((st_x(st_pointonsurface(x.g)) - v_x0)::numeric, 1), round((st_y(st_pointonsurface(x.g)) - v_y0)::numeric, 1)))
                            order by x.nombre), '[]'::jsonb) into v_barr
    from (select b.nombre, st_multi(st_collectionextract(st_simplify(st_intersection(st_transform(b.geom, 3116), v_env), 1), 3)) as g
            from public.barrios_valledupar b where b.geom && v_env_g limit 60) x where not st_isempty(x.g);
  with l as (select 'acueducto'::text as capa, a.geom from public.redes_acueducto a where a.geom && v_env_g
             union all select 'alcantarillado', b.geom from public.redes_alcantarillado b where b.geom && v_env_g),
       c as (select l.capa, (st_dump(st_collectionextract(st_simplify(st_intersection(st_transform(l.geom, 3116), v_env), 0.5), 2))).geom as g from l)
  select coalesce(jsonb_agg(jsonb_build_object('capa', c.capa, 'p', st_asgeojson(st_translate(c.g, -v_x0, -v_y0), 1)::jsonb -> 'coordinates') order by c.capa), '[]'::jsonb) into v_lin
    from (select * from c where not st_isempty(c.g) and st_npoints(c.g) >= 2 limit 1500) c;
  select coalesce(jsonb_agg(jsonb_build_object('p', jsonb_build_array(round((st_x(x.t) - v_x0)::numeric, 1), round((st_y(x.t) - v_y0)::numeric, 1)), 'cod', null, 'sin', x.sin)), '[]'::jsonb) into v_pred
    from (select st_transform(p.geom, 3116) as t, coalesce(p.sin_contrato, false) as sin from public.predios_comercial p where p.geom && v_env_g limit 4000) x
   where st_intersects(x.t, v_env);
  v_ctx := jsonb_build_object('ancho_m', 2 * v_ax, 'alto_m', 2 * v_ay, 'barrios', v_barr, 'barrio', v_barrio, 'lineas', v_lin, 'predios', v_pred, 'registro', v_reg);

  return jsonb_build_object('cercano', v_cerca, 'contexto', v_ctx);
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

commit;
