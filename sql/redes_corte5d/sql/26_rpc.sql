-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 26 — RPC NUEVA (solo service_role, por la Edge geoportal-redes)
-- «Convertir en daño», todavía sin botón (encargo del 5d, punto 6): deja anotado de qué reporte de la 116 salió un daño ya creado con el formulario de daño.
-- El camino previsto: el botón de la tarjeta del geovisor abrirá el formulario de daño en el punto del reporte y, al guardarlo, llamará a esta RPC.
-- Solo el supervisor de distribución o el administrador. Con motivo. Solo se agrega (no se desvincula).
-- =====================================================================
create function public.geoportal_redes_l116_vincular_dano(p_solicitante text, p_reporte bigint, p_dano text, p_motivo text, p_ip text default null)
returns jsonb language plpgsql security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_email text := redes.f_supervisor(p_solicitante, 'convierten los reportes de la línea 116 en daño'); v_mot text := btrim(coalesce(p_motivo, ''));
        v_rep redes.l116_reportes%rowtype; v_dano record;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  select * into v_rep from redes.l116_reportes where reporte = p_reporte;
  if not found then perform tecnica.f_error('No existe ese reporte de la línea 116', 'P0002'); end if;
  if (select oculto from redes.l116_vigente where reporte_id = v_rep.id) then perform tecnica.f_error('Ese reporte está oculto (su carga se revirtió)', '55000'); end if;
  select d.id, d.codigo, d.estado into v_dano from redes.v_dano d where d.codigo = upper(btrim(coalesce(p_dano, '')));
  if v_dano.id is null then perform tecnica.f_error('No existe ese daño', 'P0002'); end if;
  if v_dano.estado = 'oculto' then perform tecnica.f_error('Ese daño está oculto', '55000'); end if;
  if exists (select 1 from redes.l116_danos where reporte_id = v_rep.id and dano_id = v_dano.id) then perform tecnica.f_error('Ese reporte ya está unido a ese daño'); end if;
  insert into redes.l116_danos (reporte_id, dano_id, motivo, autor) values (v_rep.id, v_dano.id, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_l116_vincular_dano', p_reporte::text, jsonb_build_object('dano', v_dano.codigo, 'motivo', v_mot), p_ip);
  return jsonb_build_object('reporte', p_reporte, 'dano', v_dano.codigo, 'unido', true);
end $$;
