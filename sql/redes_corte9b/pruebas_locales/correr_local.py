#!/usr/bin/env python3
"""Arnés local del Corte 9b, Fase 1 (simulación de cierre; Code A, localhost:55432, base redes_local). Comprueba, sobre una base como producción
(Corte 10 publicado, huella aad5952c…, con los CHECK de producción de los dobles):
  · el ensayo (N de N … SIN FALLAS) y que no deja nada; la migración, la verificación (todas OK), que no se aplica dos veces y la reversa (vuelve la huella del 10);
  · public.predios_comercial es VISTA MATERIALIZADA y ningún archivo del paquete la escribe ni la refresca;
  · como la ve producción: la simulación por la RPC, una llamada por petición, con el rol de la API (service_role), statement_timeout 30 s y lock_timeout 8 s,
    sobre la red real cargada; FALLA si una pasa de 5 s / 6 = 833 ms en local (producción ~6 veces más lenta); quién simula;
  · pg-safeupdate.
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
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_10 = 'aad5952c27e13cc3ad45623279ba7085'
ADM, SD, OP, NA = 'zt9b.arnes.adm@emdupar.gov.co', 'zt9b.arnes.dist@emdupar.gov.co', 'zt9b.arnes.op@emdupar.gov.co', 'zt9b.arnes.nada@emdupar.gov.co'
TOPE_LOCAL = 5000 / 6
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
    """Una petición de la Edge: rol service_role con los topes de producción. Devuelve (ms, salida, error)."""
    t0 = time.time()
    p = psql('-Atq', '-v', 'ON_ERROR_STOP=1', '-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'", '-c', sql)
    return round((time.time() - t0) * 1000), p.stdout.strip(), (p.stderr.strip() if p.returncode else '')


# 1. ensayo
rehacer()
p = psql('-q', '-f', os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte9b_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — SIN FALLAS', p.stderr)
tiempos = (re.search(r'TIEMPOS[^\n]*', p.stderr) or [''])[0]
ok(f'01 el ensayo termina en el ERROR esperado: {m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS', m and m.group(1) == m.group(2) and 'esperado' in p.stderr, p.stderr[-1500:])
print('   ' + tiempos[:900])
ok('02 … y no deja nada (sigue la huella del 10 y no hay tabla de simulaciones)', q(CONJ) == MD5_10 and q("select to_regclass('redes.simulaciones_cierre')") == '')
ok('03 la base local tiene los CHECK de producción en los dobles (lista blanca, auditoría y personal de Técnica)',
   q("select count(*) from pg_constraint where conname in ('geoportal_lista_blanca_rol_check', 'geoportal_auditoria_email_nn', 'personal_tecnico_eventos_check1')") == '3')

# 2. la vista materializada de Comercial
rk = q("select coalesce((select relkind::text from pg_class where oid = to_regclass('public.predios_comercial')), 'no está')")
ok(f'04 public.predios_comercial: si está en la base, es vista materializada como en producción (aquí: {rk}; este corte no la lee ni la escribe)', rk in ('m', 'no está'))
sqls = [os.path.join(d, f) for d, _, fs in os.walk(RAIZ) for f in fs if f.endswith('.sql')]
ok('05 ningún archivo del paquete escribe ni refresca predios_comercial',
   not any(re.search(r'(insert\s+into|update|delete\s+from|refresh\s+materialized\s+view)\s+(public\.)?predios_comercial', open(f, encoding='utf-8').read(), re.I) for f in sqls))

# 3. huellas, migración, verificación, segunda vez
filas = psql('-AtF', '|', '-f', os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte9b_editor.sql')).stdout.strip().splitlines()
ok('06 las huellas antes de aplicar: «CORTE 10 (listo para el 9b)», la reemplazada sin cambiar, las nuevas no existen',
   any('CORTE 10 (listo para el 9b)' in f for f in filas) and sum('PRODUCCIÓN (sin cambiar)' in f for f in filas) == 2
   and sum('NO EXISTE (sin aplicar)' in f for f in filas) == 18 and any('NO EXISTEN (sin aplicar)' in f for f in filas) and not any('DISTINTA' in f or 'FALTA' in f for f in filas), '\n'.join(filas))
AV = "select md5(tecnica.f_avisos(true, true, '2026-11-17 15:00:00-05')::text)"
avisos_antes = q(AV)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte9b_editor.sql'))
ok('07 la migración se aplica', p.returncode == 0, p.stderr)
ok('07b Avisos del 12: sin válvulas cerradas, tecnica.f_avisos devuelve exactamente lo mismo que antes de la migración', q(AV) == avisos_antes)
filas = psql('-AtF', '|', '-f', os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte9b_editor.sql')).stdout.strip().splitlines()
ok('08 las huellas después: «CORTE 9b (aplicado)», 2 reemplazadas, 18 nuevas y las 6 tablas', any('CORTE 9b (aplicado)' in f for f in filas)
   and sum('CORTE 9b (reemplazada)' in f for f in filas) == 2 and sum('NUEVA (aplicada)' in f for f in filas) == 18 and any('EXISTEN (9b)' in f for f in filas), '\n'.join(filas))
filas = psql('-AtF', '|', '-f', os.path.join(RAIZ, 'verificacion_redes_corte9b_editor.sql')).stdout.strip().splitlines()
ok(f'09 la verificación: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK',
   filas and all(f.endswith('|OK') for f in filas if not f.split('|')[0].startswith('INFO')), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte9b_editor.sql'))
ok('10 una segunda migración se niega', p.returncode != 0 and 'ya está aplicado' in p.stderr, p.stderr)
ok('11 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')

# 4. como la ve producción
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{ADM}', 'ZT9B arnés admin', 'admin', 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SD}', 'ZT9B arnés supervisor', 'consulta', true, true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'ZT9B arnés operador', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{NA}', 'ZT9B arnés sin Técnica', 'consulta', 'sin_restriccion', 'todos')")
q(f"insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('{OP}', 'asignar_formulario', 'danos_fallas', '{ADM}')")
casos = q("""select string_agg(codigo, ',') from (
  (select m.codigo from redes.activo_vigente_mat m where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado order by md5(m.activo_id::text) limit 6)
  union all (select m.codigo from redes.tramo_nodos tn join redes.activo_vigente_mat m on m.activo_id = tn.activo_id and m.version = tn.version
              join redes.nodos n1 on n1.id = tn.nodo_ini join redes.activo_vigente_mat v1 on v1.activo_id = n1.activo_id and v1.prefijo = 'VAL'
              join redes.nodos n2 on n2.id = tn.nodo_fin join redes.activo_vigente_mat v2 on v2.activo_id = n2.activo_id and v2.prefijo = 'VAL'
             where m.cuenta_vigente and not m.retirado order by md5(m.activo_id::text) limit 4)
  union all (select m.codigo from redes.activo_vigente_mat m where m.prefijo in ('VAL', 'TAN', 'PTA') and m.cuenta_vigente and not m.retirado
               and exists (select 1 from redes.nodos n join redes.tramo_nodos t on n.id in (t.nodo_ini, t.nodo_fin) where n.activo_id = m.activo_id)
             order by md5(m.activo_id::text) limit 4)) x""").split(',')
medidas = []
for c in casos:
    ms, out, e = edge(f"select public.geoportal_redes_simulacion_cierre('{OP}', '{c}')")
    j = json.loads(out) if not e else {}
    medidas.append((c, ms, j.get('contratos_min'), j.get('contratos_max'), (j.get('estrecho') or {}).get('valvulas_total'), j.get('segmento_grande'), len(out), e[:120]))
peor = max(m[1] for m in medidas)
ok(f'12 {len(medidas)} simulaciones como la Edge (service_role, 30 s / 8 s) sobre la red real, sin errores: la más lenta {peor} ms (tope local {TOPE_LOCAL:.0f} ms = 5 s / 6)',
   all(not m[7] for m in medidas) and peor < TOPE_LOCAL, medidas)
for m in medidas:
    print(f'   {m[0]}: {m[1]} ms · {m[2]}–{m[3]} contratos · {m[4]} válvulas{" · segmento grande" if m[5] else ""} · {m[6] // 1024} kB {m[7]}')
ok('13 ninguna respuesta pasa de 64 kB (las listas tienen tope) ni trae la lista interna de contratos',
   max(m[6] for m in medidas) < 65536 and '_contratos' not in edge(f"select public.geoportal_redes_simulacion_cierre('{OP}', '{casos[0]}')")[1])
ok('14 alguien sin Técnica no simula; el supervisor sí', 'Acceso' in edge(f"select public.geoportal_redes_simulacion_cierre('{NA}', '{casos[0]}')")[2]
   or edge(f"select public.geoportal_redes_simulacion_cierre('{NA}', '{casos[0]}')")[2] != ''
   and not edge(f"select public.geoportal_redes_simulacion_cierre('{SD}', '{casos[0]}')")[2])
ok('15 la API no ve la tabla ni las funciones internas', 'permission denied' in edge('select count(*) from redes.simulaciones_cierre')[2]
   and 'permission denied' in edge("select redes.f_simular_cierre(1)")[2])

# 4b. Fase 1b: el cierre real como lo ve producción (una llamada por petición; el supervisor cierra las válvulas de 3 tramos reales entre dos válvulas)
TOPE_LECTURA = 1000 / 6
vals = q("""select string_agg(distinct v.codigo, ',') from (select tn.activo_id, tn.nodo_ini, tn.nodo_fin from redes.tramo_nodos tn
   join redes.activo_vigente_mat m on m.activo_id = tn.activo_id and m.version = tn.version and m.cuenta_vigente and not m.retirado
   join redes.nodos a1 on a1.id = tn.nodo_ini join redes.activo_vigente_mat b1 on b1.activo_id = a1.activo_id and b1.prefijo = 'VAL'
   join redes.nodos a2 on a2.id = tn.nodo_fin join redes.activo_vigente_mat b2 on b2.activo_id = a2.activo_id and b2.prefijo = 'VAL'
   order by md5(tn.activo_id::text) limit 3) t join redes.nodos n on n.id in (t.nodo_ini, t.nodo_fin) join redes.activo_vigente_mat v on v.activo_id = n.activo_id""").split(',')
man = []
for c in vals:
    ms, out, e = edge(f"select public.geoportal_redes_valvula_maniobra('{SD}', '{c}', 'cerrar', null, 'ZT9B arnés: prueba del cierre real')")
    man.append((c, ms, e[:150], json.loads(out)['vigente'] if not e else None))
ok(f'19 {len(man)} cierres reales como la Edge (cada uno saca la foto del corte): el más lento {max(m[1] for m in man)} ms (tope local {TOPE_LOCAL:.0f} ms)',
   all(not m[2] for m in man) and max(m[1] for m in man) < TOPE_LOCAL, man)
ms_v, out, e = edge(f"select public.geoportal_redes_cortes_vigentes('{SD}')")
cv = json.loads(out) if not e else {}
ok(f'20 cortes vigentes como la Edge ({ms_v} ms, tope local {TOPE_LECTURA:.0f} ms): {cv.get("resumen")}; {len(cv.get("zonas", []))} zonas; sin correos ni datos de suscriptores',
   not e and ms_v < TOPE_LECTURA and cv['hay'] and len(cv['valvulas']) == len(man) and '@' not in out and 'suscriptor' not in out, e or out[:300])
z = (cv.get('zonas') or [{'lat': 10.46, 'lon': -73.25}])[0]
tes = q(f"select floor(({z['lon']} + 180) / 360 * (1 << 15))::int || ',' || floor((1 - ln(tan(radians({z['lat']})) + 1 / cos(radians({z['lat']}))) / pi()) / 2 * (1 << 15))::int")
ms_t, out, e = edge(f"select public.geoportal_redes_geovisor_mvt_cortes('{SD}', 15, {tes})")
ok(f'21 la tesela del modo Afectaciones como la Edge ({ms_t} ms, {len(out) * 3 // 4} bytes; tope local {TOPE_LECTURA:.0f} ms)', not e and ms_t < TOPE_LECTURA and (len(out) > 0 or not cv.get('zonas')), e)
ms_a, out, e = edge(f"select public.geoportal_tec_avisos('{ADM}')")
ok(f'22 los Avisos completos del administrador como la Edge, con las válvulas cerradas ({ms_a} ms; tope local {TOPE_LECTURA:.0f} ms)', not e and ms_a < TOPE_LECTURA, e)
ok('23 el operador sin el geovisor no ve los cortes; la API no ve las tablas de maniobras ni de fotos',
   edge(f"select public.geoportal_redes_cortes_vigentes('{OP}')")[2] != '' and 'permission denied' in edge('select count(*) from redes.valvula_maniobras')[2]
   and 'permission denied' in edge('select count(*) from redes.corte_foto_tramos')[2])
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'reversa_redes_corte9b_editor.sql'))
ok('24 con maniobras guardadas, la reversa se niega (no borra datos)', p.returncode != 0 and 'no borra datos' in p.stderr, p.stderr)

# 5. reversa (sobre una base recién migrada, sin datos)
rehacer('con_9b')
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'reversa_redes_corte9b_editor.sql'))
ok('16 la reversa se aplica: vuelve la huella del 10 y tecnica.f_avisos del 12; no quedan tablas del 9b', p.returncode == 0 and q(CONJ) == MD5_10
   and q("select to_regclass('redes.simulaciones_cierre')::text || to_regclass('redes.valvula_maniobras')::text") == '' and q(AV) == avisos_antes, p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'reversa_redes_corte9b_editor.sql'))
ok('17 una segunda reversa se niega', p.returncode != 0 and 'No hay nada que revertir' in p.stderr, p.stderr)
rehacer('con_9b')
q("insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor) "
  "select gen_random_uuid(), 'DAN-999998', 'dano', 'fuga', 'acueducto', (select activo_id from redes.activo_vigente_mat where prefijo = 'RED' order by activo_id limit 1), "
  "10.46, -73.25, 'mapa', now(), 'medio', 'desconocida', 'zt9b@emdupar.gov.co'")      # un daño de prueba (la base local no trae daños)
q("insert into redes.simulaciones_cierre (dano_id, activo_id, red_huella, valvulas, contratos_min, contratos_max, segmento_grande, resultado, ms, autor) "
  "select (select id from redes.danos limit 1), (select id from redes.activos limit 1), md5('x'), 0, 0, 0, false, '{}', 0, 'zt9b@emdupar.gov.co' where exists (select 1 from redes.danos)")
if q('select count(*) from redes.simulaciones_cierre') != '0':
    p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'reversa_redes_corte9b_editor.sql'))
    ok('18 con simulaciones guardadas, la reversa se niega (no borra datos)', p.returncode != 0 and 'no borra datos' in p.stderr, p.stderr)
else:
    ok('18 con simulaciones guardadas, la reversa se niega (no borra datos) — sin daños en la base para probarlo', False, 'la base no tiene daños')
rehacer()

malas = [r for r in res if not r[1]]
print(f'\nRESULTADO: {len(res) - len(malas)} de {len(res)} — ' + ('SIN FALLAS' if not malas else f'{len(malas)} FALLA(S)'))
