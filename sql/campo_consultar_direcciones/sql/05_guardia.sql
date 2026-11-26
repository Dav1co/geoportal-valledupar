-- =====================================================================
-- CONSULTAR DIRECCIONES (Code A, 25-nov) · 05 — GUARDIA: se detiene sin cambiar nada si la base no es la publicada
-- Huella de campo {{HUELLA_CAMPO}} (con el registro flexible publicado), acta {{HUELLA_ACTA}} y Técnica {{HUELLA_TECNICA}} (no cambian con este paquete);
-- md5 de cada función que se reemplaza o de la que depende el cambio; estructura EXACTA (paso 0 del 25-nov, 23:25) de campo.consultas_analisis, campo.parametros
-- y campo.reporte_registro; y de las dos tablas grandes que solo se leen (catastro_valledupar, cartera_suscripcion), lo que el paquete usa: sus columnas con su
-- tipo y los índices por contrato (sin ellos, la ruta nueva barrería 123 mil y 112 mil filas).
-- =====================================================================
do $guardia$
declare v text; r record;
begin
  if to_regprocedure('public.geoportal_campo_direccion_contrato(text,text,text)') is not null then
    raise exception 'Este paquete ya parece aplicado (existe geoportal_campo_direccion_contrato): use la reversa antes de repetir';
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
  -- Estructura exacta (m2: la que deja la reversa de este paquete, que conserva la columna via; nada se borra)
  for r in select * from (values {{EST_LISTA}}) x(t, m, m2) loop
    if to_regclass(r.t) is null then raise exception 'No existe la tabla %: deténgase y avise', r.t; end if;
    select {{EST_EXPR}} into v from (select to_regclass(r.t) as rel) z;
    if v is distinct from r.m and v is distinct from coalesce(r.m2, r.m) then
      raise exception 'La estructura de % no es la de producción (columnas, restricciones, índices, disparadores, RLS o permisos): deténgase y avise', r.t;
    end if;
  end loop;
  for r in select * from (values {{EST_NUEVAS}}) x(t, m) loop
    if to_regclass(r.t) is not null then
      select {{EST_EXPR}} into v from (select to_regclass(r.t) as rel) z;
      if v is distinct from r.m then raise exception 'La tabla % ya existe y no es la de este paquete: deténgase y avise', r.t; end if;
    end if;
  end loop;
  -- Las dos tablas grandes que solo se leen: las columnas que usa el paquete, con su tipo, y los índices por contrato
  for r in select * from (values ('public.catastro_valledupar', 'cod_usuario'), ('public.catastro_valledupar', 'direccion'), ('public.catastro_valledupar', 'barrio'),
                                 ('public.catastro_valledupar', 'unih'), ('public.catastro_valledupar', 'uninh'), ('public.catastro_valledupar', 'clase_uso'),
                                 ('public.catastro_valledupar', 'act_eco'), ('public.cartera_suscripcion', 'contrato'), ('public.cartera_suscripcion', 'direccion'),
                                 ('public.cartera_suscripcion', 'barrio'), ('public.cartera_suscripcion', 'periodo_carga')) x(t, c) loop
    if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass(r.t) and a.attname = r.c and not a.attisdropped and a.atttypid = 'text'::regtype) then
      raise exception 'La columna %.% no existe o no es texto: deténgase y avise', r.t, r.c;
    end if;
  end loop;
  if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid where i.indrelid = 'public.catastro_valledupar'::regclass and c.relname = 'idx_catastro_cod_usuario'
                  and pg_get_indexdef(i.indexrelid) ~ 'USING btree \(cod_usuario\)$') then
    raise exception 'Falta el índice idx_catastro_cod_usuario (btree por cod_usuario): deténgase y avise';
  end if;
  if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid where i.indrelid = 'public.cartera_suscripcion'::regclass and c.relname = 'idx_cartera_contrato'
                  and pg_get_indexdef(i.indexrelid) ~ 'USING btree \(contrato\)$') then
    raise exception 'Falta el índice idx_cartera_contrato (btree por contrato): deténgase y avise';
  end if;
  if exists (select 1 from pg_policies where schemaname in ('campo', 'acta')) then
    raise exception 'Hay políticas RLS en campo o acta: este paquete se preparó para ninguna; deténgase y avise';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'homelab_lectura' and rolbypassrls) then
    raise exception 'No existe el rol homelab_lectura con BYPASSRLS: deténgase y avise';
  end if;
  if exists (select 1 from campo.parametros where clave = 'limite_direccion_hora' and (unidad <> 'consultas' or minimo is distinct from 1 or maximo is distinct from 1000)) then
    raise exception 'Ya existe el parámetro limite_direccion_hora y no es el de este paquete: deténgase y avise';
  end if;
  if (select count(*) from campo.parametros where clave in ('multiplo_supervisor')) <> 1 then
    raise exception 'Falta el parámetro multiplo_supervisor: deténgase y avise';
  end if;
end $guardia$;
