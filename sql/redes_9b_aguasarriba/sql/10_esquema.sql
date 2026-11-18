-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · «CIERRE POR AGUAS ARRIBA» · 10 — GUARDIA Y PARÁMETROS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: pedido de David del 17-nov (caso real RED-000077 / VAL-000684).
-- · Presupone el Corte 14 publicado: huella del conjunto de funciones de redes 1a9ef250a74fb01962f463d98834cc4a.
-- · SOLO AGREGA: 4 funciones internas, 1 RPC y 2 parámetros. No reemplaza ninguna función: la simulación de hoy (redes.f_simular_cierre) queda igual,
--   como «Aislamiento total». No toca tecnica.f_avisos, Personal, «Por verificar» ni el geovisor. Sin tablas nuevas. Solo base de datos: la ruta de la Edge
--   y la pantalla son del Code B.
-- =====================================================================
do $$
begin
  if to_regprocedure('redes.f_simular_aguas_arriba(bigint)') is not null then raise exception '«Cierre por aguas arriba» ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '1a9ef250a74fb01962f463d98834cc4a' then
    raise exception 'Las funciones de redes no son las del Corte 14 publicado (huella 1a9ef250a74fb01962f463d98834cc4a): deténgase y avise';
  end if;
  if to_regclass('redes.flujo_modelo') is null or to_regclass('redes.pm_nodos') is null or to_regprocedure('redes.f_simular_cierre(bigint)') is null then
    raise exception 'Faltan tablas o funciones del 9a o del 9b: deténgase y avise';
  end if;
end $$;

insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('sim_aguas_arriba_criterio', 1, '1 cota, 2 modelo', 1, 2,
   'Cierre por aguas arriba (Corte 9b): con qué se decide por dónde entra el agua. 1: la altura del terreno (el agua baja). 2: el flujo del modelo. El otro se muestra como comprobación'),
  ('sim_cota_minima_m', 0.1, 'm', 0, 5,
   'Cierre por aguas arriba (Corte 9b): desnivel mínimo entre los dos extremos de un tramo para decir hacia dónde baja el agua; con menos, el tramo queda sin sentido')
on conflict (clave) do update set estado = 'vigente', valor = excluded.valor, descripcion = excluded.descripcion;
