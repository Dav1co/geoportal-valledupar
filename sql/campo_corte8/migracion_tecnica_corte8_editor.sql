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
commit;
