-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO · 26 — RPC (la llama la Edge geoportal-redes, ruta evento_contrato).
--   · geoportal_redes_evento_contrato: dado un contrato, si HOY está dentro de un evento de suspensión abierto, y cuál (el más específico).
-- Para qué: que Comercial, Campo y el acta, al buscar o verificar un contrato, vean «este contrato está sin agua por el evento EVS-…» antes de mandar a alguien o de
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
