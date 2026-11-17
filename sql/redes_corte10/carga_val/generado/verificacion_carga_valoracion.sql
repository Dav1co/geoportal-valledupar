-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 — VERIFICACIÓN DE LA CARGA DEL INVENTARIO REGULATORIO (solo lectura, una consulta; apta para el editor SQL web).
-- Generado por carga_val/carga_val.py. Todas las filas deben decir OK (las INFO son informativas).
-- =====================================================================
select k, v from (
  select 1 as o, '01 la valoración vigente es la de este paquete (Valoracion_Tecnica_Valledupar_04122019.xlsx)' as k,
         case when (select md5 from redes.v_ref_carga_vigente where conjunto = 'valoracion') = '16e6a5e96e756700de07e0c92cdf40c3' then 'OK' else 'MAL' end as v
  union all select 2, '02 3 hojas con 59, 39 y 68 filas, y su BCR0 cuadra con la suma del valor remanente',
         case when (select string_agg(h.hoja || '=' || (select count(*) from redes.val_filas f where f.carga_id = h.carga_id and f.hoja = h.hoja), ',' order by h.hoja)
                      from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion')) = 'acueducto=59,alcantarillado=39,alcantarillado_2=68'
               and not exists (select 1 from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion')
                                and abs(h.bcr0 - (select sum(coalesce(f.valor_remanente, 0)) from redes.val_filas f where f.carga_id = h.carga_id and f.hoja = h.hoja)) >= 1) then 'OK' else 'MAL' end
  union all select 3, '03 el amarre vigente es el de este paquete y se hizo contra la valoración vigente',
         case when (select md5 from redes.v_ref_carga_vigente where conjunto = 'val_amarre') = '40bf197729ebbd8a662e9df4f581f326'
               and not exists (select 1 from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.val_carga_id <> redes.f_ref_vigente('valoracion')) then 'OK' else 'MAL' end
  union all select 4, '04 ningún activo cambió de versión por la carga (la ficha oficial no se toca)',
         case when not exists (select 1 from redes.activo_versiones v join redes.ref_cargas c on c.conjunto = 'val_amarre' and c.id = redes.f_ref_vigente('val_amarre')
                                where v.autor = c.autor and v.creado_en between c.creado_en - interval '1 minute' and c.creado_en + interval '5 minutes') then 'OK' else 'REVISAR' end
  union all select 5, 'INFO hoja de alcantarillado que vale · BCR0 por hoja (millones)',
         redes.f_val_hoja_alc() || ' · ' || (select string_agg(h.nombre_hoja || ' ' || round(h.bcr0 / 1e6), ' · ' order by h.hoja) from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion'))
  union all select 6, 'INFO amarre (hojas vigentes): activos con fila · sin fila · proyectados',
         (select count(distinct am.activo_id) filter (where am.n is not null) || ' · ' || count(distinct am.activo_id) filter (where am.situacion = 'sin_fila') || ' · '
                 || count(distinct am.activo_id) filter (where am.situacion = 'proyectado')
            from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja in ('acueducto', redes.f_val_hoja_alc()))
) t order by o;
