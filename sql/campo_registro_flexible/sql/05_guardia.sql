-- =====================================================================
-- REGISTRO FLEXIBLE (Code A, 25-nov) · 05 — GUARDIA: se detiene sin cambiar nada si la base no es la publicada
-- Comprueba: huella de campo {{HUELLA_CAMPO}} (todas las funciones de campo y las public.geoportal_campo_*, que incluyen la entrada de Técnica
-- geoportal_campo_tec_*), huella del acta {{HUELLA_ACTA}}, huella de Técnica {{HUELLA_TECNICA}} (esquema tecnica y public.geoportal_tec_*: este paquete
-- no la cambia; se comprueba antes y después porque cambia la firma de geoportal_campo_tec_crear_reporte), el md5 de cada función que se reemplaza o de la
-- que depende el cambio, la estructura exacta de las tablas vivas que el paquete lee o toca (columnas, tipos, NOT NULL, valores por omisión, identidad,
-- restricciones, índices, disparadores, RLS y permisos), sin políticas RLS en campo ni acta, y el rol homelab_lectura con BYPASSRLS.
-- =====================================================================
do $guardia$
declare v text; r record;
begin
  if to_regprocedure('{{F_CREAR_NUEVA}}') is not null then
    raise exception 'Este paquete ya parece aplicado (existe geoportal_campo_crear_reporte con p_registro): use la reversa antes de repetir';
  end if;
  if to_regprocedure('public.geoportal_campo_derivadas_descarga_iniciar(text,jsonb,text,boolean,text)') is not null then
    raise exception 'Este paquete ya parece aplicado (existe geoportal_campo_derivadas_descarga_iniciar): use la reversa antes de repetir';
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%');
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_CAMPO}}' then
    raise exception 'Las funciones de campo no son las publicadas (huella {{HUELLA_CAMPO}}; hay %): deténgase y avise', v;
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_acta\_%');
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_ACTA}}' then
    raise exception 'Las funciones del acta no son las publicadas (huella {{HUELLA_ACTA}}; hay %): deténgase y avise', v;
  end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) into v from pg_proc p
   where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_tec\_%'));
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_TECNICA}}' then
    raise exception 'Las funciones de Técnica no son las publicadas (huella {{HUELLA_TECNICA}}; hay %): deténgase y avise', v;
  end if;
  for r in select * from (values {{MD5_FUNCIONES}}) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la publicada: deténgase y avise', r.f;
    end if;
  end loop;
  -- Estructura exacta de las tablas vivas (la misma expresión que calcula generar.py en el doble, que es copia exacta de producción)
  -- (m2: el estado que deja la reversa de este paquete, que conserva la columna nueva de campo.reporte_fotos; nada se borra)
  for r in select * from (values {{EST_LISTA}}) x(t, m, m2) loop
    if to_regclass(r.t) is null then raise exception 'No existe la tabla %: deténgase y avise', r.t; end if;
    select {{EST_EXPR}} into v from (select to_regclass(r.t) as rel) z;
    if v is distinct from r.m and v is distinct from coalesce(r.m2, r.m) then
      raise exception 'La estructura de % no es la de producción (columnas, restricciones, índices, disparadores, RLS o permisos): deténgase y avise', r.t;
    end if;
  end loop;
  -- La tabla nueva: no existe, o existe exactamente como la crea este paquete (la conservó una reversa)
  for r in select * from (values {{EST_NUEVAS}}) x(t, m) loop
    if to_regclass(r.t) is not null then
      select {{EST_EXPR}} into v from (select to_regclass(r.t) as rel) z;
      if v is distinct from r.m then raise exception 'La tabla % ya existe y no es la de este paquete: deténgase y avise', r.t; end if;
    end if;
  end loop;
  -- Sin políticas RLS en campo ni acta (David, 23-nov): el Dell lee porque homelab_lectura tiene BYPASSRLS; basta el GRANT SELECT explícito
  if exists (select 1 from pg_policies where schemaname in ('campo', 'acta')) then
    raise exception 'Hay políticas RLS en campo o acta: este paquete se preparó para ninguna; deténgase y avise';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'homelab_lectura' and rolbypassrls) then
    raise exception 'No existe el rol homelab_lectura con BYPASSRLS: deténgase y avise';
  end if;
  -- Los 4 parámetros de la zona de Valledupar (el XY digitado se valida contra ellos)
  if (select count(*) from campo.parametros where clave in ('zona_lat_min', 'zona_lat_max', 'zona_lon_min', 'zona_lon_max')) <> 4 then
    raise exception 'Faltan los parámetros de la zona de Valledupar en campo.parametros: deténgase y avise';
  end if;
end $guardia$;
