#!/usr/bin/env python3
"""Arnés local del Corte 6a (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Como en el despliegue (1a con la carga real, Cortes 2 a 5c y la primera carga MUE de los 27 puntos publicada):
huellas antes · ensayo (ERROR esperado y sin rastro) · migración · verificación · guardia · huellas después · reversa vacía (exacta al 5c) · migrar de nuevo ·
peso y tiempo de la tesela del geovisor sobre la red real (centro de Valledupar, zooms 12 a 17) · la configuración y las capas por fecha con datos reales ·
el supervisor de distribución no recarga el acueducto real · verificación con datos · reversa con datos (rechazo).
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
    return q(f"select string_agg(objeto || '=' || estado, E'\\n') from ({open(ED('huellas_solo_lectura_redes_corte6a_editor.sql'), encoding='utf-8').read().split('-- =====================================================================', 2)[2].strip().rstrip(';')}) h")


def tesela_xy(z, lon, lat):
    n = 1 << z
    return int((lon + 180) / 360 * n), int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n)


# ---------- base como en vivo ----------
t0 = time.time()
subprocess.run(['sh', os.path.join(AQUI, 'base_chrome.sh')], env=dict(ENV, SOLO_5C='1'), check=True, capture_output=True)
# base_chrome.sh deja el 6a migrado; para empezar «antes», se revierte (y así la reversa vacía queda probada sobre la carga real)
md5_6a_mig = q(CONJ)
c, out, _ = archivo(ED('reversa_redes_corte6a_editor.sql'))
reg('00 base con la carga real del 1a, la MUE y el 5c; la reversa vacía la deja en el 5c', c == 0 and q(CONJ) == 'a5ce1ff8c5659de3b853e30f4d3025e6',
    f'{time.time() - t0:.0f} s · {q("select count(*) from redes.activo_vigente_mat where not retirado")} activos vigentes')

h = huellas()
reg('01 huellas antes: «CORTE 5c (listo para el 6a)», 4 RPC «NO EXISTE», 10 «CORTE 5c (sin cambiar)», 4 «NO EXISTE»',
    'CORTE 5c (listo para el 6a)' in h and h.count('NO EXISTE (sin aplicar)') == 8 and h.count('CORTE 5c (sin cambiar)') == 10 and 'DISTINTA' not in h, h.replace('\n', ' | ')[:300])

c, out, s = archivo(ED('ensayo_en_transaccion_redes_corte6a_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('02 ensayo con la carga real: ERROR esperado, N de N SIN FALLAS', c != 0 and m and m.group(1) == m.group(2) and 'SIN FALLAS' in m.group(3),
    (m.group(0) if m else out[-600:]) + f' · {s:.1f} s')
reg('03 el ensayo no deja rastro (sin tablas del 6a, misma huella, sin auditoría de prueba)',
    q("select to_regclass('redes.geovisor_capas') is null") == 't' and q(CONJ) == 'a5ce1ff8c5659de3b853e30f4d3025e6'
    and q("select count(*) from public.geoportal_auditoria where email like 'prueba.redes10.%'") == '0')

c, out, s = archivo(ED('migracion_redes_corte6a_editor.sql'))
reg('04 migración', c == 0, f'{s:.1f} s' + ('' if c == 0 else ' · ' + out[-400:]))
reg('05 la huella del 6a es la de generar.py', q(CONJ) == md5_6a_mig, q(CONJ))
v = q(open(ED('verificacion_redes_corte6a_editor.sql'), encoding='utf-8').read().split('-- =====================================================================', 2)[2].rstrip().rstrip(';'))
filas = [x for x in v.split('\n') if x]
reg('06 verificación: todas las filas OK', all(x.endswith('|OK') for x in filas if not x.startswith('INFO')), ' | '.join(filas)[-400:])
c, out, _ = archivo(ED('migracion_redes_corte6a_editor.sql'))
reg('07 guardia: migrar dos veces se niega', c != 0 and 'Corte 6a ya está aplicado' in out, out.strip().split('\n')[-1][:160])
h = huellas()
reg('08 huellas después: «CORTE 6a (aplicado)», 4 «NUEVA», 10 «CORTE 6a (reemplazada)», 4 «EXISTE»',
    'CORTE 6a (aplicado)' in h and h.count('NUEVA (aplicada)') == 4 and h.count('CORTE 6a (reemplazada)') == 10 and h.count('EXISTE (aplicado)') == 4, h.replace('\n', ' | ')[:300])
c, out, _ = archivo(ED('reversa_redes_corte6a_editor.sql'))
reg('09 reversa vacía: exacta al 5c (funciones), sin tablas ni columna nuevas',
    c == 0 and q(CONJ) == 'a5ce1ff8c5659de3b853e30f4d3025e6' and q("select to_regclass('redes.capas_por_perfil') is null") == 't'
    and q("select count(*) from information_schema.columns where table_schema = 'redes' and table_name = 'capas' and column_name = 'carga_supervisor'") == '0', out[-300:] if c else '')
c, out, _ = archivo(ED('migracion_redes_corte6a_editor.sql'))
reg('10 migrar de nuevo después de la reversa', c == 0 and q(CONJ) == md5_6a_mig)

# ---------- la tesela del geovisor con la red real ----------
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{ADMIN}', 'Arnés', 'admin', 'sin_restriccion', 'todos') on conflict do nothing")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SUP}', 'Arnés distribución', 'consulta', true, true, 'sin_restriccion', 'todos') on conflict do nothing")
pesos = {}
for z in range(12, 18):
    x, y = tesela_xy(z, -73.255, 10.470)
    t = time.time()
    b64 = q(f"select public.geoportal_redes_geovisor_mvt('{ADMIN}', {z}, {x}, {y})")
    pesos[z] = (len(b64) * 3 // 4, time.time() - t)
detalle = ' · '.join(f'z{z} {b // 1024} KB {s * 1000:.0f} ms' for z, (b, s) in pesos.items())
reg('11 tesela del centro de Valledupar: vacía a z12; a z13 (red principal) menos de 200 KB; ninguna pasa de 200 KB ni de 1,5 s',
    pesos[12][0] == 0 and 0 < pesos[13][0] < 200 * 1024 and all(b < 200 * 1024 and s < 1.5 for b, s in pesos.values()), detalle)
x, y = tesela_xy(15, -73.255, 10.470)
b64 = q(f"select public.geoportal_redes_geovisor_mvt('{ADMIN}', 15, {x}, {y})")
import base64  # noqa: E402
binario = base64.b64decode(b64) if b64 else b''
reg('12 la tesela real a z15 trae tramos, nodos y los materiales del modelo (PVC y AC), sin nombres de contrato', b'tramo' in binario and b'nodo' in binario and b'PVC' in binario and b'AC' in binario
    and b'emdupar.gov.co' not in binario, f'{len(binario)} bytes')
# todas las teselas de z14 que cubren la red (caja de los activos): ninguna pasa de 250 KB
caja = q("select ST_XMin(e) || ' ' || ST_YMin(e) || ' ' || ST_XMax(e) || ' ' || ST_YMax(e) from (select ST_Extent(geom)::geometry e from redes.activo_vigente_mat where sistema = 'acueducto' and not retirado) x").split()
x0, y1 = tesela_xy(14, float(caja[0]), float(caja[1]))
x1, y0 = tesela_xy(14, float(caja[2]), float(caja[3]))
mayor, n, t = 0, 0, time.time()
for xx in range(x0, x1 + 1):
    for yy in range(y0, y1 + 1):
        b = len(q(f"select public.geoportal_redes_geovisor_mvt('{ADMIN}', 14, {xx}, {yy})")) * 3 // 4
        mayor, n = max(mayor, b), n + 1
reg('13 las teselas de z14 que cubren toda la red de acueducto: la más pesada, menos de 250 KB', mayor < 250 * 1024, f'{n} teselas · la mayor {mayor // 1024} KB · {time.time() - t:.1f} s en total')

# ---------- configuración y capas con datos reales ----------
cfg = json.loads(q(f"select public.geoportal_redes_geovisor('{ADMIN}')"))
reg('14 la configuración del administrador con los datos reales: 19 capas, 8 encendidas, los tipos con alias (TOR = Torre…)',
    len(cfg['capas']) == 19 and sum(1 for c in cfg['capas'] if c['encendida']) == 8 and cfg['tipos'].get('TOR', '').startswith('Torre'), str(cfg['zoom']))
t = time.time()
mue = json.loads(q(f"select public.geoportal_redes_geovisor_capa('{ADMIN}', 'muestreo')"))
reg('15 la capa de muestreo trae los 27 puntos reales (3 verificados y 24 aproximados)', len(mue['features']) == 27
    and sum(1 for f in mue['features'] if f['properties']['exactitud'] == 'verificada') == 3, f'{(time.time() - t) * 1000:.0f} ms')
hoy = q("select (clock_timestamp() at time zone 'America/Bogota')::date")
t = time.time()
dan = json.loads(q(f"select public.geoportal_redes_geovisor_capa('{ADMIN}', 'danos', '{hoy}'::date - 365, '{hoy}'::date)"))
reg('16 la capa de daños con 12 meses de rango responde (sin datos en la base local)', dan['type'] == 'FeatureCollection' and dan['recortada'] is False, f'{(time.time() - t) * 1000:.0f} ms')
c = q(f"select public.geoportal_redes_cargue_iniciar('{SUP}', 'acueducto', encode(sha256('arnes'::bytea), 'hex'), 'shp', 4326, 'ID', 10578)")
reg('17 el supervisor de distribución no puede recargar el acueducto real', c.startswith('ERROR') and 'modelo hidráulico' in c, c[:160])
c = q(f"select (public.geoportal_redes_cargue_capas('{SUP}') ->> 'puede_cargar')")
reg('18 … pero ve «puede cargar» para las demás capas', c == 'true', c)

# ---------- verificación con datos y reversa con datos ----------
q(f"select public.geoportal_redes_geovisor_capas_fijar('{ADMIN}', 'supervisor_planta', 'acu_tramos', true, 'Arnés: el de planta también ve la red')")
v = q(open(ED('verificacion_redes_corte6a_editor.sql'), encoding='utf-8').read().split('-- =====================================================================', 2)[2].rstrip().rstrip(';'))
filas = [x for x in v.split('\n') if x]
reg('19 verificación con datos: todas OK', all(x.endswith('|OK') for x in filas if not x.startswith('INFO')), filas[-1])
c, out, _ = archivo(ED('reversa_redes_corte6a_editor.sql'))
reg('20 reversa con datos: se niega (ya hay cambios de las capas por omisión) y no cambia nada', c != 0 and 'se niega' in out and q(CONJ) == md5_6a_mig, out.strip().split('\n')[-1][:160])

ok = sum(1 for _, b, _ in res if b)
texto = '\n'.join(('OK    ' if b else 'FALLA ') + n + ((' · ' + d) if d else '') for n, b, d in res)
texto += f'\n\nRESULTADO: {ok} de {len(res)} — ' + ('SIN FALLAS' if ok == len(res) else f'{len(res) - ok} FALLA(S)') + '\n'
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write(texto)
print(f'\nRESULTADO: {ok} de {len(res)}')
