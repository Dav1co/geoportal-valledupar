-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · CORRECCIÓN «LA VÁLVULA QUE CERRÓ EL OPERADOR» · 26 — RPC (la llama la Edge geoportal-redes, ruta cierres_registro).
--   · geoportal_redes_cierres_registro: las válvulas que ese daño o esa intervención tiene cerradas AHORA (su «cerrar» sin «abrir»), para que el panel
--     «Cierre de válvulas» las muestre como cerradas y ofrezca «Válvula abierta».
-- Por qué: el panel leía geoportal_redes_cortes_vigentes, que es del geovisor (exige la casilla del geovisor). El operador sin esa casilla cerraba la válvula
--   (el cierre sí se guardaba) y el panel no se la mostraba cerrada ni le dejaba abrirla. Esta lectura NO da el geovisor: solo las válvulas de ESE registro.
-- Quién: los mismos de la simulación de cierre (quien captura daños y fallas o intervenciones, el supervisor y el administrador). «puede_abrir» dice si esa
--   persona tiene el formulario que la maniobra exige para abrir (daño: daños y fallas; intervención: mantenimiento); la maniobra lo vuelve a decidir.
-- Solo lectura: no guarda ni audita (no hay datos de suscriptores: «quién» es el nombre del funcionario).
-- =====================================================================
create function public.geoportal_redes_cierres_registro(p_solicitante text, p_registro text)
returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare v_email text := redes.f_sim_autorizar(p_solicitante); v_cod text := upper(btrim(coalesce(p_registro, ''))); v_dano uuid; v_itv uuid;
begin
  if v_cod ~ '^DAN-[0-9]{6}$' then select id into v_dano from redes.danos where codigo = v_cod;
  elsif v_cod ~ '^ITV-[0-9]{6}$' then select id into v_itv from redes.intervenciones where codigo = v_cod;
  else perform tecnica.f_error('Escriba el código del daño (DAN-000123) o de la intervención (ITV-000123)');
  end if;
  if v_dano is null and v_itv is null then perform tecnica.f_error(format('No hay ningún daño ni intervención con el código «%s»', v_cod), 'P0002'); end if;
  return jsonb_build_object(
    'registro', v_cod,
    'puede_abrir', redes.f_puede_formulario(v_email, case when v_dano is not null then 'danos_fallas' else 'mantenimiento' end),
    'valvulas', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', v.codigo, 'nombre', coalesce(v.codigo_anterior, v.codigo), 'desde', m.hecho_en,
               'quien', coalesce((select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = m.autor), 'Funcionario de EMDUPAR'),
               'registro', v_cod, 'regreso_estimado', redes.f_cierre_regreso(m.id)) order by m.hecho_en, m.id)
        from redes.valvula_maniobras m join redes.activo_vigente_mat v on v.activo_id = m.valvula_id
       where m.tipo = 'cerrar' and ((v_dano is not null and m.dano_id = v_dano) or (v_itv is not null and m.intervencion_id = v_itv))
         and not exists (select 1 from redes.valvula_maniobras ab where ab.cierre_id = m.id and ab.tipo = 'abrir')), '[]'::jsonb));
end $$;
