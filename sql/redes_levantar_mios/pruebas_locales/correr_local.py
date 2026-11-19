#!/usr/bin/env python3
"""Arnés local de «Mis reportes» (ruta levantar_mios; Code A, localhost:55432, base redes_local = producción al 19-nov, huella ef756488…,
con los CHECK, llaves y disparadores de sus migraciones):
  · el ensayo (N de N … SIN FALLAS) y que no deja nada; huellas; migración; verificación; segunda migración; reversa (vuelve la huella anterior);
  · que SOLO AGREGA: ninguna función anterior cambia de texto;
  · como la ve producción (service_role, 30 s / 8 s): un operador sintético reporta, lee los suyos y no ve los ajenos. Tope local de la lectura: 1 s / 6.
La ruta de punta a punta (Edge real en Deno) va aparte: scripts/prueba_edge_levantar_mios.mjs.
Uso: python3 -I correr_local.py"""
import json
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = 'redes_local'
NOMBRE = 'redes_levantar_mios'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_ANTES = 'ef7564883f523685cfe36478e0985e98'
VIEJAS = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) from pg_proc p "
          "where (p.pronamespace in ('redes'::regnamespace, 'tecnica'::regnamespace) or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_%')) "
          "and p.prokind = 'f' and p.proname <> 'geoportal_redes_levantar_mios'")
ADM, SD, OP, OP2, NA = 'ztm.arnes.adm@emdupar.gov.co', 'ztm.arnes.sd@emdupar.gov.co', 'ztm.arnes.op@emdupar.gov.co', 'ztm.arnes.op2@emdupar.gov.co', 'ztm.arnes.nada@emdupar.gov.co'
T1 = 1000 / 6
res = []


def ok(nombre, cond, det=''):
    res.append((nombre, bool(cond), str(det)[:500]))
    print(('OK    ' if cond else 'FALLA ') + nombre + ('' if cond else ' → ' + str(det)[:500]), flush=True)


def psql(*args, check=False):
    return subprocess.run([PSQL, '-d', BASE, '-X', *args], env=ENV, capture_output=True, text=True, check=check)


def q(sql):
    return psql('-At', '-c', sql, check=True).stdout.strip()


def rehacer(con=''):
    subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')] + ([con] if con else []), env=ENV, check=True, capture_output=True)


def edge(sql):
    """Como la llama la Edge: rol de la API y los topes de producción."""
    t0 = time.time()
    p = psql('-Atq', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'", '-c', sql)
    return round((time.time() - t0) * 1000), p.stdout.strip(), (p.stderr.strip() if p.returncode else '')


def lit(o):
    return "'" + json.dumps(o, ensure_ascii=False).replace("'", "''") + "'::jsonb"


def archivo(n):
    return os.path.join(RAIZ, n)


rehacer()
viejas0, aud0 = q(VIEJAS), q('select count(*) from public.geoportal_auditoria')
p = psql('-q', '-f', archivo(f'ensayo_en_transaccion_{NOMBRE}_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — SIN FALLAS', p.stderr)
ok(f'01 el ensayo termina en el ERROR esperado: {m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS', m and m.group(1) == m.group(2) and 'esperado' in p.stderr, p.stderr[-1500:])
for linea in re.findall(r'TIEMPOS[^\n]*', p.stderr):
    print('   ' + linea)
ok('02 … y no deja nada (sigue la huella anterior, no están la función ni el índice, ni un punto ni una fila de auditoría)',
   q(CONJ) == MD5_ANTES and q("select to_regprocedure('public.geoportal_redes_levantar_mios(text,integer)')") == '' and q("select to_regclass('redes.ix_levantar_puntos_autor')") == '' and q('select count(*) from redes.levantar_puntos') == '0'
   and q('select count(*) from public.geoportal_auditoria') == aud0)
filas = psql('-AtF', '|', '-f', archivo(f'huellas_solo_lectura_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok('03 las huellas antes: «CORTE 15 (lista para Mis reportes)», la nueva y el índice no existen y las 5 que no se tocan son las publicadas', any('lista para Mis reportes' in f for f in filas)
   and sum('NO EXISTE (sin aplicar)' in f for f in filas) == 2 and sum('LA PUBLICADA' in f for f in filas) == 5 and not any('DISTINTA' in f or 'FALTA' in f for f in filas), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('04 la migración se aplica', p.returncode == 0, p.stderr)
ok('05 SOLO AGREGA: ninguna función anterior de redes, tecnica ni public.geoportal_* cambió de texto', q(VIEJAS) == viejas0)
filas = psql('-AtF', '|', '-f', archivo(f'huellas_solo_lectura_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok('06 las huellas después: «MIS REPORTES (aplicado)», 1 nueva, el índice y las 5 publicadas igual', any('MIS REPORTES (aplicado)' in f for f in filas) and sum('NUEVA (aplicada)' in f for f in filas) == 1 and sum('ESTÁ (aplicado)' in f for f in filas) == 1
   and sum('LA PUBLICADA' in f for f in filas) == 5, '\n'.join(filas))
filas = psql('-AtF', '|', '-f', archivo(f'verificacion_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok(f'07 la verificación: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('08 una segunda migración se niega', p.returncode != 0 and 'ya está aplicado' in p.stderr, p.stderr)
ok('09 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')

# ---------- como la ve producción: perfiles sintéticos que reportan y leen los suyos ----------
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{ADM}', 'ZTM arnés admin', 'admin', 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SD}', 'ZTM arnés supervisor', 'consulta', true, true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'ZTM arnés operador', 'consulta', true, 'sin_restriccion', 'todos'), "
  f"('{OP2}', 'ZTM arnés operador dos', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_comercial, horario, dias) values ('{NA}', 'ZTM arnés sin permiso', 'consulta', true, 'sin_restriccion', 'todos')")
for e_ in (OP, OP2):
    q(f"select public.geoportal_redes_personal_formulario('{SD}', '{e_}', 'activo_campo', true, 'ZTM sale a campo a levantar activos', '127.0.0.1')")


def reportar(quien, n):
    _, out, e = edge(f"select public.geoportal_redes_levantar_preparar('{quien}', 1)")
    prep = json.loads(out)
    q(f"insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '{prep['fotos'][0]['ruta']}', '{{\"size\": 200000, \"mimetype\": \"image/jpeg\"}}')")
    _, out, e = edge("select public.geoportal_redes_levantar_crear('%s', '%s', %s, '127.0.0.1')" % (quien, prep['punto_id'], lit(
        {'servicio': 'acueducto', 'tipo': 'valvula', 'lat': 10.139, 'lon': round(-73.58 + n * 0.001, 6), 'precision_m': 5, 'fotos': prep['fotos']})))
    return json.loads(out)['codigo'] if not e else e


l1, l2, o1 = reportar(OP, 1), reportar(OP, 2), reportar(OP2, 3)
ok(f'10 dos operadores reportan como la Edge: {l1}, {l2} y {o1}', all(c.startswith('LEV-') for c in (l1, l2, o1)), (l1, l2, o1))
ms, out, e = edge(f"select public.geoportal_redes_levantar_mios('{OP}', 30)")
j = json.loads(out) if not e else {}
ok(f'11 «Mis reportes» como la Edge ({ms} ms; tope local {T1:.0f} ms): los 2 suyos, el último primero, «Reportado», y no el ajeno',
   not e and ms < T1 and [i['codigo'] for i in j['items']] == [l2, l1] and j['total'] == 2 and j['recortada'] is False and j['dias'] == 30
   and all(i['estado_nombre'] == 'Reportado' and i['activo'] is None for i in j['items']) and '@' not in out and 'ZTM' not in out, e or out[:400])
_, out, e = edge(f"select public.geoportal_redes_levantar_evento('{SD}', '{l1}', 'descartado', null, 'ZTM arnés: repetido', '127.0.0.1')")
ms, out, e2 = edge(f"select public.geoportal_redes_levantar_mios('{OP}', 0)")
j = json.loads(out) if not e2 else {}
ok('12 el supervisor descarta uno (la RPC de siempre) y «Mis reportes» lo dice, sin el motivo', not e and not e2 and [i['estado'] for i in j['items']] == ['reportado', 'descartado'] and 'repetido' not in out, e or e2 or out[:300])
ok('13 quien no puede reportar no lee (42501); un periodo que no existe se rechaza (22023); la API no ejecuta las internas',
   '42501' in edge(f"select public.geoportal_redes_levantar_mios('{NA}', 30)")[2] and '22023' in edge(f"select public.geoportal_redes_levantar_mios('{OP}', 15)")[2]
   and '42501' in edge(f"select * from redes.f_levantar_acceso('{OP}')")[2])
aud = q('select count(*) from public.geoportal_auditoria')
peor = max(edge(f"select public.geoportal_redes_levantar_mios('{OP}', 0)")[0] for _ in range(10))
ok(f'14 diez lecturas seguidas como la Edge: la más lenta {peor} ms (tope local {T1:.0f} ms); leer no deja auditoría', peor < T1 and q('select count(*) from public.geoportal_auditoria') == aud)
plan = q(f"explain select x.id from redes.levantar_puntos x where x.autor = '{OP}' order by x.registrado_en desc, x.codigo desc limit 500")
ok('15 INFO el índice por autor existe y es válido (con 3 filas el planificador puede no usarlo)', q("select indisvalid from pg_index where indexrelid = 'redes.ix_levantar_puntos_autor'::regclass") == 't', plan)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'reversa_{NOMBRE}_editor.sql'))
ok('16 la reversa se aplica: vuelve la huella anterior, las funciones anteriores siguen igual, el índice ya no está y los puntos reportados no se tocan',
   p.returncode == 0 and q(CONJ) == MD5_ANTES and q(VIEJAS) == viejas0 and q("select to_regclass('redes.ix_levantar_puntos_autor')") == '' and q('select count(*) from redes.levantar_puntos') == '3', p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'reversa_{NOMBRE}_editor.sql'))
ok('17 una segunda reversa se niega', p.returncode != 0 and 'No hay nada que revertir' in p.stderr, p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('18 después de la reversa, la migración se vuelve a aplicar', p.returncode == 0, p.stderr)
rehacer()
malas = [r for r in res if not r[1]]
print(f'\nRESULTADO: {len(res) - len(malas)} de {len(res)} — ' + ('SIN FALLAS' if not malas else f'{len(malas)} FALLA(S)'))
