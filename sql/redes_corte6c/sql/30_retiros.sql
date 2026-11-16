-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 30 — RETIRO DE LA COPIA DERIVADA (va DESPUÉS de los reemplazos: ya ninguna función la nombra)
-- redes.contratos_capa era una copia de 111 mil filas que se rehacía entera dentro de la petición del geovisor (44,7 s en producción, contra el
-- tope de 30 s). No guardaba hechos: todo lo que tenía se lee ahora, al vuelo, de las tablas de Comercial. La reversa la vuelve a crear (vacía).
-- El parámetro geovisor_contratos_horas no se borra: queda con su nota de «sin uso».
-- =====================================================================
drop function redes.f_contratos_capa_al_dia();
drop function redes.f_refrescar_contratos_capa();
drop table redes.contratos_capa;
drop table redes.contratos_capa_estado;
update redes.parametros set descripcion = 'Sin uso desde el Corte 6c: la capa de contratos se arma al vuelo en cada tesela y ya no se rehace'
 where clave = 'geovisor_contratos_horas';
update redes.geovisor_capas set nota = 'Desde el zoom 16, siempre al día. Al tocar un contrato: su consumo, nombre y dirección (la consulta queda registrada)'
 where codigo = 'contratos';
