-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 20 — FUNCIONES INTERNAS NUEVAS (nadie de la API las ejecuta)
--   · redes.f_nodo_visible_id, redes.f_nodo_de_activo y redes.f_tramos_de_nodo: el nodo vigente de un id o de un activo y los tramos que le llegan, POR ÍNDICE.
--     Antes, la ficha los buscaba en las vistas v_nodo_visible y v_tramo_nodos_vigente filtrando por una columna que no es su llave: cada ficha ordenaba
--     todos los nodos y recorría TODA la tabla de versiones de activos (con sus geometrías). En producción, 4,4 s por ficha.
--     Ahora se toma la llave del nodo (sistema y llave del modelo, la llave de la vista) y la vista se consulta solo por ella.
--   · redes.f_sector_en: el sector hidráulico de un punto (latitud y longitud), para el formulario de daño y para el daño que entra del bot.
--   · redes.f_operador_redes: quién es «operador de redes» (ve la Ficha de activos en modo buscar, solo lectura).
-- =====================================================================
create function redes.f_nodo_visible_id(p_nodo bigint) returns setof redes.v_nodo_visible
language plpgsql stable set search_path = redes, public, pg_temp as $$
declare v_s text; v_l text;
begin
  select x.sistema, x.llave_modelo into v_s, v_l from redes.nodos x where x.id = p_nodo;
  if v_s is null then return; end if;
  -- por la llave de la vista (sistema, llave_modelo): la condición entra en la vista y usa el índice ix_nodos_llave. Si el id no es el vigente de su llave, no sale (igual que antes).
  return query select * from redes.v_nodo_visible n where n.sistema = v_s and n.llave_modelo = v_l and n.nodo_id = p_nodo;
end $$;

create function redes.f_nodo_de_activo(p_activo bigint) returns setof redes.v_nodo_visible
language plpgsql stable set search_path = redes, public, pg_temp as $$
declare k record;
begin
  -- las llaves candidatas: el nodo que nació con el activo (carga) o al que se le enlazó (bandeja de nodos)
  for k in select x.sistema, x.llave_modelo from redes.nodos x where x.activo_id = p_activo
           union
           select x.sistema, x.llave_modelo from redes.nodo_eventos e join redes.nodos x on x.id = e.nodo_id where e.activo_id = p_activo and e.tipo = 'enlazar_activo' loop
    return query select * from redes.v_nodo_visible n where n.sistema = k.sistema and n.llave_modelo = k.llave_modelo and n.activo_id = p_activo;
  end loop;
end $$;

create function redes.f_tramos_de_nodo(p_nodo bigint) returns integer
language sql stable set search_path = redes, pg_temp as $$
  -- la versión vigente de cada tramo es la de activo_vigente_mat (la misma que daba la vista), por los índices de tramo_nodos
  select count(*)::integer from redes.tramo_nodos t join redes.activo_vigente_mat m on m.activo_id = t.activo_id and m.version = t.version
   where t.nodo_ini = p_nodo or t.nodo_fin = p_nodo $$;

create function redes.f_sector_en(p_lat numeric, p_lon numeric, out sector integer, out subsector text, out codigo text, out nombre text)
language plpgsql stable set search_path = redes, public, extensions, pg_temp as $$
begin
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then return; end if;
  select s.sector, s.subsector, s.codigo, s.nombre into sector, subsector, codigo, nombre
    from redes.f_sector_de(ST_SetSRID(ST_MakePoint(p_lon::double precision, p_lat::double precision), 4326)) s;
end $$;

create function redes.f_operador_redes(p_email text) returns boolean
language sql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
  -- área distribución (o las dos) en Personal, un formulario de distribución asignado o la casilla del geovisor
  select coalesce(redes.f_area(p_email) in ('distribucion', 'ambas'), false)
      or coalesce(redes.f_puede_formulario(p_email, 'danos_fallas'), false) or coalesce(redes.f_puede_formulario(p_email, 'mantenimiento'), false)
      or coalesce(redes.f_geovisor_lectura(p_email), false) $$;
