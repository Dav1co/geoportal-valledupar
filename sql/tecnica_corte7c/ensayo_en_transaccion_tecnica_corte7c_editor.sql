begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 10 — GUARDIA Y ESTRUCTURA: foto de la remisión y parámetros de químicos editables (lo pospuesto del 7a y del 7b)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- · Presupone el 7a publicado (químicos de planta). Todo es del esquema tecnica; ninguna función de redes cambia (su huella sigue igual).
-- · ⚠ Se reemplazan 2 RPC del 7a (geoportal_tec_quimico_entrada y geoportal_tec_quimico_historial), con guardia md5 y su texto exacto en la reversa.
-- · tecnica.quimico_movimientos: UNA columna nueva, «remision_foto» (nula en todo lo que ya existe; solo para las entradas).
-- · Nada se borra; los hechos son de solo inserción. La foto va al bucket privado tecnica-evidencias (ya admite JPEG), con URL firmada desde la Edge.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.quimico_movimientos') is null or to_regclass('tecnica.quimico_parametros') is null then raise exception 'Falta el Corte 7a (químicos de planta): aplíquelo antes'; end if;
  if to_regclass('tecnica.quimico_parametro_eventos') is not null or to_regclass('tecnica.quimico_remision_preparaciones') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'tecnica' and table_name = 'quimico_movimientos' and column_name = 'remision_foto') then
    raise exception 'El Corte 7c ya está aplicado: deténgase y avise';
  end if;
  if (select count(*) from (values ('public.geoportal_tec_quimico_entrada(text,jsonb,text)', '9daf6b0ef659b44d30a9260b003e0a31'), ('public.geoportal_tec_quimico_historial(text,text)', '9112d90a773971bacfb9d69310b2da89')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) <> 2 then
    raise exception 'Las RPC de entrada o de historial de químicos no son las del Corte 7a: deténgase y avise';
  end if;
  if not exists (select 1 from storage.buckets where id = 'tecnica-evidencias' and not public and allowed_mime_types @> array['image/jpeg']) then
    raise exception 'El bucket tecnica-evidencias no existe, es público o no admite JPEG: deténgase y avise';
  end if;
  if (select count(*) from tecnica.quimico_parametros where clave in ('desvio_pct', 'marca_esperado_usado', 'dias_atras_uso', 'dias_atras_entrada')) <> 4 then
    raise exception 'Faltan parámetros de químicos del 7a: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. FOTO DE LA REMISIÓN (una por entrada, opcional). La ruta la genera la base y queda anotada a nombre de quien la pidió; la entrada solo acepta una ruta suya y ya subida.
-- ---------------------------------------------------------------------
create table tecnica.quimico_remision_preparaciones (
  ruta      text primary key check (ruta ~ '^remisiones/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.jpg$'),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
comment on table tecnica.quimico_remision_preparaciones is 'Corte 7c: rutas reservadas para la foto de la remisión de una entrada de químicos. Solo inserción.';
alter table tecnica.quimico_movimientos add column remision_foto text;
alter table tecnica.quimico_movimientos add constraint quimico_movimientos_remision_foto_ck
  check (remision_foto is null or (tipo = 'entrada' and remision_foto ~ '^remisiones/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.jpg$'));
create unique index ux_qmov_remision_foto on tecnica.quimico_movimientos (remision_foto) where remision_foto is not null;      -- una foto, una entrada
comment on column tecnica.quimico_movimientos.remision_foto is 'Corte 7c: ruta de la foto de la remisión en el bucket tecnica-evidencias (solo entradas). La ruta nunca sale al navegador: se entrega una URL firmada de 60 s.';

-- ---------------------------------------------------------------------
-- 2. PARÁMETROS EDITABLES, con historial, autor y motivo. Los edita el supervisor de planta o el administrador (el jefe de planta ajusta el desvío del 25 %).
-- ---------------------------------------------------------------------
create table tecnica.quimico_parametro_eventos (
  id        bigint generated always as identity primary key,
  clave     text not null references tecnica.quimico_parametros (clave),
  antes     numeric not null,
  despues   numeric not null,
  motivo    text not null check (length(btrim(motivo)) between 10 and 1000),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
comment on table tecnica.quimico_parametro_eventos is 'Corte 7c: historial de cambios de los parámetros de químicos. Solo inserción.';
insert into tecnica.quimico_parametros values
  ('max_bytes_remision', 3145728, 100000, 5242880, 'Tamaño máximo de la foto de la remisión (bytes)')
on conflict (clave) do nothing;

do $$
begin
  execute 'create trigger t_solo_agregar before update or delete on tecnica.quimico_remision_preparaciones for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on tecnica.quimico_remision_preparaciones for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar before update or delete on tecnica.quimico_parametro_eventos for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on tecnica.quimico_parametro_eventos for each statement execute function tecnica.f_solo_agregar()';
  execute 'alter table tecnica.quimico_remision_preparaciones enable row level security';
  execute 'alter table tecnica.quimico_parametro_eventos enable row level security';
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 26 — FUNCIONES NUEVAS
--   · tecnica.f_remision_subida: la foto es de quien la pide, ya subió, es JPEG y no pasa del tamaño.
--   · geoportal_tec_quimico_remision_preparar: reserva la ruta de la foto (quien tiene «Entrada de químicos»).
--   · geoportal_tec_quimico_parametros: los parámetros que se pueden editar, con su rango y su último cambio (supervisor de planta y administrador).
--   · geoportal_tec_quimico_parametro_fijar: cambia uno, con motivo; queda en el historial y en la auditoría.
-- =====================================================================
create function tecnica.f_remision_subida(p_ruta text, p_email text) returns bigint language plpgsql stable security definer set search_path = tecnica, storage, pg_temp as $$
declare v_b bigint; v_m text;
begin
  if p_ruta is null or not exists (select 1 from tecnica.quimico_remision_preparaciones where ruta = p_ruta and autor = p_email) then
    perform tecnica.f_error('Tome de nuevo la foto de la remisión');
  end if;
  select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_b, v_m from storage.objects o where o.bucket_id = 'tecnica-evidencias' and o.name = p_ruta;
  if not found then perform tecnica.f_error('La foto de la remisión no terminó de subir: intente de nuevo'); end if;
  if v_m is distinct from 'image/jpeg' then perform tecnica.f_error('La foto de la remisión debe ser una imagen JPEG'); end if;
  if v_b > tecnica.f_qparam('max_bytes_remision') then perform tecnica.f_error('La foto de la remisión pasa del tamaño permitido'); end if;
  return v_b;
end $$;

create function public.geoportal_tec_quimico_remision_preparar(p_solicitante text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'entrada_quimicos'); v_ruta text;
begin
  v_ruta := 'remisiones/' || to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM') || '/' || gen_random_uuid() || '.jpg';
  insert into tecnica.quimico_remision_preparaciones (ruta, autor) values (v_ruta, v_email);
  return jsonb_build_object('ruta', v_ruta, 'max_bytes', tecnica.f_qparam('max_bytes_remision'), 'tipo_mime', 'image/jpeg');
end $$;

-- Los que se editan desde la pantalla (los tamaños máximos de archivos no: dependen del bucket).
create function tecnica.f_qparam_editable(p_clave text) returns boolean language sql immutable set search_path = pg_catalog as $$
  select p_clave in ('desvio_pct', 'marca_esperado_usado', 'dias_atras_uso', 'dias_atras_entrada') $$;

create function public.geoportal_tec_quimico_parametros(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante);
begin
  return jsonb_build_object('parametros', coalesce((
    select jsonb_agg(jsonb_build_object('clave', p.clave, 'valor', p.valor, 'minimo', p.minimo, 'maximo', p.maximo, 'descripcion', p.descripcion,
             'ultimo', (select jsonb_build_object('antes', e.antes, 'despues', e.despues, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en)
                          from tecnica.quimico_parametro_eventos e where e.clave = p.clave order by e.id desc limit 1))
           order by case p.clave when 'desvio_pct' then 1 when 'marca_esperado_usado' then 2 when 'dias_atras_uso' then 3 else 4 end)
      from tecnica.quimico_parametros p where tecnica.f_qparam_editable(p.clave)), '[]'::jsonb));
end $$;

create function public.geoportal_tec_quimico_parametro_fijar(p_solicitante text, p_clave text, p_valor numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); p tecnica.quimico_parametros%rowtype; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if not coalesce(tecnica.f_qparam_editable(p_clave), false) then perform tecnica.f_error('Ese parámetro no se cambia desde la pantalla'); end if;
  select * into p from tecnica.quimico_parametros where clave = p_clave for update;
  if not found then perform tecnica.f_error('Ese parámetro no existe', 'P0002'); end if;
  if p_valor is null or p_valor < p.minimo or p_valor > p.maximo then perform tecnica.f_error(format('El valor debe estar entre %s y %s', p.minimo, p.maximo)); end if;
  if p.clave in ('marca_esperado_usado', 'dias_atras_uso', 'dias_atras_entrada') and p_valor <> floor(p_valor) then perform tecnica.f_error('Ese parámetro es un número entero'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  if p_valor = p.valor then perform tecnica.f_error('El parámetro ya tiene ese valor'); end if;
  insert into tecnica.quimico_parametro_eventos (clave, antes, despues, motivo, autor) values (p.clave, p.valor, p_valor, v_mot, v_email);
  update tecnica.quimico_parametros set valor = p_valor where clave = p.clave;
  perform tecnica.f_auditar(v_email, 'tec_quimico_parametro', p.clave, jsonb_build_object('antes', p.valor, 'despues', p_valor), null);
  return jsonb_build_object('clave', p.clave, 'antes', p.valor, 'valor', p_valor);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 7a con cambios exactos, aplicados una sola vez:
--   · geoportal_tec_quimico_entrada: acepta la foto de la remisión (opcional) y la guarda con la entrada;
--   · geoportal_tec_quimico_historial: cada movimiento trae la ruta de su foto (la Edge la cambia por una URL firmada).
-- =====================================================================
-- public.geoportal_tec_quimico_entrada(text,jsonb,text)
CREATE OR REPLACE FUNCTION public.geoportal_tec_quimico_entrada(p_solicitante text, p_datos jsonb, p_clave text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'entrada_quimicos'); d jsonb := coalesce(p_datos, '{}'::jsonb); q tecnica.quimicos; v_id bigint;
        v_cant numeric; v_vence date; m tecnica.quimico_movimientos%rowtype; v_foto text := nullif(btrim(coalesce(p_datos, '{}'::jsonb) ->> 'foto'), '');
begin
  if p_clave is not null then
    select * into m from tecnica.quimico_movimientos where clave_envio = p_clave;
    if found then
      if m.autor <> v_email then perform tecnica.f_error('Esa clave de envío no es suya'); end if;
      return jsonb_build_object('movimiento_id', m.id, 'cantidad_kg', m.cantidad_kg, 'repetido', true);
    end if;
  end if;
  q := tecnica.f_quimico_por_codigo(d ->> 'quimico');
  if not q.activo then perform tecnica.f_error('Ese químico está desactivado'); end if;
  if jsonb_typeof(d -> 'cantidad') <> 'number' then perform tecnica.f_error('Escriba la cantidad recibida'); end if;
  v_cant := (d ->> 'cantidad')::numeric;
  if v_cant <= 0 or v_cant > 1000000 then perform tecnica.f_error('La cantidad recibida debe ser mayor que 0'); end if;
  if coalesce(d ->> 'unidad', '') not in ('t', 'kg') then perform tecnica.f_error('La unidad es toneladas o kg'); end if;
  begin v_vence := (d ->> 'vence')::date; exception when others then perform tecnica.f_error('La fecha de vencimiento no es válida'); end;
  -- Corte 7c: la foto de la remisión es opcional; si viene, debe ser suya, estar subida, ser JPEG y no estar ya en otra entrada
  if v_foto is not null then
    perform tecnica.f_remision_subida(v_foto, v_email);
    if exists (select 1 from tecnica.quimico_movimientos x where x.remision_foto = v_foto) then perform tecnica.f_error('Esa foto ya quedó en otra entrada: tome una nueva'); end if;
  end if;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, lote_fabricante, vence, remision_foto, autor, clave_envio)
  values ('entrada', q.id, v_cant, d ->> 'unidad', case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end,
          tecnica.f_dia_movimiento((d ->> 'dia')::date, tecnica.f_qparam('dias_atras_entrada')),
          nullif(btrim(d ->> 'proveedor'), ''), nullif(btrim(d ->> 'remision'), ''), nullif(btrim(d ->> 'lote'), ''), v_vence, v_foto, v_email, p_clave)
  returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_entrada', q.codigo, jsonb_build_object('movimiento_id', v_id, 'con_foto', v_foto is not null), null);
  return jsonb_build_object('movimiento_id', v_id, 'cantidad_kg', case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end, 'repetido', false);
end $function$;

-- public.geoportal_tec_quimico_historial(text,text)
CREATE OR REPLACE FUNCTION public.geoportal_tec_quimico_historial(p_solicitante text, p_codigo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $function$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo);
begin
  return jsonb_build_object('codigo', q.codigo, 'nombre', q.nombre,
    'eventos', coalesce((select jsonb_agg(jsonb_build_object('tipo', e.tipo, 'dosis_optima_ppm', e.dosis_optima_ppm, 'potabilizacion', e.potabilizacion, 'activo', e.activo,
                                 'ficha_ruta', e.ficha_ruta, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en) order by e.id desc)
                           from tecnica.quimico_ficha_eventos e where e.quimico_id = q.id), '[]'::jsonb),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'dia', m.dia, 'cantidad', m.cantidad, 'unidad', m.unidad, 'cantidad_kg', m.cantidad_kg,
                                 'planta', (select p.codigo from tecnica.plantas p where p.id = m.planta_id), 'para_que', m.para_que, 'dosis_optima_ppm', m.dosis_optima_ppm,
                                 'proveedor', m.proveedor, 'remision', m.remision, 'lote', m.lote_fabricante, 'vence', m.vence, 'remision_foto_ruta', m.remision_foto, 'motivo', m.motivo, 'autor', m.autor,
                                 'registrado_en', m.registrado_en) order by m.id desc)
                               from (select * from tecnica.quimico_movimientos m where m.quimico_id = q.id order by m.id desc limit 100) m), '[]'::jsonb));
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas nuevas: nadie de la API. Las 3 RPC nuevas y las 2 reemplazadas: solo execute a service_role (la Edge geoportal-tecnica). Las internas: nadie.
-- =====================================================================
revoke all on table tecnica.quimico_remision_preparaciones, tecnica.quimico_parametro_eventos from public, anon, authenticated, service_role;
revoke all on sequence tecnica.quimico_parametro_eventos_id_seq from public, anon, authenticated, service_role;
revoke all on function tecnica.f_remision_subida(text, text), tecnica.f_qparam_editable(text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_tec_quimico_remision_preparar', 'geoportal_tec_quimico_parametros', 'geoportal_tec_quimico_parametro_fijar', 'geoportal_tec_quimico_entrada', 'geoportal_tec_quimico_historial') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@tecnica_corte7c', 'migracion_tecnica_corte7c', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.quimico_remision_preparaciones', 'tecnica.quimico_parametro_eventos'),
        'columna', 'tecnica.quimico_movimientos.remision_foto', 'rpc_nuevas', 3, 'reemplazadas', jsonb_build_array('geoportal_tec_quimico_entrada', 'geoportal_tec_quimico_historial')), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de la migración, en la misma transacción.
-- Arma sus personas (prueba.tec9.*), su químico de prueba («ZT9 …») y sus archivos en Storage. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · CORTE 7c … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- reserva una foto como la persona indicada y la «sube» (deja el objeto en Storage con ese tipo y tamaño)
create function pg_temp.foto(p_quien text, p_mime text default 'image/jpeg', p_bytes bigint default 400000) returns text language plpgsql as $$
declare v text := public.geoportal_tec_quimico_remision_preparar(p_quien) ->> 'ruta';
begin
  insert into storage.objects (bucket_id, name, metadata) values ('tecnica-evidencias', v, jsonb_build_object('size', p_bytes, 'mimetype', p_mime));
  return v;
end $$;

do $prueba$
declare
  a text := 'prueba.tec9.adm@emdupar.gov.co'; sv text := 'prueba.tec9.planta@emdupar.gov.co'; op text := 'prueba.tec9.op@emdupar.gov.co'; op2 text := 'prueba.tec9.op2@emdupar.gov.co';
  v_r jsonb; v_x jsonb; v_cod text; v_ruta text; v_f1 text; v_f2 text; v_n0 integer; v_redes text; v_desvio numeric;
  v_total integer; v_bien integer; v_fallas text;
begin
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v_redes from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  select count(*) into v_n0 from tecnica.quimico_movimientos;
  select valor into v_desvio from tecnica.quimico_parametros where clave = 'desvio_pct';
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT9 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT9 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT9 Operador', 'consulta', true, 'sin_restriccion', 'todos'), (op2, 'ZT9 Operador sin químicos', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'entrada_quimicos', a), (op, 'asignar_formulario', 'uso_quimicos', a);
  -- un químico de prueba (auxiliar: no pide dosis), con su ficha en PDF
  v_ruta := public.geoportal_tec_quimico_ficha_preparar(sv) ->> 'ruta';
  insert into storage.objects (bucket_id, name, metadata) values ('tecnica-evidencias', v_ruta, '{"size": 300000, "mimetype": "application/pdf"}'::jsonb);
  v_cod := public.geoportal_tec_quimico_crear(sv, 'ZT9 Químico de prueba', 'auxiliar', false, null, v_ruta, 'ZT9 químico para las pruebas del 7c') ->> 'codigo';

  -- ===================== 01. Estructura =====================
  perform pg_temp.reg('01.01 los movimientos que ya existían no cambian: misma cantidad y ninguno con foto',
     (select count(*) from tecnica.quimico_movimientos) = v_n0 and not exists (select 1 from tecnica.quimico_movimientos where remision_foto is not null));
  perform pg_temp.reg('01.02 el parámetro del tamaño de la foto existe y los 4 que se editan siguen con su valor', (select valor from tecnica.quimico_parametros where clave = 'max_bytes_remision') = 3145728
     and (select valor from tecnica.quimico_parametros where clave = 'desvio_pct') = v_desvio);

  -- ===================== 02. Foto de la remisión =====================
  v_r := public.geoportal_tec_quimico_remision_preparar(op);
  perform pg_temp.reg('02.01 el operador con «Entrada de químicos» reserva la foto: una ruta remisiones/AAAA-MM/<uuid>.jpg, JPEG y su tamaño máximo',
     v_r ->> 'ruta' ~ '^remisiones/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.jpg$' and v_r ->> 'tipo_mime' = 'image/jpeg' and (v_r ->> 'max_bytes')::bigint = 3145728, v_r::text);
  perform pg_temp.err('02.02 un operador sin ese formulario no reserva fotos', format($$select public.geoportal_tec_quimico_remision_preparar(%L)$$, op2), '42501');
  perform pg_temp.err('02.03 una entrada con una foto que no terminó de subir se rechaza', format($$select public.geoportal_tec_quimico_entrada(%L, %L, null)$$, op,
     jsonb_build_object('quimico', v_cod, 'cantidad', 1, 'unidad', 't', 'foto', v_r ->> 'ruta')), '22023', 'no terminó de subir');
  v_f1 := pg_temp.foto(op);
  v_x := public.geoportal_tec_quimico_entrada(op, jsonb_build_object('quimico', v_cod, 'cantidad', 2, 'unidad', 't', 'remision', 'R-9001', 'foto', v_f1), 'zt9-entrada-0001');
  perform pg_temp.reg('02.04 la entrada con su foto subida queda guardada con la ruta de la foto y la auditoría dice «con_foto» (sin la ruta)',
     (select remision_foto = v_f1 and cantidad_kg = 2000 from tecnica.quimico_movimientos where id = (v_x ->> 'movimiento_id')::bigint)
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_quimico_entrada' and email = op and (detalle ->> 'con_foto')::boolean and detalle::text not like '%remisiones/%'), v_x::text);
  perform pg_temp.reg('02.05 repetir el mismo envío (misma clave) no duplica', (public.geoportal_tec_quimico_entrada(op, jsonb_build_object('quimico', v_cod, 'cantidad', 2, 'unidad', 't', 'foto', v_f1), 'zt9-entrada-0001') ->> 'repetido')::boolean
     and (select count(*) from tecnica.quimico_movimientos where remision_foto = v_f1) = 1);
  perform pg_temp.err('02.06 la misma foto no sirve para otra entrada', format($$select public.geoportal_tec_quimico_entrada(%L, %L, null)$$, op,
     jsonb_build_object('quimico', v_cod, 'cantidad', 1, 'unidad', 'kg', 'foto', v_f1)), '22023', 'otra entrada');
  v_f2 := pg_temp.foto(sv);
  perform pg_temp.err('02.07 una foto reservada por otra persona no se acepta', format($$select public.geoportal_tec_quimico_entrada(%L, %L, null)$$, op,
     jsonb_build_object('quimico', v_cod, 'cantidad', 1, 'unidad', 'kg', 'foto', v_f2)), '22023', 'Tome de nuevo');
  perform pg_temp.err('02.08 un archivo que no es JPEG se rechaza', format($$select public.geoportal_tec_quimico_entrada(%L, %L, null)$$, op,
     jsonb_build_object('quimico', v_cod, 'cantidad', 1, 'unidad', 'kg', 'foto', pg_temp.foto(op, 'application/pdf'))), '22023', 'JPEG');
  perform pg_temp.err('02.09 una foto que pasa del tamaño se rechaza', format($$select public.geoportal_tec_quimico_entrada(%L, %L, null)$$, op,
     jsonb_build_object('quimico', v_cod, 'cantidad', 1, 'unidad', 'kg', 'foto', pg_temp.foto(op, 'image/jpeg', 4000000))), '22023', 'tamaño');
  v_x := public.geoportal_tec_quimico_entrada(op, jsonb_build_object('quimico', v_cod, 'cantidad', 50, 'unidad', 'kg'), null);
  perform pg_temp.reg('02.10 la foto es opcional: una entrada sin foto se guarda como antes', (select remision_foto is null from tecnica.quimico_movimientos where id = (v_x ->> 'movimiento_id')::bigint));
  perform pg_temp.err('02.11 la regla de la tabla: solo una entrada lleva foto de remisión', format($$insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, para_que, remision_foto, autor)
     select 'uso', id, 1, 'kg', -1, current_date, 'limpieza', %L, 'x@y.co' from tecnica.quimicos where codigo = %L$$, v_f2, v_cod), '23514');
  perform pg_temp.err('02.12 la foto de una entrada no se puede cambiar después (solo inserción)', format($$update tecnica.quimico_movimientos set remision_foto = null where remision_foto = %L$$, v_f1), '42501');
  v_r := public.geoportal_tec_quimico_historial(sv, v_cod);
  perform pg_temp.reg('02.13 el historial del supervisor trae la ruta de la foto en esa entrada (la Edge la cambia por una URL firmada) y nula en las demás',
     (select count(*) from jsonb_array_elements(v_r -> 'movimientos') m where m ->> 'remision_foto_ruta' = v_f1 and m ->> 'remision' = 'R-9001') = 1
     and (select count(*) from jsonb_array_elements(v_r -> 'movimientos') m where m ->> 'remision_foto_ruta' is not null) = 1);
  perform pg_temp.err('02.14 el operador no lee el historial (ni las fotos)', format($$select public.geoportal_tec_quimico_historial(%L, %L)$$, op, v_cod), '42501');

  -- ===================== 03. Parámetros editables =====================
  v_r := public.geoportal_tec_quimico_parametros(sv);
  perform pg_temp.reg('03.01 el supervisor de planta ve los 4 parámetros que se editan, con su rango y sin los tamaños de archivo',
     (select string_agg(p ->> 'clave', ',' order by n) from jsonb_array_elements(v_r -> 'parametros') with ordinality x(p, n)) = 'desvio_pct,marca_esperado_usado,dias_atras_uso,dias_atras_entrada'
     and (v_r -> 'parametros' -> 0 ->> 'minimo')::numeric = 1 and (v_r -> 'parametros' -> 0 ->> 'maximo')::numeric = 500 and v_r -> 'parametros' -> 0 -> 'ultimo' = 'null'::jsonb, v_r::text);
  perform pg_temp.err('03.02 el operador no ve los parámetros', format($$select public.geoportal_tec_quimico_parametros(%L)$$, op), '42501');
  v_x := public.geoportal_tec_quimico_parametro_fijar(sv, 'desvio_pct', 30, 'ZT9 el jefe de planta ajusta el desvío');
  perform pg_temp.reg('03.03 el supervisor cambia el desvío a 30 %: queda el valor, el evento con el antes, el después, el motivo y el autor, y la auditoría',
     (v_x ->> 'valor')::numeric = 30 and (v_x ->> 'antes')::numeric = v_desvio and tecnica.f_qparam('desvio_pct') = 30
     and (select antes = v_desvio and despues = 30 and autor = sv and motivo like 'ZT9%' from tecnica.quimico_parametro_eventos where clave = 'desvio_pct' order by id desc limit 1)
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_quimico_parametro' and email = sv and referencia = 'desvio_pct'), v_x::text);
  perform pg_temp.reg('03.04 el cambio rige de inmediato: el catálogo y «esperado contra usado» ya dicen 30 %',
     (public.geoportal_tec_quimicos_catalogo(sv) -> 'parametros' ->> 'desvio_pct')::numeric = 30 and (public.geoportal_tec_quimicos_comparacion(sv, null, null) ->> 'desvio_pct')::numeric = 30);
  perform pg_temp.reg('03.05 la lista muestra el último cambio', (public.geoportal_tec_quimico_parametros(a) -> 'parametros' -> 0 -> 'ultimo' ->> 'autor') = sv);
  perform pg_temp.err('03.06 fuera del rango', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'desvio_pct', 0, 'ZT9 fuera del rango permitido')$$, sv), '22023', 'entre');
  perform pg_temp.err('03.07 sin motivo suficiente', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'desvio_pct', 40, 'corto')$$, sv), '22023', 'motivo');
  perform pg_temp.err('03.08 el mismo valor no es un cambio', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'desvio_pct', 30, 'ZT9 mismo valor de antes')$$, sv), '22023', 'ya tiene');
  perform pg_temp.err('03.09 los días atrás son enteros', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'dias_atras_uso', 2.5, 'ZT9 con decimales no vale')$$, sv), '22023', 'entero');
  perform pg_temp.err('03.10 un tamaño de archivo no se cambia desde la pantalla', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'max_bytes_ficha', 200000, 'ZT9 no es editable aquí')$$, a), '22023', 'pantalla');
  perform pg_temp.err('03.11 el operador no cambia parámetros', format($$select public.geoportal_tec_quimico_parametro_fijar(%L, 'desvio_pct', 50, 'ZT9 el operador no puede')$$, op), '42501');
  perform pg_temp.err('03.12 el historial de cambios no se edita', $$update tecnica.quimico_parametro_eventos set motivo = 'ZT9 cambiado a mano' where clave = 'desvio_pct'$$, '42501');
  v_x := public.geoportal_tec_quimico_parametro_fijar(a, 'dias_atras_entrada', 3, 'ZT9 el administrador acorta los días');
  perform pg_temp.reg('03.13 el administrador también; el formulario del operador ya dice 3 días atrás', (public.geoportal_tec_quimicos_formulario(op, 'entrada_quimicos') ->> 'dias_atras')::numeric = 3);

  -- ===================== 04. Lo que ve producción =====================
  perform pg_temp.reg('04.01 pg-safeupdate: ninguna función de redes, tecnica, geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
     not exists (select 1 from redes.f_funciones_sin_where()), (select string_agg(funcion || ' → ' || sentencia, ' | ') from redes.f_funciones_sin_where()));
  perform pg_temp.reg('04.02 la huella de las funciones de redes no cambió', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = v_redes);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · CORTE 7c (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
