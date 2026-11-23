-- =====================================================================
-- SCRR · CORTE 2 · 38 — SELECCIÓN: embudo, vista previa, corrida y lista descargable o imprimible
-- Universo: la foto de cartera VIGENTE más reciente (contratos con saldo pendiente), un ciclo a la vez. El motor no clasifica: el supervisor escoge la actividad
-- (Suspensión, Corte o Gestión de cobro) al generar (decisión 8 del 20-nov; decisión 4 del 22-nov).
-- Embudo (sección 4 del encargo del 20-nov; cada contrato sale en el PRIMER paso que lo excluye):
--   p0 comodín (99999999 o categoría «-1») · p1 no facturado (no figura en el último período de hechos.facturacion_sspd) o sin ruta · p2 control vigente ·
--   p3 reclamo (valor reclamo > 0 o reclamo manual) · p4 pago sin reflejar (lo pagado desde la fecha del archivo cubre el saldo; un abono menor solo MARCA) ·
--   p5 evento de suspensión de agua activo (regla de David: si Técnica quitó el agua allí, no se corta; se SACA de la lista) · p6 excluido manual ·
--   p7 saldo menor al monto mínimo. Después, los filtros del supervisor: rango (facturas VENCIDAS o monto), barrio y segmento (aproximado).
-- Paz y salvo (saldo pendiente en cero) no entra al universo; se cuenta aparte con las filas de salida del historial.
-- =====================================================================

-- Foto vigente más reciente (carga de cartera aplicada)
create function scrr.f_foto_vigente() returns scrr.cargas
language sql stable security definer set search_path = pg_catalog, scrr as $$
  select c.* from scrr.v_cargas_vigentes c where c.tipo = 'cartera' order by c.fecha_dato desc, c.version desc limit 1
$$;

-- Filtros normalizados (lo que no venga toma su valor por omisión; lo que venga mal es un error para la persona)
create function scrr.f_filtros(p jsonb) returns jsonb
language plpgsql stable set search_path = pg_catalog, scrr as $$
declare m text := coalesce(p->>'modo', 'meses'); s text := coalesce(p->>'segmento', 'todos'); d numeric; h numeric; mm numeric; b int;
begin
  if p is null or jsonb_typeof(p) <> 'object' then perform scrr.f_err('Filtros no válidos'); end if;
  if m not in ('meses','monto') then perform scrr.f_err('Modo de selección no válido'); end if;
  if s not in ('todos','pagaron_mes_pasado_no_este','cero_a_un_mes','menos_de_n') then perform scrr.f_err('Segmento no válido'); end if;
  d := coalesce(scrr.f_num(p->>'desde'), case m when 'meses' then 1 else 0 end);
  h := scrr.f_num(p->>'hasta');
  mm := coalesce(scrr.f_num(p->>'monto_minimo'), (scrr.f_param('monto_minimo_defecto') #>> '{}')::numeric);
  if d < 0 or (h is not null and h < d) or mm < 0 then perform scrr.f_err('El rango no es válido'); end if;
  b := case when nullif(p->>'barrio_id', '') is null then null else (p->>'barrio_id')::int end;
  return jsonb_build_object('modo', m, 'desde', d, 'hasta', h, 'monto_minimo', mm, 'barrio_id', b, 'segmento', s, 'n', coalesce(scrr.f_num(p->>'n'), 8));
end $$;

-- Clasificación de cada contrato del ciclo (función interna; no la ejecuta la API). Sin datos personales.
create function scrr.f_seleccion(p_ciclo smallint, p_filtros jsonb)
returns table (contrato bigint, paso text, saldo_pendiente numeric, facturas_vencidas smallint, barrio_id smallint, ruta text, codigo_reparto text, marca text)
language plpgsql stable security definer set search_path = pg_catalog, scrr, public as $$
declare f jsonb := scrr.f_filtros(p_filtros); v_foto scrr.cargas := scrr.f_foto_vigente(); v_fact text; v_susp date; v_mes date; v_mes_ant date; v_eventos boolean;
begin
  if v_foto.id is null then perform scrr.f_err('Todavía no hay una cartera aplicada', '55000'); end if;
  select max(periodo) into v_fact from hechos.facturacion_sspd;
  select k.fecha_suspension into v_susp from scrr.v_calendario_vigente k where k.periodo = to_char(v_foto.fecha_dato, 'YYYYMM') and k.ciclo = p_ciclo;
  v_mes := date_trunc('month', v_foto.fecha_dato)::date; v_mes_ant := (v_mes - interval '1 month')::date;
  v_eventos := exists (select 1 from redes.f_eventos_abiertos());
  return query
  with h as (select * from scrr.cartera_historial x where x.fecha_dato = v_foto.fecha_dato and x.version = v_foto.version and x.carga_id = v_foto.id and x.en_cartera and x.ciclo = p_ciclo),
       fact as (select distinct btrim(s.contrato) as c from hechos.facturacion_sspd s where s.periodo = v_fact),
       ctl as (select v.contrato, bool_or(v.grupo = 'control') as ctl, bool_or(v.grupo = 'reclamo') as rec, bool_or(v.grupo = 'excluido') as exc
                 from scrr.v_control_vigente v where v.contrato in (select h.contrato from h) group by v.contrato),
       pag as (select q.contrato, coalesce(sum(q.monto) filter (where q.fecha_pago >= v_foto.fecha_dato), 0) as desde_archivo,
                      bool_or(v_susp is not null and q.fecha_pago >= v_susp and q.fecha_pago < v_foto.fecha_dato) as desde_susp,
                      bool_or(q.fecha_pago >= v_mes_ant and q.fecha_pago < v_mes) as mes_pasado, bool_or(q.fecha_pago >= v_mes) as este_mes
                 from scrr.pagos_contrato q where q.fecha_pago >= least(v_mes_ant, coalesce(v_susp, v_mes_ant)) and q.contrato in (select h.contrato from h) group by q.contrato),
       b as (select h.*, (fa.c is not null) as facturado, coalesce(k.ctl, false) as ctl, coalesce(k.rec, false) as rec, coalesce(k.exc, false) as exc,
                    coalesce(g.desde_archivo, 0) as pagado, coalesce(g.desde_susp, false) as desde_susp,
                    coalesce(g.mes_pasado and not g.este_mes, false) as mp_no_este
               from h left join fact fa on fa.c = h.contrato::text left join ctl k on k.contrato = h.contrato left join pag g on g.contrato = h.contrato)
  select b.contrato,
         case when b.marca = 1 then 'p0_comodin'
              when not b.facturado or b.ruta is null or btrim(b.ruta) = '' then 'p1_no_facturado_o_sin_ruta'
              when b.ctl then 'p2_control_vigente'
              when b.valor_reclamo > 0 or b.rec then 'p3_reclamo'
              when b.pagado > 0 and b.pagado >= b.saldo_pendiente then 'p4_pago_sin_reflejar'
              when v_eventos and exists (select 1 from redes.f_eventos_del_contrato(b.contrato::text)) then 'p5_evento_suspension_agua'
              when b.exc then 'p6_excluido_manual'
              when b.saldo_pendiente < (f->>'monto_minimo')::numeric then 'p7_saldo_menor_al_minimo'
              when f->>'modo' = 'meses' and (b.facturas_vencidas < (f->>'desde')::numeric or (f->>'hasta' is not null and b.facturas_vencidas > (f->>'hasta')::numeric)) then 'f_fuera_del_rango'
              when f->>'modo' = 'monto' and (b.saldo_pendiente < (f->>'desde')::numeric or (f->>'hasta' is not null and b.saldo_pendiente > (f->>'hasta')::numeric)) then 'f_fuera_del_rango'
              when f->>'barrio_id' is not null and b.barrio_id is distinct from (f->>'barrio_id')::smallint then 'f_otro_barrio'
              when f->>'segmento' = 'pagaron_mes_pasado_no_este' and not b.mp_no_este then 'f_fuera_del_segmento'
              when f->>'segmento' = 'cero_a_un_mes' and b.facturas_vencidas > 1 then 'f_fuera_del_segmento'
              when f->>'segmento' = 'menos_de_n' and b.facturas_vencidas >= (f->>'n')::numeric then 'f_fuera_del_segmento'
              else 'candidato' end,
         b.saldo_pendiente, b.facturas_vencidas, b.barrio_id, b.ruta, b.codigo_reparto,
         case when b.pagado > 0 then 'abono' when b.desde_susp then 'abono_desde_suspension' end
    from b;
end $$;

-- Opciones de la pantalla: la foto vigente, los ciclos del período (con su ventana de suspensión) y, si se pide un ciclo, sus barrios con cuántos contratos con saldo
create function public.geoportal_scrr_seleccion_opciones(p_solicitante text, p_ciclo integer default null, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_foto scrr.cargas := scrr.f_foto_vigente(); v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  return jsonb_build_object('hoy', v_hoy, 'foto', v_foto.fecha_dato, 'facturacion_periodo', (select max(periodo) from hechos.facturacion_sspd),
    'ciclos', (select coalesce(jsonb_agg(jsonb_build_object('ciclo', k.ciclo, 'pago_oportuno', k.pago_oportuno, 'fecha_suspension', k.fecha_suspension,
                         'en_ventana', k.fecha_suspension <= v_hoy, 'con_saldo', (select count(*) from scrr.cartera_historial h where v_foto.id is not null and h.fecha_dato = v_foto.fecha_dato
                            and h.version = v_foto.version and h.carga_id = v_foto.id and h.en_cartera and h.ciclo = k.ciclo)) order by k.fecha_suspension, k.ciclo), '[]'::jsonb)
                 from scrr.v_calendario_vigente k where k.periodo = to_char(coalesce(v_foto.fecha_dato, v_hoy), 'YYYYMM')),
    'barrios', case when p_ciclo is null or v_foto.id is null then '[]'::jsonb else
                 (select coalesce(jsonb_agg(jsonb_build_object('id', x.barrio_id, 'nombre', coalesce(br.nombre_norm, 'SIN BARRIO'), 'contratos', x.n) order by br.nombre_norm nulls last), '[]'::jsonb)
                    from (select h.barrio_id, count(*) as n from scrr.cartera_historial h where h.fecha_dato = v_foto.fecha_dato and h.version = v_foto.version and h.carga_id = v_foto.id
                            and h.en_cartera and h.ciclo = p_ciclo group by h.barrio_id) x left join scrr.barrios br on br.id = x.barrio_id) end,
    'actividades', (select jsonb_agg(jsonb_build_object('id', id, 'codigo', codigo, 'nombre', nombre) order by orden) from scrr.tipos_actividad where seleccionable and activo));
end $$;

-- Vista previa: SOLO conteos (embudo, candidatos, saldo, marcas, segmentos). Se audita con los conteos (P8). Sin datos personales y sin la lista.
create function public.geoportal_scrr_seleccion_previa(p_solicitante text, p_ciclo integer, p_filtros jsonb, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_foto scrr.cargas := scrr.f_foto_vigente(); v_res jsonb; v_paz bigint;
begin
  if p_ciclo is null or p_ciclo not between 1 and 99 then perform scrr.f_err('Escoja un ciclo'); end if;
  select count(*) into v_paz from scrr.cartera_historial h where v_foto.id is not null and h.fecha_dato = v_foto.fecha_dato and h.version = v_foto.version and h.carga_id = v_foto.id
     and not h.en_cartera and h.ciclo = p_ciclo;
  with x as (select * from scrr.f_seleccion(p_ciclo::smallint, p_filtros))
  select jsonb_build_object('foto', v_foto.fecha_dato, 'ciclo', p_ciclo, 'filtros', scrr.f_filtros(p_filtros),
           'embudo', coalesce((select jsonb_object_agg(paso, jsonb_build_object('contratos', n, 'saldo', s)) from (select paso, count(*) as n, round(sum(saldo_pendiente)) as s from x group by paso) z), '{}'::jsonb)
                     || jsonb_build_object('p4_paz_y_salvo_hoy', jsonb_build_object('contratos', v_paz, 'saldo', 0)),
           'universo', (select count(*) from x), 'candidatos', count(*) filter (where paso = 'candidato'),
           'saldo_candidatos', coalesce(round(sum(saldo_pendiente) filter (where paso = 'candidato')), 0),
           'marcados_abono', count(*) filter (where paso = 'candidato' and marca = 'abono'),
           'marcados_abono_desde_suspension', count(*) filter (where paso = 'candidato' and marca = 'abono_desde_suspension'),
           'por_vencidas', coalesce((select jsonb_object_agg(t, n) from (select case when facturas_vencidas between 1 and 6 then '1-6' when facturas_vencidas between 7 and 25 then '7-25'
                                       when facturas_vencidas > 25 then '26+' else '0' end as t, count(*) as n from x where paso = 'candidato' group by 1) w), '{}'::jsonb),
           'segmentos_aproximados', true)
    into v_res
    from x;
  perform scrr.f_auditar(v_email, 'scrr_seleccion_previa', p_ciclo::text, jsonb_build_object('filtros', v_res->'filtros', 'candidatos', v_res->'candidatos', 'embudo', v_res->'embudo'), p_ip);
  return v_res;
end $$;

-- Generar la corrida: se guarda SOLO la lista (contratos en orden de ruta y reparto) con la actividad escogida. Auditada.
create function public.geoportal_scrr_seleccion_generar(p_solicitante text, p_ciclo integer, p_filtros jsonb, p_actividad text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); v_foto scrr.cargas := scrr.f_foto_vigente(); v_act scrr.tipos_actividad; v_id uuid := gen_random_uuid();
        v_n int; v_s numeric; v_emb jsonb; v_per text; v_lista jsonb; v_todo jsonb;
begin
  if p_ciclo is null or p_ciclo not between 1 and 99 then perform scrr.f_err('Escoja un ciclo'); end if;
  select * into v_act from scrr.tipos_actividad where codigo = p_actividad and seleccionable and activo;
  if not found then perform scrr.f_err('Escoja la actividad: Suspensión, Corte o Gestión de cobro'); end if;
  if v_foto.id is null then perform scrr.f_err('Todavía no hay una cartera aplicada', '55000'); end if;
  perform pg_advisory_xact_lock(hashtextextended('scrr_corrida', 0));
  -- una sola evaluación del embudo; las filas quedan en una variable (sin tablas temporales)
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_todo from scrr.f_seleccion(p_ciclo::smallint, p_filtros) x;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_lista from jsonb_array_elements(v_todo) e where e->>'paso' = 'candidato';
  select coalesce(jsonb_object_agg(z.paso, z.n), '{}'::jsonb) into v_emb from (select e->>'paso' as paso, count(*) as n from jsonb_array_elements(v_todo) e group by 1) z;
  v_n := jsonb_array_length(v_lista);
  v_s := coalesce((select sum((e->>'saldo_pendiente')::numeric) from jsonb_array_elements(v_lista) e), 0);
  if v_n = 0 then perform scrr.f_err('Con esos filtros no hay contratos para la lista', '55000'); end if;
  v_per := to_char(v_foto.fecha_dato, 'YYYYMM');
  insert into scrr.corridas (id, periodo, ciclo, fecha_dato, carga_id, actividad_id, filtros, embudo, contratos, saldo_total, autor)
    values (v_id, v_per, p_ciclo, v_foto.fecha_dato, v_foto.id, v_act.id, scrr.f_filtros(p_filtros), v_emb, v_n, v_s, v_email);
  insert into scrr.corrida_contratos (corrida_id, orden, contrato, saldo_pendiente, facturas_vencidas, barrio_id, ruta, codigo_reparto, marca)
    select v_id, row_number() over (order by t.ruta nulls last, t.codigo_reparto nulls last, t.contrato), t.contrato, t.saldo_pendiente, t.facturas_vencidas, t.barrio_id, t.ruta, t.codigo_reparto, t.marca
      from jsonb_to_recordset(v_lista) as t(contrato bigint, saldo_pendiente numeric, facturas_vencidas smallint, barrio_id smallint, ruta text, codigo_reparto text, marca text);
  perform scrr.f_auditar(v_email, 'scrr_corrida', v_id::text, jsonb_build_object('ciclo', p_ciclo, 'actividad', p_actividad, 'contratos', v_n, 'saldo', v_s, 'filtros', scrr.f_filtros(p_filtros), 'embudo', v_emb), p_ip);
  return jsonb_build_object('corrida_id', v_id, 'contratos', v_n, 'saldo_total', v_s, 'actividad', v_act.nombre);
end $$;

create function public.geoportal_scrr_corridas(p_solicitante text, p_limite integer default 30, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante);
begin
  return jsonb_build_object('corridas', (select coalesce(jsonb_agg(jsonb_build_object('corrida_id', c.id, 'tipo', c.tipo, 'ciclo', c.ciclo, 'fecha_dato', c.fecha_dato,
           'actividad', coalesce(t.nombre, 'Restablecer (reinstalación y reconexión)'), 'actividad_codigo', coalesce(t.codigo, 'retorno'),
           'contratos', c.contratos, 'saldo_total', c.saldo_total, 'filtros', c.filtros, 'autor', c.autor, 'creada_en', c.creado_en) order by c.creado_en desc), '[]'::jsonb)
      from (select * from scrr.corridas order by creado_en desc limit greatest(1, least(coalesce(p_limite, 30), 100))) c left join scrr.tipos_actividad t on t.id = c.actividad_id));
end $$;

-- Lista de una corrida para descargar (Excel) o imprimir. EXCEPCIÓN ESCRITA a la regla de descargas (P2 del 22-nov): solo para las listas de campo del SCRR,
-- llevan NOMBRE y DIRECCIÓN del suscriptor (nunca teléfono, correo ni identificación), resueltos de public.cartera_suscripcion al momento de pedirla (no se copian),
-- y cada descarga o impresión queda en la auditoría. Las dos versiones (operario y gestor de cobro) llevan la deuda (P9).
create function public.geoportal_scrr_lista(p_solicitante text, p_corrida uuid, p_formato text, p_ip text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, scrr as $$
declare v_email text := scrr.f_autorizar(p_solicitante); c scrr.corridas; v_act scrr.tipos_actividad; v_filas jsonb;
begin
  if p_formato is null or p_formato not in ('excel','impresion') then perform scrr.f_err('Formato no válido'); end if;
  select * into c from scrr.corridas where id = p_corrida;
  if not found then perform scrr.f_err('La corrida no existe', 'P0002'); end if;
  select * into v_act from scrr.tipos_actividad where id = c.actividad_id;
  select coalesce(jsonb_agg(jsonb_build_object('orden', k.orden, 'contrato', k.contrato::text, 'nombre', s.nombre, 'direccion', s.direccion, 'barrio', coalesce(s.barrio, br.nombre_norm),
                    'ciclo', coalesce(c.ciclo::text, s.ciclo), 'ruta', k.ruta, 'codigo_reparto', k.codigo_reparto, 'facturas_vencidas', k.facturas_vencidas, 'saldo_pendiente', k.saldo_pendiente,
                    'actividad', ta.nombre, 'origen', k.origen,
                    'marca', coalesce(k.aviso, case k.marca when 'abono' then 'Abonó desde la fecha del archivo' when 'abono_desde_suspension' then 'Abonó desde la fecha de suspensión' end))
                  order by k.orden), '[]'::jsonb)
    into v_filas
    from scrr.corrida_contratos k
    left join lateral (select x.nombre, x.direccion, x.barrio, x.ciclo from public.cartera_suscripcion x where x.contrato = k.contrato::text limit 1) s on true
    left join scrr.barrios br on br.id = k.barrio_id
    left join scrr.tipos_actividad ta on ta.id = coalesce(k.actividad_id, c.actividad_id)
   where k.corrida_id = p_corrida;
  perform scrr.f_auditar(v_email, 'scrr_lista_' || p_formato, p_corrida::text, jsonb_build_object('filas', jsonb_array_length(v_filas), 'ciclo', c.ciclo, 'actividad', coalesce(v_act.codigo, 'retorno')), p_ip);
  return jsonb_build_object('corrida_id', c.id, 'tipo', c.tipo, 'ciclo', c.ciclo, 'fecha_dato', c.fecha_dato, 'actividad', coalesce(v_act.nombre, 'Restablecer (reinstalación y reconexión)'),
                            'actividad_codigo', coalesce(v_act.codigo, 'retorno'),
                            'generada_en', c.creado_en, 'autor', c.autor, 'filas', v_filas);
end $$;
