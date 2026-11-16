#!/usr/bin/env python3
"""Arnés local del Corte 5a (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Como en el despliegue (1a con la carga real, Cortes 2, 3a, 3b, 4a y 4b; tecnica.puntos con los 27 puntos de muestreo, como en la base viva):
huellas antes · carga real · ensayo (ERROR esperado y sin rastro) · migración · verificación · guardia · huellas después · reversa vacía (exacta al 4b) ·
verificación del 4b · segunda reversa · migrar de nuevo · la PRIMERA CARGA MUE real (27 puntos: 3 verificados y 24 por barrio) con su maestro de psql ·
una RECARGA COMPLETA del acueducto real con una ficha editada (gana la ficha, choques, tiempos) y con un nodo J clasificado en la bandeja ·
el supervisor asigna un formulario · verificación con datos · reversa con datos (rechazo).
Uso: python3 -I correr_local.py   → escribe ../resultados/sql_local.txt
"""
import os
import re
import subprocess
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
C1A = os.environ.get('C1A', os.path.expanduser('~/geoportal-emdupar-tec-c1a/sql/redes_corte1a'))
C4B = os.path.join(os.path.dirname(RAIZ), 'redes_corte4b')
MUE = os.path.join(RAIZ, 'carga_mue', 'generado')
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
ADMIN = 'carga.local@emdupar.gov.co'
SUP = 'zt.dist@emdupar.gov.co'
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
PUNTOS = "select count(*) || '|' || count(*) filter (where activo) from tecnica.puntos"

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_4b'], env=ENV, check=True, capture_output=True)
md5_4b = q(CONJ)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte5a_editor.sql'))
reg('01 huellas antes: «CORTE 4b (listo para el 5a)», 4 de permisos «CORTE 4a (sin cambiar)», la RPC y las 3 tablas «NO EXISTE», 9 «CORTE 4b (sin cambiar)»', rc == 0
    and 'CORTE 4b (listo para el 5a)' in out and out.count('CORTE 4a (sin cambiar)') == 4 and out.count('NO EXISTE (sin aplicar)') == 4
    and out.count('CORTE 4b (sin cambiar)') == 9 and 'DISTINTA' not in out)
GEN = os.path.join(C1A, 'carga', 'generado')
rc1, _, s1 = archivo('carga_inicial_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
rc2, _, s2 = archivo('publicar.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
reg('02 carga real (35.781 activos) y los 27 puntos de muestreo sin ubicación, como en la base viva', rc1 == 0 and rc2 == 0 and q('select count(*) from redes.activo_vigente_mat') == '35781'
    and q("select count(*) from tecnica.puntos where tipo = 'muestreo' and activo") == '27', f'publicar {s2:.1f} s')
puntos0 = q(PUNTOS)
rc, out, seg = archivo(ED('ensayo_en_transaccion_redes_corte5a_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('03 ensayo DESPUÉS de la carga real: ERROR con «N de N … SIN FALLAS»', rc != 0 and m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS'),
    (m.group(0) if m else out[-800:]) + f' ({seg:.1f} s)')
reg('04 el ensayo no deja rastro (ni tablas, ni funciones, ni puntos, ni cargas)', q("select to_regclass('tecnica.puntos_ubicacion') is null and to_regclass('redes.formularios_distribucion') is null") == 't'
    and q(CONJ) == md5_4b and q(PUNTOS) == puntos0 and q("select count(*) from redes.cargas") == '4')
rc, out, seg = archivo(ED('migracion_redes_corte5a_editor.sql'))
reg('05 migración _editor', rc == 0, f'{seg:.1f} s' if rc == 0 else out[-400:])
rc, out, _ = archivo(ED('verificacion_redes_corte5a_editor.sql'))
reg('06 verificación: 9 OK', rc == 0 and out.count('| OK') == 9 and '| MAL' not in out, '' if rc == 0 else out[-300:])
rc, out, _ = archivo(ED('migracion_redes_corte5a_editor.sql'))
reg('07 repetir la migración se rechaza (guardia)', rc != 0 and 'deténgase' in out)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte5a_editor.sql'))
reg('08 huellas después: «CORTE 5a (aplicado)», la RPC «NUEVA», 9 «CORTE 5a (reemplazada)» y 3 «EXISTE»', 'CORTE 5a (aplicado)' in out and out.count('NUEVA (aplicada)') == 1
    and out.count('CORTE 5a (reemplazada)') == 9 and out.count('EXISTE (aplicado)') == 3)
rc, out, _ = archivo(ED('reversa_redes_corte5a_editor.sql'))
reg('09 reversa sin datos: vuelve exactamente al 4b (la capa queda inactiva)', rc == 0 and q(CONJ) == md5_4b and q("select activa from redes.capas where codigo = 'muestreo'") == 'f', out[-300:] if rc else '')
rc, out, _ = archivo(os.path.join(C4B, 'verificacion_redes_corte4b_editor.sql'))
reg('10 tras la reversa, la verificación del 4b vuelve a dar 9 OK', out.count('| OK') == 9 and '| MAL' not in out)
rc, out, _ = archivo(ED('reversa_redes_corte5a_editor.sql'))
reg('11 una segunda reversa se niega', rc != 0 and 'No hay nada que revertir' in out)
rc, out, _ = archivo(ED('migracion_redes_corte5a_editor.sql'))
reg('12 volver a migrar después de la reversa (la capa vuelve a quedar activa)', rc == 0 and q("select activa from redes.capas where codigo = 'muestreo'") == 't', out[-300:] if rc else '')

# ---------- la primera carga MUE, con el maestro de psql que correrá David ----------
rc, out, seg = archivo('carga_mue_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=MUE)
reg('13 carga_mue_todo.sql: un solo comando; el resumen dice «lista para publicar: SÍ», 27 «ubicacion» y ninguno se desactiva', rc == 0
    and re.search(r'lista para publicar\s*\|\s*SÍ', out) is not None and re.search(r'\|\s*ubicacion\s*\|\s*27', out) is not None and re.search(r'desactivar \(no vienen\)\s*\|\s*0', out) is not None,
    f'{seg:.1f} s' if rc == 0 else out[-500:])
rc, out, seg = archivo('publicar_mue.sql', ['-v', f'solicitante={ADMIN}'], cwd=MUE)
reg('14 publicar_mue.sql: 27 ubicaciones (3 verificadas y 24 aproximadas), ningún punto nuevo ni desactivado; tecnica.puntos con las mismas filas',
    rc == 0 and q("select count(*) || '|' || count(*) filter (where exactitud = 'verificada') from redes.v_punto_ubicacion_vigente") == '27|3'
    and q(PUNTOS) == puntos0 and q("select count(*) from tecnica.punto_eventos") == '0', f'{seg:.1f} s' if rc == 0 else out[-500:])
reg('15 MUE-24 San Joaquín en la ubicación que dio David y MUE-02 en el barrio Villalba',
    q("select u.lat || '|' || u.lon || '|' || u.fuente from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-24'") == '10.480670|-73.257440|david'
    and q("select u.barrio_capa || '|' || u.exactitud from redes.v_punto_ubicacion_vigente u join tecnica.puntos p on p.id = u.punto_id where p.codigo = 'MUE-02'") == 'VILLALBA|aproximada')
rc, out, _ = archivo('carga_mue_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=MUE)
reg('16 volver a correr el mismo archivo se niega («ya se publicó»)', rc != 0 and 'ya se publicó' in out)

# ---------- recarga completa del acueducto real: gana la ficha, choques y la bandeja de nodos ----------
v85 = q("select codigo from redes.activo_vigente_mat where codigo_anterior = 'V85'")
q(f"""select public.geoportal_redes_ficha_editar('{ADMIN}', '{v85}', '{{"nombre": "Válvula de la glorieta", "fecha_instalacion": "2019-03-01"}}', 'Dato de la cuadrilla de redes')""")
nodo = q("select nodo_id || '|' || nombre_modelo from redes.v_nodo_vigente where clase_nodo = 'por_clasificar' and nombre_modelo like 'J-%' order by nodo_id limit 1").split('|')
acc = (re.search(r'"activo": "(ACC-\d+)"', q(f"select public.geoportal_redes_nodo_crear_activo('{ADMIN}', {nodo[0]}, 'ACC', 'union', null, 'Técnica confirmó que esta J es una unión')")) or [None, ''])[1]
import tempfile
maestro = os.path.join(tempfile.mkdtemp(prefix='recarga_5a_'), 'recarga_acueducto.sql')      # fuera de los repositorios
lotes = sorted(f for f in os.listdir(os.path.join(GEN, 'lotes')) if f.startswith('acueducto_'))
n_acu = int(q("select filas_esperadas from redes.cargas where capa_codigo = 'acueducto' order by id limit 1"))
open(maestro, 'w', encoding='utf-8').write(
    "\\set ON_ERROR_STOP 1\n\\set QUIET 1\n"
    f"select (public.geoportal_redes_carga_iniciar(:'solicitante', 'acueducto', '{'5a' * 32}', 'shp', 4326, 'ID', {n_acu}, 'Recarga de prueba del Corte 5a') ->> 'carga_id') as carga_acueducto \\gset\n"
    "\\o /dev/null\n" + ''.join(f'\\ir {os.path.join(GEN, "lotes", f)}\n' for f in lotes) + "\\o\n")
rc, out, seg_l = archivo(maestro, ['-v', f'solicitante={ADMIN}'])
os.remove(maestro)
carga = q("select id from redes.v_cargas_estado where capa_codigo = 'acueducto' and estado = 'abierta'")
t0 = time.time(); r = q(f"select public.geoportal_redes_carga_resumen('{ADMIN}', {carga})"); seg_r = time.time() - t0
import json
rj = json.loads(r) if r.startswith('{') else {}
reg('17 recarga real del acueducto (10.578 tramos): sin choques (el modelo no trae nombre para V85: gana la ficha sin aviso), el nodo de la bandeja contado y nada cambia',
    rc == 0 and rj.get('choques') == [] and rj['detalle'].get('nodos_clasificados_en_la_bandeja') == 1 and rj['detalle'].get('choques_con_la_ficha') == 0
    and rj['frente_a_vigente'] == {'igual': int(q("select count(*) from redes.v_activo_vigente where capa_codigo in ('acueducto', 'acueducto_nodos') and not retirado"))}
    and rj['lista_para_publicar'], f'lotes {seg_l:.1f} s, resumen {seg_r:.1f} s · ' + json.dumps(rj.get('choques'), ensure_ascii=False)[:200] + ' · ' + json.dumps(rj.get('frente_a_vigente')))
t0 = time.time(); r = q(f"select public.geoportal_redes_carga_publicar('{ADMIN}', {carga}, 'Recarga de prueba del Corte 5a')"); seg_p = time.time() - t0
reg('18 publicar la recarga: V85 conserva su nombre y su fecha de la ficha, el accesorio de la bandeja sigue enlazado y no se retira nada',
    '"retirados": 0' in r and '"cambiados": 0' in r
    and q(f"select nombre || '|' || fecha_instalacion from redes.v_activo_vigente where codigo = '{v85}'") == 'Válvula de la glorieta|2019-03-01'
    and q(f"select clase_nodo || '|' || (activo_id = (select id from redes.activos where codigo = '{acc}')) from redes.v_nodo_vigente where nodo_id = {nodo[0]}") == 'activo|true'
    and q(f"select retirado from redes.v_activo_vigente where codigo = '{acc}'") == 'f', f'publicar {seg_p:.1f} s · ' + r[:200])

# ---------- §28.2 con la base real ----------
r = q(f"select public.geoportal_redes_personal_formulario('{SUP}', 'zt.oper.sinform@emdupar.gov.co', 'mantenimiento', true, 'Empieza a registrar intervenciones')")
reg('19 el supervisor de distribución asigna «Registrar intervención» a un operador real', '"asignado": true' in r and q("select tecnica.f_formulario_asignado('zt.oper.sinform@emdupar.gov.co', 'mantenimiento')") == 't', r[:200])
rc, out, _ = archivo(ED('verificacion_redes_corte5a_editor.sql'))
reg('20 verificación con datos: 9 OK (27 puntos con ubicación: 3 verificadas y 24 aproximadas)', out.count('| OK') == 9 and '| MAL' not in out and '27 · 27 (3 · 24)' in out)
rc, out, _ = archivo(ED('reversa_redes_corte5a_editor.sql'))
reg('21 la reversa se niega con la carga MUE publicada (nada se borra)', rc != 0 and 'se niega' in out)

bien = sum(1 for _, ok, _ in res if ok)
lin = [f"{'OK   ' if ok else 'FALLA'} {n}{(' · ' + d) if d else ''}" for n, ok, d in res]
lin.append(f'RESULTADO: {bien} de {len(res)} — {"SIN FALLAS" if bien == len(res) else str(len(res) - bien) + " FALLA(S)"}')
os.makedirs(os.path.join(RAIZ, 'resultados'), exist_ok=True)
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write('\n'.join(lin) + '\n')
print(lin[-1])
sys.exit(0 if bien == len(res) else 1)
