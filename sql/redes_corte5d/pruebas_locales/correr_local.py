#!/usr/bin/env python3
"""Arnés local del Corte 5d (Code B, clúster propio 55442; nunca el 55432 de Code A). Comprueba, sobre una base como producción:
  · el ensayo (N de N … SIN FALLAS), la migración, la verificación (todas OK), que no se aplica dos veces y la reversa (vuelve la huella del 9a-bis);
  · public.predios_comercial es VISTA MATERIALIZADA, como en producción, y escribir en ella falla (nadie la toca);
  · como las ve producción: la carga completa (22.978 reportes sintéticos, contratos del catastro de la base) por las RPC, una llamada por petición, con el rol de la
    API (service_role), statement_timeout 30 s y lock_timeout 8 s; mide cada paso y la capa del geovisor (12 meses);
  · la reversa se niega si ya hay cargas de la 116; pg-safeupdate (ninguna función con DELETE o UPDATE sin WHERE).
  · si existe el paquete de carga inicial generado desde el archivo real (carga_116.py), corre su ENSAYO y anota los tiempos (solo para medir).
Uso: python3 -I correr_local.py"""
import json
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = os.environ.get('BASE_B', 'emdupar_b')
ENV = dict(os.environ, PGHOST='localhost', PGPORT=os.environ.get('PGPORT_B', '55442'), PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
assert ENV['PGPORT'] != '55432', 'El puerto 55432 es de Code A'
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
CARGA_REAL = os.path.expanduser('~/geoportal-consultas/tecnica/paquete_fase1/corte5d/carga_116/ensayo_carga_116.sql')
SD = 'zt5d.arnes.dist@emdupar.gov.co'
res = []


def ok(nombre, cond, det=''):
    res.append((nombre, bool(cond), str(det)[:400]))
    print(('OK    ' if cond else 'FALLA ') + nombre + ('' if cond else ' → ' + str(det)[:400]), flush=True)


def psql(*args, base=BASE, check=False):
    return subprocess.run([PSQL, '-d', base, '-X', *args], env=ENV, capture_output=True, text=True, check=check)


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
p = psql('-q', '-f', os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte5d_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — SIN FALLAS', p.stderr)
tiempos_ensayo = (re.search(r'TIEMPOS[^\n]*', p.stderr) or [''])[0]
ok('01 el ensayo termina en el ERROR esperado: N de N … SIN FALLAS', m and m.group(1) == m.group(2) and 'esperado' in p.stderr, p.stderr[-800:])
ok('02 … y no deja nada (sigue la huella del 9a-bis y no hay tablas de la 116)', q(CONJ) == '814eac39ac5deae2943751b8c190f969' and q("select to_regclass('redes.l116_reportes')") == '')

# 2. la vista materializada de Comercial
ok('03 public.predios_comercial es vista materializada, como en producción', q("select relkind from pg_class where oid = 'public.predios_comercial'::regclass") == 'm')
p = psql('-c', "insert into public.predios_comercial (cod_usuario) values ('1')")
ok('04 escribir en ella falla (ningún paquete la escribe ni la refresca)', p.returncode != 0 and 'materialized view' in p.stderr, p.stderr)
ok('05 ningún archivo del paquete escribe ni refresca predios_comercial',
   not any(re.search(r'(insert\s+into|update|delete\s+from|refresh\s+materialized\s+view)\s+(public\.)?predios_comercial', open(os.path.join(RAIZ, f), encoding='utf-8').read(), re.I)
           for f in os.listdir(RAIZ) if f.endswith('.sql')))

# 3. migración, verificación, segunda vez
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte5d_editor.sql'))
ok('06 la migración se aplica', p.returncode == 0, p.stderr)
filas = psql('-AtF', '|', '-f', os.path.join(RAIZ, 'verificacion_redes_corte5d_editor.sql')).stdout.strip().splitlines()
ok('07 la verificación: todas las filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte5d_editor.sql'))
ok('08 una segunda migración se niega', p.returncode != 0 and 'ya está aplicado' in p.stderr, p.stderr)
ok('09 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')

# 4. como las ve producción: la carga completa por las RPC
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SD}', 'ZT5D arnés', 'consulta', true, true, 'sin_restriccion', 'todos')")
cods = q("select string_agg(cod_usuario, ',') from (select distinct cod_usuario from public.catastro_valledupar where cod_usuario ~ '^[0-9]{1,8}$' and cod_usuario not in ('0', '99999999') order by 1 limit 20000) x").split(',')
N = 22978
filas_v = [{'orden': i, 'wkt': None, 'atributos': {
    'REPORTE': 996000000 + i, 'ESTADO': 'Registrado' if i % 11 == 0 else 'Atendido',
    'FECHA_REGISTRO': time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(time.time() - 5 * 3600 - (i % 360) * 86400 - (i % 1440) * 60)),
    'CONTRATO': ('9960' + str(i)) if i % 7 == 0 else cods[(i * 7919) % len(cods)], 'NOMBRE': 'ZT5D NOMBRE QUE NO SE GUARDA',
    'DIRECCION': f'ZT5D DIR {i}', 'BARRIO': f'ZT5D BARRIO {i % 50}', 'COMUNA': 'COMUNA 5', 'DESC_CAUSAL': f'ZT5D CAUSAL {i % 29}',
    'SERVICIO': 'Alcantarillado' if i % 3 == 0 else 'Acueducto'}} for i in range(1, N + 1)]
ms, out, e = edge(f"select public.geoportal_redes_cargue_iniciar('{SD}', 'linea_116', '{'ab' * 32}', 'xlsx', 4326, 'reporte', {N}, 'ZT5D arnés')")
carga = json.loads(out)['carga_id'] if not e else None
ok(f'10 iniciar como la Edge ({ms} ms)', carga and ms < 8000, e)
peor = 0
errores = []
for k in range(0, N, 200):
    lote = json.dumps(filas_v[k:k + 200], ensure_ascii=False).replace("'", "''")
    ms, out, e = edge(f"select public.geoportal_redes_carga_lote('{SD}', {carga}, '{lote}'::jsonb)")
    peor = max(peor, ms)
    if e:
        errores.append(e)
ok(f'11 los {N // 200 + 1} lotes como la Edge, cada uno en menos de 8 s (el más lento, con el arranque de psql: {peor} ms)', not errores and peor < 8000, errores[:2])
ok('12 NOMBRE no llegó a la base (ninguna fila de la carga lo guarda)', q(f"select count(*) from redes.carga_filas where carga_id = {carga} and (atributos ? 'nombre' or atributos ? 'NOMBRE' or atributos::text like '%NOMBRE QUE NO%')") == '0')
ms_r, out, e = edge(f"select public.geoportal_redes_carga_resumen('{SD}', {carga})")
r = json.loads(out) if not e else {}
ok(f'13 el resumen como la Edge, en menos de 30 s ({ms_r} ms)', not e and r.get('lista_para_publicar') and ms_r < 30000, e or r.get('bloqueos'))
ms_p, out, e = edge(f"select public.geoportal_redes_carga_publicar('{SD}', {carga}, 'ZT5D publicación del arnés')")
pub = json.loads(out) if not e else {}
ok(f'14 la publicación como la Edge, en menos de 30 s ({ms_p} ms): {pub.get("nuevos")} nuevos, ubicación {pub.get("ubicacion")}', not e and pub.get('nuevos') == N and ms_p < 30000, e)
ms_c, out, e = edge(f"select public.geoportal_redes_geovisor_capa('{SD}', 'pqr_116', (current_date - interval '12 months')::date, current_date)")
ms_h, out2, e2 = edge(f"select public.geoportal_redes_geovisor_capa('{SD}', 'pqr_116', null, null)")
ok(f'15 la capa del geovisor (12 meses: {ms_c} ms; hoy: {ms_h} ms) en menos de 8 s, sin dirección, barrio ni nombre', not e and not e2 and max(ms_c, ms_h) < 8000
   and 'ZT5D DIR' not in out and 'ZT5D BARRIO' not in out and 'NOMBRE' not in out, e or e2)
# segunda carga del mismo volumen: todo igual salvo 1.000 cambios de estado (el caso de cada día o cada mes)
for f in filas_v[:1000]:
    f['atributos']['ESTADO'] = 'Atendido' if f['atributos']['ESTADO'] == 'Registrado' else 'Registrado'
ms, out, e = edge(f"select public.geoportal_redes_cargue_iniciar('{SD}', 'linea_116', '{'cd' * 32}', 'xlsx', 4326, 'reporte', {N}, 'ZT5D arnés 2')")
carga2 = json.loads(out)['carga_id']
for k in range(0, N, 200):
    edge(f"select public.geoportal_redes_carga_lote('{SD}', {carga2}, '{json.dumps(filas_v[k:k + 200], ensure_ascii=False).replace(chr(39), chr(39) * 2)}'::jsonb)")
ms_r2, out, e = edge(f"select public.geoportal_redes_carga_resumen('{SD}', {carga2})")
r2 = json.loads(out) if not e else {}
ms_p2, out, e2 = edge(f"select public.geoportal_redes_carga_publicar('{SD}', {carga2}, 'ZT5D segunda publicación del arnés')")
ok(f'16 la segunda carga completa reconoce todo por el número: 0 nuevos, 1.000 cambios de estado, {N - 1000} iguales (resumen {ms_r2} ms, publicar {ms_p2} ms)',
   not e and not e2 and r2.get('frente_a_vigente', {}).get('nuevo') == 0 and r2['frente_a_vigente'].get('estado') == 1000 and r2['frente_a_vigente'].get('igual') == N - 1000
   and max(ms_r2, ms_p2) < 30000, e or e2 or r2.get('frente_a_vigente'))
ok('17 los cambios de estado son eventos (nada se borra): 1.000 eventos «estado» y 22.978 «alta»',
   q("select count(*) filter (where tipo = 'estado') || '|' || count(*) filter (where tipo = 'alta') from redes.l116_eventos") == f'1000|{N}')

# 5. la reversa se niega con datos; sin datos, vuelve la huella
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'reversa_redes_corte5d_editor.sql'))
ok('18 la reversa se niega si ya hay cargas de la 116 (no borra datos)', p.returncode != 0 and 'Ya hay cargas de la línea 116' in p.stderr, p.stderr)
rehacer('con_5d')
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'reversa_redes_corte5d_editor.sql'))
ok('19 sin cargas, la reversa deja la huella del 9a-bis y la capa pqr_116 como estaba', p.returncode == 0 and q(CONJ) == '814eac39ac5deae2943751b8c190f969'
   and q("select fuente || '|' || estado from redes.geovisor_capas where codigo = 'pqr_116'") == 'preparada|espera_dato', p.stderr)
huellas = psql('-AtF', '|', '-f', os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte5d_editor.sql')).stdout
ok('20 las huellas después de la reversa dicen «listo para el 5d» y nada «DISTINTA»', 'CORTE 9a-bis (listo para el 5d)' in huellas and 'DISTINTA' not in huellas, huellas)

# 6. el paquete de carga con el archivo real (solo para medir)
if os.path.exists(CARGA_REAL):
    rehacer('con_5d')
    p = subprocess.run([PSQL, '-d', BASE, '-X', '-v', 'ON_ERROR_STOP=1', '-v', 'solicitante=carga.local@emdupar.gov.co', '-f', CARGA_REAL], env=ENV, capture_output=True, text=True,
                       cwd=os.path.dirname(CARGA_REAL))
    pasos = re.findall(r'^\s*(subir \d+ lotes|resumen|publicar|capa del geovisor, 12 meses)\s*\|\s*(\d+)', p.stdout, re.M)
    info = re.search(r'INFO ubicación[^\n]*', p.stdout)
    ok(f'21 el ENSAYO de la carga inicial con el archivo real: 7 de 7 SIN FALLAS ({", ".join(f"{a} {b} ms" for a, b in pasos)}; {info.group(0) if info else ""}; en local el catastro es sintético)',
       re.search(r'7 de 7 comprobaciones correctas — SIN FALLAS', p.stderr), p.stderr[-600:])
rehacer()
bien = sum(1 for r in res if r[1])
print('----')
print('TIEMPOS DEL ENSAYO: ' + tiempos_ensayo)
print(f'RESULTADO: {bien} de {len(res)} — ' + ('SIN FALLAS' if bien == len(res) else f'{len(res) - bien} FALLA(S)'))
