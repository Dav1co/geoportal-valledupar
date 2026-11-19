-- DOBLE LOCAL (solo para las pruebas de Code A; NO se corre en producción): las tablas de los reportes de campo de Comercial que toca el Corte 15
-- (un «sin_agua» hecho desde Comercial se asocia al evento y se cierra en bloque; respuesta de David del 19-nov).
-- Regla de David (17-nov): los dobles llevan los CHECK, las llaves y los disparadores de producción de toda tabla en la que escriban las pruebas.
-- · campo.reportes, campo.reporte_eventos, campo.estados_reporte, campo.subtipos_reporte, campo.causales, campo.causales_tipos, campo.reporte_fotos, campo.reporte_datos_sensibles y la
--   vista campo.v_reportes_estado: TEXTO de pg_dump de la base local de campo (los paquetes de campo de Comercial hasta la pasada del 14-nov + el Corte 8 de
--   Técnica: sql/campo_corte8/pruebas_locales/rehacer_base.sh), con sus CHECK, llaves, índices y disparadores. Las funciones de esos disparadores, con su texto.
-- · NO se trae el disparador t_encolar_constancia (AFTER INSERT ON campo.reportes → salida.f_disparar_campo()): es de la cola de constancias (esquema «salida»),
--   que esta base no tiene; no toca nada de este corte.
-- · campo.tipos_reporte y campo.grupos_reporte: al doble del Corte 14 se le ponen las columnas, los CHECK y los disparadores de producción, y el catálogo real
--   (9 grupos, 28 tipos): el ensayo del 19-nov falló en producción porque una prueba contaba los 2 tipos del doble.
-- · campo.tipo_campos y campo.tipo_fotos siguen siendo las del doble del Corte 14 (no se escriben).
set check_function_bodies = off;
CREATE OR REPLACE FUNCTION campo.f_codigo_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if new.codigo is distinct from old.codigo then
    raise exception 'El código de % no se puede cambiar: cree uno nuevo y desactive este', tg_table_name using errcode = '55000';
  end if;
  if tg_table_name = 'subtipos_reporte' then
    if new.tipo_id is distinct from old.tipo_id then
      raise exception 'Un subtipo no se puede mover a otro tipo: cree uno nuevo y desactive este' using errcode = '55000';
    end if;
  end if;
  return new;
end $function$

;
CREATE OR REPLACE FUNCTION campo.f_catalogo_d_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_table_name in ('tipo_campos', 'tipo_fotos') then
    if new.codigo is distinct from old.codigo or new.tipo_id is distinct from old.tipo_id then
      raise exception 'El código y el tipo de % no se pueden cambiar: cree uno nuevo y desactive este', tg_table_name using errcode = '55000';
    end if;
  end if;
  if tg_table_name = 'tipo_campos' then
    if new.tipo_dato is distinct from old.tipo_dato or new.sensible is distinct from old.sensible then
      raise exception 'El tipo de dato y la marca «sensible» de un campo no se pueden cambiar: cree uno nuevo y desactive este' using errcode = '55000';
    end if;
    -- Las opciones no se quitan (se desactivan): los reportes viejos guardan su código
    if old.opciones is not null and exists (select 1 from jsonb_array_elements(old.opciones) o
                                             where not exists (select 1 from jsonb_array_elements(coalesce(new.opciones, '[]'::jsonb)) n where n ->> 'codigo' = o ->> 'codigo')) then
      raise exception 'Las opciones de un campo no se quitan: desactívelas («activo»: false)' using errcode = '55000';
    end if;
  elsif tg_table_name = 'causales' then
    if new.codigo is distinct from old.codigo then
      raise exception 'El código de la causal no se puede cambiar: cree una nueva y desactive esta' using errcode = '55000';
    end if;
  elsif tg_table_name = 'causales_tipos' then
    if new.causal_id is distinct from old.causal_id or new.tipo_id is distinct from old.tipo_id then
      raise exception 'La relación causal-tipo no se mueve: desactívela y cree otra' using errcode = '55000';
    end if;
  elsif tg_table_name = 'tipos_reporte' then
    if old.prefijo_consecutivo is not null and new.prefijo_consecutivo is distinct from old.prefijo_consecutivo then
      raise exception 'El prefijo del consecutivo no se puede cambiar una vez asignado' using errcode = '55000';
    end if;
  elsif tg_table_name = 'consecutivos' then
    if new.tipo_id is distinct from old.tipo_id or new.ultimo is distinct from old.ultimo + 1 then
      raise exception 'El consecutivo solo avanza de uno en uno' using errcode = '42501';
    end if;
    new.actualizado_en := clock_timestamp();
  end if;
  return new;
end $function$

;
CREATE OR REPLACE FUNCTION campo.f_reporte_coherente()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'campo', 'pg_temp'
AS $function$
declare v_gen boolean;
begin
  if new.subtipo_id is not null and not exists (select 1 from campo.subtipos_reporte s where s.id = new.subtipo_id and s.tipo_id = new.tipo_id) then
    raise exception 'El subtipo no pertenece al tipo del reporte' using errcode = '22023';
  end if;
  select t.genera_resultado into v_gen from campo.tipos_reporte t where t.id = new.tipo_id;
  if coalesce(v_gen, false) <> (new.resultado is not null) then
    raise exception 'El resultado no corresponde al tipo del reporte' using errcode = '22023';
  end if;
  if new.causal_id is not null and not exists (
       select 1 from campo.causales c where c.id = new.causal_id
          and (c.general or exists (select 1 from campo.causales_tipos ct where ct.causal_id = c.id and ct.tipo_id = new.tipo_id))) then
    raise exception 'La causal no aplica al tipo del reporte' using errcode = '22023';
  end if;
  return new;
end $function$

;
CREATE OR REPLACE FUNCTION campo.f_evento_coherente()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'campo', 'pg_temp'
AS $function$
declare v_est campo.estados_reporte%rowtype;
begin
  if new.estado_nuevo is not null then
    select * into v_est from campo.estados_reporte where codigo = new.estado_nuevo;
    if not v_est.activo then raise exception 'El estado % está desactivado', new.estado_nuevo using errcode = '22023'; end if;
    if new.tipo_evento = 'cambio_estado' then
      if not v_est.cambio_manual then raise exception 'El estado % no se puede poner a mano', new.estado_nuevo using errcode = '22023'; end if;
      if v_est.exige_motivo and new.motivo is null then raise exception 'El estado % exige un motivo', new.estado_nuevo using errcode = '22023'; end if;
    end if;
  end if;
  if new.tipo_evento = 'vincular_duplicado' then
    if new.estado_nuevo is distinct from 'duplicado' then raise exception 'Un vínculo de duplicado deja el reporte en estado duplicado' using errcode = '22023'; end if;
    if campo.f_estado_actual(new.reporte_original_id) = 'duplicado' then
      raise exception 'El reporte original ya es un duplicado de otro: apunte al original verdadero' using errcode = '55000';
    end if;
    if exists (select 1 from (select distinct e.reporte_id from campo.reporte_eventos e
                               where e.reporte_original_id = new.reporte_id and e.tipo_evento = 'vincular_duplicado') h
                where campo.f_original_actual(h.reporte_id) = new.reporte_id) then
      raise exception 'Este reporte es el original de otros duplicados: no puede ser duplicado a su vez' using errcode = '55000';
    end if;
  end if;
  return new;
end $function$

;
CREATE OR REPLACE FUNCTION campo.f_estado_actual(p_reporte uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'campo', 'pg_temp'
AS $function$
  select coalesce(
    (select e.estado_nuevo from campo.reporte_eventos e where e.reporte_id = p_reporte and e.estado_nuevo is not null order by e.id desc limit 1),
    (select s.codigo from campo.estados_reporte s where s.inicial));
$function$

;
CREATE OR REPLACE FUNCTION campo.f_original_actual(p_reporte uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'campo', 'pg_temp'
AS $function$
  select case when x.estado_nuevo = 'duplicado' then x.reporte_original_id end
    from (select e.estado_nuevo, e.reporte_original_id from campo.reporte_eventos e
           where e.reporte_id = p_reporte and e.estado_nuevo is not null order by e.id desc limit 1) x;
$function$

;
CREATE OR REPLACE FUNCTION campo.f_tipo_general(p_codigo text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'campo', 'pg_temp'
AS $function$
  select exists (select 1 from campo.tipos_reporte t
                  where t.codigo = p_codigo
                    and not (exists (select 1 from campo.tipo_campos c where c.tipo_id = t.id and c.activo) or exists (select 1 from campo.tipo_fotos f where f.tipo_id = t.id and f.activo)
                             or t.genera_resultado or t.prefijo_consecutivo is not null)) $function$

;
-- ---------- el catálogo (campo.grupos_reporte y campo.tipos_reporte) como en producción: el doble del Corte 14 traía solo las columnas que se leían y 2 tipos.
-- La migración del Corte 15 ESCRIBE en campo.tipos_reporte (agrega «sin_agua»), así que aquí se le ponen las columnas, los CHECK, el índice y los disparadores
-- reales, y los 9 grupos y 28 tipos del catálogo (los de los paquetes de campo hasta el Corte 8). Las 2 filas del doble anterior se conservan.
alter table campo.grupos_reporte alter column orden set default 100, add column creado_en timestamptz not null default clock_timestamp(),
  add constraint grupos_reporte_codigo_check check (codigo ~ '^[a-z][a-z0-9_]{1,39}$'),
  add constraint grupos_reporte_nombre_check check (length(btrim(nombre)) >= 2 and length(btrim(nombre)) <= 100);
alter table campo.tipos_reporte alter column orden set default 100,
  add column exige_texto boolean not null default false, add column exige_subtipo boolean not null default false, add column creado_en timestamptz not null default clock_timestamp(),
  add column fotos_min smallint, add column fotos_max smallint, add column requiere_contrato text not null default 'opcional', add column limite_ventana integer,
  add constraint tipos_contrato_ck check (requiere_contrato = any (array['si', 'no', 'opcional'])),
  add constraint tipos_fotos_ck check ((fotos_max is null or fotos_max >= 1 and fotos_max <= 10) and (fotos_min is null or fotos_min >= 0 and fotos_min <= 10) and (fotos_min is null or fotos_max is null or fotos_min <= fotos_max)),
  add constraint tipos_limite_ck check (limite_ventana is null or limite_ventana >= 1 and limite_ventana <= 1000),
  add constraint tipos_prefijo_ck check (prefijo_consecutivo is null or prefijo_consecutivo ~ '^[A-Z]{2,6}$'),
  add constraint tipos_reporte_codigo_check check (codigo ~ '^[a-z][a-z0-9_]{1,59}$'),
  add constraint tipos_reporte_nombre_check check (length(btrim(nombre)) >= 2 and length(btrim(nombre)) <= 160);
create unique index tipos_reporte_prefijo_key on campo.tipos_reporte (prefijo_consecutivo) where prefijo_consecutivo is not null;
create trigger t_codigo_inmutable before update on campo.grupos_reporte for each row execute function campo.f_codigo_inmutable();
create trigger t_no_borrar before delete on campo.grupos_reporte for each row execute function campo.f_solo_agregar();
create trigger t_no_vaciar before truncate on campo.grupos_reporte for each statement execute function campo.f_solo_agregar();
create trigger t_codigo_inmutable before update on campo.tipos_reporte for each row execute function campo.f_codigo_inmutable();
create trigger t_d_inmutable before update on campo.tipos_reporte for each row execute function campo.f_catalogo_d_inmutable();
create trigger t_no_borrar before delete on campo.tipos_reporte for each row execute function campo.f_solo_agregar();
create trigger t_no_vaciar before truncate on campo.tipos_reporte for each statement execute function campo.f_solo_agregar();
insert into campo.grupos_reporte (codigo, nombre, orden, activo) values ('comercial_perdidas', 'Comercial y pérdidas', 1, 't') on conflict (codigo) do nothing;
insert into campo.grupos_reporte (codigo, nombre, orden, activo) values ('red_acueducto', 'Red de acueducto', 2, 't') on conflict (codigo) do nothing;
insert into campo.grupos_reporte (codigo, nombre, orden, activo) values ('alcantarillado', 'Alcantarillado', 3, 't') on conflict (codigo) do nothing;
insert into campo.grupos_reporte (codigo, nombre, orden, activo) values ('terceros', 'Terceros', 4, 't') on conflict (codigo) do nothing;
insert into campo.grupos_reporte (codigo, nombre, orden, activo) values ('cartera', 'Gestión de cartera', 5, 'f') on conflict (codigo) do nothing;
insert into campo.grupos_reporte (codigo, nombre, orden, activo) values ('perdidas_formatos', 'Pérdidas (instalaciones)', 6, 'f') on conflict (codigo) do nothing;
insert into campo.grupos_reporte (codigo, nombre, orden, activo) values ('pqr', 'PQR', 7, 'f') on conflict (codigo) do nothing;
insert into campo.grupos_reporte (codigo, nombre, orden, activo) values ('facturacion', 'Facturación', 8, 't') on conflict (codigo) do nothing;
insert into campo.grupos_reporte (codigo, nombre, orden, activo) values ('otros', 'Otros', 9, 't') on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'acometida_sin_permiso', 'Posible acometida sin permiso', 1, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'comercial_perdidas' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'reconexion', 'Posible reconexión', 2, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'comercial_perdidas' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'fraude', 'Posible fraude', 3, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'comercial_perdidas' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'anomalia_medicion', 'Posible anomalía en la medición', 4, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'comercial_perdidas' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'uso_distinto', 'Posible uso distinto del declarado', 5, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'comercial_perdidas' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'predio_sin_contrato', 'Predio con servicio sin contrato asignado (por verificar)', 6, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'comercial_perdidas' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'dano_red_acueducto', 'Daño en la red (fuga visible)', 1, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'red_acueducto' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'tapa_caja_acueducto', 'Tapa o caja de medidor o válvula rota o faltante', 2, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'red_acueducto' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'fuga_acometida', 'Fuga en acometida', 3, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'red_acueducto' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'caja_medidor_danada', 'Caja de medidor dañada', 4, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'red_acueducto' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'dano_red_alcantarillado', 'Daño en la red (hundimiento, colapso, rebose)', 1, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'alcantarillado' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'tapa_manhole', 'Daño en tapa de manhole (rota, hundida o faltante)', 2, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'alcantarillado' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'rejilla_sumidero', 'Daño en rejilla o sumidero', 3, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'alcantarillado' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'conexion_errada', 'Conexión errada de alcantarillado', 4, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'alcantarillado' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'dano_obra_terceros', 'Daño por obra de terceros', 1, 'f', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'terceros' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'investigacion_ubicacion', 'Investigación de ubicación del predio', 1, 'f', 'f', 'f', '3', '6', 'si', 't', 'INV', '20' from campo.grupos_reporte g where g.codigo = 'cartera' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'levantamiento_acometida', 'Levantamiento de la acometida', 2, 'f', 'f', 'f', '2', '6', 'si', 't', 'LEV', '20' from campo.grupos_reporte g where g.codigo = 'cartera' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'suspension', 'Suspensión', 3, 'f', 'f', 'f', '3', '6', 'si', 't', 'SUS', '20' from campo.grupos_reporte g where g.codigo = 'cartera' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'corte', 'Corte', 4, 'f', 't', 'f', '3', '6', 'si', 't', 'COR', '20' from campo.grupos_reporte g where g.codigo = 'cartera' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'verificacion_posterior', 'Verificación posterior al corte o a la suspensión', 5, 'f', 'f', 'f', '1', '4', 'si', 't', 'VER', '20' from campo.grupos_reporte g where g.codigo = 'cartera' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'reinstalacion', 'Reinstalación del servicio (tras una suspensión)', 6, 'f', 'f', 'f', '2', '4', 'si', 't', 'REI', '20' from campo.grupos_reporte g where g.codigo = 'cartera' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'reconexion_servicio', 'Reconexión del servicio (tras un corte)', 7, 'f', 't', 'f', '2', '4', 'si', 't', 'REC', '20' from campo.grupos_reporte g where g.codigo = 'cartera' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'cambio_medidor', 'Cambio de medidor', 8, 'f', 'f', 'f', '2', '6', 'si', 't', 'CME', '20' from campo.grupos_reporte g where g.codigo = 'cartera' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'instalacion_medidor', 'Instalación de medidor', 1, 'f', 'f', 'f', '3', '7', 'si', 't', 'IME', '20' from campo.grupos_reporte g where g.codigo = 'perdidas_formatos' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'instalacion_acometida', 'Instalación de acometida', 2, 'f', 'f', 'f', '3', '6', 'opcional', 't', 'IAC', '20' from campo.grupos_reporte g where g.codigo = 'perdidas_formatos' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'revision_pqr', 'Revisión PQR', 1, 'f', 'f', 'f', '2', '6', 'si', 't', 'PQR', '20' from campo.grupos_reporte g where g.codigo = 'pqr' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'revision_previa', 'Revisiones generales', 1, 'f', 'f', 't', '2', '6', 'si', 't', 'RPV', '20' from campo.grupos_reporte g where g.codigo = 'facturacion' on conflict (codigo) do nothing;
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) select g.id, 'otro', 'Otro', 1, 't', 'f', 't', NULL, NULL, 'opcional', 'f', NULL, NULL from campo.grupos_reporte g where g.codigo = 'otros' on conflict (codigo) do nothing;

\restrict ZIkDJojcgNUjHmW8GGNQFql3dBuDuA72tZSzTPy60ImC4kMTO1tSYsI5a2U5vI4

CREATE TABLE campo.estados_reporte (
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    inicial boolean DEFAULT false NOT NULL,
    exige_motivo boolean DEFAULT false NOT NULL,
    cambio_manual boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT estados_reporte_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,29}$'::text)),
    CONSTRAINT estados_reporte_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 60)))
);

CREATE TABLE campo.reporte_datos_sensibles (
    reporte_id uuid NOT NULL,
    datos jsonb NOT NULL,
    registrado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT reporte_datos_sensibles_datos_check CHECK (((jsonb_typeof(datos) = 'object'::text) AND (datos <> '{}'::jsonb) AND (octet_length((datos)::text) <= 4096)))
);

CREATE TABLE campo.reporte_eventos (
    id bigint NOT NULL,
    reporte_id uuid NOT NULL,
    tipo_evento text NOT NULL,
    estado_nuevo text,
    reporte_original_id uuid,
    acta_id uuid,
    motivo text,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT evento_acta_ck CHECK (((tipo_evento = 'vincular_acta'::text) = (acta_id IS NOT NULL))),
    CONSTRAINT evento_estado_ck CHECK (((tipo_evento = ANY (ARRAY['cambio_estado'::text, 'vincular_duplicado'::text])) = (estado_nuevo IS NOT NULL))),
    CONSTRAINT evento_motivo_ck CHECK (((tipo_evento <> ALL (ARRAY['ocultar'::text, 'reincluir'::text, 'vincular_duplicado'::text, 'nota'::text])) OR (motivo IS NOT NULL))),
    CONSTRAINT evento_no_a_si_mismo_ck CHECK (((reporte_original_id IS NULL) OR (reporte_original_id <> reporte_id))),
    CONSTRAINT evento_original_ck CHECK (((tipo_evento = 'vincular_duplicado'::text) = (reporte_original_id IS NOT NULL))),
    CONSTRAINT reporte_eventos_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT reporte_eventos_motivo_check CHECK (((motivo IS NULL) OR ((length(btrim(motivo)) >= 10) AND (length(btrim(motivo)) <= 1000)))),
    CONSTRAINT reporte_eventos_tipo_evento_check CHECK ((tipo_evento = ANY (ARRAY['cambio_estado'::text, 'ocultar'::text, 'reincluir'::text, 'vincular_duplicado'::text, 'nota'::text, 'vincular_acta'::text])))
);

CREATE TABLE campo.reporte_fotos (
    id bigint NOT NULL,
    reporte_id uuid NOT NULL,
    orden smallint NOT NULL,
    ruta_storage text NOT NULL,
    tamano_bytes integer NOT NULL,
    tipo_mime text NOT NULL,
    registrada_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    etiqueta text,
    CONSTRAINT reporte_fotos_etiqueta_check CHECK (((etiqueta IS NULL) OR (etiqueta ~ '^[a-z][a-z0-9_]{1,39}$'::text))),
    CONSTRAINT reporte_fotos_orden_check CHECK (((orden >= 1) AND (orden <= 10))),
    CONSTRAINT reporte_fotos_ruta_storage_check CHECK ((ruta_storage ~ '^reportes/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}/[0-9]{1,2}\.jpg$'::text)),
    CONSTRAINT reporte_fotos_tamano_bytes_check CHECK ((tamano_bytes > 0)),
    CONSTRAINT reporte_fotos_tipo_mime_check CHECK ((tipo_mime = 'image/jpeg'::text))
);

CREATE TABLE campo.reportes (
    id uuid NOT NULL,
    seq bigint NOT NULL,
    tipo_id bigint NOT NULL,
    subtipo_id bigint,
    descripcion text,
    contrato text,
    contrato_verificado boolean,
    lat numeric(9,6) NOT NULL,
    lon numeric(9,6) NOT NULL,
    geom public.geometry GENERATED ALWAYS AS (public.st_setsrid(public.st_makepoint((lon)::double precision, (lat)::double precision), 4326)) STORED,
    precision_m numeric(8,1),
    riesgo_inmediato boolean DEFAULT false NOT NULL,
    origen text NOT NULL,
    fuera_de_zona boolean DEFAULT false NOT NULL,
    autor text NOT NULL,
    registrado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    datos jsonb,
    resultado text,
    causal_id bigint,
    consecutivo_num bigint,
    consecutivo text,
    orden_trabajo_id uuid,
    inicio_en timestamp with time zone,
    inicio_origen text,
    area text DEFAULT 
CASE
    WHEN (current_setting('geoportal.via_tecnica'::text, true) = 'on'::text) THEN 'tecnica'::text
    ELSE NULL::text
END,
    CONSTRAINT reportes_area_ck CHECK (((area IS NULL) OR (area = 'tecnica'::text))),
    CONSTRAINT reportes_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT reportes_causal_ck CHECK (((causal_id IS NOT NULL) = (NOT (resultado IS DISTINCT FROM 'inefectivo'::text)))),
    CONSTRAINT reportes_consecutivo_ck CHECK ((((consecutivo IS NULL) = (consecutivo_num IS NULL)) AND ((consecutivo_num IS NULL) OR (consecutivo_num >= 1)))),
    CONSTRAINT reportes_contrato_check CHECK (((contrato IS NULL) OR (contrato ~ '^[A-Za-z0-9-]{1,20}$'::text))),
    CONSTRAINT reportes_datos_ck CHECK (((datos IS NULL) OR ((jsonb_typeof(datos) = 'object'::text) AND (octet_length((datos)::text) <= 4096)))),
    CONSTRAINT reportes_descripcion_check CHECK (((descripcion IS NULL) OR (length(descripcion) <= 1000))),
    CONSTRAINT reportes_inicio_origen_ck CHECK (((inicio_origen IS NULL) OR (inicio_origen = ANY (ARRAY['dispositivo'::text, 'servidor'::text])))),
    CONSTRAINT reportes_inicio_par_ck CHECK (((inicio_en IS NULL) = (inicio_origen IS NULL))),
    CONSTRAINT reportes_lat_check CHECK (((lat >= ('-90'::integer)::numeric) AND (lat <= (90)::numeric))),
    CONSTRAINT reportes_lon_check CHECK (((lon >= ('-180'::integer)::numeric) AND (lon <= (180)::numeric))),
    CONSTRAINT reportes_origen_check CHECK ((origen = ANY (ARRAY['campo'::text, 'escritorio'::text]))),
    CONSTRAINT reportes_precision_m_check CHECK (((precision_m IS NULL) OR ((precision_m >= (0)::numeric) AND (precision_m <= (100000)::numeric)))),
    CONSTRAINT reportes_resultado_ck CHECK (((resultado IS NULL) OR (resultado = ANY (ARRAY['efectivo'::text, 'inefectivo'::text]))))
);

COMMENT ON COLUMN campo.reportes.inicio_en IS 'Pasada 14/11: hora en que se abrió el formulario (del celular: inicio_origen = dispositivo). Fin = registrado_en (servidor).';

COMMENT ON COLUMN campo.reportes.area IS 'Corte 8 de Técnica: área que hizo el reporte. Nulo = Comercial; tecnica = hecho desde Técnica (entrada del modo Redes).';

CREATE VIEW campo.v_reportes_estado AS
 SELECT r.id,
    r.seq,
    r.tipo_id,
    r.subtipo_id,
    r.descripcion,
    r.contrato,
    r.contrato_verificado,
    r.lat,
    r.lon,
    r.geom,
    r.precision_m,
    r.riesgo_inmediato,
    r.origen,
    r.fuera_de_zona,
    r.autor,
    r.registrado_en,
    COALESCE(es.estado_nuevo, ( SELECT s.codigo
           FROM campo.estados_reporte s
          WHERE s.inicial)) AS estado,
    es.creado_en AS estado_desde,
        CASE
            WHEN (es.estado_nuevo = 'duplicado'::text) THEN es.reporte_original_id
            ELSE NULL::uuid
        END AS reporte_original_id,
    COALESCE((oc.tipo_evento = 'ocultar'::text), false) AS oculto,
    oc.creado_en AS oculto_desde,
    (( SELECT count(*) AS count
           FROM campo.reporte_fotos f
          WHERE (f.reporte_id = r.id)))::integer AS n_fotos,
    r.consecutivo,
    r.resultado,
    r.causal_id,
    r.orden_trabajo_id,
    r.datos,
    (EXISTS ( SELECT 1
           FROM campo.reporte_datos_sensibles ds
          WHERE (ds.reporte_id = r.id))) AS tiene_datos_sensibles,
    r.inicio_en,
    r.inicio_origen
   FROM ((campo.reportes r
     LEFT JOIN LATERAL ( SELECT e.estado_nuevo,
            e.reporte_original_id,
            e.creado_en
           FROM campo.reporte_eventos e
          WHERE ((e.reporte_id = r.id) AND (e.estado_nuevo IS NOT NULL))
          ORDER BY e.id DESC
         LIMIT 1) es ON (true))
     LEFT JOIN LATERAL ( SELECT e.tipo_evento,
            e.creado_en
           FROM campo.reporte_eventos e
          WHERE ((e.reporte_id = r.id) AND (e.tipo_evento = ANY (ARRAY['ocultar'::text, 'reincluir'::text])))
          ORDER BY e.id DESC
         LIMIT 1) oc ON (true));

CREATE TABLE campo.causales (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    general boolean DEFAULT false NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT causales_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,39}$'::text)),
    CONSTRAINT causales_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)))
);

ALTER TABLE campo.causales ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.causales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE campo.causales_tipos (
    causal_id bigint NOT NULL,
    tipo_id bigint NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);

ALTER TABLE campo.reporte_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.reporte_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE campo.reporte_fotos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.reporte_fotos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE campo.reportes ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.reportes_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE campo.subtipos_reporte (
    id bigint NOT NULL,
    tipo_id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT subtipos_reporte_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT subtipos_reporte_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)))
);

ALTER TABLE campo.subtipos_reporte ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.subtipos_reporte_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE ONLY campo.causales
    ADD CONSTRAINT causales_codigo_key UNIQUE (codigo);

ALTER TABLE ONLY campo.causales
    ADD CONSTRAINT causales_pkey PRIMARY KEY (id);

ALTER TABLE ONLY campo.causales_tipos
    ADD CONSTRAINT causales_tipos_pkey PRIMARY KEY (causal_id, tipo_id);

ALTER TABLE ONLY campo.estados_reporte
    ADD CONSTRAINT estados_reporte_pkey PRIMARY KEY (codigo);

ALTER TABLE ONLY campo.reporte_datos_sensibles
    ADD CONSTRAINT reporte_datos_sensibles_pkey PRIMARY KEY (reporte_id);

ALTER TABLE ONLY campo.reporte_eventos
    ADD CONSTRAINT reporte_eventos_pkey PRIMARY KEY (id);

ALTER TABLE ONLY campo.reporte_fotos
    ADD CONSTRAINT reporte_fotos_pkey PRIMARY KEY (id);

ALTER TABLE ONLY campo.reporte_fotos
    ADD CONSTRAINT reporte_fotos_reporte_id_orden_key UNIQUE (reporte_id, orden);

ALTER TABLE ONLY campo.reporte_fotos
    ADD CONSTRAINT reporte_fotos_ruta_storage_key UNIQUE (ruta_storage);

ALTER TABLE ONLY campo.reportes
    ADD CONSTRAINT reportes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY campo.reportes
    ADD CONSTRAINT reportes_seq_key UNIQUE (seq);

ALTER TABLE ONLY campo.subtipos_reporte
    ADD CONSTRAINT subtipos_reporte_pkey PRIMARY KEY (id);

ALTER TABLE ONLY campo.subtipos_reporte
    ADD CONSTRAINT subtipos_reporte_tipo_id_codigo_key UNIQUE (tipo_id, codigo);

CREATE UNIQUE INDEX estados_reporte_un_inicial ON campo.estados_reporte USING btree (inicial) WHERE inicial;

CREATE INDEX reporte_eventos_original_idx ON campo.reporte_eventos USING btree (reporte_original_id) WHERE (reporte_original_id IS NOT NULL);

CREATE INDEX reporte_eventos_reporte_idx ON campo.reporte_eventos USING btree (reporte_id, id DESC);

CREATE INDEX reportes_autor_idx ON campo.reportes USING btree (autor);

CREATE UNIQUE INDEX reportes_consecutivo_key ON campo.reportes USING btree (consecutivo) WHERE (consecutivo IS NOT NULL);

CREATE UNIQUE INDEX reportes_consecutivo_num_key ON campo.reportes USING btree (tipo_id, consecutivo_num) WHERE (consecutivo_num IS NOT NULL);

CREATE INDEX reportes_contrato_idx ON campo.reportes USING btree (contrato) WHERE (contrato IS NOT NULL);

CREATE INDEX reportes_orden_trabajo_idx ON campo.reportes USING btree (orden_trabajo_id) WHERE (orden_trabajo_id IS NOT NULL);

CREATE INDEX reportes_registrado_idx ON campo.reportes USING btree (registrado_en DESC);

CREATE INDEX reportes_tipo_idx ON campo.reportes USING btree (tipo_id);

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON campo.estados_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_codigo_inmutable();

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON campo.subtipos_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_codigo_inmutable();

CREATE TRIGGER t_d_inmutable BEFORE UPDATE ON campo.causales FOR EACH ROW EXECUTE FUNCTION campo.f_catalogo_d_inmutable();

CREATE TRIGGER t_d_inmutable BEFORE UPDATE ON campo.causales_tipos FOR EACH ROW EXECUTE FUNCTION campo.f_catalogo_d_inmutable();

CREATE TRIGGER t_evento_coherente BEFORE INSERT ON campo.reporte_eventos FOR EACH ROW EXECUTE FUNCTION campo.f_evento_coherente();

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.causales FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.causales_tipos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.estados_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.subtipos_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.causales FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.causales_tipos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.estados_reporte FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.subtipos_reporte FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_reporte_coherente BEFORE INSERT ON campo.reportes FOR EACH ROW EXECUTE FUNCTION campo.f_reporte_coherente();

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.reporte_datos_sensibles FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.reporte_eventos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.reporte_fotos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.reportes FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.reporte_datos_sensibles FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.reporte_eventos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.reporte_fotos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.reportes FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();

ALTER TABLE ONLY campo.causales_tipos
    ADD CONSTRAINT causales_tipos_causal_id_fkey FOREIGN KEY (causal_id) REFERENCES campo.causales(id);

ALTER TABLE ONLY campo.causales_tipos
    ADD CONSTRAINT causales_tipos_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES campo.tipos_reporte(id);

ALTER TABLE ONLY campo.reporte_datos_sensibles
    ADD CONSTRAINT reporte_datos_sensibles_reporte_id_fkey FOREIGN KEY (reporte_id) REFERENCES campo.reportes(id);

ALTER TABLE ONLY campo.reporte_eventos
    ADD CONSTRAINT reporte_eventos_estado_nuevo_fkey FOREIGN KEY (estado_nuevo) REFERENCES campo.estados_reporte(codigo);

ALTER TABLE ONLY campo.reporte_eventos
    ADD CONSTRAINT reporte_eventos_reporte_id_fkey FOREIGN KEY (reporte_id) REFERENCES campo.reportes(id);

ALTER TABLE ONLY campo.reporte_eventos
    ADD CONSTRAINT reporte_eventos_reporte_original_id_fkey FOREIGN KEY (reporte_original_id) REFERENCES campo.reportes(id);

ALTER TABLE ONLY campo.reporte_fotos
    ADD CONSTRAINT reporte_fotos_reporte_id_fkey FOREIGN KEY (reporte_id) REFERENCES campo.reportes(id);

ALTER TABLE ONLY campo.reportes
    ADD CONSTRAINT reportes_causal_id_fkey FOREIGN KEY (causal_id) REFERENCES campo.causales(id);

ALTER TABLE ONLY campo.reportes
    ADD CONSTRAINT reportes_subtipo_id_fkey FOREIGN KEY (subtipo_id) REFERENCES campo.subtipos_reporte(id);

ALTER TABLE ONLY campo.reportes
    ADD CONSTRAINT reportes_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES campo.tipos_reporte(id);

ALTER TABLE ONLY campo.subtipos_reporte
    ADD CONSTRAINT subtipos_reporte_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES campo.tipos_reporte(id);

ALTER TABLE campo.causales ENABLE ROW LEVEL SECURITY;

ALTER TABLE campo.causales_tipos ENABLE ROW LEVEL SECURITY;

ALTER TABLE campo.estados_reporte ENABLE ROW LEVEL SECURITY;

ALTER TABLE campo.reporte_datos_sensibles ENABLE ROW LEVEL SECURITY;

ALTER TABLE campo.reporte_eventos ENABLE ROW LEVEL SECURITY;

ALTER TABLE campo.reporte_fotos ENABLE ROW LEVEL SECURITY;

ALTER TABLE campo.reportes ENABLE ROW LEVEL SECURITY;

ALTER TABLE campo.subtipos_reporte ENABLE ROW LEVEL SECURITY;

\unrestrict ZIkDJojcgNUjHmW8GGNQFql3dBuDuA72tZSzTPy60ImC4kMTO1tSYsI5a2U5vI4

reset check_function_bodies;
insert into campo.estados_reporte (codigo, nombre, orden, inicial, exige_motivo, cambio_manual) values
  ('reportado',   'Reportado',   1, true,  false, false),
  ('en_revision', 'En revisión', 2, false, false, true),
  ('con_acta',    'Con acta',    3, false, false, false),
  ('atendido',    'Atendido',    4, false, false, true),
  ('descartado',  'Descartado',  5, false, true,  true),
  ('duplicado',   'Duplicado',   6, false, false, false);
revoke all on all tables in schema campo from public, anon, authenticated, service_role;
revoke all on all sequences in schema campo from public, anon, authenticated, service_role;
revoke all on all functions in schema campo from public, anon, authenticated;
