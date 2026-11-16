-- =====================================================================
-- DOBLE LOCAL (Corte 4a), después de la migración. SOLO PARA PRUEBAS EN EL POSTGIS DE HOMEBREW.
--   · zt.super: supervisor de planta Y de distribución (ve los dos dashboards y el selector);
--   · zt.planta: solo supervisor de planta (en redes es operador);
--   · zt.dist: solo supervisor de distribución (Registro técnico + Dashboard distribución, §16).
-- =====================================================================
update public.geoportal_lista_blanca set ver_dashboard_redes = true where email = 'zt.super@emdupar.gov.co';
insert into public.geoportal_lista_blanca (email, rol, ver_registro_tecnico, ver_dashboard_tecnico) values ('zt.planta@emdupar.gov.co', 'consulta', true, true);
insert into public.geoportal_lista_blanca (email, rol, ver_registro_tecnico, ver_dashboard_redes) values ('zt.dist@emdupar.gov.co', 'consulta', true, true);
-- el doble de la lista blanca traía dias = 'lunes_viernes'; la función viva solo admite 'habiles' | 'todos'
update public.geoportal_lista_blanca set dias = 'habiles' where email like 'zt.%' and dias not in ('habiles', 'todos');
