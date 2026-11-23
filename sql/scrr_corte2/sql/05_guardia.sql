-- =====================================================================
-- SCRR · CORTE 2 · 05 — GUARDIA (no aplica nada si la base no es la esperada)
-- Se niega si:
--   · el esquema scrr ya existe (el paquete no se reaplica: para rehacerlo, primero la reversa);
--   · la huella de campo no es la publicada el 22-nov 13:46 ({{HUELLA_CAMPO}}): el modo «Cartera» autoriza con campo.f_autorizar_supervision;
--   · campo.f_autorizar_supervision(text) no tiene su md5 publicada ({{MD5_AUTORIZAR_SUPERVISION}});
--   · public.cartera_suscripcion no es una tabla (relkind 'r') con exactamente sus 23 columnas de producción (id … cargado_en: nombre, tipo, NOT NULL y default) y su id llave primaria con
--     default nextval('cartera_suscripcion_id_seq') (el cargador la actualiza: decisión 4 del 20-nov y P4 del 22-nov);
--   · faltan public.geoportal_auditoria o public.predios_comercial (vista materializada con índice único), PostgreSQL 17, hechos.facturacion_sspd o
--     redes.f_eventos_del_contrato(text); o ya existe el rol scrr_refresco.
-- No toca las 4 funciones de permisos (geoportal_admin_permisos, geoportal_mis_permisos, geoportal_puede, geoportal_admin_guardar): la verificación comprueba
-- que siguen con su md5.
-- =====================================================================
do $guardia$
declare v text;
begin
  if exists (select 1 from pg_namespace where nspname = 'scrr') then
    raise exception 'GUARDIA SCRR: el esquema scrr ya existe. Este paquete no se reaplica; si hay que rehacerlo, primero la reversa.';
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v
    from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if v is distinct from '{{HUELLA_CAMPO}}' then
    raise exception 'GUARDIA SCRR: la huella de campo es % y se esperaba {{HUELLA_CAMPO}} (publicada el 22-nov 13:46). Deténgase y avise.', v;
  end if;
  if to_regprocedure('campo.f_autorizar_supervision(text)') is null
     or md5(pg_get_functiondef(to_regprocedure('campo.f_autorizar_supervision(text)'))) <> '{{MD5_AUTORIZAR_SUPERVISION}}' then
    raise exception 'GUARDIA SCRR: campo.f_autorizar_supervision(text) no está o cambió. Deténgase y avise.';
  end if;
  if (select relkind from pg_class where oid = to_regclass('public.cartera_suscripcion')) is distinct from 'r' then
    raise exception 'GUARDIA SCRR: public.cartera_suscripcion no existe o no es una tabla.';
  end if;
  -- nombre, tipo, NOT NULL y default de cada columna, en orden (David, 22-nov: el ensayo falló por un NOT NULL que el doble no tenía)
  select string_agg(column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, ''), ',' order by ordinal_position) into v
    from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion';
  if v is distinct from '{{COLUMNAS_SUSCRIPCION}}' then
    raise exception 'GUARDIA SCRR: las columnas de public.cartera_suscripcion (nombre:tipo:nulable:default) no son las esperadas: %', v;
  end if;
  -- id con su secuencia y llave primaria (el respaldo y la reversión de una carga de cartera restauran el id y el cargado_en originales)
  if to_regclass('public.cartera_suscripcion_id_seq') is null
     or (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
          where d.adrelid = 'public.cartera_suscripcion'::regclass and a.attname = 'id') is distinct from 'nextval(''cartera_suscripcion_id_seq''::regclass)'
     or not exists (select 1 from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
                     where i.indrelid = 'public.cartera_suscripcion'::regclass and i.indisprimary and a.attname = 'id' and i.indnatts = 1) then
    raise exception 'GUARDIA SCRR: public.cartera_suscripcion.id no es la llave primaria con default nextval(cartera_suscripcion_id_seq).';
  end if;
  if to_regclass('public.geoportal_auditoria') is null or to_regclass('public.predios_comercial') is null then
    raise exception 'GUARDIA SCRR: falta public.geoportal_auditoria o public.predios_comercial.';
  end if;
  -- Refresco del mapa comercial por el cargador (David, 22-nov): REFRESH … CONCURRENTLY exige el índice único de la vista; el rol mínimo usa MAINTAIN (PostgreSQL 17)
  if (select relkind from pg_class where oid = 'public.predios_comercial'::regclass) <> 'm'
     or not exists (select 1 from pg_index i where i.indrelid = 'public.predios_comercial'::regclass and i.indisunique and i.indpred is null) then
    raise exception 'GUARDIA SCRR: public.predios_comercial no es una vista materializada con índice único (no se podría refrescar sin bloquear el mapa).';
  end if;
  if current_setting('server_version_num')::int < 170000 then raise exception 'GUARDIA SCRR: hace falta PostgreSQL 17 (privilegio MAINTAIN).'; end if;
  if exists (select 1 from pg_roles where rolname = 'scrr_refresco') then raise exception 'GUARDIA SCRR: el rol scrr_refresco ya existe.'; end if;
  -- Selección: «facturado» = figura en hechos.facturacion_sspd (último período cargado); evento de suspensión de agua por redes.f_eventos_del_contrato
  if to_regclass('hechos.facturacion_sspd') is null
     or (select count(*) from information_schema.columns where table_schema = 'hechos' and table_name = 'facturacion_sspd' and column_name in ('periodo', 'contrato')) <> 2 then
    raise exception 'GUARDIA SCRR: falta hechos.facturacion_sspd con sus columnas periodo y contrato.';
  end if;
  if to_regprocedure('redes.f_eventos_del_contrato(text)') is null or to_regprocedure('redes.f_eventos_abiertos()') is null then
    raise exception 'GUARDIA SCRR: falta redes.f_eventos_del_contrato(text) o redes.f_eventos_abiertos() (aviso de evento por contrato, Corte 15).';
  end if;
end $guardia$;
