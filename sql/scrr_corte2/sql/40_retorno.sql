-- =====================================================================
-- SCRR · CORTE 2 · 40 — RETORNO AUTOMÁTICO (decisiones 8, 11 y 12 del 20-nov; sección 4.4 del encargo del 20-nov)
-- La única decisión del sistema: cuando un contrato que quedó SIN AGUA por una actividad efectiva (suspendido, cortado o cortado drástico, según
-- scrr.v_estado_servicio) queda con SALDO PENDIENTE EN CERO en la cartera del día, se propone la actividad subsanadora:
--   suspendido → reinstalación · cortado → reconexión · cortado drástico → reconexión drástica (con su aviso).
-- «Por confirmar»: sigue sin agua, la cartera aún muestra saldo y hay pagos desde la fecha de la cartera. No genera la actividad hasta que la cartera lo
--   confirme en cero (un pago no es paz y salvo: pudo pagar una sola factura; decisión 11).
-- Adición manual (decisión 12): el supervisor suma un contrato que sigue en deuda (p. ej. un reclamo que no está en el sistema), con motivo y auditado.
-- La lista distingue el origen (automático o manual). Generarla crea una corrida de tipo «retorno»; un contrato ya listado no vuelve a salir.
-- El saldo y los datos de ruta salen de public.cartera_suscripcion (la que actualiza la carga del día); un contrato que no está en ella no se propone.
-- =====================================================================
create table scrr.retorno_manual_eventos (
  id            bigint generated always as identity primary key,
  contrato      bigint      not null check (contrato > 0),
  tipo_evento   text        not null check (tipo_evento in ('alta', 'baja')),
  actividad_id  smallint    not null references scrr.tipos_actividad (id) check (actividad_id in (4, 5, 6)),
  motivo        text        not null check (length(btrim(motivo)) between 10 and 200),
  autor         text        not null check (autor = lower(autor) and position('@' in autor) > 1),
  creado_en     timestamptz not null default clock_timestamp()
);
create index retorno_manual_contrato_idx on scrr.retorno_manual_eventos (contrato, id desc);
alter table scrr.retorno_manual_eventos enable row level security;
create trigger retorno_manual_eventos_solo_insercion before update or delete on scrr.retorno_manual_eventos for each row execute function scrr.f_solo_insercion();

-- La lista viva del retorno (función interna; sin datos personales)
create function scrr.f_retorno()
returns table (contrato bigint, situacion text, origen text, actividad_id smallint, estado text, desde date, saldo numeric, pagado_desde_cartera numeric,
               ya_en_lista boolean, ciclo text, ruta text, codigo_reparto text, barrio text, aviso text, motivo text)
language plpgsql stable security definer set search_path = pg_catalog, scrr, public as $$
declare v_foto scrr.cargas := scrr.f_foto_vigente();
begin
  return query
  with est as (select e.contrato, e.estado, e.desde from scrr.v_estado_servicio e where e.estado in ('suspendido', 'cortado', 'cortado_drastico')),
       man as (select m.contrato, m.actividad_id, m.motivo, m.creado_en from (select distinct on (x.contrato) x.* from scrr.retorno_manual_eventos x order by x.contrato, x.id desc) m
                where m.tipo_evento = 'alta'),
       uni as (select est.contrato from est union select man.contrato from man),
       cs as (select s.contrato::bigint as contrato, max(s.saldo_pendiente) as saldo, min(s.ciclo) as ciclo, min(s.ruta) as ruta, min(s.codigo_reparto) as rep, min(s.barrio) as barrio
                from public.cartera_suscripcion s where s.contrato in (select uni.contrato::text from uni) group by s.contrato),
       pag as (select q.contrato, sum(q.monto) as monto from scrr.pagos_contrato q
                where v_foto.id is not null and q.fecha_pago >= v_foto.fecha_dato and q.contrato in (select uni.contrato from uni) group by q.contrato),
       todo as (
         -- automáticos (paz y salvo) y por confirmar
         select e.contrato, case when cs.saldo <= 0 then 'proponer' else 'por_confirmar' end as situacion, 'automatico'::text as origen,
                (case e.estado when 'suspendido' then 4 when 'cortado' then 5 else 6 end)::smallint as actividad_id, e.estado, e.desde, cs.saldo,
                coalesce(p.monto, 0) as pagado, e.desde::timestamptz as desde_ts, null::text as motivo, cs.ciclo, cs.ruta, cs.rep, cs.barrio
           from est e join cs on cs.contrato = e.contrato left join pag p on p.contrato = e.contrato
          where cs.saldo <= 0 or coalesce(p.monto, 0) > 0
         union all
         -- manuales (siguen en deuda o no figuran sin agua)
         select m.contrato, 'proponer', 'manual', m.actividad_id, coalesce(e.estado, 'sin_dato'), e.desde, cs.saldo, coalesce(p.monto, 0), m.creado_en, m.motivo,
                cs.ciclo, cs.ruta, cs.rep, cs.barrio
           from man m left join est e on e.contrato = m.contrato left join cs on cs.contrato = m.contrato left join pag p on p.contrato = m.contrato),
       uno as (select distinct on (t.contrato) t.* from todo t order by t.contrato, (t.situacion = 'proponer') desc, (t.origen = 'automatico') desc)
  select u.contrato, u.situacion, u.origen, u.actividad_id, u.estado, u.desde, u.saldo, u.pagado,
         exists (select 1 from scrr.corrida_contratos k join scrr.corridas r on r.id = k.corrida_id
                  where r.tipo = 'retorno' and k.contrato = u.contrato and r.creado_en >= coalesce(u.desde_ts, '-infinity'::timestamptz)),
         u.ciclo, u.ruta, u.rep, u.barrio,
         case when u.actividad_id = 6 then 'Reconexión DRÁSTICA: el corte fue drástico; revise la acometida antes de reconectar' end,
         u.motivo
    from uno u;
end $$;

create function public.geoportal_scrr_retorno(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_foto scrr.cargas := scrr.f_foto_vigente();
begin
  return (with r as (select x.*, t.nombre as actividad from scrr.f_retorno() x join scrr.tipos_actividad t on t.id = x.actividad_id)
    select jsonb_build_object('foto', v_foto.fecha_dato,
      'proponer', coalesce((select jsonb_agg(jsonb_build_object('contrato', r.contrato::text, 'actividad', r.actividad, 'actividad_id', r.actividad_id, 'origen', r.origen,
                     'estado', r.estado, 'desde', r.desde, 'saldo', r.saldo, 'ciclo', r.ciclo, 'ruta', r.ruta, 'aviso', r.aviso, 'motivo', r.motivo, 'ya_en_lista', r.ya_en_lista)
                     order by r.ya_en_lista, r.actividad_id, r.ruta nulls last, r.contrato) from r where r.situacion = 'proponer'), '[]'::jsonb),
      'por_confirmar', coalesce((select jsonb_agg(jsonb_build_object('contrato', r.contrato::text, 'actividad', r.actividad, 'estado', r.estado, 'desde', r.desde, 'saldo', r.saldo,
                     'pagado_desde_cartera', r.pagado_desde_cartera) order by r.contrato) from r where r.situacion = 'por_confirmar'), '[]'::jsonb),
      'pendientes', (select count(*) from r where r.situacion = 'proponer' and not r.ya_en_lista)));
end $$;

create function public.geoportal_scrr_retorno_agregar(p_solicitante text, p_contrato text, p_actividad text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_c bigint := scrr.f_contrato(p_contrato); v_act scrr.tipos_actividad;
begin
  select * into v_act from scrr.tipos_actividad where codigo = p_actividad and id in (4, 5, 6);
  if not found then perform scrr.f_err('Escoja reinstalación, reconexión o reconexión drástica'); end if;
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 200 then perform scrr.f_err('Escriba un motivo de 10 a 200 caracteres (sin nombres, cédulas ni teléfonos)'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_retorno:' || v_c, 0));
  if exists (select 1 from (select distinct on (contrato) * from scrr.retorno_manual_eventos where contrato = v_c order by contrato, id desc) m where m.tipo_evento = 'alta') then
    perform scrr.f_err('Ese contrato ya está agregado a mano en el retorno', '55000'); end if;
  insert into scrr.retorno_manual_eventos (contrato, tipo_evento, actividad_id, motivo, autor) values (v_c, 'alta', v_act.id, btrim(p_motivo), v_email);
  perform scrr.f_auditar(v_email, 'scrr_retorno_agregar', v_c::text, jsonb_build_object('actividad', p_actividad), p_ip);
  return jsonb_build_object('ok', true);
end $$;

create function public.geoportal_scrr_retorno_quitar(p_solicitante text, p_contrato text, p_motivo text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_c bigint := scrr.f_contrato(p_contrato); v_m scrr.retorno_manual_eventos;
begin
  if length(btrim(coalesce(p_motivo, ''))) not between 10 and 200 then perform scrr.f_err('Escriba un motivo de 10 a 200 caracteres'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_retorno:' || v_c, 0));
  select * into v_m from scrr.retorno_manual_eventos where contrato = v_c order by id desc limit 1;
  if not found or v_m.tipo_evento <> 'alta' then perform scrr.f_err('Ese contrato no está agregado a mano en el retorno', '55000'); end if;
  insert into scrr.retorno_manual_eventos (contrato, tipo_evento, actividad_id, motivo, autor) values (v_c, 'baja', v_m.actividad_id, btrim(p_motivo), v_email);
  perform scrr.f_auditar(v_email, 'scrr_retorno_quitar', v_c::text, '{}'::jsonb, p_ip);
  return jsonb_build_object('ok', true);
end $$;

-- Generar la lista de retorno: todos los «proponer» que todavía no están en una lista de retorno, con su actividad, su origen y su aviso. Auditada.
create function public.geoportal_scrr_retorno_generar(p_solicitante text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_foto scrr.cargas := scrr.f_foto_vigente(); v_id uuid := gen_random_uuid(); v_lista jsonb; v_n int;
begin
  if v_foto.id is null then perform scrr.f_err('Todavía no hay una cartera aplicada', '55000'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_corrida', 0));
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_lista from scrr.f_retorno() x where x.situacion = 'proponer' and not x.ya_en_lista;
  v_n := jsonb_array_length(v_lista);
  if v_n = 0 then perform scrr.f_err('No hay contratos pendientes de reinstalar o reconectar', '55000'); end if;
  insert into scrr.corridas (id, tipo, periodo, fecha_dato, carga_id, filtros, embudo, contratos, saldo_total, autor)
    values (v_id, 'retorno', to_char(v_foto.fecha_dato, 'YYYYMM'), v_foto.fecha_dato, v_foto.id, '{}'::jsonb,
            (select jsonb_object_agg(z.o, z.n) from (select e->>'origen' as o, count(*) as n from jsonb_array_elements(v_lista) e group by 1) z), v_n,
            coalesce((select sum(greatest((e->>'saldo')::numeric, 0)) from jsonb_array_elements(v_lista) e), 0), v_email);
  insert into scrr.corrida_contratos (corrida_id, orden, contrato, saldo_pendiente, facturas_vencidas, ruta, codigo_reparto, actividad_id, origen, aviso)
    select v_id, row_number() over (order by t.actividad_id, t.ruta nulls last, t.codigo_reparto nulls last, t.contrato), t.contrato, greatest(coalesce(t.saldo, 0), 0), 0,
           t.ruta, t.codigo_reparto, t.actividad_id, t.origen, t.aviso
      from jsonb_to_recordset(v_lista) as t(contrato bigint, saldo numeric, ruta text, codigo_reparto text, actividad_id smallint, origen text, aviso text);
  perform scrr.f_auditar(v_email, 'scrr_corrida', v_id::text, jsonb_build_object('tipo', 'retorno', 'contratos', v_n), p_ip);
  return jsonb_build_object('corrida_id', v_id, 'contratos', v_n);
end $$;
