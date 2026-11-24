-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS (Code B, 23-nov) · 05 — GUARDIA: se detiene sin cambiar nada si la base no es la publicada
-- Comprueba: huella de campo {{HUELLA_CAMPO}} (todas las funciones de campo y las public.geoportal_campo_*), huella del acta {{HUELLA_ACTA}},
-- el md5 de cada función que se reemplaza, la estructura exacta de las tablas vivas que el paquete lee o toca (columnas, tipos, NOT NULL,
-- valores por omisión, identidad, restricciones, índices, disparadores, RLS y permisos), y el estado de partida de la Investigación de
-- ubicación tal como está en producción (consulta del 23-nov 22:37): id 35, activa, con resultado, fotos 3 a 6, contrato «si», sus 7 campos,
-- sus 3 fotos obligatorias, 0 registros y presente en campo.actividades.
-- =====================================================================
do $guardia$
declare v text; r record; v_t campo.tipos_reporte%rowtype; v_campos text; v_fotos text;
begin
  if to_regprocedure('public.geoportal_campo_analisis_observar(text,text,text,text,text,jsonb,text)') is not null then
    raise exception 'Este paquete ya parece aplicado (existe geoportal_campo_analisis_observar): use la reversa antes de repetir';
  end if;
  if to_regprocedure('public.geoportal_campo_preparar_subida(text,integer,text,text,text)') is not null
     and md5(pg_get_functiondef('public.geoportal_campo_preparar_subida(text,integer,text,text,text)'::regprocedure)) = '{{MD5_PREPARAR_NUEVA}}' then
    raise exception 'Este paquete ya parece aplicado (preparar_subida ya es la de este cambio): use la reversa antes de repetir';
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
  for r in select * from (values {{MD5_FUNCIONES}}) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la publicada: deténgase y avise', r.f;
    end if;
  end loop;
  -- Estructura exacta de las tablas vivas (la misma expresión que calcula generar.py en el doble, que es copia exacta de producción)
  -- (m2: el estado que deja la reversa de este paquete, que conserva la estructura; nada se borra)
  for r in select * from (values {{EST_LISTA}}) x(t, m, m2) loop
    if to_regclass(r.t) is null then raise exception 'No existe la tabla %: deténgase y avise', r.t; end if;
    select {{EST_EXPR}} into v from (select to_regclass(r.t) as rel) z;
    if v is distinct from r.m and v is distinct from coalesce(r.m2, r.m) then
      raise exception 'La estructura de % no es la de producción (columnas, restricciones, índices, disparadores, RLS o permisos): deténgase y avise', r.t;
    end if;
  end loop;
  -- Las tablas nuevas: no existen, o existen exactamente como las crea este paquete (las conservó una reversa)
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
  -- Estado de partida de la Investigación de ubicación
  select * into v_t from campo.tipos_reporte where codigo = 'investigacion_ubicacion';
  if not found then raise exception 'No existe la Investigación de ubicación: deténgase y avise'; end if;
  if (v_t.id, v_t.activo, v_t.genera_resultado, v_t.fotos_min, v_t.fotos_max, v_t.requiere_contrato, v_t.prefijo_consecutivo)
     is distinct from (35::bigint, true, true, 3::smallint, 6::smallint, 'si'::text, 'INV'::text) then
    raise exception 'La Investigación de ubicación no está como en producción (id 35, activa, con resultado, fotos 3 a 6, contrato si, prefijo INV): deténgase y avise';
  end if;
  select string_agg(c.codigo || ':' || c.tipo_dato || ':' || c.obligatorio::text || ':' || c.activo::text, ',' order by c.codigo) into v_campos
    from campo.tipo_campos c where c.tipo_id = v_t.id;
  -- Se acepta también el estado que deja la reversa de este paquete (los 4 campos nuevos desactivados, nada se borra)
  if v_campos is distinct from '{{INV_CAMPOS}}' and v_campos is distinct from '{{INV_CAMPOS_TRAS_REVERSA}}' then
    raise exception 'Los campos de la Investigación no son los de producción (hay %): deténgase y avise', v_campos;
  end if;
  select string_agg(f.codigo || ':' || f.obligatoria::text || ':' || f.soporte_inefectiva::text || ':' || f.activo::text, ',' order by f.codigo) into v_fotos
    from campo.tipo_fotos f where f.tipo_id = v_t.id;
  if v_fotos is distinct from '{{INV_FOTOS}}' then
    raise exception 'Las fotos de la Investigación no son las de producción (hay %): deténgase y avise', v_fotos;
  end if;
  -- 0 registros, salvo que la Investigación esté como la deja la reversa de este paquete (esos registros se hicieron con este paquete)
  if v_campos = '{{INV_CAMPOS}}' and exists (select 1 from campo.reportes where tipo_id = v_t.id) then
    raise exception 'La Investigación de ubicación ya tiene registros: este paquete se preparó para 0; deténgase y avise';
  end if;
  if not exists (select 1 from campo.actividades a where a.codigo = 'investigacion_ubicacion' and a.activa and 'tipo:investigacion_ubicacion' = any (a.formularios)) then
    raise exception 'La actividad investigacion_ubicacion no está activa en campo.actividades: deténgase y avise';
  end if;
  if exists (select 1 from campo.tipo_campos where tipo_id = v_t.id and codigo in ('barrio', 'habitado', 'tipo_predio', 'medidor') and activo) then
    raise exception 'Algún campo nuevo de la Investigación ya existe y está activo: deténgase y avise';
  end if;
end $guardia$;
