#!/usr/bin/env python3
"""Arnés local del Corte 3b (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Como en el despliegue (1a, carga real, Cortes 2 y 3a ya publicados): huellas antes · carga real, predios, un daño y una reparación reales en V85 con fotos ·
ensayo (ERROR esperado y sin rastro) · migración · verificación · guardia · huellas después · reversa vacía (exacta al 3a) · verificación del 3a ·
segunda reversa · migrar de nuevo · editar la ficha real de V85 (versión, tabla vigente y tesela) · alias y placa y la búsqueda · galería · epicrisis ·
tiempo · verificación con datos · reversa con datos (rechazo).
Uso: python3 -I correr_local.py   → escribe ../resultados/sql_local.txt
"""
import base64
import math
import os
import re
import subprocess
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
C1A = os.environ.get('C1A', os.path.expanduser('~/geoportal-emdupar-tec-c1a/sql/redes_corte1a'))
C3A = os.path.join(os.path.dirname(RAIZ), 'redes_corte3a')
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
ADMIN = 'carga.local@emdupar.gov.co'
OPER = 'zt.oper@emdupar.gov.co'
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


def lit(s):
    return "'" + s.replace("'", "''") + "'"


ED = lambda n: os.path.join(RAIZ, n)  # noqa: E731
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
VISTAS = "select md5(pg_get_viewdef('redes.v_dano'::regclass, true)) || md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true))"
ISO = lambda intervalo: q(f"select to_char(now() + interval '{intervalo}', 'YYYY-MM-DD\"T\"HH24:MI:SSOF')")  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_3a'], env=ENV, check=True, capture_output=True)
md5_3a, epi_3a = q(CONJ), q("select md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true))")
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte3b_editor.sql'))
reg('01 huellas antes: «CORTE 3a (listo para el 3b)», 5 RPC «NO EXISTE», activo_buscar y v_epicrisis «CORTE 3a (sin cambiar)»', rc == 0 and 'CORTE 3a (listo para el 3b)' in out
    and out.count('NO EXISTE (sin aplicar)') == 5 and out.count('CORTE 3a (sin cambiar)') == 2 and 'DISTINTA' not in out and 'FALTA' not in out)
GEN = os.path.join(C1A, 'carga', 'generado')
rc1, _, s1 = archivo('carga_inicial_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
rc2, _, s2 = archivo('publicar.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
q("insert into public.catastro_valledupar (cod_usuario, geom) select (7900000 + g)::text, ST_SetSRID(ST_MakePoint(-73.30 + random() * 0.10, 10.42 + random() * 0.08), 4326) from generate_series(1, 111950) g")
v85 = q("select st_y(geom) || '|' || st_x(geom) || '|' || codigo from redes.activo_vigente_mat where codigo_anterior = 'V85'").split('|')
SUBIR = lambda ruta: q(f"insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '{ruta}', '{{\"size\": 250000, \"mimetype\": \"image/jpeg\"}}')")  # noqa: E731
prep = q(f"select public.geoportal_redes_preparar_dano('{OPER}', 1)")
did, ruta = re.search(r'"dano_id": "([0-9a-f-]+)"', prep).group(1), re.search(r'"ruta": "([^"]+)"', prep).group(1); SUBIR(ruta)
d = q(f"""select public.geoportal_redes_crear_dano('{OPER}', '{did}', {lit('{"clase": "dano", "tipo": "fuga", "sistema": "acueducto", "activo": "%s", "lat": %s, "lon": %s, "ubicacion_origen": "gps", "t_detectado": "%s", "tipo_rotura": "parcial", "riesgo": "alto", "causa_clase": "desconocida", "fotos": [{"n": 1, "momento": "dano", "ruta": "%s"}]}' % (v85[2], v85[0], v85[1], ISO('-3 hours'), ruta))})""")
cod_dano = re.search(r'"codigo": "(DAN-\d+)"', d).group(1)
prep = q(f"select public.geoportal_redes_preparar_intervencion('{OPER}', 1, 0)")
iid, ruta = re.search(r'"intervencion_id": "([0-9a-f-]+)"', prep).group(1), re.search(r'"ruta": "([^"]+)"', prep).group(1); SUBIR(ruta)
r = q(f"""select public.geoportal_redes_crear_intervencion('{OPER}', '{iid}', {lit('{"nace_de": "dano", "dano": "%s", "resuelve_dano": true, "tipo": "reparacion", "sistema": "acueducto", "activo": "%s", "lat": %s, "lon": %s, "ubicacion_origen": "gps", "t_inicio": "%s", "t_fin": "%s", "descripcion": "Cambio del empaque", "ejecutor": "emdupar", "fuentes": [{"aportante": "emdupar"}], "archivos": [{"n": 1, "clase": "despues", "ruta": "%s"}]}' % (cod_dano, v85[2], v85[0], v85[1], ISO('-2 hours'), ISO('-1 hours'), ruta))})""")
cod_itv = (re.search(r'"codigo": "(ITV-\d+)"', r) or [None, ''])[1]
reg('02 carga real (35.781 activos), predios, y un daño y una reparación reales en V85 con fotos (Cortes 2 y 3a)', rc1 == 0 and rc2 == 0 and q('select count(*) from redes.activo_vigente_mat') == '35781'
    and cod_itv.startswith('ITV-'), f'publicar {s2:.1f} s, {cod_dano}, {cod_itv}')
rc, out, seg = archivo(ED('ensayo_en_transaccion_redes_corte3b_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('03 ensayo DESPUÉS de la carga real y con hechos reales: ERROR con «N de N … SIN FALLAS»', rc != 0 and m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS'),
    (m.group(0) if m else out[-800:]) + f' ({seg:.1f} s)')
reg('04 el ensayo no deja rastro (ni tablas, ni funciones, ni activos retirados, ni versiones nuevas)', q("select to_regclass('redes.ficha_ediciones') is null") == 't' and q(CONJ) == md5_3a
    and q('select count(*) from redes.activo_vigente_mat where retirado') == '0' and q('select count(*) from redes.activo_versiones where carga_id is null') == '0')
rc, out, seg = archivo(ED('migracion_redes_corte3b_editor.sql'))
reg('05 migración _editor', rc == 0, f'{seg:.1f} s' if rc == 0 else out[-400:])
rc, out, _ = archivo(ED('verificacion_redes_corte3b_editor.sql'))
reg('06 verificación sin ediciones: 10 OK', rc == 0 and out.count('| OK') == 10 and '| MAL' not in out)
rc, out, _ = archivo(ED('migracion_redes_corte3b_editor.sql'))
reg('07 repetir la migración se rechaza (guardia)', rc != 0 and 'deténgase' in out)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte3b_editor.sql'))
reg('08 huellas después: «CORTE 3b (aplicado)», 5 «NUEVA (aplicada)» y 2 «CORTE 3b (reemplazada)»', 'CORTE 3b (aplicado)' in out and out.count('NUEVA (aplicada)') == 5 and out.count('CORTE 3b (reemplazada)') == 2)
rc, out, _ = archivo(ED('reversa_redes_corte3b_editor.sql'))
reg('09 reversa sin ediciones: vuelve exactamente al 3a (funciones y epicrisis)', rc == 0 and q(CONJ) == md5_3a and q("select md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true))") == epi_3a, out[-300:] if rc else '')
rc, out, _ = archivo(os.path.join(C3A, 'verificacion_redes_corte3a_editor.sql'))
reg('10 tras la reversa, la verificación del 3a vuelve a dar 11 OK', out.count('| OK') == 11 and '| MAL' not in out)
rc, out, _ = archivo(ED('reversa_redes_corte3b_editor.sql'))
reg('11 una segunda reversa se niega', rc != 0 and 'No hay nada que revertir' in out)
rc, out, _ = archivo(ED('migracion_redes_corte3b_editor.sql'))
reg('12 volver a migrar después de la reversa', rc == 0)

t0 = time.time()
r = q(f"""select public.geoportal_redes_ficha_editar('{ADMIN}', 'V85', '{{"diametro_mm": 110, "estado_codigo": "en_operacion", "alias": "Válvula de la glorieta", "placa": "INV-2026-0085", "observaciones": "Revisada en campo"}}', 'Revisión de la válvula en campo')""")
seg = time.time() - t0
reg('13 editar la ficha real de V85 (por su código de la capa): versión 2, sin carga', '"version_nueva": true' in r and q(f"select version || '|' || coalesce(carga_id::text, 'ficha') || '|' || diametro_mm from redes.v_activo_vigente where codigo = '{v85[2]}'") == '2|ficha|110', r[:300])
reg('14 la tabla vigente sigue con 35.781 activos y la fila de V85 refrescada (sin recalcularla entera)', q('select count(*) from redes.activo_vigente_mat') == '35781'
    and q(f"select diametro_mm || '|' || version from redes.activo_vigente_mat where codigo = '{v85[2]}'") == '110|2')
reg('15 buscar por la placa y por el alias encuentra V85', v85[2] in q(f"select public.geoportal_redes_activo_buscar('{OPER}', 'inv-2026-0085')") and v85[2] in q(f"select public.geoportal_redes_activo_buscar('{OPER}', 'glorieta', 'acueducto')"))
g = q(f"select public.geoportal_redes_galeria('zt.super@emdupar.gov.co', '{v85[2]}')")
reg('16 galería de V85: la foto del daño y la de la reparación; la principal es la de «después»', '"total": 2' in g and '"origen": "dano"' in g and f'"codigo": "{cod_itv}"' in g and '"clase": "despues"' in g, g[:300])
ep = q(f"select public.geoportal_redes_epicrisis('{OPER}', '{v85[2]}')")
reg('17 la epicrisis de V85 trae el cambio de la ficha («Diámetro (mm): de … a «110»» y el motivo), el daño y la reparación', 'Diámetro (mm): de «' in ep and 'a «110»' in ep and 'Revisión de la válvula en campo' in ep
    and cod_itv in ep and cod_dano in ep, ep[:400])
reg('18 editar la ficha en la base real tarda menos de 1 s (con psql)', seg < 1, f'{seg:.2f} s')
rc, out, _ = archivo(ED('verificacion_redes_corte3b_editor.sql'))
reg('19 verificación con datos: 10 OK', out.count('| OK') == 10 and '| MAL' not in out)
rc, out, _ = archivo(ED('reversa_redes_corte3b_editor.sql'))
reg('20 la reversa se niega con datos (nada se borra)', rc != 0 and 'se niega' in out and q('select count(*) from redes.ficha_ediciones') == '1')

bien = sum(1 for _, ok, _ in res if ok)
lin = [f"{'OK   ' if ok else 'FALLA'} {n}{(' · ' + d) if d else ''}" for n, ok, d in res]
lin.append(f'RESULTADO: {bien} de {len(res)} — {"SIN FALLAS" if bien == len(res) else str(len(res) - bien) + " FALLA(S)"}')
os.makedirs(os.path.join(RAIZ, 'resultados'), exist_ok=True)
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write('\n'.join(lin) + '\n')
print(lin[-1])
sys.exit(0 if bien == len(res) else 1)
