-- TÉCNICA · PTAR · REVERSA DE LA CARGA INICIAL: desactiva con motivo todo lo cargado de la PTAR (nada se borra, D9). Solo si hace falta repetir la carga.
begin;
update tecnica.elementos_planta set activo = false, motivo_inactivo = 'Reversa de la carga inicial del mapa de la PTAR (GeoJSON md5 6cfd0a245b3fc12752a2663db432dfba)'
 where activo and creado_por = 'carga.ptar@emdupar.gov.co' and instalacion_id = (select id from tecnica.instalaciones where codigo = 'ptar');
commit;
