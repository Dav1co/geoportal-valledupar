#!/usr/bin/env python3
"""Validación de «Cierre por aguas arriba» con la red real (Code A, localhost:55432): el caso de David (RED-000077 / VAL-000684), otros 10 tramos
y una muestra de 300. Compara las tres respuestas: aislamiento total (la de siempre), aguas arriba por cota y aguas arriba por el flujo del modelo.
Deja la base redes_local con la migración aplicada y escribe resultados/casos.txt.   Uso: python3 -I validar_casos.py"""
import json
import os
import statistics
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
SEL = ("select m.codigo from redes.activo_vigente_mat m join redes.tramo_nodos tn on tn.activo_id = m.activo_id and tn.version = m.version "
       "where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado and tn.nodo_ini is not null and tn.nodo_fin is not null "
       "and m.codigo <> 'RED-000077' order by md5(m.codigo) limit %d")
out = []


def q(sql):
    return subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, check=True, capture_output=True, text=True).stdout.strip()


def p(s=''):
    out.append(s)
    print(s, flush=True)


def caso(cod, con_total=True):
    j = json.loads(q(f"select redes.f_simular_aguas_arriba((select activo_id from redes.activo_vigente_mat where codigo = '{cod}'))"))
    t = j.get('aislamiento_total')
    if t is None and con_total:
        t = json.loads(q(f"select redes.f_simular_cierre((select activo_id from redes.activo_vigente_mat where codigo = '{cod}')) - '_contratos'"))
    return j, t


def txt(c):
    if not c.get('se_puede'):
        return 'no se puede (' + {'sin_sentido': 'sin sentido', 'sin_valvulas': 'sin válvulas aguas arriba', 'llega_a_la_fuente': 'llega al tanque'}[c['motivo']] + ')'
    v = [x['codigo'] for x in c.get('valvulas', [])]
    return f"{c['valvulas_total']} válv. ({', '.join(v[:3])}{'…' if c['valvulas_total'] > 3 else ''}) · {c['contratos_min']} a {c['contratos_max']} contratos"


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'con_au'], env=ENV, check=True, capture_output=True)
p('VALIDACIÓN DE «CIERRE POR AGUAS ARRIBA» con la red real (base local: producción con el Corte 14 + este paquete; cotas del Plan Maestro; flujo de modeloV1)')
p(f"Red: {q('select count(*) from redes.flujo_modelo where carga_id = redes.f_ref_vigente(' + chr(39) + 'flujo_modelo' + chr(39) + ')')} tubos del modelo · criterio vigente: cota")
p()
p('A. EL CASO DE DAVID y otros 10 tramos (elegidos por md5 del código, sin escoger)')
p('tramo | diámetro mm | AISLAMIENTO TOTAL (válvulas · contratos) | AGUAS ARRIBA POR COTA | AGUAS ARRIBA POR MODELO | ¿coinciden?')
for cod in ['RED-000077'] + q(SEL % 10).split('\n'):
    j, t = caso(cod)
    d = q(f"select coalesce(diametro_mm::text, '?') from redes.activo_vigente_mat where codigo = '{cod}'")
    p(f"{cod} | {d} | {t['estrecho']['valvulas_total']} válv. · {t['contratos_min']} a {t['contratos_max']} | {txt(j['aguas_arriba'])} | {txt(j['comprobacion'])} | {'sí' if j['comprobacion']['coincide'] else 'no'}")
p()
p('B. MUESTRA de 300 tramos (por md5 del código)')
n = 0
cota, modelo, coinc, ambos, ms = [], [], 0, 0, []
mot_c, mot_m = {}, {}
for cod in q(SEL % 300).split('\n'):
    j, _ = caso(cod, False)
    n += 1
    a, c = j['aguas_arriba'], j['comprobacion']
    ms.append(int(j['ms']))
    if a['se_puede']:
        cota.append(a['valvulas_total'])
    else:
        mot_c[a['motivo']] = mot_c.get(a['motivo'], 0) + 1
    if c['se_puede']:
        modelo.append(c['valvulas_total'])
    else:
        mot_m[c['motivo']] = mot_m.get(c['motivo'], 0) + 1
    if a['se_puede'] and c['se_puede']:
        ambos += 1
        coinc += 1 if c['coincide'] else 0
for nom, v, mot in (('cota', cota, mot_c), ('modelo', modelo, mot_m)):
    p(f"por {nom}: se puede en {len(v)} de {n} ({100 * len(v) / n:.0f} %); válvulas a cerrar: mediana {statistics.median(v):.0f}, de 1 a 3 en {sum(1 for x in v if x <= 3)}, de 4 a 10 en {sum(1 for x in v if 4 <= x <= 10)}, "
      f"más de 10 en {sum(1 for x in v if x > 10)}, máximo {max(v)}; no se puede en {n - len(v)}: {mot}")
p(f"los dos criterios se pueden en {ambos}; dan las MISMAS válvulas en {coinc} ({100 * coinc / max(ambos, 1):.0f} %)")
p(f"tiempo por simulación (incluye el aislamiento total cuando cae): mediana {statistics.median(ms):.0f} ms, máximo {max(ms)} ms")
open(os.path.join(os.path.dirname(AQUI), 'resultados', 'casos.txt'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
