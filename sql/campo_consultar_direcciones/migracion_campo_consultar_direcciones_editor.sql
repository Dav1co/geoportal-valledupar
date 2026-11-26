-- [Code A] CONSULTAR DIRECCIONES (25-nov) · MIGRACIÓN (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- CONSULTAR DIRECCIONES (Code A, 25-nov) · 05 — GUARDIA: se detiene sin cambiar nada si la base no es la publicada
-- Huella de campo 66496328d10a5b25eb01e572edae7cda (con el registro flexible publicado), acta 111506c690249ad3b56ebf572566434c y Técnica 838b80984e51cc7873a666f85d657195 (no cambian con este paquete);
-- md5 de cada función que se reemplaza o de la que depende el cambio; estructura EXACTA (paso 0 del 25-nov, 23:25) de campo.consultas_analisis, campo.parametros
-- y campo.reporte_registro; y de las dos tablas grandes que solo se leen (catastro_valledupar, cartera_suscripcion), lo que el paquete usa: sus columnas con su
-- tipo y los índices por contrato (sin ellos, la ruta nueva barrería 123 mil y 112 mil filas).
-- =====================================================================
do $guardia$
declare v text; r record;
begin
  if to_regprocedure('public.geoportal_campo_direccion_contrato(text,text,text)') is not null then
    raise exception 'Este paquete ya parece aplicado (existe geoportal_campo_direccion_contrato): use la reversa antes de repetir';
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if coalesce(v, '(ninguna)') is distinct from '66496328d10a5b25eb01e572edae7cda' then
    raise exception 'Las funciones de campo no son las publicadas (huella 66496328d10a5b25eb01e572edae7cda; hay %): deténgase y avise', v;
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
  for r in select * from (values ('public.geoportal_campo_analisis_contrato(text,text,text)', 'fedc868f147c9d3a92b1f9e938fa06ed'), ('public.geoportal_campo_analisis_observar(text,text,text,text,text,jsonb,text)', 'b2d92153c58a2fb1deb3fe05a524e98f'), ('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone,jsonb)', 'cfb2dbb022ae0f6e93989dcc6579e4d8'), ('public.geoportal_campo_obtener_reporte(text,uuid,text)', 'bf9900e35a4051a00fec8b87cb34f153'), ('public.geoportal_campo_listar_reportes(text,jsonb,text)', 'c6a74c023f37e5e0de7527b71d7cb369'), ('public.geoportal_campo_descarga_pagina(text,bigint,bigint,integer)', '0f4ce407e77abe49b1e6cc6132507f86'), ('public.geoportal_campo_pdf_datos(text,text,uuid,text)', '52d496ead7c6ea884b1c58b8c80541eb'), ('public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone,jsonb)', '8ae23410abdba2194377b5ae19abc417'), ('campo.f_autorizar_reporte(text)', '097a21e90766512921f185d213f3c779'), ('campo.f_autorizar_analisis(text)', 'e83b8d7eeeaede7665c3d25bb9ae4c36'), ('campo.f_perfil(text)', '0d3da36f35a5adf8936789cef91405bb'), ('campo.f_tecnica_entrar(text,text)', '0b8a0b83e29192980e9d3f902e05b305'), ('campo.f_param(text)', '23b13a57b5b26471cdf2f58824fe60c7'), ('campo.f_error(text,text)', '6439032aae6fe0575c94fb32f85f109f'), ('campo.f_error_limite(text)', '4503b0b0e5422278398e2809f9fa8d8e'), ('campo.f_texto_espera(timestamp with time zone,integer)', 'd3f0318c0cb8e0076fa87369ec1eb758'), ('campo.f_auditar(text,text,text,jsonb,text)', '67bbec1b5d638525595b52666ecb3bcd'), ('campo.f_solo_agregar()', '2a27744a1110ddd5bf835b2b65a3a671'), ('campo.f_consultas_analisis_inmutable()', '941db737e23f4ce97ce2cc0cb0cfe231'), ('campo.f_tipo_general(text)', '4ede0bf1f2a69982fb033cea893b84e2'), ('campo.f_autorizar_supervision(text)', '5ac3368fa5f3a6347328285501894aec'), ('campo.f_autorizar_documento(text,text,uuid)', 'a54711241d29ff33a8930a948d011b3f'), ('public.geoportal_puede(text,text)', '32f174a55b95788d3f8187b507303c2f'), ('public.geoportal_mis_permisos(text)', '83166fe17be58da67bbdedaae429bedb'), ('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)', '01fda69a9d912067b8b4dc153ac7957e'), ('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)', 'e5a90103b4a83440fd826f03266b7245')) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la publicada: deténgase y avise', r.f;
    end if;
  end loop;
  -- Estructura exacta (m2: la que deja la reversa de este paquete, que conserva la columna via; nada se borra)
  for r in select * from (values ('campo.consultas_analisis', '1202c7e6e2999e2d5adaccd2e371320d', 'de9c49d68dcdb8547cc072a961bcdc23'), ('campo.parametros', 'fd9322f0721b931e71fa96b3010ed6f8', null::text), ('campo.reporte_registro', '6bbcd353497807cfff9d4b0b5722da93', null::text)) x(t, m, m2) loop
    if to_regclass(r.t) is null then raise exception 'No existe la tabla %: deténgase y avise', r.t; end if;
    select md5(concat_ws('#', (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped), (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel), (select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel), (select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal), (select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel))) into v from (select to_regclass(r.t) as rel) z;
    if v is distinct from r.m and v is distinct from coalesce(r.m2, r.m) then
      raise exception 'La estructura de % no es la de producción (columnas, restricciones, índices, disparadores, RLS o permisos): deténgase y avise', r.t;
    end if;
  end loop;
  for r in select * from (values ('campo.reporte_direccion_contrato', 'de99e9852daabcac1a85aff809f2f9c7')) x(t, m) loop
    if to_regclass(r.t) is not null then
      select md5(concat_ws('#', (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped), (select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel), (select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel), (select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal), (select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel))) into v from (select to_regclass(r.t) as rel) z;
      if v is distinct from r.m then raise exception 'La tabla % ya existe y no es la de este paquete: deténgase y avise', r.t; end if;
    end if;
  end loop;
  -- Las dos tablas grandes que solo se leen: las columnas que usa el paquete, con su tipo, y los índices por contrato
  for r in select * from (values ('public.catastro_valledupar', 'cod_usuario'), ('public.catastro_valledupar', 'direccion'), ('public.catastro_valledupar', 'barrio'),
                                 ('public.catastro_valledupar', 'unih'), ('public.catastro_valledupar', 'uninh'), ('public.catastro_valledupar', 'clase_uso'),
                                 ('public.catastro_valledupar', 'act_eco'), ('public.cartera_suscripcion', 'contrato'), ('public.cartera_suscripcion', 'direccion'),
                                 ('public.cartera_suscripcion', 'barrio'), ('public.cartera_suscripcion', 'periodo_carga')) x(t, c) loop
    if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass(r.t) and a.attname = r.c and not a.attisdropped and a.atttypid = 'text'::regtype) then
      raise exception 'La columna %.% no existe o no es texto: deténgase y avise', r.t, r.c;
    end if;
  end loop;
  if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid where i.indrelid = 'public.catastro_valledupar'::regclass and c.relname = 'idx_catastro_cod_usuario'
                  and pg_get_indexdef(i.indexrelid) ~ 'USING btree \(cod_usuario\)$') then
    raise exception 'Falta el índice idx_catastro_cod_usuario (btree por cod_usuario): deténgase y avise';
  end if;
  if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid where i.indrelid = 'public.cartera_suscripcion'::regclass and c.relname = 'idx_cartera_contrato'
                  and pg_get_indexdef(i.indexrelid) ~ 'USING btree \(contrato\)$') then
    raise exception 'Falta el índice idx_cartera_contrato (btree por contrato): deténgase y avise';
  end if;
  if exists (select 1 from pg_policies where schemaname in ('campo', 'acta')) then
    raise exception 'Hay políticas RLS en campo o acta: este paquete se preparó para ninguna; deténgase y avise';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'homelab_lectura' and rolbypassrls) then
    raise exception 'No existe el rol homelab_lectura con BYPASSRLS: deténgase y avise';
  end if;
  if exists (select 1 from campo.parametros where clave = 'limite_direccion_hora' and (unidad <> 'consultas' or minimo is distinct from 1 or maximo is distinct from 1000)) then
    raise exception 'Ya existe el parámetro limite_direccion_hora y no es el de este paquete: deténgase y avise';
  end if;
  if (select count(*) from campo.parametros where clave in ('multiplo_supervisor')) <> 1 then
    raise exception 'Falta el parámetro multiplo_supervisor: deténgase y avise';
  end if;
end $guardia$;

-- =====================================================================
-- CONSULTAR DIRECCIONES (Code A, 25-nov) · 10 — ESTRUCTURA
-- 1. campo.consultas_analisis.via: la MISMA bitácora de consultas registra ahora también la dirección del contrato pedida desde un formato (decisión de David).
--    «analisis» por omisión (lo de antes); «formato» = la ruta direccion_contrato. Nada se borra; la columna es de la bitácora de solo inserción.
-- 2. Parámetro limite_direccion_hora (60 consultas por hora; el supervisor, × multiplo_supervisor; el administrador, sin tope). Los inexistentes también cuentan.
-- 3. campo.reporte_direccion_contrato: FOTO de las dos direcciones del contrato al registrar (base comercial y catastro). Una fila por reporte, solo inserción,
--    RLS sin políticas, sin permisos para la API, SELECT para homelab_lectura. Entra al sello del PDF solo si existe la fila (los reportes de antes no cambian).
-- =====================================================================
alter table campo.consultas_analisis add column if not exists via text not null default 'analisis';
do $via$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'campo.consultas_analisis'::regclass and conname = 'consultas_analisis_via_ck') then
    alter table campo.consultas_analisis add constraint consultas_analisis_via_ck check (via in ('analisis', 'formato'));
  end if;
end $via$;
comment on column campo.consultas_analisis.via is 'Consultar direcciones (25-nov): analisis = Análisis de contrato (Consultar); formato = dirección del contrato pedida desde un formato o Reportar anomalía.';

insert into campo.parametros (clave, valor, unidad, descripcion, minimo, maximo, actualizado_por)
values ('limite_direccion_hora', 60, 'consultas',
        'Consultas por hora de la dirección del contrato desde los formatos (operario; el supervisor, por el múltiplo; el administrador, sin tope). Los contratos inexistentes también cuentan.',
        1, 1000, 'migracion@geoportal')
on conflict (clave) do nothing;

create table if not exists campo.reporte_direccion_contrato (
  reporte_id uuid primary key references campo.reportes (id),
  contrato text not null,
  direccion_comercial text,          -- cartera_suscripcion, último corte
  barrio_comercial text,
  direccion_catastro text,           -- catastro_valledupar, predio principal (menor id)
  barrio_catastro text,
  predios_catastro integer not null default 0,
  creado_en timestamptz not null default clock_timestamp(),
  constraint reporte_direccion_contrato_contrato_ck check (contrato ~ '^[A-Za-z0-9-]{1,20}$'),
  constraint reporte_direccion_contrato_predios_ck check (predios_catastro >= 0)
);
comment on table campo.reporte_direccion_contrato is 'Consultar direcciones (25-nov): las dos direcciones del contrato tal como estaban al registrar el reporte. Una fila por reporte con contrato; solo inserción. Sin fila = reporte anterior a este paquete o sin contrato.';
create or replace trigger t_solo_agregar before delete or update on campo.reporte_direccion_contrato for each row execute function campo.f_solo_agregar();
create or replace trigger t_solo_agregar_trunc before truncate on campo.reporte_direccion_contrato for each statement execute function campo.f_solo_agregar();
alter table campo.reporte_direccion_contrato enable row level security;
revoke all on table campo.reporte_direccion_contrato from public, anon, authenticated, service_role;
grant select on table campo.reporte_direccion_contrato to homelab_lectura;

-- =====================================================================
-- CONSULTAR DIRECCIONES (Code A, 25-nov) · 20 — FUNCIONES NUEVAS
-- campo.f_texto_censo(t, colapsar_palabras): limpieza MÍNIMA de un texto del censo: recorta, colapsa espacios y, si se pide (clase de uso), una palabra repetida
--   seguida («RESIDENCIAL RESIDENCIAL» → «RESIDENCIAL»; «RESIDENCIAL COMERCIAL» se deja). Vacío = nulo. No interpreta ni recodifica.
-- campo.f_direcciones_contrato(contrato): las dos direcciones, por separado y sin mezclarlas: base comercial (cartera_suscripcion, último corte) y catastro
--   (catastro_valledupar, predio principal = menor id), cada una con su barrio, y cuántos predios tiene el contrato en el censo. Todo por índice
--   (idx_cartera_contrato, idx_catastro_cod_usuario). Nada más: ni nombre, ni teléfono, ni deuda.
-- geoportal_campo_direccion_contrato: la ruta de los formatos (quien tiene permiso de campo; desde Técnica, geoportal_campo_tec_direccion_contrato). Queda en la
--   bitácora campo.consultas_analisis con via = 'formato'. Tope: limite_direccion_hora por hora (supervisor × multiplo_supervisor; administrador sin tope);
--   los contratos inexistentes también cuentan.
-- =====================================================================
create function campo.f_texto_censo(p_texto text, p_colapsar_palabras boolean default false)
 returns text
 language sql
 immutable
 set search_path to 'pg_catalog'
as $function$
  select nullif(case when p_colapsar_palabras then regexp_replace(t, '(^| )([^ ]+)( \2)+(?= |$)', '\1\2', 'g') else t end, '')
    from (select btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')) as t) x
$function$;
revoke all on function campo.f_texto_censo(text, boolean) from public, anon, authenticated, service_role;

create function campo.f_direcciones_contrato(p_contrato text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'campo', 'pg_temp'
as $function$
  select jsonb_build_object(
    'encontrado', cs.contrato is not null or pr.id is not null,
    'comercial', case when cs.contrato is not null then jsonb_build_object('direccion', campo.f_texto_censo(cs.direccion), 'barrio', campo.f_texto_censo(cs.barrio), 'corte', cs.periodo_carga) end,
    'catastro', case when pr.id is not null then jsonb_build_object('direccion', campo.f_texto_censo(pr.direccion), 'barrio', campo.f_texto_censo(pr.barrio)) end,
    'predios_total', (select count(*) from public.catastro_valledupar c where c.cod_usuario = p_contrato))
    from (select 1) uno
    left join lateral (select s.contrato, s.direccion, s.barrio, s.periodo_carga from public.cartera_suscripcion s where s.contrato = p_contrato
                        order by s.periodo_carga desc nulls last limit 1) cs on true
    left join lateral (select c.id, c.direccion, c.barrio from public.catastro_valledupar c where c.cod_usuario = p_contrato order by c.id limit 1) pr on true
$function$;
revoke all on function campo.f_direcciones_contrato(text) from public, anon, authenticated, service_role;

create function public.geoportal_campo_direccion_contrato(p_solicitante text, p_contrato text, p_ip text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'campo', 'pg_temp'
as $function$
declare v_email text; v_perfil text; v_c text := btrim(coalesce(p_contrato, '')); v_lim integer; v_n integer; v_primero timestamptz; v jsonb;
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);    -- quien registra en campo (o entra por la ruta de Técnica, que ya lo autorizó)
  v_perfil := campo.f_perfil(v_email);
  if v_c !~ '^\d{1,12}$' then perform campo.f_error('Escriba solo los números del contrato (hasta 12 dígitos).'); end if;
  -- Tope por hora (decisión de David): consultas de dirección desde formatos, existan o no los contratos
  if v_perfil is distinct from 'admin' then
    v_lim := campo.f_param('limite_direccion_hora')::integer * case when v_perfil = 'supervisor' then campo.f_param('multiplo_supervisor')::integer else 1 end;
    perform pg_advisory_xact_lock(hashtextextended('campo_direccion:' || v_email, 0));
    select count(*), min(q.consultado_en) into v_n, v_primero from campo.consultas_analisis q
     where q.autor = v_email and q.via = 'formato' and q.consultado_en > clock_timestamp() - interval '1 hour';
    if v_n >= v_lim then
      perform campo.f_error_limite(format('Llegó al límite de %s consultas de dirección en una hora. Podrá consultar otra dentro de %s.',
                                          v_lim, campo.f_texto_espera(v_primero, 60)));
    end if;
  end if;
  if v_c = '99999999' then
    insert into campo.consultas_analisis (autor, contrato, existe, ip, via) values (v_email, v_c, true, left(p_ip, 64), 'formato');
    return jsonb_build_object('encontrado', true, 'comodin', true, 'contrato', v_c);
  end if;
  v := campo.f_direcciones_contrato(v_c);
  insert into campo.consultas_analisis (autor, contrato, existe, ip, via) values (v_email, v_c, (v ->> 'encontrado')::boolean, left(p_ip, 64), 'formato');
  if not (v ->> 'encontrado')::boolean then return jsonb_build_object('encontrado', false, 'contrato', v_c); end if;
  return v || jsonb_build_object('contrato', v_c, 'comodin', false,
    -- «distintas»: las dos existen y no son el mismo texto (sin distinguir mayúsculas ni espacios)
    'distintas', v -> 'comercial' ->> 'direccion' is not null and v -> 'catastro' ->> 'direccion' is not null
                 and upper(v -> 'comercial' ->> 'direccion') <> upper(v -> 'catastro' ->> 'direccion'));
end $function$;
revoke all on function public.geoportal_campo_direccion_contrato(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_direccion_contrato(text, text, text) to service_role;

-- Desde Técnica (formulario compartido «Reportar anomalía»): autoriza por el formulario de Técnica y usa la misma función
create function public.geoportal_campo_tec_direccion_contrato(p_solicitante text, p_contrato text, p_ip text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'campo', 'tecnica', 'pg_temp'
as $function$
declare v jsonb;
begin
  perform campo.f_tecnica_entrar(p_solicitante, null);      -- «Reportar anomalía» de Técnica (anomalia_compartida)
  v := public.geoportal_campo_direccion_contrato(p_solicitante, p_contrato, p_ip);
  perform set_config('geoportal.via_tecnica', '', true);
  return v;
end $function$;
revoke all on function public.geoportal_campo_tec_direccion_contrato(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_tec_direccion_contrato(text, text, text) to service_role;

-- =====================================================================
-- CONSULTAR DIRECCIONES (Code A, 25-nov) · 30 — FUNCIONES QUE CAMBIAN (misma firma: create or replace)
-- analisis_contrato (Consultar): «direcciones» (base comercial y catastro por separado) y «predio» (unidades habitacionales y no habitacionales, clase de uso,
--   actividad económica del predio principal; limpieza mínima). Lo de antes no cambia (el encabezado sigue con comercial.direccion).
-- analisis_observar: el «consultado en las últimas 12 horas» cuenta solo «Consultar» (via = analisis), no la dirección pedida desde un formato.
-- crear_reporte: la dirección encontrada en terreno se acepta en cualquier formato con contrato escrito; y con contrato, la foto de sus dos direcciones.
-- detalle, lista, descarga y PDF: la dirección del contrato junto a la encontrada en terreno. El sello solo suma la fila si existe.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.geoportal_campo_analisis_contrato(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'bi', 'bi_interno', 'pg_temp'
AS $function$
declare
  v_email   text;
  v_c       text := btrim(coalesce(p_contrato, ''));
  v_existe  boolean;
  v_id      bigint;
  cs        record;
  pr        record;
  f         bi_interno.ficha_contrato%rowtype;
  v_ficha   boolean;
  v_estado  record;
  v_tel     text[];
  v_tel_f   text;
  v_barrio  text;
  v_meses   text[];
  v_hoy     date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_predios jsonb;
  v_n_pred  integer;
  v_prom    jsonb;
begin
  v_email := campo.f_autorizar_analisis(p_solicitante);
  if v_c !~ '^\d{1,12}$' then
    raise exception 'Escriba solo los números del contrato (hasta 12 dígitos).' using errcode = '22023', hint = 'msg_usuario';
  end if;
  -- SIN límite diario (decisión de David, 14/11): cada consulta queda en la bitácora (quién, cuándo, qué contrato), sin tope.

  -- ¿existe? (todo por índice: cartera_suscripcion.contrato, catastro_valledupar.cod_usuario, clave de la ficha)
  select s.* into cs from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select count(*) into v_n_pred from public.catastro_valledupar c where c.cod_usuario = v_c;
  select * into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  v_ficha := found;
  v_existe := cs.contrato is not null or v_n_pred > 0 or v_ficha;

  insert into campo.consultas_analisis (autor, contrato, existe, ip) values (v_email, v_c, v_existe, left(p_ip, 64)) returning id into v_id;
  perform campo.f_auditar(v_email, 'campo_analisis_contrato', v_id::text, jsonb_build_object('existe', v_existe), p_ip);   -- el contrato queda en la bitácora, no en la auditoría (decisión 15)

  if v_c = '99999999' then
    return jsonb_build_object('encontrado', true, 'comodin', true, 'contrato', v_c);
  end if;
  if not v_existe then
    return jsonb_build_object('encontrado', false, 'contrato', v_c);
  end if;

  -- predio principal (menor id) y hasta 5 predios con coordenadas (decisión 20)
  select c.id, c.direccion, c.barrio, c.diam_med, c.telefono, c.telefono_propie, p.estado_predio, p.tramo_mora,
         c.unih, c.uninh, c.clase_uso, c.act_eco into pr   -- Consultar direcciones (25-nov): datos del predio en el censo
    from public.catastro_valledupar c left join public.predios_comercial p on p.id = c.id
   where c.cod_usuario = v_c order by c.id limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('direccion', nullif(btrim(x.direccion), ''), 'barrio', nullif(btrim(x.barrio), ''),
                                               'lat', round(st_y(x.geom)::numeric, 6), 'lon', round(st_x(x.geom)::numeric, 6)) order by x.id), '[]'::jsonb)
    into v_predios
    from (select c.id, c.direccion, c.barrio, c.geom from public.catastro_valledupar c where c.cod_usuario = v_c order by c.id limit 5) x;

  -- teléfonos: los de la cartera diaria; si no hay, los del censo con su rótulo (decisión 11)
  v_tel := campo.f_telefonos(cs.telefono);
  v_tel_f := case when cardinality(v_tel) > 0 then 'cartera' end;
  if cardinality(v_tel) = 0 and pr.id is not null then
    v_tel := campo.f_telefonos(concat_ws(' / ', pr.telefono, pr.telefono_propie));
    v_tel_f := case when cardinality(v_tel) > 0 then 'censo' end;
  end if;

  select * into v_estado from bi_interno.ficha_contrato_estado where id = 1;
  v_barrio := nullif(upper(btrim(coalesce(cs.barrio, ''))), '');

  -- promedios de su estrato, barrio y uso en los mismos 6 meses (null en el mes si el grupo no llega a 30 o falta el mes)
  if v_ficha then
    select array_agg(m ->> 'periodo' order by k) into v_meses from jsonb_array_elements(f.consumo_meses) with ordinality t(m, k);
    select jsonb_object_agg(d.dimension, case when d.grupo is null then null else jsonb_build_object('grupo', d.grupo, 'meses',
             (select jsonb_agg(jsonb_build_object('periodo', mp, 'media', pd.media_m3, 'contratos', pd.contratos) order by mk)
                from unnest(v_meses) with ordinality u(mp, mk)
                left join bi.v_consumo_promedio_dim pd on pd.periodo = u.mp and pd.dimension = d.dimension and pd.grupo = d.grupo)) end)
      into v_prom
      from (values ('estrato', nullif(f.estrato, '(sin dato)')), ('barrio', v_barrio), ('uso', nullif(f.uso, '(sin dato)'))) d(dimension, grupo);
  end if;

  return jsonb_build_object(
    'encontrado', true, 'comodin', false, 'contrato', v_c,
    'suscriptor', jsonb_build_object('nombre', nullif(btrim(cs.nombre), ''), 'telefonos', to_jsonb(coalesce(v_tel, '{}'::text[])), 'telefono_fuente', v_tel_f, 'corte', cs.periodo_carga),
    'comercial', jsonb_build_object(
       'estado', nullif(btrim(cs.estado), ''), 'categoria', nullif(btrim(cs.categoria), ''), 'subcategoria', nullif(btrim(cs.subcategoria), ''),
       'ciclo', nullif(btrim(cs.ciclo), ''), 'ruta', nullif(btrim(cs.ruta), ''),
       'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), '')), 'direccion', coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')),
       'deuda_total', cs.deuda_total, 'saldo_pendiente', cs.saldo_pendiente, 'facturas_pendientes', cs.facturas_pendientes, 'saldo_financiado', cs.saldo_financiado,
       'valor_reclamo', cs.valor_reclamo, 'saldo_a_favor', cs.saldo_a_favor,
       'tramo_mora', pr.tramo_mora, 'estado_predio', nullif(btrim(pr.estado_predio), ''), 'facturas_vencidas', f.facturas_vencidas, 'corte', cs.periodo_carga),
    'medidor', jsonb_build_object(
       'serial', coalesce(case when v_ficha then f.medidor_serial end, nullif(upper(btrim(cs.serial_medidor)), '')),
       'diametro', nullif(btrim(pr.diam_med::text), ''),
       'fecha_instalacion', f.medidor_fecha, 'fecha_estado', coalesce(f.medidor_fecha_estado, 'sin_dato'), 'anios', f.medidor_anios,
       'cambio', coalesce(f.cambio, jsonb_build_object('confirmado', null, 'recodificado', null))),
    'consumo', case when v_ficha then jsonb_build_object('periodo_ultimo', f.periodo_ultimo, 'meses', f.consumo_meses, 'maximo', f.cons_max, 'minimo', f.cons_min,
                                                         'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura) end,
    'promedios', coalesce(v_prom, jsonb_build_object('estrato', null, 'barrio', null, 'uso', null)),
    'submedicion', f.submedicion,
    'pago', case when f.ultimo_pago is not null then f.ultimo_pago - 'corte' || jsonb_build_object('dias', v_hoy - (f.ultimo_pago ->> 'fecha')::date) end,
    'gestiones', jsonb_build_object(
       'emd_facturados', coalesce(f.emd, '[]'::jsonb),
       'terreno', coalesce((select jsonb_agg(jsonb_build_object('tipo', x.codigo, 'tipo_nombre', x.nombre, 'consecutivo', x.consecutivo, 'fecha', x.registrado_en, 'estado', x.estado) order by x.registrado_en desc)
                              from (select distinct on (t.codigo) t.codigo, t.nombre, r.consecutivo, r.registrado_en, r.estado
                                      from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                     where r.contrato = v_c and not r.oculto and t.codigo in ('suspension', 'corte', 'reconexion_servicio', 'reinstalacion', 'verificacion_posterior')
                                     order by t.codigo, r.registrado_en desc) x), '[]'::jsonb),
       'pqr', f.pqr,
       'reportes', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', x.consecutivo, 'tipo', x.codigo, 'tipo_nombre', x.nombre, 'fecha', x.registrado_en, 'estado', x.estado, 'resultado', x.resultado) order by x.registrado_en desc)
                               from (select t.codigo, t.nombre, r.consecutivo, r.registrado_en, r.estado, r.resultado
                                       from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                      where r.contrato = v_c and not r.oculto order by r.registrado_en desc limit 15) x), '[]'::jsonb),
       'reportes_total', (select count(*) from campo.reportes r where r.contrato = v_c),
       'actas', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', a.consecutivo, 'fecha', a.fecha_acta_fisica, 'registrado_en', a.registrado_en) order by a.registrado_en desc)
                            from (select a.consecutivo, a.fecha_acta_fisica, a.registrado_en from acta.v_actas_vigentes a where a.contrato = v_c order by a.registrado_en desc limit 10) a), '[]'::jsonb),
       -- actividades derivadas pendientes (decisión 19, provisional): revisiones con «¿Se requiere cambio de medidor?» = sí y sin instalación posterior
       'pendientes', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', r.consecutivo, 'tipo_nombre', t.nombre, 'fecha', r.registrado_en, 'sugiere', 'cambio_medidor') order by r.registrado_en desc)
                                 from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                where r.contrato = v_c and not r.oculto and t.codigo in ('revision_previa', 'revision_pqr') and r.datos -> 'req_cambio_medidor' = 'true'::jsonb
                                  and r.estado not in ('descartado', 'duplicado')
                                  and not exists (select 1 from campo.reportes i join campo.tipos_reporte ti on ti.id = i.tipo_id
                                                   where i.contrato = v_c and ti.codigo = 'instalacion_medidor' and i.registrado_en > r.registrado_en)), '[]'::jsonb)),
    'ubicacion', jsonb_build_object('predios_total', v_n_pred, 'predios', v_predios),
    -- Consultar direcciones (25-nov, David): las dos direcciones POR SEPARADO (sin coalesce) y los datos del predio principal en el censo, con limpieza mínima
    'direcciones', jsonb_build_object(
       'comercial', case when cs.contrato is not null then jsonb_build_object('direccion', campo.f_texto_censo(cs.direccion), 'barrio', campo.f_texto_censo(cs.barrio), 'corte', cs.periodo_carga) end,
       'catastro', case when pr.id is not null then jsonb_build_object('direccion', campo.f_texto_censo(pr.direccion), 'barrio', campo.f_texto_censo(pr.barrio)) end),
    'predio', case when pr.id is not null then jsonb_build_object('unih', campo.f_texto_censo(pr.unih), 'uninh', campo.f_texto_censo(pr.uninh),
       'clase_uso', campo.f_texto_censo(pr.clase_uso, true), 'act_eco', campo.f_texto_censo(pr.act_eco), 'predios_total', v_n_pred) end,
    'fotos', '[]'::jsonb,
    'cortes', jsonb_build_object('cartera', cs.periodo_carga, 'consumo', f.periodo_ultimo, 'ficha', v_estado.calculado_en),
    'ficha_disponible', v_estado.id is not null);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_analisis_observar(p_solicitante text, p_contrato text, p_tipo text, p_texto text DEFAULT NULL::text, p_direccion text DEFAULT NULL::text, p_contacto jsonb DEFAULT NULL::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v_c text := btrim(coalesce(p_contrato, '')); v_tipo text := btrim(coalesce(p_tipo, '')); v_txt text; v_dir text; v_con jsonb;
  v_obs uuid; v_der bigint; v_prev bigint; v_prev_obs uuid; v_prev_en timestamptz; v_vig integer; v_dup_rel text; v_dup_por text;
begin
  v_email := campo.f_autorizar_analisis(p_solicitante);
  if v_c !~ '^\d{1,12}$' then perform campo.f_error('Escriba solo los números del contrato (hasta 12 dígitos)'); end if;
  if v_c = '99999999' then perform campo.f_error('El contrato comodín no admite observaciones'); end if;
  if v_tipo not in ('desocupado', 'direccion_errada', 'actualizacion_datos', 'otra') then
    perform campo.f_error('La observación debe ser desocupado, dirección errada, actualización de datos u otra');
  end if;
  if not exists (select 1 from campo.consultas_analisis q where q.autor = v_email and q.contrato = v_c and q.existe and q.via = 'analisis' /* consultar direcciones: no cuenta la dirección pedida desde un formato */ and q.consultado_en > clock_timestamp() - interval '12 hours') then
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
  if v_tipo = 'desocupado' then
    -- «Desocupado» (sección 7, David 24-nov): vigencia. Dentro de vigencia_avisos_dias desde el aviso ORIGINAL del mismo contrato, esté pendiente o cerrado, no se
    -- crea otro: se anota «visto otra vez». La vigencia cuenta desde el aviso original, no desde el último «visto otra vez». Pasada la vigencia, aviso nuevo.
    v_vig := campo.f_param('vigencia_avisos_dias')::integer;
    select o.id, o.creado_en, d.id into v_prev_obs, v_prev_en, v_prev
      from campo.analisis_observaciones o join campo.derivadas d on d.observacion_id = o.id and d.actividad = 'aviso_' || v_tipo
     where o.contrato = v_c and o.tipo = v_tipo and o.creado_en > clock_timestamp() - make_interval(days => v_vig)
     order by o.creado_en desc limit 1;
    if v_prev is not null then
      insert into campo.analisis_avisos_vistos (observacion_id, autor, ip) values (v_prev_obs, v_email, left(p_ip, 64));
      perform campo.f_auditar(v_email, 'campo_analisis_visto_otra_vez', v_prev_obs::text, jsonb_build_object('tipo', v_tipo, 'derivada', v_prev), p_ip);
      return jsonb_build_object('repetida', true, 'regla', 'vigencia', 'derivada_id', v_prev, 'tipo', v_tipo, 'contrato', v_c, 'ya_avisado_en', v_prev_en,
        'estado', campo.f_derivada_estado(v_prev), 'vistos', (select count(*) from campo.analisis_avisos_vistos v where v.observacion_id = v_prev_obs),
        'vigencia_dias', v_vig, 'datos_no_guardados', false);
    end if;
  else
    -- Dirección errada, Actualización de datos y Otra (David, 24-nov): uno PENDIENTE a la vez por contrato («Otra»: con el mismo texto; un texto distinto crea
    -- su propio aviso). Cerrado el anterior, se puede avisar de nuevo sin importar los días.
    select o.id, o.creado_en, d.id into v_prev_obs, v_prev_en, v_prev
      from campo.analisis_observaciones o join campo.derivadas d on d.observacion_id = o.id and d.actividad = 'aviso_' || v_tipo
     where o.contrato = v_c and o.tipo = v_tipo and campo.f_derivada_estado(d.id) = 'pendiente'
       and (v_tipo <> 'otra' or lower(o.texto) = lower(v_txt))
     order by o.creado_en desc limit 1;
    if v_prev is not null then
      -- «Actualización de datos» (David, 24-nov, revisión 7.4): SIN restricción de envíos. Cada envío con datos es una entrega más del aviso pendiente del contrato
      -- (propietario, arrendatario, correcciones). Si ya hay una entrega VIGENTE con la misma relación o la misma cédula, se guarda igual y se avisa del posible duplicado.
      if v_tipo = 'actualizacion_datos' and v_con is not null then
        select x.datos ->> 'relacion', case when v_con ? 'relacion' and x.datos ->> 'relacion' = v_con ->> 'relacion' then 'relacion' else 'cedula' end
          into v_dup_rel, v_dup_por
          from campo.analisis_observacion_datos x
         where x.observacion_id = v_prev_obs and not exists (select 1 from campo.analisis_observacion_anulaciones a where a.datos_id = x.id)
           and ((v_con ? 'relacion' and x.datos ->> 'relacion' = v_con ->> 'relacion') or (v_con ? 'cedula' and x.datos ->> 'cedula' = v_con ->> 'cedula'))
         order by x.id desc limit 1;
        insert into campo.analisis_observacion_datos (observacion_id, datos, autor) values (v_prev_obs, v_con, v_email);
        perform campo.f_auditar(v_email, 'campo_analisis_datos_entrega', v_prev_obs::text, jsonb_build_object('derivada', v_prev, 'posible_duplicado', v_dup_por is not null), p_ip);
        return jsonb_build_object('repetida', true, 'regla', 'pendiente', 'derivada_id', v_prev, 'tipo', v_tipo, 'contrato', v_c, 'ya_avisado_en', v_prev_en,
          'estado', 'pendiente', 'datos_guardados', true, 'trae_datos', true, 'posible_duplicado', v_dup_por is not null,
          'duplicado_por', v_dup_por, 'duplicado_relacion', case when v_dup_por = 'relacion' then v_dup_rel end);
      end if;
      perform campo.f_auditar(v_email, 'campo_analisis_ya_pendiente', v_prev_obs::text, jsonb_build_object('tipo', v_tipo, 'derivada', v_prev), p_ip);
      return jsonb_build_object('repetida', true, 'regla', 'pendiente', 'derivada_id', v_prev, 'tipo', v_tipo, 'contrato', v_c, 'ya_avisado_en', v_prev_en,
        'estado', 'pendiente', 'datos_no_guardados', (v_con is not null or v_dir is not null));
    end if;
  end if;

  insert into campo.analisis_observaciones (contrato, tipo, texto, direccion_correcta, autor, ip) values (v_c, v_tipo, v_txt, v_dir, v_email, left(p_ip, 64)) returning id into v_obs;
  if v_con is not null then insert into campo.analisis_observacion_datos (observacion_id, datos, autor) values (v_obs, v_con, v_email); end if;
  insert into campo.derivadas (observacion_id, contrato, actividad) values (v_obs, v_c, 'aviso_' || v_tipo) returning id into v_der;
  -- Auditoría sin el contrato (queda en la bitácora del análisis, decisión 15) ni los textos ni los datos de contacto
  perform campo.f_auditar(v_email, 'campo_analisis_observar', v_obs::text, jsonb_build_object('tipo', v_tipo, 'derivada', v_der, 'trae_datos', v_con is not null), p_ip);
  return jsonb_build_object('repetida', false, 'observacion_id', v_obs, 'derivada_id', v_der, 'tipo', v_tipo, 'contrato', v_c, 'trae_datos', v_con is not null);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_origen text, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_orden_trabajo_id uuid DEFAULT NULL::uuid, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone, p_registro jsonb DEFAULT NULL::jsonb)
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

  -- Registro flexible: la dirección opcional va en Reportar anomalía (tipos generales) y en los formatos cuyo contrato no es obligatorio (David, 25-nov).
  -- Consultar direcciones (25-nov, David): y en CUALQUIER formato con contrato escrito, como «dirección encontrada en terreno» (distinta a la del contrato).
  if (v_dir is not null or v_barrio is not null or v_refer is not null) and v_contrato is null and not (campo.f_tipo_general(v_t.codigo) or v_t.requiere_contrato <> 'si') then
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
    -- Consultar direcciones (25-nov): foto de las dos direcciones del contrato tal como están al registrar (la lee la base, no el celular)
    if v_contrato is not null then
      insert into campo.reporte_direccion_contrato (reporte_id, contrato, direccion_comercial, barrio_comercial, direccion_catastro, barrio_catastro, predios_catastro)
      select v_id, v_contrato, d -> 'comercial' ->> 'direccion', d -> 'comercial' ->> 'barrio', d -> 'catastro' ->> 'direccion', d -> 'catastro' ->> 'barrio', (d ->> 'predios_total')::integer
        from (select campo.f_direcciones_contrato(v_contrato) as d) x;
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
                                             from campo.reporte_registro rr where rr.reporte_id = v.id))
        -- Consultar direcciones (25-nov): las dos direcciones del contrato al registrar (nulo si no hay fila)
        || jsonb_build_object('direccion_contrato', (select jsonb_build_object('comercial', dc.direccion_comercial, 'barrio_comercial', dc.barrio_comercial,
                                                   'catastro', dc.direccion_catastro, 'barrio_catastro', dc.barrio_catastro, 'predios_catastro', dc.predios_catastro)
                                             from campo.reporte_direccion_contrato dc where dc.reporte_id = v.id)),
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
           (select count(*) from campo.reporte_fotos fo where fo.reporte_id = p.id and fo.origen <> 'camara')::integer as fotos_adjuntadas,
           dc.direccion_comercial as dir_contrato, dc.barrio_comercial as barrio_contrato, dc.direccion_catastro as dir_catastro
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
      left join campo.reporte_registro rr on rr.reporte_id = p.id
      left join campo.reporte_direccion_contrato dc on dc.reporte_id = p.id
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
           'direccion', f.direccion, 'barrio', f.barrio, 'referencia', f.referencia, 'fotos_adjuntadas', f.fotos_adjuntadas)
           -- Consultar direcciones (25-nov)
           || jsonb_build_object('direccion_contrato', f.dir_contrato, 'barrio_contrato', f.barrio_contrato, 'direccion_catastro', f.dir_catastro) order by f.seq desc), '[]'::jsonb),
         min(f.seq), (select count(*) from pag) > v_lim
    into v_rows, v_min, v_mas from fila f;
  return jsonb_build_object('reportes', v_rows, 'total', v_total, 'siguiente', case when v_mas then v_min end, 'distancia_duplicados_m', v_eps);
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
           (select count(*) from campo.reporte_fotos fo where fo.reporte_id = p.id and fo.origen <> 'camara')::integer as fotos_adjuntadas,
           dc.direccion_comercial as dir_contrato, dc.barrio_comercial as barrio_contrato, dc.direccion_catastro as dir_catastro, dc.barrio_catastro as barrio_catastro
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join campo.estados_reporte es on es.codigo = p.estado left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
      left join campo.reporte_registro rr on rr.reporte_id = p.id
      left join campo.reporte_direccion_contrato dc on dc.reporte_id = p.id
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
           -- Consultar direcciones (25-nov)
           || jsonb_build_object('direccion_contrato', f.dir_contrato, 'barrio_contrato', f.barrio_contrato, 'direccion_catastro', f.dir_catastro, 'barrio_catastro', f.barrio_catastro)
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
        v_dc campo.reporte_direccion_contrato;   -- consultar direcciones (25-nov)
begin
  v_email := campo.f_autorizar_documento(p_solicitante, p_esquema, p_registro_id);
  if p_esquema = 'campo' then
    select * into v_r from campo.reportes where id = p_registro_id;
    select * into v_rr from campo.reporte_registro where reporte_id = p_registro_id;
    select * into v_dc from campo.reporte_direccion_contrato where reporte_id = p_registro_id;
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
      if v_rr.direccion is not null then v_cab := v_cab || jsonb_build_array(jsonb_build_array(case when v_r.contrato is not null then 'Dirección encontrada en terreno' else 'Dirección' end, v_rr.direccion)); end if;
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
    -- Consultar direcciones (25-nov): las dos direcciones del contrato al registrar (solo si hay fila: los reportes de antes quedan igual)
    if v_dc.reporte_id is not null then
      v_cab := v_cab || jsonb_build_array(jsonb_build_array('Dirección del contrato (base comercial)', coalesce(v_dc.direccion_comercial || coalesce(' · ' || v_dc.barrio_comercial, ''), 'Sin dato')));
      if v_dc.direccion_catastro is not null and upper(v_dc.direccion_catastro) is distinct from upper(v_dc.direccion_comercial) then
        v_cab := v_cab || jsonb_build_array(jsonb_build_array('Dirección del contrato (catastro)', v_dc.direccion_catastro || coalesce(' · ' || v_dc.barrio_catastro, '')));
      end if;
    end if;
    -- Sello: sin fila en reporte_registro se le concatena '' (el sello de un reporte anterior no cambia); con fila, la fila entra al sello
    v_sello := encode(sha256(convert_to(to_jsonb(v_r)::text || coalesce(v_sen::text, '') || case when v_rr.reporte_id is null then '' else to_jsonb(v_rr)::text end || case when v_dc.reporte_id is null then '' else to_jsonb(v_dc)::text end || coalesce((select string_agg(f.huella, ',' order by f.rol) from campo.firmas f
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

commit;
