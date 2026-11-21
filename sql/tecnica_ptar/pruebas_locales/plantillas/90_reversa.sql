-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 90 — REVERSA. Deja tecnica como antes de la migración (f_autorizar_supervision vuelve a la publicada).
-- Solo si la PTAR todavía NO tiene datos: si ya hay elementos, alias o alcances, se detiene (nada se borra: entonces se desactiva con motivo, D9).
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.instalaciones') is null then raise exception 'REVERSA PTAR-1: el paquete no está aplicado'; end if;
  if exists (select 1 from tecnica.elementos_planta) or exists (select 1 from tecnica.elemento_alias_eventos) or exists (select 1 from tecnica.alcance_eventos) then
    raise exception 'REVERSA PTAR-1: la PTAR ya tiene datos (elementos, alias o alcances). No se borra: desactive con motivo y avise';
  end if;
end $$;
{{DROPS_RPC}}
create or replace function tecnica.f_autorizar_supervision(p_solicitante text) returns text
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $f$
declare v_email text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if tecnica.f_perfil(v_email) <> 'admin' and not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  return v_email;
end $f$;
do $$
begin
  if md5(pg_get_functiondef('tecnica.f_autorizar_supervision(text)'::regprocedure)) <> '{{MD5_AUT_SUP}}' then
    raise exception 'REVERSA PTAR-1: f_autorizar_supervision no quedó como la publicada';
  end if;
end $$;
{{DROPS_INTERNAS}}
drop table tecnica.alcance_eventos;
drop table tecnica.elemento_alias_eventos;
drop table tecnica.elementos_planta;
drop table tecnica.instalaciones;
{{DROPS_DISPARADORES}}
