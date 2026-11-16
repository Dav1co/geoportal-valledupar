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
commit;
