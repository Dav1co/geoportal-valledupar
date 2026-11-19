#!/usr/bin/env python3
"""Arnés local de la corrección del 9b «la válvula que cerró el operador» (Code A, localhost:55432, base redes_local = producción al 17-nov, huella af34032d…,
con los CHECK, llaves y disparadores de sus migraciones):
  · el ensayo (N de N … SIN FALLAS) y que no deja nada; huellas; migración; verificación; segunda migración; reversa (vuelve la huella anterior);
  · que SOLO AGREGA: ninguna función anterior cambia de texto;
  · como la ve producción (service_role, 30 s / 8 s), con un OPERADOR SINTÉTICO SIN EL GEOVISOR sobre la red real: registra un daño, cierra una válvula,
    la ve cerrada por la lectura nueva, la abre; y sigue sin el geovisor. Tope local de la lectura: 1 s / 6 (producción es unas 6 veces más lenta).
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
NOMBRE = 'redes_9b_valvula_operador'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_ANTES = 'af34032d8e20434f53744eb642cddac2'
VIEJAS = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) from pg_proc p "
          "where (p.pronamespace in ('redes'::regnamespace, 'tecnica'::regnamespace) or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_%')) "
          "and p.prokind = 'f' and p.proname <> 'geoportal_redes_cierres_registro'")
ADM, OP, OP2, NA = 'zt9v.arnes.adm@emdupar.gov.co', 'zt9v.arnes.op@emdupar.gov.co', 'zt9v.arnes.mant@emdupar.gov.co', 'zt9v.arnes.nada@emdupar.gov.co'
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
ok('02 … y no deja nada (sigue la huella anterior, no está la función, ni una maniobra ni una fila de auditoría)',
   q(CONJ) == MD5_ANTES and q("select to_regprocedure('public.geoportal_redes_cierres_registro(text,text)')") == '' and q('select count(*) from redes.valvula_maniobras') == '0'
   and q('select count(*) from public.geoportal_auditoria') == aud0)
filas = psql('-AtF', '|', '-f', archivo(f'huellas_solo_lectura_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok('03 las huellas antes: «AGUAS ARRIBA (lista para la corrección)», la nueva no existe y las 5 que no se tocan son las publicadas', any('lista para la corrección' in f for f in filas)
   and sum('NO EXISTE (sin aplicar)' in f for f in filas) == 1 and sum('LA PUBLICADA' in f for f in filas) == 5 and not any('DISTINTA' in f or 'FALTA' in f for f in filas), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('04 la migración se aplica', p.returncode == 0, p.stderr)
ok('05 SOLO AGREGA: ninguna función anterior de redes, tecnica ni public.geoportal_* cambió de texto', q(VIEJAS) == viejas0)
filas = psql('-AtF', '|', '-f', archivo(f'huellas_solo_lectura_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok('06 las huellas después: «CORRECCIÓN (aplicada)», 1 nueva y las 5 publicadas igual', any('CORRECCIÓN (aplicada)' in f for f in filas) and sum('NUEVA (aplicada)' in f for f in filas) == 1
   and sum('LA PUBLICADA' in f for f in filas) == 5, '\n'.join(filas))
filas = psql('-AtF', '|', '-f', archivo(f'verificacion_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok(f'07 la verificación: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('08 una segunda migración se niega', p.returncode != 0 and 'ya está aplicada' in p.stderr, p.stderr)
ok('09 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')

# ---------- como la ve producción: el operador sintético SIN el geovisor, sobre la red real ----------
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{ADM}', 'ZT9V arnés admin', 'admin', 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'ZT9V arnés operador', 'consulta', true, 'sin_restriccion', 'todos'), "
  f"('{OP2}', 'ZT9V arnés mantenimiento', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{NA}', 'ZT9V arnés sin Técnica', 'consulta', 'sin_restriccion', 'todos')")
q(f"insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('{OP}', 'asignar_formulario', 'danos_fallas', '{ADM}'), ('{OP2}', 'asignar_formulario', 'mantenimiento', '{ADM}')")
ok('10 el perfil sintético: operador con «daños y fallas», SIN la casilla del geovisor y sin dashboards',
   q(f"select redes.f_geovisor_lectura('{OP}') or coalesce((select geovisor from redes.v_personal_ficha where persona = '{OP}'), false)") == 'f'
   and q(f"select redes.f_puede_formulario('{OP}', 'danos_fallas')") == 't')
ms, out, e = edge(f"select public.geoportal_redes_simulacion_aguas_arriba('{OP}', 'RED-000077')")
sim = json.loads(out) if not e else {}
val = (sim.get('aguas_arriba', {}).get('valvulas') or [{}])[0].get('codigo')
ok(f'11 simula como la Edge sobre el caso real ({ms} ms): RED-000077 pide {val}', not e and val, e or out[:300])
_, out, e = edge(f"select public.geoportal_redes_preparar_dano('{OP}', 1)")
prep = json.loads(out) if not e else {}
if prep:
    q(f"insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '{prep['fotos'][0]['ruta']}', '{{\"size\": 300000, \"mimetype\": \"image/jpeg\"}}')")
hace = q("select to_char(now() - interval '20 minutes', 'YYYY-MM-DD\"T\"HH24:MI:SSOF')")
ms, out, e = edge("select public.geoportal_redes_crear_dano('%s', '%s', %s)" % (OP, prep.get('dano_id'), lit({
    'clase': 'dano', 'tipo': 'fuga', 'sistema': 'acueducto', 'ubicacion_origen': 'mapa', 'activo': 'RED-000077', 'lat': sim.get('activo', {}).get('lat'), 'lon': sim.get('activo', {}).get('lon'),
    't_detectado': hace, 'tipo_rotura': 'parcial', 'riesgo': 'medio', 'causa_clase': 'desconocida', 'fotos': [{'n': 1, 'momento': 'dano', 'ruta': prep.get('fotos', [{}])[0].get('ruta')}]})))
dan = json.loads(out).get('codigo') if not e else None
ok(f'12 registra su daño como la Edge ({ms} ms): {dan}', dan, e)
ms, out, e = edge(f"select public.geoportal_redes_valvula_maniobra('{OP}', '{val}', 'cerrar', '{dan}')")
man = json.loads(out) if not e else {}
ok(f'13 cierra {val} desde su daño como la Edge ({ms} ms; la foto del corte sobre la red real): queda guardado', not e and man.get('estado') == 'cerrada' and ms < 30000, e or out[:300])
_, _, e = edge(f"select public.geoportal_redes_cortes_vigentes('{OP}')")
ok('14 LA CAUSA: lo que leía el panel se le niega (42501, «Sin el geovisor técnico»)', '42501' in e and 'Sin el geovisor' in e, e[:300])
ms, out, e = edge(f"select public.geoportal_redes_cierres_registro('{OP}', '{dan}')")
j = json.loads(out) if not e else {}
ok(f'15 LA CORRECCIÓN como la Edge ({ms} ms; tope local {T1:.0f} ms): su daño tiene cerrada {val}, con desde cuándo y quién; puede abrir',
   not e and ms < T1 and [v['codigo'] for v in j['valvulas']] == [val] and j['puede_abrir'] is True and j['valvulas'][0]['quien'] == 'ZT9V arnés operador' and j['valvulas'][0]['desde'], e or out[:300])
ms, out, e = edge(f"select public.geoportal_redes_cierres_registro('{OP2}', '{dan}')")
j = json.loads(out) if not e else {}
_, _, e2 = edge(f"select public.geoportal_redes_valvula_maniobra('{OP2}', '{val}', 'abrir')")
ok('16 el operador de mantenimiento la ve cerrada pero «puede_abrir» es falso, y la maniobra se lo niega (42501)', not e and len(j['valvulas']) == 1 and j['puede_abrir'] is False and '42501' in e2, e or e2[:300])
ok('17 alguien sin Técnica no lee (42501); la API no ejecuta las internas', '42501' in edge(f"select public.geoportal_redes_cierres_registro('{NA}', '{dan}')")[2]
   and '42501' in edge("select * from redes.f_cierres_vigentes()")[2])
aud = q(f"select count(*) from public.geoportal_auditoria where email = '{OP}'")
peor = max(edge(f"select public.geoportal_redes_cierres_registro('{OP}', '{dan}')")[0] for _ in range(10))
ok(f'18 diez lecturas seguidas como la Edge: la más lenta {peor} ms (tope local {T1:.0f} ms); leer no deja auditoría', peor < T1 and q(f"select count(*) from public.geoportal_auditoria where email = '{OP}'") == aud)
ms, out, e = edge(f"select public.geoportal_redes_valvula_maniobra('{OP}', '{val}', 'abrir')")
_, out2, _ = edge(f"select public.geoportal_redes_cierres_registro('{OP}', '{dan}')")
ok(f'19 el operador sin geovisor ABRE {val} como la Edge ({ms} ms) y su daño queda sin válvulas cerradas', not e and json.loads(out)['estado'] == 'abierta' and json.loads(out2)['valvulas'] == [], e or out2[:300])
ok('20 el operador sigue SIN el geovisor: la configuración y la tesela de afectaciones se le niegan (42501)',
   '42501' in edge(f"select public.geoportal_redes_geovisor('{OP}')")[2] and '42501' in edge(f"select public.geoportal_redes_geovisor_mvt_cortes('{OP}', 16, 0, 0)")[2]
   and q(f"select redes.f_geovisor_lectura('{OP}')") == 'f')
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'reversa_{NOMBRE}_editor.sql'))
ok('21 la reversa se aplica: vuelve la huella anterior, las funciones anteriores siguen igual y las maniobras hechas no se tocan',
   p.returncode == 0 and q(CONJ) == MD5_ANTES and q(VIEJAS) == viejas0 and q('select count(*) from redes.valvula_maniobras') == '2', p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'reversa_{NOMBRE}_editor.sql'))
ok('22 una segunda reversa se niega', p.returncode != 0 and 'No hay nada que revertir' in p.stderr, p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('23 después de la reversa, la migración se vuelve a aplicar', p.returncode == 0, p.stderr)
rehacer()
malas = [r for r in res if not r[1]]
print(f'\nRESULTADO: {len(res) - len(malas)} de {len(res)} — ' + ('SIN FALLAS' if not malas else f'{len(malas)} FALLA(S)'))
