-- =====================================================================
-- DOBLE LOCAL (además de los del 1a y del Corte 2) para el Corte 3a. SOLO PARA PRUEBAS EN EL POSTGIS DE HOMEBREW.
--   · zt.oper tiene asignado también «mantenimiento» (Registrar intervención); zt.oper.sinform sigue sin formularios.
--   · zt.super: supervisor técnico (ver_dashboard_tecnico), para las pruebas en Chrome.
-- =====================================================================
insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario) values ('zt.oper@emdupar.gov.co', 'asignar_formulario', 'mantenimiento');
insert into public.geoportal_lista_blanca (email, rol, ver_registro_tecnico, ver_dashboard_tecnico)
select 'zt.super@emdupar.gov.co', 'consulta', true, true where not exists (select 1 from public.geoportal_lista_blanca where email = 'zt.super@emdupar.gov.co');
