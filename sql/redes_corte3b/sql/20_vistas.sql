-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3b · 20 — VISTAS: alias y placa vigentes, fotos del activo y la epicrisis como muro (con los cambios de la ficha)
-- PROPUESTA. No se ha ejecutado en la base real.
-- =====================================================================

-- Alias propio y placa (o número de inventario) vigentes de cada activo que tenga alguno.
create view redes.v_activo_identificadores as
select x.activo_id,
       (select e.valor from redes.activo_identificador_eventos e where e.activo_id = x.activo_id and e.campo = 'alias' order by e.id desc limit 1) as alias,
       (select e.valor from redes.activo_identificador_eventos e where e.activo_id = x.activo_id and e.campo = 'placa' order by e.id desc limit 1) as placa
  from (select distinct activo_id from redes.activo_identificador_eventos) x;

-- Todas las fotos de un activo: las de perfil, las de sus daños (no ocultos) y las de sus intervenciones (principal o también intervenido; sin los PDF).
create function redes.f_fotos_activo(p_activo bigint)
returns table (origen text, codigo text, clase text, ruta text, cuando timestamptz, autor text)
language sql stable set search_path to 'redes', 'pg_temp' as $f$
  select 'perfil', null::text, 'perfil', p.ruta_storage, p.creado_en, p.autor from redes.activo_fotos_perfil p where p.activo_id = p_activo
  union all
  select 'dano', d.codigo, f.momento, f.ruta_storage, d.t_detectado, d.autor from redes.v_dano d join redes.dano_fotos f on f.dano_id = d.id
   where d.activo_id = p_activo and d.estado <> 'oculto'
  union all
  select 'intervencion', i.codigo, a.clase, a.ruta_storage, i.t_fin, i.autor from redes.v_intervencion i join redes.intervencion_archivos a on a.intervencion_id = i.id
   where a.clase <> 'documento' and i.estado <> 'oculta'
     and (i.activo_id = p_activo or exists (select 1 from redes.intervencion_activos x where x.intervencion_id = i.id and x.activo_id = p_activo)) $f$;

-- Epicrisis: la del Corte 3a MÁS los cambios de la ficha. Mismas columnas. La reversa deja el texto del 3a.
create or replace view redes.v_epicrisis as
select v.activo_id, v.creado_en as cuando, case when v.version = 1 then 'alta' else 'version' end as clase, v.id as ref_id,
       case when v.version = 1 then 'Alta del activo' else 'Versión ' || v.version end
         || case when v.carga_id is not null then ' (carga ' || v.carga_id || ')'
                 when v.version = 1 and exists (select 1 from redes.activos x where x.id = v.activo_id and x.origen_alta = 'intervencion')
                   then coalesce(' (inversión ' || (select i.codigo from redes.intervenciones i where i.activo_id = v.activo_id and i.activo_creado limit 1) || ')', ' (intervención)')
                 else ' (ficha)' end as resumen,
       case when v.carga_id is not null and exists (select 1 from redes.carga_eventos e where e.carga_id = v.carga_id and e.tipo = 'revertir') then 'revertida' else 'vigente' end as estado,
       v.autor
  from redes.activo_versiones v
 -- las versiones que creó una edición de la ficha salen una sola vez, como «ficha», con lo que cambió y el motivo (abajo)
 where not exists (select 1 from redes.ficha_ediciones f where f.activo_id = v.activo_id and f.version = v.version)
union all
select e.activo_id, e.creado_en, 'evento_' || e.tipo, e.id, e.motivo, null, e.autor from redes.activo_eventos e
union all
select c.padre_id, c.creado_en, 'componente_' || c.accion, c.id, 'Componente ' || h.codigo || ': ' || c.motivo, null, c.autor
  from redes.activo_componentes c join redes.activos h on h.id = c.hijo_id
union all
select c.hijo_id, c.creado_en, 'es_componente_' || c.accion, c.id, 'Parte de ' || p.codigo || ': ' || c.motivo, null, c.autor
  from redes.activo_componentes c join redes.activos p on p.id = c.padre_id
union all
-- Daños y fallas: el ref_id es el número del código (DAN-000123 → 123), para paginar con el mismo cursor.
select d.activo_id, d.t_detectado, d.clase, substring(d.codigo from 5)::bigint,
       d.codigo || ' · ' || d.tipo_nombre
         || coalesce(' · ' || (select r.nombre from redes.tipos_rotura r where r.codigo = d.tipo_rotura), '')
         || ' · riesgo ' || d.riesgo
         || case d.causa_clase when 'propia' then ' · causa propia' when 'terceros' then ' · causa de terceros' else ' · causa desconocida' end
         || case when d.total_corre then '' else ' · duración ' || (d.total_s / 3600) || ' h ' || lpad(((d.total_s % 3600) / 60)::text, 2, '0') || ' min' end
         || case when d.perdida_m3 is not null then ' · pérdida ≈ ' || d.perdida_m3 || ' m³' else '' end
         || case when not exists (select 1 from redes.dano_fotos f where f.dano_id = d.id) then ' · sin evidencia fotográfica' else '' end,
       case d.estado when 'reportado' then 'Reportado' when 'en_atencion' then 'En atención' when 'atendido' then 'Atendido' else 'Oculto' end,
       d.autor
  from redes.v_dano d
 where d.activo_id is not null and d.estado <> 'oculto'
union all
-- Intervenciones: en el activo principal…
select i.activo_id, i.t_fin, 'intervencion', substring(i.codigo from 5)::bigint,
       i.codigo || ' · ' || i.tipo_nombre
         || case i.inversion_modo when 'nuevo' then ' (activo nuevo)' when 'mejora' then ' (mejora)' else '' end
         || case when i.dano_codigo is not null then ' · atiende ' || i.dano_codigo || case when i.resuelve_dano then ' (lo resuelve)' else ' (sigue abierto)' end else ' · programada o mejora' end
         || case i.ejecutor when 'emdupar' then ' · EMDUPAR' else ' · contratista' || coalesce(' ' || i.contratista, '') end
         || ' · duración ' || (i.duracion_s / 3600) || ' h ' || lpad(((i.duracion_s % 3600) / 60)::text, 2, '0') || ' min'
         || case when i.tambien > 0 then ' · ' || i.tambien || ' activo(s) más' else '' end
         || case when i.sin_evidencia then ' · sin evidencia fotográfica' else ' · ' || i.fotos || ' foto(s)' end,
       case i.estado when 'cerrada' then 'Cerrada' when 'anulada' then 'Anulada' when 'programada' then 'Programada' when 'en_ejecucion' then 'En ejecución' else 'Oculta' end,
       i.autor
  from redes.v_intervencion i
 where i.activo_id is not null and i.estado <> 'oculta'
union all
-- … y en cada activo también intervenido
select x.activo_id, i.t_fin, 'intervencion', substring(i.codigo from 5)::bigint,
       i.codigo || ' · ' || i.tipo_nombre || ' · también intervenido' || coalesce(' (principal ' || i.activo_codigo || ')', ''),
       case i.estado when 'cerrada' then 'Cerrada' when 'anulada' then 'Anulada' when 'programada' then 'Programada' when 'en_ejecucion' then 'En ejecución' else 'Oculta' end,
       i.autor
  from redes.intervencion_activos x join redes.v_intervencion i on i.id = x.intervencion_id
 where i.estado <> 'oculta' and x.activo_id is distinct from i.activo_id
union all
-- Cambios de la ficha (Corte 3b): «Se cambió X de A a B», con el motivo. La corrección del origen no muestra valores ni motivo (solo lo ve el supervisor).
select f.activo_id, f.creado_en, 'ficha', f.id,
       (select string_agg(case c ->> 'campo' when 'origen' then 'Se corrigió el origen del activo'
                                             when 'foto' then 'Nueva foto principal'
                                             else (c ->> 'rotulo') || ': de «' || coalesce(c ->> 'antes', 'sin dato') || '» a «' || coalesce(c ->> 'despues', 'sin dato') || '»' end,
                          '; ' order by o) from jsonb_array_elements(f.cambios) with ordinality y(c, o))
         || case when exists (select 1 from jsonb_array_elements(f.cambios) c where c ->> 'campo' = 'origen') then '' else ' · ' || f.motivo end,
       null, f.autor
  from redes.ficha_ediciones f;
