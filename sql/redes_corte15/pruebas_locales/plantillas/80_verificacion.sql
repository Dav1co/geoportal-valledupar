-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 80 — VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web).
-- Todas las filas deben decir OK. Nota: después de este paquete, la fila de la huella del conjunto de la verificación anterior deja de valer.
-- =====================================================================
select k, v from (
  select 1 as o, '01 las {{N_RPC}} RPC nuevas: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and (p.proname like 'geoportal\_redes\_evento%' or p.proname = 'geoportal_redes_planta_sectores_fijar') and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = {{N_RPC}} then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluida la del bot: su permiso va en otro paquete)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las {{N_NUEVAS}} nuevas, de tecnica.f_avisos, de redes.f_publicar_l116 y del conjunto de funciones de redes',
         case when (select count(*) from (values {{NUEVAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_NUEVAS}}
               and md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamptz)'::regprocedure)) = '{{MD5_AVISOS_15}}'
               and md5(pg_get_functiondef('redes.f_publicar_l116(bigint,text,text)'::regprocedure)) = '{{MD5_PUBLICAR_15}}'
               and (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
                     where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) = '{{MD5_15}}' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
  union all select 5, '05 las 7 tablas: con RLS y sin permisos para la API; las 5 de hechos, de solo agregar',
         case when (select count(*) from pg_class c where c.relnamespace = 'redes'::regnamespace and c.relkind = 'r' and c.relrowsecurity
                     and c.relname in ('eventos_suspension', 'evento_suspension_eventos', 'evento_suspension_reportes', 'evento_tipos_asociables', 'evento_tipo_eventos', 'planta_sectores', 'planta_sector_eventos')
                     and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('service_role', c.oid, 'select')) = 7
               and (select count(*) from pg_trigger t where not t.tgisinternal and t.tgname = 't_solo_agregar'
                     and t.tgrelid in ('redes.eventos_suspension'::regclass, 'redes.evento_suspension_eventos'::regclass, 'redes.evento_suspension_reportes'::regclass,
                                       'redes.evento_tipo_eventos'::regclass, 'redes.planta_sector_eventos'::regclass)) = 5 then 'OK' else 'MAL' end
  union all select 6, '06 los 4 disparadores de la asociación automática (bot, línea 116, daños y formato de campo), activos',
         case when (select count(*) from pg_trigger t where not t.tgisinternal and t.tgname = 't_evento_asociar' and t.tgenabled = 'O'
                     and t.tgrelid in ('redes.reporte_externo_eventos'::regclass, 'redes.l116_eventos'::regclass, 'redes.danos'::regclass, 'campo.reportes'::regclass)) = 4 then 'OK' else 'MAL' end
  union all select 7, '07 lo publicado que no se reemplaza sigue igual (recibir del bot, crear daño, cortes vigentes, sector de un punto)',
         case when (select count(*) from (values {{PUBLICADAS}}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = {{N_PUBLICADAS}} then 'OK' else 'MAL' end
  union all select 8, '08 el tipo «sin_agua» está activo en el catálogo de campo y en la lista de lo que se asocia; el consecutivo EVS y los parámetros, puestos',
         case when exists (select 1 from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id where t.codigo = 'sin_agua' and t.activo and g.codigo = 'red_acueducto')
               and (select count(*) from redes.evento_tipos_asociables where origen in ('bot', 'campo') and codigo = 'sin_agua' and clase = 'sin_agua' and asocia) = 2
               and exists (select 1 from redes.consecutivos where prefijo = 'EVS')
               and (select count(*) from redes.parametros where clave in ({{PARAMETROS}}) and estado = 'vigente') = 5
               and exists (select 1 from tecnica.aviso_parametros where clave = 'sin_agua_ventana_h') then 'OK' else 'MAL' end
  union all select 9, 'INFO eventos (abiertos · cerrados · anulados) · reportes asociados hoy',
         (select count(*) filter (where estado = 'abierto') || ' · ' || count(*) filter (where estado = 'cerrado') || ' · ' || count(*) filter (where estado = 'anulado') from redes.v_evento_suspension)
         || ' · ' || (select count(*) from redes.f_eventos_abiertos() e cross join lateral redes.f_evento_reportes(e.id) r)
  union all select 10, 'INFO lo que se asocia (bot · línea 116 · daños · formato de campo) · plantas con sectores asignados',
         (select count(*) filter (where origen = 'bot' and asocia) || ' · ' || count(*) filter (where origen = 'l116' and asocia) || ' · ' || count(*) filter (where origen = 'dano' and asocia) || ' · ' || count(*) filter (where origen = 'campo' and asocia) from redes.evento_tipos_asociables)
         || ' · ' || (select count(distinct planta_id) from redes.planta_sectores where activo)
) t order by o;
