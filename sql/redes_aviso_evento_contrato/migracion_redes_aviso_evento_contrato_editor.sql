begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO (primera regla de choque) · 10 — GUARDIA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo de David del 19-nov: dado un contrato, decir si HOY está dentro de un evento de suspensión abierto. Solo avisa; no bloquea nada.
-- · Presupone «Mis reportes» publicado: huella del conjunto de funciones de redes 314112df87e4d649945fd3f611857025.
-- · SOLO AGREGA 3 funciones de lectura (1 RPC). No reemplaza ninguna, no crea tablas ni índices y no cambia quién declara o ve los eventos.
-- · La regla de «a quién afecta» es la del Corte 15 (redes.f_evento_contratos): el contrato está en el evento si el tramo al que está amarrado
--   (redes.contrato_tramo) toca la zona del evento, o si el evento es de toda la ciudad. La zona de un evento por planta es la de sus sectores al declararlo.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_evento_contrato(text,text)') is not null or to_regprocedure('redes.f_eventos_del_contrato(text)') is not null
     or to_regprocedure('redes.f_evento_contrato_acceso(text)') is not null then
    raise exception 'El aviso de evento por contrato ya está aplicado: deténgase y avise';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '314112df87e4d649945fd3f611857025' then
    raise exception 'Las funciones de redes no son las de «Mis reportes» publicado (huella 314112df87e4d649945fd3f611857025): deténgase y avise';
  end if;
  if to_regclass('redes.eventos_suspension') is null or to_regclass('redes.v_evento_suspension') is null or to_regclass('redes.contrato_tramo') is null
     or to_regprocedure('redes.f_eventos_abiertos()') is null or to_regprocedure('redes.f_evento_franja(text,timestamptz,text,timestamptz)') is null
     or to_regprocedure('public.geoportal_puede(text,text)') is null or to_regprocedure('public.geoportal_estado_acceso(text)') is null then
    raise exception 'Faltan tablas o funciones del Corte 15 o del acceso: deténgase y avise';
  end if;
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO · 20 — FUNCIONES INTERNAS (no las ejecuta la API)
-- =====================================================================
-- Los eventos ABIERTOS que tocan un contrato, del más específico al más general (la misma prioridad con que el Corte 15 asocia los reportes:
-- círculo, luego sectores, luego total; entre iguales, el de menor área; luego el más nuevo).
-- La regla de a quién afecta es la de redes.f_evento_contratos (Corte 15): el tramo amarrado al contrato toca la zona, o el evento es de toda la ciudad.
-- Un contrato sin amarre (no está en redes.contrato_tramo) solo puede estar en un evento de toda la ciudad.
create function redes.f_eventos_del_contrato(p_contrato text) returns table (evento_id bigint, orden integer)
language sql stable security definer set search_path = redes, public, extensions, pg_temp as $$
  with t as (select m.geom from redes.contrato_tramo ct join redes.activo_vigente_mat m on m.activo_id = ct.activo_id where ct.contrato = p_contrato)
  select e.id, (row_number() over (order by case e.alcance when 'circulo' then 1 when 'sectores' then 2 else 3 end, ST_Area(e.geom) nulls last, e.id desc))::integer
    from redes.f_eventos_abiertos() e
   where e.todo or exists (select 1 from t where t.geom && e.geom and ST_Intersects(t.geom, e.geom)) $$;

-- Quién consulta: los perfiles que buscan contratos en Comercial (geovisor comercial) y en Campo (formularios de campo y su supervisor), y el administrador.
-- Devuelve el correo normalizado o se niega (42501). Como las demás de redes: el acceso tiene que estar «ok» (lista blanca, horario).
create function redes.f_evento_contrato_acceso(p_solicitante text) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if not (public.geoportal_puede(v_email, 'comercial') or public.geoportal_puede(v_email, 'campo')) then
    raise exception 'Sin permiso para consultar si un contrato está en un evento de suspensión' using errcode = '42501';
  end if;
  return v_email;
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO · 26 — RPC (la llama la Edge geoportal-redes, ruta evento_contrato).
--   · geoportal_redes_evento_contrato: dado un contrato, si HOY está dentro de un evento de suspensión abierto, y cuál (el más específico).
-- Para qué: que Comercial y Campo, al buscar un contrato, vean «este contrato está sin agua por el evento EVS-…» antes de mandar a alguien o de
--   recibir un reclamo. SOLO AVISA: no bloquea ni cambia nada.
-- Qué devuelve: solo datos del evento (código, tipo, causa, zona, desde, regreso estimado, el texto de la franja). Ningún dato del suscriptor ni del
--   catastro (ni nombre, ni dirección, ni tramo, ni coordenadas). «ubicado» dice si el contrato tiene amarre a la red (sin él, solo cuenta un evento de toda la ciudad).
-- Solo lectura: no guarda ni audita.
-- =====================================================================
create function public.geoportal_redes_evento_contrato(p_solicitante text, p_contrato text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_evento_contrato_acceso(p_solicitante); v_ct text := btrim(coalesce(p_contrato, '')); v_ids bigint[]; v_ev jsonb;
begin
  if v_ct !~ '^[0-9]{1,15}$' then perform tecnica.f_error('Escriba el número del contrato (solo números, hasta 15)'); end if;
  select coalesce(array_agg(x.evento_id order by x.orden), '{}') into v_ids from redes.f_eventos_del_contrato(v_ct) x;
  if cardinality(v_ids) > 0 then
    select jsonb_build_object(
             'codigo', e.codigo,
             'tipo', case when e.dano_id is not null then 'dano' when e.intervencion_id is not null then 'intervencion' else 'suspension' end,
             'tipo_nombre', case when e.dano_id is not null then 'Daño en la red' when e.intervencion_id is not null then 'Intervención en la red' else 'Suspensión del servicio' end,
             'causa', e.causa,
             'zona', case when e.alcance = 'circulo' then 'circulo' when e.alcance = 'sectores' then 'sectores' when e.todo then 'ciudad' else 'planta' end,
             'zona_nombre', e.zona_nombre,
             'desde', e.desde, 'regreso_estimado', e.regreso_vigente,
             'texto', redes.f_evento_franja(e.zona_nombre, e.desde, e.causa, e.regreso_vigente))
      into v_ev from redes.v_evento_suspension e where e.id = v_ids[1];
  end if;
  return jsonb_build_object('contrato', v_ct, 'consultado_en', clock_timestamp(),
                            'ubicado', exists (select 1 from redes.contrato_tramo ct where ct.contrato = v_ct),
                            'en_evento', cardinality(v_ids) > 0, 'evento', v_ev, 'otros_eventos', greatest(cardinality(v_ids) - 1, 0));
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO · 40 — PERMISOS: revoke all antes de dar permisos. La RPC: solo service_role. Las internas: nadie.
-- =====================================================================
revoke all on function redes.f_eventos_del_contrato(text) from public, anon, authenticated, service_role;
revoke all on function redes.f_evento_contrato_acceso(text) from public, anon, authenticated, service_role;
revoke all on function public.geoportal_redes_evento_contrato(text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_evento_contrato(text, text) to service_role;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_aviso_evento_contrato', 'migracion_redes_aviso_evento_contrato', null, jsonb_build_object(
        'nuevas', jsonb_build_array('redes.f_eventos_del_contrato', 'redes.f_evento_contrato_acceso', 'public.geoportal_redes_evento_contrato'),
        'motivo', 'primera regla de choque: al buscar un contrato, Comercial y Campo ven si está dentro de un evento de suspensión abierto (solo avisa)'), null);
commit;
