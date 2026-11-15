-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 2 · 20 — VISTAS: v_dano (tiempos, estado y pérdida calculados), v_reporte_externo y la epicrisis con daños
-- PROPUESTA. No se ha ejecutado en la base real. Nada se escribe calculado: todo se deriva en las vistas.
-- =====================================================================

-- Tiempos vigentes de la reparación: el último valor no nulo de cada uno.
create view redes.v_dano_tiempos as
select d.id as dano_id,
       (select t.t_inicio_reparacion from redes.dano_tiempos t where t.dano_id = d.id and t.t_inicio_reparacion is not null order by t.id desc limit 1) as t_inicio_reparacion,
       (select t.t_restablecido from redes.dano_tiempos t where t.dano_id = d.id and t.t_restablecido is not null order by t.id desc limit 1) as t_restablecido
  from redes.danos d;

-- Daño con sus cálculos (01 §B):
--   respuesta = inicio de la reparación − detectado; reparación = restablecido − inicio de la reparación;
--   total = restablecido (o ahora, si sigue abierto) − (inicio del daño, o detectado);
--   estado: oculto (último ocultar/reincluir) > atendido (evento «atendido» después del último «reabrir», o restablecido) > en atención (hay inicio de reparación) > reportado;
--   pérdida = caudal de fuga (caudales_fuga por diámetro del activo, tipo de rotura y presión) × total. Sin tabla, «sin_tabla» y nula.
create view redes.v_dano as
with b as (
  select d.*, tm.t_inicio_reparacion, tm.t_restablecido,
         (select e.tipo = 'ocultar' from redes.dano_eventos e where e.dano_id = d.id and e.tipo in ('ocultar', 'reincluir') order by e.id desc limit 1) as ev_oculto,
         (select e.tipo from redes.dano_eventos e where e.dano_id = d.id and e.tipo in ('atendido', 'reabrir', 'en_atencion') order by e.id desc limit 1) as ev_estado,
         (select a.codigo from redes.activos a where a.id = d.activo_id) as activo_codigo,
         (select v.diametro_mm from redes.activo_vigente_mat v where v.activo_id = d.activo_id) as diametro_mm
    from redes.danos d join redes.v_dano_tiempos tm on tm.dano_id = d.id),
c as (
  select b.*,
         case when coalesce(b.ev_oculto, false) then 'oculto'
              when b.ev_estado = 'atendido' or (b.t_restablecido is not null and b.ev_estado is distinct from 'reabrir') then 'atendido'
              when b.t_inicio_reparacion is not null or b.ev_estado in ('en_atencion', 'reabrir') then 'en_atencion'
              else 'reportado' end as estado,
         extract(epoch from (b.t_inicio_reparacion - b.t_detectado))::bigint as respuesta_s,
         extract(epoch from (b.t_restablecido - b.t_inicio_reparacion))::bigint as reparacion_s,
         extract(epoch from (coalesce(b.t_restablecido, clock_timestamp()) - coalesce(b.t_inicio_dano, b.t_detectado)))::bigint as total_s,
         b.t_restablecido is null as total_corre,
         (select q.caudal_lps from redes.caudales_fuga q
           where q.tipo_rotura = b.tipo_rotura and b.diametro_mm between q.diametro_min_mm and q.diametro_max_mm
             and (b.presion_mca is null and q.presion_min_mca is null and q.presion_max_mca is null
                  or b.presion_mca between coalesce(q.presion_min_mca, 0) and coalesce(q.presion_max_mca, 1000))
           order by q.vigente_desde desc, q.id desc limit 1) as caudal_lps
    from b)
select c.id, c.codigo, c.clase, c.tipo_codigo, (select t.nombre from redes.tipos_dano t where t.codigo = c.tipo_codigo) as tipo_nombre,
       c.sistema, c.activo_id, c.activo_codigo, c.no_ident_que_es, c.lat, c.lon, c.geom, c.ubicacion_origen, c.precision_m, c.fuera_de_zona,
       c.t_inicio_dano, c.t_detectado, c.t_inicio_reparacion, c.t_restablecido, c.inicio_en, c.inicio_origen,
       c.tipo_rotura, c.largo_afectado_m, c.presion_mca, c.usuarios_sin_servicio, c.usuarios_propuesta, c.sector_texto, c.riesgo, c.marcas,
       c.causa_clase, c.causa_codigo, c.tercero_tipo, c.descripcion, c.origen, c.reporte_externo_id, c.autor, c.registrado_en,
       c.estado, c.respuesta_s, c.reparacion_s, c.total_s, c.total_corre, c.caudal_lps,
       case when c.caudal_lps is not null then round(c.caudal_lps * c.total_s / 1000.0, 1) end as perdida_m3,
       case when c.caudal_lps is not null then 'calculada'
            when c.clase = 'falla' or c.tipo_rotura is null then 'no_aplica'
            when not exists (select 1 from redes.caudales_fuga) then 'sin_tabla'
            when c.diametro_mm is null then 'sin_diametro'
            else 'sin_fila' end as perdida_estado
  from c;

-- Reporte del bot con su estado vigente y el que se le devuelve al bot (recibido, en atención, atendido o descartado).
create view redes.v_reporte_externo as
select r.id, r.radicado, r.canal, r.origen, r.tipo_bot, r.lat, r.lon, r.geom, r.direccion, r.descripcion, r.recibido_en, r.registrado_en,
       e.tipo as ultimo_evento, e.dano_id, d.codigo as dano_codigo, d.estado as dano_estado,
       case e.tipo when 'descartado' then 'descartado'
                   when 'convertido' then case d.estado when 'atendido' then 'atendido' else 'en_atencion' end
                   when 'atendido' then 'atendido' when 'en_atencion' then 'en_atencion' else 'recibido' end as estado_bot,
       (select count(*) from redes.reporte_externo_fotos f where f.reporte_id = r.id) as fotos
  from redes.reportes_externos r
  left join lateral (select x.tipo, x.dano_id from redes.reporte_externo_eventos x where x.reporte_id = r.id order by x.id desc limit 1) e on true
  left join redes.v_dano d on d.id = e.dano_id;

-- Epicrisis: la del 1a (altas, versiones, eventos y componentes) MÁS los daños y fallas del activo (clase «dano» o «falla»).
-- Mismas columnas que en el 1a. La reversa deja el texto del 1a.
create or replace view redes.v_epicrisis as
select v.activo_id, v.creado_en as cuando, case when v.version = 1 then 'alta' else 'version' end as clase, v.id as ref_id,
       case when v.version = 1 then 'Alta del activo' else 'Versión ' || v.version end
         || case when v.carga_id is not null then ' (carga ' || v.carga_id || ')' else ' (ficha)' end as resumen,
       case when v.carga_id is not null and exists (select 1 from redes.carga_eventos e where e.carga_id = v.carga_id and e.tipo = 'revertir') then 'revertida' else 'vigente' end as estado,
       v.autor
  from redes.activo_versiones v
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
         || case when d.perdida_m3 is not null then ' · pérdida ≈ ' || d.perdida_m3 || ' m³' else '' end,
       case d.estado when 'reportado' then 'Reportado' when 'en_atencion' then 'En atención' when 'atendido' then 'Atendido' else 'Oculto' end,
       d.autor
  from redes.v_dano d
 where d.activo_id is not null and d.estado <> 'oculto';
