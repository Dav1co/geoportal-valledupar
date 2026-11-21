-- Doble local de Comercial para el Code B (Code A, 21-nov): cadena de campo + acta + salida (huellas de 8 funciones y conjuntos de acta y salida = producción del 21-nov 17:55)
-- con el paquete (a) Personal y cuadrillas YA APLICADO (rama comercial-personal-cuadrillas, cf21358). PostgreSQL 16.2. Sin datos reales. Cárguelo en una base VACÍA.
do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if; end $$;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if; end $$;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator nologin; end if; end $$;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'dell_envios') then create role dell_envios nologin; end if; end $$;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if; end $$;
--
-- PostgreSQL database dump
--

\restrict ruU3dixnJVuCkeY5Kh0WB1yIxl1o3AYgfNKyglSMfbR4mMUGDHqWlub72OG8l9x

-- Dumped from database version 16.2
-- Dumped by pg_dump version 17.12 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', false);  -- el doble de PostGIS (geometry) vive en public
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: acta; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA acta;


--
-- Name: SCHEMA acta; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA acta IS 'Acta de inspección técnica (registro digital que acompaña al acta física). Acceso solo por RPC geoportal_acta_* (service_role).';


--
-- Name: bi; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bi;


--
-- Name: bi_interno; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bi_interno;


--
-- Name: campo; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA campo;


--
-- Name: SCHEMA campo; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA campo IS 'Formatos de campo (Torre A): reporte general multipropósito. Acceso solo por RPC geoportal_campo_* (service_role).';


--
-- Name: hechos; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA hechos;


--
-- Name: redes; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA redes;


--
-- Name: salida; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA salida;


--
-- Name: SCHEMA salida; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA salida IS 'Cola de salida de constancias por correo. El Dell la lee con el rol dell_envios (vista + 4 funciones). Contrato: contrato_cola_dell.md.';


--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA storage;


--
-- Name: tecnica; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tecnica;


--
-- Name: geography; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.geography AS (
	x double precision,
	y double precision
);


--
-- Name: geometry; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.geometry AS (
	x double precision,
	y double precision
);


--
-- Name: formulario_clave; Type: DOMAIN; Schema: tecnica; Owner: -
--

CREATE DOMAIN tecnica.formulario_clave AS text
	CONSTRAINT formulario_clave_ck CHECK ((VALUE = ANY (ARRAY['entrada'::text, 'salida'::text, 'muestreo'::text, 'danos_fallas'::text, 'mantenimiento'::text, 'uso_quimicos'::text, 'entrada_quimicos'::text, 'anomalia_compartida'::text, 'revision_compartida'::text])));


--
-- Name: CAST (public.geometry AS public.geography); Type: CAST; Schema: -; Owner: -
--

CREATE CAST (public.geometry AS public.geography) WITH INOUT;


--
-- Name: f_abrir(text, text, numeric, numeric, numeric, uuid, uuid, text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_abrir(p_email text, p_perfil text, p_lat numeric, p_lon numeric, p_precision numeric, p_reporte uuid, p_correccion_de uuid, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_lat numeric; v_lon numeric; v_fuera boolean; v_serie text; v_pref text; v_num integer; v_cons text; v_id uuid := gen_random_uuid();
        v_prev acta.actas%rowtype; v_raiz uuid; v_abierto timestamptz;
begin
  if p_lat is null or p_lon is null or p_lat = 'NaN'::numeric or p_lon = 'NaN'::numeric then perform acta.f_error('La coordenada no es válida'); end if;
  if p_lat < -90 or p_lat > 90 or p_lon < -180 or p_lon > 180 then perform acta.f_error('La coordenada está fuera de los rangos válidos de latitud y longitud'); end if;
  if p_precision is not null and (p_precision = 'NaN'::numeric or p_precision < 0 or p_precision > 100000) then perform acta.f_error('La precisión de la coordenada no es válida'); end if;
  v_lat := round(p_lat, 6); v_lon := round(p_lon, 6);
  v_fuera := not (v_lat between acta.f_param('zona_lat_min') and acta.f_param('zona_lat_max') and v_lon between acta.f_param('zona_lon_min') and acta.f_param('zona_lon_max'));
  if p_reporte is not null then
    if to_regclass('campo.reportes') is null or not exists (select 1 from campo.reportes r where r.id = p_reporte) then perform acta.f_error('El reporte de campo indicado no existe'); end if;
  end if;

  if p_correccion_de is null then
    perform acta.f_cupo_aperturas(p_email, p_perfil);
    v_serie := to_char(acta.f_hoy_bogota(), 'YYYY');
    insert into acta.consecutivos (serie, prefijo) select v_serie, c.prefijo from acta.consecutivos c order by c.serie desc limit 1 on conflict (serie) do nothing;
    update acta.consecutivos set ultimo_numero = ultimo_numero + 1, actualizado_en = clock_timestamp() where serie = v_serie returning prefijo, ultimo_numero into v_pref, v_num;
    if v_pref is null then raise exception 'Falta la serie de consecutivos %: el administrador debe crearla', v_serie using errcode = 'P0002'; end if;
    v_cons := v_pref || '-' || v_serie || '-' || lpad(v_num::text, 6, '0');
    v_raiz := v_id;
  else
    select * into v_prev from acta.actas where id = p_correccion_de;
    if not found then perform acta.f_error('El acta que se quiere corregir no existe', 'P0002'); end if;
    if v_prev.id <> acta.f_vigente(v_prev.acta_raiz_id) then perform acta.f_error('Solo se corrige la versión vigente del caso', '55000'); end if;
    if exists (select 1 from acta.aperturas a where a.correccion_de = v_prev.id and not exists (select 1 from acta.actas x where x.id = a.id)
                and a.abierto_en > clock_timestamp() - make_interval(hours => acta.f_param('vigencia_apertura_horas')::integer)) then
      perform acta.f_error('Ya hay una corrección en curso para esta acta', '55000');
    end if;
    v_serie := v_prev.serie; v_num := v_prev.numero; v_cons := v_prev.consecutivo; v_raiz := v_prev.acta_raiz_id;
  end if;

  insert into acta.aperturas (id, serie, numero, consecutivo, autor, lat, lon, precision_m, fuera_de_zona, reporte_id, acta_raiz_id, correccion_de, motivo_correccion)
  values (v_id, v_serie, v_num, v_cons, p_email, v_lat, v_lon, p_precision, v_fuera, p_reporte, v_raiz, p_correccion_de, p_motivo)
  returning abierto_en into v_abierto;
  return jsonb_build_object('acta_id', v_id, 'consecutivo', v_cons, 'abierto_en', v_abierto,
                            'vence_en', v_abierto + make_interval(hours => acta.f_param('vigencia_apertura_horas')::integer), 'aviso_zona', v_fuera);
end $$;


--
-- Name: f_acta_coherente(); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_acta_coherente() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'acta', 'pg_temp'
    AS $$
declare v_prev acta.actas%rowtype; v_norm text := upper(regexp_replace(coalesce(new.numero_acta_fisica, ''), '[^A-Za-z0-9]', '', 'g'));   -- (una columna generada aún no tiene valor en un BEFORE)
begin
  if v_norm <> '' and exists (select 1 from acta.actas x where x.numero_fisico_norm = v_norm and x.acta_raiz_id <> new.acta_raiz_id) then
    raise exception 'Ese número de acta física ya está registrado en otro caso' using errcode = '23505', hint = 'msg_usuario';
  end if;
  if new.version = 1 then
    if new.acta_raiz_id <> new.id then raise exception 'La versión 1 es su propia raíz' using errcode = '22023'; end if;
  else
    select * into v_prev from acta.actas where id = new.version_anterior_id;
    if not found or v_prev.acta_raiz_id <> new.acta_raiz_id or v_prev.version + 1 <> new.version
       or v_prev.consecutivo <> new.consecutivo or v_prev.serie <> new.serie or v_prev.numero <> new.numero then
      raise exception 'La corrección no encadena con la versión anterior' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;


--
-- Name: f_acta_no_cancelada(); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_acta_no_cancelada() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'acta', 'pg_temp'
    AS $$
begin
  if new.version = 1 then
    perform 1 from acta.aperturas where id = new.id for share;
    if exists (select 1 from acta.apertura_eventos e where e.apertura_id = new.id and e.tipo_evento = 'cancelar') then
      perform acta.f_error('Este registro fue cancelado: ya no se puede registrar. Abra uno nuevo desde «Mis actas»', '55000');
    end if;
  end if;
  return new;
end $$;


--
-- Name: f_ahora_bogota(); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_ahora_bogota() RETURNS timestamp without time zone
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog'
    AS $$ select clock_timestamp() at time zone 'America/Bogota' $$;


--
-- Name: f_apertura_cancelada(uuid); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_apertura_cancelada(p_apertura uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'acta', 'pg_temp'
    AS $$ select exists (select 1 from acta.apertura_eventos e where e.apertura_id = p_apertura and e.tipo_evento = 'cancelar') $$;


--
-- Name: f_auditar(text, text, text, jsonb, text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values (lower(p_email), p_accion, p_ref, p_detalle, p_ip);
$$;


--
-- Name: f_autorizar(text, text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_autorizar(p_solicitante text, p_capacidad text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if not coalesce((acta.f_capacidades(v_email) ->> p_capacidad)::boolean, false) then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  return v_email;
end $$;


--
-- Name: f_autorizar_alguna(text, text[]); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_autorizar_alguna(p_solicitante text, p_caps text[]) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text := lower(btrim(coalesce(p_solicitante, ''))); v_c jsonb; k text; v_ok boolean := false;
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  v_c := acta.f_capacidades(v_email);
  foreach k in array p_caps loop if coalesce((v_c ->> k)::boolean, false) then v_ok := true; end if; end loop;
  if not v_ok then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  return v_email;
end $$;


--
-- Name: f_bool(jsonb, text, boolean, boolean); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_bool(p_c jsonb, p_k text, p_req boolean DEFAULT false, p_def boolean DEFAULT false) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog'
    AS $$
declare v jsonb := p_c -> p_k;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    if p_req then perform acta.f_error(format('Falta responder «%s» (sí o no)', p_k)); end if;
    return p_def;
  end if;
  if jsonb_typeof(v) <> 'boolean' then perform acta.f_error(format('El dato «%s» debe ser sí o no', p_k)); end if;
  return (v #>> '{}')::boolean;
end $$;


--
-- Name: f_capacidades(text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_capacidades(p_email text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v text := lower(btrim(coalesce(p_email, ''))); v_admin boolean; v_sup boolean; v_cap boolean;
begin
  if v = '' then return jsonb_build_object('capturar', false, 'supervisar', false, 'administrar', false, 'ver_datos_personales', false, 'descargar', false); end if;
  v_admin := public.geoportal_es_admin(v);
  v_sup := public.geoportal_puede(v, 'dashboard_acta');
  v_cap := public.geoportal_puede(v, 'acta');
  return jsonb_build_object('capturar', v_cap, 'supervisar', v_sup, 'administrar', v_admin,
                            'ver_datos_personales', v_sup,       -- nombres del atendiente y del testigo: solo supervisor y administrador
                            'descargar', v_sup);
end $$;


--
-- Name: f_codigo_inmutable(); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_codigo_inmutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  if new.codigo is distinct from old.codigo then
    raise exception 'El código de % no se puede cambiar: cree uno nuevo y desactive este', tg_table_name using errcode = '55000';
  end if;
  return new;
end $$;


--
-- Name: f_contenido_editable(uuid); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_contenido_editable(p_acta uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'acta', 'pg_temp'
    AS $$
  select jsonb_strip_nulls(jsonb_build_object(
    'modo_identificacion', a.modo_identificacion, 'contrato', a.contrato, 'direccion', a.direccion, 'barrio', a.barrio, 'estrato', a.estrato, 'uso', a.uso,
    'referencia_ubicacion', a.referencia_ubicacion, 'tiene_medidor', a.tiene_medidor, 'medidor_serie', a.medidor_serie, 'marca', a.marca, 'lectura_m3', a.lectura_m3,
    'estado_medidor', (select codigo from acta.estados_medidor where id = a.estado_medidor_id), 'estado_sellos', (select codigo from acta.estados_sellos where id = a.estado_sellos_id),
    'serie_sellos', a.serie_sellos, 'diametro', (select codigo from acta.diametros_acometida where id = a.diametro_id), 'descripcion_hallazgos', a.descripcion_hallazgos,
    'hallazgos', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', t.codigo, 'texto_otro', h.texto_otro)) order by t.orden, t.id), '[]'::jsonb) from acta.acta_hallazgos h join acta.tipos_hallazgo t on t.id = h.tipo_hallazgo_id where h.acta_id = a.id),
    'acciones', (select coalesce(jsonb_agg(jsonb_build_object('codigo', c.codigo, 'detalle', x.detalle) order by c.orden, c.id), '[]'::jsonb) from acta.acta_acciones x join acta.acciones_correctivas c on c.id = x.accion_id where x.acta_id = a.id),
    'nadie_atendio', a.nadie_atendio, 'derechos_informados', a.derechos_informados, 'firmo_operario', a.firmo_operario, 'firmo_atendiente', a.firmo_atendiente, 'se_nego_a_firmar', a.se_nego_a_firmar,
    'atendiente', (select jsonb_strip_nulls(jsonb_build_object('nombre', p.nombre, 'calidad', (select codigo from acta.calidades_atendiente where id = p.calidad_id), 'calidad_texto', p.calidad_texto)) from acta.acta_personas p where p.acta_id = a.id and p.rol = 'atendiente'),
    'testigo', (select jsonb_build_object('nombre', p.nombre) from acta.acta_personas p where p.acta_id = a.id and p.rol = 'testigo'),
    'numero_acta_fisica', a.numero_acta_fisica, 'fecha_acta_fisica', a.fecha_acta_fisica, 'papel_pendiente', a.papel_pendiente,
    'constancia_operario', a.constancia_operario, 'observaciones', a.observaciones))
  from acta.actas a where a.id = p_acta;
$$;


--
-- Name: f_contrato_existe(text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_contrato_existe(p_contrato text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists (select 1 from public.catastro_valledupar c where c.cod_usuario = p_contrato);
$$;


--
-- Name: f_cupo_aperturas(text, text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_cupo_aperturas(p_email text, p_perfil text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'acta', 'pg_temp'
    AS $$
declare v_h numeric := acta.f_param('limite_aperturas_hora') * (case when p_perfil = 'supervisor' then acta.f_param('multiplo_supervisor') else 1 end);
        v_d numeric := acta.f_param('limite_aperturas_dia')  * (case when p_perfil = 'supervisor' then acta.f_param('multiplo_supervisor') else 1 end);
        n integer; v_primero timestamptz;
begin
  if p_perfil = 'admin' then return; end if;
  perform pg_advisory_xact_lock(hashtext('acta_aperturas:' || p_email));
  select count(*), min(abierto_en) into n, v_primero from acta.aperturas where autor = p_email and abierto_en > clock_timestamp() - interval '1 hour';
  if n >= v_h then perform acta.f_error_limite('Alcanzó el máximo de registros por hora. Vuelva a intentarlo en ' || acta.f_texto_espera(v_primero, interval '1 hour')); end if;
  select count(*), min(abierto_en) into n, v_primero from acta.aperturas where autor = p_email and abierto_en > clock_timestamp() - interval '1 day';
  if n >= v_d then perform acta.f_error_limite('Alcanzó el máximo de registros por día. Vuelva a intentarlo mañana'); end if;
end $$;


--
-- Name: f_cupo_lecturas(text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_cupo_lecturas(p_email text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'acta', 'pg_temp'
    AS $$
declare n integer;
begin
  perform pg_advisory_xact_lock(hashtext('acta_lecturas:' || p_email));
  select count(*) into n from acta.accesos_evidencia where autor = p_email and accedido_en > clock_timestamp() - interval '1 minute';
  if n >= acta.f_param('limite_lecturas_minuto') then perform acta.f_error_limite('Está abriendo evidencias muy rápido. Espere un minuto'); end if;
end $$;


--
-- Name: f_cupo_mis_actas(text, text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_cupo_mis_actas(p_email text, p_perfil text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare n integer;
begin
  if p_perfil = 'admin' then return; end if;
  perform pg_advisory_xact_lock(hashtext('acta_mis_actas:' || p_email));
  select count(*) into n from public.geoportal_auditoria where email = p_email and accion = 'acta_mis_actas' and creado_en > clock_timestamp() - interval '1 minute';
  if n >= acta.f_param('limite_mis_actas_minuto') then perform acta.f_error_limite('Está consultando sus actas muy seguido. Espere un minuto'); end if;
end $$;


--
-- Name: f_cupo_precargas(text, text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_cupo_precargas(p_email text, p_perfil text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'acta', 'pg_temp'
    AS $$
declare n integer;
begin
  if p_perfil = 'admin' then return; end if;
  perform pg_advisory_xact_lock(hashtext('acta_precarga:' || p_email));
  select count(*) into n from acta.consultas_contrato where autor = p_email and consultado_en > clock_timestamp() - interval '1 day';
  if n >= acta.f_param('limite_precargas_dia') then perform acta.f_error_limite('Alcanzó el máximo de consultas de contrato del día'); end if;
  select count(*) into n from acta.consultas_contrato where autor = p_email and not existe and consultado_en > clock_timestamp() - interval '1 day';
  if n >= acta.f_param('limite_precargas_falsas_dia') then perform acta.f_error_limite('Demasiadas consultas de contratos que no existen: espere hasta mañana o llame a un administrador'); end if;
end $$;


--
-- Name: f_error(text, text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_error(p_mensaje text, p_codigo text DEFAULT '22023'::text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  raise exception '%', p_mensaje using errcode = p_codigo, hint = 'msg_usuario';
end $$;


--
-- Name: f_error_limite(text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_error_limite(p_mensaje text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  raise exception '%', p_mensaje using errcode = '53400', hint = 'msg_usuario';
end $$;


--
-- Name: f_estado_actual(uuid); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_estado_actual(p_raiz uuid) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'acta', 'pg_temp'
    AS $$
  select (select e.estado_nuevo from acta.caso_eventos e where e.acta_raiz_id = p_raiz and e.estado_nuevo is not null order by e.id desc limit 1);
$$;


--
-- Name: f_evento_apertura_coherente(); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_evento_apertura_coherente() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'acta', 'pg_temp'
    AS $$
declare v_ap acta.aperturas%rowtype; v_m acta.motivos_cancelacion%rowtype;
begin
  select * into v_ap from acta.aperturas where id = new.apertura_id for update;     -- bloquea la fila: serializa con el registro (ver t_acta_no_cancelada)
  if not found then perform acta.f_error('La apertura no existe', 'P0002'); end if;
  if v_ap.correccion_de is not null then perform acta.f_error('Una corrección en curso no se cancela desde aquí', '55000'); end if;
  if exists (select 1 from acta.actas x where x.id = new.apertura_id) then perform acta.f_error('Lo registrado no se cancela: para corregirlo use la corrección de la supervisión', '55000'); end if;
  select * into v_m from acta.motivos_cancelacion where codigo = new.motivo_codigo;
  if not found or not v_m.activo then perform acta.f_error('El motivo no existe o está desactivado'); end if;
  if v_m.exige_texto and (new.motivo_texto is null or length(btrim(new.motivo_texto)) < 10) then perform acta.f_error('Escriba el motivo (de 10 a 1.000 caracteres)'); end if;
  return new;
end $$;


--
-- Name: f_evento_coherente(); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_evento_coherente() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'acta', 'pg_temp'
    AS $$
declare v_est acta.estados_caso%rowtype; v_act text;
begin
  if new.tipo_evento = 'cambio_estado' then
    select * into v_est from acta.estados_caso where codigo = new.estado_nuevo;
    if not v_est.activo then raise exception 'El estado % está desactivado', new.estado_nuevo using errcode = '22023'; end if;
    v_act := acta.f_estado_actual(new.acta_raiz_id);
    if v_act is null then
      if new.autor <> 'sistema' or not (v_est.inicial or v_est.inicial_sin_irregularidad) then
        raise exception 'El primer estado del caso lo pone el sistema al registrar' using errcode = '22023';
      end if;
    else
      if new.autor = 'sistema' then raise exception 'El sistema solo pone el estado inicial' using errcode = '22023'; end if;
      if not v_est.cambio_manual then raise exception 'El estado % no se puede poner a mano', new.estado_nuevo using errcode = '22023'; end if;
      if not exists (select 1 from acta.transiciones_caso t where t.desde = v_act and t.hasta = new.estado_nuevo and t.activo) then
        raise exception 'No se permite pasar de % a %', v_act, new.estado_nuevo using errcode = '22023';
      end if;
      if v_est.exige_motivo and new.motivo is null then raise exception 'El estado % exige un motivo', new.estado_nuevo using errcode = '22023'; end if;
    end if;
  end if;
  return new;
end $$;


--
-- Name: f_exigir_caso(uuid); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_exigir_caso(p_raiz uuid) RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'acta', 'pg_temp'
    AS $$
begin
  if p_raiz is null or not exists (select 1 from acta.actas where id = p_raiz and version = 1) then perform acta.f_error('El caso no existe', 'P0002'); end if;
end $$;


--
-- Name: f_hoy_bogota(); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_hoy_bogota() RETURNS date
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog'
    AS $$ select (clock_timestamp() at time zone 'America/Bogota')::date $$;


--
-- Name: f_motivo(text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_motivo(p_motivo text) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog'
    AS $$
declare m text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if m is null or length(m) < 10 or length(m) > 1000 then perform acta.f_error('Escriba el motivo (de 10 a 1.000 caracteres)'); end if;
  return m;
end $$;


--
-- Name: f_num(jsonb, text, numeric, numeric); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_num(p_c jsonb, p_k text, p_min numeric, p_max numeric) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog'
    AS $$
declare v jsonb := p_c -> p_k; n numeric;
begin
  if v is null or jsonb_typeof(v) = 'null' then return null; end if;
  if jsonb_typeof(v) <> 'number' then perform acta.f_error(format('El dato «%s» debe ser un número', p_k)); end if;
  n := (v #>> '{}')::numeric;
  if n < p_min or n > p_max then perform acta.f_error(format('El dato «%s» está fuera del rango permitido', p_k)); end if;
  return n;
end $$;


--
-- Name: f_oculto(uuid); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_oculto(p_raiz uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'acta', 'pg_temp'
    AS $$
  select coalesce((select e.tipo_evento = 'ocultar' from acta.caso_eventos e
                    where e.acta_raiz_id = p_raiz and e.tipo_evento in ('ocultar', 'reincluir') order by e.id desc limit 1), false);
$$;


--
-- Name: f_param(text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_param(p_clave text) RETURNS numeric
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'acta', 'pg_temp'
    AS $$
declare v numeric; v_hay boolean;
begin
  select valor, true into v, v_hay from acta.parametros where clave = p_clave;
  if v_hay is null or v is null then raise exception 'Falta el parámetro de acta %', p_clave using errcode = 'P0002'; end if;
  return v;
end $$;


--
-- Name: f_perfil(text); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_perfil(p_email text) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare c jsonb := acta.f_capacidades(p_email);
begin
  if (c ->> 'administrar')::boolean then return 'admin'; end if;
  if (c ->> 'supervisar')::boolean then return 'supervisor'; end if;
  if (c ->> 'capturar')::boolean then return 'captura'; end if;
  return null;
end $$;


--
-- Name: f_sello(uuid); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_sello(p_acta uuid) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'acta', 'pg_catalog', 'pg_temp'
    SET "TimeZone" TO 'UTC'
    AS $$
declare v_a acta.actas%rowtype; v_canon jsonb;
begin
  select * into v_a from acta.actas where id = p_acta;
  if not found then return null; end if;
  v_canon := jsonb_build_object(
    'esquema', v_a.esquema_version,
    'acta', to_jsonb(v_a) - 'geom' - 'seq',
    'hallazgos', coalesce((select jsonb_agg(jsonb_build_object('c', t.codigo, 'o', h.texto_otro) order by t.codigo)
                             from acta.acta_hallazgos h join acta.tipos_hallazgo t on t.id = h.tipo_hallazgo_id where h.acta_id = p_acta), '[]'::jsonb),
    'acciones',  coalesce((select jsonb_agg(jsonb_build_object('c', c.codigo, 'd', x.detalle) order by c.codigo)
                             from acta.acta_acciones x join acta.acciones_correctivas c on c.id = x.accion_id where x.acta_id = p_acta), '[]'::jsonb),
    'personas',  coalesce((select jsonb_agg(to_jsonb(p) - 'id' - 'acta_id' order by p.rol) from acta.acta_personas p where p.acta_id = p_acta), '[]'::jsonb),
    'fotos',     coalesce((select jsonb_agg(jsonb_build_object('n', f.orden, 't', tf.codigo, 'r', f.ruta_storage, 'h', f.sha256, 'b', f.tamano_bytes, 'd', f.detalle) order by f.orden)
                             from acta.acta_fotos f join acta.tipos_foto tf on tf.id = f.tipo_foto_id where f.acta_id = p_acta and not f.posterior), '[]'::jsonb));
  return encode(sha256(convert_to(v_canon::text, 'UTF8')), 'hex');
end $$;


--
-- Name: f_solo_agregar(); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_solo_agregar() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  raise exception 'Tabla de solo agregar: % no permitido en %.%', tg_op, tg_table_schema, tg_table_name using errcode = '42501';
end $$;


--
-- Name: f_texto_espera(timestamp with time zone, interval); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_texto_espera(p_primero timestamp with time zone, p_ventana interval) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select case when m <= 1 then 'menos de un minuto' else m || ' minutos' end
    from (select greatest(1, ceil(extract(epoch from (p_primero + p_ventana - clock_timestamp())) / 60.0))::integer as m) x;
$$;


--
-- Name: f_txt(jsonb, text, integer, boolean); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_txt(p_c jsonb, p_k text, p_max integer, p_req boolean DEFAULT false) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog'
    AS $$
declare v jsonb := p_c -> p_k; t text;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    if p_req then perform acta.f_error(format('Falta el dato «%s»', p_k)); end if;
    return null;
  end if;
  if jsonb_typeof(v) <> 'string' then perform acta.f_error(format('El dato «%s» debe ser texto', p_k)); end if;
  t := nullif(btrim(v #>> '{}'), '');
  if t is null and p_req then perform acta.f_error(format('Falta el dato «%s»', p_k)); end if;
  if length(coalesce(t, '')) > p_max then perform acta.f_error(format('El dato «%s» es demasiado largo (máximo %s caracteres)', p_k, p_max)); end if;
  return t;
end $$;


--
-- Name: f_validar_detalle(text, jsonb, jsonb); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_validar_detalle(p_accion text, p_campos jsonb, p_detalle jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog'
    AS $_$
declare c jsonb; k text; v jsonb; r jsonb := '{}'::jsonb; t text;
begin
  p_detalle := coalesce(p_detalle, '{}'::jsonb);
  if jsonb_typeof(p_detalle) <> 'object' then perform acta.f_error(format('El detalle de la acción «%s» no tiene el formato esperado', p_accion)); end if;
  for k in select jsonb_object_keys(p_detalle) loop
    if not exists (select 1 from jsonb_array_elements(p_campos) e where e ->> 'clave' = k) then
      perform acta.f_error(format('La acción «%s» no tiene el campo «%s»', p_accion, k));
    end if;
  end loop;
  for c in select e from jsonb_array_elements(p_campos) e loop
    k := c ->> 'clave'; v := p_detalle -> k; t := c ->> 'tipo';
    if v is null or jsonb_typeof(v) = 'null' or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then
      if coalesce((c ->> 'obligatorio')::boolean, false) then perform acta.f_error(format('En la acción «%s» falta «%s»', p_accion, coalesce(c ->> 'etiqueta', k))); end if;
      continue;
    end if;
    if t = 'numero' then
      if jsonb_typeof(v) <> 'number' then perform acta.f_error(format('En la acción «%s», «%s» debe ser un número', p_accion, coalesce(c ->> 'etiqueta', k))); end if;
      r := r || jsonb_build_object(k, v);
    elsif t = 'hora' then
      if jsonb_typeof(v) <> 'string' or (v #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        perform acta.f_error(format('En la acción «%s», «%s» debe ser una hora HH:MM', p_accion, coalesce(c ->> 'etiqueta', k)));
      end if;
      r := r || jsonb_build_object(k, v);
    else   -- texto
      if jsonb_typeof(v) <> 'string' or length(btrim(v #>> '{}')) > 300 then
        perform acta.f_error(format('En la acción «%s», «%s» debe ser un texto de hasta 300 caracteres', p_accion, coalesce(c ->> 'etiqueta', k)));
      end if;
      r := r || jsonb_build_object(k, to_jsonb(btrim(v #>> '{}')));
    end if;
  end loop;
  return r;
end $_$;


--
-- Name: f_vigente(uuid); Type: FUNCTION; Schema: acta; Owner: -
--

CREATE FUNCTION acta.f_vigente(p_raiz uuid) RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path TO 'acta', 'pg_temp'
    AS $$
  select a.id from acta.actas a where a.acta_raiz_id = p_raiz order by a.version desc limit 1;
$$;


--
-- Name: f_num(text); Type: FUNCTION; Schema: bi; Owner: -
--

CREATE FUNCTION bi.f_num(t text) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case
    when t is null or btrim(t) = '' then null
    when lower(btrim(t)) in ('nan', 'none', 'null') then null
    -- '1,234,567.89' -> coma como separador de miles
    when btrim(t) ~ '^-?\d{1,3}(,\d{3})+(\.\d+)?$'
      then replace(btrim(t), ',', '')::numeric
    -- '123,45' -> coma como decimal
    when btrim(t) ~ '^-?\d+,\d+$'
      then replace(btrim(t), ',', '.')::numeric
    -- '111579.0', '-5.2', '1e+16': cast directo solo si el patrón es
    -- numérico estricto ('NaN'/'Infinity' no calzan: jamás se devuelven)
    when btrim(t) ~ '^-?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$'
      then btrim(t)::numeric
    else null
  end
$_$;


--
-- Name: recalcular(text, text); Type: FUNCTION; Schema: bi; Owner: -
--

CREATE FUNCTION bi.recalcular(p_tabla text, p_periodo text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare n integer;
begin
  if    p_tabla = 'bi.v_fact_detalle_dim'      then n := bi.recalcular_fact_detalle_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_diario_cierre' then n := bi.recalcular_recaudo_diario_cierre(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_detalle_dim'   then n := bi.recalcular_recaudo_detalle_dim(p_periodo);
  elsif p_tabla = 'bi.v_cartera_detalle_dim'   then n := bi.recalcular_cartera_detalle_dim(p_periodo);
  elsif p_tabla = 'bi.v_cartera_contratos_dim' then n := bi.recalcular_cartera_contratos_dim(p_periodo);
  elsif p_tabla = 'bi.v_cupones_mes_dim'       then n := bi.recalcular_cupones_mes_dim(p_periodo);
  elsif p_tabla = 'bi.v_notas_mes_dim'         then n := bi.recalcular_notas_mes_dim(p_periodo);
  elsif p_tabla = 'bi.v_consumo_ciclo_dim'     then n := bi.recalcular_consumo_ciclo_dim(p_periodo);
  elsif p_tabla = 'bi.v_desviacion_dim'        then n := bi.recalcular_desviacion_dim(p_periodo);
  elsif p_tabla = 'bi.v_lectura_ciclo_dim'     then n := bi.recalcular_lectura_ciclo_dim(p_periodo);
  elsif p_tabla = 'bi.v_observacion_dim'       then n := bi.recalcular_observacion_dim(p_periodo);
  elsif p_tabla = 'bi.v_medidor_antig_dim'     then n := bi.recalcular_medidor_antig_dim(p_periodo);
  elsif p_tabla = 'bi.v_consumo_rango_dim'     then n := bi.recalcular_consumo_rango_dim(p_periodo);
  elsif p_tabla = 'bi.v_consumo_basico_dim'    then n := bi.recalcular_consumo_basico_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_eficiencia_dim' then n := bi.recalcular_recaudo_eficiencia_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_ritmo_dim' then n := bi.recalcular_recaudo_ritmo_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_edad_dim' then n := bi.recalcular_recaudo_edad_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_subsidio_dim' then n := bi.recalcular_recaudo_subsidio_dim(p_periodo);
  elsif p_tabla = 'bi.v_notas_causal_dim' then n := bi.recalcular_notas_causal_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_entidad_dim' then n := bi.recalcular_recaudo_entidad_dim(p_periodo);
  elsif p_tabla = 'bi.v_cambio_medidor_dim' then n := bi.recalcular_cambio_medidor(p_periodo);
  elsif p_tabla in ('bi.v_submedicion_ref_dim', 'bi.v_submedicion_ciclo_dim', 'bi.v_submedicion_rango_dim') then n := bi.recalcular_submedicion(p_periodo);
  elsif p_tabla = 'bi.v_reclamo_metodo_dim' then n := bi.recalcular_reclamo_metodo(p_periodo);
  elsif p_tabla in ('bi.v_reclamo_metodo_banda_dim', 'bi.v_reclamo_metodo_ciclo_dim') then n := bi.recalcular_reclamo_metodo_resumen(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_ticket_dim' then n := bi.recalcular_recaudo_ticket_dim(p_periodo);
  elsif p_tabla = 'bi.v_recaudo_cuadre_dim' then n := bi.recalcular_recaudo_cuadre_dim(p_periodo);
  elsif p_tabla in ('bi.v_mapa_calor_dim', 'bi.v_mapa_calor_cobertura_dim', 'bi.v_mapa_calor_cartera_dim') then n := bi.recalcular_mapa_calor(p_periodo);
  elsif p_tabla = 'bi.v_cartera_edad_dim' then n := bi.recalcular_cartera_edad(p_periodo);
  elsif p_tabla = 'bi.v_cartera_pago_dim' then n := bi.recalcular_cartera_pago(p_periodo);
  elsif p_tabla = 'bi.v_cartera_transicion_dim' then n := bi.recalcular_cartera_transicion(p_periodo);
  elsif p_tabla = 'bi.v_emd_dim' then n := bi.recalcular_emd(p_periodo);
  elsif p_tabla = 'bi.v_cartera_concepto_dim' then n := bi.recalcular_cartera_concepto(p_periodo);
  elsif p_tabla = 'bi_interno.cartera_mapa_contrato' then n := bi.recalcular_cartera_mapa(p_periodo);
  elsif p_tabla = 'bi_interno.ficha_contrato' then n := bi.recalcular_ficha_contrato(p_periodo);
  elsif p_tabla = 'bi.v_consumo_promedio_dim' then n := bi.recalcular_consumo_promedio(p_periodo);
  else raise exception 'tabla_no_recalculable: %', p_tabla using errcode = 'P0001';
  end if;

  -- Períodos que ya no existen en la fuente (borrados por retención).
  if p_tabla = 'bi.v_fact_detalle_dim' then
    delete from bi.v_fact_detalle_dim t
    where not exists (select 1 from hechos.facturacion_contratos f where f.periodo = t.periodo);
  elsif p_tabla in ('bi.v_recaudo_diario_cierre', 'bi.v_recaudo_detalle_dim') then
    execute format(
      'delete from %s t where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo)',
      p_tabla);
  elsif p_tabla = 'bi.v_cartera_detalle_dim' then
    delete from bi.v_cartera_detalle_dim t
    where not exists (select 1 from hechos.cartera_edades f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cartera_contratos_dim' then
    delete from bi.v_cartera_contratos_dim t
    where not exists (select 1 from hechos.cartera_contrato f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cupones_mes_dim' then
    delete from bi.v_cupones_mes_dim t
    where not exists (select 1 from hechos.cupones_pagos f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_notas_mes_dim' then
    delete from bi.v_notas_mes_dim t
    where not exists (select 1 from hechos.notas f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_consumo_ciclo_dim' then
    delete from bi.v_consumo_ciclo_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_desviacion_dim' then
    delete from bi.v_desviacion_dim t
    where not exists (select 1 from hechos.facturacion_contratos f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_lectura_ciclo_dim' then
    delete from bi.v_lectura_ciclo_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_observacion_dim' then
    delete from bi.v_observacion_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_medidor_antig_dim' then
    delete from bi.v_medidor_antig_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_consumo_rango_dim' then
    delete from bi.v_consumo_rango_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_consumo_basico_dim' then
    delete from bi.v_consumo_basico_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_eficiencia_dim' then
    delete from bi.v_recaudo_eficiencia_dim t
    where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_ritmo_dim' then
    delete from bi.v_recaudo_ritmo_dim t
    where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_edad_dim' then
    delete from bi.v_recaudo_edad_dim t
    where not exists (select 1 from hechos.recaudo_agrupado f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_subsidio_dim' then
    delete from bi.v_recaudo_subsidio_dim t
    where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_notas_causal_dim' then
    delete from bi.v_notas_causal_dim t
    where not exists (select 1 from hechos.notas f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_entidad_dim' then
    delete from bi.v_recaudo_entidad_dim t
    where not exists (select 1 from hechos.cupones_pagos f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_ticket_dim' then
    delete from bi.v_recaudo_ticket_dim t
    where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_recaudo_cuadre_dim' then
    delete from bi.v_recaudo_cuadre_dim t
    where not exists (select 1 from hechos.recaudo_detalle f where f.periodo = t.periodo)
      and not exists (select 1 from hechos.cupones_pagos f where f.periodo = t.periodo)
      and not exists (select 1 from hechos.recaudo_agrupado f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cambio_medidor_dim' then
    delete from bi.v_cambio_medidor_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla in ('bi.v_submedicion_ref_dim', 'bi.v_submedicion_ciclo_dim', 'bi.v_submedicion_rango_dim') then
    delete from bi.v_submedicion_ref_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
    delete from bi.v_submedicion_ciclo_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
    delete from bi.v_submedicion_rango_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_reclamo_metodo_dim' then
    delete from bi.v_reclamo_metodo_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla in ('bi.v_reclamo_metodo_banda_dim', 'bi.v_reclamo_metodo_ciclo_dim') then
    delete from bi.v_reclamo_metodo_banda_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
    delete from bi.v_reclamo_metodo_ciclo_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla in ('bi.v_mapa_calor_dim', 'bi.v_mapa_calor_cobertura_dim', 'bi.v_mapa_calor_cartera_dim') then
    delete from bi.v_mapa_calor_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
    delete from bi.v_mapa_calor_cobertura_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
    delete from bi.v_mapa_calor_cartera_dim t
    where not exists (select 1 from hechos.consumo_metodo f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cartera_edad_dim' then
    delete from bi.v_cartera_edad_dim t
    where not exists (select 1 from hechos.cartera_edades f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cartera_pago_dim' then
    delete from bi.v_cartera_pago_dim t
    where not exists (select 1 from hechos.cartera_contrato f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cartera_transicion_dim' then
    delete from bi.v_cartera_transicion_dim t
    where not exists (select 1 from hechos.cartera_contrato f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_emd_dim' then
    delete from bi.v_emd_dim t
    where not exists (select 1 from hechos.facturacion_contratos f where f.periodo = t.periodo);
  elsif p_tabla = 'bi.v_cartera_concepto_dim' then
    delete from bi.v_cartera_concepto_dim t
    where not exists (select 1 from hechos.cartera_edades f where f.periodo = t.periodo);
  elsif p_tabla = 'bi_interno.cartera_mapa_contrato' then
    -- Limpieza de huerfanos de UN solo recorrido: los periodos vivos de la fuente se leen una vez (salto de periodo en periodo por el indice) y las tres
    -- tablas se limpian contra esa lista; sin subconsulta correlacionada fila por fila (la v1 con NOT EXISTS vencia el statement_timeout).
    declare vivos text[];
    begin
      with recursive p(periodo) as (
        select min(periodo) from hechos.cartera_contrato
        union all
        select (select min(periodo) from hechos.cartera_contrato where periodo > p.periodo) from p where p.periodo is not null)
      select coalesce(array_agg(periodo), '{}'::text[]) into vivos from p where periodo is not null;
      delete from bi_interno.cartera_mapa_contrato where periodo <> all (vivos);
      delete from bi_interno.cartera_mapa_barrio   where periodo <> all (vivos);
      delete from bi_interno.cartera_mapa_periodo  where periodo <> all (vivos);
    end;
  end if;

  return n;
end $$;


--
-- Name: recalcular_cambio_medidor(text); Type: FUNCTION; Schema: bi; Owner: -
--

CREATE FUNCTION bi.recalcular_cambio_medidor(p_periodo text) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
declare
  n          integer;
  v_ant      text;
  v_cierre   date;
  v_meses    integer;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);
  perform set_config('enable_nestloop', 'off', true);
  delete from bi.v_cambio_medidor_dim where periodo = p_periodo;
  if not exists (select 1 from hechos.consumo_metodo where periodo = p_periodo) then
    return 0;
  end if;
  select max(periodo) into v_ant from hechos.consumo_metodo where periodo < p_periodo;
  if v_ant is null then
    return 0;   -- sin periodo anterior no hay con que comparar (0 filas es lo correcto)
  end if;
  v_cierre := (to_date(v_ant || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date;
  v_meses  := (substr(p_periodo, 1, 4)::int * 12 + substr(p_periodo, 5, 2)::int)
            - (substr(v_ant, 1, 4)::int * 12 + substr(v_ant, 5, 2)::int);

  insert into bi.v_cambio_medidor_dim
  with r as materialized (
    select p.periodo, p.contrato,
           coalesce(nullif(btrim(p.ciclo), ''), '(sin ciclo)') as ciclo,
           case when btrim(coalesce(regexp_replace(btrim(p.categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(p.categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(p.categoria),'^-?\d+\s+','')) end as uso,
           case when btrim(coalesce(regexp_replace(btrim(p.subcategoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(p.subcategoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(p.subcategoria),'^-?\d+\s+','')) end as estrato,
           (nullif(btrim(p.medidor), '') is not null
            and upper(btrim(p.medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_med,
           upper(btrim(p.medidor)) as serial,
           substring(upper(btrim(p.observacion)) from '^(\d+)\s')::int as cod,
           upper(btrim(p.funcion)) as fn,
           case when p.fecha_instalacion ~ '^\d{4}-\d{2}-\d{2}' then left(p.fecha_instalacion, 10)::date end as fi,
           bi.f_num(p.consumo_facturado) as cf,
           case when btrim(p.lectura_anterior) ~ '^[0-9]+(\.[0-9]+)?$' then btrim(p.lectura_anterior)::numeric end as la,
           case when btrim(p.lectura_actual)   ~ '^[0-9]+(\.[0-9]+)?$' then btrim(p.lectura_actual)::numeric end as lc
    from (
      select distinct on (periodo, contrato) *
      from hechos.consumo_metodo
      where periodo in (p_periodo, v_ant)
      order by periodo, contrato,
               (nullif(btrim(medidor), '') is not null) desc,
               (bi.f_num(lectura_actual) is not null) desc,
               bi.f_num(consumo_cargos) desc nulls last,
               categoria, subcategoria, observacion) p),
  u as materialized (
    select r.*,
           case when r.fn ~ '^CALCCODL' and r.cod = 99 then 'lectura'
                when r.fn ~ '^(\[FAMC\]\s*-\s*)?OBTECOP[PS]' then 'promedio'
                else 'otro' end as metodo
    from r),
  j as (
    select b.ciclo, b.uso, b.estrato,
           case when a.con_med and b.con_med then
                  (case when a.serial = b.serial then 'sin_cambio'
                        when b.la is not null and a.lc is not null and b.la < a.lc and b.la <= 10 then 'reposicion_confirmada'
                        when v_meses > 1 then 'no_concluyente'
                        when b.la is null or a.lc is null then 'reposicion_sin_lectura'
                        when b.la = a.lc then 'cambio_serial_continuo'
                        when b.la < a.lc then 'cambio_serial_retroceso'
                        else 'cambio_serial_lectura_mayor' end)
                when not a.con_med and b.con_med then 'instalacion_nueva'
                when a.con_med and not b.con_med then 'retiro' end as tipo_evento,
           case when not a.con_med then 'Sin medidor'
                when a.fi is null or a.fi > v_cierre then 'Sin fecha'
                when extract(year from age(v_cierre, a.fi)) < 5  then '0-5'
                when extract(year from age(v_cierre, a.fi)) < 10 then '5-10'
                when extract(year from age(v_cierre, a.fi)) < 15 then '10-15'
                when a.fi = date '1986-01-01' then '>15 (1986-01-01)'
                else '>15 (fecha real)' end as banda_ant,
           b.metodo as metodo_act,
           (a.metodo = 'lectura' and b.metodo = 'lectura' and a.cf is not null and b.cf is not null) as pareado,
           a.cf as cf_ant, b.cf as cf_act, a.con_med as con_med_ant
    from u b join u a on a.contrato = b.contrato and a.periodo = v_ant
    where b.periodo = p_periodo)
  select p_periodo, v_ant, v_meses, ciclo, uso, estrato, tipo_evento, banda_ant, metodo_act,
         count(*),
         count(*) filter (where pareado),
         sum(cf_ant) filter (where pareado),
         sum(cf_act) filter (where pareado),
         count(*) filter (where con_med_ant)
  from j
  where tipo_evento is not null
  group by ciclo, uso, estrato, tipo_evento, banda_ant, metodo_act;
  get diagnostics n = row_count;
  return n;
end $_$;


--
-- Name: recalcular_consumo_promedio(text); Type: FUNCTION; Schema: bi; Owner: -
--

CREATE FUNCTION bi.recalcular_consumo_promedio(p_periodo text) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO 'public', 'bi', 'bi_interno', 'hechos', 'pg_temp'
    AS $$
declare n integer;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);
  delete from bi.v_consumo_promedio_dim where periodo = p_periodo
     or periodo not in (select distinct periodo from hechos.consumo_metodo);   -- periodos que la retención ya borró
  if not exists (select 1 from hechos.consumo_metodo where periodo = p_periodo) then
    return 0;
  end if;
  insert into bi.v_consumo_promedio_dim (periodo, dimension, grupo, contratos, media_m3, mediana_m3)
  with r as materialized (
    select distinct on (contrato) btrim(contrato) as contrato,
           bi_interno.f_sin_prefijo(categoria) as uso,
           bi_interno.f_sin_prefijo(subcategoria) as estrato,
           (nullif(btrim(medidor), '') is not null and upper(btrim(medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_med,
           substring(upper(btrim(observacion)) from '^(\d+)\s')::int as cod,
           upper(btrim(funcion)) as fn,
           bi.f_num(consumo_cargos) as cc
    from hechos.consumo_metodo
    where periodo = p_periodo
    order by contrato, (nullif(btrim(medidor), '') is not null) desc, (bi.f_num(lectura_actual) is not null) desc,
             bi.f_num(consumo_cargos) desc nulls last, categoria, subcategoria, observacion),
  u as materialized (
    select r.*, nullif(upper(btrim(cs.barrio)), '') as barrio
    from r left join lateral (select s.barrio from public.cartera_suscripcion s where s.contrato = r.contrato limit 1) cs on true
    where r.cod = 99 and r.fn ~ '^CALCCODL' and r.con_med and r.cc > 0 and r.cc <= 100),
  g as (
    select 'estrato' as dimension, estrato as grupo, cc from u where estrato <> '(sin dato)'
    union all select 'uso', uso, cc from u where uso <> '(sin dato)'
    union all select 'barrio', barrio, cc from u where barrio is not null)
  select p_periodo, dimension, grupo, count(*)::int, round(avg(cc), 2), round(percentile_cont(0.5) within group (order by cc)::numeric, 2)
  from g group by dimension, grupo having count(*) >= 30;
  get diagnostics n = row_count;
  return n;
end $$;


--
-- Name: recalcular_ficha_contrato(text); Type: FUNCTION; Schema: bi; Owner: -
--

CREATE FUNCTION bi.recalcular_ficha_contrato(p_periodo text) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO 'public', 'bi', 'bi_interno', 'hechos', 'pg_temp'
    AS $_$
declare
  v_t0     timestamptz := clock_timestamp();
  v_ult    text;
  v_ini    text;
  v_cierre date;
  v_ps     text;
  v_cps    date;
  v_firma  text;
  v_cc     text;
  v_cp     text;
  n        integer;
  e        record;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);
  perform set_config('enable_nestloop', 'off', true);
  select max(periodo) into v_ult from hechos.consumo_metodo;
  if v_ult is null then return 0; end if;
  select max(periodo) into v_cc from hechos.cartera_contrato;
  select max(periodo) into v_cp from hechos.cupones_pagos;
  select max(periodo) into v_ps from bi.v_submedicion_ref_dim;
  v_firma := concat_ws('|', 'cm', v_ult, (select count(*) from hechos.consumo_metodo where periodo = v_ult),
                       'cc', v_cc, (select count(*) from hechos.cartera_contrato where periodo = v_cc),
                       'cp', v_cp, (select count(*) from hechos.cupones_pagos where periodo = v_cp),
                       're', (select max(periodo) from hechos.reclamos), 'fc', (select max(periodo) from hechos.facturacion_contratos), 'sm', v_ps);
  select * into e from bi_interno.ficha_contrato_estado where id = 1;
  if found and e.firma = v_firma and e.calculado_en > clock_timestamp() - interval '2 hours' then
    return e.filas;
  end if;

  v_cierre := (to_date(v_ult || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date;
  v_ini := to_char(to_date(v_ult || '01', 'YYYYMMDD') - interval '5 months', 'YYYYMM');
  v_cps := case when v_ps is not null then (to_date(v_ps || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date end;

  -- 1. consumo de la ventana: UNA fila por contrato y periodo, con la misma elección de bi.recalcular_submedicion
  create temp table t_cm on commit drop as
  select distinct on (periodo, btrim(contrato)) periodo, btrim(contrato) as contrato,
         nullif(btrim(ciclo), '') as ciclo,
         bi_interno.f_sin_prefijo(categoria) as uso,
         bi_interno.f_sin_prefijo(subcategoria) as estrato,
         (nullif(btrim(medidor), '') is not null and upper(btrim(medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_med,
         upper(btrim(medidor)) as serial,
         substring(upper(btrim(observacion)) from '^(\d+)\s')::int as cod,
         nullif(btrim(observacion), '') as observacion,
         upper(btrim(funcion)) as fn,
         case when fecha_instalacion ~ '^\d{4}-\d{2}-\d{2}' then bi_interno.f_fecha_texto(fecha_instalacion) end as fi,
         bi.f_num(consumo_cargos) as cc,
         case when btrim(lectura_anterior) ~ '^[0-9]+(\.[0-9]+)?$' then btrim(lectura_anterior)::numeric end as la,
         case when btrim(lectura_actual)   ~ '^[0-9]+(\.[0-9]+)?$' then btrim(lectura_actual)::numeric end as lc
  from hechos.consumo_metodo
  where periodo between v_ini and v_ult
  order by periodo, btrim(contrato), (nullif(btrim(medidor), '') is not null) desc, (bi.f_num(lectura_actual) is not null) desc,
           bi.f_num(consumo_cargos) desc nulls last, categoria, subcategoria, observacion;
  create index on t_cm (contrato, periodo);
  analyze t_cm;

  -- meses calendario de la ventana (6) y periodos que SÍ existen en la fuente (un hueco como 202606 queda «sin dato», no se inventa)
  create temp table t_mes on commit drop as
  select to_char(to_date(v_ini || '01', 'YYYYMMDD') + make_interval(months => k), 'YYYYMM') as periodo, k
  from generate_series(0, 5) k;
  create temp table t_par on commit drop as      -- pares (periodo, anterior disponible en la fuente) para detectar cambios de serial
  select p.periodo, lag(p.periodo) over (order by p.periodo) as ant
  from (select distinct periodo from t_cm) p;

  -- 2. la fila más reciente de cada contrato en la ventana
  create temp table t_u on commit drop as
  select distinct on (contrato) * from t_cm order by contrato, periodo desc;
  create index on t_u (contrato);

  -- 3. fecha de instalación de respaldo y facturas vencidas: cartera_contrato del último periodo
  create temp table t_cc on commit drop as
  select btrim(contrato) as contrato,
         max(case when btrim(facturas_vencidas) ~ '^[0-9]+$' then btrim(facturas_vencidas)::int end) as fv,
         max(bi_interno.f_fecha_texto(fecha_instalacion)) as fi,
         (array_agg(jsonb_build_object('fecha', bi_interno.f_fecha_texto(fecha_ult_pago), 'valor', bi.f_num(ultimo_pago))
                    order by bi_interno.f_fecha_texto(fecha_ult_pago) desc nulls last))[1] as pago
  from hechos.cartera_contrato where periodo = v_cc
  group by btrim(contrato);
  create index on t_cc (contrato);

  -- 4. último pago por cupones (todos los periodos retenidos): la fecha más reciente y la suma de ese día
  create temp table t_cp on commit drop as
  select contrato, fecha, valor from (
    select btrim(contrato) as contrato, bi_interno.f_fecha_texto(fecha_pago) as fecha, sum(coalesce(bi.f_num(valor), 0)) as valor,
           row_number() over (partition by btrim(contrato) order by bi_interno.f_fecha_texto(fecha_pago) desc) as k
    from hechos.cupones_pagos
    where nullif(btrim(contrato), '') is not null and bi_interno.f_fecha_texto(fecha_pago) is not null
    group by 1, 2) x where k = 1;
  create index on t_cp (contrato);

  -- 5. EMD facturados (corte, suspensión, reinstalación, corte drástico, reconexión): el último periodo de cada concepto
  create temp table t_emd on commit drop as
  select contrato, jsonb_agg(jsonb_build_object('codigo', codigo, 'concepto', concepto, 'periodo', periodo) order by periodo desc, codigo) as emd
  from (select btrim(contrato) as contrato, split_part(btrim(concepto), '-', 1) as codigo, max(btrim(concepto)) as concepto, max(periodo) as periodo
        from hechos.facturacion_contratos
        where btrim(concepto) ~ '^[0-9]+- EMD '
        group by 1, 2) x
  group by contrato;
  create index on t_emd (contrato);

  -- 6. PQR: la versión más reciente de cada solicitud; por contrato, la última, las abiertas («Registrado») y las de los últimos 12 meses
  create temp table t_pqr on commit drop as
  with s as (
    select distinct on (btrim(contrato), coalesce(nullif(btrim(solicitud), ''), periodo || ':' || ctid::text))
           btrim(contrato) as contrato, nullif(btrim(solicitud), '') as solicitud, bi_interno.f_fecha_texto(fecha_registro) as fecha,
           nullif(btrim(causal), '') as causal, nullif(btrim(estado), '') as estado
    from hechos.reclamos
    where nullif(btrim(contrato), '') is not null
    order by btrim(contrato), coalesce(nullif(btrim(solicitud), ''), periodo || ':' || ctid::text), periodo desc)
  select contrato,
         jsonb_build_object(
           'ultima', (array_agg(jsonb_build_object('solicitud', solicitud, 'fecha', fecha, 'causal', causal, 'estado', estado,
                                                   'abierta', coalesce(upper(estado) like '%REGISTRAD%', false)) order by fecha desc nulls last))[1],
           'abiertas', count(*) filter (where upper(coalesce(estado, '')) like '%REGISTRAD%'),
           'ultimos_12_meses', count(*) filter (where fecha > v_cierre - interval '12 months'),
           'total', count(*)) as pqr
  from s group by contrato;
  create index on t_pqr (contrato);

  -- 7. referencia de submedición de cada estrato en el último periodo calculado (misma tabla que el Tablero)
  create temp table t_ref on commit drop as
  select estrato, max(ref_nuevos_media_m3) as ref, max(n_nuevos) as n_nuevos
  from bi.v_submedicion_ref_dim where periodo = v_ps group by estrato;

  -- 8. armar y reemplazar (DELETE + INSERT en la misma transacción: quien lee en ese momento ve la ficha anterior completa)
  create temp table t_f on commit drop as
  select u.contrato, v_ult as periodo_ultimo, u.uso, u.estrato, u.ciclo,
         (select jsonb_agg(jsonb_build_object(
                    'periodo', m.periodo, 'sin_dato', c.contrato is null, 'm3', c.cc,
                    'metodo', case when c.contrato is null then null when c.fn ~ '^CALCCODL' and c.cod = 99 then 'lectura' when c.fn ~ '^(\[FAMC\]\s*-\s*)?OBTECOP[PS]' then 'promedio' else 'otro' end,
                    'lectura_real', coalesce(c.fn ~ '^CALCCODL' and c.cod = 99, false),
                    'causal', c.observacion) order by m.k)
            from t_mes m left join t_cm c on c.contrato = u.contrato and c.periodo = m.periodo) as consumo_meses,
         (select max(c.cc) from t_cm c where c.contrato = u.contrato and c.cod = 99 and c.fn ~ '^CALCCODL') as cons_max,
         (select min(c.cc) from t_cm c where c.contrato = u.contrato and c.cod = 99 and c.fn ~ '^CALCCODL') as cons_min,
         (select round(avg(c.cc), 1) from t_cm c where c.contrato = u.contrato and c.cod = 99 and c.fn ~ '^CALCCODL' and c.cc is not null) as cons_prom,
         (select count(*) from t_cm c where c.contrato = u.contrato and c.cod = 99 and c.fn ~ '^CALCCODL' and c.cc is not null)::int as meses_con_lectura,
         case when u.con_med then u.serial end as medidor_serial,
         coalesce(u.fi, cc.fi) as fi_bruta,
         cc.fv, cc.pago as pago_cartera, cp.fecha as cp_fecha, cp.valor as cp_valor, emd.emd, pq.pqr
  from t_u u
  left join t_cc cc on cc.contrato = u.contrato
  left join t_cp cp on cp.contrato = u.contrato
  left join t_emd emd on emd.contrato = u.contrato
  left join t_pqr pq on pq.contrato = u.contrato;

  delete from bi_interno.ficha_contrato;
  insert into bi_interno.ficha_contrato (contrato, periodo_ultimo, uso, estrato, ciclo, consumo_meses, cons_max, cons_min, cons_prom, meses_con_lectura,
                                         medidor_serial, medidor_fecha, medidor_fecha_estado, medidor_anios, cambio, submedicion, emd, ultimo_pago, pqr, facturas_vencidas)
  select f.contrato, f.periodo_ultimo, f.uso, f.estrato, f.ciclo, f.consumo_meses, f.cons_max, f.cons_min, f.cons_prom, f.meses_con_lectura,
         f.medidor_serial,
         case when x.estado = 'real' then f.fi_bruta end,
         x.estado,
         case when x.estado = 'real' then extract(year from age(v_cierre, f.fi_bruta))::int end,
         -- cambio de serial entre periodos disponibles seguidos, con la clasificación de bi.recalcular_cambio_medidor
         (select jsonb_build_object(
                   'confirmado', (array_agg(jsonb_build_object('periodo', ev.periodo, 'serial_anterior', ev.s_ant, 'serial_nuevo', ev.s_nue) order by ev.periodo desc)
                                  filter (where ev.tipo = 'reposicion_confirmada'))[1],
                   'recodificado', (array_agg(jsonb_build_object('periodo', ev.periodo, 'serial_anterior', ev.s_ant, 'serial_nuevo', ev.s_nue) order by ev.periodo desc)
                                    filter (where ev.tipo in ('cambio_serial_continuo', 'cambio_serial_retroceso', 'cambio_serial_lectura_mayor', 'reposicion_sin_lectura', 'no_concluyente')))[1])
            from (select b.periodo, a.serial as s_ant, b.serial as s_nue,
                         case when a.serial = b.serial then 'sin_cambio'
                              when b.la is not null and a.lc is not null and b.la < a.lc and b.la <= 10 then 'reposicion_confirmada'
                              when ((substr(b.periodo, 1, 4)::int * 12 + substr(b.periodo, 5, 2)::int) - (substr(a.periodo, 1, 4)::int * 12 + substr(a.periodo, 5, 2)::int)) > 1 then 'no_concluyente'
                              when b.la is null or a.lc is null then 'reposicion_sin_lectura'
                              when b.la = a.lc then 'cambio_serial_continuo'
                              when b.la < a.lc then 'cambio_serial_retroceso'
                              else 'cambio_serial_lectura_mayor' end as tipo
                  from t_par p
                  join t_cm b on b.periodo = p.periodo and b.contrato = f.contrato
                  join t_cm a on a.periodo = p.ant and a.contrato = f.contrato
                  where a.con_med and b.con_med) ev
            having count(*) filter (where ev.tipo <> 'sin_cambio') > 0),
         -- posible submedición: MISMA lógica de bi.recalcular_submedicion, por contrato, en el último periodo calculado (decisión 8)
         (select case
                   when s.contrato is null or s.uso <> 'Residencial' or not s.con_med or s.cc is null then null
                   when not (s.cod = 99 and s.fn ~ '^CALCCODL') then null
                   when r.ref is null then null
                   else jsonb_build_object(
                     'periodo', v_ps, 'consumo', s.cc, 'referencia', round(r.ref, 1), 'n_nuevos', r.n_nuevos, 'estrato', s.estrato,
                     'anios', case when s.fi is not null and s.fi <= v_cps and s.fi not in (date '1986-01-01', date '1996-09-30') then extract(year from age(v_cps, s.fi))::int end,
                     'marca', (s.fi is not null and s.fi <= v_cps and s.fi not in (date '1986-01-01', date '1996-09-30')
                               and extract(year from age(v_cps, s.fi)) >= 3 and s.cc > 0 and s.cc <= 100 and s.cc < r.ref),
                     'motivo', case when s.fi is null or s.fi > v_cps then 'medidor sin fecha de instalación'
                                    when s.fi in (date '1986-01-01', date '1996-09-30') then 'fecha de instalación por defecto'
                                    when extract(year from age(v_cps, s.fi)) < 3 then 'medidor de menos de 3 años'
                                    when s.cc = 0 then 'consumo cero'
                                    when s.cc > 100 then 'consumo sobre 100 m³'
                                    when s.cc >= r.ref then 'consumo igual o sobre la referencia' end)
                 end
            from (select 1) one
            left join t_cm s on s.contrato = f.contrato and s.periodo = v_ps
            left join t_ref r on r.estrato = s.estrato),
         coalesce(f.emd, '[]'::jsonb),
         case when f.cp_fecha is null and (f.pago_cartera ->> 'fecha') is null then null
              when f.cp_fecha is not null and (f.pago_cartera ->> 'fecha' is null or f.cp_fecha >= (f.pago_cartera ->> 'fecha')::date)
                then jsonb_build_object('fecha', f.cp_fecha, 'valor', f.cp_valor, 'fuente', 'cupones', 'corte', v_cp)
              else jsonb_build_object('fecha', (f.pago_cartera ->> 'fecha')::date, 'valor', (f.pago_cartera ->> 'valor')::numeric, 'fuente', 'cartera', 'corte', v_cc) end,
         f.pqr,
         f.fv
  from t_f f
  cross join lateral (select case when f.fi_bruta is null or f.fi_bruta > v_cierre then 'sin_dato'
                                  when f.fi_bruta in (date '1986-01-01', date '1996-09-30') then 'por_defecto'
                                  else 'real' end as estado) x;
  get diagnostics n = row_count;

  insert into bi_interno.ficha_contrato_estado (id, firma, filas, calculado_en, duracion_ms)
  values (1, v_firma, n, clock_timestamp(), (extract(epoch from clock_timestamp() - v_t0) * 1000)::int)
  on conflict (id) do update set firma = excluded.firma, filas = excluded.filas, calculado_en = excluded.calculado_en, duracion_ms = excluded.duracion_ms;
  drop table t_cm, t_mes, t_par, t_u, t_cc, t_cp, t_emd, t_pqr, t_ref, t_f;
  return n;
end $_$;


--
-- Name: recalcular_submedicion(text); Type: FUNCTION; Schema: bi; Owner: -
--

CREATE FUNCTION bi.recalcular_submedicion(p_periodo text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  v_max_m3      constant numeric := 100;   -- LIMITE del universo (m3/contrato): entran 0 < consumo_cargos <= v_max_m3
  v_edad_nuevo  constant integer := 3;     -- NUEVO = menos de v_edad_nuevo anos cumplidos al cierre (la referencia es su media)
  v_edad_vejez  constant integer := 3;     -- VEJEZ = v_edad_vejez anos cumplidos o mas ('Sin fecha' no entra a ninguno)
  v_cierre date;
  v_tar    numeric;
  n1       integer;
  n2       integer;
  n3       integer;
begin
  perform set_config('plan_cache_mode', 'force_custom_plan', true);
  perform set_config('enable_nestloop', 'off', true);
  delete from bi.v_submedicion_ref_dim   where periodo = p_periodo;
  delete from bi.v_submedicion_ciclo_dim where periodo = p_periodo;
  delete from bi.v_submedicion_rango_dim where periodo = p_periodo;
  if p_periodo < '202605'
     or not exists (select 1 from hechos.consumo_metodo where periodo = p_periodo)
     or not exists (select 1 from hechos.facturacion_contratos where periodo = p_periodo) then
    return 0;   -- sin antiguedad (202601 a 202604) o sin una de las fuentes: 0 filas es lo correcto
  end if;
  v_cierre := (to_date(p_periodo || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date;
  select sum(bi.f_num(facturado)) filter (where btrim(concepto) ~ '^[24]\s*-')
         / nullif(sum(bi.f_num(consumo)) filter (where btrim(concepto) ~ '^2\s*-'), 0)
    into v_tar
  from hechos.facturacion_contratos where periodo = p_periodo;

  with r as materialized (
    select distinct on (contrato)
           coalesce(nullif(btrim(ciclo), ''), '(sin ciclo)') as ciclo,
           case when btrim(coalesce(regexp_replace(btrim(categoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(categoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(categoria),'^-?\d+\s+','')) end as uso,
           case when btrim(coalesce(regexp_replace(btrim(subcategoria),'^-?\d+\s+',''),'')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(subcategoria),'^-?\d+\s+',''))) = 'NULO' then '(sin dato)' else btrim(regexp_replace(btrim(subcategoria),'^-?\d+\s+','')) end as estrato,
           (nullif(btrim(medidor), '') is not null
            and upper(btrim(medidor)) not in ('NO APLICA','0','00','N/A','NA','NULL','NONE','NAN','-','--')) as con_med,
           substring(upper(btrim(observacion)) from '^(\d+)\s')::int as cod,
           upper(btrim(funcion)) as fn,
           case when fecha_instalacion ~ '^\d{4}-\d{2}-\d{2}' then left(fecha_instalacion, 10)::date end as fi,
           bi.f_num(consumo_cargos) as cc
    from hechos.consumo_metodo
    where periodo = p_periodo
    order by contrato,
             (nullif(btrim(medidor), '') is not null) desc,
             (bi.f_num(lectura_actual) is not null) desc,
             bi.f_num(consumo_cargos) desc nulls last,
             categoria, subcategoria, observacion),
  b as materialized (
    select ciclo, estrato, cc,
           (cod = 99 and fn ~ '^CALCCODL' and cc > 0 and cc <= v_max_m3) as en_univ,
           (cod = 99 and fn ~ '^CALCCODL' and cc = 0) as en_cero,
           (cod = 99 and fn ~ '^CALCCODL' and cc > v_max_m3) as en_sobre,
           (fn ~ '^(\[FAMC\]\s*-\s*)?OBTECOP[PS]') as es_prom,
           case when fi is null or fi > v_cierre then 'Sin fecha'
                when extract(year from age(v_cierre, fi)) < v_edad_nuevo then '0-3'
                when extract(year from age(v_cierre, fi)) < 5  then '3-5'
                when extract(year from age(v_cierre, fi)) < 10 then '5-10'
                when extract(year from age(v_cierre, fi)) < 15 then '10-15'
                when fi = date '1986-01-01' then '>15 (1986-01-01)'
                else '>15 (fecha real)' end as banda,
           case when fi is null or fi > v_cierre then null else extract(year from age(v_cierre, fi))::int end as anios
    from r where uso = 'Residencial' and con_med and cc is not null),
  nue as materialized (
    select estrato, count(*) as n, avg(cc) as media from b where en_univ and anios < v_edad_nuevo group by estrato),
  vie as materialized (
    select estrato, count(*) as n, avg(cc) as media from b where en_univ and anios >= v_edad_vejez group by estrato),
  ref as (select estrato, case when n >= 30 then media end as ref_nuevos, n as n_nuevos from nue),
  mvej as (select estrato, case when n >= 30 then media end as media_vej, n as n_vej from vie),
  uu as materialized (
    select b.*, rf.ref_nuevos, m.media_vej
    from b left join ref rf on rf.estrato = b.estrato left join mvej m on m.estrato = b.estrato),
  i1 as (
    insert into bi.v_submedicion_ref_dim
      (periodo, estrato, banda_antig, contratos_medidor, contratos, contratos_promedio, m3_consumo, ref_nuevos_media_m3,
       n_nuevos, media_vejez_m3, n_vejez, tarifa_m3, contratos_bajo_ref, m3_perdidos_bruta, m3_exceso, max_m3,
       calculado_en, contratos_cero, contratos_sobre_max)
    select p_periodo, uu.estrato, uu.banda,
           count(*), count(*) filter (where uu.en_univ), count(*) filter (where uu.es_prom),
           sum(uu.cc) filter (where uu.en_univ),
           uu.ref_nuevos, coalesce(max(rf.n_nuevos), 0), uu.media_vej, coalesce(max(m.n_vej), 0), v_tar,
           case when uu.ref_nuevos is null then null else count(*) filter (where uu.en_univ and uu.cc < uu.ref_nuevos) end,
           case when uu.ref_nuevos is null then null else coalesce(sum(greatest(uu.ref_nuevos - uu.cc, 0)) filter (where uu.en_univ), 0) end,
           case when uu.ref_nuevos is null then null else coalesce(sum(greatest(uu.cc - uu.ref_nuevos, 0)) filter (where uu.en_univ), 0) end,
           v_max_m3, now(), count(*) filter (where uu.en_cero), count(*) filter (where uu.en_sobre)
    from uu left join ref rf on rf.estrato = uu.estrato left join mvej m on m.estrato = uu.estrato
    group by uu.estrato, uu.banda, uu.ref_nuevos, uu.media_vej
    returning 1),
  i3 as (
    insert into bi.v_submedicion_rango_dim
      (periodo, ciclo, estrato, rango_m3, contratos, m3_consumo, contratos_bajo_ref, m3_perdidos_bruta, tarifa_m3, max_m3, calculado_en)
    select p_periodo, u.ciclo, u.estrato,
           case when u.cc <= 5 then '1-5' when u.cc <= 10 then '6-10' when u.cc <= 15 then '11-15' when u.cc <= 20 then '16-20'
                when u.cc <= 30 then '21-30' when u.cc <= 40 then '31-40' when u.cc <= 60 then '41-60' else '61-100' end,
           count(*), sum(u.cc),
           case when u.ref_nuevos is null then null else count(*) filter (where u.cc < u.ref_nuevos) end,
           case when u.ref_nuevos is null then null else sum(greatest(u.ref_nuevos - u.cc, 0)) end,
           v_tar, v_max_m3, now()
    from uu u where u.en_univ
    group by u.ciclo, u.estrato, u.ref_nuevos,
             case when u.cc <= 5 then '1-5' when u.cc <= 10 then '6-10' when u.cc <= 15 then '11-15' when u.cc <= 20 then '16-20'
                  when u.cc <= 30 then '21-30' when u.cc <= 40 then '31-40' when u.cc <= 60 then '41-60' else '61-100' end
    returning 1)
  insert into bi.v_submedicion_ciclo_dim
    (periodo, ciclo, estrato, contratos, m3_consumo, m3_perdidos_bruta, contratos_vejez, m3_perdidos_atrib, tarifa_m3,
     contratos_bajo_ref, m3_exceso, max_m3, calculado_en)
  select p_periodo, u.ciclo, u.estrato, count(*), sum(u.cc),
         case when u.ref_nuevos is null then null else sum(greatest(u.ref_nuevos - u.cc, 0)) end,
         count(*) filter (where u.anios >= v_edad_vejez),
         case when u.ref_nuevos is null then null
              else coalesce(sum(u.ref_nuevos - u.cc) filter (where u.anios >= v_edad_vejez), 0) end,
         v_tar,
         case when u.ref_nuevos is null then null else count(*) filter (where u.cc < u.ref_nuevos) end,
         case when u.ref_nuevos is null then null else sum(greatest(u.cc - u.ref_nuevos, 0)) end,
         v_max_m3, now()
  from uu u where u.en_univ
  group by u.ciclo, u.estrato, u.ref_nuevos, u.media_vej;

  select count(*) into n1 from bi.v_submedicion_ref_dim   where periodo = p_periodo;
  select count(*) into n2 from bi.v_submedicion_ciclo_dim where periodo = p_periodo;
  select count(*) into n3 from bi.v_submedicion_rango_dim where periodo = p_periodo;
  return n1 + n2 + n3;
end $$;


--
-- Name: f_fecha_texto(text); Type: FUNCTION; Schema: bi_interno; Owner: -
--

CREATE FUNCTION bi_interno.f_fecha_texto(p text) RETURNS date
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $_$
declare t text := btrim(coalesce(p, ''));
begin
  if t = '' then return null; end if;
  if t ~ '^\d{4}-\d{2}-\d{2}' then return to_date(left(t, 10), 'YYYY-MM-DD'); end if;
  if t ~ '^\d{5}(\.\d+)?$' and floor(t::numeric) between 20000 and 80000 then return date '1899-12-30' + floor(t::numeric)::integer; end if;
  if t ~ '^\d{1,2}/\d{1,2}/\d{4}' then return to_date(substring(t from '^\d{1,2}/\d{1,2}/\d{4}'), 'DD/MM/YYYY'); end if;
  return null;
exception when others then
  return null;   -- p. ej. 2026-02-30: no se inventa una fecha
end $_$;


--
-- Name: f_sin_prefijo(text); Type: FUNCTION; Schema: bi_interno; Owner: -
--

CREATE FUNCTION bi_interno.f_sin_prefijo(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select case when btrim(coalesce(regexp_replace(btrim(p), '^-?\d+\s+', ''), '')) !~ '[A-Za-z0-9]' or upper(btrim(regexp_replace(btrim(p), '^-?\d+\s+', ''))) = 'NULO'
              then '(sin dato)' else btrim(regexp_replace(btrim(p), '^-?\d+\s+', '')) end
$$;


--
-- Name: f_actividades_persona(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_actividades_persona(p_email text) RETURNS TABLE(codigo text, origen text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  with p as (select unnest(campo.f_actividades_propias(p_email)) as codigo),
       c as (select unnest(campo.f_cuadrilla_actividades(q.id)) as codigo
               from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(p_email) and q.activa)
  select coalesce(p.codigo, c.codigo), case when p.codigo is not null and c.codigo is not null then 'ambas' when p.codigo is not null then 'propia' else 'cuadrilla' end
    from p full join c on c.codigo = p.codigo
$$;


--
-- Name: f_actividades_propias(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_actividades_propias(p_email text) RETURNS text[]
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select coalesce(array_agg(u.valor order by u.valor), '{}') from (
    select distinct on (e.valor) e.valor, e.tipo_evento from campo.personal_eventos e
     where e.persona = lower(p_email) and e.tipo_evento in ('asignar_actividad', 'quitar_actividad') order by e.valor, e.id desc) u
   where u.tipo_evento = 'asignar_actividad'
$$;


--
-- Name: f_ahora_bogota(); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_ahora_bogota() RETURNS timestamp without time zone
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog'
    AS $$ select clock_timestamp() at time zone 'America/Bogota' $$;


--
-- Name: f_area_vigente(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_area_vigente(p_email text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select e.valor from campo.personal_eventos e where e.persona = lower(p_email) and e.tipo_evento = 'fijar_area' order by e.id desc limit 1
$$;


--
-- Name: f_auditar(text, text, text, jsonb, text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values (lower(p_email), p_accion, p_ref, p_detalle, p_ip);
$$;


--
-- Name: f_autorizar_admin(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_autorizar_admin(p_solicitante text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text;
begin
  v_email := campo.f_verificar(p_solicitante, 'dashboard_campo');
  if not public.geoportal_es_admin(v_email) then raise exception 'Solo el administrador puede hacerlo' using errcode = '42501'; end if;
  return v_email;
end $$;


--
-- Name: f_autorizar_analisis(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_autorizar_analisis(p_solicitante text) RETURNS text
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
  select campo.f_verificar(p_solicitante, 'analisis_contrato');
$$;


--
-- Name: f_autorizar_personal(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_autorizar_personal(p_solicitante text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'acta', 'pg_temp'
    AS $$
begin
  begin
    return campo.f_autorizar_supervision(p_solicitante);
  exception when sqlstate '42501' then
    return acta.f_autorizar(p_solicitante, 'supervisar');
  end;
end $$;


--
-- Name: f_autorizar_reporte(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_autorizar_reporte(p_solicitante text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  -- Corte 8 de Técnica: también pasa quien entra por las RPC geoportal_campo_tec_* (ya autorizado allá por su formulario de Técnica); la marca solo dura esa transacción
  if campo.f_perfil(v_email) is null and coalesce(current_setting('geoportal.via_tecnica', true), '') <> 'on' then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  return v_email;
end $$;


--
-- Name: f_autorizar_supervision(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_autorizar_supervision(p_solicitante text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
begin
  return campo.f_verificar(p_solicitante, 'dashboard_campo');   -- el administrador pasa siempre en geoportal_puede
end $$;


--
-- Name: f_cargo_vigente(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_cargo_vigente(p_email text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select e.cargo from campo.personal_eventos e where e.persona = lower(p_email) and e.tipo_evento = 'fijar_cargo' order by e.id desc limit 1
$$;


--
-- Name: f_catalogo_d_inmutable(); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_catalogo_d_inmutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  if tg_table_name in ('tipo_campos', 'tipo_fotos') then
    if new.codigo is distinct from old.codigo or new.tipo_id is distinct from old.tipo_id then
      raise exception 'El código y el tipo de % no se pueden cambiar: cree uno nuevo y desactive este', tg_table_name using errcode = '55000';
    end if;
  end if;
  if tg_table_name = 'tipo_campos' then
    if new.tipo_dato is distinct from old.tipo_dato or new.sensible is distinct from old.sensible then
      raise exception 'El tipo de dato y la marca «sensible» de un campo no se pueden cambiar: cree uno nuevo y desactive este' using errcode = '55000';
    end if;
    -- Las opciones no se quitan (se desactivan): los reportes viejos guardan su código
    if old.opciones is not null and exists (select 1 from jsonb_array_elements(old.opciones) o
                                             where not exists (select 1 from jsonb_array_elements(coalesce(new.opciones, '[]'::jsonb)) n where n ->> 'codigo' = o ->> 'codigo')) then
      raise exception 'Las opciones de un campo no se quitan: desactívelas («activo»: false)' using errcode = '55000';
    end if;
  elsif tg_table_name = 'causales' then
    if new.codigo is distinct from old.codigo then
      raise exception 'El código de la causal no se puede cambiar: cree una nueva y desactive esta' using errcode = '55000';
    end if;
  elsif tg_table_name = 'causales_tipos' then
    if new.causal_id is distinct from old.causal_id or new.tipo_id is distinct from old.tipo_id then
      raise exception 'La relación causal-tipo no se mueve: desactívela y cree otra' using errcode = '55000';
    end if;
  elsif tg_table_name = 'tipos_reporte' then
    if old.prefijo_consecutivo is not null and new.prefijo_consecutivo is distinct from old.prefijo_consecutivo then
      raise exception 'El prefijo del consecutivo no se puede cambiar una vez asignado' using errcode = '55000';
    end if;
  elsif tg_table_name = 'consecutivos' then
    if new.tipo_id is distinct from old.tipo_id or new.ultimo is distinct from old.ultimo + 1 then
      raise exception 'El consecutivo solo avanza de uno en uno' using errcode = '42501';
    end if;
    new.actualizado_en := clock_timestamp();
  end if;
  return new;
end $$;


--
-- Name: f_codigo_desde_nombre(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_codigo_desde_nombre(p_nombre text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select left(btrim(regexp_replace(translate(lower(btrim(p_nombre)), 'áéíóúüñàèìòù', 'aeiouunaeiou'), '[^a-z0-9]+', '_', 'g'), '_'), 40)
$$;


--
-- Name: f_codigo_inmutable(); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_codigo_inmutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  if new.codigo is distinct from old.codigo then
    raise exception 'El código de % no se puede cambiar: cree uno nuevo y desactive este', tg_table_name using errcode = '55000';
  end if;
  if tg_table_name = 'subtipos_reporte' then
    if new.tipo_id is distinct from old.tipo_id then
      raise exception 'Un subtipo no se puede mover a otro tipo: cree uno nuevo y desactive este' using errcode = '55000';
    end if;
  end if;
  return new;
end $$;


--
-- Name: f_consultas_analisis_inmutable(); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_consultas_analisis_inmutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  if tg_op = 'UPDATE' then
    raise exception 'La bitácora de consultas no se modifica' using errcode = '42501';
  end if;
  if old.consultado_en > clock_timestamp() - interval '12 months' then
    raise exception 'La bitácora de consultas se conserva 12 meses' using errcode = '42501';
  end if;
  return old;
end $$;


--
-- Name: f_cuadrilla_actividades(bigint); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_cuadrilla_actividades(p_cuadrilla bigint) RETURNS text[]
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select coalesce(array_agg(u.valor order by u.valor), '{}') from (
    select distinct on (e.valor) e.valor, e.tipo_evento from campo.cuadrilla_eventos e
     where e.cuadrilla_id = p_cuadrilla and e.tipo_evento in ('agregar_actividad', 'quitar_actividad') order by e.valor, e.id desc) u
   where u.tipo_evento = 'agregar_actividad'
$$;


--
-- Name: f_cuadrilla_vigente(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_cuadrilla_vigente(p_email text) RETURNS bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select e.valor::bigint from campo.personal_eventos e where e.persona = lower(p_email) and e.tipo_evento = 'fijar_cuadrilla' order by e.id desc limit 1
$$;


--
-- Name: f_cupo_contratos(text, text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_cupo_contratos(p_email text, p_perfil text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'campo', 'public', 'pg_temp'
    AS $$
declare v_vent integer; v_lim integer; v_n integer; v_primero timestamptz;
begin
  if p_perfil = 'admin' then return; end if;
  v_vent := campo.f_param('ventana_limite_minutos')::integer;
  v_lim := campo.f_param('limite_contratos_ventana')::integer;
  perform pg_advisory_xact_lock(hashtextextended('campo_cupo:' || p_email, 0));
  select count(*), min(registrado_en) into v_n, v_primero from campo.reportes
   where autor = p_email and contrato is not null and registrado_en > clock_timestamp() - make_interval(mins => v_vent);
  if v_n >= v_lim then
    perform campo.f_error_limite(format('Llegó al límite de %s reportes con número de contrato en %s. Puede enviar este reporte sin el número de contrato, o intentar de nuevo dentro de %s.',
                                         v_lim, campo.f_texto_ventana(v_vent), campo.f_texto_espera(v_primero, v_vent)));
  end if;
end $$;


--
-- Name: f_cupo_contratos_falsos(text, text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_cupo_contratos_falsos(p_email text, p_perfil text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'campo', 'public', 'pg_temp'
    AS $$
declare v_lim integer; v_n integer; v_primero timestamptz;
begin
  if p_perfil = 'admin' then return; end if;
  v_lim := campo.f_param('limite_contratos_falsos_dia')::integer;
  perform pg_advisory_xact_lock(hashtextextended('campo_cupo:' || p_email, 0));
  select count(*), min(registrado_en) into v_n, v_primero from campo.reportes
   where autor = p_email and contrato_verificado is false and registrado_en > clock_timestamp() - interval '24 hours';
  if v_n >= v_lim then
    perform campo.f_error_limite(format('Llegó al límite de %s reportes con número de contrato que no se pudo verificar en las últimas 24 horas. Puede enviar este reporte sin el número de contrato, o intentar de nuevo con él dentro de %s.',
                                         v_lim, campo.f_texto_espera(v_primero, 1440)));
  end if;
end $$;


--
-- Name: f_cupo_preparaciones(text, text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_cupo_preparaciones(p_email text, p_perfil text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'campo', 'public', 'pg_temp'
    AS $$
declare v_vent integer; v_lim integer; v_n integer; v_primero timestamptz;
begin
  if p_perfil = 'admin' then return; end if;
  v_vent := campo.f_param('ventana_limite_minutos')::integer;
  v_lim := campo.f_param('limite_reportes_ventana')::integer * case when p_perfil = 'supervisor' then campo.f_param('multiplo_supervisor')::integer else 1 end;
  perform pg_advisory_xact_lock(hashtextextended('campo_cupo:' || p_email, 0));
  select count(*), min(p.creado_en) into v_n, v_primero from campo.preparaciones p
   where p.autor = p_email and p.creado_en > clock_timestamp() - make_interval(mins => v_vent)
     and not exists (select 1 from campo.reportes r where r.id = p.reporte_id);
  if v_n >= v_lim then
    perform campo.f_error_limite(format('Tiene %s envíos sin terminar en %s. Espere unos minutos, o dentro de %s, antes de empezar otro.',
                                         v_n, campo.f_texto_ventana(v_vent), campo.f_texto_espera(v_primero, v_vent)));
  end if;
end $$;


--
-- Name: f_cupo_reportes(text, text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_cupo_reportes(p_email text, p_perfil text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'campo', 'public', 'pg_temp'
    AS $$
declare v_vent integer; v_lim integer; v_n integer; v_primero timestamptz;
begin
  if p_perfil = 'admin' then return; end if;
  v_vent := campo.f_param('ventana_limite_minutos')::integer;
  v_lim := campo.f_param('limite_reportes_ventana')::integer * case when p_perfil = 'supervisor' then campo.f_param('multiplo_supervisor')::integer else 1 end;
  perform pg_advisory_xact_lock(hashtextextended('campo_cupo:' || p_email, 0));
  select count(*), min(registrado_en) into v_n, v_primero from campo.reportes
   where autor = p_email and registrado_en > clock_timestamp() - make_interval(mins => v_vent);
  if v_n >= v_lim then
    perform campo.f_error_limite(format('Llegó al límite de %s reportes en %s. Podrá enviar otro dentro de %s. Si es urgente, avise a su supervisor.',
                                         v_lim, campo.f_texto_ventana(v_vent), campo.f_texto_espera(v_primero, v_vent)));
  end if;
end $$;


--
-- Name: f_cupo_tipo(text, text, bigint, integer, text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_cupo_tipo(p_email text, p_perfil text, p_tipo_id bigint, p_limite integer, p_nombre text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'campo', 'public', 'pg_temp'
    AS $$
declare v_vent integer; v_n integer; v_primero timestamptz;
begin
  if p_perfil = 'admin' then return; end if;
  v_vent := campo.f_param('ventana_limite_minutos')::integer;
  perform pg_advisory_xact_lock(hashtextextended('campo_cupo:' || p_email, 0));
  select count(*), min(registrado_en) into v_n, v_primero from campo.reportes
   where autor = p_email and tipo_id = p_tipo_id and contrato is not null and registrado_en > clock_timestamp() - make_interval(mins => v_vent);
  if v_n >= p_limite then
    perform campo.f_error_limite(format('Llegó al límite de %s reportes de «%s» en %s. Podrá enviar otro dentro de %s. Si es urgente, avise a su supervisor.',
                                         p_limite, p_nombre, campo.f_texto_ventana(v_vent), campo.f_texto_espera(v_primero, v_vent)));
  end if;
end $$;


--
-- Name: f_error(text, text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_error(p_mensaje text, p_codigo text DEFAULT '22023'::text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  raise exception '%', p_mensaje using errcode = p_codigo, hint = 'msg_usuario';
end $$;


--
-- Name: f_error_limite(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_error_limite(p_mensaje text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  raise exception '%', p_mensaje using errcode = '53400', hint = 'msg_usuario';
end $$;


--
-- Name: f_estado_actual(uuid); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_estado_actual(p_reporte uuid) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select coalesce(
    (select e.estado_nuevo from campo.reporte_eventos e where e.reporte_id = p_reporte and e.estado_nuevo is not null order by e.id desc limit 1),
    (select s.codigo from campo.estados_reporte s where s.inicial));
$$;


--
-- Name: f_evento_coherente(); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_evento_coherente() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'campo', 'pg_temp'
    AS $$
declare v_est campo.estados_reporte%rowtype;
begin
  if new.estado_nuevo is not null then
    select * into v_est from campo.estados_reporte where codigo = new.estado_nuevo;
    if not v_est.activo then raise exception 'El estado % está desactivado', new.estado_nuevo using errcode = '22023'; end if;
    if new.tipo_evento = 'cambio_estado' then
      if not v_est.cambio_manual then raise exception 'El estado % no se puede poner a mano', new.estado_nuevo using errcode = '22023'; end if;
      if v_est.exige_motivo and new.motivo is null then raise exception 'El estado % exige un motivo', new.estado_nuevo using errcode = '22023'; end if;
    end if;
  end if;
  if new.tipo_evento = 'vincular_duplicado' then
    if new.estado_nuevo is distinct from 'duplicado' then raise exception 'Un vínculo de duplicado deja el reporte en estado duplicado' using errcode = '22023'; end if;
    if campo.f_estado_actual(new.reporte_original_id) = 'duplicado' then
      raise exception 'El reporte original ya es un duplicado de otro: apunte al original verdadero' using errcode = '55000';
    end if;
    if exists (select 1 from (select distinct e.reporte_id from campo.reporte_eventos e
                               where e.reporte_original_id = new.reporte_id and e.tipo_evento = 'vincular_duplicado') h
                where campo.f_original_actual(h.reporte_id) = new.reporte_id) then
      raise exception 'Este reporte es el original de otros duplicados: no puede ser duplicado a su vez' using errcode = '55000';
    end if;
  end if;
  return new;
end $$;


--
-- Name: st_makepoint(double precision, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.st_makepoint(double precision, double precision) RETURNS public.geometry
    LANGUAGE sql IMMUTABLE
    AS $_$select row($1,$2)::geometry$_$;


--
-- Name: st_setsrid(public.geometry, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.st_setsrid(public.geometry, integer) RETURNS public.geometry
    LANGUAGE sql IMMUTABLE
    AS $_$select $1$_$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: estados_reporte; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.estados_reporte (
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    inicial boolean DEFAULT false NOT NULL,
    exige_motivo boolean DEFAULT false NOT NULL,
    cambio_manual boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT estados_reporte_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,29}$'::text)),
    CONSTRAINT estados_reporte_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 60)))
);


--
-- Name: reporte_datos_sensibles; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.reporte_datos_sensibles (
    reporte_id uuid NOT NULL,
    datos jsonb NOT NULL,
    registrado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT reporte_datos_sensibles_datos_check CHECK (((jsonb_typeof(datos) = 'object'::text) AND (datos <> '{}'::jsonb) AND (octet_length((datos)::text) <= 4096)))
);


--
-- Name: reporte_eventos; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.reporte_eventos (
    id bigint NOT NULL,
    reporte_id uuid NOT NULL,
    tipo_evento text NOT NULL,
    estado_nuevo text,
    reporte_original_id uuid,
    acta_id uuid,
    motivo text,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT evento_acta_ck CHECK (((tipo_evento = 'vincular_acta'::text) = (acta_id IS NOT NULL))),
    CONSTRAINT evento_estado_ck CHECK (((tipo_evento = ANY (ARRAY['cambio_estado'::text, 'vincular_duplicado'::text])) = (estado_nuevo IS NOT NULL))),
    CONSTRAINT evento_motivo_ck CHECK (((tipo_evento <> ALL (ARRAY['ocultar'::text, 'reincluir'::text, 'vincular_duplicado'::text, 'nota'::text])) OR (motivo IS NOT NULL))),
    CONSTRAINT evento_no_a_si_mismo_ck CHECK (((reporte_original_id IS NULL) OR (reporte_original_id <> reporte_id))),
    CONSTRAINT evento_original_ck CHECK (((tipo_evento = 'vincular_duplicado'::text) = (reporte_original_id IS NOT NULL))),
    CONSTRAINT reporte_eventos_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT reporte_eventos_motivo_check CHECK (((motivo IS NULL) OR ((length(btrim(motivo)) >= 10) AND (length(btrim(motivo)) <= 1000)))),
    CONSTRAINT reporte_eventos_tipo_evento_check CHECK ((tipo_evento = ANY (ARRAY['cambio_estado'::text, 'ocultar'::text, 'reincluir'::text, 'vincular_duplicado'::text, 'nota'::text, 'vincular_acta'::text])))
);


--
-- Name: reporte_fotos; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.reporte_fotos (
    id bigint NOT NULL,
    reporte_id uuid NOT NULL,
    orden smallint NOT NULL,
    ruta_storage text NOT NULL,
    tamano_bytes integer NOT NULL,
    tipo_mime text NOT NULL,
    registrada_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    etiqueta text,
    CONSTRAINT reporte_fotos_etiqueta_check CHECK (((etiqueta IS NULL) OR (etiqueta ~ '^[a-z][a-z0-9_]{1,39}$'::text))),
    CONSTRAINT reporte_fotos_orden_check CHECK (((orden >= 1) AND (orden <= 10))),
    CONSTRAINT reporte_fotos_ruta_storage_check CHECK ((ruta_storage ~ '^reportes/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}/[0-9]{1,2}\.jpg$'::text)),
    CONSTRAINT reporte_fotos_tamano_bytes_check CHECK ((tamano_bytes > 0)),
    CONSTRAINT reporte_fotos_tipo_mime_check CHECK ((tipo_mime = 'image/jpeg'::text))
);


--
-- Name: reportes; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.reportes (
    id uuid NOT NULL,
    seq bigint NOT NULL,
    tipo_id bigint NOT NULL,
    subtipo_id bigint,
    descripcion text,
    contrato text,
    contrato_verificado boolean,
    lat numeric(9,6) NOT NULL,
    lon numeric(9,6) NOT NULL,
    geom public.geometry GENERATED ALWAYS AS (public.st_setsrid(public.st_makepoint((lon)::double precision, (lat)::double precision), 4326)) STORED,
    precision_m numeric(8,1),
    riesgo_inmediato boolean DEFAULT false NOT NULL,
    origen text NOT NULL,
    fuera_de_zona boolean DEFAULT false NOT NULL,
    autor text NOT NULL,
    registrado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    datos jsonb,
    resultado text,
    causal_id bigint,
    consecutivo_num bigint,
    consecutivo text,
    orden_trabajo_id uuid,
    inicio_en timestamp with time zone,
    inicio_origen text,
    area text DEFAULT 
CASE
    WHEN (current_setting('geoportal.via_tecnica'::text, true) = 'on'::text) THEN 'tecnica'::text
    ELSE NULL::text
END,
    CONSTRAINT reportes_area_ck CHECK (((area IS NULL) OR (area = 'tecnica'::text))),
    CONSTRAINT reportes_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT reportes_causal_ck CHECK (((causal_id IS NOT NULL) = (NOT (resultado IS DISTINCT FROM 'inefectivo'::text)))),
    CONSTRAINT reportes_consecutivo_ck CHECK ((((consecutivo IS NULL) = (consecutivo_num IS NULL)) AND ((consecutivo_num IS NULL) OR (consecutivo_num >= 1)))),
    CONSTRAINT reportes_contrato_check CHECK (((contrato IS NULL) OR (contrato ~ '^[A-Za-z0-9-]{1,20}$'::text))),
    CONSTRAINT reportes_datos_ck CHECK (((datos IS NULL) OR ((jsonb_typeof(datos) = 'object'::text) AND (octet_length((datos)::text) <= 4096)))),
    CONSTRAINT reportes_descripcion_check CHECK (((descripcion IS NULL) OR (length(descripcion) <= 1000))),
    CONSTRAINT reportes_inicio_origen_ck CHECK (((inicio_origen IS NULL) OR (inicio_origen = ANY (ARRAY['dispositivo'::text, 'servidor'::text])))),
    CONSTRAINT reportes_inicio_par_ck CHECK (((inicio_en IS NULL) = (inicio_origen IS NULL))),
    CONSTRAINT reportes_lat_check CHECK (((lat >= ('-90'::integer)::numeric) AND (lat <= (90)::numeric))),
    CONSTRAINT reportes_lon_check CHECK (((lon >= ('-180'::integer)::numeric) AND (lon <= (180)::numeric))),
    CONSTRAINT reportes_origen_check CHECK ((origen = ANY (ARRAY['campo'::text, 'escritorio'::text]))),
    CONSTRAINT reportes_precision_m_check CHECK (((precision_m IS NULL) OR ((precision_m >= (0)::numeric) AND (precision_m <= (100000)::numeric)))),
    CONSTRAINT reportes_resultado_ck CHECK (((resultado IS NULL) OR (resultado = ANY (ARRAY['efectivo'::text, 'inefectivo'::text]))))
);


--
-- Name: COLUMN reportes.inicio_en; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON COLUMN campo.reportes.inicio_en IS 'Pasada 14/11: hora en que se abrió el formulario (del celular: inicio_origen = dispositivo). Fin = registrado_en (servidor).';


--
-- Name: COLUMN reportes.area; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON COLUMN campo.reportes.area IS 'Corte 8 de Técnica: área que hizo el reporte. Nulo = Comercial; tecnica = hecho desde Técnica (entrada del modo Redes).';


--
-- Name: v_reportes_estado; Type: VIEW; Schema: campo; Owner: -
--

CREATE VIEW campo.v_reportes_estado AS
 SELECT r.id,
    r.seq,
    r.tipo_id,
    r.subtipo_id,
    r.descripcion,
    r.contrato,
    r.contrato_verificado,
    r.lat,
    r.lon,
    r.geom,
    r.precision_m,
    r.riesgo_inmediato,
    r.origen,
    r.fuera_de_zona,
    r.autor,
    r.registrado_en,
    COALESCE(es.estado_nuevo, ( SELECT s.codigo
           FROM campo.estados_reporte s
          WHERE s.inicial)) AS estado,
    es.creado_en AS estado_desde,
        CASE
            WHEN (es.estado_nuevo = 'duplicado'::text) THEN es.reporte_original_id
            ELSE NULL::uuid
        END AS reporte_original_id,
    COALESCE((oc.tipo_evento = 'ocultar'::text), false) AS oculto,
    oc.creado_en AS oculto_desde,
    (( SELECT count(*) AS count
           FROM campo.reporte_fotos f
          WHERE (f.reporte_id = r.id)))::integer AS n_fotos,
    r.consecutivo,
    r.resultado,
    r.causal_id,
    r.orden_trabajo_id,
    r.datos,
    (EXISTS ( SELECT 1
           FROM campo.reporte_datos_sensibles ds
          WHERE (ds.reporte_id = r.id))) AS tiene_datos_sensibles,
    r.inicio_en,
    r.inicio_origen
   FROM ((campo.reportes r
     LEFT JOIN LATERAL ( SELECT e.estado_nuevo,
            e.reporte_original_id,
            e.creado_en
           FROM campo.reporte_eventos e
          WHERE ((e.reporte_id = r.id) AND (e.estado_nuevo IS NOT NULL))
          ORDER BY e.id DESC
         LIMIT 1) es ON (true))
     LEFT JOIN LATERAL ( SELECT e.tipo_evento,
            e.creado_en
           FROM campo.reporte_eventos e
          WHERE ((e.reporte_id = r.id) AND (e.tipo_evento = ANY (ARRAY['ocultar'::text, 'reincluir'::text])))
          ORDER BY e.id DESC
         LIMIT 1) oc ON (true));


--
-- Name: f_filtrar(jsonb); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_filtrar(p_filtros jsonb) RETURNS SETOF campo.v_reportes_estado
    LANGUAGE plpgsql STABLE
    SET search_path TO 'campo', 'public', 'pg_temp'
    AS $$
declare
  f jsonb := coalesce(p_filtros, '{}'::jsonb);
  v_ocultos text := coalesce(nullif(f ->> 'ocultos', ''), 'no');
  v_tipo bigint; v_grupo bigint; v_estado text;
  v_desde timestamptz; v_hasta timestamptz; v_riesgo boolean;
  v_resultado text; v_causal bigint; v_consecutivo text; v_orden uuid;
begin
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no son válidos'); end if;
  if v_ocultos not in ('no', 'si', 'todos') then perform campo.f_error('El filtro de ocultos debe ser no, si o todos'); end if;
  if nullif(f ->> 'tipo', '') is not null then v_tipo := coalesce((select t.id from campo.tipos_reporte t where t.codigo = f ->> 'tipo'), -1); end if;
  if nullif(f ->> 'grupo', '') is not null then v_grupo := coalesce((select g.id from campo.grupos_reporte g where g.codigo = f ->> 'grupo'), -1); end if;
  if nullif(f ->> 'estado', '') is not null then v_estado := f ->> 'estado'; end if;
  if nullif(f ->> 'desde', '') is not null then v_desde := ((f ->> 'desde')::date)::timestamp at time zone 'America/Bogota'; end if;
  if nullif(f ->> 'hasta', '') is not null then v_hasta := (((f ->> 'hasta')::date) + 1)::timestamp at time zone 'America/Bogota'; end if;
  if nullif(f ->> 'riesgo_inmediato', '') is not null then v_riesgo := (f ->> 'riesgo_inmediato')::boolean; end if;
  if nullif(f ->> 'resultado', '') is not null then
    v_resultado := f ->> 'resultado';
    if v_resultado not in ('efectivo', 'inefectivo') then perform campo.f_error('El filtro de resultado debe ser efectivo o inefectivo'); end if;
  end if;
  if nullif(f ->> 'causal', '') is not null then v_causal := coalesce((select c.id from campo.causales c where c.codigo = f ->> 'causal'), -1); end if;
  if nullif(f ->> 'consecutivo', '') is not null then v_consecutivo := upper(btrim(f ->> 'consecutivo')); end if;
  if nullif(f ->> 'orden_trabajo_id', '') is not null then v_orden := (f ->> 'orden_trabajo_id')::uuid; end if;
  return query
    select v.* from campo.v_reportes_estado v
     where (v_tipo is null or v.tipo_id = v_tipo)
       and (v_grupo is null or v.tipo_id in (select t.id from campo.tipos_reporte t where t.grupo_id = v_grupo))
       and (v_estado is null or v.estado = v_estado)
       and (v_desde is null or v.registrado_en >= v_desde)
       and (v_hasta is null or v.registrado_en < v_hasta)
       and (v_riesgo is null or v.riesgo_inmediato = v_riesgo)
       and (v_resultado is null or v.resultado = v_resultado)
       and (v_causal is null or v.causal_id = v_causal)
       and (v_consecutivo is null or v.consecutivo = v_consecutivo)
       and (v_orden is null or v.orden_trabajo_id = v_orden)
       and (v_ocultos = 'todos' or (v_ocultos = 'si') = v.oculto);
end $$;


--
-- Name: f_formularios_asignados(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_formularios_asignados(p_email text) RETURNS text[]
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select coalesce(array_agg(u.formulario order by u.formulario), '{}') from (
    select distinct on (e.formulario) e.formulario, e.tipo_evento from campo.personal_eventos e
     where e.persona = lower(p_email) and e.tipo_evento in ('asignar_formulario', 'quitar_formulario') order by e.formulario, e.id desc) u
   where u.tipo_evento = 'asignar_formulario'
$$;


--
-- Name: f_formularios_personal(); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_formularios_personal() RETURNS TABLE(clave text, nombre text, grupo text, orden integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select 'reporte_general', 'Reportar anomalía', 'Reportar anomalía', 0
  union all
  select 'tipo:' || t.codigo, t.nombre, g.nombre, (1000 + g.orden * 1000 + t.orden)::integer
    from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where t.activo and g.activo
     and (exists (select 1 from campo.tipo_campos c where c.tipo_id = t.id and c.activo) or exists (select 1 from campo.tipo_fotos f where f.tipo_id = t.id and f.activo)
          or t.genera_resultado or t.prefijo_consecutivo is not null)
  union all
  select 'acta', 'Reportar posible pérdida', 'Reportar posible pérdida', 2000000000
  union all      -- Corte 14 de Técnica: «Encontrar o reportar activo» (lo usa quien tiene Formularios de campo; aquí solo se registra a quién se le asigna)
  select 'activo_campo', 'Encontrar o reportar activo', 'Activos de la red', 2000000001
$$;


--
-- Name: f_grupos_cercanos(numeric, uuid[]); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_grupos_cercanos(p_eps_m numeric, p_ids uuid[]) RETURNS TABLE(reporte_id uuid, grupo_id uuid, tamano integer)
    LANGUAGE sql STABLE
    SET search_path TO 'campo', 'public', 'pg_temp'
    AS $$
  with recursive pares as (
    select a.id as a, b.id as b from campo.reportes a join campo.reportes b on a.tipo_id = b.tipo_id
     where a.id = any (p_ids) and b.id = any (p_ids)
       and st_distance(a.geom::geography, b.geom::geography) <= p_eps_m::double precision
  ), alc(origen, destino) as (
    select a, b from pares union select alc.origen, p.b from alc join pares p on p.a = alc.destino
  ), g as (
    select alc.origen as id,
           (select r.id from campo.reportes r where r.id in (select destino from alc a2 where a2.origen = alc.origen)
             order by r.registrado_en, r.id limit 1) as grupo,
           (select count(*) from alc a3 where a3.origen = alc.origen)::integer as n
      from (select distinct origen from alc) alc
  )
  select g.id, g.grupo, g.n from g where g.n > 1;
$$;


--
-- Name: f_miembros_cuadrillas(); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_miembros_cuadrillas() RETURNS TABLE(persona text, cuadrilla_id bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
  select v.persona, v.valor::bigint from (
    select distinct on (e.persona) e.persona, e.valor from campo.personal_eventos e where e.tipo_evento = 'fijar_cuadrilla' order by e.persona, e.id desc) v
   where v.valor is not null and campo.f_persona_comercial(v.persona)
$$;


--
-- Name: f_motivo_personal(text, boolean); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_motivo_personal(p_motivo text, p_obligatorio boolean) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog'
    AS $$
declare v text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if v is null and p_obligatorio then perform campo.f_error('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
  if v is not null and (length(v) < 10 or length(v) > 300) then perform campo.f_error('El motivo debe tener entre 10 y 300 caracteres'); end if;
  return v;
end $$;


--
-- Name: f_no_borrar_catalogo(); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_no_borrar_catalogo() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception 'En %.% no se borra: se desactiva con motivo', tg_table_schema, tg_table_name using errcode = '42501';
  end if;
  if (to_jsonb(new) -> 'codigo') is distinct from (to_jsonb(old) -> 'codigo') or (to_jsonb(new) -> 'id') is distinct from (to_jsonb(old) -> 'id')
     or (to_jsonb(new) -> 'creado_en') is distinct from (to_jsonb(old) -> 'creado_en') or (to_jsonb(new) -> 'autor') is distinct from (to_jsonb(old) -> 'autor') then
    raise exception 'En %.% no cambian el código, el id, el autor ni la fecha de creación', tg_table_schema, tg_table_name using errcode = '42501';
  end if;
  return new;
end $$;


--
-- Name: f_oculto(uuid); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_oculto(p_reporte uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select coalesce((select e.tipo_evento = 'ocultar' from campo.reporte_eventos e
                    where e.reporte_id = p_reporte and e.tipo_evento in ('ocultar', 'reincluir') order by e.id desc limit 1), false);
$$;


--
-- Name: f_opciones_validas(jsonb); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_opciones_validas(p jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $_$
  select p is null or (
    jsonb_typeof(p) = 'array' and jsonb_array_length(p) between 1 and 40
    and not exists (select 1 from jsonb_array_elements(p) e
                     where jsonb_typeof(e) <> 'object'
                        or coalesce(e ->> 'codigo', '') !~ '^[a-z0-9][a-z0-9_]{0,39}$'
                        or length(btrim(coalesce(e ->> 'nombre', ''))) not between 1 and 120
                        or (e ? 'activo' and jsonb_typeof(e -> 'activo') <> 'boolean'))
    and (select count(*) = count(distinct e ->> 'codigo') from jsonb_array_elements(p) e));
$_$;


--
-- Name: f_original_actual(uuid); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_original_actual(p_reporte uuid) RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select case when x.estado_nuevo = 'duplicado' then x.reporte_original_id end
    from (select e.estado_nuevo, e.reporte_original_id from campo.reporte_eventos e
           where e.reporte_id = p_reporte and e.estado_nuevo is not null order by e.id desc limit 1) x;
$$;


--
-- Name: f_param(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_param(p_clave text) RETURNS numeric
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
declare v numeric;
begin
  select valor into v from campo.parametros where clave = p_clave;
  if not found then raise exception 'Falta el parámetro de campo %', p_clave using errcode = 'P0002'; end if;
  return v;
end $$;


--
-- Name: f_perfil(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_perfil(p_email text) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v text := lower(btrim(coalesce(p_email, '')));
begin
  if v = '' then return null; end if;
  if public.geoportal_es_admin(v) then return 'admin'; end if;
  if public.geoportal_puede(v, 'dashboard_campo') then return 'supervisor'; end if;
  if public.geoportal_puede(v, 'campo') then return 'reportante'; end if;
  return null;
end $$;


--
-- Name: f_persona_comercial(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_persona_comercial(p_email text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
  select exists (select 1 from public.geoportal_lista_blanca lb where lb.email = lower(p_email) and lb.activo and lb.rol <> 'admin'
                   and (coalesce(lb.ver_campo, false) or coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_acta, false) or coalesce(lb.ver_dashboard_acta, false)))
$$;


--
-- Name: f_quien_puede(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_quien_puede(p_actividad text) RETURNS TABLE(persona text, cuadrilla_id bigint, origen text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
  with propias as (
         select u.persona from (
           select distinct on (e.persona) e.persona, e.tipo_evento from campo.personal_eventos e
            where e.valor = p_actividad and e.tipo_evento in ('asignar_actividad', 'quitar_actividad') order by e.persona, e.id desc) u
          where u.tipo_evento = 'asignar_actividad' and campo.f_persona_comercial(u.persona)),
       por_cuadrilla as (
         select m.persona, m.cuadrilla_id from campo.f_miembros_cuadrillas() m join campo.cuadrillas q on q.id = m.cuadrilla_id and q.activa
          where p_actividad = any (campo.f_cuadrilla_actividades(m.cuadrilla_id)))
  select coalesce(p.persona, c.persona), (select m.cuadrilla_id from campo.f_miembros_cuadrillas() m where m.persona = coalesce(p.persona, c.persona)),
         case when p.persona is not null and c.persona is not null then 'ambas' when p.persona is not null then 'propia' else 'cuadrilla' end
    from propias p full join por_cuadrilla c on c.persona = p.persona
$$;


--
-- Name: f_reporte_coherente(); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_reporte_coherente() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'campo', 'pg_temp'
    AS $$
declare v_gen boolean;
begin
  if new.subtipo_id is not null and not exists (select 1 from campo.subtipos_reporte s where s.id = new.subtipo_id and s.tipo_id = new.tipo_id) then
    raise exception 'El subtipo no pertenece al tipo del reporte' using errcode = '22023';
  end if;
  select t.genera_resultado into v_gen from campo.tipos_reporte t where t.id = new.tipo_id;
  if coalesce(v_gen, false) <> (new.resultado is not null) then
    raise exception 'El resultado no corresponde al tipo del reporte' using errcode = '22023';
  end if;
  if new.causal_id is not null and not exists (
       select 1 from campo.causales c where c.id = new.causal_id
          and (c.general or exists (select 1 from campo.causales_tipos ct where ct.causal_id = c.id and ct.tipo_id = new.tipo_id))) then
    raise exception 'La causal no aplica al tipo del reporte' using errcode = '22023';
  end if;
  return new;
end $$;


--
-- Name: f_siguiente_consecutivo(bigint); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_siguiente_consecutivo(p_tipo_id bigint) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
declare v bigint;
begin
  if not exists (select 1 from campo.tipos_reporte t where t.id = p_tipo_id and t.prefijo_consecutivo is not null) then return null; end if;
  insert into campo.consecutivos as c (tipo_id, ultimo) values (p_tipo_id, 1)
  on conflict (tipo_id) do update set ultimo = c.ultimo + 1
  returning ultimo into v;
  return v;
end $$;


--
-- Name: f_solo_agregar(); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_solo_agregar() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  raise exception 'Tabla de solo agregar: % no permitido en %.%', tg_op, tg_table_schema, tg_table_name using errcode = '42501';
end $$;


--
-- Name: f_tecnica_claves(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_tecnica_claves(p_solicitante text) RETURNS text[]
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'tecnica', 'pg_temp'
    AS $$
declare v text[] := '{}'; k text;
begin
  foreach k in array array['anomalia_compartida', 'revision_compartida'] loop
    begin
      perform tecnica.f_autorizar_captura(p_solicitante, k);
      v := v || k;
    exception when insufficient_privilege then null;      -- no tiene ese formulario: se sigue con el otro
    end;
  end loop;
  return v;
end $$;


--
-- Name: f_tecnica_entrar(text, text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_tecnica_entrar(p_solicitante text, p_tipo text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'tecnica', 'pg_temp'
    AS $$
declare v_email text; v_clave text;
begin
  v_clave := case when p_tipo = 'revision_previa' then 'revision_compartida'
                  when p_tipo is null or campo.f_tipo_general(p_tipo) then 'anomalia_compartida' end;
  if v_clave is null then raise exception 'Ese formato no se llena desde Técnica' using errcode = '42501'; end if;
  v_email := tecnica.f_autorizar_captura(p_solicitante, v_clave);
  perform set_config('geoportal.via_tecnica', 'on', true);      -- solo dura esta transacción; solo la ponen estas funciones (nadie de la API las ejecuta salvo la Edge)
  return v_email;
end $$;


--
-- Name: f_telefonos(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_telefonos(p_texto text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $_$
declare
  v_pieza text;
  v_grupo text;
  v_buf   text;
  v_sig   text;
  v_g     text[];
  i       integer;
  v_todos text[] := '{}';
  v_cel   text[] := '{}';
  v_otros text[] := '{}';
  v_x     text;
begin
  if p_texto is null or btrim(p_texto) = '' then return '{}'; end if;
  -- piezas: separadores explícitos (coma, punto y coma, barra, «y», «o», «-» rodeado de espacios)
  foreach v_pieza in array regexp_split_to_array(p_texto, '\s*(,|;|/|\||\s-\s|\s+y\s+|\s+o\s+)\s*') loop
    -- dentro de una pieza, los puntos, guiones y paréntesis entre dígitos se quitan; los espacios separan grupos de dígitos
    v_pieza := regexp_replace(v_pieza, '(\d)[.\-()]+(?=\d)', '\1', 'g');
    select coalesce(array_agg(m[1]), '{}') into v_g from regexp_matches(v_pieza, '(\d+)', 'g') m;
    v_buf := '';
    for i in 1 .. coalesce(array_length(v_g, 1), 0) loop
      v_grupo := v_g[i];
      v_sig := case when i < array_length(v_g, 1) then v_g[i + 1] end;
      v_buf := v_buf || v_grupo;
      if length(v_buf) = 12 and left(v_buf, 2) = '57' then v_buf := substr(v_buf, 3); end if;
      if length(v_buf) = 10
         or (length(v_buf) between 7 and 9 and (v_sig is null or length(v_buf) + length(v_sig) > 12)) then
        v_todos := v_todos || v_buf; v_buf := '';
      elsif length(v_buf) > 10 then
        -- varios números pegados: si se parte en bloques de 10 que empiezan por 3, son celulares; si no, se descarta
        if length(v_buf) % 10 = 0 and v_buf ~ ('^(3\d{9}){' || (length(v_buf) / 10) || '}$') then
          foreach v_x in array (select array_agg(substr(v_buf, 1 + 10 * k, 10)) from generate_series(0, length(v_buf) / 10 - 1) k) loop
            v_todos := v_todos || v_x;
          end loop;
        end if;
        v_buf := '';
      end if;
    end loop;
  end loop;
  foreach v_x in array v_todos loop
    if v_x ~ '^3\d{9}$' then
      if not v_x = any (v_cel) then v_cel := v_cel || v_x; end if;
    elsif v_x !~ '^0+$' and not v_x = any (v_otros) then
      v_otros := v_otros || v_x;
    end if;
  end loop;
  return (v_cel || v_otros)[1:3];
end $_$;


--
-- Name: f_texto_consecutivo(text, bigint); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_texto_consecutivo(p_prefijo text, p_num bigint) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select p_prefijo || '-' || case when p_num < 1000000 then lpad(p_num::text, 6, '0') else p_num::text end;
$$;


--
-- Name: f_texto_espera(timestamp with time zone, integer); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_texto_espera(p_primero timestamp with time zone, p_ventana_min integer) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select case when m <= 1 then 'menos de un minuto' else m || ' minutos' end
    from (select greatest(1, ceil(extract(epoch from (p_primero + make_interval(mins => p_ventana_min) - clock_timestamp())) / 60.0))::integer as m) x;
$$;


--
-- Name: f_texto_ventana(integer); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_texto_ventana(p_ventana_min integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select case when p_ventana_min = 60 then 'la última hora' when p_ventana_min % 60 = 0 then 'las últimas ' || (p_ventana_min / 60) || ' horas' else 'los últimos ' || p_ventana_min || ' minutos' end;
$$;


--
-- Name: f_tipo_general(text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_tipo_general(p_codigo text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select exists (select 1 from campo.tipos_reporte t
                  where t.codigo = p_codigo
                    and not (exists (select 1 from campo.tipo_campos c where c.tipo_id = t.id and c.activo) or exists (select 1 from campo.tipo_fotos f where f.tipo_id = t.id and f.activo)
                             or t.genera_resultado or t.prefijo_consecutivo is not null)) $$;


--
-- Name: f_validar_datos(bigint, jsonb, boolean); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_validar_datos(p_tipo_id bigint, p_datos jsonb, p_exigir boolean) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $_$
declare
  d jsonb := coalesce(p_datos, '{}'::jsonb); c campo.tipo_campos%rowtype; v jsonb; v_k text; v_txt text; v_num numeric; v_max integer; v_ts timestamp;
  v_gen jsonb := '{}'::jsonb; v_sen jsonb := '{}'::jsonb; v_norm jsonb; v_vacio boolean;
  v_ocultos text[] := '{}'; v_padre jsonb; v_visible boolean;   -- pasada 14/11
begin
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del formato no vienen en la forma esperada'); end if;
  if octet_length(d::text) > 4096 then perform campo.f_error('Los datos del formato son demasiado grandes'); end if;
  select k into v_k from jsonb_object_keys(d) k
   where not exists (select 1 from campo.tipo_campos x where x.tipo_id = p_tipo_id and x.codigo = k and x.activo) order by k limit 1;
  if v_k is not null then perform campo.f_error(format('El campo «%s» no existe en este formato', left(v_k, 40))); end if;

  for c in select * from campo.tipo_campos x where x.tipo_id = p_tipo_id and x.activo order by x.orden, x.id loop
    v := d -> c.codigo;
    -- Pasada 14/11: la condición de pantalla (visible_si) decide también si el campo se EXIGE. Misma regla que la pantalla (src/campo/formatos/logica.ts):
    -- oculto si su campo «padre» está oculto o sin respuesta, o si no cumple «es» / «no_es». Un campo oculto que llega con valor se valida y se guarda como antes.
    v_visible := true;
    if c.visible_si is not null then
      v_padre := d -> (c.visible_si ->> 'campo');
      if (c.visible_si ->> 'campo') = any (v_ocultos) or v_padre is null or jsonb_typeof(v_padre) = 'null'
         or (jsonb_typeof(v_padre) = 'string' and btrim(v_padre #>> '{}') = '') or (jsonb_typeof(v_padre) = 'array' and jsonb_array_length(v_padre) = 0) then
        v_visible := false;
      elsif c.visible_si ? 'no_es' then
        v_visible := case when jsonb_typeof(v_padre) = 'array' then not (v_padre ? (c.visible_si ->> 'no_es')) else v_padre is distinct from (c.visible_si -> 'no_es') end;
      elsif jsonb_typeof(c.visible_si -> 'es') = 'boolean' then
        v_visible := v_padre = (c.visible_si -> 'es');
      else
        v_visible := case when jsonb_typeof(v_padre) = 'array' then v_padre ? (c.visible_si ->> 'es') else v_padre = (c.visible_si -> 'es') end;
      end if;
      if not v_visible then v_ocultos := v_ocultos || c.codigo; end if;
    end if;
    v_vacio := v is null or jsonb_typeof(v) = 'null' or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') or (jsonb_typeof(v) = 'array' and jsonb_array_length(v) = 0);
    if v_vacio then
      if c.obligatorio and p_exigir and v_visible then perform campo.f_error(format('Falta «%s»', c.nombre)); end if;
      continue;
    end if;
    if c.tipo_dato = 'texto' then
      if jsonb_typeof(v) <> 'string' then perform campo.f_error(format('«%s» debe ser un texto', c.nombre)); end if;
      v_txt := btrim(v #>> '{}'); v_max := coalesce(c.maximo, 300)::integer;
      if length(v_txt) > v_max then perform campo.f_error(format('«%s» es demasiado largo (máximo %s caracteres)', c.nombre, v_max)); end if;
      v_norm := to_jsonb(v_txt);
    elsif c.tipo_dato in ('entero', 'decimal') then
      if jsonb_typeof(v) <> 'number' then perform campo.f_error(format('«%s» debe ser un número', c.nombre)); end if;
      v_num := (v #>> '{}')::numeric;
      if c.tipo_dato = 'entero' and v_num <> trunc(v_num) then perform campo.f_error(format('«%s» debe ser un número entero', c.nombre)); end if;
      if (c.minimo is not null and v_num < c.minimo) or (c.maximo is not null and v_num > c.maximo) then
        perform campo.f_error(format('«%s» está fuera del rango permitido%s', c.nombre,
          case when c.minimo is not null and c.maximo is not null then format(' (de %s a %s)', trim_scale(c.minimo), trim_scale(c.maximo))
               when c.minimo is not null then format(' (mínimo %s)', trim_scale(c.minimo)) else format(' (máximo %s)', trim_scale(c.maximo)) end));
      end if;
      v_norm := to_jsonb(v_num);
    elsif c.tipo_dato = 'dia_hora' then
      if jsonb_typeof(v) <> 'string' or (v #>> '{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$' then
        perform campo.f_error(format('«%s» debe ser un día y una hora (AAAA-MM-DDTHH:MM)', c.nombre));
      end if;
      begin v_ts := (v #>> '{}')::timestamp; exception when others then v_ts := null; end;
      if v_ts is null then perform campo.f_error(format('«%s» no es un día y una hora válidos', c.nombre)); end if;
      if v_ts < timestamp '2020-01-01' or v_ts > campo.f_ahora_bogota() + interval '1 year' then
        perform campo.f_error(format('«%s» está fuera del rango permitido (desde 2020 hasta un año adelante)', c.nombre));
      end if;
      v_norm := to_jsonb(to_char(v_ts, 'YYYY-MM-DD"T"HH24:MI'));
    elsif c.tipo_dato = 'si_no' then
      if jsonb_typeof(v) <> 'boolean' then perform campo.f_error(format('«%s» debe ser sí o no', c.nombre)); end if;
      v_norm := v;
    elsif c.tipo_dato = 'opcion' then
      if jsonb_typeof(v) <> 'string' or not exists (select 1 from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = v #>> '{}' and coalesce((o ->> 'activo')::boolean, true)) then
        perform campo.f_error(format('Elija una opción válida en «%s»', c.nombre));
      end if;
      v_norm := v;
    else  -- opciones (varias)
      if jsonb_typeof(v) <> 'array'
         or exists (select 1 from jsonb_array_elements(v) e where jsonb_typeof(e) <> 'string'
                       or not exists (select 1 from jsonb_array_elements(c.opciones) o where o ->> 'codigo' = e #>> '{}' and coalesce((o ->> 'activo')::boolean, true)))
         or (select count(*) <> count(distinct e #>> '{}') from jsonb_array_elements(v) e) then
        perform campo.f_error(format('Elija opciones válidas, sin repetir, en «%s»', c.nombre));
      end if;
      v_norm := v;
    end if;
    if c.sensible then v_sen := v_sen || jsonb_build_object(c.codigo, v_norm); else v_gen := v_gen || jsonb_build_object(c.codigo, v_norm); end if;
  end loop;
  return jsonb_build_object('general', v_gen, 'sensibles', v_sen);
end $_$;


--
-- Name: FUNCTION f_validar_datos(p_tipo_id bigint, p_datos jsonb, p_exigir boolean); Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON FUNCTION campo.f_validar_datos(p_tipo_id bigint, p_datos jsonb, p_exigir boolean) IS 'Valida los campos propios contra la definición del tipo. Pasada 14/11: los obligatorios ocultos por visible_si no se exigen.';


--
-- Name: f_validar_orden_trabajo(uuid, text, bigint); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_validar_orden_trabajo(p_orden uuid, p_email text, p_tipo_id bigint) RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
begin
  return;
end $$;


--
-- Name: f_verificar(text, text); Type: FUNCTION; Schema: campo; Owner: -
--

CREATE FUNCTION campo.f_verificar(p_solicitante text, p_modo text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if not public.geoportal_puede(v_email, p_modo) then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  return v_email;
end $$;


--
-- Name: f_knn_doble(public.geometry, public.geometry); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f_knn_doble(public.geometry, public.geometry) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $_$ select sqrt(power(st_x($1) - st_x($2), 2) + power(st_y($1) - st_y($2), 2)) $_$;


--
-- Name: geoportal_acta_abrir(text, numeric, numeric, numeric, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_abrir(p_solicitante text, p_lat numeric, p_lon numeric, p_precision_m numeric DEFAULT NULL::numeric, p_reporte_id uuid DEFAULT NULL::uuid, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_r jsonb;
begin
  v_email := acta.f_autorizar(p_solicitante, 'capturar');
  v_r := acta.f_abrir(v_email, acta.f_perfil(v_email), p_lat, p_lon, p_precision_m, p_reporte_id, null, null);
  perform acta.f_auditar(v_email, 'acta_abrir', v_r ->> 'acta_id', jsonb_build_object('consecutivo', v_r ->> 'consecutivo', 'fuera_de_zona', (v_r ->> 'aviso_zona')::boolean), p_ip);
  return v_r;
end $$;


--
-- Name: geoportal_acta_aperturas_sin_registrar(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_aperturas_sin_registrar(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_lim integer; v_inc boolean := false; v_vig integer := acta.f_param('vigencia_apertura_horas')::integer; v_filas jsonb; v_res jsonb;
begin
  v_email := acta.f_autorizar_alguna(p_solicitante, array['supervisar', 'administrar']);
  begin v_lim := least(greatest(coalesce((f ->> 'limite')::integer, 200), 1), 500); exception when others then perform acta.f_error('El límite no es válido'); end;
  begin v_inc := coalesce((f ->> 'incluir_canceladas')::boolean, false); exception when others then perform acta.f_error('El filtro incluir_canceladas debe ser sí o no'); end;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.abierto_en desc), '[]'::jsonb) into v_filas from (
    select c.apertura_id as acta_id, c.consecutivo, c.autor, c.abierto_en, c.abierto_en + make_interval(hours => v_vig) as vence_en, c.situacion,
           c.cancelada_en, c.cancelada_por, c.motivo_cancelacion,
           (select m.nombre from acta.motivos_cancelacion m where m.codigo = c.motivo_cancelacion) as motivo_nombre, c.motivo_texto
      from acta.v_conciliacion c
     where c.situacion <> 'registrada' and (v_inc or c.situacion <> 'cancelada')
     order by c.abierto_en desc limit v_lim) q;
  select jsonb_build_object('en_curso', count(*) filter (where situacion = 'abierta_en_curso'), 'vencidas', count(*) filter (where situacion = 'abierta_vencida_sin_registrar'),
                            'canceladas', count(*) filter (where situacion = 'cancelada'))
    into v_res from acta.v_conciliacion;
  perform acta.f_auditar(v_email, 'acta_aperturas_sin_registrar', null, jsonb_build_object('incluir_canceladas', v_inc), p_ip);
  return jsonb_build_object('resumen', v_res, 'filas', v_filas, 'max_filas', v_lim);
end $$;


--
-- Name: geoportal_acta_cambiar_estado(text, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_cambiar_estado(p_solicitante text, p_acta_raiz_id uuid, p_estado text, p_motivo text DEFAULT NULL::text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_est acta.estados_caso%rowtype; v_act text; v_m text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  perform acta.f_exigir_caso(p_acta_raiz_id);
  select * into v_est from acta.estados_caso where codigo = btrim(coalesce(p_estado, ''));
  if not found or not v_est.activo then perform acta.f_error('El estado no existe o está desactivado'); end if;
  if not v_est.cambio_manual then perform acta.f_error(format('El estado «%s» no se puede poner a mano', v_est.nombre)); end if;
  v_act := acta.f_estado_actual(p_acta_raiz_id);
  if v_act = v_est.codigo then perform acta.f_error('El caso ya está en ese estado', '55000'); end if;
  if not exists (select 1 from acta.transiciones_caso t where t.desde = v_act and t.hasta = v_est.codigo and t.activo) then
    perform acta.f_error(format('No se permite pasar del estado «%s» a «%s»', (select nombre from acta.estados_caso where codigo = v_act), v_est.nombre), '55000');
  end if;
  if v_est.exige_motivo or v_m is not null then v_m := acta.f_motivo(v_m); end if;
  insert into acta.caso_eventos (acta_raiz_id, tipo_evento, estado_nuevo, motivo, autor) values (p_acta_raiz_id, 'cambio_estado', v_est.codigo, v_m, v_email);
  perform acta.f_auditar(v_email, 'acta_cambiar_estado', p_acta_raiz_id::text, jsonb_build_object('de', v_act, 'a', v_est.codigo), p_ip);
  return jsonb_build_object('acta_raiz_id', p_acta_raiz_id, 'estado', v_est.codigo);
end $$;


--
-- Name: geoportal_acta_cancelar(text, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_cancelar(p_solicitante text, p_acta_id uuid, p_motivo_codigo text, p_motivo_texto text DEFAULT NULL::text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_c jsonb; v_ap acta.aperturas%rowtype; v_rol text; v_ev acta.apertura_eventos%rowtype; v_txt text := nullif(btrim(coalesce(p_motivo_texto, '')), '');
        v_cod text := btrim(coalesce(p_motivo_codigo, '')); v_creado timestamptz;
begin
  v_email := acta.f_autorizar_alguna(p_solicitante, array['capturar', 'supervisar', 'administrar']);
  v_c := acta.f_capacidades(v_email);
  if p_acta_id is null then perform acta.f_error('Falta el identificador del acta'); end if;
  if v_cod = '' then perform acta.f_error('Elija el motivo de la cancelación'); end if;
  if v_txt is not null and (length(v_txt) < 3 or length(v_txt) > 1000) then perform acta.f_error('El texto del motivo debe tener entre 3 y 1.000 caracteres'); end if;
  select * into v_ap from acta.aperturas where id = p_acta_id for update;          -- bloquea la fila: serializa con un registro que llegue al mismo tiempo
  -- Quien solo captura no se entera de si existe una apertura ajena
  if not found or (v_ap.autor <> v_email and not (coalesce((v_c ->> 'supervisar')::boolean, false) or coalesce((v_c ->> 'administrar')::boolean, false))) then
    perform acta.f_error('Identificador de acta no válido');
  end if;
  v_rol := case when v_ap.autor = v_email then 'autor' when coalesce((v_c ->> 'administrar')::boolean, false) then 'administrador' else 'supervisor' end;
  select * into v_ev from acta.apertura_eventos where apertura_id = p_acta_id and tipo_evento = 'cancelar';
  if found then
    return jsonb_build_object('acta_id', p_acta_id, 'consecutivo', v_ap.consecutivo, 'cancelada', true, 'repetido', true, 'cancelada_en', v_ev.creado_en);
  end if;
  if v_ap.correccion_de is not null then perform acta.f_error('Una corrección en curso no se cancela desde aquí', '55000'); end if;
  if exists (select 1 from acta.actas x where x.id = p_acta_id) then perform acta.f_error('Lo registrado no se cancela: para corregirlo use la corrección de la supervisión', '55000'); end if;
  -- El disparador valida el motivo (activo; texto si lo exige) y repite las dos comprobaciones anteriores
  insert into acta.apertura_eventos (apertura_id, tipo_evento, motivo_codigo, motivo_texto, autor, rol_autor)
  values (p_acta_id, 'cancelar', v_cod, v_txt, v_email, v_rol) returning creado_en into v_creado;
  perform acta.f_auditar(v_email, 'acta_cancelar', p_acta_id::text, jsonb_build_object('consecutivo', v_ap.consecutivo, 'motivo', v_cod, 'rol', v_rol), p_ip);
  return jsonb_build_object('acta_id', p_acta_id, 'consecutivo', v_ap.consecutivo, 'cancelada', true, 'repetido', false, 'cancelada_en', v_creado);
end $$;


--
-- Name: geoportal_acta_cercanas(text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_cercanas(p_solicitante text, p_acta_id uuid, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; a acta.actas%rowtype; v_d numeric := acta.f_param('distancia_sugerencia_m'); v_r jsonb;
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  select * into a from acta.actas where id = p_acta_id;
  if not found then perform acta.f_error('El acta no existe', 'P0002'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('acta_raiz_id', c.acta_raiz_id, 'consecutivo', c.consecutivo, 'estado', c.estado, 'modo_identificacion', c.modo_identificacion,
           'fecha_acta_fisica', c.fecha_acta_fisica, 'distancia_m', round(st_distance(c.geom::geography, a.geom::geography)::numeric, 1)) order by st_distance(c.geom::geography, a.geom::geography)), '[]'::jsonb)
    into v_r from acta.v_casos c where c.acta_raiz_id <> a.acta_raiz_id and st_dwithin(c.geom::geography, a.geom::geography, v_d::double precision);
  perform acta.f_auditar(v_email, 'acta_cercanas', p_acta_id::text, '{}'::jsonb, p_ip);
  return jsonb_build_object('distancia_m', v_d, 'cercanas', v_r);
end $$;


--
-- Name: geoportal_acta_conciliacion(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_conciliacion(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_lim integer; v_filas jsonb; v_res jsonb;
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  begin v_lim := least(greatest(coalesce((f ->> 'limite')::integer, 200), 1), 1000); exception when others then perform acta.f_error('El límite no es válido'); end;
  if f ->> 'situacion' is not null and f ->> 'situacion' not in ('registrada', 'abierta_en_curso', 'abierta_vencida_sin_registrar', 'cancelada') then perform acta.f_error('Situación no válida'); end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.abierto_en desc), '[]'::jsonb) into v_filas from (
    select c.consecutivo, c.autor, c.abierto_en, c.situacion, c.numero_acta_fisica, c.fecha_acta_fisica, c.sin_foto_acta_fisica, c.apertura_id, c.cancelada_en, c.motivo_cancelacion
      from acta.v_conciliacion c
     where (f ->> 'situacion' is null or c.situacion = f ->> 'situacion')
       and (c.situacion <> 'cancelada' or f ->> 'situacion' = 'cancelada' or coalesce((f ->> 'incluir_canceladas')::boolean, false))
       and (coalesce((f ->> 'solo_pendientes')::boolean, false) = false or c.situacion not in ('registrada', 'cancelada') or c.sin_foto_acta_fisica)
     order by c.abierto_en desc limit v_lim) q;
  select jsonb_build_object('registradas', count(*) filter (where situacion = 'registrada'), 'abiertas_en_curso', count(*) filter (where situacion = 'abierta_en_curso'),
                            'abiertas_vencidas_sin_registrar', count(*) filter (where situacion = 'abierta_vencida_sin_registrar'), 'canceladas', count(*) filter (where situacion = 'cancelada'), 'registros_sin_foto_acta_fisica', count(*) filter (where sin_foto_acta_fisica))
    into v_res from acta.v_conciliacion;
  perform acta.f_auditar(v_email, 'acta_conciliacion', null, '{}'::jsonb, p_ip);
  return jsonb_build_object('resumen', v_res, 'filas', v_filas);
end $$;


--
-- Name: geoportal_acta_custodia_medidor(text, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_custodia_medidor(p_solicitante text, p_acta_raiz_id uuid, p_custodia text, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_m text; v_cod text;
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  perform acta.f_exigir_caso(p_acta_raiz_id); v_m := acta.f_motivo(p_motivo);
  select codigo into v_cod from acta.estados_custodia where codigo = btrim(coalesce(p_custodia, '')) and activo;
  if v_cod is null then perform acta.f_error('El estado de custodia no existe o está desactivado'); end if;
  insert into acta.caso_eventos (acta_raiz_id, tipo_evento, custodia_codigo, motivo, autor) values (p_acta_raiz_id, 'custodia_medidor', v_cod, v_m, v_email);
  perform acta.f_auditar(v_email, 'acta_custodia_medidor', p_acta_raiz_id::text, jsonb_build_object('custodia', v_cod), p_ip);
  return jsonb_build_object('acta_raiz_id', p_acta_raiz_id, 'custodia', v_cod);
end $$;


--
-- Name: geoportal_acta_foto_papel_posterior(text, uuid, integer, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_foto_papel_posterior(p_solicitante text, p_acta_id uuid, p_orden integer, p_ruta text, p_huella text, p_detalle text DEFAULT NULL::text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'storage', 'pg_temp'
    AS $_$
declare v_email text; v_a acta.actas%rowtype; v_tf acta.tipos_foto%rowtype; v_next integer; v_np integer; v_size bigint; v_mime text; v_perfil text;
begin
  v_email := acta.f_autorizar(p_solicitante, 'capturar');
  v_perfil := acta.f_perfil(v_email);
  select * into v_a from acta.actas where id = p_acta_id;
  if not found or (v_a.autor <> v_email and v_perfil not in ('admin', 'supervisor')) then perform acta.f_error('Identificador de acta no válido'); end if;
  if not v_a.papel_pendiente then perform acta.f_error('Esta acta no está marcada con «papel pendiente»', '55000'); end if;
  if v_a.id <> acta.f_vigente(v_a.acta_raiz_id) then perform acta.f_error('Solo se adjunta a la versión vigente', '55000'); end if;
  select * into v_tf from acta.tipos_foto where es_acta_fisica and activo order by id limit 1;
  if not found then raise exception 'No hay un tipo de foto activo para el acta física' using errcode = 'P0002'; end if;
  select count(*) into v_np from acta.acta_fotos f join acta.tipos_foto t on t.id = f.tipo_foto_id join acta.actas x on x.id = f.acta_id where x.acta_raiz_id = v_a.acta_raiz_id and t.es_acta_fisica;
  if v_np >= acta.f_param('max_fotos_acta_fisica') then perform acta.f_error('Ya están las fotos del acta física permitidas'); end if;
  select coalesce(max(orden), 0) + 1 into v_next from acta.acta_fotos where acta_id = p_acta_id;
  if p_orden is distinct from v_next then perform acta.f_error(format('La foto debe llevar el orden %s', v_next)); end if;
  if p_ruta is null or p_ruta !~ ('^actas/[0-9]{4}-[0-9]{2}/' || p_acta_id::text || '/fotos/' || p_orden || '\.jpg$') then perform acta.f_error('La ruta de la foto no corresponde a esta acta'); end if;
  if p_huella is null or p_huella !~ '^[0-9a-f]{64}$' then perform acta.f_error('Falta la huella de la foto'); end if;
  select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'acta-evidencias' and o.name = p_ruta;
  if not found then perform acta.f_error('No se encontró la foto: súbala de nuevo'); end if;
  if coalesce(v_size, 0) <= 0 or v_size > acta.f_param('max_bytes_foto_acta_fisica') then perform acta.f_error('La foto está vacía o pesa más de lo permitido'); end if;
  if v_mime is distinct from 'image/jpeg' then perform acta.f_error('La foto debe ser JPEG'); end if;
  insert into acta.acta_fotos (acta_id, orden, tipo_foto_id, ruta_storage, sha256, tamano_bytes, tipo_mime, detalle, posterior)
  values (p_acta_id, p_orden, v_tf.id, p_ruta, p_huella, v_size, v_mime, nullif(btrim(coalesce(p_detalle, '')), ''), true);
  insert into acta.caso_eventos (acta_raiz_id, tipo_evento, acta_id, autor) values (v_a.acta_raiz_id, 'foto_acta_fisica_posterior', p_acta_id, v_email);
  perform acta.f_auditar(v_email, 'acta_foto_papel_posterior', p_acta_id::text, jsonb_build_object('orden', p_orden), p_ip);
  return jsonb_build_object('acta_id', p_acta_id, 'orden', p_orden);
end $_$;


--
-- Name: geoportal_acta_foto_ruta(text, uuid, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_foto_ruta(p_solicitante text, p_acta_id uuid, p_orden integer, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_ruta text;
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  perform acta.f_cupo_lecturas(v_email);
  select f.ruta_storage into v_ruta from acta.acta_fotos f where f.acta_id = p_acta_id and f.orden = p_orden;
  if v_ruta is null then perform acta.f_error('La foto no existe', 'P0002'); end if;
  insert into acta.accesos_evidencia (autor, acta_id, orden) values (v_email, p_acta_id, p_orden);
  perform acta.f_auditar(v_email, 'acta_ver_foto', p_acta_id::text, jsonb_build_object('orden', p_orden), p_ip);
  return jsonb_build_object('ruta', v_ruta, 'segundos', acta.f_param('url_lectura_segundos'));
end $$;


--
-- Name: geoportal_acta_gestionar_catalogo(text, text, text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_gestionar_catalogo(p_solicitante text, p_entidad text, p_accion text, p_datos jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $_$
declare
  v_email text; v_d jsonb := coalesce(p_datos, '{}'::jsonb); v_ent text := btrim(coalesce(p_entidad, '')); v_acc text := btrim(coalesce(p_accion, ''));
  v_crear text[]; v_edit text[]; v_clave text; v_antes jsonb; v_despues jsonb; k text; v_set text := ''; v_cols text; v_c jsonb; v_row jsonb; v_p acta.parametros%rowtype;
  v_todas constant text[] := array['tipos_hallazgo', 'calidades_atendiente', 'estados_medidor', 'estados_sellos', 'diametros_acometida', 'acciones_correctivas', 'tipos_foto',
                                   'estados_caso', 'transiciones_caso', 'estados_custodia', 'parametros'];
begin
  v_email := acta.f_autorizar(p_solicitante, 'administrar');
  if v_ent <> all (v_todas) then perform acta.f_error('Entidad de catálogo no válida'); end if;
  if v_acc not in ('crear', 'actualizar') then perform acta.f_error('La acción debe ser crear o actualizar (nada se borra: se desactiva)'); end if;
  if jsonb_typeof(v_d) <> 'object' then perform acta.f_error('Los datos no tienen el formato esperado'); end if;

  if v_ent = 'parametros' then
    if v_acc = 'crear' then perform acta.f_error('Los parámetros no se crean desde aquí: se cambia el valor de los existentes'); end if;
    select * into v_p from acta.parametros where clave = v_d ->> 'clave';
    if not found then perform acta.f_error('El parámetro no existe', 'P0002'); end if;
    if (select count(*) from jsonb_object_keys(v_d) as kk(kc) where kc not in ('clave', 'valor')) > 0 then perform acta.f_error('Solo se puede cambiar el valor de un parámetro'); end if;
    if jsonb_typeof(v_d -> 'valor') <> 'number' then perform acta.f_error('El valor debe ser un número'); end if;
    begin
      update acta.parametros set valor = (v_d ->> 'valor')::numeric, actualizado_en = clock_timestamp(), actualizado_por = v_email where clave = v_p.clave;
    exception when check_violation then perform acta.f_error(format('El valor está fuera del rango permitido (%s a %s)', coalesce(v_p.minimo::text, '—'), coalesce(v_p.maximo::text, '—')));
    end;
    perform acta.f_auditar(v_email, 'acta_catalogo', 'parametros:' || v_p.clave, jsonb_build_object('antes', v_p.valor, 'despues', (v_d ->> 'valor')::numeric), p_ip);
    return jsonb_build_object('entidad', v_ent, 'clave', v_p.clave, 'valor', (v_d ->> 'valor')::numeric);
  end if;

  -- columnas permitidas por entidad (el código solo se da al crear; nunca cambia)
  v_clave := case when v_ent = 'transiciones_caso' then 'desde,hasta' else 'codigo' end;
  v_crear := case v_ent
    when 'tipos_hallazgo' then array['codigo','nombre','nota','orden','exige_texto','excluyente','habilita_accion_codigo','activo']
    when 'calidades_atendiente' then array['codigo','nombre','exige_texto','orden','activo']
    when 'acciones_correctivas' then array['codigo','nombre','orden','campos','activo']
    when 'tipos_foto' then array['codigo','nombre','orden','exigida_con_irregularidad','es_acta_fisica','activo']
    when 'estados_caso' then array['codigo','nombre','orden','inicial','inicial_sin_irregularidad','exige_motivo','cambio_manual','terminal','gestiona','activo']
    when 'transiciones_caso' then array['desde','hasta','activo']
    else array['codigo','nombre','orden','activo'] end;
  v_edit := array(select c from unnest(v_crear) c where c not in ('codigo', 'desde', 'hasta'));

  if v_d ? 'campos' then
    if jsonb_typeof(v_d -> 'campos') <> 'array' then perform acta.f_error('«campos» debe ser una lista'); end if;
    for v_c in select e from jsonb_array_elements(v_d -> 'campos') e loop
      if jsonb_typeof(v_c) <> 'object' or coalesce(v_c ->> 'clave', '') !~ '^[a-z][a-z0-9_]{1,39}$' or coalesce(v_c ->> 'tipo', '') not in ('texto', 'numero', 'hora')
         or length(btrim(coalesce(v_c ->> 'etiqueta', ''))) < 2 or (v_c ? 'obligatorio' and jsonb_typeof(v_c -> 'obligatorio') <> 'boolean') then
        perform acta.f_error('Cada campo debe tener clave (minúsculas y guion bajo), etiqueta, tipo (texto, numero u hora) y, si quiere, obligatorio (sí/no)');
      end if;
    end loop;
  end if;
  for k in select jsonb_object_keys(v_d) loop
    if k <> all (v_crear) then perform acta.f_error(format('El dato «%s» no se admite para %s', k, v_ent)); end if;
  end loop;

  if v_acc = 'crear' then
    select string_agg(format('%I', c), ', ') into v_cols from unnest(v_crear) c where v_d ? c;
    if v_cols is null then perform acta.f_error('Faltan datos'); end if;
    begin
      execute format('insert into acta.%I (%s) select %s from jsonb_populate_record(null::acta.%I, $1) returning to_jsonb(%I.*)', v_ent, v_cols, v_cols, v_ent, v_ent) into v_despues using v_d;
    exception when unique_violation then perform acta.f_error('Ya existe uno con ese código (o con esa condición única)', '23505');
              when check_violation or not_null_violation or foreign_key_violation then perform acta.f_error('Algún dato no es válido o falta');
    end;
    perform acta.f_auditar(v_email, 'acta_catalogo', v_ent || ':crear', jsonb_build_object('despues', v_despues), p_ip);
    return jsonb_build_object('entidad', v_ent, 'accion', 'crear', 'registro', v_despues);
  end if;

  -- actualizar
  if v_ent = 'transiciones_caso' then
    execute 'select to_jsonb(t.*) from acta.transiciones_caso t where desde = $1 and hasta = $2' into v_antes using v_d ->> 'desde', v_d ->> 'hasta';
  else
    execute format('select to_jsonb(t.*) from acta.%I t where codigo = $1', v_ent) into v_antes using v_d ->> 'codigo';
  end if;
  if v_antes is null then perform acta.f_error('No existe ese registro del catálogo', 'P0002'); end if;
  select string_agg(format('%1$I = r.%1$I', c), ', ') into v_set from unnest(v_edit) c where v_d ? c;
  if v_set is null then perform acta.f_error('No hay nada que cambiar'); end if;
  begin
    if v_ent = 'transiciones_caso' then
      execute format('update acta.transiciones_caso t set %s from jsonb_populate_record(null::acta.transiciones_caso, $1) r where t.desde = $2 and t.hasta = $3 returning to_jsonb(t.*)', v_set) into v_despues using v_d, v_d ->> 'desde', v_d ->> 'hasta';
    else
      execute format('update acta.%1$I t set %2$s from jsonb_populate_record(null::acta.%1$I, $1) r where t.codigo = $2 returning to_jsonb(t.*)', v_ent, v_set) using v_d, v_d ->> 'codigo' into v_despues;
    end if;
  exception when unique_violation then perform acta.f_error('Esa condición única ya la cumple otro registro (por ejemplo, ya hay un estado inicial)', '23505');
            when check_violation or not_null_violation then perform acta.f_error('Algún dato no es válido');
  end;
  perform acta.f_auditar(v_email, 'acta_catalogo', v_ent || ':actualizar', jsonb_build_object('antes', v_antes, 'despues', v_despues), p_ip);
  return jsonb_build_object('entidad', v_ent, 'accion', 'actualizar', 'registro', v_despues);
end $_$;


--
-- Name: geoportal_acta_iniciar_correccion(text, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_iniciar_correccion(p_solicitante text, p_acta_id uuid, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_m text; a acta.actas%rowtype; v_r jsonb;
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  v_m := acta.f_motivo(p_motivo);
  select * into a from acta.actas where id = p_acta_id;
  if not found then perform acta.f_error('El acta no existe', 'P0002'); end if;
  v_r := acta.f_abrir(v_email, acta.f_perfil(v_email), a.lat, a.lon, a.precision_m, a.reporte_id, a.id, v_m);
  perform acta.f_auditar(v_email, 'acta_iniciar_correccion', v_r ->> 'acta_id', jsonb_build_object('corrige', a.id, 'consecutivo', a.consecutivo), p_ip);
  return v_r || jsonb_build_object('contenido', acta.f_contenido_editable(a.id),
    'fotos', (select coalesce(jsonb_agg(jsonb_build_object('orden', f.orden, 'tipo', t.codigo, 'detalle', f.detalle) order by f.orden), '[]'::jsonb) from acta.acta_fotos f join acta.tipos_foto t on t.id = f.tipo_foto_id where f.acta_id = a.id));
end $$;


--
-- Name: geoportal_acta_listar(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_listar(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_lim integer; v_filas jsonb; v_sig bigint; v_n integer; v_desde date; v_hasta date; v_ocultas text; v_modo text;
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  if jsonb_typeof(f) <> 'object' then perform acta.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_desde := nullif(f ->> 'desde', '')::date; v_hasta := nullif(f ->> 'hasta', '')::date; v_lim := least(greatest(coalesce((f ->> 'limite')::integer, 50), 1), 200);
  exception when others then perform acta.f_error('Algún filtro tiene un valor no válido');
  end;
  v_ocultas := coalesce(f ->> 'ocultas', 'no'); v_modo := f ->> 'modo';
  if v_ocultas not in ('no', 'si', 'todas') then perform acta.f_error('El filtro «ocultas» debe ser no, si o todas'); end if;
  if v_modo is not null and v_modo not in ('con_contrato', 'sin_contrato', 'contrato_vinculado') then perform acta.f_error('Modo de identificación no válido'); end if;
  with s as (
    select c.* from acta.v_casos c
     where (v_desde is null or c.fecha_acta_fisica >= v_desde) and (v_hasta is null or c.fecha_acta_fisica <= v_hasta)
       and (f ->> 'barrio' is null or c.barrio ilike '%' || (f ->> 'barrio') || '%')
       and (f ->> 'estado' is null or c.estado = f ->> 'estado')
       and (f ->> 'operario' is null or c.autor = lower(f ->> 'operario'))
       and (f ->> 'contrato' is null or c.contrato = f ->> 'contrato' or c.contrato_vinculado = f ->> 'contrato')
       and (f ->> 'nivel_alerta' is null or c.nivel_alerta = f ->> 'nivel_alerta')
       and (f ->> 'numero_fisico' is null or exists (select 1 from acta.actas x where x.acta_raiz_id = c.acta_raiz_id and x.numero_fisico_norm = upper(regexp_replace(f ->> 'numero_fisico', '[^A-Za-z0-9]', '', 'g'))))
       and (f ->> 'tipo_hallazgo' is null or exists (select 1 from acta.acta_hallazgos h join acta.tipos_hallazgo t on t.id = h.tipo_hallazgo_id where h.acta_id = c.acta_id and t.codigo = f ->> 'tipo_hallazgo'))
       and (coalesce((f ->> 'sin_foto_acta_fisica')::boolean, false) = false or c.registro_sin_foto_acta_fisica)
       and (v_modo is null or (v_modo = 'con_contrato' and c.modo_identificacion = 'con_contrato') or (v_modo = 'sin_contrato' and c.modo_identificacion = 'sin_contrato' and c.contrato_vinculado is null)
            or (v_modo = 'contrato_vinculado' and c.contrato_vinculado is not null))
       and (v_ocultas = 'todas' or (v_ocultas = 'si') = c.oculto)
       and (f ->> 'antes_caso_seq' is null or c.caso_seq < (f ->> 'antes_caso_seq')::bigint)
     order by c.caso_seq desc limit v_lim + 1
  )
  select count(*), max(caso_seq) filter (where rn = v_lim), coalesce(jsonb_agg(jsonb_build_object(
      'acta_id', acta_id, 'acta_raiz_id', acta_raiz_id, 'caso_seq', caso_seq, 'consecutivo', consecutivo, 'version', version, 'numero_acta_fisica', numero_acta_fisica,
      'fecha_acta_fisica', fecha_acta_fisica, 'papel_pendiente', papel_pendiente, 'registro_sin_foto_acta_fisica', registro_sin_foto_acta_fisica,
      'modo_identificacion', modo_identificacion, 'contrato', contrato, 'contrato_vinculado', contrato_vinculado, 'direccion', direccion, 'barrio', barrio,
      'estado', estado, 'oculto', oculto, 'custodia', custodia, 'caso_cerrado', caso_cerrado, 'nivel_alerta', nivel_alerta, 'dias_transcurridos', dias_transcurridos,
      'fecha_limite', fecha_limite, 'sin_irregularidad', sin_irregularidad, 'nadie_atendio', nadie_atendio, 'se_nego_a_firmar', se_nego_a_firmar, 'fuera_de_zona', fuera_de_zona,
      'lat', lat, 'lon', lon, 'autor', autor, 'registrado_en', registrado_en,
      -- pasada 14/11: inicio = apertura del registro (servidor), fin = registro (servidor)
      'inicio_en', (select x.inicio_en from acta.actas x where x.id = q.acta_id), 'fin_en', (select x.fin_en from acta.actas x where x.id = q.acta_id)) order by caso_seq desc) filter (where rn <= v_lim), '[]'::jsonb)
    into v_n, v_sig, v_filas
    from (select s.*, row_number() over (order by s.caso_seq desc) as rn from s) q;
  perform acta.f_auditar(v_email, 'acta_listar', null, jsonb_build_object('filtros', (select coalesce(jsonb_agg(k), '[]'::jsonb) from jsonb_object_keys(f) k), 'devueltas', least(v_n, v_lim)), p_ip);
  return jsonb_build_object('filas', v_filas, 'siguiente_antes_caso_seq', case when v_n > v_lim then v_sig end);
end $$;


--
-- Name: geoportal_acta_mis_actas(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_mis_actas(p_solicitante text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_perfil text; v_max integer := acta.f_param('mis_actas_max_filas')::integer; v_vig integer := acta.f_param('vigencia_apertura_horas')::integer;
        v_max_p integer := acta.f_param('max_fotos_acta_fisica')::integer; v_filas jsonb; v_hay boolean;
begin
  v_email := acta.f_autorizar(p_solicitante, 'capturar');
  v_perfil := acta.f_perfil(v_email);
  perform acta.f_cupo_mis_actas(v_email, v_perfil);
  with ap as (
    select a.* from acta.aperturas a where a.autor = v_email and a.correccion_de is null
       and not exists (select 1 from acta.apertura_eventos e where e.apertura_id = a.id and e.tipo_evento = 'cancelar') order by a.abierto_en desc, a.seq desc limit v_max + 1
  ), d as (
    select ap.id, ap.seq, ap.consecutivo, ap.abierto_en, ap.acta_raiz_id, x.id as xid, x.registrado_en, x.modo_identificacion, x.contrato, x.papel_pendiente, acta.f_vigente(ap.acta_raiz_id) as vigente,
           (select count(*) from acta.acta_fotos f join acta.tipos_foto tf on tf.id = f.tipo_foto_id join acta.actas y on y.id = f.acta_id where y.acta_raiz_id = ap.acta_raiz_id and tf.es_acta_fisica)::integer as n_papel,
           (select coalesce(max(f.orden), 0) + 1 from acta.acta_fotos f where f.acta_id = ap.id)::integer as sig_orden,
           acta.f_estado_actual(ap.acta_raiz_id) as estado
      from ap left join acta.actas x on x.id = ap.id
  ), q as (
    select d.*, row_number() over (order by d.abierto_en desc, d.seq desc) as rn from d
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'acta_id', q.id, 'consecutivo', q.consecutivo,
           'situacion', case when q.xid is not null then 'registrada' when q.abierto_en + make_interval(hours => v_vig) < clock_timestamp() then 'abierta_vencida' else 'abierta_en_curso' end,
           'abierto_en', q.abierto_en, 'vence_en', q.abierto_en + make_interval(hours => v_vig), 'registrado_en', q.registrado_en,
           'estado', q.estado, 'estado_nombre', (select e.nombre from acta.estados_caso e where e.codigo = q.estado),
           'modo_identificacion', q.modo_identificacion, 'contrato', q.contrato,
           'papel_pendiente', coalesce(q.papel_pendiente, false), 'fotos_papel', case when q.xid is null then 0 else q.n_papel end, 'tiene_foto_papel', q.xid is not null and q.n_papel > 0,
           'max_fotos_papel', v_max_p,
           'puede_adjuntar_papel', q.xid is not null and q.papel_pendiente and q.vigente = q.id and q.n_papel < v_max_p,
           'siguiente_orden_foto', case when q.xid is null then null else q.sig_orden end,
           'puede_cancelar', q.xid is null) order by q.rn) filter (where q.rn <= v_max), '[]'::jsonb),
         coalesce(bool_or(q.rn > v_max), false)
    into v_filas, v_hay from q;
  perform acta.f_auditar(v_email, 'acta_mis_actas', null, jsonb_build_object('filas', jsonb_array_length(v_filas)), p_ip);
  return jsonb_build_object('filas', v_filas, 'hay_mas', v_hay, 'max_filas', v_max);
end $$;


--
-- Name: geoportal_acta_motivos_cancelacion(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_motivos_cancelacion(p_solicitante text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text;
begin
  v_email := acta.f_autorizar_alguna(p_solicitante, array['capturar', 'supervisar', 'administrar']);
  return jsonb_build_object('motivos', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', m.nombre, 'exige_texto', m.exige_texto) order by m.orden, m.id)
                                                   from acta.motivos_cancelacion m where m.activo), '[]'::jsonb));
end $$;


--
-- Name: geoportal_acta_obtener(text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_obtener(p_solicitante text, p_id uuid, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; a acta.actas%rowtype; v_cap jsonb; v_pers jsonb; v_sello text;
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  v_cap := acta.f_capacidades(v_email);
  select * into a from acta.actas where id = p_id;
  if not found then perform acta.f_error('El acta no existe', 'P0002'); end if;
  select sello_sha256 into v_sello from acta.acta_sellos where acta_id = a.id;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('rol', p.rol, 'nombre', case when (v_cap ->> 'ver_datos_personales')::boolean then p.nombre end, 'email', p.email,
           'calidad', (select codigo from acta.calidades_atendiente where id = p.calidad_id), 'calidad_texto', p.calidad_texto)) order by p.rol), '[]'::jsonb)
    into v_pers from acta.acta_personas p where p.acta_id = a.id;
  perform acta.f_auditar(v_email, 'acta_ver', a.id::text, jsonb_build_object('consecutivo', a.consecutivo, 'version', a.version), p_ip);
  return jsonb_build_object(
    'aviso_registro', 'Registro digital que acompaña al acta física firmada; no la sustituye.',
    'acta', to_jsonb(a) - 'geom' - 'seq' - 'numero_fisico_norm',
    'personas', v_pers,
    'contenido', acta.f_contenido_editable(a.id),
    'fotos', (select coalesce(jsonb_agg(jsonb_build_object('orden', f.orden, 'tipo', t.codigo, 'acta_fisica', t.es_acta_fisica, 'detalle', f.detalle, 'posterior', f.posterior,
                'heredada', f.heredada_de is not null, 'tamano_bytes', f.tamano_bytes, 'sha256', f.sha256, 'registrada_en', f.registrada_en) order by f.orden), '[]'::jsonb)
                from acta.acta_fotos f join acta.tipos_foto t on t.id = f.tipo_foto_id where f.acta_id = a.id),
    'sello_guardado', v_sello, 'sello_coincide', v_sello is not null and v_sello = acta.f_sello(a.id),
    'versiones', (select coalesce(jsonb_agg(jsonb_build_object('acta_id', x.id, 'version', x.version, 'registrado_en', x.registrado_en, 'autor', x.autor, 'motivo_correccion', x.motivo_correccion) order by x.version), '[]'::jsonb) from acta.actas x where x.acta_raiz_id = a.acta_raiz_id),
    'caso', (select to_jsonb(c) - 'geom' from acta.v_casos c where c.acta_raiz_id = a.acta_raiz_id),
    'eventos', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', e.id, 'tipo', e.tipo_evento, 'estado', e.estado_nuevo, 'motivo', e.motivo, 'custodia', e.custodia_codigo,
                'contrato', e.contrato, 'reporte_id', e.reporte_id, 'acta_id', e.acta_id, 'autor', e.autor, 'creado_en', e.creado_en)) order by e.id), '[]'::jsonb) from acta.caso_eventos e where e.acta_raiz_id = a.acta_raiz_id));
end $$;


--
-- Name: geoportal_acta_obtener_formulario(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_obtener_formulario(p_solicitante text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_cap jsonb;
begin
  v_email := acta.f_autorizar(p_solicitante, 'capturar');
  v_cap := acta.f_capacidades(v_email);
  return jsonb_build_object(
    'capacidades', v_cap,
    'aviso_registro', 'Este es el REGISTRO DIGITAL que acompaña al acta física firmada. No sustituye al papel: el acta física es el documento con valor probatorio. Escriba en el papel el consecutivo que le entrega el sistema.',
    'tipos_hallazgo', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'nota', nota, 'exige_texto', exige_texto, 'excluyente', excluyente, 'habilita_accion', habilita_accion_codigo) order by orden, id) from acta.tipos_hallazgo where activo), '[]'),
    'calidades_atendiente', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'exige_texto', exige_texto) order by orden, id) from acta.calidades_atendiente where activo), '[]'),
    'estados_medidor', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden, id) from acta.estados_medidor where activo), '[]'),
    'estados_sellos', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden, id) from acta.estados_sellos where activo), '[]'),
    'diametros', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden, id) from acta.diametros_acometida where activo), '[]'),
    'acciones', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'campos', campos) order by orden, id) from acta.acciones_correctivas where activo), '[]'),
    'tipos_foto', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'exigida_con_irregularidad', exigida_con_irregularidad, 'acta_fisica', es_acta_fisica) order by orden, id) from acta.tipos_foto where activo), '[]'),
    'limites', jsonb_build_object(
        'min_fotos_irregularidad', acta.f_param('min_fotos_irregularidad'), 'min_fotos_sin_irregularidad', acta.f_param('min_fotos_sin_irregularidad'),
        'max_fotos', acta.f_param('max_fotos'), 'max_fotos_acta_fisica', acta.f_param('max_fotos_acta_fisica'),
        'max_bytes_foto', acta.f_param('max_bytes_foto'), 'max_bytes_foto_acta_fisica', acta.f_param('max_bytes_foto_acta_fisica'),
        'vigencia_apertura_horas', acta.f_param('vigencia_apertura_horas'), 'max_dias_acta_fisica_atras', acta.f_param('max_dias_acta_fisica_atras')),
    'zona', jsonb_build_object('lat_min', acta.f_param('zona_lat_min'), 'lat_max', acta.f_param('zona_lat_max'), 'lon_min', acta.f_param('zona_lon_min'), 'lon_max', acta.f_param('zona_lon_max')));
end $$;


--
-- Name: geoportal_acta_ocultar(text, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_ocultar(p_solicitante text, p_acta_raiz_id uuid, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_m text;
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  perform acta.f_exigir_caso(p_acta_raiz_id); v_m := acta.f_motivo(p_motivo);
  if acta.f_oculto(p_acta_raiz_id) then perform acta.f_error('El caso ya está oculto', '55000'); end if;
  insert into acta.caso_eventos (acta_raiz_id, tipo_evento, motivo, autor) values (p_acta_raiz_id, 'ocultar', v_m, v_email);
  perform acta.f_auditar(v_email, 'acta_ocultar', p_acta_raiz_id::text, '{}'::jsonb, p_ip);
  return jsonb_build_object('acta_raiz_id', p_acta_raiz_id, 'oculto', true);
end $$;


--
-- Name: geoportal_acta_precargar_predio(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_precargar_predio(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $_$
declare v_email text; v_c text := nullif(btrim(coalesce(p_contrato, '')), ''); r record; v_existe boolean; v_uso text; v_barrio_ok boolean;
begin
  v_email := acta.f_autorizar(p_solicitante, 'capturar');
  if v_c is null or v_c !~ '^[A-Za-z0-9-]{1,20}$' then perform acta.f_error('El contrato solo puede llevar letras, números y guiones (máximo 20)'); end if;
  perform acta.f_cupo_precargas(v_email, acta.f_perfil(v_email));
  select c.direccion, c.barrio, c.estrato, c.clase_uso, count(*) over () as n into r
    from public.catastro_valledupar c where c.cod_usuario = v_c order by c.id limit 1;
  v_existe := found;
  insert into acta.consultas_contrato (autor, contrato, existe) values (v_email, v_c, v_existe);
  perform acta.f_auditar(v_email, 'acta_precargar_predio', null, jsonb_build_object('existe', v_existe), p_ip);   -- el contrato consultado no se copia a la auditoría
  if not v_existe then return jsonb_build_object('existe', false); end if;
  -- el uso viene sucio («RESIDENCIAL RESIDENCIAL»): se colapsan espacios y palabras repetidas
  select string_agg(w, ' ' order by o) into v_uso from (select w, min(o) o from regexp_split_to_table(regexp_replace(btrim(coalesce(r.clase_uso, '')), '\s+', ' ', 'g'), ' ') with ordinality t(w, o) where w <> '' group by w) x;
  v_barrio_ok := exists (select 1 from public.barrios_valledupar b where lower(btrim(b.nombre)) = lower(btrim(coalesce(r.barrio, ''))));
  return jsonb_build_object('existe', true, 'direccion', nullif(btrim(r.direccion), ''), 'barrio', nullif(btrim(r.barrio), ''), 'barrio_en_lista', v_barrio_ok,
                            'estrato', nullif(btrim(r.estrato), ''), 'estrato_codigo_no_estandar', coalesce(btrim(r.estrato) not in ('1', '2', '3', '4', '5', '6'), false) and nullif(btrim(r.estrato), '') is not null,
                            'uso', v_uso, 'predios_con_ese_contrato', r.n);   -- estratos como 0, 9 o 99 se muestran TAL CUAL, marcados como «código no estándar» (sin interpretarlos)
end $_$;


--
-- Name: geoportal_acta_predios_cercanos(text, numeric, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_predios_cercanos(p_solicitante text, p_lat numeric, p_lon numeric, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_d numeric := acta.f_param('distancia_sugerencia_m'); v_n integer; v_lista jsonb;
begin
  v_email := acta.f_autorizar(p_solicitante, 'capturar');
  if p_lat is null or p_lon is null or p_lat < -90 or p_lat > 90 or p_lon < -180 or p_lon > 180 then perform acta.f_error('La coordenada no es válida'); end if;
  perform acta.f_cupo_precargas(v_email, acta.f_perfil(v_email));
  select count(*), coalesce(jsonb_agg(x.cod order by x.d) filter (where x.rn <= 5), '[]'::jsonb) into v_n, v_lista from (
    select c.cod_usuario as cod, st_distance(c.geom::geography, st_setsrid(st_makepoint(p_lon::double precision, p_lat::double precision), 4326)::geography) as d,
           row_number() over (order by st_distance(c.geom::geography, st_setsrid(st_makepoint(p_lon::double precision, p_lat::double precision), 4326)::geography)) as rn
      from public.catastro_valledupar c
     where st_dwithin(c.geom::geography, st_setsrid(st_makepoint(p_lon::double precision, p_lat::double precision), 4326)::geography, v_d::double precision)) x;
  insert into acta.consultas_contrato (autor, contrato, existe) values (v_email, 'cercanos', true);
  perform acta.f_auditar(v_email, 'acta_predios_cercanos', null, jsonb_build_object('n', v_n), p_ip);
  return jsonb_build_object('distancia_m', v_d, 'hay_predios_cercanos', v_n > 0, 'cantidad', v_n, 'contratos', v_lista);
end $$;


--
-- Name: geoportal_acta_preparar_subida(text, uuid, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_preparar_subida(p_solicitante text, p_acta_id uuid, p_fotos jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_ap acta.aperturas%rowtype; v_a acta.actas%rowtype; v_n integer; v_f jsonb; v_t acta.tipos_foto%rowtype; v_res jsonb := '[]'::jsonb;
        v_max integer := acta.f_param('max_fotos')::integer + acta.f_param('max_fotos_acta_fisica')::integer; v_orden integer; v_mes text; v_desde integer := 1;
        v_registrada boolean;
begin
  v_email := acta.f_autorizar(p_solicitante, 'capturar');
  if jsonb_typeof(coalesce(p_fotos, 'null'::jsonb)) <> 'array' or jsonb_array_length(p_fotos) < 1 then perform acta.f_error('Indique las fotos que va a subir'); end if;
  v_n := jsonb_array_length(p_fotos);
  select * into v_ap from acta.aperturas where id = p_acta_id;
  if not found or v_ap.autor <> v_email then perform acta.f_error('Identificador de acta no válido'); end if;
  select * into v_a from acta.actas where id = p_acta_id;
  v_registrada := found;
  if v_registrada then
    if not v_a.papel_pendiente or v_a.id <> acta.f_vigente(v_a.acta_raiz_id) then perform acta.f_error('Esta acta ya fue registrada: no admite más fotos', '55000'); end if;
    select coalesce(max(orden), 0) + 1 into v_desde from acta.acta_fotos where acta_id = p_acta_id;
  else
    if v_ap.abierto_en < clock_timestamp() - make_interval(hours => acta.f_param('vigencia_apertura_horas')::integer) then perform acta.f_error('El registro caducó: ábralo de nuevo', '55000'); end if;
    if v_ap.correccion_de is not null then select coalesce(max(f.orden), 0) + 1 into v_desde from acta.acta_fotos f where f.acta_id = v_ap.correccion_de; end if;
  end if;
  if v_n > v_max then perform acta.f_error(format('Máximo %s fotos por acta', v_max)); end if;
  v_mes := to_char(v_ap.abierto_en at time zone 'America/Bogota', 'YYYY-MM');
  if (select count(distinct (e ->> 'orden')::integer) <> v_n or min((e ->> 'orden')::integer) <> v_desde or max((e ->> 'orden')::integer) <> v_desde + v_n - 1 from jsonb_array_elements(p_fotos) e) then
    perform acta.f_error(format('El orden de las fotos debe ir de %s a %s, sin repetir ni saltar', v_desde, v_desde + v_n - 1));
  end if;
  for v_f in select e from jsonb_array_elements(p_fotos) e order by (e ->> 'orden')::integer loop
    v_orden := (v_f ->> 'orden')::integer;
    select * into v_t from acta.tipos_foto where codigo = v_f ->> 'tipo' and activo;
    if not found then perform acta.f_error(format('El tipo de la foto %s no existe o está desactivado', v_orden)); end if;
    if v_registrada and not v_t.es_acta_fisica then perform acta.f_error('Después del registro solo se admite la foto del acta física'); end if;
    v_res := v_res || jsonb_build_object('orden', v_orden, 'tipo', v_t.codigo, 'ruta', 'actas/' || v_mes || '/' || p_acta_id::text || '/fotos/' || v_orden || '.jpg');
  end loop;
  perform acta.f_auditar(v_email, 'acta_preparar_subida', p_acta_id::text, jsonb_build_object('fotos', v_n), p_ip);
  return jsonb_build_object('acta_id', p_acta_id, 'fotos', v_res);
end $$;


--
-- Name: geoportal_acta_registrar(text, uuid, jsonb, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_registrar(p_solicitante text, p_acta_id uuid, p_contenido jsonb, p_huellas jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'storage', 'pg_temp'
    AS $_$
declare
  v_email text; v_perfil text; v_c jsonb := p_contenido; v_h jsonb := coalesce(p_huellas, '{}'::jsonb);
  v_ap acta.aperturas%rowtype; v_prev acta.actas%rowtype; v_dup acta.actas%rowtype; v_ver integer := 1; v_prev_id uuid; v_k text;
  v_modo text; v_contrato text; v_dir text; v_barrio text; v_barrio_id bigint; v_fuera_lista boolean := false; v_estrato text; v_uso text; v_ref text;
  v_tiene_med boolean; v_serie_med text; v_marca text; v_lect numeric; v_est_med bigint; v_est_sel bigint; v_serie_sel text; v_diam bigint;
  v_sin boolean := false; v_desc text; v_nadie boolean; v_dere boolean; v_fo boolean; v_fa boolean; v_neg boolean; v_const text; v_obs text;
  v_num_fis text; v_fecha date; v_pend boolean; v_hoy date := acta.f_hoy_bogota(); v_f_txt text;
  v_hall jsonb; v_hrow jsonb; v_th acta.tipos_hallazgo%rowtype; v_hl jsonb := '[]'::jsonb; v_hab text[] := '{}'::text[];
  v_acc jsonb; v_arow jsonb; v_ac acta.acciones_correctivas%rowtype; v_al jsonb := '[]'::jsonb;
  v_aten jsonb; v_cal acta.calidades_atendiente%rowtype; v_aten_nom text; v_cal_txt text; v_test jsonb; v_test_nom text;
  v_fotos jsonb := coalesce(v_c -> 'fotos', '[]'::jsonb); v_f jsonb; v_orden integer; v_ruta text; v_size bigint; v_mime text; v_tf acta.tipos_foto%rowtype; v_sha text;
  v_fl jsonb := '[]'::jsonb; v_inh jsonb := '[]'::jsonb; v_desde integer := 1; v_nh integer; v_np integer; v_nombre_op text; v_nuevo_est text; v_fin timestamptz; v_reg timestamptz;
  v_max_h integer := acta.f_param('max_fotos')::integer; v_max_p integer := acta.f_param('max_fotos_acta_fisica')::integer;
  v_sello text; v_ntot integer;
begin
  v_email := acta.f_autorizar(p_solicitante, 'capturar');
  v_perfil := acta.f_perfil(v_email);
  if p_acta_id is null then perform acta.f_error('Falta el identificador del acta'); end if;
  if v_c is null or jsonb_typeof(v_c) <> 'object' then perform acta.f_error('El contenido del acta no tiene el formato esperado'); end if;
  if jsonb_typeof(v_h) <> 'object' then perform acta.f_error('Las huellas de las fotos no tienen el formato esperado'); end if;

  -- El cliente no manda fechas, horas, autores ni usuarios (la única fecha permitida es la del papel); solo claves conocidas
  for v_k in select jsonb_object_keys(v_c) loop
    if v_k <> 'fecha_acta_fisica' and v_k ~* '(fecha|hora|autor|usuario|email|solicitante)' then perform acta.f_error(format('El dato «%s» lo fija el servidor: no se acepta', v_k)); end if;
    if v_k <> all (array['modo_identificacion','contrato','direccion','barrio','estrato','uso','referencia_ubicacion','tiene_medidor','medidor_serie','marca','lectura_m3',
                         'estado_medidor','estado_sellos','serie_sellos','diametro','descripcion_hallazgos','hallazgos','acciones','nadie_atendio','derechos_informados',
                         'atendiente','testigo','firmo_operario','firmo_atendiente','se_nego_a_firmar','numero_acta_fisica','fecha_acta_fisica','papel_pendiente',
                         'constancia_operario','observaciones','fotos']) then
      perform acta.f_error(format('El dato «%s» no existe en el formulario', v_k));
    end if;
  end loop;

  -- Apertura: del solicitante, vigente; reintento = misma respuesta
  select * into v_ap from acta.aperturas where id = p_acta_id;
  if not found or v_ap.autor <> v_email then perform acta.f_error('Identificador de acta no válido'); end if;
  select * into v_dup from acta.actas where id = p_acta_id;
  if found then
    return jsonb_build_object('acta_id', v_dup.id, 'consecutivo', v_dup.consecutivo, 'version', v_dup.version, 'registrado_en', v_dup.registrado_en, 'repetido', true, 'aviso_zona', v_dup.fuera_de_zona);
  end if;
  if v_ap.abierto_en < clock_timestamp() - make_interval(hours => acta.f_param('vigencia_apertura_horas')::integer) then perform acta.f_error('El registro caducó: ábralo de nuevo', '55000'); end if;
  if v_ap.correccion_de is not null then
    select * into v_prev from acta.actas where id = v_ap.correccion_de;
    if v_prev.id <> acta.f_vigente(v_prev.acta_raiz_id) then perform acta.f_error('La versión que se corrige ya no es la vigente', '55000'); end if;
    v_ver := v_prev.version + 1; v_prev_id := v_prev.id;
  end if;

  -- Predio
  v_modo := acta.f_txt(v_c, 'modo_identificacion', 20, true);
  if v_modo not in ('con_contrato', 'sin_contrato') then perform acta.f_error('El modo de identificación debe ser con_contrato o sin_contrato'); end if;
  v_contrato := acta.f_txt(v_c, 'contrato', 20);
  if v_modo = 'con_contrato' then
    if v_contrato is null then perform acta.f_error('Indique el contrato o cambie a «sin contrato»'); end if;
    if v_contrato !~ '^[A-Za-z0-9-]{1,20}$' then perform acta.f_error('El contrato solo puede llevar letras, números y guiones (máximo 20)'); end if;
    if not acta.f_contrato_existe(v_contrato) then perform acta.f_error('Ese contrato no existe: corríjalo o registre el predio como «sin contrato»'); end if;
  elsif v_contrato is not null then perform acta.f_error('Un registro «sin contrato» no lleva número de contrato');
  end if;
  v_dir := acta.f_txt(v_c, 'direccion', 300, true);
  if length(v_dir) < 3 then perform acta.f_error('La dirección es demasiado corta'); end if;
  v_barrio := acta.f_txt(v_c, 'barrio', 120, true);
  select b.id, btrim(b.nombre) into v_barrio_id, v_barrio from public.barrios_valledupar b where lower(btrim(b.nombre)) = lower(v_barrio) order by b.id limit 1;
  if v_barrio_id is null then v_fuera_lista := true; v_barrio := acta.f_txt(v_c, 'barrio', 120, true); end if;
  v_estrato := acta.f_txt(v_c, 'estrato', 20); v_uso := acta.f_txt(v_c, 'uso', 80); v_ref := acta.f_txt(v_c, 'referencia_ubicacion', 300);

  -- Medidor
  v_tiene_med := acta.f_bool(v_c, 'tiene_medidor', true);
  v_serie_med := acta.f_txt(v_c, 'medidor_serie', 40); v_marca := acta.f_txt(v_c, 'marca', 60); v_lect := acta.f_num(v_c, 'lectura_m3', 0, 99999999);
  if not v_tiene_med and (v_serie_med is not null or v_marca is not null or v_lect is not null or acta.f_txt(v_c, 'estado_medidor', 60) is not null) then
    perform acta.f_error('Si no hay medidor, no se llenan los datos del medidor');
  end if;
  if v_tiene_med then
    select id into v_est_med from acta.estados_medidor where codigo = acta.f_txt(v_c, 'estado_medidor', 60, true) and activo;
    if v_est_med is null then perform acta.f_error('El estado del medidor no existe o está desactivado'); end if;
  end if;
  if acta.f_txt(v_c, 'estado_sellos', 60) is not null then
    select id into v_est_sel from acta.estados_sellos where codigo = acta.f_txt(v_c, 'estado_sellos', 60) and activo;
    if v_est_sel is null then perform acta.f_error('El estado de los sellos no existe o está desactivado'); end if;
  end if;
  v_serie_sel := acta.f_txt(v_c, 'serie_sellos', 60);
  if acta.f_txt(v_c, 'diametro', 60) is not null then
    select id into v_diam from acta.diametros_acometida where codigo = acta.f_txt(v_c, 'diametro', 60) and activo;
    if v_diam is null then perform acta.f_error('El diámetro de la acometida no existe o está desactivado'); end if;
  end if;

  -- Hallazgos (la irregularidad se DERIVA: «Sin irregularidad» es un tipo excluyente del catálogo)
  v_hall := coalesce(v_c -> 'hallazgos', '[]'::jsonb);
  if jsonb_typeof(v_hall) <> 'array' or jsonb_array_length(v_hall) < 1 then perform acta.f_error('Marque al menos un hallazgo (o «Sin irregularidad»)'); end if;
  if (select count(distinct e ->> 'codigo') <> count(*) from jsonb_array_elements(v_hall) e) then perform acta.f_error('Hay hallazgos repetidos'); end if;
  for v_hrow in select e from jsonb_array_elements(v_hall) e loop
    select * into v_th from acta.tipos_hallazgo where codigo = v_hrow ->> 'codigo' and activo;
    if not found then perform acta.f_error('Un tipo de hallazgo no existe o está desactivado'); end if;
    if v_th.excluyente then v_sin := true; end if;
    if v_th.exige_texto and length(coalesce(btrim(v_hrow ->> 'texto_otro'), '')) < 3 then perform acta.f_error(format('«%s» exige describirlo', v_th.nombre)); end if;
    if length(coalesce(v_hrow ->> 'texto_otro', '')) > 300 then perform acta.f_error('El texto del hallazgo es demasiado largo (máximo 300 caracteres)'); end if;
    if v_th.habilita_accion_codigo is not null then v_hab := v_hab || v_th.habilita_accion_codigo; end if;
    v_hl := v_hl || jsonb_build_object('id', v_th.id, 'texto', nullif(btrim(coalesce(v_hrow ->> 'texto_otro', '')), ''));
  end loop;
  if v_sin and jsonb_array_length(v_hall) > 1 then perform acta.f_error('«Sin irregularidad» no se combina con otros hallazgos'); end if;
  v_desc := acta.f_txt(v_c, 'descripcion_hallazgos', 4000);
  if not v_sin and (v_desc is null or length(v_desc) < 10) then perform acta.f_error('Describa los hallazgos (mínimo 10 caracteres)'); end if;

  -- Acciones correctivas (catálogo con campos)
  v_acc := coalesce(v_c -> 'acciones', '[]'::jsonb);
  if jsonb_typeof(v_acc) <> 'array' then perform acta.f_error('Las acciones no vienen en el formato esperado'); end if;
  if v_sin and jsonb_array_length(v_acc) > 0 then perform acta.f_error('Un registro «Sin irregularidad» no lleva acciones correctivas'); end if;
  if (select count(distinct e ->> 'codigo') <> count(*) from jsonb_array_elements(v_acc) e) then perform acta.f_error('Hay acciones repetidas'); end if;
  for v_arow in select e from jsonb_array_elements(v_acc) e loop
    select * into v_ac from acta.acciones_correctivas where codigo = v_arow ->> 'codigo' and activo;
    if not found then perform acta.f_error('Una acción correctiva no existe o está desactivada'); end if;
    if exists (select 1 from acta.tipos_hallazgo h where h.activo and h.habilita_accion_codigo = v_ac.codigo) and not (v_ac.codigo = any (v_hab)) then
      perform acta.f_error(format('La acción «%s» solo procede con el hallazgo que la habilita', v_ac.nombre));
    end if;
    v_al := v_al || jsonb_build_object('id', v_ac.id, 'detalle', acta.f_validar_detalle(v_ac.nombre, v_ac.campos, v_arow -> 'detalle'));
  end loop;

  -- Atención de la visita y firmas DECLARADAS (hechos del papel)
  v_nadie := acta.f_bool(v_c, 'nadie_atendio', true);
  v_fo := acta.f_bool(v_c, 'firmo_operario', true);
  v_fa := acta.f_bool(v_c, 'firmo_atendiente'); v_neg := acta.f_bool(v_c, 'se_nego_a_firmar'); v_dere := case when v_c ? 'derechos_informados' then acta.f_bool(v_c, 'derechos_informados') end;
  v_const := acta.f_txt(v_c, 'constancia_operario', 2000); v_obs := acta.f_txt(v_c, 'observaciones', 2000);
  v_aten := v_c -> 'atendiente'; v_test := v_c -> 'testigo';
  if v_aten is not null and jsonb_typeof(v_aten) = 'null' then v_aten := null; end if;
  if v_test is not null and jsonb_typeof(v_test) = 'null' then v_test := null; end if;
  if v_nadie and v_neg then perform acta.f_error('No puede ser a la vez «nadie atendió» y «se negó a firmar»'); end if;
  if v_nadie then
    if v_aten is not null then perform acta.f_error('Si nadie atendió, no hay atendiente'); end if;
    if v_fa then perform acta.f_error('Si nadie atendió, no firmó ningún atendiente'); end if;
    if v_const is null or length(v_const) < 10 then perform acta.f_error('Si nadie atendió, escriba la constancia del operario'); end if;
  else
    if v_aten is null or jsonb_typeof(v_aten) <> 'object' then perform acta.f_error('Registre quién atendió la visita'); end if;
    v_aten_nom := acta.f_txt(v_aten, 'nombre', 120, true);
    if length(v_aten_nom) < 2 then perform acta.f_error('El nombre del atendiente es demasiado corto'); end if;
    select * into v_cal from acta.calidades_atendiente where codigo = acta.f_txt(v_aten, 'calidad', 60, true) and activo;
    if not found then perform acta.f_error('La calidad del atendiente no existe o está desactivada'); end if;
    v_cal_txt := acta.f_txt(v_aten, 'calidad_texto', 100);
    if v_cal.exige_texto and (v_cal_txt is null or length(v_cal_txt) < 2) then perform acta.f_error(format('«%s» exige describirlo', v_cal.nombre)); end if;
    if not v_cal.exige_texto then v_cal_txt := null; end if;
    if v_neg then
      if v_fa then perform acta.f_error('Si se negó a firmar, no firmó'); end if;
      if v_const is null or length(v_const) < 10 then perform acta.f_error('Si se negó a firmar, escriba la constancia del operario'); end if;
    elsif not v_fa then perform acta.f_error('El atendiente debe haber firmado, o marque que se negó a firmar');
    end if;
  end if;
  if v_neg and (v_test is null or jsonb_typeof(v_test) <> 'object') then perform acta.f_error('Si el atendiente se negó a firmar, registre el nombre del testigo'); end if;
  if v_test is not null then
    if not (v_neg or v_nadie) then perform acta.f_error('El testigo solo aplica si el atendiente se negó a firmar o nadie atendió'); end if;
    v_test_nom := acta.f_txt(v_test, 'nombre', 120, true);
    if length(v_test_nom) < 2 then perform acta.f_error('El nombre del testigo es demasiado corto'); end if;
  end if;
  if not v_fo and (v_const is null or length(v_const) < 10) then perform acta.f_error('Si el operario no firmó, escriba el motivo en la constancia del operario'); end if;

  -- Enlace con el papel
  v_num_fis := acta.f_txt(v_c, 'numero_acta_fisica', 30);
  v_f_txt := acta.f_txt(v_c, 'fecha_acta_fisica', 10, true);
  begin
    if v_f_txt !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'x'; end if;
    v_fecha := v_f_txt::date;
  exception when others then perform acta.f_error('La fecha del acta física debe ser AAAA-MM-DD y existir');
  end;
  if v_fecha > v_hoy then perform acta.f_error('La fecha del acta física no puede ser futura'); end if;
  if v_ap.correccion_de is null and v_fecha < v_hoy - acta.f_param('max_dias_acta_fisica_atras')::integer then
    perform acta.f_error(format('La fecha del acta física no puede ser anterior a %s días', acta.f_param('max_dias_acta_fisica_atras')::integer));
  end if;
  if v_num_fis is not null and exists (select 1 from acta.actas x where x.numero_fisico_norm = upper(regexp_replace(v_num_fis, '[^A-Za-z0-9]', '', 'g')) and x.acta_raiz_id <> v_ap.acta_raiz_id) then
    perform acta.f_error('Ese número de acta física ya está registrado en otro caso. Si lo digitó mal, corríjalo', '23505');
  end if;
  v_pend := acta.f_bool(v_c, 'papel_pendiente');

  -- Fotos: heredadas de la versión anterior (corrección) + las nuevas, con ruta propia, huella y objeto realmente subido
  if jsonb_typeof(v_fotos) <> 'array' then perform acta.f_error('Las fotos no vienen en el formato esperado'); end if;
  if v_prev_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('orden', f.orden, 'tipo_id', f.tipo_foto_id, 'ruta', f.ruta_storage, 'sha', f.sha256, 'tam', f.tamano_bytes, 'mime', f.tipo_mime, 'detalle', f.detalle,
                                                'de', coalesce(f.heredada_de, f.acta_id)) order by f.orden), '[]'::jsonb), coalesce(max(f.orden), 0) + 1
      into v_inh, v_desde from acta.acta_fotos f where f.acta_id = v_prev_id;
  end if;
  if jsonb_array_length(v_fotos) > 0 and (select count(distinct (e ->> 'orden')::integer) <> count(*) or min((e ->> 'orden')::integer) <> v_desde or max((e ->> 'orden')::integer) <> v_desde + jsonb_array_length(v_fotos) - 1
                                          from jsonb_array_elements(v_fotos) e) then
    perform acta.f_error(format('El orden de las fotos nuevas debe ir de %s a %s, sin repetir ni saltar', v_desde, v_desde + jsonb_array_length(v_fotos) - 1));
  end if;
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'orden')::integer loop
    v_orden := (v_f ->> 'orden')::integer;
    select * into v_tf from acta.tipos_foto where codigo = v_f ->> 'tipo' and activo;
    if not found then perform acta.f_error(format('El tipo de la foto %s no existe o está desactivado', v_orden)); end if;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^actas/[0-9]{4}-[0-9]{2}/' || p_acta_id::text || '/fotos/' || v_orden || '\.jpg$') then
      perform acta.f_error(format('La ruta de la foto %s no corresponde a esta acta', v_orden));
    end if;
    v_sha := v_h ->> v_orden::text;
    if v_sha is null or v_sha !~ '^[0-9a-f]{64}$' then perform acta.f_error(format('Falta la huella de la foto %s', v_orden)); end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime from storage.objects o where o.bucket_id = 'acta-evidencias' and o.name = v_ruta;
    if not found then perform acta.f_error(format('No se encontró la foto %s: súbala de nuevo', v_orden)); end if;
    if coalesce(v_size, 0) <= 0 then perform acta.f_error(format('La foto %s está vacía', v_orden)); end if;
    if v_size > (case when v_tf.es_acta_fisica then acta.f_param('max_bytes_foto_acta_fisica') else acta.f_param('max_bytes_foto') end) then perform acta.f_error(format('La foto %s pesa más de lo permitido', v_orden)); end if;
    if v_mime is distinct from 'image/jpeg' then perform acta.f_error(format('La foto %s debe ser JPEG', v_orden)); end if;
    v_fl := v_fl || jsonb_build_object('orden', v_orden, 'tipo_id', v_tf.id, 'ruta', v_ruta, 'sha', v_sha, 'tam', v_size, 'mime', v_mime, 'detalle', acta.f_txt(v_f, 'detalle', 200), 'de', null);
  end loop;
  -- conteos sobre el conjunto completo (heredadas + nuevas)
  select count(*) filter (where not tf.es_acta_fisica), count(*) filter (where tf.es_acta_fisica), count(*)
    into v_nh, v_np, v_ntot
    from (select (e ->> 'tipo_id')::bigint as tid from jsonb_array_elements(v_inh || v_fl) e) x join acta.tipos_foto tf on tf.id = x.tid;
  if v_nh > v_max_h then perform acta.f_error(format('Máximo %s fotos del hallazgo', v_max_h)); end if;
  if v_np > v_max_p then perform acta.f_error(format('Máximo %s fotos del acta física', v_max_p)); end if;
  if v_sin then
    if v_nh < acta.f_param('min_fotos_sin_irregularidad') then perform acta.f_error(format('Tome al menos %s foto(s) del predio', acta.f_param('min_fotos_sin_irregularidad')::integer)); end if;
  else
    if v_nh < acta.f_param('min_fotos_irregularidad') then perform acta.f_error(format('Con irregularidad se necesitan al menos %s fotos del hallazgo', acta.f_param('min_fotos_irregularidad')::integer)); end if;
    if exists (select 1 from acta.tipos_foto tf where tf.activo and tf.exigida_con_irregularidad and not exists (select 1 from jsonb_array_elements(v_inh || v_fl) e where (e ->> 'tipo_id')::bigint = tf.id)) then
      perform acta.f_error('Faltan fotos de los tipos obligatorios (por ejemplo fachada y hallazgo)');
    end if;
  end if;
  if v_pend then
    if v_np > 0 then perform acta.f_error('Quite la marca «papel pendiente»: ya adjuntó la foto del acta física'); end if;
  elsif v_np < 1 then perform acta.f_error('Falta la foto del acta física firmada (o marque «papel pendiente» y adjúntela al volver)');
  end if;

  -- Inserción (una sola transacción; una carrera por el mismo acta_id se resuelve como «repetido»)
  select coalesce(nullif(btrim(lb.nombre), ''), split_part(v_email, '@', 1)) into v_nombre_op from public.geoportal_lista_blanca lb where lb.email = v_email;
  v_nombre_op := coalesce(v_nombre_op, split_part(v_email, '@', 1));
  v_fin := clock_timestamp();
  begin
    insert into acta.actas (id, consecutivo, serie, numero, version, acta_raiz_id, version_anterior_id, motivo_correccion, numero_acta_fisica, fecha_acta_fisica, papel_pendiente,
        modo_identificacion, contrato, direccion, barrio, barrio_id, barrio_fuera_de_lista, estrato, uso, referencia_ubicacion, lat, lon, precision_m, fuera_de_zona,
        tiene_medidor, medidor_serie, marca, lectura_m3, estado_medidor_id, estado_sellos_id, serie_sellos, diametro_id, sin_irregularidad, descripcion_hallazgos,
        nadie_atendio, derechos_informados, firmo_operario, firmo_atendiente, se_nego_a_firmar, constancia_operario, observaciones, inicio_en, fin_en, registrado_en, autor, reporte_id)
    values (p_acta_id, v_ap.consecutivo, v_ap.serie, v_ap.numero, v_ver, v_ap.acta_raiz_id, v_prev_id, v_ap.motivo_correccion, v_num_fis, v_fecha, v_pend,
        v_modo, v_contrato, v_dir, v_barrio, v_barrio_id, v_fuera_lista, v_estrato, v_uso, v_ref, v_ap.lat, v_ap.lon, v_ap.precision_m, v_ap.fuera_de_zona,
        v_tiene_med, v_serie_med, v_marca, v_lect, v_est_med, v_est_sel, v_serie_sel, v_diam, v_sin, v_desc,
        v_nadie, v_dere, v_fo, v_fa, v_neg, v_const, v_obs, v_ap.abierto_en, v_fin, v_fin, v_email, v_ap.reporte_id)
    returning registrado_en into v_reg;
  exception when unique_violation then
    select * into v_dup from acta.actas where id = p_acta_id;
    if found and v_dup.autor = v_email then
      return jsonb_build_object('acta_id', v_dup.id, 'consecutivo', v_dup.consecutivo, 'version', v_dup.version, 'registrado_en', v_dup.registrado_en, 'repetido', true, 'aviso_zona', v_dup.fuera_de_zona);
    end if;
    if sqlerrm like '%numero_fisico%' or sqlerrm like '%número de acta física%' then perform acta.f_error('Ese número de acta física ya está registrado en otro caso', '23505'); end if;
    perform acta.f_error('Una de las fotos ya está usada en otra acta', '23505');
  end;
  insert into acta.acta_personas (acta_id, rol, nombre, email, origen) values (p_acta_id, 'operario', v_nombre_op, v_email, 'perfil');
  if v_aten_nom is not null then insert into acta.acta_personas (acta_id, rol, nombre, calidad_id, calidad_texto, origen) values (p_acta_id, 'atendiente', v_aten_nom, v_cal.id, v_cal_txt, 'digitado'); end if;
  if v_test_nom is not null then insert into acta.acta_personas (acta_id, rol, nombre, origen) values (p_acta_id, 'testigo', v_test_nom, 'digitado'); end if;
  insert into acta.acta_hallazgos (acta_id, tipo_hallazgo_id, texto_otro) select p_acta_id, (x ->> 'id')::bigint, x ->> 'texto' from jsonb_array_elements(v_hl) x;
  insert into acta.acta_acciones (acta_id, accion_id, detalle) select p_acta_id, (x ->> 'id')::bigint, x -> 'detalle' from jsonb_array_elements(v_al) x;
  insert into acta.acta_fotos (acta_id, orden, tipo_foto_id, ruta_storage, sha256, tamano_bytes, tipo_mime, detalle, heredada_de)
    select p_acta_id, (x ->> 'orden')::smallint, (x ->> 'tipo_id')::bigint, x ->> 'ruta', x ->> 'sha', (x ->> 'tam')::integer, x ->> 'mime', x ->> 'detalle', nullif(x ->> 'de', '')::uuid
      from jsonb_array_elements(v_inh || v_fl) x;
  v_sello := acta.f_sello(p_acta_id);
  insert into acta.acta_sellos (acta_id, sello_sha256) values (p_acta_id, v_sello);
  if v_ver = 1 then
    select codigo into v_nuevo_est from acta.estados_caso where case when v_sin then inicial_sin_irregularidad else inicial end;
    insert into acta.caso_eventos (acta_raiz_id, tipo_evento, estado_nuevo, autor) values (v_ap.acta_raiz_id, 'cambio_estado', v_nuevo_est, 'sistema');
  else
    insert into acta.caso_eventos (acta_raiz_id, tipo_evento, motivo, acta_id, autor) values (v_ap.acta_raiz_id, 'nueva_version', v_ap.motivo_correccion, p_acta_id, v_email);
  end if;
  -- Vínculo opcional con un reporte de campo (80_enlace_campo.sql): solo si está aplicado. El acta funciona completa sin él.
  if v_ver = 1 and v_ap.reporte_id is not null and to_regprocedure('acta.f_vincular_reporte(uuid,uuid,text)') is not null then
    execute 'select acta.f_vincular_reporte($1, $2, $3)' using v_ap.acta_raiz_id, v_ap.reporte_id, v_email;
  end if;
  perform acta.f_auditar(v_email, 'acta_registrar', p_acta_id::text,
    jsonb_build_object('consecutivo', v_ap.consecutivo, 'version', v_ver, 'modo', v_modo, 'sin_irregularidad', v_sin, 'fotos', v_ntot, 'papel_pendiente', v_pend,
                       'fuera_de_zona', v_ap.fuera_de_zona, 'nadie_atendio', v_nadie, 'se_nego_a_firmar', v_neg), p_ip);
  return jsonb_build_object('acta_id', p_acta_id, 'consecutivo', v_ap.consecutivo, 'version', v_ver, 'registrado_en', v_reg, 'repetido', false, 'aviso_zona', v_ap.fuera_de_zona);
end $_$;


--
-- Name: geoportal_acta_reincluir(text, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_reincluir(p_solicitante text, p_acta_raiz_id uuid, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_m text;
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  perform acta.f_exigir_caso(p_acta_raiz_id); v_m := acta.f_motivo(p_motivo);
  if not acta.f_oculto(p_acta_raiz_id) then perform acta.f_error('El caso no está oculto', '55000'); end if;
  insert into acta.caso_eventos (acta_raiz_id, tipo_evento, motivo, autor) values (p_acta_raiz_id, 'reincluir', v_m, v_email);
  perform acta.f_auditar(v_email, 'acta_reincluir', p_acta_raiz_id::text, '{}'::jsonb, p_ip);
  return jsonb_build_object('acta_raiz_id', p_acta_raiz_id, 'oculto', false);
end $$;


--
-- Name: geoportal_acta_vincular_contrato(text, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_acta_vincular_contrato(p_solicitante text, p_acta_raiz_id uuid, p_contrato text, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'pg_temp'
    AS $_$
declare v_email text; v_m text; v_c text := nullif(btrim(coalesce(p_contrato, '')), ''); v_vig acta.actas%rowtype;
begin
  v_email := acta.f_autorizar(p_solicitante, 'supervisar');
  perform acta.f_exigir_caso(p_acta_raiz_id); v_m := acta.f_motivo(p_motivo);
  select * into v_vig from acta.actas where id = acta.f_vigente(p_acta_raiz_id);
  if v_vig.modo_identificacion <> 'sin_contrato' then perform acta.f_error('Solo se vincula contrato a un registro «sin contrato»', '55000'); end if;
  if exists (select 1 from acta.caso_eventos e where e.acta_raiz_id = p_acta_raiz_id and e.tipo_evento = 'vincular_contrato') then perform acta.f_error('Este caso ya tiene un contrato vinculado', '55000'); end if;
  if v_c is null or v_c !~ '^[A-Za-z0-9-]{1,20}$' then perform acta.f_error('El contrato solo puede llevar letras, números y guiones (máximo 20)'); end if;
  if not acta.f_contrato_existe(v_c) then perform acta.f_error('Ese contrato no existe'); end if;
  insert into acta.caso_eventos (acta_raiz_id, tipo_evento, contrato, motivo, autor) values (p_acta_raiz_id, 'vincular_contrato', v_c, v_m, v_email);
  perform acta.f_auditar(v_email, 'acta_vincular_contrato', p_acta_raiz_id::text, '{}'::jsonb, p_ip);
  return jsonb_build_object('acta_raiz_id', p_acta_raiz_id, 'contrato_vinculado', true);
end $_$;


--
-- Name: geoportal_admin_listar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_admin_listar(p_solicitante text) RETURNS TABLE(email text, nombre text, rol text, activo boolean, creado_en timestamp with time zone, ver_explorar boolean, ver_focalizacion boolean, ver_comercial boolean, ver_rutas boolean, ver_dashboard boolean, horario text, dias text, ver_registro_tecnico boolean, ver_dashboard_tecnico boolean, ver_campo boolean, ver_dashboard_campo boolean, ver_acta boolean, ver_dashboard_acta boolean, ver_aseo boolean, ver_dashboard_aseo boolean, ver_analisis_contrato boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select lb.email, lb.nombre, lb.rol, lb.activo, lb.creado_en, lb.ver_explorar, lb.ver_focalizacion, lb.ver_comercial, lb.ver_rutas, lb.ver_dashboard,
         lb.horario, lb.dias, lb.ver_registro_tecnico, lb.ver_dashboard_tecnico, lb.ver_campo, lb.ver_dashboard_campo, lb.ver_acta, lb.ver_dashboard_acta, lb.ver_aseo, lb.ver_dashboard_aseo, lb.ver_analisis_contrato
  from public.geoportal_lista_blanca lb
  where public.geoportal_es_admin(p_solicitante)
  order by lb.creado_en;
$$;


--
-- Name: geoportal_admin_permisos(text, text, boolean, boolean, boolean, boolean, text, text, boolean, boolean, boolean, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_admin_permisos(p_solicitante text, p_email text, p_explorar boolean, p_focalizacion boolean, p_comercial boolean, p_rutas boolean, p_horario text, p_dias text, p_dashboard boolean DEFAULT false, p_registro_tecnico boolean DEFAULT NULL::boolean, p_dashboard_tecnico boolean DEFAULT NULL::boolean, p_ip text DEFAULT NULL::text, p_campo boolean DEFAULT NULL::boolean, p_dashboard_campo boolean DEFAULT NULL::boolean, p_acta boolean DEFAULT NULL::boolean, p_dashboard_acta boolean DEFAULT NULL::boolean, p_aseo boolean DEFAULT NULL::boolean, p_dashboard_aseo boolean DEFAULT NULL::boolean, p_analisis_contrato boolean DEFAULT NULL::boolean) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_antes jsonb; v_despues jsonb;
begin
  if not public.geoportal_es_admin(p_solicitante) then raise exception 'No autorizado'; end if;
  if p_horario not in ('laboral','extendido','sin_restriccion') then raise exception 'Horario inválido'; end if;
  if p_dias not in ('habiles','todos') then raise exception 'Días inválidos'; end if;
  select to_jsonb(lb) - 'creado_en' - 'creado_por' into v_antes from public.geoportal_lista_blanca lb where lb.email = lower(p_email);
  if v_antes is not null and v_antes->>'rol' <> 'admin' and not public.geoportal_aislamiento_verificado()
     and ((p_registro_tecnico is true and (v_antes->>'ver_registro_tecnico')::boolean is not true)
       or (p_dashboard_tecnico is true and (v_antes->>'ver_dashboard_tecnico')::boolean is not true)
       or (p_campo is true and (v_antes->>'ver_campo')::boolean is not true)
       or (p_dashboard_campo is true and (v_antes->>'ver_dashboard_campo')::boolean is not true)
       or (p_acta is true and (v_antes->>'ver_acta')::boolean is not true)
       or (p_dashboard_acta is true and (v_antes->>'ver_dashboard_acta')::boolean is not true)
       or (p_aseo is true and (v_antes->>'ver_aseo')::boolean is not true)
       or (p_dashboard_aseo is true and (v_antes->>'ver_dashboard_aseo')::boolean is not true)) then
    raise exception 'Antes de dar permisos técnicos, de campo, de acta o de aseo debe verificarse el bloqueo de las funciones comerciales (aislamiento)';
  end if;
  update public.geoportal_lista_blanca
  set ver_explorar = p_explorar, ver_focalizacion = p_focalizacion, ver_comercial = p_comercial, ver_rutas = p_rutas, ver_dashboard = p_dashboard,
      ver_registro_tecnico  = coalesce(p_registro_tecnico, ver_registro_tecnico),
      ver_dashboard_tecnico = coalesce(p_dashboard_tecnico, ver_dashboard_tecnico),
      ver_campo             = coalesce(p_campo, ver_campo),
      ver_dashboard_campo   = coalesce(p_dashboard_campo, ver_dashboard_campo),
      ver_acta              = coalesce(p_acta, ver_acta),
      ver_dashboard_acta    = coalesce(p_dashboard_acta, ver_dashboard_acta),
      ver_aseo              = coalesce(p_aseo, ver_aseo),
      ver_dashboard_aseo    = coalesce(p_dashboard_aseo, ver_dashboard_aseo),
      ver_analisis_contrato = coalesce(p_analisis_contrato, ver_analisis_contrato),
      horario = p_horario, dias = p_dias
  where email = lower(p_email);
  if not found then return false; end if;
  select to_jsonb(lb) - 'creado_en' - 'creado_por' into v_despues from public.geoportal_lista_blanca lb where lb.email = lower(p_email);
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
  values (lower(p_solicitante), 'admin_cambiar_permisos', lower(p_email), jsonb_build_object('antes', v_antes, 'despues', v_despues), p_ip);
  return true;
end;
$$;


--
-- Name: geoportal_aislamiento_verificado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_aislamiento_verificado() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$ select coalesce((select aislamiento_tecnica_ok from public.geoportal_config where id = 1), false); $$;


--
-- Name: geoportal_campo_analisis_cercanos(text, numeric, numeric, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_analisis_cercanos(p_solicitante text, p_lat numeric, p_lon numeric, p_precision_m numeric DEFAULT NULL::numeric, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $_$
declare
  v_email   text;
  v_admin   boolean;
  v_lim     integer;
  v_usadas  integer;
  v_primero timestamptz;
  v_pto     geometry;
  v_lista   jsonb;
  v_n       integer;
begin
  v_email := campo.f_autorizar_analisis(p_solicitante);
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 or (p_precision_m is not null and p_precision_m < 0) then
    raise exception 'La ubicación no viene en la forma esperada.' using errcode = '22023', hint = 'msg_usuario';
  end if;
  v_admin := exists (select 1 from public.geoportal_lista_blanca lb where lb.email = v_email and lb.activo and lb.rol = 'admin');
  v_lim := campo.f_param('limite_cercania_dia')::int;
  perform pg_advisory_xact_lock(hashtextextended('campo_cercania:' || v_email, 0));
  select count(*), min(q.consultado_en) into v_usadas, v_primero
    from campo.consultas_cercania q where q.autor = v_email and q.cobrada and q.consultado_en > clock_timestamp() - interval '24 hours';
  if not v_admin and v_usadas >= v_lim then
    perform campo.f_error_limite(format('Llegó al límite de %s búsquedas de contratos cercanos de hoy. Vuelve a tener cupo a las %s.', v_lim,
                                        to_char((v_primero + interval '24 hours') at time zone 'America/Bogota', 'HH24:MI')));
  end if;

  v_pto := st_setsrid(st_makepoint(p_lon::double precision, p_lat::double precision), 4326);
  -- 1) candidatos por KNN (usa el índice GiST); 2) distancia real en metros; 3) un contrato por fila; 4) radio 300 m; 5) los 5 más cercanos
  select coalesce(jsonb_agg(jsonb_build_object('contrato', z.contrato, 'direccion', z.direccion, 'distancia_m', round(z.d)::int) order by z.d, z.contrato), '[]'::jsonb), count(*)
    into v_lista, v_n
    from (select x.* from (select distinct on (k.contrato) k.contrato, k.direccion, k.d
                             from (select btrim(c.cod_usuario) as contrato, nullif(btrim(c.direccion), '') as direccion, st_distancesphere(c.geom, v_pto) as d
                                     from public.catastro_valledupar c
                                    where c.geom is not null and c.cod_usuario ~ '^\d{1,12}$' and c.cod_usuario not in ('0', '99999999')
                                    order by c.geom <-> v_pto
                                    limit 60) k
                            where k.d <= 300
                            order by k.contrato, k.d) x
           order by x.d, x.contrato
           limit 5) z;

  insert into campo.consultas_cercania (autor, lat_red, lon_red, resultados, cobrada, ip)
  values (v_email, round(p_lat, 3), round(p_lon, 3), v_n, not v_admin, left(p_ip, 64));
  perform campo.f_auditar(v_email, 'campo_analisis_cercanos', currval(pg_get_serial_sequence('campo.consultas_cercania', 'id'))::text, jsonb_build_object('resultados', v_n), p_ip);
  select count(*) into v_usadas from campo.consultas_cercania q where q.autor = v_email and q.cobrada and q.consultado_en > clock_timestamp() - interval '24 hours';
  return jsonb_build_object('radio_m', 300, 'contratos', v_lista,
                            'cupo', jsonb_build_object('limite', v_lim, 'usadas', v_usadas, 'restantes', greatest(v_lim - v_usadas, 0), 'sin_limite', v_admin));
end $_$;


--
-- Name: geoportal_campo_analisis_contrato(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_analisis_contrato(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'bi', 'bi_interno', 'pg_temp'
    AS $_$
declare
  v_email   text;
  v_c       text := btrim(coalesce(p_contrato, ''));
  v_existe  boolean;
  v_id      bigint;
  cs        record;
  pr        record;
  f         bi_interno.ficha_contrato%rowtype;
  v_ficha   boolean;
  v_estado  record;
  v_tel     text[];
  v_tel_f   text;
  v_barrio  text;
  v_meses   text[];
  v_hoy     date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_predios jsonb;
  v_n_pred  integer;
  v_prom    jsonb;
begin
  v_email := campo.f_autorizar_analisis(p_solicitante);
  if v_c !~ '^\d{1,12}$' then
    raise exception 'Escriba solo los números del contrato (hasta 12 dígitos).' using errcode = '22023', hint = 'msg_usuario';
  end if;
  -- SIN límite diario (decisión de David, 14/11): cada consulta queda en la bitácora (quién, cuándo, qué contrato), sin tope.

  -- ¿existe? (todo por índice: cartera_suscripcion.contrato, catastro_valledupar.cod_usuario, clave de la ficha)
  select s.* into cs from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select count(*) into v_n_pred from public.catastro_valledupar c where c.cod_usuario = v_c;
  select * into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  v_ficha := found;
  v_existe := cs.contrato is not null or v_n_pred > 0 or v_ficha;

  insert into campo.consultas_analisis (autor, contrato, existe, ip) values (v_email, v_c, v_existe, left(p_ip, 64)) returning id into v_id;
  perform campo.f_auditar(v_email, 'campo_analisis_contrato', v_id::text, jsonb_build_object('existe', v_existe), p_ip);   -- el contrato queda en la bitácora, no en la auditoría (decisión 15)

  if v_c = '99999999' then
    return jsonb_build_object('encontrado', true, 'comodin', true, 'contrato', v_c);
  end if;
  if not v_existe then
    return jsonb_build_object('encontrado', false, 'contrato', v_c);
  end if;

  -- predio principal (menor id) y hasta 5 predios con coordenadas (decisión 20)
  select c.id, c.direccion, c.barrio, c.diam_med, c.telefono, c.telefono_propie, p.estado_predio, p.tramo_mora into pr
    from public.catastro_valledupar c left join public.predios_comercial p on p.id = c.id
   where c.cod_usuario = v_c order by c.id limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('direccion', nullif(btrim(x.direccion), ''), 'barrio', nullif(btrim(x.barrio), ''),
                                               'lat', round(st_y(x.geom)::numeric, 6), 'lon', round(st_x(x.geom)::numeric, 6)) order by x.id), '[]'::jsonb)
    into v_predios
    from (select c.id, c.direccion, c.barrio, c.geom from public.catastro_valledupar c where c.cod_usuario = v_c order by c.id limit 5) x;

  -- teléfonos: los de la cartera diaria; si no hay, los del censo con su rótulo (decisión 11)
  v_tel := campo.f_telefonos(cs.telefono);
  v_tel_f := case when cardinality(v_tel) > 0 then 'cartera' end;
  if cardinality(v_tel) = 0 and pr.id is not null then
    v_tel := campo.f_telefonos(concat_ws(' / ', pr.telefono, pr.telefono_propie));
    v_tel_f := case when cardinality(v_tel) > 0 then 'censo' end;
  end if;

  select * into v_estado from bi_interno.ficha_contrato_estado where id = 1;
  v_barrio := nullif(upper(btrim(coalesce(cs.barrio, ''))), '');

  -- promedios de su estrato, barrio y uso en los mismos 6 meses (null en el mes si el grupo no llega a 30 o falta el mes)
  if v_ficha then
    select array_agg(m ->> 'periodo' order by k) into v_meses from jsonb_array_elements(f.consumo_meses) with ordinality t(m, k);
    select jsonb_object_agg(d.dimension, case when d.grupo is null then null else jsonb_build_object('grupo', d.grupo, 'meses',
             (select jsonb_agg(jsonb_build_object('periodo', mp, 'media', pd.media_m3, 'contratos', pd.contratos) order by mk)
                from unnest(v_meses) with ordinality u(mp, mk)
                left join bi.v_consumo_promedio_dim pd on pd.periodo = u.mp and pd.dimension = d.dimension and pd.grupo = d.grupo)) end)
      into v_prom
      from (values ('estrato', nullif(f.estrato, '(sin dato)')), ('barrio', v_barrio), ('uso', nullif(f.uso, '(sin dato)'))) d(dimension, grupo);
  end if;

  return jsonb_build_object(
    'encontrado', true, 'comodin', false, 'contrato', v_c,
    'suscriptor', jsonb_build_object('nombre', nullif(btrim(cs.nombre), ''), 'telefonos', to_jsonb(coalesce(v_tel, '{}'::text[])), 'telefono_fuente', v_tel_f, 'corte', cs.periodo_carga),
    'comercial', jsonb_build_object(
       'estado', nullif(btrim(cs.estado), ''), 'categoria', nullif(btrim(cs.categoria), ''), 'subcategoria', nullif(btrim(cs.subcategoria), ''),
       'ciclo', nullif(btrim(cs.ciclo), ''), 'ruta', nullif(btrim(cs.ruta), ''),
       'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), '')), 'direccion', coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')),
       'deuda_total', cs.deuda_total, 'saldo_pendiente', cs.saldo_pendiente, 'facturas_pendientes', cs.facturas_pendientes, 'saldo_financiado', cs.saldo_financiado,
       'valor_reclamo', cs.valor_reclamo, 'saldo_a_favor', cs.saldo_a_favor,
       'tramo_mora', pr.tramo_mora, 'estado_predio', nullif(btrim(pr.estado_predio), ''), 'facturas_vencidas', f.facturas_vencidas, 'corte', cs.periodo_carga),
    'medidor', jsonb_build_object(
       'serial', coalesce(case when v_ficha then f.medidor_serial end, nullif(upper(btrim(cs.serial_medidor)), '')),
       'diametro', nullif(btrim(pr.diam_med::text), ''),
       'fecha_instalacion', f.medidor_fecha, 'fecha_estado', coalesce(f.medidor_fecha_estado, 'sin_dato'), 'anios', f.medidor_anios,
       'cambio', coalesce(f.cambio, jsonb_build_object('confirmado', null, 'recodificado', null))),
    'consumo', case when v_ficha then jsonb_build_object('periodo_ultimo', f.periodo_ultimo, 'meses', f.consumo_meses, 'maximo', f.cons_max, 'minimo', f.cons_min,
                                                         'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura) end,
    'promedios', coalesce(v_prom, jsonb_build_object('estrato', null, 'barrio', null, 'uso', null)),
    'submedicion', f.submedicion,
    'pago', case when f.ultimo_pago is not null then f.ultimo_pago - 'corte' || jsonb_build_object('dias', v_hoy - (f.ultimo_pago ->> 'fecha')::date) end,
    'gestiones', jsonb_build_object(
       'emd_facturados', coalesce(f.emd, '[]'::jsonb),
       'terreno', coalesce((select jsonb_agg(jsonb_build_object('tipo', x.codigo, 'tipo_nombre', x.nombre, 'consecutivo', x.consecutivo, 'fecha', x.registrado_en, 'estado', x.estado) order by x.registrado_en desc)
                              from (select distinct on (t.codigo) t.codigo, t.nombre, r.consecutivo, r.registrado_en, r.estado
                                      from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                     where r.contrato = v_c and not r.oculto and t.codigo in ('suspension', 'corte', 'reconexion_servicio', 'reinstalacion', 'verificacion_posterior')
                                     order by t.codigo, r.registrado_en desc) x), '[]'::jsonb),
       'pqr', f.pqr,
       'reportes', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', x.consecutivo, 'tipo', x.codigo, 'tipo_nombre', x.nombre, 'fecha', x.registrado_en, 'estado', x.estado, 'resultado', x.resultado) order by x.registrado_en desc)
                               from (select t.codigo, t.nombre, r.consecutivo, r.registrado_en, r.estado, r.resultado
                                       from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                      where r.contrato = v_c and not r.oculto order by r.registrado_en desc limit 15) x), '[]'::jsonb),
       'reportes_total', (select count(*) from campo.reportes r where r.contrato = v_c),
       'actas', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', a.consecutivo, 'fecha', a.fecha_acta_fisica, 'registrado_en', a.registrado_en) order by a.registrado_en desc)
                            from (select a.consecutivo, a.fecha_acta_fisica, a.registrado_en from acta.v_actas_vigentes a where a.contrato = v_c order by a.registrado_en desc limit 10) a), '[]'::jsonb),
       -- actividades derivadas pendientes (decisión 19, provisional): revisiones con «¿Se requiere cambio de medidor?» = sí y sin instalación posterior
       'pendientes', coalesce((select jsonb_agg(jsonb_build_object('consecutivo', r.consecutivo, 'tipo_nombre', t.nombre, 'fecha', r.registrado_en, 'sugiere', 'cambio_medidor') order by r.registrado_en desc)
                                 from campo.v_reportes_estado r join campo.tipos_reporte t on t.id = r.tipo_id
                                where r.contrato = v_c and not r.oculto and t.codigo in ('revision_previa', 'revision_pqr') and r.datos -> 'req_cambio_medidor' = 'true'::jsonb
                                  and r.estado not in ('descartado', 'duplicado')
                                  and not exists (select 1 from campo.reportes i join campo.tipos_reporte ti on ti.id = i.tipo_id
                                                   where i.contrato = v_c and ti.codigo = 'instalacion_medidor' and i.registrado_en > r.registrado_en)), '[]'::jsonb)),
    'ubicacion', jsonb_build_object('predios_total', v_n_pred, 'predios', v_predios),
    'fotos', '[]'::jsonb,
    'cortes', jsonb_build_object('cartera', cs.periodo_carga, 'consumo', f.periodo_ultimo, 'ficha', v_estado.calculado_en),
    'ficha_disponible', v_estado.id is not null);
end $_$;


--
-- Name: geoportal_campo_cambiar_estado(text, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_cambiar_estado(p_solicitante text, p_id uuid, p_estado text, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_est campo.estados_reporte%rowtype; v_actual text; v_motivo text := nullif(btrim(coalesce(p_motivo, '')), ''); v_ev bigint;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if not exists (select 1 from campo.reportes where id = p_id) then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  select * into v_est from campo.estados_reporte where codigo = btrim(coalesce(p_estado, ''));
  if not found or not v_est.activo then perform campo.f_error('El estado no existe o está desactivado'); end if;
  if not v_est.cambio_manual then perform campo.f_error(format('El estado «%s» no se puede poner a mano', v_est.nombre), '55000'); end if;
  if v_est.exige_motivo and v_motivo is null then perform campo.f_error(format('El estado «%s» exige un motivo (mínimo 10 caracteres)', v_est.nombre)); end if;
  if v_motivo is not null and length(v_motivo) < 10 then perform campo.f_error('El motivo debe tener al menos 10 caracteres'); end if;
  v_actual := campo.f_estado_actual(p_id);
  if v_actual = v_est.codigo then perform campo.f_error('El reporte ya está en ese estado', '55000'); end if;
  insert into campo.reporte_eventos (reporte_id, tipo_evento, estado_nuevo, motivo, autor) values (p_id, 'cambio_estado', v_est.codigo, v_motivo, v_email) returning id into v_ev;
  perform campo.f_auditar(v_email, 'campo_cambiar_estado', p_id::text, jsonb_build_object('de', v_actual, 'a', v_est.codigo, 'motivo', v_motivo), p_ip);
  return jsonb_build_object('id', p_id, 'evento_id', v_ev, 'estado', v_est.codigo, 'estado_anterior', v_actual);
end $$;


--
-- Name: geoportal_campo_catalogo_cambiar(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_catalogo_cambiar(p_solicitante text, p_datos jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $_$
declare v_email text; d jsonb := coalesce(p_datos, '{}'::jsonb); v_cat text; v_tipo text; v_cod text; v_nombre text; v_m text; v_activa boolean; v_actual text; v_ev bigint; v_que text;
begin
  v_email := campo.f_autorizar_admin(p_solicitante);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del cambio no tienen el formato esperado'); end if;
  v_cat := d ->> 'catalogo'; v_tipo := d ->> 'tipo';
  if v_cat is null or v_cat not in ('area', 'actividad') then perform campo.f_error('El catálogo debe ser area o actividad'); end if;
  if v_tipo is null or v_tipo not in ('crear', 'renombrar', 'desactivar', 'activar') then perform campo.f_error('El cambio debe ser crear, renombrar, desactivar o activar'); end if;
  v_que := case v_cat when 'area' then 'un área' else 'una actividad' end;
  v_m := campo.f_motivo_personal(d ->> 'motivo', v_tipo = 'desactivar');
  perform pg_advisory_xact_lock(hashtext('campo_catalogo:' || v_cat));
  if v_tipo in ('crear', 'renombrar') then
    v_nombre := regexp_replace(btrim(coalesce(d ->> 'nombre', '')), '\s+', ' ', 'g');
    if length(v_nombre) < 2 or length(v_nombre) > 60 then perform campo.f_error('El nombre debe tener entre 2 y 60 caracteres'); end if;
  end if;
  if v_tipo = 'crear' then
    v_cod := campo.f_codigo_desde_nombre(v_nombre);
    if v_cod !~ '^[a-z][a-z0-9_]{1,39}$' then perform campo.f_error('El nombre debe empezar con una letra'); end if;
    if (v_cat = 'area' and exists (select 1 from campo.areas_comercial a where lower(a.nombre) = lower(v_nombre) or a.codigo = v_cod))
       or (v_cat = 'actividad' and exists (select 1 from campo.actividades a where lower(a.nombre) = lower(v_nombre) or a.codigo = v_cod)) then
      perform campo.f_error('Ya existe ' || v_que || ' con ese nombre', '55000');
    end if;
    if v_cat = 'area' then
      insert into campo.areas_comercial (codigo, nombre, orden, autor) select v_cod, v_nombre, coalesce(max(orden), 0) + 1, v_email from campo.areas_comercial;
    else
      insert into campo.actividades (codigo, nombre, orden, autor) select v_cod, v_nombre, coalesce(max(orden), 0) + 1, v_email from campo.actividades;
    end if;
  else
    v_cod := nullif(btrim(coalesce(d ->> 'codigo', '')), '');
    if v_cat = 'area' then select a.nombre, a.activa into v_actual, v_activa from campo.areas_comercial a where a.codigo = v_cod;
    else select a.nombre, a.activa into v_actual, v_activa from campo.actividades a where a.codigo = v_cod; end if;
    if v_actual is null then perform campo.f_error('No existe ' || v_que || ' con ese código'); end if;
    if v_tipo = 'renombrar' then
      if v_nombre = v_actual then perform campo.f_error('Ya tiene ese nombre', '55000'); end if;
      if (v_cat = 'area' and exists (select 1 from campo.areas_comercial a where a.codigo <> v_cod and lower(a.nombre) = lower(v_nombre)))
         or (v_cat = 'actividad' and exists (select 1 from campo.actividades a where a.codigo <> v_cod and lower(a.nombre) = lower(v_nombre))) then
        perform campo.f_error('Ya existe ' || v_que || ' con ese nombre', '55000');
      end if;
    elsif v_tipo = 'desactivar' and not v_activa then perform campo.f_error('Ya está desactivada', '55000');
    elsif v_tipo = 'activar' and v_activa then perform campo.f_error('Ya está activa', '55000');
    end if;
    if v_cat = 'area' then
      update campo.areas_comercial set nombre = coalesce(v_nombre, nombre), activa = case v_tipo when 'desactivar' then false when 'activar' then true else activa end where codigo = v_cod;
    else
      update campo.actividades set nombre = coalesce(v_nombre, nombre), activa = case v_tipo when 'desactivar' then false when 'activar' then true else activa end where codigo = v_cod;
    end if;
  end if;
  insert into campo.catalogo_eventos (catalogo, codigo, tipo_evento, nombre, motivo, autor) values (v_cat, v_cod, v_tipo, v_nombre, v_m, v_email) returning id into v_ev;
  perform campo.f_auditar(v_email, 'campo_catalogo_' || v_cat || '_' || v_tipo, v_cod, jsonb_build_object('evento', v_ev), p_ip);
  return jsonb_build_object('codigo', v_cod, 'cambio', true);
end $_$;


--
-- Name: geoportal_campo_catalogo_lectura(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_catalogo_lectura(p_solicitante text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_perfil text; v_todo boolean; v_sup boolean; v_max integer := campo.f_param('max_fotos')::integer;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);   -- supervisor de campo o administrador
  v_perfil := campo.f_perfil(v_email);
  v_todo := true;   -- lectura completa: activos e inactivos
  v_sup := v_perfil in ('admin', 'supervisor');
  return jsonb_build_object(
    'solo_lectura', v_perfil <> 'admin',
    -- estado de constancias, de solo lectura (mismo contenido que geoportal_envio_estado, que sigue siendo del administrador)
    'constancias', jsonb_build_object(
      'texto', (select jsonb_build_object('version', x.version, 'borrador', x.borrador, 'texto', x.texto) from salida.f_texto_vigente() x),
      'documentos', (select coalesce(jsonb_agg(jsonb_build_object('documento', c.documento, 'habilitado', c.habilitado, 'copias_internas', to_jsonb(c.copias_internas)) order by c.documento), '[]'::jsonb) from salida.config_documentos c),
      'cola', (select coalesce(jsonb_object_agg(s.estado, s.n), '{}'::jsonb) from (select estado, count(*) n from salida.envios group by estado) s),
      'fallos_ultimos_30_dias', (select count(*) from salida.fallos_encolado f where f.creado_en > clock_timestamp() - interval '30 days'))
  ) || jsonb_build_object(
    'perfil', v_perfil,
    'puede', jsonb_build_object('reportar', true, 'crear_desde_escritorio', v_sup, 'supervisar', v_sup, 'administrar_catalogo', v_perfil = 'admin'),
    'limites', jsonb_build_object('max_fotos', v_max, 'min_fotos_campo', 1,
                                  'max_bytes_foto', campo.f_param('max_bytes_foto')::bigint, 'tipo_mime', 'image/jpeg',
                                  'max_bytes_datos', 4096, 'etiqueta_foto_adicional', 'adicional',
                                  'max_descripcion', campo.f_param('max_descripcion')::integer),
    'zona', jsonb_build_object('lat_min', campo.f_param('zona_lat_min'), 'lat_max', campo.f_param('zona_lat_max'),
                               'lon_min', campo.f_param('zona_lon_min'), 'lon_max', campo.f_param('zona_lon_max')),
    'grupos', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre, 'orden', g.orden, 'activo', g.activo,
        'tipos', coalesce((
          select jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre, 'orden', t.orden, 'activo', t.activo,
                   'exige_texto', t.exige_texto, 'exige_subtipo', t.exige_subtipo,
                   'tiene_subtipos', exists (select 1 from campo.subtipos_reporte s0 where s0.tipo_id = t.id and (v_todo or s0.activo)),
                   'subtipos', coalesce((select jsonb_agg(jsonb_build_object('codigo', s.codigo, 'nombre', s.nombre, 'orden', s.orden, 'activo', s.activo) order by s.orden, s.id)
                                           from campo.subtipos_reporte s where s.tipo_id = t.id and (v_todo or s.activo)), '[]'::jsonb))
                   -- Paso D
                   || jsonb_build_object(
                   'fotos_min', coalesce(t.fotos_min, 1), 'fotos_max', coalesce(t.fotos_max, v_max),
                   'requiere_contrato', t.requiere_contrato, 'genera_resultado', t.genera_resultado, 'usa_consecutivo', t.prefijo_consecutivo is not null,
                   'campos', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'tipo_dato', c.tipo_dato, 'obligatorio', c.obligatorio,
                                                'opciones', (select jsonb_agg(jsonb_build_object('codigo', o ->> 'codigo', 'nombre', o ->> 'nombre', 'activo', coalesce((o ->> 'activo')::boolean, true)) order by n)
                                                               from jsonb_array_elements(c.opciones) with ordinality x(o, n) where v_todo or coalesce((o ->> 'activo')::boolean, true)),
                                                'minimo', c.minimo, 'maximo', case when c.tipo_dato = 'texto' then coalesce(c.maximo, 300) else c.maximo end,
                                                'unidad', c.unidad, 'ayuda', c.ayuda, 'sensible', c.sensible, 'seccion', c.seccion, 'visible_si', c.visible_si, 'orden', c.orden, 'activo', c.activo)) order by c.orden, c.id)
                                         from campo.tipo_campos c where c.tipo_id = t.id and (v_todo or c.activo)), '[]'::jsonb),
                   'fotos', coalesce((select jsonb_agg(jsonb_build_object('codigo', tf.codigo, 'nombre', tf.nombre, 'obligatoria', tf.obligatoria, 'soporte_inefectiva', tf.soporte_inefectiva, 'orden', tf.orden, 'activo', tf.activo) order by tf.orden, tf.id)
                                        from campo.tipo_fotos tf where tf.tipo_id = t.id and (v_todo or tf.activo)), '[]'::jsonb),
                   'causales', case when not t.genera_resultado then '[]'::jsonb else coalesce((
                                 select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre) order by c.orden, c.id) from campo.causales c
                                  where c.activo and (c.general or exists (select 1 from campo.causales_tipos ct where ct.causal_id = c.id and ct.tipo_id = t.id and ct.activo))), '[]'::jsonb) end)
                   || case when v_todo then jsonb_build_object('prefijo_consecutivo', t.prefijo_consecutivo, 'limite_ventana', t.limite_ventana,
                                                               'fotos_min_propio', t.fotos_min, 'fotos_max_propio', t.fotos_max) else '{}'::jsonb end
                   order by t.orden, t.id)
            from campo.tipos_reporte t where t.grupo_id = g.id and (v_todo or t.activo)), '[]'::jsonb))
        order by g.orden, g.id)
        from campo.grupos_reporte g where (v_todo or g.activo)), '[]'::jsonb),
    'estados', case when not v_sup then null else coalesce((
      select jsonb_agg(jsonb_build_object('codigo', e.codigo, 'nombre', e.nombre, 'orden', e.orden, 'activo', e.activo,
                                          'exige_motivo', e.exige_motivo, 'cambio_manual', e.cambio_manual) order by e.orden, e.codigo)
        from campo.estados_reporte e where v_todo or e.activo), '[]'::jsonb) end,
    'causales', case when not v_sup then null else coalesce((
      select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'general', c.general, 'orden', c.orden, 'activo', c.activo,
                                          'tipos', coalesce((select jsonb_agg(t.codigo order by t.codigo) from campo.causales_tipos ct join campo.tipos_reporte t on t.id = ct.tipo_id
                                                              where ct.causal_id = c.id and ct.activo), '[]'::jsonb)) order by c.orden, c.id)
        from campo.causales c where v_todo or c.activo), '[]'::jsonb) end,
    -- Paso C: los parámetros los ve SIEMPRE el administrador (con quién y cuándo los cambió); alerta_base_pct no se muestra (es de la verificación)
    'parametros', case when not v_sup then null else coalesce((
      select jsonb_agg(jsonb_build_object('clave', p.clave, 'valor', p.valor, 'unidad', p.unidad, 'descripcion', p.descripcion,
                                          'minimo', p.minimo, 'maximo', p.maximo, 'actualizado_en', p.actualizado_en, 'actualizado_por', p.actualizado_por) order by p.clave)
        from campo.parametros p where p.clave <> 'alerta_base_pct'), '[]'::jsonb) end,
    -- Paso C: definiciones de campos y fotos de TODOS los tipos, aun los desactivados, para que el supervisor etiquete datos de reportes viejos
    'definiciones', case when not v_sup then null else coalesce((
      select jsonb_agg(jsonb_build_object('tipo', t.codigo,
        'campos', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'tipo_dato', c.tipo_dato, 'unidad', c.unidad, 'sensible', c.sensible, 'activo', c.activo, 'seccion', c.seccion, 'orden', c.orden,
                                      'opciones', (select jsonb_agg(jsonb_build_object('codigo', o ->> 'codigo', 'nombre', o ->> 'nombre')) from jsonb_array_elements(c.opciones) o))) order by c.orden, c.id)
                              from campo.tipo_campos c where c.tipo_id = t.id), '[]'::jsonb),
        'fotos', coalesce((select jsonb_agg(jsonb_build_object('codigo', tf.codigo, 'nombre', tf.nombre, 'activo', tf.activo) order by tf.orden, tf.id) from campo.tipo_fotos tf where tf.tipo_id = t.id), '[]'::jsonb))
        order by t.orden, t.id) from campo.tipos_reporte t), '[]'::jsonb) end);
end $$;


--
-- Name: FUNCTION geoportal_campo_catalogo_lectura(p_solicitante text, p_ip text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.geoportal_campo_catalogo_lectura(p_solicitante text, p_ip text) IS 'Pasada 14/11: lectura completa del catálogo, los parámetros y el estado de constancias para el supervisor de campo y el administrador. No escribe nada.';


--
-- Name: geoportal_campo_catalogos(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_catalogos(p_solicitante text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  return jsonb_build_object(
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'activa', a.activa, 'orden', a.orden) order by a.orden, a.codigo), '[]'::jsonb) from campo.areas_comercial a),
    'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'activa', a.activa, 'orden', a.orden) order by a.orden, a.codigo), '[]'::jsonb) from campo.actividades a));
end $$;


--
-- Name: geoportal_campo_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, text, jsonb, text, jsonb, text, text, uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_origen text, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_orden_trabajo_id uuid DEFAULT NULL::uuid, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'storage', 'pg_temp'
    AS $_$
declare
  v_email text; v_perfil text; v_origen text := coalesce(p_origen, ''); v_maxdesc integer := campo.f_param('max_descripcion')::integer;
  v_t campo.tipos_reporte%rowtype; v_s campo.subtipos_reporte%rowtype; v_sub bigint;
  v_desc text; v_contrato text; v_verif boolean; v_fuera boolean; v_lat numeric; v_lon numeric;
  v_max_fotos integer; v_min_fotos integer; v_max_bytes bigint := campo.f_param('max_bytes_foto')::bigint;
  v_fotos jsonb := coalesce(p_fotos, '[]'::jsonb); v_n integer; v_f jsonb; v_orden integer; v_ruta text; v_size bigint; v_mime text;
  v_id uuid := p_id; v_prev campo.reportes%rowtype; v_reg timestamptz; v_ref jsonb := '[]'::jsonb;
  v_resultado text; v_causal_id bigint; v_causal_cod text; v_exigir boolean; v_val jsonb; v_gen jsonb; v_sen jsonb;
  v_con_etiquetas boolean; v_etq text; v_etqs text[] := '{}'; v_falta text; v_num bigint; v_consecutivo text;
  v_fin timestamptz; v_max_h numeric;   -- pasada 14/11: hora de inicio
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);
  v_perfil := campo.f_perfil(v_email);
  if v_origen not in ('campo', 'escritorio') then perform campo.f_error('El origen debe ser campo o escritorio'); end if;
  if v_origen = 'escritorio' and v_perfil not in ('admin', 'supervisor') then
    raise exception 'Solo el supervisor o el administrador crean reportes desde el escritorio' using errcode = '42501';
  end if;

  -- Reenvío (red inestable): mismo identificador y mismo autor = misma respuesta, sin duplicar (y sin gastar cupo ni consecutivo)
  if v_id is not null then
    select * into v_prev from campo.reportes where id = v_id;
    if found then
      if v_prev.autor = v_email then
        return jsonb_build_object('id', v_prev.id, 'registrado_en', v_prev.registrado_en, 'repetido', true,
                                  'contrato_verificado', v_prev.contrato_verificado, 'aviso_zona', v_prev.fuera_de_zona, 'consecutivo', v_prev.consecutivo);
      end if;
      perform campo.f_error('Identificador de reporte no válido');
    end if;
  end if;

  -- Límite de ritmo (Paso B1): los reenvíos idempotentes de arriba NO consumen cupo; el cupo se verifica antes de validar el resto
  perform campo.f_cupo_reportes(v_email, v_perfil);

  -- Tipo, subtipo y texto
  select t.* into v_t from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id
   where t.codigo = btrim(coalesce(p_tipo, '')) and t.activo and g.activo;
  if not found then perform campo.f_error('El tipo de reporte no existe o está desactivado'); end if;
  if nullif(btrim(coalesce(p_subtipo, '')), '') is not null then
    select s.* into v_s from campo.subtipos_reporte s where s.tipo_id = v_t.id and s.codigo = btrim(p_subtipo);
    if not found then perform campo.f_error('El subtipo no corresponde al tipo elegido'); end if;
    if not v_s.activo then perform campo.f_error('El subtipo está desactivado'); end if;
    v_sub := v_s.id;
  elsif v_t.exige_subtipo then
    perform campo.f_error('Elija un subtipo para este tipo de reporte');
  end if;
  v_desc := nullif(btrim(coalesce(p_descripcion, '')), '');
  if v_t.exige_texto and (v_desc is null or length(v_desc) < 3) then perform campo.f_error('Describa lo que encontró: este tipo de reporte lo exige'); end if;
  if length(coalesce(v_desc, '')) > v_maxdesc then perform campo.f_error(format('La descripción es demasiado larga (máximo %s caracteres)', replace(to_char(v_maxdesc, 'FM9G999'), ',', '.'))); end if;

  -- Resultado y causal (Paso D): solo en los tipos que lo llevan
  v_resultado := nullif(btrim(coalesce(p_resultado, '')), '');
  v_causal_cod := nullif(btrim(coalesce(p_causal, '')), '');
  if v_t.genera_resultado then
    if v_resultado is null then perform campo.f_error('Indique si la visita fue efectiva o inefectiva'); end if;
    if v_resultado not in ('efectivo', 'inefectivo') then perform campo.f_error('El resultado debe ser efectivo o inefectivo'); end if;
    if v_resultado = 'inefectivo' then
      if v_causal_cod is null then perform campo.f_error('Una visita inefectiva necesita la causal'); end if;
      select c.id into v_causal_id from campo.causales c
       where c.codigo = v_causal_cod and c.activo
         and (c.general or exists (select 1 from campo.causales_tipos ct where ct.causal_id = c.id and ct.tipo_id = v_t.id and ct.activo));
      if not found then perform campo.f_error('La causal no existe, está desactivada o no aplica a este formato'); end if;
    elsif v_causal_cod is not null then
      perform campo.f_error('La causal solo se informa cuando la visita es inefectiva');
    end if;
  elsif v_resultado is not null or v_causal_cod is not null then
    perform campo.f_error('Este tipo de reporte no lleva resultado ni causal');
  end if;
  v_exigir := v_resultado is distinct from 'inefectivo';

  -- Coordenada: dato numérico en rango; nunca se rechaza por la ubicación
  if p_lat is null or p_lon is null or p_lat = 'NaN'::numeric or p_lon = 'NaN'::numeric then perform campo.f_error('La coordenada no es válida'); end if;
  if p_lat < -90 or p_lat > 90 or p_lon < -180 or p_lon > 180 then perform campo.f_error('La coordenada está fuera de los rangos válidos de latitud y longitud'); end if;
  v_lat := round(p_lat, 6); v_lon := round(p_lon, 6);
  v_fuera := not (v_lat between campo.f_param('zona_lat_min') and campo.f_param('zona_lat_max')
              and v_lon between campo.f_param('zona_lon_min') and campo.f_param('zona_lon_max'));
  if p_precision_m is not null and (p_precision_m = 'NaN'::numeric or p_precision_m < 0 or p_precision_m > 100000) then perform campo.f_error('La precisión de la coordenada no es válida'); end if;
  if v_resultado = 'inefectivo' and v_origen = 'campo' and p_precision_m is null then
    perform campo.f_error('Una visita inefectiva necesita la ubicación tomada por el celular (con su precisión): active la ubicación e intente de nuevo');
  end if;

  -- Contrato: según el tipo es obligatorio, opcional o no se pide. Solo se confirma si existe; no se lee ningún otro dato
  v_contrato := nullif(btrim(coalesce(p_contrato, '')), '');
  if v_t.requiere_contrato = 'si' and v_contrato is null then perform campo.f_error('Este formato necesita el número de contrato'); end if;
  if v_t.requiere_contrato = 'no' and v_contrato is not null then perform campo.f_error('Este formato no lleva número de contrato'); end if;
  if v_contrato is not null then
    if v_contrato !~ '^[A-Za-z0-9-]{1,20}$' then perform campo.f_error('El contrato solo puede llevar letras, números y guiones (máximo 20)'); end if;
    if v_t.limite_ventana is not null then
      perform campo.f_cupo_tipo(v_email, v_perfil, v_t.id, v_t.limite_ventana, v_t.nombre);   -- Paso D: tope propio del tipo, en vez del general de contratos
    else
      perform campo.f_cupo_contratos(v_email, v_perfil);   -- Paso B1: tope de reportes con contrato (impide enumerar contratos); antes de consultar si existe
    end if;
    perform campo.f_cupo_contratos_falsos(v_email, v_perfil);   -- Paso B1: tope de contratos NO verificados en 24 h; también antes de consultar si existe
    v_verif := exists (select 1 from public.predios_comercial pc where pc.cod_usuario = v_contrato);
  end if;

  -- Campos propios (Paso D): validados contra la definición del tipo; los sensibles se separan
  v_val := campo.f_validar_datos(v_t.id, p_datos, v_exigir);
  v_gen := nullif(v_val -> 'general', '{}'::jsonb);
  v_sen := nullif(v_val -> 'sensibles', '{}'::jsonb);

  -- Orden de trabajo (Paso D): gancho para SCRR; hoy solo se guarda
  if p_orden_trabajo_id is not null then perform campo.f_validar_orden_trabajo(p_orden_trabajo_id, v_email, v_t.id); end if;

  -- Fotos: cantidad (mínimo y máximo del tipo), orden, etiqueta, ruta propia y objeto realmente subido (tamaño y tipo leídos de Storage)
  v_max_fotos := coalesce(v_t.fotos_max, campo.f_param('max_fotos')::integer);
  v_min_fotos := case when v_origen <> 'campo' then 0 when v_exigir then coalesce(v_t.fotos_min, 1) else least(coalesce(v_t.fotos_min, 1), 1) end;
  if jsonb_typeof(v_fotos) <> 'array' then perform campo.f_error('Las fotos no vienen en el formato esperado'); end if;
  v_n := jsonb_array_length(v_fotos);
  if v_n < v_min_fotos then
    if v_min_fotos = 1 then perform campo.f_error('Un reporte de campo necesita al menos una foto'); end if;
    perform campo.f_error(format('Este formato necesita al menos %s fotos (lleva %s)', v_min_fotos, v_n));
  end if;
  if v_n > v_max_fotos then perform campo.f_error(format('Máximo %s fotos por reporte', v_max_fotos)); end if;
  if v_n > 0 and v_id is null then perform campo.f_error('Para adjuntar fotos primero debe reservarse el reporte (preparar la subida)'); end if;
  if v_n > 0 and (select count(distinct (e ->> 'orden')::integer) <> v_n or min((e ->> 'orden')::integer) <> 1 or max((e ->> 'orden')::integer) <> v_n
                    from jsonb_array_elements(v_fotos) e) then
    perform campo.f_error('El orden de las fotos debe ser 1, 2, … sin repetir ni saltar');
  end if;
  v_con_etiquetas := exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo);
  for v_f in select e from jsonb_array_elements(v_fotos) e order by (e ->> 'orden')::integer loop
    v_orden := (v_f ->> 'orden')::integer;
    v_ruta := v_f ->> 'ruta';
    if v_ruta is null or v_ruta !~ ('^reportes/[0-9]{4}-[0-9]{2}/' || v_id::text || '/' || v_orden || '\.jpg$') then
      perform campo.f_error(format('La ruta de la foto %s no corresponde a este reporte', v_orden));
    end if;
    v_etq := nullif(btrim(coalesce(v_f ->> 'etiqueta', '')), '');
    if v_con_etiquetas then
      if v_etq is null then perform campo.f_error(format('Indique qué muestra la foto %s', v_orden)); end if;
      if v_etq <> 'adicional' then
        if not exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.codigo = v_etq and tf.activo) then
          perform campo.f_error(format('La etiqueta de la foto %s no existe en este formato', v_orden));
        end if;
        if v_etq = any (v_etqs) then perform campo.f_error(format('Hay dos fotos con la misma etiqueta (foto %s)', v_orden)); end if;
      end if;
      v_etqs := v_etqs || v_etq;
    elsif v_etq is not null then
      perform campo.f_error('Este tipo de reporte no usa etiquetas de foto');
    end if;
    select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_mime
      from storage.objects o where o.bucket_id = 'campo-fotos' and o.name = v_ruta;
    if not found then perform campo.f_error(format('No se encontró la foto %s: súbala de nuevo', v_orden)); end if;
    if coalesce(v_size, 0) <= 0 then perform campo.f_error(format('La foto %s está vacía', v_orden)); end if;
    if v_size > v_max_bytes then perform campo.f_error(format('La foto %s pesa más de lo permitido (%s KB)', v_orden, v_max_bytes / 1024)); end if;
    if v_mime is distinct from 'image/jpeg' then perform campo.f_error(format('La foto %s debe ser JPEG', v_orden)); end if;
    v_ref := v_ref || jsonb_build_object('orden', v_orden, 'ruta', v_ruta, 'tamano', v_size, 'mime', v_mime, 'etiqueta', v_etq);
  end loop;
  if v_con_etiquetas and v_exigir and v_origen = 'campo' then
    select tf.nombre into v_falta from campo.tipo_fotos tf
     where tf.tipo_id = v_t.id and tf.activo and tf.obligatoria and tf.codigo <> all (v_etqs) order by tf.orden, tf.id limit 1;
    if v_falta is not null then perform campo.f_error(format('Falta la foto obligatoria: «%s»', v_falta)); end if;
  end if;
  -- Visita inefectiva en campo: al menos una foto de la fachada o del predio (las etiquetas con soporte_inefectiva del tipo)
  if v_resultado = 'inefectivo' and v_origen = 'campo' and exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo and tf.soporte_inefectiva)
     and not exists (select 1 from campo.tipo_fotos tf where tf.tipo_id = v_t.id and tf.activo and tf.soporte_inefectiva and tf.codigo = any (v_etqs)) then
    perform campo.f_error('Una visita inefectiva necesita la foto de la fachada o del predio');
  end if;
  -- Pasada 14/11: hora de inicio = la del celular al abrir el formulario. Fin = la hora del servidor al registrar (v_fin: la MISMA que se guarda en registrado_en).
  v_fin := clock_timestamp();
  if p_inicio_dispositivo is not null then
    v_max_h := campo.f_param('max_horas_inicio');
    if p_inicio_dispositivo > v_fin + interval '2 minutes' then
      perform campo.f_error('La hora de su celular está adelantada. Corríjala y vuelva a enviar: lo escrito y las fotos no se pierden.');
    end if;
    if p_inicio_dispositivo < v_fin - v_max_h * interval '1 hour' then
      perform campo.f_error(format('Este formulario se abrió hace más de %s horas. Revise la hora de su celular o ábralo de nuevo.', trim_scale(v_max_h)));
    end if;
  end if;
  if v_id is null then v_id := gen_random_uuid(); end if;

  -- Inserción (una sola transacción; una carrera por el mismo id se resuelve como «repetido»).
  -- El consecutivo se toma AQUÍ, al final y dentro del mismo bloque: si la inserción falla, el número vuelve al contador (sin huecos).
  begin
    v_num := campo.f_siguiente_consecutivo(v_t.id);
    if v_num is not null then v_consecutivo := campo.f_texto_consecutivo(v_t.prefijo_consecutivo, v_num); end if;
    insert into campo.reportes (id, tipo_id, subtipo_id, descripcion, contrato, contrato_verificado, lat, lon, precision_m, riesgo_inmediato, origen, fuera_de_zona, autor,
                                datos, resultado, causal_id, consecutivo_num, consecutivo, orden_trabajo_id, registrado_en, inicio_en, inicio_origen)
    values (v_id, v_t.id, v_sub, v_desc, v_contrato, v_verif, v_lat, v_lon, p_precision_m, coalesce(p_riesgo_inmediato, false), v_origen, v_fuera, v_email,
            v_gen, v_resultado, v_causal_id, v_num, v_consecutivo, p_orden_trabajo_id, v_fin, p_inicio_dispositivo, case when p_inicio_dispositivo is not null then 'dispositivo' end)
    returning registrado_en into v_reg;
    insert into campo.reporte_fotos (reporte_id, orden, ruta_storage, tamano_bytes, tipo_mime, etiqueta)
      select v_id, (x ->> 'orden')::smallint, x ->> 'ruta', (x ->> 'tamano')::integer, x ->> 'mime', x ->> 'etiqueta' from jsonb_array_elements(v_ref) x;
    if v_sen is not null then insert into campo.reporte_datos_sensibles (reporte_id, datos) values (v_id, v_sen); end if;
  exception when unique_violation then
    select * into v_prev from campo.reportes where id = v_id;
    if found and v_prev.autor = v_email then
      return jsonb_build_object('id', v_prev.id, 'registrado_en', v_prev.registrado_en, 'repetido', true,
                                'contrato_verificado', v_prev.contrato_verificado, 'aviso_zona', v_prev.fuera_de_zona, 'consecutivo', v_prev.consecutivo);
    end if;
    perform campo.f_error('Una de las fotos ya está usada en otro reporte');
  end;

  -- Auditoría: nunca los valores de los campos propios, solo cuántos y si hubo sensibles
  perform campo.f_auditar(v_email, 'campo_crear_reporte', v_id::text,
    jsonb_build_object('tipo', v_t.codigo, 'subtipo', v_s.codigo, 'origen', v_origen, 'fotos', v_n, 'riesgo_inmediato', coalesce(p_riesgo_inmediato, false),
                       'fuera_de_zona', v_fuera, 'contrato_informado', v_contrato is not null, 'contrato_verificado', v_verif,
                       'consecutivo', v_consecutivo, 'resultado', v_resultado, 'causal', case when v_causal_id is not null then v_causal_cod end, 'con_inicio', p_inicio_dispositivo is not null,
                       'campos', (select count(*) from jsonb_object_keys(coalesce(v_gen, '{}'::jsonb))), 'campos_sensibles', v_sen is not null,
                       'orden_trabajo', p_orden_trabajo_id is not null), p_ip);
  return jsonb_build_object('id', v_id, 'registrado_en', v_reg, 'repetido', false, 'contrato_verificado', v_verif, 'aviso_zona', v_fuera, 'consecutivo', v_consecutivo);
end $_$;


--
-- Name: geoportal_campo_cuadrilla_cambiar(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_cuadrilla_cambiar(p_solicitante text, p_datos jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; d jsonb := coalesce(p_datos, '{}'::jsonb); v_tipo text; v_id bigint; v_q campo.cuadrillas; v_nombre text; v_m text; v_a campo.actividades; v_n integer; v_ev bigint; v_val text;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del cambio no tienen el formato esperado'); end if;
  v_tipo := d ->> 'tipo';
  if v_tipo is null or v_tipo not in ('crear', 'renombrar', 'desactivar', 'activar', 'agregar_actividad', 'quitar_actividad') then
    perform campo.f_error('El cambio debe ser crear, renombrar, desactivar, activar, agregar_actividad o quitar_actividad');
  end if;
  v_m := campo.f_motivo_personal(d ->> 'motivo', v_tipo in ('desactivar', 'quitar_actividad'));
  if v_tipo in ('crear', 'renombrar') then
    v_nombre := regexp_replace(btrim(coalesce(d ->> 'nombre', '')), '\s+', ' ', 'g');
    if length(v_nombre) < 2 or length(v_nombre) > 60 then perform campo.f_error('El nombre de la cuadrilla debe tener entre 2 y 60 caracteres'); end if;
  end if;
  if v_tipo = 'crear' then
    perform pg_advisory_xact_lock(hashtext('campo_cuadrillas'));
    if exists (select 1 from campo.cuadrillas q where lower(regexp_replace(q.nombre, '\s', '', 'g')) = lower(regexp_replace(v_nombre, '\s', '', 'g'))) then
      perform campo.f_error('Ya existe una cuadrilla con ese nombre', '55000');
    end if;
    insert into campo.cuadrillas (nombre, autor) values (v_nombre, v_email) returning id into v_id;
    insert into campo.cuadrilla_eventos (cuadrilla_id, tipo_evento, valor, autor) values (v_id, 'crear', v_nombre, v_email) returning id into v_ev;
    perform campo.f_auditar(v_email, 'campo_cuadrilla_crear', v_id::text, jsonb_build_object('evento', v_ev), p_ip);
    return jsonb_build_object('id', v_id, 'cambio', true);
  end if;
  begin v_id := (d ->> 'cuadrilla_id')::bigint; exception when others then perform campo.f_error('La cuadrilla no es válida'); end;
  if v_id is null then perform campo.f_error('Indique la cuadrilla'); end if;
  perform pg_advisory_xact_lock(hashtext('campo_cuadrillas'));
  perform pg_advisory_xact_lock(hashtext('campo_cuadrilla:' || v_id));
  select * into v_q from campo.cuadrillas q where q.id = v_id;
  if v_q.id is null then perform campo.f_error('Esa cuadrilla no existe'); end if;
  if v_tipo = 'renombrar' then
    if v_nombre = v_q.nombre then perform campo.f_error('La cuadrilla ya tiene ese nombre', '55000'); end if;
    if exists (select 1 from campo.cuadrillas q where q.id <> v_id and lower(regexp_replace(q.nombre, '\s', '', 'g')) = lower(regexp_replace(v_nombre, '\s', '', 'g'))) then
      perform campo.f_error('Ya existe una cuadrilla con ese nombre', '55000');
    end if;
    update campo.cuadrillas set nombre = v_nombre where id = v_id;
    v_val := v_nombre;
  elsif v_tipo = 'desactivar' then
    if not v_q.activa then perform campo.f_error('La cuadrilla ya está desactivada', '55000'); end if;
    select count(*) into v_n from campo.f_miembros_cuadrillas() m where m.cuadrilla_id = v_id;
    if v_n > 0 then
      perform campo.f_error(case when v_n = 1 then 'La cuadrilla tiene 1 miembro: sáquelo antes de desactivarla' else 'La cuadrilla tiene ' || v_n || ' miembros: sáquelos antes de desactivarla' end, '55000');
    end if;
    update campo.cuadrillas set activa = false where id = v_id;
  elsif v_tipo = 'activar' then
    if v_q.activa then perform campo.f_error('La cuadrilla ya está activa', '55000'); end if;
    update campo.cuadrillas set activa = true where id = v_id;
  else
    select * into v_a from campo.actividades a where a.codigo = nullif(btrim(coalesce(d ->> 'actividad', '')), '');
    if v_a.codigo is null then perform campo.f_error('Esa actividad no existe'); end if;
    if v_tipo = 'agregar_actividad' then
      if not v_q.activa then perform campo.f_error('Esa cuadrilla está desactivada'); end if;
      if not v_a.activa then perform campo.f_error('Esa actividad está desactivada'); end if;
      if v_a.codigo = any (campo.f_cuadrilla_actividades(v_id)) then perform campo.f_error('La cuadrilla ya tiene esa actividad', '55000'); end if;
    elsif not (v_a.codigo = any (campo.f_cuadrilla_actividades(v_id))) then perform campo.f_error('La cuadrilla no tiene esa actividad', '55000');
    end if;
    v_val := v_a.codigo;
  end if;
  insert into campo.cuadrilla_eventos (cuadrilla_id, tipo_evento, valor, motivo, autor) values (v_id, v_tipo, v_val, v_m, v_email) returning id into v_ev;
  perform campo.f_auditar(v_email, 'campo_cuadrilla_' || v_tipo, v_id::text, jsonb_build_object('evento', v_ev, 'valor', v_val), p_ip);
  return jsonb_build_object('id', v_id, 'cambio', true);
end $$;


--
-- Name: geoportal_campo_cuadrillas(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_cuadrillas(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_todas boolean;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  if f ? 'incluir_inactivas' and jsonb_typeof(f -> 'incluir_inactivas') not in ('boolean', 'null') then perform campo.f_error('incluir_inactivas debe ser sí o no'); end if;
  v_todas := coalesce((f ->> 'incluir_inactivas')::boolean, false);
  return jsonb_build_object('cuadrillas', (
    with m as (select * from campo.f_miembros_cuadrillas())
    select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nombre', q.nombre, 'activa', q.activa, 'creada_en', q.creado_en, 'autor', q.autor,
             'n_miembros', (select count(*) from m where m.cuadrilla_id = q.id),
             'miembros', (select coalesce(jsonb_agg(jsonb_build_object('email', m.persona, 'nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = m.persona))
                                                    order by m.persona), '[]'::jsonb) from m where m.cuadrilla_id = q.id),
             'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'nombre', coalesce(a.nombre, x.codigo), 'activa', coalesce(a.activa, false)) order by a.orden, x.codigo), '[]'::jsonb)
                               from unnest(campo.f_cuadrilla_actividades(q.id)) as x(codigo) left join campo.actividades a on a.codigo = x.codigo))
             order by q.activa desc, lower(q.nombre), q.id), '[]'::jsonb)
      from campo.cuadrillas q where q.activa or v_todas));
end $$;


--
-- Name: geoportal_campo_datos_sensibles(text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_datos_sensibles(p_solicitante text, p_id uuid, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_tipo bigint; v_datos jsonb;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select r.tipo_id into v_tipo from campo.reportes r where r.id = p_id;
  if not found then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  select ds.datos into v_datos from campo.reporte_datos_sensibles ds where ds.reporte_id = p_id;
  if not found then perform campo.f_error('El reporte no tiene datos sensibles', 'P0002'); end if;
  perform campo.f_auditar(v_email, 'campo_ver_datos_sensibles', p_id::text, jsonb_build_object('campos', (select jsonb_agg(k order by k) from jsonb_object_keys(v_datos) k)), p_ip);
  return jsonb_build_object('reporte_id', p_id, 'datos', v_datos,
    'campos', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'tipo_dato', c.tipo_dato, 'unidad', c.unidad,
                                  'opciones', (select jsonb_agg(jsonb_build_object('codigo', o ->> 'codigo', 'nombre', o ->> 'nombre')) from jsonb_array_elements(c.opciones) o))) order by c.orden, c.id)
                          from campo.tipo_campos c where c.tipo_id = v_tipo and c.sensible), '[]'::jsonb));
end $$;


--
-- Name: geoportal_campo_descarga_cerrar(text, bigint, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_descarga_cerrar(p_solicitante text, p_descarga_id bigint, p_filas integer, p_resultado text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; a record; v_res text := lower(btrim(coalesce(p_resultado, '')));
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if v_res not in ('completa', 'cancelada', 'error') then perform campo.f_error('El resultado debe ser completa, cancelada o error'); end if;
  if p_filas is null or p_filas < 0 then perform campo.f_error('El número de filas no es válido'); end if;
  select x.id, x.email, x.detalle into a from public.geoportal_auditoria x where x.id = p_descarga_id and x.accion = 'campo_descarga_iniciar';
  if not found or a.email <> v_email then perform campo.f_error('La descarga no existe', 'P0002'); end if;
  if exists (select 1 from public.geoportal_auditoria x where x.accion = 'campo_descarga_cerrar' and x.referencia = p_descarga_id::text) then
    return jsonb_build_object('cerrada', true, 'repetida', true);
  end if;
  perform campo.f_auditar(v_email, 'campo_descarga_cerrar', p_descarga_id::text, jsonb_build_object('filas', p_filas, 'resultado', v_res, 'filas_esperadas', a.detalle -> 'filas_esperadas'), p_ip);
  return jsonb_build_object('cerrada', true, 'repetida', false);
end $$;


--
-- Name: geoportal_campo_descarga_iniciar(text, jsonb, text, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_descarga_iniciar(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_formato text DEFAULT 'csv'::text, p_incluir_autor boolean DEFAULT false, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_f jsonb := coalesce(p_filtros, '{}'::jsonb) - 'cursor' - 'limite'; v_formato text := lower(btrim(coalesce(p_formato, ''))); v_total bigint; v_corte bigint; v_id bigint; v_autor boolean := coalesce(p_incluir_autor, false);
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if v_formato not in ('csv', 'xlsx') then perform campo.f_error('El formato debe ser Excel o CSV'); end if;
  if v_autor and campo.f_perfil(v_email) <> 'admin' then perform campo.f_error('Solo el administrador puede incluir el correo de quien reportó', '42501'); end if;
  if jsonb_typeof(v_f) <> 'object' then perform campo.f_error('Los filtros no son válidos'); end if;
  select count(*), max(x.seq) into v_total, v_corte from campo.f_filtrar(v_f) x;
  if v_total = 0 then perform campo.f_error('No hay reportes con esos filtros'); end if;
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
  values (v_email, 'campo_descarga_iniciar', v_formato, jsonb_build_object('filtros', v_f, 'incluir_autor', v_autor, 'filas_esperadas', v_total, 'hasta_seq', v_corte), p_ip)
  returning id into v_id;
  return jsonb_build_object('descarga_id', v_id, 'total', v_total, 'formato', v_formato, 'filtros', v_f, 'incluir_autor', v_autor, 'hasta_seq', v_corte,
                            'generado_por', v_email, 'generado_en', to_char(campo.f_ahora_bogota(), 'DD/MM/YYYY HH24:MI'));
end $$;


--
-- Name: geoportal_campo_descarga_pagina(text, bigint, bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_descarga_pagina(p_solicitante text, p_descarga_id bigint, p_despues_de bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 5000) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; a record; v_f jsonb; v_corte bigint; v_autor boolean; v_lim integer := least(greatest(coalesce(p_limite, 5000), 1), 5000); v_eps numeric := campo.f_param('distancia_duplicados_m');
        v_ids uuid[]; v_rows jsonb; v_min bigint; v_mas boolean;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select x.id, x.email, x.detalle into a from public.geoportal_auditoria x where x.id = p_descarga_id and x.accion = 'campo_descarga_iniciar';
  if not found or a.email <> v_email then perform campo.f_error('La descarga no existe', 'P0002'); end if;
  if exists (select 1 from public.geoportal_auditoria x where x.accion = 'campo_descarga_cerrar' and x.referencia = p_descarga_id::text) then perform campo.f_error('La descarga ya se cerró', '55000'); end if;
  v_f := a.detalle -> 'filtros'; v_corte := (a.detalle ->> 'hasta_seq')::bigint; v_autor := coalesce((a.detalle ->> 'incluir_autor')::boolean, false);
  select coalesce(array_agg(x.id), '{}'::uuid[]) into v_ids from campo.f_filtrar(v_f) x where x.seq <= v_corte;
  with pag as (
    select x.*, row_number() over (order by x.seq desc) as rn from campo.f_filtrar(v_f) x where x.seq <= v_corte and (p_despues_de is null or x.seq < p_despues_de) order by x.seq desc limit v_lim + 1
  ), cl as (select * from campo.f_grupos_cercanos(v_eps, v_ids)),
  fila as (
    select p.*, t.codigo as tipo_codigo, t.nombre as tipo_nombre, g.nombre as grupo_nombre, s.nombre as sub_nombre, es.nombre as estado_nombre, ca.nombre as causal_nombre,
           cl.grupo_id as grupo_dup, cl.tamano as tam_dup
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join campo.estados_reporte es on es.codigo = p.estado left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
     where p.rn <= v_lim
  )
  select coalesce(jsonb_agg(
           jsonb_build_object('seq', f.seq, 'id', f.id, 'registrado_local', to_char(f.registrado_en at time zone 'America/Bogota', 'YYYY-MM-DD"T"HH24:MI:SS'),
             'tipo_codigo', f.tipo_codigo, 'tipo_nombre', f.tipo_nombre, 'grupo_nombre', f.grupo_nombre, 'subtipo_nombre', f.sub_nombre,
             'consecutivo', f.consecutivo, 'resultado', f.resultado, 'causal_nombre', f.causal_nombre,
             'estado', f.estado, 'estado_nombre', f.estado_nombre, 'oculto', f.oculto, 'riesgo_inmediato', f.riesgo_inmediato, 'fuera_de_zona', f.fuera_de_zona,
             'contrato', f.contrato, 'contrato_verificado', f.contrato_verificado, 'descripcion', f.descripcion,
             'lat', f.lat, 'lon', f.lon, 'precision_m', f.precision_m, 'origen', f.origen, 'n_fotos', f.n_fotos,
             'grupo_duplicados', f.grupo_dup, 'tamano_grupo', f.tam_dup, 'reporte_original_id', f.reporte_original_id,
             'orden_trabajo_id', f.orden_trabajo_id, 'datos', coalesce(f.datos, '{}'::jsonb),
             'inicio_local', to_char(f.inicio_en at time zone 'America/Bogota', 'YYYY-MM-DD"T"HH24:MI:SS'), 'inicio_origen', f.inicio_origen,
             'duracion_min', round(extract(epoch from (f.registrado_en - f.inicio_en)) / 60.0, 1))
           || case when v_autor then jsonb_build_object('autor', f.autor) else '{}'::jsonb end order by f.seq desc), '[]'::jsonb),
         min(f.seq), (select count(*) from pag) > v_lim
    into v_rows, v_min, v_mas from fila f;
  return jsonb_build_object('registros', v_rows, 'devueltos', jsonb_array_length(v_rows), 'ultimo_seq', v_min, 'hay_mas', v_mas);
end $$;


--
-- Name: geoportal_campo_foto_ruta(text, uuid, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_foto_ruta(p_solicitante text, p_id uuid, p_orden integer, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; f campo.reporte_fotos%rowtype;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select * into f from campo.reporte_fotos where reporte_id = p_id and orden = p_orden;
  if not found then perform campo.f_error('La foto no existe', 'P0002'); end if;
  perform campo.f_auditar(v_email, 'campo_ver_foto', p_id::text, jsonb_build_object('orden', p_orden), p_ip);
  return jsonb_build_object('bucket', 'campo-fotos', 'ruta', f.ruta_storage, 'tipo_mime', f.tipo_mime, 'tamano_bytes', f.tamano_bytes);
end $$;


--
-- Name: geoportal_campo_gestionar_catalogo(text, text, text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_gestionar_catalogo(p_solicitante text, p_entidad text, p_accion text, p_datos jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare
  v_email text; d jsonb := coalesce(p_datos, '{}'::jsonb); v_tab text; v_where text; v_antes jsonb; v_despues jsonb; v_set text[] := '{}'; v_gid bigint; v_tid bigint; v_cid bigint; v_orden integer;
begin
  v_email := campo.f_autorizar_admin(p_solicitante);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos no son válidos'); end if;
  v_tab := case p_entidad when 'grupo' then 'grupos_reporte' when 'tipo' then 'tipos_reporte' when 'subtipo' then 'subtipos_reporte'
                          when 'estado' then 'estados_reporte' when 'parametro' then 'parametros'
                          when 'campo' then 'tipo_campos' when 'foto' then 'tipo_fotos' when 'causal' then 'causales' when 'causal_tipo' then 'causales_tipos' end;
  if v_tab is null then perform campo.f_error('La entidad debe ser grupo, tipo, subtipo, estado, parametro, campo, foto, causal o causal_tipo'); end if;
  if p_accion not in ('crear', 'renombrar', 'reordenar', 'activar', 'desactivar', 'actualizar') then perform campo.f_error('Acción no válida'); end if;
  if p_entidad = 'parametro' and p_accion <> 'actualizar' then perform campo.f_error('Los parámetros solo se actualizan'); end if;
  if p_entidad = 'causal_tipo' and p_accion not in ('crear', 'activar', 'desactivar') then perform campo.f_error('La relación entre causal y tipo solo se crea, se activa o se desactiva'); end if;
  v_orden := coalesce(nullif(d ->> 'orden', '')::integer, 100);

  begin
    if p_accion = 'crear' then
      if p_entidad = 'grupo' then
        insert into campo.grupos_reporte (codigo, nombre, orden) values (d ->> 'codigo', d ->> 'nombre', v_orden) returning to_jsonb(grupos_reporte.*) into v_despues;
      elsif p_entidad = 'tipo' then
        select id into v_gid from campo.grupos_reporte where codigo = d ->> 'grupo';
        if v_gid is null then perform campo.f_error('El grupo no existe', 'P0002'); end if;
        insert into campo.tipos_reporte (grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo,
                                         fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana)
        values (v_gid, d ->> 'codigo', d ->> 'nombre', v_orden, coalesce((d ->> 'exige_texto')::boolean, false), coalesce((d ->> 'exige_subtipo')::boolean, false),
                (d ->> 'fotos_min')::smallint, (d ->> 'fotos_max')::smallint, coalesce(d ->> 'requiere_contrato', 'opcional'), coalesce((d ->> 'genera_resultado')::boolean, false),
                nullif(d ->> 'prefijo_consecutivo', ''), (d ->> 'limite_ventana')::integer)
        returning to_jsonb(tipos_reporte.*) into v_despues;
      elsif p_entidad = 'subtipo' then
        select id into v_tid from campo.tipos_reporte where codigo = d ->> 'tipo';
        if v_tid is null then perform campo.f_error('El tipo no existe', 'P0002'); end if;
        insert into campo.subtipos_reporte (tipo_id, codigo, nombre, orden) values (v_tid, d ->> 'codigo', d ->> 'nombre', v_orden)
        returning to_jsonb(subtipos_reporte.*) into v_despues;
      elsif p_entidad = 'estado' then
        insert into campo.estados_reporte (codigo, nombre, orden, exige_motivo) values (d ->> 'codigo', d ->> 'nombre', v_orden, coalesce((d ->> 'exige_motivo')::boolean, false))
        returning to_jsonb(estados_reporte.*) into v_despues;
      elsif p_entidad in ('campo', 'foto') then
        select id into v_tid from campo.tipos_reporte where codigo = d ->> 'tipo';
        if v_tid is null then perform campo.f_error('El tipo no existe', 'P0002'); end if;
        if p_entidad = 'campo' then
          insert into campo.tipo_campos (tipo_id, codigo, nombre, tipo_dato, obligatorio, opciones, minimo, maximo, unidad, ayuda, sensible, orden, seccion, visible_si)
          values (v_tid, d ->> 'codigo', d ->> 'nombre', d ->> 'tipo_dato', coalesce((d ->> 'obligatorio')::boolean, false), nullif(d -> 'opciones', 'null'::jsonb),
                  (d ->> 'minimo')::numeric, (d ->> 'maximo')::numeric, nullif(d ->> 'unidad', ''), nullif(d ->> 'ayuda', ''), coalesce((d ->> 'sensible')::boolean, false), v_orden,
                  nullif(d ->> 'seccion', ''), nullif(d -> 'visible_si', 'null'::jsonb))
          returning to_jsonb(tipo_campos.*) into v_despues;
        else
          insert into campo.tipo_fotos (tipo_id, codigo, nombre, obligatoria, soporte_inefectiva, orden)
          values (v_tid, d ->> 'codigo', d ->> 'nombre', coalesce((d ->> 'obligatoria')::boolean, true), coalesce((d ->> 'soporte_inefectiva')::boolean, false), v_orden)
          returning to_jsonb(tipo_fotos.*) into v_despues;
        end if;
      elsif p_entidad = 'causal' then
        insert into campo.causales (codigo, nombre, general, orden) values (d ->> 'codigo', d ->> 'nombre', coalesce((d ->> 'general')::boolean, false), v_orden)
        returning to_jsonb(causales.*) into v_despues;
      else  -- causal_tipo
        select id into v_cid from campo.causales where codigo = d ->> 'causal';
        if v_cid is null then perform campo.f_error('La causal no existe', 'P0002'); end if;
        select id into v_tid from campo.tipos_reporte where codigo = d ->> 'tipo';
        if v_tid is null then perform campo.f_error('El tipo no existe', 'P0002'); end if;
        insert into campo.causales_tipos (causal_id, tipo_id) values (v_cid, v_tid) returning to_jsonb(causales_tipos.*) into v_despues;
      end if;
    else
      v_where := case p_entidad
        when 'grupo' then format('codigo = %L', d ->> 'codigo')
        when 'tipo' then format('codigo = %L', d ->> 'codigo')
        when 'estado' then format('codigo = %L', d ->> 'codigo')
        when 'causal' then format('codigo = %L', d ->> 'codigo')
        when 'parametro' then format('clave = %L', d ->> 'clave')
        when 'causal_tipo' then format('causal_id = (select id from campo.causales where codigo = %L) and tipo_id = (select id from campo.tipos_reporte where codigo = %L)', d ->> 'causal', d ->> 'tipo')
        else format('tipo_id = (select id from campo.tipos_reporte where codigo = %L) and codigo = %L', d ->> 'tipo', d ->> 'codigo') end;   -- subtipo, campo, foto
      execute format('select to_jsonb(t.*) from campo.%I t where %s', v_tab, v_where) into v_antes;
      if v_antes is null then perform campo.f_error('No se encontró lo que se quiere cambiar', 'P0002'); end if;

      if p_accion = 'renombrar' then v_set := array[format('nombre = %L', d ->> 'nombre')];
      elsif p_accion = 'reordenar' then v_set := array[format('orden = %s', (d ->> 'orden')::integer)];
      elsif p_accion = 'activar' then v_set := array['activo = true'];
      elsif p_accion = 'desactivar' then
        if p_entidad = 'estado' and (d ->> 'codigo') in ('reportado', 'duplicado') then perform campo.f_error('Los estados reportado y duplicado son del sistema y no se desactivan', '55000'); end if;
        v_set := array['activo = false'];
      else  -- actualizar
        if p_entidad = 'tipo' then
          if d ? 'exige_texto' then v_set := v_set || format('exige_texto = %L', (d ->> 'exige_texto')::boolean); end if;
          if d ? 'exige_subtipo' then v_set := v_set || format('exige_subtipo = %L', (d ->> 'exige_subtipo')::boolean); end if;
          if d ? 'grupo' then
            select id into v_gid from campo.grupos_reporte where codigo = d ->> 'grupo';
            if v_gid is null then perform campo.f_error('El grupo no existe', 'P0002'); end if;
            v_set := v_set || format('grupo_id = %s', v_gid);
          end if;
          if d ? 'fotos_min' then v_set := v_set || format('fotos_min = %L', (d ->> 'fotos_min')::smallint); end if;
          if d ? 'fotos_max' then v_set := v_set || format('fotos_max = %L', (d ->> 'fotos_max')::smallint); end if;
          if d ? 'requiere_contrato' then v_set := v_set || format('requiere_contrato = %L', d ->> 'requiere_contrato'); end if;
          if d ? 'genera_resultado' then v_set := v_set || format('genera_resultado = %L', (d ->> 'genera_resultado')::boolean); end if;
          if d ? 'prefijo_consecutivo' then v_set := v_set || format('prefijo_consecutivo = %L', nullif(d ->> 'prefijo_consecutivo', '')); end if;
          if d ? 'limite_ventana' then v_set := v_set || format('limite_ventana = %L', (d ->> 'limite_ventana')::integer); end if;
        elsif p_entidad = 'estado' then
          if d ? 'exige_motivo' then v_set := v_set || format('exige_motivo = %L', (d ->> 'exige_motivo')::boolean); end if;
        elsif p_entidad = 'parametro' then
          v_set := array[format('valor = %L', (d ->> 'valor')::numeric), 'actualizado_en = clock_timestamp()', format('actualizado_por = %L', v_email)];
        elsif p_entidad = 'campo' then
          if d ? 'obligatorio' then v_set := v_set || format('obligatorio = %L', (d ->> 'obligatorio')::boolean); end if;
          if d ? 'opciones' then v_set := v_set || format('opciones = %L::jsonb', (nullif(d -> 'opciones', 'null'::jsonb))::text); end if;
          if d ? 'minimo' then v_set := v_set || format('minimo = %L', (d ->> 'minimo')::numeric); end if;
          if d ? 'maximo' then v_set := v_set || format('maximo = %L', (d ->> 'maximo')::numeric); end if;
          if d ? 'unidad' then v_set := v_set || format('unidad = %L', nullif(d ->> 'unidad', '')); end if;
          if d ? 'ayuda' then v_set := v_set || format('ayuda = %L', nullif(d ->> 'ayuda', '')); end if;
          if d ? 'seccion' then v_set := v_set || format('seccion = %L', nullif(d ->> 'seccion', '')); end if;
          if d ? 'visible_si' then v_set := v_set || format('visible_si = %L::jsonb', (nullif(d -> 'visible_si', 'null'::jsonb))::text); end if;
        elsif p_entidad = 'foto' then
          if d ? 'obligatoria' then v_set := v_set || format('obligatoria = %L', (d ->> 'obligatoria')::boolean); end if;
          if d ? 'soporte_inefectiva' then v_set := v_set || format('soporte_inefectiva = %L', (d ->> 'soporte_inefectiva')::boolean); end if;
        elsif p_entidad = 'causal' then
          if d ? 'general' then v_set := v_set || format('general = %L', (d ->> 'general')::boolean); end if;
        end if;
        if cardinality(v_set) = 0 then perform campo.f_error('No hay nada que actualizar para esa entidad'); end if;
      end if;
      execute format('update campo.%I set %s where %s', v_tab, array_to_string(v_set, ', '), v_where);
      execute format('select to_jsonb(t.*) from campo.%I t where %s', v_tab, v_where) into v_despues;
    end if;
  exception
    when unique_violation then perform campo.f_error('Ya existe un elemento con ese código', '55000');
    when check_violation then perform campo.f_error('Algún dato no cumple las reglas (código, longitud o rango permitido)');
    when not_null_violation then perform campo.f_error('Falta un dato obligatorio');
    when invalid_text_representation or numeric_value_out_of_range then perform campo.f_error('Algún dato no tiene el formato esperado');
  end;

  perform campo.f_auditar(v_email, 'campo_catalogo', p_entidad || ':' || p_accion, jsonb_build_object('antes', v_antes, 'despues', v_despues), p_ip);
  return jsonb_build_object('entidad', p_entidad, 'accion', p_accion, 'antes', v_antes, 'despues', v_despues);
end $$;


--
-- Name: geoportal_campo_guardar_parametro(text, jsonb, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_guardar_parametro(p_solicitante text, p_cambios jsonb, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare
  v_email text; v_motivo text := nullif(btrim(coalesce(p_motivo, '')), ''); c jsonb; p campo.parametros%rowtype; v_val numeric; v_res jsonb := '[]'::jsonb; v_claves text[] := '{}'; v_clave text;
  v_enteros text[] := array['max_fotos', 'max_bytes_foto', 'limite_reportes_ventana', 'limite_contratos_ventana', 'multiplo_supervisor', 'ventana_limite_minutos', 'limite_contratos_falsos_dia', 'max_descripcion'];
  v_a numeric; v_b numeric;
begin
  v_email := campo.f_autorizar_admin(p_solicitante);
  if v_motivo is null or length(v_motivo) < 10 then perform campo.f_error('Indique el motivo (mínimo 10 caracteres)'); end if;
  if length(v_motivo) > 1000 then perform campo.f_error('El motivo es demasiado largo (máximo 1.000 caracteres)'); end if;
  if jsonb_typeof(p_cambios) is distinct from 'array' or jsonb_array_length(p_cambios) not between 1 and 20 then perform campo.f_error('Indique de 1 a 20 parámetros por cambio'); end if;
  for c in select e from jsonb_array_elements(p_cambios) e loop
    if jsonb_typeof(c) <> 'object' then perform campo.f_error('Un cambio de parámetro no tiene el formato esperado'); end if;
    v_clave := coalesce(c ->> 'clave', '');
    if v_clave = any (v_claves) then perform campo.f_error(format('El parámetro «%s» viene repetido', left(v_clave, 60))); end if;
    v_claves := v_claves || v_clave;
    select * into p from campo.parametros where clave = v_clave for update;
    if not found then perform campo.f_error(format('El parámetro «%s» no existe', left(v_clave, 60)), 'P0002'); end if;
    if v_clave = 'alerta_base_pct' then perform campo.f_error('Ese parámetro no se edita desde esta pantalla'); end if;
    if jsonb_typeof(c -> 'valor') is distinct from 'number' then perform campo.f_error(format('El valor de «%s» debe ser un número', v_clave)); end if;
    v_val := (c ->> 'valor')::numeric;
    if v_clave = any (v_enteros) and v_val <> trunc(v_val) then perform campo.f_error(format('El valor de «%s» debe ser un número entero', v_clave)); end if;
    if (p.minimo is not null and v_val < p.minimo) or (p.maximo is not null and v_val > p.maximo) then
      perform campo.f_error(format('El valor de «%s» debe estar entre %s y %s %s', v_clave, replace(trim_scale(p.minimo)::text, '.', ','), replace(trim_scale(p.maximo)::text, '.', ','), p.unidad));
    end if;
    if v_val is distinct from p.valor then
      update campo.parametros set valor = v_val, actualizado_en = clock_timestamp(), actualizado_por = v_email where clave = v_clave;
      v_res := v_res || jsonb_build_object('clave', v_clave, 'antes', p.valor, 'despues', v_val);
    end if;
  end loop;
  if jsonb_array_length(v_res) = 0 then perform campo.f_error('Ningún valor cambia: ya son los vigentes', '55000'); end if;
  -- Coherencia de la caja de zona (mínimo menor que máximo), con los valores ya cambiados
  select valor into v_a from campo.parametros where clave = 'zona_lat_min'; select valor into v_b from campo.parametros where clave = 'zona_lat_max';
  if v_a >= v_b then perform campo.f_error('La latitud mínima de la zona debe ser menor que la máxima'); end if;
  select valor into v_a from campo.parametros where clave = 'zona_lon_min'; select valor into v_b from campo.parametros where clave = 'zona_lon_max';
  if v_a >= v_b then perform campo.f_error('La longitud mínima de la zona debe ser menor que la máxima'); end if;
  perform campo.f_auditar(v_email, 'campo_parametro', 'guardar', jsonb_build_object('motivo', v_motivo, 'cambios', v_res), p_ip);
  return jsonb_build_object('cambios', v_res);
end $$;


--
-- Name: geoportal_campo_historial_personal(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_historial_personal(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_p text; v_desp bigint; v_lim integer; v_cuad bigint; v_filas jsonb; v_n integer;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  begin
    v_p := nullif(lower(btrim(coalesce(f ->> 'persona', ''))), ''); v_desp := nullif(f ->> 'despues_de', '')::bigint;
    v_lim := least(greatest(coalesce(nullif(f ->> 'limite', '')::integer, 100), 1), 500);
    v_cuad := nullif(f ->> 'cuadrilla_id', '')::bigint;
  exception when others then perform campo.f_error('Algún filtro tiene un valor no válido');
  end;
  if v_cuad is not null then
    if not exists (select 1 from campo.cuadrillas q where q.id = v_cuad) then perform campo.f_error('Esa cuadrilla no existe'); end if;
    with ce as (
      select e.creado_en, jsonb_build_object('clave', 'c:' || e.id, 'id', e.id, 'persona', null, 'nombre', null, 'tipo_evento', 'cuadrilla_' || e.tipo_evento,
               'cuadrilla', jsonb_build_object('id', q.id, 'nombre', q.nombre),
               'formulario', null, 'formulario_nombre', null, 'cargo', null,
               'valor_codigo', case when e.tipo_evento in ('agregar_actividad', 'quitar_actividad') then e.valor end,
               'valor_nombre', case when e.tipo_evento in ('agregar_actividad', 'quitar_actividad') then coalesce((select a.nombre from campo.actividades a where a.codigo = e.valor), e.valor) else e.valor end,
               'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en, 'vigente', null) as fila
        from campo.cuadrilla_eventos e join campo.cuadrillas q on q.id = e.cuadrilla_id where e.cuadrilla_id = v_cuad
    ), pe as (
      select x.*, lag(x.valor) over (partition by x.persona order by x.id) as anterior from campo.personal_eventos x where x.tipo_evento = 'fijar_cuadrilla'
    ), pm as (
      select pe.creado_en, jsonb_build_object('clave', 'p:' || pe.id, 'id', pe.id, 'persona', pe.persona, 'nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = pe.persona),
               'tipo_evento', pe.tipo_evento, 'cuadrilla', jsonb_build_object('id', q.id, 'nombre', q.nombre),
               'formulario', null, 'formulario_nombre', null, 'cargo', null,
               'valor_codigo', pe.valor, 'valor_nombre', (select c.nombre from campo.cuadrillas c where c.id = pe.valor::bigint),
               'entra', pe.valor = v_cuad::text, 'motivo', pe.motivo, 'autor', pe.autor, 'creado_en', pe.creado_en, 'vigente', null) as fila
        from pe join campo.cuadrillas q on q.id = v_cuad where pe.valor = v_cuad::text or pe.anterior = v_cuad::text
    ), todo as (select * from ce union all select * from pm order by 1 desc limit 500)
    select coalesce(jsonb_agg(fila order by creado_en desc), '[]'::jsonb) into v_filas from todo;
    return jsonb_build_object('eventos', v_filas, 'siguiente', null);
  end if;
  with ev as (
    select e.*, e.id = max(e.id) over (partition by e.persona, case when e.tipo_evento in ('asignar_formulario', 'quitar_formulario') then 'f:' || e.formulario
                                                                    when e.tipo_evento in ('asignar_actividad', 'quitar_actividad') then 'a:' || e.valor
                                                                    else e.tipo_evento end) as vigente
      from campo.personal_eventos e where v_p is null or e.persona = v_p
  ), pag as (select * from ev where v_desp is null or ev.id < v_desp order by ev.id desc limit v_lim + 1)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'persona', p.persona, 'nombre', (select nullif(btrim(lb.nombre), '') from public.geoportal_lista_blanca lb where lb.email = p.persona),
           'tipo_evento', p.tipo_evento, 'formulario', p.formulario,
           'formulario_nombre', case when p.formulario is null then null else coalesce((select x.nombre from campo.f_formularios_personal() x where x.clave = p.formulario),
                                                                                     (select t.nombre from campo.tipos_reporte t where 'tipo:' || t.codigo = p.formulario), p.formulario) end,
           'cargo', p.cargo, 'motivo', p.motivo, 'autor', p.autor, 'creado_en', p.creado_en, 'vigente', p.vigente,
           'clave', 'p:' || p.id, 'valor_codigo', p.valor,
           'valor_nombre', case p.tipo_evento when 'fijar_area' then (select a.nombre from campo.areas_comercial a where a.codigo = p.valor)
                                              when 'fijar_cuadrilla' then (select q.nombre from campo.cuadrillas q where q.id = p.valor::bigint)
                                              when 'asignar_actividad' then (select a.nombre from campo.actividades a where a.codigo = p.valor)
                                              when 'quitar_actividad' then (select a.nombre from campo.actividades a where a.codigo = p.valor) end) order by p.id desc) filter (where rn <= v_lim), '[]'::jsonb)
    into v_n, v_filas from (select pag.*, row_number() over (order by pag.id desc) as rn from pag) p;
  return jsonb_build_object('eventos', v_filas, 'siguiente', case when v_n > v_lim then (select min((x ->> 'id')::bigint) from jsonb_array_elements(v_filas) x) end);
end $$;


--
-- Name: geoportal_campo_indicadores(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_indicadores(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare
  v_email text; v_f jsonb := coalesce(p_filtros, '{}'::jsonb) - 'cursor' - 'limite'; v_base jsonb; v_out jsonb;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if jsonb_typeof(v_f) <> 'object' then perform campo.f_error('Los filtros no son válidos'); end if;
  v_base := v_f - 'ocultos';
  with s as materialized (
    select x.id, x.registrado_en, (x.registrado_en at time zone 'America/Bogota')::date as dia, x.tipo_id, x.estado from campo.f_filtrar(v_f) x
  ), rango as (
    select greatest(coalesce(nullif(v_f ->> 'desde', '')::date, min(dia)), coalesce(nullif(v_f ->> 'hasta', '')::date, max(dia)) - 999) as ini,
           coalesce(nullif(v_f ->> 'hasta', '')::date, max(dia)) as fin,
           coalesce(nullif(v_f ->> 'desde', '')::date, min(dia)) < coalesce(nullif(v_f ->> 'hasta', '')::date, max(dia)) - 999 as recortada
      from s
  ), por_dia as (
    select coalesce(jsonb_agg(jsonb_build_object('dia', to_char(d.dia, 'YYYY-MM-DD'), 'n', coalesce(c.n, 0)) order by d.dia), '[]'::jsonb) as j
      from rango r cross join lateral (select g::date as dia from generate_series(r.ini::timestamp, r.fin::timestamp, interval '1 day') g where r.ini is not null and r.fin >= r.ini) d
      left join (select dia, count(*) as n from s group by 1) c on c.dia = d.dia
  ), por_tipo as (
    select coalesce(jsonb_agg(jsonb_build_object('tipo', jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre), 'grupo', jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre), 'n', q.n)
                              order by q.n desc, t.codigo), '[]'::jsonb) as j
      from (select tipo_id, count(*) as n from s group by 1) q join campo.tipos_reporte t on t.id = q.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
  ), por_estado as (
    select coalesce(jsonb_agg(jsonb_build_object('estado', e.codigo, 'nombre', e.nombre, 'n', q.n) order by e.orden, e.codigo), '[]'::jsonb) as j
      from (select estado, count(*) as n from s group by 1) q join campo.estados_reporte e on e.codigo = q.estado
  ), r as (
    select s.id, (select extract(epoch from (e.creado_en - s.registrado_en)) from campo.reporte_eventos e
                   where e.reporte_id = s.id and e.tipo_evento in ('cambio_estado', 'vincular_duplicado') order by e.id limit 1) as seg
      from s
  ), rev as (
    select jsonb_build_object('revisados', count(seg), 'sin_revisar', count(*) - count(seg),
             'mediana_segundos', round((percentile_cont(0.5) within group (order by seg))::numeric, 0),
             'promedio_segundos', round(avg(seg)::numeric, 0),
             'p90_segundos', round((percentile_cont(0.9) within group (order by seg))::numeric, 0)) as j
      from r
  )
  select jsonb_build_object('total', (select count(*) from s), 'por_dia', (select j from por_dia), 'serie_recortada', coalesce((select recortada from rango), false),
           'por_tipo', (select j from por_tipo), 'por_estado', (select j from por_estado), 'revision', (select j from rev)) into v_out;
  return v_out || jsonb_build_object(
    'corte', to_char(campo.f_ahora_bogota(), 'DD/MM/YYYY HH24:MI'), 'filtros', v_f,
    'visibles', (select count(*) from campo.f_filtrar(v_base || '{"ocultos":"no"}'::jsonb)),
    'ocultos', (select count(*) from campo.f_filtrar(v_base || '{"ocultos":"si"}'::jsonb)));
end $$;


--
-- Name: geoportal_campo_listar_reportes(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_listar_reportes(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_f jsonb := coalesce(p_filtros, '{}'::jsonb); v_ids uuid[]; v_total integer; v_eps numeric; v_lim integer; v_cur bigint;
        v_rows jsonb; v_min bigint; v_mas boolean;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  v_eps := campo.f_param('distancia_duplicados_m');
  v_lim := least(greatest(coalesce(nullif(v_f ->> 'limite', '')::integer, 1000), 1), 5000);
  v_cur := nullif(v_f ->> 'cursor', '')::bigint;
  select coalesce(array_agg(x.id), '{}'::uuid[]), count(*)::integer into v_ids, v_total from campo.f_filtrar(v_f) x;
  with pag as (
    select x.*, row_number() over (order by x.seq desc) as rn
      from campo.f_filtrar(v_f) x where v_cur is null or x.seq < v_cur order by x.seq desc limit v_lim + 1
  ), cl as (select * from campo.f_grupos_cercanos(v_eps, v_ids)),
  fila as (
    select p.*, t.codigo as tipo_codigo, t.nombre as tipo_nombre, g.codigo as grupo_codigo, g.nombre as grupo_nombre,
           s.codigo as sub_codigo, s.nombre as sub_nombre, cl.grupo_id as grupo_dup, cl.tamano as tam_dup,
           ca.codigo as causal_codigo, ca.nombre as causal_nombre
      from pag p join campo.tipos_reporte t on t.id = p.tipo_id join campo.grupos_reporte g on g.id = t.grupo_id
      left join campo.subtipos_reporte s on s.id = p.subtipo_id left join cl on cl.reporte_id = p.id
      left join campo.causales ca on ca.id = p.causal_id
     where p.rn <= v_lim
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'seq', f.seq,
           'tipo', jsonb_build_object('codigo', f.tipo_codigo, 'nombre', f.tipo_nombre),
           'grupo', jsonb_build_object('codigo', f.grupo_codigo, 'nombre', f.grupo_nombre),
           'subtipo', case when f.sub_codigo is null then null else jsonb_build_object('codigo', f.sub_codigo, 'nombre', f.sub_nombre) end,
           'descripcion', f.descripcion, 'contrato', f.contrato, 'contrato_verificado', f.contrato_verificado,
           'lat', f.lat, 'lon', f.lon, 'precision_m', f.precision_m, 'riesgo_inmediato', f.riesgo_inmediato, 'origen', f.origen,
           'fuera_de_zona', f.fuera_de_zona, 'autor', f.autor, 'registrado_en', f.registrado_en,
           'estado', f.estado, 'estado_desde', f.estado_desde, 'oculto', f.oculto, 'reporte_original_id', f.reporte_original_id,
           'grupo_duplicados', f.grupo_dup, 'tamano_grupo', f.tam_dup, 'n_fotos', f.n_fotos)
           -- Paso D
           || jsonb_build_object(
           'consecutivo', f.consecutivo, 'resultado', f.resultado,
           'causal', case when f.causal_codigo is null then null else jsonb_build_object('codigo', f.causal_codigo, 'nombre', f.causal_nombre) end,
           'orden_trabajo_id', f.orden_trabajo_id, 'datos', coalesce(f.datos, '{}'::jsonb), 'tiene_datos_sensibles', f.tiene_datos_sensibles,
           'inicio_en', f.inicio_en, 'inicio_origen', f.inicio_origen) order by f.seq desc), '[]'::jsonb),
         min(f.seq), (select count(*) from pag) > v_lim
    into v_rows, v_min, v_mas from fila f;
  return jsonb_build_object('reportes', v_rows, 'total', v_total, 'siguiente', case when v_mas then v_min end, 'distancia_duplicados_m', v_eps);
end $$;


--
-- Name: geoportal_campo_obtener_formulario(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_obtener_formulario(p_solicitante text, p_incluir_inactivos boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_perfil text; v_todo boolean; v_sup boolean; v_max integer := campo.f_param('max_fotos')::integer;
begin
  v_email := campo.f_autorizar_reporte(p_solicitante);
  v_perfil := campo.f_perfil(v_email);
  v_todo := coalesce(p_incluir_inactivos, false) and v_perfil = 'admin';
  v_sup := v_perfil in ('admin', 'supervisor');
  return jsonb_build_object(
    'perfil', v_perfil,
    'puede', jsonb_build_object('reportar', true, 'crear_desde_escritorio', v_sup, 'supervisar', v_sup, 'administrar_catalogo', v_perfil = 'admin'),
    'limites', jsonb_build_object('max_fotos', v_max, 'min_fotos_campo', 1,
                                  'max_bytes_foto', campo.f_param('max_bytes_foto')::bigint, 'tipo_mime', 'image/jpeg',
                                  'max_bytes_datos', 4096, 'etiqueta_foto_adicional', 'adicional',
                                  'max_descripcion', campo.f_param('max_descripcion')::integer),
    'zona', jsonb_build_object('lat_min', campo.f_param('zona_lat_min'), 'lat_max', campo.f_param('zona_lat_max'),
                               'lon_min', campo.f_param('zona_lon_min'), 'lon_max', campo.f_param('zona_lon_max')),
    'grupos', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre, 'orden', g.orden, 'activo', g.activo,
        'tipos', coalesce((
          select jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre, 'orden', t.orden, 'activo', t.activo,
                   'exige_texto', t.exige_texto, 'exige_subtipo', t.exige_subtipo,
                   'tiene_subtipos', exists (select 1 from campo.subtipos_reporte s0 where s0.tipo_id = t.id and (v_todo or s0.activo)),
                   'subtipos', coalesce((select jsonb_agg(jsonb_build_object('codigo', s.codigo, 'nombre', s.nombre, 'orden', s.orden, 'activo', s.activo) order by s.orden, s.id)
                                           from campo.subtipos_reporte s where s.tipo_id = t.id and (v_todo or s.activo)), '[]'::jsonb))
                   -- Paso D
                   || jsonb_build_object(
                   'fotos_min', coalesce(t.fotos_min, 1), 'fotos_max', coalesce(t.fotos_max, v_max),
                   'requiere_contrato', t.requiere_contrato, 'genera_resultado', t.genera_resultado, 'usa_consecutivo', t.prefijo_consecutivo is not null,
                   'campos', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'tipo_dato', c.tipo_dato, 'obligatorio', c.obligatorio,
                                                'opciones', (select jsonb_agg(jsonb_build_object('codigo', o ->> 'codigo', 'nombre', o ->> 'nombre', 'activo', coalesce((o ->> 'activo')::boolean, true)) order by n)
                                                               from jsonb_array_elements(c.opciones) with ordinality x(o, n) where v_todo or coalesce((o ->> 'activo')::boolean, true)),
                                                'minimo', c.minimo, 'maximo', case when c.tipo_dato = 'texto' then coalesce(c.maximo, 300) else c.maximo end,
                                                'unidad', c.unidad, 'ayuda', c.ayuda, 'sensible', c.sensible, 'seccion', c.seccion, 'visible_si', c.visible_si, 'orden', c.orden, 'activo', c.activo)) order by c.orden, c.id)
                                         from campo.tipo_campos c where c.tipo_id = t.id and (v_todo or c.activo)), '[]'::jsonb),
                   'fotos', coalesce((select jsonb_agg(jsonb_build_object('codigo', tf.codigo, 'nombre', tf.nombre, 'obligatoria', tf.obligatoria, 'soporte_inefectiva', tf.soporte_inefectiva, 'orden', tf.orden, 'activo', tf.activo) order by tf.orden, tf.id)
                                        from campo.tipo_fotos tf where tf.tipo_id = t.id and (v_todo or tf.activo)), '[]'::jsonb),
                   'causales', case when not t.genera_resultado then '[]'::jsonb else coalesce((
                                 select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre) order by c.orden, c.id) from campo.causales c
                                  where c.activo and (c.general or exists (select 1 from campo.causales_tipos ct where ct.causal_id = c.id and ct.tipo_id = t.id and ct.activo))), '[]'::jsonb) end)
                   || case when v_todo then jsonb_build_object('prefijo_consecutivo', t.prefijo_consecutivo, 'limite_ventana', t.limite_ventana,
                                                               'fotos_min_propio', t.fotos_min, 'fotos_max_propio', t.fotos_max) else '{}'::jsonb end
                   order by t.orden, t.id)
            from campo.tipos_reporte t where t.grupo_id = g.id and (v_todo or t.activo)), '[]'::jsonb))
        order by g.orden, g.id)
        from campo.grupos_reporte g where (v_todo or g.activo)), '[]'::jsonb),
    'estados', case when not v_sup then null else coalesce((
      select jsonb_agg(jsonb_build_object('codigo', e.codigo, 'nombre', e.nombre, 'orden', e.orden, 'activo', e.activo,
                                          'exige_motivo', e.exige_motivo, 'cambio_manual', e.cambio_manual) order by e.orden, e.codigo)
        from campo.estados_reporte e where v_todo or e.activo), '[]'::jsonb) end,
    'causales', case when not v_sup then null else coalesce((
      select jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'general', c.general, 'orden', c.orden, 'activo', c.activo,
                                          'tipos', coalesce((select jsonb_agg(t.codigo order by t.codigo) from campo.causales_tipos ct join campo.tipos_reporte t on t.id = ct.tipo_id
                                                              where ct.causal_id = c.id and ct.activo), '[]'::jsonb)) order by c.orden, c.id)
        from campo.causales c where v_todo or c.activo), '[]'::jsonb) end,
    -- Paso C: los parámetros los ve SIEMPRE el administrador (con quién y cuándo los cambió); alerta_base_pct no se muestra (es de la verificación)
    'parametros', case when v_perfil <> 'admin' then null else coalesce((
      select jsonb_agg(jsonb_build_object('clave', p.clave, 'valor', p.valor, 'unidad', p.unidad, 'descripcion', p.descripcion,
                                          'minimo', p.minimo, 'maximo', p.maximo, 'actualizado_en', p.actualizado_en, 'actualizado_por', p.actualizado_por) order by p.clave)
        from campo.parametros p where p.clave <> 'alerta_base_pct'), '[]'::jsonb) end,
    -- Paso C: definiciones de campos y fotos de TODOS los tipos, aun los desactivados, para que el supervisor etiquete datos de reportes viejos
    'definiciones', case when not v_sup then null else coalesce((
      select jsonb_agg(jsonb_build_object('tipo', t.codigo,
        'campos', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'tipo_dato', c.tipo_dato, 'unidad', c.unidad, 'sensible', c.sensible, 'activo', c.activo, 'seccion', c.seccion, 'orden', c.orden,
                                      'opciones', (select jsonb_agg(jsonb_build_object('codigo', o ->> 'codigo', 'nombre', o ->> 'nombre')) from jsonb_array_elements(c.opciones) o))) order by c.orden, c.id)
                              from campo.tipo_campos c where c.tipo_id = t.id), '[]'::jsonb),
        'fotos', coalesce((select jsonb_agg(jsonb_build_object('codigo', tf.codigo, 'nombre', tf.nombre, 'activo', tf.activo) order by tf.orden, tf.id) from campo.tipo_fotos tf where tf.tipo_id = t.id), '[]'::jsonb))
        order by t.orden, t.id) from campo.tipos_reporte t), '[]'::jsonb) end);
end $$;


--
-- Name: geoportal_campo_obtener_reporte(text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_obtener_reporte(p_solicitante text, p_id uuid, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v campo.v_reportes_estado%rowtype; v_eps numeric := campo.f_param('distancia_duplicados_m');
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  select * into v from campo.v_reportes_estado where id = p_id;
  if not found then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  -- Paso C: consultar el detalle (muestra autor y contrato) queda auditado
  perform campo.f_auditar(v_email, 'campo_ver_detalle', p_id::text, '{}'::jsonb, p_ip);
  return (
    select jsonb_build_object(
      'reporte', jsonb_build_object(
        'id', v.id, 'seq', v.seq,
        'tipo', jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre), 'grupo', jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre),
        'subtipo', case when s.id is null then null else jsonb_build_object('codigo', s.codigo, 'nombre', s.nombre) end,
        'descripcion', v.descripcion, 'contrato', v.contrato, 'contrato_verificado', v.contrato_verificado, 'lat', v.lat, 'lon', v.lon,
        'precision_m', v.precision_m, 'riesgo_inmediato', v.riesgo_inmediato, 'origen', v.origen, 'fuera_de_zona', v.fuera_de_zona,
        'autor', v.autor, 'registrado_en', v.registrado_en, 'estado', v.estado, 'estado_desde', v.estado_desde, 'oculto', v.oculto,
        'reporte_original_id', v.reporte_original_id)
        -- Paso D
        || jsonb_build_object(
        'consecutivo', v.consecutivo, 'resultado', v.resultado,
        'causal', (select jsonb_build_object('codigo', ca.codigo, 'nombre', ca.nombre) from campo.causales ca where ca.id = v.causal_id),
        'orden_trabajo_id', v.orden_trabajo_id, 'datos', coalesce(v.datos, '{}'::jsonb), 'tiene_datos_sensibles', v.tiene_datos_sensibles,
        'inicio_en', v.inicio_en, 'inicio_origen', v.inicio_origen),
      'campos', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'tipo_dato', c.tipo_dato, 'unidad', c.unidad,
                                  'opciones', (select jsonb_agg(jsonb_build_object('codigo', o ->> 'codigo', 'nombre', o ->> 'nombre')) from jsonb_array_elements(c.opciones) o),
                                  'sensible', c.sensible, 'activo', c.activo)) order by c.orden, c.id)
                           from campo.tipo_campos c where c.tipo_id = v.tipo_id), '[]'::jsonb),
      'fotos', coalesce((select jsonb_agg(jsonb_build_object('orden', f.orden, 'tamano_bytes', f.tamano_bytes, 'tipo_mime', f.tipo_mime, 'registrada_en', f.registrada_en,
                                  'etiqueta', f.etiqueta,
                                  'etiqueta_nombre', case when f.etiqueta = 'adicional' then 'Adicional'
                                                          else (select tf.nombre from campo.tipo_fotos tf where tf.tipo_id = v.tipo_id and tf.codigo = f.etiqueta) end) order by f.orden)
                           from campo.reporte_fotos f where f.reporte_id = v.id), '[]'::jsonb),
      'eventos', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'tipo_evento', e.tipo_evento, 'estado_nuevo', e.estado_nuevo,
                                  'reporte_original_id', e.reporte_original_id, 'motivo', e.motivo, 'autor', e.autor, 'creado_en', e.creado_en) order by e.id)
                           from campo.reporte_eventos e where e.reporte_id = v.id), '[]'::jsonb),
      'cercanos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'distancia_m', c.d, 'registrado_en', c.registrado_en, 'estado', c.estado) order by c.d)
                              from (select o.id, round(st_distance(o.geom::geography, v.geom::geography)::numeric, 1) as d, o.registrado_en, o.estado
                                      from campo.v_reportes_estado o
                                     where o.id <> v.id and o.tipo_id = v.tipo_id and not o.oculto and st_dwithin(o.geom::geography, v.geom::geography, v_eps::double precision)
                                     order by st_distance(o.geom::geography, v.geom::geography) limit 20) c), '[]'::jsonb),
      'distancia_duplicados_m', v_eps)
    from campo.tipos_reporte t join campo.grupos_reporte g on g.id = t.grupo_id left join campo.subtipos_reporte s on s.id = v.subtipo_id
   where t.id = v.tipo_id);
end $$;


--
-- Name: geoportal_campo_ocultar_reporte(text, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_ocultar_reporte(p_solicitante text, p_id uuid, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_motivo text := nullif(btrim(coalesce(p_motivo, '')), ''); v_ev bigint;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if not exists (select 1 from campo.reportes where id = p_id) then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  if v_motivo is null or length(v_motivo) < 10 then perform campo.f_error('Indique el motivo (mínimo 10 caracteres)'); end if;
  if campo.f_oculto(p_id) then perform campo.f_error('El reporte ya está oculto', '55000'); end if;
  insert into campo.reporte_eventos (reporte_id, tipo_evento, motivo, autor) values (p_id, 'ocultar', v_motivo, v_email) returning id into v_ev;
  perform campo.f_auditar(v_email, 'campo_ocultar', p_id::text, jsonb_build_object('motivo', v_motivo), p_ip);
  return jsonb_build_object('id', p_id, 'evento_id', v_ev, 'oculto', true);
end $$;


--
-- Name: geoportal_campo_personal(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_personal(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; f jsonb := coalesce(p_filtros, '{}'::jsonb); v_buscar text; v_admin boolean; v_sup boolean;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  if jsonb_typeof(f) <> 'object' then perform campo.f_error('Los filtros no tienen el formato esperado'); end if;
  v_buscar := nullif(btrim(coalesce(f ->> 'buscar', '')), '');
  v_admin := public.geoportal_es_admin(v_email);
  v_sup := v_admin or public.geoportal_puede(v_email, 'dashboard_campo');
  return jsonb_build_object(
    'puede_editar', v_admin,
    'yo', v_email,
    'puede', jsonb_build_object('cargo', v_admin, 'area', v_admin, 'cuadrilla', v_sup, 'cuadrillas', v_sup, 'actividades', v_sup, 'formularios', v_sup, 'catalogos', v_admin),
    'formularios', (select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'nombre', x.nombre, 'grupo', x.grupo) order by x.orden, x.clave), '[]'::jsonb) from campo.f_formularios_personal() x),
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre) order by a.orden, a.codigo), '[]'::jsonb) from campo.areas_comercial a where a.activa),
    'cuadrillas', (select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nombre', q.nombre) order by lower(q.nombre), q.id), '[]'::jsonb) from campo.cuadrillas q where q.activa),
    'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre) order by a.orden, a.codigo), '[]'::jsonb) from campo.actividades a where a.activa),
    'personas', (select coalesce(jsonb_agg(p order by p ->> 'nombre_orden', p ->> 'email'), '[]'::jsonb) from (
      select jsonb_build_object('email', lb.email, 'nombre', nullif(btrim(lb.nombre), ''), 'nombre_orden', lower(coalesce(nullif(btrim(lb.nombre), ''), lb.email)),
               'perfil', case when coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_dashboard_acta, false) then 'supervisor' else 'operario' end,
               'permisos', jsonb_build_object('campo', coalesce(lb.ver_campo, false), 'dashboard_campo', coalesce(lb.ver_dashboard_campo, false),
                                              'acta', coalesce(lb.ver_acta, false), 'dashboard_acta', coalesce(lb.ver_dashboard_acta, false)),
               'cargo', campo.f_cargo_vigente(lb.email),
               'formularios', to_jsonb(campo.f_formularios_asignados(lb.email)),
               'sin_asignacion', cardinality(campo.f_formularios_asignados(lb.email)) = 0,
               'ultimo_cambio', (select max(e.creado_en) from campo.personal_eventos e where e.persona = lb.email),
               'propia', lb.email = v_email,
               'area', (select jsonb_build_object('codigo', a.codigo, 'nombre', a.nombre, 'activa', a.activa) from campo.areas_comercial a where a.codigo = campo.f_area_vigente(lb.email)),
               'cuadrilla', (select jsonb_build_object('id', q.id, 'nombre', q.nombre, 'activa', q.activa) from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(lb.email)),
               'actividades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'nombre', coalesce(a.nombre, x.codigo), 'activa', coalesce(a.activa, false), 'origen', x.origen)
                                                         order by a.orden, x.codigo), '[]'::jsonb)
                                 from campo.f_actividades_persona(lb.email) x left join campo.actividades a on a.codigo = x.codigo)) as p
        from public.geoportal_lista_blanca lb
       where lb.activo and lb.rol <> 'admin'
         and (coalesce(lb.ver_campo, false) or coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_acta, false) or coalesce(lb.ver_dashboard_acta, false))
         and (v_buscar is null or lb.email ilike '%' || v_buscar || '%' or coalesce(lb.nombre, '') ilike '%' || v_buscar || '%')) s));
end $$;


--
-- Name: geoportal_campo_personal_actividad(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_personal_actividad(p_solicitante text, p_actividad text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_a campo.actividades;
begin
  v_email := campo.f_autorizar_personal(p_solicitante);
  select * into v_a from campo.actividades a where a.codigo = nullif(btrim(coalesce(p_actividad, '')), '');
  if v_a.codigo is null then perform campo.f_error('Esa actividad no existe'); end if;
  return jsonb_build_object(
    'actividad', jsonb_build_object('codigo', v_a.codigo, 'nombre', v_a.nombre, 'activa', v_a.activa),
    'personas', (select coalesce(jsonb_agg(jsonb_build_object('email', x.persona, 'nombre', nullif(btrim(lb.nombre), ''),
                                                              'cuadrilla', (select jsonb_build_object('id', q.id, 'nombre', q.nombre) from campo.cuadrillas q where q.id = x.cuadrilla_id),
                                                              'origen', x.origen) order by lower(coalesce(nullif(btrim(lb.nombre), ''), x.persona)), x.persona), '[]'::jsonb)
                   from campo.f_quien_puede(v_a.codigo) x left join public.geoportal_lista_blanca lb on lb.email = x.persona));
end $$;


--
-- Name: geoportal_campo_personal_cambiar(text, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_personal_cambiar(p_solicitante text, p_persona text, p_tipo text, p_formulario text DEFAULT NULL::text, p_cargo text DEFAULT NULL::text, p_motivo text DEFAULT NULL::text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_p text := lower(btrim(coalesce(p_persona, ''))); v_f text := nullif(btrim(coalesce(p_formulario, '')), ''); v_c text := nullif(btrim(coalesce(p_cargo, '')), '');
        v_m text := nullif(btrim(coalesce(p_motivo, '')), ''); v_id bigint;
begin
  v_email := campo.f_autorizar_admin(p_solicitante);
  if p_tipo is null or p_tipo not in ('fijar_cargo', 'asignar_formulario', 'quitar_formulario') then perform campo.f_error('El cambio debe ser fijar_cargo, asignar_formulario o quitar_formulario'); end if;
  if not exists (select 1 from public.geoportal_lista_blanca lb where lb.email = v_p and lb.activo and lb.rol <> 'admin'
                   and (coalesce(lb.ver_campo, false) or coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_acta, false) or coalesce(lb.ver_dashboard_acta, false))) then
    perform campo.f_error('Esa persona no tiene acceso activo a Formularios de campo ni al acta');
  end if;
  perform pg_advisory_xact_lock(hashtext('campo_personal:' || v_p));
  if p_tipo = 'fijar_cargo' then
    if v_c is null or length(v_c) < 2 or length(v_c) > 80 then perform campo.f_error('El cargo debe tener entre 2 y 80 caracteres'); end if;
    if v_c is not distinct from campo.f_cargo_vigente(v_p) then perform campo.f_error('Ese ya es el cargo vigente', '55000'); end if;
    v_f := null; v_m := null;
  else
    if v_f is null then perform campo.f_error('Indique el formulario'); end if;
    v_c := null;
    if p_tipo = 'asignar_formulario' then
      if not exists (select 1 from campo.f_formularios_personal() x where x.clave = v_f) then perform campo.f_error('Ese formulario no existe o está desactivado'); end if;
      if v_f = any (campo.f_formularios_asignados(v_p)) then perform campo.f_error('Ya tiene asignado ese formulario', '55000'); end if;
    else
      if not (v_f = any (campo.f_formularios_asignados(v_p))) then perform campo.f_error('No tiene asignado ese formulario', '55000'); end if;
      if v_m is null or length(v_m) < 10 or length(v_m) > 300 then perform campo.f_error('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
    end if;
  end if;
  insert into campo.personal_eventos (persona, tipo_evento, formulario, cargo, motivo, autor) values (v_p, p_tipo, v_f, v_c, v_m, v_email) returning id into v_id;
  perform campo.f_auditar(v_email, 'campo_personal_' || p_tipo, v_p, jsonb_build_object('evento', v_id, 'formulario', v_f, 'cargo', v_c is not null), p_ip);
  return jsonb_build_object('id', v_id, 'cambio', true);
end $$;


--
-- Name: geoportal_campo_personal_fijar(text, text, text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_personal_fijar(p_solicitante text, p_persona text, p_tipo text, p_datos jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_admin boolean; d jsonb := coalesce(p_datos, '{}'::jsonb); v_p text := lower(btrim(coalesce(p_persona, '')));
        v_f text; v_c text; v_m text; v_val text; v_cuad bigint; v_ant bigint; v_q campo.cuadrillas; v_a campo.actividades; v_ar campo.areas_comercial; v_id bigint;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  v_admin := public.geoportal_es_admin(v_email);
  if jsonb_typeof(d) <> 'object' then perform campo.f_error('Los datos del cambio no tienen el formato esperado'); end if;
  if p_tipo is null or p_tipo not in ('fijar_cargo', 'fijar_area', 'fijar_cuadrilla', 'asignar_formulario', 'quitar_formulario', 'asignar_actividad', 'quitar_actividad') then
    perform campo.f_error('El cambio debe ser fijar_cargo, fijar_area, fijar_cuadrilla, asignar_formulario, quitar_formulario, asignar_actividad o quitar_actividad');
  end if;
  if p_tipo in ('fijar_cargo', 'fijar_area') and not v_admin then raise exception 'Solo el administrador puede hacerlo' using errcode = '42501'; end if;
  if not campo.f_persona_comercial(v_p) then perform campo.f_error('Esa persona no tiene acceso activo a Formularios de campo ni al acta'); end if;
  if v_p = v_email then perform campo.f_error('No puede cambiar su propia ficha'); end if;
  perform pg_advisory_xact_lock(hashtext('campo_personal:' || v_p));
  v_m := campo.f_motivo_personal(d ->> 'motivo', p_tipo in ('quitar_formulario', 'quitar_actividad'));
  if p_tipo = 'fijar_cargo' then
    v_c := nullif(btrim(coalesce(d ->> 'cargo', '')), '');
    if v_c is null or length(v_c) < 2 or length(v_c) > 80 then perform campo.f_error('El cargo debe tener entre 2 y 80 caracteres'); end if;
    if v_c is not distinct from campo.f_cargo_vigente(v_p) then perform campo.f_error('Ese ya es el cargo vigente', '55000'); end if;
  elsif p_tipo = 'fijar_area' then
    select * into v_ar from campo.areas_comercial a where a.codigo = nullif(btrim(coalesce(d ->> 'area', '')), '');
    if v_ar.codigo is null then perform campo.f_error('Esa área no existe'); end if;
    if not v_ar.activa then perform campo.f_error('Esa área está desactivada'); end if;
    if v_ar.codigo is not distinct from campo.f_area_vigente(v_p) then perform campo.f_error('Ya tiene esa área', '55000'); end if;
    v_val := v_ar.codigo;
  elsif p_tipo = 'fijar_cuadrilla' then
    begin v_cuad := nullif(d ->> 'cuadrilla_id', '')::bigint; exception when others then perform campo.f_error('La cuadrilla no es válida'); end;
    v_ant := campo.f_cuadrilla_vigente(v_p);
    if v_cuad is not null then
      perform pg_advisory_xact_lock(hashtext('campo_cuadrilla:' || v_cuad));
      select * into v_q from campo.cuadrillas q where q.id = v_cuad;
      if v_q.id is null then perform campo.f_error('Esa cuadrilla no existe'); end if;
      if not v_q.activa then perform campo.f_error('Esa cuadrilla está desactivada'); end if;
    end if;
    if v_cuad is not distinct from v_ant then
      perform campo.f_error(case when v_cuad is null then 'No está en ninguna cuadrilla' else 'Ya está en esa cuadrilla' end, '55000');
    end if;
    if v_ant is not null and v_m is null then perform campo.f_error('Escriba el motivo (entre 10 y 300 caracteres)'); end if;
    v_val := v_cuad::text;
  elsif p_tipo in ('asignar_formulario', 'quitar_formulario') then
    v_f := nullif(btrim(coalesce(d ->> 'formulario', '')), '');
    if v_f is null then perform campo.f_error('Indique el formulario'); end if;
    if p_tipo = 'asignar_formulario' then
      if not exists (select 1 from campo.f_formularios_personal() x where x.clave = v_f) then perform campo.f_error('Ese formulario no existe o está desactivado'); end if;
      if v_f = any (campo.f_formularios_asignados(v_p)) then perform campo.f_error('Ya tiene asignado ese formulario', '55000'); end if;
    elsif not (v_f = any (campo.f_formularios_asignados(v_p))) then perform campo.f_error('No tiene asignado ese formulario', '55000');
    end if;
  else
    select * into v_a from campo.actividades a where a.codigo = nullif(btrim(coalesce(d ->> 'actividad', '')), '');
    if v_a.codigo is null then perform campo.f_error('Esa actividad no existe'); end if;
    if p_tipo = 'asignar_actividad' then
      if not v_a.activa then perform campo.f_error('Esa actividad está desactivada'); end if;
      if v_a.codigo = any (campo.f_actividades_propias(v_p)) then perform campo.f_error('Ya tiene esa actividad', '55000'); end if;
    elsif not (v_a.codigo = any (campo.f_actividades_propias(v_p))) then
      if exists (select 1 from campo.f_actividades_persona(v_p) x where x.codigo = v_a.codigo) then
        perform campo.f_error('Esa actividad viene de la cuadrilla ' || (select q.nombre from campo.cuadrillas q where q.id = campo.f_cuadrilla_vigente(v_p)) || ': se quita en la cuadrilla', '55000');
      end if;
      perform campo.f_error('No tiene esa actividad', '55000');
    end if;
    v_val := v_a.codigo;
  end if;
  insert into campo.personal_eventos (persona, tipo_evento, formulario, cargo, valor, motivo, autor) values (v_p, p_tipo, v_f, v_c, v_val, v_m, v_email) returning id into v_id;
  perform campo.f_auditar(v_email, 'campo_personal_' || p_tipo, v_p, jsonb_build_object('evento', v_id, 'formulario', v_f, 'valor', v_val, 'cargo', v_c is not null), p_ip);
  return jsonb_build_object('id', v_id, 'cambio', true);
end $$;


--
-- Name: geoportal_campo_preparar_subida(text, integer, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_preparar_subida(p_solicitante text, p_cantidad integer, p_origen text DEFAULT 'campo'::text, p_ip text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
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
end $$;


--
-- Name: geoportal_campo_reincluir_reporte(text, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_reincluir_reporte(p_solicitante text, p_id uuid, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_motivo text := nullif(btrim(coalesce(p_motivo, '')), ''); v_ev bigint;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if not exists (select 1 from campo.reportes where id = p_id) then perform campo.f_error('El reporte no existe', 'P0002'); end if;
  if v_motivo is null or length(v_motivo) < 10 then perform campo.f_error('Indique el motivo (mínimo 10 caracteres)'); end if;
  if not campo.f_oculto(p_id) then perform campo.f_error('El reporte no está oculto', '55000'); end if;
  insert into campo.reporte_eventos (reporte_id, tipo_evento, motivo, autor) values (p_id, 'reincluir', v_motivo, v_email) returning id into v_ev;
  perform campo.f_auditar(v_email, 'campo_reincluir', p_id::text, jsonb_build_object('motivo', v_motivo), p_ip);
  return jsonb_build_object('id', p_id, 'evento_id', v_ev, 'oculto', false);
end $$;


--
-- Name: geoportal_campo_tec_crear_reporte(text, uuid, text, text, text, text, numeric, numeric, numeric, boolean, jsonb, text, jsonb, text, text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_tec_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_fotos jsonb, p_ip text DEFAULT NULL::text, p_datos jsonb DEFAULT NULL::jsonb, p_resultado text DEFAULT NULL::text, p_causal text DEFAULT NULL::text, p_inicio_dispositivo timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'tecnica', 'pg_temp'
    AS $$
declare v jsonb;
begin
  if p_tipo is null then raise exception 'Falta el tipo de reporte' using errcode = '22023'; end if;
  perform campo.f_tecnica_entrar(p_solicitante, p_tipo);
  v := public.geoportal_campo_crear_reporte(p_solicitante, p_id, p_tipo, p_subtipo, p_descripcion, p_contrato, p_lat, p_lon, p_precision_m, p_riesgo_inmediato, 'campo', p_fotos,
                                            p_ip, p_datos, p_resultado, p_causal, null, p_inicio_dispositivo);
  perform set_config('geoportal.via_tecnica', '', true);
  return v || jsonb_build_object('area', 'tecnica');
end $$;


--
-- Name: geoportal_campo_tec_formulario(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_tec_formulario(p_solicitante text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'tecnica', 'pg_temp'
    AS $$
declare v_claves text[] := campo.f_tecnica_claves(p_solicitante); v jsonb;
begin
  if cardinality(v_claves) = 0 then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  perform set_config('geoportal.via_tecnica', 'on', true);
  v := public.geoportal_campo_obtener_formulario(p_solicitante, false);
  perform set_config('geoportal.via_tecnica', '', true);      -- la marca se apaga en cuanto vuelve la RPC de campo
  return jsonb_build_object(
    'perfil', 'reportante', 'area', 'tecnica', 'formularios', to_jsonb(v_claves),
    'puede', jsonb_build_object('reportar', true, 'crear_desde_escritorio', false, 'supervisar', false, 'administrar_catalogo', false),
    'limites', v -> 'limites', 'zona', v -> 'zona',
    'estados', null, 'causales', null, 'definiciones', null, 'parametros', null,
    'grupos', coalesce((
      select jsonb_agg(g.j || jsonb_build_object('tipos', g.tipos) order by g.n)
        from (select x.j - 'tipos' as j, x.n,
                     (select jsonb_agg(t.j order by t.n) from jsonb_array_elements(x.j -> 'tipos') with ordinality t(j, n)
                       where ('anomalia_compartida' = any (v_claves) and campo.f_tipo_general(t.j ->> 'codigo'))
                          or ('revision_compartida' = any (v_claves) and t.j ->> 'codigo' = 'revision_previa')) as tipos
                from jsonb_array_elements(v -> 'grupos') with ordinality x(j, n)) g
       where g.tipos is not null), '[]'::jsonb));
end $$;


--
-- Name: geoportal_campo_tec_preparar_subida(text, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_tec_preparar_subida(p_solicitante text, p_cantidad integer, p_ip text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'tecnica', 'pg_temp'
    AS $$
declare v jsonb;
begin
  perform campo.f_tecnica_entrar(p_solicitante, p_tipo);
  v := public.geoportal_campo_preparar_subida(p_solicitante, p_cantidad, 'campo', p_ip, p_tipo);
  perform set_config('geoportal.via_tecnica', '', true);
  return v;
end $$;


--
-- Name: geoportal_campo_vincular_duplicado(text, uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_campo_vincular_duplicado(p_solicitante text, p_id uuid, p_original_id uuid, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'campo', 'pg_temp'
    AS $$
declare v_email text; v_motivo text := nullif(btrim(coalesce(p_motivo, '')), ''); v_ev bigint;
begin
  v_email := campo.f_autorizar_supervision(p_solicitante);
  if p_id is null or p_original_id is null then perform campo.f_error('Indique el reporte y su original'); end if;
  if p_id = p_original_id then perform campo.f_error('Un reporte no puede ser duplicado de sí mismo'); end if;
  if not exists (select 1 from campo.reportes where id = p_id) or not exists (select 1 from campo.reportes where id = p_original_id) then
    perform campo.f_error('El reporte o su original no existe', 'P0002');
  end if;
  if v_motivo is null or length(v_motivo) < 10 then perform campo.f_error('Indique el motivo (mínimo 10 caracteres)'); end if;
  if campo.f_original_actual(p_id) = p_original_id then perform campo.f_error('Ya está vinculado como duplicado de ese reporte', '55000'); end if;
  -- Las reglas «el original no es un duplicado» y «este reporte no es original de otros» las garantiza además el disparador f_evento_coherente
  insert into campo.reporte_eventos (reporte_id, tipo_evento, estado_nuevo, reporte_original_id, motivo, autor)
  values (p_id, 'vincular_duplicado', 'duplicado', p_original_id, v_motivo, v_email) returning id into v_ev;
  perform campo.f_auditar(v_email, 'campo_vincular_duplicado', p_id::text, jsonb_build_object('original', p_original_id, 'motivo', v_motivo), p_ip);
  return jsonb_build_object('id', p_id, 'evento_id', v_ev, 'estado', 'duplicado', 'reporte_original_id', p_original_id);
end $$;


--
-- Name: geoportal_dominio_ok(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_dominio_ok(p_email text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$ select lower(coalesce(p_email,'')) like '%@emdupar.gov.co' or lower(coalesce(p_email,'')) like '%@gmail.com'; $$;


--
-- Name: geoportal_envio_config(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_envio_config(p_solicitante text, p_documento text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'salida', 'pg_temp'
    AS $$
declare v_email text; v_cfg salida.config_documentos%rowtype; v_t salida.textos_autorizacion%rowtype;
begin
  v_email := salida.f_autorizar_captura(p_solicitante, btrim(coalesce(p_documento, '')));
  select * into v_cfg from salida.config_documentos where documento = btrim(p_documento);
  if not found or not v_cfg.habilitado then return jsonb_build_object('habilitado', false); end if;
  v_t := salida.f_texto_vigente();
  return jsonb_build_object('habilitado', true, 'texto_version', v_t.version, 'texto', v_t.texto, 'partes', jsonb_build_array(
    jsonb_build_object('codigo', 'quien_atendio', 'nombre', 'Quien atendió la visita'), jsonb_build_object('codigo', 'suscriptor', 'nombre', 'El suscriptor'), jsonb_build_object('codigo', 'otro', 'nombre', 'Otra persona')));
end $$;


--
-- Name: geoportal_envio_depurar(text, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_envio_depurar(p_solicitante text, p_solo_contar boolean DEFAULT true, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'salida', 'acta', 'pg_temp'
    AS $$
declare v_email text; v jsonb;
begin
  v_email := acta.f_autorizar(p_solicitante, 'administrar');
  v := salida.f_depurar(v_email, coalesce(p_solo_contar, true));
  perform acta.f_auditar(v_email, 'envio_depurar', null, v, p_ip);
  return v;
end $$;


--
-- Name: geoportal_envio_estado(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_envio_estado(p_solicitante text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'salida', 'acta', 'pg_temp'
    AS $$
declare v_email text;
begin
  v_email := acta.f_autorizar(p_solicitante, 'administrar');
  return jsonb_build_object(
    'texto', (select jsonb_build_object('version', t.version, 'borrador', t.borrador, 'texto', t.texto) from salida.f_texto_vigente() t),
    'documentos', (select coalesce(jsonb_agg(jsonb_build_object('documento', c.documento, 'habilitado', c.habilitado, 'copias_internas', to_jsonb(c.copias_internas)) order by c.documento), '[]'::jsonb) from salida.config_documentos c),
    'cola', (select coalesce(jsonb_object_agg(s.estado, s.n), '{}'::jsonb) from (select estado, count(*) n from salida.envios group by estado) s),
    'fallos_ultimos_30_dias', (select count(*) from salida.fallos_encolado f where f.creado_en > clock_timestamp() - interval '30 days'));
end $$;


--
-- Name: geoportal_envio_guardar_config(text, text, boolean, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_envio_guardar_config(p_solicitante text, p_documento text, p_habilitado boolean, p_copias jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'salida', 'acta', 'pg_temp'
    AS $_$
declare v_email text; v_doc text := btrim(coalesce(p_documento, '')); v_cop text[] := '{}'; x jsonb; v_c text; v_t salida.textos_autorizacion%rowtype;
begin
  v_email := acta.f_autorizar(p_solicitante, 'administrar');
  if not exists (select 1 from salida.config_documentos where documento = v_doc) then perform salida.f_error('El documento no envía constancias'); end if;
  if p_copias is null or jsonb_typeof(p_copias) <> 'array' or jsonb_array_length(p_copias) > 10 then perform salida.f_error('Las copias internas deben ser una lista de hasta 10 correos'); end if;
  for x in select e from jsonb_array_elements(p_copias) e loop
    v_c := lower(btrim(coalesce(x #>> '{}', '')));
    if v_c !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or length(v_c) > 254 then perform salida.f_error('Una dirección de copia interna no es válida'); end if;
    if not (v_c = any (v_cop)) then v_cop := v_cop || v_c; end if;
  end loop;
  v_t := salida.f_texto_vigente();
  if p_habilitado is null then perform salida.f_error('Indique si el documento queda habilitado'); end if;
  if p_habilitado and (v_t.version is null or v_t.borrador) then perform salida.f_error('No se puede habilitar: el texto de autorización sigue como borrador (pendiente de jurídica)'); end if;
  update salida.config_documentos set habilitado = p_habilitado, copias_internas = v_cop, actualizado_por = v_email, actualizado_en = clock_timestamp() where documento = v_doc;
  insert into salida.config_eventos (documento, habilitado, copias_internas, autor) values (v_doc, p_habilitado, v_cop, v_email);
  perform acta.f_auditar(v_email, 'envio_guardar_config', v_doc, jsonb_build_object('habilitado', p_habilitado, 'copias', cardinality(v_cop)), p_ip);
  return jsonb_build_object('documento', v_doc, 'habilitado', p_habilitado, 'copias_internas', to_jsonb(v_cop));
end $_$;


--
-- Name: geoportal_envio_nuevo_texto(text, text, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_envio_nuevo_texto(p_solicitante text, p_texto text, p_borrador boolean, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'salida', 'acta', 'pg_temp'
    AS $$
declare v_email text; v_ver int;
begin
  v_email := acta.f_autorizar(p_solicitante, 'administrar');
  if p_texto is null or length(btrim(p_texto)) < 20 or length(btrim(p_texto)) > 2000 then perform salida.f_error('El texto debe tener entre 20 y 2.000 caracteres'); end if;
  if p_borrador is null then perform salida.f_error('Indique si el texto sigue como borrador'); end if;
  insert into salida.textos_autorizacion (texto, borrador, creado_por) values (btrim(p_texto), p_borrador, v_email) returning version into v_ver;
  -- un texto nuevo apaga todo hasta que se vuelva a habilitar (la autorización de los capturistas se rige por el texto vigente)
  update salida.config_documentos set habilitado = false, actualizado_por = v_email, actualizado_en = clock_timestamp() where habilitado and p_borrador;
  perform acta.f_auditar(v_email, 'envio_nuevo_texto', v_ver::text, jsonb_build_object('borrador', p_borrador), p_ip);
  return jsonb_build_object('version', v_ver, 'borrador', p_borrador);
end $$;


--
-- Name: geoportal_envio_preparar(text, text, uuid, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_envio_preparar(p_solicitante text, p_documento text, p_registro_id uuid, p_contacto jsonb, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'salida', 'acta', 'campo', 'pg_temp'
    AS $_$
declare v_email text; v_doc text := btrim(coalesce(p_documento, '')); v_cfg salida.config_documentos%rowtype; v_t salida.textos_autorizacion%rowtype; v_esq text;
        v_correo text; v_cel text; v_parte text; v_ver int; v_k text; v_ya boolean; v_a acta.actas%rowtype; v_r campo.reportes%rowtype; v_envio uuid; v_cons text; v_const jsonb;
begin
  v_email := salida.f_autorizar_captura(p_solicitante, v_doc);
  if p_registro_id is null then perform salida.f_error('Falta el identificador del registro'); end if;
  select * into v_cfg from salida.config_documentos where documento = v_doc;
  if not v_cfg.habilitado then return jsonb_build_object('estado', 'apagado'); end if;
  if p_contacto is null or jsonb_typeof(p_contacto) <> 'object' then perform salida.f_error('El bloque de contacto no tiene el formato esperado'); end if;
  for v_k in select jsonb_object_keys(p_contacto) loop
    if v_k <> all (array['correo', 'celular', 'parte', 'autoriza', 'texto_version']) then perform salida.f_error(format('El dato «%s» no existe en la constancia', v_k)); end if;
  end loop;
  if p_contacto -> 'autoriza' is distinct from 'true'::jsonb then perform salida.f_error('Sin la autorización del titular no se envía la constancia'); end if;
  v_correo := lower(btrim(coalesce(p_contacto ->> 'correo', '')));
  if v_correo !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or length(v_correo) > 254 then perform salida.f_error('El correo no es válido'); end if;
  v_cel := nullif(regexp_replace(coalesce(p_contacto ->> 'celular', ''), '[ .-]', '', 'g'), '');
  if v_cel is not null and v_cel !~ '^3[0-9]{9}$' then perform salida.f_error('El celular debe tener 10 dígitos y empezar por 3'); end if;
  v_parte := coalesce(nullif(p_contacto ->> 'parte', ''), 'otro');
  if v_parte not in ('quien_atendio', 'suscriptor', 'otro') then perform salida.f_error('Indique a quién va la constancia'); end if;
  v_t := salida.f_texto_vigente();
  begin v_ver := (p_contacto ->> 'texto_version')::int; exception when others then v_ver := null; end;
  if v_ver is distinct from v_t.version then perform salida.f_error('El texto de autorización cambió: vuelva a cargar el formulario', '55000'); end if;

  v_esq := case when v_doc = 'acta_inspeccion' then 'acta' else 'campo' end;
  -- el registro debe ser del solicitante: apertura (acta) o reserva de reporte (campo)
  if v_esq = 'acta' then
    if not exists (select 1 from acta.aperturas a where a.id = p_registro_id and a.autor = v_email and a.correccion_de is null) then perform salida.f_error('Identificador de acta no válido'); end if;
  else
    if not exists (select 1 from campo.preparaciones p where p.reporte_id = p_registro_id and p.autor = v_email) then perform salida.f_error('Identificador de reporte no válido'); end if;
  end if;
  if exists (select 1 from salida.envios e where e.esquema_origen = v_esq and e.registro_id = p_registro_id) then return jsonb_build_object('estado', 'ya_encolado'); end if;
  insert into salida.contactos (esquema_origen, registro_id, documento, correo, celular, parte, autoriza, texto_version, autor)
  values (v_esq, p_registro_id, v_doc, v_correo, v_cel, v_parte, true, v_ver, v_email)
  on conflict (esquema_origen, registro_id) do update set correo = excluded.correo, celular = excluded.celular, parte = excluded.parte, texto_version = excluded.texto_version
    where salida.contactos.autor = v_email and salida.contactos.depurado_en is null;
  perform acta.f_auditar(v_email, 'envio_reservar_contacto', p_registro_id::text, jsonb_build_object('documento', v_doc, 'con_celular', v_cel is not null), p_ip);   -- nunca el correo ni el celular

  -- ¿el registro ya se hizo? (reintento tras corte de red): se encola en el acto si es del solicitante, versión 1 y reciente
  v_ya := false;
  if v_esq = 'acta' then
    select * into v_a from acta.actas where id = p_registro_id;
    if found then v_ya := true; if v_a.version = 1 and v_a.autor = v_email and v_a.registrado_en > clock_timestamp() - make_interval(mins => salida.f_param('ventana_posterior_min')::int) then v_cons := v_a.consecutivo; v_const := salida.f_constancia_acta(v_a.id); end if; end if;
  else
    select * into v_r from campo.reportes where id = p_registro_id;
    if found then v_ya := true; if v_r.autor = v_email and v_r.registrado_en > clock_timestamp() - make_interval(mins => salida.f_param('ventana_posterior_min')::int) then v_cons := coalesce(v_r.consecutivo, ''); v_const := salida.f_constancia_campo(v_r.id); end if; end if;
  end if;
  if not v_ya then return jsonb_build_object('estado', 'reservado'); end if;
  if exists (select 1 from salida.envios e where e.esquema_origen = v_esq and e.registro_id = p_registro_id) then return jsonb_build_object('estado', 'ya_encolado'); end if;
  if v_const is null then return jsonb_build_object('estado', 'fuera_de_ventana'); end if;
  v_envio := salida.f_encolar(v_esq, p_registro_id, v_doc, v_cons, v_const, v_email);
  return jsonb_build_object('estado', case when v_envio is null then 'sin_destino' else 'encolado' end);
end $_$;


--
-- Name: geoportal_es_admin(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_es_admin(p_email text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$ select exists (select 1 from public.geoportal_lista_blanca where email = lower(p_email) and activo and rol = 'admin'); $$;


--
-- Name: geoportal_estado_acceso(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_estado_acceso(p_email text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with ahora as (select now() at time zone 'America/Bogota' as ts),
  u as (select lb.rol, lb.horario, lb.dias from public.geoportal_lista_blanca lb where lb.email = lower(p_email) and lb.activo limit 1),
  cfg as (select pausado from public.geoportal_config where id = 1)
  select case
    when not (public.geoportal_dominio_ok(p_email) and exists (select 1 from u)) then 'denegado'
    when (select rol from u) = 'admin' then 'ok'
    when coalesce((select pausado from cfg), false) then 'pausado'
    when (select dias from u) = 'habiles' and extract(dow from (select ts from ahora)) not between 1 and 5 then 'fuera_horario'
    when (select horario from u) = 'sin_restriccion' then 'ok'
    when (select ts from ahora)::time between time '07:00' and (case when (select horario from u) = 'extendido' then time '22:00' else time '18:00' end) then 'ok'
    else 'fuera_horario' end; $$;


--
-- Name: geoportal_log(text, text, text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_log(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    AS $$ insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values (lower(p_email), p_accion, p_ref, p_detalle, p_ip); $$;


--
-- Name: geoportal_mis_permisos(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_mis_permisos(p_email text) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    (select jsonb_build_object(
       'rol', lb.rol, 'explorar', lb.ver_explorar, 'focalizacion', lb.ver_focalizacion, 'comercial', lb.ver_comercial,
       'rutas', lb.ver_rutas, 'dashboard', lb.ver_dashboard,
       'registro_tecnico', lb.ver_registro_tecnico, 'dashboard_tecnico', lb.ver_dashboard_tecnico,
       'campo', (lb.rol = 'admin' or lb.ver_campo or lb.ver_dashboard_campo),
       'dashboard_campo', (lb.rol = 'admin' or lb.ver_dashboard_campo),
       'acta', (lb.rol = 'admin' or lb.ver_acta or lb.ver_dashboard_acta),
       'dashboard_acta', (lb.rol = 'admin' or lb.ver_dashboard_acta),
       'aseo', (lb.rol = 'admin' or lb.ver_aseo or lb.ver_dashboard_aseo),
       'dashboard_aseo', (lb.rol = 'admin' or lb.ver_dashboard_aseo),
       'analisis_contrato', (lb.rol = 'admin' or lb.ver_analisis_contrato),
       'torre_a', (lb.rol = 'admin' or lb.ver_explorar or lb.ver_focalizacion or lb.ver_comercial or lb.ver_rutas or lb.ver_dashboard
                   or lb.ver_campo or lb.ver_dashboard_campo or lb.ver_acta or lb.ver_dashboard_acta or lb.ver_analisis_contrato),
       'torre_b', (lb.rol = 'admin' or lb.ver_registro_tecnico or lb.ver_dashboard_tecnico),
       'torre_c', (lb.rol = 'admin' or lb.ver_aseo or lb.ver_dashboard_aseo))
     from public.geoportal_lista_blanca lb
     where lb.email = lower(p_email) and lb.activo limit 1),
    jsonb_build_object('rol','consulta','explorar',true,'focalizacion',false,'comercial',false,'rutas',false,'dashboard',false,
                       'registro_tecnico',false,'dashboard_tecnico',false,'campo',false,'dashboard_campo',false,'acta',false,'dashboard_acta',false,
                       'aseo',false,'dashboard_aseo',false,'analisis_contrato',false,'torre_a',false,'torre_b',false,'torre_c',false));
$$;


--
-- Name: geoportal_puede(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_puede(p_email text, p_modo text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce((
    select case
      when lb.rol = 'admin' then true
      when p_modo = 'explorar' then lb.ver_explorar
      when p_modo = 'focalizacion' then lb.ver_focalizacion
      when p_modo = 'comercial' then lb.ver_comercial
      when p_modo = 'rutas' then lb.ver_rutas
      when p_modo = 'dashboard' then lb.ver_dashboard
      when p_modo = 'registro_tecnico' then lb.ver_registro_tecnico
      when p_modo = 'dashboard_tecnico' then lb.ver_dashboard_tecnico
      when p_modo = 'campo' then (lb.ver_campo or lb.ver_dashboard_campo)
      when p_modo = 'dashboard_campo' then lb.ver_dashboard_campo
      when p_modo = 'acta' then (lb.ver_acta or lb.ver_dashboard_acta)
      when p_modo = 'dashboard_acta' then lb.ver_dashboard_acta
      when p_modo = 'aseo' then (lb.ver_aseo or lb.ver_dashboard_aseo)          -- el supervisor de aseo también captura
      when p_modo = 'dashboard_aseo' then lb.ver_dashboard_aseo
      when p_modo = 'analisis_contrato' then lb.ver_analisis_contrato   -- Análisis de contrato (consulta con nombre y teléfono)
      else false
    end
    from public.geoportal_lista_blanca lb
    where lb.email = lower(p_email) and lb.activo
    limit 1), false);
$$;


--
-- Name: geoportal_sin_acceso_comercial(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_sin_acceso_comercial(p_email text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce((select lb.rol <> 'admin' and not (lb.ver_explorar or lb.ver_focalizacion or lb.ver_comercial or lb.ver_rutas or lb.ver_dashboard)
    from public.geoportal_lista_blanca lb where lb.email = lower(p_email) and lb.activo limit 1), false); $$;


--
-- Name: geoportal_tec_asignar_formulario(text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_tec_asignar_formulario(p_solicitante text, p_persona text, p_formulario text, p_motivo text DEFAULT NULL::text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v_email text; v_persona text; v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  if not exists (select 1 from tecnica.f_formularios() f where f.clave = p_formulario) then perform tecnica.f_error('Formulario desconocido', 'P0002'); end if;
  if v_motivo is not null and length(v_motivo) < 3 then perform tecnica.f_error('El motivo es demasiado corto'); end if;
  v_persona := tecnica.f_validar_persona(p_persona, true);
  perform pg_advisory_xact_lock(hashtextextended('pte|' || v_persona, 0));
  if tecnica.f_formulario_asignado(v_persona, p_formulario) then
    return jsonb_build_object('persona', v_persona, 'formulario', p_formulario, 'asignado', true, 'cambio', false);
  end if;
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, motivo, autor)
  values (v_persona, 'asignar_formulario', p_formulario, v_motivo, v_email);
  insert into tecnica.senal_cambio (tabla) values ('personal_tecnico_eventos');
  perform tecnica.f_auditar(v_email, 'tec_asignar_formulario', v_persona, jsonb_build_object('formulario', p_formulario), p_ip);
  return jsonb_build_object('persona', v_persona, 'formulario', p_formulario, 'asignado', true, 'cambio', true);
end $$;


--
-- Name: geoportal_tec_cambiar_estado_tecnica(text, text, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_tec_cambiar_estado_tecnica(p_solicitante text, p_persona text, p_activo boolean, p_motivo text DEFAULT NULL::text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v_email text; v_persona text; v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  if p_activo is null then perform tecnica.f_error('Indique si la persona queda activa o desactivada en Técnica'); end if;
  if p_activo = false and (v_motivo is null or length(v_motivo) < 10) then perform tecnica.f_error('Indique el motivo (mínimo 10 caracteres)'); end if;
  if v_motivo is not null and length(v_motivo) < 3 then perform tecnica.f_error('El motivo es demasiado corto'); end if;
  v_persona := tecnica.f_validar_persona(p_persona, false);
  perform pg_advisory_xact_lock(hashtextextended('pte|' || v_persona, 0));
  if tecnica.f_tecnica_activa(v_persona) = p_activo then
    return jsonb_build_object('persona', v_persona, 'activo', p_activo, 'cambio', false);
  end if;
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, motivo, autor)
  values (v_persona, case when p_activo then 'activar_tecnica' else 'desactivar_tecnica' end, v_motivo, v_email);
  insert into tecnica.senal_cambio (tabla) values ('personal_tecnico_eventos');
  perform tecnica.f_auditar(v_email, case when p_activo then 'tec_activar' else 'tec_desactivar' end, v_persona, null, p_ip);
  return jsonb_build_object('persona', v_persona, 'activo', p_activo, 'cambio', true);
end $$;


--
-- Name: geoportal_tec_excluir_registro(text, uuid, bigint, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_tec_excluir_registro(p_solicitante text, p_lote_id uuid DEFAULT NULL::uuid, p_registro_id bigint DEFAULT NULL::bigint, p_motivo text DEFAULT NULL::text, p_accion text DEFAULT 'EXCLUIR'::text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v_email text; v_accion text := upper(btrim(coalesce(p_accion, ''))); v_motivo text := btrim(coalesce(p_motivo, ''));
        v_lote uuid; v_id bigint; v_afectados int; v_excluido boolean;
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  if num_nonnulls(p_lote_id, p_registro_id) <> 1 then perform tecnica.f_error('Indique el lote o el registro, no ambos'); end if;
  if v_accion not in ('EXCLUIR', 'REINCLUIR') then perform tecnica.f_error('Acción no válida: use EXCLUIR o REINCLUIR'); end if;
  if length(v_motivo) < 10 or length(v_motivo) > 1000 then perform tecnica.f_error('El motivo debe tener entre 10 y 1000 caracteres'); end if;

  if p_registro_id is not null then
    select r.lote_id into v_lote from tecnica.registros r where r.id = p_registro_id;
    if not found then perform tecnica.f_error('El registro no existe', 'P0002'); end if;
  else
    v_lote := p_lote_id;
    if not exists (select 1 from tecnica.registros r where r.lote_id = v_lote) then perform tecnica.f_error('El lote no existe', 'P0002'); end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_lote::text, 0));      -- serializa a quienes gestionan el mismo lote

  if p_registro_id is not null then
    select s.excluido into v_excluido from tecnica.v_registros_estado s where s.id = p_registro_id;
    if v_accion = 'EXCLUIR' and v_excluido then perform tecnica.f_error('El registro ya está excluido', '55000'); end if;
    if v_accion = 'REINCLUIR' and not v_excluido then perform tecnica.f_error('El registro ya está incluido', '55000'); end if;
    v_afectados := 1;
  else
    select count(*) into v_afectados from tecnica.v_registros_estado s where s.lote_id = v_lote and s.excluido = (v_accion = 'REINCLUIR');
    if v_afectados = 0 then
      perform tecnica.f_error(case when v_accion = 'EXCLUIR' then 'Todo el lote ya está excluido' else 'Todo el lote ya está incluido' end, '55000');
    end if;
  end if;

  insert into tecnica.exclusiones (registro_id, lote_id, accion, motivo, autor)
  values (p_registro_id, p_lote_id, v_accion, v_motivo, v_email) returning id into v_id;
  insert into tecnica.senal_cambio (tabla) values ('exclusiones');
  perform tecnica.f_auditar(v_email, 'tec_' || lower(v_accion), coalesce(p_registro_id::text, p_lote_id::text),
                            jsonb_build_object('alcance', case when p_registro_id is null then 'lote' else 'registro' end, 'afectados', v_afectados), p_ip);
  return jsonb_build_object('id', v_id, 'accion', v_accion, 'alcance', case when p_registro_id is null then 'lote' else 'registro' end,
                            'afectados', v_afectados);
end $$;


--
-- Name: geoportal_tec_listar_registros(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_tec_listar_registros(p_solicitante text, p_filtros jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare
  v_email text; v_f jsonb := coalesce(p_filtros, '{}'::jsonb);
  v_desde date; v_hasta date; v_planta text; v_form text; v_estado text; v_despues bigint; v_limite int;
  v_total bigint; v_filas jsonb;
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  if jsonb_typeof(v_f) <> 'object' then perform tecnica.f_error('Filtros inválidos'); end if;
  begin
    v_desde := nullif(v_f ->> 'desde', '')::date;
    v_hasta := nullif(v_f ->> 'hasta', '')::date;
    v_despues := nullif(v_f ->> 'despues_de', '')::bigint;
    v_limite := nullif(v_f ->> 'limite', '')::int;
  exception when others then
    perform tecnica.f_error('Algún filtro no es válido (fechas AAAA-MM-DD, números enteros)');
  end;
  v_planta := nullif(lower(btrim(coalesce(v_f ->> 'planta', ''))), '');
  v_form   := nullif(lower(btrim(coalesce(v_f ->> 'formulario', ''))), '');
  v_estado := coalesce(nullif(lower(btrim(coalesce(v_f ->> 'estado', ''))), ''), 'todos');
  if v_estado not in ('todos', 'vigentes', 'excluidos') then perform tecnica.f_error('Estado no válido'); end if;
  if v_limite is not null and v_limite < 1 then perform tecnica.f_error('El límite debe ser mayor que cero'); end if;

  select count(*) into v_total from tecnica.v_registros_detalle d
   where (v_desde is null or d.fecha_muestra >= v_desde) and (v_hasta is null or d.fecha_muestra <= v_hasta)
     and (v_planta is null or d.planta = v_planta) and (v_form is null or d.formulario = v_form)
     and (v_estado = 'todos' or (v_estado = 'excluidos') = d.excluido);

  select coalesce(jsonb_agg(jsonb_build_object(
           'registro_id', x.registro_id, 'lote_id', x.lote_id, 'formulario', x.formulario,
           'variable', x.variable, 'variable_nombre', x.variable_nombre, 'unidad', x.unidad, 'decimales', x.decimales, 'valor', x.valor,
           'planta', x.planta, 'planta_nombre', x.planta_nombre, 'punto', x.punto, 'punto_nombre', x.punto_nombre,
           'fecha_muestra', x.fecha_muestra, 'hora_muestra', to_char(x.hora_muestra, 'HH24:MI'),
           'registrado_en', x.registrado_en, 'autor', x.autor, 'fuera_de_rango', x.fuera_de_rango,
           'excluido', x.excluido, 'exclusion_motivo', x.exclusion_motivo, 'exclusion_autor', x.exclusion_autor, 'exclusion_en', x.exclusion_en)
         order by x.registro_id desc), '[]'::jsonb)
    into v_filas
    from (select d.* from tecnica.v_registros_detalle d
           where (v_desde is null or d.fecha_muestra >= v_desde) and (v_hasta is null or d.fecha_muestra <= v_hasta)
             and (v_planta is null or d.planta = v_planta) and (v_form is null or d.formulario = v_form)
             and (v_estado = 'todos' or (v_estado = 'excluidos') = d.excluido)
             and (v_despues is null or d.registro_id < v_despues)
           order by d.registro_id desc
           limit v_limite) x;                       -- limit null = sin tope

  return jsonb_build_object('total', v_total, 'devueltos', jsonb_array_length(v_filas), 'registros', v_filas);
end $$;


--
-- Name: geoportal_tec_mis_formularios(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_tec_mis_formularios(p_solicitante text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v_email text; v_perfil text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'registro_tecnico');
  v_perfil := tecnica.f_perfil(v_email);
  if v_perfil <> 'admin' and not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'perfil', v_perfil,
    'formularios', coalesce((
      select jsonb_agg(jsonb_build_object(
               'clave', f.clave, 'nombre', f.nombre, 'descripcion', f.descripcion,
               'con_campos', exists (select 1 from tecnica.formulario_variables fv join tecnica.variables v on v.id = fv.variable_id
                                      where fv.formulario = f.clave and fv.activa and v.activa)) order by f.orden)
        from tecnica.f_formularios() f
       where v_perfil in ('admin', 'supervisor') or tecnica.f_formulario_asignado(v_email, f.clave)), '[]'::jsonb));
end $$;


--
-- Name: geoportal_tec_obtener_formulario(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_tec_obtener_formulario(p_solicitante text, p_formulario text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v_email text; v_f record; v_ahora timestamp := tecnica.f_ahora_bogota(); v_hora time;
begin
  v_email := tecnica.f_autorizar_captura(p_solicitante, p_formulario);
  select * into v_f from tecnica.f_formularios() f where f.clave = p_formulario;
  if not found then perform tecnica.f_error('Formulario desconocido', 'P0002'); end if;
  -- Hora propuesta: ahora menos 15 minutos, sin cruzar la medianoche hacia el día anterior.
  v_hora := case when v_ahora::time < time '00:15' then time '00:00' else v_ahora::time - interval '15 minutes' end;
  return jsonb_build_object(
    'formulario', jsonb_build_object('clave', v_f.clave, 'nombre', v_f.nombre, 'descripcion', v_f.descripcion),
    'fecha_hoy', to_char(v_ahora, 'YYYY-MM-DD'),
    'hora_propuesta', to_char(v_hora, 'HH24:MI'),
    'plantas', coalesce((select jsonb_agg(jsonb_build_object('codigo', pl.codigo, 'nombre', pl.nombre) order by pl.id)
                           from tecnica.plantas pl where pl.activa), '[]'::jsonb),
    'puntos', coalesce((select jsonb_agg(jsonb_build_object('codigo', pu.codigo, 'nombre', pu.nombre, 'tipo', pu.tipo, 'planta', pl.codigo) order by pu.codigo)
                          from tecnica.puntos pu left join tecnica.plantas pl on pl.id = pu.planta_id where pu.activo), '[]'::jsonb),
    'variables', coalesce((
      select jsonb_agg(jsonb_build_object(
               'codigo', v.codigo, 'nombre', v.nombre, 'unidad', v.unidad, 'categoria', v.categoria, 'decimales', v.decimales,
               'orden', fv.orden, 'obligatoria', fv.obligatoria, 'alcance', fv.alcance,
               'punto', case when pu.id is null then null else jsonb_build_object('codigo', pu.codigo, 'nombre', pu.nombre) end)
             order by fv.orden, v.id)
        from tecnica.formulario_variables fv
        join tecnica.variables v on v.id = fv.variable_id
        left join tecnica.puntos pu on pu.id = fv.punto_id
       where fv.formulario = p_formulario and fv.activa and v.activa), '[]'::jsonb));
end $$;


--
-- Name: geoportal_tec_quitar_formulario(text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_tec_quitar_formulario(p_solicitante text, p_persona text, p_formulario text, p_motivo text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v_email text; v_persona text; v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  v_email := tecnica.f_autorizar_supervision(p_solicitante);
  if not exists (select 1 from tecnica.f_formularios() f where f.clave = p_formulario) then perform tecnica.f_error('Formulario desconocido', 'P0002'); end if;
  if length(v_motivo) < 10 then perform tecnica.f_error('Indique el motivo (mínimo 10 caracteres)'); end if;
  v_persona := tecnica.f_validar_persona(p_persona, false);
  perform pg_advisory_xact_lock(hashtextextended('pte|' || v_persona, 0));
  if not tecnica.f_formulario_asignado(v_persona, p_formulario) then
    return jsonb_build_object('persona', v_persona, 'formulario', p_formulario, 'asignado', false, 'cambio', false);
  end if;
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, motivo, autor)
  values (v_persona, 'quitar_formulario', p_formulario, v_motivo, v_email);
  insert into tecnica.senal_cambio (tabla) values ('personal_tecnico_eventos');
  perform tecnica.f_auditar(v_email, 'tec_quitar_formulario', v_persona, jsonb_build_object('formulario', p_formulario), p_ip);
  return jsonb_build_object('persona', v_persona, 'formulario', p_formulario, 'asignado', false, 'cambio', true);
end $$;


--
-- Name: geoportal_tec_registrar_medicion(text, text, text, text, jsonb, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_tec_registrar_medicion(p_solicitante text, p_formulario text, p_planta text, p_hora_muestra text, p_valores jsonb, p_punto text DEFAULT NULL::text, p_clave_envio text DEFAULT NULL::text, p_ip text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $_$
declare
  v_email text; v_hora time; v_fecha date; v_planta_id bigint; v_punto_id bigint; v_lote uuid := gen_random_uuid();
  v_item jsonb; v_cod text; v_val jsonb; v_num numeric; v_txt text;
  fv record; v_n int := 0; v_vistos text[] := '{}'; v_previo uuid; v_nprevio int;
begin
  v_email := tecnica.f_autorizar_captura(p_solicitante, p_formulario);
  if not exists (select 1 from tecnica.f_formularios() f where f.clave = p_formulario) then
    perform tecnica.f_error('Formulario desconocido', 'P0002');
  end if;

  -- Reintento del mismo envío (celular con mala señal): devuelve el lote original sin duplicar.
  if p_clave_envio is not null then
    if p_clave_envio !~ '^[A-Za-z0-9_-]{8,80}$' then perform tecnica.f_error('Clave de envío inválida'); end if;
    perform pg_advisory_xact_lock(hashtextextended(v_email || '|' || p_clave_envio, 0));
    select r.lote_id, count(*) into v_previo, v_nprevio from tecnica.registros r
     where r.autor = v_email and r.clave_envio = p_clave_envio group by r.lote_id limit 1;
    if v_previo is not null then
      return jsonb_build_object('lote_id', v_previo, 'formulario', p_formulario, 'guardados', v_nprevio, 'duplicado', true);
    end if;
  end if;

  -- Hora de la muestra (la fecha NO se recibe: la calcula el servidor).
  begin
    v_hora := date_trunc('minute', btrim(coalesce(p_hora_muestra, ''))::time);
  exception when others then
    perform tecnica.f_error('La hora de la muestra no es válida. Use el formato HH:MM');
  end;
  v_fecha := tecnica.f_fecha_muestra(v_hora);

  if p_planta is not null and btrim(p_planta) <> '' then
    select pl.id into v_planta_id from tecnica.plantas pl where pl.codigo = lower(btrim(p_planta)) and pl.activa;
    if not found then perform tecnica.f_error('La planta no es válida'); end if;
  end if;

  if p_punto is not null and btrim(p_punto) <> '' then
    select pu.id into v_punto_id from tecnica.puntos pu
     where pu.codigo = upper(btrim(p_punto)) and pu.activo and (pu.planta_id is null or v_planta_id is null or pu.planta_id = v_planta_id);
    if not found then perform tecnica.f_error('El punto no existe, está inactivo o no corresponde a la planta elegida'); end if;
  end if;

  if p_valores is null or jsonb_typeof(p_valores) <> 'array' or jsonb_array_length(p_valores) not between 1 and 60 then
    perform tecnica.f_error('Debe enviar entre 1 y 60 valores');
  end if;

  for v_item in select e.value from jsonb_array_elements(p_valores) e loop
    if jsonb_typeof(v_item) <> 'object' then perform tecnica.f_error('Cada valor debe indicar su variable'); end if;
    v_cod := lower(btrim(coalesce(v_item ->> 'variable', '')));
    select f.alcance, f.punto_id, f.variable_id, v.nombre into fv
      from tecnica.formulario_variables f join tecnica.variables v on v.id = f.variable_id
     where f.formulario = p_formulario and v.codigo = v_cod and f.activa and v.activa;
    if not found then perform tecnica.f_error('La variable «' || left(v_cod, 40) || '» no pertenece a este formulario'); end if;
    if v_cod = any (v_vistos) then perform tecnica.f_error('La variable «' || fv.nombre || '» viene repetida'); end if;
    v_vistos := v_vistos || v_cod;

    v_val := v_item -> 'valor';
    -- vacío: no se guarda (si la variable es obligatoria se detecta después)
    if v_val is null or jsonb_typeof(v_val) = 'null' or (jsonb_typeof(v_val) = 'string' and btrim(v_val #>> '{}') = '') then
      continue;
    end if;
    if jsonb_typeof(v_val) = 'number' then
      v_num := (v_val #>> '{}')::numeric;
    elsif jsonb_typeof(v_val) = 'string' then
      v_txt := btrim(v_val #>> '{}');
      if v_txt !~ '^-?[0-9]+(\.[0-9]+)?$' then
        perform tecnica.f_error('El valor de «' || fv.nombre || '» no es un número');
      end if;
      v_num := v_txt::numeric;
    else
      perform tecnica.f_error('El valor de «' || fv.nombre || '» no es un número');
    end if;

    if fv.alcance = 'por_planta' and v_planta_id is null then
      perform tecnica.f_error('Elija la planta para «' || fv.nombre || '»');
    end if;
    if fv.punto_id is not null and v_punto_id is not null and fv.punto_id <> v_punto_id then
      perform tecnica.f_error('El punto elegido no corresponde a la variable «' || fv.nombre || '»');
    end if;

    insert into tecnica.registros (lote_id, formulario, variable_id, planta_id, punto_id, valor, fecha_muestra, hora_muestra, autor, clave_envio)
    values (v_lote, p_formulario, fv.variable_id, case when fv.alcance = 'por_planta' then v_planta_id end, coalesce(fv.punto_id, v_punto_id),
            v_num, v_fecha, v_hora, v_email, p_clave_envio);
    v_n := v_n + 1;
  end loop;

  if v_n = 0 then perform tecnica.f_error('No hay valores para guardar'); end if;

  -- Obligatorias que no llegaron con valor.
  for fv in
    select v.nombre from tecnica.formulario_variables f join tecnica.variables v on v.id = f.variable_id
     where f.formulario = p_formulario and f.activa and v.activa and f.obligatoria
       and not exists (select 1 from tecnica.registros r where r.lote_id = v_lote and r.variable_id = f.variable_id)
     order by f.orden limit 1
  loop
    perform tecnica.f_error('Falta el valor de «' || fv.nombre || '»');
  end loop;

  insert into tecnica.senal_cambio (tabla, planta_id) values ('registros', v_planta_id);
  perform tecnica.f_auditar(v_email, 'tec_registrar', v_lote::text, jsonb_build_object('formulario', p_formulario, 'valores', v_n), p_ip);

  -- La confirmación NO incluye marcas de rango ni la hora del servidor (el operador no las ve).
  return jsonb_build_object('lote_id', v_lote, 'formulario', p_formulario, 'fecha_muestra', v_fecha,
                            'hora_muestra', to_char(v_hora, 'HH24:MI'), 'guardados', v_n, 'duplicado', false);
end $_$;


--
-- Name: geoportal_tec_resumen_operador(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geoportal_tec_resumen_operador(p_solicitante text, p_formulario text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v_email text;
begin
  v_email := tecnica.f_autorizar_captura(p_solicitante, p_formulario);
  return jsonb_build_object('formulario', p_formulario, 'ventana_horas', 24, 'filas', coalesce((
    select jsonb_agg(jsonb_build_object(
             'variable', v.codigo, 'nombre', v.nombre, 'unidad', v.unidad, 'decimales', v.decimales,
             'planta', x.planta, 'planta_nombre', x.planta_nombre,
             'promedio', round(st.prom, 6), 'minimo', st.mn, 'maximo', st.mx)
           order by fv.orden, v.id, x.orden_planta)
      from tecnica.formulario_variables fv
      join tecnica.variables v on v.id = fv.variable_id
      cross join lateral (
        select null::text as planta, null::text as planta_nombre, null::bigint as pid, 0::bigint as orden_planta where fv.alcance = 'ambas_plantas'
        union all
        select pl.codigo, pl.nombre, pl.id, pl.id from tecnica.plantas pl where fv.alcance = 'por_planta' and pl.activa) x
      left join lateral (
        select avg(s.valor) as prom, min(s.valor) as mn, max(s.valor) as mx
          from tecnica.v_registros_estado s
         where s.formulario = fv.formulario and s.variable_id = fv.variable_id and s.planta_id is not distinct from x.pid
           and not s.excluido
           and s.muestra_ts >= clock_timestamp() - interval '24 hours' and s.muestra_ts <= clock_timestamp() + interval '5 minutes') st on true
     where fv.formulario = p_formulario and fv.activa and v.activa), '[]'::jsonb));
end $$;


--
-- Name: st_distance(public.geography, public.geography); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.st_distance(a public.geography, b public.geography) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $$
  select 2*6371008.8*asin(sqrt(power(sin(radians(b.y-a.y)/2),2)+cos(radians(a.y))*cos(radians(b.y))*power(sin(radians(b.x-a.x)/2),2))) $$;


--
-- Name: st_distancesphere(public.geometry, public.geometry); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.st_distancesphere(public.geometry, public.geometry) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $_$ select 2 * 6370986 * asin(sqrt(power(sin(radians(st_y($2) - st_y($1)) / 2), 2) + cos(radians(st_y($1))) * cos(radians(st_y($2))) * power(sin(radians(st_x($2) - st_x($1)) / 2), 2))) $_$;


--
-- Name: st_dwithin(public.geography, public.geography, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.st_dwithin(a public.geography, b public.geography, m double precision) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$select st_distance(a,b) <= m$$;


--
-- Name: st_x(public.geometry); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.st_x(public.geometry) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $_$ select ($1).x $_$;


--
-- Name: st_y(public.geometry); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.st_y(public.geometry) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $_$ select ($1).y $_$;


--
-- Name: f_funciones_sin_where(); Type: FUNCTION; Schema: redes; Owner: -
--

CREATE FUNCTION redes.f_funciones_sin_where() RETURNS TABLE(funcion text, sentencia text)
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog'
    AS $_$
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
   order by 1, 2 $_$;


--
-- Name: f_autorizar_captura(text, text); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_autorizar_captura(p_solicitante text, p_documento text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'campo', 'salida', 'pg_temp'
    AS $$
begin
  if p_documento = 'acta_inspeccion' then return acta.f_autorizar(p_solicitante, 'capturar');
  elsif p_documento in ('revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida') then return campo.f_autorizar_reporte(p_solicitante);
  end if;
  perform salida.f_error('El documento no envía constancias');
  return null;
end $$;


--
-- Name: f_constancia_acta(uuid); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_constancia_acta(p_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'acta', 'pg_temp'
    AS $$
  select jsonb_build_object('documento', 'Acta de inspección técnica', 'consecutivo', a.consecutivo,
         'registrado_en_bogota', to_char(a.registrado_en at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'),
         'contrato', a.contrato, 'direccion', a.direccion,
         'resultado', case when a.sin_irregularidad then 'Sin irregularidad' else 'Con irregularidad' end,
         'leyenda', 'Esta constancia no es el acta. El acta física firmada es el documento con valor probatorio.')
    from acta.actas a where a.id = p_id; $$;


--
-- Name: f_constancia_campo(uuid); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_constancia_campo(p_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'campo', 'pg_temp'
    AS $$
  select jsonb_build_object('documento', t.nombre, 'consecutivo', r.consecutivo,
         'registrado_en_bogota', to_char(r.registrado_en at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'),
         'contrato', r.contrato, 'direccion', null,
         'resultado', case r.resultado when 'efectivo' then 'Visita efectiva' when 'inefectivo' then 'Visita inefectiva' else null end,
         'leyenda', 'Esta constancia no es el acta. El acta física firmada es el documento con valor probatorio.')
    from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id where r.id = p_id; $$;


--
-- Name: f_contacto_actualizable(); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_contacto_actualizable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.id <> old.id or new.esquema_origen <> old.esquema_origen or new.registro_id <> old.registro_id or new.documento <> old.documento or new.autor <> old.autor then
    raise exception 'Esos datos del contacto no cambian' using errcode = '55000';
  end if;
  if old.depurado_en is not null then raise exception 'El contacto ya fue depurado' using errcode = '55000'; end if;
  if new.depurado_en is not null then return new; end if;     -- depuración (el check de la tabla exige correo y celular nulos)
  if exists (select 1 from salida.envios e where e.contacto_id = old.id) then raise exception 'El contacto ya tiene un envío: no se modifica' using errcode = '55000'; end if;
  return new;
end $$;


--
-- Name: f_depurar(text, boolean); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_depurar(p_actor text, p_solo_contar boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'salida', 'pg_temp'
    AS $$
declare v_meses int := salida.f_param('retencion_meses')::int; r record; n_env int := 0; n_con int := 0;
begin
  for r in select e.id, e.contacto_id, e.estado from salida.envios e
            where e.estado in ('enviado', 'rebotado', 'error', 'anulado') and e.depurado_en is null and e.destinatario_correo is not null
              and e.ultimo_cambio_en < clock_timestamp() - make_interval(months => v_meses) for update loop
    n_env := n_env + 1;
    if not p_solo_contar then
      update salida.envios set destinatario_correo = null, destinatario_celular = null, depurado_en = clock_timestamp() where id = r.id;
      if r.contacto_id is not null then update salida.contactos set correo = null, celular = null, depurado_en = clock_timestamp() where id = r.contacto_id and depurado_en is null; end if;
      insert into salida.envio_eventos (envio_id, estado_desde, estado_hasta, actor, detalle) values (r.id, r.estado, r.estado, p_actor, '{"motivo":"depuracion_retencion"}');
    end if;
  end loop;
  for r in select c.id from salida.contactos c where c.depurado_en is null and c.reservado_en < clock_timestamp() - interval '30 days'
              and not exists (select 1 from salida.envios e where e.contacto_id = c.id) for update loop
    n_con := n_con + 1;
    if not p_solo_contar then update salida.contactos set correo = null, celular = null, depurado_en = clock_timestamp() where id = r.id; end if;
  end loop;
  return jsonb_build_object('envios', n_env, 'contactos_sin_envio', n_con, 'aplicado', not p_solo_contar);
end $$;


--
-- Name: f_disparar_acta(); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_disparar_acta() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'salida', 'acta', 'pg_temp'
    AS $$
begin
  if new.version = 1 then
    begin
      perform salida.f_encolar('acta', new.id, 'acta_inspeccion', new.consecutivo, salida.f_constancia_acta(new.id), new.autor);
    exception when others then
      insert into salida.fallos_encolado (esquema_origen, registro_id, mensaje) values ('acta', new.id, left(sqlerrm, 300));
    end;
  end if;
  return null;
end $$;


--
-- Name: f_disparar_campo(); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_disparar_campo() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'salida', 'campo', 'pg_temp'
    AS $$
declare v_cod text;
begin
  select t.codigo into v_cod from campo.tipos_reporte t where t.id = new.tipo_id;
  if v_cod in ('revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida') then
    begin
      perform salida.f_encolar('campo', new.id, v_cod, coalesce(new.consecutivo, ''), salida.f_constancia_campo(new.id), new.autor);
    exception when others then
      insert into salida.fallos_encolado (esquema_origen, registro_id, mensaje) values ('campo', new.id, left(sqlerrm, 300));
    end;
  end if;
  return null;
end $$;


--
-- Name: f_encolar(text, uuid, text, text, jsonb, text); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_encolar(p_esquema text, p_registro uuid, p_documento text, p_consecutivo text, p_constancia jsonb, p_autor text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'salida', 'pg_temp'
    AS $$
declare v_cfg salida.config_documentos%rowtype; v_c salida.contactos%rowtype; v_id uuid;
begin
  select * into v_cfg from salida.config_documentos where documento = p_documento;
  if not found or not v_cfg.habilitado then return null; end if;
  if exists (select 1 from salida.envios e where e.esquema_origen = p_esquema and e.registro_id = p_registro) then return null; end if;
  select * into v_c from salida.contactos c where c.esquema_origen = p_esquema and c.registro_id = p_registro and c.documento = p_documento and c.autor = p_autor and c.depurado_en is null;
  if not found and cardinality(v_cfg.copias_internas) = 0 then return null; end if;
  insert into salida.envios (contacto_id, esquema_origen, registro_id, documento, consecutivo, destinatario_correo, destinatario_celular, parte, copias_internas, texto_version, constancia, max_intentos)
  values (v_c.id, p_esquema, p_registro, p_documento, p_consecutivo, v_c.correo, v_c.celular, v_c.parte, v_cfg.copias_internas, v_c.texto_version, p_constancia, salida.f_param('max_intentos')::int)
  returning id into v_id;
  insert into salida.envio_eventos (envio_id, estado_desde, estado_hasta, actor, detalle) values (v_id, null, 'pendiente', 'sistema', jsonb_build_object('con_titular', v_c.id is not null, 'copias', cardinality(v_cfg.copias_internas)));
  return v_id;
end $$;


--
-- Name: f_envio_actualizable(); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_envio_actualizable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.id <> old.id or new.esquema_origen <> old.esquema_origen or new.registro_id <> old.registro_id or new.documento <> old.documento or new.consecutivo <> old.consecutivo
     or new.constancia <> old.constancia or new.copias_internas <> old.copias_internas or new.creado_en <> old.creado_en or new.max_intentos <> old.max_intentos
     or new.contacto_id is distinct from old.contacto_id or new.texto_version is distinct from old.texto_version or new.parte is distinct from old.parte then
    raise exception 'El contenido del envío no cambia' using errcode = '55000';
  end if;
  if (new.destinatario_correo is distinct from old.destinatario_correo or new.destinatario_celular is distinct from old.destinatario_celular) then
    if not (new.depurado_en is not null and old.depurado_en is null and new.destinatario_correo is null and new.destinatario_celular is null) then
      raise exception 'El destinatario solo se modifica al depurar' using errcode = '55000';
    end if;
  end if;
  return new;
end $$;


--
-- Name: f_error(text, text); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_error(p_mensaje text, p_codigo text DEFAULT '22023'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin raise exception '%', p_mensaje using errcode = p_codigo, hint = 'msg_usuario'; end $$;


--
-- Name: f_param(text); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_param(p_clave text) RETURNS numeric
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'salida', 'pg_temp'
    AS $$
declare v numeric;
begin select valor into v from salida.parametros where clave = p_clave; if v is null then raise exception 'Falta el parámetro de salida %', p_clave using errcode = 'P0002'; end if; return v; end $$;


--
-- Name: f_registro_vigente(text, uuid); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_registro_vigente(p_esquema text, p_id uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'acta', 'campo', 'pg_temp'
    AS $$
begin
  if p_esquema = 'acta' then
    return exists (select 1 from acta.actas a where a.id = p_id and not acta.f_oculto(a.acta_raiz_id));
  elsif p_esquema = 'campo' then
    return exists (select 1 from campo.reportes r where r.id = p_id) and not campo.f_oculto(p_id);
  end if;
  return false;
end $$;


--
-- Name: f_solo_agregar(); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_solo_agregar() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin raise exception 'La tabla % es de solo inserción', tg_table_name using errcode = '55000'; end $$;


--
-- Name: textos_autorizacion; Type: TABLE; Schema: salida; Owner: -
--

CREATE TABLE salida.textos_autorizacion (
    version integer NOT NULL,
    texto text NOT NULL,
    borrador boolean DEFAULT true NOT NULL,
    creado_por text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT textos_autorizacion_texto_check CHECK (((length(btrim(texto)) >= 20) AND (length(btrim(texto)) <= 2000)))
);


--
-- Name: f_texto_vigente(); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.f_texto_vigente() RETURNS salida.textos_autorizacion
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'salida', 'pg_temp'
    AS $$
  select t from salida.textos_autorizacion t order by t.version desc limit 1; $$;


--
-- Name: liberar_envio(uuid, uuid); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.liberar_envio(p_envio_id uuid, p_lease_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'salida', 'pg_temp'
    AS $$
declare e salida.envios%rowtype;
begin
  select * into e from salida.envios where id = p_envio_id for update;
  if not found then raise exception 'Envío no encontrado' using errcode = 'P0002'; end if;
  if e.lease_id is distinct from p_lease_id then raise exception 'El lease no corresponde a este envío' using errcode = '22023'; end if;
  if e.estado = 'pendiente' then return e.estado; end if;
  if e.estado <> 'tomado' then raise exception 'El envío no está tomado (estado %)', e.estado using errcode = '22023'; end if;
  update salida.envios set estado = 'pendiente', intentos = greatest(intentos - 1, 0), tomado_hasta = null, ultimo_cambio_en = clock_timestamp() where id = e.id;
  insert into salida.envio_eventos (envio_id, estado_desde, estado_hasta, actor, detalle) values (e.id, 'tomado', 'pendiente', 'dell', '{"motivo":"liberado"}');
  return 'pendiente';
end $$;


--
-- Name: marcar_envio(uuid, uuid, text, jsonb, boolean); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.marcar_envio(p_envio_id uuid, p_lease_id uuid, p_estado text, p_detalle jsonb DEFAULT '{}'::jsonb, p_reintentable boolean DEFAULT false) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'salida', 'pg_temp'
    AS $$
declare e salida.envios%rowtype; v_nuevo text; v_det jsonb := coalesce(p_detalle, '{}'::jsonb); v_err text;
begin
  if p_estado not in ('enviado', 'rebotado', 'error') then raise exception 'Estado no válido: use enviado, rebotado o error' using errcode = '22023'; end if;
  if jsonb_typeof(v_det) <> 'object' or length(v_det::text) > 2048 then raise exception 'p_detalle debe ser un objeto de hasta 2 KB' using errcode = '22023'; end if;
  select * into e from salida.envios where id = p_envio_id for update;
  if not found then raise exception 'Envío no encontrado' using errcode = 'P0002'; end if;
  if e.lease_id is distinct from p_lease_id then raise exception 'El lease no corresponde a este envío' using errcode = '22023'; end if;
  if e.estado = p_estado then return e.estado; end if;                       -- cierre repetido: inocuo
  if e.estado <> 'tomado' then raise exception 'El envío no está tomado (estado %)', e.estado using errcode = '22023'; end if;
  v_err := left(v_det ->> 'error', 500);
  v_nuevo := case when p_estado = 'error' and p_reintentable and e.intentos < e.max_intentos then 'pendiente' else p_estado end;
  update salida.envios set estado = v_nuevo, tomado_hasta = null, ultimo_error = case when p_estado = 'enviado' then null else coalesce(v_err, ultimo_error) end, ultimo_cambio_en = clock_timestamp() where id = e.id;
  insert into salida.envio_eventos (envio_id, estado_desde, estado_hasta, actor, detalle) values (e.id, 'tomado', v_nuevo, 'dell', v_det);
  return v_nuevo;
end $$;


--
-- Name: reportar_rebote(uuid, jsonb); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.reportar_rebote(p_envio_id uuid, p_detalle jsonb DEFAULT '{}'::jsonb) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'salida', 'pg_temp'
    AS $$
declare e salida.envios%rowtype; v_det jsonb := coalesce(p_detalle, '{}'::jsonb);
begin
  if jsonb_typeof(v_det) <> 'object' or length(v_det::text) > 2048 then raise exception 'p_detalle debe ser un objeto de hasta 2 KB' using errcode = '22023'; end if;
  select * into e from salida.envios where id = p_envio_id for update;
  if not found then raise exception 'Envío no encontrado' using errcode = 'P0002'; end if;
  if e.estado = 'rebotado' then return e.estado; end if;
  if e.estado <> 'enviado' then raise exception 'Solo un envío enviado puede reportarse como rebotado (estado %)', e.estado using errcode = '22023'; end if;
  update salida.envios set estado = 'rebotado', ultimo_error = left(v_det ->> 'error', 500), ultimo_cambio_en = clock_timestamp() where id = e.id;
  insert into salida.envio_eventos (envio_id, estado_desde, estado_hasta, actor, detalle) values (e.id, 'enviado', 'rebotado', 'dell', v_det);
  return 'rebotado';
end $$;


--
-- Name: tomar_envios(integer, integer); Type: FUNCTION; Schema: salida; Owner: -
--

CREATE FUNCTION salida.tomar_envios(p_limite integer DEFAULT 5, p_arriendo_segundos integer DEFAULT 300) RETURNS TABLE(envio_id uuid, lease_id uuid, creado_en timestamp with time zone, documento text, consecutivo text, esquema_origen text, registro_id uuid, destinatario_correo text, destinatario_celular text, destinatario_nombre text, parte text, copias_internas text[], texto_version integer, constancia jsonb, intentos integer, ultimo_error text, constancia_version integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'salida', 'public', 'acta', 'campo', 'pg_temp'
    AS $$
#variable_conflict use_column
declare v_ids uuid[]; r record;
begin
  if p_limite is null or p_limite < 1 or p_limite > 20 then raise exception 'p_limite entre 1 y 20' using errcode = '22023'; end if;
  if p_arriendo_segundos is null or p_arriendo_segundos < 30 or p_arriendo_segundos > 3600 then raise exception 'p_arriendo_segundos entre 30 y 3600' using errcode = '22023'; end if;
  -- (1) arriendos vencidos que ya agotaron sus intentos → error
  for r in select e.id from salida.envios e where e.estado = 'tomado' and e.tomado_hasta < clock_timestamp() and e.intentos >= e.max_intentos for update skip locked loop
    update salida.envios set estado = 'error', ultimo_error = 'Arriendo vencido sin respuesta del Dell', tomado_hasta = null, ultimo_cambio_en = clock_timestamp() where id = r.id;
    insert into salida.envio_eventos (envio_id, estado_desde, estado_hasta, actor, detalle) values (r.id, 'tomado', 'error', 'sistema', '{"motivo":"arriendo_vencido"}');
  end loop;
  -- (2) pendientes cuyo registro ya no está vigente (oculto) → anulado
  for r in select e.id, e.estado from salida.envios e where e.estado in ('pendiente', 'tomado') and not salida.f_registro_vigente(e.esquema_origen, e.registro_id)
            and (e.estado = 'pendiente' or e.tomado_hasta < clock_timestamp()) for update skip locked loop
    update salida.envios set estado = 'anulado', tomado_hasta = null, lease_id = null, ultimo_cambio_en = clock_timestamp() where id = r.id;
    insert into salida.envio_eventos (envio_id, estado_desde, estado_hasta, actor, detalle) values (r.id, r.estado, 'anulado', 'sistema', '{"motivo":"registro_no_vigente"}');
  end loop;
  -- (3) tomar con bloqueo
  select array_agg(x.id) into v_ids from (
    select e.id from salida.envios e
     where (e.estado = 'pendiente' or (e.estado = 'tomado' and e.tomado_hasta < clock_timestamp())) and e.intentos < e.max_intentos
     order by e.creado_en limit p_limite for update skip locked) x;
  if v_ids is null then return; end if;
  for r in select e.id, e.estado from salida.envios e where e.id = any (v_ids) loop
    update salida.envios set estado = 'tomado', intentos = intentos + 1, lease_id = gen_random_uuid(), tomado_hasta = clock_timestamp() + make_interval(secs => p_arriendo_segundos), ultimo_cambio_en = clock_timestamp() where id = r.id;
    insert into salida.envio_eventos (envio_id, estado_desde, estado_hasta, actor, detalle) values (r.id, r.estado, 'tomado', 'dell', '{}');
  end loop;
  return query select e.id, e.lease_id, e.creado_en, e.documento, e.consecutivo, e.esquema_origen, e.registro_id, e.destinatario_correo, e.destinatario_celular, null::text, e.parte, e.copias_internas,
                      e.texto_version, e.constancia, e.intentos, e.ultimo_error, e.constancia_version from salida.envios e where e.id = any (v_ids) order by e.creado_en;
end $$;


--
-- Name: f_ahora_bogota(); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_ahora_bogota() RETURNS timestamp without time zone
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select clock_timestamp() at time zone 'America/Bogota';
$$;


--
-- Name: f_auditar(text, text, text, jsonb, text); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
  insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip) values (lower(p_email), p_accion, p_ref, p_detalle, p_ip);
$$;


--
-- Name: f_autorizar_captura(text, text); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_autorizar_captura(p_solicitante text, p_formulario text) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v_email text; v_perfil text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'registro_tecnico');       -- 28000 / 42501 si no hay sesión, acceso o permiso
  v_perfil := tecnica.f_perfil(v_email);
  if v_perfil = 'admin' then return v_email; end if;
  if not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  if v_perfil = 'supervisor' then return v_email; end if;
  if not tecnica.f_formulario_asignado(v_email, p_formulario) then
    raise exception 'No tiene asignado este formulario' using errcode = '42501';
  end if;
  return v_email;
end $$;


--
-- Name: f_autorizar_supervision(text); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_autorizar_supervision(p_solicitante text) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v_email text;
begin
  v_email := tecnica.f_verificar(p_solicitante, 'dashboard_tecnico');
  if tecnica.f_perfil(v_email) <> 'admin' and not tecnica.f_tecnica_activa(v_email) then
    raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501';
  end if;
  return v_email;
end $$;


--
-- Name: f_catalogo_protegido(); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_catalogo_protegido() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
begin
  if tg_table_name = 'variables' then
    if (new.codigo is distinct from old.codigo or new.unidad is distinct from old.unidad or new.categoria is distinct from old.categoria)
       and exists (select 1 from tecnica.registros r where r.variable_id = old.id) then
      raise exception 'La variable ya tiene registros: no se puede cambiar su código, unidad ni categoría. Cree una variable nueva y desactive esta' using errcode = '55000';
    end if;
  elsif tg_table_name = 'formulario_variables' then
    if (new.formulario is distinct from old.formulario or new.variable_id is distinct from old.variable_id or new.alcance is distinct from old.alcance)
       and exists (select 1 from tecnica.registros r where r.formulario = old.formulario and r.variable_id = old.variable_id) then
      raise exception 'La variable ya tiene registros en este formulario: no se puede cambiar su alcance. Cree una fila nueva y desactive esta' using errcode = '55000';
    end if;
  end if;
  return new;
end $$;


--
-- Name: f_error(text, text); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_error(p_mensaje text, p_codigo text DEFAULT '22023'::text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  raise exception '%', p_mensaje using errcode = p_codigo, hint = 'msg_usuario';
end $$;


--
-- Name: f_fecha_muestra(time without time zone, timestamp without time zone); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_fecha_muestra(p_hora time without time zone, p_ahora timestamp without time zone DEFAULT NULL::timestamp without time zone) RETURNS date
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog', 'tecnica'
    AS $$
declare
  v_ventana_min constant int := 60;
  v_ahora timestamp := coalesce(p_ahora, tecnica.f_ahora_bogota());
  v_hoy date := v_ahora::date;
begin
  if (v_hoy + p_hora) > (v_ahora + interval '5 minutes') then        -- se compara fecha+hora: sumar 5 minutos a un «time» daría la vuelta a las 00:00
    if v_ventana_min > 0 and v_ahora::time < make_interval(mins => v_ventana_min)::time and p_hora >= time '23:00' then
      return v_hoy - 1;
    end if;
    perform tecnica.f_error('La hora de la muestra es posterior a la hora actual. Revise la hora.');
  end if;
  return v_hoy;
end $$;


--
-- Name: f_formulario_asignado(text, text); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_formulario_asignado(p_email text, p_formulario text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
  select coalesce((select e.tipo_evento = 'asignar_formulario' from tecnica.personal_tecnico_eventos e
                    where e.persona = lower(p_email) and e.formulario = p_formulario
                      and e.tipo_evento in ('asignar_formulario', 'quitar_formulario')
                    order by e.id desc limit 1), false);
$$;


--
-- Name: f_formularios(); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_formularios() RETURNS TABLE(clave text, nombre text, descripcion text, orden integer)
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  values ('entrada',          'Entrada',                           'Agua cruda que ingresa a las plantas.', 1),
         ('salida',           'Salida',                            'Agua tratada que sale de las plantas.', 2),
         ('muestreo',         'Muestreo',                          'Muestreo en los puntos de la red y los tanques.', 3),
         ('danos_fallas',     'Daños o fallas',                    'Daños o fallas en la planta.', 4),
         ('mantenimiento',    'Mantenimiento, reparación e inversión', 'Mantenimiento, reparación e inversión.', 5),
         ('uso_quimicos',     'Uso de químicos',                   'Químicos usados en el proceso.', 6),
         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7),
         ('anomalia_compartida', 'Reportar anomalía',               'El mismo reporte de anomalías de Comercial, hecho desde Técnica.', 8),
         ('revision_compartida', 'Revisiones generales',            'La misma revisión general de Comercial, hecha desde Técnica.', 9);
$$;


--
-- Name: f_generar_vista_ancha(text); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_generar_vista_ancha(p_formulario text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $_$
declare v_cols text := ''; v_vista text; r record;
begin
  if p_formulario not in (select clave from tecnica.f_formularios()) then raise exception 'Formulario desconocido' using errcode = '22023'; end if;
  v_vista := 'v_' || p_formulario || '_ancha';
  for r in
    select v.codigo, fv.alcance, pl.codigo as planta
    from tecnica.formulario_variables fv
    join tecnica.variables v on v.id = fv.variable_id
    left join tecnica.plantas pl on fv.alcance = 'por_planta' and pl.activa
    where fv.formulario = p_formulario and fv.activa and v.activa
    order by fv.orden, v.codigo, pl.codigo
  loop
    v_cols := v_cols || format(', max(d.valor) filter (where d.variable = %L and d.planta %s) as %I',
                r.codigo, case when r.alcance = 'por_planta' then format('= %L', r.planta) else 'is null' end,
                r.codigo || coalesce('_' || r.planta, ''));
  end loop;
  execute format('drop view if exists tecnica.%I', v_vista);
  execute format($f$create view tecnica.%I as
    select d.lote_id, min(d.fecha_muestra) as fecha_muestra, min(d.hora_muestra) as hora_muestra,
           min(d.registrado_en) as registrado_en, min(d.autor) as autor, bool_and(d.excluido) as excluido %s
    from tecnica.v_registros_detalle d where d.formulario = %L group by d.lote_id$f$, v_vista, v_cols, p_formulario);
  return v_vista;
end $_$;


--
-- Name: f_marca_rango(numeric, numeric, numeric); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_marca_rango(p_valor numeric, p_min numeric, p_max numeric) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select case when p_min is not null and p_valor < p_min then 'bajo'
              when p_max is not null and p_valor > p_max then 'alto' end;
$$;


--
-- Name: f_perfil(text); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_perfil(p_email text) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v text := lower(btrim(coalesce(p_email, '')));
begin
  if v = '' then return null; end if;
  if public.geoportal_es_admin(v) then return 'admin'; end if;
  if public.geoportal_puede(v, 'dashboard_tecnico') then return 'supervisor'; end if;
  if public.geoportal_puede(v, 'registro_tecnico') then return 'operador'; end if;
  return null;
end $$;


--
-- Name: f_registro_coherente(); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_registro_coherente() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
declare v_alcance text;
begin
  select fv.alcance into v_alcance from tecnica.formulario_variables fv
   where fv.formulario = new.formulario and fv.variable_id = new.variable_id;
  if v_alcance = 'por_planta' and new.planta_id is null then
    raise exception 'La variable es por planta: falta la planta' using errcode = '22023';
  end if;
  if v_alcance = 'ambas_plantas' and new.planta_id is not null then
    raise exception 'La variable es para las dos plantas: no lleva planta' using errcode = '22023';
  end if;
  return new;
end $$;


--
-- Name: f_solo_agregar(); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_solo_agregar() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  raise exception 'Tabla de solo agregar: % no permitido en %.%', tg_op, tg_table_schema, tg_table_name using errcode = '42501';
end $$;


--
-- Name: f_tecnica_activa(text); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_tecnica_activa(p_email text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
  select coalesce((select e.tipo_evento = 'activar_tecnica' from tecnica.personal_tecnico_eventos e
                    where e.persona = lower(p_email) and e.tipo_evento in ('activar_tecnica', 'desactivar_tecnica')
                    order by e.id desc limit 1), true);
$$;


--
-- Name: f_validar_persona(text, boolean); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_validar_persona(p_persona text, p_exigir_tecnica boolean) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v text := lower(btrim(coalesce(p_persona, ''))); v_ok boolean;
begin
  if position('@' in v) < 2 then perform tecnica.f_error('Indique el correo de la persona'); end if;
  select (lb.rol = 'admin' or lb.ver_registro_tecnico) into v_ok from public.geoportal_lista_blanca lb where lb.email = v;
  if not found then perform tecnica.f_error('La persona no está registrada en el geoportal', 'P0002'); end if;
  if p_exigir_tecnica and not v_ok then
    perform tecnica.f_error('Esta persona no tiene acceso a Técnica: el administrador debe dárselo primero', '55000');
  end if;
  return v;
end $$;


--
-- Name: f_verificar(text, text); Type: FUNCTION; Schema: tecnica; Owner: -
--

CREATE FUNCTION tecnica.f_verificar(p_solicitante text, p_modo text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'tecnica', 'pg_temp'
    AS $$
declare v_email text := lower(btrim(coalesce(p_solicitante, '')));
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if not public.geoportal_puede(v_email, p_modo) then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;
  return v_email;
end $$;


--
-- Name: <->; Type: OPERATOR; Schema: public; Owner: -
--

CREATE OPERATOR public.<-> (
    FUNCTION = public.f_knn_doble,
    LEFTARG = public.geometry,
    RIGHTARG = public.geometry
);


--
-- Name: accesos_evidencia; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.accesos_evidencia (
    id bigint NOT NULL,
    autor text NOT NULL,
    acta_id uuid NOT NULL,
    orden smallint NOT NULL,
    accedido_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT accesos_evidencia_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1)))
);


--
-- Name: accesos_evidencia_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.accesos_evidencia ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.accesos_evidencia_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: acciones_correctivas; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.acciones_correctivas (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    campos jsonb DEFAULT '[]'::jsonb NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT acciones_correctivas_campos_check CHECK ((jsonb_typeof(campos) = 'array'::text)),
    CONSTRAINT acciones_correctivas_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT acciones_correctivas_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 200)))
);


--
-- Name: acciones_correctivas_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.acciones_correctivas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.acciones_correctivas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: acta_acciones; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.acta_acciones (
    id bigint NOT NULL,
    acta_id uuid NOT NULL,
    accion_id bigint NOT NULL,
    detalle jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT acta_acciones_detalle_check CHECK ((jsonb_typeof(detalle) = 'object'::text))
);


--
-- Name: acta_acciones_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.acta_acciones ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.acta_acciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: acta_fotos; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.acta_fotos (
    id bigint NOT NULL,
    acta_id uuid NOT NULL,
    orden smallint NOT NULL,
    tipo_foto_id bigint NOT NULL,
    ruta_storage text NOT NULL,
    sha256 text NOT NULL,
    tamano_bytes integer NOT NULL,
    tipo_mime text NOT NULL,
    detalle text,
    posterior boolean DEFAULT false NOT NULL,
    heredada_de uuid,
    registrada_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT acta_fotos_detalle_check CHECK (((detalle IS NULL) OR ((length(btrim(detalle)) >= 1) AND (length(btrim(detalle)) <= 200)))),
    CONSTRAINT acta_fotos_orden_check CHECK (((orden >= 1) AND (orden <= 40))),
    CONSTRAINT acta_fotos_ruta_storage_check CHECK ((ruta_storage ~ '^actas/[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}/fotos/[0-9]{1,2}\.jpg$'::text)),
    CONSTRAINT acta_fotos_sha256_check CHECK ((sha256 ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT acta_fotos_tamano_bytes_check CHECK ((tamano_bytes > 0)),
    CONSTRAINT acta_fotos_tipo_mime_check CHECK ((tipo_mime = 'image/jpeg'::text))
);


--
-- Name: acta_fotos_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.acta_fotos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.acta_fotos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: acta_hallazgos; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.acta_hallazgos (
    acta_id uuid NOT NULL,
    tipo_hallazgo_id bigint NOT NULL,
    texto_otro text,
    CONSTRAINT acta_hallazgos_texto_otro_check CHECK (((texto_otro IS NULL) OR ((length(btrim(texto_otro)) >= 3) AND (length(btrim(texto_otro)) <= 300))))
);


--
-- Name: acta_personas; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.acta_personas (
    id bigint NOT NULL,
    acta_id uuid NOT NULL,
    rol text NOT NULL,
    nombre text NOT NULL,
    email text,
    calidad_id bigint,
    calidad_texto text,
    origen text NOT NULL,
    CONSTRAINT acta_personas_calidad_texto_check CHECK (((calidad_texto IS NULL) OR ((length(btrim(calidad_texto)) >= 2) AND (length(btrim(calidad_texto)) <= 100)))),
    CONSTRAINT acta_personas_check CHECK (((rol = 'operario'::text) = (email IS NOT NULL))),
    CONSTRAINT acta_personas_check1 CHECK (((rol = 'atendiente'::text) OR ((calidad_id IS NULL) AND (calidad_texto IS NULL)))),
    CONSTRAINT acta_personas_email_check CHECK (((email IS NULL) OR ((email = lower(email)) AND (POSITION(('@'::text) IN (email)) > 1)))),
    CONSTRAINT acta_personas_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 120))),
    CONSTRAINT acta_personas_origen_check CHECK ((origen = ANY (ARRAY['perfil'::text, 'digitado'::text]))),
    CONSTRAINT acta_personas_rol_check CHECK ((rol = ANY (ARRAY['operario'::text, 'atendiente'::text, 'testigo'::text])))
);


--
-- Name: acta_personas_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.acta_personas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.acta_personas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: acta_sellos; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.acta_sellos (
    acta_id uuid NOT NULL,
    sello_sha256 text NOT NULL,
    calculado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT acta_sellos_sello_sha256_check CHECK ((sello_sha256 ~ '^[0-9a-f]{64}$'::text))
);


--
-- Name: actas; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.actas (
    id uuid NOT NULL,
    seq bigint NOT NULL,
    consecutivo text NOT NULL,
    serie text NOT NULL,
    numero integer NOT NULL,
    version integer NOT NULL,
    acta_raiz_id uuid NOT NULL,
    version_anterior_id uuid,
    motivo_correccion text,
    numero_acta_fisica text,
    numero_fisico_norm text GENERATED ALWAYS AS (upper(regexp_replace(COALESCE(numero_acta_fisica, ''::text), '[^A-Za-z0-9]'::text, ''::text, 'g'::text))) STORED,
    fecha_acta_fisica date NOT NULL,
    papel_pendiente boolean DEFAULT false NOT NULL,
    modo_identificacion text NOT NULL,
    contrato text,
    direccion text NOT NULL,
    barrio text NOT NULL,
    barrio_id bigint,
    barrio_fuera_de_lista boolean DEFAULT false NOT NULL,
    estrato text,
    uso text,
    referencia_ubicacion text,
    lat numeric(9,6) NOT NULL,
    lon numeric(9,6) NOT NULL,
    precision_m numeric(9,1),
    fuera_de_zona boolean NOT NULL,
    geom public.geometry GENERATED ALWAYS AS (public.st_setsrid(public.st_makepoint((lon)::double precision, (lat)::double precision), 4326)) STORED,
    tiene_medidor boolean NOT NULL,
    medidor_serie text,
    marca text,
    lectura_m3 numeric(12,2),
    estado_medidor_id bigint,
    estado_sellos_id bigint,
    serie_sellos text,
    diametro_id bigint,
    sin_irregularidad boolean NOT NULL,
    descripcion_hallazgos text,
    nadie_atendio boolean NOT NULL,
    derechos_informados boolean,
    firmo_operario boolean NOT NULL,
    firmo_atendiente boolean NOT NULL,
    se_nego_a_firmar boolean NOT NULL,
    constancia_operario text,
    observaciones text,
    inicio_en timestamp with time zone NOT NULL,
    fin_en timestamp with time zone NOT NULL,
    registrado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    autor text NOT NULL,
    reporte_id uuid,
    esquema_version integer DEFAULT 1 NOT NULL,
    CONSTRAINT acta_contrato_ck CHECK (((modo_identificacion = 'con_contrato'::text) = (contrato IS NOT NULL))),
    CONSTRAINT acta_fin_ck CHECK ((fin_en >= inicio_en)),
    CONSTRAINT acta_hallazgo_ck CHECK ((sin_irregularidad OR (descripcion_hallazgos IS NOT NULL))),
    CONSTRAINT acta_medidor_ck CHECK ((tiene_medidor OR ((medidor_serie IS NULL) AND (marca IS NULL) AND (lectura_m3 IS NULL) AND (estado_medidor_id IS NULL)))),
    CONSTRAINT acta_motivo_ck CHECK (((version = 1) OR (motivo_correccion IS NOT NULL))),
    CONSTRAINT acta_nadie_ck CHECK (((NOT nadie_atendio) OR ((NOT firmo_atendiente) AND (NOT se_nego_a_firmar) AND (constancia_operario IS NOT NULL)))),
    CONSTRAINT acta_negativa_ck CHECK (((NOT se_nego_a_firmar) OR ((NOT firmo_atendiente) AND (constancia_operario IS NOT NULL)))),
    CONSTRAINT acta_version_ck CHECK (((version = 1) = (version_anterior_id IS NULL))),
    CONSTRAINT actas_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT actas_barrio_check CHECK (((length(btrim(barrio)) >= 2) AND (length(btrim(barrio)) <= 120))),
    CONSTRAINT actas_constancia_operario_check CHECK (((constancia_operario IS NULL) OR ((length(btrim(constancia_operario)) >= 10) AND (length(btrim(constancia_operario)) <= 2000)))),
    CONSTRAINT actas_contrato_check CHECK (((contrato IS NULL) OR (contrato ~ '^[A-Za-z0-9-]{1,20}$'::text))),
    CONSTRAINT actas_descripcion_hallazgos_check CHECK (((descripcion_hallazgos IS NULL) OR ((length(btrim(descripcion_hallazgos)) >= 10) AND (length(btrim(descripcion_hallazgos)) <= 4000)))),
    CONSTRAINT actas_direccion_check CHECK (((length(btrim(direccion)) >= 3) AND (length(btrim(direccion)) <= 300))),
    CONSTRAINT actas_estrato_check CHECK (((estrato IS NULL) OR ((length(btrim(estrato)) >= 1) AND (length(btrim(estrato)) <= 20)))),
    CONSTRAINT actas_lat_check CHECK (((lat >= ('-90'::integer)::numeric) AND (lat <= (90)::numeric))),
    CONSTRAINT actas_lectura_m3_check CHECK (((lectura_m3 IS NULL) OR (lectura_m3 >= (0)::numeric))),
    CONSTRAINT actas_lon_check CHECK (((lon >= ('-180'::integer)::numeric) AND (lon <= (180)::numeric))),
    CONSTRAINT actas_marca_check CHECK (((marca IS NULL) OR ((length(btrim(marca)) >= 1) AND (length(btrim(marca)) <= 60)))),
    CONSTRAINT actas_medidor_serie_check CHECK (((medidor_serie IS NULL) OR ((length(btrim(medidor_serie)) >= 1) AND (length(btrim(medidor_serie)) <= 40)))),
    CONSTRAINT actas_modo_identificacion_check CHECK ((modo_identificacion = ANY (ARRAY['con_contrato'::text, 'sin_contrato'::text]))),
    CONSTRAINT actas_motivo_correccion_check CHECK (((motivo_correccion IS NULL) OR ((length(btrim(motivo_correccion)) >= 10) AND (length(btrim(motivo_correccion)) <= 1000)))),
    CONSTRAINT actas_numero_acta_fisica_check CHECK (((numero_acta_fisica IS NULL) OR ((length(btrim(numero_acta_fisica)) >= 1) AND (length(btrim(numero_acta_fisica)) <= 30)))),
    CONSTRAINT actas_observaciones_check CHECK (((observaciones IS NULL) OR (length(btrim(observaciones)) <= 2000))),
    CONSTRAINT actas_referencia_ubicacion_check CHECK (((referencia_ubicacion IS NULL) OR (length(btrim(referencia_ubicacion)) <= 300))),
    CONSTRAINT actas_serie_sellos_check CHECK (((serie_sellos IS NULL) OR ((length(btrim(serie_sellos)) >= 1) AND (length(btrim(serie_sellos)) <= 60)))),
    CONSTRAINT actas_uso_check CHECK (((uso IS NULL) OR ((length(btrim(uso)) >= 1) AND (length(btrim(uso)) <= 80)))),
    CONSTRAINT actas_version_check CHECK ((version >= 1))
);


--
-- Name: TABLE actas; Type: COMMENT; Schema: acta; Owner: -
--

COMMENT ON TABLE acta.actas IS 'Una fila por VERSIÓN del registro digital. Inmutable: la corrección es una versión nueva enlazada. NO sustituye el acta física firmada.';


--
-- Name: COLUMN actas.numero_acta_fisica; Type: COMMENT; Schema: acta; Owner: -
--

COMMENT ON COLUMN acta.actas.numero_acta_fisica IS 'Otro número que el papel ya traiga impreso (texto libre, opcional). El número de referencia es el consecutivo del sistema, escrito en el papel.';


--
-- Name: COLUMN actas.fecha_acta_fisica; Type: COMMENT; Schema: acta; Owner: -
--

COMMENT ON COLUMN acta.actas.fecha_acta_fisica IS 'Fecha del acta física (fecha civil de la visita, America/Bogota). De aquí se cuenta la alerta de antigüedad.';


--
-- Name: actas_seq_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.actas ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.actas_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: apertura_eventos; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.apertura_eventos (
    id bigint NOT NULL,
    apertura_id uuid NOT NULL,
    tipo_evento text NOT NULL,
    motivo_codigo text NOT NULL,
    motivo_texto text,
    autor text NOT NULL,
    rol_autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT apertura_eventos_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT apertura_eventos_motivo_texto_check CHECK (((motivo_texto IS NULL) OR ((length(btrim(motivo_texto)) >= 3) AND (length(btrim(motivo_texto)) <= 1000)))),
    CONSTRAINT apertura_eventos_rol_autor_check CHECK ((rol_autor = ANY (ARRAY['autor'::text, 'supervisor'::text, 'administrador'::text]))),
    CONSTRAINT apertura_eventos_tipo_evento_check CHECK ((tipo_evento = 'cancelar'::text))
);


--
-- Name: apertura_eventos_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.apertura_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.apertura_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: aperturas; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.aperturas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    seq bigint NOT NULL,
    serie text NOT NULL,
    numero integer NOT NULL,
    consecutivo text NOT NULL,
    autor text NOT NULL,
    abierto_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    lat numeric(9,6) NOT NULL,
    lon numeric(9,6) NOT NULL,
    precision_m numeric(9,1),
    fuera_de_zona boolean NOT NULL,
    reporte_id uuid,
    acta_raiz_id uuid NOT NULL,
    correccion_de uuid,
    motivo_correccion text,
    CONSTRAINT apertura_correccion_ck CHECK (((correccion_de IS NULL) = (motivo_correccion IS NULL))),
    CONSTRAINT apertura_raiz_ck CHECK (((correccion_de IS NOT NULL) OR (acta_raiz_id = id))),
    CONSTRAINT aperturas_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT aperturas_consecutivo_check CHECK ((consecutivo ~ '^[A-Z]{2,6}-[0-9]{4}-[0-9]{6}$'::text)),
    CONSTRAINT aperturas_lat_check CHECK (((lat >= ('-90'::integer)::numeric) AND (lat <= (90)::numeric))),
    CONSTRAINT aperturas_lon_check CHECK (((lon >= ('-180'::integer)::numeric) AND (lon <= (180)::numeric))),
    CONSTRAINT aperturas_motivo_correccion_check CHECK (((motivo_correccion IS NULL) OR ((length(btrim(motivo_correccion)) >= 10) AND (length(btrim(motivo_correccion)) <= 1000)))),
    CONSTRAINT aperturas_numero_check CHECK ((numero > 0)),
    CONSTRAINT aperturas_precision_m_check CHECK (((precision_m IS NULL) OR (precision_m >= (0)::numeric)))
);


--
-- Name: TABLE aperturas; Type: COMMENT; Schema: acta; Owner: -
--

COMMENT ON TABLE acta.aperturas IS 'Apertura del registro: reserva acta_id y consecutivo (que el operario escribe en el papel). Solo inserción.';


--
-- Name: aperturas_seq_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.aperturas ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.aperturas_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: calidades_atendiente; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.calidades_atendiente (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    exige_texto boolean DEFAULT false NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT calidades_atendiente_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT calidades_atendiente_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))
);


--
-- Name: calidades_atendiente_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.calidades_atendiente ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.calidades_atendiente_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: caso_eventos; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.caso_eventos (
    id bigint NOT NULL,
    acta_raiz_id uuid NOT NULL,
    tipo_evento text NOT NULL,
    estado_nuevo text,
    motivo text,
    custodia_codigo text,
    contrato text,
    reporte_id uuid,
    acta_id uuid,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT caso_eventos_autor_check CHECK (((autor = 'sistema'::text) OR ((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1)))),
    CONSTRAINT caso_eventos_contrato_check CHECK (((contrato IS NULL) OR (contrato ~ '^[A-Za-z0-9-]{1,20}$'::text))),
    CONSTRAINT caso_eventos_motivo_check CHECK (((motivo IS NULL) OR ((length(btrim(motivo)) >= 10) AND (length(btrim(motivo)) <= 1000)))),
    CONSTRAINT caso_eventos_tipo_evento_check CHECK ((tipo_evento = ANY (ARRAY['cambio_estado'::text, 'ocultar'::text, 'reincluir'::text, 'nota'::text, 'custodia_medidor'::text, 'vincular_contrato'::text, 'vincular_reporte'::text, 'nueva_version'::text, 'foto_acta_fisica_posterior'::text]))),
    CONSTRAINT evento_acta_ck CHECK (((tipo_evento = ANY (ARRAY['nueva_version'::text, 'foto_acta_fisica_posterior'::text])) = (acta_id IS NOT NULL))),
    CONSTRAINT evento_contrato_ck CHECK (((tipo_evento = 'vincular_contrato'::text) = (contrato IS NOT NULL))),
    CONSTRAINT evento_custodia_ck CHECK (((tipo_evento = 'custodia_medidor'::text) = (custodia_codigo IS NOT NULL))),
    CONSTRAINT evento_estado_ck CHECK (((tipo_evento = 'cambio_estado'::text) = (estado_nuevo IS NOT NULL))),
    CONSTRAINT evento_motivo_ck CHECK (((tipo_evento = ANY (ARRAY['cambio_estado'::text, 'vincular_reporte'::text, 'foto_acta_fisica_posterior'::text])) OR (motivo IS NOT NULL))),
    CONSTRAINT evento_reporte_ck CHECK (((tipo_evento = 'vincular_reporte'::text) = (reporte_id IS NOT NULL)))
);


--
-- Name: TABLE caso_eventos; Type: COMMENT; Schema: acta; Owner: -
--

COMMENT ON TABLE acta.caso_eventos IS 'Eventos posteriores al registro; estado, ocultamiento y custodia se derivan de aquí.';


--
-- Name: caso_eventos_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.caso_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.caso_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: consecutivos; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.consecutivos (
    serie text NOT NULL,
    prefijo text NOT NULL,
    ultimo_numero integer DEFAULT 0 NOT NULL,
    actualizado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT consecutivos_prefijo_check CHECK ((prefijo ~ '^[A-Z]{2,6}$'::text)),
    CONSTRAINT consecutivos_serie_check CHECK ((serie ~ '^[0-9]{4}$'::text)),
    CONSTRAINT consecutivos_ultimo_numero_check CHECK ((ultimo_numero >= 0))
);


--
-- Name: consultas_contrato; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.consultas_contrato (
    id bigint NOT NULL,
    autor text NOT NULL,
    contrato text NOT NULL,
    existe boolean NOT NULL,
    consultado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT consultas_contrato_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1)))
);


--
-- Name: consultas_contrato_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.consultas_contrato ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.consultas_contrato_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: diametros_acometida; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.diametros_acometida (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT diametros_acometida_codigo_check CHECK ((codigo ~ '^[a-z0-9][a-z0-9_]{0,59}$'::text)),
    CONSTRAINT diametros_acometida_nombre_check CHECK (((length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 100)))
);


--
-- Name: diametros_acometida_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.diametros_acometida ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.diametros_acometida_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: estados_caso; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.estados_caso (
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    inicial boolean DEFAULT false NOT NULL,
    inicial_sin_irregularidad boolean DEFAULT false NOT NULL,
    exige_motivo boolean DEFAULT false NOT NULL,
    cambio_manual boolean DEFAULT true NOT NULL,
    terminal boolean DEFAULT false NOT NULL,
    gestiona text DEFAULT 'supervisor'::text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT estados_caso_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT estados_caso_gestiona_check CHECK ((gestiona = ANY (ARRAY['supervisor'::text, 'juridica'::text, 'sistema'::text]))),
    CONSTRAINT estados_caso_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))
);


--
-- Name: estados_custodia; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.estados_custodia (
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT estados_custodia_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT estados_custodia_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))
);


--
-- Name: estados_medidor; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.estados_medidor (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT estados_medidor_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT estados_medidor_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))
);


--
-- Name: estados_medidor_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.estados_medidor ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.estados_medidor_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: estados_sellos; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.estados_sellos (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT estados_sellos_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT estados_sellos_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))
);


--
-- Name: estados_sellos_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.estados_sellos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.estados_sellos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: motivos_cancelacion; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.motivos_cancelacion (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    exige_texto boolean DEFAULT false NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT motivos_cancelacion_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT motivos_cancelacion_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))
);


--
-- Name: motivos_cancelacion_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.motivos_cancelacion ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.motivos_cancelacion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: parametros; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.parametros (
    clave text NOT NULL,
    valor numeric,
    unidad text NOT NULL,
    descripcion text NOT NULL,
    minimo numeric,
    maximo numeric,
    actualizado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    actualizado_por text,
    CONSTRAINT parametros_clave_check CHECK ((clave ~ '^[a-z][a-z0-9_]{2,59}$'::text)),
    CONSTRAINT parametros_rango_ck CHECK (((valor IS NULL) OR (((minimo IS NULL) OR (valor >= minimo)) AND ((maximo IS NULL) OR (valor <= maximo)))))
);


--
-- Name: tipos_foto; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.tipos_foto (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    exigida_con_irregularidad boolean DEFAULT false NOT NULL,
    es_acta_fisica boolean DEFAULT false NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT tipos_foto_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT tipos_foto_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))
);


--
-- Name: tipos_foto_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.tipos_foto ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.tipos_foto_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipos_hallazgo; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.tipos_hallazgo (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    nota text,
    orden integer DEFAULT 100 NOT NULL,
    exige_texto boolean DEFAULT false NOT NULL,
    excluyente boolean DEFAULT false NOT NULL,
    habilita_accion_codigo text,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT tipos_hallazgo_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT tipos_hallazgo_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 200)))
);


--
-- Name: tipos_hallazgo_id_seq; Type: SEQUENCE; Schema: acta; Owner: -
--

ALTER TABLE acta.tipos_hallazgo ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME acta.tipos_hallazgo_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: transiciones_caso; Type: TABLE; Schema: acta; Owner: -
--

CREATE TABLE acta.transiciones_caso (
    desde text NOT NULL,
    hasta text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT transiciones_caso_check CHECK ((desde <> hasta))
);


--
-- Name: v_actas_vigentes; Type: VIEW; Schema: acta; Owner: -
--

CREATE VIEW acta.v_actas_vigentes AS
 SELECT id,
    seq,
    consecutivo,
    serie,
    numero,
    version,
    acta_raiz_id,
    version_anterior_id,
    motivo_correccion,
    numero_acta_fisica,
    numero_fisico_norm,
    fecha_acta_fisica,
    papel_pendiente,
    modo_identificacion,
    contrato,
    direccion,
    barrio,
    barrio_id,
    barrio_fuera_de_lista,
    estrato,
    uso,
    referencia_ubicacion,
    lat,
    lon,
    precision_m,
    fuera_de_zona,
    geom,
    tiene_medidor,
    medidor_serie,
    marca,
    lectura_m3,
    estado_medidor_id,
    estado_sellos_id,
    serie_sellos,
    diametro_id,
    sin_irregularidad,
    descripcion_hallazgos,
    nadie_atendio,
    derechos_informados,
    firmo_operario,
    firmo_atendiente,
    se_nego_a_firmar,
    constancia_operario,
    observaciones,
    inicio_en,
    fin_en,
    registrado_en,
    autor,
    reporte_id,
    esquema_version
   FROM acta.actas a
  WHERE (version = ( SELECT max(x.version) AS max
           FROM acta.actas x
          WHERE (x.acta_raiz_id = a.acta_raiz_id)));


--
-- Name: v_casos; Type: VIEW; Schema: acta; Owner: -
--

CREATE VIEW acta.v_casos AS
 WITH v AS (
         SELECT a.id,
            a.seq,
            a.consecutivo,
            a.serie,
            a.numero,
            a.version,
            a.acta_raiz_id,
            a.version_anterior_id,
            a.motivo_correccion,
            a.numero_acta_fisica,
            a.numero_fisico_norm,
            a.fecha_acta_fisica,
            a.papel_pendiente,
            a.modo_identificacion,
            a.contrato,
            a.direccion,
            a.barrio,
            a.barrio_id,
            a.barrio_fuera_de_lista,
            a.estrato,
            a.uso,
            a.referencia_ubicacion,
            a.lat,
            a.lon,
            a.precision_m,
            a.fuera_de_zona,
            a.geom,
            a.tiene_medidor,
            a.medidor_serie,
            a.marca,
            a.lectura_m3,
            a.estado_medidor_id,
            a.estado_sellos_id,
            a.serie_sellos,
            a.diametro_id,
            a.sin_irregularidad,
            a.descripcion_hallazgos,
            a.nadie_atendio,
            a.derechos_informados,
            a.firmo_operario,
            a.firmo_atendiente,
            a.se_nego_a_firmar,
            a.constancia_operario,
            a.observaciones,
            a.inicio_en,
            a.fin_en,
            a.registrado_en,
            a.autor,
            a.reporte_id,
            a.esquema_version,
            ( SELECT e.estado_nuevo
                   FROM acta.caso_eventos e
                  WHERE ((e.acta_raiz_id = a.acta_raiz_id) AND (e.estado_nuevo IS NOT NULL))
                  ORDER BY e.id DESC
                 LIMIT 1) AS estado,
            ( SELECT e.creado_en
                   FROM acta.caso_eventos e
                  WHERE ((e.acta_raiz_id = a.acta_raiz_id) AND (e.estado_nuevo IS NOT NULL))
                  ORDER BY e.id DESC
                 LIMIT 1) AS estado_desde,
            COALESCE(( SELECT (e.tipo_evento = 'ocultar'::text)
                   FROM acta.caso_eventos e
                  WHERE ((e.acta_raiz_id = a.acta_raiz_id) AND (e.tipo_evento = ANY (ARRAY['ocultar'::text, 'reincluir'::text])))
                  ORDER BY e.id DESC
                 LIMIT 1), false) AS oculto,
            ( SELECT e.custodia_codigo
                   FROM acta.caso_eventos e
                  WHERE ((e.acta_raiz_id = a.acta_raiz_id) AND (e.tipo_evento = 'custodia_medidor'::text))
                  ORDER BY e.id DESC
                 LIMIT 1) AS custodia,
            ( SELECT e.contrato
                   FROM acta.caso_eventos e
                  WHERE ((e.acta_raiz_id = a.acta_raiz_id) AND (e.tipo_evento = 'vincular_contrato'::text))
                  ORDER BY e.id DESC
                 LIMIT 1) AS contrato_vinculado,
            ( SELECT e.reporte_id
                   FROM acta.caso_eventos e
                  WHERE ((e.acta_raiz_id = a.acta_raiz_id) AND (e.tipo_evento = 'vincular_reporte'::text))
                  ORDER BY e.id DESC
                 LIMIT 1) AS reporte_vinculado,
            (EXISTS ( SELECT 1
                   FROM ((acta.acta_fotos f
                     JOIN acta.tipos_foto tf ON ((tf.id = f.tipo_foto_id)))
                     JOIN acta.actas x ON ((x.id = f.acta_id)))
                  WHERE ((x.acta_raiz_id = a.acta_raiz_id) AND tf.es_acta_fisica))) AS tiene_foto_acta_fisica
           FROM acta.v_actas_vigentes a
        )
 SELECT v.id AS acta_id,
    v.seq,
    ( SELECT r.seq
           FROM acta.actas r
          WHERE (r.id = v.acta_raiz_id)) AS caso_seq,
    v.acta_raiz_id,
    v.consecutivo,
    v.version,
    v.numero_acta_fisica,
    v.fecha_acta_fisica,
    v.papel_pendiente,
    v.modo_identificacion,
    v.contrato,
    v.contrato_vinculado,
    v.direccion,
    v.barrio,
    v.barrio_fuera_de_lista,
    v.estrato,
    v.uso,
    v.lat,
    v.lon,
    v.fuera_de_zona,
    v.geom,
    v.sin_irregularidad,
    v.nadie_atendio,
    v.se_nego_a_firmar,
    v.firmo_operario,
    v.firmo_atendiente,
    v.autor,
    v.registrado_en,
    v.estado,
    v.estado_desde,
    v.oculto,
    v.custodia,
    v.reporte_vinculado,
    v.tiene_foto_acta_fisica,
    (v.papel_pendiente AND (NOT v.tiene_foto_acta_fisica)) AS registro_sin_foto_acta_fisica,
    COALESCE(ec.terminal, false) AS caso_cerrado,
    (acta.f_hoy_bogota() - v.fecha_acta_fisica) AS dias_transcurridos,
    ((v.fecha_acta_fisica + make_interval(months => (acta.f_param('alerta_meses'::text))::integer)))::date AS fecha_limite,
        CASE
            WHEN (acta.f_hoy_bogota() > ((v.fecha_acta_fisica + make_interval(months => (acta.f_param('alerta_meses'::text))::integer)))::date) THEN 'vencida'::text
            WHEN ((((v.fecha_acta_fisica + make_interval(months => (acta.f_param('alerta_meses'::text))::integer)))::date - acta.f_hoy_bogota()) < (acta.f_param('alerta_previa_dias'::text))::integer) THEN 'proxima'::text
            ELSE 'normal'::text
        END AS nivel_alerta
   FROM (v
     LEFT JOIN acta.estados_caso ec ON ((ec.codigo = v.estado)));


--
-- Name: v_conciliacion; Type: VIEW; Schema: acta; Owner: -
--

CREATE VIEW acta.v_conciliacion AS
 SELECT ap.consecutivo,
    ap.numero,
    ap.serie,
    ap.autor,
    ap.abierto_en,
        CASE
            WHEN (a.id IS NOT NULL) THEN 'registrada'::text
            WHEN (c.id IS NOT NULL) THEN 'cancelada'::text
            WHEN (ap.abierto_en < (clock_timestamp() - make_interval(hours => (acta.f_param('vigencia_apertura_horas'::text))::integer))) THEN 'abierta_vencida_sin_registrar'::text
            ELSE 'abierta_en_curso'::text
        END AS situacion,
    a.id AS acta_id,
    a.numero_acta_fisica,
    a.fecha_acta_fisica,
    (a.papel_pendiente AND (NOT (EXISTS ( SELECT 1
           FROM ((acta.acta_fotos f
             JOIN acta.tipos_foto tf ON ((tf.id = f.tipo_foto_id)))
             JOIN acta.actas x ON ((x.id = f.acta_id)))
          WHERE ((x.acta_raiz_id = a.acta_raiz_id) AND tf.es_acta_fisica))))) AS sin_foto_acta_fisica,
    ap.id AS apertura_id,
    c.creado_en AS cancelada_en,
    c.autor AS cancelada_por,
    c.motivo_codigo AS motivo_cancelacion,
    c.motivo_texto
   FROM ((acta.aperturas ap
     LEFT JOIN acta.actas a ON ((a.id = ap.id)))
     LEFT JOIN acta.apertura_eventos c ON (((c.apertura_id = ap.id) AND (c.tipo_evento = 'cancelar'::text))))
  WHERE (ap.correccion_de IS NULL);


--
-- Name: v_cambio_medidor_dim; Type: TABLE; Schema: bi; Owner: -
--

CREATE TABLE bi.v_cambio_medidor_dim (
    periodo text NOT NULL,
    periodo_ant text,
    meses_intervalo integer,
    ciclo text NOT NULL,
    uso text NOT NULL,
    estrato text NOT NULL,
    tipo_evento text NOT NULL,
    banda_ant text NOT NULL,
    metodo_act text NOT NULL,
    contratos bigint,
    contratos_pareados bigint,
    m3_ant numeric,
    m3_act numeric,
    contratos_con_medidor_ant bigint
);


--
-- Name: v_consumo_promedio_dim; Type: TABLE; Schema: bi; Owner: -
--

CREATE TABLE bi.v_consumo_promedio_dim (
    periodo text NOT NULL,
    dimension text NOT NULL,
    grupo text NOT NULL,
    contratos integer NOT NULL,
    media_m3 numeric NOT NULL,
    mediana_m3 numeric NOT NULL,
    calculado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT v_consumo_promedio_dim_contratos_check CHECK ((contratos >= 30)),
    CONSTRAINT v_consumo_promedio_dim_dimension_check CHECK ((dimension = ANY (ARRAY['estrato'::text, 'barrio'::text, 'uso'::text]))),
    CONSTRAINT v_consumo_promedio_dim_periodo_check CHECK ((periodo ~ '^\d{6}$'::text))
);


--
-- Name: TABLE v_consumo_promedio_dim; Type: COMMENT; Schema: bi; Owner: -
--

COMMENT ON TABLE bi.v_consumo_promedio_dim IS 'Promedio de consumo (m³) por estrato (subcategoría), barrio (de cartera_suscripcion) y uso, con lectura real (observación 99 y CALCCODL), con medidor y 0 < consumo_cargos <= 100. Solo grupos de 30 o más contratos.';


--
-- Name: v_submedicion_ciclo_dim; Type: TABLE; Schema: bi; Owner: -
--

CREATE TABLE bi.v_submedicion_ciclo_dim (
    periodo text NOT NULL,
    ciclo text NOT NULL,
    estrato text NOT NULL,
    contratos bigint,
    m3_consumo numeric,
    m3_perdidos_bruta numeric,
    contratos_vejez bigint,
    m3_perdidos_atrib numeric,
    tarifa_m3 numeric,
    contratos_bajo_ref bigint,
    m3_exceso numeric,
    max_m3 numeric,
    calculado_en timestamp with time zone
);


--
-- Name: v_submedicion_rango_dim; Type: TABLE; Schema: bi; Owner: -
--

CREATE TABLE bi.v_submedicion_rango_dim (
    periodo text NOT NULL,
    ciclo text NOT NULL,
    estrato text NOT NULL,
    rango_m3 text NOT NULL,
    contratos bigint,
    m3_consumo numeric,
    contratos_bajo_ref bigint,
    m3_perdidos_bruta numeric,
    tarifa_m3 numeric,
    max_m3 numeric,
    calculado_en timestamp with time zone
);


--
-- Name: v_submedicion_ref_dim; Type: TABLE; Schema: bi; Owner: -
--

CREATE TABLE bi.v_submedicion_ref_dim (
    periodo text NOT NULL,
    estrato text NOT NULL,
    banda_antig text NOT NULL,
    contratos_medidor bigint,
    contratos bigint,
    contratos_promedio bigint,
    m3_consumo numeric,
    ref_nuevos_media_m3 numeric,
    n_nuevos bigint,
    media_vejez_m3 numeric,
    n_vejez bigint,
    tarifa_m3 numeric,
    contratos_bajo_ref bigint,
    m3_perdidos_bruta numeric,
    m3_exceso numeric,
    max_m3 numeric,
    calculado_en timestamp with time zone,
    contratos_cero bigint,
    contratos_sobre_max bigint
);


--
-- Name: ficha_contrato; Type: TABLE; Schema: bi_interno; Owner: -
--

CREATE TABLE bi_interno.ficha_contrato (
    contrato text NOT NULL,
    periodo_ultimo text NOT NULL,
    periodo text GENERATED ALWAYS AS (periodo_ultimo) STORED,
    uso text,
    estrato text,
    ciclo text,
    consumo_meses jsonb NOT NULL,
    cons_max numeric,
    cons_min numeric,
    cons_prom numeric,
    meses_con_lectura integer DEFAULT 0 NOT NULL,
    medidor_serial text,
    medidor_fecha date,
    medidor_fecha_estado text NOT NULL,
    medidor_anios integer,
    cambio jsonb,
    submedicion jsonb,
    emd jsonb DEFAULT '[]'::jsonb NOT NULL,
    ultimo_pago jsonb,
    pqr jsonb,
    facturas_vencidas integer,
    calculado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT ficha_contrato_consumo_meses_check CHECK (((jsonb_typeof(consumo_meses) = 'array'::text) AND (jsonb_array_length(consumo_meses) = 6))),
    CONSTRAINT ficha_contrato_medidor_fecha_estado_check CHECK ((medidor_fecha_estado = ANY (ARRAY['real'::text, 'por_defecto'::text, 'sin_dato'::text]))),
    CONSTRAINT ficha_contrato_periodo_ultimo_check CHECK ((periodo_ultimo ~ '^\d{6}$'::text))
);


--
-- Name: TABLE ficha_contrato; Type: COMMENT; Schema: bi_interno; Owner: -
--

COMMENT ON TABLE bi_interno.ficha_contrato IS 'Análisis de contrato: una fila por contrato con 6 meses de consumo, medidor, cambio detectado, submedición, EMD facturados, último pago y PQR. SIN datos personales. La recalcula bi.recalcular(''bi_interno.ficha_contrato'', periodo). La reutilizan el simulador y el SCRR.';


--
-- Name: ficha_contrato_estado; Type: TABLE; Schema: bi_interno; Owner: -
--

CREATE TABLE bi_interno.ficha_contrato_estado (
    id integer NOT NULL,
    firma text NOT NULL,
    filas integer NOT NULL,
    calculado_en timestamp with time zone NOT NULL,
    duracion_ms integer NOT NULL,
    CONSTRAINT ficha_contrato_estado_id_check CHECK ((id = 1))
);


--
-- Name: actividades; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.actividades (
    codigo text NOT NULL,
    nombre text NOT NULL,
    activa boolean DEFAULT true NOT NULL,
    orden integer NOT NULL,
    formularios text[] DEFAULT '{}'::text[] NOT NULL,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT actividades_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT actividades_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,39}$'::text)),
    CONSTRAINT actividades_formularios_check CHECK (((cardinality(formularios) <= 10) AND (array_to_string(formularios, ','::text) !~ '[^a-z0-9_:,]'::text))),
    CONSTRAINT actividades_nombre_check CHECK ((((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 60)) AND (nombre = btrim(nombre)))),
    CONSTRAINT actividades_orden_check CHECK (((orden >= 0) AND (orden <= 100000)))
);


--
-- Name: TABLE actividades; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON TABLE campo.actividades IS 'Comercial 21-nov (D3, D4): actividades que hace el personal de Comercial (SCRR, lectura, reparto, revisiones, instalaciones…). Las asigna el supervisor a una cuadrilla o a una persona; hoy SOLO se registran (no restringen la captura). «formularios» = claves de campo.f_formularios_personal() que corresponden a la actividad (informativo). No se borran.';


--
-- Name: areas_comercial; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.areas_comercial (
    codigo text NOT NULL,
    nombre text NOT NULL,
    activa boolean DEFAULT true NOT NULL,
    orden integer NOT NULL,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT areas_comercial_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT areas_comercial_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,39}$'::text)),
    CONSTRAINT areas_comercial_nombre_check CHECK ((((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 60)) AND (nombre = btrim(nombre)))),
    CONSTRAINT areas_comercial_orden_check CHECK (((orden >= 0) AND (orden <= 100000)))
);


--
-- Name: TABLE areas_comercial; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON TABLE campo.areas_comercial IS 'Comercial 21-nov (D2): áreas de Comercial para la ficha de Personal. Las edita el administrador; no se borran (se desactivan con motivo, ver campo.catalogo_eventos).';


--
-- Name: catalogo_eventos; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.catalogo_eventos (
    id bigint NOT NULL,
    catalogo text NOT NULL,
    codigo text NOT NULL,
    tipo_evento text NOT NULL,
    nombre text,
    motivo text,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT catalogo_eventos_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT catalogo_eventos_catalogo_check CHECK ((catalogo = ANY (ARRAY['area'::text, 'actividad'::text]))),
    CONSTRAINT catalogo_eventos_ck CHECK ((((tipo_evento = ANY (ARRAY['crear'::text, 'renombrar'::text])) = (nombre IS NOT NULL)) AND ((tipo_evento <> 'desactivar'::text) OR (motivo IS NOT NULL)))),
    CONSTRAINT catalogo_eventos_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,39}$'::text)),
    CONSTRAINT catalogo_eventos_motivo_check CHECK (((motivo IS NULL) OR ((length(btrim(motivo)) >= 10) AND (length(btrim(motivo)) <= 300)))),
    CONSTRAINT catalogo_eventos_nombre_check CHECK (((nombre IS NULL) OR ((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 60)))),
    CONSTRAINT catalogo_eventos_tipo_evento_check CHECK ((tipo_evento = ANY (ARRAY['crear'::text, 'renombrar'::text, 'desactivar'::text, 'activar'::text])))
);


--
-- Name: TABLE catalogo_eventos; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON TABLE campo.catalogo_eventos IS 'Comercial 21-nov: historial de los catálogos de áreas y de actividades. Solo agregar.';


--
-- Name: catalogo_eventos_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.catalogo_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.catalogo_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: causales; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.causales (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    general boolean DEFAULT false NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT causales_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,39}$'::text)),
    CONSTRAINT causales_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)))
);


--
-- Name: causales_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.causales ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.causales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: causales_tipos; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.causales_tipos (
    causal_id bigint NOT NULL,
    tipo_id bigint NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: consecutivos; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.consecutivos (
    tipo_id bigint NOT NULL,
    ultimo bigint NOT NULL,
    actualizado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT consecutivos_ultimo_check CHECK ((ultimo >= 1))
);


--
-- Name: consultas_analisis; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.consultas_analisis (
    id bigint NOT NULL,
    autor text NOT NULL,
    contrato text NOT NULL,
    existe boolean NOT NULL,
    consultado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    ip text,
    CONSTRAINT consultas_analisis_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT consultas_analisis_contrato_check CHECK ((contrato ~ '^\d{1,12}$'::text)),
    CONSTRAINT consultas_analisis_ip_check CHECK (((ip IS NULL) OR (length(ip) <= 64)))
);


--
-- Name: TABLE consultas_analisis; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON TABLE campo.consultas_analisis IS 'Análisis de contrato: bitácora de consultas (autor, contrato, si existía, hora). Sin límite diario. Solo se agrega; retención 12 meses.';


--
-- Name: consultas_analisis_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.consultas_analisis ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.consultas_analisis_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: consultas_cercania; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.consultas_cercania (
    id bigint NOT NULL,
    autor text NOT NULL,
    lat_red numeric(6,3) NOT NULL,
    lon_red numeric(7,3) NOT NULL,
    resultados integer NOT NULL,
    cobrada boolean NOT NULL,
    consultado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    ip text,
    CONSTRAINT consultas_cercania_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT consultas_cercania_ip_check CHECK (((ip IS NULL) OR (length(ip) <= 64))),
    CONSTRAINT consultas_cercania_lat_red_check CHECK (((lat_red >= ('-90'::integer)::numeric) AND (lat_red <= (90)::numeric))),
    CONSTRAINT consultas_cercania_lon_red_check CHECK (((lon_red >= ('-180'::integer)::numeric) AND (lon_red <= (180)::numeric))),
    CONSTRAINT consultas_cercania_resultados_check CHECK (((resultados >= 0) AND (resultados <= 5)))
);


--
-- Name: TABLE consultas_cercania; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON TABLE campo.consultas_cercania IS 'Análisis de contrato: bitácora de «Contratos cerca de mí» con la posición redondeada a 3 decimales (no la exacta). Solo se agrega; retención 12 meses.';


--
-- Name: consultas_cercania_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.consultas_cercania ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.consultas_cercania_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cuadrilla_eventos; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.cuadrilla_eventos (
    id bigint NOT NULL,
    cuadrilla_id bigint NOT NULL,
    tipo_evento text NOT NULL,
    valor text,
    motivo text,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT cuadrilla_eventos_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT cuadrilla_eventos_ck CHECK ((((tipo_evento = ANY (ARRAY['crear'::text, 'renombrar'::text, 'agregar_actividad'::text, 'quitar_actividad'::text])) = (valor IS NOT NULL)) AND ((tipo_evento <> ALL (ARRAY['desactivar'::text, 'quitar_actividad'::text])) OR (motivo IS NOT NULL)))),
    CONSTRAINT cuadrilla_eventos_motivo_check CHECK (((motivo IS NULL) OR ((length(btrim(motivo)) >= 10) AND (length(btrim(motivo)) <= 300)))),
    CONSTRAINT cuadrilla_eventos_tipo_evento_check CHECK ((tipo_evento = ANY (ARRAY['crear'::text, 'renombrar'::text, 'desactivar'::text, 'activar'::text, 'agregar_actividad'::text, 'quitar_actividad'::text]))),
    CONSTRAINT cuadrilla_eventos_valor_check CHECK (((valor IS NULL) OR ((length(btrim(valor)) >= 2) AND (length(btrim(valor)) <= 60))))
);


--
-- Name: TABLE cuadrilla_eventos; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON TABLE campo.cuadrilla_eventos IS 'Comercial 21-nov: historial de cada cuadrilla (crear, renombrar, desactivar, activar) y de sus actividades (agregar o quitar; valor = código de la actividad). Lo vigente es el último evento de cada actividad. Solo agregar.';


--
-- Name: cuadrilla_eventos_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.cuadrilla_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.cuadrilla_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cuadrillas; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.cuadrillas (
    id bigint NOT NULL,
    nombre text NOT NULL,
    activa boolean DEFAULT true NOT NULL,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT cuadrillas_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT cuadrillas_nombre_check CHECK ((((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 60)) AND (nombre = btrim(nombre))))
);


--
-- Name: TABLE cuadrillas; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON TABLE campo.cuadrillas IS 'Comercial 21-nov: cuadrillas del personal de Comercial. Las crea el supervisor de campo (o el administrador). Nombre único sin distinguir mayúsculas ni espacios. No se borran: se desactivan con motivo (y solo sin miembros).';


--
-- Name: cuadrillas_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.cuadrillas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.cuadrillas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: grupos_reporte; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.grupos_reporte (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT grupos_reporte_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,39}$'::text)),
    CONSTRAINT grupos_reporte_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))
);


--
-- Name: grupos_reporte_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.grupos_reporte ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.grupos_reporte_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: parametros; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.parametros (
    clave text NOT NULL,
    valor numeric NOT NULL,
    unidad text NOT NULL,
    descripcion text NOT NULL,
    minimo numeric,
    maximo numeric,
    actualizado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    actualizado_por text,
    CONSTRAINT parametros_clave_check CHECK ((clave ~ '^[a-z][a-z0-9_]{2,59}$'::text)),
    CONSTRAINT parametros_rango_ck CHECK ((((minimo IS NULL) OR (valor >= minimo)) AND ((maximo IS NULL) OR (valor <= maximo))))
);


--
-- Name: personal_eventos; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.personal_eventos (
    id bigint NOT NULL,
    persona text NOT NULL,
    tipo_evento text NOT NULL,
    formulario text,
    cargo text,
    motivo text,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    valor text,
    CONSTRAINT personal_ev_ck CHECK ((((tipo_evento = 'fijar_cargo'::text) = (cargo IS NOT NULL)) AND ((tipo_evento = ANY (ARRAY['asignar_formulario'::text, 'quitar_formulario'::text])) = (formulario IS NOT NULL)) AND ((tipo_evento <> ALL (ARRAY['quitar_formulario'::text, 'quitar_actividad'::text])) OR (motivo IS NOT NULL)) AND ((tipo_evento <> ALL (ARRAY['fijar_area'::text, 'asignar_actividad'::text, 'quitar_actividad'::text])) OR (valor IS NOT NULL)) AND ((tipo_evento = ANY (ARRAY['fijar_area'::text, 'fijar_cuadrilla'::text, 'asignar_actividad'::text, 'quitar_actividad'::text])) OR (valor IS NULL)) AND ((tipo_evento <> 'fijar_cuadrilla'::text) OR (valor IS NULL) OR (valor ~ '^[0-9]{1,18}$'::text)))),
    CONSTRAINT personal_eventos_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT personal_eventos_cargo_check CHECK (((cargo IS NULL) OR ((length(btrim(cargo)) >= 2) AND (length(btrim(cargo)) <= 80)))),
    CONSTRAINT personal_eventos_formulario_check CHECK (((formulario IS NULL) OR (formulario ~ '^(reporte_general|acta|activo_campo|tipo:[a-z][a-z0-9_]{1,59})$'::text))),
    CONSTRAINT personal_eventos_motivo_check CHECK (((motivo IS NULL) OR ((length(btrim(motivo)) >= 10) AND (length(btrim(motivo)) <= 300)))),
    CONSTRAINT personal_eventos_persona_check CHECK (((persona = lower(persona)) AND (POSITION(('@'::text) IN (persona)) > 1))),
    CONSTRAINT personal_eventos_tipo_evento_check CHECK ((tipo_evento = ANY (ARRAY['fijar_cargo'::text, 'asignar_formulario'::text, 'quitar_formulario'::text, 'fijar_area'::text, 'fijar_cuadrilla'::text, 'asignar_actividad'::text, 'quitar_actividad'::text]))),
    CONSTRAINT personal_eventos_valor_check CHECK (((valor IS NULL) OR (valor ~ '^[a-z0-9_]{1,40}$'::text)))
);


--
-- Name: TABLE personal_eventos; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON TABLE campo.personal_eventos IS 'Pasada 14/11: cargo y formularios asignados del personal de Comercial (campo y acta). Solo agregar. En este corte las asignaciones SOLO se registran (no restringen la captura).';


--
-- Name: COLUMN personal_eventos.valor; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON COLUMN campo.personal_eventos.valor IS 'Comercial 21-nov: el código del área (fijar_area), el id de la cuadrilla (fijar_cuadrilla; nulo = sin cuadrilla) o el código de la actividad (asignar_actividad, quitar_actividad).';


--
-- Name: personal_eventos_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.personal_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.personal_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: preparaciones; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.preparaciones (
    reporte_id uuid NOT NULL,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT preparaciones_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1)))
);


--
-- Name: reporte_eventos_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.reporte_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.reporte_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reporte_fotos_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.reporte_fotos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.reporte_fotos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reportes_seq_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.reportes ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.reportes_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: subtipos_reporte; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.subtipos_reporte (
    id bigint NOT NULL,
    tipo_id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT subtipos_reporte_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT subtipos_reporte_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)))
);


--
-- Name: subtipos_reporte_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.subtipos_reporte ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.subtipos_reporte_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipo_campos; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.tipo_campos (
    id bigint NOT NULL,
    tipo_id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    tipo_dato text NOT NULL,
    obligatorio boolean DEFAULT false NOT NULL,
    opciones jsonb,
    minimo numeric,
    maximo numeric,
    unidad text,
    ayuda text,
    sensible boolean DEFAULT false NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    seccion text,
    visible_si jsonb,
    CONSTRAINT tipo_campos_ayuda_check CHECK (((ayuda IS NULL) OR (length(ayuda) <= 200))),
    CONSTRAINT tipo_campos_codigo_check CHECK (((codigo ~ '^[a-z][a-z0-9_]{1,39}$'::text) AND (codigo !~ 'fecha'::text) AND (codigo <> ALL (ARRAY['usuario'::text, 'email'::text, 'autor'::text, 'solicitante'::text, 'correo'::text, 'registrado_en'::text, 'creado_en'::text])))),
    CONSTRAINT tipo_campos_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 120))),
    CONSTRAINT tipo_campos_opciones_check CHECK (campo.f_opciones_validas(opciones)),
    CONSTRAINT tipo_campos_opciones_ck CHECK (((tipo_dato = ANY (ARRAY['opcion'::text, 'opciones'::text])) = (opciones IS NOT NULL))),
    CONSTRAINT tipo_campos_rango_ck CHECK ((((minimo IS NULL) OR (maximo IS NULL) OR (minimo <= maximo)) AND ((tipo_dato = ANY (ARRAY['entero'::text, 'decimal'::text, 'texto'::text])) OR ((minimo IS NULL) AND (maximo IS NULL))) AND ((tipo_dato <> 'texto'::text) OR ((minimo IS NULL) AND ((maximo IS NULL) OR ((maximo >= (1)::numeric) AND (maximo <= (500)::numeric))))))),
    CONSTRAINT tipo_campos_seccion_ck CHECK (((seccion IS NULL) OR ((length(btrim(seccion)) >= 2) AND (length(btrim(seccion)) <= 60)))),
    CONSTRAINT tipo_campos_tipo_dato_check CHECK ((tipo_dato = ANY (ARRAY['texto'::text, 'entero'::text, 'decimal'::text, 'si_no'::text, 'opcion'::text, 'opciones'::text, 'dia_hora'::text]))),
    CONSTRAINT tipo_campos_unidad_check CHECK (((unidad IS NULL) OR ((length(unidad) >= 1) AND (length(unidad) <= 20)))),
    CONSTRAINT tipo_campos_unidad_ck CHECK (((unidad IS NULL) OR (tipo_dato = ANY (ARRAY['entero'::text, 'decimal'::text])))),
    CONSTRAINT tipo_campos_visible_si_ck CHECK (((visible_si IS NULL) OR ((jsonb_typeof(visible_si) = 'object'::text) AND (visible_si ? 'campo'::text) AND (jsonb_typeof((visible_si -> 'campo'::text)) = 'string'::text) AND ((visible_si ->> 'campo'::text) ~ '^[a-z][a-z0-9_]{1,39}$'::text) AND (((visible_si ? 'es'::text) AND (NOT (visible_si ? 'no_es'::text)) AND (jsonb_typeof((visible_si -> 'es'::text)) = ANY (ARRAY['boolean'::text, 'string'::text])) AND (((visible_si - 'campo'::text) - 'es'::text) = '{}'::jsonb)) OR ((visible_si ? 'no_es'::text) AND (NOT (visible_si ? 'es'::text)) AND (jsonb_typeof((visible_si -> 'no_es'::text)) = 'string'::text) AND (((visible_si - 'campo'::text) - 'no_es'::text) = '{}'::jsonb))))))
);


--
-- Name: COLUMN tipo_campos.seccion; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON COLUMN campo.tipo_campos.seccion IS 'Título de la sección en pantalla (opcional). No afecta la validación.';


--
-- Name: COLUMN tipo_campos.visible_si; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON COLUMN campo.tipo_campos.visible_si IS 'Condición de pantalla {"campo": ..., "es": ...} o {"campo": ..., "no_es": código}. La base no la verifica: un campo oculto que llega con valor se guarda igual. Un campo con condición no debe ser obligatorio.';


--
-- Name: tipo_campos_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.tipo_campos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.tipo_campos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipo_fotos; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.tipo_fotos (
    id bigint NOT NULL,
    tipo_id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    obligatoria boolean DEFAULT true NOT NULL,
    soporte_inefectiva boolean DEFAULT false NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT tipo_fotos_codigo_check CHECK (((codigo ~ '^[a-z][a-z0-9_]{1,39}$'::text) AND (codigo <> 'adicional'::text))),
    CONSTRAINT tipo_fotos_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 120)))
);


--
-- Name: COLUMN tipo_fotos.soporte_inefectiva; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON COLUMN campo.tipo_fotos.soporte_inefectiva IS 'Verdadero = esta etiqueta sirve de soporte de una visita inefectiva hecha en campo (fachada o predio). Si el tipo tiene alguna etiqueta así, la RPC exige al menos una foto con ella cuando el resultado es inefectivo.';


--
-- Name: tipo_fotos_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.tipo_fotos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.tipo_fotos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipos_reporte; Type: TABLE; Schema: campo; Owner: -
--

CREATE TABLE campo.tipos_reporte (
    id bigint NOT NULL,
    grupo_id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    exige_texto boolean DEFAULT false NOT NULL,
    exige_subtipo boolean DEFAULT false NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    fotos_min smallint,
    fotos_max smallint,
    requiere_contrato text DEFAULT 'opcional'::text NOT NULL,
    genera_resultado boolean DEFAULT false NOT NULL,
    prefijo_consecutivo text,
    limite_ventana integer,
    CONSTRAINT tipos_contrato_ck CHECK ((requiere_contrato = ANY (ARRAY['si'::text, 'no'::text, 'opcional'::text]))),
    CONSTRAINT tipos_fotos_ck CHECK ((((fotos_max IS NULL) OR ((fotos_max >= 1) AND (fotos_max <= 10))) AND ((fotos_min IS NULL) OR ((fotos_min >= 0) AND (fotos_min <= 10))) AND ((fotos_min IS NULL) OR (fotos_max IS NULL) OR (fotos_min <= fotos_max)))),
    CONSTRAINT tipos_limite_ck CHECK (((limite_ventana IS NULL) OR ((limite_ventana >= 1) AND (limite_ventana <= 1000)))),
    CONSTRAINT tipos_prefijo_ck CHECK (((prefijo_consecutivo IS NULL) OR (prefijo_consecutivo ~ '^[A-Z]{2,6}$'::text))),
    CONSTRAINT tipos_reporte_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,59}$'::text)),
    CONSTRAINT tipos_reporte_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)))
);


--
-- Name: COLUMN tipos_reporte.limite_ventana; Type: COMMENT; Schema: campo; Owner: -
--

COMMENT ON COLUMN campo.tipos_reporte.limite_ventana IS 'Tope de ritmo propio del formato: máximo de reportes DE ESTE TIPO CON número de contrato que una persona puede crear dentro de la ventana (parámetro ventana_limite_minutos, hoy 60 minutos). Reemplaza, para este tipo, al tope general limite_contratos_ventana. NULO = el tipo no tiene tope propio y se le aplica el tope general (NO significa sin límite). Siempre siguen aplicando el tope general de reportes por hora (limite_reportes_ventana) y el de contratos no verificados en 24 horas (limite_contratos_falsos_dia). Administrador exento; el supervisor no tiene multiplicador. El máximo permitido es 1000, que en la práctica equivale a no limitar.';


--
-- Name: tipos_reporte_id_seq; Type: SEQUENCE; Schema: campo; Owner: -
--

ALTER TABLE campo.tipos_reporte ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME campo.tipos_reporte_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cartera_contrato; Type: TABLE; Schema: hechos; Owner: -
--

CREATE TABLE hechos.cartera_contrato (
    periodo text,
    contrato text,
    product_id text,
    facturas_vencidas text,
    fecha_instalacion text,
    fecha_ult_pago text,
    ultimo_pago text,
    total_cartera text,
    ciclo text
);


--
-- Name: consumo_metodo; Type: TABLE; Schema: hechos; Owner: -
--

CREATE TABLE hechos.consumo_metodo (
    periodo text,
    contrato text,
    ciclo text,
    categoria text,
    subcategoria text,
    medidor text,
    consumo_facturado text,
    consumo_cargos text,
    lectura_actual text,
    lectura_anterior text,
    fecha_lectura_actual text,
    fecha_lectura_anterior text,
    observacion text,
    funcion text,
    metodo_calculo text,
    fecha_instalacion text,
    estado_tecnico text
);


--
-- Name: cupones_pagos; Type: TABLE; Schema: hechos; Owner: -
--

CREATE TABLE hechos.cupones_pagos (
    periodo text,
    contrato text,
    cupon text,
    valor text,
    fecha_pago text
);


--
-- Name: facturacion_contratos; Type: TABLE; Schema: hechos; Owner: -
--

CREATE TABLE hechos.facturacion_contratos (
    periodo text,
    contrato text,
    ciclo text,
    categoria text,
    subcategoria text,
    concepto text,
    facturado text,
    consumo text
);


--
-- Name: reclamos; Type: TABLE; Schema: hechos; Owner: -
--

CREATE TABLE hechos.reclamos (
    periodo text,
    contrato text,
    solicitud text,
    fecha_registro text,
    estado text,
    causal text,
    nombre_cliente text
);


--
-- Name: barrios_valledupar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.barrios_valledupar (
    id bigint NOT NULL,
    nombre text,
    buscable boolean DEFAULT true
);


--
-- Name: barrios_valledupar_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.barrios_valledupar ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.barrios_valledupar_id_seq
    START WITH 100000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cartera_suscripcion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cartera_suscripcion (
    contrato text,
    estado text,
    identificacion text,
    nombre text,
    correo text,
    telefono text,
    direccion text,
    barrio text,
    categoria text,
    subcategoria text,
    ciclo text,
    facturas_pendientes numeric,
    deuda_total numeric,
    saldo_pendiente numeric,
    saldo_a_favor numeric,
    valor_reclamo numeric,
    saldo_financiado numeric,
    serial_medidor text,
    codigo_reparto text,
    ruta text,
    periodo_carga text
);


--
-- Name: catastro_valledupar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catastro_valledupar (
    id bigint NOT NULL,
    cod_usuario text,
    direccion text,
    barrio text,
    estrato text,
    clase_uso text,
    geom public.geometry,
    telefono text,
    telefono_propie text,
    diam_med text
);


--
-- Name: catastro_valledupar_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.catastro_valledupar ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.catastro_valledupar_id_seq
    START WITH 100000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: geoportal_auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geoportal_auditoria (
    id bigint NOT NULL,
    email text,
    accion text,
    referencia text,
    detalle jsonb,
    ip text,
    creado_en timestamp with time zone DEFAULT now()
);


--
-- Name: geoportal_auditoria_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.geoportal_auditoria ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.geoportal_auditoria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: geoportal_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geoportal_config (
    id integer NOT NULL,
    pausado boolean DEFAULT false,
    pausado_por text,
    pausado_en timestamp with time zone,
    aislamiento_tecnica_ok boolean DEFAULT false
);


--
-- Name: geoportal_lista_blanca; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geoportal_lista_blanca (
    email text NOT NULL,
    nombre text,
    activo boolean DEFAULT true,
    creado_en timestamp with time zone DEFAULT now(),
    creado_por text,
    rol text DEFAULT 'consulta'::text,
    ver_explorar boolean DEFAULT true,
    ver_focalizacion boolean DEFAULT false,
    ver_comercial boolean DEFAULT false,
    ver_rutas boolean DEFAULT false,
    horario text DEFAULT 'laboral'::text,
    dias text DEFAULT 'habiles'::text,
    ver_dashboard boolean DEFAULT false,
    ver_registro_tecnico boolean DEFAULT false,
    ver_dashboard_tecnico boolean DEFAULT false,
    ver_campo boolean DEFAULT false NOT NULL,
    ver_dashboard_campo boolean DEFAULT false NOT NULL,
    ver_acta boolean DEFAULT false NOT NULL,
    ver_dashboard_acta boolean DEFAULT false NOT NULL,
    ver_aseo boolean DEFAULT false NOT NULL,
    ver_dashboard_aseo boolean DEFAULT false NOT NULL,
    ver_analisis_contrato boolean DEFAULT false NOT NULL,
    CONSTRAINT geoportal_lista_blanca_rol_check CHECK ((rol = ANY (ARRAY['admin'::text, 'consulta'::text])))
);


--
-- Name: COLUMN geoportal_lista_blanca.ver_campo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.geoportal_lista_blanca.ver_campo IS 'Formatos de campo: puede registrar reportes (cualquier persona con el modo).';


--
-- Name: COLUMN geoportal_lista_blanca.ver_dashboard_campo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.geoportal_lista_blanca.ver_dashboard_campo IS 'Formatos de campo: supervisor de reportes (ve, clasifica, oculta, vincula duplicados). El administrador pasa siempre.';


--
-- Name: COLUMN geoportal_lista_blanca.ver_acta; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.geoportal_lista_blanca.ver_acta IS 'Acta de inspección técnica: puede capturar (registrar) actas.';


--
-- Name: COLUMN geoportal_lista_blanca.ver_dashboard_acta; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.geoportal_lista_blanca.ver_dashboard_acta IS 'Acta de inspección técnica: supervisor (revisa, cambia estado, oculta, corrige). El administrador pasa siempre.';


--
-- Name: COLUMN geoportal_lista_blanca.ver_aseo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.geoportal_lista_blanca.ver_aseo IS 'Aseo (interventoría): puede capturar auditorías.';


--
-- Name: COLUMN geoportal_lista_blanca.ver_dashboard_aseo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.geoportal_lista_blanca.ver_dashboard_aseo IS 'Aseo (interventoría): supervisor (revisa, oculta, gestiona rutas). El administrador pasa siempre.';


--
-- Name: COLUMN geoportal_lista_blanca.ver_analisis_contrato; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.geoportal_lista_blanca.ver_analisis_contrato IS 'Análisis de contrato (Formularios de campo): consulta un contrato con cartera, consumo, medidor, gestiones, ubicación, nombre y teléfono del suscriptor. El administrador pasa siempre.';


--
-- Name: predios_comercial_fuente_local; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.predios_comercial_fuente_local (
    id bigint NOT NULL,
    cod_usuario text,
    deuda_total numeric,
    barrio text,
    estado_predio text,
    tramo_mora text
);


--
-- Name: predios_comercial; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.predios_comercial AS
 SELECT id,
    cod_usuario,
    deuda_total,
    barrio,
    estado_predio,
    tramo_mora
   FROM public.predios_comercial_fuente_local
  WITH NO DATA;


--
-- Name: v_reportes_comercial; Type: VIEW; Schema: redes; Owner: -
--

CREATE VIEW redes.v_reportes_comercial AS
 SELECT COALESCE(e.consecutivo, ('REP-'::text || lpad((e.seq)::text, 6, '0'::text))) AS codigo,
    t.nombre AS tipo,
    s.nombre AS subtipo,
    COALESCE(r.area, 'comercial'::text) AS area,
    (e.contrato IS NOT NULL) AS con_contrato,
    COALESCE(x.nombre, e.estado) AS estado,
    e.registrado_en,
    e.lat,
    e.lon
   FROM ((((campo.v_reportes_estado e
     JOIN campo.reportes r ON ((r.id = e.id)))
     JOIN campo.tipos_reporte t ON ((t.id = e.tipo_id)))
     LEFT JOIN campo.subtipos_reporte s ON ((s.id = e.subtipo_id)))
     LEFT JOIN campo.estados_reporte x ON ((x.codigo = e.estado)))
  WHERE ((NOT e.oculto) AND ((t.codigo = 'revision_previa'::text) OR campo.f_tipo_general(t.codigo)));


--
-- Name: VIEW v_reportes_comercial; Type: COMMENT; Schema: redes; Owner: -
--

COMMENT ON VIEW redes.v_reportes_comercial IS 'Corte 8: reportes de anomalía y revisiones generales de campo.reportes para el geovisor técnico. Sin contrato, descripción, fotos ni autor.';


--
-- Name: config_documentos; Type: TABLE; Schema: salida; Owner: -
--

CREATE TABLE salida.config_documentos (
    documento text NOT NULL,
    habilitado boolean DEFAULT false NOT NULL,
    copias_internas text[] DEFAULT '{}'::text[] NOT NULL,
    actualizado_por text,
    actualizado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT config_documentos_documento_check CHECK ((documento = ANY (ARRAY['acta_inspeccion'::text, 'revision_previa'::text, 'revision_pqr'::text, 'instalacion_medidor'::text, 'instalacion_acometida'::text])))
);


--
-- Name: config_eventos; Type: TABLE; Schema: salida; Owner: -
--

CREATE TABLE salida.config_eventos (
    id bigint NOT NULL,
    documento text NOT NULL,
    habilitado boolean NOT NULL,
    copias_internas text[] NOT NULL,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: config_eventos_id_seq; Type: SEQUENCE; Schema: salida; Owner: -
--

ALTER TABLE salida.config_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME salida.config_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: contactos; Type: TABLE; Schema: salida; Owner: -
--

CREATE TABLE salida.contactos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    esquema_origen text NOT NULL,
    registro_id uuid NOT NULL,
    documento text NOT NULL,
    correo text,
    celular text,
    parte text NOT NULL,
    autoriza boolean NOT NULL,
    texto_version integer NOT NULL,
    autor text NOT NULL,
    reservado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    depurado_en timestamp with time zone,
    CONSTRAINT contactos_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT contactos_autoriza_check CHECK (autoriza),
    CONSTRAINT contactos_celular_check CHECK (((celular IS NULL) OR (celular ~ '^3[0-9]{9}$'::text))),
    CONSTRAINT contactos_check CHECK ((((depurado_en IS NULL) AND (correo IS NOT NULL)) OR ((depurado_en IS NOT NULL) AND (correo IS NULL) AND (celular IS NULL)))),
    CONSTRAINT contactos_correo_check CHECK (((correo IS NULL) OR ((correo = lower(correo)) AND (correo ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::text) AND (length(correo) <= 254)))),
    CONSTRAINT contactos_esquema_origen_check CHECK ((esquema_origen = ANY (ARRAY['acta'::text, 'campo'::text]))),
    CONSTRAINT contactos_parte_check CHECK ((parte = ANY (ARRAY['quien_atendio'::text, 'suscriptor'::text, 'otro'::text])))
);


--
-- Name: envio_eventos; Type: TABLE; Schema: salida; Owner: -
--

CREATE TABLE salida.envio_eventos (
    id bigint NOT NULL,
    envio_id uuid NOT NULL,
    estado_desde text,
    estado_hasta text NOT NULL,
    actor text NOT NULL,
    detalle jsonb DEFAULT '{}'::jsonb NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: envio_eventos_id_seq; Type: SEQUENCE; Schema: salida; Owner: -
--

ALTER TABLE salida.envio_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME salida.envio_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: envios; Type: TABLE; Schema: salida; Owner: -
--

CREATE TABLE salida.envios (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contacto_id uuid,
    esquema_origen text NOT NULL,
    registro_id uuid NOT NULL,
    documento text NOT NULL,
    consecutivo text NOT NULL,
    destinatario_correo text,
    destinatario_celular text,
    parte text,
    copias_internas text[] DEFAULT '{}'::text[] NOT NULL,
    texto_version integer,
    constancia jsonb NOT NULL,
    constancia_version integer DEFAULT 1 NOT NULL,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    intentos integer DEFAULT 0 NOT NULL,
    max_intentos integer NOT NULL,
    tomado_hasta timestamp with time zone,
    lease_id uuid,
    ultimo_error text,
    ultimo_cambio_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    depurado_en timestamp with time zone,
    CONSTRAINT envios_check CHECK (((destinatario_correo IS NOT NULL) OR (depurado_en IS NOT NULL) OR (cardinality(copias_internas) > 0))),
    CONSTRAINT envios_check1 CHECK (((estado <> 'tomado'::text) OR ((lease_id IS NOT NULL) AND (tomado_hasta IS NOT NULL)))),
    CONSTRAINT envios_constancia_check CHECK ((jsonb_typeof(constancia) = 'object'::text)),
    CONSTRAINT envios_esquema_origen_check CHECK ((esquema_origen = ANY (ARRAY['acta'::text, 'campo'::text]))),
    CONSTRAINT envios_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'tomado'::text, 'enviado'::text, 'rebotado'::text, 'error'::text, 'anulado'::text]))),
    CONSTRAINT envios_intentos_check CHECK ((intentos >= 0)),
    CONSTRAINT envios_max_intentos_check CHECK (((max_intentos >= 1) AND (max_intentos <= 20))),
    CONSTRAINT envios_ultimo_error_check CHECK (((ultimo_error IS NULL) OR (length(ultimo_error) <= 500)))
);


--
-- Name: fallos_encolado; Type: TABLE; Schema: salida; Owner: -
--

CREATE TABLE salida.fallos_encolado (
    id bigint NOT NULL,
    esquema_origen text,
    registro_id uuid,
    mensaje text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: fallos_encolado_id_seq; Type: SEQUENCE; Schema: salida; Owner: -
--

ALTER TABLE salida.fallos_encolado ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME salida.fallos_encolado_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: parametros; Type: TABLE; Schema: salida; Owner: -
--

CREATE TABLE salida.parametros (
    clave text NOT NULL,
    valor numeric NOT NULL,
    descripcion text NOT NULL,
    minimo numeric,
    maximo numeric,
    actualizado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT parametros_clave_check CHECK ((clave ~ '^[a-z][a-z0-9_]{2,59}$'::text)),
    CONSTRAINT parametros_rango_ck CHECK ((((minimo IS NULL) OR (valor >= minimo)) AND ((maximo IS NULL) OR (valor <= maximo))))
);


--
-- Name: textos_autorizacion_version_seq; Type: SEQUENCE; Schema: salida; Owner: -
--

ALTER TABLE salida.textos_autorizacion ALTER COLUMN version ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME salida.textos_autorizacion_version_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: v_envios_pendientes; Type: VIEW; Schema: salida; Owner: -
--

CREATE VIEW salida.v_envios_pendientes AS
 SELECT id AS envio_id,
    creado_en,
    documento,
    consecutivo,
    esquema_origen,
    registro_id,
    destinatario_correo,
    destinatario_celular,
    NULL::text AS destinatario_nombre,
    parte,
    copias_internas,
    texto_version,
    constancia,
    intentos,
    ultimo_error,
    constancia_version
   FROM salida.envios e
  WHERE (((estado = 'pendiente'::text) OR ((estado = 'tomado'::text) AND (tomado_hasta < clock_timestamp()))) AND (intentos < max_intentos) AND salida.f_registro_vigente(esquema_origen, registro_id));


--
-- Name: buckets; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text,
    public boolean,
    file_size_limit bigint,
    allowed_mime_types text[]
);


--
-- Name: objects; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: exclusiones; Type: TABLE; Schema: tecnica; Owner: -
--

CREATE TABLE tecnica.exclusiones (
    id bigint NOT NULL,
    registro_id bigint,
    lote_id uuid,
    accion text DEFAULT 'EXCLUIR'::text NOT NULL,
    motivo text NOT NULL,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT exclusiones_accion_check CHECK ((accion = ANY (ARRAY['EXCLUIR'::text, 'REINCLUIR'::text]))),
    CONSTRAINT exclusiones_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT exclusiones_check CHECK ((num_nonnulls(registro_id, lote_id) = 1)),
    CONSTRAINT exclusiones_motivo_check CHECK (((length(btrim(motivo)) >= 10) AND (length(btrim(motivo)) <= 1000)))
);


--
-- Name: exclusiones_id_seq; Type: SEQUENCE; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.exclusiones ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME tecnica.exclusiones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: formulario_variables; Type: TABLE; Schema: tecnica; Owner: -
--

CREATE TABLE tecnica.formulario_variables (
    id bigint NOT NULL,
    formulario tecnica.formulario_clave NOT NULL,
    variable_id bigint NOT NULL,
    orden smallint DEFAULT 1 NOT NULL,
    obligatoria boolean DEFAULT false NOT NULL,
    alcance text NOT NULL,
    punto_id bigint,
    activa boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT formulario_variables_alcance_check CHECK ((alcance = ANY (ARRAY['por_planta'::text, 'ambas_plantas'::text]))),
    CONSTRAINT formulario_variables_orden_check CHECK (((orden >= 1) AND (orden <= 999)))
);


--
-- Name: formulario_variables_id_seq; Type: SEQUENCE; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.formulario_variables ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME tecnica.formulario_variables_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: personal_tecnico_eventos; Type: TABLE; Schema: tecnica; Owner: -
--

CREATE TABLE tecnica.personal_tecnico_eventos (
    id bigint NOT NULL,
    persona text NOT NULL,
    tipo_evento text NOT NULL,
    formulario tecnica.formulario_clave,
    motivo text,
    autor text NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT personal_tecnico_eventos_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT personal_tecnico_eventos_check CHECK (((tipo_evento = ANY (ARRAY['asignar_formulario'::text, 'quitar_formulario'::text])) = (formulario IS NOT NULL))),
    CONSTRAINT personal_tecnico_eventos_check1 CHECK (((tipo_evento <> ALL (ARRAY['quitar_formulario'::text, 'desactivar_tecnica'::text])) OR (motivo IS NOT NULL))),
    CONSTRAINT personal_tecnico_eventos_motivo_check CHECK (((motivo IS NULL) OR ((length(btrim(motivo)) >= 3) AND (length(btrim(motivo)) <= 1000)))),
    CONSTRAINT personal_tecnico_eventos_persona_check CHECK (((persona = lower(persona)) AND (POSITION(('@'::text) IN (persona)) > 1))),
    CONSTRAINT personal_tecnico_eventos_tipo_evento_check CHECK ((tipo_evento = ANY (ARRAY['asignar_formulario'::text, 'quitar_formulario'::text, 'activar_tecnica'::text, 'desactivar_tecnica'::text])))
);


--
-- Name: personal_tecnico_eventos_id_seq; Type: SEQUENCE; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.personal_tecnico_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME tecnica.personal_tecnico_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: plantas; Type: TABLE; Schema: tecnica; Owner: -
--

CREATE TABLE tecnica.plantas (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    activa boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT plantas_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,29}$'::text)),
    CONSTRAINT plantas_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 80)))
);


--
-- Name: plantas_id_seq; Type: SEQUENCE; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.plantas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME tecnica.plantas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: puntos; Type: TABLE; Schema: tecnica; Owner: -
--

CREATE TABLE tecnica.puntos (
    id bigint NOT NULL,
    planta_id bigint,
    codigo text NOT NULL,
    nombre text NOT NULL,
    tipo text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT puntos_codigo_check CHECK ((codigo ~ '^[A-Z0-9][A-Z0-9_-]{1,39}$'::text)),
    CONSTRAINT puntos_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 120))),
    CONSTRAINT puntos_tipo_check CHECK ((tipo = ANY (ARRAY['macromedicion'::text, 'muestreo'::text, 'tanque'::text])))
);


--
-- Name: puntos_id_seq; Type: SEQUENCE; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.puntos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME tecnica.puntos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: registros; Type: TABLE; Schema: tecnica; Owner: -
--

CREATE TABLE tecnica.registros (
    id bigint NOT NULL,
    lote_id uuid NOT NULL,
    formulario tecnica.formulario_clave NOT NULL,
    variable_id bigint NOT NULL,
    planta_id bigint,
    punto_id bigint,
    valor numeric NOT NULL,
    fecha_muestra date NOT NULL,
    hora_muestra time(0) without time zone NOT NULL,
    registrado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    autor text NOT NULL,
    clave_envio text,
    muestra_ts timestamp with time zone GENERATED ALWAYS AS (((fecha_muestra + hora_muestra) AT TIME ZONE 'America/Bogota'::text)) STORED,
    CONSTRAINT ck_registro_fecha_hoy CHECK (((fecha_muestra <= ((registrado_en AT TIME ZONE 'America/Bogota'::text))::date) AND (fecha_muestra >= (((registrado_en AT TIME ZONE 'America/Bogota'::text))::date - 1)))),
    CONSTRAINT registros_autor_check CHECK (((autor = lower(autor)) AND (POSITION(('@'::text) IN (autor)) > 1))),
    CONSTRAINT registros_clave_envio_check CHECK (((clave_envio IS NULL) OR (clave_envio ~ '^[A-Za-z0-9_-]{8,80}$'::text))),
    CONSTRAINT registros_valor_check CHECK (((valor)::text <> ALL (ARRAY['NaN'::text, 'Infinity'::text, '-Infinity'::text])))
);


--
-- Name: registros_id_seq; Type: SEQUENCE; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.registros ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME tecnica.registros_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: senal_cambio; Type: TABLE; Schema: tecnica; Owner: -
--

CREATE TABLE tecnica.senal_cambio (
    id bigint NOT NULL,
    tabla text NOT NULL,
    planta_id bigint,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT senal_cambio_tabla_check CHECK ((tabla = ANY (ARRAY['registros'::text, 'exclusiones'::text, 'personal_tecnico_eventos'::text])))
);


--
-- Name: senal_cambio_id_seq; Type: SEQUENCE; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.senal_cambio ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME tecnica.senal_cambio_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: v_registros_estado; Type: VIEW; Schema: tecnica; Owner: -
--

CREATE VIEW tecnica.v_registros_estado AS
 SELECT r.id,
    r.lote_id,
    r.formulario,
    r.variable_id,
    r.planta_id,
    r.punto_id,
    r.valor,
    r.fecha_muestra,
    r.hora_muestra,
    r.registrado_en,
    r.autor,
    r.clave_envio,
    r.muestra_ts,
    COALESCE((ult.accion = 'EXCLUIR'::text), false) AS excluido,
    ult.id AS exclusion_id,
    ult.motivo AS exclusion_motivo,
    ult.autor AS exclusion_autor,
    ult.creado_en AS exclusion_en
   FROM (tecnica.registros r
     LEFT JOIN LATERAL ( SELECT e.id,
            e.accion,
            e.motivo,
            e.autor,
            e.creado_en
           FROM tecnica.exclusiones e
          WHERE ((e.registro_id = r.id) OR (e.lote_id = r.lote_id))
          ORDER BY e.id DESC
         LIMIT 1) ult ON (true));


--
-- Name: variables; Type: TABLE; Schema: tecnica; Owner: -
--

CREATE TABLE tecnica.variables (
    id bigint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    unidad text NOT NULL,
    categoria text NOT NULL,
    decimales smallint DEFAULT 2 NOT NULL,
    ref_min numeric,
    ref_max numeric,
    activa boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT variables_categoria_check CHECK ((categoria = ANY (ARRAY['fisicoquimico'::text, 'caudal'::text, 'nivel'::text, 'otro'::text]))),
    CONSTRAINT variables_check CHECK (((ref_min IS NULL) OR (ref_max IS NULL) OR (ref_min <= ref_max))),
    CONSTRAINT variables_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{1,39}$'::text)),
    CONSTRAINT variables_decimales_check CHECK (((decimales >= 0) AND (decimales <= 6))),
    CONSTRAINT variables_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100))),
    CONSTRAINT variables_unidad_check CHECK (((length(btrim(unidad)) >= 1) AND (length(btrim(unidad)) <= 20)))
);


--
-- Name: v_registros_detalle; Type: VIEW; Schema: tecnica; Owner: -
--

CREATE VIEW tecnica.v_registros_detalle AS
 SELECT s.id AS registro_id,
    s.lote_id,
    s.formulario,
    v.codigo AS variable,
    v.nombre AS variable_nombre,
    v.unidad,
    v.categoria,
    v.decimales,
    s.valor,
    pl.codigo AS planta,
    pl.nombre AS planta_nombre,
    pu.codigo AS punto,
    pu.nombre AS punto_nombre,
    s.fecha_muestra,
    s.hora_muestra,
    s.muestra_ts,
    s.registrado_en,
    s.autor,
    tecnica.f_marca_rango(s.valor, v.ref_min, v.ref_max) AS fuera_de_rango,
    s.excluido,
    s.exclusion_motivo,
    s.exclusion_autor,
    s.exclusion_en
   FROM (((tecnica.v_registros_estado s
     JOIN tecnica.variables v ON ((v.id = s.variable_id)))
     LEFT JOIN tecnica.plantas pl ON ((pl.id = s.planta_id)))
     LEFT JOIN tecnica.puntos pu ON ((pu.id = s.punto_id)));


--
-- Name: v_entrada_ancha; Type: VIEW; Schema: tecnica; Owner: -
--

CREATE VIEW tecnica.v_entrada_ancha AS
 SELECT lote_id,
    min(fecha_muestra) AS fecha_muestra,
    min(hora_muestra) AS hora_muestra,
    min(registrado_en) AS registrado_en,
    min(autor) AS autor,
    bool_and(excluido) AS excluido,
    max(valor) FILTER (WHERE ((variable = 'caudal_qi'::text) AND (planta = 'gota_fria'::text))) AS caudal_qi_gota_fria,
    max(valor) FILTER (WHERE ((variable = 'caudal_qi'::text) AND (planta = 'huaricha'::text))) AS caudal_qi_huaricha,
    max(valor) FILTER (WHERE ((variable = 'turbiedad_ingreso'::text) AND (planta IS NULL))) AS turbiedad_ingreso,
    max(valor) FILTER (WHERE ((variable = 'alcalinidad_ingreso'::text) AND (planta IS NULL))) AS alcalinidad_ingreso,
    max(valor) FILTER (WHERE ((variable = 'ph_ingreso'::text) AND (planta IS NULL))) AS ph_ingreso,
    max(valor) FILTER (WHERE ((variable = 'conductividad'::text) AND (planta IS NULL))) AS conductividad
   FROM tecnica.v_registros_detalle d
  WHERE ((formulario)::text = 'entrada'::text)
  GROUP BY lote_id;


--
-- Name: v_lotes; Type: VIEW; Schema: tecnica; Owner: -
--

CREATE VIEW tecnica.v_lotes AS
 SELECT lote_id,
    formulario,
    min(fecha_muestra) AS fecha_muestra,
    min(hora_muestra) AS hora_muestra,
    min(registrado_en) AS registrado_en,
    min(autor) AS autor,
    bool_and(excluido) AS excluido,
    jsonb_object_agg((variable || COALESCE(('__'::text || planta), ''::text)), valor) AS valores
   FROM tecnica.v_registros_detalle d
  GROUP BY lote_id, formulario;


--
-- Name: variables_id_seq; Type: SEQUENCE; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.variables ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME tecnica.variables_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Data for Name: accesos_evidencia; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.accesos_evidencia (id, autor, acta_id, orden, accedido_en) FROM stdin;
\.


--
-- Data for Name: acciones_correctivas; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.acciones_correctivas (id, codigo, nombre, orden, campos, activo, creado_en) FROM stdin;
1	suspension_inmediata	Suspensión inmediata del servicio desde la red	10	[{"tipo": "hora", "clave": "suspension_a_las", "etiqueta": "Hora de la suspensión", "obligatorio": true}]	t	2026-11-21 18:45:37.803892-05
2	retiro_acometida_ilegal	Retiro de acometida ilegal, paralela o bypass	20	[{"tipo": "texto", "clave": "descripcion", "etiqueta": "Descripción de lo retirado", "obligatorio": true}]	t	2026-11-21 18:45:37.804081-05
3	retiro_medidor	Retiro de medidor para calibración o laboratorio técnico	30	[{"tipo": "texto", "clave": "serie_retirada", "etiqueta": "Serie del medidor retirado", "obligatorio": true}, {"tipo": "numero", "clave": "lectura_retiro", "etiqueta": "Lectura al retiro (m³)", "obligatorio": true}, {"tipo": "texto", "clave": "sello_o_bolsa", "etiqueta": "Número de sello o bolsa de custodia", "obligatorio": true}, {"tipo": "texto", "clave": "destino", "etiqueta": "Destino", "obligatorio": true}]	t	2026-11-21 18:45:37.804092-05
4	instalacion_medidor_o_sello	Instalación de nuevo medidor o sello de seguridad	40	[{"tipo": "texto", "clave": "serie_nueva", "etiqueta": "Serie del medidor nuevo", "obligatorio": false}, {"tipo": "numero", "clave": "lectura_inicial", "etiqueta": "Lectura inicial (m³)", "obligatorio": false}, {"tipo": "texto", "clave": "sello_instalado", "etiqueta": "Número de sello instalado", "obligatorio": false}, {"tipo": "texto", "clave": "diametro_acometida", "etiqueta": "Diámetro de la acometida", "obligatorio": false}]	t	2026-11-21 18:45:37.8041-05
5	normalizacion_provisional	Normalización provisional de la acometida	50	[{"tipo": "texto", "clave": "descripcion", "etiqueta": "Descripción", "obligatorio": true}]	t	2026-11-21 18:45:37.804112-05
6	corte_taponamiento	Corte o taponamiento	60	[{"tipo": "texto", "clave": "descripcion", "etiqueta": "Descripción", "obligatorio": true}, {"tipo": "hora", "clave": "realizado_a_las", "etiqueta": "Hora", "obligatorio": true}]	t	2026-11-21 18:45:37.804121-05
\.


--
-- Data for Name: acta_acciones; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.acta_acciones (id, acta_id, accion_id, detalle) FROM stdin;
\.


--
-- Data for Name: acta_fotos; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.acta_fotos (id, acta_id, orden, tipo_foto_id, ruta_storage, sha256, tamano_bytes, tipo_mime, detalle, posterior, heredada_de, registrada_en) FROM stdin;
\.


--
-- Data for Name: acta_hallazgos; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.acta_hallazgos (acta_id, tipo_hallazgo_id, texto_otro) FROM stdin;
\.


--
-- Data for Name: acta_personas; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.acta_personas (id, acta_id, rol, nombre, email, calidad_id, calidad_texto, origen) FROM stdin;
\.


--
-- Data for Name: acta_sellos; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.acta_sellos (acta_id, sello_sha256, calculado_en) FROM stdin;
\.


--
-- Data for Name: actas; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.actas (id, seq, consecutivo, serie, numero, version, acta_raiz_id, version_anterior_id, motivo_correccion, numero_acta_fisica, fecha_acta_fisica, papel_pendiente, modo_identificacion, contrato, direccion, barrio, barrio_id, barrio_fuera_de_lista, estrato, uso, referencia_ubicacion, lat, lon, precision_m, fuera_de_zona, tiene_medidor, medidor_serie, marca, lectura_m3, estado_medidor_id, estado_sellos_id, serie_sellos, diametro_id, sin_irregularidad, descripcion_hallazgos, nadie_atendio, derechos_informados, firmo_operario, firmo_atendiente, se_nego_a_firmar, constancia_operario, observaciones, inicio_en, fin_en, registrado_en, autor, reporte_id, esquema_version) FROM stdin;
\.


--
-- Data for Name: apertura_eventos; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.apertura_eventos (id, apertura_id, tipo_evento, motivo_codigo, motivo_texto, autor, rol_autor, creado_en) FROM stdin;
\.


--
-- Data for Name: aperturas; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.aperturas (id, seq, serie, numero, consecutivo, autor, abierto_en, lat, lon, precision_m, fuera_de_zona, reporte_id, acta_raiz_id, correccion_de, motivo_correccion) FROM stdin;
\.


--
-- Data for Name: calidades_atendiente; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.calidades_atendiente (id, codigo, nombre, exige_texto, orden, activo, creado_en) FROM stdin;
1	propietario	Propietario	f	10	t	2026-11-21 18:45:37.803041-05
2	arrendatario	Arrendatario	f	20	t	2026-11-21 18:45:37.803198-05
3	poseedor	Poseedor	f	30	t	2026-11-21 18:45:37.803207-05
4	residente	Residente	f	40	t	2026-11-21 18:45:37.803212-05
5	otro	Otro	t	90	t	2026-11-21 18:45:37.803217-05
\.


--
-- Data for Name: caso_eventos; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.caso_eventos (id, acta_raiz_id, tipo_evento, estado_nuevo, motivo, custodia_codigo, contrato, reporte_id, acta_id, autor, creado_en) FROM stdin;
\.


--
-- Data for Name: consecutivos; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.consecutivos (serie, prefijo, ultimo_numero, actualizado_en) FROM stdin;
2026	AI	0	2026-11-21 18:45:37.802544-05
\.


--
-- Data for Name: consultas_contrato; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.consultas_contrato (id, autor, contrato, existe, consultado_en) FROM stdin;
\.


--
-- Data for Name: diametros_acometida; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.diametros_acometida (id, codigo, nombre, orden, activo, creado_en) FROM stdin;
1	d_1_2	1/2 pulgada	10	t	2026-11-21 18:45:37.80361-05
2	d_3_4	3/4 de pulgada	20	t	2026-11-21 18:45:37.803812-05
3	d_1	1 pulgada	30	t	2026-11-21 18:45:37.803821-05
4	d_1_1_2	1 1/2 pulgadas	40	t	2026-11-21 18:45:37.803827-05
5	d_2	2 pulgadas	50	t	2026-11-21 18:45:37.803832-05
6	d_3	3 pulgadas	60	t	2026-11-21 18:45:37.803836-05
7	d_4	4 pulgadas	70	t	2026-11-21 18:45:37.803841-05
8	otro	Otro (describir en observaciones)	99	t	2026-11-21 18:45:37.803845-05
\.


--
-- Data for Name: estados_caso; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.estados_caso (codigo, nombre, orden, inicial, inicial_sin_irregularidad, exige_motivo, cambio_manual, terminal, gestiona, activo, creado_en) FROM stdin;
reportado	Reportado	10	t	f	f	f	f	sistema	t	2026-11-21 18:45:37.804354-05
papel_recibido	Papel recibido	20	f	f	f	t	f	supervisor	t	2026-11-21 18:45:37.804497-05
en_revision	En revisión	30	f	f	f	t	f	supervisor	t	2026-11-21 18:45:37.804505-05
confirmado	Hallazgo confirmado (fraude)	40	f	f	t	t	f	supervisor	t	2026-11-21 18:45:37.804511-05
descartado	Descartado	50	f	f	t	t	t	supervisor	t	2026-11-21 18:45:37.804516-05
cerrado_constancia	Cerrado como constancia	60	f	t	f	f	t	sistema	t	2026-11-21 18:45:37.804522-05
en_gestion_posterior	En gestión de jurídica o control de pérdidas	70	f	f	f	t	f	juridica	t	2026-11-21 18:45:37.804572-05
cerrado	Cerrado	80	f	f	t	t	t	juridica	t	2026-11-21 18:45:37.804616-05
\.


--
-- Data for Name: estados_custodia; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.estados_custodia (codigo, nombre, orden, activo, creado_en) FROM stdin;
en_campo	En poder de la cuadrilla	10	t	2026-11-21 18:45:37.805245-05
entregado_almacen	Entregado al almacén	20	t	2026-11-21 18:45:37.805351-05
en_laboratorio	En laboratorio	30	t	2026-11-21 18:45:37.805363-05
resultado_recibido	Resultado recibido	40	t	2026-11-21 18:45:37.805369-05
\.


--
-- Data for Name: estados_medidor; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.estados_medidor (id, codigo, nombre, orden, activo, creado_en) FROM stdin;
1	funcionando	Funcionando	10	t	2026-11-21 18:45:37.803245-05
2	frenado	Frenado	20	t	2026-11-21 18:45:37.803388-05
3	invertido	Invertido	30	t	2026-11-21 18:45:37.803395-05
4	empanado	Empañado	40	t	2026-11-21 18:45:37.8034-05
5	destruido_ausente	Destruido o ausente	50	t	2026-11-21 18:45:37.803405-05
\.


--
-- Data for Name: estados_sellos; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.estados_sellos (id, codigo, nombre, orden, activo, creado_en) FROM stdin;
1	conformes	Conformes	10	t	2026-11-21 18:45:37.803433-05
2	rotos	Rotos	20	t	2026-11-21 18:45:37.803565-05
3	ausentes	Ausentes	30	t	2026-11-21 18:45:37.803571-05
4	manipulados	Manipulados	40	t	2026-11-21 18:45:37.803576-05
\.


--
-- Data for Name: motivos_cancelacion; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.motivos_cancelacion (id, codigo, nombre, exige_texto, orden, activo, creado_en) FROM stdin;
1	prueba	Prueba	f	10	t	2026-11-21 18:45:37.844746-05
2	equivocacion_formulario	Me equivoqué de formulario	f	20	t	2026-11-21 18:45:37.844877-05
3	visita_no_realizada	Visita no realizada	f	30	t	2026-11-21 18:45:37.844889-05
4	duplicado	Duplicado	f	40	t	2026-11-21 18:45:37.844895-05
5	otro	Otro (escriba cuál)	t	90	t	2026-11-21 18:45:37.844899-05
\.


--
-- Data for Name: parametros; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.parametros (clave, valor, unidad, descripcion, minimo, maximo, actualizado_en, actualizado_por) FROM stdin;
min_fotos_irregularidad	2	fotos	Mínimo de fotos del hallazgo cuando hay irregularidad (fachada y hallazgo). PROPUESTA del diseño	1	20	2026-11-21 18:45:37.79935-05	\N
min_fotos_sin_irregularidad	1	fotos	Mínimo de fotos del predio cuando NO hay irregularidad. PROPUESTA	0	20	2026-11-21 18:45:37.799638-05	\N
max_fotos	10	fotos	Máximo de fotos del hallazgo (sin contar las del acta física). PROPUESTA del diseño	2	30	2026-11-21 18:45:37.799654-05	\N
max_fotos_acta_fisica	2	fotos	Máximo de fotos del acta física firmada (páginas del papel)	1	6	2026-11-21 18:45:37.79966-05	\N
max_bytes_foto	1572864	bytes	Tamaño máximo de una foto del hallazgo (1,5 MB, igual que campo)	102400	3145728	2026-11-21 18:45:37.799668-05	\N
max_bytes_foto_acta_fisica	2621440	bytes	Tamaño máximo de una foto del acta física (2,5 MB: debe poder leerse el texto). PROPUESTA	102400	3145728	2026-11-21 18:45:37.799674-05	\N
vigencia_apertura_horas	12	horas	Horas que dura una apertura antes de caducar. PROPUESTA	1	72	2026-11-21 18:45:37.799687-05	\N
max_dias_acta_fisica_atras	30	días	Cuántos días atrás puede estar la fecha del acta física al registrar (no aplica a correcciones). PROPUESTA	0	365	2026-11-21 18:45:37.799694-05	\N
alerta_meses	5	meses	Meses desde la fecha del acta física para la alerta de antigüedad (art. 150 Ley 142 de 1994: por confirmar con jurídica)	1	36	2026-11-21 18:45:37.799703-05	\N
alerta_previa_dias	30	días	Días antes del límite en que la alerta pasa a «próxima». PROPUESTA, PENDIENTE de David	1	120	2026-11-21 18:45:37.799709-05	\N
distancia_sugerencia_m	15	m	Distancia para sugerir predios con contrato cercanos y para detectar actas cercanas (igual que duplicados de campo)	1	500	2026-11-21 18:45:37.799717-05	\N
url_lectura_segundos	60	segundos	Vigencia de la URL de lectura de una evidencia	10	600	2026-11-21 18:45:37.799725-05	\N
limite_aperturas_hora	6	registros	Máximo de aperturas por persona por hora (el supervisor lo multiplica). PROPUESTA	1	200	2026-11-21 18:45:37.799732-05	\N
limite_aperturas_dia	20	registros	Máximo de aperturas por persona por día (el supervisor lo multiplica). PROPUESTA	1	500	2026-11-21 18:45:37.799741-05	\N
multiplo_supervisor	5	veces	Veces que el supervisor supera los topes de aperturas. El administrador no tiene tope. PROPUESTA	1	100	2026-11-21 18:45:37.79983-05	\N
limite_precargas_dia	60	consultas	Máximo de consultas de contrato por persona por día (el contrato es enumerable). PROPUESTA	1	1000	2026-11-21 18:45:37.799872-05	\N
limite_precargas_falsas_dia	5	consultas	Máximo de consultas de contratos que NO existen por persona por día (patrón de enumeración). PROPUESTA	1	100	2026-11-21 18:45:37.799884-05	\N
limite_lecturas_minuto	30	lecturas	Máximo de evidencias que una persona de supervisión abre por minuto. PROPUESTA	1	600	2026-11-21 18:45:37.799895-05	\N
limite_mis_actas_minuto	20	consultas	Máximo de consultas de «mis actas» por persona por minuto (el administrador no tiene tope). PROPUESTA	1	600	2026-11-21 18:45:37.799904-05	\N
mis_actas_max_filas	50	filas	Filas que devuelve «mis actas» (las más recientes del propio operario). PROPUESTA	1	200	2026-11-21 18:45:37.799914-05	\N
zona_lat_min	10.35	grados	Zona de operación: latitud mínima (valores de campo, con margen). Fuera de la zona se guarda con marca; no se rechaza	-90	90	2026-11-21 18:45:37.799924-05	\N
zona_lat_max	10.56	grados	Zona de operación: latitud máxima	-90	90	2026-11-21 18:45:37.79993-05	\N
zona_lon_min	-73.36	grados	Zona de operación: longitud mínima	-180	180	2026-11-21 18:45:37.799937-05	\N
zona_lon_max	-73.18	grados	Zona de operación: longitud máxima	-180	180	2026-11-21 18:45:37.799976-05	\N
\.


--
-- Data for Name: tipos_foto; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.tipos_foto (id, codigo, nombre, orden, exigida_con_irregularidad, es_acta_fisica, activo, creado_en) FROM stdin;
1	fachada	Fachada o nomenclatura	10	t	f	t	2026-11-21 18:45:37.804156-05
2	medidor	Medidor y lectura	20	f	f	t	2026-11-21 18:45:37.804292-05
3	sellos	Sellos	30	f	f	t	2026-11-21 18:45:37.804299-05
4	hallazgo	Hallazgo	40	t	f	t	2026-11-21 18:45:37.804303-05
5	acciones	Acciones ejecutadas	50	f	f	t	2026-11-21 18:45:37.804308-05
6	otro	Otro	60	f	f	t	2026-11-21 18:45:37.804314-05
7	acta_fisica	Acta física firmada (páginas del papel)	90	f	t	t	2026-11-21 18:45:37.804319-05
\.


--
-- Data for Name: tipos_hallazgo; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.tipos_hallazgo (id, codigo, nombre, nota, orden, exige_texto, excluyente, habilita_accion_codigo, activo, creado_en) FROM stdin;
1	conexion_directa	Posible conexión directa a la red de distribución	Sin medidor o con bypass	10	f	f	\N	t	2026-11-21 18:45:37.802796-05
2	acometida_paralela	Posible acometida paralela clandestina	Derivación antes del medidor	20	f	f	\N	t	2026-11-21 18:45:37.802956-05
3	medidor_manipulado	Posible medidor manipulado o alterado en sus mecanismos internos	\N	30	f	f	\N	t	2026-11-21 18:45:37.802969-05
4	reconexion_no_autorizada	Posible reconexión no autorizada	Servicio suspendido o cortado; habilita corte o taponamiento	40	f	f	corte_taponamiento	t	2026-11-21 18:45:37.802977-05
5	sellos_alterados	Posible alteración de los sellos de seguridad de la Empresa	\N	50	f	f	\N	t	2026-11-21 18:45:37.802986-05
6	uso_diferente	Posible uso del servicio diferente al contratado	Ejemplo: residencial facturado como comercial	60	f	f	\N	t	2026-11-21 18:45:37.802993-05
7	otro	Otro	\N	90	t	f	\N	t	2026-11-21 18:45:37.803-05
8	sin_irregularidad	Sin irregularidad	No se combina con otros hallazgos; el caso se cierra como constancia	99	f	t	\N	t	2026-11-21 18:45:37.803006-05
\.


--
-- Data for Name: transiciones_caso; Type: TABLE DATA; Schema: acta; Owner: -
--

COPY acta.transiciones_caso (desde, hasta, activo) FROM stdin;
reportado	papel_recibido	t
reportado	en_revision	t
reportado	descartado	t
papel_recibido	en_revision	t
papel_recibido	descartado	t
en_revision	confirmado	t
en_revision	descartado	t
confirmado	en_gestion_posterior	t
en_gestion_posterior	cerrado	t
confirmado	cerrado	t
\.


--
-- Data for Name: v_cambio_medidor_dim; Type: TABLE DATA; Schema: bi; Owner: -
--

COPY bi.v_cambio_medidor_dim (periodo, periodo_ant, meses_intervalo, ciclo, uso, estrato, tipo_evento, banda_ant, metodo_act, contratos, contratos_pareados, m3_ant, m3_act, contratos_con_medidor_ant) FROM stdin;
\.


--
-- Data for Name: v_consumo_promedio_dim; Type: TABLE DATA; Schema: bi; Owner: -
--

COPY bi.v_consumo_promedio_dim (periodo, dimension, grupo, contratos, media_m3, mediana_m3, calculado_en) FROM stdin;
\.


--
-- Data for Name: v_submedicion_ciclo_dim; Type: TABLE DATA; Schema: bi; Owner: -
--

COPY bi.v_submedicion_ciclo_dim (periodo, ciclo, estrato, contratos, m3_consumo, m3_perdidos_bruta, contratos_vejez, m3_perdidos_atrib, tarifa_m3, contratos_bajo_ref, m3_exceso, max_m3, calculado_en) FROM stdin;
\.


--
-- Data for Name: v_submedicion_rango_dim; Type: TABLE DATA; Schema: bi; Owner: -
--

COPY bi.v_submedicion_rango_dim (periodo, ciclo, estrato, rango_m3, contratos, m3_consumo, contratos_bajo_ref, m3_perdidos_bruta, tarifa_m3, max_m3, calculado_en) FROM stdin;
\.


--
-- Data for Name: v_submedicion_ref_dim; Type: TABLE DATA; Schema: bi; Owner: -
--

COPY bi.v_submedicion_ref_dim (periodo, estrato, banda_antig, contratos_medidor, contratos, contratos_promedio, m3_consumo, ref_nuevos_media_m3, n_nuevos, media_vejez_m3, n_vejez, tarifa_m3, contratos_bajo_ref, m3_perdidos_bruta, m3_exceso, max_m3, calculado_en, contratos_cero, contratos_sobre_max) FROM stdin;
\.


--
-- Data for Name: ficha_contrato; Type: TABLE DATA; Schema: bi_interno; Owner: -
--

COPY bi_interno.ficha_contrato (contrato, periodo_ultimo, uso, estrato, ciclo, consumo_meses, cons_max, cons_min, cons_prom, meses_con_lectura, medidor_serial, medidor_fecha, medidor_fecha_estado, medidor_anios, cambio, submedicion, emd, ultimo_pago, pqr, facturas_vencidas, calculado_en) FROM stdin;
\.


--
-- Data for Name: ficha_contrato_estado; Type: TABLE DATA; Schema: bi_interno; Owner: -
--

COPY bi_interno.ficha_contrato_estado (id, firma, filas, calculado_en, duracion_ms) FROM stdin;
\.


--
-- Data for Name: actividades; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.actividades (codigo, nombre, activa, orden, formularios, autor, creado_en) FROM stdin;
suspension	Suspensión	t	1	{tipo:suspension}	migracion@geoportal	2026-11-21 18:45:37.985913-05
corte	Corte	t	2	{tipo:corte}	migracion@geoportal	2026-11-21 18:45:37.986088-05
reconexion	Reconexión	t	3	{tipo:reconexion_servicio,tipo:reinstalacion}	migracion@geoportal	2026-11-21 18:45:37.986095-05
lectura	Lectura	t	4	{}	migracion@geoportal	2026-11-21 18:45:37.986101-05
reparto	Reparto	t	5	{}	migracion@geoportal	2026-11-21 18:45:37.986105-05
revision_previa	Revisiones generales	t	6	{tipo:revision_previa}	migracion@geoportal	2026-11-21 18:45:37.98611-05
revision_pqr	Revisión PQR	t	7	{tipo:revision_pqr}	migracion@geoportal	2026-11-21 18:45:37.986116-05
instalacion_medidor	Instalación o cambio de medidor	t	8	{tipo:instalacion_medidor}	migracion@geoportal	2026-11-21 18:45:37.986123-05
instalacion_acometida	Instalación de acometida	t	9	{tipo:instalacion_acometida}	migracion@geoportal	2026-11-21 18:45:37.986132-05
posible_perdida	Posible pérdida (acta)	t	10	{acta}	migracion@geoportal	2026-11-21 18:45:37.98614-05
\.


--
-- Data for Name: areas_comercial; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.areas_comercial (codigo, nombre, activa, orden, autor, creado_en) FROM stdin;
facturacion	Facturación	t	1	migracion@geoportal	2026-11-21 18:45:37.985673-05
cartera_scrr	Cartera / SCRR	t	2	migracion@geoportal	2026-11-21 18:45:37.985862-05
perdidas	Pérdidas	t	3	migracion@geoportal	2026-11-21 18:45:37.985873-05
pqr_atencion	PQR / Atención al usuario	t	4	migracion@geoportal	2026-11-21 18:45:37.985877-05
\.


--
-- Data for Name: catalogo_eventos; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.catalogo_eventos (id, catalogo, codigo, tipo_evento, nombre, motivo, autor, creado_en) FROM stdin;
1	area	facturacion	crear	Facturación	\N	migracion@geoportal	2026-11-21 18:45:37.986651-05
2	area	cartera_scrr	crear	Cartera / SCRR	\N	migracion@geoportal	2026-11-21 18:45:37.986819-05
3	area	perdidas	crear	Pérdidas	\N	migracion@geoportal	2026-11-21 18:45:37.986826-05
4	area	pqr_atencion	crear	PQR / Atención al usuario	\N	migracion@geoportal	2026-11-21 18:45:37.98683-05
5	actividad	suspension	crear	Suspensión	\N	migracion@geoportal	2026-11-21 18:45:37.986836-05
6	actividad	corte	crear	Corte	\N	migracion@geoportal	2026-11-21 18:45:37.98684-05
7	actividad	reconexion	crear	Reconexión	\N	migracion@geoportal	2026-11-21 18:45:37.986844-05
8	actividad	lectura	crear	Lectura	\N	migracion@geoportal	2026-11-21 18:45:37.986848-05
9	actividad	reparto	crear	Reparto	\N	migracion@geoportal	2026-11-21 18:45:37.986851-05
10	actividad	revision_previa	crear	Revisiones generales	\N	migracion@geoportal	2026-11-21 18:45:37.986855-05
11	actividad	revision_pqr	crear	Revisión PQR	\N	migracion@geoportal	2026-11-21 18:45:37.98686-05
12	actividad	instalacion_medidor	crear	Instalación o cambio de medidor	\N	migracion@geoportal	2026-11-21 18:45:37.986865-05
13	actividad	instalacion_acometida	crear	Instalación de acometida	\N	migracion@geoportal	2026-11-21 18:45:37.98687-05
14	actividad	posible_perdida	crear	Posible pérdida (acta)	\N	migracion@geoportal	2026-11-21 18:45:37.986876-05
\.


--
-- Data for Name: causales; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.causales (id, codigo, nombre, general, orden, activo, creado_en) FROM stdin;
1	no_hay_acceso	No hay acceso al predio	t	1	t	2026-11-21 18:45:37.733505-05
2	usuario_impide	El usuario impide la actividad	t	2	t	2026-11-21 18:45:37.73371-05
3	predio_no_ubicado	Predio no ubicado	t	3	t	2026-11-21 18:45:37.733718-05
4	nadie_atiende	No hay quien atienda	t	4	t	2026-11-21 18:45:37.733725-05
5	riesgo_seguridad	Riesgo para la seguridad del personal	t	5	t	2026-11-21 18:45:37.73373-05
6	medidor_no_accesible	Medidor o caja no accesible	t	6	t	2026-11-21 18:45:37.733736-05
7	ya_pago	El usuario presenta soporte de pago o acuerdo	f	7	t	2026-11-21 18:45:37.733743-05
\.


--
-- Data for Name: causales_tipos; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.causales_tipos (causal_id, tipo_id, activo, creado_en) FROM stdin;
7	19	t	2026-11-21 18:45:37.733817-05
7	20	t	2026-11-21 18:45:37.73393-05
\.


--
-- Data for Name: consecutivos; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.consecutivos (tipo_id, ultimo, actualizado_en) FROM stdin;
\.


--
-- Data for Name: consultas_analisis; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.consultas_analisis (id, autor, contrato, existe, consultado_en, ip) FROM stdin;
\.


--
-- Data for Name: consultas_cercania; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.consultas_cercania (id, autor, lat_red, lon_red, resultados, cobrada, consultado_en, ip) FROM stdin;
\.


--
-- Data for Name: cuadrilla_eventos; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.cuadrilla_eventos (id, cuadrilla_id, tipo_evento, valor, motivo, autor, creado_en) FROM stdin;
\.


--
-- Data for Name: cuadrillas; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.cuadrillas (id, nombre, activa, autor, creado_en) FROM stdin;
\.


--
-- Data for Name: estados_reporte; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.estados_reporte (codigo, nombre, orden, activo, inicial, exige_motivo, cambio_manual, creado_en) FROM stdin;
reportado	Reportado	1	t	t	f	f	2026-11-21 18:45:37.688288-05
en_revision	En revisión	2	t	f	f	t	2026-11-21 18:45:37.688665-05
con_acta	Con acta	3	t	f	f	f	2026-11-21 18:45:37.688675-05
atendido	Atendido	4	t	f	f	t	2026-11-21 18:45:37.688684-05
descartado	Descartado	5	t	f	t	t	2026-11-21 18:45:37.688692-05
duplicado	Duplicado	6	t	f	f	f	2026-11-21 18:45:37.688697-05
\.


--
-- Data for Name: grupos_reporte; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.grupos_reporte (id, codigo, nombre, orden, activo, creado_en) FROM stdin;
1	comercial_perdidas	Comercial y pérdidas	1	t	2026-11-21 18:45:37.68878-05
2	red_acueducto	Red de acueducto	2	t	2026-11-21 18:45:37.689627-05
3	alcantarillado	Alcantarillado	3	t	2026-11-21 18:45:37.689641-05
4	terceros	Terceros	4	t	2026-11-21 18:45:37.689649-05
5	otros	Otros	9	t	2026-11-21 18:45:37.689656-05
6	cartera	Gestión de cartera	5	f	2026-11-21 18:45:37.728466-05
7	perdidas_formatos	Pérdidas (instalaciones)	6	f	2026-11-21 18:45:37.728553-05
8	pqr	PQR	7	f	2026-11-21 18:45:37.728565-05
9	facturacion	Facturación	8	t	2026-11-21 18:45:37.825852-05
\.


--
-- Data for Name: parametros; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.parametros (clave, valor, unidad, descripcion, minimo, maximo, actualizado_en, actualizado_por) FROM stdin;
distancia_duplicados_m	15	m	Distancia máxima entre reportes del mismo tipo para sugerirlos como posibles duplicados (PROPUESTA)	1	1000	2026-11-21 18:45:37.68674-05	\N
max_fotos	2	fotos	Máximo de fotos por reporte	1	10	2026-11-21 18:45:37.688175-05	\N
max_bytes_foto	1572864	bytes	Tamaño máximo de cada foto ya reducida (1,5 MB). El bucket tiene un tope duro de 2 MB	102400	2097152	2026-11-21 18:45:37.688193-05	\N
zona_lat_min	10.35	grados	Límite sur de la zona de operación; fuera de la caja el reporte SE GUARDA con la marca fuera_de_zona (PROPUESTA: extensión de los predios + ~5 km)	-90	90	2026-11-21 18:45:37.688205-05	\N
zona_lat_max	10.56	grados	Límite norte de la zona de operación (PROPUESTA)	-90	90	2026-11-21 18:45:37.688215-05	\N
zona_lon_min	-73.36	grados	Límite occidental de la zona de operación (PROPUESTA)	-180	180	2026-11-21 18:45:37.688224-05	\N
zona_lon_max	-73.18	grados	Límite oriental de la zona de operación (PROPUESTA)	-180	180	2026-11-21 18:45:37.688229-05	\N
limite_reportes_ventana	20	reportes	Máximo de reportes que una persona puede crear dentro de la ventana (y de preparaciones abandonadas). PROPUESTA	1	1000	2026-11-21 18:45:37.694246-05	\N
limite_contratos_ventana	10	reportes	Máximo de reportes CON número de contrato por persona dentro de la ventana: tope contra la enumeración de contratos. PROPUESTA	1	1000	2026-11-21 18:45:37.694282-05	\N
multiplo_supervisor	5	veces	Veces que el supervisor puede superar el tope de reportes (el de contratos no se multiplica). El administrador no tiene tope. PROPUESTA	1	100	2026-11-21 18:45:37.694291-05	\N
ventana_limite_minutos	60	minutos	Ancho de la ventana móvil de los topes (por omisión, una hora). PROPUESTA	5	1440	2026-11-21 18:45:37.694298-05	\N
limite_contratos_falsos_dia	5	reportes	Máximo de reportes con número de contrato NO verificado (que no existe en la base comercial) por persona en las últimas 24 horas; al alcanzarlo, no puede enviar reportes con número de contrato hasta que pase la ventana (sin número, sí). El administrador no tiene tope; el supervisor tampoco tiene multiplicador. PROPUESTA	1	100	2026-11-21 18:45:37.694305-05	\N
alerta_base_pct	80	por ciento	Umbral de alerta de capacidad: la verificación de solo lectura marca ALERTA si la base (y el Storage) superan este porcentaje del plan	50	99	2026-11-21 18:45:37.722719-05	\N
max_descripcion	1000	caracteres	Máximo de caracteres de la descripción de un reporte (PROPUESTA: 1.000, que es lo que admite la tabla; solo puede bajar)	100	1000	2026-11-21 18:45:37.813184-05	\N
max_horas_inicio	12	h	Horas máximas entre la apertura del formulario (hora del celular) y el registro; más antiguo se rechaza	1	72	2026-11-21 18:45:37.897774-05	\N
limite_cercania_dia	30	búsquedas	Análisis de contrato: búsquedas «Contratos cerca de mí» que una persona puede hacer en 24 horas (el administrador no tiene límite)	1	200	2026-11-21 18:45:37.937624-05	\N
\.


--
-- Data for Name: personal_eventos; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.personal_eventos (id, persona, tipo_evento, formulario, cargo, motivo, autor, creado_en, valor) FROM stdin;
\.


--
-- Data for Name: preparaciones; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.preparaciones (reporte_id, autor, creado_en) FROM stdin;
\.


--
-- Data for Name: reporte_datos_sensibles; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.reporte_datos_sensibles (reporte_id, datos, registrado_en) FROM stdin;
\.


--
-- Data for Name: reporte_eventos; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.reporte_eventos (id, reporte_id, tipo_evento, estado_nuevo, reporte_original_id, acta_id, motivo, autor, creado_en) FROM stdin;
\.


--
-- Data for Name: reporte_fotos; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.reporte_fotos (id, reporte_id, orden, ruta_storage, tamano_bytes, tipo_mime, registrada_en, etiqueta) FROM stdin;
\.


--
-- Data for Name: reportes; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.reportes (id, seq, tipo_id, subtipo_id, descripcion, contrato, contrato_verificado, lat, lon, precision_m, riesgo_inmediato, origen, fuera_de_zona, autor, registrado_en, datos, resultado, causal_id, consecutivo_num, consecutivo, orden_trabajo_id, inicio_en, inicio_origen, area) FROM stdin;
\.


--
-- Data for Name: subtipos_reporte; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.subtipos_reporte (id, tipo_id, codigo, nombre, orden, activo, creado_en) FROM stdin;
1	3	medidor_ausente	Medidor ausente	4	t	2026-11-21 18:45:37.690998-05
2	3	caja_sin_tapa	Caja sin tapa	3	t	2026-11-21 18:45:37.691364-05
3	3	medidor_no_visible	Medidor no visible	2	t	2026-11-21 18:45:37.691376-05
4	3	medidor_vandalizado	Medidor vandalizado o con luneta rayada	1	t	2026-11-21 18:45:37.691384-05
5	4	doble_acometida	Doble acometida	3	t	2026-11-21 18:45:37.691393-05
6	4	acometida_paralela	Acometida paralela	2	t	2026-11-21 18:45:37.691399-05
7	4	bypass	Bypass	1	t	2026-11-21 18:45:37.691405-05
8	6	ampliacion	Ampliación	2	t	2026-11-21 18:45:37.691411-05
9	6	construccion_nueva	Construcción nueva	1	t	2026-11-21 18:45:37.691415-05
10	9	sanitario_a_lluvias	Aguas sanitarias a alcantarillado de lluvias	2	t	2026-11-21 18:45:37.691422-05
11	9	lluvias_a_sanitario	Aguas lluvias a sanitario	1	t	2026-11-21 18:45:37.691429-05
12	16	drastica	Reconexión drástica	2	t	2026-11-21 18:45:37.729585-05
13	16	sencilla	Reconexión sencilla	1	t	2026-11-21 18:45:37.72966-05
14	19	drastico	Corte drástico (en red o taponamiento)	2	t	2026-11-21 18:45:37.729668-05
15	19	sencillo	Corte sencillo	1	t	2026-11-21 18:45:37.729673-05
\.


--
-- Data for Name: tipo_campos; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.tipo_campos (id, tipo_id, codigo, nombre, tipo_dato, obligatorio, opciones, minimo, maximo, unidad, ayuda, sensible, orden, activo, creado_en, seccion, visible_si) FROM stdin;
1	22	hallazgo	Hallazgo	opcion	t	[{"codigo": "ubicado", "nombre": "Predio ubicado"}, {"codigo": "no_existe", "nombre": "No existe"}, {"codigo": "demolido", "nombre": "Demolido"}, {"codigo": "lote", "nombre": "Es un lote"}]	\N	\N	\N	\N	f	1	t	2026-11-21 18:45:37.730985-05	\N	\N
2	22	direccion_encontrada	Dirección encontrada en terreno	texto	f	\N	\N	120	\N	\N	f	2	t	2026-11-21 18:45:37.731544-05	\N	\N
3	21	diametro	Diámetro de la acometida	opcion	t	[{"codigo": "media", "nombre": "1/2 pulgada"}, {"codigo": "tres_cuartos", "nombre": "3/4 pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "mayor", "nombre": "Mayor de 1 pulgada"}, {"codigo": "no_determinado", "nombre": "No se pudo determinar"}]	\N	\N	\N	\N	f	1	t	2026-11-21 18:45:37.731574-05	\N	\N
4	21	material	Material	opcion	t	[{"codigo": "pvc", "nombre": "PVC"}, {"codigo": "polietileno", "nombre": "Polietileno"}, {"codigo": "cobre", "nombre": "Cobre"}, {"codigo": "galvanizado", "nombre": "Hierro galvanizado"}, {"codigo": "otro", "nombre": "Otro"}, {"codigo": "no_determinado", "nombre": "No se pudo determinar"}]	\N	\N	\N	\N	f	2	t	2026-11-21 18:45:37.731611-05	\N	\N
5	21	estado_acometida	Estado de la acometida	opcion	t	[{"codigo": "bueno", "nombre": "Bueno"}, {"codigo": "regular", "nombre": "Regular"}, {"codigo": "malo", "nombre": "Malo"}]	\N	\N	\N	\N	f	3	t	2026-11-21 18:45:37.731651-05	\N	\N
6	21	tiene_medidor	¿Tiene medidor?	si_no	f	\N	\N	\N	\N	\N	f	4	t	2026-11-21 18:45:37.731676-05	\N	\N
7	21	profundidad	Profundidad de la conexión	entero	f	\N	0	500	cm	\N	f	5	t	2026-11-21 18:45:37.73169-05	\N	\N
8	20	lectura	Lectura del medidor	entero	t	\N	0	9999999	m³	\N	f	1	t	2026-11-21 18:45:37.731704-05	\N	\N
9	20	serial_medidor	Serial del medidor	texto	t	\N	\N	30	\N	\N	f	2	t	2026-11-21 18:45:37.731716-05	\N	\N
10	20	numero_sello	Número del sello instalado	texto	t	\N	\N	30	\N	\N	f	3	t	2026-11-21 18:45:37.731729-05	\N	\N
11	19	forma_corte	Forma del corte	opcion	f	[{"codigo": "en_red", "nombre": "En red"}, {"codigo": "taponamiento", "nombre": "Taponamiento"}, {"codigo": "retiro_acometida", "nombre": "Retiro de la acometida"}]	\N	\N	\N	\N	f	1	t	2026-11-21 18:45:37.731743-05	\N	\N
12	19	materiales	Materiales usados	texto	f	\N	\N	300	\N	\N	f	2	t	2026-11-21 18:45:37.731767-05	\N	\N
13	19	reposicion_pavimento	¿Hubo reposición de pavimento?	si_no	t	\N	\N	\N	\N	\N	f	3	t	2026-11-21 18:45:37.731779-05	\N	\N
14	18	estado_servicio	Estado del servicio	opcion	t	[{"codigo": "sigue_interrumpido", "nombre": "Sigue interrumpido"}, {"codigo": "reconexion_no_autorizada", "nombre": "Reconexión no autorizada"}]	\N	\N	\N	\N	f	1	t	2026-11-21 18:45:37.731793-05	\N	\N
15	17	lectura_inicial	Lectura inicial	entero	t	\N	0	9999999	m³	\N	f	1	t	2026-11-21 18:45:37.731817-05	\N	\N
16	17	referencia_soporte	Referencia del soporte de pago o del acuerdo (solo el número)	texto	f	\N	\N	40	\N	\N	f	2	t	2026-11-21 18:45:37.731829-05	\N	\N
17	16	lectura_inicial	Lectura inicial	entero	t	\N	0	9999999	m³	\N	f	1	t	2026-11-21 18:45:37.731843-05	\N	\N
18	16	referencia_soporte	Referencia del soporte de pago o del acuerdo (solo el número)	texto	f	\N	\N	40	\N	\N	f	2	t	2026-11-21 18:45:37.731855-05	\N	\N
19	15	serial_retirado	Serial del medidor retirado	texto	t	\N	\N	30	\N	\N	f	1	t	2026-11-21 18:45:37.731868-05	\N	\N
20	15	lectura_retirado	Lectura del medidor retirado	entero	t	\N	0	9999999	m³	\N	f	2	t	2026-11-21 18:45:37.73188-05	\N	\N
21	15	serial_nuevo	Serial del medidor nuevo	texto	t	\N	\N	30	\N	\N	f	3	t	2026-11-21 18:45:37.731892-05	\N	\N
22	15	lectura_inicial	Lectura inicial del medidor nuevo	entero	t	\N	0	9999999	m³	\N	f	4	t	2026-11-21 18:45:37.731905-05	\N	\N
31	15	despeje_caja	Se hizo despeje de caja o adecuación del sitio	si_no	f	\N	\N	\N	\N	\N	f	90	t	2026-11-21 18:45:37.732344-05	\N	\N
32	15	despeje_observacion	Qué se hizo en la caja (opcional, corto)	texto	f	\N	\N	120	\N	\N	f	91	t	2026-11-21 18:45:37.732486-05	\N	\N
33	15	visita_concertada	Fue visita concertada o con acompañamiento	si_no	f	\N	\N	\N	\N	\N	f	92	t	2026-11-21 18:45:37.732503-05	\N	\N
34	15	cita_acordada	Día y hora acordados con el usuario (visita concertada)	dia_hora	f	\N	\N	\N	\N	\N	f	93	t	2026-11-21 18:45:37.732516-05	\N	\N
35	15	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	t	2026-11-21 18:45:37.732533-05	\N	\N
36	16	despeje_caja	Se hizo despeje de caja o adecuación del sitio	si_no	f	\N	\N	\N	\N	\N	f	90	t	2026-11-21 18:45:37.732547-05	\N	\N
37	16	despeje_observacion	Qué se hizo en la caja (opcional, corto)	texto	f	\N	\N	120	\N	\N	f	91	t	2026-11-21 18:45:37.73256-05	\N	\N
38	16	visita_concertada	Fue visita concertada o con acompañamiento	si_no	f	\N	\N	\N	\N	\N	f	92	t	2026-11-21 18:45:37.732574-05	\N	\N
39	16	cita_acordada	Día y hora acordados con el usuario (visita concertada)	dia_hora	f	\N	\N	\N	\N	\N	f	93	t	2026-11-21 18:45:37.732586-05	\N	\N
40	16	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	t	2026-11-21 18:45:37.732599-05	\N	\N
41	17	despeje_caja	Se hizo despeje de caja o adecuación del sitio	si_no	f	\N	\N	\N	\N	\N	f	90	t	2026-11-21 18:45:37.732612-05	\N	\N
42	17	despeje_observacion	Qué se hizo en la caja (opcional, corto)	texto	f	\N	\N	120	\N	\N	f	91	t	2026-11-21 18:45:37.732624-05	\N	\N
43	17	visita_concertada	Fue visita concertada o con acompañamiento	si_no	f	\N	\N	\N	\N	\N	f	92	t	2026-11-21 18:45:37.732638-05	\N	\N
44	17	cita_acordada	Día y hora acordados con el usuario (visita concertada)	dia_hora	f	\N	\N	\N	\N	\N	f	93	t	2026-11-21 18:45:37.73265-05	\N	\N
45	17	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	t	2026-11-21 18:45:37.732662-05	\N	\N
46	18	despeje_caja	Se hizo despeje de caja o adecuación del sitio	si_no	f	\N	\N	\N	\N	\N	f	90	t	2026-11-21 18:45:37.732675-05	\N	\N
47	18	despeje_observacion	Qué se hizo en la caja (opcional, corto)	texto	f	\N	\N	120	\N	\N	f	91	t	2026-11-21 18:45:37.732686-05	\N	\N
48	18	visita_concertada	Fue visita concertada o con acompañamiento	si_no	f	\N	\N	\N	\N	\N	f	92	t	2026-11-21 18:45:37.732699-05	\N	\N
49	18	cita_acordada	Día y hora acordados con el usuario (visita concertada)	dia_hora	f	\N	\N	\N	\N	\N	f	93	t	2026-11-21 18:45:37.732712-05	\N	\N
50	18	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	t	2026-11-21 18:45:37.732854-05	\N	\N
51	19	despeje_caja	Se hizo despeje de caja o adecuación del sitio	si_no	f	\N	\N	\N	\N	\N	f	90	t	2026-11-21 18:45:37.732869-05	\N	\N
52	19	despeje_observacion	Qué se hizo en la caja (opcional, corto)	texto	f	\N	\N	120	\N	\N	f	91	t	2026-11-21 18:45:37.732881-05	\N	\N
53	19	visita_concertada	Fue visita concertada o con acompañamiento	si_no	f	\N	\N	\N	\N	\N	f	92	t	2026-11-21 18:45:37.732895-05	\N	\N
54	19	cita_acordada	Día y hora acordados con el usuario (visita concertada)	dia_hora	f	\N	\N	\N	\N	\N	f	93	t	2026-11-21 18:45:37.732908-05	\N	\N
55	19	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	t	2026-11-21 18:45:37.73292-05	\N	\N
56	20	despeje_caja	Se hizo despeje de caja o adecuación del sitio	si_no	f	\N	\N	\N	\N	\N	f	90	t	2026-11-21 18:45:37.732932-05	\N	\N
57	20	despeje_observacion	Qué se hizo en la caja (opcional, corto)	texto	f	\N	\N	120	\N	\N	f	91	t	2026-11-21 18:45:37.732944-05	\N	\N
58	20	visita_concertada	Fue visita concertada o con acompañamiento	si_no	f	\N	\N	\N	\N	\N	f	92	t	2026-11-21 18:45:37.732958-05	\N	\N
59	20	cita_acordada	Día y hora acordados con el usuario (visita concertada)	dia_hora	f	\N	\N	\N	\N	\N	f	93	t	2026-11-21 18:45:37.73297-05	\N	\N
60	20	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	t	2026-11-21 18:45:37.732982-05	\N	\N
61	21	despeje_caja	Se hizo despeje de caja o adecuación del sitio	si_no	f	\N	\N	\N	\N	\N	f	90	t	2026-11-21 18:45:37.732995-05	\N	\N
62	21	despeje_observacion	Qué se hizo en la caja (opcional, corto)	texto	f	\N	\N	120	\N	\N	f	91	t	2026-11-21 18:45:37.733007-05	\N	\N
63	21	visita_concertada	Fue visita concertada o con acompañamiento	si_no	f	\N	\N	\N	\N	\N	f	92	t	2026-11-21 18:45:37.73302-05	\N	\N
64	21	cita_acordada	Día y hora acordados con el usuario (visita concertada)	dia_hora	f	\N	\N	\N	\N	\N	f	93	t	2026-11-21 18:45:37.733032-05	\N	\N
65	21	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	t	2026-11-21 18:45:37.733044-05	\N	\N
66	22	despeje_caja	Se hizo despeje de caja o adecuación del sitio	si_no	f	\N	\N	\N	\N	\N	f	90	t	2026-11-21 18:45:37.733058-05	\N	\N
67	22	despeje_observacion	Qué se hizo en la caja (opcional, corto)	texto	f	\N	\N	120	\N	\N	f	91	t	2026-11-21 18:45:37.73307-05	\N	\N
68	22	visita_concertada	Fue visita concertada o con acompañamiento	si_no	f	\N	\N	\N	\N	\N	f	92	t	2026-11-21 18:45:37.733082-05	\N	\N
69	22	cita_acordada	Día y hora acordados con el usuario (visita concertada)	dia_hora	f	\N	\N	\N	\N	\N	f	93	t	2026-11-21 18:45:37.733095-05	\N	\N
70	22	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	t	2026-11-21 18:45:37.733107-05	\N	\N
29	25	numero_pqr	Número de la PQR	texto	t	\N	\N	30	\N	\N	f	1	f	2026-11-21 18:45:37.73202-05	\N	\N
30	25	hallazgo_revision	Qué se encontró	texto	t	\N	\N	300	\N	\N	f	2	f	2026-11-21 18:45:37.732031-05	\N	\N
73	25	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	f	2026-11-21 18:45:37.733424-05	\N	\N
23	24	serial_nuevo	Serial del medidor instalado	texto	t	\N	\N	30	\N	\N	f	1	f	2026-11-21 18:45:37.731919-05	\N	\N
24	24	lectura_inicial	Lectura inicial	entero	t	\N	0	9999999	m³	\N	f	2	f	2026-11-21 18:45:37.73193-05	\N	\N
25	24	accesorios	Accesorios instalados	texto	f	\N	\N	300	\N	\N	f	3	f	2026-11-21 18:45:37.731942-05	\N	\N
72	24	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	f	2026-11-21 18:45:37.733412-05	\N	\N
26	23	diametro	Diámetro de la acometida	opcion	t	[{"codigo": "media", "nombre": "1/2 pulgada"}, {"codigo": "tres_cuartos", "nombre": "3/4 pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "mayor", "nombre": "Mayor de 1 pulgada"}]	\N	\N	\N	\N	f	1	f	2026-11-21 18:45:37.731956-05	\N	\N
27	23	material	Material	opcion	t	[{"codigo": "pvc", "nombre": "PVC"}, {"codigo": "polietileno", "nombre": "Polietileno"}, {"codigo": "cobre", "nombre": "Cobre"}, {"codigo": "otro", "nombre": "Otro"}]	\N	\N	\N	\N	f	2	f	2026-11-21 18:45:37.731984-05	\N	\N
28	23	longitud	Longitud instalada	decimal	f	\N	0	500	m	\N	f	3	f	2026-11-21 18:45:37.732008-05	\N	\N
71	23	observacion	Observación (no escriba nombres, cédulas ni teléfonos)	texto	f	\N	\N	300	\N	\N	f	99	f	2026-11-21 18:45:37.733287-05	\N	\N
74	25	serie_acta	Serie del acta física	texto	t	\N	\N	20	\N	La serie impresa en el papel.	f	101	t	2026-11-21 18:45:37.828691-05	1. Datos básicos	\N
75	24	serie_acta	Serie del acta física	texto	t	\N	\N	20	\N	La serie impresa en el papel.	f	101	t	2026-11-21 18:45:37.828867-05	1. Datos básicos	\N
76	23	serie_acta	Serie del acta física	texto	t	\N	\N	20	\N	La serie impresa en el papel.	f	101	t	2026-11-21 18:45:37.828884-05	1. Datos básicos	\N
77	26	serie_acta	Serie del acta física	texto	t	\N	\N	20	\N	La serie impresa en el papel.	f	101	t	2026-11-21 18:45:37.828898-05	1. Datos básicos	\N
78	25	orden_servicio	Orden de servicio	texto	t	\N	\N	20	\N	\N	f	102	t	2026-11-21 18:45:37.828912-05	1. Datos básicos	\N
79	24	orden_servicio	Orden de servicio	texto	t	\N	\N	20	\N	\N	f	102	t	2026-11-21 18:45:37.828926-05	1. Datos básicos	\N
80	23	orden_servicio	Orden de servicio	texto	t	\N	\N	20	\N	\N	f	102	t	2026-11-21 18:45:37.82894-05	1. Datos básicos	\N
81	26	orden_servicio	Orden de servicio	texto	t	\N	\N	20	\N	\N	f	102	t	2026-11-21 18:45:37.828953-05	1. Datos básicos	\N
82	25	tipo_orden	Tipo de orden	texto	f	\N	\N	40	\N	\N	f	103	t	2026-11-21 18:45:37.828966-05	1. Datos básicos	\N
83	24	tipo_orden	Tipo de orden	texto	f	\N	\N	40	\N	\N	f	103	t	2026-11-21 18:45:37.828978-05	1. Datos básicos	\N
84	23	tipo_orden	Tipo de orden	texto	f	\N	\N	40	\N	\N	f	103	t	2026-11-21 18:45:37.82899-05	1. Datos básicos	\N
85	26	tipo_orden	Tipo de orden	texto	f	\N	\N	40	\N	\N	f	103	t	2026-11-21 18:45:37.829002-05	1. Datos básicos	\N
86	25	contratista	Contratista	texto	f	\N	\N	60	\N	\N	f	104	t	2026-11-21 18:45:37.829015-05	1. Datos básicos	\N
87	24	contratista	Contratista	texto	f	\N	\N	60	\N	\N	f	104	t	2026-11-21 18:45:37.829027-05	1. Datos básicos	\N
88	23	contratista	Contratista	texto	f	\N	\N	60	\N	\N	f	104	t	2026-11-21 18:45:37.82904-05	1. Datos básicos	\N
89	26	contratista	Contratista	texto	f	\N	\N	60	\N	\N	f	104	t	2026-11-21 18:45:37.829052-05	1. Datos básicos	\N
241	26	fuga_imperceptible	¿Hay fugas imperceptibles?	si_no	f	\N	\N	\N	\N	\N	f	509	t	2026-11-21 18:45:37.832467-05	5. Instalaciones internas	\N
90	25	tipo_servicio	Tipo de servicio	opcion	t	[{"codigo": "residencial", "nombre": "Residencial"}, {"codigo": "comercial", "nombre": "Comercial"}, {"codigo": "industrial", "nombre": "Industrial"}, {"codigo": "oficial", "nombre": "Oficial"}]	\N	\N	\N	\N	f	105	t	2026-11-21 18:45:37.829069-05	1. Datos básicos	\N
91	24	tipo_servicio	Tipo de servicio	opcion	t	[{"codigo": "residencial", "nombre": "Residencial"}, {"codigo": "comercial", "nombre": "Comercial"}, {"codigo": "industrial", "nombre": "Industrial"}, {"codigo": "oficial", "nombre": "Oficial"}]	\N	\N	\N	\N	f	105	t	2026-11-21 18:45:37.829149-05	1. Datos básicos	\N
92	23	tipo_servicio	Tipo de servicio	opcion	t	[{"codigo": "residencial", "nombre": "Residencial"}, {"codigo": "comercial", "nombre": "Comercial"}, {"codigo": "industrial", "nombre": "Industrial"}, {"codigo": "oficial", "nombre": "Oficial"}]	\N	\N	\N	\N	f	105	t	2026-11-21 18:45:37.829185-05	1. Datos básicos	\N
93	26	tipo_servicio	Tipo de servicio	opcion	t	[{"codigo": "residencial", "nombre": "Residencial"}, {"codigo": "comercial", "nombre": "Comercial"}, {"codigo": "industrial", "nombre": "Industrial"}, {"codigo": "oficial", "nombre": "Oficial"}]	\N	\N	\N	\N	f	105	t	2026-11-21 18:45:37.829215-05	1. Datos básicos	\N
94	25	hora_inicio	Hora de inicio	dia_hora	t	\N	\N	\N	\N	Día y hora.	f	106	t	2026-11-21 18:45:37.829242-05	1. Datos básicos	\N
95	24	hora_inicio	Hora de inicio	dia_hora	t	\N	\N	\N	\N	Día y hora.	f	106	t	2026-11-21 18:45:37.829255-05	1. Datos básicos	\N
96	23	hora_inicio	Hora de inicio	dia_hora	t	\N	\N	\N	\N	Día y hora.	f	106	t	2026-11-21 18:45:37.829268-05	1. Datos básicos	\N
97	26	hora_inicio	Hora de inicio	dia_hora	t	\N	\N	\N	\N	Día y hora.	f	106	t	2026-11-21 18:45:37.829281-05	1. Datos básicos	\N
98	25	hora_final	Hora final	dia_hora	t	\N	\N	\N	\N	Día y hora.	f	107	t	2026-11-21 18:45:37.829294-05	1. Datos básicos	\N
99	24	hora_final	Hora final	dia_hora	t	\N	\N	\N	\N	Día y hora.	f	107	t	2026-11-21 18:45:37.829307-05	1. Datos básicos	\N
100	23	hora_final	Hora final	dia_hora	t	\N	\N	\N	\N	Día y hora.	f	107	t	2026-11-21 18:45:37.82932-05	1. Datos básicos	\N
101	26	hora_final	Hora final	dia_hora	t	\N	\N	\N	\N	Día y hora.	f	107	t	2026-11-21 18:45:37.829333-05	1. Datos básicos	\N
102	25	habitantes	Habitantes del predio	entero	f	\N	0	99	\N	\N	f	108	t	2026-11-21 18:45:37.829351-05	1. Datos básicos	\N
103	24	habitantes	Habitantes del predio	entero	f	\N	0	99	\N	\N	f	108	t	2026-11-21 18:45:37.829365-05	1. Datos básicos	\N
104	23	habitantes	Habitantes del predio	entero	f	\N	0	99	\N	\N	f	108	t	2026-11-21 18:45:37.829377-05	1. Datos básicos	\N
105	26	habitantes	Habitantes del predio	entero	f	\N	0	99	\N	\N	f	108	t	2026-11-21 18:45:37.82939-05	1. Datos básicos	\N
106	25	acompanado	¿El usuario hizo uso del derecho a estar acompañado de un técnico o testigo?	si_no	f	\N	\N	\N	\N	\N	f	109	t	2026-11-21 18:45:37.829403-05	1. Datos básicos	\N
107	24	acompanado	¿El usuario hizo uso del derecho a estar acompañado de un técnico o testigo?	si_no	f	\N	\N	\N	\N	\N	f	109	t	2026-11-21 18:45:37.829416-05	1. Datos básicos	\N
108	23	acompanado	¿El usuario hizo uso del derecho a estar acompañado de un técnico o testigo?	si_no	f	\N	\N	\N	\N	\N	f	109	t	2026-11-21 18:45:37.829428-05	1. Datos básicos	\N
109	26	acompanado	¿El usuario hizo uso del derecho a estar acompañado de un técnico o testigo?	si_no	f	\N	\N	\N	\N	\N	f	109	t	2026-11-21 18:45:37.829441-05	1. Datos básicos	\N
110	25	me_lectura	Medidor encontrado · Lectura (enteros y decimales del registro)	decimal	f	\N	0	99999999	m³	\N	f	201	t	2026-11-21 18:45:37.829453-05	2. Medidor encontrado	\N
112	23	me_lectura	Medidor encontrado · Lectura (enteros y decimales del registro)	decimal	f	\N	0	99999999	m³	\N	f	201	t	2026-11-21 18:45:37.829481-05	2. Medidor encontrado	\N
113	26	me_lectura	Medidor encontrado · Lectura (enteros y decimales del registro)	decimal	f	\N	0	99999999	m³	\N	f	201	t	2026-11-21 18:45:37.829494-05	2. Medidor encontrado	\N
114	25	me_marca	Medidor encontrado · Marca	texto	f	\N	\N	30	\N	\N	f	202	t	2026-11-21 18:45:37.829507-05	2. Medidor encontrado	\N
116	23	me_marca	Medidor encontrado · Marca	texto	f	\N	\N	30	\N	\N	f	202	t	2026-11-21 18:45:37.829533-05	2. Medidor encontrado	\N
117	26	me_marca	Medidor encontrado · Marca	texto	f	\N	\N	30	\N	\N	f	202	t	2026-11-21 18:45:37.829545-05	2. Medidor encontrado	\N
122	25	me_serial	Medidor encontrado · Serial	texto	f	\N	\N	30	\N	Si no se alcanza a leer, deje vacío y marque «Serial ilegible».	f	204	t	2026-11-21 18:45:37.829609-05	2. Medidor encontrado	\N
124	23	me_serial	Medidor encontrado · Serial	texto	f	\N	\N	30	\N	Si no se alcanza a leer, deje vacío y marque «Serial ilegible».	f	204	t	2026-11-21 18:45:37.829636-05	2. Medidor encontrado	\N
125	26	me_serial	Medidor encontrado · Serial	texto	f	\N	\N	30	\N	Si no se alcanza a leer, deje vacío y marque «Serial ilegible».	f	204	t	2026-11-21 18:45:37.829649-05	2. Medidor encontrado	\N
126	25	me_serial_ilegible	Medidor encontrado · Serial ilegible	si_no	f	\N	\N	\N	\N	\N	f	205	t	2026-11-21 18:45:37.829662-05	2. Medidor encontrado	\N
128	23	me_serial_ilegible	Medidor encontrado · Serial ilegible	si_no	f	\N	\N	\N	\N	\N	f	205	t	2026-11-21 18:45:37.829692-05	2. Medidor encontrado	\N
129	26	me_serial_ilegible	Medidor encontrado · Serial ilegible	si_no	f	\N	\N	\N	\N	\N	f	205	t	2026-11-21 18:45:37.829707-05	2. Medidor encontrado	\N
130	25	me_diametro	Medidor encontrado · Diámetro	opcion	f	[{"codigo": "media", "nombre": "½ pulgada"}, {"codigo": "tres_cuartos", "nombre": "¾ pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "una_media", "nombre": "1½ pulgadas"}, {"codigo": "dos", "nombre": "2 pulgadas"}, {"codigo": "tres", "nombre": "3 pulgadas"}, {"codigo": "cuatro", "nombre": "4 pulgadas"}]	\N	\N	\N	\N	f	206	t	2026-11-21 18:45:37.829724-05	2. Medidor encontrado	\N
242	25	geofono	¿Se hizo detección con geófono?	si_no	f	\N	\N	\N	\N	\N	f	510	t	2026-11-21 18:45:37.832483-05	5. Instalaciones internas	{"es": true, "campo": "fuga_imperceptible"}
132	23	me_diametro	Medidor encontrado · Diámetro	opcion	f	[{"codigo": "media", "nombre": "½ pulgada"}, {"codigo": "tres_cuartos", "nombre": "¾ pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "una_media", "nombre": "1½ pulgadas"}, {"codigo": "dos", "nombre": "2 pulgadas"}, {"codigo": "tres", "nombre": "3 pulgadas"}, {"codigo": "cuatro", "nombre": "4 pulgadas"}]	\N	\N	\N	\N	f	206	t	2026-11-21 18:45:37.829823-05	2. Medidor encontrado	\N
133	26	me_diametro	Medidor encontrado · Diámetro	opcion	f	[{"codigo": "media", "nombre": "½ pulgada"}, {"codigo": "tres_cuartos", "nombre": "¾ pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "una_media", "nombre": "1½ pulgadas"}, {"codigo": "dos", "nombre": "2 pulgadas"}, {"codigo": "tres", "nombre": "3 pulgadas"}, {"codigo": "cuatro", "nombre": "4 pulgadas"}]	\N	\N	\N	\N	f	206	t	2026-11-21 18:45:37.829861-05	2. Medidor encontrado	\N
134	25	me_precinto_tipo	Medidor encontrado · Tipo de precintos	texto	f	\N	\N	30	\N	\N	f	207	t	2026-11-21 18:45:37.829897-05	2. Medidor encontrado	\N
136	23	me_precinto_tipo	Medidor encontrado · Tipo de precintos	texto	f	\N	\N	30	\N	\N	f	207	t	2026-11-21 18:45:37.829928-05	2. Medidor encontrado	\N
137	26	me_precinto_tipo	Medidor encontrado · Tipo de precintos	texto	f	\N	\N	30	\N	\N	f	207	t	2026-11-21 18:45:37.829942-05	2. Medidor encontrado	\N
138	25	me_precinto_serie	Medidor encontrado · Serie de precintos	texto	f	\N	\N	30	\N	\N	f	208	t	2026-11-21 18:45:37.829956-05	2. Medidor encontrado	\N
140	23	me_precinto_serie	Medidor encontrado · Serie de precintos	texto	f	\N	\N	30	\N	\N	f	208	t	2026-11-21 18:45:37.829986-05	2. Medidor encontrado	\N
141	26	me_precinto_serie	Medidor encontrado · Serie de precintos	texto	f	\N	\N	30	\N	\N	f	208	t	2026-11-21 18:45:37.830001-05	2. Medidor encontrado	\N
142	25	me_anio	Medidor encontrado · Año de fabricación	entero	f	\N	1950	2100	\N	\N	f	209	t	2026-11-21 18:45:37.830016-05	2. Medidor encontrado	\N
144	23	me_anio	Medidor encontrado · Año de fabricación	entero	f	\N	1950	2100	\N	\N	f	209	t	2026-11-21 18:45:37.830043-05	2. Medidor encontrado	\N
145	26	me_anio	Medidor encontrado · Año de fabricación	entero	f	\N	1950	2100	\N	\N	f	209	t	2026-11-21 18:45:37.830056-05	2. Medidor encontrado	\N
146	25	me_talco	Talco	opciones	f	[{"codigo": "opaco", "nombre": "Opaco"}, {"codigo": "partido_fisurado", "nombre": "Partido o fisurado"}, {"codigo": "perforado", "nombre": "Perforado"}, {"codigo": "transparente_ok", "nombre": "Transparente / ok"}, {"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "destruido", "nombre": "Destruido"}, {"codigo": "ilegible", "nombre": "Ilegible"}, {"codigo": "vidrio_roto", "nombre": "Vidrio roto"}, {"codigo": "sin_agujas", "nombre": "Sin agujas"}]	\N	\N	\N	\N	f	301	t	2026-11-21 18:45:37.830073-05	3. Estado del medidor	\N
148	23	me_talco	Talco	opciones	f	[{"codigo": "opaco", "nombre": "Opaco"}, {"codigo": "partido_fisurado", "nombre": "Partido o fisurado"}, {"codigo": "perforado", "nombre": "Perforado"}, {"codigo": "transparente_ok", "nombre": "Transparente / ok"}, {"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "destruido", "nombre": "Destruido"}, {"codigo": "ilegible", "nombre": "Ilegible"}, {"codigo": "vidrio_roto", "nombre": "Vidrio roto"}, {"codigo": "sin_agujas", "nombre": "Sin agujas"}]	\N	\N	\N	\N	f	301	t	2026-11-21 18:45:37.830168-05	3. Estado del medidor	\N
149	26	me_talco	Talco	opciones	f	[{"codigo": "opaco", "nombre": "Opaco"}, {"codigo": "partido_fisurado", "nombre": "Partido o fisurado"}, {"codigo": "perforado", "nombre": "Perforado"}, {"codigo": "transparente_ok", "nombre": "Transparente / ok"}, {"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "destruido", "nombre": "Destruido"}, {"codigo": "ilegible", "nombre": "Ilegible"}, {"codigo": "vidrio_roto", "nombre": "Vidrio roto"}, {"codigo": "sin_agujas", "nombre": "Sin agujas"}]	\N	\N	\N	\N	f	301	t	2026-11-21 18:45:37.830213-05	3. Estado del medidor	\N
150	25	me_cuerpo	Cuerpo	opciones	f	[{"codigo": "perforado", "nombre": "Perforado"}, {"codigo": "fisurado_roto", "nombre": "Fisurado o roto"}, {"codigo": "conexion_invertida", "nombre": "Conexión invertida"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	302	t	2026-11-21 18:45:37.830255-05	3. Estado del medidor	\N
152	23	me_cuerpo	Cuerpo	opciones	f	[{"codigo": "perforado", "nombre": "Perforado"}, {"codigo": "fisurado_roto", "nombre": "Fisurado o roto"}, {"codigo": "conexion_invertida", "nombre": "Conexión invertida"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	302	t	2026-11-21 18:45:37.830314-05	3. Estado del medidor	\N
153	26	me_cuerpo	Cuerpo	opciones	f	[{"codigo": "perforado", "nombre": "Perforado"}, {"codigo": "fisurado_roto", "nombre": "Fisurado o roto"}, {"codigo": "conexion_invertida", "nombre": "Conexión invertida"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	302	t	2026-11-21 18:45:37.830341-05	3. Estado del medidor	\N
154	25	me_registro	Registro	opciones	f	[{"codigo": "detenido", "nombre": "Medidor detenido"}, {"codigo": "giro_irregular", "nombre": "Giro irregular"}, {"codigo": "obstruido", "nombre": "Medidor obstruido"}, {"codigo": "mal_estado", "nombre": "Registro en mal estado"}]	\N	\N	\N	\N	f	303	t	2026-11-21 18:45:37.830369-05	3. Estado del medidor	\N
156	23	me_registro	Registro	opciones	f	[{"codigo": "detenido", "nombre": "Medidor detenido"}, {"codigo": "giro_irregular", "nombre": "Giro irregular"}, {"codigo": "obstruido", "nombre": "Medidor obstruido"}, {"codigo": "mal_estado", "nombre": "Registro en mal estado"}]	\N	\N	\N	\N	f	303	t	2026-11-21 18:45:37.830441-05	3. Estado del medidor	\N
157	26	me_registro	Registro	opciones	f	[{"codigo": "detenido", "nombre": "Medidor detenido"}, {"codigo": "giro_irregular", "nombre": "Giro irregular"}, {"codigo": "obstruido", "nombre": "Medidor obstruido"}, {"codigo": "mal_estado", "nombre": "Registro en mal estado"}]	\N	\N	\N	\N	f	303	t	2026-11-21 18:45:37.83047-05	3. Estado del medidor	\N
158	25	req_cambio_medidor	¿Se requiere cambio de medidor?	si_no	t	\N	\N	\N	\N	\N	f	304	t	2026-11-21 18:45:37.830498-05	3. Estado del medidor	\N
160	23	req_cambio_medidor	¿Se requiere cambio de medidor?	si_no	f	\N	\N	\N	\N	\N	f	304	t	2026-11-21 18:45:37.83053-05	3. Estado del medidor	\N
161	26	req_cambio_medidor	¿Se requiere cambio de medidor?	si_no	t	\N	\N	\N	\N	\N	f	304	t	2026-11-21 18:45:37.830545-05	3. Estado del medidor	\N
162	25	calib_realizada	Prueba de calibración: ¿se realizó?	si_no	f	\N	\N	\N	\N	\N	f	305	t	2026-11-21 18:45:37.83059-05	3. Estado del medidor	\N
164	23	calib_realizada	Prueba de calibración: ¿se realizó?	si_no	f	\N	\N	\N	\N	\N	f	305	t	2026-11-21 18:45:37.830619-05	3. Estado del medidor	\N
165	26	calib_realizada	Prueba de calibración: ¿se realizó?	si_no	f	\N	\N	\N	\N	\N	f	305	t	2026-11-21 18:45:37.830632-05	3. Estado del medidor	\N
166	25	calib_vol_patron	Volumen del patrón	decimal	f	\N	0	100000	L	\N	f	306	t	2026-11-21 18:45:37.830646-05	3. Estado del medidor	{"es": true, "campo": "calib_realizada"}
168	23	calib_vol_patron	Volumen del patrón	decimal	f	\N	0	100000	L	\N	f	306	t	2026-11-21 18:45:37.83069-05	3. Estado del medidor	{"es": true, "campo": "calib_realizada"}
169	26	calib_vol_patron	Volumen del patrón	decimal	f	\N	0	100000	L	\N	f	306	t	2026-11-21 18:45:37.830707-05	3. Estado del medidor	{"es": true, "campo": "calib_realizada"}
170	25	calib_vol_cliente	Volumen del cliente	decimal	f	\N	0	100000	L	\N	f	307	t	2026-11-21 18:45:37.830726-05	3. Estado del medidor	{"es": true, "campo": "calib_realizada"}
172	23	calib_vol_cliente	Volumen del cliente	decimal	f	\N	0	100000	L	\N	f	307	t	2026-11-21 18:45:37.830762-05	3. Estado del medidor	{"es": true, "campo": "calib_realizada"}
173	26	calib_vol_cliente	Volumen del cliente	decimal	f	\N	0	100000	L	\N	f	307	t	2026-11-21 18:45:37.830781-05	3. Estado del medidor	{"es": true, "campo": "calib_realizada"}
174	25	calib_error_pct	Error de la prueba	decimal	f	\N	-100	1000	%	\N	f	308	t	2026-11-21 18:45:37.830798-05	3. Estado del medidor	{"es": true, "campo": "calib_realizada"}
176	23	calib_error_pct	Error de la prueba	decimal	f	\N	-100	1000	%	\N	f	308	t	2026-11-21 18:45:37.830833-05	3. Estado del medidor	{"es": true, "campo": "calib_realizada"}
177	26	calib_error_pct	Error de la prueba	decimal	f	\N	-100	1000	%	\N	f	308	t	2026-11-21 18:45:37.83085-05	3. Estado del medidor	{"es": true, "campo": "calib_realizada"}
178	25	acom_diametro	Acometida · Diámetro	opcion	f	[{"codigo": "media", "nombre": "½ pulgada"}, {"codigo": "tres_cuartos", "nombre": "¾ pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "una_media", "nombre": "1½ pulgadas"}, {"codigo": "dos", "nombre": "2 pulgadas"}, {"codigo": "tres", "nombre": "3 pulgadas"}, {"codigo": "cuatro", "nombre": "4 pulgadas"}]	\N	\N	\N	\N	f	401	t	2026-11-21 18:45:37.83087-05	4. Acometida y accesorios	\N
179	24	acom_diametro	Acometida · Diámetro	opcion	f	[{"codigo": "media", "nombre": "½ pulgada"}, {"codigo": "tres_cuartos", "nombre": "¾ pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "una_media", "nombre": "1½ pulgadas"}, {"codigo": "dos", "nombre": "2 pulgadas"}, {"codigo": "tres", "nombre": "3 pulgadas"}, {"codigo": "cuatro", "nombre": "4 pulgadas"}]	\N	\N	\N	\N	f	401	t	2026-11-21 18:45:37.830908-05	4. Acometida y accesorios	\N
180	23	acom_diametro	Acometida · Diámetro	opcion	t	[{"codigo": "media", "nombre": "½ pulgada"}, {"codigo": "tres_cuartos", "nombre": "¾ pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "una_media", "nombre": "1½ pulgadas"}, {"codigo": "dos", "nombre": "2 pulgadas"}, {"codigo": "tres", "nombre": "3 pulgadas"}, {"codigo": "cuatro", "nombre": "4 pulgadas"}]	\N	\N	\N	\N	f	401	t	2026-11-21 18:45:37.830945-05	4. Acometida y accesorios	\N
181	26	acom_diametro	Acometida · Diámetro	opcion	f	[{"codigo": "media", "nombre": "½ pulgada"}, {"codigo": "tres_cuartos", "nombre": "¾ pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "una_media", "nombre": "1½ pulgadas"}, {"codigo": "dos", "nombre": "2 pulgadas"}, {"codigo": "tres", "nombre": "3 pulgadas"}, {"codigo": "cuatro", "nombre": "4 pulgadas"}]	\N	\N	\N	\N	f	401	t	2026-11-21 18:45:37.830981-05	4. Acometida y accesorios	\N
182	25	acom_estado	Acometida · Estado	opciones	f	[{"codigo": "fugas_visibles", "nombre": "Fugas visibles"}, {"codigo": "derivacion_no_autorizada", "nombre": "Derivación no autorizada"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "conexion_directa", "nombre": "Conexión directa"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	402	t	2026-11-21 18:45:37.831016-05	4. Acometida y accesorios	\N
183	24	acom_estado	Acometida · Estado	opciones	f	[{"codigo": "fugas_visibles", "nombre": "Fugas visibles"}, {"codigo": "derivacion_no_autorizada", "nombre": "Derivación no autorizada"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "conexion_directa", "nombre": "Conexión directa"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	402	t	2026-11-21 18:45:37.831052-05	4. Acometida y accesorios	\N
184	23	acom_estado	Acometida · Estado	opciones	f	[{"codigo": "fugas_visibles", "nombre": "Fugas visibles"}, {"codigo": "derivacion_no_autorizada", "nombre": "Derivación no autorizada"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "conexion_directa", "nombre": "Conexión directa"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	402	t	2026-11-21 18:45:37.831086-05	4. Acometida y accesorios	\N
185	26	acom_estado	Acometida · Estado	opciones	f	[{"codigo": "fugas_visibles", "nombre": "Fugas visibles"}, {"codigo": "derivacion_no_autorizada", "nombre": "Derivación no autorizada"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "conexion_directa", "nombre": "Conexión directa"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	402	t	2026-11-21 18:45:37.831137-05	4. Acometida y accesorios	\N
186	25	cajilla	Cajilla	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "sin_fondo", "nombre": "Sin fondo"}, {"codigo": "tapada", "nombre": "Tapada"}, {"codigo": "sin_acceso", "nombre": "Sin acceso"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	403	t	2026-11-21 18:45:37.831172-05	4. Acometida y accesorios	\N
187	24	cajilla	Cajilla	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "sin_fondo", "nombre": "Sin fondo"}, {"codigo": "tapada", "nombre": "Tapada"}, {"codigo": "sin_acceso", "nombre": "Sin acceso"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	403	t	2026-11-21 18:45:37.831205-05	4. Acometida y accesorios	\N
188	23	cajilla	Cajilla	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "sin_fondo", "nombre": "Sin fondo"}, {"codigo": "tapada", "nombre": "Tapada"}, {"codigo": "sin_acceso", "nombre": "Sin acceso"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	403	t	2026-11-21 18:45:37.83124-05	4. Acometida y accesorios	\N
189	26	cajilla	Cajilla	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "sin_fondo", "nombre": "Sin fondo"}, {"codigo": "tapada", "nombre": "Tapada"}, {"codigo": "sin_acceso", "nombre": "Sin acceso"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	403	t	2026-11-21 18:45:37.831272-05	4. Acometida y accesorios	\N
190	25	reg_corte	Registro de corte	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "fuga", "nombre": "Presenta fuga"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	404	t	2026-11-21 18:45:37.831303-05	4. Acometida y accesorios	\N
191	24	reg_corte	Registro de corte	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "fuga", "nombre": "Presenta fuga"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	404	t	2026-11-21 18:45:37.831328-05	4. Acometida y accesorios	\N
192	23	reg_corte	Registro de corte	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "fuga", "nombre": "Presenta fuga"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	404	t	2026-11-21 18:45:37.831353-05	4. Acometida y accesorios	\N
193	26	reg_corte	Registro de corte	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "fuga", "nombre": "Presenta fuga"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	404	t	2026-11-21 18:45:37.831378-05	4. Acometida y accesorios	\N
194	25	llave_control	Llave de control	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "fuga", "nombre": "Presenta fuga"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	405	t	2026-11-21 18:45:37.831404-05	4. Acometida y accesorios	\N
195	24	llave_control	Llave de control	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "fuga", "nombre": "Presenta fuga"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	405	t	2026-11-21 18:45:37.831429-05	4. Acometida y accesorios	\N
196	23	llave_control	Llave de control	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "fuga", "nombre": "Presenta fuga"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	405	t	2026-11-21 18:45:37.831455-05	4. Acometida y accesorios	\N
197	26	llave_control	Llave de control	opciones	f	[{"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "mal_estado", "nombre": "En mal estado"}, {"codigo": "fuga", "nombre": "Presenta fuga"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	405	t	2026-11-21 18:45:37.831481-05	4. Acometida y accesorios	\N
198	25	req_instalar	Tras el diagnóstico, el cliente requiere INSTALAR	opciones	f	[{"codigo": "acometida", "nombre": "Acometida"}, {"codigo": "registro_corte", "nombre": "Registro de corte"}, {"codigo": "llave_control", "nombre": "Llave de control"}, {"codigo": "cajilla", "nombre": "Cajilla"}]	\N	\N	\N	\N	f	406	t	2026-11-21 18:45:37.831506-05	4. Acometida y accesorios	\N
199	24	req_instalar	Tras el diagnóstico, el cliente requiere INSTALAR	opciones	f	[{"codigo": "acometida", "nombre": "Acometida"}, {"codigo": "registro_corte", "nombre": "Registro de corte"}, {"codigo": "llave_control", "nombre": "Llave de control"}, {"codigo": "cajilla", "nombre": "Cajilla"}]	\N	\N	\N	\N	f	406	t	2026-11-21 18:45:37.831536-05	4. Acometida y accesorios	\N
200	23	req_instalar	Tras el diagnóstico, el cliente requiere INSTALAR	opciones	f	[{"codigo": "acometida", "nombre": "Acometida"}, {"codigo": "registro_corte", "nombre": "Registro de corte"}, {"codigo": "llave_control", "nombre": "Llave de control"}, {"codigo": "cajilla", "nombre": "Cajilla"}]	\N	\N	\N	\N	f	406	t	2026-11-21 18:45:37.831566-05	4. Acometida y accesorios	\N
201	26	req_instalar	Tras el diagnóstico, el cliente requiere INSTALAR	opciones	f	[{"codigo": "acometida", "nombre": "Acometida"}, {"codigo": "registro_corte", "nombre": "Registro de corte"}, {"codigo": "llave_control", "nombre": "Llave de control"}, {"codigo": "cajilla", "nombre": "Cajilla"}]	\N	\N	\N	\N	f	406	t	2026-11-21 18:45:37.831594-05	4. Acometida y accesorios	\N
202	25	req_adecuar	Tras el diagnóstico, el cliente requiere ADECUAR	opciones	f	[{"codigo": "acometida", "nombre": "Acometida"}, {"codigo": "registro_corte", "nombre": "Registro de corte"}, {"codigo": "llave_control", "nombre": "Llave de control"}, {"codigo": "cajilla", "nombre": "Cajilla"}]	\N	\N	\N	\N	f	407	t	2026-11-21 18:45:37.831623-05	4. Acometida y accesorios	\N
243	24	geofono	¿Se hizo detección con geófono?	si_no	f	\N	\N	\N	\N	\N	f	510	t	2026-11-21 18:45:37.832502-05	5. Instalaciones internas	{"es": true, "campo": "fuga_imperceptible"}
203	24	req_adecuar	Tras el diagnóstico, el cliente requiere ADECUAR	opciones	f	[{"codigo": "acometida", "nombre": "Acometida"}, {"codigo": "registro_corte", "nombre": "Registro de corte"}, {"codigo": "llave_control", "nombre": "Llave de control"}, {"codigo": "cajilla", "nombre": "Cajilla"}]	\N	\N	\N	\N	f	407	t	2026-11-21 18:45:37.831652-05	4. Acometida y accesorios	\N
204	23	req_adecuar	Tras el diagnóstico, el cliente requiere ADECUAR	opciones	f	[{"codigo": "acometida", "nombre": "Acometida"}, {"codigo": "registro_corte", "nombre": "Registro de corte"}, {"codigo": "llave_control", "nombre": "Llave de control"}, {"codigo": "cajilla", "nombre": "Cajilla"}]	\N	\N	\N	\N	f	407	t	2026-11-21 18:45:37.831695-05	4. Acometida y accesorios	\N
205	26	req_adecuar	Tras el diagnóstico, el cliente requiere ADECUAR	opciones	f	[{"codigo": "acometida", "nombre": "Acometida"}, {"codigo": "registro_corte", "nombre": "Registro de corte"}, {"codigo": "llave_control", "nombre": "Llave de control"}, {"codigo": "cajilla", "nombre": "Cajilla"}]	\N	\N	\N	\N	f	407	t	2026-11-21 18:45:37.831725-05	4. Acometida y accesorios	\N
206	25	pt_llaves	Llaves o plumas · Cantidad	entero	f	\N	0	99	\N	\N	f	501	t	2026-11-21 18:45:37.831753-05	5. Instalaciones internas	\N
207	24	pt_llaves	Llaves o plumas · Cantidad	entero	f	\N	0	99	\N	\N	f	501	t	2026-11-21 18:45:37.831767-05	5. Instalaciones internas	\N
208	23	pt_llaves	Llaves o plumas · Cantidad	entero	f	\N	0	99	\N	\N	f	501	t	2026-11-21 18:45:37.83178-05	5. Instalaciones internas	\N
209	26	pt_llaves	Llaves o plumas · Cantidad	entero	f	\N	0	99	\N	\N	f	501	t	2026-11-21 18:45:37.831794-05	5. Instalaciones internas	\N
210	25	pt_duchas	Duchas · Cantidad	entero	f	\N	0	99	\N	\N	f	502	t	2026-11-21 18:45:37.831807-05	5. Instalaciones internas	\N
211	24	pt_duchas	Duchas · Cantidad	entero	f	\N	0	99	\N	\N	f	502	t	2026-11-21 18:45:37.831821-05	5. Instalaciones internas	\N
212	23	pt_duchas	Duchas · Cantidad	entero	f	\N	0	99	\N	\N	f	502	t	2026-11-21 18:45:37.831892-05	5. Instalaciones internas	\N
213	26	pt_duchas	Duchas · Cantidad	entero	f	\N	0	99	\N	\N	f	502	t	2026-11-21 18:45:37.831908-05	5. Instalaciones internas	\N
214	25	pt_sanitarios	Sanitarios · Cantidad	entero	f	\N	0	99	\N	\N	f	503	t	2026-11-21 18:45:37.831922-05	5. Instalaciones internas	\N
215	24	pt_sanitarios	Sanitarios · Cantidad	entero	f	\N	0	99	\N	\N	f	503	t	2026-11-21 18:45:37.831937-05	5. Instalaciones internas	\N
216	23	pt_sanitarios	Sanitarios · Cantidad	entero	f	\N	0	99	\N	\N	f	503	t	2026-11-21 18:45:37.831951-05	5. Instalaciones internas	\N
217	26	pt_sanitarios	Sanitarios · Cantidad	entero	f	\N	0	99	\N	\N	f	503	t	2026-11-21 18:45:37.831965-05	5. Instalaciones internas	\N
218	25	pt_valvula_riego	Válvula de riego · Cantidad	entero	f	\N	0	99	\N	\N	f	504	t	2026-11-21 18:45:37.831979-05	5. Instalaciones internas	\N
219	24	pt_valvula_riego	Válvula de riego · Cantidad	entero	f	\N	0	99	\N	\N	f	504	t	2026-11-21 18:45:37.831994-05	5. Instalaciones internas	\N
220	23	pt_valvula_riego	Válvula de riego · Cantidad	entero	f	\N	0	99	\N	\N	f	504	t	2026-11-21 18:45:37.832017-05	5. Instalaciones internas	\N
221	26	pt_valvula_riego	Válvula de riego · Cantidad	entero	f	\N	0	99	\N	\N	f	504	t	2026-11-21 18:45:37.832031-05	5. Instalaciones internas	\N
222	25	pt_otros	Otros puntos de agua · Cantidad	entero	f	\N	0	99	\N	\N	f	505	t	2026-11-21 18:45:37.832046-05	5. Instalaciones internas	\N
223	24	pt_otros	Otros puntos de agua · Cantidad	entero	f	\N	0	99	\N	\N	f	505	t	2026-11-21 18:45:37.832059-05	5. Instalaciones internas	\N
224	23	pt_otros	Otros puntos de agua · Cantidad	entero	f	\N	0	99	\N	\N	f	505	t	2026-11-21 18:45:37.832125-05	5. Instalaciones internas	\N
225	26	pt_otros	Otros puntos de agua · Cantidad	entero	f	\N	0	99	\N	\N	f	505	t	2026-11-21 18:45:37.83214-05	5. Instalaciones internas	\N
226	25	pt_con_fuga	Puntos de agua con fuga	opciones	f	[{"codigo": "llaves", "nombre": "Llaves o plumas"}, {"codigo": "duchas", "nombre": "Duchas"}, {"codigo": "sanitarios", "nombre": "Sanitarios"}, {"codigo": "valvula_riego", "nombre": "Válvula de riego"}, {"codigo": "otros", "nombre": "Otros"}]	\N	\N	\N	\N	f	506	t	2026-11-21 18:45:37.832156-05	5. Instalaciones internas	\N
227	24	pt_con_fuga	Puntos de agua con fuga	opciones	f	[{"codigo": "llaves", "nombre": "Llaves o plumas"}, {"codigo": "duchas", "nombre": "Duchas"}, {"codigo": "sanitarios", "nombre": "Sanitarios"}, {"codigo": "valvula_riego", "nombre": "Válvula de riego"}, {"codigo": "otros", "nombre": "Otros"}]	\N	\N	\N	\N	f	506	t	2026-11-21 18:45:37.832188-05	5. Instalaciones internas	\N
228	23	pt_con_fuga	Puntos de agua con fuga	opciones	f	[{"codigo": "llaves", "nombre": "Llaves o plumas"}, {"codigo": "duchas", "nombre": "Duchas"}, {"codigo": "sanitarios", "nombre": "Sanitarios"}, {"codigo": "valvula_riego", "nombre": "Válvula de riego"}, {"codigo": "otros", "nombre": "Otros"}]	\N	\N	\N	\N	f	506	t	2026-11-21 18:45:37.832219-05	5. Instalaciones internas	\N
229	26	pt_con_fuga	Puntos de agua con fuga	opciones	f	[{"codigo": "llaves", "nombre": "Llaves o plumas"}, {"codigo": "duchas", "nombre": "Duchas"}, {"codigo": "sanitarios", "nombre": "Sanitarios"}, {"codigo": "valvula_riego", "nombre": "Válvula de riego"}, {"codigo": "otros", "nombre": "Otros"}]	\N	\N	\N	\N	f	506	t	2026-11-21 18:45:37.83225-05	5. Instalaciones internas	\N
230	25	fuga_perceptible	¿Hay fugas perceptibles?	si_no	f	\N	\N	\N	\N	\N	f	507	t	2026-11-21 18:45:37.832279-05	5. Instalaciones internas	\N
231	24	fuga_perceptible	¿Hay fugas perceptibles?	si_no	f	\N	\N	\N	\N	\N	f	507	t	2026-11-21 18:45:37.832294-05	5. Instalaciones internas	\N
232	23	fuga_perceptible	¿Hay fugas perceptibles?	si_no	f	\N	\N	\N	\N	\N	f	507	t	2026-11-21 18:45:37.832309-05	5. Instalaciones internas	\N
233	26	fuga_perceptible	¿Hay fugas perceptibles?	si_no	f	\N	\N	\N	\N	\N	f	507	t	2026-11-21 18:45:37.832324-05	5. Instalaciones internas	\N
234	25	fuga_percep_obs	Fugas perceptibles · Observación	texto	f	\N	\N	150	\N	\N	f	508	t	2026-11-21 18:45:37.832339-05	5. Instalaciones internas	{"es": true, "campo": "fuga_perceptible"}
235	24	fuga_percep_obs	Fugas perceptibles · Observación	texto	f	\N	\N	150	\N	\N	f	508	t	2026-11-21 18:45:37.83236-05	5. Instalaciones internas	{"es": true, "campo": "fuga_perceptible"}
236	23	fuga_percep_obs	Fugas perceptibles · Observación	texto	f	\N	\N	150	\N	\N	f	508	t	2026-11-21 18:45:37.832379-05	5. Instalaciones internas	{"es": true, "campo": "fuga_perceptible"}
237	26	fuga_percep_obs	Fugas perceptibles · Observación	texto	f	\N	\N	150	\N	\N	f	508	t	2026-11-21 18:45:37.832398-05	5. Instalaciones internas	{"es": true, "campo": "fuga_perceptible"}
238	25	fuga_imperceptible	¿Hay fugas imperceptibles?	si_no	f	\N	\N	\N	\N	\N	f	509	t	2026-11-21 18:45:37.832416-05	5. Instalaciones internas	\N
239	24	fuga_imperceptible	¿Hay fugas imperceptibles?	si_no	f	\N	\N	\N	\N	\N	f	509	t	2026-11-21 18:45:37.832432-05	5. Instalaciones internas	\N
240	23	fuga_imperceptible	¿Hay fugas imperceptibles?	si_no	f	\N	\N	\N	\N	\N	f	509	t	2026-11-21 18:45:37.832448-05	5. Instalaciones internas	\N
244	23	geofono	¿Se hizo detección con geófono?	si_no	f	\N	\N	\N	\N	\N	f	510	t	2026-11-21 18:45:37.832519-05	5. Instalaciones internas	{"es": true, "campo": "fuga_imperceptible"}
245	26	geofono	¿Se hizo detección con geófono?	si_no	f	\N	\N	\N	\N	\N	f	510	t	2026-11-21 18:45:37.832552-05	5. Instalaciones internas	{"es": true, "campo": "fuga_imperceptible"}
246	25	fuga_imperc_obs	Fugas imperceptibles · Localización u observación	texto	f	\N	\N	150	\N	\N	f	511	t	2026-11-21 18:45:37.832571-05	5. Instalaciones internas	{"es": true, "campo": "fuga_imperceptible"}
247	24	fuga_imperc_obs	Fugas imperceptibles · Localización u observación	texto	f	\N	\N	150	\N	\N	f	511	t	2026-11-21 18:45:37.83259-05	5. Instalaciones internas	{"es": true, "campo": "fuga_imperceptible"}
248	23	fuga_imperc_obs	Fugas imperceptibles · Localización u observación	texto	f	\N	\N	150	\N	\N	f	511	t	2026-11-21 18:45:37.832609-05	5. Instalaciones internas	{"es": true, "campo": "fuga_imperceptible"}
249	26	fuga_imperc_obs	Fugas imperceptibles · Localización u observación	texto	f	\N	\N	150	\N	\N	f	511	t	2026-11-21 18:45:37.832628-05	5. Instalaciones internas	{"es": true, "campo": "fuga_imperceptible"}
250	25	irr_hay	¿Se encontró irregularidad?	si_no	t	\N	\N	\N	\N	Si responde «Sí», al guardar podrá abrir el acta de inspección técnica sobre el mismo contrato.	f	801	t	2026-11-21 18:45:37.832647-05	8. Irregularidades	\N
251	24	irr_hay	¿Se encontró irregularidad?	si_no	t	\N	\N	\N	\N	Si responde «Sí», al guardar podrá abrir el acta de inspección técnica sobre el mismo contrato.	f	801	t	2026-11-21 18:45:37.832661-05	8. Irregularidades	\N
252	23	irr_hay	¿Se encontró irregularidad?	si_no	t	\N	\N	\N	\N	Si responde «Sí», al guardar podrá abrir el acta de inspección técnica sobre el mismo contrato.	f	801	t	2026-11-21 18:45:37.832674-05	8. Irregularidades	\N
253	26	irr_hay	¿Se encontró irregularidad?	si_no	t	\N	\N	\N	\N	Si responde «Sí», al guardar podrá abrir el acta de inspección técnica sobre el mismo contrato.	f	801	t	2026-11-21 18:45:37.832688-05	8. Irregularidades	\N
254	25	irr_tipos	Tipos de irregularidad	opciones	f	[{"codigo": "acometida_fraudulenta", "nombre": "Acometida fraudulenta"}, {"codigo": "conexiones_medidor_adulteradas", "nombre": "Conexiones del medidor adulteradas"}, {"codigo": "medidor_adulterado", "nombre": "Medidor adulterado"}, {"codigo": "medidor_desconectado", "nombre": "Medidor desconectado"}, {"codigo": "adulteracion_sellos", "nombre": "Adulteración de sellos"}, {"codigo": "servicio_no_facturado", "nombre": "Servicio no facturado"}, {"codigo": "reconexion_no_autorizada", "nombre": "Reconexión no autorizada"}, {"codigo": "uso_no_autorizado", "nombre": "Uso no autorizado"}, {"codigo": "cajilla_interna", "nombre": "Cajilla interna"}]	\N	\N	\N	\N	f	802	t	2026-11-21 18:45:37.832705-05	8. Irregularidades	{"es": true, "campo": "irr_hay"}
255	24	irr_tipos	Tipos de irregularidad	opciones	f	[{"codigo": "acometida_fraudulenta", "nombre": "Acometida fraudulenta"}, {"codigo": "conexiones_medidor_adulteradas", "nombre": "Conexiones del medidor adulteradas"}, {"codigo": "medidor_adulterado", "nombre": "Medidor adulterado"}, {"codigo": "medidor_desconectado", "nombre": "Medidor desconectado"}, {"codigo": "adulteracion_sellos", "nombre": "Adulteración de sellos"}, {"codigo": "servicio_no_facturado", "nombre": "Servicio no facturado"}, {"codigo": "reconexion_no_autorizada", "nombre": "Reconexión no autorizada"}, {"codigo": "uso_no_autorizado", "nombre": "Uso no autorizado"}, {"codigo": "cajilla_interna", "nombre": "Cajilla interna"}]	\N	\N	\N	\N	f	802	t	2026-11-21 18:45:37.832771-05	8. Irregularidades	{"es": true, "campo": "irr_hay"}
256	23	irr_tipos	Tipos de irregularidad	opciones	f	[{"codigo": "acometida_fraudulenta", "nombre": "Acometida fraudulenta"}, {"codigo": "conexiones_medidor_adulteradas", "nombre": "Conexiones del medidor adulteradas"}, {"codigo": "medidor_adulterado", "nombre": "Medidor adulterado"}, {"codigo": "medidor_desconectado", "nombre": "Medidor desconectado"}, {"codigo": "adulteracion_sellos", "nombre": "Adulteración de sellos"}, {"codigo": "servicio_no_facturado", "nombre": "Servicio no facturado"}, {"codigo": "reconexion_no_autorizada", "nombre": "Reconexión no autorizada"}, {"codigo": "uso_no_autorizado", "nombre": "Uso no autorizado"}, {"codigo": "cajilla_interna", "nombre": "Cajilla interna"}]	\N	\N	\N	\N	f	802	t	2026-11-21 18:45:37.832873-05	8. Irregularidades	{"es": true, "campo": "irr_hay"}
257	26	irr_tipos	Tipos de irregularidad	opciones	f	[{"codigo": "acometida_fraudulenta", "nombre": "Acometida fraudulenta"}, {"codigo": "conexiones_medidor_adulteradas", "nombre": "Conexiones del medidor adulteradas"}, {"codigo": "medidor_adulterado", "nombre": "Medidor adulterado"}, {"codigo": "medidor_desconectado", "nombre": "Medidor desconectado"}, {"codigo": "adulteracion_sellos", "nombre": "Adulteración de sellos"}, {"codigo": "servicio_no_facturado", "nombre": "Servicio no facturado"}, {"codigo": "reconexion_no_autorizada", "nombre": "Reconexión no autorizada"}, {"codigo": "uso_no_autorizado", "nombre": "Uso no autorizado"}, {"codigo": "cajilla_interna", "nombre": "Cajilla interna"}]	\N	\N	\N	\N	f	802	t	2026-11-21 18:45:37.832966-05	8. Irregularidades	{"es": true, "campo": "irr_hay"}
258	25	irr_descripcion	Descripción de la irregularidad	texto	f	\N	\N	300	\N	\N	f	803	t	2026-11-21 18:45:37.833026-05	8. Irregularidades	{"es": true, "campo": "irr_hay"}
259	24	irr_descripcion	Descripción de la irregularidad	texto	f	\N	\N	300	\N	\N	f	803	t	2026-11-21 18:45:37.833043-05	8. Irregularidades	{"es": true, "campo": "irr_hay"}
260	23	irr_descripcion	Descripción de la irregularidad	texto	f	\N	\N	300	\N	\N	f	803	t	2026-11-21 18:45:37.833061-05	8. Irregularidades	{"es": true, "campo": "irr_hay"}
261	26	irr_descripcion	Descripción de la irregularidad	texto	f	\N	\N	300	\N	\N	f	803	t	2026-11-21 18:45:37.833077-05	8. Irregularidades	{"es": true, "campo": "irr_hay"}
262	25	firma_atendio	Firma de quien atendió	opcion	t	[{"codigo": "atendio_firmo", "nombre": "Atendió y firmó el acta"}, {"codigo": "atendio_se_nego", "nombre": "Atendió y se negó a firmar"}, {"codigo": "nadie_atendio", "nombre": "Nadie atendió"}]	\N	\N	\N	Solo se declara; el acta física firmada es el documento con valor probatorio. No escriba nombres ni documentos.	f	901	t	2026-11-21 18:45:37.833096-05	9. Firmas y papel	\N
263	24	firma_atendio	Firma de quien atendió	opcion	t	[{"codigo": "atendio_firmo", "nombre": "Atendió y firmó el acta"}, {"codigo": "atendio_se_nego", "nombre": "Atendió y se negó a firmar"}, {"codigo": "nadie_atendio", "nombre": "Nadie atendió"}]	\N	\N	\N	Solo se declara; el acta física firmada es el documento con valor probatorio. No escriba nombres ni documentos.	f	901	t	2026-11-21 18:45:37.833125-05	9. Firmas y papel	\N
264	23	firma_atendio	Firma de quien atendió	opcion	t	[{"codigo": "atendio_firmo", "nombre": "Atendió y firmó el acta"}, {"codigo": "atendio_se_nego", "nombre": "Atendió y se negó a firmar"}, {"codigo": "nadie_atendio", "nombre": "Nadie atendió"}]	\N	\N	\N	Solo se declara; el acta física firmada es el documento con valor probatorio. No escriba nombres ni documentos.	f	901	t	2026-11-21 18:45:37.833154-05	9. Firmas y papel	\N
265	26	firma_atendio	Firma de quien atendió	opcion	t	[{"codigo": "atendio_firmo", "nombre": "Atendió y firmó el acta"}, {"codigo": "atendio_se_nego", "nombre": "Atendió y se negó a firmar"}, {"codigo": "nadie_atendio", "nombre": "Nadie atendió"}]	\N	\N	\N	Solo se declara; el acta física firmada es el documento con valor probatorio. No escriba nombres ni documentos.	f	901	t	2026-11-21 18:45:37.833181-05	9. Firmas y papel	\N
266	25	hubo_testigo	¿Hubo testigo?	si_no	f	\N	\N	\N	\N	\N	f	902	t	2026-11-21 18:45:37.833221-05	9. Firmas y papel	\N
267	24	hubo_testigo	¿Hubo testigo?	si_no	f	\N	\N	\N	\N	\N	f	902	t	2026-11-21 18:45:37.833236-05	9. Firmas y papel	\N
268	23	hubo_testigo	¿Hubo testigo?	si_no	f	\N	\N	\N	\N	\N	f	902	t	2026-11-21 18:45:37.83325-05	9. Firmas y papel	\N
269	26	hubo_testigo	¿Hubo testigo?	si_no	f	\N	\N	\N	\N	\N	f	902	t	2026-11-21 18:45:37.833264-05	9. Firmas y papel	\N
270	25	firmo_operario	¿El operario firmó el acta física?	si_no	t	\N	\N	\N	\N	\N	f	903	t	2026-11-21 18:45:37.833278-05	9. Firmas y papel	\N
271	24	firmo_operario	¿El operario firmó el acta física?	si_no	t	\N	\N	\N	\N	\N	f	903	t	2026-11-21 18:45:37.833293-05	9. Firmas y papel	\N
272	23	firmo_operario	¿El operario firmó el acta física?	si_no	t	\N	\N	\N	\N	\N	f	903	t	2026-11-21 18:45:37.833308-05	9. Firmas y papel	\N
273	26	firmo_operario	¿El operario firmó el acta física?	si_no	t	\N	\N	\N	\N	\N	f	903	t	2026-11-21 18:45:37.833322-05	9. Firmas y papel	\N
274	25	pqr_numero	Número de la PQR	texto	t	\N	\N	30	\N	Solo el número; no escriba nombres ni teléfonos.	f	110	t	2026-11-21 18:45:37.833337-05	1. Datos básicos	\N
275	24	inst_tipo	Tipo de instalación	opcion	t	[{"codigo": "d1", "nombre": "D1"}, {"codigo": "d2", "nombre": "D2"}, {"codigo": "d3", "nombre": "D3"}]	\N	\N	\N	Se confirmará el significado de D1, D2 y D3.	f	701	t	2026-11-21 18:45:37.833354-05	7. Instalaciones y adecuaciones	\N
276	23	inst_tipo	Tipo de instalación	opcion	t	[{"codigo": "d1", "nombre": "D1"}, {"codigo": "d2", "nombre": "D2"}, {"codigo": "d3", "nombre": "D3"}]	\N	\N	\N	Se confirmará el significado de D1, D2 y D3.	f	701	t	2026-11-21 18:45:37.833378-05	7. Instalaciones y adecuaciones	\N
277	24	inst_materiales	Materiales usados	opciones	f	[{"codigo": "union_simple_pvc", "nombre": "Unión simple PVC"}, {"codigo": "codo_90_pvc", "nombre": "Codo 90 PVC"}, {"codigo": "adaptador_macho_pvc", "nombre": "Adaptador macho PVC"}, {"codigo": "adaptador_hembra_pvc", "nombre": "Adaptador hembra PVC"}, {"codigo": "buje_soldado", "nombre": "Buje soldado"}, {"codigo": "valvula_incorporacion", "nombre": "Válvula de incorporación"}, {"codigo": "buje_roscado", "nombre": "Buje roscado"}, {"codigo": "tapon_soldado", "nombre": "Tapón soldado"}, {"codigo": "tapon_roscado", "nombre": "Tapón roscado"}, {"codigo": "tee_pvc", "nombre": "Tee PVC"}, {"codigo": "galapago", "nombre": "Galápago"}, {"codigo": "pf_macho", "nombre": "PF macho"}, {"codigo": "collar_derivacion", "nombre": "Collar de derivación"}, {"codigo": "tuberia_pvc", "nombre": "Tubería PVC"}, {"codigo": "losa_concreto", "nombre": "Losa de concreto"}, {"codigo": "soldadura_liquida", "nombre": "Soldadura líquida"}, {"codigo": "cajilla", "nombre": "Cajilla"}, {"codigo": "pf_hembra", "nombre": "PF hembra"}, {"codigo": "valvula_antifraude", "nombre": "Válvula antifraude"}, {"codigo": "valvula_paso", "nombre": "Válvula de paso"}, {"codigo": "teflon", "nombre": "Teflón"}, {"codigo": "sellos", "nombre": "Sellos"}, {"codigo": "tuberia_pf", "nombre": "Tubería PF"}, {"codigo": "pf_a_pf", "nombre": "PF a PF"}]	\N	\N	\N	\N	f	702	t	2026-11-21 18:45:37.833409-05	7. Instalaciones y adecuaciones	\N
278	23	inst_materiales	Materiales usados	opciones	f	[{"codigo": "union_simple_pvc", "nombre": "Unión simple PVC"}, {"codigo": "codo_90_pvc", "nombre": "Codo 90 PVC"}, {"codigo": "adaptador_macho_pvc", "nombre": "Adaptador macho PVC"}, {"codigo": "adaptador_hembra_pvc", "nombre": "Adaptador hembra PVC"}, {"codigo": "buje_soldado", "nombre": "Buje soldado"}, {"codigo": "valvula_incorporacion", "nombre": "Válvula de incorporación"}, {"codigo": "buje_roscado", "nombre": "Buje roscado"}, {"codigo": "tapon_soldado", "nombre": "Tapón soldado"}, {"codigo": "tapon_roscado", "nombre": "Tapón roscado"}, {"codigo": "tee_pvc", "nombre": "Tee PVC"}, {"codigo": "galapago", "nombre": "Galápago"}, {"codigo": "pf_macho", "nombre": "PF macho"}, {"codigo": "collar_derivacion", "nombre": "Collar de derivación"}, {"codigo": "tuberia_pvc", "nombre": "Tubería PVC"}, {"codigo": "losa_concreto", "nombre": "Losa de concreto"}, {"codigo": "soldadura_liquida", "nombre": "Soldadura líquida"}, {"codigo": "cajilla", "nombre": "Cajilla"}, {"codigo": "pf_hembra", "nombre": "PF hembra"}, {"codigo": "valvula_antifraude", "nombre": "Válvula antifraude"}, {"codigo": "valvula_paso", "nombre": "Válvula de paso"}, {"codigo": "teflon", "nombre": "Teflón"}, {"codigo": "sellos", "nombre": "Sellos"}, {"codigo": "tuberia_pf", "nombre": "Tubería PF"}, {"codigo": "pf_a_pf", "nombre": "PF a PF"}]	\N	\N	\N	\N	f	702	t	2026-11-21 18:45:37.833528-05	7. Instalaciones y adecuaciones	\N
279	24	inst_mat_cantidades	Cantidades y diámetros de los materiales	texto	f	\N	\N	300	\N	Texto libre. Ejemplo: codo 90 PVC ½: 2; tubería PVC ½: 3 m.	f	703	t	2026-11-21 18:45:37.833637-05	7. Instalaciones y adecuaciones	\N
280	23	inst_mat_cantidades	Cantidades y diámetros de los materiales	texto	f	\N	\N	300	\N	Texto libre. Ejemplo: codo 90 PVC ½: 2; tubería PVC ½: 3 m.	f	703	t	2026-11-21 18:45:37.833655-05	7. Instalaciones y adecuaciones	\N
281	24	mi_lectura	Medidor instalado · Lectura (enteros y decimales del registro)	decimal	t	\N	0	99999999	m³	\N	f	704	t	2026-11-21 18:45:37.833672-05	7. Instalaciones y adecuaciones	\N
282	23	mi_lectura	Medidor instalado · Lectura (enteros y decimales del registro)	decimal	f	\N	0	99999999	m³	\N	f	704	t	2026-11-21 18:45:37.833687-05	7. Instalaciones y adecuaciones	\N
283	24	mi_marca	Medidor instalado · Marca	texto	f	\N	\N	30	\N	\N	f	705	t	2026-11-21 18:45:37.833702-05	7. Instalaciones y adecuaciones	\N
284	23	mi_marca	Medidor instalado · Marca	texto	f	\N	\N	30	\N	\N	f	705	t	2026-11-21 18:45:37.833716-05	7. Instalaciones y adecuaciones	\N
287	24	mi_serial	Medidor instalado · Serial	texto	f	\N	\N	30	\N	Si no se alcanza a leer, deje vacío y marque «Serial ilegible».	f	707	t	2026-11-21 18:45:37.833759-05	7. Instalaciones y adecuaciones	\N
288	23	mi_serial	Medidor instalado · Serial	texto	f	\N	\N	30	\N	Si no se alcanza a leer, deje vacío y marque «Serial ilegible».	f	707	t	2026-11-21 18:45:37.833775-05	7. Instalaciones y adecuaciones	\N
289	24	mi_serial_ilegible	Medidor instalado · Serial ilegible	si_no	f	\N	\N	\N	\N	\N	f	708	t	2026-11-21 18:45:37.833791-05	7. Instalaciones y adecuaciones	\N
290	23	mi_serial_ilegible	Medidor instalado · Serial ilegible	si_no	f	\N	\N	\N	\N	\N	f	708	t	2026-11-21 18:45:37.833807-05	7. Instalaciones y adecuaciones	\N
291	24	mi_diametro	Medidor instalado · Diámetro	opcion	f	[{"codigo": "media", "nombre": "½ pulgada"}, {"codigo": "tres_cuartos", "nombre": "¾ pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "una_media", "nombre": "1½ pulgadas"}, {"codigo": "dos", "nombre": "2 pulgadas"}, {"codigo": "tres", "nombre": "3 pulgadas"}, {"codigo": "cuatro", "nombre": "4 pulgadas"}]	\N	\N	\N	\N	f	709	t	2026-11-21 18:45:37.833826-05	7. Instalaciones y adecuaciones	\N
292	23	mi_diametro	Medidor instalado · Diámetro	opcion	f	[{"codigo": "media", "nombre": "½ pulgada"}, {"codigo": "tres_cuartos", "nombre": "¾ pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "una_media", "nombre": "1½ pulgadas"}, {"codigo": "dos", "nombre": "2 pulgadas"}, {"codigo": "tres", "nombre": "3 pulgadas"}, {"codigo": "cuatro", "nombre": "4 pulgadas"}]	\N	\N	\N	\N	f	709	t	2026-11-21 18:45:37.833884-05	7. Instalaciones y adecuaciones	\N
293	24	mi_precinto_tipo	Medidor instalado · Tipo de precintos	texto	f	\N	\N	30	\N	\N	f	710	t	2026-11-21 18:45:37.833923-05	7. Instalaciones y adecuaciones	\N
294	23	mi_precinto_tipo	Medidor instalado · Tipo de precintos	texto	f	\N	\N	30	\N	\N	f	710	t	2026-11-21 18:45:37.833939-05	7. Instalaciones y adecuaciones	\N
295	24	mi_precinto_serie	Medidor instalado · Serie de precintos	texto	f	\N	\N	30	\N	\N	f	711	t	2026-11-21 18:45:37.833955-05	7. Instalaciones y adecuaciones	\N
296	23	mi_precinto_serie	Medidor instalado · Serie de precintos	texto	f	\N	\N	30	\N	\N	f	711	t	2026-11-21 18:45:37.833971-05	7. Instalaciones y adecuaciones	\N
297	24	mi_anio	Medidor instalado · Año de fabricación	entero	f	\N	1950	2100	\N	\N	f	712	t	2026-11-21 18:45:37.833987-05	7. Instalaciones y adecuaciones	\N
298	23	mi_anio	Medidor instalado · Año de fabricación	entero	f	\N	1950	2100	\N	\N	f	712	t	2026-11-21 18:45:37.834002-05	7. Instalaciones y adecuaciones	\N
299	24	inst_forma_pago	Forma de pago	opcion	f	[{"codigo": "contado", "nombre": "Contado en la próxima facturación"}, {"codigo": "financiado", "nombre": "Financiado"}, {"codigo": "provisional", "nombre": "Provisional"}]	\N	\N	\N	\N	f	713	t	2026-11-21 18:45:37.834018-05	7. Instalaciones y adecuaciones	\N
300	23	inst_forma_pago	Forma de pago	opcion	f	[{"codigo": "contado", "nombre": "Contado en la próxima facturación"}, {"codigo": "financiado", "nombre": "Financiado"}, {"codigo": "provisional", "nombre": "Provisional"}]	\N	\N	\N	\N	f	713	t	2026-11-21 18:45:37.834046-05	7. Instalaciones y adecuaciones	\N
301	25	atendio_nombre	Nombre de quien atendió	texto	f	\N	\N	60	\N	Solo el nombre; sin cédula ni teléfono.	t	910	t	2026-11-21 18:45:37.839377-05	10. Quién atendió	{"campo": "firma_atendio", "no_es": "nadie_atendio"}
302	25	atendio_relacion	Relación con el predio	opcion	f	[{"codigo": "propietario", "nombre": "Propietario"}, {"codigo": "familiar_propietario", "nombre": "Familiar del propietario"}, {"codigo": "arrendatario", "nombre": "Arrendatario (inquilino)"}, {"codigo": "poseedor", "nombre": "Poseedor"}, {"codigo": "residente", "nombre": "Residente u ocupante"}, {"codigo": "administrador", "nombre": "Administrador o encargado"}, {"codigo": "trabajador", "nombre": "Trabajador del predio (empleado, doméstico)"}, {"codigo": "otro", "nombre": "Otro (¿cuál?)"}]	\N	\N	\N	\N	f	911	t	2026-11-21 18:45:37.839621-05	10. Quién atendió	{"campo": "firma_atendio", "no_es": "nadie_atendio"}
303	25	atendio_relacion_otra	¿Cuál otra relación?	texto	f	\N	\N	40	\N	No escriba nombres.	f	912	t	2026-11-21 18:45:37.839685-05	10. Quién atendió	{"es": "otro", "campo": "atendio_relacion"}
304	24	atendio_nombre	Nombre de quien atendió	texto	f	\N	\N	60	\N	Solo el nombre; sin cédula ni teléfono.	t	910	t	2026-11-21 18:45:37.83971-05	10. Quién atendió	{"campo": "firma_atendio", "no_es": "nadie_atendio"}
305	24	atendio_relacion	Relación con el predio	opcion	f	[{"codigo": "propietario", "nombre": "Propietario"}, {"codigo": "familiar_propietario", "nombre": "Familiar del propietario"}, {"codigo": "arrendatario", "nombre": "Arrendatario (inquilino)"}, {"codigo": "poseedor", "nombre": "Poseedor"}, {"codigo": "residente", "nombre": "Residente u ocupante"}, {"codigo": "administrador", "nombre": "Administrador o encargado"}, {"codigo": "trabajador", "nombre": "Trabajador del predio (empleado, doméstico)"}, {"codigo": "otro", "nombre": "Otro (¿cuál?)"}]	\N	\N	\N	\N	f	911	t	2026-11-21 18:45:37.839734-05	10. Quién atendió	{"campo": "firma_atendio", "no_es": "nadie_atendio"}
306	24	atendio_relacion_otra	¿Cuál otra relación?	texto	f	\N	\N	40	\N	No escriba nombres.	f	912	t	2026-11-21 18:45:37.839783-05	10. Quién atendió	{"es": "otro", "campo": "atendio_relacion"}
307	23	atendio_nombre	Nombre de quien atendió	texto	f	\N	\N	60	\N	Solo el nombre; sin cédula ni teléfono.	t	910	t	2026-11-21 18:45:37.839805-05	10. Quién atendió	{"campo": "firma_atendio", "no_es": "nadie_atendio"}
308	23	atendio_relacion	Relación con el predio	opcion	f	[{"codigo": "propietario", "nombre": "Propietario"}, {"codigo": "familiar_propietario", "nombre": "Familiar del propietario"}, {"codigo": "arrendatario", "nombre": "Arrendatario (inquilino)"}, {"codigo": "poseedor", "nombre": "Poseedor"}, {"codigo": "residente", "nombre": "Residente u ocupante"}, {"codigo": "administrador", "nombre": "Administrador o encargado"}, {"codigo": "trabajador", "nombre": "Trabajador del predio (empleado, doméstico)"}, {"codigo": "otro", "nombre": "Otro (¿cuál?)"}]	\N	\N	\N	\N	f	911	t	2026-11-21 18:45:37.839827-05	10. Quién atendió	{"campo": "firma_atendio", "no_es": "nadie_atendio"}
309	23	atendio_relacion_otra	¿Cuál otra relación?	texto	f	\N	\N	40	\N	No escriba nombres.	f	912	t	2026-11-21 18:45:37.839872-05	10. Quién atendió	{"es": "otro", "campo": "atendio_relacion"}
310	26	atendio_nombre	Nombre de quien atendió	texto	f	\N	\N	60	\N	Solo el nombre; sin cédula ni teléfono.	t	910	t	2026-11-21 18:45:37.839893-05	10. Quién atendió	{"campo": "firma_atendio", "no_es": "nadie_atendio"}
311	26	atendio_relacion	Relación con el predio	opcion	f	[{"codigo": "propietario", "nombre": "Propietario"}, {"codigo": "familiar_propietario", "nombre": "Familiar del propietario"}, {"codigo": "arrendatario", "nombre": "Arrendatario (inquilino)"}, {"codigo": "poseedor", "nombre": "Poseedor"}, {"codigo": "residente", "nombre": "Residente u ocupante"}, {"codigo": "administrador", "nombre": "Administrador o encargado"}, {"codigo": "trabajador", "nombre": "Trabajador del predio (empleado, doméstico)"}, {"codigo": "otro", "nombre": "Otro (¿cuál?)"}]	\N	\N	\N	\N	f	911	t	2026-11-21 18:45:37.839914-05	10. Quién atendió	{"campo": "firma_atendio", "no_es": "nadie_atendio"}
312	26	atendio_relacion_otra	¿Cuál otra relación?	texto	f	\N	\N	40	\N	No escriba nombres.	f	912	t	2026-11-21 18:45:37.83996-05	10. Quién atendió	{"es": "otro", "campo": "atendio_relacion"}
313	24	inst_modalidad	Instalación o cambio de medidor	opcion	t	[{"codigo": "instalacion", "nombre": "Instalación de medidor"}, {"codigo": "cambio", "nombre": "Cambio de medidor"}]	\N	\N	\N	Con «Cambio de medidor» aparecen los datos del medidor retirado.	f	100	t	2026-11-21 18:45:37.888012-05	1. Datos básicos	\N
115	24	me_marca	Medidor retirado · Marca	texto	f	\N	\N	30	\N	\N	f	202	t	2026-11-21 18:45:37.82952-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
123	24	me_serial	Medidor retirado · Serial	texto	f	\N	\N	30	\N	Si no se alcanza a leer, deje vacío y marque «Serial ilegible».	f	204	t	2026-11-21 18:45:37.829623-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
127	24	me_serial_ilegible	Medidor retirado · Serial ilegible	si_no	f	\N	\N	\N	\N	\N	f	205	t	2026-11-21 18:45:37.829677-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
131	24	me_diametro	Medidor retirado · Diámetro	opcion	f	[{"codigo": "media", "nombre": "½ pulgada"}, {"codigo": "tres_cuartos", "nombre": "¾ pulgada"}, {"codigo": "una", "nombre": "1 pulgada"}, {"codigo": "una_media", "nombre": "1½ pulgadas"}, {"codigo": "dos", "nombre": "2 pulgadas"}, {"codigo": "tres", "nombre": "3 pulgadas"}, {"codigo": "cuatro", "nombre": "4 pulgadas"}]	\N	\N	\N	\N	f	206	t	2026-11-21 18:45:37.829769-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
135	24	me_precinto_tipo	Medidor retirado · Tipo de precintos	texto	f	\N	\N	30	\N	\N	f	207	t	2026-11-21 18:45:37.829913-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
139	24	me_precinto_serie	Medidor retirado · Serie de precintos	texto	f	\N	\N	30	\N	\N	f	208	t	2026-11-21 18:45:37.829972-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
143	24	me_anio	Medidor retirado · Año de fabricación	entero	f	\N	1950	2100	\N	\N	f	209	t	2026-11-21 18:45:37.830029-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
147	24	me_talco	Talco	opciones	f	[{"codigo": "opaco", "nombre": "Opaco"}, {"codigo": "partido_fisurado", "nombre": "Partido o fisurado"}, {"codigo": "perforado", "nombre": "Perforado"}, {"codigo": "transparente_ok", "nombre": "Transparente / ok"}, {"codigo": "no_tiene", "nombre": "No tiene"}, {"codigo": "destruido", "nombre": "Destruido"}, {"codigo": "ilegible", "nombre": "Ilegible"}, {"codigo": "vidrio_roto", "nombre": "Vidrio roto"}, {"codigo": "sin_agujas", "nombre": "Sin agujas"}]	\N	\N	\N	\N	f	301	t	2026-11-21 18:45:37.830122-05	3. Estado del medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
151	24	me_cuerpo	Cuerpo	opciones	f	[{"codigo": "perforado", "nombre": "Perforado"}, {"codigo": "fisurado_roto", "nombre": "Fisurado o roto"}, {"codigo": "conexion_invertida", "nombre": "Conexión invertida"}, {"codigo": "ok", "nombre": "Ok"}]	\N	\N	\N	\N	f	302	t	2026-11-21 18:45:37.830286-05	3. Estado del medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
159	24	req_cambio_medidor	¿Se requiere cambio de medidor?	si_no	f	\N	\N	\N	\N	\N	f	304	t	2026-11-21 18:45:37.830514-05	3. Estado del medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
163	24	calib_realizada	Prueba de calibración: ¿se realizó?	si_no	f	\N	\N	\N	\N	\N	f	305	t	2026-11-21 18:45:37.830605-05	3. Estado del medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
155	24	me_registro	Registro	opciones	f	[{"codigo": "detenido", "nombre": "Medidor detenido"}, {"codigo": "giro_irregular", "nombre": "Giro irregular"}, {"codigo": "obstruido", "nombre": "Medidor obstruido"}, {"codigo": "mal_estado", "nombre": "Registro en mal estado"}]	\N	\N	\N	\N	f	303	t	2026-11-21 18:45:37.830398-05	3. Estado del medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
167	24	calib_vol_patron	Volumen del patrón	decimal	f	\N	0	100000	L	\N	f	306	t	2026-11-21 18:45:37.830671-05	3. Estado del medidor retirado	{"es": true, "campo": "calib_realizada"}
171	24	calib_vol_cliente	Volumen del cliente	decimal	f	\N	0	100000	L	\N	f	307	t	2026-11-21 18:45:37.830744-05	3. Estado del medidor retirado	{"es": true, "campo": "calib_realizada"}
175	24	calib_error_pct	Error de la prueba	decimal	f	\N	-100	1000	%	\N	f	308	t	2026-11-21 18:45:37.830816-05	3. Estado del medidor retirado	{"es": true, "campo": "calib_realizada"}
111	24	me_lectura	Medidor retirado · Lectura (enteros y decimales del registro)	decimal	t	\N	0	99999999	m³	\N	f	201	t	2026-11-21 18:45:37.829467-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
314	25	me_r	Medidor encontrado · R del medidor	opcion	f	[{"codigo": "r80", "nombre": "R80"}, {"codigo": "r160", "nombre": "R160"}, {"codigo": "r200", "nombre": "R200"}, {"codigo": "r315", "nombre": "R315"}, {"codigo": "r400", "nombre": "R400 (o superior)"}, {"codigo": "no_legible", "nombre": "No legible"}]	\N	\N	\N	\N	f	210	t	2026-11-21 18:45:37.890881-05	2. Medidor encontrado	\N
315	25	me_tipo_medidor	Medidor encontrado · Tipo de medidor	opcion	f	[{"codigo": "volumetrico", "nombre": "Volumétrico"}, {"codigo": "velocidad", "nombre": "Velocidad"}, {"codigo": "woltman", "nombre": "Woltman"}, {"codigo": "ultrasonico", "nombre": "Ultrasónico"}, {"codigo": "electromagnetico", "nombre": "Electromagnético"}]	\N	\N	\N	\N	f	211	t	2026-11-21 18:45:37.891078-05	2. Medidor encontrado	\N
316	24	me_r	Medidor retirado · R del medidor	opcion	t	[{"codigo": "r80", "nombre": "R80"}, {"codigo": "r160", "nombre": "R160"}, {"codigo": "r200", "nombre": "R200"}, {"codigo": "r315", "nombre": "R315"}, {"codigo": "r400", "nombre": "R400 (o superior)"}, {"codigo": "no_legible", "nombre": "No legible"}]	\N	\N	\N	\N	f	210	t	2026-11-21 18:45:37.891127-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
317	24	me_tipo_medidor	Medidor retirado · Tipo de medidor	opcion	t	[{"codigo": "volumetrico", "nombre": "Volumétrico"}, {"codigo": "velocidad", "nombre": "Velocidad"}, {"codigo": "woltman", "nombre": "Woltman"}, {"codigo": "ultrasonico", "nombre": "Ultrasónico"}, {"codigo": "electromagnetico", "nombre": "Electromagnético"}]	\N	\N	\N	\N	f	211	t	2026-11-21 18:45:37.891179-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
318	23	me_r	Medidor encontrado · R del medidor	opcion	f	[{"codigo": "r80", "nombre": "R80"}, {"codigo": "r160", "nombre": "R160"}, {"codigo": "r200", "nombre": "R200"}, {"codigo": "r315", "nombre": "R315"}, {"codigo": "r400", "nombre": "R400 (o superior)"}, {"codigo": "no_legible", "nombre": "No legible"}]	\N	\N	\N	\N	f	210	t	2026-11-21 18:45:37.891232-05	2. Medidor encontrado	\N
319	23	me_tipo_medidor	Medidor encontrado · Tipo de medidor	opcion	f	[{"codigo": "volumetrico", "nombre": "Volumétrico"}, {"codigo": "velocidad", "nombre": "Velocidad"}, {"codigo": "woltman", "nombre": "Woltman"}, {"codigo": "ultrasonico", "nombre": "Ultrasónico"}, {"codigo": "electromagnetico", "nombre": "Electromagnético"}]	\N	\N	\N	\N	f	211	t	2026-11-21 18:45:37.891275-05	2. Medidor encontrado	\N
320	26	me_r	Medidor encontrado · R del medidor	opcion	f	[{"codigo": "r80", "nombre": "R80"}, {"codigo": "r160", "nombre": "R160"}, {"codigo": "r200", "nombre": "R200"}, {"codigo": "r315", "nombre": "R315"}, {"codigo": "r400", "nombre": "R400 (o superior)"}, {"codigo": "no_legible", "nombre": "No legible"}]	\N	\N	\N	\N	f	210	t	2026-11-21 18:45:37.891318-05	2. Medidor encontrado	\N
321	26	me_tipo_medidor	Medidor encontrado · Tipo de medidor	opcion	f	[{"codigo": "volumetrico", "nombre": "Volumétrico"}, {"codigo": "velocidad", "nombre": "Velocidad"}, {"codigo": "woltman", "nombre": "Woltman"}, {"codigo": "ultrasonico", "nombre": "Ultrasónico"}, {"codigo": "electromagnetico", "nombre": "Electromagnético"}]	\N	\N	\N	\N	f	211	t	2026-11-21 18:45:37.891358-05	2. Medidor encontrado	\N
322	24	mi_r	Medidor instalado · R del medidor	opcion	t	[{"codigo": "r80", "nombre": "R80"}, {"codigo": "r160", "nombre": "R160"}, {"codigo": "r200", "nombre": "R200"}, {"codigo": "r315", "nombre": "R315"}, {"codigo": "r400", "nombre": "R400 (o superior)"}, {"codigo": "no_legible", "nombre": "No legible"}]	\N	\N	\N	\N	f	712	t	2026-11-21 18:45:37.891528-05	7. Instalaciones y adecuaciones	\N
323	24	mi_tipo_medidor	Medidor instalado · Tipo de medidor	opcion	t	[{"codigo": "volumetrico", "nombre": "Volumétrico"}, {"codigo": "velocidad", "nombre": "Velocidad"}, {"codigo": "woltman", "nombre": "Woltman"}, {"codigo": "ultrasonico", "nombre": "Ultrasónico"}, {"codigo": "electromagnetico", "nombre": "Electromagnético"}]	\N	\N	\N	\N	f	712	t	2026-11-21 18:45:37.89172-05	7. Instalaciones y adecuaciones	\N
324	23	mi_r	Medidor instalado · R del medidor	opcion	f	[{"codigo": "r80", "nombre": "R80"}, {"codigo": "r160", "nombre": "R160"}, {"codigo": "r200", "nombre": "R200"}, {"codigo": "r315", "nombre": "R315"}, {"codigo": "r400", "nombre": "R400 (o superior)"}, {"codigo": "no_legible", "nombre": "No legible"}]	\N	\N	\N	\N	f	712	t	2026-11-21 18:45:37.891769-05	7. Instalaciones y adecuaciones	\N
325	23	mi_tipo_medidor	Medidor instalado · Tipo de medidor	opcion	f	[{"codigo": "volumetrico", "nombre": "Volumétrico"}, {"codigo": "velocidad", "nombre": "Velocidad"}, {"codigo": "woltman", "nombre": "Woltman"}, {"codigo": "ultrasonico", "nombre": "Ultrasónico"}, {"codigo": "electromagnetico", "nombre": "Electromagnético"}]	\N	\N	\N	\N	f	712	t	2026-11-21 18:45:37.891809-05	7. Instalaciones y adecuaciones	\N
326	24	inst_lectura_remota	Lectura remota	opciones	f	[{"codigo": "remota", "nombre": "Se instaló lectura remota"}, {"codigo": "remota_pila", "nombre": "Se instaló lectura remota con pila"}]	\N	\N	\N	Marque solo lo que se instaló; si no se instaló, déjelo vacío.	f	714	t	2026-11-21 18:45:37.89194-05	7. Instalaciones y adecuaciones	\N
327	24	inst_reubica_cajilla	¿Se reubicó la cajilla?	si_no	t	\N	\N	\N	\N	\N	f	715	t	2026-11-21 18:45:37.892197-05	7. Instalaciones y adecuaciones	\N
328	23	inst_reubica_cajilla	¿Se reubicó la cajilla?	si_no	t	\N	\N	\N	\N	\N	f	715	t	2026-11-21 18:45:37.89236-05	7. Instalaciones y adecuaciones	\N
118	25	me_tipo	Medidor encontrado · Tipo	texto	f	\N	\N	30	\N	\N	f	203	f	2026-11-21 18:45:37.829558-05	2. Medidor encontrado	\N
120	23	me_tipo	Medidor encontrado · Tipo	texto	f	\N	\N	30	\N	\N	f	203	f	2026-11-21 18:45:37.829584-05	2. Medidor encontrado	\N
121	26	me_tipo	Medidor encontrado · Tipo	texto	f	\N	\N	30	\N	\N	f	203	f	2026-11-21 18:45:37.829597-05	2. Medidor encontrado	\N
285	24	mi_tipo	Medidor instalado · Tipo	texto	f	\N	\N	30	\N	\N	f	706	f	2026-11-21 18:45:37.833731-05	7. Instalaciones y adecuaciones	\N
286	23	mi_tipo	Medidor instalado · Tipo	texto	f	\N	\N	30	\N	\N	f	706	f	2026-11-21 18:45:37.833745-05	7. Instalaciones y adecuaciones	\N
119	24	me_tipo	Medidor retirado · Tipo	texto	f	\N	\N	30	\N	\N	f	203	f	2026-11-21 18:45:37.829571-05	2. Medidor retirado	{"es": "cambio", "campo": "inst_modalidad"}
\.


--
-- Data for Name: tipo_fotos; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.tipo_fotos (id, tipo_id, codigo, nombre, obligatoria, soporte_inefectiva, orden, activo, creado_en) FROM stdin;
1	22	fachada_nomenclatura	Fachada con nomenclatura	t	t	1	t	2026-11-21 18:45:37.729915-05
2	22	predio_lote	Predio o lote	t	t	2	t	2026-11-21 18:45:37.730137-05
3	22	vecino_referencia	Vecino o referencia	t	f	3	t	2026-11-21 18:45:37.730148-05
4	21	punto_conexion	Punto de conexión a la red	t	f	1	t	2026-11-21 18:45:37.730156-05
5	21	recorrido	Recorrido de la acometida	t	f	2	t	2026-11-21 18:45:37.730161-05
6	21	caja_medidor	Caja o medidor (si existe)	f	f	3	t	2026-11-21 18:45:37.730167-05
7	20	medidor_lectura_serial	Medidor con lectura y serial	t	f	1	t	2026-11-21 18:45:37.730173-05
8	20	valvula_cerrada	Válvula cerrada	t	f	2	t	2026-11-21 18:45:37.730179-05
9	20	sello_instalado	Sello instalado	t	f	3	t	2026-11-21 18:45:37.730185-05
10	19	antes	Antes del corte	t	f	1	t	2026-11-21 18:45:37.730191-05
11	19	punto_corte	Punto de corte	t	f	2	t	2026-11-21 18:45:37.730195-05
12	19	tapon_retiro	Tapón o retiro	t	f	3	t	2026-11-21 18:45:37.7302-05
13	19	reposicion_pavimento	Reposición del pavimento (si aplica)	f	f	4	t	2026-11-21 18:45:37.730205-05
14	18	estado_sello_corte	Estado del sello o del corte	t	f	1	t	2026-11-21 18:45:37.730212-05
15	17	medidor_lectura_inicial	Medidor con lectura inicial	t	f	1	t	2026-11-21 18:45:37.730217-05
16	17	servicio_restablecido	Servicio restablecido	t	f	2	t	2026-11-21 18:45:37.730223-05
17	16	medidor_lectura_inicial	Medidor con lectura inicial	t	f	1	t	2026-11-21 18:45:37.73023-05
18	16	servicio_restablecido	Servicio restablecido	t	f	2	t	2026-11-21 18:45:37.730236-05
19	15	medidor_retirado	Medidor retirado, con serial y lectura	t	f	1	t	2026-11-21 18:45:37.730243-05
20	15	medidor_nuevo	Medidor nuevo, con serial y lectura	t	f	2	t	2026-11-21 18:45:37.730248-05
26	15	fachada_predio	Fachada o predio	f	t	90	t	2026-11-21 18:45:37.730678-05
27	16	fachada_predio	Fachada o predio	f	t	90	t	2026-11-21 18:45:37.730702-05
28	17	fachada_predio	Fachada o predio	f	t	90	t	2026-11-21 18:45:37.73071-05
29	18	fachada_predio	Fachada o predio	f	t	90	t	2026-11-21 18:45:37.730716-05
30	19	fachada_predio	Fachada o predio	f	t	90	t	2026-11-21 18:45:37.730721-05
31	20	fachada_predio	Fachada o predio	f	t	90	t	2026-11-21 18:45:37.730727-05
32	21	fachada_predio	Fachada o predio	f	t	90	t	2026-11-21 18:45:37.730732-05
22	24	sitio_terminado	Sitio terminado	t	f	2	f	2026-11-21 18:45:37.730259-05
23	23	punto_conexion	Punto de conexión a la red	t	f	1	f	2026-11-21 18:45:37.730265-05
24	23	acometida_terminada	Acometida terminada	t	f	2	f	2026-11-21 18:45:37.73027-05
25	25	evidencia	Evidencia de lo revisado	t	f	1	f	2026-11-21 18:45:37.730276-05
36	26	fachada_predio	Fachada o predio	t	t	1	t	2026-11-21 18:45:37.83506-05
37	26	medidor_encontrado	Medidor encontrado	f	f	2	t	2026-11-21 18:45:37.835092-05
38	26	acometida_encontrada	Acometida encontrada	f	f	3	t	2026-11-21 18:45:37.8351-05
39	26	acta_fisica	Acta física firmada	t	f	9	t	2026-11-21 18:45:37.835106-05
41	25	medidor_encontrado	Medidor encontrado	f	f	2	t	2026-11-21 18:45:37.835116-05
42	25	acometida_encontrada	Acometida encontrada	f	f	3	t	2026-11-21 18:45:37.835122-05
43	25	acta_fisica	Acta física firmada	t	f	9	t	2026-11-21 18:45:37.835128-05
46	24	acometida_encontrada	Acometida encontrada	f	f	3	t	2026-11-21 18:45:37.835144-05
48	24	acta_fisica	Acta física firmada	t	f	9	t	2026-11-21 18:45:37.835155-05
50	23	medidor_encontrado	Medidor encontrado	f	f	2	t	2026-11-21 18:45:37.835165-05
51	23	acometida_instalada	Acometida instalada	t	f	4	t	2026-11-21 18:45:37.835174-05
52	23	acta_fisica	Acta física firmada	t	f	9	t	2026-11-21 18:45:37.835181-05
33	23	fachada_predio	Fachada o predio	t	t	1	t	2026-11-21 18:45:37.730738-05
34	24	fachada_predio	Fachada o predio	t	t	1	t	2026-11-21 18:45:37.730744-05
35	25	fachada_predio	Fachada o predio	t	t	1	t	2026-11-21 18:45:37.73075-05
21	24	medidor_instalado	Medidor instalado, con serial y lectura	t	f	4	t	2026-11-21 18:45:37.730254-05
45	24	medidor_encontrado	Medidor retirado	f	f	2	t	2026-11-21 18:45:37.835138-05
\.


--
-- Data for Name: tipos_reporte; Type: TABLE DATA; Schema: campo; Owner: -
--

COPY campo.tipos_reporte (id, grupo_id, codigo, nombre, orden, exige_texto, exige_subtipo, activo, creado_en, fotos_min, fotos_max, requiere_contrato, genera_resultado, prefijo_consecutivo, limite_ventana) FROM stdin;
1	1	predio_sin_contrato	Predio con servicio sin contrato asignado (por verificar)	6	f	f	t	2026-11-21 18:45:37.69-05	\N	\N	opcional	f	\N	\N
2	1	uso_distinto	Posible uso distinto del declarado	5	f	f	t	2026-11-21 18:45:37.690315-05	\N	\N	opcional	f	\N	\N
3	1	anomalia_medicion	Posible anomalía en la medición	4	f	f	t	2026-11-21 18:45:37.690329-05	\N	\N	opcional	f	\N	\N
4	1	fraude	Posible fraude	3	f	f	t	2026-11-21 18:45:37.690344-05	\N	\N	opcional	f	\N	\N
5	1	reconexion	Posible reconexión	2	f	f	t	2026-11-21 18:45:37.690349-05	\N	\N	opcional	f	\N	\N
6	1	acometida_sin_permiso	Posible acometida sin permiso	1	f	f	t	2026-11-21 18:45:37.690355-05	\N	\N	opcional	f	\N	\N
7	2	tapa_caja_acueducto	Tapa o caja de medidor o válvula rota o faltante	2	f	f	t	2026-11-21 18:45:37.690367-05	\N	\N	opcional	f	\N	\N
8	2	dano_red_acueducto	Daño en la red (fuga visible)	1	f	f	t	2026-11-21 18:45:37.690375-05	\N	\N	opcional	f	\N	\N
9	3	conexion_errada	Conexión errada de alcantarillado	4	f	f	t	2026-11-21 18:45:37.690383-05	\N	\N	opcional	f	\N	\N
10	3	rejilla_sumidero	Daño en rejilla o sumidero	3	f	f	t	2026-11-21 18:45:37.690455-05	\N	\N	opcional	f	\N	\N
11	3	tapa_manhole	Daño en tapa de manhole (rota, hundida o faltante)	2	f	f	t	2026-11-21 18:45:37.690488-05	\N	\N	opcional	f	\N	\N
12	3	dano_red_alcantarillado	Daño en la red (hundimiento, colapso, rebose)	1	f	f	t	2026-11-21 18:45:37.690509-05	\N	\N	opcional	f	\N	\N
13	4	dano_obra_terceros	Daño por obra de terceros	1	f	f	t	2026-11-21 18:45:37.690541-05	\N	\N	opcional	f	\N	\N
14	5	otro	Otro	1	t	f	t	2026-11-21 18:45:37.690566-05	\N	\N	opcional	f	\N	\N
15	6	cambio_medidor	Cambio de medidor	8	f	f	f	2026-11-21 18:45:37.72877-05	2	6	si	t	CME	20
16	6	reconexion_servicio	Reconexión del servicio (tras un corte)	7	f	t	f	2026-11-21 18:45:37.728933-05	2	4	si	t	REC	20
17	6	reinstalacion	Reinstalación del servicio (tras una suspensión)	6	f	f	f	2026-11-21 18:45:37.728947-05	2	4	si	t	REI	20
18	6	verificacion_posterior	Verificación posterior al corte o a la suspensión	5	f	f	f	2026-11-21 18:45:37.728956-05	1	4	si	t	VER	20
19	6	corte	Corte	4	f	t	f	2026-11-21 18:45:37.728967-05	3	6	si	t	COR	20
20	6	suspension	Suspensión	3	f	f	f	2026-11-21 18:45:37.728974-05	3	6	si	t	SUS	20
21	6	levantamiento_acometida	Levantamiento de la acometida	2	f	f	f	2026-11-21 18:45:37.728991-05	2	6	si	t	LEV	20
22	6	investigacion_ubicacion	Investigación de ubicación del predio	1	f	f	f	2026-11-21 18:45:37.729001-05	3	6	si	t	INV	20
25	8	revision_pqr	Revisión PQR	1	f	f	f	2026-11-21 18:45:37.729034-05	2	6	si	t	PQR	20
24	7	instalacion_medidor	Instalación de medidor	1	f	f	f	2026-11-21 18:45:37.729023-05	3	7	si	t	IME	20
23	7	instalacion_acometida	Instalación de acometida	2	f	f	f	2026-11-21 18:45:37.729012-05	3	6	opcional	t	IAC	20
26	9	revision_previa	Revisiones generales	1	f	f	t	2026-11-21 18:45:37.826661-05	2	6	si	t	RPV	20
27	2	fuga_acometida	Fuga en acometida	3	f	f	t	2026-11-21 18:45:37.968003-05	\N	\N	opcional	f	\N	\N
28	2	caja_medidor_danada	Caja de medidor dañada	4	f	f	t	2026-11-21 18:45:37.968064-05	\N	\N	opcional	f	\N	\N
\.


--
-- Data for Name: cartera_contrato; Type: TABLE DATA; Schema: hechos; Owner: -
--

COPY hechos.cartera_contrato (periodo, contrato, product_id, facturas_vencidas, fecha_instalacion, fecha_ult_pago, ultimo_pago, total_cartera, ciclo) FROM stdin;
\.


--
-- Data for Name: consumo_metodo; Type: TABLE DATA; Schema: hechos; Owner: -
--

COPY hechos.consumo_metodo (periodo, contrato, ciclo, categoria, subcategoria, medidor, consumo_facturado, consumo_cargos, lectura_actual, lectura_anterior, fecha_lectura_actual, fecha_lectura_anterior, observacion, funcion, metodo_calculo, fecha_instalacion, estado_tecnico) FROM stdin;
\.


--
-- Data for Name: cupones_pagos; Type: TABLE DATA; Schema: hechos; Owner: -
--

COPY hechos.cupones_pagos (periodo, contrato, cupon, valor, fecha_pago) FROM stdin;
\.


--
-- Data for Name: facturacion_contratos; Type: TABLE DATA; Schema: hechos; Owner: -
--

COPY hechos.facturacion_contratos (periodo, contrato, ciclo, categoria, subcategoria, concepto, facturado, consumo) FROM stdin;
\.


--
-- Data for Name: reclamos; Type: TABLE DATA; Schema: hechos; Owner: -
--

COPY hechos.reclamos (periodo, contrato, solicitud, fecha_registro, estado, causal, nombre_cliente) FROM stdin;
\.


--
-- Data for Name: barrios_valledupar; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.barrios_valledupar (id, nombre, buscable) FROM stdin;
1	Centro	t
2	Norte	t
3	Los Músicos	t
\.


--
-- Data for Name: cartera_suscripcion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cartera_suscripcion (contrato, estado, identificacion, nombre, correo, telefono, direccion, barrio, categoria, subcategoria, ciclo, facturas_pendientes, deuda_total, saldo_pendiente, saldo_a_favor, valor_reclamo, saldo_financiado, serial_medidor, codigo_reparto, ruta, periodo_carga) FROM stdin;
\.


--
-- Data for Name: catastro_valledupar; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.catastro_valledupar (id, cod_usuario, direccion, barrio, estrato, clase_uso, geom, telefono, telefono_propie, diam_med) FROM stdin;
1	123456	CRA 10 # 5-20	Centro	3	RESIDENCIAL RESIDENCIAL	(-73.25,10.46)	\N	\N	\N
2	123456	CRA 10 # 5-22	Centro	3	COMERCIAL	(-73.2501,10.4601)	\N	\N	\N
3	4321	CLL 20 # 8-15	Barrio Nuevo	9	 COMERCIAL  RESIDENCIAL	(-73.24,10.47)	\N	\N	\N
4	777	CLL 1 # 1-1	Norte	\N	\N	(-73.26,10.45)	\N	\N	\N
\.


--
-- Data for Name: geoportal_auditoria; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.geoportal_auditoria (id, email, accion, referencia, detalle, ip, creado_en) FROM stdin;
1	migracion@analisis_contrato	admin_permiso_inicial_analisis_contrato	\N	{"regla": "ver_comercial o ver_campo o ver_acta o ver_dashboard_campo o ver_dashboard", "marcados": 0}	\N	2026-11-21 18:45:37.924865-05
2	migracion@tecnica_corte8	migracion_tecnica_corte8	\N	{"vista": "redes.v_reportes_comercial", "columna": "campo.reportes.area", "dominio": "tecnica.formulario_clave", "rpc_nuevas": ["geoportal_campo_tec_formulario", "geoportal_campo_tec_preparar_subida", "geoportal_campo_tec_crear_reporte"], "reemplazadas": ["campo.f_autorizar_reporte", "tecnica.f_formularios"], "tipos_agregados": ["fuga_acometida", "caja_medidor_danada"]}	\N	2026-11-21 18:45:37.964012-05
\.


--
-- Data for Name: geoportal_config; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.geoportal_config (id, pausado, pausado_por, pausado_en, aislamiento_tecnica_ok) FROM stdin;
1	f	\N	\N	t
\.


--
-- Data for Name: geoportal_lista_blanca; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.geoportal_lista_blanca (email, nombre, activo, creado_en, creado_por, rol, ver_explorar, ver_focalizacion, ver_comercial, ver_rutas, horario, dias, ver_dashboard, ver_registro_tecnico, ver_dashboard_tecnico, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta, ver_aseo, ver_dashboard_aseo, ver_analisis_contrato) FROM stdin;
\.


--
-- Data for Name: predios_comercial_fuente_local; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.predios_comercial_fuente_local (id, cod_usuario, deuda_total, barrio, estado_predio, tramo_mora) FROM stdin;
1	123456	999999	Centro	\N	\N
2	4321	0	Norte	\N	\N
\.


--
-- Data for Name: config_documentos; Type: TABLE DATA; Schema: salida; Owner: -
--

COPY salida.config_documentos (documento, habilitado, copias_internas, actualizado_por, actualizado_en) FROM stdin;
acta_inspeccion	f	{}	\N	2026-11-21 18:45:37.866008-05
revision_previa	f	{}	\N	2026-11-21 18:45:37.866142-05
revision_pqr	f	{}	\N	2026-11-21 18:45:37.866145-05
instalacion_medidor	f	{}	\N	2026-11-21 18:45:37.866147-05
instalacion_acometida	f	{}	\N	2026-11-21 18:45:37.866148-05
\.


--
-- Data for Name: config_eventos; Type: TABLE DATA; Schema: salida; Owner: -
--

COPY salida.config_eventos (id, documento, habilitado, copias_internas, autor, creado_en) FROM stdin;
\.


--
-- Data for Name: contactos; Type: TABLE DATA; Schema: salida; Owner: -
--

COPY salida.contactos (id, esquema_origen, registro_id, documento, correo, celular, parte, autoriza, texto_version, autor, reservado_en, depurado_en) FROM stdin;
\.


--
-- Data for Name: envio_eventos; Type: TABLE DATA; Schema: salida; Owner: -
--

COPY salida.envio_eventos (id, envio_id, estado_desde, estado_hasta, actor, detalle, creado_en) FROM stdin;
\.


--
-- Data for Name: envios; Type: TABLE DATA; Schema: salida; Owner: -
--

COPY salida.envios (id, contacto_id, esquema_origen, registro_id, documento, consecutivo, destinatario_correo, destinatario_celular, parte, copias_internas, texto_version, constancia, constancia_version, estado, intentos, max_intentos, tomado_hasta, lease_id, ultimo_error, ultimo_cambio_en, creado_en, depurado_en) FROM stdin;
\.


--
-- Data for Name: fallos_encolado; Type: TABLE DATA; Schema: salida; Owner: -
--

COPY salida.fallos_encolado (id, esquema_origen, registro_id, mensaje, creado_en) FROM stdin;
\.


--
-- Data for Name: parametros; Type: TABLE DATA; Schema: salida; Owner: -
--

COPY salida.parametros (clave, valor, descripcion, minimo, maximo, actualizado_en) FROM stdin;
max_intentos	5	Intentos de envío antes de marcar error	1	20	2026-11-21 18:45:37.865797-05
arriendo_segundos	300	Arriendo de un envío tomado (el Dell lo pide en tomar_envios; valor de referencia)	30	3600	2026-11-21 18:45:37.865958-05
sondeo_segundos	60	Cada cuánto consulta el Dell (referencia, no la aplica la base)	10	3600	2026-11-21 18:45:37.86597-05
ventana_posterior_min	30	Minutos tras registrar en que aún se puede reservar el contacto de un registro ya hecho	1	240	2026-11-21 18:45:37.865975-05
retencion_meses	6	Meses tras el último envío exitoso o la anulación para enmascarar los contactos	1	120	2026-11-21 18:45:37.865982-05
\.


--
-- Data for Name: textos_autorizacion; Type: TABLE DATA; Schema: salida; Owner: -
--

COPY salida.textos_autorizacion (version, texto, borrador, creado_por, creado_en) FROM stdin;
1	BORRADOR pendiente de jurídica. Autorizo a EMDUPAR S.A. E.S.P. a tratar mi correo electrónico y mi número de celular únicamente para enviarme la constancia de este registro, de acuerdo con la Ley 1581 de 2012 y la política de tratamiento de datos de la empresa.	t	sistema	2026-11-21 18:45:37.866183-05
\.


--
-- Data for Name: buckets; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.buckets (id, name, public, file_size_limit, allowed_mime_types) FROM stdin;
campo-fotos	campo-fotos	f	2097152	{image/jpeg}
acta-evidencias	acta-evidencias	f	3145728	{image/jpeg}
\.


--
-- Data for Name: objects; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.objects (id, bucket_id, name, metadata, created_at) FROM stdin;
\.


--
-- Data for Name: exclusiones; Type: TABLE DATA; Schema: tecnica; Owner: -
--

COPY tecnica.exclusiones (id, registro_id, lote_id, accion, motivo, autor, creado_en) FROM stdin;
\.


--
-- Data for Name: formulario_variables; Type: TABLE DATA; Schema: tecnica; Owner: -
--

COPY tecnica.formulario_variables (id, formulario, variable_id, orden, obligatoria, alcance, punto_id, activa, creado_en) FROM stdin;
1	entrada	1	1	t	por_planta	\N	t	2026-11-21 18:45:37.959376-05
2	entrada	2	2	f	ambas_plantas	\N	t	2026-11-21 18:45:37.959502-05
3	entrada	3	3	f	ambas_plantas	\N	t	2026-11-21 18:45:37.959507-05
4	entrada	4	4	f	ambas_plantas	\N	t	2026-11-21 18:45:37.959509-05
5	entrada	5	5	f	ambas_plantas	\N	t	2026-11-21 18:45:37.959511-05
\.


--
-- Data for Name: personal_tecnico_eventos; Type: TABLE DATA; Schema: tecnica; Owner: -
--

COPY tecnica.personal_tecnico_eventos (id, persona, tipo_evento, formulario, motivo, autor, creado_en) FROM stdin;
\.


--
-- Data for Name: plantas; Type: TABLE DATA; Schema: tecnica; Owner: -
--

COPY tecnica.plantas (id, codigo, nombre, activa, creado_en) FROM stdin;
1	huaricha	Huaricha	t	2026-11-21 18:45:37.958852-05
2	gota_fria	Gota Fría	t	2026-11-21 18:45:37.95904-05
\.


--
-- Data for Name: puntos; Type: TABLE DATA; Schema: tecnica; Owner: -
--

COPY tecnica.puntos (id, planta_id, codigo, nombre, tipo, activo, creado_en) FROM stdin;
\.


--
-- Data for Name: registros; Type: TABLE DATA; Schema: tecnica; Owner: -
--

COPY tecnica.registros (id, lote_id, formulario, variable_id, planta_id, punto_id, valor, fecha_muestra, hora_muestra, registrado_en, autor, clave_envio) FROM stdin;
\.


--
-- Data for Name: senal_cambio; Type: TABLE DATA; Schema: tecnica; Owner: -
--

COPY tecnica.senal_cambio (id, tabla, planta_id, creado_en) FROM stdin;
\.


--
-- Data for Name: variables; Type: TABLE DATA; Schema: tecnica; Owner: -
--

COPY tecnica.variables (id, codigo, nombre, unidad, categoria, decimales, ref_min, ref_max, activa, creado_en) FROM stdin;
1	caudal_qi	Caudal de ingreso Qi	L/s	caudal	0	\N	\N	t	2026-11-21 18:45:37.959088-05
2	turbiedad_ingreso	Turbiedad de ingreso (Ti)	NTU	fisicoquimico	1	\N	\N	t	2026-11-21 18:45:37.959248-05
3	alcalinidad_ingreso	Alcalinidad de ingreso	mg/L	fisicoquimico	0	\N	\N	t	2026-11-21 18:45:37.959257-05
4	ph_ingreso	pH de ingreso	pH	fisicoquimico	2	\N	\N	t	2026-11-21 18:45:37.959264-05
5	conductividad	Conductividad	µS/cm	fisicoquimico	0	\N	\N	t	2026-11-21 18:45:37.959269-05
\.


--
-- Name: accesos_evidencia_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.accesos_evidencia_id_seq', 1, false);


--
-- Name: acciones_correctivas_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.acciones_correctivas_id_seq', 6, true);


--
-- Name: acta_acciones_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.acta_acciones_id_seq', 1, false);


--
-- Name: acta_fotos_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.acta_fotos_id_seq', 1, false);


--
-- Name: acta_personas_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.acta_personas_id_seq', 1, false);


--
-- Name: actas_seq_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.actas_seq_seq', 1, false);


--
-- Name: apertura_eventos_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.apertura_eventos_id_seq', 1, false);


--
-- Name: aperturas_seq_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.aperturas_seq_seq', 1, false);


--
-- Name: calidades_atendiente_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.calidades_atendiente_id_seq', 5, true);


--
-- Name: caso_eventos_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.caso_eventos_id_seq', 1, false);


--
-- Name: consultas_contrato_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.consultas_contrato_id_seq', 1, false);


--
-- Name: diametros_acometida_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.diametros_acometida_id_seq', 8, true);


--
-- Name: estados_medidor_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.estados_medidor_id_seq', 5, true);


--
-- Name: estados_sellos_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.estados_sellos_id_seq', 4, true);


--
-- Name: motivos_cancelacion_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.motivos_cancelacion_id_seq', 5, true);


--
-- Name: tipos_foto_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.tipos_foto_id_seq', 7, true);


--
-- Name: tipos_hallazgo_id_seq; Type: SEQUENCE SET; Schema: acta; Owner: -
--

SELECT pg_catalog.setval('acta.tipos_hallazgo_id_seq', 8, true);


--
-- Name: catalogo_eventos_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.catalogo_eventos_id_seq', 14, true);


--
-- Name: causales_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.causales_id_seq', 7, true);


--
-- Name: consultas_analisis_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.consultas_analisis_id_seq', 1, false);


--
-- Name: consultas_cercania_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.consultas_cercania_id_seq', 1, false);


--
-- Name: cuadrilla_eventos_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.cuadrilla_eventos_id_seq', 1, false);


--
-- Name: cuadrillas_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.cuadrillas_id_seq', 1, false);


--
-- Name: grupos_reporte_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.grupos_reporte_id_seq', 9, true);


--
-- Name: personal_eventos_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.personal_eventos_id_seq', 1, false);


--
-- Name: reporte_eventos_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.reporte_eventos_id_seq', 1, false);


--
-- Name: reporte_fotos_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.reporte_fotos_id_seq', 1, false);


--
-- Name: reportes_seq_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.reportes_seq_seq', 1, false);


--
-- Name: subtipos_reporte_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.subtipos_reporte_id_seq', 15, true);


--
-- Name: tipo_campos_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.tipo_campos_id_seq', 328, true);


--
-- Name: tipo_fotos_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.tipo_fotos_id_seq', 52, true);


--
-- Name: tipos_reporte_id_seq; Type: SEQUENCE SET; Schema: campo; Owner: -
--

SELECT pg_catalog.setval('campo.tipos_reporte_id_seq', 28, true);


--
-- Name: barrios_valledupar_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.barrios_valledupar_id_seq', 100000, false);


--
-- Name: catastro_valledupar_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.catastro_valledupar_id_seq', 100000, false);


--
-- Name: geoportal_auditoria_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.geoportal_auditoria_id_seq', 2, true);


--
-- Name: config_eventos_id_seq; Type: SEQUENCE SET; Schema: salida; Owner: -
--

SELECT pg_catalog.setval('salida.config_eventos_id_seq', 1, false);


--
-- Name: envio_eventos_id_seq; Type: SEQUENCE SET; Schema: salida; Owner: -
--

SELECT pg_catalog.setval('salida.envio_eventos_id_seq', 1, false);


--
-- Name: fallos_encolado_id_seq; Type: SEQUENCE SET; Schema: salida; Owner: -
--

SELECT pg_catalog.setval('salida.fallos_encolado_id_seq', 1, false);


--
-- Name: textos_autorizacion_version_seq; Type: SEQUENCE SET; Schema: salida; Owner: -
--

SELECT pg_catalog.setval('salida.textos_autorizacion_version_seq', 1, true);


--
-- Name: exclusiones_id_seq; Type: SEQUENCE SET; Schema: tecnica; Owner: -
--

SELECT pg_catalog.setval('tecnica.exclusiones_id_seq', 1, false);


--
-- Name: formulario_variables_id_seq; Type: SEQUENCE SET; Schema: tecnica; Owner: -
--

SELECT pg_catalog.setval('tecnica.formulario_variables_id_seq', 5, true);


--
-- Name: personal_tecnico_eventos_id_seq; Type: SEQUENCE SET; Schema: tecnica; Owner: -
--

SELECT pg_catalog.setval('tecnica.personal_tecnico_eventos_id_seq', 1, false);


--
-- Name: plantas_id_seq; Type: SEQUENCE SET; Schema: tecnica; Owner: -
--

SELECT pg_catalog.setval('tecnica.plantas_id_seq', 2, true);


--
-- Name: puntos_id_seq; Type: SEQUENCE SET; Schema: tecnica; Owner: -
--

SELECT pg_catalog.setval('tecnica.puntos_id_seq', 1, false);


--
-- Name: registros_id_seq; Type: SEQUENCE SET; Schema: tecnica; Owner: -
--

SELECT pg_catalog.setval('tecnica.registros_id_seq', 1, false);


--
-- Name: senal_cambio_id_seq; Type: SEQUENCE SET; Schema: tecnica; Owner: -
--

SELECT pg_catalog.setval('tecnica.senal_cambio_id_seq', 1, false);


--
-- Name: variables_id_seq; Type: SEQUENCE SET; Schema: tecnica; Owner: -
--

SELECT pg_catalog.setval('tecnica.variables_id_seq', 5, true);


--
-- Name: accesos_evidencia accesos_evidencia_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.accesos_evidencia
    ADD CONSTRAINT accesos_evidencia_pkey PRIMARY KEY (id);


--
-- Name: acciones_correctivas acciones_correctivas_codigo_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acciones_correctivas
    ADD CONSTRAINT acciones_correctivas_codigo_key UNIQUE (codigo);


--
-- Name: acciones_correctivas acciones_correctivas_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acciones_correctivas
    ADD CONSTRAINT acciones_correctivas_pkey PRIMARY KEY (id);


--
-- Name: acta_acciones acta_acciones_acta_id_accion_id_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_acciones
    ADD CONSTRAINT acta_acciones_acta_id_accion_id_key UNIQUE (acta_id, accion_id);


--
-- Name: acta_acciones acta_acciones_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_acciones
    ADD CONSTRAINT acta_acciones_pkey PRIMARY KEY (id);


--
-- Name: acta_fotos acta_fotos_acta_id_orden_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_fotos
    ADD CONSTRAINT acta_fotos_acta_id_orden_key UNIQUE (acta_id, orden);


--
-- Name: acta_fotos acta_fotos_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_fotos
    ADD CONSTRAINT acta_fotos_pkey PRIMARY KEY (id);


--
-- Name: acta_hallazgos acta_hallazgos_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_hallazgos
    ADD CONSTRAINT acta_hallazgos_pkey PRIMARY KEY (acta_id, tipo_hallazgo_id);


--
-- Name: acta_personas acta_personas_acta_id_rol_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_personas
    ADD CONSTRAINT acta_personas_acta_id_rol_key UNIQUE (acta_id, rol);


--
-- Name: acta_personas acta_personas_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_personas
    ADD CONSTRAINT acta_personas_pkey PRIMARY KEY (id);


--
-- Name: acta_sellos acta_sellos_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_sellos
    ADD CONSTRAINT acta_sellos_pkey PRIMARY KEY (acta_id);


--
-- Name: actas actas_acta_raiz_id_version_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.actas
    ADD CONSTRAINT actas_acta_raiz_id_version_key UNIQUE (acta_raiz_id, version);


--
-- Name: actas actas_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.actas
    ADD CONSTRAINT actas_pkey PRIMARY KEY (id);


--
-- Name: actas actas_seq_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.actas
    ADD CONSTRAINT actas_seq_key UNIQUE (seq);


--
-- Name: apertura_eventos apertura_eventos_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.apertura_eventos
    ADD CONSTRAINT apertura_eventos_pkey PRIMARY KEY (id);


--
-- Name: aperturas aperturas_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.aperturas
    ADD CONSTRAINT aperturas_pkey PRIMARY KEY (id);


--
-- Name: calidades_atendiente calidades_atendiente_codigo_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.calidades_atendiente
    ADD CONSTRAINT calidades_atendiente_codigo_key UNIQUE (codigo);


--
-- Name: calidades_atendiente calidades_atendiente_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.calidades_atendiente
    ADD CONSTRAINT calidades_atendiente_pkey PRIMARY KEY (id);


--
-- Name: caso_eventos caso_eventos_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.caso_eventos
    ADD CONSTRAINT caso_eventos_pkey PRIMARY KEY (id);


--
-- Name: consecutivos consecutivos_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.consecutivos
    ADD CONSTRAINT consecutivos_pkey PRIMARY KEY (serie);


--
-- Name: consultas_contrato consultas_contrato_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.consultas_contrato
    ADD CONSTRAINT consultas_contrato_pkey PRIMARY KEY (id);


--
-- Name: diametros_acometida diametros_acometida_codigo_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.diametros_acometida
    ADD CONSTRAINT diametros_acometida_codigo_key UNIQUE (codigo);


--
-- Name: diametros_acometida diametros_acometida_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.diametros_acometida
    ADD CONSTRAINT diametros_acometida_pkey PRIMARY KEY (id);


--
-- Name: estados_caso estados_caso_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.estados_caso
    ADD CONSTRAINT estados_caso_pkey PRIMARY KEY (codigo);


--
-- Name: estados_custodia estados_custodia_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.estados_custodia
    ADD CONSTRAINT estados_custodia_pkey PRIMARY KEY (codigo);


--
-- Name: estados_medidor estados_medidor_codigo_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.estados_medidor
    ADD CONSTRAINT estados_medidor_codigo_key UNIQUE (codigo);


--
-- Name: estados_medidor estados_medidor_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.estados_medidor
    ADD CONSTRAINT estados_medidor_pkey PRIMARY KEY (id);


--
-- Name: estados_sellos estados_sellos_codigo_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.estados_sellos
    ADD CONSTRAINT estados_sellos_codigo_key UNIQUE (codigo);


--
-- Name: estados_sellos estados_sellos_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.estados_sellos
    ADD CONSTRAINT estados_sellos_pkey PRIMARY KEY (id);


--
-- Name: motivos_cancelacion motivos_cancelacion_codigo_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.motivos_cancelacion
    ADD CONSTRAINT motivos_cancelacion_codigo_key UNIQUE (codigo);


--
-- Name: motivos_cancelacion motivos_cancelacion_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.motivos_cancelacion
    ADD CONSTRAINT motivos_cancelacion_pkey PRIMARY KEY (id);


--
-- Name: parametros parametros_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.parametros
    ADD CONSTRAINT parametros_pkey PRIMARY KEY (clave);


--
-- Name: tipos_foto tipos_foto_codigo_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.tipos_foto
    ADD CONSTRAINT tipos_foto_codigo_key UNIQUE (codigo);


--
-- Name: tipos_foto tipos_foto_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.tipos_foto
    ADD CONSTRAINT tipos_foto_pkey PRIMARY KEY (id);


--
-- Name: tipos_hallazgo tipos_hallazgo_codigo_key; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.tipos_hallazgo
    ADD CONSTRAINT tipos_hallazgo_codigo_key UNIQUE (codigo);


--
-- Name: tipos_hallazgo tipos_hallazgo_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.tipos_hallazgo
    ADD CONSTRAINT tipos_hallazgo_pkey PRIMARY KEY (id);


--
-- Name: transiciones_caso transiciones_caso_pkey; Type: CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.transiciones_caso
    ADD CONSTRAINT transiciones_caso_pkey PRIMARY KEY (desde, hasta);


--
-- Name: v_cambio_medidor_dim v_cambio_medidor_dim_pkey; Type: CONSTRAINT; Schema: bi; Owner: -
--

ALTER TABLE ONLY bi.v_cambio_medidor_dim
    ADD CONSTRAINT v_cambio_medidor_dim_pkey PRIMARY KEY (periodo, ciclo, uso, estrato, tipo_evento, banda_ant, metodo_act);


--
-- Name: v_consumo_promedio_dim v_consumo_promedio_dim_pkey; Type: CONSTRAINT; Schema: bi; Owner: -
--

ALTER TABLE ONLY bi.v_consumo_promedio_dim
    ADD CONSTRAINT v_consumo_promedio_dim_pkey PRIMARY KEY (periodo, dimension, grupo);


--
-- Name: v_submedicion_ciclo_dim v_submedicion_ciclo_dim_pkey; Type: CONSTRAINT; Schema: bi; Owner: -
--

ALTER TABLE ONLY bi.v_submedicion_ciclo_dim
    ADD CONSTRAINT v_submedicion_ciclo_dim_pkey PRIMARY KEY (periodo, ciclo, estrato);


--
-- Name: v_submedicion_rango_dim v_submedicion_rango_dim_pkey; Type: CONSTRAINT; Schema: bi; Owner: -
--

ALTER TABLE ONLY bi.v_submedicion_rango_dim
    ADD CONSTRAINT v_submedicion_rango_dim_pkey PRIMARY KEY (periodo, ciclo, estrato, rango_m3);


--
-- Name: v_submedicion_ref_dim v_submedicion_ref_dim_pkey; Type: CONSTRAINT; Schema: bi; Owner: -
--

ALTER TABLE ONLY bi.v_submedicion_ref_dim
    ADD CONSTRAINT v_submedicion_ref_dim_pkey PRIMARY KEY (periodo, estrato, banda_antig);


--
-- Name: ficha_contrato_estado ficha_contrato_estado_pkey; Type: CONSTRAINT; Schema: bi_interno; Owner: -
--

ALTER TABLE ONLY bi_interno.ficha_contrato_estado
    ADD CONSTRAINT ficha_contrato_estado_pkey PRIMARY KEY (id);


--
-- Name: ficha_contrato ficha_contrato_pkey; Type: CONSTRAINT; Schema: bi_interno; Owner: -
--

ALTER TABLE ONLY bi_interno.ficha_contrato
    ADD CONSTRAINT ficha_contrato_pkey PRIMARY KEY (contrato);


--
-- Name: actividades actividades_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.actividades
    ADD CONSTRAINT actividades_pkey PRIMARY KEY (codigo);


--
-- Name: areas_comercial areas_comercial_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.areas_comercial
    ADD CONSTRAINT areas_comercial_pkey PRIMARY KEY (codigo);


--
-- Name: catalogo_eventos catalogo_eventos_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.catalogo_eventos
    ADD CONSTRAINT catalogo_eventos_pkey PRIMARY KEY (id);


--
-- Name: causales causales_codigo_key; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.causales
    ADD CONSTRAINT causales_codigo_key UNIQUE (codigo);


--
-- Name: causales causales_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.causales
    ADD CONSTRAINT causales_pkey PRIMARY KEY (id);


--
-- Name: causales_tipos causales_tipos_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.causales_tipos
    ADD CONSTRAINT causales_tipos_pkey PRIMARY KEY (causal_id, tipo_id);


--
-- Name: consecutivos consecutivos_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.consecutivos
    ADD CONSTRAINT consecutivos_pkey PRIMARY KEY (tipo_id);


--
-- Name: consultas_analisis consultas_analisis_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.consultas_analisis
    ADD CONSTRAINT consultas_analisis_pkey PRIMARY KEY (id);


--
-- Name: consultas_cercania consultas_cercania_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.consultas_cercania
    ADD CONSTRAINT consultas_cercania_pkey PRIMARY KEY (id);


--
-- Name: cuadrilla_eventos cuadrilla_eventos_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.cuadrilla_eventos
    ADD CONSTRAINT cuadrilla_eventos_pkey PRIMARY KEY (id);


--
-- Name: cuadrillas cuadrillas_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.cuadrillas
    ADD CONSTRAINT cuadrillas_pkey PRIMARY KEY (id);


--
-- Name: estados_reporte estados_reporte_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.estados_reporte
    ADD CONSTRAINT estados_reporte_pkey PRIMARY KEY (codigo);


--
-- Name: grupos_reporte grupos_reporte_codigo_key; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.grupos_reporte
    ADD CONSTRAINT grupos_reporte_codigo_key UNIQUE (codigo);


--
-- Name: grupos_reporte grupos_reporte_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.grupos_reporte
    ADD CONSTRAINT grupos_reporte_pkey PRIMARY KEY (id);


--
-- Name: parametros parametros_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.parametros
    ADD CONSTRAINT parametros_pkey PRIMARY KEY (clave);


--
-- Name: personal_eventos personal_eventos_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.personal_eventos
    ADD CONSTRAINT personal_eventos_pkey PRIMARY KEY (id);


--
-- Name: preparaciones preparaciones_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.preparaciones
    ADD CONSTRAINT preparaciones_pkey PRIMARY KEY (reporte_id);


--
-- Name: reporte_datos_sensibles reporte_datos_sensibles_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reporte_datos_sensibles
    ADD CONSTRAINT reporte_datos_sensibles_pkey PRIMARY KEY (reporte_id);


--
-- Name: reporte_eventos reporte_eventos_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reporte_eventos
    ADD CONSTRAINT reporte_eventos_pkey PRIMARY KEY (id);


--
-- Name: reporte_fotos reporte_fotos_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reporte_fotos
    ADD CONSTRAINT reporte_fotos_pkey PRIMARY KEY (id);


--
-- Name: reporte_fotos reporte_fotos_reporte_id_orden_key; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reporte_fotos
    ADD CONSTRAINT reporte_fotos_reporte_id_orden_key UNIQUE (reporte_id, orden);


--
-- Name: reporte_fotos reporte_fotos_ruta_storage_key; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reporte_fotos
    ADD CONSTRAINT reporte_fotos_ruta_storage_key UNIQUE (ruta_storage);


--
-- Name: reportes reportes_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reportes
    ADD CONSTRAINT reportes_pkey PRIMARY KEY (id);


--
-- Name: reportes reportes_seq_key; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reportes
    ADD CONSTRAINT reportes_seq_key UNIQUE (seq);


--
-- Name: subtipos_reporte subtipos_reporte_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.subtipos_reporte
    ADD CONSTRAINT subtipos_reporte_pkey PRIMARY KEY (id);


--
-- Name: subtipos_reporte subtipos_reporte_tipo_id_codigo_key; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.subtipos_reporte
    ADD CONSTRAINT subtipos_reporte_tipo_id_codigo_key UNIQUE (tipo_id, codigo);


--
-- Name: tipo_campos tipo_campos_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.tipo_campos
    ADD CONSTRAINT tipo_campos_pkey PRIMARY KEY (id);


--
-- Name: tipo_campos tipo_campos_tipo_id_codigo_key; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.tipo_campos
    ADD CONSTRAINT tipo_campos_tipo_id_codigo_key UNIQUE (tipo_id, codigo);


--
-- Name: tipo_fotos tipo_fotos_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.tipo_fotos
    ADD CONSTRAINT tipo_fotos_pkey PRIMARY KEY (id);


--
-- Name: tipo_fotos tipo_fotos_tipo_id_codigo_key; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.tipo_fotos
    ADD CONSTRAINT tipo_fotos_tipo_id_codigo_key UNIQUE (tipo_id, codigo);


--
-- Name: tipos_reporte tipos_reporte_codigo_key; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.tipos_reporte
    ADD CONSTRAINT tipos_reporte_codigo_key UNIQUE (codigo);


--
-- Name: tipos_reporte tipos_reporte_pkey; Type: CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.tipos_reporte
    ADD CONSTRAINT tipos_reporte_pkey PRIMARY KEY (id);


--
-- Name: barrios_valledupar barrios_valledupar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barrios_valledupar
    ADD CONSTRAINT barrios_valledupar_pkey PRIMARY KEY (id);


--
-- Name: catastro_valledupar catastro_valledupar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catastro_valledupar
    ADD CONSTRAINT catastro_valledupar_pkey PRIMARY KEY (id);


--
-- Name: geoportal_auditoria geoportal_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geoportal_auditoria
    ADD CONSTRAINT geoportal_auditoria_pkey PRIMARY KEY (id);


--
-- Name: geoportal_config geoportal_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geoportal_config
    ADD CONSTRAINT geoportal_config_pkey PRIMARY KEY (id);


--
-- Name: geoportal_lista_blanca geoportal_lista_blanca_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geoportal_lista_blanca
    ADD CONSTRAINT geoportal_lista_blanca_pkey PRIMARY KEY (email);


--
-- Name: predios_comercial_fuente_local predios_comercial_fuente_local_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.predios_comercial_fuente_local
    ADD CONSTRAINT predios_comercial_fuente_local_pkey PRIMARY KEY (id);


--
-- Name: config_documentos config_documentos_pkey; Type: CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.config_documentos
    ADD CONSTRAINT config_documentos_pkey PRIMARY KEY (documento);


--
-- Name: config_eventos config_eventos_pkey; Type: CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.config_eventos
    ADD CONSTRAINT config_eventos_pkey PRIMARY KEY (id);


--
-- Name: contactos contactos_esquema_origen_registro_id_key; Type: CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.contactos
    ADD CONSTRAINT contactos_esquema_origen_registro_id_key UNIQUE (esquema_origen, registro_id);


--
-- Name: contactos contactos_pkey; Type: CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.contactos
    ADD CONSTRAINT contactos_pkey PRIMARY KEY (id);


--
-- Name: envio_eventos envio_eventos_pkey; Type: CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.envio_eventos
    ADD CONSTRAINT envio_eventos_pkey PRIMARY KEY (id);


--
-- Name: envios envios_esquema_origen_registro_id_key; Type: CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.envios
    ADD CONSTRAINT envios_esquema_origen_registro_id_key UNIQUE (esquema_origen, registro_id);


--
-- Name: envios envios_pkey; Type: CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.envios
    ADD CONSTRAINT envios_pkey PRIMARY KEY (id);


--
-- Name: fallos_encolado fallos_encolado_pkey; Type: CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.fallos_encolado
    ADD CONSTRAINT fallos_encolado_pkey PRIMARY KEY (id);


--
-- Name: parametros parametros_pkey; Type: CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.parametros
    ADD CONSTRAINT parametros_pkey PRIMARY KEY (clave);


--
-- Name: textos_autorizacion textos_autorizacion_pkey; Type: CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.textos_autorizacion
    ADD CONSTRAINT textos_autorizacion_pkey PRIMARY KEY (version);


--
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- Name: objects objects_bucket_id_name_key; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_bucket_id_name_key UNIQUE (bucket_id, name);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: exclusiones exclusiones_pkey; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.exclusiones
    ADD CONSTRAINT exclusiones_pkey PRIMARY KEY (id);


--
-- Name: formulario_variables formulario_variables_pkey; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.formulario_variables
    ADD CONSTRAINT formulario_variables_pkey PRIMARY KEY (id);


--
-- Name: personal_tecnico_eventos personal_tecnico_eventos_pkey; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.personal_tecnico_eventos
    ADD CONSTRAINT personal_tecnico_eventos_pkey PRIMARY KEY (id);


--
-- Name: plantas plantas_codigo_key; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.plantas
    ADD CONSTRAINT plantas_codigo_key UNIQUE (codigo);


--
-- Name: plantas plantas_pkey; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.plantas
    ADD CONSTRAINT plantas_pkey PRIMARY KEY (id);


--
-- Name: puntos puntos_codigo_key; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.puntos
    ADD CONSTRAINT puntos_codigo_key UNIQUE (codigo);


--
-- Name: puntos puntos_pkey; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.puntos
    ADD CONSTRAINT puntos_pkey PRIMARY KEY (id);


--
-- Name: registros registros_pkey; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.registros
    ADD CONSTRAINT registros_pkey PRIMARY KEY (id);


--
-- Name: senal_cambio senal_cambio_pkey; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.senal_cambio
    ADD CONSTRAINT senal_cambio_pkey PRIMARY KEY (id);


--
-- Name: formulario_variables uq_formulario_variable; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.formulario_variables
    ADD CONSTRAINT uq_formulario_variable UNIQUE (formulario, variable_id);


--
-- Name: variables variables_codigo_key; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.variables
    ADD CONSTRAINT variables_codigo_key UNIQUE (codigo);


--
-- Name: variables variables_pkey; Type: CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.variables
    ADD CONSTRAINT variables_pkey PRIMARY KEY (id);


--
-- Name: accesos_evidencia_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX accesos_evidencia_idx ON acta.accesos_evidencia USING btree (autor, accedido_en DESC);


--
-- Name: acta_fotos_ruta_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX acta_fotos_ruta_idx ON acta.acta_fotos USING btree (ruta_storage);


--
-- Name: actas_autor_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX actas_autor_idx ON acta.actas USING btree (autor, registrado_en DESC);


--
-- Name: actas_consec_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX actas_consec_idx ON acta.actas USING btree (consecutivo);


--
-- Name: actas_contrato_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX actas_contrato_idx ON acta.actas USING btree (contrato) WHERE (contrato IS NOT NULL);


--
-- Name: actas_fisico_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX actas_fisico_idx ON acta.actas USING btree (numero_fisico_norm) WHERE (numero_fisico_norm <> ''::text);


--
-- Name: actas_raiz_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX actas_raiz_idx ON acta.actas USING btree (acta_raiz_id, version DESC);


--
-- Name: actas_reg_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX actas_reg_idx ON acta.actas USING btree (registrado_en DESC);


--
-- Name: apertura_eventos_cancelar_uk; Type: INDEX; Schema: acta; Owner: -
--

CREATE UNIQUE INDEX apertura_eventos_cancelar_uk ON acta.apertura_eventos USING btree (apertura_id) WHERE (tipo_evento = 'cancelar'::text);


--
-- Name: apertura_eventos_creado_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX apertura_eventos_creado_idx ON acta.apertura_eventos USING btree (creado_en DESC);


--
-- Name: aperturas_autor_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX aperturas_autor_idx ON acta.aperturas USING btree (autor, abierto_en DESC);


--
-- Name: aperturas_consecutivo_uk; Type: INDEX; Schema: acta; Owner: -
--

CREATE UNIQUE INDEX aperturas_consecutivo_uk ON acta.aperturas USING btree (consecutivo) WHERE (correccion_de IS NULL);


--
-- Name: aperturas_numero_uk; Type: INDEX; Schema: acta; Owner: -
--

CREATE UNIQUE INDEX aperturas_numero_uk ON acta.aperturas USING btree (serie, numero) WHERE (correccion_de IS NULL);


--
-- Name: aperturas_raiz_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX aperturas_raiz_idx ON acta.aperturas USING btree (acta_raiz_id);


--
-- Name: caso_eventos_raiz_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX caso_eventos_raiz_idx ON acta.caso_eventos USING btree (acta_raiz_id, id DESC);


--
-- Name: consultas_contrato_idx; Type: INDEX; Schema: acta; Owner: -
--

CREATE INDEX consultas_contrato_idx ON acta.consultas_contrato USING btree (autor, consultado_en DESC);


--
-- Name: estados_caso_inicial_si_uk; Type: INDEX; Schema: acta; Owner: -
--

CREATE UNIQUE INDEX estados_caso_inicial_si_uk ON acta.estados_caso USING btree ((true)) WHERE inicial_sin_irregularidad;


--
-- Name: estados_caso_inicial_uk; Type: INDEX; Schema: acta; Owner: -
--

CREATE UNIQUE INDEX estados_caso_inicial_uk ON acta.estados_caso USING btree ((true)) WHERE inicial;


--
-- Name: actividades_nombre_uk; Type: INDEX; Schema: campo; Owner: -
--

CREATE UNIQUE INDEX actividades_nombre_uk ON campo.actividades USING btree (lower(nombre));


--
-- Name: areas_comercial_nombre_uk; Type: INDEX; Schema: campo; Owner: -
--

CREATE UNIQUE INDEX areas_comercial_nombre_uk ON campo.areas_comercial USING btree (lower(nombre));


--
-- Name: catalogo_eventos_codigo_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX catalogo_eventos_codigo_idx ON campo.catalogo_eventos USING btree (catalogo, codigo, id DESC);


--
-- Name: consultas_analisis_autor_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX consultas_analisis_autor_idx ON campo.consultas_analisis USING btree (autor, consultado_en DESC);


--
-- Name: consultas_analisis_contrato_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX consultas_analisis_contrato_idx ON campo.consultas_analisis USING btree (contrato, consultado_en DESC);


--
-- Name: consultas_cercania_autor_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX consultas_cercania_autor_idx ON campo.consultas_cercania USING btree (autor, consultado_en DESC);


--
-- Name: cuadrilla_eventos_cuadrilla_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX cuadrilla_eventos_cuadrilla_idx ON campo.cuadrilla_eventos USING btree (cuadrilla_id, id DESC);


--
-- Name: cuadrillas_nombre_uk; Type: INDEX; Schema: campo; Owner: -
--

CREATE UNIQUE INDEX cuadrillas_nombre_uk ON campo.cuadrillas USING btree (lower(regexp_replace(nombre, '\s'::text, ''::text, 'g'::text)));


--
-- Name: estados_reporte_un_inicial; Type: INDEX; Schema: campo; Owner: -
--

CREATE UNIQUE INDEX estados_reporte_un_inicial ON campo.estados_reporte USING btree (inicial) WHERE inicial;


--
-- Name: personal_eventos_persona_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX personal_eventos_persona_idx ON campo.personal_eventos USING btree (persona, id DESC);


--
-- Name: personal_eventos_tipo_valor_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX personal_eventos_tipo_valor_idx ON campo.personal_eventos USING btree (tipo_evento, valor) WHERE (valor IS NOT NULL);


--
-- Name: preparaciones_autor_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX preparaciones_autor_idx ON campo.preparaciones USING btree (autor, creado_en DESC);


--
-- Name: reporte_eventos_original_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX reporte_eventos_original_idx ON campo.reporte_eventos USING btree (reporte_original_id) WHERE (reporte_original_id IS NOT NULL);


--
-- Name: reporte_eventos_reporte_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX reporte_eventos_reporte_idx ON campo.reporte_eventos USING btree (reporte_id, id DESC);


--
-- Name: reportes_autor_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX reportes_autor_idx ON campo.reportes USING btree (autor);


--
-- Name: reportes_consecutivo_key; Type: INDEX; Schema: campo; Owner: -
--

CREATE UNIQUE INDEX reportes_consecutivo_key ON campo.reportes USING btree (consecutivo) WHERE (consecutivo IS NOT NULL);


--
-- Name: reportes_consecutivo_num_key; Type: INDEX; Schema: campo; Owner: -
--

CREATE UNIQUE INDEX reportes_consecutivo_num_key ON campo.reportes USING btree (tipo_id, consecutivo_num) WHERE (consecutivo_num IS NOT NULL);


--
-- Name: reportes_contrato_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX reportes_contrato_idx ON campo.reportes USING btree (contrato) WHERE (contrato IS NOT NULL);


--
-- Name: reportes_orden_trabajo_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX reportes_orden_trabajo_idx ON campo.reportes USING btree (orden_trabajo_id) WHERE (orden_trabajo_id IS NOT NULL);


--
-- Name: reportes_registrado_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX reportes_registrado_idx ON campo.reportes USING btree (registrado_en DESC);


--
-- Name: reportes_tipo_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX reportes_tipo_idx ON campo.reportes USING btree (tipo_id);


--
-- Name: tipo_campos_tipo_idx; Type: INDEX; Schema: campo; Owner: -
--

CREATE INDEX tipo_campos_tipo_idx ON campo.tipo_campos USING btree (tipo_id, orden, id);


--
-- Name: tipos_reporte_prefijo_key; Type: INDEX; Schema: campo; Owner: -
--

CREATE UNIQUE INDEX tipos_reporte_prefijo_key ON campo.tipos_reporte USING btree (prefijo_consecutivo) WHERE (prefijo_consecutivo IS NOT NULL);


--
-- Name: idx_cartera_contrato; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cartera_contrato ON public.cartera_suscripcion USING btree (contrato);


--
-- Name: predios_comercial_id_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX predios_comercial_id_key ON public.predios_comercial USING btree (id);


--
-- Name: envio_eventos_idx; Type: INDEX; Schema: salida; Owner: -
--

CREATE INDEX envio_eventos_idx ON salida.envio_eventos USING btree (envio_id, id);


--
-- Name: envios_cola_idx; Type: INDEX; Schema: salida; Owner: -
--

CREATE INDEX envios_cola_idx ON salida.envios USING btree (creado_en) WHERE (estado = ANY (ARRAY['pendiente'::text, 'tomado'::text]));


--
-- Name: envios_estado_idx; Type: INDEX; Schema: salida; Owner: -
--

CREATE INDEX envios_estado_idx ON salida.envios USING btree (estado, ultimo_cambio_en);


--
-- Name: ix_exclusiones_lote; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE INDEX ix_exclusiones_lote ON tecnica.exclusiones USING btree (lote_id, id DESC) WHERE (lote_id IS NOT NULL);


--
-- Name: ix_exclusiones_registro; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE INDEX ix_exclusiones_registro ON tecnica.exclusiones USING btree (registro_id, id DESC) WHERE (registro_id IS NOT NULL);


--
-- Name: ix_pte_persona; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE INDEX ix_pte_persona ON tecnica.personal_tecnico_eventos USING btree (persona, id DESC);


--
-- Name: ix_pte_persona_form; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE INDEX ix_pte_persona_form ON tecnica.personal_tecnico_eventos USING btree (persona, formulario, id DESC);


--
-- Name: ix_registros_autor; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE INDEX ix_registros_autor ON tecnica.registros USING btree (autor, id DESC);


--
-- Name: ix_registros_form_fecha; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE INDEX ix_registros_form_fecha ON tecnica.registros USING btree (formulario, fecha_muestra DESC);


--
-- Name: ix_registros_lote; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE INDEX ix_registros_lote ON tecnica.registros USING btree (lote_id);


--
-- Name: ix_registros_muestra; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE INDEX ix_registros_muestra ON tecnica.registros USING btree (muestra_ts DESC);


--
-- Name: ix_registros_variable; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE INDEX ix_registros_variable ON tecnica.registros USING btree (variable_id, planta_id, muestra_ts DESC);


--
-- Name: ix_senal_creado; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE INDEX ix_senal_creado ON tecnica.senal_cambio USING btree (creado_en DESC);


--
-- Name: uq_registro_clave_envio; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE UNIQUE INDEX uq_registro_clave_envio ON tecnica.registros USING btree (autor, clave_envio, variable_id, COALESCE(planta_id, (0)::bigint)) WHERE (clave_envio IS NOT NULL);


--
-- Name: uq_registro_lote_variable_planta; Type: INDEX; Schema: tecnica; Owner: -
--

CREATE UNIQUE INDEX uq_registro_lote_variable_planta ON tecnica.registros USING btree (lote_id, variable_id, COALESCE(planta_id, (0)::bigint));


--
-- Name: actas t_acta_coherente; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_acta_coherente BEFORE INSERT ON acta.actas FOR EACH ROW EXECUTE FUNCTION acta.f_acta_coherente();


--
-- Name: actas t_acta_no_cancelada; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_acta_no_cancelada BEFORE INSERT ON acta.actas FOR EACH ROW EXECUTE FUNCTION acta.f_acta_no_cancelada();


--
-- Name: acciones_correctivas t_codigo_inmutable; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON acta.acciones_correctivas FOR EACH ROW EXECUTE FUNCTION acta.f_codigo_inmutable();


--
-- Name: calidades_atendiente t_codigo_inmutable; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON acta.calidades_atendiente FOR EACH ROW EXECUTE FUNCTION acta.f_codigo_inmutable();


--
-- Name: diametros_acometida t_codigo_inmutable; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON acta.diametros_acometida FOR EACH ROW EXECUTE FUNCTION acta.f_codigo_inmutable();


--
-- Name: estados_caso t_codigo_inmutable; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON acta.estados_caso FOR EACH ROW EXECUTE FUNCTION acta.f_codigo_inmutable();


--
-- Name: estados_custodia t_codigo_inmutable; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON acta.estados_custodia FOR EACH ROW EXECUTE FUNCTION acta.f_codigo_inmutable();


--
-- Name: estados_medidor t_codigo_inmutable; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON acta.estados_medidor FOR EACH ROW EXECUTE FUNCTION acta.f_codigo_inmutable();


--
-- Name: estados_sellos t_codigo_inmutable; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON acta.estados_sellos FOR EACH ROW EXECUTE FUNCTION acta.f_codigo_inmutable();


--
-- Name: motivos_cancelacion t_codigo_inmutable; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON acta.motivos_cancelacion FOR EACH ROW EXECUTE FUNCTION acta.f_codigo_inmutable();


--
-- Name: tipos_foto t_codigo_inmutable; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON acta.tipos_foto FOR EACH ROW EXECUTE FUNCTION acta.f_codigo_inmutable();


--
-- Name: tipos_hallazgo t_codigo_inmutable; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON acta.tipos_hallazgo FOR EACH ROW EXECUTE FUNCTION acta.f_codigo_inmutable();


--
-- Name: actas t_encolar_constancia; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_encolar_constancia AFTER INSERT ON acta.actas FOR EACH ROW EXECUTE FUNCTION salida.f_disparar_acta();


--
-- Name: apertura_eventos t_evento_apertura_coherente; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_evento_apertura_coherente BEFORE INSERT ON acta.apertura_eventos FOR EACH ROW EXECUTE FUNCTION acta.f_evento_apertura_coherente();


--
-- Name: caso_eventos t_evento_coherente; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_evento_coherente BEFORE INSERT ON acta.caso_eventos FOR EACH ROW EXECUTE FUNCTION acta.f_evento_coherente();


--
-- Name: acciones_correctivas t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.acciones_correctivas FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: calidades_atendiente t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.calidades_atendiente FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: consecutivos t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.consecutivos FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: diametros_acometida t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.diametros_acometida FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: estados_caso t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.estados_caso FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: estados_custodia t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.estados_custodia FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: estados_medidor t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.estados_medidor FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: estados_sellos t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.estados_sellos FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: motivos_cancelacion t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.motivos_cancelacion FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: parametros t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.parametros FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: tipos_foto t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.tipos_foto FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: tipos_hallazgo t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.tipos_hallazgo FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: transiciones_caso t_no_borrar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON acta.transiciones_caso FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acciones_correctivas t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.acciones_correctivas FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: calidades_atendiente t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.calidades_atendiente FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: consecutivos t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.consecutivos FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: diametros_acometida t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.diametros_acometida FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: estados_caso t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.estados_caso FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: estados_custodia t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.estados_custodia FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: estados_medidor t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.estados_medidor FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: estados_sellos t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.estados_sellos FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: motivos_cancelacion t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.motivos_cancelacion FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: parametros t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.parametros FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: tipos_foto t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.tipos_foto FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: tipos_hallazgo t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.tipos_hallazgo FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: transiciones_caso t_no_vaciar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON acta.transiciones_caso FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: accesos_evidencia t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.accesos_evidencia FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acta_acciones t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.acta_acciones FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acta_fotos t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.acta_fotos FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acta_hallazgos t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.acta_hallazgos FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acta_personas t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.acta_personas FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acta_sellos t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.acta_sellos FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: actas t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.actas FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: apertura_eventos t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.apertura_eventos FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: aperturas t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.aperturas FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: caso_eventos t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.caso_eventos FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: consultas_contrato t_solo_agregar; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON acta.consultas_contrato FOR EACH ROW EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: accesos_evidencia t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.accesos_evidencia FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acta_acciones t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.acta_acciones FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acta_fotos t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.acta_fotos FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acta_hallazgos t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.acta_hallazgos FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acta_personas t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.acta_personas FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: acta_sellos t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.acta_sellos FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: actas t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.actas FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: apertura_eventos t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.apertura_eventos FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: aperturas t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.aperturas FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: caso_eventos t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.caso_eventos FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: consultas_contrato t_solo_agregar_trunc; Type: TRIGGER; Schema: acta; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON acta.consultas_contrato FOR EACH STATEMENT EXECUTE FUNCTION acta.f_solo_agregar();


--
-- Name: consultas_analisis consultas_analisis_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER consultas_analisis_inmutable BEFORE DELETE OR UPDATE ON campo.consultas_analisis FOR EACH ROW EXECUTE FUNCTION campo.f_consultas_analisis_inmutable();


--
-- Name: consultas_cercania consultas_cercania_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER consultas_cercania_inmutable BEFORE DELETE OR UPDATE ON campo.consultas_cercania FOR EACH ROW EXECUTE FUNCTION campo.f_consultas_analisis_inmutable();


--
-- Name: estados_reporte t_codigo_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON campo.estados_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_codigo_inmutable();


--
-- Name: grupos_reporte t_codigo_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON campo.grupos_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_codigo_inmutable();


--
-- Name: subtipos_reporte t_codigo_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON campo.subtipos_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_codigo_inmutable();


--
-- Name: tipos_reporte t_codigo_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_codigo_inmutable BEFORE UPDATE ON campo.tipos_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_codigo_inmutable();


--
-- Name: causales t_d_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_d_inmutable BEFORE UPDATE ON campo.causales FOR EACH ROW EXECUTE FUNCTION campo.f_catalogo_d_inmutable();


--
-- Name: causales_tipos t_d_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_d_inmutable BEFORE UPDATE ON campo.causales_tipos FOR EACH ROW EXECUTE FUNCTION campo.f_catalogo_d_inmutable();


--
-- Name: consecutivos t_d_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_d_inmutable BEFORE UPDATE ON campo.consecutivos FOR EACH ROW EXECUTE FUNCTION campo.f_catalogo_d_inmutable();


--
-- Name: tipo_campos t_d_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_d_inmutable BEFORE UPDATE ON campo.tipo_campos FOR EACH ROW EXECUTE FUNCTION campo.f_catalogo_d_inmutable();


--
-- Name: tipo_fotos t_d_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_d_inmutable BEFORE UPDATE ON campo.tipo_fotos FOR EACH ROW EXECUTE FUNCTION campo.f_catalogo_d_inmutable();


--
-- Name: tipos_reporte t_d_inmutable; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_d_inmutable BEFORE UPDATE ON campo.tipos_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_catalogo_d_inmutable();


--
-- Name: reportes t_encolar_constancia; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_encolar_constancia AFTER INSERT ON campo.reportes FOR EACH ROW EXECUTE FUNCTION salida.f_disparar_campo();


--
-- Name: reporte_eventos t_evento_coherente; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_evento_coherente BEFORE INSERT ON campo.reporte_eventos FOR EACH ROW EXECUTE FUNCTION campo.f_evento_coherente();


--
-- Name: actividades t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE OR UPDATE ON campo.actividades FOR EACH ROW EXECUTE FUNCTION campo.f_no_borrar_catalogo();


--
-- Name: areas_comercial t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE OR UPDATE ON campo.areas_comercial FOR EACH ROW EXECUTE FUNCTION campo.f_no_borrar_catalogo();


--
-- Name: causales t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.causales FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: causales_tipos t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.causales_tipos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: consecutivos t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.consecutivos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: cuadrillas t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE OR UPDATE ON campo.cuadrillas FOR EACH ROW EXECUTE FUNCTION campo.f_no_borrar_catalogo();


--
-- Name: estados_reporte t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.estados_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: grupos_reporte t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.grupos_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: parametros t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.parametros FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: subtipos_reporte t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.subtipos_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: tipo_campos t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.tipo_campos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: tipo_fotos t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.tipo_fotos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: tipos_reporte t_no_borrar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON campo.tipos_reporte FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: actividades t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.actividades FOR EACH STATEMENT EXECUTE FUNCTION campo.f_no_borrar_catalogo();


--
-- Name: areas_comercial t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.areas_comercial FOR EACH STATEMENT EXECUTE FUNCTION campo.f_no_borrar_catalogo();


--
-- Name: causales t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.causales FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: causales_tipos t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.causales_tipos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: consecutivos t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.consecutivos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: cuadrillas t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.cuadrillas FOR EACH STATEMENT EXECUTE FUNCTION campo.f_no_borrar_catalogo();


--
-- Name: estados_reporte t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.estados_reporte FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: grupos_reporte t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.grupos_reporte FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: parametros t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.parametros FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: subtipos_reporte t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.subtipos_reporte FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: tipo_campos t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.tipo_campos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: tipo_fotos t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.tipo_fotos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: tipos_reporte t_no_vaciar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON campo.tipos_reporte FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: reportes t_reporte_coherente; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_reporte_coherente BEFORE INSERT ON campo.reportes FOR EACH ROW EXECUTE FUNCTION campo.f_reporte_coherente();


--
-- Name: catalogo_eventos t_solo_agregar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.catalogo_eventos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: cuadrilla_eventos t_solo_agregar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.cuadrilla_eventos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: personal_eventos t_solo_agregar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.personal_eventos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: preparaciones t_solo_agregar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.preparaciones FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: reporte_datos_sensibles t_solo_agregar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.reporte_datos_sensibles FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: reporte_eventos t_solo_agregar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.reporte_eventos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: reporte_fotos t_solo_agregar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.reporte_fotos FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: reportes t_solo_agregar; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON campo.reportes FOR EACH ROW EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: catalogo_eventos t_solo_agregar_trunc; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.catalogo_eventos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: cuadrilla_eventos t_solo_agregar_trunc; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.cuadrilla_eventos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: personal_eventos t_solo_agregar_trunc; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.personal_eventos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: preparaciones t_solo_agregar_trunc; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.preparaciones FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: reporte_datos_sensibles t_solo_agregar_trunc; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.reporte_datos_sensibles FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: reporte_eventos t_solo_agregar_trunc; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.reporte_eventos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: reporte_fotos t_solo_agregar_trunc; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.reporte_fotos FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: reportes t_solo_agregar_trunc; Type: TRIGGER; Schema: campo; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON campo.reportes FOR EACH STATEMENT EXECUTE FUNCTION campo.f_solo_agregar();


--
-- Name: contactos t_contacto_actualizable; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_contacto_actualizable BEFORE UPDATE ON salida.contactos FOR EACH ROW EXECUTE FUNCTION salida.f_contacto_actualizable();


--
-- Name: envios t_envio_actualizable; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_envio_actualizable BEFORE UPDATE ON salida.envios FOR EACH ROW EXECUTE FUNCTION salida.f_envio_actualizable();


--
-- Name: contactos t_no_borrar; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON salida.contactos FOR EACH ROW EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: envios t_no_borrar; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON salida.envios FOR EACH ROW EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: contactos t_no_truncar; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_no_truncar BEFORE TRUNCATE ON salida.contactos FOR EACH STATEMENT EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: envios t_no_truncar; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_no_truncar BEFORE TRUNCATE ON salida.envios FOR EACH STATEMENT EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: config_eventos t_solo_agregar; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON salida.config_eventos FOR EACH ROW EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: envio_eventos t_solo_agregar; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON salida.envio_eventos FOR EACH ROW EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: fallos_encolado t_solo_agregar; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON salida.fallos_encolado FOR EACH ROW EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: textos_autorizacion t_solo_agregar; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON salida.textos_autorizacion FOR EACH ROW EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: config_eventos t_solo_agregar_trunc; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON salida.config_eventos FOR EACH STATEMENT EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: envio_eventos t_solo_agregar_trunc; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON salida.envio_eventos FOR EACH STATEMENT EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: fallos_encolado t_solo_agregar_trunc; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON salida.fallos_encolado FOR EACH STATEMENT EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: textos_autorizacion t_solo_agregar_trunc; Type: TRIGGER; Schema: salida; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON salida.textos_autorizacion FOR EACH STATEMENT EXECUTE FUNCTION salida.f_solo_agregar();


--
-- Name: formulario_variables t_catalogo_protegido; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_catalogo_protegido BEFORE UPDATE ON tecnica.formulario_variables FOR EACH ROW EXECUTE FUNCTION tecnica.f_catalogo_protegido();


--
-- Name: variables t_catalogo_protegido; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_catalogo_protegido BEFORE UPDATE ON tecnica.variables FOR EACH ROW EXECUTE FUNCTION tecnica.f_catalogo_protegido();


--
-- Name: formulario_variables t_no_borrar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON tecnica.formulario_variables FOR EACH ROW EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: plantas t_no_borrar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON tecnica.plantas FOR EACH ROW EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: puntos t_no_borrar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON tecnica.puntos FOR EACH ROW EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: variables t_no_borrar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_no_borrar BEFORE DELETE ON tecnica.variables FOR EACH ROW EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: formulario_variables t_no_vaciar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON tecnica.formulario_variables FOR EACH STATEMENT EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: plantas t_no_vaciar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON tecnica.plantas FOR EACH STATEMENT EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: puntos t_no_vaciar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON tecnica.puntos FOR EACH STATEMENT EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: variables t_no_vaciar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_no_vaciar BEFORE TRUNCATE ON tecnica.variables FOR EACH STATEMENT EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: registros t_registro_coherente; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_registro_coherente BEFORE INSERT ON tecnica.registros FOR EACH ROW EXECUTE FUNCTION tecnica.f_registro_coherente();


--
-- Name: exclusiones t_solo_agregar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON tecnica.exclusiones FOR EACH ROW EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: personal_tecnico_eventos t_solo_agregar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON tecnica.personal_tecnico_eventos FOR EACH ROW EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: registros t_solo_agregar; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_solo_agregar BEFORE DELETE OR UPDATE ON tecnica.registros FOR EACH ROW EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: exclusiones t_solo_agregar_trunc; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON tecnica.exclusiones FOR EACH STATEMENT EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: personal_tecnico_eventos t_solo_agregar_trunc; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON tecnica.personal_tecnico_eventos FOR EACH STATEMENT EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: registros t_solo_agregar_trunc; Type: TRIGGER; Schema: tecnica; Owner: -
--

CREATE TRIGGER t_solo_agregar_trunc BEFORE TRUNCATE ON tecnica.registros FOR EACH STATEMENT EXECUTE FUNCTION tecnica.f_solo_agregar();


--
-- Name: accesos_evidencia accesos_evidencia_acta_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.accesos_evidencia
    ADD CONSTRAINT accesos_evidencia_acta_id_fkey FOREIGN KEY (acta_id) REFERENCES acta.actas(id);


--
-- Name: acta_acciones acta_acciones_accion_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_acciones
    ADD CONSTRAINT acta_acciones_accion_id_fkey FOREIGN KEY (accion_id) REFERENCES acta.acciones_correctivas(id);


--
-- Name: acta_acciones acta_acciones_acta_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_acciones
    ADD CONSTRAINT acta_acciones_acta_id_fkey FOREIGN KEY (acta_id) REFERENCES acta.actas(id);


--
-- Name: acta_fotos acta_fotos_acta_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_fotos
    ADD CONSTRAINT acta_fotos_acta_id_fkey FOREIGN KEY (acta_id) REFERENCES acta.actas(id);


--
-- Name: acta_fotos acta_fotos_heredada_de_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_fotos
    ADD CONSTRAINT acta_fotos_heredada_de_fkey FOREIGN KEY (heredada_de) REFERENCES acta.actas(id);


--
-- Name: acta_fotos acta_fotos_tipo_foto_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_fotos
    ADD CONSTRAINT acta_fotos_tipo_foto_id_fkey FOREIGN KEY (tipo_foto_id) REFERENCES acta.tipos_foto(id);


--
-- Name: acta_hallazgos acta_hallazgos_acta_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_hallazgos
    ADD CONSTRAINT acta_hallazgos_acta_id_fkey FOREIGN KEY (acta_id) REFERENCES acta.actas(id);


--
-- Name: acta_hallazgos acta_hallazgos_tipo_hallazgo_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_hallazgos
    ADD CONSTRAINT acta_hallazgos_tipo_hallazgo_id_fkey FOREIGN KEY (tipo_hallazgo_id) REFERENCES acta.tipos_hallazgo(id);


--
-- Name: acta_personas acta_personas_acta_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_personas
    ADD CONSTRAINT acta_personas_acta_id_fkey FOREIGN KEY (acta_id) REFERENCES acta.actas(id);


--
-- Name: acta_personas acta_personas_calidad_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_personas
    ADD CONSTRAINT acta_personas_calidad_id_fkey FOREIGN KEY (calidad_id) REFERENCES acta.calidades_atendiente(id);


--
-- Name: acta_sellos acta_sellos_acta_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.acta_sellos
    ADD CONSTRAINT acta_sellos_acta_id_fkey FOREIGN KEY (acta_id) REFERENCES acta.actas(id);


--
-- Name: actas actas_diametro_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.actas
    ADD CONSTRAINT actas_diametro_id_fkey FOREIGN KEY (diametro_id) REFERENCES acta.diametros_acometida(id);


--
-- Name: actas actas_estado_medidor_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.actas
    ADD CONSTRAINT actas_estado_medidor_id_fkey FOREIGN KEY (estado_medidor_id) REFERENCES acta.estados_medidor(id);


--
-- Name: actas actas_estado_sellos_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.actas
    ADD CONSTRAINT actas_estado_sellos_id_fkey FOREIGN KEY (estado_sellos_id) REFERENCES acta.estados_sellos(id);


--
-- Name: actas actas_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.actas
    ADD CONSTRAINT actas_id_fkey FOREIGN KEY (id) REFERENCES acta.aperturas(id);


--
-- Name: actas actas_version_anterior_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.actas
    ADD CONSTRAINT actas_version_anterior_id_fkey FOREIGN KEY (version_anterior_id) REFERENCES acta.actas(id);


--
-- Name: apertura_eventos apertura_eventos_apertura_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.apertura_eventos
    ADD CONSTRAINT apertura_eventos_apertura_id_fkey FOREIGN KEY (apertura_id) REFERENCES acta.aperturas(id);


--
-- Name: apertura_eventos apertura_eventos_motivo_codigo_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.apertura_eventos
    ADD CONSTRAINT apertura_eventos_motivo_codigo_fkey FOREIGN KEY (motivo_codigo) REFERENCES acta.motivos_cancelacion(codigo);


--
-- Name: aperturas aperturas_correccion_fk; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.aperturas
    ADD CONSTRAINT aperturas_correccion_fk FOREIGN KEY (correccion_de) REFERENCES acta.actas(id);


--
-- Name: caso_eventos caso_eventos_acta_id_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.caso_eventos
    ADD CONSTRAINT caso_eventos_acta_id_fkey FOREIGN KEY (acta_id) REFERENCES acta.actas(id);


--
-- Name: caso_eventos caso_eventos_custodia_codigo_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.caso_eventos
    ADD CONSTRAINT caso_eventos_custodia_codigo_fkey FOREIGN KEY (custodia_codigo) REFERENCES acta.estados_custodia(codigo);


--
-- Name: caso_eventos caso_eventos_estado_nuevo_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.caso_eventos
    ADD CONSTRAINT caso_eventos_estado_nuevo_fkey FOREIGN KEY (estado_nuevo) REFERENCES acta.estados_caso(codigo);


--
-- Name: transiciones_caso transiciones_caso_desde_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.transiciones_caso
    ADD CONSTRAINT transiciones_caso_desde_fkey FOREIGN KEY (desde) REFERENCES acta.estados_caso(codigo);


--
-- Name: transiciones_caso transiciones_caso_hasta_fkey; Type: FK CONSTRAINT; Schema: acta; Owner: -
--

ALTER TABLE ONLY acta.transiciones_caso
    ADD CONSTRAINT transiciones_caso_hasta_fkey FOREIGN KEY (hasta) REFERENCES acta.estados_caso(codigo);


--
-- Name: causales_tipos causales_tipos_causal_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.causales_tipos
    ADD CONSTRAINT causales_tipos_causal_id_fkey FOREIGN KEY (causal_id) REFERENCES campo.causales(id);


--
-- Name: causales_tipos causales_tipos_tipo_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.causales_tipos
    ADD CONSTRAINT causales_tipos_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES campo.tipos_reporte(id);


--
-- Name: consecutivos consecutivos_tipo_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.consecutivos
    ADD CONSTRAINT consecutivos_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES campo.tipos_reporte(id);


--
-- Name: cuadrilla_eventos cuadrilla_eventos_cuadrilla_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.cuadrilla_eventos
    ADD CONSTRAINT cuadrilla_eventos_cuadrilla_id_fkey FOREIGN KEY (cuadrilla_id) REFERENCES campo.cuadrillas(id);


--
-- Name: reporte_datos_sensibles reporte_datos_sensibles_reporte_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reporte_datos_sensibles
    ADD CONSTRAINT reporte_datos_sensibles_reporte_id_fkey FOREIGN KEY (reporte_id) REFERENCES campo.reportes(id);


--
-- Name: reporte_eventos reporte_eventos_estado_nuevo_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reporte_eventos
    ADD CONSTRAINT reporte_eventos_estado_nuevo_fkey FOREIGN KEY (estado_nuevo) REFERENCES campo.estados_reporte(codigo);


--
-- Name: reporte_eventos reporte_eventos_reporte_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reporte_eventos
    ADD CONSTRAINT reporte_eventos_reporte_id_fkey FOREIGN KEY (reporte_id) REFERENCES campo.reportes(id);


--
-- Name: reporte_eventos reporte_eventos_reporte_original_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reporte_eventos
    ADD CONSTRAINT reporte_eventos_reporte_original_id_fkey FOREIGN KEY (reporte_original_id) REFERENCES campo.reportes(id);


--
-- Name: reporte_fotos reporte_fotos_reporte_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reporte_fotos
    ADD CONSTRAINT reporte_fotos_reporte_id_fkey FOREIGN KEY (reporte_id) REFERENCES campo.reportes(id);


--
-- Name: reportes reportes_causal_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reportes
    ADD CONSTRAINT reportes_causal_id_fkey FOREIGN KEY (causal_id) REFERENCES campo.causales(id);


--
-- Name: reportes reportes_subtipo_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reportes
    ADD CONSTRAINT reportes_subtipo_id_fkey FOREIGN KEY (subtipo_id) REFERENCES campo.subtipos_reporte(id);


--
-- Name: reportes reportes_tipo_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.reportes
    ADD CONSTRAINT reportes_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES campo.tipos_reporte(id);


--
-- Name: subtipos_reporte subtipos_reporte_tipo_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.subtipos_reporte
    ADD CONSTRAINT subtipos_reporte_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES campo.tipos_reporte(id);


--
-- Name: tipo_campos tipo_campos_tipo_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.tipo_campos
    ADD CONSTRAINT tipo_campos_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES campo.tipos_reporte(id);


--
-- Name: tipo_fotos tipo_fotos_tipo_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.tipo_fotos
    ADD CONSTRAINT tipo_fotos_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES campo.tipos_reporte(id);


--
-- Name: tipos_reporte tipos_reporte_grupo_id_fkey; Type: FK CONSTRAINT; Schema: campo; Owner: -
--

ALTER TABLE ONLY campo.tipos_reporte
    ADD CONSTRAINT tipos_reporte_grupo_id_fkey FOREIGN KEY (grupo_id) REFERENCES campo.grupos_reporte(id);


--
-- Name: contactos contactos_texto_version_fkey; Type: FK CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.contactos
    ADD CONSTRAINT contactos_texto_version_fkey FOREIGN KEY (texto_version) REFERENCES salida.textos_autorizacion(version);


--
-- Name: envio_eventos envio_eventos_envio_id_fkey; Type: FK CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.envio_eventos
    ADD CONSTRAINT envio_eventos_envio_id_fkey FOREIGN KEY (envio_id) REFERENCES salida.envios(id);


--
-- Name: envios envios_contacto_id_fkey; Type: FK CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.envios
    ADD CONSTRAINT envios_contacto_id_fkey FOREIGN KEY (contacto_id) REFERENCES salida.contactos(id);


--
-- Name: envios envios_documento_fkey; Type: FK CONSTRAINT; Schema: salida; Owner: -
--

ALTER TABLE ONLY salida.envios
    ADD CONSTRAINT envios_documento_fkey FOREIGN KEY (documento) REFERENCES salida.config_documentos(documento);


--
-- Name: exclusiones exclusiones_registro_id_fkey; Type: FK CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.exclusiones
    ADD CONSTRAINT exclusiones_registro_id_fkey FOREIGN KEY (registro_id) REFERENCES tecnica.registros(id);


--
-- Name: registros fk_registro_formulario_variable; Type: FK CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.registros
    ADD CONSTRAINT fk_registro_formulario_variable FOREIGN KEY (formulario, variable_id) REFERENCES tecnica.formulario_variables(formulario, variable_id);


--
-- Name: formulario_variables formulario_variables_punto_id_fkey; Type: FK CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.formulario_variables
    ADD CONSTRAINT formulario_variables_punto_id_fkey FOREIGN KEY (punto_id) REFERENCES tecnica.puntos(id);


--
-- Name: formulario_variables formulario_variables_variable_id_fkey; Type: FK CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.formulario_variables
    ADD CONSTRAINT formulario_variables_variable_id_fkey FOREIGN KEY (variable_id) REFERENCES tecnica.variables(id);


--
-- Name: puntos puntos_planta_id_fkey; Type: FK CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.puntos
    ADD CONSTRAINT puntos_planta_id_fkey FOREIGN KEY (planta_id) REFERENCES tecnica.plantas(id);


--
-- Name: registros registros_planta_id_fkey; Type: FK CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.registros
    ADD CONSTRAINT registros_planta_id_fkey FOREIGN KEY (planta_id) REFERENCES tecnica.plantas(id);


--
-- Name: registros registros_punto_id_fkey; Type: FK CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.registros
    ADD CONSTRAINT registros_punto_id_fkey FOREIGN KEY (punto_id) REFERENCES tecnica.puntos(id);


--
-- Name: senal_cambio senal_cambio_planta_id_fkey; Type: FK CONSTRAINT; Schema: tecnica; Owner: -
--

ALTER TABLE ONLY tecnica.senal_cambio
    ADD CONSTRAINT senal_cambio_planta_id_fkey FOREIGN KEY (planta_id) REFERENCES tecnica.plantas(id);


--
-- Name: accesos_evidencia; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.accesos_evidencia ENABLE ROW LEVEL SECURITY;

--
-- Name: acciones_correctivas; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.acciones_correctivas ENABLE ROW LEVEL SECURITY;

--
-- Name: acta_acciones; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.acta_acciones ENABLE ROW LEVEL SECURITY;

--
-- Name: acta_fotos; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.acta_fotos ENABLE ROW LEVEL SECURITY;

--
-- Name: acta_hallazgos; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.acta_hallazgos ENABLE ROW LEVEL SECURITY;

--
-- Name: acta_personas; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.acta_personas ENABLE ROW LEVEL SECURITY;

--
-- Name: acta_sellos; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.acta_sellos ENABLE ROW LEVEL SECURITY;

--
-- Name: actas; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.actas ENABLE ROW LEVEL SECURITY;

--
-- Name: apertura_eventos; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.apertura_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: aperturas; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.aperturas ENABLE ROW LEVEL SECURITY;

--
-- Name: calidades_atendiente; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.calidades_atendiente ENABLE ROW LEVEL SECURITY;

--
-- Name: caso_eventos; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.caso_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: consecutivos; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.consecutivos ENABLE ROW LEVEL SECURITY;

--
-- Name: consultas_contrato; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.consultas_contrato ENABLE ROW LEVEL SECURITY;

--
-- Name: diametros_acometida; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.diametros_acometida ENABLE ROW LEVEL SECURITY;

--
-- Name: estados_caso; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.estados_caso ENABLE ROW LEVEL SECURITY;

--
-- Name: estados_custodia; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.estados_custodia ENABLE ROW LEVEL SECURITY;

--
-- Name: estados_medidor; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.estados_medidor ENABLE ROW LEVEL SECURITY;

--
-- Name: estados_sellos; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.estados_sellos ENABLE ROW LEVEL SECURITY;

--
-- Name: motivos_cancelacion; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.motivos_cancelacion ENABLE ROW LEVEL SECURITY;

--
-- Name: parametros; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.parametros ENABLE ROW LEVEL SECURITY;

--
-- Name: tipos_foto; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.tipos_foto ENABLE ROW LEVEL SECURITY;

--
-- Name: tipos_hallazgo; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.tipos_hallazgo ENABLE ROW LEVEL SECURITY;

--
-- Name: transiciones_caso; Type: ROW SECURITY; Schema: acta; Owner: -
--

ALTER TABLE acta.transiciones_caso ENABLE ROW LEVEL SECURITY;

--
-- Name: actividades; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.actividades ENABLE ROW LEVEL SECURITY;

--
-- Name: areas_comercial; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.areas_comercial ENABLE ROW LEVEL SECURITY;

--
-- Name: catalogo_eventos; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.catalogo_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: causales; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.causales ENABLE ROW LEVEL SECURITY;

--
-- Name: causales_tipos; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.causales_tipos ENABLE ROW LEVEL SECURITY;

--
-- Name: consecutivos; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.consecutivos ENABLE ROW LEVEL SECURITY;

--
-- Name: cuadrilla_eventos; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.cuadrilla_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: cuadrillas; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.cuadrillas ENABLE ROW LEVEL SECURITY;

--
-- Name: estados_reporte; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.estados_reporte ENABLE ROW LEVEL SECURITY;

--
-- Name: grupos_reporte; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.grupos_reporte ENABLE ROW LEVEL SECURITY;

--
-- Name: parametros; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.parametros ENABLE ROW LEVEL SECURITY;

--
-- Name: personal_eventos; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.personal_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: preparaciones; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.preparaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: reporte_datos_sensibles; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.reporte_datos_sensibles ENABLE ROW LEVEL SECURITY;

--
-- Name: reporte_eventos; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.reporte_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: reporte_fotos; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.reporte_fotos ENABLE ROW LEVEL SECURITY;

--
-- Name: reportes; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.reportes ENABLE ROW LEVEL SECURITY;

--
-- Name: subtipos_reporte; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.subtipos_reporte ENABLE ROW LEVEL SECURITY;

--
-- Name: tipo_campos; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.tipo_campos ENABLE ROW LEVEL SECURITY;

--
-- Name: tipo_fotos; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.tipo_fotos ENABLE ROW LEVEL SECURITY;

--
-- Name: tipos_reporte; Type: ROW SECURITY; Schema: campo; Owner: -
--

ALTER TABLE campo.tipos_reporte ENABLE ROW LEVEL SECURITY;

--
-- Name: config_documentos; Type: ROW SECURITY; Schema: salida; Owner: -
--

ALTER TABLE salida.config_documentos ENABLE ROW LEVEL SECURITY;

--
-- Name: config_eventos; Type: ROW SECURITY; Schema: salida; Owner: -
--

ALTER TABLE salida.config_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: contactos; Type: ROW SECURITY; Schema: salida; Owner: -
--

ALTER TABLE salida.contactos ENABLE ROW LEVEL SECURITY;

--
-- Name: envio_eventos; Type: ROW SECURITY; Schema: salida; Owner: -
--

ALTER TABLE salida.envio_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: envios; Type: ROW SECURITY; Schema: salida; Owner: -
--

ALTER TABLE salida.envios ENABLE ROW LEVEL SECURITY;

--
-- Name: fallos_encolado; Type: ROW SECURITY; Schema: salida; Owner: -
--

ALTER TABLE salida.fallos_encolado ENABLE ROW LEVEL SECURITY;

--
-- Name: parametros; Type: ROW SECURITY; Schema: salida; Owner: -
--

ALTER TABLE salida.parametros ENABLE ROW LEVEL SECURITY;

--
-- Name: textos_autorizacion; Type: ROW SECURITY; Schema: salida; Owner: -
--

ALTER TABLE salida.textos_autorizacion ENABLE ROW LEVEL SECURITY;

--
-- Name: exclusiones; Type: ROW SECURITY; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.exclusiones ENABLE ROW LEVEL SECURITY;

--
-- Name: formulario_variables; Type: ROW SECURITY; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.formulario_variables ENABLE ROW LEVEL SECURITY;

--
-- Name: personal_tecnico_eventos; Type: ROW SECURITY; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.personal_tecnico_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: plantas; Type: ROW SECURITY; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.plantas ENABLE ROW LEVEL SECURITY;

--
-- Name: puntos; Type: ROW SECURITY; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.puntos ENABLE ROW LEVEL SECURITY;

--
-- Name: registros; Type: ROW SECURITY; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.registros ENABLE ROW LEVEL SECURITY;

--
-- Name: senal_cambio; Type: ROW SECURITY; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.senal_cambio ENABLE ROW LEVEL SECURITY;

--
-- Name: variables; Type: ROW SECURITY; Schema: tecnica; Owner: -
--

ALTER TABLE tecnica.variables ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA salida; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA salida TO dell_envios;


--
-- Name: FUNCTION f_abrir(p_email text, p_perfil text, p_lat numeric, p_lon numeric, p_precision numeric, p_reporte uuid, p_correccion_de uuid, p_motivo text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_abrir(p_email text, p_perfil text, p_lat numeric, p_lon numeric, p_precision numeric, p_reporte uuid, p_correccion_de uuid, p_motivo text) FROM PUBLIC;


--
-- Name: FUNCTION f_acta_coherente(); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_acta_coherente() FROM PUBLIC;


--
-- Name: FUNCTION f_acta_no_cancelada(); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_acta_no_cancelada() FROM PUBLIC;


--
-- Name: FUNCTION f_ahora_bogota(); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_ahora_bogota() FROM PUBLIC;


--
-- Name: FUNCTION f_apertura_cancelada(p_apertura uuid); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_apertura_cancelada(p_apertura uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text) FROM PUBLIC;


--
-- Name: FUNCTION f_autorizar(p_solicitante text, p_capacidad text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_autorizar(p_solicitante text, p_capacidad text) FROM PUBLIC;


--
-- Name: FUNCTION f_autorizar_alguna(p_solicitante text, p_caps text[]); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_autorizar_alguna(p_solicitante text, p_caps text[]) FROM PUBLIC;


--
-- Name: FUNCTION f_bool(p_c jsonb, p_k text, p_req boolean, p_def boolean); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_bool(p_c jsonb, p_k text, p_req boolean, p_def boolean) FROM PUBLIC;


--
-- Name: FUNCTION f_capacidades(p_email text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_capacidades(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_codigo_inmutable(); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_codigo_inmutable() FROM PUBLIC;


--
-- Name: FUNCTION f_contenido_editable(p_acta uuid); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_contenido_editable(p_acta uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_contrato_existe(p_contrato text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_contrato_existe(p_contrato text) FROM PUBLIC;


--
-- Name: FUNCTION f_cupo_aperturas(p_email text, p_perfil text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_cupo_aperturas(p_email text, p_perfil text) FROM PUBLIC;


--
-- Name: FUNCTION f_cupo_lecturas(p_email text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_cupo_lecturas(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_cupo_mis_actas(p_email text, p_perfil text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_cupo_mis_actas(p_email text, p_perfil text) FROM PUBLIC;


--
-- Name: FUNCTION f_cupo_precargas(p_email text, p_perfil text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_cupo_precargas(p_email text, p_perfil text) FROM PUBLIC;


--
-- Name: FUNCTION f_error(p_mensaje text, p_codigo text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_error(p_mensaje text, p_codigo text) FROM PUBLIC;


--
-- Name: FUNCTION f_error_limite(p_mensaje text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_error_limite(p_mensaje text) FROM PUBLIC;


--
-- Name: FUNCTION f_estado_actual(p_raiz uuid); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_estado_actual(p_raiz uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_evento_apertura_coherente(); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_evento_apertura_coherente() FROM PUBLIC;


--
-- Name: FUNCTION f_evento_coherente(); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_evento_coherente() FROM PUBLIC;


--
-- Name: FUNCTION f_exigir_caso(p_raiz uuid); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_exigir_caso(p_raiz uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_hoy_bogota(); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_hoy_bogota() FROM PUBLIC;


--
-- Name: FUNCTION f_motivo(p_motivo text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_motivo(p_motivo text) FROM PUBLIC;


--
-- Name: FUNCTION f_num(p_c jsonb, p_k text, p_min numeric, p_max numeric); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_num(p_c jsonb, p_k text, p_min numeric, p_max numeric) FROM PUBLIC;


--
-- Name: FUNCTION f_oculto(p_raiz uuid); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_oculto(p_raiz uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_param(p_clave text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_param(p_clave text) FROM PUBLIC;


--
-- Name: FUNCTION f_perfil(p_email text); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_perfil(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_sello(p_acta uuid); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_sello(p_acta uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_solo_agregar(); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_solo_agregar() FROM PUBLIC;


--
-- Name: FUNCTION f_texto_espera(p_primero timestamp with time zone, p_ventana interval); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_texto_espera(p_primero timestamp with time zone, p_ventana interval) FROM PUBLIC;


--
-- Name: FUNCTION f_txt(p_c jsonb, p_k text, p_max integer, p_req boolean); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_txt(p_c jsonb, p_k text, p_max integer, p_req boolean) FROM PUBLIC;


--
-- Name: FUNCTION f_validar_detalle(p_accion text, p_campos jsonb, p_detalle jsonb); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_validar_detalle(p_accion text, p_campos jsonb, p_detalle jsonb) FROM PUBLIC;


--
-- Name: FUNCTION f_vigente(p_raiz uuid); Type: ACL; Schema: acta; Owner: -
--

REVOKE ALL ON FUNCTION acta.f_vigente(p_raiz uuid) FROM PUBLIC;


--
-- Name: FUNCTION recalcular_cambio_medidor(p_periodo text); Type: ACL; Schema: bi; Owner: -
--

REVOKE ALL ON FUNCTION bi.recalcular_cambio_medidor(p_periodo text) FROM PUBLIC;


--
-- Name: FUNCTION recalcular_consumo_promedio(p_periodo text); Type: ACL; Schema: bi; Owner: -
--

REVOKE ALL ON FUNCTION bi.recalcular_consumo_promedio(p_periodo text) FROM PUBLIC;


--
-- Name: FUNCTION recalcular_ficha_contrato(p_periodo text); Type: ACL; Schema: bi; Owner: -
--

REVOKE ALL ON FUNCTION bi.recalcular_ficha_contrato(p_periodo text) FROM PUBLIC;


--
-- Name: FUNCTION recalcular_submedicion(p_periodo text); Type: ACL; Schema: bi; Owner: -
--

REVOKE ALL ON FUNCTION bi.recalcular_submedicion(p_periodo text) FROM PUBLIC;


--
-- Name: FUNCTION f_fecha_texto(p text); Type: ACL; Schema: bi_interno; Owner: -
--

REVOKE ALL ON FUNCTION bi_interno.f_fecha_texto(p text) FROM PUBLIC;


--
-- Name: FUNCTION f_sin_prefijo(p text); Type: ACL; Schema: bi_interno; Owner: -
--

REVOKE ALL ON FUNCTION bi_interno.f_sin_prefijo(p text) FROM PUBLIC;


--
-- Name: FUNCTION f_actividades_persona(p_email text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_actividades_persona(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_actividades_propias(p_email text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_actividades_propias(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_ahora_bogota(); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_ahora_bogota() FROM PUBLIC;


--
-- Name: FUNCTION f_area_vigente(p_email text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_area_vigente(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text) FROM PUBLIC;


--
-- Name: FUNCTION f_autorizar_admin(p_solicitante text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_autorizar_admin(p_solicitante text) FROM PUBLIC;


--
-- Name: FUNCTION f_autorizar_analisis(p_solicitante text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_autorizar_analisis(p_solicitante text) FROM PUBLIC;


--
-- Name: FUNCTION f_autorizar_personal(p_solicitante text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_autorizar_personal(p_solicitante text) FROM PUBLIC;


--
-- Name: FUNCTION f_autorizar_reporte(p_solicitante text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_autorizar_reporte(p_solicitante text) FROM PUBLIC;


--
-- Name: FUNCTION f_autorizar_supervision(p_solicitante text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_autorizar_supervision(p_solicitante text) FROM PUBLIC;


--
-- Name: FUNCTION f_cargo_vigente(p_email text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_cargo_vigente(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_catalogo_d_inmutable(); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_catalogo_d_inmutable() FROM PUBLIC;


--
-- Name: FUNCTION f_codigo_desde_nombre(p_nombre text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_codigo_desde_nombre(p_nombre text) FROM PUBLIC;


--
-- Name: FUNCTION f_codigo_inmutable(); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_codigo_inmutable() FROM PUBLIC;


--
-- Name: FUNCTION f_consultas_analisis_inmutable(); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_consultas_analisis_inmutable() FROM PUBLIC;


--
-- Name: FUNCTION f_cuadrilla_actividades(p_cuadrilla bigint); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_cuadrilla_actividades(p_cuadrilla bigint) FROM PUBLIC;


--
-- Name: FUNCTION f_cuadrilla_vigente(p_email text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_cuadrilla_vigente(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_cupo_contratos(p_email text, p_perfil text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_cupo_contratos(p_email text, p_perfil text) FROM PUBLIC;


--
-- Name: FUNCTION f_cupo_contratos_falsos(p_email text, p_perfil text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_cupo_contratos_falsos(p_email text, p_perfil text) FROM PUBLIC;


--
-- Name: FUNCTION f_cupo_preparaciones(p_email text, p_perfil text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_cupo_preparaciones(p_email text, p_perfil text) FROM PUBLIC;


--
-- Name: FUNCTION f_cupo_reportes(p_email text, p_perfil text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_cupo_reportes(p_email text, p_perfil text) FROM PUBLIC;


--
-- Name: FUNCTION f_cupo_tipo(p_email text, p_perfil text, p_tipo_id bigint, p_limite integer, p_nombre text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_cupo_tipo(p_email text, p_perfil text, p_tipo_id bigint, p_limite integer, p_nombre text) FROM PUBLIC;


--
-- Name: FUNCTION f_error(p_mensaje text, p_codigo text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_error(p_mensaje text, p_codigo text) FROM PUBLIC;


--
-- Name: FUNCTION f_error_limite(p_mensaje text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_error_limite(p_mensaje text) FROM PUBLIC;


--
-- Name: FUNCTION f_estado_actual(p_reporte uuid); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_estado_actual(p_reporte uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_evento_coherente(); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_evento_coherente() FROM PUBLIC;


--
-- Name: FUNCTION f_filtrar(p_filtros jsonb); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_filtrar(p_filtros jsonb) FROM PUBLIC;


--
-- Name: FUNCTION f_formularios_asignados(p_email text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_formularios_asignados(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_formularios_personal(); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_formularios_personal() FROM PUBLIC;


--
-- Name: FUNCTION f_grupos_cercanos(p_eps_m numeric, p_ids uuid[]); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_grupos_cercanos(p_eps_m numeric, p_ids uuid[]) FROM PUBLIC;


--
-- Name: FUNCTION f_miembros_cuadrillas(); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_miembros_cuadrillas() FROM PUBLIC;


--
-- Name: FUNCTION f_motivo_personal(p_motivo text, p_obligatorio boolean); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_motivo_personal(p_motivo text, p_obligatorio boolean) FROM PUBLIC;


--
-- Name: FUNCTION f_no_borrar_catalogo(); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_no_borrar_catalogo() FROM PUBLIC;


--
-- Name: FUNCTION f_oculto(p_reporte uuid); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_oculto(p_reporte uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_opciones_validas(p jsonb); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_opciones_validas(p jsonb) FROM PUBLIC;


--
-- Name: FUNCTION f_original_actual(p_reporte uuid); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_original_actual(p_reporte uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_param(p_clave text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_param(p_clave text) FROM PUBLIC;


--
-- Name: FUNCTION f_perfil(p_email text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_perfil(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_persona_comercial(p_email text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_persona_comercial(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_quien_puede(p_actividad text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_quien_puede(p_actividad text) FROM PUBLIC;


--
-- Name: FUNCTION f_reporte_coherente(); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_reporte_coherente() FROM PUBLIC;


--
-- Name: FUNCTION f_siguiente_consecutivo(p_tipo_id bigint); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_siguiente_consecutivo(p_tipo_id bigint) FROM PUBLIC;


--
-- Name: FUNCTION f_solo_agregar(); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_solo_agregar() FROM PUBLIC;


--
-- Name: FUNCTION f_tecnica_claves(p_solicitante text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_tecnica_claves(p_solicitante text) FROM PUBLIC;


--
-- Name: FUNCTION f_tecnica_entrar(p_solicitante text, p_tipo text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_tecnica_entrar(p_solicitante text, p_tipo text) FROM PUBLIC;


--
-- Name: FUNCTION f_telefonos(p_texto text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_telefonos(p_texto text) FROM PUBLIC;


--
-- Name: FUNCTION f_texto_consecutivo(p_prefijo text, p_num bigint); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_texto_consecutivo(p_prefijo text, p_num bigint) FROM PUBLIC;


--
-- Name: FUNCTION f_texto_espera(p_primero timestamp with time zone, p_ventana_min integer); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_texto_espera(p_primero timestamp with time zone, p_ventana_min integer) FROM PUBLIC;


--
-- Name: FUNCTION f_texto_ventana(p_ventana_min integer); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_texto_ventana(p_ventana_min integer) FROM PUBLIC;


--
-- Name: FUNCTION f_tipo_general(p_codigo text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_tipo_general(p_codigo text) FROM PUBLIC;


--
-- Name: FUNCTION f_validar_datos(p_tipo_id bigint, p_datos jsonb, p_exigir boolean); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_validar_datos(p_tipo_id bigint, p_datos jsonb, p_exigir boolean) FROM PUBLIC;


--
-- Name: FUNCTION f_validar_orden_trabajo(p_orden uuid, p_email text, p_tipo_id bigint); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_validar_orden_trabajo(p_orden uuid, p_email text, p_tipo_id bigint) FROM PUBLIC;


--
-- Name: FUNCTION f_verificar(p_solicitante text, p_modo text); Type: ACL; Schema: campo; Owner: -
--

REVOKE ALL ON FUNCTION campo.f_verificar(p_solicitante text, p_modo text) FROM PUBLIC;


--
-- Name: FUNCTION geoportal_acta_abrir(p_solicitante text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_reporte_id uuid, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_abrir(p_solicitante text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_reporte_id uuid, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_abrir(p_solicitante text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_reporte_id uuid, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_aperturas_sin_registrar(p_solicitante text, p_filtros jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_aperturas_sin_registrar(p_solicitante text, p_filtros jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_aperturas_sin_registrar(p_solicitante text, p_filtros jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_cambiar_estado(p_solicitante text, p_acta_raiz_id uuid, p_estado text, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_cambiar_estado(p_solicitante text, p_acta_raiz_id uuid, p_estado text, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_cambiar_estado(p_solicitante text, p_acta_raiz_id uuid, p_estado text, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_cancelar(p_solicitante text, p_acta_id uuid, p_motivo_codigo text, p_motivo_texto text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_cancelar(p_solicitante text, p_acta_id uuid, p_motivo_codigo text, p_motivo_texto text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_cancelar(p_solicitante text, p_acta_id uuid, p_motivo_codigo text, p_motivo_texto text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_cercanas(p_solicitante text, p_acta_id uuid, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_cercanas(p_solicitante text, p_acta_id uuid, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_cercanas(p_solicitante text, p_acta_id uuid, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_conciliacion(p_solicitante text, p_filtros jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_conciliacion(p_solicitante text, p_filtros jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_conciliacion(p_solicitante text, p_filtros jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_custodia_medidor(p_solicitante text, p_acta_raiz_id uuid, p_custodia text, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_custodia_medidor(p_solicitante text, p_acta_raiz_id uuid, p_custodia text, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_custodia_medidor(p_solicitante text, p_acta_raiz_id uuid, p_custodia text, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_foto_papel_posterior(p_solicitante text, p_acta_id uuid, p_orden integer, p_ruta text, p_huella text, p_detalle text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_foto_papel_posterior(p_solicitante text, p_acta_id uuid, p_orden integer, p_ruta text, p_huella text, p_detalle text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_foto_papel_posterior(p_solicitante text, p_acta_id uuid, p_orden integer, p_ruta text, p_huella text, p_detalle text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_foto_ruta(p_solicitante text, p_acta_id uuid, p_orden integer, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_foto_ruta(p_solicitante text, p_acta_id uuid, p_orden integer, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_foto_ruta(p_solicitante text, p_acta_id uuid, p_orden integer, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_gestionar_catalogo(p_solicitante text, p_entidad text, p_accion text, p_datos jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_gestionar_catalogo(p_solicitante text, p_entidad text, p_accion text, p_datos jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_gestionar_catalogo(p_solicitante text, p_entidad text, p_accion text, p_datos jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_iniciar_correccion(p_solicitante text, p_acta_id uuid, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_iniciar_correccion(p_solicitante text, p_acta_id uuid, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_iniciar_correccion(p_solicitante text, p_acta_id uuid, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_listar(p_solicitante text, p_filtros jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_listar(p_solicitante text, p_filtros jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_listar(p_solicitante text, p_filtros jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_mis_actas(p_solicitante text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_mis_actas(p_solicitante text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_mis_actas(p_solicitante text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_motivos_cancelacion(p_solicitante text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_motivos_cancelacion(p_solicitante text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_motivos_cancelacion(p_solicitante text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_obtener(p_solicitante text, p_id uuid, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_obtener(p_solicitante text, p_id uuid, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_obtener(p_solicitante text, p_id uuid, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_obtener_formulario(p_solicitante text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_obtener_formulario(p_solicitante text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_obtener_formulario(p_solicitante text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_ocultar(p_solicitante text, p_acta_raiz_id uuid, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_ocultar(p_solicitante text, p_acta_raiz_id uuid, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_ocultar(p_solicitante text, p_acta_raiz_id uuid, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_precargar_predio(p_solicitante text, p_contrato text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_precargar_predio(p_solicitante text, p_contrato text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_precargar_predio(p_solicitante text, p_contrato text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_predios_cercanos(p_solicitante text, p_lat numeric, p_lon numeric, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_predios_cercanos(p_solicitante text, p_lat numeric, p_lon numeric, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_predios_cercanos(p_solicitante text, p_lat numeric, p_lon numeric, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_preparar_subida(p_solicitante text, p_acta_id uuid, p_fotos jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_preparar_subida(p_solicitante text, p_acta_id uuid, p_fotos jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_preparar_subida(p_solicitante text, p_acta_id uuid, p_fotos jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_registrar(p_solicitante text, p_acta_id uuid, p_contenido jsonb, p_huellas jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_registrar(p_solicitante text, p_acta_id uuid, p_contenido jsonb, p_huellas jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_registrar(p_solicitante text, p_acta_id uuid, p_contenido jsonb, p_huellas jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_reincluir(p_solicitante text, p_acta_raiz_id uuid, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_reincluir(p_solicitante text, p_acta_raiz_id uuid, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_reincluir(p_solicitante text, p_acta_raiz_id uuid, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_acta_vincular_contrato(p_solicitante text, p_acta_raiz_id uuid, p_contrato text, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_acta_vincular_contrato(p_solicitante text, p_acta_raiz_id uuid, p_contrato text, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_acta_vincular_contrato(p_solicitante text, p_acta_raiz_id uuid, p_contrato text, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_admin_listar(p_solicitante text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_admin_listar(p_solicitante text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_admin_listar(p_solicitante text) TO service_role;


--
-- Name: FUNCTION geoportal_admin_permisos(p_solicitante text, p_email text, p_explorar boolean, p_focalizacion boolean, p_comercial boolean, p_rutas boolean, p_horario text, p_dias text, p_dashboard boolean, p_registro_tecnico boolean, p_dashboard_tecnico boolean, p_ip text, p_campo boolean, p_dashboard_campo boolean, p_acta boolean, p_dashboard_acta boolean, p_aseo boolean, p_dashboard_aseo boolean, p_analisis_contrato boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_admin_permisos(p_solicitante text, p_email text, p_explorar boolean, p_focalizacion boolean, p_comercial boolean, p_rutas boolean, p_horario text, p_dias text, p_dashboard boolean, p_registro_tecnico boolean, p_dashboard_tecnico boolean, p_ip text, p_campo boolean, p_dashboard_campo boolean, p_acta boolean, p_dashboard_acta boolean, p_aseo boolean, p_dashboard_aseo boolean, p_analisis_contrato boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_admin_permisos(p_solicitante text, p_email text, p_explorar boolean, p_focalizacion boolean, p_comercial boolean, p_rutas boolean, p_horario text, p_dias text, p_dashboard boolean, p_registro_tecnico boolean, p_dashboard_tecnico boolean, p_ip text, p_campo boolean, p_dashboard_campo boolean, p_acta boolean, p_dashboard_acta boolean, p_aseo boolean, p_dashboard_aseo boolean, p_analisis_contrato boolean) TO service_role;


--
-- Name: FUNCTION geoportal_campo_analisis_cercanos(p_solicitante text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_analisis_cercanos(p_solicitante text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_analisis_cercanos(p_solicitante text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_analisis_contrato(p_solicitante text, p_contrato text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_analisis_contrato(p_solicitante text, p_contrato text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_analisis_contrato(p_solicitante text, p_contrato text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_cambiar_estado(p_solicitante text, p_id uuid, p_estado text, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_cambiar_estado(p_solicitante text, p_id uuid, p_estado text, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_cambiar_estado(p_solicitante text, p_id uuid, p_estado text, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_catalogo_cambiar(p_solicitante text, p_datos jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_catalogo_cambiar(p_solicitante text, p_datos jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_catalogo_cambiar(p_solicitante text, p_datos jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_catalogo_lectura(p_solicitante text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_catalogo_lectura(p_solicitante text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_catalogo_lectura(p_solicitante text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_catalogos(p_solicitante text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_catalogos(p_solicitante text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_catalogos(p_solicitante text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_origen text, p_fotos jsonb, p_ip text, p_datos jsonb, p_resultado text, p_causal text, p_orden_trabajo_id uuid, p_inicio_dispositivo timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_origen text, p_fotos jsonb, p_ip text, p_datos jsonb, p_resultado text, p_causal text, p_orden_trabajo_id uuid, p_inicio_dispositivo timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_origen text, p_fotos jsonb, p_ip text, p_datos jsonb, p_resultado text, p_causal text, p_orden_trabajo_id uuid, p_inicio_dispositivo timestamp with time zone) TO service_role;


--
-- Name: FUNCTION geoportal_campo_cuadrilla_cambiar(p_solicitante text, p_datos jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_cuadrilla_cambiar(p_solicitante text, p_datos jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_cuadrilla_cambiar(p_solicitante text, p_datos jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_cuadrillas(p_solicitante text, p_filtros jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_cuadrillas(p_solicitante text, p_filtros jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_cuadrillas(p_solicitante text, p_filtros jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_datos_sensibles(p_solicitante text, p_id uuid, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_datos_sensibles(p_solicitante text, p_id uuid, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_datos_sensibles(p_solicitante text, p_id uuid, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_descarga_cerrar(p_solicitante text, p_descarga_id bigint, p_filas integer, p_resultado text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_descarga_cerrar(p_solicitante text, p_descarga_id bigint, p_filas integer, p_resultado text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_descarga_cerrar(p_solicitante text, p_descarga_id bigint, p_filas integer, p_resultado text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_descarga_iniciar(p_solicitante text, p_filtros jsonb, p_formato text, p_incluir_autor boolean, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_descarga_iniciar(p_solicitante text, p_filtros jsonb, p_formato text, p_incluir_autor boolean, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_descarga_iniciar(p_solicitante text, p_filtros jsonb, p_formato text, p_incluir_autor boolean, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_descarga_pagina(p_solicitante text, p_descarga_id bigint, p_despues_de bigint, p_limite integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_descarga_pagina(p_solicitante text, p_descarga_id bigint, p_despues_de bigint, p_limite integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_descarga_pagina(p_solicitante text, p_descarga_id bigint, p_despues_de bigint, p_limite integer) TO service_role;


--
-- Name: FUNCTION geoportal_campo_foto_ruta(p_solicitante text, p_id uuid, p_orden integer, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_foto_ruta(p_solicitante text, p_id uuid, p_orden integer, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_foto_ruta(p_solicitante text, p_id uuid, p_orden integer, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_gestionar_catalogo(p_solicitante text, p_entidad text, p_accion text, p_datos jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_gestionar_catalogo(p_solicitante text, p_entidad text, p_accion text, p_datos jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_gestionar_catalogo(p_solicitante text, p_entidad text, p_accion text, p_datos jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_guardar_parametro(p_solicitante text, p_cambios jsonb, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_guardar_parametro(p_solicitante text, p_cambios jsonb, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_guardar_parametro(p_solicitante text, p_cambios jsonb, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_historial_personal(p_solicitante text, p_filtros jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_historial_personal(p_solicitante text, p_filtros jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_historial_personal(p_solicitante text, p_filtros jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_indicadores(p_solicitante text, p_filtros jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_indicadores(p_solicitante text, p_filtros jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_indicadores(p_solicitante text, p_filtros jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_listar_reportes(p_solicitante text, p_filtros jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_listar_reportes(p_solicitante text, p_filtros jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_listar_reportes(p_solicitante text, p_filtros jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_obtener_formulario(p_solicitante text, p_incluir_inactivos boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_obtener_formulario(p_solicitante text, p_incluir_inactivos boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_obtener_formulario(p_solicitante text, p_incluir_inactivos boolean) TO service_role;


--
-- Name: FUNCTION geoportal_campo_obtener_reporte(p_solicitante text, p_id uuid, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_obtener_reporte(p_solicitante text, p_id uuid, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_obtener_reporte(p_solicitante text, p_id uuid, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_ocultar_reporte(p_solicitante text, p_id uuid, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_ocultar_reporte(p_solicitante text, p_id uuid, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_ocultar_reporte(p_solicitante text, p_id uuid, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_personal(p_solicitante text, p_filtros jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_personal(p_solicitante text, p_filtros jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_personal(p_solicitante text, p_filtros jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_personal_actividad(p_solicitante text, p_actividad text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_personal_actividad(p_solicitante text, p_actividad text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_personal_actividad(p_solicitante text, p_actividad text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_personal_cambiar(p_solicitante text, p_persona text, p_tipo text, p_formulario text, p_cargo text, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_personal_cambiar(p_solicitante text, p_persona text, p_tipo text, p_formulario text, p_cargo text, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_personal_cambiar(p_solicitante text, p_persona text, p_tipo text, p_formulario text, p_cargo text, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_personal_fijar(p_solicitante text, p_persona text, p_tipo text, p_datos jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_personal_fijar(p_solicitante text, p_persona text, p_tipo text, p_datos jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_personal_fijar(p_solicitante text, p_persona text, p_tipo text, p_datos jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_preparar_subida(p_solicitante text, p_cantidad integer, p_origen text, p_ip text, p_tipo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_preparar_subida(p_solicitante text, p_cantidad integer, p_origen text, p_ip text, p_tipo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_preparar_subida(p_solicitante text, p_cantidad integer, p_origen text, p_ip text, p_tipo text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_reincluir_reporte(p_solicitante text, p_id uuid, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_reincluir_reporte(p_solicitante text, p_id uuid, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_reincluir_reporte(p_solicitante text, p_id uuid, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_tec_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_fotos jsonb, p_ip text, p_datos jsonb, p_resultado text, p_causal text, p_inicio_dispositivo timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_tec_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_fotos jsonb, p_ip text, p_datos jsonb, p_resultado text, p_causal text, p_inicio_dispositivo timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_tec_crear_reporte(p_solicitante text, p_id uuid, p_tipo text, p_subtipo text, p_descripcion text, p_contrato text, p_lat numeric, p_lon numeric, p_precision_m numeric, p_riesgo_inmediato boolean, p_fotos jsonb, p_ip text, p_datos jsonb, p_resultado text, p_causal text, p_inicio_dispositivo timestamp with time zone) TO service_role;


--
-- Name: FUNCTION geoportal_campo_tec_formulario(p_solicitante text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_tec_formulario(p_solicitante text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_tec_formulario(p_solicitante text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_tec_preparar_subida(p_solicitante text, p_cantidad integer, p_ip text, p_tipo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_tec_preparar_subida(p_solicitante text, p_cantidad integer, p_ip text, p_tipo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_tec_preparar_subida(p_solicitante text, p_cantidad integer, p_ip text, p_tipo text) TO service_role;


--
-- Name: FUNCTION geoportal_campo_vincular_duplicado(p_solicitante text, p_id uuid, p_original_id uuid, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_campo_vincular_duplicado(p_solicitante text, p_id uuid, p_original_id uuid, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_campo_vincular_duplicado(p_solicitante text, p_id uuid, p_original_id uuid, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_envio_config(p_solicitante text, p_documento text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_envio_config(p_solicitante text, p_documento text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_envio_config(p_solicitante text, p_documento text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_envio_depurar(p_solicitante text, p_solo_contar boolean, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_envio_depurar(p_solicitante text, p_solo_contar boolean, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_envio_depurar(p_solicitante text, p_solo_contar boolean, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_envio_estado(p_solicitante text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_envio_estado(p_solicitante text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_envio_estado(p_solicitante text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_envio_guardar_config(p_solicitante text, p_documento text, p_habilitado boolean, p_copias jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_envio_guardar_config(p_solicitante text, p_documento text, p_habilitado boolean, p_copias jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_envio_guardar_config(p_solicitante text, p_documento text, p_habilitado boolean, p_copias jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_envio_nuevo_texto(p_solicitante text, p_texto text, p_borrador boolean, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_envio_nuevo_texto(p_solicitante text, p_texto text, p_borrador boolean, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_envio_nuevo_texto(p_solicitante text, p_texto text, p_borrador boolean, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_envio_preparar(p_solicitante text, p_documento text, p_registro_id uuid, p_contacto jsonb, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_envio_preparar(p_solicitante text, p_documento text, p_registro_id uuid, p_contacto jsonb, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_envio_preparar(p_solicitante text, p_documento text, p_registro_id uuid, p_contacto jsonb, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_mis_permisos(p_email text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_mis_permisos(p_email text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_mis_permisos(p_email text) TO service_role;


--
-- Name: FUNCTION geoportal_puede(p_email text, p_modo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_puede(p_email text, p_modo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_puede(p_email text, p_modo text) TO service_role;


--
-- Name: FUNCTION geoportal_tec_asignar_formulario(p_solicitante text, p_persona text, p_formulario text, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_tec_asignar_formulario(p_solicitante text, p_persona text, p_formulario text, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_tec_asignar_formulario(p_solicitante text, p_persona text, p_formulario text, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_tec_cambiar_estado_tecnica(p_solicitante text, p_persona text, p_activo boolean, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_tec_cambiar_estado_tecnica(p_solicitante text, p_persona text, p_activo boolean, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_tec_cambiar_estado_tecnica(p_solicitante text, p_persona text, p_activo boolean, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_tec_excluir_registro(p_solicitante text, p_lote_id uuid, p_registro_id bigint, p_motivo text, p_accion text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_tec_excluir_registro(p_solicitante text, p_lote_id uuid, p_registro_id bigint, p_motivo text, p_accion text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_tec_excluir_registro(p_solicitante text, p_lote_id uuid, p_registro_id bigint, p_motivo text, p_accion text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_tec_listar_registros(p_solicitante text, p_filtros jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_tec_listar_registros(p_solicitante text, p_filtros jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_tec_listar_registros(p_solicitante text, p_filtros jsonb) TO service_role;


--
-- Name: FUNCTION geoportal_tec_mis_formularios(p_solicitante text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_tec_mis_formularios(p_solicitante text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_tec_mis_formularios(p_solicitante text) TO service_role;


--
-- Name: FUNCTION geoportal_tec_obtener_formulario(p_solicitante text, p_formulario text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_tec_obtener_formulario(p_solicitante text, p_formulario text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_tec_obtener_formulario(p_solicitante text, p_formulario text) TO service_role;


--
-- Name: FUNCTION geoportal_tec_quitar_formulario(p_solicitante text, p_persona text, p_formulario text, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_tec_quitar_formulario(p_solicitante text, p_persona text, p_formulario text, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_tec_quitar_formulario(p_solicitante text, p_persona text, p_formulario text, p_motivo text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_tec_registrar_medicion(p_solicitante text, p_formulario text, p_planta text, p_hora_muestra text, p_valores jsonb, p_punto text, p_clave_envio text, p_ip text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_tec_registrar_medicion(p_solicitante text, p_formulario text, p_planta text, p_hora_muestra text, p_valores jsonb, p_punto text, p_clave_envio text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_tec_registrar_medicion(p_solicitante text, p_formulario text, p_planta text, p_hora_muestra text, p_valores jsonb, p_punto text, p_clave_envio text, p_ip text) TO service_role;


--
-- Name: FUNCTION geoportal_tec_resumen_operador(p_solicitante text, p_formulario text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.geoportal_tec_resumen_operador(p_solicitante text, p_formulario text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geoportal_tec_resumen_operador(p_solicitante text, p_formulario text) TO service_role;


--
-- Name: FUNCTION f_autorizar_captura(p_solicitante text, p_documento text); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_autorizar_captura(p_solicitante text, p_documento text) FROM PUBLIC;


--
-- Name: FUNCTION f_constancia_acta(p_id uuid); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_constancia_acta(p_id uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_constancia_campo(p_id uuid); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_constancia_campo(p_id uuid) FROM PUBLIC;


--
-- Name: FUNCTION f_contacto_actualizable(); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_contacto_actualizable() FROM PUBLIC;


--
-- Name: FUNCTION f_depurar(p_actor text, p_solo_contar boolean); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_depurar(p_actor text, p_solo_contar boolean) FROM PUBLIC;


--
-- Name: FUNCTION f_disparar_acta(); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_disparar_acta() FROM PUBLIC;


--
-- Name: FUNCTION f_disparar_campo(); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_disparar_campo() FROM PUBLIC;


--
-- Name: FUNCTION f_encolar(p_esquema text, p_registro uuid, p_documento text, p_consecutivo text, p_constancia jsonb, p_autor text); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_encolar(p_esquema text, p_registro uuid, p_documento text, p_consecutivo text, p_constancia jsonb, p_autor text) FROM PUBLIC;


--
-- Name: FUNCTION f_envio_actualizable(); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_envio_actualizable() FROM PUBLIC;


--
-- Name: FUNCTION f_error(p_mensaje text, p_codigo text); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_error(p_mensaje text, p_codigo text) FROM PUBLIC;


--
-- Name: FUNCTION f_param(p_clave text); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_param(p_clave text) FROM PUBLIC;


--
-- Name: FUNCTION f_registro_vigente(p_esquema text, p_id uuid); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_registro_vigente(p_esquema text, p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION salida.f_registro_vigente(p_esquema text, p_id uuid) TO dell_envios;


--
-- Name: FUNCTION f_solo_agregar(); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_solo_agregar() FROM PUBLIC;


--
-- Name: FUNCTION f_texto_vigente(); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.f_texto_vigente() FROM PUBLIC;


--
-- Name: FUNCTION liberar_envio(p_envio_id uuid, p_lease_id uuid); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.liberar_envio(p_envio_id uuid, p_lease_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION salida.liberar_envio(p_envio_id uuid, p_lease_id uuid) TO dell_envios;


--
-- Name: FUNCTION marcar_envio(p_envio_id uuid, p_lease_id uuid, p_estado text, p_detalle jsonb, p_reintentable boolean); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.marcar_envio(p_envio_id uuid, p_lease_id uuid, p_estado text, p_detalle jsonb, p_reintentable boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION salida.marcar_envio(p_envio_id uuid, p_lease_id uuid, p_estado text, p_detalle jsonb, p_reintentable boolean) TO dell_envios;


--
-- Name: FUNCTION reportar_rebote(p_envio_id uuid, p_detalle jsonb); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.reportar_rebote(p_envio_id uuid, p_detalle jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION salida.reportar_rebote(p_envio_id uuid, p_detalle jsonb) TO dell_envios;


--
-- Name: FUNCTION tomar_envios(p_limite integer, p_arriendo_segundos integer); Type: ACL; Schema: salida; Owner: -
--

REVOKE ALL ON FUNCTION salida.tomar_envios(p_limite integer, p_arriendo_segundos integer) FROM PUBLIC;
GRANT ALL ON FUNCTION salida.tomar_envios(p_limite integer, p_arriendo_segundos integer) TO dell_envios;


--
-- Name: FUNCTION f_ahora_bogota(); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_ahora_bogota() FROM PUBLIC;


--
-- Name: FUNCTION f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_auditar(p_email text, p_accion text, p_ref text, p_detalle jsonb, p_ip text) FROM PUBLIC;


--
-- Name: FUNCTION f_autorizar_captura(p_solicitante text, p_formulario text); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_autorizar_captura(p_solicitante text, p_formulario text) FROM PUBLIC;


--
-- Name: FUNCTION f_autorizar_supervision(p_solicitante text); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_autorizar_supervision(p_solicitante text) FROM PUBLIC;


--
-- Name: FUNCTION f_catalogo_protegido(); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_catalogo_protegido() FROM PUBLIC;


--
-- Name: FUNCTION f_error(p_mensaje text, p_codigo text); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_error(p_mensaje text, p_codigo text) FROM PUBLIC;


--
-- Name: FUNCTION f_fecha_muestra(p_hora time without time zone, p_ahora timestamp without time zone); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_fecha_muestra(p_hora time without time zone, p_ahora timestamp without time zone) FROM PUBLIC;


--
-- Name: FUNCTION f_formulario_asignado(p_email text, p_formulario text); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_formulario_asignado(p_email text, p_formulario text) FROM PUBLIC;


--
-- Name: FUNCTION f_formularios(); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_formularios() FROM PUBLIC;


--
-- Name: FUNCTION f_generar_vista_ancha(p_formulario text); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_generar_vista_ancha(p_formulario text) FROM PUBLIC;


--
-- Name: FUNCTION f_marca_rango(p_valor numeric, p_min numeric, p_max numeric); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_marca_rango(p_valor numeric, p_min numeric, p_max numeric) FROM PUBLIC;


--
-- Name: FUNCTION f_perfil(p_email text); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_perfil(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_registro_coherente(); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_registro_coherente() FROM PUBLIC;


--
-- Name: FUNCTION f_solo_agregar(); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_solo_agregar() FROM PUBLIC;


--
-- Name: FUNCTION f_tecnica_activa(p_email text); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_tecnica_activa(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION f_validar_persona(p_persona text, p_exigir_tecnica boolean); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_validar_persona(p_persona text, p_exigir_tecnica boolean) FROM PUBLIC;


--
-- Name: FUNCTION f_verificar(p_solicitante text, p_modo text); Type: ACL; Schema: tecnica; Owner: -
--

REVOKE ALL ON FUNCTION tecnica.f_verificar(p_solicitante text, p_modo text) FROM PUBLIC;


--
-- Name: TABLE v_envios_pendientes; Type: ACL; Schema: salida; Owner: -
--

GRANT SELECT ON TABLE salida.v_envios_pendientes TO dell_envios;


--
-- Name: predios_comercial; Type: MATERIALIZED VIEW DATA; Schema: public; Owner: -
--

REFRESH MATERIALIZED VIEW public.predios_comercial;


--
-- PostgreSQL database dump complete
--

\unrestrict ruU3dixnJVuCkeY5Kh0WB1yIxl1o3AYgfNKyglSMfbR4mMUGDHqWlub72OG8l9x

