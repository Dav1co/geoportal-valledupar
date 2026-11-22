-- =====================================================================
-- DOBLE LOCAL (solo pruebas del Code C; NO va en la migración): lo de la Torre B publicado que la base local no trae y que necesita la captura por punto.
-- Copiado de los paquetes publicados (rutas en ~/geoportal-consultas/tecnica/):
--   · tecnica.f_formularios: la publicada en el Corte 8 (campo_corte8/sql/25_reemplazos.sql, 9 claves); la base local traía un doble viejo de 7.
--   · tecnica.f_fecha_muestra (corte1_paso_a/sql/20_funciones_internas.sql) y tecnica.f_resolver_fecha_muestra (corte2_paso_a/sql/10_tablas_y_reglas.sql).
--   · public.geoportal_tec_obtener_formulario y geoportal_tec_resumen_operador: las del Corte 3 (corte3_paso_a/sql/20_funciones.sql).
--   · public.geoportal_tec_registrar_medicion: la VIGENTE, de la hora de inicio (14/11), con sus dos columnas en tecnica.registros.
-- =====================================================================

-- tecnica.formulario_variables.frecuencia_norma (Corte 2, corte2_paso_a/sql/10_tablas_y_reglas.sql): la columna y su CHECK, que la base local no traía.
alter table tecnica.formulario_variables add column if not exists frecuencia_norma text;
alter table tecnica.formulario_variables add constraint formulario_variables_frecuencia_check
  check (frecuencia_norma is null or frecuencia_norma in ('diaria', 'semanal', 'semestral', 'segun_mapa_riesgo'));

-- tecnica.formularios_config (Corte 2, corte2_paso_a/sql/10_tablas_y_reglas.sql): la tabla, sus disparadores y sus filas (Muestreo, 7 días).
create table tecnica.formularios_config (
  formulario      tecnica.formulario_clave primary key,
  dias_atras_max  smallint not null default 0 check (dias_atras_max between 0 and 31),
  activa          boolean not null default true,
  creado_en       timestamptz not null default clock_timestamp()
);
alter table tecnica.formularios_config enable row level security;
revoke all on tecnica.formularios_config from public, anon, authenticated;
create trigger t_no_borrar before delete   on tecnica.formularios_config for each row       execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on tecnica.formularios_config for each statement execute function tecnica.f_solo_agregar();

insert into tecnica.formularios_config (formulario, dias_atras_max)
select f.clave, case when f.clave = 'muestreo' then 7 else 0 end from tecnica.f_formularios() f;     -- Muestreo = 7 (confirmado por David)

CREATE OR REPLACE FUNCTION tecnica.f_formularios()
 RETURNS TABLE(clave text, nombre text, descripcion text, orden integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  values ('entrada',          'Entrada',                           'Agua cruda que ingresa a las plantas.', 1),
         ('salida',           'Salida',                            'Agua tratada que sale de las plantas.', 2),
         ('muestreo',         'Muestreo',                          'Muestreo en los puntos de la red y los tanques.', 3),
         ('danos_fallas',     'Daños o fallas',                    'Daños o fallas en la planta.', 4),
         ('mantenimiento',    'Mantenimiento, reparación e inversión', 'Mantenimiento, reparación e inversión.', 5),
         ('uso_quimicos',     'Uso de químicos',                   'Químicos usados en el proceso.', 6),
         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7),
         ('anomalia_compartida', 'Reportar anomalía',               'El mismo reporte de anomalías de Comercial, hecho desde Técnica.', 8),
         ('revision_compartida', 'Revisiones generales',            'La misma revisión general de Comercial, hecha desde Técnica.', 9);
$function$;

create or replace function tecnica.f_fecha_muestra(p_hora time, p_ahora timestamp default null) returns date
language plpgsql stable set search_path to 'pg_catalog', 'tecnica' as $$
declare
  v_ventana_min constant int := 60;
  v_ahora timestamp := coalesce(p_ahora, tecnica.f_ahora_bogota());
  v_hoy date := v_ahora::date;
begin
  if (v_hoy + p_hora) > (v_ahora + interval '5 minutes') then        -- se compara fecha+hora: sumar 5 minutos a un «time» daría la vuelta a las 00:00
    if v_ventana_min > 0 and v_ahora::time < make_interval(mins => v_ventana_min)::time and p_hora >= time '23:00' then
      return v_hoy - 1;
    end if;
    perform tecnica.f_error('La hora de la muestra es posterior a la hora actual. Revise la hora.');
  end if;
  return v_hoy;
end $$;

create or replace function tecnica.f_resolver_fecha_muestra(p_formulario text, p_hora time, p_fecha date, p_ahora timestamp default null) returns date
language plpgsql stable set search_path to 'pg_catalog', 'tecnica' as $$
declare v_ahora timestamp := coalesce(p_ahora, tecnica.f_ahora_bogota()); v_hoy date := v_ahora::date; v_n smallint;
begin
  if p_fecha is null then return tecnica.f_fecha_muestra(p_hora, p_ahora); end if;
  select c.dias_atras_max into v_n from tecnica.formularios_config c where c.formulario = p_formulario and c.activa;
  if coalesce(v_n, 0) = 0 then
    perform tecnica.f_error('Este formulario no admite elegir la fecha de la muestra: la fija el servidor.');
  end if;
  if p_fecha > v_hoy then perform tecnica.f_error('La fecha de la muestra no puede ser futura.'); end if;
  if p_fecha < v_hoy - v_n then
    perform tecnica.f_error('La fecha de la muestra no puede ser anterior al ' || to_char(v_hoy - v_n, 'DD/MM/YYYY') || ' (máximo ' || v_n || ' días atrás).');
  end if;
  if p_fecha = v_hoy and (v_hoy + p_hora) > (v_ahora + interval '5 minutes') then
    perform tecnica.f_error('La hora de la muestra es posterior a la hora actual. Revise la hora.');
  end if;
  return p_fecha;
end $$;

CREATE OR REPLACE FUNCTION public.geoportal_tec_obtener_formulario(p_solicitante text, p_formulario text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $$
declare v_email text; v_f record; v_ahora timestamp := tecnica.f_ahora_bogota(); v_hora time; v_dias int; v_tipos text[];
begin
  v_email := tecnica.f_autorizar_captura(p_solicitante, p_formulario);
  select * into v_f from tecnica.f_formularios() f where f.clave = p_formulario;
  if not found then perform tecnica.f_error('Formulario desconocido', 'P0002'); end if;
  -- Hora propuesta: ahora menos 15 minutos, sin cruzar la medianoche hacia el día anterior.
  v_hora := case when v_ahora::time < time '00:15' then time '00:00' else v_ahora::time - interval '15 minutes' end;
  select coalesce((select c.dias_atras_max from tecnica.formularios_config c where c.formulario = p_formulario and c.activa), 0) into v_dias;
  -- Tipos de punto que piden las variables «por punto» del formulario (nulo si no tiene ninguna).
  select array_agg(distinct fv.tipo_punto) into v_tipos from tecnica.formulario_variables fv join tecnica.variables v on v.id = fv.variable_id
   where fv.formulario = p_formulario and fv.alcance = 'por_punto' and fv.activa and v.activa;
  return jsonb_build_object(
    'formulario', jsonb_build_object('clave', v_f.clave, 'nombre', v_f.nombre, 'descripcion', v_f.descripcion),
    'fecha_hoy', to_char(v_ahora, 'YYYY-MM-DD'),
    'dias_atras_max', v_dias,
    'fecha_minima', to_char(v_ahora::date - v_dias, 'YYYY-MM-DD'),
    'hora_propuesta', to_char(v_hora, 'HH24:MI'),
    'plantas', coalesce((select jsonb_agg(jsonb_build_object('codigo', pl.codigo, 'nombre', pl.nombre) order by pl.id)
                           from tecnica.plantas pl where pl.activa), '[]'::jsonb),
    'puntos', coalesce((select jsonb_agg(jsonb_build_object('codigo', pu.codigo, 'nombre', pu.nombre, 'tipo', pu.tipo, 'planta', pl.codigo,
                                                            'zona', pu.zona, 'numero_informe', pu.numero_informe) order by pu.codigo)
                          from tecnica.puntos pu left join tecnica.plantas pl on pl.id = pu.planta_id
                         where pu.activo and (v_tipos is null or pu.tipo = any (v_tipos))), '[]'::jsonb),
    'variables', coalesce((
      select jsonb_agg(jsonb_build_object(
               'codigo', v.codigo, 'nombre', v.nombre, 'unidad', v.unidad, 'categoria', v.categoria, 'decimales', v.decimales,
               'orden', fv.orden, 'obligatoria', fv.obligatoria, 'alcance', fv.alcance, 'frecuencia_norma', fv.frecuencia_norma,
               'punto', case when pu.id is null then null else jsonb_build_object('codigo', pu.codigo, 'nombre', pu.nombre) end,
               'tipo_punto', case when fv.alcance = 'por_punto' then fv.tipo_punto end,
               'puntos', case when fv.alcance = 'por_punto' then coalesce((
                   select jsonb_agg(pq.codigo order by pq.codigo) from tecnica.puntos pq
                    where pq.activo and pq.tipo = fv.tipo_punto and (fv.punto_id is null or pq.id = fv.punto_id)), '[]'::jsonb) end)
             order by fv.orden, v.id)
        from tecnica.formulario_variables fv
        join tecnica.variables v on v.id = fv.variable_id
        left join tecnica.puntos pu on pu.id = fv.punto_id
       where fv.formulario = p_formulario and fv.activa and v.activa), '[]'::jsonb));
end $$;


CREATE OR REPLACE FUNCTION public.geoportal_tec_resumen_operador(p_solicitante text, p_formulario text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $$
declare v_email text; v_por_registro boolean; v_t timestamptz := clock_timestamp();     -- instante fijo: así el planificador puede usar los índices por fecha (con v_t directo no puede)
begin
  v_email := tecnica.f_autorizar_captura(p_solicitante, p_formulario);
  v_por_registro := coalesce((select c.dias_atras_max from tecnica.formularios_config c where c.formulario = p_formulario and c.activa), 0) > 0;
  return jsonb_build_object('formulario', p_formulario, 'ventana_horas', 24, 'base', case when v_por_registro then 'registro' else 'muestra' end, 'filas', coalesce((
    select jsonb_agg(jsonb_build_object(
             'variable', v.codigo, 'nombre', v.nombre, 'unidad', v.unidad, 'decimales', v.decimales,
             'planta', x.planta, 'planta_nombre', x.planta_nombre, 'zona', x.zona, 'zona_nombre', initcap(x.zona),
             'promedio', round(st.prom, 6), 'minimo', st.mn, 'maximo', st.mx,
             'punto', x.punto, 'punto_nombre', x.punto_nombre)
           order by fv.orden, v.id, x.orden_x)
      from tecnica.formulario_variables fv
      join tecnica.variables v on v.id = fv.variable_id
      cross join lateral (
        select null::text as planta, null::text as planta_nombre, null::bigint as pid, null::text as zona, null::text as punto, null::text as punto_nombre, null::bigint as puid, 0::bigint as orden_x where fv.alcance = 'ambas_plantas'
        union all
        select pl.codigo, pl.nombre, pl.id, null::text, null::text, null::text, null::bigint, pl.id from tecnica.plantas pl where fv.alcance = 'por_planta' and pl.activa
        union all
        select null::text, null::text, null::bigint, z.zona, null::text, null::text, null::bigint, z.o
          from (select zz.zona, case zz.zona when 'norte' then 1 when 'sur' then 2 else 3 end as o
                  from (select distinct pu.zona from tecnica.puntos pu where pu.activo and pu.tipo = 'muestreo' and pu.zona is not null) zz) z
         where fv.alcance = 'por_punto' and fv.tipo_punto = 'muestreo'
        union all
        -- Variables «por punto» que no son de muestreo (cloro en tanques, caudales de distribución): una fila por punto, no por zona.
        select null::text, null::text, null::bigint, null::text, pq.codigo, pq.nombre, pq.id, pq.id
          from tecnica.puntos pq
         where fv.alcance = 'por_punto' and fv.tipo_punto <> 'muestreo' and pq.activo and pq.tipo = fv.tipo_punto and (fv.punto_id is null or pq.id = fv.punto_id)) x
      left join lateral (
        select avg(s.valor) as prom, min(s.valor) as mn, max(s.valor) as mx
          from tecnica.v_registros_estado s
          left join tecnica.puntos sp on sp.id = s.punto_id
         where s.formulario = fv.formulario and s.variable_id = fv.variable_id
           and (fv.alcance <> 'por_planta' or s.planta_id is not distinct from x.pid)
           and (fv.alcance <> 'por_punto' or (fv.tipo_punto = 'muestreo' and sp.zona = x.zona) or (fv.tipo_punto <> 'muestreo' and s.punto_id is not distinct from x.puid))
           and not s.excluido
           and case when v_por_registro
                    then s.registrado_en >= v_t - interval '24 hours'
                    else s.muestra_ts >= v_t - interval '24 hours' and s.muestra_ts <= v_t + interval '5 minutes' end) st on true
     where fv.formulario = p_formulario and fv.activa and v.activa), '[]'::jsonb));
end $$;

-- La hora de inicio (pasada 14/11, campo/paquete_pasada_14nov/tecnica_inicio): las columnas de tecnica.registros y la registrar_medicion VIGENTE (11 parámetros).
-- Columnas: «if not exists» porque una reversa con registros que ya tienen inicio las CONSERVA (son historial).
alter table tecnica.registros add column if not exists inicio_en timestamptz;
alter table tecnica.registros add column if not exists inicio_origen text;

do $restricciones$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'tecnica.registros'::regclass and conname = 'ck_registro_inicio_origen') then
    alter table tecnica.registros add constraint ck_registro_inicio_origen check (inicio_origen in ('dispositivo', 'servidor'));
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'tecnica.registros'::regclass and conname = 'ck_registro_inicio_par') then
    alter table tecnica.registros add constraint ck_registro_inicio_par check ((inicio_en is null) = (inicio_origen is null));
  end if;
end $restricciones$;

comment on column tecnica.registros.inicio_en is 'Hora en que se abrió el formulario (celular: inicio_dispositivo). Nula en registros anteriores al 14/11/2026 o enviados por una pantalla vieja. Fin = registrado_en.';
comment on column tecnica.registros.inicio_origen is '«dispositivo» = hora del celular al abrir el formulario; «servidor» = hora del servidor. Nula si no hay inicio.';

-- Máximo de horas entre abrir el formulario y registrarlo (contrato común: max_horas_inicio = 12). Técnica no tiene tabla de parámetros: constante en función.
create or replace function tecnica.f_max_horas_inicio() returns integer
language sql immutable set search_path to 'pg_catalog' as $$ select 12 $$;
revoke all on function tecnica.f_max_horas_inicio() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.geoportal_tec_registrar_medicion(p_solicitante text, p_formulario text, p_planta text, p_hora_muestra text, p_valores jsonb, p_punto text DEFAULT NULL::text, p_clave_envio text DEFAULT NULL::text, p_ip text DEFAULT NULL::text, p_fecha_muestra date DEFAULT NULL::date, p_fuente text DEFAULT 'manual'::text, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'tecnica', 'pg_temp'
AS $function$
declare
  v_email text; v_hora time; v_fecha date; v_planta_id bigint; v_punto_id bigint; v_punto_tipo text; v_lote uuid := gen_random_uuid();
  v_item jsonb; v_cod text; v_val jsonb; v_num numeric; v_txt text; v_fuente text := lower(btrim(coalesce(p_fuente, '')));
  fv record; v_n int := 0; v_vistos text[] := '{}'; v_previo uuid; v_nprevio int;
  v_fin timestamptz;   -- hora del servidor que se guarda como registro (fin); la misma variable valida el inicio
begin
  v_email := tecnica.f_autorizar_captura(p_solicitante, p_formulario);
  if not exists (select 1 from tecnica.f_formularios() f where f.clave = p_formulario) then
    perform tecnica.f_error('Formulario desconocido', 'P0002');
  end if;
  if v_fuente not in ('manual', 'telemetria') then perform tecnica.f_error('La fuente del dato no es válida.'); end if;

  -- Reintento del mismo envío (celular con mala señal): devuelve el lote original sin duplicar.
  if p_clave_envio is not null then
    if p_clave_envio !~ '^[A-Za-z0-9_-]{8,80}$' then perform tecnica.f_error('Clave de envío inválida'); end if;
    perform pg_advisory_xact_lock(hashtextextended(v_email || '|' || p_clave_envio, 0));
    select r.lote_id, count(*) into v_previo, v_nprevio from tecnica.registros r
     where r.autor = v_email and r.clave_envio = p_clave_envio group by r.lote_id limit 1;
    if v_previo is not null then
      return jsonb_build_object('lote_id', v_previo, 'formulario', p_formulario, 'guardados', v_nprevio, 'duplicado', true);
    end if;
  end if;

  -- Hora y fecha de la muestra. Sin p_fecha_muestra: la fecha la fija el servidor (regla de siempre). Con ella: ver tecnica.f_resolver_fecha_muestra.
  begin
    v_hora := date_trunc('minute', btrim(coalesce(p_hora_muestra, ''))::time);
  exception when others then
    perform tecnica.f_error('La hora de la muestra no es válida. Use el formato HH:MM');
  end;
  v_fecha := tecnica.f_resolver_fecha_muestra(p_formulario, v_hora, p_fecha_muestra);

  -- Hora de inicio (contrato común, pasada 14/11): la del celular al abrir el formulario. Opcional: sin ella, el registro queda sin inicio (pantalla vieja).
  v_fin := clock_timestamp();
  if p_inicio_dispositivo is not null then
    if p_inicio_dispositivo > v_fin + interval '2 minutes' then
      perform tecnica.f_error('La hora de su celular está adelantada. Corríjala y vuelva a enviar: lo escrito y las fotos no se pierden.');
    end if;
    if p_inicio_dispositivo < v_fin - make_interval(hours => tecnica.f_max_horas_inicio()) then
      perform tecnica.f_error('Este formulario se abrió hace más de ' || tecnica.f_max_horas_inicio() || ' horas. Revise la hora de su celular o ábralo de nuevo.');
    end if;
  end if;

  if p_planta is not null and btrim(p_planta) <> '' then
    select pl.id into v_planta_id from tecnica.plantas pl where pl.codigo = lower(btrim(p_planta)) and pl.activa;
    if not found then perform tecnica.f_error('La planta no es válida'); end if;
  end if;

  if p_punto is not null and btrim(p_punto) <> '' then
    select pu.id, pu.tipo into v_punto_id, v_punto_tipo from tecnica.puntos pu
     where pu.codigo = upper(btrim(p_punto)) and pu.activo and (pu.planta_id is null or v_planta_id is null or pu.planta_id = v_planta_id);
    if not found then perform tecnica.f_error('El punto no existe, está inactivo o no corresponde a la planta elegida'); end if;
  end if;

  if p_valores is null or jsonb_typeof(p_valores) <> 'array' or jsonb_array_length(p_valores) not between 1 and 60 then
    perform tecnica.f_error('Debe enviar entre 1 y 60 valores');
  end if;

  for v_item in select e.value from jsonb_array_elements(p_valores) e loop
    if jsonb_typeof(v_item) <> 'object' then perform tecnica.f_error('Cada valor debe indicar su variable'); end if;
    v_cod := lower(btrim(coalesce(v_item ->> 'variable', '')));
    select f.alcance, f.punto_id, f.variable_id, f.tipo_punto, v.nombre into fv
      from tecnica.formulario_variables f join tecnica.variables v on v.id = f.variable_id
     where f.formulario = p_formulario and v.codigo = v_cod and f.activa and v.activa;
    if not found then perform tecnica.f_error('La variable «' || left(v_cod, 40) || '» no pertenece a este formulario'); end if;
    if v_cod = any (v_vistos) then perform tecnica.f_error('La variable «' || fv.nombre || '» viene repetida'); end if;
    v_vistos := v_vistos || v_cod;

    v_val := v_item -> 'valor';
    -- vacío: no se guarda (si la variable es obligatoria se detecta después)
    if v_val is null or jsonb_typeof(v_val) = 'null' or (jsonb_typeof(v_val) = 'string' and btrim(v_val #>> '{}') = '') then
      continue;
    end if;
    if jsonb_typeof(v_val) = 'number' then
      v_num := (v_val #>> '{}')::numeric;
    elsif jsonb_typeof(v_val) = 'string' then
      v_txt := btrim(v_val #>> '{}');
      if v_txt !~ '^-?[0-9]+(\.[0-9]+)?$' then
        perform tecnica.f_error('El valor de «' || fv.nombre || '» no es un número');
      end if;
      v_num := v_txt::numeric;
    else
      perform tecnica.f_error('El valor de «' || fv.nombre || '» no es un número');
    end if;

    if fv.alcance = 'por_planta' then
      if v_planta_id is null then perform tecnica.f_error('Elija la planta para «' || fv.nombre || '»'); end if;
      if (fv.punto_id is not null or v_punto_id is not null) and tecnica.f_regla_planta_con_punto() then
        perform tecnica.f_error('La variable «' || fv.nombre || '» es por planta: no lleva punto.');
      end if;
    elsif fv.alcance = 'por_punto' then
      if v_punto_id is null and fv.punto_id is null then perform tecnica.f_error('Elija el ' || tecnica.f_tipo_punto_texto(fv.tipo_punto) || ' para «' || fv.nombre || '».'); end if;
      if v_punto_id is not null and v_punto_tipo <> fv.tipo_punto then perform tecnica.f_error('El punto elegido no es un ' || tecnica.f_tipo_punto_texto(fv.tipo_punto) || '.'); end if;
    end if;
    if fv.punto_id is not null and v_punto_id is not null and fv.punto_id <> v_punto_id then
      perform tecnica.f_error('El punto elegido no corresponde a la variable «' || fv.nombre || '»');
    end if;

    insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, punto_id, valor, fecha_muestra, hora_muestra, autor, clave_envio, fuente, registrado_en, inicio_en, inicio_origen)
    values (v_lote, p_formulario, fv.variable_id, case when fv.alcance = 'por_planta' then v_planta_id end, coalesce(fv.punto_id, v_punto_id),
            v_num, v_fecha, v_hora, v_email, p_clave_envio, v_fuente, v_fin, p_inicio_dispositivo, case when p_inicio_dispositivo is not null then 'dispositivo' end);
    v_n := v_n + 1;
  end loop;

  if v_n = 0 then perform tecnica.f_error('No hay valores para guardar'); end if;

  -- Obligatorias que no llegaron con valor.
  for fv in
    select v.nombre from tecnica.formulario_variables f join tecnica.variables v on v.id = f.variable_id
     where f.formulario = p_formulario and f.activa and v.activa and f.obligatoria
       and not exists (select 1 from tecnica.registros r where r.lote_id = v_lote and r.variable_id = f.variable_id)
     order by f.orden limit 1
  loop
    perform tecnica.f_error('Falta el valor de «' || fv.nombre || '»');
  end loop;

  insert into tecnica.senal_cambio (tabla, planta_id) values ('registros', v_planta_id);
  perform tecnica.f_auditar(v_email, 'tec_registrar', v_lote::text,
                            jsonb_build_object('formulario', p_formulario, 'valores', v_n, 'fuente', v_fuente, 'fecha_distinta_de_hoy', p_fecha_muestra is not null, 'con_inicio', p_inicio_dispositivo is not null), p_ip);

  -- La confirmación NO incluye marcas de rango ni la hora del servidor (el operador no las ve).
  return jsonb_build_object('lote_id', v_lote, 'formulario', p_formulario, 'fecha_muestra', v_fecha,
                            'hora_muestra', to_char(v_hora, 'HH24:MI'), 'guardados', v_n, 'duplicado', false);
end $function$
;

revoke all on function tecnica.f_fecha_muestra(time, timestamp), tecnica.f_resolver_fecha_muestra(text, time, date, timestamp) from public, anon, authenticated;
revoke all on function public.geoportal_tec_registrar_medicion(text, text, text, text, jsonb, text, text, text, date, text, timestamptz), public.geoportal_tec_obtener_formulario(text, text),
  public.geoportal_tec_resumen_operador(text, text) from public, anon, authenticated;
grant execute on function public.geoportal_tec_registrar_medicion(text, text, text, text, jsonb, text, text, text, date, text, timestamptz), public.geoportal_tec_obtener_formulario(text, text),
  public.geoportal_tec_resumen_operador(text, text) to service_role;
