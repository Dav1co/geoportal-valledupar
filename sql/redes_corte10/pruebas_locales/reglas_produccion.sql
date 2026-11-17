-- =====================================================================
-- Reglas de PRODUCCIÓN que los dobles locales de Code B no traían (pedido de David, 16-nov: un ensayo falló en producción por un CHECK que el doble
-- local no tenía). Se aplican una vez a la plantilla emdupar_b_10base. Solo para la base local: NO va a producción.
-- · public.geoportal_lista_blanca y public.geoportal_auditoria: de ~/geoportal-consultas/tecnica/pruebas_sql/base.sql (leída de la base viva).
-- · tecnica.*: copia de sql/tecnica_corte12/pruebas_locales/reglas_tecnica_produccion.sql del Code A (rama tecnica-corte12), que las tomó de
--   tecnica/corte1_paso_a, corte2_paso_a y corte3_paso_a. Van NOT VALID: rigen para lo que se inserte desde ahora.
-- Las tablas de «redes» salen de las migraciones reales (1a … 5d): ya traen sus CHECK.
-- =====================================================================
alter table public.geoportal_lista_blanca add constraint geoportal_lista_blanca_rol_check check (rol in ('admin', 'consulta')) not valid;
alter table public.geoportal_auditoria add constraint geoportal_auditoria_email_nn check (email is not null) not valid;      -- en producción son NOT NULL
alter table public.geoportal_auditoria add constraint geoportal_auditoria_accion_nn check (accion is not null) not valid;

-- personal_tecnico_eventos (Corte 1): sin valor por omisión del autor; motivo obligatorio para quitar un formulario o desactivar Técnica
alter table tecnica.personal_tecnico_eventos alter column autor drop default;
alter table tecnica.personal_tecnico_eventos add constraint personal_tecnico_eventos_persona_check check (persona = lower(persona) and position('@' in persona) > 1) not valid;
alter table tecnica.personal_tecnico_eventos add constraint personal_tecnico_eventos_tipo_evento_check check (tipo_evento in ('asignar_formulario', 'quitar_formulario', 'activar_tecnica', 'desactivar_tecnica')) not valid;
alter table tecnica.personal_tecnico_eventos add constraint personal_tecnico_eventos_motivo_check check (motivo is null or length(btrim(motivo)) between 3 and 1000) not valid;
alter table tecnica.personal_tecnico_eventos add constraint personal_tecnico_eventos_autor_check check (autor = lower(autor) and position('@' in autor) > 1) not valid;
alter table tecnica.personal_tecnico_eventos add constraint personal_tecnico_eventos_check check ((tipo_evento in ('asignar_formulario', 'quitar_formulario')) = (formulario is not null)) not valid;
alter table tecnica.personal_tecnico_eventos add constraint personal_tecnico_eventos_check1 check (tipo_evento not in ('quitar_formulario', 'desactivar_tecnica') or motivo is not null) not valid;
create trigger t_solo_agregar before update or delete on tecnica.personal_tecnico_eventos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.personal_tecnico_eventos for each statement execute function tecnica.f_solo_agregar();

-- plantas (Corte 1)
alter table tecnica.plantas add constraint plantas_codigo_check check (codigo ~ '^[a-z][a-z0-9_]{1,29}$') not valid;
alter table tecnica.plantas add constraint plantas_nombre_check check (length(btrim(nombre)) between 2 and 80) not valid;
create trigger t_no_borrar before delete on tecnica.plantas for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on tecnica.plantas for each statement execute function tecnica.f_solo_agregar();

-- registros (Corte 1 y Corte 2): valor finito, autor, clave de envío, fecha de la muestra hasta 31 días antes del registro (nunca futura) y coherencia planta/punto
alter table tecnica.registros add constraint registros_valor_check check (valor::text not in ('NaN', 'Infinity', '-Infinity')) not valid;
alter table tecnica.registros add constraint registros_autor_check check (autor = lower(autor) and position('@' in autor) > 1) not valid;
alter table tecnica.registros add constraint registros_clave_envio_check check (clave_envio is null or clave_envio ~ '^[A-Za-z0-9_-]{8,80}$') not valid;
alter table tecnica.registros add constraint ck_registro_fecha_rango check (
  fecha_muestra <= (registrado_en at time zone 'America/Bogota')::date
  and fecha_muestra >= (registrado_en at time zone 'America/Bogota')::date - 31) not valid;
alter table tecnica.registros add constraint registros_planta_id_fkey foreign key (planta_id) references tecnica.plantas (id) not valid;
create or replace function tecnica.f_regla_planta_con_punto() returns boolean language sql immutable set search_path to 'pg_catalog' as $$ select true $$;

create or replace function tecnica.f_registro_coherente() returns trigger
language plpgsql set search_path to 'pg_catalog', 'pg_temp' as $$
declare v_alcance text; v_tipo text; v_activo boolean;
begin
  select fv.alcance into v_alcance from tecnica.formulario_variables fv
   where fv.formulario = new.formulario and fv.variable_id = new.variable_id;
  if v_alcance = 'por_planta' then
    if new.planta_id is null then
      raise exception 'La variable es por planta: falta la planta' using errcode = '22023';
    end if;
    if new.punto_id is not null and tecnica.f_regla_planta_con_punto() then
      raise exception 'La variable es por planta: no lleva punto' using errcode = '22023';
    end if;
  elsif v_alcance = 'ambas_plantas' then
    if new.planta_id is not null then
      raise exception 'La variable es para las dos plantas: no lleva planta' using errcode = '22023';
    end if;
  elsif v_alcance = 'por_punto' then
    if new.punto_id is null then
      raise exception 'La variable es por punto: falta el punto' using errcode = '22023';
    end if;
    if new.planta_id is not null then
      raise exception 'La variable es por punto: no lleva planta' using errcode = '22023';
    end if;
    select pu.tipo, pu.activo into v_tipo, v_activo from tecnica.puntos pu where pu.id = new.punto_id;
    if v_tipo is distinct from 'muestreo' or v_activo is not true then
      raise exception 'La variable es por punto: el punto debe ser un punto de muestreo activo' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
create trigger t_registro_coherente before insert on tecnica.registros for each row execute function tecnica.f_registro_coherente();
create trigger t_solo_agregar before update or delete on tecnica.registros for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.registros for each statement execute function tecnica.f_solo_agregar();

-- exclusiones (Corte 1)
alter table tecnica.exclusiones add constraint exclusiones_motivo_check check (length(btrim(motivo)) between 10 and 1000) not valid;
alter table tecnica.exclusiones add constraint exclusiones_autor_check check (autor = lower(autor) and position('@' in autor) > 1) not valid;
alter table tecnica.exclusiones add constraint exclusiones_check check (num_nonnulls(registro_id, lote_id) = 1) not valid;
create trigger t_solo_agregar before update or delete on tecnica.exclusiones for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.exclusiones for each statement execute function tecnica.f_solo_agregar();

-- referencias (Corte 3 de planta)
alter table tecnica.referencias add column if not exists desactivada_en timestamptz;
alter table tecnica.referencias add constraint referencias_planta_id_fkey foreign key (planta_id) references tecnica.plantas (id) not valid;
alter table tecnica.referencias add constraint referencias_punto_id_fkey foreign key (punto_id) references tecnica.puntos (id) not valid;
alter table tecnica.referencias add constraint referencias_origen_check check (origen in ('norma', 'criterio_planta')) not valid;
alter table tecnica.referencias add constraint referencias_fuente_check check (length(btrim(fuente)) between 3 and 400) not valid;
alter table tecnica.referencias add constraint referencias_algun_limite check (ref_min is not null or ref_max is not null) not valid;
alter table tecnica.referencias add constraint referencias_orden_limites check (ref_min is null or ref_max is null or ref_min <= ref_max) not valid;
alter table tecnica.referencias add constraint referencias_un_solo_alcance check (num_nonnulls(planta_id, punto_id) <= 1) not valid;
create unique index if not exists uq_referencias_activa on tecnica.referencias (variable_id, coalesce(planta_id, 0), coalesce(punto_id, 0)) where activa;
create or replace function tecnica.f_referencia_protegida() returns trigger
language plpgsql set search_path to 'pg_catalog', 'pg_temp' as $$
begin
  if new.id is distinct from old.id or new.variable_id is distinct from old.variable_id or new.planta_id is distinct from old.planta_id
     or new.punto_id is distinct from old.punto_id or new.ref_min is distinct from old.ref_min or new.ref_max is distinct from old.ref_max
     or new.origen is distinct from old.origen or new.fuente is distinct from old.fuente or new.creado_en is distinct from old.creado_en
     or new.desactivada_en is distinct from old.desactivada_en then
    raise exception 'Una referencia no se edita: desactívela y cree otra, para conservar el historial' using errcode = '55000';
  end if;
  if old.activa and not new.activa then
    new.desactivada_en := clock_timestamp();
  elsif new.activa is distinct from old.activa then
    raise exception 'Una referencia desactivada no se reactiva: cree otra' using errcode = '55000';
  end if;
  return new;
end $$;
create trigger t_no_borrar before delete on tecnica.referencias for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on tecnica.referencias for each statement execute function tecnica.f_solo_agregar();
create trigger t_catalogo_protegido before update on tecnica.referencias for each row execute function tecnica.f_referencia_protegida();
