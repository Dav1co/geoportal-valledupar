-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 90 — REVERSA.
-- Siempre quita las 12 RPC public.geoportal_analisis_* (la Edge deja de responder; nadie más entra a las tablas).
-- · Si todavía NO hay cuadernos ni conteos: quita también las tablas, las funciones y el esquema (queda como antes de la migración; se puede volver a migrar).
-- · Si YA hay datos: NADA se borra. Quedan las tablas con sus filas, sus disparadores de solo agregar y las funciones internas (que nadie de la API puede ejecutar).
-- No toca redes ni técnica; el bucket analisis-capturas tampoco (lo administra David).
-- =====================================================================
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'analisis') then raise exception 'REVERSA ANÁLISIS: el paquete no está aplicado'; end if;
end $$;
{{DROPS_RPC}}
do $$
begin
  if exists (select 1 from analisis.cuadernos) or exists (select 1 from analisis.zona_consultas) then
    raise notice 'REVERSA ANÁLISIS: hay datos; se quitaron solo las 12 RPC. Las tablas, sus filas y las funciones internas se conservan.';
    return;
  end if;
  drop function analisis.f_cuaderno(text,uuid,boolean);                 -- devuelve una fila de analisis.cuadernos: va antes que la tabla
  drop table analisis.zona_consultas, analisis.capturas_anuladas, analisis.capturas_confirmadas, analisis.capturas, analisis.marca_versiones, analisis.marcas, analisis.cuaderno_eventos,
             analisis.cuaderno_versiones, analisis.cuadernos, analisis.parametros, analisis.catalogo;
{{DROPS_INTERNAS}}
  drop schema analisis;
  raise notice 'REVERSA ANÁLISIS: sin datos; se quitaron las RPC, las tablas, las funciones y el esquema.';
end $$;
do $$
declare v text;
begin
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname like 'geoportal\_analisis\_%') then raise exception 'REVERSA ANÁLISIS: quedó alguna RPC'; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if v is distinct from '{{MD5_REDES}}' then raise exception 'REVERSA ANÁLISIS: la huella de redes cambió (%)', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'));
  if v is distinct from '{{MD5_TECNICA}}' then raise exception 'REVERSA ANÁLISIS: la huella de técnica cambió (%)', v; end if;
end $$;
