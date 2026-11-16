-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 26 — RPC NUEVA: el supervisor de distribución asigna o quita a su gente los formularios de distribución (§28.2)
-- PROPUESTA. No se ha ejecutado en la base real. security definer, search_path fijo, mensajes con HINT msg_usuario; solo service_role.
-- · Solo los formularios de redes.formularios_distribucion (hoy «Reportar daño o falla» y «Registrar intervención»). Los de planta siguen en
--   Personal del Dashboard PTAP, con sus RPC de siempre (geoportal_tec_asignar_formulario y geoportal_tec_quitar_formulario), que no se tocan.
-- · Escribe un EVENTO en tecnica.personal_tecnico_eventos (la misma tabla viva que ya filtra la captura), con la misma forma que las de planta,
--   y la señal de tiempo real en tecnica.senal_cambio. Nada se actualiza ni se borra. Siempre con motivo (10 caracteres o más).
-- =====================================================================
create function public.geoportal_redes_personal_formulario(p_solicitante text, p_persona text, p_formulario text, p_asignar boolean, p_motivo text, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare
  v_email text := redes.f_supervisor(p_solicitante, 'asignan los formularios de distribución'); v_p text := lower(btrim(coalesce(p_persona, '')));
  lb public.geoportal_lista_blanca; v_mot text := btrim(coalesce(p_motivo, '')); f redes.formularios_distribucion%rowtype; v_tiene boolean;
begin
  if p_asignar is null then perform tecnica.f_error('Diga si se asigna o se quita el formulario'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  select * into f from redes.formularios_distribucion where clave = p_formulario and activo;
  if not found then perform tecnica.f_error('Ese no es un formulario de distribución (los de planta se asignan en el Dashboard PTAP)'); end if;
  lb := redes.f_persona_tecnica(v_p);
  if lb.email is null then perform tecnica.f_error('Esa persona no está en Técnica (o su cuenta está inactiva)', 'P0002'); end if;
  if p_asignar and not lb.ver_registro_tecnico then perform tecnica.f_error('Esta persona no tiene «Registro técnico»: el administrador debe dárselo primero', '55000'); end if;
  if v_p = v_email then perform tecnica.f_error('No puede cambiar sus propios formularios: pídaselo a otro supervisor o al administrador'); end if;
  perform pg_advisory_xact_lock(hashtextextended('pte|' || v_p, 0));      -- el mismo candado que usan las RPC de planta
  v_tiene := tecnica.f_formulario_asignado(v_p, f.clave);
  if v_tiene = p_asignar then perform tecnica.f_error(case when p_asignar then 'Ya tiene ese formulario asignado' else 'No tiene ese formulario asignado' end); end if;
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, motivo, autor)
  values (v_p, case when p_asignar then 'asignar_formulario' else 'quitar_formulario' end, f.clave, v_mot, v_email);
  insert into tecnica.senal_cambio (tabla) values ('personal_tecnico_eventos');
  perform tecnica.f_auditar(v_email, case when p_asignar then 'redes_asignar_formulario' else 'redes_quitar_formulario' end, v_p, jsonb_build_object('formulario', f.clave, 'motivo', v_mot), p_ip);
  return jsonb_build_object('persona', v_p, 'formulario', f.clave, 'nombre', f.nombre, 'asignado', p_asignar);
end $f$;
