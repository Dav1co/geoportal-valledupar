begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 10 — GUARDIA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte6c_contratos_capa.md (16-nov): la capa de contratos sale de la petición.
-- · Presupone el 6b MÁS el hotfix de pg-safeupdate (huella del conjunto de funciones de redes 8113af17c6bd862d62a6cbc4bc4cba1f).
-- · La tesela de contratos se arma AL VUELO, solo con los predios de su recuadro, con los índices que ya existen en Comercial (no se crea ninguno):
--   GiST de catastro_valledupar.geom, catastro por cod_usuario, ficha_contrato por contrato y cartera_suscripcion por contrato.
-- · Lee (no escribe) lo vivo de Comercial: public.catastro_valledupar, public.cartera_suscripcion y bi_interno.ficha_contrato. Nada de eso cambia.
-- · ⚠ Se reemplazan 3 RPC del 6b (geoportal_redes_geovisor, _geovisor_mvt_contratos y _contrato_tarjeta), con su texto exacto en la reversa.
-- · ⚠ Se retiran la copia derivada (redes.contratos_capa y redes.contratos_capa_estado) y las 2 funciones que la rehacían. No guardaban hechos:
--   eran una copia que se recalculaba entera; la reversa las vuelve a crear vacías.
-- =====================================================================
do $$
begin
  if to_regclass('redes.contratos_capa') is null or to_regprocedure('redes.f_refrescar_contratos_capa()') is null then
    raise exception 'No está la capa derivada del Corte 6b (o el Corte 6c ya está aplicado): deténgase y avise';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '8113af17c6bd862d62a6cbc4bc4cba1f' then
    raise exception 'Las funciones de redes no son las del Corte 6b con el hotfix de safeupdate (o el Corte 6c ya está aplicado): deténgase y avise';
  end if;
  -- lo vivo que se lee
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catastro_valledupar' and column_name in ('id', 'cod_usuario', 'direccion', 'barrio', 'geom')) <> 5
     or (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion'
          and column_name in ('contrato', 'estado', 'nombre', 'direccion', 'barrio', 'categoria', 'periodo_carga')) <> 7
     or (select count(*) from information_schema.columns where table_schema = 'bi_interno' and table_name = 'ficha_contrato'
          and column_name in ('contrato', 'periodo_ultimo', 'uso', 'consumo_meses', 'cons_prom', 'meses_con_lectura', 'medidor_anios')) <> 7 then
    raise exception 'Las tablas de Comercial (catastro, cartera diaria o ficha del contrato) no tienen las columnas esperadas: deténgase y avise';
  end if;
  -- los índices de Comercial con los que la tesela responde rápido (no se crean aquí: si falta alguno, se avisa)
  if not exists (select 1 from pg_index x join pg_class i on i.oid = x.indexrelid join pg_am am on am.oid = i.relam
                  where x.indrelid = 'public.catastro_valledupar'::regclass and am.amname = 'gist' and pg_get_indexdef(i.oid) ~ '\(geom\)') then
    raise exception 'Falta el índice espacial (GiST) de catastro_valledupar.geom: deténgase y avise';
  end if;
  if not exists (select 1 from pg_index x where x.indrelid = 'public.catastro_valledupar'::regclass and x.indisvalid and x.indpred is null
                  and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(cod_usuario( text_pattern_ops)?[,)]') then
    raise exception 'Falta el índice de catastro_valledupar por cod_usuario: deténgase y avise';
  end if;
  if not exists (select 1 from pg_index x where x.indrelid = 'public.cartera_suscripcion'::regclass and x.indisvalid and x.indpred is null
                  and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(contrato[,)]') then
    raise exception 'Falta el índice de cartera_suscripcion por contrato: deténgase y avise';
  end if;
  if not exists (select 1 from pg_index x where x.indrelid = 'bi_interno.ficha_contrato'::regclass and x.indisvalid and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(contrato[,)]') then
    raise exception 'Falta el índice de bi_interno.ficha_contrato por contrato: deténgase y avise';
  end if;
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 26 — FUNCIONES NUEVAS (internas; nadie de la API las ejecuta)
--   · redes.f_contrato_uso: el uso del contrato (el de la ficha y, si no hay, la categoría de la cartera sin su número). Es la misma regla del 6b,
--     ahora en un solo lugar para la tesela y la tarjeta.
--   · redes.f_funciones_sin_where: comprobación estática para pg-safeupdate. En Supabase, las sesiones de la API (rol authenticator) rechazan todo
--     DELETE o UPDATE sin WHERE, también dentro de funciones SECURITY DEFINER; el editor SQL no lo hace, así que un ensayo en el editor no lo ve.
--     Devuelve las sentencias de las funciones de redes, tecnica y public.geoportal_redes_* que no pasarían. Debe devolver cero filas.
-- =====================================================================
create function redes.f_contrato_uso(p_uso_ficha text, p_categoria text) returns text language sql immutable set search_path = pg_catalog as $$
  select coalesce(nullif(btrim(p_uso_ficha), '(sin dato)'), nullif(regexp_replace(btrim(coalesce(p_categoria, '')), '^-?[0-9]+\s+', ''), '')) $$;

-- Cómo mira: quita los comentarios de línea, parte el cuerpo por «;» y marca cada trozo con «delete from …» o «update <tabla> set …» sin un «where»
-- después. No cuentan «on conflict … do update», «for update» ni los disparadores «before update or delete». Límite conocido: un UPDATE cuyo único
-- «where» está dentro de una subconsulta pasa sin marcarse.
create function redes.f_funciones_sin_where() returns table (funcion text, sentencia text)
language sql stable set search_path = pg_catalog as $$
  with f as (
    select p.oid::regprocedure::text as funcion,
           regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace in (select n.oid from pg_namespace n where n.nspname in ('redes', 'tecnica'))
            or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select s.funcion, left(s.st, 200) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M')
   order by 1, 2 $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (6b + hotfix) con cambios exactos, aplicados una sola vez:
--   · geoportal_redes_geovisor: ya no rehace la capa de contratos (vuelve a ser STABLE: solo lee) ni informa el estado de la copia;
--   · geoportal_redes_geovisor_mvt_contratos: la tesela se arma al vuelo con los predios de su recuadro (catastro, ficha y último corte de cartera);
--   · geoportal_redes_contrato_tarjeta: el estado y el uso se leen en el momento; ya no depende de la copia.
-- =====================================================================
-- public.geoportal_redes_geovisor(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare a record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  return jsonb_build_object(
    'perfil', case when a.admin then 'admin' when a.completo then 'supervisor' else 'operador' end,
    'completo', a.completo, 'perfiles', to_jsonb(a.perfiles),
    'hoy', (clock_timestamp() at time zone 'America/Bogota')::date,
    'rango_meses', floor(redes.f_param('geovisor_rango_meses'))::integer,
    'max_elementos', floor(redes.f_param('geovisor_max_elementos'))::integer,
    'zoom', jsonb_build_object('min', redes.f_param('geovisor_zoom_min'), 'red_completa', redes.f_param('geovisor_zoom_red_completa'),
                               'nodos', redes.f_param('geovisor_zoom_nodos'), 'accesorios', redes.f_param('geovisor_zoom_acc'),
                               'contratos', redes.f_param('geovisor_zoom_contratos')),
    'version', (select coalesce(sum(version), 0) from redes.tesela_version),
    'formularios', jsonb_build_object('danos_fallas', redes.f_puede_formulario(a.email, 'danos_fallas'),
                                      'mantenimiento', redes.f_puede_formulario(a.email, 'mantenimiento')),
    'ficha', a.completo, 'compartir', a.completo,
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre, 'grupo', g.grupo, 'fuente', g.fuente, 'estado', g.estado, 'nota', g.nota,
                                          'prefijos', to_jsonb(g.prefijos), 'por_fecha', g.por_fecha,
                                          'encendida', exists (select 1 from redes.capas_por_perfil c where c.capa = g.codigo and c.encendida and c.perfil = any (a.perfiles)))
             order by g.orden)
        from redes.geovisor_capas g where g.activa and (a.completo or not g.solo_completo)), '[]'::jsonb),
    'tipos', coalesce((select jsonb_object_agg(t.prefijo, t.nombre_visible) from redes.v_tipo_visible t), '{}'::jsonb),
    'estados', coalesce((select jsonb_object_agg(e.codigo, e.nombre) from redes.estados_activo e), '{}'::jsonb),
    'materiales', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', m.nombre) order by m.codigo) from redes.materiales m), '[]'::jsonb),
    -- solo el administrador: la tabla de capas por omisión, para editarla (N-11)
    'por_perfil', case when a.admin then coalesce((
      select jsonb_agg(jsonb_build_object('perfil', c.perfil, 'capa', c.capa, 'encendida', c.encendida, 'actualizado_en', c.actualizado_en, 'actualizado_por', c.actualizado_por)
             order by c.perfil, c.capa) from redes.capas_por_perfil c), '[]'::jsonb) end);
end $function$;

-- public.geoportal_redes_geovisor_mvt_contratos(text,integer,integer,integer)
CREATE OR REPLACE FUNCTION public.geoportal_redes_geovisor_mvt_contratos(p_solicitante text, p_z integer, p_x integer, p_y integer)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare a record; v_env geometry; v_env4 geometry; v bytea;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La capa de contratos es para supervisores' using errcode = '42501'; end if;
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < redes.f_param('geovisor_zoom_contratos') then return ''; end if;
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4 := ST_Transform(v_env, 4326);
  -- Corte 6c: sin copia derivada. Un punto por contrato (el predio de menor id); sin el comodín (99999999) ni el «0»; sin nombre, dirección ni deuda.
  select ST_AsMVT(t, 'contratos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(c.geom, 3857), v_env, 4096, 32, true) as geom, c.cod_usuario as contrato,
           coalesce(redes.f_contrato_uso(f.uso, cs.categoria), '') as uso, redes.f_estado_contrato(cs.estado) as estado,
           f.cons_prom::real as consumo, f.medidor_anios as medidor_anios
      from public.catastro_valledupar c
      left join bi_interno.ficha_contrato f on f.contrato = c.cod_usuario
      left join lateral (select s.estado, s.categoria from public.cartera_suscripcion s where s.contrato = c.cod_usuario order by s.periodo_carga desc nulls last limit 1) cs on true
     where c.geom && v_env4 and c.cod_usuario ~ '^[0-9]{1,12}$' and c.cod_usuario not in ('0', '99999999')
       and c.id = (select min(c2.id) from public.catastro_valledupar c2 where c2.cod_usuario = c.cod_usuario and c2.geom is not null)) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $function$;

-- public.geoportal_redes_contrato_tarjeta(text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_contrato_tarjeta(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'bi_interno', 'pg_temp'
AS $function$
declare a record; cs record; pr record; f record; v_c text := btrim(coalesce(p_contrato, ''));
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;
  if v_c !~ '^[0-9]{1,12}$' then perform tecnica.f_error('Escriba solo los números del contrato'); end if;
  if v_c in ('0', '99999999') or not exists (select 1 from public.catastro_valledupar cv where cv.cod_usuario = v_c and cv.geom is not null) then
    perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002');
  end if;
  select s.nombre, s.estado, s.categoria, s.direccion, s.barrio, s.periodo_carga into cs
    from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select cv.direccion, cv.barrio into pr from public.catastro_valledupar cv where cv.cod_usuario = v_c order by cv.id limit 1;
  select fc.periodo_ultimo, fc.uso, fc.consumo_meses, fc.cons_prom, fc.meses_con_lectura, fc.medidor_anios into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  -- la lectura queda registrada: quién, cuándo y qué contrato (NUNCA el nombre ni la dirección)
  perform tecnica.f_auditar(a.email, 'redes_contrato_tarjeta', v_c, jsonb_build_object('datos', 'nombre, dirección y barrio', 'desde', 'geovisor'), p_ip);
  return jsonb_build_object(
    'contrato', v_c,
    'estado', redes.f_estado_contrato(cs.estado), 'estado_texto', nullif(btrim(cs.estado), ''),
    'uso', redes.f_contrato_uso(f.uso, cs.categoria),
    'consumo', case when f.periodo_ultimo is not null then jsonb_build_object(
        'periodo_ultimo', f.periodo_ultimo, 'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura,
        'meses', (select coalesce(jsonb_agg(jsonb_build_object('periodo', m ->> 'periodo', 'm3', m -> 'm3', 'sin_dato', coalesce((m ->> 'sin_dato')::boolean, false),
                                                               'lectura_real', coalesce((m ->> 'lectura_real')::boolean, false)) order by k), '[]'::jsonb)
                    from jsonb_array_elements(f.consumo_meses) with ordinality x(m, k))) end,
    'medidor_anios', f.medidor_anios,
    'tramo', (select v.codigo from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id where t.contrato = v_c),
    'suscriptor', jsonb_build_object(                                  -- DATO PERSONAL: solo en pantalla
      'nombre', nullif(btrim(cs.nombre), ''),
      'direccion', coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')),
      'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), ''))),
    'corte', cs.periodo_carga);
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 30 — RETIRO DE LA COPIA DERIVADA (va DESPUÉS de los reemplazos: ya ninguna función la nombra)
-- redes.contratos_capa era una copia de 111 mil filas que se rehacía entera dentro de la petición del geovisor (44,7 s en producción, contra el
-- tope de 30 s). No guardaba hechos: todo lo que tenía se lee ahora, al vuelo, de las tablas de Comercial. La reversa la vuelve a crear (vacía).
-- El parámetro geovisor_contratos_horas no se borra: queda con su nota de «sin uso».
-- =====================================================================
drop function redes.f_contratos_capa_al_dia();
drop function redes.f_refrescar_contratos_capa();
drop table redes.contratos_capa;
drop table redes.contratos_capa_estado;
update redes.parametros set descripcion = 'Sin uso desde el Corte 6c: la capa de contratos se arma al vuelo en cada tesela y ya no se rehace'
 where clave = 'geovisor_contratos_horas';
update redes.geovisor_capas set nota = 'Desde el zoom 16, siempre al día. Al tocar un contrato: su consumo, nombre y dirección (la consulta queda registrada)'
 where codigo = 'contratos';
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Las 2 funciones internas nuevas: nadie de la API. Las 3 RPC reemplazadas conservan lo suyo (create or replace no cambia permisos); se repite
-- aquí el revoke y el grant a service_role (la Edge geoportal-redes) para que quede explícito.
-- =====================================================================
revoke all on function redes.f_contrato_uso(text, text), redes.f_funciones_sin_where() from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte6c', 'migracion_redes_corte6c', null, jsonb_build_object(
        'reemplazadas', jsonb_build_array('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta'),
        'nuevas', jsonb_build_array('redes.f_contrato_uso', 'redes.f_funciones_sin_where'),
        'retiradas', jsonb_build_array('redes.contratos_capa', 'redes.contratos_capa_estado', 'redes.f_refrescar_contratos_capa', 'redes.f_contratos_capa_al_dia'),
        'motivo', 'la capa de contratos se arma al vuelo; ninguna petición la rehace'), null);
commit;
