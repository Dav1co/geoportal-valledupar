-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-1 · 06 — FOTO DE LAS COLUMNAS. Va SOLO en el ensayo, ANTES de la guardia y del esquema (la migración no la lleva).
-- Guarda, en una tabla temporal, las columnas de todas las tablas que ya existen en el esquema tecnica (nombre, tipo, nulo y valor por omisión).
-- La prueba 09.06 compara contra esta foto: ninguna tabla existente cambia de columnas, sin números fijos sacados de una base local.
-- =====================================================================
create function pg_temp.columnas_tecnica() returns table (tabla text, columna text, tipo text, no_nulo boolean, por_omision text) language sql stable as $$
  select c.relname::text, a.attname::text, format_type(a.atttypid, a.atttypmod), a.attnotnull, pg_get_expr(d.adbin, d.adrelid)
    from pg_class c join pg_attribute a on a.attrelid = c.oid left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
   where c.relnamespace = 'tecnica'::regnamespace and c.relkind in ('r', 'p') and a.attnum > 0 and not a.attisdropped $$;
create temp table _ptar_columnas_antes as select * from pg_temp.columnas_tecnica();
