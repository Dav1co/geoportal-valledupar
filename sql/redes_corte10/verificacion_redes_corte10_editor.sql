-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Generada por pruebas_locales/generar.py. Todas las filas deben decir OK (las INFO son informativas).
-- Nota: después del 10, la fila 03 de la verificación del 5d deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 la RPC nueva y las dos reemplazadas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('geoportal_redes_valoracion', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor')
                     and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 3 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluidas las 3 nuevas)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las 4 reemplazadas, de las 4 nuevas y del conjunto de funciones de redes del 10',
         case when (select count(*) from (values ('redes.f_ficha(bigint,text)', 'cf4791cf96d0b9852fcfa78bb4b25622'), ('redes.f_param_entero(text)', 'b6218d0d4d4e8b343116b99fc35bc0ea'), ('public.geoportal_redes_geovisor_mvt(text,integer,integer,integer)', '017d8993f9e9677c881f5d7a4763a06a'), ('public.geoportal_redes_geovisor(text)', 'f9d408248906b538278a474ca2ab92af')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 4
               and (select count(*) from (values ('redes.f_val_hoja_alc()', '12f0e8528d072329237d2487b7e0225a'), ('redes.f_val_prefijos()', '96809e8a00089c8142dfc1c1a6b7e7a2'), ('redes.f_ficha_regulatorio(bigint,text)', '4260a4611f540b87566ee145729e0737'), ('public.geoportal_redes_valoracion(text)', 'ec88cca4eea304ad4310015c2a386b4a')) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 4
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = 'aad5952c27e13cc3ad45623279ba7085' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función de redes, tecnica, public.geoportal_redes_* ni geoportal_tec_* con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 las 3 tablas de la valoración: nadie de la API las lee ni las escribe; son de solo agregar (con su disparador)',
         case when (select count(*) from pg_class c where c.oid in (to_regclass('redes.val_hojas'), to_regclass('redes.val_filas'), to_regclass('redes.val_amarre')) and c.relrowsecurity
                     and not exists (select 1 from aclexplode(c.relacl) x where x.grantee in (0, (select oid from pg_roles where rolname = 'anon'), (select oid from pg_roles where rolname = 'authenticated'),
                                                                                              (select oid from pg_roles where rolname = 'service_role')))) = 3
               and (select count(*) from pg_trigger t where t.tgrelid in ('redes.val_hojas'::regclass, 'redes.val_filas'::regclass, 'redes.val_amarre'::regclass)
                     and t.tgfoid = 'tecnica.f_solo_agregar'::regproc) = 6 then 'OK' else 'MAL' end
  union all select 6, '06 ninguna tabla de la valoración tiene columnas de personas (suscriptor, contrato, teléfono, dirección)',
         case when not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name like 'val\_%'
                                and column_name ~ 'suscriptor|contrato|telefono|celular|direccion|cedula|propietario') then 'OK' else 'MAL' end
  union all select 7, '07 los parámetros: la hoja de alcantarillado vigente (1 o 2) y la tolerancia de la conciliación',
         case when (select count(*) from redes.parametros where clave in ('valoracion_hoja_alcantarillado', 'valoracion_tolerancia_pct') and estado = 'vigente' and valor is not null) = 2
               and (select valor from redes.parametros where clave = 'valoracion_hoja_alcantarillado') in (1, 2) then 'OK' else 'MAL' end
  union all select 8, 'INFO valoración vigente: archivo · filas · hoja de alcantarillado que vale · amarre vigente (filas)',
         coalesce((select c.archivo || ' · ' || c.filas from redes.v_ref_carga_vigente c where c.conjunto = 'valoracion'), 'sin cargar todavía (paquete carga_val)')
         || ' · ' || redes.f_val_hoja_alc() || ' · ' || coalesce((select c.filas::text from redes.v_ref_carga_vigente c where c.conjunto = 'val_amarre'), 'sin amarre')
  union all select 9, 'INFO activos amarrados con fila (hojas vigentes) · sin fila · proyectados',
         coalesce((select count(distinct am.activo_id) filter (where am.n is not null) || ' · ' || count(distinct am.activo_id) filter (where am.situacion = 'sin_fila') || ' · '
                          || count(distinct am.activo_id) filter (where am.situacion = 'proyectado')
                     from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja in ('acueducto', redes.f_val_hoja_alc())), '0 · 0 · 0')
) t order by o;
