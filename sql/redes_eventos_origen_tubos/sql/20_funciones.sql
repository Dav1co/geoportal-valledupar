-- =====================================================================
-- 20 — FUNCIONES INTERNAS NUEVAS (nadie de la API las ejecuta)
-- =====================================================================
-- El origen de un evento, DERIVADO (nada viejo se completa): daño, intervención, trabajo (con su causal) o «No registrado (anterior al cambio)».
create function redes.f_evento_origen(p_evento bigint) returns jsonb
language sql stable set search_path to 'redes', 'pg_temp' as $$
  select case when e.dano_id is not null then jsonb_build_object('codigo', 'dano', 'nombre', 'Daño')
              when e.intervencion_id is not null then jsonb_build_object('codigo', 'intervencion', 'nombre', 'Intervención')
              when c.causal is not null then jsonb_build_object('codigo', 'trabajo', 'nombre', 'Trabajo')
              else jsonb_build_object('codigo', 'no_registrado', 'nombre', 'No registrado (anterior al cambio)') end
    from redes.eventos_suspension e left join redes.evento_causal c on c.evento_id = e.id where e.id = p_evento $$;

-- Los tubos de salida pedidos → sus ids, la unión de sus sectores y subsectores ACTIVOS y el nombre de la zona.
-- Un tubo que no existe o está inactivo, o que no tiene sectores asignados, es error (David, 20-nov).
create function redes.f_tubo_zona(p_codigos text[], out ids bigint[], out sectores bigint[], out geom geometry, out zona_nombre text) returns record
language plpgsql stable set search_path to 'public', 'redes', 'tecnica', 'extensions', 'pg_temp' as $$
declare v_cods text[]; v_c text; v_sin text;
begin
  select array_agg(distinct upper(btrim(x)) order by upper(btrim(x))) into v_cods from unnest(coalesce(p_codigos, '{}')) x where btrim(coalesce(x, '')) <> '';
  if coalesce(cardinality(v_cods), 0) = 0 then perform tecnica.f_error('Escoja al menos un tubo de salida'); end if;
  foreach v_c in array v_cods loop
    if not exists (select 1 from tecnica.puntos p where p.codigo = v_c and p.tipo = 'distribucion' and p.activo) then
      perform tecnica.f_error('Ese tubo de salida no existe o está inactivo.');
    end if;
  end loop;
  select string_agg(p.codigo, ', ' order by p.codigo) into v_sin from tecnica.puntos p
   where p.codigo = any (v_cods) and p.tipo = 'distribucion'
     and not exists (select 1 from redes.tubo_sectores ts join redes.activo_vigente_mat m on m.activo_id = ts.sector_id
                      where ts.punto_id = p.id and ts.activo and m.prefijo = 'SEC' and not m.retirado and not m.oculto);
  if v_sin is not null then perform tecnica.f_error(format('Ese tubo no tiene sectores asignados (%s).', v_sin)); end if;
  select array_agg(p.id order by p.codigo) into ids from tecnica.puntos p where p.codigo = any (v_cods) and p.tipo = 'distribucion';
  select array_agg(distinct m.activo_id order by m.activo_id), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(m.geom)), 3)) into sectores, geom
    from redes.tubo_sectores ts join redes.activo_vigente_mat m on m.activo_id = ts.sector_id
   where ts.punto_id = any (ids) and ts.activo and m.prefijo = 'SEC' and not m.retirado and not m.oculto;
  select case when count(*) = 1 then 'lo que sale por ' || max(coalesce(nullif(btrim(p.nombre), ''), p.codigo)) || ' (' || max(p.codigo) || ')'
              else 'lo que sale por los tubos ' || string_agg(p.codigo, ', ' order by p.codigo) end
    into zona_nombre from tecnica.puntos p where p.id = any (ids);
  zona_nombre := left(zona_nombre, 300);
end $$;
