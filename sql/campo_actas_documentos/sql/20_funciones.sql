-- =====================================================================
-- COMERCIAL 21-NOV · (b) ACTAS · 20 — FUNCIONES INTERNAS Y DISPARADORES (no se tocan geoportal_campo_crear_reporte ni geoportal_acta_registrar)
-- Al registrar: (1) se exige la firma del operario (B5) en los 9 formularios con PDF; (2) en los REV, req_cambio_medidor debe coincidir con da_lugar (D13);
-- (3) después de registrar, cada opción de da_lugar crea una derivada pendiente.
-- =====================================================================

create function campo.f_formulario_de_reporte(p_tipo_id bigint) returns text
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select 'tipo:' || t.codigo from campo.tipos_reporte t where t.id = p_tipo_id
$$;

create function campo.f_documento_de(p_formulario text) returns campo.formularios_documento
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select d from campo.formularios_documento d where d.formulario = p_formulario and d.activo
$$;


-- Disparador ANTES de insertar en campo.reportes: firma del operario y coherencia de req_cambio_medidor con da_lugar
create function campo.f_firmas_al_registrar_reporte() returns trigger
language plpgsql security definer set search_path to 'campo', 'pg_temp' as $$
declare v_d campo.formularios_documento; v_codigo text; v_da jsonb;
begin
  v_d := campo.f_documento_de(campo.f_formulario_de_reporte(new.tipo_id));
  if v_d.formulario is not null and v_d.firma_operario = 'obligatoria'
     and not exists (select 1 from campo.firmas f where f.esquema = 'campo' and f.registro_id = new.id and f.rol = 'operario' and f.estado = 'firmo' and f.autor = new.autor) then
    perform campo.f_error('Falta la firma del operario');
  end if;
  select t.codigo into v_codigo from campo.tipos_reporte t where t.id = new.tipo_id;
  if v_codigo in ('revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida') and new.datos ? 'da_lugar' and new.datos ? 'req_cambio_medidor' then
    v_da := new.datos -> 'da_lugar';
    if jsonb_typeof(v_da) = 'array' and (new.datos -> 'req_cambio_medidor') is distinct from to_jsonb(v_da ? 'cambio_medidor') then
      perform campo.f_error('¿Se requiere cambio de medidor? no coincide con las actividades derivadas');
    end if;
  end if;
  return new;
end $$;

-- Disparador DESPUÉS de insertar en campo.reportes: una derivada pendiente por cada opción de da_lugar
create function campo.f_derivadas_al_registrar() returns trigger
language plpgsql security definer set search_path to 'campo', 'pg_temp' as $$
begin
  if jsonb_typeof(new.datos -> 'da_lugar') = 'array' then
    insert into campo.derivadas (origen_id, contrato, actividad)
    select new.id, new.contrato, c.codigo from campo.derivadas_catalogo c
     where new.datos -> 'da_lugar' ? c.codigo
    on conflict (origen_id, actividad) do nothing;
  end if;
  return null;
end $$;

-- Disparador ANTES de insertar en acta.actas: firma del operario en TODAS las versiones (David, 21-nov: la corrección la firma quien corrige)
create function campo.f_firmas_al_registrar_acta() returns trigger
language plpgsql security definer set search_path to 'campo', 'pg_temp' as $$
declare v_d campo.formularios_documento;
begin
  v_d := campo.f_documento_de('acta');
  if v_d.formulario is not null and v_d.firma_operario = 'obligatoria'
     and not exists (select 1 from campo.firmas f where f.esquema = 'acta' and f.registro_id = new.id and f.rol = 'operario' and f.estado = 'firmo' and f.autor = new.autor) then
    perform campo.f_error('Falta la firma del operario');
  end if;
  return new;
end $$;


create trigger t_firmas_al_registrar before insert on campo.reportes for each row execute function campo.f_firmas_al_registrar_reporte();
create trigger t_derivadas_al_registrar after insert on campo.reportes for each row execute function campo.f_derivadas_al_registrar();
create trigger t_firmas_al_registrar before insert on acta.actas for each row execute function campo.f_firmas_al_registrar_acta();

-- Estado de una derivada: pendiente, atendida, atendida_fuera o anulada
create function campo.f_derivada_estado(p_id bigint) returns text
language sql stable security definer set search_path to 'campo', 'pg_temp' as $$
  select coalesce((select e.tipo_evento from campo.derivada_eventos e where e.derivada_id = p_id), 'pendiente')
$$;

-- Quién puede ver o generar el documento de un registro: su autor, el supervisor (campo o actas) o el administrador. Devuelve el correo.
create function campo.f_autorizar_documento(p_solicitante text, p_esquema text, p_id uuid) returns text
language plpgsql security definer set search_path to 'public', 'campo', 'acta', 'pg_temp' as $$
declare v_email text := lower(btrim(coalesce(p_solicitante, ''))); v_autor text;
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  -- primero el permiso (403), después la existencia (404): quien no tiene campo ni acta no averigua si un registro existe
  if not (public.geoportal_es_admin(v_email) or public.geoportal_puede(v_email, 'campo') or public.geoportal_puede(v_email, 'acta')
          or public.geoportal_puede(v_email, 'dashboard_campo') or public.geoportal_puede(v_email, 'dashboard_acta')) then
    raise exception 'Sin permiso para esta función' using errcode = '42501';
  end if;
  if p_esquema = 'campo' then select r.autor into v_autor from campo.reportes r where r.id = p_id;
  elsif p_esquema = 'acta' then select a.autor into v_autor from acta.actas a where a.id = p_id;
  else perform campo.f_error('El tipo de registro no es válido'); end if;
  if v_autor is null then perform campo.f_error('Ese registro no existe', 'P0002'); end if;
  if v_autor = v_email or public.geoportal_es_admin(v_email) or public.geoportal_puede(v_email, 'dashboard_acta') or public.geoportal_puede(v_email, 'dashboard_campo') then
    return v_email;
  end if;
  raise exception 'Sin permiso para esta función' using errcode = '42501';
end $$;

-- Quién ve las actas registradas: supervisor de actas, supervisor de campo o administrador
create function campo.f_autorizar_registradas(p_solicitante text) returns text
language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if public.geoportal_es_admin(v_email) or public.geoportal_puede(v_email, 'dashboard_acta') or public.geoportal_puede(v_email, 'dashboard_campo') then return v_email; end if;
  raise exception 'Sin permiso para esta función' using errcode = '42501';
end $$;

-- Nombre del PDF: AAAAMMDDHHMMSS (registrado_en en hora de Bogotá) - SIGLA - NÚMERO (acta: AI-AAAA-NNNNNN; campo: consecutivo sin guion) [-vN si es corrección]
create function campo.f_nombre_pdf(p_registrado timestamptz, p_sigla text, p_numero text, p_version integer) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  select to_char(p_registrado at time zone 'America/Bogota', 'YYYYMMDDHH24MISS') || '-' || p_sigla || '-' || p_numero || case when p_version > 1 then '-v' || p_version else '' end || '.pdf'
$$;

-- Fila común de las «actas registradas» (acta AI y los 8 formatos con PDF de campo). Sin nombres de personas ni texto libre.
create function campo.f_registradas() returns table (registro_id uuid, esquema text, formulario text, tipo text, tipo_nombre text, consecutivo text, numero_fisico text, fecha date,
                                                      registrado_en timestamptz, operario text, contrato text, barrio text, resultado text, orden bigint)
language sql stable security definer set search_path to 'campo', 'acta', 'pg_temp' as $$
  select a.id, 'acta', 'acta', 'acta', 'Reportar posible pérdida', a.consecutivo, a.numero_acta_fisica, a.fecha_acta_fisica, a.registrado_en, a.autor, a.contrato, a.barrio,
         case when a.sin_irregularidad then 'sin_irregularidad' else 'con_hallazgos' end, a.seq
    from acta.actas a
   where not exists (select 1 from acta.actas b where b.version_anterior_id = a.id)
  union all
  select r.id, 'campo', 'tipo:' || t.codigo, t.codigo, t.nombre, r.consecutivo, r.datos ->> 'serie_acta', (r.registrado_en at time zone 'America/Bogota')::date, r.registrado_en, r.autor, r.contrato,
         null::text, r.resultado, r.seq
    from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id
   where exists (select 1 from campo.formularios_documento d where d.formulario = 'tipo:' || t.codigo and d.activo)
$$;

revoke all on function campo.f_formulario_de_reporte(bigint) from public, anon, authenticated, service_role;
revoke all on function campo.f_documento_de(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_firmas_al_registrar_reporte() from public, anon, authenticated, service_role;
revoke all on function campo.f_derivadas_al_registrar() from public, anon, authenticated, service_role;
revoke all on function campo.f_firmas_al_registrar_acta() from public, anon, authenticated, service_role;
revoke all on function campo.f_derivada_estado(bigint) from public, anon, authenticated, service_role;
revoke all on function campo.f_autorizar_documento(text, text, uuid) from public, anon, authenticated, service_role;
revoke all on function campo.f_autorizar_registradas(text) from public, anon, authenticated, service_role;
revoke all on function campo.f_nombre_pdf(timestamptz, text, text, integer) from public, anon, authenticated, service_role;
revoke all on function campo.f_registradas() from public, anon, authenticated, service_role;

-- Los campos «¿Da lugar a otras actividades?» quedan activos (si una reversa los desactivó, se reactivan: no se borran)
update campo.tipo_campos set activo = true where codigo in ('da_lugar', 'da_lugar_otra') and not activo;
