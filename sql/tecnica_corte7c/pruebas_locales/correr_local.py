#!/usr/bin/env python3
"""Arnés local del Corte 7c (foto de la remisión y parámetros de químicos editables). Base: redes_local en localhost:55432, como producción con el 7a publicado.
huellas antes · ensayo (ERROR esperado, sin rastro) · migración · verificación · guardia · huellas después · reversa (exacta al 7a) · migrar de nuevo ·
las RPC como las ve producción (service_role, statement_timeout 30 s y lock_timeout 8 s) · reversa con datos (se niega).
Uso: python3 -I correr_local.py   → escribe ../resultados/sql_local.txt"""
import json
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
EDGE = ['-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'"]
SEP = '-- ====================================================================='
res = []


def archivo(nombre):
    p = subprocess.run([PSQL, '-d', 'redes_local', '-X', '-v', 'ON_ERROR_STOP=1', '-f', nombre], env=ENV, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def q(sql):
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip()


def edge(sql):
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtqX', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', *EDGE, '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip()), time.time() - t, p.returncode != 0


def reg(nombre, ok, detalle=''):
    res.append((nombre, bool(ok), detalle))
    print(('OK   ' if ok else 'FALLA'), nombre, ('· ' + detalle if detalle else ''), flush=True)


ED = lambda n: os.path.join(RAIZ, n)  # noqa: E731
consulta = lambda n: open(ED(n), encoding='utf-8').read().split(SEP, 2)[2].strip().rstrip(';')  # noqa: E731
huellas = lambda: q(f"select string_agg(objeto || '=' || estado, E'\\n') from ({consulta('huellas_solo_lectura_tecnica_corte7c_editor.sql')}) h")  # noqa: E731
ESTADO = ("select md5((select string_agg(pg_get_functiondef(p.oid), E'\\n' order by n.nspname, p.proname, p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
          "where n.nspname in ('tecnica', 'redes') or (n.nspname = 'public' and p.proname like 'geoportal\\_%')) || '|' || "
          "(select string_agg(table_schema || '.' || table_name || '.' || column_name, ',' order by table_schema, table_name, column_name) from information_schema.columns where table_schema = 'tecnica'))")
REDES = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
         "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_7a'], env=ENV, check=True, capture_output=True)
antes = q(ESTADO)
reg('00 base local con el 7a publicado (huella de redes 79f184a4…; en producción, con el 9a del Code B, es 4a46069f…: este corte no toca redes)', q(REDES) == '79f184a4fe37ed2baa67dac7f3dd9b3c' and len(antes) == 32)
h = huellas()
reg('01 huellas antes: 2 «CORTE 7a (sin cambiar)», 5 funciones y 3 objetos «NO EXISTE»', h.count('CORTE 7a (sin cambiar)') == 2 and h.count('NO EXISTE (sin aplicar)') == 8 and 'DISTINTA' not in h and 'FALTA' not in h, h.replace('\n', ' | ')[:300])
c, out = archivo(ED('ensayo_en_transaccion_tecnica_corte7c_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('02 ensayo: ERROR esperado, N de N SIN FALLAS', c != 0 and m and m.group(1) == m.group(2) and 'SIN FALLAS' in m.group(3), m.group(0) if m else out[-600:])
reg('03 el ensayo no deja rastro', q(ESTADO) == antes and q("select count(*) from public.geoportal_lista_blanca where email like 'prueba.tec9.%'") == '0' and q("select count(*) from tecnica.quimicos where nombre like 'ZT9%'") == '0'
    and q("select valor from tecnica.quimico_parametros where clave = 'desvio_pct'") == '25')
c, out = archivo(ED('migracion_tecnica_corte7c_editor.sql'))
reg('04 migración', c == 0, '' if c == 0 else out[-400:])
despues = q(ESTADO)
filas = [x for x in q(consulta('verificacion_tecnica_corte7c_editor.sql')).split('\n') if x]
reg('05 verificación: 8 OK y 2 INFO', len(filas) == 10 and sum(x.endswith('|OK') for x in filas) == 8, ' | '.join(x for x in filas if not x.endswith('|OK'))[:300])
c, out = archivo(ED('migracion_tecnica_corte7c_editor.sql'))
reg('06 guardia: migrar dos veces se niega', c != 0 and 'ya está aplicado' in out)
h = huellas()
reg('07 huellas después: 2 «CORTE 7c (reemplazada)», 5 «NUEVA» y 3 «EXISTE»', h.count('CORTE 7c (reemplazada)') == 2 and h.count('NUEVA (aplicada)') == 5 and h.count('EXISTE (aplicado)') == 3, h.replace('\n', ' | ')[:300])
reg('08 la huella de las funciones de redes no cambió con la migración', q(REDES) == '79f184a4fe37ed2baa67dac7f3dd9b3c')
c, out = archivo(ED('reversa_tecnica_corte7c_editor.sql'))
reg('09 reversa vacía: funciones y columnas de tecnica exactamente como en el 7a', c == 0 and q(ESTADO) == antes, out[-300:] if c else '')
c, out = archivo(ED('migracion_tecnica_corte7c_editor.sql'))
reg('10 migrar de nuevo después de la reversa: mismo resultado', c == 0 and q(ESTADO) == despues, out[-300:] if c else '')

# ---------- como las ve producción ----------
PLA, OP = 'arnes.planta9@emdupar.gov.co', 'arnes.oper9@emdupar.gov.co'
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values ('{PLA}', 'Arnés planta', 'consulta', true, true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'Arnés operador', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('{OP}', 'asignar_formulario', 'entrada_quimicos', '{PLA}')")
out, s, mal = edge(f"select public.geoportal_tec_quimico_remision_preparar('{OP}')")
ruta = json.loads(out)['ruta'] if not mal else ''
q(f"""insert into storage.objects (bucket_id, name, metadata) values ('tecnica-evidencias', '{ruta}', '{{"size": 420000, "mimetype": "image/jpeg"}}')""")
out2, s2, mal2 = edge(f"""select public.geoportal_tec_quimico_entrada('{OP}', '{{"quimico": "pac", "cantidad": 1.5, "unidad": "t", "remision": "R-77", "foto": "{ruta}"}}', 'arnes-7c-0001')""")
reg('11 Edge (service_role, 30 s y 8 s): el operador reserva la foto y registra la entrada con ella', not mal and not mal2 and q(f"select remision_foto from tecnica.quimico_movimientos where clave_envio = 'arnes-7c-0001'") == ruta
    and s + s2 < 2, f'{(s + s2) * 1000:.0f} ms' + (out2[:200] if mal2 else ''))
out, s, mal = edge(f"select public.geoportal_tec_quimico_historial('{PLA}', 'pac')")
reg('12 Edge: el historial del supervisor trae la ruta de la foto de esa entrada', not mal and any(m.get('remision_foto_ruta') == ruta for m in json.loads(out)['movimientos']), f'{s * 1000:.0f} ms')
out, s, mal = edge(f"select public.geoportal_tec_quimico_parametro_fijar('{PLA}', 'desvio_pct', 35, 'Arnés: el jefe de planta lo sube a 35')")
out2, _, mal2 = edge(f"select public.geoportal_tec_quimico_parametros('{PLA}')")
reg('13 Edge: el supervisor cambia el desvío a 35 % (un UPDATE con WHERE: pasa por pg-safeupdate) y la lista lo muestra con su último cambio', not mal and not mal2
    and json.loads(out2)['parametros'][0]['valor'] == 35 and json.loads(out2)['parametros'][0]['ultimo']['antes'] == 25, (out + out2)[:200] if mal or mal2 else f'{s * 1000:.0f} ms')
out, _, mal = edge(f"select public.geoportal_tec_quimico_parametro_fijar('{OP}', 'desvio_pct', 10, 'Arnés: el operador no puede')")
reg('14 Edge: el operador no cambia parámetros (42501)', mal and '42501' in out)
out, _, mal = edge('select count(*) from tecnica.quimico_parametro_eventos')
reg('15 la API no lee las tablas nuevas', mal)
filas = [x for x in q(consulta('verificacion_tecnica_corte7c_editor.sql')).split('\n') if x]
reg('16 verificación con datos: 8 OK', sum(x.endswith('|OK') for x in filas) == 8, filas[-1][:200])
c, out = archivo(ED('reversa_tecnica_corte7c_editor.sql'))
reg('17 reversa con datos: se niega y no cambia nada', c != 0 and 'se niega' in out and q(ESTADO) == despues)

ok = sum(1 for _, b, _ in res if b)
texto = '\n'.join(('OK    ' if b else 'FALLA ') + n + ((' · ' + d) if d else '') for n, b, d in res)
texto += f'\n\nRESULTADO: {ok} de {len(res)} — ' + ('SIN FALLAS' if ok == len(res) else f'{len(res) - ok} FALLA(S)') + '\n'
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write(texto)
print(f'\nRESULTADO: {ok} de {len(res)}')
