begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 10 — GUARDIA, RESPUESTAS AL 6b Y QUÍMICOS DE PLANTA (catálogo con historial, movimientos, bucket y parámetros)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: §29 de la bitácora (químicos), respuestas de David al 6b (16-nov), plan 02 (Corte 7), 01 sección F y D-17.
-- · Presupone el 6b aplicado (huella del conjunto de funciones de redes) y el paquete vivo «químicos y dosis» (tecnica.quimicos y tecnica.uso_quimicos).
-- · ⚠ redes: se reemplazan 2 funciones del 6b (redes.f_estado_contrato y geoportal_redes_contrato_tarjeta) y se amplía el CHECK de estado de redes.contratos_capa.
-- · ⚠ tecnica.quimicos (viva): se amplía el CHECK de «rol» con «auxiliar», se le agrega un candado de identidad (el nombre no cambia) y una fila (hipoclorito de
--   calcio). tecnica.uso_quimicos (la dosis en ppm) NO se toca.
-- · Bucket nuevo «tecnica-evidencias» (privado, PDF y JPEG, 5 MB), sin políticas: todo por URL firmada desde la Edge, como en redes.
-- =====================================================================
do $$
begin
  if to_regclass('redes.vistas_compartidas') is null then raise exception 'Falta el Corte 6b: aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'fca28bf695d1fcfa153f1113ce821528' then
    raise exception 'Las funciones de redes no son las del Corte 6b (o el Corte 7a ya está aplicado): deténgase y avise';
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
--    (2) un color por estado del contrato: activo, suspendido, cortado, retirado y otro (más «sin dato»). La capa se rehace en la próxima apertura del geovisor.
--    (3) el muestreo se pinta hasta 35 días (parámetro editable), con su evento.
--    (1) nombre y dirección del contrato: en 25 (la RPC de la tarjeta).
-- ---------------------------------------------------------------------
alter table redes.contratos_capa drop constraint contratos_capa_estado_check;
alter table redes.contratos_capa add constraint contratos_capa_estado_check check (estado in ('activo', 'suspendido', 'cortado', 'retirado', 'otro', 'sin_dato'));
update redes.contratos_capa_estado set firma = 'rehacer: estados del Corte 7a' where id = 1;
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
-- cada uno es el texto del 6b con cambios exactos, aplicados una sola vez (respuestas de David al 6b):
--   · redes.f_estado_contrato: suspendido y cortado como estados propios;
--   · geoportal_redes_contrato_tarjeta: nombre y dirección solo para el administrador y el supervisor de distribución; «datos_personales» en la respuesta.
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
declare a record; c redes.contratos_capa%rowtype; cs record; pr record; f record; v_c text := btrim(coalesce(p_contrato, '')); v_personal boolean;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;
  -- Corte 7a (respuesta 1 de David al 6b): nombre y dirección solo para el administrador y el supervisor de distribución (su permiso, o área distribución o las dos)
  v_personal := a.admin or public.geoportal_puede(a.email, 'dashboard_redes') or coalesce(redes.f_area(a.email) in ('distribucion', 'ambas'), false);
  if v_c !~ '^[0-9]{1,12}$' then perform tecnica.f_error('Escriba solo los números del contrato'); end if;
  select * into c from redes.contratos_capa where contrato = v_c;
  if not found then perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002'); end if;
  select s.nombre, s.estado, s.categoria, s.direccion, s.barrio, s.periodo_carga into cs
    from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select cv.direccion, cv.barrio into pr from public.catastro_valledupar cv where cv.cod_usuario = v_c order by cv.id limit 1;
  select fc.periodo_ultimo, fc.uso, fc.consumo_meses, fc.cons_prom, fc.meses_con_lectura, fc.medidor_anios into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  -- la lectura queda registrada: quién, cuándo y qué contrato (NUNCA el nombre ni la dirección)
  perform tecnica.f_auditar(a.email, 'redes_contrato_tarjeta', v_c, jsonb_build_object('datos', case when v_personal then 'nombre, dirección y barrio' else 'sin nombre ni dirección' end, 'desde', 'geovisor'), p_ip);
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
      'nombre', case when v_personal then nullif(btrim(cs.nombre), '') end,
      'direccion', case when v_personal then coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')) end,
      'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), ''))),
    'datos_personales', v_personal,
    'corte', cs.periodo_carga);
end $function$;
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
        'reemplazadas', jsonb_build_array('redes.f_estado_contrato', 'public.geoportal_redes_contrato_tarjeta'), 'bucket', 'tecnica-evidencias'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.tec7.*), sus químicos («ZT7 …»), sus PDF en Storage, sus caudales de Entrada del día y,
-- para la tarjeta del contrato, un contrato de prueba (99000000120x) como la suite viva de Análisis de contrato. Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE TÉCNICA · CORTE 7a … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- prepara la subida de un PDF y lo deja «subido» en Storage (la subida real la hace el navegador con la URL firmada)
create function pg_temp.pdf(p_quien text, p_mime text default 'application/pdf', p_bytes integer default 200000) returns text language plpgsql as $$
declare v_r text := public.geoportal_tec_quimico_ficha_preparar(p_quien) ->> 'ruta';
begin
  insert into storage.objects (bucket_id, name, metadata) values ('tecnica-evidencias', v_r, jsonb_build_object('size', p_bytes, 'mimetype', p_mime));
  return v_r;
end $$;
create function pg_temp.saldo(p_cod text) returns numeric language sql as $$ select saldo_kg from tecnica.v_quimico_saldo where codigo = p_cod $$;
create function pg_temp.fila(p jsonb, p_quimico text, p_planta text) returns jsonb language sql as $$
  select f from jsonb_array_elements(p -> 'filas') f where f ->> 'quimico' = p_quimico and f ->> 'planta' = p_planta and (f ->> 'dia')::date = (clock_timestamp() at time zone 'America/Bogota')::date $$;

do $prueba$
declare
  a text := 'prueba.tec7.adm@emdupar.gov.co'; sv text := 'prueba.tec7.planta@emdupar.gov.co'; sd text := 'prueba.tec7.dist@emdupar.gov.co';
  op text := 'prueba.tec7.op@emdupar.gov.co'; op2 text := 'prueba.tec7.op2@emdupar.gov.co'; sv2 text := 'prueba.tec7.planta2@emdupar.gov.co';
  C1 text := '990000001201';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_r jsonb; v_x jsonb; v_cod text; v_ruta text; v_n integer; v_qi numeric; v_esp numeric;
  v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT7 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values
    (sv, 'ZT7 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos'), (sv2, 'ZT7 Supervisor de planta y distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT7 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT7 Operador', 'consulta', true, 'sin_restriccion', 'todos'),
    (op2, 'ZT7 Operador sin químicos', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'uso_quimicos', a), (op, 'asignar_formulario', 'entrada_quimicos', a);

  -- ===================== 01. Respuestas al 6b =====================
  perform pg_temp.reg('01.01 estados del contrato: SUSPENDIDO, CORTADO, RETIRADO y ACTIVO, cada uno el suyo; otro texto, «otro»',
     redes.f_estado_contrato('SUSPENDIDO') = 'suspendido' and redes.f_estado_contrato(' cortado ') = 'cortado' and redes.f_estado_contrato('RETIRADO') = 'retirado'
     and redes.f_estado_contrato('ACTIVO') = 'activo' and redes.f_estado_contrato('EN TRAMITE') = 'otro' and redes.f_estado_contrato(null) = 'sin_dato');
  perform pg_temp.reg('01.02 el muestreo se pinta hasta 35 días, con su evento', (select valor from redes.parametros where clave = 'geovisor_muestreo_dias') = 35
     and exists (select 1 from redes.parametro_eventos where clave = 'geovisor_muestreo_dias' and despues = 35));
  insert into public.cartera_suscripcion (contrato, estado, identificacion, nombre, correo, telefono, direccion, barrio, categoria, subcategoria, ciclo,
                                          facturas_pendientes, deuda_total, saldo_pendiente, saldo_a_favor, valor_reclamo, saldo_financiado, serial_medidor, ruta, periodo_carga)
  values (C1, 'SUSPENDIDO', 'DOC-PRUEBA-7', 'NOMBRE DE PRUEBA SIETE', null, '3007770000', 'CRA ZT7 1', 'ZT7 BARRIO', '1 Residencial', '2 Estrato 2', '7', 1, 1000, 0, 0, 0, 0, null, '0701', '29991231');
  insert into public.catastro_valledupar (cod_usuario, direccion, barrio, geom) values (C1, 'CRA ZT7 1 CATASTRO', 'ZT7 BARRIO', ST_SetSRID(ST_MakePoint(-73.30, 10.42), 4326));
  perform redes.f_refrescar_contratos_capa();
  perform pg_temp.reg('01.03 la capa de contratos clasifica el suspendido como «suspendido»', (select estado from redes.contratos_capa where contrato = C1) = 'suspendido');
  v_r := public.geoportal_redes_contrato_tarjeta(sv, C1);
  perform pg_temp.reg('01.04 el supervisor de planta ve la tarjeta SIN nombre ni dirección (sí el barrio) y la auditoría lo dice',
     not (v_r ->> 'datos_personales')::boolean and v_r -> 'suscriptor' ->> 'nombre' is null and v_r -> 'suscriptor' ->> 'direccion' is null and v_r -> 'suscriptor' ->> 'barrio' = 'ZT7 BARRIO'
     and v_r::text not like '%NOMBRE DE PRUEBA%' and v_r::text not like '%CRA ZT7%'
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta' and email = sv and referencia = C1 and detalle ->> 'datos' = 'sin nombre ni dirección'), v_r::text);
  v_r := public.geoportal_redes_contrato_tarjeta(sd, C1);
  perform pg_temp.reg('01.05 el supervisor de distribución sí ve nombre y dirección', (v_r ->> 'datos_personales')::boolean and v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA SIETE');
  v_r := public.geoportal_redes_contrato_tarjeta(a, C1);
  perform pg_temp.reg('01.06 el administrador también', v_r -> 'suscriptor' ->> 'direccion' = 'CRA ZT7 1 CATASTRO');
  perform public.geoportal_redes_personal_fijar(sd, sv2, 'area', 'ambas', 'ZT7 trabaja en planta y en la red');
  v_r := public.geoportal_redes_contrato_tarjeta(sv2, C1);
  perform pg_temp.reg('01.07 un supervisor de planta con área «las dos» en Personal sí los ve', (v_r ->> 'datos_personales')::boolean and v_r -> 'suscriptor' ->> 'nombre' = 'NOMBRE DE PRUEBA SIETE');

  -- ===================== 02. Catálogo e identidad =====================
  perform pg_temp.reg('02.01 hipoclorito de calcio en el catálogo (auxiliar, no de potabilización); PAC y cloro gaseoso de potabilización',
     (select rol || '|' || potabilizacion from tecnica.v_quimico_vigente where codigo = 'hipoclorito_calcio') = 'auxiliar|false'
     and (select bool_and(potabilizacion) from tecnica.v_quimico_vigente where codigo in ('pac', 'cloro_gaseoso')));
  v_r := public.geoportal_tec_quimicos_catalogo(sv);
  perform pg_temp.reg('02.02 el supervisor de planta ve el catálogo con saldo y parámetros (sin «Otro»)', jsonb_array_length(v_r -> 'quimicos') >= 3
     and not exists (select 1 from jsonb_array_elements(v_r -> 'quimicos') x where x ->> 'codigo' = 'otro') and (v_r -> 'parametros' ->> 'desvio_pct')::numeric = 25
     and (v_r -> 'parametros' ->> 'marca_esperado_usado')::numeric = 1);
  perform pg_temp.err('02.03 el operador no ve el catálogo ni el saldo', format($$select public.geoportal_tec_quimicos_catalogo(%L)$$, op), '42501');
  perform pg_temp.err('02.04 el supervisor de distribución tampoco (químicos es solo de planta)', format($$select public.geoportal_tec_quimicos_catalogo(%L)$$, sd), '42501');
  perform pg_temp.err('02.05 el nombre de un químico no se cambia (identidad)', $$update tecnica.quimicos set nombre = 'Otro nombre' where codigo = 'pac'$$, '55000', 'identidad');
  perform pg_temp.err('02.06 los químicos no se borran', $$delete from tecnica.quimicos where codigo = 'hipoclorito_calcio'$$, '42501');

  -- ===================== 03. Crear un químico (PDF obligatorio) =====================
  v_ruta := public.geoportal_tec_quimico_ficha_preparar(sv) ->> 'ruta';
  perform pg_temp.reg('03.01 preparar la subida da una ruta de PDF en quimicos/AAAA-MM/', v_ruta ~ '^quimicos/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.pdf$', v_ruta);
  perform pg_temp.err('03.02 crear sin que el PDF haya subido', format($$select public.geoportal_tec_quimico_crear(%L, 'ZT7 Coagulante', 'coagulante', true, 20, %L, 'ZT7 coagulante de prueba')$$, sv, v_ruta), '22023', 'no terminó de subir');
  perform pg_temp.err('03.03 crear con un archivo que no es PDF', format($$select public.geoportal_tec_quimico_crear(%L, 'ZT7 Coagulante', 'coagulante', true, 20, %L, 'ZT7 coagulante de prueba')$$, sv, pg_temp.pdf(sv, 'image/jpeg')), '22023', 'PDF');
  perform pg_temp.err('03.04 crear con el PDF que preparó otra persona', format($$select public.geoportal_tec_quimico_crear(%L, 'ZT7 Coagulante', 'coagulante', true, 20, %L, 'ZT7 coagulante de prueba')$$, sv2, pg_temp.pdf(sv)), '22023', 'Suba primero');
  perform pg_temp.err('03.05 de potabilización sin dosis óptima', format($$select public.geoportal_tec_quimico_crear(%L, 'ZT7 Coagulante', 'coagulante', true, null, %L, 'ZT7 coagulante de prueba')$$, sv, pg_temp.pdf(sv)), '22023', 'dosis óptima');
  perform pg_temp.err('03.06 sin PDF no se crea', format($$select public.geoportal_tec_quimico_crear(%L, 'ZT7 Coagulante', 'coagulante', true, 20, null, 'ZT7 coagulante de prueba')$$, sv), '22023', 'Suba primero');
  v_r := public.geoportal_tec_quimico_crear(sv, '  ZT7   Coagulante Ñandú ', 'coagulante', true, 20, pg_temp.pdf(sv), 'ZT7 coagulante de prueba');
  v_cod := v_r ->> 'codigo';
  perform pg_temp.reg('03.07 se crea: código del nombre (sin tildes ni espacios), alta con dosis, potabilización, activo y la ficha; auditado',
     v_cod = 'zt7_coagulante_nandu' and v_r ->> 'nombre' = 'ZT7 Coagulante Ñandú'
     and (select dosis_optima_ppm || '|' || potabilizacion || '|' || activo || '|' || (ficha_ruta is not null) from tecnica.v_quimico_vigente where codigo = v_cod) = '20|true|true|true'
     and exists (select 1 from public.geoportal_auditoria where accion = 'tec_quimico_crear' and referencia = v_cod), v_r::text);
  perform pg_temp.err('03.08 el mismo nombre otra vez (aunque con otra tilde)', format($$select public.geoportal_tec_quimico_crear(%L, 'zt7 coagulante ñandu', 'coagulante', true, 20, %L, 'ZT7 coagulante de prueba')$$, sv, pg_temp.pdf(sv)), '55000', 'Ya hay');
  perform pg_temp.err('03.09 el operador no crea químicos', format($$select public.geoportal_tec_quimico_ficha_preparar(%L)$$, op), '42501');

  -- ===================== 04. Lo que sí cambia, con historial =====================
  perform pg_temp.err('04.01 la dosis óptima no cambia sin un PDF nuevo', format($$select public.geoportal_tec_quimico_fijar(%L, %L, '{"dosis_optima_ppm": 30}', null, 'ZT7 nueva dosis del jar test')$$, sv, v_cod), '22023', 'PDF');
  perform pg_temp.err('04.02 el nombre no se cambia por aquí', format($$select public.geoportal_tec_quimico_fijar(%L, %L, '{"nombre": "Otro"}', null, 'ZT7 cambiar el nombre')$$, sv, v_cod), '22023', 'identidad');
  perform pg_temp.err('04.03 sin motivo no', format($$select public.geoportal_tec_quimico_fijar(%L, %L, '{"activo": false}', null, 'corto')$$, sv, v_cod), '22023', 'motivo');
  perform pg_temp.reg('04.04 una versión nueva de la ficha sola (sin cambiar la dosis)',
     public.geoportal_tec_quimico_fijar(sv, v_cod, '{}', pg_temp.pdf(sv), 'ZT7 el proveedor mandó la ficha nueva') -> 'cambios' = '["ficha"]'::jsonb);
  perform pg_temp.err('04.05 nada que cambiar', format($$select public.geoportal_tec_quimico_fijar(%L, %L, '{"dosis_optima_ppm": 20, "potabilizacion": true}', null, 'ZT7 nada cambia')$$, sv, v_cod), '22023', 'No hay cambios');

  -- ===================== 05. Bodega: inventario inicial, entrada, uso y ajuste (todo en kg) =====================
  perform pg_temp.err('05.01 el ajuste antes del inventario inicial', format($$select public.geoportal_tec_quimico_ajuste(%L, %L, -5, 'ZT7 faltante del conteo')$$, sv, v_cod), '55000', 'inventario inicial');
  perform pg_temp.err('05.02 el operador no carga el inventario inicial', format($$select public.geoportal_tec_quimico_inventario(%L, %L, 2, 't', %L, 'ZT7 conteo físico de bodega')$$, op, v_cod, hoy), '42501');
  v_r := public.geoportal_tec_quimico_inventario(sv, v_cod, 2, 't', hoy - 1, 'ZT7 conteo físico de bodega');
  perform pg_temp.reg('05.03 inventario inicial de 2 t: saldo 2.000 kg', (v_r ->> 'saldo_kg')::numeric = 2000 and pg_temp.saldo(v_cod) = 2000, v_r::text);
  perform pg_temp.err('05.04 el inventario con fecha futura', format($$select public.geoportal_tec_quimico_inventario(%L, %L, 2, 't', %L, 'ZT7 conteo físico de bodega')$$, sv, v_cod, hoy + 1), '22023', 'fecha');
  perform pg_temp.err('05.05 el operador sin el formulario de entrada no registra', format($$select public.geoportal_tec_quimico_entrada(%L, '{"quimico": %s, "cantidad": 1, "unidad": "t"}', null)$$, op2, to_jsonb(v_cod)), '42501');
  v_r := public.geoportal_tec_quimico_entrada(op, jsonb_build_object('quimico', v_cod, 'cantidad', 1.5, 'unidad', 't', 'proveedor', 'ZT7 Proveedor', 'remision', 'R-77', 'lote', 'L-1', 'vence', hoy + 365), 'zt7-entrada-0001');
  perform pg_temp.reg('05.06 entrada de 1,5 t: se guarda como 1.500 kg con proveedor, remisión, lote y vencimiento; saldo 3.500', (v_r ->> 'cantidad_kg')::numeric = 1500 and pg_temp.saldo(v_cod) = 3500
     and (select proveedor || '|' || remision || '|' || lote_fabricante || '|' || unidad || '|' || cantidad from tecnica.quimico_movimientos where id = (v_r ->> 'movimiento_id')::bigint) = 'ZT7 Proveedor|R-77|L-1|t|1.5', v_r::text);
  v_x := public.geoportal_tec_quimico_entrada(op, jsonb_build_object('quimico', v_cod, 'cantidad', 1.5, 'unidad', 't'), 'zt7-entrada-0001');
  perform pg_temp.reg('05.07 el reintento con la misma clave no duplica', (v_x ->> 'repetido')::boolean and pg_temp.saldo(v_cod) = 3500);
  perform pg_temp.err('05.08 la entrada con día futuro', format($$select public.geoportal_tec_quimico_entrada(%L, '{"quimico": %s, "cantidad": 1, "unidad": "t", "dia": %s}', null)$$, op, to_jsonb(v_cod), to_jsonb(hoy + 1)), '22023', 'futuro');
  perform pg_temp.err('05.09 la entrada de hace 20 días (el tope es 7)', format($$select public.geoportal_tec_quimico_entrada(%L, '{"quimico": %s, "cantidad": 1, "unidad": "t", "dia": %s}', null)$$, op, to_jsonb(v_cod), to_jsonb(hoy - 20)), '22023', 'días atrás');
  perform pg_temp.err('05.10 una unidad que no es t ni kg', format($$select public.geoportal_tec_quimico_entrada(%L, '{"quimico": %s, "cantidad": 1, "unidad": "lb"}', null)$$, op, to_jsonb(v_cod)), '22023', 'unidad');
  perform pg_temp.err('05.11 el uso para dosificar sin la planta', format($$select public.geoportal_tec_quimico_uso(%L, '{"quimico": %s, "cantidad": 100, "para_que": "dosificacion"}', null)$$, op, to_jsonb(v_cod)), '22023', 'planta');
  v_r := public.geoportal_tec_quimico_uso(op, jsonb_build_object('quimico', v_cod, 'cantidad', 200, 'unidad', 'kg', 'para_que', 'dosificacion', 'planta', 'huaricha'), 'zt7-uso-0001');
  perform pg_temp.reg('05.12 uso de 200 kg para dosificar en Huaricha: resta del saldo (3.300) y guarda la dosis óptima vigente (20 ppm)',
     (v_r ->> 'cantidad_kg')::numeric = -200 and (v_r ->> 'dosis_optima_ppm')::numeric = 20 and pg_temp.saldo(v_cod) = 3300, v_r::text);
  perform public.geoportal_tec_quimico_uso(op, jsonb_build_object('quimico', 'hipoclorito_calcio', 'cantidad', 5, 'para_que', 'limpieza'), null);
  perform pg_temp.reg('05.13 el hipoclorito para limpieza no pide planta', exists (select 1 from tecnica.quimico_movimientos m join tecnica.quimicos q on q.id = m.quimico_id
     where q.codigo = 'hipoclorito_calcio' and m.para_que = 'limpieza' and m.planta_id is null and m.cantidad_kg = -5));
  v_r := public.geoportal_tec_quimico_ajuste(sv, v_cod, -50, 'ZT7 faltante del conteo semanal');
  perform pg_temp.reg('05.14 ajuste de −50 kg con motivo: saldo 3.250', (v_r ->> 'saldo_kg')::numeric = 3250);
  perform pg_temp.err('05.15 el operador no ajusta', format($$select public.geoportal_tec_quimico_ajuste(%L, %L, 10, 'ZT7 ajuste no permitido')$$, op, v_cod), '42501');
  perform pg_temp.err('05.16 los movimientos no se cambian', $$update tecnica.quimico_movimientos set cantidad = 1$$, '42501');
  perform pg_temp.err('05.17 la regla de la tabla: los kg cuadran con las toneladas', format($$insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, autor)
     select 'entrada', id, 1, 't', 900, current_date, 'x' from tecnica.quimicos where codigo = %L$$, v_cod), '23514');
  v_x := public.geoportal_tec_quimicos_formulario(op, 'uso_quimicos');
  perform pg_temp.reg('05.18 el formulario del operador: químicos activos (sin saldo), plantas, para qué y días atrás',
     exists (select 1 from jsonb_array_elements(v_x -> 'quimicos') x where x ->> 'codigo' = v_cod) and not (v_x::text like '%saldo%') and (v_x ->> 'dias_atras')::numeric = 7
     and v_x -> 'para_que' = '["dosificacion", "limpieza", "otro"]'::jsonb);

  -- ===================== 06. Esperado contra usado (marca encendida) =====================
  insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, valor, fecha_muestra, hora_muestra, autor)
  select gen_random_uuid(), 'entrada', v.id, p.id, 500, hoy, make_time(h, 0, 0), op from tecnica.variables v, tecnica.plantas p, generate_series(0, 2) h where v.codigo = 'caudal_qi' and p.codigo = 'huaricha';
  select avg(r.valor) into v_qi from tecnica.v_registros_estado r join tecnica.plantas p on p.id = r.planta_id
   where r.formulario::text = 'entrada' and p.codigo = 'huaricha' and r.fecha_muestra = hoy and not r.excluido and r.variable_id = (select id from tecnica.variables where codigo = 'caudal_qi');
  v_esp := round(20 * v_qi * 86.4 / 1000, 1);
  -- la dosis óptima cambia DESPUÉS del uso: la comparación de hoy sigue con la que guardó el uso (20)
  perform public.geoportal_tec_quimico_fijar(sv, v_cod, '{"dosis_optima_ppm": 30}', pg_temp.pdf(sv), 'ZT7 nueva dosis del jar test');
  perform pg_temp.reg('04.06 la dosis óptima cambia con su PDF: evento con el antes en el historial', (select dosis_optima_ppm from tecnica.v_quimico_vigente where codigo = v_cod) = 30
     and (select count(*) from tecnica.quimico_ficha_eventos e join tecnica.quimicos q on q.id = e.quimico_id where q.codigo = v_cod and e.tipo in ('alta', 'dosis_optima')) = 2);
  v_r := public.geoportal_tec_quimicos_comparacion(sv, hoy - 2, hoy);
  v_x := pg_temp.fila(v_r, v_cod, 'huaricha');
  perform pg_temp.reg('06.01 hoy en Huaricha: volumen = Qi promedio × 86,4; esperado = 20 ppm (la del uso) × volumen / 1.000; usado 200 kg',
     (v_x ->> 'dosis_optima_ppm')::numeric = 20 and (v_x ->> 'esperado_kg')::numeric = v_esp and (v_x ->> 'usado_kg')::numeric = 200, coalesce(v_x::text, 'sin fila') || ' · esperado ' || v_esp);
  perform pg_temp.reg('06.02 la marca sale si se aparta más del 25 %', (v_x ->> 'marca')::boolean = (abs(200 - v_esp) > v_esp * 0.25) and (v_r ->> 'marca_activa')::boolean);
  perform pg_temp.reg('06.03 la dosis nueva (30) cuenta para un uso nuevo', (public.geoportal_tec_quimico_uso(op, jsonb_build_object('quimico', v_cod, 'cantidad', 10, 'para_que', 'dosificacion', 'planta', 'huaricha'), null) ->> 'dosis_optima_ppm')::numeric = 30);
  perform pg_temp.err('06.04 el operador no ve la comparación', format($$select public.geoportal_tec_quimicos_comparacion(%L, null, null)$$, op), '42501');
  perform pg_temp.err('06.05 un rango de más de 3 meses', format($$select public.geoportal_tec_quimicos_comparacion(%L, %L, %L)$$, sv, hoy - 200, hoy), '22023', '3 meses');

  -- ===================== 07. Desactivar y volver a activar =====================
  v_r := public.geoportal_tec_quimico_fijar(sv, v_cod, '{"activo": false}', null, 'ZT7 se dejó de usar en la planta');
  perform pg_temp.reg('07.01 desactivado con motivo: sale del formulario del operador; queda en el catálogo del supervisor con su historial',
     not (select activo from tecnica.quimicos where codigo = v_cod) and not exists (select 1 from jsonb_array_elements(public.geoportal_tec_quimicos_formulario(op, 'uso_quimicos') -> 'quimicos') x where x ->> 'codigo' = v_cod)
     and exists (select 1 from jsonb_array_elements(public.geoportal_tec_quimicos_catalogo(sv) -> 'quimicos') x where x ->> 'codigo' = v_cod and not (x ->> 'activo')::boolean)
     and jsonb_array_length(public.geoportal_tec_quimico_historial(sv, v_cod) -> 'eventos') >= 4);
  perform pg_temp.err('07.02 un químico desactivado no recibe usos', format($$select public.geoportal_tec_quimico_uso(%L, '{"quimico": %s, "cantidad": 1, "para_que": "otro"}', null)$$, op, to_jsonb(v_cod)), '22023', 'desactivado');
  perform public.geoportal_tec_quimico_fijar(a, v_cod, '{"activo": true}', null, 'ZT7 se volvió a usar');
  perform pg_temp.reg('07.03 el administrador lo reactiva', (select activo from tecnica.quimicos where codigo = v_cod));
  perform pg_temp.reg('07.04 el historial trae eventos y movimientos (sin la ruta del PDF a la vista del operador: el operador no tiene la ruta)',
     jsonb_array_length(public.geoportal_tec_quimico_historial(sv, v_cod) -> 'movimientos') >= 5);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE TÉCNICA · CORTE 7a (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
