-- =====================================================================
-- DOBLE LOCAL (además del del 1a) de lo vivo que usa el Corte 2. SOLO PARA PRUEBAS EN EL POSTGIS DE HOMEBREW.
--   · Storage: storage.buckets y storage.objects (con metadata size y mimetype, como Supabase), con RLS activa y sin políticas;
--   · tecnica.f_formulario_asignado, tecnica.f_autorizar_captura (texto de corte1_paso_a/sql/20_funciones_internas.sql) y
--     tecnica.f_max_horas_inicio() = 12 (pasada 14/11).
--   · personas de prueba: zt.oper tiene asignado «danos_fallas»; zt.oper.sinform no.
-- =====================================================================
create schema if not exists storage;
create table storage.buckets (id text primary key, name text not null, public boolean default false, file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now());
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets (id), name text not null, owner uuid,
  metadata jsonb, created_at timestamptz default now(), unique (bucket_id, name));
alter table storage.objects enable row level security;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('campo-fotos', 'campo-fotos', false, 2097152, array['image/jpeg']);

create function tecnica.f_formulario_asignado(p_email text, p_formulario text) returns boolean
language sql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
  select coalesce((select e.tipo_evento = 'asignar_formulario' from tecnica.personal_tecnico_eventos e
                    where e.persona = lower(p_email) and e.formulario = p_formulario
                      and e.tipo_evento in ('asignar_formulario', 'quitar_formulario')
                    order by e.id desc limit 1), false);
$$;
create function tecnica.f_autorizar_captura(p_solicitante text, p_formulario text) returns text
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text; v_perfil text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'registro_tecnico');       -- 28000 / 42501 si no hay sesión, acceso o permiso
  v_perfil := tecnica.f_perfil(v_email);
  if v_perfil = 'admin' then return v_email; end if;
  if not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  if v_perfil = 'supervisor' then return v_email; end if;
  if not tecnica.f_formulario_asignado(v_email, p_formulario) then
    raise exception 'No tiene asignado este formulario' using errcode = '42501';
  end if;
  return v_email;
end $$;
create function tecnica.f_max_horas_inicio() returns integer
language sql immutable set search_path to 'pg_catalog' as $$ select 12 $$;

insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario) values ('zt.oper@emdupar.gov.co', 'asignar_formulario', 'danos_fallas');
insert into public.geoportal_lista_blanca (email, rol, ver_registro_tecnico) values ('zt.oper.sinform@emdupar.gov.co', 'consulta', true);
