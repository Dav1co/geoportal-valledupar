-- =====================================================================
-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · 05 — GUARDIA (se detiene si la base no es la de producción del 21-nov 17:55)
-- Huellas: redes 1ba19272… y técnica 3e9b0121… (corte de eventos publicado); campo cf40d2a2… (68 funciones) y las md5 de lo que se reemplaza.
-- =====================================================================
do $$
declare v text;
begin
  if to_regprocedure('public.geoportal_campo_cuadrillas(text,jsonb,text)') is not null then
    raise exception 'Personal y cuadrillas de Comercial ya parece aplicado (existe geoportal_campo_cuadrillas): use la reversa antes de repetir';
  end if;
  -- tras una reversa con datos, las tablas se conservan (y el disparador campo.f_no_borrar_catalogo): la migración las reutiliza; por eso esa función no cuenta en la huella
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v from pg_proc p
   where p.pronamespace = to_regnamespace('redes') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_REDES}}' then raise exception 'Las funciones de redes no son las publicadas el 21-nov (huella {{HUELLA_REDES}}; hay %): deténgase y avise', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = to_regnamespace('tecnica') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%');
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_TECNICA}}' then raise exception 'Las funciones de técnica no son las publicadas el 21-nov (huella {{HUELLA_TECNICA}}; hay %): deténgase y avise', v; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where (p.pronamespace = 'campo'::regnamespace and p.proname <> 'f_no_borrar_catalogo') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_CAMPO}}' then raise exception 'Las funciones de campo no son las del 21-nov 17:55 (huella {{HUELLA_CAMPO}}; hay %): deténgase y avise', v; end if;
  if md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal(text,jsonb,text)'))) is distinct from 'f8a83b02da97e8f6a729767f57a394c4'
     or md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_historial_personal(text,jsonb,text)'))) is distinct from 'e82377f5de26a2dcc1a007403889ba48'
     or md5(pg_get_functiondef(to_regprocedure('public.geoportal_campo_personal_cambiar(text,text,text,text,text,text,text)'))) is distinct from 'c0302a7b45307215d8f780d8c78cd396'
     or md5(pg_get_functiondef(to_regprocedure('campo.f_formularios_personal()'))) is distinct from '283a63c1ee3fad9e5956a65f8a4644b6' then
    raise exception 'Las funciones de Personal de campo no son las esperadas (pasada del 14-nov y Corte 14): deténgase y avise';
  end if;
  if to_regclass('campo.cuadrillas') is null and ((select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_eventos_tipo_evento_check')
       is distinct from 'CHECK ((tipo_evento = ANY (ARRAY[''fijar_cargo''::text, ''asignar_formulario''::text, ''quitar_formulario''::text])))'
     or (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_ev_ck')
       is distinct from 'CHECK ((((tipo_evento = ''fijar_cargo''::text) = (cargo IS NOT NULL)) AND ((tipo_evento = ''fijar_cargo''::text) = (formulario IS NULL)) AND ((tipo_evento <> ''quitar_formulario''::text) OR (motivo IS NOT NULL))))'
     or exists (select 1 from pg_attribute where attrelid = 'campo.personal_eventos'::regclass and attname = 'valor' and not attisdropped)) then
    raise exception 'campo.personal_eventos no tiene los CHECK de la pasada del 14-nov: deténgase y avise';
  end if;
  if to_regprocedure('campo.f_auditar(text,text,text,jsonb,text)') is null or to_regprocedure('campo.f_autorizar_personal(text)') is null
     or to_regprocedure('campo.f_autorizar_supervision(text)') is null or to_regprocedure('campo.f_autorizar_admin(text)') is null or to_regprocedure('campo.f_solo_agregar()') is null then
    raise exception 'Faltan funciones internas de campo (auditar, autorizar o solo agregar): deténgase y avise';
  end if;
end $$;
