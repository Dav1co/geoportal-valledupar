-- DOBLE LOCAL (solo pruebas del Code C; NO va en la migración). Producción tiene tecnica.plantas con 5 columnas (la quinta, creado_en, del Corte 1:
-- corte1_paso_a, «create table tecnica.plantas (… creado_en timestamptz not null default clock_timestamp())»). La base local, rehecha con la cadena del B, traía 4.
-- Lo encontró el ensayo de PTAR-1 en producción (21-nov): plantas 5, puntos 15, registros 16, referencias 11 = 47 columnas.
alter table tecnica.plantas add column if not exists creado_en timestamptz not null default clock_timestamp();
