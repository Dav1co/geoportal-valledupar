#!/usr/bin/env python3
"""Arnés local del Corte 4a (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Como en el despliegue (1a, carga real, Cortes 2, 3a y 3b publicados; las 4 funciones de permisos con su texto vivo del 14-nov): huellas antes · carga real y
hechos reales en V85 · ensayo (ERROR esperado y sin rastro) · migración · verificación · guardia · huellas después · reversa vacía (exacta al 3b y a las
4 funciones del 14-nov) · verificación del 3b · segunda reversa · migrar de nuevo · dar el permiso nuevo · sector y ocultar en la base real · tiempos ·
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
C3B = os.path.join(os.path.dirname(RAIZ), 'redes_corte3b')
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

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_3b'], env=ENV, check=True, capture_output=True)
md5_3b = q(CONJ)
VIV = "select string_agg(md5(pg_get_functiondef(oid)), ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('geoportal_puede', 'geoportal_mis_permisos', 'geoportal_admin_permisos', 'geoportal_admin_listar')"
viv_0 = q(VIV)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte4a_editor.sql'))
reg('01 huellas antes: «CORTE 3b (listo para el 4a)», las 4 de permisos «14-nov (sin cambiar)», 7 RPC «NO EXISTE» y 10 «CORTE 3b (sin cambiar)»', rc == 0
    and 'CORTE 3b (listo para el 4a)' in out and out.count('14-nov (sin cambiar)') == 4 and out.count('NO EXISTE (sin aplicar)') == 9 and out.count('CORTE 3b (sin cambiar)') == 10 and 'DISTINTA' not in out)
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
rc, out, seg = archivo(ED('ensayo_en_transaccion_redes_corte4a_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('03 ensayo DESPUÉS de la carga real y con hechos reales: ERROR con «N de N … SIN FALLAS»', rc != 0 and m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS'),
    (m.group(0) if m else out[-800:]) + f' ({seg:.1f} s)')
reg('04 el ensayo no deja rastro (ni columnas, ni funciones, ni las de permisos cambiadas)', q("select count(*) from information_schema.columns where column_name in ('ver_dashboard_redes', 'sector_num')") == '0'
    and q(CONJ) == md5_3b and q(VIV) == viv_0)
rc, out, seg = archivo(ED('migracion_redes_corte4a_editor.sql'))
reg('05 migración _editor', rc == 0, f'{seg:.1f} s' if rc == 0 else out[-400:])
rc, out, _ = archivo(ED('verificacion_redes_corte4a_editor.sql'))
reg('06 verificación: 8 OK', rc == 0 and out.count('| OK') == 8 and '| MAL' not in out)
rc, out, _ = archivo(ED('migracion_redes_corte4a_editor.sql'))
reg('07 repetir la migración se rechaza (guardia)', rc != 0 and 'deténgase' in out)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte4a_editor.sql'))
reg('08 huellas después: «CORTE 4a (aplicado)», 4 «con dashboard_redes», 7 «NUEVA» y 10 «reemplazada»', 'CORTE 4a (aplicado)' in out and out.count('CORTE 4a (con dashboard_redes)') == 4
    and out.count('NUEVA (aplicada)') == 7 and out.count('CORTE 4a (reemplazada)') == 10)
rc, out, _ = archivo(ED('reversa_redes_corte4a_editor.sql'))
reg('09 reversa sin datos: vuelve exactamente al 3b y a las 4 funciones de permisos del 14-nov', rc == 0 and q(CONJ) == md5_3b and q(VIV) == viv_0, out[-300:] if rc else '')
rc, out, _ = archivo(os.path.join(C3B, 'verificacion_redes_corte3b_editor.sql'))
reg('10 tras la reversa, la verificación del 3b vuelve a dar 10 OK', out.count('| OK') == 10 and '| MAL' not in out)
rc, out, _ = archivo(ED('reversa_redes_corte4a_editor.sql'))
reg('11 una segunda reversa se niega', rc != 0 and 'No hay nada que revertir' in out)
rc, out, _ = archivo(ED('migracion_redes_corte4a_editor.sql'))
reg('12 volver a migrar después de la reversa', rc == 0)

SUP = 'zt.super@emdupar.gov.co'
q(f"select public.geoportal_admin_permisos('zt.admin@emdupar.gov.co', '{SUP}', false, false, false, false, 'sin_restriccion', 'todos', false, null, false, null, null, null, null, null, null, null, null, true)")
reg('13 el administrador da ver_dashboard_redes a zt.super (y le quita el de planta): es supervisor de distribución', q(f"select public.geoportal_redes_mi_perfil('{SUP}') ->> 'perfil'") == 'supervisor'
    and q(f"select ver_dashboard_redes and not ver_dashboard_tecnico from public.geoportal_lista_blanca where email = '{SUP}'") == 't')
t0 = time.time()
lista = q(f"select public.geoportal_redes_danos('{SUP}', 'abiertos', 300)")
seg = time.time() - t0
reg('14 la lista de daños abiertos trae el daño real (atendido no; el reabierto sí)', cod_dano not in lista or '"estado": "atendido"' not in lista, f'{seg:.2f} s')
r = q(f"select public.geoportal_redes_dano_evento('{SUP}', '{cod_dano}', 'reabrir', 'Volvió a salir agua en el mismo punto')")
reg('15 reabrir el daño real atendido: «en atención»', '"estado": "en_atencion"' in r, r[:200])
r = q(f"select public.geoportal_redes_intervencion_evento('{SUP}', '{cod_itv}', 'ocultar', 'Intervención de prueba (dato de prueba)')")
reg('16 ocultar la intervención real de prueba: «oculta» y fuera de la epicrisis de V85', '"estado": "oculta"' in r and cod_itv not in q(f"select public.geoportal_redes_epicrisis('{OPER}', '{v85[2]}')"))
reg('17 la ficha de V85 la edita el supervisor de distribución (alias), y el origen no', '"version_nueva": false' in q(f"""select public.geoportal_redes_ficha_editar('{SUP}', 'V85', '{{"alias": "Válvula de la glorieta"}}', 'Alias del supervisor de distribución')""")
    and 'solo lo corrige el administrador' in q(f"""select public.geoportal_redes_ficha_editar('{SUP}', 'V85', '{{"origen": {{"origen": "tercero", "aportante": "alcaldia"}}}}', 'Corrección del origen')"""))
reg('18 la lista de daños en la base real tarda menos de 1 s', seg < 1, f'{seg:.2f} s')
rc, out, _ = archivo(ED('verificacion_redes_corte4a_editor.sql'))
reg('19 verificación con datos: 8 OK y 1 supervisor de distribución', out.count('| OK') == 8 and '| MAL' not in out)
rc, out, _ = archivo(ED('reversa_redes_corte4a_editor.sql'))
reg('20 la reversa se niega con un supervisor de distribución asignado (nada se borra)', rc != 0 and 'se niega' in out)

bien = sum(1 for _, ok, _ in res if ok)
lin = [f"{'OK   ' if ok else 'FALLA'} {n}{(' · ' + d) if d else ''}" for n, ok, d in res]
lin.append(f'RESULTADO: {bien} de {len(res)} — {"SIN FALLAS" if bien == len(res) else str(len(res) - bien) + " FALLA(S)"}')
os.makedirs(os.path.join(RAIZ, 'resultados'), exist_ok=True)
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write('\n'.join(lin) + '\n')
print(lin[-1])
sys.exit(0 if bien == len(res) else 1)
