-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 26 — FUNCIONES NUEVAS (internas; nadie de la API las ejecuta)
--   · redes.f_contrato_uso: el uso del contrato (el de la ficha y, si no hay, la categoría de la cartera sin su número). Es la misma regla del 6b,
--     ahora en un solo lugar para la tesela y la tarjeta.
--   · redes.f_funciones_sin_where: comprobación estática para pg-safeupdate. En Supabase, las sesiones de la API (rol authenticator) rechazan todo
--     DELETE o UPDATE sin WHERE, también dentro de funciones SECURITY DEFINER; el editor SQL no lo hace, así que un ensayo en el editor no lo ve.
--     Devuelve las sentencias de las funciones de redes, tecnica y public.geoportal_redes_* que no pasarían. Debe devolver cero filas.
-- =====================================================================
create function redes.f_contrato_uso(p_uso_ficha text, p_categoria text) returns text language sql immutable set search_path = pg_catalog as $$
  select coalesce(nullif(btrim(p_uso_ficha), '(sin dato)'), nullif(regexp_replace(btrim(coalesce(p_categoria, '')), '^-?[0-9]+\s+', ''), '')) $$;

-- Cómo mira: quita los comentarios de línea, parte el cuerpo por «;» y marca cada trozo con «delete from …» o «update <tabla> set …» sin un «where»
-- después. No cuentan «on conflict … do update», «for update» ni los disparadores «before update or delete». Límite conocido: un UPDATE cuyo único
-- «where» está dentro de una subconsulta pasa sin marcarse.
create function redes.f_funciones_sin_where() returns table (funcion text, sentencia text)
language sql stable set search_path = pg_catalog as $$
  with f as (
    select p.oid::regprocedure::text as funcion,
           regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace in (select n.oid from pg_namespace n where n.nspname in ('redes', 'tecnica'))
            or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select s.funcion, left(s.st, 200) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')
   order by 1, 2 $$;
