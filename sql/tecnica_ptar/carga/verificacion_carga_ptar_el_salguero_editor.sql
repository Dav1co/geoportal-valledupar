-- TÉCNICA · PTAR · VERIFICACIÓN DE LA CARGA INICIAL (solo lectura; una consulta, apta para el editor SQL). GeoJSON md5 6cfd0a245b3fc12752a2663db432dfba.
with e as (select e.* from tecnica.elementos_planta e join tecnica.instalaciones i on i.id = e.instalacion_id where i.codigo = 'ptar' and e.activo)
select k, valor, case when ok then 'OK' else 'REVISAR' end as estado from (
  select 1 as o, 'elementos del dibujo (esperado 39)' as k, count(*)::text as valor, count(*) = 39 as ok from e where origen = 'dibujo'
  union all select 2, 'copiados de redes: pozos', count(*)::text, count(*) > 0 from e where origen = 'redes' and tipo = 'pozo'
  union all select 2, 'copiados de redes: descargas (VER)', count(*)::text, bool_and(activo_codigo like 'VER-%') is not false from e where origen = 'redes' and tipo = 'descarga'
  union all select 2, 'ningún activo del dibujo copiado otra vez', (select count(*) from e x join e y on x.activo_codigo = y.activo_codigo and x.origen = 'dibujo' and y.origen = 'redes')::text,
                   not exists (select 1 from e x join e y on x.activo_codigo = y.activo_codigo and x.origen = 'dibujo' and y.origen = 'redes') from (select 1) z
  union all select 3, 'copiados de redes: conductos (tramos sin desde/hasta)', count(*)::text, count(*) > 0 and bool_and(desde_id is null and hasta_id is null) from e where origen = 'redes' and tipo = 'tramo'
  union all select 4, 'perímetro (esperado 1)', count(*)::text, count(*) = 1 from e where tipo = 'perimetro'
  union all select 5, 'lagunas', count(*)::text, count(*) = 31 from e where tipo = 'laguna'
  union all select 5, 'puntos de medición enlazados a su punto de la PTAR (esperado 4)', count(punto_id)::text, count(punto_id) = 4 from e where tipo = 'punto_medicion'
  union all select 6, 'copiados con su activo en redes', count(a.id)::text || ' de ' || count(*)::text, count(a.id) = count(*) from e left join redes.activos a on a.codigo = e.activo_codigo where e.origen = 'redes'
  union all select 7, 'sin activos repetidos', (count(*) - count(distinct activo_codigo))::text, count(*) = count(distinct activo_codigo) from e where activo_codigo is not null
  union all select 8, 'pg-safeupdate: funciones con DELETE/UPDATE sin WHERE', (select count(*) from redes.f_funciones_sin_where())::text, not exists (select 1 from redes.f_funciones_sin_where())
) t order by o;
