begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · REPORTES DEL PTAP (pestaña «Reportes» del Dashboard PTAP) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Encargo de David del 19-nov: cada formulario o ítem del PTAP tiene su propia descarga (Excel y CSV, el archivo lo arma el navegador).
-- · Solo AGREGA: 2 tablas (las descargas y sus cierres, solo inserción), funciones internas de lectura y 4 RPC. No reemplaza nada.
-- · Lee lo publicado: registros con su estado de exclusión (v_registros_estado), la referencia vigente (f_referencia_vigente) y la marca de rango
--   (f_marca_rango) de planta (Torre B), las revisiones, químicos (7a y 7c), la dosis de Entrada y los eventos de
--   suspensión de planta del Corte 15 (redes). Por eso exige la huella de redes publicada: b474fbbe3e0f7a3a7e6dbc04c53e02e7 (aviso por contrato) o, si ya se aplicaron las
--   descargas de Distribución, 3f3c89e603629d92e1cc5065de33d0c1. El esquema «tecnica» no tiene huella de conjunto publicada: se exige que exista lo que se lee
--   (tablas, columnas y funciones con su firma); el paso de huellas (05) imprime la huella de técnica para anotarla.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.reporte_descargas') is not null or to_regprocedure('public.geoportal_tec_reporte_iniciar(text,text,jsonb,text,boolean,text)') is not null then
    raise exception 'Los reportes del PTAP ya están aplicados: deténgase y avise';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
     not in ('b474fbbe3e0f7a3a7e6dbc04c53e02e7', '3f3c89e603629d92e1cc5065de33d0c1') then
    raise exception 'Las funciones de redes no son las publicadas (huella b474fbbe3e0f7a3a7e6dbc04c53e02e7): deténgase y avise';
  end if;
  if to_regclass('tecnica.v_registros_estado') is null or to_regclass('tecnica.revisiones_fuera_referencia') is null or to_regclass('tecnica.v_uso_quimicos_estado') is null
     or to_regclass('tecnica.quimico_movimientos') is null or to_regclass('tecnica.formulario_variables') is null or to_regclass('redes.v_evento_suspension') is null
     or to_regprocedure('tecnica.f_autorizar_supervision(text)') is null or to_regprocedure('tecnica.f_error(text,text)') is null
     or to_regprocedure('tecnica.f_auditar(text,text,text,jsonb,text)') is null or to_regprocedure('tecnica.f_formularios()') is null
     or to_regprocedure('tecnica.f_referencia_vigente(bigint,bigint,bigint)') is null or to_regprocedure('tecnica.f_marca_rango(numeric,numeric,numeric)') is null
     or to_regprocedure('tecnica.f_solo_agregar()') is null or to_regprocedure('redes.f_evento_reportes(bigint)') is null
     or to_regclass('redes.tipos_dano') is null or to_regclass('redes.causas') is null or to_regclass('redes.tipos_tercero') is null or to_regclass('redes.tipos_intervencion') is null then
    raise exception 'Faltan tablas o funciones de planta, de químicos, de los catálogos de daños o del Corte 15: deténgase y avise';
  end if;
  if (select count(*) from pg_attribute where not attisdropped and attnum > 0 and (
        (attrelid = 'tecnica.v_registros_estado'::regclass and attname in ('id', 'lote_id', 'formulario', 'variable_id', 'planta_id', 'punto_id', 'valor', 'fecha_muestra',
           'muestra_ts', 'registrado_en', 'autor', 'fuente', 'excluido'))
     or (attrelid = 'tecnica.quimico_movimientos'::regclass and attname in ('tipo', 'quimico_id', 'planta_id', 'para_que', 'cantidad', 'unidad', 'cantidad_kg', 'dia',
           'dosis_optima_ppm', 'proveedor', 'remision', 'lote_fabricante', 'vence', 'remision_foto', 'autor', 'registrado_en'))
     or (attrelid = 'tecnica.puntos'::regclass and attname in ('codigo', 'nombre', 'tipo', 'zona', 'numero_informe', 'planta_id'))
     or (attrelid = 'tecnica.variables'::regclass and attname in ('codigo', 'nombre', 'unidad', 'decimales', 'activa'))
     or (attrelid = 'redes.danos'::regclass and attname in ('id', 'codigo', 'tipo_codigo', 'causa_clase', 'causa_codigo', 'tercero_tipo'))
     or (attrelid = 'redes.intervenciones'::regclass and attname in ('id', 'codigo', 'dano_id', 'tipo_codigo')))) <> 13 + 16 + 6 + 5 + 6 + 4 then
    raise exception 'Las vistas o tablas de planta no tienen las columnas esperadas: deténgase y avise';
  end if;
end $$;

-- Una fila por descarga iniciada (quién, qué, con qué filtros y columnas, y el instante de la foto). Solo inserción.
create table tecnica.reporte_descargas (
  id         bigint generated always as identity primary key,
  email      text not null check (email = lower(email) and position('@' in email) > 1),
  reporte    text not null check (reporte ~ '^[a-z_]{3,30}$'),
  filtros    jsonb not null check (jsonb_typeof(filtros) = 'object'),
  incluir    boolean not null,
  formato    text not null check (formato in ('csv', 'xlsx')),
  columnas   jsonb not null check (jsonb_typeof(columnas) = 'array'),
  total      integer not null check (total >= 0),
  corte_en   timestamptz not null,
  ip         text,
  creado_en  timestamptz not null default clock_timestamp()
);
create index ix_tec_rep_descargas_email on tecnica.reporte_descargas (email, id desc);
-- El cierre de cada descarga (una sola vez). Solo inserción.
create table tecnica.reporte_descarga_cierres (
  descarga_id bigint primary key references tecnica.reporte_descargas (id),
  filas       integer not null check (filas >= 0),
  resultado   text not null check (resultado in ('completa', 'cancelada', 'error')),
  ip          text,
  creado_en   timestamptz not null default clock_timestamp()
);
create trigger t_solo_agregar before update or delete on tecnica.reporte_descargas for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.reporte_descargas for each statement execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar before update or delete on tecnica.reporte_descarga_cierres for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.reporte_descarga_cierres for each statement execute function tecnica.f_solo_agregar();
alter table tecnica.reporte_descargas enable row level security;
alter table tecnica.reporte_descarga_cierres enable row level security;
revoke all on tecnica.reporte_descargas, tecnica.reporte_descarga_cierres from public, anon, authenticated, service_role;
revoke all on sequence tecnica.reporte_descargas_id_seq from public, anon, authenticated, service_role;
-- =====================================================================
-- 20 — FUNCIONES INTERNAS de los reportes del PTAP (nadie de la API las ejecuta; las llaman las RPC del 26).
-- Cada reporte es una función que devuelve (k, fila): «k» es la llave de orden y de paginación (texto) y «fila» el objeto con las claves de sus columnas.
-- Sin textos libres: ni motivos, ni notas, ni la causa de un evento, ni el nombre de «Otro» químico. Los correos que salen son de funcionarios.
-- =====================================================================

-- Catálogo de reportes: clave, título, orden, filtros que admite y si «Incluir excluidos» aplica.
create function tecnica.f_rep_catalogo() returns table (clave text, titulo text, orden integer, filtros text[], usa_excluidos boolean, periodo_sobre text)
language sql immutable set search_path to 'pg_catalog' as $$
  values ('entrada',          'Entrada',             1, array['planta'],                        true,  'la fecha de la muestra'),
         ('salida',           'Salida',              2, array['planta', 'punto'],               true,  'la fecha de la muestra'),
         ('muestreo',         'Muestreo',            3, array['punto', 'zona'],                 true,  'la fecha de la muestra'),
         ('uso_quimicos',     'Uso de químicos',     4, array['planta', 'quimico'],             false, 'el día del uso'),
         ('entrada_quimicos', 'Entrada de químicos', 5, array['quimico'],                       false, 'el día de la entrada'),
         ('kardex_quimicos',  'Kardex de químicos',  6, array['quimico'],                       false, 'el día del movimiento'),
         ('eventos_planta',   'Eventos de planta',   7, array['planta'],                        true,  'el evento: sale si estuvo vigente algún momento del periodo'),
         ('fuera_referencia', 'Fuera de referencia', 8, array['planta', 'formulario', 'punto'], true,  'la fecha de la muestra') $$;

-- Máximo de filas por descarga y por página.
create function tecnica.f_rep_max_filas() returns integer language sql immutable set search_path to 'pg_catalog' as $$ select 50000 $$;
create function tecnica.f_rep_max_pagina() returns integer language sql immutable set search_path to 'pg_catalog' as $$ select 5000 $$;

-- Fecha y hora de Bogotá para el archivo (sin zona): «AAAA-MM-DDTHH:MM:SS».
create function tecnica.f_rep_ts(p timestamptz) returns text language sql stable set search_path to 'pg_catalog' as $$
  select to_char(p at time zone 'America/Bogota', 'YYYY-MM-DD"T"HH24:MI:SS') $$;

-- Una columna del archivo.
create function tecnica.f_rep_col(p_clave text, p_titulo text, p_tipo text, p_unidad text default null, p_decimales integer default null) returns jsonb
language sql immutable set search_path to 'pg_catalog' as $$
  select jsonb_build_object('clave', p_clave, 'titulo', p_titulo, 'unidad', p_unidad, 'tipo', p_tipo)
         || case when p_decimales is not null then jsonb_build_object('decimales', p_decimales) else '{}'::jsonb end $$;

-- Filtros normalizados y validados. Devuelve {desde, hasta, …} con los códigos limpios y los nombres para el Léame.
create function tecnica.f_rep_filtros(p_reporte text, p_filtros jsonb) returns jsonb
language plpgsql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_f jsonb := coalesce(p_filtros, '{}'::jsonb); v_permitidos text[]; v_desde date; v_hasta date; v_k text; v_r jsonb; v_t text; v_n text;
begin
  select c.filtros into v_permitidos from tecnica.f_rep_catalogo() c where c.clave = p_reporte;
  if not found then perform tecnica.f_error('Ese reporte no existe.'); end if;
  if jsonb_typeof(v_f) <> 'object' then perform tecnica.f_error('Los filtros no son válidos.'); end if;
  for v_k in select jsonb_object_keys(v_f) loop
    if v_k not in ('desde', 'hasta') and not v_k = any (v_permitidos) then perform tecnica.f_error('Ese filtro no aplica a este reporte.'); end if;
    if jsonb_typeof(v_f -> v_k) <> 'string' then perform tecnica.f_error('Un filtro no es válido.'); end if;
  end loop;
  begin
    v_desde := (v_f ->> 'desde')::date; v_hasta := (v_f ->> 'hasta')::date;
  exception when others then perform tecnica.f_error('Elija el periodo (desde y hasta, como AAAA-MM-DD).');
  end;
  if v_desde is null or v_hasta is null then perform tecnica.f_error('Elija el periodo (desde y hasta).'); end if;
  if v_hasta < v_desde then perform tecnica.f_error('La fecha inicial no puede ser posterior a la final.'); end if;
  if v_hasta - v_desde > 365 then perform tecnica.f_error('El periodo va hasta de un año: acórtelo.'); end if;
  v_r := jsonb_build_object('desde', v_desde, 'hasta', v_hasta);
  v_t := nullif(lower(btrim(v_f ->> 'planta')), '');
  if v_t is not null then
    select p.nombre into v_n from tecnica.plantas p where p.codigo = v_t;
    if not found then perform tecnica.f_error('Esa planta no existe.'); end if;
    v_r := v_r || jsonb_build_object('planta', v_t, 'planta_nombre', v_n);
  end if;
  v_t := nullif(upper(btrim(v_f ->> 'punto')), '');
  if v_t is not null then
    select p.nombre into v_n from tecnica.puntos p where p.codigo = v_t;
    if not found then perform tecnica.f_error('Ese punto no existe.'); end if;
    v_r := v_r || jsonb_build_object('punto', v_t, 'punto_nombre', v_n);
  end if;
  v_t := nullif(lower(btrim(v_f ->> 'zona')), '');
  if v_t is not null then
    if v_t not in ('norte', 'sur', 'medio') then perform tecnica.f_error('Esa zona no existe.'); end if;
    v_r := v_r || jsonb_build_object('zona', v_t);
  end if;
  v_t := nullif(lower(btrim(v_f ->> 'quimico')), '');
  if v_t is not null then
    select q.nombre into v_n from tecnica.quimicos q where q.codigo = v_t and q.codigo <> 'otro';
    if not found then perform tecnica.f_error('Ese químico no existe.'); end if;
    v_r := v_r || jsonb_build_object('quimico', v_t, 'quimico_nombre', v_n);
  end if;
  v_t := nullif(lower(btrim(v_f ->> 'formulario')), '');
  if v_t is not null then
    if v_t not in ('entrada', 'salida', 'muestreo') then perform tecnica.f_error('Ese formulario no tiene valores con referencia.'); end if;
    v_r := v_r || jsonb_build_object('formulario', v_t);
  end if;
  return v_r;
end $$;

-- Columnas de las variables de un formulario: las activas y las que tienen datos en el periodo (en el orden del catálogo).
create function tecnica.f_rep_cols_variables(p_formulario text, p_desde date, p_hasta date) returns jsonb
language sql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
  select coalesce(jsonb_agg(tecnica.f_rep_col('v_' || v.codigo, v.nombre, 'decimal', v.unidad, v.decimales::integer) order by fv.orden, v.codigo), '[]'::jsonb)
    from tecnica.formulario_variables fv join tecnica.variables v on v.id = fv.variable_id
   where fv.formulario = p_formulario
     and ((fv.activa and v.activa)
          or exists (select 1 from tecnica.registros r where r.formulario = fv.formulario and r.variable_id = fv.variable_id and r.fecha_muestra between p_desde and p_hasta)) $$;

-- Las columnas de cada reporte (el orden del archivo).
create function tecnica.f_rep_columnas(p_reporte text, p_f jsonb) returns jsonb
language plpgsql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare c jsonb; v_desde date := (p_f ->> 'desde')::date; v_hasta date := (p_f ->> 'hasta')::date;
  fin_envio jsonb := jsonb_build_array(
    tecnica.f_rep_col('fuera_referencia', 'Valores fuera de referencia', 'entero'),
    tecnica.f_rep_col('estado', 'Estado', 'texto'),
    tecnica.f_rep_col('fuente', 'Fuente', 'texto'),
    tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'),
    tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'),
    tecnica.f_rep_col('envio', 'Envío (identificador)', 'texto'));
begin
  case p_reporte
  when 'entrada' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('planta', 'Planta', 'texto'))
         || tecnica.f_rep_cols_variables('entrada', v_desde, v_hasta)
         || jsonb_build_array(tecnica.f_rep_col('coagulante', 'Coagulante', 'texto'), tecnica.f_rep_col('dosis_ppm', 'Dosis de coagulante', 'decimal', 'ppm', 2))
         || fin_envio;
  when 'salida' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('planta', 'Planta', 'texto'),
                           tecnica.f_rep_col('punto', 'Punto', 'texto'), tecnica.f_rep_col('punto_nombre', 'Nombre del punto', 'texto'))
         || tecnica.f_rep_cols_variables('salida', v_desde, v_hasta) || fin_envio;
  when 'muestreo' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('punto', 'Punto', 'texto'),
                           tecnica.f_rep_col('punto_nombre', 'Nombre del punto', 'texto'), tecnica.f_rep_col('tipo_punto', 'Tipo de punto', 'texto'),
                           tecnica.f_rep_col('zona', 'Zona', 'texto'), tecnica.f_rep_col('numero_informe', 'Número en el informe', 'entero'))
         || tecnica.f_rep_cols_variables('muestreo', v_desde, v_hasta) || fin_envio;
  when 'uso_quimicos' then
    c := jsonb_build_array(tecnica.f_rep_col('movimiento', 'Movimiento', 'entero'), tecnica.f_rep_col('dia', 'Día', 'fecha'), tecnica.f_rep_col('quimico', 'Químico', 'texto'),
                           tecnica.f_rep_col('planta', 'Planta', 'texto'), tecnica.f_rep_col('para_que', 'Para qué', 'texto'),
                           tecnica.f_rep_col('cantidad', 'Cantidad digitada', 'decimal', null, 3), tecnica.f_rep_col('unidad', 'Unidad digitada', 'texto'),
                           tecnica.f_rep_col('cantidad_kg', 'Cantidad', 'decimal', 'kg', 3), tecnica.f_rep_col('dosis_optima_ppm', 'Dosis óptima vigente', 'decimal', 'ppm', 2),
                           tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'), tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'));
  when 'entrada_quimicos' then
    c := jsonb_build_array(tecnica.f_rep_col('movimiento', 'Movimiento', 'entero'), tecnica.f_rep_col('dia', 'Día', 'fecha'), tecnica.f_rep_col('quimico', 'Químico', 'texto'),
                           tecnica.f_rep_col('cantidad', 'Cantidad digitada', 'decimal', null, 3), tecnica.f_rep_col('unidad', 'Unidad digitada', 'texto'),
                           tecnica.f_rep_col('cantidad_kg', 'Cantidad', 'decimal', 'kg', 3), tecnica.f_rep_col('proveedor', 'Proveedor', 'texto'),
                           tecnica.f_rep_col('remision', 'Remisión', 'texto'), tecnica.f_rep_col('lote_fabricante', 'Lote del fabricante', 'texto'),
                           tecnica.f_rep_col('vence', 'Vence', 'fecha'), tecnica.f_rep_col('foto_remision', 'Foto de la remisión', 'enlace'),
                           tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'), tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'));
  when 'kardex_quimicos' then
    c := jsonb_build_array(tecnica.f_rep_col('quimico', 'Químico', 'texto'), tecnica.f_rep_col('bodega', 'Bodega', 'texto'), tecnica.f_rep_col('dia', 'Día', 'fecha'),
                           tecnica.f_rep_col('movimiento', 'Movimiento', 'entero'), tecnica.f_rep_col('tipo', 'Tipo', 'texto'), tecnica.f_rep_col('planta', 'Planta', 'texto'),
                           tecnica.f_rep_col('detalle', 'Detalle', 'texto'), tecnica.f_rep_col('entra_kg', 'Entra', 'decimal', 'kg', 3),
                           tecnica.f_rep_col('sale_kg', 'Sale', 'decimal', 'kg', 3), tecnica.f_rep_col('conteo_kg', 'Conteo físico', 'decimal', 'kg', 3),
                           tecnica.f_rep_col('saldo_kg', 'Saldo', 'decimal', 'kg', 3), tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'));
  when 'eventos_planta' then
    c := jsonb_build_array(tecnica.f_rep_col('evento', 'Evento', 'texto'), tecnica.f_rep_col('planta', 'Planta', 'texto'), tecnica.f_rep_col('estado', 'Estado', 'texto'),
                           tecnica.f_rep_col('suspendido', 'Suspendido desde', 'fecha_hora'), tecnica.f_rep_col('regreso_estimado_inicial', 'Regreso estimado al declarar', 'fecha_hora'),
                           tecnica.f_rep_col('regreso_estimado', 'Regreso estimado vigente', 'fecha_hora'), tecnica.f_rep_col('cambios_regreso', 'Cambios del regreso estimado', 'entero'),
                           tecnica.f_rep_col('reanudado', 'Reanudado', 'fecha_hora'), tecnica.f_rep_col('duracion_h', 'Duración', 'decimal', 'h', 1),
                           tecnica.f_rep_col('contratos', 'Contratos afectados', 'entero'), tecnica.f_rep_col('sensibles', 'Usuarios sensibles afectados', 'entero'),
                           tecnica.f_rep_col('reportes', 'Reportes asociados', 'entero'), tecnica.f_rep_col('dano', 'Daño', 'texto'),
                           tecnica.f_rep_col('tipo', 'Tipo de daño o falla', 'texto'), tecnica.f_rep_col('causa', 'Causa del daño', 'texto'),
                           tecnica.f_rep_col('intervencion', 'Intervención', 'texto'), tecnica.f_rep_col('tipo_intervencion', 'Tipo de intervención', 'texto'),
                           tecnica.f_rep_col('declaro', 'Declaró (correo)', 'texto'),
                           tecnica.f_rep_col('cerro', 'Cerró o anuló (correo)', 'texto'));
  when 'fuera_referencia' then
    c := jsonb_build_array(tecnica.f_rep_col('muestra', 'Fecha y hora de la muestra', 'fecha_hora'), tecnica.f_rep_col('formulario', 'Formulario', 'texto'),
                           tecnica.f_rep_col('planta', 'Planta', 'texto'), tecnica.f_rep_col('punto', 'Punto', 'texto'), tecnica.f_rep_col('variable', 'Variable', 'texto'),
                           tecnica.f_rep_col('valor', 'Valor', 'decimal', null, 6), tecnica.f_rep_col('unidad', 'Unidad', 'texto'), tecnica.f_rep_col('marca', 'Marca', 'texto'),
                           tecnica.f_rep_col('ref_min', 'Referencia mínima', 'decimal', null, 6), tecnica.f_rep_col('ref_max', 'Referencia máxima', 'decimal', null, 6),
                           tecnica.f_rep_col('ref_origen', 'Origen de la referencia', 'texto'), tecnica.f_rep_col('revision', 'Revisión', 'texto'),
                           tecnica.f_rep_col('revisado_por', 'Revisó (correo)', 'texto'), tecnica.f_rep_col('revisado_en', 'Revisado', 'fecha_hora'),
                           tecnica.f_rep_col('excluido', 'Excluido', 'si_no'), tecnica.f_rep_col('registrado', 'Registrado', 'fecha_hora'),
                           tecnica.f_rep_col('registro', 'Registró (correo)', 'texto'), tecnica.f_rep_col('registro_id', 'Registro', 'entero'));
  else perform tecnica.f_error('Ese reporte no existe.');
  end case;
  return c;
end $$;

-- Los valores de planta de un periodo con su estado de exclusión (tecnica.v_registros_estado) y su marca de rango. La referencia vigente se pide UNA vez por
-- combinación variable–planta–punto (tecnica.f_referencia_vigente, la publicada) y la marca la da tecnica.f_marca_rango, como en tecnica.v_registros_detalle,
-- que haría la consulta de la referencia por cada valor (seis veces más lento con un año de datos).
create function tecnica.f_rep_valores(p_formularios text[], p_f jsonb, p_corte timestamptz, p_fecha_min date, p_id_min bigint, p_fecha_max date default null, p_solo_fuera boolean default false)
returns table (registro_id bigint, lote_id uuid, formulario text, variable_id bigint, planta_id bigint, punto_id bigint, valor numeric, fecha_muestra date, muestra_ts timestamptz,
               registrado_en timestamptz, autor text, fuente text, excluido boolean, ref_min numeric, ref_max numeric, ref_origen text, marca text)
language sql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
  with d as (
    select s.id, s.lote_id, s.formulario::text as formulario, s.variable_id, s.planta_id, s.punto_id, s.valor, s.fecha_muestra, s.muestra_ts, s.registrado_en, s.autor, s.fuente, s.excluido
      from tecnica.v_registros_estado s
     where s.formulario::text = any (p_formularios)
       and s.fecha_muestra between (p_f ->> 'desde')::date and (p_f ->> 'hasta')::date and s.fecha_muestra >= coalesce(p_fecha_min, '-infinity'::date) and s.fecha_muestra <= coalesce(p_fecha_max, 'infinity'::date)
       and s.id > coalesce(p_id_min, 0) and s.registrado_en <= p_corte
       and (p_f ->> 'planta' is null or s.planta_id = (select pl.id from tecnica.plantas pl where pl.codigo = p_f ->> 'planta'))
       and (p_f ->> 'punto' is null or s.punto_id = (select pu.id from tecnica.puntos pu where pu.codigo = p_f ->> 'punto'))
       and (p_f ->> 'zona' is null or s.punto_id in (select pu.id from tecnica.puntos pu where pu.zona = p_f ->> 'zona'))),
  dl as (select d.*, coalesce(d.planta_id, pu.planta_id) as pl from d left join tecnica.puntos pu on pu.id = d.punto_id),
  rf as (select c.variable_id, c.pl, c.punto_id, f.ref_min, f.ref_max, f.origen
           from (select distinct dl.variable_id, dl.pl, dl.punto_id from dl) c left join lateral tecnica.f_referencia_vigente(c.variable_id, c.pl, c.punto_id) f on true)
  select dl.id, dl.lote_id, dl.formulario, dl.variable_id, dl.planta_id, dl.punto_id, dl.valor, dl.fecha_muestra, dl.muestra_ts, dl.registrado_en, dl.autor, dl.fuente, dl.excluido,
         rf.ref_min, rf.ref_max, rf.origen, case when rf.ref_min is null and rf.ref_max is null then null else tecnica.f_marca_rango(dl.valor, rf.ref_min, rf.ref_max) end
    from dl left join rf on rf.variable_id = dl.variable_id and coalesce(rf.pl, -1) = coalesce(dl.pl, -1) and coalesce(rf.punto_id, -1) = coalesce(dl.punto_id, -1)
   -- «solo fuera»: lo que f_marca_rango marcaría (estrictamente por debajo del mínimo o por encima del máximo); la marca misma la sigue dando f_marca_rango
   where not p_solo_fuera or dl.valor < rf.ref_min or dl.valor > rf.ref_max $$;

-- 1–3. Las llaves de los envíos (envío y lugar) en orden, sin referencias: para contar y para saber hasta qué día llega una página.
create function tecnica.f_rep_envios_llaves(p_formulario text, p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer)
returns table (k text, fecha date)
language sql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
  select g.k, g.fecha
    from (select to_char(min(s.muestra_ts) at time zone 'America/Bogota', 'YYYYMMDDHH24MISS') || '|' || s.lote_id::text || '|' || coalesce(pl.codigo, '') || '|' || coalesce(pu.codigo, '') as k,
                 min(s.fecha_muestra) as fecha, bool_and(s.excluido) as todo_excluido
            from tecnica.v_registros_estado s left join tecnica.plantas pl on pl.id = s.planta_id left join tecnica.puntos pu on pu.id = s.punto_id
           where s.formulario::text = p_formulario
             and s.fecha_muestra between (p_f ->> 'desde')::date and (p_f ->> 'hasta')::date
             and (p_cursor is null or s.fecha_muestra >= to_date(left(p_cursor, 8), 'YYYYMMDD')) and s.registrado_en <= p_corte
             and (p_f ->> 'planta' is null or pl.codigo = p_f ->> 'planta') and (p_f ->> 'punto' is null or pu.codigo = p_f ->> 'punto')
             and (p_f ->> 'zona' is null or pu.zona = p_f ->> 'zona')
           group by s.lote_id, pl.codigo, pu.codigo) g
   where (p_incl or not g.todo_excluido) and (p_cursor is null or g.k > p_cursor)
   order by g.k
   limit p_limite $$;

create function tecnica.f_rep_envios_pagina(p_formulario text, p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_plantilla jsonb, p_fecha_max date)
returns table (k text, fila jsonb)
language sql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
  select x.k,
         p_plantilla || coalesce(x.valores, '{}'::jsonb) || jsonb_build_object(
           'muestra', tecnica.f_rep_ts(x.muestra_ts),
           'fuera_referencia', x.n_fuera, 'estado', case when x.n_excl = 0 then 'Vigente' when x.n_excl = x.n then 'Excluido' else 'Excluido en parte' end,
           'fuente', case x.fuente when 'manual' then 'Manual' when 'telemetria' then 'Telemetría' else x.fuente end,
           'registrado', tecnica.f_rep_ts(x.registrado_en), 'registro', x.autor, 'envio', x.lote_id::text)
         || case when p_formulario <> 'muestreo' then jsonb_build_object('planta', x.planta_nombre) else '{}'::jsonb end
         || case when p_formulario <> 'entrada' then jsonb_build_object('punto', x.punto, 'punto_nombre', x.punto_nombre) else '{}'::jsonb end
         || case when p_formulario = 'muestreo' then jsonb_build_object('tipo_punto', case pu.tipo when 'muestreo' then 'Muestreo' when 'tanque' then 'Tanque' when 'distribucion' then 'Distribución' when 'macromedicion' then 'Macromedición' else pu.tipo end, 'zona', pu.zona, 'numero_informe', pu.numero_informe)
                 else '{}'::jsonb end
         || case when p_formulario = 'entrada' then jsonb_build_object('coagulante', dz.coagulante, 'dosis_ppm', dz.dosis) else '{}'::jsonb end
    from (select d.lote_id, pl.codigo as planta, pu.codigo as punto, min(d.muestra_ts) as muestra_ts,
                 to_char(min(d.muestra_ts) at time zone 'America/Bogota', 'YYYYMMDDHH24MISS') || '|' || d.lote_id::text || '|' || coalesce(pl.codigo, '') || '|' || coalesce(pu.codigo, '') as k,
                 min(pl.nombre) as planta_nombre, min(pu.nombre) as punto_nombre, min(d.registrado_en) as registrado_en, min(d.autor) as autor, min(d.fuente) as fuente,
                 count(*) as n, count(*) filter (where d.excluido) as n_excl,
                 count(*) filter (where d.marca is not null and (p_incl or not d.excluido)) as n_fuera,
                 jsonb_object_agg('v_' || v.codigo, d.valor) filter (where p_incl or not d.excluido) as valores
            from tecnica.f_rep_valores(array[p_formulario], p_f, p_corte, case when p_cursor is not null then to_date(left(p_cursor, 8), 'YYYYMMDD') end, null, p_fecha_max) d
            join tecnica.variables v on v.id = d.variable_id
            left join tecnica.plantas pl on pl.id = d.planta_id
            left join tecnica.puntos pu on pu.id = d.punto_id
           group by d.lote_id, pl.codigo, pu.codigo) x
    left join tecnica.puntos pu on pu.codigo = x.punto
    left join lateral (select case when q.pide_nombre then 'Otro' else q.nombre end as coagulante, u.dosis
                         from tecnica.v_uso_quimicos_estado u join tecnica.quimicos q on q.id = u.quimico_id join tecnica.plantas pl on pl.id = u.planta_id
                        where p_formulario = 'entrada' and u.lote_id = x.lote_id and u.origen = 'entrada' and pl.codigo = x.planta and (p_incl or not u.excluido)
                        order by u.id limit 1) dz on true
   where (p_incl or x.n_excl < x.n) and (p_cursor is null or x.k > p_cursor)
   order by x.k
   limit p_limite $$;

-- Entrada, Salida y Muestreo: primero las llaves de la página (hasta qué día llega) y después solo esos días con sus valores y marcas.
-- Con «solo llave» (para contar al iniciar) no se calculan referencias.
create function tecnica.f_rep_envios(p_formulario text, p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_plantilla jsonb, p_solo_llave boolean default false)
returns table (k text, fila jsonb)
language plpgsql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_hasta date;
begin
  if p_solo_llave then
    return query select l.k, null::jsonb from tecnica.f_rep_envios_llaves(p_formulario, p_f, p_incl, p_corte, p_cursor, p_limite) l;
    return;
  end if;
  select max(l.fecha) into v_hasta from tecnica.f_rep_envios_llaves(p_formulario, p_f, p_incl, p_corte, p_cursor, p_limite) l;
  if v_hasta is null then return; end if;
  return query select * from tecnica.f_rep_envios_pagina(p_formulario, p_f, p_incl, p_corte, p_cursor, p_limite, p_plantilla, v_hasta);
end $$;

-- 4–5. Uso y entrada de químicos: una fila por movimiento.
create function tecnica.f_rep_quimicos(p_tipo text, p_f jsonb, p_corte timestamptz, p_cursor text, p_limite integer) returns table (k text, fila jsonb)
language sql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
  select lpad(m.id::text, 19, '0'),
         jsonb_build_object('movimiento', m.id, 'dia', m.dia, 'quimico', q.nombre, 'cantidad', m.cantidad, 'unidad', m.unidad, 'cantidad_kg', abs(m.cantidad_kg),
                            'registrado', tecnica.f_rep_ts(m.registrado_en), 'registro', m.autor)
         || case when p_tipo = 'uso' then jsonb_build_object('planta', pl.nombre, 'dosis_optima_ppm', m.dosis_optima_ppm,
                                                            'para_que', case m.para_que when 'dosificacion' then 'Dosificación' when 'limpieza' then 'Limpieza' else 'Otro' end)
                 else jsonb_build_object('proveedor', m.proveedor, 'remision', m.remision, 'lote_fabricante', m.lote_fabricante, 'vence', m.vence,
                                         'foto_remision', case when m.remision_foto is not null then m.id end) end
    from tecnica.quimico_movimientos m join tecnica.quimicos q on q.id = m.quimico_id left join tecnica.plantas pl on pl.id = m.planta_id
   where m.tipo = p_tipo and m.dia between (p_f ->> 'desde')::date and (p_f ->> 'hasta')::date and m.registrado_en <= p_corte
     and (p_f ->> 'quimico' is null or q.codigo = p_f ->> 'quimico') and (p_f ->> 'planta' is null or pl.codigo = p_f ->> 'planta')
     and (p_cursor is null or m.id > p_cursor::bigint)
   order by m.id
   limit p_limite $$;

-- 6. Kardex: por químico, saldo inicial, cada movimiento (por día y número) con el saldo corrido, y saldo al cierre. El inventario inicial REEMPLAZA el saldo
--    (igual que tecnica.v_quimico_saldo). Antes del primer inventario el saldo es desconocido (nulo).
create function tecnica.f_rep_kardex(p_f jsonb, p_corte timestamptz, p_cursor text, p_limite integer) returns table (k text, fila jsonb)
language sql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
  with m as (
    select m.*, q.codigo as q_codigo, q.nombre as q_nombre,
           sum(case when m.tipo = 'inventario_inicial' then 1 else 0 end) over (partition by m.quimico_id order by m.dia, m.id) as seg
      from tecnica.quimico_movimientos m join tecnica.quimicos q on q.id = m.quimico_id
     where q.codigo <> 'otro' and (p_f ->> 'quimico' is null or q.codigo = p_f ->> 'quimico')
       and m.dia <= (p_f ->> 'hasta')::date and m.registrado_en <= p_corte),
  s as (select m.*, case when m.seg = 0 then null else sum(m.cantidad_kg) over (partition by m.quimico_id, m.seg order by m.dia, m.id) end as saldo from m),
  qs as (select distinct s.quimico_id, s.q_codigo, s.q_nombre from s),
  filas as (
    select qs.q_codigo || '|0' as k,
           jsonb_build_object('quimico', qs.q_nombre, 'tipo', 'Saldo inicial', 'dia', (p_f ->> 'desde')::date,
                              'saldo_kg', (select s.saldo from s where s.quimico_id = qs.quimico_id and s.dia < (p_f ->> 'desde')::date order by s.dia desc, s.id desc limit 1)) as fila
      from qs
    union all
    select s.q_codigo || '|1|' || to_char(s.dia, 'YYYYMMDD') || '|' || lpad(s.id::text, 19, '0'),
           jsonb_build_object('quimico', s.q_nombre, 'dia', s.dia, 'movimiento', s.id,
             'tipo', case s.tipo when 'inventario_inicial' then 'Inventario inicial' when 'entrada' then 'Entrada' when 'uso' then 'Uso' else 'Ajuste por conteo' end,
             'planta', (select pl.nombre from tecnica.plantas pl where pl.id = s.planta_id),
             'detalle', case s.tipo when 'uso' then case s.para_que when 'dosificacion' then 'Dosificación' when 'limpieza' then 'Limpieza' else 'Otro' end
                                    when 'entrada' then concat_ws(' · ', 'Remisión ' || s.remision, s.proveedor)
                                    when 'inventario_inicial' then 'Conteo físico' else 'Ajuste por conteo' end,
             'entra_kg', case when s.tipo in ('entrada', 'ajuste') and s.cantidad_kg > 0 then s.cantidad_kg end,
             'sale_kg', case when s.tipo in ('uso', 'ajuste') and s.cantidad_kg < 0 then -s.cantidad_kg end,
             'conteo_kg', case when s.tipo = 'inventario_inicial' then s.cantidad_kg end,
             'saldo_kg', s.saldo, 'registro', s.autor)
      from s where s.dia >= (p_f ->> 'desde')::date
    union all
    select qs.q_codigo || '|2',
           jsonb_build_object('quimico', qs.q_nombre, 'tipo', 'Saldo al cierre', 'dia', (p_f ->> 'hasta')::date,
                              'saldo_kg', (select s.saldo from s where s.quimico_id = qs.quimico_id order by s.dia desc, s.id desc limit 1))
      from qs)
  select f.k, jsonb_build_object('bodega', 'Bodega de químicos', 'movimiento', null, 'planta', null, 'detalle', null, 'entra_kg', null, 'sale_kg', null,
                                 'conteo_kg', null, 'registro', null) || f.fila
    from filas f
   where p_cursor is null or f.k > p_cursor
   order by f.k
   limit p_limite $$;

-- 7. Eventos de suspensión de una planta (Corte 15): sale si estuvo vigente algún momento del periodo. Anulados solo con «Incluir excluidos». Sin la causa.
create function tecnica.f_rep_eventos_planta(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer) returns table (k text, fila jsonb)
language sql stable set search_path to 'public', 'tecnica', 'redes', 'pg_temp' as $$
  select lpad(e.id::text, 19, '0'),
         jsonb_build_object('evento', e.codigo, 'planta', pl.nombre, 'estado', case e.estado when 'abierto' then 'Abierto' when 'cerrado' then 'Cerrado' else 'Anulado' end,
           'suspendido', tecnica.f_rep_ts(e.desde), 'regreso_estimado_inicial', tecnica.f_rep_ts(e.regreso_estimado), 'regreso_estimado', tecnica.f_rep_ts(e.regreso_vigente),
           'cambios_regreso', (select count(*) from redes.evento_suspension_eventos x where x.evento_id = e.id and x.tipo = 'regreso'),
           'reanudado', case when e.estado = 'cerrado' then tecnica.f_rep_ts(e.fin_en) end,
           'duracion_h', case when e.estado = 'cerrado' then round(extract(epoch from e.fin_en - e.desde) / 3600.0, 1) end,
           'contratos', e.contratos, 'sensibles', e.sensibles, 'reportes', (select count(*) from redes.f_evento_reportes(e.id)),
           'dano', cat.dano, 'tipo', cat.tipo, 'causa', cat.causa, 'intervencion', cat.intervencion, 'tipo_intervencion', cat.tipo_intervencion,
           'declaro', e.autor, 'cerro', e.fin_autor)
    from redes.v_evento_suspension e join tecnica.plantas pl on pl.id = e.planta_id
    -- del catálogo (David, 20-nov): el tipo y la causa del daño asociado (el del evento o el de su intervención) y el tipo de la intervención; la causa ESCRITA no
    left join lateral (select case when e.dano_id is not null then d.codigo end as dano, td.nombre as tipo, i.codigo as intervencion, ti.nombre as tipo_intervencion,
                              case d.causa_clase when 'propia' then coalesce(ca.nombre, 'Propia') when 'terceros' then 'Terceros' || coalesce(': ' || tt.nombre, '')
                                                 when 'desconocida' then 'Desconocida' end as causa
                         from (select 1) u
                         left join redes.intervenciones i on i.id = e.intervencion_id
                         left join redes.tipos_intervencion ti on ti.codigo = i.tipo_codigo
                         left join redes.danos d on d.id = coalesce(e.dano_id, i.dano_id)
                         left join redes.tipos_dano td on td.codigo = d.tipo_codigo
                         left join redes.causas ca on ca.codigo = d.causa_codigo
                         left join redes.tipos_tercero tt on tt.codigo = d.tercero_tipo) cat on true
   where e.planta_id is not null and e.creado_en <= p_corte
     and e.desde < (((p_f ->> 'hasta')::date + 1)::timestamp at time zone 'America/Bogota')
     and coalesce(e.fin_en, 'infinity'::timestamptz) >= ((p_f ->> 'desde')::date::timestamp at time zone 'America/Bogota')
     and (p_incl or e.estado <> 'anulado') and (p_f ->> 'planta' is null or pl.codigo = p_f ->> 'planta')
     and (p_cursor is null or e.id > p_cursor::bigint)
   order by e.id
   limit p_limite $$;

-- 8. Valores fuera de referencia, con la revisión vigente del supervisor (sin su nota).
create function tecnica.f_rep_fuera_referencia(p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer) returns table (k text, fila jsonb)
language sql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
  select lpad(d.registro_id::text, 19, '0'),
         jsonb_build_object('muestra', tecnica.f_rep_ts(d.muestra_ts), 'formulario', f.nombre, 'planta', pl.nombre, 'punto', pu.codigo,
           'variable', v.nombre, 'valor', d.valor, 'unidad', v.unidad, 'marca', case d.marca when 'alto' then 'Alto' else 'Bajo' end,
           'ref_min', d.ref_min, 'ref_max', d.ref_max, 'ref_origen', case d.ref_origen when 'norma' then 'Norma' when 'criterio_planta' then 'Criterio de planta' else d.ref_origen end,
           'revision', case rv.accion when 'revisado' then 'Revisado' when 'reabierto' then 'Reabierto' else 'Sin revisar' end,
           'revisado_por', rv.creado_por, 'revisado_en', tecnica.f_rep_ts(rv.creado_en), 'excluido', d.excluido,
           'registrado', tecnica.f_rep_ts(d.registrado_en), 'registro', d.autor, 'registro_id', d.registro_id)
    from tecnica.f_rep_valores(case when p_f ->> 'formulario' is null then array['entrada', 'salida', 'muestreo'] else array[p_f ->> 'formulario'] end,
                               p_f, p_corte, null, case when p_cursor is not null then p_cursor::bigint end, null, true) d
    join tecnica.f_formularios() f on f.clave = d.formulario
    join tecnica.variables v on v.id = d.variable_id
    left join tecnica.plantas pl on pl.id = d.planta_id
    left join tecnica.puntos pu on pu.id = d.punto_id
    left join lateral (select r.accion, r.creado_por, r.creado_en from tecnica.revisiones_fuera_referencia r where r.registro_id = d.registro_id order by r.id desc limit 1) rv on true
   where d.marca is not null and (p_incl or not d.excluido)
   order by d.registro_id
   limit p_limite $$;

-- Las filas de cualquier reporte (p_limite nulo = todas; con «solo llave», así se cuentan al iniciar).
create function tecnica.f_rep_filas(p_reporte text, p_f jsonb, p_incl boolean, p_corte timestamptz, p_cursor text, p_limite integer, p_plantilla jsonb, p_solo_llave boolean default false)
returns table (k text, fila jsonb)
language plpgsql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
begin
  if p_reporte in ('entrada', 'salida', 'muestreo') then
    return query select * from tecnica.f_rep_envios(p_reporte, p_f, p_incl, p_corte, p_cursor, p_limite, p_plantilla, p_solo_llave);
  elsif p_reporte = 'uso_quimicos' then
    return query select * from tecnica.f_rep_quimicos('uso', p_f, p_corte, p_cursor, p_limite);
  elsif p_reporte = 'entrada_quimicos' then
    return query select * from tecnica.f_rep_quimicos('entrada', p_f, p_corte, p_cursor, p_limite);
  elsif p_reporte = 'kardex_quimicos' then
    return query select * from tecnica.f_rep_kardex(p_f, p_corte, p_cursor, p_limite);
  elsif p_reporte = 'eventos_planta' then
    return query select * from tecnica.f_rep_eventos_planta(p_f, p_incl, p_corte, p_cursor, p_limite);
  elsif p_reporte = 'fuera_referencia' then
    return query select * from tecnica.f_rep_fuera_referencia(p_f, p_incl, p_corte, p_cursor, p_limite);
  else
    perform tecnica.f_error('Ese reporte no existe.');
  end if;
end $$;

-- Las líneas de la hoja «Léame».
create function tecnica.f_rep_leame(p_reporte text, p_f jsonb, p_incl boolean, p_email text, p_corte timestamptz) returns jsonb
language plpgsql stable set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare c record; v_trae text[]; v_no text[] := array['Textos libres (descripciones, observaciones, motivos y notas): pueden traer datos de personas y se ven solo en pantalla.',
                                                       'Teléfonos y nombres de suscriptores o de terceros.'];
  v_filtros text[]; v_ex text;
begin
  select * into c from tecnica.f_rep_catalogo() x where x.clave = p_reporte;
  v_trae := case p_reporte
    when 'entrada' then array['Una fila por envío del formulario Entrada y por planta, con una columna por variable (las unidades van en el encabezado).',
                              'La dosis de coagulante registrada con el mismo envío («Otro» sale sin su nombre).',
                              'Cuántos valores del envío quedaron fuera de referencia y si el envío está vigente o excluido.']
    when 'salida' then array['Una fila por envío del formulario Salida y por lugar (planta o punto), con una columna por variable.',
                             'Cuántos valores del envío quedaron fuera de referencia y si el envío está vigente o excluido.']
    when 'muestreo' then array['Una fila por muestra (envío de un punto), con una columna por parámetro.',
                               'Si los resultados de una misma muestra llegaron en varios envíos, sale una fila por envío.',
                               'Cuántos valores quedaron fuera de referencia y si el envío está vigente o excluido.']
    when 'uso_quimicos' then array['Una fila por uso registrado (formulario Uso de químicos), con la cantidad digitada y en kg, y la dosis óptima vigente al registrarlo.']
    when 'entrada_quimicos' then array['Una fila por entrada a la bodega (formulario Entrada de químicos).',
                                       'La foto de la remisión va como enlace: se abre en el geoportal con su sesión (solo supervisor de planta y administrador).']
    when 'kardex_quimicos' then array['Por químico: el saldo al empezar el periodo, cada movimiento (inventario inicial, entrada, uso y ajuste por conteo) con el saldo corrido, y el saldo al cierre.',
                                      'Orden: por día y, el mismo día, por número de movimiento. Un inventario inicial reemplaza el saldo por lo contado.',
                                      'Antes del primer inventario inicial de un químico el saldo es desconocido y la celda va vacía.',
                                      'Hoy hay una sola bodega de químicos.']
    when 'eventos_planta' then array['Una fila por evento de suspensión declarado para una planta, vigente algún momento del periodo: suspensión, regreso estimado (al declarar y el vigente), reanudación y duración.',
                                     'Contratos y usuarios sensibles afectados como números (los que se calcularon al declarar), y cuántos reportes tiene asociados hoy.',
                                     'El tipo de daño o falla y la causa del daño salen del catálogo del daño asociado (el del evento o el de su intervención); vacíos si el evento no tiene daño.']
    when 'fuera_referencia' then array['Una fila por valor de Entrada, Salida o Muestreo fuera de su referencia vigente, con la revisión vigente (la más reciente): su estado, quién y cuándo. No trae el historial de revisiones.']
  end;
  if p_reporte = 'eventos_planta' then v_no := v_no || array['La causa escrita al declarar el evento ni los motivos de cierre o anulación (texto libre).']; end if;
  if p_reporte = 'fuera_referencia' then v_no := v_no || array['La nota de la revisión (texto libre).']; end if;
  if p_reporte in ('uso_quimicos', 'entrada_quimicos', 'kardex_quimicos') then v_no := v_no || array['Los motivos de inventarios y ajustes (texto libre).']; end if;
  v_filtros := array['Periodo: ' || to_char((p_f ->> 'desde')::date, 'DD/MM/YYYY') || ' a ' || to_char((p_f ->> 'hasta')::date, 'DD/MM/YYYY') || ' (según ' || c.periodo_sobre || ')'];
  if p_f ? 'planta' then v_filtros := v_filtros || ('Planta: ' || (p_f ->> 'planta_nombre')); end if;
  if p_f ? 'punto' then v_filtros := v_filtros || ('Punto: ' || (p_f ->> 'punto') || ' · ' || (p_f ->> 'punto_nombre')); end if;
  if p_f ? 'zona' then v_filtros := v_filtros || ('Zona: ' || initcap(p_f ->> 'zona')); end if;
  if p_f ? 'quimico' then v_filtros := v_filtros || ('Químico: ' || (p_f ->> 'quimico_nombre')); end if;
  if p_f ? 'formulario' then v_filtros := v_filtros || ('Formulario: ' || initcap(p_f ->> 'formulario')); end if;
  v_ex := case when not c.usa_excluidos then null
               when p_reporte = 'eventos_planta' then case when p_incl then 'Eventos anulados: incluidos' else 'Eventos anulados: no incluidos' end
               else case when p_incl then 'Valores excluidos: incluidos' else 'Valores excluidos: no incluidos' end end;
  if v_ex is not null then v_filtros := v_filtros || v_ex; end if;
  return jsonb_build_object('que_trae', to_jsonb(v_trae), 'que_no_trae', to_jsonb(v_no), 'filtros', to_jsonb(v_filtros),
                            'generado_por', p_email, 'generado_en', tecnica.f_rep_ts(p_corte));
end $$;
-- =====================================================================
-- 26 — RPC de los reportes del PTAP (solo supervisor de planta y administrador: tecnica.f_autorizar_supervision). Solo service_role las ejecuta (la Edge).
--   iniciar → valida, cuenta, guarda la descarga (con la foto de las columnas y el instante) y la deja en la auditoría;
--   pagina  → entrega hasta 5.000 filas con los filtros GUARDADOS, solo lo que existía al iniciar; vence a las 2 horas y no sirve a otra persona;
--   cerrar  → guarda el cierre (una vez) y lo deja en la auditoría;
--   remision_foto → la ruta de la foto de la remisión de una entrada de químicos (la Edge la firma por 60 s); queda en la auditoría.
-- =====================================================================
create function public.geoportal_tec_reporte_iniciar(p_solicitante text, p_reporte text, p_filtros jsonb default '{}'::jsonb, p_formato text default 'xlsx',
                                                     p_incluir_excluidos boolean default false, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text; v_rep text := lower(btrim(coalesce(p_reporte, ''))); v_formato text := lower(btrim(coalesce(p_formato, ''))); c record;
  v_f jsonb; v_incl boolean; v_corte timestamptz := clock_timestamp(); v_cols jsonb; v_plantilla jsonb; v_total bigint; v_max integer := tecnica.f_rep_max_filas(); v_id bigint;
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  select * into c from tecnica.f_rep_catalogo() x where x.clave = v_rep;
  if not found then perform tecnica.f_error('Ese reporte no existe.'); end if;
  if v_formato not in ('csv', 'xlsx') then perform tecnica.f_error('El formato debe ser Excel o CSV.'); end if;
  v_f := tecnica.f_rep_filtros(v_rep, p_filtros);
  v_incl := coalesce(p_incluir_excluidos, false) and c.usa_excluidos;
  v_cols := tecnica.f_rep_columnas(v_rep, v_f);
  select jsonb_object_agg(x ->> 'clave', 'null'::jsonb) into v_plantilla from jsonb_array_elements(v_cols) x;
  select count(*) into v_total from tecnica.f_rep_filas(v_rep, v_f, v_incl, v_corte, null, null, v_plantilla, true);
  if v_total = 0 then perform tecnica.f_error('No hay datos con esos filtros.', 'P0002'); end if;
  if v_total > v_max then
    perform tecnica.f_error('La descarga supera el máximo de ' || replace(to_char(v_max, 'FM999G999'), ',', '.') || ' filas (hay '
                            || replace(to_char(v_total, 'FM999G999G999'), ',', '.') || '). Acote el periodo o los filtros.');
  end if;
  insert into tecnica.reporte_descargas (email, reporte, filtros, incluir, formato, columnas, total, corte_en, ip)
  values (v_email, v_rep, v_f, v_incl, v_formato, v_cols, v_total, v_corte, p_ip) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_reporte_iniciar', v_id::text,
                            jsonb_build_object('reporte', v_rep, 'filtros', v_f, 'incluir_excluidos', v_incl, 'formato', v_formato, 'filas', v_total), p_ip);
  return jsonb_build_object('descarga_id', v_id, 'reporte', v_rep, 'titulo', c.titulo,
                            'archivo', 'ptap_' || v_rep || '_' || (v_f ->> 'desde') || '_a_' || (v_f ->> 'hasta'),
                            'total', v_total, 'max', v_max, 'formato', v_formato, 'incluir_excluidos', v_incl,
                            'filtros', v_f - 'planta_nombre' - 'punto_nombre' - 'quimico_nombre', 'columnas', v_cols,
                            'leame', tecnica.f_rep_leame(v_rep, v_f, v_incl, v_email, v_corte));
end $$;

create function public.geoportal_tec_reporte_pagina(p_solicitante text, p_descarga_id bigint, p_cursor text default null, p_limite integer default 5000) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text; d tecnica.reporte_descargas; v_lim integer := least(greatest(coalesce(p_limite, 5000), 1), tecnica.f_rep_max_pagina());
  v_plantilla jsonb; v_filas jsonb; v_n integer; v_ultimo text;
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  select * into d from tecnica.reporte_descargas x where x.id = p_descarga_id;
  if not found or d.email <> v_email then perform tecnica.f_error('La descarga no existe.', 'P0002'); end if;
  if exists (select 1 from tecnica.reporte_descarga_cierres c where c.descarga_id = d.id) then perform tecnica.f_error('La descarga ya terminó. Vuelva a iniciarla.', '55000'); end if;
  if d.creado_en < clock_timestamp() - interval '2 hours' then perform tecnica.f_error('La descarga venció. Vuelva a iniciarla.', '55000'); end if;
  if p_cursor is not null and (length(p_cursor) > 200 or p_cursor !~ '^[0-9A-Za-z_|-]+$') then perform tecnica.f_error('La página pedida no es válida.'); end if;
  select jsonb_object_agg(x ->> 'clave', 'null'::jsonb) into v_plantilla from jsonb_array_elements(d.columnas) x;
  select coalesce(jsonb_agg(r.fila order by r.k), '[]'::jsonb), count(*), max(r.k) into v_filas, v_n, v_ultimo
    from tecnica.f_rep_filas(d.reporte, d.filtros, d.incluir, d.corte_en, p_cursor, v_lim, v_plantilla) r;
  return jsonb_build_object('filas', v_filas, 'devueltos', v_n, 'cursor', case when v_n = v_lim then v_ultimo end);
end $$;

create function public.geoportal_tec_reporte_cerrar(p_solicitante text, p_descarga_id bigint, p_filas integer default 0, p_resultado text default 'completa', p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text; v_res text := lower(btrim(coalesce(p_resultado, ''))); d tecnica.reporte_descargas; v_n integer;
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  if v_res not in ('completa', 'cancelada', 'error') then perform tecnica.f_error('Resultado de descarga no válido.'); end if;
  if p_filas is null or p_filas < 0 then perform tecnica.f_error('El número de filas no es válido.'); end if;
  select * into d from tecnica.reporte_descargas x where x.id = p_descarga_id;
  if not found or d.email <> v_email then perform tecnica.f_error('La descarga no existe.', 'P0002'); end if;
  insert into tecnica.reporte_descarga_cierres (descarga_id, filas, resultado, ip) values (d.id, p_filas, v_res, p_ip) on conflict (descarga_id) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('descarga_id', d.id, 'cerrada', true, 'repetida', true); end if;
  perform tecnica.f_auditar(v_email, 'tec_reporte_cerrar', d.id::text, jsonb_build_object('reporte', d.reporte, 'filas_entregadas', p_filas, 'resultado', v_res), p_ip);
  return jsonb_build_object('descarga_id', d.id, 'cerrada', true, 'repetida', false);
end $$;

create function public.geoportal_tec_reporte_remision_foto(p_solicitante text, p_movimiento bigint, p_ip text default null) returns jsonb
language plpgsql security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text; v_ruta text;
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  select m.remision_foto into v_ruta from tecnica.quimico_movimientos m where m.id = p_movimiento and m.tipo = 'entrada';
  if v_ruta is null then perform tecnica.f_error('Ese movimiento no tiene foto de la remisión.', 'P0002'); end if;
  perform tecnica.f_auditar(v_email, 'tec_reporte_remision_foto', p_movimiento::text, '{}'::jsonb, p_ip);
  return jsonb_build_object('movimiento', p_movimiento, 'ruta', v_ruta);
end $$;
-- =====================================================================
-- 40 — PERMISOS: todo lo nuevo sin permisos para nadie; las 4 RPC solo para service_role (la Edge). Por NOMBRE EXACTO, nunca por patrón.
-- =====================================================================
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where (p.pronamespace = 'tecnica'::regnamespace and p.proname = any (array['f_rep_catalogo', 'f_rep_max_filas', 'f_rep_max_pagina', 'f_rep_ts', 'f_rep_col', 'f_rep_filtros', 'f_rep_cols_variables', 'f_rep_columnas', 'f_rep_valores', 'f_rep_envios_llaves', 'f_rep_envios_pagina', 'f_rep_envios', 'f_rep_quimicos', 'f_rep_kardex', 'f_rep_eventos_planta', 'f_rep_fuera_referencia', 'f_rep_filas', 'f_rep_leame']))
               or (p.pronamespace = 'public'::regnamespace and p.proname = any (array['geoportal_tec_reporte_iniciar', 'geoportal_tec_reporte_pagina', 'geoportal_tec_reporte_cerrar', 'geoportal_tec_reporte_remision_foto']))
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end $$;
grant execute on function public.geoportal_tec_reporte_iniciar(text, text, jsonb, text, boolean, text) to service_role;
grant execute on function public.geoportal_tec_reporte_pagina(text, bigint, text, integer) to service_role;
grant execute on function public.geoportal_tec_reporte_cerrar(text, bigint, integer, text, text) to service_role;
grant execute on function public.geoportal_tec_reporte_remision_foto(text, bigint, text) to service_role;
notify pgrst, 'reload schema';
-- =====================================================================
-- TÉCNICA · FASE 1 · REPORTES DEL PTAP · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26 y 40, en la misma transacción.
-- Todo es SIMULADO y se deshace: sus personas (prueba.rep.*), una planta de prueba (zt_rep_pl), 3 puntos (ZTREP-*), 5 variables (zt_rep_*) en Entrada, Salida y
-- Muestreo, una referencia, 2 químicos de prueba con su kardex, envíos con exclusiones y una revisión, y 2 eventos de suspensión de la planta de prueba.
-- Los textos libres de prueba llevan un nombre y un teléfono inventados («ZTREP Pedro Prueba 3009990000») para comprobar que NO salen.
-- Mide con UN AÑO de Entrada simulado en la planta de prueba (6 envíos al día, 2 variables).
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · reportes del PTAP … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
create function pg_temp.claves(j jsonb) returns text language sql as $$ select string_agg(k, ',' order by k) from jsonb_object_keys(j) k $$;
create function pg_temp.ccols(j jsonb) returns text language sql as $$ select string_agg(x ->> 'clave', ',' order by x ->> 'clave') from jsonb_array_elements(j) x $$;
create function pg_temp.todas(p_quien text, p_id bigint, p_lim integer default 5000) returns jsonb language plpgsql as $$
declare v_c text; v_r jsonb; v_todas jsonb := '[]'; i integer := 0;
begin
  loop
    v_r := public.geoportal_tec_reporte_pagina(p_quien, p_id, v_c, p_lim);
    v_todas := v_todas || (v_r -> 'filas'); v_c := v_r ->> 'cursor'; i := i + 1;
    exit when v_c is null or i > 5000;
  end loop;
  return v_todas;
end $$;
create function pg_temp.bajar(p_quien text, p_rep text, p_f jsonb, p_incl boolean default false, p_lim integer default 5000) returns jsonb language plpgsql as $$
declare v_i jsonb;
begin
  v_i := public.geoportal_tec_reporte_iniciar(p_quien, p_rep, p_f, 'xlsx', p_incl, '10.0.0.1');
  return jsonb_build_object('ini', v_i, 'filas', pg_temp.todas(p_quien, (v_i ->> 'descarga_id')::bigint, p_lim));
end $$;
create function pg_temp.hay(p_filas jsonb, p_clave text, p_valor text) returns boolean language sql as $$
  select exists (select 1 from jsonb_array_elements(p_filas) f where f ->> p_clave = p_valor) $$;
create function pg_temp.fila(p_filas jsonb, p_clave text, p_valor text) returns jsonb language sql as $$
  select f from jsonb_array_elements(p_filas) f where f ->> p_clave = p_valor limit 1 $$;
create temp table _v (codigo text primary key, id bigint);
create function pg_temp.vid(p text) returns bigint language sql as $$ select id from _v where codigo = p $$;
create function pg_temp.reg_valor(p_lote uuid, p_form text, p_var text, p_planta bigint, p_punto bigint, p_valor numeric, p_dias integer, p_hora integer) returns bigint language sql as $$
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, punto_id, valor, fecha_muestra, hora_muestra, autor)
  values (p_lote, p_form, pg_temp.vid(p_var), p_planta, p_punto, p_valor, (clock_timestamp() at time zone 'America/Bogota')::date - p_dias, make_time(p_hora, 0, 0), 'prueba.rep.op@emdupar.gov.co')
  returning id $$;

do $prueba$
declare
  adm text := 'prueba.rep.adm@emdupar.gov.co'; sp text := 'prueba.rep.sp@emdupar.gov.co'; sp2 text := 'prueba.rep.sp2@emdupar.gov.co'; sd text := 'prueba.rep.sd@emdupar.gov.co';
  op text := 'prueba.rep.op@emdupar.gov.co'; libre text := 'ZTREP Pedro Prueba 3009990000';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; per jsonb; pf jsonb; j jsonb; j2 jsonb; f jsonb; v_id bigint; v_id2 bigint; v_n integer;
  v_pl bigint; v_m1 bigint; v_m2 bigint; v_t1 bigint; v_q bigint; v_coag bigint; e1 uuid := gen_random_uuid(); e2 uuid := gen_random_uuid(); e3 uuid := gen_random_uuid();
  s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); m1 uuid := gen_random_uuid(); m2 uuid := gen_random_uuid(); v_r_alto bigint; v_r_excl bigint;
  v_mov_foto bigint; v_mov_uso bigint; v_ev1 bigint; v_ev2 bigint; v_txt text; v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_info text; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (adm, 'ZTREP Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp, 'ZTREP Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sp2, 'ZTREP Otro supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZTREP Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZTREP Operador', 'consulta', true, 'sin_restriccion', 'todos');
  per := jsonb_build_object('desde', (hoy - 30)::text, 'hasta', hoy::text);
  pf := per || '{"planta": "zt_rep_pl"}';

  -- ---------- el catálogo de prueba ----------
  insert into tecnica.plantas (codigo, nombre) values ('zt_rep_pl', 'ZTREP Planta') returning id into v_pl;
  insert into tecnica.puntos (codigo, nombre, tipo, zona, numero_informe) select 'ZTREP-M1', 'ZTREP Muestreo norte', 'muestreo', 'norte', coalesce(max(numero_informe), 0) + 1 from tecnica.puntos where tipo = 'muestreo' returning id into v_m1;
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('ZTREP-M2', 'ZTREP Muestreo sur', 'muestreo', 'sur') returning id into v_m2;
  insert into tecnica.puntos (codigo, nombre, tipo, planta_id) values ('ZTREP-T1', 'ZTREP Tanque', 'tanque', v_pl) returning id into v_t1;
  with v as (insert into tecnica.variables (codigo, nombre, unidad, categoria, decimales) values
               ('zt_rep_ti', 'ZTREP Turbiedad de ingreso', 'NTU', 'fisicoquimico', 1), ('zt_rep_qi', 'ZTREP Caudal de ingreso', 'L/s', 'caudal', 0),
               ('zt_rep_cl', 'ZTREP Cloro de salida', 'mg/L', 'fisicoquimico', 2), ('zt_rep_clt', 'ZTREP Cloro en tanque', 'mg/L', 'fisicoquimico', 2),
               ('zt_rep_ph', 'ZTREP pH', 'pH', 'fisicoquimico', 2) returning codigo, id)
  insert into _v select codigo, id from v;
  insert into tecnica.formulario_variables (formulario, variable_id, orden, alcance, tipo_punto) values
    ('entrada', pg_temp.vid('zt_rep_ti'), 991, 'por_planta', 'muestreo'), ('entrada', pg_temp.vid('zt_rep_qi'), 992, 'por_planta', 'muestreo'),
    ('salida', pg_temp.vid('zt_rep_cl'), 991, 'por_planta', 'muestreo'), ('salida', pg_temp.vid('zt_rep_clt'), 992, 'por_punto', 'tanque'),
    ('muestreo', pg_temp.vid('zt_rep_ph'), 991, 'por_punto', 'muestreo');
  insert into tecnica.referencias (variable_id, planta_id, ref_max, origen, fuente) values (pg_temp.vid('zt_rep_ti'), v_pl, 1000, 'criterio_planta', 'ZTREP referencia de prueba');
  insert into tecnica.quimicos (codigo, nombre, rol) values ('zt_rep_coag', 'ZTREP Coagulante', 'coagulante') returning id into v_coag;
  insert into tecnica.quimicos (codigo, nombre, rol) values ('zt_rep_q', 'ZTREP Químico de bodega', 'auxiliar') returning id into v_q;

  -- ---------- envíos: Entrada (E1 normal con dosis, E2 con un valor alto y otro excluido, E3 excluido entero), Salida (planta y tanque), Muestreo (2 puntos) ----------
  perform pg_temp.reg_valor(e1, 'entrada', 'zt_rep_ti', v_pl, null, 12.5, 3, 8); perform pg_temp.reg_valor(e1, 'entrada', 'zt_rep_qi', v_pl, null, 400, 3, 8);
  v_r_alto := pg_temp.reg_valor(e2, 'entrada', 'zt_rep_ti', v_pl, null, 4321.5, 2, 8); v_r_excl := pg_temp.reg_valor(e2, 'entrada', 'zt_rep_qi', v_pl, null, 410, 2, 8);
  perform pg_temp.reg_valor(e3, 'entrada', 'zt_rep_ti', v_pl, null, 10, 1, 8); perform pg_temp.reg_valor(e3, 'entrada', 'zt_rep_qi', v_pl, null, 420, 1, 8);
  insert into tecnica.exclusiones (registro_id, motivo, autor) values (v_r_excl, libre, sp);
  insert into tecnica.exclusiones (lote_id, motivo, autor) values (e3, libre, sp);
  insert into tecnica.uso_quimicos (lote_id, origen, tipo_uso, quimico_id, planta_id, dosis, fecha_muestra, hora_muestra, autor)
  values (e1, 'entrada', 'dosificacion', v_coag, v_pl, 25, hoy - 3, '08:00', op);
  insert into tecnica.revisiones_fuera_referencia (registro_id, accion, nota, creado_por) values (v_r_alto, 'revisado', libre, sp2);
  perform pg_temp.reg_valor(s1, 'salida', 'zt_rep_cl', v_pl, null, 1.2, 2, 9); perform pg_temp.reg_valor(s2, 'salida', 'zt_rep_clt', null, v_t1, 0.8, 2, 10);
  perform pg_temp.reg_valor(m1, 'muestreo', 'zt_rep_ph', null, v_m1, 7.1, 4, 7); perform pg_temp.reg_valor(m2, 'muestreo', 'zt_rep_ph', null, v_m2, 6.0, 4, 11);

  -- ---------- 01. Quién entra ----------
  perform pg_temp.reg('01.01 el supervisor de planta inicia (Entrada de la planta de prueba): 2 envíos vigentes',
    (public.geoportal_tec_reporte_iniciar(sp, 'entrada', pf, 'xlsx', false, null) ->> 'total')::integer = 2);
  perform pg_temp.reg('01.02 el administrador también', (public.geoportal_tec_reporte_iniciar(adm, 'entrada', pf, 'csv', false, null) ->> 'total')::integer = 2);
  perform pg_temp.err('01.03 el supervisor de distribución no (403)', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sd, 'entrada', pf), '42501');
  perform pg_temp.err('01.04 el operador no (403)', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', op, 'entrada', pf), '42501');
  perform pg_temp.err('01.05 ni la foto de una remisión para el supervisor de distribución (403)', format('select public.geoportal_tec_reporte_remision_foto(%L, 1)', sd), '42501');

  -- ---------- 02. Lo que se rechaza ----------
  perform pg_temp.err('02.01 un reporte que no existe', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'registros', per), null, 'Ese reporte no existe');
  perform pg_temp.err('02.02 un formato que no es Excel ni CSV', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L, %L)', sp, 'entrada', per, 'pdf'), null, 'Excel o CSV');
  perform pg_temp.err('02.03 un filtro que no aplica (químico en Entrada)', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'entrada', per || '{"quimico": "zt_rep_q"}'), null, 'no aplica');
  perform pg_temp.err('02.04 sin periodo', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'salida', '{}'), null, 'Elija el periodo');
  perform pg_temp.err('02.05 más de un año', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'salida', jsonb_build_object('desde', (hoy - 366)::text, 'hasta', hoy::text)), null, 'hasta de un año');
  perform pg_temp.err('02.06 una planta que no existe', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'entrada', per || '{"planta": "zt_no_existe"}'), null, 'planta no existe');
  perform pg_temp.err('02.07 una zona que no existe', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'muestreo', per || '{"zona": "oeste"}'), null, 'zona no existe');
  perform pg_temp.err('02.08 un formulario sin referencias (Uso de químicos) en Fuera de referencia', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'fuera_referencia', per || '{"formulario": "uso_quimicos"}'), null, 'no tiene valores');
  perform pg_temp.err('02.09 sin datos: 404', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'entrada', jsonb_build_object('desde', '2001-01-01', 'hasta', '2001-01-31', 'planta', 'zt_rep_pl')), 'P0002', 'No hay datos');

  -- ---------- 03. Entrada ----------
  j := pg_temp.bajar(sp, 'entrada', pf);
  f := pg_temp.fila(j -> 'filas', 'envio', e1::text);
  perform pg_temp.reg('03.01 una fila por envío y planta; una columna por variable con su unidad (las de prueba al final, en el orden del catálogo); la dosis del envío',
    jsonb_array_length(j -> 'filas') = 2 and (f ->> 'v_zt_rep_ti')::numeric = 12.5 and (f ->> 'v_zt_rep_qi')::numeric = 400 and f ->> 'planta' = 'ZTREP Planta'
    and f ->> 'coagulante' = 'ZTREP Coagulante' and (f ->> 'dosis_ppm')::numeric = 25 and f ->> 'estado' = 'Vigente' and (f ->> 'fuera_referencia')::integer = 0
    and exists (select 1 from jsonb_array_elements(j -> 'ini' -> 'columnas') c where c ->> 'clave' = 'v_zt_rep_ti' and c ->> 'unidad' = 'NTU' and (c ->> 'decimales')::integer = 1)
    and f ->> 'muestra' = to_char(hoy - 3, 'YYYY-MM-DD') || 'T08:00:00' and f ->> 'registro' = op, f::text);
  perform pg_temp.reg('03.02 las claves de cada fila son exactamente las columnas que anunció «iniciar»',
    (select bool_and(pg_temp.claves(x) = pg_temp.ccols(j -> 'ini' -> 'columnas')) from jsonb_array_elements(j -> 'filas') x));
  f := pg_temp.fila(j -> 'filas', 'envio', e2::text);
  perform pg_temp.reg('03.03 el valor excluido sale vacío, el envío «Excluido en parte», con 1 valor fuera de referencia; el envío excluido entero no sale',
    f -> 'v_zt_rep_qi' = 'null' and (f ->> 'v_zt_rep_ti')::numeric = 4321.5 and f ->> 'estado' = 'Excluido en parte' and (f ->> 'fuera_referencia')::integer = 1
    and not pg_temp.hay(j -> 'filas', 'envio', e3::text), f::text);
  j2 := pg_temp.bajar(sp, 'entrada', pf, true);
  perform pg_temp.reg('03.04 con «Incluir excluidos»: el valor excluido aparece y el envío excluido entero también («Excluido»)',
    (pg_temp.fila(j2 -> 'filas', 'envio', e2::text) ->> 'v_zt_rep_qi')::numeric = 410 and pg_temp.fila(j2 -> 'filas', 'envio', e3::text) ->> 'estado' = 'Excluido'
    and position('Valores excluidos: incluidos' in (j2 -> 'ini' -> 'leame')::text) > 0);
  perform pg_temp.reg('03.05 el Léame: qué trae, qué no, filtros (periodo y planta), quién y cuándo; sin motivos de exclusión en ninguna parte',
    jsonb_array_length(j -> 'ini' -> 'leame' -> 'que_trae') >= 1 and jsonb_array_length(j -> 'ini' -> 'leame' -> 'que_no_trae') >= 1
    and position('Planta: ZTREP Planta' in (j -> 'ini' -> 'leame')::text) > 0 and j -> 'ini' -> 'leame' ->> 'generado_por' = sp and position('Pedro' in (j || j2)::text) = 0);

  -- ---------- 04. Salida y 05. Muestreo ----------
  j := pg_temp.bajar(sp, 'salida', per || '{"punto": "ZTREP-T1"}');
  perform pg_temp.reg('04.01 Salida por punto: el envío del tanque con su punto y su variable; el de la planta no',
    jsonb_array_length(j -> 'filas') = 1 and (j -> 'filas' -> 0 ->> 'v_zt_rep_clt')::numeric = 0.8 and j -> 'filas' -> 0 ->> 'punto' = 'ZTREP-T1' and j -> 'filas' -> 0 ->> 'punto_nombre' = 'ZTREP Tanque', (j -> 'filas')::text);
  j := pg_temp.bajar(sp, 'salida', pf);
  perform pg_temp.reg('04.02 Salida por planta: el envío de la planta, con la planta y sin punto', jsonb_array_length(j -> 'filas') = 1 and (j -> 'filas' -> 0 ->> 'v_zt_rep_cl')::numeric = 1.2 and j -> 'filas' -> 0 -> 'punto' = 'null', (j -> 'filas')::text);
  j := pg_temp.bajar(sp, 'muestreo', per || '{"zona": "norte"}');
  f := pg_temp.fila(j -> 'filas', 'punto', 'ZTREP-M1');
  perform pg_temp.reg('05.01 Muestreo por zona norte: el punto de prueba del norte con tipo, zona y número en el informe; el del sur no',
    f ->> 'tipo_punto' = 'Muestreo' and f ->> 'zona' = 'norte' and (f ->> 'numero_informe')::integer = (select numero_informe from tecnica.puntos where codigo = 'ZTREP-M1') and (f ->> 'v_zt_rep_ph')::numeric = 7.1 and not pg_temp.hay(j -> 'filas', 'punto', 'ZTREP-M2')
    and not (j -> 'ini' -> 'columnas')::text like '%"planta"%', f::text);
  perform pg_temp.reg('05.02 Muestreo por punto', jsonb_array_length((pg_temp.bajar(sp, 'muestreo', per || '{"punto": "ZTREP-M2"}')) -> 'filas') = 1);

  -- ---------- 06–08. Químicos: un kardex completo del químico de prueba (inventario, entrada, uso, entrada con foto, ajuste, inventario, uso) ----------
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, autor) values ('entrada', v_q, 300, 'kg', 300, hoy - 45, 'ZTREP Químicos S. A.', 'R-090', op);
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor) values ('inventario_inicial', v_q, 1000, 'kg', 1000, hoy - 40, 'ZTREP conteo inicial de prueba', sp);
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, autor) values ('entrada', v_q, 0.5, 't', 500, hoy - 35, 'ZTREP Químicos S. A.', 'R-100', op);
  insert into tecnica.quimico_movimientos (tipo, quimico_id, planta_id, para_que, cantidad, unidad, cantidad_kg, dia, dosis_optima_ppm, autor) values ('uso', v_q, v_pl, 'dosificacion', 200, 'kg', -200, hoy - 20, 18, op) returning id into v_mov_uso;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, lote_fabricante, vence, remision_foto, autor)
  values ('entrada', v_q, 1, 't', 1000, hoy - 10, 'ZTREP Químicos S. A.', 'R-123', 'L-9', hoy + 300, 'remisiones/' || to_char(hoy, 'YYYY-MM') || '/' || gen_random_uuid() || '.jpg', op) returning id into v_mov_foto;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor) values ('ajuste', v_q, 100, 'kg', -100, hoy - 5, libre, sp);
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor) values ('inventario_inicial', v_q, 2150, 'kg', 2150, hoy - 2, libre, sp);
  insert into tecnica.quimico_movimientos (tipo, quimico_id, planta_id, para_que, cantidad, unidad, cantidad_kg, dia, autor) values ('uso', v_q, v_pl, 'limpieza', 50, 'kg', -50, hoy - 1, op);
  j := pg_temp.bajar(sp, 'uso_quimicos', per || '{"quimico": "zt_rep_q"}');
  f := pg_temp.fila(j -> 'filas', 'movimiento', v_mov_uso::text);
  perform pg_temp.reg('06.01 Uso de químicos: los 2 usos del periodo, con planta, «Dosificación», kg en positivo y la dosis óptima vigente',
    jsonb_array_length(j -> 'filas') = 2 and f ->> 'para_que' = 'Dosificación' and (f ->> 'cantidad_kg')::numeric = 200 and (f ->> 'dosis_optima_ppm')::numeric = 18 and f ->> 'planta' = 'ZTREP Planta'
    and pg_temp.hay(j -> 'filas', 'para_que', 'Limpieza'), (j -> 'filas')::text);
  j := pg_temp.bajar(sp, 'entrada_quimicos', per || '{"quimico": "zt_rep_q"}');
  f := pg_temp.fila(j -> 'filas', 'movimiento', v_mov_foto::text);
  perform pg_temp.reg('07.01 Entrada de químicos: la del periodo, con proveedor, remisión, lote, vencimiento y la foto como enlace (el número del movimiento), no la ruta',
    jsonb_array_length(j -> 'filas') = 1 and f ->> 'proveedor' = 'ZTREP Químicos S. A.' and f ->> 'remision' = 'R-123' and (f ->> 'foto_remision')::bigint = v_mov_foto
    and (f ->> 'cantidad_kg')::numeric = 1000 and f ->> 'unidad' = 't' and position('remisiones/' in (j)::text) = 0, f::text);
  j2 := public.geoportal_tec_reporte_remision_foto(sp, v_mov_foto, '10.0.0.3');
  perform pg_temp.reg('07.02 la foto de la remisión: la ruta para que la Edge la firme, y la consulta queda en la auditoría',
    j2 ->> 'ruta' like 'remisiones/%' and (j2 ->> 'movimiento')::bigint = v_mov_foto
    and exists (select 1 from public.geoportal_auditoria a where a.accion = 'tec_reporte_remision_foto' and a.referencia = v_mov_foto::text and a.email = sp and a.ip = '10.0.0.3'));
  perform pg_temp.err('07.03 un movimiento sin foto: 404', format('select public.geoportal_tec_reporte_remision_foto(%L, %s)', sp, v_mov_uso), 'P0002', 'no tiene foto');
  j := pg_temp.bajar(sp, 'kardex_quimicos', per || '{"quimico": "zt_rep_q"}');
  perform pg_temp.reg('08.01 Kardex: saldo inicial 1.500 kg (lo de antes del periodo), los 5 movimientos del periodo en orden y saldo al cierre 2.100 kg',
    jsonb_array_length(j -> 'filas') = 7 and j -> 'filas' -> 0 ->> 'tipo' = 'Saldo inicial' and (j -> 'filas' -> 0 ->> 'saldo_kg')::numeric = 1500
    and (select string_agg(x ->> 'tipo', ',' order by n) from jsonb_array_elements(j -> 'filas') with ordinality t(x, n)) = 'Saldo inicial,Uso,Entrada,Ajuste por conteo,Inventario inicial,Uso,Saldo al cierre'
    and (select string_agg(x ->> 'saldo_kg', ',' order by n) from jsonb_array_elements(j -> 'filas') with ordinality t(x, n)) = '1500,1300,2300,2200,2150,2100,2100'
    and j -> 'filas' -> 6 ->> 'tipo' = 'Saldo al cierre', (j -> 'filas')::text);
  perform pg_temp.reg('08.02 el saldo al cierre de hoy es el mismo del sistema (v_quimico_saldo); el inventario va como conteo y reemplaza el saldo; el ajuste sale',
    (j -> 'filas' -> 6 ->> 'saldo_kg')::numeric = (select s.saldo_kg from tecnica.v_quimico_saldo s where s.quimico_id = v_q)
    and (j -> 'filas' -> 4 ->> 'conteo_kg')::numeric = 2150 and (j -> 'filas' -> 3 ->> 'sale_kg')::numeric = 100 and j -> 'filas' -> 2 ->> 'detalle' = 'Remisión R-123 · ZTREP Químicos S. A.'
    and (select bool_and(x ->> 'bodega' = 'Bodega de químicos') from jsonb_array_elements(j -> 'filas') x));
  perform pg_temp.reg('08.03 los motivos de inventarios y ajustes no salen en ninguno de los tres reportes de químicos', position('Pedro' in (j)::text) = 0);
  j := pg_temp.bajar(sp, 'kardex_quimicos', jsonb_build_object('desde', (hoy - 60)::text, 'hasta', (hoy - 41)::text, 'quimico', 'zt_rep_q'));
  perform pg_temp.reg('08.04 un periodo antes del primer inventario: la entrada sale, pero el saldo es desconocido (vacío) al empezar, en el movimiento y al cerrar',
    jsonb_array_length(j -> 'filas') = 3 and j -> 'filas' -> 1 ->> 'tipo' = 'Entrada' and (j -> 'filas' -> 1 ->> 'entra_kg')::numeric = 300
    and (select bool_and(x -> 'saldo_kg' = 'null') from jsonb_array_elements(j -> 'filas') x), (j -> 'filas')::text);

  -- ---------- 09. Eventos de planta ----------
  -- un daño de prueba (falla eléctrica causada por un vehículo; su descripción no debe salir) al que se amarra el evento cerrado
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, no_ident_que_es, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, tercero_tipo, descripcion, autor)
  values (gen_random_uuid(), 'DAN-' || lpad(((select coalesce(max(substr(d.codigo, 5)::integer), 0) from redes.danos d) + 1)::text, 6, '0'), 'falla', 'electrica', 'acueducto',
          'ZTREP transformador de la planta', 10.1305, -73.5795, 'gps', clock_timestamp() - interval '11 hours', 'alto', 'terceros', 'vehiculo', libre, sd)
  returning codigo into v_txt;
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, planta_id, zona_nombre, causa, dano_id, desde, regreso_estimado, contratos, sensibles, autor)
  values ('EVS-990001', 'total', false, ST_Multi(ST_MakeEnvelope(-73.58, 10.13, -73.579, 10.131, 4326)), '{}', v_pl, 'lo que surte la planta ZTREP Planta', libre,
          (select d.id from redes.danos d where d.codigo = v_txt), clock_timestamp() - interval '10 hours', clock_timestamp() - interval '2 hours', 120, 3, sd) returning id into v_ev1;
  insert into redes.evento_suspension_eventos (evento_id, tipo, regreso_estimado, hecho_en, autor) values (v_ev1, 'regreso', clock_timestamp() - interval '1 hour', clock_timestamp() - interval '5 hours', sd);
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) values (v_ev1, 'cerrar', 'ZTREP volvió el agua a la planta', clock_timestamp() - interval '30 minutes', sp);
  insert into redes.eventos_suspension (codigo, alcance, todo, geom, sectores, planta_id, zona_nombre, causa, desde, contratos, sensibles, autor)
  values ('EVS-990002', 'total', false, ST_Multi(ST_MakeEnvelope(-73.58, 10.13, -73.579, 10.131, 4326)), '{}', v_pl, 'lo que surte la planta ZTREP Planta', 'ZTREP evento anulado',
          clock_timestamp() - interval '3 hours', 0, 0, sd) returning id into v_ev2;
  insert into redes.evento_suspension_eventos (evento_id, tipo, motivo, hecho_en, autor) values (v_ev2, 'anular', 'ZTREP se declaró por error', clock_timestamp() - interval '2 hours', sd);
  j := pg_temp.bajar(sp, 'eventos_planta', pf);
  f := pg_temp.fila(j -> 'filas', 'evento', 'EVS-990001');
  perform pg_temp.reg('09.01 Eventos de planta: el cerrado con su suspensión, regreso al declarar y vigente, 1 cambio, reanudación, 9,5 h, contratos y sensibles; el anulado no; sin la causa',
    jsonb_array_length(j -> 'filas') = 1 and f ->> 'estado' = 'Cerrado' and (f ->> 'cambios_regreso')::integer = 1 and (f ->> 'duracion_h')::numeric = 9.5 and (f ->> 'contratos')::integer = 120
    and (f ->> 'sensibles')::integer = 3 and f ->> 'reanudado' is not null and f ->> 'regreso_estimado' <> f ->> 'regreso_estimado_inicial' and f ->> 'declaro' = sd and f ->> 'cerro' = sp
    and position('Pedro' in (j)::text) = 0 and pg_temp.claves(f) = pg_temp.ccols(j -> 'ini' -> 'columnas'), f::text);
  perform pg_temp.reg('09.01b del catálogo del daño amarrado: tipo «Falla eléctrica» y causa «Terceros: Vehículo»; sin intervención; el Léame dice que la causa escrita no sale',
    f ->> 'dano' = v_txt and f ->> 'tipo' = 'Falla eléctrica' and f ->> 'causa' = 'Terceros: Vehículo' and f -> 'intervencion' = 'null' and f -> 'tipo_intervencion' = 'null'
    and (j -> 'ini' -> 'leame' -> 'que_no_trae')::text like '%causa escrita al declarar%', f::text);
  j := pg_temp.bajar(sp, 'eventos_planta', pf, true);
  perform pg_temp.reg('09.02 con «Incluir excluidos»: también el anulado (sin reanudación ni duración)',
    jsonb_array_length(j -> 'filas') = 2 and pg_temp.fila(j -> 'filas', 'evento', 'EVS-990002') ->> 'estado' = 'Anulado' and pg_temp.fila(j -> 'filas', 'evento', 'EVS-990002') -> 'duracion_h' = 'null');

  -- ---------- 10. Fuera de referencia ----------
  j := pg_temp.bajar(sp, 'fuera_referencia', pf);
  f := pg_temp.fila(j -> 'filas', 'registro_id', v_r_alto::text);
  perform pg_temp.reg('10.01 Fuera de referencia: el valor alto con su referencia, la marca, la revisión y quién la hizo; sin la nota',
    f ->> 'marca' = 'Alto' and (f ->> 'ref_max')::numeric = 1000 and f ->> 'ref_origen' = 'Criterio de planta' and f ->> 'revision' = 'Revisado' and f ->> 'revisado_por' = sp2
    and f ->> 'formulario' = 'Entrada' and f ->> 'variable' = 'ZTREP Turbiedad de ingreso' and f ->> 'unidad' = 'NTU' and (f ->> 'excluido')::boolean = false and position('Pedro' in (j)::text) = 0, f::text);
  insert into tecnica.exclusiones (registro_id, motivo, autor) values (v_r_alto, 'ZTREP se excluye el valor alto', sp);
  perform pg_temp.err('10.02 excluido el valor, ya no sale (404 sin datos)', format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'fuera_referencia', pf), 'P0002');
  j := pg_temp.bajar(sp, 'fuera_referencia', pf || '{"formulario": "entrada"}', true);
  perform pg_temp.reg('10.03 con «Incluir excluidos» vuelve, marcado «excluido»', (pg_temp.fila(j -> 'filas', 'registro_id', v_r_alto::text) ->> 'excluido')::boolean = true);
  insert into tecnica.exclusiones (registro_id, accion, motivo, autor) values (v_r_alto, 'REINCLUIR', 'ZTREP se vuelve a incluir el valor alto', sp);
  insert into tecnica.revisiones_fuera_referencia (registro_id, accion, nota, creado_por) values (v_r_alto, 'reabierto', 'ZTREP ' || libre, sp);
  j := pg_temp.bajar(sp, 'fuera_referencia', pf);
  perform pg_temp.reg('10.05 solo la revisión vigente: tras reabrirla, el valor sale UNA vez, «Reabierto», con quién y cuándo (no el historial); sin la nota',
    (select count(*) from jsonb_array_elements(j -> 'filas') x where x ->> 'registro_id' = v_r_alto::text) = 1
    and pg_temp.fila(j -> 'filas', 'registro_id', v_r_alto::text) ->> 'revision' = 'Reabierto' and pg_temp.fila(j -> 'filas', 'registro_id', v_r_alto::text) ->> 'revisado_por' = sp
    and pg_temp.fila(j -> 'filas', 'registro_id', v_r_alto::text) ->> 'revisado_en' is not null and position('Pedro' in (j)::text) = 0, (j -> 'filas')::text);

  perform pg_temp.reg('10.04 la marca, la referencia y la exclusión de cada valor del periodo (una referencia por combinación) son las mismas de tecnica.v_registros_detalle',
    (select count(*) from tecnica.f_rep_valores(array['entrada', 'salida', 'muestreo'], per, clock_timestamp(), null, null))
      = (select count(*) from tecnica.v_registros_detalle d where d.formulario in ('entrada', 'salida', 'muestreo') and d.fecha_muestra between hoy - 30 and hoy)
    and not exists (select 1 from tecnica.f_rep_valores(array['entrada', 'salida', 'muestreo'], per, clock_timestamp(), null, null) a
                     join tecnica.v_registros_detalle d on d.registro_id = a.registro_id
                    where a.marca is distinct from d.fuera_de_rango or a.excluido <> d.excluido or a.ref_min is distinct from d.ref_min or a.ref_max is distinct from d.ref_max
                       or a.ref_origen is distinct from d.ref_origen or a.lote_id <> d.lote_id or a.valor <> d.valor));

  -- ---------- 11. Paginación ----------
  j := pg_temp.bajar(sp, 'entrada', pf, true, 5000); j2 := pg_temp.bajar(sp, 'entrada', pf, true, 1);
  perform pg_temp.reg('11.01 Entrada de uno en uno = de una vez (mismo orden, sin repetir ni saltar)', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = (j -> 'ini' ->> 'total')::integer);
  j := pg_temp.bajar(sp, 'kardex_quimicos', per || '{"quimico": "zt_rep_q"}', false, 5000); j2 := pg_temp.bajar(sp, 'kardex_quimicos', per || '{"quimico": "zt_rep_q"}', false, 2);
  perform pg_temp.reg('11.02 Kardex de dos en dos = de una vez (el saldo corrido no se pierde entre páginas)', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = 7);
  j := pg_temp.bajar(sp, 'muestreo', per, false, 5000); j2 := pg_temp.bajar(sp, 'muestreo', per, false, 1);
  perform pg_temp.reg('11.03 Muestreo (todos los puntos) de uno en uno = de una vez', j -> 'filas' = j2 -> 'filas' and jsonb_array_length(j -> 'filas') = (j -> 'ini' ->> 'total')::integer);
  perform pg_temp.err('11.04 un cursor con caracteres raros se rechaza', format('select public.geoportal_tec_reporte_pagina(%L, %s, %L)', sp, j -> 'ini' ->> 'descarga_id', 'x''; drop'), null, 'no es válida');

  -- ---------- 12. La foto: lo que llega después de iniciar no entra ----------
  j := public.geoportal_tec_reporte_iniciar(sp, 'salida', pf, 'xlsx', false, null);
  perform pg_temp.reg_valor(gen_random_uuid(), 'salida', 'zt_rep_cl', v_pl, null, 1.9, 0, 6);
  perform pg_temp.reg('12.01 un envío registrado después de iniciar no sale en esa descarga (sí en una nueva)',
    jsonb_array_length(pg_temp.todas(sp, (j ->> 'descarga_id')::bigint)) = 1 and jsonb_array_length(pg_temp.bajar(sp, 'salida', pf) -> 'filas') = 2);

  -- ---------- 13. La descarga es de quien la inició, vence y se cierra una vez ----------
  v_id := (public.geoportal_tec_reporte_iniciar(sp, 'entrada', pf, 'csv', false, '10.0.0.2') ->> 'descarga_id')::bigint;
  perform pg_temp.err('13.01 otra persona no puede pedir sus páginas (404)', format('select public.geoportal_tec_reporte_pagina(%L, %s)', sp2, v_id), 'P0002');
  perform pg_temp.err('13.02 ni cerrarla (404)', format('select public.geoportal_tec_reporte_cerrar(%L, %s, 1)', sp2, v_id), 'P0002');
  j := public.geoportal_tec_reporte_cerrar(sp, v_id, 2, 'completa', '10.0.0.2'); j2 := public.geoportal_tec_reporte_cerrar(sp, v_id, 2, 'completa', '10.0.0.2');
  perform pg_temp.reg('13.03 cerrarla dos veces no es error: la segunda dice «repetida»', (j ->> 'repetida')::boolean = false and (j2 ->> 'repetida')::boolean = true);
  perform pg_temp.err('13.04 cerrada, sus páginas ya no salen (409)', format('select public.geoportal_tec_reporte_pagina(%L, %s)', sp, v_id), '55000', 'ya terminó');
  insert into tecnica.reporte_descargas (email, reporte, filtros, incluir, formato, columnas, total, corte_en, creado_en)
  values (sp, 'entrada', pf, false, 'xlsx', '[]', 1, clock_timestamp() - interval '3 hours', clock_timestamp() - interval '3 hours') returning id into v_id2;
  perform pg_temp.err('13.05 iniciada hace más de 2 horas: venció (409)', format('select public.geoportal_tec_reporte_pagina(%L, %s)', sp, v_id2), '55000', 'venció');

  -- ---------- 14. Auditoría ----------
  perform pg_temp.reg('14.01 iniciar queda en la auditoría: quién, qué reporte, filtros, filas, formato e IP',
    (select count(*) from public.geoportal_auditoria a where a.accion = 'tec_reporte_iniciar' and a.referencia = v_id::text and a.email = sp and a.ip = '10.0.0.2'
       and a.detalle ->> 'reporte' = 'entrada' and (a.detalle ->> 'filas')::integer = 2 and a.detalle ->> 'formato' = 'csv' and a.detalle -> 'filtros' ->> 'planta' = 'zt_rep_pl') = 1);
  perform pg_temp.reg('14.02 cerrar queda una sola vez, con las filas entregadas y el resultado',
    (select count(*) from public.geoportal_auditoria a where a.accion = 'tec_reporte_cerrar' and a.referencia = v_id::text and (a.detalle ->> 'filas_entregadas')::integer = 2) = 1);
  perform pg_temp.reg('14.03 la auditoría no guarda filas ni textos libres', not exists (select 1 from public.geoportal_auditoria a where a.accion like 'tec\_reporte\_%' and position('Pedro' in a.detalle::text) > 0));

  -- ---------- 15. Seguridad del esquema ----------
  perform pg_temp.reg('15.01 las 4 RPC: security definer, search_path fijo, solo service_role (ni anon, ni authenticated, ni PUBLIC)',
    (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname = any (array['geoportal_tec_reporte_iniciar', 'geoportal_tec_reporte_pagina', 'geoportal_tec_reporte_cerrar', 'geoportal_tec_reporte_remision_foto']) and p.prosecdef and p.proconfig is not null
       and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 4);
  perform pg_temp.reg('15.02 las funciones internas: nadie más que su dueño',
    not exists (select 1 from pg_proc p where p.pronamespace = 'tecnica'::regnamespace and p.proname like 'f\_rep\_%' and exists (select 1 from aclexplode(p.proacl) x where x.grantee <> p.proowner)));
  perform pg_temp.reg('15.03 las 2 tablas nuevas: RLS y sin permisos para la API',
    (select count(*) from pg_class c where c.oid in ('tecnica.reporte_descargas'::regclass, 'tecnica.reporte_descarga_cierres'::regclass) and c.relrowsecurity
       and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')) = 2);
  perform pg_temp.err('15.04 las descargas son de solo inserción: no se cambian', format('update tecnica.reporte_descargas set total = 0 where id = %s', v_id));
  perform pg_temp.err('15.05 ni se borran', format('delete from tecnica.reporte_descarga_cierres where descarga_id = %s', v_id));
  perform pg_temp.reg('15.06 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()));
  perform pg_temp.reg('15.07 la huella de redes no cambia con este paquete',
    (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
      where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) in ('b474fbbe3e0f7a3a7e6dbc04c53e02e7', '3f3c89e603629d92e1cc5065de33d0c1'));

  -- ---------- 16. Tiempos: un año de Entrada en la planta de prueba (6 envíos al día, 2 variables) ----------
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor, registrado_en)
  select l.lote, 'entrada', v.id, v_pl, 100 + (random() * 50)::integer, hoy - l.d, make_time(l.h, 0, 0), op, (hoy - l.d)::timestamp at time zone 'America/Bogota' + make_interval(hours => l.h + 1)
    from (select gen_random_uuid() as lote, d, h from generate_series(4, 365) d cross join generate_series(0, 20, 4) h) l
    cross join (select id from tecnica.variables where codigo in ('zt_rep_ti', 'zt_rep_qi')) v;
  analyze tecnica.registros;
  v_t0 := clock_timestamp(); j := public.geoportal_tec_reporte_iniciar(sp, 'entrada', jsonb_build_object('desde', (hoy - 365)::text, 'hasta', hoy::text, 'planta', 'zt_rep_pl'), 'xlsx', false, null);
  v_ms1 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_t0 := clock_timestamp(); j2 := public.geoportal_tec_reporte_pagina(sp, (j ->> 'descarga_id')::bigint, null, 1000); v_ms2 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_t0 := clock_timestamp(); v_n := (public.geoportal_tec_reporte_pagina(sp, (j ->> 'descarga_id')::bigint, j2 ->> 'cursor', 1000) ->> 'devueltos')::integer; v_ms3 := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_info := format('TIEMPOS con un año de Entrada simulado (%s envíos, %s valores): iniciar %s ms · primera página de 1.000 %s ms · la segunda %s ms (tope de la API: 30 s por llamada)',
                   j ->> 'total', (select count(*) from tecnica.registros where planta_id = v_pl), round(v_ms1), round(v_ms2), round(v_ms3));
  perform pg_temp.reg('16.01 TIEMPOS: un año de Entrada; iniciar y cada página en menos de 5 s', (j ->> 'total')::integer = 362 * 6 + 2 and (j2 ->> 'devueltos')::integer = 1000 and v_n = 1000
    and v_ms1 < 5000 and v_ms2 < 5000 and v_ms3 < 5000, v_info);

  -- ---------- 17. El tope de filas (se baja solo dentro de esta prueba) ----------
  -- Con los datos de PRUEBA (la Entrada de la planta de prueba, que tras la 16 tiene 2.174 envíos), no con Muestreo de todos los puntos: en producción, sin
  -- muestreos reales en los últimos 30 días, Muestreo traía solo los 2 de prueba y no superaba el tope de 2 (60 de 61, 20-nov).
  perform pg_temp.reg('17.00 el tope real es 50.000 (la función publicada y lo que devolvió iniciar en la 16)', tecnica.f_rep_max_filas() = 50000 and (j ->> 'max')::integer = 50000, j ->> 'max');
  create or replace function tecnica.f_rep_max_filas() returns integer language sql immutable set search_path to 'pg_catalog' as $f$ select 2 $f$;
  perform pg_temp.reg('17.02 el tope bajado está vigente en esta prueba', tecnica.f_rep_max_filas() = 2);
  perform pg_temp.err('17.01 más filas que el tope: «Acote el periodo o los filtros» (la Entrada de la planta de prueba, más de 2 envíos)',
    format('select public.geoportal_tec_reporte_iniciar(%L, %L, %L)', sp, 'entrada', per || '{"planta": "zt_rep_pl"}'), null, 'Acote el periodo');

  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · reportes del PTAP (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
