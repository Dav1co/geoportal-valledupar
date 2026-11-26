-- =====================================================================
-- ANÁLISIS · «Cuadernos de análisis» · 40 — PERMISOS
-- RPC public.geoportal_analisis_*: EXECUTE SOLO para service_role (la Edge). Las internas del esquema analisis: nadie de la API.
-- Tablas: nada para public, anon, authenticated ni service_role (ya revocado en 10); el Dell (homelab_lectura) lee con SELECT explícito, tabla por tabla.
-- =====================================================================
do $p$
declare f record;
begin
  for f in select p.oid::regprocedure as firma, p.pronamespace = 'public'::regnamespace as es_rpc from pg_proc p
            where p.pronamespace = 'analisis'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_analisis\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    if f.es_rpc then execute format('grant execute on function %s to service_role', f.firma); end if;
  end loop;
end
$p$;

grant usage on schema analisis to homelab_lectura;
grant select on analisis.catalogo, analisis.parametros, analisis.cuadernos, analisis.cuaderno_versiones, analisis.cuaderno_eventos, analisis.marcas, analisis.marca_versiones,
                analisis.capturas, analisis.capturas_confirmadas, analisis.zona_consultas to homelab_lectura;

-- Cierre: las huellas de redes y de técnica siguen iguales, y ninguna función del paquete tiene DELETE/UPDATE sin WHERE (pg-safeupdate)
do $cierre$
declare v text;
begin
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if v is distinct from '1ba192724c2fddcf321104700829f3cc' then raise exception 'ANÁLISIS: la huella de redes cambió (%)', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'));
  if v is distinct from '838b80984e51cc7873a666f85d657195' then raise exception 'ANÁLISIS: la huella de técnica cambió (%)', v; end if;
  if exists (select 1 from analisis.f_funciones_sin_where()) then raise exception 'ANÁLISIS: hay funciones con DELETE/UPDATE sin WHERE'; end if;
end
$cierre$;
