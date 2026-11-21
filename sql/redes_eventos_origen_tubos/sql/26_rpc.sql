-- =====================================================================
-- 26 — RPC NUEVAS (las llama la Edge geoportal-redes). Quién puede lo decide redes.f_evento_autorizar(…, 'reportes'), como evento_tipo_fijar
-- y planta_sectores_fijar: el supervisor de distribución y el administrador.
-- =====================================================================
-- Las causales de un evento de trabajo: crear (sin código) o cambiar el nombre, activarla o desactivarla (con código). Siempre con motivo; queda el historial.
create function public.geoportal_redes_evento_causal_fijar(p_solicitante text, p_codigo text, p_nombre text, p_activa boolean, p_motivo text) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'reportes'); v_cod text := nullif(lower(btrim(coalesce(p_codigo, ''))), '');
  v_nom text := nullif(regexp_replace(btrim(coalesce(p_nombre, '')), '\s+', ' ', 'g'), ''); v_mot text := btrim(coalesce(p_motivo, '')); k redes.evento_causales%rowtype; v_acc text;
begin
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  if v_nom is not null and (length(v_nom) < 3 or length(v_nom) > 80) then perform tecnica.f_error('El nombre de la causal va de 3 a 80 letras'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.evento_causales'));
  if v_cod is null then
    if v_nom is null then perform tecnica.f_error('Escriba el nombre de la causal'); end if;
    v_cod := left(trim(both '_' from regexp_replace(translate(lower(v_nom), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', '_', 'g')), 40);
    if v_cod !~ '^[a-z][a-z0-9_]{1,39}$' then perform tecnica.f_error('El nombre de la causal debe empezar con una letra'); end if;
    if exists (select 1 from redes.evento_causales c where c.codigo = v_cod or lower(c.nombre) = lower(v_nom)) then perform tecnica.f_error('Ya hay una causal con ese nombre'); end if;
    insert into redes.evento_causales (codigo, nombre, activa, orden) values (v_cod, v_nom, coalesce(p_activa, true), 50);
    v_acc := 'crear';
  else
    select * into k from redes.evento_causales c where c.codigo = v_cod;
    if k.codigo is null then perform tecnica.f_error('Esa causal no existe', 'P0002'); end if;
    if v_nom is null and p_activa is null then perform tecnica.f_error('Diga qué cambia: el nombre o si está activa'); end if;
    if v_nom is not null and exists (select 1 from redes.evento_causales c where c.codigo <> v_cod and lower(c.nombre) = lower(v_nom)) then perform tecnica.f_error('Ya hay una causal con ese nombre'); end if;
    update redes.evento_causales set nombre = coalesce(v_nom, nombre), activa = coalesce(p_activa, activa) where codigo = v_cod;
    v_acc := 'cambiar';
  end if;
  select * into k from redes.evento_causales c where c.codigo = v_cod;
  insert into redes.evento_causal_eventos (codigo, accion, nombre, activa, motivo, autor) values (k.codigo, v_acc, k.nombre, k.activa, v_mot, v_email);
  return jsonb_build_object('codigo', k.codigo, 'nombre', k.nombre, 'activa', k.activa);
end $$;

-- Qué sectores o subsectores abastece un tubo de salida (la lista completa cada vez, como planta_sectores_fijar). Con motivo; queda el historial.
create function public.geoportal_redes_tubo_sectores_fijar(p_solicitante text, p_tubo text, p_sectores text[], p_motivo text) returns jsonb
language plpgsql security definer set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_email text := redes.f_evento_autorizar(p_solicitante, 'reportes'); v_mot text := btrim(coalesce(p_motivo, '')); v_tubo tecnica.puntos%rowtype; v_cods text[]; v_ids bigint[];
begin
  select * into v_tubo from tecnica.puntos pu where pu.codigo = upper(btrim(coalesce(p_tubo, ''))) and pu.tipo = 'distribucion' and pu.activo;
  if v_tubo.id is null then perform tecnica.f_error('Ese tubo de salida no existe o está inactivo.'); end if;
  if length(v_mot) < 10 or length(v_mot) > 500 then perform tecnica.f_error('Escriba el motivo (de 10 a 500 letras)'); end if;
  select coalesce(array_agg(distinct upper(btrim(x))), '{}') into v_cods from unnest(coalesce(p_sectores, '{}')) x where btrim(coalesce(x, '')) <> '';
  select coalesce(array_agg(m.activo_id order by m.codigo), '{}') into v_ids from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and not m.oculto and m.codigo = any (v_cods);
  if cardinality(v_ids) <> cardinality(v_cods) then perform tecnica.f_error('Alguno de los sectores no existe o ya no está vigente', 'P0002'); end if;
  perform pg_advisory_xact_lock(hashtext('redes.tubo_sectores'));
  update redes.tubo_sectores set activo = false where punto_id = v_tubo.id and activo and sector_id <> all (v_ids);
  insert into redes.tubo_sectores (punto_id, sector_id) select v_tubo.id, x from unnest(v_ids) x
  on conflict (punto_id, sector_id) do update set activo = true;
  insert into redes.tubo_sector_eventos (punto_id, sectores, motivo, autor) values (v_tubo.id, v_ids, v_mot, v_email);
  return jsonb_build_object('tubo', v_tubo.codigo, 'nombre', coalesce(nullif(btrim(v_tubo.nombre), ''), v_tubo.codigo),
                            'sectores', (select coalesce(jsonb_agg(m.codigo order by m.codigo), '[]'::jsonb) from redes.activo_vigente_mat m where m.activo_id = any (v_ids)));
end $$;
