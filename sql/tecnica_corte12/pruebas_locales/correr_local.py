#!/usr/bin/env python3
"""Arnés local del Corte 12 (Avisos y cola de avisos de salida). Base: redes_local en localhost:55432, como producción hoy (7a + 9a + 9a-bis + 7c).
huellas antes · ensayo (ERROR esperado, sin rastro) · migración · verificación · guardia · huellas después · reversa · migrar de nuevo ·
las RPC como las ve producción (service_role, statement_timeout 30 s y lock_timeout 8 s) · el rol del Dell · TIEMPO con volumen grande · reversa con datos (se niega).
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
DELL = ['-c', 'set role dell_avisos', '-c', "set statement_timeout = '15s'", '-c', "set lock_timeout = '8s'"]
SEP = '-- ====================================================================='
res = []


def archivo(nombre):
    p = subprocess.run([PSQL, '-d', 'redes_local', '-X', '-v', 'ON_ERROR_STOP=1', '-f', nombre], env=ENV, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def q(sql):
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-v', 'ON_ERROR_STOP=1', '-c', sql], env=ENV, capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip()


def como(rol, sql):
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtqX', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', *rol, '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip()), time.time() - t, p.returncode != 0


edge = lambda sql: como(EDGE, sql)  # noqa: E731
dell = lambda sql: como(DELL, sql)  # noqa: E731


def reg(nombre, ok, detalle=''):
    res.append((nombre, bool(ok), detalle))
    print(('OK   ' if ok else 'FALLA'), nombre, ('· ' + detalle if detalle else ''), flush=True)


ED = lambda n: os.path.join(RAIZ, n)  # noqa: E731
consulta = lambda n: open(ED(n), encoding='utf-8').read().split(SEP, 2)[2].strip().rstrip(';')  # noqa: E731
huellas = lambda: q(f"select string_agg(objeto || '=' || estado, E'\\n') from ({consulta('huellas_solo_lectura_tecnica_corte12_editor.sql')}) h")  # noqa: E731
verif = lambda: q(f"select string_agg(que || '=' || resultado, E'\\n') from ({consulta('verificacion_tecnica_corte12_editor.sql')}) v")  # noqa: E731
ESTADO = ("select md5((select string_agg(pg_get_functiondef(p.oid), E'\\n' order by n.nspname, p.proname, p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
          "where n.nspname in ('tecnica', 'redes') or (n.nspname = 'public' and p.proname like 'geoportal\\_%')) || '|' || "
          "(select string_agg(table_schema || '.' || table_name || '.' || column_name, ',' order by table_schema, table_name, column_name) from information_schema.columns where table_schema = 'tecnica'))")
REDES = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
         "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
HUELLA_PROD = '5fd6d00efdaa1a798e2628a2cde23c61'      # con el 5d del Code B publicado
ADM, SP, SD, OP = 'zt.admin@emdupar.gov.co', 'zt.planta@emdupar.gov.co', 'zt.dist@emdupar.gov.co', 'zt.oper@emdupar.gov.co'

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'sin_12'], env=ENV, check=True, capture_output=True)
antes = q(ESTADO)
reg('00 base local como producción (7a + 9a + 9a-bis + 7c + 8 + 5d): huella de redes ' + HUELLA_PROD[:8] + '…', q(REDES) == HUELLA_PROD)
h = huellas()
reg('01 huellas antes: las 2 de redes «SIN CAMBIAR»; 16 funciones, 6 objetos y el rol «NO EXISTE»', h.count('SIN CAMBIAR') == 2 and h.count('NO EXISTE (sin aplicar)') == 23 and 'DISTINTA' not in h and 'FALTA' not in h
    and 'IGUAL AL DEL ENCARGO' in h, h.replace('\n', ' | ')[:300])
c, out = archivo(ED('ensayo_en_transaccion_tecnica_corte12_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
t = re.search(r'TIEMPOS: .*', out)
reg('02 ensayo: ERROR esperado, N de N SIN FALLAS (con TIEMPOS)', c != 0 and m and m.group(1) == m.group(2) and 'SIN FALLAS' in m.group(3) and t,
    (m.group(0) if m else out[-600:]) + (' · ' + t.group(0) if t else ''))
reg('03 el ensayo no deja rastro (ni el rol del Dell)', q(ESTADO) == antes and q("select count(*) from public.geoportal_lista_blanca where email like 'prueba.tec12.%'") == '0'
    and q("select count(*) from pg_roles where rolname = 'dell_avisos'") == '0' and q("select count(*) from redes.danos where codigo like 'DAN-9912%'") == '0')
c, out = archivo(ED('migracion_tecnica_corte12_editor.sql'))
reg('04 migración', c == 0, out[-300:] if c else '')
v = verif()
reg('05 verificación: todas OK', v.count('=OK') == 8 and 'FALLA' not in v, v.replace('\n', ' | ')[:400])
c, out = archivo(ED('migracion_tecnica_corte12_editor.sql'))
reg('06 la guardia no deja aplicar dos veces', c != 0 and 'ya está aplicado' in out, out[-200:])
h = huellas()
reg('07 huellas después: 2 «SIN CAMBIAR», 16 «NUEVA», 6 «EXISTE» y el rol «EXISTE (nologin)»', h.count('SIN CAMBIAR') == 2 and h.count('NUEVA (aplicada)') == 16 and h.count('EXISTE (aplicado)') == 6
    and 'EXISTE (nologin)' in h, h.replace('\n', ' | ')[:300])
reg('08 la huella de redes no cambió', q(REDES) == HUELLA_PROD)
c, out = archivo(ED('reversa_tecnica_corte12_editor.sql'))
reg('09 reversa sin datos: deja la base como estaba (y sin el rol)', c == 0 and q(ESTADO) == antes and q("select count(*) from pg_roles where rolname = 'dell_avisos'") == '0', out[-300:] if c else '')
c, out = archivo(ED('migracion_tecnica_corte12_editor.sql'))
reg('10 migrar de nuevo después de la reversa', c == 0, out[-300:] if c else '')

# ---------- las RPC como las ve producción ----------
r, s, e = edge(f"select public.geoportal_tec_avisos('{ADM}')")
j = json.loads(r) if not e else {}
reg('11 administrador (service_role, 30 s / 8 s): avisos de planta, distribución y personal', not e and j['areas']['planta'] and j['areas']['distribucion'], f'{j.get("total")} avisos, {round(s * 1000)} ms con psql')
r, s, e = edge(f"select public.geoportal_tec_avisos('{SP}')")
j = json.loads(r) if not e else {}
reg('12 supervisor de planta: sin avisos de distribución', not e and not j['areas']['distribucion'] and all(a['area'] != 'distribucion' for a in j['avisos']), r[:200] if e else '')
r, s, e = edge(f"select public.geoportal_tec_avisos('{SD}')")
reg('13 supervisor de distribución: sin avisos de planta', not e and all(a['area'] != 'planta' for a in json.loads(r)['avisos']), r[:200] if e else '')
r, s, e = edge(f"select public.geoportal_tec_avisos('{OP}')")
reg('14 operador: 42501', e and '42501' in r, r[:160])
r, s, e = edge(f"select public.geoportal_tec_aviso_parametro_fijar('{SD}', 'dano_alto_rojo_h', 8, 'Arnés: el supervisor de distribución alarga el rojo')")
reg('15 el supervisor de distribución cambia un plazo de su área (con el rol de la API)', not e and json.loads(r)['valor'] == 8, r[:200])
r, s, e = edge(f"select public.geoportal_tec_quimico_minimo_fijar('{SP}', 'pac', 1000, 'Arnés: mínimo del PAC en bodega')")
reg('16 el supervisor de planta fija el saldo mínimo del PAC', not e, r[:200])
r, s, e = edge("select tecnica.avisos_tomar(5, 300)")
reg('17 la API (service_role) no puede tomar la cola del Dell', e and '42501' in r, r[:160])
r, s, e = edge("select count(*) from tecnica.aviso_parametros")
reg('18 la API no lee las tablas de los avisos', e and '42501' in r, r[:160])

# ---------- el rol del Dell ----------
q("insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor) "
  "select gen_random_uuid(), 'DAN-991299', 'dano', (select codigo from redes.tipos_dano where activo and 'acueducto' = any (sistemas) order by orden limit 1), 'acueducto', "
  "(select activo_id from redes.activo_vigente_mat where sistema = 'acueducto' and not retirado order by activo_id limit 1), 10.47, -73.24, 'mapa', clock_timestamp() - interval '10 minutes', 'alto', 'desconocida', 'arnes'")
r, s, e = dell("select aviso_id || '|' || lease_id || '|' || (mensaje ->> 'dano') from tecnica.avisos_tomar(5, 300)")
reg('19 el Dell (rol dell_avisos, search_path pg_catalog, 15 s) toma el aviso del daño alto nuevo', not e and 'DAN-991299' in r, r[:200])
if not e and r:
    av, lease, _ = r.split('\n')[0].split('|')
    r2, s, e2 = dell(f"select tecnica.avisos_marcar('{av}', '{lease}', 'enviado', '{{\"telegram\":\"ok\"}}')")
    reg('20 el Dell lo marca enviado', not e2 and r2 == 'enviado', r2[:160])
r, s, e = dell("select public.geoportal_tec_avisos('zt.admin@emdupar.gov.co')")
reg('21 el Dell no puede leer los avisos de pantalla', e and '42501' in r, r[:160])
r, s, e = dell("select count(*) from tecnica.avisos_salida")
reg('22 el Dell no lee las tablas', e and '42501' in r, r[:160])

# ---------- TIEMPO con volumen grande (lo que puede crecer en producción) ----------
q("""do $$ begin
  insert into redes.activo_eventos (activo_id, tipo, motivo, autor)
  select m.activo_id, case when random() < 0.7 then 'por_verificar' else 'verificar' end, 'Arnés: volumen de verificación del Plan Maestro', 'arnes'
    from (select activo_id from redes.activo_vigente_mat order by activo_id limit 6000) m;
  insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor)
  select gen_random_uuid(), 'DAN-98' || lpad(g::text, 4, '0'), 'dano', (select codigo from redes.tipos_dano where activo and 'acueducto' = any (sistemas) order by orden limit 1), 'acueducto',
         (select activo_id from redes.activo_vigente_mat where sistema = 'acueducto' and not retirado order by activo_id limit 1), 10.47, -73.24, 'mapa',
         clock_timestamp() - make_interval(hours => g % 300), (array['alto', 'medio', 'bajo'])[1 + g % 3], 'desconocida', 'arnes'
    from generate_series(1, 2000) g;
  analyze redes.activo_eventos; analyze redes.danos;
end $$""")
vol = q("select (select count(*) from redes.activo_eventos) || ' eventos de activos, ' || (select count(*) from redes.danos) || ' daños, ' || (select count(*) from redes.activo_vigente_mat) || ' activos'")
peor = 0
for _ in range(3):
    r, s, e = edge(f"select (public.geoportal_tec_avisos('{ADM}') ->> 'ms')::numeric")
    peor = max(peor, float(r) if not e else 99999)
reg('23 TIEMPO: todos los avisos del administrador con ' + vol + ' (producción: ≈1.750 por verificar y pocos daños): menos de 170 ms en local (producción ~6× más lenta: tope 1 s)', peor < 170, f'{round(peor)} ms (el peor de 3, medido en la base)')
r, s, e = dell("select count(*) from tecnica.avisos_tomar(20, 300)")
reg('24 TIEMPO: el Dell encola y toma con 2.000 daños abiertos en menos de 15 s (su tope)', not e, f'{round(s * 1000)} ms con psql · {r}')
reg('25 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')
c, out = archivo(ED('reversa_tecnica_corte12_editor.sql'))
reg('26 reversa con datos: se niega (nada se borra)', c != 0 and 'se niega' in out, out[-200:])

bien = sum(1 for _, ok, _ in res if ok)
lineas = [f"{'OK   ' if ok else 'FALLA'} {n}{(' · ' + d) if d else ''}" for n, ok, d in res]
lineas.append(f'RESULTADO: {bien} de {len(res)} — ' + ('SIN FALLAS' if bien == len(res) else f'{len(res) - bien} FALLA(S)'))
os.makedirs(os.path.join(RAIZ, 'resultados'), exist_ok=True)
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write('\n'.join(lineas) + '\n')
print(lineas[-1])
