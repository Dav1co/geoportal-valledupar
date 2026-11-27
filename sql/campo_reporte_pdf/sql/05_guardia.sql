-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov) · 05 — GUARDIA: se detiene sin cambiar nada si la base no es la esperada
-- Huella de campo {{HUELLA_CAMPO}} (con la etiqueta del último pago), ordenada con collate "C"; acta y Técnica publicadas; las funciones de permisos vivas;
-- las columnas que se leen de las tablas de campo, acta y la lista blanca; las capas del mapa con sus índices GiST de producción; el bucket privado de los PDF.
-- =====================================================================
do $guardia$
declare v text; r record;
begin
  if to_regprocedure('public.geoportal_campo_ran_datos(text,uuid,text)') is not null then
    raise exception 'Este paquete ya parece aplicado (existe geoportal_campo_ran_datos): use la reversa antes de repetir';
  end if;
  select ({{HUELLA_CAMPO_Q}}) into v;
  if coalesce(v, '(ninguna)') is distinct from '{{HUELLA_CAMPO}}' then
    raise exception 'Las funciones de campo no son las esperadas (huella {{HUELLA_CAMPO}}; hay %): deténgase y avise', v;
  end if;
  if ({{HUELLA_ACTA_Q}}) is distinct from '{{HUELLA_ACTA}}' then raise exception 'Las funciones del acta no son las publicadas: deténgase y avise'; end if;
  if ({{HUELLA_TECNICA_Q}}) is distinct from '{{HUELLA_TECNICA}}' then raise exception 'Las funciones de Técnica no son las publicadas: deténgase y avise'; end if;
  for r in select * from (values {{MD5_PERMISOS}}) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la publicada: deténgase y avise', r.f;
    end if;
  end loop;
  -- la tabla nueva, si quedó de una reversa, debe ser exactamente la de este paquete
  if to_regclass('campo.reporte_pdf') is not null then
    select {{EST_EXPR}} into v from (select to_regclass('campo.reporte_pdf') as rel) z;
    if v is distinct from '{{EST_TABLA_NUEVA}}' then raise exception 'La tabla campo.reporte_pdf ya existe y no es la de este paquete: deténgase y avise'; end if;
  end if;
  if to_regclass('campo.reporte_ran') is not null then
    select {{EST_EXPR}} into v from (select to_regclass('campo.reporte_ran') as rel) z;
    if v is distinct from '{{EST_TABLA_RAN}}' then raise exception 'La tabla campo.reporte_ran ya existe y no es la de este paquete: deténgase y avise'; end if;
  end if;
  -- columnas que se leen (con su tipo)
  for r in select * from (values {{COLUMNAS}}) x(t, c, ty) loop
    if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass(r.t) and a.attname = r.c and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = r.ty) then
      raise exception 'La columna %.% no existe o no es %: deténgase y avise', r.t, r.c, r.ty;
    end if;
  end loop;
  -- capas de los dos mapas (paso 0 de producción, David, 27-nov): clase, geometría y su índice GiST con la definición EXACTA
  for r in select * from (values
      ('public.redes_acueducto', 'r', 'CREATE INDEX idx_redes_acu_geom ON public.redes_acueducto USING gist (geom)'),
      ('public.redes_alcantarillado', 'r', 'CREATE INDEX idx_redes_alc_geom ON public.redes_alcantarillado USING gist (geom)'),
      ('public.predios_comercial', 'm', 'CREATE INDEX idx_predcom_geom_n ON public.predios_comercial USING gist (geom)'),
      ('public.catastro_valledupar', 'r', 'CREATE INDEX idx_catastro_geom ON public.catastro_valledupar USING gist (geom)'),
      ('public.terrenos_valledupar', 'r', 'CREATE INDEX terrenos_valledupar_geom_geom_idx ON public.terrenos_valledupar USING gist (geom)'),
      ('public.barrios_valledupar', 'r', 'CREATE INDEX idx_barrios_geom ON public.barrios_valledupar USING gist (geom)'),
      ('tecnica.elementos_planta', 'r', 'CREATE INDEX ix_elementos_planta_geom ON tecnica.elementos_planta USING gist (geom)')) x(t, k, i) loop
    if to_regclass(r.t) is null or (select relkind::text from pg_class where oid = to_regclass(r.t)) <> r.k then
      raise exception 'La capa % no existe o no es de la clase esperada (%): deténgase y avise', r.t, r.k;
    end if;
    if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass(r.t) and a.attname = 'geom' and not a.attisdropped and format_type(a.atttypid, a.atttypmod) like 'geometry%') then
      raise exception 'La capa % no tiene la columna geom (geometry): deténgase y avise', r.t;
    end if;
    if not exists (select 1 from pg_index i where i.indrelid = to_regclass(r.t) and pg_get_indexdef(i.indexrelid) = r.i) then
      raise exception 'Falta el índice GiST de % con la definición «%»: deténgase y avise', r.t, r.i;
    end if;
  end loop;
  -- las columnas de las capas que se leen (de predios_comercial SOLO cod_usuario y sin_contrato)
  for r in select * from (values ('public.predios_comercial', 'cod_usuario', 'text'), ('public.predios_comercial', 'sin_contrato', 'boolean'),
                                 ('public.barrios_valledupar', 'nombre', 'text'), ('tecnica.elementos_planta', 'tipo', 'text'),
                                 ('tecnica.elementos_planta', 'codigo', 'text'), ('tecnica.elementos_planta', 'activo', 'boolean')) x(t, c, ty) loop
    if not exists (select 1 from pg_attribute a where a.attrelid = to_regclass(r.t) and a.attname = r.c and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = r.ty) then
      raise exception 'La columna %.% no existe o no es %: deténgase y avise', r.t, r.c, r.ty;
    end if;
  end loop;
  if not exists (select 1 from public.spatial_ref_sys where srid = 3116) then raise exception 'Falta el sistema de referencia 3116 (MAGNA-SIRGAS Bogotá): deténgase y avise'; end if;
  if not exists (select 1 from storage.buckets where id = 'actas-pdf' and not public) then raise exception 'Falta el bucket privado actas-pdf: deténgase y avise'; end if;
  if exists (select 1 from pg_policies where schemaname in ('campo', 'acta')) then raise exception 'Hay políticas RLS en campo o acta: deténgase y avise'; end if;
  if not exists (select 1 from pg_roles where rolname = 'homelab_lectura') then raise exception 'No existe el rol homelab_lectura: deténgase y avise'; end if;
end $guardia$;
