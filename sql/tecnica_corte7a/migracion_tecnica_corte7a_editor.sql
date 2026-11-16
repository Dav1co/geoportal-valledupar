begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 10 — GUARDIA, RESPUESTAS AL 6b Y QUÍMICOS DE PLANTA (catálogo con historial, movimientos, bucket y parámetros)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: §29 de la bitácora (químicos), respuestas de David al 6b (16-nov), plan 02 (Corte 7), 01 sección F y D-17.
-- · REGENERADO sobre el Corte 6c (16-nov): presupone el 6c aplicado (huella del conjunto de funciones de redes) y el paquete vivo «químicos y dosis» (tecnica.quimicos y tecnica.uso_quimicos).
-- · ⚠ redes: se reemplazan 4 funciones del 6c (redes.f_estado_contrato, redes.f_funciones_sin_where, geoportal_redes_contrato_tarjeta y geoportal_redes_geovisor). Ya no hay copia de contratos
--   (el 6c la retiró): la tesela y la tarjeta toman los estados nuevos solas, sin rehacer nada.
-- · ⚠ tecnica.quimicos (viva): se amplía el CHECK de «rol» con «auxiliar», se le agrega un candado de identidad (el nombre no cambia) y una fila (hipoclorito de
--   calcio). tecnica.uso_quimicos (la dosis en ppm) NO se toca.
-- · Bucket nuevo «tecnica-evidencias» (privado, PDF y JPEG, 5 MB), sin políticas: todo por URL firmada desde la Edge, como en redes.
-- =====================================================================
do $$
begin
  if to_regprocedure('redes.f_funciones_sin_where()') is null then raise exception 'Falta el Corte 6c: aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '2c2658002d114d755f19a7b5f5dfe542' then
    raise exception 'Las funciones de redes no son las del Corte 6c (o el Corte 7a ya está aplicado): deténgase y avise';
  end if;
  if to_regclass('tecnica.quimico_movimientos') is not null or to_regclass('tecnica.quimico_ficha_eventos') is not null then
    raise exception 'Las tablas del 7a ya existen: el Corte 7a parece aplicado';
  end if;
  if to_regclass('tecnica.quimicos') is null or to_regclass('tecnica.uso_quimicos') is null
     or (select count(*) from information_schema.columns where table_schema = 'tecnica' and table_name = 'quimicos'
          and column_name in ('id', 'codigo', 'nombre', 'unidad_dosis', 'rol', 'pide_nombre', 'activo')) <> 7 then
    raise exception 'Falta tecnica.quimicos o tecnica.uso_quimicos (paquete «químicos y dosis») o no tienen las columnas esperadas: deténgase y avise';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'tecnica.quimicos'::regclass and conname = 'quimicos_rol_check')
     <> 'CHECK ((rol = ANY (ARRAY[''coagulante''::text, ''desinfectante''::text, ''otro''::text])))' then
    raise exception 'El CHECK de rol de tecnica.quimicos no es el esperado: deténgase y avise';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'tecnica.quimicos'::regclass and tgname = 't_quimico_protegido' and not tgisinternal)
     or not exists (select 1 from pg_trigger where tgrelid = 'tecnica.quimicos'::regclass and tgname = 't_no_borrar' and not tgisinternal) then
    raise exception 'tecnica.quimicos no tiene sus candados: deténgase y avise';
  end if;
  if not exists (select 1 from tecnica.variables where codigo = 'caudal_qi') then raise exception 'Falta la variable caudal_qi (Entrada): deténgase y avise'; end if;
  if to_regprocedure('tecnica.f_autorizar_supervision(text)') is null or to_regprocedure('tecnica.f_autorizar_captura(text,text)') is null then
    raise exception 'Faltan las funciones de autorización de planta: deténgase y avise';
  end if;
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then raise exception 'Falta Storage (storage.buckets y storage.objects)'; end if;
  if exists (select 1 from storage.objects where bucket_id = 'tecnica-evidencias') then raise exception 'El bucket tecnica-evidencias ya tiene archivos: revise antes de seguir'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. RESPUESTAS DE DAVID AL 6b
--    (2) un color por estado del contrato: activo, suspendido, cortado, retirado y otro (más «sin dato»): en 25 (redes.f_estado_contrato); sin copia que rehacer.
--    (3) el muestreo se pinta hasta 35 días (parámetro editable), con su evento.
--    (1) nombre y dirección del contrato: en 25 (la RPC de la tarjeta).
-- ---------------------------------------------------------------------
insert into redes.parametro_eventos (clave, antes, despues, motivo, autor)
select clave, valor, 35, 'David (respuesta 3 al 6b): el muestreo se pinta hasta 35 días', 'migracion@tecnica_corte7a' from redes.parametros where clave = 'geovisor_muestreo_dias' and valor <> 35;
update redes.parametros set valor = 35 where clave = 'geovisor_muestreo_dias';

-- ---------------------------------------------------------------------
-- 2. CATÁLOGO DE QUÍMICOS (§29). La IDENTIDAD (código y nombre; todo se maneja en kg) no cambia: si quedó mal, se desactiva con motivo y se crea otro.
--    Cambian, con historial, autor y motivo: la dosis óptima, «de potabilización», la ficha técnica en PDF (versión nueva) y activo/inactivo.
-- ---------------------------------------------------------------------
alter table tecnica.quimicos drop constraint quimicos_rol_check;
alter table tecnica.quimicos add constraint quimicos_rol_check check (rol = any (array['coagulante', 'desinfectante', 'otro', 'auxiliar']));     -- auxiliar: limpieza, pH, otros

create function tecnica.f_quimico_identidad() returns trigger language plpgsql set search_path to 'pg_catalog', 'pg_temp' as $$
begin
  if new.nombre is distinct from old.nombre or new.codigo is distinct from old.codigo then
    raise exception 'La identidad del químico (código y nombre) no se cambia: desactívelo con motivo y cree uno nuevo' using errcode = '55000';
  end if;
  return new;
end $$;
create trigger t_quimico_identidad before update on tecnica.quimicos for each row execute function tecnica.f_quimico_identidad();

insert into tecnica.quimicos (codigo, nombre, rol, pide_nombre) values ('hipoclorito_calcio', 'Hipoclorito de calcio', 'auxiliar', false)
on conflict (codigo) do nothing;

create table tecnica.quimico_ficha_eventos (
  id               bigint generated always as identity primary key,
  quimico_id       bigint not null references tecnica.quimicos (id),
  tipo             text not null check (tipo in ('alta', 'dosis_optima', 'potabilizacion', 'ficha', 'activo')),
  dosis_optima_ppm numeric check (dosis_optima_ppm is null or (dosis_optima_ppm > 0 and dosis_optima_ppm <= 1000)),
  potabilizacion   boolean,
  activo           boolean,
  ficha_ruta       text check (ficha_ruta is null or ficha_ruta ~ '^quimicos/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.pdf$'),
  ficha_bytes      bigint,
  motivo           text not null check (length(btrim(motivo)) between 10 and 1000),
  autor            text not null,
  creado_en        timestamptz not null default clock_timestamp(),
  check (tipo <> 'dosis_optima' or (dosis_optima_ppm is not null and ficha_ruta is not null)),      -- §29: el PDF es obligatorio al cambiar la dosis
  check (tipo <> 'alta' or ficha_ruta is not null),                                                   -- … y al dar de alta
  check (tipo <> 'ficha' or ficha_ruta is not null),
  check (tipo <> 'potabilizacion' or potabilizacion is not null),
  check (tipo <> 'activo' or activo is not null)
);
create index ix_qfe_quimico on tecnica.quimico_ficha_eventos (quimico_id, id desc);
comment on table tecnica.quimico_ficha_eventos is 'Corte 7a (§29): historial de la ficha de cada químico (alta, dosis óptima, de potabilización, ficha técnica en PDF y activo). Solo inserción.';

create table tecnica.quimico_ficha_preparaciones (
  ruta      text primary key check (ruta ~ '^quimicos/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.pdf$'),
  autor     text not null,
  creado_en timestamptz not null default clock_timestamp()
);
comment on table tecnica.quimico_ficha_preparaciones is 'Corte 7a: rutas de PDF de ficha técnica preparadas para subir con URL firmada (quién la pidió).';

-- Lo vigente de cada químico: el último evento de cada clase.
create view tecnica.v_quimico_vigente as
select q.id as quimico_id, q.codigo, q.nombre, q.rol, q.activo,
       (select e.dosis_optima_ppm from tecnica.quimico_ficha_eventos e where e.quimico_id = q.id and e.dosis_optima_ppm is not null order by e.id desc limit 1) as dosis_optima_ppm,
       coalesce((select e.potabilizacion from tecnica.quimico_ficha_eventos e where e.quimico_id = q.id and e.potabilizacion is not null order by e.id desc limit 1),
                q.codigo in ('pac', 'cloro_gaseoso')) as potabilizacion,
       (select e.ficha_ruta from tecnica.quimico_ficha_eventos e where e.quimico_id = q.id and e.ficha_ruta is not null order by e.id desc limit 1) as ficha_ruta,
       (select e.creado_en from tecnica.quimico_ficha_eventos e where e.quimico_id = q.id and e.ficha_ruta is not null order by e.id desc limit 1) as ficha_en
  from tecnica.quimicos q
 where q.codigo <> 'otro';

-- ---------------------------------------------------------------------
-- 3. MOVIMIENTOS DE LA BODEGA (§29: una sola bodega; se recibe en toneladas y se maneja en kg). Solo inserción.
--    inventario_inicial (conteo físico, supervisor) · entrada (recepción) · uso (consumo; guarda la dosis óptima vigente) · ajuste (supervisor, con motivo).
--    cantidad y unidad: lo que digitó la persona; cantidad_kg: normalizada y con signo (el uso resta). El saldo es el último inventario inicial más lo que vino después.
-- ---------------------------------------------------------------------
create table tecnica.quimico_movimientos (
  id               bigint generated always as identity primary key,
  tipo             text not null check (tipo in ('inventario_inicial', 'entrada', 'uso', 'ajuste')),
  quimico_id       bigint not null references tecnica.quimicos (id),
  planta_id        bigint references tecnica.plantas (id),
  para_que         text check (para_que in ('dosificacion', 'limpieza', 'otro')),
  cantidad         numeric not null check (cantidad >= 0 and cantidad <= 1000000),
  unidad           text not null check (unidad in ('kg', 't')),
  cantidad_kg      numeric not null,
  dia              date not null,
  dosis_optima_ppm numeric,
  proveedor        text check (proveedor is null or length(btrim(proveedor)) between 2 and 120),
  remision         text check (remision is null or length(btrim(remision)) between 1 and 60),
  lote_fabricante  text check (lote_fabricante is null or length(btrim(lote_fabricante)) between 1 and 60),
  vence            date,
  motivo           text check (motivo is null or length(btrim(motivo)) between 10 and 1000),
  autor            text not null,
  registrado_en    timestamptz not null default clock_timestamp(),
  clave_envio      text unique check (clave_envio is null or clave_envio ~ '^[A-Za-z0-9_-]{8,80}$'),
  check (cantidad_kg = case unidad when 't' then cantidad * 1000 else cantidad end * case tipo when 'uso' then -1 when 'ajuste' then sign(cantidad_kg) else 1 end),
  check ((tipo = 'uso') = (para_que is not null)),
  check (tipo <> 'uso' or cantidad > 0),
  check (tipo <> 'entrada' or cantidad > 0),
  check (tipo not in ('inventario_inicial', 'ajuste') or motivo is not null),
  check (tipo = 'entrada' or (proveedor is null and remision is null and lote_fabricante is null and vence is null))
);
create index ix_qmov_quimico on tecnica.quimico_movimientos (quimico_id, id);
create index ix_qmov_dia on tecnica.quimico_movimientos (dia, planta_id) where tipo = 'uso';
comment on table tecnica.quimico_movimientos is 'Corte 7a (§29): movimientos de la bodega de químicos de planta, en kg. Solo inserción.';

create view tecnica.v_quimico_saldo as
select q.id as quimico_id, q.codigo, q.nombre,
       i.id as inventario_id, i.dia as inventario_dia, i.cantidad_kg as inventario_kg,
       case when i.id is null then null
            else i.cantidad_kg + coalesce((select sum(m.cantidad_kg) from tecnica.quimico_movimientos m where m.quimico_id = q.id and m.id > i.id and m.tipo <> 'inventario_inicial'), 0) end as saldo_kg
  from tecnica.quimicos q
  left join lateral (select m.id, m.dia, m.cantidad_kg from tecnica.quimico_movimientos m where m.quimico_id = q.id and m.tipo = 'inventario_inicial' order by m.id desc limit 1) i on true
 where q.codigo <> 'otro';

create table tecnica.quimico_parametros (
  clave       text primary key check (clave ~ '^[a-z][a-z0-9_]{2,40}$'),
  valor       numeric not null,
  minimo      numeric not null,
  maximo      numeric not null,
  descripcion text not null,
  check (valor between minimo and maximo)
);
insert into tecnica.quimico_parametros values
  ('marca_esperado_usado', 1, 0, 1, 'Marca de esperado contra usado encendida (1) o apagada (0). §29: encendida'),
  ('desvio_pct', 25, 1, 500, 'La marca sale si lo usado se aparta de lo esperado en más de este porcentaje'),
  ('dias_atras_uso', 7, 0, 31, 'Un uso se registra hasta estos días atrás'),
  ('dias_atras_entrada', 7, 0, 31, 'Una entrada se registra hasta estos días atrás'),
  ('max_bytes_ficha', 5242880, 100000, 5242880, 'Tamaño máximo del PDF de la ficha técnica (bytes)');

do $$
begin
  execute 'create trigger t_solo_agregar before update or delete on tecnica.quimico_ficha_eventos for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on tecnica.quimico_ficha_eventos for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar before update or delete on tecnica.quimico_movimientos for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on tecnica.quimico_movimientos for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_no_borrar before delete on tecnica.quimico_parametros for each row execute function tecnica.f_solo_agregar()';
  execute 'alter table tecnica.quimico_ficha_eventos enable row level security';
  execute 'alter table tecnica.quimico_ficha_preparaciones enable row level security';
  execute 'alter table tecnica.quimico_movimientos enable row level security';
  execute 'alter table tecnica.quimico_parametros enable row level security';
end $$;

-- La ficha de los químicos que ya existen, sin PDF todavía (alta «migración»: el supervisor sube el PDF y fija la dosis desde el Dashboard PTAP).
insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, potabilizacion, motivo, autor)
select q.id, 'potabilizacion', q.codigo in ('pac', 'cloro_gaseoso'), 'Corte 7a (§29): PAC y cloro gaseoso de potabilización; hipoclorito de calcio para limpieza', 'migracion@tecnica_corte7a'
  from tecnica.quimicos q where q.codigo <> 'otro';

-- ---------------------------------------------------------------------
-- 4. BUCKET de planta para la ficha técnica en PDF (y, en el 7b, la foto de la remisión). Privado; sin políticas: todo con URL firmada desde la Edge.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('tecnica-evidencias', 'tecnica-evidencias', false, 5242880, array['application/pdf', 'image/jpeg'])
on conflict (id) do nothing;      -- si una reversa lo dejó (Storage no deja borrarlo por SQL), se reutiliza vacío
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 26 — FUNCIONES NUEVAS DE QUÍMICOS (planta; §29)
--   Supervisor de planta y administrador (tecnica.f_autorizar_supervision): catálogo y saldo, historial, preparar la subida del PDF de la ficha técnica,
--   crear un químico, cambiar su dosis óptima / «de potabilización» / ficha / activo, inventario inicial, ajuste y la comparación de esperado contra usado.
--   Captura (tecnica.f_autorizar_captura con 'entrada_quimicos' o 'uso_quimicos'): formulario, entrada (t o kg) y uso (guarda la dosis óptima vigente).
--   El operador NO ve el saldo. Las rutas de Storage no salen al navegador: la Edge las cambia por URL firmadas.
-- =====================================================================
create function tecnica.f_qparam(p_clave text) returns numeric language sql stable set search_path = tecnica, pg_temp as $$
  select valor from tecnica.quimico_parametros where clave = p_clave $$;

create function tecnica.f_quimico_por_codigo(p_codigo text) returns tecnica.quimicos language plpgsql stable set search_path = tecnica, pg_temp as $$
declare q tecnica.quimicos;
begin
  select * into q from tecnica.quimicos where codigo = lower(btrim(coalesce(p_codigo, ''))) and codigo <> 'otro';
  if not found then perform tecnica.f_error('Ese químico no existe', 'P0002'); end if;
  return q;
end $$;

-- El PDF de la ficha: preparado por esta persona y ya subido a Storage (PDF, tamaño tope). Devuelve sus bytes.
create function tecnica.f_ficha_subida(p_ruta text, p_email text) returns bigint language plpgsql stable security definer set search_path = tecnica, storage, pg_temp as $$
declare v_b bigint; v_m text;
begin
  if p_ruta is null or not exists (select 1 from tecnica.quimico_ficha_preparaciones where ruta = p_ruta and autor = p_email) then
    perform tecnica.f_error('Suba primero el PDF de la ficha técnica');
  end if;
  select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_b, v_m from storage.objects o where o.bucket_id = 'tecnica-evidencias' and o.name = p_ruta;
  if not found then perform tecnica.f_error('El PDF de la ficha técnica no terminó de subir: intente de nuevo'); end if;
  if v_m is distinct from 'application/pdf' then perform tecnica.f_error('La ficha técnica debe ser un PDF'); end if;
  if v_b > tecnica.f_qparam('max_bytes_ficha') then perform tecnica.f_error('El PDF de la ficha técnica pasa del tamaño permitido'); end if;
  return v_b;
end $$;

-- Dosis óptima vigente de un químico en un momento (la del último evento hasta entonces).
create function tecnica.f_dosis_optima_en(p_quimico bigint, p_hasta timestamptz) returns numeric language sql stable set search_path = tecnica, pg_temp as $$
  select e.dosis_optima_ppm from tecnica.quimico_ficha_eventos e where e.quimico_id = p_quimico and e.dosis_optima_ppm is not null and e.creado_en <= p_hasta order by e.id desc limit 1 $$;

-- ---------- Catálogo y saldo (supervisor) ----------
create function public.geoportal_tec_quimicos_catalogo(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante);
begin
  return jsonb_build_object(
    'quimicos', coalesce((select jsonb_agg(jsonb_build_object('codigo', v.codigo, 'nombre', v.nombre, 'rol', v.rol, 'activo', v.activo, 'dosis_optima_ppm', v.dosis_optima_ppm,
                                 'potabilizacion', v.potabilizacion, 'ficha_ruta', v.ficha_ruta, 'ficha_en', v.ficha_en,
                                 'saldo_kg', s.saldo_kg, 'inventario_dia', s.inventario_dia,
                                 'ultimo_movimiento', (select max(m.registrado_en) from tecnica.quimico_movimientos m where m.quimico_id = v.quimico_id))
                               order by v.activo desc, v.potabilizacion desc, v.nombre)
                            from tecnica.v_quimico_vigente v join tecnica.v_quimico_saldo s on s.quimico_id = v.quimico_id), '[]'::jsonb),
    'parametros', (select jsonb_object_agg(clave, valor) from tecnica.quimico_parametros),
    'puede_editar', true);
end $$;

create function public.geoportal_tec_quimico_historial(p_solicitante text, p_codigo text) returns jsonb
language plpgsql stable security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo);
begin
  return jsonb_build_object('codigo', q.codigo, 'nombre', q.nombre,
    'eventos', coalesce((select jsonb_agg(jsonb_build_object('tipo', e.tipo, 'dosis_optima_ppm', e.dosis_optima_ppm, 'potabilizacion', e.potabilizacion, 'activo', e.activo,
                                 'ficha_ruta', e.ficha_ruta, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en) order by e.id desc)
                           from tecnica.quimico_ficha_eventos e where e.quimico_id = q.id), '[]'::jsonb),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'dia', m.dia, 'cantidad', m.cantidad, 'unidad', m.unidad, 'cantidad_kg', m.cantidad_kg,
                                 'planta', (select p.codigo from tecnica.plantas p where p.id = m.planta_id), 'para_que', m.para_que, 'dosis_optima_ppm', m.dosis_optima_ppm,
                                 'proveedor', m.proveedor, 'remision', m.remision, 'lote', m.lote_fabricante, 'vence', m.vence, 'motivo', m.motivo, 'autor', m.autor,
                                 'registrado_en', m.registrado_en) order by m.id desc)
                               from (select * from tecnica.quimico_movimientos m where m.quimico_id = q.id order by m.id desc limit 100) m), '[]'::jsonb));
end $$;

-- ---------- PDF de la ficha técnica: la ruta donde se sube (la Edge firma la subida) ----------
create function public.geoportal_tec_quimico_ficha_preparar(p_solicitante text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_ruta text;
begin
  v_ruta := 'quimicos/' || to_char(clock_timestamp() at time zone 'America/Bogota', 'YYYY-MM') || '/' || gen_random_uuid() || '.pdf';
  insert into tecnica.quimico_ficha_preparaciones (ruta, autor) values (v_ruta, v_email);
  return jsonb_build_object('ruta', v_ruta, 'max_bytes', tecnica.f_qparam('max_bytes_ficha'), 'tipo_mime', 'application/pdf');
end $$;

-- ---------- Crear un químico (§29): nombre (identidad), rol, de potabilización, dosis óptima (obligatoria si es de potabilización) y el PDF (obligatorio) ----------
create function public.geoportal_tec_quimico_crear(p_solicitante text, p_nombre text, p_rol text, p_potabilizacion boolean, p_dosis_optima numeric, p_ficha_ruta text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_nom text := regexp_replace(btrim(coalesce(p_nombre, '')), '\s+', ' ', 'g');
        v_base text; v_cod text; v_n integer := 1; v_id bigint; v_bytes bigint; v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if length(v_nom) < 2 or length(v_nom) > 100 then perform tecnica.f_error('Escriba el nombre del químico (2 a 100 caracteres)'); end if;
  if coalesce(p_rol, '') not in ('coagulante', 'desinfectante', 'auxiliar') then perform tecnica.f_error('Elija para qué sirve: coagulante, desinfectante u otro uso (auxiliar)'); end if;
  if p_potabilizacion is null then perform tecnica.f_error('Diga si es de potabilización'); end if;
  if p_potabilizacion and p_dosis_optima is null then perform tecnica.f_error('Un químico de potabilización lleva su dosis óptima (ppm)'); end if;
  if p_dosis_optima is not null and (p_dosis_optima <= 0 or p_dosis_optima > 1000) then perform tecnica.f_error('La dosis óptima va de más de 0 a 1.000 ppm'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  if exists (select 1 from tecnica.quimicos where lower(translate(nombre, 'áéíóúÁÉÍÓÚñÑ', 'aeiouAEIOUnN')) = lower(translate(v_nom, 'áéíóúÁÉÍÓÚñÑ', 'aeiouAEIOUnN'))) then
    perform tecnica.f_error('Ya hay un químico con ese nombre (si está desactivado, actívelo en vez de crear otro)', '55000');
  end if;
  v_bytes := tecnica.f_ficha_subida(p_ficha_ruta, v_email);
  perform pg_advisory_xact_lock(hashtext('tecnica.quimicos.alta'));
  v_base := left(trim(both '_' from regexp_replace(lower(translate(v_nom, 'áéíóúÁÉÍÓÚñÑüÜ', 'aeiouAEIOUnNuU')), '[^a-z0-9]+', '_', 'g')), 26);
  if v_base !~ '^[a-z]' then v_base := 'q_' || v_base; end if;
  v_cod := v_base;
  while exists (select 1 from tecnica.quimicos where codigo = v_cod) loop v_n := v_n + 1; v_cod := v_base || '_' || v_n; end loop;
  insert into tecnica.quimicos (codigo, nombre, rol, pide_nombre) values (v_cod, v_nom, p_rol, false) returning id into v_id;
  insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, dosis_optima_ppm, potabilizacion, activo, ficha_ruta, ficha_bytes, motivo, autor)
  values (v_id, 'alta', p_dosis_optima, p_potabilizacion, true, p_ficha_ruta, v_bytes, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'tec_quimico_crear', v_cod, jsonb_build_object('nombre', v_nom, 'rol', p_rol, 'potabilizacion', p_potabilizacion, 'dosis_optima_ppm', p_dosis_optima), null);
  return jsonb_build_object('codigo', v_cod, 'nombre', v_nom);
end $$;

-- ---------- Cambiar lo que sí cambia (§29), cada cosa con su evento y el mismo motivo. La dosis óptima exige un PDF nuevo. ----------
create function public.geoportal_tec_quimico_fijar(p_solicitante text, p_codigo text, p_cambios jsonb, p_ficha_ruta text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo); v tecnica.v_quimico_vigente%rowtype;
        c jsonb := coalesce(p_cambios, '{}'::jsonb); v_mot text := btrim(coalesce(p_motivo, '')); v_bytes bigint; v_hechos text[] := '{}'; v_dosis numeric; v_ficha_usada boolean := false;
begin
  if jsonb_typeof(c) <> 'object' or exists (select 1 from jsonb_object_keys(c) k where k not in ('dosis_optima_ppm', 'potabilizacion', 'activo')) then
    perform tecnica.f_error('Esos cambios no corresponden: solo dosis óptima, de potabilización y activo (la identidad no se cambia)');
  end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  perform pg_advisory_xact_lock(hashtext('tecnica.quimico.' || q.codigo));
  select * into v from tecnica.v_quimico_vigente where quimico_id = q.id;
  if p_ficha_ruta is not null then v_bytes := tecnica.f_ficha_subida(p_ficha_ruta, v_email); end if;
  if c ? 'dosis_optima_ppm' then
    if jsonb_typeof(c -> 'dosis_optima_ppm') <> 'number' then perform tecnica.f_error('La dosis óptima es un número en ppm'); end if;
    v_dosis := (c ->> 'dosis_optima_ppm')::numeric;
    if v_dosis <= 0 or v_dosis > 1000 then perform tecnica.f_error('La dosis óptima va de más de 0 a 1.000 ppm'); end if;
    if v_dosis is distinct from v.dosis_optima_ppm then
      if p_ficha_ruta is null then perform tecnica.f_error('Para cambiar la dosis óptima suba el PDF de la ficha técnica'); end if;
      insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, dosis_optima_ppm, ficha_ruta, ficha_bytes, motivo, autor) values (q.id, 'dosis_optima', v_dosis, p_ficha_ruta, v_bytes, v_mot, v_email);
      v_hechos := v_hechos || 'dosis_optima'::text; v_ficha_usada := true;
    end if;
  end if;
  if c ? 'potabilizacion' then
    if jsonb_typeof(c -> 'potabilizacion') <> 'boolean' then perform tecnica.f_error('«De potabilización» es sí o no'); end if;
    if (c ->> 'potabilizacion')::boolean is distinct from v.potabilizacion then
      if (c ->> 'potabilizacion')::boolean and coalesce(v_dosis, v.dosis_optima_ppm) is null then perform tecnica.f_error('Para marcarlo de potabilización fije también su dosis óptima'); end if;
      insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, potabilizacion, motivo, autor) values (q.id, 'potabilizacion', (c ->> 'potabilizacion')::boolean, v_mot, v_email);
      v_hechos := v_hechos || 'potabilizacion'::text;
    end if;
  end if;
  if c ? 'activo' then
    if jsonb_typeof(c -> 'activo') <> 'boolean' then perform tecnica.f_error('Activo es sí o no'); end if;
    if (c ->> 'activo')::boolean is distinct from q.activo then
      update tecnica.quimicos set activo = (c ->> 'activo')::boolean where id = q.id;
      insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, activo, motivo, autor) values (q.id, 'activo', (c ->> 'activo')::boolean, v_mot, v_email);
      v_hechos := v_hechos || 'activo'::text;
    end if;
  end if;
  if p_ficha_ruta is not null and not v_ficha_usada then      -- solo una versión nueva de la ficha (sin cambiar la dosis)
    insert into tecnica.quimico_ficha_eventos (quimico_id, tipo, ficha_ruta, ficha_bytes, motivo, autor) values (q.id, 'ficha', p_ficha_ruta, v_bytes, v_mot, v_email);
    v_hechos := v_hechos || 'ficha'::text;
  end if;
  if cardinality(v_hechos) = 0 then perform tecnica.f_error('No hay cambios que guardar'); end if;
  perform tecnica.f_auditar(v_email, 'tec_quimico_fijar', q.codigo, jsonb_build_object('cambios', to_jsonb(v_hechos), 'nuevo', c, 'motivo', v_mot), null);
  return jsonb_build_object('codigo', q.codigo, 'cambios', to_jsonb(v_hechos));
end $$;

-- ---------- Inventario inicial y ajuste (supervisor, con motivo) ----------
create function public.geoportal_tec_quimico_inventario(p_solicitante text, p_codigo text, p_cantidad numeric, p_unidad text, p_corte date, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo); v_id bigint;
        v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
begin
  if p_cantidad is null or p_cantidad < 0 or p_cantidad > 1000000 then perform tecnica.f_error('La cantidad contada va de 0 a 1.000.000'); end if;
  if coalesce(p_unidad, '') not in ('kg', 't') then perform tecnica.f_error('La unidad es kg o toneladas'); end if;
  if p_corte is null or p_corte > v_hoy or p_corte < v_hoy - 31 then perform tecnica.f_error('La fecha del conteo es de hoy o de hasta 31 días atrás'); end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más): por ejemplo, «conteo físico de la bodega»'); end if;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor)
  values ('inventario_inicial', q.id, p_cantidad, p_unidad, case p_unidad when 't' then p_cantidad * 1000 else p_cantidad end, p_corte, btrim(p_motivo), v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_inventario', q.codigo, jsonb_build_object('kg', case p_unidad when 't' then p_cantidad * 1000 else p_cantidad end, 'corte', p_corte), null);
  return jsonb_build_object('movimiento_id', v_id, 'saldo_kg', (select saldo_kg from tecnica.v_quimico_saldo where quimico_id = q.id));
end $$;

create function public.geoportal_tec_quimico_ajuste(p_solicitante text, p_codigo text, p_kg numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); q tecnica.quimicos := tecnica.f_quimico_por_codigo(p_codigo); v_id bigint;
begin
  if p_kg is null or p_kg = 0 or abs(p_kg) > 1000000 then perform tecnica.f_error('El ajuste es un número de kg distinto de 0 (negativo si falta)'); end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then perform tecnica.f_error('Escriba el motivo del ajuste (10 caracteres o más)'); end if;
  if not exists (select 1 from tecnica.quimico_movimientos where quimico_id = q.id and tipo = 'inventario_inicial') then
    perform tecnica.f_error('Primero cargue el inventario inicial de este químico', '55000');
  end if;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, motivo, autor)
  values ('ajuste', q.id, abs(p_kg), 'kg', p_kg, (clock_timestamp() at time zone 'America/Bogota')::date, btrim(p_motivo), v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_ajuste', q.codigo, jsonb_build_object('kg', p_kg), null);
  return jsonb_build_object('movimiento_id', v_id, 'saldo_kg', (select saldo_kg from tecnica.v_quimico_saldo where quimico_id = q.id));
end $$;

-- ---------- Captura: formulario, entrada y uso (las pantallas del operador llegan en el 7b) ----------
create function public.geoportal_tec_quimicos_formulario(p_solicitante text, p_formulario text) returns jsonb
language plpgsql stable security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text;
begin
  if coalesce(p_formulario, '') not in ('entrada_quimicos', 'uso_quimicos') then perform tecnica.f_error('Ese formulario no es de químicos'); end if;
  v_email := tecnica.f_autorizar_captura(p_solicitante, p_formulario);
  return jsonb_build_object('formulario', p_formulario, 'hoy', (clock_timestamp() at time zone 'America/Bogota')::date,
    'unidades', '["t", "kg"]'::jsonb,      -- David (16-nov): la entrada va en toneladas o kg; nunca por cilindros ni tanques
    'dias_atras', tecnica.f_qparam(case p_formulario when 'uso_quimicos' then 'dias_atras_uso' else 'dias_atras_entrada' end),
    'quimicos', coalesce((select jsonb_agg(jsonb_build_object('codigo', v.codigo, 'nombre', v.nombre, 'potabilizacion', v.potabilizacion) order by v.potabilizacion desc, v.nombre)
                            from tecnica.v_quimico_vigente v where v.activo), '[]'::jsonb),
    'plantas', coalesce((select jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre) order by p.nombre) from tecnica.plantas p where p.activa), '[]'::jsonb),
    'para_que', case when p_formulario = 'uso_quimicos' then '["dosificacion", "limpieza", "otro"]'::jsonb end);
end $$;

create function tecnica.f_dia_movimiento(p_dia date, p_dias_atras numeric) returns date language plpgsql stable set search_path = tecnica, pg_temp as $$
declare v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
begin
  if p_dia is null then return v_hoy; end if;
  if p_dia > v_hoy then perform tecnica.f_error('El día no puede ser futuro'); end if;
  if p_dia < v_hoy - p_dias_atras::integer then perform tecnica.f_error(format('Se registra hasta %s días atrás', p_dias_atras::integer)); end if;
  return p_dia;
end $$;

-- Entrada: se recibe en toneladas (o kg) y se guarda en kg. Reintento con la misma clave: devuelve lo guardado.
create function public.geoportal_tec_quimico_entrada(p_solicitante text, p_datos jsonb, p_clave text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'entrada_quimicos'); d jsonb := coalesce(p_datos, '{}'::jsonb); q tecnica.quimicos; v_id bigint;
        v_cant numeric; v_vence date; m tecnica.quimico_movimientos%rowtype;
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
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, lote_fabricante, vence, autor, clave_envio)
  values ('entrada', q.id, v_cant, d ->> 'unidad', case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end,
          tecnica.f_dia_movimiento((d ->> 'dia')::date, tecnica.f_qparam('dias_atras_entrada')),
          nullif(btrim(d ->> 'proveedor'), ''), nullif(btrim(d ->> 'remision'), ''), nullif(btrim(d ->> 'lote'), ''), v_vence, v_email, p_clave)
  returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_entrada', q.codigo, jsonb_build_object('movimiento_id', v_id), null);
  return jsonb_build_object('movimiento_id', v_id, 'cantidad_kg', case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end, 'repetido', false);
end $$;

-- Uso: en kg (o t), con la planta (obligatoria si es para dosificar) y para qué. Guarda la dosis óptima vigente (§29: la comparación no cambia hacia atrás).
create function public.geoportal_tec_quimico_uso(p_solicitante text, p_datos jsonb, p_clave text) returns jsonb
language plpgsql security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_captura(p_solicitante, 'uso_quimicos'); d jsonb := coalesce(p_datos, '{}'::jsonb); q tecnica.quimicos; v_id bigint;
        v_cant numeric; v_planta bigint; v_dosis numeric; m tecnica.quimico_movimientos%rowtype;
begin
  if p_clave is not null then
    select * into m from tecnica.quimico_movimientos where clave_envio = p_clave;
    if found then
      if m.autor <> v_email then perform tecnica.f_error('Esa clave de envío no es suya'); end if;
      return jsonb_build_object('movimiento_id', m.id, 'cantidad_kg', m.cantidad_kg, 'dosis_optima_ppm', m.dosis_optima_ppm, 'repetido', true);
    end if;
  end if;
  q := tecnica.f_quimico_por_codigo(d ->> 'quimico');
  if not q.activo then perform tecnica.f_error('Ese químico está desactivado'); end if;
  if coalesce(d ->> 'para_que', '') not in ('dosificacion', 'limpieza', 'otro') then perform tecnica.f_error('Diga para qué se usó: dosificación, limpieza u otro'); end if;
  if jsonb_typeof(d -> 'cantidad') <> 'number' then perform tecnica.f_error('Escriba la cantidad usada'); end if;
  v_cant := (d ->> 'cantidad')::numeric;
  if v_cant <= 0 or v_cant > 1000000 then perform tecnica.f_error('La cantidad usada debe ser mayor que 0'); end if;
  if coalesce(d ->> 'unidad', 'kg') not in ('t', 'kg') then perform tecnica.f_error('La unidad es kg o toneladas'); end if;
  if nullif(d ->> 'planta', '') is not null then
    select id into v_planta from tecnica.plantas where codigo = d ->> 'planta' and activa;
    if v_planta is null then perform tecnica.f_error('Esa planta no existe o está inactiva'); end if;
  elsif d ->> 'para_que' = 'dosificacion' then
    perform tecnica.f_error('Para dosificar, elija la planta');
  end if;
  select dosis_optima_ppm into v_dosis from tecnica.v_quimico_vigente where quimico_id = q.id;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, planta_id, para_que, cantidad, unidad, cantidad_kg, dia, dosis_optima_ppm, autor, clave_envio)
  values ('uso', q.id, v_planta, d ->> 'para_que', v_cant, coalesce(d ->> 'unidad', 'kg'), - (case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end),
          tecnica.f_dia_movimiento((d ->> 'dia')::date, tecnica.f_qparam('dias_atras_uso')), v_dosis, v_email, p_clave)
  returning id into v_id;
  perform tecnica.f_auditar(v_email, 'tec_quimico_uso', q.codigo, jsonb_build_object('movimiento_id', v_id), null);
  return jsonb_build_object('movimiento_id', v_id, 'cantidad_kg', -(case d ->> 'unidad' when 't' then v_cant * 1000 else v_cant end), 'dosis_optima_ppm', v_dosis, 'repetido', false);
end $$;

-- ---------- Esperado contra usado (supervisor), por planta, día y químico de potabilización ----------
-- Volumen del día = promedio del caudal de ingreso Qi (L/s, Entrada, sin excluidos) × 86,4 (m³ por L/s en un día).
-- Esperado (kg) = dosis óptima (ppm = g/m³) × volumen / 1.000. La dosis es la que guardaron los usos de ese día (§29: no cambia hacia atrás); sin usos, la vigente ese día.
-- Usado (kg) = los usos «dosificación» de ese químico en esa planta y ese día. La marca sale si se aparta más de desvio_pct. Solo marca: no rechaza nada.
create function public.geoportal_tec_quimicos_comparacion(p_solicitante text, p_desde date, p_hasta date) returns jsonb
language plpgsql stable security definer set search_path = public, tecnica, pg_temp as $$
declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        v_desde date := coalesce(p_desde, v_hoy - 13); v_hasta date := coalesce(p_hasta, v_hoy); v_pct numeric := tecnica.f_qparam('desvio_pct'); v_on boolean := tecnica.f_qparam('marca_esperado_usado') = 1;
begin
  if v_desde > v_hasta or v_hasta > v_hoy or v_hasta - v_desde > 92 then perform tecnica.f_error('El rango de fechas es de hasta 3 meses y hasta hoy'); end if;
  return jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'desvio_pct', v_pct, 'marca_activa', v_on,
    'filas', coalesce((
      select jsonb_agg(jsonb_build_object('dia', x.dia, 'planta', x.planta, 'planta_nombre', x.planta_nombre, 'quimico', x.codigo, 'quimico_nombre', x.nombre,
               'qi_lps', round(x.qi, 1), 'volumen_m3', round(x.qi * 86.4), 'dosis_optima_ppm', x.dosis,
               'esperado_kg', round(x.dosis * x.qi * 86.4 / 1000, 1), 'usado_kg', round(x.usado, 1),
               'desvio_pct', case when x.dosis * x.qi > 0 then round((x.usado - x.dosis * x.qi * 86.4 / 1000) / (x.dosis * x.qi * 86.4 / 1000) * 100, 1) end,
               'marca', v_on and x.dosis * x.qi > 0 and abs(x.usado - x.dosis * x.qi * 86.4 / 1000) > (x.dosis * x.qi * 86.4 / 1000) * v_pct / 100)
             order by x.dia desc, x.planta, x.codigo)
        from (select d.dia, p.codigo as planta, p.nombre as planta_nombre, v.codigo, v.nombre, qi.qi,
                     coalesce((select m.dosis_optima_ppm from tecnica.quimico_movimientos m where m.tipo = 'uso' and m.para_que = 'dosificacion' and m.quimico_id = v.quimico_id
                                and m.planta_id = p.id and m.dia = d.dia and m.dosis_optima_ppm is not null order by m.id desc limit 1),
                              tecnica.f_dosis_optima_en(v.quimico_id, ((d.dia + 1)::timestamp at time zone 'America/Bogota'))) as dosis,
                     coalesce((select -sum(m.cantidad_kg) from tecnica.quimico_movimientos m where m.tipo = 'uso' and m.para_que = 'dosificacion' and m.quimico_id = v.quimico_id
                                and m.planta_id = p.id and m.dia = d.dia), 0) as usado
                from generate_series(v_desde, v_hasta, interval '1 day') d0(t) cross join lateral (select d0.t::date as dia) d
                cross join tecnica.plantas p
                cross join tecnica.v_quimico_vigente v
                cross join lateral (select avg(r.valor) as qi from tecnica.v_registros_estado r
                                     where r.formulario::text = 'entrada' and r.planta_id = p.id and r.fecha_muestra = d.dia and not r.excluido
                                       and r.variable_id = (select id from tecnica.variables where codigo = 'caudal_qi')) qi
               where p.activa and v.potabilizacion and qi.qi is not null) x
       where x.dosis is not null or x.usado > 0), '[]'::jsonb));
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 6c con cambios exactos, aplicados una sola vez (respuestas de David al 6b y al 6c):
--   · redes.f_estado_contrato: suspendido y cortado como estados propios;
--   · geoportal_redes_contrato_tarjeta: nombre y dirección solo para el administrador y el supervisor de distribución; «datos_personales» en la respuesta;
--   · redes.f_funciones_sin_where: cubre también public.geoportal_tec_* (las RPC de planta y de químicos);
--   · geoportal_redes_geovisor: «contratos_corte», la fecha del último corte de la cartera (nota pequeña de la capa de contratos).
-- =====================================================================
-- redes.f_estado_contrato(text)
CREATE OR REPLACE FUNCTION redes.f_estado_contrato(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select case when nullif(btrim(coalesce(p, '')), '') is null then 'sin_dato' when upper(btrim(p)) like 'RETIR%' then 'retirado'
              when upper(btrim(p)) like 'ACTIV%' then 'activo'
              when upper(btrim(p)) like 'SUSP%' then 'suspendido' when upper(btrim(p)) like 'CORT%' then 'cortado' else 'otro' end $function$;

-- public.geoportal_redes_contrato_tarjeta(text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_contrato_tarjeta(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'bi_interno', 'pg_temp'
AS $function$
declare a record; cs record; pr record; f record; v_c text := btrim(coalesce(p_contrato, '')); v_personal boolean;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;
  -- Corte 7a (respuesta 1 de David al 6b): nombre y dirección solo para el administrador y el supervisor de distribución (su permiso, o área distribución o las dos)
  v_personal := a.admin or public.geoportal_puede(a.email, 'dashboard_redes') or coalesce(redes.f_area(a.email) in ('distribucion', 'ambas'), false);
  if v_c !~ '^[0-9]{1,12}$' then perform tecnica.f_error('Escriba solo los números del contrato'); end if;
  if v_c in ('0', '99999999') or not exists (select 1 from public.catastro_valledupar cv where cv.cod_usuario = v_c and cv.geom is not null) then
    perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002');
  end if;
  select s.nombre, s.estado, s.categoria, s.direccion, s.barrio, s.periodo_carga into cs
    from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select cv.direccion, cv.barrio into pr from public.catastro_valledupar cv where cv.cod_usuario = v_c order by cv.id limit 1;
  select fc.periodo_ultimo, fc.uso, fc.consumo_meses, fc.cons_prom, fc.meses_con_lectura, fc.medidor_anios into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  -- la lectura queda registrada: quién, cuándo y qué contrato (NUNCA el nombre ni la dirección)
  perform tecnica.f_auditar(a.email, 'redes_contrato_tarjeta', v_c, jsonb_build_object('datos', case when v_personal then 'nombre, dirección y barrio' else 'sin nombre ni dirección' end, 'desde', 'geovisor'), p_ip);
  return jsonb_build_object(
    'contrato', v_c,
    'estado', redes.f_estado_contrato(cs.estado), 'estado_texto', nullif(btrim(cs.estado), ''),
    'uso', redes.f_contrato_uso(f.uso, cs.categoria),
    'consumo', case when f.periodo_ultimo is not null then jsonb_build_object(
        'periodo_ultimo', f.periodo_ultimo, 'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura,
        'meses', (select coalesce(jsonb_agg(jsonb_build_object('periodo', m ->> 'periodo', 'm3', m -> 'm3', 'sin_dato', coalesce((m ->> 'sin_dato')::boolean, false),
                                                               'lectura_real', coalesce((m ->> 'lectura_real')::boolean, false)) order by k), '[]'::jsonb)
                    from jsonb_array_elements(f.consumo_meses) with ordinality x(m, k))) end,
    'medidor_anios', f.medidor_anios,
    'tramo', (select v.codigo from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id where t.contrato = v_c),
    'suscriptor', jsonb_build_object(                                  -- DATO PERSONAL: solo en pantalla
      'nombre', case when v_personal then nullif(btrim(cs.nombre), '') end,
      'direccion', case when v_personal then coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')) end,
      'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), ''))),
    'datos_personales', v_personal,
    'corte', cs.periodo_carga);
end $function$;

-- public.geoportal_redes_geovisor(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare a record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
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
    'contratos_corte', case when a.completo then (select max(s.periodo_carga) from public.cartera_suscripcion s) end,      -- Corte 7a: fecha (AAAAMMDD) del último corte de la cartera
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

-- redes.f_funciones_sin_where()
CREATE OR REPLACE FUNCTION redes.f_funciones_sin_where()
 RETURNS TABLE(funcion text, sentencia text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
  with f as (
    select p.oid::regprocedure::text as funcion,
           regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace in (select n.oid from pg_namespace n where n.nspname in ('redes', 'tecnica'))
            or (p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\_redes\_%' or p.proname like 'geoportal\_tec\_%')))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select s.funcion, left(s.st, 200) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')
   order by 1, 2 $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas y vistas nuevas: nadie de la API. Las 11 RPC nuevas: solo execute a service_role (la Edge geoportal-tecnica). Las funciones internas: nadie.
-- =====================================================================
revoke all on table tecnica.quimico_ficha_eventos, tecnica.quimico_ficha_preparaciones, tecnica.quimico_movimientos, tecnica.quimico_parametros,
                    tecnica.v_quimico_vigente, tecnica.v_quimico_saldo from public, anon, authenticated, service_role;
revoke all on sequence tecnica.quimico_ficha_eventos_id_seq, tecnica.quimico_movimientos_id_seq from public, anon, authenticated, service_role;
revoke all on function tecnica.f_qparam(text), tecnica.f_quimico_por_codigo(text), tecnica.f_ficha_subida(text, text), tecnica.f_dosis_optima_en(bigint, timestamptz),
                       tecnica.f_dia_movimiento(date, numeric), tecnica.f_quimico_identidad() from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_quimic%' and p.proname <> 'geoportal_tec_listar_quimicos' loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@tecnica_corte7a', 'migracion_tecnica_corte7a', null, jsonb_build_object('tablas', jsonb_build_array('tecnica.quimico_ficha_eventos', 'tecnica.quimico_ficha_preparaciones',
        'tecnica.quimico_movimientos', 'tecnica.quimico_parametros'), 'vistas', jsonb_build_array('tecnica.v_quimico_vigente', 'tecnica.v_quimico_saldo'), 'rpc_nuevas', 11,
        'reemplazadas', jsonb_build_array('redes.f_estado_contrato', 'public.geoportal_redes_contrato_tarjeta', 'public.geoportal_redes_geovisor', 'redes.f_funciones_sin_where'), 'base', 'corte 6c', 'bucket', 'tecnica-evidencias'), null);
commit;
