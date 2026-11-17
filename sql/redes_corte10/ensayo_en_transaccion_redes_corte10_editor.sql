begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 10 — GUARDIA Y ESQUEMA (inventario regulatorio: la Valoración Técnica de 2019, Res. CRA 688 de 2014)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code B). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte10_inventario_regulatorio.md (16-nov) y regulatorio/salida_geoportal/LEEME.md.
-- · Presupone el Corte 5d publicado (huella del conjunto de funciones de redes 5fd6d00efdaa1a798e2628a2cde23c61).
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
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '5fd6d00efdaa1a798e2628a2cde23c61' then
    raise exception 'Las funciones de redes no son las del Corte 5d publicado (huella 5fd6d00efdaa1a798e2628a2cde23c61): deténgase y avise';
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
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 20 — FUNCIONES INTERNAS (nadie de la API las ejecuta: ver 40_permisos.sql)
-- =====================================================================
-- La hoja de alcantarillado que vale hoy (parámetro; la decide David)
create function redes.f_val_hoja_alc() returns text language sql stable set search_path to 'redes', 'pg_temp' as $$
  select case when redes.f_param('valoracion_hoja_alcantarillado') = 1 then 'alcantarillado' else 'alcantarillado_2' end $$;

-- Los tipos de activo que la valoración cubre: solo en ellos la ficha dice «fuera de la valoración» cuando no hay amarre (un pozo o un accesorio no llevan la sección)
create function redes.f_val_prefijos() returns text[] language sql immutable set search_path to 'pg_catalog' as $$
  select array['RED', 'CON', 'ADU', 'COL', 'INT', 'TOR', 'HID', 'VAL', 'TAN', 'PTA', 'PTR', 'CAP', 'DES'] $$;

-- La sección «Inventario regulatorio» de la ficha (solo la piden supervisor y administrador: lo decide redes.f_ficha).
-- Los valores son DE LA FILA (agregados): no se reparten por activo. «Vida útil remanente a hoy» = vida útil − años desde la entrada en operación regulatoria.
create function redes.f_ficha_regulatorio(p_activo bigint, p_prefijo text) returns jsonb
language plpgsql stable set search_path to 'redes', 'public', 'pg_temp' as $$
declare v_val bigint := redes.f_ref_vigente('valoracion'); v_am bigint; v_hoja text; c redes.ref_cargas%rowtype;
        v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; v_filas jsonb; v_sit text; v_nota text; v_n integer;
begin
  if v_val is null then return null; end if;      -- todavía no se ha cargado la valoración
  v_am := redes.f_ref_vigente('val_amarre'); v_hoja := redes.f_val_hoja_alc();
  select count(*), min(am.situacion) filter (where am.n is null), min(am.nota) filter (where am.n is null) into v_n, v_sit, v_nota
    from redes.val_amarre am where am.activo_id = p_activo and am.carga_id = v_am and am.val_carga_id = v_val and am.hoja in ('acueducto', v_hoja);
  if v_n = 0 and not (p_prefijo = any (redes.f_val_prefijos())) then return null; end if;
  select * into c from redes.ref_cargas where id = v_val;
  select jsonb_agg(jsonb_build_object(
           'hoja', h.nombre_hoja, 'n', f.n, 'nombre', f.nombre, 'clase', f.clase, 'caracteristica', f.caracteristica, 'diametro_pulg', f.diametro_pulg,
           'cantidad', f.cantidad, 'unidad', f.unidad,
           'activos', (select count(*) from redes.val_amarre x where x.carga_id = v_am and x.hoja = f.hoja and x.n = f.n and x.val_carga_id = v_val),
           'anio_operacion', f.anio_operacion, 'fecha_operacion', f.fecha_operacion, 'fecha_tarifa', f.fecha_tarifa, 'vida_util', f.vida_util,
           'vida_remanente_hoy', case when f.vida_util is not null and f.fecha_operacion is not null
                                      then greatest(0, round(f.vida_util - (v_hoy - f.fecha_operacion) / 365.25, 1)) end,
           'fin_vida_util', case when f.vida_util is not null and f.fecha_operacion is not null then (f.fecha_operacion + make_interval(months => round(f.vida_util * 12)::integer))::date end,
           'valor_total', round(f.valor_total), 'valor_remanente', round(f.valor_remanente), 'depreciacion_anual', round(f.depreciacion_anual),
           'aporte', am.cantidad, 'nota', am.nota) order by f.n)
    into v_filas
    from redes.val_amarre am
    join redes.val_filas f on f.carga_id = am.val_carga_id and f.hoja = am.hoja and f.n = am.n
    join redes.val_hojas h on h.carga_id = f.carga_id and h.hoja = f.hoja
   where am.activo_id = p_activo and am.carga_id = v_am and am.val_carga_id = v_val and am.hoja in ('acueducto', v_hoja);
  if v_filas is null then v_sit := case when v_n = 0 then 'fuera' else coalesce(v_sit, 'sin_fila') end; else v_sit := 'con_fila'; end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'fuente', 'Valoración técnica 2019 (Res. CRA 688 de 2014), propuesta',
    'archivo', c.archivo, 'cargada_en', c.creado_en,
    'remunerado', v_filas is not null,
    'situacion', v_sit,
    'texto', case v_sit when 'con_fila' then null
                        when 'fuera' then 'Fuera de la valoración 2019: el activo no estaba en la red con que se amarró la valoración (por ejemplo, uno nuevo de una inversión). Queda así hasta que haya una valoración nueva.'
                        when 'proyectado' then 'Proyectado por el Plan Maestro: no entra en la valoración 2019.'
                        else 'Sin fila en la valoración 2019: ninguna fila corresponde a su material y diámetro.' end,
    'nota', case when v_filas is null then v_nota end,
    'filas', v_filas));
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 26 — RPC NUEVA (solo service_role: la llama la Edge geoportal-redes)
-- =====================================================================
-- La conciliación del inventario regulatorio con la red (pantalla del administrador y su descarga en Excel). Solo lectura.
-- Por fila de la valoración: lo que dice el libro contra lo que suma la red amarrada (activos vigentes, sin los retirados ni los ocultos), diferencia y porcentaje.
-- Además: las filas sin activos y los activos sin fila (agrupados por tipo, material y diámetro). Sin datos de personas. No recalcula nada: lee el amarre vigente.
create function public.geoportal_redes_valoracion(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'redes', 'pg_temp' as $$
declare v_email text := redes.f_autorizar_admin(p_solicitante);
        v_val bigint := redes.f_ref_vigente('valoracion'); v_am bigint := redes.f_ref_vigente('val_amarre'); v_hoja text := redes.f_val_hoja_alc();
        v_tol numeric := redes.f_param('valoracion_tolerancia_pct'); v_pref text[] := redes.f_val_prefijos();
        v_hojas jsonb; v_filas jsonb; v_sin jsonb; c redes.ref_cargas%rowtype; a redes.ref_cargas%rowtype;
begin
  if v_val is null then
    return jsonb_build_object('cargada', false, 'hoja_alcantarillado', v_hoja, 'tolerancia_pct', v_tol);
  end if;
  select * into c from redes.ref_cargas where id = v_val;
  select * into a from redes.ref_cargas where id = v_am;
  with red as (
    select am.hoja, am.n, count(*) as activos, sum(am.cantidad) as cantidad, coalesce(sum(am.cantidad) filter (where am.situacion <> 'con_fila'), 0) as aparte,
           case when count(*) <= 4 then string_agg(m.codigo, ', ' order by m.codigo) end as codigos
      from redes.val_amarre am
      join redes.activo_vigente_mat m on m.activo_id = am.activo_id and not m.retirado and not m.oculto
     where am.carga_id = v_am and am.val_carga_id = v_val and am.n is not null
     group by am.hoja, am.n),
  fil as (
    select f.*, coalesce(r.activos, 0) as activos, r.cantidad as red, r.aparte, r.codigos,
           f.clase in ('tuberia', 'valvula', 'hidrante') as comparable
      from redes.val_filas f left join red r on r.hoja = f.hoja and r.n = f.n
     where f.carga_id = v_val)
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'hoja', x.hoja, 'n', x.n, 'nombre', x.nombre, 'clase', x.clase, 'caracteristica', x.caracteristica, 'unidad', x.unidad, 'cantidad', x.cantidad,
           'anio_operacion', x.anio_operacion, 'vida_util', x.vida_util, 'valor_total', round(x.valor_total), 'valor_remanente', round(x.valor_remanente),
           'depreciacion_anual', round(x.depreciacion_anual),
           'activos', x.activos, 'codigos', x.codigos, 'comparable', x.comparable,
           'red', case when x.comparable then round(coalesce(x.red, 0), 1) end,
           'aparte', case when x.comparable and x.aparte > 0 then round(x.aparte, 1) end,
           'diferencia', case when x.comparable then round(coalesce(x.red, 0) - coalesce(x.cantidad, 0), 1) end,
           'pct', case when x.comparable and x.cantidad > 0 then round(100 * coalesce(x.red, 0) / x.cantidad, 1) end,
           'calza', case when x.comparable then abs(coalesce(x.red, 0) - coalesce(x.cantidad, 0)) <= coalesce(x.cantidad, 0) * v_tol / 100 end,
           'nota', x.nota)) order by x.hoja, x.n)
    into v_filas from fil x;
  select jsonb_agg(jsonb_build_object('hoja', h.hoja, 'nombre', h.nombre_hoja, 'servicio', h.servicio, 'filas', h.filas, 'bcr0', round(h.bcr0), 'valor_total', round(h.valor_total),
                                      'depreciacion_anual', round(h.depreciacion_anual), 'vigente', h.hoja in ('acueducto', v_hoja)) order by h.hoja)
    into v_hojas from redes.val_hojas h where h.carga_id = v_val;
  -- activos de los tipos que la valoración cubre y que no tienen fila en la hoja vigente de su servicio
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('prefijo', g.prefijo, 'tipo', (select t.nombre_visible from redes.v_tipo_visible t where t.prefijo = g.prefijo),
                                                                 'sistema', g.sistema, 'material', (select mt.nombre from redes.materiales mt where mt.codigo = g.material_codigo),
                                                                 'diametro_mm', g.diametro_mm, 'motivo', g.motivo, 'activos', g.activos, 'longitud_m', round(g.longitud, 1)))
                            order by g.sistema, g.prefijo, g.motivo, g.activos desc), '[]'::jsonb)
    into v_sin
    from (select m.prefijo, m.sistema, m.material_codigo, m.diametro_mm, coalesce(x.situacion, 'fuera') as motivo, count(*) as activos, sum(coalesce(x.cantidad, m.longitud_m)) as longitud
            from redes.activo_vigente_mat m
            left join lateral (select am.situacion, am.cantidad, am.n from redes.val_amarre am
                                where am.activo_id = m.activo_id and am.carga_id = v_am and am.val_carga_id = v_val and am.hoja in ('acueducto', v_hoja)
                                order by am.n nulls last limit 1) x on true
           where not m.retirado and not m.oculto and m.prefijo = any (v_pref) and x.n is null
           group by m.prefijo, m.sistema, m.material_codigo, m.diametro_mm, coalesce(x.situacion, 'fuera')) g;
  return jsonb_build_object(
    'cargada', true,
    'fuente', 'Valoración técnica 2019 (Res. CRA 688 de 2014), propuesta',
    'valoracion', jsonb_build_object('archivo', c.archivo, 'md5', c.md5, 'filas', c.filas, 'cargada_en', c.creado_en, 'origen', c.origen),
    'amarre', case when a.id is not null then jsonb_build_object('archivo', a.archivo, 'md5', a.md5, 'filas', a.filas, 'cargado_en', a.creado_en, 'nota', a.nota) end,
    'hoja_alcantarillado', v_hoja, 'tolerancia_pct', v_tol,
    'generado_en', clock_timestamp(), 'generado_por', v_email,
    'hojas', coalesce(v_hojas, '[]'::jsonb), 'filas', coalesce(v_filas, '[]'::jsonb), 'sin_fila', v_sin);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del 5d publicado) con cambios exactos, aplicados una sola vez.
--   · redes.f_ficha: la sección «regulatorio» (solo supervisor y administrador);
--   · redes.f_param_entero: la unidad «hoja» es un número entero;
--   · geoportal_redes_geovisor: «edad_ref» (hay amarre vigente), para la nota de la leyenda, solo a quien ve el geovisor completo;
--   · geoportal_redes_geovisor_mvt: sin fecha de instalación, la edad sale de la fecha regulatoria de la fila (propiedad «edad_reg»), para quien ve el geovisor completo.
-- =====================================================================
-- redes.f_ficha(bigint,text)
CREATE OR REPLACE FUNCTION redes.f_ficha(p_activo bigint, p_perfil text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'redes', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v redes.v_activo_vigente%rowtype; t redes.v_tipo_visible%rowtype; v_super boolean := p_perfil in ('admin', 'supervisor');
  v_campos jsonb; v_origen jsonb; v_nodo jsonb; v_tramo jsonb; v_pto geometry;
begin
  select * into v from redes.v_activo_vigente where activo_id = p_activo;
  if not found then perform tecnica.f_error('Ese activo no está vigente', 'P0002'); end if;
  select * into t from redes.v_tipo_visible where prefijo = v.prefijo;
  v_pto := case when GeometryType(v.geom) = 'POINT' then v.geom else ST_PointOnSurface(v.geom) end;
  -- campos por tipo (tipos_activo.campos): el valor sale de la columna o de atributos; nulo = «sin dato»
  select coalesce(jsonb_agg(jsonb_build_object('clave', c ->> 'clave', 'rotulo', c ->> 'rotulo', 'unidad', c ->> 'unidad',
           'valor', case c ->> 'clave'
                      when 'diametro_mm' then to_jsonb(v.diametro_mm)
                      when 'longitud_m' then to_jsonb(v.longitud_m)
                      when 'capacidad' then to_jsonb(v.capacidad)
                      when 'profundidad_m' then to_jsonb(v.profundidad_m)
                      when 'material_codigo' then to_jsonb((select m.nombre from redes.materiales m where m.codigo = v.material_codigo))
                      when 'clase' then to_jsonb((select x.nombre from redes.clases_activo x where x.prefijo = v.prefijo and x.codigo = v.clase))
                      when 'efecto' then to_jsonb((select e.nombre from redes.efectos_valvula e where e.codigo = v.efecto))
                      when 'punto_codigo' then (select to_jsonb(ap.punto_codigo) from redes.v_activo_punto_vigente ap where ap.activo_id = p_activo)
                      else v.atributos -> (c ->> 'clave') end) order by o), '[]'::jsonb)
    into v_campos
    from jsonb_array_elements(t.campos) with ordinality as e(c, o);
  if v_super then
    select jsonb_build_object('origen', o.origen, 'aportante', o.aportante_codigo, 'aportante_nombre', a.nombre, 'tiene_soporte', o.soporte_ruta is not null, 'nota', o.nota)
      into v_origen from redes.v_activo_origen_vigente o left join redes.entidades_aportantes a on a.codigo = o.aportante_codigo where o.activo_id = p_activo;
  end if;
  -- si el activo es un nodo de la topología: cuántos tramos llegan
  select jsonb_build_object('nombre_modelo', n.nombre_modelo, 'nombre_visible', n.nombre_visible,
           'tramos', redes.f_tramos_de_nodo(n.nodo_id))
    into v_nodo from redes.f_nodo_de_activo(p_activo) n limit 1;      -- 9a-bis: por índice
  -- si es un tramo: sus dos extremos (con el activo de cada nodo, si lo tiene)
  select jsonb_build_object('metodo', tn.metodo,
           'inicio', (select jsonb_build_object('nombre', n.nombre_visible, 'activo', redes.f_activo_corto(n.activo_id)) from redes.f_nodo_visible_id(tn.nodo_ini) n),
           'fin', (select jsonb_build_object('nombre', n.nombre_visible, 'activo', redes.f_activo_corto(n.activo_id)) from redes.f_nodo_visible_id(tn.nodo_fin) n))
    into v_tramo from redes.tramo_nodos tn join redes.activo_vigente_mat tv on tv.activo_id = tn.activo_id and tv.version = tn.version where tn.activo_id = p_activo;
  return jsonb_strip_nulls(jsonb_build_object(
    'perfil', p_perfil,
    'activo', jsonb_build_object(
      'codigo', v.codigo, 'prefijo', v.prefijo, 'tipo', t.nombre_visible, 'tipo_catalogo', t.nombre,
      'sistema', v.sistema, 'sistema_nombre', (select s.nombre from redes.sistemas s where s.codigo = v.sistema), 'etapa', t.etapa, 'geometria', t.geometria,
      'nombre', v.nombre, 'clase', (select x.nombre from redes.clases_activo x where x.prefijo = v.prefijo and x.codigo = v.clase),
      'estado', (select s.nombre from redes.estados_activo s where s.codigo = v.estado_codigo), 'estado_codigo', v.estado_codigo,
      'cuenta_vigente', v.cuenta_vigente, 'punteado', v.punteado, 'retirado', v.retirado, 'oculto', v.oculto, 'por_verificar', v.por_verificar,
      'material', (select m.nombre from redes.materiales m where m.codigo = v.material_codigo),
      'fecha_instalacion', v.fecha_instalacion, 'barrio_sector', v.barrio_sector, 'codigo_anterior', v.codigo_anterior,
      'version', v.version, 'version_creada_en', v.version_creada_en, 'lat', round(ST_Y(v_pto)::numeric, 6), 'lon', round(ST_X(v_pto)::numeric, 6),
      'campos', v_campos),
    -- Corte 9a: se lee de las tablas de referencia y de los polígonos vigentes de sectores. 9a-bis: el sector hidráulico (por la ubicación) es el oficial
    'sector_hidraulico', case when v.prefijo <> 'SEC' then (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector, 'codigo', s.codigo, 'nombre', s.nombre)
                                                        from redes.f_sector_de(v.geom) s where s.sector is not null) end,
    'referencia', case when v_super then nullif(redes.f_ficha_referencia(p_activo), '[]'::jsonb) end,
    -- Corte 10: inventario regulatorio (la fila de la Valoración Técnica 2019 a la que está amarrado). Solo supervisor y administrador
    'regulatorio', case when v_super then redes.f_ficha_regulatorio(p_activo, v.prefijo) end,
    'por_verificar_motivo', case when v.por_verificar then (select e.motivo from redes.activo_eventos e where e.activo_id = p_activo and e.tipo = 'por_verificar' order by e.id desc limit 1) end,
    'origen', v_origen,
    'modelo', case when v_super then v.atributos -> 'modelo' end,
    'nodo', v_nodo,
    'tramo', v_tramo,
    'contratos_enlazados', case when v.prefijo in ('RED', 'CON') then (select count(*) from redes.contrato_tramo ct where ct.activo_id = p_activo) end,
    'componentes', (select coalesce(jsonb_agg(redes.f_activo_corto(c.hijo_id) order by h.codigo), '[]'::jsonb)
                      from redes.v_componentes_vigentes c join redes.activos h on h.id = c.hijo_id where c.padre_id = p_activo
                       and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = c.hijo_id)),
    'parte_de', (select coalesce(jsonb_agg(redes.f_activo_corto(c.padre_id) order by p.codigo), '[]'::jsonb)
                   from redes.v_componentes_vigentes c join redes.activos p on p.id = c.padre_id where c.hijo_id = p_activo
                    and exists (select 1 from redes.activo_vigente_mat m where m.activo_id = c.padre_id)),
    'admite_componentes', (select admite_componentes from redes.tipos_activo where prefijo = v.prefijo),
    -- «hechos»: daños, fallas e intervenciones (los suma la epicrisis desde los Cortes 2 y 3); «registro»: altas, versiones, retiros y componentes
    'epicrisis', jsonb_build_object(
      'hechos', (select count(*) from redes.v_epicrisis e where e.activo_id = p_activo and e.clase in ('dano', 'falla', 'intervencion')),
      'registro', (select count(*) from redes.v_epicrisis e where e.activo_id = p_activo and e.clase not in ('dano', 'falla', 'intervencion')),
      'danos_12_meses', (select count(*) from redes.v_epicrisis e where e.activo_id = p_activo and e.clase in ('dano', 'falla') and e.cuando >= now() - interval '12 months'))));
end $function$;

-- redes.f_param_entero(text)
CREATE OR REPLACE FUNCTION redes.f_param_entero(p_unidad text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select p_unidad in ('fotos', 'documentos', 'materiales', 'activos', 'días', 'horas', 'filas', 'bytes', 'zoom', 'hoja') $function$;

-- public.geoportal_redes_geovisor_mvt(text,integer,integer,integer)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor_mvt(p_solicitante text, p_z integer, p_x integer, p_y integer)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare a record; v_am bigint; v_val bigint; v_hoja text; v_env geometry; v_env4326 geometry; v bytea; v_pref text[]; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        z_min numeric := redes.f_param('geovisor_zoom_min'); z_red numeric := redes.f_param('geovisor_zoom_red_completa');
        z_nod numeric := redes.f_param('geovisor_zoom_nodos'); z_acc numeric := redes.f_param('geovisor_zoom_acc');
        d_acu numeric := redes.f_param('geovisor_diam_principal_acu_mm'); d_alc numeric := redes.f_param('geovisor_diam_principal_alc_mm');
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if a.completo then v_val := redes.f_ref_vigente('valoracion'); v_am := redes.f_ref_vigente('val_amarre'); v_hoja := redes.f_val_hoja_alc(); end if;      -- Corte 10
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < z_min then return ''; end if;
  select array_agg(distinct p) into v_pref from redes.geovisor_capas g cross join unnest(g.prefijos) p where g.activa and g.fuente = 'tesela' and (a.completo or not g.solo_completo);
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4326 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'activos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, m.codigo, m.prefijo, m.sistema,
           case GeometryType(m.geom) when 'POINT' then 'nodo' when 'POLYGON' then 'area' when 'MULTIPOLYGON' then 'area' else 'tramo' end as forma,
           coalesce(m.clase, '') as clase, coalesce(m.material_codigo, '') as material, m.diametro_mm::real as diametro,
           case when m.fecha_instalacion is not null then greatest(0, extract(year from age(v_hoy, m.fecha_instalacion)))::integer
                when r.fecha is not null then greatest(0, extract(year from age(v_hoy, r.fecha)))::integer end as edad,
           case when m.fecha_instalacion is null and r.fecha is not null then true end as edad_reg,      -- Corte 10: fecha regulatoria, no de instalación
           m.estado_codigo as estado, m.punteado,
           case when m.prefijo in ('SEC', 'TAN', 'PTA', 'CAP', 'DES', 'EBA', 'EBR', 'PTR') then m.nombre end as nombre
      from redes.activo_vigente_mat m
      left join lateral (select min(f.fecha_operacion) as fecha
                           from redes.val_amarre am join redes.val_filas f on f.carga_id = am.val_carga_id and f.hoja = am.hoja and f.n = am.n
                          where v_am is not null and m.fecha_instalacion is null and am.activo_id = m.activo_id and am.carga_id = v_am and am.val_carga_id = v_val
                            and am.hoja in ('acueducto', v_hoja) and am.n is not null) r on true
     where not m.retirado and not m.oculto and m.prefijo = any (v_pref)
       and m.geom && v_env4326
       and case
             when m.prefijo = 'ACC' then p_z >= z_acc
             when m.prefijo in ('TAN', 'PTA', 'CAP', 'DES', 'EBA', 'EBR', 'PTR', 'SEC') then true
             when GeometryType(m.geom) = 'POINT' then p_z >= z_nod
             when p_z >= z_red then true
             else m.prefijo in ('CON', 'ADU', 'INT')
                  or (m.sistema = 'acueducto' and m.diametro_mm >= d_acu) or (m.sistema = 'alcantarillado' and m.diametro_mm >= d_alc)
           end) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
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
    'edad_ref', case when a.completo and redes.f_ref_vigente('val_amarre') is not null then true end,      -- Corte 10: hay amarre con la valoración
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
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las funciones internas nuevas y las reemplazadas: nadie de la API. La RPC nueva y las dos RPC reemplazadas: solo service_role (la Edge geoportal-redes).
-- Las tablas nuevas: nadie de la API (10_esquema.sql): las leen solo las funciones SECURITY DEFINER.
-- =====================================================================
revoke all on function redes.f_val_hoja_alc(), redes.f_val_prefijos(), redes.f_ficha_regulatorio(bigint, text) from public, anon, authenticated, service_role;
revoke all on function redes.f_ficha(bigint, text), redes.f_param_entero(text) from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_valoracion', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte10', 'migracion_redes_corte10', null, jsonb_build_object(
        'tablas', jsonb_build_array('redes.val_hojas', 'redes.val_filas', 'redes.val_amarre'),
        'nuevas', jsonb_build_array('redes.f_val_hoja_alc', 'redes.f_val_prefijos', 'redes.f_ficha_regulatorio', 'geoportal_redes_valoracion'),
        'reemplazadas', jsonb_build_array('redes.f_ficha', 'redes.f_param_entero', 'geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt'),
        'parametros', jsonb_build_array('valoracion_hoja_alcantarillado', 'valoracion_tolerancia_pct'),
        'motivo', 'inventario regulatorio: la Valoración Técnica de 2019 como referencia, el amarre de cada activo con su fila, la conciliación, la sección de la ficha y la fecha regulatoria en el color por edad'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 20, 26, 25 y 40, en la misma transacción.
-- No supone códigos ni conteos de la base: arma sus personas (prueba.redes10.*), sus activos (ZT10, en un rincón de Valledupar), su valoración de prueba
-- (archivo «ZT10 …», que dentro de esta transacción pasa a ser la vigente) y sus amarres. Ninguna cifra real de la valoración.
-- Mide con el volumen real: amarra TODOS los tramos, conductos, hidrantes y válvulas de la base donde corre a la valoración de prueba y toma el tiempo de la
-- conciliación, de la ficha y de la tesela más cargada: FALLA si alguna llamada pasa de 5 s.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 10 … RESULTADO: N de N pruebas correctas — SIN FALLAS
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
-- un rincón de la caja de Valledupar, lejos de la red (x, y en metros aproximados)
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$
  select ST_SetSRID(ST_MakePoint(round(-73.5800 + x * 0.0000091, 6), round(10.1300 + y * 0.0000090, 6)), 4326) $$;
create function pg_temp.linea(x0 numeric, y0 numeric, x1 numeric, y1 numeric) returns geometry language sql as $$ select ST_MakeLine(pg_temp.pt(x0, y0), pg_temp.pt(x1, y1)) $$;
create function pg_temp.activo(p_prefijo text, p_geom geometry, p_origen_alta text default 'carga', p_fecha date default null, p_estado text default 'en_operacion')
returns bigint language plpgsql as $$
declare v_cons bigint; v_cod text; v_id bigint; q text := 'prueba.redes10.adm@emdupar.gov.co';
begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = p_prefijo returning ultimo into v_cons;
  v_cod := p_prefijo || '-' || lpad(v_cons::text, 6, '0');
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values (v_cod, p_prefijo, p_origen_alta, q) returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, estado_codigo, fecha_instalacion, atributos, huella, autor)
  values (v_id, 1, p_geom, 'ZT10 ' || p_prefijo, p_estado, p_fecha, '{}'::jsonb, md5(v_cod), q);
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT10 activo de prueba', q);
  perform redes.f_mat_refrescar_uno(v_id);
  return v_id;
end $$;
create function pg_temp.cod(p_id bigint) returns text language sql as $$ select codigo from redes.activos where id = p_id $$;
-- la tesela (z, x, y) que contiene un punto
create function pg_temp.tx(g geometry, z integer) returns integer language sql as $$ select floor((ST_X(g) + 180) / 360 * (1 << z))::integer $$;
create function pg_temp.ty(g geometry, z integer) returns integer language sql as $$
  select floor((1 - ln(tan(radians(ST_Y(g))) + 1 / cos(radians(ST_Y(g)))) / pi()) / 2 * (1 << z))::integer $$;
-- una fila de la conciliación
create function pg_temp.fila(p jsonb, p_hoja text, p_n integer) returns jsonb language sql as $$
  select x from jsonb_array_elements(p -> 'filas') x where x ->> 'hoja' = p_hoja and (x ->> 'n')::integer = p_n $$;

do $prueba$
declare
  a text := 'prueba.redes10.adm@emdupar.gov.co'; sd text := 'prueba.redes10.dist@emdupar.gov.co'; op text := 'prueba.redes10.op@emdupar.gov.co';
  v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date; v_fop date; v_antes bigint;
  v_val bigint; v_am bigint; v_am2 bigint; v_j jsonb; v_f jsonb; v_x jsonb;
  t1 bigint; t2 bigint; t3 bigint; t4 bigint; t5 bigint; t6 bigint; h1 bigint; h2 bigint; pl bigint; c1 bigint; pz bigint;
  v_z integer; v_m text; v_m2 text; v_g geometry;
  v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_ms4 numeric; v_n integer; v_real bigint; v_tx integer; v_ty integer;
  v_info text := ''; v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT10 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT10 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT10 Operador de redes', 'consulta', true, 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a);
  v_fop := (v_hoy - interval '10 years')::date;

  -- ===================== 01. Esquema, permisos y parámetros =====================
  perform pg_temp.reg('01.01 las 3 funciones internas nuevas no las ejecuta la API; la RPC nueva y las dos reemplazadas (configuración y tesela del geovisor), solo service_role (security definer)',
     not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace and p.proname in ('f_val_hoja_alc', 'f_val_prefijos', 'f_ficha_regulatorio', 'f_ficha', 'f_param_entero')
                   and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')))
     and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_redes_valoracion', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor') and p.prosecdef
           and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
           and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 3);
  perform pg_temp.reg('01.02 las 3 tablas: con seguridad de filas, sin permisos para la API y de solo agregar (6 disparadores)',
     (select count(*) from pg_class c where c.oid in ('redes.val_hojas'::regclass, 'redes.val_filas'::regclass, 'redes.val_amarre'::regclass) and c.relrowsecurity
       and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')) = 3
     and (select count(*) from pg_trigger t where t.tgrelid in ('redes.val_hojas'::regclass, 'redes.val_filas'::regclass, 'redes.val_amarre'::regclass) and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 6);
  perform pg_temp.reg('01.03 los parámetros: vale la hoja «ALCANTARILLADO (2)» (2) y la tolerancia es 2 %; la unidad «hoja» es un entero',
     redes.f_param('valoracion_hoja_alcantarillado') = 2 and redes.f_val_hoja_alc() = 'alcantarillado_2' and redes.f_param('valoracion_tolerancia_pct') = 2
     and redes.f_param_entero('hoja') and redes.f_param_entero('zoom') and not redes.f_param_entero('%'));
  perform pg_temp.reg('01.04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()),
     (select string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()));

  -- ===================== 02. Los activos de prueba y, antes de cargar nada, cómo responde =====================
  t1 := pg_temp.activo('RED', pg_temp.linea(0, 0, 100, 0));                 -- amarrado, sin fecha de instalación
  t2 := pg_temp.activo('RED', pg_temp.linea(0, 20, 150, 20));               -- amarrado
  t3 := pg_temp.activo('RED', pg_temp.linea(0, 40, 60, 40), 'carga', null, 'proyectado');      -- proyectado: no entra
  t4 := pg_temp.activo('RED', pg_temp.linea(0, 60, 80, 60));                -- sin fila
  t5 := pg_temp.activo('RED', pg_temp.linea(0, 80, 40, 80), 'intervencion');      -- nuevo de una inversión: sin amarre → fuera de la valoración
  t6 := pg_temp.activo('RED', pg_temp.linea(20000, 20000, 20100, 20000), 'carga', (v_hoy - interval '3 years')::date);      -- lejos; amarrado y CON fecha de instalación
  h1 := pg_temp.activo('TOR', pg_temp.pt(10, 100)); h2 := pg_temp.activo('TOR', pg_temp.pt(30, 100));
  pl := pg_temp.activo('PTA', pg_temp.pt(50, 120));                          -- una planta para dos filas
  c1 := pg_temp.activo('COL', pg_temp.linea(0, 140, 90, 140));              -- conducto de alcantarillado: fila según la hoja que valga
  pz := pg_temp.activo('POZ', pg_temp.pt(0, 160));                           -- un tipo que la valoración no cubre
  v_antes := redes.f_ref_vigente('valoracion');
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t1));
  v_j := public.geoportal_redes_valoracion(a);
  perform pg_temp.reg('02.01 sin valoración cargada: la ficha no trae la sección y la conciliación dice «sin cargar» (si ya hay una vigente, la trae)',
     case when v_antes is null then not (v_f ? 'regulatorio') and not (v_j ->> 'cargada')::boolean and v_j ->> 'hoja_alcantarillado' = 'alcantarillado_2'
          else (v_j ->> 'cargada')::boolean and (v_f -> 'regulatorio' ->> 'situacion') = 'fuera' end,
     case when v_antes is null then 'la base no tenía valoración' else 'la base ya tenía una valoración vigente (carga ' || v_antes || ')' end);

  -- ===================== 03. La valoración y el amarre de prueba =====================
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor) values ('valoracion', 'ZT10 valoracion de prueba.xlsx', md5('zt10-val'), 8, 'ZT10 valoración de prueba', null, a) returning id into v_val;
  insert into redes.val_hojas (carga_id, hoja, nombre_hoja, servicio, filas, bcr0, valor_total, depreciacion_anual) values
    (v_val, 'acueducto', 'ZT10 ACUEDUCTO', 'acueducto', 5, 5000, 9000, 200), (v_val, 'alcantarillado', 'ZT10 ALCANTARILLADO', 'alcantarillado', 1, 700, 900, 20),
    (v_val, 'alcantarillado_2', 'ZT10 ALCANTARILLADO (2)', 'alcantarillado', 2, 800, 1000, 30);
  insert into redes.val_filas (carga_id, hoja, n, nombre, vida_util, caracteristica, cantidad, unidad, precio_unitario, valor_total, anio_operacion, fecha_operacion, fecha_tarifa,
                               valor_remanente, depreciacion_anual, clase, material, diametro_pulg, nota) values
    (v_val, 'acueducto', 1, 'TUBERIA ZT10', 45, '3', 250, 'm', 10, 2500, extract(year from v_fop)::integer, v_fop, v_fop + 30, 1500, 55.6, 'tuberia', 'ZT10', 3, null),
    (v_val, 'acueducto', 2, 'TUBERIA ZT10', 45, '4', 500, 'm', 12, 6000, 1989, date '1989-07-01', date '2016-07-01', 3000, 133.3, 'tuberia', 'ZT10', 4, null),
    (v_val, 'acueducto', 3, 'HIDRANTES ZT10', 45, null, 2, 'un', 100, 200, 1989, date '1989-07-01', date '2016-07-01', 100, 4.4, 'hidrante', null, null, null),
    (v_val, 'acueducto', 4, 'PLANTA ZT10 UNO', 40, 'Planta', 600, 'L/s', null, 200, 1992, date '1992-07-01', date '2016-07-01', 200, 5, 'puntual', null, null, null),
    (v_val, 'acueducto', 5, 'PLANTA ZT10 DOS', 40, 'Planta', 300, 'L/s', null, 100, 2001, date '2001-07-01', date '2016-07-01', 200, 2.5, 'puntual', null, null, 'ZT10 nota de la fila'),
    (v_val, 'alcantarillado', 1, 'TUBERIA ZT10 GRES', 45, '8', 500, 'm', 9, 900, 1989, date '1989-07-01', date '2016-07-01', 700, 20, 'tuberia', 'ZT10 GRES', 8, null),
    (v_val, 'alcantarillado_2', 1, 'TUBERIA ZT10 GRES', 45, '8', 90, 'm', 9, 810, 1989, date '1989-07-01', date '2016-07-01', 600, 18, 'tuberia', 'ZT10 GRES', 8, null),
    (v_val, 'alcantarillado_2', 2, 'TUBERIA ZT10 PVC', 45, '8', 40, 'm', 9, 190, 1989, date '1989-07-01', date '2016-07-01', 200, 12, 'tuberia', 'ZT10 PVC', 8, null);
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor) values ('val_amarre', 'ZT10 amarre de prueba.csv', md5('zt10-am'), 10, 'ZT10 amarre de prueba', null, a) returning id into v_am;
  insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion, nota) values
    (v_am, v_val, t1, 'acueducto', 1, 100, 'con_fila', null), (v_am, v_val, t2, 'acueducto', 1, 150, 'aparte_siva', 'ZT10 obra de un tercero'),
    (v_am, v_val, t3, 'acueducto', null, 60, 'proyectado', null), (v_am, v_val, t4, 'acueducto', null, 80, 'sin_fila', 'ZT10 sin pareja'),
    (v_am, v_val, t6, 'acueducto', 1, 0, 'con_fila', null),
    (v_am, v_val, h1, 'acueducto', 3, 1, 'con_fila', null), (v_am, v_val, h2, 'acueducto', 3, 1, 'con_fila', null),
    (v_am, v_val, pl, 'acueducto', 4, 1, 'con_fila', null), (v_am, v_val, pl, 'acueducto', 5, 1, 'con_fila', null),
    (v_am, v_val, c1, 'alcantarillado_2', 1, 90, 'con_fila', null), (v_am, v_val, c1, 'alcantarillado', 1, 90, 'con_fila', null);
  perform pg_temp.reg('03.01 la valoración y el amarre de prueba quedan vigentes', redes.f_ref_vigente('valoracion') = v_val and redes.f_ref_vigente('val_amarre') = v_am);
  perform pg_temp.err('03.02 un amarre «con fila» sin número de fila se rechaza',
     format($$insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion) values (%s, %s, %s, 'acueducto', null, 1, 'con_fila')$$, v_am, v_val, t4), '23514');
  perform pg_temp.err('03.03 un amarre a una fila que no existe en la valoración se rechaza',
     format($$insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion) values (%s, %s, %s, 'acueducto', 99, 1, 'con_fila')$$, v_am, v_val, t4), '23503');
  perform pg_temp.err('03.04 el mismo activo no se amarra dos veces a la misma fila en una carga',
     format($$insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion) values (%s, %s, %s, 'acueducto', 1, 1, 'con_fila')$$, v_am, v_val, t1), '23505');
  perform pg_temp.err('03.05 la valoración es de solo inserción: no se corrige una fila', format($$update redes.val_filas set cantidad = 1 where carga_id = %s and hoja = 'acueducto' and n = 1$$, v_val));
  perform pg_temp.err('03.06 el amarre es de solo inserción: no se borra', format($$delete from redes.val_amarre where carga_id = %s and activo_id = %s$$, v_am, t1));

  -- ===================== 04. La ficha: «Inventario regulatorio», solo supervisor y administrador =====================
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t1)) -> 'regulatorio';
  v_x := v_f -> 'filas' -> 0;
  perform pg_temp.reg('04.01 administrador, tramo amarrado: remunerado, con su fila (nombre, característica, cantidad y cuántos activos tiene amarrados)',
     (v_f ->> 'remunerado')::boolean and v_f ->> 'situacion' = 'con_fila' and v_f ->> 'fuente' like 'Valoración técnica 2019%propuesta' and jsonb_array_length(v_f -> 'filas') = 1
     and v_x ->> 'nombre' = 'TUBERIA ZT10' and v_x ->> 'caracteristica' = '3' and (v_x ->> 'cantidad')::numeric = 250 and v_x ->> 'unidad' = 'm' and (v_x ->> 'activos')::integer = 3
     and v_x ->> 'hoja' = 'ZT10 ACUEDUCTO' and (v_x ->> 'aporte')::numeric = 100, v_f::text);
  perform pg_temp.reg('04.02 fecha de entrada en operación regulatoria, vida útil 45 y vida útil remanente A HOY (45 − 10 años = 35,0); valor y depreciación de la FILA',
     (v_x ->> 'fecha_operacion')::date = v_fop and (v_x ->> 'vida_util')::numeric = 45 and (v_x ->> 'vida_remanente_hoy')::numeric between 34.9 and 35.1
     and (v_x ->> 'fin_vida_util')::date = (v_fop + interval '45 years')::date
     and (v_x ->> 'valor_total')::numeric = 2500 and (v_x ->> 'valor_remanente')::numeric = 1500 and (v_x ->> 'depreciacion_anual')::numeric = 56, v_x::text);
  perform pg_temp.reg('04.03 una fila ya vencida da vida útil remanente 0 o más (nunca negativa)',
     (select (public.geoportal_redes_activo(a, pg_temp.cod(h1)) -> 'regulatorio' -> 'filas' -> 0 ->> 'vida_remanente_hoy')::numeric)
       = greatest(0, round(45 - (v_hoy - date '1989-07-01') / 365.25, 1)));
  perform pg_temp.reg('04.04 el supervisor de distribución también la ve; el operador NO (ni la sección ni ningún valor)',
     (public.geoportal_redes_activo(sd, pg_temp.cod(t1)) -> 'regulatorio' ->> 'remunerado')::boolean
     and not (public.geoportal_redes_activo(op, pg_temp.cod(t1)) ? 'regulatorio')
     and public.geoportal_redes_activo(op, pg_temp.cod(t1))::text !~* 'remunerad|valoraci|depreciaci|tarif|regulator');
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t2)) -> 'regulatorio';
  perform pg_temp.reg('04.05 un tramo «marcado aparte» (obra de un tercero) tiene fila y lleva su nota',
     (v_f ->> 'remunerado')::boolean and v_f -> 'filas' -> 0 ->> 'nota' = 'ZT10 obra de un tercero', v_f::text);
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t3)) -> 'regulatorio';
  perform pg_temp.reg('04.06 un tramo proyectado: no remunerado, «no entra en la valoración»',
     not (v_f ->> 'remunerado')::boolean and v_f ->> 'situacion' = 'proyectado' and v_f ->> 'texto' like 'Proyectado%' and not (v_f ? 'filas'), v_f::text);
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t4)) -> 'regulatorio';
  perform pg_temp.reg('04.07 un tramo sin fila: no remunerado, con el motivo',
     not (v_f ->> 'remunerado')::boolean and v_f ->> 'situacion' = 'sin_fila' and v_f ->> 'texto' like 'Sin fila%' and v_f ->> 'nota' = 'ZT10 sin pareja', v_f::text);
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(t5)) -> 'regulatorio';
  perform pg_temp.reg('04.08 un activo nuevo de una inversión (sin amarre): «fuera de la valoración 2019», no remunerado',
     not (v_f ->> 'remunerado')::boolean and v_f ->> 'situacion' = 'fuera' and v_f ->> 'texto' like 'Fuera de la valoración 2019%', v_f::text);
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(pl)) -> 'regulatorio';
  perform pg_temp.reg('04.09 un activo con dos filas (la planta): las trae las dos, en orden',
     (v_f ->> 'remunerado')::boolean and jsonb_array_length(v_f -> 'filas') = 2 and v_f -> 'filas' -> 0 ->> 'nombre' = 'PLANTA ZT10 UNO' and v_f -> 'filas' -> 1 ->> 'nombre' = 'PLANTA ZT10 DOS'
     and v_f -> 'filas' -> 0 ->> 'unidad' = 'L/s', v_f::text);
  perform pg_temp.reg('04.10 un tipo que la valoración no cubre (un pozo) no lleva la sección',
     not (public.geoportal_redes_activo(a, pg_temp.cod(pz)) ? 'regulatorio'));
  perform pg_temp.reg('04.11 la ficha oficial no cambió: ningún activo de prueba tiene más de su versión 1',
     (select max(v.version) from redes.activo_versiones v where v.activo_id in (t1, t2, t3, t4, t5, t6, h1, h2, pl, c1, pz)) = 1);

  -- ===================== 05. La hoja de alcantarillado que vale (parámetro) =====================
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(c1)) -> 'regulatorio';
  perform pg_temp.reg('05.01 con el parámetro en 2, el conducto muestra su fila de «ALCANTARILLADO (2)»',
     v_f -> 'filas' -> 0 ->> 'hoja' = 'ZT10 ALCANTARILLADO (2)' and (v_f -> 'filas' -> 0 ->> 'cantidad')::numeric = 90 and jsonb_array_length(v_f -> 'filas') = 1, v_f::text);
  perform pg_temp.err('05.02 el parámetro de la hoja solo admite 1 o 2 (enteros)',
     format($$select public.geoportal_redes_parametro_fijar(%L, 'valoracion_hoja_alcantarillado', 1.5, 'ZT10 prueba de la hoja vigente')$$, a), null, 'enteros');
  perform pg_temp.err('05.03 el supervisor no cambia la hoja: solo el administrador',
     format($$select public.geoportal_redes_parametro_fijar(%L, 'valoracion_hoja_alcantarillado', 1, 'ZT10 prueba de la hoja vigente')$$, sd), '42501');
  perform public.geoportal_redes_parametro_fijar(a, 'valoracion_hoja_alcantarillado', 1, 'ZT10 prueba de la hoja vigente');
  v_f := public.geoportal_redes_activo(a, pg_temp.cod(c1)) -> 'regulatorio';
  v_j := public.geoportal_redes_valoracion(a);
  perform pg_temp.reg('05.04 al cambiar el parámetro a 1, vale la otra hoja: en la ficha y en la conciliación (sin recargar nada)',
     v_f -> 'filas' -> 0 ->> 'hoja' = 'ZT10 ALCANTARILLADO' and (v_f -> 'filas' -> 0 ->> 'cantidad')::numeric = 500 and v_j ->> 'hoja_alcantarillado' = 'alcantarillado'
     and (select (x ->> 'vigente')::boolean from jsonb_array_elements(v_j -> 'hojas') x where x ->> 'hoja' = 'alcantarillado')
     and not (select (x ->> 'vigente')::boolean from jsonb_array_elements(v_j -> 'hojas') x where x ->> 'hoja' = 'alcantarillado_2'), v_f::text);
  perform public.geoportal_redes_parametro_fijar(a, 'valoracion_hoja_alcantarillado', 2, 'ZT10 prueba: vuelve a la hoja (2)');

  -- ===================== 06. La conciliación (solo el administrador) =====================
  perform pg_temp.err('06.01 la conciliación no la ve el supervisor de distribución', format('select public.geoportal_redes_valoracion(%L)', sd), '42501');
  perform pg_temp.err('06.02 ni el operador', format('select public.geoportal_redes_valoracion(%L)', op), '42501');
  perform pg_temp.err('06.03 ni alguien sin identificar', 'select public.geoportal_redes_valoracion(null)', '28000');
  v_j := public.geoportal_redes_valoracion(a);
  v_x := pg_temp.fila(v_j, 'acueducto', 1);
  perform pg_temp.reg('06.04 una fila de tubería: 250 m en la valoración contra 250 m de la red (3 tramos; 150 «aparte»), diferencia 0, 100 %, calza',
     (v_x ->> 'cantidad')::numeric = 250 and (v_x ->> 'red')::numeric = 250 and (v_x ->> 'activos')::integer = 3 and (v_x ->> 'aparte')::numeric = 150
     and (v_x ->> 'diferencia')::numeric = 0 and (v_x ->> 'pct')::numeric = 100 and (v_x ->> 'calza')::boolean and (v_x ->> 'comparable')::boolean, v_x::text);
  v_x := pg_temp.fila(v_j, 'acueducto', 2);
  perform pg_temp.reg('06.05 una fila sin activos: red 0, diferencia −500, 0 %, no calza',
     (v_x ->> 'activos')::integer = 0 and (v_x ->> 'red')::numeric = 0 and (v_x ->> 'diferencia')::numeric = -500 and (v_x ->> 'pct')::numeric = 0 and not (v_x ->> 'calza')::boolean, v_x::text);
  v_x := pg_temp.fila(v_j, 'acueducto', 3);
  perform pg_temp.reg('06.06 hidrantes: 2 en la valoración y 2 en la red, con sus códigos', (v_x ->> 'red')::numeric = 2 and (v_x ->> 'calza')::boolean and v_x ->> 'codigos' like 'TOR-%, TOR-%', v_x::text);
  v_x := pg_temp.fila(v_j, 'acueducto', 5);
  perform pg_temp.reg('06.07 un puntual (planta) no se compara por cantidad: dice con qué activo está amarrado y trae la nota de la fila',
     not (v_x ->> 'comparable')::boolean and not (v_x ? 'red') and not (v_x ? 'calza') and (v_x ->> 'activos')::integer = 1 and v_x ->> 'codigos' = pg_temp.cod(pl) and v_x ->> 'nota' = 'ZT10 nota de la fila', v_x::text);
  v_x := pg_temp.fila(v_j, 'alcantarillado_2', 1);
  perform pg_temp.reg('06.08 las dos hojas de alcantarillado vienen conciliadas: la (2) calza (90 de 90) y la de referencia no (90 de 500)',
     (v_x ->> 'calza')::boolean and (pg_temp.fila(v_j, 'alcantarillado', 1) ->> 'pct')::numeric = 18 and not (pg_temp.fila(v_j, 'alcantarillado', 1) ->> 'calza')::boolean
     and (pg_temp.fila(v_j, 'alcantarillado_2', 2) ->> 'activos')::integer = 0, v_x::text);
  perform pg_temp.reg('06.09 activos sin fila, agrupados: el proyectado, el «sin fila» y el nuevo de una inversión («fuera»), con sus metros',
     (select count(*) from jsonb_array_elements(v_j -> 'sin_fila') x where x ->> 'prefijo' = 'RED' and x ->> 'motivo' = 'proyectado' and (x ->> 'longitud_m')::numeric = 60) >= 1
     and (select count(*) from jsonb_array_elements(v_j -> 'sin_fila') x where x ->> 'prefijo' = 'RED' and x ->> 'motivo' = 'sin_fila' and (x ->> 'longitud_m')::numeric = 80) >= 1
     and (select count(*) from jsonb_array_elements(v_j -> 'sin_fila') x where x ->> 'prefijo' = 'RED' and x ->> 'motivo' = 'fuera' and (x ->> 'activos')::integer >= 1) >= 1
     and not exists (select 1 from jsonb_array_elements(v_j -> 'sin_fila') x where x ->> 'prefijo' = 'POZ'),
     (select string_agg(x ->> 'prefijo' || ':' || (x ->> 'motivo') || ':' || (x ->> 'activos'), ' ') from jsonb_array_elements(v_j -> 'sin_fila') x));
  perform pg_temp.reg('06.10 la conciliación dice de qué archivo sale, que es una propuesta, los totales por hoja y la tolerancia; sin datos de personas',
     v_j ->> 'fuente' like '%propuesta' and v_j -> 'valoracion' ->> 'archivo' = 'ZT10 valoracion de prueba.xlsx' and v_j -> 'amarre' ->> 'archivo' = 'ZT10 amarre de prueba.csv'
     and (v_j ->> 'tolerancia_pct')::numeric = 2 and jsonb_array_length(v_j -> 'hojas') = 3 and jsonb_array_length(v_j -> 'filas') = 8
     and (select (x ->> 'bcr0')::numeric from jsonb_array_elements(v_j -> 'hojas') x where x ->> 'hoja' = 'acueducto') = 5000
     and v_j::text !~* 'suscriptor|telefono|teléfono|cedula|cédula');

  -- ===================== 07. El color por edad del geovisor =====================
  -- (la tesela no se puede abrir desde SQL: se compara la del administrador con la del operador, que nunca recibe la fecha regulatoria)
  v_z := floor(redes.f_param('geovisor_zoom_red_completa'))::integer;
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT10 prueba: el operador con el geovisor');
  v_g := pg_temp.pt(50, 0);
  v_m := public.geoportal_redes_geovisor_mvt(a, v_z, pg_temp.tx(v_g, v_z), pg_temp.ty(v_g, v_z));
  v_m2 := public.geoportal_redes_geovisor_mvt(op, v_z, pg_temp.tx(v_g, v_z), pg_temp.ty(v_g, v_z));
  perform pg_temp.reg('07.01 tramos sin fecha de instalación y con fila: la tesela del administrador trae la edad de la fecha regulatoria (marcada «edad_reg»); la del operador de redes, no',
     length(v_m2) > 0 and length(v_m) > length(v_m2) and position('edad_reg'::bytea in decode(v_m, 'base64')) > 0, length(v_m) || ' caracteres contra ' || length(v_m2));
  perform pg_temp.reg('07.02 el supervisor de distribución recibe la misma tesela que el administrador',
     public.geoportal_redes_geovisor_mvt(sd, v_z, pg_temp.tx(v_g, v_z), pg_temp.ty(v_g, v_z)) = v_m);
  v_g := pg_temp.pt(20050, 20000);
  v_m := public.geoportal_redes_geovisor_mvt(a, v_z, pg_temp.tx(v_g, v_z), pg_temp.ty(v_g, v_z));
  v_m2 := public.geoportal_redes_geovisor_mvt(op, v_z, pg_temp.tx(v_g, v_z), pg_temp.ty(v_g, v_z));
  perform pg_temp.reg('07.04 la configuración del geovisor avisa que hay edad regulatoria (para la nota de la leyenda) a supervisores y administrador, no al operador',
     (public.geoportal_redes_geovisor(a) ->> 'edad_ref')::boolean and (public.geoportal_redes_geovisor(sd) ->> 'edad_ref')::boolean
     and (public.geoportal_redes_geovisor(op) ->> 'edad_ref') is null and public.geoportal_redes_geovisor(op)::text !~* 'regulator|valoraci|tarif');
  perform pg_temp.reg('07.03 la fecha de instalación de la ficha siempre gana: un tramo con fecha y con fila sale igual para el administrador y para el operador (sin fecha regulatoria)',
     length(v_m) > 0 and v_m = v_m2, length(v_m) || ' caracteres');

  -- ===================== 08. El amarre se puede volver a cargar: vale el último; el anterior queda =====================
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor) values ('val_amarre', 'ZT10 amarre de prueba 2.csv', md5('zt10-am2'), 1, 'ZT10 amarre de prueba', null, a) returning id into v_am2;
  insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion) values (v_am2, v_val, t4, 'acueducto', 2, 80, 'con_fila');
  v_j := public.geoportal_redes_valoracion(a);
  perform pg_temp.reg('08.01 con un amarre nuevo, el tramo que estaba «sin fila» queda con fila, y el que no viene en él queda «fuera»; el amarre anterior sigue guardado',
     (public.geoportal_redes_activo(a, pg_temp.cod(t4)) -> 'regulatorio' ->> 'remunerado')::boolean
     and public.geoportal_redes_activo(a, pg_temp.cod(t1)) -> 'regulatorio' ->> 'situacion' = 'fuera'
     and (pg_temp.fila(v_j, 'acueducto', 2) ->> 'red')::numeric = 80 and (select count(*) from redes.val_amarre where carga_id = v_am) = 11);
  insert into redes.ref_carga_eventos (carga_id, tipo, motivo, autor) values (v_am2, 'anular', 'ZT10 prueba: se anula el segundo amarre', a);
  perform pg_temp.reg('08.02 al anular esa carga (con motivo) vuelve a valer el amarre anterior',
     redes.f_ref_vigente('val_amarre') = v_am and (public.geoportal_redes_activo(a, pg_temp.cod(t1)) -> 'regulatorio' ->> 'remunerado')::boolean);

  -- ===================== 09. Tiempos con el volumen real =====================
  -- todos los tramos, conductos, hidrantes y válvulas de la base, amarrados a la valoración de prueba (lo que hará la carga real)
  insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor) values ('val_amarre', 'ZT10 amarre de volumen.csv', md5('zt10-vol'), 0, 'ZT10 amarre de prueba', null, a) returning id into v_am2;
  insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion)
  select v_am2, v_val, m.activo_id, h.hoja, case when h.hoja = 'acueducto' and m.prefijo in ('TOR', 'HID', 'VAL') then 3 when h.hoja = 'acueducto' then 1 + (m.activo_id % 2)::integer else 1 end,
         coalesce(m.longitud_m, 1), 'con_fila'
    from redes.activo_vigente_mat m
    join (values ('acueducto', 'acueducto'), ('alcantarillado', 'alcantarillado'), ('alcantarillado', 'alcantarillado_2')) h(sistema, hoja) on h.sistema = m.sistema
   where not m.retirado and not m.oculto and m.prefijo in ('RED', 'CON', 'COL', 'TOR', 'HID', 'VAL');
  get diagnostics v_n = row_count;
  analyze redes.val_amarre;
  select m.activo_id into v_real from redes.activo_vigente_mat m where m.prefijo = 'RED' and not m.retirado and m.activo_id not in (t1, t2, t3, t4, t5, t6) order by m.activo_id limit 1;
  v_real := coalesce(v_real, t1);
  select t.x, t.y into v_tx, v_ty from (select pg_temp.tx(ST_PointOnSurface(m.geom), v_z) as x, pg_temp.ty(ST_PointOnSurface(m.geom), v_z) as y
                                          from redes.activo_vigente_mat m where m.prefijo in ('RED', 'COL') and not m.retirado) t group by t.x, t.y order by count(*) desc limit 1;
  v_t0 := clock_timestamp(); v_j := public.geoportal_redes_valoracion(a); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_f := public.geoportal_redes_activo(a, pg_temp.cod(v_real)); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_m := public.geoportal_redes_geovisor_mvt(a, v_z, v_tx, v_ty); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_m2 := public.geoportal_redes_geovisor_mvt(a, v_z - 1, v_tx / 2, v_ty / 2); v_ms4 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS con %s amarres (todos los tramos, conductos, hidrantes y válvulas de esta base): conciliación %s ms · ficha de %s %s ms · tesela más cargada %s/%s/%s %s ms (%s kB) · tesela %s/%s/%s %s ms (%s kB)',
                   v_n, v_ms1, pg_temp.cod(v_real), v_ms2, v_z, v_tx, v_ty, v_ms3, round(length(v_m) * 0.75 / 1024), v_z - 1, v_tx / 2, v_ty / 2, v_ms4, round(length(v_m2) * 0.75 / 1024));
  perform pg_temp.reg('09.01 con el volumen real, la conciliación suma todo lo amarrado y la ficha de un tramo real trae su fila',
     (v_f -> 'regulatorio' ->> 'remunerado')::boolean
     and (select sum((x ->> 'activos')::integer) from jsonb_array_elements(v_j -> 'filas') x) = v_n, v_info);
  perform pg_temp.reg('09.02 TIEMPOS: la conciliación, la ficha y las teselas, cada llamada en menos de 5 s (el tope de la Edge es 30 s)', greatest(v_ms1, v_ms2, v_ms3, v_ms4) < 5000, v_info);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 10 (esperado: este ERROR deshace todo lo de la prueba)\n%\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_info, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
