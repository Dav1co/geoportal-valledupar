-- =====================================================================
-- COMERCIAL 21-NOV · (b) ACTAS: FIRMAS, PDF, ACTAS REGISTRADAS Y DERIVADAS · 05 — GUARDIA
-- Va DESPUÉS del paquete (a) Personal y cuadrillas. Huellas: redes y técnica del 21-nov; campo tras (a); acta (111506c6…) y salida (4edfed33…) del 21-nov 17:55.
-- =====================================================================
do $$
declare v text;
begin
  if to_regprocedure('public.geoportal_campo_documentos_catalogo(text,text)') is not null then
    raise exception 'Las actas con firmas y PDF ya parecen aplicadas (existe geoportal_campo_documentos_catalogo): use la reversa antes de repetir';
  end if;
  -- tras una reversa con datos se conservan las tablas y campo.f_firmas_definitivas y campo.f_registro_existe (protegen las firmas): no cuentan en la huella
  if to_regprocedure('public.geoportal_campo_cuadrillas(text,jsonb,text)') is null then
    raise exception 'Falta el paquete (a) Personal y cuadrillas: aplíquelo antes';
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v from pg_proc p
   where p.pronamespace = to_regnamespace('redes') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_REDES}}' then raise exception 'Las funciones de redes no son las publicadas (huella {{HUELLA_REDES}}; hay %): deténgase y avise', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = to_regnamespace('tecnica') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%');
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_TECNICA}}' then raise exception 'Las funciones de técnica no son las publicadas (huella {{HUELLA_TECNICA}}; hay %): deténgase y avise', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where (p.pronamespace = 'campo'::regnamespace and p.proname not in ('f_no_borrar_catalogo', 'f_firmas_definitivas', 'f_registro_existe')) or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if v is distinct from '{{HUELLA_CAMPO_A}}' then raise exception 'Las funciones de campo no son las de Personal y cuadrillas publicado (huella {{HUELLA_CAMPO_A}}; hay %): deténgase y avise', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%');
  if v is distinct from '111506c690249ad3b56ebf572566434c' then raise exception 'Las funciones del acta no son las del 21-nov 17:55 (huella 111506c6…; hay %): deténgase y avise', v; end if;
  if to_regclass('campo.formularios_documento') is null and exists (select 1 from storage.buckets where id = 'actas-pdf') then raise exception 'Ya existe el bucket actas-pdf: deténgase y avise'; end if;
  if exists (select 1 from pg_trigger where tgrelid in ('campo.reportes'::regclass, 'acta.actas'::regclass) and tgname in ('t_firmas_al_registrar', 't_derivadas_al_registrar')) then
    raise exception 'Ya hay disparadores de firmas o derivadas en campo.reportes o acta.actas: deténgase y avise';
  end if;
  if to_regclass('campo.formularios_documento') is null and exists (select 1 from campo.tipo_campos where codigo in ('da_lugar', 'da_lugar_otra') and activo) then
    raise exception 'Ya existen los campos da_lugar activos: deténgase y avise';
  end if;
  if (select count(*) from campo.tipos_reporte where codigo in ('revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida', 'suspension', 'corte', 'reinstalacion', 'reconexion_servicio')) <> 8 then
    raise exception 'Faltan tipos de reporte de los 8 formatos con PDF: deténgase y avise';
  end if;
end $$;
