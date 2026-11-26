-- =====================================================================
-- CONSULTAR DIRECCIONES (Code A, 25-nov) · 20 — FUNCIONES NUEVAS
-- campo.f_texto_censo(t, colapsar_palabras): limpieza MÍNIMA de un texto del censo: recorta, colapsa espacios y, si se pide (clase de uso), una palabra repetida
--   seguida («RESIDENCIAL RESIDENCIAL» → «RESIDENCIAL»; «RESIDENCIAL COMERCIAL» se deja). Vacío = nulo. No interpreta ni recodifica.
-- campo.f_direcciones_contrato(contrato): las dos direcciones, por separado y sin mezclarlas: base comercial (cartera_suscripcion, último corte) y catastro
--   (catastro_valledupar, predio principal = menor id), cada una con su barrio, y cuántos predios tiene el contrato en el censo. Todo por índice
--   (idx_cartera_contrato, idx_catastro_cod_usuario). Nada más: ni nombre, ni teléfono, ni deuda.
-- geoportal_campo_direccion_contrato: la ruta de los formatos (quien tiene permiso de campo; desde Técnica, geoportal_campo_tec_direccion_contrato). Queda en la
--   bitácora campo.consultas_analisis con via = 'formato'. Tope: limite_direccion_hora por hora (supervisor × multiplo_supervisor; administrador sin tope);
--   los contratos inexistentes también cuentan.
-- =====================================================================
create function campo.f_texto_censo(p_texto text, p_colapsar_palabras boolean default false)
 returns text
 language sql
 immutable
 set search_path to 'pg_catalog'
as $function$
  select nullif(case when p_colapsar_palabras then regexp_replace(t, '(^| )([^ ]+)( \2)+(?= |$)', '\1\2', 'g') else t end, '')
    from (select btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')) as t) x
$function$;
revoke all on function campo.f_texto_censo(text, boolean) from public, anon, authenticated, service_role;

create function campo.f_direcciones_contrato(p_contrato text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'campo', 'pg_temp'
as $function$
  select jsonb_build_object(
    'encontrado', cs.contrato is not null or pr.id is not null,
    'comercial', case when cs.contrato is not null then jsonb_build_object('direccion', campo.f_texto_censo(cs.direccion), 'barrio', campo.f_texto_censo(cs.barrio), 'corte', cs.periodo_carga) end,
    'catastro', case when pr.id is not null then jsonb_build_object('direccion', campo.f_texto_censo(pr.direccion), 'barrio', campo.f_texto_censo(pr.barrio)) end,
    'predios_total', (select count(*) from public.catastro_valledupar c where c.cod_usuario = p_contrato))
    from (select 1) uno
    left join lateral (select s.contrato, s.direccion, s.barrio, s.periodo_carga from public.cartera_suscripcion s where s.contrato = p_contrato
                        order by s.periodo_carga desc nulls last limit 1) cs on true
    left join lateral (select c.id, c.direccion, c.barrio from public.catastro_valledupar c where c.cod_usuario = p_contrato order by c.id limit 1) pr on true
$function$;
revoke all on function campo.f_direcciones_contrato(text) from public, anon, authenticated, service_role;

create function public.geoportal_campo_direccion_contrato(p_solicitante text, p_contrato text, p_ip text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'campo', 'pg_temp'
as $function$
declare v_email text; v_perfil text; v_c text := btrim(coalesce(p_contrato, '')); v_lim integer; v_n integer; v_primero timestamptz; v jsonb;
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);    -- quien registra en campo (o entra por la ruta de Técnica, que ya lo autorizó)
  v_perfil := campo.f_perfil(v_email);
  if v_c !~ '^\d{1,12}$' then perform campo.f_error('Escriba solo los números del contrato (hasta 12 dígitos).'); end if;
  -- Tope por hora (decisión de David): consultas de dirección desde formatos, existan o no los contratos
  if v_perfil is distinct from 'admin' then
    v_lim := campo.f_param('limite_direccion_hora')::integer * case when v_perfil = 'supervisor' then campo.f_param('multiplo_supervisor')::integer else 1 end;
    perform pg_advisory_xact_lock(hashtextextended('campo_direccion:' || v_email, 0));
    select count(*), min(q.consultado_en) into v_n, v_primero from campo.consultas_analisis q
     where q.autor = v_email and q.via = 'formato' and q.consultado_en > clock_timestamp() - interval '1 hour';
    if v_n >= v_lim then
      perform campo.f_error_limite(format('Llegó al límite de %s consultas de dirección en una hora. Podrá consultar otra dentro de %s.',
                                          v_lim, campo.f_texto_espera(v_primero, 60)));
    end if;
  end if;
  if v_c = '99999999' then
    insert into campo.consultas_analisis (autor, contrato, existe, ip, via) values (v_email, v_c, true, left(p_ip, 64), 'formato');
    return jsonb_build_object('encontrado', true, 'comodin', true, 'contrato', v_c);
  end if;
  v := campo.f_direcciones_contrato(v_c);
  insert into campo.consultas_analisis (autor, contrato, existe, ip, via) values (v_email, v_c, (v ->> 'encontrado')::boolean, left(p_ip, 64), 'formato');
  if not (v ->> 'encontrado')::boolean then return jsonb_build_object('encontrado', false, 'contrato', v_c); end if;
  return v || jsonb_build_object('contrato', v_c, 'comodin', false,
    -- «distintas»: las dos existen y no son el mismo texto (sin distinguir mayúsculas ni espacios)
    'distintas', v -> 'comercial' ->> 'direccion' is not null and v -> 'catastro' ->> 'direccion' is not null
                 and upper(v -> 'comercial' ->> 'direccion') <> upper(v -> 'catastro' ->> 'direccion'));
end $function$;
revoke all on function public.geoportal_campo_direccion_contrato(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_direccion_contrato(text, text, text) to service_role;

-- Desde Técnica (formulario compartido «Reportar anomalía»): autoriza por el formulario de Técnica y usa la misma función
create function public.geoportal_campo_tec_direccion_contrato(p_solicitante text, p_contrato text, p_ip text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'campo', 'tecnica', 'pg_temp'
as $function$
declare v jsonb;
begin
  perform campo.f_tecnica_entrar(p_solicitante, null);      -- «Reportar anomalía» de Técnica (anomalia_compartida)
  v := public.geoportal_campo_direccion_contrato(p_solicitante, p_contrato, p_ip);
  perform set_config('geoportal.via_tecnica', '', true);
  return v;
end $function$;
revoke all on function public.geoportal_campo_tec_direccion_contrato(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_campo_tec_direccion_contrato(text, text, text) to service_role;
