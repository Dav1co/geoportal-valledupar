-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b, Fase 3 — VERIFICACIÓN DE LA CARGA DEL FLUJO DEL MODELO (solo lectura, una consulta; apta para el editor SQL web).
-- Generado por carga_flujo/carga_flujo.py. Todas las filas deben decir OK (las INFO son informativas).
-- =====================================================================
select k, v from (
  select 1 as o, '01 el flujo vigente es el de este paquete (flujo_modelo_v1.csv)' as k,
         case when (select md5 from redes.v_ref_carga_vigente where conjunto = 'flujo_modelo') = '2b0b8616697e22427f7019f766de1448' then 'OK' else 'MAL' end as v
  union all select 2, '02 9580 tubos; 8669 con su tramo de la red y 911 sin tramo',
         case when (select count(*) = 9580 and count(activo_id) = 8669 from redes.flujo_modelo where carga_id = redes.f_ref_vigente('flujo_modelo')) then 'OK' else 'MAL' end
  union all select 3, '03 las dos horas: mayor 17:00 y menor 23:00',
         case when (select string_agg(cual || '=' || hora, ',' order by cual) from redes.flujo_modelo_horas where carga_id = redes.f_ref_vigente('flujo_modelo')) = 'mayor=17,menor=23' then 'OK' else 'MAL' end
  union all select 4, '04 una sola carga de flujo vigente y ningún tramo con dos tubos',
         case when (select count(*) from redes.v_ref_carga_vigente where conjunto = 'flujo_modelo') = 1
               and not exists (select 1 from redes.flujo_modelo where carga_id = redes.f_ref_vigente('flujo_modelo') and activo_id is not null group by activo_id having count(*) > 1) then 'OK' else 'MAL' end
  union all select 5, 'INFO tramos de acueducto visibles con flecha · sin dato del modelo',
         (select count(*) filter (where f.activo_id is not null) || ' · ' || count(*) filter (where f.activo_id is null)
            from redes.activo_vigente_mat m left join redes.flujo_modelo f on f.carga_id = redes.f_ref_vigente('flujo_modelo') and f.activo_id = m.activo_id
           where m.sistema = 'acueducto' and m.prefijo in ('RED', 'CON') and not m.retirado and not m.oculto)
) t order by o;
