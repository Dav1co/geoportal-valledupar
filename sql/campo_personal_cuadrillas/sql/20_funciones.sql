-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 20 — FUNCIONES INTERNAS (nadie las ejecuta directamente: revoke all)
-- Lo vigente es siempre el último evento de cada grupo (área; cuadrilla; cada actividad), igual que cargo y formularios en la pasada del 14-nov.
-- =====================================================================

-- Persona que se gestiona en Personal de Comercial: la misma regla de la pasada del 14-nov (activa, no administradora, con acceso a campo o al acta).
create function campo.f_persona_comercial(p_email text) returns boolean
language sql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
  select exists (select 1 from public.geoportal_lista_blanca lb where lb.email = lower(p_email) and lb.activo and lb.rol <> 'admin'
                   and (coalesce(lb.ver_campo, false) or coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_acta, false) or coalesce(lb.ver_dashboard_acta, false)))
$$;

create function campo.f_area_vigente(p_email text) returns text
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select e.valor from campo.personal_eventos e where e.persona = lower(p_email) and e.tipo_evento = 'fijar_area' order by e.id desc limit 1
$$;

create function campo.f_cuadrilla_vigente(p_email text) returns bigint
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select e.valor::bigint from campo.personal_eventos e where e.persona = lower(p_email) and e.tipo_evento = 'fijar_cuadrilla' order by e.id desc limit 1
$$;

create function campo.f_actividades_propias(p_email text) returns text[]
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select coalesce(array_agg(u.valor order by u.valor), '{}') from (
    select distinct on (e.valor) e.valor, e.tipo_evento from campo.personal_eventos e
     where e.persona = lower(p_email) and e.tipo_evento in ('asignar_actividad', 'quitar_actividad') order by e.valor, e.id desc) u
   where u.tipo_evento = 'asignar_actividad'
$$;

create function campo.f_cuadrilla_actividades(p_cuadrilla bigint) returns text[]
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select coalesce(array_agg(u.valor order by u.valor), '{}') from (
    select distinct on (e.valor) e.valor, e.tipo_evento from campo.cuadrilla_eventos e
     where e.cuadrilla_id = p_cuadrilla and e.tipo_evento in ('agregar_actividad', 'quitar_actividad') order by e.valor, e.id desc) u
   where u.tipo_evento = 'agregar_actividad'
$$;

-- Miembros vigentes de las cuadrillas: el último fijar_cuadrilla de cada persona gestionable.
create function campo.f_miembros_cuadrillas() returns table (persona text, cuadrilla_id bigint)
language sql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
  select v.persona, v.valor::bigint from (
    select distinct on (e.persona) e.persona, e.valor from campo.personal_eventos e where e.tipo_evento = 'fijar_cuadrilla' order by e.persona, e.id desc) v
   where v.valor is not null and campo.f_persona_comercial(v.persona)
$$;

-- Actividades vigentes de una persona: las propias más las de su cuadrilla (D3), con su origen. Incluye las desactivadas (la pantalla las marca).
create function campo.f_actividades_persona(p_email text) returns table (codigo text, origen text)
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  with p as (select unnest(campo.f_actividades_propias(p_email)) as codigo),
       c as (select unnest(campo.f_cuadrilla_actividades(q.id)) as codigo
               from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(p_email) and q.activa)
  select coalesce(p.codigo, c.codigo), case when p.codigo is not null and c.codigo is not null then 'ambas' when p.codigo is not null then 'propia' else 'cuadrilla' end
    from p full join c on c.codigo = p.codigo
$$;

-- «Quién puede hacer la actividad X» (para SCRR, lectura y reparto, que la usarán desde sus propias RPC): personas activas con acceso a campo o al acta,
-- que tienen la actividad como propia o por su cuadrilla activa.
create function campo.f_quien_puede(p_actividad text) returns table (persona text, cuadrilla_id bigint, origen text)
language sql stable security definer set search_path to 'public', 'campo', 'pg_temp' as $$
  with propias as (
         select u.persona from (
           select distinct on (e.persona) e.persona, e.tipo_evento from campo.personal_eventos e
            where e.valor = p_actividad and e.tipo_evento in ('asignar_actividad', 'quitar_actividad') order by e.persona, e.id desc) u
          where u.tipo_evento = 'asignar_actividad' and campo.f_persona_comercial(u.persona)),
       por_cuadrilla as (
         select m.persona, m.cuadrilla_id from campo.f_miembros_cuadrillas() m join campo.cuadrillas q on q.id = m.cuadrilla_id and q.activa
          where p_actividad = any (campo.f_cuadrilla_actividades(m.cuadrilla_id)))
  select coalesce(p.persona, c.persona), (select m.cuadrilla_id from campo.f_miembros_cuadrillas() m where m.persona = coalesce(p.persona, c.persona)),
         case when p.persona is not null and c.persona is not null then 'ambas' when p.persona is not null then 'propia' else 'cuadrilla' end
    from propias p full join por_cuadrilla c on c.persona = p.persona
$$;

-- Código a partir del nombre (catálogos): minúsculas sin tildes, guion bajo en lo demás, hasta 40 caracteres.
create function campo.f_codigo_desde_nombre(p_nombre text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select left(btrim(regexp_replace(translate(lower(btrim(p_nombre)), 'áéíóúüñàèìòù', 'aeiouunaeiou'), '[^a-z0-9]+', '_', 'g'), '_'), 40)
$$;

-- Motivo: nulo o de 10 a 300 caracteres (el CHECK de las tablas); el mensaje lo ve el usuario.
create function campo.f_motivo_personal(p_motivo text, p_obligatorio boolean) returns text
language plpgsql stable set search_path to 'pg_catalog' as $$
declare v text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if v is null and p_obligatorio then perform campo.f_error('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
  if v is not null and (length(v) < 10 or length(v) > 300) then perform campo.f_error('El motivo debe tener entre 10 y 300 caracteres'); end if;
  return v;
end $$;

revoke all on function campo.f_persona_comercial(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_area_vigente(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_cuadrilla_vigente(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_actividades_propias(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_cuadrilla_actividades(bigint) from public, anon, authenticated, service_role;
revoke all on function campo.f_miembros_cuadrillas() from public, anon, authenticated, service_role;
revoke all on function campo.f_actividades_persona(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_quien_puede(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_codigo_desde_nombre(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_motivo_personal(text, boolean) from public, anon, authenticated, service_role;
