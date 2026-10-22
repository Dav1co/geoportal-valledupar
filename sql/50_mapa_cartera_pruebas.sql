-- =====================================================================
-- sql/50 · pruebas del mapa de calor de cartera (SOLO LECTURA, solo agregados; rol propietario)
-- =====================================================================
-- 1) Privilegios:       psql "$PGURL_OWNER" -X -A -t -F '|' -f sql/50_mapa_cartera_pruebas.sql  (cada seccion es independiente; todas las filas ok = t)
-- 2) Regresion de las 64 ramas anteriores con las claves nuevas presentes: huella md5 por vista; correr ANTES y DESPUES de cambiar la RPC y comparar.
--    Usa :p como periodo (-v p=AAAAMM).
-- 3) Prueba de la rama 65: EXCEPT 0/0 de las celdas de la RPC contra la agregacion directa de la tabla, conciliacion exacta y supresion (23 comprobaciones).
-- =====================================================================

-- >>> PRIVILEGIOS (Z1 y Z3)
-- Controles de privilegios (solo lectura, sin datos): las tablas internas no se ven desde fuera y las funciones no se ejecutan desde fuera.
begin read only;
select 'Z1 tablas internas: sin select para anon, authenticated ni claude_ro, y RLS desactivada de forma explicita' as control,
  bool_and(not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('claude_ro', c.oid, 'select') and not c.relrowsecurity) and count(*) = 3 as ok
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'bi_interno' and c.relname in ('cartera_mapa_contrato', 'cartera_mapa_barrio', 'cartera_mapa_periodo')
union all
select 'Z3 la tabla interna no esta en la lista cerrada de vistas de la RPC (solo la vista agregada v_cartera_mapa)',
  pg_get_functiondef('public.geoportal_bi_consulta(text,jsonb)'::regprocedure) !~ 'cartera_mapa_contrato';
rollback;

-- >>> PRIVILEGIOS DE LAS FUNCIONES (Z2; despues de crear las funciones de lectura)
-- Control Z2 (al final del paso 4, cuando ya existen las tres funciones): sin EXECUTE para anon, authenticated, claude_ro ni PUBLIC.
begin read only;
select 'Z2 funciones nuevas: sin EXECUTE para anon, authenticated, claude_ro ni PUBLIC',
  bool_and(not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('claude_ro', p.oid, 'execute') and coalesce(p.proacl::text, '') !~ '(^\{|,)=X') and count(*) = 3
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'bi' and p.proname in ('recalcular_cartera_mapa', 'f_mapa_cartera', 'f_mapa_cartera_catalogo')
;
rollback;

-- >>> REGRESION DE LAS 64 RAMAS
-- Regresion de las 64 ramas: huella (md5) de cada vista con (a) solo el periodo y (b) el periodo MAS todas las claves nuevas del mapa en los filtros.
-- Se corre ANTES y DESPUES de la rama 65. Cada vista debe dar la misma huella en (a) y (b), y la misma antes y despues. Solo lectura.
begin read only;
set local statement_timeout = '600s';
select set_config('mc.p', :'p', true) as periodo \gset
do $$
declare v text; f1 jsonb; f2 jsonb; h1 text; h2 text; p text := current_setting('mc.p');
begin
  f1 := jsonb_build_object('periodo', p);
  f2 := f1 || jsonb_build_object('parte', 'mapa', 'medida', 'gt8', 'resolucion', '100', 'comunas', '1,2', 'barrios', '1,2', 'ciclos', '1,2', 'bandas', '4,5', 'tramos', '0,1');
  for v in select distinct m[1] from regexp_matches(pg_get_functiondef('public.geoportal_bi_consulta(text,jsonb)'::regprocedure), 'p_vista = ''([a-z0-9_]+)''', 'g') m order by 1 loop
    if v = 'v_cartera_mapa' then continue; end if;
    begin
      h1 := md5(public.geoportal_bi_consulta(v, f1)::text);
      h2 := md5(public.geoportal_bi_consulta(v, f2)::text);
    exception when others then h1 := 'ERROR ' || sqlstate; h2 := h1; end;
    raise notice 'REG|%|%|%', v, h1, h2;
  end loop;
end $$;
rollback;

-- >>> PRUEBA DE LA RAMA 65 (23 comprobaciones)
-- Prueba de la rama 65 (rol propietario, solo lectura, solo agregados). Cada fila: etiqueta|ok. Todas deben ser true.
--   psql "$PGURL_OWNER" -X -A -t -F '|' -v p=202609 -f sql/50_mapa_cartera_pruebas.sql  (la seccion de la prueba de la rama)
begin read only;
set local statement_timeout = '300s';
with r as (select jsonb_array_elements(public.geoportal_bi_consulta('v_cartera_mapa', jsonb_build_object('periodo', :'p', 'medida', 'deuda', 'resolucion', '250'))) x),
rc as (select (x ->> 'cx')::int cx, (x ->> 'cy')::int cy, (x ->> 'n')::int n, (x ->> 's')::numeric s from r where x ->> 'tipo' = 'celda'),
d as (select x250 cx, y250 cy, count(*)::int n, sum(saldo) s from bi_interno.cartera_mapa_contrato where periodo = :'p' and con_coord group by 1, 2 having count(*) >= 5),
cn as (select x from r where x ->> 'tipo' = 'concilia')
select label, ok from (values
  ('A1 RPC EXCEPT agregacion directa de la tabla = 0 filas', not exists (select * from rc except select * from d)),
  ('A2 agregacion directa EXCEPT RPC = 0 filas (o 1: celda oculta por supresion complementaria)', (select count(*) from (select * from d except select * from rc) z) <= 1),
  ('A3 conciliacion: total = dibujada + no dibujada (saldo y contratos, exacto)',
     (select (x ->> 'total_s')::numeric = (x ->> 'dibujada_s')::numeric + (x ->> 'no_dibujada_s')::numeric and (x ->> 'total_n')::int = (x ->> 'dibujada_n')::int + (x ->> 'no_dibujada_n')::int from cn)),
  ('A4 el total de la conciliacion = saldo total de la tabla del periodo',
     (select (x ->> 'total_s')::numeric from cn) = (select sum(saldo) from bi_interno.cartera_mapa_contrato where periodo = :'p'))
) v(label, ok);
-- Filtro de antigüedad por facturas vencidas (tramos): EXCEPT 0/0 de las celdas de la RPC contra la agregacion directa de la tabla con ese tramo
with r5 as (select jsonb_array_elements(public.geoportal_bi_consulta('v_cartera_mapa', jsonb_build_object('periodo', :'p', 'medida', 'deuda', 'resolucion', '250', 'tramos', '5'))) x),
rc5 as (select (x ->> 'cx')::int cx, (x ->> 'cy')::int cy, (x ->> 'n')::int n, (x ->> 's')::numeric s from r5 where x ->> 'tipo' = 'celda'),
d5 as (select x250 cx, y250 cy, count(*)::int n, sum(saldo) s from bi_interno.cartera_mapa_contrato where periodo = :'p' and con_coord and tramo = 5 group by 1, 2 having count(*) >= 5),
r6 as (select jsonb_array_elements(public.geoportal_bi_consulta('v_cartera_mapa', jsonb_build_object('periodo', :'p', 'medida', 'deuda', 'resolucion', '250', 'tramos', '0,1,2'))) x),
rc6 as (select (x ->> 'cx')::int cx, (x ->> 'cy')::int cy, (x ->> 'n')::int n, (x ->> 's')::numeric s from r6 where x ->> 'tipo' = 'celda'),
d6 as (select x250 cx, y250 cy, count(*)::int n, sum(saldo) s from bi_interno.cartera_mapa_contrato where periodo = :'p' and con_coord and tramo in (0, 1, 2) group by 1, 2 having count(*) >= 5),
rt as (select jsonb_array_elements(public.geoportal_bi_consulta('v_cartera_mapa', jsonb_build_object('periodo', :'p', 'medida', 'deuda', 'resolucion', '250', 'tramos', '0,1,2,3,4,5'))) x),
rs as (select jsonb_array_elements(public.geoportal_bi_consulta('v_cartera_mapa', jsonb_build_object('periodo', :'p', 'medida', 'deuda', 'resolucion', '250'))) x)
select label, ok from (values
  ('A5 tramo 5 (mas de 60): RPC EXCEPT agregacion directa = 0 filas', not exists (select * from rc5 except select * from d5)),
  ('A5b tramo 5: agregacion directa EXCEPT RPC = 0 filas (o 1: celda oculta por supresion complementaria)', (select count(*) from (select * from d5 except select * from rc5) z) <= 1),
  ('A6 tramos 0,1,2: RPC EXCEPT agregacion directa = 0 filas', not exists (select * from rc6 except select * from d6)),
  ('A6b tramos 0,1,2: agregacion directa EXCEPT RPC = 0 filas (o 1)', (select count(*) from (select * from d6 except select * from rc6) z) <= 1),
  ('A7 los seis tramos juntos = sin filtro (mismas celdas y misma conciliacion)',
     not exists (select x from rt where x ->> 'tipo' in ('celda', 'concilia') except select x from rs where x ->> 'tipo' in ('celda', 'concilia'))
     and not exists (select x from rs where x ->> 'tipo' in ('celda', 'concilia') except select x from rt where x ->> 'tipo' in ('celda', 'concilia')))
) v(label, ok);
with casos(id, medida, res, com, bar, cic, ban, tra) as (values
  (1, 'deuda',  'auto', null::smallint[], null::integer[], null::smallint[], null::smallint[], null::smallint[]),
  (2, 'gt8',    'auto', null, null, null, null, null),
  (3, 'gt60',   'auto', null, null, null, null, null),
  (4, 'part60', 'auto', null, null, null, null, null),
  (5, 'deuda',  'auto', array[1]::smallint[], null, null, null, null),
  (6, 'deuda',  'auto', array[3, 4]::smallint[], null, array[5, 6]::smallint[], null, null),
  (7, 'gt60',   '100',  array[2]::smallint[], null, null, array[4, 5]::smallint[], null),
  (8, 'gt8',    'auto', null, null, array[0]::smallint[], null, null),
  (9, 'deuda',  'auto', null, null, null, array[5]::smallint[], null),
  (10, 'deuda',  'auto', null, null, null, null, array[0]::smallint[]),
  (11, 'deuda',  'auto', null, null, null, null, array[1, 2]::smallint[]),
  (12, 'gt8',    'auto', null, null, null, null, array[3, 4]::smallint[]),
  (13, 'gt60',   'auto', null, null, null, null, array[5]::smallint[]),
  (14, 'part60', 'auto', array[3, 4]::smallint[], null, null, array[4, 5]::smallint[], array[2, 4, 5]::smallint[])),
r as (select c.*, bi.f_mapa_cartera(:'p', c.medida, c.res, c.com, c.bar, c.cic, c.ban, c.tra) j from casos c),
e as (select r.id, r.medida, x from r, lateral jsonb_array_elements(r.j) x)
select 'B' || id || ' ' || medida || ': conciliacion exacta, celdas con 5 o mas, grupos 0 o 5 o mas, anillos y residual sin 1 a 4' as label,
  coalesce(bool_and((x ->> 'total_s')::numeric = (x ->> 'dibujada_s')::numeric + (x ->> 'no_dibujada_s')::numeric and (x ->> 'total_n')::int = (x ->> 'dibujada_n')::int + (x ->> 'no_dibujada_n')::int and (x ->> 'no_dibujada_n')::int not between 1 and 4) filter (where x ->> 'tipo' = 'concilia'), true)
  and coalesce(bool_and((x ->> 'n')::int >= 5 and (coalesce((x ->> 'n8')::int, 0) = 0 or (x ->> 'n8')::int >= 5) and (coalesce((x ->> 'n60')::int, 0) = 0 or (x ->> 'n60')::int >= 5)
        and ((x ->> 'n')::int - coalesce((x ->> 'n8')::int, (x ->> 'n')::int)) not between 1 and 4) filter (where x ->> 'tipo' = 'celda'), true) as ok
from e group by id, medida order by id;
rollback;
