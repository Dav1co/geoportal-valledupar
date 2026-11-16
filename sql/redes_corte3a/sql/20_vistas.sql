-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 3a · 20 — VISTAS: v_intervencion (estado, activo vigente, recursos y evidencia), fuentes vigentes,
-- bandeja de no identificados, v_dano (con el activo asociado) y la epicrisis con las intervenciones.
-- PROPUESTA. No se ha ejecutado en la base real. Nada se escribe calculado: todo se deriva en las vistas.
-- =====================================================================

-- Daño (Corte 2) con UN cambio: el activo vigente es el del último «asociar_activo» (bandeja de no identificados) o, si no hay, el del reporte.
-- Mismas columnas, en el mismo orden. La reversa deja el texto del Corte 2.
create or replace view redes.v_dano as
with b0 as (
  select d.*, coalesce((select e.activo_id from redes.dano_eventos e where e.dano_id = d.id and e.tipo = 'asociar_activo' order by e.id desc limit 1), d.activo_id) as activo_vig
    from redes.danos d),
b as (
  select d.*, tm.t_inicio_reparacion, tm.t_restablecido,
         (select e.tipo = 'ocultar' from redes.dano_eventos e where e.dano_id = d.id and e.tipo in ('ocultar', 'reincluir') order by e.id desc limit 1) as ev_oculto,
         (select e.tipo from redes.dano_eventos e where e.dano_id = d.id and e.tipo in ('atendido', 'reabrir', 'en_atencion') order by e.id desc limit 1) as ev_estado,
         (select a.codigo from redes.activos a where a.id = d.activo_vig) as activo_codigo,
         (select v.diametro_mm from redes.activo_vigente_mat v where v.activo_id = d.activo_vig) as diametro_mm
    from b0 d join redes.v_dano_tiempos tm on tm.dano_id = d.id),
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
       c.sistema, c.activo_vig as activo_id, c.activo_codigo, c.no_ident_que_es, c.lat, c.lon, c.geom, c.ubicacion_origen, c.precision_m, c.fuera_de_zona,
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

-- Fuentes vigentes de cada intervención: las de su última versión.
create view redes.v_intervencion_fuentes as
select f.*
  from redes.intervencion_fuentes f
 where f.version = (select max(x.version) from redes.intervencion_fuentes x where x.intervencion_id = f.intervencion_id);

-- Intervención con lo derivado:
--   activo vigente = el del último «asociar_activo» o, si no hay, el del formulario (o el que creó la inversión);
--   estado = último de programada, en_ejecucion, cerrada o anulada (flujo A: siempre «cerrada» al crearse); oculta = último ocultar/reincluir;
--   recursos = «por_completar» mientras alguna fuente vigente no tenga ni valor ni porcentaje (el operario solo marca quién aporta);
--   sin_evidencia = no tiene ninguna foto (solo puede pasar si la registró un supervisor o el administrador, con su motivo).
create view redes.v_intervencion as
with b as (
  select i.*, coalesce((select e.activo_id from redes.intervencion_eventos e where e.intervencion_id = i.id and e.tipo = 'asociar_activo' order by e.id desc limit 1), i.activo_id) as activo_vig,
         (select e.tipo from redes.intervencion_eventos e where e.intervencion_id = i.id and e.tipo in ('programada', 'en_ejecucion', 'cerrada', 'anulada') order by e.id desc limit 1) as ev_estado,
         coalesce((select e.tipo = 'ocultar' from redes.intervencion_eventos e where e.intervencion_id = i.id and e.tipo in ('ocultar', 'reincluir') order by e.id desc limit 1), false) as oculta,
         (select count(*) from redes.intervencion_archivos a where a.intervencion_id = i.id and a.clase <> 'documento')::integer as fotos,
         (select count(*) from redes.intervencion_archivos a where a.intervencion_id = i.id and a.clase = 'documento')::integer as documentos
    from redes.intervenciones i)
select b.id, b.codigo, b.nace_de, b.dano_id, (select d.codigo from redes.danos d where d.id = b.dano_id) as dano_codigo,
       b.tipo_codigo, (select t.nombre from redes.tipos_intervencion t where t.codigo = b.tipo_codigo) as tipo_nombre, b.inversion_modo,
       b.sistema, b.activo_vig as activo_id, (select a.codigo from redes.activos a where a.id = b.activo_vig) as activo_codigo, b.activo_creado,
       b.no_ident_que_es, b.lat, b.lon, b.geom, b.ubicacion_origen, b.precision_m, b.fuera_de_zona,
       b.t_inicio, b.t_fin, extract(epoch from (b.t_fin - b.t_inicio))::bigint as duracion_s, b.inicio_en, b.inicio_origen, b.descripcion,
       b.ejecutor, b.contratista_id, coalesce((select c.nombre from redes.contratistas c where c.id = b.contratista_id), b.contratista_nombre) as contratista,
       b.contrato_orden, b.companeros, b.sin_evidencia_motivo, b.autor, b.registrado_en,
       case when b.oculta then 'oculta' else coalesce(b.ev_estado, 'cerrada') end as estado,
       b.fotos, b.documentos, b.fotos = 0 as sin_evidencia,
       case when exists (select 1 from redes.v_intervencion_fuentes f where f.intervencion_id = b.id and f.valor is null and f.porcentaje is null) then 'por_completar' else 'completos' end as recursos,
       (select array_agg(coalesce(f.entidad, e.nombre) order by f.n) from redes.v_intervencion_fuentes f join redes.entidades_aportantes e on e.codigo = f.aportante_codigo
         where f.intervencion_id = b.id) as aportantes,
       (select count(*) from redes.intervencion_activos x where x.intervencion_id = b.id)::integer as tambien
  from b;

-- Bandeja de «activo no identificado» (para el supervisor): intervenciones y daños sin activo vigente, que no estén ocultos.
create view redes.v_no_identificados as
select 'intervencion'::text as clase, i.id, i.codigo, i.sistema, i.no_ident_que_es as que_es, i.lat, i.lon, i.geom, i.t_fin as cuando, i.tipo_nombre as resumen, i.estado, i.autor, i.registrado_en
  from redes.v_intervencion i
 where i.activo_id is null and i.estado <> 'oculta'
union all
select 'dano', d.id, d.codigo, d.sistema, d.no_ident_que_es, d.lat, d.lon, d.geom, d.t_detectado, d.tipo_nombre, d.estado, d.autor, d.registrado_en
  from redes.v_dano d
 where d.activo_id is null and d.estado <> 'oculto';

-- Epicrisis: la del Corte 2 (altas, versiones, eventos, componentes, daños y fallas) MÁS las intervenciones (clase «intervencion»), en el activo
-- principal y en cada «también intervenido». El ref_id es el número del código (ITV-000123 → 123), para paginar con el mismo cursor.
-- Mismas columnas que en el Corte 2. La reversa deja el texto del Corte 2.
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
         || case when i.dano_codigo is not null then ' · atiende ' || i.dano_codigo else ' · programada o mejora' end
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
 where i.estado <> 'oculta' and x.activo_id is distinct from i.activo_id;
