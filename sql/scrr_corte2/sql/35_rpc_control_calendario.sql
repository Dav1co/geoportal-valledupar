-- =====================================================================
-- SCRR · CORTE 2 · 35 — RPC de contratos con control, excluidos manuales (P6) y calendario de ciclos
-- Alta y baja siempre con motivo; nada se borra (la baja es un evento). Carga por archivo con un motivo común (P10), sin perder el alta de uno en uno.
-- =====================================================================

create function scrr.f_contrato(p text) returns bigint
language plpgsql immutable set search_path = pg_catalog as $$
begin
  if btrim(coalesce(p, '')) !~ '^[0-9]{1,12}$' then perform scrr.f_err('El contrato debe ser un número de hasta 12 dígitos'); end if;
  return btrim(p)::bigint;
end $$;

-- Alta de uno (control o excluido manual, según la causa)
create function public.geoportal_scrr_control_agregar(p_solicitante text, p_contrato text, p_causa text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_causa scrr.causas_control; v_c bigint := scrr.f_contrato(p_contrato);
begin
  if v_c::text = scrr.f_param('comodin_contrato') #>> '{}' then perform scrr.f_err('Ese número es el comodín del sistema comercial, no un contrato'); end if;
  select * into v_causa from scrr.causas_control where codigo = p_causa and activo;
  if not found then perform scrr.f_err('Causa no válida'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 200 then perform scrr.f_err('Escriba un motivo de 10 a 200 caracteres (sin nombres, cédulas ni teléfonos)'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_control:' || v_c, 0));
  if exists (select 1 from scrr.v_control_vigente where contrato = v_c and causa_id = v_causa.id) then perform scrr.f_err('Ese contrato ya está en la lista por esa causa', '55000'); end if;
  insert into scrr.control_eventos (contrato, causa_id, tipo_evento, motivo, autor) values (v_c, v_causa.id, 'alta', btrim(p_motivo), v_email);
  perform scrr.f_auditar(v_email, 'scrr_control_alta', v_c::text, jsonb_build_object('causa', p_causa, 'grupo', v_causa.grupo), p_ip);
  return jsonb_build_object('ok', true);
end $$;

-- Alta por archivo (P10): hasta 5.000 contratos por llamada, un motivo común. Los que ya están por esa causa se cuentan, no se duplican.
create function public.geoportal_scrr_control_lote(p_solicitante text, p_contratos jsonb, p_causa text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_causa scrr.causas_control; v_n int; v_validos int; v_filas_validas int; v_nuevos int;
        v_com text := scrr.f_param('comodin_contrato') #>> '{}';
begin
  select * into v_causa from scrr.causas_control where codigo = p_causa and activo;
  if not found then perform scrr.f_err('Causa no válida'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 200 then perform scrr.f_err('Escriba un motivo común de 10 a 200 caracteres'); end if;
  if p_contratos is null or jsonb_typeof(p_contratos) <> 'array' then perform scrr.f_err('La lista de contratos no es válida'); end if;
  v_n := jsonb_array_length(p_contratos);
  if v_n < 1 or v_n > 5000 then perform scrr.f_err('Se cargan de 1 a 5.000 contratos por vez'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_control_lote', 0));
  select count(*) into v_filas_validas from jsonb_array_elements(p_contratos) x
   where btrim(x #>> '{}') ~ '^[0-9]{1,12}$' and btrim(x #>> '{}') <> v_com and btrim(x #>> '{}')::bigint > 0;
  with lista as (select distinct btrim(x #>> '{}')::bigint as contrato from jsonb_array_elements(p_contratos) x
                  where btrim(x #>> '{}') ~ '^[0-9]{1,12}$' and btrim(x #>> '{}') <> v_com and btrim(x #>> '{}')::bigint > 0),
       nuevos as (insert into scrr.control_eventos (contrato, causa_id, tipo_evento, motivo, origen, autor)
                    select l.contrato, v_causa.id, 'alta', btrim(p_motivo), 'archivo', v_email from lista l
                     where not exists (select 1 from scrr.v_control_vigente v where v.contrato = l.contrato and v.causa_id = v_causa.id)
                  returning 1)
  select (select count(*) from lista), (select count(*) from nuevos) into v_validos, v_nuevos;
  perform scrr.f_auditar(v_email, 'scrr_control_lote', p_causa, jsonb_build_object('recibidos', v_n, 'validos', v_validos, 'nuevos', v_nuevos), p_ip);
  return jsonb_build_object('recibidos', v_n, 'no_validos', v_n - v_filas_validas, 'repetidos_en_el_archivo', v_filas_validas - v_validos, 'nuevos', v_nuevos, 'ya_estaban', v_validos - v_nuevos);
end $$;

create function public.geoportal_scrr_control_baja(p_solicitante text, p_contrato text, p_causa text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_causa scrr.causas_control; v_c bigint := scrr.f_contrato(p_contrato);
begin
  select * into v_causa from scrr.causas_control where codigo = p_causa;
  if not found then perform scrr.f_err('Causa no válida'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 200 then perform scrr.f_err('Escriba un motivo de 10 a 200 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_control:' || v_c, 0));
  if not exists (select 1 from scrr.v_control_vigente where contrato = v_c and causa_id = v_causa.id) then perform scrr.f_err('Ese contrato no está en la lista por esa causa', '55000'); end if;
  insert into scrr.control_eventos (contrato, causa_id, tipo_evento, motivo, autor) values (v_c, v_causa.id, 'baja', btrim(p_motivo), v_email);
  perform scrr.f_auditar(v_email, 'scrr_control_baja', v_c::text, jsonb_build_object('causa', p_causa), p_ip);
  return jsonb_build_object('ok', true);
end $$;

-- Lista: p_grupo 'control' (control y reclamo manual) o 'excluido'. Sin contrato = vigentes paginados; con contrato = su historial completo (todas las causas).
create function public.geoportal_scrr_control_lista(p_solicitante text, p_grupo text default 'control', p_contrato text default null, p_despues bigint default null,
                                                    p_limite integer default 200, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_lim integer := greatest(1, least(coalesce(p_limite, 200), 500)); v_grupos text[];
begin
  v_grupos := case p_grupo when 'excluido' then array['excluido'] when 'control' then array['control','reclamo'] else null end;
  if v_grupos is null then perform scrr.f_err('Grupo no válido'); end if;
  if p_contrato is not null then
    return jsonb_build_object('historial', (select coalesce(jsonb_agg(jsonb_build_object('causa', k.nombre, 'evento', e.tipo_evento, 'motivo', e.motivo, 'origen', e.origen, 'autor', e.autor, 'fecha', e.creado_en) order by e.id desc), '[]'::jsonb)
                                              from scrr.control_eventos e join scrr.causas_control k on k.id = e.causa_id where e.contrato = scrr.f_contrato(p_contrato)));
  end if;
  return jsonb_build_object(
    'vigentes', (select coalesce(jsonb_agg(jsonb_build_object('contrato', q.contrato, 'causa', q.codigo, 'causa_nombre', q.nombre, 'desde', q.desde, 'autor', q.autor, 'origen', q.origen) order by q.contrato, q.codigo), '[]'::jsonb)
                   from (select v.contrato, k.codigo, k.nombre, v.desde, v.autor, v.origen from scrr.v_control_vigente v join scrr.causas_control k on k.id = v.causa_id
                          where v.grupo = any (v_grupos) and (p_despues is null or v.contrato > p_despues) order by v.contrato limit v_lim) q),
    'total', (select count(*) from scrr.v_control_vigente where grupo = any (v_grupos)),
    'bajas_recientes', (select coalesce(jsonb_agg(jsonb_build_object('contrato', b.contrato, 'causa_nombre', k.nombre, 'fecha', b.creado_en, 'motivo', b.motivo) order by b.id desc), '[]'::jsonb)
                          from (select * from scrr.control_eventos e where e.tipo_evento = 'baja' and e.causa_id in (select id from scrr.causas_control where grupo = any (v_grupos))
                                 order by e.id desc limit 20) b join scrr.causas_control k on k.id = b.causa_id));
end $$;

-- Calendario: los ciclos de un período (con su última versión) y guardar uno (nuevo, o cambio con motivo). Se pueden agregar ciclos (1 a 99).
create function public.geoportal_scrr_calendario_lista(p_solicitante text, p_periodo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  if coalesce(p_periodo, '') !~ '^20[0-9]{2}(0[1-9]|1[0-2])$' then perform scrr.f_err('El período debe ser aaaamm'); end if;
  return jsonb_build_object('periodo', p_periodo, 'hoy', v_hoy,
    'ciclos', (select coalesce(jsonb_agg(jsonb_build_object('ciclo', v.ciclo, 'pago_oportuno', v.pago_oportuno, 'fecha_suspension', v.fecha_suspension, 'etapas', v.etapas,
                        'en_ventana', v.fecha_suspension <= v_hoy, 'versiones', (select count(*) from scrr.calendario_ciclos c where c.periodo = v.periodo and c.ciclo = v.ciclo),
                        'ultimo_cambio', v.vigente_desde, 'motivo', v.motivo) order by v.pago_oportuno, v.ciclo), '[]'::jsonb)
                 from scrr.v_calendario_vigente v where v.periodo = p_periodo),
    'periodos', (select coalesce(jsonb_agg(distinct periodo order by periodo desc), '[]'::jsonb) from scrr.calendario_ciclos));
end $$;

create function public.geoportal_scrr_calendario_guardar(p_solicitante text, p_periodo text, p_ciclo integer, p_pago_oportuno date, p_fecha_suspension date,
                                                         p_etapas jsonb default '{}'::jsonb, p_motivo text default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_ant scrr.v_calendario_vigente; v_ini date;
begin
  if coalesce(p_periodo, '') !~ '^20[0-9]{2}(0[1-9]|1[0-2])$' then perform scrr.f_err('El período debe ser aaaamm'); end if;
  if p_ciclo is null or p_ciclo not between 1 and 99 then perform scrr.f_err('El ciclo va de 1 a 99'); end if;
  if p_pago_oportuno is null or p_fecha_suspension is null then perform scrr.f_err('Pago oportuno y fecha de suspensión son obligatorios'); end if;
  if p_fecha_suspension < p_pago_oportuno then perform scrr.f_err('La fecha de suspensión no puede ser anterior al pago oportuno'); end if;
  v_ini := to_date(p_periodo || '01', 'YYYYMMDD');
  if p_pago_oportuno < v_ini - 31 or p_pago_oportuno > (v_ini + interval '2 months')::date then perform scrr.f_err('El pago oportuno no corresponde a ese período'); end if;
  if p_etapas is null or jsonb_typeof(p_etapas) <> 'object' or length(p_etapas::text) > 4000 then perform scrr.f_err('Las etapas no son válidas'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_calendario:' || p_periodo || ':' || p_ciclo, 0));
  select * into v_ant from scrr.v_calendario_vigente where periodo = p_periodo and ciclo = p_ciclo;
  if found then
    if v_ant.pago_oportuno = p_pago_oportuno and v_ant.fecha_suspension = p_fecha_suspension and v_ant.etapas = p_etapas then
      perform scrr.f_err('No hay cambios', '55000'); end if;
    if length(btrim(coalesce(p_motivo, ''))) not between 5 and 300 then perform scrr.f_err('Cambiar un ciclo ya guardado exige un motivo de 5 a 300 caracteres'); end if;
  end if;
  insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, etapas, motivo, autor)
    values (p_periodo, p_ciclo, p_pago_oportuno, p_fecha_suspension, p_etapas, nullif(btrim(coalesce(p_motivo, '')), ''), v_email);
  perform scrr.f_auditar(v_email, 'scrr_calendario', p_periodo || '/' || p_ciclo,
    jsonb_build_object('pago_oportuno', p_pago_oportuno, 'fecha_suspension', p_fecha_suspension, 'nuevo', v_ant.ciclo is null), p_ip);
  return jsonb_build_object('ok', true, 'nuevo', v_ant.ciclo is null);
end $$;

-- «Copiar del mes anterior» (David, 22-nov 21:21): la pantalla propone las fechas del mes anterior corridas un mes, la persona las corrige y guarda todas de una vez.
-- Solo crea los ciclos que el período destino todavía no tiene (los que ya están no se tocan: cambiarlos exige motivo, uno por uno). Auditado una vez.
create function public.geoportal_scrr_calendario_guardar_lote(p_solicitante text, p_periodo text, p_ciclos jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_ini date; r record; v_nuevos int := 0; v_ya int := 0;
begin
  if coalesce(p_periodo, '') !~ '^20[0-9]{2}(0[1-9]|1[0-2])$' then perform scrr.f_err('El período debe ser aaaamm'); end if;
  if p_ciclos is null or jsonb_typeof(p_ciclos) <> 'array' or jsonb_array_length(p_ciclos) not between 1 and 99 then perform scrr.f_err('La lista de ciclos no es válida'); end if;
  v_ini := to_date(p_periodo || '01', 'YYYYMMDD');
  perform pg_advisory_xact_lock(hashtextextended('scrr_calendario_lote:' || p_periodo, 0));
  for r in select (e->>'ciclo')::int as ciclo, scrr.f_fecha(e->>'pago_oportuno') as po, scrr.f_fecha(e->>'fecha_suspension') as fs,
                  coalesce(e->'etapas', '{}'::jsonb) as etapas from jsonb_array_elements(p_ciclos) e loop
    if r.ciclo is null or r.ciclo not between 1 and 99 then perform scrr.f_err('Un ciclo no es válido (1 a 99)'); end if;
    if r.po is null or r.fs is null or r.fs < r.po then perform scrr.f_err(format('Ciclo %s: revise el pago oportuno y la fecha de suspensión', r.ciclo)); end if;
    if r.po < v_ini - 31 or r.po > (v_ini + interval '2 months')::date then perform scrr.f_err(format('Ciclo %s: el pago oportuno no corresponde a ese período', r.ciclo)); end if;
    if jsonb_typeof(r.etapas) <> 'object' then perform scrr.f_err('Las etapas no son válidas'); end if;
    if exists (select 1 from scrr.v_calendario_vigente k where k.periodo = p_periodo and k.ciclo = r.ciclo) then v_ya := v_ya + 1; continue; end if;
    insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, etapas, autor) values (p_periodo, r.ciclo, r.po, r.fs, r.etapas, v_email);
    v_nuevos := v_nuevos + 1;
  end loop;
  perform scrr.f_auditar(v_email, 'scrr_calendario_lote', p_periodo, jsonb_build_object('nuevos', v_nuevos, 'ya_estaban', v_ya), p_ip);
  return jsonb_build_object('nuevos', v_nuevos, 'ya_estaban', v_ya);
end $$;
