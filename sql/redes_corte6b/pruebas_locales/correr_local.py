#!/usr/bin/env python3
"""Arnés local del Corte 6b (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Como en el despliegue (1a con la carga real, Cortes 2 a 6a y la MUE publicada) más 111.950 contratos SINTÉTICOS sobre la red (predio, cartera y ficha):
huellas antes · ensayo (ERROR esperado y sin rastro) · migración · verificación · guardia · huellas después · reversa vacía (exacta al 6a) · migrar de nuevo ·
tiempo de rehacer la capa de contratos y peso de su tesela · la tarjeta y su auditoría · el color de los 27 puntos MUE · compartir y abrir una vista ·
verificación con datos · reversa con datos (rechazo).
Uso: python3 -I correr_local.py   → escribe ../resultados/sql_local.txt
"""
import json
import math
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
ADMIN = 'carga.local@emdupar.gov.co'
SUP = 'arnes.dist@emdupar.gov.co'
res = []


def archivo(nombre):
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-X', '-v', 'ON_ERROR_STOP=1', '-f', nombre], env=ENV, capture_output=True, text=True)
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


def huellas():
    return q(f"select string_agg(objeto || '=' || estado, E'\\n') from ({open(ED('huellas_solo_lectura_redes_corte6b_editor.sql'), encoding='utf-8').read().split('-- =====================================================================', 2)[2].strip().rstrip(';')}) h")


def tesela_xy(z, lon, lat):
    n = 1 << z
    return int((lon + 180) / 360 * n), int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n)


# ---------- base como en vivo ----------
H6A = '91a4d3e6e1c3539d8a447cb00a52d735'
t0 = time.time()
subprocess.run(['sh', os.path.join(AQUI, 'base_chrome.sh'), 'solo_6a'], env=ENV, check=True, capture_output=True)
reg('00 base con la carga real, la MUE, el 6a y 111.950 contratos sintéticos', q(CONJ) == H6A,
    f"{time.time() - t0:.0f} s · {q('select count(distinct cod_usuario) from public.catastro_valledupar')} contratos en el catastro")
h = huellas()
reg('01 huellas antes: «CORTE 6a (listo para el 6b)», 4 RPC y 5 objetos «NO EXISTE», 2 «CORTE 6a (sin cambiar)»',
    'CORTE 6a (listo para el 6b)' in h and h.count('NO EXISTE (sin aplicar)') == 9 and h.count('CORTE 6a (sin cambiar)') == 2 and 'DISTINTA' not in h, h.replace('\n', ' | ')[:300])
c, out, s = archivo(ED('ensayo_en_transaccion_redes_corte6b_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('02 ensayo con la carga real y los contratos: ERROR esperado, N de N SIN FALLAS', c != 0 and m and m.group(1) == m.group(2) and 'SIN FALLAS' in m.group(3),
    (m.group(0) if m else out[-600:]) + f' · {s:.1f} s')
reg('03 el ensayo no deja rastro', q("select to_regclass('redes.contratos_capa') is null") == 't' and q(CONJ) == H6A
    and q("select count(*) from public.geoportal_auditoria where email like 'prueba.redes11.%'") == '0' and q("select count(*) from public.catastro_valledupar where cod_usuario like '99000000110%'") == '0')
c, out, s = archivo(ED('migracion_redes_corte6b_editor.sql'))
reg('04 migración', c == 0, f'{s:.1f} s' + ('' if c == 0 else ' · ' + out[-400:]))
md5_6b = q(CONJ)
v = q(open(ED('verificacion_redes_corte6b_editor.sql'), encoding='utf-8').read().split('-- =====================================================================', 2)[2].rstrip().rstrip(';'))
filas = [x for x in v.split('\n') if x]
reg('05 verificación: todas las filas OK', all(x.endswith('|OK') for x in filas if not x.startswith('INFO')), ' | '.join(filas)[-300:])
c, out, _ = archivo(ED('migracion_redes_corte6b_editor.sql'))
reg('06 guardia: migrar dos veces se niega', c != 0 and 'Corte 6b ya está aplicado' in out, out.strip().split('\n')[-1][:160])
h = huellas()
reg('07 huellas después: «CORTE 6b (aplicado)», 4 «NUEVA», 2 «CORTE 6b (reemplazada)», 5 «EXISTE»',
    'CORTE 6b (aplicado)' in h and h.count('NUEVA (aplicada)') == 4 and h.count('CORTE 6b (reemplazada)') == 2 and h.count('EXISTE (aplicado)') == 5, h.replace('\n', ' | ')[:300])
c, out, _ = archivo(ED('reversa_redes_corte6b_editor.sql'))
reg('08 reversa vacía: exacta al 6a, sin las tablas nuevas y el catálogo como en el 6a', c == 0 and q(CONJ) == H6A and q("select to_regclass('redes.vistas_compartidas') is null") == 't'
    and q("select fuente from redes.geovisor_capas where codigo = 'contratos'") == 'preparada', out[-300:] if c else '')
c, out, _ = archivo(ED('migracion_redes_corte6b_editor.sql'))
reg('09 migrar de nuevo después de la reversa', c == 0 and q(CONJ) == md5_6b)

# ---------- la capa de contratos con 112 mil contratos ----------
SUP = 'arnes.dist@emdupar.gov.co'
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SUP}', 'Arnés distribución', 'consulta', true, true, 'sin_restriccion', 'todos') on conflict do nothing")
t = time.time()
cfg = json.loads(q(f"select public.geoportal_redes_geovisor('{SUP}')"))
s_cfg = time.time() - t
reg('10 la primera configuración del supervisor rehace la capa de contratos (sin el comodín ni el «0»; uno por contrato) en menos de 15 s',
    cfg['contratos_capa']['filas'] == int(q("select count(distinct cod_usuario) from public.catastro_valledupar where cod_usuario not in ('0', '99999999')")) and s_cfg < 15,
    f"{cfg['contratos_capa']['filas']} contratos · {s_cfg:.1f} s · {q('select duracion_ms from redes.contratos_capa_estado')} ms de rehacer")
t = time.time(); q(f"select public.geoportal_redes_geovisor('{SUP}')"); s2 = time.time() - t
reg('11 la siguiente configuración no la rehace (rápida)', s2 < 1, f'{s2 * 1000:.0f} ms')
reg('12 estados de la cartera: activos, retirados y otros (suspendidos)', q("select string_agg(estado || '=' || n, ' ' order by estado) from (select estado, count(*) n from redes.contratos_capa group by 1) x").count('=') >= 3,
    q("select string_agg(estado || '=' || n, ' ' order by estado) from (select estado, count(*) n from redes.contratos_capa group by 1) x"))
pesos = {}
for z in (15, 16, 17, 18):
    x, y = tesela_xy(z, -73.255, 10.470)
    t = time.time(); b64 = q(f"select public.geoportal_redes_geovisor_mvt_contratos('{SUP}', {z}, {x}, {y})"); pesos[z] = (len(b64) * 3 // 4, time.time() - t)
reg('13 tesela de contratos del centro: vacía a z15; a z16 menos de 200 KB; ninguna de más de 1 s', pesos[15][0] == 0 and 0 < pesos[16][0] < 200 * 1024 and all(s < 1 for _, s in pesos.values()),
    ' · '.join(f'z{z} {b // 1024} KB {s * 1000:.0f} ms' for z, (b, s) in pesos.items()))
import base64  # noqa: E402
binario = base64.b64decode(q(f"select public.geoportal_redes_geovisor_mvt_contratos('{SUP}', 17, {tesela_xy(17, -73.255, 10.470)[0]}, {tesela_xy(17, -73.255, 10.470)[1]})") or '')
reg('14 la tesela no lleva nombres, direcciones ni teléfonos de la cartera sintética', b'SUSCRIPTOR' not in binario and b'DIRECCION' not in binario and b'3000000000' not in binario and b'BARRIO' not in binario,
    f'{len(binario)} bytes')
c1 = q("select contrato from redes.contratos_capa where estado = 'activo' order by contrato limit 1")
n0 = int(q("select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta'"))
t = time.time(); tj = json.loads(q(f"select public.geoportal_redes_contrato_tarjeta('{SUP}', '{c1}', '127.0.0.1')")); s_tj = time.time() - t
reg('15 la tarjeta de un contrato sintético: nombre del último corte, consumo de 6 meses, tramo enlazado o nulo; sin teléfono ni deuda; menos de 300 ms',
    tj['suscriptor']['nombre'].startswith('SUSCRIPTOR SINTETICO') and len(tj['consumo']['meses']) == 6 and '3000000000' not in json.dumps(tj) and '99999' not in json.dumps(tj) and s_tj < 0.3,
    f"{s_tj * 1000:.0f} ms · {json.dumps(tj, ensure_ascii=False)[:200]}")
reg('16 la lectura quedó en la auditoría sin el nombre', int(q("select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta'")) == n0 + 1
    and 'SUSCRIPTOR' not in q("select detalle::text from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta' order by id desc limit 1"))

# ---------- el muestreo real (27 puntos) con las muestras sintéticas ----------
mue = json.loads(q(f"select public.geoportal_redes_geovisor_capa('{SUP}', 'muestreo')"))
cal = [f['properties']['calidad'] for f in mue['features']]
reg('17 los 27 puntos MUE con su color: uno «fuera» (cloro 0,1), uno «dentro», y los demás «sin_muestra» (uno con una muestra de hace 90 días)',
    len(cal) == 27 and cal.count('fuera') == 1 and cal.count('dentro') == 1 and cal.count('sin_muestra') == 25, str({k: cal.count(k) for k in set(cal)}))

# ---------- compartir y abrir ----------
vid = json.loads(q(f"""select public.geoportal_redes_vista_compartir('{SUP}', '{{"capas": ["acu_tramos", "contratos"], "colores": "tipo", "periodo": {{"modo": "hoy"}}, "lon": -73.25, "lat": 10.46, "zoom": 17}}')"""))['id']
ab = json.loads(q(f"select public.geoportal_redes_vista_abrir('{SUP}', '{vid}')"))
reg('18 compartir y abrir una vista', ab['capas'] == ['acu_tramos', 'contratos'] and ab['zoom'] == 17, vid)
v = q(open(ED('verificacion_redes_corte6b_editor.sql'), encoding='utf-8').read().split('-- =====================================================================', 2)[2].rstrip().rstrip(';'))
filas = [x for x in v.split('\n') if x]
reg('19 verificación con datos: todas OK', all(x.endswith('|OK') for x in filas if not x.startswith('INFO')), filas[-1])
c, out, _ = archivo(ED('reversa_redes_corte6b_editor.sql'))
reg('20 reversa con datos: se niega (ya hay vistas compartidas) y no cambia nada', c != 0 and 'se niega' in out and q(CONJ) == md5_6b, out.strip().split('\n')[-1][:160])

ok = sum(1 for _, b, _ in res if b)
texto = '\n'.join(('OK    ' if b else 'FALLA ') + n + ((' · ' + d) if d else '') for n, b, d in res)
texto += f'\n\nRESULTADO: {ok} de {len(res)} — ' + ('SIN FALLAS' if ok == len(res) else f'{len(res) - ok} FALLA(S)') + '\n'
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write(texto)
print(f'\nRESULTADO: {ok} de {len(res)}')
