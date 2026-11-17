-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 10 — GUARDIA Y ESQUEMA (inventario regulatorio: la Valoración Técnica de 2019, Res. CRA 688 de 2014)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code B). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte10_inventario_regulatorio.md (16-nov) y regulatorio/salida_geoportal/LEEME.md.
-- · Presupone el Corte 5d publicado (huella del conjunto de funciones de redes {{MD5_BASE}}).
-- · La valoración va en tablas APARTE, de referencia y de solo inserción, por carga (redes.ref_cargas, conjunto «valoracion»): vale la última no anulada.
--   Es una PROPUESTA de 2019 cuya adopción no está confirmada: así se dice en la ficha y en la conciliación.
-- · El amarre activo → fila también va aparte y por carga (conjunto «val_amarre»): se puede volver a calcular y cargar; la ficha oficial no se toca.
--   Un activo que no está en el amarre vigente (uno nuevo de una inversión) queda «fuera de la valoración 2019».
-- · Las tablas quedan vacías: se llenan con el paquete de carga por psql (carga_val/). Sin datos de personas. Nada se borra.
-- =====================================================================
do $$
begin
  if to_regclass('redes.val_filas') is not null then raise exception 'El Corte 10 ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_BASE}}' then
    raise exception 'Las funciones de redes no son las del Corte 5d publicado (huella {{MD5_BASE}}): deténgase y avise';
  end if;
  if to_regclass('redes.ref_cargas') is null or to_regclass('redes.pm_valvulas') is null or to_regclass('redes.v_ref_carga_vigente') is null then
    raise exception 'Faltan las tablas de referencia del Corte 9a: deténgase y avise';
  end if;
end $$;

-- ---------- 1. La valoración: sus hojas (con los totales) y sus filas ----------
create table redes.val_hojas (
  carga_id           bigint not null references redes.ref_cargas (id),
  hoja               text not null check (hoja in ('acueducto', 'alcantarillado', 'alcantarillado_2')),
  nombre_hoja        text not null check (length(btrim(nombre_hoja)) between 3 and 60),      -- como se llama en el libro: «ALCANTARILLADO (2)»
  servicio           text not null check (servicio in ('acueducto', 'alcantarillado')),
  filas              integer not null check (filas >= 0),
  bcr0               numeric not null check (bcr0 >= 0),      -- el total de la hoja RESUMEN del libro (base de capital regulada)
  valor_total        numeric not null check (valor_total >= 0),
  depreciacion_anual numeric not null check (depreciacion_anual >= 0),
  primary key (carga_id, hoja),
  check ((hoja = 'acueducto') = (servicio = 'acueducto'))
);
comment on table redes.val_hojas is 'Corte 10: hojas de la Valoración Técnica de 2019 (Res. CRA 688 de 2014) con sus totales. Referencia, solo inserción. La hoja de alcantarillado vigente la dice el parámetro valoracion_hoja_alcantarillado.';
create table redes.val_filas (
  carga_id           bigint not null,
  hoja               text not null,
  n                  integer not null check (n >= 1),      -- el «N°» de la fila en su hoja
  nombre             text not null check (length(btrim(nombre)) between 2 and 200),
  subsistema         text,
  actividad          text,
  tipo_activo        text,
  vida_util          numeric check (vida_util is null or vida_util between 1 and 200),      -- años (vida útil regulatoria)
  caracteristica     text,      -- «característica técnica»: en las tuberías, el diámetro en pulgadas
  cantidad           numeric check (cantidad is null or cantidad >= 0),      -- longitud (m), capacidad (L/s, m³) o unidades
  unidad             text check (unidad is null or unidad in ('m', 'un', 'L/s', 'm³')),
  precio_unitario    numeric,
  valor_total        numeric,
  anio_operacion     integer check (anio_operacion is null or anio_operacion between 1900 and 2100),
  fecha_operacion    date,      -- entrada en operación REGULATORIA (no es la fecha de instalación)
  fecha_tarifa       date,      -- inicio de la aplicación tarifaria
  tiempo_operacion   numeric,
  vida_remanente     numeric,   -- la del libro (al inicio de la aplicación tarifaria); «a hoy» se calcula al leer
  valor_remanente    numeric,
  depreciacion_anual numeric,
  clase              text not null check (clase in ('tuberia', 'valvula', 'hidrante', 'puntual', 'terreno', 'otro')),
  material           text,      -- en las tuberías, como lo nombra la valoración: PVC, AC, GRES, CONCRETO…
  diametro_pulg      numeric check (diametro_pulg is null or diametro_pulg > 0),
  nota               text check (nota is null or length(nota) <= 600),      -- lo que dejó el análisis del Plan Maestro (dudas, con qué se amarra)
  primary key (carga_id, hoja, n),
  foreign key (carga_id, hoja) references redes.val_hojas (carga_id, hoja)
);
comment on table redes.val_filas is 'Corte 10: filas de la Valoración Técnica de 2019: activos AGREGADOS (una tubería por material y diámetro con su longitud total). Referencia, solo inserción. Los valores son de la fila, no de un tramo.';

-- ---------- 2. El amarre: cada activo físico con su fila (por carga; se puede recalcular y volver a cargar) ----------
create table redes.val_amarre (
  carga_id     bigint not null references redes.ref_cargas (id),      -- la carga del amarre (conjunto «val_amarre»)
  val_carga_id bigint not null references redes.ref_cargas (id),      -- la carga de la valoración contra la que se amarró
  activo_id    bigint not null references redes.activos (id),
  hoja         text not null check (hoja in ('acueducto', 'alcantarillado', 'alcantarillado_2')),
  n            integer,      -- nulo: el activo no tiene fila en esa hoja
  cantidad     numeric not null check (cantidad >= 0),      -- lo que el activo aporta a la fila: metros (tramos y conductos) o 1 (puntuales)
  situacion    text not null check (situacion in ('con_fila', 'aparte_fuera_servicio', 'aparte_siva', 'proyectado', 'sin_fila')),
  nota         text check (nota is null or length(nota) <= 300),
  check ((n is null) = (situacion in ('proyectado', 'sin_fila'))),
  foreign key (val_carga_id, hoja, n) references redes.val_filas (carga_id, hoja, n)
);
create unique index ux_val_amarre on redes.val_amarre (carga_id, activo_id, hoja, coalesce(n, 0));
create index ix_val_amarre_activo on redes.val_amarre (activo_id, carga_id);
create index ix_val_amarre_fila on redes.val_amarre (carga_id, hoja, n);
comment on table redes.val_amarre is 'Corte 10: amarre de cada activo físico con su fila de la valoración (tramos por material y diámetro; puntuales uno a uno). Por carga: vale la última no anulada. No toca la ficha oficial.';

do $$
declare t text;
begin
  foreach t in array array['val_hojas', 'val_filas', 'val_amarre'] loop
    execute format('alter table redes.%I enable row level security', t);
    execute format('revoke all on table redes.%I from public, anon, authenticated, service_role', t);
    execute format('create trigger t_solo_agregar before update or delete on redes.%I for each row execute function tecnica.f_solo_agregar()', t);
    execute format('create trigger t_solo_agregar_trunc before truncate on redes.%I for each statement execute function tecnica.f_solo_agregar()', t);
  end loop;
end $$;

-- ---------- 3. Parámetros ----------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('valoracion_hoja_alcantarillado', 2, 'hoja', 1, 2,
   'Inventario regulatorio (Corte 10): hoja de alcantarillado de la Valoración Técnica 2019 que vale. 1 = «ALCANTARILLADO» (138.548 millones); 2 = «ALCANTARILLADO (2)» (176.452 millones, la que cuadra con el valor ajustado). La otra queda de referencia'),
  ('valoracion_tolerancia_pct', 2, '%', 0, 50,
   'Inventario regulatorio (Corte 10): una fila de la valoración «calza» con la red si la diferencia de longitud o de cantidad no pasa de este porcentaje')
on conflict (clave) do update set estado = 'vigente', descripcion = excluded.descripcion;
