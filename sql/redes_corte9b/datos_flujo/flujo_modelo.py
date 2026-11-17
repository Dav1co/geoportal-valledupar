#!/usr/bin/env python3
"""Corte 9b · Fase 0 — Flujo del agua según el modelo (modeloV1, Plan Maestro 2014). Reproducible; no escribe en ninguna base.
1. Corre en EPANET (wntr) el .inp de la red existente validada (modeloV1, ya probado en el análisis del Plan Maestro), 24 h.
2. Elige la hora de MAYOR y la de MENOR consumo por la demanda total de los nodos (horas 0 a 23).
   (solo entre las horas confiables: en las 5, 7, 10, 12 y 14 el modelo colapsa y el consumo «cae» por el modelo, no por la ciudad)
3. Por cada tubo del modelo: sentido del flujo, caudal (L/s, con signo: + = del nodo inicial al final del modelo) y velocidad (m/s) en esas dos horas.
4. Amarra cada tubo con su activo de la red: primero por la llave (ID del modelo = llave_capa de la capa «acueducto», como el 9a) y, si no, por geometría
   (los dos extremos del tramo a menos de TOL_M de los dos nodos del tubo, en cualquier sentido; un tramo no se usa dos veces). Dice si la geometría del activo
   va en el mismo sentido que el tubo del modelo. Todo en EPSG:3116 con PostGIS (solo lectura: una tabla temporal de la sesión).
Salida (en DESTINO): flujo_modelo_v1.csv, flujo_modelo_v1.csv.md5, horas_modelo_v1.csv (consumo por hora) y amarre_flujo_v1.txt (informe corto).
Uso: <venv_epanet>/bin/python flujo_modelo.py <archivo.inp> <destino> [base: host:puerto/base, por omisión localhost:55432/redes_local]
"""
import csv
import hashlib
import os
import subprocess
import sys

import wntr

INP, DESTINO = sys.argv[1], sys.argv[2]
BASE = sys.argv[3] if len(sys.argv) > 3 else 'localhost:55432/redes_local'
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
NO_CONFIABLES = {5, 7, 10, 12, 14}      # horas en que EPANET da la red ~14 m.c.a. por debajo de WaterGEMS (LEEME de salida_geoportal)
SIN_FLUJO_LPS = 0.01
os.makedirs(DESTINO, exist_ok=True)

wn = wntr.network.WaterNetworkModel(INP)
res = wntr.sim.EpanetSimulator(wn).run_sim()
paso = int(wn.options.time.report_timestep or 3600)
dem = res.node['demand'][wn.junction_name_list]                  # m³/s por nodo y tiempo (demanda servida, con las fugas de los emisores)
tot = dem.sum(axis=1)
horas = {int(t // 3600): float(v) for t, v in tot.items() if t % 3600 == 0 and t < 24 * 3600}
# en las horas no confiables el consumo «cae» porque el modelo colapsa (las fugas de los emisores dependen de la presión): se eligen entre las confiables
conf = [h for h in horas if h not in NO_CONFIABLES]
h_mayor = max(conf, key=lambda h: horas[h]); h_menor = min(conf, key=lambda h: horas[h])

with open(os.path.join(DESTINO, 'horas_modelo_v1.csv'), 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f, lineterminator='\n'); w.writerow(['hora', 'consumo_total_lps', 'confiable'])
    for h in sorted(horas): w.writerow([h, f'{horas[h] * 1000:.1f}', 'no' if h in NO_CONFIABLES else 'si'])

q = res.link['flowrate']; v = res.link['velocity']
coords = {n: wn.get_node(n).coordinates for n in wn.node_name_list}

# extremos de los activos de la capa «acueducto» en EPSG:3116 (solo lectura)
host, resto = BASE.split(':'); puerto, base = resto.split('/')
sql = ("select llave_capa || '|' || st_x(st_transform(st_startpoint(g), 3116)) || '|' || st_y(st_transform(st_startpoint(g), 3116)) || '|' || "
       "st_x(st_transform(st_endpoint(g), 3116)) || '|' || st_y(st_transform(st_endpoint(g), 3116)) || '|' || codigo "
       "from (select m.llave_capa, m.codigo, (st_dump(st_linemerge(m.geom))).geom as g from redes.activo_vigente_mat m "
       "where m.capa_codigo = 'acueducto' and not m.retirado and geometrytype(m.geom) in ('LINESTRING', 'MULTILINESTRING')) x")
salida = subprocess.run([PSQL, '-h', host, '-p', puerto, '-U', 'postgres', '-d', base, '-AtX', '-c', sql], check=True, capture_output=True, text=True).stdout
act = {}
for l in salida.splitlines():
    k, x1, y1, x2, y2, cod = l.split('|')
    act.setdefault(k, []).append((float(x1), float(y1), float(x2), float(y2), cod))


TOL_M = 2.0      # = cruce_geometria_tol_m del Cargue (Corte 5c)
usados = {k for k in act if k in set(wn.pipe_name_list)}
sin_llave = [n for n in wn.pipe_name_list if n not in act]
filas_tmp = '\n'.join(f"{n}\t{coords[wn.get_link(n).start_node_name][0]}\t{coords[wn.get_link(n).start_node_name][1]}\t{coords[wn.get_link(n).end_node_name][0]}\t{coords[wn.get_link(n).end_node_name][1]}" for n in sin_llave)
sql_geo = (f"create temp table _t (llave text, x1 float8, y1 float8, x2 float8, y2 float8);\n\\copy _t from stdin\n{filas_tmp}\n\\.\n"
   "create temp table _c as select m.llave_capa, m.codigo, st_transform(st_startpoint(g), 3116) as a, st_transform(st_endpoint(g), 3116) as b "
   "from (select m.*, (st_dump(st_linemerge(m.geom))).geom as g from redes.activo_vigente_mat m where m.capa_codigo = 'acueducto' and not m.retirado) m;\n"
   "create index on _c using gist (a);\n"
   f"select t.llave || '|' || c.llave_capa || '|' || c.codigo || '|' || case when st_dwithin(c.a, st_setsrid(st_makepoint(t.x1, t.y1), 3116), {TOL_M}) then 'si' else 'no' end "
   "from _t t join _c c on (st_dwithin(c.a, st_setsrid(st_makepoint(t.x1, t.y1), 3116), " + str(TOL_M) + ") and st_dwithin(c.b, st_setsrid(st_makepoint(t.x2, t.y2), 3116), " + str(TOL_M) + ")) "
   "or (st_dwithin(c.a, st_setsrid(st_makepoint(t.x2, t.y2), 3116), " + str(TOL_M) + ") and st_dwithin(c.b, st_setsrid(st_makepoint(t.x1, t.y1), 3116), " + str(TOL_M) + "));\n")
geo = subprocess.run([PSQL, '-h', host, '-p', puerto, '-U', 'postgres', '-d', base, '-AtXq'], input=sql_geo, check=True, capture_output=True, text=True).stdout
cand = {}
for l in geo.splitlines():
    if l.count('|') != 3: continue
    t, k, cod, mismo = l.split('|'); cand.setdefault(t, []).append((k, cod, mismo))
por_geo = {}; ambiguos = 0
for t_ in sorted(cand, key=lambda s: (len(s), s)):
    libres = [c for c in cand[t_] if c[0] not in usados]
    if len(libres) == 1: por_geo[t_] = libres[0]; usados.add(libres[0][0])
    elif len(libres) > 1: ambiguos += 1


def sentido(qq):
    return 'sin_flujo' if abs(qq) < SIN_FLUJO_LPS else ('ini_fin' if qq > 0 else 'fin_ini')


filas = []; amarran = 0; amarran_geo = 0; dudosos = 0; multi = 0
for nombre in sorted(wn.pipe_name_list, key=lambda s: (len(s), s)):
    p = wn.get_link(nombre)
    qa, qb = q[nombre].loc[h_mayor * 3600] * 1000, q[nombre].loc[h_menor * 3600] * 1000
    va, vb = v[nombre].loc[h_mayor * 3600], v[nombre].loc[h_menor * 3600]
    a = act.get(nombre); mismo = ''; codigo = ''; via = ''
    if nombre in por_geo:
        via = 'geometria'; codigo = por_geo[nombre][1]; mismo = por_geo[nombre][2]; amarran_geo += 1
    elif a:
        via = 'llave'
        amarran += 1
        if len(a) > 1: multi += 1
        x1, y1, x2, y2, codigo = a[0]
        (ix, iy), (fx, fy) = coords[p.start_node_name], coords[p.end_node_name]
        d_igual = ((x1 - ix) ** 2 + (y1 - iy) ** 2) ** .5 + ((x2 - fx) ** 2 + (y2 - fy) ** 2) ** .5
        d_cruz = ((x1 - fx) ** 2 + (y1 - fy) ** 2) ** .5 + ((x2 - ix) ** 2 + (y2 - iy) ** 2) ** .5
        mismo = 'si' if d_igual < d_cruz else 'no'
        if min(d_igual, d_cruz) > 20: dudosos += 1                # los extremos no coinciden a menos de ~10 m cada uno
    filas.append([nombre, codigo, p.start_node_name, p.end_node_name, f'{p.length:.2f}', f'{p.diameter * 1000:.1f}', str(p.initial_status).lower().replace('linkstatus.', ''),
                  f'{qa:.3f}', f'{va:.3f}', sentido(qa), f'{qb:.3f}', f'{vb:.3f}', sentido(qb), mismo, via])

arch = os.path.join(DESTINO, 'flujo_modelo_v1.csv')
with open(arch, 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f, lineterminator='\n')
    w.writerow(['llave', 'activo_codigo', 'nodo_ini', 'nodo_fin', 'longitud_m', 'diametro_mm', 'estado_inicial',
                f'q_lps_h{h_mayor:02d}', f'v_mps_h{h_mayor:02d}', f'sentido_h{h_mayor:02d}', f'q_lps_h{h_menor:02d}', f'v_mps_h{h_menor:02d}', f'sentido_h{h_menor:02d}', 'geom_mismo_sentido', 'amarre'])
    w.writerows(filas)
md5 = hashlib.md5(open(arch, 'rb').read()).hexdigest()
open(arch + '.md5', 'w').write(f'{md5}  flujo_modelo_v1.csv\n')

n = len(filas); sinf_a = sum(1 for r in filas if r[9] == 'sin_flujo'); sinf_b = sum(1 for r in filas if r[12] == 'sin_flujo')
capa = sum(len(x) for x in act.values())
inf = f"""Flujo del agua según el modelo (modeloV1, Plan Maestro 2014) — Corte 9b, Fase 0
Modelo: {os.path.basename(INP)} · EPANET (wntr {wntr.__version__}) · 24 h, reporte cada {paso // 60} min
Hora de MAYOR consumo: {h_mayor}:00 ({horas[h_mayor] * 1000:.0f} L/s; {'NO confiable' if h_mayor in NO_CONFIABLES else 'confiable'}) · hora de MENOR consumo: {h_menor}:00 ({horas[h_menor] * 1000:.0f} L/s; {'NO confiable' if h_menor in NO_CONFIABLES else 'confiable'})
Tubos del modelo: {n} · sin flujo (|Q| < {SIN_FLUJO_LPS} L/s): {sinf_a} en la hora de mayor consumo y {sinf_b} en la de menor
Amarre con la capa «acueducto»: {amarran + amarran_geo} amarran ({(amarran + amarran_geo) * 100 / n:.1f} %) y {n - amarran - amarran_geo} no amarran
  · por la llave (ID del modelo = llave_capa, como el 9a): {amarran} · por geometría (los dos extremos a menos de {TOL_M:g} m de los nodos del tubo): {amarran_geo} · con más de un tramo posible (sin amarrar): {ambiguos}
  · de los que amarran: {sum(1 for r in filas if r[13] == 'si')} con la geometría en el mismo sentido que el modelo y {sum(1 for r in filas if r[13] == 'no')} al revés (la flecha se voltea al cargar)
  · {dudosos} con los extremos lejos de los nodos del modelo (más de ~10 m en promedio) y {multi} con la geometría partida en varias líneas: revisar
Tramos de la capa sin tubo del modelo: {len(set(act) - usados)} (de {len(act)}): red que no está en modeloV1 (nueva, del Plan o de la carga del 1a)
CSV: flujo_modelo_v1.csv · md5 {md5}
"""
open(os.path.join(DESTINO, 'amarre_flujo_v1.txt'), 'w', encoding='utf-8').write(inf)
print(inf)
