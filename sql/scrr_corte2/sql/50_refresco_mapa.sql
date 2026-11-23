-- =====================================================================
-- SCRR · CORTE 2 · 50 — REFRESCO DEL MAPA COMERCIAL POR EL CARGADOR (David, 22-nov: lo hacía cargar_diario.py; el script se retira)
-- Después de cerrar (o de revertir) una carga de cartera, la Edge geoportal-scrr corre, con una conexión PROPIA a la base y como sentencia suelta:
--     refresh materialized view concurrently public.predios_comercial;
-- Por qué no lo hace una RPC: las RPC corren como service_role con statement_timeout de 30 s (un SET dentro de la función no lo amplía; probado en local) y el
-- refresco real tarda decenas de segundos. La conexión propia pone su tope (120 s) y un candado de sesión para que no corran dos refrescos a la vez.
-- CONCURRENTLY: el mapa se sigue leyendo durante el refresco (probado en local con 123.000 predios: lecturas de 13 ms como máximo).
-- Rol MÍNIMO scrr_refresco (PostgreSQL 17, privilegio MAINTAIN): solo puede refrescar esa vista; no puede leerla ni leer ninguna tabla (probado en local).
-- Nace SIN login: la clave la pone David en el editor (alter role scrr_refresco login password '…') y la cadena de conexión va en el secreto de la Edge
-- SCRR_REFRESCO_DB_URL. Ninguna clave queda en este archivo ni en el repositorio. Sin el secreto, la Edge responde «falta configurar» y la carga sigue aplicada.
-- =====================================================================
create role scrr_refresco nologin noinherit nosuperuser nocreatedb nocreaterole noreplication;
comment on role scrr_refresco is 'SCRR corte 2: solo refresca public.predios_comercial (MAINTAIN). Lo usa la Edge geoportal-scrr con el secreto SCRR_REFRESCO_DB_URL.';
do $$ begin execute format('grant connect on database %I to scrr_refresco', current_database()); end $$;
grant usage on schema public to scrr_refresco;
grant maintain on public.predios_comercial to scrr_refresco;

-- Antes del refresco: quién lo pide (Supervisor comercial o administrador) y sobre qué carga de cartera; queda en la auditoría
create function public.geoportal_scrr_refresco_iniciar(p_solicitante text, p_carga uuid, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.cargas;
begin
  select * into c from scrr.cargas where id = p_carga;
  if not found or c.tipo <> 'cartera' then perform scrr.f_err('La carga de cartera no existe', 'P0002'); end if;
  if scrr.f_estado_carga(p_carga) not in ('aplicada', 'anulada', 'reemplazada') then perform scrr.f_err('El mapa se actualiza al cerrar o revertir una carga de cartera', '55000'); end if;
  perform scrr.f_auditar(v_email, 'scrr_refresco_mapa_inicio', p_carga::text, jsonb_build_object('estado_carga', scrr.f_estado_carga(p_carga)), p_ip);
  return jsonb_build_object('ok', true);
end $$;

-- Después: el resultado (ok, ocupado, error o sin_configurar) y cuánto tardó
create function public.geoportal_scrr_refresco_cerrar(p_solicitante text, p_carga uuid, p_resultado text, p_ms integer, p_detalle text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante);
begin
  if p_resultado is null or p_resultado not in ('ok', 'ocupado', 'error', 'sin_configurar') then perform scrr.f_err('Resultado no válido'); end if;
  perform scrr.f_auditar(v_email, 'scrr_refresco_mapa', p_carga::text, jsonb_build_object('resultado', p_resultado, 'ms', p_ms, 'detalle', left(p_detalle, 300)), p_ip);
  return jsonb_build_object('ok', true);
end $$;
