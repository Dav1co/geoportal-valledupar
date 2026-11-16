#!/usr/bin/env python3
"""Arnés local del Corte 9a-bis (base de Code B: emdupar_b en localhost:55442; nunca la de Code A). Resultado «N de N».
Recorre la publicación con la base como producción hoy (el 9a y su carga, volumen real): huellas → ensayo (sin rastro) → migración → verificación → guardia →
reversa exacta → migrar de nuevo → ensayo de los sectores oficiales (sin rastro) → sectores oficiales → verificación → las RPC como las llama la Edge
(service_role, 30 s y 8 s), con sus tiempos.
Uso: python3 -I correr_local.py"""
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
GEN = os.path.join(RAIZ, 'carga_sectores', 'generado')
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = os.environ.get('BASE_B', 'emdupar_b')
ENV = dict(os.environ, PGHOST='localhost', PGPORT=os.environ.get('PGPORT_B', '55442'), PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
assert ENV['PGPORT'] != '55432', 'El puerto 55432 es de Code A'
ADMIN = 'carga.local@emdupar.gov.co'
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
EDGE = ['-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'"]
res = []


def ok(nombre, cond, det=''):
    res.append((nombre, bool(cond), str(det)[:400]))
    print(('OK    ' if cond else 'FALLA ') + nombre + ('' if cond else ' → ' + str(det)[:400]), flush=True)


def archivo(nombre, cwd=RAIZ, var=None):
    t0 = time.time()
    p = subprocess.run([PSQL, '-d', BASE, '-X', '-v', 'ON_ERROR_STOP=1'] + (['-v', var] if var else []) + ['-f', nombre], env=ENV, capture_output=True, text=True, cwd=cwd)
    return p.returncode, p.stdout + p.stderr, time.time() - t0


def q(sql):
    p = subprocess.run([PSQL, '-d', BASE, '-AtX', '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout + p.stderr).strip()


def edge(sql):
    t0 = time.time()
    p = subprocess.run([PSQL, '-d', BASE, '-AtqX', '-v', 'ON_ERROR_STOP=1', *EDGE, '-c', sql], env=ENV, capture_output=True, text=True)
    return p.stdout.strip(), p.stderr.strip(), round((time.time() - t0) * 1000)


def rastro():
    return q("select (select count(*) from public.geoportal_lista_blanca where email like 'prueba.redes14.%') || '|' || (select count(*) from redes.activos) || '|' || (select count(*) from redes.activo_eventos)"
             " || '|' || (select count(*) from redes.nodo_eventos) || '|' || (select count(*) from redes.danos) || '|' || (select count(*) from public.geoportal_auditoria) || '|' || (select count(*) from redes.cargas)")


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
H = open(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte9a_bis_editor.sql'), encoding='utf-8').read()
MD5_BASE = re.search(r"when '([0-9a-f]{32})' then 'CORTE 9a \(listo para el 9a-bis\)'", H).group(1)
MD5_BIS = re.search(r"when '([0-9a-f]{32})' then 'CORTE 9a-bis \(aplicado\)'", H).group(1)

ok('01 la base local es como producción hoy: huella del conjunto de redes del 9a publicado, con la carga del Plan', q(CONJ) == MD5_BASE and q("select count(*) from redes.v_ref_carga_vigente") == '12', q(CONJ))
ok('02 volumen real: 36.302 activos vigentes y más de 111 mil contratos en el catastro', q("select count(*) from redes.activo_vigente_mat where not retirado") == '36302'
   and int(q("select count(distinct cod_usuario) from public.catastro_valledupar")) > 111000)
_, t, _ = archivo('huellas_solo_lectura_redes_corte9a_bis_editor.sql')
ok('03 huellas ANTES: «CORTE 9a (listo para el 9a-bis)», 14 «sin cambiar», 7 «NO EXISTE», los 4 índices y nada «DISTINTA» ni «FALTA»',
   'CORTE 9a (listo para el 9a-bis)' in t and t.count('CORTE 9a (sin cambiar)') == 14 and t.count('NO EXISTE (sin aplicar)') == 7 and t.count('| EXISTE') == 4 and 'DISTINTA' not in t and 'FALTA' not in t, t[-600:])
r0 = rastro()
c, t, s = archivo('ensayo_en_transaccion_redes_corte9a_bis_editor.sql')
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', t)
ok(f'04 ensayo en transacción: termina en ERROR con «{m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS» ({s:.1f} s)', c != 0 and m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS'), t[-900:])
print('     ' + (re.search(r'TIEMPOS:.*', t).group(0) if re.search(r'TIEMPOS:.*', t) else ''))
ok('05 el ensayo no deja rastro y el 9a-bis sigue sin aplicar', rastro() == r0 and q(CONJ) == MD5_BASE, rastro())
c, t, s = archivo('migracion_redes_corte9a_bis_editor.sql')
ok(f'06 la migración aplica en una transacción ({s:.1f} s)', c == 0, t[-500:])
ok('07 huella del conjunto de redes del 9a-bis', q(CONJ) == MD5_BIS, q(CONJ))
_, t, _ = archivo('verificacion_redes_corte9a_bis_editor.sql')
ok('08 verificación: 7 OK y ninguna MAL', len(re.findall(r'\| OK', t)) == 7 and 'MAL' not in t, t[-900:])
_, t, _ = archivo('huellas_solo_lectura_redes_corte9a_bis_editor.sql')
ok('09 huellas DESPUÉS: «CORTE 9a-bis (aplicado)», 14 «reemplazada» y 7 «NUEVA»', 'CORTE 9a-bis (aplicado)' in t and t.count('CORTE 9a-bis (reemplazada)') == 14 and t.count('NUEVA (aplicada)') == 7 and 'DISTINTA' not in t, t[-600:])
c, t, _ = archivo('migracion_redes_corte9a_bis_editor.sql')
ok('10 guardia: migrar dos veces se niega («ya está aplicado»)', c != 0 and 'ya está aplicado' in t, t[-300:])
nota9a = q("select nombre || '|' || nota from redes.geovisor_capas where codigo = 'sectores'")
c, t, _ = archivo('reversa_redes_corte9a_bis_editor.sql')
ok('11 la reversa deja las funciones EXACTAS como en el 9a y la capa de sectores como estaba', c == 0 and q(CONJ) == MD5_BASE
   and q("select nota from redes.geovisor_capas where codigo = 'sectores'").startswith('Proyectados por el Plan Maestro 2014'), t[-400:])
c, t, _ = archivo('migracion_redes_corte9a_bis_editor.sql')
ok('12 se puede migrar de nuevo después de la reversa y la huella es la misma', c == 0 and q(CONJ) == MD5_BIS and q("select nombre || '|' || nota from redes.geovisor_capas where codigo = 'sectores'") == nota9a, t[-400:])

r0 = rastro()
c, t, s = archivo('ensayo_sectores_oficiales.sql', GEN, f'solicitante={ADMIN}')
m = re.search(r'(\d+) de (\d+) comprobaciones correctas — (SIN FALLAS|.*)', t)
ok(f'13 ensayo de los sectores oficiales: ERROR con «{m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS» y sin rastro ({s:.1f} s)',
   m and m.group(1) == m.group(2) and 'ENSAYO' in t and rastro() == r0, t[-600:])
c, t, s = archivo('sectores_oficiales.sql', GEN, f'solicitante={ADMIN}')
ok(f'14 sectores_oficiales.sql: los 36 polígonos pasan a «En operación» con una versión nueva por el motor ({s:.1f} s)', c == 0
   and q("select count(*) filter (where estado_codigo = 'en_operacion') || '·' || count(*) from redes.activo_vigente_mat where prefijo = 'SEC' and not retirado") == '36·36', t[-500:])
c, t, _ = archivo('sectores_oficiales.sql', GEN, f'solicitante={ADMIN}')
ok('15 repetirlo se niega (el mismo archivo ya está publicado) y no cambia nada', c != 0 and q("select max(version) from redes.activo_vigente_mat where prefijo = 'SEC'") == '2', t[-300:])
_, t, _ = archivo('verificacion_redes_corte9a_bis_editor.sql')
ok('16 la verificación sigue en 7 OK; la fila INFO dice 36 en operación y 0 proyectados', len(re.findall(r'\| OK', t)) == 7 and re.search(r'\| *36 · 0 · ', t) is not None, t[-500:])

SD, AD, OPE, OPS = 'zt.dist@emdupar.gov.co', 'zt.admin@emdupar.gov.co', 'zt.oper@emdupar.gov.co', 'zt.oper.sinform@emdupar.gov.co'
tiempos = []


def medir(nombre, sql):
    t, e, ms = edge(sql)
    tiempos.append((nombre, ms))
    return t, e


val = q("select codigo from redes.activo_vigente_mat where codigo_anterior = 'V85'")
red = q("select m.codigo from redes.activo_vigente_mat m join redes.tramo_nodos t on t.activo_id = m.activo_id and t.version = m.version where m.prefijo = 'RED' order by m.activo_id limit 1")
t, e = medir('ficha de una válvula', f"select public.geoportal_redes_activo('{SD}', '{val}') -> 'nodo' ->> 'tramos'")
ok('17 Edge: la ficha de una válvula real trae su nodo y sus tramos', e == '' and t.isdigit(), e or t)
t, e = medir('ficha de un tramo', f"select public.geoportal_redes_activo('{SD}', '{red}') -> 'tramo' ->> 'metodo'")
ok('18 Edge: la ficha de un tramo real trae sus extremos', e == '' and t == 'modelo', e or t)
t, e = medir('minimapa de un tramo', f"select jsonb_array_length(public.geoportal_redes_tramo_nodos('{OPE}', '{red}') -> 'nodos')")
ok('19 Edge: el minimapa de un tramo trae sus 2 nodos', e == '' and t == '2', e or t)
t, e = medir('ficha del operador', f"select (public.geoportal_redes_activo('{OPE}', '{val}') ? 'referencia')::text || (public.geoportal_redes_activo('{OPE}', '{val}') ? 'sector_hidraulico')::text")
ok('20 Edge: el operador ve el sector hidráulico y no la referencia del Plan', e == '' and t == 'falsetrue', e or t)
t, e = medir('mi perfil del operador', f"select (public.geoportal_redes_mi_perfil('{OPE}') ->> 'ficha_buscar') || (public.geoportal_redes_mi_perfil('{OPS}') ->> 'ficha_buscar')")
ok('21 Edge: «ficha_buscar» sí para el operador de redes y no para quien no lo es', e == '' and t == 'truefalse', e or t)
lat, lon = q("select ST_Y(ST_PointOnSurface(geom)) || ' ' || ST_X(ST_PointOnSurface(geom)) from redes.activo_vigente_mat where prefijo = 'SEC' and nombre = 'Subsector 4.1'").split()
t, e = medir('sector de un punto', f"select public.geoportal_redes_sector_en('{OPE}', {lat}, {lon}) ->> 'subsector'")
ok('22 Edge: el sector de un punto (4.1)', e == '' and t == '4.1', e or t)
t, e = medir('bandeja de nodos (supervisor)', f"select public.geoportal_redes_nodos_por_clasificar('{SD}', null, null, 50) -> 'grupos_no_crear'")
ok('23 Edge: el supervisor ve la bandeja de nodos con los grupos de «no crear activo» (491, 5 y 4)', e == '' and '"n": 491' in t and '"n": 5' in t and '"n": 4' in t, e or t)
t, e = medir('vista previa de las válvulas propuestas', f"select public.geoportal_redes_nodos_clasificar_grupo('{SD}', 'valvula_propuesta') ->> 'huella'")
ok('24 Edge: la vista previa del grupo de válvulas propuestas', e == '' and len(t) == 32, e or t)
huella = t
t, e = medir('confirmar 491 válvulas propuestas', f"select public.geoportal_redes_nodos_clasificar_grupo('{SD}', 'valvula_propuesta', '{huella}', 'Arnés: válvulas que el Plan propuso y no se instalaron') ->> 'n'")
ok('25 Edge (escribe): confirmar el grupo de 491 válvulas pasa por la API (inserts con motivo; nada sin WHERE)', e == '' and t == '491'
   and q("select count(*) from redes.v_nodo_vigente where clase_nodo = 'propuesta_plan'") == '491', e or t)
t, e = medir('crear un daño (sector de la ubicación)', f"""select public.geoportal_redes_crear_dano('{OPE}', (public.geoportal_redes_preparar_dano('{OPE}', 1) ->> 'dano_id')::uuid, '{{}}'::jsonb)""")
ok('26 Edge: la RPC de crear daño sigue validando como antes (sin datos: «Falta…», no un error del servidor)', 'Falta' in e or 'Elija' in e or 'Escriba' in e, e[-300:])
t, e = edge(f"select public.geoportal_redes_nodos_por_clasificar('{OPE}')")[:2]
ok('27 Edge: el operador no ve la bandeja de nodos (42501)', 'Solo el supervisor o el administrador' in e, e or t)
peor = max(tiempos, key=lambda z: z[1])
ok(f'28 ninguna llamada pasó de 1,5 s en local con el volumen real (la más lenta: {peor[0]}, {peor[1]} ms, con el arranque de psql)', peor[1] < 1500, tiempos)
print('TIEMPOS (local, cada uno con el arranque de psql): ' + ' · '.join(f'{n} {ms} ms' for n, ms in tiempos))
bien = sum(1 for r in res if r[1])
print('----')
print(f'RESULTADO: {bien} de {len(res)} — ' + ('SIN FALLAS' if bien == len(res) else f'{len(res) - bien} FALLA(S)'))
raise SystemExit(0 if bien == len(res) else 1)
