-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 20 — VISTA DE LA FICHA DEL PERSONAL Y FUNCIONES INTERNAS (nadie de la API las ejecuta)
-- PROPUESTA. No se ha ejecutado en la base real.
-- =====================================================================

-- Ficha vigente de cada persona: el último evento de cada tipo (nulo = sin definir).
create view redes.v_personal_ficha as
select x.persona,
       max(x.valor) filter (where x.tipo_evento = 'fijar_area') as area,
       max(x.valor) filter (where x.tipo_evento = 'fijar_cargo') as cargo,
       max(x.valor) filter (where x.tipo_evento = 'fijar_cuadrilla')::bigint as cuadrilla_id,
       coalesce(max(x.valor) filter (where x.tipo_evento = 'fijar_geovisor') = 'si', false) as geovisor,
       max(x.creado_en) as ultimo_cambio
  from (select distinct on (e.persona, e.tipo_evento) e.persona, e.tipo_evento, e.valor, e.creado_en
          from tecnica.personal_ficha_eventos e order by e.persona, e.tipo_evento, e.id desc) x
 group by x.persona;

-- Área de una persona (planta | distribucion | ambas), o nulo si nadie la ha fijado.
create function redes.f_area(p_email text) returns text
language sql stable security definer set search_path to 'redes', 'tecnica', 'pg_temp' as $f$
  select area from redes.v_personal_ficha where persona = lower(btrim(coalesce(p_email, ''))) $f$;

-- ¿Ve el geovisor principal? (lo usará el Corte 6). El administrador, el supervisor de distribución, el supervisor de planta (abre con muestreo y
-- tanques) y el operador al que se le activó la casilla en Personal (solo lectura, N-13). Tener un formulario de distribución ya no basta.
-- Con el acceso a Técnica desactivado, nadie que no sea el administrador.
create function redes.f_geovisor_lectura(p_email text) returns boolean
language plpgsql stable security definer set search_path to 'public', 'redes', 'tecnica', 'pg_temp' as $f$
declare v text := lower(btrim(coalesce(p_email, '')));
begin
  if v = '' or position('@' in v) < 2 or public.geoportal_estado_acceso(v) <> 'ok' then return false; end if;
  if public.geoportal_es_admin(v) then return true; end if;
  if not tecnica.f_tecnica_activa(v) then return false; end if;
  return public.geoportal_puede(v, 'dashboard_redes') or public.geoportal_puede(v, 'dashboard_tecnico')
      or (public.geoportal_puede(v, 'registro_tecnico') and coalesce((select geovisor from redes.v_personal_ficha where persona = v), false));
end $f$;

-- Personas que salen en Personal del Dashboard distribución: activas en la lista blanca, que no sean administradores, con Registro técnico o
-- Dashboard distribución. Devuelve la fila de la lista blanca o nada.
create function redes.f_persona_tecnica(p_email text) returns public.geoportal_lista_blanca
language sql stable security definer set search_path to 'public', 'pg_temp' as $f$
  select lb.* from public.geoportal_lista_blanca lb
   where lb.email = lower(btrim(coalesce(p_email, ''))) and lb.activo and lb.rol <> 'admin' and (lb.ver_registro_tecnico or lb.ver_dashboard_redes) $f$;

-- Valor entero para los parámetros que se cuentan (fotos, días, horas, filas, bytes, zoom…).
create function redes.f_param_entero(p_unidad text) returns boolean
language sql immutable set search_path to 'pg_catalog' as $f$
  select p_unidad in ('fotos', 'documentos', 'materiales', 'activos', 'días', 'horas', 'filas', 'bytes', 'zoom') $f$;
