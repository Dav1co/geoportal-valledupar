#!/usr/bin/env python3
"""Corte 9b · Fase 3 — genera el paquete de carga por psql del «Flujo del agua (modelo)» a partir de los CSV de la Fase 0
(sql/redes_corte9b/datos_flujo/flujo_modelo_v1.csv y horas_modelo_v1.csv). No toca ninguna base: solo escribe generado/.
  generado/carga_flujo_modelo.sql          la carga (una transacción; comprobaciones «N de N»; no duplica)
  generado/ensayo_carga_flujo_modelo.sql   lo mismo, pero termina en ERROR a propósito y no deja nada
  generado/verificacion_carga_flujo_modelo.sql   solo lectura (una consulta; editor SQL)
Uso: python3 -I carga_flujo.py"""
import csv
import hashlib
import os

AQUI = os.path.dirname(os.path.abspath(__file__))
DATOS = os.path.join(AQUI, '..', '..', 'redes_corte9b', 'datos_flujo')
GEN = os.path.join(AQUI, 'generado')
CSV_FLUJO, CSV_HORAS = os.path.join(DATOS, 'flujo_modelo_v1.csv'), os.path.join(DATOS, 'horas_modelo_v1.csv')
MD5 = hashlib.md5(open(CSV_FLUJO, 'rb').read()).hexdigest()
MD5_ESPERADO = '2b0b8616697e22427f7019f766de1448'      # el de la Fase 0 (ENTRADA_BITACORA.md)
assert MD5 == MD5_ESPERADO, MD5
filas = list(csv.DictReader(open(CSV_FLUJO, encoding='utf-8')))
horas = [h for h in csv.DictReader(open(CSV_HORAS, encoding='utf-8')) if h['confiable'] == 'si']
h_mayor = max(horas, key=lambda h: float(h['consumo_total_lps']))
h_menor = min(horas, key=lambda h: float(h['consumo_total_lps']))
assert (h_mayor['hora'], h_menor['hora']) == ('17', '23'), (h_mayor, h_menor)      # las columnas del CSV son _h17 y _h23
N = len(filas)
N_AM = sum(1 for f in filas if f['activo_codigo'])
N_LLAVE = sum(1 for f in filas if f['amarre'] == 'llave')
N_GEOM = sum(1 for f in filas if f['amarre'] == 'geometria')
N_REVES = sum(1 for f in filas if f['geom_mismo_sentido'] == 'no')
SF_MAYOR = sum(1 for f in filas if f['sentido_h17'] == 'sin_flujo')
SF_MENOR = sum(1 for f in filas if f['sentido_h23'] == 'sin_flujo')
CAMBIAN = sum(1 for f in filas if f['activo_codigo'] and {f['sentido_h17'], f['sentido_h23']} == {'ini_fin', 'fin_ini'})
ARCHIVO = 'flujo_modelo_v1.csv'
ORIGEN = 'modeloV1 del Plan Maestro 2014, corrido en EPANET (wntr): flujo por tubo. Modelo, no medido'
NOTA = (f'{N} tubos del modelo; {N_AM} amarran con un tramo de la red ({N_LLAVE} por la llave y {N_GEOM} por geometría a 2 m) y {N - N_AM} no. '
        f'Hora de mayor consumo {h_mayor["hora"]}:00 ({float(h_mayor["consumo_total_lps"]):.0f} L/s) y de menor {h_menor["hora"]}:00 ({float(h_menor["consumo_total_lps"]):.0f} L/s), '
        'entre las horas en que el modelo es confiable')


def lit(s):
    return 'null' if s in (None, '') else "'" + s.replace("'", "''") + "'"


def escribir(nombre, texto):
    ruta = os.path.join(GEN, nombre)
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    open(ruta, 'w', encoding='utf-8').write(texto)


# ---------- partes/10_flujo.sql ----------
vals = ',\n'.join(
    f"({lit(f['llave'])}, {lit(f['activo_codigo'])}, {lit(f['amarre'])}, {'null' if not f['geom_mismo_sentido'] else ('true' if f['geom_mismo_sentido'] == 'si' else 'false')}, "
    f"{f['q_lps_h17']}, {f['v_mps_h17']}, {lit(f['sentido_h17'])}, {f['q_lps_h23']}, {f['v_mps_h23']}, {lit(f['sentido_h23'])})" for f in filas)
escribir('partes/10_flujo.sql', f"""-- Corte 9b · Fase 3 · carga del flujo del modelo · 1. los {N} tubos. Generado por carga_flujo.py.
insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor)
values ('flujo_modelo', {lit(ARCHIVO)}, '{MD5}', {N}, {lit(ORIGEN)}, {lit(NOTA)}, lower(:'solicitante')) returning id as fl \\gset
insert into redes.flujo_modelo_horas (carga_id, cual, hora, consumo_lps) values (:fl, 'mayor', {h_mayor['hora']}, {h_mayor['consumo_total_lps']}), (:fl, 'menor', {h_menor['hora']}, {h_menor['consumo_total_lps']});
create temp table _fl (llave text, codigo text, amarre text, geom_mismo boolean, q1 numeric, v1 numeric, s1 text, q2 numeric, v2 numeric, s2 text) on commit drop;
insert into _fl values
{vals};
-- cada tubo con el tramo de la red de su código (un código que no sea un tramo de acueducto de esta base queda sin amarrar, y se cuenta)
insert into redes.flujo_modelo (carga_id, llave, activo_id, amarre, geom_mismo, q_mayor_lps, v_mayor_mps, sentido_mayor, q_menor_lps, v_menor_mps, sentido_menor)
select :fl, x.llave, a.id, case when a.id is not null then x.amarre end, case when a.id is not null then x.geom_mismo end, x.q1, x.v1, x.s1, x.q2, x.v2, x.s2
  from _fl x left join redes.activos a on a.codigo = x.codigo and a.prefijo in ('RED', 'CON');
select set_config('redes.flujo_sin_activo', (select count(*) from _fl x where x.codigo is not null and not exists (select 1 from redes.activos a where a.codigo = x.codigo and a.prefijo in ('RED', 'CON')))::text, true) as sin_activo \\gset
analyze redes.flujo_modelo;
""")

# ---------- partes/30_comprobar.sql ----------
escribir('partes/30_comprobar.sql', f"""-- Corte 9b · Fase 3 · carga del flujo del modelo · 2. comprobaciones «N de N». Generado por carga_flujo.py. Si alguna falla, ERROR: la transacción no queda.
select set_config('redes.flujo_solicitante', lower(:'solicitante'), true) as quien \\gset
do $$
declare v_q text := current_setting('redes.flujo_solicitante'); v_c bigint := redes.f_ref_vigente('flujo_modelo'); v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_ms4 numeric;
        v_j jsonb; v_f jsonb; v_cod text; v_z integer := floor(redes.f_param('geovisor_zoom_red_completa'))::integer; v_x integer; v_y integer; v_m1 text; v_m2 text;
        v_total integer; v_bien integer; v_fallas text; v_info text;
begin
  create temp table _fl_r (n integer, nombre text, ok boolean, detalle text) on commit drop;
  -- la tesela con más red, al zoom desde el que se ve toda, en las dos horas; la información de la capa y la tarjeta de un tramo
  select t.x, t.y into v_x, v_y from (
    select floor((ST_X(ST_PointOnSurface(m.geom)) + 180) / 360 * (1 << v_z))::integer as x,
           floor((1 - ln(tan(radians(ST_Y(ST_PointOnSurface(m.geom)))) + 1 / cos(radians(ST_Y(ST_PointOnSurface(m.geom))))) / pi()) / 2 * (1 << v_z))::integer as y
      from redes.activo_vigente_mat m join redes.flujo_modelo f on f.carga_id = v_c and f.activo_id = m.activo_id where not m.retirado) t group by t.x, t.y order by count(*) desc limit 1;
  v_t0 := clock_timestamp(); v_m1 := public.geoportal_redes_geovisor_mvt_flujo(v_q, 'mayor', v_z, v_x, v_y); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_m2 := public.geoportal_redes_geovisor_mvt_flujo(v_q, 'menor', v_z, v_x, v_y); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_t0 := clock_timestamp(); v_j := public.geoportal_redes_flujo_modelo(v_q); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  select a.codigo into v_cod from redes.flujo_modelo f join redes.activos a on a.id = f.activo_id where f.carga_id = v_c and f.sentido_mayor <> 'sin_flujo' order by abs(f.q_mayor_lps) desc, f.llave limit 1;
  v_t0 := clock_timestamp(); v_f := public.geoportal_redes_flujo_tramo(v_q, v_cod); v_ms4 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  v_info := format('TIEMPOS: tesela más cargada %s/%s/%s hora mayor %s ms (%s kB) · hora menor %s ms (%s kB) · información de la capa %s ms · tarjeta de %s %s ms',
                   v_z, v_x, v_y, v_ms1, round(length(v_m1) * 0.75 / 1024), v_ms2, round(length(v_m2) * 0.75 / 1024), v_ms3, v_cod, v_ms4);
  insert into _fl_r values
  (1, '01 el flujo vigente es el de este paquete ({ARCHIVO}, md5 {MD5[:8]}…): {N} tubos',
      (select md5 from redes.v_ref_carga_vigente where conjunto = 'flujo_modelo') = '{MD5}' and (select count(*) from redes.flujo_modelo where carga_id = v_c) = {N},
      (select count(*)::text from redes.flujo_modelo where carga_id = v_c)),
  (2, '02 los {N_AM} tubos que amarran son tramos de acueducto de esta base (por su código): ninguno quedó sin su tramo',
      current_setting('redes.flujo_sin_activo')::integer = 0 and (select count(activo_id) from redes.flujo_modelo where carga_id = v_c) = {N_AM},
      current_setting('redes.flujo_sin_activo') || ' código(s) del análisis sin tramo; amarrados ' || (select count(activo_id) from redes.flujo_modelo where carga_id = v_c)),
  (3, '03 {N_LLAVE} amarran por la llave y {N_GEOM} por geometría; {N - N_AM} tubos del modelo quedan sin tramo (no se dibujan); {N_REVES} con la geometría al revés del tubo',
      (select count(*) filter (where amarre = 'llave') = {N_LLAVE} and count(*) filter (where amarre = 'geometria') = {N_GEOM} and count(*) filter (where activo_id is null) = {N - N_AM}
              and count(*) filter (where geom_mismo is false) = {N_REVES} from redes.flujo_modelo where carga_id = v_c), null),
  (4, '04 las horas: mayor consumo a las {h_mayor['hora']}:00 y menor a las {h_menor['hora']}:00',
      (select string_agg(cual || '=' || hora, ',' order by cual) from redes.flujo_modelo_horas where carga_id = v_c) = 'mayor={h_mayor['hora']},menor={h_menor['hora']}', null),
  (5, '05 sin flujo: {SF_MAYOR} tubos en la hora mayor y {SF_MENOR} en la menor; {CAMBIAN} tramos cambian de sentido entre las dos horas',
      (select count(*) filter (where sentido_mayor = 'sin_flujo') = {SF_MAYOR} and count(*) filter (where sentido_menor = 'sin_flujo') = {SF_MENOR}
              and count(*) filter (where activo_id is not null and sentido_mayor <> sentido_menor and 'sin_flujo' not in (sentido_mayor, sentido_menor)) = {CAMBIAN}
         from redes.flujo_modelo where carga_id = v_c), null),
  (6, '06 ningún tramo de la red con dos tubos; los tramos amarrados que hoy están retirados u ocultos no se dibujan (informativo)',
      not exists (select 1 from redes.flujo_modelo where carga_id = v_c and activo_id is not null group by activo_id having count(*) > 1),
      (select count(*) || ' amarrados a tramos retirados u ocultos' from redes.flujo_modelo f join redes.activo_vigente_mat m on m.activo_id = f.activo_id where f.carga_id = v_c and (m.retirado or m.oculto))),
  (7, '07 la información de la capa: cargada, con el rótulo «Modelo, no medido (modeloV1, Plan Maestro 2014)» y la cobertura',
      (v_j ->> 'cargado')::boolean and v_j ->> 'rotulo' = 'Modelo, no medido (modeloV1, Plan Maestro 2014)' and (v_j -> 'cobertura' ->> 'con_tramo')::integer = {N_AM},
      v_j ->> 'cobertura'),
  (8, '08 la tarjeta del tramo de más caudal trae las dos horas', (v_f ->> 'en_modelo')::boolean and jsonb_array_length(v_f -> 'horas') = 2, v_f::text),
  (9, '09 TIEMPOS: las teselas de las dos horas, la información y la tarjeta, cada una en menos de 1 s',
      length(v_m1) > 0 and greatest(v_ms1, v_ms2, v_ms3, v_ms4) < 1000, v_info),
  (10, '10 no cambió la ficha de ningún activo (ni versiones ni eventos nuevos por esta carga)',
      not exists (select 1 from redes.activo_versiones v where v.creado_en >= (select creado_en from redes.ref_cargas where id = v_c)), null);
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\\n' order by n) filter (where not ok), '') into v_total, v_bien, v_fallas from _fl_r;
  if current_setting('redes.flujo_ensayo', true) = 'si' then
    raise exception E'CARGA DEL FLUJO DEL MODELO · CORTE 9b, Fase 3 (ENSAYO: este ERROR es el esperado y deshace todo)\\n%\\n%\\nRESULTADO: % de % comprobaciones correctas — %', v_fallas, v_info, v_bien, v_total,
      case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
  elsif v_bien <> v_total then
    raise exception E'CARGA DEL FLUJO DEL MODELO: % FALLA(S); no se carga nada\\n%', v_total - v_bien, v_fallas;
  end if;
  raise warning E'CARGA DEL FLUJO DEL MODELO · CORTE 9b, Fase 3\\n%\\nRESULTADO: % de % comprobaciones correctas — SIN FALLAS', v_info, v_bien, v_total;
end $$;
""")


def cabeza(ensayo):
    nombre = 'ensayo_carga_flujo_modelo.sql' if ensayo else 'carga_flujo_modelo.sql'
    intro = (f"""-- TÉCNICA · FASE 1 · CORTE 9b, Fase 3 — ENSAYO DE LA CARGA DEL FLUJO DEL AGUA (MODELO) (no deja nada). Generado por carga_flujo/carga_flujo.py.
-- Corre toda la carga en UNA transacción que termina en ERROR a propósito y deshace todo:
--   psql "$CADENA_EMDUPAR" -v solicitante=CORREO_DEL_ADMINISTRADOR -f {nombre}
-- Resultado esperado al final:  ERROR: CARGA DEL FLUJO DEL MODELO … (ENSAYO…) … RESULTADO: N de N comprobaciones correctas — SIN FALLAS
-- Copie la línea TIEMPOS: son los tiempos medidos en la base donde corre (la comprobación 09 falla si alguno pasa de 1 s).""" if ensayo else
             f"""-- TÉCNICA · FASE 1 · CORTE 9b, Fase 3 — CARGA DEL FLUJO DEL AGUA (MODELO): caudal, velocidad y sentido por tubo. Generado por carga_flujo/carga_flujo.py.
-- DESPUÉS de la migración de la Fase 3 y de su verificación. Un solo comando, desde esta carpeta (la cadena de conexión la pone usted en su terminal):
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f {nombre}
-- Todo va en UNA transacción: si una comprobación falla, no queda nada. No cambia la ficha de ningún activo. Repetirlo no duplica (la guardia se niega).
-- Al final muestra «N de N comprobaciones correctas — SIN FALLAS» con los TIEMPOS.""")
    return f"""-- =====================================================================
{intro}
-- Archivo de la Fase 0 con que se generó (md5):  {MD5}  {ARCHIVO}
-- Es un flujo de MODELO (modeloV1, Plan Maestro 2014), no medido.
-- =====================================================================
\\set ON_ERROR_STOP 1
\\if :{{?solicitante}}
\\else
  \\echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f {nombre}'
  \\quit
\\endif
\\pset pager off
\\timing on
begin;
set local statement_timeout = 0;
do $$
begin
  if to_regclass('redes.flujo_modelo') is null or to_regprocedure('public.geoportal_redes_flujo_modelo(text)') is null then raise exception 'Falta la migración de la Fase 3 del Corte 9b: deténgase y avise'; end if;
end $$;
select public.geoportal_es_admin(lower(:'solicitante')) as es_admin \\gset
\\if :es_admin
\\else
  \\echo 'Ese correo no es de un administrador del geoportal: no se carga nada.'
  rollback;
  \\quit
\\endif
select exists (select 1 from redes.v_ref_carga_vigente where conjunto = 'flujo_modelo' and md5 = '{MD5}') as ya_cargada \\gset
\\if :ya_cargada
  \\echo 'Este flujo del modelo ya está cargado y vigente (mismo archivo): no se carga de nuevo.'
  rollback;
  \\quit
\\endif
""" + ("select set_config('redes.flujo_ensayo', 'si', true) as ensayo \\gset\n" if ensayo else '') + """\\ir partes/10_flujo.sql
\\ir partes/30_comprobar.sql
""" + ('rollback;\n' if ensayo else "commit;\n\\echo 'Flujo del modelo cargado. Corra ahora verificacion_carga_flujo_modelo.sql.'\n")


escribir('carga_flujo_modelo.sql', cabeza(False))
escribir('ensayo_carga_flujo_modelo.sql', cabeza(True))
escribir('verificacion_carga_flujo_modelo.sql', f"""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b, Fase 3 — VERIFICACIÓN DE LA CARGA DEL FLUJO DEL MODELO (solo lectura, una consulta; apta para el editor SQL web).
-- Generado por carga_flujo/carga_flujo.py. Todas las filas deben decir OK (las INFO son informativas).
-- =====================================================================
select k, v from (
  select 1 as o, '01 el flujo vigente es el de este paquete ({ARCHIVO})' as k,
         case when (select md5 from redes.v_ref_carga_vigente where conjunto = 'flujo_modelo') = '{MD5}' then 'OK' else 'MAL' end as v
  union all select 2, '02 {N} tubos; {N_AM} con su tramo de la red y {N - N_AM} sin tramo',
         case when (select count(*) = {N} and count(activo_id) = {N_AM} from redes.flujo_modelo where carga_id = redes.f_ref_vigente('flujo_modelo')) then 'OK' else 'MAL' end
  union all select 3, '03 las dos horas: mayor {h_mayor['hora']}:00 y menor {h_menor['hora']}:00',
         case when (select string_agg(cual || '=' || hora, ',' order by cual) from redes.flujo_modelo_horas where carga_id = redes.f_ref_vigente('flujo_modelo')) = 'mayor={h_mayor['hora']},menor={h_menor['hora']}' then 'OK' else 'MAL' end
  union all select 4, '04 una sola carga de flujo vigente y ningún tramo con dos tubos',
         case when (select count(*) from redes.v_ref_carga_vigente where conjunto = 'flujo_modelo') = 1
               and not exists (select 1 from redes.flujo_modelo where carga_id = redes.f_ref_vigente('flujo_modelo') and activo_id is not null group by activo_id having count(*) > 1) then 'OK' else 'MAL' end
  union all select 5, 'INFO tramos de acueducto visibles con flecha · sin dato del modelo',
         (select count(*) filter (where f.activo_id is not null) || ' · ' || count(*) filter (where f.activo_id is null)
            from redes.activo_vigente_mat m left join redes.flujo_modelo f on f.carga_id = redes.f_ref_vigente('flujo_modelo') and f.activo_id = m.activo_id
           where m.sistema = 'acueducto' and m.prefijo in ('RED', 'CON') and not m.retirado and not m.oculto)
) t order by o;
""")
print(f'generado: {N} tubos, {N_AM} amarrados ({N_LLAVE} llave, {N_GEOM} geometría, {N_REVES} al revés), sin flujo {SF_MAYOR}/{SF_MENOR}, cambian de sentido {CAMBIAN}; horas {h_mayor["hora"]} y {h_menor["hora"]}; md5 {MD5}')
