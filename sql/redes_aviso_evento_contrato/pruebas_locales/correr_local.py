#!/usr/bin/env python3
"""Arnés local del aviso de evento por contrato (ruta evento_contrato; Code A, localhost:55432, base redes_local = producción al 19-nov, huella 314112df…,
con los CHECK, llaves y disparadores de sus migraciones):
  · el ensayo (N de N … SIN FALLAS) y que no deja nada; huellas; migración; verificación; segunda migración; reversa (vuelve la huella anterior);
  · que SOLO AGREGA: ninguna función anterior cambia de texto;
  · como la ve producción (service_role, 30 s / 8 s), sobre la RED REAL: un evento SIMULADO (círculo de 300 m en el centro de la red, declarado con la RPC
    publicada) y contratos reales adentro y afuera. Tope local por contrato: 150 ms / 6 = 25 ms (producción es unas 6 veces más lenta).
La ruta de punta a punta (Edge real en Deno) va aparte: scripts/prueba_edge_evento_contrato.mjs.
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
NOMBRE = 'redes_aviso_evento_contrato'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_ANTES = '314112df87e4d649945fd3f611857025'
VIEJAS = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) from pg_proc p "
          "where (p.pronamespace in ('redes'::regnamespace, 'tecnica'::regnamespace) or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_%')) "
          "and p.prokind = 'f' and p.proname not in ('geoportal_redes_evento_contrato', 'f_eventos_del_contrato', 'f_evento_contrato_acceso')")
ADM, SD, CO, CA, OP = 'ztevc.arnes.adm@emdupar.gov.co', 'ztevc.arnes.sd@emdupar.gov.co', 'ztevc.arnes.comercial@emdupar.gov.co', 'ztevc.arnes.campo@emdupar.gov.co', 'ztevc.arnes.op@emdupar.gov.co'
T1 = 150 / 6      # la meta de producción (150 ms por contrato) entre 6: producción es unas 6 veces más lenta
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
ok('02 … y no deja nada (sigue la huella anterior, no están las funciones, ni un evento ni una fila de auditoría)',
   q(CONJ) == MD5_ANTES and q("select to_regprocedure('public.geoportal_redes_evento_contrato(text,text)')") == '' and q('select count(*) from redes.eventos_suspension') == '0'
   and q('select count(*) from public.geoportal_auditoria') == aud0)
filas = psql('-AtF', '|', '-f', archivo(f'huellas_solo_lectura_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok('03 las huellas antes: «MIS REPORTES (lista para el aviso)», las 3 nuevas no existen y las 5 que no se tocan son las publicadas', any('lista para el aviso' in f for f in filas)
   and sum('NO EXISTE (sin aplicar)' in f for f in filas) == 3 and sum('LA PUBLICADA' in f for f in filas) == 5 and not any('DISTINTA' in f or 'FALTA' in f for f in filas), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('04 la migración se aplica', p.returncode == 0, p.stderr)
ok('05 SOLO AGREGA: ninguna función anterior de redes, tecnica ni public.geoportal_* cambió de texto', q(VIEJAS) == viejas0)
filas = psql('-AtF', '|', '-f', archivo(f'huellas_solo_lectura_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok('06 las huellas después: «AVISO POR CONTRATO (aplicado)», 3 nuevas y las 5 publicadas igual', any('AVISO POR CONTRATO (aplicado)' in f for f in filas) and sum('NUEVA (aplicada)' in f for f in filas) == 3
   and sum('LA PUBLICADA' in f for f in filas) == 5, '\n'.join(filas))
filas = psql('-AtF', '|', '-f', archivo(f'verificacion_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok(f'07 la verificación: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('08 una segunda migración se niega', p.returncode != 0 and 'ya está aplicado' in p.stderr, p.stderr)
ok('09 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')

# ---------- como la ve producción, sobre la red real: un evento SIMULADO y contratos reales ----------
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{ADM}', 'ZTEVC arnés admin', 'admin', 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SD}', 'ZTEVC arnés supervisor', 'consulta', true, true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_comercial, horario, dias) values ('{CO}', 'ZTEVC arnés comercial', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values ('{CA}', 'ZTEVC arnés campo', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'ZTEVC arnés operador', 'consulta', true, 'sin_restriccion', 'todos')")
centro = json.loads(q("select jsonb_build_object('lat', round(ST_Y(ST_Centroid(ST_Extent(geom)))::numeric, 6), 'lon', round(ST_X(ST_Centroid(ST_Extent(geom)))::numeric, 6)) from redes.activo_vigente_mat where prefijo = 'RED' and sistema = 'acueducto'"))
dentro = q(f"select string_agg(ct.contrato, ',' order by ct.contrato) from (select ct.contrato from redes.contrato_tramo ct join redes.activo_vigente_mat m on m.activo_id = ct.activo_id "
           f"where ST_DWithin(m.geom::geography, ST_SetSRID(ST_MakePoint({centro['lon']}, {centro['lat']}), 4326)::geography, 150) order by ct.contrato limit 20) ct").split(',')
fuera = q(f"select string_agg(ct.contrato, ',' order by ct.contrato) from (select ct.contrato from redes.contrato_tramo ct join redes.activo_vigente_mat m on m.activo_id = ct.activo_id "
          f"where not ST_DWithin(m.geom::geography, ST_SetSRID(ST_MakePoint({centro['lon']}, {centro['lat']}), 4326)::geography, 1500) order by md5(ct.contrato) limit 20) ct").split(',')
ms, out, e = edge(f"select public.geoportal_redes_evento_contrato('{CO}', '{fuera[0]}')")
ok(f'10 antes del evento, un contrato real como la Edge ({ms} ms): sin evento', not e and json.loads(out)['en_evento'] is False and json.loads(out)['ubicado'] is True, e or out)
ms, out, e = edge("select public.geoportal_redes_evento_declarar('%s', %s)" % (SD, lit({'alcance': 'circulo', 'lat': centro['lat'], 'lon': centro['lon'], 'radio_m': 300,
                                                                                          'causa': 'ZTEVC arnés: fuga simulada en el centro'})))
ev = json.loads(out)['codigo'] if not e else None
ok(f'11 se declara un evento SIMULADO (círculo de 300 m en el centro de la red real) con la RPC publicada: {ev}, {q(f"select contratos from redes.eventos_suspension where codigo = %s" % repr(ev)) if ev else "?"} contratos', ev and len(dentro) == 20, e)
malos, tiempos = [], []
for c in dentro:
    ms, out, e = edge(f"select public.geoportal_redes_evento_contrato('{CO}', '{c}')")
    tiempos.append(ms)
    j = json.loads(out) if not e else {}
    if not (j.get('en_evento') and j['evento']['codigo'] == ev and j['evento']['zona'] == 'circulo'):
        malos.append(f'{c}: {e or out[:120]}')
for c in fuera:
    ms, out, e = edge(f"select public.geoportal_redes_evento_contrato('{CA}', '{c}')")
    tiempos.append(ms)
    if e or json.loads(out)['en_evento']:
        malos.append(f'{c}: {e or out[:120]}')
ok(f'12 como la Edge: los 20 contratos reales a menos de 150 m del centro están en {ev} y los 20 a más de 1,5 km no', not malos, '\n'.join(malos))
n_ev = int(q(f"select contratos from redes.eventos_suspension where codigo = '{ev}'"))
n_mio = int(q(f"select count(*) from redes.contrato_tramo ct where exists (select 1 from redes.f_eventos_del_contrato(ct.contrato) x join redes.eventos_suspension e on e.id = x.evento_id where e.codigo = '{ev}')"))
ok(f'13 MISMA REGLA DEL CORTE 15 sobre la red real: el evento contó {n_ev} contratos al declararse y esta consulta pone dentro exactamente {n_mio}', n_ev == n_mio and n_ev > 20, (n_ev, n_mio))
ok('14 el operador de Técnica y alguien sin permiso no consultan (42501)', '42501' in edge(f"select public.geoportal_redes_evento_contrato('{OP}', '{dentro[0]}')")[2]
   and '42501' in edge(f"select public.geoportal_redes_evento_contrato('ztevc.nadie@emdupar.gov.co', '{dentro[0]}')")[2] and '42501' in edge(f"select * from redes.f_eventos_del_contrato('{dentro[0]}')")[2])
aud = q('select count(*) from public.geoportal_auditoria')
frio, _, _ = edge(f"select public.geoportal_redes_evento_contrato('{CO}', '{dentro[1]}')")
lista = "array[" + ", ".join(f"'{c}'" for c in dentro + fuera) + "]"
# una sola sesión con el rol y los topes de la API, como las conexiones que PostgREST mantiene abiertas: cada contrato medido por separado
e = psql('-Atq', '-v', 'ON_ERROR_STOP=1', '-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'", '-c', f"""do $$ declare c text; t0 timestamptz; v numeric[] := '{{}}'; r jsonb; begin
                      foreach c in array {lista} loop t0 := clock_timestamp(); r := public.geoportal_redes_evento_contrato('{CO}', c); v := v || (extract(epoch from clock_timestamp() - t0) * 1000); end loop;
                      raise warning 'MEDIDA %|%|%', (select max(x) from unnest(v[2:]) x)::numeric(8,2), (select percentile_cont(0.5) within group (order by x) from unnest(v) x)::numeric(8,2), v[1]::numeric(8,2); end $$""").stderr
m = re.search(r'MEDIDA ([0-9.]+)\|([0-9.]+)\|([0-9.]+)', e)
out, e = (m.group(1) + '|' + m.group(2), '') if m else ('', e)
primera = float(m.group(3)) if m else 9e9
peor, med = (float(x) for x in out.split('|')) if not e else (9e9, 9e9)
ok(f'15 TIEMPOS como la Edge, en una sesión abierta (como las de PostgREST): 40 contratos reales, mediana {med} ms y, sin contar la primera, el más lento {peor} ms '
   f'(tope local {T1:.0f} ms). La primera de la sesión {primera} ms (prepara las funciones y PostGIS; tope local 150 ms). INFO: con una conexión NUEVA, {frio} ms contando abrir psql. Leer no audita',
   not e and peor < T1 and primera < 150 and q('select count(*) from public.geoportal_auditoria') == aud, e or out)
ms, out, e = edge(f"select public.geoportal_redes_evento_cerrar('{SD}', '{ev}', 'ZTEVC arnés: se reparó')")
_, out2, e2 = edge(f"select public.geoportal_redes_evento_contrato('{CO}', '{dentro[0]}')")
ok('16 cerrado el evento simulado, el contrato vuelve a «sin evento»', not e and not e2 and json.loads(out2)['en_evento'] is False, e or e2 or out2)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'reversa_{NOMBRE}_editor.sql'))
ok('17 la reversa se aplica: vuelve la huella anterior, las funciones anteriores siguen igual y el evento simulado no se toca',
   p.returncode == 0 and q(CONJ) == MD5_ANTES and q(VIEJAS) == viejas0 and q('select count(*) from redes.eventos_suspension') == '1', p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'reversa_{NOMBRE}_editor.sql'))
ok('18 una segunda reversa se niega', p.returncode != 0 and 'No hay nada que revertir' in p.stderr, p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('19 después de la reversa, la migración se vuelve a aplicar', p.returncode == 0, p.stderr)
rehacer()
malas = [r for r in res if not r[1]]
print(f'\nRESULTADO: {len(res) - len(malas)} de {len(res)} — ' + ('SIN FALLAS' if not malas else f'{len(malas)} FALLA(S)'))
