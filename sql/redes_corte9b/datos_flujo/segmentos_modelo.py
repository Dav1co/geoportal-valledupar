#!/usr/bin/env python3
"""Corte 9b · Fase 0 — Segmentos de aislamiento de modeloV1 (análisis «segmento-válvula» de la §17). Reproducible; no escribe en ninguna base.
Un segmento = lo que queda conectado al quitar todas las válvulas del modelo: es lo mínimo que se puede aislar cerrando las válvulas que lo rodean.
Para cada válvula: si se cierra sola, qué demanda queda sin camino hasta una fuente (tanque o embalse); y los segmentos sin fuente propia.
Salida: segmentos_modelo_v1.csv (tubo → segmento), valvulas_criticidad_v1.csv y segmentos_v1.txt (resumen).
Uso: <venv_epanet>/bin/python segmentos_modelo.py <archivo.inp> <destino>
"""
import csv
import os
import sys
from collections import Counter, defaultdict

import networkx as nx
import wntr

INP, DESTINO = sys.argv[1], sys.argv[2]
os.makedirs(DESTINO, exist_ok=True)
wn = wntr.network.WaterNetworkModel(INP)
fuentes = set(wn.tank_name_list) | set(wn.reservoir_name_list)
dem = {j: wn.get_node(j).base_demand * 1000 for j in wn.junction_name_list}          # L/s (demanda base del primer patrón)
G = nx.Graph()
G.add_nodes_from(wn.node_name_list)
for n in wn.pipe_name_list + wn.pump_name_list:
    l = wn.get_link(n)
    if str(l.initial_status).lower().endswith('closed'): continue                     # tubos cerrados en el modelo no conducen
    G.add_edge(l.start_node_name, l.end_node_name, link=n)
valv = {}
for n in wn.valve_name_list:
    l = wn.get_link(n); valv[n] = (l.start_node_name, l.end_node_name, str(l.initial_status).lower())

seg_de = {}
for i, comp in enumerate(sorted(nx.connected_components(G), key=lambda c: (-len(c), min(c)))):
    for nodo in comp: seg_de[nodo] = i
segs = defaultdict(lambda: {'nodos': 0, 'demanda': 0.0, 'fuente': False, 'tubos': 0, 'valvulas': set()})
for nodo, s in seg_de.items():
    segs[s]['nodos'] += 1; segs[s]['demanda'] += dem.get(nodo, 0.0); segs[s]['fuente'] |= nodo in fuentes
for a, b, d in G.edges(data=True): segs[seg_de[a]]['tubos'] += 1
for n, (a, b, _) in valv.items():
    segs[seg_de[a]]['valvulas'].add(n); segs[seg_de[b]]['valvulas'].add(n)

# Criticidad: la red con todas las válvulas abiertas (las cerradas en el modelo se quedan cerradas); se cierra UNA y se mira qué demanda pierde la fuente
H = G.copy()
for n, (a, b, st) in valv.items():
    if not st.endswith('closed'): H.add_edge(a, b, link=n)


def sin_fuente(g):
    alc = set()
    for f in fuentes:
        if f in g: alc |= nx.node_connected_component(g, f)
    return [n for n in g.nodes if n not in alc]


base_sin = set(sin_fuente(H))
crit = []
for n, (a, b, st) in sorted(valv.items(), key=lambda x: (len(x[0]), x[0])):
    if st.endswith('closed') or not H.has_edge(a, b): crit.append((n, st, 0, 0.0, 'fuera_de_servicio' if st.endswith('closed') else 'paralela')); continue
    d = H.get_edge_data(a, b); H.remove_edge(a, b)
    perd = [x for x in sin_fuente(H) if x not in base_sin]
    H.add_edge(a, b, **d)
    crit.append((n, st, len(perd), sum(dem.get(x, 0.0) for x in perd), 'cierra' if perd else 'deriva'))

with open(os.path.join(DESTINO, 'segmentos_modelo_v1.csv'), 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f, lineterminator='\n'); w.writerow(['llave_tubo', 'segmento'])
    for a, b, d in sorted(G.edges(data=True), key=lambda e: (len(e[2]['link']), e[2]['link'])): w.writerow([d['link'], seg_de[a]])
with open(os.path.join(DESTINO, 'valvulas_criticidad_v1.csv'), 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f, lineterminator='\n'); w.writerow(['llave_valvula', 'estado_modelo', 'nodos_sin_agua', 'demanda_sin_agua_lps', 'efecto_sugerido'])
    for r in crit: w.writerow([r[0], r[1].replace('linkstatus.', ''), r[2], f'{r[3]:.2f}', r[4]])

con_demanda = [s for s in segs.values() if s['demanda'] > 0]
tam = sorted((s['demanda'] for s in segs.values()), reverse=True)
sin_valv = sum(1 for s in segs.values() if not s['valvulas'] and not s['fuente'])
ef = Counter(r[4] for r in crit); top = sorted(crit, key=lambda r: -r[3])[:5]
tot = sum(dem.values())
inf = f"""Segmentos de aislamiento de modeloV1 (análisis segmento-válvula, §17) — Corte 9b, Fase 0
Red: {len(wn.junction_name_list)} nodos de consumo, {len(wn.pipe_name_list)} tubos, {len(valv)} válvulas ({sum(1 for v in valv.values() if v[2].endswith('closed'))} cerradas en el modelo), {len(fuentes)} fuentes (tanques y embalses). Demanda base total {tot:.0f} L/s.
Segmentos (lo mínimo que se aísla cerrando las válvulas que lo rodean): {len(segs)}; con demanda: {len(con_demanda)}.
  · el más grande lleva {tam[0]:.0f} L/s ({tam[0] * 100 / tot:.0f} % de la demanda); los 5 más grandes, {sum(tam[:5]) * 100 / tot:.0f} %; mediana de los que tienen demanda {sorted(s['demanda'] for s in con_demanda)[len(con_demanda) // 2]:.2f} L/s
  · segmentos sin ninguna válvula alrededor ni fuente (no se pueden aislar con válvulas del modelo): {sin_valv}
Válvulas cerradas una a una (las demás como en el modelo): {ef.get('cierra', 0)} «cierran» (dejan demanda sin camino a una fuente), {ef.get('deriva', 0)} «derivan» (el agua llega por otro lado), {ef.get('fuera_de_servicio', 0)} cerradas en el modelo, {ef.get('paralela', 0)} en paralelo
Las 5 más críticas (demanda que dejan sin agua): {', '.join(f'{r[0]} ({r[3]:.1f} L/s, {r[2]} nodos)' for r in top)}
"""
open(os.path.join(DESTINO, 'segmentos_v1.txt'), 'w', encoding='utf-8').write(inf)
print(inf)
