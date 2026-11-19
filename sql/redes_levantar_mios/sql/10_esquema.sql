-- =====================================================================
-- TÉCNICA · FASE 1 · «MIS REPORTES» (levantar_mios) · 10 — GUARDIA E ÍNDICE
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: contrato del Code B (paquete_fase1/mis_reportes_y_repetidos/ENTRADA_BITACORA.md) y encargo de David del 19-nov.
-- · Presupone el Corte 15 publicado: huella del conjunto de funciones de redes ef7564883f523685cfe36478e0985e98.
-- · SOLO AGREGA 1 RPC de lectura y 1 índice (por autor) en redes.levantar_puntos. No reemplaza ninguna función, no crea tablas ni parámetros
--   y no cambia quién puede reportar ni quién ve la bandeja del supervisor.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_levantar_mios(text,integer)') is not null or to_regclass('redes.ix_levantar_puntos_autor') is not null then raise exception '«Mis reportes» ya está aplicado: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'ef7564883f523685cfe36478e0985e98' then
    raise exception 'Las funciones de redes no son las del Corte 15 publicado (huella ef7564883f523685cfe36478e0985e98): deténgase y avise';
  end if;
  if to_regclass('redes.levantar_puntos') is null or to_regclass('redes.v_levantar_punto') is null or to_regprocedure('redes.f_levantar_acceso(text)') is null
     or to_regprocedure('redes.f_levantar_tipo_nombre(text)') is null or to_regprocedure('redes.f_levantar_estado_nombre(text)') is null then
    raise exception 'Faltan tablas o funciones del Corte 14 («Encontrar o reportar activo»): deténgase y avise';
  end if;
end $$;
-- «los míos, los últimos primero»: por autor y fecha (la tabla solo tenía índice por fecha y por lugar)
create index ix_levantar_puntos_autor on redes.levantar_puntos (autor, registrado_en desc);
