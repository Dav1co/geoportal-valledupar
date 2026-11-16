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
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_CORTE_6C}}' then
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
