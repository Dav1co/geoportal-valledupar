-- =====================================================================
-- DOBLE LOCAL (Corte 5b) de lo vivo de planta que usan las RPC nuevas. SOLO PARA PRUEBAS EN EL POSTGIS DE HOMEBREW.
--   · tecnica.f_autorizar_supervision con el MISMO texto de corte1_paso_a/sql/20_funciones_internas.sql (la puerta del Dashboard PTAP);
--   · personas de prueba: zt.oper tiene asignado «muestreo» (además de «danos_fallas»); zt.oper.sinform no tiene Muestreo;
--     zt.super2 es un segundo supervisor de planta (para aprobar lo que propone zt.super).
-- =====================================================================
create function tecnica.f_autorizar_supervision(p_solicitante text) returns text
language plpgsql stable security definer set search_path to 'public', 'tecnica', 'pg_temp' as $$
declare v_email text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if tecnica.f_perfil(v_email) <> 'admin' and not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  return v_email;
end $$;
revoke all on function tecnica.f_autorizar_supervision(text) from public, anon, authenticated, service_role;
insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario) values ('zt.oper@emdupar.gov.co', 'asignar_formulario', 'muestreo');
insert into public.geoportal_lista_blanca (email, rol, ver_registro_tecnico, ver_dashboard_tecnico) values ('zt.super2@emdupar.gov.co', 'consulta', true, true);
