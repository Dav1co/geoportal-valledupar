-- =====================================================================
-- Reglas de PRODUCCIÓN de tablas de public que el doble local de Code A no traía (las mismas que puso el Code B en
-- sql/redes_corte10/pruebas_locales/reglas_produccion.sql, leídas de la base viva). Las de tecnica ya vienen de
-- sql/tecnica_corte12/pruebas_locales/reglas_tecnica_produccion.sql. Solo para la base local: NO va a producción.
-- Las tablas nuevas del 9b salen de su propia migración.
-- =====================================================================
alter table public.geoportal_lista_blanca add constraint geoportal_lista_blanca_rol_check check (rol in ('admin', 'consulta')) not valid;
alter table public.geoportal_auditoria add constraint geoportal_auditoria_email_nn check (email is not null) not valid;
alter table public.geoportal_auditoria add constraint geoportal_auditoria_accion_nn check (accion is not null) not valid;
