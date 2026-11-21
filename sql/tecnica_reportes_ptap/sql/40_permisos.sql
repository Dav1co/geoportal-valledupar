-- =====================================================================
-- 40 — PERMISOS: todo lo nuevo sin permisos para nadie; las 4 RPC solo para service_role (la Edge). Por NOMBRE EXACTO, nunca por patrón.
-- =====================================================================
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where (p.pronamespace = 'tecnica'::regnamespace and p.proname = any (array['f_rep_catalogo', 'f_rep_max_filas', 'f_rep_max_pagina', 'f_rep_ts', 'f_rep_col', 'f_rep_filtros', 'f_rep_cols_variables', 'f_rep_columnas', 'f_rep_valores', 'f_rep_envios_llaves', 'f_rep_envios_pagina', 'f_rep_envios', 'f_rep_quimicos', 'f_rep_kardex', 'f_rep_eventos_planta', 'f_rep_fuera_referencia', 'f_rep_filas', 'f_rep_leame']))
               or (p.pronamespace = 'public'::regnamespace and p.proname = any (array['geoportal_tec_reporte_iniciar', 'geoportal_tec_reporte_pagina', 'geoportal_tec_reporte_cerrar', 'geoportal_tec_reporte_remision_foto']))
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end $$;
grant execute on function public.geoportal_tec_reporte_iniciar(text, text, jsonb, text, boolean, text) to service_role;
grant execute on function public.geoportal_tec_reporte_pagina(text, bigint, text, integer) to service_role;
grant execute on function public.geoportal_tec_reporte_cerrar(text, bigint, integer, text, text) to service_role;
grant execute on function public.geoportal_tec_reporte_remision_foto(text, bigint, text) to service_role;
notify pgrst, 'reload schema';
