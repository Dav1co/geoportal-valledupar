begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 10 — GUARDIA, CAPA DE CONTRATOS, VISTAS COMPARTIDAS, RANGOS DE MUESTREO, CAPA DE REPORTES DE COMERCIAL Y PARÁMETROS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: §30.1, §30.2 y §30.4 de la bitácora; respuestas de David al 6a (16-nov 10:55); plan 02 (Corte 6) y 01 sección D.
-- · Presupone el 6a aplicado (huella del conjunto de funciones de redes). Se publica junto con el 6a, después de él.
-- · Lee (no escribe) lo vivo de Comercial: public.catastro_valledupar, public.cartera_suscripcion, bi_interno.ficha_contrato y su estado; y de planta:
--   tecnica.v_registros_estado, tecnica.variables y tecnica.f_referencia_vigente. Nada de eso cambia.
-- · ⚠ Se reemplazan 2 RPC del 6a (geoportal_redes_geovisor y geoportal_redes_geovisor_capa), con su texto exacto en la reversa.
-- · ⚠ redes.geovisor_capas (del 6a): se amplía el CHECK de «fuente» con «contratos» y se ponen al día 3 filas (contratos, reportes de Comercial y muestreo).
-- =====================================================================
do $$
begin
  if to_regclass('redes.geovisor_capas') is null then raise exception 'Falta el Corte 6a: aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '91a4d3e6e1c3539d8a447cb00a52d735' then
    raise exception 'Las funciones de redes no son las del Corte 6a (o el Corte 6b ya está aplicado): deténgase y avise';
  end if;
  if to_regclass('redes.contratos_capa') is not null or to_regclass('redes.vistas_compartidas') is not null then
    raise exception 'Las tablas del 6b ya existen: el Corte 6b parece aplicado';
  end if;
  -- lo vivo que se lee
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catastro_valledupar' and column_name in ('id', 'cod_usuario', 'direccion', 'barrio', 'geom')) <> 5
     or (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion'
          and column_name in ('contrato', 'estado', 'nombre', 'direccion', 'barrio', 'categoria', 'periodo_carga')) <> 7
     or (select count(*) from information_schema.columns where table_schema = 'bi_interno' and table_name = 'ficha_contrato'
          and column_name in ('contrato', 'periodo_ultimo', 'uso', 'consumo_meses', 'cons_prom', 'meses_con_lectura', 'medidor_anios')) <> 7
     or to_regclass('bi_interno.ficha_contrato_estado') is null then
    raise exception 'Las tablas de Comercial (catastro, cartera diaria o ficha del contrato) no tienen las columnas esperadas: deténgase y avise';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'tecnica' and table_name = 'v_registros_estado'
        and column_name in ('formulario', 'variable_id', 'punto_id', 'valor', 'muestra_ts', 'excluido')) <> 6
     or to_regprocedure('tecnica.f_referencia_vigente(bigint,bigint,bigint)') is null
     or (select count(*) from tecnica.variables where codigo in ('cloro_residual_libre', 'turbiedad', 'cloro_libre_tanque', 'turbiedad_salida')) <> 4 then
    raise exception 'Faltan las variables de Muestreo o de Salida, la vista de registros o el resolutor de referencias: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. CAPA DE CONTRATOS (§30.1; 01 sección D). Una fila por contrato con su punto (el predio de menor id, como contrato_tramo), uso, estado comercial,
--    consumo promedio y años del medidor. SIN nombre, teléfono, dirección ni deuda: esos van solo en la tarjeta, pedidos al tocar.
--    Es derivada: se rehace entera con redes.f_refrescar_contratos_capa() cuando cambia la ficha del contrato o tiene más de un día.
-- ---------------------------------------------------------------------
create table redes.contratos_capa (
  contrato      text primary key,
  geom          geometry(Point, 4326) not null,
  uso           text,
  estado        text not null check (estado in ('activo', 'retirado', 'otro', 'sin_dato')),
  consumo_prom  numeric,
  medidor_anios integer
);
create index ix_contratos_capa_geom on redes.contratos_capa using gist (geom);
comment on table redes.contratos_capa is 'Corte 6b: capa de contratos del geovisor técnico. Derivada (se rehace entera). Sin datos personales.';
create table redes.contratos_capa_estado (
  id           integer primary key check (id = 1),
  firma        text not null,
  filas        integer not null,
  calculado_en timestamptz not null,
  duracion_ms  integer not null
);

-- ---------------------------------------------------------------------
-- 2. VISTAS COMPARTIDAS (§30.2): el enlace guarda capas, colores, fechas, centro y zoom; nunca datos personales. Quien lo abre inicia sesión y ve solo
--    las capas para las que tiene permiso. Solo inserción.
-- ---------------------------------------------------------------------
create table redes.vistas_compartidas (
  id        text primary key check (id ~ '^[a-z0-9]{10}$'),
  capas     text[] not null check (cardinality(capas) between 0 and 40),
  colores   text not null check (colores in ('tipo', 'material', 'edad')),
  periodo   jsonb not null,
  lon       numeric(9, 6) not null,
  lat       numeric(9, 6) not null,
  zoom      numeric(4, 2) not null check (zoom between 10 and 20),
  atenuadas text[] not null default '{}',
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
comment on table redes.vistas_compartidas is 'Corte 6b (§30.2): vistas del geovisor compartidas por enlace. Sin datos personales. Solo inserción.';

-- ---------------------------------------------------------------------
-- 3. RANGOS DEL MUESTREO (respuesta 4 de David al 6a): el color del punto sale de la referencia de la variable de Muestreo si la tiene (por punto o general);
--    si no, de la referencia de la variable equivalente de Salida (Res. 2115 de 2007 y criterio de planta). Una fila por variable que colorea.
-- ---------------------------------------------------------------------
create table redes.muestreo_rangos (
  variable_muestreo text primary key,
  variable_salida   text not null,
  orden             integer not null
);
insert into redes.muestreo_rangos values ('cloro_residual_libre', 'cloro_libre_tanque', 1), ('turbiedad', 'turbiedad_salida', 2);
comment on table redes.muestreo_rangos is 'Corte 6b: qué variables colorean un punto de muestreo y de qué variable de Salida toman el rango cuando no tienen el suyo.';

do $$
begin
  execute 'create trigger t_solo_agregar before update or delete on redes.vistas_compartidas for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on redes.vistas_compartidas for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_no_borrar before delete on redes.muestreo_rangos for each row execute function tecnica.f_solo_agregar()';
  execute 'alter table redes.contratos_capa enable row level security';
  execute 'alter table redes.contratos_capa_estado enable row level security';
  execute 'alter table redes.vistas_compartidas enable row level security';
  execute 'alter table redes.muestreo_rangos enable row level security';
end $$;

-- ---------------------------------------------------------------------
-- 4. CAPA DE REPORTES DE COMERCIAL (§30.4), lista para que el Corte 8 la llene: la vista vacía con sus columnas. El Corte 8 la reemplaza (create or replace)
--    leyendo los reportes compartidos (anomalías y revisiones). con_contrato: azul si trae código de contrato, rojo si es un posible clandestino.
-- ---------------------------------------------------------------------
create view redes.v_reportes_comercial as
select null::text as codigo, null::text as tipo, null::text as subtipo, null::text as area, null::boolean as con_contrato, null::text as estado,
       null::timestamptz as registrado_en, null::numeric(9, 6) as lat, null::numeric(9, 6) as lon
 where false;
comment on view redes.v_reportes_comercial is 'Corte 6b: capa de reportes de Comercial del geovisor, vacía hasta el Corte 8. Sin datos del suscriptor ni textos.';

-- ---------------------------------------------------------------------
-- 5. EL CATÁLOGO DEL GEOVISOR: contratos pasa a capa propia; reportes de Comercial se puede encender (vacía hasta el 8); muestreo con su color.
-- ---------------------------------------------------------------------
alter table redes.geovisor_capas drop constraint geovisor_capas_fuente_check;
alter table redes.geovisor_capas add constraint geovisor_capas_fuente_check check (fuente in ('tesela', 'geojson', 'preparada', 'contratos'));
update redes.geovisor_capas set fuente = 'contratos', estado = 'activa', nota = 'Desde el zoom 16. Al tocar un contrato: su consumo, nombre y dirección (la consulta queda registrada)'
 where codigo = 'contratos';
update redes.geovisor_capas set fuente = 'geojson', por_fecha = true, nota = 'Se llena con el Corte 8: azul con contrato, rojo posible clandestino. Se puede atenuar'
 where codigo = 'reportes_comercial';
update redes.geovisor_capas set nota = 'Color por el último cloro y la turbiedad frente a los rangos de Salida (Res. 2115 de 2007 y criterio de planta)'
 where codigo = 'muestreo';

-- ---------------------------------------------------------------------
-- 6. PARÁMETROS
-- ---------------------------------------------------------------------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('geovisor_zoom_contratos', 16, 'zoom', 13, 20, 'Geovisor (Corte 6b): desde este zoom se ven los contratos'),
  ('geovisor_contratos_horas', 24, 'horas', 1, 720, 'Geovisor: la capa de contratos se rehace si tiene más de estas horas o si cambió la ficha del contrato'),
  ('geovisor_muestreo_dias', 30, 'días', 1, 365, 'Geovisor: un resultado de muestreo más viejo que esto no colorea el punto («sin muestra reciente»)')
on conflict (clave) do nothing;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 26 — FUNCIONES NUEVAS
--   · redes.f_estado_contrato, redes.f_refrescar_contratos_capa y redes.f_contratos_capa_al_dia: la capa de contratos (derivada, sin datos personales).
--   · redes.f_muestreo_calidad: el último cloro y la última turbiedad de un punto frente a sus rangos (respuesta 4 de David al 6a).
--   · public.geoportal_redes_geovisor_mvt_contratos: la tesela de los contratos (número, uso, estado, consumo promedio y años del medidor).
--   · public.geoportal_redes_contrato_tarjeta: la tarjeta del contrato al tocarlo (§30.1), con nombre, dirección y barrio; lectura auditada; sin teléfono ni deuda.
--   · public.geoportal_redes_vista_compartir y _vista_abrir: compartir la vista con un enlace (§30.2).
-- =====================================================================

-- ---------- Capa de contratos ----------
create function redes.f_estado_contrato(p text) returns text language sql immutable set search_path = pg_catalog as $$
  select case when nullif(btrim(coalesce(p, '')), '') is null then 'sin_dato' when upper(btrim(p)) like 'RETIR%' then 'retirado'
              when upper(btrim(p)) like 'ACTIV%' then 'activo' else 'otro' end $$;

-- Rehace la capa entera: un punto por contrato (el predio de menor id, como redes.contrato_tramo); sin el comodín (99999999) ni el «0».
create function redes.f_refrescar_contratos_capa() returns integer
language plpgsql security definer set search_path = public, redes, bi_interno, extensions, pg_temp as $$
declare t0 timestamptz := clock_timestamp(); n integer;
begin
  delete from redes.contratos_capa;
  insert into redes.contratos_capa (contrato, geom, uso, estado, consumo_prom, medidor_anios)
  select c.cod_usuario, c.geom,
         coalesce(nullif(btrim(f.uso), '(sin dato)'), nullif(regexp_replace(btrim(coalesce(cs.categoria, '')), '^-?[0-9]+\s+', ''), '')),
         redes.f_estado_contrato(cs.estado), f.cons_prom, f.medidor_anios
    from (select distinct on (cv.cod_usuario) cv.cod_usuario, cv.geom from public.catastro_valledupar cv
           where cv.cod_usuario ~ '^[0-9]{1,12}$' and cv.cod_usuario not in ('0', '99999999') and cv.geom is not null
           order by cv.cod_usuario, cv.id) c
    left join bi_interno.ficha_contrato f on f.contrato = c.cod_usuario
    left join lateral (select s.estado, s.categoria from public.cartera_suscripcion s where s.contrato = c.cod_usuario order by s.periodo_carga desc nulls last limit 1) cs on true;
  get diagnostics n = row_count;
  insert into redes.contratos_capa_estado (id, firma, filas, calculado_en, duracion_ms)
  values (1, coalesce((select calculado_en::text from bi_interno.ficha_contrato_estado where id = 1), 'sin ficha'), n, clock_timestamp(),
          (extract(epoch from clock_timestamp() - t0) * 1000)::integer)
  on conflict (id) do update set firma = excluded.firma, filas = excluded.filas, calculado_en = excluded.calculado_en, duracion_ms = excluded.duracion_ms;
  return n;
end $$;

-- La rehace si cambió la ficha del contrato (cálculo mensual) o si tiene más de geovisor_contratos_horas. Si otra sesión la está rehaciendo, no espera.
create function redes.f_contratos_capa_al_dia() returns boolean
language plpgsql security definer set search_path = public, redes, bi_interno, pg_temp as $$
declare e redes.contratos_capa_estado%rowtype;
begin
  select * into e from redes.contratos_capa_estado where id = 1;
  if found and e.firma = coalesce((select calculado_en::text from bi_interno.ficha_contrato_estado where id = 1), 'sin ficha')
     and e.calculado_en > clock_timestamp() - make_interval(hours => floor(redes.f_param('geovisor_contratos_horas'))::integer) then
    return false;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('redes.contratos_capa')) then return false; end if;
  perform redes.f_refrescar_contratos_capa();
  return true;
end $$;

-- ---------- Calidad de un punto de muestreo: el último resultado (no excluido) de cada variable que colorea, frente a su rango ----------
-- Rango: el de la variable de Muestreo si lo tiene (por punto o general); si no, el general de la variable de Salida; si Salida solo tiene rangos por planta,
-- el más estricto de ellos. Estado: «fuera» si alguno reciente se sale; «dentro» si los recientes con rango están dentro; «sin_rango»; «sin_muestra».
create function redes.f_muestreo_calidad(p_punto_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_dias integer := floor(redes.f_param('geovisor_muestreo_dias'))::integer; m record; u record; rg record; v_med jsonb := '[]'::jsonb;
        v_reciente boolean; v_dentro boolean; v_fuente text; n_rec integer := 0; n_rango integer := 0; n_fuera integer := 0;
begin
  for m in select r.variable_muestreo, r.variable_salida, v.id as vid, v.nombre, v.unidad, s.id as sid
             from redes.muestreo_rangos r join tecnica.variables v on v.codigo = r.variable_muestreo join tecnica.variables s on s.codigo = r.variable_salida order by r.orden loop
    select e.valor, e.muestra_ts into u from tecnica.v_registros_estado e
     where e.formulario::text = 'muestreo' and e.punto_id = p_punto_id and e.variable_id = m.vid and not e.excluido
     order by e.muestra_ts desc, e.id desc limit 1;
    if not found then continue; end if;
    v_fuente := 'muestreo';
    select x.ref_min, x.ref_max into rg from tecnica.f_referencia_vigente(m.vid, null, p_punto_id) x;
    if not found or (rg.ref_min is null and rg.ref_max is null) then
      v_fuente := 'salida';
      select x.ref_min, x.ref_max into rg from tecnica.f_referencia_vigente(m.sid, null, null) x;
      if not found or (rg.ref_min is null and rg.ref_max is null) then
        select max(r.ref_min) as ref_min, min(r.ref_max) as ref_max into rg from tecnica.referencias r where r.activa and r.variable_id = m.sid and r.punto_id is null;
      end if;
    end if;
    v_reciente := u.muestra_ts >= clock_timestamp() - make_interval(days => v_dias);
    v_dentro := case when rg.ref_min is null and rg.ref_max is null then null
                     else (rg.ref_min is null or u.valor >= rg.ref_min) and (rg.ref_max is null or u.valor <= rg.ref_max) end;
    if v_reciente then
      n_rec := n_rec + 1;
      if v_dentro is not null then n_rango := n_rango + 1; if not v_dentro then n_fuera := n_fuera + 1; end if; end if;
    end if;
    v_med := v_med || jsonb_build_array(jsonb_build_object('variable', m.variable_muestreo, 'nombre', m.nombre, 'unidad', m.unidad, 'valor', u.valor, 'cuando', u.muestra_ts,
               'reciente', v_reciente, 'min', rg.ref_min, 'max', rg.ref_max, 'dentro', v_dentro,
               'rango', case when rg.ref_min is null and rg.ref_max is null then null else v_fuente end));
  end loop;
  return jsonb_build_object('calidad', case when n_rec = 0 then 'sin_muestra' when n_fuera > 0 then 'fuera' when n_rango > 0 then 'dentro' else 'sin_rango' end, 'medidas', v_med);
end $$;

-- ---------- Tesela de contratos (supervisores y administrador; el operador en solo lectura no la ve) ----------
create function public.geoportal_redes_geovisor_mvt_contratos(p_solicitante text, p_z integer, p_x integer, p_y integer) returns text
language plpgsql stable security definer set search_path = public, redes, extensions, pg_temp as $$
declare a record; v_env geometry; v bytea;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La capa de contratos es para supervisores' using errcode = '42501'; end if;
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < redes.f_param('geovisor_zoom_contratos') then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  select ST_AsMVT(t, 'contratos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(c.geom, 3857), v_env, 4096, 32, true) as geom, c.contrato, coalesce(c.uso, '') as uso, c.estado,
           c.consumo_prom::real as consumo, c.medidor_anios as medidor_anios
      from redes.contratos_capa c where c.geom && ST_Transform(v_env, 4326)) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $$;

-- ---------- Tarjeta del contrato (§30.1): se pide al tocarlo; el nombre y la dirección son dato personal: solo en pantalla, lectura auditada ----------
create function public.geoportal_redes_contrato_tarjeta(p_solicitante text, p_contrato text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, bi_interno, pg_temp as $$
declare a record; c redes.contratos_capa%rowtype; cs record; pr record; f record; v_c text := btrim(coalesce(p_contrato, ''));
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;
  if v_c !~ '^[0-9]{1,12}$' then perform tecnica.f_error('Escriba solo los números del contrato'); end if;
  select * into c from redes.contratos_capa where contrato = v_c;
  if not found then perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002'); end if;
  select s.nombre, s.estado, s.categoria, s.direccion, s.barrio, s.periodo_carga into cs
    from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select cv.direccion, cv.barrio into pr from public.catastro_valledupar cv where cv.cod_usuario = v_c order by cv.id limit 1;
  select fc.periodo_ultimo, fc.uso, fc.consumo_meses, fc.cons_prom, fc.meses_con_lectura, fc.medidor_anios into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  -- la lectura queda registrada: quién, cuándo y qué contrato (NUNCA el nombre ni la dirección)
  perform tecnica.f_auditar(a.email, 'redes_contrato_tarjeta', v_c, jsonb_build_object('datos', 'nombre, dirección y barrio', 'desde', 'geovisor'), p_ip);
  return jsonb_build_object(
    'contrato', v_c,
    'estado', c.estado, 'estado_texto', nullif(btrim(cs.estado), ''),
    'uso', c.uso,
    'consumo', case when f.periodo_ultimo is not null then jsonb_build_object(
        'periodo_ultimo', f.periodo_ultimo, 'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura,
        'meses', (select coalesce(jsonb_agg(jsonb_build_object('periodo', m ->> 'periodo', 'm3', m -> 'm3', 'sin_dato', coalesce((m ->> 'sin_dato')::boolean, false),
                                                               'lectura_real', coalesce((m ->> 'lectura_real')::boolean, false)) order by k), '[]'::jsonb)
                    from jsonb_array_elements(f.consumo_meses) with ordinality x(m, k))) end,
    'medidor_anios', f.medidor_anios,
    'tramo', (select v.codigo from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id where t.contrato = v_c),
    'suscriptor', jsonb_build_object(                                  -- DATO PERSONAL: solo en pantalla
      'nombre', nullif(btrim(cs.nombre), ''),
      'direccion', coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')),
      'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), ''))),
    'corte', cs.periodo_carga);
end $$;

-- ---------- Compartir la vista (§30.2) ----------
-- La guardan los supervisores y el administrador (el operador en solo lectura no comparte). Solo capas que existen y que la persona ve; sin datos personales.
create function public.geoportal_redes_vista_compartir(p_solicitante text, p_vista jsonb) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, pg_temp as $$
declare a record; v jsonb := coalesce(p_vista, '{}'::jsonb); v_capas text[]; v_aten text[]; v_malas text[]; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        v_modo text := coalesce(v #>> '{periodo,modo}', 'hoy'); v_desde date; v_hasta date; v_lon numeric; v_lat numeric; v_zoom numeric; v_id text;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'El geovisor en solo lectura no comparte vistas' using errcode = '42501'; end if;
  if jsonb_typeof(v) <> 'object' or jsonb_typeof(v -> 'capas') <> 'array' then perform tecnica.f_error('La vista no es válida'); end if;
  select array_agg(x order by x) into v_capas from (select distinct jsonb_array_elements_text(v -> 'capas') x) z;
  v_capas := coalesce(v_capas, '{}');
  select array_agg(x) into v_aten from (select distinct jsonb_array_elements_text(coalesce(v -> 'atenuadas', '[]'::jsonb)) x) z;
  v_aten := coalesce(v_aten, '{}');
  select array_agg(x) into v_malas from unnest(v_capas || v_aten) x
   where not exists (select 1 from redes.geovisor_capas g where g.codigo = x and g.activa and g.fuente <> 'preparada');
  if v_malas is not null then perform tecnica.f_error(format('Capas que no existen en el geovisor: %s', array_to_string(v_malas, ', '))); end if;
  if coalesce(v ->> 'colores', '') not in ('tipo', 'material', 'edad') then perform tecnica.f_error('Los colores son por tipo, material o edad'); end if;
  if v_modo not in ('hoy', 'semana', 'rango') then perform tecnica.f_error('Las fechas son hoy, 7 días o un rango'); end if;
  if v_modo = 'rango' then
    begin
      v_desde := (v #>> '{periodo,desde}')::date; v_hasta := (v #>> '{periodo,hasta}')::date;
    exception when others then perform tecnica.f_error('Las fechas del rango no son válidas');
    end;
    if v_desde is null or v_hasta is null or v_desde > v_hasta or v_hasta > v_hoy
       or v_desde < (v_hasta - make_interval(months => floor(redes.f_param('geovisor_rango_meses'))::integer))::date then
      perform tecnica.f_error(format('El rango de fechas no es válido (hasta hoy y de máximo %s meses)', floor(redes.f_param('geovisor_rango_meses'))));
    end if;
  end if;
  if jsonb_typeof(v -> 'lon') <> 'number' or jsonb_typeof(v -> 'lat') <> 'number' or jsonb_typeof(v -> 'zoom') <> 'number' then perform tecnica.f_error('Falta el centro o el zoom'); end if;
  v_lon := round((v ->> 'lon')::numeric, 6); v_lat := round((v ->> 'lat')::numeric, 6); v_zoom := round((v ->> 'zoom')::numeric, 2);
  if v_lon not between redes.f_param('caja_lon_min') and redes.f_param('caja_lon_max') or v_lat not between redes.f_param('caja_lat_min') and redes.f_param('caja_lat_max') then
    perform tecnica.f_error('El centro del mapa está fuera de Valledupar');
  end if;
  if v_zoom not between 10 and 20 then perform tecnica.f_error('El zoom no es válido'); end if;
  loop
    v_id := substr(md5(random()::text || clock_timestamp()::text || a.email), 1, 10);
    exit when not exists (select 1 from redes.vistas_compartidas where id = v_id);
  end loop;
  insert into redes.vistas_compartidas (id, capas, colores, periodo, lon, lat, zoom, atenuadas, autor)
  values (v_id, v_capas, v ->> 'colores', jsonb_build_object('modo', v_modo, 'desde', v_desde, 'hasta', v_hasta), v_lon, v_lat, v_zoom, v_aten, a.email);
  perform tecnica.f_auditar(a.email, 'redes_vista_compartir', v_id, jsonb_build_object('capas', v_capas), null);
  return jsonb_build_object('id', v_id);
end $$;

-- Abrir un enlace: quien lo abre ya inició sesión (lo exige la Edge) y debe tener el geovisor; ve solo las capas para las que tiene permiso.
-- Al operador en solo lectura se le abren las actividades de hoy, aunque el enlace diga otras fechas.
create function public.geoportal_redes_vista_abrir(p_solicitante text, p_id text) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, pg_temp as $$
declare a record; v redes.vistas_compartidas%rowtype; v_ok text[]; v_omit text[]; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; v_modo text;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if coalesce(p_id, '') !~ '^[a-z0-9]{10}$' then perform tecnica.f_error('El enlace no es válido'); end if;
  select * into v from redes.vistas_compartidas where id = p_id;
  if not found then perform tecnica.f_error('Ese enlace no existe', 'P0002'); end if;
  select array_agg(x order by x) filter (where ok), array_agg(nombre order by x) filter (where not ok) into v_ok, v_omit
    from (select x, coalesce(g.nombre, x) as nombre, coalesce(g.activa and g.fuente <> 'preparada' and (a.completo or not g.solo_completo), false) as ok
            from unnest(v.capas) x left join redes.geovisor_capas g on g.codigo = x) z;
  v_modo := case when not a.completo then 'hoy' else v.periodo ->> 'modo' end;
  perform tecnica.f_auditar(a.email, 'redes_vista_abrir', v.id, jsonb_build_object('omitidas', coalesce(cardinality(v_omit), 0)), null);
  return jsonb_build_object('id', v.id, 'capas', to_jsonb(coalesce(v_ok, '{}')), 'omitidas', to_jsonb(coalesce(v_omit, '{}')), 'colores', v.colores,
    'periodo', jsonb_build_object('modo', v_modo,
                                  'desde', case v_modo when 'hoy' then v_hoy when 'semana' then v_hoy - 6 else (v.periodo ->> 'desde')::date end,
                                  'hasta', case v_modo when 'rango' then (v.periodo ->> 'hasta')::date else v_hoy end),
    'lon', v.lon, 'lat', v.lat, 'zoom', v.zoom, 'atenuadas', to_jsonb(v.atenuadas), 'creada_en', v.creado_en,
    'fechas_cambiadas', not a.completo and v.periodo ->> 'modo' <> 'hoy');
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 6a con cambios exactos, aplicados una sola vez:
--   · geoportal_redes_geovisor: rehace la capa de contratos si hace falta (deja de ser STABLE), el zoom de contratos, «compartir» y el estado de la capa;
--   · geoportal_redes_geovisor_capa: el color del muestreo (último resultado frente a los rangos) y la capa de reportes de Comercial (vacía hasta el Corte 8).
-- =====================================================================
-- public.geoportal_redes_geovisor(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare a record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if a.completo then perform redes.f_contratos_capa_al_dia(); end if;      -- Corte 6b: la capa de contratos se rehace sola si cambió la ficha o tiene más de un día
  return jsonb_build_object(
    'perfil', case when a.admin then 'admin' when a.completo then 'supervisor' else 'operador' end,
    'completo', a.completo, 'perfiles', to_jsonb(a.perfiles),
    'hoy', (clock_timestamp() at time zone 'America/Bogota')::date,
    'rango_meses', floor(redes.f_param('geovisor_rango_meses'))::integer,
    'max_elementos', floor(redes.f_param('geovisor_max_elementos'))::integer,
    'zoom', jsonb_build_object('min', redes.f_param('geovisor_zoom_min'), 'red_completa', redes.f_param('geovisor_zoom_red_completa'),
                               'nodos', redes.f_param('geovisor_zoom_nodos'), 'accesorios', redes.f_param('geovisor_zoom_acc'),
                               'contratos', redes.f_param('geovisor_zoom_contratos')),
    'version', (select coalesce(sum(version), 0) from redes.tesela_version),
    'formularios', jsonb_build_object('danos_fallas', redes.f_puede_formulario(a.email, 'danos_fallas'),
                                      'mantenimiento', redes.f_puede_formulario(a.email, 'mantenimiento')),
    'ficha', a.completo, 'compartir', a.completo,
    'contratos_capa', case when a.completo then (select jsonb_build_object('filas', e.filas, 'calculado_en', e.calculado_en) from redes.contratos_capa_estado e where e.id = 1) end,
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre, 'grupo', g.grupo, 'fuente', g.fuente, 'estado', g.estado, 'nota', g.nota,
                                          'prefijos', to_jsonb(g.prefijos), 'por_fecha', g.por_fecha,
                                          'encendida', exists (select 1 from redes.capas_por_perfil c where c.capa = g.codigo and c.encendida and c.perfil = any (a.perfiles)))
             order by g.orden)
        from redes.geovisor_capas g where g.activa and (a.completo or not g.solo_completo)), '[]'::jsonb),
    'tipos', coalesce((select jsonb_object_agg(t.prefijo, t.nombre_visible) from redes.v_tipo_visible t), '{}'::jsonb),
    'estados', coalesce((select jsonb_object_agg(e.codigo, e.nombre) from redes.estados_activo e), '{}'::jsonb),
    'materiales', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', m.nombre) order by m.codigo) from redes.materiales m), '[]'::jsonb),
    -- solo el administrador: la tabla de capas por omisión, para editarla (N-11)
    'por_perfil', case when a.admin then coalesce((
      select jsonb_agg(jsonb_build_object('perfil', c.perfil, 'capa', c.capa, 'encendida', c.encendida, 'actualizado_en', c.actualizado_en, 'actualizado_por', c.actualizado_por)
             order by c.perfil, c.capa) from redes.capas_por_perfil c), '[]'::jsonb) end);
end $function$;

-- public.geoportal_redes_geovisor_capa(text,text,date,date)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor_capa(p_solicitante text, p_capa text, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare a record; g redes.geovisor_capas%rowtype; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        v_desde date := coalesce(p_desde, v_hoy); v_hasta date := coalesce(p_hasta, v_hoy); v_max integer := floor(redes.f_param('geovisor_max_elementos'))::integer;
        v_ini timestamptz; v_fin timestamptz; v_f jsonb; v_n integer;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into g from redes.geovisor_capas where codigo = p_capa and activa;
  if not found or g.fuente <> 'geojson' then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if g.solo_completo and not a.completo then raise exception 'Capa solo para supervisores' using errcode = '42501'; end if;
  if g.por_fecha then
    if v_desde > v_hasta then perform tecnica.f_error('La fecha inicial es posterior a la final'); end if;
    if v_hasta > v_hoy then perform tecnica.f_error('La fecha final no puede ser futura'); end if;
    if v_desde < (v_hasta - make_interval(months => floor(redes.f_param('geovisor_rango_meses'))::integer))::date then
      perform tecnica.f_error(format('El rango de fechas es de máximo %s meses', floor(redes.f_param('geovisor_rango_meses'))::integer));
    end if;
    if not a.completo and (v_desde <> v_hoy or v_hasta <> v_hoy) then raise exception 'El geovisor en solo lectura muestra solo las actividades del día' using errcode = '42501'; end if;
  end if;
  v_ini := v_desde::timestamp at time zone 'America/Bogota';
  v_fin := (v_hasta + 1)::timestamp at time zone 'America/Bogota';

  if p_capa = 'danos' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(d.lon, d.lat)),
               'properties', jsonb_build_object('codigo', d.codigo, 'clase', d.clase, 'tipo', d.tipo_nombre, 'sistema', d.sistema, 'estado', d.estado,
                                                'activo', d.activo_codigo, 'cuando', d.t_detectado, 'riesgo', d.riesgo, 'origen', d.origen)) as f, d.t_detectado as o
        from redes.v_dano d
       where d.estado <> 'oculto' and d.t_detectado >= v_ini and d.t_detectado < v_fin and d.lat is not null
       order by d.t_detectado desc limit v_max + 1) x;
  elsif p_capa = 'intervenciones' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(i.lon, i.lat)),
               'properties', jsonb_build_object('codigo', i.codigo, 'tipo_codigo', i.tipo_codigo, 'tipo', i.tipo_nombre, 'sistema', i.sistema, 'estado', i.estado,
                                                'activo', i.activo_codigo, 'dano', i.dano_codigo, 'cuando', i.t_inicio, 'fin', i.t_fin, 'ejecutor', i.ejecutor)) as f, i.t_inicio as o
        from redes.v_intervencion i
       where i.estado not in ('oculta', 'anulada') and i.t_inicio >= v_ini and i.t_inicio < v_fin and i.lat is not null
       order by i.t_inicio desc limit v_max + 1) x;
  elsif p_capa = 'reportes_bot' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.radicado, 'canal', r.canal, 'tipo', r.tipo_bot, 'estado', r.estado_bot, 'dano', r.dano_codigo,
                                                'cuando', r.recibido_en)) as f, r.recibido_en as o
        from redes.v_reporte_externo r
       where r.recibido_en >= v_ini and r.recibido_en < v_fin and r.lat is not null
       order by r.recibido_en desc limit v_max + 1) x;
  elsif p_capa = 'muestreo' then
    select coalesce(jsonb_agg(f order by o), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(u.lon, u.lat)),
               'properties', jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'exactitud', u.exactitud) || redes.f_muestreo_calidad(p.id)) as f, p.codigo as o
        from tecnica.puntos p join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
       where p.tipo = 'muestreo' and p.activo
       order by p.codigo limit v_max + 1) x;
  elsif p_capa = 'reportes_comercial' then      -- Corte 6b (§30.4): la vista la llena el Corte 8; azul con contrato, rojo posible clandestino
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.codigo, 'tipo', r.tipo, 'subtipo', r.subtipo, 'area', r.area, 'con_contrato', coalesce(r.con_contrato, false),
                                                'estado', r.estado, 'cuando', r.registrado_en)) as f, r.registrado_en as o
        from redes.v_reportes_comercial r
       where r.registrado_en >= v_ini and r.registrado_en < v_fin and r.lat is not null
       order by r.registrado_en desc limit v_max + 1) x;
  else
    perform tecnica.f_error('Esa capa todavía no tiene datos', 'P0002');
  end if;

  if v_n > v_max then v_f := v_f - v_max; end if;      -- se quitó el elemento de más (el último de la lista)
  return jsonb_build_object('type', 'FeatureCollection', 'capa', p_capa, 'desde', case when g.por_fecha then v_desde end, 'hasta', case when g.por_fecha then v_hasta end,
                            'recortada', v_n > v_max, 'features', v_f);
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vista nuevas: nadie de la API. Las 4 RPC nuevas: solo execute a service_role (la Edge geoportal-redes). Las 4 funciones internas: nadie.
-- =====================================================================
revoke all on table redes.contratos_capa, redes.contratos_capa_estado, redes.vistas_compartidas, redes.muestreo_rangos, redes.v_reportes_comercial
  from public, anon, authenticated, service_role;
revoke all on function redes.f_estado_contrato(text), redes.f_refrescar_contratos_capa(), redes.f_contratos_capa_al_dia(), redes.f_muestreo_calidad(bigint)
  from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_vista_compartir', 'geoportal_redes_vista_abrir') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte6b', 'migracion_redes_corte6b', null, jsonb_build_object('tablas', jsonb_build_array('redes.contratos_capa', 'redes.contratos_capa_estado', 'redes.vistas_compartidas', 'redes.muestreo_rangos'),
        'vista', 'redes.v_reportes_comercial',
        'rpc', jsonb_build_array('geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_vista_compartir', 'geoportal_redes_vista_abrir'),
        'reemplazadas', 2), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes11.*), sus contratos de prueba (99000000xxxx, con predio, cartera y ficha, como la suite
-- viva de Análisis de contrato), sus puntos de muestreo (MUE-95nn) con sus muestras, y una referencia propia de Muestreo para un punto.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 6b … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4200 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.3000 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.trae(p_b64 text, p_txt text) returns boolean language sql as $$
  select coalesce(position(convert_to(p_txt, 'UTF8') in decode(nullif(p_b64, ''), 'base64')) > 0, false) $$;
create function pg_temp.tesela(p_quien text, p_z integer, x numeric, y numeric) returns text language sql as $$
  select public.geoportal_redes_geovisor_mvt_contratos(p_quien, p_z, floor((pg_temp.lon(x) + 180) / 360 * (1 << p_z))::integer,
                                                       floor((1 - ln(tan(radians(pg_temp.lat(y))) + 1 / cos(radians(pg_temp.lat(y)))) / pi()) / 2 * (1 << p_z))::integer) $$;
create function pg_temp.meses6(p_ult text, p_m3 integer[]) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('periodo', to_char(to_date(p_ult, 'YYYYMM') - make_interval(months => 6 - k), 'YYYYMM'), 'sin_dato', p_m3[k] is null, 'm3', p_m3[k],
                                      'metodo', case when p_m3[k] is null then null else 'lectura' end, 'lectura_real', p_m3[k] is not null, 'causal', '99 LECTURA NORMAL') order by k)
    from generate_series(1, 6) k $$;
create function pg_temp.prop(p jsonb, p_codigo text) returns jsonb language sql as $$
  select f -> 'properties' from jsonb_array_elements(p -> 'features') f where f -> 'properties' ->> 'codigo' = p_codigo $$;

do $prueba$
declare
  a text := 'prueba.redes11.adm@emdupar.gov.co'; sd text := 'prueba.redes11.dist@emdupar.gov.co'; sv text := 'prueba.redes11.planta@emdupar.gov.co';
  op text := 'prueba.redes11.op@emdupar.gov.co'; na text := 'prueba.redes11.nada@emdupar.gov.co';
  C1 text := '990000001101'; C2 text := '990000001102'; C3 text := '990000001103'; C4 text := '990000001104';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_r jsonb; v_x jsonb; v_t text; v_n integer; v_id text; v_aud0 integer; v_p1 bigint; v_p2 bigint; v_p3 bigint; v_p4 bigint; v_ref jsonb;
  v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT11 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT11 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT11 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT11 Operador', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT11 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT11 necesita ver la red en la calle');

  -- ===================== 01. Esquema =====================
  perform pg_temp.reg('01.01 la capa de contratos no tiene columnas de nombre, dirección, teléfono, barrio ni deuda',
     not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'contratos_capa' and column_name ~ '(nombre|direccion|telefono|deuda|barrio|saldo)'));
  perform pg_temp.reg('01.02 el catálogo: contratos con capa propia (solo supervisores), reportes de Comercial por fecha, 6 preparadas',
     (select fuente || '|' || estado || '|' || solo_completo from redes.geovisor_capas where codigo = 'contratos') = 'contratos|activa|true'
     and (select fuente || '|' || por_fecha || '|' || solo_completo from redes.geovisor_capas where codigo = 'reportes_comercial') = 'geojson|true|true'
     and (select count(*) from redes.geovisor_capas where fuente = 'preparada') = 6);
  perform pg_temp.reg('01.03 los rangos del muestreo: cloro con el de Salida del tanque y turbiedad con la de salida', (select string_agg(variable_muestreo || '>' || variable_salida, ',' order by orden) from redes.muestreo_rangos)
     = 'cloro_residual_libre>cloro_libre_tanque,turbiedad>turbiedad_salida');
  perform pg_temp.reg('01.04 los 3 parámetros nuevos', (select count(*) from redes.parametros where clave in ('geovisor_zoom_contratos', 'geovisor_contratos_horas', 'geovisor_muestreo_dias')) = 3);
  perform pg_temp.reg('01.06 la capa de reportes de Comercial existe y está vacía hasta el Corte 8', (select count(*) from redes.v_reportes_comercial) = 0);

  -- ===================== 02. Capa de contratos =====================
  insert into public.cartera_suscripcion (contrato, estado, identificacion, nombre, correo, telefono, direccion, barrio, categoria, subcategoria, ciclo,
                                          facturas_pendientes, deuda_total, saldo_pendiente, saldo_a_favor, valor_reclamo, saldo_financiado, serial_medidor, ruta, periodo_carga)
  values (C1, 'RETIRADO', 'DOC-PRUEBA-1', 'NOMBRE VIEJO DE PRUEBA', null, '3001112233', 'DIR VIEJA', 'ZT11 BARRIO VIEJO', '1 Residencial', '2 Estrato 2', '7', 9, 412300, 98000, 0, 0, 0, 'ZTM1', '0701', '20200101'),
         (C1, 'ACTIVO', 'DOC-PRUEBA-1', 'NOMBRE DE PRUEBA ONCE', null, '3001112233', 'CRA ZT11 1 2 3', 'ZT11 BARRIO CARTERA', '1 Residencial', '2 Estrato 2', '7', 9, 412300, 98000, 0, 0, 0, 'ZTM1', '0701', '29991231'),
         (C2, 'RETIRADO', 'DOC-PRUEBA-2', 'NOMBRE DE PRUEBA DOCE', null, null, 'CRA ZT11 9 9', 'ZT11 BARRIO CARTERA', '2 Comercial', '201 1/2', '7', 0, 0, 0, 0, 0, 0, null, '0702', '29991231');
  insert into public.catastro_valledupar (cod_usuario, direccion, barrio, geom)
  values (C1, 'CRA ZT11 1 2 3 CATASTRO', 'ZT11 BARRIO CATASTRO', pg_temp.pt(0, 0)), (C1, 'OTRO PREDIO', 'ZT11 BARRIO CATASTRO', pg_temp.pt(400, 400)),
         (C2, 'CRA ZT11 9 9', 'ZT11 BARRIO CATASTRO', pg_temp.pt(30, 0)), (C3, 'CRA ZT11 SOLO CATASTRO', 'ZT11 OTRO', pg_temp.pt(60, 0)), ('99999999', 'COMODIN', 'X', pg_temp.pt(90, 0));
  insert into bi_interno.ficha_contrato (contrato, periodo_ultimo, uso, consumo_meses, cons_prom, meses_con_lectura, medidor_fecha_estado, medidor_anios)
  values (C1, '202610', 'Residencial', pg_temp.meses6('202610', array[7, null, 9, 6, 5, 6]), 6.6, 5, 'real', 12);
  v_n := redes.f_refrescar_contratos_capa();
  perform pg_temp.reg('02.01 la capa se rehace con los contratos del catastro (al menos los 3 de prueba) y deja su estado',
     v_n >= 3 and (select filas from redes.contratos_capa_estado where id = 1) = v_n and (select count(*) from redes.contratos_capa where contrato in (C1, C2, C3)) = 3, v_n::text);
  perform pg_temp.reg('02.02 un punto por contrato: el del predio de menor id; con uso, estado del último corte de la cartera, consumo y años del medidor',
     (select ST_Equals(geom, pg_temp.pt(0, 0)) and uso = 'Residencial' and estado = 'activo' and consumo_prom = 6.6 and medidor_anios = 12 from redes.contratos_capa where contrato = C1));
  perform pg_temp.reg('02.03 retirado: sin ficha toma el uso de la cartera sin su número («Comercial»); sin cartera: estado «sin_dato»',
     (select estado || '|' || uso from redes.contratos_capa where contrato = C2) = 'retirado|Comercial' and (select estado from redes.contratos_capa where contrato = C3) = 'sin_dato');
  perform pg_temp.reg('02.04 el comodín 99999999 y el «0» no entran', not exists (select 1 from redes.contratos_capa where contrato in ('99999999', '0')));
  perform pg_temp.reg('02.05 «al día»: con la misma ficha y menos de un día, no la rehace', not redes.f_contratos_capa_al_dia());
  update bi_interno.ficha_contrato_estado set calculado_en = clock_timestamp() + interval '1 minute' where id = 1;
  if not found then insert into bi_interno.ficha_contrato_estado (id, firma, filas, calculado_en, duracion_ms) values (1, 'zt11', 1, clock_timestamp() + interval '1 minute', 1); end if;
  perform pg_temp.reg('02.06 si cambió la ficha del contrato (cálculo mensual), la rehace', redes.f_contratos_capa_al_dia());
  v_r := public.geoportal_redes_geovisor(sd);
  perform pg_temp.reg('02.07 la configuración del supervisor trae el zoom de contratos, «compartir» y el estado de la capa', (v_r -> 'zoom' ->> 'contratos')::numeric = 16
     and (v_r ->> 'compartir')::boolean and (v_r -> 'contratos_capa' ->> 'filas')::integer >= 3 and 'contratos' = any (select jsonb_array_elements(v_r -> 'capas') ->> 'codigo'));
  v_r := public.geoportal_redes_geovisor(op);
  perform pg_temp.reg('02.08 el operador en solo lectura: sin contratos, sin «compartir» y sin el estado de la capa', not (v_r ->> 'compartir')::boolean and v_r -> 'contratos_capa' = 'null'::jsonb
     and not ('contratos' = any (select jsonb_array_elements(v_r -> 'capas') ->> 'codigo')));
  -- tesela
  perform pg_temp.reg('02.09 la tesela de contratos: vacía a zoom 15; a zoom 17 trae el número, el estado y el uso', pg_temp.tesela(sd, 15, 0, 0) = ''
     and pg_temp.trae(pg_temp.tesela(sd, 17, 0, 0), C1) and pg_temp.trae(pg_temp.tesela(sd, 17, 0, 0), 'activo') and pg_temp.trae(pg_temp.tesela(sd, 17, 0, 0), 'Residencial'));
  v_t := pg_temp.tesela(a, 17, 0, 0);
  perform pg_temp.reg('02.10 la tesela no lleva nombre, dirección, barrio ni teléfono', not pg_temp.trae(v_t, 'NOMBRE DE PRUEBA') and not pg_temp.trae(v_t, 'CRA ZT11') and not pg_temp.trae(v_t, 'ZT11 BARRIO')
     and not pg_temp.trae(v_t, '3001112233'));
  perform pg_temp.err('02.11 el operador no pide la tesela de contratos', format($$select pg_temp.tesela(%L, 17, 0, 0)$$, op), '42501');
  perform pg_temp.err('02.12 quien no tiene el geovisor tampoco', format($$select pg_temp.tesela(%L, 17, 0, 0)$$, na), '42501');
  perform pg_temp.reg('02.13 el supervisor de planta sí (geovisor completo)', pg_temp.trae(pg_temp.tesela(sv, 17, 0, 0), C1));

  -- ===================== 03. Tarjeta del contrato (§30.1) =====================
  select count(*) into v_aud0 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta';
  v_r := public.geoportal_redes_contrato_tarjeta(sd, C1, '10.0.0.7');
  perform pg_temp.reg('03.01 la tarjeta trae número, estado (activo), uso, el perfil de consumo de 6 meses (con el hueco) y los años del medidor',
     v_r ->> 'contrato' = C1 and v_r ->> 'estado' = 'activo' and v_r ->> 'estado_texto' = 'ACTIVO' and v_r ->> 'uso' = 'Residencial'
     and jsonb_array_length(v_r -> 'consumo' -> 'meses') = 6 and (v_r -> 'consumo' -> 'meses' -> 1 ->> 'sin_dato')::boolean and (v_r -> 'consumo' ->> 'promedio')::numeric = 6.6
     and (v_r ->> 'medidor_anios')::integer = 12, left(v_r::text, 400));
  perform pg_temp.reg('03.02 nombre, dirección (la del catastro) y barrio (el de la cartera) del ÚLTIMO corte', v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA ONCE'
     and v_r -> 'suscriptor' ->> 'direccion' = 'CRA ZT11 1 2 3 CATASTRO' and v_r -> 'suscriptor' ->> 'barrio' = 'ZT11 BARRIO CARTERA', (v_r -> 'suscriptor')::text);
  perform pg_temp.reg('03.03 sin teléfono, deuda, documento ni saldos', v_r::text not like '%3001112233%' and v_r::text not like '%412300%' and v_r::text not like '%DOC-PRUEBA%'
     and not (v_r ? 'deuda_total') and not (v_r -> 'suscriptor' ? 'telefonos'));
  perform pg_temp.reg('03.04 la lectura queda en la auditoría (quién, contrato e IP) sin el nombre ni la dirección',
     (select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta') = v_aud0 + 1
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta' and email = sd and referencia = C1 and ip = '10.0.0.7'
                   and detalle::text not like '%NOMBRE DE PRUEBA%' and detalle::text not like '%CRA ZT11%'));
  v_r := public.geoportal_redes_contrato_tarjeta(a, C2);
  perform pg_temp.reg('03.05 un contrato retirado y sin ficha: «retirado», sin consumo, con nombre y dirección', v_r ->> 'estado' = 'retirado' and v_r -> 'consumo' = 'null'::jsonb
     and v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA DOCE');
  v_r := public.geoportal_redes_contrato_tarjeta(sv, C3);
  perform pg_temp.reg('03.06 sin cartera: sin nombre, con la dirección y el barrio del catastro', v_r -> 'suscriptor' ->> 'nombre' is null and v_r -> 'suscriptor' ->> 'barrio' = 'ZT11 OTRO');
  perform pg_temp.err('03.07 el operador en solo lectura no abre la tarjeta del contrato', format($$select public.geoportal_redes_contrato_tarjeta(%L, %L)$$, op, C1), '42501');
  perform pg_temp.err('03.08 quien no es de Técnica tampoco', format($$select public.geoportal_redes_contrato_tarjeta(%L, %L)$$, na, C1), '42501');
  perform pg_temp.reg('03.09 los intentos negados no dejan lectura', (select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta') = v_aud0 + 3);
  perform pg_temp.err('03.10 un contrato mal escrito', format($$select public.geoportal_redes_contrato_tarjeta(%L, '12A')$$, sd), '22023', 'números');
  perform pg_temp.err('03.11 un contrato fuera de la capa (el comodín)', format($$select public.geoportal_redes_contrato_tarjeta(%L, '99999999')$$, sd), 'P0002');

  -- ===================== 04. Compartir la vista (§30.2) =====================
  v_x := jsonb_build_object('capas', jsonb_build_array('acu_tramos', 'danos', 'contratos', 'muestreo'), 'colores', 'material',
                            'periodo', jsonb_build_object('modo', 'rango', 'desde', hoy - 30, 'hasta', hoy), 'lon', -73.25, 'lat', 10.46, 'zoom', 16.5, 'atenuadas', jsonb_build_array('reportes_comercial'));
  v_r := public.geoportal_redes_vista_compartir(sd, v_x);
  v_id := v_r ->> 'id';
  perform pg_temp.reg('04.01 el supervisor comparte la vista: un código de 10 letras y números, guardado con su autor y en la auditoría',
     v_id ~ '^[a-z0-9]{10}$' and (select autor || '|' || colores || '|' || array_to_string(capas, ',') from redes.vistas_compartidas where id = v_id) = sd || '|material|acu_tramos,contratos,danos,muestreo'
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_vista_compartir' and referencia = v_id), v_r::text);
  perform pg_temp.reg('04.02 la vista no guarda datos personales (solo capas, colores, fechas, centro y zoom)',
     (select to_jsonb(v) - 'id' - 'autor' - 'creado_en' from redes.vistas_compartidas v where id = v_id)::text !~* '(nombre|direcci|telefono|suscriptor)');
  perform pg_temp.err('04.02b una vista compartida no se cambia ni se borra', format($$update redes.vistas_compartidas set zoom = 12 where id = %L$$, v_id), '42501');
  v_r := public.geoportal_redes_vista_abrir(a, v_id);
  perform pg_temp.reg('04.03 el administrador la abre igual: capas, colores, el rango de fechas, centro y zoom; nada omitido',
     v_r -> 'capas' = '["acu_tramos", "contratos", "danos", "muestreo"]'::jsonb and v_r ->> 'colores' = 'material' and (v_r -> 'periodo' ->> 'desde')::date = hoy - 30
     and (v_r ->> 'zoom')::numeric = 16.5 and jsonb_array_length(v_r -> 'omitidas') = 0 and exists (select 1 from public.geoportal_auditoria where accion = 'redes_vista_abrir' and email = a and referencia = v_id), v_r::text);
  v_r := public.geoportal_redes_vista_abrir(op, v_id);
  perform pg_temp.reg('04.04 el operador con la casilla la abre sin las capas que no ve (contratos y muestreo, nombradas) y con las actividades de hoy',
     v_r -> 'capas' = '["acu_tramos", "danos"]'::jsonb and v_r -> 'omitidas' @> '["Contratos (consumo y edad del medidor)", "Puntos de muestreo"]'::jsonb
     and (v_r -> 'periodo' ->> 'modo') = 'hoy' and (v_r -> 'periodo' ->> 'desde')::date = hoy and (v_r ->> 'fechas_cambiadas')::boolean, v_r::text);
  perform pg_temp.err('04.05 quien no tiene el geovisor no abre el enlace', format($$select public.geoportal_redes_vista_abrir(%L, %L)$$, na, v_id), '42501');
  perform pg_temp.err('04.06 un enlace que no existe', format($$select public.geoportal_redes_vista_abrir(%L, 'zzzzzzzzzz')$$, sd), 'P0002');
  perform pg_temp.err('04.07 un enlace mal formado', format($$select public.geoportal_redes_vista_abrir(%L, 'ABC')$$, sd), '22023');
  perform pg_temp.err('04.08 el operador en solo lectura no comparte', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, op, v_x), '42501');
  perform pg_temp.err('04.09 una capa que no existe', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, sd, v_x || '{"capas": ["acu_tramos", "inventada"]}'), '22023', 'inventada');
  perform pg_temp.err('04.10 una capa preparada no se comparte', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, sd, v_x || '{"capas": ["presion"]}'), '22023', 'presion');
  perform pg_temp.err('04.11 un rango de más de 12 meses', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, sd,
     v_x || jsonb_build_object('periodo', jsonb_build_object('modo', 'rango', 'desde', hoy - 400, 'hasta', hoy))), '22023', 'rango');
  perform pg_temp.err('04.12 un centro fuera de Valledupar', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, sd, v_x || '{"lon": -74.08, "lat": 4.6}'), '22023', 'fuera de Valledupar');
  perform pg_temp.err('04.13 unos colores que no existen', format($$select public.geoportal_redes_vista_compartir(%L, %L)$$, sd, v_x || '{"colores": "arcoiris"}'), '22023', 'colores');
  v_r := public.geoportal_redes_vista_compartir(sv, v_x || '{"periodo": {"modo": "semana"}}');
  perform pg_temp.reg('04.14 «7 días» guarda el modo y, al abrirla otro día, son los 7 días de ese día', (public.geoportal_redes_vista_abrir(sd, v_r ->> 'id') -> 'periodo' ->> 'desde')::date = hoy - 6);

  -- ===================== 05. Color del muestreo (rangos de Salida, respuesta 4 de David al 6a) =====================
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9501', 'ZT11 Uno', 'muestreo', 'norte'), ('MUE-9502', 'ZT11 Dos', 'muestreo', 'sur'),
    ('MUE-9503', 'ZT11 Tres', 'muestreo', 'medio'), ('MUE-9504', 'ZT11 Cuatro', 'muestreo', 'medio');
  select id into v_p1 from tecnica.puntos where codigo = 'MUE-9501'; select id into v_p2 from tecnica.puntos where codigo = 'MUE-9502';
  select id into v_p3 from tecnica.puntos where codigo = 'MUE-9503'; select id into v_p4 from tecnica.puntos where codigo = 'MUE-9504';
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, autor)
  select id, pg_temp.lat(500 + id % 50), pg_temp.lon(500), 'verificada', 'david', a from tecnica.puntos where codigo like 'MUE-95__';
  -- el rango de Salida del cloro, como lo resuelve planta (general o, si no hay, el más estricto por planta)
  select coalesce((select jsonb_build_object('min', x.ref_min, 'max', x.ref_max) from tecnica.f_referencia_vigente((select id from tecnica.variables where codigo = 'cloro_libre_tanque'), null, null) x),
                  (select jsonb_build_object('min', max(r.ref_min), 'max', min(r.ref_max)) from tecnica.referencias r where r.activa and r.punto_id is null
                      and r.variable_id = (select id from tecnica.variables where codigo = 'cloro_libre_tanque'))) into v_ref;
  insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'muestreo', v.id, x.p, x.valor, hoy - x.dias, x.hora::time, op
    from (values (v_p1, 'cloro_residual_libre', 1000.0, 0, '06:00'), (v_p1, 'cloro_residual_libre', 1.0, 1, '06:00'),   -- el último (hoy) es absurdo: se sale de cualquier rango
                 (v_p2, 'ph', 7.0, 0, '06:00'),                                                                         -- el pH no colorea
                 (v_p3, 'cloro_residual_libre', 1000.0, 1, '00:00'),                                                    -- de ayer a la medianoche (para la prueba de «reciente»)
                 (v_p4, 'cloro_residual_libre', 1000.0, 0, '06:00')) x(p, cod, valor, dias, hora)
    join tecnica.variables v on v.codigo = x.cod;
  v_r := public.geoportal_redes_geovisor_capa(sv, 'muestreo');
  perform pg_temp.reg('05.01 un punto con el último cloro fuera del rango de Salida sale «fuera», con su valor, la fecha y el rango (de Salida)',
     (v_ref ->> 'min' is null and v_ref ->> 'max' is null and pg_temp.prop(v_r, 'MUE-9501') ->> 'calidad' = 'sin_rango')
     or (pg_temp.prop(v_r, 'MUE-9501') ->> 'calidad' = 'fuera' and (pg_temp.prop(v_r, 'MUE-9501') -> 'medidas' -> 0 ->> 'valor')::numeric = 1000
         and pg_temp.prop(v_r, 'MUE-9501') -> 'medidas' -> 0 ->> 'rango' = 'salida'), (pg_temp.prop(v_r, 'MUE-9501'))::text || ' · ref ' || coalesce(v_ref::text, 'ninguna'));
  perform pg_temp.reg('05.02 sin cloro ni turbiedad (solo pH): «sin_muestra»', pg_temp.prop(v_r, 'MUE-9502') ->> 'calidad' = 'sin_muestra');
  update redes.parametros set valor = 1 where clave = 'geovisor_muestreo_dias';      -- con 1 día, la de ayer a la medianoche ya no es reciente
  v_x := pg_temp.prop(public.geoportal_redes_geovisor_capa(sv, 'muestreo'), 'MUE-9503');
  update redes.parametros set valor = 30 where clave = 'geovisor_muestreo_dias';
  perform pg_temp.reg('05.03 una muestra más vieja que «geovisor_muestreo_dias» no colorea («sin_muestra», marcada como no reciente); con 30 días sí cuenta',
     v_x ->> 'calidad' = 'sin_muestra' and not (v_x -> 'medidas' -> 0 ->> 'reciente')::boolean and pg_temp.prop(v_r, 'MUE-9503') ->> 'calidad' <> 'sin_muestra', v_x::text);
  insert into tecnica.exclusiones (registro_id, accion, motivo, autor)
  select r.id, 'EXCLUIR', 'ZT11 valor de prueba mal digitado', a from tecnica.registros r where r.punto_id = v_p1 and r.valor = 1000;
  v_r := public.geoportal_redes_geovisor_capa(sv, 'muestreo');
  perform pg_temp.reg('05.04 si se excluye ese registro, cuenta la muestra anterior (1,0 mg/L) y queda dentro del rango',
     (pg_temp.prop(v_r, 'MUE-9501') -> 'medidas' -> 0 ->> 'valor')::numeric = 1.0
     and (pg_temp.prop(v_r, 'MUE-9501') ->> 'calidad' = case when coalesce((v_ref ->> 'min')::numeric, 0) <= 1 and coalesce((v_ref ->> 'max')::numeric, 99) >= 1 and v_ref is not null
                                                              and (v_ref ->> 'min' is not null or v_ref ->> 'max' is not null) then 'dentro' else pg_temp.prop(v_r, 'MUE-9501') ->> 'calidad' end),
     (pg_temp.prop(v_r, 'MUE-9501'))::text);
  -- una referencia propia de Muestreo para un punto gana sobre la de Salida
  insert into tecnica.referencias (variable_id, punto_id, ref_min, ref_max, origen, fuente)
  select id, v_p4, 0, 2000, 'criterio_planta', 'ZT11 referencia de prueba del punto' from tecnica.variables where codigo = 'cloro_residual_libre';
  v_r := public.geoportal_redes_geovisor_capa(sv, 'muestreo');
  perform pg_temp.reg('05.05 la referencia propia del punto (Muestreo) gana sobre la de Salida: 1000 queda «dentro» con rango «muestreo»',
     pg_temp.prop(v_r, 'MUE-9504') ->> 'calidad' = 'dentro' and pg_temp.prop(v_r, 'MUE-9504') -> 'medidas' -> 0 ->> 'rango' = 'muestreo', (pg_temp.prop(v_r, 'MUE-9504'))::text);
  perform pg_temp.reg('05.06 la capa sigue sin datos personales (sin el autor de la muestra)', v_r::text not like '%' || op || '%');

  -- ===================== 06. Reportes de Comercial (§30.4), vacía hasta el Corte 8 =====================
  v_r := public.geoportal_redes_geovisor_capa(sd, 'reportes_comercial', hoy - 7, hoy);
  perform pg_temp.reg('06.01 la capa de reportes de Comercial responde vacía (la llena el Corte 8)', v_r ->> 'type' = 'FeatureCollection' and jsonb_array_length(v_r -> 'features') = 0);
  perform pg_temp.err('06.02 el operador no la ve', format($$select public.geoportal_redes_geovisor_capa(%L, 'reportes_comercial')$$, op), '42501');
  perform pg_temp.reg('06.03 las demás capas por fecha siguen igual (daños de hoy)', public.geoportal_redes_geovisor_capa(sd, 'danos') ->> 'type' = 'FeatureCollection');

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 6b (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
