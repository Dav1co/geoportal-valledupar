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
commit;
