begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 10 — GUARDIA Y ESTRUCTURA: reportes compartidos con Comercial (§10 y §30.3-4 de la bitácora; precisión de David, 16-nov)
-- PROPUESTA. No se ha ejecutado en la base real (solo en un PostgreSQL local con los paquetes de campo hasta la pasada del 14-nov y el Corte 1 de Técnica).
-- Regla de este corte: el formulario, las tablas y la Edge son LOS MISMOS de Comercial (esquema campo, geoportal-campo). No se crea ninguna tabla.
-- No se modifica ni se borra ningún registro existente de las tablas de campo: solo se agrega.
-- · campo.reportes: UNA columna nueva, «area» (nula = Comercial; 'tecnica' = hecho desde Técnica). Agregar una columna nula no reescribe ni cambia ninguna fila.
-- · ⚠ campo.f_autorizar_reporte (viva): una sola condición más, con guardia md5 y su texto exacto en la reversa.
-- · ⚠ tecnica.formulario_clave (dominio vivo) y tecnica.f_formularios (viva): dos claves más, «anomalia_compartida» y «revision_compartida».
-- · campo.tipos_reporte: se AGREGAN «Fuga en acometida» y «Caja de medidor dañada» solo si no existen; los 26 tipos actuales no se tocan.
-- · redes.v_reportes_comercial (del 6b, vacía): se reemplaza la vista (mismas columnas). Ninguna función de redes cambia.
-- =====================================================================
do $$
begin
  if to_regclass('campo.reportes') is null or to_regprocedure('campo.f_autorizar_reporte(text)') is null or to_regprocedure('campo.f_perfil(text)') is null then
    raise exception 'Falta el esquema campo (Formatos de campo): deténgase y avise';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'campo' and table_name = 'reportes' and column_name = 'area')
     or to_regprocedure('campo.f_tecnica_claves(text)') is not null then
    raise exception 'El Corte 8 ya está aplicado (campo.reportes ya tiene «area»): deténgase y avise';
  end if;
  if md5(pg_get_functiondef('campo.f_autorizar_reporte(text)'::regprocedure)) <> 'aac8af95274e11b2f3e5ed1eb1e5025a' then
    raise exception 'campo.f_autorizar_reporte no es la del Paso A de campo: deténgase y avise';
  end if;
  if (select count(*) from pg_proc p where p.oid in (to_regprocedure('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)'),
        to_regprocedure('public.geoportal_campo_preparar_subida(text,integer,text,text,text)'), to_regprocedure('public.geoportal_campo_obtener_formulario(text,boolean)'))) <> 3 then
    raise exception 'Las RPC de campo (crear, preparar la subida y el formulario) no tienen las firmas esperadas (pasada del 14-nov): deténgase y avise';
  end if;
  if to_regclass('campo.v_reportes_estado') is null or to_regclass('campo.tipos_reporte') is null or to_regclass('campo.grupos_reporte') is null
     or not exists (select 1 from campo.tipos_reporte where codigo = 'revision_previa')
     or not exists (select 1 from campo.grupos_reporte where codigo = 'red_acueducto') then
    raise exception 'El catálogo de campo no es el esperado (falta revision_previa, el grupo red_acueducto o la vista de estados): deténgase y avise';
  end if;
  if to_regtype('tecnica.formulario_clave') is null or to_regprocedure('tecnica.f_autorizar_captura(text,text)') is null
     or md5(pg_get_functiondef('tecnica.f_formularios()'::regprocedure)) <> '11b0b586919d0d7240d1dd84f3edbe6b' then
    raise exception 'tecnica.f_formularios o el dominio de formularios de Técnica no son los del Corte 1 de planta: deténgase y avise';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') <> 'CHECK ((VALUE = ANY (ARRAY[''entrada''::text, ''salida''::text, ''muestreo''::text, ''danos_fallas''::text, ''mantenimiento''::text, ''uso_quimicos''::text, ''entrada_quimicos''::text])))' then
    raise exception 'El dominio tecnica.formulario_clave no tiene las 7 claves esperadas: deténgase y avise';
  end if;
  if to_regclass('redes.v_reportes_comercial') is null
     or (select string_agg(column_name || ':' || data_type, ',' order by ordinal_position) from information_schema.columns where table_schema = 'redes' and table_name = 'v_reportes_comercial')
        <> 'codigo:text,tipo:text,subtipo:text,area:text,con_contrato:boolean,estado:text,registrado_en:timestamp with time zone,lat:numeric,lon:numeric' then
    raise exception 'Falta redes.v_reportes_comercial (Corte 6b) o no tiene las columnas esperadas: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. EL ÁREA DEL REGISTRO, en la misma tabla. Nula = Comercial (todo lo que ya existe y lo que Comercial siga haciendo). 'tecnica' = hecho desde Técnica.
--    La columna se llena sola al insertar: su valor por omisión mira la marca de la transacción que solo ponen las 3 RPC nuevas (20_funciones).
--    Primero la columna (sin valor por omisión: no toca ninguna fila) y después el valor por omisión (solo para lo que se inserte en adelante).
-- ---------------------------------------------------------------------
alter table campo.reportes add column area text;
alter table campo.reportes add constraint reportes_area_ck check (area is null or area = 'tecnica');
alter table campo.reportes alter column area set default (case when current_setting('geoportal.via_tecnica', true) = 'on' then 'tecnica' end);
comment on column campo.reportes.area is 'Corte 8 de Técnica: área que hizo el reporte. Nulo = Comercial; tecnica = hecho desde Técnica (entrada del modo Redes).';

-- ---------------------------------------------------------------------
-- 2. LAS DOS CLAVES NUEVAS DE TÉCNICA: se asignan en Personal como cualquier formulario (la captura la restringe tecnica.f_autorizar_captura).
-- ---------------------------------------------------------------------
alter domain tecnica.formulario_clave drop constraint formulario_clave_ck;
alter domain tecnica.formulario_clave add constraint formulario_clave_ck check (value in
  ('entrada', 'salida', 'muestreo', 'danos_fallas', 'mantenimiento', 'uso_quimicos', 'entrada_quimicos', 'anomalia_compartida', 'revision_compartida'));

-- ---------------------------------------------------------------------
-- 3. EL CATÁLOGO ES EL MISMO (§30.3): se agregan dos tipos al grupo «red_acueducto», solo si no existe ya uno con ese nombre. Los demás no se tocan.
--    Son del reporte general (sin campos propios ni consecutivo), con contrato opcional, como los otros del grupo.
-- ---------------------------------------------------------------------
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden)
select g.id, x.codigo, x.nombre, (select coalesce(max(t.orden), 0) from campo.tipos_reporte t where t.grupo_id = g.id) + x.n
  from campo.grupos_reporte g, (values (1, 'fuga_acometida', 'Fuga en acometida', '%fuga%acometida%'), (2, 'caja_medidor_danada', 'Caja de medidor dañada', '%caja%medidor%da_ad%')) x(n, codigo, nombre, parecido)
 where g.codigo = 'red_acueducto'
   and not exists (select 1 from campo.tipos_reporte t where lower(t.nombre) like x.parecido or t.codigo = x.codigo);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 20 — FUNCIONES
--   · campo.f_tipo_general: «Reportar anomalía» = los tipos que NO son formato de actividad (la misma regla de la pantalla y de campo.f_formularios_personal).
--   · campo.f_tecnica_claves: qué formularios compartidos tiene la persona en Técnica (lo decide tecnica.f_autorizar_captura, sin copiar su lógica).
--   · campo.f_tecnica_entrar: autoriza la entrada desde Técnica para un tipo y pone la marca de la transacción.
--   · 3 RPC nuevas que llama la MISMA Edge geoportal-campo cuando la pantalla se abre desde Técnica (?area=tecnica): formulario, preparar la subida y crear.
--     Cada una autoriza por Técnica y llama a la RPC de campo de siempre, en la misma transacción. El reporte queda en campo.reportes con area = 'tecnica'.
--   · ⚠ campo.f_autorizar_reporte: una condición más (la marca). Sin la marca se comporta exactamente como antes.
--   · tecnica.f_formularios: los dos formularios compartidos, para asignarlos en Personal y que salgan en el inicio de Técnica.
-- =====================================================================
create function campo.f_tipo_general(p_codigo text) returns boolean
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select exists (select 1 from campo.tipos_reporte t
                  where t.codigo = p_codigo
                    and not (exists (select 1 from campo.tipo_campos c where c.tipo_id = t.id and c.activo) or exists (select 1 from campo.tipo_fotos f where f.tipo_id = t.id and f.activo)
                             or t.genera_resultado or t.prefijo_consecutivo is not null)) $$;

create function campo.f_tecnica_claves(p_solicitante text) returns text[]
language plpgsql security definer set search_path to 'public', 'campo', 'tecnica', 'pg_temp' as $$
declare v text[] := '{}'; k text;
begin
  foreach k in array array['anomalia_compartida', 'revision_compartida'] loop
    begin
      perform tecnica.f_autorizar_captura(p_solicitante, k);
      v := v || k;
    exception when insufficient_privilege then null;      -- no tiene ese formulario: se sigue con el otro
    end;
  end loop;
  return v;
end $$;

-- Autoriza por Técnica el tipo pedido (nulo = el reporte general) y pone la marca. Devuelve el correo. Cada RPC apaga la marca al volver de la RPC de campo.
create function campo.f_tecnica_entrar(p_solicitante text, p_tipo text) returns text
language plpgsql security definer set search_path to 'public', 'campo', 'tecnica', 'pg_temp' as $$
declare v_email text; v_clave text;
begin
  v_clave := case when p_tipo = 'revision_previa' then 'revision_compartida'
                  when p_tipo is null or campo.f_tipo_general(p_tipo) then 'anomalia_compartida' end;
  if v_clave is null then raise exception 'Ese formato no se llena desde Técnica' using errcode = '42501'; end if;
  v_email := tecnica.f_autorizar_captura(p_solicitante, v_clave);
  perform set_config('geoportal.via_tecnica', 'on', true);      -- solo dura esta transacción; solo la ponen estas funciones (nadie de la API las ejecuta salvo la Edge)
  return v_email;
end $$;

-- El formulario, como lo ve un reportante, solo con lo que la persona tiene en Técnica: los tipos del reporte general y/o «Revisiones generales».
create function public.geoportal_campo_tec_formulario(p_solicitante text) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'tecnica', 'pg_temp' as $$
declare v_claves text[] := campo.f_tecnica_claves(p_solicitante); v jsonb;
begin
  if cardinality(v_claves) = 0 then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  perform set_config('geoportal.via_tecnica', 'on', true);
  v := public.geoportal_campo_obtener_formulario(p_solicitante, false);
  perform set_config('geoportal.via_tecnica', '', true);      -- la marca se apaga en cuanto vuelve la RPC de campo
  return jsonb_build_object(
    'perfil', 'reportante', 'area', 'tecnica', 'formularios', to_jsonb(v_claves),
    'puede', jsonb_build_object('reportar', true, 'crear_desde_escritorio', false, 'supervisar', false, 'administrar_catalogo', false),
    'limites', v -> 'limites', 'zona', v -> 'zona',
    'estados', null, 'causales', null, 'definiciones', null, 'parametros', null,
    'grupos', coalesce((
      select jsonb_agg(g.j || jsonb_build_object('tipos', g.tipos) order by g.n)
        from (select x.j - 'tipos' as j, x.n,
                     (select jsonb_agg(t.j order by t.n) from jsonb_array_elements(x.j -> 'tipos') with ordinality t(j, n)
                       where ('anomalia_compartida' = any (v_claves) and campo.f_tipo_general(t.j ->> 'codigo'))
                          or ('revision_compartida' = any (v_claves) and t.j ->> 'codigo' = 'revision_previa')) as tipos
                from jsonb_array_elements(v -> 'grupos') with ordinality x(j, n)) g
       where g.tipos is not null), '[]'::jsonb));
end $$;

create function public.geoportal_campo_tec_preparar_subida(p_solicitante text, p_cantidad integer, p_ip text default null, p_tipo text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'tecnica', 'pg_temp' as $$
declare v jsonb;
begin
  perform campo.f_tecnica_entrar(p_solicitante, p_tipo);
  v := public.geoportal_campo_preparar_subida(p_solicitante, p_cantidad, 'campo', p_ip, p_tipo);
  perform set_config('geoportal.via_tecnica', '', true);
  return v;
end $$;

-- Mismos datos que el crear de campo (sin «origen»: desde Técnica siempre es captura en campo; sin orden de trabajo: las órdenes son de Comercial).
create function public.geoportal_campo_tec_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text,
  p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_fotos jsonb,
  p_ip text default null, p_datos jsonb default null, p_resultado text default null, p_causal text default null, p_inicio_dispositivo timestamptz default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'campo', 'tecnica', 'pg_temp' as $$
declare v jsonb;
begin
  if p_tipo is null then raise exception 'Falta el tipo de reporte' using errcode = '22023'; end if;
  perform campo.f_tecnica_entrar(p_solicitante, p_tipo);
  v := public.geoportal_campo_crear_reporte(p_solicitante, p_id, p_tipo, p_subtipo, p_descripcion, p_contrato, p_lat, p_lon, p_precision_m, p_riesgo_inmediato, 'campo', p_fotos,
                                            p_ip, p_datos, p_resultado, p_causal, null, p_inicio_dispositivo);
  perform set_config('geoportal.via_tecnica', '', true);
  return v || jsonb_build_object('area', 'tecnica');
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo con UN cambio exacto:
--   · campo.f_autorizar_reporte: también pasa quien entra por las RPC de Técnica (la marca de la transacción). Sin la marca, igual que antes;
--   · tecnica.f_formularios: los dos formularios compartidos («Reportar anomalía» y «Revisiones generales»).
-- =====================================================================
-- campo.f_autorizar_reporte(text)
CREATE OR REPLACE FUNCTION campo.f_autorizar_reporte(p_solicitante text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  -- Corte 8 de Técnica: también pasa quien entra por las RPC geoportal_campo_tec_* (ya autorizado allá por su formulario de Técnica); la marca solo dura esa transacción
  if campo.f_perfil(v_email) is null and coalesce(current_setting('geoportal.via_tecnica', true), '') <> 'on' then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  return v_email;
end $function$;

-- tecnica.f_formularios()
CREATE OR REPLACE FUNCTION tecnica.f_formularios()
 RETURNS TABLE(clave text, nombre text, descripcion text, orden integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  values ('entrada',          'Entrada',                           'Agua cruda que ingresa a las plantas.', 1),
         ('salida',           'Salida',                            'Agua tratada que sale de las plantas.', 2),
         ('muestreo',         'Muestreo',                          'Muestreo en los puntos de la red y los tanques.', 3),
         ('danos_fallas',     'Daños o fallas',                    'Daños o fallas en la planta.', 4),
         ('mantenimiento',    'Mantenimiento, reparación e inversión', 'Mantenimiento, reparación e inversión.', 5),
         ('uso_quimicos',     'Uso de químicos',                   'Químicos usados en el proceso.', 6),
         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7),
         ('anomalia_compartida', 'Reportar anomalía',               'El mismo reporte de anomalías de Comercial, hecho desde Técnica.', 8),
         ('revision_compartida', 'Revisiones generales',            'La misma revisión general de Comercial, hecha desde Técnica.', 9);
$function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 30 — LA CAPA «REPORTES DE COMERCIAL» DEL GEOVISOR (§30.4): se reemplaza la vista vacía del 6b, con las mismas columnas.
-- Lo que muestra: los reportes de anomalía (reporte general) y las revisiones generales de campo.reportes, de Comercial y de Técnica, que no estén ocultos.
-- SIN datos del suscriptor: no lleva el número de contrato (solo si lo trae: azul con contrato, rojo posible clandestino), ni la descripción, ni fotos, ni autor.
-- Ninguna función de redes cambia: geoportal_redes_geovisor_capa ya lee esta vista.
-- =====================================================================
create or replace view redes.v_reportes_comercial as
select coalesce(e.consecutivo, 'REP-' || lpad(e.seq::text, 6, '0'))::text as codigo,
       t.nombre::text as tipo,
       s.nombre::text as subtipo,
       coalesce(r.area, 'comercial')::text as area,
       (e.contrato is not null) as con_contrato,
       coalesce(x.nombre, e.estado)::text as estado,
       e.registrado_en,
       e.lat::numeric(9, 6) as lat,
       e.lon::numeric(9, 6) as lon
  from campo.v_reportes_estado e
  join campo.reportes r on r.id = e.id
  join campo.tipos_reporte t on t.id = e.tipo_id
  left join campo.subtipos_reporte s on s.id = e.subtipo_id
  left join campo.estados_reporte x on x.codigo = e.estado
 where not e.oculto
   and (t.codigo = 'revision_previa' or campo.f_tipo_general(t.codigo));
comment on view redes.v_reportes_comercial is 'Corte 8: reportes de anomalía y revisiones generales de campo.reportes para el geovisor técnico. Sin contrato, descripción, fotos ni autor.';
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Funciones internas: nadie de la API. Las 3 RPC nuevas: solo execute a service_role (la Edge geoportal-campo). La vista: nadie de la API (como en el 6b).
-- =====================================================================
revoke all on function campo.f_tipo_general(text), campo.f_tecnica_claves(text), campo.f_tecnica_entrar(text, text) from public, anon, authenticated, service_role;
revoke all on function campo.f_autorizar_reporte(text), tecnica.f_formularios() from public, anon, authenticated, service_role;
revoke all on table redes.v_reportes_comercial from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_campo_tec_formulario', 'geoportal_campo_tec_preparar_subida', 'geoportal_campo_tec_crear_reporte') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@tecnica_corte8', 'migracion_tecnica_corte8', null, jsonb_build_object(
        'columna', 'campo.reportes.area', 'reemplazadas', jsonb_build_array('campo.f_autorizar_reporte', 'tecnica.f_formularios'), 'dominio', 'tecnica.formulario_clave',
        'rpc_nuevas', jsonb_build_array('geoportal_campo_tec_formulario', 'geoportal_campo_tec_preparar_subida', 'geoportal_campo_tec_crear_reporte'),
        'vista', 'redes.v_reportes_comercial',
        'tipos_agregados', (select coalesce(jsonb_agg(codigo), '[]'::jsonb) from campo.tipos_reporte where codigo in ('fuga_acometida', 'caja_medidor_danada'))), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de la migración, en la misma transacción.
-- No supone conteos de la base: arma sus personas (prueba.tec8.*) y sus reportes (en un rincón de Valledupar, con el contrato de prueba 990000001301).
-- No escribe en ninguna tabla ni vista de Comercial que no sea de solo inserción propia de la prueba: en particular, NO toca public.predios_comercial (vista materializada).
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · CORTE 8 … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.tipos(p jsonb) returns text language sql as $$
  select coalesce(string_agg(t ->> 'codigo', ',' order by t ->> 'codigo'), '') from jsonb_array_elements(p -> 'grupos') g, jsonb_array_elements(g -> 'tipos') t $$;

do $prueba$
declare
  a text := 'prueba.tec8.adm@emdupar.gov.co'; sv text := 'prueba.tec8.sup@emdupar.gov.co'; o1 text := 'prueba.tec8.op1@emdupar.gov.co'; o2 text := 'prueba.tec8.op2@emdupar.gov.co';
  o3 text := 'prueba.tec8.op3@emdupar.gov.co'; rc text := 'prueba.tec8.rep@emdupar.gov.co'; na text := 'prueba.tec8.nada@emdupar.gov.co';
  C1 text := '990000001301';
  v_r jsonb; v_x jsonb; v_id uuid; v_id2 uuid; v_id3 uuid; v_n0 integer; v_t0 integer; v_gen text; v_md5 text; v_fotos jsonb;
  v_total integer; v_bien integer; v_fallas text;
begin
  select count(*), md5(coalesce(string_agg(r.id::text || coalesce(r.descripcion, '') || coalesce(r.contrato, '') || r.registrado_en::text || coalesce(r.datos::text, ''), ',' order by r.seq), '')) into v_n0, v_md5 from campo.reportes r;
  select count(*) into v_t0 from campo.tipos_reporte where codigo not in ('fuga_acometida', 'caja_medidor_danada');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT8 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT8 Supervisor técnico', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values
    (o1, 'ZT8 Operador con anomalía', 'consulta', true, 'sin_restriccion', 'todos'), (o2, 'ZT8 Operador con revisión', 'consulta', true, 'sin_restriccion', 'todos'),
    (o3, 'ZT8 Operador sin compartidos', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values (rc, 'ZT8 Reportante de Comercial', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT8 Sin nada', 'consulta', 'sin_restriccion', 'todos');

  -- ===================== 01. Técnica: las dos claves nuevas =====================
  perform pg_temp.reg('01.01 tecnica.f_formularios lista 9 formularios: los 7 de antes, «Reportar anomalía» y «Revisiones generales»',
     (select count(*) from tecnica.f_formularios()) = 9 and (select string_agg(clave, ',' order by orden) from tecnica.f_formularios() where orden > 7) = 'anomalia_compartida,revision_compartida');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (o1, 'asignar_formulario', 'anomalia_compartida', a), (o2, 'asignar_formulario', 'revision_compartida', a),
    (o3, 'asignar_formulario', 'entrada', a);
  perform pg_temp.reg('01.02 las claves nuevas se asignan en Personal como cualquier formulario (el dominio las admite)',
     (select count(*) from tecnica.personal_tecnico_eventos where persona in (o1, o2) and formulario in ('anomalia_compartida', 'revision_compartida')) = 2);
  perform pg_temp.err('01.03 una clave inventada sigue sin entrar al dominio', format($$insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (%L, 'asignar_formulario', 'inventada', %L)$$, o1, a), '23514');
  v_r := public.geoportal_tec_mis_formularios(o1);
  perform pg_temp.reg('01.04 «mis formularios» del operador trae «Reportar anomalía» (sin campos propios: la pantalla es la de Comercial)',
     exists (select 1 from jsonb_array_elements(v_r -> 'formularios') f where f ->> 'clave' = 'anomalia_compartida' and f ->> 'nombre' = 'Reportar anomalía' and not (f ->> 'con_campos')::boolean)
     and not exists (select 1 from jsonb_array_elements(v_r -> 'formularios') f where f ->> 'clave' = 'revision_compartida'), v_r::text);
  perform pg_temp.reg('01.05 quién tiene qué: operador 1 anomalía, operador 2 revisión, operador 3 ninguno, supervisor técnico y administrador los dos; Comercial y «nada», ninguno',
     campo.f_tecnica_claves(o1) = '{anomalia_compartida}' and campo.f_tecnica_claves(o2) = '{revision_compartida}' and campo.f_tecnica_claves(o3) = '{}'
     and cardinality(campo.f_tecnica_claves(sv)) = 2 and cardinality(campo.f_tecnica_claves(a)) = 2 and campo.f_tecnica_claves(rc) = '{}' and campo.f_tecnica_claves(na) = '{}');

  -- ===================== 02. El catálogo es el mismo =====================
  perform pg_temp.reg('02.01 los tipos que ya había siguen todos, sin cambios de cantidad; existen «Fuga en acometida» y «Caja de medidor dañada»',
     (select count(*) from campo.tipos_reporte where codigo not in ('fuga_acometida', 'caja_medidor_danada')) = v_t0
     and exists (select 1 from campo.tipos_reporte where lower(nombre) like '%fuga%acometida%') and exists (select 1 from campo.tipos_reporte where lower(nombre) like '%caja%medidor%da_ad%'));
  perform pg_temp.reg('02.02 los dos nuevos son del reporte general (sin campos ni consecutivo) y «Revisiones generales» no',
     (not exists (select 1 from campo.tipos_reporte where codigo = 'fuga_acometida') or campo.f_tipo_general('fuga_acometida'))
     and (not exists (select 1 from campo.tipos_reporte where codigo = 'caja_medidor_danada') or campo.f_tipo_general('caja_medidor_danada'))
     and not campo.f_tipo_general('revision_previa') and not campo.f_tipo_general('inventado'));
  select t.codigo into v_gen from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where t.activo and g.activo and campo.f_tipo_general(t.codigo) and not t.exige_subtipo and not t.exige_texto and t.requiere_contrato <> 'si' order by (t.codigo = 'fuga_acometida') desc, t.id limit 1;

  -- ===================== 03. El formulario, desde Técnica =====================
  v_r := public.geoportal_campo_tec_formulario(o1);
  perform pg_temp.reg('03.01 operador con «Reportar anomalía»: perfil de reportante, área «tecnica» y solo los tipos del reporte general (sin formatos de actividad ni revisiones)',
     v_r ->> 'perfil' = 'reportante' and v_r ->> 'area' = 'tecnica' and not (v_r -> 'puede' ->> 'supervisar')::boolean and v_r -> 'limites' ->> 'max_fotos' is not null
     and pg_temp.tipos(v_r) <> '' and not exists (select 1 from unnest(string_to_array(pg_temp.tipos(v_r), ',')) c where not campo.f_tipo_general(c)), pg_temp.tipos(v_r));
  perform pg_temp.reg('03.02 es el MISMO catálogo que ve el reportante de Comercial en «Reportar anomalía»',
     pg_temp.tipos(v_r) = (select string_agg(c, ',' order by c) from unnest(string_to_array(pg_temp.tipos(public.geoportal_campo_obtener_formulario(rc, false)), ',')) c where campo.f_tipo_general(c)));
  v_x := public.geoportal_campo_tec_formulario(o2);
  perform pg_temp.reg('03.03 operador con «Revisiones generales»: solo ese formato, con sus campos', pg_temp.tipos(v_x) = 'revision_previa'
     and (select jsonb_array_length(t -> 'campos') > 5 from jsonb_array_elements(v_x -> 'grupos') g, jsonb_array_elements(g -> 'tipos') t), pg_temp.tipos(v_x));
  v_x := public.geoportal_campo_tec_formulario(a);
  perform pg_temp.reg('03.04 el administrador, entrando por Técnica, recibe la vista de reportante (sin estados, parámetros ni definiciones de supervisión) con los dos formularios',
     v_x ->> 'perfil' = 'reportante' and v_x -> 'parametros' = 'null'::jsonb and v_x -> 'estados' = 'null'::jsonb and position('revision_previa' in pg_temp.tipos(v_x)) > 0 and position(v_gen in pg_temp.tipos(v_x)) > 0);
  perform pg_temp.err('03.05 un operador de Técnica sin formularios compartidos no entra', format($$select public.geoportal_campo_tec_formulario(%L)$$, o3), '42501');
  perform pg_temp.err('03.06 un reportante de Comercial sin Técnica tampoco entra por esta puerta', format($$select public.geoportal_campo_tec_formulario(%L)$$, rc), '42501');
  perform pg_temp.err('03.07 quien no tiene nada, tampoco', format($$select public.geoportal_campo_tec_formulario(%L)$$, na), '42501');
  perform pg_temp.err('03.08 el operador de Técnica sigue SIN entrar al formulario de Comercial por la puerta de Comercial', format($$select public.geoportal_campo_obtener_formulario(%L, false)$$, o1), '42501');

  -- ===================== 04. Crear desde Técnica: misma tabla, con el área =====================
  -- El contrato de prueba NO se crea en public.predios_comercial: en producción es una VISTA MATERIALIZADA (la refresca el cargador diario de Comercial) y no se escribe
  -- en ella. El reporte lleva un contrato que no está en el catastro comercial: se guarda igual, como «no verificado» (el tipo lo pide «opcional»).
  v_r := public.geoportal_campo_tec_preparar_subida(o1, 1, '10.0.0.8', null);
  v_id := (v_r ->> 'reporte_id')::uuid;
  perform pg_temp.reg('04.01 preparar la subida desde Técnica: mismas rutas del bucket de campo (campo-fotos)', v_r ->> 'bucket' = 'campo-fotos' and jsonb_array_length(v_r -> 'fotos') = 1 and v_id is not null, v_r::text);
  insert into storage.objects (bucket_id, name, metadata) select 'campo-fotos', f ->> 'ruta', '{"size": 200000, "mimetype": "image/jpeg"}'::jsonb from jsonb_array_elements(v_r -> 'fotos') f;
  v_fotos := (select jsonb_agg(jsonb_build_object('orden', (f ->> 'orden')::integer, 'ruta', f ->> 'ruta', 'tomada_en', clock_timestamp())) from jsonb_array_elements(v_r -> 'fotos') f);
  v_x := public.geoportal_campo_tec_crear_reporte(o1, v_id, v_gen, null, 'ZT8 fuga en la acometida, frente al predio', C1, 10.4400, -73.2600, 8, false, v_fotos, '10.0.0.8');
  perform pg_temp.reg('04.02 el operador de Técnica crea el reporte: queda en campo.reportes (la misma tabla), con el área «tecnica», su autor y origen «campo»',
     (v_x ->> 'id')::uuid = v_id and v_x ->> 'area' = 'tecnica'
     and (select area || '|' || autor || '|' || origen || '|' || contrato || '|' || contrato_verificado from campo.reportes where id = v_id) = 'tecnica|' || o1 || '|campo|' || C1 || '|false', v_x::text);
  perform pg_temp.reg('04.02b la prueba no escribió en public.predios_comercial (vista materializada de Comercial): el contrato de prueba no está allí',
     not exists (select 1 from public.predios_comercial where cod_usuario = C1));
  perform pg_temp.reg('04.03 con sus fotos, su evento inicial y su auditoría, como cualquier reporte de campo',
     (select count(*) from campo.reporte_fotos where reporte_id = v_id) = 1 and (select estado from campo.v_reportes_estado where id = v_id) = 'reportado'
     and exists (select 1 from public.geoportal_auditoria where accion = 'campo_crear_reporte' and email = o1));
  perform pg_temp.err('04.04 el reporte no se puede cambiar después (solo inserción): tampoco su área', format($$update campo.reportes set area = null where id = %L$$, v_id), '42501');
  perform pg_temp.err('04.05 el operador con solo «Reportar anomalía» no crea una revisión general', format($$select public.geoportal_campo_tec_crear_reporte(%L, gen_random_uuid(), 'revision_previa', null, null, %L, 10.44, -73.26, 8, false, '[]'::jsonb)$$, o1, C1), '42501');
  perform pg_temp.err('04.06 el operador con solo «Revisiones generales» no crea un reporte de anomalía', format($$select public.geoportal_campo_tec_crear_reporte(%L, gen_random_uuid(), %L, null, 'x', null, 10.44, -73.26, 8, false, '[]'::jsonb)$$, o2, v_gen), '42501');
  perform pg_temp.err('04.07 desde Técnica no se llena ningún otro formato de Comercial (por ejemplo, una suspensión)', format($$select public.geoportal_campo_tec_crear_reporte(%L, gen_random_uuid(), 'suspension', null, null, %L, 10.44, -73.26, 8, false, '[]'::jsonb)$$, a, C1), '42501', 'Técnica');
  perform pg_temp.err('04.08 ni se prepara la subida de otro formato', format($$select public.geoportal_campo_tec_preparar_subida(%L, 2, null, 'corte')$$, a), '42501');
  perform pg_temp.err('04.09 un operador sin compartidos no crea nada', format($$select public.geoportal_campo_tec_crear_reporte(%L, gen_random_uuid(), %L, null, 'x', null, 10.44, -73.26, 8, false, '[]'::jsonb)$$, o3, v_gen), '42501');
  perform pg_temp.reg('04.10 la marca se apaga al terminar cada RPC de Técnica (no queda puesta para la llamada siguiente)', coalesce(current_setting('geoportal.via_tecnica', true), '') <> 'on');
  perform pg_temp.err('04.11 por eso el operador de Técnica sigue sin poder crear por la puerta de Comercial, aun en la misma transacción',
     format($$select public.geoportal_campo_crear_reporte(%L, gen_random_uuid(), %L, null, 'ZT8 intento por Comercial', null, 10.44, -73.26, 8, false, 'campo', '[]'::jsonb)$$, o1, v_gen), '42501');

  -- ===================== 05. Comercial sigue igual =====================
  perform pg_temp.err('05.01 sin la marca, quien no tiene campo sigue rechazado por campo.f_autorizar_reporte', format($$select campo.f_autorizar_reporte(%L)$$, o1), '42501');
  v_r := public.geoportal_campo_preparar_subida(rc, 1, 'campo', '10.0.0.9', null);
  v_id2 := (v_r ->> 'reporte_id')::uuid;
  insert into storage.objects (bucket_id, name, metadata) select 'campo-fotos', f ->> 'ruta', '{"size": 200000, "mimetype": "image/jpeg"}'::jsonb from jsonb_array_elements(v_r -> 'fotos') f;
  v_fotos := (select jsonb_agg(jsonb_build_object('orden', (f ->> 'orden')::integer, 'ruta', f ->> 'ruta', 'tomada_en', clock_timestamp())) from jsonb_array_elements(v_r -> 'fotos') f);
  v_x := public.geoportal_campo_crear_reporte(rc, v_id2, v_gen, null, 'ZT8 reporte de Comercial sin contrato', null, 10.4410, -73.2610, 8, false, 'campo', v_fotos, '10.0.0.9');
  perform pg_temp.reg('05.02 el reportante de Comercial crea su reporte como siempre: el área queda NULA (Comercial) y la respuesta no cambia',
     (select area is null and autor = rc from campo.reportes where id = v_id2) and not (v_x ? 'area') and v_x ? 'registrado_en', v_x::text);
  perform pg_temp.reg('05.03 ningún reporte que ya existía cambió: mismos registros, mismo contenido y área nula',
     (select count(*) from campo.reportes where id not in (v_id, v_id2)) = v_n0
     and (select md5(coalesce(string_agg(r.id::text || coalesce(r.descripcion, '') || coalesce(r.contrato, '') || r.registrado_en::text || coalesce(r.datos::text, ''), ',' order by r.seq), ''))
            from campo.reportes r where r.id not in (v_id, v_id2)) = v_md5
     and not exists (select 1 from campo.reportes where id not in (v_id, v_id2) and area is not null));
  perform pg_temp.reg('05.04 el formulario de Comercial sigue trayendo lo mismo para el reportante (incluidos los formatos de actividad activos)',
     public.geoportal_campo_obtener_formulario(rc, false) ->> 'perfil' = 'reportante' and position('revision_previa' in pg_temp.tipos(public.geoportal_campo_obtener_formulario(rc, false))) > 0);

  -- ===================== 06. La capa del geovisor =====================
  perform pg_temp.reg('06.01 la vista trae los dos reportes: el de Técnica con contrato (azul) y el de Comercial sin contrato (rojo, posible clandestino), con su área',
     (select string_agg(area || ':' || con_contrato, ',' order by area) from redes.v_reportes_comercial where registrado_en >= clock_timestamp() - interval '5 minutes'
        and lat between 10.4399 and 10.4411 and lon between -73.2611 and -73.2599) = 'comercial:false,tecnica:true',
     (select string_agg(area || ':' || con_contrato || ':' || codigo, ',') from redes.v_reportes_comercial where registrado_en >= clock_timestamp() - interval '5 minutes'));
  perform pg_temp.reg('06.02 sin datos del suscriptor: ni el contrato, ni la descripción, ni el autor',
     (select bool_and(to_jsonb(v)::text not like '%' || C1 || '%' and to_jsonb(v)::text not like '%ZT8%' and to_jsonb(v)::text not like '%prueba.tec8%') from redes.v_reportes_comercial v
       where v.registrado_en >= clock_timestamp() - interval '5 minutes'));
  perform pg_temp.reg('06.03 con el nombre del tipo, el estado y un código que no es el contrato',
     (select bool_and(tipo is not null and estado = 'Reportado' and codigo ~ '^REP-[0-9]{6,}$') from redes.v_reportes_comercial where registrado_en >= clock_timestamp() - interval '5 minutes'
        and lat between 10.4399 and 10.4411));
  insert into campo.reporte_eventos (reporte_id, tipo_evento, autor, motivo) values (v_id2, 'ocultar', a, 'ZT8 reporte de prueba del Corte 8');
  perform pg_temp.reg('06.04 un reporte oculto sale de la capa', not exists (select 1 from redes.v_reportes_comercial v where v.lat = 10.4410 and v.lon = -73.2610 and v.registrado_en >= clock_timestamp() - interval '5 minutes'));

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · CORTE 8 (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
