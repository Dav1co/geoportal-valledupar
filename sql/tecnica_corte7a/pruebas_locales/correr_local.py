#!/usr/bin/env python3
"""Arnés local del Corte 7a (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Como en el despliegue (todo hasta el 6b, con la carga real, la MUE y 111.950 contratos sintéticos) más caudales de Entrada de 3 días:
huellas antes · ensayo · migración · verificación · guardia · huellas después · reversa vacía (exacta al 6b) · migrar de nuevo · la capa de contratos con los
estados nuevos · un químico de punta a punta (PDF, inventario, entrada en toneladas, uso y la comparación con el caudal) · verificación con datos · reversa con datos.
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
    return q(f"select string_agg(objeto || '=' || estado, E'\\n') from ({open(ED('huellas_solo_lectura_tecnica_corte7a_editor.sql'), encoding='utf-8').read().split('-- =====================================================================', 2)[2].strip().rstrip(';')}) h")


def tesela_xy(z, lon, lat):
    n = 1 << z
    return int((lon + 180) / 360 * n), int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n)


# ---------- base como en vivo ----------
H6B = 'fca28bf695d1fcfa153f1113ce821528'
t0 = time.time()
subprocess.run(['sh', os.path.join(AQUI, 'base_chrome.sh'), 'solo_6b'], env=ENV, check=True, capture_output=True)
reg('00 base hasta el 6b con la carga real, contratos sintéticos y caudales de Entrada', q(CONJ) == H6B, f"{time.time() - t0:.0f} s")
h = huellas()
reg('01 huellas antes: «CORTE 6b (listo para el 7a)», 11 RPC y 7 objetos «NO EXISTE», 2 «CORTE 6b (sin cambiar)»',
    'CORTE 6b (listo para el 7a)' in h and h.count('NO EXISTE (sin aplicar)') == 18 and h.count('CORTE 6b (sin cambiar)') == 2 and 'DISTINTA' not in h, h.replace('\n', ' | ')[:300])
c, out, s = archivo(ED('ensayo_en_transaccion_tecnica_corte7a_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('02 ensayo sobre la base completa: ERROR esperado, N de N SIN FALLAS', c != 0 and m and m.group(1) == m.group(2) and 'SIN FALLAS' in m.group(3), (m.group(0) if m else out[-600:]) + f' · {s:.1f} s')
reg('03 el ensayo no deja rastro', q("select to_regclass('tecnica.quimico_movimientos') is null") == 't' and q(CONJ) == H6B
    and q("select count(*) from public.geoportal_auditoria where email like 'prueba.tec7.%'") == '0' and q("select count(*) from tecnica.quimicos where nombre like 'ZT7%'") == '0')
c, out, s = archivo(ED('migracion_tecnica_corte7a_editor.sql'))
reg('04 migración', c == 0, f'{s:.1f} s' + ('' if c == 0 else ' · ' + out[-400:]))
md5_7a = q(CONJ)
v = q(open(ED('verificacion_tecnica_corte7a_editor.sql'), encoding='utf-8').read().split('-- =====================================================================', 2)[2].rstrip().rstrip(';'))
filas = [x for x in v.split('\n') if x]
reg('05 verificación: todas las filas OK', all(x.endswith('|OK') for x in filas if not x.startswith('INFO')), ' | '.join(filas)[-300:])
c, out, _ = archivo(ED('migracion_tecnica_corte7a_editor.sql'))
reg('06 guardia: migrar dos veces se niega', c != 0 and 'Corte 7a ya está aplicado' in out, out.strip().split('\n')[-1][:160])
h = huellas()
reg('07 huellas después: «CORTE 7a (aplicado)», 11 «NUEVA», 2 «CORTE 7a (reemplazada)», 7 «EXISTE»',
    'CORTE 7a (aplicado)' in h and h.count('NUEVA (aplicada)') == 11 and h.count('CORTE 7a (reemplazada)') == 2 and h.count('EXISTE (aplicado)') == 7, h.replace('\n', ' | ')[:300])
c, out, _ = archivo(ED('reversa_tecnica_corte7a_editor.sql'))
reg('08 reversa vacía: exacta al 6b, sin las tablas de químicos, hipoclorito desactivado, el bucket vacío se queda',
    c == 0 and q(CONJ) == H6B and q("select to_regclass('tecnica.quimico_movimientos') is null") == 't'
    and q("select activo from tecnica.quimicos where codigo = 'hipoclorito_calcio'") == 'f' and q("select count(*) from storage.buckets where id = 'tecnica-evidencias'") == '1', out[-300:] if c else '')
c, out, _ = archivo(ED('migracion_tecnica_corte7a_editor.sql'))
reg('09 migrar de nuevo después de la reversa (reutiliza el bucket y el hipoclorito)', c == 0 and q(CONJ) == md5_7a, out[-300:] if c else '')
q("update tecnica.quimicos set activo = true where codigo = 'hipoclorito_calcio'")      # (una reversa real lo deja desactivado; aquí se vuelve a la base)

# ---------- la capa de contratos con los estados nuevos ----------
SUP = 'arnes.dist@emdupar.gov.co'; PLA = 'arnes.planta@emdupar.gov.co'
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SUP}', 'Arnés distribución', 'consulta', true, true, 'sin_restriccion', 'todos') on conflict do nothing")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values ('{PLA}', 'Arnés planta', 'consulta', true, true, 'sin_restriccion', 'todos') on conflict do nothing")
t = time.time(); q(f"select public.geoportal_redes_geovisor('{SUP}')"); s = time.time() - t
est = q("select string_agg(estado || '=' || n, ' ' order by estado) from (select estado, count(*) n from redes.contratos_capa group by 1) x")
reg('10 la primera apertura rehace la capa y aparecen los suspendidos como estado propio', 'suspendido=' in est and 'otro=' not in est, f'{est} · {s:.1f} s')
c1 = q("select contrato from redes.contratos_capa where estado = 'activo' order by contrato limit 1")
tj = json.loads(q(f"select public.geoportal_redes_contrato_tarjeta('{PLA}', '{c1}')"))
reg('11 el supervisor de planta: tarjeta sin nombre ni dirección', tj['datos_personales'] is False and tj['suscriptor']['nombre'] is None and 'SUSCRIPTOR' not in json.dumps(tj))

# ---------- un químico de punta a punta ----------
ruta = json.loads(q(f"select public.geoportal_tec_quimico_ficha_preparar('{PLA}')"))['ruta']
q(f"""insert into storage.objects (bucket_id, name, metadata) values ('tecnica-evidencias', '{ruta}', '{{"size": 350000, "mimetype": "application/pdf"}}')""")
r = q(f"select public.geoportal_tec_quimico_fijar('{PLA}', 'pac', '{{\"dosis_optima_ppm\": 18}}', '{ruta}', 'Arnés: dosis óptima del jar test')".replace('\\"', '"'))
reg('12 el supervisor de planta fija la dosis óptima del PAC con su PDF', 'dosis_optima' in r, r[:200])
q(f"select public.geoportal_tec_quimico_inventario('{PLA}', 'pac', 12, 't', current_date, 'Arnés: conteo físico de la bodega')")
q(f"""select public.geoportal_tec_quimico_entrada('{PLA}', '{{"quimico": "pac", "cantidad": 5, "unidad": "t"}}', null)""")
q(f"""select public.geoportal_tec_quimico_uso('{PLA}', '{{"quimico": "pac", "cantidad": 300, "para_que": "dosificacion", "planta": "huaricha"}}', null)""")
reg('13 saldo del PAC: 12 t + 5 t − 300 kg = 16.700 kg', q("select saldo_kg from tecnica.v_quimico_saldo where codigo = 'pac'") == '16700')
t = time.time(); cmp = json.loads(q(f"select public.geoportal_tec_quimicos_comparacion('{PLA}', current_date - 13, current_date)")); s = time.time() - t
fil = [f for f in cmp['filas'] if f['quimico'] == 'pac' and f['planta'] == 'huaricha']
reg('14 la comparación del PAC en Huaricha con el caudal sintético (1.000 L/s): esperado 18 × 86.400 / 1.000 = 1.555,2 kg por día; usado 300 hoy y marca',
    any(f['esperado_kg'] == 1555.2 and f['usado_kg'] == 300 and f['marca'] for f in fil) and s < 2, f'{len(cmp["filas"])} filas · {s * 1000:.0f} ms · {fil[:1]}')
v = q(open(ED('verificacion_tecnica_corte7a_editor.sql'), encoding='utf-8').read().split('-- =====================================================================', 2)[2].rstrip().rstrip(';'))
filas = [x for x in v.split('\n') if x]
reg('15 verificación con datos: todas OK', all(x.endswith('|OK') for x in filas if not x.startswith('INFO')), filas[-1])
c, out, _ = archivo(ED('reversa_tecnica_corte7a_editor.sql'))
reg('16 reversa con datos: se niega (ya hay movimientos) y no cambia nada', c != 0 and 'se niega' in out and q(CONJ) == md5_7a, out.strip().split('\n')[-1][:160])

ok = sum(1 for _, b, _ in res if b)
texto = '\n'.join(('OK    ' if b else 'FALLA ') + n + ((' · ' + d) if d else '') for n, b, d in res)
texto += f'\n\nRESULTADO: {ok} de {len(res)} — ' + ('SIN FALLAS' if ok == len(res) else f'{len(res) - ok} FALLA(S)') + '\n'
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write(texto)
print(f'\nRESULTADO: {ok} de {len(res)}')
