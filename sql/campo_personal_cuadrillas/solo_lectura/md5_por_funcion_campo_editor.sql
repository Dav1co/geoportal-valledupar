-- COMERCIAL 21-NOV · SOLO LECTURA · md5 de cada función de campo (esquema campo y public.geoportal_campo_*), para compararla con la base local del Code A.
-- La huella de conjunto local (bda09093…) no es la de producción (cf40d2a2…), aunque las dos tienen 68 funciones: esta lista dice cuál difiere. No cambia nada.
select p.oid::regprocedure::text as funcion, md5(pg_get_functiondef(p.oid)) as md5
  from pg_proc p
 where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')
 order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text;
