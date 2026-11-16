#!/usr/bin/env python3
"""Arnés local del Corte 3a (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Encadena, como en el despliegue (1a, carga real y Corte 2 ya publicados), con los _editor del 3a y los shapefiles REALES:
  huellas antes · carga real, predios y un daño real en V85 · ensayo (ERROR esperado y sin rastro) · migración · verificación ·
  migración repetida · huellas después · reversa vacía (vuelve exacto al Corte 2) · verificación del Corte 2 · segunda reversa · migrar de nuevo ·
  una reparación real que atiende el daño de V85 · una inversión que crea un tramo real · tesela y búsqueda con el tramo nuevo · tiempos ·
  verificación con datos · reversa con datos (rechazo).
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
C2 = os.path.join(os.path.dirname(RAIZ), 'redes_corte2')
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
subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_2'], env=ENV, check=True, capture_output=True)
md5_2, vistas_2 = q(CONJ), q(VISTAS)

rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte3a_editor.sql'))
reg('01 huellas antes: «CORTE 2 (listo para el 3a)», 8 RPC «NO EXISTE», 2 RPC y 2 vistas «CORTE 2 (sin cambiar)», bucket y 5 dependencias «EXISTE»',
    rc == 0 and 'CORTE 2 (listo para el 3a)' in out and out.count('NO EXISTE (sin aplicar)') == 8 and out.count('CORTE 2 (sin cambiar)') == 4
    and out.count('| EXISTE') == 6 and 'FALTA' not in out and 'DISTINTA' not in out)

# Como en Supabase: la carga real ya está publicada, hay predios (33 a menos de 30 m de la red de prueba) y hay daños reales (uno en V85).
GEN = os.path.join(C1A, 'carga', 'generado')
rc1, _, s1 = archivo('carga_inicial_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
rc2, _, s2 = archivo('publicar.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
q("insert into public.catastro_valledupar (cod_usuario, geom) select (7800000 + g)::text, ST_SetSRID(ST_MakePoint(-73.2400 + (3 * g) * 0.0000091, 10.4700 + (case when g % 2 = 0 then 8 else -8 end) * 0.0000090), 4326) from generate_series(1, 33) g")
q("insert into public.catastro_valledupar (cod_usuario, geom) select (7900000 + g)::text, ST_SetSRID(ST_MakePoint(-73.30 + random() * 0.10, 10.42 + random() * 0.08), 4326) from generate_series(1, 111950) g")
v85 = q("select st_y(geom) || '|' || st_x(geom) || '|' || codigo from redes.activo_vigente_mat where codigo_anterior = 'V85'").split('|')


def dano_real(quien, extra=''):
    prep = q(f"select public.geoportal_redes_preparar_dano('{quien}', 1)")
    did = re.search(r'"dano_id": "([0-9a-f-]+)"', prep).group(1)
    ruta = re.search(r'"ruta": "([^"]+)"', prep).group(1)
    q(f"insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '{ruta}', '{{\"size\": 250000, \"mimetype\": \"image/jpeg\"}}')")
    datos = ('{"clase": "dano", "tipo": "fuga", "sistema": "acueducto", "activo": "%s", "lat": %s, "lon": %s, "ubicacion_origen": "gps", "t_detectado": "%s", '
             '"tipo_rotura": "parcial", "riesgo": "alto", "causa_clase": "desconocida", "fotos": [{"n": 1, "momento": "dano", "ruta": "%s"}]%s}') % (v85[2], v85[0], v85[1], ISO('-3 hours'), ruta, extra)
    return q(f"select public.geoportal_redes_crear_dano('{quien}', '{did}', {lit(datos)})")


d_real = dano_real(OPER)
cod_dano = (re.search(r'"codigo": "(DAN-\d+)"', d_real) or [None, ''])[1]
reg('02 carga real publicada (35.781 activos), 111.983 predios y un daño real en V85 con el Corte 2 (el operador lo reporta)',
    rc1 == 0 and rc2 == 0 and q('select count(*) from redes.activo_vigente_mat') == '35781' and cod_dano.startswith('DAN-'), f'maestro {s1:.1f} s, publicar {s2:.1f} s, {cod_dano}')

rc, out, seg = archivo(ED('ensayo_en_transaccion_redes_corte3a_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('03 ensayo DESPUÉS de la carga real y con daños reales: ERROR con «N de N … SIN FALLAS»', rc != 0 and m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS'),
    (m.group(0) if m else out[-800:]) + f' ({seg:.1f} s)')
reg('04 el ensayo no deja rastro (ni tablas, ni funciones, ni activos retirados, ni el daño real tocado)', q("select to_regclass('redes.intervenciones') is null") == 't' and q(CONJ) == md5_2
    and q('select count(*) from redes.activo_vigente_mat where retirado') == '0' and q(f"select estado from redes.v_dano where codigo = '{cod_dano}'") == 'reportado')
rc, out, seg = archivo(ED('migracion_redes_corte3a_editor.sql'))
reg('05 migración _editor', rc == 0, f'{seg:.1f} s' if rc == 0 else out[-400:])
rc, out, _ = archivo(ED('verificacion_redes_corte3a_editor.sql'))
reg('06 verificación sin intervenciones: 11 OK', rc == 0 and out.count('| OK') == 11 and '| MAL' not in out)
rc, out, _ = archivo(ED('migracion_redes_corte3a_editor.sql'))
reg('07 repetir la migración se rechaza (guardia)', rc != 0 and 'deténgase' in out)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte3a_editor.sql'))
reg('08 huellas después: «CORTE 3a (aplicado)», 8 «NUEVA (aplicada)» y 4 «CORTE 3a (reemplazada)»', 'CORTE 3a (aplicado)' in out and out.count('NUEVA (aplicada)') == 8
    and out.count('CORTE 3a (reemplazada)') == 4)
reg('09 el daño real del Corte 2 se sigue viendo igual (v_dano reemplazada)', q(f"select estado || '|' || activo_codigo from redes.v_dano where codigo = '{cod_dano}'") == f'reportado|{v85[2]}')
rc, out, _ = archivo(ED('reversa_redes_corte3a_editor.sql'))
reg('10 reversa sin intervenciones: vuelve exactamente al Corte 2 (funciones y vistas)', rc == 0 and q(CONJ) == md5_2 and q(VISTAS) == vistas_2
    and q("select to_regclass('redes.intervenciones') is null") == 't', out[-400:] if rc else '')
rc, out, _ = archivo(os.path.join(C2, 'verificacion_redes_corte2_editor.sql'))
reg('11 tras la reversa, la verificación del Corte 2 vuelve a dar 11 OK', out.count('| OK') == 11 and '| MAL' not in out)
rc, out, _ = archivo(ED('reversa_redes_corte3a_editor.sql'))
reg('12 una segunda reversa se niega', rc != 0 and 'No hay nada que revertir' in out)
rc, out, _ = archivo(ED('migracion_redes_corte3a_editor.sql'))
reg('13 volver a migrar después de la reversa', rc == 0)

# una reparación real que atiende el daño de V85 (foto en el Storage local)
t0 = time.time()
prep = q(f"select public.geoportal_redes_preparar_intervencion('{OPER}', 2, 0)")
iid = re.search(r'"intervencion_id": "([0-9a-f-]+)"', prep).group(1)
rutas = re.findall(r'"ruta": "([^"]+)"', prep)
for r_ in rutas:
    q(f"insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '{r_}', '{{\"size\": 280000, \"mimetype\": \"image/jpeg\"}}')")
abiertos = q(f"select public.geoportal_redes_danos_abiertos('{OPER}', 'acueducto', '{v85[2]}')")
reg('14 «daños abiertos» de V85 trae el daño real, como del mismo activo', f'"codigo": "{cod_dano}"' in abiertos and '"mismo_activo": true' in abiertos)
datos = ('{"nace_de": "dano", "dano": "%s", "tipo": "reparacion", "sistema": "acueducto", "activo": "%s", "lat": %s, "lon": %s, "ubicacion_origen": "gps", '
         '"t_inicio": "%s", "t_fin": "%s", "descripcion": "Cambio del empaque de la válvula", "ejecutor": "emdupar", "fuentes": [{"aportante": "emdupar"}], '
         '"materiales": [{"material": "Empaque 4 pulg", "cantidad": 1, "unidad": "und"}], '
         '"archivos": [{"n": 1, "clase": "antes", "ruta": "%s"}, {"n": 2, "clase": "despues", "ruta": "%s"}]}') % (cod_dano, v85[2], v85[0], v85[1], ISO('-2 hours'), ISO('-30 minutes'), rutas[0], rutas[1])
r = q(f"select public.geoportal_redes_crear_intervencion('{OPER}', '{iid}', {lit(datos)})")
seg_itv = time.time() - t0
cod_itv = (re.search(r'"codigo": "(ITV-\d+)"', r) or [None, ''])[1]
reg('15 una reparación real sobre V85 que atiende su daño: ITV-000001, cerrada, y el daño atendido', cod_itv == 'ITV-000001' and '"dano_estado": "atendido"' in r, r[:300])
ep = q(f"select public.geoportal_redes_epicrisis('{ADMIN}', '{v85[2]}')")
fi = q(f"select public.geoportal_redes_activo('{OPER}', '{v85[2]}') -> 'epicrisis'")
reg('16 la epicrisis de V85 trae la reparación y el daño atendido; la ficha cuenta 2 hechos', f'{cod_itv} · Reparación · atiende {cod_dano}' in ep and '"estado": "Atendido"' in ep and '"hechos": 2' in fi, fi)

# una inversión real: tramo nuevo de 2 puntos al lado de V85
lat, lon = float(v85[0]), float(v85[1])
prep = q(f"select public.geoportal_redes_preparar_intervencion('{OPER}', 1, 0)")
iid = re.search(r'"intervencion_id": "([0-9a-f-]+)"', prep).group(1)
ruta = re.search(r'"ruta": "([^"]+)"', prep).group(1)
q(f"insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '{ruta}', '{{\"size\": 280000, \"mimetype\": \"image/jpeg\"}}')")
datos = ('{"nace_de": "programada", "tipo": "inversion", "inversion_modo": "nuevo", "sistema": "acueducto", "lat": %.6f, "lon": %.6f, "ubicacion_origen": "mapa", '
         '"nuevo": {"prefijo": "RED", "material": "PVC", "diametro_mm": 76, "puntos": [[%.6f, %.6f], [%.6f, %.6f]]}, "t_inicio": "%s", "t_fin": "%s", '
         '"descripcion": "Extensión de red nueva para el barrio", "ejecutor": "contratista", "contratista_nombre": "Obras de prueba", '
         '"fuentes": [{"aportante": "alcaldia"}], "archivos": [{"n": 1, "clase": "despues", "ruta": "%s"}]}') % (
    lat + 0.0002, lon + 0.0002, lat + 0.0001, lon + 0.0001, lat + 0.0003, lon + 0.0004, ISO('-5 hours'), ISO('-1 hours'), ruta)
r = q(f"select public.geoportal_redes_crear_intervencion('{OPER}', '{iid}', {lit(datos)})")
nuevo = (re.search(r'"activo": "(RED-\d+)"', r) or [None, ''])[1]
reg('17 la inversión crea un tramo RED-010574 (el siguiente después de los 10.573 cargados), por verificar y de origen tercero', nuevo == 'RED-010574'
    and q(f"select por_verificar from redes.v_activo_vigente where codigo = '{nuevo}'") == 't'
    and q(f"select o.origen from redes.v_activo_origen_vigente o join redes.activos a on a.id = o.activo_id where a.codigo = '{nuevo}'") == 'tercero', r[:300])


def tesela(z, lon_, lat_):
    n = 1 << z
    return z, int((lon_ + 180) / 360 * n), int((1 - math.log(math.tan(math.radians(lat_)) + 1 / math.cos(math.radians(lat_))) / math.pi) / 2 * n)


z, x, y = tesela(17, lon + 0.0002, lat + 0.0002)
crudo = base64.b64decode(q(f"select public.geoportal_redes_mvt('{OPER}', {z}, {x}, {y}, 'acueducto')"))
reg('18 el tramo nuevo sale en la tesela del minimapa, en la búsqueda y en la tabla vigente (sin recalcularla entera)', nuevo.encode() in crudo
    and nuevo in q(f"select public.geoportal_redes_activo_buscar('{OPER}', '{nuevo}', 'acueducto')") and q('select count(*) from redes.activo_vigente_mat') == '35782')
reg('19 registrar una intervención en la base real tarda menos de 2 s (con psql)', seg_itv < 2, f'{seg_itv:.2f} s (preparar, daños abiertos y crear)')
rc, out, _ = archivo(ED('verificacion_redes_corte3a_editor.sql'))
reg('20 verificación con datos: 11 OK', out.count('| OK') == 11 and '| MAL' not in out and 'inversion 1' in out and 'reparacion 1' in out)
rc, out, _ = archivo(ED('reversa_redes_corte3a_editor.sql'))
reg('21 la reversa se niega con datos (nada se borra)', rc != 0 and 'se niega' in out and q('select count(*) from redes.intervenciones') == '2')

bien = sum(1 for _, ok, _ in res if ok)
lin = [f"{'OK   ' if ok else 'FALLA'} {n}{(' · ' + d) if d else ''}" for n, ok, d in res]
lin.append(f'RESULTADO: {bien} de {len(res)} — {"SIN FALLAS" if bien == len(res) else str(len(res) - bien) + " FALLA(S)"}')
os.makedirs(os.path.join(RAIZ, 'resultados'), exist_ok=True)
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write('\n'.join(lin) + '\n')
print(lin[-1])
sys.exit(0 if bien == len(res) else 1)
