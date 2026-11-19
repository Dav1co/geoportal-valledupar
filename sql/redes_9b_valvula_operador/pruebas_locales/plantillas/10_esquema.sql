-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · CORRECCIÓN «LA VÁLVULA QUE CERRÓ EL OPERADOR» · 10 — GUARDIA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: hallazgo del Code B (17-nov) y encargo de David del 18-nov.
-- · Presupone «Cierre por aguas arriba» publicado: huella del conjunto de funciones de redes {{MD5_BASE}}.
-- · SOLO AGREGA 1 RPC de lectura. No reemplaza ninguna función (ni la maniobra ni los cortes vigentes del geovisor), no crea tablas ni parámetros
--   y no cambia quién tiene el geovisor.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_cierres_registro(text,text)') is not null then raise exception 'La corrección «la válvula que cerró el operador» ya está aplicada: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_BASE}}' then
    raise exception 'Las funciones de redes no son las de «Cierre por aguas arriba» publicado (huella {{MD5_BASE}}): deténgase y avise';
  end if;
  if to_regclass('redes.valvula_maniobras') is null or to_regprocedure('redes.f_sim_autorizar(text)') is null or to_regprocedure('redes.f_puede_formulario(text,text)') is null
     or to_regprocedure('redes.f_cierre_regreso(bigint)') is null then
    raise exception 'Faltan tablas o funciones del 9b: deténgase y avise';
  end if;
end $$;
