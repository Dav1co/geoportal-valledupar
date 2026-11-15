#!/usr/bin/env python3
"""Arnés local del Corte 2 (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Encadena, con los _editor del 1a y del 2 y los shapefiles REALES (la carga del 1a):
  huellas antes · ensayo (ERROR esperado y sin rastro) · migración · verificación · migración repetida · reversa vacía (vuelve al 1a) ·
  migración de nuevo · carga real del 1a · consulta de los 35 pozos «0» · teselas reales (peso a z15 y tiempo) · un daño real en V85 y su epicrisis ·
  verificación con datos · reversa con datos (rechazo).
Uso: python3 -I correr_local.py   → escribe ../resultados/sql_local.txt
"""
import os
import re
import subprocess
import sys
import time
import base64

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
C1A = os.environ.get('C1A', os.path.expanduser('~/geoportal-emdupar-tec-c1a/sql/redes_corte1a'))
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
ADMIN = 'carga.local@emdupar.gov.co'
res = []


def archivo(nombre, extra=None, cwd=None):
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-X', '-v', 'ON_ERROR_STOP=1'] + (extra or []) + ['-f', nombre], env=ENV, capture_output=True, text=True, cwd=cwd)
    return p.returncode, p.stdout + p.stderr, time.time() - t


def q(sql):
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip())


def reg(nombre, ok, detalle=''):
    res.append((nombre, bool(ok), detalle))
    print(('OK   ' if ok else 'FALLA'), nombre, ('· ' + detalle if detalle else ''))


ED = lambda n: os.path.join(RAIZ, n)  # noqa: E731
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_1a'], env=ENV, check=True, capture_output=True)
md5_1a = q(CONJ)

rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte2_editor.sql'))
reg('01 huellas antes: «CORTE 1a (listo para el 2)», 8 RPC y bucket «NO EXISTE», 5 dependencias «EXISTE»', rc == 0 and 'CORTE 1a (listo para el 2)' in out
    and out.count('NO EXISTE (sin aplicar)') == 9 and out.count('| EXISTE') == 5 and 'FALTA' not in out and 'DISTINTA' not in out)
rc, out, seg = archivo(ED('ensayo_en_transaccion_redes_corte2_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('02 ensayo: ERROR con «N de N … SIN FALLAS»', rc != 0 and m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS'), (m.group(0) if m else out[-500:]) + f' ({seg:.1f} s)')
reg('03 el ensayo no deja rastro (ni tablas, ni bucket, ni funciones)', q("select to_regclass('redes.danos') is null") == 't' and q("select count(*) from storage.buckets where id = 'redes-evidencias'") == '0' and q(CONJ) == md5_1a)
rc, out, seg = archivo(ED('migracion_redes_corte2_editor.sql'))
reg('04 migración _editor', rc == 0, f'{seg:.1f} s' if rc == 0 else out[-300:])
rc, out, _ = archivo(ED('verificacion_redes_corte2_editor.sql'))
reg('05 verificación sin datos: 11 OK', rc == 0 and out.count('| OK') == 11 and '| MAL' not in out)
rc, out, _ = archivo(ED('migracion_redes_corte2_editor.sql'))
reg('06 repetir la migración se rechaza (guardia)', rc != 0 and 'deténgase' in out)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte2_editor.sql'))
reg('07 huellas después: «CORTE 2 (aplicado)», 8 RPC y bucket «NUEVA (aplicada)»', 'CORTE 2 (aplicado)' in out and out.count('NUEVA (aplicada)') == 9)
rc, out, _ = archivo(ED('reversa_redes_corte2_editor.sql'))
reg('08 reversa sin datos: vuelve exactamente al 1a (funciones y epicrisis)', rc == 0 and q(CONJ) == md5_1a and q("select to_regclass('redes.danos') is null") == 't', out[-300:] if rc else '')
rc, out, _ = archivo(os.path.join(C1A, 'verificacion_redes_corte1a_editor.sql'))
reg('09 tras la reversa, la verificación del 1a vuelve a dar 13 OK', out.count('| OK') == 13)
rc, out, _ = archivo(ED('reversa_redes_corte2_editor.sql'))
reg('10 una segunda reversa se niega', rc != 0 and 'No hay nada que revertir' in out)
rc, out, _ = archivo(ED('migracion_redes_corte2_editor.sql'))
reg('11 volver a migrar después de la reversa', rc == 0)

# carga real del 1a con el Corte 2 ya aplicado
GEN = os.path.join(C1A, 'carga', 'generado')
rc1, _, s1 = archivo('carga_inicial_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
rc2, _, s2 = archivo('publicar.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
reg('12 la carga real del 1a con el Corte 2 aplicado: 35.781 activos', rc1 == 0 and rc2 == 0 and q('select count(*) from redes.activo_vigente_mat') == '35781', f'maestro {s1:.1f} s, publicar {s2:.1f} s')
rc, out, _ = archivo(os.path.join(C1A, 'consulta_pozos_eliminar_sin_dato_editor.sql'))
open(os.path.join(RAIZ, 'resultados', 'pozos_por_eliminar_sin_dato.txt'), 'w', encoding='utf-8').write(out)
reg('13 consulta para Técnica: los 35 pozos con EST_POZO «0», «por eliminar» y «Sin dato»', rc == 0 and '(35 filas)' in out, out.strip().splitlines()[-1] if out.strip() else '')

# teselas reales: peso y tiempo
def tesela(z, lon, lat):
    import math
    n = 1 << z
    return z, int((lon + 180) / 360 * n), int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n)
CENTRO = (-73.2532, 10.4631)
for sis in ('acueducto', 'alcantarillado'):
    pesos, t0 = [], time.time()
    z, x0, y0 = tesela(15, *CENTRO)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            b64 = q(f"select public.geoportal_redes_mvt('{ADMIN}', 15, {x0 + dx}, {y0 + dy}, '{sis}')")
            pesos.append(len(base64.b64decode(b64)) if b64 and not b64.startswith('ERROR') else -1)
    ms = (time.time() - t0) / 9 * 1000
    reg(f'14 teselas z15 de {sis} en el centro (3×3): la más pesada por debajo de 150 KB (riesgo del Corte 2)', min(pesos) >= 0 and max(pesos) < 150 * 1024,
        f'máx {max(pesos) / 1024:.1f} KB, media {sum(pesos) / len(pesos) / 1024:.1f} KB, {ms:.0f} ms por tesela (con psql)')
v85 = q("select st_y(geom) || '|' || st_x(geom) || '|' || codigo from redes.activo_vigente_mat where codigo_anterior = 'V85'").split('|')
z, x, y = tesela(17, float(v85[1]), float(v85[0]))
b64_17 = q(f"select public.geoportal_redes_mvt('{ADMIN}', 17, {x}, {y}, 'acueducto')")
crudo = base64.b64decode(b64_17)
reg('15 tesela z17 sobre V85: trae la válvula y accesorios', v85[2].encode() in crudo and b'ACC-' in crudo, f'{len(crudo) / 1024:.1f} KB')
z, x, y = tesela(16, float(v85[1]), float(v85[0]))
reg('16 tesela z16 sobre V85: sin accesorios (desde z17)', b'ACC-' not in base64.b64decode(q(f"select public.geoportal_redes_mvt('{ADMIN}', 16, {x}, {y}, 'acueducto')")))

# un daño real sobre V85 (foto de prueba en el Storage local)
prep = q(f"select public.geoportal_redes_preparar_dano('{ADMIN}', 1)")
did = re.search(r'"dano_id": "([0-9a-f-]+)"', prep).group(1)
ruta = re.search(r'"ruta": "([^"]+)"', prep).group(1)
q(f"insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '{ruta}', '{{\"size\": 250000, \"mimetype\": \"image/jpeg\"}}')")
datos = ('{"clase": "falla", "tipo": "valvula_no_opera", "sistema": "acueducto", "activo": "%s", "lat": %s, "lon": %s, "ubicacion_origen": "gps", "precision_m": 5, '
         '"t_detectado": "%s", "riesgo": "alto", "marcas": ["personas"], "causa_clase": "desconocida", "fotos": [{"n": 1, "momento": "dano", "ruta": "%s"}]}') % (
    v85[2], v85[0], v85[1], q("select to_char(now() - interval '30 minutes', 'YYYY-MM-DD\"T\"HH24:MI:SSOF')"), ruta)
r = q(f"select public.geoportal_redes_crear_dano('{ADMIN}', '{did}', '{datos}')")
reg('17 un daño real (falla: válvula que no opera) sobre V85: DAN-000001', '"codigo": "DAN-000001"' in r, r[:200])
ep = q(f"select public.geoportal_redes_epicrisis('{ADMIN}', '{v85[2]}')")
fi = q(f"select public.geoportal_redes_activo('{ADMIN}', '{v85[2]}') -> 'epicrisis'")
reg('18 la epicrisis de V85 trae la falla como «hecho» y la ficha cuenta 1', '"clase": "falla"' in ep and '"grupo": "hecho"' in ep and '"hechos": 1' in fi, fi)
rc, out, _ = archivo(ED('verificacion_redes_corte2_editor.sql'))
reg('19 verificación con datos: 11 OK', out.count('| OK') == 11 and '| MAL' not in out and 'reportado 1' in out)
rc, out, _ = archivo(ED('reversa_redes_corte2_editor.sql'))
reg('20 la reversa se niega con datos (nada se borra)', rc != 0 and 'se niega' in out and q('select count(*) from redes.danos') == '1')

bien = sum(1 for _, ok, _ in res if ok)
lin = [f"{'OK   ' if ok else 'FALLA'} {n}{(' · ' + d) if d else ''}" for n, ok, d in res]
lin.append(f'RESULTADO: {bien} de {len(res)} — {"SIN FALLAS" if bien == len(res) else str(len(res) - bien) + " FALLA(S)"}')
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write('\n'.join(lin) + '\n')
print(lin[-1])
sys.exit(0 if bien == len(res) else 1)
