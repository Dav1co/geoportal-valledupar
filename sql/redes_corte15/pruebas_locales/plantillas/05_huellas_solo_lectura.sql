-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- ANTES: «funciones de redes» dice «CORRECCIÓN DEL 9b (lista para el 15)», tecnica.f_avisos «LA DEL CORTE 14», las {{N_NUEVAS}} nuevas «NO EXISTE» y las tablas «NO EXISTEN».
-- DESPUÉS: «CORTE 15 (aplicado)», f_avisos «CORTE 15 (reemplazada)», {{N_NUEVAS}} «NUEVA» y las tablas «EXISTEN». Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise.
-- redes.f_publicar_l116 dice «LA PUBLICADA (Corte 5d)» antes y «CORTE 15 (reemplazada)» después.
-- Las huellas de tecnica.f_avisos y de redes.f_publicar_l116 salen de la base local de Code A (no se han comprobado contra la base viva): por eso van aquí, antes de todo.
-- =====================================================================
with nue(firma, nueva) as (values {{NUEVAS}}),
pub(firma, publicada) as (values {{PUBLICADAS}}),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{{MD5_BASE}}' then 'CORRECCIÓN DEL 9b (lista para el 15)' when '{{MD5_15}}' then 'CORTE 15 (aplicado)' else 'DISTINTA' end as estado
union all select '1 tecnica.f_avisos(boolean,boolean,timestamptz)', md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamptz)'::regprocedure)),
       case md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamptz)'::regprocedure)) when '{{MD5_AVISOS}}' then 'LA DEL CORTE 14' when '{{MD5_AVISOS_15}}' then 'CORTE 15 (reemplazada)' else 'DISTINTA' end
union all select '1b redes.f_publicar_l116(bigint,text,text)', md5(pg_get_functiondef('redes.f_publicar_l116(bigint,text,text)'::regprocedure)),
       case md5(pg_get_functiondef('redes.f_publicar_l116(bigint,text,text)'::regprocedure)) when '{{MD5_PUBLICAR}}' then 'LA PUBLICADA (Corte 5d)' when '{{MD5_PUBLICAR_15}}' then 'CORTE 15 (reemplazada)' else 'DISTINTA' end
union all select '2 ' || p.firma || ' (no se toca)', md5(pg_get_functiondef(to_regprocedure(p.firma))),
       case when to_regprocedure(p.firma) is null then 'FALTA' when md5(pg_get_functiondef(to_regprocedure(p.firma))) = p.publicada then 'LA PUBLICADA' else 'DISTINTA' end from pub p
union all select '3 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
       case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end from nue n
union all select '4 tablas del corte (7)', null,
       case (select count(*) from pg_class c where c.relnamespace = 'redes'::regnamespace and c.relkind = 'r' and c.relname in ('eventos_suspension', 'evento_suspension_eventos',
               'evento_suspension_reportes', 'evento_tipos_asociables', 'evento_tipo_eventos', 'planta_sectores', 'planta_sector_eventos')) when 0 then 'NO EXISTEN (sin aplicar)' when 7 then 'EXISTEN' else 'FALTA' end
union all select '5 tablas que usa (bot, línea 116, daños, sensibles, plantas, catálogo y reportes de campo)', null,
       case when to_regclass('redes.reporte_externo_eventos') is not null and to_regclass('redes.l116_eventos') is not null and to_regclass('redes.l116_vigente') is not null
             and to_regclass('redes.danos') is not null and to_regclass('redes.usuarios_sensibles') is not null and to_regclass('tecnica.plantas') is not null
             and to_regclass('campo.tipos_reporte') is not null and to_regclass('campo.reportes') is not null and to_regclass('campo.reporte_eventos') is not null
             and to_regclass('campo.v_reportes_estado') is not null and exists (select 1 from campo.estados_reporte where codigo = 'atendido' and activo and cambio_manual and not exige_motivo)
             and exists (select 1 from campo.grupos_reporte where codigo = 'red_acueducto') then 'ESTÁN' else 'FALTA' end
union all select '6 INFO sectores y subsectores vigentes · plantas activas · sensibles confirmados · contratos con tramo', null,
       (select count(*) from redes.activo_vigente_mat where prefijo = 'SEC' and not retirado and not oculto) || ' · ' || (select count(*) from tecnica.plantas where activa)
       || ' · ' || (select count(*) from redes.v_usuario_sensible where estado = 'confirmado') || ' · ' || (select count(*) from redes.contrato_tramo)
union all select '7 INFO tipo «sin_agua» en el catálogo de campo · tipos parecidos', null,
       coalesce((select string_agg(t.codigo || '=' || t.nombre || case when t.activo then '' else ' (inactivo)' end, ' | ' order by t.codigo) from campo.tipos_reporte t
                  where t.codigo = 'sin_agua' or lower(t.nombre) like '%sin agua%' or lower(t.nombre) like '%no tengo agua%' or lower(t.nombre) like '%presi_n%'), 'ninguno')
union all select '8 INFO causales de acueducto de la línea 116 (para revisar la lista de lo que se asocia)', null,
       coalesce((select string_agg(x.causal || ' (' || x.n || ')', ' | ' order by x.n desc) from (select v.causal, count(*) n from redes.l116_vigente v where lower(v.servicio) = 'acueducto' group by 1) x), 'sin reportes')
union all select '9 INFO disparadores que ya tiene campo.reportes (el corte agrega t_evento_asociar)', null,
       coalesce((select string_agg(t.tgname, ', ' order by t.tgname) from pg_trigger t where t.tgrelid = to_regclass('campo.reportes') and not t.tgisinternal), 'ninguno')
order by 1;
