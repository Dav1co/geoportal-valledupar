-- =====================================================================================================================
-- 43_proyeccion_recaudo.sql · Proyeccion de recaudo 2026 (formato FO-GF-33) y cumplimiento diario
-- SOLO objetos NUEVOS en el esquema bi; no altera ninguno existente. Solo agregados (ruta, mes, dia); sin datos de contratos.
-- Orden: 1) meta certificada y vistas de proyeccion; 2) calendario, pesos, meta diaria y cumplimiento; 3) año completo.
-- Fuentes: bi.v_recaudo_ruta, bi.v_recaudo_diario_mes, bi.v_recaudo_ritmo_dim. Meta certificada: FO-GF-33 corregido (filas 43 y 53).
-- Origen: escrito y probado por David en el SQL Editor de Supabase el 2026-10-16 (originales de este archivo; reemplaza la version
--         reconstruida desde la base).
-- RLS: bi.calendario_festivos y bi.proy_meta_certificada tienen RLS activado. NO se validan con el rol de solo lectura claude_ro
--      (devuelve el calendario vacio y cambia el cumplimiento); se validan solo con el rol propietario, que es el que usa la RPC
--      SECURITY DEFINER public.geoportal_bi_consulta.
-- Las metas certificadas y los festivos se editan con el rol propietario (SQL Editor); no hay pantalla de edicion.
-- bi.v_proy_cumplimiento_dia (paso 1b) fue una vista de prueba y NO se versiona.
-- =====================================================================================================================

-- PASO 1 (objetos NUEVOS en el esquema bi; no altera nada existente)
-- Fuente: bi.v_recaudo_ruta (periodo, ruta_efectiva, recaudo). Solo agregados por ruta y mes.

-- 1A. Meta certificada (FO-GF-33 corregido, filas 43 = servicios y 53 = otros ingresos; sin terceros), en pesos.
create table if not exists bi.proy_meta_certificada (
  periodo        text primary key,            -- AAAAMM
  meta_servicios numeric not null,
  meta_otros     numeric not null,
  fuente         text    not null,
  cargado_en     timestamptz not null default now()
);
alter table bi.proy_meta_certificada enable row level security;
insert into bi.proy_meta_certificada (periodo, meta_servicios, meta_otros, fuente) values
 ('202609', 4950119156.06, 133838079.60, 'FO-GF-33 corregido (Nuevo2), columnas M, filas 43 y 53'),
 ('202610', 4927731207.54, 134217206.60, 'FO-GF-33 corregido (Nuevo2), columnas N, filas 43 y 53'),
 ('202611', 4985168781.28, 134596333.60, 'FO-GF-33 corregido (Nuevo2), columnas O, filas 43 y 53'),
 ('202612', 5001409063.88, 134975460.60, 'FO-GF-33 corregido (Nuevo2), columnas P, filas 43 y 53')
on conflict (periodo) do nothing;

-- 1B. Proyección propia por ruta: real del año en curso + proyectado hasta diciembre.
--     Anclada al último período cargado en bi.v_recaudo_ruta (se corre sola cada mes).
create or replace view bi.v_proy_recaudo as
with s as (
  select to_date(periodo::text || '01', 'YYYYMMDD') as f, ruta_efectiva as ruta, sum(recaudo)::numeric as v
  from bi.v_recaudo_ruta group by 1, 2
),
t as (select max(f) as t0 from s),
rutas as (
  select ruta,
         case when ruta = 'TERCERO' then 'tercero'
              when ruta like '%OTROS INGRESOS%' then 'otros'
              else 'servicio' end as grupo
  from (select distinct ruta from s) x
),
est as (
  select r.ruta, r.grupo,
         avg(s.v) filter (where s.f >= t.t0 - interval '2 months') as a3,
         sum(s.v) filter (where s.f >= t.t0 - interval '2 months') as s3,
         sum(s.v) filter (where s.f between t.t0 - interval '14 months' and t.t0 - interval '12 months') as s3ly,
         percentile_cont(0.5) within group (order by s.v) filter (where s.f > t.t0 - interval '6 months') as med6,
         avg(s.v) filter (where s.f > t.t0 - interval '6 months') as avg6
  from rutas r join s using (ruta) cross join t
  group by r.ruta, r.grupo
),
proy as (
  select e.ruta, e.grupo,
         (t.t0 + make_interval(months => g.h))::date as f,
         case e.grupo
           when 'servicio' then
             ( sy.v * (e.s3 / nullif(e.s3ly, 0))                                               -- B: mismo mes año anterior x razón anual
             + e.a3 * (1 + ((e.s3 / nullif(e.s3ly, 0)) ^ (1.0 / 12) - 1) * (g.h + 1)) ) / 2    -- D: promedio 3 m con tendencia
           when 'otros' then e.med6                                                             -- mediana de 6 meses
           else e.avg6 end as v                                                                 -- tercero: promedio de 6 meses
  from est e
  cross join t
  cross join lateral generate_series(1, 12 - extract(month from t.t0)::int) as g(h)
  left join s sy on sy.ruta = e.ruta and sy.f = (t.t0 + make_interval(months => g.h) - interval '12 months')::date
)
select to_char(s.f, 'YYYYMM') as periodo, 'real'::text as tipo, s.ruta, r.grupo, s.v as recaudo
from s join rutas r using (ruta) cross join t
where extract(year from s.f) = extract(year from t.t0)
union all
select to_char(f, 'YYYYMM'), 'proyectado', ruta, grupo, v from proy;

-- 1C. Totales mensuales y acumulado, con y sin terceros.
create or replace view bi.v_proy_recaudo_total as
with b as (
  select periodo, tipo,
         sum(recaudo) filter (where ruta <> 'TERCERO') as sin_terceros,
         sum(recaudo)                                   as con_terceros,
         sum(recaudo) filter (where grupo = 'servicio') as servicios,
         sum(recaudo) filter (where grupo = 'otros')    as otros
  from bi.v_proy_recaudo group by periodo, tipo
)
select periodo, tipo,
       round(servicios) as servicios, round(otros) as otros,
       round(sin_terceros) as sin_terceros, round(con_terceros) as con_terceros,
       round(sum(sin_terceros) over (order by periodo)) as acum_sin_terceros,
       round(sum(con_terceros) over (order by periodo)) as acum_con_terceros
from b;

-- PASO 1c (objetos NUEVOS en bi; dependen de los pasos 1 y 1b). No altera nada existente.
-- Meta diaria repartida con calendario: tipo de dia (lunes..domingo, festivo) x tramo del mes (1-9, 10-20, 21-fin),
-- con pesos aprendidos del histórico de meses cerrados (bi.v_recaudo_ritmo_dim).
-- Todo en base "sin terceros" (se descuenta la participacion de la ruta TERCERO), comparable con el FO-GF-33.

-- 1C.1 Calendario de festivos (editable). Colombia 2026.
create table if not exists bi.calendario_festivos (
  fecha  date primary key,
  nombre text not null
);
alter table bi.calendario_festivos enable row level security;
insert into bi.calendario_festivos (fecha, nombre) values
 ('2026-01-01','Año Nuevo'),('2026-01-12','Reyes Magos'),('2026-03-23','San José'),
 ('2026-04-02','Jueves Santo'),('2026-04-03','Viernes Santo'),('2026-05-01','Dia del Trabajo'),
 ('2026-05-18','Ascension'),('2026-06-08','Corpus Christi'),('2026-06-15','Sagrado Corazon'),
 ('2026-06-29','San Pedro y San Pablo'),('2026-07-20','Independencia'),('2026-08-07','Batalla de Boyaca'),
 ('2026-08-17','Asuncion'),('2026-10-12','Dia de la Raza'),('2026-11-02','Todos los Santos'),
 ('2026-11-16','Independencia de Cartagena'),('2026-12-08','Inmaculada Concepcion'),('2026-12-25','Navidad')
on conflict (fecha) do nothing;

-- 1C.2 Funciones auxiliares de clasificacion.
create or replace function bi.proy_tipo_dia(p date) returns text language sql stable as $$
  select case when exists (select 1 from bi.calendario_festivos where fecha = p) then 'festivo'
         else (array['lunes','martes','miercoles','jueves','viernes','sabado','domingo'])[extract(isodow from p)::int] end
$$;
create or replace function bi.proy_tramo(p date) returns text language sql immutable as $$
  select case when extract(day from p) < 10 then '01-09'
              when extract(day from p) <= 20 then '10-20'
              else '21-fin' end
$$;

-- 1C.3 Pesos por tipo de dia y tramo: promedio del % del recaudo del mes que aporta cada dia (meses cerrados).
create or replace view bi.v_proy_peso_dia as
with m as (select distinct periodo from bi.v_recaudo_ritmo_dim where mes_completo),
cal as (
  select m.periodo, g::date as f
  from m cross join lateral generate_series(
         to_date(m.periodo || '01', 'YYYYMMDD'),
         (to_date(m.periodo || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date,
         interval '1 day') g),
x as (
  select c.periodo, coalesce(r.recaudo_dia, 0)::numeric as v,
         bi.proy_tipo_dia(c.f) as tipo, bi.proy_tramo(c.f) as tramo
  from cal c
  left join bi.v_recaudo_ritmo_dim r on r.periodo = c.periodo and r.dia = extract(day from c.f)::int),
t as (select periodo, sum(v) as tot from x group by periodo)
select x.tipo, x.tramo, count(*) as dias, avg(100 * x.v / t.tot) as pct_mes_por_dia
from x join t using (periodo)
group by x.tipo, x.tramo;

-- 1C.4 Meta diaria: reparte la meta del mes entre sus dias segun el peso del calendario.
create or replace view bi.v_proy_meta_dia as
with metas as (
  select c.periodo,
         (c.meta_servicios + c.meta_otros)::numeric as meta_cert,
         p.sin_terceros::numeric                    as meta_propia
  from bi.proy_meta_certificada c
  left join bi.v_proy_recaudo_total p on p.periodo = c.periodo and p.tipo = 'proyectado'),
cal as (
  select m.periodo, g::date as fecha
  from metas m cross join lateral generate_series(
         to_date(m.periodo || '01', 'YYYYMMDD'),
         (to_date(m.periodo || '01', 'YYYYMMDD') + interval '1 month - 1 day')::date,
         interval '1 day') g),
w as (
  select c.periodo, c.fecha, extract(day from c.fecha)::int as dia,
         bi.proy_tipo_dia(c.fecha) as tipo_dia, bi.proy_tramo(c.fecha) as tramo,
         coalesce(p.pct_mes_por_dia, 0) as peso
  from cal c
  left join bi.v_proy_peso_dia p
         on p.tipo = bi.proy_tipo_dia(c.fecha) and p.tramo = bi.proy_tramo(c.fecha)),
n as (select w.*, w.peso / nullif(sum(w.peso) over (partition by w.periodo), 0) as frac from w)
select n.periodo, n.dia, n.fecha, n.tipo_dia, n.tramo, n.frac, m.meta_cert, m.meta_propia,
       m.meta_cert   * n.frac as meta_cert_dia,
       m.meta_propia * n.frac as meta_propia_dia,
       m.meta_cert   * sum(n.frac) over (partition by n.periodo order by n.dia) as meta_cert_acum,
       m.meta_propia * sum(n.frac) over (partition by n.periodo order by n.dia) as meta_propia_acum
from n join metas m using (periodo);

-- 1C.5 Cumplimiento, faltante y cierre corregido con el avance (base sin terceros).
--  * cierre_corregido = real al ultimo dia cargado + (meta propia restante) x (ritmo a la fecha = real / meta propia a la fecha).
--  * exigencia_dia = lo que falta de cada meta repartido entre los dias que quedan segun el peso del calendario.
create or replace view bi.v_proy_cumplimiento as
with terc as (
  select coalesce(sum(recaudo) filter (where ruta = 'TERCERO') / nullif(sum(recaudo), 0), 0)::numeric as w
  from bi.v_proy_recaudo where tipo = 'real'),
ult as (select periodo, max(dia) as ult_dia from bi.v_recaudo_diario_mes group by periodo),
b as (
  select m.*, u.ult_dia,
         case when m.dia <= u.ult_dia then coalesce(d.valor_dia, 0) * (1 - t.w) end as real_dia,
         case when m.dia <= u.ult_dia
              then sum(coalesce(d.valor_dia, 0)) over (partition by m.periodo order by m.dia) * (1 - t.w) end as real_acum
  from bi.v_proy_meta_dia m
  join ult u on u.periodo = m.periodo
  left join bi.v_recaudo_diario_mes d on d.periodo = m.periodo and d.dia = m.dia
  cross join terc t),
corte as (
  select periodo,
         max(real_acum)       filter (where dia = ult_dia) as ra,
         max(meta_cert_acum)  filter (where dia = ult_dia) as mca,
         max(meta_propia_acum) filter (where dia = ult_dia) as mpa,
         sum(frac)            filter (where dia > ult_dia) as fr_rest
  from b group by periodo)
select b.periodo, b.dia, b.fecha, b.tipo_dia, b.tramo, b.ult_dia,
       round(b.real_dia)          as real_dia,
       round(b.real_acum)         as real_acum,
       round(b.meta_cert_dia)     as meta_certificada_dia,
       round(b.meta_propia_dia)   as meta_propia_dia,
       round(b.meta_cert_acum)    as meta_certificada_acum,
       round(b.meta_propia_acum)  as meta_propia_acum,
       round(100 * b.real_acum / nullif(b.meta_cert_acum, 0), 1)   as cumplimiento_certificada_pct,
       round(100 * b.real_acum / nullif(b.meta_propia_acum, 0), 1) as cumplimiento_propia_pct,
       round(b.meta_cert   - c.ra) as falta_certificada_mes,
       round(b.meta_propia - c.ra) as falta_propia_mes,
       case when b.dia > b.ult_dia and c.fr_rest > 0
            then round(greatest(b.meta_cert   - c.ra, 0) * b.frac / c.fr_rest) end as exigencia_dia_certificada,
       case when b.dia > b.ult_dia and c.fr_rest > 0
            then round(greatest(b.meta_propia - c.ra, 0) * b.frac / c.fr_rest) end as exigencia_dia_propia,
       round(c.ra + (b.meta_propia - c.mpa) * c.ra / nullif(c.mpa, 0)) as cierre_corregido_con_avance
from b join corte c using (periodo);

-- 1D (objeto NUEVO en bi; depende de los pasos 1 y 1c): año completo con tres lecturas, base sin terceros.
--   propia            = real hasta el ultimo mes cerrado + proyeccion propia (v_proy_recaudo_total)
--   propia_corregida  = igual, pero el mes en curso se reemplaza por su cierre corregido con el avance
--   certificada       = real hasta el ultimo mes cerrado + meta certificada FO-GF-33 en los meses proyectados
-- Los subsidios NO entran en ninguna de estas cifras (se muestran aparte, solo informativos).
create or replace view bi.v_proy_anual as
with t as (
  select periodo, tipo, sin_terceros::numeric as st, con_terceros::numeric as ct
  from bi.v_proy_recaudo_total),
cc as (
  select periodo, max(cierre_corregido_con_avance)::numeric as cierre
  from bi.v_proy_cumplimiento group by periodo),
b as (
  select t.periodo, t.tipo, t.st as propia_st, t.ct as propia_ct,
         case when t.tipo = 'proyectado' then coalesce(cc.cierre, t.st) else t.st end as corregida_st,
         case when t.tipo = 'proyectado' then coalesce((m.meta_servicios + m.meta_otros)::numeric, t.st) else t.st end as certificada_st
  from t
  left join cc on cc.periodo = t.periodo
  left join bi.proy_meta_certificada m on m.periodo = t.periodo)
select periodo, tipo,
       round(propia_st)      as propia_sin_terceros,
       round(corregida_st)   as propia_corregida_sin_terceros,
       round(certificada_st) as certificada_sin_terceros,
       round(propia_ct)      as propia_con_terceros,
       round(sum(propia_st)      over (order by periodo)) as acum_propia,
       round(sum(corregida_st)   over (order by periodo)) as acum_propia_corregida,
       round(sum(certificada_st) over (order by periodo)) as acum_certificada
from b;
