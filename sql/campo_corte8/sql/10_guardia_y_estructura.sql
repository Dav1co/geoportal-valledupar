-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 10 — GUARDIA Y ESTRUCTURA: reportes compartidos con Comercial (§10 y §30.3-4 de la bitácora; precisión de David, 16-nov)
-- PROPUESTA. No se ha ejecutado en la base real (solo en un PostgreSQL local con los paquetes de campo hasta la pasada del 14-nov y el Corte 1 de Técnica).
-- Regla de este corte: el formulario, las tablas y la Edge son LOS MISMOS de Comercial (esquema campo, geoportal-campo). No se crea ninguna tabla.
-- No se modifica ni se borra ningún registro existente de las tablas de campo: solo se agrega.
-- · campo.reportes: UNA columna nueva, «area» (nula = Comercial; 'tecnica' = hecho desde Técnica). Agregar una columna nula no reescribe ni cambia ninguna fila.
-- · ⚠ campo.f_autorizar_reporte (viva): una sola condición más, con guardia md5 y su texto exacto en la reversa.
-- · ⚠ tecnica.formulario_clave (dominio vivo) y tecnica.f_formularios (viva): dos claves más, «anomalia_compartida» y «revision_compartida».
-- · campo.tipos_reporte: se AGREGAN «Fuga en acometida» y «Caja de medidor dañada» solo si no existen; los 26 tipos actuales no se tocan.
-- · redes.v_reportes_comercial (del 6b, vacía): se reemplaza la vista (mismas columnas). Ninguna función de redes cambia.
-- =====================================================================
do $$
begin
  if to_regclass('campo.reportes') is null or to_regprocedure('campo.f_autorizar_reporte(text)') is null or to_regprocedure('campo.f_perfil(text)') is null then
    raise exception 'Falta el esquema campo (Formatos de campo): deténgase y avise';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'campo' and table_name = 'reportes' and column_name = 'area')
     or to_regprocedure('campo.f_tecnica_claves(text)') is not null then
    raise exception 'El Corte 8 ya está aplicado (campo.reportes ya tiene «area»): deténgase y avise';
  end if;
  if md5(pg_get_functiondef('campo.f_autorizar_reporte(text)'::regprocedure)) <> '{{MD5_AUTORIZAR}}' then
    raise exception 'campo.f_autorizar_reporte no es la del Paso A de campo: deténgase y avise';
  end if;
  if (select count(*) from pg_proc p where p.oid in (to_regprocedure('public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)'),
        to_regprocedure('public.geoportal_campo_preparar_subida(text,integer,text,text,text)'), to_regprocedure('public.geoportal_campo_obtener_formulario(text,boolean)'))) <> 3 then
    raise exception 'Las RPC de campo (crear, preparar la subida y el formulario) no tienen las firmas esperadas (pasada del 14-nov): deténgase y avise';
  end if;
  if to_regclass('campo.v_reportes_estado') is null or to_regclass('campo.tipos_reporte') is null or to_regclass('campo.grupos_reporte') is null
     or not exists (select 1 from campo.tipos_reporte where codigo = 'revision_previa')
     or not exists (select 1 from campo.grupos_reporte where codigo = 'red_acueducto') then
    raise exception 'El catálogo de campo no es el esperado (falta revision_previa, el grupo red_acueducto o la vista de estados): deténgase y avise';
  end if;
  if to_regtype('tecnica.formulario_clave') is null or to_regprocedure('tecnica.f_autorizar_captura(text,text)') is null
     or md5(pg_get_functiondef('tecnica.f_formularios()'::regprocedure)) <> '{{MD5_FORMULARIOS}}' then
    raise exception 'tecnica.f_formularios o el dominio de formularios de Técnica no son los del Corte 1 de planta: deténgase y avise';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck') <> '{{DEF_DOMINIO}}' then
    raise exception 'El dominio tecnica.formulario_clave no tiene las 7 claves esperadas: deténgase y avise';
  end if;
  if to_regclass('redes.v_reportes_comercial') is null
     or (select string_agg(column_name || ':' || data_type, ',' order by ordinal_position) from information_schema.columns where table_schema = 'redes' and table_name = 'v_reportes_comercial')
        <> 'codigo:text,tipo:text,subtipo:text,area:text,con_contrato:boolean,estado:text,registrado_en:timestamp with time zone,lat:numeric,lon:numeric' then
    raise exception 'Falta redes.v_reportes_comercial (Corte 6b) o no tiene las columnas esperadas: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. EL ÁREA DEL REGISTRO, en la misma tabla. Nula = Comercial (todo lo que ya existe y lo que Comercial siga haciendo). 'tecnica' = hecho desde Técnica.
--    La columna se llena sola al insertar: su valor por omisión mira la marca de la transacción que solo ponen las 3 RPC nuevas (20_funciones).
--    Primero la columna (sin valor por omisión: no toca ninguna fila) y después el valor por omisión (solo para lo que se inserte en adelante).
-- ---------------------------------------------------------------------
alter table campo.reportes add column area text;
alter table campo.reportes add constraint reportes_area_ck check (area is null or area = 'tecnica');
alter table campo.reportes alter column area set default (case when current_setting('geoportal.via_tecnica', true) = 'on' then 'tecnica' end);
comment on column campo.reportes.area is 'Corte 8 de Técnica: área que hizo el reporte. Nulo = Comercial; tecnica = hecho desde Técnica (entrada del modo Redes).';

-- ---------------------------------------------------------------------
-- 2. LAS DOS CLAVES NUEVAS DE TÉCNICA: se asignan en Personal como cualquier formulario (la captura la restringe tecnica.f_autorizar_captura).
-- ---------------------------------------------------------------------
alter domain tecnica.formulario_clave drop constraint formulario_clave_ck;
alter domain tecnica.formulario_clave add constraint formulario_clave_ck check (value in
  ('entrada', 'salida', 'muestreo', 'danos_fallas', 'mantenimiento', 'uso_quimicos', 'entrada_quimicos', 'anomalia_compartida', 'revision_compartida'));

-- ---------------------------------------------------------------------
-- 3. EL CATÁLOGO ES EL MISMO (§30.3): se agregan dos tipos al grupo «red_acueducto», solo si no existe ya uno con ese nombre. Los demás no se tocan.
--    Son del reporte general (sin campos propios ni consecutivo), con contrato opcional, como los otros del grupo.
-- ---------------------------------------------------------------------
insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden)
select g.id, x.codigo, x.nombre, (select coalesce(max(t.orden), 0) from campo.tipos_reporte t where t.grupo_id = g.id) + x.n
  from campo.grupos_reporte g, (values (1, 'fuga_acometida', 'Fuga en acometida', '%fuga%acometida%'), (2, 'caja_medidor_danada', 'Caja de medidor dañada', '%caja%medidor%da_ad%')) x(n, codigo, nombre, parecido)
 where g.codigo = 'red_acueducto'
   and not exists (select 1 from campo.tipos_reporte t where lower(t.nombre) like x.parecido or t.codigo = x.codigo);
