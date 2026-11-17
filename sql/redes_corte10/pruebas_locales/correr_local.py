#!/usr/bin/env python3
"""Arnés local del Corte 10 (Code B, clúster propio 55442; nunca el 55432 de Code A). Comprueba, sobre una base como producción (con los CHECK de producción
en los dobles: reglas_produccion.sql):
  · el ensayo (N de N … SIN FALLAS), la migración, la verificación (todas OK), que no se aplica dos veces y la reversa (vuelve la huella del 5d);
  · public.predios_comercial es VISTA MATERIALIZADA, como en producción, y ningún archivo del paquete la escribe ni la refresca;
  · el paquete de carga (la valoración real y los amarres): su ensayo (N de N … SIN FALLAS y no deja nada), la carga, su verificación y que no se carga dos veces;
  · como las ve producción: la conciliación, la ficha y las teselas por las RPC, una llamada por petición, con el rol de la API (service_role),
    statement_timeout 30 s y lock_timeout 8 s; FALLA si alguna pasa de 5 s; quién ve qué (administrador, supervisor de distribución y operador);
  · el parámetro de la hoja vigente; la reversa se niega con la valoración cargada; pg-safeupdate.
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
MD5_5D = '5fd6d00efdaa1a798e2628a2cde23c61'
GEN = os.path.join(RAIZ, 'carga_val', 'generado')
ADM, SD, OP = 'carga.local@emdupar.gov.co', 'zt10.arnes.dist@emdupar.gov.co', 'zt10.arnes.op@emdupar.gov.co'
res = []


def ok(nombre, cond, det=''):
    res.append((nombre, bool(cond), str(det)[:500]))
    print(('OK    ' if cond else 'FALLA ') + nombre + ('' if cond else ' → ' + str(det)[:500]), flush=True)


def psql(*args, base=BASE, check=False, cwd=None):
    return subprocess.run([PSQL, '-d', base, '-X', *args], env=ENV, capture_output=True, text=True, check=check, cwd=cwd)


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
p = psql('-q', '-f', os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte10_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — SIN FALLAS', p.stderr)
tiempos_ensayo = (re.search(r'TIEMPOS[^\n]*', p.stderr) or [''])[0]
ok(f'01 el ensayo termina en el ERROR esperado: {m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS', m and m.group(1) == m.group(2) and 'esperado' in p.stderr, p.stderr[-800:])
ok('02 … y no deja nada (sigue la huella del 5d y no hay tablas de la valoración)', q(CONJ) == MD5_5D and q("select to_regclass('redes.val_filas')") == '')
ok('03 la base local tiene los CHECK de producción en los dobles (lista blanca, auditoría y personal de Técnica)',
   q("select count(*) from pg_constraint where conname in ('geoportal_lista_blanca_rol_check', 'geoportal_auditoria_email_nn', 'personal_tecnico_eventos_check1')") == '3')

# 2. la vista materializada de Comercial
ok('04 public.predios_comercial es vista materializada, como en producción', q("select relkind from pg_class where oid = 'public.predios_comercial'::regclass") == 'm')
sqls = [os.path.join(d, f) for d, _, fs in os.walk(RAIZ) for f in fs if f.endswith('.sql')]
ok('05 ningún archivo del paquete (ni de la carga) escribe ni refresca predios_comercial',
   not any(re.search(r'(insert\s+into|update|delete\s+from|refresh\s+materialized\s+view)\s+(public\.)?predios_comercial', open(f, encoding='utf-8').read(), re.I) for f in sqls))

# 3. migración, verificación, segunda vez
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte10_editor.sql'))
ok('06 la migración se aplica', p.returncode == 0, p.stderr)
filas = psql('-AtF', '|', '-f', os.path.join(RAIZ, 'verificacion_redes_corte10_editor.sql')).stdout.strip().splitlines()
ok(f'07 la verificación: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte10_editor.sql'))
ok('08 una segunda migración se niega', p.returncode != 0 and 'ya está aplicado' in p.stderr, p.stderr)
ok('09 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SD}', 'ZT10 arnés supervisor', 'consulta', true, true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'ZT10 arnés operador', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('{OP}', 'asignar_formulario', 'danos_fallas', '{ADM}')")
cod = 'RED-000435'      # un tramo en operación que el análisis dejó «con fila» (el mismo que usa la carga en su comprobación 11)
ms, out, e = edge(f"select public.geoportal_redes_valoracion('{ADM}')")
ok('10 antes de cargar: la conciliación dice «sin cargar» y la ficha no trae la sección', not e and json.loads(out)['cargada'] is False
   and 'regulatorio' not in json.loads(edge(f"select public.geoportal_redes_activo('{ADM}', '{cod}')")[1]), e)

# 4. el paquete de carga: ensayo, carga, verificación, segunda vez
p = psql('-v', f'solicitante={ADM}', '-f', 'ensayo_carga_valoracion.sql', cwd=GEN)
m = re.search(r'RESULTADO: (\d+) de (\d+) comprobaciones correctas — SIN FALLAS', p.stderr)
ok(f'11 el ENSAYO de la carga (la valoración real y los amarres): {m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS', m and m.group(1) == m.group(2) and 'ENSAYO' in p.stderr, p.stderr[-900:])
ok('12 … y no deja nada cargado', q("select count(*) from redes.val_filas") == '0' and q("select count(*) from redes.ref_cargas where conjunto in ('valoracion', 'val_amarre')") == '0')
p = psql('-v', 'ON_ERROR_STOP=1', '-v', f'solicitante={SD}', '-f', 'carga_valoracion.sql', cwd=GEN)
ok('13 la carga se niega a quien no es administrador', 'no es de un administrador' in p.stdout and q("select count(*) from redes.val_filas") == '0', p.stdout[-300:] + p.stderr[-300:])
t0 = time.time()
p = subprocess.run([PSQL, '-d', BASE, '-X', '-v', 'ON_ERROR_STOP=1', '-v', f'solicitante={ADM}', '-f', 'carga_valoracion.sql'], env=dict(ENV, PGOPTIONS=''), capture_output=True, text=True, cwd=GEN)      # con los avisos, como los verá David
ms_carga = round((time.time() - t0) * 1000)
m = re.search(r'(\d+) de (\d+) comprobaciones correctas — SIN FALLAS', p.stderr)
tiempos_carga = (re.search(r'TIEMPOS[^\n]*', p.stderr) or [''])[0]
ok(f'14 la carga real: {m.group(1) if m else "?"} de {m.group(2) if m else "?"} comprobaciones, SIN FALLAS ({ms_carga} ms en total)', p.returncode == 0 and m and m.group(1) == m.group(2), p.stderr[-900:])
filas = psql('-AtF', '|', '-f', 'verificacion_carga_valoracion.sql', cwd=GEN).stdout.strip().splitlines()
ok(f'15 la verificación de la carga: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
p = psql('-v', 'ON_ERROR_STOP=1', '-v', f'solicitante={ADM}', '-f', 'carga_valoracion.sql', cwd=GEN)
ok('16 una segunda carga del mismo archivo se niega (no duplica)', 'ya está cargada' in p.stdout and q("select count(*) from redes.ref_cargas where conjunto = 'valoracion'") == '1', p.stdout[-300:])
ok('17 ningún activo cambió de versión ni tuvo eventos por la carga (la ficha oficial no se toca)',
   q("select count(*) from redes.activo_versiones v where v.creado_en >= (select min(creado_en) from redes.ref_cargas where conjunto = 'valoracion')") == '0')

# 5. como las ve producción
ms_c, out, e = edge(f"select public.geoportal_redes_valoracion('{ADM}')")
c = json.loads(out) if not e else {}
tub = [f for f in c.get('filas', []) if f['clase'] == 'tuberia']
calza = {h: (sum(1 for f in tub if f['hoja'] == h and f.get('calza')), sum(1 for f in tub if f['hoja'] == h)) for h in ('acueducto', 'alcantarillado', 'alcantarillado_2')}
bcr = {h['hoja']: round(h['bcr0'] / 1e6) for h in c.get('hojas', [])}
ok(f'18 la conciliación como la Edge ({ms_c} ms, {len(out) // 1024} kB): 166 filas; BCR0 {bcr}; tuberías que calzan {calza}', not e and ms_c < 5000 and len(c['filas']) == 166
   and bcr == {'acueducto': 101061, 'alcantarillado': 138548, 'alcantarillado_2': 176452} and c['hoja_alcantarillado'] == 'alcantarillado_2', e)
ok('19 la conciliación solo la ve el administrador (supervisor y operador: 42501)',
   'Solo el administrador' in edge(f"select public.geoportal_redes_valoracion('{SD}')")[2] and edge(f"select public.geoportal_redes_valoracion('{OP}')")[2] != '')
ms_f, out, e = edge(f"select public.geoportal_redes_activo('{ADM}', '{cod}')")
f = json.loads(out).get('regulatorio', {}) if not e else {}
ok(f'20 la ficha de {cod} como la Edge ({ms_f} ms): remunerado, fila «{(f.get("filas") or [{}])[0].get("nombre")} {(f.get("filas") or [{}])[0].get("caracteristica")}», valoración «propuesta»',
   not e and ms_f < 5000 and f.get('remunerado') is True and 'propuesta' in f.get('fuente', '') and f['filas'][0].get('vida_remanente_hoy') is not None, e or f)
out_sd = edge(f"select public.geoportal_redes_activo('{SD}', '{cod}')")[1]
out_op = edge(f"select public.geoportal_redes_activo('{OP}', '{cod}')")[1]
ok('21 el supervisor de distribución ve la sección; el operador no recibe nada de ella (sin términos tarifarios)',
   'regulatorio' in json.loads(out_sd) and 'regulatorio' not in json.loads(out_op) and not re.search(r'remunerad|valoraci|depreciaci|tarif|regulator', out_op, re.I))
for letra, nombre, sql_cod in (('a', 'un tramo proyectado', "am.situacion = 'proyectado'"), ('b', 'un tramo sin fila', "am.situacion = 'sin_fila' and a.prefijo = 'RED'"),
                               ('c', 'un tramo de obra SIVA (con fila, marcado aparte)', "am.situacion = 'aparte_siva'"), ('d', 'un tramo fuera de servicio (con fila, marcado aparte)', "am.situacion = 'aparte_fuera_servicio'")):
    c2 = q(f"select a.codigo from redes.val_amarre am join redes.activos a on a.id = am.activo_id where am.hoja = 'acueducto' and {sql_cod} order by a.id limit 1")
    f2 = json.loads(edge(f"select public.geoportal_redes_activo('{ADM}', '{c2}')")[1]).get('regulatorio', {})
    ok(f'22{letra} {nombre} ({c2}): no remunerado, «{f2.get("texto", "")[:60]}…»', f2.get('remunerado') is False and f2.get('texto'), f2)
popa = q("select codigo from redes.activo_vigente_mat where prefijo = 'TAN' and lower(nombre) like '%la popa%'")
pta = json.loads(edge(f"select public.geoportal_redes_activo('{ADM}', 'PTA-000001')")[1]).get('regulatorio', {})
ok('23 la planta trae sus dos filas (Huaricha y Gota Fría) y La Popa la suya', [x['nombre'] for x in pta.get('filas', [])] == ['PLANTA HUARICHA', 'PLANTA GOTA FRÍA']
   and json.loads(edge(f"select public.geoportal_redes_activo('{ADM}', '{popa}')")[1])['regulatorio']['filas'][0]['nombre'] == 'TANQUE LA POPA', pta)
z = int(float(q("select redes.f_param('geovisor_zoom_red_completa')")))
x, y = q(f"""select t.x || ',' || t.y from (select floor((ST_X(ST_PointOnSurface(m.geom)) + 180) / 360 * (1 << {z}))::integer as x,
  floor((1 - ln(tan(radians(ST_Y(ST_PointOnSurface(m.geom)))) + 1 / cos(radians(ST_Y(ST_PointOnSurface(m.geom))))) / pi()) / 2 * (1 << {z}))::integer as y
  from redes.activo_vigente_mat m where m.prefijo in ('RED', 'COL') and not m.retirado) t group by t.x, t.y order by count(*) desc limit 1""").split(',')
peor, tam = 0, 0
errores = []
for zz, xx, yy in [(z, int(x), int(y)), (z, int(x) + 1, int(y)), (z, int(x), int(y) + 1), (z - 1, int(x) // 2, int(y) // 2), (z + 2, int(x) * 4, int(y) * 4), (z + 3, int(x) * 8 + 3, int(y) * 8 + 3)]:
    ms, out, e = edge(f"select public.geoportal_redes_geovisor_mvt('{ADM}', {zz}, {xx}, {yy})")
    peor, tam = max(peor, ms), max(tam, len(out))
    if e:
        errores.append(e)
ok(f'24 seis teselas del geovisor alrededor de la más cargada ({z}/{x}/{y}) como la Edge: la más lenta {peor} ms, la mayor {tam * 3 // 4 // 1024} kB; menos de 5 s', not errores and peor < 5000, errores[:1])
q(f"select public.geoportal_redes_personal_fijar('{SD}', '{OP}', 'geovisor', 'si', 'ZT10 arnés: el operador con el geovisor')")
t_adm = edge(f"select public.geoportal_redes_geovisor_mvt('{ADM}', {z}, {x}, {y})")[1]
t_op = edge(f"select public.geoportal_redes_geovisor_mvt('{OP}', {z}, {x}, {y})")[1]
ok(f'25 la misma tesela: la del administrador trae la edad regulatoria ({len(t_adm)} caracteres) y la del operador no ({len(t_op)})', len(t_adm) > len(t_op) > 0)
ok('26 con la carga hecha, las teselas subieron de versión (el navegador las pide de nuevo)', int(q('select sum(version) from redes.tesela_version')) >= 2)

# 6. la hoja vigente (parámetro)
col = q("select a.codigo from redes.val_amarre am join redes.activos a on a.id = am.activo_id where am.hoja = 'alcantarillado' and am.n is not null order by a.id limit 1")
h2 = json.loads(edge(f"select public.geoportal_redes_activo('{ADM}', '{col}')")[1])['regulatorio']['filas'][0]['hoja']
ms, out, e = edge(f"select public.geoportal_redes_parametro_fijar('{ADM}', 'valoracion_hoja_alcantarillado', 1, 'ZT10 arnés: prueba de la otra hoja')")
h1 = json.loads(edge(f"select public.geoportal_redes_activo('{ADM}', '{col}')")[1])['regulatorio']['filas'][0]['hoja']
c1 = json.loads(edge(f"select public.geoportal_redes_valoracion('{ADM}')")[1])
ok(f'27 al cambiar el parámetro, vale la otra hoja sin recargar nada: {col} pasa de «{h2}» a «{h1}»', not e and (h2, h1) == ('ALCANTARILLADO (2)', 'ALCANTARILLADO') and c1['hoja_alcantarillado'] == 'alcantarillado', e)
edge(f"select public.geoportal_redes_parametro_fijar('{ADM}', 'valoracion_hoja_alcantarillado', 2, 'ZT10 arnés: vuelve a la hoja (2)')")

# 7. la reversa
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'reversa_redes_corte10_editor.sql'))
ok('28 la reversa se niega con la valoración cargada (no borra datos)', p.returncode != 0 and 'ya está cargada' in p.stderr, p.stderr)
rehacer('con_10')
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'reversa_redes_corte10_editor.sql'))
ok('29 sin cargar, la reversa deja la huella del 5d y quita las tablas', p.returncode == 0 and q(CONJ) == MD5_5D and q("select to_regclass('redes.val_filas')") == '', p.stderr)
huellas = psql('-AtF', '|', '-f', os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte10_editor.sql')).stdout
ok('30 las huellas después de la reversa dicen «listo para el 10» y nada «DISTINTA»', 'CORTE 5d (listo para el 10)' in huellas and 'DISTINTA' not in huellas and 'NO EXISTEN' in huellas, huellas)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte10_editor.sql'))
ok('31 y se puede migrar de nuevo después de la reversa (los parámetros vuelven a quedar vigentes)', p.returncode == 0
   and q("select count(*) from redes.parametros where clave like 'valoracion\\_%' and descripcion not like 'Sin uso%'") == '2', p.stderr)
rehacer()
bien = sum(1 for r in res if r[1])
print('----')
print('TIEMPOS DEL ENSAYO SQL: ' + tiempos_ensayo)
print('TIEMPOS DE LA CARGA: ' + tiempos_carga)
print(f'RESULTADO: {bien} de {len(res)} — ' + ('SIN FALLAS' if bien == len(res) else f'{len(res) - bien} FALLA(S)'))
