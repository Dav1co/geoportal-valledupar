-- [Code B] INVESTIGACIÓN Y ANÁLISIS (23-nov) · REVERSA (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- INVESTIGACIÓN Y ANÁLISIS · 90 — REVERSA
-- Vuelve preparar_subida y las 4 funciones de las derivadas a su texto publicado, quita las 6 funciones nuevas, desactiva los 5 códigos del
-- catálogo de derivadas (las tablas nuevas y las columnas de campo.derivadas se conservan: nada se borra) y deja la Investigación de ubicación como estaba en producción el 23-nov:
-- con resultado, fotos 3 a 6, las 3 fotos obligatorias (fachada y predio como soporte de la inefectiva), dirección opcional, hallazgo
-- obligatorio y los 4 campos de despeje y visita y la observación activos. Nada se borra: los 4 campos nuevos quedan DESACTIVADOS (activo = false), y los
-- registros que se hayan hecho con ellos conservan sus datos.
-- =====================================================================
do $rev$
declare v_t bigint; r record; v_n bigint;
begin
  if md5(pg_get_functiondef('public.geoportal_campo_preparar_subida(text,integer,text,text,text)'::regprocedure)) is distinct from 'a00d66705d7a0c88a38ab5d882153669' then
    raise exception 'preparar_subida no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise';
  end if;
  for r in select * from (values ('public.geoportal_campo_preparar_subida(text,integer,text,text,text)', 'a00d66705d7a0c88a38ab5d882153669'), ('campo.f_derivada_json(bigint)', '9f59c5cc28a88a5a1f2962ff9d5cb3d2'), ('public.geoportal_campo_derivadas(text,jsonb,text)', '9addead3b57c75986cc5eed52d6cb14a'), ('public.geoportal_campo_derivada_atender(text,bigint,text,uuid,text)', '6735acb66f16e461a252cb6848b5761a'), ('public.geoportal_campo_derivadas_abiertas(text,text,text,text)', '3f369afcec700b12f19b1522f03627e9')) x(f, m) loop
    if md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % cambió después de este paquete: la reversa no la pisa; deténgase y avise', r.f;
    end if;
  end loop;
  -- Con avisos guardados, las funciones publicadas de las derivadas (join estricto con campo.reportes) dejarían filas vacías en «Actividades derivadas»
  select count(*) into v_n from campo.derivadas where observacion_id is not null;
  if v_n > 0 then
    raise exception 'Hay % avisos o actividades del Análisis de contrato: revertir dejaría filas vacías en «Actividades derivadas». Deténgase y avise (no se revierte nada)', v_n;
  end if;
  select id into v_t from campo.tipos_reporte where codigo = 'investigacion_ubicacion' and not genera_resultado and fotos_min = 0;
  if not found then raise exception 'La Investigación de ubicación no está como la deja este paquete: deténgase y avise'; end if;
end $rev$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_preparar_subida(p_solicitante text, p_cantidad integer, p_origen text DEFAULT 'campo'::text, p_ip text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; v_perfil text; v_id uuid := gen_random_uuid(); v_mes text := to_char(campo.f_ahora_bogota(), 'YYYY-MM'); v_max integer := campo.f_param('max_fotos')::integer; v_tmax smallint;
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);
  v_perfil := campo.f_perfil(v_email);
  if coalesce(p_origen, '') not in ('campo', 'escritorio') then perform campo.f_error('El origen debe ser campo o escritorio'); end if;
  if p_origen = 'escritorio' and v_perfil not in ('admin', 'supervisor') then raise exception 'Solo el supervisor o el administrador crean reportes desde el escritorio' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_tipo, '')), '') is not null then
    select t.fotos_max into v_tmax from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id where t.codigo = btrim(p_tipo) and t.activo and g.activo;
    if not found then perform campo.f_error('El tipo de reporte no existe o está desactivado'); end if;
    v_max := coalesce(v_tmax, v_max);
  end if;
  if p_cantidad is null or p_cantidad < (case when p_origen = 'campo' then 1 else 0 end) or p_cantidad > v_max then
    perform campo.f_error(format('La cantidad de fotos debe estar entre %s y %s', case when p_origen = 'campo' then 1 else 0 end, v_max));
  end if;
  perform campo.f_cupo_preparaciones(v_email, v_perfil);   -- Paso B1
  insert into campo.preparaciones (reporte_id, autor) values (v_id, v_email);
  return jsonb_build_object('reporte_id', v_id, 'bucket', 'campo-fotos', 'max_bytes_foto', campo.f_param('max_bytes_foto')::bigint, 'tipo_mime', 'image/jpeg',
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', n, 'ruta', 'reportes/' || v_mes || '/' || v_id::text || '/' || n || '.jpg') order by n)
                         from generate_series(1, p_cantidad) n), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION campo.f_derivada_json(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'campo', 'pg_temp'
AS $function$
  select jsonb_build_object('id', d.id, 'actividad', d.actividad, 'actividad_nombre', c.nombre, 'contrato', d.contrato, 'estado', campo.f_derivada_estado(d.id), 'creada_en', d.creado_en,
           'destinos', to_jsonb(c.destinos), 'destino_omision', c.destino_omision,
           'origen', jsonb_build_object('registro_id', r.id, 'tipo', t.codigo, 'tipo_nombre', t.nombre, 'consecutivo', r.consecutivo, 'fecha', r.registrado_en, 'operario', r.autor),
           'cierre', (select jsonb_build_object('tipo', e.tipo_evento, 'esquema', e.esquema, 'registro_id', e.registro_id, 'autor', e.autor, 'en', e.creado_en, 'motivo', e.motivo,
                                                 'consecutivo', case e.esquema when 'campo' then (select x.consecutivo from campo.reportes x where x.id = e.registro_id)
                                                                               when 'acta' then (select x.consecutivo from acta.actas x where x.id = e.registro_id) end)
                        from campo.derivada_eventos e where e.derivada_id = d.id))
    from campo.derivadas d join campo.derivadas_catalogo c on c.codigo = d.actividad join campo.reportes r on r.id = d.origen_id join campo.tipos_reporte t on t.id = r.tipo_id
   where d.id = p_id
$function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivadas(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'pg_temp'
AS $function$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_est text; v_con text; v_act text; v_desde date; v_hasta date; v_antes bigint; v_lim integer; v_filas jsonb; v_n integer;
begin
  v_email := campo.f_autorizar_registradas(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_est := nullif(f ->> 'estado', ''); v_con := nullif(btrim(coalesce(f ->> 'contrato', '')), ''); v_act := nullif(f ->> 'actividad', '');
    v_desde := nullif(f ->> 'desde', '')::date; v_hasta := nullif(f ->> 'hasta', '')::date; v_antes := nullif(f ->> 'antes', '')::bigint;
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 50), 1), 200);
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  if v_est is not null and v_est not in ('pendiente', 'atendida', 'atendida_fuera', 'anulada') then perform campo.f_error('El estado no es válido'); end if;
  select count(*), coalesce(jsonb_agg(campo.f_derivada_json(x.id) order by x.id desc) filter (where x.rn <= v_lim), '[]'::jsonb) into v_n, v_filas
    from (select d.id, row_number() over (order by d.id desc) as rn from campo.derivadas d
           where (v_est is null or campo.f_derivada_estado(d.id) = v_est) and (v_con is null or d.contrato = v_con) and (v_act is null or d.actividad = v_act)
             and (v_desde is null or (d.creado_en at time zone 'America/Bogota')::date >= v_desde) and (v_hasta is null or (d.creado_en at time zone 'America/Bogota')::date <= v_hasta)
             and (v_antes is null or d.id < v_antes) order by d.id desc limit v_lim + 1) x;
  return jsonb_build_object('filas', v_filas, 'siguiente', case when v_n > v_lim then (select min((e ->> 'id')::bigint) from jsonb_array_elements(v_filas) e) end);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivada_atender(p_solicitante text, p_derivada_id bigint, p_esquema text, p_registro_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'acta', 'pg_temp'
AS $function$
declare v_email text; v_d campo.derivadas; v_c campo.derivadas_catalogo; v_form text; v_con text; v_autor text;
begin
  v_email := campo.f_autorizar_documento(p_solicitante, p_esquema, p_registro_id);
  perform pg_advisory_xact_lock(hashtext('campo_derivada:' || p_derivada_id));
  select * into v_d from campo.derivadas where id = p_derivada_id;
  if v_d.id is null then perform campo.f_error('Esa actividad derivada no existe', 'P0002'); end if;
  select * into v_c from campo.derivadas_catalogo where codigo = v_d.actividad;
  if campo.f_derivada_estado(v_d.id) <> 'pendiente' then perform campo.f_error('Esa actividad derivada ya está cerrada', '55000'); end if;
  if p_esquema = 'campo' then select 'tipo:' || t.codigo, r.contrato, r.autor into v_form, v_con, v_autor from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id where r.id = p_registro_id;
  else select 'acta', a.contrato, a.autor into v_form, v_con, v_autor from acta.actas a where a.id = p_registro_id; end if;
  if not (v_form = any (v_c.destinos)) then perform campo.f_error('Ese formulario no atiende esa actividad derivada'); end if;
  if v_con is distinct from v_d.contrato then perform campo.f_error('El registro es de otro contrato'); end if;
  if p_registro_id = v_d.origen_id then perform campo.f_error('Una revisión no atiende sus propias actividades derivadas'); end if;
  insert into campo.derivada_eventos (derivada_id, tipo_evento, esquema, registro_id, autor) values (v_d.id, 'atendida', p_esquema, p_registro_id, v_email);
  perform campo.f_auditar(v_email, 'campo_derivada_atender', v_d.id::text, jsonb_build_object('esquema', p_esquema, 'registro', p_registro_id), p_ip);
  return campo.f_derivada_json(v_d.id);
end $function$;

CREATE OR REPLACE FUNCTION public.geoportal_campo_derivadas_abiertas(p_solicitante text, p_contrato text, p_formulario text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'campo', 'acta', 'pg_temp'
AS $function$
declare v_email text; v_con text := nullif(btrim(coalesce(p_contrato, '')), '');
begin
  if p_formulario = 'acta' then v_email := acta.f_autorizar(p_solicitante, 'capturar'); else v_email := campo.f_verificar(p_solicitante, 'campo'); end if;
  if v_con is null then return jsonb_build_object('derivadas', '[]'::jsonb); end if;
  return jsonb_build_object('derivadas', (select coalesce(jsonb_agg(campo.f_derivada_json(d.id) order by d.id), '[]'::jsonb)
    from campo.derivadas d join campo.derivadas_catalogo c on c.codigo = d.actividad
   where d.contrato = v_con and p_formulario = any (c.destinos) and campo.f_derivada_estado(d.id) = 'pendiente'));
end $function$;

-- DROP (por qué y alcance): las 6 funciones las creó este paquete; con las 4 de las derivadas ya devueltas a su texto publicado, nadie las usa,
-- y la huella de campo vuelve a 261bed3c9242f6261f845ec4e1374b3a. Alcance: SOLO esas 6 firmas; no toca tablas, datos ni otras funciones.
drop function public.geoportal_campo_aviso_datos_anular(text, bigint, bigint, text, text);
drop function public.geoportal_campo_aviso_datos(text, bigint, text);
drop function public.geoportal_campo_aviso_crear_actividad(text, bigint, text, text);
drop function public.geoportal_campo_analisis_observar(text, text, text, text, text, jsonb, text);
drop function campo.f_texto_sin_datos(text, text, integer, integer);
drop function campo.f_contacto(jsonb);

-- Los 5 códigos del catálogo de derivadas quedan desactivados (nada se borra). Las tablas nuevas y las columnas de campo.derivadas se conservan.
update campo.derivadas_catalogo set activa = false
 where codigo in ('aviso_desocupado', 'aviso_direccion_errada', 'aviso_actualizacion_datos', 'aviso_otra', 'actividad_supervisor');

do $rev_inv$
declare v_t bigint; v_antes jsonb; v_despues jsonb;
begin
  select id into v_t from campo.tipos_reporte where codigo = 'investigacion_ubicacion';
  select jsonb_build_object('tipo', (select to_jsonb(t) from campo.tipos_reporte t where t.id = v_t),
                            'campos', (select jsonb_agg(to_jsonb(c) order by c.orden, c.id) from campo.tipo_campos c where c.tipo_id = v_t),
                            'fotos', (select jsonb_agg(to_jsonb(f) order by f.orden, f.id) from campo.tipo_fotos f where f.tipo_id = v_t)) into v_antes;
  update campo.tipos_reporte set genera_resultado = true, fotos_min = 3 where id = v_t;
  update campo.tipo_fotos set obligatoria = true where tipo_id = v_t and codigo in ('fachada_nomenclatura', 'predio_lote', 'vecino_referencia');
  update campo.tipo_fotos set soporte_inefectiva = true where tipo_id = v_t and codigo in ('fachada_nomenclatura', 'predio_lote');
  update campo.tipo_campos set obligatorio = false where tipo_id = v_t and codigo = 'direccion_encontrada';
  update campo.tipo_campos set obligatorio = true where tipo_id = v_t and codigo = 'hallazgo';
  update campo.tipo_campos set activo = true where tipo_id = v_t and codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada', 'cita_acordada', 'observacion');
  update campo.tipo_campos set activo = false where tipo_id = v_t and codigo in ('barrio', 'habitado', 'tipo_predio', 'medidor');
  select jsonb_build_object('tipo', (select to_jsonb(t) from campo.tipos_reporte t where t.id = v_t),
                            'campos', (select jsonb_agg(to_jsonb(c) order by c.orden, c.id) from campo.tipo_campos c where c.tipo_id = v_t),
                            'fotos', (select jsonb_agg(to_jsonb(f) order by f.orden, f.id) from campo.tipo_fotos f where f.tipo_id = v_t)) into v_despues;
  perform campo.f_auditar('migracion@geoportal', 'campo_catalogo', 'tipo:investigacion_ubicacion',
                          jsonb_build_object('paquete', 'campo_inv_analisis', 'reversa', true, 'antes', v_antes, 'despues', v_despues), null);
end $rev_inv$;

commit;
