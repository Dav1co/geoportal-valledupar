#!/usr/bin/env python3
"""Arnés local del Corte 5b (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Como en el despliegue (1a con la carga real, Cortes 2 a 5a y la primera carga MUE de los 27 puntos publicada):
huellas antes · ensayo (ERROR esperado y sin rastro) · migración · verificación · guardia · huellas después · reversa vacía (exacta al 5a) ·
verificación del 5a · segunda reversa · migrar de nuevo · un operador real propone la ubicación de un punto real, un supervisor la aprueba ·
la recarga de la capa MUE con el mismo archivo de la primera carga conserva la verificada · verificación con datos · reversa con datos (rechazo).
Uso: python3 -I correr_local.py   → escribe ../resultados/sql_local.txt
"""
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
C1A = os.environ.get('C1A', os.path.expanduser('~/geoportal-emdupar-tec-c1a/sql/redes_corte1a'))
C5A = os.path.join(os.path.dirname(RAIZ), 'redes_corte5a')
MUE = os.path.join(C5A, 'carga_mue', 'generado')
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
ADMIN = 'carga.local@emdupar.gov.co'
OP = 'zt.oper@emdupar.gov.co'
SUP = 'zt.super@emdupar.gov.co'
res = []


def archivo(nombre, extra=None, cwd=None):
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-X', '-v', 'ON_ERROR_STOP=1'] + (extra or []) + ['-f', nombre], env=ENV, capture_output=True, text=True, cwd=cwd)
    return p.returncode, p.stdout + p.stderr, time.time() - t


def q(sql):
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip())


def reg(nombre, ok, detalle=''):
    detalle = '' if ok and len(detalle) > 260 else detalle
    res.append((nombre, bool(ok), detalle))
    print(('OK   ' if ok else 'FALLA'), nombre, ('· ' + detalle if detalle else ''))


ED = lambda n: os.path.join(RAIZ, n)  # noqa: E731
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
VIG = ("select u.exactitud || '|' || u.fuente || '|' || u.autor from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = '{}'")

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_5a'], env=ENV, check=True, capture_output=True)
GEN = os.path.join(C1A, 'carga', 'generado')
rc1, _, _ = archivo('carga_inicial_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
rc2, _, s2 = archivo('publicar.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
rc3, _, _ = archivo('carga_mue_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=MUE)
rc4, out4, _ = archivo('publicar_mue.sql', ['-v', f'solicitante={ADMIN}'], cwd=MUE)
reg('01 como en la base viva al publicar: carga real (35.781 activos) y la primera carga MUE (27 puntos: 3 verificados, 24 aproximados)',
    rc1 == rc2 == rc3 == rc4 == 0 and q('select count(*) from redes.activo_vigente_mat') == '35781'
    and q("select count(*) filter (where exactitud = 'verificada') || '|' || count(*) from redes.v_punto_ubicacion_vigente") == '3|27', out4[-300:] if rc4 else '')
md5_5a = q(CONJ)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte5b_editor.sql'))
reg('02 huellas antes: «CORTE 5a (listo para el 5b)», 4 RPC «NO EXISTE», la reemplazada «CORTE 5a (sin cambiar)», 2 tablas «NO EXISTE»', rc == 0
    and 'CORTE 5a (listo para el 5b)' in out and out.count('NO EXISTE (sin aplicar)') == 6 and out.count('CORTE 5a (sin cambiar)') == 1 and 'DISTINTA' not in out)
ubic0 = q('select count(*) from tecnica.puntos_ubicacion')
rc, out, seg = archivo(ED('ensayo_en_transaccion_redes_corte5b_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('03 ensayo DESPUÉS de la carga real y la MUE: ERROR con «N de N … SIN FALLAS»', rc != 0 and m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS'),
    (m.group(0) if m else out[-800:]) + f' ({seg:.1f} s)')
reg('04 el ensayo no deja rastro (ni tablas, ni funciones, ni ubicaciones, ni puntos de prueba)', q("select to_regclass('tecnica.punto_ubicacion_propuestas') is null") == 't'
    and q(CONJ) == md5_5a and q('select count(*) from tecnica.puntos_ubicacion') == ubic0 and q("select count(*) from tecnica.puntos where codigo like 'MUE-98%'") == '0')
rc, out, seg = archivo(ED('migracion_redes_corte5b_editor.sql'))
reg('05 migración _editor', rc == 0, f'{seg:.1f} s' if rc == 0 else out[-400:])
rc, out, _ = archivo(ED('verificacion_redes_corte5b_editor.sql'))
reg('06 verificación: 8 OK', rc == 0 and out.count('| OK') == 8 and '| MAL' not in out, '' if rc == 0 else out[-300:])
rc, out, _ = archivo(ED('migracion_redes_corte5b_editor.sql'))
reg('07 repetir la migración se rechaza (guardia)', rc != 0 and 'deténgase' in out)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte5b_editor.sql'))
reg('08 huellas después: «CORTE 5b (aplicado)», 4 «NUEVA», «CORTE 5b (reemplazada)» y 2 «EXISTE»', 'CORTE 5b (aplicado)' in out and out.count('NUEVA (aplicada)') == 4
    and out.count('CORTE 5b (reemplazada)') == 1 and out.count('EXISTE (aplicado)') == 2 and 'DISTINTA' not in out)
rc, out, _ = archivo(os.path.join(C5A, 'verificacion_redes_corte5a_editor.sql'))
reg('09 la verificación del 5a, con el 5b aplicado: solo la fila 05 dice MAL (a propósito: cambió el conjunto de funciones)', out.count('| MAL') == 1 and re.search(r'05 huellas[^\n]*\| MAL', out) is not None)
rc, out, _ = archivo(ED('reversa_redes_corte5b_editor.sql'))
reg('10 reversa sin datos: vuelve exactamente al 5a', rc == 0 and q(CONJ) == md5_5a and q("select count(*) from pg_proc where proname like 'geoportal\\_tec\\_punto%'") == '0', out[-300:] if rc else '')
rc, out, _ = archivo(os.path.join(C5A, 'verificacion_redes_corte5a_editor.sql'))
reg('11 tras la reversa, la verificación del 5a vuelve a dar 9 OK', out.count('| OK') == 9 and '| MAL' not in out)
rc, out, _ = archivo(ED('reversa_redes_corte5b_editor.sql'))
reg('12 una segunda reversa se niega (no hay nada que revertir)', rc != 0 and 'No hay nada que revertir' in out)
rc, out, _ = archivo(ED('migracion_redes_corte5b_editor.sql'))
reg('13 migrar de nuevo después de la reversa', rc == 0, out[-300:] if rc else '')

# un operador real propone la ubicación de un punto real aproximado (MUE-05, OGB) y un supervisor la aprueba
pto = 'MUE-05'
lat, lon = q(f"select u.lat || '|' || u.lon from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = '{pto}'").split('|')
r = q(f"select public.geoportal_tec_punto_ubicacion_proponer('{OP}', '{pto}', {float(lat) + 0.0003}, {float(lon) - 0.0002}, 7.5)")
reg('14 el operador propone la ubicación de MUE-05 (aproximada por barrio) con el GPS: pendiente', '"estado": "pendiente"' in r, r[:200])
pid = re.search(r'"propuesta_id": (\d+)', r).group(1) if '"propuesta_id"' in r else '0'
r = q(f"select public.geoportal_tec_punto_ubicacion_revisar('{SUP}', {pid}, 'aprobar', null)")
reg('15 el supervisor de planta la aprueba: MUE-05 queda verificada, del GPS del operador', '"aprobada"' in r and q(VIG.format(pto)) == f'verificada|gps_operador|{OP}', r[:200])
mapa = q(f"select public.geoportal_tec_puntos_mapa('{OP}')")
reg('16 el minimapa trae los 27 puntos, 4 verificados', mapa.count('"Feature"') == 27 and mapa.count('"verificada"') == 4)

# una recarga con el mismo contenido que la primera carga (otra huella de archivo): MUE-05 se conserva verificada
gen = open(os.path.join(MUE, 'carga_mue_todo.sql'), encoding='utf-8').read()
m_sha = re.search(r"'([0-9a-f]{64})'", gen)
gen2 = gen.replace(m_sha.group(1), 'f' * 64) if m_sha else gen
tmp = os.path.join(RAIZ, 'resultados', '_recarga_mue.sql')
open(tmp, 'w', encoding='utf-8').write(gen2)
rc, out, _ = archivo(tmp, ['-v', f'solicitante={ADMIN}'], cwd=MUE)
os.remove(tmp)
reg('17 recarga MUE con el archivo de la primera carga: MUE-05 sale «conserva_verificada» y la carga queda lista para publicar', rc == 0 and 'conserva_verificada' in out
    and re.search(r'lista para publicar\s*\|\s*SÍ', out) is not None, out[-600:])
cid = q("select max(id) from redes.cargas where capa_codigo = 'muestreo'")
r = q(f"select public.geoportal_redes_carga_publicar('{ADMIN}', {cid}, 'Recarga local de prueba del Corte 5b')")
reg('18 al publicar la recarga, MUE-05 sigue verificada por GPS y las otras 26 no cambian', q(VIG.format(pto)) == f'verificada|gps_operador|{OP}'
    and q("select count(*) filter (where exactitud = 'verificada') || '|' || count(*) from redes.v_punto_ubicacion_vigente") == '4|27', r[:300])
rc, out, _ = archivo(ED('verificacion_redes_corte5b_editor.sql'))
reg('19 verificación con datos: 8 OK (INFO: 0 pendientes · 1 aprobada; 4 verificados · 23 aproximados)', out.count('| OK') == 8 and '| MAL' not in out
    and '0 · 1 · 0' in out and '4 · 23 · 0' in out, out[-500:])
rc, out, _ = archivo(ED('reversa_redes_corte5b_editor.sql'))
reg('20 la reversa con datos se niega (nada se borra)', rc != 0 and 'la reversa se niega' in out and q("select to_regclass('tecnica.punto_ubicacion_propuestas') is not null") == 't')

bien = sum(1 for _, ok, _ in res if ok)
lineas = [('OK   ' if ok else 'FALLA') + ' ' + n + (' · ' + d if d else '') for n, ok, d in res]
lineas.append(f'RESULTADO: {bien} de {len(res)} — ' + ('SIN FALLAS' if bien == len(res) else f'{len(res) - bien} FALLA(S)'))
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write('\n'.join(lineas) + '\n')
print(lineas[-1])
