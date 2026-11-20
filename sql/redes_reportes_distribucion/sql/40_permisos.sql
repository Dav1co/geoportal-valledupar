-- =====================================================================
-- 40 — PERMISOS: todo lo nuevo sin permisos para nadie; las 3 RPC solo para service_role (la Edge). Por NOMBRE EXACTO, nunca por patrón:
--      «geoportal_redes_reporte_%» también abarca las publicadas reporte_convertir y reporte_descartar, que no se tocan.
-- =====================================================================
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where (p.pronamespace = 'redes'::regnamespace and p.proname = any (array['f_rep_catalogo', 'f_rep_max_filas', 'f_rep_ts', 'f_rep_col', 'f_rep_rotulo', 'f_rep_sector_geom', 'f_rep_punto', 'f_rep_filtros', 'f_rep_columnas', 'f_rep_levantamientos', 'f_rep_valvulas', 'f_rep_eventos', 'f_rep_l116', 'f_rep_bot', 'f_rep_sensibles', 'f_rep_activos', 'f_rep_filas', 'f_rep_contar', 'f_rep_leame']))
               or (p.pronamespace = 'public'::regnamespace and p.proname = any (array['geoportal_redes_reporte_iniciar', 'geoportal_redes_reporte_pagina', 'geoportal_redes_reporte_cerrar']))
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end $$;
grant execute on function public.geoportal_redes_reporte_iniciar(text, text, jsonb, text, boolean, text) to service_role;
grant execute on function public.geoportal_redes_reporte_pagina(text, bigint, text, integer) to service_role;
grant execute on function public.geoportal_redes_reporte_cerrar(text, bigint, integer, text, text) to service_role;
notify pgrst, 'reload schema';
