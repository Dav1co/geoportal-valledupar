create schema if not exists tecnica;
create or replace function tecnica.f_solo_agregar() returns trigger language plpgsql set search_path = pg_catalog as $f$
begin
  raise exception 'Tabla de solo agregar: % no permitido en %.%', tg_op, tg_table_schema, tg_table_name using errcode = '42501';
end $f$;

revoke all on function tecnica.f_solo_agregar() from public, anon, authenticated, service_role;   -- funcion de disparador: nadie de la API la ejecuta
create or replace function tecnica.f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text) returns void
language sql security definer set search_path = public, tecnica, pg_temp as $f$
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values (lower(p_email), p_accion, p_ref, p_detalle, p_ip);
$f$;
revoke all on function tecnica.f_auditar(text, text, text, jsonb, text) from public, anon, authenticated, service_role;
create or replace function tecnica.f_verificar(p_solicitante text, p_modo text) returns text
language plpgsql security definer set search_path = public, tecnica, pg_temp as $f$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if not public.geoportal_puede(v_email, p_modo) then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  return v_email;
end $f$;
revoke all on function tecnica.f_verificar(text, text) from public, anon, authenticated, service_role;
