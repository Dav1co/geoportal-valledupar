-- [Code B] INVESTIGACIÓN Y ANÁLISIS (23-nov) · VERIFICACIÓN (solo lectura; después de la migración: 10 de 10 OK) (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
select o, k, estado from (
  select 1 as o, '1 preparar_subida es la de este cambio' as k, case when md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_preparar_subida(text,integer,text,text,text)'))) = 'a00d66705d7a0c88a38ab5d882153669' then 'OK' else 'FALLA' end as estado
  union all
  select 2 as o, '2 la huella de campo es la de este cambio' as k, case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%')) = 'd4c76af821deee9ecbee4ac451d943ff' then 'OK' else 'FALLA' end as estado
  union all
  select 3 as o, '3 la huella del acta no cambió (111506c6…)' as k, case when (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%')) = '111506c690249ad3b56ebf572566434c' then 'OK' else 'FALLA' end as estado
  union all
  select 4 as o, '4 Investigación: id 35, activa, sin resultado, fotos de 0 a 6, contrato si' as k, case when exists (select 1 from campo.tipos_reporte where codigo = 'investigacion_ubicacion' and id = 35 and activo and not genera_resultado and fotos_min = 0 and fotos_max = 6 and requiere_contrato = 'si') then 'OK' else 'FALLA' end as estado
  union all
  select 5 as o, '5 Investigación: campos como decidió David (4 nuevos, 4 desactivados, dirección obligatoria)' as k, case when (select string_agg(c.codigo || ':' || c.tipo_dato || ':' || c.obligatorio::text || ':' || c.activo::text, ',' order by c.codigo) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id where t.codigo = 'investigacion_ubicacion') = 'barrio:texto:false:true,cita_acordada:dia_hora:false:false,despeje_caja:si_no:false:false,despeje_observacion:texto:false:false,direccion_encontrada:texto:true:true,habitado:si_no:false:true,hallazgo:opcion:false:true,medidor:texto:false:true,observacion:texto:false:true,tipo_predio:opcion:false:true,visita_concertada:si_no:false:false' then 'OK' else 'FALLA' end as estado
  union all
  select 6 as o, '6 Investigación: las 3 fotos opcionales y sin soporte' as k, case when (select string_agg(f.codigo || ':' || f.obligatoria::text || ':' || f.soporte_inefectiva::text || ':' || f.activo::text, ',' order by f.codigo) from campo.tipo_fotos f join campo.tipos_reporte t on t.id = f.tipo_id where t.codigo = 'investigacion_ubicacion') = 'fachada_nomenclatura:false:false:true,predio_lote:false:false:true,vecino_referencia:false:false:true' then 'OK' else 'FALLA' end as estado
  union all
  select 7 as o, '7 preparar_subida sigue solo para service_role' as k, case when has_function_privilege('service_role', 'public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'execute') and not has_function_privilege('anon', 'public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'execute') and not has_function_privilege('authenticated', 'public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'execute') then 'OK' else 'FALLA' end as estado
  union all
  select 8 as o, '8 las 4 funciones de permisos vivas no cambiaron' as k, case when md5(pg_get_functiondef(to_regprocedure('public.geoportal_puede(text,text)'))) = '32f174a55b95788d3f8187b507303c2f' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_mis_permisos(text)'))) = '83166fe17be58da67bbdedaae429bedb' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)'))) = '01fda69a9d912067b8b4dc153ac7957e' and md5(pg_get_functiondef(to_regprocedure('public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'))) = 'e5a90103b4a83440fd826f03266b7245' then 'OK' else 'FALLA' end as estado
  union all
  select 9 as o, '9 ninguna función de campo con DELETE o UPDATE sin WHERE' as k, case when (with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')) = 0 then 'OK' else 'FALLA' end as estado
  union all
  select 10 as o, '10 redes.f_funciones_sin_where() devuelve cero filas' as k, case when (select count(*) from redes.f_funciones_sin_where()) = 0 then 'OK' else 'FALLA' end as estado
) t order by o;
